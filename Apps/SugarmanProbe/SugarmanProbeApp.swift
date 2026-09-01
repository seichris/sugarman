// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import SwiftUI

@main
struct SugarmanProbeApp: App {
    @State private var model = ProbeAppModel()

    var body: some Scene {
        WindowGroup {
            ProbeView()
                .environment(model)
        }
    }
}
