// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Transport
import Observation
import SugarmanDiagnostics

enum ProbePlatform: Sendable {
    static var supportsLiveCoreBluetooth: Bool {
        #if os(iOS) && !targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

/// Settings/Privacy probe. Default off. Device uses CoreBluetoothRuntime;
/// simulator cannot enable a live probe.
@Observable
@MainActor
final class DiagnosticProbeSession {
    var isEnabled = false
    var peripherals: [AdvertisementSnapshot] = []
    var status = String(localized: "privacy.probe_disabled")
    var deviceInformation: DeviceInformationSnapshot?
    var selectedPeripheralID: UUID?
    var gattMap: RedactedGATTMap?
    var gattMapFileURL: URL?

    private var probe: ReadOnlyDiagnosticProbe?
    #if canImport(CoreBluetooth)
    private var liveRuntime: CoreBluetoothRuntime?
    #endif
    private var pollTask: Task<Void, Never>?
    private var activeConnectionOperationID: UUID?

    var canEnable: Bool { ProbePlatform.supportsLiveCoreBluetooth }

    func setEnabled(_ enabled: Bool) async {
        activeConnectionOperationID = nil
        pollTask?.cancel()
        pollTask = nil
        if let probe {
            do {
                try await probe.disconnect()
            } catch {
                clearSession()
                isEnabled = false
                status = error.localizedDescription
                return
            }
        }
        clearSession()

        guard enabled else {
            isEnabled = false
            status = String(localized: "privacy.probe_disabled")
            return
        }
        guard canEnable else {
            isEnabled = false
            status = String(localized: "privacy.probe_simulator")
            return
        }

        #if os(iOS) && !targetEnvironment(simulator) && canImport(CoreBluetooth)
        let runtime = CoreBluetoothRuntime()
        runtime.onDiscover = { [weak self] snapshot in
            Task { @MainActor in
                self?.upsert(snapshot)
            }
        }
        liveRuntime = runtime
        probe = ReadOnlyDiagnosticProbe(isEnabled: true, runtime: runtime)
        isEnabled = true
        status = String(localized: "privacy.probe_ready")
        #else
        isEnabled = false
        status = String(localized: "privacy.probe_simulator")
        #endif
    }

    func startScan() async {
        guard let probe, isEnabled else {
            status = String(localized: "privacy.probe_disabled")
            return
        }
        guard selectedPeripheralID == nil else {
            status = TransportError.commandInFlight.localizedDescription
            return
        }
        deviceInformation = nil
        do {
            try await probe.scan()
            status = String(localized: "privacy.probe_scanning")
            startPolling()
        } catch {
            status = error.localizedDescription
        }
    }

    func connectAndRead(_ peripheralID: UUID) async {
        guard let probe, isEnabled else {
            status = String(localized: "privacy.probe_disabled")
            return
        }
        guard selectedPeripheralID == nil else {
            status = TransportError.commandInFlight.localizedDescription
            return
        }
        let operationID = UUID()
        activeConnectionOperationID = operationID
        selectedPeripheralID = peripheralID
        status = String(localized: "privacy.probe_connecting")
        do {
            let snapshot = try await probe.connectAndReadDeviceInformation(peripheralID: peripheralID)
            guard activeConnectionOperationID == operationID, isEnabled else { return }
            deviceInformation = snapshot
            try writeCurrentMap(probe: probe, peripheralID: peripheralID)
            try await probe.disconnect()
            guard activeConnectionOperationID == operationID, isEnabled else { return }
            activeConnectionOperationID = nil
            selectedPeripheralID = nil
            status = String(localized: "privacy.probe_dis_ok")
        } catch {
            guard activeConnectionOperationID == operationID, isEnabled else { return }
            let operationError = error
            var messages = [operationError.localizedDescription]
            do {
                try writeCurrentMap(probe: probe, peripheralID: peripheralID)
            } catch {
                messages.append(error.localizedDescription)
            }
            do {
                try await probe.disconnect()
            } catch {
                messages.append(error.localizedDescription)
            }
            guard activeConnectionOperationID == operationID, isEnabled else { return }
            activeConnectionOperationID = nil
            selectedPeripheralID = nil
            status = messages.joined(separator: " ")
        }
    }

    func disconnect() async {
        guard let probe else { return }
        activeConnectionOperationID = nil
        do {
            try await probe.disconnect()
            selectedPeripheralID = nil
            status = String(localized: "privacy.probe_disconnected")
        } catch {
            status = error.localizedDescription
        }
    }

    private func writeCurrentMap(probe: ReadOnlyDiagnosticProbe, peripheralID: UUID) throws {
        let name = peripherals.first(where: { $0.peripheralID == peripheralID })?.name
        let map = probe.redactedGATTMap(peripheralID: peripheralID, localName: name)
        gattMap = map
        gattMapFileURL = try GATTMapFileWriter().write(map, to: FileManager.default.temporaryDirectory)
    }

    private func clearSession() {
        activeConnectionOperationID = nil
        probe = nil
        #if canImport(CoreBluetooth)
        liveRuntime = nil
        #endif
        peripherals = []
        deviceInformation = nil
        selectedPeripheralID = nil
        gattMap = nil
        gattMapFileURL = nil
    }

    private func upsert(_ snapshot: AdvertisementSnapshot) {
        if let index = peripherals.firstIndex(where: { $0.peripheralID == snapshot.peripheralID }) {
            peripherals[index] = snapshot
        } else {
            peripherals.append(snapshot)
        }
        peripherals.sort { $0.peripheralID.uuidString < $1.peripheralID.uuidString }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self {
                    let latest = self.probe?.discoveredAdvertisements ?? []
                    for item in latest {
                        self.upsert(item)
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
