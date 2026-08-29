// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Transport

/// Marker protocol for mutating GATT operations. The read-only probe does
/// not conform to this protocol (verified by tests).
public protocol CharacteristicMutating: Sendable {}

/// Device Information characteristics the probe may display. Serial number
/// is allowlisted for the transport read path but is never requested or shown.
public enum ProbeDisplayCharacteristic: Sendable {
    public static let all: [UUID] = [
        DocumentedReadableCharacteristic.manufacturerName,
        DocumentedReadableCharacteristic.modelNumber,
        DocumentedReadableCharacteristic.hardwareRevision,
        DocumentedReadableCharacteristic.firmwareRevision,
        DocumentedReadableCharacteristic.softwareRevision,
    ]
}

/// Read-only diagnostic session. Disabled by default. Supports scan, connect,
/// discover, and read of documented-readable characteristics only.
public struct ReadOnlyDiagnosticProbe: Sendable {
    public let isEnabled: Bool
    private let session: GS3TransportSession
    private let runtime: any BluetoothRuntime

    public init(isEnabled: Bool = false, runtime: any BluetoothRuntime) {
        self.isEnabled = isEnabled
        self.runtime = runtime
        self.session = GS3TransportSession(runtime: runtime)
    }

    public func scan() async throws {
        try requireEnabled()
        try await session.handle(.startScan)
    }

    public func connect(peripheralID: UUID) async throws {
        try requireEnabled()
        try await session.handle(.connect(peripheralID: peripheralID))
    }

    public func noteConnected() async throws {
        try requireEnabled()
        try await session.handle(.connected)
    }

    public func noteServicesDiscovered() async throws {
        try requireEnabled()
        try await session.handle(.servicesDiscovered)
    }

    public func noteCharacteristicsDiscovered() async throws {
        try requireEnabled()
        try await session.handle(.characteristicsDiscovered)
    }

    public func noteSubscribed() async throws {
        try requireEnabled()
        try await session.handle(.subscribed)
    }

    public func readDocumentedCharacteristic(_ uuid: UUID) async throws {
        try requireEnabled()
        guard DocumentedReadableCharacteristic.isAllowlisted(uuid) else {
            throw TransportError.mutatingOperationRefused
        }
        if uuid == DocumentedReadableCharacteristic.serialNumber {
            throw TransportError.mutatingOperationRefused
        }
        try await session.readDocumentedCharacteristic(uuid)
        try await session.handle(.readComplete(characteristic: uuid, byteCount: 0))
    }

    /// Scan → connect → DIS discovery → allowlisted reads except serial.
    public func connectAndReadDeviceInformation(peripheralID: UUID) async throws -> DeviceInformationSnapshot {
        try requireEnabled()
        try await connect(peripheralID: peripheralID)
        try await noteConnected()
        try await noteServicesDiscovered()
        try await noteCharacteristicsDiscovered()
        try await noteSubscribed()
        for uuid in ProbeDisplayCharacteristic.all {
            try await readDocumentedCharacteristic(uuid)
        }
        return DeviceInformationSnapshot.omittingSerial(from: documentedTexts())
    }

    public func disconnect() async throws {
        try await session.handle(.disconnect)
    }

    public var state: TransportState {
        session.state
    }

    public var discoveredAdvertisements: [AdvertisementSnapshot] {
        runtime.discoveredAdvertisements
    }

    public func documentedTexts() -> [UUID: String] {
        var texts: [UUID: String] = [:]
        for uuid in ProbeDisplayCharacteristic.all {
            if let value = runtime.documentedReadableText(for: uuid) {
                texts[uuid] = value
            }
        }
        return texts
    }

    private func requireEnabled() throws {
        if !isEnabled {
            throw TransportError.probeDisabled
        }
    }
}
