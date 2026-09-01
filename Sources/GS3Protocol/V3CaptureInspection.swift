// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Package-only, side-effect-free validation used by the private handover
/// builder. It exposes no transport or lifecycle operation and returns only
/// values already required by the strict private handover schema.
package enum V3OfflineCaptureInspector {
    package static func recoverRegisteredBlock(
        authenticationCiphertext: EncodedFrame,
        sensorAddress: [UInt8],
        authenticationID: [UInt8]
    ) throws -> [UInt8] {
        guard authenticationCiphertext.byteCount == 38 else {
            throw GS3ProtocolError.invalidV3AuthenticationCaptureLength(
                authenticationCiphertext.byteCount
            )
        }
        guard authenticationID.count == 12 else {
            throw GS3ProtocolError.invalidAuthenticationIDLength(authenticationID.count)
        }

        let plaintext = try AES128OFB.crypt(
            authenticationCiphertext.bytes,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: v3TransportInitializationVector(
                sensorAddress: sensorAddress
            )
        )
        guard plaintext[0] == 0x25,
              plaintext[1] == 0xE2,
              plaintext[2] == 0,
              Array(plaintext[3..<9]) == sensorAddress,
              Array(plaintext[25..<37]) == authenticationID,
              plaintext.reduce(UInt8.zero, &+) == 0 else {
            throw GS3ProtocolError.invalidV3AuthenticationCapture
        }

        let registeredBlock = Array(plaintext[9..<25])
        let replay = try V3OfflineAuthenticationCodec.encode(
            V3AuthenticationInputs(
                deviceType: 0,
                sensorAddress: sensorAddress,
                authenticationID: authenticationID,
                recoveredRegisteredBlock: registeredBlock
            )
        )
        guard replay.bytes == authenticationCiphertext.bytes else {
            throw GS3ProtocolError.v3AuthenticationReplayMismatch
        }
        return registeredBlock
    }

    package static func historyStart(
        requestCiphertext: EncodedFrame,
        sensorAddress: [UInt8]
    ) throws -> UInt16 {
        guard requestCiphertext.byteCount == 7 else {
            throw GS3ProtocolError.invalidV3EffectiveDataCapture
        }
        let plaintext = try AES128OFB.crypt(
            requestCiphertext.bytes,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: v3TransportInitializationVector(
                sensorAddress: sensorAddress
            )
        )
        guard plaintext[0] == 0x06,
              plaintext[1] == 0x39,
              plaintext[4] == 0xFF,
              plaintext[5] == 0xFF,
              plaintext.reduce(UInt8.zero, &+) == 0 else {
            throw GS3ProtocolError.invalidV3EffectiveDataCapture
        }
        return UInt16(plaintext[2]) | (UInt16(plaintext[3]) << 8)
    }

    package static func dataBatchStart(
        ciphertext: EncodedFrame,
        sensorAddress: [UInt8]
    ) throws -> UInt16 {
        guard ciphertext.byteCount >= 24 else {
            throw GS3ProtocolError.invalidV3DataBatchCapture
        }
        let plaintext = try AES128OFB.crypt(
            ciphertext.bytes,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: v3TransportInitializationVector(
                sensorAddress: sensorAddress
            )
        )
        guard Int(plaintext[0]) + 1 == plaintext.count,
              plaintext[1] == 0x32 || plaintext[1] == 0x39,
              plaintext[2] > 0,
              plaintext.count == 8 + (Int(plaintext[2]) * 16),
              plaintext.reduce(UInt8.zero, &+) == 0 else {
            throw GS3ProtocolError.invalidV3DataBatchCapture
        }
        return UInt16(plaintext[3]) | (UInt16(plaintext[4]) << 8)
    }
}
