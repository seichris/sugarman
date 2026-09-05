// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

#if canImport(CoreBluetooth)
import CoreBluetooth
import GS3Transport
import Testing

@Suite("Bluetooth power notice")
@MainActor
struct BluetoothPowerMonitorTests {
    @Test func onlyPoweredOffShowsNotice() {
        let monitor = BluetoothPowerMonitor()
        for state: CBManagerState in [.unknown, .resetting, .unsupported, .unauthorized, .poweredOn] {
            monitor.update(state)
            #expect(!monitor.isPoweredOff)
            #expect(!monitor.shouldShowNotice)
        }
        monitor.update(.poweredOff)
        #expect(monitor.isPoweredOff)
        #expect(monitor.shouldShowNotice)
    }

    @Test func dismissalLastsUntilBluetoothIsEnabledAgain() {
        let monitor = BluetoothPowerMonitor()
        monitor.update(.poweredOff)
        monitor.dismissNotice()
        monitor.update(.poweredOff)
        #expect(!monitor.shouldShowNotice)
        monitor.update(.resetting)
        monitor.update(.poweredOff)
        #expect(!monitor.shouldShowNotice)
        monitor.update(.poweredOn)
        #expect(!monitor.shouldShowNotice)
        monitor.update(.poweredOff)
        #expect(monitor.shouldShowNotice)
    }

    @Test func powerRestorationAndStoppingClearNotice() {
        let monitor = BluetoothPowerMonitor()
        monitor.update(.poweredOff)
        monitor.update(.poweredOn)
        #expect(!monitor.shouldShowNotice)
        monitor.update(.poweredOff)
        monitor.stop()
        #expect(!monitor.isPoweredOff)
        #expect(!monitor.shouldShowNotice)
    }
}
#endif
