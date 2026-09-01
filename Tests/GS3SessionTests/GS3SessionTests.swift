// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SafetyEngine
import SugarmanDomain
import SugarmanStore
import Testing
@testable import GS3Session

struct GS3SessionTests {
    private let anchor = CaptureBackedHistoryStart(sensorIndex: 424_242)

    @Test func fullForegroundLifecycleRequiresOwnershipSubscribeAuthAndDurableHistory() {
        var machine = GS3ForegroundSessionMachine(sessionOrdinal: 7)

        #expect(machine.send(.start).contains(.acquireOwnership))
        #expect(machine.phase == .acquiringOwnership)
        #expect(machine.send(.ownershipAcquired).contains(.connect))
        #expect(machine.connectionOrdinal == 1)
        #expect(machine.send(.connected).contains(.discoverServices))
        #expect(machine.send(.servicesDiscovered).contains(.discoverCharacteristics))
        #expect(machine.send(.characteristicsDiscovered).contains(.subscribeToNotifications))

        let subscription = machine.send(.notificationSubscriptionEnabled)
        #expect(subscription.filter { $0 == .authenticateConnection }.count == 1)
        #expect(machine.authenticationRequestCount == 1)
        #expect(machine.send(.authenticationAccepted).contains(.loadHistoryPlan))

        let plan = HistoryRequestPlan(startingIndex: anchor.sensorIndex, source: .captureBacked)
        #expect(machine.send(.historyPlanLoaded(plan)).contains(.prepareHistoryRequest(plan)))
        let prepared = machine.send(.historyRequestDurablyPrepared(plan))
        #expect(prepared.filter { $0 == .requestHistory(plan) }.count == 1)
        #expect(machine.historyRequestCount == 1)
        #expect(machine.phase == .requestingHistory)

        #expect(machine.send(.historyAcknowledged).isEmpty)
        #expect(machine.phase == .synchronizing)
        _ = machine.send(
            .batchCommitted(
                GS3BatchCommitSummary(insertedCount: 3, duplicateCount: 1, gapRangeCount: 0)
            )
        )
        let completed = machine.send(.synchronizationCompleted)
        #expect(completed.contains(.publishConnection(.subscribed)))
        #expect(machine.phase == .live)
        #expect(machine.presentationConnectionState == .subscribed)
        #expect(machine.authenticationRequestCount == 1)
        #expect(machine.historyRequestCount == 1)
    }

    @Test func oneObservedHistoryPreambleIsRecordedAndDuplicateFailsClosed() {
        var machine = machine(at: .requestingHistory)

        let observed = machine.send(
            .historyPreambleObserved,
            elapsedWholeSeconds: 12
        )
        #expect(machine.phase == .requestingHistory)
        #expect(machine.historyPreambleCount == 1)
        #expect(observed.contains {
            if case .record(let event) = $0 {
                return event.kind == .historyPreambleObserved
                    && event.historyPreambleCount == 1
            }
            return false
        })

        #expect(
            machine.send(.historyPreambleObserved)
                == [.fail(.invalidTransition(from: .requestingHistory))]
        )
        #expect(machine.historyPreambleCount == 1)
    }

    @Test func observedHistoryPreambleCountResetsForReauthenticatedConnection() {
        var machine = machine(at: .requestingHistory)
        _ = machine.send(.historyPreambleObserved)
        let disconnected = machine.send(.disconnected(.timeout))
        let token = reconnectSchedule(in: disconnected)!.token
        _ = machine.send(.reconnectDelayElapsed(token: token))

        #expect(machine.phase == .connecting)
        #expect(machine.historyPreambleCount == 0)
        _ = machine.send(.connected)
        _ = machine.send(.servicesDiscovered)
        _ = machine.send(.characteristicsDiscovered)
        _ = machine.send(.notificationSubscriptionEnabled)
        _ = machine.send(.authenticationAccepted)
        let plan = HistoryRequestPlan(
            startingIndex: anchor.sensorIndex,
            source: .captureBacked
        )
        _ = machine.send(.historyPlanLoaded(plan))
        _ = machine.send(.historyRequestDurablyPrepared(plan))

        #expect(machine.phase == .requestingHistory)
        #expect(machine.send(.historyPreambleObserved).contains {
            if case .record(let event) = $0 {
                return event.kind == .historyPreambleObserved
            }
            return false
        })
        #expect(machine.historyPreambleCount == 1)
    }

    @Test func observedHistoryPreambleOutsideHistoryRequestFailsClosed() {
        for phase in [
            GS3ForegroundPhase.authenticating,
            .loadingHistoryPlan,
            .preparingHistoryRequest,
            .synchronizing,
            .live,
        ] {
            var machine = machine(at: phase)
            #expect(
                machine.send(.historyPreambleObserved)
                    == [.fail(.invalidTransition(from: phase))]
            )
            #expect(machine.historyPreambleCount == 0)
        }
    }

    @Test func protocolRejectionDiagnosticIsRecordedOncePerConnection() throws {
        var machine = machine(at: .requestingHistory)
        let rejection = GS3ProtocolRejection(
            origin: .inboundClassification,
            frameCategory: .notificationCandidate,
            frameByteCount: 24,
            timingWindow: .historyWritePending
        )

        let first = machine.send(
            .protocolRejectionObserved(rejection),
            elapsedWholeSeconds: 7
        )
        #expect(first.contains {
            if case .record(let event) = $0 {
                return event.kind == .protocolRejected
                    && event.protocolRejection == rejection
                    && event.elapsedWholeSeconds == 7
            }
            return false
        })
        #expect(machine.send(.protocolRejectionObserved(rejection)).isEmpty)

        let disconnected = machine.send(.disconnected(.timeout))
        let token = try #require(reconnectSchedule(in: disconnected)?.token)
        _ = machine.send(.reconnectDelayElapsed(token: token))
        #expect(machine.phase == .connecting)
        #expect(machine.send(.protocolRejectionObserved(rejection)).contains {
            if case .record(let event) = $0 {
                return event.kind == .protocolRejected
            }
            return false
        })
    }

    @Test func everyProtocolRejectionOriginIsTypedBoundedAndPayloadFree() {
        #expect(GS3ProtocolFrameCategory.classify(byteCount: 0) == .missing)
        #expect(GS3ProtocolFrameCategory.classify(byteCount: 5) == .controlCandidate)
        #expect(GS3ProtocolFrameCategory.classify(byteCount: 24) == .notificationCandidate)
        #expect(GS3ProtocolFrameCategory.classify(byteCount: 3) == .other)

        for origin in GS3ProtocolRejectionOrigin.allCases {
            let rejection = GS3ProtocolRejection(
                origin: origin,
                frameCategory: .notificationCandidate,
                frameByteCount: Int.max,
                timingWindow: .historyWritePending
            )
            var dumped = ""
            dump(rejection, to: &dumped)
            let text = "\(rejection) \(String(reflecting: rejection)) \(dumped)"

            #expect(rejection.frameByteCount == 512)
            #expect(rejection.frameByteCountWasCapped)
            #expect(text.contains("origin=\(origin.rawValue)"))
            #expect(text.contains("frame=notificationCandidate"))
            #expect(text.contains("bytes=512+"))
            #expect(text.contains("window=historyWritePending"))
            for forbidden in [
                "0x36", "sensor-identifier", "glucose-value", "record-index",
                "private-material", "json-contents", "json-hash",
                "arbitrary-command-bytes",
            ] {
                #expect(!text.contains(forbidden))
            }
        }

        let knownPreambleRejection = GS3ProtocolRejection(
            origin: .inboundClassification,
            frameCategory: .observedHistoryPreambleCandidate,
            frameByteCount: 24,
            timingWindow: .authenticated
        )
        var dumped = ""
        dump(knownPreambleRejection, to: &dumped)
        let text = "\(knownPreambleRejection) "
            + "\(String(reflecting: knownPreambleRejection)) \(dumped)"
        #expect(text.contains("frame=observedHistoryPreambleCandidate"))
        #expect(text.contains("window=authenticated"))
        for forbidden in [
            "0x36", "sensor-identifier", "glucose-value", "record-index",
            "private-material", "json-contents", "json-hash", "packet-body",
            "arbitrary-command-bytes",
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    @Test func reconnectIsSingleFlightAndRepeatsSubscriptionAuthenticationAndHistory() {
        var machine = machine(at: .live)
        let disconnected = machine.send(.disconnected(.timeout), elapsedWholeSeconds: 90)
        let schedule = reconnectSchedule(in: disconnected)
        #expect(schedule?.attempt == 1)
        #expect(disconnected.filter(isReconnectSchedule).count == 1)
        #expect(machine.phase == .backoff)
        #expect(machine.hasOwnership)
        #expect(machine.send(.disconnected(.linkLoss)).isEmpty)

        let token = try! #require(schedule?.token)
        #expect(machine.send(.reconnectDelayElapsed(token: token)).contains(.connect))
        #expect(machine.connectionOrdinal == 2)
        #expect(machine.authenticationRequestCount == 0)
        #expect(machine.historyRequestCount == 0)

        _ = machine.send(.connected)
        _ = machine.send(.servicesDiscovered)
        let discovery = machine.send(.characteristicsDiscovered)
        #expect(discovery.filter { $0 == .subscribeToNotifications }.count == 1)
        let subscription = machine.send(.notificationSubscriptionEnabled)
        #expect(subscription.filter { $0 == .authenticateConnection }.count == 1)
        #expect(machine.authenticationRequestCount == 1)
        #expect(machine.send(.authenticationAccepted).contains(.loadHistoryPlan))

        let overlap = HistoryRequestPlan(startingIndex: 42, source: .committedOverlap)
        _ = machine.send(.historyPlanLoaded(overlap))
        let request = machine.send(.historyRequestDurablyPrepared(overlap))
        #expect(request.filter { $0 == .requestHistory(overlap) }.count == 1)
        #expect(machine.historyRequestCount == 1)
        #expect(machine.send(.historyRequestDurablyPrepared(overlap)).contains {
            if case .fail(.invalidTransition) = $0 { return true }
            return false
        })
    }

    @Test func disconnectFromEveryConnectionPhaseSchedulesExactlyOneReconnect() {
        let phases: [GS3ForegroundPhase] = [
            .connecting,
            .discoveringServices,
            .discoveringCharacteristics,
            .subscribing,
            .authenticating,
            .loadingHistoryPlan,
            .preparingHistoryRequest,
            .requestingHistory,
            .synchronizing,
            .live,
        ]

        for phase in phases {
            var machine = machine(at: phase)
            let effects = machine.send(.disconnected(.linkLoss))
            #expect(machine.phase == .backoff, "phase \(phase) did not enter backoff")
            #expect(effects.filter(isReconnectSchedule).count == 1)
            #expect(effects.filter { $0 == .ensureTransportDisconnected }.count == 1)
            #expect(effects.contains(.publishConnection(.disconnected)))
            #expect(machine.send(.disconnected(.linkLoss)).isEmpty)
        }

        var idle = GS3ForegroundSessionMachine(sessionOrdinal: 1)
        #expect(idle.send(.disconnected(.linkLoss)).isEmpty)
        _ = idle.send(.start)
        #expect(idle.send(.disconnected(.linkLoss)).contains {
            if case .fail(.invalidTransition(from: .acquiringOwnership)) = $0 { return true }
            return false
        })
        _ = idle.send(.ownershipAcquired)
        let firstDisconnect = idle.send(.disconnected(.linkLoss))
        #expect(firstDisconnect.filter(isReconnectSchedule).count == 1)
        #expect(idle.send(.disconnected(.linkLoss)).isEmpty)
        _ = idle.send(.stop)
        #expect(idle.send(.disconnected(.linkLoss)).isEmpty)

        var disconnecting = machine(at: .connecting)
        _ = disconnecting.send(.foregroundEnded)
        let controlledCompletion = disconnecting.send(.disconnected(.linkLoss))
        #expect(controlledCompletion.contains(.releaseOwnership))
        #expect(controlledCompletion.filter(isReconnectSchedule).isEmpty)
        #expect(disconnecting.phase == .stopped)
        #expect(!disconnecting.hasOwnership)
    }

    @Test func reconnectBackoffIsBoundedAndReleasesOwnershipWhenExhausted() throws {
        let policy = try GS3ReconnectPolicy(delaysSeconds: [0.5, 1])
        var machine = GS3ForegroundSessionMachine(sessionOrdinal: 2, reconnectPolicy: policy)
        _ = machine.send(.start)
        _ = machine.send(.ownershipAcquired)

        for expectedAttempt in 1...2 {
            let effects = machine.send(.disconnected(.timeout))
            let schedule = try #require(reconnectSchedule(in: effects))
            #expect(schedule.attempt == expectedAttempt)
            #expect(machine.phase == .backoff)
            _ = machine.send(.reconnectDelayElapsed(token: schedule.token))
            #expect(machine.phase == .connecting)
        }

        let exhausted = machine.send(.disconnected(.timeout))
        #expect(machine.phase == .stopped)
        #expect(machine.stopReason == .reconnectExhausted)
        #expect(!machine.hasOwnership)
        #expect(exhausted.contains(.releaseOwnership))
        #expect(exhausted.filter(isReconnectSchedule).isEmpty)
    }

    @Test func foregroundEndCancelsPendingReconnectDisconnectsAndReleasesOwnership() throws {
        var backoff = machine(at: .connecting)
        let schedule = try #require(
            reconnectSchedule(in: backoff.send(.disconnected(.timeout)))
        )
        let stopped = backoff.send(.foregroundEnded)
        #expect(stopped.contains(.cancelReconnect(token: schedule.token)))
        #expect(stopped.contains(.releaseOwnership))
        #expect(stopped.contains(.publishConnection(.disconnected)))
        #expect(backoff.stopReason == .foregroundEnded)
        #expect(backoff.send(.reconnectDelayElapsed(token: schedule.token)).isEmpty)
        #expect(backoff.send(.start).contains(.fail(.invalidTransition(from: .stopped))))

        var connected = machine(at: .authenticating)
        let connectedStop = connected.send(.foregroundEnded)
        #expect(connectedStop.contains(.ensureTransportDisconnected))
        #expect(!connectedStop.contains(.releaseOwnership))
        #expect(connected.phase == .disconnecting)
        #expect(connected.hasOwnership)
        let disconnected = connected.send(.transportDisconnected)
        #expect(disconnected.contains(.releaseOwnership))
        #expect(connected.phase == .stopped)
        #expect(!connected.hasOwnership)
    }

    @Test func lateOwnershipAcquisitionAfterForegroundExitIsUnwound() {
        var machine = GS3ForegroundSessionMachine(sessionOrdinal: 8)
        _ = machine.send(.start)
        _ = machine.send(.foregroundEnded)

        let late = machine.send(.ownershipAcquired)
        #expect(late.first == .releaseOwnership)
        #expect(late.contains(.fail(.invalidTransition(from: .stopped))))
        #expect(machine.phase == .stopped)
        #expect(!machine.hasOwnership)
    }

    @Test func lateTransportConnectionAfterForegroundExitIsDisconnectedAgain() {
        var machine = machine(at: .connecting)
        _ = machine.send(.foregroundEnded)

        let late = machine.send(.connected)
        #expect(late.first == .ensureTransportDisconnected)
        #expect(late.contains(.fail(.invalidTransition(from: .disconnecting))))
        #expect(machine.phase == .disconnecting)
        #expect(machine.hasOwnership)
        let completed = machine.send(.transportDisconnected)
        #expect(completed.contains(.releaseOwnership))
        #expect(machine.phase == .stopped)
        #expect(!machine.hasOwnership)
    }

    @Test func terminalFailuresNeverReconnect() {
        for reason in [
            GS3DisconnectReason.permissionDenied,
            .authenticationRejected,
            .protocolViolation,
        ] {
            var machine = machine(at: .authenticating)
            let effects = machine.send(.disconnected(reason))
            #expect(machine.phase == .stopped)
            #expect(!machine.hasOwnership)
            #expect(effects.contains(.releaseOwnership))
            #expect(effects.filter(isReconnectSchedule).isEmpty)
        }
    }

    @Test func persistenceFailureIsPayloadFreeTerminalAndNeverReconnects() {
        for phase in [
            GS3ForegroundPhase.loadingHistoryPlan,
            .preparingHistoryRequest,
            .requestingHistory,
            .synchronizing,
            .live,
        ] {
            var machine = machine(at: phase)
            let effects = machine.send(.persistenceFailed)
            #expect(machine.phase == .disconnecting)
            #expect(machine.stopReason == .persistenceFailure)
            #expect(machine.hasOwnership)
            #expect(!effects.contains(.fail(.persistenceFailure)))
            #expect(effects.contains(.ensureTransportDisconnected))
            #expect(!effects.contains(.releaseOwnership))
            #expect(effects.filter(isReconnectSchedule).isEmpty)
            for effect in effects {
                #expect(!effect.description.contains("raw-private-store-error"))
            }
            let completed = machine.send(.transportDisconnected)
            #expect(completed.contains(.releaseOwnership))
            #expect(completed.last == .fail(.persistenceFailure))
            #expect(machine.phase == .stopped)
            #expect(!machine.hasOwnership)
        }
    }

    @Test func historyCursorUsesCaptureThenPreparedThenCommittedOverlap() {
        let sensorID = UUID()
        var session = SensorSession(id: UUID(), sensorID: sensorID)
        let capture = HistoryCursorPolicy.plan(session: session, captureBackedStart: anchor)
        #expect(capture.startingIndex == anchor.sensorIndex)
        #expect(capture.source == .captureBacked)

        session.lastRequestedIndex = 12
        let prepared = HistoryCursorPolicy.plan(session: session, captureBackedStart: anchor)
        #expect(prepared.startingIndex == 12)
        #expect(prepared.source == .durablyPrepared)

        session.lastCommittedIndex = 20
        let overlap = HistoryCursorPolicy.plan(session: session, captureBackedStart: anchor)
        #expect(overlap.startingIndex == 20)
        #expect(overlap.source == .committedOverlap)
    }

    @Test func lifecycleAndHistoryDiagnosticsDoNotRevealIndexesOrArbitraryErrors() {
        let privateIndexText = "424242"
        let plan = HistoryRequestPlan(startingIndex: anchor.sensorIndex, source: .captureBacked)
        let input = GS3ForegroundInput.historyPlanLoaded(plan)
        let effect = GS3ForegroundEffect.requestHistory(plan)
        var machine = machine(at: .loadingHistoryPlan)
        _ = machine.send(.historyPlanLoaded(plan))
        let event = GS3LifecycleEvent(
            sessionOrdinal: 2,
            connectionOrdinal: 3,
            elapsedWholeSeconds: 44,
            phase: .backoff,
            kind: .reconnectScheduled,
            disconnectReason: .otherRedacted,
            reconnectAttempt: 1,
            authenticationRequestCount: 1,
            historyRequestCount: 1,
            historyPreambleCount: 1,
            insertedSampleCount: 5,
            duplicateSampleCount: 2,
            gapRangeCount: 1
        )

        var dumpedPlan = ""
        dump(plan, to: &dumpedPlan)
        var dumpedAnchor = ""
        dump(anchor, to: &dumpedAnchor)
        var dumpedInput = ""
        dump(input, to: &dumpedInput)
        var dumpedEffect = ""
        dump(effect, to: &dumpedEffect)
        var dumpedEvent = ""
        dump(event, to: &dumpedEvent)
        for text in [
            anchor.description,
            String(reflecting: anchor),
            dumpedAnchor,
            plan.description,
            String(reflecting: plan),
            dumpedPlan,
            input.description,
            String(reflecting: input),
            dumpedInput,
            effect.description,
            String(reflecting: effect),
            dumpedEffect,
            machine.description,
            event.description,
            String(reflecting: event),
            dumpedEvent,
        ] {
            #expect(!text.contains(privateIndexText))
            #expect(!text.contains("sensor-identifier-secret"))
            #expect(!text.contains("raw-private-error"))
        }
        #expect(event.description.contains("other error redacted"))
        #expect(event.description.contains("historyPreambles=1"))
    }

    @Test func presentationProjectionKeepsBackoffDisconnectedAndEventuallyStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID()
        let sample = GlucoseSample(
            sessionID: sessionID,
            sensorIndex: 1,
            sensorTimestamp: now.addingTimeInterval(-30),
            receiptTimestamp: now.addingTimeInterval(-30),
            milligramsPerDeciliter: 100,
            trend: .stable,
            quality: .ok,
            source: .live,
            decoderRevision: "synthetic"
        )
        let safety = SafetyEngine(policy: SafetyPolicy(staleAfterSeconds: 600))
        var machine = machine(at: .live)
        let current = safety.evaluate(
            now: now,
            connection: machine.presentationConnectionState,
            lifecycle: .live,
            latestSample: sample
        )
        #expect(current.showsValueAsCurrent)

        _ = machine.send(.disconnected(.linkLoss))
        let disconnected = safety.evaluate(
            now: now,
            connection: machine.presentationConnectionState,
            lifecycle: .live,
            latestSample: sample
        )
        #expect(disconnected.isDisconnected)
        #expect(!disconnected.showsValueAsCurrent)

        let stale = safety.evaluate(
            now: now.addingTimeInterval(1_200),
            connection: machine.presentationConnectionState,
            lifecycle: .live,
            latestSample: sample
        )
        #expect(stale.isDisconnected)
        #expect(stale.isStale)
        #expect(!stale.showsValueAsCurrent)
    }

    @Test func mismatchedPreparedHistoryPlanFailsClosedWithoutARequest() {
        var machine = machine(at: .preparingHistoryRequest)
        let other = HistoryRequestPlan(startingIndex: 999, source: .captureBacked)
        let effects = machine.send(.historyRequestDurablyPrepared(other))
        #expect(!effects.contains(.fail(.mismatchedHistoryPlan)))
        #expect(effects.contains(.ensureTransportDisconnected))
        #expect(!effects.contains(.releaseOwnership))
        #expect(effects.contains(.publishConnection(.disconnected)))
        #expect(effects.contains {
            if case .record(let event) = $0, event.kind == .integrityFailure { return true }
            return false
        })
        #expect(effects.filter(isReconnectSchedule).isEmpty)
        #expect(machine.phase == .disconnecting)
        #expect(machine.stopReason == .integrityFailure)
        #expect(machine.hasOwnership)
        #expect(machine.historyRequestCount == 0)
        let completed = machine.send(.transportDisconnected)
        #expect(completed.contains(.releaseOwnership))
        #expect(completed.last == .fail(.mismatchedHistoryPlan))
        #expect(machine.phase == .stopped)
        #expect(!machine.hasOwnership)
    }

    private func machine(at target: GS3ForegroundPhase) -> GS3ForegroundSessionMachine {
        var machine = GS3ForegroundSessionMachine(sessionOrdinal: 1)
        if target == .idle { return machine }
        _ = machine.send(.start)
        if target == .acquiringOwnership { return machine }
        _ = machine.send(.ownershipAcquired)
        if target == .connecting { return machine }
        _ = machine.send(.connected)
        if target == .discoveringServices { return machine }
        _ = machine.send(.servicesDiscovered)
        if target == .discoveringCharacteristics { return machine }
        _ = machine.send(.characteristicsDiscovered)
        if target == .subscribing { return machine }
        _ = machine.send(.notificationSubscriptionEnabled)
        if target == .authenticating { return machine }
        _ = machine.send(.authenticationAccepted)
        if target == .loadingHistoryPlan { return machine }
        let plan = HistoryRequestPlan(startingIndex: anchor.sensorIndex, source: .captureBacked)
        _ = machine.send(.historyPlanLoaded(plan))
        if target == .preparingHistoryRequest { return machine }
        _ = machine.send(.historyRequestDurablyPrepared(plan))
        if target == .requestingHistory { return machine }
        _ = machine.send(.historyAcknowledged)
        if target == .synchronizing { return machine }
        _ = machine.send(.synchronizationCompleted)
        return machine
    }

    private func reconnectSchedule(
        in effects: [GS3ForegroundEffect]
    ) -> GS3ReconnectSchedule? {
        effects.compactMap { effect in
            if case .scheduleReconnect(let schedule) = effect { return schedule }
            return nil
        }.first
    }

    private func isReconnectSchedule(_ effect: GS3ForegroundEffect) -> Bool {
        if case .scheduleReconnect = effect { return true }
        return false
    }
}
