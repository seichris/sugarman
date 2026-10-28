# Sugarman whole-app review — 28 October 2026

Found and locally repaired nine defects: two P1 and seven P2. All nine are **fixed+verified** by the evidence described below; there are no active findings in the final confirming pass. Verification is source/host/build coverage, not physical sensor qualification.

## Original review scope and snapshot

- Repository: `seichris/sugarman`; requested scope: the whole committed app, overriding the skill's usual diff-only scope.
- Reviewed branch: `feat/workout-tab-plans`, HEAD `333a94441068579b6b80723d5a9bc33d6f5d4da4`.
- Local remote-default reference: `cbb6e56e5ebe33c2755c2905771115d54004f2f5`; merge base: `333a94441068579b6b80723d5a9bc33d6f5d4da4`. This is a review of the specified local checkout, not a claim about the current remote head.
- Original final target: HEAD above plus the loop-owned files listed in `.build/review-20261028/manifest.json`.
- Original final source/config/test content SHA-256: `035bce93c33f7043186c798c24a59af6644d540e84b005dd231f05da30b28b2a`. The manifest defines the hashing rule.
- Mode/profile/strategy: `fix-local` / `standard` / `sequential-local`; subagents: **0**; severity gate: **P0/P1/P2**.
- Iterations: **3**, no configured round limit. First pass inspected the app; second pass reviewed the fixes and adjacent contracts and found R9; third pass confirmed the final fixes. Terminal state: **clean** within this source review and verification scope.
- Original checkout remains untouched. Its existing Info.plist, entitlements, project, project.yml, AppStoreLaunch, privacy manifest, and Health sync plan changes were excluded and preserved. The fixes were prepared in an isolated review worktree; the original checkout and its App Store work are excluded from this patch.

## Findings and evidence

### R1 — P1 — Workout edits never update the saved workout

**Trigger/impact:** Open any saved workout, edit a field, and save. The old `WorkoutPlanEditorView.makePlan()` constructed a new plan UUID, phase UUIDs, and creation date. `updateWorkoutPlan` looked up the new UUID, failed with `notFound`, and the editor dismissed, losing the edit.

**Fix:** Extracted the actual editor value state into `Apps/Sugarman/WorkoutPlanDraft.swift:91`, preserving the existing plan ID, creation date, and surviving phase IDs. The detail screen also reconciles its phase selection if an edited phase is removed.

**Verification:** `editingPlanPreservesIdentityAndPersistsTheChanges` failed on the original transformation with five assertions, then passed with the fix. It exercises the editor transformation, real app model, store update, and selected phase. State: **fixed+verified**.

### R5 — P1 — A failed connection-state save suppresses Bluetooth cleanup

**Trigger/impact:** A live session's record is deleted or its connection projection cannot be saved. The coordinator's `.publishConnection` catch returned `false`, aborting the remaining disconnect/release effects. A user stop could leave the transport connected; a terminal disconnect could retain the process ownership lease.

**Fix:** `Sources/GS3Transport/GS3ForegroundSessionCoordinator.swift:411` continues terminal cleanup when the reducer is already disconnecting/stopped. Nonterminal storage failures still transition to the existing controlled stop.

**Verification:** `stopStillDisconnectsWhenConnectionProjectionCannotBeSaved` and `terminalDisconnectReleasesOwnershipWhenProjectionCannotBeSaved` both failed before the fix and passed afterward. Tests check disconnect dispatch, lease retention until acknowledgement, eventual release, and absence of reconnect scheduling. State: **fixed+verified**.

### R2 — P2 — Workout write failures are silently dismissed

**Trigger/impact:** A workout insert/update fails (for example, persistent storage is unavailable). The model swallowed the error and the editor always dismissed. A subsequent successful refresh could erase the only storage error. Template-import and deletion failures were also invisible on the Workout screen.

**Fix:** Add/update return success and retain a separate action error. The editor dismisses only on successful persistence and otherwise keeps the draft visible with the error. The Workout screen shows catalog/delete failures too.

**Verification:** `failedWorkoutWritesReturnFailureAndKeepAnActionableError` exercises the real app model with the fail-closed store. Inspected the editor's conditional dismissal at `Apps/Sugarman/WorkoutPlanEditorView.swift:104`; iOS builds pass. State: **fixed+verified**.

### R3 — P2 — Empty-session charts show another sensor's readings

**Trigger/impact:** Select a new/empty sensor session while an older one has readings. Both History and workout detail fell back to `model.samples` when the selected session was empty, drawing unrelated readings under the selected-session context.

**Fix:** Both charts exclusively consume `model.activeSamples`; History also uses that scoped collection for its chart visibility condition (`Apps/Sugarman/HistoryView.swift:25`).

**Verification:** `emptySelectedSessionDoesNotBorrowOtherSensorSamples` verifies the two-session model scenario. UI call-path inspection confirms both former fallbacks now use that same tested selection. Builds pass; no simulator UI interaction was performed. State: **fixed+verified**.

### R4 — P2 — Live screen omits its promised no-dosing notice

**Trigger/impact:** Opening Live showed the glucose hero/chart without the notice required by README's product posture. `NoDosingBanner` existed but had no live-screen caller; the disclaimer was only on Privacy.

**Fix:** Render the existing accessible banner unconditionally at the top of Live (`Apps/Sugarman/DashboardView.swift:39`), including empty/onboarding and demo states.

**Verification:** Source reachability inspection confirms the banner precedes all content branches. Both shared iOS app targets build. Visual layout and VoiceOver were not exercised interactively. State: **fixed+verified**.

### R6 — P2 — Deleted live sessions can be recreated on relaunch

**Trigger/impact:** Delete the provisioned session from Privacy while durable connection intent remains enabled. The old code only deleted store rows; the controller kept running until a later error, and bootstrap could call `ensureLocalSession`, recreate the same session, and backfill deleted readings.

**Fix:** Provisioning summaries expose the local linked session UUID without adding it to diagnostic descriptions. `AppModel.deleteSession` stops the matching controller and requires restart intent to be durably disabled before deleting the rows (`Apps/Sugarman/SugarmanApp.swift:1421`). Private connection material remains available for a later explicit reconnect. Device Test stops its matching foreground controller.

**Verification:** `deletingProvisionedSessionDisablesRestartIntent` uses synthetic in-memory provisioning and checks the actual model deletion path, absent session, disabled intent, and disabled connection. R5's tests cover cleanup after a record disappears. State: **fixed+verified**.

### R7 — P2 — Local exports survive deletion and remain shareable

**Trigger/impact:** Export JSON/CSV, then delete a session or all local data. Temporary share files still contained the removed readings, and Privacy retained its ShareLink.

**Fix:** Remove only the three known Sugarman export filenames through `PrivacyExportFileWriter.removeExports` (`Sources/Integrations/PrivacyExportFile.swift:17`). Both deletion paths call it. Privacy clears the share URL and serializes export/deletion actions; deleting all data also disables the diagnostic probe.

**Verification:** `deletingSessionRemovesExportCopiesAndPreservesUnrelatedFiles` checks all export formats and preservation of an unrelated file. `deletingAllDataAlsoRemovesExports` covers complete deletion. UI call-path inspection confirms stale links are cleared. Copies already exported to other apps are outside the app's local deletion scope. State: **fixed+verified**.

### R8 — P2 — Persisted subscription is treated as a current connection

**Trigger/impact:** Relaunch after an unclean exit with a recent sample and a stored `.subscribed` session, or encounter a failure to persist disconnection. `activeConnection` trusted the stored value even if this process had no running controller, allowing a reading to retain connected presentation.

**Fix:** Real-session presentation now requires an enabled/armed connection to the exact provisioned session and uses the current process's callback state (`Apps/Sugarman/SugarmanApp.swift:249`). Demo presentation remains based on its explicit fixture. The Device Test failure callback also stops/disarms its lifecycle.

**Verification:** `persistedSubscriptionDoesNotImplyThisProcessIsConnected` covers fresh-process, enabled, and disabled states using the real app model and safety engine. Device Test branches are separately compiled for simulator and generic iOS. State: **fixed+verified**.

### R9 — P2 — Device Test reuses a stopped controller after backgrounding

**Trigger/impact:** Arm Device Test, background it, then return. The installed factory returned the same single-use controller. After `foregroundEnded`, its reducer is stopped and a second `start()` throws instead of creating the fresh reducer promised by the Device Test guide.

**Fix:** Construct the managed controller inside the installed factory on every foreground entry (`Apps/Sugarman/SugarmanApp.swift:1074`). Keep the link-loss test handle pointed at the new instance. The governance check now requires construction inside the factory rather than the obsolete cached-controller spelling.

**Verification:** Existing `reentryConstructsFreshControllerAndRemoveFactoryStopsIt` verifies lifecycle factory semantics; source inspection and the strengthened governance check verify the app wiring. Device Test simulator and generic-iOS builds passed again after this final change. Physical background/foreground behavior is still a hardware gate. State: **fixed+verified**.

## Verification

| Check | Classification | Evidence |
| --- | --- | --- |
| Baseline governance | passed | `python3 Scripts/check_governance.py` |
| Baseline iOS simulator app build | passed | `sugarman-review-baseline-build.log` |
| Baseline host suite | intermittent pre-existing failure | SwiftData test process exited with signal 11 before fixes; isolated 11-test SwiftData rerun passed. Root cause not established. |
| Direct reproductions | expected failures | Workout editor lost five identity/persistence assertions; both coordinator cleanup tests failed. |
| Targeted app/coordinator regression suites | passed | 7 app-model tests plus 27 coordinator tests |
| Full host suite | passed | `swift test --enable-swift-testing`, **281 tests**, exit 0 |
| iOS simulator builds | passed | Sugarman, SugarmanDeviceTest, SugarmanProbe |
| Generic iOS builds (unsigned) | passed | Sugarman, SugarmanDeviceTest, SugarmanProbe |
| macOS build (unsigned) | passed | SugarmanMacDeviceTest |
| Final Device Test rebuilds | passed | Simulator and generic iOS after R9 |
| Final governance and whitespace | passed | `python3 Scripts/check_governance.py`; `git diff --check` |

Original review logs, source manifest, and patch are retained locally under `.build/review-20261028/` and are not part of the published source. No installations, sensor commands, or physical device actions were performed.

## Coverage and remaining limits

Inspected the production UI flows, app orchestration, domain selection, safety projection, SwiftData/in-memory persistence, exports/deletion, typed protocol decode, provisioning/import boundaries, sensor ownership, foreground/persistent lifecycle, reconnect/history coordination, and diagnostic paths. Checked shared Device Test wiring, build configuration, existing tests, and repository governance. Developer Probe/macOS targets received build and shared-contract coverage, not a complete interactive hardware audit. Reference-only upstream submodules and unrelated App Store launch work were excluded.

Physical BLE/NFC, state restoration after process termination, healthy/error native sensor-state mapping, timestamp accuracy, real sensor handback, and long-running performance remain unqualified by this review. The baseline SwiftData crash is retained as an intermittent verification risk despite the final green suite. No claim of medical accuracy, release readiness, or absence of all bugs is made.

## Publication verification

The authorized publication integrates these fixes onto `main` at `76413bb237a22e754aeaee044769a5a041b5cc2c`. It preserves the newer Apple Health, persisted workout selection, fueling, and release changes. The original checkout and all pre-existing App Store changes remain excluded. The Xcode project diff only registers `WorkoutPlanDraft.swift` in the two shared app targets.

A fourth review pass covered the integrated diff, conflict resolutions, affected callers, and the nine retained findings. No new in-gate findings were identified. Host app tests use an isolated UserDefaults suite and include the current Apple Health bridge. The integrated source/config/test SHA-256 is `9a5987264efd1a80f65506fdd4114a85681c483e23f1b55f64b294ed95f661a2`, using the original manifest's hashing rule and file list.

Pre-publication verification passed: **309 host tests**, all **seven unsigned build configurations** listed above, governance, and whitespace checks. Final verification from the clean published PR head and GitHub CI status are recorded in the PR description and retained local publication manifest. The earlier verification table remains evidence for the original snapshot, not a new whole-app audit of subsequently merged features.

Publication profile: `publish` / `standard` / `sequential-local`, zero subagents, P0/P1/P2 gate, four review iterations carried forward with no configured limit. Ledger: nine fixed+verified, zero active, zero invalidated, zero user-deferred. The final remote head, final confirming-pass count, and terminal state are retained in the publication manifest after remote verification.
