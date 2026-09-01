// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Owns a writable copy of an imported private document so its bytes can be
/// cleared without attempting to mutate file-backed or read-only storage.
public final class PrivateDocumentImportBuffer {
    private let storage: NSMutableData

    public init(contentsOf url: URL) throws {
        storage = try NSMutableData(contentsOf: url, options: [])
    }

    /// Provides a non-owning view while this buffer keeps the mutable bytes alive.
    public func withData<Result>(_ body: (Data) throws -> Result) rethrows -> Result {
        try body(borrowedData)
    }

    /// Provides a non-owning view for the duration of an asynchronous import.
    public func withData<Result>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: (Data) async throws -> Result
    ) async rethrows -> Result {
        _ = isolation
        return try await body(borrowedData)
    }

    /// Best-effort clearing of the buffer. Calling this more than once is safe.
    public func zeroize() {
        guard storage.length > 0 else { return }
        storage.resetBytes(in: NSRange(location: 0, length: storage.length))
    }

    deinit {
        zeroize()
    }

    private var borrowedData: Data {
        guard storage.length > 0 else { return Data() }
        return Data(
            bytesNoCopy: storage.mutableBytes,
            count: storage.length,
            deallocator: .none
        )
    }
}
