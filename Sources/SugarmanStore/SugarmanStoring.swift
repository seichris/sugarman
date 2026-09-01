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
}

public protocol SugarmanStoring: Sendable {
    func insertSample(_ sample: GlucoseSample) async throws
    func sample(sessionID: UUID, sensorIndex: UInt32) async throws -> GlucoseSample?
    func latestSample(sessionID: UUID) async throws -> GlucoseSample?
    func samples(sessionID: UUID) async throws -> [GlucoseSample]
    func allSamples() async throws -> [GlucoseSample]
    func insertSession(_ session: SensorSession) async throws
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
