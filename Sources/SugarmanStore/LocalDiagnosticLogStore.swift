// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// The intentionally small set of categories that may be written to the
/// local diagnostic log. The log is for operational correlation, not a second
/// copy of the glucose database.
public enum LocalDiagnosticCategory: String, Codable, Sendable, Equatable {
    case app
    case sensor
    case storage
    case workout
    case fueling
    case export
    case probe
}

/// Allowlisted operational events for the local JSON Lines log.
public enum LocalDiagnosticEvent: String, Codable, Sendable, Equatable {
    case appLaunched
    case scenePhaseChanged
    case storeRefreshFailed
    case sensorConnectionChanged
    case sensorLifecycle
    case sensorSamplesCommitted
    case sensorFailure
    case sensorCommandAcknowledged
    case sensorNativeStateObserved
    case workoutPlanSelected
    case workoutPhaseSelected
    case workoutSelectionCleared
    case workoutPlanAdded
    case workoutPlanUpdated
    case workoutPlanDeleted
    case workoutPlanWriteFailed
    case workoutPlanDeleteFailed
    case workoutPlanCatalogApplied
    case fuelingAdded
    case fuelingDeleted
    case exportRequested
    case exportCompleted
    case exportFailed
    case probeAction
}

/// One privacy-safe JSON Lines record.
///
/// Callers provide only allowlisted event names and bounded attributes. Keys
/// and values are sanitized again here so a user-entered label or an error
/// accidentally passed by a future caller cannot create multiline JSON or an
/// unbounded diagnostic record.
public struct LocalDiagnosticLogEntry: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let timestamp: Date
    public let category: LocalDiagnosticCategory
    public let event: LocalDiagnosticEvent
    public let attributes: [String: String]

    public init(
        timestamp: Date = .now,
        category: LocalDiagnosticCategory,
        event: LocalDiagnosticEvent,
        attributes: [String: String] = [:]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.timestamp = timestamp
        self.category = category
        self.event = event

        var safeAttributes: [String: String] = [:]
        for key in attributes.keys.sorted().prefix(16) {
            let safeKey = Self.sanitizeKey(key)
            guard !safeKey.isEmpty else { continue }
            safeAttributes[safeKey] = Self.sanitizeValue(attributes[key] ?? "")
        }
        self.attributes = safeAttributes
    }

    private static func sanitizeKey(_ key: String) -> String {
        var result = ""
        result.reserveCapacity(min(key.count, 48))
        for scalar in key.unicodeScalars {
            let value = scalar.value
            if (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
                || scalar == "_"
                || scalar == "-"
                || scalar == "."
            {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
            if result.count >= 48 { break }
        }
        return result
    }

    private static func sanitizeValue(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(min(value.count, 160))
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 10, 13:
                result.append(" ")
            case 0..<32, 127:
                continue
            default:
                result.unicodeScalars.append(scalar)
            }
            if result.count >= 160 { break }
        }
        return result
    }
}

/// A cheap summary used by the Privacy screen without exposing log contents.
public struct LocalDiagnosticLogSummary: Sendable, Equatable {
    public let entryCount: Int
    public let byteCount: Int
    public let invalidLineCount: Int

    public init(entryCount: Int, byteCount: Int, invalidLineCount: Int = 0) {
        self.entryCount = max(0, entryCount)
        self.byteCount = max(0, byteCount)
        self.invalidLineCount = max(0, invalidLineCount)
    }
}

/// Local-only append-only diagnostics storage.
///
/// The file is deliberately outside SwiftData so it can be copied as one
/// small, human-readable artifact over a trusted USB developer connection.
/// It is still under the app's Application Support container and is deleted
/// by the app's all-local-data deletion flow.
@MainActor
public final class LocalDiagnosticLogStore {
    public static let filename = "diagnostics.jsonl"
    public static let relativePath =
        "Library/Application Support/Sugarman/diagnostics.jsonl"

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            self.fileURL = applicationSupport
                .appendingPathComponent("Sugarman", isDirectory: true)
                .appendingPathComponent(Self.filename, isDirectory: false)
        }
    }

    public var url: URL { fileURL }

    public func append(_ entry: LocalDiagnosticLogEntry) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        let encoder = Self.makeEncoder()
        var next = try readData()
        if !next.isEmpty, next.last != 10 {
            next.append(10)
        }
        next.append(contentsOf: try encoder.encode(entry))
        next.append(10)
        try next.write(to: fileURL, options: .atomic)
        try applyFileProtection()
    }

    public func readData() throws -> Data {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Data() }
        return try Data(contentsOf: fileURL)
    }

    public func summary() throws -> LocalDiagnosticLogSummary {
        let data = try readData()
        guard !data.isEmpty else {
            return LocalDiagnosticLogSummary(entryCount: 0, byteCount: 0)
        }

        let decoder = Self.makeDecoder()
        var entryCount = 0
        var invalidLineCount = 0
        for line in data.split(separator: 10, omittingEmptySubsequences: true) {
            do {
                _ = try decoder.decode(
                    LocalDiagnosticLogEntry.self,
                    from: Data(line)
                )
                entryCount += 1
            } catch {
                invalidLineCount += 1
            }
        }
        return LocalDiagnosticLogSummary(
            entryCount: entryCount,
            byteCount: data.count,
            invalidLineCount: invalidLineCount
        )
    }

    public func removeAll() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func applyFileProtection() throws {
#if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
#endif
    }
}
