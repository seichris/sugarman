// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Session

/// The allowlisted, payload-free fields that the app may persist for one
/// lifecycle event. This keeps the production app independent of the module
/// that defines the event while preserving the existing privacy boundary.
public extension GS3LifecycleEvent {
    var localDiagnosticAttributes: [String: String] {
        var attributes: [String: String] = [
            "session_ordinal": String(sessionOrdinal),
            "connection_ordinal": String(connectionOrdinal),
            "elapsed_seconds": String(elapsedWholeSeconds),
            "phase": phase.rawValue,
            "kind": kind.rawValue,
            "reconnect_attempt": String(reconnectAttempt),
            "authentication_requests": String(authenticationRequestCount),
            "history_requests": String(historyRequestCount),
            "history_preambles": String(historyPreambleCount),
            "inserted_samples": String(insertedSampleCount),
            "duplicate_samples": String(duplicateSampleCount),
            "gap_ranges": String(gapRangeCount),
        ]
        if let disconnectReason {
            attributes["disconnect_reason"] = localDiagnosticDisconnectReason(disconnectReason)
        }
        if let protocolRejection {
            attributes["rejection_origin"] = protocolRejection.origin.rawValue
            attributes["rejection_frame_category"] = protocolRejection.frameCategory.rawValue
            attributes["rejection_timing_window"] = protocolRejection.timingWindow.rawValue
            attributes["rejection_frame_bytes"] = protocolRejection.frameByteCount.map(String.init)
                ?? "unavailable"
            attributes["rejection_frame_bytes_capped"] =
                String(protocolRejection.frameByteCountWasCapped)
        }
        return attributes
    }
}

private func localDiagnosticDisconnectReason(_ reason: GS3DisconnectReason) -> String {
    switch reason {
    case .linkLoss:
        "link_loss"
    case .timeout:
        "timeout"
    case .coreBluetooth(let code):
        "core_bluetooth_\(code)"
    case .bluetoothUnavailable:
        "bluetooth_unavailable"
    case .permissionDenied:
        "permission_denied"
    case .authenticationRejected:
        "authentication_rejected"
    case .protocolViolation:
        "protocol_violation"
    case .otherRedacted:
        "other_redacted"
    }
}
