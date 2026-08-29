// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public struct SugarmanStoreBootstrap: Sendable {
    public var store: any SugarmanStoring
    public var loadError: String?
    public var usesSwiftData: Bool

    public init(store: any SugarmanStoring, loadError: String?, usesSwiftData: Bool) {
        self.store = store
        self.loadError = loadError
        self.usesSwiftData = usesSwiftData
    }
}

/// Constructs the app's `SugarmanStoring` implementation. Prefers on-disk
/// SwiftData when the OS supports it; falls back to the in-memory store.
public enum SugarmanStoreFactory: Sendable {
    public static func makePersistent() -> SugarmanStoreBootstrap {
        make(inMemory: false)
    }

    public static func make(inMemory: Bool) -> SugarmanStoreBootstrap {
        #if canImport(SwiftData)
        if #available(iOS 26, macOS 26, *) {
            do {
                let store = try SwiftDataSugarmanStore.make(inMemory: inMemory)
                return SugarmanStoreBootstrap(store: store, loadError: nil, usesSwiftData: true)
            } catch {
                return SugarmanStoreBootstrap(
                    store: InMemorySugarmanStore(),
                    loadError: error.localizedDescription,
                    usesSwiftData: false
                )
            }
        }
        #endif
        return SugarmanStoreBootstrap(
            store: InMemorySugarmanStore(),
            loadError: nil,
            usesSwiftData: false
        )
    }
}
