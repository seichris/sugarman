// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AccountBinding
import GS3Transport
import Integrations
import Observation
import SafetyEngine
import SensorOnboarding
import SugarmanDiagnostics
import SugarmanDomain
import SugarmanStore
import SwiftUI

@main
struct SugarmanApp: App {
    @State private var model = AppModel.bootstrapped()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

@Observable
@MainActor
final class AppModel {
    static let preferredUnitDefaultsKey = "app.sugarman.preferredUnit"

    var store: any SugarmanStoring
    private var primaryStore: any SugarmanStoring
    var safety: SafetyEngine
    var connection: ConnectionState
    var lifecycle: SensorLifecycleState
    var latestSample: GlucoseSample?
    var preferredUnit: GlucoseUnit {
        didSet {
            UserDefaults.standard.set(preferredUnit.rawValue, forKey: Self.preferredUnitDefaultsKey)
        }
    }
    var probeEnabled: Bool
    var probeSession: DiagnosticProbeSession
    var isSyntheticDemo: Bool
    var demoScenario: SyntheticDemoScenario?
    var demoSessionID: UUID?
    var selectedSessionID: UUID?
    var samples: [GlucoseSample]
    var sessions: [SensorSession]
    var fuelingEvents: [FuelingEvent]
    var workouts: [WorkoutContext]
    var identities: [SensorIdentity]
    var ownerAccountID: OwnerAccountID?
    var exporter: VersionedDataExporter
    var exportFileWriter: PrivacyExportFileWriter
    var demoLoadError: String?
    var storeErrorMessage: String?

    static func bootstrapped() -> AppModel {
        let result = SugarmanStoreFactory.makePersistent()
        return AppModel(store: result.store, initialStoreError: result.loadError)
    }

    init(
        store: any SugarmanStoring = InMemorySugarmanStore(),
        safety: SafetyEngine = SafetyEngine(),
        connection: ConnectionState = .disconnected,
        lifecycle: SensorLifecycleState = .unknown,
        latestSample: GlucoseSample? = nil,
        preferredUnit: GlucoseUnit? = nil,
        probeEnabled: Bool = false,
        initialStoreError: String? = nil
    ) {
        self.store = store
        self.primaryStore = store
        self.safety = safety
        self.connection = connection
        self.lifecycle = lifecycle
        self.latestSample = latestSample
        self.preferredUnit = preferredUnit
            ?? UserDefaults.standard.string(forKey: Self.preferredUnitDefaultsKey)
                .flatMap(GlucoseUnit.init(rawValue:))
            ?? .milligramsPerDeciliter
        self.probeEnabled = probeEnabled
        self.probeSession = DiagnosticProbeSession()
        self.isSyntheticDemo = false
        self.demoScenario = nil
        self.demoSessionID = nil
        self.selectedSessionID = nil
        self.samples = []
        self.sessions = []
        self.fuelingEvents = []
        self.workouts = []
        self.identities = []
        self.ownerAccountID = nil
        self.exporter = VersionedDataExporter()
        self.exportFileWriter = PrivacyExportFileWriter()
        self.demoLoadError = nil
        self.storeErrorMessage = initialStoreError
    }

    func assessment(at now: Date = Date()) -> SafetyAssessment {
        safety.evaluate(
            now: now,
            connection: activeConnection,
            lifecycle: activeLifecycle,
            latestSample: latestSample
        )
    }

    var assessment: SafetyAssessment {
        assessment(at: Date())
    }

    var activeSessionID: UUID? {
        ActiveSessionSelection.resolve(
            sessions: sessions,
            demoSessionID: demoSessionID,
            selectedSessionID: selectedSessionID
        )
    }

    var activeSession: SensorSession? {
        guard let activeSessionID else { return nil }
        return sessions.first { $0.id == activeSessionID }
    }

    var activeConnection: ConnectionState { activeSession?.connection ?? connection }
    var activeLifecycle: SensorLifecycleState { activeSession?.lifecycle ?? lifecycle }

    var activeSamples: [GlucoseSample] {
        ActiveSessionSelection.samples(samples, for: activeSessionID)
    }

    var visibleFuelingEvents: [FuelingEvent] {
        ActiveSessionSelection.fuelingEvents(fuelingEvents, for: activeSessionID)
    }

    var visibleWorkouts: [WorkoutContext] {
        ActiveSessionSelection.workouts(workouts, for: activeSessionID)
    }

    func refresh() async {
        do {
            try await refreshFromStore()
        } catch {
            // `refreshFromStore` preserves the last complete snapshot and
            // exposes the error through `storeErrorMessage`.
        }
    }

    func loadDemo(_ scenario: SyntheticDemoScenario) async throws {
        demoLoadError = nil
        do {
            let demoStore = InMemorySugarmanStore()
            let fixture = SyntheticDemoCatalog.make(scenario)
            try await demoStore.insertSession(fixture.session)
            try await demoStore.insertIdentity(fixture.identity)
            for sample in fixture.samples {
                try await demoStore.insertSample(sample)
            }
            for workout in fixture.workouts {
                try await demoStore.insertWorkout(workout)
            }
            store = demoStore
            isSyntheticDemo = true
            demoScenario = scenario
            demoSessionID = fixture.session.id
            selectedSessionID = ActiveSessionSelection.selectionAfterInsert(
                insertedID: fixture.session.id,
                sessions: [fixture.session],
                currentSelection: nil
            )
            try await refreshFromStore()
        } catch {
            store = primaryStore
            isSyntheticDemo = false
            demoScenario = nil
            demoSessionID = nil
            await refresh()
            demoLoadError = error.localizedDescription
            throw error
        }
    }

    func exitDemo() async {
        guard isSyntheticDemo else { return }
        store = primaryStore
        isSyntheticDemo = false
        demoScenario = nil
        demoSessionID = nil
        demoLoadError = nil
        selectedSessionID = nil
        await refresh()
    }

    func addFueling(label: String, carbohydrateGrams: Double?, timestamp: Date) async throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100 else { throw AppInputError.invalidFuelingLabel }
        if let carbohydrateGrams,
           !carbohydrateGrams.isFinite || !(0...1000).contains(carbohydrateGrams) {
            throw AppInputError.invalidCarbohydrateAmount
        }
        let event = FuelingEvent(
            timestamp: timestamp,
            carbohydrateGrams: carbohydrateGrams,
            label: trimmed,
            sessionID: activeSessionID
        )
        try await store.insertFueling(event)
        try await refreshFromStore()
    }

    func deleteFueling(_ id: UUID) async throws {
        try await store.deleteFueling(id: id)
        try await refreshFromStore()
    }

    func chooseSession(_ id: UUID) async {
        selectedSessionID = id
        if demoSessionID != id {
            demoSessionID = nil
        }
        await refresh()
    }

    func confirmIdentity(_ identity: SensorIdentity) async throws {
        try await store.insertIdentity(identity)
        try await refreshFromStore()
        if sessions.count == 1, let only = sessions.first {
            selectedSessionID = ActiveSessionSelection.selectionAfterInsert(
                insertedID: only.id,
                sessions: sessions,
                currentSelection: selectedSessionID
            )
        }
    }

    func storeOwnerAccountID(_ raw: String) throws -> OwnerAccountID {
        let id = try ManualOwnerBinding().validate(raw)
        ownerAccountID = id
        return id
    }

    func deleteSession(_ id: UUID) async throws {
        let wasOnlySession = sessions.count <= 1
        let wasDemoSession = demoSessionID == id
        let wasSelected = selectedSessionID == id
        try await store.delete(sessionID: id)
        if wasOnlySession || wasDemoSession {
            if wasDemoSession {
                await exitDemo()
                return
            }
            clearLivePresentation()
        } else if wasSelected {
            selectedSessionID = nil
        }
        try await refreshFromStore()
        if sessions.isEmpty {
            clearLivePresentation()
        }
    }

    func deleteAllLocalData() async throws {
        try await primaryStore.deleteAll()
        store = primaryStore
        clearLivePresentation()
        ownerAccountID = nil
        try await refreshFromStore()
    }

    func exportJSON() async throws -> Data {
        let samples = try await store.allSamples()
        let fueling = try await store.fuelingEvents()
        return try exporter.exportJSON(samples: samples, fueling: fueling)
    }

    func exportCSV() async throws -> String {
        let samples = try await store.allSamples()
        return try exporter.exportCSV(samples: samples)
    }

    func samples(overlapping workout: WorkoutContext) -> [GlucoseSample] {
        let start = workout.start
        let end = workout.end ?? Date()
        return activeSamples.filter { sample in
            sample.sensorTimestamp >= start && sample.sensorTimestamp <= end
        }
        .sorted { $0.sensorIndex < $1.sensorIndex }
    }

    private func refreshFromStore() async throws {
        do {
            let newSamples = try await store.allSamples()
            let newSessions = try await store.allSessions()
            let newFueling = try await store.fuelingEvents()
            let newWorkouts = try await store.workouts()
            let newIdentities = try await store.identities()
            let resolved = ActiveSessionSelection.resolve(
                sessions: newSessions,
                demoSessionID: demoSessionID,
                selectedSessionID: selectedSessionID
            )
            let newLatest: GlucoseSample? = if let resolved {
                try await store.latestSample(sessionID: resolved)
            } else {
                nil
            }

            samples = newSamples
            sessions = newSessions
            fuelingEvents = newFueling
            workouts = newWorkouts
            identities = newIdentities
            selectedSessionID = resolved
            latestSample = newLatest
            isSyntheticDemo = demoSessionID != nil
            storeErrorMessage = nil
        } catch {
            storeErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func clearLivePresentation() {
        latestSample = nil
        lifecycle = .unknown
        connection = .disconnected
        isSyntheticDemo = false
        demoScenario = nil
        demoSessionID = nil
        selectedSessionID = nil
    }
}

enum AppInputError: LocalizedError {
    case invalidFuelingLabel
    case invalidCarbohydrateAmount

    var errorDescription: String? {
        switch self {
        case .invalidFuelingLabel:
            "Enter a fueling label between 1 and 100 characters."
        case .invalidCarbohydrateAmount:
            "Carbohydrate amount must be a finite value between 0 and 1000 grams."
        }
    }
}
