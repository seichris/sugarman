// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import SugarmanDiagnostics

struct BTSnoopAnalyzerTests {
    @Test func summarizesSyntheticLabCaptureWithoutLeakingSecrets() throws {
        let data = SyntheticBTSnoop.labCapture(
            includePeerInManufacturerData: true,
            includeSixByteSerial: true
        )
        let summary = try BTSnoopAnalyzer.summarize(data: data)
        #expect(summary.schemaVersion == 1)
        #expect(summary.leAdvertisementCount == 1)
        #expect(summary.connectionEventCount == 1)
        #expect(summary.attPduCount >= 4)
        #expect(summary.advertisedNames == ["redacted-name(len:12)"])
        #expect(summary.advertisedServiceUUIDs.contains("180A"))
        #expect(summary.manufacturerDataLengths.contains(4))
        #expect(summary.hciPeerAddressFieldObserved)
        #expect(summary.sixByteFieldInAdvertisementPayload)
        #expect(summary.sixByteAddressSource == .advertisement)
        #expect(summary.cipherHypothesis == .unknownUntilCapture)
        #expect(summary.refusedGlucoseDecode)
        #expect(summary.attOperations.contains { $0.opcodeName == "writeRequest" })
        let write = summary.attOperations.first { $0.opcodeName == "writeRequest" }
        #expect(write?.valueByteCount == SyntheticBTSnoop.writePayload.count)

        let described = String(describing: summary)
        let json = String(decoding: try BTSnoopAnalyzer.jsonData(from: summary), as: UTF8.self)
        for blob in [described, json] {
            #expect(!blob.contains("01:23:45:67:89:AB"))
            #expect(!blob.contains("0123456789AB"))
            #expect(!blob.contains("C0FFEE"))
            #expect(!blob.contains("RC4"))
            #expect(!blob.contains("AES"))
            #expect(!blob.contains("\u{01}#Eg\u{89}\u{AB}"))
        }
    }

    @Test func arbitrarySixByteSerialIsNotAddressEvidence() throws {
        let data = SyntheticBTSnoop.labCapture(
            includePeerInManufacturerData: false,
            includeSixByteSerial: true,
            serialPayload: Array("ABCDEF".utf8)
        )
        let summary = try BTSnoopAnalyzer.summarize(data: data)
        #expect(!summary.sixByteFieldInDeviceInformationRead)
        #expect(summary.sixByteAddressSource == .notFound)
    }

    @Test func deviceInformationSourceWhenOnlySerialIsSixBytes() throws {
        let data = SyntheticBTSnoop.labCapture(
            includePeerInManufacturerData: false,
            includeSixByteSerial: true
        )
        let summary = try BTSnoopAnalyzer.summarize(data: data)
        #expect(summary.sixByteFieldInAdvertisementPayload == false)
        #expect(summary.sixByteAddressSource == .deviceInformation)
        #expect(summary.cipherHypothesis == .unknownUntilCapture)
    }

    @Test func notFoundWhenSixBytesAreOnlyInHCIPeerField() throws {
        let data = SyntheticBTSnoop.labCapture(
            includePeerInManufacturerData: false,
            includeSixByteSerial: false
        )
        let summary = try BTSnoopAnalyzer.summarize(data: data)
        #expect(summary.hciPeerAddressFieldObserved)
        #expect(summary.sixByteAddressSource == .notFound)
        #expect(summary.notes.contains {
            $0.contains("not an iOS-accessible source")
        })
    }

    @Test func refusesGlucoseDecode() {
        #expect(throws: GlucoseDecodeRefusal.refusedUntilPhysicalParity) {
            try BTSnoopAnalyzer.decodeGlucose(Data([0x01, 0x02, 0x03]))
        }
    }

    @Test func rejectsInvalidMagic() {
        #expect(throws: BTSnoopError.invalidMagic) {
            try BTSnoopAnalyzer.summarize(data: Data("not-btsnoop-header!".utf8))
        }
        #expect(throws: BTSnoopError.truncated) {
            try BTSnoopAnalyzer.summarize(data: Data("short".utf8))
        }
    }

    @Test func rejectsUnsupportedVersionDatalinkAndTrailingTruncation() {
        var unsupportedVersion = SyntheticBTSnoop.labCapture(
            includePeerInManufacturerData: false,
            includeSixByteSerial: false
        )
        unsupportedVersion.replaceSubrange(8..<12, with: [0x00, 0x00, 0x00, 0x02])
        #expect(throws: BTSnoopError.unsupportedVersion(2)) {
            try BTSnoopAnalyzer.summarize(data: unsupportedVersion)
        }

        var unsupported = SyntheticBTSnoop.labCapture(
            includePeerInManufacturerData: false,
            includeSixByteSerial: false
        )
        unsupported.replaceSubrange(12..<16, with: [0x00, 0x00, 0x03, 0xE9])
        #expect(throws: BTSnoopError.unsupportedDatalink(1001)) {
            try BTSnoopAnalyzer.summarize(data: unsupported)
        }

        var trailing = SyntheticBTSnoop.labCapture(
            includePeerInManufacturerData: false,
            includeSixByteSerial: false
        )
        trailing.append(0x00)
        #expect(throws: BTSnoopError.truncated) {
            try BTSnoopAnalyzer.summarize(data: trailing)
        }
    }

    @Test func sixByteAddressSourceCasesExistForP1() {
        #expect(SixByteAddressSource.allCases.contains(.package))
        #expect(SixByteAddressSource.allCases.contains(.nfc))
        #expect(SixByteAddressSource.allCases.contains(.advertisement))
        #expect(SixByteAddressSource.allCases.contains(.deviceInformation))
        #expect(SixByteAddressSource.allCases.contains(.otherReadable))
        #expect(SixByteAddressSource.allCases.contains(.notFound))
        #expect(CipherHypothesis.allCases == [.unknownUntilCapture])
    }
}
