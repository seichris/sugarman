// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Protocol

/// The payload-free connection state needed to classify one empirically
/// observed history preamble without weakening the general decoder policy.
package struct V3ForegroundInboundContext: Sendable, Equatable {
    package let isAwaitingHistory: Bool
    package let authenticationAccepted: Bool
    package let historyWriteCallCount: Int
    package let historyWriteAcknowledgementPending: Bool
    package let historyControlAcknowledged: Bool
    package let historyReadyEmitted: Bool
    package let hasReceivedGlucoseBatch: Bool
    package let historyPreambleCount: Int

    package init(
        isAwaitingHistory: Bool,
        authenticationAccepted: Bool,
        historyWriteCallCount: Int,
        historyWriteAcknowledgementPending: Bool,
        historyControlAcknowledged: Bool,
        historyReadyEmitted: Bool,
        hasReceivedGlucoseBatch: Bool,
        historyPreambleCount: Int
    ) {
        self.isAwaitingHistory = isAwaitingHistory
        self.authenticationAccepted = authenticationAccepted
        self.historyWriteCallCount = historyWriteCallCount
        self.historyWriteAcknowledgementPending = historyWriteAcknowledgementPending
        self.historyControlAcknowledged = historyControlAcknowledged
        self.historyReadyEmitted = historyReadyEmitted
        self.hasReceivedGlucoseBatch = hasReceivedGlucoseBatch
        self.historyPreambleCount = historyPreambleCount
    }

    fileprivate var permitsObservedHistoryPreamble: Bool {
        isAwaitingHistory
            && authenticationAccepted
            && historyWriteCallCount == 1
            && historyWriteAcknowledgementPending
            && !historyControlAcknowledged
            && !historyReadyEmitted
            && !hasReceivedGlucoseBatch
            && historyPreambleCount == 0
    }
}

package enum V3ForegroundInboundClassification: Sendable, Equatable {
    case control(V3ControlResponse)
    case glucose(V3GlucoseBatch)
    case observedHistoryPreamble
}

/// Pure, host-testable inbound policy for the foreground transport.
///
/// Public capture evidence does not establish the product meaning of command
/// `0x36`. It does establish one checksum-valid 24-byte occurrence while the
/// sole typed history write acknowledgement was pending, followed by valid
/// history and live data. The classifier therefore recognizes that exact
/// shape and window once per connection, emits no payload, and grants no
/// write, retry, glucose, or readiness semantics. Every other unsupported or
/// malformed notification still throws and remains terminal.
package enum V3ForegroundInboundClassifier: Sendable {
    package static let observedHistoryPreambleCommand: UInt8 = 0x36
    package static let observedHistoryPreambleByteCount = 24

    package static func classify(
        _ frame: EncodedFrame,
        using material: V3ActiveSessionMaterial,
        context: V3ForegroundInboundContext
    ) throws -> V3ForegroundInboundClassification {
        if frame.byteCount == 5 {
            return .control(try material.decodeControl(frame))
        }

        do {
            return .glucose(try material.decodeGlucose(frame))
        } catch {
            guard let protocolError = error as? GS3ProtocolError,
                  protocolError == .unsupportedV3NotificationCommand(
                      observedHistoryPreambleCommand
                  ),
                  frame.byteCount == observedHistoryPreambleByteCount,
                  context.permitsObservedHistoryPreamble else {
                throw error
            }
            return .observedHistoryPreamble
        }
    }
}
