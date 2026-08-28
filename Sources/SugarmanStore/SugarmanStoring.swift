// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public enum StoreError: Error, Sendable, Equatable {
    case duplicateSample(SampleKey)
    case notFound
    case persistenceUnavailable
}

public protocol SugarmanStoring: Sendable {
    func insertSample(_ sample: GlucoseSample) async throws
    func sample(sessionID: UUID, sensorIndex: UInt32) async throws -> GlucoseSample?
    func latestSample(sessionID: UUID) async throws -> GlucoseSample?
    func insertSession(_ session: SensorSession) async throws
    func session(id: UUID) async throws -> SensorSession?
    func delete(sessionID: UUID) async throws
    func deleteAll() async throws
    func sessionIDs() async throws -> [UUID]
}
