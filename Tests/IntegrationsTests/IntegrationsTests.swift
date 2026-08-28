// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import Integrations

struct IntegrationsTests {
    @Test func healthKitWriterDoesNotPersist() async {
        let writer = DisabledHealthKitWriter()
        let sample = GlucoseSample(
            sessionID: UUID(),
            sensorIndex: 1,
            sensorTimestamp: Date(),
            receiptTimestamp: Date(),
            milligramsPerDeciliter: 90,
            decoderRevision: "none"
        )
        await #expect(throws: IntegrationError.healthKitWritesDisabledUntilParity) {
            try await writer.persistValidatedGlucose([sample])
        }
    }

    @Test func exportOmitsAuthMaterial() throws {
        let exporter = VersionedDataExporter()
        let sample = GlucoseSample(
            sessionID: UUID(),
            sensorIndex: 3,
            sensorTimestamp: Date(timeIntervalSince1970: 0),
            receiptTimestamp: Date(timeIntervalSince1970: 1),
            milligramsPerDeciliter: 101,
            decoderRevision: "none"
        )
        let json = try exporter.exportJSON(samples: [sample])
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains("schemaVersion"))
        #expect(text.contains("mg/dL"))
        #expect(!text.contains("packet"))
        #expect(!text.contains("RC4"))
        let csv = try exporter.exportCSV(samples: [sample])
        #expect(csv.contains("sensorIndex"))
        #expect(csv.contains("101"))
    }
}
