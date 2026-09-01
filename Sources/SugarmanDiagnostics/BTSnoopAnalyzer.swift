// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Redacted summary of an Android BTSnoop / HCI snoop file.
///
/// Counts, lengths, and GATT UUID allowlists only. Never includes a full
/// Bluetooth address, full serial, or application/auth payload bytes.
/// Does not implement a cipher and will not decode glucose.
public struct BTSnoopSummary: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible {
    public var schemaVersion: Int
    public var recordCount: Int
    public var leAdvertisementCount: Int
    public var scanResponseCount: Int
    public var connectionEventCount: Int
    public var attPduCount: Int
    public var advertisedNames: [String]
    public var advertisedServiceUUIDs: [String]
    public var manufacturerDataLengths: [Int]
    public var attOperations: [ATTOperationSummary]
    /// Android HCI peer-address field observed. Not an iOS-accessible source.
    public var hciPeerAddressFieldObserved: Bool
    public var sixByteFieldInAdvertisementPayload: Bool
    public var sixByteFieldInScanResponsePayload: Bool
    public var sixByteFieldInDeviceInformationRead: Bool
    public var sixByteFieldInOtherReadable: Bool
    public var sixByteAddressSource: SixByteAddressSource
    public var cipherHypothesis: CipherHypothesis
    public var refusedGlucoseDecode: Bool
    public var notes: [String]

    public var description: String {
        var lines: [String] = [
            "BTSnoopSummary schema=\(schemaVersion) records=\(recordCount)",
            "LE adv=\(leAdvertisementCount) scanRsp=\(scanResponseCount) connections=\(connectionEventCount) ATT=\(attPduCount)",
            "names=\(advertisedNames.sorted().joined(separator: ","))",
            "serviceUUIDs=\(advertisedServiceUUIDs.sorted().joined(separator: ","))",
            "manufacturerDataLengths=\(manufacturerDataLengths.sorted().map(String.init).joined(separator: ","))",
            "hciPeerAddressFieldObserved=\(hciPeerAddressFieldObserved) (Android-only; not an iOS source)",
            "sixByteAddressSource=\(sixByteAddressSource.rawValue)",
            "cipherHypothesis=\(cipherHypothesis.rawValue)",
            "refusedGlucoseDecode=\(refusedGlucoseDecode)",
        ]
        for op in attOperations {
            lines.append("ATT \(op.opcodeName) handle=\(op.handle.map { String(format: "0x%04X", $0) } ?? "-") uuid=\(op.uuid ?? "-") valueByteCount=\(op.valueByteCount.map(String.init) ?? "-")")
        }
        lines.append(contentsOf: notes)
        return lines.joined(separator: "\n")
    }

    public var debugDescription: String { description }
}

public struct ATTOperationSummary: Sendable, Equatable, Codable {
    public var opcodeName: String
    public var opcode: UInt8
    public var handle: UInt16?
    public var uuid: String?
    public var valueByteCount: Int?
}

public enum BTSnoopError: Error, Sendable, Equatable {
    case invalidMagic
    case truncated
    case unsupportedVersion(UInt32)
    case unsupportedDatalink(UInt32)
}

/// Parses Android BTSnoop / HCI snoop files for P1 analysis.
///
/// Fail closed: no cipher, no glucose decode, no printing of MAC/serial/auth
/// payloads. Feed git fixtures or gitignored private-evidence locally.
public enum BTSnoopAnalyzer: Sendable {
    public static let schemaVersion = 1

    public static func summarize(fileURL: URL) throws -> BTSnoopSummary {
        let data = try Data(contentsOf: fileURL)
        return try summarize(data: data)
    }

    public static func summarize(data: Data) throws -> BTSnoopSummary {
        guard data.count >= 16 else { throw BTSnoopError.truncated }
        let magic = data.prefix(8)
        guard magic == Data("btsnoop\0".utf8) else { throw BTSnoopError.invalidMagic }
        let version = readUInt32BE(data, 8)
        guard version == 1 else { throw BTSnoopError.unsupportedVersion(version) }
        let datalink = readUInt32BE(data, 12)
        guard datalink == 1002 else { throw BTSnoopError.unsupportedDatalink(datalink) }
        var offset = 16
        var recordCount = 0
        var advCount = 0
        var scanRspCount = 0
        var connectionCount = 0
        var attCount = 0
        var names: Set<String> = []
        var serviceUUIDs: Set<String> = []
        var mfgLengths: [Int] = []
        var attOps: [ATTOperationSummary] = []
        var hciPeer = false
        var advertisementMatches: [Data: AddressPayloadMatch] = [:]
        var sixInDIS = false
        var sixInOther = false
        var notes: [String] = [
            "Payloads, full MACs, and serials omitted.",
            "Does not identify a cipher. CipherHypothesis remains unknownUntilCapture.",
        ]
        var aclReassembly: [UInt32: Data] = [:]
        var peerAddressesByConnection: [UInt16: [UInt8]] = [:]
        var allConnectedPeers: Set<Data> = []
        var characteristicUUIDsByConnection: [UInt16: [UInt16: String]] = [:]
        var pendingReadHandleByConnection: [UInt16: UInt16] = [:]
        var pendingReadByTypeUUIDByConnection: [UInt16: String] = [:]

        while offset + 24 <= data.count {
            let originalLength = Int(readUInt32BE(data, offset))
            let includedLength = Int(readUInt32BE(data, offset + 4))
            let packetFlags = readUInt32BE(data, offset + 8)
            _ = readUInt32BE(data, offset + 12) // drops
            _ = readUInt64BE(data, offset + 16)
            offset += 24
            guard includedLength <= originalLength, offset + includedLength <= data.count else {
                throw BTSnoopError.truncated
            }
            let packet = data.subdata(in: offset..<(offset + includedLength))
            offset += includedLength
            recordCount += 1
            _ = originalLength

            guard let (kind, body) = splitH4(packet) else { continue }
            switch kind {
            case .event:
                parseEvent(
                    body,
                    advCount: &advCount,
                    scanRspCount: &scanRspCount,
                    connectionCount: &connectionCount,
                    names: &names,
                    serviceUUIDs: &serviceUUIDs,
                    mfgLengths: &mfgLengths,
                    hciPeer: &hciPeer,
                    advertisementMatches: &advertisementMatches,
                    peerAddressesByConnection: &peerAddressesByConnection,
                    allConnectedPeers: &allConnectedPeers,
                    reassembly: &aclReassembly,
                    characteristicUUIDsByConnection: &characteristicUUIDsByConnection,
                    pendingReadHandleByConnection: &pendingReadHandleByConnection,
                    pendingReadByTypeUUIDByConnection: &pendingReadByTypeUUIDByConnection
                )
            case .acl:
                parseACL(
                    body,
                    direction: UInt8(packetFlags & 0x1),
                    reassembly: &aclReassembly,
                    attCount: &attCount,
                    attOps: &attOps,
                    serviceUUIDs: &serviceUUIDs,
                    sixInDIS: &sixInDIS,
                    sixInOther: &sixInOther,
                    peerAddressesByConnection: peerAddressesByConnection,
                    characteristicUUIDsByConnection: &characteristicUUIDsByConnection,
                    pendingReadHandleByConnection: &pendingReadHandleByConnection,
                    pendingReadByTypeUUIDByConnection: &pendingReadByTypeUUIDByConnection,
                    notes: &notes
                )
            case .command, .sco, .iso:
                continue
            }
        }

        guard offset == data.count else { throw BTSnoopError.truncated }

        let connectedAdvertisementMatches = advertisementMatches.filter {
            allConnectedPeers.contains($0.key)
        }
        let sixInAdv = connectedAdvertisementMatches.contains { $0.value.advertisement }
        let sixInScan = connectedAdvertisementMatches.contains { $0.value.scanResponse }

        let source = resolveAddressSource(
            sixInAdv: sixInAdv,
            sixInScan: sixInScan,
            sixInDIS: sixInDIS,
            sixInOther: sixInOther
        )
        if hciPeer && source == .notFound {
            notes.append("HCI peer-address field was present but is not an iOS-accessible source.")
        }

        return BTSnoopSummary(
            schemaVersion: schemaVersion,
            recordCount: recordCount,
            leAdvertisementCount: advCount,
            scanResponseCount: scanRspCount,
            connectionEventCount: connectionCount,
            attPduCount: attCount,
            advertisedNames: names.sorted(),
            advertisedServiceUUIDs: serviceUUIDs.sorted(),
            manufacturerDataLengths: mfgLengths,
            attOperations: attOps,
            hciPeerAddressFieldObserved: hciPeer,
            sixByteFieldInAdvertisementPayload: sixInAdv,
            sixByteFieldInScanResponsePayload: sixInScan,
            sixByteFieldInDeviceInformationRead: sixInDIS,
            sixByteFieldInOtherReadable: sixInOther,
            sixByteAddressSource: source,
            cipherHypothesis: .unknownUntilCapture,
            refusedGlucoseDecode: true,
            notes: notes
        )
    }

    /// Always throws. Application payloads are never decoded as glucose.
    public static func decodeGlucose(_: Data) throws {
        throw GlucoseDecodeRefusal.refusedUntilPhysicalParity
    }

    public static func jsonData(from summary: BTSnoopSummary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(summary)
    }

    private enum H4Kind {
        case command, acl, sco, event, iso
    }

    private struct AddressPayloadMatch {
        var advertisement = false
        var scanResponse = false
    }

    private static func splitH4(_ packet: Data) -> (H4Kind, Data)? {
        guard packet.count >= 1 else { return nil }
        let type = byte(packet, 0)
        let body = slice(packet, 1, packet.count - 1) ?? Data()
        switch type {
        case 0x01: return (.command, body)
        case 0x02: return (.acl, body)
        case 0x03: return (.sco, body)
        case 0x04: return (.event, body)
        case 0x05: return (.iso, body)
        default:
            // Unencapsulated HCI event: event code is first byte.
            if type == 0x05 || type == 0x3E || type == 0x0E || type == 0x13 {
                return (.event, packet)
            }
            return nil
        }
    }

    private static func parseEvent(
        _ body: Data,
        advCount: inout Int,
        scanRspCount: inout Int,
        connectionCount: inout Int,
        names: inout Set<String>,
        serviceUUIDs: inout Set<String>,
        mfgLengths: inout [Int],
        hciPeer: inout Bool,
        advertisementMatches: inout [Data: AddressPayloadMatch],
        peerAddressesByConnection: inout [UInt16: [UInt8]],
        allConnectedPeers: inout Set<Data>,
        reassembly: inout [UInt32: Data],
        characteristicUUIDsByConnection: inout [UInt16: [UInt16: String]],
        pendingReadHandleByConnection: inout [UInt16: UInt16],
        pendingReadByTypeUUIDByConnection: inout [UInt16: String]
    ) {
        guard body.count >= 2 else { return }
        guard let eventCode = byte(body, 0), let paramLenByte = byte(body, 1) else { return }
        let paramLen = Int(paramLenByte)
        guard body.count >= 2 + paramLen else { return }
        guard let params = slice(body, 2, paramLen) else { return }
        if eventCode == 0x05, params.count >= 4,
           let rawHandle = readUInt16LE(params, 1) {
            clearConnectionState(
                rawHandle & 0x0FFF,
                peerAddressesByConnection: &peerAddressesByConnection,
                reassembly: &reassembly,
                characteristicUUIDsByConnection: &characteristicUUIDsByConnection,
                pendingReadHandleByConnection: &pendingReadHandleByConnection,
                pendingReadByTypeUUIDByConnection: &pendingReadByTypeUUIDByConnection
            )
            return
        }
        guard eventCode == 0x3E, params.count >= 1, let sub = byte(params, 0) else { return }
        let rest = slice(params, 1, params.count - 1) ?? Data()
        switch sub {
        case 0x01, 0x0A: // Connection Complete / Enhanced Connection Complete
            connectionCount += 1
            if rest.count >= 11, byte(rest, 0) == 0 {
                // Enhanced: status(1)+handle(2)+role(1)+peerType(1)+addr(6)
                // Legacy:    status(1)+handle(2)+role(1)+peerType(1)+addr(6)
                let addrOffset = 5
                if let connectionHandle = readUInt16LE(rest, 1),
                   let addrData = slice(rest, addrOffset, 6) {
                    let handle = connectionHandle & 0x0FFF
                    clearConnectionState(
                        handle,
                        peerAddressesByConnection: &peerAddressesByConnection,
                        reassembly: &reassembly,
                        characteristicUUIDsByConnection: &characteristicUUIDsByConnection,
                        pendingReadHandleByConnection: &pendingReadHandleByConnection,
                        pendingReadByTypeUUIDByConnection: &pendingReadByTypeUUIDByConnection
                    )
                    hciPeer = true
                    peerAddressesByConnection[handle] = Array(addrData)
                    allConnectedPeers.insert(addrData)
                }
            }
        case 0x02: // LE Advertising Report
            parseLegacyAdvReport(
                Data(rest),
                advCount: &advCount,
                scanRspCount: &scanRspCount,
                names: &names,
                serviceUUIDs: &serviceUUIDs,
                mfgLengths: &mfgLengths,
                hciPeer: &hciPeer,
                advertisementMatches: &advertisementMatches
            )
        case 0x0D: // LE Extended Advertising Report
            parseExtendedAdvReport(
                Data(rest),
                advCount: &advCount,
                scanRspCount: &scanRspCount,
                names: &names,
                serviceUUIDs: &serviceUUIDs,
                mfgLengths: &mfgLengths,
                hciPeer: &hciPeer,
                advertisementMatches: &advertisementMatches
            )
        default:
            break
        }
    }

    private static func parseLegacyAdvReport(
        _ data: Data,
        advCount: inout Int,
        scanRspCount: inout Int,
        names: inout Set<String>,
        serviceUUIDs: inout Set<String>,
        mfgLengths: inout [Int],
        hciPeer: inout Bool,
        advertisementMatches: inout [Data: AddressPayloadMatch]
    ) {
        guard data.count >= 1, let numByte = byte(data, 0) else { return }
        var offset = 1
        let num = Int(numByte)
        for _ in 0..<num {
            guard offset + 8 <= data.count else { return }
            guard let eventType = byte(data, offset) else { return }
            offset += 1
            offset += 1 // addr type
            guard let addrData = slice(data, offset, 6) else { return }
            let addr = Array(addrData)
            offset += 6
            hciPeer = true
            guard offset < data.count, let dataLenByte = byte(data, offset) else { return }
            let dataLen = Int(dataLenByte)
            offset += 1
            guard let ad = slice(data, offset, dataLen) else { return }
            offset += dataLen
            if offset < data.count { offset += 1 } // RSSI
            let isScan = eventType == 0x04
            if isScan {
                scanRspCount += 1
            } else {
                advCount += 1
            }
            inspectAD(
                ad,
                peer: addr,
                names: &names,
                serviceUUIDs: &serviceUUIDs,
                mfgLengths: &mfgLengths,
                isScanResponse: isScan,
                advertisementMatches: &advertisementMatches
            )
        }
    }

    private static func parseExtendedAdvReport(
        _ data: Data,
        advCount: inout Int,
        scanRspCount: inout Int,
        names: inout Set<String>,
        serviceUUIDs: inout Set<String>,
        mfgLengths: inout [Int],
        hciPeer: inout Bool,
        advertisementMatches: inout [Data: AddressPayloadMatch]
    ) {
        guard data.count >= 1, let numByte = byte(data, 0) else { return }
        var offset = 1
        let num = Int(numByte)
        for _ in 0..<num {
            // eventType(2)+addrType(1)+addr(6)+primPHY(1)+secPHY(1)+SID(1)+tx(1)+RSSI(1)+interval(2)+directType(1)+directAddr(6)+dataLen(1)
            guard offset + 24 <= data.count,
                  let eventType = readUInt16LE(data, offset) else { return }
            offset += 2
            offset += 1
            guard let addrData = slice(data, offset, 6) else { return }
            let addr = Array(addrData)
            offset += 6
            hciPeer = true
            offset += 1 + 1 + 1 + 1 + 1 + 2 + 1
            offset += 6 // direct addr
            guard let dataLenByte = byte(data, offset) else { return }
            let dataLen = Int(dataLenByte)
            offset += 1
            guard let ad = slice(data, offset, dataLen) else { return }
            offset += dataLen
            let isScan = (eventType & 0x0008) != 0
            if isScan {
                scanRspCount += 1
            } else {
                advCount += 1
            }
            inspectAD(
                ad,
                peer: addr,
                names: &names,
                serviceUUIDs: &serviceUUIDs,
                mfgLengths: &mfgLengths,
                isScanResponse: isScan,
                advertisementMatches: &advertisementMatches
            )
        }
    }

    private static func inspectAD(
        _ ad: Data,
        peer: [UInt8],
        names: inout Set<String>,
        serviceUUIDs: inout Set<String>,
        mfgLengths: inout [Int],
        isScanResponse: Bool,
        advertisementMatches: inout [Data: AddressPayloadMatch]
    ) {
        var offset = 0
        while offset < ad.count {
            guard let lengthByte = byte(ad, offset) else { break }
            let length = Int(lengthByte)
            if length == 0 { break }
            guard offset + 1 + length <= ad.count, let type = byte(ad, offset + 1) else { break }
            let payload = slice(ad, offset + 2, length - 1) ?? Data()
            offset += 1 + length
            switch type {
            case 0x08, 0x09:
                if let name = String(data: payload, encoding: .utf8) {
                    names.insert(redactName(name))
                }
            case 0x02, 0x03, 0x14, 0x1F:
                var i = 0
                while i + 2 <= payload.count {
                    if let uuid = hexUUID16(payload, i) {
                        serviceUUIDs.insert(uuid)
                    }
                    i += 2
                }
            case 0x06, 0x07:
                var i = 0
                while i + 16 <= payload.count {
                    if let uuid = formatUUID128(payload, i) {
                        serviceUUIDs.insert(uuid)
                    }
                    i += 16
                }
            case 0xFF:
                mfgLengths.append(payload.count)
            default:
                break
            }
            if payloadLooksLikeAddress(payload, peer: peer) {
                let key = Data(peer)
                var match = advertisementMatches[key] ?? AddressPayloadMatch()
                if isScanResponse {
                    match.scanResponse = true
                } else {
                    match.advertisement = true
                }
                advertisementMatches[key] = match
            }
        }
    }

    private static func parseACL(
        _ body: Data,
        direction: UInt8,
        reassembly: inout [UInt32: Data],
        attCount: inout Int,
        attOps: inout [ATTOperationSummary],
        serviceUUIDs: inout Set<String>,
        sixInDIS: inout Bool,
        sixInOther: inout Bool,
        peerAddressesByConnection: [UInt16: [UInt8]],
        characteristicUUIDsByConnection: inout [UInt16: [UInt16: String]],
        pendingReadHandleByConnection: inout [UInt16: UInt16],
        pendingReadByTypeUUIDByConnection: inout [UInt16: String],
        notes: inout [String]
    ) {
        guard body.count >= 4,
              let handleFlags = readUInt16LE(body, 0),
              let aclLen = readUInt16LE(body, 2) else { return }
        let handle = handleFlags & 0x0FFF
        let pb = (handleFlags >> 12) & 0x3
        let key = reassemblyKey(handle: handle, direction: direction)
        let dataLength = Int(aclLen)
        guard let chunk = slice(body, 4, dataLength) else { return }
        if pb == 0x01 {
            var existing = reassembly[key] ?? Data()
            existing.append(chunk)
            reassembly[key] = existing
        } else {
            reassembly[key] = chunk
        }
        guard let l2cap = reassembly[key], l2cap.count >= 4,
              let l2capLen16 = readUInt16LE(l2cap, 0),
              let cid = readUInt16LE(l2cap, 2) else { return }
        let l2capLen = Int(l2capLen16)
        guard let att = slice(l2cap, 4, l2capLen) else { return }
        reassembly[key] = nil
        guard cid == 0x0004 else { return } // ATT
        parseATT(
            att,
            attCount: &attCount,
            attOps: &attOps,
            serviceUUIDs: &serviceUUIDs,
            sixInDIS: &sixInDIS,
            sixInOther: &sixInOther,
            connectionHandle: handle,
            knownPeerAddress: peerAddressesByConnection[handle],
            characteristicUUIDsByConnection: &characteristicUUIDsByConnection,
            pendingReadHandleByConnection: &pendingReadHandleByConnection,
            pendingReadByTypeUUIDByConnection: &pendingReadByTypeUUIDByConnection,
            notes: &notes
        )
    }

    private static func parseATT(
        _ att: Data,
        attCount: inout Int,
        attOps: inout [ATTOperationSummary],
        serviceUUIDs: inout Set<String>,
        sixInDIS: inout Bool,
        sixInOther: inout Bool,
        connectionHandle: UInt16,
        knownPeerAddress: [UInt8]?,
        characteristicUUIDsByConnection: inout [UInt16: [UInt16: String]],
        pendingReadHandleByConnection: inout [UInt16: UInt16],
        pendingReadByTypeUUIDByConnection: inout [UInt16: String],
        notes: inout [String]
    ) {
        guard att.count >= 1, let opcode = byte(att, 0) else { return }
        attCount += 1
        let name = attOpcodeName(opcode)
        var handle: UInt16?
        var uuid: String?
        var valueByteCount: Int?

        switch opcode {
        case 0x01: // Error Response: request opcode + attribute handle + error code
            if att.count >= 5 { handle = readUInt16LE(att, 2) }
            if byte(att, 1) == 0x08 {
                pendingReadByTypeUUIDByConnection[connectionHandle] = nil
            }
            pendingReadHandleByConnection[connectionHandle] = nil
        case 0x04, 0x06, 0x10: // find/read-by-group requests
            if att.count >= 5 { handle = readUInt16LE(att, 1) }
            uuid = uuidFromTail(att, start: 5)
        case 0x08: // Read By Type Request
            if att.count >= 5 { handle = readUInt16LE(att, 1) }
            uuid = uuidFromTail(att, start: 5)
            pendingReadByTypeUUIDByConnection[connectionHandle] = uuid
        case 0x05: // Find Information Response
            if att.count >= 2, let format = byte(att, 1) {
                let uuidLen = format == 0x01 ? 2 : 16
                var i = 2
                while i + 2 + uuidLen <= att.count {
                    handle = readUInt16LE(att, i)
                    uuid = format == 0x01
                        ? hexUUID16(att, i + 2)
                        : formatUUID128(att, i + 2)
                    if let handle, let uuid {
                        characteristicUUIDsByConnection[connectionHandle, default: [:]][handle] = uuid
                        serviceUUIDs.insert(uuid)
                    }
                    i += 2 + uuidLen
                }
            }
        case 0x09, 0x11: // Read By Type / Group Type Response
            let requestedType = opcode == 0x09
                ? pendingReadByTypeUUIDByConnection.removeValue(forKey: connectionHandle)
                : nil
            let isCharacteristicDeclaration = requestedType?.uppercased() == "2803"
            if att.count >= 2, let pairLenByte = byte(att, 1) {
                let pairLen = Int(pairLenByte)
                var i = 2
                while pairLen >= 2, i + pairLen <= att.count {
                    handle = readUInt16LE(att, i)
                    let value = slice(att, i + 2, pairLen - 2) ?? Data()
                    valueByteCount = value.count
                    if opcode == 0x11, value.count == 4 {
                        uuid = hexUUID16(value, 2)
                    } else if opcode == 0x11, value.count == 18 {
                        uuid = formatUUID128(value, 2)
                    } else if value.count >= 3, isCharacteristicDeclaration, pairLen >= 5 {
                        // Characteristic declaration: props(1)+valueHandle(2)+uuid
                        if let charUUID = slice(value, 3, value.count - 3) {
                            if charUUID.count == 2 {
                                uuid = hexUUID16(charUUID, 0)
                            } else if charUUID.count == 16 {
                                uuid = formatUUID128(charUUID, 0)
                            }
                        }
                        if let valueHandle = readUInt16LE(value, 1), let uuid {
                            characteristicUUIDsByConnection[connectionHandle, default: [:]][valueHandle] = uuid
                        }
                    } else if opcode == 0x09 {
                        uuid = requestedType
                    }
                    if let uuid { serviceUUIDs.insert(uuid) }
                    i += pairLen
                }
            }
        case 0x0A, 0x0C: // Read / Read Blob Request
            if att.count >= 3, let readHandle = readUInt16LE(att, 1) {
                handle = readHandle
                pendingReadHandleByConnection[connectionHandle] = readHandle
                uuid = characteristicUUIDsByConnection[connectionHandle]?[readHandle]
            }
        case 0x0B, 0x0D: // Read / Read Blob Response
            valueByteCount = att.count - 1
            let readHandle = pendingReadHandleByConnection.removeValue(forKey: connectionHandle)
            handle = readHandle
            uuid = readHandle.flatMap { characteristicUUIDsByConnection[connectionHandle]?[$0] }
            inspectReadValue(
                slice(att, 1, att.count - 1) ?? Data(),
                uuid: uuid,
                sixInDIS: &sixInDIS,
                sixInOther: &sixInOther,
                knownPeerAddress: knownPeerAddress
            )
        case 0x12, 0x52: // Write Request / Write Command
            if att.count >= 3 {
                handle = readUInt16LE(att, 1)
                valueByteCount = att.count - 3
                uuid = handle.flatMap { characteristicUUIDsByConnection[connectionHandle]?[$0] }
            }
            notes.append("Write ATT PDU omitted (possible auth); length only.")
        case 0x16, 0x17: // Prepare Write Request / Response: handle + offset + value
            if att.count >= 5 {
                handle = readUInt16LE(att, 1)
                valueByteCount = att.count - 5
                uuid = handle.flatMap { characteristicUUIDsByConnection[connectionHandle]?[$0] }
            }
            notes.append("Prepare-write ATT PDU omitted (possible auth); length only.")
        case 0x1B, 0x1D: // Notification / Indication
            if att.count >= 3 {
                handle = readUInt16LE(att, 1)
                valueByteCount = att.count - 3
                uuid = handle.flatMap { characteristicUUIDsByConnection[connectionHandle]?[$0] }
            }
        default:
            if att.count >= 3 { handle = readUInt16LE(att, 1) }
            valueByteCount = max(0, att.count - 1)
        }

        attOps.append(
            ATTOperationSummary(
                opcodeName: name,
                opcode: opcode,
                handle: handle,
                uuid: uuid,
                valueByteCount: valueByteCount
            )
        )
    }

    private static func inspectReadValue(
        _ value: Data,
        uuid: String?,
        sixInDIS: inout Bool,
        sixInOther: inout Bool,
        knownPeerAddress: [UInt8]?
    ) {
        let matchesPeer = payloadLooksLikeAddress(value, peer: knownPeerAddress)
        let textualMatchesPeer = textualAddress(value).map { candidate in
            guard let knownPeerAddress else { return false }
            return candidate == knownPeerAddress || candidate == Array(knownPeerAddress.reversed())
        } ?? false
        guard let uuid, matchesPeer || textualMatchesPeer else { return }
        let dis = isDeviceInformationUUID(uuid) || isSerialUUID(uuid)
        if dis {
            sixInDIS = true
        } else {
            sixInOther = true
        }
    }

    private static func reassemblyKey(handle: UInt16, direction: UInt8) -> UInt32 {
        (UInt32(direction & 0x1) << 16) | UInt32(handle)
    }

    private static func clearConnectionState(
        _ handle: UInt16,
        peerAddressesByConnection: inout [UInt16: [UInt8]],
        reassembly: inout [UInt32: Data],
        characteristicUUIDsByConnection: inout [UInt16: [UInt16: String]],
        pendingReadHandleByConnection: inout [UInt16: UInt16],
        pendingReadByTypeUUIDByConnection: inout [UInt16: String]
    ) {
        peerAddressesByConnection[handle] = nil
        characteristicUUIDsByConnection[handle] = nil
        pendingReadHandleByConnection[handle] = nil
        pendingReadByTypeUUIDByConnection[handle] = nil
        reassembly[reassemblyKey(handle: handle, direction: 0)] = nil
        reassembly[reassemblyKey(handle: handle, direction: 1)] = nil
    }

    private static func textualAddress(_ value: Data) -> [UInt8]? {
        guard let text = String(data: value, encoding: .utf8) else { return nil }
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard compact.count == 12, compact.allSatisfy(\.isHexDigit) else { return nil }
        var bytes: [UInt8] = []
        var index = compact.startIndex
        for _ in 0..<6 {
            let next = compact.index(index, offsetBy: 2)
            guard let parsed = UInt8(compact[index..<next], radix: 16) else { return nil }
            bytes.append(parsed)
            index = next
        }
        return bytes
    }

    private static func isDeviceInformationUUID(_ uuid: String?) -> Bool {
        guard let uuid else { return false }
        let short = uuid.suffix(4).uppercased()
        let dis: Set<String> = ["180A", "2A23", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29"]
        return dis.contains(uuid.uppercased()) || dis.contains(short)
    }

    private static func isSerialUUID(_ uuid: String) -> Bool {
        uuid.uppercased() == "2A25" || uuid.suffix(4).uppercased() == "2A25"
    }

    private static func looksLikeMACString(_ value: Data) -> Bool {
        guard let text = String(data: value, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 17, trimmed.split(separator: ":").count == 6 { return true }
        if trimmed.count == 12, trimmed.allSatisfy({ $0.isHexDigit }) { return true }
        return false
    }

    private static func payloadLooksLikeAddress(_ payload: Data, peer: [UInt8]?) -> Bool {
        guard let peer, !peer.isEmpty else { return false }
        let bytes = Array(payload)
        if payload.count == 6 {
            return bytes == peer || bytes == Array(peer.reversed())
        }
        if payload.count > 6 {
            return containsSequence(bytes, peer) || containsSequence(bytes, Array(peer.reversed()))
        }
        return false
    }

    private static func containsSequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count > 0, haystack.count >= needle.count else { return false }
        let limit = haystack.count - needle.count
        if limit < 0 { return false }
        for i in 0...limit {
            if Array(haystack[i..<(i + needle.count)]) == needle { return true }
        }
        return false
    }

    private static func resolveAddressSource(
        sixInAdv: Bool,
        sixInScan: Bool,
        sixInDIS: Bool,
        sixInOther: Bool
    ) -> SixByteAddressSource {
        if sixInAdv || sixInScan { return .advertisement }
        if sixInDIS { return .deviceInformation }
        if sixInOther { return .otherReadable }
        return .notFound
    }

    private static func redactName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "redacted-name(len:\(trimmed.count))"
    }

    private static func attOpcodeName(_ opcode: UInt8) -> String {
        switch opcode {
        case 0x01: return "errorResponse"
        case 0x02: return "exchangeMTURequest"
        case 0x03: return "exchangeMTUResponse"
        case 0x04: return "findInformationRequest"
        case 0x05: return "findInformationResponse"
        case 0x08: return "readByTypeRequest"
        case 0x09: return "readByTypeResponse"
        case 0x0A: return "readRequest"
        case 0x0B: return "readResponse"
        case 0x0C: return "readBlobRequest"
        case 0x0D: return "readBlobResponse"
        case 0x10: return "readByGroupTypeRequest"
        case 0x11: return "readByGroupTypeResponse"
        case 0x12: return "writeRequest"
        case 0x13: return "writeResponse"
        case 0x16: return "prepareWriteRequest"
        case 0x17: return "prepareWriteResponse"
        case 0x18: return "executeWriteRequest"
        case 0x19: return "executeWriteResponse"
        case 0x1B: return "handleValueNotification"
        case 0x1D: return "handleValueIndication"
        case 0x52: return "writeCommand"
        default: return String(format: "opcode0x%02X", opcode)
        }
    }

    private static func hexUUID16(_ data: Data, _ offset: Int) -> String? {
        guard let value = readUInt16LE(data, offset) else { return nil }
        return String(format: "%04X", value)
    }

    private static func uuidFromTail(_ data: Data, start: Int) -> String? {
        let remaining = data.count - start
        if remaining == 2 {
            return hexUUID16(data, start)
        }
        if remaining == 16 {
            return formatUUID128(data, start)
        }
        return nil
    }

    private static func formatUUID128(_ data: Data, _ offset: Int) -> String? {
        // Bluetooth UUID128 is little-endian in ATT.
        guard let raw = slice(data, offset, 16) else { return nil }
        let bytes = Array(raw.reversed())
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        let s = hex
        let i0 = s.index(s.startIndex, offsetBy: 8)
        let i1 = s.index(i0, offsetBy: 4)
        let i2 = s.index(i1, offsetBy: 4)
        let i3 = s.index(i2, offsetBy: 4)
        return "\(s[..<i0])-\(s[i0..<i1])-\(s[i1..<i2])-\(s[i2..<i3])-\(s[i3...])"
    }
}

private func byte(_ data: Data, _ offset: Int) -> UInt8? {
    guard offset >= 0, offset < data.count else { return nil }
    return data[data.startIndex + offset]
}

private func slice(_ data: Data, _ offset: Int, _ count: Int) -> Data? {
    guard offset >= 0, count >= 0, offset + count <= data.count else { return nil }
    let start = data.startIndex + offset
    return data.subdata(in: start..<(start + count))
}

private func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16? {
    guard let lo = byte(data, offset), let hi = byte(data, offset + 1) else { return nil }
    return UInt16(lo) | (UInt16(hi) << 8)
}

private func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
    let b0 = byte(data, offset) ?? 0
    let b1 = byte(data, offset + 1) ?? 0
    let b2 = byte(data, offset + 2) ?? 0
    let b3 = byte(data, offset + 3) ?? 0
    return (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
}

private func readUInt64BE(_ data: Data, _ offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for i in 0..<8 {
        value = (value << 8) | UInt64(byte(data, offset + i) ?? 0)
    }
    return value
}
