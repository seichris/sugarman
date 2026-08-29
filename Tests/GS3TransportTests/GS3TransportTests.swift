// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import GS3Transport
#if canImport(CoreBluetooth)
import CoreBluetooth
#endif

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

    @Test func recordingRuntimeHappyPathIdleToSubscribed() async throws {
        let runtime = RecordingBluetoothRuntime()
        let session = GS3TransportSession(runtime: runtime)
        try await session.handle(.startScan)
        #expect(session.state == .scanning)
        let id = UUID()
        try await session.handle(.advertisement(peripheralID: id))
        try await session.handle(.connect(peripheralID: id))
        #expect(session.state == .connecting)
        try await session.handle(.connected)
        #expect(session.state == .discovering)
        try await session.handle(.servicesDiscovered)
        try await session.handle(.characteristicsDiscovered)
        #expect(session.state == .subscribed)
        try await session.handle(.subscribed)
        #expect(session.state == .subscribed)
        #expect(runtime.log.effects == [
            .startScan,
            .stopScan,
            .connect(id),
            .discoverServices,
            .discoverCharacteristics,
            .subscribe,
        ])
        #expect(session.state != .authenticating)
        #expect(session.state != .binding)
        #expect(session.state != .live)
    }

    @Test func oneInFlightCommand() {
        var machine = TransportStateMachine()
        _ = machine.send(.startScan)
        let second = machine.send(.startScan)
        #expect(second == [.fail(.commandInFlight)])
    }

    @Test func oneInFlightCommandOnSession() async throws {
        let runtime = RecordingBluetoothRuntime()
        let session = GS3TransportSession(runtime: runtime)
        try await session.handle(.startScan)
        await #expect(throws: TransportError.commandInFlight) {
            try await session.handle(.startScan)
        }
        #expect(session.state == .scanning)
    }

    @Test func authenticationAndBindingAreRefused() {
        var machine = TransportStateMachine()
        #expect(machine.send(.requestAuthentication) == [.fail(.authenticationUnimplemented)])
        #expect(machine.send(.requestBinding) == [.fail(.bindingUnimplemented)])
        #expect(machine.state == .idle)
    }

    @Test func requestAuthenticationAndBindingStayFailClosedOnSession() async throws {
        let runtime = RecordingBluetoothRuntime()
        let session = GS3TransportSession(runtime: runtime)
        try await session.handle(.startScan)
        let id = UUID()
        try await session.handle(.connect(peripheralID: id))
        try await session.handle(.connected)
        try await session.handle(.servicesDiscovered)
        try await session.handle(.characteristicsDiscovered)
        try await session.handle(.subscribed)
        await #expect(throws: TransportError.authenticationUnimplemented) {
            try await session.handle(.requestAuthentication)
        }
        await #expect(throws: TransportError.bindingUnimplemented) {
            try await session.handle(.requestBinding)
        }
        #expect(session.state == .subscribed)
        #expect(session.state != .authenticating)
        #expect(session.state != .binding)
        #expect(session.state != .live)
        let failed = runtime.log.effects.contains { effect in
            if case .fail(.authenticationUnimplemented) = effect { return true }
            if case .fail(.bindingUnimplemented) = effect { return true }
            return false
        }
        #expect(failed)
    }

    @Test func timeoutEntersBackoff() async throws {
        let runtime = RecordingBluetoothRuntime()
        let session = GS3TransportSession(runtime: runtime)
        try await session.handle(.startScan)
        try await session.handle(.timeout)
        #expect(session.state == .backoff)
        #expect(runtime.log.effects.contains(.stopScan))
        #expect(runtime.log.effects.contains(.waitBackoff))
        try await session.handle(.startScan)
        #expect(session.state == .scanning)
    }

    @Test func permissionDeniedIsDistinctFromBluetoothUnavailable() {
        #expect(TransportError.permissionDenied != TransportError.bluetoothUnavailable)
        #expect(TransportError.permissionDenied.description != TransportError.bluetoothUnavailable.description)
        #expect(TransportError.permissionDenied.description == "Bluetooth permission was denied.")
        #expect(TransportError.bluetoothUnavailable.description == "Bluetooth is unavailable.")
    }

    @Test func permissionAndBluetoothUnavailableEndSession() async throws {
        let unavailableRuntime = RecordingBluetoothRuntime()
        let unavailable = GS3TransportSession(runtime: unavailableRuntime)
        try await unavailable.handle(.startScan)
        await #expect(throws: TransportError.bluetoothUnavailable) {
            try await unavailable.handle(.bluetoothUnavailable)
        }
        #expect(unavailable.state == .ended)

        let permissionRuntime = RecordingBluetoothRuntime()
        let permission = GS3TransportSession(runtime: permissionRuntime)
        await #expect(throws: TransportError.permissionDenied) {
            try await permission.handle(.permissionDenied)
        }
        #expect(permission.state == .ended)
        #expect(permissionRuntime.log.effects.contains(.stopScan))
        #expect(permissionRuntime.log.effects.contains(.fail(.permissionDenied)))
        #expect(!permissionRuntime.log.effects.contains(.fail(.bluetoothUnavailable)))
    }

    @Test func cancelStopsScanAndConnection() async throws {
        let runtime = RecordingBluetoothRuntime()
        let session = GS3TransportSession(runtime: runtime)
        try await session.handle(.startScan)
        let id = UUID()
        try await session.handle(.connect(peripheralID: id))
        try await session.handle(.cancel)
        #expect(session.state == .ended)
        #expect(runtime.log.effects.contains(.stopScan))
        #expect(runtime.log.effects.contains(.cancelConnection(id)))
    }

    /// Simulated restoration: the machine is constructed already in a boundary
    /// state as if CoreBluetooth restored the central there. This is not a live
    /// `willRestoreState` implementation.
    @Test func simulatedRestorationAtScanningConnectingDiscoveringSubscribed() async throws {
        let id = UUID()

        let scanningRuntime = RecordingBluetoothRuntime()
        let scanning = GS3TransportSession(
            runtime: scanningRuntime,
            machine: TransportStateMachine(state: .scanning, inFlight: true)
        )
        try await scanning.handle(.advertisement(peripheralID: id))
        try await scanning.handle(.connect(peripheralID: id))
        #expect(scanning.state == .connecting)

        let connectingRuntime = RecordingBluetoothRuntime()
        let connecting = GS3TransportSession(
            runtime: connectingRuntime,
            machine: TransportStateMachine(state: .connecting, inFlight: true, peripheralID: id)
        )
        try await connecting.handle(.connected)
        #expect(connecting.state == .discovering)
        #expect(connectingRuntime.log.effects == [.discoverServices])

        let discoveringRuntime = RecordingBluetoothRuntime()
        let discovering = GS3TransportSession(
            runtime: discoveringRuntime,
            machine: TransportStateMachine(state: .discovering, inFlight: true, peripheralID: id)
        )
        try await discovering.handle(.servicesDiscovered)
        try await discovering.handle(.characteristicsDiscovered)
        #expect(discovering.state == .subscribed)

        let subscribedRuntime = RecordingBluetoothRuntime()
        let subscribed = GS3TransportSession(
            runtime: subscribedRuntime,
            machine: TransportStateMachine(state: .subscribed, inFlight: false, peripheralID: id)
        )
        try await subscribed.handle(.subscribed)
        try await subscribed.readDocumentedCharacteristic(DocumentedReadableCharacteristic.modelNumber)
        #expect(subscribed.state == .subscribed)
        #expect(subscribedRuntime.log.effects.contains(.read(DocumentedReadableCharacteristic.modelNumber)))
        await #expect(throws: TransportError.authenticationUnimplemented) {
            try await subscribed.handle(.requestAuthentication)
        }
        #expect(subscribed.state != .authenticating)
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


    @Test func commandStartIncludesScanConnectAndRead() {
        let machine = TransportStateMachine()
        #expect(machine.isCommandStart(.startScan))
        #expect(machine.isCommandStart(.connect(peripheralID: UUID())))
        #expect(!machine.isCommandStart(.advertisement(peripheralID: UUID())))
        #expect(!machine.isCommandStart(.subscribed))
    }

    @Test func connectWhileScanningIsAllowedDespiteInFlight() {
        var machine = TransportStateMachine()
        #expect(machine.send(.startScan) == [.startScan])
        #expect(machine.inFlight)
        let id = UUID()
        #expect(machine.send(.connect(peripheralID: id)) == [.stopScan, .connect(id)])
        #expect(machine.state == .connecting)
    }

    @Test func secondConnectFromIdleWhileInFlightIsBlocked() {
        var machine = TransportStateMachine(state: .idle, inFlight: true)
        let id = UUID()
        #expect(machine.send(.connect(peripheralID: id)) == [.fail(.commandInFlight)])
        #expect(machine.state == .idle)
    }

    @Test func secondReadWhileInFlightIsBlocked() {
        var machine = TransportStateMachine()
        let id = UUID()
        _ = machine.send(.startScan)
        _ = machine.send(.connect(peripheralID: id))
        _ = machine.send(.connected)
        _ = machine.send(.servicesDiscovered)
        _ = machine.send(.characteristicsDiscovered)
        _ = machine.send(.subscribed)
        let characteristic = DocumentedReadableCharacteristic.manufacturerName
        #expect(machine.beginAllowlistedRead(characteristic) == [.read(characteristic)])
        #expect(machine.inFlight)
        #expect(machine.beginAllowlistedRead(characteristic) == [.fail(.commandInFlight)])
        #expect(machine.send(.requestAuthentication) == [.fail(.authenticationUnimplemented)])
        #expect(machine.send(.requestBinding) == [.fail(.bindingUnimplemented)])
        #expect(machine.state == .subscribed)
    }

    @Test func backoffJitterStaysWithinBounds() {
        let low = TransportBackoff.delaySeconds(attempt: 0, unitJitter: 0)
        let high = TransportBackoff.delaySeconds(attempt: 0, unitJitter: 1)
        #expect(low <= high)
        #expect(low >= 0)
        #expect(high <= TransportBackoff.defaultMaximumSeconds)
        #expect(TransportBackoff.delaySeconds(attempt: 0, unitJitter: -4) == low)
        #expect(TransportBackoff.delaySeconds(attempt: 0, unitJitter: 8) == high)
        let capped = TransportBackoff.delaySeconds(attempt: 20, unitJitter: 1)
        #expect(capped <= TransportBackoff.defaultMaximumSeconds)
        let later = TransportBackoff.delaySeconds(attempt: 3, unitJitter: 0.5)
        let early = TransportBackoff.delaySeconds(attempt: 0, unitJitter: 0.5)
        #expect(later >= early)
    }

    @Test func recordingRuntimeRemainsDefaultAndMachineFailClosesAuthBind() async throws {
        let runtime = RecordingBluetoothRuntime()
        let session = GS3TransportSession(runtime: runtime)
        try await session.handle(.startScan)
        await #expect(throws: TransportError.authenticationUnimplemented) {
            try await session.handle(.requestAuthentication)
        }
        await #expect(throws: TransportError.bindingUnimplemented) {
            try await session.handle(.requestBinding)
        }
        #expect(session.state == .scanning)
    }

#if canImport(CoreBluetooth)
    @Test func coreBluetoothConstantsAndAuthorizationMapping() {
        #expect(CoreBluetoothRuntime.restorationIdentifier == "app.sugarman.ios.gs3.transport")
        #expect(CoreBluetoothRuntime.queueLabel == "app.sugarman.ios.gs3.transport")
        #expect(BluetoothAuthorizationMapping.transportError(for: .denied) == .permissionDenied)
        #expect(BluetoothAuthorizationMapping.transportError(for: .restricted) == .permissionDenied)
        #expect(BluetoothAuthorizationMapping.transportError(for: .allowedAlways) == nil)
        #expect(BluetoothAuthorizationMapping.transportError(for: .notDetermined) == nil)
        #expect(BluetoothAuthorizationMapping.transportError(forManagerState: .unauthorized) == .permissionDenied)
        #expect(BluetoothAuthorizationMapping.transportError(forManagerState: .poweredOff) == .bluetoothUnavailable)
        #expect(BluetoothAuthorizationMapping.transportError(forManagerState: .unsupported) == .bluetoothUnavailable)
        #expect(BluetoothAuthorizationMapping.transportError(forManagerState: .poweredOn) == nil)
        #expect(BluetoothAuthorizationMapping.transportError(forManagerState: .unknown) == nil)
    }
#endif

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
