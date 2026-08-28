// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Optional HealthKit workout overlay. No automated fueling prescription.
public struct WorkoutContext: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var id: UUID
    public var healthKitWorkoutUUID: UUID?
    public var start: Date
    public var end: Date?
    public var activityType: String
    public var summary: String?

    public init(
        id: UUID = UUID(),
        healthKitWorkoutUUID: UUID? = nil,
        start: Date,
        end: Date? = nil,
        activityType: String,
        summary: String? = nil
    ) {
        self.id = id
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.start = start
        self.end = end
        self.activityType = activityType
        self.summary = summary
    }
}
