// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AppleHealthIntegration
import GS3Protocol
import Foundation
import SwiftData
import Testing
import SugarmanDomain
import SugarmanStore
import Integrations
@testable import GS3DeviceProvisioning
@testable import SugarmanAppTestSupport

@MainActor
struct AppModelTests {
    private func model(
        store: any SugarmanStoring,
        provisioning: DeviceOnlyGS3Provisioning? = nil,
        defaults: UserDefaults = UserDefaults(suiteName: "app.sugarman.review-tests.\(UUID())")!,
        exportDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    ) -> AppModel {
        AppModel(store: store, diagnosticLogStore: LocalDiagnosticLogStore(
            fileURL: exportDirectory.appendingPathComponent("diagnostics.jsonl")
        ), userDefaults: defaults,
        exportDirectory: exportDirectory,
        sensorProvisioning: provisioning ?? DeviceOnlyGS3Provisioning(persistence: MemoryProvisioning()))
    }

    @Test func editingPlanPreservesIdentityAndPersistsTheChanges() async throws {
        let store = InMemorySugarmanStore()
        let original = WorkoutPlanCatalog.dayOne150KmRide
        try await store.insertWorkoutPlan(original)
        let app = model(store: store)
        await app.refresh()
        app.selectWorkoutPlan(original.id)
        app.selectWorkoutPhase(original.phases[1].id)
        var draft = WorkoutPlanDraft(plan: original)
        draft.name = "Edited ride"
        draft.phases[1].lower = "95"
        let edited = try #require(draft.makePlan())
        #expect(edited.id == original.id)
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.phases.map(\.id) == original.phases.map(\.id))
        await app.updateWorkoutPlan(edited)
        let saved = try #require(try await store.workoutPlans().first)
        #expect(saved.name == "Edited ride")
        #expect(saved.phases[1].lowerMgdl == 95)
        #expect(app.selectedWorkoutPhaseID == original.phases[1].id)
    }
    @Test func failedWorkoutWritesReturnFailureAndKeepAnActionableError() async {
        let app = model(store: UnavailableSugarmanStore())
        #expect(await app.addWorkoutPlan(WorkoutPlanCatalog.dayOne150KmRide) == false)
        #expect(app.workoutActionError != nil)
        #expect(await app.updateWorkoutPlan(WorkoutPlanCatalog.dayOne150KmRide) == false)
        #expect(app.workoutActionError != nil)
        #expect(app.selectedWorkoutPlanID == nil)
    }

    @Test func emptySelectedSessionDoesNotBorrowOtherSensorSamples() async throws {
        let store = InMemorySugarmanStore()
        let old = SensorSession(sensorID: UUID())
        let empty = SensorSession(sensorID: UUID())
        try await store.insertSession(old)
        try await store.insertSession(empty)
        try await store.insertSample(sample(sessionID: old.id))
        let app = model(store: store)
        await app.refresh()
        await app.chooseSession(empty.id)
        #expect(app.activeSamples.isEmpty)
        #expect(app.latestSample == nil)
        #expect(app.samples.count == 1)
    }

    @Test func persistedSubscriptionDoesNotImplyThisProcessIsConnected() async throws {
        let store = InMemorySugarmanStore()
        let session = SensorSession(sensorID: UUID(), lifecycle: .live, connection: .subscribed)
        try await store.insertSession(session)
        try await store.insertSample(sample(sessionID: session.id))
        let app = model(store: store)
        await app.refresh()
        #expect(app.activeConnection == .disconnected)
        #expect(app.assessment.isDisconnected)
        app.provisionedSessionID = session.id
        app.isSensorConnectionEnabled = true
        app.connection = .subscribed
        #expect(app.assessment.showsValueAsCurrent)
        app.isSensorConnectionEnabled = false
        #expect(app.assessment.isDisconnected)
        #expect(!app.assessment.showsValueAsCurrent)
    }

    @Test func deletingProvisionedSessionDisablesRestartIntent() async throws {
        let store = InMemorySugarmanStore()
        let identity = SensorIdentity(redactedSerial: "SYN…TIC")
        try await store.insertIdentity(identity)
        let provisioning = DeviceOnlyGS3Provisioning(persistence: MemoryProvisioning())
        try await provisioning.importDocument(handoverData(), linkedSensorID: identity.id, into: store)
        try await provisioning.setConnectionIntentEnabled(true)
        let sessionID = try #require(try await provisioning.summary()?.linkedSessionID)
        let app = model(store: store, provisioning: provisioning)
        await app.refresh()
        try await app.deleteSession(sessionID)
        #expect(try await store.session(id: sessionID) == nil)
        #expect(try await provisioning.summary()?.connectionIntentEnabled == false)
        #expect(!app.isSensorConnectionEnabled)
    }

    @Test func deletingSessionRemovesExportCopiesAndPreservesUnrelatedFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InMemorySugarmanStore()
        let session = SensorSession(sensorID: UUID())
        try await store.insertSession(session)
        let app = model(store: store, exportDirectory: directory)
        await app.refresh()
        let writer = PrivacyExportFileWriter()
        let json = try writer.writeJSON(Data("private data".utf8), to: directory)
        let csv = try writer.writeCSV("private data", to: directory)
        let diagnostic = try writer.writeDiagnostics(Data("private data".utf8), to: directory)
        let unrelated = directory.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)
        try await app.deleteSession(session.id)
        for url in [json, csv, diagnostic] {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func deletingAllDataAlsoRemovesExports() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = model(store: InMemorySugarmanStore(), exportDirectory: directory)
        let url = try app.exportFileWriter.writeJSON(Data("private data".utf8), to: directory)
        try await app.deleteAllLocalData()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func handoverData() -> Data {
        Data("""
        {"schemaVersion":1,"peripheralIdentifier":"10000000-2000-3000-4000-500000000001","sensorAddressHex":"010203040506","authenticationIDHex":"202122232425262728292a2b","registeredBlockHex":"303132333435363738393a3b3c3d3e3f","algorithmKeyHex":"404142434445464748494a4b4c4d4e4f","algorithmIVHex":"505152535455565758595a5b5c5d5e5f","effectiveDataStartIndex":100}
        """.utf8)
    }

    @Test func explicitStopSurvivesFailedKeychainUpdateAndRelaunch() async throws {
        let persistence = MemoryProvisioning()
        let provisioning = DeviceOnlyGS3Provisioning(persistence: persistence)
        let store = InMemorySugarmanStore()
        let identity = SensorIdentity(redactedSerial: "SYN…TIC")
        try await store.insertIdentity(identity)
        try await provisioning.importDocument(handoverData(), linkedSensorID: identity.id, into: store)
        try await provisioning.setConnectionIntentEnabled(true)
        let defaults = UserDefaults(suiteName: "app.sugarman.stop-tests.\(UUID())")!
        let app = model(store: store, provisioning: provisioning, defaults: defaults)
        persistence.failReplacements()
        await app.stopSensorConnection()
        #expect(try await provisioning.summary()?.connectionIntentEnabled == true)
        let relaunched = model(store: store, provisioning: provisioning, defaults: defaults)
        await relaunched.handleScenePhase(.active)
        #expect(!relaunched.isSensorConnectionEnabled)
        #expect(relaunched.sensorConnectionActivity == .stopped)
    }

    @Test func committedFuelingSurvivesAnUnrelatedRefreshError() async throws {
        let container = try SwiftDataSugarmanStore.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let invalidSample = GlucoseSampleRecord(from: sample(sessionID: UUID()))
        invalidSample.sensorIndex = -1
        context.insert(invalidSample)
        try context.save()

        let store = SwiftDataSugarmanStore(modelContainer: container)
        let app = model(store: store)
        try await app.addFueling(label: "Gel", carbohydrateGrams: 25, timestamp: .now)
        let event = try #require(try await store.fuelingEvents().first)
        #expect(app.storeErrorMessage != nil)
        try await app.deleteFueling(event.id)
        #expect(try await store.fuelingEvents().isEmpty)
    }

    @Test func committedReadingTriggersHealthWriteWithoutReconnecting() async throws {
        let store = InMemorySugarmanStore()
        let app = model(store: store)
        let defaults = UserDefaults(suiteName: "app.sugarman.sync-tests.\(UUID())")!
        defaults.set(true, forKey: AppleHealthAppBridge.enabledDefaultsKey)
        let writer = SampleWriter()
        app.appleHealth = AppleHealthAppBridge(store: store, userDefaults: defaults, writer: writer)
        let reading = GlucoseSample(
            sessionID: UUID(), sensorIndex: 1, sensorTimestamp: .now, receiptTimestamp: .now,
            milligramsPerDeciliter: 100, quality: .ok,
            decoderRevision: V3OfflineGlucoseNotificationDecoder.evidenceRevision
        )
        try await store.insertSample(reading)
        app.makeSensorCallbacks().onSamplesCommitted(.init(insertedCount: 1, duplicateCount: 0, gapRangeCount: 0))
        let deadline = ContinuousClock.now + .seconds(3)
        while await writer.keys.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await writer.keys == [reading.id])
    }

    @Test func switchingSessionsKeepsActivityAndReadingsWithTheirOwner() async throws {
        let store = InMemorySugarmanStore()
        let live = SensorSession(sensorID: UUID())
        let previous = SensorSession(sensorID: UUID())
        for session in [live, previous] {
            try await store.insertSession(session)
            try await store.insertSample(sample(sessionID: session.id))
        }
        let app = model(store: store)
        await app.refresh()
        app.provisionedSessionID = live.id
        app.isSensorConnectionEnabled = true
        app.sensorConnectionActivity = .synchronizing
        await app.chooseSession(live.id)
        #expect(app.selectedSensorActivity == .synchronizing)
        app.store = UnavailableSugarmanStore()
        await app.chooseSession(previous.id)
        #expect(app.selectedSensorActivity == nil)
        #expect(app.latestSample?.sessionID == previous.id)
        #expect(app.activeConnection == .disconnected)
    }

    @Test func deletingLastSensorKeepsSelectedWorkoutAndPhase() async throws {
        let store = InMemorySugarmanStore()
        let session = SensorSession(sensorID: UUID())
        let plan = WorkoutPlanCatalog.dayOne150KmRide
        try await store.insertSession(session)
        try await store.insertWorkoutPlan(plan)
        let app = model(store: store)
        await app.refresh()
        app.selectWorkoutPlan(plan.id)
        app.selectWorkoutPhase(plan.phases[1].id)
        try await app.deleteSession(session.id)
        #expect(app.selectedWorkoutPlanID == plan.id)
        #expect(app.selectedWorkoutPhaseID == plan.phases[1].id)
    }

    private func sample(sessionID: UUID) -> GlucoseSample {
        GlucoseSample(sessionID: sessionID, sensorIndex: 1,
                      sensorTimestamp: .now, receiptTimestamp: .now,
                      milligramsPerDeciliter: 100, quality: .ok,
                      decoderRevision: "synthetic-test")
    }
}

private final class MemoryProvisioning: GS3DeviceProvisioningPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?
    func load() throws -> Data? { lock.withLock { stored } }
    private var rejectReplacement = false
    func failReplacements() { lock.withLock { rejectReplacement = true } }
    func replace(with data: Data) throws {
        try lock.withLock {
            guard !rejectReplacement else { throw GS3DeviceProvisioningError.invalidStoredMaterial }
            stored = data
        }
    }
    func delete() throws { lock.withLock { stored = nil } }
}

private actor SampleWriter: AppleHealthGlucoseWritingClient {
    private(set) var keys: [SampleKey] = []
    func authorizationState() async -> AppleHealthAuthorizationState { .authorized }
    func requestWriteAuthorization() async throws {}
    func earliestPermittedSampleDate() async throws -> Date { .distantPast }
    func save(_ payloads: [AppleHealthGlucosePayload]) async throws {
        keys.append(contentsOf: payloads.map(\.key))
    }
}
