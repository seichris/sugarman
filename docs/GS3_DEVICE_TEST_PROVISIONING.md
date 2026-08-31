# GS3 managed foreground device-test provisioning

## Purpose

`SugarmanDeviceTest` is an isolated signing and physical-acceptance target for
the normal Sugarman production lifecycle. It reuses the normal app UI,
persistent store, safety projection, shared process ownership lease, typed
foreground coordinator, bounded single-flight reconnect, history cursor,
deduplication, and payload-free lifecycle events. It does not link or extend
the historical one-shot `SugarmanProbe` runtime.

The release `Sugarman` target remains fail closed and does not link
`GS3DeviceProvisioning`. This target is not an App Store distribution path.

## Two independent gates

Private import and live execution are separate operations:

1. **Import** requires a previously stored redacted owned-sensor identity and a
   strict private JSON document. It normalizes the values into a dedicated
   Keychain item using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, creates
   or validates one local `.live` / `.v3AES` session, and stops. It does not
   construct a controller, start CoreBluetooth, retrieve a peripheral,
   subscribe, authenticate, or write.
2. **Arm** is an explicit confirmation in the Device Test UI. Every new app
   process begins unarmed even when Keychain material exists. Arming installs
   the existing typed factory and starts it only while the scene is foreground.
   Leaving foreground performs the coordinator's controlled stop. Returning to
   foreground starts a fresh reducer only while that same process remains
   explicitly armed.

Deleting provisioning first stops the controller and then deletes only the
private Keychain item. Deleting all local app data also deletes that item.

## Private schema

The schema version is `1` and requires exactly these keys:

| Key | Boundary |
| --- | --- |
| `schemaVersion` | Must equal `1` |
| `peripheralIdentifier` | One private, previously observed CoreBluetooth UUID; never scanned or printed by this target |
| `sensorAddressHex` | Exactly 6 bytes of ASCII hexadecimal |
| `authenticationIDHex` | Exactly 12 bytes of ASCII hexadecimal |
| `registeredBlockHex` | Exactly 16 bytes of ASCII hexadecimal |
| `algorithmKeyHex` | Exactly 16 bytes of ASCII hexadecimal |
| `algorithmIVHex` | Exactly 16 bytes of ASCII hexadecimal |
| `effectiveDataStartIndex` | Capture-backed unsigned value bounded to the observed 16-bit request field |

Unknown keys fail closed. The document cannot represent activation,
registration, binding, reset, expiry, firmware, secret-key exchange, arbitrary
commands, or a fresh-sensor flow. The raw JSON is not committed, logged,
bundled, or stored verbatim; the app clears its mutable import buffer after
normalization. Replacing material for a different private sensor identity
requires explicit deletion first so durable session history cannot be silently
retargeted.

Private files and their hashes remain device-only/private evidence. Do not add
their contents, filenames, hashes, peripheral identifier, history start,
packet bodies, or sensor identifiers to Git, issues, PRs, logs, fixtures, or
shared diagnostics.

## Local session and controller boundary

The import links material to an already stored redacted `SensorIdentity` using
only its local random UUID. A separate local random session UUID is generated
once and retained inside the normalized Keychain record. The module inserts
the session as already-active `.live` / `.v3AES`, with a disconnected UI
projection and no claimed activation timestamp. This is local metadata only;
no sensor lifecycle command exists.

The public provisioning surface can return only a redacted availability
summary, import/delete material, or construct the existing
`GS3ForegroundSessionControlling` interface. Controller construction always
uses `GS3ForegroundSessionFactory.makeKnownPeripheralController`, which couples
the real shared App Group ownership provider to the bounded reconnect
scheduler and typed two-command CoreBluetooth adapter. Provisioning adds no
scan, raw frame, characteristic, or arbitrary-write surface.

## Observability and acceptance

The Device Test UI retains at most 128 in-memory `GS3LifecycleEvent`
descriptions plus typed write-acknowledgement counts. Its shareable report
contains process-local ordinals, phases, bounded counts, reconnect attempts,
and allowlisted transport reasons only. It omits packet bodies, UUIDs,
peripheral names, owner fields, private material, history indexes, glucose
values, and arbitrary error strings.

Host and simulator verification cannot establish CoreBluetooth behavior. A
new exact signed artifact and fresh owner confirmation must still gate every
installation, launch, import, arm, disconnect induction, Android handback, or
other physical step. The physical acceptance gates remain those in
[`GS3_FOREGROUND_PRODUCTION_DESIGN.md`](GS3_FOREGROUND_PRODUCTION_DESIGN.md):
five consecutive readings, zero unknown commands, one reconnect timer and one
fresh subscribe/authenticate/history sequence per connection, durable overlap
without duplicates or gaps, timestamp parity, stale/disconnected UI, process
exclusion, and official Android handback without binding or activation.

## Provenance and scope

This module is independently authored around the already-reviewed Sugarman
typed interfaces and public redacted evidence. It adds no new upstream source
adaptation and therefore no new provenance registry record.

Activation, binding, reset, expiry, firmware, secret-key and fresh-sensor
flows, HealthKit glucose writes, background restoration, scanning, arbitrary
raw writes, and TestFlight/App Store distribution remain out of scope.
