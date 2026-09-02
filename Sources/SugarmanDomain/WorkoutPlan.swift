// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// The point in a workout timeline for which an athlete records a target band.
/// These labels are guidance entered by the athlete, not medical instructions.
public enum WorkoutPhase: String, Sendable, Codable, Equatable, CaseIterable, Identifiable, Hashable {
    case preWorkout
    case duringWorkout
    case postWorkout
    case overnight

    public var id: String { rawValue }
}

/// A user-owned glucose band attached to one phase of a saved workout.
/// Values are stored canonically in mg/dL and converted for display only.
public struct WorkoutPhaseTarget: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var phase: WorkoutPhase
    public var label: String
    public var lowerMgdl: Int
    public var upperMgdl: Int
    /// Optional lower threshold to make a distinction such as “typically
    /// 90–150, stay above 80” visible without pretending it is the target band.
    public var floorMgdl: Int?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        phase: WorkoutPhase,
        label: String,
        lowerMgdl: Int,
        upperMgdl: Int,
        floorMgdl: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.phase = phase
        self.label = label
        self.lowerMgdl = lowerMgdl
        self.upperMgdl = upperMgdl
        self.floorMgdl = floorMgdl
        self.notes = notes
    }

    public var isValid: Bool {
        lowerMgdl > 0
            && upperMgdl >= lowerMgdl
            && (floorMgdl == nil || floorMgdl! > 0 && floorMgdl! <= lowerMgdl)
    }

    public func lowerValue(in unit: GlucoseUnit) -> Double {
        switch unit {
        case .milligramsPerDeciliter:
            Double(lowerMgdl)
        case .millimolesPerLiter:
            Double(lowerMgdl) / 18.0
        }
    }

    public func upperValue(in unit: GlucoseUnit) -> Double {
        switch unit {
        case .milligramsPerDeciliter:
            Double(upperMgdl)
        case .millimolesPerLiter:
            Double(upperMgdl) / 18.0
        }
    }

    public func floorValue(in unit: GlucoseUnit) -> Double? {
        guard let floorMgdl else { return nil }
        switch unit {
        case .milligramsPerDeciliter:
            return Double(floorMgdl)
        case .millimolesPerLiter:
            return Double(floorMgdl) / 18.0
        }
    }
}

/// A reusable workout definition. It is separate from `WorkoutContext`, which
/// represents a concrete HealthKit workout occurrence.
public struct WorkoutPlan: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var activityType: String
    public var phases: [WorkoutPhaseTarget]
    public var notes: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        activityType: String,
        phases: [WorkoutPhaseTarget],
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.activityType = activityType
        self.phases = phases
        self.notes = notes
        self.createdAt = createdAt
    }

    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !activityType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phases.isEmpty
            && phases.allSatisfy { $0.isValid }
    }
}

/// The two-day 150 km ride supplied in the initial Codex conversation. Keeping
/// it as ordinary domain data makes it editable and persistable like any plan
/// the athlete creates in the app.
public enum WorkoutPlanCatalog: Sendable {
    public static var twoDay150KmRide: [WorkoutPlan] {
        [dayOne150KmRide, dayTwo150KmRide]
    }

    public static let dayOne150KmRide = WorkoutPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000151")!,
        name: "150 km bike — Day 1",
        activityType: "Cycling",
        phases: [
            WorkoutPhaseTarget(
                phase: .preWorkout,
                label: "Day 1 start",
                lowerMgdl: 90,
                upperMgdl: 130,
                notes: "Same as a single day. 100 is good; 120 after breakfast is fine."
            ),
            WorkoutPhaseTarget(
                phase: .duringWorkout,
                label: "During either day",
                lowerMgdl: 90,
                upperMgdl: 150,
                floorMgdl: 80,
                notes: "Stay at least 80–90; typically 90–150. Start eating in the first 20 minutes. Day 2 can sag earlier if dinner or breakfast were light."
            ),
            WorkoutPhaseTarget(
                phase: .postWorkout,
                label: "Right after day 1",
                lowerMgdl: 100,
                upperMgdl: 160,
                notes: "This meal is for day 2, not celebration."
            ),
            WorkoutPhaseTarget(
                phase: .overnight,
                label: "Overnight after day 1",
                lowerMgdl: 80,
                upperMgdl: 110,
                notes: "High insulin sensitivity. 60 here is a problem — eat before bed or if you wake."
            ),
        ],
        notes: "Two-day 150 km cycling block. These are your saved reference ranges, not a prescription."
    )

    public static let dayTwo150KmRide = WorkoutPlan(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000152")!,
        name: "150 km bike — Day 2",
        activityType: "Cycling",
        phases: [
            WorkoutPhaseTarget(
                phase: .preWorkout,
                label: "Day 2 start",
                lowerMgdl: 90,
                upperMgdl: 130,
                notes: "If you wake around 80 and it rises with breakfast, go. If you wake at 70 and falling, eat more and wait."
            ),
            WorkoutPhaseTarget(
                phase: .duringWorkout,
                label: "During either day",
                lowerMgdl: 90,
                upperMgdl: 150,
                floorMgdl: 80,
                notes: "Stay at least 80–90; typically 90–150. Start eating in the first 20 minutes."
            ),
            WorkoutPhaseTarget(
                phase: .postWorkout,
                label: "After day 2",
                lowerMgdl: 100,
                upperMgdl: 160,
                notes: "Less urgent unless there is a day 3."
            ),
        ],
        notes: "Second day of the two-day 150 km cycling block. These are your saved reference ranges, not a prescription."
    )
}
