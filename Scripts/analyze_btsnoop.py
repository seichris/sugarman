#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors
"""Redacting Android BTSnoop / HCI snoop analyzer for Sugarman P1.

Summaries only: counts, lengths, UUID allowlists. Never prints a full MAC,
full serial, or auth-looking payload. Never decodes glucose or claims RC4/AES.

Usage:
  python3 Scripts/analyze_btsnoop.py path/to/btsnoop_hci.log
  python3 Scripts/analyze_btsnoop.py --json path/to/btsnoop_hci.log
  python3 Scripts/analyze_btsnoop.py --self-test
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

CIPHER_HYPOTHESIS = "unknownUntilCapture"

ATT_NAMES = {
    0x01: "errorResponse",
    0x02: "exchangeMTURequest",
    0x03: "exchangeMTUResponse",
    0x04: "findInformationRequest",
    0x05: "findInformationResponse",
    0x08: "readByTypeRequest",
    0x09: "readByTypeResponse",
    0x0A: "readRequest",
    0x0B: "readResponse",
    0x0C: "readBlobRequest",
    0x0D: "readBlobResponse",
    0x10: "readByGroupTypeRequest",
    0x11: "readByGroupTypeResponse",
    0x12: "writeRequest",
    0x13: "writeResponse",
    0x16: "prepareWriteRequest",
    0x17: "prepareWriteResponse",
    0x18: "executeWriteRequest",
    0x19: "executeWriteResponse",
    0x1B: "handleValueNotification",
    0x1D: "handleValueIndication",
    0x52: "writeCommand",
}

DIS_SHORT = {"180A", "2A23", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29"}


def u16le(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


def uuid128(data: bytes, offset: int) -> str:
    raw = bytes(reversed(data[offset : offset + 16])).hex().upper()
    return f"{raw[0:8]}-{raw[8:12]}-{raw[12:16]}-{raw[16:20]}-{raw[20:32]}"


def looks_like_mac_string(value: bytes) -> bool:
    try:
        text = value.decode("utf-8").strip()
    except UnicodeDecodeError:
        return False
    if len(text) == 17 and text.count(":") == 5:
        return True
    if len(text) == 12 and all(c in "0123456789abcdefABCDEF" for c in text):
        return True
    return False


def contains_seq(haystack: bytes, needle: bytes) -> bool:
    return needle and needle in haystack


def payload_looks_like_address(payload: bytes, peer: bytes | None) -> bool:
    if not peer:
        return False
    rev = peer[::-1]
    if len(payload) == 6:
        return payload == peer or payload == rev
    if len(payload) > 6:
        return contains_seq(payload, peer) or contains_seq(payload, rev)
    return False


def redact_name(name: str) -> str:
    trimmed = name.strip()
    if not trimmed:
        return "redacted-name(len: 0)"
    if looks_like_mac_string(trimmed.encode("utf-8")):
        return f"redacted-name(len: {len(trimmed)})"
    hexish = "".join(c for c in trimmed if c in "0123456789abcdefABCDEF:")
    if len(hexish) >= 12 and len(hexish) >= len(trimmed) - 1:
        return f"redacted-name(len: {len(trimmed)})"
    if len(trimmed) > 24:
        return f"redacted-name(len: {len(trimmed)})"
    return trimmed


def inspect_ad(ad: bytes, peer: bytes | None, state: dict, is_scan: bool) -> None:
    offset = 0
    while offset < len(ad):
        length = ad[offset]
        if length == 0:
            break
        if offset + 1 + length > len(ad):
            break
        typ = ad[offset + 1]
        payload = ad[offset + 2 : offset + 1 + length]
        offset += 1 + length
        if typ in (0x08, 0x09):
            try:
                state["names"].add(redact_name(payload.decode("utf-8")))
            except UnicodeDecodeError:
                pass
        elif typ in (0x02, 0x03, 0x14, 0x1F):
            i = 0
            while i + 2 <= len(payload):
                state["service_uuids"].add(f"{u16le(payload, i):04X}")
                i += 2
        elif typ in (0x06, 0x07):
            i = 0
            while i + 16 <= len(payload):
                state["service_uuids"].add(uuid128(payload, i))
                i += 16
        elif typ == 0xFF:
            state["mfg_lengths"].append(len(payload))
        flag = payload_looks_like_address(payload, peer) or (
            len(payload) == 6 and payload_looks_like_address(payload, peer)
        )
        if flag:
            if is_scan:
                state["six_scan"] = True
            else:
                state["six_adv"] = True


def parse_legacy_adv(params: bytes, state: dict) -> None:
    if not params:
        return
    num = params[0]
    offset = 1
    for _ in range(num):
        if offset + 8 > len(params):
            return
        event_type = params[offset]
        offset += 1
        offset += 1
        addr = params[offset : offset + 6]
        offset += 6
        state["hci_peer"] = True
        if state["peer"] is None:
            state["peer"] = addr
        if offset >= len(params):
            return
        data_len = params[offset]
        offset += 1
        if offset + data_len > len(params):
            return
        ad = params[offset : offset + data_len]
        offset += data_len
        if offset < len(params):
            offset += 1
        is_scan = event_type == 0x04
        if is_scan:
            state["scan_rsp"] += 1
        else:
            state["adv"] += 1
        inspect_ad(ad, addr, state, is_scan)


def parse_event(body: bytes, state: dict) -> None:
    if len(body) < 2:
        return
    event_code = body[0]
    param_len = body[1]
    if len(body) < 2 + param_len:
        return
    params = body[2 : 2 + param_len]
    if event_code != 0x3E or not params:
        return
    sub = params[0]
    rest = params[1:]
    if sub in (0x01, 0x0A):
        state["connections"] += 1
        if len(rest) >= 11:
            state["hci_peer"] = True
            if state["peer"] is None:
                state["peer"] = rest[5:11]
    elif sub == 0x02:
        parse_legacy_adv(rest, state)
    elif sub == 0x0D and rest:
        num = rest[0]
        offset = 1
        for _ in range(num):
            if offset + 24 > len(rest):
                return
            event_type = u16le(rest, offset)
            offset += 2
            offset += 1
            addr = rest[offset : offset + 6]
            offset += 6
            state["hci_peer"] = True
            if state["peer"] is None:
                state["peer"] = addr
            offset += 1 + 1 + 1 + 1 + 1 + 2 + 1 + 6
            data_len = rest[offset]
            offset += 1
            if offset + data_len > len(rest):
                return
            ad = rest[offset : offset + data_len]
            offset += data_len
            is_scan = (event_type & 0x0008) != 0
            if is_scan:
                state["scan_rsp"] += 1
            else:
                state["adv"] += 1
            inspect_ad(ad, addr, state, is_scan)


def att_name(opcode: int) -> str:
    return ATT_NAMES.get(opcode, f"opcode0x{opcode:02X}")


def is_dis(uuid: str | None) -> bool:
    if not uuid:
        return False
    short = uuid[-4:].upper()
    return uuid.upper() in DIS_SHORT or short in DIS_SHORT


def parse_att(att: bytes, state: dict) -> None:
    if not att:
        return
    state["att"] += 1
    opcode = att[0]
    handle = None
    uuid = None
    value_len = None
    if opcode == 0x01 and len(att) >= 5:
        handle = u16le(att, 1)
    elif opcode in (0x04, 0x06, 0x08, 0x10) and len(att) >= 5:
        handle = u16le(att, 1)
        rem = att[5:]
        if len(rem) == 2:
            uuid = f"{u16le(rem, 0):04X}"
        elif len(rem) == 16:
            uuid = uuid128(rem, 0)
    elif opcode in (0x09, 0x11) and len(att) >= 2:
        pair_len = att[1]
        i = 2
        while pair_len >= 2 and i + pair_len <= len(att):
            handle = u16le(att, i)
            value = att[i + 2 : i + pair_len]
            value_len = len(value)
            if opcode == 0x11 and len(value) == 4:
                uuid = f"{u16le(value, 2):04X}"
            elif opcode == 0x11 and len(value) == 18:
                uuid = uuid128(value, 2)
            elif len(value) == 2:
                uuid = f"{u16le(value, 0):04X}"
            elif len(value) == 16:
                uuid = uuid128(value, 0)
            elif opcode == 0x09 and len(value) >= 5:
                char_uuid = value[3:]
                if len(char_uuid) == 2:
                    uuid = f"{u16le(char_uuid, 0):04X}"
                elif len(char_uuid) == 16:
                    uuid = uuid128(char_uuid, 0)
            if uuid:
                state["service_uuids"].add(uuid)
            i += pair_len
    elif opcode in (0x0A, 0x0C) and len(att) >= 3:
        handle = u16le(att, 1)
    elif opcode in (0x0B, 0x0D):
        value = att[1:]
        value_len = len(value)
        last_uuid = None
        for op in reversed(state["att_ops"]):
            if op.get("uuid"):
                last_uuid = op["uuid"]
                break
        matches = payload_looks_like_address(value, state["peer"])
        mac_str = looks_like_mac_string(value)
        if is_dis(last_uuid) and (len(value) == 6 or mac_str or matches):
            state["six_dis"] = True
        elif matches or mac_str:
            state["six_other"] = True
    elif opcode in (0x12, 0x16, 0x52):
        if len(att) >= 3:
            handle = u16le(att, 1)
            value_len = len(att) - 3
        state["notes"].append("Write/prepare ATT PDU omitted (possible auth); length only.")
    elif opcode in (0x1B, 0x1D) and len(att) >= 3:
        handle = u16le(att, 1)
        value_len = len(att) - 3
    else:
        if len(att) >= 3:
            handle = u16le(att, 1)
        value_len = max(0, len(att) - 1)
    if uuid:
        state["service_uuids"].add(uuid)
    state["att_ops"].append(
        {
            "opcodeName": att_name(opcode),
            "opcode": opcode,
            "handle": handle,
            "uuid": uuid,
            "valueByteCount": value_len,
        }
    )


def parse_acl(body: bytes, state: dict) -> None:
    if len(body) < 4:
        return
    handle_flags = u16le(body, 0)
    handle = handle_flags & 0x0FFF
    pb = (handle_flags >> 12) & 0x3
    data_len = u16le(body, 2)
    if len(body) < 4 + data_len:
        return
    chunk = body[4 : 4 + data_len]
    buf = state["acl"].get(handle, b"")
    if pb == 0x01:
        buf = buf + chunk
    else:
        buf = chunk
    state["acl"][handle] = buf
    if len(buf) < 4:
        return
    l2cap_len = u16le(buf, 0)
    cid = u16le(buf, 2)
    if len(buf) < 4 + l2cap_len:
        return
    state["acl"].pop(handle, None)
    if cid != 0x0004:
        return
    parse_att(buf[4 : 4 + l2cap_len], state)


def split_h4(packet: bytes) -> tuple[str, bytes] | None:
    if not packet:
        return None
    kind = {0x01: "command", 0x02: "acl", 0x03: "sco", 0x04: "event", 0x05: "iso"}.get(packet[0])
    if kind:
        return kind, packet[1:]
    if packet[0] in (0x3E, 0x0E, 0x13):
        return "event", packet
    return None


def summarize(data: bytes) -> dict:
    if len(data) < 16 or data[:8] != b"btsnoop\0":
        raise ValueError("invalid BTSnoop magic")
    _version, _datalink = struct.unpack(">II", data[8:16])
    offset = 16
    state = {
        "records": 0,
        "adv": 0,
        "scan_rsp": 0,
        "connections": 0,
        "att": 0,
        "names": set(),
        "service_uuids": set(),
        "mfg_lengths": [],
        "att_ops": [],
        "hci_peer": False,
        "six_adv": False,
        "six_scan": False,
        "six_dis": False,
        "six_other": False,
        "peer": None,
        "acl": {},
        "notes": [
            "Payloads, full MACs, and serials omitted.",
            "Does not identify a cipher. CipherHypothesis remains unknownUntilCapture.",
        ],
    }
    while offset + 24 <= len(data):
        original, included, _flags, _drops = struct.unpack(">IIII", data[offset : offset + 16])
        offset += 24
        if included < 0 or offset + included > len(data):
            raise ValueError("truncated BTSnoop record")
        packet = data[offset : offset + included]
        offset += included
        state["records"] += 1
        _ = original
        split = split_h4(packet)
        if not split:
            continue
        kind, body = split
        if kind == "event":
            parse_event(body, state)
        elif kind == "acl":
            parse_acl(body, state)
    if state["six_adv"] or state["six_scan"]:
        source = "advertisement"
    elif state["six_dis"]:
        source = "deviceInformation"
    elif state["six_other"]:
        source = "otherReadable"
    else:
        source = "notFound"
    if state["hci_peer"] and source == "notFound":
        state["notes"].append(
            "HCI peer-address field was present but is not an iOS-accessible source."
        )
    return {
        "schemaVersion": 1,
        "recordCount": state["records"],
        "leAdvertisementCount": state["adv"],
        "scanResponseCount": state["scan_rsp"],
        "connectionEventCount": state["connections"],
        "attPduCount": state["att"],
        "advertisedNames": sorted(state["names"]),
        "advertisedServiceUUIDs": sorted(state["service_uuids"]),
        "manufacturerDataLengths": state["mfg_lengths"],
        "attOperations": state["att_ops"],
        "hciPeerAddressFieldObserved": state["hci_peer"],
        "sixByteFieldInAdvertisementPayload": state["six_adv"],
        "sixByteFieldInScanResponsePayload": state["six_scan"],
        "sixByteFieldInDeviceInformationRead": state["six_dis"],
        "sixByteFieldInOtherReadable": state["six_other"],
        "sixByteAddressSource": source,
        "cipherHypothesis": CIPHER_HYPOTHESIS,
        "refusedGlucoseDecode": True,
        "notes": state["notes"],
    }


def assert_redacted(summary: dict, forbidden: list[bytes]) -> None:
    blob = json.dumps(summary).encode("utf-8")
    text = blob.decode("utf-8")
    for item in forbidden:
        if item.lower() in blob.lower() or item.decode("latin1", errors="replace") in text:
            raise AssertionError("summary leaked forbidden bytes")
    if "RC4" in text or "AES" in text:
        raise AssertionError("summary claimed a cipher")
    if summary["cipherHypothesis"] != CIPHER_HYPOTHESIS:
        raise AssertionError("cipher hypothesis must stay unknownUntilCapture")


def build_synthetic() -> bytes:
    """Tiny synthetic capture. Not a real sensor dump."""
    peer = bytes([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB])
    name = b"SyntheticLab"
    # AD: flags, complete name, 16-bit UUID 180A, manufacturer 4 bytes,
    # plus company-id + peer (so six bytes appear in payload).
    ad = bytearray()
    ad += bytes([2, 0x01, 0x06])
    ad += bytes([1 + len(name), 0x09]) + name
    ad += bytes([3, 0x03, 0x0A, 0x18])
    ad += bytes([5, 0xFF, 0x00, 0x00, 0xDE, 0xAD])
    ad += bytes([1 + 2 + len(peer), 0xFF, 0xFF, 0xFF]) + peer
    params = bytes([0x02, 0x01, 0x00, 0x00]) + peer + bytes([len(ad)]) + bytes(ad) + bytes([0xC8])
    event = bytes([0x3E, len(params)]) + params
    h4_event = bytes([0x04]) + event

    conn_params = bytes(
        [0x01, 0x00, 0x40, 0x00, 0x00, 0x00]
    ) + peer + bytes([0x06, 0x00, 0x00, 0x00, 0x48, 0x00, 0x01])
    # subevent 0x01, then status,handle,role,peerType,addr,interval,latency,timeout,accuracy
    conn_body = bytes([0x01]) + bytes([0x00, 0x40, 0x00, 0x00, 0x00]) + peer + bytes(
        [0x06, 0x00, 0x00, 0x00, 0x48, 0x00, 0x01]
    )
    conn_event = bytes([0x3E, len(conn_body)]) + conn_body
    h4_conn = bytes([0x04]) + conn_event

    def acl_att(pdu: bytes) -> bytes:
        l2cap = struct.pack("<HH", len(pdu), 0x0004) + pdu
        handle_flags = 0x0040 | (0x2 << 12)
        hdr = struct.pack("<HH", handle_flags, len(l2cap))
        return bytes([0x02]) + hdr + l2cap

    read_group = bytes([0x11, 0x06, 0x01, 0x00, 0x10, 0x00, 0x0A, 0x18])
    read_req = bytes([0x0A, 0x03, 0x00])
    read_resp = bytes([0x0B]) + b"Acme"
    write_req = bytes([0x12, 0x32, 0x00]) + bytes([0xC0, 0xFF, 0xEE, 0x11, 0x22, 0x33])
    serial_req = bytes([0x0A, 0x25, 0x2A])
    serial_resp = bytes([0x0B]) + peer

    packets = [
        h4_event,
        h4_conn,
        acl_att(read_group),
        acl_att(read_req),
        acl_att(read_resp),
        acl_att(serial_req),
        acl_att(serial_resp),
        acl_att(write_req),
    ]
    out = bytearray(b"btsnoop\0")
    out += struct.pack(">II", 1, 1002)
    ts = 0
    for pkt in packets:
        out += struct.pack(">IIIIQ", len(pkt), len(pkt), 0, 0, ts)
        out += pkt
        ts += 1000
    return bytes(out)


def format_text(summary: dict) -> str:
    lines = [
        f"BTSnoopSummary schema={summary['schemaVersion']} records={summary['recordCount']}",
        f"LE adv={summary['leAdvertisementCount']} scanRsp={summary['scanResponseCount']} "
        f"connections={summary['connectionEventCount']} ATT={summary['attPduCount']}",
        "names=" + ",".join(summary["advertisedNames"]),
        "serviceUUIDs=" + ",".join(summary["advertisedServiceUUIDs"]),
        "manufacturerDataLengths=" + ",".join(str(x) for x in summary["manufacturerDataLengths"]),
        f"hciPeerAddressFieldObserved={summary['hciPeerAddressFieldObserved']} (Android-only; not an iOS source)",
        f"sixByteAddressSource={summary['sixByteAddressSource']}",
        f"cipherHypothesis={summary['cipherHypothesis']}",
        f"refusedGlucoseDecode={summary['refusedGlucoseDecode']}",
    ]
    for op in summary["attOperations"]:
        handle = f"0x{op['handle']:04X}" if op["handle"] is not None else "-"
        uuid = op["uuid"] or "-"
        count = op["valueByteCount"] if op["valueByteCount"] is not None else "-"
        lines.append(
            f"ATT {op['opcodeName']} handle={handle} uuid={uuid} valueByteCount={count}"
        )
    lines.extend(summary["notes"])
    return "\n".join(lines)


def self_test() -> int:
    data = build_synthetic()
    summary = summarize(data)
    forbidden = [
        bytes([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB]),
        b"01:23:45:67:89:AB",
        b"C0FFEE",
        b"\xc0\xff\xee",
    ]
    text = format_text(summary)
    blob = json.dumps(summary)
    for item in forbidden:
        if item in data and item in blob.encode("utf-8"):
            print("self-test failed: leaked capture bytes", file=sys.stderr)
            return 1
        if item.decode("latin1", errors="ignore") in text and item not in (b"C0FFEE",):
            # hex dump of MAC must not appear
            if "01:23:45:67:89:AB" in text:
                print("self-test failed: leaked MAC text", file=sys.stderr)
                return 1
    if "01:23:45:67:89:AB" in text or "0123456789AB" in text:
        print("self-test failed: leaked MAC", file=sys.stderr)
        return 1
    if "C0FFEE" in text.upper() or "\\xc0" in text:
        print("self-test failed: leaked write payload", file=sys.stderr)
        return 1
    if summary["cipherHypothesis"] != CIPHER_HYPOTHESIS:
        return 1
    if summary["advertisedNames"] != ["SyntheticLab"]:
        print("self-test failed: name", summary["advertisedNames"], file=sys.stderr)
        return 1
    if "180A" not in summary["advertisedServiceUUIDs"]:
        print("self-test failed: uuid", summary["advertisedServiceUUIDs"], file=sys.stderr)
        return 1
    if summary["leAdvertisementCount"] < 1 or summary["connectionEventCount"] < 1:
        print("self-test failed: counts", file=sys.stderr)
        return 1
    if summary["sixByteAddressSource"] != "advertisement":
        print("self-test failed: source", summary["sixByteAddressSource"], file=sys.stderr)
        return 1
    print("self-test passed")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", help="BTSnoop HCI log")
    parser.add_argument("--json", action="store_true", help="print JSON summary")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.path:
        parser.print_help()
        return 2
    path = Path(args.path)
    data = path.read_bytes()
    try:
        summary = summarize(data)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    # Refuse glucose decode: no such mode exists.
    if args.json:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print(format_text(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
