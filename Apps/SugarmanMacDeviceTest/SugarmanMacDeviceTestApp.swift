// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

@main
struct SugarmanMacDeviceTestApp: App {
    @State private var model = MacDeviceTestModel.bootstrapped()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Sugarman Mac Device Test") {
            MacDeviceTestView()
                .environment(model)
                .frame(minWidth: 680, minHeight: 620)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    Task { await model.handleScenePhase(phase) }
                }
        }
        .defaultSize(width: 760, height: 760)
    }
}
