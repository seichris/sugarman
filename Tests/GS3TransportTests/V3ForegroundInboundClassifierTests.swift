// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Testing
@testable import GS3Protocol
@testable import GS3Session
@testable import GS3Transport

struct V3ForegroundInboundClassifierTests {
    @Test func notificationOvertakingHistoryDispatchRemainsTerminalAndDiagnosable() throws {
        let material = try syntheticActiveSessionMaterial()
        let frame = try syntheticUnsupportedNotification(command: 0x36)
        let authenticatedBeforeHistoryDispatch = V3ForegroundInboundContext(
            isAwaitingHistory: false,
            authenticationAccepted: true,
            historyWriteCallCount: 0,
            historyWriteAcknowledgementPending: false,
            historyControlAcknowledged: false,
            historyReadyEmitted: false,
            hasReceivedGlucoseBatch: false,
            historyPreambleCount: 0
        )

        #expect(
            throws: V3ForegroundInboundClassifierError
                .observedHistoryPreambleOutsideAllowedWindow
        ) {
            try V3ForegroundInboundClassifier.classify(
                frame,
                using: material,
                context: authenticatedBeforeHistoryDispatch
            )
        }

        let rejection = GS3ProtocolRejection(
            origin: .inboundClassification,
            frameCategory: .observedHistoryPreambleCandidate,
            frameByteCount: frame.byteCount,
            timingWindow: .authenticated
        )
        #expect(
            rejection.description
                == "origin=inboundClassification, "
                    + "frame=observedHistoryPreambleCandidate, "
                    + "bytes=24, window=authenticated"
        )
        #expect(
            V3ForegroundInboundClassifier.rejectionFrameCategory(
                for: V3ForegroundInboundClassifierError
                    .observedHistoryPreambleOutsideAllowedWindow,
                frameByteCount: frame.byteCount
            ) == .observedHistoryPreambleCandidate
        )
    }

    @Test func exactObservedHistoryPreambleIsAcceptedOnlyInPendingWriteWindow() throws {
        let material = try syntheticActiveSessionMaterial()
        let frame = try syntheticUnsupportedNotification(command: 0x36)

        #expect(
            try V3ForegroundInboundClassifier.classify(
                frame,
                using: material,
                context: pendingHistoryWriteContext()
            ) == .observedHistoryPreamble
        )

        let disallowedContexts = [
            pendingHistoryWriteContext(isAwaitingHistory: false),
            pendingHistoryWriteContext(authenticationAccepted: false),
            pendingHistoryWriteContext(historyWriteCallCount: 0),
            pendingHistoryWriteContext(historyWriteCallCount: 2),
            pendingHistoryWriteContext(historyWriteAcknowledgementPending: false),
            pendingHistoryWriteContext(historyControlAcknowledged: true),
            pendingHistoryWriteContext(historyReadyEmitted: true),
            pendingHistoryWriteContext(hasReceivedGlucoseBatch: true),
            pendingHistoryWriteContext(historyPreambleCount: 1),
        ]
        for context in disallowedContexts {
            #expect(
                throws: V3ForegroundInboundClassifierError
                    .observedHistoryPreambleOutsideAllowedWindow
            ) {
                try V3ForegroundInboundClassifier.classify(
                    frame,
                    using: material,
                    context: context
                )
            }
        }
    }

    @Test func malformedOrDifferentUnsupportedNotificationsRemainTerminal() throws {
        let material = try syntheticActiveSessionMaterial()
        let context = pendingHistoryWriteContext()

        #expect(throws: GS3ProtocolError.unsupportedV3NotificationCommand(0x31)) {
            try V3ForegroundInboundClassifier.classify(
                syntheticUnsupportedNotification(command: 0x31),
                using: material,
                context: context
            )
        }
        #expect(throws: GS3ProtocolError.unsupportedV3NotificationCommand(0x36)) {
            try V3ForegroundInboundClassifier.classify(
                syntheticUnsupportedNotification(command: 0x36, byteCount: 25),
                using: material,
                context: context
            )
        }

        var invalidChecksum = try syntheticUnsupportedNotification(command: 0x36).bytes
        invalidChecksum[invalidChecksum.count - 1] &+= 1
        #expect(throws: GS3ProtocolError.invalidV3GlucoseNotificationChecksum) {
            try V3ForegroundInboundClassifier.classify(
                EncodedFrame(bytes: invalidChecksum),
                using: material,
                context: context
            )
        }

        #expect(
            V3ForegroundInboundClassifier.rejectionFrameCategory(
                for: GS3ProtocolError.unsupportedV3NotificationCommand(0x31),
                frameByteCount: 24
            ) == .notificationCandidate
        )
        #expect(
            V3ForegroundInboundClassifier.rejectionFrameCategory(
                for: GS3ProtocolError.invalidV3GlucoseNotificationChecksum,
                frameByteCount: 24
            ) == .notificationCandidate
        )
    }

    private func pendingHistoryWriteContext(
        isAwaitingHistory: Bool = true,
        authenticationAccepted: Bool = true,
        historyWriteCallCount: Int = 1,
        historyWriteAcknowledgementPending: Bool = true,
        historyControlAcknowledged: Bool = false,
        historyReadyEmitted: Bool = false,
        hasReceivedGlucoseBatch: Bool = false,
        historyPreambleCount: Int = 0
    ) -> V3ForegroundInboundContext {
        V3ForegroundInboundContext(
            isAwaitingHistory: isAwaitingHistory,
            authenticationAccepted: authenticationAccepted,
            historyWriteCallCount: historyWriteCallCount,
            historyWriteAcknowledgementPending: historyWriteAcknowledgementPending,
            historyControlAcknowledged: historyControlAcknowledged,
            historyReadyEmitted: historyReadyEmitted,
            hasReceivedGlucoseBatch: hasReceivedGlucoseBatch,
            historyPreambleCount: historyPreambleCount
        )
    }

    private func syntheticActiveSessionMaterial() throws -> V3ActiveSessionMaterial {
        try V3ActiveSessionMaterial(
            sensorAddress: Array(1...6),
            authenticationID: Array(0x20...0x2B),
            registeredBlock: Array(0x30...0x3F),
            algorithmKey: Array(0x40...0x4F),
            algorithmInitializationVector: Array(0x50...0x5F)
        )
    }

    private func syntheticUnsupportedNotification(
        command: UInt8,
        byteCount: Int = 24
    ) throws -> EncodedFrame {
        var plaintext = [UInt8](repeating: 0, count: byteCount)
        plaintext[0] = UInt8(byteCount - 1)
        plaintext[1] = command
        plaintext[byteCount - 1] = UInt8.zero &- plaintext.dropLast().reduce(0, &+)
        return EncodedFrame(
            bytes: try AES128OFB.crypt(
                plaintext,
                key: V3ProtocolConstants.fixedKey,
                initializationVector: Array(1...6) + [UInt8](repeating: 0, count: 10)
            )
        )
    }
}
