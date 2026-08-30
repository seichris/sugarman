// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain

/// Fail-closed protocol errors. Live request encoding remains unavailable.
public enum GS3ProtocolError: Error, Sendable, Equatable {
    case unimplementedVariant(ProtocolVariant)
    case physicalGatesRequired
    case noEncodableRequest
    case malformedInput
    case invalidSensorAddressLength(Int)
    case invalidRegisteredBlockLength(Int)
    case invalidAuthenticationIDLength(Int)
    case invalidInitializationVectorLength(Int)
    case invalidAESBlockLength(Int)
    case invalidAESKeyLength(Int)
    case invalidRC4KeyLength(Int)
    case invalidRegistrationEnvelopeLength(Int)
    case invalidRegistrationEnvelopeEncoding
    case registrationMarkerMismatch
}

extension GS3ProtocolError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unimplementedVariant(let variant):
            return "Protocol variant \(variant.rawValue) is not implemented."
        case .physicalGatesRequired:
            return "Required protocol and hardware evidence has not passed for this operation."
        case .noEncodableRequest:
            return "No live protocol request is currently representable."
        case .malformedInput:
            return "Input was rejected as malformed."
        case .invalidSensorAddressLength(let count):
            return "V3 sensor address must contain 6 bytes; received \(count)."
        case .invalidRegisteredBlockLength(let count):
            return "V3 registered block must contain 16 bytes; received \(count)."
        case .invalidAuthenticationIDLength(let count):
            return "V3 authentication ID must contain at most 12 bytes; received \(count)."
        case .invalidInitializationVectorLength(let count):
            return "V3 initialization vector must contain 16 bytes; received \(count)."
        case .invalidAESBlockLength(let count):
            return "AES block must contain 16 bytes; received \(count)."
        case .invalidAESKeyLength(let count):
            return "AES-128 key must contain 16 bytes; received \(count)."
        case .invalidRC4KeyLength(let count):
            return "RC4 key must not be empty; received \(count) bytes."
        case .invalidRegistrationEnvelopeLength(let count):
            return "V3 registration envelope has an unsupported encoded length of \(count) bytes."
        case .invalidRegistrationEnvelopeEncoding:
            return "V3 registration envelope must contain only ASCII hexadecimal characters."
        case .registrationMarkerMismatch:
            return "V3 registration envelope did not match the caller-provided marker."
        }
    }
}
