// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// Testable store. Uniqueness is enforced on `(sessionID, sensorIndex)`.
public actor InMemorySugarmanStore: SugarmanStoring {
    private var samples: [SampleKey: GlucoseSample] = [:]
    private var sessions: [UUID: SensorSession] = [:]

    public init() {}

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

    public func insertSession(_ session: SensorSession) async throws {
        sessions[session.id] = session
    }

    public func session(id: UUID) async throws -> SensorSession? {
        sessions[id]
    }

    public func delete(sessionID: UUID) async throws {
        sessions[sessionID] = nil
        samples = samples.filter { $0.key.sessionID != sessionID }
    }

    public func deleteAll() async throws {
        sessions.removeAll()
        samples.removeAll()
    }

    public func sessionIDs() async throws -> [UUID] {
        Array(sessions.keys)
    }
}
