<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- Copyright (C) 2026 Sugarman contributors -->

# Mainland GS3 P1/P2 hardware evidence — 2026-08-30

This is a sanitized report from an owned, already-active Mainland China
SiBionics GS3 and the owner's legitimate official Android app. It contains no
Bluetooth address, full sensor serial, account identifier, credential,
authentication payload, glucose payload, APK, vendor library, or raw HCI log.
The private inputs remain outside Git under the policy in
[`EVIDENCE_STORAGE.md`](EVIDENCE_STORAGE.md).

## Scope and method

- Sensor state: already active, owner-bound, and in its normal calibration
  period.
- Android phone: Xiaomi M2102K1C, Android 14 / API 34.
- Official app: `com.sibionics.gstoc`, version `01.10.00.00`
  (`versionCode=12`).
- Official APK SHA-256:
  `0357d558c221a62129dca632fec2c73de70a978862228024f63f45d0b88fc1d7`.
- APK signer SHA-256:
  `3F:E0:03:F5:00:2C:9F:4C:03:15:C8:9C:28:9B:07:0A:C7:95:22:0A:45:45:54:23:9F:78:3B:29:62:F2:0F:27`.
- Capture method: Android's normal **Bluetooth HCI snoop log** developer option
  set to full, one Bluetooth off/on cycle, and an ordinary reconnect by the
  official app. There was no MITM, certificate-pinning bypass, rooted access,
  private-storage extraction, or command sent by Sugarman.
- The bugreport's standard `BTSNOOP_LOG_SUMMARY` was converted with AOSP
  `btsnooz.py` from Bluetooth commit
  `745ee92b87ed62b5a8a1bac47d5df8cad623bf59`. The extraction-script SHA-256 was
  `ff4c96875c555f50e34eb5031ad23b53894cf0d8cfc59aac6289f711645a66bd`.
- Private BTSnoop SHA-256:
  `8f59200f694c51c533a30ae6e7398c35b46ced2bce3d7a6ec200e8e072302c19`.
  It was 482,512 bytes with 13,773 HCI records and 404 ATT PDUs.

The private capture was analyzed with Sugarman's redacting analyzer plus
targeted offline correlation that emitted only UUIDs, lengths, ordering, and
match direction. Raw values were not copied into this report.

## Observed device and GATT shape

| Field | Sanitized observation |
| --- | --- |
| Manufacturer | `SISENSING-CN` |
| Model | `GS3*-5EANLA` |
| Hardware | `GK5_NRF_V0.1` |
| Firmware | `01.07.00` |
| Software | `1.1.6G_V3.4.0` |
| Custom service | FF30 |
| Notify characteristic | FF31 |
| Write characteristic | FF32 |

The extracted in-memory capture contained connection and ATT traffic but no LE
advertising report, so this run provides no evidence about advertisement names
or payloads.

## P1: legitimate source for the six authentication bytes

**Conclusion: passed with high confidence.**

The standard readable Device Information serial-number characteristic `2A25`
returned a 17-character textual Bluetooth address. The analyzer correlated the
ATT read request and response with the same HCI connection and found that the
six parsed bytes exactly matched that connection's peer-address field in normal
order. A same-length value alone was not treated as evidence.

The value itself was neither printed nor retained in this report. This proves a
legitimate BLE-readable source instead of guessing from CoreBluetooth's opaque
peer UUID. A physical iPhone probe must still confirm that CoreBluetooth can
read `2A25` on this sensor and should consume the value transiently without
displaying, persisting, logging, or exporting it.

## P2: protocol generation

**Conclusion: V3 / AES-OFB with high confidence.**

Independent observations converge:

1. The official-app exchanges contained four 38-byte authentication writes and
   zero 26-byte authentication writes. The pinned Juggluco V1.20/RC4
   authentication builder emits 26 bytes.
2. The sensor's readable software revision identifies `V3.4.0`.
3. Static inspection of the owned APK found both V2 and V3 entry points, so
   symbol presence alone was not considered proof. Its V3
   `nativeBuildAuthIdCommand` calls `sdk_authid`; that routine builds and returns
   exactly `0x26` (38) bytes.
4. That 38-byte routine calls `AesFixedIvXorWithKey`, which directly calls
   `AES_OFB_encrypt_buffer` in the same owned APK library.

No key bytes were extracted and no cipher was tried against the live sensor.
The evidence identifies the protocol and cipher family; it is not yet a
complete, independently implementable V3 frame specification.

## Consequences

- Stop the planned V1.20/RC4 implementation for this Mainland hardware.
- Do not ship or link the official APK or any Android `.so` in Sugarman.
- Treat the owned APK only as private interoperability evidence. Complete the
  planned legal review before adapting V3 behavior into GPL Swift source.
- Build any codec offline, in pure Swift, with exact file-level provenance and
  capture-derived tests before enabling a live authentication write.

## Remaining gates

1. Preserve a second private HCI capture after calibration produces the first
   official glucose reading; the current capture proves authentication but not
   live-glucose decoding.
2. Release the official app and run Sugarman's bounded physical-iPhone probe:
   scan, connect, discover, read DIS, export a redacted GATT map, and disconnect.
   Do not authenticate or hand over yet.
3. Create a V3 source map that identifies frame structure, registration input,
   checksum/integrity behavior, response state machine, and glucose/history
   semantics without relying on a distributable vendor binary.
4. Implement and verify a pure Swift offline codec before the separately gated
   same-owner handover test.

This report advances issue #6's P1 and P2 evidence gates. It does not claim that
Sugarman can authenticate, collect glucose, activate, or take over a GS3.
