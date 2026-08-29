// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import Testing
import SugarmanDomain
import SugarmanStore
@testable import Integrations

struct IntegrationsTests {
    let exporter = VersionedDataExporter()
    let zone = TimeZone(secondsFromGMT: 0)!
    let pacific = TimeZone(identifier: "America/Los_Angeles")!

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
        #expect(document.schemaVersion == 2)
        #expect(document.unit == "mg/dL")
        #expect(document.timeZone == "UTC")
        #expect(document.samples.isEmpty)
        #expect(document.fueling.isEmpty)
        #expect(document.disclaimer == ProductCopy.noDosing)
        let csv = try exporter.exportCSV(samples: [], timeZone: zone)
        let records = RFC4180CSV.records(in: csv)
        #expect(records[0] == ["schemaVersion", "unit", "timeZone", "disclaimer"])
        #expect(records[1][0] == "2")
        #expect(records[1][1] == "mg/dL")
        #expect(records[1][2] == "UTC")
        let headerIndex = records.firstIndex { $0.first == "sessionID" }
        #expect(headerIndex != nil)
        if let headerIndex {
            #expect(records.dropFirst(headerIndex + 1).isEmpty)
        }
    }

    @Test func smallDatasetUnder50RowsIsFullyExported() throws {
        let session = UUID()
        let samples = (1...7).map { sample(session: session, index: UInt32($0), mgdl: 90 + $0) }
        let json = try exporter.exportJSON(samples: samples, timeZone: zone)
        let document = try JSONDecoder().decode(GlucoseExportDocument.self, from: json)
        #expect(document.samples.count == 7)
        #expect(document.samples.map(\.sensorIndex) == [1, 2, 3, 4, 5, 6, 7])
        let csv = try exporter.exportCSV(samples: samples, timeZone: zone)
        let records = RFC4180CSV.records(in: csv)
        guard let headerIndex = records.firstIndex(where: { $0.first == "sessionID" }) else {
            Issue.record("missing sessionID header")
            return
        }
        let dataRows = Array(records.dropFirst(headerIndex + 1))
        #expect(dataRows.count == 7)
        #expect(dataRows.map { $0[1] } == ["1", "2", "3", "4", "5", "6", "7"])
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

    @Test func csvQuotesCommaContainingDisclaimerAndUnitAsOneField() throws {
        #expect(ProductCopy.noDosing.contains(","))
        let csv = try exporter.exportCSV(samples: [sample(index: 1)], timeZone: pacific)
        let records = RFC4180CSV.records(in: csv)
        #expect(records[0] == ["schemaVersion", "unit", "timeZone", "disclaimer"])
        #expect(records[1].count == 4)
        #expect(records[1][1] == "mg/dL")
        #expect(records[1][3] == ProductCopy.noDosing)
        #expect(records[1][3].contains(","))
        let quotedUnit = RFC4180CSV.row(["mg/dL, mmol/L", "never, dose"])
        let parsed = RFC4180CSV.parseRow(quotedUnit)
        #expect(parsed == ["mg/dL, mmol/L", "never, dose"])
        let quotedQuotes = RFC4180CSV.parseRow(RFC4180CSV.row([#"say "hello, world""#]))
        #expect(quotedQuotes == [#"say "hello, world""#])
    }

    @Test func exportTimestampsAreUTCEvenWhenCallerZoneIsLocal() throws {
        let sample = sample(index: 1, mgdl: 101)
        let json = try exporter.exportJSON(samples: [sample], timeZone: pacific)
        let document = try JSONDecoder().decode(GlucoseExportDocument.self, from: json)
        #expect(document.timeZone == "UTC")
        #expect(document.samples[0].sensorTimestamp == "1970-01-01T00:00:01Z")
        #expect(document.samples[0].receiptTimestamp == "1970-01-01T00:00:02Z")
        #expect(document.samples[0].sensorTimestamp.hasSuffix("Z"))
        #expect(document.samples[0].receiptTimestamp.hasSuffix("Z"))

        let csv = try exporter.exportCSV(samples: [sample], timeZone: pacific)
        let records = RFC4180CSV.records(in: csv)
        #expect(records[1][2] == "UTC")
        guard let headerIndex = records.firstIndex(where: { $0.first == "sessionID" }) else {
            Issue.record("missing sessionID header")
            return
        }
        let row = records[headerIndex + 1]
        #expect(row[2] == "1970-01-01T00:00:01Z")
        #expect(row[3] == "1970-01-01T00:00:02Z")
        #expect(row[2].hasSuffix("Z"))
        #expect(row[3].hasSuffix("Z"))
    }

    @Test func exportFromStoreWithOwnerIDDoesNotLeakAccountID() async throws {
        let store = InMemorySugarmanStore()
        let owner = "owner-account-secret-xyz-42"
        let sessionID = UUID()
        let session = SensorSession(
            id: sessionID,
            sensorID: UUID(),
            ownerAccountReference: owner
        )
        try await store.insertSession(session)
        try await store.insertSample(sample(session: sessionID, index: 4, mgdl: 99))
        let samples = try await store.allSamples()
        let json = try exporter.exportJSON(samples: samples, timeZone: pacific)
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains(owner))
        #expect(!text.contains("ownerAccount"))
        #expect(!text.contains("accountID"))
        #expect(!text.contains(session.ownerAccountReference ?? "missing-owner"))
        let csv = try exporter.exportCSV(samples: samples, timeZone: pacific)
        #expect(!csv.contains(owner))
        #expect(!csv.contains("ownerAccount"))
        #expect(!csv.contains("accountID"))
        let decoded = try JSONDecoder().decode(GlucoseExportDocument.self, from: json)
        #expect(decoded.samples.count == 1)
    }

    @Test func jsonExportIncludesFuelingWithoutAccountIDsAndCSVStaysGlucose() async throws {
        let store = InMemorySugarmanStore()
        let owner = "owner-account-secret-xyz-42"
        let sessionID = UUID()
        try await store.insertSession(
            SensorSession(id: sessionID, sensorID: UUID(), ownerAccountReference: owner)
        )
        try await store.insertSample(sample(session: sessionID, index: 4, mgdl: 99))
        let gel = FuelingEvent(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            timestamp: Date(timeIntervalSince1970: 50),
            carbohydrateGrams: 25,
            label: "gel, banana",
            notes: "athlete log",
            sessionID: sessionID
        )
        try await store.insertFueling(gel)
        let samples = try await store.allSamples()
        let fueling = try await store.fuelingEvents()
        let json = try exporter.exportJSON(samples: samples, fueling: fueling, timeZone: pacific)
        let document = try JSONDecoder().decode(GlucoseExportDocument.self, from: json)
        #expect(document.schemaVersion == 2)
        #expect(document.fueling.count == 1)
        #expect(document.fueling[0].label == "gel, banana")
        #expect(document.fueling[0].carbohydrateGrams == 25)
        #expect(document.fueling[0].sessionID == sessionID.uuidString)
        #expect(document.fueling[0].timestamp == "1970-01-01T00:00:50Z")
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.contains(owner))
        #expect(!text.contains("ownerAccount"))
        #expect(!text.contains("accountID"))
        let csv = try exporter.exportCSV(samples: samples, timeZone: pacific)
        #expect(!csv.contains("gel, banana"))
        #expect(!csv.contains("athlete log"))
        #expect(!csv.contains(owner))
        let records = RFC4180CSV.records(in: csv)
        #expect(records[1][0] == "2")
    }
}
