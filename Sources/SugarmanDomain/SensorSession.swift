// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// One wear session for a sensor. Account binding is a reference only —
/// never credentials, tokens, or email hashes.
public struct SensorSession: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var sensorID: UUID
    public var activatedAt: Date?
    public var warmUpEndsAt: Date?
    public var expectedEndsAt: Date?
    public var endedAt: Date?
    public var ownerAccountReference: String?
    public var lastRequestedIndex: UInt32?
    public var lastReceivedIndex: UInt32?
    public var lastCommittedIndex: UInt32?
    public var protocolVariant: ProtocolVariant
    public var lifecycle: SensorLifecycleState
    public var connection: ConnectionState
    public var sensorErrorCode: String?

    public init(
        id: UUID = UUID(),
        sensorID: UUID,
        activatedAt: Date? = nil,
        warmUpEndsAt: Date? = nil,
        expectedEndsAt: Date? = nil,
        endedAt: Date? = nil,
        ownerAccountReference: String? = nil,
        lastRequestedIndex: UInt32? = nil,
        lastReceivedIndex: UInt32? = nil,
        lastCommittedIndex: UInt32? = nil,
        protocolVariant: ProtocolVariant = .unknown,
        lifecycle: SensorLifecycleState = .unknown,
        connection: ConnectionState = .disconnected,
        sensorErrorCode: String? = nil
    ) {
        self.id = id
        self.sensorID = sensorID
        self.activatedAt = activatedAt
        self.warmUpEndsAt = warmUpEndsAt
        self.expectedEndsAt = expectedEndsAt
        self.endedAt = endedAt
        self.ownerAccountReference = ownerAccountReference
        self.lastRequestedIndex = lastRequestedIndex
        self.lastReceivedIndex = lastReceivedIndex
        self.lastCommittedIndex = lastCommittedIndex
        self.protocolVariant = protocolVariant
        self.lifecycle = lifecycle
        self.connection = connection
        self.sensorErrorCode = sensorErrorCode
    }
}
