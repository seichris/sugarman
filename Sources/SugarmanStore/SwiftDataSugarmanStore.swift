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

    public func domainValue() throws -> GlucoseSample {
        guard sensorIndex >= 0, sensorIndex <= Int64(UInt32.max) else {
            throw StoreError.invalidSensorIndex(sensorIndex)
        }
        return GlucoseSample(
            sessionID: sessionID,
            sensorIndex: UInt32(sensorIndex),
            sensorTimestamp: sensorTimestamp,
            receiptTimestamp: receiptTimestamp,
            milligramsPerDeciliter: milligramsPerDeciliter,
            originalTenthsMillimolesPerLiter: originalTenthsMillimolesPerLiter,
            trend: GlucoseTrend(rawValue: trendRaw) ?? .unknown,
            quality: SampleQuality(rawValue: qualityRaw) ?? .unknown,
            source: SampleSource(rawValue: sourceRaw) ?? .unknown,
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
    public var activatedAt: Date?
    public var warmUpEndsAt: Date?
    public var expectedEndsAt: Date?
    public var endedAt: Date?
    public var lastRequestedIndex: Int64?
    public var lastReceivedIndex: Int64?
    public var lastCommittedIndex: Int64?
    public var sensorErrorCode: String?

    public init(from session: SensorSession) {
        self.sessionID = session.id
        self.sensorID = session.sensorID
        self.lifecycleRaw = session.lifecycle.rawValue
        self.connectionRaw = session.connection.rawValue
        self.protocolRaw = session.protocolVariant.rawValue
        self.ownerAccountReference = session.ownerAccountReference
        self.activatedAt = session.activatedAt
        self.warmUpEndsAt = session.warmUpEndsAt
        self.expectedEndsAt = session.expectedEndsAt
        self.endedAt = session.endedAt
        self.lastRequestedIndex = session.lastRequestedIndex.map(Int64.init)
        self.lastReceivedIndex = session.lastReceivedIndex.map(Int64.init)
        self.lastCommittedIndex = session.lastCommittedIndex.map(Int64.init)
        self.sensorErrorCode = session.sensorErrorCode
    }

    public func update(from session: SensorSession) {
        sensorID = session.sensorID
        lifecycleRaw = session.lifecycle.rawValue
        connectionRaw = session.connection.rawValue
        protocolRaw = session.protocolVariant.rawValue
        ownerAccountReference = session.ownerAccountReference
        activatedAt = session.activatedAt
        warmUpEndsAt = session.warmUpEndsAt
        expectedEndsAt = session.expectedEndsAt
        endedAt = session.endedAt
        lastRequestedIndex = session.lastRequestedIndex.map(Int64.init)
        lastReceivedIndex = session.lastReceivedIndex.map(Int64.init)
        lastCommittedIndex = session.lastCommittedIndex.map(Int64.init)
        sensorErrorCode = session.sensorErrorCode
    }

    public func domainValue() throws -> SensorSession {
        SensorSession(
            id: sessionID,
            sensorID: sensorID,
            activatedAt: activatedAt,
            warmUpEndsAt: warmUpEndsAt,
            expectedEndsAt: expectedEndsAt,
            endedAt: endedAt,
            ownerAccountReference: ownerAccountReference,
            lastRequestedIndex: try checkedIndex(lastRequestedIndex),
            lastReceivedIndex: try checkedIndex(lastReceivedIndex),
            lastCommittedIndex: try checkedIndex(lastCommittedIndex),
            protocolVariant: ProtocolVariant(rawValue: protocolRaw) ?? .unknown,
            lifecycle: SensorLifecycleState(rawValue: lifecycleRaw) ?? .unknown,
            connection: ConnectionState(rawValue: connectionRaw) ?? .disconnected,
            sensorErrorCode: sensorErrorCode
        )
    }

    private func checkedIndex(_ value: Int64?) throws -> UInt32? {
        guard let value else { return nil }
        guard value >= 0, value <= Int64(UInt32.max) else {
            throw StoreError.invalidSensorIndex(value)
        }
        return UInt32(value)
    }
}

@available(iOS 26, macOS 26, *)
@Model
public final class FuelingEventRecord {
    #Unique<FuelingEventRecord>([\.eventID])
    public var eventID: UUID
    public var timestamp: Date
    public var carbohydrateGrams: Double?
    public var label: String
    public var notes: String?
    public var sessionID: UUID?

    public init(from event: FuelingEvent) {
        self.eventID = event.id
        self.timestamp = event.timestamp
        self.carbohydrateGrams = event.carbohydrateGrams
        self.label = event.label
        self.notes = event.notes
        self.sessionID = event.sessionID
    }

    public func domainValue() -> FuelingEvent {
        FuelingEvent(
            id: eventID,
            timestamp: timestamp,
            carbohydrateGrams: carbohydrateGrams,
            label: label,
            notes: notes,
            sessionID: sessionID
        )
    }
}

@available(iOS 26, macOS 26, *)
@Model
public final class WorkoutContextRecord {
    #Unique<WorkoutContextRecord>([\.workoutID])
    public var workoutID: UUID
    public var sessionID: UUID?
    public var healthKitWorkoutUUID: UUID?
    public var start: Date
    public var end: Date?
    public var activityType: String
    public var summary: String?

    public init(from workout: WorkoutContext) {
        self.workoutID = workout.id
        self.sessionID = workout.sessionID
        self.healthKitWorkoutUUID = workout.healthKitWorkoutUUID
        self.start = workout.start
        self.end = workout.end
        self.activityType = workout.activityType
        self.summary = workout.summary
    }

    public func domainValue() -> WorkoutContext {
        WorkoutContext(
            id: workoutID,
            sessionID: sessionID,
            healthKitWorkoutUUID: healthKitWorkoutUUID,
            start: start,
            end: end,
            activityType: activityType,
            summary: summary
        )
    }
}

@available(iOS 26, macOS 26, *)
@Model
public final class SensorIdentityRecord {
    #Unique<SensorIdentityRecord>([\.identityID])
    public var identityID: UUID
    public var productName: String?
    public var sku: String?
    public var gtin: String?
    public var redactedSerial: String
    public var protocolRaw: String
    public var classificationEvidenceRevision: String
    public var udiIssuingAgency: String?
    public var peerUUID: UUID?
    public var firmwareRevision: String?
    public var hardwareRevision: String?
    public var manufacturer: String?

    public init(from identity: SensorIdentity) {
        self.identityID = identity.id
        self.productName = identity.productName
        self.sku = identity.sku
        self.gtin = identity.gtin
        self.redactedSerial = identity.redactedSerial
        self.protocolRaw = identity.protocolVariant.rawValue
        self.classificationEvidenceRevision = identity.classificationEvidenceRevision
        self.udiIssuingAgency = identity.udiIssuingAgency
        self.peerUUID = identity.peerUUID
        self.firmwareRevision = identity.firmwareRevision
        self.hardwareRevision = identity.hardwareRevision
        self.manufacturer = identity.manufacturer
    }

    public func domainValue() -> SensorIdentity {
        SensorIdentity(
            id: identityID,
            productName: productName,
            sku: sku,
            gtin: gtin,
            redactedSerial: redactedSerial,
            udiIssuingAgency: udiIssuingAgency,
            peerUUID: peerUUID,
            firmwareRevision: firmwareRevision,
            hardwareRevision: hardwareRevision,
            manufacturer: manufacturer,
            protocolVariant: ProtocolVariant(rawValue: protocolRaw) ?? .unknown,
            classificationEvidenceRevision: classificationEvidenceRevision
        )
    }
}

/// SwiftData-backed store isolated behind the repository protocol. Uniqueness
/// on `(sessionID, sensorIndex)` is enforced in the actor, not by CloudKit.
/// CloudKit is not configured.
@available(iOS 26, macOS 26, *)
@ModelActor
public actor SwiftDataSugarmanStore: SugarmanStoring {
    nonisolated public static func make(inMemory: Bool) throws -> SwiftDataSugarmanStore {
        let container = try makeContainer(inMemory: inMemory)
        return SwiftDataSugarmanStore(modelContainer: container)
    }

    nonisolated public static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([
            GlucoseSampleRecord.self,
            SensorSessionRecord.self,
            FuelingEventRecord.self,
            WorkoutContextRecord.self,
            SensorIdentityRecord.self,
        ])
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            let url = try persistentStoreURL()
            configuration = ModelConfiguration(
                "Sugarman",
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        }
        let container = try ModelContainer(for: schema, configurations: [configuration])
        if !inMemory {
            try applyFileProtection(at: try persistentStoreURL())
        }
        return container
    }

    nonisolated public static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema([
            GlucoseSampleRecord.self,
            SensorSessionRecord.self,
            FuelingEventRecord.self,
            WorkoutContextRecord.self,
            SensorIdentityRecord.self,
        ])
        let configuration = ModelConfiguration(
            "Sugarman",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    nonisolated private static func persistentStoreURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Sugarman", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try applyFileProtection(at: directory)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(resourceValues)
        return directory.appendingPathComponent("sugarman.store")
    }

    nonisolated private static func applyFileProtection(at url: URL) throws {
        #if os(iOS)
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: path
        )
        #endif
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
        return try found.first?.domainValue()
    }

    public func latestSample(sessionID: UUID) async throws -> GlucoseSample? {
        let found = try modelContext.fetch(
            FetchDescriptor<GlucoseSampleRecord>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
        )
        return try found.max(by: { $0.sensorIndex < $1.sensorIndex })?.domainValue()
    }

    public func samples(sessionID: UUID) async throws -> [GlucoseSample] {
        let found = try modelContext.fetch(
            FetchDescriptor<GlucoseSampleRecord>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
        )
        return try found.map { try $0.domainValue() }.sorted { $0.sensorIndex < $1.sensorIndex }
    }

    public func allSamples() async throws -> [GlucoseSample] {
        let found = try modelContext.fetch(FetchDescriptor<GlucoseSampleRecord>())
        return try found.map { try $0.domainValue() }.sorted { lhs, rhs in
            if lhs.sessionID != rhs.sessionID {
                return lhs.sessionID.uuidString < rhs.sessionID.uuidString
            }
            return lhs.sensorIndex < rhs.sensorIndex
        }
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

    public func updateSession(_ session: SensorSession) async throws {
        let id = session.id
        let records = try modelContext.fetch(
            FetchDescriptor<SensorSessionRecord>(
                predicate: #Predicate { $0.sessionID == id }
            )
        )
        guard let record = records.first else { throw StoreError.notFound }
        record.update(from: session)
        try modelContext.save()
    }

    public func session(id: UUID) async throws -> SensorSession? {
        let found = try modelContext.fetch(
            FetchDescriptor<SensorSessionRecord>(
                predicate: #Predicate { $0.sessionID == id }
            )
        )
        return try found.first?.domainValue()
    }

    public func allSessions() async throws -> [SensorSession] {
        let records = try modelContext.fetch(FetchDescriptor<SensorSessionRecord>())
        return try records.map { try $0.domainValue() }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func delete(sessionID: UUID) async throws {
        let sessionRecords = try modelContext.fetch(
            FetchDescriptor<SensorSessionRecord>(
                predicate: #Predicate { $0.sessionID == sessionID }
            )
        )
        guard !sessionRecords.isEmpty else { throw StoreError.notFound }
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
        let fuelingRecords = try modelContext.fetch(FetchDescriptor<FuelingEventRecord>())
        for record in fuelingRecords where record.sessionID == sessionID {
            modelContext.delete(record)
        }
        let workoutRecords = try modelContext.fetch(FetchDescriptor<WorkoutContextRecord>())
        for record in workoutRecords where record.sessionID == sessionID {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    public func deleteAll() async throws {
        try modelContext.delete(model: SensorSessionRecord.self)
        try modelContext.delete(model: GlucoseSampleRecord.self)
        try modelContext.delete(model: FuelingEventRecord.self)
        try modelContext.delete(model: WorkoutContextRecord.self)
        try modelContext.delete(model: SensorIdentityRecord.self)
        try modelContext.save()
    }

    public func sessionIDs() async throws -> [UUID] {
        let records = try modelContext.fetch(FetchDescriptor<SensorSessionRecord>())
        return records.map(\.sessionID)
    }

    public func insertFueling(_ event: FuelingEvent) async throws {
        let id = event.id
        let existing = try modelContext.fetch(
            FetchDescriptor<FuelingEventRecord>(
                predicate: #Predicate { $0.eventID == id }
            )
        )
        if !existing.isEmpty {
            throw StoreError.duplicateFueling(id)
        }
        modelContext.insert(FuelingEventRecord(from: event))
        try modelContext.save()
    }

    public func fuelingEvents() async throws -> [FuelingEvent] {
        let records = try modelContext.fetch(FetchDescriptor<FuelingEventRecord>())
        return records.map { $0.domainValue() }.sorted { $0.timestamp < $1.timestamp }
    }

    public func deleteFueling(id: UUID) async throws {
        let records = try modelContext.fetch(
            FetchDescriptor<FuelingEventRecord>(
                predicate: #Predicate { $0.eventID == id }
            )
        )
        guard !records.isEmpty else { throw StoreError.notFound }
        for record in records {
            modelContext.delete(record)
        }
        try modelContext.save()
    }

    public func insertWorkout(_ workout: WorkoutContext) async throws {
        let id = workout.id
        let existing = try modelContext.fetch(
            FetchDescriptor<WorkoutContextRecord>(
                predicate: #Predicate { $0.workoutID == id }
            )
        )
        if !existing.isEmpty {
            throw StoreError.duplicateWorkout(id)
        }
        modelContext.insert(WorkoutContextRecord(from: workout))
        try modelContext.save()
    }

    public func workouts() async throws -> [WorkoutContext] {
        let records = try modelContext.fetch(FetchDescriptor<WorkoutContextRecord>())
        return records.map { $0.domainValue() }.sorted { $0.start < $1.start }
    }

    public func insertIdentity(_ identity: SensorIdentity) async throws {
        let id = identity.id
        let existing = try modelContext.fetch(
            FetchDescriptor<SensorIdentityRecord>(
                predicate: #Predicate { $0.identityID == id }
            )
        )
        if !existing.isEmpty {
            throw StoreError.duplicateIdentity(id)
        }
        modelContext.insert(SensorIdentityRecord(from: identity))
        try modelContext.save()
    }

    public func identities() async throws -> [SensorIdentity] {
        let records = try modelContext.fetch(FetchDescriptor<SensorIdentityRecord>())
        return records.map { $0.domainValue() }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
#else
/// SwiftData is unavailable on this platform. Callers should use
/// `InMemorySugarmanStore`, which remains testable.
public enum SwiftDataStoreFactory {
    public static var isAvailable: Bool { false }
}
#endif
