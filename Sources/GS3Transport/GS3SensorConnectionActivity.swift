// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Session
import SugarmanDomain

public extension SensorConnectionActivity {
    init(phase: GS3ForegroundPhase) {
        switch phase {
        case .idle, .stopped:
            self = .stopped
        case .acquiringOwnership, .connecting, .discoveringServices,
             .discoveringCharacteristics, .subscribing, .authenticating:
            self = .connecting
        case .loadingHistoryPlan, .preparingHistoryRequest, .requestingHistory,
             .synchronizing:
            self = .synchronizing
        case .live:
            self = .live
        case .backoff:
            self = .reconnecting
        case .disconnecting:
            self = .reconnecting
        }
    }
}
