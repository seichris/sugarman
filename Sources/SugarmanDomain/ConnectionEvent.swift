// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Operational connection log. No account IDs, MAC-like identifiers, packet
/// payloads, credentials, or exact glucose values.
public struct ConnectionEvent: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var state: ConnectionState
    public var reason: ConnectionReason
    public var durationSeconds: TimeInterval?
    public var appLifecycle: AppLifecycleState

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        state: ConnectionState,
        reason: ConnectionReason,
        durationSeconds: TimeInterval? = nil,
        appLifecycle: AppLifecycleState
    ) {
        self.id = id
        self.timestamp = timestamp
        self.state = state
        self.reason = reason
        self.durationSeconds = durationSeconds
        self.appLifecycle = appLifecycle
    }
}
