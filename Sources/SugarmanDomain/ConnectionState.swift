// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

public enum ConnectionState: String, Sendable, Codable, Equatable, CaseIterable {
    case idle
    case scanning
    case connecting
    case connected
    case subscribed
    case disconnected
    case bluetoothUnavailable
    case unauthorized
}

public enum ConnectionReason: String, Sendable, Codable, Equatable {
    case userRequested
    case outOfRange
    case peripheralDisconnect
    case bluetoothPoweredOff
    case restoration
    case timeout
    case probeDisabled
    case unknown
}

public enum AppLifecycleState: String, Sendable, Codable, Equatable {
    case foreground
    case background
    case suspended
    case terminatedUnknown
}

/// User-visible progress for the one managed sensor connection.
///
/// This deliberately contains no peripheral identity, protocol bytes, sensor
/// values, or arbitrary error text. It is the single source of truth used by
/// the Live screen while a reading cannot yet be presented as current.
public enum SensorConnectionActivity: String, Sendable, Codable, Equatable, CaseIterable {
    case notConfigured
    case stopped
    case connecting
    case synchronizing
    case live
    case reconnecting
    case failed
}
