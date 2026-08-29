// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Stable uniqueness key: one sample per `(sessionID, sensorIndex)`.
public struct SampleKey: Sendable, Hashable, Codable, Equatable {
    public var sessionID: UUID
    public var sensorIndex: UInt32

    public init(sessionID: UUID, sensorIndex: UInt32) {
        self.sessionID = sessionID
        self.sensorIndex = sensorIndex
    }
}

public enum GlucoseTrend: String, Sendable, Codable, Equatable, CaseIterable {
    case unknown
    case fallingQuickly
    case falling
    case stable
    case rising
    case risingQuickly
}

public enum SampleQuality: String, Sendable, Codable, Equatable, CaseIterable {
    case unknown
    case ok
    case questionable
    case error
}

public enum SampleSource: String, Sendable, Codable, Equatable, CaseIterable {
    case live
    case backfill
}

/// Processed glucose. Must not carry raw authentication or packet bytes.
public struct GlucoseSample: Sendable, Equatable, Codable, Identifiable, Hashable {
    public var sessionID: UUID
    public var sensorIndex: UInt32
    public var sensorTimestamp: Date
    public var receiptTimestamp: Date
    public var milligramsPerDeciliter: Int
    public var originalTenthsMillimolesPerLiter: Int?
    public var trend: GlucoseTrend
    public var quality: SampleQuality
    public var source: SampleSource
    public var decoderRevision: String

    public var id: SampleKey {
        SampleKey(sessionID: sessionID, sensorIndex: sensorIndex)
    }

    public init(
        sessionID: UUID,
        sensorIndex: UInt32,
        sensorTimestamp: Date,
        receiptTimestamp: Date,
        milligramsPerDeciliter: Int,
        originalTenthsMillimolesPerLiter: Int? = nil,
        trend: GlucoseTrend = .unknown,
        quality: SampleQuality = .unknown,
        source: SampleSource = .live,
        decoderRevision: String
    ) {
        self.sessionID = sessionID
        self.sensorIndex = sensorIndex
        self.sensorTimestamp = sensorTimestamp
        self.receiptTimestamp = receiptTimestamp
        self.milligramsPerDeciliter = milligramsPerDeciliter
        self.originalTenthsMillimolesPerLiter = originalTenthsMillimolesPerLiter
        self.trend = trend
        self.quality = quality
        self.source = source
        self.decoderRevision = decoderRevision
    }
}

public enum GlucoseUnit: String, Sendable, Codable, Equatable, CaseIterable {
    case milligramsPerDeciliter
    case millimolesPerLiter
}
