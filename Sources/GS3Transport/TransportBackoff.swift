// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Pure exponential backoff with jitter. Testable without CoreBluetooth.
///
/// `unitJitter` is a deterministic draw in `[0, 1]`: `0` yields the low bound
/// and `1` yields the high bound. Values outside that range are clamped.
/// The returned delay is always in `[0, maximumSeconds]`.
public enum TransportBackoff: Sendable {
    public static let defaultBaseSeconds: TimeInterval = 0.25
    public static let defaultMaximumSeconds: TimeInterval = 8
    public static let defaultJitterFraction: Double = 0.2

    public static func delaySeconds(
        attempt: Int,
        baseSeconds: TimeInterval = defaultBaseSeconds,
        maximumSeconds: TimeInterval = defaultMaximumSeconds,
        jitterFraction: Double = defaultJitterFraction,
        unitJitter: Double
    ) -> TimeInterval {
        let attempt = max(0, attempt)
        let base = max(0, baseSeconds)
        let maximum = max(base, maximumSeconds)
        let fraction = min(1, max(0, jitterFraction))
        let unit = min(1, max(0, unitJitter))
        let exponential = min(maximum, base * pow(2.0, Double(attempt)))
        let low = max(0, exponential * (1 - fraction))
        let high = min(maximum, exponential * (1 + fraction))
        return low + (high - low) * unit
    }

    public static func randomUnitJitter() -> Double {
        Double.random(in: 0...1)
    }
}
