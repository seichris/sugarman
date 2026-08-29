// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Testable central abstraction. CoreBluetooth objects stay on the dedicated
/// serial queue in a later adapter; this surface never exposes a mutating
/// characteristic operation.
public protocol BluetoothRuntime: Sendable {
    func perform(_ effect: TransportEffect) async throws
}

public struct AdvertisementSnapshot: Sendable, Equatable {
    public var peripheralID: UUID
    public var name: String?
    public var serviceUUIDs: [UUID]
    public var rssi: Int?

    public init(peripheralID: UUID, name: String? = nil, serviceUUIDs: [UUID] = [], rssi: Int? = nil) {
        self.peripheralID = peripheralID
        self.name = name
        self.serviceUUIDs = serviceUUIDs
        self.rssi = rssi
    }
}

/// Bluetooth SIG Device Information service and commonly readable
/// characteristics. GS3-specific FF30/FF31/FF32 UUIDs are not treated as
/// documented-readable until P1 evidence exists.
public enum DocumentedReadableCharacteristic: Sendable {
    public static let deviceInformationService = bluetoothUUID(0x180A)
    public static let manufacturerName = bluetoothUUID(0x2A29)
    public static let modelNumber = bluetoothUUID(0x2A24)
    public static let serialNumber = bluetoothUUID(0x2A25)
    public static let hardwareRevision = bluetoothUUID(0x2A27)
    public static let firmwareRevision = bluetoothUUID(0x2A26)
    public static let softwareRevision = bluetoothUUID(0x2A28)

    public static let all: Set<UUID> = [
        manufacturerName,
        modelNumber,
        serialNumber,
        hardwareRevision,
        firmwareRevision,
        softwareRevision,
    ]

    public static func isAllowlisted(_ uuid: UUID) -> Bool {
        all.contains(uuid)
    }
}

public func bluetoothUUID(_ short: UInt16) -> UUID {
    // Bluetooth base UUID: 0000xxxx-0000-1000-8000-00805F9B34FB
    let hex = String(format: "%04X", short)
    return UUID(uuidString: "0000\(hex)-0000-1000-8000-00805F9B34FB")!
}

public struct RecordingBluetoothRuntime: BluetoothRuntime, Sendable {
    public final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [TransportEffect] = []
        public init() {}
        public var effects: [TransportEffect] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        func append(_ effect: TransportEffect) {
            lock.lock()
            storage.append(effect)
            lock.unlock()
        }
    }

    public let log: Log

    public init(log: Log = Log()) {
        self.log = log
    }

    public func perform(_ effect: TransportEffect) async throws {
        switch effect {
        case .fail(let error):
            log.append(effect)
            throw error
        default:
            log.append(effect)
        }
    }
}
