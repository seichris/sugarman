// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Live", systemImage: "heart.text.clipboard")
                }
            OnboardingPlaceholderView()
                .tabItem {
                    Label("Onboarding", systemImage: "qrcode.viewfinder")
                }
            PrivacyView()
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
        }
    }
}
