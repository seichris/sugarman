// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Transport
import SwiftUI
import UIKit

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
        .background(OutsideTextFieldKeyboardDismissal())
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

/// Observes taps throughout this scene, including navigation bars and sheets,
/// without consuming the controls' own touches or interrupting text selection.
private struct OutsideTextFieldKeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ uiView: ObserverView, context: Context) {}

    static func dismantleUIView(_ uiView: ObserverView, coordinator: ()) {
        uiView.detach()
    }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        private weak var observedWindow: UIWindow?
        private lazy var tap: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            observedWindow = window
            window?.addGestureRecognizer(tap)
        }

        func detach() {
            observedWindow?.removeGestureRecognizer(tap)
            observedWindow = nil
        }

        @objc private func dismissKeyboard() {
            observedWindow?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
