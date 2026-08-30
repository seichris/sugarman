// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// Fail-closed store used when the persistent container cannot be opened.
/// It prevents the UI from appearing to save data into a temporary database.
public struct UnavailableSugarmanStore: SugarmanStoring {
    public init() {}

    private func unavailable() throws -> Never { throw StoreError.persistenceUnavailable }

    public func insertSample(_: GlucoseSample) async throws { try unavailable() }
    public func sample(sessionID _: UUID, sensorIndex _: UInt32) async throws -> GlucoseSample? { try unavailable() }
    public func latestSample(sessionID _: UUID) async throws -> GlucoseSample? { try unavailable() }
    public func samples(sessionID _: UUID) async throws -> [GlucoseSample] { try unavailable() }
    public func allSamples() async throws -> [GlucoseSample] { try unavailable() }
    public func insertSession(_: SensorSession) async throws { try unavailable() }
    public func updateSession(_: SensorSession) async throws { try unavailable() }
    public func session(id _: UUID) async throws -> SensorSession? { try unavailable() }
    public func allSessions() async throws -> [SensorSession] { try unavailable() }
    public func delete(sessionID _: UUID) async throws { try unavailable() }
    public func deleteAll() async throws { try unavailable() }
    public func sessionIDs() async throws -> [UUID] { try unavailable() }
    public func insertFueling(_: FuelingEvent) async throws { try unavailable() }
    public func fuelingEvents() async throws -> [FuelingEvent] { try unavailable() }
    public func deleteFueling(id _: UUID) async throws { try unavailable() }
    public func insertWorkout(_: WorkoutContext) async throws { try unavailable() }
    public func workouts() async throws -> [WorkoutContext] { try unavailable() }
    public func insertIdentity(_: SensorIdentity) async throws { try unavailable() }
    public func identities() async throws -> [SensorIdentity] { try unavailable() }
}
