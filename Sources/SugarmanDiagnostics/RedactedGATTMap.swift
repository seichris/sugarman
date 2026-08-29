// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation
import GS3Transport

/// Redacted GATT map for P1. Service/characteristic UUIDs, properties, and
/// value byte counts only. Raw characteristic values and serial strings are
/// never included.
public struct RedactedGATTCharacteristic: Sendable, Equatable, Codable {
    public var uuid: String
    public var uuidShort: String?
    public var properties: [String]
    public var valueByteCount: Int?
    public var serialValueOmitted: Bool

    public init(
        uuid: String,
        uuidShort: String? = nil,
        properties: [String],
        valueByteCount: Int? = nil,
        serialValueOmitted: Bool = false
    ) {
        self.uuid = uuid
        self.uuidShort = uuidShort
        self.properties = properties
        self.valueByteCount = valueByteCount
        self.serialValueOmitted = serialValueOmitted
    }
}

public struct RedactedGATTService: Sendable, Equatable, Codable {
    public var uuid: String
    public var uuidShort: String?
    public var characteristics: [RedactedGATTCharacteristic]

    public init(uuid: String, uuidShort: String? = nil, characteristics: [RedactedGATTCharacteristic]) {
        self.uuid = uuid
        self.uuidShort = uuidShort
        self.characteristics = characteristics
    }
}

public struct RedactedGATTMap: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public var schemaVersion: Int
    public var peripheralID: String
    public var localName: String?
    public var services: [RedactedGATTService]
    public var serialByteCount: Int?
    public var sixByteAddressSource: SixByteAddressSource
    public var cipherHypothesis: CipherHypothesis
    public var notes: [String]

    public init(
        schemaVersion: Int = 1,
        peripheralID: String,
        localName: String? = nil,
        services: [RedactedGATTService],
        serialByteCount: Int? = nil,
        sixByteAddressSource: SixByteAddressSource = .notFound,
        cipherHypothesis: CipherHypothesis = .unknownUntilCapture,
        notes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.peripheralID = peripheralID
        self.localName = localName
        self.services = services
        self.serialByteCount = serialByteCount
        self.sixByteAddressSource = sixByteAddressSource
        self.cipherHypothesis = cipherHypothesis
        self.notes = notes
    }

    public var description: String {
        var lines = [
            "RedactedGATTMap schema=\(schemaVersion) services=\(services.count)",
            "sixByteAddressSource=\(sixByteAddressSource.rawValue)",
            "cipherHypothesis=\(cipherHypothesis.rawValue)",
            "serialByteCount=\(serialByteCount.map(String.init) ?? "nil")",
        ]
        for service in services {
            lines.append("service \(service.uuidShort ?? service.uuid) chars=\(service.characteristics.count)")
            for characteristic in service.characteristics {
                let short = characteristic.uuidShort ?? characteristic.uuid
                lines.append(
                    "  \(short) props=\(characteristic.properties.joined(separator: ",")) byteCount=\(characteristic.valueByteCount.map(String.init) ?? "-")"
                )
            }
        }
        lines.append(contentsOf: notes)
        return lines.joined(separator: "\n")
    }

    public var debugDescription: String { description }
}

public enum RedactedGATTMapBuilder: Sendable {
    public static let schemaVersion = 1
    public static let filename = "sugarman-gatt-map.json"

    public static func make(
        peripheralID: UUID,
        localName: String?,
        services: [GATTServiceSnapshot],
        serialByteCount: Int?,
        deviceInformationPresent: Bool
    ) -> RedactedGATTMap {
        let redactedServices = services.map { service in
            RedactedGATTService(
                uuid: service.uuid.uuidString,
                uuidShort: shortUUID(service.uuid),
                characteristics: service.characteristics.map { characteristic in
                    let isSerial = characteristic.uuid == DocumentedReadableCharacteristic.serialNumber
                    return RedactedGATTCharacteristic(
                        uuid: characteristic.uuid.uuidString,
                        uuidShort: shortUUID(characteristic.uuid),
                        properties: characteristic.properties,
                        valueByteCount: isSerial ? serialByteCount ?? characteristic.valueByteCount : characteristic.valueByteCount,
                        serialValueOmitted: isSerial
                    )
                }
            )
        }
        let source: SixByteAddressSource
        if serialByteCount == 6 {
            source = .deviceInformation
        } else {
            source = .notFound
        }
        var notes = [
            "Raw characteristic values omitted.",
            "Serial number bytes omitted; byteCount only.",
            "Does not identify a cipher. CipherHypothesis remains unknownUntilCapture.",
            "Simulator probe remains disabled; this map is produced on device only.",
        ]
        if deviceInformationPresent {
            notes.append("Device Information service was observed.")
        }
        return RedactedGATTMap(
            schemaVersion: schemaVersion,
            peripheralID: peripheralID.uuidString,
            localName: localName,
            services: redactedServices,
            serialByteCount: serialByteCount,
            sixByteAddressSource: source,
            cipherHypothesis: .unknownUntilCapture,
            notes: notes
        )
    }

    public static func jsonData(from map: RedactedGATTMap) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(map)
    }

    public static func shortUUID(_ uuid: UUID) -> String? {
        let text = uuid.uuidString.uppercased()
        if text.hasPrefix("0000"), text.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            let short = String(text.dropFirst(4).prefix(4))
            return short
        }
        return nil
    }
}

public struct GATTMapFileWriter: Sendable {
    public init() {}

    public func write(_ map: RedactedGATTMap, to directory: URL) throws -> URL {
        let data = try RedactedGATTMapBuilder.jsonData(from: map)
        let text = String(decoding: data, as: UTF8.self)
        let forbidden = ["writeValue", "RC4", "AES-OFB"]
        for needle in forbidden {
            if text.contains(needle) {
                throw TransportError.mutatingOperationRefused
            }
        }
        let url = directory.appendingPathComponent(RedactedGATTMapBuilder.filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
