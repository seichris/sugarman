// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Shows only the last characters of a serial. Full serials must not be stored
/// or shown in the UI.
public enum SerialRedaction: Sendable {
    public static func redact(_ serial: String, visibleTail: Int = 4) -> String {
        let trimmed = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "…"
        }
        if trimmed.hasPrefix("…") {
            return trimmed
        }
        if trimmed.count <= visibleTail {
            return "…" + trimmed
        }
        return "…" + String(trimmed.suffix(visibleTail))
    }
}
