# GS3 V3 glucose-notification source map — 2026-08-30

## Outcome

An authorized read-only analysis of one owner's Mainland GS3, official Android
app, HCI capture, and owned APK establishes an offline decoder for the observed
V3 `0x32` glucose-notification family. The result has **high confidence for the
exact app, library, sensor, and capture hashes below**.

The private replay matches one withheld official-app observation exactly. The
reading, observation time, timezone context, and trend details are intentionally
omitted from Git. This is one parity point from one sensor, not validation of all
states, trend codes, lots, or firmware.

No sensor command was sent during this analysis. The new Swift decoder is
offline-only and remains disconnected from scanning, transport, and the live
codec factory.

## Scope, authorization, and evidence identity

All hardware, app, account, and capture data belonged to the owner. Inspection
used ordinary HCI logging, owner-readable logs, static symbol/disassembly
analysis, and private offline replay. It did not root the phone, read protected
app-private storage, defeat the managed-code wrapper, intercept TLS, alter the
APK, attach to the app, or bypass authentication or activation controls.

| Item | Verified identity |
| --- | --- |
| Official app | `com.sibionics.gstoc` `01.10.00.00` (version code 12) |
| APK SHA-256 | `0357d558c221a62129dca632fec2c73de70a978862228024f63f45d0b88fc1d7` |
| ARM64 library | `lib/arm64-v8a/libcxm_protocol.so` |
| Library SHA-256 | `19238019b9aca5f8ffae6a81fad98bb9f6525750b914367378f1ac1bbf765964` |
| Canonical glucose HCI capture SHA-256 | `165d697f4126d0fa2a8ea4f6d822b8fe74dd03e5663ba1e0910c9a197882d3e7` |
| Canonical capture size | 480,730 bytes |
| Pinned Juggluco reference | `11d016eb3aeffe77e86d9522f5192e83790b5a21` |

The raw capture, APK, native library, device address, authentication frames,
account identifier, registered block, algorithm key/IV bytes, and all other
glucose values remain under gitignored `private-evidence/`.

## Verified outer transport

Targeted ARM64 inspection of the exact library hash maps the outer notification
path as follows:

| Symbol / storage | VMA | Verified behavior used |
| --- | ---: | --- |
| `sdk_spilt_data` | `0x90068` | For encrypted inbound data, applies `AesFixedIvXorWithKey` to the complete frame before dispatching by command. The symbol spelling is from the library. |
| Glucose parser inside `sdk_spilt_data` | `0x92a80` | Validates and expands command `0x32` records into the native glucose structure. |
| `AesFixedIvXorWithKey` | `0xa93ec` | AES-128 OFB using the existing fixed V3 protocol key and the 16-byte session IV. |
| Fixed transport key | `.rodata` `0x5b910` | Same exact constant already recorded once in `V3Authentication.swift`. |
| Runtime IV | `.bss` `0x172880` | For this session, privately verified as the six Device Information address bytes in their displayed order followed by ten zero bytes. |

All 69 unique 24-byte FF31 notifications in the canonical capture decrypt to a
valid length byte, command `0x32`, one record, and an additive checksum whose
unsigned byte sum is zero modulo 256. The capture contains 68 notification
intervals: 66 are 59–61 seconds, the median is approximately 59.95 seconds,
and one interval exceeds 90 seconds across a reconnect. This supports a roughly
one-minute push cadence; it is not a guarantee about iOS background delivery.

## Verified plaintext layout

For record count `n`, the total plaintext size is `8 + 16n` bytes and byte 0 is
that total minus one. The 24-byte, one-record case is therefore length byte 23.

| Offset | Length | Meaning |
| ---: | ---: | --- |
| 0 | 1 | Declared frame length excluding this byte |
| 1 | 1 | Command `0x32` |
| 2 | 1 | Record count |
| 3 | 2 | Starting sensor index, little-endian |
| 5 | `16n` | Fixed-width records described below |
| `5 + 16n` | 2 | Ending reindex source, little-endian |
| final | 1 | Additive checksum |

Each 16-byte record has this layout:

| Record offset | Length | Swift name | Evidence status |
| ---: | ---: | --- | --- |
| 0 | 2 | `rawTemperature` | Native boundary verified; unit/scale unresolved |
| 2 | 2 | `rawDump` | Native boundary verified; meaning unresolved |
| 4 | 2 | `rawCurrent` | Native boundary verified; unit/scale unresolved |
| 6 | 2 | `rawDisplayGlucose` | Native `display_glouse` field; product semantics unresolved |
| 8 | 2 | encrypted algorithm glucose | Separate inner transform verified below |
| 10, bits 0–2 | 3 bits | `trendCode` | Bit boundary verified; semantic mapping remains private and unresolved for product use |
| 10, bit 3 | 1 bit | `presentCState` | Bit boundary verified |
| 10, bits 4–7 | 4 bits | `algorithmCState` | Bit boundary verified |
| 11, bits 0–1 | 2 bits | `tState` | Bit boundary verified |
| 11, bits 2–4 | 3 bits | `dState` | Bit boundary verified |
| 11, bits 5–7 | 3 bits | `algorithmReserved` | Bit boundary verified |
| 12 | 2 | `rawCEVoltage` | Native boundary verified; unit/scale unresolved |
| 14 | 2 | `rawREVoltage` | Native boundary verified; unit/scale unresolved |

The native parser increments `index` from the starting index. It assigns
`reindex` in descending order from `endingReindex + count - 1`. Integer fields
are little-endian. The committed Swift implementation preserves unresolved
fields as raw integers rather than inventing units or state labels.

## Verified inner glucose transform

| Symbol / storage | VMA | Verified behavior used |
| --- | ---: | --- |
| `Java_com_sisensing_cxmsdk_protocol_v3_V3ProtocolJNI_nativeDecryptAlgorithmGlucose` | `0x8c3b4` | Applies AES-128 OFB to the two-byte algorithm-glucose field. |
| Algorithm key | `.rodata` `0x5b7bd` | Fixed 16-byte value distinct from the outer transport key; bytes omitted from Git. |
| Algorithm IV | `.rodata` `0x5b7cd` | Fixed 16-byte value; bytes omitted from Git. |
| `struct_to_json_sdk_glouse_data_t` | `0x93c6c` | Corroborates the native field boundaries and names. |

The two decrypted bytes form an unsigned little-endian value in tenths of
mmol/L. Private replay produced the exact withheld parity point above. Every
post-calibration frame from that point through the end of the capture decoded
to the expected technical range. Plausibility is only a sanity check; the
private visible parity point is the stronger evidence.

Two owner-readable official-app logcat snapshots independently contain managed
`SDKGlucoseDataHandler` measurement records. Their readings, timestamps, trend
details, and identifiers remain private. This corroborates that the parsed trend
field reaches the managed layer without publishing an owner observation or
claiming a product-level semantic mapping.

## Observed official-app connection sequence

The canonical capture contains the following encrypted FF32 writes, classified
only after private decryption. Raw payloads are omitted:

| Command | Count | Observed role |
| --- | ---: | --- |
| `0xE2` | 4 | 38-byte authentication, once per connection |
| `0xF0` | 29 | Device-information queries |
| `0x35` | 1 | Activation-without-sensitivity, initial connection only |
| `0x39` | 4 | Single effective-data request, once after each reconnect |

The `0xF0` subcommands observed were 1, 3, 14, 15, and 17. The native response
mappers label them glucose sensitivity, device time, serial, device state, and
initialization time respectively. Static inspection also verifies:

- `sdk_get_single_effective_data` at `0x8fea8` constructs a seven-byte `0x39`
  request containing little-endian start/end indices and an additive checksum;
- `sdk_get_single_data` at `0x8f4e8` uses the same shape with command `0x30`.

A later payload-free chronological replay verified an additional bounded
relationship: for all four official `0x39` requests, the request's start index
equals the first following `0x32` or `0x39` data-batch start. There are three
distinct start indexes across those four connections. This proves how an
operator can validate a private probe import against the owned capture; it does
not establish the official app's broader persistence policy or authorize
guessing an index.

A post-probe official-app reconnect supplied a second independent ring-buffer
summary, SHA-256
`6d6467d9bcde31b23bc8c561e50a549dd5a24e43e231bc8bad40ae40ff4f77ac`.
It contains 13,527 HCI records, 580 ATT PDUs, five 38-byte `0xE2` writes, and
five seven-byte `0x39` requests with four distinct starts. All five request
starts equal their first following valid data-batch starts. The newest request
differs from the earlier provisional private import, so the next private import
was regenerated from that newest matched relationship. Only its
`effectiveDataStartIndex` field changed; the value and import hash remain
outside Git. The bugreport's separate `.filtered` snoop retained ACL/L2CAP
headers but no ATT payload and was not used for this conclusion.

A third bounded iPhone run used that replacement, authenticated successfully,
and invoked one `0x39` write. Its first following 24-byte FF31 value decrypted
to a matching declared length but an unsupported command before CoreBluetooth
acknowledged the write. The artifact did not retain the command byte or evaluate
the checksum after that failure. Official Android handback passed. This
disproves the earlier start-index mismatch as the cause of the third-run
failure, but it does not alter the verified canonical `0x32` layout above.

A real iOS handover therefore cannot be literally write-free: CoreBluetooth
must subscribe to notifications through the CCCD, and the observed official
sequence performs authentication and an initial data request. It does not issue
a per-reading write after setup. For an already-active handover, Sugarman must
omit `0x35` and every binding, activation, reset, and lifecycle mutation.

## Authentication correction relevant to handover

The same private replay corrects the earlier runtime-material result:

- the runtime IV is the six address bytes in the Device Information/displayed
  order followed by ten zero bytes;
- the 16-byte registered block can be recovered privately from the owned
  official authentication ciphertext once that IV is known; its public
  SHA-256 is `9b3982b682013c4ef96d9a32faf059fca53789cb712ba25fff1a2ad55e6555d6`;
- the authentication ID is the owner's numeric official-app user ID encoded as
  unsigned big-endian eight bytes followed by four zero bytes; and
- these values reproduce the private 38-byte authentication ciphertext exactly.

This unlocks a private already-active replay path. It does **not** establish a
general registration-material acquisition flow, and it does not solve fresh
activation. The `nativeRegisterKey` expected marker/AppKey route remains
unresolved; the private package value remains only an owner-visible
six-character link code, not a verified marker.

## Swift implementation and containment

- `V3GlucoseCryptoMaterial` constructs the verified outer IV shape but requires
  the algorithm key and IV from a caller-controlled source. Its descriptions
  expose lengths only.
- `V3OfflineGlucoseNotificationDecoder` verifies outer length, command, record
  count, exact frame size, and checksum before decoding records. It resets the
  inner OFB transform for each algorithm field, matching the verified JNI
  boundary.
- `V3GlucoseRecord` exposes typed fields but redacts glucose from descriptions
  and reflection.
- Tests use NIST-verified AES/OFB plus independently authored synthetic frames,
  including a two-record case. They contain no real key, IV, address, frame,
  registered block, account ID, or additional glucose history.
- In the normal `Sugarman` target, `GS3ProtocolRequest` remains empty,
  `GS3CodecFactory` still fails closed, and `GS3Transport` exposes no
  characteristic-write API. The separate developer target reaches this decoder
  through a typed one-shot state machine only.

The second fixed algorithm key and IV are intentionally **not** embedded. The
earlier scoped provenance approval recorded only the existing transport/auth
constant. Publishing the newly observed constants requires a separate explicit
legal/provenance decision. This containment allows decoder review and synthetic
testing now without silently expanding that approval.

## Licence and reference consequences

The Swift code is independently authored GPL-3.0-or-later expression based on
owned interoperability observations and public AES/OFB standards. No vendor
instruction sequence, table, compiled object, APK, or shared library is linked,
copied, or redistributed. The vendor binary remains proprietary or
unknown-licence evidence, not a Sugarman build input.

Pinned Juggluco remains an Android-only behavioral reference. Its older GS3
trend mapping must not be imported into V3 because V3 product semantics remain
unresolved. No Juggluco or xdripswift source was copied for this decoder.

The project's GPL obligations continue to apply to every distributed Sugarman
binary. App Store distribution and publication of additional fixed vendor
constants remain separate legal-review gates.

## Confidence, unknowns, and next gate

**High confidence for the exact evidence hashes:** outer AES-OFB transport,
address/IV order, `0x32` frame and record layout, additive checksum, separate
inner AES-OFB, little-endian tenths-of-mmol/L result, one private parity point,
and the observed reconnect command sequence.

**Medium product confidence:** one sensor/lot, one private parity point, and no
iOS background lifecycle evidence are insufficient for general Mainland GS3
support.

**Still requires physical testing:** already-active iPhone handover, official
Android handback after release, multiple consecutive iPhone values, background
and reconnect behavior, stale/error/calibration/expiry flags, non-flat trends,
another sensor lot, and a full sensor run.

**Still unresolved:** fresh activation's legitimate config/AppKey/marker route,
all trend/state mappings, historical range semantics, and whether another app
or firmware revision changes either fixed transform.

The next bounded implementation is a developer-only already-active probe that
can perform only CCCD subscription, one `0xE2` authentication, and one `0x39`
effective-data request. It must exclude `0x35` and all binding/activation/reset
commands, keep all owner material outside Git and logs, pass independent review,
and receive a fresh exact artifact/device/action confirmation before install or
live execution. The implementation and physical acceptance gates are specified
in
[`V3_ALREADY_ACTIVE_HANDOVER_TEST_PLAN.md`](V3_ALREADY_ACTIVE_HANDOVER_TEST_PLAN.md).
