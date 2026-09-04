// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

/// Stores the user's no-workout chart reference independently from workout
/// plans. Invalid or partial persisted values fail closed to the app default.
public struct NoWorkoutGlucoseRangePreferences {
    public static let lowerMgdlKey = "app.sugarman.noWorkoutRange.lowerMgdl"
    public static let upperMgdlKey = "app.sugarman.noWorkoutRange.upperMgdl"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> GlucoseReferenceRange {
        guard let lower = userDefaults.object(forKey: Self.lowerMgdlKey) as? NSNumber,
              let upper = userDefaults.object(forKey: Self.upperMgdlKey) as? NSNumber else {
            return .healthyAdultDefault
        }
        let range = GlucoseReferenceRange(
            lowerMgdl: lower.intValue,
            upperMgdl: upper.intValue
        )
        return range.isValid ? range : .healthyAdultDefault
    }

    public func save(_ range: GlucoseReferenceRange) {
        guard range.isValid else { return }
        userDefaults.set(range.lowerMgdl, forKey: Self.lowerMgdlKey)
        userDefaults.set(range.upperMgdl, forKey: Self.upperMgdlKey)
    }

    public func reset() {
        userDefaults.removeObject(forKey: Self.lowerMgdlKey)
        userDefaults.removeObject(forKey: Self.upperMgdlKey)
    }
}
