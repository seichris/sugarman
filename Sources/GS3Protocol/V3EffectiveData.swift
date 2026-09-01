// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Typed, offline input for the observed V3 `0x39` effective-data request.
public struct V3EffectiveDataRequest: Sendable, Equatable {
    public let startingIndex: UInt16
    public let endingIndex: UInt16

    public init(startingIndex: UInt16, endingIndex: UInt16 = .max) {
        self.startingIndex = startingIndex
        self.endingIndex = endingIndex
    }
}

/// Offline encoder for the seven-byte encrypted V3 `0x39` request.
///
/// It is deliberately absent from `GS3ProtocolRequest` and the release
/// `GS3CodecFactory`. The separate developer probe can transmit one result of
/// this encoder only after a verified `0xE2` acceptance response.
public enum V3OfflineEffectiveDataRequestCodec: Sendable {
    public static let evidenceRevision =
        "owned-mainland-gs3-v3-effective-data-2026-08-30"

    public static func encode(
        _ request: V3EffectiveDataRequest,
        sensorAddress: [UInt8]
    ) throws -> EncodedFrame {
        var plaintext: [UInt8] = [
            0x06,
            0x39,
            UInt8(truncatingIfNeeded: request.startingIndex),
            UInt8(truncatingIfNeeded: request.startingIndex >> 8),
            UInt8(truncatingIfNeeded: request.endingIndex),
            UInt8(truncatingIfNeeded: request.endingIndex >> 8),
        ]
        plaintext.append(additiveChecksum(for: plaintext))

        let encrypted = try AES128OFB.crypt(
            plaintext,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: v3TransportInitializationVector(
                sensorAddress: sensorAddress
            )
        )
        return EncodedFrame(bytes: encrypted)
    }
}

public enum V3ControlResponse: Sendable, Equatable {
    case authenticationAccepted
    case authenticationRejected(code: UInt8, detail: UInt8)
    case effectiveDataAcknowledgement(code: UInt8, detail: UInt8)
}

/// Decrypts only the observed five-byte `0xE2` and `0x39` control responses.
/// It returns status bytes, never the raw plaintext or session material.
public enum V3OfflineControlResponseDecoder: Sendable {
    public static func decode(
        _ frame: EncodedFrame,
        sensorAddress: [UInt8]
    ) throws -> V3ControlResponse {
        guard frame.byteCount == 5 else {
            throw GS3ProtocolError.invalidV3ControlResponseLength(frame.byteCount)
        }
        let plaintext = try AES128OFB.crypt(
            frame.bytes,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: v3TransportInitializationVector(
                sensorAddress: sensorAddress
            )
        )
        guard plaintext[0] == 0x04 else {
            throw GS3ProtocolError.invalidV3ControlResponseLength(plaintext.count)
        }
        guard plaintext.reduce(UInt8.zero, &+) == 0 else {
            throw GS3ProtocolError.invalidV3ControlResponseChecksum
        }

        switch plaintext[1] {
        case 0xE2:
            if plaintext[2] == 0x01, plaintext[3] == 0x00 {
                return .authenticationAccepted
            }
            return .authenticationRejected(code: plaintext[2], detail: plaintext[3])
        case 0x39:
            return .effectiveDataAcknowledgement(
                code: plaintext[2],
                detail: plaintext[3]
            )
        default:
            throw GS3ProtocolError.unsupportedV3ControlResponseCommand(
                plaintext[1]
            )
        }
    }
}

private func additiveChecksum(for bytes: [UInt8]) -> UInt8 {
    UInt8.zero &- bytes.reduce(UInt8.zero, &+)
}
