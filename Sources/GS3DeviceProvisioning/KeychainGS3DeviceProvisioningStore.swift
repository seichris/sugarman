// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Security

package protocol GS3DeviceProvisioningPersisting: Sendable {
    func load() throws -> Data?
    func replace(with data: Data) throws
    func delete() throws
}

/// Fixed storage scopes keep production and physical-test material isolated.
/// Callers cannot supply an arbitrary Keychain service or access group.
public enum GS3DeviceProvisioningScope: Sendable, Equatable {
    case production
    case deviceTest
}

/// Device-only Keychain storage for normalized sensor connection material.
///
/// The item is readable only while this device is unlocked, does not migrate
/// through backups, and is not shared with the developer Probe target. The
/// imported JSON document is never stored verbatim.
package struct KeychainGS3DeviceProvisioningStore:
    GS3DeviceProvisioningPersisting
{
    private static let account = "owned-already-active-sensor"

    private let service: String

    package init(scope: GS3DeviceProvisioningScope) {
        self.service = Self.service(for: scope)
    }

    package init(service: String) {
        self.service = service
    }

    package static func service(for scope: GS3DeviceProvisioningScope) -> String {
        #if os(macOS)
        switch scope {
        case .production:
            "app.sugarman.macos.gs3-v3-provisioning"
        case .deviceTest:
            "app.sugarman.macos.devicetest.gs3-v3-provisioning"
        }
        #else
        switch scope {
        case .production:
            "app.sugarman.ios.gs3-v3-provisioning"
        case .deviceTest:
            "app.sugarman.ios.devicetest.gs3-v3-provisioning"
        }
        #endif
    }

    package func load() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw GS3DeviceProvisioningError.keychain(status)
        }
        guard let data = result as? Data else {
            throw GS3DeviceProvisioningError.invalidStoredMaterial
        }
        return data
    }

    package func replace(with data: Data) throws {
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw GS3DeviceProvisioningError.keychain(updateStatus)
        }

        var add = baseQuery()
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GS3DeviceProvisioningError.keychain(addStatus)
        }
    }

    package func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GS3DeviceProvisioningError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}
