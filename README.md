# Sugarman — Glucose monitoring for endurance athletes

Sugarman is a native Swift/SwiftUI Apple-platform project that gives endurance athletes a
glanceable view of glucose, trend, reading age, and sensor connectivity, then
correlates that timeline with workouts and user-recorded fueling events.

**Athlete fueling insight only.** Sugarman does not diagnose conditions,
recommend treatment, or suggest insulin or medication doses. Never use these
readings to dose insulin.

Licence: [GPL-3.0-or-later](LICENSE)

## Licence

Sugarman is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This project adopted `GPL-3.0-or-later` **before** adapting any Juggluco or
xDrip/xdripswift expression. See [THIRD_PARTY.md](THIRD_PARTY.md),
[docs/provenance/](docs/provenance/), and
[docs/LEGAL_LOCAL_RESEARCH.md](docs/LEGAL_LOCAL_RESEARCH.md).

### Corresponding source for distributed builds

Every binary that is distributed outside a private owner-device build must be
accompanied by the exact corresponding source required by GPLv3 section 6:

1. Tag the Git commit that produced the build (`sugarman-<version>-<git-sha>`).
2. Archive this repository at that tag, including the `Package.swift`,
   `project.yml`, Xcode project, and build/CI scripts in this tree.
3. Publish the tag and archive (GitHub Releases is sufficient) or offer the
   same source by a written offer as GPLv3 allows.
4. Record the tag in [docs/provenance/registry.json](docs/provenance/registry.json).

Upstream Git submodules under `upstream/` are **reference-only** and are not
part of the Sugarman application binary. They are not Xcode/package
dependencies. See [docs/UPSTREAMS.md](docs/UPSTREAMS.md).

## Product posture

- Offline-first; no cloud backend and no CloudKit in the initial product.
- First live UI always shows reading age, stale/disconnected state, and the
  no-dosing notice.
- The legacy normal-app request enum remains empty, its generic codec factory
  remains fail closed, and the read-only diagnostic transport still has no
  write API. A separate reviewed foreground adapter can retrieve one known
  peripheral and execute only package-scoped typed `0xE2` authentication and
  `0x39` effective-data requests, both with response. The release bootstrap
  installs no factory or active-session material, so it cannot instantiate that
  path without a separately reviewed device-only artifact. The concrete
  adapter/coordinator are package-only; their public factory always installs the
  real shared process owner and bounded reconnect scheduler.
- A separately signed `SugarmanDeviceTest` target reuses the normal Sugarman UI,
  store, safety projection, and production coordinator without linking the
  historical one-shot Probe. Its dedicated provisioning module accepts one
  strict private JSON document after installation, normalizes it into a
  when-unlocked, this-device-only Keychain item, and prepares only a local
  already-active `.live` / `.v3AES` session. It can alternatively validate the
  historical Probe JSON in memory, then—behind another explicit confirmation—
  run one ten-second, exact-name, shared-owner scan that stores the matching
  CoreBluetooth UUID without connecting. Import is Bluetooth-inert, and the
  scan-only adapter has no connect, GATT, subscription, command, or write API.
  Every app process starts unarmed, and only a separate in-app confirmation
  installs the typed factory and begins the managed foreground lifecycle. The
  release `Sugarman` target does not link this module.
- An isolated `SugarmanMacDeviceTest` target reuses the same typed controller,
  persistence, ownership, and payload-free diagnostics for faster Mac-side
  hardware iteration. Its exact-name scan resolves a Mac-local CoreBluetooth
  identifier, and both scan and arm require a non-persisted confirmation that
  every phone and other app has released the sensor. It is reusable groundwork
  for a future Mac product, not a production release or a substitute for final
  iPhone acceptance. See the [macOS Device Test guide](docs/MACOS_DEVICE_TEST.md).
- The production foreground lifecycle requires one shared App Group process
  lease, repeats subscription/authentication/history on every connection, uses
  bounded single-flight reconnect, establishes a durable sensor-time anchor
  with its cadence/revision, and commits overlapping history atomically. The
  reducer, coordinator,
  persistence, ownership, and privacy boundaries are host-tested; CoreBluetooth
  reconnect and timestamp behavior remain physical gates. See the
  [foreground production design](docs/GS3_FOREGROUND_PRODUCTION_DESIGN.md).
- A separate, foreground-only `SugarmanProbe` developer target can perform one
  tightly bounded already-active handover attempt: subscribe to FF31, transmit
  one typed `0xE2` authentication, transmit one typed `0x39` request only after
  exact authentication acceptance, observe five unique live readings, then
  disconnect. A follow-up may quarantine one checksum-valid 24-byte unsupported
  command only while the sole `0x39` write acknowledgement is pending; it
  retains only that command byte and does not interpret it. It has no
  activation, binding, reset, retry, reconnect, arbitrary raw-write, background,
  or HealthKit path. It requires post-install private
  material import and a fresh exact physical-device confirmation; see the
  [probe guide](docs/V3_DEVELOPER_HANDOVER_PROBE.md).
- Merged PR #16 physically produced the first validated iPhone live reading:
  `5.3 mmol/L`, matching the official Android pre-run value, with one typed
  `0xE2`, one typed `0x39`, history batches, and one live `0x32` batch. The link
  then timed out at 1/5 readings and the run had quarantined one checksum-valid
  `0x36`, so the full handover/durability gate remains incomplete. Android
  handback passed with a fresh `5.2 mmol/L` reading. See the
  [first-live-reading result](docs/V3_FIRST_LIVE_READING_RESULT_2026-08-30.md)
  and the [earlier probe results](docs/V3_PROBE_PHYSICAL_RESULT_2026-08-30.md).
- The first managed Device Test run reached its durably prepared history
  request, then failed closed before the CoreBluetooth history-write
  acknowledgement; official Android handback again passed. The host policy
  recognizes one exact checksum-valid 24-byte `0x36` as a payload-free observed
  preamble, with no added write, retry, data, or readiness semantics. See the
  [managed-run result](docs/GS3_DEVICE_TEST_PHYSICAL_RESULT_2026-09-01.md).
- Exact Mac Device Test runs reproduced the typed iPhone ordering, proved the
  rejected frame was the known checksum-valid 24-byte preamble overtaking
  history dispatch, and then physically passed the two-layer receive-only gate.
  The successful run used one authentication write, one history write, and one
  accepted preamble; committed history through zero remaining gaps; and entered
  `live` only after committing a live notification. It added no command, retry,
  or reconnect and stopped cleanly. Five-reading durability, unexpected-link-
  loss reconnect, official-app handback for that run, and final iPhone
  acceptance remain open.

## Repository layout

| Path | Role |
| --- | --- |
| `Sources/SugarmanDomain` | Pure domain types and product copy |
| `Sources/GS3Protocol` | Fail-closed live interfaces plus isolated offline V3 authentication and glucose codecs |
| `Sources/GS3DeveloperProbe` | Typed, one-shot already-active V3 probe state machine and device-only private-material store |
| `Sources/GS3Transport` | Read-only BLE diagnostics plus the typed known-peer foreground coordinator and adapter |
| `Sources/GS3Session` | Pure foreground ownership/reconnect/history lifecycle reducer |
| `Sources/GS3DeviceProvisioning` | Strict device-only import, Keychain normalization, local live-session preparation, and typed production-controller construction for the isolated Device Test target |
| `Sources/GS3DeviceTesting` | Shared scan-only adapter and non-persisted cross-device ownership confirmation for isolated Device Test apps |
| `Sources/SensorOwnership` | Payload-free cross-process App Group file lease |
| `Sources/SensorOnboarding` | Bounded package/NDEF parser interfaces |
| `Sources/AccountBinding` | Manual legitimate owner ID only |
| `Sources/SugarmanStore` | Repository protocols, in-memory store, optional SwiftData |
| `Sources/SafetyEngine` | Stale/disconnected/warm-up/error/expiry evaluator |
| `Sources/Integrations` | HealthKit/export interfaces; HealthKit writes disabled |
| `Sources/SugarmanDiagnostics` | Read-only GATT probe, redacted GATT export, BTSnoop analyzer |
| `Apps/Sugarman` | SwiftUI iOS application shell |
| `Apps/SugarmanProbe` | Separate foreground-only developer handover application; not linked by `Sugarman` |
| `Apps/SugarmanDeviceTest` | Signing metadata for the isolated normal-app production-lifecycle test target |
| `Apps/SugarmanMacDeviceTest` | Isolated macOS test/product-foundation shell; no release-app linkage |
| `upstream/` | Pinned research references — not build inputs |

## Build and test

Portable modules (Swift 6):

```sh
swift test
```

iOS application (iOS 26.0, Xcode 26):

```sh
xcodegen generate
xcodebuild -scheme Sugarman -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Explicitly isolated production-lifecycle test target; importing remains inert.
CC="$PWD/Scripts/xcode-clang-wrapper.sh" xcodebuild \
  -scheme SugarmanDeviceTest \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Or open `Sugarman.xcodeproj` in Xcode and run the `Sugarman` scheme on an iOS 26
simulator. Device builds need an Apple Developer team selected locally; the
bundle identifier is `app.sugarman.ios`. Do not invent a team ID. See
[docs/LOCAL_SIGNING.md](docs/LOCAL_SIGNING.md).

Compile the isolated Mac target without signing or running it:

```sh
xcodegen generate
CC="$PWD/Scripts/xcode-clang-wrapper.sh" xcodebuild \
  -scheme SugarmanMacDeviceTest \
  -destination 'generic/platform=macOS' \
  -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO SDK_STAT_CACHE_ENABLE=NO
```

See [the macOS Device Test guide](docs/MACOS_DEVICE_TEST.md) before any signed
launch, private import, scan, or connection.

The developer probe is a separate scheme and bundle identifier
`app.sugarman.probe`:

```sh
xcodegen generate
CC="$PWD/Scripts/xcode-clang-wrapper.sh" xcodebuild \
  -scheme SugarmanProbe \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Building the probe does not authorize installing it or contacting a sensor.
Follow [the bounded probe guide](docs/V3_DEVELOPER_HANDOVER_PROBE.md).

P0/P1 evidence lab (private captures stay gitignored):

- [docs/P0_INVENTORY.template.md](docs/P0_INVENTORY.template.md)
- [docs/P1_CAPTURE_RUNBOOK.md](docs/P1_CAPTURE_RUNBOOK.md)
- [docs/EVIDENCE_STORAGE.md](docs/EVIDENCE_STORAGE.md)

Redacting HCI analyzer (synthetic fixtures in tests; private dumps stay gitignored):

```sh
python3 Scripts/analyze_btsnoop.py private-evidence/hci/btsnoop_hci.log
```

Governance check (also run in CI):

```sh
python3 Scripts/check_governance.py
```

## Upstream references

This repository tracks two upstream projects as pinned Git submodules rather
than vendoring their histories into Sugarman:

- `upstream/xdripswift` — iOS/Swift reference implementation
- `upstream/Juggluco` — Android/reference implementation for sensor behaviour

They are reference sources, **not** Xcode or Swift package build dependencies.
Do not add either path to a target, do not symlink them into the app, and do
not ship Android `.so` / `.aar` / APK binaries.

Clone with the references included:

```sh
git clone --recurse-submodules git@github.com:seichris/sugarman.git
```

For an existing clone:

```sh
git submodule update --init --recursive
```

See [the upstream policy](docs/UPSTREAMS.md) before copying or adapting code.
The Mainland GS3 plan is
[docs/MAINLAND_GS3_IOS_IMPLEMENTATION_PLAN.md](docs/MAINLAND_GS3_IOS_IMPLEMENTATION_PLAN.md).
