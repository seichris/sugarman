// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Security

package protocol GS3DeviceProvisioningPersisting: Sendable {
    func load() throws -> Data?
    func replace(with data: Data) throws
    func delete() throws
}

/// Device-only Keychain storage for normalized production-test material.
///
/// The item is readable only while this device is unlocked, does not migrate
/// through backups, and is not shared with the developer Probe target. The
/// imported JSON document is never stored verbatim.
package struct KeychainGS3DeviceProvisioningStore:
    GS3DeviceProvisioningPersisting
{
    #if os(macOS)
    package static let defaultService =
        "app.sugarman.macos.devicetest.gs3-v3-provisioning"
    #else
    package static let defaultService =
        "app.sugarman.ios.devicetest.gs3-v3-provisioning"
    #endif
    private static let account = "owned-already-active-sensor"

    private let service: String

    package init(service: String = defaultService) {
        self.service = service
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
