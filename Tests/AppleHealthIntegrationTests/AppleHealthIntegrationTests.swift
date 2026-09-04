// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import AppleHealthIntegration
import Foundation
import SugarmanDomain
import SugarmanStore
import Testing

@Suite("Apple Health glucose integration")
struct AppleHealthIntegrationTests {
    @Test("production opens only for the physically confirmed GS3 decoder")
    func productionGateAndIdentifier() throws {
        let revision = "owned-mainland-gs3-v3-glucose-source-map-2026-08-30"
        let policy = AppleHealthValidationPolicy.production(
            physicallyValidatedGS3DecoderRevision: revision
        )
        let sample = makeSample(
            index: 7,
            quality: .questionable,
            decoderRevision: revision
        )
        #expect(policy.isGateOpen)
        #expect(
            AppleHealthGlucosePayload.syncIdentifier(for: sample.id)
                == "app.sugarman.glucose.v1:11111111-2222-3333-4444-555555555555:7"
        )
        _ = try policy.payload(
            for: sample,
            earliestPermittedDate: .distantPast,
            now: Date(timeIntervalSince1970: 2_000)
        )
        #expect(throws: AppleHealthEligibilityError.decoderNotAllowed) {
            try policy.payload(
                for: makeSample(index: 8, decoderRevision: "unreviewed"),
                earliestPermittedDate: .distantPast,
                now: Date(timeIntervalSince1970: 2_000)
            )
        }
        #expect(throws: AppleHealthEligibilityError.qualityNotValidated) {
            try policy.payload(
                for: makeSample(
                    index: 9,
                    quality: .error,
                    decoderRevision: revision
                ),
                earliestPermittedDate: .distantPast,
                now: Date(timeIntervalSince1970: 2_000)
            )
        }
        #expect(AppleHealthValidationPolicy.closed.isGateOpen == false)
        #expect(
            AppleHealthValidationPolicy.production(
                physicallyValidatedGS3DecoderRevision: "synthetic-demo"
            ).isGateOpen == false
        )
    }

    @Test("opt-in drains complete local history in bounded batches")
    func drainsHistoryInBatches() async throws {
        let store = InMemorySugarmanStore()
        for index in 0..<205 {
            try await store.insertSample(makeSample(index: UInt32(index)))
        }
        let writer = RecordingWriter()
        let coordinator = AppleHealthGlucoseSyncCoordinator(
            store: store,
            writer: writer,
            policy: AppleHealthValidationPolicy(
                allowedDecoderRevisions: ["validated-v1"]
            ),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let result = await coordinator.drain(isEnabled: true)

        #expect(result.phase == .idle)
        #expect(result.summary.syncedCount == 205)
        #expect(result.summary.pendingCount == 0)
        #expect(await writer.savedBatchSizes() == [100, 100, 5])
    }

    @Test("unvalidated samples are blocked before reaching HealthKit")
    func blocksIneligibleSamples() async throws {
        let store = InMemorySugarmanStore()
        try await store.insertSample(
            GlucoseSample(
                sessionID: Self.sessionID,
                sensorIndex: 1,
                sensorTimestamp: Date(timeIntervalSince1970: 1_000),
                receiptTimestamp: Date(timeIntervalSince1970: 1_000),
                milligramsPerDeciliter: 110,
                quality: .questionable,
                source: .live,
                decoderRevision: "validated-v1"
            )
        )
        let writer = RecordingWriter()
        let coordinator = AppleHealthGlucoseSyncCoordinator(
            store: store,
            writer: writer,
            policy: AppleHealthValidationPolicy(
                allowedDecoderRevisions: ["validated-v1"]
            ),
            now: { Date(timeIntervalSince1970: 2_000) }
        )

        let result = await coordinator.drain(isEnabled: true)

        #expect(result.summary.blockedCount == 1)
        #expect(await writer.savedBatchSizes().isEmpty)
    }

    private static let sessionID = UUID(
        uuidString: "11111111-2222-3333-4444-555555555555"
    )!

    private func makeSample(
        index: UInt32,
        quality: SampleQuality = .ok,
        decoderRevision: String = "validated-v1"
    ) -> GlucoseSample {
        GlucoseSample(
            sessionID: Self.sessionID,
            sensorIndex: index,
            sensorTimestamp: Date(timeIntervalSince1970: 1_000 + Double(index)),
            receiptTimestamp: Date(timeIntervalSince1970: 1_000 + Double(index)),
            milligramsPerDeciliter: 100 + Int(index % 30),
            quality: quality,
            source: index.isMultiple(of: 2) ? .live : .backfill,
            decoderRevision: decoderRevision
        )
    }
}

private actor RecordingWriter: AppleHealthGlucoseWritingClient {
    private var batches: [[AppleHealthGlucosePayload]] = []

    func authorizationState() async -> AppleHealthAuthorizationState { .authorized }
    func requestWriteAuthorization() async throws {}
    func earliestPermittedSampleDate() async throws -> Date { .distantPast }
    func save(_ payloads: [AppleHealthGlucosePayload]) async throws {
        batches.append(payloads)
    }
    func savedBatchSizes() -> [Int] { batches.map(\.count) }
}
