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

/// Allowlisted origin for one fail-closed protocol rejection. The enum has no
/// packet, command, characteristic, peripheral, sensor, or arbitrary-text case.
public enum GS3ProtocolRejectionOrigin: String, Sendable, Equatable, CaseIterable {
    case inboundClassification
    case writeCallbackInvariant
    case stateInvariant
    case requestInvariant
}

/// Coarse frame shape derived only from the notification byte count.
public enum GS3ProtocolFrameCategory: String, Sendable, Equatable {
    case unavailable
    case missing
    case controlCandidate
    case notificationCandidate
    case other

    package static func classify(byteCount: Int) -> Self {
        switch byteCount {
        case 0: .missing
        case 5: .controlCandidate
        case 6...: .notificationCandidate
        default: .other
        }
    }
}

/// Payload-free timing window for a rejection. These values intentionally omit
/// request indexes, command bytes, material, and device identity.
public enum GS3ProtocolTimingWindow: String, Sendable, Equatable {
    case unavailable
    case connectionSetup
    case authentication
    case authenticated
    case historyRequestPreparing
    case historyWritePending
    case historyResponse
    case streaming
    case disconnecting
}

/// Privacy-safe metadata for the first protocol rejection in one connection.
///
/// Frame length is bounded before it reaches descriptions or reflection. A
/// value above the CoreBluetooth attribute maximum is represented as `512+`.
public struct GS3ProtocolRejection:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public static let maximumReportedFrameByteCount = 512

    public let origin: GS3ProtocolRejectionOrigin
    public let frameCategory: GS3ProtocolFrameCategory
    public let frameByteCount: Int?
    public let frameByteCountWasCapped: Bool
    public let timingWindow: GS3ProtocolTimingWindow

    public init(
        origin: GS3ProtocolRejectionOrigin,
        frameCategory: GS3ProtocolFrameCategory = .unavailable,
        frameByteCount: Int? = nil,
        timingWindow: GS3ProtocolTimingWindow = .unavailable
    ) {
        self.origin = origin
        self.frameCategory = frameCategory
        if let frameByteCount, frameByteCount >= 0 {
            self.frameByteCount = min(
                frameByteCount,
                Self.maximumReportedFrameByteCount
            )
            self.frameByteCountWasCapped =
                frameByteCount > Self.maximumReportedFrameByteCount
        } else {
            self.frameByteCount = nil
            self.frameByteCountWasCapped = false
        }
        self.timingWindow = timingWindow
    }

    package init(
        origin: GS3ProtocolRejectionOrigin,
        frameByteCount: Int,
        timingWindow: GS3ProtocolTimingWindow
    ) {
        self.init(
            origin: origin,
            frameCategory: .classify(byteCount: frameByteCount),
            frameByteCount: frameByteCount,
            timingWindow: timingWindow
        )
    }

    public var description: String {
        let length: String
        if let frameByteCount {
            length = frameByteCountWasCapped ? "\(frameByteCount)+" : "\(frameByteCount)"
        } else {
            length = "unavailable"
        }
        return "origin=\(origin.rawValue), frame=\(frameCategory.rawValue), "
            + "bytes=\(length), window=\(timingWindow.rawValue)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "origin": origin.rawValue,
                "frameCategory": frameCategory.rawValue,
                "frameByteCount": frameByteCount.map(String.init) ?? "unavailable",
                "frameByteCountWasCapped": frameByteCountWasCapped,
                "timingWindow": timingWindow.rawValue,
            ],
            displayStyle: .struct
        )
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
    case historyPreambleObserved
    case protocolRejected
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
    public let protocolRejection: GS3ProtocolRejection?
    public let reconnectAttempt: Int
    public let authenticationRequestCount: Int
    public let historyRequestCount: Int
    public let historyPreambleCount: Int
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
        protocolRejection: GS3ProtocolRejection? = nil,
        reconnectAttempt: Int = 0,
        authenticationRequestCount: Int = 0,
        historyRequestCount: Int = 0,
        historyPreambleCount: Int = 0,
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
        self.protocolRejection = protocolRejection
        self.reconnectAttempt = reconnectAttempt
        self.authenticationRequestCount = authenticationRequestCount
        self.historyRequestCount = historyRequestCount
        self.historyPreambleCount = historyPreambleCount
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
            + "historyPreambles=\(historyPreambleCount), "
            + "inserted=\(insertedSampleCount), duplicates=\(duplicateSampleCount), "
            + "gapRanges=\(gapRangeCount)"
        if let disconnectReason {
            text += ", transport=\(disconnectReason)"
        }
        if let protocolRejection {
            text += ", rejection={\(protocolRejection)}"
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
                "protocolRejection": protocolRejection?.description ?? "none",
                "reconnectAttempt": reconnectAttempt,
                "authenticationRequestCount": authenticationRequestCount,
                "historyRequestCount": historyRequestCount,
                "historyPreambleCount": historyPreambleCount,
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
