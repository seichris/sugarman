// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
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
        exportDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    ) -> AppModel {
        AppModel(store: store, diagnosticLogStore: LocalDiagnosticLogStore(
            fileURL: exportDirectory.appendingPathComponent("diagnostics.jsonl")
        ), userDefaults: UserDefaults(suiteName: "app.sugarman.review-tests.\(UUID().uuidString)")!,
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
        let data = Data("""
        {"schemaVersion":1,"peripheralIdentifier":"10000000-2000-3000-4000-500000000001","sensorAddressHex":"010203040506","authenticationIDHex":"202122232425262728292a2b","registeredBlockHex":"303132333435363738393a3b3c3d3e3f","algorithmKeyHex":"404142434445464748494a4b4c4d4e4f","algorithmIVHex":"505152535455565758595a5b5c5d5e5f","effectiveDataStartIndex":100}
        """.utf8)
        try await provisioning.importDocument(data, linkedSensorID: identity.id, into: store)
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
    func replace(with data: Data) throws { lock.withLock { stored = data } }
    func delete() throws { lock.withLock { stored = nil } }
}
