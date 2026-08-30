// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct NDEFParseResult: Sendable, Equatable {
    /// Parsed records suitable for presentation. Owned-hardware parsers redact
    /// unique identifiers before returning them; raw reader records must remain
    /// transient and must not be logged or persisted as diagnostic evidence.
    public var textRecords: [String]
    public var productName: String?
    public var sku: String?
    public var redactedSerial: String?
    public var regionHypothesis: String
    public var protocolHypothesis: ProtocolVariant
    public var confidence: EvidenceConfidence
    public var formatName: String
    public var isSynthetic: Bool
}

public protocol NDEFParsing: Sendable {
    func parseTextRecords(_ records: [String]) throws -> NDEFParseResult
}

/// Bounded NDEF text parser. No sensor side effects. Unknown records fail closed.
/// Oversized payloads are those above 4 KiB total UTF-8.
public struct BoundedNDEFParser: NDEFParsing {
    public static let defaultMaximumTotalBytes = 4096
    public var maximumRecords: Int
    public var maximumRecordBytes: Int
    public var maximumTotalBytes: Int

    public init(
        maximumRecords: Int = 8,
        maximumRecordBytes: Int = 4096,
        maximumTotalBytes: Int = BoundedNDEFParser.defaultMaximumTotalBytes
    ) {
        self.maximumRecords = maximumRecords
        self.maximumRecordBytes = maximumRecordBytes
        self.maximumTotalBytes = maximumTotalBytes
    }

    public func parse(_ payload: String) throws -> NDEFParseResult {
        try parseTextRecords([payload])
    }

    public func parseTextRecords(_ records: [String]) throws -> NDEFParseResult {
        if records.isEmpty {
            throw OnboardingError.emptyPayload
        }
        let trimmedRecords = records.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if trimmedRecords.allSatisfy(\.isEmpty) {
            throw OnboardingError.emptyPayload
        }
        if records.count > maximumRecords {
            throw OnboardingError.payloadTooLarge
        }
        var totalBytes = 0
        for record in records {
            if record.contains("\0") {
                throw OnboardingError.unsupportedFormat(reason: "NUL bytes are not allowed")
            }
            let count = record.utf8.count
            if count > maximumRecordBytes {
                throw OnboardingError.payloadTooLarge
            }
            totalBytes += count
        }
        if totalBytes > maximumTotalBytes {
            throw OnboardingError.payloadTooLarge
        }

        let nonEmptyRecords = trimmedRecords.filter { !$0.isEmpty }
        let observedGS3Records = nonEmptyRecords.filter { $0.hasPrefix("GJ,") }
        if !observedGS3Records.isEmpty {
            guard nonEmptyRecords.count == 1, observedGS3Records.count == 1 else {
                throw OnboardingError.unsupportedFormat(
                    reason: "ambiguous GS3 NDEF message; expected one text record"
                )
            }
            return try parseObservedGS3(observedGS3Records[0])
        }

        if let synthetic = trimmedRecords.first(where: { $0.hasPrefix("SUGARMAN-SYNTHETIC-NDEF") }) {
            return try parseSynthetic(synthetic, allRecords: trimmedRecords)
        }

        throw OnboardingError.unsupportedFormat(
            reason: "no supported owned-tag NDEF profile"
        )
    }

    /// Parses the exact four-field text layout observed on one owned, active
    /// Mainland China GS3. The six-character link identifier is validated only
    /// as an input-shape gate; it is deliberately not returned or persisted.
    private func parseObservedGS3(_ payload: String) throws -> NDEFParseResult {
        let fields = payload.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 4, fields[0] == "GJ" else {
            throw malformedObservedGS3()
        }

        let serial = String(fields[1])
        let declaredLinkLength = String(fields[2])
        let linkIdentifier = String(fields[3])
        guard serial.utf8.count == 15,
              isUppercaseASCIIAlphaNumeric(serial),
              declaredLinkLength == "6",
              linkIdentifier.utf8.count == 6,
              isUppercaseASCIIAlphaNumeric(linkIdentifier) else {
            throw malformedObservedGS3()
        }

        let redactedSerial = SerialRedaction.redact(serial)
        return NDEFParseResult(
            textRecords: ["GJ,\(redactedSerial),6,…"],
            productName: "GS3",
            sku: nil,
            redactedSerial: redactedSerial,
            regionHypothesis: "Mainland China test context (region is not encoded by the observed NDEF record)",
            protocolHypothesis: .unknown,
            confidence: .high,
            formatName: "sibionics-gs3-gj-ndef-v1",
            isSynthetic: false
        )
    }

    private func isUppercaseASCIIAlphaNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte)
        }
    }

    private func malformedObservedGS3() -> OnboardingError {
        .unsupportedFormat(
            reason: "malformed GS3 GJ NDEF record; expected four bounded ASCII fields"
        )
    }

    private func parseSynthetic(_ payload: String, allRecords: [String]) throws -> NDEFParseResult {
        let body = String(payload.dropFirst("SUGARMAN-SYNTHETIC-NDEF".count))
        let fields = SyntheticFieldParser.fields(in: body)
        guard let serial = fields["serial"], !serial.isEmpty else {
            throw OnboardingError.unsupportedFormat(reason: "truncated synthetic NDEF payload")
        }
        let sku = fields["sku"]
        let productFromSKU = sku.flatMap { DocumentedSKUClassification.productName(for: $0) }
        let region = sku.map { DocumentedSKUClassification.regionHypothesis(for: $0) }
            ?? "Unknown region (synthetic parse; not hardware proof)"
        return NDEFParseResult(
            textRecords: allRecords.filter { !$0.isEmpty },
            productName: fields["product"] ?? productFromSKU ?? "Synthetic demo sensor",
            sku: sku,
            redactedSerial: SerialRedaction.redact(serial),
            regionHypothesis: region,
            protocolHypothesis: .unknown,
            confidence: .unsupported,
            formatName: "synthetic-demo-ndef",
            isSynthetic: true
        )
    }
}
