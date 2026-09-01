// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

package enum GS3KnownPeripheralState: Sendable, Equatable, CaseIterable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

package enum GS3KnownPeripheralAction: Sendable, Equatable {
    case connect
    case awaitConnection
    case resumeConnected
    case awaitDisconnection
}

/// Pure, identity-free policy shared by restoration code and host tests.
package enum GS3RestorationPolicy {
    package static func action(
        for state: GS3KnownPeripheralState,
        persistentConnection: Bool
    ) -> GS3KnownPeripheralAction {
        guard persistentConnection else { return .connect }
        switch state {
        case .disconnected: return .connect
        case .connecting: return .awaitConnection
        case .connected: return .resumeConnected
        case .disconnecting: return .awaitDisconnection
        }
    }

    package static func acceptsRestoredPeripheral(
        identifierMatches: Bool,
        persistentConnection: Bool
    ) -> Bool {
        persistentConnection && identifierMatches
    }
}
