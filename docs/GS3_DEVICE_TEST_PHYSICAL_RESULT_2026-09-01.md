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

## Newer follow-up report after narrow preamble handling

A genuinely newer payload-free export contains the added
`historyPreambles=0` field and establishes this order:

1. one authentication write acknowledgement and exact authentication
   acceptance;
2. exactly one history request;
3. no history write acknowledgement and no observed history preamble;
4. an immediate protocol-violation disconnect while the reducer was in
   `requestingHistory`; and
5. no inserted sample, duplicate, or gap.

This physically disproves validation of the current narrow preamble handling.
It does not prove the rejected frame, command, or failure origin. In particular,
the report cannot distinguish an inbound classification rejection from a
write-callback, transport/coordinator state, or request invariant failure. The
next safe production step is typed payload-free first-rejection observability;
the existing classifier and exactly-one typed write policy remain unchanged.

The follow-up report contains no exact signed-artifact identity, so it does not
replace the exact artifact record above or authorize a further physical action.

## Typed first-rejection diagnostic run

The owner then built and installed the exact typed-observability source commit
`3ffbfcd566e205ef44fa79868e6c5be4aff3a452` with the
`SugarmanDeviceTest` scheme. The signed-app manifest SHA-256 recorded at build
time was
`57850ea3f18346ad3c1ee28bd13a2ffe2e2793dc36df9fec2429b569895f9491`.
The subsequently exported payload-free report establishes:

1. one authentication write acknowledgement and exact authentication
   acceptance;
2. exactly one durably prepared history request intent;
3. no history write acknowledgement and no accepted history preamble;
4. the first rejection was `inboundClassification` for a coarse
   `notificationCandidate` of 24 bytes while the transport timing window was
   `authenticated`;
5. the rejection was recorded before the protocol-violation disconnect and
   terminal stop; and
6. no sample insertion, duplicate, gap, retry, or reconnect.

This is a successful observability result and a failed reading/durability run.
It distinguishes the failure from write-callback, coordinator state, and
request-invariant origins for this connection. The combination of one
coordinator history intent with the transport's earlier `authenticated` window
is consistent with a notification overtaking the actual history-write
dispatch. That is a source-backed timing inference, not a packet
classification. The report still does not expose the decrypted command, packet
body, sensor identity, private material, record index, or failure semantics,
and it does not justify broadening the accepted preamble window.

The next physical step may be accelerated with the isolated macOS Device Test,
but a signed exact Mac artifact plus separate launch, private import, scan, and
arm confirmations are still required. Final product acceptance remains an
iPhone gate. See [`MACOS_DEVICE_TEST.md`](MACOS_DEVICE_TEST.md).

## First managed macOS Device Test run

The owner subsequently built and signed the exact Mac source commit
`0efb7f22e033e29315b0ef47ca1673b005eec2c5` with the
`SugarmanMacDeviceTest` scheme. The signed-app manifest SHA-256 was
`eabc34256c2fb6875536651692a8556ff0c22be8bcd786ff5dd5fe7c36005fe0`,
and the bundle identifier was `app.sugarman.macos.devicetest`. Separate owner
confirmations covered launch, private import, the bounded scan-only action, and
one managed foreground connection.

The payload-free report recorded one authentication write acknowledgement and
acceptance, one coordinator history-request intent, no history-write
acknowledgement, no history preamble, and then inbound classification rejection
of a 24-byte notification candidate in the transport's `authenticated` timing
window. The rejection preceded the protocol-violation disconnect and terminal
stop at approximately two elapsed seconds. It recorded no inserted sample,
duplicate, gap, retry, or reconnect. A later explicit stop produced a separate
stopped lifecycle entry; the app was then quit and verified absent from the
process list.

This independently reproduces the typed iPhone failure ordering on the Mac and
supports the same notification-overtaking-history-dispatch hypothesis. It does
not prove that the rejected frame was the observed `0x36` preamble, identify its
meaning, establish sensor health, or replace an official-app handback or final
iPhone acceptance run. The normalized private provisioning remains only in the
Mac-specific this-device-only Keychain item.

## Next fail-closed diagnostic refinement

The next source candidate may distinguish the already allowlisted, exact
checksum-valid 24-byte observed-preamble shape when it arrives outside its sole
accepted pending-history-write window. The result is one bounded category: no
packet body, command byte, sensor identifier, private material, glucose value,
record index, imported JSON content or hash is reported.

That refinement remains terminal outside the existing accepted window. It adds
no accepted frame, request, write, retry, reconnect, readiness, or glucose
semantics. It is host evidence only until a newly confirmed exact artifact
reports the new categories.
