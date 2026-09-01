# GS3 production background restoration

## Implemented boundary

The normal Sugarman target keeps one explicit connection-intent Boolean beside
its normalized, after-first-unlock, this-device-only Keychain provisioning.
This lets iOS reconstruct a background session after the user has unlocked once
since boot, without backup or cross-device migration. Version-1 records migrate
with that Boolean disabled, so an update cannot silently begin Bluetooth work.
Connect enables it; Stop and terminal fail-closed paths clear it. Import, NFC,
and scan-only lookup remain Bluetooth-inert.

When intent is enabled, one `GS3PersistentSessionLifecycle` owns one typed
controller across scene background transitions. Its generation guard prevents
concurrent construction or a late factory/start result from becoming a second
owner. The coordinator still acquires the cross-process owner lease before the
transport creates or uses CoreBluetooth.

Production creates `CBCentralManager` with the stable restoration identifier
`app.sugarman.ios.gs3.managed-session`. It is deliberately distinct from the
read-only diagnostic central's identifier. Restoration accepts only the already
provisioned CoreBluetooth identifier. A matching connected or connecting
peripheral is resumed without cancel/reconnect churn; a disconnected one uses
the existing system connection request. Every connection still performs fresh
service/characteristic discovery, notification subscription, typed
authentication, and one durable-overlap history request. Device Test supplies
no restoration identifier and keeps its foreground stop behavior.

This follows Apple's documented `bluetooth-central` wake and opt-in state
preservation model:

- <https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html>
- <https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionrestoreidentifierkey>
- <https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate/centralmanager(_:willrestorestate:)>

## Safety and privacy boundaries

- No scan, raw-write, retry command, activation, binding, or classifier
  weakening was added.
- Restored peripherals must match the one provisioned UUID; diagnostics never
  expose that UUID.
- Live UI progress is a single typed state: connecting, synchronizing,
  reconnecting, live, stopped, or failed.
- Native glucose-state observability contains only the five decoded status
  fields and record/distinct-state counts. It omits packet bodies, command
  bytes, identifiers, private material, glucose, timestamps, and record
  indexes.
- All native-state fingerprints remain `unvalidated`, producing
  `SampleQuality.questionable`. No physical evidence in this change proves a
  healthy/error mapping.

## Evidence status

Host tests verify Keychain-format migration, explicit intent transitions,
single-owner construction races, restoration policy for every peripheral
state, typed UI projection for every coordinator phase, and native-state
redaction/fail-closed classification. Unsigned simulator/device builds verify
compilation only.

Still physically gated: iOS background wake, lock-screen delivery, process
termination/relaunch restoration, RF loss and recovery, durable-overlap history
after restoration, notification cadence, battery behavior, and correlation of
native state fingerprints with the official app's healthy/error/calibration/
expiry states. Each run requires a new exact artifact/device/action
confirmation.
