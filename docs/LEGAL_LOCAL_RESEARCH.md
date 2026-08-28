# Lean legal note — local interoperability research

**This is an engineering note for local, owner-device work. It is not legal
advice and it is not a distribution opinion.**

## Scope of this note

This note covers **local interoperability research** on hardware, packaging,
accounts, and software copies that the operator already owns. It does **not**
authorize:

- App Store, TestFlight, or other external distribution;
- a conclusion that GPLv3 is compatible with Apple's developer agreements;
- scraping credentials from another app;
- bypassing certificate pinning, account ownership, device binding, sensor
  expiry, or other security controls;
- support for sensors the operator does not own.

A written legal review is required before external TestFlight or App Store
submission. That review must cover GPLv3/App Store compatibility,
corresponding-source delivery, cryptography/export, interoperability and
vendor terms, health-data privacy, athlete-wellness versus medical-device
claims, and the appropriate legal entity. See the implementation plan.

## Licence adopted before adaptation

Sugarman is licensed as `GPL-3.0-or-later` from milestone M0, **before** any
Juggluco or xdripswift code is copied, translated, or adapted. Adapting that
expression later means the distributed combined work must remain
GPL-compatible. Do not silently relicense adapted code.

## Interoperability research (engineering practice)

Local research on an owned Mainland GS3 sensor is intended to:

- identify advertised BLE services and documented-readable characteristics;
- parse packaging/NDEF the owner already has;
- compare official-app behaviour on an owned account and owned sensor;
- decide which protocol generation the physical device uses **before** any
  authentication or activation write is implemented.

M0 implements **no** live sensor command: no authentication write, binding
mutation, activation, reset, expiry, secret-key, or other lifecycle write.
The read-only diagnostic probe is disabled by default and has no write API.

If a legitimate source for required authentication inputs cannot be found in
package, NFC, advertisement, Device Information, or another readable field,
stop and seek vendor documentation rather than guessing.

## Binary and secret policy

Never add Android `.so` files, `.aar` files, APKs, or undocumented vendor
libraries to Sugarman. Extracting a file from an APK does not grant
redistribution permission. Private evidence handling is described in
[EVIDENCE_STORAGE.md](EVIDENCE_STORAGE.md).

## Product claims

User-facing copy must keep the athlete-fueling posture. Do not claim
diagnosis, treatment, insulin dosing, or that a fueling strategy is
clinically optimal.
