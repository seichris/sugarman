// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

/// Opaque inputs required to decode an owned GS3 V3 glucose notification
/// offline. The sensor address is expanded to the observed session IV shape.
/// The separate algorithm key and IV are caller supplied so newly observed
/// vendor constants and private sensor material do not enter this repository
/// without their own legal/provenance decision.
public struct V3GlucoseCryptoMaterial:
    Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    fileprivate let transportInitializationVector: [UInt8]
    fileprivate let algorithmKey: [UInt8]
    fileprivate let algorithmInitializationVector: [UInt8]

    public init(
        sensorAddress: [UInt8],
        algorithmKey: [UInt8],
        algorithmInitializationVector: [UInt8]
    ) throws {
        guard sensorAddress.count == 6 else {
            throw GS3ProtocolError.invalidSensorAddressLength(sensorAddress.count)
        }
        guard algorithmKey.count == AES128.blockByteCount else {
            throw GS3ProtocolError.invalidAESKeyLength(algorithmKey.count)
        }
        guard algorithmInitializationVector.count == AES128.blockByteCount else {
            throw GS3ProtocolError.invalidInitializationVectorLength(
                algorithmInitializationVector.count
            )
        }

        self.transportInitializationVector = try v3TransportInitializationVector(
            sensorAddress: sensorAddress
        )
        self.algorithmKey = algorithmKey
        self.algorithmInitializationVector = algorithmInitializationVector
    }

    public var description: String {
        "V3GlucoseCryptoMaterial(transportIVByteCount: "
            + "\(transportInitializationVector.count), algorithmKeyByteCount: "
            + "\(algorithmKey.count), algorithmIVByteCount: "
            + "\(algorithmInitializationVector.count))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "transportIVByteCount": transportInitializationVector.count,
                "algorithmKeyByteCount": algorithmKey.count,
                "algorithmIVByteCount": algorithmInitializationVector.count,
            ],
            displayStyle: .struct
        )
    }
}

/// One record from a decrypted V3 `0x32` notification.
///
/// Names prefixed with `raw` retain native field boundaries without assigning
/// an unverified physical unit or product meaning. Glucose is the separately
/// decrypted algorithm field and is represented exactly as tenths of mmol/L.
public struct V3GlucoseRecord:
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    public let index: UInt16
    public let reindex: UInt16
    public let rawTemperature: UInt16
    public let rawDump: UInt16
    public let rawCurrent: UInt16
    public let rawDisplayGlucose: UInt16
    public let glucoseTenthsMillimolesPerLiter: UInt16
    public let trendCode: UInt8
    public let presentCState: Bool
    public let algorithmCState: UInt8
    public let tState: UInt8
    public let dState: UInt8
    public let algorithmReserved: UInt8
    public let rawCEVoltage: UInt16
    public let rawREVoltage: UInt16

    public var glucoseMillimolesPerLiter: Double {
        Double(glucoseTenthsMillimolesPerLiter) / 10
    }

    public var description: String {
        "V3GlucoseRecord(index: \(index), reindex: \(reindex), glucose: redacted)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "index": index,
                "reindex": reindex,
                "glucose": "redacted",
            ],
            displayStyle: .struct
        )
    }
}

public enum V3GlucoseBatchSource: UInt8, Sendable, Equatable {
    case liveNotification = 0x32
    case effectiveData = 0x39
}

public struct V3GlucoseBatch: Sendable, Equatable {
    public let source: V3GlucoseBatchSource
    public let records: [V3GlucoseRecord]

    public init(source: V3GlucoseBatchSource, records: [V3GlucoseRecord]) {
        self.source = source
        self.records = records
    }
}

/// Offline-only decoder for encrypted V3 `0x32` glucose notifications.
///
/// This type is not connected to `GS3CodecFactory` or `GS3Transport`. It
/// cannot scan, connect, subscribe, authenticate, activate, or write to a
/// sensor. Its input must come from a caller-controlled offline source.
public enum V3OfflineGlucoseNotificationDecoder: Sendable {
    public static let evidenceRevision =
        "owned-mainland-gs3-v3-glucose-source-map-2026-08-30"

    private static let headerByteCount = 5
    private static let recordByteCount = 16
    private static let trailerByteCount = 3

    public static func decode(
        _ frame: EncodedFrame,
        using material: V3GlucoseCryptoMaterial
    ) throws -> [V3GlucoseRecord] {
        let batch = try decodeBatch(frame, using: material)
        guard batch.source == .liveNotification else {
            throw GS3ProtocolError.unsupportedV3NotificationCommand(
                batch.source.rawValue
            )
        }
        return batch.records
    }

    /// Decodes either the observed live `0x32` batch or the structurally
    /// identical `0x39` effective-data batch returned after the bounded
    /// already-active history request.
    public static func decodeBatch(
        _ frame: EncodedFrame,
        using material: V3GlucoseCryptoMaterial
    ) throws -> V3GlucoseBatch {
        let encrypted = frame.bytes
        guard encrypted.count >= headerByteCount + recordByteCount + trailerByteCount else {
            throw GS3ProtocolError.invalidV3GlucoseNotificationLength(encrypted.count)
        }

        let plaintext = try AES128OFB.crypt(
            encrypted,
            key: V3ProtocolConstants.fixedKey,
            initializationVector: material.transportInitializationVector
        )

        guard Int(plaintext[0]) + 1 == plaintext.count else {
            throw GS3ProtocolError.invalidV3GlucoseNotificationDeclaredLength
        }
        guard let source = V3GlucoseBatchSource(rawValue: plaintext[1]) else {
            throw GS3ProtocolError.unsupportedV3NotificationCommand(plaintext[1])
        }

        let recordCount = Int(plaintext[2])
        guard recordCount > 0 else {
            throw GS3ProtocolError.invalidV3GlucoseRecordCount(recordCount)
        }
        guard recordCount <= (Int(UInt8.max) - 7) / recordByteCount else {
            throw GS3ProtocolError.invalidV3GlucoseRecordCount(recordCount)
        }

        let expectedByteCount = headerByteCount
            + (recordCount * recordByteCount)
            + trailerByteCount
        guard plaintext.count == expectedByteCount else {
            throw GS3ProtocolError.invalidV3GlucoseRecordLayout
        }
        guard plaintext.reduce(UInt8.zero, &+) == 0 else {
            throw GS3ProtocolError.invalidV3GlucoseNotificationChecksum
        }

        let startingIndex = littleEndianUInt16(plaintext, at: 3)
        let endingReindex = littleEndianUInt16(plaintext, at: plaintext.count - 3)
        var records: [V3GlucoseRecord] = []
        records.reserveCapacity(recordCount)

        for recordOffset in 0..<recordCount {
            let offset = headerByteCount + (recordOffset * recordByteCount)
            let algorithmCiphertext = Array(plaintext[(offset + 8)...(offset + 9)])
            let algorithmPlaintext = try AES128OFB.crypt(
                algorithmCiphertext,
                key: material.algorithmKey,
                initializationVector: material.algorithmInitializationVector
            )
            let flags = plaintext[offset + 10]
            let states = plaintext[offset + 11]

            records.append(
                V3GlucoseRecord(
                    index: startingIndex &+ UInt16(recordOffset),
                    reindex: endingReindex &+ UInt16(recordCount - 1 - recordOffset),
                    rawTemperature: littleEndianUInt16(plaintext, at: offset),
                    rawDump: littleEndianUInt16(plaintext, at: offset + 2),
                    rawCurrent: littleEndianUInt16(plaintext, at: offset + 4),
                    rawDisplayGlucose: littleEndianUInt16(plaintext, at: offset + 6),
                    glucoseTenthsMillimolesPerLiter: littleEndianUInt16(
                        algorithmPlaintext,
                        at: 0
                    ),
                    trendCode: flags & 0x07,
                    presentCState: flags & 0x08 != 0,
                    algorithmCState: flags >> 4,
                    tState: states & 0x03,
                    dState: (states >> 2) & 0x07,
                    algorithmReserved: states >> 5,
                    rawCEVoltage: littleEndianUInt16(plaintext, at: offset + 12),
                    rawREVoltage: littleEndianUInt16(plaintext, at: offset + 14)
                )
            )
        }

        return V3GlucoseBatch(source: source, records: records)
    }

    private static func littleEndianUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }
}
