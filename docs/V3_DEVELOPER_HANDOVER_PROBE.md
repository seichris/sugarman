# V3 developer handover probe

## Status and scope

`SugarmanProbe` is a separate, foreground-only iOS developer application for
one owner-controlled, already-active Mainland GS3. Merged PR #16 physically
validated authentication, one effective-data request, history delivery, and one
live `0x32` iPhone reading. The `5.3 mmol/L` result matched the official Android
pre-run control. The link then timed out at 1/5 readings, after one diagnostic
`0x36` quarantine, so the full handover/durability gate remains incomplete.
Official Android handback passed with a fresh `5.2 mmol/L` value. See
[`V3_FIRST_LIVE_READING_RESULT_2026-08-30.md`](V3_FIRST_LIVE_READING_RESULT_2026-08-30.md)
and the [earlier physical results](V3_PROBE_PHYSICAL_RESULT_2026-08-30.md).

The normal `Sugarman` application does not link `GS3DeveloperProbe` and retains
its empty live-request enum and transport without a write API. The developer
probe is not an App Store product target.

## Verified evidence and confidence

High confidence for the exact owned app/library/capture hashes:

- service FF30, notification FF31, and acknowledged-write FF32;
- a 38-byte encrypted `0xE2` authentication request;
- every observed `0xE2` write in the canonical private capture is followed by
  a five-byte response; the exact decrypted accepted response is command
  `0xE2`, code `0x01`, detail `0x00`;
- a seven-byte encrypted `0x39` request with little-endian start index,
  `0xFFFF` end index, and additive checksum;
- five-byte `0x39` acknowledgements and multi-record `0x39` data batches;
- live `0x32` notifications with 16-byte records; and
- one private offline decoder parity point against the official app.

These are independently recorded interoperability facts from the owned APK,
native library, and HCI capture. Raw packets, owner identifiers, cryptographic
material, and non-authorized glucose history remain outside Git. One-value iPhone
interoperability is physically proven; durable same-owner handover is not.

## Physical-run diagnosis and official-sequence comparison

The PR #13 UI retained neither packet classification nor state/counter
diagnostics. Source inspection shows that `error.localizedDescription` also
lost the probe's `CustomStringConvertible` message. The observed generic error
therefore cannot establish which packet class triggered the fail-closed path or
whether the conditional `0x39` CoreBluetooth call occurred.

A payload-free private re-analysis of all four connections in the canonical
Android capture verified the repeated order `0xE2 request`, exact acceptance,
device-information exchanges, `0x39` request, `0x39` acknowledgement, then
data. No live notification preceded authentication acceptance. The developer
probe omits the intervening device-information writes. That difference is
verified, but their necessity is not; the follow-up does not add them.

Merged PR #14 retained the payload-free trace. It proves the exact
authentication acceptance and bounded application-write calls, but its single
combined malformed/unsupported classification cannot identify why the
following 24-byte FF31 value failed. Private offline replay narrows the next
test:

- the imported address, outer material, and inner material decode all 69 unique
  canonical 24-byte live frames;
- each of four official `0x39` request starts exactly matches the first
  following data-batch start; and
- the second-run import's start index matches none of those official requests.

A fresh post-handback ring-buffer summary then independently yielded five
official `0x39` requests with four distinct starts. Every request start matches
its first following valid data batch. The newest request differs from both the
second-run value and the earlier provisional correction. The replacement
private import changes only `effectiveDataStartIndex` from the original PR #13
file to that newest verified start. The selected value and import hash remain
outside Git. Before the third run, the mismatch was the leading hypothesis at
medium confidence because the second-run FF31 payload was intentionally not
retained.

The third run used that replacement start and reached the same 24-byte point.
Its granular classification proves that outer decryption produced a matching
declared length and then an unsupported command, but the exact command and
checksum result were omitted. This disproves the start-index hypothesis for the
third-run failure. Merged PR #16 checks the checksum before reporting an
unsupported command, retains only the allowlisted protocol command byte, and
may quarantine one such 24-byte command only while CoreBluetooth still awaits
the sole `0x39` write acknowledgement. It adds no transmission. A second or
later unknown still fails closed, and readings observed after a quarantine do
not by themselves pass the diagnostic gate.

## Enforced command boundary

The flow is a typed state machine:

1. explicit peripheral selection, with an exact local-name match when the
   private import supplies one;
2. discover FF30 and only FF31/FF32;
3. subscribe to FF31;
4. transmit one typed authentication frame to FF32 with CoreBluetooth
   `.withResponse`;
5. decrypt and require the exact `0xE2 / 0x01 / 0x00` acceptance;
6. transmit one typed effective-data frame to FF32 with `.withResponse`;
7. while the sole `0x39` write acknowledgement is pending, optionally
   quarantine one checksum-valid 24-byte unsupported command without
   interpreting it or retaining any other payload byte;
8. accept validated `0x39` batches and count unique live `0x32` record indexes;
9. disconnect after five unique live readings or after seven minutes. A second
   or later unknown response fails closed.

There is no retry, reconnect, state restoration, background BLE mode, raw-write
entry point, `0x35`, `0x30`, `0xF0`, activation, binding, reset, secret-key,
firmware, lifecycle, HealthKit, or notification path. Authentication rejection,
an unknown notification, malformed crypto/frame data, BLE failure, cancel, or
timeout disconnects without another application write.

The merged follow-up also classifies every inbound FF31 value without
retaining its packet body, records state transitions and byte counts in memory,
reports CoreBluetooth write calls separately from acknowledgements, and permits
only one in-flight application write. It separates
control length/command/checksum failures and glucose minimum length/declared
length/command/count/layout/checksum failures. It also records whether
an FF31 value arrived while an FF32 write acknowledgement was outstanding. It
additionally exposes an unsupported command byte as protocol
metadata and checks the checksum before quarantine. The trace can be manually
shared as text and excludes all other packet bytes, identifiers, private
material, glucose values, and record indexes.

After the first live run exposed an unexpected transport timeout, the adapter
also records a per-process session ordinal, monotonic whole-second duration,
state, bounded write/live/quarantine counters, and either a numeric
CoreBluetooth error code or a redacted non-CoreBluetooth class. These fields are
payload-free and add no sensor operation, retry, or reconnect.

`Scripts/check_governance.py` permits exactly one CoreBluetooth write call in
the repository, in the probe adapter. It requires typed authentication and
effective-data cases plus `.withResponse`, forbids the listed command surfaces,
requires a separate package product and app target, and verifies the normal app
does not link the probe.

## Private material boundary

No real value belongs in source, build settings, app resources, launch
arguments, tests, logs, screenshots, PR text, or Git history. Create a JSON file
outside this repository using the private results from the owned HCI/APK
analysis:

```json
{
  "schemaVersion": 1,
  "expectedPeripheralName": "REPLACE_WITH_PRIVATE_LOCAL_NAME",
  "sensorAddressHex": "REPLACE_WITH_12_HEX_CHARACTERS",
  "authenticationIDHex": "REPLACE_WITH_24_HEX_CHARACTERS",
  "registeredBlockHex": "REPLACE_WITH_32_HEX_CHARACTERS",
  "algorithmKeyHex": "REPLACE_WITH_32_HEX_CHARACTERS",
  "algorithmIVHex": "REPLACE_WITH_32_HEX_CHARACTERS",
  "effectiveDataStartIndex": 0
}
```

`expectedPeripheralName` may be omitted, but including the exact owned name pins
it first in the searchable scan list. `effectiveDataStartIndex` is an unsigned
16-bit index selected from an actual private official-app `0x39` request whose
start matches its first following data batch; it is not a time or glucose
value. A placeholder, package link code, guessed number, or unrelated sensor
index is not valid material. The importer rejects wrong schema versions,
non-ASCII hex, incorrect byte counts, and invalid names, while capture-backed
selection remains an operator evidence gate.

The file is imported after installation with the Files picker. The app stores a
normalized binary record in a generic-password Keychain item using
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; it never stores the source JSON
verbatim. Delete the Files copy after import and use the app's delete action to
remove the Keychain item after testing. This limits accidental publication but
does not make an unlocked development phone a hardware security module.

## Host verification

Run from the repository root:

```sh
swift test
python3 Scripts/check_governance.py
xcodegen generate
CC="$PWD/Scripts/xcode-clang-wrapper.sh" xcodebuild \
  -scheme SugarmanProbe \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Tests use only synthetic addresses, IDs, blocks, keys, IVs, packets, indexes,
and glucose values. A simulator launch can validate the import/scan UI but
cannot validate CoreBluetooth hardware behavior.

## Physical gate

Building does not authorize installation, and installation does not authorize
sensor traffic. Before either operation, record the exact Git commit, signed app
manifest SHA-256, signing team, bundle ID, stable iPhone serial, iOS version,
sensor already-active state, and allowed actions. Obtain fresh owner confirmation
that quotes those identifiers and explicitly permits the installation and the
one-shot `0xE2`/`0x39` attempt.

Then follow
[`V3_ALREADY_ACTIVE_HANDOVER_TEST_PLAN.md`](V3_ALREADY_ACTIVE_HANDOVER_TEST_PLAN.md):
record the official Android baseline, turn Android Bluetooth off without
unbinding, run only a newly confirmed follow-up artifact and replacement
private import once, preserve its redacted trace, require five unique live
readings, disconnect, and prove official Android handback. Do not rerun any of
the PR #13, merged PR #14, or merged PR #15 artifact/material combinations. Any
extra write, second or late unknown response, value mismatch, or failed
handback fails the gate. A reading sequence after one quarantined command
remains diagnostic evidence rather than a handover pass until that command is
explained.

Fresh activation is outside this probe and requires a separate implementation,
legal decision, artifact, confirmation, and irreversible hardware gate.

## Licence and distribution consequence

All new source is GPL-3.0-or-later and independently authored. No vendor APK,
shared library, instruction sequence, or source is linked or redistributed.
The private fixed algorithm material is an operator-supplied local input, not a
committed or bundled dependency. This structure preserves provenance but is not
legal approval for TestFlight or App Store distribution. App Store/GPL terms,
vendor terms, interoperability law, cryptography/export, privacy, and athlete
wellness/medical positioning still require review before distribution.
