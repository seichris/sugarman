// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct SafetyPolicy: Sendable, Equatable {
    public var staleAfterSeconds: TimeInterval
    public var futureToleranceSeconds: TimeInterval

    public init(
        staleAfterSeconds: TimeInterval = 11 * 60,
        futureToleranceSeconds: TimeInterval = 60
    ) {
        self.staleAfterSeconds = staleAfterSeconds
        self.futureToleranceSeconds = futureToleranceSeconds
    }
}

/// How the live UI may classify glucose. `.current` is the only case validated
/// as a current reading; `SafetyAssessment.unvalidatedGlucoseMgdl` may expose a
/// recent live value separately while preserving the warning state.
public enum ReadingPresentation: Sendable, Equatable {
    case empty
    case connectedNoData
    case disconnected(readingAgeSeconds: TimeInterval?)
    case stale(readingAgeSeconds: TimeInterval)
    case warmUp
    case sensorError
    case expired
    case questionable
    case current(mgdl: Int, readingAgeSeconds: TimeInterval)
}

public struct SafetyAssessment: Sendable, Equatable {
    public var presentation: ReadingPresentation
    public var readingAgeSeconds: TimeInterval?
    public var isStale: Bool
    public var isDisconnected: Bool
    public var noDosingNotice: String
    public var notCurrentNotice: String?
    public var unvalidatedGlucoseMgdl: Int?

    public var showsValueAsCurrent: Bool {
        if case .current = presentation { return true }
        return false
    }
}

public struct SafetyEngine: Sendable {
    public var policy: SafetyPolicy

    public init(policy: SafetyPolicy = SafetyPolicy()) {
        self.policy = policy
    }

    public func evaluate(
        now: Date,
        connection: ConnectionState,
        lifecycle: SensorLifecycleState,
        latestSample: GlucoseSample?
    ) -> SafetyAssessment {
        let sensorAge = latestSample.map { now.timeIntervalSince($0.sensorTimestamp) }
        let receiptAge = latestSample.map { now.timeIntervalSince($0.receiptTimestamp) }
        let age = latestSample.map { sample in
            max(0, max(now.timeIntervalSince(sample.sensorTimestamp), now.timeIntervalSince(sample.receiptTimestamp)))
        }
        let disconnected = isDisconnected(connection)
        let noDosing = ProductCopy.noDosing

        func assessment(
            _ presentation: ReadingPresentation,
            stale: Bool,
            notCurrent: String?,
            unvalidatedGlucoseMgdl: Int? = nil
        ) -> SafetyAssessment {
            SafetyAssessment(
                presentation: presentation,
                readingAgeSeconds: age,
                isStale: stale,
                isDisconnected: disconnected,
                noDosingNotice: noDosing,
                notCurrentNotice: notCurrent,
                unvalidatedGlucoseMgdl: unvalidatedGlucoseMgdl
            )
        }

        switch lifecycle {
        case .warmUp:
            return assessment(.warmUp, stale: false, notCurrent: ProductCopy.notCurrentReading)
        case .error:
            return assessment(.sensorError, stale: false, notCurrent: ProductCopy.notCurrentReading)
        case .expired, .ended:
            return assessment(.expired, stale: false, notCurrent: ProductCopy.notCurrentReading)
        case .unknown, .identified, .live:
            break
        }

        if disconnected {
            return assessment(
                .disconnected(readingAgeSeconds: age),
                stale: age.map { $0 >= policy.staleAfterSeconds } ?? false,
                notCurrent: ProductCopy.disconnected
            )
        }

        guard let latestSample, let age else {
            switch connection {
            case .connected, .subscribed:
                return assessment(
                    .connectedNoData,
                    stale: false,
                    notCurrent: ProductCopy.connectedNoData
                )
            default:
                return assessment(.empty, stale: false, notCurrent: ProductCopy.emptyDashboard)
            }
        }

        if age >= policy.staleAfterSeconds {
            return assessment(
                .stale(readingAgeSeconds: age),
                stale: true,
                notCurrent: ProductCopy.stale
            )
        }


        if sensorAge.map({ $0 < -policy.futureToleranceSeconds }) == true
            || receiptAge.map({ $0 < -policy.futureToleranceSeconds }) == true {
            return assessment(
                .questionable,
                stale: false,
                notCurrent: ProductCopy.questionableSample
            )
        }

        guard lifecycle == .live,
              connection == .subscribed,
              latestSample.source == .live else {
            return assessment(
                .questionable,
                stale: false,
                notCurrent: ProductCopy.questionableSample
            )
        }

        switch latestSample.quality {
        case .error:
            return assessment(
                .sensorError,
                stale: false,
                notCurrent: ProductCopy.notCurrentReading
            )
        case .questionable:
            return assessment(
                .questionable,
                stale: false,
                notCurrent: ProductCopy.questionableSample,
                unvalidatedGlucoseMgdl: latestSample.milligramsPerDeciliter
            )
        case .unknown:
            return assessment(
                .questionable,
                stale: false,
                notCurrent: ProductCopy.questionableSample
            )
        case .ok:
            break
        }

        return assessment(
            .current(mgdl: latestSample.milligramsPerDeciliter, readingAgeSeconds: age),
            stale: false,
            notCurrent: nil
        )
    }

    private func isDisconnected(_ connection: ConnectionState) -> Bool {
        switch connection {
        case .disconnected, .idle, .scanning, .connecting, .bluetoothUnavailable, .unauthorized:
            return true
        case .connected, .subscribed:
            return false
        }
    }
}
