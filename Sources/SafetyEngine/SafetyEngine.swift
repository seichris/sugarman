// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

public struct SafetyPolicy: Sendable, Equatable {
    public var staleAfterSeconds: TimeInterval

    public init(staleAfterSeconds: TimeInterval = 11 * 60) {
        self.staleAfterSeconds = staleAfterSeconds
    }
}

/// How the live UI may present glucose. `.current` is the only case that may
/// display a milligram value as the live reading.
public enum ReadingPresentation: Sendable, Equatable {
    case empty
    case connectedNoData
    case disconnected(readingAgeSeconds: TimeInterval?)
    case stale(readingAgeSeconds: TimeInterval)
    case warmUp
    case sensorError
    case expired
    case current(mgdl: Int, readingAgeSeconds: TimeInterval)
}

public struct SafetyAssessment: Sendable, Equatable {
    public var presentation: ReadingPresentation
    public var readingAgeSeconds: TimeInterval?
    public var isStale: Bool
    public var isDisconnected: Bool
    public var noDosingNotice: String
    public var notCurrentNotice: String?

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
        let age = latestSample.map { now.timeIntervalSince($0.receiptTimestamp) }
        let disconnected = isDisconnected(connection)
        let noDosing = ProductCopy.noDosing

        func assessment(
            _ presentation: ReadingPresentation,
            stale: Bool,
            notCurrent: String?
        ) -> SafetyAssessment {
            SafetyAssessment(
                presentation: presentation,
                readingAgeSeconds: age,
                isStale: stale,
                isDisconnected: disconnected,
                noDosingNotice: noDosing,
                notCurrentNotice: notCurrent
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

        return assessment(
            .current(mgdl: latestSample.milligramsPerDeciliter, readingAgeSeconds: age),
            stale: false,
            notCurrent: nil
        )
    }

    private func isDisconnected(_ connection: ConnectionState) -> Bool {
        switch connection {
        case .disconnected, .idle, .bluetoothUnavailable, .unauthorized:
            return true
        case .scanning, .connecting, .connected, .subscribed:
            return false
        }
    }
}
