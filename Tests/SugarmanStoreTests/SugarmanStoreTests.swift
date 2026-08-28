// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import SugarmanStore

struct SugarmanStoreTests {
    func makeSample(session: UUID, index: UInt32) -> GlucoseSample {
        GlucoseSample(
            sessionID: session,
            sensorIndex: index,
            sensorTimestamp: Date(timeIntervalSince1970: Double(index)),
            receiptTimestamp: Date(timeIntervalSince1970: Double(index) + 1),
            milligramsPerDeciliter: 100,
            decoderRevision: "none"
        )
    }

    @Test func uniquenessOnSessionAndIndex() async throws {
        let store = InMemorySugarmanStore()
        let session = UUID()
        try await store.insertSample(makeSample(session: session, index: 1))
        await #expect(throws: StoreError.duplicateSample(SampleKey(sessionID: session, sensorIndex: 1))) {
            try await store.insertSample(makeSample(session: session, index: 1))
        }
        try await store.insertSample(makeSample(session: session, index: 2))
        try await store.insertSample(makeSample(session: UUID(), index: 1))
        let latest = try await store.latestSample(sessionID: session)
        #expect(latest?.sensorIndex == 2)
    }

    @Test func deleteSessionAndDeleteAll() async throws {
        let store = InMemorySugarmanStore()
        let sessionA = UUID()
        let sessionB = UUID()
        try await store.insertSession(SensorSession(id: sessionA, sensorID: UUID()))
        try await store.insertSession(SensorSession(id: sessionB, sensorID: UUID()))
        try await store.insertSample(makeSample(session: sessionA, index: 1))
        try await store.insertSample(makeSample(session: sessionB, index: 1))
        try await store.delete(sessionID: sessionA)
        #expect(try await store.sample(sessionID: sessionA, sensorIndex: 1) == nil)
        #expect(try await store.sample(sessionID: sessionB, sensorIndex: 1) != nil)
        try await store.deleteAll()
        #expect(try await store.sessionIDs().isEmpty)
    }
}
