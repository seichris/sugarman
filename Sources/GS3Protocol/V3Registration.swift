// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Opaque V3 values produced by the observed registration-envelope transform.
/// Values are intentionally unavailable as public properties; they can only be
/// passed into `V3AuthenticationInputs` and are omitted from descriptions.
public struct V3RegisteredMaterial:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible
{
    let registeredBlock: [UInt8]
    let initializationVector: [UInt8]

    init(registeredBlock: [UInt8], initializationVector: [UInt8]) {
        self.registeredBlock = registeredBlock
        self.initializationVector = initializationVector
    }

    public var description: String {
        "V3RegisteredMaterial(registeredBlockByteCount: \(registeredBlock.count), "
            + "initializationVectorByteCount: \(initializationVector.count))"
    }

    public var debugDescription: String { description }
}

/// Strict offline decoder for the registration-envelope shape observed in the
/// owned V3 native library. Callers must obtain all three inputs through a
/// legitimate owner-controlled route; this API does not read another app's
/// storage, call a vendor service, or invent missing values.
public enum V3RegistrationEnvelopeDecoder: Sendable {
    public static func decode(
        encodedHex: String,
        expectedMarker: String,
        initializationVector: [UInt8]
    ) throws -> V3RegisteredMaterial {
        guard initializationVector.count == 16 else {
            throw GS3ProtocolError.invalidInitializationVectorLength(initializationVector.count)
        }

        let encoded = Array(encodedHex.utf8)
        guard encoded.count >= 56, encoded.count <= 254, encoded.count.isMultiple(of: 2) else {
            throw GS3ProtocolError.invalidRegistrationEnvelopeLength(encoded.count)
        }
        guard encoded.allSatisfy(isASCIIHexDigit) else {
            throw GS3ProtocolError.invalidRegistrationEnvelopeEncoding
        }

        var encrypted: [UInt8] = []
        encrypted.reserveCapacity(encoded.count / 2)
        for offset in stride(from: 0, to: encoded.count, by: 2) {
            let high = hexNibble(encoded[offset])
            let low = hexNibble(encoded[offset + 1])
            encrypted.append((high << 4) | low)
        }

        let decoded = try RC4.crypt(encrypted, key: V3ProtocolConstants.fixedKey)
        let marker = Array(expectedMarker.utf8)
        let requiredMarkerLength = decoded.count - 28
        guard marker.count == requiredMarkerLength else {
            throw GS3ProtocolError.registrationMarkerMismatch
        }
        guard decoded[22..<(22 + marker.count)].elementsEqual(marker) else {
            throw GS3ProtocolError.registrationMarkerMismatch
        }

        return V3RegisteredMaterial(
            registeredBlock: Array(decoded[6..<22]),
            initializationVector: initializationVector
        )
    }

    private static func isASCIIHexDigit(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39)
            || (byte >= 0x41 && byte <= 0x46)
            || (byte >= 0x61 && byte <= 0x66)
    }

    private static func hexNibble(_ byte: UInt8) -> UInt8 {
        switch byte {
        case 0x30...0x39:
            byte - 0x30
        case 0x41...0x46:
            byte - 0x41 + 10
        default:
            byte - 0x61 + 10
        }
    }
}

/// RC4 exists here only to reproduce the vendor registration-envelope
/// transform. It must not be selected as a general-purpose cipher.
enum RC4 {
    static func crypt(_ input: [UInt8], key: [UInt8]) throws -> [UInt8] {
        guard !key.isEmpty else {
            throw GS3ProtocolError.invalidRC4KeyLength(0)
        }

        var state = (0...255).map(UInt8.init)
        var j = 0
        for i in 0..<256 {
            j = (j + Int(state[i]) + Int(key[i % key.count])) & 0xFF
            state.swapAt(i, j)
        }

        var output = input
        var i = 0
        j = 0
        for index in output.indices {
            i = (i + 1) & 0xFF
            j = (j + Int(state[i])) & 0xFF
            state.swapAt(i, j)
            let streamByte = state[(Int(state[i]) + Int(state[j])) & 0xFF]
            output[index] ^= streamByte
        }
        return output
    }
}
