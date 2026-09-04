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
    private var isDraining = false
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
        let summary = (try? await store.appleHealthSyncSummary()) ?? .empty
        if !policy.isGateOpen {
            return AppleHealthSyncSnapshot(
                phase: .gateClosed,
                authorization: .unavailable,
                summary: summary
            )
        }
        let authorization = await writer.authorizationState()
        let phase: AppleHealthSyncPhase
        if !isEnabled { phase = .disabled }
        else if authorization != .authorized { phase = .authorizationRequired }
        else { phase = .idle }
        return AppleHealthSyncSnapshot(
            phase: phase,
            authorization: authorization,
            summary: summary
        )
    }

    public func drain(
        isEnabled: Bool,
        forceRetry: Bool = false
    ) async -> AppleHealthSyncSnapshot {
        enabledDuringDrain = isEnabled
        guard !isDraining else { return await snapshot(isEnabled: isEnabled) }
        guard policy.isGateOpen else { return await snapshot(isEnabled: isEnabled) }
        guard isEnabled else { return await snapshot(isEnabled: false) }
        let authorization = await writer.authorizationState()
        guard authorization == .authorized else {
            return await snapshot(isEnabled: true)
        }

        isDraining = true
        defer { isDraining = false }
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
            return AppleHealthSyncSnapshot(
                phase: .idle,
                authorization: .authorized,
                summary: try await store.appleHealthSyncSummary()
            )
        } catch {
            return AppleHealthSyncSnapshot(
                phase: .failed,
                authorization: authorization,
                summary: (try? await store.appleHealthSyncSummary()) ?? .empty
            )
        }
    }
}
