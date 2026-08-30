# Third-party software and provenance

Sugarman is licensed under **GPL-3.0-or-later**. This file records third-party
material that is, or may later be, combined with Sugarman. It is an engineering
record, not a licence opinion.

## Sugarman

| Field | Value |
| --- | --- |
| Project | Sugarman |
| URL | https://github.com/seichris/sugarman |
| Licence | GPL-3.0-or-later |
| SPDX | `GPL-3.0-or-later` |
| Corresponding source | Git tags for every distributed build; see README |

New Sugarman files carry an SPDX identifier and a copyright line:

```
SPDX-License-Identifier: GPL-3.0-or-later
Copyright (C) 2026 Sugarman contributors
```

## Reference-only upstreams (not build dependencies)

These Git submodules exist so reviewers can inspect source next to Sugarman.
They are **not** linked, compiled, bundled, or shipped with the iOS app.
CI fails if an Xcode or Swift package target references `upstream/`, `.so`,
`.aar`, or APK files as resources.

| Path | Project | Pinned revision | Published licence text | Role in Sugarman |
| --- | --- | --- | --- | --- |
| `upstream/xdripswift` | [xdripswift](https://github.com/xdripswift/xdripswift) | `69eb88330a22e7d9969ee94ec6fa87072367fd2e` | GPL version 3 (see `upstream/xdripswift/LICENSE`) | iOS BLE/background/HealthKit design evidence |
| `upstream/Juggluco` | [Juggluco](https://github.com/johannesjo/Juggluco) | `11d016eb3aeffe77e86d9522f5192e83790b5a21` | GPL version 3 (see `upstream/Juggluco/LICENSE.txt`) | Android GS3 behaviour/protocol evidence |

Juggluco's nested `libjuice` pin is documented in the implementation plan.
Juggluco's Android build instructions refer to third-party `.so` inputs
extracted from an APK. Those binaries are **not** Sugarman dependencies and
must never be added to this repository's application targets or release
archives.

## Owned vendor-app interoperability observation

An owner-controlled copy of the official Mainland Android app and its native
library were inspected as proprietary-or-unknown-licence evidence. They are not
linked, copied, bundled, or redistributed with Sugarman. Separately authored
GPL Swift source records only approved functional interoperability facts,
public-standard algorithms, and one fixed non-account-specific protocol
constant required for the offline V3 authentication transform. The exact
evidence hashes, source locations, destination files, and scope limits are in
[`docs/V3_AUTH_SOURCE_MAP_2026-08-30.md`](docs/V3_AUTH_SOURCE_MAP_2026-08-30.md)
and [`docs/provenance/registry.json`](docs/provenance/registry.json).

This is a provenance record, not a conclusion that vendor code or binaries are
GPL-compatible and not approval for App Store/binary distribution. Runtime IVs,
registration material, authentication IDs, account data, and device identifiers
remain private and are never committed.

## Apple system frameworks

The iOS app links only system frameworks provided by the SDK (SwiftUI,
Observation, CoreBluetooth, CoreNFC, HealthKit, SwiftData, Vision, and similar).
Those are used under Apple's SDK terms; they are not third-party source
adapted into this tree.

## How to obtain corresponding source

For any Sugarman binary you received:

1. Read the build's version/commit shown in Settings (or the Git tag named in
   the distribution notes).
2. Fetch https://github.com/seichris/sugarman at that tag, or use the source
   archive attached to the GitHub Release.
3. The corresponding source includes this repository's application code,
   `Package.swift`, `project.yml`, Xcode project, test sources, and the scripts
   under `Scripts/` and `.github/workflows/` that control the build.
4. `upstream/` is provided for research; it is not required to rebuild the
   Sugarman app binary and is not part of the application target.

If you received a binary without a tag, contact the distributor and request
the corresponding source as GPLv3 requires.

## Adaptation workflow

No Juggluco or xdripswift source has been copied or translated into Sugarman
in milestone M0. Before any later adaptation:

1. Add a provenance record using [docs/provenance/TEMPLATE.md](docs/provenance/TEMPLATE.md)
   and [docs/provenance/schema.json](docs/provenance/schema.json).
2. Preserve upstream notices and add a modification date/author.
3. Keep the adaptation in a narrow commit.
4. Do not copy implementation text from an LLM transcript.
5. Do not commit APKs, credentials, full UDI/serials, tokens, runtime/account
   keys, IVs, or other owner-specific secret bytes. A fixed, non-owner-specific
   interoperability constant may be recorded only after scoped legal/provenance
   approval, in one authoritative implementation location, with the vendor
   binary excluded from every build and distribution artifact.

Machine-readable registry: [docs/provenance/registry.json](docs/provenance/registry.json).
