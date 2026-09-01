// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
@testable import PrivateDocumentImport
import Testing

@Suite("Private document import buffer")
struct PrivateDocumentImportBufferTests {
    @Test("owns readable storage and zeroizes the borrowed view")
    func ownsAndZeroizesStorage() throws {
        let expected = Data("synthetic-private-document".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try expected.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let buffer = try PrivateDocumentImportBuffer(contentsOf: url)
        try FileManager.default.removeItem(at: url)
        buffer.withData { borrowed in
            #expect(borrowed == expected)

            buffer.zeroize()
            buffer.zeroize()

            #expect(borrowed.count == expected.count)
            #expect(borrowed.allSatisfy { $0 == 0 })
        }
    }

    @Test("accepts and clears an empty document")
    func acceptsEmptyDocument() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let buffer = try PrivateDocumentImportBuffer(contentsOf: url)

        buffer.withData { borrowed in
            #expect(borrowed.isEmpty)
            buffer.zeroize()
            #expect(borrowed.isEmpty)
        }
    }

    @Test("keeps the borrowed bytes alive across an actor-inherited suspension")
    @MainActor
    func supportsActorInheritedAsyncImport() async throws {
        let expected = Data("synthetic-async-document".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try expected.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let buffer = try PrivateDocumentImportBuffer(contentsOf: url)
        await buffer.withData { borrowed in
            await Task.yield()
            #expect(borrowed == expected)
            buffer.zeroize()
            #expect(borrowed.allSatisfy { $0 == 0 })
        }
    }
}
