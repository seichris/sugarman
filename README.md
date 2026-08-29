# Sugarman — Glucose monitoring for endurance athletes

Sugarman is a native Swift/SwiftUI iOS app that gives endurance athletes a
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
- No live sensor commands (authentication write, binding mutation, activation,
  reset, expiry, secret-key, or other lifecycle writes) until physical gates
  P1 and P2 in the
  [implementation plan](docs/MAINLAND_GS3_IOS_IMPLEMENTATION_PLAN.md) pass.
- No GS3 codec/cipher implementation in this milestone.

## Repository layout

| Path | Role |
| --- | --- |
| `Sources/SugarmanDomain` | Pure domain types and product copy |
| `Sources/GS3Protocol` | Protocol interfaces only; every variant fails closed |
| `Sources/GS3Transport` | BLE state machine and testable central abstraction |
| `Sources/SensorOnboarding` | Bounded package/NDEF parser interfaces |
| `Sources/AccountBinding` | Manual legitimate owner ID only |
| `Sources/SugarmanStore` | Repository protocols, in-memory store, optional SwiftData |
| `Sources/SafetyEngine` | Stale/disconnected/warm-up/error/expiry evaluator |
| `Sources/Integrations` | HealthKit/export interfaces; HealthKit writes disabled |
| `Sources/SugarmanDiagnostics` | Read-only GATT probe, disabled by default |
| `Apps/Sugarman` | SwiftUI iOS application shell |
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
```

Or open `Sugarman.xcodeproj` in Xcode and run the `Sugarman` scheme on an iOS 26
simulator. Device builds need an Apple Developer team; the bundle identifier
placeholder is `app.sugarman.ios`.

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
