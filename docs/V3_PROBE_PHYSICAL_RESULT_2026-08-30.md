# GS3 V3 developer-probe physical result — 2026-08-30

## Outcome

The first bounded developer-probe run on one owned, already-active Mainland
GS3 **failed closed before any glucose value was validated**. The iPhone app
connected to the explicitly selected expected peripheral, then displayed the
generic Swift error `GS3DeveloperProbe.V3ProbeError error 4` and returned to
its idle scan state. The run was not retried.

The official Chinese Android app subsequently reconnected to the same active
sensor and resumed fresh data. The owner-reported post-run control point was:

- displayed update time `20:02` in the owner-local Asia/Singapore test context;
- `8.8 mmol/L`; and
- an arrow visually pointing right-down.

The arrow wording is a visual observation only. This record does not map it to
a native trend code or physiological meaning.

## Exact authorized artifact and boundary

- Pull request: `#13`
- Source commit: `e0e332cee3dd7acf725262ba9da6bb52ddb59c94`
- Signed-app manifest SHA-256:
  `1c15cbfcbde10135a0f93bd167fd0af06b807f51015f764feb75540005c16855`
- Bundle ID: `app.sugarman.probe`
- Test platform: one owned iPhone on iOS `26.6.1`
- Sensor: one owned, already-active Mainland GS3

The stable iPhone serial, signing identity, sensor identity, imported material,
and import-file hash remain private. The authorization allowed one connection,
FF31 subscription, at most one typed `0xE2` authentication write, and—only
after exact authentication acceptance—at most one typed `0x39` request. It
forbade retry, reconnect, activation, binding, reset, firmware, lifecycle,
HealthKit, and every other sensor write.

## What is verified and what is not

### Physical observations — high confidence

- The expected peripheral was discoverable and explicitly selected.
- CoreBluetooth connected before the app failed closed.
- The probe returned to its idle state and did not automatically retry or
  reconnect.
- The official Android app later reconnected and displayed the fresh control
  point above.

### Source evidence — high confidence

- The exact PR source permits no more than one typed `0xE2` effect and one
  typed `0x39` effect.
- Its unknown/malformed notification path disconnects without a retry.
- `V3ProbeError` conformed only to `CustomStringConvertible`, not
  `LocalizedError`, so `error.localizedDescription` discarded the useful
  source message and produced the generic UI text.
- The exact build retained no packet/state trace, so it cannot reveal the
  received frame class or whether the conditional `0x39` write was invoked.

### Inference — medium confidence

The displayed numeric error is consistent with the source
`unexpectedNotification` case. It is not sufficient evidence to determine
whether the triggering FF31 value was an early/duplicate control response, a
data notification in an unexpected state, a malformed frame, or a frame that
failed decryption with the imported inputs.

### Not verified by this run

- Actual over-the-air or controller-level application-write counts; there was
  no contemporaneous iPhone HCI capture.
- Authentication acceptance or rejection.
- Whether a `0x39` request reached the sensor.
- Any iPhone glucose decode, cross-app value parity, or five-reading sequence.
- Background reconnect, another sensor lot, or fresh activation.

## Payload-free comparison with the official Android capture

A fresh private re-analysis of the canonical owned Android HCI capture grouped
the traffic into four connections and decrypted it only long enough to emit
allowlisted command classes and byte counts. No payload, address, owner value,
key, IV, or identifier was printed or committed.

All four official connections had the same relevant order:

1. one 38-byte `0xE2` request;
2. one exact five-byte authentication acceptance;
3. a series of paired device-information request/responses;
4. one seven-byte `0x39` request;
5. one five-byte `0x39` acknowledgement; and
6. effective and/or live data.

The canonical capture contains no live-data notification before authentication
acceptance. The first connection also contains the already documented official
activation flow; the developer probe intentionally does not implement it.

PR #13 sends `0x39` immediately after authentication acceptance and omits the
intervening device-information queries. The capture proves that ordering
difference, but it does **not** prove those queries are required. Adding them
would widen the application-write surface and is therefore deferred until a
diagnostic follow-up identifies a concrete need.

## Follow-up decision

Do not rerun the PR #13 artifact. The next candidate must retain the two-command
maximum and add only:

- payload-free inbound classification, byte count, state-before/state-after,
  and authorized-command counters;
- separate CoreBluetooth write-call and write-acknowledgement evidence;
- a clear localized failure explaining the unexpected class and state;
- an in-memory, manually shareable redacted trace with no identifiers, packet
  bytes, private material, glucose values, or record indexes; and
- an explicit one-in-flight write gate so a conditional `0x39` is never invoked
  until the preceding CoreBluetooth write callback succeeds.

Host verification and review of that follow-up do not authorize another
physical run. A new source commit, signed manifest, device/environment record,
and fresh owner confirmation are required first.
