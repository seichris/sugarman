// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import SugarmanStore

private func testTimeAnchor(
    index: UInt32,
    timestamp: Date
) throws -> SensorTimeAnchor {
    try SensorTimeAnchor(
        sensorIndex: index,
        timestamp: timestamp,
        sampleIntervalSeconds: 60,
        mappingRevision: "synthetic-test-v1"
    )
}

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

    @Test func appleHealthDeliveryLedgerPersistsRetriesAndSuccess() async throws {
        let store = InMemorySugarmanStore()
        let session = UUID()
        let sample = makeSample(session: session, index: 1)
        let now = Date(timeIntervalSince1970: 100)
        try await store.insertSample(sample)
        #expect(
            try await store.appleHealthSyncCandidates(
                limit: 100,
                now: now,
                ignoringRetryDeadline: false
            ).map(\.sample.id) == [sample.id]
        )

        try await store.recordAppleHealthAttempt([sample.id], at: now)
        try await store.recordAppleHealthFailure(
            [sample.id],
            reason: .healthKit,
            retryable: true,
            retryAfter: now.addingTimeInterval(60),
            at: now
        )
        #expect(
            try await store.appleHealthSyncCandidates(
                limit: 100,
                now: now.addingTimeInterval(30),
                ignoringRetryDeadline: false
            ).isEmpty
        )
        #expect(
            try await store.appleHealthSyncCandidates(
                limit: 100,
                now: now,
                ignoringRetryDeadline: true
            ).first?.attemptCount == 1
        )

        try await store.recordAppleHealthSuccess([sample.id], version: 1, at: now)
        let summary = try await store.appleHealthSyncSummary()
        #expect(summary.syncedCount == 1)
        #expect(summary.pendingCount == 0)
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

    @Test func sessionCanBeUpdatedWithoutLosingFields() async throws {
        let store = InMemorySugarmanStore()
        let session = SensorSession(id: UUID(), sensorID: UUID())
        try await store.insertSession(session)
        var updated = session
        updated.activatedAt = Date(timeIntervalSince1970: 100)
        updated.lastCommittedIndex = 42
        updated.lifecycle = .live
        updated.connection = .subscribed
        updated.sensorErrorCode = "E-test"
        try await store.updateSession(updated)
        #expect(try await store.session(id: session.id) == updated)
        await #expect(throws: StoreError.notFound) {
            try await store.updateSession(SensorSession(sensorID: UUID()))
        }
    }

    @Test func atomicConnectionProjectionPreservesDurableSessionFields() async throws {
        let store = InMemorySugarmanStore()
        let anchor = try testTimeAnchor(
            index: 42,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let session = SensorSession(
            id: UUID(),
            sensorID: UUID(),
            lastRequestedIndex: 40,
            lastReceivedIndex: 42,
            lastCommittedIndex: 42,
            sensorTimeAnchor: anchor,
            protocolVariant: .v3AES,
            lifecycle: .live,
            connection: .disconnected
        )
        try await store.insertSession(session)

        try await store.setConnection(.subscribed, sessionID: session.id)

        var expected = session
        expected.connection = .subscribed
        #expect(try await store.session(id: session.id) == expected)
        await #expect(throws: StoreError.notFound) {
            try await store.setConnection(.connected, sessionID: UUID())
        }
    }

    @Test func unavailableStoreFailsClosed() async {
        let store = UnavailableSugarmanStore()
        await #expect(throws: StoreError.persistenceUnavailable) {
            try await store.allSamples()
        }
        await #expect(throws: StoreError.persistenceUnavailable) {
            try await store.insertFueling(FuelingEvent(timestamp: Date(), label: "gel"))
        }
        await #expect(throws: StoreError.persistenceUnavailable) {
            try await store.prepareHistoryRequest(sessionID: UUID(), startingAt: 1)
        }
        await #expect(throws: StoreError.persistenceUnavailable) {
            try await store.commitSamples([], sessionID: UUID())
        }
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

    @Test func workoutPlansPersistUniquelyAndDelete() async throws {
        let store = InMemorySugarmanStore()
        let plan = WorkoutPlanCatalog.dayOne150KmRide
        try await store.insertWorkoutPlan(plan)
        await #expect(throws: StoreError.duplicateWorkout(plan.id)) {
            try await store.insertWorkoutPlan(plan)
        }
        let listed = try await store.workoutPlans()
        #expect(listed == [plan])
        try await store.deleteWorkoutPlan(id: plan.id)
        #expect(try await store.workoutPlans().isEmpty)
    }

    @Test func deletingMissingEntitiesFailsInsteadOfReportingSuccess() async {
        let store = InMemorySugarmanStore()
        await #expect(throws: StoreError.notFound) {
            try await store.delete(sessionID: UUID())
        }
        await #expect(throws: StoreError.notFound) {
            try await store.deleteFueling(id: UUID())
        }
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
        let workoutA = WorkoutContext(sessionID: sessionA, start: Date(timeIntervalSince1970: 10), activityType: "run")
        let workoutB = WorkoutContext(sessionID: sessionB, start: Date(timeIntervalSince1970: 20), activityType: "ride")
        try await store.insertFueling(scopedA)
        try await store.insertFueling(scopedB)
        try await store.insertFueling(unscoped)
        try await store.insertWorkout(workoutA)
        try await store.insertWorkout(workoutB)
        try await store.delete(sessionID: sessionA)
        let remaining = try await store.fuelingEvents()
        #expect(remaining.map(\.label) == ["gel-b", "unscoped-gel"])
        #expect(try await store.sample(sessionID: sessionA, sensorIndex: 1) == nil)
        #expect(try await store.workouts() == [workoutB])
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

    @Test func atomicBatchCommitDeduplicatesAndPinsAContiguousGap() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        await #expect(throws: StoreError.historyRequestNotPrepared) {
            try await store.commitSamples([], sessionID: sessionID)
        }
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 10)

        let first = try await store.commitSamples(
            [
                makeSample(session: sessionID, index: 10),
                makeSample(session: sessionID, index: 12),
            ],
            sessionID: sessionID
        )
        #expect(first.insertedCount == 2)
        #expect(first.duplicateCount == 0)
        #expect(first.gapRangeCount == 1)
        #expect(first.lastReceivedIndex == 12)
        #expect(first.lastCommittedIndex == 10)
        #expect(try await store.session(id: sessionID)?.lastCommittedIndex == 10)

        let emptyRetry = try await store.commitSamples([], sessionID: sessionID)
        #expect(emptyRetry.insertedCount == 0)
        #expect(emptyRetry.duplicateCount == 0)
        #expect(emptyRetry.gapRangeCount == 1)
        #expect(emptyRetry.lastReceivedIndex == 12)
        #expect(emptyRetry.lastCommittedIndex == 10)

        // The next request overlaps the committed cursor. Existing records are
        // ignored only when their decoded sensor content agrees.
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 10)
        var semanticDuplicate = makeSample(session: sessionID, index: 10)
        semanticDuplicate.receiptTimestamp = .distantFuture
        semanticDuplicate.source = .live
        semanticDuplicate.decoderRevision = "synthetic-next-revision"
        let repaired = try await store.commitSamples(
            [
                semanticDuplicate,
                makeSample(session: sessionID, index: 11),
            ],
            sessionID: sessionID
        )
        #expect(repaired.insertedCount == 1)
        #expect(repaired.duplicateCount == 1)
        #expect(repaired.gapRangeCount == 0)
        #expect(repaired.lastCommittedIndex == 12)
        #expect(try await store.samples(sessionID: sessionID).map(\.sensorIndex) == [10, 11, 12])
    }

    @Test func conflictingDuplicateRejectsTheWholeBatchWithoutCursorAdvance() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 5)
        let original = makeSample(session: sessionID, index: 5)
        _ = try await store.commitSamples([original], sessionID: sessionID)

        var conflict = original
        conflict.milligramsPerDeciliter = 200
        await #expect(throws: StoreError.conflictingSample(original.id)) {
            try await store.commitSamples(
                [makeSample(session: sessionID, index: 6), conflict],
                sessionID: sessionID
            )
        }
        #expect(try await store.samples(sessionID: sessionID) == [original])
        #expect(try await store.session(id: sessionID)?.lastReceivedIndex == 5)
        #expect(try await store.session(id: sessionID)?.lastCommittedIndex == 5)
    }

    @Test func historyPreparationCannotMovePastDurableState() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 100)
        await #expect(throws: StoreError.historyRequestWouldSkipCommittedCursor) {
            try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 101)
        }
        _ = try await store.commitSamples(
            [makeSample(session: sessionID, index: 100)],
            sessionID: sessionID
        )
        await #expect(throws: StoreError.historyRequestWouldSkipCommittedCursor) {
            try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 101)
        }
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 100)
    }

    @Test func batchCommitDiagnosticsDoNotPrintSensorIndexes() {
        let result = SampleBatchCommitResult(
            insertedCount: 2,
            duplicateCount: 1,
            gapRangeCount: 1,
            lastReceivedIndex: 424_242,
            lastCommittedIndex: 424_200
        )
        var dumped = ""
        dump(result, to: &dumped)
        for text in [result.description, String(reflecting: result), dumped] {
            #expect(!text.contains("424242"))
            #expect(!text.contains("424200"))
        }
    }

    @Test func firstTimeAnchorAndSamplesCommitAtomicallyAndConflictsFailClosed() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 10)
        let anchor = try testTimeAnchor(
            index: 11,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var first = makeSample(session: sessionID, index: 10)
        first.sensorTimestamp = try anchor.timestamp(for: 10)
        var second = makeSample(session: sessionID, index: 11)
        second.sensorTimestamp = anchor.timestamp

        await #expect(throws: StoreError.timeAnchorRequiresMatchingSample) {
            try await store.commitSamples(
                [],
                sessionID: sessionID,
                establishingTimeAnchor: anchor
            )
        }
        #expect(try await store.session(id: sessionID)?.sensorTimeAnchor == nil)

        let committed = try await store.commitSamples(
            [first, second],
            sessionID: sessionID,
            establishingTimeAnchor: anchor
        )
        #expect(committed.lastCommittedIndex == 11)
        #expect(try await store.session(id: sessionID)?.sensorTimeAnchor == anchor)

        let conflicting = try testTimeAnchor(
            index: 11,
            timestamp: anchor.timestamp.addingTimeInterval(1)
        )
        await #expect(throws: StoreError.conflictingTimeAnchor) {
            try await store.commitSamples(
                [],
                sessionID: sessionID,
                establishingTimeAnchor: conflicting
            )
        }
        var wrongTimestamp = makeSample(session: sessionID, index: 12)
        wrongTimestamp.sensorTimestamp = anchor.timestamp
        await #expect(throws: StoreError.sampleTimestampDoesNotMatchAnchor) {
            try await store.commitSamples([wrongTimestamp], sessionID: sessionID)
        }
        #expect(try await store.samples(sessionID: sessionID) == [first, second])
        let text = "\(anchor) \(String(reflecting: anchor))"
        #expect(!text.contains("1800000000"))
        #expect(!text.contains("11"))
    }

    @Test func v3BatchCannotCommitWithoutATimeAnchor() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(
            SensorSession(
                id: sessionID,
                sensorID: UUID(),
                protocolVariant: .v3AES,
                lifecycle: .live
            )
        )
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 20)

        await #expect(throws: StoreError.missingTimeAnchor) {
            try await store.commitSamples(
                [makeSample(session: sessionID, index: 20)],
                sessionID: sessionID
            )
        }
        #expect(try await store.samples(sessionID: sessionID).isEmpty)
    }

    @Test func v3CannotEstablishAnchorOverLegacyUnanchoredSamples() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(
            SensorSession(
                id: sessionID,
                sensorID: UUID(),
                protocolVariant: .v3AES,
                lifecycle: .live
            )
        )
        try await store.insertSample(makeSample(session: sessionID, index: 19))
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 20)
        let anchor = try testTimeAnchor(
            index: 20,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var anchored = makeSample(session: sessionID, index: 20)
        anchored.sensorTimestamp = anchor.timestamp

        await #expect(throws: StoreError.missingTimeAnchor) {
            try await store.commitSamples(
                [anchored],
                sessionID: sessionID,
                establishingTimeAnchor: anchor
            )
        }
        #expect(try await store.session(id: sessionID)?.sensorTimeAnchor == nil)
        #expect(try await store.samples(sessionID: sessionID).map(\.sensorIndex) == [19])
    }

    @Test func v3CommitRejectsCorruptDurableCursorBeforeMutation() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        let anchor = try testTimeAnchor(
            index: 102,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await store.insertSession(
            SensorSession(
                id: sessionID,
                sensorID: UUID(),
                lastRequestedIndex: 100,
                lastReceivedIndex: 102,
                lastCommittedIndex: 102,
                sensorTimeAnchor: anchor,
                protocolVariant: .v3AES,
                lifecycle: .live
            )
        )
        var first = makeSample(session: sessionID, index: 100)
        first.sensorTimestamp = try anchor.timestamp(for: 100)
        var gapped = makeSample(session: sessionID, index: 102)
        gapped.sensorTimestamp = anchor.timestamp
        try await store.insertSample(first)
        try await store.insertSample(gapped)
        var incoming = makeSample(session: sessionID, index: 103)
        incoming.sensorTimestamp = try anchor.timestamp(for: 103)

        await #expect(throws: StoreError.incompleteTimeAnchor) {
            try await store.commitSamples([incoming], sessionID: sessionID)
        }
        #expect(try await store.sample(sessionID: sessionID, sensorIndex: 103) == nil)
        #expect(try await store.session(id: sessionID)?.lastCommittedIndex == 102)
    }

    @Test @MainActor func localDiagnosticLogStoreAppendsAndSummarizesJSONLines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sugarman-diagnostics-\(UUID().uuidString)",
            isDirectory: true
        )
        let url = directory.appendingPathComponent("diagnostics.jsonl")
        let log = LocalDiagnosticLogStore(fileURL: url)
        let longValue = String(repeating: "x", count: 240) + "\nnext-line"

        try log.append(
            LocalDiagnosticLogEntry(
                timestamp: Date(timeIntervalSince1970: 1),
                category: .workout,
                event: .workoutPlanSelected,
                attributes: ["phase": "day-1", "note": longValue]
            )
        )
        try log.append(
            LocalDiagnosticLogEntry(
                timestamp: Date(timeIntervalSince1970: 2),
                category: .sensor,
                event: .sensorSamplesCommitted,
                attributes: ["inserted": "3"]
            )
        )

        let summary = try log.summary()
        #expect(summary.entryCount == 2)
        #expect(summary.invalidLineCount == 0)
        #expect(summary.byteCount == (try log.readData()).count)

        let lines = try log.readData().split(separator: 10)
        #expect(lines.count == 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let first = try decoder.decode(
            LocalDiagnosticLogEntry.self,
            from: Data(lines[0])
        )
        #expect(first.schemaVersion == LocalDiagnosticLogEntry.currentSchemaVersion)
        #expect(first.attributes["note"]?.contains("\n") == false)
        #expect(first.attributes["note"]?.count == 160)

        try log.removeAll()
        #expect(try log.summary() == LocalDiagnosticLogSummary(entryCount: 0, byteCount: 0))
    }

    @Test func workoutSelectionPersistsUntilExplicitlyCleared() throws {
        let suiteName =
            "app.sugarman.tests.workout-selection.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let selected = StoredWorkoutSelection(planID: UUID(), phaseID: UUID())
        WorkoutSelectionPreferences(userDefaults: userDefaults).save(selected)

        let relaunchedDefaults = try #require(UserDefaults(suiteName: suiteName))
        let relaunchedPreferences = WorkoutSelectionPreferences(
            userDefaults: relaunchedDefaults
        )
        #expect(relaunchedPreferences.load() == selected)

        relaunchedPreferences.save(
            StoredWorkoutSelection(planID: nil, phaseID: nil)
        )
        #expect(
            relaunchedPreferences.load()
                == StoredWorkoutSelection(planID: nil, phaseID: nil)
        )
        #expect(
            userDefaults.object(forKey: WorkoutSelectionPreferences.selectedPlanKey) == nil
        )
        #expect(
            userDefaults.object(forKey: WorkoutSelectionPreferences.selectedPhaseKey) == nil
        )
    }

    @Test func noWorkoutRangePersistsAndInvalidStateUsesDefault() throws {
        let suiteName =
            "app.sugarman.tests.no-workout-range.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let preferences = NoWorkoutGlucoseRangePreferences(
            userDefaults: userDefaults
        )

        #expect(preferences.load() == .healthyAdultDefault)

        let custom = GlucoseReferenceRange(lowerMgdl: 75, upperMgdl: 135)
        preferences.save(custom)
        #expect(preferences.load() == custom)

        userDefaults.set(160, forKey: NoWorkoutGlucoseRangePreferences.lowerMgdlKey)
        userDefaults.set(120, forKey: NoWorkoutGlucoseRangePreferences.upperMgdlKey)
        #expect(preferences.load() == .healthyAdultDefault)

        preferences.reset()
        #expect(preferences.load() == .healthyAdultDefault)
        #expect(
            userDefaults.object(forKey: NoWorkoutGlucoseRangePreferences.lowerMgdlKey) == nil
        )
        #expect(
            userDefaults.object(forKey: NoWorkoutGlucoseRangePreferences.upperMgdlKey) == nil
        )
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

    func completeSession(
        id: UUID = UUID(),
        sensorID: UUID = UUID()
    ) throws -> SensorSession {
        SensorSession(
            id: id,
            sensorID: sensorID,
            activatedAt: Date(timeIntervalSince1970: 100),
            warmUpEndsAt: Date(timeIntervalSince1970: 200),
            expectedEndsAt: Date(timeIntervalSince1970: 300),
            endedAt: Date(timeIntervalSince1970: 400),
            ownerAccountReference: "owner-local",
            lastRequestedIndex: 10,
            lastReceivedIndex: 9,
            lastCommittedIndex: 8,
            sensorTimeAnchor: try testTimeAnchor(
                index: 8,
                timestamp: Date(timeIntervalSince1970: 500)
            ),
            protocolVariant: .v120RC4,
            lifecycle: .ended,
            connection: .disconnected,
            sensorErrorCode: "E-test"
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

    @Test func legacySampleWithoutDeliveryRecordIsReconciledLazily() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sample = makeSample(session: UUID(), index: 8)
        context.insert(GlucoseSampleRecord(from: sample))
        try context.save()

        let store = SwiftDataSugarmanStore(modelContainer: container)
        let summary = try await store.appleHealthSyncSummary()
        #expect(summary.pendingCount == 1)
        let candidates = try await store.appleHealthSyncCandidates(
            limit: 100,
            now: Date(timeIntervalSince1970: 100),
            ignoringRetryDeadline: false
        )
        #expect(candidates.map(\.sample.id) == [sample.id])

        try await store.recordAppleHealthSuccess(
            [sample.id],
            version: 1,
            at: Date(timeIntervalSince1970: 101)
        )
        #expect(try await store.appleHealthSyncSummary().syncedCount == 1)
    }

    @Test func unversionedStoreMigratesToDeliveryLedgerSchema() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sugarman-health-migration-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("sugarman.store")
        let sample = makeSample(session: UUID(), index: 9)
        do {
            let oldSchema = Schema([
                GlucoseSampleRecord.self,
                SensorSessionRecord.self,
                FuelingEventRecord.self,
                WorkoutContextRecord.self,
                WorkoutPlanRecord.self,
                SensorIdentityRecord.self,
            ])
            let configuration = ModelConfiguration(
                "Sugarman",
                schema: oldSchema,
                url: url,
                cloudKitDatabase: .none
            )
            let oldContainer = try ModelContainer(
                for: oldSchema,
                configurations: [configuration]
            )
            let context = ModelContext(oldContainer)
            context.insert(GlucoseSampleRecord(from: sample))
            try context.save()
        }

        let migrated = SwiftDataSugarmanStore(
            modelContainer: try SwiftDataSugarmanStore.makeContainer(url: url)
        )
        #expect(
            try await migrated.sample(
                sessionID: sample.sessionID,
                sensorIndex: sample.sensorIndex
            ) == sample
        )
        #expect(try await migrated.appleHealthSyncSummary().pendingCount == 1)
    }

    @Test func reopeningExistingContainerKeepsSamples() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "sugarman-reopen-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sugarman.store")
        let sensorID = UUID()
        let session = try completeSession(sensorID: sensorID)
        let identity = SensorIdentity(
            id: sensorID,
            productName: "GS3",
            sku: "64221",
            gtin: "06912345678901",
            redactedSerial: "…1234",
            udiIssuingAgency: "GS1",
            peerUUID: UUID(),
            firmwareRevision: "1.2.3",
            hardwareRevision: "A",
            manufacturer: "SiBionics",
            protocolVariant: .v120RC4,
            classificationEvidenceRevision: "gs1-concatenated-v1"
        )
        let workout = WorkoutContext(
            id: UUID(),
            sessionID: session.id,
            healthKitWorkoutUUID: UUID(),
            start: Date(timeIntervalSince1970: 120),
            end: Date(timeIntervalSince1970: 180),
            activityType: "run",
            summary: "persisted"
        )
        let sample = makeSample(session: session.id, index: 1)
        do {
            let store = SwiftDataSugarmanStore(modelContainer: try SwiftDataSugarmanStore.makeContainer(url: url))
            try await store.insertSession(session)
            try await store.insertIdentity(identity)
            try await store.insertWorkout(workout)
            try await store.insertSample(sample)
        }
        let reopened = SwiftDataSugarmanStore(modelContainer: try SwiftDataSugarmanStore.makeContainer(url: url))
        #expect(try await reopened.session(id: session.id) == session)
        #expect(try await reopened.identities() == [identity])
        #expect(try await reopened.workouts() == [workout])
        #expect(try await reopened.sample(sessionID: session.id, sensorIndex: 1) == sample)
        await #expect(throws: StoreError.duplicateSample(SampleKey(sessionID: session.id, sensorIndex: 1))) {
            try await reopened.insertSample(makeSample(session: session.id, index: 1))
        }
        try await reopened.insertSample(makeSample(session: session.id, index: 2))
        #expect(try await reopened.samples(sessionID: session.id).count == 2)
    }

    @Test func sessionAndIdentityRoundTripEveryDomainFieldAndUpdate() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let store = SwiftDataSugarmanStore(modelContainer: container)
        var session = try completeSession()
        let identity = SensorIdentity(
            id: UUID(),
            productName: "GS3",
            sku: "64221",
            gtin: "06912345678901",
            redactedSerial: "…1234",
            udiIssuingAgency: "GS1",
            peerUUID: UUID(),
            firmwareRevision: "1.2.3",
            hardwareRevision: "A",
            manufacturer: "SiBionics",
            protocolVariant: .v120RC4,
            classificationEvidenceRevision: "gs1-concatenated-v1"
        )
        let workout = WorkoutContext(
            id: UUID(),
            sessionID: session.id,
            healthKitWorkoutUUID: UUID(),
            start: Date(timeIntervalSince1970: 120),
            end: Date(timeIntervalSince1970: 180),
            activityType: "run",
            summary: "test"
        )
        try await store.insertSession(session)
        try await store.insertIdentity(identity)
        try await store.insertWorkout(workout)
        #expect(try await store.session(id: session.id) == session)
        #expect(try await store.identities() == [identity])
        #expect(try await store.workouts() == [workout])

        session.lifecycle = .live
        session.connection = .subscribed
        session.endedAt = nil
        session.lastCommittedIndex = UInt32.max
        try await store.updateSession(session)
        #expect(try await store.session(id: session.id) == session)
    }

    @Test func corruptSensorIndexThrowsInsteadOfTrapping() throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let record = GlucoseSampleRecord(from: makeSample(session: UUID(), index: 1))
        record.sensorIndex = -1
        #expect(throws: StoreError.invalidSensorIndex(-1)) {
            try record.domainValue()
        }
        record.sensorIndex = Int64(UInt32.max) + 1
        #expect(throws: StoreError.invalidSensorIndex(Int64(UInt32.max) + 1)) {
            try record.domainValue()
        }
    }

    @Test func unknownStoredSampleSourceFailsSafe() throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let record = GlucoseSampleRecord(from: makeSample(session: UUID(), index: 1))
        record.sourceRaw = "future-unknown-source"
        #expect(try record.domainValue().source == .unknown)
    }

    @Test func swiftDataBatchCommitIsAtomicDeduplicatingAndGapAware() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let store = SwiftDataSugarmanStore(modelContainer: container)
        let sessionID = UUID()
        try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 20)

        let first = try await store.commitSamples(
            [
                makeSample(session: sessionID, index: 20),
                makeSample(session: sessionID, index: 22),
            ],
            sessionID: sessionID
        )
        #expect(first.gapRangeCount == 1)
        #expect(first.lastCommittedIndex == 20)

        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 20)
        let repaired = try await store.commitSamples(
            [
                makeSample(session: sessionID, index: 20),
                makeSample(session: sessionID, index: 21),
                makeSample(session: sessionID, index: 22),
            ],
            sessionID: sessionID
        )
        #expect(repaired.insertedCount == 1)
        #expect(repaired.duplicateCount == 2)
        #expect(repaired.gapRangeCount == 0)
        #expect(repaired.lastCommittedIndex == 22)
        #expect(try await store.samples(sessionID: sessionID).map(\.sensorIndex) == [20, 21, 22])

        var conflict = makeSample(session: sessionID, index: 22)
        conflict.milligramsPerDeciliter = 250
        await #expect(throws: StoreError.conflictingSample(conflict.id)) {
            try await store.commitSamples(
                [makeSample(session: sessionID, index: 23), conflict],
                sessionID: sessionID
            )
        }
        #expect(try await store.sample(sessionID: sessionID, sensorIndex: 23) == nil)
        #expect(try await store.session(id: sessionID)?.lastCommittedIndex == 22)
    }

    @Test func swiftDataPersistsTimeAnchorWithItsFirstMappedBatch() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let store = SwiftDataSugarmanStore(modelContainer: container)
        let sessionID = UUID()
        try await store.insertSession(SensorSession(id: sessionID, sensorID: UUID()))
        try await store.prepareHistoryRequest(sessionID: sessionID, startingAt: 30)
        let anchor = try testTimeAnchor(
            index: 30,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        var sample = makeSample(session: sessionID, index: 30)
        sample.sensorTimestamp = anchor.timestamp

        _ = try await store.commitSamples(
            [sample],
            sessionID: sessionID,
            establishingTimeAnchor: anchor
        )

        #expect(try await store.session(id: sessionID)?.sensorTimeAnchor == anchor)
        #expect(try await store.sample(sessionID: sessionID, sensorIndex: 30) == sample)
    }

    @Test func swiftDataConnectionProjectionPreservesOtherSessionFields() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let store = SwiftDataSugarmanStore(modelContainer: container)
        let session = try completeSession()
        try await store.insertSession(session)

        try await store.setConnection(.connected, sessionID: session.id)

        var expected = session
        expected.connection = .connected
        #expect(try await store.session(id: session.id) == expected)
    }

    @Test func swiftDataRejectsPartiallyStoredTimeAnchor() throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let record = SensorSessionRecord(
            from: SensorSession(sensorID: UUID())
        )
        record.sensorTimeAnchorIndex = 10
        record.sensorTimeAnchorTimestamp = Date(timeIntervalSince1970: 100)

        #expect(throws: StoreError.incompleteTimeAnchor) {
            try record.domainValue()
        }
    }

    @Test func workoutPlanRoundTripsThroughSwiftData() async throws {
        guard #available(iOS 26, macOS 26, *) else { return }
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let store = SwiftDataSugarmanStore(modelContainer: container)
        let plan = WorkoutPlanCatalog.dayOne150KmRide
        try await store.insertWorkoutPlan(plan)
        let loaded = try await store.workoutPlans()
        #expect(loaded == [plan])
        #expect(loaded.first?.phases[1].floorMgdl == 80)
    }
}
#endif
