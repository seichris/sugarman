// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
@testable import Integrations

struct IntegrationsTests {
    let exporter = VersionedDataExporter()
    let zone = TimeZone(secondsFromGMT: 0)!

    func sample(session: UUID = UUID(), index: UInt32, mgdl: Int = 101) -> GlucoseSample {
        GlucoseSample(
            sessionID: session,
            sensorIndex: index,
            sensorTimestamp: Date(timeIntervalSince1970: Double(index)),
            receiptTimestamp: Date(timeIntervalSince1970: Double(index) + 1),
            milligramsPerDeciliter: mgdl,
            trend: .stable,
            quality: .ok,
            source: index < 3 ? .backfill : .live,
            decoderRevision: "synthetic-demo"
        )
    }

    @Test func healthKitWriterDoesNotPersist() async {
        let writer = DisabledHealthKitWriter()
        let sample = sample(index: 1, mgdl: 90)
        await #expect(throws: IntegrationError.healthKitWritesDisabledUntilParity) {
            try await writer.persistValidatedGlucose([sample])
        }
    }

    @Test func emptyExportHasSchemaAndNoDataRows() throws {
        let json = try exporter.exportJSON(samples: [], timeZone: zone)
        let document = try JSONDecoder().decode(GlucoseExportDocument.self, from: json)
        #expect(document.schemaVersion == 1)
        #expect(document.unit == "mg/dL")
        #expect(document.timeZone == zone.identifier)
        #expect(document.samples.isEmpty)
        #expect(document.disclaimer == ProductCopy.noDosing)
        let csv = try exporter.exportCSV(samples: [], timeZone: zone)
        #expect(csv.contains("schemaVersion=1"))
        #expect(csv.contains("unit=mg/dL"))
        #expect(csv.contains("timeZone="))
        let dataRows = csv.split(separator: "\n").drop { !$0.hasPrefix("sessionID,") }.dropFirst()
        #expect(Array(dataRows).isEmpty)
    }

    @Test func smallDatasetUnder50RowsIsFullyExported() throws {
        let session = UUID()
        let samples = (1...7).map { sample(session: session, index: UInt32($0), mgdl: 90 + $0) }
        let json = try exporter.exportJSON(samples: samples, timeZone: zone)
        let document = try JSONDecoder().decode(GlucoseExportDocument.self, from: json)
        #expect(document.samples.count == 7)
        #expect(document.samples.map(\.sensorIndex) == [1, 2, 3, 4, 5, 6, 7])
        let csv = try exporter.exportCSV(samples: samples, timeZone: zone)
        for index in 1...7 {
            #expect(csv.contains(",\(index),"))
        }
        #expect(csv.contains("synthetic-demo"))
        #expect(csv.contains("backfill"))
        #expect(csv.contains("live"))
    }

    @Test func exportOmitsAuthMaterialAndSensitiveFields() throws {
        let sample = sample(index: 3, mgdl: 101)
        let json = try exporter.exportJSON(samples: [sample], timeZone: zone)
        let text = String(decoding: json, as: UTF8.self)
        #expect(text.contains("schemaVersion"))
        #expect(text.contains("mg/dL"))
        #expect(text.contains("timeZone"))
        let forbidden = ["packet", "RC4", "password", "token", "credential", "ownerAccount", "serial", "MAC", "accountID"]
        for needle in forbidden {
            #expect(!text.contains(needle), "JSON export unexpectedly contained \(needle)")
        }
        let csv = try exporter.exportCSV(samples: [sample], timeZone: zone)
        #expect(csv.contains("sensorIndex"))
        #expect(csv.contains("101"))
        for needle in forbidden {
            #expect(!csv.contains(needle), "CSV export unexpectedly contained \(needle)")
        }
    }

    @Test func exportPreservesIndexSortAcrossSessions() throws {
        let sessionB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let sessionA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let samples = [
            sample(session: sessionB, index: 2, mgdl: 120),
            sample(session: sessionA, index: 9, mgdl: 110),
            sample(session: sessionA, index: 1, mgdl: 100),
        ]
        let document = try JSONDecoder().decode(
            GlucoseExportDocument.self,
            from: try exporter.exportJSON(samples: samples, timeZone: zone)
        )
        #expect(document.samples.map(\.sensorIndex) == [1, 9, 2])
        #expect(document.samples.map(\.sessionID) == [
            sessionA.uuidString,
            sessionA.uuidString,
            sessionB.uuidString,
        ])
    }
}
