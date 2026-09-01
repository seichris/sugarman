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

## Exact-preamble macOS diagnostic run

The next exact Mac source commit was
`592056b43ee9e0c5d59d464851f4736d2d4533da`. Its signed-app manifest
SHA-256 was
`003611eeba2ef674e6ce7c22d0cc4791a42172dfe9e430755baf4bdc62031632`,
and its bundle identifier was `app.sugarman.macos.devicetest`. After separate
owner confirmations, one bounded managed foreground connection was armed.

The first connection attempt timed out and scheduled exactly one bounded
reconnect. The second connection then established this payload-free order:

1. subscription, exactly one authentication request, one authentication write
   acknowledgement, and exact authentication acceptance;
2. one durably prepared coordinator history-request intent;
3. no CoreBluetooth history-write acknowledgement;
4. inbound classification rejection of the exact checksum-valid 24-byte known
   observed-preamble shape while the transport timing window was
   `authenticated`;
5. one protocol-violation disconnect followed by terminal stop, with no retry
   after that protocol violation; and
6. no inserted sample, duplicate, or gap.

The exact category is stronger evidence than the prior coarse notification
category: it proves the inbound classifier reached the known 24-byte
observed-preamble branch. It does not establish the frame's product meaning or
prove that accepting it will lead to history or live data. The coexistence of
the coordinator's durable history intent with the transport's earlier
`authenticated` window physically verifies the dispatch race previously only
inferred from source ordering.

After Sugarman stopped and released the sensor, the owner reported that the
official Android app received a new reading and displayed history. That is a
handback and sensor/history-availability pass. It is not a Mac reading,
durability, or final interoperability pass. The normalized provisioning remains
in the Mac-specific this-device-only Keychain item.

## Receive-only response and remaining physical gate

The next production candidate uses two independent gates for only that exact,
checksum-valid, 24-byte shape. The transport may classify it once in either the
authenticated-before-history-dispatch race or the existing pending-history-
write window. The coordinator accepts the resulting payload-free event only
after the sole history request has been durably prepared. An earlier event,
duplicate, late occurrence, wrong length, bad checksum, or different command
remains terminal.

This changes no command encoder or typed write boundary and adds no write,
retry, reconnect, acknowledgement, readiness, glucose, or generic unknown-frame
semantics. Host tests cover both transport windows, the independent durable-
intent gate, early/late/duplicate rejection, redaction, diagnostic suppression,
disconnect ordering, ownership, and the existing lifecycle.

It remains host evidence until a newly confirmed exact Mac artifact physically
proceeds through history and live data. Final acceptance still requires a
separately confirmed iPhone artifact and the complete durability matrix. This
report authorizes no further build, launch, scan, connection, or hardware
action.

## First managed macOS history and live-reading pass

The exact receive-only candidate at source commit
`5ef4ad4921e15d7400c037ac34a95c9de9797fd6` was built with the
`SugarmanMacDeviceTest` scheme. Its signed universal app manifest SHA-256 was
`7c3b61d927d866966910974bbf3fbb276d83a21a4e09e44ea179a865d462ff9a`,
and its bundle identifier remained `app.sugarman.macos.devicetest`. The
signature and sandbox, Bluetooth, and App Group entitlements were verified
before launch. No other local Sugarman process was running.

The payload-free UI report established this order on one connection:

1. one ownership acquisition, connection, subscription, authentication
   request, authentication write acknowledgement, and exact authentication
   acceptance;
2. exactly one durably prepared history request and one history write
   acknowledgement;
3. exactly one observed preamble, with no protocol rejection, retry, or
   reconnect;
4. transition to `subscribed` / reducer phase `live`, which the coordinator can
   reach only after committing a live notification;
5. completion of the history overlap with 2,510 inserted samples, one
   equivalent duplicate, and zero remaining gap ranges at 51 elapsed seconds;
6. a later one-sample durable increase to 2,511 while still live at 72 elapsed
   seconds; and
7. an explicit stop at 107 elapsed seconds with the same final counts, followed
   by process exit.

This is the first physical Mac history and live-reading interoperability pass
for the managed production lifecycle. It physically validates the combined
transport-race and durable-coordinator preamble gate for this connection. It
also confirms that the exact preamble event added no second request or retry.

The report remains payload-free: it contains no sensor/peripheral identifier,
private material, packet body, command byte, glucose value, record index,
imported JSON content/hash, or arbitrary error text. The private provisioning
remains in the Mac-specific this-device-only Keychain item.

This run does not establish five consecutive live readings, unexpected-link-
loss reconnect, iPhone parity, timestamp parity with the official app, native
quality-state meaning, protocol completeness, or official-app handback after
this specific run. Those remain separate physical gates.

## Five-consecutive-live-reading macOS pass

The same exact receive-only Mac artifact at source commit
`5ef4ad4921e15d7400c037ac34a95c9de9797fd6` and signed-app manifest SHA-256
`7c3b61d927d866966910974bbf3fbb276d83a21a4e09e44ea179a865d462ff9a`
was later armed for a longer managed foreground connection. The payload-free
report established:

1. initial synchronization completed at 29 elapsed seconds with 23 inserted
   samples, one equivalent duplicate, and zero gap ranges;
2. five consecutive one-sample durable increases occurred at 89, 149, 209,
   269, and 329 elapsed seconds;
3. the connection retained exactly one authentication request and
   acknowledgement and exactly one history request, preamble, and
   acknowledgement throughout the run;
4. there was no extra request, reconnect, protocol rejection, or gap; and
5. explicit stop at 373 elapsed seconds produced `disconnectRequested`, then
   `transportDisconnected`, then `stopped`.

This physically passes the five-consecutive-reading and foreground durability
gates on the Mac. It also confirms an approximately 60-second live cadence for
this run; the client is not polling every five minutes. Private values, record
indexes, and timestamps remain outside this report. Sequential timestamp and
value comparison with the official app remains open.

## Device-Test-only injected-link-loss macOS pass

The reconnect diagnostic source commit was
`8179b0c2dcc7482081a1fbbf9a62bca9d74b7be6`. Its signed arm64 Mac app
manifest SHA-256 was
`7ad43f53c00b246e189cc747d8f6521fe71a65a49595352c7758db1ad0fbe8ca`,
and the executable SHA-256 was
`d3e5a5be7a7141b63b21455dffb267e14077af30889ce2b8eb78d15e8790416c`.
The signature and sandbox, Bluetooth, and App Group entitlements were verified
before launch.

After initial synchronization reached `live`, the Device-Test-only control
cancelled that one already-streaming CoreBluetooth connection without sending
a sensor write. The payload-free report established:

1. connection one performed exactly one subscription, authentication, and
   history request and reached `live` with zero gaps;
2. the injected cancellation produced one `linkLoss` disconnect and exactly
   one reconnect schedule;
3. connection two freshly subscribed and authenticated, then made exactly one
   history request;
4. its first inclusive overlap inserted no row and counted one equivalent
   duplicate, with zero gaps;
5. its next batch durably inserted one sample and returned the reducer to
   `live`, still with zero gaps and no rejection; and
6. explicit stop produced `disconnectRequested`, then
   `transportDisconnected`, then `stopped`, with no second reconnect.

This physically validates the integrated single-flight reconnect, fresh
per-connection authentication/history sequence, durable inclusive overlap,
deduplication, and disconnect ordering on the Mac. The trigger was an explicit
Device Test CoreBluetooth cancellation routed through the link-loss path; it
was not an uncontrolled radio or out-of-range loss. Spontaneous RF-loss
classification therefore remains a distinct physical gate. The control is
live-only, at most once per controller, absent from the release app, and adds
no command, retry, raw-write, or classifier semantics.

Final acceptance still requires sequential private timestamp/value comparison
with the official app and the equivalent exact-artifact iPhone run. Native
quality-state meaning, index wrap, and official-app handback after the final
iPhone run also remain open.

## Predeclared private comparison protocol

Before inspecting official-app values or timestamps, the acceptance tolerance
is fixed as follows:

1. compare at least five sequential corresponding readings with both apps set
   to the same display unit;
2. require each displayed value to match exactly;
3. require each Sugarman mapped timestamp to differ from its corresponding
   official-app timestamp by no more than 30 seconds;
4. require the same order and approximately 60-second spacing across the whole
   sequence; and
5. fail the current 60-second anchor policy on any adjacent-slot shift,
   reordered or missing value, larger timestamp error, or value mismatch.

Thirty seconds is strictly less than one 60-second sample interval, so the
tolerance cannot silently accept a one-record index shift. It also accommodates
an official UI that rounds a timestamp to the nearest minute. The owner must
perform this comparison locally in the two private app views and record only
pass/fail and mismatch categories. Values, timestamps, indexes, screenshots,
and imported material remain outside Git, PRs, chat, and shared diagnostics.

## Exact iPhone durability and injected-reconnect pass

The exact signed iPhone Device Test artifact used source commit
`1bc52f3d08e1f7d512ed4242ecd7ba83abdd45b3`, bundle identifier
`app.sugarman.ios.devicetest`, and signed-app manifest SHA-256
`b2c6a8949082ed43df154218f954640e56996ad41a1dd375aa6e0e5a2f12d232`.
Its signature, embedded provisioning for the separately confirmed owned
iPhone, App Group entitlement, and bundle identifier were verified before
installation. The exact device identifier, serial, and provisioning material
remain outside Git.

The final payload-free report established:

1. connection one subscribed, authenticated, made one history request, and
   observed one bounded preamble, then encountered one unexpected
   allowlisted CoreBluetooth disconnect before committing a batch;
2. exactly one reconnect schedule created connection two, which freshly
   subscribed and authenticated, made one history request, observed one
   preamble, and completed initial synchronization with zero duplicates or
   gaps;
3. connection two then committed ten consecutive one-sample live batches at
   exact 60-second intervals, with no extra authentication/history request,
   duplicate, gap, rejection, or protocol violation;
4. one Device-Test-only link-loss injection while `live` produced exactly one
   `link loss` disconnect and one reconnect schedule;
5. connection three freshly subscribed and authenticated, made exactly one
   history request, and observed one preamble;
6. its first inclusive overlap inserted zero samples and counted one
   equivalent duplicate with zero gaps; its next batch inserted one sample,
   retained that single cumulative duplicate, and returned the reducer to
   `live` with zero gaps;
7. the UI totals were three authentication write acknowledgements and three
   history write acknowledgements for the three connections; and
8. explicit stop immediately after the return to `live` produced
   `disconnectRequested`, then `transportDisconnected`, then `stopped`, with
   no further reconnect.

This physically passes the iPhone five-reading, exact 60-second cadence,
single-flight reconnect, fresh per-connection authentication/history,
inclusive-overlap deduplication, zero-gap, fail-closed protocol, and controlled
stop gates for this exact artifact. The unexpected disconnect occurred before
initial synchronization; the post-live reconnect was an explicit Device Test
CoreBluetooth cancellation, not an uncontrolled RF or out-of-range loss.

The report contained only the allowlisted header, acknowledgement totals, and
typed lifecycle rows. It contained no sensor identifier, private material,
packet body, arbitrary command byte, glucose value, record index, imported
JSON content/hash, arbitrary error string, or non-diagnostic line.

Official-app handback and the predeclared private five-reading timestamp/value
comparison remain pending. Native quality-state meaning, sensor-index wrap,
final product meaning for the observed preamble, background restoration, and
fresh-sensor activation also remain outside this pass.
