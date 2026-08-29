// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct PackageParseResult: Sendable, Equatable {
    public var productName: String?
    public var gtin: String?
    public var sku: String?
    public var redactedSerial: String
    public var regionHypothesis: String
    public var protocolHypothesis: ProtocolVariant
    public var confidence: EvidenceConfidence
    public var formatName: String
    public var isSynthetic: Bool

    public init(
        productName: String? = nil,
        gtin: String? = nil,
        sku: String? = nil,
        redactedSerial: String,
        regionHypothesis: String,
        protocolHypothesis: ProtocolVariant,
        confidence: EvidenceConfidence,
        formatName: String,
        isSynthetic: Bool
    ) {
        self.productName = productName
        self.gtin = gtin
        self.sku = sku
        self.redactedSerial = redactedSerial
        self.regionHypothesis = regionHypothesis
        self.protocolHypothesis = protocolHypothesis
        self.confidence = confidence
        self.formatName = formatName
        self.isSynthetic = isSynthetic
    }
}

public protocol PackageParsing: Sendable {
    func parse(_ payload: String) throws -> PackageParseResult
}

/// Bounded package parser. Does not send sensor commands and does not copy
/// offset-based upstream parsers. Unknown formats fail closed.
///
/// Default limit is 4 KiB. Truncated, oversized, empty, NUL, and unknown
/// payloads are rejected. Independently observed GS1/UDI-like strings
/// (`(01)GTIN(21)serial` or concatenated AI 01/17/10/21) are accepted as
/// synthetic identity, not hardware proof.
public struct BoundedPackageParser: PackageParsing {
    public static let defaultMaximumUTF8Bytes = 4096
    public var maximumUTF8Bytes: Int

    public init(maximumUTF8Bytes: Int = BoundedPackageParser.defaultMaximumUTF8Bytes) {
        self.maximumUTF8Bytes = maximumUTF8Bytes
    }

    public func parse(_ payload: String) throws -> PackageParseResult {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw OnboardingError.emptyPayload
        }
        let byteCount = trimmed.utf8.count
        if byteCount > maximumUTF8Bytes {
            throw OnboardingError.payloadTooLarge
        }
        if trimmed.contains("\0") {
            throw OnboardingError.unsupportedFormat(reason: "NUL bytes are not allowed")
        }
        if trimmed.hasPrefix("SUGARMAN-FIXTURE/") {
            return try parseLegacyFixture(trimmed)
        }
        if trimmed.hasPrefix("SUGARMAN-SYNTHETIC") && !trimmed.hasPrefix("SUGARMAN-SYNTHETIC-NDEF") {
            return try parseSynthetic(trimmed)
        }
        if let gs1 = GS1ElementString.parse(trimmed) {
            return parseGS1(gs1)
        }
        if looksLikeTruncatedGS1(trimmed) {
            throw OnboardingError.unsupportedFormat(reason: "truncated GS1/UDI payload")
        }
        throw OnboardingError.unsupportedFormat(
            reason: "no supported Data Matrix profile; hardware fixtures are required"
        )
    }

    private func looksLikeTruncatedGS1(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("(01)") { return true }
        if trimmed.hasPrefix("01"), trimmed.count < 18 { return true }
        if trimmed.contains("(21)") && !trimmed.contains("(01)") { return true }
        return false
    }

    private func parseGS1(_ gs1: GS1ElementString) -> PackageParseResult {
        PackageParseResult(
            productName: "GS1 UDI (synthetic parse)",
            gtin: gs1.gtin,
            sku: nil,
            redactedSerial: SerialRedaction.redact(gs1.serial),
            regionHypothesis: "Independently observed GS1/UDI layout; synthetic parse, not hardware proof",
            protocolHypothesis: .unknown,
            confidence: .low,
            formatName: "gs1-udi-synthetic",
            isSynthetic: true
        )
    }

    private func parseLegacyFixture(_ trimmed: String) throws -> PackageParseResult {
        let body = String(trimmed.dropFirst("SUGARMAN-FIXTURE/".count))
        let parts = body.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw OnboardingError.unsupportedFormat(reason: "truncated SUGARMAN-FIXTURE payload")
        }
        return PackageParseResult(
            productName: nil,
            gtin: String(parts[0]),
            sku: nil,
            redactedSerial: SerialRedaction.redact(String(parts[1])),
            regionHypothesis: "synthetic fixture; not hardware proof",
            protocolHypothesis: .unknown,
            confidence: .low,
            formatName: "sugarman-sanitized-fixture",
            isSynthetic: true
        )
    }

    private func parseSynthetic(_ trimmed: String) throws -> PackageParseResult {
        let body: String
        if trimmed.hasPrefix("SUGARMAN-SYNTHETIC/") {
            body = String(trimmed.dropFirst("SUGARMAN-SYNTHETIC/".count))
        } else if trimmed.hasPrefix("SUGARMAN-SYNTHETIC") {
            body = String(trimmed.dropFirst("SUGARMAN-SYNTHETIC".count))
        } else {
            throw OnboardingError.unsupportedFormat(reason: "truncated synthetic package payload")
        }
        let fields = SyntheticFieldParser.fields(in: body)
        guard let serial = fields["serial"], !serial.isEmpty else {
            throw OnboardingError.unsupportedFormat(reason: "synthetic package payload missing serial")
        }
        let sku = fields["sku"]
        let productFromSKU = sku.flatMap { DocumentedSKUClassification.productName(for: $0) }
        let region = sku.map { DocumentedSKUClassification.regionHypothesis(for: $0) }
            ?? "Unknown region (synthetic parse; not hardware proof)"
        return PackageParseResult(
            productName: fields["product"] ?? productFromSKU ?? "Synthetic demo sensor",
            gtin: fields["gtin"],
            sku: sku,
            redactedSerial: SerialRedaction.redact(serial),
            regionHypothesis: region,
            protocolHypothesis: .unknown,
            confidence: .unsupported,
            formatName: "synthetic-demo",
            isSynthetic: true
        )
    }
}

enum SyntheticFieldParser {
    static func fields(in body: String) -> [String: String] {
        var result: [String: String] = [:]
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ";/"))
        for token in body.components(separatedBy: separators) where !token.isEmpty {
            let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }
}
