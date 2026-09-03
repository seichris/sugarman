# Mac-first GS3 private handover builder

## Purpose and boundary

`gs3-private-handover` is an offline macOS command-line tool for an owner who
already has an active Mainland GS3 sensor in the official Android app. It turns
one bounded Android Bluetooth HCI/BTSnoop session, the numeric user ID visible
to that owner in the official app, and a separately held private profile into
the existing strict version-1 Probe handover JSON.

The reusable Swift core has no Bluetooth, device, network, telemetry, vendor
login, APK, or native-library dependency. It does not activate, bind, reset,
scan for, connect to, or write to a sensor. It does not read Android private
app data. The command performs only local file reads and one atomic local file
write.

This is an already-active handover tool, not a fresh-activation implementation.
The legitimate fresh config/AppKey, encoded registration envelope, and marker
route remain unresolved. The tool fails closed rather than inventing them.

## Prerequisites

- macOS with the repository's supported Swift toolchain;
- one owner-controlled, already-active GS3 session in the official Android app;
- one normal Android Bluetooth HCI snoop export containing exactly one complete
  candidate connection;
- the owner-visible decimal official-app user ID; and
- a private version-1 profile containing the fixed algorithm key and IV from
  the previously authorized, version-pinned offline analysis.

Keep the capture, user ID, private profile, and output outside Git. The profile
must contain exactly these fields:

```json
{
  "schemaVersion": 1,
  "evidenceRevision": "<PINNED_EVIDENCE_REVISION>",
  "officialAppVersion": "<PINNED_OFFICIAL_APP_VERSION>",
  "nativeLibrarySHA256": "<PINNED_PUBLIC_LIBRARY_HASH>",
  "algorithmKeyHex": "<PRIVATE_16_BYTE_HEX>",
  "algorithmIVHex": "<PRIVATE_16_BYTE_HEX>"
}
```

The accepted public pins are the exact evidence revision, official-app version,
and native-library hash recorded in
[`V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md`](V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md).
The key and IV are not in this repository and must not be pasted into issues,
PRs, logs, fixtures, shell history, or shared diagnostics. Normal generation
does not repeat APK or native-library extraction.

## Obtain ordinary Android HCI evidence

On the owner's Android phone, use the normal Developer Options control for
Bluetooth HCI snoop logging. Enable it, let the official app complete one
ordinary connection to the already-active owned sensor, then disable logging.
Use Android's normal system bug-report/export UI to save the HCI log into the
owner's private evidence storage. Exact menu labels and the location inside a
bug report vary by Android vendor and version.

This route requires no root, `run-as`, private app-container access, ADB, TLS
interception, app modification, or sensor command. HCI logs can include traffic
from unrelated Bluetooth devices, so capture a short bounded window, avoid
sharing it, and fail closed if the builder reports more than one candidate
session. Do not edit or payload-filter the capture in a way that removes the
GATT discovery, Device Information read, official authentication write, or
history request/data pair.

## Build and run

From the repository root:

```sh
swift build -c release --product gs3-private-handover

swift run -c release gs3-private-handover build \
  --capture '<PRIVATE_BTSNOOP_PATH>' \
  --user-id '<OWNER_VISIBLE_NUMERIC_ID>' \
  --private-profile '<PRIVATE_PROFILE_PATH>' \
  --output '<PRIVATE_HANDOVER_OUTPUT_PATH>'
```

Use placeholders only in notes and shared command transcripts. Prefer entering
the real command in a private local shell session whose history is disabled or
cleared according to the owner's local policy.

On success, stdout contains only `Private handover written securely.` On
failure, stderr contains one bounded redacted reason. Neither stream includes
paths, packet bodies, command bytes, sensor names or addresses, user IDs,
private material, glucose values, record indexes, generated JSON, or hashes of
private values.

The output is created atomically in its destination directory with owner-only
`0600` permissions. It refuses to overwrite an existing path or either input.
A failed write removes its private temporary file. The JSON is never written to
stdout.

## What is extracted and validated

For exactly one capture-backed connection, the builder requires and validates:

- one exact complete advertised local name tied to the connected HCI peer;
- one six-byte Device Information address matching that peer in either byte
  order, with the exact order selected only by authentication replay;
- one unique official 38-byte authentication write;
- the decimal owner ID encoded as unsigned big-endian eight bytes plus four
  zero bytes;
- the authentication runtime IV as the selected address plus ten zero bytes;
- recovery of the registered block from the captured ciphertext;
- exact decrypt, checksum, field, and re-encode ciphertext parity; and
- one unique encrypted `0x39` history request whose start equals the first
  following valid `0x32` or `0x39` data-batch start.

Exact duplicate observations are suppressed. Missing, malformed, unsupported,
conflicting, or multiple evidence fails closed.

The profile's schema, public version pins, hex encoding, and lengths are
validated. The HCI capture does not contain an independent known plaintext for
the separate fixed algorithm key/IV, so a wrong but correctly sized private
pair cannot be detected from this evidence alone. The builder does not claim
otherwise and never guesses or substitutes those values.

## Limitations

The current parser accepts complete BTSnoop version-1 H4 captures using Android
datalink type 1002. The bounded session must retain the connection event,
complete-name advertisement or scan response, characteristic discovery,
Device Information read, complete FF32 writes, and FF31 notifications. It does
not reconstruct an authentication value split across ATT prepare-write
transactions, select among reconnects, repair filtered captures, or infer
missing handle-to-UUID mappings.

The evidence pins cover the exact official-app and native-library revision in
the source map. Other app versions, firmware, lots, address relationships, or
capture formats are unsupported until separately evidenced. The profile
key/IV limitation above remains independent of authentication replay parity.
No result establishes fresh activation or general GS3 compatibility.

## Import and cleanup

The result is the historical Probe schema documented in
[`GS3_PRIVATE_HANDOVER_JSON_PROVENANCE.md`](GS3_PRIVATE_HANDOVER_JSON_PROVENANCE.md).
Transfer it privately to the iPhone and choose the existing Probe JSON import
route in Sugarman's sensor provisioning UI. Import is inert. A separate,
explicit scan-only step matches the exact private name and learns the
iPhone-local CoreBluetooth identifier; Android, the package, the sensor, and
this Mac cannot provide that opaque Apple-host UUID.

After confirmed import, delete the transferred JSON and any local working copy
according to the owner's private-evidence retention policy. Keep or destroy the
source capture and profile under that separate policy. Do not commit any of
them. Removing files does not securely erase copies already retained by backup,
sync, snapshots, shell history, or bug-report archives.

The QR code, NFC/package data, or an unauthenticated sensor alone cannot supply
the complete already-active handover: they do not provide the captured official
authentication session, recovered registered block, private algorithm profile,
or iPhone-local CoreBluetooth identifier.
