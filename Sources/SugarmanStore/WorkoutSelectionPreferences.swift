// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public struct StoredWorkoutSelection: Sendable, Equatable {
    public var planID: UUID?
    public var phaseID: UUID?

    public init(planID: UUID?, phaseID: UUID?) {
        self.planID = planID
        self.phaseID = phaseID
    }
}

/// Persists the currently presented workout target independently from the
/// workout plan catalog so it can be restored after an app relaunch.
public struct WorkoutSelectionPreferences {
    public static let selectedPlanKey = "app.sugarman.selectedWorkoutPlanID"
    public static let selectedPhaseKey = "app.sugarman.selectedWorkoutPhaseID"

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func load() -> StoredWorkoutSelection {
        StoredWorkoutSelection(
            planID: storedUUID(forKey: Self.selectedPlanKey),
            phaseID: storedUUID(forKey: Self.selectedPhaseKey)
        )
    }

    public func save(_ selection: StoredWorkoutSelection) {
        save(selection.planID, forKey: Self.selectedPlanKey)
        save(selection.phaseID, forKey: Self.selectedPhaseKey)
    }

    private func storedUUID(forKey key: String) -> UUID? {
        userDefaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    private func save(_ id: UUID?, forKey key: String) {
        if let id {
            userDefaults.set(id.uuidString, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
}
