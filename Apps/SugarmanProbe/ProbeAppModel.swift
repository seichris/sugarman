// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3DeveloperProbe
import Observation

@Observable
@MainActor
final class ProbeAppModel {
    var hasMaterial = false
    var expectedPeripheralName: String?
    var peripherals: [ProbePeripheral] = []
    var searchText = ""
    var status = "Import private material to begin."
    var isScanning = false
    var isRunning = false
    var reading: V3ProbeReading?
    var validatedLiveReadingCount = 0
    var diagnostics: [ProbeDiagnosticEntry] = []

    var redactedDiagnosticReport: String {
        let lines = diagnostics.map(\.displayText)
        return ([
            "Sugarman Probe redacted diagnostics",
            "Packet bodies are omitted except for an allowlisted protocol command byte; device identifiers, private material, glucose values, and record indexes are also omitted.",
            "Final status: \(status)",
            "",
        ] + lines).joined(separator: "\n")
    }

    @ObservationIgnored
    private let materialStore = KeychainV3ProbeMaterialStore()
    @ObservationIgnored
    private lazy var runtime = V3ProbeBluetoothRuntime { [weak self] event in
        Task { @MainActor in
            self?.handle(event)
        }
    }

    init() {
        Task { await refreshMaterialState() }
    }

    var visiblePeripherals: [ProbePeripheral] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return peripherals
            .filter { peripheral in
                query.isEmpty
                    || peripheral.displayName.localizedCaseInsensitiveContains(query)
                    || peripheral.id.uuidString.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                let lhsTarget = lhs.name == expectedPeripheralName
                let rhsTarget = rhs.name == expectedPeripheralName
                if lhsTarget != rhsTarget { return lhsTarget }
                if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func canRun(_ peripheral: ProbePeripheral) -> Bool {
        expectedPeripheralName.map { peripheral.name == $0 } ?? true
    }

    func importMaterial(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            var data = try Data(contentsOf: url, options: [.mappedIfSafe])
            defer { data.resetBytes(in: 0..<data.count) }
            let material = try V3ProbeMaterial(importJSONData: data)
            try await materialStore.replace(with: material)
            hasMaterial = true
            expectedPeripheralName = material.expectedPeripheralName
            status = "Private material imported into this device's Keychain."
        } catch {
            status = error.localizedDescription
        }
    }

    func deleteMaterial() async {
        do {
            runtime.cancel()
            try await materialStore.delete()
            hasMaterial = false
            expectedPeripheralName = nil
            reading = nil
            validatedLiveReadingCount = 0
            diagnostics = []
            status = "Private material deleted from this device."
        } catch {
            status = error.localizedDescription
        }
    }

    func startScan() {
        guard hasMaterial, !isRunning else { return }
        reading = nil
        validatedLiveReadingCount = 0
        peripherals = []
        isScanning = true
        runtime.startScanning()
    }

    func stopScan() {
        runtime.stopScanning()
        isScanning = false
    }

    func runProbe(peripheral: ProbePeripheral) async {
        guard !isRunning else { return }
        guard canRun(peripheral) else {
            status = "The selected peripheral does not match the imported expected name."
            return
        }
        do {
            guard let material = try await materialStore.load() else {
                hasMaterial = false
                status = "Private material is missing. Import it again."
                return
            }
            isScanning = false
            isRunning = true
            reading = nil
            validatedLiveReadingCount = 0
            diagnostics = []
            runtime.run(peripheral: peripheral, material: material)
        } catch {
            isRunning = false
            status = error.localizedDescription
        }
    }

    func cancelProbe() {
        runtime.cancel()
    }

    private func refreshMaterialState() async {
        do {
            let material = try await materialStore.load()
            hasMaterial = material != nil
            expectedPeripheralName = material?.expectedPeripheralName
            status = material == nil
                ? "Import private material to begin."
                : "Private material is available in this device's Keychain."
        } catch {
            hasMaterial = false
            status = error.localizedDescription
        }
    }

    private func handle(_ event: ProbeRuntimeEvent) {
        switch event {
        case .discovered(let peripheral):
            if let index = peripherals.firstIndex(where: { $0.id == peripheral.id }) {
                peripherals[index] = peripheral
            } else {
                peripherals.append(peripheral)
            }
        case .status(let message):
            status = message
        case .diagnostic(let entry):
            diagnostics.append(entry)
            if diagnostics.count > 64 {
                diagnostics.removeFirst(diagnostics.count - 64)
            }
        case .reading(let value):
            reading = value
            if value.source == .liveNotification {
                validatedLiveReadingCount += 1
            }
        case .failed(let message):
            status = message
            isRunning = false
            isScanning = false
        case .finished(let completedSuccessfully):
            isRunning = false
            isScanning = false
            if completedSuccessfully {
                status = "Five live readings validated; bounded probe disconnected."
            }
        }
    }
}
