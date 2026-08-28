// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public enum AlarmKind: String, Sendable, Codable, Equatable, CaseIterable {
    case staleReading
    case disconnected
    case missingReading
    case warmUp
    case sensorError
    case expired
}

public struct AlarmRule: Sendable, Equatable, Codable, Hashable {
    public var kind: AlarmKind
    public var staleAfterSeconds: TimeInterval

    public init(kind: AlarmKind, staleAfterSeconds: TimeInterval = 11 * 60) {
        self.kind = kind
        self.staleAfterSeconds = staleAfterSeconds
    }
}

/// Operational alarm record. Exact glucose values are omitted so logs cannot
/// be mistaken for a current reading.
public struct AlarmEvent: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var kind: AlarmKind
    public var reason: String
    public var durationSeconds: TimeInterval?
    public var appLifecycle: AppLifecycleState

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: AlarmKind,
        reason: String,
        durationSeconds: TimeInterval? = nil,
        appLifecycle: AppLifecycleState = .foreground
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.reason = reason
        self.durationSeconds = durationSeconds
        self.appLifecycle = appLifecycle
    }
}
