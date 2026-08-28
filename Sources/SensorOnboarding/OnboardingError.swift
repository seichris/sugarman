// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

public enum OnboardingError: Error, Sendable, Equatable {
    case emptyPayload
    case payloadTooLarge
    case unsupportedFormat(reason: String)
    case invalidEncoding
}

extension OnboardingError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .emptyPayload:
            return "Onboarding payload was empty."
        case .payloadTooLarge:
            return "Onboarding payload exceeded the bounded parser limit."
        case .unsupportedFormat(let reason):
            return "Unsupported onboarding format: \(reason)"
        case .invalidEncoding:
            return "Onboarding payload was not valid text."
        }
    }
}

public enum EvidenceConfidence: String, Sendable, Codable, Equatable {
    case high
    case medium
    case low
    case unsupported
}
