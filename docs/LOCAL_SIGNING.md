# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors

# Local device signing

Physical iPhone builds for NFC, Bluetooth, and HealthKit require an Apple
Developer **Development Team** selected in Xcode. Simulator builds in CI use
`CODE_SIGNING_ALLOWED=NO` and do not need a team.

The isolated macOS Device Test also compiles unsigned, but a physical Bluetooth
run needs a locally signed Mac app with the Bluetooth, sandbox, user-selected
read-only file, and shared sensor-owner App Group entitlements. A compile-only
build must not be launched as a substitute for that signing check.

## Identifiers

| Item | Value |
| --- | --- |
| Bundle identifier | `app.sugarman.ios` |
| Device-test bundle identifier | `app.sugarman.ios.devicetest` |
| Mac Device Test bundle identifier | `app.sugarman.macos.devicetest` |
| Apple Developer team | WEB3 team, identifier **TBD** |
| `DEVELOPMENT_TEAM` in Git | Empty (`project.yml` / Xcode project keep it blank) |

Do **not** invent or commit a team ID. When the WEB3 team ID is known, set it
locally in Xcode (or a gitignored `local.xcconfig` / `Secrets.xcconfig`). Do
not paste it into `project.yml` until that is an intentional, reviewed change.

## What device signing unlocks

- Core NFC NDEF reading (Near Field Communication Tag Reading / NDEF format)
- HealthKit permission prompts (glucose **writes remain disabled** until
  physical parity gates pass)
- Installing the app on a physical iPhone

The normal `Sugarman` scheme now links the production provisioning and
scan-only products, but every process begins disconnected: private import,
scan-only lookup, and foreground connection are separate explicit UI gates.
`SugarmanDeviceTest` additionally links the isolated link-loss test surface.
Both App IDs must be assigned to `group.app.sugarman.sensor-owner`. A
development profile for a physical test must be constrained to the exact
owner-confirmed device. Building, installing, launching, private import,
scan-only lookup, and connecting are separate approval gates.

`SugarmanMacDeviceTest` is a separate macOS application and Keychain namespace.
Its App ID must also be assigned to `group.app.sugarman.sensor-owner`. That
lease coordinates only processes on the same Mac; it does not exclude an
iPhone or Android owner, so the Mac UI requires an additional process-local
release confirmation before scan and arm. Building, signing, launching,
private import, scan-only provisioning, and arming are separate approval gates.

## Local workflow

1. Open `Sugarman.xcodeproj` in Xcode.
2. Select the Sugarman target → Signing & Capabilities.
3. Choose your Development Team. Leave the bundle id `app.sugarman.ios`.
4. Confirm the NFC Tag Reading capability lists **NDEF** (not a generic tag
   command session).
5. Run on the physical iPhone. Simulator keeps NFC and live camera unavailable.

NFC and HealthKit entitlements are rejected at install time without a team.
That is expected for unsigned CI simulator builds.

## Core Bluetooth restoration identifier

The production `GS3ForegroundCoreBluetoothTransport` registers
`CBCentralManagerOptionRestoreIdentifierKey` as
`app.sugarman.ios.gs3.managed-session`, matching Info.plist `bluetooth-central`.
After an explicit user opt-in, the app reconstructs that manager on launch,
accepts only the provisioned known peripheral from `willRestoreState`, and
rediscovers, resubscribes, authenticates, and requests durable-overlap history.
Device Test does not opt into restoration. Background relaunch and lock-screen
behavior still require a separately confirmed physical test; an unsigned build
is compile evidence only.

`DEVELOPMENT_TEAM` is empty in Git (`Config/DevelopmentTeam.xcconfig` and
`project.yml`). Fill it locally; do not invent or commit a team ID.
