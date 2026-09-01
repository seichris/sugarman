// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import SafetyEngine

struct SafetyEngineTests {
    let engine = SafetyEngine(policy: SafetyPolicy(staleAfterSeconds: 600))
    let sessionID = UUID()

    func sample(
        age: TimeInterval,
        mgdl: Int = 110,
        quality: SampleQuality = .ok,
        source: SampleSource = .live,
        receiptAge: TimeInterval? = nil
    ) -> GlucoseSample {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return GlucoseSample(
            sessionID: sessionID,
            sensorIndex: 1,
            sensorTimestamp: now.addingTimeInterval(-age),
            receiptTimestamp: now.addingTimeInterval(-(receiptAge ?? age)),
            milligramsPerDeciliter: mgdl,
            quality: quality,
            source: source,
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

    @Test func okQualityFreshSubscribedLiveIsCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 20, mgdl: 101, quality: .ok)
        )
        #expect(result.showsValueAsCurrent)
        if case .current(let mgdl, _) = result.presentation {
            #expect(mgdl == 101)
        } else {
            Issue.record("expected current presentation, got \(result.presentation)")
        }
    }

    @Test func errorQualityFreshSubscribedLiveIsNeverCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 15, mgdl: 180, quality: .error)
        )
        #expect(result.showsValueAsCurrent == false)
        #expect(result.presentation == .sensorError)
        #expect(result.notCurrentNotice == ProductCopy.notCurrentReading)
        if case .current = result.presentation {
            Issue.record("error quality must never present as current")
        }
    }

    @Test func questionableQualityFreshSubscribedLiveIsNeverCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 15, mgdl: 180, quality: .questionable)
        )
        #expect(result.showsValueAsCurrent == false)
        #expect(result.presentation == .questionable)
        #expect(result.notCurrentNotice == ProductCopy.questionableSample)
        #expect(result.unvalidatedGlucoseMgdl == 180)
        if case .current = result.presentation {
            Issue.record("questionable quality must never present as current")
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

    @Test func scanningIsNotCurrentOrConnected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .scanning,
            lifecycle: .live,
            latestSample: sample(age: 30, mgdl: 120)
        )
        #expect(result.isDisconnected)
        #expect(!result.showsValueAsCurrent)
    }

    @Test func sensorTimestampControlsStalenessEvenWhenReceiptIsFresh() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 1200, receiptAge: 5)
        )
        #expect(result.isStale)
        #expect(!result.showsValueAsCurrent)
    }

    @Test func backfillUnknownQualityAndFutureDatesAreNeverCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let backfill = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 10, source: .backfill)
        )
        let unknown = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: 10, quality: .unknown)
        )
        let future = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .live,
            latestSample: sample(age: -120)
        )
        #expect(backfill.presentation == .questionable)
        #expect(unknown.presentation == .questionable)
        #expect(future.presentation == .questionable)
        #expect(!backfill.showsValueAsCurrent)
        #expect(!unknown.showsValueAsCurrent)
        #expect(!future.showsValueAsCurrent)
        #expect(backfill.unvalidatedGlucoseMgdl == nil)
        #expect(unknown.unvalidatedGlucoseMgdl == nil)
        #expect(future.unvalidatedGlucoseMgdl == nil)
    }

    @Test func connectedAndUnknownLifecycleAreNeverCurrent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let connected = engine.evaluate(
            now: now,
            connection: .connected,
            lifecycle: .live,
            latestSample: sample(age: 10)
        )
        let unidentified = engine.evaluate(
            now: now,
            connection: .subscribed,
            lifecycle: .unknown,
            latestSample: sample(age: 10)
        )
        #expect(connected.presentation == .questionable)
        #expect(unidentified.presentation == .questionable)
        #expect(!connected.showsValueAsCurrent)
        #expect(!unidentified.showsValueAsCurrent)
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
