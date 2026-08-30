// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public enum TransportState: String, Sendable, Equatable, CaseIterable {
    case idle
    case scanning
    case connecting
    case discovering
    case subscribed
    case authenticating
    case binding
    case synchronizing
    case live
    case backoff
    case ended
}

public enum TransportInput: Sendable, Equatable {
    case startScan
    case advertisement(peripheralID: UUID)
    case connect(peripheralID: UUID)
    case connected
    case servicesDiscovered
    case characteristicsDiscovered
    case subscribed
    case readComplete(characteristic: UUID, byteCount: Int)
    case disconnect
    case timeout
    case cancel
    case bluetoothUnavailable
    case permissionDenied
    /// Policy-gated steps. M0 refuses them so the machine stays fail-closed.
    case requestAuthentication
    case requestBinding
}

public enum TransportEffect: Sendable, Equatable {
    case startScan
    case stopScan
    case connect(UUID)
    case cancelConnection(UUID)
    case discoverServices
    case discoverCharacteristics
    case subscribe
    case read(UUID)
    case waitBackoff
    case fail(TransportError)
}

public enum TransportError: Error, Sendable, Equatable, CustomStringConvertible {
    case bluetoothUnavailable
    case permissionDenied
    case commandInFlight
    case mutatingOperationRefused
    case authenticationUnimplemented
    case bindingUnimplemented
    case invalidTransition(from: TransportState)
    case probeDisabled
    case timeout
    case disconnected
    case characteristicUnavailable(UUID)

    public var description: String {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable."
        case .permissionDenied:
            return "Bluetooth permission was denied."
        case .commandInFlight:
            return "Only one in-flight command is allowed."
        case .mutatingOperationRefused:
            return "Mutating peripheral operations are refused."
        case .authenticationUnimplemented:
            return "Authentication is unimplemented until P1/P2."
        case .bindingUnimplemented:
            return "Binding is unimplemented until P1/P2."
        case .invalidTransition(let from):
            return "Invalid transport transition from \(from.rawValue)."
        case .probeDisabled:
            return "Read-only diagnostic probe is disabled."
        case .timeout:
            return "Transport timed out."
        case .disconnected:
            return "The Bluetooth peripheral disconnected."
        case .characteristicUnavailable(let uuid):
            return "Readable characteristic \(uuid.uuidString) is unavailable."
        }
    }
}
