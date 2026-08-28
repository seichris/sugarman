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
    @State private var model = AppModel()

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
    var store: InMemorySugarmanStore
    var safety: SafetyEngine
    var connection: ConnectionState
    var lifecycle: SensorLifecycleState
    var latestSample: GlucoseSample?
    var preferredUnit: GlucoseUnit
    var probeEnabled: Bool
    var isSyntheticDemo: Bool
    var demoScenario: SyntheticDemoScenario?
    var demoSessionID: UUID?
    var samples: [GlucoseSample]
    var sessions: [SensorSession]
    var fuelingEvents: [FuelingEvent]
    var workouts: [WorkoutContext]
    var identities: [SensorIdentity]
    var ownerAccountID: OwnerAccountID?
    var exporter: VersionedDataExporter
    var demoLoadError: String?

    init(
        store: InMemorySugarmanStore = InMemorySugarmanStore(),
        safety: SafetyEngine = SafetyEngine(),
        connection: ConnectionState = .disconnected,
        lifecycle: SensorLifecycleState = .unknown,
        latestSample: GlucoseSample? = nil,
        preferredUnit: GlucoseUnit = .milligramsPerDeciliter,
        probeEnabled: Bool = false
    ) {
        self.store = store
        self.safety = safety
        self.connection = connection
        self.lifecycle = lifecycle
        self.latestSample = latestSample
        self.preferredUnit = preferredUnit
        self.probeEnabled = probeEnabled
        self.isSyntheticDemo = false
        self.demoScenario = nil
        self.demoSessionID = nil
        self.samples = []
        self.sessions = []
        self.fuelingEvents = []
        self.workouts = []
        self.identities = []
        self.ownerAccountID = nil
        self.exporter = VersionedDataExporter()
        self.demoLoadError = nil
    }

    func assessment(at now: Date = Date()) -> SafetyAssessment {
        safety.evaluate(
            now: now,
            connection: connection,
            lifecycle: lifecycle,
            latestSample: latestSample
        )
    }

    var assessment: SafetyAssessment {
        assessment(at: Date())
    }

    var activeSessionID: UUID? {
        sessions.first?.id
    }

    func refresh() async {
        samples = (try? await store.allSamples()) ?? []
        sessions = (try? await store.allSessions()) ?? []
        fuelingEvents = (try? await store.fuelingEvents()) ?? []
        workouts = (try? await store.workouts()) ?? []
        identities = (try? await store.identities()) ?? []
        if let sessionID = activeSessionID {
            latestSample = try? await store.latestSample(sessionID: sessionID)
        } else {
            latestSample = nil
        }
    }

    func loadDemo(_ scenario: SyntheticDemoScenario) async throws {
        demoLoadError = nil
        do {
            try await store.deleteAll()
            clearLivePresentation()
            let fixture = SyntheticDemoCatalog.make(scenario)
            try await store.insertSession(fixture.session)
            try await store.insertIdentity(fixture.identity)
            for sample in fixture.samples {
                try await store.insertSample(sample)
            }
            for workout in fixture.workouts {
                try await store.insertWorkout(workout)
            }
            connection = fixture.connection
            lifecycle = fixture.lifecycle
            isSyntheticDemo = true
            demoScenario = scenario
            demoSessionID = fixture.session.id
            await refresh()
        } catch {
            try? await store.deleteAll()
            clearLivePresentation()
            await refresh()
            demoLoadError = error.localizedDescription
            throw error
        }
    }

    func addFueling(label: String, carbohydrateGrams: Double?, timestamp: Date) async {
        let event = FuelingEvent(
            timestamp: timestamp,
            carbohydrateGrams: carbohydrateGrams,
            label: label,
            sessionID: activeSessionID
        )
        try? await store.insertFueling(event)
        await refresh()
    }

    func deleteFueling(_ id: UUID) async {
        try? await store.deleteFueling(id: id)
        await refresh()
    }

    func confirmIdentity(_ identity: SensorIdentity) async {
        try? await store.insertIdentity(identity)
        await refresh()
    }

    func storeOwnerAccountID(_ raw: String) throws -> OwnerAccountID {
        let id = try ManualOwnerBinding().validate(raw)
        ownerAccountID = id
        return id
    }

    func deleteSession(_ id: UUID) async {
        let wasOnlySession = sessions.count <= 1
        let wasDemoSession = demoSessionID == id
        do {
            try await store.delete(sessionID: id)
        } catch {
            demoLoadError = error.localizedDescription
            await refresh()
            return
        }
        if wasOnlySession || wasDemoSession {
            clearLivePresentation()
        }
        await refresh()
        if sessions.isEmpty {
            clearLivePresentation()
        }
    }

    func deleteAllLocalData() async {
        try? await store.deleteAll()
        clearLivePresentation()
        ownerAccountID = nil
        await refresh()
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
        return samples.filter { sample in
            sample.sensorTimestamp >= start && sample.sensorTimestamp <= end
        }
        .sorted { $0.sensorIndex < $1.sensorIndex }
    }

    private func clearLivePresentation() {
        latestSample = nil
        lifecycle = .unknown
        connection = .disconnected
        isSyntheticDemo = false
        demoScenario = nil
        demoSessionID = nil
    }
}
