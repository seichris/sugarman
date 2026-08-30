# Hardware-readiness code review

- Reviewed target and remediation base: `e127bffd23db9a1cf4c6ca3f68b16412fc8b8cdf`
- Local remediation branch: `fix/hardware-readiness` (uncommitted working tree)
- Review date: 2026-08-29
- Scope: all Sugarman application, package, diagnostics, persistence, tests,
  governance, provenance, and build configuration implemented through issue #6
- Review profile: deep, sequential, `P0/P1/P2`
- Physical hardware used during review: none

## Outcome

The reviewed target is the governance foundation and software portion of the
P0/P1 evidence lab. It is not yet a GS3 glucose collector: authentication,
binding, decoding, handover, activation, and HealthKit glucose writes remain
intentionally unimplemented until physical P1/P2 evidence exists.

An already-active owned Mainland GS3 is the correct first physical sensor, but
the Android official-app HCI capture comes before a Sugarman handover. All
source findings below are remediated in this working tree. That makes the next
step the private P0 inventory and official-app Android HCI capture, followed by
the bounded Sugarman read-only iOS probe. It does not make authentication,
handover, glucose collection, or activation ready.

## Finding ledger

| ID | Severity | Finding | Remediation and status |
| --- | --- | --- | --- |
| HR-01 | P1 | The physical-iPhone target did not compile because the live camera delegate crossed Swift 6 actor isolation and called an optional callback without unwrapping it. | **Fixed:** a queue-confined capture engine owns AVFoundation/Vision and crosses to `MainActor` only for callbacks; CI now builds simulator and generic device. A narrow compiler-probe wrapper avoids Xcode 26.6's verbose-probe pipe stall without changing real compiler invocations. |
| HR-02 | P1 | Six bytes by length alone, or a response paired with the last unrelated UUID, could falsely prove the P1 authentication-address source. | **Fixed:** Swift and Python analyzers correlate peer, connection handle, ATT read handle, characteristic declaration/UUID, and exact normal/reversed bytes. Six-byte length alone remains `notFound`. |
| HR-03 | P1 | Disabling the probe entered reconnect backoff instead of cancelling the peripheral connection. | **Fixed:** operator disconnect uses transport cancellation, stops scanning, cancels the peripheral, and is available explicitly in the UI. |
| HR-04 | P1 | Core Bluetooth operations had no deadlines, pending continuations survived disconnects, optional DIS fields were mandatory, and per-device values were not reset. | **Fixed:** operations have 15-second deadlines; disconnect/timeout completes pending work; evidence resets per peer; callbacks match the connected peer and pending operation; only present readable DIS fields are read. |
| HR-05 | P1 | Receipt time, backfill, unknown quality/lifecycle/source, and reconnecting states could make non-current glucose appear current. | **Fixed:** current requires fresh sensor and receipt timestamps, live source and lifecycle, subscribed transport, and `ok` quality. Unknown persisted source decodes fail-safe. |
| HR-06 | P1 | SwiftData dropped lifecycle/index/device-evidence fields and silently fell back to volatile memory on persistent-store failure. | **Fixed:** every domain field is persisted, session update is supported, integer ranges are checked, an on-disk reopen regression compares full values, and bootstrap failure returns a visible fail-closed store. |
| HR-07 | P1 | Choosing a synthetic demo deleted all local user data without a transaction or confirmation. | **Fixed:** demos use a separate in-memory store and an explicit exit restores the untouched persistent store. |
| HR-08 | P2 | Active-session glucose, connection/lifecycle state, history, and workout overlap were not consistently scoped to the selected session. | **Fixed:** selection, currentness, samples, fueling, workouts, and overlap use one resolved session ID; workouts are persisted with optional session scope. |
| HR-09 | P2 | Store errors were swallowed and some UI paths reported success after failed writes or deletion. | **Fixed:** mutations throw, missing deletes fail, refresh assigns an atomic snapshot and preserves the previous one on error, and app surfaces storage/action failures. |
| HR-10 | P2 | Shareable diagnostic output could include unique Bluetooth local names and stable CoreBluetooth peer UUIDs. | **Fixed:** every exported name becomes a length marker and the peer identifier becomes `redacted-peer`; raw discovery identity remains transient on device. |
| HR-11 | P2 | Unsupported BTSnoop versions/datalinks and trailing truncation were accepted silently. | **Fixed:** both analyzers require version 1 and H4 datalink 1002 and reject malformed/trailing records. |
| HR-12 | P2 | Concatenated GS1 parsing could interpret AI-looking digits inside a variable lot or serial as a new field. | **Fixed:** variable fields end only at FNC1/group separator or input end; a missing required separator fails closed. |
| HR-13 | P2 | A late camera-permission callback could start capture after the scanner was dismissed. | **Fixed:** the capture engine records dismissal on its session queue and refuses late starts. |
| HR-14 | P2 | `OwnerAccountID`'s public synthesized decoder bypassed manual validation. | **Fixed:** decoding uses the same bounded no-email validator as direct user input. |

## Safe physical sequence after remediation

1. Complete the private P0 inventory without sending sensor commands.
2. Use the official Chinese Android app with the already-active owned sensor to
   capture advertisements, connection establishment, service discovery, and
   the first authentication exchange through normal Android HCI snoop tooling.
3. Keep the raw capture private. Run the corrected analyzer offline and require
   an exact, reproducible address-byte match rather than a length match.
4. Build and sign Sugarman for the owned iPhone. Only after the official app has
   released the sensor, run the bounded read-only scan/connect/DIS probe.
5. Explicitly disconnect Sugarman and verify the official app reconnects with
   ownership and remaining sensor life unchanged.
6. Identify P2 as V1.20/RC4, V3/AES, or unknown offline. Do not try multiple
   ciphers against the live sensor.
7. Implement the offline codec only for the physically supported variant, then
   proceed to the separately gated same-owner handover.

## Licence and provenance state

The reviewed tree is `GPL-3.0-or-later`, has no upstream project in an Xcode or
Swift package target, includes no Android/vendor binary, commits no private HCI
evidence, and contains no Core Bluetooth `writeValue` call. No GS3 codec or
adapted upstream protocol implementation exists yet. Any later Juggluco or
xdripswift adaptation must add exact file/commit/blob provenance, preserve
copyright and GPL notices, and ship corresponding source. TestFlight/App Store
distribution remains subject to the written legal review documented elsewhere
in this repository.

## Verification

The base commit had 104 passing package tests and a failing generic-device
build. The remediated working tree passes all of the following local gates:

- `python3 Scripts/check_governance.py`: passed.
- `python3 Scripts/analyze_btsnoop.py --self-test`: passed.
- `swift test --enable-swift-testing`: 119 tests in 12 suites passed.
- `bash -n Scripts/xcode-clang-wrapper.sh`: passed.
- `python3 -m json.tool Apps/Sugarman/Localizable.xcstrings`: passed.
- `xcodegen generate` followed by a project-file diff check: passed with no
  generated-project change.
- Static checks for Core Bluetooth writes, swallowed store errors, unresolved
  merge files, and whitespace errors: passed.
- Unsigned generic iOS Simulator Debug build: passed.
- Unsigned generic iOS device Debug build: passed.

The iOS builds set `CC` to the narrow compiler-discovery wrapper in
`Scripts/xcode-clang-wrapper.sh`. It removes `-v` only from Xcode 26.6's
`clang -E -dM ... /dev/null` probe, whose verbose stderr deadlocked the local
build service, and forwards real compile/link invocations unchanged. GitHub CI
has not run because this branch is local and unpushed.

This remains source/build evidence only. No sensor, phone radio, account, APK,
HCI capture, authentication payload, or other physical/private evidence was
accessed during review or remediation.
