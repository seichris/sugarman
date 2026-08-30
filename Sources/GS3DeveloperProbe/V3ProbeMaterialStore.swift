// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Security

public enum V3ProbeMaterialStoreError: Error, Sendable, Equatable {
    case keychain(OSStatus)
}

extension V3ProbeMaterialStoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .keychain(let status):
            return "Private probe Keychain operation failed with status \(status)."
        }
    }
}

/// Device-only Keychain storage for normalized probe material.
///
/// The item is available only while the device is unlocked and does not
/// migrate through backups. Imported JSON is never stored verbatim.
public actor KeychainV3ProbeMaterialStore {
    public static let defaultService = "app.sugarman.probe.gs3-v3-material"
    private static let account = "owned-already-active-sensor"

    private let service: String

    public init(service: String = defaultService) {
        self.service = service
    }

    public func containsMaterial() throws -> Bool {
        let status = SecItemCopyMatching(baseQuery(returnData: false) as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw V3ProbeMaterialStoreError.keychain(status)
        }
    }

    public func load() throws -> V3ProbeMaterial? {
        var query = baseQuery(returnData: true)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw V3ProbeMaterialStoreError.keychain(status)
        }
        guard let data = result as? Data else {
            throw V3ProbeMaterialError.invalidStoredMaterial
        }
        return try V3ProbeMaterial(storedData: data)
    }

    public func replace(with material: V3ProbeMaterial) throws {
        let data = material.encodedForStorage()
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(
            baseQuery(returnData: false) as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw V3ProbeMaterialStoreError.keychain(updateStatus)
        }

        var add = baseQuery(returnData: false)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw V3ProbeMaterialStoreError.keychain(addStatus)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery(returnData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw V3ProbeMaterialStoreError.keychain(status)
        }
    }

    private func baseQuery(returnData: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: returnData,
        ]
    }
}
