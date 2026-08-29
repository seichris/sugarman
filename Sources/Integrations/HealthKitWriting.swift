// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public enum IntegrationError: Error, Sendable, Equatable {
    case healthKitWritesDisabledUntilParity
    case exportEmpty
}

public protocol HealthKitGlucoseWriting: Sendable {
    /// Must not persist HealthKit samples until the decoder passes physical
    /// parity gates. The M0 adapter always throws.
    func persistValidatedGlucose(_ samples: [GlucoseSample]) async throws
}

public protocol HealthKitWorkoutReading: Sendable {
    func loadWorkouts() async throws -> [WorkoutContext]
}

/// M0 adapter. Does not write HealthKit samples.
public struct DisabledHealthKitWriter: HealthKitGlucoseWriting {
    public init() {}

    public func persistValidatedGlucose(_ samples: [GlucoseSample]) async throws {
        _ = samples
        throw IntegrationError.healthKitWritesDisabledUntilParity
    }
}

public struct DisabledHealthKitWorkoutReader: HealthKitWorkoutReading {
    public init() {}

    public func loadWorkouts() async throws -> [WorkoutContext] {
        []
    }
}
