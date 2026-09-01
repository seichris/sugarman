// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sugarman contributors

import Foundation

/// Builds tiny synthetic BTSnoop blobs for tests. Not a real sensor capture.
enum SyntheticBTSnoop {
    static let peer: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]
    static let writePayload: [UInt8] = [0xC0, 0xFF, 0xEE, 0x11, 0x22, 0x33]
    static let localName = "SyntheticLab"

    static func labCapture(
        includePeerInManufacturerData: Bool,
        includeSixByteSerial: Bool,
        serialPayload: [UInt8]? = nil
    ) -> Data {
        var packets: [Data] = []
        packets.append(h4Event(legacyAdvertisement(includePeerInManufacturerData: includePeerInManufacturerData)))
        packets.append(h4Event(connectionComplete()))
        packets.append(h4ACL(att: Data([0x11, 0x06, 0x01, 0x00, 0x10, 0x00, 0x0A, 0x18])))
        packets.append(h4ACL(att: Data([0x08, 0x01, 0x00, 0xFF, 0xFF, 0x03, 0x28])))
        // Characteristic declarations: value handle 3 = manufacturer (2A29),
        // value handle 5 = serial number (2A25), value handle 49 = FF31,
        // and value handle 50 = FF32.
        packets.append(h4ACL(att: Data([
            0x09, 0x07,
            0x02, 0x00, 0x02, 0x03, 0x00, 0x29, 0x2A,
            0x04, 0x00, 0x02, 0x05, 0x00, 0x25, 0x2A,
            0x06, 0x00, 0x10, 0x31, 0x00, 0x31, 0xFF,
            0x07, 0x00, 0x0C, 0x32, 0x00, 0x32, 0xFF,
        ])))
        packets.append(h4ACL(att: Data([0x0A, 0x03, 0x00])))
        packets.append(h4ACL(att: Data([0x0B]) + Data("Acme".utf8)))
        packets.append(h4ACL(att: Data([0x0A, 0x05, 0x00])))
        if includeSixByteSerial {
            packets.append(h4ACL(att: Data([0x0B]) + Data(serialPayload ?? peer)))
        } else {
            packets.append(h4ACL(att: Data([0x0B]) + Data("SN".utf8)))
        }
        packets.append(h4ACL(att: Data([0x1B, 0x31, 0x00, 0xBA, 0xAD, 0xF0, 0x0D])))
        packets.append(h4ACL(att: Data([0x12, 0x32, 0x00]) + Data(writePayload)))
        return btsnoop(packets: packets)
    }

    static func reusedHandleWithoutRediscovery() -> Data {
        let secondPeer: [UInt8] = [0x10, 0x32, 0x54, 0x76, 0x98, 0xBA]
        var packets: [Data] = []
        packets.append(h4Event(connectionComplete()))
        packets.append(h4ACL(att: Data([0x08, 0x01, 0x00, 0xFF, 0xFF, 0x03, 0x28])))
        packets.append(h4ACL(att: Data([
            0x09, 0x07,
            0x04, 0x00, 0x02, 0x05, 0x00, 0x25, 0x2A,
        ])))
        packets.append(h4ACL(att: Data([0x0A, 0x05, 0x00])))
        packets.append(h4ACL(att: Data([0x0B]) + Data("not-an-address".utf8)))
        packets.append(h4Event(disconnectionComplete()))
        packets.append(h4Event(connectionComplete(peer: secondPeer)))
        packets.append(h4ACL(att: Data([0x0A, 0x05, 0x00])))
        packets.append(h4ACL(att: Data([0x0B]) + Data(secondPeer)))
        return btsnoop(packets: packets)
    }

    private static func btsnoop(packets: [Data]) -> Data {
        var out = Data("btsnoop\0".utf8)
        out.append(contentsOf: be32(1))
        out.append(contentsOf: be32(1002))
        var timestamp: UInt64 = 1
        for packet in packets {
            out.append(contentsOf: be32(UInt32(packet.count)))
            out.append(contentsOf: be32(UInt32(packet.count)))
            out.append(contentsOf: be32(0))
            out.append(contentsOf: be32(0))
            out.append(contentsOf: be64(timestamp))
            out.append(packet)
            timestamp += 1000
        }
        return out
    }

    private static func h4Event(_ event: Data) -> Data {
        Data([0x04]) + event
    }

    private static func legacyAdvertisement(includePeerInManufacturerData: Bool) -> Data {
        var ad = Data()
        ad.append(contentsOf: [2, 0x01, 0x06])
        let name = Data(localName.utf8)
        ad.append(contentsOf: [UInt8(1 + name.count), 0x09])
        ad.append(name)
        ad.append(contentsOf: [3, 0x03, 0x0A, 0x18])
        ad.append(contentsOf: [5, 0xFF, 0x00, 0x00, 0xDE, 0xAD])
        if includePeerInManufacturerData {
            ad.append(contentsOf: [UInt8(1 + 2 + peer.count), 0xFF, 0xFF, 0xFF])
            ad.append(contentsOf: peer)
        }
        var params = Data([0x02, 0x01, 0x00, 0x00]) // subevent, num, eventType, addrType
        params.append(contentsOf: peer)
        params.append(UInt8(ad.count))
        params.append(ad)
        params.append(0xC8) // RSSI
        var event = Data([0x3E, UInt8(params.count)])
        event.append(params)
        return event
    }

    private static func connectionComplete(peer: [UInt8] = peer) -> Data {
        var params = Data([0x01, 0x00, 0x40, 0x00, 0x00, 0x00])
        params.append(contentsOf: peer)
        params.append(contentsOf: [0x06, 0x00, 0x00, 0x00, 0x48, 0x00, 0x01])
        var event = Data([0x3E, UInt8(params.count)])
        event.append(params)
        return event
    }

    private static func disconnectionComplete() -> Data {
        Data([0x05, 0x04, 0x00, 0x40, 0x00, 0x13])
    }

    private static func h4ACL(att: Data) -> Data {
        var l2cap = Data()
        l2cap.append(contentsOf: le16(UInt16(att.count)))
        l2cap.append(contentsOf: le16(0x0004))
        l2cap.append(att)
        let handleFlags: UInt16 = 0x0040 | (0x2 << 12)
        var acl = Data()
        acl.append(contentsOf: le16(handleFlags))
        acl.append(contentsOf: le16(UInt16(l2cap.count)))
        acl.append(l2cap)
        return Data([0x02]) + acl
    }

    private static func be32(_ value: UInt32) -> [UInt8] {
        [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
    }

    private static func be64(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((value >> (56 - $0 * 8)) & 0xFF) }
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }
}
