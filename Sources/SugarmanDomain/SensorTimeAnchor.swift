// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

public enum SensorTimeAnchorError: Error, Sendable, Equatable {
    case invalidSampleInterval
    case invalidMappingRevision
    case timestampOutOfRange
}

/// Stable mapping between one sensor-owned record index and wall-clock time.
///
/// The index remains available to persistence and mapping code, but diagnostic
/// representations deliberately omit both the index and timestamp. GS3's
/// current one-minute interval and its inference revision are persisted with
/// the anchor so a later policy change cannot silently retime an active
/// session.
public struct SensorTimeAnchor:
    Sendable, Equatable, Codable, Hashable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    private enum CodingKeys: String, CodingKey {
        case sensorIndex
        case timestamp
        case sampleIntervalSeconds
        case mappingRevision
    }

    public let sensorIndex: UInt32
    public let timestamp: Date
    public let sampleIntervalSeconds: TimeInterval
    public let mappingRevision: String

    public init(
        sensorIndex: UInt32,
        timestamp: Date,
        sampleIntervalSeconds: TimeInterval,
        mappingRevision: String
    ) throws {
        guard sampleIntervalSeconds.isFinite, sampleIntervalSeconds > 0 else {
            throw SensorTimeAnchorError.invalidSampleInterval
        }
        let revision = mappingRevision.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard mappingRevision == revision,
              !revision.isEmpty,
              revision.count <= 128 else {
            throw SensorTimeAnchorError.invalidMappingRevision
        }
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw SensorTimeAnchorError.timestampOutOfRange
        }
        self.sensorIndex = sensorIndex
        self.timestamp = timestamp
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.mappingRevision = revision
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sensorIndex: container.decode(UInt32.self, forKey: .sensorIndex),
            timestamp: container.decode(Date.self, forKey: .timestamp),
            sampleIntervalSeconds: container.decode(
                TimeInterval.self,
                forKey: .sampleIntervalSeconds
            ),
            mappingRevision: container.decode(
                String.self,
                forKey: .mappingRevision
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sensorIndex, forKey: .sensorIndex)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(
            sampleIntervalSeconds,
            forKey: .sampleIntervalSeconds
        )
        try container.encode(mappingRevision, forKey: .mappingRevision)
    }

    public func timestamp(for sensorIndex: UInt32) throws -> Date {
        let delta = Int64(sensorIndex) - Int64(self.sensorIndex)
        let seconds = TimeInterval(delta) * sampleIntervalSeconds
        guard seconds.isFinite else {
            throw SensorTimeAnchorError.timestampOutOfRange
        }
        let mapped = timestamp.addingTimeInterval(seconds)
        guard mapped.timeIntervalSinceReferenceDate.isFinite else {
            throw SensorTimeAnchorError.timestampOutOfRange
        }
        return mapped
    }

    public var description: String {
        "SensorTimeAnchor(index: redacted, timestamp: redacted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "sensorIndex": "redacted",
                "timestamp": "redacted",
                "sampleIntervalSeconds": "redacted",
                "mappingRevision": "redacted",
            ],
            displayStyle: .struct
        )
    }
}
