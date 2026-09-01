// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import GS3Transport
@testable import SugarmanDiagnostics

struct RedactedGATTMapTests {
    @Test func jsonOmitsSerialBytesAndRawValues() throws {
        let serial = "FULLSERIAL9999"
        let peripheral = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let services = [
            GATTServiceSnapshot(
                uuid: DocumentedReadableCharacteristic.deviceInformationService,
                characteristics: [
                    GATTCharacteristicSnapshot(
                        uuid: DocumentedReadableCharacteristic.manufacturerName,
                        properties: ["read"],
                        valueByteCount: 4
                    ),
                    GATTCharacteristicSnapshot(
                        uuid: DocumentedReadableCharacteristic.serialNumber,
                        properties: ["read"],
                        valueByteCount: 6
                    ),
                    GATTCharacteristicSnapshot(
                        uuid: bluetoothUUID(0xFF32),
                        properties: ["write", "writeWithoutResponse"],
                        valueByteCount: nil
                    ),
                ]
            ),
        ]
        let map = RedactedGATTMapBuilder.make(
            peripheralID: peripheral,
            localName: "SyntheticLab",
            services: services,
            serialByteCount: 6,
            deviceInformationPresent: true
        )
        #expect(map.sixByteAddressSource == .notFound)
        #expect(map.peripheralID == "redacted-peer")
        #expect(map.localName == "redacted-name(len:12)")
        #expect(map.cipherHypothesis == .unknownUntilCapture)
        #expect(map.serialByteCount == 6)
        let data = try RedactedGATTMapBuilder.jsonData(from: map)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains(serial))
        #expect(!text.contains("FULLSERIAL"))
        #expect(!text.contains("SyntheticLab"))
        #expect(!text.contains(peripheral.uuidString))
        #expect(text.contains("2A25"))
        #expect(text.contains("serialValueOmitted"))
        #expect(text.contains("FF32") || text.contains("0000FF32"))
        #expect(!text.contains("writeValue"))
        #expect(!text.contains("RC4"))
        #expect(!text.contains("AES"))
        let described = String(describing: map)
        #expect(!described.contains(serial))

        let url = try GATTMapFileWriter().write(map, to: FileManager.default.temporaryDirectory)
        #expect(url.lastPathComponent == "sugarman-gatt-map.json")
        let roundTrip = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(!roundTrip.contains(serial))
        #expect(roundTrip.contains("unknownUntilCapture"))
    }

    @Test func sixByteLengthAloneIsNotAddressEvidence() {
        let map = RedactedGATTMapBuilder.make(
            peripheralID: UUID(),
            localName: "unique-sensor-name",
            services: [],
            serialByteCount: 6,
            deviceInformationPresent: true
        )
        #expect(map.sixByteAddressSource == .notFound)
        #expect(map.localName == "redacted-name(len:18)")
        #expect(map.notes.contains { $0.contains("not address-source evidence") })
    }

    @Test func notFoundWhenSerialIsNotSixBytes() {
        let map = RedactedGATTMapBuilder.make(
            peripheralID: UUID(),
            localName: nil,
            services: [],
            serialByteCount: 12,
            deviceInformationPresent: false
        )
        #expect(map.sixByteAddressSource == .notFound)
        #expect(map.cipherHypothesis == .unknownUntilCapture)
    }
}
