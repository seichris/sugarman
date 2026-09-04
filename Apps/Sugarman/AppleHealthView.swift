// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

#if !SUGARMAN_DEVICE_TEST
import AppleHealthIntegration
import SwiftUI

struct AppleHealthView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEnable = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.red)
                        .frame(width: 42)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("privacy.apple_health")
                            .font(.headline)
                        Text("privacy.apple_health_body")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("apple_health.sync_section") {
                Toggle(
                    "privacy.apple_health_toggle",
                    isOn: Binding(
                        get: { model.appleHealth.isEnabled },
                        set: { enabled in
                            if enabled {
                                confirmEnable = true
                            } else {
                                Task { await model.appleHealth.disable() }
                            }
                        }
                    )
                )
                .disabled(!model.appleHealth.isEligibilityGateOpen)

                Label(statusKey, systemImage: statusSymbol)
                    .foregroundStyle(.secondary)

                if model.appleHealth.snapshot.summary.retryableFailureCount > 0 {
                    Button("privacy.apple_health_retry") {
                        Task { await model.appleHealth.drain(forceRetry: true) }
                    }
                }
            }

            Section("apple_health.history_section") {
                LabeledContent("apple_health.pending") {
                    Text(model.appleHealth.snapshot.summary.pendingCount, format: .number)
                }
                LabeledContent("apple_health.synced") {
                    Text(model.appleHealth.snapshot.summary.syncedCount, format: .number)
                }
                if model.appleHealth.snapshot.summary.blockedCount > 0 {
                    LabeledContent("apple_health.blocked") {
                        Text(model.appleHealth.snapshot.summary.blockedCount, format: .number)
                    }
                }
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
            }

            Section("apple_health.privacy_section") {
                Text("privacy.apple_health_no_delete")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("privacy.apple_health")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "privacy.apple_health_confirm_title",
            isPresented: $confirmEnable
        ) {
            Button("privacy.apple_health_confirm") {
                Task { await model.appleHealth.enable() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("privacy.apple_health_confirm_body")
        }
        .task {
            await model.appleHealth.refresh()
        }
    }

    private var statusKey: LocalizedStringKey {
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

    private var statusSymbol: String {
        switch model.appleHealth.snapshot.phase {
        case .idle:
            "checkmark.circle.fill"
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .authorizationRequired:
            "hand.raised.fill"
        case .failed, .gateClosed:
            "exclamationmark.triangle.fill"
        case .disabled:
            "heart"
        }
    }
}
#endif
