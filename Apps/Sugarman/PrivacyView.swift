// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteAll = false
    @State private var sessionPendingDelete: UUID?
    @State private var exportFileURL: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
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
                            Task { await model.probeSession.startScan() }
                        }
                        .accessibilityHint(Text("privacy.probe_scan_hint"))
                        Text(model.probeSession.status)
                            .font(.footnote)
                        if model.probeSession.peripherals.isEmpty {
                            Text("privacy.probe_empty")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.probeSession.peripherals, id: \.peripheralID) { item in
                                Button {
                                    Task { await model.probeSession.connectAndRead(item.peripheralID) }
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(item.name ?? String(localized: "privacy.probe_unnamed"))
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
                Section("privacy.licence") {
                    Text("privacy.gpl")
                }
            }
            .navigationTitle("privacy.title")
            .confirmationDialog("privacy.delete_confirm_title", isPresented: $confirmDeleteAll) {
                Button("privacy.delete_all", role: .destructive) {
                    Task { await model.deleteAllLocalData() }
                }
            } message: {
                Text("privacy.delete_confirm_body")
            }
            .confirmationDialog(
                "privacy.delete_session_title",
                isPresented: Binding(
                    get: { sessionPendingDelete != nil },
                    set: { if !$0 { sessionPendingDelete = nil } }
                )
            ) {
                Button("privacy.delete_session", role: .destructive) {
                    if let id = sessionPendingDelete {
                        Task { await model.deleteSession(id) }
                    }
                    sessionPendingDelete = nil
                }
            } message: {
                Text("privacy.delete_session_body")
            }
        }
    }

    private enum ExportKind {
        case json
        case csv
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
            }
        } catch {
            exportError = error.localizedDescription
            exportFileURL = nil
        }
    }
}
