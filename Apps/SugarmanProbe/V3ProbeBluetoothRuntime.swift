// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3DeveloperProbe
import GS3Protocol
@preconcurrency import CoreBluetooth

struct ProbePeripheral: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String?
    let rssi: Int

    var displayName: String { name ?? "Unnamed peripheral" }
}

enum ProbeRuntimeEvent: Sendable, Equatable {
    case discovered(ProbePeripheral)
    case status(String)
    case diagnostic(ProbeDiagnosticEntry)
    case reading(V3ProbeReading)
    case failed(String)
    case finished(completedSuccessfully: Bool)
}

struct ProbeDiagnosticEntry: Identifiable, Sendable, Equatable {
    let id: Int
    let message: String

    var displayText: String {
        String(format: "%02d  %@", id, message)
    }
}

private enum ProbeWriteKind: Sendable, Equatable {
    case authentication
    case effectiveData

    var diagnosticName: String {
        switch self {
        case .authentication: "E2 authentication"
        case .effectiveData: "0x39 effective-data request"
        }
    }
}

/// Foreground-only CoreBluetooth adapter for the separate developer target.
/// There is no restoration identifier, reconnect, retry, raw-write API, or
/// dependency from the App Store `Sugarman` target.
final class V3ProbeBluetoothRuntime: NSObject, @unchecked Sendable {
    private static let serviceUUID = CBUUID(string: "FF30")
    private static let notificationUUID = CBUUID(string: "FF31")
    private static let transmissionUUID = CBUUID(string: "FF32")
    private static let timeoutSeconds: TimeInterval = 420

    private let queue = DispatchQueue(label: "app.sugarman.probe.gs3-v3")
    private let eventHandler: @Sendable (ProbeRuntimeEvent) -> Void
    private var central: CBCentralManager?
    private var discovered: [UUID: CBPeripheral] = [:]
    private var scanWhenPoweredOn = false
    private var activePeripheral: CBPeripheral?
    private var notificationCharacteristic: CBCharacteristic?
    private var transmissionCharacteristic: CBCharacteristic?
    private var probe: V3DeveloperHandoverProbe?
    private var runToken: UUID?
    private var finishing = false
    private var completedSuccessfully = false
    private var diagnosticSequence = 0
    private var inFlightWrite: ProbeWriteKind?
    private var queuedTransmission: V3ProbeTransmission?
    private var authenticationWriteCallCount = 0
    private var effectiveDataWriteCallCount = 0

    init(eventHandler: @escaping @Sendable (ProbeRuntimeEvent) -> Void) {
        self.eventHandler = eventHandler
        super.init()
    }

    func startScanning() {
        queue.async {
            guard self.runToken == nil else {
                self.emit(.failed("The previous bounded probe is still disconnecting."))
                return
            }
            self.ensureCentral()
            guard CBManager.authorization != .denied,
                  CBManager.authorization != .restricted else {
                self.emit(.failed("Bluetooth permission is denied."))
                return
            }
            guard let central = self.central else { return }
            if central.state == .poweredOn {
                central.scanForPeripherals(withServices: nil)
                self.emit(.status("Scanning. The imported expected name is pinned first."))
            } else {
                self.scanWhenPoweredOn = true
                self.emit(.status("Waiting for Bluetooth to become available."))
            }
        }
    }

    func stopScanning() {
        queue.async {
            self.scanWhenPoweredOn = false
            self.central?.stopScan()
            self.emit(.status("Scan stopped."))
        }
    }

    func run(peripheral selected: ProbePeripheral, material: V3ProbeMaterial) {
        queue.async {
            guard self.runToken == nil else {
                self.emit(.failed("A bounded probe is already running."))
                return
            }
            self.ensureCentral()
            guard let central = self.central, central.state == .poweredOn else {
                self.emit(.failed("Bluetooth is unavailable."))
                return
            }
            guard material.expectedPeripheralName.map({ selected.name == $0 }) ?? true else {
                self.emit(.failed("The selected peripheral does not match the imported expected name."))
                return
            }
            let peripheral = self.discovered[selected.id]
                ?? central.retrievePeripherals(withIdentifiers: [selected.id]).first
            guard let peripheral else {
                self.emit(.failed("The selected peripheral is no longer available."))
                return
            }

            central.stopScan()
            self.scanWhenPoweredOn = false
            self.activePeripheral = peripheral
            self.notificationCharacteristic = nil
            self.transmissionCharacteristic = nil
            self.probe = V3DeveloperHandoverProbe(material: material)
            self.finishing = false
            self.completedSuccessfully = false
            self.diagnosticSequence = 0
            self.inFlightWrite = nil
            self.queuedTransmission = nil
            self.authenticationWriteCallCount = 0
            self.effectiveDataWriteCallCount = 0
            let token = UUID()
            self.runToken = token
            peripheral.delegate = self
            self.emitDiagnostic(
                "Session started for the explicitly selected expected peripheral; no identifier retained."
            )
            self.emit(.status("Connecting once; there is no automatic reconnect."))
            central.connect(peripheral, options: nil)
            self.queue.asyncAfter(deadline: .now() + Self.timeoutSeconds) { [weak self] in
                guard let self, self.runToken == token else { return }
                self.fail("The bounded probe timed out and is disconnecting.")
            }
        }
    }

    func cancel() {
        queue.async {
            guard self.runToken != nil else {
                self.central?.stopScan()
                return
            }
            if var probe = self.probe {
                let effects = probe.cancel()
                self.probe = probe
                self.finishing = true
                self.emit(.status("Cancelled; disconnecting."))
                self.apply(effects)
            } else {
                self.disconnectAndFinish()
            }
        }
    }

    private func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue, options: nil)
        }
    }

    private func emit(_ event: ProbeRuntimeEvent) {
        eventHandler(event)
    }

    private func emitDiagnostic(_ message: String) {
        diagnosticSequence += 1
        emit(.diagnostic(ProbeDiagnosticEntry(id: diagnosticSequence, message: message)))
    }

    private func apply(_ effects: [V3ProbeEffect]) {
        for effect in effects {
            switch effect {
            case .subscribeToNotifications:
                guard let peripheral = activePeripheral,
                      let characteristic = notificationCharacteristic else {
                    fail("FF31 notification characteristic is unavailable.")
                    return
                }
                peripheral.setNotifyValue(true, for: characteristic)
                emit(.status("Subscribing to FF31 notifications."))
                emitDiagnostic("Enabling FF31 notifications; state=subscribing.")

            case .transmit(let transmission):
                transmit(transmission)

            case .report(let reading, let count, let required):
                emit(.reading(reading))
                emit(.status("Validated live readings: \(count)/\(required)."))

            case .disconnect:
                if probe?.state == .completed,
                   (authenticationWriteCallCount != 1 || effectiveDataWriteCallCount != 1) {
                    fail("The probe reached completion without both bounded CoreBluetooth write calls.")
                    return
                }
                if probe?.state == .completed,
                   probe?.quarantinedGlucoseCommandCount == 0 {
                    emitDiagnostic(
                        "Completion gate passed with CoreBluetooth write calls E2=1, 0x39=1; disconnecting."
                    )
                } else if probe?.state == .completed {
                    emitDiagnostic(
                        "Five live readings followed one quarantined protocol command; "
                            + "the diagnostic gate remains inconclusive; disconnecting."
                    )
                    emit(
                        .status(
                            "Five live readings were validated after one quarantined protocol "
                                + "command. The diagnostic gate remains inconclusive."
                        )
                    )
                }
                finishing = true
                completedSuccessfully = probe?.state == .completed
                    && probe?.quarantinedGlucoseCommandCount == 0
                disconnectAndFinish()
            }
        }
    }

    private func transmit(_ transmission: V3ProbeTransmission) {
        guard !finishing else { return }
        if let inFlightWrite {
            guard inFlightWrite == .authentication,
                  case .effectiveData = transmission,
                  queuedTransmission == nil else {
                fail("A second application write was requested while another write was in flight.")
                return
            }
            queuedTransmission = transmission
            emitDiagnostic(
                "0x39 authorized after authentication acceptance; waiting for the E2 CoreBluetooth write acknowledgement."
            )
            return
        }

        guard let peripheral = activePeripheral,
              let characteristic = transmissionCharacteristic,
              characteristic.uuid == Self.transmissionUUID,
              characteristic.properties.contains(.write) else {
            fail("FF32 acknowledged-write characteristic is unavailable.")
            return
        }

        let frame: EncodedFrame
        let message: String
        let writeKind: ProbeWriteKind
        switch transmission {
        case .authentication(let typedFrame):
            guard typedFrame.byteCount == 38 else {
                fail("Typed authentication frame has an invalid length.")
                return
            }
            guard authenticationWriteCallCount == 0,
                  effectiveDataWriteCallCount == 0 else {
                fail("The bounded E2 CoreBluetooth write-call limit was reached.")
                return
            }
            frame = typedFrame
            writeKind = .authentication
            authenticationWriteCallCount += 1
            message = "Transmitting the single typed 0xE2 authentication."
        case .effectiveData(let typedFrame):
            guard typedFrame.byteCount == 7 else {
                fail("Typed effective-data frame has an invalid length.")
                return
            }
            guard authenticationWriteCallCount == 1,
                  effectiveDataWriteCallCount == 0 else {
                fail("The bounded 0x39 CoreBluetooth write-call limit was reached.")
                return
            }
            frame = typedFrame
            writeKind = .effectiveData
            effectiveDataWriteCallCount += 1
            message = "Authentication accepted; transmitting the single typed 0x39 request."
        }
        inFlightWrite = writeKind
        emit(.status(message))
        emitDiagnostic(
            "TX FF32 \(writeKind.diagnosticName), \(frame.byteCount) bytes; "
                + "CoreBluetooth write calls E2=\(authenticationWriteCallCount), "
                + "0x39=\(effectiveDataWriteCallCount)."
        )
        peripheral.writeValue(
            Data(frame.bytes),
            for: characteristic,
            type: .withResponse
        )
    }

    private func fail(_ message: String) {
        guard runToken != nil else {
            emit(.failed(message))
            return
        }
        finishing = true
        completedSuccessfully = false
        queuedTransmission = nil
        emitDiagnostic("Fail closed: \(message)")
        emit(.failed(message))
        disconnectAndFinish()
    }

    private func disconnectAndFinish() {
        guard let token = runToken else { return }
        guard let peripheral = activePeripheral, let central else {
            let completedSuccessfully = completedSuccessfully
            resetRun()
            emit(.finished(completedSuccessfully: completedSuccessfully))
            return
        }
        central.cancelPeripheralConnection(peripheral)
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.runToken == token else { return }
            let completedSuccessfully = self.completedSuccessfully
            self.resetRun()
            self.emit(.finished(completedSuccessfully: completedSuccessfully))
        }
    }

    private func resetRun() {
        runToken = nil
        activePeripheral = nil
        notificationCharacteristic = nil
        transmissionCharacteristic = nil
        probe = nil
        finishing = false
        completedSuccessfully = false
        inFlightWrite = nil
        queuedTransmission = nil
        authenticationWriteCallCount = 0
        effectiveDataWriteCallCount = 0
    }
}

extension V3ProbeBluetoothRuntime: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, scanWhenPoweredOn {
            scanWhenPoweredOn = false
            central.scanForPeripherals(withServices: nil)
            emit(.status("Scanning. The imported expected name is pinned first."))
        } else if central.state == .unauthorized {
            if runToken != nil {
                fail("Bluetooth permission is denied.")
            } else {
                emit(.failed("Bluetooth permission is denied."))
            }
        } else if central.state == .poweredOff || central.state == .unsupported {
            if runToken != nil {
                fail("Bluetooth is unavailable.")
            } else {
                emit(.failed("Bluetooth is unavailable."))
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripheral.delegate = self
        discovered[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        emit(
            .discovered(
                ProbePeripheral(
                    id: peripheral.identifier,
                    name: name,
                    rssi: RSSI.intValue
                )
            )
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard runToken != nil, activePeripheral?.identifier == peripheral.identifier else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        emitDiagnostic("Connected once; discovering only service FF30.")
        emit(.status("Connected; discovering only the FF30 service."))
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard activePeripheral?.identifier == peripheral.identifier else { return }
        fail(error?.localizedDescription ?? "The one-shot connection failed.")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard activePeripheral?.identifier == peripheral.identifier else { return }
        if !finishing, let error {
            emit(.failed(error.localizedDescription))
        } else if !finishing {
            emit(.failed("The sensor disconnected before the bounded probe completed."))
        }
        let completedSuccessfully = completedSuccessfully
        resetRun()
        emit(.finished(completedSuccessfully: completedSuccessfully))
    }
}

extension V3ProbeBluetoothRuntime: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard activePeripheral?.identifier == peripheral.identifier else { return }
        if let error {
            fail(error.localizedDescription)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            fail("The selected peripheral does not expose FF30.")
            return
        }
        peripheral.discoverCharacteristics(
            [Self.notificationUUID, Self.transmissionUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard activePeripheral?.identifier == peripheral.identifier,
              service.uuid == Self.serviceUUID else { return }
        if let error {
            fail(error.localizedDescription)
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.notificationUUID,
               characteristic.properties.contains(.notify) {
                notificationCharacteristic = characteristic
            } else if characteristic.uuid == Self.transmissionUUID,
                      characteristic.properties.contains(.write) {
                transmissionCharacteristic = characteristic
            }
        }
        guard notificationCharacteristic != nil, transmissionCharacteristic != nil else {
            fail("The expected FF31/FF32 properties are unavailable.")
            return
        }
        emitDiagnostic("Found FF31 notify and FF32 acknowledged-write characteristics.")
        do {
            guard var probe else { throw V3ProbeError.invalidTransition(from: .failed) }
            let effects = try probe.start()
            self.probe = probe
            apply(effects)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard activePeripheral?.identifier == peripheral.identifier,
              characteristic.uuid == Self.notificationUUID else { return }
        if let error {
            fail(error.localizedDescription)
            return
        }
        guard characteristic.isNotifying else {
            fail("FF31 notification subscription was not enabled.")
            return
        }
        emitDiagnostic("FF31 notification subscription enabled.")
        do {
            guard var probe else { throw V3ProbeError.invalidTransition(from: .failed) }
            let effects = try probe.didSubscribe()
            self.probe = probe
            apply(effects)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard activePeripheral?.identifier == peripheral.identifier,
              characteristic.uuid == Self.transmissionUUID else { return }
        guard !finishing else {
            inFlightWrite = nil
            queuedTransmission = nil
            return
        }
        if let error {
            fail(error.localizedDescription)
            return
        }
        guard let completedWrite = inFlightWrite else {
            fail("CoreBluetooth acknowledged an FF32 write with no tracked in-flight command.")
            return
        }
        inFlightWrite = nil
        emitDiagnostic("CoreBluetooth acknowledged FF32 \(completedWrite.diagnosticName).")
        if let queuedTransmission {
            self.queuedTransmission = nil
            transmit(queuedTransmission)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard activePeripheral?.identifier == peripheral.identifier,
              !finishing,
              characteristic.uuid == Self.notificationUUID else { return }
        if let error {
            fail(error.localizedDescription)
            return
        }
        guard let data = characteristic.value else { return }
        if let inFlightWrite {
            emitDiagnostic(
                "RX FF31 delivered while CoreBluetooth awaited FF32 "
                    + "\(inFlightWrite.diagnosticName) acknowledgement."
            )
        }
        guard var activeProbe = probe else {
            fail(V3ProbeError.invalidTransition(from: .failed).localizedDescription)
            return
        }
        do {
            let effects = try activeProbe.didReceive(
                EncodedFrame(bytes: [UInt8](data)),
                effectiveDataWriteAcknowledgementPending: inFlightWrite == .effectiveData
            )
            self.probe = activeProbe
            if let diagnostic = activeProbe.lastPacketDiagnostic {
                emitDiagnostic(diagnostic.description)
            }
            apply(effects)
        } catch {
            self.probe = activeProbe
            if let diagnostic = activeProbe.lastPacketDiagnostic {
                emitDiagnostic(diagnostic.description)
            }
            fail(error.localizedDescription)
        }
    }
}
