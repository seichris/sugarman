// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol

/// Opaque request for matching the exact private local name from an existing
/// Probe JSON document. The name and request token are deliberately unavailable
/// to application code, descriptions, reflection, and diagnostics.
public struct GS3ProbeBridgeScanRequest:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    package let token: UUID
    private let expectedPeripheralName: String

    package init(token: UUID, expectedPeripheralName: String) {
        self.token = token
        self.expectedPeripheralName = expectedPeripheralName
    }

    public func matches(localName: String?) -> Bool {
        localName == expectedPeripheralName
    }

    public var description: String {
        "GS3ProbeBridgeScanRequest(expectedPeripheralName: redacted, token: redacted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "expectedPeripheralName": "redacted",
                "token": "redacted",
            ],
            displayStyle: .struct
        )
    }
}

/// Pure accumulator used by the CoreBluetooth scan-only adapter.
///
/// Repeated callbacks for one peripheral are de-duplicated. Zero matches and
/// multiple distinct matches fail closed after the bounded scan window.
public struct GS3ProbeBridgeDiscoveryAccumulator:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private let request: GS3ProbeBridgeScanRequest
    private var matchingPeripheralIDs: Set<UUID> = []

    public init(request: GS3ProbeBridgeScanRequest) {
        self.request = request
    }

    public mutating func observe(peripheralID: UUID, localName: String?) {
        guard request.matches(localName: localName) else { return }
        guard matchingPeripheralIDs.count < 2
            || matchingPeripheralIDs.contains(peripheralID)
        else {
            return
        }
        matchingPeripheralIDs.insert(peripheralID)
    }

    public func selectedPeripheralID() throws -> UUID {
        guard !matchingPeripheralIDs.isEmpty else {
            throw GS3DeviceProvisioningError.probeBridgePeripheralNotFound
        }
        guard matchingPeripheralIDs.count == 1,
              let only = matchingPeripheralIDs.first else {
            throw GS3DeviceProvisioningError.probeBridgePeripheralAmbiguous
        }
        return only
    }

    public var description: String {
        "GS3ProbeBridgeDiscoveryAccumulator(matches: \(boundedMatchCount), payload: redacted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "matches": boundedMatchCount,
                "request": "redacted",
                "peripherals": "redacted",
            ],
            displayStyle: .struct
        )
    }

    private var boundedMatchCount: Int {
        min(matchingPeripheralIDs.count, 2)
    }
}

/// Strict representation of the historical one-shot Probe JSON schema.
///
/// It is intentionally reimplemented inside the provisioning boundary rather
/// than exposing the Probe's private material type. The raw document is never
/// retained or re-encoded, and this type cannot represent a sensor command.
package struct GS3ProbeProvisioningDocument:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    private static let schemaVersion = 1
    private static let allowedKeys: Set<String> = [
        "schemaVersion",
        "expectedPeripheralName",
        "sensorAddressHex",
        "authenticationIDHex",
        "registeredBlockHex",
        "algorithmKeyHex",
        "algorithmIVHex",
        "effectiveDataStartIndex",
    ]

    package let expectedPeripheralName: String
    package let captureBackedStart: UInt16
    package let sensorAddress: [UInt8]
    package let authenticationID: [UInt8]
    package let registeredBlock: [UInt8]
    package let algorithmKey: [UInt8]
    package let algorithmInitializationVector: [UInt8]

    package init(importJSONData data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw GS3DeviceProvisioningError.invalidDocument
        }
        guard let dictionary = object as? [String: Any] else {
            throw GS3DeviceProvisioningError.invalidDocument
        }
        guard Set(dictionary.keys) == Self.allowedKeys else {
            throw GS3DeviceProvisioningError.unexpectedDocumentField
        }

        let document: ImportDocument
        do {
            document = try JSONDecoder().decode(ImportDocument.self, from: data)
        } catch {
            throw GS3DeviceProvisioningError.invalidDocument
        }
        guard document.schemaVersion == Self.schemaVersion else {
            throw GS3DeviceProvisioningError.unsupportedSchemaVersion(
                document.schemaVersion
            )
        }
        guard let expectedPeripheralName = document.expectedPeripheralName else {
            throw GS3DeviceProvisioningError.invalidProbePeripheralName
        }
        let nameBytes = Array(expectedPeripheralName.utf8)
        guard !nameBytes.isEmpty,
              nameBytes.count <= 64,
              nameBytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else {
            throw GS3DeviceProvisioningError.invalidProbePeripheralName
        }
        guard let captureBackedStart = UInt16(
            exactly: document.effectiveDataStartIndex
        ) else {
            throw GS3DeviceProvisioningError.invalidHistoryStart
        }

        let sensorAddress = try Self.hexBytes(
            document.sensorAddressHex,
            field: "sensorAddressHex"
        )
        let authenticationID = try Self.hexBytes(
            document.authenticationIDHex,
            field: "authenticationIDHex"
        )
        let registeredBlock = try Self.hexBytes(
            document.registeredBlockHex,
            field: "registeredBlockHex"
        )
        let algorithmKey = try Self.hexBytes(
            document.algorithmKeyHex,
            field: "algorithmKeyHex"
        )
        let algorithmInitializationVector = try Self.hexBytes(
            document.algorithmIVHex,
            field: "algorithmIVHex"
        )

        try Self.requireLength(sensorAddress, field: "sensorAddressHex", expected: 6)
        try Self.requireLength(
            authenticationID,
            field: "authenticationIDHex",
            expected: 12
        )
        try Self.requireLength(
            registeredBlock,
            field: "registeredBlockHex",
            expected: 16
        )
        try Self.requireLength(algorithmKey, field: "algorithmKeyHex", expected: 16)
        try Self.requireLength(
            algorithmInitializationVector,
            field: "algorithmIVHex",
            expected: 16
        )
        _ = try V3ActiveSessionMaterial(
            sensorAddress: sensorAddress,
            authenticationID: authenticationID,
            registeredBlock: registeredBlock,
            algorithmKey: algorithmKey,
            algorithmInitializationVector: algorithmInitializationVector
        )

        self.expectedPeripheralName = expectedPeripheralName
        self.captureBackedStart = captureBackedStart
        self.sensorAddress = sensorAddress
        self.authenticationID = authenticationID
        self.registeredBlock = registeredBlock
        self.algorithmKey = algorithmKey
        self.algorithmInitializationVector = algorithmInitializationVector
    }

    package var description: String {
        "GS3ProbeProvisioningDocument(expectedPeripheralName: redacted, "
            + "captureStart: redacted, material: present)"
    }

    package var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "expectedPeripheralName": "redacted",
                "captureStart": "redacted",
                "material": "present",
            ],
            displayStyle: .struct
        )
    }

    private struct ImportDocument: Decodable {
        let schemaVersion: Int
        let expectedPeripheralName: String?
        let sensorAddressHex: String
        let authenticationIDHex: String
        let registeredBlockHex: String
        let algorithmKeyHex: String
        let algorithmIVHex: String
        let effectiveDataStartIndex: UInt32
    }

    private static func requireLength(
        _ bytes: [UInt8],
        field: String,
        expected: Int
    ) throws {
        guard bytes.count == expected else {
            throw GS3DeviceProvisioningError.invalidLength(
                field: field,
                expected: expected,
                actual: bytes.count
            )
        }
    }

    private static func hexBytes(_ text: String, field: String) throws -> [UInt8] {
        let encoded = Array(text.utf8)
        guard encoded.count.isMultiple(of: 2),
              encoded.allSatisfy({ byte in
                  (byte >= 0x30 && byte <= 0x39)
                      || (byte >= 0x41 && byte <= 0x46)
                      || (byte >= 0x61 && byte <= 0x66)
              }) else {
            throw GS3DeviceProvisioningError.invalidHex(field: field)
        }
        var output: [UInt8] = []
        output.reserveCapacity(encoded.count / 2)
        for offset in stride(from: 0, to: encoded.count, by: 2) {
            output.append((nibble(encoded[offset]) << 4) | nibble(encoded[offset + 1]))
        }
        return output
    }

    private static func nibble(_ byte: UInt8) -> UInt8 {
        switch byte {
        case 0x30...0x39: byte - 0x30
        case 0x41...0x46: byte - 0x41 + 10
        default: byte - 0x61 + 10
        }
    }
}

package struct PendingGS3ProbeBridge:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    package let request: GS3ProbeBridgeScanRequest
    package let document: GS3ProbeProvisioningDocument
    package let linkedSensorID: UUID

    package var description: String {
        "PendingGS3ProbeBridge(request: redacted, document: redacted, sensor: redacted)"
    }

    package var debugDescription: String { description }

    package var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "request": "redacted",
                "document": "redacted",
                "sensor": "redacted",
            ],
            displayStyle: .struct
        )
    }
}
