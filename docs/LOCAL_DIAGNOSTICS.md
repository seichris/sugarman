# Local diagnostics and USB retrieval

Sugarman keeps a small, structured diagnostic log on the iPhone. The log is
written automatically as the app observes lifecycle, sensor, workout, fueling,
storage, probe, and export events. It is an append-only UTF-8 JSON Lines file at
this path inside the app container:

```text
Library/Application Support/Sugarman/diagnostics.jsonl
```

The log is local-only. Sugarman does not upload it and has no analytics or
cloud backend. The records contain event names, timestamps, and bounded
operational counts/state labels. They omit glucose values, location, sensor and
session identifiers, private handover material, packet bytes, and user-entered
fueling text. The separate JSON export remains the deliberate path for raw
glucose and fueling history.

## Export from the app

Open **Privacy → Local diagnostics → Export local diagnostics**. Sugarman
creates `sugarman-diagnostics.jsonl` and presents the normal iOS share sheet.
This is a manual copy; tapping the button does not upload anything.

The existing **Delete all local Sugarman data** action also removes the
diagnostic log. Deleting a single sensor session does not remove the whole log,
so the operational history remains useful until the user chooses all-data
deletion.

## Pull over a trusted USB developer connection

With the iPhone connected and trusted, first list devices and use the exact
CoreDevice identifier (not the display name):

```sh
xcrun devicectl list devices
zsh Scripts/pull_sugarman_diagnostics.sh <core-device-id-or-udid> /tmp/sugarman-diagnostics.jsonl
```

The script uses the equivalent command below and copies only Sugarman's log
from the app data container:

```sh
xcrun devicectl device copy from \
  --device <core-device-id-or-udid> \
  --domain-type appDataContainer \
  --domain-identifier app.sugarman.ios \
  --source 'Library/Application Support/Sugarman/diagnostics.jsonl' \
  --destination /tmp/sugarman-diagnostics.jsonl
```

The phone must be unlocked and the installed build must have created at least
one event. `devicectl` may report that the source is absent for a fresh install
before the app has launched; that is expected and does not change app data.

This path is for app diagnostics, not Apple's unified log or crash reports.
Those remain separate Xcode/`devicectl` artifacts and are not automatically
included in Sugarman's privacy export.
