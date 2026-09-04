// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

#if !SUGARMAN_DEVICE_TEST
import AppleHealthIntegration
import Foundation
import Observation
import SugarmanStore

@Observable
@MainActor
final class AppleHealthAppBridge {
    static let enabledDefaultsKey = "app.sugarman.appleHealthGlucoseSyncEnabled"

    private(set) var isEnabled: Bool
    private(set) var snapshot: AppleHealthSyncSnapshot
    private let coordinator: AppleHealthGlucoseSyncCoordinator
    @ObservationIgnored private let userDefaults: UserDefaults

    init(store: any SugarmanStoring, userDefaults: UserDefaults) {
        let policy = AppleHealthValidationPolicy.production
        self.userDefaults = userDefaults
        self.isEnabled = policy.isGateOpen
            && userDefaults.bool(forKey: Self.enabledDefaultsKey)
        self.coordinator = AppleHealthGlucoseSyncCoordinator(
            store: store,
            writer: SystemAppleHealthGlucoseWriter(policy: policy),
            policy: policy
        )
        self.snapshot = AppleHealthSyncSnapshot(
            phase: .gateClosed,
            authorization: .unavailable,
            summary: .empty
        )
    }

    var isEligibilityGateOpen: Bool {
        snapshot.phase != .gateClosed
    }

    func refresh() async {
        snapshot = await coordinator.snapshot(isEnabled: isEnabled)
    }

    func enable() async {
        guard await coordinator.isEligibilityGateOpen else {
            await refresh()
            return
        }
        isEnabled = true
        userDefaults.set(true, forKey: Self.enabledDefaultsKey)
        await coordinator.setEnabled(true)
        do {
            let authorization = try await coordinator.requestAuthorization()
            guard authorization == .authorized else {
                await refresh()
                return
            }
            await drain()
        } catch {
            await refresh()
        }
    }

    func disable() async {
        isEnabled = false
        userDefaults.set(false, forKey: Self.enabledDefaultsKey)
        await coordinator.setEnabled(false)
        await refresh()
    }

    func drain(forceRetry: Bool = false) async {
        if isEnabled, snapshot.authorization == .authorized {
            snapshot = AppleHealthSyncSnapshot(
                phase: .syncing,
                authorization: snapshot.authorization,
                summary: snapshot.summary
            )
        }
        snapshot = await coordinator.drain(
            isEnabled: isEnabled,
            forceRetry: forceRetry
        )
    }
}
#endif
