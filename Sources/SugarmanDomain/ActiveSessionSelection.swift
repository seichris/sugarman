// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Chooses the active sensor session without UUID-sorting the session list.
///
/// Preference order:
/// 1. `demoSessionID` when that session still exists
/// 2. `selectedSessionID` when that session still exists
/// 3. the only remaining session
/// 4. the most recently created session (`activatedAt`)
public enum ActiveSessionSelection: Sendable {
    public static func resolve(
        sessions: [SensorSession],
        demoSessionID: UUID?,
        selectedSessionID: UUID?
    ) -> UUID? {
        let ids = Set(sessions.map(\.id))
        if let demoSessionID, ids.contains(demoSessionID) {
            return demoSessionID
        }
        if let selectedSessionID, ids.contains(selectedSessionID) {
            return selectedSessionID
        }
        if sessions.count == 1 {
            return sessions[0].id
        }
        if sessions.isEmpty {
            return nil
        }
        var best: SensorSession?
        for session in sessions {
            guard let current = best else {
                best = session
                continue
            }
            let currentDate = current.activatedAt ?? .distantPast
            let candidateDate = session.activatedAt ?? .distantPast
            if candidateDate > currentDate {
                best = session
            }
        }
        return best?.id
    }

    /// Explicit selection after inserting a session: keep a still-valid
    /// selection, otherwise take the inserted id (also when it is the only
    /// session).
    public static func selectionAfterInsert(
        insertedID: UUID,
        sessions: [SensorSession],
        currentSelection: UUID?
    ) -> UUID {
        let ids = Set(sessions.map(\.id))
        if sessions.count == 1, ids.contains(insertedID) {
            return insertedID
        }
        if let currentSelection, ids.contains(currentSelection) {
            return currentSelection
        }
        return insertedID
    }
}
