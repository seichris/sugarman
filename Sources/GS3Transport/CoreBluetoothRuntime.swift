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
    private enum PendingOperation: Equatable {
        case startScan
        case connect(UUID)
        case discoverServices
        case discoverCharacteristics
        case read(UUID)
    }
    /// Stable CoreBluetooth state-restoration identifier. Identity only —
    /// this adapter does not reconnect to a live sensor or resume
    /// authentication after `willRestoreState`.
    public static let restorationIdentifier = "app.sugarman.ios.gs3.transport"
    public static let queueLabel = "app.sugarman.ios.gs3.transport"

    public let queue: DispatchQueue
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connected: CBPeripheral?
    private var characteristics: [UUID: CBCharacteristic] = [:]
    private var pending: CheckedContinuation<Void, Error>?
    private var pendingOperationID: UUID?
    private var pendingOperation: PendingOperation?
    private var startScanAfterPoweredOn = false
    private var backoffAttempt = 0
    private var advertisements: [UUID: AdvertisementSnapshot] = [:]
    private var documentedTexts: [UUID: String] = [:]
    private var gattServices: [GATTServiceSnapshot] = []
    private var serialByteCount: Int?
    private var remainingCharacteristicDiscoveries = 0
    private let operationTimeoutSeconds: TimeInterval
    public var onDiscover: (@Sendable (AdvertisementSnapshot) -> Void)?

    public var discoveredAdvertisements: [AdvertisementSnapshot] {
        queue.sync {
            advertisements.values.sorted { $0.peripheralID.uuidString < $1.peripheralID.uuidString }
        }
    }

    public func documentedReadableText(for uuid: UUID) -> String? {
        if uuid == DocumentedReadableCharacteristic.serialNumber {
            return nil
        }
        return queue.sync { documentedTexts[uuid] }
    }

    public var discoveredGATTServices: [GATTServiceSnapshot] {
        queue.sync { gattServices }
    }

    public var serialNumberByteCount: Int? {
        queue.sync { serialByteCount }
    }

    public func deviceInformationSnapshot() -> DeviceInformationSnapshot {
        DeviceInformationSnapshot.omittingSerial(from: queue.sync { documentedTexts })
    }

    public init(
        queue: DispatchQueue = DispatchQueue(label: CoreBluetoothRuntime.queueLabel),
        operationTimeoutSeconds: TimeInterval = 15
    ) {
        self.queue = queue
        self.operationTimeoutSeconds = operationTimeoutSeconds
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
                    self.advertisements = [:]
                    switch self.central?.state {
                    case .poweredOn:
                        self.central?.scanForPeripherals(withServices: nil, options: nil)
                        continuation.resume()
                    case .unauthorized:
                        continuation.resume(throwing: TransportError.permissionDenied)
                    case .poweredOff, .unsupported, .resetting:
                        continuation.resume(throwing: TransportError.bluetoothUnavailable)
                    default:
                        guard self.pending == nil else {
                            continuation.resume(throwing: TransportError.commandInFlight)
                            return
                        }
                        self.pending = continuation
                        self.pendingOperation = .startScan
                        let operationID = UUID()
                        self.pendingOperationID = operationID
                        self.startScanAfterPoweredOn = true
                        self.scheduleTimeout(operationID: operationID)
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
                if self.pendingOperation == .startScan {
                    self.resumePending(error: TransportError.disconnected)
                }
                continuation.resume()
            }
        }
    }

    private func connect(_ id: UUID) async throws {
        try await enqueue(kind: .connect(id)) { runtime in
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
            runtime.resetPeripheralEvidenceLocked()
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
                if self.pending != nil {
                    self.resumePending(error: TransportError.disconnected)
                }
                continuation.resume()
            }
        }
    }

    private func discoverServices() async throws {
        try await enqueue(kind: .discoverServices) { runtime in
            guard let peripheral = runtime.connected else {
                throw TransportError.invalidTransition(from: .connecting)
            }
            // P1 GATT map needs every service. Reads stay allowlisted below.
            peripheral.discoverServices(nil)
        }
    }

    private func discoverCharacteristics() async throws {
        try await enqueue(kind: .discoverCharacteristics) { runtime in
            guard let peripheral = runtime.connected else {
                throw TransportError.invalidTransition(from: .discovering)
            }
            let services = peripheral.services ?? []
            guard !services.isEmpty else {
                throw TransportError.timeout
            }
            runtime.gattServices = []
            runtime.remainingCharacteristicDiscoveries = services.count
            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    private func readAllowlisted(_ uuid: UUID) async throws {
        guard DocumentedReadableCharacteristic.isAllowlisted(uuid) else {
            throw TransportError.mutatingOperationRefused
        }
        try await enqueue(kind: .read(uuid)) { runtime in
            guard let characteristic = runtime.characteristics[uuid] else {
                throw TransportError.characteristicUnavailable(uuid)
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

    private func enqueue(
        kind: PendingOperation,
        _ body: @escaping @Sendable (CoreBluetoothRuntime) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if self.pending != nil {
                    continuation.resume(throwing: TransportError.commandInFlight)
                    return
                }
                do {
                    self.pending = continuation
                    self.pendingOperation = kind
                    let operationID = UUID()
                    self.pendingOperationID = operationID
                    self.scheduleTimeout(operationID: operationID)
                    try body(self)
                } catch {
                    self.pending = nil
                    self.pendingOperationID = nil
                    self.pendingOperation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func resumePending(error: Error?) {
        startScanAfterPoweredOn = false
        guard let pending else { return }
        self.pending = nil
        pendingOperationID = nil
        pendingOperation = nil
        if let error {
            pending.resume(throwing: error)
        } else {
            pending.resume()
        }
    }

    private func scheduleTimeout(operationID: UUID) {
        queue.asyncAfter(deadline: .now() + operationTimeoutSeconds) { [weak self] in
            guard let self, self.pendingOperationID == operationID else { return }
            if case .connect(let id) = self.pendingOperation,
               let peripheral = self.peripherals[id] {
                self.central?.cancelPeripheralConnection(peripheral)
            }
            if self.pendingOperation == .startScan {
                self.central?.stopScan()
            }
            self.resumePending(error: TransportError.timeout)
        }
    }

    private func resetPeripheralEvidenceLocked() {
        connected = nil
        characteristics = [:]
        documentedTexts = [:]
        gattServices = []
        serialByteCount = nil
        remainingCharacteristicDiscoveries = 0
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
        if startScanAfterPoweredOn, pendingOperation == .startScan, central.state == .poweredOn {
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
        peripheral.delegate = self
        peripherals[peripheral.identifier] = peripheral
        let localName = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .compactMap { self.sugarmanUUID(from: $0) }
        let snapshot = AdvertisementSnapshot(
            peripheralID: peripheral.identifier,
            name: localName,
            serviceUUIDs: services,
            rssi: RSSI.intValue
        )
        advertisements[peripheral.identifier] = snapshot
        onDiscover?(snapshot)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        connected = peripheral
        peripherals[peripheral.identifier] = peripheral
        if pendingOperation == .connect(peripheral.identifier) {
            resumePending(error: nil)
        } else {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if pendingOperation == .connect(peripheral.identifier) {
            resumePending(error: error ?? TransportError.timeout)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let wasConnectedPeripheral = connected?.identifier == peripheral.identifier
        if wasConnectedPeripheral {
            connected = nil
        }
        let matchesPendingOperation: Bool
        switch pendingOperation {
        case .connect(let id):
            matchesPendingOperation = id == peripheral.identifier
        case .discoverServices, .discoverCharacteristics, .read:
            matchesPendingOperation = wasConnectedPeripheral
        case .startScan, nil:
            matchesPendingOperation = false
        }
        if matchesPendingOperation {
            resumePending(error: error ?? TransportError.disconnected)
        }
    }
}

extension CoreBluetoothRuntime: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard pendingOperation == .discoverServices,
              connected?.identifier == peripheral.identifier else { return }
        if let error {
            resumePending(error: error)
            return
        }
        _ = peripheral
        resumePending(error: nil)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard pendingOperation == .discoverCharacteristics,
              connected?.identifier == peripheral.identifier else { return }
        if let error {
            remainingCharacteristicDiscoveries = 0
            resumePending(error: error)
            return
        }
        var mapped: [GATTCharacteristicSnapshot] = []
        for characteristic in service.characteristics ?? [] {
            let uuid = sugarmanUUID(from: characteristic.uuid)
            if let uuid,
               DocumentedReadableCharacteristic.isAllowlisted(uuid),
               characteristic.properties.contains(.read) {
                characteristics[uuid] = characteristic
            }
            if let uuid {
                mapped.append(
                    GATTCharacteristicSnapshot(
                        uuid: uuid,
                        properties: Self.propertyNames(characteristic.properties),
                        valueByteCount: characteristic.value?.count
                    )
                )
            }
        }
        if let serviceUUID = sugarmanUUID(from: service.uuid) {
            gattServices.append(GATTServiceSnapshot(uuid: serviceUUID, characteristics: mapped))
        }
        remainingCharacteristicDiscoveries = max(0, remainingCharacteristicDiscoveries - 1)
        if remainingCharacteristicDiscoveries == 0 {
            resumePending(error: nil)
        }
        _ = peripheral
    }

    private static func propertyNames(_ properties: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if properties.contains(.broadcast) { names.append("broadcast") }
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.writeWithoutResponse) { names.append("writeWithoutResponse") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        if properties.contains(.authenticatedSignedWrites) { names.append("authenticatedSignedWrites") }
        if properties.contains(.extendedProperties) { names.append("extendedProperties") }
        if properties.contains(.notifyEncryptionRequired) { names.append("notifyEncryptionRequired") }
        if properties.contains(.indicateEncryptionRequired) { names.append("indicateEncryptionRequired") }
        return names
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard connected?.identifier == peripheral.identifier,
              let characteristicUUID = sugarmanUUID(from: characteristic.uuid),
              pendingOperation == .read(characteristicUUID) else { return }
        if error == nil {
            let uuid = characteristicUUID
            let count = characteristic.value?.count
            if uuid == DocumentedReadableCharacteristic.serialNumber {
                serialByteCount = count
                // Never store serial text.
            } else if DocumentedReadableCharacteristic.isAllowlisted(uuid),
                      let data = characteristic.value,
                      let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    documentedTexts[uuid] = trimmed
                }
            }
            if let index = gattServices.firstIndex(where: { service in
                service.characteristics.contains(where: { $0.uuid == uuid })
            }) {
                var service = gattServices[index]
                service.characteristics = service.characteristics.map { item in
                    guard item.uuid == uuid else { return item }
                    return GATTCharacteristicSnapshot(
                        uuid: item.uuid,
                        properties: item.properties,
                        valueByteCount: count ?? item.valueByteCount
                    )
                }
                gattServices[index] = service
            }
        }
        resumePending(error: error)
    }
}
#endif
