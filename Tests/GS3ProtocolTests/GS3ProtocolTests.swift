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
        #expect(described == "EncodedFrame(byteCount: 5)")
        #expect(reflected == "EncodedFrame(byteCount: 5)")
        #expect(!described.contains("222"))
        #expect(!described.contains("DEAD"))
        #expect(!reflected.contains("222"))
        #expect(frame.bytes == [0xDE, 0xAD, 0xBE, 0xEF, 0x00])
    }

    @Test func aes128MatchesNISTFIPS197Example() throws {
        let key = bytes("000102030405060708090a0b0c0d0e0f")
        let plaintext = bytes("00112233445566778899aabbccddeeff")
        let expected = bytes("69c4e0d86a7b0430d8cdb78070b4c55a")

        #expect(try AES128.encrypt(block: plaintext, key: key) == expected)
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
    }

    @Test func v3OfflineAuthLayoutAndCipherMatchIndependentSyntheticVector() throws {
        let inputs = try syntheticV3Inputs()
        let plaintext = V3OfflineAuthenticationCodec.makePlaintext(inputs)

        #expect(
            plaintext
                == bytes("25e200010203040506101112131415161718191a1b1c1d1e1f6f776e65722d3132330000007e"))
        #expect(plaintext.count == 38)
        #expect(plaintext.reduce(UInt8.zero) { $0 &+ $1 } == 0)

        let encoded = try V3OfflineAuthenticationCodec.encode(inputs)
        #expect(
            encoded.bytes
                == bytes("05bee87ea695ebcf6aa251c0fc051bf08610aa17da6a074fcf3a9f8edf1d13ff2020f32a5cd1"))
        #expect(encoded.byteCount == 38)
    }

    @Test func v3OfflineAuthInputsRejectEveryUnprovenLength() throws {
        let valid = try syntheticV3Inputs()

        #expect(throws: GS3ProtocolError.invalidSensorAddressLength(5)) {
            try V3AuthenticationInputs(
                deviceType: valid.deviceType,
                sensorAddress: [UInt8](repeating: 0, count: 5),
                registeredBlock: [UInt8](repeating: 0, count: 16),
                authenticationID: [],
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidRegisteredBlockLength(15)) {
            try V3AuthenticationInputs(
                deviceType: valid.deviceType,
                sensorAddress: [UInt8](repeating: 0, count: 6),
                registeredBlock: [UInt8](repeating: 0, count: 15),
                authenticationID: [],
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidAuthenticationIDLength(13)) {
            try V3AuthenticationInputs(
                deviceType: valid.deviceType,
                sensorAddress: [UInt8](repeating: 0, count: 6),
                registeredBlock: [UInt8](repeating: 0, count: 16),
                authenticationID: [UInt8](repeating: 0, count: 13),
                initializationVector: [UInt8](repeating: 0, count: 16)
            )
        }
        #expect(throws: GS3ProtocolError.invalidInitializationVectorLength(15)) {
            try V3AuthenticationInputs(
                deviceType: valid.deviceType,
                sensorAddress: [UInt8](repeating: 0, count: 6),
                registeredBlock: [UInt8](repeating: 0, count: 16),
                authenticationID: [],
                initializationVector: [UInt8](repeating: 0, count: 15)
            )
        }
    }

    @Test func v3DescriptionsDoNotExposeSensitiveValues() throws {
        let inputs = try syntheticV3Inputs()
        let described = String(describing: inputs)
        let reflected = String(reflecting: inputs)

        #expect(described == reflected)
        #expect(!described.contains("owner"))
        #expect(!described.contains("010203040506"))
        #expect(!described.contains("A0A1"))
        #expect(described.contains("authenticationIDByteCount: 9"))
    }

    private func syntheticV3Inputs() throws -> V3AuthenticationInputs {
        try V3AuthenticationInputs(
            deviceType: 0,
            sensorAddress: Array(1...6),
            registeredBlock: Array(0x10...0x1F),
            authenticationID: Array("owner-123".utf8),
            initializationVector: Array(0xA0...0xAF)
        )
    }

    private func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }
    }
}
