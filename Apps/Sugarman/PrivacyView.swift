// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SugarmanDomain
import SwiftUI

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteAll = false
    @State private var sessionPendingDelete: UUID?
    @State private var exportText = ""
    @State private var exportTitle = ""
    @State private var showExport = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("privacy.retention") {
                    Text("privacy.retention_body")
                    Text("privacy.no_cloud")
                    Text(verbatim: ProductCopy.noDosing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("privacy.export") {
                    Button("privacy.export_json") {
                        Task { await export(kind: .json) }
                    }
                    Button("privacy.export_csv") {
                        Task { await export(kind: .csv) }
                    }
                    Text("privacy.export_body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                                }
                            }
                            .accessibilityLabel(Text("privacy.delete_session"))
                        }
                    }
                }
                Section("privacy.diagnostics") {
                    Toggle("privacy.probe_toggle", isOn: Bindable(model).probeEnabled)
                        .disabled(true)
                    Text("privacy.probe_disabled")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .sheet(isPresented: $showExport) {
                NavigationStack {
                    ScrollView {
                        Text(exportText)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .padding()
                    }
                    .navigationTitle(Text(exportTitle))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            ShareLink(item: exportText) {
                                Label("privacy.share", systemImage: "square.and.arrow.up")
                            }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Button("privacy.done") { showExport = false }
                        }
                    }
                }
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
            switch kind {
            case .json:
                let data = try await model.exportJSON()
                exportText = String(decoding: data, as: UTF8.self)
                exportTitle = String(localized: "privacy.export_json")
            case .csv:
                exportText = try await model.exportCSV()
                exportTitle = String(localized: "privacy.export_csv")
            }
            showExport = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}
