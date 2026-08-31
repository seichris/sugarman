// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AccountBinding
#if SUGARMAN_DEVICE_TEST
import GS3DeviceProvisioning
#endif
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
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    Task { await model.handleScenePhase(phase) }
                }
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
    private var foregroundSessionBridge: ForegroundGS3SessionBridge
#if SUGARMAN_DEVICE_TEST
    var hasDeviceTestProvisioning: Bool
    var deviceTestLinkedSensorID: UUID?
    var isDeviceTestArmed: Bool
    var deviceTestStatus: String
    var deviceTestLifecycleLines: [String]
    var deviceTestAuthenticationAcknowledgementCount: Int
    var deviceTestHistoryAcknowledgementCount: Int
    var hasDeviceTestProbeBridgePending: Bool
    var isDeviceTestProbeBridgeScanning: Bool
    @ObservationIgnored private let deviceTestProvisioning: DeviceOnlyGS3Provisioning
    @ObservationIgnored private let deviceTestProbeBridgeScanner:
        DeviceTestProbeProvisioningScanner
    @ObservationIgnored private var deviceTestProbeBridgeRequest:
        GS3ProbeBridgeScanRequest?
    private var currentScenePhase: ScenePhase
#endif

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
        self.foregroundSessionBridge = ForegroundGS3SessionBridge()
#if SUGARMAN_DEVICE_TEST
        self.hasDeviceTestProvisioning = false
        self.deviceTestLinkedSensorID = nil
        self.isDeviceTestArmed = false
        self.deviceTestStatus = "Import private material after storing an owned sensor identity."
        self.deviceTestLifecycleLines = []
        self.deviceTestAuthenticationAcknowledgementCount = 0
        self.deviceTestHistoryAcknowledgementCount = 0
        self.hasDeviceTestProbeBridgePending = false
        self.isDeviceTestProbeBridgeScanning = false
        self.deviceTestProvisioning = DeviceOnlyGS3Provisioning()
        self.deviceTestProbeBridgeScanner = DeviceTestProbeProvisioningScanner()
        self.deviceTestProbeBridgeRequest = nil
        self.currentScenePhase = .inactive
#endif
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

    func handleScenePhase(_ phase: ScenePhase) async {
#if SUGARMAN_DEVICE_TEST
        currentScenePhase = phase
#endif
        switch phase {
        case .active:
            do {
                try await foregroundSessionBridge.enterForeground()
            } catch {
                // The bridge and coordinator expose only typed, redacted
                // failures. Keep prior readings fail closed through the
                // persisted disconnected projection.
                storeErrorMessage = String(localized: "live.session_start_failed")
            }
        case .inactive:
            // Transient foreground interruptions (for example, system UI)
            // must not churn ownership or manufacture a reconnect.
            break
        case .background:
#if SUGARMAN_DEVICE_TEST
            deviceTestProbeBridgeScanner.cancel()
#endif
            await foregroundSessionBridge.leaveForeground()
        @unknown default:
#if SUGARMAN_DEVICE_TEST
            deviceTestProbeBridgeScanner.cancel()
#endif
            await foregroundSessionBridge.leaveForeground()
        }
        await refresh()
    }

    func installForegroundSessionFactory(
        _ factory: @escaping @Sendable (
            GS3ForegroundSessionCallbacks
        ) async throws -> any GS3ForegroundSessionControlling
    ) {
        let refresh: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
#if SUGARMAN_DEVICE_TEST
        let callbacks = GS3ForegroundSessionCallbacks(
            onConnection: { _ in refresh() },
            onLifecycleEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.recordDeviceTestLifecycle(event.description)
                }
            },
            onSamplesCommitted: { _ in refresh() },
            onCommandAcknowledged: { [weak self] command in
                Task { @MainActor [weak self] in
                    switch command {
                    case .authentication:
                        self?.deviceTestAuthenticationAcknowledgementCount += 1
                    case .effectiveData:
                        self?.deviceTestHistoryAcknowledgementCount += 1
                    }
                }
            },
            onFailure: { [weak self] failure in
                refresh()
                Task { @MainActor [weak self] in
                    self?.deviceTestStatus =
                        "Managed foreground session failed closed (\(failure.rawValue))."
                }
            }
        )
#else
        let callbacks = GS3ForegroundSessionCallbacks(
            onConnection: { _ in refresh() },
            onSamplesCommitted: { _ in refresh() },
            onFailure: { _ in refresh() }
        )
#endif
        foregroundSessionBridge.install {
            try await factory(callbacks)
        }
    }

#if SUGARMAN_DEVICE_TEST
    var redactedDeviceTestReport: String {
        ([
            "Sugarman managed foreground device-test diagnostics",
            "Packet bodies, sensor identifiers, private material, glucose values, and record indexes are omitted.",
            "Authentication write acknowledgements: \(deviceTestAuthenticationAcknowledgementCount)",
            "History write acknowledgements: \(deviceTestHistoryAcknowledgementCount)",
            "",
        ] + deviceTestLifecycleLines).joined(separator: "\n")
    }

    func refreshDeviceTestProvisioningAvailability() async {
        do {
            let summary = try await deviceTestProvisioning.summary()
            hasDeviceTestProvisioning = summary != nil
            deviceTestLinkedSensorID = summary?.linkedSensorID
            if summary != nil, !isDeviceTestArmed {
                deviceTestStatus = "Private material is available in this device's Keychain."
            } else if summary == nil {
                deviceTestStatus = hasDeviceTestProbeBridgePending
                    ? "Probe material is validated in memory. Run the separately confirmed scan-only provisioning lookup."
                    : "Import private material after storing an owned sensor identity."
            }
        } catch {
            hasDeviceTestProvisioning = false
            deviceTestLinkedSensorID = nil
            deviceTestStatus = error.localizedDescription
        }
    }

    func importDeviceTestProvisioning(
        from url: URL,
        linkedSensorID: UUID
    ) async {
        guard !isDeviceTestArmed else {
            deviceTestStatus = "Stop the managed foreground session before importing material."
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            var data = try Data(contentsOf: url, options: [.mappedIfSafe])
            defer {
                if !data.isEmpty { data.resetBytes(in: 0..<data.count) }
            }
            try await deviceTestProvisioning.importDocument(
                data,
                linkedSensorID: linkedSensorID,
                into: primaryStore
            )
            try await refreshFromStore()
            await refreshDeviceTestProvisioningAvailability()
            deviceTestStatus =
                "Private material imported. No Bluetooth action has started."
        } catch {
            deviceTestStatus = error.localizedDescription
        }
    }

    func prepareDeviceTestProbeBridge(
        from url: URL,
        linkedSensorID: UUID
    ) async {
        guard !isDeviceTestArmed,
              !hasDeviceTestProvisioning,
              !isDeviceTestProbeBridgeScanning else {
            deviceTestStatus =
                "Stop the managed foreground session before preparing Probe material."
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            var data = try Data(contentsOf: url, options: [.mappedIfSafe])
            defer {
                if !data.isEmpty { data.resetBytes(in: 0..<data.count) }
            }
            let request = try await deviceTestProvisioning.prepareProbeBridgeImport(
                data,
                linkedSensorID: linkedSensorID,
                in: primaryStore
            )
            deviceTestProbeBridgeRequest = request
            hasDeviceTestProbeBridgePending = true
            deviceTestStatus =
                "Existing Probe material validated in memory. No Bluetooth action has started."
        } catch {
            deviceTestStatus = error.localizedDescription
        }
    }

    func runDeviceTestProbeBridgeScan() async {
        guard currentScenePhase == .active else {
            deviceTestStatus =
                "Keep Sugarman Device Test in the foreground for scan-only provisioning."
            return
        }
        guard !isDeviceTestArmed,
              !hasDeviceTestProvisioning,
              !isDeviceTestProbeBridgeScanning,
              let request = deviceTestProbeBridgeRequest else {
            return
        }
        isDeviceTestProbeBridgeScanning = true
        deviceTestStatus =
            "Scanning only for the exact Probe name; no peripheral connection or sensor command is allowed."
        do {
            let peripheralID = try await deviceTestProbeBridgeScanner.scan(
                matching: request
            )
            try await deviceTestProvisioning.completeProbeBridgeImport(
                request: request,
                peripheralID: peripheralID,
                into: primaryStore
            )
            deviceTestProbeBridgeRequest = nil
            hasDeviceTestProbeBridgePending = false
            isDeviceTestProbeBridgeScanning = false
            try await refreshFromStore()
            await refreshDeviceTestProvisioningAvailability()
            deviceTestStatus =
                "Known peripheral stored in this device's Keychain. No connection or sensor command was sent."
        } catch {
            isDeviceTestProbeBridgeScanning = false
            deviceTestStatus = error.localizedDescription
        }
    }

    func cancelDeviceTestProbeBridgeScan() {
        guard isDeviceTestProbeBridgeScanning else { return }
        deviceTestProbeBridgeScanner.cancel()
    }

    func discardDeviceTestProbeBridge() async {
        deviceTestProbeBridgeScanner.cancel()
        await deviceTestProvisioning.discardProbeBridgeImport()
        deviceTestProbeBridgeRequest = nil
        hasDeviceTestProbeBridgePending = false
        isDeviceTestProbeBridgeScanning = false
        deviceTestStatus =
            "Pending Probe material discarded. Importing or scanning is required before arming."
    }

    func armDeviceTest() async {
        guard !isSyntheticDemo else {
            deviceTestStatus = "Exit synthetic demo mode before arming the device test."
            return
        }
        guard hasDeviceTestProvisioning,
              !isDeviceTestArmed,
              !isDeviceTestProbeBridgeScanning else { return }
        let provisioning = deviceTestProvisioning
        let liveStore = primaryStore
        deviceTestLifecycleLines = []
        deviceTestAuthenticationAcknowledgementCount = 0
        deviceTestHistoryAcknowledgementCount = 0
        installForegroundSessionFactory { callbacks in
            try await provisioning.makeController(
                store: liveStore,
                callbacks: callbacks
            )
        }
        isDeviceTestArmed = true
        deviceTestStatus = "Managed foreground session armed."
        guard currentScenePhase == .active else { return }
        do {
            try await foregroundSessionBridge.enterForeground()
        } catch {
            isDeviceTestArmed = false
            await foregroundSessionBridge.removeFactory()
            deviceTestStatus = error.localizedDescription
        }
    }

    func stopDeviceTest() async {
        isDeviceTestArmed = false
        await foregroundSessionBridge.removeFactory()
        if hasDeviceTestProvisioning {
            deviceTestStatus =
                "Managed foreground session stopped. Private material remains device-only."
        }
        await refresh()
    }

    func deleteDeviceTestProvisioning() async {
        deviceTestProbeBridgeScanner.cancel()
        await stopDeviceTest()
        do {
            try await deviceTestProvisioning.delete()
            hasDeviceTestProvisioning = false
            deviceTestLinkedSensorID = nil
            deviceTestProbeBridgeRequest = nil
            hasDeviceTestProbeBridgePending = false
            isDeviceTestProbeBridgeScanning = false
            deviceTestLifecycleLines = []
            deviceTestAuthenticationAcknowledgementCount = 0
            deviceTestHistoryAcknowledgementCount = 0
            deviceTestStatus = "Private device-test material deleted from this device."
        } catch {
            deviceTestStatus = error.localizedDescription
        }
    }

    private func recordDeviceTestLifecycle(_ line: String) {
        deviceTestLifecycleLines.append(line)
        if deviceTestLifecycleLines.count > 128 {
            deviceTestLifecycleLines.removeFirst(
                deviceTestLifecycleLines.count - 128
            )
        }
    }
#endif

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
#if SUGARMAN_DEVICE_TEST
        deviceTestProbeBridgeScanner.cancel()
        await stopDeviceTest()
        try await deviceTestProvisioning.delete()
        hasDeviceTestProvisioning = false
        deviceTestLinkedSensorID = nil
        deviceTestProbeBridgeRequest = nil
        hasDeviceTestProbeBridgePending = false
        isDeviceTestProbeBridgeScanning = false
#endif
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
