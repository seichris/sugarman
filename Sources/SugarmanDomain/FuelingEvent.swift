// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// User-entered fueling log. Sugarman never prescribes carbohydrate or dose.
///
/// `sessionID` is optional: `nil` means the event is unscoped (not tied to a
/// sensor session). Session-scoped events are deleted with that session.
/// Unscoped events persist until `deleteFueling` or `deleteAll`.
public struct FuelingEvent: Sendable, Equatable, Codable, Identifiable, Hashable {
    public static let defaultEmoji = "🍽️"

    public var id: UUID
    public var timestamp: Date
    public var carbohydrateGrams: Double?
    public var label: String
    public var emoji: String
    public var notes: String?
    public var sessionID: UUID?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        carbohydrateGrams: Double? = nil,
        label: String,
        notes: String? = nil,
        sessionID: UUID? = nil,
        emoji: String = FuelingEvent.defaultEmoji
    ) {
        self.id = id
        self.timestamp = timestamp
        self.carbohydrateGrams = carbohydrateGrams
        self.label = label
        self.emoji = emoji.isEmpty ? Self.defaultEmoji : emoji
        self.notes = notes
        self.sessionID = sessionID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case carbohydrateGrams
        case label
        case emoji
        case notes
        case sessionID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.carbohydrateGrams = try container.decodeIfPresent(
            Double.self,
            forKey: .carbohydrateGrams
        )
        self.label = try container.decode(String.self, forKey: .label)
        let decodedEmoji = try container.decodeIfPresent(String.self, forKey: .emoji)
            ?? Self.defaultEmoji
        self.emoji = decodedEmoji.isEmpty ? Self.defaultEmoji : decodedEmoji
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
    }
}
