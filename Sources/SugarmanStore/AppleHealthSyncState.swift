// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public enum AppleHealthDeliveryState: String, Codable, Sendable, Equatable {
    case pending
    case synced
    case retryableFailure
    case blocked
}

public enum AppleHealthSyncFailureReason: String, Codable, Sendable, Equatable {
    case unavailable
    case notAuthorized
    case ineligible
    case healthKit
    case persistence
}

/// A local glucose sample together with privacy-safe delivery bookkeeping.
/// The value remains authoritative in `GlucoseSample`; no second payload copy
/// is persisted for Apple Health.
public struct AppleHealthSyncCandidate: Sendable, Equatable {
    public let sample: GlucoseSample
    public let attemptCount: Int

    public init(sample: GlucoseSample, attemptCount: Int) {
        self.sample = sample
        self.attemptCount = max(0, attemptCount)
    }
}

public struct AppleHealthSyncSummary: Sendable, Equatable {
    public let pendingCount: Int
    public let syncedCount: Int
    public let retryableFailureCount: Int
    public let blockedCount: Int
    public let lastAttemptAt: Date?
    public let lastSyncedAt: Date?

    public init(
        pendingCount: Int,
        syncedCount: Int,
        retryableFailureCount: Int,
        blockedCount: Int,
        lastAttemptAt: Date?,
        lastSyncedAt: Date?
    ) {
        self.pendingCount = max(0, pendingCount)
        self.syncedCount = max(0, syncedCount)
        self.retryableFailureCount = max(0, retryableFailureCount)
        self.blockedCount = max(0, blockedCount)
        self.lastAttemptAt = lastAttemptAt
        self.lastSyncedAt = lastSyncedAt
    }

    public static let empty = AppleHealthSyncSummary(
        pendingCount: 0,
        syncedCount: 0,
        retryableFailureCount: 0,
        blockedCount: 0,
        lastAttemptAt: nil,
        lastSyncedAt: nil
    )
}
