// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

#if canImport(CoreBluetooth)
import CoreBluetooth
import Observation

/// Observes radio power independently of the sensor session, including after
/// its retry budget is exhausted. Never scans, connects, or requests permission.
@Observable
@MainActor
public final class BluetoothPowerMonitor: NSObject, @preconcurrency CBCentralManagerDelegate {
    public private(set) var isPoweredOff = false
    public private(set) var shouldShowNotice = false
    private var dismissedForCurrentOutage = false
    @ObservationIgnored private var central: CBCentralManager?

    public override init() {
        super.init()
    }

    public func startIfAuthorized() {
        guard central == nil, CBCentralManager.authorization == .allowedAlways else { return }
        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    public func stop() {
        central?.delegate = nil
        central = nil
        isPoweredOff = false
        shouldShowNotice = false
        dismissedForCurrentOutage = false
    }

    public func dismissNotice() {
        guard isPoweredOff else { return }
        dismissedForCurrentOutage = true
        shouldShowNotice = false
    }

    // Kept separate from manager creation so state transitions can be tested
    // without accessing the host's Bluetooth hardware.
    package func update(_ state: CBManagerState) {
        isPoweredOff = state == .poweredOff
        if state == .poweredOn {
            dismissedForCurrentOutage = false
        }
        shouldShowNotice = isPoweredOff && !dismissedForCurrentOutage
    }

    // This manager explicitly delivers its delegate callbacks on .main.
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard self.central === central else { return }
        update(central.state)
    }
}
#endif
