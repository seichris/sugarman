# Mainland China SiBionics GS3 support for Sugarman

- Status: P1/P2 and one-value already-active iPhone interoperability passed for one owned sensor on 2026-08-30; official Android handback also passed. The exact typed-observability Device Test artifact at commit `3ffbfcd` later failed closed after one history intent and identified the first rejection as inbound classification of a 24-byte notification candidate while the transport was still `authenticated`; no history write acknowledgement, preamble, sample, retry, or reconnect occurred. This narrows the timing failure but does not identify or authorize accepting the command. Five-reading durability, final `0x36` product meaning, zero-unsupported-command behavior, iPhone reconnect, timestamp parity, native state mapping, and sensor-index wrap remain incomplete. The branch now also contains an isolated macOS Device Test that reuses the typed controller, scan-only provisioning, local process lease, a non-persisted cross-device release confirmation, and payload-free reporting. It is future Mac-product groundwork and can accelerate physical timing tests, but has only been built unsigned and cannot replace final iPhone acceptance. The normal release bootstrap still installs no controller factory or active-session material. A signed exact artifact and fresh action confirmation gate every physical run. See [`GS3_FOREGROUND_PRODUCTION_DESIGN.md`](GS3_FOREGROUND_PRODUCTION_DESIGN.md), [`GS3_DEVICE_TEST_PROVISIONING.md`](GS3_DEVICE_TEST_PROVISIONING.md), [`GS3_DEVICE_TEST_PHYSICAL_RESULT_2026-09-01.md`](GS3_DEVICE_TEST_PHYSICAL_RESULT_2026-09-01.md), and [`MACOS_DEVICE_TEST.md`](MACOS_DEVICE_TEST.md). Fresh activation remains unresolved.
- Date: 2026-08-28
- Product: Sugarman — glucose monitoring and fueling insight for endurance athletes

## Executive decision

Build Sugarman as a new, native Swift/SwiftUI application. Keep
`upstream/xdripswift` and `upstream/Juggluco` as pinned research references;
do not add either submodule to an Xcode target or treat either as a build
dependency.

The selected implementation route is GPL adaptation. Before any upstream code
is copied, translated, or adapted, Sugarman must adopt `GPL-3.0-or-later`, add
the provenance workflow in this plan, and preserve all applicable notices.

The product goal is full Mainland GS3 support, not a throwaway MVP:

1. take over an already activated sensor belonging to the same owner;
2. activate and run a new owned sensor;
3. recover current and historical readings across normal iOS background and
   reconnection conditions;
4. present trustworthy connection age and glucose state during endurance
   activities;
5. write validated glucose to HealthKit, read workouts with permission, and
   export the user's data.

Testing will start locally on owned hardware. App Store distribution through
the WEB3 Apple Developer team is a later release gate, after a lean legal review
has been expanded enough to cover GPL/App Store compatibility, interoperability,
vendor terms, cryptography/export declarations, privacy, and medical/wellness
positioning.

Two technical questions originally blocked protocol implementation and now
have evidence-backed answers for one owned sensor/app/library combination:

1. Does the available Mainland GS3 use Juggluco's RC4/V1.20 path, the AES-OFB
   "V3" path alleged by the shared LLM conversations, or another firmware
   variant?
2. Juggluco constructs its initial authentication from six bytes derived from
   the Android-visible Bluetooth device address. CoreBluetooth exposes an
   opaque peer UUID instead of that Android-style MAC address. Sugarman must
   prove a legitimate source for the required six bytes from the package, NFC,
   advertisement, Device Information service, or another readable field.

See [`P1_OWNED_HARDWARE_RESULT_2026-08-30.md`](P1_OWNED_HARDWARE_RESULT_2026-08-30.md),
[`P2_OWNED_PROTOCOL_RESULT_2026-08-30.md`](P2_OWNED_PROTOCOL_RESULT_2026-08-30.md),
and [`V3_AUTH_SOURCE_MAP_2026-08-30.md`](V3_AUTH_SOURCE_MAP_2026-08-30.md).
The later glucose and authentication correction is in
[`V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md`](V3_GLUCOSE_NOTIFICATION_SOURCE_MAP_2026-08-30.md).
These results permit offline work; they do not by themselves authorize a live
sensor command.

## Resolved product and project decisions

| Decision | Selected direction |
| --- | --- |
| Distribution | Local Xcode/device builds first; App Store later through the WEB3 Apple Developer team. |
| Licence | GPL adaptation; license Sugarman as `GPL-3.0-or-later` before adapting upstream expression. |
| Legal review | Lean review during local research; full distribution review before external TestFlight/App Store delivery. |
| Support scope | Full support: same-owner handover first, then fresh activation. |
| Hardware | At least two unopened Mainland GS3 sensors, packaging/UDI, an active or otherwise suitable test sensor, an iPhone, and an Android test phone are available. Consuming at least one fresh sensor and running a full 14-day test are authorized after prior gates pass. |
| Official software | The owned Android phone has access to the Chinese official app corresponding to the APK discussed in the shared research. Inventory its exact package, version, signer, and APK hash locally; do not commit or redistribute the APK. |
| iOS baseline | Test phone is on iOS 26.6. Use iOS 26.0 as the working deployment target and current Swift/SwiftUI APIs. Revisit only if App Store reach later justifies supporting an older release. |
| Product posture | Athlete fueling and performance insight. No insulin dosing, diagnosis, treatment recommendation, or automated medical decision-making. |
| Safety | Advanced configurable alarms and Critical Alerts are not an early priority. Reading age, stale/disconnected state, and explicit no-dosing language are mandatory from the first live UI. |
| Data policy | Offline-first. Retain session and glucose history locally until the user deletes it; provide per-session and delete-all controls. No initial cloud backend. Raw diagnostic captures are opt-in, development-only, and automatically expire. |
| Integrations | Initial HealthKit scope: write validated glucose and optionally read workouts. Defer Watch, Nightscout, remote sharing, and other CGM brands. |
| Language and units | English UI initially; support mg/dL and mmol/L presentation. Put all user-facing text in a String Catalog so later localization does not require a refactor. |

## Evidence method and confidence

This plan separates four evidence classes:

- **High confidence:** directly verified at the pinned source revision or in an
  authoritative platform/vendor source.
- **Medium confidence:** the source strongly indicates the behavior, but the
  owned Mainland hardware has not confirmed it.
- **Low confidence:** a guess, incomplete reverse engineering, or an
  uncorroborated LLM claim.
- **Physical gate:** cannot be established without an owned sensor and phone.

The inspected revisions are:

- Sugarman: `bdcf91d053788cb0dda1363ace07044e0c8e36cc`
- xdripswift: `69eb88330a22e7d9969ee94ec6fa87072367fd2e`
- Juggluco: `11d016eb3aeffe77e86d9522f5192e83790b5a21`
- Juggluco's nested libjuice: `80b7ddacb7650a327a5a0ddd17b77044d0654980`

The pins and reference-only policy are documented in
[UPSTREAMS.md](UPSTREAMS.md). Updating a pin is a separately reviewed source,
licence, and binary-provenance change.

### Verified source conclusions

- **High:** Juggluco maps SKU `64221` to one GS3 subtype and SKU `64300` to a
  Chinese GS3 subtype named `si3zh` in
  [`sensoren.hpp`](../upstream/Juggluco/Common/src/main/cpp/sensoren.hpp), around
  lines 880-904. This proves the source author's intended classification, not
  that every Mainland lot uses that SKU or protocol.
- **High for source, medium for Mainland hardware:** the pinned GS3 codec in
  [`interpretgs3.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics3/interpretgs3.cpp)
  builds account-binding, activation, device-information, and history commands;
  RC4-decrypts responses; validates additive checksums; and extracts a
  five-minute processed glucose stream.
- **Low for actual Mainland authentication:** the registered block selected for
  subtype 5 is explicitly annotated `Guess` in
  [`interpret_data.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics/interpret_data.cpp),
  around lines 397-405.
- **High:** [`handleData.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics/handleData.cpp),
  around lines 83-110, obtains the Android Bluetooth address, reverses six bytes,
  and supplies them to initial authentication.
- **High:** Apple's `CBPeer.identifier` is a system-assigned UUID, not the
  Android Bluetooth MAC value. See
  [Apple's identifier documentation](https://developer.apple.com/documentation/corebluetooth/cbpeer/identifier).
- **High:** xdripswift contains no SiBionics or GS3 implementation. Its useful
  contribution is iOS BLE/background, notification, persistence, HealthKit, and
  export design evidence.
- **High:** Juggluco's full Android build expects native `.so` files extracted
  from an APK. See
  [Juggluco's README](../upstream/Juggluco/README.md), around lines 26-37. The
  inspected RC4 GS3 decoder itself appears source-implemented and reads processed
  glucose values, so the full-build binary requirement is not proof that the
  RC4 GS3 path needs a vendor algorithm library.
- **High:** the public GS3 product page describes initial NFC interaction, a
  one-hour warm-up, five-minute Bluetooth updates, and 14-day sensor life and
  memory. These are product acceptance targets, not proof of EU/Mainland
  protocol equivalence. See the
  [official GS3 page](https://en.sibionics.com/GS3/index.html).
- **High:** the current Mainland `硅基动感健康` listing describes Bluetooth
  streaming, historical review, alarms, and AGP reports. See the
  [Mainland App Store listing](https://apps.apple.com/cn/app/%E7%A1%85%E5%9F%BA%E5%8A%A8%E6%84%9F%E5%81%A5%E5%BA%B7/id6755506502).

### Shared-conversation evaluation

The research conversations are useful hypothesis indexes, not implementation
specifications:

- [Grok shared conversation](https://grok.com/share/bGVnYWN5LWNvcHk_9f1b127a-3b0e-4a74-bdd7-83a0f83fd3b9)
- [ChatGPT shared conversation](https://chatgpt.com/share/6a9116a7-cba0-83ea-94f4-324a9bf4d7d7)

Both opened successfully. Corroborated leads include the FF30/FF31/FF32 GATT
shape, account binding, SKU `64300`, xdripswift's lack of GS3 support, and the
value of xdripswift's background BLE lifecycle.

The following claims remain unverified and must not be copied into production:

- the APK hashes, protected DEX details, native library exports, AES-OFB frame
  layouts, AppKey registration-token format, and Chinese API endpoints described
  in the ChatGPT conversation;
- the assertion that all current Mainland GS3 devices use AES V3;
- the competing assertion that Mainland GS3 needs only a one-line RC4 subtype
  change;
- the assertion that the sensor universally allows only one BLE central;
- any proposed arbitrary account ID, rooted-app credential extraction, or
  undocumented server login route.

The public ChatGPT share displayed links to a generated report and evidence
bundle, but did not expose those artifacts for independent inspection. The
owned Android app/APK therefore becomes a local research input: hash and inspect
it under the legal/provenance rules below, without checking the APK, credentials,
owner/runtime secrets, or vendor binaries into Git. A later approved source-map
pass recorded one fixed non-owner protocol constant under the narrower policy in
[`THIRD_PARTY.md`](../THIRD_PARTY.md).

The conversations also contradict themselves about whether the subtype-specific
registered block applies to GS3. The pinned code sends subtype-based
authentication before its GS3 account-binding state machine. Protocol
classification is therefore Physical Gate P2, not an assumption.

## Product goal and user journeys

### Product goal

Sugarman should give endurance athletes a reliable, glanceable view of current
glucose, trend, data age, and sensor connectivity, then correlate the glucose
timeline with workouts and user-recorded fueling events. It may help users
observe their own fueling patterns, but must not claim to diagnose glucose
conditions or prescribe carbohydrate, medication, or insulin doses.

### Primary journeys

1. **Inventory and onboard an owned sensor**
   - Scan the package Data Matrix or read the sensor's NDEF tag.
   - Display the parsed product, SKU/GTIN, redacted serial, region hypothesis,
     and protocol-confidence evidence.
   - Require confirmation before storing identity data or sending a command.

2. **Take over an already activated sensor**
   - The owner disconnects or force-stops the official app.
   - Sugarman authenticates with the same legitimate owner binding.
   - It obtains current glucose and backfills missed history.
   - The official app remains usable after Sugarman releases the connection.

3. **Activate a new sensor**
   - Show the exact sensor, account-ID source, protocol variant, app build, and
     irreversible nature of activation.
   - Require a fresh confirmation immediately before activation.
   - Bind only to the legitimate owner's account and model the warm-up state.

4. **Monitor an endurance activity**
   - Show glucose, trend, reading age, connection status, and stale state at a
     glance while the phone is locked or the app is backgrounded.
   - Record workout/fueling context without presenting medical instructions.

5. **Recover after interruption**
   - Reconnect after range loss, Bluetooth toggles, suspension, memory
     termination, and normal relaunch.
   - Resume from the last durably stored sensor index and de-duplicate history.

6. **Review and export**
   - Overlay permitted HealthKit workouts with glucose and fueling events.
   - Write physically validated glucose to HealthKit.
   - Export versioned CSV/JSON without credentials, authentication material, or
     raw BLE payloads.

### Initial non-goals

- insulin dosing, automated insulin delivery, diagnosis, or treatment advice;
- automated carbohydrate prescriptions or claims that a fueling strategy is
  clinically optimal;
- sensor-life extension, expiry/reset bypass, account-binding bypass, arbitrary
  IDs, brute forcing, or support for sensors not owned by the tester;
- silent extraction of credentials or account IDs from the official app;
- concurrent collection with the official app until the physical sensor proves
  it safe;
- cloud accounts, family sharing, Watch collection, Nightscout, or other CGM
  brands before GS3 collection is stable;
- shipping any Android `.so`, APK library, or undocumented vendor SDK.

### Definition of full Mainland China GS3 support

Full support requires all of these outcomes:

1. Mainland identity is established from package/UDI, official-app
   compatibility, and observed device information, not only a local name or
   `CN` suffix.
2. Package Data Matrix onboarding works, and NFC onboarding works where the
   physical tag and Core NFC permit it.
3. Sugarman determines the protocol generation without speculative activation
   writes.
4. Authentication and binding use only a legitimate owner identifier.
5. Both same-owner handover and fresh activation work.
6. Current and historical readings preserve the sensor's own indices and
   survive reconnects without duplication.
7. Values, timestamps, trends, warm-up, error, and end-of-life states are
   compared with the official app/export across real sessions.
8. Background collection, stale-state handling, HealthKit, and export pass the
   physical acceptance gates below.
9. At least two Mainland sensors from different lots or firmware revisions are
   tested, including one full 14-day session.

If only handover or only activation works, document that capability as partial
support rather than calling the Mainland GS3 implementation complete.

## Exact upstream source map

All entries refer to the pinned commits listed above.

| Area | Exact evidence | Use in Sugarman |
| --- | --- | --- |
| Android scanning and reconnection | [`SensorBluetooth.java`](../upstream/Juggluco/Common/src/main/java/tk/glucodata/SensorBluetooth.java), especially lines 123-225, 291-340, and 817-848. | Android-only behavioral reference. Do not port Android scanning APIs. |
| GS3 GATT session | [`Si3GattCallback.java`](../upstream/Juggluco/Common/src/mobileSi/java/tk/glucodata/Si3GattCallback.java), especially lines 67-115, 149-184, 223-292, and 337-367. | Behavioral reference for FF30, notify FF31, write FF32, subscribe/authenticate ordering, and reconnect. Actual advertisements and characteristics require hardware evidence. |
| Region and Device Information | [`Si3GattCallback.java`](../upstream/Juggluco/Common/src/mobileSi/java/tk/glucodata/Si3GattCallback.java), lines 223-270. | Negative design evidence: region detection is coupled to debug logging. Sugarman must never do this. |
| Data Matrix onboarding | [`PhotoScan.java`](../upstream/Juggluco/Common/src/mobileSi/java/tk/glucodata/PhotoScan.java), lines 199-225 and 270-320; [`sensoren.hpp`](../upstream/Juggluco/Common/src/main/cpp/sensoren.hpp), lines 880-904. | Reimplement camera UI with Vision/VisionKit. Adapt the validated SKU/parser facts under GPL with provenance. |
| NFC onboarding | [`Sib3Scan.java`](../upstream/Juggluco/Common/src/mobileSi/java/tk/glucodata/Sib3Scan.java), lines 30-94 and 150-231; [`sibionics3/java.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics3/java.cpp), lines 109-153. | Android UI is behavioral only. Port only validated parser behavior; use Core NFC NDEF APIs. The existing offset-based parser is brittle and needs bounds checks plus real fixtures. |
| Sensor classification and state | [`SensorGlucoseData.hpp`](../upstream/Juggluco/Common/src/main/cpp/SensorGlucoseData.hpp), lines 1181-1193 and 1259-1278. | Behavioral/data reference. Do not reuse the packed global-state persistence design. |
| Initial authentication | [`handleData.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics/handleData.cpp), lines 83-110; [`interpret_data.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics/interpret_data.cpp), lines 397-459. | GPL protocol adaptation after P1/P2. Address material and subtype-5 registered block must be physically confirmed. Do not expose owner/runtime key material in plans, logs, or diagnostics. |
| Account binding, activation, history | [`interpretgs3.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics3/interpretgs3.cpp), lines 51-213. | GPL protocol adaptation into a pure Swift codec after protocol classification. |
| Decryption and decoding | [`interpretgs3.cpp`](../upstream/Juggluco/Common/src/main/cpp/sibionics3/interpretgs3.cpp), lines 342-420 and 428-725. | GPL adaptation. Preserve checksum, ACK, index, backfill, warm-up, and error semantics; fail closed on unimplemented variants. |
| Account UI/server behavior | [`GetGS3ID.java`](../upstream/Juggluco/Common/src/mobileSi/java/tk/glucodata/GetGS3ID.java), lines 59-124 and 147-233; [`GS3ID.java`](../upstream/Juggluco/Common/src/mobile/java/tk/glucodata/GS3ID.java), lines 44-170. | Do not reuse. The inspected email/MD5 flow is not verified for Mainland accounts and logs credential-derived data and tokens in debug mode. |
| Native iOS BLE lifecycle | [`BluetoothTransmitter.swift`](../upstream/xdripswift/xDrip/BluetoothTransmitter/Generic/BluetoothTransmitter.swift), especially lines 1-75, 215-223, 274-355, 471-552, 643-697, and 768-870. | Directly compilable GPL iOS code, but generic and coupled. Adapt its verified lifecycle ideas into a smaller GS3 transport; do not copy raw-frame public logging. |
| Background capabilities | [`Info.plist`](../upstream/xdripswift/xDrip/Supporting%20Files/Info.plist), lines 61-102. | Use NFC, Bluetooth, HealthKit, and `bluetooth-central` as needed. Do not copy the audio background mode. |
| Persistence | [`BgReading+CoreDataProperties.swift`](../upstream/xdripswift/xDrip/Core%20Data/Extensions/BgReading%2BCoreDataProperties.swift), lines 11-27; [`BLEPeripheral+CoreDataProperties.swift`](../upstream/xdripswift/xDrip/Core%20Data/classes/BLEPeripheral%2BCoreDataProperties.swift), lines 10-66. | Design reference only. Sugarman uses a smaller domain model and SwiftData repository boundary. |
| Alarms | [`AlertManager.swift`](../upstream/xdripswift/xDrip/Managers/Alerts/AlertManager.swift), especially lines 106-180, 484-501, and 651-814. | Reimplement a pure safety/stale-state evaluator. Defer broad alarm configurability until transport is stable. |
| HealthKit | [`HealthKitManager.swift`](../upstream/xdripswift/xDrip/Managers/HealthKit/HealthKitManager.swift), lines 69-173. | Reimplement using HealthKit sync identifiers and versions for stronger idempotency. |
| Export | [`DataExporter.swift`](../upstream/xdripswift/xDrip/Utilities/HouseKeeping/DataExporter.swift), lines 87-249. | Do not copy wholesale. It is coupled to xDrip Core Data and has a zero-modulus defect for datasets below 50 readings. |
| Android binary inputs | [Juggluco README](../upstream/Juggluco/README.md), lines 26-37; [`CMakeLists.txt`](../upstream/Juggluco/Common/src/main/cpp/CMakeLists.txt), lines 209-227. | Never link or distribute these Android binaries. The submodule remains a source/behavior reference only. |

xdripswift has no unit or UI test target at this pin. Its apparent maturity is
not equivalent to verified behavior for Sugarman.

## Authorized protocol and hardware-validation sequence

All work in this section uses only owned sensors, phones, packaging, accounts,
and software copies. Do not bypass certificate pinning, cloud authentication,
account ownership, device binding, sensor expiry, or other security controls.

### P0 — establish the physical corpus

For every available sensor, record in a private test inventory:

- package photographs, UDI, GTIN/SKU, lot, expiry, and redacted serial;
- Data Matrix text and NDEF records, with sanitized fixtures for the repository;
- sensor state: unopened, active, expired, or already bound;
- official app package, version, signer fingerprint, and APK SHA-256;
- account region and user-visible account/binding information;
- Android/iOS model and OS version;
- visible sensor firmware, hardware, manufacturer, and official app behavior.

Do not put the APK, credentials, full UDI/serials, tokens, runtime IVs,
registration material, authentication IDs, or other owner-specific secret bytes
in Git. The separately governed fixed protocol constant is not a P0 inventory
value; its publication scope and provenance are recorded in the V3 source map.

Exit evidence: signed-off inventory and sanitized package/NFC fixtures. No BLE
command has been sent by Sugarman.

### P1 — passive BLE and address-material discovery

With the official Chinese app legitimately operating an owned active sensor:

1. Enable Android Bluetooth HCI snoop using normal developer tooling.
2. Capture advertisements, connection establishment, service discovery, and the
   first official authentication exchange.
3. Record advertised service UUIDs, local name, manufacturer/service data,
   Device Information values, connection cadence, and frame lengths.
4. After the official app releases the sensor, use an iOS read-only diagnostic
   target to scan, connect, discover services, and read only characteristics
   documented as readable.
5. Determine whether the six address-derived authentication bytes are available
   legitimately in package/NFC data, advertisement data, a Device Information
   characteristic, another readable characteristic, or a documented transform.

Do not assume UUID `5347`, service-filter behavior, Android MTU 247, a stable
local name, or that CoreBluetooth's UUID can substitute for the MAC input.

Exit evidence: redacted advertisement/GATT map and a reproducible source for the
six address bytes. If no legitimate iOS-accessible source exists, stop and seek
vendor documentation/support rather than guessing.

### P2 — identify the protocol generation

Compare the first legitimate official-app exchanges against distinct
hypotheses:

- **V1.20/RC4:** the capture matches Juggluco's authentication, checksum,
  account-binding, activation, and history-command family after decoding with
  the pinned implementation.
- **V3/AES:** frame lengths and state transitions do not match the pinned RC4
  path and corroborate the AES-OFB/native-library hypothesis.
- **Unknown:** neither hypothesis is sufficiently supported.

Produce a short protocol-identification report containing device/firmware,
capture hashes, redacted frames, method, expected/observed results, and
confidence. Do not implement an automatic "try RC4, then AES" fallback against
a live sensor.

If V3 is observed, stop the RC4 implementation milestone. Inspect the owned APK
under the GPL/provenance and legal rules, seek a vendor SDK/specification where
possible, and create a new evidence-backed V3 source map. Never ship the Android
native library.

### P3 — same-owner, already-active handover

Only after P1 and P2 pass:

1. Establish the legitimate account-ID source without scraping another app's
   private credentials or generating an arbitrary ID.
2. Record the official app's last visible glucose/index/time where available.
3. Release the official app's BLE connection.
4. Connect Sugarman and perform authentication/binding only; do not send
   activation, reset, expiry, or secret-key mutation commands.
5. Request the smallest safe range beginning after the last durably known index.
6. Verify live and history data against official app records/export.
7. Release Sugarman and verify that the official app can reconnect with the
   sensor's account and remaining life unchanged.

Treat simultaneous official-app use as unsupported until the physical sensor
proves otherwise. BLE in general does not prove that this particular peripheral
accepts exactly one central.

Exit evidence: at least 24 hours of same-owner collection, successful backfill
after controlled gaps, and a clean return to the official app.

### P4 — fresh activation

Use an unopened owned sensor only after P3 is stable. Immediately before the
irreversible write, require a fresh confirmation naming:

- package serial/lot;
- protocol variant and evidence report;
- legitimate account-ID source;
- Sugarman build/commit;
- iPhone and OS;
- intended activation environment.

Do not use Juggluco's documented arbitrary-number behavior, try alternate
account IDs or registered blocks, send reset/life-extension commands, or make
multiple speculative activation attempts.

Exit evidence: activation, expected warm-up, first live reading, official-app
ownership check where safe, and no unexplained lifecycle change.

### P5 — longitudinal acceptance

Run:

- one fresh activation through a full 14-day session;
- one same-owner handover;
- at least two Mainland sensor lots or firmware revisions;
- the iPhone on iOS 26.6 and, before App Store release, one additional supported
  physical iPhone/iOS combination;
- foreground, screen lock, overnight background, long workout, out-of-range,
  Bluetooth off/on, memory pressure/termination, normal relaunch, reboot, and
  explicit force-quit cases.

Apple supports BLE central background events and opt-in state restoration, but
force-quitting can prevent relaunch. See the
[Core Bluetooth background guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
and [TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules).

## Native iOS architecture

Use an iOS 26 deployment target, Swift 6 language mode, SwiftUI, Observation,
structured concurrency, and SwiftData behind repository protocols. Keep
CoreBluetooth objects confined to their delegate queue because they should not
be passed freely across actors as domain state.

### Module boundaries

#### `SugarmanDomain`

Pure Swift value types and policies:

- `SensorIdentity`
- `SensorSession`
- `GlucoseSample`
- `ConnectionState`
- `SensorLifecycleState`
- `ProtocolVariant`
- `FuelingEvent`
- `AlarmRule` and `AlarmEvent`

No Apple frameworks, persistence models, UI, logging, or cryptography.

#### `GS3Protocol`

Pure Swift, deterministic protocol implementation:

- packet builders and checksum validation;
- cipher abstraction and the physically verified variant only;
- response framing and malformed-input rejection;
- account binding, activation, device information, history, and live-data
  state-machine events;
- sensor-index and timestamp conversion;
- processed glucose/trend decoding;
- injected validated address/auth/account inputs;
- no CoreBluetooth, Keychain, persistence, UI, or side-effectful logging.

Use explicit variants such as `.v120RC4`, `.v3AES`, and `.unknown`. The `.v3AES`
classification is present only because its primary evidence and source map now
exist. Its already-active typed foreground path is implemented but remains
disabled in the release bootstrap and physically unvalidated for reconnect and
durability. Unknown firmware must fail closed before authentication; no
activation write exists.

#### `GS3Transport`

The implemented M3 foreground adapter owns one `CBCentralManager` on a dedicated
serial queue and exposes typed events to higher layers:

- known-peripheral retrieval by one caller-supplied CoreBluetooth UUID, with no
  scan API;
- service/characteristic discovery and notification subscription;
- one in-flight command at a time;
- operation/response timeout and controlled cancellation;
- reducer-owned bounded single-flight foreground reconnect;
- rediscovery, resubscription, reauthentication, and one history request on
  every new connection;
- exactly one package-scoped typed `0xE2` and one package-scoped typed `0x39`
  command per connection, both written with response;
- no audio background mode and no raw-frame production logging.

Service-filtered scanning, jitter, state restoration, and a stable restoration
identifier remain M5 work after the foreground physical gates pass.

Transport state machine:

`idle -> owner -> connecting -> discovering -> subscribed -> authenticating -> synchronizing -> live -> backoff/ended`

Only idempotent steps may retry automatically. Binding mutation, activation,
reset, secret-key, and lifecycle commands require explicit policy approval.

#### `SensorOnboarding`

- Vision/VisionKit Data Matrix scanning;
- Core NFC NDEF reading;
- bounded package/NDEF parsers;
- versioned SKU/firmware evidence table;
- user-visible confidence and unsupported-format errors;
- no sensor side effects.

Apple supports NDEF tags through Core NFC. One owned active Mainland GS3 now
physically validates an exact four-field NDEF text shape, recorded in
[`evidence/owned-mainland-gs3-ndef-v1.json`](evidence/owned-mainland-gs3-ndef-v1.json).
That single-sensor result does not validate another lot, registration inputs,
authentication, or activation. See
[Core NFC](https://developer.apple.com/documentation/corenfc).

#### `AccountBinding`

- user-entered legitimately obtained account ID initially;
- optional vendor-authorized API adapter only after its endpoint, terms,
  authentication, privacy, and security have been reviewed;
- credentials/tokens in device-only Keychain storage if an API is later added;
- no account credentials or tokens in SwiftData, logs, diagnostics, or exports.

Do not copy Juggluco's email/MD5 login or any LLM-proposed Chinese endpoint.

#### `SugarmanStore`

SwiftData models accessed through repository protocols and a dedicated
`ModelActor`:

- transactional sample/index commits;
- uniqueness on `(sessionID, sensorIndex)`;
- schema migrations and recovery;
- in-memory test configuration;
- file protection compatible with background collection after first unlock;
- local retention until explicit user deletion;
- no CloudKit sync in the initial product.

#### `SafetyEngine`

A pure deterministic evaluator for:

- stale reading and missing-reading state;
- disconnected versus connected-but-no-data state;
- sensor warm-up, error, and expiry;
- later optional high/low/rate thresholds, hysteresis, and snooze.

The live UI must never make an old sample look current. Critical Alerts are
deferred and require a special Apple entitlement. See
[Apple's Critical Alerts documentation](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/criticalalert).

#### `Integrations`

- HealthKit glucose writer;
- optional HealthKit workout reader;
- versioned CSV/JSON exporter;
- later independent adapters for Watch, Nightscout, or sharing.

HealthKit writes use `(sessionID, sensorIndex)` as
`HKMetadataKeySyncIdentifier` and the decoder/protocol revision as
`HKMetadataKeySyncVersion`. See
[Apple's sync-identifier documentation](https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier).

Do not write samples to HealthKit until the decoder variant passes physical
parity gates. Request only permissions used by the selected features. See
[Apple's HealthKit privacy guidance](https://developer.apple.com/documentation/healthkit/protecting_user_privacy).

#### `SugarmanApp`

SwiftUI features:

- onboarding and evidence review;
- live glucose/trend/data-age/connection dashboard;
- session and workout timeline;
- manual fueling-event entry;
- HealthKit permissions and export;
- sensor/session diagnostics;
- privacy, retention, and deletion controls.

All user-facing text lives in an English String Catalog even though additional
locales are deferred.

### Data model

`SensorIdentity`

- local UUID;
- product/SKU/GTIN;
- redacted serial and optional UDI fields;
- CoreBluetooth peer UUID;
- observed firmware, hardware, and manufacturer;
- protocol variant and classification-evidence revision.

`SensorSession`

- sensor identity;
- activation, warm-up, expected end, and actual end;
- account-binding reference, never credentials;
- last requested, received, and durably committed indices;
- protocol/session state;
- latest connection and sensor-error state.

`GlucoseSample`

- stable key `(sessionID, sensorIndex)`;
- sensor timestamp and receipt timestamp;
- canonical integer mg/dL and optional original tenths-mmol value;
- trend/rate and quality/status;
- live or backfill source;
- decoder/protocol revision;
- no raw authentication or packet data.

`WorkoutContext` and `FuelingEvent`

- optional HealthKit workout reference;
- workout start/end/type and user-selected summary fields;
- user-entered carbohydrate amount, label, and timestamp;
- no automated fueling prescription in the initial product.

`ConnectionEvent` and `AlarmEvent`

- timestamp, typed state/reason, duration, and app lifecycle state;
- no account IDs, MAC-like identifiers, packet payloads, credentials, or exact
  glucose values in operational logs.

### Privacy and observability defaults

- Offline-first and no advertising/analytics SDK.
- Local glucose/session/workout/fueling history persists until the user deletes
  it; provide per-session and delete-all controls.
- No CloudKit or custom cloud backend initially.
- Production unified logs contain privacy-marked state transitions, timing,
  counts, firmware/protocol revision, and error codes only.
- Raw HCI/BLE capture is a separate development diagnostic mode, explicitly
  enabled, encrypted locally, and automatically deleted after seven days.
- User-generated support bundles are redacted and never contain credentials,
  account IDs, raw packets, full serials, or glucose history unless the user
  explicitly selects a data export.
- CSV/JSON exports are schema-versioned, declare units/timezone, preserve sensor
  indices, and exclude all protocol/authentication material.

## GPLv3, App Store, binary, and provenance consequences

This is an engineering risk plan, not legal advice.

### Selected GPL adaptation track

Before adapting upstream code:

1. add a root `LICENSE` containing GPLv3;
2. declare Sugarman `GPL-3.0-or-later` in the README and package metadata;
3. add per-file copyright/SPDX notices;
4. add `THIRD_PARTY.md` and a machine-readable provenance registry;
5. document how to obtain the exact corresponding source for every distributed
   build.

Adapting or translating Juggluco's protocol/state-machine expression or copying
xdripswift files means the distributed combined work must remain GPL-compatible.
Preserve notices, mark modifications and dates, provide complete corresponding
source and build/control scripts for distributed binaries, and do not impose
further downstream restrictions. Relevant requirements are in GPLv3 sections
5, 6, and 10. See the
[GNU GPLv3 text](https://www.gnu.org/licenses/gpl-3.0.en.html).

### App Store gate

Do not assume that publishing the source makes App Store delivery compliant.
Apple distribution/signing terms and GPLv3's no-further-restrictions rule create
a compatibility risk. Local owner-device development can proceed after the lean
review, but before external TestFlight or App Store submission the WEB3 team
must obtain a written legal conclusion covering:

- GPLv3 and Apple's current developer/distribution agreements;
- exact corresponding-source delivery and notices;
- whether additional upstream permission is needed;
- custom cryptography/export declarations;
- interoperability and vendor terms;
- health-data privacy and target jurisdictions;
- athlete-wellness versus medical-device claims;
- whether the WEB3 App Store provider is the appropriate legal entity.

Apple gives medical hardware and health-accuracy claims heightened scrutiny.
See the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

If counsel blocks GPL-derived App Store distribution, the decision point is to
seek additional permission from all relevant rightsholders or establish a
separate clean-room implementation. Do not silently relicense adapted code.

### Third-party binaries

Never add the Juggluco `.so` files, `.aar` files, APK, alleged
`libcxm_protocol.so`, or any undocumented vendor binary to Sugarman:

- Android ELF binaries are not native iOS dependencies;
- source availability, copyright, licence, redistribution, and export status
  are not established;
- extracting a file from an APK does not grant redistribution permission;
- the submodules are explicitly reference-only;
- if the physically observed V3 variant requires a vendor algorithm, obtain a
  documented iOS SDK with written redistribution terms or stop.

### Provenance workflow

Every adapted unit must have a record containing:

- upstream project and URL;
- pinned commit and source path;
- source blob SHA;
- copyright holders and `git blame`/history reviewed;
- file-header and repository licence evidence;
- purpose and behavior taken;
- reuse mode: `verbatim`, `adapted`, `behavioral`, or `independently observed`;
- Sugarman destination path;
- modification date and author;
- fixtures' origin and capture hash;
- reviewer and legal-review status.

Implementation rules:

1. Preserve upstream headers and add an explicit modification notice.
2. Keep each adaptation in a narrow commit.
3. Never copy implementation text from an LLM transcript.
4. Separate public sanitized fixtures from private hardware evidence.
5. Maintain SPDX/REUSE metadata and an SBOM.
6. Add CI checks that no `upstream/` path, `.so`, `.aar`, APK, or unexplained
   binary enters an Xcode target or release archive.
7. Require a provenance entry for every adapted file/algorithm.
8. Require two-person review for crypto, authentication, binding, activation,
   reset/lifecycle commands, and licence records.
9. Tag the exact source corresponding to every externally distributed build.

## Milestones and exit gates

The sequence deliberately builds the durable architecture around evidence. It
does not discard handover work when fresh activation is added.

### M0 — governance and repository foundation

Deliverables:

- root GPL-3.0-or-later licensing and notices;
- provenance registry/template and binary-exclusion CI policy;
- lean legal note for local interoperability research;
- private owned-device/APK evidence storage policy;
- iOS 26 app/package/module skeleton and test targets;
- explicit safety/no-dosing product language.

Exit gate: GPL adoption is recorded, upstreams remain reference-only, and local
research scope is legally reviewed.

### M1 — owned-hardware evidence lab

Deliverables:

- P0 sensor/package/app inventory;
- sanitized Data Matrix and NDEF fixtures;
- Android HCI captures and read-only iOS GATT map;
- six-byte address-material finding;
- RC4 versus V3 protocol-identification report;
- firmware/SKU support matrix.

Exit gate: P1 and P2 pass. This gate passed for one owned active sensor on
2026-08-30; another lot remains a generalization gate.

### M2 — offline GS3 protocol library

Deliverables:

- pure Swift implementation of only the verified protocol variant;
- checksum/cipher/packet/session-state tests;
- malformed-input and fuzz coverage;
- redacted trace replay;
- provenance records for each adapted algorithm.

Exit gate: all offline vectors, replay, negative tests, and provenance review
pass. No live activation/reset command exists yet.

### M3 — same-owner handover proof

The current foreground slice implements process ownership, deterministic
reconnect sequencing, per-connection subscribe/auth/history, a typed known-peer
CoreBluetooth adapter, atomic time-anchor (including cadence/revision),
overlap/deduplication persistence, and
fail-closed UI projection. The release bootstrap provides no material or
controller factory, and no adapter instance has been physically run. Binding,
scanning, background restoration, and physical validation remain out of scope.
See
[`GS3_FOREGROUND_PRODUCTION_DESIGN.md`](GS3_FOREGROUND_PRODUCTION_DESIGN.md).

Deliverables:

- typed foreground known-peer CoreBluetooth transport (implemented; physical
  gate pending);
- connect/discover/subscribe/reauthenticate/history path without scan or bind
  (implemented; physical gate pending);
- durable sensor-index/time-anchor storage, including the mapping revision, and
  history backfill (host-tested; physical gate pending);
- live dashboard showing connection and reading age;
- release-back-to-official-app test.

Exit gate: P3 succeeds for at least 24 hours, controlled gaps backfill without
duplicates, and the official app can resume without ownership/life changes.

### M4 — guarded fresh activation

Deliverables:

- activation policy and fresh-confirmation UI;
- warm-up, first-data, failure, error, and end-state handling;
- crash-safe activation audit record;
- no arbitrary-ID/reset/expiry code path.

Exit gate: P4 succeeds on one unopened sensor and the full lifecycle state is
recorded correctly.

### M5 — production background lifecycle

Deliverables:

- stable CoreBluetooth restoration identifier;
- background central mode and service-filtered scans;
- reconnect/backoff/resubscription/backfill;
- permission/Bluetooth/reboot/force-quit education;
- privacy-safe local diagnostics and battery/latency metrics.

Exit gate: overnight, locked-phone, and long-workout tests plus the transport
fault matrix pass.

### M6 — athlete product features and integrations

Deliverables:

- polished SwiftUI live/history/workout views;
- manual fueling-event log and workout correlation;
- stale/disconnected state and basic optional alerts;
- idempotent HealthKit glucose writing and optional workout reading;
- CSV/JSON export;
- English String Catalog, accessibility, retention, and deletion controls.

Exit gate: HealthKit/export idempotency, privacy review, accessibility, and all
user journeys pass on the physical iPhone.

### M7 — full-session beta and App Store readiness

Deliverables:

- P5 results across at least two lots/firmware revisions;
- one complete 14-day run and one handover run;
- a second physical iPhone/iOS release-matrix check;
- exact release-source and SBOM archive;
- expanded legal/regulatory/privacy review;
- WEB3 team signing, App Store metadata, privacy disclosures, and review notes.

Exit gate: all physical acceptance criteria pass, no unresolved protocol frames
affect safety/data, and GPL/App Store distribution is approved in writing.

## Test strategy

### Protocol tests

- cipher vectors for the verified variant;
- packet checksum, byte order, length, sequence, and account-ID bounds;
- truncated, oversized, malformed, duplicate, and unknown commands;
- plaintext/bootstrap exceptions where physically verified;
- sensor-index wrap, gaps, duplicates, out-of-order history, and repeated ACKs;
- processed mmol/L-to-mg/dL conversion and trend mapping;
- property-based tests and fuzzing for every decoder entry point;
- record/replay against redacted owned-sensor traces.

If fixtures are derived from upstream source rather than hardware, mark them GPL
and record the provenance. Hardware capture remains the final oracle.

### Transport tests

Use a scripted CoreBluetooth abstraction to test:

- permission denied/revoked and Bluetooth unavailable;
- filtered-scan timeout and known-peripheral retrieval;
- service/characteristic/notification failures;
- write acknowledgment, timeout, disconnect, and cancellation;
- restoration at every state-machine boundary;
- disconnect during authentication, binding, history, and durable commit;
- backoff, no double-connect, and no concurrent writes;
- app background, lock, relaunch, restoration, and explicit force-quit behavior.

### Persistence and integration tests

- uniqueness of `(sessionID, sensorIndex)`;
- crash between receipt, database commit, and next-range request;
- migration and corrupted-store recovery;
- deterministic retention and deletion;
- HealthKit sync identifier/version idempotency;
- export schema, empty/small datasets, units, timezone, and ordering;
- workout/fueling correlation without medical recommendation;
- stale/disconnected/warm-up/error/expired presentation;
- notification denial, snooze, timezone, and daylight-saving changes;
- English UI, Dynamic Type, VoiceOver, and high contrast;
- automated assertions that secrets and raw frames never reach production logs.

### Physical acceptance criteria

For every claimed supported firmware/SKU:

- onboarding identifies the sensor without unsafe fallback;
- authentication/binding succeeds only with the legitimate owner identity;
- the command audit shows no unexplained write;
- at least 99% of expected five-minute samples are retained while the phone is
  in range and the app has not been explicitly force-quit;
- recoverable disconnects backfill gaps without duplicates;
- aligned samples match official app/export values after documented unit
  rounding, with every discrepancy investigated;
- warm-up, stale, disconnected, sensor-error, and expired states are visibly
  distinct from a valid current reading;
- a long locked-screen workout and overnight background run succeed;
- HealthKit and exports contain one record per sensor index;
- returning to the official app does not alter account ownership or remaining
  sensor life.

These are software acceptance criteria, not independent clinical validation.

## Risk register and decision points

| Risk | Current assessment | Required response |
| --- | --- | --- |
| RC4 versus AES V3 | Resolved as V3/AES-OFB for the owned app/sensor/library hash; other lots unknown. | Keep an explicit variant allowlist and require evidence before generalizing. |
| Six address bytes unavailable on iOS | Resolved for the owned sensor through readable Device Information `2A25`; other lots unknown. | Verify every supported firmware/lot and fail closed if the field is absent or malformed. |
| V3 runtime IV/registered block/authentication ID | Resolved by exact private replay for this already-active owned sensor/config; no general fresh-registration route exists. | Keep recovered values outside Git/logs, add a reviewed local-material path for the bounded handover only, and separately solve the legitimate fresh config/AppKey/marker route. |
| Subtype-5 registered block is wrong | High impact; upstream calls it `Guess`. | Prove on already-active handover before fresh activation. |
| Mainland account binding/API | High impact; official flow not mapped. | Start with a legitimate documented/manual owner ID. Add network login only with reviewed endpoint and terms. |
| SKU/NFC format drift | Medium/high. | Versioned fixture corpus, bounded parsers, explicit unsupported state. |
| Official-app/local-process concurrency | Two attempts stopped before FF31 while both Sugarman targets were running; a clean Probe-only run reached live data. Contention is a medium-confidence inference, not a proven cause. | Enforce one local sensor owner, terminate scanning on handoff, and test process/restoration contention explicitly. |
| Firmware drift | High over time. | Firmware/protocol allowlist, decoder revision on every sample, fail closed on unknown frames. |
| GPL/App Store compatibility | High distribution risk. | Written legal conclusion before external TestFlight/App Store; seek extra permission or clean room if blocked. |
| Health/medical claims | High review and user-safety risk. | Athlete insight only; no dosing/diagnosis/prescription; evidence-backed marketing. |
| Background reliability and battery | High product risk. | State restoration, filtered scan, durable backfill, local metrics, full-session tests. |
| APK/vendor binary dependency | Unknown. | Never ship Android binary; obtain licensed iOS SDK or stop if source-only implementation is insufficient. |
| Single current iPhone | Adequate for PoC, insufficient for release confidence. | Add one second physical supported iPhone before App Store readiness. |

## Inputs to capture at implementation start

The strategic choices are resolved. M0/M1 still need the following concrete
artifacts, gathered without putting secrets or proprietary binaries in Git:

1. Exact package/UDI/lot inventory for the available sensors.
2. Which available sensor is already active and safe for the first handover.
3. Official Chinese Android app package/version, signer fingerprint, and APK
   SHA-256.
4. User-visible account region and any legitimate documented account-ID route.
5. Android HCI-snoop availability and storage location for private captures.
6. iPhone model, Xcode version, Apple team/bundle-ID plan for local signing.
7. WEB3 Apple Developer legal-entity/team details before App Store work.
8. The exact fresh sensor selected later for the irreversible P4 activation.

These are evidence-collection inputs, not unresolved product-scope questions.
