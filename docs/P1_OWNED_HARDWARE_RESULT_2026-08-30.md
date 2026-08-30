# P1 owned-hardware result — 2026-08-30

## Scope and authorization

This run used an already-active Mainland China SiBionics GS3, the owner's
official Chinese Android app and account, an owned Android phone, and an owned
iPhone 16 Pro Max running iOS 26.6.1. The owner explicitly authorized the
bounded iOS probe after the official app released the sensor.

Tested Sugarman source was pull request #8 head
`4856f8f9be0290e865adf6491851de6e5dcc2f3c`. The signed app's canonical
file-manifest SHA-256 was
`53607588934405819fb9dad0795de933b60dbba15b6080704245f00adc409b9a`.

The public record intentionally omits the sensor's advertised name,
CoreBluetooth identifier, device serials, account data, raw characteristic
values, screenshots, glucose value, and Android HCI payloads.

## Procedure and verified observations

1. The official Android app showed a live reading before release. Android
   Bluetooth was then turned off so the peripheral could advertise.
2. Sugarman's read-only probe found the owned sensor. The presentation-only
   name-format heuristic ranked it first and required an explicit tap.
3. Sugarman connected, discovered services and characteristics, read only its
   Device Information allowlist, wrote the redacted map locally, and
   disconnected. The success status is assigned only after those operations
   complete.
4. Android Bluetooth was re-enabled. The official app produced a fresh reading
   and trend after the probe, confirming reconnection and continued data flow.

No sensor authentication, binding, activation, reset, characteristic write,
notification subscription, glucose decode, or sensor-level handover was part
of this run.

Confidence is **high** for the observed GATT topology and completed iOS
disconnect, and **high** for official-app reconnection based on the owner's
post-probe live reading. Remaining sensor life and account binding were not
independently inspected after the run.

## Sanitized GATT evidence

The exported schema-v1 map is committed as
[`evidence/owned-mainland-gs3-gatt-map-v1.json`](evidence/owned-mainland-gs3-gatt-map-v1.json).
The exact device-export bytes had SHA-256
`4c5dbfd08cadd094ad507db5bf78e4ff8130e82e7f15d3ad20a61d1b3a24c4fe`.
The committed copy differs only by a final newline required by the repository;
its SHA-256 is
`006f61bda5728727eaa73ceb3ae618baba96195fedbf2de9d693d0163543b740`.

| Service | Observed characteristics | Evidence and interpretation |
| --- | --- | --- |
| Device Information `180A` | `2A24`–`2A29`, `2ABE` | The allowlisted fields were readable. The `2A25` serial value was omitted and only its 17-byte length was retained. `2ABE` was discoverable/readable but was not read. |
| Battery `180F` | `2A19` (`read`, `notify`) | Property discovery only; no battery value was retained and notifications were not enabled. |
| GS3 data `FF30` | `FF31` (`notify`), `FF32` (`write`, `writeWithoutResponse`) | Exact topology match to pinned Juggluco [`Si3GattCallback.java`](../upstream/Juggluco/Common/src/mobileSi/java/tk/glucodata/Si3GattCallback.java) at commit `11d016eb3aeffe77e86d9522f5192e83790b5a21`, file SHA-256 `9a1799201bc379be203414668f2586d2b654a84258caad4f2c1208e5ed91f8f3`. No upstream implementation was copied and no write was sent. |
| MCUmgr SMP `8D53DC1D-1DB7-4CD3-868B-8A527460AA84` | `DA2E7828-FBCE-4E01-AE9E-261174997C48` (`notify`, `writeWithoutResponse`) | UUID and properties match the official [Zephyr SMP BLE transport specification](https://docs.zephyrproject.org/latest/services/device_mgmt/smp_transport.html). This appears to be a firmware-management surface; Sugarman did not interact with it. |

The serial byte count is not authentication-address evidence. No exact six-byte
candidate was retained or compared to the Android HCI peer address, so
`sixByteAddressSource` remains `notFound` and `cipherHypothesis` remains
`unknownUntilCapture`.

## Gate result and next step

The physical scan, explicit selection, GATT discovery, bounded Device
Information read, redacted export, disconnect, and official-app handback gates
passed on this owned setup.

This is **not** Mainland GS3 glucose support and does not authorize a live
authentication attempt. The next protocol step remains offline analysis of the
private official-app Android HCI capture against the pinned Juggluco behavior.
If no legitimate iOS-readable source exactly supplies the required six address
bytes, implementation must stop at that gate rather than derive them from the
opaque CoreBluetooth UUID or guess a transform.
