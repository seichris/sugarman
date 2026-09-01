// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

#if !SUGARMAN_DEVICE_TEST
import GS3DeviceProvisioning
import SugarmanDomain
import SwiftUI

struct SensorConnectionSection: View {
    @Environment(AppModel.self) private var model
    @State private var selectedIdentityID: UUID?
    @State private var showScanConfirmation = false
    @State private var showConnectConfirmation = false
    @State private var showDeleteConfirmation = false

    let requestFileImport: (GS3DeviceProvisioningFileImportRequest) -> Void

    var body: some View {
        Section("Connect this sensor") {
            Text(
                "A package or NFC scan stores the sensor identity, but it does not contain "
                    + "the private values needed to read an already-active sensor. Import "
                    + "its private handover file, resolve this iPhone's Bluetooth identity, "
                    + "then connect."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if model.identities.isEmpty {
                Text("Store the owned sensor identity above first.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Stored sensor", selection: $selectedIdentityID) {
                    Text("Select a sensor").tag(nil as UUID?)
                    ForEach(model.identities) { identity in
                        Text(identityLabel(identity)).tag(identity.id as UUID?)
                    }
                }
                .disabled(model.hasSensorProvisioning || model.isSensorConnectionEnabled)
            }

            LabeledContent(
                "Private connection material",
                value: model.hasSensorProvisioning ? "Available" : "Missing"
            )

            if let linkedIdentity {
                LabeledContent("Linked sensor", value: identityLabel(linkedIdentity))
            }

            if !model.hasSensorProvisioning {
                Button("Import private handover file", systemImage: "lock.doc") {
                    guard let selectedIdentityID else { return }
                    requestFileImport(
                        GS3DeviceProvisioningFileImportRequest(
                            kind: .existingProbe,
                            linkedSensorID: selectedIdentityID
                        )
                    )
                }
                .accessibilityIdentifier("sensor-import-private-handover")
                .disabled(
                    selectedIdentityID == nil
                        || model.hasSensorProbeBridgePending
                        || model.isSensorProbeBridgeScanning
                )
            }

            if model.hasSensorProbeBridgePending {
                LabeledContent(
                    "Handover file",
                    value: model.isSensorProbeBridgeScanning
                        ? "Scanning only"
                        : "Ready in memory"
                )
                if model.isSensorProbeBridgeScanning {
                    ProgressView()
                    Button("Stop scan", role: .cancel) {
                        model.cancelSensorProbeBridgeScan()
                    }
                } else {
                    Button(
                        "Find this sensor on this iPhone",
                        systemImage: "dot.radiowaves.left.and.right"
                    ) {
                        showScanConfirmation = true
                    }
                    Button("Discard pending handover", role: .destructive) {
                        Task { await model.discardSensorProbeBridge() }
                    }
                }
            }

            if model.hasSensorProvisioning {
                if model.isSensorConnectionEnabled {
                    Button("Stop and disconnect", role: .cancel) {
                        Task { await model.stopSensorConnection() }
                    }
                } else {
                    Button(
                        "Connect to sensor",
                        systemImage: "antenna.radiowaves.left.and.right"
                    ) {
                        showConnectConfirmation = true
                    }
                    .disabled(model.isSyntheticDemo)
                }

                Button("Delete private connection material", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(model.isSensorConnectionEnabled)
            }

            Text(model.sensorConnectionStatus)
                .font(.footnote)

            Text(
                "For an already-active sensor, this handover file comes from "
                    + "owner-controlled activation/session evidence. It cannot be recreated "
                    + "from the box QR or activation number alone."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task {
            await model.refreshSensorProvisioningAvailability()
            reconcileSelectedIdentity()
        }
        .onChange(of: model.identities.map(\.id), initial: true) { _, _ in
            reconcileSelectedIdentity()
        }
        .onChange(of: model.provisionedSensorID, initial: true) { _, _ in
            reconcileSelectedIdentity()
        }
        .confirmationDialog(
            "Find this sensor?",
            isPresented: $showScanConfirmation,
            titleVisibility: .visible
        ) {
            Button("Scan only; do not connect") {
                model.confirmExclusiveSensorAccess()
                Task { await model.runSensorProbeBridgeScan() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "First release the sensor from the official Android app and stop other "
                    + "Sugarman targets. Sugarman will scan for ten seconds using the exact "
                    + "private name in the handover file. This cannot connect or write."
            )
        }
        .confirmationDialog(
            "Connect to this sensor?",
            isPresented: $showConnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Connect while foregrounded") {
                model.confirmExclusiveSensorAccess()
                Task { await model.connectSensor() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "First release the sensor from the official Android app and stop other "
                    + "Sugarman targets. While foregrounded, Sugarman may subscribe, send "
                    + "one typed authentication request and one typed history request, and "
                    + "use the bounded reconnect path. Unknown traffic fails closed."
            )
        }
        .confirmationDialog(
            "Delete private connection material from this iPhone?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete private material", role: .destructive) {
                Task { await model.deleteSensorProvisioning() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The redacted sensor identity and collected readings are retained.")
        }
    }

    private var linkedIdentity: SensorIdentity? {
        guard let provisionedSensorID = model.provisionedSensorID else { return nil }
        return model.identities.first { $0.id == provisionedSensorID }
    }

    private func reconcileSelectedIdentity() {
        selectedIdentityID = GS3DeviceProvisioningIdentitySelection.resolve(
            current: selectedIdentityID,
            linked: model.provisionedSensorID,
            available: model.identities.map(\.id)
        )
    }

    private func identityLabel(_ identity: SensorIdentity) -> String {
        let product = identity.productName ?? "Owned sensor"
        return "\(product) · \(identity.redactedSerial)"
    }
}
#endif
