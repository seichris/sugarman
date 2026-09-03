// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

struct PrivateBTSnoopCapture: Sendable {
    struct ATTPayload: Sendable {
        enum Kind: Sendable {
            case write
            case notification
        }

        let ordinal: Int
        let kind: Kind
        let handle: UInt16
        let value: Data
    }

    struct Session: Sendable {
        let peerAddress: Data
        var characteristicUUIDs: [UInt16: String] = [:]
        var pendingReadHandle: UInt16?
        var pendingReadTypeUUID: String?
        var deviceInformationValues: [Data] = []
        var attPayloads: [ATTPayload] = []
    }

    let completeNamesByPeer: [Data: Set<String>]
    let sessions: [Session]

    static func parse(_ data: Data) throws -> Self {
        guard data.count >= 16 else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        guard data.prefix(8) == Data("btsnoop\0".utf8) else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        guard readUInt32BE(data, 8) == 1,
              readUInt32BE(data, 12) == 1002 else {
            throw GS3PrivateHandoverError.unsupportedCapture
        }

        var offset = 16
        var ordinal = 0
        var names: [Data: Set<String>] = [:]
        var sessions: [Session] = []
        var activeSessionByHandle: [UInt16: Int] = [:]
        var reassembly: [UInt32: Data] = [:]

        while offset < data.count {
            guard offset + 24 <= data.count else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            let originalLength = Int(readUInt32BE(data, offset))
            let includedLength = Int(readUInt32BE(data, offset + 4))
            let flags = readUInt32BE(data, offset + 8)
            offset += 24
            guard originalLength == includedLength,
                  includedLength > 0,
                  offset + includedLength <= data.count else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            let packet = data.subdata(in: offset..<(offset + includedLength))
            offset += includedLength
            ordinal += 1

            guard let kind = byte(packet, 0) else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            let body = packet.dropFirstData()
            switch kind {
            case 0x04:
                try parseEvent(
                    body,
                    ordinal: ordinal,
                    names: &names,
                    sessions: &sessions,
                    activeSessionByHandle: &activeSessionByHandle,
                    reassembly: &reassembly
                )
            case 0x02:
                try parseACL(
                    body,
                    direction: UInt8(flags & 1),
                    ordinal: ordinal,
                    sessions: &sessions,
                    activeSessionByHandle: activeSessionByHandle,
                    reassembly: &reassembly
                )
            case 0x01, 0x03, 0x05:
                break
            default:
                // Some Android captures omit the H4 event discriminator.
                if kind == 0x3E || kind == 0x05 {
                    try parseEvent(
                        packet,
                        ordinal: ordinal,
                        names: &names,
                        sessions: &sessions,
                        activeSessionByHandle: &activeSessionByHandle,
                        reassembly: &reassembly
                    )
                }
            }
        }
        guard reassembly.values.allSatisfy(\.isEmpty) else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        return Self(completeNamesByPeer: names, sessions: sessions)
    }

    private static func parseEvent(
        _ body: Data,
        ordinal: Int,
        names: inout [Data: Set<String>],
        sessions: inout [Session],
        activeSessionByHandle: inout [UInt16: Int],
        reassembly: inout [UInt32: Data]
    ) throws {
        _ = ordinal
        guard body.count >= 2,
              let eventCode = byte(body, 0),
              let parameterLength = byte(body, 1),
              body.count >= 2 + Int(parameterLength) else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        let parameters = body.subdata(in: 2..<(2 + Int(parameterLength)))
        if eventCode == 0x05 {
            guard parameters.count >= 4,
                  let rawHandle = readUInt16LE(parameters, 1) else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            let handle = rawHandle & 0x0FFF
            activeSessionByHandle[handle] = nil
            reassembly[reassemblyKey(handle: handle, direction: 0)] = nil
            reassembly[reassemblyKey(handle: handle, direction: 1)] = nil
            return
        }
        guard eventCode == 0x3E,
              let subevent = byte(parameters, 0) else {
            return
        }
        let rest = parameters.dropFirstData()
        switch subevent {
        case 0x01, 0x0A:
            guard rest.count >= 11 else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            guard byte(rest, 0) == 0,
                  let rawHandle = readUInt16LE(rest, 1),
                  let peer = slice(rest, 5, 6) else {
                return
            }
            let handle = rawHandle & 0x0FFF
            activeSessionByHandle[handle] = nil
            reassembly[reassemblyKey(handle: handle, direction: 0)] = nil
            reassembly[reassemblyKey(handle: handle, direction: 1)] = nil
            sessions.append(Session(peerAddress: peer))
            activeSessionByHandle[handle] = sessions.count - 1
        case 0x02:
            try parseLegacyAdvertisements(rest, names: &names)
        case 0x0D:
            try parseExtendedAdvertisements(rest, names: &names)
        default:
            break
        }
    }

    private static func parseLegacyAdvertisements(
        _ data: Data,
        names: inout [Data: Set<String>]
    ) throws {
        guard let reportCount = byte(data, 0) else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        var offset = 1
        for _ in 0..<Int(reportCount) {
            guard offset + 9 <= data.count,
                  let peer = slice(data, offset + 2, 6),
                  let payloadLength = byte(data, offset + 8) else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            offset += 9
            guard let payload = slice(data, offset, Int(payloadLength)) else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            offset += Int(payloadLength)
            guard offset < data.count else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            offset += 1 // RSSI
            inspectAdvertisingData(payload, peer: peer, names: &names)
        }
    }

    private static func parseExtendedAdvertisements(
        _ data: Data,
        names: inout [Data: Set<String>]
    ) throws {
        guard let reportCount = byte(data, 0) else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        var offset = 1
        for _ in 0..<Int(reportCount) {
            guard offset + 24 <= data.count,
                  let peer = slice(data, offset + 3, 6),
                  let payloadLength = byte(data, offset + 23) else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            offset += 24
            guard let payload = slice(data, offset, Int(payloadLength)) else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            offset += Int(payloadLength)
            inspectAdvertisingData(payload, peer: peer, names: &names)
        }
    }

    private static func inspectAdvertisingData(
        _ data: Data,
        peer: Data,
        names: inout [Data: Set<String>]
    ) {
        var offset = 0
        while offset < data.count {
            guard let length = byte(data, offset) else { return }
            if length == 0 { return }
            guard Int(length) >= 1,
                  offset + 1 + Int(length) <= data.count,
                  let type = byte(data, offset + 1),
                  let payload = slice(data, offset + 2, Int(length) - 1) else {
                return
            }
            offset += 1 + Int(length)
            guard type == 0x09 else { continue }
            if let name = String(data: payload, encoding: .utf8) {
                names[peer, default: []].insert(name)
            }
        }
    }

    private static func parseACL(
        _ body: Data,
        direction: UInt8,
        ordinal: Int,
        sessions: inout [Session],
        activeSessionByHandle: [UInt16: Int],
        reassembly: inout [UInt32: Data]
    ) throws {
        guard body.count >= 4,
              let handleFlags = readUInt16LE(body, 0),
              let aclLength = readUInt16LE(body, 2),
              let chunk = slice(body, 4, Int(aclLength)) else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        let handle = handleFlags & 0x0FFF
        let boundary = (handleFlags >> 12) & 0x3
        let key = reassemblyKey(handle: handle, direction: direction)
        if boundary == 0x01 {
            guard reassembly[key] != nil else {
                throw GS3PrivateHandoverError.invalidCapture
            }
            reassembly[key]?.append(chunk)
        } else {
            reassembly[key] = chunk
        }
        guard let assembled = reassembly[key], assembled.count >= 4,
              let payloadLength = readUInt16LE(assembled, 0),
              let channel = readUInt16LE(assembled, 2) else {
            return
        }
        let total = 4 + Int(payloadLength)
        guard assembled.count <= total else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        guard assembled.count == total else { return }
        reassembly[key] = nil
        guard channel == 0x0004,
              let sessionIndex = activeSessionByHandle[handle] else {
            return
        }
        let att = assembled.subdata(in: 4..<total)
        try parseATT(att, ordinal: ordinal, session: &sessions[sessionIndex])
    }

    private static func parseATT(
        _ data: Data,
        ordinal: Int,
        session: inout Session
    ) throws {
        guard let opcode = byte(data, 0) else {
            throw GS3PrivateHandoverError.invalidCapture
        }
        switch opcode {
        case 0x01:
            session.pendingReadHandle = nil
            session.pendingReadTypeUUID = nil
        case 0x05:
            guard data.count >= 2, let format = byte(data, 1) else { return }
            let uuidLength = format == 0x01 ? 2 : format == 0x02 ? 16 : 0
            guard uuidLength > 0 else { return }
            var offset = 2
            while offset + 2 + uuidLength <= data.count {
                if let handle = readUInt16LE(data, offset),
                   let uuid = formatUUID(data, offset: offset + 2, count: uuidLength) {
                    session.characteristicUUIDs[handle] = uuid
                }
                offset += 2 + uuidLength
            }
        case 0x08:
            session.pendingReadTypeUUID = uuidFromTail(data, start: 5)
        case 0x09:
            let requested = session.pendingReadTypeUUID
            session.pendingReadTypeUUID = nil
            guard data.count >= 2, let pairLength = byte(data, 1) else { return }
            var offset = 2
            while Int(pairLength) >= 2, offset + Int(pairLength) <= data.count {
                guard let value = slice(data, offset + 2, Int(pairLength) - 2) else {
                    throw GS3PrivateHandoverError.invalidCapture
                }
                if requested?.uppercased() == "2803", value.count >= 5,
                   let valueHandle = readUInt16LE(value, 1),
                   let uuid = formatUUID(value, offset: 3, count: value.count - 3) {
                    session.characteristicUUIDs[valueHandle] = uuid
                } else if isDeviceInformationUUID(requested) {
                    session.deviceInformationValues.append(value)
                }
                offset += Int(pairLength)
            }
        case 0x0A, 0x0C:
            session.pendingReadHandle = readUInt16LE(data, 1)
        case 0x0B, 0x0D:
            if let handle = session.pendingReadHandle {
                session.pendingReadHandle = nil
                let uuid = session.characteristicUUIDs[handle]
                if isDeviceInformationUUID(uuid) {
                    session.deviceInformationValues.append(data.dropFirstData())
                }
            }
        case 0x12, 0x52:
            if let handle = readUInt16LE(data, 1),
               let value = slice(data, 3, data.count - 3) {
                session.attPayloads.append(
                    ATTPayload(ordinal: ordinal, kind: .write, handle: handle, value: value)
                )
            }
        case 0x1B, 0x1D:
            if let handle = readUInt16LE(data, 1),
               let value = slice(data, 3, data.count - 3) {
                session.attPayloads.append(
                    ATTPayload(
                        ordinal: ordinal,
                        kind: .notification,
                        handle: handle,
                        value: value
                    )
                )
            }
        default:
            break
        }
    }

    private static func isDeviceInformationUUID(_ uuid: String?) -> Bool {
        guard let uuid else { return false }
        let upper = uuid.uppercased()
        let short = String(upper.suffix(4))
        return ["2A23", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29"]
            .contains(upper) || ["2A23", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29"]
            .contains(short)
    }

    private static func uuidFromTail(_ data: Data, start: Int) -> String? {
        formatUUID(data, offset: start, count: data.count - start)
    }

    private static func formatUUID(_ data: Data, offset: Int, count: Int) -> String? {
        if count == 2, let value = readUInt16LE(data, offset) {
            return String(format: "%04X", value)
        }
        guard count == 16, let raw = slice(data, offset, 16) else { return nil }
        let hex = raw.reversed().map { String(format: "%02X", $0) }.joined()
        let cuts = [8, 12, 16, 20]
        var result = ""
        var start = hex.startIndex
        for cut in cuts {
            let end = hex.index(hex.startIndex, offsetBy: cut)
            if !result.isEmpty { result.append("-") }
            result.append(contentsOf: hex[start..<end])
            start = end
        }
        result.append("-")
        result.append(contentsOf: hex[start...])
        return result
    }

    private static func reassemblyKey(handle: UInt16, direction: UInt8) -> UInt32 {
        (UInt32(direction & 1) << 16) | UInt32(handle)
    }
}
private extension Data {
    func dropFirstData() -> Data {
        isEmpty ? Data() : subdata(in: (startIndex + 1)..<endIndex)
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
    guard let low = byte(data, offset), let high = byte(data, offset + 1) else {
        return nil
    }
    return UInt16(low) | (UInt16(high) << 8)
}

private func readUInt32BE(_ data: Data, _ offset: Int) -> UInt32 {
    var value: UInt32 = 0
    for index in 0..<4 {
        value = (value << 8) | UInt32(byte(data, offset + index) ?? 0)
    }
    return value
}
