// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import GS3Protocol

struct GS3ProtocolTests {
    @Test func noLiveRequestsAreRepresentable() {
        #expect(GS3ProtocolRequest.allCases.isEmpty)
    }

    @Test func allVariantsFailClosedInLiveFactory() {
        for variant in ProtocolVariant.allCases {
            let codec = UnimplementedGS3Codec(variant: variant)
            #expect(throws: GS3ProtocolError.unimplementedVariant(variant)) {
                try codec.decode(EncodedFrame(bytes: [0x00]))
            }
            #expect(throws: GS3ProtocolError.unimplementedVariant(variant)) {
                try GS3CodecFactory.make(variant: variant)
            }
        }
    }

    @Test func factoryNeverReturnsAnImplementedCodec() {
        #expect(ProtocolVariant.allCases.allSatisfy { !$0.isImplemented })
    }

    @Test func encodedFrameDescriptionOmitsBytes() {
        let frame = EncodedFrame(bytes: [0xDE, 0xAD, 0xBE, 0xEF, 0x00])
        let described = String(describing: frame)
        let reflected = String(reflecting: frame)
        var dumped = ""
        dump(frame, to: &dumped)
        #expect(described == "EncodedFrame(byteCount: 5)")
        #expect(reflected == "EncodedFrame(byteCount: 5)")
        #expect(!described.contains("222"))
        #expect(!described.contains("DEAD"))
        #expect(!reflected.contains("222"))
        #expect(!dumped.contains("222"))
        #expect(!dumped.contains("173"))
        #expect(frame.bytes == [0xDE, 0xAD, 0xBE, 0xEF, 0x00])
    }

    @Test func aes128MatchesNISTFIPS197Example() throws {
        let key = bytes("000102030405060708090a0b0c0d0e0f")
        let plaintext = bytes("00112233445566778899aabbccddeeff")
        let expected = bytes("69c4e0d86a7b0430d8cdb78070b4c55a")

        #expect(try AES128.encrypt(block: plaintext, key: key) == expected)
        #expect(throws: GS3ProtocolError.invalidAESBlockLength(15)) {
            try AES128.encrypt(block: [UInt8](repeating: 0, count: 15), key: key)
        }
        #expect(throws: GS3ProtocolError.invalidAESKeyLength(15)) {
            try AES128.encrypt(block: plaintext, key: [UInt8](repeating: 0, count: 15))
        }
    }

    @Test func aes128OFBMatchesNISTSP80038AExample() throws {
        let key = bytes("2b7e151628aed2a6abf7158809cf4f3c")
        let initializationVector = bytes("000102030405060708090a0b0c0d0e0f")
        let plaintext = bytes(
            "6bc1bee22e409f96e93d7e117393172a"
                + "ae2d8a571e03ac9c9eb76fac45af8e51"
                + "30c81c46a35ce411e5fbc1191a0a52ef"
                + "f69f2445df4f9b17ad2b417be66c3710"
        )
        let expected = bytes(
            "3b3fd92eb72dad20333449f8e83cfb4a"
                + "7789508d16918f03f53c52dac54ed825"
                + "9740051e9c5fecf64344f7a82260edcc"
                + "304c6528f659c77866a510d9c1d6ae5e"
        )

        #expect(
            try AES128OFB.crypt(
                plaintext,
                key: key,
                initializationVector: initializationVector
            ) == expected
        )
        #expect(
            try AES128OFB.crypt(
                expected,
                key: key,
                initializationVector: initializationVector
            ) == plaintext
        )
        #expect(throws: GS3ProtocolError.invalidAESKeyLength(0)) {
            try AES128OFB.crypt(
                [],
                key: [],
                initializationVector: initializationVector
            )
        }
    }

    @Test func rc4MatchesRFC6229Initial128BitVector() throws {
        let key = bytes("0102030405060708090a0b0c0d0e0f10")
        let expectedKeystream = bytes("9ac7cc9a609d1ef7b2932899cde41b97")

        #expect(
            try RC4.crypt([UInt8](repeating: 0, count: 16), key: key)
                == expectedKeystream
        )
        #expect(throws: GS3ProtocolError.invalidRC4KeyLength(0)) {
            try RC4.crypt([], key: [])
        }
    }

    @Test func registrationEnvelopeProducesOpaqueMaterialAndAuthVector() throws {
        let encodedHex = "26f56cdd0d7548cdaf92921619a01e9598a8f8513c9b0ec1106f88096d180448c0"
        let material = try V3RegistrationEnvelopeDecoder.decode(
            encodedHex: encodedHex,
            expectedMarker: "owner",
            initializationVector: Array(0xA0...0xAF)
        )

        #expect(material.registeredBlock == Array(0x10...0x1F))
        #expect(material.initializationVector == Array(0xA0...0xAF))
        #expect(!String(describing: material).contains("101112"))

        let inputs = try V3AuthenticationInputs(
            deviceType: 0,
            sensorAddress: Array(1...6),
            authenticationID: Array("owner-123".utf8),
            registeredMaterial: material
        )
        #expect(
            try V3OfflineAuthenticationCodec.encode(inputs).bytes
                == bytes("05bee87ea695ebcf6aa251c0fc051bf08610aa17da6a074fcf3a9f8edf1d13ff2020f32a5cd1")
        )
    }

    @Test func registrationEnvelopeFailsClosed() {
        #expect(throws: GS3ProtocolError.invalidRegistrationEnvelopeLength(2)) {
            try V3RegistrationEnvelopeDecoder.decode(
                encodedHex: "00",
                expectedMarker: "",
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidRegistrationEnvelopeEncoding) {
            try V3RegistrationEnvelopeDecoder.decode(
                encodedHex: String(repeating: "z", count: 56),
                expectedMarker: "",
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.registrationMarkerMismatch) {
            try V3RegistrationEnvelopeDecoder.decode(
                encodedHex: "26f56cdd0d7548cdaf92921619a01e9598a8f8513c9b0ec1106f88096d180448c0",
                expectedMarker: "wrong",
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidInitializationVectorLength(15)) {
            try V3RegistrationEnvelopeDecoder.decode(
                encodedHex: String(repeating: "0", count: 56),
                expectedMarker: "",
                initializationVector: [UInt8](repeating: 0, count: 15)
            )
        }
        #expect(throws: GS3ProtocolError.invalidRegistrationMarkerEncoding) {
            try V3RegistrationEnvelopeDecoder.decode(
                encodedHex: "26f56cdd0d7548cdaf92921619a01e9598a8f8513c9b0ec1106f88096d180448c0",
                expectedMarker: "own\0r",
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidRegistrationMarkerEncoding) {
            try V3RegistrationEnvelopeDecoder.decode(
                encodedHex: "26f56cdd0d7548cdaf92921619a01e9598a8f8513c9b0ec1106f88096d180448c0",
                expectedMarker: "ownér",
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
    }

    @Test func v3OfflineAuthLayoutAndCipherMatchIndependentSyntheticVector() throws {
        let inputs = try syntheticV3Inputs()
        let encoded = try V3OfflineAuthenticationCodec.encode(inputs)
        let plaintext = try AES128OFB.crypt(
            encoded.bytes,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: Array(0xA0...0xAF)
        )

        #expect(
            plaintext
                == bytes("25e200010203040506101112131415161718191a1b1c1d1e1f6f776e65722d3132330000007e"))
        #expect(plaintext.count == 38)
        #expect(plaintext.reduce(UInt8.zero) { $0 &+ $1 } == 0)

        #expect(
            encoded.bytes
                == bytes("05bee87ea695ebcf6aa251c0fc051bf08610aa17da6a074fcf3a9f8edf1d13ff2020f32a5cd1"))
        #expect(encoded.byteCount == 38)
    }

    @Test func v3OfflineAuthInputsRejectEveryUnprovenLength() throws {
        let material = try syntheticMaterial()

        #expect(throws: GS3ProtocolError.invalidSensorAddressLength(5)) {
            try V3AuthenticationInputs(
                deviceType: 0,
                sensorAddress: [UInt8](repeating: 0, count: 5),
                authenticationID: [],
                registeredMaterial: material
            )
        }
        #expect(throws: GS3ProtocolError.invalidAuthenticationIDLength(13)) {
            try V3AuthenticationInputs(
                deviceType: 0,
                sensorAddress: [UInt8](repeating: 0, count: 6),
                authenticationID: [UInt8](repeating: 0, count: 13),
                registeredMaterial: material
            )
        }
    }

    @Test func v3OfflineAuthAcceptsEveryProvenAuthenticationIDLength() throws {
        let material = try syntheticMaterial()
        for count in 0...12 {
            let inputs = try V3AuthenticationInputs(
                deviceType: 0,
                sensorAddress: Array(1...6),
                authenticationID: [UInt8](repeating: 0x41, count: count),
                registeredMaterial: material
            )
            let encoded = try V3OfflineAuthenticationCodec.encode(inputs)
            let plaintext = try AES128OFB.crypt(
                encoded.bytes,
                key: V3ProtocolConstants.fixedKey,
                initializationVector: Array(0xA0...0xAF)
            )
            #expect(encoded.byteCount == 38)
            #expect(plaintext.reduce(UInt8.zero) { $0 &+ $1 } == 0)
        }
    }

    @Test func v3DescriptionsDoNotExposeSensitiveValues() throws {
        let inputs = try syntheticV3Inputs()
        let described = String(describing: inputs)
        let reflected = String(reflecting: inputs)
        let material = try syntheticMaterial()
        var inputDump = ""
        var materialDump = ""
        dump(inputs, to: &inputDump)
        dump(material, to: &materialDump)

        #expect(described == reflected)
        #expect(!described.contains("owner"))
        #expect(!described.contains("010203040506"))
        #expect(!described.contains("A0A1"))
        #expect(!inputDump.contains("owner"))
        #expect(!inputDump.contains("161"))
        #expect(!materialDump.contains("161"))
        #expect(!materialDump.contains("16, 17"))
        #expect(described.contains("authenticationIDByteCount: 9"))
    }

    @Test func v3OfflineGlucoseDecoderParsesSyntheticMultiRecordNotification() throws {
        let material = try syntheticGlucoseMaterial()
        let frame = try syntheticGlucoseNotification(
            startingIndex: 0x1234,
            endingReindex: 400,
            records: [
                SyntheticGlucoseRecord(
                    rawTemperature: 0x1112,
                    rawDump: 0x2122,
                    rawCurrent: 0x3132,
                    rawDisplayGlucose: 0x3334,
                    glucoseTenths: 72,
                    flags: 0xAA,
                    states: 0x75,
                    rawCEVoltage: 0x4445,
                    rawREVoltage: 0x5556
                ),
                SyntheticGlucoseRecord(
                    rawTemperature: 0x6162,
                    rawDump: 0x7172,
                    rawCurrent: 0x8182,
                    rawDisplayGlucose: 0x8384,
                    glucoseTenths: 98,
                    flags: 0x35,
                    states: 0x4E,
                    rawCEVoltage: 0x9192,
                    rawREVoltage: 0xA1A2
                ),
            ]
        )

        let decoded = try V3OfflineGlucoseNotificationDecoder.decode(
            frame,
            using: material
        )

        #expect(decoded.count == 2)
        #expect(decoded[0].index == 0x1234)
        #expect(decoded[0].reindex == 401)
        #expect(decoded[0].rawTemperature == 0x1112)
        #expect(decoded[0].rawDump == 0x2122)
        #expect(decoded[0].rawCurrent == 0x3132)
        #expect(decoded[0].rawDisplayGlucose == 0x3334)
        #expect(decoded[0].glucoseTenthsMillimolesPerLiter == 72)
        #expect(decoded[0].glucoseMillimolesPerLiter == 7.2)
        #expect(decoded[0].trendCode == 2)
        #expect(decoded[0].presentCState)
        #expect(decoded[0].algorithmCState == 10)
        #expect(decoded[0].tState == 1)
        #expect(decoded[0].dState == 5)
        #expect(decoded[0].algorithmReserved == 3)
        #expect(decoded[0].rawCEVoltage == 0x4445)
        #expect(decoded[0].rawREVoltage == 0x5556)
        #expect(decoded[1].index == 0x1235)
        #expect(decoded[1].reindex == 400)
        #expect(decoded[1].glucoseTenthsMillimolesPerLiter == 98)
        #expect(decoded[1].trendCode == 5)
    }

    @Test func v3OfflineGlucoseDecoderFailsClosedOnMalformedFrames() throws {
        let material = try syntheticGlucoseMaterial()
        let valid = try syntheticGlucoseNotification(
            startingIndex: 1,
            endingReindex: 1,
            records: [.minimal]
        )

        #expect(throws: GS3ProtocolError.invalidV3GlucoseNotificationLength(23)) {
            try V3OfflineGlucoseNotificationDecoder.decode(
                EncodedFrame(bytes: Array(valid.bytes.dropLast())),
                using: material
            )
        }

        var badDeclaredLengthPlaintext = try decryptSyntheticTransport(valid)
        badDeclaredLengthPlaintext[0] &-= 1
        badDeclaredLengthPlaintext[23] = 0
        badDeclaredLengthPlaintext[23] = UInt8.zero
            &- badDeclaredLengthPlaintext.dropLast().reduce(0, &+)
        let badDeclaredLength = try encryptSyntheticTransport(
            badDeclaredLengthPlaintext
        )
        #expect(throws: GS3ProtocolError.invalidV3GlucoseNotificationDeclaredLength) {
            try V3OfflineGlucoseNotificationDecoder.decode(
                badDeclaredLength,
                using: material
            )
        }

        var badChecksumPlaintext = try decryptSyntheticTransport(valid)
        badChecksumPlaintext[23] &+= 1
        let badChecksum = try encryptSyntheticTransport(badChecksumPlaintext)
        #expect(throws: GS3ProtocolError.invalidV3GlucoseNotificationChecksum) {
            try V3OfflineGlucoseNotificationDecoder.decode(badChecksum, using: material)
        }

        var wrongCommandPlaintext = try decryptSyntheticTransport(valid)
        wrongCommandPlaintext[1] = 0x31
        wrongCommandPlaintext[23] = 0
        wrongCommandPlaintext[23] = UInt8.zero &- wrongCommandPlaintext.dropLast().reduce(0, &+)
        let wrongCommand = try encryptSyntheticTransport(wrongCommandPlaintext)
        #expect(throws: GS3ProtocolError.unsupportedV3NotificationCommand(0x31)) {
            try V3OfflineGlucoseNotificationDecoder.decode(wrongCommand, using: material)
        }

        var zeroRecordsPlaintext = try decryptSyntheticTransport(valid)
        zeroRecordsPlaintext[2] = 0
        zeroRecordsPlaintext[23] = 0
        zeroRecordsPlaintext[23] = UInt8.zero &- zeroRecordsPlaintext.dropLast().reduce(0, &+)
        let zeroRecords = try encryptSyntheticTransport(zeroRecordsPlaintext)
        #expect(throws: GS3ProtocolError.invalidV3GlucoseRecordCount(0)) {
            try V3OfflineGlucoseNotificationDecoder.decode(zeroRecords, using: material)
        }

        var wrongRecordLayoutPlaintext = try decryptSyntheticTransport(valid)
        wrongRecordLayoutPlaintext[2] = 2
        wrongRecordLayoutPlaintext[23] = 0
        wrongRecordLayoutPlaintext[23] = UInt8.zero
            &- wrongRecordLayoutPlaintext.dropLast().reduce(0, &+)
        let wrongRecordLayout = try encryptSyntheticTransport(
            wrongRecordLayoutPlaintext
        )
        #expect(throws: GS3ProtocolError.invalidV3GlucoseRecordLayout) {
            try V3OfflineGlucoseNotificationDecoder.decode(
                wrongRecordLayout,
                using: material
            )
        }
    }

    @Test func v3GlucoseMaterialAndRecordsRedactSensitiveValues() throws {
        let material = try syntheticGlucoseMaterial()
        var materialDump = ""
        dump(material, to: &materialDump)

        #expect(!String(describing: material).contains("161"))
        #expect(!materialDump.contains("161"))

        let record = try V3OfflineGlucoseNotificationDecoder.decode(
            syntheticGlucoseNotification(
                startingIndex: 1,
                endingReindex: 1,
                records: [.minimal]
            ),
            using: material
        )[0]
        var recordDump = ""
        dump(record, to: &recordDump)
        #expect(!String(describing: record).contains("72"))
        #expect(!recordDump.contains("72"))
        #expect(recordDump.contains("redacted"))
    }

    @Test func v3GlucoseMaterialRejectsUnprovenLengths() {
        #expect(throws: GS3ProtocolError.invalidSensorAddressLength(5)) {
            try V3GlucoseCryptoMaterial(
                sensorAddress: [UInt8](repeating: 0, count: 5),
                algorithmKey: [UInt8](repeating: 0, count: 16),
                algorithmInitializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidAESKeyLength(15)) {
            try V3GlucoseCryptoMaterial(
                sensorAddress: [UInt8](repeating: 0, count: 6),
                algorithmKey: [UInt8](repeating: 0, count: 15),
                algorithmInitializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidInitializationVectorLength(15)) {
            try V3GlucoseCryptoMaterial(
                sensorAddress: [UInt8](repeating: 0, count: 6),
                algorithmKey: [UInt8](repeating: 0, count: 16),
                algorithmInitializationVector: [UInt8](repeating: 0, count: 15)
            )
        }
    }

    private func syntheticV3Inputs() throws -> V3AuthenticationInputs {
        try V3AuthenticationInputs(
            deviceType: 0,
            sensorAddress: Array(1...6),
            authenticationID: Array("owner-123".utf8),
            registeredMaterial: syntheticMaterial()
        )
    }

    private func syntheticMaterial() throws -> V3RegisteredMaterial {
        try V3RegistrationEnvelopeDecoder.decode(
            encodedHex: "26f56cdd0d7548cdaf92921619a01e9598a8f8513c9b0ec1106f88096d180448c0",
            expectedMarker: "owner",
            initializationVector: Array(0xA0...0xAF)
        )
    }

    @Test func activeSessionMaterialExposesOnlyTwoTypedFramesAndRejectsIndexWrap() throws {
        let material = try syntheticActiveSessionMaterial()
        #expect(try material.authenticationFrame().byteCount == 38)
        #expect(try material.effectiveDataFrame(startingIndex: 123).byteCount == 7)
        #expect(throws: GS3ProtocolError.v3EffectiveDataStartIndexOutOfRange) {
            try material.effectiveDataFrame(startingIndex: UInt32(UInt16.max) + 1)
        }
    }

    @Test func activeSessionMaterialDiagnosticsRevealOnlyByteCounts() throws {
        let material = try syntheticActiveSessionMaterial()
        let text = "\(material) \(String(reflecting: material))"
        for secret in ["010203040506", "202122232425", "303132333435", "404142434445"] {
            #expect(!text.localizedCaseInsensitiveContains(secret))
        }
        #expect(text.contains("addressBytes: 6"))
        #expect(text.contains("algorithmKeyBytes: 16"))
        #expect(!text.contains("[1, 2, 3"))
    }

    private func syntheticActiveSessionMaterial() throws -> V3ActiveSessionMaterial {
        try V3ActiveSessionMaterial(
            sensorAddress: Array(1...6),
            authenticationID: Array(0x20...0x2B),
            registeredBlock: Array(0x30...0x3F),
            algorithmKey: syntheticAlgorithmKey,
            algorithmInitializationVector: syntheticAlgorithmInitializationVector
        )
    }

    private struct SyntheticGlucoseRecord {
        let rawTemperature: UInt16
        let rawDump: UInt16
        let rawCurrent: UInt16
        let rawDisplayGlucose: UInt16
        let glucoseTenths: UInt16
        let flags: UInt8
        let states: UInt8
        let rawCEVoltage: UInt16
        let rawREVoltage: UInt16

        static let minimal = SyntheticGlucoseRecord(
            rawTemperature: 1,
            rawDump: 2,
            rawCurrent: 3,
            rawDisplayGlucose: 4,
            glucoseTenths: 72,
            flags: 2,
            states: 0,
            rawCEVoltage: 5,
            rawREVoltage: 6
        )
    }

    private func syntheticGlucoseMaterial() throws -> V3GlucoseCryptoMaterial {
        try V3GlucoseCryptoMaterial(
            sensorAddress: Array(1...6),
            algorithmKey: Array(0x10...0x1F),
            algorithmInitializationVector: Array(0xA0...0xAF)
        )
    }

    private func syntheticGlucoseNotification(
        startingIndex: UInt16,
        endingReindex: UInt16,
        records: [SyntheticGlucoseRecord]
    ) throws -> EncodedFrame {
        var plaintext: [UInt8] = [0, 0x32, UInt8(records.count)]
        appendLittleEndian(startingIndex, to: &plaintext)

        for record in records {
            appendLittleEndian(record.rawTemperature, to: &plaintext)
            appendLittleEndian(record.rawDump, to: &plaintext)
            appendLittleEndian(record.rawCurrent, to: &plaintext)
            appendLittleEndian(record.rawDisplayGlucose, to: &plaintext)
            let algorithmPlaintext = [
                UInt8(truncatingIfNeeded: record.glucoseTenths),
                UInt8(truncatingIfNeeded: record.glucoseTenths >> 8),
            ]
            plaintext.append(
                contentsOf: try AES128OFB.crypt(
                    algorithmPlaintext,
                    key: syntheticAlgorithmKey,
                    initializationVector: syntheticAlgorithmInitializationVector
                )
            )
            plaintext.append(record.flags)
            plaintext.append(record.states)
            appendLittleEndian(record.rawCEVoltage, to: &plaintext)
            appendLittleEndian(record.rawREVoltage, to: &plaintext)
        }

        appendLittleEndian(endingReindex, to: &plaintext)
        plaintext.append(0)
        plaintext[0] = UInt8(plaintext.count - 1)
        plaintext[plaintext.count - 1] = UInt8.zero &- plaintext.dropLast().reduce(0, &+)
        return try encryptSyntheticTransport(plaintext)
    }

    private func encryptSyntheticTransport(_ plaintext: [UInt8]) throws -> EncodedFrame {
        EncodedFrame(
            bytes: try AES128OFB.crypt(
                plaintext,
                key: V3ProtocolConstants.fixedKey,
                initializationVector: syntheticTransportInitializationVector
            )
        )
    }

    private func decryptSyntheticTransport(_ frame: EncodedFrame) throws -> [UInt8] {
        try AES128OFB.crypt(
            frame.bytes,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: syntheticTransportInitializationVector
        )
    }

    private var syntheticTransportInitializationVector: [UInt8] {
        Array(1...6) + [UInt8](repeating: 0, count: 10)
    }

    private var syntheticAlgorithmKey: [UInt8] {
        Array(0x10...0x1F)
    }

    private var syntheticAlgorithmInitializationVector: [UInt8] {
        Array(0xA0...0xAF)
    }

    private func appendLittleEndian(_ value: UInt16, to bytes: inout [UInt8]) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }
    }
}
