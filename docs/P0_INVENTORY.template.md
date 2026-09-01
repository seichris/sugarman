# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Sugarman contributors

# P0 physical inventory template

Copy this file **out of Git**. Fill it locally under gitignored `private-evidence/`
(or `~/Documents/sugarman-private-evidence/`). Do **not** commit the filled copy.

**Never put in Git:** APKs, `.so` / `.aar` / DEX, tokens, cookies, passwords,
Keychain dumps, full serials, full UDI strings, unredacted package photographs,
runtime/account keys, IVs, registration tokens, authentication IDs, or raw
authentication payloads.

See [EVIDENCE_STORAGE.md](EVIDENCE_STORAGE.md) and
[P1_CAPTURE_RUNBOOK.md](P1_CAPTURE_RUNBOOK.md).

## Sensor

| Field | How to record | Value |
| --- | --- | --- |
| Inventory ID | Local label only (for example `gs3-lot-a-unopened`) | |
| Package photos path | **Local filesystem path only.** Do not commit photos. | |
| UDI | Full UDI stays local. In any Git-bound summary, redact. | |
| GTIN / SKU | From package / Data Matrix. | |
| Lot | Package lot. | |
| Expiry | Package expiry. | |
| Redacted serial | First/last character plus length, or last four (`…ABCD`). Never the full serial in Git. | |
| Data Matrix text (sanitized) | Unique identifiers removed or replaced. Full payload stays local. | |
| NDEF summary | Record types and sanitized text. Full NDEF stays local. | |
| Sensor state | `unopened` / `active` / `expired` / `bound` | |

## Official app (local hash only)

Record package, version, signer, and APK SHA-256 **locally**. Do not commit the
APK, signer certificate files, or the hash file if it embeds a full path to a
secret store. A one-line package/version note without credentials is enough for
a later redacted P1 report.

| Field | Value (local) |
| --- | --- |
| Package name | |
| Version name / code | |
| Signer fingerprint | |
| APK SHA-256 | |
| Storage path (local only) | |

## Account and phones

No credentials, cookies, SMS codes, or account passwords.

| Field | Value |
| --- | --- |
| Account region (as visible to the owner) | |
| Android model / OS | |
| iPhone model / iOS | |
| Visible sensor firmware / hardware / manufacturer | |

## Sign-off

P0 exit: inventory complete and sanitized fixtures exist. Sugarman has sent
**no** BLE command.
