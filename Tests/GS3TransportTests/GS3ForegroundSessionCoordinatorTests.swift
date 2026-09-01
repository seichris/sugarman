// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Session
import SugarmanDomain
import SugarmanStore
import Testing
@testable import GS3Protocol
@testable import GS3Transport

private enum RecordedForegroundCommand: Sendable, Equatable {
    case connect
    case disconnect
    case discoverService
    case discoverCharacteristics
    case subscribe
    case authenticate
    case requestHistory(HistoryRequestSource)
}

private actor RecordingForegroundTransport: GS3ForegroundTransporting {
    private var handler: (@Sendable (GS3ForegroundTransportEvent) -> Void)?
    private var storage: [RecordedForegroundCommand] = []

    func installEventHandler(
        _ handler: @escaping @Sendable (GS3ForegroundTransportEvent) -> Void
    ) {
        self.handler = handler
    }

    func connectKnownPeripheral() {
        storage.append(.connect)
    }

    func ensureDisconnected() {
        storage.append(.disconnect)
    }

    func discoverGS3Service() {
        storage.append(.discoverService)
    }

    func discoverGS3Characteristics() {
        storage.append(.discoverCharacteristics)
    }

    func subscribeToGS3Notifications() {
        storage.append(.subscribe)
    }

    func authenticateConnection() {
        storage.append(.authenticate)
    }

    func requestEffectiveData(_ plan: HistoryRequestPlan) {
        storage.append(.requestHistory(plan.source))
    }

    func commands() -> [RecordedForegroundCommand] {
        storage
    }

    func emit(_ events: [GS3ForegroundTransportEvent]) {
        guard let handler else { return }
        for event in events {
            handler(event)
        }
    }
}

private final class RecordingLease: GS3SensorOwnerLeaseHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func release() {
        lock.lock()
        active = false
        lock.unlock()
    }
}

private final class RecordingOwnershipProvider:
    GS3SensorOwnershipProviding, @unchecked Sendable
{
    private let lock = NSLock()
    private var storage: [RecordingLease] = []

    func acquire() throws -> any GS3SensorOwnerLeaseHandle {
        let lease = RecordingLease()
        lock.lock()
        storage.append(lease)
        lock.unlock()
        return lease
    }

    var latestLease: RecordingLease? {
        lock.lock()
        defer { lock.unlock() }
        return storage.last
    }

    var acquisitionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}

private actor RecordingReconnectScheduler: GS3ReconnectScheduling {
    private var schedules: [UInt64: GS3ReconnectSchedule] = [:]
    private var actions: [UInt64: @Sendable () -> Void] = [:]

    func schedule(
        _ schedule: GS3ReconnectSchedule,
        action: @escaping @Sendable () -> Void
    ) {
        schedules[schedule.token] = schedule
        actions[schedule.token] = action
    }

    func cancel(token: UInt64) {
        schedules[token] = nil
        actions[token] = nil
    }

    func cancelAll() {
        schedules.removeAll()
        actions.removeAll()
    }

    func pending() -> [GS3ReconnectSchedule] {
        schedules.values.sorted { $0.token < $1.token }
    }

    func fire(token: UInt64) {
        let action = actions.removeValue(forKey: token)
        schedules[token] = nil
        action?()
    }
}

private final class ForegroundCallbackLog: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var connections: [ConnectionState] = []
    private(set) var events: [GS3LifecycleEvent] = []
    private(set) var commits: [GS3BatchCommitSummary] = []
    private(set) var acknowledgements: [GS3ForegroundCommandKind] = []
    private(set) var failures: [GS3ForegroundCoordinatorFailure] = []

    func callbacks() -> GS3ForegroundSessionCallbacks {
        GS3ForegroundSessionCallbacks(
            onConnection: { [weak self] value in self?.appendConnection(value) },
            onLifecycleEvent: { [weak self] value in self?.appendEvent(value) },
            onSamplesCommitted: { [weak self] value in self?.appendCommit(value) },
            onCommandAcknowledged: { [weak self] value in self?.appendAcknowledgement(value) },
            onFailure: { [weak self] value in self?.appendFailure(value) }
        )
    }

    func snapshot() -> (
        connections: [ConnectionState],
        events: [GS3LifecycleEvent],
        commits: [GS3BatchCommitSummary],
        acknowledgements: [GS3ForegroundCommandKind],
        failures: [GS3ForegroundCoordinatorFailure]
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (connections, events, commits, acknowledgements, failures)
    }

    private func appendConnection(_ value: ConnectionState) {
        lock.lock(); connections.append(value); lock.unlock()
    }

    private func appendEvent(_ value: GS3LifecycleEvent) {
        lock.lock(); events.append(value); lock.unlock()
    }

    private func appendCommit(_ value: GS3BatchCommitSummary) {
        lock.lock(); commits.append(value); lock.unlock()
    }

    private func appendAcknowledgement(_ value: GS3ForegroundCommandKind) {
        lock.lock(); acknowledgements.append(value); lock.unlock()
    }

    private func appendFailure(_ value: GS3ForegroundCoordinatorFailure) {
        lock.lock(); failures.append(value); lock.unlock()
    }
}

private struct ForegroundHarness {
    let sessionID: UUID
    let store: InMemorySugarmanStore
    let transport: RecordingForegroundTransport
    let ownership: RecordingOwnershipProvider
    let scheduler: RecordingReconnectScheduler
    let callbackLog: ForegroundCallbackLog
    let coordinator: GS3ForegroundSessionCoordinator

    static func make(
        sessionID: UUID = UUID(),
        captureStart: UInt32 = 100
    ) async throws -> ForegroundHarness {
        let store = InMemorySugarmanStore()
        try await store.insertSession(
            SensorSession(
                id: sessionID,
                sensorID: UUID(),
                protocolVariant: .v3AES,
                lifecycle: .live,
                connection: .disconnected
            )
        )
        let transport = RecordingForegroundTransport()
        let ownership = RecordingOwnershipProvider()
        let scheduler = RecordingReconnectScheduler()
        let callbackLog = ForegroundCallbackLog()
        let configuration = try GS3ForegroundSessionConfiguration(
            sessionID: sessionID,
            sessionOrdinal: 1,
            captureBackedStart: CaptureBackedHistoryStart(
                sensorIndex: captureStart
            )
        )
        let coordinator = GS3ForegroundSessionCoordinator(
            configuration: configuration,
            store: store,
            transport: transport,
            ownershipProvider: ownership,
            reconnectScheduler: scheduler,
            callbacks: callbackLog.callbacks(),
            monotonicNanoseconds: { 5_000_000_000 }
        )
        return ForegroundHarness(
            sessionID: sessionID,
            store: store,
            transport: transport,
            ownership: ownership,
            scheduler: scheduler,
            callbackLog: callbackLog,
            coordinator: coordinator
        )
    }

    func advanceToHistoryRequest() async throws {
        try await coordinator.start()
        await coordinator.receive(.connected)
        await coordinator.receive(.servicesDiscovered)
        await coordinator.receive(.characteristicsDiscovered)
        await coordinator.receive(.notificationSubscriptionEnabled)
        await coordinator.receive(.authenticationWriteAcknowledged)
        await coordinator.receive(.authenticationAccepted)
        await coordinator.receive(.historyWriteAcknowledged)
    }

    func advanceToLive(at date: Date = Date(timeIntervalSince1970: 1_800_000_000)) async throws {
        try await advanceToHistoryRequest()
        await coordinator.receive(.historyAcknowledged)
        await coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: [
                        syntheticRecord(index: 100, tenths: 90),
                        syntheticRecord(index: 101, tenths: 91),
                    ]
                ),
                receivedAt: date.addingTimeInterval(-1)
            )
        )
        await coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .liveNotification,
                    records: [syntheticRecord(index: 102, tenths: 92)]
                ),
                receivedAt: date
            )
        )
    }
}

private func syntheticRecord(index: UInt16, tenths: UInt16) -> V3GlucoseRecord {
    V3GlucoseRecord(
        index: index,
        reindex: index,
        rawTemperature: 1,
        rawDump: 2,
        rawCurrent: 3,
        rawDisplayGlucose: tenths,
        glucoseTenthsMillimolesPerLiter: tenths,
        trendCode: 2,
        presentCState: false,
        algorithmCState: 0,
        tState: 0,
        dState: 0,
        algorithmReserved: 0,
        rawCEVoltage: 4,
        rawREVoltage: 5
    )
}

private func syntheticTimeAnchor(
    index: UInt32,
    timestamp: Date
) throws -> SensorTimeAnchor {
    try SensorTimeAnchor(
        sensorIndex: index,
        timestamp: timestamp,
        sampleIntervalSeconds: GS3ForegroundSessionConfiguration
            .inferredSampleIntervalSeconds,
        mappingRevision: GS3ForegroundSessionConfiguration
            .inferredTimeMappingRevision
    )
}

struct GS3ForegroundSessionCoordinatorTests {
    @Test func concurrentStartsAcquireAndConnectExactlyOnce() async throws {
        let harness = try await ForegroundHarness.make()
        let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        try await harness.coordinator.start()
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var values: [Bool] = []
            for await value in group {
                values.append(value)
            }
            return values
        }

        #expect(outcomes.filter { $0 }.count == 1)
        #expect(harness.ownership.acquisitionCount == 1)
        #expect(await harness.transport.commands().filter { $0 == .connect }.count == 1)
    }

    @Test func transportHandlerPreservesSourceEventOrder() async throws {
        let harness = try await ForegroundHarness.make()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await harness.coordinator.start()

        await harness.transport.emit([
            .connected,
            .servicesDiscovered,
            .characteristicsDiscovered,
            .notificationSubscriptionEnabled,
            .authenticationAccepted,
            .historyWriteAcknowledged,
            .historyAcknowledged,
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .liveNotification,
                    records: [syntheticRecord(index: 100, tenths: 90)]
                ),
                receivedAt: now
            ),
        ])
        for _ in 0..<200 where await harness.coordinator.currentPhase() != .live {
            await Task.yield()
        }

        #expect(await harness.coordinator.currentPhase() == .live)
        #expect(harness.callbackLog.snapshot().failures.isEmpty)
        #expect(
            await harness.transport.commands() == [
                .connect,
                .discoverService,
                .discoverCharacteristics,
                .subscribe,
                .authenticate,
                .requestHistory(.captureBacked),
            ]
        )
    }

    @Test func startupPersistenceFailureIsTypedAndTouchesNoOwnerOrTransport() async throws {
        let transport = RecordingForegroundTransport()
        let ownership = RecordingOwnershipProvider()
        let callbackLog = ForegroundCallbackLog()
        let coordinator = GS3ForegroundSessionCoordinator(
            configuration: try GS3ForegroundSessionConfiguration(
                sessionID: UUID(),
                sessionOrdinal: 1,
                captureBackedStart: CaptureBackedHistoryStart(sensorIndex: 1)
            ),
            store: UnavailableSugarmanStore(),
            transport: transport,
            ownershipProvider: ownership,
            reconnectScheduler: RecordingReconnectScheduler(),
            callbacks: callbackLog.callbacks()
        )

        await #expect(throws: GS3ForegroundCoordinatorError.startFailed) {
            try await coordinator.start()
        }
        #expect(callbackLog.snapshot().failures == [.persistence])
        #expect(ownership.acquisitionCount == 0)
        #expect(await transport.commands().isEmpty)
    }

    @Test func actualDisconnectAtEveryObservableIntegrationPhaseKeepsOneOwnerAndOneReconnect() async throws {
        let phases: [GS3ForegroundPhase] = [
            .connecting,
            .discoveringServices,
            .discoveringCharacteristics,
            .subscribing,
            .authenticating,
            .requestingHistory,
            .synchronizing,
            .live,
        ]

        for target in phases {
            let harness = try await ForegroundHarness.make()
            try await advance(harness, to: target)
            #expect(await harness.coordinator.currentPhase() == target)

            await harness.coordinator.receive(.disconnected(.timeout))

            #expect(await harness.coordinator.currentPhase() == .backoff)
            #expect(harness.ownership.acquisitionCount == 1)
            #expect(harness.ownership.latestLease?.isActive == true)
            #expect(await harness.scheduler.pending().count == 1)
            #expect(
                try await harness.store.session(id: harness.sessionID)?.connection
                    == .disconnected
            )

            await harness.coordinator.foregroundEnded()
            #expect(await harness.coordinator.currentPhase() == .stopped)
            #expect(harness.ownership.latestLease?.isActive == false)
            #expect(await harness.scheduler.pending().isEmpty)
        }
    }

    @Test func typedCoordinatorRunsOwnedForegroundLifecycleAndCommitsOneAnchorTransaction() async throws {
        let harness = try await ForegroundHarness.make()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try await harness.advanceToLive(at: now)

        #expect(await harness.coordinator.currentPhase() == .live)
        #expect(harness.ownership.acquisitionCount == 1)
        #expect(harness.ownership.latestLease?.isActive == true)
        #expect(
            await harness.transport.commands() == [
                .connect,
                .discoverService,
                .discoverCharacteristics,
                .subscribe,
                .authenticate,
                .requestHistory(.captureBacked),
            ]
        )
        let session = try #require(await harness.store.session(id: harness.sessionID))
        #expect(session.connection == .subscribed)
        #expect(session.lastRequestedIndex == 100)
        #expect(session.lastCommittedIndex == 102)
        let expectedAnchor = try syntheticTimeAnchor(index: 102, timestamp: now)
        #expect(session.sensorTimeAnchor == expectedAnchor)

        let samples = try await harness.store.samples(sessionID: harness.sessionID)
        #expect(samples.map(\.sensorIndex) == [100, 101, 102])
        #expect(samples.map(\.sensorTimestamp) == [
            now.addingTimeInterval(-120),
            now.addingTimeInterval(-60),
            now,
        ])
        #expect(samples.map(\.source) == [.backfill, .backfill, .live])
        #expect(samples.last?.milligramsPerDeciliter == 166)
        #expect(samples.last?.trend == .stable)
        #expect(samples.last?.quality == .questionable)

        let callbacks = harness.callbackLog.snapshot()
        #expect(callbacks.acknowledgements == [.authentication, .effectiveData])
        #expect(callbacks.failures.isEmpty)
        #expect(callbacks.connections.last == .subscribed)

        await harness.coordinator.stop()
        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(harness.ownership.latestLease?.isActive == true)
        #expect(await harness.transport.commands().last == .disconnect)
        await harness.coordinator.receive(.transportDisconnected)
        #expect(await harness.coordinator.currentPhase() == .stopped)
        #expect(harness.ownership.latestLease?.isActive == false)
        #expect(try await harness.store.session(id: harness.sessionID)?.connection == .disconnected)
    }

    @Test func reconnectIsSingleFlightAndRepeatsTypedAuthAndDurableOverlap() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.advanceToLive()

        await harness.coordinator.receive(.disconnected(.timeout))
        #expect(await harness.coordinator.currentPhase() == .backoff)
        #expect(harness.ownership.latestLease?.isActive == true)
        let pending = await harness.scheduler.pending()
        #expect(pending.count == 1)
        #expect(pending.first?.attempt == 1)

        await harness.coordinator.receive(.disconnected(.timeout))
        #expect(await harness.scheduler.pending().count == 1)

        let token = try #require(pending.first?.token)
        await harness.scheduler.fire(token: token)
        for _ in 0..<100 where await harness.transport.commands().filter({ $0 == .connect }).count < 2 {
            await Task.yield()
        }
        #expect(await harness.transport.commands().filter({ $0 == .connect }).count == 2)

        await harness.coordinator.receive(.connected)
        await harness.coordinator.receive(.servicesDiscovered)
        await harness.coordinator.receive(.characteristicsDiscovered)
        await harness.coordinator.receive(.notificationSubscriptionEnabled)
        await harness.coordinator.receive(.authenticationAccepted)

        let commands = await harness.transport.commands()
        #expect(commands.filter({ $0 == .authenticate }).count == 2)
        #expect(commands.filter({ $0 == .requestHistory(.committedOverlap) }).count == 1)
        #expect(harness.ownership.acquisitionCount == 1)
    }

    @Test func outOfOrderBackoffEventCancelsReconnectAndReleasesOwner() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.advanceToLive()
        await harness.coordinator.receive(.disconnected(.timeout))
        #expect(await harness.coordinator.currentPhase() == .backoff)
        #expect(await harness.scheduler.pending().count == 1)

        await harness.coordinator.receive(.servicesDiscovered)

        #expect(await harness.coordinator.currentPhase() == .stopped)
        #expect(await harness.scheduler.pending().isEmpty)
        #expect(harness.ownership.latestLease?.isActive == false)
        #expect(harness.callbackLog.snapshot().failures.contains(.stateMachine))
    }

    @Test func durableGapPinsCursorThenInclusiveReconnectRepairsWithoutDuplicates() async throws {
        let anchorDate = Date(timeIntervalSince1970: 1_800_000_000)
        let anchor = try syntheticTimeAnchor(index: 102, timestamp: anchorDate)
        let harness = try await ForegroundHarness.make(captureStart: 100)
        try await harness.store.prepareHistoryRequest(
            sessionID: harness.sessionID,
            startingAt: 100
        )
        _ = try await harness.store.commitSamples(
            [
                mappedSample(sessionID: harness.sessionID, index: 100, tenths: 90, anchor: anchor),
                mappedSample(sessionID: harness.sessionID, index: 101, tenths: 91, anchor: anchor),
                mappedSample(sessionID: harness.sessionID, index: 102, tenths: 92, anchor: anchor),
            ],
            sessionID: harness.sessionID,
            establishingTimeAnchor: anchor
        )

        try await harness.advanceToHistoryRequest()
        await harness.coordinator.receive(.historyAcknowledged)
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: [syntheticRecord(index: 102, tenths: 92)]
                ),
                receivedAt: anchorDate
            )
        )
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: [syntheticRecord(index: 104, tenths: 94)]
                ),
                receivedAt: anchorDate
            )
        )
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .liveNotification,
                    records: [syntheticRecord(index: 105, tenths: 95)]
                ),
                receivedAt: anchorDate.addingTimeInterval(180)
            )
        )

        let gapped = try #require(await harness.store.session(id: harness.sessionID))
        #expect(gapped.lastCommittedIndex == 102)
        #expect(gapped.lastReceivedIndex == 105)

        await harness.coordinator.receive(.disconnected(.timeout))
        let schedule = try #require(await harness.scheduler.pending().first)
        await harness.scheduler.fire(token: schedule.token)
        for _ in 0..<100 where await harness.transport.commands().filter({ $0 == .connect }).count < 2 {
            await Task.yield()
        }
        await harness.coordinator.receive(.connected)
        await harness.coordinator.receive(.servicesDiscovered)
        await harness.coordinator.receive(.characteristicsDiscovered)
        await harness.coordinator.receive(.notificationSubscriptionEnabled)
        await harness.coordinator.receive(.authenticationAccepted)
        await harness.coordinator.receive(.historyAcknowledged)
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: (102...105).map {
                        syntheticRecord(index: UInt16($0), tenths: UInt16($0 - 10))
                    }
                ),
                receivedAt: anchorDate.addingTimeInterval(181)
            )
        )
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .liveNotification,
                    records: [syntheticRecord(index: 106, tenths: 96)]
                ),
                receivedAt: anchorDate.addingTimeInterval(240)
            )
        )

        let repaired = try #require(await harness.store.session(id: harness.sessionID))
        #expect(repaired.lastCommittedIndex == 106)
        #expect(try await harness.store.samples(sessionID: harness.sessionID).map(\.sensorIndex) == Array(100...106))
        #expect(
            await harness.transport.commands().filter({
                $0 == .requestHistory(.committedOverlap)
            }).count == 2
        )
    }

    @Test func effectiveDataBeforeExactHistoryAckStaysBuffered() async throws {
        let anchorDate = Date(timeIntervalSince1970: 1_800_000_000)
        let anchor = try syntheticTimeAnchor(index: 102, timestamp: anchorDate)
        let harness = try await ForegroundHarness.make(captureStart: 100)
        try await harness.store.prepareHistoryRequest(
            sessionID: harness.sessionID,
            startingAt: 100
        )
        _ = try await harness.store.commitSamples(
            (100...102).map {
                try mappedSample(
                    sessionID: harness.sessionID,
                    index: UInt32($0),
                    tenths: $0 - 10,
                    anchor: anchor
                )
            },
            sessionID: harness.sessionID,
            establishingTimeAnchor: anchor
        )
        try await harness.advanceToHistoryRequest()

        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: [syntheticRecord(index: 103, tenths: 93)]
                ),
                receivedAt: anchorDate.addingTimeInterval(60)
            )
        )
        #expect(
            try await harness.store.sample(
                sessionID: harness.sessionID,
                sensorIndex: 103
            ) == nil
        )

        await harness.coordinator.receive(.historyAcknowledged)
        #expect(
            try await harness.store.sample(
                sessionID: harness.sessionID,
                sensorIndex: 103
            ) != nil
        )
    }

    @Test func protocolViolationBeforeHistoryAckDisconnectsWithoutCommittingPayload() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.advanceToHistoryRequest()
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .liveNotification,
                    records: [syntheticRecord(index: 100, tenths: 90)]
                ),
                receivedAt: Date()
            )
        )

        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(try await harness.store.samples(sessionID: harness.sessionID).isEmpty)
        #expect(harness.callbackLog.snapshot().failures.contains(.protocolViolation))
        #expect(await harness.transport.commands().last == .disconnect)
        #expect(harness.ownership.latestLease?.isActive == true)
        let events = harness.callbackLog.snapshot().events
        let rejectionIndex = try #require(
            events.firstIndex(where: { $0.kind == .protocolRejected })
        )
        let disconnectIndex = try #require(
            events.firstIndex(where: { $0.kind == .disconnectRequested })
        )
        #expect(rejectionIndex < disconnectIndex)
        #expect(events[rejectionIndex].protocolRejection?.origin == .stateInvariant)
    }

    @Test func typedTransportRejectionsAreDeduplicatedAndRecordedBeforeDisconnect() async throws {
        for origin in GS3ProtocolRejectionOrigin.allCases {
            let harness = try await ForegroundHarness.make()
            try await harness.advanceToHistoryRequest()
            let commandsBeforeRejection = await harness.transport.commands()
            let rejection = GS3ProtocolRejection(
                origin: origin,
                frameCategory: .notificationCandidate,
                frameByteCount: 24,
                timingWindow: .historyWritePending
            )

            await harness.transport.emit([
                .protocolRejected(rejection),
                .protocolRejected(rejection),
                .disconnected(.protocolViolation),
            ])
            for _ in 0..<200 where await harness.coordinator.currentPhase() != .stopped {
                await Task.yield()
            }

            let snapshot = harness.callbackLog.snapshot()
            let diagnostics = snapshot.events.filter { $0.kind == .protocolRejected }
            #expect(diagnostics.count == 1)
            #expect(diagnostics.first?.protocolRejection == rejection)
            let rejectionIndex = try #require(
                snapshot.events.firstIndex(where: { $0.kind == .protocolRejected })
            )
            let disconnectIndex = try #require(
                snapshot.events.firstIndex(where: { $0.kind == .disconnected })
            )
            let stoppedIndex = try #require(
                snapshot.events.firstIndex(where: { $0.kind == .stopped })
            )
            #expect(rejectionIndex < disconnectIndex)
            #expect(disconnectIndex < stoppedIndex)
            #expect(await harness.coordinator.currentPhase() == .stopped)
            #expect(harness.ownership.latestLease?.isActive == false)
            #expect(await harness.scheduler.pending().isEmpty)
            #expect(
                await harness.transport.commands()
                    == commandsBeforeRejection + [.disconnect]
            )
        }
    }

    @Test func authenticatedInboundRejectionAfterHistoryIntentMatchesPhysicalOrdering() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.coordinator.start()
        await harness.coordinator.receive(.connected)
        await harness.coordinator.receive(.servicesDiscovered)
        await harness.coordinator.receive(.characteristicsDiscovered)
        await harness.coordinator.receive(.notificationSubscriptionEnabled)
        await harness.coordinator.receive(.authenticationWriteAcknowledged)
        await harness.coordinator.receive(.authenticationAccepted)

        #expect(await harness.coordinator.currentPhase() == .requestingHistory)
        #expect(
            await harness.transport.commands().filter {
                if case .requestHistory = $0 { true } else { false }
            }.count == 1
        )
        #expect(harness.callbackLog.snapshot().acknowledgements == [.authentication])

        let rejection = GS3ProtocolRejection(
            origin: .inboundClassification,
            frameCategory: .observedHistoryPreambleCandidate,
            frameByteCount: 24,
            timingWindow: .authenticated
        )
        await harness.transport.emit([
            .protocolRejected(rejection),
            .disconnected(.protocolViolation),
        ])
        for _ in 0..<200 where await harness.coordinator.currentPhase() != .stopped {
            await Task.yield()
        }

        let snapshot = harness.callbackLog.snapshot()
        let historyIntent = try #require(
            snapshot.events.firstIndex(where: { $0.kind == .historyRequested })
        )
        let rejectionIndex = try #require(
            snapshot.events.firstIndex(where: { $0.kind == .protocolRejected })
        )
        let disconnectedIndex = try #require(
            snapshot.events.firstIndex(where: { $0.kind == .disconnected })
        )
        let stoppedIndex = try #require(
            snapshot.events.firstIndex(where: { $0.kind == .stopped })
        )
        #expect(historyIntent < rejectionIndex)
        #expect(rejectionIndex < disconnectedIndex)
        #expect(disconnectedIndex < stoppedIndex)
        #expect(snapshot.events.filter { $0.kind == .protocolRejected }.count == 1)
        #expect(
            snapshot.events[rejectionIndex].protocolRejection?.frameCategory
                == .observedHistoryPreambleCandidate
        )
        #expect(
            snapshot.events[rejectionIndex].protocolRejection?.timingWindow
                == .authenticated
        )
        let diagnosticText = snapshot.events[rejectionIndex].description
        #expect(diagnosticText.contains("frame=observedHistoryPreambleCandidate"))
        for forbidden in [
            "0x36", "sensor-identifier", "private-material", "glucose-value",
            "record-index", "json-contents", "json-hash", "packet-body",
        ] {
            #expect(!diagnosticText.contains(forbidden))
        }
        #expect(snapshot.acknowledgements == [.authentication])
        #expect(try await harness.store.samples(sessionID: harness.sessionID).isEmpty)
        #expect(harness.ownership.latestLease?.isActive == false)
    }

    @Test func outOfRangeHistoryRequestReportsRequestInvariantWithoutWriting() async throws {
        let harness = try await ForegroundHarness.make(captureStart: 65_536)
        try await harness.coordinator.start()
        await harness.coordinator.receive(.connected)
        await harness.coordinator.receive(.servicesDiscovered)
        await harness.coordinator.receive(.characteristicsDiscovered)
        await harness.coordinator.receive(.notificationSubscriptionEnabled)
        await harness.coordinator.receive(.authenticationAccepted)

        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(
            await harness.transport.commands().filter {
                if case .requestHistory = $0 { true } else { false }
            }.isEmpty
        )
        let rejection = try #require(
            harness.callbackLog.snapshot().events.first(where: {
                $0.kind == .protocolRejected
            })?.protocolRejection
        )
        #expect(rejection.origin == .requestInvariant)
        #expect(rejection.frameCategory == .unavailable)
        #expect(rejection.frameByteCount == nil)
        #expect(rejection.timingWindow == .historyRequestPreparing)
        #expect(harness.ownership.latestLease?.isActive == true)
        #expect(await harness.transport.commands().last == .disconnect)
    }

    @Test func observedHistoryPreambleDoesNotWriteRetryOrBlockValidHistory() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.advanceToHistoryRequest()
        let commandsBeforePreamble = await harness.transport.commands()

        await harness.coordinator.receive(.historyPreambleObserved)

        #expect(await harness.coordinator.currentPhase() == .requestingHistory)
        #expect(await harness.transport.commands() == commandsBeforePreamble)
        #expect(harness.callbackLog.snapshot().failures.isEmpty)
        #expect(harness.callbackLog.snapshot().events.contains {
            $0.kind == .historyPreambleObserved
                && $0.historyPreambleCount == 1
        })

        await harness.coordinator.receive(.historyAcknowledged)
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: [syntheticRecord(index: 100, tenths: 90)]
                ),
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .liveNotification,
                    records: [syntheticRecord(index: 101, tenths: 91)]
                ),
                receivedAt: Date(timeIntervalSince1970: 1_800_000_060)
            )
        )

        #expect(await harness.coordinator.currentPhase() == .live)
        #expect((try await harness.store.samples(sessionID: harness.sessionID)).count == 2)
        #expect(await harness.transport.commands() == commandsBeforePreamble)
        #expect(harness.callbackLog.snapshot().failures.isEmpty)
    }

    @Test func duplicateObservedHistoryPreambleDisconnectsWithoutAnotherWrite() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.advanceToHistoryRequest()
        let commandsBeforePreamble = await harness.transport.commands()

        await harness.coordinator.receive(.historyPreambleObserved)
        await harness.coordinator.receive(.historyPreambleObserved)

        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(
            await harness.transport.commands()
                == commandsBeforePreamble + [.disconnect]
        )
        #expect(harness.callbackLog.snapshot().failures.contains(.stateMachine))
        #expect(harness.ownership.latestLease?.isActive == true)
    }

    @Test func outOfOrderEventKeepsOwnershipUntilControlledDisconnectCompletes() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.coordinator.start()

        await harness.coordinator.receive(.servicesDiscovered)

        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(harness.ownership.latestLease?.isActive == true)
        #expect(await harness.transport.commands().last == .disconnect)
        #expect(harness.callbackLog.snapshot().failures.contains(.stateMachine))

        await harness.coordinator.receive(.transportDisconnected)
        #expect(await harness.coordinator.currentPhase() == .stopped)
        #expect(harness.ownership.latestLease?.isActive == false)
    }

    @Test func historyBelowDurablyPreparedStartFailsBeforeCommit() async throws {
        let harness = try await ForegroundHarness.make(captureStart: 100)
        try await harness.advanceToHistoryRequest()
        await harness.coordinator.receive(.historyAcknowledged)

        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: [syntheticRecord(index: 99, tenths: 90)]
                ),
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(try await harness.store.samples(sessionID: harness.sessionID).isEmpty)
        #expect(harness.callbackLog.snapshot().failures.contains(.protocolViolation))
        #expect(harness.ownership.latestLease?.isActive == true)
    }

    @Test func firstLiveIndexCannotMoveBehindBufferedHistory() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.advanceToHistoryRequest()
        await harness.coordinator.receive(.historyAcknowledged)
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .effectiveData,
                    records: [syntheticRecord(index: 101, tenths: 91)]
                ),
                receivedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        await harness.coordinator.receive(
            .glucoseBatch(
                V3GlucoseBatch(
                    source: .liveNotification,
                    records: [syntheticRecord(index: 100, tenths: 90)]
                ),
                receivedAt: Date(timeIntervalSince1970: 1_800_000_060)
            )
        )

        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(try await harness.store.samples(sessionID: harness.sessionID).isEmpty)
        #expect(harness.callbackLog.snapshot().failures.contains(.protocolViolation))
    }

    @Test func coordinatorRejectsNonLiveOrNonV3SessionsBeforeOwnershipAndTransport() async throws {
        for (lifecycle, variant, expected) in [
            (SensorLifecycleState.identified, ProtocolVariant.v3AES, GS3ForegroundCoordinatorError.sessionNotLive),
            (SensorLifecycleState.live, ProtocolVariant.unknown, GS3ForegroundCoordinatorError.unsupportedProtocol),
        ] {
            let store = InMemorySugarmanStore()
            let sessionID = UUID()
            try await store.insertSession(
                SensorSession(
                    id: sessionID,
                    sensorID: UUID(),
                    protocolVariant: variant,
                    lifecycle: lifecycle
                )
            )
            let transport = RecordingForegroundTransport()
            let ownership = RecordingOwnershipProvider()
            let coordinator = GS3ForegroundSessionCoordinator(
                configuration: try GS3ForegroundSessionConfiguration(
                    sessionID: sessionID,
                    sessionOrdinal: 1,
                    captureBackedStart: CaptureBackedHistoryStart(sensorIndex: 1)
                ),
                store: store,
                transport: transport,
                ownershipProvider: ownership,
                reconnectScheduler: RecordingReconnectScheduler()
            )
            await #expect(throws: expected) {
                try await coordinator.start()
            }
            #expect(ownership.acquisitionCount == 0)
            #expect(await transport.commands().isEmpty)
        }
    }

    @Test func coordinatorRejectsOrphanedDurableAnchorBeforeOwnership() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(
            SensorSession(
                id: sessionID,
                sensorID: UUID(),
                sensorTimeAnchor: try syntheticTimeAnchor(
                    index: 10,
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                protocolVariant: .v3AES,
                lifecycle: .live
            )
        )
        let transport = RecordingForegroundTransport()
        let ownership = RecordingOwnershipProvider()
        let callbackLog = ForegroundCallbackLog()
        let coordinator = GS3ForegroundSessionCoordinator(
            configuration: try GS3ForegroundSessionConfiguration(
                sessionID: sessionID,
                sessionOrdinal: 1,
                captureBackedStart: CaptureBackedHistoryStart(sensorIndex: 10)
            ),
            store: store,
            transport: transport,
            ownershipProvider: ownership,
            reconnectScheduler: RecordingReconnectScheduler(),
            callbacks: callbackLog.callbacks()
        )

        await #expect(throws: GS3ForegroundCoordinatorError.startFailed) {
            try await coordinator.start()
        }
        #expect(callbackLog.snapshot().failures == [.persistence])
        #expect(ownership.acquisitionCount == 0)
        #expect(await transport.commands().isEmpty)
    }

    @Test func coordinatorRejectsUnanchoredStoredSampleBeforeOwnership() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        try await store.insertSession(
            SensorSession(
                id: sessionID,
                sensorID: UUID(),
                protocolVariant: .v3AES,
                lifecycle: .live
            )
        )
        try await store.insertSample(
            GlucoseSample(
                sessionID: sessionID,
                sensorIndex: 10,
                sensorTimestamp: Date(timeIntervalSince1970: 1_800_000_000),
                receiptTimestamp: Date(timeIntervalSince1970: 1_800_000_000),
                milligramsPerDeciliter: 100,
                decoderRevision: "synthetic"
            )
        )
        let transport = RecordingForegroundTransport()
        let ownership = RecordingOwnershipProvider()
        let callbackLog = ForegroundCallbackLog()
        let coordinator = GS3ForegroundSessionCoordinator(
            configuration: try GS3ForegroundSessionConfiguration(
                sessionID: sessionID,
                sessionOrdinal: 1,
                captureBackedStart: CaptureBackedHistoryStart(sensorIndex: 10)
            ),
            store: store,
            transport: transport,
            ownershipProvider: ownership,
            reconnectScheduler: RecordingReconnectScheduler(),
            callbacks: callbackLog.callbacks()
        )

        await #expect(throws: GS3ForegroundCoordinatorError.startFailed) {
            try await coordinator.start()
        }
        #expect(callbackLog.snapshot().failures == [.persistence])
        #expect(ownership.acquisitionCount == 0)
        #expect(await transport.commands().isEmpty)
    }

    @Test func coordinatorRejectsCursorThatSkipsADurableGapBeforeOwnership() async throws {
        let store = InMemorySugarmanStore()
        let sessionID = UUID()
        let anchor = try syntheticTimeAnchor(
            index: 102,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await store.insertSession(
            SensorSession(
                id: sessionID,
                sensorID: UUID(),
                lastRequestedIndex: 100,
                lastReceivedIndex: 102,
                lastCommittedIndex: 102,
                sensorTimeAnchor: anchor,
                protocolVariant: .v3AES,
                lifecycle: .live
            )
        )
        try await store.insertSample(
            mappedSample(
                sessionID: sessionID,
                index: 100,
                tenths: 90,
                anchor: anchor
            )
        )
        try await store.insertSample(
            mappedSample(
                sessionID: sessionID,
                index: 102,
                tenths: 92,
                anchor: anchor
            )
        )
        let transport = RecordingForegroundTransport()
        let ownership = RecordingOwnershipProvider()
        let coordinator = GS3ForegroundSessionCoordinator(
            configuration: try GS3ForegroundSessionConfiguration(
                sessionID: sessionID,
                sessionOrdinal: 1,
                captureBackedStart: CaptureBackedHistoryStart(sensorIndex: 100)
            ),
            store: store,
            transport: transport,
            ownershipProvider: ownership,
            reconnectScheduler: RecordingReconnectScheduler()
        )

        await #expect(throws: GS3ForegroundCoordinatorError.startFailed) {
            try await coordinator.start()
        }
        #expect(ownership.acquisitionCount == 0)
        #expect(await transport.commands().isEmpty)
    }

    @Test func connectionRevalidationStopsBeforeHistoryWriteOnNewCorruption() async throws {
        let harness = try await ForegroundHarness.make()
        try await harness.coordinator.start()
        try await harness.store.insertSample(
            GlucoseSample(
                sessionID: harness.sessionID,
                sensorIndex: 10,
                sensorTimestamp: Date(timeIntervalSince1970: 1_800_000_000),
                receiptTimestamp: Date(timeIntervalSince1970: 1_800_000_000),
                milligramsPerDeciliter: 100,
                decoderRevision: "synthetic"
            )
        )
        await harness.coordinator.receive(.connected)
        await harness.coordinator.receive(.servicesDiscovered)
        await harness.coordinator.receive(.characteristicsDiscovered)
        await harness.coordinator.receive(.notificationSubscriptionEnabled)
        await harness.coordinator.receive(.authenticationAccepted)

        #expect(await harness.coordinator.currentPhase() == .disconnecting)
        #expect(
            await harness.transport.commands().filter {
                if case .requestHistory = $0 { true } else { false }
            }.isEmpty
        )
        #expect(harness.callbackLog.snapshot().failures.contains(.persistence))
        #expect(harness.ownership.latestLease?.isActive == true)
    }

    @Test func transportAndConfigurationDiagnosticsOmitIdentityIndexTimeAndGlucose() throws {
        let sessionID = UUID()
        let configuration = try GS3ForegroundSessionConfiguration(
            sessionID: sessionID,
            sessionOrdinal: 7,
            captureBackedStart: CaptureBackedHistoryStart(sensorIndex: 54_321)
        )
        let receivedAt = Date(timeIntervalSince1970: 1_800_123_456)
        let event = GS3ForegroundTransportEvent.glucoseBatch(
            V3GlucoseBatch(
                source: .liveNotification,
                records: [syntheticRecord(index: 54_322, tenths: 137)]
            ),
            receivedAt: receivedAt
        )
        let coordinator = GS3ForegroundSessionCoordinator(
            configuration: configuration,
            store: InMemorySugarmanStore(),
            transport: RecordingForegroundTransport(),
            ownershipProvider: RecordingOwnershipProvider(),
            reconnectScheduler: RecordingReconnectScheduler()
        )
        var dumpedEvent = ""
        dump(event, to: &dumpedEvent)
        var dumpedCoordinator = ""
        dump(coordinator, to: &dumpedCoordinator)
        let text = "\(configuration) \(event) \(String(reflecting: event)) "
            + "\(String(reflecting: configuration)) \(dumpedEvent) "
            + "\(String(reflecting: coordinator)) \(dumpedCoordinator)"
        #expect(!text.contains(sessionID.uuidString))
        #expect(!text.contains("54321"))
        #expect(!text.contains("54322"))
        #expect(!text.contains("137"))
        #expect(!text.contains("1800123456"))
        #expect(!text.contains("Data"))
        #expect(!text.contains("bytes"))
    }

    @Test func protocolRejectionTransportEventExposesOnlyAllowlistedMetadata() {
        let rejection = GS3ProtocolRejection(
            origin: .inboundClassification,
            frameCategory: .notificationCandidate,
            frameByteCount: 24,
            timingWindow: .historyWritePending
        )
        let event = GS3ForegroundTransportEvent.protocolRejected(rejection)
        var dumped = ""
        dump(event, to: &dumped)
        let text = "\(event) \(String(reflecting: event)) \(dumped)"

        #expect(text.contains("origin=inboundClassification"))
        #expect(text.contains("frame=notificationCandidate"))
        #expect(text.contains("bytes=24"))
        #expect(text.contains("window=historyWritePending"))
        for forbidden in [
            "0x36", "sensor-identifier", "private-material", "glucose-value",
            "record-index", "json-contents", "json-hash", "command-body",
        ] {
            #expect(!text.contains(forbidden))
        }
    }
}

private func advance(
    _ harness: ForegroundHarness,
    to target: GS3ForegroundPhase
) async throws {
    try await harness.coordinator.start()
    if target == .connecting { return }
    await harness.coordinator.receive(.connected)
    if target == .discoveringServices { return }
    await harness.coordinator.receive(.servicesDiscovered)
    if target == .discoveringCharacteristics { return }
    await harness.coordinator.receive(.characteristicsDiscovered)
    if target == .subscribing { return }
    await harness.coordinator.receive(.notificationSubscriptionEnabled)
    if target == .authenticating { return }
    await harness.coordinator.receive(.authenticationAccepted)
    if target == .requestingHistory { return }
    await harness.coordinator.receive(.historyAcknowledged)
    if target == .synchronizing { return }
    await harness.coordinator.receive(
        .glucoseBatch(
            V3GlucoseBatch(
                source: .liveNotification,
                records: [syntheticRecord(index: 100, tenths: 90)]
            ),
            receivedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    )
}

private func mappedSample(
    sessionID: UUID,
    index: UInt32,
    tenths: Int,
    anchor: SensorTimeAnchor
) throws -> GlucoseSample {
    GlucoseSample(
        sessionID: sessionID,
        sensorIndex: index,
        sensorTimestamp: try anchor.timestamp(for: index),
        receiptTimestamp: anchor.timestamp,
        milligramsPerDeciliter: ((tenths * 18) + 5) / 10,
        originalTenthsMillimolesPerLiter: tenths,
        trend: .stable,
        quality: .questionable,
        source: .backfill,
        decoderRevision: "synthetic"
    )
}
