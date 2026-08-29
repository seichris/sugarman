// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import SensorOnboarding

struct SensorOnboardingTests {
    let parser = BoundedPackageParser(maximumUTF8Bytes: 64)
    let defaultParser = BoundedPackageParser()

    @Test func rejectsEmptyAndOversized() {
        #expect(throws: OnboardingError.emptyPayload) {
            try parser.parse("   ")
        }
        let huge = String(repeating: "A", count: 65)
        #expect(throws: OnboardingError.payloadTooLarge) {
            try parser.parse(huge)
        }
    }

    @Test func defaultParserRejectsMoreThan4KiB() {
        let oversized = "SUGARMAN-SYNTHETIC sku=64221 serial=" + String(repeating: "X", count: 5000)
        #expect(throws: OnboardingError.payloadTooLarge) {
            try defaultParser.parse(oversized)
        }
        #expect(throws: OnboardingError.emptyPayload) {
            try defaultParser.parse("")
        }
    }

    @Test func rejectsNULAndGarbageAndTruncated() {
        #expect(throws: OnboardingError.unsupportedFormat(reason: "NUL bytes are not allowed")) {
            try parser.parse("SUGARMAN-SYNTHETIC\0sku=64221 serial=ABCD")
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "no supported Data Matrix profile; hardware fixtures are required")) {
            try parser.parse("01 06900000000000 21 ABCDEF")
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "synthetic package payload missing serial")) {
            try defaultParser.parse("SUGARMAN-SYNTHETIC sku=64221")
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "truncated SUGARMAN-FIXTURE payload")) {
            try parser.parse("SUGARMAN-FIXTURE/0123")
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
        #expect(result.redactedSerial == SerialRedaction.redact("A…Z"))
        #expect(result.protocolHypothesis.rawValue == "unknown")
        #expect(result.confidence == .low)
        #expect(result.isSynthetic)
    }

    @Test func fixturePayloadDoesNotEchoFullSerial() throws {
        let fullSerial = "FULLSERIAL9999"
        let result = try defaultParser.parse("SUGARMAN-FIXTURE/01234567890123/\(fullSerial)")
        #expect(result.redactedSerial == "…9999")
        #expect(result.redactedSerial != fullSerial)
        #expect(!result.redactedSerial.contains("FULLSERIAL"))
        #expect(result.gtin == "01234567890123")
        #expect(result.isSynthetic)
    }

    @Test func happySyntheticSKU64221() throws {
        let result = try defaultParser.parse("SUGARMAN-SYNTHETIC sku=64221 serial=SYNTHDEMO1234 gtin=00000000000000")
        #expect(result.sku == "64221")
        #expect(result.productName == "GS3")
        #expect(result.redactedSerial == "…1234")
        #expect(result.protocolHypothesis.rawValue == "unknown")
        #expect(result.confidence == .unsupported)
        #expect(result.isSynthetic)
        #expect(result.formatName == "synthetic-demo")
        #expect(result.regionHypothesis.contains("64221"))
        #expect(result.regionHypothesis.contains("not hardware proof"))
    }

    @Test func happySyntheticSKU64300() throws {
        let result = try defaultParser.parse("SUGARMAN-SYNTHETIC sku=64300 serial=SYNTHNFC9999")
        #expect(result.sku == "64300")
        #expect(result.redactedSerial == "…9999")
        #expect(result.confidence == .unsupported)
        #expect(result.protocolHypothesis.rawValue == "unknown")
        #expect(result.regionHypothesis.contains("Mainland China"))
        #expect(result.regionHypothesis.contains("not hardware proof"))
    }

    @Test func ndefUnknownFailsClosed() {
        let ndef = BoundedNDEFParser()
        #expect(throws: OnboardingError.unsupportedFormat(reason: "owned-tag NDEF layout is not yet physically validated")) {
            try ndef.parseTextRecords(["hello"])
        }
    }

    @Test func ndefSyntheticHappyPathAndRejections() throws {
        let ndef = BoundedNDEFParser()
        let result = try ndef.parse("SUGARMAN-SYNTHETIC-NDEF sku=64221 serial=NDEFSERIALABCD")
        #expect(result.sku == "64221")
        #expect(result.redactedSerial == "…ABCD")
        #expect(result.isSynthetic)
        #expect(result.confidence == .unsupported)
        #expect(result.protocolHypothesis.rawValue == "unknown")

        #expect(throws: OnboardingError.emptyPayload) {
            try ndef.parse("   ")
        }
        let huge = "SUGARMAN-SYNTHETIC-NDEF serial=" + String(repeating: "Z", count: 5000)
        #expect(throws: OnboardingError.payloadTooLarge) {
            try ndef.parse(huge)
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "NUL bytes are not allowed")) {
            try ndef.parseTextRecords(["SUGARMAN-SYNTHETIC-NDEF serial=AB\0CD"])
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "truncated synthetic NDEF payload")) {
            try ndef.parse("SUGARMAN-SYNTHETIC-NDEF sku=64300")
        }
    }

    @Test func serialRedactionShowsLastFour() {
        #expect(SerialRedaction.redact("SYNTHDEMO1234") == "…1234")
        #expect(SerialRedaction.redact("…WXYZ") == "…WXYZ")
        #expect(SerialRedaction.redact("AB") == "…AB")
    }

    @Test func gs1ParenthesizedAndConcatenatedParse() throws {
        let parenthesized = try defaultParser.parse("(01)01234567890123(21)SYNTHSERIAL99")
        #expect(parenthesized.gtin == "01234567890123")
        #expect(parenthesized.redactedSerial == "…AL99")
        #expect(parenthesized.formatName == "gs1-udi-synthetic")
        #expect(parenthesized.confidence == .low)
        #expect(parenthesized.isSynthetic)
        #expect(parenthesized.protocolHypothesis.rawValue == "unknown")
        #expect(parenthesized.regionHypothesis.contains("not hardware proof"))

        let withOptional = try defaultParser.parse("(01)01234567890123(17)251231(10)LOT42(21)SER1234")
        #expect(withOptional.gtin == "01234567890123")
        #expect(withOptional.redactedSerial == "…1234")

        let concatenated = try defaultParser.parse("010123456789012321SER1234")
        #expect(concatenated.gtin == "01234567890123")
        #expect(concatenated.redactedSerial == "…1234")

        let gs = String(GS1ElementString.groupSeparator)
        let withGS = try defaultParser.parse("010123456789012310LOT42" + gs + "21SER99ZZ")
        #expect(withGS.gtin == "01234567890123")
        #expect(withGS.redactedSerial == "…99ZZ")
    }

    @Test func gs1UnknownTruncatedEmptyNULStillFailClosed() {
        #expect(throws: OnboardingError.unsupportedFormat(reason: "no supported Data Matrix profile; hardware fixtures are required")) {
            try parser.parse("01 06900000000000 21 ABCDEF")
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "truncated GS1/UDI payload")) {
            try defaultParser.parse("(01)01234567890123")
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "truncated GS1/UDI payload")) {
            try defaultParser.parse("(01)0123")
        }
        #expect(throws: OnboardingError.emptyPayload) {
            try defaultParser.parse("")
        }
        #expect(throws: OnboardingError.unsupportedFormat(reason: "NUL bytes are not allowed")) {
            try defaultParser.parse("(01)01234567890123(21)AB\0CD")
        }
        let oversized = "(01)01234567890123(21)" + String(repeating: "X", count: 5000)
        #expect(throws: OnboardingError.payloadTooLarge) {
            try defaultParser.parse(oversized)
        }
    }

    @Test func stubScannerFeedsGS1Parser() async throws {
        let scanner = StubBarcodeImageScanner(
            payloadsToReturn: ["(01)01234567890123(21)SYNTHSERIAL99"]
        )
        let payloads = try await scanner.payloads(fromImageData: Data())
        #expect(payloads.count == 1)
        let parsed = try defaultParser.parse(payloads[0])
        #expect(parsed.gtin == "01234567890123")
        #expect(parsed.redactedSerial == "…AL99")
    }

#if canImport(Vision)
    @Test func visionScannerOnTinyPNGReturnsNoPayload() async throws {
        let scanner = VisionDataMatrixScanner()
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let payloads = try await scanner.payloads(fromImageData: png)
        #expect(payloads.isEmpty)
        await #expect(throws: OnboardingError.invalidEncoding) {
            try await scanner.payloads(fromImageData: Data([0x00, 0x01, 0x02]))
        }
    }
#endif

    @Test func ndefAndLiveCaptureAvailabilityTypesCompile() {
        _ = NDEFTagReadingAvailability.coreNFCCompiled
        _ = NDEFTagReadingAvailability.readingAvailable
        _ = LiveBarcodeCaptureAvailability.liveCaptureCompiled
#if os(iOS) && canImport(AVFoundation) && canImport(Vision)
        #expect(LiveBarcodeCaptureAvailability.liveCaptureCompiled)
        #expect(!BarcodeSymbologyPolicy.liveCapture.isEmpty)
#else
        #expect(!LiveBarcodeCaptureAvailability.liveCaptureCompiled)
#endif
#if canImport(CoreNFC)
        #expect(NDEFTagReadingAvailability.coreNFCCompiled)
#else
        #expect(!NDEFTagReadingAvailability.coreNFCCompiled)
        #expect(!NDEFTagReadingAvailability.readingAvailable)
#endif
    }
}
