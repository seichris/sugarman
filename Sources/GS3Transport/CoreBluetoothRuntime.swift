// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

#if canImport(CoreBluetooth)
import CoreBluetooth

/// Maps CoreBluetooth authorization and manager state onto `TransportError`.
/// Denied/restricted/unauthorized become `permissionDenied`, which is distinct
/// from `bluetoothUnavailable` (powered off, unsupported).
public enum BluetoothAuthorizationMapping: Sendable {
    public static func transportError(for authorization: CBManagerAuthorization) -> TransportError? {
        switch authorization {
        case .denied, .restricted:
            return .permissionDenied
        case .allowedAlways, .notDetermined:
            return nil
        @unknown default:
            return .bluetoothUnavailable
        }
    }

    public static func transportError(forManagerState state: CBManagerState) -> TransportError? {
        switch state {
        case .unauthorized:
            return .permissionDenied
        case .poweredOff, .unsupported, .resetting:
            return .bluetoothUnavailable
        case .poweredOn, .unknown:
            return nil
        @unknown default:
            return .bluetoothUnavailable
        }
    }
}

/// Read-only CoreBluetooth adapter behind `BluetoothRuntime`.
///
/// Implements scan, connect, discover, subscribe, and allowlisted Device
/// Information characteristic reads. Does not implement write, authenticate,
/// bind, or activate. Does not call `writeValue`. Simulator has no BLE
/// peripheral; this type must not be required to talk to live hardware in tests.
public final class CoreBluetoothRuntime: NSObject, BluetoothRuntime, @unchecked Sendable {
    public static let restorationIdentifier = "app.sugarman.ios.gs3.transport"
    public static let queueLabel = "app.sugarman.ios.gs3.transport"

    public let queue: DispatchQueue
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var characteristics: [UUID: CBCharacteristic] = [:]
    private var pending: CheckedContinuation<Void, Error>?
    private var startScanAfterPoweredOn = false
    private var backoffAttempt = 0

    public init(queue: DispatchQueue = DispatchQueue(label: CoreBluetoothRuntime.queueLabel)) {
        self.queue = queue
        super.init()
    }

    public func perform(_ effect: TransportEffect) async throws {
        switch effect {
        case .startScan:
            try await startScan()
        case .stopScan:
            await stopScan()
        case .connect(let id):
            try await connect(id)
        case .cancelConnection(let id):
            await cancelConnection(id)
        case .discoverServices:
            try await discoverServices()
        case .discoverCharacteristics:
            try await discoverCharacteristics()
        case .subscribe:
            // Read-only: do not write CCCD. DIS reads do not require notify.
            return
        case .read(let uuid):
            try await readAllowlisted(uuid)
        case .waitBackoff:
            let seconds = TransportBackoff.delaySeconds(
                attempt: backoffAttempt,
                unitJitter: TransportBackoff.randomUnitJitter()
            )
            backoffAttempt = min(backoffAttempt + 1, 16)
            let nanoseconds = UInt64((seconds * 1_000_000_000).rounded(.up))
            try await Task.sleep(nanoseconds: nanoseconds)
        case .fail(let error):
            throw error
        }
    }

    private func startScan() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.ensureCentralLocked()
                    if let error = BluetoothAuthorizationMapping.transportError(for: CBManager.authorization) {
                        throw error
                    }
                    self.backoffAttempt = 0
                    switch self.central?.state {
                    case .poweredOn:
                        self.central?.scanForPeripherals(withServices: nil, options: nil)
                        continuation.resume()
                    case .unauthorized:
                        continuation.resume(throwing: TransportError.permissionDenied)
                    case .poweredOff, .unsupported, .resetting:
                        continuation.resume(throwing: TransportError.bluetoothUnavailable)
                    default:
                        self.pending = continuation
                        self.startScanAfterPoweredOn = true
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopScan() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.startScanAfterPoweredOn = false
                self.central?.stopScan()
                continuation.resume()
            }
        }
    }

    private func connect(_ id: UUID) async throws {
        try await enqueue { runtime in
            try runtime.ensureCentralLocked()
            let peripheral: CBPeripheral
            if let known = runtime.peripherals[id] {
                peripheral = known
            } else if let retrieved = runtime.central?.retrievePeripherals(withIdentifiers: [id]).first {
                retrieved.delegate = runtime
                runtime.peripherals[id] = retrieved
                peripheral = retrieved
            } else {
                throw TransportError.timeout
            }
            runtime.central?.stopScan()
            runtime.central?.connect(peripheral, options: nil)
        }
    }

    private func cancelConnection(_ id: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let peripheral = self.peripherals[id] {
                    self.central?.cancelPeripheralConnection(peripheral)
                }
                if self.connected?.identifier == id {
                    self.connected = nil
                }
                continuation.resume()
            }
        }
    }

    private func discoverServices() async throws {
        try await enqueue { runtime in
            guard let peripheral = runtime.connected else {
                throw TransportError.invalidTransition(from: .connecting)
            }
            let dis = CBUUID(nsuuid: DocumentedReadableCharacteristic.deviceInformationService)
            peripheral.discoverServices([dis])
        }
    }

    private func discoverCharacteristics() async throws {
        try await enqueue { runtime in
            guard let peripheral = runtime.connected else {
                throw TransportError.invalidTransition(from: .discovering)
            }
            let allowlisted = DocumentedReadableCharacteristic.all.map { CBUUID(nsuuid: $0) }
            let services = peripheral.services ?? []
            guard !services.isEmpty else {
                throw TransportError.timeout
            }
            for service in services {
                peripheral.discoverCharacteristics(allowlisted, for: service)
            }
        }
    }

    private func readAllowlisted(_ uuid: UUID) async throws {
        guard DocumentedReadableCharacteristic.isAllowlisted(uuid) else {
            throw TransportError.mutatingOperationRefused
        }
        try await enqueue { runtime in
            guard let characteristic = runtime.characteristics[uuid] else {
                throw TransportError.timeout
            }
            guard let peripheral = runtime.connected else {
                throw TransportError.invalidTransition(from: .subscribed)
            }
            peripheral.readValue(for: characteristic)
        }
    }

    private func ensureCentralLocked() throws {
        if let error = BluetoothAuthorizationMapping.transportError(for: CBManager.authorization) {
            throw error
        }
        if central == nil {
            var options: [String: Any] = [:]
            #if os(iOS)
            options[CBCentralManagerOptionRestoreIdentifierKey] = Self.restorationIdentifier
            #endif
            central = CBCentralManager(delegate: self, queue: queue, options: options.isEmpty ? nil : options)
        }
    }

    private func enqueue(_ body: @escaping @Sendable (CoreBluetoothRuntime) throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if self.pending != nil {
                    continuation.resume(throwing: TransportError.commandInFlight)
                    return
                }
                do {
                    self.pending = continuation
                    try body(self)
                } catch {
                    self.pending = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func resumePending(error: Error?) {
        startScanAfterPoweredOn = false
        guard let pending else { return }
        self.pending = nil
        if let error {
            pending.resume(throwing: error)
        } else {
            pending.resume()
        }
    }

    private func sugarmanUUID(from cbuuid: CBUUID) -> UUID? {
        if let uuid = UUID(uuidString: cbuuid.uuidString) {
            return uuid
        }
        return UUID(uuidString: "0000\(cbuuid.uuidString)-0000-1000-8000-00805F9B34FB")
    }
}

extension CoreBluetoothRuntime: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if let error = BluetoothAuthorizationMapping.transportError(forManagerState: central.state) {
            resumePending(error: error)
            return
        }
        if startScanAfterPoweredOn, central.state == .poweredOn {
            startScanAfterPoweredOn = false
            central.scanForPeripherals(withServices: nil, options: nil)
            resumePending(error: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            peripheral.delegate = self
            peripherals[peripheral.identifier] = peripheral
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        _ = advertisementData
        _ = RSSI
        peripheral.delegate = self
        peripherals[peripheral.identifier] = peripheral
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        connected = peripheral
        peripherals[peripheral.identifier] = peripheral
        resumePending(error: nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        _ = peripheral
        resumePending(error: error ?? TransportError.timeout)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        _ = error
        if connected?.identifier == peripheral.identifier {
            connected = nil
        }
    }
}

extension CoreBluetoothRuntime: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            resumePending(error: error)
            return
        }
        _ = peripheral
        resumePending(error: nil)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            resumePending(error: error)
            return
        }
        for characteristic in service.characteristics ?? [] {
            if let uuid = sugarmanUUID(from: characteristic.uuid),
               DocumentedReadableCharacteristic.isAllowlisted(uuid) {
                characteristics[uuid] = characteristic
            }
        }
        resumePending(error: nil)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        _ = peripheral
        _ = characteristic.value?.count
        resumePending(error: error)
    }
}
#endif
