// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import GS3Transport
@testable import SugarmanDiagnostics

struct SugarmanDiagnosticsTests {
    @Test func disabledByDefault() async {
        let runtime = RecordingBluetoothRuntime()
        let probe = ReadOnlyDiagnosticProbe(runtime: runtime)
        #expect(probe.isEnabled == false)
        await #expect(throws: TransportError.probeDisabled) {
            try await probe.scan()
        }
        #expect(runtime.log.effects.isEmpty)
    }

    @Test func probeDoesNotConformToMutatingMarker() {
        let probe = ReadOnlyDiagnosticProbe(runtime: RecordingBluetoothRuntime())
        #expect(!(probe is any CharacteristicMutating))
    }

    @Test func enabledProbeCanScanConnectAndReadAllowlisted() async throws {
        let runtime = RecordingBluetoothRuntime()
        let probe = ReadOnlyDiagnosticProbe(isEnabled: true, runtime: runtime)
        try await probe.scan()
        let id = UUID()
        try await probe.connect(peripheralID: id)
        try await probe.noteConnected()
        try await probe.noteServicesDiscovered()
        try await probe.noteCharacteristicsDiscovered()
        try await probe.noteSubscribed()
        try await probe.readDocumentedCharacteristic(DocumentedReadableCharacteristic.manufacturerName)
        #expect(runtime.log.effects.contains(.startScan))
        #expect(runtime.log.effects.contains(.read(DocumentedReadableCharacteristic.manufacturerName)))
        let writes = runtime.log.effects.contains { effect in
            switch effect {
            case .read, .startScan, .stopScan, .connect, .cancelConnection,
                 .discoverServices, .discoverCharacteristics, .subscribe,
                 .waitBackoff, .fail:
                return false
            }
        }
        #expect(!writes)
    }

    @Test func refusesNonDocumentedCharacteristic() async {
        let runtime = RecordingBluetoothRuntime()
        let probe = ReadOnlyDiagnosticProbe(isEnabled: true, runtime: runtime)
        await #expect(throws: TransportError.mutatingOperationRefused) {
            try await probe.readDocumentedCharacteristic(UUID())
        }
    }

    @Test func refusesSerialCharacteristic() async {
        let runtime = RecordingBluetoothRuntime()
        let probe = ReadOnlyDiagnosticProbe(isEnabled: true, runtime: runtime)
        await #expect(throws: TransportError.mutatingOperationRefused) {
            try await probe.readDocumentedCharacteristic(DocumentedReadableCharacteristic.serialNumber)
        }
        #expect(runtime.log.effects.isEmpty)
    }

    @Test func deviceInformationOmitsSerial() {
        let serial = DocumentedReadableCharacteristic.serialNumber
        let manufacturer = DocumentedReadableCharacteristic.manufacturerName
        let snapshot = DeviceInformationSnapshot.omittingSerial(from: [
            serial: "FULLSERIAL9999",
            manufacturer: "Acme",
        ])
        #expect(snapshot.manufacturerName == "Acme")
        #expect(snapshot.modelNumber == nil)
        #expect(snapshot.firmwareRevision == nil)
        let described = String(describing: snapshot)
        #expect(!described.contains("FULLSERIAL9999"))
    }

    @Test func displayCharacteristicsExcludeSerial() {
        #expect(!ProbeDisplayCharacteristic.all.contains(DocumentedReadableCharacteristic.serialNumber))
        #expect(ProbeDisplayCharacteristic.all.contains(DocumentedReadableCharacteristic.firmwareRevision))
    }

    @Test func redactedGATTMapOmitsValuesAndStaysUnknownCipher() {
        let probe = ReadOnlyDiagnosticProbe(isEnabled: true, runtime: RecordingBluetoothRuntime())
        let map = probe.redactedGATTMap(peripheralID: UUID(), localName: "SyntheticLab")
        #expect(map.cipherHypothesis == .unknownUntilCapture)
        #expect(map.sixByteAddressSource == .notFound)
        let described = String(describing: map)
        #expect(!described.contains("RC4"))
        #expect(!described.contains("AES"))
    }
}
