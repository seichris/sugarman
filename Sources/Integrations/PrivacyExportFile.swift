// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Writes privacy-export JSON/CSV to UTF-8 files for `ShareLink`.
/// Filenames stay stable (`sugarman-export-utc.json` / `.csv`) and never
/// include account IDs, frames, or full serials.
public struct PrivacyExportFileWriter: Sendable {
    public static let jsonFilename = "sugarman-export-utc.json"
    public static let csvFilename = "sugarman-export-utc.csv"

    public init() {}

    public func writeJSON(_ data: Data, to directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(Self.jsonFilename)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func writeCSV(_ text: String, to directory: URL) throws -> URL {
        guard let data = text.data(using: .utf8) else {
            throw IntegrationError.exportEmpty
        }
        let url = directory.appendingPathComponent(Self.csvFilename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
