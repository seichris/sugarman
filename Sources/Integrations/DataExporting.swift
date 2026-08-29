// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public protocol DataExporting: Sendable {
    func exportJSON(samples: [GlucoseSample], timeZone: TimeZone) throws -> Data
    func exportCSV(samples: [GlucoseSample], timeZone: TimeZone) throws -> String
}

public struct GlucoseExportRow: Sendable, Equatable, Codable {
    public var sessionID: String
    public var sensorIndex: UInt32
    public var sensorTimestamp: String
    public var receiptTimestamp: String
    public var milligramsPerDeciliter: Int
    public var trend: String
    public var quality: String
    public var source: String
    public var decoderRevision: String
}

public struct FuelingExportRow: Sendable, Equatable, Codable {
    public var id: String
    public var timestamp: String
    public var carbohydrateGrams: Double?
    public var label: String
    public var notes: String?
    public var sessionID: String?
}

public struct GlucoseExportDocument: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var unit: String
    public var timeZone: String
    public var disclaimer: String
    public var samples: [GlucoseExportRow]
    public var fueling: [FuelingExportRow]
}

/// RFC 4180 quoting. Every field is quoted; internal quotes are doubled.
public enum RFC4180CSV: Sendable {
    public static let utcTimeZoneIdentifier = "UTC"

    public static func quote(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func row(_ fields: [String]) -> String {
        fields.map(quote).joined(separator: ",")
    }

    public static func parseRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if inQuotes {
                if character == "\"" {
                    let next = line.index(after: index)
                    if next < line.endIndex, line[next] == "\"" {
                        current.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }

    public static func records(in csv: String) -> [[String]] {
        csv.split(separator: "\n", omittingEmptySubsequences: false)
            .map { parseRow(String($0)) }
            .filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}

/// Versioned export without credentials, authentication material, frames,
/// account IDs, MAC-like identifiers, or full serials.
///
/// Timestamps are always UTC (`Z`) and `timeZone` is always `"UTC"`, even if
/// the caller passes a local `TimeZone`. That keeps the declared zone
/// consistent with the formatted timestamps.
///
/// JSON schema version 2 adds an optional-looking `fueling` array. CSV remains
/// glucose rows only. Neither format includes owner account IDs.
///
/// Small datasets (including empty and fewer than 50 rows) are exported in
/// full. This does not copy xDrip modulus-based chunking, which dropped
/// remainder rows when `count % 50 == 0` was treated as a special case.
public struct VersionedDataExporter: DataExporting {
    public static let schemaVersion = 2
    public static let unit = "mg/dL"
    public static let timeZoneIdentifier = RFC4180CSV.utcTimeZoneIdentifier

    public init() {}

    public func exportJSON(samples: [GlucoseSample]) throws -> Data {
        try exportJSON(samples: samples, fueling: [], timeZone: .current)
    }

    public func exportCSV(samples: [GlucoseSample]) throws -> String {
        try exportCSV(samples: samples, timeZone: .current)
    }

    public func exportJSON(samples: [GlucoseSample], timeZone: TimeZone) throws -> Data {
        try exportJSON(samples: samples, fueling: [], timeZone: timeZone)
    }

    public func exportJSON(samples: [GlucoseSample], fueling: [FuelingEvent]) throws -> Data {
        try exportJSON(samples: samples, fueling: fueling, timeZone: .current)
    }

    public func exportJSON(
        samples: [GlucoseSample],
        fueling: [FuelingEvent],
        timeZone _: TimeZone
    ) throws -> Data {
        let document = makeDocument(samples: samples, fueling: fueling)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public func exportCSV(samples: [GlucoseSample], timeZone _: TimeZone) throws -> String {
        let document = makeDocument(samples: samples, fueling: [])
        var lines = [
            RFC4180CSV.row(["schemaVersion", "unit", "timeZone", "disclaimer"]),
            RFC4180CSV.row([
                String(document.schemaVersion),
                document.unit,
                document.timeZone,
                document.disclaimer,
            ]),
            "",
            RFC4180CSV.row([
                "sessionID",
                "sensorIndex",
                "sensorTimestamp",
                "receiptTimestamp",
                "milligramsPerDeciliter",
                "trend",
                "quality",
                "source",
                "decoderRevision",
            ]),
        ]
        for row in document.samples {
            lines.append(
                RFC4180CSV.row([
                    row.sessionID,
                    String(row.sensorIndex),
                    row.sensorTimestamp,
                    row.receiptTimestamp,
                    String(row.milligramsPerDeciliter),
                    row.trend,
                    row.quality,
                    row.source,
                    row.decoderRevision,
                ])
            )
        }
        return lines.joined(separator: "\n")
    }

    private func utcFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: Self.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private func makeDocument(samples: [GlucoseSample], fueling: [FuelingEvent]) -> GlucoseExportDocument {
        let formatter = utcFormatter()
        let rows = sorted(samples).map { sample in
            GlucoseExportRow(
                sessionID: sample.sessionID.uuidString,
                sensorIndex: sample.sensorIndex,
                sensorTimestamp: formatter.string(from: sample.sensorTimestamp),
                receiptTimestamp: formatter.string(from: sample.receiptTimestamp),
                milligramsPerDeciliter: sample.milligramsPerDeciliter,
                trend: sample.trend.rawValue,
                quality: sample.quality.rawValue,
                source: sample.source.rawValue,
                decoderRevision: sample.decoderRevision
            )
        }
        let fuelingRows = fueling.sorted { $0.timestamp < $1.timestamp }.map { event in
            FuelingExportRow(
                id: event.id.uuidString,
                timestamp: formatter.string(from: event.timestamp),
                carbohydrateGrams: event.carbohydrateGrams,
                label: event.label,
                notes: event.notes,
                sessionID: event.sessionID?.uuidString
            )
        }
        return GlucoseExportDocument(
            schemaVersion: Self.schemaVersion,
            unit: Self.unit,
            timeZone: Self.timeZoneIdentifier,
            disclaimer: ProductCopy.noDosing,
            samples: rows,
            fueling: fuelingRows
        )
    }

    private func sorted(_ samples: [GlucoseSample]) -> [GlucoseSample] {
        samples.sorted { lhs, rhs in
            if lhs.sessionID != rhs.sessionID {
                return lhs.sessionID.uuidString < rhs.sessionID.uuidString
            }
            return lhs.sensorIndex < rhs.sensorIndex
        }
    }
}
