# GS3 V3 runtime-material evidence result — 2026-08-30

## Outcome

The authorized, owner-accessible evidence does **not** contain enough material
to reproduce the official app's 38-byte V3 authentication write offline.
Sugarman therefore remains deliberately unable to represent or send a live
authentication request.

The six-byte sensor address has a legitimate Device Information source, and the
package/NDEF link field is a plausible registration-marker candidate. The
official app's owner-readable logs also contain user/link metadata. However, no
legitimate source was found for the encoded registration envelope or the
16-byte runtime IV that the verified native registration routine requires.
Those values cannot be recovered from the observed ciphertext by assumption or
from the other known fields.

Confidence is **high for the inspected files and captures** and **unknown for
data that may exist only behind the vendor service or inside protected
app-private state**.

The payload-free machine-readable summary is
[`evidence/owned-mainland-gs3-runtime-material-summary-v1.json`](evidence/owned-mainland-gs3-runtime-material-summary-v1.json).

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
- The HCI capture therefore supplies the **output** needed for replay parity,
  not the two missing registration inputs needed to generate that output.
- The public Swift codec passes standard and independent synthetic vectors, but
  no owned official-app replay fixture exists yet.

## Inferences, not implementation inputs

- The package/NDEF link field may be the native expected marker because the
  official connection logs call it a link code. Confidence: **medium**.
- The owner-visible/logged user identifier may map to the native authentication
  ID. Confidence: **low to medium** because the protected call site was not
  observed.
- Neither inference supplies or substitutes for the registration envelope or
  runtime IV. No value should be guessed, padded, hashed, or taken from MQTT
  configuration to fill those fields.

## Decision

1. Do not create a write-capable handover build and do not send an
   authentication probe.
2. Seek a legitimate vendor-documented or owner-visible route for the
   registration envelope, runtime IV, and authentication-ID semantics: vendor
   interoperability support, API documentation, or an official user-facing
   export/support bundle.
3. If that route remains unavailable, a fresh official-app activation on a
   separate unopened owned sensor may be considered only after a new explicit
   irreversible-test confirmation and scoped legal review. Use normal HCI and
   owner-readable diagnostics only; do not intercept TLS or access protected
   private storage. If the inputs remain protected, stop.
4. Once legitimate inputs exist, run a private offline replay against the
   captured 38-byte write in both candidate address orders.
5. Only exact replay parity, independent review, and a new artifact/hardware
   confirmation can authorize preparation of one bounded authentication-only
   handover probe.

This is a negative evidence result, not a protocol failure. It preserves the
active sensor and the official app connection while identifying the exact
missing inputs.
