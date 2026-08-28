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

public struct GlucoseExportDocument: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var unit: String
    public var timeZone: String
    public var disclaimer: String
    public var samples: [GlucoseExportRow]
}

/// Versioned export without credentials, authentication material, frames,
/// account IDs, MAC-like identifiers, or full serials.
///
/// Small datasets (including empty and fewer than 50 rows) are exported in
/// full. This does not copy xDrip's modulus-based chunking, which dropped
/// remainder rows when `count % 50 == 0` was treated as a special case.
public struct VersionedDataExporter: DataExporting {
    public static let schemaVersion = 1
    public static let unit = "mg/dL"

    public init() {}

    public func exportJSON(samples: [GlucoseSample]) throws -> Data {
        try exportJSON(samples: samples, timeZone: .current)
    }

    public func exportCSV(samples: [GlucoseSample]) throws -> String {
        try exportCSV(samples: samples, timeZone: .current)
    }

    public func exportJSON(samples: [GlucoseSample], timeZone: TimeZone) throws -> Data {
        let document = makeDocument(samples: samples, timeZone: timeZone)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public func exportCSV(samples: [GlucoseSample], timeZone: TimeZone) throws -> String {
        let document = makeDocument(samples: samples, timeZone: timeZone)
        var lines = [
            "schemaVersion=\(document.schemaVersion)",
            "unit=\(document.unit)",
            "timeZone=\(document.timeZone)",
            "disclaimer=\(document.disclaimer)",
            "sessionID,sensorIndex,sensorTimestamp,receiptTimestamp,milligramsPerDeciliter,trend,quality,source,decoderRevision",
        ]
        for row in document.samples {
            lines.append(
                [
                    row.sessionID,
                    String(row.sensorIndex),
                    row.sensorTimestamp,
                    row.receiptTimestamp,
                    String(row.milligramsPerDeciliter),
                    row.trend,
                    row.quality,
                    row.source,
                    row.decoderRevision,
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n")
    }

    private func makeDocument(samples: [GlucoseSample], timeZone: TimeZone) -> GlucoseExportDocument {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
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
        return GlucoseExportDocument(
            schemaVersion: Self.schemaVersion,
            unit: Self.unit,
            timeZone: timeZone.identifier,
            disclaimer: ProductCopy.noDosing,
            samples: rows
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
