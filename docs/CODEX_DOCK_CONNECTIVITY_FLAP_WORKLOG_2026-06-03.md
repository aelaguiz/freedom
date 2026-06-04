# Codex Dock Connectivity Flap Worklog - 2026-06-03

## Goal

Monitor the running iPhone simulator and both configured relay hosts,
`Amir-M5` and `home`, to diagnose repeated online/offline or degraded
connectivity states such as `Online 2/2` while the underlying app state is
degraded. Keep observations here as they are gathered. Fix the identified root
cause and prove the fix on both hosts.

## Requirements

- Observe the actual simulator UI, not only unit tests.
- Capture host health for local `Amir-M5` and remote `home`.
- Distinguish process reachability from Dock data freshness.
- Record all meaningful observations with timestamps.
- Do not call the issue fixed until both hosts have current proof.
- Do not call the full user goal complete until the installed app is proven on
  the physical iPhone 17 Pro, or until that proof is explicitly blocked by
  device availability.

## Worklog

### 2026-06-03T23:13:04Z - Investigation started

- Current branch has one intentionally unstaged local file:
  - `AGENTS.md`
- Recent unrelated fix `e037a2d Restore visible thread composer` is committed
  and pushed.
- Existing related prior art:
  - `docs/CODEX_DOCK_STALENESS_ROOT_CAUSE_WORKLOG_2026-05-31.md`
  - `docs/CODEX_DOCK_CONNECTIVITY_DETECTION_AND_DISPLAY_AUDIT_2026-05-31.md`
- Initial code path search found the main connectivity rendering chain:
  - `CodexDock/State/AppConnectivityStore.swift`
  - `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - `CodexDock/State/ThreadCardProjectionState.swift`
  - `CodexDock/Features/Dock/DockView.swift`
  - `scripts/dock-relay-sync-audit.mjs`
  - `scripts/dock-relay-simulator-ui-sync-proof.mjs`

### 2026-06-03T23:13:04Z - Initial code observation

- `HostConnectivityPhase.isOnlineLike` returns `true` for both `.online` and
  `.partial`.
- `AppConnectivityStore.record(hostStates:source:)` maps Dock host
  `.degraded` to `.partial`.
- `AppConnectivityStore.rollup(_:)` returns `.partial(...)` when all hosts are
  online-like but at least one host phase is `.partial`.
- `GlobalConnectivityIndicatorView.displayLabel` renders `.partial` multi-host
  states as `Online N/N`, because it calls `hostCountLabel(prefix: "Online")`.
- This means the UI can display `Online 2/2` while accessibility value says
  `Partial: <host>: <reason>`. That matches the reported confusing state
  shape, but it does not yet prove the source of the continuous flapping.

### 2026-06-03T23:15Z - Scope correction from phone behavior

- User-visible symptom on the physical phone is not only a misleading label.
- The phone randomly drops and stops showing updates.
- Investigation scope is therefore a real fresh-data loss across one of these
  paths:
  - raw app-server to Dock relay;
  - Dock relay state/stream;
  - phone WebSocket stream;
  - Swift stream reconciliation;
  - Swift Dock projection/UI publish.
- UI labeling remains a related problem only if it hides the real stale state.

### 2026-06-03T23:15Z - Initial simulator observation caveat

- First simulator screenshot was launched through Mobile MCP instead of the
  Makefile app path, so it did not inherit the normal two-host
  `CODEX_DOCK_HOSTS` launch environment.
- That invalid snapshot showed only `Amir-M5`, not both configured hosts.
- Artifact kept only as a caveat:
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-current.png`

### 2026-06-03T23:16Z - Valid simulator launch proof

- Re-launched the simulator through the repo-owned command:
  - `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`
- Valid simulator state after relaunch:
  - Global connectivity label: `Online 2/2`
  - Accessibility value: `Online: 2 hosts online`
  - Dock root value included `loaded; rows=1229; visibleRows=1229`
  - Visible rows included both `Amir-M5` and `home` host rows.
- Artifact:
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-after-make-launch.png`

### 2026-06-03T23:15Z - Relay status snapshot

- Captured full relay `statusz` and `readyz` JSON for both configured relay
  hosts.
- Local `Amir-M5` relay:
  - `readyz`: `{"ok":true,"service":"codex-dock-relay","auth":"none"}`
  - `dock/subscribe`: `healthy`
  - `dock/subscribe` last success:
    `2026-06-03T23:14:50.674Z`
  - `dock/subscribe` last measurement: `rowCount: 259`
  - `dock/subscribe` counters: `total: 11`, `succeeded: 11`, `failed: 0`
  - `initialize`: `healthy`
  - app-server history health: `up`
  - reconnect state: inactive.
- Remote `home` relay:
  - `readyz`: `{"ok":true,"service":"codex-dock-relay","auth":"none"}`
  - `dock/subscribe`: `healthy`
  - `dock/subscribe` last success:
    `2026-06-03T23:14:50.849Z`
  - `dock/subscribe` last measurement: `rowCount: 250`
  - `dock/subscribe` counters: `total: 10`, `succeeded: 10`, `failed: 0`
  - `dock/resync`: `healthy`, last success:
    `2026-06-03T22:15:55.028Z`, `rowCount: 250`
  - `initialize`: `healthy`
  - app-server history health: `up`
  - reconnect state: inactive.
- Artifacts:
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/local-statusz-full.json`
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/local-readyz-full.json`
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/home-statusz-full.json`
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/home-readyz-full.json`
- Interpretation: this proves both relays could answer a Dock snapshot at that
  moment. It does not prove that later stream updates kept flowing to the
  simulator or physical phone.

### 2026-06-03T23:18Z - Relay soak harness blocked

- Attempted 2-minute `dock-relay-sync-audit.mjs --mode soak` runs against:
  - `ws://amir-m5.fairy-salmon.ts.net:4510`
  - `ws://home.fairy-salmon.ts.net:4510`
- Both runs failed in the proof-report contract validator, not from a captured
  stream mismatch:
  - `relay-sync-audit failed: proof report contract failed`
  - first reported issue: `<report>: must NOT have additional properties`
- The script did not write `local-soak.json`, `local-soak.md`,
  `home-soak.json`, or `home-soak.md`.
- Interpretation: these two runs are unusable as pass/fail evidence for the
  user-visible phone drop. The harness failure should not be counted as a relay
  stream failure.

### 2026-06-03T23:19Z - Root cause candidate confirmed in code

- The Dock/archive card stream client was using:
  - `AppServerClient(... connectionPolicy: .liveDetail)`
- That creates two reconnect owners:
  - lower layer: generic JSON-RPC WebSocket client;
  - upper layer: `StreamReconciler`, which owns projection snapshots,
    heartbeats, sequence gaps, and `dock/subscribe` / `dock/resync`.
- The lower WebSocket reconnect reopens and re-initializes the JSON-RPC
  connection, but it does not replay a previous `dock/subscribe` subscription.
- Resulting failure shape:
  - relay path can look reachable again;
  - the phone can hold a fresh WebSocket connection;
  - the relay has no Dock subscription on that new socket;
  - the app stops receiving `dock/update` notifications until the projection
    layer notices a heartbeat timeout and recovers later.
- This matches the corrected user report: real updates stop, not only the
  visual connectivity label.

### 2026-06-03T23:20Z - Implemented scoped fix

- Changed only the default card stream connection policy in:
  - `CodexDock/State/AppServerThreadCardStreamClient.swift`
- New default:
  - `AppServerThreadCardStreamClient(... connectionPolicy: .oneShot)`
- Meaning:
  - Dock/archive card streams no longer auto-reconnect underneath
    `StreamReconciler`.
  - On WebSocket loss, the stream closes promptly.
  - `StreamReconciler` sees the closed stream, marks the host degraded/offline
    while preserving rows, reconnects, and performs a fresh `dock/subscribe`.
- Left thread detail unchanged:
  - `AppServerThreadDetailSession` still uses `.liveDetail`.
- Rejected and removed a more invasive alternative that replayed
  `dock/subscribe` inside `AppServerThreadCardStreamConnection`; it failed the
  iOS Swift 6 actor-initializer build and duplicated reconnect ownership.

### 2026-06-03T23:20Z - Regression tests added

- Added:
  - `CodexDockTests/AppServerThreadCardStreamClientTests.swift`
- Coverage:
  - default Dock card stream client uses `.oneShot`;
  - archive card stream client also uses `.oneShot`;
  - injected custom factories do not claim a default reconnect policy.
- Added focused app-server client coverage in:
  - `CodexDockTests/AppServerClientTests.swift`
- Coverage:
  - a one-shot `AppServerThreadCardStreamConnection` finishes its update
    stream when the underlying transport closes;
  - this is the handoff that lets `StreamReconciler` reconnect and perform a
    fresh `dock/subscribe`.
- `rtk xcodegen generate --spec project.yml` was run by Makefile-owned targets,
  which updated `CodexDock.xcodeproj/project.pbxproj` to include the new test
  file.

### 2026-06-03T23:21Z - Physical install blocked

- Attempted:
  - `rtk make iphone-17-pro`
- Failed before build/install because Xcode could not find the physical device:
  - `Unable to find a destination matching the provided destination specifier`
  - destination id:
    `CB9FFF0E-89AD-57B5-9C00-6552D814875E`
- Confirmed with:
  - `rtk make devices`
- Device list showed:
  - `Amir's iPhone  iPhone 17 Pro  CB9FFF0E-89AD-57B5-9C00-6552D814875E  unavailable`
  - `iPhone         iPhone 14      0A4EFF8B-54D8-58FB-B3FB-63263265B9CC  unavailable`
  - `iPhone (5)     iPhone 13 Pro  DA37BD8A-A4EA-5377-937F-AB9EFC324F96  unavailable`
- Physical phone proof is therefore blocked by device availability on this Mac,
  not by a build or signing failure.

### 2026-06-03T23:31Z - Connectivity label masking fix

- The real update-loss fix remains the card stream policy change above.
- A second, smaller UI masking bug was also fixed:
  - `GlobalConnectivityIndicatorView.displayLabel` now renders `.partial`
    multi-host states as `Partial N/N` instead of `Online N/N`.
- Reason:
  - `.partial` still counts as online-like for host reachability, but the global
    chip should not say `Online` when the rollup status is degraded.
- Added a regression assertion in:
  - `CodexDockTests/AppConnectivityStoreTests.swift`
- Expected visible result:
  - if both hosts are reachable but one host has degraded Dock data, the chip
    says `Partial 2/2`, not `Online 2/2`.

### 2026-06-03T23:32Z - Focused Swift verification after label fix

- `rtk swift test --filter AppConnectivityStoreTests`
  - Passed: `18` tests, `0` failures.
  - Includes:
    `testGlobalConnectivityIndicatorPartialLabelDoesNotClaimOnline`.
- `rtk swift test --filter AppServerThreadCardStreamClientTests`
  - Passed: `3` tests, `0` failures.
- `rtk swift test --filter AppServerClientTests`
  - Passed: `53` tests, `5` expected real-host skips, `0` failures.
  - Includes:
    `testThreadCardStreamConnectionFinishesUpdatesWhenOneShotTransportCloses`.
- `rtk swift test --filter DockStoreStreamTests`
  - Passed: `18` tests, `0` failures.

### 2026-06-03T23:33Z - Fresh simulator proof after rebuild

- Rebuilt, installed, and relaunched the simulator app through:
  - `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`
- Result:
  - command exited `0`.
- Then captured a fresh simulator UI dump:
  - `rtk make sim-ui-dump SIM='iPhone 17' SIM_UI_DUMP_DIR='/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-ui-dump-after-partial-label-fix'`
- UI dump result:
  - status: `pass`
  - simulator: `iPhone 17`
    (`DEF1631B-7125-43C6-BFA3-4423BF103C91`)
  - app: `com.aelaguiz.CodexDockApp`
  - screen: `dock -> dock`
  - visible elements: `48`
  - Dock rows: `1229`
- Extracted accessibility evidence:
  - global chip label: `Online 2/2`
  - global chip value: `Online: 2 hosts online`
  - Dock root value includes `loaded; rows=1229; visibleRows=1229`
  - visible row identifiers include both:
    - `codexdock.dock.row.Amir-M5...`
    - `codexdock.dock.row.home...`
- Simulator relay config check:
  - `rtk make sim-config-verify SIM='iPhone 17'`
  - Result: exited `0`.
- Artifacts:
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-ui-dump-after-partial-label-fix/sim-ui-dump.json`
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-ui-dump-after-partial-label-fix/sim-ui-dump.md`

### 2026-06-03T23:33Z - Local restart proof attempt

- Attempted:
  - `rtk make dock-relay-restart`
- Result:
  - command exited `2`.
- Failure:
  - `launchctl bootstrap gui/501 /Users/aelaguiz/workspace/codex-client/.codex-dock/services/com.aelaguiz.codex-dock.app-server.plist failed with exit 5`
- Follow-up health checks immediately after the failed restart attempt:
  - `rtk make app-server-status`
    - `status: ready`
    - raw app-server active: `true`
    - Dock relay active: `true`
    - raw app-server `readyz`: `ok: true`
    - relay `readyz`: `ok: true`
    - relay `statusz`: `snapshotOK: true`
  - `rtk make dock-relay-status`
    - `status: ready`
    - raw app-server active: `true`
    - Dock relay active: `true`
    - raw app-server `readyz`: `ok: true`
    - relay `readyz`: `ok: true`
    - relay `statusz`: `snapshotOK: true`
- Interpretation:
  - this failed target is not proof of app reconnect behavior;
  - it also did not leave the local service path down.

### 2026-06-03T23:35Z - Direct stream probes for both phone relay URLs

- Created a temporary read-only probe outside the repo:
  - `/tmp/codex-client/connectivity-flap-20260603T2315Z/relay-stream-probe.mjs`
- The probe connects, performs `initialize`, sends `initialized`, calls
  `dock/subscribe`, then counts `dock/update` notifications for 22 seconds.
- `ws://amir-m5.fairy-salmon.ts.net:4510`
  - status: `pass`
  - duration: `22049ms`
  - initial snapshot:
    - `kind: snapshot`
    - `seq: 34095`
    - `complete: true`
    - `totalRows: 259`
    - `rowCount: 259`
    - `freshness: fresh`
  - `dock/update` notifications: `5`
  - update kinds: `heartbeat: 5`
  - first update:
    - `2026-06-03T23:35:00.434Z`
  - last update:
    - `2026-06-03T23:35:20.442Z`
  - artifact:
    - `/tmp/codex-client/connectivity-flap-20260603T2315Z/relay-stream-probe-amir-m5-20260603T2334Z.json`
- `ws://home.fairy-salmon.ts.net:4510`
  - status: `pass`
  - duration: `22090ms`
  - initial snapshot:
    - `kind: snapshot`
    - `seq: 8056`
    - `complete: false`
    - `totalRows: 970`
    - `rowCount: 250`
    - `freshness: fresh`
  - `dock/update` notifications: `13`
  - update kinds: `heartbeat: 4`, `page: 9`
  - first update:
    - `2026-06-03T23:35:00.157Z`
  - last update:
    - `2026-06-03T23:35:18.402Z`
  - artifact:
    - `/tmp/codex-client/connectivity-flap-20260603T2315Z/relay-stream-probe-home-20260603T2334Z.json`
- Interpretation:
  - both phone-facing relay URLs can create a Dock subscription and continue
    sending live `dock/update` notifications;
  - this supports the Swift-side root cause because the relays are producing
    updates, while the old app-side `.liveDetail` policy could reconnect without
    resubscribing.

### 2026-06-03T23:35Z - Physical install still blocked

- Retried:
  - `rtk make iphone-17-pro`
- Result:
  - command exited `2`.
  - build log:
    `/Users/aelaguiz/workspace/codex-client/.codex-dock/logs/app-device-build-20260603233530-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log`
- Xcode failure:
  - `Unable to find a destination matching the provided destination specifier:
    { id:CB9FFF0E-89AD-57B5-9C00-6552D814875E }`
- `rtk make devices` also showed the same iPhone 17 Pro as `unavailable`.
- Current completion status:
  - Swift fix is implemented.
  - Simulator proof is current.
  - Both phone-facing relay URLs have current stream proof.
  - Physical iPhone installed-app proof is still missing because CoreDevice does
    not expose the device to Xcode on this Mac.

### 2026-06-03T23:39Z - Continuation: longer relay soak, sim proof, and device blocker

- A longer relay stream probe completed against both phone-facing relay URLs.
- Probe behavior:
  - opened WebSocket;
  - sent `initialize`;
  - sent `initialized`;
  - called `dock/subscribe`;
  - listened for `dock/update` notifications for 120 seconds.
- `ws://amir-m5.fairy-salmon.ts.net:4510`
  - status: `pass`
  - duration: `120050ms`
  - initial snapshot:
    - `kind: snapshot`
    - `seq: 34098`
    - `complete: true`
    - `totalRows: 259`
    - `rowCount: 259`
    - `freshness: fresh`
  - `dock/update` notifications: `28`
  - update kinds: `heartbeat: 24`, `upsert: 4`
  - first update:
    - `2026-06-03T23:36:53.126Z`
  - last update:
    - `2026-06-03T23:38:50.502Z`
  - artifact:
    - `/tmp/codex-client/connectivity-flap-20260603T2315Z/relay-stream-probe-amir-m5-20260603T-continuation-120s.json`
- `ws://home.fairy-salmon.ts.net:4510`
  - status: `pass`
  - duration: `120079ms`
  - initial snapshot:
    - `kind: snapshot`
    - `seq: 8056`
    - `complete: false`
    - `totalRows: 970`
    - `rowCount: 250`
    - `freshness: fresh`
  - `dock/update` notifications: `33`
  - update kinds: `heartbeat: 24`, `page: 9`
  - first update:
    - `2026-06-03T23:36:52.428Z`
  - last update:
    - `2026-06-03T23:38:48.438Z`
  - artifact:
    - `/tmp/codex-client/connectivity-flap-20260603T2315Z/relay-stream-probe-home-20260603T-continuation-120s.json`
- Captured a fresh simulator UI dump after the 120-second relay monitor:
  - `rtk make sim-ui-dump SIM='iPhone 17' SIM_UI_DUMP_DIR='/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-ui-dump-after-120s-relay-monitor'`
  - result: `pass`
  - simulator: `iPhone 17`
    (`DEF1631B-7125-43C6-BFA3-4423BF103C91`)
  - app: `com.aelaguiz.CodexDockApp`
  - state: `runningForeground -> runningForeground`
  - screen: `dock -> dock`
  - Dock rows: `1229`
  - global chip label: `Online 2/2`
  - global chip value: `Online: 2 hosts online`
  - row identifiers include both `codexdock.dock.row.Amir-M5...` and
    `codexdock.dock.row.home...`
  - artifacts:
    - `/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-ui-dump-after-120s-relay-monitor/sim-ui-dump.json`
    - `/tmp/codex-client/connectivity-flap-20260603T2315Z/sim-ui-dump-after-120s-relay-monitor/sim-ui-dump.md`
- Rechecked physical device visibility:
  - `rtk make devices`
  - result:
    - `Amir's iPhone  iPhone 17 Pro  CB9FFF0E-89AD-57B5-9C00-6552D814875E  unavailable`
    - `iPhone         iPhone 14      0A4EFF8B-54D8-58FB-B3FB-63263265B9CC  unavailable`
    - `iPhone (5)     iPhone 13 Pro  DA37BD8A-A4EA-5377-937F-AB9EFC324F96  unavailable`
- Retried physical install:
  - `rtk make iphone-17-pro`
  - result: command exited `2`
  - build log:
    `/Users/aelaguiz/workspace/codex-client/.codex-dock/logs/app-device-build-20260603233907-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log`
  - exact Xcode failure:
    - `Unable to find a destination matching the provided destination specifier:
      { id:CB9FFF0E-89AD-57B5-9C00-6552D814875E }`
- Checked Mobile MCP available devices:
  - result: only simulators were listed:
    - `0F4A5606-5204-4B5C-9037-1185B9394077`
      (`feat_more_shaders - iPhone 14`)
    - `DEF1631B-7125-43C6-BFA3-4423BF103C91`
      (`feat_remount-disposal-lifecycle-post-audit - iPhone 17`)
    - `EC91B75F-F136-478F-9740-3EA2D855825B`
      (`feat_redo_scene_arch - iPhone 16`)
- Interpretation:
  - both relay hosts have now shown continuous live `dock/update` delivery for
    two minutes;
  - Xcode/CoreDevice and Mobile MCP both fail to expose the physical iPhone;
  - the remaining physical installed-app proof cannot be gathered from this Mac
    until the device becomes available.

## 2026-06-03 Physical iPhone Log Fallback And Reconnect Root Cause

- Canonical physical log collection still failed:
  - `rtk make device-logs DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`
  - result: `log: Must be root to collect logs from attached device`
  - user retry with `sudo make device-logs ...` failed with:
    - `Warning: --predicate is ignored when collecting from attached device`
    - `log: failed to create archive: Device not configured (6)`
- CoreDevice diagnostics were also unhealthy:
  - `rtk make device-debug-bundle DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`
  - result:
    - `A connection to this device could not be established.`
    - `Timed out while attempting to negotiate tunnel parameters`
- Alternate path that worked:
  - installed Homebrew `libimobiledevice`
  - hardware UDID: `00008150-00054DEC1461401C`
  - `idevicepair -u 00008150-00054DEC1461401C validate`
    returned success
  - pulled archive with:
    - `idevicesyslog -u 00008150-00054DEC1461401C archive /tmp/codex-client/iphone17pro-idevicesyslog-archive-last10m.tar --age-limit 600 --size-limit 100000000`
- Physical log artifacts:
  - raw archive:
    `/tmp/codex-client/iphone17pro-idevicesyslog-archive-last10m.tar`
  - extracted unified log archive:
    `/tmp/codex-client/iphone17pro-idevicesyslog-last10m.logarchive`
  - filtered app subsystem log:
    `/tmp/codex-client/iphone17pro-codexdock-unified-last10m.log`
  - filtered process log:
    `/tmp/codex-client/iphone17pro-codexdock-process-unified-last10m.log`
  - live syslog sample:
    `/tmp/codex-client/iphone17pro-codexdock-syslog-60s.log`
- The physical app log reproduced the user-visible failure:
  - repeated every approximately five seconds:
    - `app-server connect initialize started`
    - `app-server request failed method=initialize request_id=initialize duration_ms=0 error=AppServerClientError: JSON-RPC request \`initialize\` was cancelled`
    - `app-server connect initialize failed duration_ms=1 error=AppServerClientError: JSON-RPC request \`initialize\` was cancelled`
    - `connectivity overall status=Partial message=Amir-M5: JSON-RPC request \`initialize\` was cancelled`
  - CFNetwork showed the app canceling its own HTTP/WebSocket task:
    - `NSURLErrorDomain Code=-999`
    - `HTTP load canceled, 0/0 bytes`
  - The network path was available while this happened:
    - `Path is satisfied`
    - `uses wifi`
    - `LQM: good` or `moderate`
- Root cause found in `StreamReconciler`:
  - a scheduled reconnect task slept for `streamReconnectDelay`;
  - after the sleep, that same task called `start()`;
  - `start()` immediately cancelled `reconnectTask`;
  - because the caller was the reconnect task, it cancelled itself;
  - the next `connectAndInitialize()` inherited that cancellation and canceled
    the `initialize` request in `0-1ms`.
- Fix:
  - `StreamReconciler.start()` now delegates to
    `start(cancelScheduledReconnect:)`;
  - external starts still cancel any pending reconnect task;
  - scheduled reconnects call `start(cancelScheduledReconnect: false)` so they
    do not cancel themselves before opening the connection.
- Regression proof:
  - added
    `DockStoreStreamTests.testScheduledReconnectDoesNotCancelItsOwnConnectTask`
  - it records `Task.isCancelled` for the original connect and scheduled
    reconnect connect;
  - expected states are `[false, false]`.
- Test run:
  - `rtk swift test --filter DockStoreStreamTests`
  - result: `19` tests, `0` failures.
