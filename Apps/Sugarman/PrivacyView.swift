// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section("privacy.retention") {
                    Text("privacy.retention_body")
                    Text("privacy.no_cloud")
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
        }
    }
}
