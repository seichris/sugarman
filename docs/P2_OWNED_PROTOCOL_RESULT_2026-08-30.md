# P2 owned-protocol result — 2026-08-30

## Result

The owned Mainland China GS3 and official Android app use a **V3, 38-byte
AES-OFB authentication path**, not the 26-byte V1.20/RC4 path implemented by
the pinned Juggluco reference. Confidence is **high for this app, sensor, and
firmware**.

This identifies the protocol family. A later approved, read-only source-map
pass verified the authentication-frame construction and produced an isolated
offline Swift encoder; it does **not** authorize a live write. The legitimate
runtime-IV/registration-material source, owned-capture parity, notification
decryption, glucose decoding, a second sensor lot, and fresh activation remain
unverified. See
[`V3_AUTH_SOURCE_MAP_2026-08-30.md`](V3_AUTH_SOURCE_MAP_2026-08-30.md).

The payload-free machine-readable evidence is
[`evidence/owned-mainland-gs3-p2-summary-v1.json`](evidence/owned-mainland-gs3-p2-summary-v1.json).
All APK/native-library bytes and all owned runtime IV, registration,
authentication, address, account, and glucose values remain private and
gitignored. The exact fixed interoperability constant required by the observed
algorithm is recorded once in the approved GPL Swift implementation with
file-level provenance.

## Verified source evidence

### Official-app HCI behavior

In the canonical private HCI snapshot
`8f59200f694c51c533a30ae6e7398c35b46ced2bce3d7a6ec200e8e072302c19`:

- the first application write to the observed FF32 value handle is 38 bytes on
  each of four connections;
- those four authentication-like writes have one unique payload;
- there are no 26-byte writes; and
- none of the captured writes or notifications passes the pinned Juggluco RC4
  length/header/checksum family when checked offline with its pinned key.

Only lengths, counts, and pass/fail results are published. The analyzer did not
print the raw frames or attempt glucose decoding.

### Pinned GPL reference

At pinned Juggluco commit
`11d016eb3aeffe77e86d9522f5192e83790b5a21`:

- [`handleData.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics/handleData.cpp)
  SHA-256
  `36de28f7e9d09c72118e25593ef5e6cbdc426bf8b49557a77371ab9a1636d4a9`
  allocates a 26-byte authentication command and calls
  `v120_apply_authentication`; and
- [`interpret_data.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics/interpret_data.cpp)
  SHA-256
  `f796c1d1f4407439943f85671e9c29e74cf7abcc6d006889e9b141b689083fb7`
  constructs 26 bytes, applies the pinned RC4 routine, and returns 26.

Both files carry GPL-3.0-or-later notices. No source or key was copied into
Sugarman; this comparison uses their documented behavior and exact provenance.

### Owned APK static evidence

The owned official app copy is `com.sibionics.gstoc` version `01.10.00.00`, APK
SHA-256
`0357d558c221a62129dca632fec2c73de70a978862228024f63f45d0b88fc1d7`.
Its ARM64 `libcxm_protocol.so` has SHA-256
`19238019b9aca5f8ffae6a81fad98bb9f6525750b914367378f1ac1bbf765964`.

Read-only dynamic-symbol and targeted disassembly inspection verified this
call chain:

```text
V3ProtocolJNI.nativeBuildAuthIdCommand
  -> sdk_authid
  -> AesFixedIvXorWithKey
  -> AES_OFB_encrypt_buffer
```

The `sdk_authid` function passes 38 bytes to the AES wrapper and returns 38.
The library also exports V3 protocol and glucose-decryption JNI entry points.
No function was executed, patched, injected, or attached to the official app,
and no certificate pinning, login, or security control was bypassed.

## Evidence-backed inference

The exact 38-byte capture shape, the V3 JNI call path, and the native
38-byte AES-OFB construction mutually corroborate the conclusion. The pinned
26-byte RC4 path is incompatible with this owned setup.

The evidence does **not** establish that every Mainland GS3 lot uses the same
firmware, nor does the presence of AES-OFB symbols by itself reveal an approved
key/IV source or validate a glucose decoder. Those claims require separate
evidence.

## Licence and provenance consequence

The Juggluco files may be behaviorally referenced or adapted under
GPL-3.0-or-later with exact notices and provenance, but they implement the
wrong authentication generation for this sensor. The official Android APK and
its `.so` are proprietary/unknown-licence evidence, not reusable build inputs.
Sugarman must never ship, link, or copy them.

On 2026-08-30 the owner reported scoped approval for offline interoperability
analysis and a separately authored GPL Swift implementation. No approval
document or reviewer identity is asserted in the repository. The approval
covers publication of the separately authored GPL source, but not vendor-binary
redistribution, a live sensor write, or App Store/binary distribution.
Publishing source does not convert the vendor binary into a GPL-compatible or
redistributable input.

## Next gate

1. Keep the sensor on the official Android app; no live Sugarman write is
   approved by this report.
2. Establish a legitimate owner-controlled source for the runtime IV,
   registered block, and authentication ID without extracting another app's
   private storage or inventing values.
3. Reproduce the private official-app 38-byte authentication write with the
   isolated Swift encoder, including the correct address order.
4. Only after that parity, independent review, and a fresh physical-write
   confirmation may Sugarman attempt one bounded already-active authentication
   handover.
5. Validate a second lot before generalizing Mainland GS3 support, then test a
   fresh activation as a separate irreversible gate.
