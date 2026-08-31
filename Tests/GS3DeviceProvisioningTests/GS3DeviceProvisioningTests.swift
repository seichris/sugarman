// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
@testable import GS3DeviceProvisioning
import GS3Transport
import SugarmanDomain
import SugarmanStore
import Testing

@Suite("GS3 device-only provisioning")
struct GS3DeviceProvisioningTests {
    @Test func importNormalizesMaterialAndPreparesOneLiveSession() async throws {
        let persistence = InMemoryProvisioningPersistence()
        let generatedSessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let service = DeviceOnlyGS3Provisioning(
            persistence: persistence,
            uuidGenerator: { generatedSessionID }
        )
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)

        var data = Data(syntheticJSON().utf8)
        defer { data.resetBytes(in: 0..<data.count) }
        try await service.importDocument(
            data,
            linkedSensorID: identity.id,
            into: store
        )

        let summary = try await service.summary()
        let sessions = try await store.allSessions()
        #expect(summary?.linkedSensorID == identity.id)
        #expect(sessions.count == 1)
        #expect(sessions[0].id == generatedSessionID)
        #expect(sessions[0].sensorID == identity.id)
        #expect(sessions[0].lifecycle == .live)
        #expect(sessions[0].protocolVariant == .v3AES)
        #expect(sessions[0].connection == .disconnected)
        #expect(persistence.data != data)
        #expect(persistence.data?.count == 121)
    }

    @Test func importRequiresAnExistingRedactedIdentity() async {
        let service = DeviceOnlyGS3Provisioning(
            persistence: InMemoryProvisioningPersistence()
        )
        let store = InMemorySugarmanStore()

        await #expect(throws: GS3DeviceProvisioningError.linkedIdentityUnavailable) {
            try await service.importDocument(
                Data(syntheticJSON().utf8),
                linkedSensorID: UUID(),
                into: store
            )
        }
        let summary = try? await service.summary()
        #expect(summary == nil)
    }

    @Test func sameSensorReimportPreservesDurableSessionAndUpdatesOnlyCaptureStart() async throws {
        let persistence = InMemoryProvisioningPersistence()
        let generatedSessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let service = DeviceOnlyGS3Provisioning(
            persistence: persistence,
            uuidGenerator: { generatedSessionID }
        )
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)

        try await service.importDocument(
            Data(syntheticJSON(historyStart: 0x1200).utf8),
            linkedSensorID: identity.id,
            into: store
        )
        try await service.importDocument(
            Data(syntheticJSON(historyStart: 0x1201).utf8),
            linkedSensorID: identity.id,
            into: store
        )

        let sessions = try await store.allSessions()
        #expect(sessions.map(\.id) == [generatedSessionID])
        let record = try #require(
            persistence.data.map { try StoredGS3DeviceProvisioning(storedData: $0) }
        )
        #expect(record.captureBackedStart == 0x1201)
    }

    @Test func differentPrivateIdentityRequiresExplicitDeletion() async throws {
        let persistence = InMemoryProvisioningPersistence()
        let service = DeviceOnlyGS3Provisioning(persistence: persistence)
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)
        try await service.importDocument(
            Data(syntheticJSON().utf8),
            linkedSensorID: identity.id,
            into: store
        )

        await #expect(throws: GS3DeviceProvisioningError.replacementRequiresDeletion) {
            try await service.importDocument(
                Data(
                    syntheticJSON(
                        peripheralID: "10000000-2000-3000-4000-500000000099"
                    ).utf8
                ),
                linkedSensorID: identity.id,
                into: store
            )
        }
        #expect(try await store.allSessions().count == 1)
    }

    @Test func controllerConstructionUsesPreparedSessionWithoutStartingTransport() async throws {
        let service = DeviceOnlyGS3Provisioning(
            persistence: InMemoryProvisioningPersistence()
        )
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)
        try await service.importDocument(
            Data(syntheticJSON().utf8),
            linkedSensorID: identity.id,
            into: store
        )

        let controller = try await service.makeController(store: store)
        #expect(await controller.currentPhase() == .idle)
        #expect(try await store.allSessions().count == 1)
    }

    @Test func controllerConstructionResetsAStaleConnectionProjection() async throws {
        let service = DeviceOnlyGS3Provisioning(
            persistence: InMemoryProvisioningPersistence()
        )
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)
        try await service.importDocument(
            Data(syntheticJSON().utf8),
            linkedSensorID: identity.id,
            into: store
        )
        var session = try #require(try await store.allSessions().first)
        session.connection = .subscribed
        try await store.updateSession(session)

        let controller = try await service.makeController(store: store)
        let refreshed = try #require(try await store.session(id: session.id))
        #expect(await controller.currentPhase() == .idle)
        #expect(refreshed.connection == .disconnected)
    }

    @Test func controllerConstructionRejectsConflictingDurableSession() async throws {
        let service = DeviceOnlyGS3Provisioning(
            persistence: InMemoryProvisioningPersistence()
        )
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)
        try await service.importDocument(
            Data(syntheticJSON().utf8),
            linkedSensorID: identity.id,
            into: store
        )
        var session = try #require(try await store.allSessions().first)
        session.lifecycle = .ended
        try await store.updateSession(session)

        await #expect(throws: GS3DeviceProvisioningError.sessionConflict) {
            try await service.makeController(store: store)
        }
        #expect(try await store.allSessions().count == 1)
    }

    @Test func concurrentSameSensorImportsConvergeOnOneDurableSession() async throws {
        let generatedSessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let service = DeviceOnlyGS3Provisioning(
            persistence: InMemoryProvisioningPersistence(),
            uuidGenerator: { generatedSessionID }
        )
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)
        let data = Data(syntheticJSON().utf8)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await service.importDocument(
                        data,
                        linkedSensorID: identity.id,
                        into: store
                    )
                }
            }
            try await group.waitForAll()
        }

        let sessions = try await store.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions[0].id == generatedSessionID)
    }

    @Test func corruptStoredMaterialFailsClosedWithoutAController() async throws {
        let persistence = InMemoryProvisioningPersistence()
        try persistence.replace(with: Data([0x53, 0x47, 0x33, 0x50, 0x01]))
        let service = DeviceOnlyGS3Provisioning(persistence: persistence)

        await #expect(throws: GS3DeviceProvisioningError.invalidStoredMaterial) {
            try await service.summary()
        }
        await #expect(throws: GS3DeviceProvisioningError.invalidStoredMaterial) {
            try await service.makeController(store: InMemorySugarmanStore())
        }
    }

    @Test func strictImportRejectsUnknownFieldsMalformedUUIDSchemaAndIndex() {
        let extraField = syntheticJSON().replacingOccurrences(
            of: "\"schemaVersion\":1,",
            with: "\"schemaVersion\":1,\"activate\":true,"
        )
        #expect(throws: GS3DeviceProvisioningError.unexpectedDocumentField) {
            try GS3DeviceProvisioningDocument(importJSONData: Data(extraField.utf8))
        }
        #expect(throws: GS3DeviceProvisioningError.invalidPeripheralIdentifier) {
            try GS3DeviceProvisioningDocument(
                importJSONData: Data(syntheticJSON(peripheralID: "not-a-uuid").utf8)
            )
        }
        #expect(throws: GS3DeviceProvisioningError.unsupportedSchemaVersion(2)) {
            try GS3DeviceProvisioningDocument(
                importJSONData: Data(syntheticJSON(schemaVersion: 2).utf8)
            )
        }
        #expect(throws: GS3DeviceProvisioningError.invalidHistoryStart) {
            try GS3DeviceProvisioningDocument(
                importJSONData: Data(syntheticJSON(historyStart: 65_536).utf8)
            )
        }
    }

    @Test func strictImportRejectsWrongLengthsAndNonHexMaterial() {
        #expect(
            throws: GS3DeviceProvisioningError.invalidLength(
                field: "sensorAddressHex",
                expected: 6,
                actual: 2
            )
        ) {
            try GS3DeviceProvisioningDocument(
                importJSONData: Data(syntheticJSON(sensorAddressHex: "0102").utf8)
            )
        }
        #expect(throws: GS3DeviceProvisioningError.invalidHex(field: "sensorAddressHex")) {
            try GS3DeviceProvisioningDocument(
                importJSONData: Data(syntheticJSON(sensorAddressHex: "01020304050Z").utf8)
            )
        }
    }

    @Test func storedMaterialSummaryDumpAndReflectionArePayloadFree() async throws {
        let persistence = InMemoryProvisioningPersistence()
        let service = DeviceOnlyGS3Provisioning(persistence: persistence)
        let store = InMemorySugarmanStore()
        let identity = syntheticIdentity()
        try await store.insertIdentity(identity)
        try await service.importDocument(
            Data(syntheticJSON().utf8),
            linkedSensorID: identity.id,
            into: store
        )
        let stored = try StoredGS3DeviceProvisioning(
            storedData: #require(persistence.data)
        )
        let summary = try #require(try await service.summary())

        var text = ""
        dump(stored, to: &text)
        dump(summary, to: &text)
        #expect(text.contains("redacted"))
        #expect(!text.contains("10000000-2000-3000-4000-500000000001"))
        #expect(!text.contains("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
        #expect(!text.contains("010203040506"))
        #expect(!text.contains("4660"))
    }

    @Test func deleteIsIdempotentAndPreventsControllerConstruction() async throws {
        let persistence = InMemoryProvisioningPersistence()
        let service = DeviceOnlyGS3Provisioning(persistence: persistence)
        try await service.delete()
        try await service.delete()
        #expect(try await service.summary() == nil)
        await #expect(throws: GS3DeviceProvisioningError.missingMaterial) {
            try await service.makeController(store: InMemorySugarmanStore())
        }
    }

    private func syntheticIdentity() -> SensorIdentity {
        SensorIdentity(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            productName: "Synthetic GS3",
            redactedSerial: "SYN…TIC"
        )
    }

    private func syntheticJSON(
        schemaVersion: Int = 1,
        peripheralID: String = "10000000-2000-3000-4000-500000000001",
        historyStart: UInt32 = 0x1234,
        sensorAddressHex: String = "010203040506"
    ) -> String {
        """
        {"schemaVersion":\(schemaVersion),"peripheralIdentifier":"\(peripheralID)","sensorAddressHex":"\(sensorAddressHex)","authenticationIDHex":"202122232425262728292a2b","registeredBlockHex":"303132333435363738393a3b3c3d3e3f","algorithmKeyHex":"404142434445464748494a4b4c4d4e4f","algorithmIVHex":"505152535455565758595a5b5c5d5e5f","effectiveDataStartIndex":\(historyStart)}
        """
    }
}

private final class InMemoryProvisioningPersistence:
    GS3DeviceProvisioningPersisting, @unchecked Sendable
{
    private let lock = NSLock()
    private var stored: Data?

    var data: Data? {
        lock.withLock { stored }
    }

    func load() throws -> Data? {
        lock.withLock { stored }
    }

    func replace(with data: Data) throws {
        lock.withLock { stored = data }
    }

    func delete() throws {
        lock.withLock { stored = nil }
    }
}
