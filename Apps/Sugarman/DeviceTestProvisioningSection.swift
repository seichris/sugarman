// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

#if SUGARMAN_DEVICE_TEST
import SugarmanDomain
import SwiftUI
import UniformTypeIdentifiers

struct DeviceTestProvisioningSection: View {
    @Environment(AppModel.self) private var model
    @State private var selectedIdentityID: UUID?
    @State private var showImporter = false
    @State private var showArmConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Section("Managed foreground device test") {
            Text(
                "Developer-only boundary for one owned, already-active V3 sensor. "
                    + "Importing material does not start Bluetooth. A separate explicit "
                    + "arm confirmation is required for every app process."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            if model.identities.isEmpty {
                Text("Store a redacted owned-sensor identity above before importing material.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Linked stored identity", selection: $selectedIdentityID) {
                    Text("Select an identity").tag(nil as UUID?)
                    ForEach(model.identities) { identity in
                        Text(identityLabel(identity)).tag(identity.id as UUID?)
                    }
                }
                .disabled(model.hasDeviceTestProvisioning || model.isDeviceTestArmed)
            }

            LabeledContent(
                "This-device-only Keychain",
                value: model.hasDeviceTestProvisioning ? "Available" : "Missing"
            )

            if let linked = linkedIdentity {
                LabeledContent("Linked sensor", value: identityLabel(linked))
            }

            Button("Import private provisioning JSON", systemImage: "lock.doc") {
                showImporter = true
            }
            .disabled(
                selectedIdentityID == nil
                    || model.hasDeviceTestProvisioning
                    || model.isDeviceTestArmed
            )

            if model.hasDeviceTestProvisioning {
                if model.isDeviceTestArmed {
                    Button("Stop and disconnect", role: .cancel) {
                        Task { await model.stopDeviceTest() }
                    }
                } else {
                    Button("Arm managed foreground test", systemImage: "antenna.radiowaves.left.and.right") {
                        showArmConfirmation = true
                    }
                    .disabled(model.isSyntheticDemo)
                }

                Button("Delete private provisioning material", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(model.isDeviceTestArmed)
            }

            Text(model.deviceTestStatus)
                .font(.footnote)

            if !model.deviceTestLifecycleLines.isEmpty {
                Text(
                    "Payload-free lifecycle only. Sensor identifiers, record indexes, "
                        + "packet bodies, private material, and glucose values are omitted."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(
                    Array(model.deviceTestLifecycleLines.enumerated()),
                    id: \.offset
                ) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                ShareLink(
                    item: model.redactedDeviceTestReport,
                    subject: Text("Sugarman managed foreground device-test diagnostics")
                ) {
                    Label("Share redacted lifecycle report", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task {
            await model.refreshDeviceTestProvisioningAvailability()
            if selectedIdentityID == nil {
                selectedIdentityID = model.deviceTestLinkedSensorID
                    ?? model.identities.first?.id
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first, let selectedIdentityID else { return }
                Task {
                    await model.importDeviceTestProvisioning(
                        from: url,
                        linkedSensorID: selectedIdentityID
                    )
                }
            case .failure:
                model.deviceTestStatus = "Private provisioning file selection failed closed."
            }
        }
        .confirmationDialog(
            "Arm the managed foreground GS3 test?",
            isPresented: $showArmConfirmation,
            titleVisibility: .visible
        ) {
            Button("Arm and connect while foregrounded") {
                Task { await model.armDeviceTest() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "First release the owned sensor from the official Android app and ensure "
                    + "other Sugarman targets are stopped. Each physical connection may "
                    + "subscribe, send exactly one typed authentication request and one "
                    + "typed effective-data request, then use bounded single-flight "
                    + "foreground reconnect. Unknown or malformed commands fail closed."
            )
        }
        .confirmationDialog(
            "Delete private provisioning material from this iPhone?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete private material", role: .destructive) {
                Task { await model.deleteDeviceTestProvisioning() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Local redacted identities and previously collected samples are retained.")
        }
    }

    private var linkedIdentity: SensorIdentity? {
        guard let linked = model.deviceTestLinkedSensorID else { return nil }
        return model.identities.first { $0.id == linked }
    }

    private func identityLabel(_ identity: SensorIdentity) -> String {
        let product = identity.productName ?? "Owned sensor"
        return "\(product) · \(identity.redactedSerial)"
    }
}
#endif
