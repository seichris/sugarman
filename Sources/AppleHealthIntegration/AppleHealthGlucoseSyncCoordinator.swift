// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain
import SugarmanStore

public enum AppleHealthSyncPhase: String, Sendable, Equatable {
    case disabled
    case gateClosed
    case authorizationRequired
    case syncing
    case idle
    case failed
}

public struct AppleHealthSyncSnapshot: Sendable, Equatable {
    public let phase: AppleHealthSyncPhase
    public let authorization: AppleHealthAuthorizationState
    public let summary: AppleHealthSyncSummary

    public init(
        phase: AppleHealthSyncPhase,
        authorization: AppleHealthAuthorizationState,
        summary: AppleHealthSyncSummary
    ) {
        self.phase = phase
        self.authorization = authorization
        self.summary = summary
    }
}

public actor AppleHealthGlucoseSyncCoordinator {
    public static let batchSize = 100
    public static let maximumBatchesPerDrain = 5

    private let store: any SugarmanStoring
    private let writer: any AppleHealthGlucoseWritingClient
    private let policy: AppleHealthValidationPolicy
    private let now: @Sendable () -> Date
    private var activeDrain: Task<AppleHealthSyncSnapshot, Never>?
    private var queuedRetry: Bool?
    private var enabledDuringDrain = false

    public init(
        store: any SugarmanStoring,
        writer: any AppleHealthGlucoseWritingClient,
        policy: AppleHealthValidationPolicy = .closed,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.writer = writer
        self.policy = policy
        self.now = now
    }

    public var isEligibilityGateOpen: Bool { policy.isGateOpen }

    public func setEnabled(_ enabled: Bool) {
        enabledDuringDrain = enabled
    }

    public func requestAuthorization() async throws -> AppleHealthAuthorizationState {
        guard policy.isGateOpen else { return .unavailable }
        try await writer.requestWriteAuthorization()
        return await writer.authorizationState()
    }

    public func snapshot(isEnabled: Bool) async -> AppleHealthSyncSnapshot {
        let summary = try? await store.appleHealthSyncSummary()
        if !policy.isGateOpen {
            return AppleHealthSyncSnapshot(
                phase: .gateClosed,
                authorization: .unavailable,
                summary: summary ?? .empty
            )
        }
        let authorization = isEnabled ? await writer.authorizationState() : .unavailable
        let phase: AppleHealthSyncPhase
        if !isEnabled { phase = .disabled }
        else if authorization != .authorized { phase = .authorizationRequired }
        else if summary == nil || (summary?.retryableFailureCount ?? 0) > 0 { phase = .failed }
        else { phase = .idle }
        return AppleHealthSyncSnapshot(
            phase: phase,
            authorization: authorization,
            summary: summary ?? .empty
        )
    }

    public func drain(
        isEnabled: Bool,
        forceRetry: Bool = false
    ) async -> AppleHealthSyncSnapshot {
        enabledDuringDrain = isEnabled
        guard isEnabled, policy.isGateOpen else { return await snapshot(isEnabled: isEnabled) }
        if let activeDrain {
            queuedRetry = (queuedRetry ?? false) || forceRetry
            return await activeDrain.value
        }

        // Reserve ownership before the first suspension, including authorization.
        let task = Task { await drainQueuedBatches(forceRetry: forceRetry) }
        activeDrain = task
        return await task.value
    }

    private func drainQueuedBatches(forceRetry: Bool) async -> AppleHealthSyncSnapshot {
        var retry = forceRetry
        while true {
            let result = await drainOnce(forceRetry: retry)
            if enabledDuringDrain, let queued = queuedRetry {
                queuedRetry = nil
                retry = queued
            } else {
                queuedRetry = nil
                activeDrain = nil
                return result
            }
        }
    }

    private func drainOnce(forceRetry: Bool) async -> AppleHealthSyncSnapshot {
        guard enabledDuringDrain else { return await snapshot(isEnabled: false) }
        let authorization = await writer.authorizationState()
        guard authorization == .authorized else {
            return await snapshot(isEnabled: enabledDuringDrain)
        }

        do {
            let earliestDate = try await writer.earliestPermittedSampleDate()
            for _ in 0..<Self.maximumBatchesPerDrain {
                guard enabledDuringDrain else { break }
                let attemptDate = now()
                let candidates = try await store.appleHealthSyncCandidates(
                    limit: Self.batchSize,
                    now: attemptDate,
                    ignoringRetryDeadline: forceRetry
                )
                guard !candidates.isEmpty else { break }

                var payloads: [AppleHealthGlucosePayload] = []
                var blocked: [SampleKey] = []
                for candidate in candidates {
                    do {
                        payloads.append(
                            try policy.payload(
                                for: candidate.sample,
                                earliestPermittedDate: earliestDate,
                                now: attemptDate
                            )
                        )
                    } catch {
                        blocked.append(candidate.sample.id)
                    }
                }
                if !blocked.isEmpty {
                    try await store.recordAppleHealthFailure(
                        blocked,
                        reason: .ineligible,
                        retryable: false,
                        retryAfter: nil,
                        at: attemptDate
                    )
                }
                guard !payloads.isEmpty else { continue }
                let keys = payloads.map(\.key)
                try await store.recordAppleHealthAttempt(keys, at: attemptDate)
                guard enabledDuringDrain else { break }
                do {
                    try await writer.save(payloads)
                    try await store.recordAppleHealthSuccess(
                        keys,
                        version: AppleHealthGlucosePayload.syncVersion,
                        at: now()
                    )
                } catch {
                    let highestAttempt = candidates.map(\.attemptCount).max() ?? 0
                    let baseDelay = min(
                        3_600.0,
                        60.0 * pow(2.0, Double(highestAttempt))
                    )
                    let jitterBucket = Double(keys.first?.sensorIndex ?? 0)
                        .truncatingRemainder(dividingBy: 21)
                    let jitter = 0.8 + jitterBucket / 50.0
                    let delay = min(3_600.0, baseDelay * jitter)
                    try await store.recordAppleHealthFailure(
                        keys,
                        reason: .healthKit,
                        retryable: true,
                        retryAfter: attemptDate.addingTimeInterval(delay),
                        at: attemptDate
                    )
                    break
                }
            }
            return await snapshot(isEnabled: enabledDuringDrain)
        } catch {
            return AppleHealthSyncSnapshot(
                phase: .failed,
                authorization: authorization,
                summary: (try? await store.appleHealthSyncSummary()) ?? .empty
            )
        }
    }
}
