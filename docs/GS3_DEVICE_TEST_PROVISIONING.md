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

The reusable scan-only adapter and non-persisted external-owner confirmation
live in the separate `GS3DeviceTesting` package product. The iOS Device Test
and isolated `SugarmanMacDeviceTest` share those boundaries without linking
them into the release app. The Mac shell is future-product groundwork, but
remains a development target; see [`MACOS_DEVICE_TEST.md`](MACOS_DEVICE_TEST.md).

## Provisioning and live gates

Private import and live execution are separate operations:

1. **Direct import** requires a previously stored redacted owned-sensor identity
   and a strict private JSON document. It normalizes the values into a dedicated
   Keychain item using `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, creates
   or validates one local `.live` / `.v3AES` session, and stops. It does not
   construct a controller, start CoreBluetooth, retrieve a peripheral,
   subscribe, authenticate, or write.
2. **Existing Probe JSON bridge** is an optional provisioning route when the
   direct document is unavailable. Import strictly validates the Probe schema,
   links it to the redacted identity, clears the mutable file buffer, and keeps
   only normalized material in process memory. A second explicit action acquires
   the shared process-owner lease and scans for ten seconds. It retains only
   UUIDs whose local name exactly matches the private expected name, fails closed
   on zero or multiple distinct matches, stores the unique UUID with the
   normalized material, and stops. The adapter cannot connect, discover GATT,
   subscribe, authenticate, request history, or write. Backgrounding or an
   explicit stop cancels the scan and releases ownership. Process exit discards
   an incomplete bridge.
3. **Arm** is an explicit confirmation in the Device Test UI. Every new app
   process begins unarmed even when Keychain material exists. Arming installs
   the existing typed factory and starts it only while the scene is foreground.
   Leaving foreground performs the coordinator's controlled stop. Returning to
   foreground starts a fresh reducer only while that same process remains
   explicitly armed.

The Sensor screen owns one system file-import presentation for package images,
managed provisioning JSON, and the existing Probe JSON. A device-test request
pins its import kind and selected redacted identity before the picker appears;
the completion cannot be silently retargeted by an asynchronous store refresh.
The identity picker reconciles again whenever stored identities or the existing
Keychain link change, rather than relying on one launch-time task. Cancellation
and picker failure leave Keychain provisioning unchanged and surface a bounded
status without file paths or private content.

Both private JSON routes use the shared `PrivateDocumentImport` boundary. It
reads without memory-mapping, copies into owned mutable storage, exposes that
storage only through a scoped non-owning `Data` view, and clears the bytes on
every import exit and deinitialization. Private import code must not combine
`Data.ReadingOptions.mappedIfSafe` with `resetBytes`: a mapped file may be
read-only, so trying to clear it can terminate the process before the import UI
can report success.

Deleting provisioning first stops the controller and then deletes only the
private Keychain item. Deleting all local app data also deletes that item.

## Private schemas

The direct managed schema version is `1` and requires exactly these keys:

| Key | Boundary |
| --- | --- |
| `schemaVersion` | Must equal `1` |
| `peripheralIdentifier` | One private, previously observed CoreBluetooth UUID; never printed or shared by this target |
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

The bridge accepts exactly the historical Probe schema: the same six private
material/history fields plus `schemaVersion` and `expectedPeripheralName`.
`expectedPeripheralName` must be non-empty bounded printable ASCII; unlike the
historical Probe parser, `nil` is rejected because an unfiltered provisioning
scan would not identify one owned sensor. The bridge accepts no UUID in the
Probe JSON, emits no converted JSON, and never exposes the discovered UUID to
UI, diagnostics, reports, or logs.

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
summary, validate/discard an opaque Probe bridge request, complete that request
with one transient UUID, import/delete material, or construct the existing
`GS3ForegroundSessionControlling` interface. Controller construction always
uses `GS3ForegroundSessionFactory.makeKnownPeripheralController`, which couples
the real shared App Group ownership provider to the bounded reconnect
scheduler and typed two-command CoreBluetooth adapter. The separate Device Test
scan-only adapter uses the opaque request as an exact-name matcher and has no
controller, raw frame, characteristic, connection, or arbitrary-write surface.
It also requires a non-persisted external-owner confirmation before acquiring
the same-machine process lease. Scanning consumes that confirmation; arming
requires a fresh confirmation.

The separate `GS3DeviceTesting` product may wrap that typed controller with one
Device-Test-only link-loss control. It can cancel an already-streaming
CoreBluetooth connection at most once per controller. It is inert before
`live`, cannot encode or dispatch a frame, and is not linked into the release
app. The ordinary typed controller and two-command write boundary remain
unchanged.

## Observability and acceptance

The Device Test UI retains at most 128 in-memory `GS3LifecycleEvent`
descriptions plus typed write-acknowledgement counts. Its shareable report
contains process-local ordinals, phases, bounded counts, reconnect attempts,
and allowlisted transport reasons only. It omits packet bodies, arbitrary
command bytes, UUIDs, peripheral names, owner fields, private material, history
indexes, glucose values, imported JSON contents or hashes, and arbitrary error
strings. The typed first-rejection diagnostic distinguishes inbound
classification, write-callback, state, and request invariant failures. It may
record only a coarse frame category, bounded byte count, and allowlisted timing
window. It is ordered before the existing fail-closed disconnect and is
suppressed after the first occurrence in each connection. A separate typed
`historyPreambleObserved` event and per-connection count remain available when
the exact bounded empirical preamble policy actually accepts a frame.

The Mac Device Test may additionally show recent sample timestamps and values
inside its private on-device UI for side-by-side owner comparison. Those fields
are never included in the lifecycle report or share sheet and must not be
copied into Git, issues, PRs, logs, or shared diagnostics.

Host, simulator, and unsigned Mac builds cannot establish CoreBluetooth behavior. A
new exact signed artifact and fresh owner confirmation must still gate every
installation, launch, provisioning scan, arm, disconnect induction, Android
handback, or other physical step. A separately confirmed signed Mac run may
collect faster timing evidence, but it does not replace final iPhone
acceptance. The physical acceptance gates remain those in
[`GS3_FOREGROUND_PRODUCTION_DESIGN.md`](GS3_FOREGROUND_PRODUCTION_DESIGN.md):
five consecutive readings, zero unsupported or malformed commands, one
reconnect timer and one
fresh subscribe/authenticate/history sequence per connection, durable overlap
without duplicates or gaps, timestamp parity, stale/disconnected UI, process
exclusion, and official Android handback without binding or activation. One
exact bounded observed preamble may continue only to collect evidence; it does
not resolve the command's meaning or pass final protocol completeness.

## Provenance and scope

This module is independently authored around the already-reviewed Sugarman
typed interfaces and public redacted evidence. It adds no new upstream source
adaptation and therefore no new provenance registry record.

Activation, binding, reset, expiry, firmware, secret-key and fresh-sensor
flows, HealthKit glucose writes, background restoration, production connection
scanning, arbitrary raw writes, and TestFlight/App Store distribution remain
out of scope. The one bounded scan-only UUID-provisioning bridge is the sole
scanning exception.
