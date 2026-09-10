// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// A quick-add choice for the local fueling log.
///
/// The carbohydrate values are editable starting points, not recommendations
/// or a dosing prescription. The selected label and amount are copied into a
/// `FuelingEvent` so later edits to this catalog cannot rewrite history.
public struct FuelingPreset: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let emoji: String
    public let carbohydrateGrams: Double?

    public init(
        id: String,
        label: String,
        emoji: String,
        carbohydrateGrams: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.carbohydrateGrams = carbohydrateGrams
    }

    /// The initial quick-add catalog. These are deliberately ordinary foods
    /// and drinks; Sugarman does not suggest when or how much to consume.
    public static let defaults: [FuelingPreset] = [
        FuelingPreset(
            id: "pocari-pouch-13g",
            label: "Pocari",
            emoji: "🥤",
            carbohydrateGrams: 13
        ),
        FuelingPreset(
            id: "energy-gel-25g",
            label: "Energy gel",
            emoji: "⚡️",
            carbohydrateGrams: 25
        ),
        FuelingPreset(
            id: "banana-27g",
            label: "Banana",
            emoji: "🍌",
            carbohydrateGrams: 27
        ),
        FuelingPreset(
            id: "rice-ball-40g",
            label: "Rice ball",
            emoji: "🍙",
            carbohydrateGrams: 40
        ),
        FuelingPreset(
            id: "energy-bar-40g",
            label: "Energy bar",
            emoji: "🍫",
            carbohydrateGrams: 40
        ),
        // Portion sizes vary; these choices leave the amount for the user.
        FuelingPreset(id: "apple", label: "Apple", emoji: "🍎"),
        FuelingPreset(id: "orange", label: "Orange", emoji: "🍊"),
        FuelingPreset(id: "sandwich", label: "Sandwich", emoji: "🥪"),
        FuelingPreset(id: "oatmeal", label: "Oatmeal", emoji: "🥣"),
        FuelingPreset(id: "pretzels", label: "Pretzels", emoji: "🥨"),
        FuelingPreset(id: "dried-fruit", label: "Dried fruit", emoji: "🍇"),
        FuelingPreset(id: "sports-drink", label: "Sports drink", emoji: "🧃"),
    ]

    public static let emojiChoices = [
        "🍽️", "🥤", "⚡️", "🍌", "🍙", "🍫", "💧", "☕️", "🥨",
        "🍎", "🍊", "🥪", "🥣", "🍇", "🧃"
    ]
}
