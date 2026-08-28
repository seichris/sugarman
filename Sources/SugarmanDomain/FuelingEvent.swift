// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// User-entered fueling log. Sugarman never prescribes carbohydrate or dose.
///
/// `sessionID` is optional: `nil` means the event is unscoped (not tied to a
/// sensor session). Session-scoped events are deleted with that session.
/// Unscoped events persist until `deleteFueling` or `deleteAll`.
public struct FuelingEvent: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var carbohydrateGrams: Double?
    public var label: String
    public var notes: String?
    public var sessionID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        carbohydrateGrams: Double? = nil,
        label: String,
        notes: String? = nil,
        sessionID: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.carbohydrateGrams = carbohydrateGrams
        self.label = label
        self.notes = notes
        self.sessionID = sessionID
    }
}
