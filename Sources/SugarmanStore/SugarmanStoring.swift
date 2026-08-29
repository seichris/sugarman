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
        }
    }
}

public protocol SugarmanStoring: Sendable {
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
