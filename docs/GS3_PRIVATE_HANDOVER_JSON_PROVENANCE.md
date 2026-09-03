# GS3 private handover JSON provenance

## What this file is

The historical `v3-probe-material.json` was a locally assembled handover
document for one owner-controlled, already-active Mainland GS3 sensor. It was
not exported by the official Android app, downloaded from the vendor, read from
the Android app's private sandbox, or reconstructed from the box QR code.

The document combines facts from four separately controlled evidence sources:

1. normal Android Bluetooth HCI snoop captures of the owner's official-app
   sessions;
2. owner-readable official-app logs and the owner-visible official-app user ID;
3. offline analysis of the exact owned APK/native library, followed by private
   replay against captured official traffic; and
4. sensor and Apple-host observations, such as the advertised local name and a
   host-local CoreBluetooth identifier.

The raw captures, APK, native library, account value, sensor identifiers,
cryptographic material, packet bodies, glucose values, and the private JSON
remain outside Git. Public evidence records contain only hashes, counts,
source mappings, and payload-free conclusions.

## Evidence boundary

The Android work was read-only. It did not use root access, `run-as`, private
app-data access, TLS interception, certificate-pinning bypass, managed-code
unpacking, process injection, credential use, or a sensor/NFC command. The
protected managed implementation was not bypassed. The vendor APK and native
library were inspection evidence only and are neither committed nor linked by
Sugarman.

The owner-readable logs did **not** contain a named registration envelope,
runtime IV, or complete handover record. The HCI capture contained the official
authentication ciphertext and protocol traffic, but not a ready-to-import
JSON. The handover document was therefore constructed only after the native
input layout had been mapped and a private offline replay reproduced the
official authentication ciphertext exactly for this sensor/configuration.

## Field-by-field origin

The historical Probe schema has exactly the following fields. Values are never
included in this document.

| Field | Provenance | Confidence and limitation |
| --- | --- | --- |
| `schemaVersion` | Sugarman-authored import format. | Local format metadata; not supplied by Android or the sensor. |
| `expectedPeripheralName` | Exact local name observed in owned BLE advertising/session evidence. | Used only for an exact-name, bounded scan. It is an identifier, not authentication material. |
| `sensorAddressHex` | Six Device Information address bytes observed for the owned sensor, in the displayed order verified by private replay. | Sensor-specific. It is not an Apple CoreBluetooth UUID. |
| `authenticationIDHex` | Owner-visible numeric official-app user ID, verified for this replay as unsigned big-endian eight bytes followed by four zero bytes. | Verified for this owner/app/sensor replay; not a documented vendor export contract. |
| `registeredBlockHex` | Sensor/config-specific block recovered privately from the official authentication ciphertext after the runtime-IV construction and native layout were established. | Exact private ciphertext replay passed. A legitimate fresh-registration envelope route is still unresolved. |
| `algorithmKeyHex` | Private notification-decoding material established by authorized offline native-library analysis and capture replay. | Kept outside Git and logs. It is distinct from the public source description of the algorithm. |
| `algorithmIVHex` | Private notification-decoding material established by the same offline analysis and replay. | Kept outside Git and logs. It is not the authentication runtime IV. |
| `effectiveDataStartIndex` | Start value from an observed official `0x39` history request whose start matched its following data batch; the handover value was later replaced using fresher post-handback evidence. | Capture-backed bootstrap only. Once Sugarman has durable history, its persisted cursor supersedes this value. |

The authentication runtime IV is not a separate JSON field. Private replay
verified that it is constructed from the six sensor-address bytes followed by
ten zero bytes.

The historical Probe document intentionally contains no
`peripheralIdentifier`. CoreBluetooth identifiers are opaque and local to each
Apple host, so Android, the sensor package, and another Mac/iPhone cannot supply
the iPhone's value. After import, Sugarman's separately confirmed scan-only
step learns that host-local identifier by matching the exact private advertised
name. The scan cannot connect, discover GATT, subscribe, send a command, or
write.

## How the private document was assembled

This is a provenance record, not a promise of an automated acquisition path:

1. The owner enabled normal Android HCI snoop capture and allowed the official
   app to operate the already-active owned sensor.
2. Owner-readable app logs and HCI captures were copied to private evidence
   storage, hashed, and inspected offline. Credential-like unrelated data was
   excluded.
3. The exact owned APK and `libcxm_protocol.so` were identified by hashes. The
   native registration/authentication input shape and notification-decoding
   behavior were mapped without executing or redistributing vendor code.
4. Sensor address order, authentication-ID encoding, the authentication
   runtime-IV construction, and the recovered registered block were accepted
   only after an exact private replay of the captured official authentication
   ciphertext.
5. The distinct notification key/IV and one decoded notification point were
   checked privately against the official capture/app display.
6. A capture-backed history start and the exact advertised local name were
   selected from owned observations.
7. Those values were manually placed into the strict version-1 Probe schema
   and kept as a private local file for post-install import. At the time of the
   historical handover, no conversion tool or committed generator produced it.

The current repository now includes a Mac-first offline builder for repeating
that already-active construction without repeating APK/native-library analysis.
It accepts one owner-supplied BTSnoop session, the owner-visible numeric user
ID, and a separately held version-pinned private algorithm profile. It recovers
the registered block only after exact authentication decrypt/re-encode parity,
and accepts a history start only when the following valid data batch begins at
the same index. It emits this same strict schema; it does not add a permissive
format or a fresh-activation route. See
[`GS3_PRIVATE_HANDOVER_BUILDER.md`](GS3_PRIVATE_HANDOVER_BUILDER.md).

The HCI evidence cannot independently distinguish a correct private algorithm
key/IV from another correctly sized pair. The builder validates the separate
profile's exact public evidence pins and shape, while preserving that limitation
instead of claiming capture parity for those two fixed private values.

The current app validates this historical schema, copies it through a mutable
non-memory-mapped buffer, normalizes the material into a production-specific
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` Keychain item, and clears
the import buffer. This remains device-only and non-migrating while allowing a
previously opted-in managed connection to resume after lock-screen relaunch.
It never stores or exports the original JSON verbatim. Device Test and the
developer Probe retain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

## What the QR code and sensor cannot provide

The package QR/NFC data can identify or classify the sensor and may contain a
link marker or activation input. It does not provide the complete already-active
handover material above. Reading the sensor can provide observable identity and
Device Information values, but an unauthenticated sensor does not disclose the
complete active-session material as a handover document.

For a future unopened sensor, the desired product flow is a legitimate
activation/registration implementation that obtains its own authorized inputs.
The current evidence does not establish the vendor config/AppKey, encoded
registration-envelope, and expected-marker route. Do not guess those inputs,
scrape Android private storage, or reactivate a working sensor merely to
regenerate a handover file.

## Related evidence

- [`P2_RUNTIME_MATERIAL_RESULT_2026-08-30.md`](P2_RUNTIME_MATERIAL_RESULT_2026-08-30.md)
- [`V3_AUTH_SOURCE_MAP_2026-08-30.md`](V3_AUTH_SOURCE_MAP_2026-08-30.md)
- [`V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md`](V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md)
- [`GS3_DEVICE_TEST_PROVISIONING.md`](GS3_DEVICE_TEST_PROVISIONING.md)
- [`evidence/owned-mainland-gs3-runtime-material-summary-v1.json`](evidence/owned-mainland-gs3-runtime-material-summary-v1.json)
- [`evidence/owned-mainland-gs3-v3-glucose-summary-v1.json`](evidence/owned-mainland-gs3-v3-glucose-summary-v1.json)
