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
}
