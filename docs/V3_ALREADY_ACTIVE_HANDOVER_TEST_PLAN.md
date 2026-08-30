# V3 already-active handover test plan

## Purpose and current status

This is the first bounded iPhone validation for one owner-controlled, already
active Mainland GS3. It is designed to prove authentication, one effective-data
request, live notification decoding, and official Android-app handback while
excluding activation and every lifecycle mutation.

The developer-only probe is **implemented and host-verified, but has not been
installed or physically run**. Its code and material boundary are documented in
[`V3_DEVELOPER_HANDOVER_PROBE.md`](V3_DEVELOPER_HANDOVER_PROBE.md). The normal
`Sugarman` application remains read-only; only the separate `SugarmanProbe`
target can express the bounded writes below. No artifact covered by this
document is currently authorized for installation or sensor traffic.

## Implemented boundary before the physical gate

The separate `SugarmanProbe` target exposes only these operations:

1. connect to the explicitly selected owned peripheral;
2. discover the already observed FF30/FF31/FF32 characteristics;
3. subscribe to FF31 notifications through CoreBluetooth;
4. send exactly one encrypted `0xE2` authentication frame to FF32;
5. only after the exact observed decrypted authentication acceptance
   `command 0xE2, code 0x01, detail 0x00`, send exactly one encrypted `0x39`
   effective-data request from the imported start index through `0xFFFF`;
6. decode FF31 `0x39` batches and `0x32` live notifications with the
   offline-reviewed decoder;
7. display redacted state plus the latest value and disconnect after five
   unique live `0x32` indexes or a seven-minute cap.

The target contains no builders or cases for `0x35`, binding, activation,
reset, secret-key, expiry/lifecycle, firmware, or arbitrary raw writes. The
transport API must accept only typed allowlisted probe actions, enforce one
in-flight command, cap the session duration, and fail closed on every unknown
response.

Owner-specific address, account ID, registered block, and cryptographic inputs
must be imported only after installation through a developer-only local channel
into device-only Keychain storage. They must never be compiled or copied into
the app bundle, committed to Git, included in launch arguments, or emitted to
unified logs/crash reports; transient buffers should be cleared where practical.
The distinct fixed algorithm-glucose key/IV are not embedded. They use the same
post-install private import path, with the private source configuration never
packaged or committed.

## Host acceptance gate

Before producing a device artifact:

- all `swift test` and governance checks pass;
- synthetic tests cover authentication, `0x39`, `0x32`, checksum failures,
  timeouts, duplicate notifications, exact five-reading completion, and unknown
  commands;
- an independent reviewer confirms the outbound command enum contains only
  `0xE2` and `0x39` for this target;
- a build-product string/byte audit finds no forbidden command builder and no
  owner secret in the app bundle, symbols, generated files, or logs;
- the exact source commit, signed app manifest SHA-256, signing team, bundle ID,
  iPhone serial, iOS version, and sensor state are recorded; and
- the owner gives fresh confirmation quoting those exact identifiers and the
  bounded action.

Building is not authorization to install. Installing is not authorization to
connect. The final confirmation must cover both if both are intended.

## Physical procedure after fresh confirmation

1. In the official Android app, record a current value, trend, sensor state,
   reading timestamp, and successful reconnect baseline privately.
2. Stop HCI logging unless a new owner-approved capture is required. Release the
   sensor by disabling Android Bluetooth; do not unbind, log out, clear app data,
   or change sensor settings.
3. Install and launch only the confirmed iPhone artifact. Select the owned
   sensor explicitly. Do not enable any activation or onboarding action.
4. Run one bounded probe. Abort automatically if authentication is rejected, an
   unexpected command would be needed, frame validation fails, or the timeout
   expires.
5. Require at least five consecutive approximately one-minute iPhone readings.
   Compare timestamp/index, mmol/L after documented rounding, reading age, and
   the known flat trend case against the official app's private record. Do not
   infer meanings for unverified trend/state codes.
6. Disconnect Sugarman and terminate the probe. Re-enable Android Bluetooth and
   require the official app to reconnect and resume values without re-binding,
   reactivation, lost history, or changed remaining sensor life.
7. If handback does not occur within the predefined timeout, keep Sugarman
   disconnected, restart only the official app/Bluetooth through ordinary user
   controls, preserve redacted diagnostics, and stop. Do not send recovery,
   reset, activation, or guessed commands.

## Pass criteria

- exactly one `0xE2` and one `0x39` application write occurred; no forbidden
  command occurred;
- FF31 notifications pass length, command, count, exact-size, and checksum
  validation before values enter the domain/store;
- at least five consecutive decoded values align with official-app values and
  indexes/timestamps without unexplained discrepancy;
- stale/disconnected state is shown whenever a current validated notification
  is absent;
- Sugarman disconnects within the time cap; and
- the official Android app resumes the same active sensor without binding or
  activation changes.

Any unexplained value mismatch, unexpected state, extra write, handback failure,
or requirement for a lifecycle command fails the gate.

## After this gate

A pass supports only same-owner handover for this sensor/app/library
combination. Next gates are background/locked-screen reconnect, a full sensor
run, a second lot, broader trend/state mapping, and finally a separately
confirmed unopened-sensor activation. Fresh activation must not reuse this
handover authorization.
