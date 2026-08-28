// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import GS3Transport

struct GS3TransportTests {
    @Test func scanConnectDiscoverReadPath() {
        var machine = TransportStateMachine()
        #expect(machine.send(.startScan) == [.startScan])
        #expect(machine.state == .scanning)
        let id = UUID()
        _ = machine.send(.advertisement(peripheralID: id))
        #expect(machine.send(.connect(peripheralID: id)) == [.stopScan, .connect(id)])
        #expect(machine.send(.connected) == [.discoverServices])
        #expect(machine.send(.servicesDiscovered) == [.discoverCharacteristics])
        #expect(machine.send(.characteristicsDiscovered) == [.subscribe])
        #expect(machine.send(.subscribed).isEmpty)
        #expect(machine.state == .subscribed)
        let characteristic = DocumentedReadableCharacteristic.manufacturerName
        #expect(machine.beginAllowlistedRead(characteristic) == [.read(characteristic)])
    }

    @Test func oneInFlightCommand() {
        var machine = TransportStateMachine()
        _ = machine.send(.startScan)
        let second = machine.send(.startScan)
        #expect(second == [.fail(.commandInFlight)])
    }

    @Test func authenticationAndBindingAreRefused() {
        var machine = TransportStateMachine()
        #expect(machine.send(.requestAuthentication) == [.fail(.authenticationUnimplemented)])
        #expect(machine.send(.requestBinding) == [.fail(.bindingUnimplemented)])
        #expect(machine.state == .idle)
    }

    @Test func nonAllowlistedReadIsRefused() {
        var machine = TransportStateMachine()
        _ = machine.send(.startScan)
        let id = UUID()
        _ = machine.send(.connect(peripheralID: id))
        _ = machine.send(.connected)
        _ = machine.send(.servicesDiscovered)
        _ = machine.send(.characteristicsDiscovered)
        _ = machine.send(.subscribed)
        let effects = machine.beginAllowlistedRead(UUID())
        #expect(effects == [.fail(.mutatingOperationRefused)])
    }

    @Test func dedicatedQueueLabel() {
        let runtime = RecordingBluetoothRuntime()
        let session = GS3TransportSession(runtime: runtime)
        #expect(session.queue.label == "app.sugarman.ios.gs3.transport")
    }

    @Test func effectsHaveNoMutatingCharacteristicCase() {
        // Exhaustiveness: adding a mutating characteristic effect should fail this switch.
        let samples: [TransportEffect] = [
            .startScan, .stopScan, .connect(UUID()), .cancelConnection(UUID()),
            .discoverServices, .discoverCharacteristics, .subscribe,
            .read(UUID()), .waitBackoff, .fail(.timeout),
        ]
        for effect in samples {
            switch effect {
            case .startScan, .stopScan, .connect, .cancelConnection,
                 .discoverServices, .discoverCharacteristics, .subscribe,
                 .read, .waitBackoff, .fail:
                continue
            }
        }
    }
}
