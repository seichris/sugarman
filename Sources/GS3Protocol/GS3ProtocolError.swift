// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain

/// Fail-closed protocol errors. No codec is implemented at M0.
public enum GS3ProtocolError: Error, Sendable, Equatable {
    case unimplementedVariant(ProtocolVariant)
    case physicalGatesRequired
    case noEncodableRequest
    case malformedInput
}

extension GS3ProtocolError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unimplementedVariant(let variant):
            return "Protocol variant \(variant.rawValue) is not implemented."
        case .physicalGatesRequired:
            return "P1/P2 hardware evidence is required before any codec work."
        case .noEncodableRequest:
            return "No live protocol request is representable at M0."
        case .malformedInput:
            return "Input was rejected as malformed."
        }
    }
}
