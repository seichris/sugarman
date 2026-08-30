# Mainland GS3 foreground production lifecycle

## Decision

The first production transport milestone is a deterministic foreground session,
not an extension of the one-shot developer probe. It owns the sensor through
one cross-process lease, repeats subscription and authentication on every new
physical connection, prepares one capture-backed or durable-overlap history
request per connection, commits decoded samples atomically, and makes every
non-live phase fail closed in the UI.

This change implements the safe host-testable core and the shared ownership
gate. It does **not** connect the normal app to a live writer. `GS3ProtocolRequest`
remains empty, `GS3CodecFactory` remains fail closed, and `GS3Transport` still
has no characteristic-write API. The new state machine emits typed integration
intents only. A separate review and physical authorization must approve the
adapter that could execute those two already-active commands.

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
- five consecutive live readings arrive on a managed foreground session;
- the acceptance run has no quarantined command, or `0x36` receives a separately
  reviewed product classification;
- stale and disconnected presentation matches the actual link and reading age;
  and
- official Android handback still succeeds without binding or activation.

No physical action is authorized by this design.

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

### Durable history and deduplication

`SugarmanStoring.prepareHistoryRequest` saves the inclusive start before a
typed request can be emitted. It refuses to advance an already prepared start
or skip beyond the last contiguous committed cursor.

`SugarmanStoring.commitSamples` performs one transaction:

1. reject samples from another session;
2. reject conflicting values with the same `(session, sensor index)` key;
3. ignore equivalent duplicates from overlap, including live/history receipt
   and decoder-version metadata differences when decoded sensor content agrees;
4. insert new decoded samples;
5. advance `lastReceivedIndex` to the highest received key;
6. advance `lastCommittedIndex` only through a contiguous run; and
7. save samples and cursors together.

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

## Scope boundaries

Out of scope remain activation, binding, reset, expiry, firmware, secret-key or
fresh-sensor flows; arbitrary raw writes; HealthKit glucose writes; background
restoration; signed device artifacts; installation; device enumeration;
Bluetooth scanning/connection; and TestFlight/App Store distribution.

This implementation is independently authored from the public repository's
redacted owned-hardware observations and existing Sugarman contracts. It does
not copy or adapt new upstream expression, so it adds no provenance registry
row. Private material, captures, identifiers, record indexes, and import hashes
remain outside Git, logs, fixtures, and tests.
