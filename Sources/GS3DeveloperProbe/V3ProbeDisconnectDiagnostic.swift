// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Payload-free transport classification for a developer-probe disconnect.
///
/// The runtime may retain a numeric CoreBluetooth error code because it is
/// protocol-independent platform metadata. Non-CoreBluetooth errors are
/// deliberately collapsed so their descriptions cannot leak identifiers or
/// private material into a shared report.
public enum V3ProbeTransportErrorClass: Sendable, Equatable {
    case noneReported
    case coreBluetooth(code: Int)
    case redactedOther
}

extension V3ProbeTransportErrorClass: CustomStringConvertible {
    public var description: String {
        switch self {
        case .noneReported:
            "none reported"
        case .coreBluetooth(let code):
            "CoreBluetooth code \(code)"
        case .redactedOther:
            "non-CoreBluetooth error redacted"
        }
    }
}

/// Redacted snapshot emitted when the one-shot developer probe disconnects
/// before its completion gate.
public struct V3ProbeDisconnectDiagnostic:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let sessionOrdinal: Int
    public let elapsedWholeSeconds: Int
    public let state: V3ProbeState
    public let transportError: V3ProbeTransportErrorClass
    public let authenticationWriteCallCount: Int
    public let effectiveDataWriteCallCount: Int
    public let uniqueLiveReadingCount: Int
    public let quarantinedCommandCount: Int

    public init(
        sessionOrdinal: Int,
        elapsedWholeSeconds: Int,
        state: V3ProbeState,
        transportError: V3ProbeTransportErrorClass,
        authenticationWriteCallCount: Int,
        effectiveDataWriteCallCount: Int,
        uniqueLiveReadingCount: Int,
        quarantinedCommandCount: Int
    ) {
        self.sessionOrdinal = sessionOrdinal
        self.elapsedWholeSeconds = elapsedWholeSeconds
        self.state = state
        self.transportError = transportError
        self.authenticationWriteCallCount = authenticationWriteCallCount
        self.effectiveDataWriteCallCount = effectiveDataWriteCallCount
        self.uniqueLiveReadingCount = uniqueLiveReadingCount
        self.quarantinedCommandCount = quarantinedCommandCount
    }

    public var description: String {
        "Session #\(sessionOrdinal) disconnected unexpectedly after "
            + "\(elapsedWholeSeconds) seconds; state=\(state); "
            + "transport=\(transportError); CoreBluetooth write calls "
            + "E2=\(authenticationWriteCallCount), 0x39=\(effectiveDataWriteCallCount); "
            + "unique live=\(uniqueLiveReadingCount); "
            + "quarantined commands=\(quarantinedCommandCount)."
    }

    /// Sanitized status copied into the manually shareable report. Never use
    /// the transport error's arbitrary localized description here.
    public var failureDescription: String {
        "The sensor disconnected before the bounded probe completed; "
            + "transport=\(transportError)."
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "sessionOrdinal": sessionOrdinal,
                "elapsedWholeSeconds": elapsedWholeSeconds,
                "state": state,
                "transportError": transportError,
                "authenticationWriteCallCount": authenticationWriteCallCount,
                "effectiveDataWriteCallCount": effectiveDataWriteCallCount,
                "uniqueLiveReadingCount": uniqueLiveReadingCount,
                "quarantinedCommandCount": quarantinedCommandCount,
            ],
            displayStyle: .struct
        )
    }
}
