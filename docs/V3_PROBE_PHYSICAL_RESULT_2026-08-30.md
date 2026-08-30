# GS3 V3 developer-probe physical results — 2026-08-30

## Outcome

Three bounded developer-probe runs on one owned, already-active Mainland GS3
**failed closed before any iPhone glucose value was validated**. None of the
three exact artifact/material combinations may be retried.

The first PR #13 run connected, displayed the generic Swift error
`GS3DeveloperProbe.V3ProbeError error 4`, and returned to its idle scan state.
Its follow-up diagnostics could not be reconstructed because that artifact did
not retain a trace.

The second run used merged PR #14. Its redacted trace proves exact
authentication acceptance, one acknowledged `0xE2` CoreBluetooth write, and
one `0x39` CoreBluetooth write call. The first subsequent FF31 value retained
only its 24-byte length and was classified by that artifact as malformed or
unsupported. The probe then disconnected without a retry. The trace does not
retain enough information to identify the failed validation stage.

The third run used merged PR #15 with the fresh-capture-backed replacement
start index. Its redacted trace again proves exact authentication acceptance,
one acknowledged `0xE2` CoreBluetooth write, and one `0x39` CoreBluetooth write
call. Before the `0x39` write acknowledgement callback, FF31 delivered one
24-byte value. This artifact narrowed the failure to a declared-length-valid
but unsupported decrypted command. It did not retain the command byte or check
the checksum after that command failure, and it disconnected without retrying.

After the first run, the official Chinese Android app reconnected to the same
active sensor and resumed fresh data. The owner-reported post-run control point
was:

- displayed update time `20:02` in the owner-local Asia/Singapore test context;
- `8.8 mmol/L`; and
- an arrow visually pointing right-down.

The arrow wording is a visual observation only. This record does not map it to
a native trend code or physiological meaning.

Before the second run, the owner reported an official-app control point at
`20:57`, `6.7 mmol/L`, with an arrow visually pointing right. After the second
run, the official app reconnected and resumed fresh data at `21:17`,
`6.2 mmol/L`, again with an arrow visually pointing right. The time context and
visual-arrow caveat are the same as for the first run.

Before the third run, the owner reported an official-app control point at
`22:12`, `5.0 mmol/L`, with an arrow visually pointing right. After the third
run, the official app reconnected and resumed fresh data at `22:27`,
`5.2 mmol/L`, again with an arrow visually pointing right. No re-binding or
reactivation was required.

## Exact authorized artifacts and boundary

### First run — PR #13

- Pull request: `#13`
- Source commit: `e0e332cee3dd7acf725262ba9da6bb52ddb59c94`
- Signed-app manifest SHA-256:
  `1c15cbfcbde10135a0f93bd167fd0af06b807f51015f764feb75540005c16855`
- Bundle ID: `app.sugarman.probe`
- Test platform: one owned iPhone on iOS `26.6.1`
- Sensor: one owned, already-active Mainland GS3

### Second run — merged PR #14

- Source commit: `99717cee15a6f83a0a9c1a3b05607445f2f24787`
- Signed-app manifest SHA-256:
  `8c2290dfb8e5e0e381dca23702f752a1e3efc576fad3219d88544951ef4f360e`
- Bundle ID: `app.sugarman.probe`
- Test platform: the same owned iPhone on iOS `26.6.1`
- Redacted diagnostic attachment: 1,328 bytes, SHA-256
  `c2449c64d444961a56b5f830c72dcfef09552fbaa38486e36fcb5d3ff340f5ef`

### Third run — merged PR #15

- Source commit: `34668001866eb6ca010b0c34b748e542a26222c7`
- Signed-app manifest SHA-256:
  `e1c314afa40a2c9086f7963e63ae20472f2fea387829691e245c6b2ad96fa7d3`
- Bundle ID: `app.sugarman.probe`
- Test platform: the same owned iPhone on iOS `26.6.1`
- Redacted diagnostic attachment: 1,398 bytes, SHA-256
  `92b94d973df7ebf9eb34de4a71da558b5e3afba62161a5e39d965b999b33cc9b`

The stable iPhone serial, signing identity, sensor identity, imported material,
and import-file hash remain outside Git. Each authorization allowed one
connection, FF31 subscription, at most one typed `0xE2` authentication write,
and—only after exact authentication acceptance—at most one typed `0x39`
request. It forbade retry, reconnect, activation, binding, reset, firmware,
lifecycle, HealthKit, and every other sensor write.

## What is verified and what is not

### First-run physical observations — high confidence

- The expected peripheral was discoverable and explicitly selected.
- CoreBluetooth connected before the app failed closed.
- The probe returned to its idle state and did not automatically retry or
  reconnect.
- The official Android app later reconnected and displayed the fresh control
  point above.

### Second-run redacted trace — high confidence

- The expected peripheral connected once and exposed the verified
  FF30/FF31/FF32 path.
- FF31 notification subscription succeeded.
- CoreBluetooth invoked exactly one 38-byte `0xE2` write and acknowledged it.
- FF31 delivered the exact five-byte `0xE2 / 0x01 / 0x00` authentication
  acceptance.
- Only after that acceptance, CoreBluetooth invoked exactly one seven-byte
  `0x39` write.
- Before an acknowledgement callback for that `0x39` write was recorded, FF31
  delivered one 24-byte value that failed the combined decoder.
- The state machine failed closed with authorized effect counts `E2=1` and
  `0x39=1`, zero unique live readings, and no retry or reconnect.
- The official Android app subsequently reconnected and displayed the fresh
  `21:17` control point without re-binding or reactivation.

### Third-run redacted trace — high confidence

- The fresh-capture-backed replacement start index was imported successfully.
  Its value and import-file hash remain outside Git.
- The expected peripheral connected once and exposed FF30/FF31/FF32.
- FF31 notification subscription succeeded.
- CoreBluetooth invoked exactly one 38-byte `0xE2` write and acknowledged it.
- FF31 delivered the exact five-byte authentication acceptance.
- CoreBluetooth then invoked exactly one seven-byte `0x39` write.
- Before the `0x39` write acknowledgement callback, FF31 delivered one 24-byte
  value. Decryption produced a matching declared length, then failed at the
  command allowlist as `glucoseUnsupportedCommand`.
- The exact command byte, checksum result, record fields, and payload were not
  retained. Zero unique live readings were accepted.
- The state machine disconnected with application-write counts `E2=1` and
  `0x39=1`, without retry or reconnect.
- The official Android app subsequently reconnected and displayed the fresh
  `22:27` control point without re-binding or reactivation.

### First-run source evidence — high confidence

- The exact PR source permits no more than one typed `0xE2` effect and one
  typed `0x39` effect.
- Its unknown/malformed notification path disconnects without a retry.
- `V3ProbeError` conformed only to `CustomStringConvertible`, not
  `LocalizedError`, so `error.localizedDescription` discarded the useful
  source message and produced the generic UI text.
- The exact build retained no packet/state trace, so it cannot reveal the
  received frame class or whether the conditional `0x39` write was invoked.

### Offline replay and request-index evidence — high confidence

- The same private address/key/IV material decodes all 69 unique 24-byte live
  notifications in the canonical official Android capture as structurally
  valid `0x32` frames. The algorithm key and IV are used only after structural
  length, command, count, layout, and checksum validation, so they cannot alone
  explain the second run's generic structural classification.
- The canonical capture contains four official `0x39` requests with three
  distinct start indexes. Every official request start equals the first
  following `0x32` or `0x39` data-batch start.
- The start index in the second run's private import matches none of those four
  official requests.
- A fresh post-handback ring-buffer summary independently contains five valid
  official `0x39` requests with four distinct starts. Every start again equals
  the first following valid data-batch start, and the newest request differs
  from the earlier provisional correction.
- The replacement private import changes only `effectiveDataStartIndex` from
  the original PR #13 file to that newest verified request start. The selected
  value and import hash remain outside Git.
- The third run used that replacement and still reached the same 24-byte
  failure point. The earlier start-index mismatch is therefore not the cause of
  this failure.

### Inferences

- **Medium confidence:** the 24-byte value is either a real protocol command
  outside the current `0x32`/`0x39` allowlist or a differently encrypted frame.
  Matching declared length alone cannot distinguish those cases because the
  third artifact checked the command before the checksum.
- **Medium confidence:** delivery before the `0x39` CoreBluetooth
  acknowledgement is a narrow reason to quarantine one future checksum-valid
  24-byte unsupported command and continue listening without another write.
  This is a diagnostic exception, not evidence that the unknown command is
  safe to interpret or ignore in the product.
- **Low confidence:** omission of official-app device-information queries may
  matter. The exact authentication acceptance proves they were not required
  before authentication, and the current evidence does not justify adding more
  writes.

### Not verified by this run

- Over-the-air or controller-level write evidence; CoreBluetooth write calls
  are application evidence, not an iPhone HCI capture.
- Whether the second or third run's `0x39` write reached or was accepted by the sensor;
  no write acknowledgement or `0x39` control acknowledgement was retained.
- The third-run 24-byte value's decrypted command or checksum result.
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

The second and third runs narrow that earlier uncertainty: authentication itself works
without those queries. It does not prove whether any query is needed before a
valid effective-data response, so the next candidate still does not add one.

## Fresh official reconnect evidence

After the second Android handback, a read-only bugreport collection preserved a
standard `BTSNOOP_LOG_SUMMARY`. The directly included `.filtered` file omitted
every ATT payload and is not protocol evidence. Decoding the standard summary
with the already pinned AOSP tool produced a 13,527-record capture, SHA-256
`6d6467d9bcde31b23bc8c561e50a549dd5a24e43e231bc8bad40ae40ff4f77ac`,
with 580 ATT PDUs.

Private allowlisted replay found five official authentication writes and five
effective-data requests. The five requests contain four distinct starts; all
five starts equal the first following valid data-batch start. The newest start
differs from both the second-run import and the earlier provisional correction.
The new replacement import preserves every original field byte-for-byte except
`effectiveDataStartIndex`. No packet, address, key, owner identifier, selected
index, glucose history, or private-import hash is printed or committed.

## Follow-up decision

Do not rerun the PR #13, merged PR #14, or merged PR #15 artifact/material
combinations. The next reviewed candidate retains the two-command maximum and
adds only:

- checksum validation before unsupported glucose-command reporting;
- the unsupported protocol command byte as allowlisted metadata, while still
  omitting every other payload byte;
- quarantine of at most one checksum-valid 24-byte unsupported command only
  while the sole `0x39` CoreBluetooth acknowledgement remains outstanding; and
- continued receive-only observation after that quarantine. A second or later
  unknown response still fails closed, and a five-reading result after a
  quarantine remains diagnostically inconclusive.

It preserves the existing localized errors, state/counter trace, separate
write-call/acknowledgement evidence, one-in-flight gate, and zero-retention rule
for all packet bytes except the command metadata, identifiers, private material,
glucose values, and record indexes. It does not add `0xF0` device-information
writes or any other command.
Host verification and review do not authorize another physical run. A new
source commit, signed manifest, confirmed-private-import hash,
device/environment record, and fresh owner confirmation are required first.
