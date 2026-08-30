// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanStore

public enum GS3ForegroundPhase: String, Sendable, Equatable, CaseIterable {
    case idle
    case acquiringOwnership
    case connecting
    case discoveringServices
    case discoveringCharacteristics
    case subscribing
    case authenticating
    case loadingHistoryPlan
    case preparingHistoryRequest
    case requestingHistory
    case synchronizing
    case live
    case backoff
    case disconnecting
    case stopped
}

public enum GS3DisconnectReason: Sendable, Equatable {
    case linkLoss
    case timeout
    case coreBluetooth(code: Int)
    case bluetoothUnavailable
    case permissionDenied
    case authenticationRejected
    case protocolViolation
    case otherRedacted

    public var isRetryable: Bool {
        switch self {
        case .linkLoss, .timeout, .coreBluetooth, .bluetoothUnavailable, .otherRedacted:
            true
        case .permissionDenied, .authenticationRejected, .protocolViolation:
            false
        }
    }
}

extension GS3DisconnectReason: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .linkLoss: "link loss"
        case .timeout: "timeout"
        case .coreBluetooth(let code): "CoreBluetooth code \(code)"
        case .bluetoothUnavailable: "Bluetooth unavailable"
        case .permissionDenied: "permission denied"
        case .authenticationRejected: "authentication rejected"
        case .protocolViolation: "protocol violation"
        case .otherRedacted: "other error redacted"
        }
    }

    public var debugDescription: String { description }
}

public enum GS3LifecycleKind: String, Sendable, Equatable {
    case sessionStarted
    case ownershipAcquired
    case ownershipDenied
    case connectionAttemptStarted
    case transportConnected
    case notificationsSubscribed
    case authenticationRequested
    case authenticationAccepted
    case historyPlanLoaded
    case historyRequestPrepared
    case historyRequested
    case batchCommitted
    case synchronizationCompleted
    case integrityFailure
    case persistenceFailed
    case disconnectRequested
    case transportDisconnected
    case disconnected
    case reconnectScheduled
    case stopped
}

/// Payload-free event safe for local lifecycle diagnostics.
///
/// It intentionally has no sensor/session UUID, peripheral name, owner value,
/// history index, packet body, glucose value, or arbitrary error string.
public struct GS3LifecycleEvent:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let sessionOrdinal: UInt64
    public let connectionOrdinal: UInt64
    public let elapsedWholeSeconds: Int
    public let phase: GS3ForegroundPhase
    public let kind: GS3LifecycleKind
    public let disconnectReason: GS3DisconnectReason?
    public let reconnectAttempt: Int
    public let authenticationRequestCount: Int
    public let historyRequestCount: Int
    public let insertedSampleCount: Int
    public let duplicateSampleCount: Int
    public let gapRangeCount: Int

    public init(
        sessionOrdinal: UInt64,
        connectionOrdinal: UInt64,
        elapsedWholeSeconds: Int,
        phase: GS3ForegroundPhase,
        kind: GS3LifecycleKind,
        disconnectReason: GS3DisconnectReason? = nil,
        reconnectAttempt: Int = 0,
        authenticationRequestCount: Int = 0,
        historyRequestCount: Int = 0,
        insertedSampleCount: Int = 0,
        duplicateSampleCount: Int = 0,
        gapRangeCount: Int = 0
    ) {
        self.sessionOrdinal = sessionOrdinal
        self.connectionOrdinal = connectionOrdinal
        self.elapsedWholeSeconds = max(0, elapsedWholeSeconds)
        self.phase = phase
        self.kind = kind
        self.disconnectReason = disconnectReason
        self.reconnectAttempt = reconnectAttempt
        self.authenticationRequestCount = authenticationRequestCount
        self.historyRequestCount = historyRequestCount
        self.insertedSampleCount = insertedSampleCount
        self.duplicateSampleCount = duplicateSampleCount
        self.gapRangeCount = gapRangeCount
    }

    public var description: String {
        var text = "GS3 lifecycle session #\(sessionOrdinal), connection #"
            + "\(connectionOrdinal), elapsed=\(elapsedWholeSeconds)s, "
            + "phase=\(phase.rawValue), event=\(kind.rawValue), "
            + "reconnectAttempt=\(reconnectAttempt), authRequests="
            + "\(authenticationRequestCount), historyRequests=\(historyRequestCount), "
            + "inserted=\(insertedSampleCount), duplicates=\(duplicateSampleCount), "
            + "gapRanges=\(gapRangeCount)"
        if let disconnectReason {
            text += ", transport=\(disconnectReason)"
        }
        return text + "."
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "sessionOrdinal": sessionOrdinal,
                "connectionOrdinal": connectionOrdinal,
                "elapsedWholeSeconds": elapsedWholeSeconds,
                "phase": phase.rawValue,
                "kind": kind.rawValue,
                "disconnectReason": disconnectReason?.description ?? "none",
                "reconnectAttempt": reconnectAttempt,
                "authenticationRequestCount": authenticationRequestCount,
                "historyRequestCount": historyRequestCount,
                "insertedSampleCount": insertedSampleCount,
                "duplicateSampleCount": duplicateSampleCount,
                "gapRangeCount": gapRangeCount,
            ],
            displayStyle: .struct
        )
    }
}

public struct GS3BatchCommitSummary: Sendable, Equatable {
    public let insertedCount: Int
    public let duplicateCount: Int
    public let gapRangeCount: Int

    public init(insertedCount: Int, duplicateCount: Int, gapRangeCount: Int) {
        self.insertedCount = max(0, insertedCount)
        self.duplicateCount = max(0, duplicateCount)
        self.gapRangeCount = max(0, gapRangeCount)
    }

    public init(_ result: SampleBatchCommitResult) {
        self.init(
            insertedCount: result.insertedCount,
            duplicateCount: result.duplicateCount,
            gapRangeCount: result.gapRangeCount
        )
    }
}
