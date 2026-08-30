// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
@testable import GS3DeveloperProbe
@testable import GS3Protocol

struct GS3DeveloperProbeTests {
    @Test func disconnectDiagnosticIsPayloadFreeAndDistinguishesRuns() {
        let diagnostic = V3ProbeDisconnectDiagnostic(
            sessionOrdinal: 2,
            elapsedWholeSeconds: 147,
            state: .awaitingEffectiveData,
            transportError: .coreBluetooth(code: 6),
            authenticationWriteCallCount: 1,
            effectiveDataWriteCallCount: 1,
            uniqueLiveReadingCount: 1,
            quarantinedCommandCount: 1
        )

        #expect(
            diagnostic.description
                == "Session #2 disconnected unexpectedly after 147 seconds; "
                    + "state=awaiting effective data; transport=CoreBluetooth code 6; "
                    + "CoreBluetooth write calls E2=1, 0x39=1; unique live=1; "
                    + "quarantined commands=1."
        )
        #expect(!diagnostic.description.contains("glucose-secret"))
        #expect(!diagnostic.description.contains("record-index-secret"))
        #expect(!diagnostic.description.contains("sensor-identifier"))

        let redactedOther = V3ProbeDisconnectDiagnostic(
            sessionOrdinal: 3,
            elapsedWholeSeconds: 1,
            state: .subscribing,
            transportError: .redactedOther,
            authenticationWriteCallCount: 0,
            effectiveDataWriteCallCount: 0,
            uniqueLiveReadingCount: 0,
            quarantinedCommandCount: 0
        )
        #expect(redactedOther.description.contains("non-CoreBluetooth error redacted"))
        #expect(redactedOther.description.contains("Session #3"))
    }

    @Test func privateImportNormalizesAndRedactsEverySensitiveField() throws {
        let json = """
        {
          "schemaVersion": 1,
          "expectedPeripheralName": "SYNTHETIC_V3",
          "sensorAddressHex": "010203040506",
          "authenticationIDHex": "202122232425262728292a2b",
          "registeredBlockHex": "303132333435363738393a3b3c3d3e3f",
          "algorithmKeyHex": "404142434445464748494a4b4c4d4e4f",
          "algorithmIVHex": "505152535455565758595a5b5c5d5e5f",
          "effectiveDataStartIndex": 4660
        }
        """
        let material = try V3ProbeMaterial(importJSONData: Data(json.utf8))
        let stored = material.encodedForStorage()
        let restored = try V3ProbeMaterial(storedData: stored)
        var dumped = ""
        dump(restored, to: &dumped)

        #expect(restored.expectedPeripheralName == "SYNTHETIC_V3")
        #expect(restored.effectiveDataStartIndex == 4660)
        #expect(restored.sensorAddress == Array(1...6))
        #expect(!String(describing: restored).contains("010203"))
        #expect(!String(reflecting: restored).contains("303132"))
        #expect(!dumped.contains("64, 65"))
        #expect(!dumped.contains("SYNTHETIC_V3"))
    }

    @Test func privateImportRejectsWrongLengthsAndSchema() {
        let shortAddress = syntheticJSON(sensorAddressHex: "0102")
        #expect(
            throws: V3ProbeMaterialError.invalidLength(
                field: "sensorAddressHex",
                expected: 6,
                actual: 2
            )
        ) {
            try V3ProbeMaterial(importJSONData: Data(shortAddress.utf8))
        }

        let wrongSchema = syntheticJSON(schemaVersion: 2)
        #expect(throws: V3ProbeMaterialError.unsupportedSchemaVersion(2)) {
            try V3ProbeMaterial(importJSONData: Data(wrongSchema.utf8))
        }
    }

    @Test func oneShotProbeEmitsOnlySubscribeAuthEffectiveDataAndDisconnect() throws {
        let material = try syntheticMaterial()
        var probe = V3DeveloperHandoverProbe(
            material: material,
            requiredLiveReadingCount: 1
        )

        #expect(try probe.start() == [.subscribeToNotifications])
        let authEffects = try probe.didSubscribe()
        guard case .transmit(.authentication(let authFrame)) = authEffects.first else {
            Issue.record("missing typed authentication transmission")
            return
        }
        #expect(authFrame.byteCount == 38)
        #expect(probe.authenticationTransmissionCount == 1)
        #expect(probe.effectiveDataTransmissionCount == 0)

        let accepted = try encryptedControlResponse(
            command: 0xE2,
            code: 0x01,
            detail: 0x00
        )
        let requestEffects = try probe.didReceive(accepted)
        guard case .transmit(.effectiveData(let requestFrame)) = requestEffects.first else {
            Issue.record("missing typed effective-data transmission")
            return
        }
        #expect(requestFrame.byteCount == 7)
        #expect(probe.authenticationTransmissionCount == 1)
        #expect(probe.effectiveDataTransmissionCount == 1)
        #expect(
            probe.lastPacketDiagnostic == V3ProbePacketDiagnostic(
                stateBefore: .awaitingAuthentication,
                stateAfter: .awaitingEffectiveData,
                classification: .authenticationAccepted,
                byteCount: 5,
                authenticationTransmissionCount: 1,
                effectiveDataTransmissionCount: 1,
                uniqueLiveReadingCount: 0
            )
        )

        let requestPlaintext = try decryptTransport(requestFrame)
        #expect(requestPlaintext == [0x06, 0x39, 0x34, 0x12, 0xFF, 0xFF, 0x7D])

        let acknowledgement = try encryptedControlResponse(
            command: 0x39,
            code: 0x01,
            detail: 0x00
        )
        #expect(try probe.didReceive(acknowledgement).isEmpty)
        #expect(probe.state == .awaitingEffectiveData)
        #expect(probe.lastPacketDiagnostic?.classification == .effectiveDataAcknowledgement)

        let glucose = try encryptedGlucoseBatch(command: 0x32, glucoseTenths: 72)
        let completion = try probe.didReceive(glucose)
        guard case .report(let reading, let count, let required) = completion.first else {
            Issue.record("missing reading")
            return
        }
        #expect(reading.glucoseTenthsMillimolesPerLiter == 72)
        #expect(reading.trendCode == 2)
        #expect(reading.source == .liveNotification)
        #expect(count == 1)
        #expect(required == 1)
        #expect(completion.last == .disconnect)
        #expect(probe.state == .completed)
        #expect(probe.lastPacketDiagnostic?.classification == .liveNotificationBatch)
        #expect(probe.lastPacketDiagnostic?.stateAfter == .completed)
        #expect(probe.authenticationTransmissionCount == 1)
        #expect(probe.effectiveDataTransmissionCount == 1)
        #expect(probe.completionGatePassed)
        #expect(throws: V3ProbeError.invalidTransition(from: .completed)) {
            try probe.didReceive(glucose)
        }
    }

    @Test func effectiveDataBatchCanCompleteProbe() throws {
        var probe = V3DeveloperHandoverProbe(
            material: try syntheticMaterial(),
            requiredLiveReadingCount: 1
        )
        _ = try probe.start()
        _ = try probe.didSubscribe()
        _ = try probe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )

        let batch = try encryptedGlucoseBatch(command: 0x39, glucoseTenths: 98)
        let effects = try probe.didReceive(batch)
        guard case .report(let reading, let count, let required) = effects.first else {
            Issue.record("missing effective-data reading")
            return
        }
        #expect(reading.source == .effectiveData)
        #expect(reading.glucoseTenthsMillimolesPerLiter == 98)
        #expect(count == 0)
        #expect(required == 1)
        #expect(effects.last != .disconnect)

        let live = try encryptedGlucoseBatch(command: 0x32, glucoseTenths: 99)
        #expect(try probe.didReceive(live).last == .disconnect)
    }

    @Test func rejectedAuthenticationNeverEmitsEffectiveDataRequest() throws {
        var probe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try probe.start()
        _ = try probe.didSubscribe()
        let rejected = try encryptedControlResponse(
            command: 0xE2,
            code: 0,
            detail: 5
        )

        #expect(throws: V3ProbeError.authenticationRejected(code: 0, detail: 5)) {
            try probe.didReceive(rejected)
        }
        #expect(probe.state == .failed)
        #expect(probe.authenticationTransmissionCount == 1)
        #expect(probe.effectiveDataTransmissionCount == 0)
    }

    @Test func defaultProbeWaitsForFiveUniqueLiveIndexesWithoutAnotherWrite() throws {
        var probe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try probe.start()
        _ = try probe.didSubscribe()
        _ = try probe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )

        for index in UInt16(1)...UInt16(4) {
            let frame = try encryptedGlucoseBatch(
                command: 0x32,
                glucoseTenths: 72,
                startingIndex: index
            )
            let effects = try probe.didReceive(frame)
            #expect(effects.count == 1)
            #expect(effects.last != .disconnect)
        }
        let duplicate = try encryptedGlucoseBatch(
            command: 0x32,
            glucoseTenths: 72,
            startingIndex: 4
        )
        #expect(try probe.didReceive(duplicate).isEmpty)
        let earlierDuplicate = try encryptedGlucoseBatch(
            command: 0x32,
            glucoseTenths: 72,
            startingIndex: 2
        )
        #expect(try probe.didReceive(earlierDuplicate).isEmpty)
        #expect(probe.uniqueLiveReadingCount == 4)

        let unexpectedPreAuthenticationAcknowledgement = try encryptedControlResponse(
            command: 0x39,
            code: 1,
            detail: 0
        )
        var freshProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try freshProbe.start()
        _ = try freshProbe.didSubscribe()
        let expectedDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingAuthentication,
            stateAfter: .failed,
            classification: .effectiveDataAcknowledgement,
            byteCount: 5,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 0,
            uniqueLiveReadingCount: 0
        )
        #expect(throws: V3ProbeError.unexpectedNotification(expectedDiagnostic)) {
            try freshProbe.didReceive(unexpectedPreAuthenticationAcknowledgement)
        }
        #expect(freshProbe.lastPacketDiagnostic == expectedDiagnostic)
        #expect(freshProbe.state == .failed)

        let fifth = try encryptedGlucoseBatch(
            command: 0x32,
            glucoseTenths: 73,
            startingIndex: 5
        )
        let completion = try probe.didReceive(fifth)
        #expect(completion.count == 2)
        #expect(completion.last == .disconnect)
        #expect(probe.authenticationTransmissionCount == 1)
        #expect(probe.effectiveDataTransmissionCount == 1)
        #expect(probe.uniqueLiveReadingCount == 5)
    }

    @Test func diagnosticsDistinguishDuplicateAuthAndShortFramesWithoutPayloads() throws {
        var duplicateAuthProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try duplicateAuthProbe.start()
        _ = try duplicateAuthProbe.didSubscribe()
        let accepted = try encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        _ = try duplicateAuthProbe.didReceive(accepted)

        let duplicateDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingEffectiveData,
            stateAfter: .failed,
            classification: .authenticationAccepted,
            byteCount: 5,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 1,
            uniqueLiveReadingCount: 0
        )
        #expect(throws: V3ProbeError.unexpectedNotification(duplicateDiagnostic)) {
            try duplicateAuthProbe.didReceive(accepted)
        }
        #expect(duplicateAuthProbe.lastPacketDiagnostic == duplicateDiagnostic)

        var malformedProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try malformedProbe.start()
        _ = try malformedProbe.didSubscribe()
        let malformedDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingAuthentication,
            stateAfter: .failed,
            classification: .glucoseFrameTooShort,
            byteCount: 3,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 0,
            uniqueLiveReadingCount: 0
        )
        let malformed = EncodedFrame(bytes: [0xAA, 0xBB, 0xCC])
        #expect(throws: V3ProbeError.unexpectedNotification(malformedDiagnostic)) {
            try malformedProbe.didReceive(malformed)
        }

        let message = V3ProbeError.unexpectedNotification(malformedDiagnostic)
            .localizedDescription
        #expect(message.contains("glucose frame shorter than the verified minimum"))
        #expect(message.contains("awaiting authentication"))
        #expect(message.contains("3 bytes"))
        #expect(message.contains("do not retry"))
        #expect(!message.contains("GS3DeveloperProbe.V3ProbeError"))
        #expect(!message.contains("AABBCC"))
        #expect(!malformedDiagnostic.description.contains("AABBCC"))

        var earlyLiveProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try earlyLiveProbe.start()
        _ = try earlyLiveProbe.didSubscribe()
        let earlyLive = try encryptedGlucoseBatch(command: 0x32, glucoseTenths: 72)
        let earlyLiveDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingAuthentication,
            stateAfter: .failed,
            classification: .liveNotificationBatch,
            byteCount: 24,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 0,
            uniqueLiveReadingCount: 0
        )
        #expect(throws: V3ProbeError.unexpectedNotification(earlyLiveDiagnostic)) {
            try earlyLiveProbe.didReceive(earlyLive)
        }
    }

    @Test func diagnosticsClassifyEveryRedactedValidationStage() throws {
        func classification(
            for frame: EncodedFrame
        ) throws -> V3ProbeInboundClassification? {
            var probe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
            _ = try probe.start()
            _ = try probe.didSubscribe()
            _ = try probe.didReceive(
                encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
            )
            do {
                _ = try probe.didReceive(frame)
                Issue.record("malformed synthetic frame did not fail closed")
            } catch is V3ProbeError {
                // Expected. The assertion below checks the redacted failure stage.
            }
            #expect(probe.state == .failed)
            #expect(probe.authenticationTransmissionCount == 1)
            #expect(probe.effectiveDataTransmissionCount == 1)
            return probe.lastPacketDiagnostic?.classification
        }

        let accepted = try encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        var controlLengthPlaintext = try decryptTransport(accepted)
        controlLengthPlaintext[0] = 3
        replaceChecksum(in: &controlLengthPlaintext)
        #expect(
            try classification(for: encryptTransport(controlLengthPlaintext))
                == .controlLengthMismatch
        )

        #expect(
            try classification(
                for: encryptedControlResponse(command: 0xF0, code: 1, detail: 0)
            ) == .controlUnsupportedCommand
        )

        var controlChecksumPlaintext = try decryptTransport(accepted)
        controlChecksumPlaintext[4] &+= 1
        #expect(
            try classification(for: encryptTransport(controlChecksumPlaintext))
                == .controlChecksumMismatch
        )

        let valid = try encryptedGlucoseBatch(command: 0x32, glucoseTenths: 72)
        var glucosePlaintext = try decryptTransport(valid)

        var declaredLengthPlaintext = glucosePlaintext
        declaredLengthPlaintext[0] &-= 1
        replaceChecksum(in: &declaredLengthPlaintext)
        #expect(
            try classification(for: encryptTransport(declaredLengthPlaintext))
                == .glucoseDeclaredLengthMismatch
        )

        var unsupportedCommandPlaintext = glucosePlaintext
        unsupportedCommandPlaintext[1] = 0x31
        replaceChecksum(in: &unsupportedCommandPlaintext)
        #expect(
            try classification(for: encryptTransport(unsupportedCommandPlaintext))
                == .glucoseUnsupportedCommand(0x31)
        )

        unsupportedCommandPlaintext[23] &+= 1
        #expect(
            try classification(for: encryptTransport(unsupportedCommandPlaintext))
                == .glucoseChecksumMismatch
        )

        var invalidCountPlaintext = glucosePlaintext
        invalidCountPlaintext[2] = 0
        replaceChecksum(in: &invalidCountPlaintext)
        #expect(
            try classification(for: encryptTransport(invalidCountPlaintext))
                == .glucoseRecordCountInvalid
        )

        var invalidLayoutPlaintext = glucosePlaintext
        invalidLayoutPlaintext[2] = 2
        replaceChecksum(in: &invalidLayoutPlaintext)
        #expect(
            try classification(for: encryptTransport(invalidLayoutPlaintext))
                == .glucoseRecordLayoutMismatch
        )

        glucosePlaintext[23] &+= 1
        #expect(
            try classification(for: encryptTransport(glucosePlaintext))
                == .glucoseChecksumMismatch
        )

        #expect(
            try classification(for: EncodedFrame(bytes: [0xAA, 0xBB, 0xCC]))
                == .glucoseFrameTooShort
        )
    }

    @Test func quarantinesOnlyFirstChecksumValidUnsupportedCommandDuring0x39Write() throws {
        var probe = V3DeveloperHandoverProbe(
            material: try syntheticMaterial(),
            requiredLiveReadingCount: 1
        )
        _ = try probe.start()
        _ = try probe.didSubscribe()
        _ = try probe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )

        let unsupported = try encryptedGlucoseBatch(command: 0x31, glucoseTenths: 72)
        #expect(
            try probe.didReceive(
                unsupported,
                effectiveDataWriteAcknowledgementPending: true
            ).isEmpty
        )
        #expect(probe.state == .awaitingEffectiveData)
        #expect(probe.quarantinedGlucoseCommandCount == 1)
        #expect(probe.authenticationTransmissionCount == 1)
        #expect(probe.effectiveDataTransmissionCount == 1)
        #expect(
            probe.lastPacketDiagnostic?.classification
                == .quarantinedGlucoseCommand(0x31)
        )
        #expect(probe.lastPacketDiagnostic?.description.contains("0x31") == true)

        let acknowledgement = try encryptedControlResponse(
            command: 0x39,
            code: 1,
            detail: 0
        )
        #expect(
            try probe.didReceive(
                acknowledgement,
                effectiveDataWriteAcknowledgementPending: true
            ).isEmpty
        )

        let live = try encryptedGlucoseBatch(command: 0x32, glucoseTenths: 73)
        let completion = try probe.didReceive(live)
        #expect(completion.last == .disconnect)
        #expect(probe.state == .completed)
        #expect(probe.quarantinedGlucoseCommandCount == 1)
        #expect(!probe.completionGatePassed)
        #expect(probe.authenticationTransmissionCount == 1)
        #expect(probe.effectiveDataTransmissionCount == 1)

        let failedUnsupportedDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingEffectiveData,
            stateAfter: .failed,
            classification: .glucoseUnsupportedCommand(0x31),
            byteCount: 24,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 1,
            uniqueLiveReadingCount: 0
        )
        var lateProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try lateProbe.start()
        _ = try lateProbe.didSubscribe()
        _ = try lateProbe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )
        #expect(throws: V3ProbeError.unexpectedNotification(failedUnsupportedDiagnostic)) {
            try lateProbe.didReceive(
                unsupported,
                effectiveDataWriteAcknowledgementPending: false
            )
        }
        #expect(lateProbe.state == .failed)
        #expect(lateProbe.quarantinedGlucoseCommandCount == 0)

        var checksumPlaintext = try decryptTransport(unsupported)
        checksumPlaintext[23] &+= 1
        let checksumInvalid = try encryptTransport(checksumPlaintext)
        let checksumDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingEffectiveData,
            stateAfter: .failed,
            classification: .glucoseChecksumMismatch,
            byteCount: 24,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 1,
            uniqueLiveReadingCount: 0
        )
        var checksumProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try checksumProbe.start()
        _ = try checksumProbe.didSubscribe()
        _ = try checksumProbe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )
        #expect(throws: V3ProbeError.unexpectedNotification(checksumDiagnostic)) {
            try checksumProbe.didReceive(
                checksumInvalid,
                effectiveDataWriteAcknowledgementPending: true
            )
        }
        #expect(checksumProbe.quarantinedGlucoseCommandCount == 0)

        var duplicateProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try duplicateProbe.start()
        _ = try duplicateProbe.didSubscribe()
        _ = try duplicateProbe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )
        _ = try duplicateProbe.didReceive(
            unsupported,
            effectiveDataWriteAcknowledgementPending: true
        )
        #expect(throws: V3ProbeError.unexpectedNotification(failedUnsupportedDiagnostic)) {
            try duplicateProbe.didReceive(
                unsupported,
                effectiveDataWriteAcknowledgementPending: true
            )
        }
        #expect(duplicateProbe.state == .failed)
        #expect(duplicateProbe.quarantinedGlucoseCommandCount == 1)
        #expect(
            duplicateProbe.lastPacketDiagnostic?.classification
                == .glucoseUnsupportedCommand(0x31)
        )

        var longPlaintext = try decryptTransport(unsupported)
        longPlaintext.insert(
            contentsOf: [UInt8](repeating: 0, count: 16),
            at: longPlaintext.count - 3
        )
        longPlaintext[0] = UInt8(longPlaintext.count - 1)
        replaceChecksum(in: &longPlaintext)
        let longUnsupported = try encryptTransport(longPlaintext)
        let longDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingEffectiveData,
            stateAfter: .failed,
            classification: .glucoseUnsupportedCommand(0x31),
            byteCount: 40,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 1,
            uniqueLiveReadingCount: 0
        )
        var longProbe = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try longProbe.start()
        _ = try longProbe.didSubscribe()
        _ = try longProbe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )
        #expect(throws: V3ProbeError.unexpectedNotification(longDiagnostic)) {
            try longProbe.didReceive(
                longUnsupported,
                effectiveDataWriteAcknowledgementPending: true
            )
        }
        #expect(longProbe.quarantinedGlucoseCommandCount == 0)

        var postLiveProbe = V3DeveloperHandoverProbe(
            material: try syntheticMaterial(),
            requiredLiveReadingCount: 2
        )
        _ = try postLiveProbe.start()
        _ = try postLiveProbe.didSubscribe()
        _ = try postLiveProbe.didReceive(
            encryptedControlResponse(command: 0xE2, code: 1, detail: 0)
        )
        _ = try postLiveProbe.didReceive(live)
        let postLiveDiagnostic = V3ProbePacketDiagnostic(
            stateBefore: .awaitingEffectiveData,
            stateAfter: .failed,
            classification: .glucoseUnsupportedCommand(0x31),
            byteCount: 24,
            authenticationTransmissionCount: 1,
            effectiveDataTransmissionCount: 1,
            uniqueLiveReadingCount: 1
        )
        #expect(throws: V3ProbeError.unexpectedNotification(postLiveDiagnostic)) {
            try postLiveProbe.didReceive(
                unsupported,
                effectiveDataWriteAcknowledgementPending: true
            )
        }
        #expect(postLiveProbe.quarantinedGlucoseCommandCount == 0)
    }

    @Test func timeoutAndCancelDisconnectWithoutRetry() throws {
        var timedOut = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try timedOut.start()
        #expect(timedOut.timeOut() == [.disconnect])
        #expect(timedOut.timeOut().isEmpty)
        #expect(timedOut.state == .failed)

        var cancelled = V3DeveloperHandoverProbe(material: try syntheticMaterial())
        _ = try cancelled.start()
        #expect(cancelled.cancel() == [.disconnect])
        #expect(cancelled.cancel().isEmpty)
        #expect(cancelled.authenticationTransmissionCount == 0)
        #expect(cancelled.effectiveDataTransmissionCount == 0)
    }

    @Test func protocolControlDecoderRequiresExactObservedAuthAcceptance() throws {
        let accepted = try encryptedControlResponse(
            command: 0xE2,
            code: 1,
            detail: 0
        )
        #expect(
            try V3OfflineControlResponseDecoder.decode(
                accepted,
                sensorAddress: Array(1...6)
            ) == .authenticationAccepted
        )

        let unsupported = try encryptedControlResponse(
            command: 0xF0,
            code: 1,
            detail: 0
        )
        #expect(throws: GS3ProtocolError.unsupportedV3ControlResponseCommand(0xF0)) {
            try V3OfflineControlResponseDecoder.decode(
                unsupported,
                sensorAddress: Array(1...6)
            )
        }
    }

    private func syntheticMaterial() throws -> V3ProbeMaterial {
        try V3ProbeMaterial(
            expectedPeripheralName: "SYNTHETIC_V3",
            effectiveDataStartIndex: 0x1234,
            sensorAddress: Array(1...6),
            authenticationID: Array(0x20...0x2B),
            registeredBlock: Array(0x30...0x3F),
            algorithmKey: Array(0x40...0x4F),
            algorithmInitializationVector: Array(0x50...0x5F)
        )
    }

    private func syntheticJSON(
        schemaVersion: Int = 1,
        sensorAddressHex: String = "010203040506"
    ) -> String {
        """
        {"schemaVersion":\(schemaVersion),"sensorAddressHex":"\(sensorAddressHex)","authenticationIDHex":"202122232425262728292a2b","registeredBlockHex":"303132333435363738393a3b3c3d3e3f","algorithmKeyHex":"404142434445464748494a4b4c4d4e4f","algorithmIVHex":"505152535455565758595a5b5c5d5e5f","effectiveDataStartIndex":1}
        """
    }

    private func encryptedControlResponse(
        command: UInt8,
        code: UInt8,
        detail: UInt8
    ) throws -> EncodedFrame {
        var plaintext: [UInt8] = [0x04, command, code, detail]
        plaintext.append(UInt8.zero &- plaintext.reduce(UInt8.zero, &+))
        return EncodedFrame(
            bytes: try AES128OFB.crypt(
                plaintext,
                key: V3ProtocolConstants.fixedKey,
                initializationVector: Array(1...6) + [UInt8](repeating: 0, count: 10)
            )
        )
    }

    private func encryptedGlucoseBatch(
        command: UInt8,
        glucoseTenths: UInt16,
        startingIndex: UInt16 = 0x22
    ) throws -> EncodedFrame {
        let algorithmPlaintext = [
            UInt8(truncatingIfNeeded: glucoseTenths),
            UInt8(truncatingIfNeeded: glucoseTenths >> 8),
        ]
        let algorithmCiphertext = try AES128OFB.crypt(
            algorithmPlaintext,
            key: Array(0x40...0x4F),
            initializationVector: Array(0x50...0x5F)
        )
        var plaintext: [UInt8] = [
            0x17,
            command,
            1,
            UInt8(truncatingIfNeeded: startingIndex),
            UInt8(truncatingIfNeeded: startingIndex >> 8),
        ]
        plaintext.append(contentsOf: [
            0x01, 0, 0x02, 0, 0x03, 0, 0x04, 0,
            algorithmCiphertext[0], algorithmCiphertext[1], 0x02, 0,
            0x05, 0, 0x06, 0,
        ])
        plaintext.append(contentsOf: [
            UInt8(truncatingIfNeeded: startingIndex),
            UInt8(truncatingIfNeeded: startingIndex >> 8),
        ])
        plaintext.append(UInt8.zero &- plaintext.reduce(UInt8.zero, &+))
        return EncodedFrame(
            bytes: try AES128OFB.crypt(
                plaintext,
                key: V3ProtocolConstants.fixedKey,
                initializationVector: Array(1...6) + [UInt8](repeating: 0, count: 10)
            )
        )
    }

    private func decryptTransport(_ frame: EncodedFrame) throws -> [UInt8] {
        try AES128OFB.crypt(
            frame.bytes,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: Array(1...6) + [UInt8](repeating: 0, count: 10)
        )
    }

    private func encryptTransport(_ plaintext: [UInt8]) throws -> EncodedFrame {
        EncodedFrame(
            bytes: try AES128OFB.crypt(
                plaintext,
                key: V3ProtocolConstants.fixedKey,
                initializationVector: Array(1...6) + [UInt8](repeating: 0, count: 10)
            )
        )
    }

    private func replaceChecksum(in plaintext: inout [UInt8]) {
        plaintext[plaintext.count - 1] = 0
        plaintext[plaintext.count - 1] = UInt8.zero
            &- plaintext.dropLast().reduce(UInt8.zero, &+)
    }
}
