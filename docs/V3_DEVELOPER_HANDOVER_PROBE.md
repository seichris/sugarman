# V3 developer handover probe

## Status and scope

`SugarmanProbe` is a separate, foreground-only iOS developer application for
one owner-controlled, already-active Mainland GS3. It is implemented and
host-verified with synthetic data. It has **not** been installed on an iPhone,
connected to the sensor, or physically validated.

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
material, and non-authorized glucose history remain outside Git. Operational
iPhone handover confidence is **unproven until the physical gate passes**.

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
7. accept validated `0x39` batches and count unique live `0x32` record indexes;
8. disconnect after five unique live readings or after seven minutes.

There is no retry, reconnect, state restoration, background BLE mode, raw-write
entry point, `0x35`, `0x30`, `0xF0`, activation, binding, reset, secret-key,
firmware, lifecycle, HealthKit, or notification path. Authentication rejection,
an unknown notification, malformed crypto/frame data, BLE failure, cancel, or
timeout disconnects without another application write.

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
16-bit index selected from the private official-app capture; it is not a time or
glucose value. The importer rejects wrong schema versions, non-ASCII hex,
incorrect byte counts, and invalid names.

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
unbinding, run only the confirmed iPhone artifact once, require five unique live
readings, disconnect, and prove official Android handback. Any extra write,
unexpected response, value mismatch, or failed handback fails the gate.

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
