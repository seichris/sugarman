// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Transport
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
#if !SUGARMAN_DEVICE_TEST
    @Environment(\.scenePhase) private var scenePhase
    @State private var bluetoothPower = BluetoothPowerMonitor()
#endif

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
#if !SUGARMAN_DEVICE_TEST
        .onChange(of: shouldMonitorBluetooth, initial: true) { _, _ in
            updateBluetoothMonitoring()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { updateBluetoothMonitoring() }
        }
        .onChange(of: model.isSensorConnectionEnabled) { _, _ in
            updateBluetoothMonitoring()
        }
        .sheet(isPresented: Binding(
            get: {
                shouldMonitorBluetooth && scenePhase == .active
                    && bluetoothPower.shouldShowNotice
            },
            set: { presented in
                if !presented, scenePhase == .active, shouldMonitorBluetooth {
                    bluetoothPower.dismissNotice()
                }
            }
        )) {
            BluetoothOffNotice()
        }
#endif
    }
#if !SUGARMAN_DEVICE_TEST
    private var shouldMonitorBluetooth: Bool {
        model.hasSensorProvisioning && !model.isSyntheticDemo
    }

    private func updateBluetoothMonitoring() {
        if shouldMonitorBluetooth {
            bluetoothPower.startIfAuthorized()
        } else {
            bluetoothPower.stop()
        }
    }
#endif
}
