// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

extension GlucoseSample {
    /// Millimoles per litre. Prefers the original tenths-mmol field when the
    /// decoder stored it; otherwise divides milligrams per decilitre by 18.
    public func millimolesPerLiter() -> Double {
        if let tenths = originalTenthsMillimolesPerLiter {
            return Double(tenths) / 10.0
        }
        return Double(milligramsPerDeciliter) / 18.0
    }

    public func value(in unit: GlucoseUnit) -> Double {
        switch unit {
        case .milligramsPerDeciliter:
            return Double(milligramsPerDeciliter)
        case .millimolesPerLiter:
            return millimolesPerLiter()
        }
    }
}

extension GlucoseUnit {
    public var displaySymbol: String {
        switch self {
        case .milligramsPerDeciliter:
            return "mg/dL"
        case .millimolesPerLiter:
            return "mmol/L"
        }
    }

    public var alternate: GlucoseUnit {
        switch self {
        case .milligramsPerDeciliter:
            return .millimolesPerLiter
        case .millimolesPerLiter:
            return .milligramsPerDeciliter
        }
    }
}

/// A reusable history window for the Live glucose surface on iPhone and Mac.
public enum GlucoseHistoryRange: Int, Sendable, Codable, Equatable, CaseIterable, Identifiable {
    case threeHours = 3
    case sixHours = 6
    case twelveHours = 12
    case twentyFourHours = 24

    public var id: Int { rawValue }

    public var duration: TimeInterval {
        TimeInterval(rawValue * 60 * 60)
    }
}

/// Source-ordered samples inside one bounded Live-chart window.
public struct GlucoseTimeline: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var samples: [GlucoseSample]

    public init(
        samples: [GlucoseSample],
        endingAt end: Date,
        range: GlucoseHistoryRange
    ) {
        let start = end.addingTimeInterval(-range.duration)
        self.start = start
        self.end = end
        self.samples = samples
            .filter { sample in
                sample.sensorTimestamp >= start && sample.sensorTimestamp <= end
            }
            .sorted { left, right in
                if left.sensorTimestamp == right.sensorTimestamp {
                    return left.sensorIndex < right.sensorIndex
                }
                return left.sensorTimestamp < right.sensorTimestamp
            }
    }
}

/// Fixed cross-platform chart scale matching the product's mmol/L reference.
public struct GlucoseChartScale: Sendable, Equatable {
    public var domain: ClosedRange<Double>
    public var gridValues: [Double]
    public var tickValues: [Double]

    public init(unit: GlucoseUnit) {
        switch unit {
        case .millimolesPerLiter:
            domain = 0...15
            gridValues = stride(from: 0.0, through: 15.0, by: 1.0).map(\.self)
            tickValues = stride(from: 0.0, through: 15.0, by: 3.0).map(\.self)
        case .milligramsPerDeciliter:
            domain = 0...270
            gridValues = stride(from: 0.0, through: 270.0, by: 18.0).map(\.self)
            tickValues = stride(from: 0.0, through: 250.0, by: 50.0).map(\.self)
        }
    }
}
