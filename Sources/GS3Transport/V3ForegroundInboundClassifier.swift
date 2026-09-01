// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import GS3Protocol
import GS3Session

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
        guard authenticationAccepted,
              !historyControlAcknowledged,
              !historyReadyEmitted,
              !hasReceivedGlucoseBatch,
              historyPreambleCount == 0 else {
            return false
        }

        let authenticatedBeforeHistoryDispatch = !isAwaitingHistory
            && historyWriteCallCount == 0
            && !historyWriteAcknowledgementPending
        let pendingHistoryWrite = isAwaitingHistory
            && historyWriteCallCount == 1
            && historyWriteAcknowledgementPending
        return authenticatedBeforeHistoryDispatch || pendingHistoryWrite
    }
}

package enum V3ForegroundInboundClassification: Sendable, Equatable {
    case control(V3ControlResponse)
    case glucose(V3GlucoseBatch)
    case observedHistoryPreamble
}

/// An allowlisted, payload-free reason the otherwise exact observed preamble
/// was rejected. No case can carry a packet, command byte, index, or material.
package enum V3ForegroundInboundClassifierError: Error, Sendable, Equatable {
    case observedHistoryPreambleOutsideAllowedWindow
}

/// Pure, host-testable inbound policy for the foreground transport.
///
/// Public capture evidence does not establish the product meaning of command
/// `0x36`. It does establish checksum-valid 24-byte occurrences immediately
/// after authentication, including one that overtook dispatch of the sole
/// typed history write after the coordinator had durably prepared that
/// request. The classifier therefore recognizes that exact shape in either
/// adjacent transport window once per connection. The coordinator separately
/// requires its durable history-request state before accepting the event. The
/// event carries no payload and grants no write, retry, glucose, or readiness
/// semantics. Every other unsupported or malformed notification still throws
/// and remains terminal.
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
                  frame.byteCount == observedHistoryPreambleByteCount else {
                throw error
            }
            guard context.permitsObservedHistoryPreamble else {
                throw V3ForegroundInboundClassifierError
                    .observedHistoryPreambleOutsideAllowedWindow
            }
            return .observedHistoryPreamble
        }
    }

    package static func rejectionFrameCategory(
        for error: any Error,
        frameByteCount: Int
    ) -> GS3ProtocolFrameCategory {
        if let classifierError = error as? V3ForegroundInboundClassifierError,
           classifierError == .observedHistoryPreambleOutsideAllowedWindow {
            return .observedHistoryPreambleCandidate
        }
        return .classify(byteCount: frameByteCount)
    }
}
