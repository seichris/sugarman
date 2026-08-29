# Private evidence-storage policy

Hardware captures, APKs, and identifying sensor data stay **out of Git**.
This policy is operational, not a legal opinion.

## What never goes in this repository

- Official or third-party APKs, DEX, `.so`, `.aar`, or vendor SDKs
- Credentials, tokens, cookies, account passwords, and Keychain dumps
- Full UDI strings, full serial numbers, and unredacted package photographs
  that expose unique identifiers
- Embedded key bytes, registration tokens, and cipher key material
- Raw BLE/HCI captures that include authentication payloads
- LLM transcripts used as if they were implementation specifications

`.gitignore` already excludes `private-evidence/`, `*.apk`, `*.so`, `*.aar`,
and similar patterns. Do not force-add them.

## Private corpus layout (local only)

Keep a directory **outside** this Git worktree, for example:

```
~/Documents/sugarman-private-evidence/
  inventory.md          # redacted-in-git version may be summarized
  apk/                  # hash only is recorded in Git
  hci/                  # Android HCI snoop, encrypted at rest if possible
  ios-gatt/             # read-only diagnostic notes
  photos/               # package photos
  hashes.sha256
```

Record in the private inventory (P0): package UDI/GTIN/SKU/lot/expiry with
full serials; Data Matrix and NDEF text; sensor state; official app
package/version/signer/APK SHA-256; account region as visible to the owner;
phone models and OS versions; visible firmware/hardware/manufacturer.

## What may go in Git

- Redacted serials (for example first/last character plus length)
- Sanitized Data Matrix / NDEF fixtures with unique identifiers removed
- Advertisement/GATT maps with payloads truncated or hashed
- Protocol-identification reports that quote lengths, states, and hashes
- Provenance records that name source paths and blob SHAs, not secrets

Fixtures derived from upstream source rather than hardware must be marked
GPL and recorded in the provenance registry.

## Diagnostic captures inside the app

Raw HCI/BLE capture, if added later, is a separate development mode:

- disabled by default;
- explicitly enabled by a developer setting;
- encrypted locally;
- automatically deleted after seven days;
- never included in production unified logs.

User-generated support bundles must be redacted and must not contain
credentials, account IDs, raw packets, full serials, or glucose history
unless the user explicitly selects a data export.

## Retention

Private evidence is retained only as long as needed for the P0–P5 gates and
then deleted or archived offline under the operator's control. Sugarman the
app retains session and glucose history locally until the user deletes it;
that user data is not this private engineering corpus.
