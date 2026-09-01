// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AccountBinding
import GS3DeviceProvisioning
import GS3ProvisioningScan
#if SUGARMAN_DEVICE_TEST
import GS3DeviceTesting
import GS3Session
#endif
import GS3Transport
import Integrations
import Observation
import PrivateDocumentImport
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
    private var foregroundSessionBridge: GS3ForegroundSessionLifecycle
    private var currentScenePhase: ScenePhase
#if !SUGARMAN_DEVICE_TEST
    private var persistentSessionBridge: GS3PersistentSessionLifecycle
    private var didBootstrapPersistentSensorConnection: Bool
    var hasSensorProvisioning: Bool
    var provisionedSensorID: UUID?
    var isSensorConnectionEnabled: Bool
    var sensorConnectionStatus: String
    var sensorConnectionActivity: SensorConnectionActivity
    var hasSensorProbeBridgePending: Bool
    var isSensorProbeBridgeScanning: Bool
    @ObservationIgnored private let sensorProvisioning: DeviceOnlyGS3Provisioning
    @ObservationIgnored private let sensorExternalOwnershipGate:
        GS3ExternalOwnershipGate
    @ObservationIgnored private let sensorProbeBridgeScanner:
        GS3ProbeProvisioningScanner
    @ObservationIgnored private var sensorProbeBridgeRequest:
        GS3ProbeBridgeScanRequest?
#endif
#if SUGARMAN_DEVICE_TEST
    var hasDeviceTestProvisioning: Bool
    var deviceTestLinkedSensorID: UUID?
    var isDeviceTestArmed: Bool
    var deviceTestStatus: String
    var deviceTestLifecycleLines: [String]
    var deviceTestAuthenticationAcknowledgementCount: Int
    var deviceTestHistoryAcknowledgementCount: Int
    var deviceTestPhase: GS3ForegroundPhase
    var isDeviceTestLinkLossInjectionPending: Bool
    var hasDeviceTestProbeBridgePending: Bool
    var isDeviceTestProbeBridgeScanning: Bool
    @ObservationIgnored private let deviceTestProvisioning: DeviceOnlyGS3Provisioning
    @ObservationIgnored private let deviceTestExternalOwnershipGate:
        GS3ExternalOwnershipGate
    @ObservationIgnored private let deviceTestProbeBridgeScanner:
        GS3ProbeProvisioningScanner
    @ObservationIgnored private var deviceTestProbeBridgeRequest:
        GS3ProbeBridgeScanRequest?
    @ObservationIgnored private var managedDeviceTestController:
        GS3ManagedForegroundDeviceTestController?
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
        self.foregroundSessionBridge = GS3ForegroundSessionLifecycle()
        self.currentScenePhase = .inactive
#if !SUGARMAN_DEVICE_TEST
        self.persistentSessionBridge = GS3PersistentSessionLifecycle()
        self.didBootstrapPersistentSensorConnection = false
        let externalOwnershipGate = GS3ExternalOwnershipGate()
        self.hasSensorProvisioning = false
        self.provisionedSensorID = nil
        self.isSensorConnectionEnabled = false
        self.sensorConnectionStatus =
            "Import the private handover file for this already-active sensor."
        self.sensorConnectionActivity = .notConfigured
        self.hasSensorProbeBridgePending = false
        self.isSensorProbeBridgeScanning = false
        self.sensorProvisioning = DeviceOnlyGS3Provisioning(scope: .production)
        self.sensorExternalOwnershipGate = externalOwnershipGate
        self.sensorProbeBridgeScanner = GS3ProbeProvisioningScanner(
            externalOwnershipGate: externalOwnershipGate
        )
        self.sensorProbeBridgeRequest = nil
#endif
#if SUGARMAN_DEVICE_TEST
        let externalOwnershipGate = GS3ExternalOwnershipGate()
        self.hasDeviceTestProvisioning = false
        self.deviceTestLinkedSensorID = nil
        self.isDeviceTestArmed = false
        self.deviceTestStatus = "Import private material after storing an owned sensor identity."
        self.deviceTestLifecycleLines = []
        self.deviceTestAuthenticationAcknowledgementCount = 0
        self.deviceTestHistoryAcknowledgementCount = 0
        self.deviceTestPhase = .idle
        self.isDeviceTestLinkLossInjectionPending = false
        self.hasDeviceTestProbeBridgePending = false
        self.isDeviceTestProbeBridgeScanning = false
        self.deviceTestProvisioning = DeviceOnlyGS3Provisioning(scope: .deviceTest)
        self.deviceTestExternalOwnershipGate = externalOwnershipGate
        self.deviceTestProbeBridgeScanner = GS3ProbeProvisioningScanner(
            externalOwnershipGate: externalOwnershipGate
        )
        self.deviceTestProbeBridgeRequest = nil
        self.managedDeviceTestController = nil
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
        currentScenePhase = phase
        switch phase {
        case .active:
#if SUGARMAN_DEVICE_TEST
            do {
                try await foregroundSessionBridge.enterForeground()
            } catch {
                // The bridge and coordinator expose only typed, redacted
                // failures. Keep prior readings fail closed through the
                // persisted disconnected projection.
                storeErrorMessage = String(localized: "live.session_start_failed")
            }
#else
            await bootstrapPersistentSensorConnectionIfNeeded()
#endif
        case .inactive:
            // Transient foreground interruptions (for example, system UI)
            // must not churn ownership or manufacture a reconnect.
            break
        case .background:
#if SUGARMAN_DEVICE_TEST
            deviceTestProbeBridgeScanner.cancel()
            await foregroundSessionBridge.leaveForeground()
#else
            sensorProbeBridgeScanner.cancel()
            await bootstrapPersistentSensorConnectionIfNeeded()
#endif
        @unknown default:
#if SUGARMAN_DEVICE_TEST
            deviceTestProbeBridgeScanner.cancel()
            await foregroundSessionBridge.leaveForeground()
#else
            sensorProbeBridgeScanner.cancel()
            await bootstrapPersistentSensorConnectionIfNeeded()
#endif
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
        let callbacks = makeDeviceTestCallbacks()
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

#if !SUGARMAN_DEVICE_TEST
    private func bootstrapPersistentSensorConnectionIfNeeded() async {
        guard !didBootstrapPersistentSensorConnection else { return }
        didBootstrapPersistentSensorConnection = true
        do {
            let summary = try await sensorProvisioning.summary()
            hasSensorProvisioning = summary != nil
            provisionedSensorID = summary?.linkedSensorID
            guard summary?.connectionIntentEnabled == true else {
                isSensorConnectionEnabled = false
                sensorConnectionActivity = summary == nil ? .notConfigured : .stopped
                return
            }
            installPersistentSensorFactory()
            isSensorConnectionEnabled = true
            sensorConnectionActivity = .connecting
            sensorConnectionStatus = "Connecting to the sensor."
            try await persistentSessionBridge.startIfNeeded()
        } catch {
            isSensorConnectionEnabled = false
            sensorConnectionActivity = .failed
            sensorConnectionStatus =
                "The saved sensor connection failed closed. Open Sensor Connection to try again."
            try? await sensorProvisioning.setConnectionIntentEnabled(false)
            await persistentSessionBridge.removeFactory()
        }
    }

    private func installPersistentSensorFactory() {
        let provisioning = sensorProvisioning
        let liveStore = primaryStore
        let callbacks = makeSensorCallbacks()
        persistentSessionBridge.install {
            try await provisioning.makeController(
                store: liveStore,
                callbacks: callbacks
            )
        }
    }

    private func makeSensorCallbacks() -> GS3ForegroundSessionCallbacks {
        GS3ForegroundSessionCallbacks(
            onConnection: { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.connection = connection
                    await self?.refresh()
                }
            },
            onLifecycleEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.isSensorConnectionEnabled else { return }
                    self.sensorConnectionActivity = SensorConnectionActivity(
                        phase: event.phase
                    )
                    self.sensorConnectionStatus = self.sensorActivityStatus
                }
            },
            onSamplesCommitted: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            },
            onFailure: { [weak self] failure in
                Task { @MainActor [weak self] in
                    await self?.handleSensorSessionFailure(failure)
                }
            }
        )
    }

    private func handleSensorSessionFailure(
        _ failure: GS3ForegroundCoordinatorFailure
    ) async {
        sensorConnectionActivity = .failed
        sensorConnectionStatus =
            "The sensor connection failed closed. Open Sensor Connection to try again."
        isSensorConnectionEnabled = false
        if failure != .ownershipUnavailable {
            try? await sensorProvisioning.setConnectionIntentEnabled(false)
        }
        await persistentSessionBridge.removeFactory()
        await refresh()
    }

    var sensorActivityStatus: String {
        switch sensorConnectionActivity {
        case .notConfigured:
            "Set up the sensor connection to receive readings."
        case .stopped:
            "Sensor connection is stopped."
        case .connecting:
            "Connecting to the sensor."
        case .synchronizing:
            "Synchronizing sensor history."
        case .live:
            "Sensor connection is live."
        case .reconnecting:
            "Reconnecting to the sensor."
        case .failed:
            "The sensor connection failed closed."
        }
    }

    func refreshSensorProvisioningAvailability() async {
        do {
            let summary = try await sensorProvisioning.summary()
            hasSensorProvisioning = summary != nil
            provisionedSensorID = summary?.linkedSensorID
            if !isSensorConnectionEnabled {
                sensorConnectionActivity = summary == nil ? .notConfigured : .stopped
            }
            if summary != nil, !isSensorConnectionEnabled {
                sensorConnectionStatus =
                    "Private connection material is available in this iPhone's Keychain."
            } else if summary == nil {
                sensorConnectionStatus = hasSensorProbeBridgePending
                    ? "Private handover material is ready in memory. Run the scan-only lookup next."
                    : "Import the private handover file for this already-active sensor."
            }
        } catch {
            hasSensorProvisioning = false
            provisionedSensorID = nil
            sensorConnectionStatus = error.localizedDescription
        }
    }

    func prepareSensorProbeBridge(
        from url: URL,
        linkedSensorID: UUID
    ) async {
        guard !isSensorConnectionEnabled,
              !hasSensorProvisioning,
              !isSensorProbeBridgeScanning else {
            sensorConnectionStatus =
                "Disconnect before importing private handover material."
            return
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let buffer = try PrivateDocumentImportBuffer(contentsOf: url)
            defer { buffer.zeroize() }
            let request = try await buffer.withData { data in
                try await sensorProvisioning.prepareProbeBridgeImport(
                    data,
                    linkedSensorID: linkedSensorID,
                    in: primaryStore
                )
            }
            sensorProbeBridgeRequest = request
            hasSensorProbeBridgePending = true
            sensorConnectionStatus =
                "Private handover material is ready in memory. No Bluetooth action has started."
        } catch {
            sensorConnectionStatus = sensorProvisioningFailureMessage(error)
        }
    }

    func confirmExclusiveSensorAccess() {
        sensorExternalOwnershipGate.confirmExclusiveAccess()
    }

    func runSensorProbeBridgeScan() async {
        defer { sensorExternalOwnershipGate.revoke() }
        guard currentScenePhase == .active else {
            sensorConnectionStatus =
                "Keep Sugarman in the foreground for the scan-only lookup."
            return
        }
        guard !isSensorConnectionEnabled,
              !hasSensorProvisioning,
              !isSensorProbeBridgeScanning,
              let request = sensorProbeBridgeRequest else { return }
        isSensorProbeBridgeScanning = true
        sensorConnectionStatus =
            "Scanning only for the exact private sensor name. No connection or command is allowed."
        do {
            let peripheralID = try await sensorProbeBridgeScanner.scan(
                matching: request
            )
            try await sensorProvisioning.completeProbeBridgeImport(
                request: request,
                peripheralID: peripheralID,
                into: primaryStore
            )
            sensorProbeBridgeRequest = nil
            hasSensorProbeBridgePending = false
            isSensorProbeBridgeScanning = false
            try await refreshFromStore()
            await refreshSensorProvisioningAvailability()
            sensorConnectionStatus =
                "Sensor connection is ready. The scan did not connect or send a command."
        } catch {
            isSensorProbeBridgeScanning = false
            sensorConnectionStatus = sensorProvisioningFailureMessage(error)
        }
    }

    func cancelSensorProbeBridgeScan() {
        guard isSensorProbeBridgeScanning else { return }
        sensorProbeBridgeScanner.cancel()
    }

    func discardSensorProbeBridge() async {
        sensorProbeBridgeScanner.cancel()
        await sensorProvisioning.discardProbeBridgeImport()
        sensorProbeBridgeRequest = nil
        hasSensorProbeBridgePending = false
        isSensorProbeBridgeScanning = false
        sensorConnectionStatus =
            "Pending private handover material was discarded."
    }

    func connectSensor() async {
        defer { sensorExternalOwnershipGate.revoke() }
        guard !isSyntheticDemo else {
            sensorConnectionStatus = "Exit demo mode before connecting to the sensor."
            return
        }
        guard hasSensorProvisioning,
              !isSensorConnectionEnabled,
              !isSensorProbeBridgeScanning else { return }
        do {
            try sensorExternalOwnershipGate.requireConfirmation()
        } catch {
            sensorConnectionStatus = error.localizedDescription
            return
        }

        do {
            didBootstrapPersistentSensorConnection = true
            try await sensorProvisioning.setConnectionIntentEnabled(true)
            installPersistentSensorFactory()
            isSensorConnectionEnabled = true
            sensorConnectionActivity = .connecting
            sensorConnectionStatus = "Connecting to the sensor."
            try await persistentSessionBridge.startIfNeeded()
        } catch {
            isSensorConnectionEnabled = false
            sensorConnectionActivity = .failed
            try? await sensorProvisioning.setConnectionIntentEnabled(false)
            await persistentSessionBridge.removeFactory()
            sensorConnectionStatus =
                "The sensor connection failed closed. No private details were retained."
        }
    }

    func stopSensorConnection() async {
        isSensorConnectionEnabled = false
        sensorConnectionActivity = hasSensorProvisioning ? .stopped : .notConfigured
        sensorExternalOwnershipGate.revoke()
        try? await sensorProvisioning.setConnectionIntentEnabled(false)
        await persistentSessionBridge.removeFactory()
        if hasSensorProvisioning {
            sensorConnectionStatus =
                "Sensor disconnected. Private material remains device-only."
        }
        await refresh()
    }

    func deleteSensorProvisioning() async {
        sensorProbeBridgeScanner.cancel()
        await stopSensorConnection()
        do {
            try await sensorProvisioning.delete()
            hasSensorProvisioning = false
            provisionedSensorID = nil
            sensorProbeBridgeRequest = nil
            hasSensorProbeBridgePending = false
            isSensorProbeBridgeScanning = false
            sensorConnectionStatus =
                "Private sensor connection material was deleted from this iPhone."
            sensorConnectionActivity = .notConfigured
        } catch {
            sensorConnectionStatus = sensorProvisioningFailureMessage(error)
        }
    }

    private func sensorProvisioningFailureMessage(_ error: Error) -> String {
        switch error {
        case let error as GS3DeviceProvisioningError:
            error.localizedDescription
        case let error as GS3ProbeProvisioningScanError:
            error.localizedDescription
        case let error as GS3ExternalOwnershipError:
            error.localizedDescription
        default:
            "The private sensor operation failed closed. No file or private details were retained."
        }
    }
#endif

#if SUGARMAN_DEVICE_TEST
    private func makeDeviceTestCallbacks() -> GS3ForegroundSessionCallbacks {
        let refresh: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        return GS3ForegroundSessionCallbacks(
            onConnection: { _ in refresh() },
            onLifecycleEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.deviceTestPhase = event.phase
                    if event.phase == .live {
                        self?.isDeviceTestLinkLossInjectionPending = false
                    }
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
            onNativeStateObserved: { [weak self] summary in
                Task { @MainActor [weak self] in
                    self?.recordDeviceTestLifecycle(summary.description)
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
    }

    var redactedDeviceTestReport: String {
        ([
            "Sugarman managed foreground device-test diagnostics",
            "Packet bodies, arbitrary command bytes, sensor identifiers, private material, glucose values, record indexes, and imported JSON contents or hashes are omitted.",
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
            let buffer = try PrivateDocumentImportBuffer(contentsOf: url)
            defer { buffer.zeroize() }
            try await buffer.withData { data in
                try await deviceTestProvisioning.importDocument(
                    data,
                    linkedSensorID: linkedSensorID,
                    into: primaryStore
                )
            }
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
            let buffer = try PrivateDocumentImportBuffer(contentsOf: url)
            defer { buffer.zeroize() }
            let request = try await buffer.withData { data in
                try await deviceTestProvisioning.prepareProbeBridgeImport(
                    data,
                    linkedSensorID: linkedSensorID,
                    in: primaryStore
                )
            }
            deviceTestProbeBridgeRequest = request
            hasDeviceTestProbeBridgePending = true
            deviceTestStatus =
                "Existing Probe material validated in memory. No Bluetooth action has started."
        } catch {
            deviceTestStatus = error.localizedDescription
        }
    }

    func runDeviceTestProbeBridgeScan() async {
        defer { deviceTestExternalOwnershipGate.revoke() }
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

    func confirmExclusiveAccessForDeviceTest() {
        deviceTestExternalOwnershipGate.confirmExclusiveAccess()
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
            deviceTestExternalOwnershipGate.revoke()
            deviceTestStatus = "Exit synthetic demo mode before arming the device test."
            return
        }
        guard hasDeviceTestProvisioning,
              !isDeviceTestArmed,
              !isDeviceTestProbeBridgeScanning else {
            deviceTestExternalOwnershipGate.revoke()
            return
        }
        do {
            try deviceTestExternalOwnershipGate.requireConfirmation()
        } catch {
            deviceTestExternalOwnershipGate.revoke()
            deviceTestStatus = error.localizedDescription
            return
        }
        let provisioning = deviceTestProvisioning
        let liveStore = primaryStore
        deviceTestLifecycleLines = []
        deviceTestAuthenticationAcknowledgementCount = 0
        deviceTestHistoryAcknowledgementCount = 0
        deviceTestPhase = .idle
        isDeviceTestLinkLossInjectionPending = false
        let callbacks = makeDeviceTestCallbacks()
        do {
            let controller = try await provisioning.makeManagedForegroundDeviceTestController(
                store: liveStore,
                callbacks: callbacks
            )
            managedDeviceTestController = controller
            foregroundSessionBridge.install { controller }
        } catch {
            deviceTestExternalOwnershipGate.revoke()
            deviceTestStatus = error.localizedDescription
            return
        }
        isDeviceTestArmed = true
        deviceTestStatus = "Managed foreground session armed."
        guard currentScenePhase == .active else { return }
        do {
            try await foregroundSessionBridge.enterForeground()
        } catch {
            isDeviceTestArmed = false
            managedDeviceTestController = nil
            deviceTestExternalOwnershipGate.revoke()
            await foregroundSessionBridge.removeFactory()
            deviceTestStatus = error.localizedDescription
        }
    }

    func stopDeviceTest() async {
        isDeviceTestArmed = false
        deviceTestPhase = .stopped
        isDeviceTestLinkLossInjectionPending = false
        deviceTestExternalOwnershipGate.revoke()
        await foregroundSessionBridge.removeFactory()
        managedDeviceTestController = nil
        if hasDeviceTestProvisioning {
            deviceTestStatus =
                "Managed foreground session stopped. Private material remains device-only."
        }
        await refresh()
    }

    func injectDeviceTestLinkLoss() async {
        guard isDeviceTestArmed,
              deviceTestPhase == .live,
              !isDeviceTestLinkLossInjectionPending,
              let managedDeviceTestController else { return }
        isDeviceTestLinkLossInjectionPending = true
        if await managedDeviceTestController.injectLinkLoss() {
            deviceTestStatus =
                "Injected one Device-Test-only link loss; awaiting bounded reconnect."
        } else {
            isDeviceTestLinkLossInjectionPending = false
            deviceTestStatus =
                "Link-loss injection was inert because the session was not live."
        }
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
#else
        sensorProbeBridgeScanner.cancel()
        await stopSensorConnection()
        try await sensorProvisioning.delete()
        hasSensorProvisioning = false
        provisionedSensorID = nil
        sensorProbeBridgeRequest = nil
        hasSensorProbeBridgePending = false
        isSensorProbeBridgeScanning = false
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
