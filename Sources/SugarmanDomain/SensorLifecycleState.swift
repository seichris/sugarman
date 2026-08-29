// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

public enum SensorLifecycleState: String, Sendable, Codable, Equatable, CaseIterable {
    case unknown
    case identified
    case warmUp
    case live
    case error
    case expired
    case ended
}
