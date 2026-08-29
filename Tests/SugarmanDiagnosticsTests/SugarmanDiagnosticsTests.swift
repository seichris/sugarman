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
    }

    @Test func refusesNonDocumentedCharacteristic() async {
        let runtime = RecordingBluetoothRuntime()
        let probe = ReadOnlyDiagnosticProbe(isEnabled: true, runtime: runtime)
        await #expect(throws: TransportError.mutatingOperationRefused) {
            try await probe.readDocumentedCharacteristic(UUID())
        }
    }
}
