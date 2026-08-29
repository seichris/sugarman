# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors

# P1 capture runbook (owned hardware only)

Use only sensors, phones, packaging, accounts, and app copies Chris already
owns. Sugarman must not send a live sensor command until P1 and P2 have
evidence-backed answers.

Store raw material under gitignored `private-evidence/` (or
`~/Documents/sugarman-private-evidence/`). See
[EVIDENCE_STORAGE.md](EVIDENCE_STORAGE.md) and
[P0_INVENTORY.template.md](P0_INVENTORY.template.md).

**Out of scope (do not do these):**

- bypassing certificate pinning or cloud login
- scraping the official app for credentials, tokens, or account IDs
- generating or trying arbitrary account IDs
- Frida / MITM / unofficial debug builds of the vendor app
- authentication writes, binding mutation, activation, reset, or `writeValue`
  from Sugarman
- a live-sensor “try RC4 then AES” fallback

## What P1 must answer

Juggluco builds initial authentication from **six bytes derived from the
Android-visible Bluetooth device address**. CoreBluetooth exposes an opaque
peer UUID, not that MAC.

Find a **legitimate, readable** source for those six bytes, or **stop**:

| Candidate | How to check | Result |
| --- | --- | --- |
| Package / UDI / Data Matrix | P0 payload, sanitized in Git | |
| NFC NDEF | Core NFC NDEF read only | |
| Advertisement | Android HCI snoop of official-app ads | |
| Device Information (DIS) | iOS read-only probe: manufacturer / model / firmware / hardware / software. Do not log serials or frame bytes. | |
| Other documented-readable characteristic | Only if the characteristic is readable without a write | |
| None | Stop. Seek vendor documentation. Do not guess a transform from the CoreBluetooth UUID. | |

Exit: a redacted advertisement/GATT map plus a reproducible six-byte source,
**or** an explicit stop.

## What P2 must answer

Compare the **first official-app authentication exchange** (from the Android
capture) against the pinned Juggluco codec **offline**. Do not probe a live
sensor with both ciphers.

| Hypothesis | Evidence |
| --- | --- |
| **V1.20 / RC4** | Capture matches Juggluco’s authentication, checksum, and command family after decoding with the pinned implementation. |
| **V3 / AES** | Frame lengths and state transitions do not match the pinned RC4 path and corroborate an AES-OFB / native-library path. |
| **Unknown** | Neither hypothesis is supported well enough. |

Write a short local report: device/firmware, capture hashes, redacted frame
lengths (not raw auth payloads), method, expected vs observed, confidence.

If V3: **stop** the RC4 implementation milestone. Do not ship an Android
`.so`. Inspect the owned APK only under the legal/provenance rules; do not
commit it.

## Android — official app, HCI snoop, bugreport

Prerequisite: P0 inventory for an **already-active** owned sensor. Force-stop
or background other CGM apps so only the official Chinese app is the central.

### Enable Bluetooth HCI snoop (normal Developer options)

1. On the owned Android phone: **Settings → About phone** and tap **Build
   number** until developer mode is on (stock path; OEM labels vary).
2. **Settings → System → Developer options** (or the OEM equivalent).
3. Turn on **Enable Bluetooth HCI snoop log** (sometimes “Bluetooth HCI snoop
   log”). Use this official toggle only.
4. Toggle Bluetooth off and on once so the snoop file starts cleanly.

### Capture advertisements and the first auth exchange

1. Confirm the owned sensor is already active and bound to the owner’s
   legitimate account. Do not activate a fresh sensor for P1.
2. Start the official app the owner already uses. Let it scan, connect, and
   complete its **first authentication exchange**.
3. Leave it connected long enough to see advertisements, connection,
   service discovery, and that first auth — then disconnect or force-stop the
   official app so the peripheral is free for iOS later.
4. Do not intercept TLS, disable pinning, or dump the official app’s private
   storage.

### Pull a bugreport and extract the snoop log

1. In Developer options, generate a **bug report**, or from a trusted cable:

   ```sh
   adb bugreport private-evidence/android/bugreport
   ```

2. The HCI snoop is typically inside the bugreport as
   `FS/data/misc/bluetooth/logs/btsnoop_hci.log` (path varies by OEM/Android
   version). Copy **only** that log (and a note of the path) into
   `private-evidence/hci/`.
3. Delete or encrypt the full bugreport if it contains accounts, SMS, or
   other unrelated personal data.

### Redact before any Git-bound note

Keep in private-evidence (gitignored):

- raw `btsnoop_hci.log`
- APK (if hashed for P0; never commit)
- full serials

Safe to summarize later in Git:

- advertised local name (if not unique)
- 16-bit service UUIDs
- DIS field **names** and firmware/model **strings** (no serial)
- frame **lengths** and GATT handle/UUID map
- hashes of the capture file

Never commit raw authentication payloads, tokens, or full serials.

## iOS — Sugarman read-only diagnostic

Do this **after** the official app has released the sensor.

1. Set a Development Team in Xcode (see [LOCAL_SIGNING.md](LOCAL_SIGNING.md)).
   Bundle id stays `app.sugarman.ios`. Do not invent a team ID.
2. Install Sugarman on the owned iPhone.
3. Privacy → enable **Read-only Bluetooth probe** (default **off**). Simulator
   leaves this disabled.
4. Scan. Note each peripheral’s **name**, CoreBluetooth **identifier UUID**,
   and **RSSI**. Do not log advertisement bytes or serials.
5. Connect to the owned sensor only. Discover services. Read **Device
   Information** characteristics that are documented as readable
   (manufacturer, model, hardware, firmware, software). Skip serial display.
6. Disconnect. Sugarman must not write CCCD as a sensor command channel, must
   not call `writeValue`, and must not authenticate, bind, activate, or reset.

If the six address bytes are not in package, NFC, advertisement, DIS, or
another readable field, **stop**.
