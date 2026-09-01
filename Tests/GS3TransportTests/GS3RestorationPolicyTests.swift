// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Session
import SugarmanDomain
import Testing
@testable import GS3Transport

struct GS3RestorationPolicyTests {
    @Test func persistentPolicyResumesEveryKnownPeripheralStateWithoutChurn() {
        #expect(GS3RestorationPolicy.action(
            for: .disconnected,
            persistentConnection: true
        ) == .connect)
        #expect(GS3RestorationPolicy.action(
            for: .connecting,
            persistentConnection: true
        ) == .awaitConnection)
        #expect(GS3RestorationPolicy.action(
            for: .connected,
            persistentConnection: true
        ) == .resumeConnected)
        #expect(GS3RestorationPolicy.action(
            for: .disconnecting,
            persistentConnection: true
        ) == .awaitDisconnection)
    }

    @Test func restorationAcceptsOnlyTheConfiguredKnownPeer() {
        #expect(GS3RestorationPolicy.acceptsRestoredPeripheral(
            identifierMatches: true,
            persistentConnection: true
        ))
        #expect(!GS3RestorationPolicy.acceptsRestoredPeripheral(
            identifierMatches: false,
            persistentConnection: true
        ))
        #expect(!GS3RestorationPolicy.acceptsRestoredPeripheral(
            identifierMatches: true,
            persistentConnection: false
        ))
    }

    @Test func foregroundPolicyPreservesFreshConnectBehavior() {
        for state in GS3KnownPeripheralState.allCases {
            #expect(GS3RestorationPolicy.action(
                for: state,
                persistentConnection: false
            ) == .connect)
        }
    }

    @Test func everyCoordinatorPhaseHasOneTypedUserVisibleProjection() {
        for phase in GS3ForegroundPhase.allCases {
            let activity = SensorConnectionActivity(phase: phase)
            #expect(SensorConnectionActivity.allCases.contains(activity))
        }
        #expect(SensorConnectionActivity(phase: .connecting) == .connecting)
        #expect(SensorConnectionActivity(phase: .requestingHistory) == .synchronizing)
        #expect(SensorConnectionActivity(phase: .backoff) == .reconnecting)
        #expect(SensorConnectionActivity(phase: .live) == .live)
    }
}
