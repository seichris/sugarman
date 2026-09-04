// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Transport
import SugarmanDiagnostics
import SugarmanDomain
import SugarmanStore
import SwiftUI

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    private let embeddedInNavigationStack: Bool
    @State private var confirmDeleteAll = false
    @State private var sessionPendingDelete: UUID?
    @State private var exportFileURL: URL?
    @State private var exportError: String?
    @State private var diagnosticSummary: LocalDiagnosticLogSummary?
    @State private var peripheralSearchText = ""
#if !SUGARMAN_DEVICE_TEST
    @State private var confirmAppleHealthEnable = false
#endif

    init(embeddedInNavigationStack: Bool = false) {
        self.embeddedInNavigationStack = embeddedInNavigationStack
    }

    @ViewBuilder
    var body: some View {
        if embeddedInNavigationStack {
            privacyContent
        } else {
            NavigationStack {
                privacyContent
            }
        }
    }

    private var privacyContent: some View {
        Group {
            Form {
                Section("privacy.retention") {
                    Text("privacy.retention_body")
                    Text("privacy.no_cloud")
                    Text(verbatim: ProductCopy.noDosing)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
                Section("privacy.export") {
                    Button("privacy.export_json") {
                        Task { await export(kind: .json) }
                    }
                    .accessibilityLabel(Text("privacy.export_json"))
                    .accessibilityHint(Text("privacy.export_file_hint"))
                    Button("privacy.export_csv") {
                        Task { await export(kind: .csv) }
                    }
                    .accessibilityLabel(Text("privacy.export_csv"))
                    .accessibilityHint(Text("privacy.export_file_hint"))
                    Text("privacy.export_body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let exportFileURL {
                        ShareLink(item: exportFileURL) {
                            Label(
                                exportFileURL.lastPathComponent,
                                systemImage: "square.and.arrow.up"
                            )
                        }
                        .accessibilityLabel(Text("privacy.share_file"))
                        .accessibilityHint(Text("privacy.share_file_hint"))
                        Text("privacy.export_file_ready")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    if let exportError {
                        Text(exportError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
#if !SUGARMAN_DEVICE_TEST
                Section("privacy.apple_health") {
                    Toggle(
                        "privacy.apple_health_toggle",
                        isOn: Binding(
                            get: { model.appleHealth.isEnabled },
                            set: { enabled in
                                if enabled {
                                    confirmAppleHealthEnable = true
                                } else {
                                    Task { await model.appleHealth.disable() }
                                }
                            }
                        )
                    )
                    .disabled(!model.appleHealth.isEligibilityGateOpen)
                    Text(appleHealthStatusKey)
                        .foregroundStyle(.secondary)
                    Text(
                        String(
                            format: String(localized: "privacy.apple_health_counts"),
                            locale: .current,
                            Int64(model.appleHealth.snapshot.summary.pendingCount),
                            Int64(model.appleHealth.snapshot.summary.syncedCount)
                        )
                    )
                    .font(.footnote)
                    if let lastAttempt = model.appleHealth.snapshot.summary.lastAttemptAt {
                        LabeledContent("privacy.apple_health_last_attempt") {
                            Text(lastAttempt, format: .dateTime)
                        }
                    }
                    if let lastSync = model.appleHealth.snapshot.summary.lastSyncedAt {
                        LabeledContent("privacy.apple_health_last_sync") {
                            Text(lastSync, format: .dateTime)
                        }
                    }
                    if model.appleHealth.snapshot.summary.retryableFailureCount > 0 {
                        Button("privacy.apple_health_retry") {
                            Task { await model.appleHealth.drain(forceRetry: true) }
                        }
                    }
                    Text("privacy.apple_health_no_delete")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
#endif
                Section("privacy.local_diagnostics") {
                    Text("privacy.local_diagnostics_body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let diagnosticSummary {
                        if diagnosticSummary.entryCount == 0 {
                            Text("privacy.local_diagnostics_empty")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(
                                String(
                                    format: String(localized: "privacy.local_diagnostics_summary"),
                                    locale: .current,
                                    Int64(diagnosticSummary.entryCount),
                                    Int64(diagnosticSummary.byteCount)
                                )
                            )
                            .font(.footnote)
                        }
                        if diagnosticSummary.invalidLineCount > 0 {
                            Text("privacy.local_diagnostics_invalid")
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                    Button("privacy.export_diagnostics") {
                        Task { await export(kind: .diagnostics) }
                    }
                    .accessibilityLabel(Text("privacy.export_diagnostics"))
                    .accessibilityHint(Text("privacy.export_diagnostics_hint"))
                    if let diagnosticLogError = model.diagnosticLogError {
                        Text(diagnosticLogError)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                Section("privacy.sessions") {
                    if model.sessions.isEmpty {
                        Text("privacy.no_sessions")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.sessions) { session in
                            Button(role: .destructive) {
                                sessionPendingDelete = session.id
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("privacy.delete_session")
                                    Text(session.id.uuidString)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    if model.activeSessionID == session.id {
                                        Text("session.active_badge")
                                            .font(.footnote.weight(.semibold))
                                    }
                                }
                            }
                            .accessibilityLabel(Text("privacy.delete_session"))
                        }
                    }
                }
                Section("privacy.diagnostics") {
                    Toggle(
                        "privacy.probe_toggle",
                        isOn: Binding(
                            get: { model.probeSession.isEnabled },
                            set: { enabled in
                                model.recordProbeAction(enabled ? "enabled" : "disabled")
                                Task { await model.probeSession.setEnabled(enabled) }
                            }
                        )
                    )
                    .disabled(!model.probeSession.canEnable)
                    Text(model.probeSession.canEnable ? "privacy.probe_device_help" : "privacy.probe_simulator")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("privacy.probe_no_writes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if model.probeSession.isEnabled {
                        Button("privacy.probe_scan") {
                            model.recordProbeAction("scan_started")
                            Task { await model.probeSession.startScan() }
                        }
                        .disabled(model.probeSession.selectedPeripheralID != nil)
                        .accessibilityHint(Text("privacy.probe_scan_hint"))
                        if model.probeSession.selectedPeripheralID != nil {
                            Button("privacy.probe_disconnect") {
                                model.recordProbeAction("disconnect_requested")
                                Task { await model.probeSession.disconnect() }
                            }
                        }
                        Text(model.probeSession.status)
                            .font(.footnote)
                        if model.probeSession.peripherals.isEmpty {
                            Text("privacy.probe_empty")
                                .foregroundStyle(.secondary)
                        } else {
                            TextField("privacy.probe_search", text: $peripheralSearchText)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .accessibilityHint(Text("privacy.probe_search_hint"))
                            if visiblePeripherals.isEmpty {
                                Text("privacy.probe_no_matches")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(visiblePeripherals, id: \.peripheralID) { item in
                                Button {
                                    model.recordProbeAction("peripheral_selected")
                                    Task { await model.probeSession.connectAndRead(item.peripheralID) }
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(item.name ?? String(localized: "privacy.probe_unnamed"))
                                        if PeripheralDiscoveryList.hasObservedGS3NameFormat(item.name) {
                                            Label(
                                                "privacy.probe_likely_gs3",
                                                systemImage: "sensor.tag.radiowaves.forward"
                                            )
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        }
                                        Text(item.peripheralID.uuidString)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        if let rssi = item.rssi {
                                            Text(
                                                String(
                                                    format: String(localized: "privacy.probe_rssi_format"),
                                                    locale: .current,
                                                    rssi
                                                )
                                            )
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityHint(Text("privacy.probe_connect_hint"))
                                .disabled(model.probeSession.selectedPeripheralID != nil)
                            }
                        }
                        if let dis = model.probeSession.deviceInformation {
                            LabeledContent("privacy.probe_manufacturer", value: dis.manufacturerName ?? "—")
                            LabeledContent("privacy.probe_model", value: dis.modelNumber ?? "—")
                            LabeledContent("privacy.probe_hardware", value: dis.hardwareRevision ?? "—")
                            LabeledContent("privacy.probe_firmware", value: dis.firmwareRevision ?? "—")
                            LabeledContent("privacy.probe_software", value: dis.softwareRevision ?? "—")
                        }
                        if let gattMapFileURL = model.probeSession.gattMapFileURL {
                            ShareLink(item: gattMapFileURL) {
                                Label("privacy.probe_share_gatt", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityHint(Text("privacy.probe_share_gatt_hint"))
                            Text("privacy.probe_gatt_body")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("privacy.deletion") {
                    Button("privacy.delete_all", role: .destructive) {
                        confirmDeleteAll = true
                    }
                }
                if let storeErrorMessage = model.storeErrorMessage {
                    Section("privacy.local_storage") {
                        Text(storeErrorMessage).foregroundStyle(.red)
                    }
                }
                Section("privacy.licence") {
                    Text("privacy.gpl")
                }
            }
            .navigationTitle("privacy.title")
            .confirmationDialog("privacy.delete_confirm_title", isPresented: $confirmDeleteAll) {
                Button("privacy.delete_all", role: .destructive) {
                    Task {
                        do {
                            try await model.deleteAllLocalData()
                            diagnosticSummary = model.diagnosticLogSummary()
                        } catch {
                            model.storeErrorMessage = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("privacy.delete_confirm_body")
            }
#if !SUGARMAN_DEVICE_TEST
            .confirmationDialog(
                "privacy.apple_health_confirm_title",
                isPresented: $confirmAppleHealthEnable
            ) {
                Button("privacy.apple_health_confirm") {
                    Task { await model.appleHealth.enable() }
                }
                Button("common.cancel", role: .cancel) {}
            } message: {
                Text("privacy.apple_health_confirm_body")
            }
#endif
            .confirmationDialog(
                "privacy.delete_session_title",
                isPresented: Binding(
                    get: { sessionPendingDelete != nil },
                    set: { if !$0 { sessionPendingDelete = nil } }
                )
            ) {
                Button("privacy.delete_session", role: .destructive) {
                    if let id = sessionPendingDelete {
                        Task {
                            do {
                                try await model.deleteSession(id)
                            } catch {
                                model.storeErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    sessionPendingDelete = nil
                }
            } message: {
                Text("privacy.delete_session_body")
            }
            .task {
                diagnosticSummary = model.diagnosticLogSummary()
#if !SUGARMAN_DEVICE_TEST
                await model.appleHealth.refresh()
#endif
            }
        }
    }

    private var visiblePeripherals: [AdvertisementSnapshot] {
        PeripheralDiscoveryList.results(
            from: model.probeSession.peripherals,
            searchText: peripheralSearchText
        )
    }

#if !SUGARMAN_DEVICE_TEST
    private var appleHealthStatusKey: LocalizedStringKey {
        let snapshot = model.appleHealth.snapshot
        return switch snapshot.phase {
        case .gateClosed:
            "privacy.apple_health_gate_closed"
        case .failed:
            "privacy.apple_health_failed"
        case .authorizationRequired where snapshot.authorization == .denied:
            "privacy.apple_health_denied"
        case .authorizationRequired:
            "privacy.apple_health_authorization_required"
        case .idle where snapshot.summary.pendingCount > 0:
            "privacy.apple_health_pending"
        case .idle:
            "privacy.apple_health_caught_up"
        case .disabled:
            "privacy.apple_health_body"
        case .syncing:
            "privacy.apple_health_syncing"
        }
    }
#endif

    private enum ExportKind {
        case json
        case csv
        case diagnostics
    }

    private func export(kind: ExportKind) async {
        exportError = nil
        do {
            let writer = model.exportFileWriter
            let directory = FileManager.default.temporaryDirectory
            switch kind {
            case .json:
                let data = try await model.exportJSON()
                exportFileURL = try writer.writeJSON(data, to: directory)
            case .csv:
                let text = try await model.exportCSV()
                exportFileURL = try writer.writeCSV(text, to: directory)
            case .diagnostics:
                let data = try model.exportDiagnosticLogs()
                exportFileURL = try writer.writeDiagnostics(data, to: directory)
            }
            diagnosticSummary = model.diagnosticLogSummary()
        } catch {
            exportError = error.localizedDescription
            exportFileURL = nil
        }
    }
}
