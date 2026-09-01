# Sugarman macOS Device Test

## Purpose and current status

`SugarmanMacDeviceTest` is an isolated macOS application target for faster
owned-hardware iteration with the same typed GS3 foreground controller used by
the iPhone Device Test. It is also the first reusable application shell for a
possible future Sugarman Mac product. It is not a production Mac release and it
does not replace final iPhone acceptance.

The target first passed an unsigned generic macOS build, then separately
confirmed exact artifacts were signed, launched, provisioned through the
bounded scan-only route, armed for one managed foreground connection, stopped,
and quit. The first run reproduced the iPhone's payload-free inbound-
classification failure before the history-write acknowledgement. The next
exact diagnostic run proved that the rejected frame reached the known,
checksum-valid 24-byte observed-preamble branch after durable coordinator
history intent but while the transport was still `authenticated`.

The next exact artifact at commit `5ef4ad4` physically passed that race. It
accepted one preamble after durable history intent, acknowledged the sole
history write, committed history through zero remaining gaps, entered
`subscribed` / reducer phase `live` after a committed live notification, and
later durably increased its sample count while still live. It used no second
request, retry, or reconnect, then stopped and exited cleanly. This is the first
managed Mac history/live-reading pass. The earlier official Android handback
establishes sensor/history availability only; handback after the successful Mac
run remains open.

A longer run of that same exact artifact then durably committed five
consecutive live samples at approximately 60-second intervals with no extra
authentication/history request, reconnect, rejection, or gap. A later exact
Device-Test artifact exercised one live-only CoreBluetooth cancellation: the
managed lifecycle scheduled exactly one reconnect, freshly subscribed and
authenticated, made one inclusive history request, deduplicated its overlap,
committed the next live sample, and stopped without a second reconnect. This
was an injected cancellation through the link-loss path, not a spontaneous RF
loss. Sequential private comparison with the official app and iPhone parity
remain open. See
[`GS3_DEVICE_TEST_PHYSICAL_RESULT_2026-09-01.md`](GS3_DEVICE_TEST_PHYSICAL_RESULT_2026-09-01.md).
Every future build and physical action remains separately gated.

## Reused production boundaries

The Mac target reuses:

- `SugarmanStore` and its macOS SwiftData persistence;
- strict Probe JSON validation and normalized, Mac-local Keychain storage;
- the bounded exact-name scan-only adapter;
- the kernel-backed App Group process-owner lease;
- the typed known-peripheral transport with only authentication and
  effective-data requests;
- the same coordinator, history cursor, deduplication, reconnect, and
  payload-free lifecycle diagnostics;
- a separate Device-Test-only, live-only, at-most-once link-loss injector with
  no frame encoder or write surface; and
- `GS3ForegroundSessionLifecycle`, shared by iOS and macOS so delayed creation
  or start cannot outlive the foreground scene that requested it.

The SwiftUI shell owns only application state and presentations. Protocol,
scanner, ownership, provisioning, and lifecycle behavior remain in reusable
package products rather than the view hierarchy.

## Mac-specific ownership boundary

A CoreBluetooth peripheral identifier observed on an iPhone is not a portable
Mac provisioning value. The Mac route therefore imports the existing Probe
JSON only into a cleared process-memory buffer, then requires a separate
confirmation before one ten-second exact-name scan resolves this Mac's local
identifier. The scan cannot connect, discover GATT, subscribe, authenticate,
request history, or write.

The App Group lease excludes cooperating Sugarman processes on the same Mac. It
cannot exclude an official app on a phone. A second
`GS3DeviceTestExternalOwnershipGate` therefore requires a human confirmation
that every phone and app has released the owned sensor before either scanning
or arming. The confirmation is process-local, is never persisted, and is
revoked after scanning, stopping, a failed arm, or background shutdown.

## Privacy boundary

The Mac shareable report contains only bounded lifecycle descriptions and typed
write-acknowledgement counts. It excludes sensor and peripheral identifiers,
private names and material, record indexes, packet bodies, arbitrary command
bytes, glucose values, imported JSON contents and hashes, file paths, and
arbitrary error strings.

Recent values and timestamps may be rendered for private side-by-side owner
comparison inside the app. They are excluded from the bounded shareable report
and must remain outside source control and shared diagnostics.

The imported Probe file remains private evidence. Its normalized material is
stored under a Mac-specific Keychain service using
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; it does not reuse the iPhone
Keychain item. The sandbox permits Bluetooth and user-selected read-only file
access only.

## Build and physical gates

An unsigned compile-only check is:

```sh
xcodegen generate
CC="$PWD/Scripts/xcode-clang-wrapper.sh" xcodebuild \
  -scheme SugarmanMacDeviceTest \
  -destination 'generic/platform=macOS' \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO SDK_STAT_CACHE_ENABLE=NO
```

Building does not authorize running. Each of these requires a new exact
artifact and action confirmation: signing, launching, private-file import,
scan-only provisioning, arming/connecting, disconnect induction, and official
app handback. A Mac physical run can accelerate protocol timing evidence, but
the complete acceptance matrix must still pass on the intended iPhone product
path. The five-reading and injected-reconnect gates have passed on Mac only.

## Provenance

The Mac shell and shared device-test execution boundaries are independently
authored around existing reviewed Sugarman interfaces. They add no adapted
upstream expression and require no new provenance registry entry.
