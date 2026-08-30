# GS3 V3 authentication source map — 2026-08-30

## Scope and approval

This source map covers **offline interoperability analysis** of the owner's
copy of the official Mainland Android app and a separately authored GPL Swift
implementation of the observed V3 authentication frame. On 2026-08-30, the
owner reported that the required scoped legal/provenance approval had been
obtained.

That report is recorded as a user attestation; no legal opinion, reviewer name,
or approval document was supplied to this repository. The approved scope
includes publication of the separately authored GPL source. It does not include
redistributing or linking the APK/shared library, bypassing app or account
security controls, sending a live sensor write, or App Store/binary
distribution.

## Evidence identity

| Item | Verified identity |
| --- | --- |
| Official app | `com.sibionics.gstoc` `01.10.00.00` (version code 12) |
| APK SHA-256 | `0357d558c221a62129dca632fec2c73de70a978862228024f63f45d0b88fc1d7` |
| ARM64 library | `lib/arm64-v8a/libcxm_protocol.so` |
| Library SHA-256 | `19238019b9aca5f8ffae6a81fad98bb9f6525750b914367378f1ac1bbf765964` |
| ELF build ID | `7ac080cb4cab9882abeac7beb86fafb2c6ccbdb1` |
| Owned HCI snapshot | `8f59200f694c51c533a30ae6e7398c35b46ced2bce3d7a6ec200e8e072302c19` |

The APK, ELF, raw HCI capture, addresses, authentication frames, account data,
and runtime registration material remain under gitignored `private-evidence/`.

## Verified native source map

The following facts were reproduced with Apple LLVM `objdump` against the
exact ARM64 library above. VMAs and sizes refer only to that hash.

| Symbol / storage | VMA | Size | Verified behavior used |
| --- | ---: | ---: | --- |
| `Java_com_sisensing_cxmsdk_protocol_v3_V3ProtocolJNI_nativeBuildAuthIdCommand` | `0x8b4bc` | `0x1dc` | Accepts the encryption flag and device type, requires a 6-byte address, accepts at most 12 authentication-ID bytes, calls `sdk_authid`, and returns its output. |
| `sdk_authid` | `0x8f810` | `0x22c` | Constructs 38 bytes, adds the final additive checksum, optionally encrypts all 38 bytes, and returns 38. |
| `AesFixedIvXorWithKey` | `0xa93ec` | `0x78` | Initializes AES-128 from the fixed 16-byte protocol constant, loads a 16-byte runtime IV, and invokes OFB over the frame in place. |
| `AES_OFB_encrypt_buffer` | `0xa9184` | `0x268` | Implements bytewise XOR with successive AES-encrypted feedback blocks, including a partial final block. |
| Fixed protocol constant | `.rodata` `0x5b910` | 16 bytes | Passed as the AES-128 key by `sdk_authid`. The exact value appears once in the independently authored Swift implementation. |
| Runtime IV | `.bss` `0x172880` | 16 bytes | `sdk_register_key` copies the third `nativeRegisterKey` byte-array argument here; `sdk_authid` later passes it as the OFB IV. |
| Registered block | `.bss` `0x172890` | 16 bytes | On successful registration-envelope validation, `sdk_register_key` copies 16 decoded bytes here; `sdk_authid` places them in the authentication plaintext. |
| `sdk_register_key` | `0x935b8` | `0x498` | Copies the runtime IV, decodes a textual envelope, applies the observed fixed-key transform, validates an embedded marker, and stores the 16-byte registered block. |

The managed DEX exposes Kotlin/source-map names but its application classes are
protected. We did not unpack the protection-wrapped managed payload, dump it,
inject into it, attach to it, or bypass that protection. Field names below
therefore distinguish native facts from semantic inference.

## Verified 38-byte plaintext layout

| Offset | Length | Meaning / confidence |
| ---: | ---: | --- |
| 0 | 2 | Constant header `25 e2`; verified. |
| 2 | 1 | Native integer argument narrowed to one byte; `deviceType` is the JNI/log terminology, high confidence. |
| 3 | 6 | Address byte-array argument; exact length verified. P1 separately proves a legitimate iOS-readable source. Address byte order still needs replay parity. |
| 9 | 16 | Registered global block populated by `sdk_register_key`; placement and length verified, higher-level meaning unresolved. |
| 25 | 12 | Authentication-ID argument, copied then zero-padded to 12; layout verified, higher-level owner/account semantics unresolved. |
| 37 | 1 | Two's-complement additive checksum so the unsigned sum of all 38 plaintext bytes is zero modulo 256; verified. |

The whole 38-byte plaintext is then transformed with AES-128 OFB using the
observed fixed key and the registered runtime IV. OFB has no padding, so the
ciphertext is also exactly 38 bytes. The Swift AES implementation is separately
checked against [NIST FIPS 197](https://csrc.nist.gov/pubs/fips/197/final) and
the OFB vectors in
[NIST SP 800-38A](https://csrc.nist.gov/pubs/sp/800/38/a/final).

## Swift destination and containment

- `Sources/GS3Protocol/AES128.swift` is a clean Swift implementation of the
  public NIST AES-128 and OFB algorithms.
- `Sources/GS3Protocol/V3Authentication.swift` contains the observed frame
  layout and the one exact fixed protocol constant required by it.
- `Sources/GS3Protocol/V3Registration.swift` strictly reproduces the observed
  registration-envelope transform when a caller already has the legitimate
  encoded envelope, expected marker, and 16-byte IV. Its RC4 primitive is
  checked against [RFC 6229](https://www.rfc-editor.org/info/rfc6229/) and is
  unavailable as a general cipher choice. The public decoder accepts only the
  non-NUL ASCII marker subset whose bytes have identical Swift UTF-8 and JNI
  C-string representations; other marker encodings fail closed.
- Public construction accepts only opaque material returned by that strict
  decoder; raw block-and-IV construction is file-private to the decoder and raw
  authentication-input construction is private to its type.
- `ProtocolVariant.v3AES` identifies the observed family but remains
  `isImplemented == false`.
- `GS3ProtocolRequest` remains empty, `GS3CodecFactory` still fails closed, and
  `GS3Transport` has no characteristic-write API. The encoder is therefore
  reachable only as an explicit offline function.
- Tests use NIST vectors and synthetic V3 inputs independently reproduced with
  OpenSSL 3.6.3 during review. No
  owned address, IV, registered block, authentication ID, or HCI payload is in
  the repository.

No source, instruction sequence, table, or compiled object from the vendor ELF
is linked or copied. The fixed 16-byte interoperability constant and behavioral
facts above are independently recorded under the user-reported approval. The
vendor binaries remain proprietary/unknown-licence evidence and are not GPL
inputs or redistributable artifacts.

## Remaining gates and confidence

### Verified source evidence — high confidence for this app/library hash

- exact 38-byte layout, checksum, AES-128/OFB path, fixed-key location, runtime
  IV location, registered-block location, and native input length checks;
- official HCI first-write length is 38 bytes on four captured connections;
- standard AES/OFB behavior is testable against NIST vectors.

### Evidence-backed inference — medium confidence

- `deviceType`, `registeredBlock`, and `authenticationID` are safe API labels
  for the native values, but the protected managed layer prevents stronger
  semantic claims;
- the same source map likely applies to another sensor using the exact app and
  library hash, but this has not been tested across lots or firmware.

### Physical/private evidence still required

The bounded owner-readable log/HCI search is documented in
[`P2_RUNTIME_MATERIAL_RESULT_2026-08-30.md`](P2_RUNTIME_MATERIAL_RESULT_2026-08-30.md).
It did not locate the missing registration envelope or runtime IV and does not
permit a live probe.

1. Establish a legitimate owner-controlled source for the runtime IV,
   registered block, and authentication ID without reading another app's
   private storage or inventing values.
2. Reproduce the official 38-byte ciphertext from a private replay fixture,
   testing the proven Device Information address in both candidate byte orders.
3. Obtain a fresh physical-write confirmation naming the exact commit, build,
   iPhone serial, iOS version, owned sensor, and bounded authentication-only
   action.
4. Only then connect the offline encoder to a single transport write and verify
   official-app handback. Activation, reset, secret-key, lifecycle, and
   firmware-management commands remain out of scope.

Until items 1 and 2 pass, confidence in the **offline construction** is high,
but confidence in an **operational handover** is explicitly unproven.
