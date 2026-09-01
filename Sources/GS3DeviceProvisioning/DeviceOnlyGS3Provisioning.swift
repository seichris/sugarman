// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol
import GS3Session
import GS3Transport
import SugarmanDomain
import SugarmanStore

public struct GS3DeviceProvisioningSummary:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// Local random identity key only. Descriptions and reflection redact it.
    public let linkedSensorID: UUID
    public let connectionIntentEnabled: Bool

    public init(linkedSensorID: UUID, connectionIntentEnabled: Bool) {
        self.linkedSensorID = linkedSensorID
        self.connectionIntentEnabled = connectionIntentEnabled
    }

    public var description: String {
        "GS3DeviceProvisioningSummary(material: available, linkedSensor: redacted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "material": "available",
                "linkedSensor": "redacted",
                "connectionIntentEnabled": connectionIntentEnabled,
            ],
            displayStyle: .struct
        )
    }
}

/// Device-only provisioning boundary for the normal production coordinator.
///
/// Import and Keychain availability never start Bluetooth. A caller must make
/// and start a controller explicitly after its own physical-test confirmation.
/// The returned controller retains the existing typed two-command transport;
/// this type adds no scan, raw-frame, or arbitrary-command surface.
public actor DeviceOnlyGS3Provisioning {
    private let persistence: any GS3DeviceProvisioningPersisting
    private let uuidGenerator: @Sendable () -> UUID
    private let requestTokenGenerator: @Sendable () -> UUID
    private var sessionOrdinal: UInt64 = 0
    private var pendingProbeBridge: PendingGS3ProbeBridge?
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(scope: GS3DeviceProvisioningScope) {
        self.persistence = KeychainGS3DeviceProvisioningStore(scope: scope)
        self.uuidGenerator = { UUID() }
        self.requestTokenGenerator = { UUID() }
    }

    package init(
        persistence: any GS3DeviceProvisioningPersisting,
        uuidGenerator: @escaping @Sendable () -> UUID = { UUID() },
        requestTokenGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.persistence = persistence
        self.uuidGenerator = uuidGenerator
        self.requestTokenGenerator = requestTokenGenerator
    }

    public func summary() async throws -> GS3DeviceProvisioningSummary? {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        guard let record = try loadRecord() else { return nil }
        return GS3DeviceProvisioningSummary(
            linkedSensorID: record.sensorID,
            connectionIntentEnabled: record.connectionIntentEnabled
        )
    }

    /// Persists only the user's opt-in state alongside device-only material.
    /// Enabling this flag performs no Bluetooth operation.
    public func setConnectionIntentEnabled(_ enabled: Bool) async throws {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        guard let record = try loadRecord() else {
            throw GS3DeviceProvisioningError.missingMaterial
        }
        try persistence.replace(
            with: record.withConnectionIntentEnabled(enabled).encodedForStorage()
        )
    }

    public func importDocument(
        _ data: Data,
        linkedSensorID: UUID,
        into store: any SugarmanStoring
    ) async throws {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        let document = try GS3DeviceProvisioningDocument(importJSONData: data)
        let identities: [SensorIdentity]
        do {
            identities = try await store.identities()
        } catch {
            throw GS3DeviceProvisioningError.persistence
        }
        guard identities.contains(where: { $0.id == linkedSensorID }) else {
            throw GS3DeviceProvisioningError.linkedIdentityUnavailable
        }

        let record: StoredGS3DeviceProvisioning
        if let existing = try loadRecord() {
            guard existing.sensorID == linkedSensorID,
                  existing.matchesPrivateIdentity(document) else {
                throw GS3DeviceProvisioningError.replacementRequiresDeletion
            }
            record = try StoredGS3DeviceProvisioning(
                document: document,
                sessionID: existing.sessionID,
                sensorID: existing.sensorID,
                connectionIntentEnabled: existing.connectionIntentEnabled
            )
        } else {
            record = try StoredGS3DeviceProvisioning(
                document: document,
                sessionID: uuidGenerator(),
                sensorID: linkedSensorID
            )
        }

        try persistence.replace(with: record.encodedForStorage())
        try await ensureLocalSession(for: record, in: store)
    }

    /// Strictly validates an existing one-shot Probe JSON document and keeps
    /// only its normalized material in process memory for one scan-only
    /// provisioning attempt. This method performs no Bluetooth operation and
    /// does not persist the raw document.
    public func prepareProbeBridgeImport(
        _ data: Data,
        linkedSensorID: UUID,
        in store: any SugarmanStoring
    ) async throws -> GS3ProbeBridgeScanRequest {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        guard try loadRecord() == nil else {
            throw GS3DeviceProvisioningError.replacementRequiresDeletion
        }
        guard pendingProbeBridge == nil else {
            throw GS3DeviceProvisioningError.probeBridgeAlreadyPrepared
        }
        let document = try GS3ProbeProvisioningDocument(importJSONData: data)
        try await requireIdentity(linkedSensorID, in: store)
        let request = GS3ProbeBridgeScanRequest(
            token: requestTokenGenerator(),
            expectedPeripheralName: document.expectedPeripheralName
        )
        pendingProbeBridge = PendingGS3ProbeBridge(
            request: request,
            document: document,
            linkedSensorID: linkedSensorID
        )
        return request
    }

    /// Completes the in-memory Probe bridge after a separate scan-only adapter
    /// returns exactly one matching CoreBluetooth identifier. No connection or
    /// transport controller is created or started here.
    public func completeProbeBridgeImport(
        request: GS3ProbeBridgeScanRequest,
        peripheralID: UUID,
        into store: any SugarmanStoring
    ) async throws {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        guard let pendingProbeBridge else {
            throw GS3DeviceProvisioningError.probeBridgeNotPrepared
        }
        guard pendingProbeBridge.request.token == request.token else {
            throw GS3DeviceProvisioningError.staleProbeBridgeRequest
        }
        guard try loadRecord() == nil else {
            throw GS3DeviceProvisioningError.replacementRequiresDeletion
        }
        try await requireIdentity(pendingProbeBridge.linkedSensorID, in: store)
        let record = try StoredGS3DeviceProvisioning(
            probeDocument: pendingProbeBridge.document,
            peripheralID: peripheralID,
            sessionID: uuidGenerator(),
            sensorID: pendingProbeBridge.linkedSensorID
        )
        try persistence.replace(with: record.encodedForStorage())
        self.pendingProbeBridge = nil
        try await ensureLocalSession(for: record, in: store)
    }

    /// Clears only process-memory material prepared from the Probe JSON.
    /// Existing final Keychain provisioning, sessions, and samples are not
    /// changed.
    public func discardProbeBridgeImport() async {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        pendingProbeBridge = nil
    }

    public func delete() async throws {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        pendingProbeBridge = nil
        try persistence.delete()
    }

    public func makeController(
        store: any SugarmanStoring,
        callbacks: GS3ForegroundSessionCallbacks = GS3ForegroundSessionCallbacks()
    ) async throws -> any GS3ForegroundSessionControlling {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        guard let record = try loadRecord() else {
            throw GS3DeviceProvisioningError.missingMaterial
        }
        try await ensureLocalSession(for: record, in: store)

        let configuration = try makeConfiguration(for: record)

        return GS3ForegroundSessionFactory.makeKnownPeripheralController(
            configuration: configuration,
            store: store,
            peripheralID: record.peripheralID,
            material: try record.activeSessionMaterial(),
            callbacks: callbacks
        )
    }

    /// Package-only construction path consumed by the isolated Device Test
    /// product. It uses the same stored material, typed transport, coordinator,
    /// ownership provider, and reconnect scheduler as production.
    package func makeDeviceTestController(
        store: any SugarmanStoring,
        callbacks: GS3ForegroundSessionCallbacks = GS3ForegroundSessionCallbacks()
    ) async throws -> any GS3ForegroundDeviceTestControlling {
        await acquireOperationGate()
        defer { releaseOperationGate() }
        guard let record = try loadRecord() else {
            throw GS3DeviceProvisioningError.missingMaterial
        }
        try await ensureLocalSession(for: record, in: store)

        return GS3ForegroundSessionFactory.makeKnownPeripheralDeviceTestController(
            configuration: try makeConfiguration(for: record),
            store: store,
            peripheralID: record.peripheralID,
            material: try record.activeSessionMaterial(),
            callbacks: callbacks
        )
    }

    private func makeConfiguration(
        for record: StoredGS3DeviceProvisioning
    ) throws -> GS3ForegroundSessionConfiguration {
        sessionOrdinal &+= 1
        if sessionOrdinal == 0 { sessionOrdinal = 1 }
        do {
            return try GS3ForegroundSessionConfiguration(
                sessionID: record.sessionID,
                sessionOrdinal: sessionOrdinal,
                captureBackedStart: CaptureBackedHistoryStart(
                    sensorIndex: UInt32(record.captureBackedStart)
                )
            )
        } catch {
            throw GS3DeviceProvisioningError.invalidStoredMaterial
        }
    }

    private func loadRecord() throws -> StoredGS3DeviceProvisioning? {
        guard var data = try persistence.load() else { return nil }
        defer {
            if !data.isEmpty { data.resetBytes(in: 0..<data.count) }
        }
        return try StoredGS3DeviceProvisioning(storedData: data)
    }

    private func acquireOperationGate() async {
        guard operationInProgress else {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperationGate() {
        guard !operationWaiters.isEmpty else {
            operationInProgress = false
            return
        }
        operationWaiters.removeFirst().resume()
    }

    private func ensureLocalSession(
        for record: StoredGS3DeviceProvisioning,
        in store: any SugarmanStoring
    ) async throws {
        do {
            let identities = try await store.identities()
            guard identities.contains(where: { $0.id == record.sensorID }) else {
                throw GS3DeviceProvisioningError.linkedIdentityUnavailable
            }
            if let existing = try await store.session(id: record.sessionID) {
                guard existing.sensorID == record.sensorID,
                      existing.lifecycle == .live,
                      existing.protocolVariant == .v3AES else {
                    throw GS3DeviceProvisioningError.sessionConflict
                }
                try await store.setConnection(.disconnected, sessionID: record.sessionID)
                return
            }
            try await store.insertSession(
                SensorSession(
                    id: record.sessionID,
                    sensorID: record.sensorID,
                    protocolVariant: .v3AES,
                    lifecycle: .live,
                    connection: .disconnected
                )
            )
        } catch let error as GS3DeviceProvisioningError {
            throw error
        } catch {
            throw GS3DeviceProvisioningError.persistence
        }
    }

    private func requireIdentity(
        _ linkedSensorID: UUID,
        in store: any SugarmanStoring
    ) async throws {
        let identities: [SensorIdentity]
        do {
            identities = try await store.identities()
        } catch {
            throw GS3DeviceProvisioningError.persistence
        }
        guard identities.contains(where: { $0.id == linkedSensorID }) else {
            throw GS3DeviceProvisioningError.linkedIdentityUnavailable
        }
    }
}

package struct StoredGS3DeviceProvisioning:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private static let magic: [UInt8] = [0x53, 0x47, 0x33, 0x50]
    private static let storageVersion: UInt8 = 2
    private static let version1StoredByteCount = 4 + 1 + 16 + 16 + 16 + 2 + 6 + 12 + 16 + 16 + 16
    private static let storedByteCount = version1StoredByteCount + 1

    package let peripheralID: UUID
    package let sessionID: UUID
    package let sensorID: UUID
    package let captureBackedStart: UInt16
    package var connectionIntentEnabled: Bool
    private let sensorAddress: [UInt8]
    private let authenticationID: [UInt8]
    private let registeredBlock: [UInt8]
    private let algorithmKey: [UInt8]
    private let algorithmInitializationVector: [UInt8]

    package init(
        document: GS3DeviceProvisioningDocument,
        sessionID: UUID,
        sensorID: UUID,
        connectionIntentEnabled: Bool = false
    ) throws {
        self.peripheralID = document.peripheralID
        self.sessionID = sessionID
        self.sensorID = sensorID
        self.captureBackedStart = document.captureBackedStart
        self.connectionIntentEnabled = connectionIntentEnabled
        self.sensorAddress = document.sensorAddress
        self.authenticationID = document.authenticationID
        self.registeredBlock = document.registeredBlock
        self.algorithmKey = document.algorithmKey
        self.algorithmInitializationVector = document.algorithmInitializationVector
        _ = try activeSessionMaterial()
    }

    package init(
        probeDocument: GS3ProbeProvisioningDocument,
        peripheralID: UUID,
        sessionID: UUID,
        sensorID: UUID
    ) throws {
        self.peripheralID = peripheralID
        self.sessionID = sessionID
        self.sensorID = sensorID
        self.captureBackedStart = probeDocument.captureBackedStart
        self.connectionIntentEnabled = false
        self.sensorAddress = probeDocument.sensorAddress
        self.authenticationID = probeDocument.authenticationID
        self.registeredBlock = probeDocument.registeredBlock
        self.algorithmKey = probeDocument.algorithmKey
        self.algorithmInitializationVector = probeDocument.algorithmInitializationVector
        _ = try activeSessionMaterial()
    }

    package init(storedData data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 5,
              Array(bytes.prefix(4)) == Self.magic else {
            throw GS3DeviceProvisioningError.invalidStoredMaterial
        }
        let version = bytes[4]
        guard (version == 1 && bytes.count == Self.version1StoredByteCount)
                || (version == Self.storageVersion && bytes.count == Self.storedByteCount) else {
            throw GS3DeviceProvisioningError.invalidStoredMaterial
        }
        var offset = 5
        func take(_ count: Int) -> [UInt8] {
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }
        guard let peripheralID = Self.uuid(from: take(16)),
              let sessionID = Self.uuid(from: take(16)),
              let sensorID = Self.uuid(from: take(16)) else {
            throw GS3DeviceProvisioningError.invalidStoredMaterial
        }
        let startBytes = take(2)

        self.peripheralID = peripheralID
        self.sessionID = sessionID
        self.sensorID = sensorID
        self.captureBackedStart = UInt16(startBytes[0]) | (UInt16(startBytes[1]) << 8)
        self.sensorAddress = take(6)
        self.authenticationID = take(12)
        self.registeredBlock = take(16)
        self.algorithmKey = take(16)
        self.algorithmInitializationVector = take(16)
        if version == Self.storageVersion {
            let intent = take(1)[0]
            guard intent == 0 || intent == 1 else {
                throw GS3DeviceProvisioningError.invalidStoredMaterial
            }
            self.connectionIntentEnabled = intent == 1
        } else {
            self.connectionIntentEnabled = false
        }
        do {
            _ = try activeSessionMaterial()
        } catch {
            throw GS3DeviceProvisioningError.invalidStoredMaterial
        }
    }

    package func encodedForStorage() -> Data {
        var bytes = Self.magic
        bytes.append(Self.storageVersion)
        bytes.append(contentsOf: Self.bytes(from: peripheralID))
        bytes.append(contentsOf: Self.bytes(from: sessionID))
        bytes.append(contentsOf: Self.bytes(from: sensorID))
        bytes.append(UInt8(truncatingIfNeeded: captureBackedStart))
        bytes.append(UInt8(truncatingIfNeeded: captureBackedStart >> 8))
        bytes.append(contentsOf: sensorAddress)
        bytes.append(contentsOf: authenticationID)
        bytes.append(contentsOf: registeredBlock)
        bytes.append(contentsOf: algorithmKey)
        bytes.append(contentsOf: algorithmInitializationVector)
        bytes.append(connectionIntentEnabled ? 1 : 0)
        return Data(bytes)
    }

    package func withConnectionIntentEnabled(_ enabled: Bool) -> Self {
        var copy = self
        copy.connectionIntentEnabled = enabled
        return copy
    }

    package func matchesPrivateIdentity(
        _ document: GS3DeviceProvisioningDocument
    ) -> Bool {
        peripheralID == document.peripheralID
            && sensorAddress == document.sensorAddress
            && authenticationID == document.authenticationID
            && registeredBlock == document.registeredBlock
            && algorithmKey == document.algorithmKey
            && algorithmInitializationVector == document.algorithmInitializationVector
    }

    package func activeSessionMaterial() throws -> V3ActiveSessionMaterial {
        try V3ActiveSessionMaterial(
            sensorAddress: sensorAddress,
            authenticationID: authenticationID,
            registeredBlock: registeredBlock,
            algorithmKey: algorithmKey,
            algorithmInitializationVector: algorithmInitializationVector
        )
    }

    package var description: String {
        "StoredGS3DeviceProvisioning(peripheral: redacted, session: redacted, "
            + "sensor: redacted, captureStart: redacted, material: present)"
    }

    package var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "peripheral": "redacted",
                "session": "redacted",
                "sensor": "redacted",
                "captureStart": "redacted",
                "material": "present",
            ],
            displayStyle: .struct
        )
    }

    private static func bytes(from id: UUID) -> [UInt8] {
        let value = id.uuid
        return [
            value.0, value.1, value.2, value.3,
            value.4, value.5, value.6, value.7,
            value.8, value.9, value.10, value.11,
            value.12, value.13, value.14, value.15,
        ]
    }

    private static func uuid(from bytes: [UInt8]) -> UUID? {
        guard bytes.count == 16 else { return nil }
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }
}
