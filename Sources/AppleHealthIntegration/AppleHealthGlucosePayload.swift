// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct AppleHealthGlucosePayload: Sendable, Equatable {
    public static let syncVersion = 1

    public let key: SampleKey
    public let milligramsPerDeciliter: Int
    public let timestamp: Date
    public let syncIdentifier: String
    let sample: GlucoseSample

    init(validatedSample sample: GlucoseSample) {
        self.key = sample.id
        self.milligramsPerDeciliter = sample.milligramsPerDeciliter
        self.timestamp = sample.sensorTimestamp
        self.syncIdentifier = Self.syncIdentifier(for: sample.id)
        self.sample = sample
    }

    public static func syncIdentifier(for key: SampleKey) -> String {
        "app.sugarman.glucose.v1:"
            + key.sessionID.uuidString.lowercased()
            + ":\(key.sensorIndex)"
    }
}

public enum AppleHealthEligibilityError: Error, Sendable, Equatable {
    case gateClosed
    case decoderNotAllowed
    case qualityNotValidated
    case invalidGlucose
    case beforeHealthKitWindow
    case futureTimestamp
}

public struct AppleHealthValidationPolicy: Sendable, Equatable {
    public let allowedDecoderRevisions: Set<String>
    public let physicallyValidatedQuestionableDecoderRevisions: Set<String>
    public let maximumFutureSkew: TimeInterval

    public init(
        allowedDecoderRevisions: Set<String>,
        physicallyValidatedQuestionableDecoderRevisions: Set<String> = [],
        maximumFutureSkew: TimeInterval = 5 * 60
    ) {
        self.allowedDecoderRevisions = allowedDecoderRevisions
        self.physicallyValidatedQuestionableDecoderRevisions =
            physicallyValidatedQuestionableDecoderRevisions
        self.maximumFutureSkew = maximumFutureSkew
    }

    public static let closed = AppleHealthValidationPolicy(
        allowedDecoderRevisions: []
    )

    /// Opens production only for the exact decoder revision whose glucose and
    /// timestamps the user compared against the official GS3 app. The explicit
    /// exception preserves the unresolved native-state quality classification
    /// instead of globally promoting every GS3 fingerprint to `.ok`.
    public static func production(
        physicallyValidatedGS3DecoderRevision revision: String
    ) -> AppleHealthValidationPolicy {
        guard !revision.isEmpty, revision != "synthetic-demo" else {
            return .closed
        }
        return AppleHealthValidationPolicy(
            allowedDecoderRevisions: [revision],
            physicallyValidatedQuestionableDecoderRevisions: [revision]
        )
    }

    public var isGateOpen: Bool { !allowedDecoderRevisions.isEmpty }

    public func payload(
        for sample: GlucoseSample,
        earliestPermittedDate: Date,
        now: Date
    ) throws -> AppleHealthGlucosePayload {
        guard isGateOpen else { throw AppleHealthEligibilityError.gateClosed }
        guard allowedDecoderRevisions.contains(sample.decoderRevision),
              sample.decoderRevision != "synthetic-demo" else {
            throw AppleHealthEligibilityError.decoderNotAllowed
        }
        let isQualityEligible = sample.quality == .ok
            || (
                sample.quality == .questionable
                    && physicallyValidatedQuestionableDecoderRevisions.contains(
                        sample.decoderRevision
                    )
            )
        guard isQualityEligible else {
            throw AppleHealthEligibilityError.qualityNotValidated
        }
        guard sample.milligramsPerDeciliter > 0 else {
            throw AppleHealthEligibilityError.invalidGlucose
        }
        guard sample.sensorTimestamp >= earliestPermittedDate else {
            throw AppleHealthEligibilityError.beforeHealthKitWindow
        }
        guard sample.sensorTimestamp <= now.addingTimeInterval(maximumFutureSkew) else {
            throw AppleHealthEligibilityError.futureTimestamp
        }
        return AppleHealthGlucosePayload(validatedSample: sample)
    }
}
