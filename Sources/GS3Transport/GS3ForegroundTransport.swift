// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol
import GS3Session
import SensorOwnership
import SugarmanDomain

public enum GS3ForegroundCommandKind: String, Sendable, Equatable {
    case authentication
    case effectiveData
}

/// Typed events from the foreground transport. Packet bytes, characteristic
/// objects, peripheral identity, and arbitrary error text never cross this
/// boundary.
package enum GS3ForegroundTransportEvent: Sendable, Equatable {
    case connected
    case servicesDiscovered
    case characteristicsDiscovered
    case notificationSubscriptionEnabled
    case authenticationWriteAcknowledged
    case authenticationAccepted
    case authenticationRejected
    case historyWriteAcknowledged
    case historyPreambleObserved
    case protocolRejected(GS3ProtocolRejection)
    case historyAcknowledged
    case glucoseBatch(V3GlucoseBatch, receivedAt: Date)
    case transportDisconnected
    case disconnected(GS3DisconnectReason)
}

extension GS3ForegroundTransportEvent:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    package var description: String {
        switch self {
        case .connected: "connected"
        case .servicesDiscovered: "servicesDiscovered"
        case .characteristicsDiscovered: "characteristicsDiscovered"
        case .notificationSubscriptionEnabled: "notificationSubscriptionEnabled"
        case .authenticationWriteAcknowledged: "authenticationWriteAcknowledged"
        case .authenticationAccepted: "authenticationAccepted"
        case .authenticationRejected: "authenticationRejected"
        case .historyWriteAcknowledged: "historyWriteAcknowledged"
        case .historyPreambleObserved: "historyPreambleObserved"
        case .protocolRejected(let rejection): "protocolRejected(\(rejection))"
        case .historyAcknowledged: "historyAcknowledged"
        case .glucoseBatch(let batch, _):
            "glucoseBatch(source: \(batch.source), recordCount: \(batch.records.count), payload: omitted)"
        case .transportDisconnected: "transportDisconnected"
        case .disconnected(let reason): "disconnected(\(reason))"
        }
    }

    package var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(
            self,
            children: ["event": description],
            displayStyle: .enum
        )
    }
}

/// The only live transport surface available to the production coordinator.
/// There is deliberately no scan, raw frame, characteristic, arbitrary
/// command, activation, binding, reset, or write method.
package protocol GS3ForegroundTransporting: Sendable {
    func installEventHandler(
        _ handler: @escaping @Sendable (GS3ForegroundTransportEvent) -> Void
    ) async
    func connectKnownPeripheral() async
    func ensureDisconnected() async
    func discoverGS3Service() async
    func discoverGS3Characteristics() async
    func subscribeToGS3Notifications() async
    func authenticateConnection() async
    func requestEffectiveData(_ plan: HistoryRequestPlan) async
}

package protocol GS3SensorOwnerLeaseHandle: AnyObject, Sendable {
    var isActive: Bool { get }
    func release()
}

package protocol GS3SensorOwnershipProviding: Sendable {
    func acquire() throws -> any GS3SensorOwnerLeaseHandle
}

private final class SharedGS3SensorOwnerLeaseHandle:
    GS3SensorOwnerLeaseHandle, @unchecked Sendable
{
    private let lease: SensorOwnerLease

    init(lease: SensorOwnerLease) {
        self.lease = lease
    }

    var isActive: Bool { lease.isActive }

    func release() {
        lease.release()
    }
}

package struct SharedGS3SensorOwnershipProvider: GS3SensorOwnershipProviding {
    package init() {}

    package func acquire() throws -> any GS3SensorOwnerLeaseHandle {
        SharedGS3SensorOwnerLeaseHandle(
            lease: try SharedSensorOwnerLease.acquire()
        )
    }
}

package protocol GS3ReconnectScheduling: Sendable {
    func schedule(
        _ schedule: GS3ReconnectSchedule,
        action: @escaping @Sendable () -> Void
    ) async
    func cancel(token: UInt64) async
    func cancelAll() async
}

package actor TaskGS3ReconnectScheduler: GS3ReconnectScheduling {
    private var tasks: [UInt64: Task<Void, Never>] = [:]

    package init() {}

    package func schedule(
        _ schedule: GS3ReconnectSchedule,
        action: @escaping @Sendable () -> Void
    ) {
        tasks[schedule.token]?.cancel()
        let nanoseconds = UInt64(
            (schedule.delaySeconds * 1_000_000_000).rounded(.up)
        )
        tasks[schedule.token] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
            await self?.remove(token: schedule.token)
        }
    }

    package func cancel(token: UInt64) {
        tasks.removeValue(forKey: token)?.cancel()
    }

    package func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
    }

    private func remove(token: UInt64) {
        tasks[token] = nil
    }
}

public enum GS3ForegroundCoordinatorFailure: String, Sendable, Equatable {
    case sessionUnavailable
    case sessionNotLive
    case unsupportedProtocol
    case ownershipUnavailable
    case persistence
    case protocolViolation
    case stateMachine
}

public struct GS3ForegroundSessionCallbacks: Sendable {
    public var onConnection: @Sendable (ConnectionState) -> Void
    public var onLifecycleEvent: @Sendable (GS3LifecycleEvent) -> Void
    public var onSamplesCommitted: @Sendable (GS3BatchCommitSummary) -> Void
    public var onCommandAcknowledged: @Sendable (GS3ForegroundCommandKind) -> Void
    public var onFailure: @Sendable (GS3ForegroundCoordinatorFailure) -> Void

    public init(
        onConnection: @escaping @Sendable (ConnectionState) -> Void = { _ in },
        onLifecycleEvent: @escaping @Sendable (GS3LifecycleEvent) -> Void = { _ in },
        onSamplesCommitted: @escaping @Sendable (GS3BatchCommitSummary) -> Void = { _ in },
        onCommandAcknowledged: @escaping @Sendable (GS3ForegroundCommandKind) -> Void = { _ in },
        onFailure: @escaping @Sendable (GS3ForegroundCoordinatorFailure) -> Void = { _ in }
    ) {
        self.onConnection = onConnection
        self.onLifecycleEvent = onLifecycleEvent
        self.onSamplesCommitted = onSamplesCommitted
        self.onCommandAcknowledged = onCommandAcknowledged
        self.onFailure = onFailure
    }
}

public enum GS3ForegroundConfigurationError: Error, Sendable, Equatable {
    case invalidSessionOrdinal
    case invalidBufferedRecordLimit
}

public struct GS3ForegroundSessionConfiguration:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public static let inferredSampleIntervalSeconds: TimeInterval = 60
    public static let inferredTimeMappingRevision =
        "owned-mainland-gs3-observed-cadence-v1"

    public let sessionID: UUID
    public let sessionOrdinal: UInt64
    public let captureBackedStart: CaptureBackedHistoryStart
    public let maximumBufferedRecordCount: Int

    public init(
        sessionID: UUID,
        sessionOrdinal: UInt64,
        captureBackedStart: CaptureBackedHistoryStart,
        maximumBufferedRecordCount: Int = 32_768
    ) throws {
        guard sessionOrdinal > 0 else {
            throw GS3ForegroundConfigurationError.invalidSessionOrdinal
        }
        guard (1...65_536).contains(maximumBufferedRecordCount) else {
            throw GS3ForegroundConfigurationError.invalidBufferedRecordLimit
        }
        self.sessionID = sessionID
        self.sessionOrdinal = sessionOrdinal
        self.captureBackedStart = captureBackedStart
        self.maximumBufferedRecordCount = maximumBufferedRecordCount
    }

    public var description: String {
        "GS3ForegroundSessionConfiguration(sessionID: redacted, sessionOrdinal: "
            + "#\(sessionOrdinal), captureStart: redacted, bufferLimit: "
            + "\(maximumBufferedRecordCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "sessionID": "redacted",
                "sessionOrdinal": sessionOrdinal,
                "captureBackedStart": "redacted",
                "maximumBufferedRecordCount": maximumBufferedRecordCount,
            ],
            displayStyle: .struct
        )
    }
}

public protocol GS3ForegroundSessionControlling: Sendable {
    func start() async throws
    func stop() async
    func foregroundEnded() async
    func currentPhase() async -> GS3ForegroundPhase
}
