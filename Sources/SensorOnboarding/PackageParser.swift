// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct PackageParseResult: Sendable, Equatable {
    public var gtin: String?
    public var sku: String?
    public var redactedSerial: String
    public var protocolHypothesis: ProtocolVariant
    public var confidence: EvidenceConfidence
    public var formatName: String
}

public protocol PackageParsing: Sendable {
    func parse(_ payload: String) throws -> PackageParseResult
}

/// Bounded package parser. Does not send sensor commands and does not copy
/// offset-based upstream parsers. Unknown formats fail closed.
public struct BoundedPackageParser: PackageParsing {
    public var maximumUTF8Bytes: Int

    public init(maximumUTF8Bytes: Int = 512) {
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
            throw OnboardingError.invalidEncoding
        }
        // Independently defined sanitized fixture prefix. Not an upstream SKU table.
        if trimmed.hasPrefix("SUGARMAN-FIXTURE/") {
            let body = String(trimmed.dropFirst("SUGARMAN-FIXTURE/".count))
            let parts = body.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw OnboardingError.unsupportedFormat(reason: "fixture must be SUGARMAN-FIXTURE/gtin/redactedSerial")
            }
            return PackageParseResult(
                gtin: String(parts[0]),
                sku: nil,
                redactedSerial: String(parts[1]),
                protocolHypothesis: .unknown,
                confidence: .low,
                formatName: "sugarman-sanitized-fixture"
            )
        }
        throw OnboardingError.unsupportedFormat(
            reason: "no supported Data Matrix profile; hardware fixtures are required"
        )
    }
}
