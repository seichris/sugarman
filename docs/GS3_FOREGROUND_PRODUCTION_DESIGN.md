# Mainland GS3 foreground production lifecycle

## Decision

The first production transport milestone is a deterministic foreground session,
not an extension of the one-shot developer probe. It owns the sensor through
one cross-process lease, repeats subscription and authentication on every new
physical connection, prepares one capture-backed or durable-overlap history
request per connection, commits decoded samples atomically, and makes every
non-live phase fail closed in the UI.

This change implements the host-testable core, shared ownership gate, durable
time-anchor transaction, typed coordinator, and a foreground-only
CoreBluetooth adapter. `GS3ProtocolRequest` remains empty, `GS3CodecFactory`
remains fail closed, and the existing diagnostic runtime remains read-only.
The new adapter retrieves one known peripheral without scanning and has one
characteristic-write site that accepts only package-scoped frames produced by
the reviewed `0xE2` authentication and `0x39` effective-data encoders.

The normal app now has a lifecycle bridge, but its release bootstrap installs
no controller factory and has no source of active-session material. It therefore
cannot construct or run the adapter. A separately reviewed signed artifact and
fresh physical authorization remain mandatory before this code contacts a
sensor.

That scene/controller boundary now lives in the shared `GS3Transport` product
as `GS3ForegroundSessionLifecycle`, so iOS and the isolated macOS Device Test
use the same generation-based cleanup. A controller that finishes construction
after its scene ended is explicitly stopped, and an in-progress start cannot
become the active owner after foreground exit.

The isolated `SugarmanDeviceTest` target supplies that test boundary without
changing the release bootstrap. It links a dedicated strict private-import
module, stores normalized material only in a when-unlocked this-device-only
Keychain item, and begins every process unarmed. Import prepares local
already-active session metadata but cannot start Bluetooth. Only a separate
in-app arm confirmation installs the existing typed factory. See
[`GS3_DEVICE_TEST_PROVISIONING.md`](GS3_DEVICE_TEST_PROVISIONING.md).

When only the historical Probe JSON is available, the Device Test target now
has a separate provisioning-only bridge. It validates that exact schema in
memory, then an explicitly confirmed, shared-owner, ten-second adapter scans
for the exact private local name and stores one unique CoreBluetooth UUID. That
adapter cannot connect or access GATT and is not part of the foreground
transport. Zero or multiple matches fail closed, and the UUID remains absent
from UI, reports, diagnostics, and logs. The production adapter still retrieves
only the resulting known peripheral and never scans.

## Evidence ledger

### Verified facts

- The official Android captures for the owned, already-active sensor contain
  four grouped connections with one 38-byte `0xE2` authentication and one
  seven-byte `0x39` effective-data request on each connection. Every observed
  connection subscribed before data, authenticated before live data, and sent
  the `0x39` request after authentication acceptance.
- A later official reconnect capture contains five `0xE2` writes and five
  `0x39` requests. Each request's private start value matched the first
  following valid data batch. The values themselves remain device-only.
- The bounded iPhone run recorded by PR #17 subscribed, received exact
  authentication acceptance, made one acknowledged `0xE2` write and one
  acknowledged `0x39` write, received history, decoded one live `0x32` value,
  and then encountered an unexpected CoreBluetooth timeout.
- The official Android app subsequently resumed fresh data without binding or
  activation. This passes one-value interoperability and Android handback only.
- The iPhone run quarantined one checksum-valid `0x36` notification. Five
  consecutive readings, a zero-quarantine run, iPhone reconnect, and same-owner
  durability are not verified.
- The first managed Device Test run reached one durably prepared history
  request, then reported a terminal protocol violation before CoreBluetooth
  acknowledged the history write. Its payload-free diagnostics do not identify
  the inbound command. The official Android app subsequently received a fresh
  reading, so handback passed and the sensor remained healthy for that
  observation.
- A genuinely newer managed report after the narrow preamble handling was
  added again recorded one authentication write acknowledgement and acceptance,
  exactly one history request, no history write acknowledgement, no observed
  preamble, and an immediate protocol-violation disconnect while requesting
  history, with no inserted samples, duplicates, or gaps. This physically
  disproves validation of the current narrow preamble handling. The report does
  not establish the rejected frame or whether classification, a write callback,
  transport state, or request invariant originated the failure.
- The exact typed-observability artifact at commit `3ffbfcd` subsequently
  reported the first rejection as inbound classification of a 24-byte
  notification candidate in the transport's `authenticated` timing window,
  after one coordinator history intent and before any history-write
  acknowledgement. This rules out the other typed rejection origins for that
  connection. It supports a timing-race hypothesis but still does not identify
  the decrypted command or justify accepting the frame.
- The first exact Mac Device Test artifact at commit `0efb7f2` independently
  reproduced that ordering: authentication was acknowledged and accepted, the
  coordinator emitted one history intent, the transport reported no history
  write acknowledgement, and a 24-byte notification candidate was rejected in
  the transport's `authenticated` window. It inserted no sample and performed
  no retry or reconnect. Cross-platform reproduction strengthens the timing-race
  inference but still does not identify the command or justify accepting it.
- The next exact Mac artifact at commit `592056b` classified the rejected
  inbound frame as the exact checksum-valid 24-byte known observed-preamble
  shape, still in the transport's `authenticated` window after the coordinator
  had durably prepared one history intent and before the history write was
  dispatched or acknowledged. It inserted no sample and performed no retry
  after the terminal protocol violation. This physically verifies the
  notification-overtaking-history-dispatch race; it does not establish the
  frame's product meaning or validate the next receive-only policy.
- After that Mac run stopped, the official Android app received a new reading
  and displayed history. This verifies handback plus sensor/history
  availability, not Mac history/live reception or durability.
- The exact receive-only Mac artifact at commit `5ef4ad4` then completed the
  same connection with one authentication write acknowledgement, one history
  request and acknowledgement, one accepted preamble, no rejection/retry/
  reconnect, durable history overlap, and reducer phase `live`. The transition
  to `live` is possible only after a live notification is committed. The
  payload-free count reached 2,510 inserted samples, one equivalent duplicate,
  and zero gaps, then later increased by one while still live. The session was
  explicitly stopped and the process exited. This is a Mac history and
  live-reading interoperability pass, not final iPhone or durability proof.
- A longer run of that same exact artifact completed initial synchronization
  and then durably inserted five consecutive one-sample live batches at
  approximately 60-second intervals. It retained exactly one authentication
  and history request, with no reconnect, rejection, or gap, and stopped in the
  required disconnect ordering. This passes the five-reading durability gate
  on Mac only.
- The exact Device-Test reconnect artifact at commit `8179b0c` then injected
  one cancellation only after reaching `live`. The lifecycle scheduled exactly
  one reconnect, freshly subscribed and authenticated, requested one inclusive
  history overlap, deduplicated it, committed the next live sample, and stopped
  without a second reconnect or rejection. This validates the integrated Mac
  reconnect path but is not evidence of spontaneous RF-loss classification or
  iPhone parity.
- The exact signed iPhone Device Test artifact at commit `1bc52f3` subsequently
  completed initial synchronization after one pre-sync unexpected
  CoreBluetooth disconnect and one fresh reconnect. It then committed ten
  consecutive one-sample live batches at exact 60-second intervals. One
  Device-Test-only live link-loss injection produced exactly one further
  reconnect with fresh subscription/authentication/history, a duplicate-only
  inclusive overlap, one new live sample, zero gaps or rejection, return to
  `live`, and ordered controlled stop. This passes iPhone five-reading and
  injected-reconnect parity; spontaneous post-live RF loss, private
  official-app comparison, and final handback remain open.
- Two earlier attempts stopped before FF31 subscription while both Sugarman
  processes were running; a Probe-only run reached live data. That sequence is
  observed, but it does not isolate process contention as the cause.
- The canonical official capture contains 68 notification intervals: 66 are
  between 59 and 61 seconds and the median is approximately 59.95 seconds. This
  verifies an approximately one-minute notification cadence for that run, not
  an exact sensor-index clock on iPhone.

Public evidence: `docs/V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md`,
`docs/V3_PROBE_PHYSICAL_RESULT_2026-08-30.md`,
`docs/V3_FIRST_LIVE_READING_RESULT_2026-08-30.md`, and the redacted JSON records
under `docs/evidence/`. The managed-run result is
`docs/GS3_DEVICE_TEST_PHYSICAL_RESULT_2026-09-01.md`.

### Production inferences

1. **Authenticate once on every new CoreBluetooth connection.** The official
   sequence is connection-scoped in every observed capture, and no capture
   demonstrates that authentication survives a disconnect. Reusing an old
   authenticated state would be a weaker assumption.
2. **Resubscribe before each authentication.** Notification delivery is needed
   for acceptance and data responses, and the developer probe's physically
   successful path used this order.
3. **Send at most one `0x39` request per connection.** This matches all observed
   official connections. A remaining gap pins the durable cursor so the next
   connection repeats an inclusive overlap; the foreground slice does not
   invent extra same-connection requests.
4. **Use a private capture-backed start only before local history exists.** Once
   a request is durably prepared, restart repeats it. Once a contiguous sample
   is committed, reconnect starts at that committed index, intentionally
   overlapping one record for crash recovery and deduplication.
5. **Keep the ownership lease through reconnect backoff.** Releasing it during
   a scheduled reconnect would permit the other Sugarman process to connect in
   the middle of one logical foreground session. A controlled stop likewise
   retains the lease until the transport reports that disconnection completed.
6. **Anchor sensor indexes to the first received live record at a 60-second
   interval.** The observed cadence and monotonically increasing indexes support
   this host-side mapping, but reception time includes radio and scheduling
   latency. The anchor is persisted atomically with its first mapped batch so a
   reconnect cannot silently retime prior history. Its inferred interval and
   mapping revision are persisted with it, so a later policy change cannot
   reinterpret an existing session. The current coordinator rejects an unknown
   interval/revision rather than silently migrating it. Exact timestamp parity
   and index-wrap behavior remain physical gates.
7. **Treat decoded production samples as questionable until native state flags
   are mapped.** The bit boundaries are verified, but their healthy, error,
   calibration, and expiry meanings are not. Glucose and the observed trend can
   be stored for comparison without allowing `SafetyEngine` to present them as
   current.
8. **Classify one exact observed history preamble without assigning semantic
   meaning.** The Probe physically observed one checksum-valid 24-byte `0x36`
   while the sole typed `0x39` CoreBluetooth acknowledgement was pending, then
   received valid history and live data. The exact Mac diagnostic later proved
   the same known frame shape can arrive after the coordinator has durably
   prepared its history intent but before the transport dispatches that write.
   The transport may therefore recognize that exact shape once, before any
   glucose batch, in either of those two adjacent transport windows.
9. **Require the independent durable-request gate.** Transport classification
   alone grants no acceptance. The coordinator accepts the payload-free event
   only in `requestingHistory`, after exactly one history request has been
   durably prepared. An event before that state, a duplicate, a late event, or
   any malformed/different unsupported notification remains terminal. The
   combined policy adds no payload, write, retry, reconnect, glucose,
   acknowledgement, or readiness semantics.

The combined preamble policy is now physically interoperable for managed Mac
history/live connections. Five-reading durability and the injected-link-loss
reconnect path have passed on Mac; they remain unverified on iPhone, and the
injected cancellation is not proof of spontaneous RF-loss classification.

### Physical-test gates

Before calling this a working iPhone production transport, a newly reviewed
exact artifact must prove, with fresh owner confirmation:

- the App Group entitlement and file lease prevent the normal app and probe
  from owning sensor access simultaneously on the signed device;
- an unexpected disconnect causes exactly one reconnect timer and one new
  connection, followed by a fresh subscription, one accepted `0xE2`, and one
  acknowledged `0x39`;
- a controlled gap is backfilled from the durable inclusive cursor without a
  duplicate database row or a skipped index;
- at least five sequential corresponding readings match the official app's
  displayed value after selecting the same unit, each mapped timestamp differs
  by no more than 30 seconds, and their order and approximately 60-second
  spacing agree; any adjacent-slot shift, reordered/missing value, larger
  timestamp error, or value mismatch fails the current anchor policy;
- native sensor-index wrap behavior is captured before any session can cross
  the current `UInt16` boundary;
- five consecutive live readings arrive on a managed foreground session;
- healthy/error/calibration/expiry state patterns are compared with the official
  app before any production sample quality can become `ok`;
- the acceptance run has no unsupported or malformed command; an exact bounded
  `0x36` occurrence is reported separately as an observed-history-preamble
  count, and any second, late, wrong-length, checksum-invalid, or different
  unsupported command stops the adapter;
- a bounded preamble occurrence may collect history/live interoperability
  evidence, but it does not by itself pass final protocol-completeness or
  five-reading durability while the command's product meaning remains unknown;
- stale and disconnected presentation matches the actual link and reading age;
  and
- official Android handback still succeeds without binding or activation.

No physical action is authorized by this design or by provisioning/import
alone. Every exact artifact and each physical test action still requires fresh
owner confirmation.

The isolated `SugarmanMacDeviceTest` can shorten the build/run loop while
reusing the typed controller. Because a CoreBluetooth identifier is host-local,
the Mac must perform its own separately confirmed scan-only provisioning. Its
App Group lease excludes local Sugarman processes only, so a second
non-persisted confirmation gates external phone/app ownership. Mac evidence can
inform protocol timing; it cannot replace final iPhone acceptance. See
[`MACOS_DEVICE_TEST.md`](MACOS_DEVICE_TEST.md).

## Architecture

### One local process owner

`SensorOwnership` uses a non-blocking exclusive `flock` on an empty file in the
shared App Group `group.app.sugarman.sensor-owner`. Both the normal app's
read-only diagnostic runtime and `SugarmanProbe` acquire the same lease before
they may own CoreBluetooth sensor access. Failure to resolve the shared
container or acquire the lock disables sensor access. The file stores no role,
PID, sensor identity, or payload, and process exit releases the kernel lock.

The App Group must be registered in the eventual provisioning setup. Host tests
verify exclusion and release semantics; no signed entitlement was built or
tested here.

### Deterministic foreground reducer

`GS3ForegroundSessionMachine` is the long-lived production core:

```text
idle -> acquire owner -> connect -> discover -> subscribe -> authenticate
     -> load cursor -> durably prepare history -> request history -> sync -> live
                                 ^                                  |
                                 |------ bounded reconnect <--------|
```

- Only one reducer owns connection state.
- Every connection ordinal resets its authentication/history counters.
- Duplicate callbacks fail closed; stale reconnect timer tokens are ignored.
- Durable-plan or batch-commit failure has a payload-free terminal transition;
  it disconnects and releases ownership without retrying or logging the error.
- Disconnect in any connection phase publishes `disconnected` immediately and
  creates at most one reconnect schedule.
- The fixed foreground backoff is 1, 2, 4, 8, then 16 seconds. Exhaustion,
  permission denial, authentication rejection, protocol violation, user stop,
  or leaving foreground releases ownership and cannot reconnect automatically.
- Entering `live` resets the consecutive reconnect attempt count.
- Foreground exit cancels a pending timer, disconnects the adapter, releases
  ownership, and leaves background/restoration work for a later milestone.
- Active-link stops pass through `disconnecting`; cancellation alone does not
  release ownership. A typed transport-completion callback releases the lease.
- A lease-acquisition callback that races with foreground exit is immediately
  unwound, even though the reducer never entered its owned state.
- A canceled connection that reports late success is explicitly disconnected
  again outside connection phases.
- A stopped reducer is terminal; a new foreground session receives a fresh
  reducer instance and process-local session ordinal.

The reducer has no packet type, raw byte buffer, characteristic writer, sensor
identifier, activation, binding, reset, expiry, firmware, or secret-key effect.

### Typed coordinator and CoreBluetooth adapter

`GS3ForegroundSessionCoordinator` is the only executor of reducer effects. It
preflights an existing `.live` / `.v3AES` session before acquiring ownership or
touching the transport, installs one typed event handler, loads and durably
prepares history on every connection, and maps decoded batches into atomic store
commits. Before ownership and again before every history request, it validates
the complete stored time mapping, anchor sample, cursors, and sample set; a
new inconsistency stops before `0x39`. Connection UI projection uses a
field-specific atomic store update so it cannot overwrite a concurrent cursor
or anchor commit. Its inbound event method and the material's frame/decode
methods have package access, so application code cannot extract frames or
inject decoded payloads through the public controller surface.

Transport callbacks enter one bounded `AsyncStream` in source order and one
consumer submits them to the serialized action pump. The coordinator never
creates an independent task per normal callback; a full event buffer is a
terminal protocol violation rather than a reason to reorder or silently drop
input.

The concrete coordinator, transport protocol, ownership provider, scheduler,
and CoreBluetooth adapter are package-only. The sole public construction API,
`GS3ForegroundSessionFactory.makeKnownPeripheralController`, couples the typed
adapter to the real shared App Group ownership provider and bounded scheduler.
Application code cannot replace either dependency or instantiate the adapter
directly.

`GS3ForegroundCoreBluetoothTransport` is deliberately narrower than the later
background design:

- it uses `retrievePeripherals(withIdentifiers:)` for one caller-supplied
  CoreBluetooth UUID and exposes no scan API; an unexpectedly connected or
  connecting retrieved object is canceled before a new attempt can begin;
- it has no restoration identifier or background lifecycle;
- it subscribes to FF31 before authentication and rediscovers/resubscribes on
  each new connection;
- it allows one acknowledged 38-byte authentication frame and one acknowledged
  seven-byte effective-data frame per connection, with one write in flight;
- it requires exact authentication acceptance plus both the CoreBluetooth
  write acknowledgement and observed `0x39` response code/detail before
  treating the connection as synchronized; effective-data packets received
  before both acknowledgements remain bounded in memory and are not persisted;
  a live packet before both is terminal; the post-authentication planning gap
  is also bounded by the operation timeout; and
- it recognizes at most one checksum-valid 24-byte `0x36` before any glucose
  batch, either while authenticated just before history dispatch or while the
  sole typed history write acknowledgement is pending. The coordinator
  independently requires its durably prepared, exactly-once history-request
  state before accepting the receive-only event. The event is named an
  observed history preamble, increments a payload-free per-connection count,
  and grants no write, retry, glucose, acknowledgement, or readiness semantics.
  Any early coordinator event, duplicate, late occurrence, other unsupported
  command, or malformed notification is a terminal protocol violation;
- delegate callbacks must match the active central, peripheral, and exact
  characteristic object, and value/write callbacks are ignored once controlled
  disconnection begins; and
- a controlled cancellation waits for CoreBluetooth's disconnect callback,
  with one bounded completion timeout so the lifecycle cannot retain a stale
  lease indefinitely. Callback timing and that timeout remain physical gates.

CoreBluetooth delegate timing is covered through the typed host state machine,
not claimed as radio evidence. No adapter instance was created during this
implementation or verification.

### Durable history and deduplication

`SugarmanStoring.prepareHistoryRequest` saves the inclusive start before a
typed request can be emitted. It refuses to advance an already prepared start
or skip beyond the last contiguous committed cursor.

`SugarmanStoring.commitSamples` performs one transaction:

1. establish the first sensor-time anchor, including its interval and mapping
   revision, or reject a conflicting anchor;
2. reject samples from another session or timestamps inconsistent with the
   durable anchor;
3. reject conflicting values with the same `(session, sensor index)` key;
4. ignore equivalent duplicates from overlap, including live/history receipt
   and decoder-version metadata differences when decoded sensor content agrees;
5. insert new decoded samples;
6. advance `lastReceivedIndex` to the highest received key;
7. advance `lastCommittedIndex` only through a contiguous run; and
8. save the anchor, samples, and cursors together.

The in-memory actor validates the full batch before replacing its state.
SwiftData inserts and updates under one model-context save and rolls back on a
save failure. An empty batch still requires a prepared request and preserves
any previously known gap count. A gap leaves the committed cursor pinned, so
the next connection repeats the overlap and repairs the missing range.
Sensor-index wrap semantics remain a physical protocol gate; this slice does
not guess them.

### UI projection

Only the reducer's `live` phase projects to domain state `subscribed`.
Discovery, subscription, authentication, history preparation, and sync project
to `connected`; idle, ownership acquisition, backoff, and terminal states
project to `disconnected`. The existing `SafetyEngine` therefore never presents
an old value as current during reconnect or sync, and it independently marks
the reading stale when sensor or receipt age crosses policy.

The normal-app bridge refreshes the existing store-backed dashboard when a
configured controller publishes connection changes, committed samples, or a
typed failure. The release bootstrap currently configures no controller. Thus
the existing stale/disconnected UI is integrated without turning this host
slice into an implicitly enabled sensor path. Even in reducer phase `live`, the
unresolved native state mapping keeps decoded samples `questionable`, so the
dashboard cannot label them current. The isolated Device Test target can
install that same bridge only after an explicit process-local arm confirmation;
the release target does not link its provisioning module.

### Payload-free observability

`GS3LifecycleEvent` records only process-local session/connection ordinals,
monotonic elapsed whole seconds supplied by the adapter, lifecycle phase,
allowlisted error class or CoreBluetooth numeric code, reconnect attempt, and
bounded authentication, history-request, observed-preamble, insert, duplicate,
and gap counts. It contains no UUID, peripheral name, owner field, history
index, glucose value, packet body, private material, or arbitrary localized
error text. History plans, commit results, effects, and ownership leases redact
their operational index/path fields from description, debug, and reflection.

The first protocol rejection in each connection is recorded before disconnect
as one typed, payload-free diagnostic. Its origin is limited to inbound
classification, write-callback, state, or request invariant; optional frame
metadata is limited to a coarse category and byte count capped at 512; and its
timing is an allowlisted lifecycle window. Duplicate diagnostics are suppressed.
Packet bodies, arbitrary command bytes, sensor identifiers, private material,
glucose values, record indexes, imported JSON contents or hashes, and arbitrary
error text cannot enter this type.

PR #17's developer-probe disconnect status is also sanitized before it becomes
the exportable report's final status; non-CoreBluetooth error descriptions no
longer bypass the structured redaction.

The transport event, coordinator, concrete adapter, configuration, active
material, anchor, and commit result also provide redacted debug/reflection
representations. A generic `dump` therefore cannot recursively expose their
private stored fields.

## Scope boundaries

Out of scope remain activation, binding, reset, expiry, firmware, secret-key or
fresh-sensor flows; arbitrary raw writes; HealthKit glucose writes; background
restoration or scanning; signed device artifacts; installation; device
enumeration; physical Bluetooth execution; and TestFlight/App Store
distribution.

This implementation is independently authored from the public repository's
redacted owned-hardware observations and existing Sugarman contracts. It does
not copy or adapt new upstream expression, so it adds no provenance registry
row. This change adds no sensor identifier, private import hash or content,
packet body, or owned-run record index to Git, logs, fixtures, or tests.
