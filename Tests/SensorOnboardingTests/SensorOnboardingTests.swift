// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Testing
@testable import SensorOnboarding

struct SensorOnboardingTests {
    let parser = BoundedPackageParser(maximumUTF8Bytes: 64)

    @Test func rejectsEmptyAndOversized() {
        #expect(throws: OnboardingError.emptyPayload) {
            try parser.parse("   ")
        }
        let huge = String(repeating: "A", count: 65)
        #expect(throws: OnboardingError.payloadTooLarge) {
            try parser.parse(huge)
        }
    }

    @Test func unknownFormatFailsClosed() {
        #expect(throws: OnboardingError.unsupportedFormat(reason: "no supported Data Matrix profile; hardware fixtures are required")) {
            try parser.parse("01 06900000000000 21 ABCDEF")
        }
    }

    @Test func sanitizedFixtureParsesWithoutSideEffects() throws {
        let result = try parser.parse("SUGARMAN-FIXTURE/01234567890123/A…Z")
        #expect(result.gtin == "01234567890123")
        #expect(result.redactedSerial == "A…Z")
        #expect(result.protocolHypothesis.rawValue == "unknown")
        #expect(result.confidence == .low)
    }

    @Test func ndefUnknownFailsClosed() {
        let ndef = BoundedNDEFParser()
        #expect(throws: OnboardingError.unsupportedFormat(reason: "owned-tag NDEF layout is not yet physically validated")) {
            try ndef.parseTextRecords(["hello"])
        }
    }
}
