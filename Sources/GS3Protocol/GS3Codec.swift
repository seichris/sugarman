// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// Intentionally empty: live sensor requests are not representable until
/// physical gates P1 and P2 pass. There is therefore no authentication,
/// binding, activation, reset, expiry, or secret-key request case.
public enum GS3ProtocolRequest: Sendable, Equatable, CaseIterable {
}

/// Opaque frame wrapper. Production logs must never print `bytes`.
public struct EncodedFrame:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let bytes: [UInt8]
    public let byteCount: Int

    public init(bytes: [UInt8]) {
        self.bytes = bytes
        self.byteCount = bytes.count
    }

    public var description: String {
        "EncodedFrame(byteCount: \(byteCount))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: ["byteCount": byteCount], displayStyle: .struct)
    }
}

public enum GS3ProtocolEvent: Sendable, Equatable {
    case rejectedUnimplemented
}

/// Deterministic codec interface. M0 implementations always fail closed.
public protocol GS3Codec: Sendable {
    var variant: ProtocolVariant { get }
    func encode(_ request: GS3ProtocolRequest) throws -> EncodedFrame
    func decode(_ frame: EncodedFrame) throws -> GS3ProtocolEvent
}

/// Placeholder live codec. Even `.v3AES` stays unavailable here: its current
/// implementation surface is an isolated offline authentication builder only.
public struct UnimplementedGS3Codec: GS3Codec {
    public let variant: ProtocolVariant

    public init(variant: ProtocolVariant) {
        self.variant = variant
    }

    public func encode(_ request: GS3ProtocolRequest) throws -> EncodedFrame {
        _ = request
        switch variant {
        case .unknown, .v120RC4, .v3AES:
            throw GS3ProtocolError.unimplementedVariant(variant)
        }
    }

    public func decode(_ frame: EncodedFrame) throws -> GS3ProtocolEvent {
        _ = frame.byteCount
        throw GS3ProtocolError.unimplementedVariant(variant)
    }
}

public enum GS3CodecFactory: Sendable {
    public static func make(variant: ProtocolVariant) throws -> any GS3Codec {
        throw GS3ProtocolError.unimplementedVariant(variant)
    }
}
