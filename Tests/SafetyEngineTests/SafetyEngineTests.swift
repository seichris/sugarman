// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import SafetyEngine

struct SafetyEngineTests {
    let engine = SafetyEngine(policy: SafetyPolicy(staleAfterSeconds: 600))
    let sessionID = UUID()

    func sample(age: TimeInterval, mgdl: Int = 110) -> GlucoseSample {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return GlucoseSample(
            sessionID: sessionID,
            sensorIndex: 1,
            sensorTimestamp: now.addingTimeInterval(-age),
            receiptTimestamp: now.addingTimeInterval(-age),
            milligramsPerDeciliter: mgdl,
            decoderRevision: "none"
        )
    }

    @Test func disconnectedNeverPresentsOldSampleAsCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .disconnected,
            lifecycle: .live,
            latestSample: sample(age: 30, mgdl: 180)
        )
        #expect(result.showsValueAsCurrent == false)
        #expect(result.isDisconnected)
        #expect(result.noDosingNotice == ProductCopy.noDosing)
        if case .disconnected = result.presentation {
            // expected
        } else {
            Issue.record("expected disconnected presentation, got \(result.presentation)")
        }
    }

    @Test func staleReadingIsNotCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 1200, mgdl: 180)
        )
        #expect(result.isStale)
        #expect(result.showsValueAsCurrent == false)
        if case .stale(let age) = result.presentation {
            #expect(age == 1200)
        } else {
            Issue.record("expected stale presentation, got \(result.presentation)")
        }
    }

    @Test func freshConnectedSampleIsCurrentWithAge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 60, mgdl: 95)
        )
        #expect(result.showsValueAsCurrent)
        #expect(result.isStale == false)
        if case .current(let mgdl, let age) = result.presentation {
            #expect(mgdl == 95)
            #expect(age == 60)
        } else {
            Issue.record("expected current presentation, got \(result.presentation)")
        }
    }

    @Test func warmUpIsNeverCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .warmUp,
            latestSample: sample(age: 10, mgdl: 70)
        )
        #expect(result.presentation == .warmUp)
        #expect(result.showsValueAsCurrent == false)
    }

    @Test func errorAndExpiryAreDistinctFromCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let error = engine.evaluate(
            now: now, connection: .subscribed, lifecycle: .error, latestSample: sample(age: 5)
        )
        let expired = engine.evaluate(
            now: now, connection: .subscribed, lifecycle: .expired, latestSample: sample(age: 5)
        )
        #expect(error.presentation == .sensorError)
        #expect(expired.presentation == .expired)
        #expect(error.showsValueAsCurrent == false)
        #expect(expired.showsValueAsCurrent == false)
    }

    @Test func emptyDisconnectedDashboard() {
        let result = engine.evaluate(
            now: Date(),
            connection: .disconnected,
            lifecycle: .unknown,
            latestSample: nil
        )
        #expect(result.showsValueAsCurrent == false)
        #expect(result.noDosingNotice.contains("dose insulin"))
    }

    @Test func scanningIsNotDisconnected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .scanning,
            lifecycle: .live,
            latestSample: sample(age: 30, mgdl: 120)
        )
        #expect(result.isDisconnected == false)
    }

    @Test func connectedWithNilSampleIsConnectedNoData() {
        let result = engine.evaluate(
            now: Date(),
            connection: .connected,
            lifecycle: .live,
            latestSample: nil
        )
        #expect(result.presentation == .connectedNoData)
        #expect(result.showsValueAsCurrent == false)
        #expect(result.isDisconnected == false)
        #expect(result.notCurrentNotice == ProductCopy.connectedNoData)
    }

    @Test func subscribedWithNilSampleIsConnectedNoData() {
        let result = engine.evaluate(
            now: Date(),
            connection: .subscribed,
            lifecycle: .live,
            latestSample: nil
        )
        #expect(result.presentation == .connectedNoData)
        #expect(result.showsValueAsCurrent == false)
    }

    @Test func disconnectedFreshSampleStillNotCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .disconnected,
            lifecycle: .live,
            latestSample: sample(age: 20, mgdl: 140)
        )
        #expect(result.showsValueAsCurrent == false)
        #expect(result.isDisconnected)
    }
}
