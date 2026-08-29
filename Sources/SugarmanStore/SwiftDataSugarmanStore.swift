// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import SugarmanDomain

#if canImport(SwiftData)
import SwiftData

@available(iOS 26, macOS 26, *)
@Model
public final class GlucoseSampleRecord {
    #Unique<GlucoseSampleRecord>([\.sessionID, \.sensorIndex])
    public var sessionID: UUID
    public var sensorIndex: Int64
    public var sensorTimestamp: Date
    public var receiptTimestamp: Date
    public var milligramsPerDeciliter: Int
    public var originalTenthsMillimolesPerLiter: Int?
    public var trendRaw: String
    public var qualityRaw: String
    public var sourceRaw: String
    public var decoderRevision: String

    public init(from sample: GlucoseSample) {
        self.sessionID = sample.sessionID
        self.sensorIndex = Int64(sample.sensorIndex)
        self.sensorTimestamp = sample.sensorTimestamp
        self.receiptTimestamp = sample.receiptTimestamp
        self.milligramsPerDeciliter = sample.milligramsPerDeciliter
        self.originalTenthsMillimolesPerLiter = sample.originalTenthsMillimolesPerLiter
        self.trendRaw = sample.trend.rawValue
        self.qualityRaw = sample.quality.rawValue
        self.sourceRaw = sample.source.rawValue
        self.decoderRevision = sample.decoderRevision
    }

    public func domainValue() -> GlucoseSample {
        GlucoseSample(
            sessionID: sessionID,
            sensorIndex: UInt32(sensorIndex),
            sensorTimestamp: sensorTimestamp,
            receiptTimestamp: receiptTimestamp,
            milligramsPerDeciliter: milligramsPerDeciliter,
            originalTenthsMillimolesPerLiter: originalTenthsMillimolesPerLiter,
            trend: GlucoseTrend(rawValue: trendRaw) ?? .unknown,
            quality: SampleQuality(rawValue: qualityRaw) ?? .unknown,
            source: SampleSource(rawValue: sourceRaw) ?? .live,
            decoderRevision: decoderRevision
        )
    }
}

@available(iOS 26, macOS 26, *)
@Model
public final class SensorSessionRecord {
    #Unique<SensorSessionRecord>([\.sessionID])
    public var sessionID: UUID
    public var sensorID: UUID
    public var lifecycleRaw: String
    public var connectionRaw: String
    public var protocolRaw: String
    public var ownerAccountReference: String?

    public init(from session: SensorSession) {
        self.sessionID = session.id
        self.sensorID = session.sensorID
        self.lifecycleRaw = session.lifecycle.rawValue
        self.connectionRaw = session.connection.rawValue
        self.protocolRaw = session.protocolVariant.rawValue
        self.ownerAccountReference = session.ownerAccountReference
    }
}

/// SwiftData-backed store isolated behind the repository protocol. Uniqueness
/// on `(sessionID, sensorIndex)` is enforced in the actor, not by CloudKit.
/// CloudKit is not configured.
@available(iOS 26, macOS 26, *)
@ModelActor
public actor SwiftDataSugarmanStore: SugarmanStoring {
    public static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([GlucoseSampleRecord.self, SensorSessionRecord.self])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    public func insertSample(_ sample: GlucoseSample) async throws {
        let sessionID = sample.sessionID
        let index = Int64(sample.sensorIndex)
        let existing = try modelContext.fetch(
            FetchDescriptor<GlucoseSampleRecord>(
                predicate: #Predicate {
                    $0.sessionID == sessionID && $0.sensorIndex == index
                }
            )
        )
        if !existing.isEmpty {
            throw StoreError.duplicateSample(sample.id)
        }
        modelContext.insert(GlucoseSampleRecord(from: sample))
        try modelContext.save()
    }

    public func sample(sessionID: UUID, sensorIndex: UInt32) async throws -> GlucoseSample? {
        let index = Int64(sensorIndex)
        let found = try modelContext.fetch(
            FetchDescriptor<GlucoseSampleRecord>(
                predicate: #Predicate {
                    $0.sessionID == sessionID && $0.sensorIndex == index
                }
            )
        )
        return found.first?.domainValue()
    }

    public func latestSample(sessionID: UUID) async throws -> GlucoseSample? {
        let found = try modelContext.fetch(
            FetchDescriptor<GlucoseSampleRecord>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
        )
        return found.max(by: { $0.sensorIndex < $1.sensorIndex })?.domainValue()
    }

    public func insertSession(_ session: SensorSession) async throws {
        let id = session.id
        let existing = try modelContext.fetch(
            FetchDescriptor<SensorSessionRecord>(
                predicate: #Predicate { $0.sessionID == id }
            )
        )
        if !existing.isEmpty {
            throw StoreError.duplicateSession(id)
        }
        modelContext.insert(SensorSessionRecord(from: session))
        try modelContext.save()
    }

    public func session(id: UUID) async throws -> SensorSession? {
        let found = try modelContext.fetch(
            FetchDescriptor<SensorSessionRecord>(
                predicate: #Predicate { $0.sessionID == id }
            )
        )
        guard let record = found.first else { return nil }
        return SensorSession(
            id: record.sessionID,
            sensorID: record.sensorID,
            ownerAccountReference: record.ownerAccountReference,
            protocolVariant: ProtocolVariant(rawValue: record.protocolRaw) ?? .unknown,
            lifecycle: SensorLifecycleState(rawValue: record.lifecycleRaw) ?? .unknown,
            connection: ConnectionState(rawValue: record.connectionRaw) ?? .disconnected
        )
    }

    public func delete(sessionID: UUID) async throws {
        let sessionRecords = try modelContext.fetch(
            FetchDescriptor<SensorSessionRecord>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
        )
        for record in sessionRecords {
            modelContext.delete(record)
        }
        let sampleRecords = try modelContext.fetch(
            FetchDescriptor<GlucoseSampleRecord>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
        )
        for record in sampleRecords {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    public func deleteAll() async throws {
        try modelContext.delete(model: SensorSessionRecord.self)
        try modelContext.delete(model: GlucoseSampleRecord.self)
        try modelContext.save()
    }

    public func sessionIDs() async throws -> [UUID] {
        let records = try modelContext.fetch(FetchDescriptor<SensorSessionRecord>())
        return records.map(\.sessionID)
    }
}
#else
/// SwiftData is unavailable on this platform. Callers should use
/// `InMemorySugarmanStore`, which remains testable.
public enum SwiftDataStoreFactory {
    public static var isAvailable: Bool { false }
}
#endif
