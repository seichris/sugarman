// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI
import UniformTypeIdentifiers

struct MacDeviceTestView: View {
    @Environment(MacDeviceTestModel.self) private var model
    @State private var showFileImporter = false
    @State private var showScanConfirmation = false
    @State private var showArmConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Mac device-test foundation") {
                Text(
                    "This isolated target reuses the production typed foreground lifecycle. "
                        + "It creates no raw-write surface and cannot replace final iPhone acceptance."
                )
                .foregroundStyle(.secondary)

                LabeledContent(
                    "Mac-local Keychain",
                    value: model.hasProvisioning ? "Available" : "Missing"
                )
                LabeledContent(
                    "External-owner confirmation",
                    value: model.isArmed ? "Confirmed for this run" : "Required per action"
                )
                Text(model.status)
                    .font(.callout)
            }

            Section("Provision this Mac") {
                Text(
                    "CoreBluetooth identifiers are local to each host. Import the existing "
                        + "Probe JSON, then explicitly authorize one bounded exact-name scan "
                        + "to resolve this Mac's identifier."
                )
                .foregroundStyle(.secondary)

                if !model.hasProvisioning && !model.hasPendingProbeBridge {
                    Button("Import existing Probe JSON", systemImage: "lock.doc") {
                        showFileImporter = true
                    }
                    .disabled(model.isScanning || model.isArmed)
                }

                if model.hasPendingProbeBridge {
                    LabeledContent(
                        "Probe material",
                        value: model.isScanning ? "Scanning only" : "Validated in memory"
                    )
                    if model.isScanning {
                        ProgressView()
                        Button("Stop scan", role: .cancel) {
                            model.cancelProbeBridgeScan()
                        }
                    } else {
                        Button(
                            "Confirm exclusive access and scan",
                            systemImage: "dot.radiowaves.left.and.right"
                        ) {
                            showScanConfirmation = true
                        }
                        Button("Discard pending material", role: .destructive) {
                            Task { await model.discardPendingProbeBridge() }
                        }
                    }
                }
            }

            Section("Managed foreground test") {
                if model.hasProvisioning {
                    if model.isArmed {
                        Button("Stop and disconnect", role: .cancel) {
                            Task { await model.stop() }
                        }
                        Button(
                            "Inject one link loss",
                            systemImage: "bolt.horizontal.circle"
                        ) {
                            Task { await model.injectLinkLoss() }
                        }
                        .disabled(
                            model.deviceTestPhase != .live
                                || model.isLinkLossInjectionPending
                        )
                    } else {
                        Button(
                            "Confirm exclusive access and arm",
                            systemImage: "antenna.radiowaves.left.and.right"
                        ) {
                            showArmConfirmation = true
                        }
                        .disabled(model.isScanning || !model.isSceneActive)
                    }

                    Button("Delete Mac-local private material", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(model.isArmed || model.isScanning)
                }
            }

            Section("Private on-Mac reading comparison") {
                Text(
                    "These recent values and timestamps stay in this app view. They are "
                        + "never included in the redacted diagnostics or Share action."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if model.privateRecentReadings.isEmpty {
                    Text("No locally stored readings yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.privateRecentReadings) { sample in
                        LabeledContent {
                            Text("\(sample.milligramsPerDeciliter) mg/dL")
                                .monospacedDigit()
                        } label: {
                            Text(
                                sample.sensorTimestamp.formatted(
                                    date: .abbreviated,
                                    time: .standard
                                )
                            )
                        }
                    }
                }
            }

            Section("Payload-free diagnostics") {
                Text(
                    "Sensor identifiers, record indexes, packet bodies, command bytes, "
                        + "private material, glucose values, and imported JSON contents or hashes are omitted."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollView {
                    Text(model.redactedReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180)

                ShareLink(
                    item: model.redactedReport,
                    subject: Text("Sugarman macOS device-test diagnostics")
                ) {
                    Label("Share redacted report", systemImage: "square.and.arrow.up")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await model.prepare() }
        .onDisappear {
            Task { await model.shutdown() }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                Task { await model.prepareProbeBridge(from: url) }
            case .failure:
                model.fileImportFailed()
            }
        }
        .confirmationDialog(
            "Run one scan-only Mac provisioning lookup?",
            isPresented: $showScanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirm release and scan only") {
                Task { await model.confirmAndRunProbeBridgeScan() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Release the sensor from every phone and stop other Sugarman processes. "
                    + "This scans for ten seconds and cannot connect, discover GATT, subscribe, "
                    + "authenticate, request history, or write."
            )
        }
        .confirmationDialog(
            "Arm the managed foreground Mac test?",
            isPresented: $showArmConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirm release, arm, and connect") {
                Task { await model.confirmAndArm() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Release the owned sensor from every phone and stop other Sugarman processes. "
                    + "Each connection can send only the typed authentication and effective-data "
                    + "requests. Unknown or malformed input fails closed."
            )
        }
        .confirmationDialog(
            "Delete private provisioning from this Mac?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete private material", role: .destructive) {
                Task { await model.deleteProvisioning() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Previously collected local session data is retained.")
        }
    }
}
