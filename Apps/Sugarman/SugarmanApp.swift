// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AccountBinding
import GS3Transport
import Observation
import SafetyEngine
import SugarmanDiagnostics
import SugarmanDomain
import SugarmanStore
import SwiftUI

@main
struct SugarmanApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

@Observable
@MainActor
final class AppModel {
    var store: InMemorySugarmanStore
    var safety: SafetyEngine
    var connection: ConnectionState
    var lifecycle: SensorLifecycleState
    var latestSample: GlucoseSample?
    var preferredUnit: GlucoseUnit
    var probeEnabled: Bool

    init(
        store: InMemorySugarmanStore = InMemorySugarmanStore(),
        safety: SafetyEngine = SafetyEngine(),
        connection: ConnectionState = .disconnected,
        lifecycle: SensorLifecycleState = .unknown,
        latestSample: GlucoseSample? = nil,
        preferredUnit: GlucoseUnit = .milligramsPerDeciliter,
        probeEnabled: Bool = false
    ) {
        self.store = store
        self.safety = safety
        self.connection = connection
        self.lifecycle = lifecycle
        self.latestSample = latestSample
        self.preferredUnit = preferredUnit
        self.probeEnabled = probeEnabled
    }

    var assessment: SafetyAssessment {
        safety.evaluate(
            now: Date(),
            connection: connection,
            lifecycle: lifecycle,
            latestSample: latestSample
        )
    }

    func deleteAllLocalData() async {
        try? await store.deleteAll()
        latestSample = nil
        lifecycle = .unknown
        connection = .disconnected
    }
}
