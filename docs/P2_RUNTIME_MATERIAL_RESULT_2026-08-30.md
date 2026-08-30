# GS3 V3 runtime-material evidence result — 2026-08-30

## Historical outcome and correction

The first bounded owner-readable search correctly found no *named*
registration-envelope or runtime-IV record in logs, exported files, or HCI.
Later authorized static analysis and private offline replay supersede the
earlier conclusion that the authentication material could not be recovered:

- the runtime IV is the owned sensor's six Device Information address bytes in
  displayed order followed by ten zero bytes;
- the 16-byte registered block is privately recoverable from the owned official
  authentication ciphertext once that IV is known;
- the authentication ID is the owner's numeric official-app user ID encoded as
  unsigned big-endian eight bytes followed by four zero bytes; and
- those values reproduce the private official 38-byte authentication
  ciphertext exactly.

The registered block remains sensor/config-specific and private. Its public
SHA-256 is
`9b3982b682013c4ef96d9a32faf059fca53789cb712ba25fff1a2ad55e6555d6`.
No raw IV, address, block, account value, authentication frame, or registration
envelope is committed.

This made an already-active private replay technically possible. The normal
`Sugarman` target still cannot represent or send a live authentication request:
its live request enum is empty and transport has no write API. A later separate
developer target now implements the bounded private-material import and one-shot
handover path described in
[`V3_DEVELOPER_HANDOVER_PROBE.md`](V3_DEVELOPER_HANDOVER_PROBE.md). Two bounded
physical runs have since failed closed before a validated iPhone value; the
latest proves authentication acceptance but not glucose decoding. No current
artifact is authorized for execution.

The payload-free machine-readable summary is
[`evidence/owned-mainland-gs3-runtime-material-summary-v1.json`](evidence/owned-mainland-gs3-runtime-material-summary-v1.json).
That file preserves the historical search result and is explicitly marked as
superseded in part. The corrected glucose/authentication evidence is in
[`V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md`](V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md).

## Authorized evidence inspected

All inspection was read-only and used the owner's Android phone, account, app
copy, active sensor, and existing captures. No root access, `run-as`, private
app-data read, TLS interception, certificate-pinning bypass, managed-code
unpacking, credential use, sensor command, or NFC command was attempted.

| Evidence | Public identity | Result |
| --- | --- | --- |
| Process-filtered official-app logcat | SHA-256 `c2754841bf877864bd4924998f26dfaa4364718b48a8307b5de6c80865f60922`; 836,474 bytes | Link metadata is present. No `nativeRegisterKey`, `registerKey`, `authId`, `AppKey`, `expectedId`, or registration-envelope record was found. Generic Android registration messages are unrelated. |
| Canonical owner-readable external app log | SHA-256 `74894891046cd8e19b32b4425991300ae640150192e7c730f6849d27259ca149`; 2,389,290 bytes | Connection records expose device/link/user metadata but no named registration envelope or runtime IV. |
| Five private BTSnoop files | Complete canonical hashes already recorded in the P1/P2 reports; one headers-only file and one truncated filtered file add no ATT payload evidence | Complete captures contain the repeated 38-byte authentication ciphertext and later protocol traffic, not the registration input or runtime IV. |
| Canonical glucose/auth capture | SHA-256 `165d697f4126d0fa2a8ea4f6d822b8fe74dd03e5663ba1e0910c9a197882d3e7`; 480,730 bytes | Later private decryption proves the address-plus-zero IV and permits registered-block recovery without publishing it. |
| Owned official app/APK | Package `com.sibionics.gstoc` `01.10.00.00`; APK SHA-256 `0357d558c221a62129dca632fec2c73de70a978862228024f63f45d0b88fc1d7` | Managed string tables expose wrapper/field names, while the relevant managed call-site implementation remains protected. We did not bypass that protection. The already-mapped native routine consumes, but does not derive, the missing envelope and IV. |

The external logs also contain opaque MQTT configuration values. They are
credential-like, unrelated to the proven native registration inputs, and were
excluded from analysis and publication.

## Verified source evidence

- `nativeRegisterKey` forwards a textual envelope, an expected marker, and a
  16-byte IV to `sdk_register_key`.
- `sdk_register_key` decodes the envelope, validates the marker, stores the
  16-byte registered block, and stores the caller-provided IV.
- `sdk_authid` later combines the address, stored block, authentication ID, and
  stored IV to produce the 38-byte authentication ciphertext.
- The HCI capture supplies the private output needed to verify the IV shape,
  recover the sensor/config-specific block, and test replay parity.
- Private replay now matches the official ciphertext exactly. The public Swift
  tests still use synthetic inputs only and contain no owner material.

## Fresh-activation inferences, not implementation inputs

- The package/NDEF link field may be the native expected marker because the
  official connection logs call it a link code. Confidence: **medium**.
- The owner-visible numeric user ID is now verified as the authentication-ID
  source for this owned replay. That does not prove a vendor-supported route for
  other accounts or fresh activation.
- No value should be guessed, padded, hashed, or taken from MQTT configuration
  to fill the still-unresolved fresh-registration inputs.

## Decision

1. Keep the new glucose decoder offline-only and use synthetic public fixtures.
2. Independently review the source map, private replay result, and provenance
   boundaries.
3. Decide whether the newly observed fixed algorithm-glucose key/IV may be
   published or must remain local developer inputs.
4. Review the implemented developer-only already-active probe, which is limited
   to CCCD subscription, one `0xE2` authentication, and one `0x39`
   effective-data request and omits `0x35`, binding, activation, reset, and
   lifecycle commands.
5. Obtain a fresh exact artifact/device/action confirmation before installation
   or execution, then verify official Android handback immediately afterward.
6. Treat fresh activation and its legitimate config/AppKey/marker route as a
   later, separate irreversible gate.

This correction advances already-active handover without weakening the
fresh-activation, provenance, or physical-device gates.
