// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public enum IntegrationError: Error, Sendable, Equatable {
    case healthKitWritesDisabledUntilParity
    case exportEmpty
}


/// Compile-time product guard. Glucose HealthKit writes stay off until
/// physical decoder parity. Do not flip this without P1/P2 and live-read
/// evidence.
public enum HealthKitWritePolicy: Sendable {
    public static let glucoseWritesEnabled = false
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
        guard HealthKitWritePolicy.glucoseWritesEnabled else {
            throw IntegrationError.healthKitWritesDisabledUntilParity
        }
        throw IntegrationError.healthKitWritesDisabledUntilParity
    }
}

public struct DisabledHealthKitWorkoutReader: HealthKitWorkoutReading {
    public init() {}

    public func loadWorkouts() async throws -> [WorkoutContext] {
        []
    }
}
