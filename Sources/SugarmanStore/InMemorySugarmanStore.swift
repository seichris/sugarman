// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// Testable store. Uniqueness is enforced on `(sessionID, sensorIndex)`.
public actor InMemorySugarmanStore: SugarmanStoring {
    private var samples: [SampleKey: GlucoseSample] = [:]
    private var sessions: [UUID: SensorSession] = [:]
    private var fueling: [UUID: FuelingEvent] = [:]
    private var workoutRecords: [UUID: WorkoutContext] = [:]
    private var identityRecords: [UUID: SensorIdentity] = [:]

    public init() {}

    public func prepareHistoryRequest(sessionID: UUID, startingAt: UInt32) async throws {
        guard var session = sessions[sessionID] else { throw StoreError.notFound }
        if let committed = session.lastCommittedIndex, startingAt != committed {
            throw StoreError.historyRequestWouldSkipCommittedCursor
        }
        if session.lastCommittedIndex == nil,
           let prepared = session.lastRequestedIndex,
           startingAt != prepared {
            throw StoreError.historyRequestWouldSkipCommittedCursor
        }
        session.lastRequestedIndex = startingAt
        sessions[sessionID] = session
    }

    public func commitSamples(
        _ incomingSamples: [GlucoseSample],
        sessionID: UUID,
        establishingTimeAnchor: SensorTimeAnchor?
    ) async throws -> SampleBatchCommitResult {
        guard var session = sessions[sessionID] else { throw StoreError.notFound }
        let existing = samples.values.filter { $0.sessionID == sessionID }
        let plan = try SampleBatchCommitPlanner.makePlan(
            session: session,
            existingSamples: existing,
            incomingSamples: incomingSamples,
            establishingTimeAnchor: establishingTimeAnchor
        )

        // All validation happens before this copy-on-commit mutation so a
        // conflicting duplicate cannot leave a partial batch behind.
        var nextSamples = samples
        for sample in plan.samplesToInsert {
            nextSamples[sample.id] = sample
        }
        session.lastReceivedIndex = plan.result.lastReceivedIndex
        session.lastCommittedIndex = plan.result.lastCommittedIndex
        if session.sensorTimeAnchor == nil {
            session.sensorTimeAnchor = establishingTimeAnchor
        }
        samples = nextSamples
        sessions[sessionID] = session
        return plan.result
    }

    public func insertSample(_ sample: GlucoseSample) async throws {
        let key = sample.id
        if samples[key] != nil {
            throw StoreError.duplicateSample(key)
        }
        samples[key] = sample
    }

    public func sample(sessionID: UUID, sensorIndex: UInt32) async throws -> GlucoseSample? {
        samples[SampleKey(sessionID: sessionID, sensorIndex: sensorIndex)]
    }

    public func latestSample(sessionID: UUID) async throws -> GlucoseSample? {
        samples.values
            .filter { $0.sessionID == sessionID }
            .max(by: { lhs, rhs in
                if lhs.sensorIndex != rhs.sensorIndex {
                    return lhs.sensorIndex < rhs.sensorIndex
                }
                return lhs.sensorTimestamp < rhs.sensorTimestamp
            })
    }

    public func samples(sessionID: UUID) async throws -> [GlucoseSample] {
        samples.values
            .filter { $0.sessionID == sessionID }
            .sorted { lhs, rhs in
                if lhs.sensorIndex != rhs.sensorIndex {
                    return lhs.sensorIndex < rhs.sensorIndex
                }
                return lhs.sensorTimestamp < rhs.sensorTimestamp
            }
    }

    public func allSamples() async throws -> [GlucoseSample] {
        samples.values.sorted { lhs, rhs in
            if lhs.sessionID != rhs.sessionID {
                return lhs.sessionID.uuidString < rhs.sessionID.uuidString
            }
            return lhs.sensorIndex < rhs.sensorIndex
        }
    }

    public func insertSession(_ session: SensorSession) async throws {
        if sessions[session.id] != nil {
            throw StoreError.duplicateSession(session.id)
        }
        sessions[session.id] = session
    }

    public func updateSession(_ session: SensorSession) async throws {
        guard sessions[session.id] != nil else { throw StoreError.notFound }
        sessions[session.id] = session
    }

    public func setConnection(
        _ connection: ConnectionState,
        sessionID: UUID
    ) async throws {
        guard var session = sessions[sessionID] else {
            throw StoreError.notFound
        }
        session.connection = connection
        sessions[sessionID] = session
    }

    public func session(id: UUID) async throws -> SensorSession? {
        sessions[id]
    }

    public func allSessions() async throws -> [SensorSession] {
        Array(sessions.values).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func delete(sessionID: UUID) async throws {
        guard sessions[sessionID] != nil else { throw StoreError.notFound }
        sessions[sessionID] = nil
        samples = samples.filter { $0.key.sessionID != sessionID }
        // Identities are global and are removed by deleteAll only. Scoped
        // fueling and workouts are deleted with their session.
        fueling = fueling.filter { $0.value.sessionID != sessionID }
        workoutRecords = workoutRecords.filter { $0.value.sessionID != sessionID }
    }

    public func deleteAll() async throws {
        sessions.removeAll()
        samples.removeAll()
        fueling.removeAll()
        workoutRecords.removeAll()
        identityRecords.removeAll()
    }

    public func sessionIDs() async throws -> [UUID] {
        Array(sessions.keys)
    }

    public func insertFueling(_ event: FuelingEvent) async throws {
        if fueling[event.id] != nil {
            throw StoreError.duplicateFueling(event.id)
        }
        fueling[event.id] = event
    }

    public func fuelingEvents() async throws -> [FuelingEvent] {
        fueling.values.sorted { $0.timestamp < $1.timestamp }
    }

    public func deleteFueling(id: UUID) async throws {
        guard fueling[id] != nil else { throw StoreError.notFound }
        fueling[id] = nil
    }

    public func insertWorkout(_ workout: WorkoutContext) async throws {
        if workoutRecords[workout.id] != nil {
            throw StoreError.duplicateWorkout(workout.id)
        }
        workoutRecords[workout.id] = workout
    }

    public func workouts() async throws -> [WorkoutContext] {
        workoutRecords.values.sorted { $0.start < $1.start }
    }

    public func insertIdentity(_ identity: SensorIdentity) async throws {
        if identityRecords[identity.id] != nil {
            throw StoreError.duplicateIdentity(identity.id)
        }
        identityRecords[identity.id] = identity
    }

    public func identities() async throws -> [SensorIdentity] {
        Array(identityRecords.values).sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
