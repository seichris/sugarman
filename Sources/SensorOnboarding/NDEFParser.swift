// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct NDEFParseResult: Sendable, Equatable {
    public var textRecords: [String]
    public var redactedSerial: String?
    public var protocolHypothesis: ProtocolVariant
    public var confidence: EvidenceConfidence
}

public protocol NDEFParsing: Sendable {
    func parseTextRecords(_ records: [String]) throws -> NDEFParseResult
}

/// Bounded NDEF text parser. No sensor side effects. Unknown records fail closed.
public struct BoundedNDEFParser: NDEFParsing {
    public var maximumRecords: Int
    public var maximumRecordBytes: Int

    public init(maximumRecords: Int = 8, maximumRecordBytes: Int = 256) {
        self.maximumRecords = maximumRecords
        self.maximumRecordBytes = maximumRecordBytes
    }

    public func parseTextRecords(_ records: [String]) throws -> NDEFParseResult {
        if records.isEmpty {
            throw OnboardingError.emptyPayload
        }
        if records.count > maximumRecords {
            throw OnboardingError.payloadTooLarge
        }
        for record in records {
            if record.utf8.count > maximumRecordBytes {
                throw OnboardingError.payloadTooLarge
            }
        }
        throw OnboardingError.unsupportedFormat(
            reason: "owned-tag NDEF layout is not yet physically validated"
        )
    }
}
