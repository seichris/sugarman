# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors

# Local device signing

Physical iPhone builds for NFC, Bluetooth, and HealthKit require an Apple
Developer **Development Team** selected in Xcode. Simulator builds in CI use
`CODE_SIGNING_ALLOWED=NO` and do not need a team.

## Identifiers

| Item | Value |
| --- | --- |
| Bundle identifier | `app.sugarman.ios` |
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

## Local workflow

1. Open `Sugarman.xcodeproj` in Xcode.
2. Select the Sugarman target → Signing & Capabilities.
3. Choose your Development Team. Leave the bundle id `app.sugarman.ios`.
4. Confirm the NFC Tag Reading capability lists **NDEF** (not a generic tag
   command session).
5. Run on the physical iPhone. Simulator keeps NFC and live camera unavailable.

NFC and HealthKit entitlements are rejected at install time without a team.
That is expected for unsigned CI simulator builds.
