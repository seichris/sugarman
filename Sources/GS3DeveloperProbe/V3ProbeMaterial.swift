// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Protocol

public enum V3ProbeMaterialError: Error, Sendable, Equatable {
    case invalidDocument
    case unsupportedSchemaVersion(Int)
    case invalidHex(field: String)
    case invalidLength(field: String, expected: Int, actual: Int)
    case invalidPeripheralName
    case invalidStoredMaterial
}

extension V3ProbeMaterialError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidDocument:
            return "The private probe material document is malformed."
        case .unsupportedSchemaVersion(let version):
            return "Private probe material schema version \(version) is unsupported."
        case .invalidHex(let field):
            return "Private probe field \(field) must contain ASCII hexadecimal bytes."
        case .invalidLength(let field, let expected, let actual):
            return "Private probe field \(field) must contain \(expected) bytes; received \(actual)."
        case .invalidPeripheralName:
            return "The expected peripheral name is invalid."
        case .invalidStoredMaterial:
            return "Stored private probe material is invalid."
        }
    }
}

/// Opaque material for one owner-controlled, already-active V3 sensor.
///
/// Values enter only through a post-install private import and are normalized
/// for device-only Keychain storage. Descriptions and reflection expose only
/// byte counts. This type cannot represent registration, binding, activation,
/// reset, or any lifecycle command.
public struct V3ProbeMaterial:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public static let schemaVersion = 1

    public let expectedPeripheralName: String?
    public let effectiveDataStartIndex: UInt16
    let sensorAddress: [UInt8]
    let authenticationID: [UInt8]
    let registeredBlock: [UInt8]
    let algorithmKey: [UInt8]
    let algorithmInitializationVector: [UInt8]

    public init(
        expectedPeripheralName: String?,
        effectiveDataStartIndex: UInt16,
        sensorAddress: [UInt8],
        authenticationID: [UInt8],
        registeredBlock: [UInt8],
        algorithmKey: [UInt8],
        algorithmInitializationVector: [UInt8]
    ) throws {
        if let expectedPeripheralName {
            let utf8 = Array(expectedPeripheralName.utf8)
            guard !utf8.isEmpty,
                  utf8.count <= 64,
                  utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else {
                throw V3ProbeMaterialError.invalidPeripheralName
            }
        }
        try Self.requireLength(sensorAddress, field: "sensorAddressHex", expected: 6)
        try Self.requireLength(authenticationID, field: "authenticationIDHex", expected: 12)
        try Self.requireLength(registeredBlock, field: "registeredBlockHex", expected: 16)
        try Self.requireLength(algorithmKey, field: "algorithmKeyHex", expected: 16)
        try Self.requireLength(
            algorithmInitializationVector,
            field: "algorithmIVHex",
            expected: 16
        )

        self.expectedPeripheralName = expectedPeripheralName
        self.effectiveDataStartIndex = effectiveDataStartIndex
        self.sensorAddress = sensorAddress
        self.authenticationID = authenticationID
        self.registeredBlock = registeredBlock
        self.algorithmKey = algorithmKey
        self.algorithmInitializationVector = algorithmInitializationVector
    }

    public init(importJSONData data: Data) throws {
        let document: ImportDocument
        do {
            document = try JSONDecoder().decode(ImportDocument.self, from: data)
        } catch {
            throw V3ProbeMaterialError.invalidDocument
        }
        guard document.schemaVersion == Self.schemaVersion else {
            throw V3ProbeMaterialError.unsupportedSchemaVersion(document.schemaVersion)
        }
        try self.init(
            expectedPeripheralName: document.expectedPeripheralName,
            effectiveDataStartIndex: document.effectiveDataStartIndex,
            sensorAddress: try Self.hexBytes(
                document.sensorAddressHex,
                field: "sensorAddressHex"
            ),
            authenticationID: try Self.hexBytes(
                document.authenticationIDHex,
                field: "authenticationIDHex"
            ),
            registeredBlock: try Self.hexBytes(
                document.registeredBlockHex,
                field: "registeredBlockHex"
            ),
            algorithmKey: try Self.hexBytes(
                document.algorithmKeyHex,
                field: "algorithmKeyHex"
            ),
            algorithmInitializationVector: try Self.hexBytes(
                document.algorithmIVHex,
                field: "algorithmIVHex"
            )
        )
    }

    public var description: String {
        "V3ProbeMaterial(peripheralNameByteCount: "
            + "\(expectedPeripheralName?.utf8.count ?? 0), sensorAddressByteCount: "
            + "\(sensorAddress.count), authenticationIDByteCount: "
            + "\(authenticationID.count), registeredBlockByteCount: "
            + "\(registeredBlock.count), algorithmKeyByteCount: "
            + "\(algorithmKey.count), algorithmIVByteCount: "
            + "\(algorithmInitializationVector.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "peripheralNameByteCount": expectedPeripheralName?.utf8.count ?? 0,
                "sensorAddressByteCount": sensorAddress.count,
                "authenticationIDByteCount": authenticationID.count,
                "registeredBlockByteCount": registeredBlock.count,
                "algorithmKeyByteCount": algorithmKey.count,
                "algorithmIVByteCount": algorithmInitializationVector.count,
            ],
            displayStyle: .struct
        )
    }

    func authenticationFrame() throws -> EncodedFrame {
        let inputs = try V3AuthenticationInputs(
            deviceType: 0,
            sensorAddress: sensorAddress,
            authenticationID: authenticationID,
            recoveredRegisteredBlock: registeredBlock
        )
        return try V3OfflineAuthenticationCodec.encode(inputs)
    }

    func effectiveDataFrame() throws -> EncodedFrame {
        try V3OfflineEffectiveDataRequestCodec.encode(
            V3EffectiveDataRequest(startingIndex: effectiveDataStartIndex),
            sensorAddress: sensorAddress
        )
    }

    func decodeControl(_ frame: EncodedFrame) throws -> V3ControlResponse {
        try V3OfflineControlResponseDecoder.decode(
            frame,
            sensorAddress: sensorAddress
        )
    }

    func decodeGlucose(_ frame: EncodedFrame) throws -> V3GlucoseBatch {
        let crypto = try V3GlucoseCryptoMaterial(
            sensorAddress: sensorAddress,
            algorithmKey: algorithmKey,
            algorithmInitializationVector: algorithmInitializationVector
        )
        return try V3OfflineGlucoseNotificationDecoder.decodeBatch(
            frame,
            using: crypto
        )
    }

    func encodedForStorage() -> Data {
        let name = expectedPeripheralName.map { Array($0.utf8) } ?? []
        var bytes: [UInt8] = [UInt8(Self.schemaVersion), UInt8(name.count)]
        bytes.append(contentsOf: name)
        bytes.append(UInt8(truncatingIfNeeded: effectiveDataStartIndex))
        bytes.append(UInt8(truncatingIfNeeded: effectiveDataStartIndex >> 8))
        bytes.append(contentsOf: sensorAddress)
        bytes.append(contentsOf: authenticationID)
        bytes.append(contentsOf: registeredBlock)
        bytes.append(contentsOf: algorithmKey)
        bytes.append(contentsOf: algorithmInitializationVector)
        return Data(bytes)
    }

    init(storedData: Data) throws {
        let bytes = [UInt8](storedData)
        guard bytes.count >= 2,
              bytes[0] == UInt8(Self.schemaVersion) else {
            throw V3ProbeMaterialError.invalidStoredMaterial
        }
        let nameCount = Int(bytes[1])
        let fixedTailCount = 2 + 6 + 12 + 16 + 16 + 16
        guard bytes.count == 2 + nameCount + fixedTailCount else {
            throw V3ProbeMaterialError.invalidStoredMaterial
        }
        var offset = 2
        let nameBytes = Array(bytes[offset..<(offset + nameCount)])
        offset += nameCount
        let name: String?
        if nameBytes.isEmpty {
            name = nil
        } else if let decoded = String(bytes: nameBytes, encoding: .utf8) {
            name = decoded
        } else {
            throw V3ProbeMaterialError.invalidStoredMaterial
        }
        let startIndex = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        offset += 2

        func take(_ count: Int) -> [UInt8] {
            defer { offset += count }
            return Array(bytes[offset..<(offset + count)])
        }

        try self.init(
            expectedPeripheralName: name,
            effectiveDataStartIndex: startIndex,
            sensorAddress: take(6),
            authenticationID: take(12),
            registeredBlock: take(16),
            algorithmKey: take(16),
            algorithmInitializationVector: take(16)
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
        let effectiveDataStartIndex: UInt16
    }

    private static func requireLength(
        _ bytes: [UInt8],
        field: String,
        expected: Int
    ) throws {
        guard bytes.count == expected else {
            throw V3ProbeMaterialError.invalidLength(
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
            throw V3ProbeMaterialError.invalidHex(field: field)
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
