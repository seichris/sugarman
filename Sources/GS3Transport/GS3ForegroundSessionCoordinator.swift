// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol
import GS3Session
import SugarmanDomain
import SugarmanStore

public enum GS3ForegroundCoordinatorError: Error, Sendable, Equatable {
    case alreadyStarted
    case sessionUnavailable
    case sessionNotLive
    case unsupportedProtocol
    case startFailed
}

extension GS3ForegroundCoordinatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyStarted:
            "The foreground GS3 session has already started."
        case .sessionUnavailable:
            "The local sensor session is unavailable."
        case .sessionNotLive:
            "Only an already-active live sensor session can use this transport."
        case .unsupportedProtocol:
            "The local sensor session is not the physically verified V3 protocol."
        case .startFailed:
            "The foreground GS3 session failed closed before connecting."
        }
    }
}

private struct BufferedGS3Record: Sendable {
    let record: V3GlucoseRecord
    let source: V3GlucoseBatchSource
    let receivedAt: Date
}

private enum QueuedCoordinatorAction: Sendable {
    case input(GS3ForegroundInput)
    case transport(GS3ForegroundTransportEvent)
}

private struct PendingCoordinatorAction {
    let action: QueuedCoordinatorAction
    let completion: CheckedContinuation<Void, Never>
}

/// Actor that executes every effect from `GS3ForegroundSessionMachine` through
/// typed dependencies. It owns no CoreBluetooth object and exposes no packet or
/// arbitrary-write surface, which keeps the full lifecycle host-testable.
package actor GS3ForegroundSessionCoordinator: GS3ForegroundSessionControlling {
    private let configuration: GS3ForegroundSessionConfiguration
    private let store: any SugarmanStoring
    private let transport: any GS3ForegroundTransporting
    private let ownershipProvider: any GS3SensorOwnershipProviding
    private let reconnectScheduler: any GS3ReconnectScheduling
    private let callbacks: GS3ForegroundSessionCallbacks
    private let monotonicNanoseconds: @Sendable () -> UInt64

    private var machine: GS3ForegroundSessionMachine
    private var ownerLease: (any GS3SensorOwnerLeaseHandle)?
    private var startRequested = false
    private var startedAtNanoseconds: UInt64?
    private var sensorTimeAnchor: SensorTimeAnchor?
    private var activeHistoryStart: UInt32?
    private var bufferedRecords: [BufferedGS3Record] = []
    private var historyWasAcknowledged = false
    private var pendingActions: [PendingCoordinatorAction] = []
    private var isDrainingActions = false
    private var foregroundStopRequested = false
    private var eventContinuation:
        AsyncStream<GS3ForegroundTransportEvent>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var eventDeliveryOverflowReported = false

    package init(
        configuration: GS3ForegroundSessionConfiguration,
        store: any SugarmanStoring,
        transport: any GS3ForegroundTransporting,
        callbacks: GS3ForegroundSessionCallbacks = GS3ForegroundSessionCallbacks()
    ) {
        self.init(
            configuration: configuration,
            store: store,
            transport: transport,
            ownershipProvider: SharedGS3SensorOwnershipProvider(),
            reconnectScheduler: TaskGS3ReconnectScheduler(),
            callbacks: callbacks,
            monotonicNanoseconds: {
                DispatchTime.now().uptimeNanoseconds
            }
        )
    }

    package init(
        configuration: GS3ForegroundSessionConfiguration,
        store: any SugarmanStoring,
        transport: any GS3ForegroundTransporting,
        ownershipProvider: any GS3SensorOwnershipProviding,
        reconnectScheduler: any GS3ReconnectScheduling,
        callbacks: GS3ForegroundSessionCallbacks = GS3ForegroundSessionCallbacks(),
        monotonicNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.configuration = configuration
        self.store = store
        self.transport = transport
        self.ownershipProvider = ownershipProvider
        self.reconnectScheduler = reconnectScheduler
        self.callbacks = callbacks
        self.monotonicNanoseconds = monotonicNanoseconds
        self.machine = GS3ForegroundSessionMachine(
            sessionOrdinal: configuration.sessionOrdinal
        )
    }

    public func start() async throws {
        guard machine.phase == .idle, !startRequested else {
            throw GS3ForegroundCoordinatorError.alreadyStarted
        }
        startRequested = true
        let loadedSession: SensorSession?
        do {
            loadedSession = try await store.session(id: configuration.sessionID)
        } catch {
            callbacks.onFailure(.persistence)
            throw GS3ForegroundCoordinatorError.startFailed
        }
        guard let session = loadedSession else {
            callbacks.onFailure(.sessionUnavailable)
            throw GS3ForegroundCoordinatorError.sessionUnavailable
        }
        guard session.lifecycle == .live else {
            callbacks.onFailure(.sessionNotLive)
            throw GS3ForegroundCoordinatorError.sessionNotLive
        }
        guard session.protocolVariant == .v3AES else {
            callbacks.onFailure(.unsupportedProtocol)
            throw GS3ForegroundCoordinatorError.unsupportedProtocol
        }
        do {
            try await validateDurableTimeline(for: session)
        } catch {
            callbacks.onFailure(.persistence)
            throw GS3ForegroundCoordinatorError.startFailed
        }
        guard machine.phase == .idle else {
            throw GS3ForegroundCoordinatorError.startFailed
        }

        sensorTimeAnchor = session.sensorTimeAnchor
        startedAtNanoseconds = monotonicNanoseconds()
        let (events, continuation) = AsyncStream.makeStream(
            of: GS3ForegroundTransportEvent.self,
            bufferingPolicy: .bufferingOldest(256)
        )
        eventContinuation = continuation
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.receive(event)
            }
        }
        await transport.installEventHandler { [weak self] event in
            switch continuation.yield(event) {
            case .enqueued:
                break
            case .dropped:
                Task { await self?.eventDeliveryOverflowed() }
            case .terminated:
                break
            @unknown default:
                Task { await self?.eventDeliveryOverflowed() }
            }
        }
        await submit(.input(.start))
        if machine.phase == .stopped {
            throw GS3ForegroundCoordinatorError.startFailed
        }
    }

    public func stop() async {
        await submit(.input(.stop))
    }

    public func foregroundEnded() async {
        await submit(.input(.foregroundEnded))
    }

    public func currentPhase() -> GS3ForegroundPhase {
        machine.phase
    }

    package func receive(_ event: GS3ForegroundTransportEvent) async {
        await submit(.transport(event))
    }

    private func handle(_ event: GS3ForegroundTransportEvent) async {
        switch event {
        case .connected:
            await advance(.connected)
        case .servicesDiscovered:
            await advance(.servicesDiscovered)
        case .characteristicsDiscovered:
            await advance(.characteristicsDiscovered)
        case .notificationSubscriptionEnabled:
            await advance(.notificationSubscriptionEnabled)
        case .authenticationWriteAcknowledged:
            callbacks.onCommandAcknowledged(.authentication)
        case .authenticationAccepted:
            await advance(.authenticationAccepted)
        case .authenticationRejected:
            await advance(.authenticationRejected)
        case .historyWriteAcknowledged:
            callbacks.onCommandAcknowledged(.effectiveData)
        case .historyPreambleObserved:
            await advance(.historyPreambleObserved)
        case .historyAcknowledged:
            await advance(.historyAcknowledged)
            historyWasAcknowledged = machine.phase == .synchronizing
                || machine.phase == .live
            if historyWasAcknowledged,
               let anchor = sensorTimeAnchor,
               !bufferedRecords.isEmpty {
                await commit(
                    records: bufferedRecords,
                    anchor: anchor,
                    establishingAnchor: nil,
                    completesSynchronization: false,
                    clearBufferedRecordsOnSuccess: true
                )
            }
        case .glucoseBatch(let batch, let receivedAt):
            await receive(batch: batch, receivedAt: receivedAt)
        case .transportDisconnected:
            await advance(.transportDisconnected)
        case .disconnected(let reason):
            await advance(.disconnected(reason))
        }
    }

    private func submit(_ action: QueuedCoordinatorAction) async {
        if case .input(let input) = action,
           input == .stop || input == .foregroundEnded {
            foregroundStopRequested = true
        }
        await withCheckedContinuation { continuation in
            pendingActions.append(
                PendingCoordinatorAction(
                    action: action,
                    completion: continuation
                )
            )
            guard !isDrainingActions else { return }
            isDrainingActions = true
            Task { await self.drainActions() }
        }
    }

    private func drainActions() async {
        while !pendingActions.isEmpty {
            let pending = pendingActions.removeFirst()
            switch pending.action {
            case .input(let input):
                await advance(input)
            case .transport(let event):
                await handle(event)
            }
            pending.completion.resume()
            if machine.phase == .stopped {
                finishEventDelivery()
            }
        }
        isDrainingActions = false
    }

    private func advance(_ input: GS3ForegroundInput) async {
        let effects = machine.send(
            input,
            elapsedWholeSeconds: elapsedWholeSeconds()
        )
        for effect in effects {
            guard await apply(effect) else { break }
        }
    }

    private func apply(_ effect: GS3ForegroundEffect) async -> Bool {
        if foregroundStopRequested, effectStartsNewForegroundWork(effect) {
            return false
        }
        switch effect {
        case .acquireOwnership:
            do {
                let lease = try ownershipProvider.acquire()
                ownerLease = lease
                await advance(.ownershipAcquired)
            } catch {
                callbacks.onFailure(.ownershipUnavailable)
                await advance(.ownershipDenied)
            }
            return false

        case .releaseOwnership:
            ownerLease?.release()
            ownerLease = nil

        case .connect:
            bufferedRecords.removeAll(keepingCapacity: true)
            activeHistoryStart = nil
            historyWasAcknowledged = false
            await transport.connectKnownPeripheral()

        case .ensureTransportDisconnected:
            await transport.ensureDisconnected()

        case .discoverServices:
            await transport.discoverGS3Service()

        case .discoverCharacteristics:
            await transport.discoverGS3Characteristics()

        case .subscribeToNotifications:
            await transport.subscribeToGS3Notifications()

        case .authenticateConnection:
            await transport.authenticateConnection()

        case .loadHistoryPlan:
            do {
                guard let session = try await store.session(id: configuration.sessionID) else {
                    throw StoreError.notFound
                }
                guard session.lifecycle == .live else {
                    callbacks.onFailure(.sessionNotLive)
                    await advance(.protocolViolation)
                    return false
                }
                guard session.protocolVariant == .v3AES else {
                    callbacks.onFailure(.unsupportedProtocol)
                    await advance(.protocolViolation)
                    return false
                }
                try await validateDurableTimeline(for: session)
                sensorTimeAnchor = session.sensorTimeAnchor
                let plan = HistoryCursorPolicy.plan(
                    session: session,
                    captureBackedStart: configuration.captureBackedStart
                )
                guard !foregroundStopRequested else { return false }
                await advance(.historyPlanLoaded(plan))
            } catch {
                callbacks.onFailure(.persistence)
                await advance(.persistenceFailed)
            }
            return false

        case .prepareHistoryRequest(let plan):
            do {
                try await store.prepareHistoryRequest(
                    sessionID: configuration.sessionID,
                    startingAt: plan.startingIndex
                )
                guard !foregroundStopRequested else { return false }
                await advance(.historyRequestDurablyPrepared(plan))
            } catch {
                callbacks.onFailure(.persistence)
                await advance(.persistenceFailed)
            }
            return false

        case .requestHistory(let plan):
            guard UInt16(exactly: plan.startingIndex) != nil else {
                await protocolViolation()
                return false
            }
            activeHistoryStart = plan.startingIndex
            await transport.requestEffectiveData(plan)

        case .scheduleReconnect(let schedule):
            await reconnectScheduler.schedule(schedule) { [weak self] in
                Task {
                    await self?.submit(
                        .input(.reconnectDelayElapsed(token: schedule.token))
                    )
                }
            }

        case .cancelReconnect(let token):
            await reconnectScheduler.cancel(token: token)

        case .publishConnection(let connection):
            do {
                try await store.setConnection(
                    connection,
                    sessionID: configuration.sessionID
                )
                callbacks.onConnection(connection)
            } catch {
                callbacks.onFailure(.persistence)
                await advance(.persistenceFailed)
                return false
            }

        case .record(let event):
            callbacks.onLifecycleEvent(event)

        case .fail:
            callbacks.onFailure(.stateMachine)
            if isActiveConnectionPhase(machine.phase)
                || machine.phase == .acquiringOwnership
                || machine.phase == .backoff {
                await advance(.protocolViolation)
            }
            return false
        }
        return true
    }

    private func receive(batch: V3GlucoseBatch, receivedAt: Date) async {
        guard !batch.records.isEmpty, hasNoNativeWrap(batch.records) else {
            await protocolViolation()
            return
        }

        switch batch.source {
        case .effectiveData:
            guard machine.phase == .requestingHistory
                    || machine.phase == .synchronizing
                    || machine.phase == .live else {
                await protocolViolation()
                return
            }
            guard let activeHistoryStart,
                  batch.records.allSatisfy({
                      UInt32($0.index) >= activeHistoryStart
                  }) else {
                await protocolViolation()
                return
            }
            if !historyWasAcknowledged {
                guard appendToBuffer(
                    batch.records,
                    source: batch.source,
                    receivedAt: receivedAt
                ) else {
                    await protocolViolation()
                    return
                }
            } else if let anchor = sensorTimeAnchor {
                await commit(
                    records: batch.records.map {
                        BufferedGS3Record(
                            record: $0,
                            source: batch.source,
                            receivedAt: receivedAt
                        )
                    },
                    anchor: anchor,
                    establishingAnchor: nil,
                    completesSynchronization: false
                )
            } else {
                guard appendToBuffer(
                    batch.records,
                    source: batch.source,
                    receivedAt: receivedAt
                ) else {
                    await protocolViolation()
                    return
                }
            }

        case .liveNotification:
            guard historyWasAcknowledged,
                  (machine.phase == .synchronizing || machine.phase == .live) else {
                await protocolViolation()
                return
            }
            let live = batch.records.map {
                BufferedGS3Record(
                    record: $0,
                    source: batch.source,
                    receivedAt: receivedAt
                )
            }
            if let anchor = sensorTimeAnchor {
                guard let first = batch.records.first,
                      UInt32(first.index) >= anchor.sensorIndex else {
                    await protocolViolation()
                    return
                }
                await commit(
                    records: live,
                    anchor: anchor,
                    establishingAnchor: nil,
                    completesSynchronization: machine.phase == .synchronizing
                )
            } else {
                guard let last = batch.records.last,
                      bufferedRecords.map(\.record.index).max().map({
                          $0 <= last.index
                      }) ?? true,
                      bufferedRecords.count <= configuration.maximumBufferedRecordCount
                        - live.count else {
                    await protocolViolation()
                    return
                }
                let anchor: SensorTimeAnchor
                do {
                    anchor = try SensorTimeAnchor(
                        sensorIndex: UInt32(last.index),
                        timestamp: receivedAt,
                        sampleIntervalSeconds: GS3ForegroundSessionConfiguration
                            .inferredSampleIntervalSeconds,
                        mappingRevision: GS3ForegroundSessionConfiguration
                            .inferredTimeMappingRevision
                    )
                } catch {
                    await protocolViolation()
                    return
                }
                let records = bufferedRecords + live
                await commit(
                    records: records,
                    anchor: anchor,
                    establishingAnchor: anchor,
                    completesSynchronization: true
                )
            }
        }
    }

    private func commit(
        records: [BufferedGS3Record],
        anchor: SensorTimeAnchor,
        establishingAnchor: SensorTimeAnchor?,
        completesSynchronization: Bool,
        clearBufferedRecordsOnSuccess: Bool = false
    ) async {
        do {
            let samples = try records.map { item in
                try sample(from: item, anchor: anchor)
            }
            let result = try await store.commitSamples(
                samples,
                sessionID: configuration.sessionID,
                establishingTimeAnchor: establishingAnchor
            )
            if establishingAnchor != nil || clearBufferedRecordsOnSuccess {
                sensorTimeAnchor = anchor
                bufferedRecords.removeAll(keepingCapacity: false)
            }
            let summary = GS3BatchCommitSummary(result)
            await advance(.batchCommitted(summary))
            callbacks.onSamplesCommitted(summary)
            if completesSynchronization, machine.phase == .synchronizing {
                await advance(.synchronizationCompleted)
            }
        } catch {
            callbacks.onFailure(.persistence)
            await advance(.persistenceFailed)
        }
    }

    private func sample(
        from item: BufferedGS3Record,
        anchor: SensorTimeAnchor
    ) throws -> GlucoseSample {
        let tenths = Int(item.record.glucoseTenthsMillimolesPerLiter)
        return GlucoseSample(
            sessionID: configuration.sessionID,
            sensorIndex: UInt32(item.record.index),
            sensorTimestamp: try anchor.timestamp(
                for: UInt32(item.record.index)
            ),
            receiptTimestamp: item.receivedAt,
            milligramsPerDeciliter: ((tenths * 18) + 5) / 10,
            originalTenthsMillimolesPerLiter: tenths,
            trend: item.record.trendCode == 2 ? .stable : .unknown,
            // The bit boundaries are decoded, but their product meaning is
            // unresolved. Never promote a live value to "current" until a
            // physical gate establishes the healthy/error state mapping.
            quality: .questionable,
            source: item.source == .liveNotification ? .live : .backfill,
            decoderRevision: V3OfflineGlucoseNotificationDecoder.evidenceRevision
        )
    }

    private func hasNoNativeWrap(_ records: [V3GlucoseRecord]) -> Bool {
        guard records.count > 1 else { return true }
        for (left, right) in zip(records, records.dropFirst()) {
            guard left.index != .max, right.index == left.index + 1 else {
                return false
            }
        }
        return true
    }

    private func appendToBuffer(
        _ records: [V3GlucoseRecord],
        source: V3GlucoseBatchSource,
        receivedAt: Date
    ) -> Bool {
        guard bufferedRecords.count <= configuration.maximumBufferedRecordCount
                - records.count else {
            return false
        }
        bufferedRecords.append(
            contentsOf: records.map {
                BufferedGS3Record(
                    record: $0,
                    source: source,
                    receivedAt: receivedAt
                )
            }
        )
        return true
    }

    private func validateDurableTimeline(
        for session: SensorSession
    ) async throws {
        let samples = try await store.samples(
            sessionID: configuration.sessionID
        )
        guard let anchor = session.sensorTimeAnchor else {
            guard samples.isEmpty,
                  session.lastReceivedIndex == nil,
                  session.lastCommittedIndex == nil else {
                throw StoreError.missingTimeAnchor
            }
            return
        }

        guard anchor.sampleIntervalSeconds == GS3ForegroundSessionConfiguration
                .inferredSampleIntervalSeconds,
              anchor.mappingRevision == GS3ForegroundSessionConfiguration
                .inferredTimeMappingRevision,
              !samples.isEmpty,
              let requested = session.lastRequestedIndex,
              let highestIndex = samples.map(\.sensorIndex).max(),
              session.lastReceivedIndex == highestIndex,
              session.lastCommittedIndex == contiguousCommittedIndex(
                  startingAt: requested,
                  storedIndices: Set(samples.map(\.sensorIndex))
              ),
              samples.contains(where: {
                  $0.sensorIndex == anchor.sensorIndex
                      && $0.sensorTimestamp == anchor.timestamp
              }) else {
            throw StoreError.incompleteTimeAnchor
        }
        for sample in samples {
            guard sample.sensorTimestamp == (try anchor.timestamp(
                for: sample.sensorIndex
            )) else {
                throw StoreError.sampleTimestampDoesNotMatchAnchor
            }
        }
    }

    private func contiguousCommittedIndex(
        startingAt start: UInt32,
        storedIndices: Set<UInt32>
    ) -> UInt32? {
        var index = start
        var committed: UInt32?
        while storedIndices.contains(index) {
            committed = index
            guard index != .max else { break }
            index += 1
        }
        return committed
    }

    private func protocolViolation() async {
        callbacks.onFailure(.protocolViolation)
        await advance(.protocolViolation)
    }

    private func eventDeliveryOverflowed() async {
        guard !eventDeliveryOverflowReported else { return }
        eventDeliveryOverflowReported = true
        eventContinuation?.finish()
        eventTask?.cancel()
        callbacks.onFailure(.protocolViolation)
        await submit(.input(.protocolViolation))
    }

    private func finishEventDelivery() {
        eventContinuation?.finish()
        eventContinuation = nil
        eventTask?.cancel()
        eventTask = nil
    }

    private func elapsedWholeSeconds() -> Int {
        guard let startedAtNanoseconds else { return 0 }
        let now = monotonicNanoseconds()
        guard now >= startedAtNanoseconds else { return 0 }
        let seconds = (now - startedAtNanoseconds) / 1_000_000_000
        return seconds > UInt64(Int.max) ? Int.max : Int(seconds)
    }

    private func isActiveConnectionPhase(_ phase: GS3ForegroundPhase) -> Bool {
        switch phase {
        case .connecting, .discoveringServices, .discoveringCharacteristics,
             .subscribing, .authenticating, .loadingHistoryPlan,
             .preparingHistoryRequest, .requestingHistory, .synchronizing,
             .live:
            true
        case .idle, .acquiringOwnership, .backoff, .disconnecting, .stopped:
            false
        }
    }

    private func effectStartsNewForegroundWork(
        _ effect: GS3ForegroundEffect
    ) -> Bool {
        switch effect {
        case .acquireOwnership, .connect, .discoverServices,
             .discoverCharacteristics, .subscribeToNotifications,
             .authenticateConnection, .loadHistoryPlan,
             .prepareHistoryRequest, .requestHistory, .scheduleReconnect:
            true
        case .releaseOwnership, .ensureTransportDisconnected,
             .cancelReconnect, .publishConnection, .record, .fail:
            false
        }
    }
}

extension GS3ForegroundSessionCoordinator:
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    nonisolated package var description: String {
        "GS3ForegroundSessionCoordinator(state: redacted)"
    }

    nonisolated package var debugDescription: String { description }

    nonisolated package var customMirror: Mirror {
        Mirror(
            self,
            children: ["state": "redacted"],
            displayStyle: .class
        )
    }
}
