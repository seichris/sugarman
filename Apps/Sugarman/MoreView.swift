// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
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
}
