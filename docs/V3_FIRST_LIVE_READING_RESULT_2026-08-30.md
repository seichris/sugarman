# First live Mainland GS3 iPhone reading — 2026-08-30

## Outcome

A clean, bounded run of the merged PR #16 developer probe physically validated
one live Mainland GS3 glucose reading on iPhone. The probe authenticated,
requested effective data, received history, decoded one live `0x32` record, and
then lost the CoreBluetooth connection before the five-reading durability gate.

The iPhone reading matched the private official Android pre-run control. After
the iPhone disconnected and Android Bluetooth was re-enabled, the official app
reconnected without re-binding or reactivation and displayed fresh data. The
readings, observation times, and trend details remain private.

This is a **protocol-interoperability pass for one live value** and an **Android
handback pass**. It is not yet a same-owner handover pass: only one of five
required live readings arrived, the link timed out unexpectedly, and the run
used the deliberately diagnostic single-command quarantine.

## Exact public artifact and evidence

- Source: merged `main` commit
  `ff6cdb54b3233cb4b8cbef529b7bcc56da83d7a0` (PR #16)
- Signed-app manifest SHA-256:
  `08c7e246f78436e5bb8fd3d0d4863fe367bbac1cd7d9c5c65ffb4fe8e572364e`
- Bundle ID: `app.sugarman.probe`
- Test platform: one owned iPhone on iOS `26.6.1`
- Sensor: one owned, already-active Mainland GS3
- Clean-run redacted diagnostic: 4,841 bytes, SHA-256
  `b5d86b95c80370ea9cb52ecba2a654f4ccdd174d53f28fc188d9008fb36c2189`

The stable device serial, sensor identity, private-import hash and contents,
sensor record indexes, and packet bodies remain outside Git.

## Clean-run trace — high confidence

The redacted diagnostic directly establishes this order:

1. one connection and discovery of FF30/FF31/FF32;
2. successful FF31 notification subscription;
3. exactly one 38-byte `0xE2` CoreBluetooth write call and acknowledgement;
4. exact decrypted `0xE2 / 0x01 / 0x00` authentication acceptance;
5. exactly one seven-byte `0x39` CoreBluetooth write call and acknowledgement;
6. quarantine of one checksum-valid 24-byte unsupported command `0x36` while
   the sole `0x39` write acknowledgement was pending;
7. one five-byte effective-data acknowledgement;
8. twenty-two effective-data batches: twenty-one 136-byte values and one
   120-byte value;
9. one 24-byte live-notification batch, producing one unique validated live
   reading; and
10. an unexpected CoreBluetooth connection timeout, with no retry, reconnect,
    or additional application write.

The app's own seven-minute timer uses different wording, so the observed
localized timeout was a transport disconnect rather than the bounded timer.
The exact underlying CoreBluetooth numeric error code was not retained by this
artifact.

## Private parity comparison — high confidence within stated limits

- Official Android pre-run control: recorded privately.
- iPhone: matched the private control from a live `0x32` source.
- Official Android post-run handback: fresh data recorded privately.

The pre-run parity and live source are physically verified for this owned
sensor/app/library combination. The specific measurements, timestamps, and
trend observations remain private, and this result does not establish a general
trend mapping for other firmware or sensor lots.

## Preflight contention observations

Two immediately preceding attempts with the same artifact stopped after
connection and FF30 service discovery, before FF31 subscription or any
application write. Their shared redacted report bytes had SHA-256
`a00fc882594be2e561d7bfd45215ce9c770c462275bd0c0505b6e5312c13d36e`.
The report format did not contain a run ordinal or timestamp, so the two files
cannot independently prove which attempt produced which copy.

Both the normal `Sugarman` app and `SugarmanProbe` were running during those
attempts. After both processes were terminated and only `SugarmanProbe` was
launched, the clean run reached live data. This makes local CoreBluetooth
ownership contention a **medium-confidence hypothesis**, not a proven cause.
The normal app has background-central/restoration behavior, while the probe is
foreground-only. Production code should prevent two Sugarman processes from
competing for the same sensor and should retain payload-free run/disconnect
metadata.

## What remains unverified

- five consecutive live readings on one iPhone connection;
- the exact meaning and product treatment of command `0x36`;
- a successful gate with zero quarantined commands;
- whether a reconnect requires a fresh `0xE2` and `0x39` pair, even though the
  official Android capture shows that pair once per observed connection;
- reconnect backoff, resubscription, history backfill, deduplication, stale UI,
  background restoration, lock-screen behavior, and a 24-hour run;
- another sensor lot/firmware, another iPhone, or fresh activation; and
- over-the-air/controller-level iPhone write evidence.

## Decision

Do not repeat the one-shot probe merely to chase five readings. The next work is
a reviewed production transport design for explicit process ownership,
single-flight reconnect, reauthentication policy, resubscription, capture-backed
history start, durable deduplication/backfill, and stale/disconnected UI. It must
preserve private material in device-only Keychain, retain the typed command
allowlist, and add no activation/binding/reset surface.

Any newly signed build or physical sensor run still requires a fresh exact
artifact/device/action confirmation. This report itself authorizes no install,
launch, connection, or sensor command.
