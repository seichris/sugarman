// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public enum GS3ReconnectPolicyError: Error, Sendable, Equatable {
    case invalidDelays
}

/// Fixed, deterministic foreground reconnect schedule.
///
/// The schedule is finite, nondecreasing, and capped at five minutes per
/// attempt. Jitter belongs in a later physically tested adapter; the pure
/// reducer remains exactly reproducible in host tests.
public struct GS3ReconnectPolicy: Sendable, Equatable {
    public static let foregroundDefault = GS3ReconnectPolicy(
        validatedDelays: [1, 2, 4, 8, 16]
    )

    public let delaysSeconds: [TimeInterval]

    public init(delaysSeconds: [TimeInterval]) throws {
        guard !delaysSeconds.isEmpty,
              delaysSeconds.count <= 16,
              delaysSeconds.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 300 }),
              zip(delaysSeconds, delaysSeconds.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw GS3ReconnectPolicyError.invalidDelays
        }
        self.delaysSeconds = delaysSeconds
    }

    private init(validatedDelays: [TimeInterval]) {
        delaysSeconds = validatedDelays
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt > 0, attempt <= delaysSeconds.count else { return nil }
        return delaysSeconds[attempt - 1]
    }
}

public struct GS3ReconnectSchedule: Sendable, Equatable {
    public let token: UInt64
    public let attempt: Int
    public let delaySeconds: TimeInterval

    public init(token: UInt64, attempt: Int, delaySeconds: TimeInterval) {
        self.token = token
        self.attempt = attempt
        self.delaySeconds = delaySeconds
    }
}

public enum GS3ForegroundStopReason: String, Sendable, Equatable {
    case userStopped
    case foregroundEnded
    case ownershipUnavailable
    case reconnectExhausted
    case terminalTransportFailure
    case integrityFailure
    case persistenceFailure
}

public enum GS3ForegroundError: Error, Sendable, Equatable {
    case invalidTransition(from: GS3ForegroundPhase)
    case mismatchedHistoryPlan
    case persistenceFailure
}

extension GS3ForegroundError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let phase):
            "Invalid foreground GS3 transition from \(phase.rawValue)."
        case .mismatchedHistoryPlan:
            "The durably prepared history request did not match the loaded plan."
        case .persistenceFailure:
            "Local persistence failed; sensor access stopped."
        }
    }
}

public enum GS3ForegroundInput: Sendable, Equatable {
    case start
    case ownershipAcquired
    case ownershipDenied
    case connected
    case servicesDiscovered
    case characteristicsDiscovered
    case notificationSubscriptionEnabled
    case authenticationAccepted
    case authenticationRejected
    case protocolRejectionObserved(GS3ProtocolRejection)
    case protocolViolation
    case historyPlanLoaded(HistoryRequestPlan)
    case historyRequestDurablyPrepared(HistoryRequestPlan)
    case historyPreambleObserved
    case historyAcknowledged
    case batchCommitted(GS3BatchCommitSummary)
    case synchronizationCompleted
    case persistenceFailed
    case transportDisconnected
    case disconnected(GS3DisconnectReason)
    case reconnectDelayElapsed(token: UInt64)
    case foregroundEnded
    case stop
}

extension GS3ForegroundInput: CustomStringConvertible {
    public var description: String {
        switch self {
        case .start: "start"
        case .ownershipAcquired: "ownershipAcquired"
        case .ownershipDenied: "ownershipDenied"
        case .connected: "connected"
        case .servicesDiscovered: "servicesDiscovered"
        case .characteristicsDiscovered: "characteristicsDiscovered"
        case .notificationSubscriptionEnabled: "notificationSubscriptionEnabled"
        case .authenticationAccepted: "authenticationAccepted"
        case .authenticationRejected: "authenticationRejected"
        case .protocolRejectionObserved(let rejection):
            "protocolRejectionObserved(\(rejection))"
        case .protocolViolation: "protocolViolation"
        case .historyPlanLoaded: "historyPlanLoaded(index: redacted)"
        case .historyRequestDurablyPrepared: "historyRequestDurablyPrepared(index: redacted)"
        case .historyPreambleObserved: "historyPreambleObserved"
        case .historyAcknowledged: "historyAcknowledged"
        case .batchCommitted: "batchCommitted(payload: omitted)"
        case .synchronizationCompleted: "synchronizationCompleted"
        case .persistenceFailed: "persistenceFailed(error: redacted)"
        case .transportDisconnected: "transportDisconnected"
        case .disconnected(let reason): "disconnected(\(reason))"
        case .reconnectDelayElapsed: "reconnectDelayElapsed"
        case .foregroundEnded: "foregroundEnded"
        case .stop: "stop"
        }
    }
}

/// Pure effects. No case carries a packet body, sensor identifier, private
/// material, arbitrary raw write, activation, binding, reset, or secret-key
/// operation. Authentication and history are typed integration intents only;
/// a separately guarded transport decides whether they can be executed.
public enum GS3ForegroundEffect: Sendable, Equatable {
    case acquireOwnership
    case releaseOwnership
    case connect
    case ensureTransportDisconnected
    case discoverServices
    case discoverCharacteristics
    case subscribeToNotifications
    case authenticateConnection
    case loadHistoryPlan
    case prepareHistoryRequest(HistoryRequestPlan)
    case requestHistory(HistoryRequestPlan)
    case scheduleReconnect(GS3ReconnectSchedule)
    case cancelReconnect(token: UInt64)
    case publishConnection(ConnectionState)
    case record(GS3LifecycleEvent)
    case fail(GS3ForegroundError)
}

extension GS3ForegroundEffect: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .acquireOwnership: "acquireOwnership"
        case .releaseOwnership: "releaseOwnership"
        case .connect: "connect"
        case .ensureTransportDisconnected: "ensureTransportDisconnected"
        case .discoverServices: "discoverServices"
        case .discoverCharacteristics: "discoverCharacteristics"
        case .subscribeToNotifications: "subscribeToNotifications"
        case .authenticateConnection: "authenticateConnection(typed)"
        case .loadHistoryPlan: "loadHistoryPlan"
        case .prepareHistoryRequest(let plan): "prepareHistoryRequest(\(plan))"
        case .requestHistory(let plan): "requestHistory(\(plan))"
        case .scheduleReconnect(let schedule):
            "scheduleReconnect(attempt: \(schedule.attempt), delay: \(schedule.delaySeconds))"
        case .cancelReconnect: "cancelReconnect"
        case .publishConnection(let state): "publishConnection(\(state.rawValue))"
        case .record(let event): "record(\(event))"
        case .fail(let error): "fail(\(error.localizedDescription))"
        }
    }

    public var debugDescription: String { description }
}

/// Deterministic, foreground-only production lifecycle reducer.
///
/// Ownership is acquired before connection, kept through a bounded reconnect
/// sequence, and released on every terminal path. Every connection repeats
/// discovery, notification subscription, authentication, and one durably
/// prepared history request before it can become live.
public struct GS3ForegroundSessionMachine:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let sessionOrdinal: UInt64
    public let reconnectPolicy: GS3ReconnectPolicy
    public private(set) var phase: GS3ForegroundPhase = .idle
    public private(set) var connectionOrdinal: UInt64 = 0
    public private(set) var reconnectAttempt: Int = 0
    public private(set) var hasOwnership = false
    public private(set) var authenticationRequestCount = 0
    public private(set) var historyRequestCount = 0
    public private(set) var historyPreambleCount = 0
    public private(set) var stopReason: GS3ForegroundStopReason?

    private var nextReconnectToken: UInt64 = 0
    private var pendingReconnect: GS3ReconnectSchedule?
    private var pendingHistoryPlan: HistoryRequestPlan?
    private var pendingTerminalFailure: GS3ForegroundError?
    private var protocolRejectionReported = false
    private var insertedSampleCount = 0
    private var duplicateSampleCount = 0
    private var gapRangeCount = 0

    public init(
        sessionOrdinal: UInt64,
        reconnectPolicy: GS3ReconnectPolicy = .foregroundDefault
    ) {
        self.sessionOrdinal = sessionOrdinal
        self.reconnectPolicy = reconnectPolicy
    }

    public var presentationConnectionState: ConnectionState {
        switch phase {
        case .connecting:
            .connecting
        case .discoveringServices, .discoveringCharacteristics, .subscribing,
             .authenticating, .loadingHistoryPlan, .preparingHistoryRequest,
             .requestingHistory, .synchronizing:
            .connected
        case .live:
            .subscribed
        case .idle, .acquiringOwnership, .backoff, .disconnecting, .stopped:
            .disconnected
        }
    }

    public mutating func send(
        _ input: GS3ForegroundInput,
        elapsedWholeSeconds: Int = 0
    ) -> [GS3ForegroundEffect] {
        let elapsed = max(0, elapsedWholeSeconds)
        switch input {
        case .start:
            guard phase == .idle else {
                return invalidTransition()
            }
            resetForNewSession()
            phase = .acquiringOwnership
            return [
                .publishConnection(.disconnected),
                record(.sessionStarted, elapsed: elapsed),
                .acquireOwnership,
            ]

        case .ownershipAcquired:
            guard phase == .acquiringOwnership else {
                if !hasOwnership && (phase == .idle || phase == .stopped) {
                    // Acquisition may complete just after foreground stop. The
                    // adapter now holds a real lease even though the reducer
                    // never entered the owned state, so unwind it explicitly.
                    return [.releaseOwnership] + invalidTransition()
                }
                return invalidTransition()
            }
            hasOwnership = true
            let acquired = record(.ownershipAcquired, elapsed: elapsed)
            return [acquired] + beginConnection(elapsed: elapsed)

        case .ownershipDenied:
            guard phase == .acquiringOwnership else { return invalidTransition() }
            phase = .stopped
            stopReason = .ownershipUnavailable
            return [
                .publishConnection(.disconnected),
                record(.ownershipDenied, elapsed: elapsed),
                record(.stopped, elapsed: elapsed),
            ]

        case .connected:
            guard phase == .connecting else {
                if !isConnectionPhase(phase) {
                    // A canceled CoreBluetooth connect can still report success.
                    // Never leave that late transport attached outside a
                    // connection phase.
                    return [.ensureTransportDisconnected] + invalidTransition()
                }
                return invalidTransition()
            }
            phase = .discoveringServices
            return [
                .publishConnection(.connected),
                record(.transportConnected, elapsed: elapsed),
                .discoverServices,
            ]

        case .servicesDiscovered:
            guard phase == .discoveringServices else { return invalidTransition() }
            phase = .discoveringCharacteristics
            return [.discoverCharacteristics]

        case .characteristicsDiscovered:
            guard phase == .discoveringCharacteristics else { return invalidTransition() }
            phase = .subscribing
            return [.subscribeToNotifications]

        case .notificationSubscriptionEnabled:
            guard phase == .subscribing, authenticationRequestCount == 0 else {
                return invalidTransition()
            }
            phase = .authenticating
            authenticationRequestCount = 1
            return [
                record(.notificationsSubscribed, elapsed: elapsed),
                record(.authenticationRequested, elapsed: elapsed),
                .authenticateConnection,
            ]

        case .authenticationAccepted:
            guard phase == .authenticating, authenticationRequestCount == 1 else {
                return invalidTransition()
            }
            phase = .loadingHistoryPlan
            return [
                record(.authenticationAccepted, elapsed: elapsed),
                .loadHistoryPlan,
            ]

        case .authenticationRejected:
            guard phase == .authenticating else { return invalidTransition() }
            return stopAfterTerminalFailure(
                reason: .authenticationRejected,
                elapsed: elapsed
            )

        case .protocolRejectionObserved(let rejection):
            guard phase != .idle, phase != .stopped else { return [] }
            guard !protocolRejectionReported else { return [] }
            protocolRejectionReported = true
            return [
                record(
                    .protocolRejected,
                    rejection: rejection,
                    elapsed: elapsed
                )
            ]

        case .protocolViolation:
            if isConnectionPhase(phase) {
                return stopAfterTerminalFailure(
                    reason: .protocolViolation,
                    elapsed: elapsed
                )
            }
            if phase == .acquiringOwnership || phase == .backoff {
                return [record(.integrityFailure, elapsed: elapsed)]
                    + stop(.integrityFailure, elapsed: elapsed)
            }
            return invalidTransition()

        case .historyPlanLoaded(let plan):
            guard phase == .loadingHistoryPlan else { return invalidTransition() }
            pendingHistoryPlan = plan
            phase = .preparingHistoryRequest
            return [
                record(.historyPlanLoaded, elapsed: elapsed),
                .prepareHistoryRequest(plan),
            ]

        case .historyRequestDurablyPrepared(let plan):
            guard phase == .preparingHistoryRequest else { return invalidTransition() }
            guard pendingHistoryPlan == plan else {
                return stopAfterIntegrityFailure(
                    .mismatchedHistoryPlan,
                    elapsed: elapsed
                )
            }
            guard historyRequestCount == 0 else { return invalidTransition() }
            historyRequestCount = 1
            phase = .requestingHistory
            return [
                record(.historyRequestPrepared, elapsed: elapsed),
                record(.historyRequested, elapsed: elapsed),
                .requestHistory(plan),
            ]

        case .historyPreambleObserved:
            guard phase == .requestingHistory,
                  historyRequestCount == 1,
                  historyPreambleCount == 0 else {
                return invalidTransition()
            }
            historyPreambleCount = 1
            return [record(.historyPreambleObserved, elapsed: elapsed)]

        case .historyAcknowledged:
            guard phase == .requestingHistory, historyRequestCount == 1 else {
                return invalidTransition()
            }
            phase = .synchronizing
            return []

        case .batchCommitted(let summary):
            guard phase == .requestingHistory || phase == .synchronizing || phase == .live else {
                return invalidTransition()
            }
            insertedSampleCount = saturatingAdd(insertedSampleCount, summary.insertedCount)
            duplicateSampleCount = saturatingAdd(duplicateSampleCount, summary.duplicateCount)
            gapRangeCount = summary.gapRangeCount
            return [record(.batchCommitted, elapsed: elapsed)]

        case .synchronizationCompleted:
            guard phase == .synchronizing else { return invalidTransition() }
            phase = .live
            reconnectAttempt = 0
            pendingHistoryPlan = nil
            return [
                .publishConnection(.subscribed),
                record(.synchronizationCompleted, elapsed: elapsed),
            ]

        case .persistenceFailed:
            if isConnectionPhase(phase) {
                return stopAfterPersistenceFailure(elapsed: elapsed)
            }
            if phase == .acquiringOwnership || phase == .backoff {
                return stop(.persistenceFailure, elapsed: elapsed)
            }
            return invalidTransition()

        case .transportDisconnected:
            guard phase == .disconnecting else {
                if phase == .idle || phase == .backoff || phase == .stopped {
                    return []
                }
                return invalidTransition()
            }
            return finishControlledStop(elapsed: elapsed)

        case .disconnected(let reason):
            return handleDisconnect(reason: reason, elapsed: elapsed)

        case .reconnectDelayElapsed(let token):
            guard phase == .backoff,
                  let pendingReconnect,
                  pendingReconnect.token == token else {
                // Timer cancellation races are expected. A stale callback must
                // never start another connection or schedule another timer.
                return []
            }
            self.pendingReconnect = nil
            return beginConnection(elapsed: elapsed)

        case .foregroundEnded:
            return stop(.foregroundEnded, elapsed: elapsed)

        case .stop:
            return stop(.userStopped, elapsed: elapsed)
        }
    }

    private mutating func beginConnection(elapsed: Int) -> [GS3ForegroundEffect] {
        guard hasOwnership else { return invalidTransition() }
        connectionOrdinal &+= 1
        authenticationRequestCount = 0
        historyRequestCount = 0
        historyPreambleCount = 0
        protocolRejectionReported = false
        pendingHistoryPlan = nil
        pendingTerminalFailure = nil
        insertedSampleCount = 0
        duplicateSampleCount = 0
        gapRangeCount = 0
        phase = .connecting
        return [
            .publishConnection(.connecting),
            record(.connectionAttemptStarted, elapsed: elapsed),
            .connect,
        ]
    }

    private mutating func handleDisconnect(
        reason: GS3DisconnectReason,
        elapsed: Int
    ) -> [GS3ForegroundEffect] {
        if phase == .disconnecting {
            return finishControlledStop(reason: reason, elapsed: elapsed)
        }
        if phase == .backoff || phase == .idle || phase == .stopped {
            return []
        }
        guard isConnectionPhase(phase) else { return invalidTransition() }

        var effects: [GS3ForegroundEffect] = [
            .publishConnection(.disconnected),
            record(.disconnected, reason: reason, elapsed: elapsed),
            .ensureTransportDisconnected,
        ]
        pendingHistoryPlan = nil

        guard reason.isRetryable else {
            phase = .stopped
            stopReason = .terminalTransportFailure
            if hasOwnership {
                hasOwnership = false
                effects.append(.releaseOwnership)
            }
            effects.append(record(.stopped, reason: reason, elapsed: elapsed))
            return effects
        }

        let nextAttempt = reconnectAttempt + 1
        guard let delay = reconnectPolicy.delay(forAttempt: nextAttempt) else {
            phase = .stopped
            stopReason = .reconnectExhausted
            if hasOwnership {
                hasOwnership = false
                effects.append(.releaseOwnership)
            }
            effects.append(record(.stopped, reason: reason, elapsed: elapsed))
            return effects
        }

        reconnectAttempt = nextAttempt
        nextReconnectToken &+= 1
        let schedule = GS3ReconnectSchedule(
            token: nextReconnectToken,
            attempt: nextAttempt,
            delaySeconds: delay
        )
        pendingReconnect = schedule
        phase = .backoff
        effects.append(record(.reconnectScheduled, reason: reason, elapsed: elapsed))
        effects.append(.scheduleReconnect(schedule))
        return effects
    }

    private mutating func stopAfterTerminalFailure(
        reason: GS3DisconnectReason,
        elapsed: Int
    ) -> [GS3ForegroundEffect] {
        beginControlledStop(
            reason: .terminalTransportFailure,
            lifecycleKind: .disconnectRequested,
            disconnectReason: reason,
            elapsed: elapsed
        )
    }

    private mutating func stopAfterIntegrityFailure(
        _ error: GS3ForegroundError,
        elapsed: Int
    ) -> [GS3ForegroundEffect] {
        beginControlledStop(
            reason: .integrityFailure,
            failure: error,
            lifecycleKind: .integrityFailure,
            elapsed: elapsed
        )
    }

    private mutating func stopAfterPersistenceFailure(
        elapsed: Int
    ) -> [GS3ForegroundEffect] {
        beginControlledStop(
            reason: .persistenceFailure,
            failure: .persistenceFailure,
            lifecycleKind: .persistenceFailed,
            elapsed: elapsed
        )
    }

    private mutating func beginControlledStop(
        reason: GS3ForegroundStopReason,
        failure: GS3ForegroundError? = nil,
        lifecycleKind: GS3LifecycleKind = .disconnectRequested,
        disconnectReason: GS3DisconnectReason? = nil,
        elapsed: Int
    ) -> [GS3ForegroundEffect] {
        stopReason = reason
        pendingHistoryPlan = nil
        pendingTerminalFailure = failure
        phase = .disconnecting
        return [
            .publishConnection(.disconnected),
            record(lifecycleKind, reason: disconnectReason, elapsed: elapsed),
            .ensureTransportDisconnected,
        ]
    }

    private mutating func finishControlledStop(
        reason: GS3DisconnectReason? = nil,
        elapsed: Int
    ) -> [GS3ForegroundEffect] {
        var effects: [GS3ForegroundEffect] = [
            record(
                reason == nil ? .transportDisconnected : .disconnected,
                reason: reason,
                elapsed: elapsed
            )
        ]
        let failure = pendingTerminalFailure
        pendingTerminalFailure = nil
        phase = .stopped
        if hasOwnership {
            hasOwnership = false
            effects.append(.releaseOwnership)
        }
        effects.append(record(.stopped, reason: reason, elapsed: elapsed))
        if let failure {
            effects.append(.fail(failure))
        }
        return effects
    }

    private mutating func stop(
        _ reason: GS3ForegroundStopReason,
        elapsed: Int
    ) -> [GS3ForegroundEffect] {
        var effects: [GS3ForegroundEffect] = []
        if let pendingReconnect {
            effects.append(.cancelReconnect(token: pendingReconnect.token))
            self.pendingReconnect = nil
        }
        if phase == .disconnecting {
            return effects
        }
        if isConnectionPhase(phase) {
            return effects + beginControlledStop(reason: reason, elapsed: elapsed)
        }
        if hasOwnership {
            hasOwnership = false
            effects.append(.releaseOwnership)
        }
        phase = .stopped
        stopReason = reason
        effects.append(.publishConnection(.disconnected))
        effects.append(record(.stopped, elapsed: elapsed))
        return effects
    }

    private mutating func resetForNewSession() {
        connectionOrdinal = 0
        reconnectAttempt = 0
        hasOwnership = false
        authenticationRequestCount = 0
        historyRequestCount = 0
        historyPreambleCount = 0
        protocolRejectionReported = false
        stopReason = nil
        pendingReconnect = nil
        pendingHistoryPlan = nil
        pendingTerminalFailure = nil
        insertedSampleCount = 0
        duplicateSampleCount = 0
        gapRangeCount = 0
    }

    private func record(
        _ kind: GS3LifecycleKind,
        reason: GS3DisconnectReason? = nil,
        rejection: GS3ProtocolRejection? = nil,
        elapsed: Int
    ) -> GS3ForegroundEffect {
        .record(
            GS3LifecycleEvent(
                sessionOrdinal: sessionOrdinal,
                connectionOrdinal: connectionOrdinal,
                elapsedWholeSeconds: elapsed,
                phase: phase,
                kind: kind,
                disconnectReason: reason,
                protocolRejection: rejection,
                reconnectAttempt: reconnectAttempt,
                authenticationRequestCount: authenticationRequestCount,
                historyRequestCount: historyRequestCount,
                historyPreambleCount: historyPreambleCount,
                insertedSampleCount: insertedSampleCount,
                duplicateSampleCount: duplicateSampleCount,
                gapRangeCount: gapRangeCount
            )
        )
    }

    private func invalidTransition() -> [GS3ForegroundEffect] {
        [.fail(.invalidTransition(from: phase))]
    }

    private func isConnectionPhase(_ phase: GS3ForegroundPhase) -> Bool {
        switch phase {
        case .connecting, .discoveringServices, .discoveringCharacteristics,
             .subscribing, .authenticating, .loadingHistoryPlan,
             .preparingHistoryRequest, .requestingHistory, .synchronizing, .live:
            true
        case .idle, .acquiringOwnership, .backoff, .disconnecting, .stopped:
            false
        }
    }

    private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : result
    }

    public var description: String {
        "GS3ForegroundSessionMachine(session: #\(sessionOrdinal), connection: "
            + "#\(connectionOrdinal), phase: \(phase.rawValue), ownsSensor: "
            + "\(hasOwnership), authRequests: \(authenticationRequestCount), "
            + "historyRequests: \(historyRequestCount), historyPreambles: "
            + "\(historyPreambleCount))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "sessionOrdinal": sessionOrdinal,
                "connectionOrdinal": connectionOrdinal,
                "phase": phase.rawValue,
                "hasOwnership": hasOwnership,
                "authenticationRequestCount": authenticationRequestCount,
                "historyRequestCount": historyRequestCount,
                "historyPreambleCount": historyPreambleCount,
                "reconnectAttempt": reconnectAttempt,
            ],
            displayStyle: .struct
        )
    }
}
