// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public enum GS3DeviceTestExternalOwnershipError: Error, Sendable, Equatable {
    case confirmationRequired
}

extension GS3DeviceTestExternalOwnershipError: LocalizedError {
    public var errorDescription: String? {
        "Confirm that every other phone, app, and process has released the owned sensor."
    }
}

/// Process-local confirmation for owners that cannot share the App Group lock,
/// such as an iPhone or Android device.
///
/// Confirmation is deliberately never persisted. The real controller and the
/// scan-only adapter still acquire the kernel-backed local process lease; this
/// gate adds a separate human boundary for cross-device exclusion.
public final class GS3DeviceTestExternalOwnershipGate: @unchecked Sendable {
    private let lock = NSLock()
    private var confirmed = false

    public init() {}

    public var isConfirmed: Bool {
        lock.withLock { confirmed }
    }

    public func confirmExclusiveAccess() {
        lock.withLock { confirmed = true }
    }

    public func revoke() {
        lock.withLock { confirmed = false }
    }

    public func requireConfirmation() throws {
        guard isConfirmed else {
            throw GS3DeviceTestExternalOwnershipError.confirmationRequired
        }
    }
}
