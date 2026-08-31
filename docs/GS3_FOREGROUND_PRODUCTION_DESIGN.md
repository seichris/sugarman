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

The isolated `SugarmanDeviceTest` target supplies that test boundary without
changing the release bootstrap. It links a dedicated strict private-import
module, stores normalized material only in a when-unlocked this-device-only
Keychain item, and begins every process unarmed. Import prepares local
already-active session metadata but cannot start Bluetooth. Only a separate
in-app arm confirmation installs the existing typed factory. See
[`GS3_DEVICE_TEST_PROVISIONING.md`](GS3_DEVICE_TEST_PROVISIONING.md).

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
under `docs/evidence/`.

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

These are reviewed policies, not claims of physical iPhone reconnect parity.

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
- mapped history timestamps agree with the official app within a predeclared
  tolerance, and the 60-second anchor policy is revised if they do not;
- native sensor-index wrap behavior is captured before any session can cross
  the current `UInt16` boundary;
- five consecutive live readings arrive on a managed foreground session;
- healthy/error/calibration/expiry state patterns are compared with the official
  app before any production sample quality can become `ok`;
- the acceptance run has no unknown or malformed command; if `0x36` recurs, the
  production adapter stops and that command requires a separate product
  classification before any policy can change;
- stale and disconnected presentation matches the actual link and reading age;
  and
- official Android handback still succeeds without binding or activation.

No physical action is authorized by this design or by provisioning/import
alone. Every exact artifact and each physical test action still requires fresh
owner confirmation.

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
- it treats every unknown or malformed notification, including the previously
  quarantined family, as a terminal protocol violation. Production does not
  inherit the one-shot probe's quarantine;
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
bounded counts. It contains no UUID, peripheral name, owner field, history
index, glucose value, packet body, private material, or arbitrary localized
error text. History plans, commit results, effects, and ownership leases redact
their operational index/path fields from description, debug, and reflection.

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
