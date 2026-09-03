// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Live", systemImage: "heart.text.clipboard")
                }
            WorkoutView()
                .tabItem {
                    Label("Workout", systemImage: "figure.run")
                }
            FuelingView()
                .tabItem {
                    Label("Fueling", systemImage: "fork.knife")
                }
            SensorOnboardingView()
                .tabItem {
                    Label("Sensor", systemImage: "sensor.tag.radiowaves.forward")
                }
            MoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
        }
        .task {
            await model.refresh()
        }
    }
}
