// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol
import Security

public enum GS3DeviceProvisioningError: Error, Sendable, Equatable {
    case invalidDocument
    case unsupportedSchemaVersion(Int)
    case unexpectedDocumentField
    case invalidPeripheralIdentifier
    case invalidHex(field: String)
    case invalidLength(field: String, expected: Int, actual: Int)
    case invalidHistoryStart
    case invalidStoredMaterial
    case missingMaterial
    case linkedIdentityUnavailable
    case sessionConflict
    case replacementRequiresDeletion
    case invalidProbePeripheralName
    case probeBridgeAlreadyPrepared
    case probeBridgeNotPrepared
    case staleProbeBridgeRequest
    case probeBridgePeripheralNotFound
    case probeBridgePeripheralAmbiguous
    case keychain(OSStatus)
    case persistence
}

extension GS3DeviceProvisioningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "The private device-test provisioning document is malformed."
        case .unsupportedSchemaVersion(let version):
            "Private device-test provisioning schema version \(version) is unsupported."
        case .unexpectedDocumentField:
            "The private device-test provisioning document contains an unsupported field."
        case .invalidPeripheralIdentifier:
            "The private device-test provisioning document has an invalid known-peripheral identifier."
        case .invalidHex(let field):
            "Private device-test field \(field) must contain ASCII hexadecimal bytes."
        case .invalidLength(let field, let expected, let actual):
            "Private device-test field \(field) must contain \(expected) bytes; received \(actual)."
        case .invalidHistoryStart:
            "The private device-test capture-backed history start is invalid."
        case .invalidStoredMaterial:
            "Stored private device-test material is invalid."
        case .missingMaterial:
            "Private device-test material is missing. Import it again."
        case .linkedIdentityUnavailable:
            "The linked local sensor identity is unavailable."
        case .sessionConflict:
            "The linked local sensor session conflicts with the provisioned live V3 session."
        case .replacementRequiresDeletion:
            "Delete the existing private device-test material before provisioning another sensor."
        case .invalidProbePeripheralName:
            "The Probe JSON must contain one bounded expected peripheral name for scan-only provisioning."
        case .probeBridgeAlreadyPrepared:
            "Discard the pending Probe JSON before preparing another scan-only provisioning attempt."
        case .probeBridgeNotPrepared:
            "Import the existing Probe JSON before starting scan-only provisioning."
        case .staleProbeBridgeRequest:
            "The scan-only provisioning request is no longer current. Import the Probe JSON again."
        case .probeBridgePeripheralNotFound:
            "The bounded provisioning scan did not find the expected owned sensor."
        case .probeBridgePeripheralAmbiguous:
            "The bounded provisioning scan found more than one matching peripheral and failed closed."
        case .keychain(let status):
            "Private device-test Keychain operation failed with status \(status)."
        case .persistence:
            "The private device-test session could not be prepared in local storage."
        }
    }
}

/// Strict, private-import representation for one already-active owned sensor.
///
/// The document cannot represent activation, registration, binding, reset,
/// firmware, expiry, arbitrary commands, or a fresh-sensor flow. Unknown keys
/// fail closed instead of being silently ignored.
package struct GS3DeviceProvisioningDocument: Sendable {
    package static let schemaVersion = 1
    private static let allowedKeys: Set<String> = [
        "schemaVersion",
        "peripheralIdentifier",
        "sensorAddressHex",
        "authenticationIDHex",
        "registeredBlockHex",
        "algorithmKeyHex",
        "algorithmIVHex",
        "effectiveDataStartIndex",
    ]

    package let peripheralID: UUID
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
        guard let peripheralID = UUID(uuidString: document.peripheralIdentifier) else {
            throw GS3DeviceProvisioningError.invalidPeripheralIdentifier
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

        self.peripheralID = peripheralID
        self.captureBackedStart = captureBackedStart
        self.sensorAddress = sensorAddress
        self.authenticationID = authenticationID
        self.registeredBlock = registeredBlock
        self.algorithmKey = algorithmKey
        self.algorithmInitializationVector = algorithmInitializationVector
    }

    private struct ImportDocument: Decodable {
        let schemaVersion: Int
        let peripheralIdentifier: String
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
