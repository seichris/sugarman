// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// The two strict private-document routes supported by the isolated Device Test
/// target. This type carries routing metadata only; it never contains file data
/// or private sensor material.
public enum GS3DeviceProvisioningFileImportKind: Sendable, Equatable {
    case managedProvisioning
    case existingProbe
}

/// Screen-owned file-import request. Keeping the selected redacted identity in
/// the request prevents a later view refresh from silently retargeting an
/// already-presented document picker.
public struct GS3DeviceProvisioningFileImportRequest: Sendable, Equatable {
    public let kind: GS3DeviceProvisioningFileImportKind
    public let linkedSensorID: UUID

    public init(
        kind: GS3DeviceProvisioningFileImportKind,
        linkedSensorID: UUID
    ) {
        self.kind = kind
        self.linkedSensorID = linkedSensorID
    }
}

/// Deterministic identity reconciliation for the Device Test picker. Stored
/// identities load asynchronously at app start, so a one-shot view task is not
/// sufficient to establish a selection.
public enum GS3DeviceProvisioningIdentitySelection {
    public static func resolve(
        current: UUID?,
        linked: UUID?,
        available: [UUID]
    ) -> UUID? {
        if let current, available.contains(current) {
            return current
        }
        if let linked, available.contains(linked) {
            return linked
        }
        return available.first
    }
}
