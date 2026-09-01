// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Selects the Live screen's primary content without coupling the decision to
/// SwiftUI. Synthetic fixtures remain visible for previews and host tests, but
/// a real session with no readings leads directly to sensor setup.
public enum LiveDashboardContentMode: Sendable, Equatable {
    case sensorOnboarding
    case readings

    public static func resolve(
        sampleCount: Int,
        isSyntheticDemo: Bool
    ) -> LiveDashboardContentMode {
        sampleCount > 0 || isSyntheticDemo ? .readings : .sensorOnboarding
    }
}
