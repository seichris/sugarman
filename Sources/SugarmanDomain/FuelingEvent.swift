// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// User-entered fueling log. Sugarman never prescribes carbohydrate or dose.
public struct FuelingEvent: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var timestamp: Date
    public var carbohydrateGrams: Double?
    public var label: String
    public var notes: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        carbohydrateGrams: Double? = nil,
        label: String,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.carbohydrateGrams = carbohydrateGrams
        self.label = label
        self.notes = notes
    }
}
