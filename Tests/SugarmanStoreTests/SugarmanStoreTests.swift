// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import SugarmanStore

#if canImport(SwiftData)
import SwiftData
#endif

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

    @Test func crashRecoveryDuplicateInsertThrowsAndKeepsOriginal() async throws {
        let store = InMemorySugarmanStore()
        let session = UUID()
        let sample = makeSample(session: session, index: 1)
        try await store.insertSample(sample)
        await #expect(throws: StoreError.duplicateSample(SampleKey(sessionID: session, sensorIndex: 1))) {
            try await store.insertSample(makeSample(session: session, index: 1))
        }
        let kept = try await store.sample(sessionID: session, sensorIndex: 1)
        #expect(kept == sample)
        let listed = try await store.samples(sessionID: session)
        #expect(listed.count == 1)
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
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func duplicateSessionThrows() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        await #expect(throws: StoreError.duplicateSession(sessionID)) {
            try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        }
        #expect(try await store.sessionIDs() == [sessionID])
    }

    @Test func fuelingPersistenceUniquenessAndDelete() async throws {
        let store = InMemorySugarmanStore()
        let event = FuelingEvent(timestamp: Date(timeIntervalSince1970: 100), carbohydrateGrams: 25, label: "gel")
        try await store.insertFueling(event)
        await #expect(throws: StoreError.duplicateFueling(event.id)) {
            try await store.insertFueling(event)
        }
        let listed = try await store.fuelingEvents()
        #expect(listed.count == 1)
        #expect(listed.first?.label == "gel")
        #expect(listed.first?.sessionID == nil)
        try await store.deleteFueling(id: event.id)
        #expect(try await store.fuelingEvents().isEmpty)
        try await store.insertFueling(event)
        try await store.deleteAll()
        #expect(try await store.fuelingEvents().isEmpty)
    }

    @Test func deleteSessionRemovesMatchingFuelingKeepsUnscoped() async throws {
        let store = InMemorySugarmanStore()
        let sessionA = UUID()
        let sessionB = UUID()
        try await store.insertSession(SensorSession(id: sessionA, sensorID: UUID()))
        try await store.insertSession(SensorSession(id: sessionB, sensorID: UUID()))
        try await store.insertSample(makeSample(session: sessionA, index: 1))
        let scopedA = FuelingEvent(
            timestamp: Date(timeIntervalSince1970: 10),
            label: "gel-a",
            sessionID: sessionA
        )
        let scopedB = FuelingEvent(
            timestamp: Date(timeIntervalSince1970: 20),
            label: "gel-b",
            sessionID: sessionB
        )
        let unscoped = FuelingEvent(
            timestamp: Date(timeIntervalSince1970: 30),
            label: "unscoped-gel",
            sessionID: nil
        )
        try await store.insertFueling(scopedA)
        try await store.insertFueling(scopedB)
        try await store.insertFueling(unscoped)
        try await store.delete(sessionID: sessionA)
        let remaining = try await store.fuelingEvents()
        #expect(remaining.map(\.label) == ["gel-b", "unscoped-gel"])
        #expect(try await store.sample(sessionID: sessionA, sensorIndex: 1) == nil)
        try await store.deleteAll()
        #expect(try await store.fuelingEvents().isEmpty)
        #expect(try await store.workouts().isEmpty)
        #expect(try await store.identities().isEmpty)
    }

    @Test func demoFixtureInsertsWithoutDuplicate() async throws {
        let store = InMemorySugarmanStore()
        let fixture = SyntheticDemoCatalog.make(.current, now: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.insertSession(fixture.session)
        try await store.insertIdentity(fixture.identity)
        for sample in fixture.samples {
            try await store.insertSample(sample)
        }
        for workout in fixture.workouts {
            try await store.insertWorkout(workout)
        }
        #expect(try await store.samples(sessionID: fixture.session.id).count == 8)
        #expect(try await store.allSamples().allSatisfy { $0.decoderRevision == "synthetic-demo" })
        await #expect(throws: StoreError.duplicateSession(fixture.session.id)) {
            try await store.insertSession(fixture.session)
        }
    }
}

#if canImport(SwiftData)
struct SwiftDataSugarmanStoreTests {
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
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let store = SwiftDataSugarmanStore(modelContainer: container)
        let session = UUID()
        try await store.insertSample(makeSample(session: session, index: 1))
        await #expect(throws: StoreError.duplicateSample(SampleKey(sessionID: session, sensorIndex: 1))) {
            try await store.insertSample(makeSample(session: session, index: 1))
        }
        let kept = try await store.sample(sessionID: session, sensorIndex: 1)
        #expect(kept?.sensorIndex == 1)
        try await store.insertSample(makeSample(session: session, index: 2))
        let latest = try await store.latestSample(sessionID: session)
        #expect(latest?.sensorIndex == 2)
    }

    @Test func crashBetweenInsertsPreservesUniqueness() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let store = SwiftDataSugarmanStore(modelContainer: container)
        let session = UUID()
        let first = makeSample(session: session, index: 1)
        let second = makeSample(session: session, index: 2)
        try await store.insertSample(first)
        let unsaved = ModelContext(container)
        unsaved.insert(GlucoseSampleRecord(from: second))
        let recovered = SwiftDataSugarmanStore(modelContainer: container)
        #expect(try await recovered.sample(sessionID: session, sensorIndex: 1)?.sensorIndex == 1)
        #expect(try await recovered.sample(sessionID: session, sensorIndex: 2) == nil)
        await #expect(throws: StoreError.duplicateSample(SampleKey(sessionID: session, sensorIndex: 1))) {
            try await recovered.insertSample(makeSample(session: session, index: 1))
        }
        try await recovered.insertSample(second)
        #expect(try await recovered.samples(sessionID: session).count == 2)
    }

    @Test func reopeningExistingContainerKeepsSamples() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sugarman-reopen-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sugarman.store")
        let session = UUID()
        let sample = makeSample(session: session, index: 1)
        do {
            let store = SwiftDataSugarmanStore(modelContainer: try SwiftDataSugarmanStore.makeContainer(url: url))
            try await store.insertSession(SensorSession(id: session, sensorID: UUID()))
            try await store.insertSample(sample)
        }
        let reopened = SwiftDataSugarmanStore(modelContainer: try SwiftDataSugarmanStore.makeContainer(url: url))
        #expect(try await reopened.sample(sessionID: session, sensorIndex: 1)?.sensorIndex == 1)
        await #expect(throws: StoreError.duplicateSample(SampleKey(sessionID: session, sensorIndex: 1))) {
            try await reopened.insertSample(makeSample(session: session, index: 1))
        }
        try await reopened.insertSample(makeSample(session: session, index: 2))
        #expect(try await reopened.samples(sessionID: session).count == 2)
    }
}
#endif
