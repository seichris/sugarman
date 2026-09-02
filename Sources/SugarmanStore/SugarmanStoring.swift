// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public enum StoreError: Error, Sendable, Equatable {
    case duplicateSample(SampleKey)
    case duplicateSession(UUID)
    case duplicateFueling(UUID)
    case duplicateWorkout(UUID)
    case duplicateIdentity(UUID)
    case notFound
    case persistenceUnavailable
    case invalidSensorIndex(Int64)
    case sampleSessionMismatch
    case conflictingSample(SampleKey)
    case historyRequestNotPrepared
    case historyRequestWouldSkipCommittedCursor
    case conflictingTimeAnchor
    case missingTimeAnchor
    case timeAnchorRequiresMatchingSample
    case sampleTimestampDoesNotMatchAnchor
    case incompleteTimeAnchor
}

extension StoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .duplicateSample:
            "A glucose sample with the same sensor index already exists."
        case .duplicateSession:
            "This sensor session already exists."
        case .duplicateFueling:
            "This fueling event already exists."
        case .duplicateWorkout:
            "This workout already exists."
        case .duplicateIdentity:
            "This sensor identity already exists."
        case .notFound:
            "The requested local record was not found."
        case .persistenceUnavailable:
            "Persistent local storage is unavailable. No data will be saved until this is resolved."
        case .invalidSensorIndex(let value):
            "Stored sensor index \(value) is invalid."
        case .sampleSessionMismatch:
            "A glucose batch contained a sample from a different sensor session."
        case .conflictingSample:
            "Two glucose samples with the same durable key disagree."
        case .historyRequestNotPrepared:
            "The history request was not durably prepared before samples arrived."
        case .historyRequestWouldSkipCommittedCursor:
            "The history request would skip the durable backfill cursor."
        case .conflictingTimeAnchor:
            "The incoming sensor-time anchor conflicts with durable state."
        case .missingTimeAnchor:
            "A V3 sample batch requires a durable sensor-time anchor."
        case .timeAnchorRequiresMatchingSample:
            "A new sensor-time anchor requires its matching sample in the same transaction."
        case .sampleTimestampDoesNotMatchAnchor:
            "A decoded sample timestamp does not match the durable sensor-time anchor."
        case .incompleteTimeAnchor:
            "Stored sensor-time anchor data is incomplete."
        }
    }
}

public protocol SugarmanStoring: Sendable {
    /// Durably records the inclusive history-request start before a request can
    /// be sent. Once prepared, a reconnect may repeat that start but may not
    /// advance past the contiguous committed cursor.
    func prepareHistoryRequest(sessionID: UUID, startingAt: UInt32) async throws

    /// Atomically inserts a decoded batch and advances the session's received
    /// and contiguous committed cursors. Existing equivalent keys are counted
    /// as duplicates; conflicting values fail closed without a partial commit.
    /// A first live batch may establish the session's time anchor in the same
    /// transaction so a crash cannot persist samples without their mapping.
    func commitSamples(
        _ samples: [GlucoseSample],
        sessionID: UUID,
        establishingTimeAnchor: SensorTimeAnchor?
    ) async throws -> SampleBatchCommitResult

    func insertSample(_ sample: GlucoseSample) async throws
    func sample(sessionID: UUID, sensorIndex: UInt32) async throws -> GlucoseSample?
    func latestSample(sessionID: UUID) async throws -> GlucoseSample?
    func samples(sessionID: UUID) async throws -> [GlucoseSample]
    func allSamples() async throws -> [GlucoseSample]
    func insertSession(_ session: SensorSession) async throws
    func updateSession(_ session: SensorSession) async throws
    /// Atomically updates only the UI connection projection, preserving
    /// concurrently persisted lifecycle, cursor, and time-anchor fields.
    func setConnection(
        _ connection: ConnectionState,
        sessionID: UUID
    ) async throws
    func session(id: UUID) async throws -> SensorSession?
    func allSessions() async throws -> [SensorSession]
    func delete(sessionID: UUID) async throws
    func deleteAll() async throws
    func sessionIDs() async throws -> [UUID]
    func insertFueling(_ event: FuelingEvent) async throws
    func fuelingEvents() async throws -> [FuelingEvent]
    func deleteFueling(id: UUID) async throws
    func insertWorkout(_ workout: WorkoutContext) async throws
    func workouts() async throws -> [WorkoutContext]
    func insertWorkoutPlan(_ plan: WorkoutPlan) async throws
    func workoutPlans() async throws -> [WorkoutPlan]
    func updateWorkoutPlan(_ plan: WorkoutPlan) async throws
    func deleteWorkoutPlan(id: UUID) async throws
    func insertIdentity(_ identity: SensorIdentity) async throws
    func identities() async throws -> [SensorIdentity]
}

extension SugarmanStoring {
    public func commitSamples(
        _ samples: [GlucoseSample],
        sessionID: UUID
    ) async throws -> SampleBatchCommitResult {
        try await commitSamples(
            samples,
            sessionID: sessionID,
            establishingTimeAnchor: nil
        )
    }
}
