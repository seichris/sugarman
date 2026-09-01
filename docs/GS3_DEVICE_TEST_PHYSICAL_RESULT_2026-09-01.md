# First managed foreground Device Test result — 2026-09-01

## Outcome

The first physical run of the isolated `SugarmanDeviceTest` target reached the
durably prepared history request, then failed closed before CoreBluetooth
acknowledged that write. The official Android app subsequently received a fresh
reading. This is a useful transport-failure observation and an Android handback
pass; it is not a managed-reading or durability pass.

## Exact public artifact

- Source commit: `3eccdb4eeb02350ea5d434fc139093a8aa0a7e50`
- Signed-app SHA-256:
  `65ae8bd7d9eb686c4f3bc4bd7eb9c358aa767573b0159e7b5d439876bb8a1453`
- Bundle ID: `app.sugarman.ios.devicetest`
- Test platform: one owned iPhone
- Sensor: one owned, already-active Mainland GS3

The stable device serial, sensor identity, private-import filename, hash and
contents, history start, record indexes, packet bodies, and glucose values
remain outside Git.

## Verified facts from the payload-free report

The report establishes this order:

1. one shared-process ownership acquisition and one connection;
2. service/characteristic discovery and notification subscription;
3. exactly one authentication request and CoreBluetooth write
   acknowledgement;
4. exact authentication acceptance;
5. one history plan load and durable preparation;
6. exactly one typed history request attempt;
7. no CoreBluetooth history-write acknowledgement;
8. an immediate terminal protocol-violation disconnect while the reducer was
   in `requestingHistory`; and
9. no committed sample, duplicate, or gap.

The official Android app then received a fresh reading without a reported
binding or activation step, so handback passed for this run.

## Inference, not a verified packet classification

The failure timing is consistent with the checksum-valid 24-byte `0x36`
notification previously observed by the one-shot Probe while the sole `0x39`
CoreBluetooth acknowledgement was pending. The Device Test artifact reported
all inbound decoder failures as the same payload-free protocol violation,
however, so this run does **not** prove that `0x36` was the triggering command.
It also does not establish that command's semantic meaning.

## Product response and next gate

The host policy may recognize one exact checksum-valid 24-byte `0x36` only
before any glucose batch and in that narrow pending-write window, then report it
as an observed history preamble.
That receive-only classification grants no readiness, glucose, retry, reconnect,
or write semantics. A duplicate, late occurrence, wrong length, bad checksum,
or any other unsupported command remains terminal.

This policy is synthetic-test evidence only until a newly reviewed exact
artifact physically reports the preamble count and proceeds to valid history
and live data. Five-reading durability, iPhone reconnect with fresh
reauthentication/resubscription, durable overlap, timestamp parity, native
state mapping, and final protocol classification remain open.

This report authorizes no build, installation, launch, scan, connection, or
sensor action.
