// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3DeviceProvisioning
import GS3DeviceTesting
import GS3Session
import GS3Transport
import Observation
import PrivateDocumentImport
import SugarmanDomain
import SugarmanStore
import SwiftUI

@Observable
@MainActor
final class MacDeviceTestModel {
    private static let maximumLifecycleLineCount = 128

    var hasProvisioning = false
    var hasPendingProbeBridge = false
    var isScanning = false
    var isArmed = false
    var isSceneActive = false
    var status = "Preparing the local device-test boundary."
    var lifecycleLines: [String] = []
    var authenticationAcknowledgementCount = 0
    var historyAcknowledgementCount = 0
    var privateRecentReadings: [GlucoseSample] = []
    var isLinkLossInjectionPending = false
    var deviceTestPhase: GS3ForegroundPhase = .idle

    @ObservationIgnored private let store: any SugarmanStoring
    @ObservationIgnored private let provisioning: DeviceOnlyGS3Provisioning
    @ObservationIgnored private let externalOwnershipGate:
        GS3DeviceTestExternalOwnershipGate
    @ObservationIgnored private let scanner: GS3ProbeProvisioningScanner
    @ObservationIgnored private let foregroundLifecycle:
        GS3ForegroundSessionLifecycle
    @ObservationIgnored private var linkedSensorID: UUID?
    @ObservationIgnored private var linkedSessionID: UUID?
    @ObservationIgnored private var pendingProbeRequest: GS3ProbeBridgeScanRequest?
    @ObservationIgnored private var deviceTestController:
        GS3ManagedForegroundDeviceTestController?

    static func bootstrapped() -> MacDeviceTestModel {
        let result = SugarmanStoreFactory.makePersistent()
        return MacDeviceTestModel(
            store: result.store,
            initialStoreError: result.loadError
        )
    }

    init(
        store: any SugarmanStoring = InMemorySugarmanStore(),
        initialStoreError: String? = nil
    ) {
        let externalOwnershipGate = GS3DeviceTestExternalOwnershipGate()
        self.store = store
        self.provisioning = DeviceOnlyGS3Provisioning()
        self.externalOwnershipGate = externalOwnershipGate
        self.scanner = GS3ProbeProvisioningScanner(
            externalOwnershipGate: externalOwnershipGate
        )
        self.foregroundLifecycle = GS3ForegroundSessionLifecycle()
        if initialStoreError != nil {
            status = "Persistent local storage is unavailable. Live testing remains disabled."
        }
    }

    var redactedReport: String {
        ([
            "Sugarman macOS managed foreground device-test diagnostics",
            "Packet bodies, arbitrary command bytes, sensor identifiers, private material, glucose values, record indexes, and imported JSON contents or hashes are omitted.",
            "Authentication write acknowledgements: \(authenticationAcknowledgementCount)",
            "History write acknowledgements: \(historyAcknowledgementCount)",
            "",
        ] + lifecycleLines).joined(separator: "\n")
    }

    func prepare() async {
        do {
            let summary = try await provisioning.summary()
            let identities = try await store.identities()
            if let summary {
                guard identities.contains(where: { $0.id == summary.linkedSensorID }) else {
                    hasProvisioning = true
                    linkedSensorID = nil
                    status =
                        "Private material exists, but its local redacted identity is missing. Delete it before reprovisioning."
                    return
                }
                hasProvisioning = true
                linkedSensorID = summary.linkedSensorID
                try await resolveLinkedSession(for: summary.linkedSensorID)
                await refreshPrivateReadings()
                status = "Mac-local private material is available in this Mac's Keychain."
                return
            }

            hasProvisioning = false
            if let identity = identities.first {
                linkedSensorID = identity.id
            } else {
                let identity = SensorIdentity(
                    productName: "Owned GS3",
                    redactedSerial: "redacted",
                    protocolVariant: .v3AES,
                    classificationEvidenceRevision: "mac-device-test-owner-confirmation-v1"
                )
                try await store.insertIdentity(identity)
                linkedSensorID = identity.id
            }
            status =
                "Import existing Probe JSON. Import validates private material but does not start Bluetooth."
        } catch {
            status = safeMessage(for: error)
        }
    }

    func prepareProbeBridge(from url: URL) async {
        guard !hasProvisioning,
              !hasPendingProbeBridge,
              !isScanning,
              !isArmed,
              let linkedSensorID else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let buffer = try PrivateDocumentImportBuffer(contentsOf: url)
            defer { buffer.zeroize() }
            pendingProbeRequest = try await buffer.withData { data in
                try await provisioning.prepareProbeBridgeImport(
                    data,
                    linkedSensorID: linkedSensorID,
                    in: store
                )
            }
            hasPendingProbeBridge = true
            status =
                "Probe material is validated in process memory. No Bluetooth action has started."
        } catch {
            status = safeMessage(for: error)
        }
    }

    func fileImportFailed() {
        status = "The private file was not selected or could not be read. No state changed."
    }

    func confirmAndRunProbeBridgeScan() async {
        externalOwnershipGate.confirmExclusiveAccess()
        defer { externalOwnershipGate.revoke() }
        guard isSceneActive else {
            status = "Keep the Mac Device Test window active for scan-only provisioning."
            return
        }
        guard !hasProvisioning,
              hasPendingProbeBridge,
              !isScanning,
              !isArmed,
              let request = pendingProbeRequest else { return }

        isScanning = true
        status =
            "Scanning for one exact private name. Connecting and sensor commands are unavailable."
        do {
            let peripheralID = try await scanner.scan(
                matching: request,
                timeoutSeconds: GS3ProbeProvisioningScanner.scanWindowSeconds
            )
            try await provisioning.completeProbeBridgeImport(
                request: request,
                peripheralID: peripheralID,
                into: store
            )
            pendingProbeRequest = nil
            hasPendingProbeBridge = false
            hasProvisioning = true
            status =
                "Mac-local provisioning is stored. The scan ended without connecting or writing."
        } catch {
            status = safeMessage(for: error)
        }
        isScanning = false
    }

    func cancelProbeBridgeScan() {
        guard isScanning else { return }
        scanner.cancel()
    }

    func discardPendingProbeBridge() async {
        scanner.cancel()
        await provisioning.discardProbeBridgeImport()
        externalOwnershipGate.revoke()
        pendingProbeRequest = nil
        hasPendingProbeBridge = false
        isScanning = false
        status = "Pending Probe material was discarded from process memory."
    }

    func confirmAndArm() async {
        externalOwnershipGate.confirmExclusiveAccess()
        await arm()
    }

    func stop() async {
        isArmed = false
        isLinkLossInjectionPending = false
        deviceTestPhase = .stopped
        externalOwnershipGate.revoke()
        await foregroundLifecycle.removeFactory()
        deviceTestController = nil
        status = hasProvisioning
            ? "Managed foreground session stopped. Private material remains Mac-local."
            : "Managed foreground session stopped."
    }

    func injectLinkLoss() async {
        guard isArmed,
              deviceTestPhase == .live,
              !isLinkLossInjectionPending,
              let deviceTestController else { return }
        isLinkLossInjectionPending = true
        if await deviceTestController.injectLinkLoss() {
            status = "Injected one Device-Test-only link loss; awaiting bounded reconnect."
        } else {
            isLinkLossInjectionPending = false
            status = "Link-loss injection was inert because the session was not live."
        }
    }

    func deleteProvisioning() async {
        scanner.cancel()
        await stop()
        await provisioning.discardProbeBridgeImport()
        do {
            try await provisioning.delete()
            hasProvisioning = false
            hasPendingProbeBridge = false
            pendingProbeRequest = nil
            status = "Mac-local private provisioning material was deleted."
        } catch {
            status = safeMessage(for: error)
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .active:
            isSceneActive = true
        case .inactive:
            break
        case .background:
            isSceneActive = false
            scanner.cancel()
            if isArmed {
                await stop()
            } else {
                externalOwnershipGate.revoke()
                await foregroundLifecycle.leaveForeground()
            }
        @unknown default:
            isSceneActive = false
            scanner.cancel()
            if isArmed {
                await stop()
            }
        }
    }

    func shutdown() async {
        scanner.cancel()
        await discardPendingProbeBridge()
        await stop()
    }

    private func arm() async {
        guard isSceneActive else {
            externalOwnershipGate.revoke()
            status = "Keep the Mac Device Test window active before arming."
            return
        }
        guard hasProvisioning, !isScanning, !isArmed else {
            externalOwnershipGate.revoke()
            return
        }
        do {
            try externalOwnershipGate.requireConfirmation()
        } catch {
            externalOwnershipGate.revoke()
            status = safeMessage(for: error)
            return
        }

        lifecycleLines = []
        authenticationAcknowledgementCount = 0
        historyAcknowledgementCount = 0
        isLinkLossInjectionPending = false
        deviceTestPhase = .idle
        let callbacks = makeCallbacks()
        let provisioning = self.provisioning
        let store = self.store
        do {
            let controller = try await provisioning.makeManagedForegroundDeviceTestController(
                store: store,
                callbacks: callbacks
            )
            deviceTestController = controller
            foregroundLifecycle.install { controller }
        } catch {
            externalOwnershipGate.revoke()
            status = safeMessage(for: error)
            return
        }
        isArmed = true
        status = "Managed foreground session armed on this Mac."
        do {
            try await foregroundLifecycle.enterForeground()
        } catch {
            isArmed = false
            deviceTestController = nil
            externalOwnershipGate.revoke()
            await foregroundLifecycle.removeFactory()
            status = safeMessage(for: error)
        }
    }

    private func makeCallbacks() -> GS3ForegroundSessionCallbacks {
        GS3ForegroundSessionCallbacks(
            onConnection: { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.status = "Managed connection state: \(connection.rawValue)."
                }
            },
            onLifecycleEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.deviceTestPhase = event.phase
                    if event.phase == .live {
                        self?.isLinkLossInjectionPending = false
                    }
                    self?.recordLifecycle(event.description)
                }
            },
            onSamplesCommitted: { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshPrivateReadings()
                }
            },
            onCommandAcknowledged: { [weak self] command in
                Task { @MainActor [weak self] in
                    switch command {
                    case .authentication:
                        self?.authenticationAcknowledgementCount += 1
                    case .effectiveData:
                        self?.historyAcknowledgementCount += 1
                    }
                }
            },
            onFailure: { [weak self] failure in
                Task { @MainActor [weak self] in
                    self?.status =
                        "Managed foreground session failed closed (\(failure.rawValue))."
                }
            }
        )
    }

    private func recordLifecycle(_ line: String) {
        lifecycleLines.append(line)
        if lifecycleLines.count > Self.maximumLifecycleLineCount {
            lifecycleLines.removeFirst(
                lifecycleLines.count - Self.maximumLifecycleLineCount
            )
        }
    }

    private func resolveLinkedSession(for sensorID: UUID) async throws {
        let matching = try await store.allSessions().filter {
            $0.sensorID == sensorID && $0.lifecycle == .live
        }
        guard matching.count == 1, let session = matching.first else {
            throw GS3DeviceProvisioningError.sessionConflict
        }
        linkedSessionID = session.id
    }

    private func refreshPrivateReadings() async {
        guard let linkedSessionID else {
            privateRecentReadings = []
            return
        }
        do {
            privateRecentReadings = Array(
                try await store.samples(sessionID: linkedSessionID).suffix(8)
            )
        } catch {
            privateRecentReadings = []
        }
    }

    private func safeMessage(for error: Error) -> String {
        switch error {
        case let error as GS3DeviceProvisioningError:
            error.localizedDescription
        case let error as GS3ProbeProvisioningScanError:
            error.localizedDescription
        case let error as GS3DeviceTestExternalOwnershipError:
            error.localizedDescription
        default:
            "The operation failed closed. No private details were retained in diagnostics."
        }
    }
}
