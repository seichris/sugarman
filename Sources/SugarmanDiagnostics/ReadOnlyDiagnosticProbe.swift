// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Transport

/// Marker protocol for mutating GATT operations. The read-only probe does
/// not conform to this protocol (verified by tests).
public protocol CharacteristicMutating: Sendable {}

/// Read-only diagnostic session. Disabled by default. Supports scan, connect,
/// discover, and read of documented-readable characteristics only.
public struct ReadOnlyDiagnosticProbe: Sendable {
    public var isEnabled: Bool
    private let session: GS3TransportSession

    public init(isEnabled: Bool = false, runtime: any BluetoothRuntime) {
        self.isEnabled = isEnabled
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
        try await session.readDocumentedCharacteristic(uuid)
    }

    public func disconnect() async throws {
        try await session.handle(.disconnect)
    }

    public var state: TransportState {
        session.state
    }

    private func requireEnabled() throws {
        if !isEnabled {
            throw TransportError.probeDisabled
        }
    }
}
