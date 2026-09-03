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
    case invalidRegistrationMarkerEncoding
    case registrationMarkerMismatch
    case invalidV3GlucoseNotificationLength(Int)
    case invalidV3GlucoseNotificationDeclaredLength
    case invalidV3GlucoseRecordCount(Int)
    case invalidV3GlucoseRecordLayout
    case unsupportedV3NotificationCommand(UInt8)
    case invalidV3GlucoseNotificationChecksum
    case invalidV3ControlResponseLength(Int)
    case unsupportedV3ControlResponseCommand(UInt8)
    case invalidV3ControlResponseChecksum
    case v3EffectiveDataStartIndexOutOfRange
    case invalidV3AuthenticationCaptureLength(Int)
    case invalidV3AuthenticationCapture
    case v3AuthenticationReplayMismatch
    case invalidV3EffectiveDataCapture
    case invalidV3DataBatchCapture
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
        case .invalidRegistrationMarkerEncoding:
            return "V3 registration marker must contain only non-NUL ASCII bytes."
        case .registrationMarkerMismatch:
            return "V3 registration envelope did not match the caller-provided marker."
        case .invalidV3GlucoseNotificationLength(let count):
            return "V3 glucose notification has an unsupported length of \(count) bytes."
        case .invalidV3GlucoseNotificationDeclaredLength:
            return "V3 glucose notification declared a length that does not match the frame."
        case .invalidV3GlucoseRecordCount(let count):
            return "V3 glucose notification has an unsupported record count of \(count)."
        case .invalidV3GlucoseRecordLayout:
            return "V3 glucose notification record count does not match the frame layout."
        case .unsupportedV3NotificationCommand(let command):
            return "V3 notification command 0x\(String(command, radix: 16)) is unsupported."
        case .invalidV3GlucoseNotificationChecksum:
            return "V3 glucose notification failed its additive checksum."
        case .invalidV3ControlResponseLength(let count):
            return "V3 control response must contain 5 bytes; received \(count)."
        case .unsupportedV3ControlResponseCommand(let command):
            return "V3 control response command 0x\(String(command, radix: 16)) is unsupported."
        case .invalidV3ControlResponseChecksum:
            return "V3 control response failed its additive checksum."
        case .v3EffectiveDataStartIndexOutOfRange:
            return "The durable V3 history cursor cannot be represented by the verified request."
        case .invalidV3AuthenticationCaptureLength(let count):
            return "The captured V3 authentication write must contain 38 bytes; received \(count)."
        case .invalidV3AuthenticationCapture:
            return "The captured V3 authentication write failed closed validation."
        case .v3AuthenticationReplayMismatch:
            return "The captured V3 authentication write did not reproduce exactly."
        case .invalidV3EffectiveDataCapture:
            return "The captured V3 history request failed closed validation."
        case .invalidV3DataBatchCapture:
            return "The captured V3 data batch failed closed validation."
        }
    }
}
