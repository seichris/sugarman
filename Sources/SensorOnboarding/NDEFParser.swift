// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct NDEFParseResult: Sendable, Equatable {
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

        if let synthetic = trimmedRecords.first(where: { $0.hasPrefix("SUGARMAN-SYNTHETIC-NDEF") }) {
            return try parseSynthetic(synthetic, allRecords: trimmedRecords)
        }

        throw OnboardingError.unsupportedFormat(
            reason: "owned-tag NDEF layout is not yet physically validated"
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
