// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

struct MoreView: View {
#if !SUGARMAN_DEVICE_TEST
    @Environment(AppModel.self) private var model
#endif

    var body: some View {
        NavigationStack {
            List {
#if !SUGARMAN_DEVICE_TEST
                NavigationLink {
                    AppleHealthView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("privacy.apple_health")
                                .font(.headline)
                            Text(appleHealthSubtitleKey)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
#endif

                NavigationLink {
                    HistoryView(embeddedInNavigationStack: true)
                } label: {
                    Label("history.title", systemImage: "chart.xyaxis.line")
                }

                NavigationLink {
                    PrivacyView(embeddedInNavigationStack: true)
                } label: {
                    Label("privacy.title", systemImage: "lock.shield")
                }
            }
            .navigationTitle("More")
        }
    }

#if !SUGARMAN_DEVICE_TEST
    private var appleHealthSubtitleKey: LocalizedStringKey {
        model.appleHealth.isEnabled
            ? "apple_health.more_enabled"
            : "apple_health.more_subtitle"
    }
#endif
}
