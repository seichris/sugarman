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
    func commitSamples(
        _ samples: [GlucoseSample],
        sessionID: UUID
    ) async throws -> SampleBatchCommitResult

    func insertSample(_ sample: GlucoseSample) async throws
    func sample(sessionID: UUID, sensorIndex: UInt32) async throws -> GlucoseSample?
    func latestSample(sessionID: UUID) async throws -> GlucoseSample?
    func samples(sessionID: UUID) async throws -> [GlucoseSample]
    func allSamples() async throws -> [GlucoseSample]
    func insertSession(_ session: SensorSession) async throws
    func updateSession(_ session: SensorSession) async throws
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
    func insertIdentity(_ identity: SensorIdentity) async throws
    func identities() async throws -> [SensorIdentity]
}
