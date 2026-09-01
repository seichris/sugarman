// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3DeveloperProbe
import SwiftUI
import UniformTypeIdentifiers

struct ProbeView: View {
    @Environment(ProbeAppModel.self) private var model
    @State private var showImporter = false
    @State private var showDeleteConfirmation = false
    @State private var pendingPeripheral: ProbePeripheral?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Text("Developer-only, owner-controlled handover probe")
                        .font(.headline)
                    Text("This separate app can subscribe to FF31, transmit one 0xE2 authentication, and—only after the captured 01 00 acceptance—transmit one 0x39 request. It then observes five live readings without another write. While that 0x39 write acknowledgement is pending, it may quarantine exactly one checksum-valid 24-byte unsupported command without interpreting it. It never retries, reconnects, activates, binds, resets, or writes HealthKit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Private material") {
                    LabeledContent("Keychain", value: model.hasMaterial ? "Available" : "Missing")
                    if let expected = model.expectedPeripheralName {
                        LabeledContent("Expected local name", value: expected)
                    }
                    Button("Import private JSON file", systemImage: "lock.doc") {
                        showImporter = true
                    }
                    if model.hasMaterial {
                        Button("Delete private material", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }

                Section("Bounded session") {
                    Text(model.status)
                        .font(.footnote)
                    if model.isRunning {
                        ProgressView()
                        Button("Cancel and disconnect", role: .cancel) {
                            model.cancelProbe()
                        }
                    } else if model.isScanning {
                        Button("Stop scan") { model.stopScan() }
                    } else {
                        Button("Scan for owned sensor", systemImage: "antenna.radiowaves.left.and.right") {
                            model.startScan()
                        }
                        .disabled(!model.hasMaterial)
                    }
                }

                if !model.diagnostics.isEmpty {
                    Section("Redacted diagnostics") {
                        Text("Kept in memory only. Packet bodies are omitted except for an allowlisted protocol command byte; identifiers, private material, glucose values, and record indexes are also omitted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.diagnostics) { entry in
                            Text(entry.displayText)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        ShareLink(
                            item: model.redactedDiagnosticReport,
                            subject: Text("Sugarman Probe redacted diagnostics")
                        ) {
                            Label("Share redacted diagnostics", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let reading = model.reading {
                    Section("One-shot result") {
                        LabeledContent(
                            "Glucose",
                            value: String(format: "%.1f mmol/L", reading.glucoseMillimolesPerLiter)
                        )
                        LabeledContent("Trend code", value: String(reading.trendCode))
                        LabeledContent("Record index", value: String(reading.index))
                        LabeledContent(
                            "Source",
                            value: reading.source == .liveNotification ? "live 0x32" : "effective data 0x39"
                        )
                        LabeledContent(
                            "Validated live readings",
                            value: "\(model.validatedLiveReadingCount)/5"
                        )
                    }
                }

                if model.isScanning || !model.peripherals.isEmpty {
                    Section("Discovered peripherals") {
                        ForEach(model.visiblePeripherals) { peripheral in
                            Button {
                                pendingPeripheral = peripheral
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(peripheral.displayName)
                                        if peripheral.name == model.expectedPeripheralName {
                                            Text("EXPECTED")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(.green.opacity(0.2), in: Capsule())
                                        }
                                    }
                                    Text(peripheral.id.uuidString)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Text("RSSI \(peripheral.rssi)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(model.isRunning || !model.canRun(peripheral))
                        }
                    }
                }
            }
            .navigationTitle("Sugarman Probe")
            .searchable(text: $model.searchText, prompt: "Name or iOS identifier")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await model.importMaterial(from: url) }
                } else if case .failure(let error) = result {
                    model.status = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Delete all imported probe secrets from this iPhone?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete private material", role: .destructive) {
                    Task { await model.deleteMaterial() }
                }
            }
            .confirmationDialog(
                "Run the one-shot handover probe?",
                isPresented: Binding(
                    get: { pendingPeripheral != nil },
                    set: { if !$0 { pendingPeripheral = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingPeripheral {
                    Button("Run once on \(pendingPeripheral.displayName)") {
                        let peripheral = pendingPeripheral
                        self.pendingPeripheral = nil
                        Task { await model.runProbe(peripheral: peripheral) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingPeripheral = nil
                }
            } message: {
                Text("First disconnect the official Android app and turn Android Bluetooth off. This writes exactly one authentication and, only after acceptance, one effective-data request. While that write acknowledgement is pending, it may quarantine one checksum-valid 24-byte unsupported command without interpreting it. It then disconnects after five unique live readings or the seven-minute timeout; any second or later unknown fails closed.")
            }
        }
    }
}
