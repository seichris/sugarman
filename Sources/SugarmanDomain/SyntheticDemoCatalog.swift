// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Simulator-only demo states. Fixtures are synthetic and must never be
/// presented as a real GS3 sensor.
public enum SyntheticDemoScenario: String, Sendable, CaseIterable, Identifiable, Codable, Equatable {
    case current
    case stale
    case disconnected
    case warmUp
    case sensorError
    case expired
    case connectedNoData
    case questionableSample

    public var id: String { rawValue }

    public var decoderRevision: String { SyntheticDemoCatalog.decoderRevision }
}

public struct SyntheticDemoFixture: Sendable, Equatable {
    public var scenario: SyntheticDemoScenario
    public var session: SensorSession
    public var samples: [GlucoseSample]
    public var workouts: [WorkoutContext]
    public var identity: SensorIdentity
    public var connection: ConnectionState
    public var lifecycle: SensorLifecycleState
}

public enum SyntheticDemoCatalog: Sendable {
    public static let decoderRevision = "synthetic-demo"
    public static let productName = "Synthetic demo sensor"

    public static func make(
        _ scenario: SyntheticDemoScenario,
        now: Date = Date(),
        sessionID: UUID = UUID(),
        sensorID: UUID = UUID()
    ) -> SyntheticDemoFixture {
        let identity = SensorIdentity(
            id: sensorID,
            productName: productName,
            sku: nil,
            gtin: nil,
            redactedSerial: "…DEMO",
            protocolVariant: .unknown,
            classificationEvidenceRevision: decoderRevision
        )

        let connection: ConnectionState
        let lifecycle: SensorLifecycleState
        let endedAt: Date?
        let warmUpEndsAt: Date?
        let sampleAge: TimeInterval
        let includeSamples: Bool

        switch scenario {
        case .current, .questionableSample:
            connection = .subscribed
            lifecycle = .live
            endedAt = nil
            warmUpEndsAt = now.addingTimeInterval(-3600)
            sampleAge = 45
            includeSamples = true
        case .stale:
            connection = .subscribed
            lifecycle = .live
            endedAt = nil
            warmUpEndsAt = now.addingTimeInterval(-3600)
            sampleAge = 20 * 60
            includeSamples = true
        case .disconnected:
            connection = .disconnected
            lifecycle = .live
            endedAt = nil
            warmUpEndsAt = now.addingTimeInterval(-3600)
            sampleAge = 90
            includeSamples = true
        case .warmUp:
            connection = .subscribed
            lifecycle = .warmUp
            endedAt = nil
            warmUpEndsAt = now.addingTimeInterval(1800)
            sampleAge = 30
            includeSamples = true
        case .sensorError:
            connection = .subscribed
            lifecycle = .error
            endedAt = nil
            warmUpEndsAt = now.addingTimeInterval(-3600)
            sampleAge = 40
            includeSamples = true
        case .expired:
            connection = .subscribed
            lifecycle = .expired
            endedAt = now.addingTimeInterval(-60)
            warmUpEndsAt = now.addingTimeInterval(-14 * 24 * 3600)
            sampleAge = 120
            includeSamples = true
        case .connectedNoData:
            connection = .subscribed
            lifecycle = .live
            endedAt = nil
            warmUpEndsAt = now.addingTimeInterval(-3600)
            sampleAge = 0
            includeSamples = false
        }

        let session = SensorSession(
            id: sessionID,
            sensorID: sensorID,
            activatedAt: now.addingTimeInterval(-6 * 3600),
            warmUpEndsAt: warmUpEndsAt,
            expectedEndsAt: now.addingTimeInterval(8 * 24 * 3600),
            endedAt: endedAt,
            lastReceivedIndex: includeSamples ? 8 : nil,
            lastCommittedIndex: includeSamples ? 8 : nil,
            protocolVariant: .unknown,
            lifecycle: lifecycle,
            connection: connection,
            sensorErrorCode: scenario == .sensorError ? "synthetic-error" : nil
        )

        let samples: [GlucoseSample]
        if includeSamples {
            samples = makeSamples(
                sessionID: sessionID,
                now: now,
                latestAge: sampleAge,
                scenario: scenario
            )
        } else {
            samples = []
        }

        let workoutEnd = now.addingTimeInterval(-sampleAge)
        let workout = WorkoutContext(
            sessionID: sessionID,
            start: workoutEnd.addingTimeInterval(-45 * 60),
            end: workoutEnd,
            activityType: "run",
            summary: "Synthetic demo workout. Athlete insight only."
        )

        return SyntheticDemoFixture(
            scenario: scenario,
            session: session,
            samples: samples,
            workouts: [workout],
            identity: identity,
            connection: connection,
            lifecycle: lifecycle
        )
    }

    private static func makeSamples(
        sessionID: UUID,
        now: Date,
        latestAge: TimeInterval,
        scenario: SyntheticDemoScenario
    ) -> [GlucoseSample] {
        let values = [92, 98, 104, 110, 108, 102, 99, 105]
        let trends: [GlucoseTrend] = [
            .stable, .rising, .rising, .stable, .falling, .falling, .stable, .stable,
        ]
        return values.enumerated().map { offset, mgdl in
            let index = UInt32(offset + 1)
            let age = latestAge + Double(values.count - 1 - offset) * 5 * 60
            let timestamp = now.addingTimeInterval(-age)
            let source: SampleSource = offset < 3 ? .backfill : .live
            let isLatest = offset == values.count - 1
            let quality: SampleQuality
            switch scenario {
            case .sensorError:
                quality = .error
            case .questionableSample where isLatest:
                quality = .questionable
            default:
                quality = .ok
            }
            return GlucoseSample(
                sessionID: sessionID,
                sensorIndex: index,
                sensorTimestamp: timestamp,
                receiptTimestamp: timestamp.addingTimeInterval(2),
                milligramsPerDeciliter: mgdl,
                originalTenthsMillimolesPerLiter: Int((Double(mgdl) / 18.0 * 10.0).rounded()),
                trend: trends[offset],
                quality: quality,
                source: source,
                decoderRevision: decoderRevision
            )
        }
    }
}
