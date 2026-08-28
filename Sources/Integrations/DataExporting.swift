// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public protocol DataExporting: Sendable {
    func exportJSON(samples: [GlucoseSample]) throws -> Data
    func exportCSV(samples: [GlucoseSample]) throws -> String
}

/// Versioned export without credentials, authentication material, or frames.
public struct VersionedDataExporter: DataExporting {
    public static let schemaVersion = 1

    public init() {}

    public func exportJSON(samples: [GlucoseSample]) throws -> Data {
        let payload: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "unit": "mg/dL",
            "timeZone": TimeZone.current.identifier,
            "disclaimer": ProductCopy.noDosing,
            "samples": samples
                .sorted { $0.sensorIndex < $1.sensorIndex }
                .map { sample in
                    [
                        "sessionID": sample.sessionID.uuidString,
                        "sensorIndex": Int(sample.sensorIndex),
                        "sensorTimestamp": ISO8601DateFormatter().string(from: sample.sensorTimestamp),
                        "receiptTimestamp": ISO8601DateFormatter().string(from: sample.receiptTimestamp),
                        "mgdl": sample.milligramsPerDeciliter,
                        "source": sample.source.rawValue,
                        "decoderRevision": sample.decoderRevision,
                    ] as [String: Any]
                },
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    public func exportCSV(samples: [GlucoseSample]) throws -> String {
        var lines = [
            "schemaVersion=\(Self.schemaVersion)",
            "unit=mg/dL",
            "disclaimer=\(ProductCopy.noDosing)",
            "sessionID,sensorIndex,sensorTimestamp,receiptTimestamp,mgdl,source,decoderRevision",
        ]
        let formatter = ISO8601DateFormatter()
        for sample in samples.sorted(by: { $0.sensorIndex < $1.sensorIndex }) {
            lines.append(
                [
                    sample.sessionID.uuidString,
                    String(sample.sensorIndex),
                    formatter.string(from: sample.sensorTimestamp),
                    formatter.string(from: sample.receiptTimestamp),
                    String(sample.milligramsPerDeciliter),
                    sample.source.rawValue,
                    sample.decoderRevision,
                ].joined(separator: ",")
            )
        }
        return lines.joined(separator: "\n")
    }
}
