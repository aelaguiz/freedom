# Codex Dock Connectivity Resilience Implementation Log

Date: 2026-05-28

Parent plan: `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`

Primary plan: `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`

## Phase 1 - Observable Connection Failure Path

Status: implemented in the current working tree; full Connectivity plan remains in progress.

Changed code:

- `CodexDock/AppServer/AppServerClient.swift`
  - Added `connectionStates` as a nonisolated `AsyncStream<AppServerConnectionState>`.
  - Routed state transitions through one helper so idle, connecting, connected, offline, error, and explicit close are observable.
  - Added retired-request handling so late responses for timed-out or cancelled requests do not tear down a healthy connection.
  - Finished notification and server-request streams on terminal transport failure.
  - Serialized `URLSessionWebSocketTask` access with a lock around send, receive, connect, and disconnect task reads/writes.
- `CodexDock/State/ThreadDetailStore.swift`
  - Extended `ThreadDetailSession` with connection-state observation.
  - Added a connection observation task beside notification and server-request observation.
  - Marked loaded live detail stale when the live session reports offline/error/closed or when notification/server-request streams end.
  - Suppressed stale publication during intentional close and preserved existing stale/closed reasons.
- `CodexDockTests/AppServerClientTests.swift`
  - Added coverage for connection-state transitions, explicit stream finish, late timed-out responses, late cancelled responses, and never-issued response IDs.
- `CodexDockTests/ThreadDetailStoreTests.swift`
  - Added coverage for connection drop/error stale state, notification stream end, server-request stream end, close suppression, and draft/request-card/event preservation.

Verification:

- `rtk swift test --filter AppServerClientTests`
  - Result: passed.
  - Executed 34 tests, 5 skipped, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Result: passed.
  - Executed 21 tests, 0 failures.

Notes:

- This phase intentionally stops at visible stale state and safe stream/request handling.
- Reconnect, compact rehydrate, global connectivity status, background/resume lifecycle, relay upstream recovery/fail-loud behavior, README updates, full `rtk swift test`, relay tests, and physical `iPhone 14` proof remain later Connectivity-plan work.

## Phase 2 - Reconnect And Thread Rehydrate

Status: implemented in the current working tree; full Connectivity plan remains in progress.

Changed code:

- `CodexDock/AppServer/AppServerClient.swift`
  - Added `AppServerConnectionPolicy` and `AppServerReconnectPolicy`.
  - Kept reconnect disabled by default with `.oneShot`.
  - Added `.liveDetail` reconnect policy for live thread-detail sessions.
  - Added `.reconnecting(attempt:reason:)` connection state.
  - Reconnect-enabled clients now fail in-flight requests on transport loss, keep notification/request streams open during retry, re-run `initialize` plus `initialized`, and return to `.connected` on recovery.
  - Explicit disconnect cancels scheduled reconnect and closes streams.
  - Reconnect exhaustion moves to `.offline` and finishes data streams.
  - Send-side transport failure while connected enters the same reconnect path and does not replay user requests.
- `CodexDock/State/ThreadDetailStore.swift`
  - Uses `.liveDetail` client policy for real live detail sessions.
  - Added `ThreadDetailLiveState.reconnecting`.
  - Split compact detail loading into reusable read/turns/resume helpers.
  - Rehydrates after `.reconnecting -> .connected` with `thread/read includeTurns:false`, `thread/turns/list limit:10`, and `thread/resume excludeTurns:true`.
  - Preserves existing events, request cards, card input/status, composer draft, failed-send state, active-turn handling, and closed-thread state during reconnect.
- `CodexDock/Features/Session/SessionDetailView.swift`
  - Added `Reconnecting` pill icon/color support.
- `CodexDockTests/AppServerClientTests.swift`
  - Added reconnect transition, exhaustion, explicit-disconnect cancellation, and no-request-replay coverage.
- `CodexDockTests/ThreadDetailStoreTests.swift`
  - Added reconnect/rehydrate, preservation, dedupe, stale-on-rehydrate-failure, closed-thread, and failed-send no-replay coverage.

Verification:

- `rtk swift test --filter AppServerClientTests`
  - Result: passed.
  - Executed 38 tests, 5 skipped, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Result: passed.
  - Executed 27 tests, 0 failures.

Notes:

- This phase handles the open thread-detail recovery path only.
- Global `AppConnectivityStore`, root-mounted indicator, background/resume lifecycle, relay upstream recovery/fail-loud behavior, README updates, full `rtk swift test`, relay tests, and physical `iPhone 14` proof remain later Connectivity-plan work.

## Phase 3 - App-Wide Connectivity Store And Indicator

Status: implemented in the current working tree; full Connectivity plan remains in progress.

Changed code:

- `CodexDock/State/AppConnectivityStore.swift`
  - Added the canonical app-wide connectivity rollup.
  - Tracks per-host source observations, message, last checked time, and last success time instead of using last-writer-wins host state.
  - Rolls host state into overall status: unconfigured, checking, online, partial, reconnecting, stale, offline, error, and configuration error.
  - Uses lifecycle as an explicit foreground/background overlay so old store facts cannot overwrite `Resuming` before fresh proof lands.
  - Treats nil bearer relay hosts as configured hosts, not auth failures.
  - Consumes Dock scoped outcomes, Archive outcomes, manual host tests, and Thread detail live/reconnect/stale states.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - Added passive root-level indicator UI backed only by `AppConnectivityStore`.
- `CodexDock/Features/Dock/DockView.swift`
  - `CodexDockRootView` now owns `AppConnectivityStore`.
  - All three root initializers create the connectivity store.
  - Root mounts `GlobalConnectivityIndicatorView`.
  - Root binds Dock, Archive, and Hosts stores to the connectivity reporter.
  - Root owns the Dock refresh loop; `DockView.runRefreshLoop()` was removed.
  - `DockView` passes the connectivity reporter into `ThreadDetailStore`.
- `CodexDock/State/DockStore.swift`
  - Reports loading, loaded, offline, error, and scoped partial outcomes to the connectivity reporter.
- `CodexDock/State/ArchiveStore.swift` and `CodexDock/Features/Archive/ArchiveView.swift`
  - Archive reports host outcomes to the connectivity reporter.
  - All-offline/all-error archive now renders `Archive unavailable` instead of a normal empty archive.
- `CodexDock/State/HostSettingsStore.swift`
  - Manual host test status reports into the app-wide connectivity store.
- `CodexDock/State/ThreadDetailStore.swift`
  - Loaded live/reconnecting/stale/closed detail state reports into the app-wide connectivity store.
- `CodexDockTests/AppConnectivityStoreTests.swift`
  - Added direct rollup tests.
- `CodexDockTests/DockStoreTests.swift`
  - Added Archive all-hosts-failed unavailable coverage.

Verification:

- `rtk swift test --filter AppConnectivityStoreTests`
  - Result: passed.
  - Executed 7 tests, 0 failures.
- `rtk swift test --filter DockStoreTests`
  - Result: passed.
  - Executed 19 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Result: passed.
  - Executed 27 tests, 0 failures.
- `rtk swift test`
  - Result: passed.
  - Executed 129 tests, 5 skipped, 0 failures.
- Focused code readback:
  - `CodexDockRootView.init(store:)`, `init(registry:)`, and `init(configurationError:)` each initialize `_connectivityStore`.
  - `CodexDockRootView` mounts `GlobalConnectivityIndicatorView`.
  - `DockView.runRefreshLoop()` is removed; only root `runDockRefreshLoop()` remains.

Notes:

- This phase does not yet model SwiftUI `scenePhase` or background/resume. That remains Phase 4.
- Relay upstream recovery/fail-loud behavior, README updates, relay tests, and physical `iPhone 14` proof remain later Connectivity-plan work.

## Phase 4 - App Background And Foreground Resume Lifecycle

Status: implemented in the current working tree; full Connectivity plan remains in progress.

Changed code:

- `CodexDock/State/AppLifecycleCoordinator.swift`
  - Added the root lifecycle owner for active, inactive, backgrounded, and foreground-resuming state.
  - Added resume generations, foreground-work gating, and multicast snapshot streams for detail/session participants.
  - Keeps duplicate `.active` scene-phase events in `foregroundResuming` until foreground resume work explicitly finishes.
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
  - Observes SwiftUI `scenePhase` before `CodexDockRootView` exists.
  - Forwards lifecycle snapshots into `RelayBootstrapStore`.
  - Reports bootstrap starting/discovering/failed states into `AppConnectivityStore`.
  - Shows `GlobalConnectivityIndicatorView` during non-ready bootstrap states and passes the same connectivity store into the ready root.
  - Passes the same lifecycle coordinator into `CodexDockRootView` after relay bootstrap reaches `.ready`.
- `CodexDock/Features/Dock/DockView.swift`
  - `CodexDockRootView` now owns `AppLifecycleCoordinator`.
  - Root observes `scenePhase`, reports lifecycle into `AppConnectivityStore`, pauses the Dock refresh loop while foreground work is not allowed, and forces Dock/Archive refresh on foreground resume before finishing the lifecycle generation.
  - `DockView` passes the lifecycle coordinator into each `ThreadDetailStore`.
- `CodexDock/State/AppConnectivityStore.swift` and `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - Added backgrounded/resuming rollup states and indicator icon/color support.
- `CodexDock/AppServer/AppServerClient.swift`
  - Added an optional foreground-work gate.
  - Reconnect-enabled clients wait while the app is backgrounded before consuming a reconnect attempt.
  - Reconnect-enabled clients re-check the foreground gate after backoff sleep and before opening transport.
- `CodexDock/State/ThreadDetailStore.swift`
  - Observes lifecycle snapshots.
  - Marks open loaded detail stale on background without clearing events, request cards, active turn, draft, or failed-send state.
  - Cancels active voice capture on background through `VoiceCaptureControlling`.
  - On foreground resume, waits for the session to be connected, then reuses the Phase 2 compact `thread/read includeTurns:false`, `thread/turns/list limit:10`, and `thread/resume excludeTurns:true` path before returning to `.live`.
- `CodexDock/Configuration/RelayBootstrapStore.swift`
  - Added lifecycle handling for bootstrap discovery before root exists.
  - Stops discovery while backgrounded before `.ready`.
  - Restarts discovery on foreground resume when still unready.
  - Preserves manual URL text and avoids duplicate auto-use of the same discovered relay.
- `CodexDock/Configuration/RelayDiscovery.swift`
  - Made Bonjour discovery start/stop idempotent.
- Tests:
  - Added `CodexDockTests/AppLifecycleCoordinatorTests.swift`.
  - Extended `AppConnectivityStoreTests`, `AppServerClientTests`, `DockConfigurationTests`, and `ThreadDetailStoreTests`.

Verification:

- `rtk swift test --filter AppLifecycleCoordinatorTests`
  - Result: passed.
  - Executed 3 tests, 0 failures.
- `rtk swift test --filter AppConnectivityStoreTests`
  - Result: passed.
  - Executed 11 tests, 0 failures.
- `rtk swift test --filter DockConfigurationTests`
  - Result: passed.
  - Executed 14 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Result: passed.
  - Executed 31 tests, 0 failures.
- `rtk swift test --filter AppServerClientTests`
  - Result: passed.
  - Executed 40 tests, 5 skipped, 0 failures.
- `rtk swift test`
  - Result: passed.
  - Executed 147 tests, 5 skipped, 0 failures.
- `rtk git diff --check`
  - Result: passed.

Notes:

- Phase 4 proves app background/resume lifecycle and paused client reconnect attempts at the Swift layer.
- Relay upstream recovery/fail-loud behavior, README updates, relay tests, and physical `iPhone 14` proof remain later Connectivity-plan work.

## Phase 5 - Relay Recovery And Update Delivery Hardening

Status: implemented in the current working tree; full Connectivity plan remains in progress.

Changed code:

- `scripts/dock-relay.mjs`
  - Added bounded upstream recovery constants for active detail sessions.
  - Tracks downstream session resume params, selected upstream endpoint, recovery task, and closing state.
  - Tracks session generations so stale recovery and stale initial `thread/resume` work cannot replace a newer active session.
  - Abandons and closes a newly-created upstream if the downstream phone WebSocket closes before the initial `thread/resume` completes.
  - Attempts bounded reconnect plus compact `thread/resume` when an active upstream closes while the downstream phone socket is still open.
  - Closes the downstream phone WebSocket with a fail-loud `1011` close when upstream recovery is unsafe or exhausted.
  - Requires `forwardToActiveUpstream` to use an actually open upstream socket.
  - Changes attention probing to call `thread/resume` with `excludeTurns:true`.
  - Preserves live loaded rows inside the relay `thread/list` limit before filling remaining slots with stored history rows.
  - Keeps relay-only `dockRelaySource` metadata out of phone-facing rows.
- `scripts/dock-relay-json-rpc-client.mjs`
  - Extracted the JSON-RPC WebSocket client from the relay runtime.
  - Rejects pending upstream requests on close, exposes `isOpen()` for forwarding decisions, and owns upstream close callbacks.
- `scripts/dock-relay.test.mjs`, `scripts/dock-relay-phase5.test.mjs`, and `scripts/dock-relay-test-helpers.mjs`
  - Split relay test coverage into base/helper/audio/security tests, Phase 5 in-process WebSocket tests, and shared helpers.
  - Added in-process WebSocket relay coverage for compact attention probing, live-row-preserving list limits, history failure with live success, live endpoint failure with history success, owning-upstream `thread/turns/list`, `thread/resume` notification/request forwarding, initial-resume downstream close cleanup, stale recovery suppression, upstream recovery, downstream fail-loud close, health auth reporting, and bearer rejection.

Verification:

- `rtk node --check scripts/dock-relay.mjs`
  - Result: passed.
- `rtk node --check scripts/dock-relay-json-rpc-client.mjs`
  - Result: passed.
- `rtk node --check scripts/dock-relay-test-helpers.mjs`
  - Result: passed.
- `rtk node --check scripts/dock-relay-phase5.test.mjs`
  - Result: passed.
- `rtk npm run test:relay`
  - Result: passed.
  - Executed 33 tests, 0 failures.
- `rtk npm test`
  - Result: passed.
  - Executed 33 tests, 0 failures.
- `rtk swift test --filter AppServerClientTests`
  - Result: passed.
  - Executed 40 tests, 5 skipped, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Result: passed.
  - Executed 31 tests, 0 failures.
- `rtk git diff --check`
  - Result: passed.

Notes:

- Phase 5 proves the relay no longer hides active upstream death from Swift and that list/attention probing behavior stays compact and live-aware.
- README updates, final full test/service verification, plan audit, thermo-nuclear review, and physical `iPhone 14` proof remain later Connectivity-plan work.

## Phase 6 - Final Verification, Runbook, And Physical iPhone Proof

Status: verified with a user-approved non-Pro simulator visual fallback in the current working tree. Physical `iPhone 14` install/launch/process proof passed, but physical screenshot/UI navigation automation remains deferred because WebDriverAgent is not running on the real device.

Changed code after simulator proof:

- `CodexDock/Features/Dock/DockView.swift`
  - Removed a render-time `connectivityStore.configure(registry)` call from `CodexDockRootView.init(registry:...)`.
  - The non-Pro simulator initially rendered a blank app surface while SwiftUI repeatedly logged `Publishing changes from within view updates`; the app rendered normally after this state mutation was removed from view initialization.

Changed docs:

- `README.md`
  - Replaced stale "status only breaks ties" wording with the implemented live-row-first relay/Dock behavior.
  - Documented the root connectivity indicator labels and ownership.
  - Documented reconnect, compact detail rehydrate, relay fail-loud close, iOS background/resume behavior, and voice-capture cancellation on background.
  - Added the current physical acceptance command for `iPhone 14` destination id `00008110-000E04940240A01E` with team `R6B8KXF3QW`.
- `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`
  - Updated Phase 6 to record physical `iPhone 14` install/launch proof, physical WebDriverAgent automation as deferred, and the user-approved non-Pro simulator visual fallback.

Verification:

- `rtk swift test`
  - Result: passed.
  - Executed 147 tests, 5 skipped, 0 failures.
- `rtk node --check scripts/dock-relay.mjs`
  - Result: passed.
- `rtk npm test`
  - Result: passed.
  - Executed 33 tests, 0 failures.
- `rtk git diff --check`
  - Result: passed after Phase 6 docs, simulator proof, and the SwiftUI fix were recorded.
- `rtk make dock-relay`
  - Result: passed.
  - Raw app-server endpoint: `ws://192.168.50.117:4500`; pid `93066`; `/readyz` returned `HTTP/1.1 200 OK`.
  - Dock relay endpoint: `ws://192.168.50.117:4510`; pid `39096`; phone auth `none`; `/readyz` returned `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
- `rtk make app-server-status`
  - Result: passed.
  - Confirmed raw app-server pid `93066`, endpoint `ws://192.168.50.117:4500`, and `/readyz` `HTTP/1.1 200 OK`.
- `rtk make dock-relay-status`
  - Result: passed.
  - Confirmed relay pid `39096`, endpoint `ws://192.168.50.117:4510`, history endpoint `ws://127.0.0.1:4500`, phone auth `none`, and `/readyz` `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
- `rtk env -u CODEX_DOCK_APP_SERVER_BEARER_TOKEN -u CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 swift test --filter AppServerClientTests/testPhoneReachableRealHost`
  - Result: passed.
  - Executed 4 tests, 1 skipped, 0 failures.
  - Passed phone-reachable relay handshake, `thread/list`, and `thread/read` plus `thread/resume`.
  - Skipped only the explicitly gated archive/unarchive round trip because `CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP=1` was not set.
- `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`
  - Result: passed.
  - Regenerated `CodexDock.xcodeproj`, built `CodexDockApp` for the physical device, and installed bundle `com.aelaguiz.CodexDockApp` on the physical `iPhone 14`.
  - Latest install URL after the final Swift fixes: `file:///private/var/containers/Bundle/Application/B70EDC60-1552-4A2C-8DBC-0D237333782D/CodexDockApp.app/`.
- `xcrun devicectl device process launch --device 00008110-000E04940240A01E com.aelaguiz.CodexDockApp`
  - Result: passed.
  - Launched `com.aelaguiz.CodexDockApp` on the physical device.
- `xcrun devicectl device info processes --device 00008110-000E04940240A01E`
  - Result: passed.
  - Confirmed `CodexDockApp` running as pid `4340` after the final physical env relay launch.
- `xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing --activate --environment-variables <non-secret relay URL env> com.aelaguiz.CodexDockApp`
  - Result: passed.
  - Launched the physical app with non-secret relay coordinates only; no OpenAI key, raw app-server bearer token, or relay bearer token was passed to the phone.
- Physical relay smoke after final Swift fixes:
  - `rtk env -u CODEX_DOCK_APP_SERVER_BEARER_TOKEN -u CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 swift test --filter AppServerClientTests/testPhoneReachableRealHost`
  - Result: passed.
  - Executed 4 tests, 1 skipped, 0 failures.
  - Passed relay handshake, `thread/list`, and `thread/read` plus `thread/resume` with no phone-side bearer env.
  - This proves the relay-backed host path after the final Swift fixes; it is not a substitute for physical screen/navigation proof.
- User-directed simulator visual fallback:
  - Target: `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`; this is intentionally not the `iPhone 17 Pro` simulator.
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
    - Result: passed after the SwiftUI render-mutation fix.
    - Confirmed raw app-server pid `93066`, relay pid `27197`, endpoint `ws://192.168.50.117:4510`, phone auth `none`, build/install, and launch of `com.aelaguiz.CodexDockApp` as pid `28003`.
  - `xcrun simctl io BAD95C8E-3E57-4818-9B90-E4ED22593B4B screenshot /tmp/codex-client/20260528T144220Z/iphone17-sim-connectivity-fixed.png`
    - Result: passed.
    - Screenshot shows the root `Online` indicator, host `Amir-M5`, endpoint `ws://192.168.50.117:4510`, `206 sessions`, and real Dock rows.
  - `xcrun simctl spawn BAD95C8E-3E57-4818-9B90-E4ED22593B4B log show --style compact --start '2026-05-28 09:46:30' --predicate 'process == "CodexDockApp" AND eventMessage CONTAINS "Publishing changes from within view updates"'`
    - Result: passed.
    - No matching SwiftUI render-mutation warnings were logged after the fixed app launch.
  - Mobile MCP simulator proof after the tool recovered:
    - `mobile_list_available_devices` listed the simulator as online.
    - `mobile_launch_app` launched `com.aelaguiz.CodexDockApp`.
    - `mobile_list_elements_on_screen` on Dock read back `Online: 206 sessions`, `Amir-M5`, `ws://192.168.50.117:4510 · 206 sessions`, counted tabs, and real Dock row labels.
    - Dock row readback included current/latest preview text, for example `Right now it's so spammy because I'm seeing by de...`, not only the opening prompt.
    - `mobile_click_on_screen_at_coordinates` opened Archive at `(201, 822)`, Relay at `(287, 822)`, returned to Dock at `(115, 822)`, and opened Session detail at `(200, 409)`.
    - `mobile_list_elements_on_screen` on Archive, Relay, and Session detail confirmed the root indicator remains visible. Archive and Relay showed `Online: 206 sessions`; Session detail showed live state plus the root online indicator.
    - Saved screenshots:
      - `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/001_dock_online_rows.png`
      - `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/002_archive_online_indicator.png`
      - `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/003_relay_online_indicator.png`
      - `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/004_session_detail_live_indicator.png`
- `rtk swift test --filter AppConnectivityStoreTests`
  - Result: passed after the SwiftUI render-mutation fix.
  - Executed 11 tests, 0 failures.
- Final service status after simulator proof:
  - `rtk make dock-relay-status && rtk make app-server-status`
  - Result: passed.
  - Confirmed relay pid `27197`, endpoint `ws://192.168.50.117:4510`, history endpoint `ws://127.0.0.1:4500`, phone auth `none`, and `/readyz` `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
  - Confirmed raw app-server pid `93066`, endpoint `ws://192.168.50.117:4500`, and `/readyz` `HTTP/1.1 200 OK`.

Deferred physical-only proof:

- `mobile_list_elements_on_screen` and `mobile_save_screenshot` both failed for device `00008110-000E04940240A01E` with: `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
- Because of that device automation blocker, this run could not capture physical screenshots or automatically navigate Dock, Archive, Relay, and Session detail on the real phone.
- The user explicitly directed using a different simulator rather than staying blocked on physical device automation. The Mobile MCP simulator proof above is accepted for the current Connectivity closeout path; physical `iPhone 14` visual navigation proof remains a deferred hardware-automation follow-up when WebDriverAgent is available.

## 2026-05-28 - Header Indicator Collision Fix

Status: fixed and installed on the physical `iPhone 14`.

User feedback: the root `Online` indicator visually sat on top of the disabled plus button in the Dock header. The accepted correction keeps it in the Dock header row, immediately left of the plus button, with no added vertical strip.

Change:

- Updated `CodexDock/Features/Dock/DockView.swift` so `CodexDockRootView` passes the shared `AppConnectivityStore` into `DockView`, and `DockView` renders `GlobalConnectivityIndicatorView` inline in the existing Dock header `HStack`.
- The indicator now sits to the left of the disabled plus button and uses the existing header height, so it cannot cover the button and does not consume an extra vertical row.

Verification:

- `rtk swift test --filter AppConnectivityStoreTests`
  - Result: passed.
  - Executed 11 tests, 0 failures.
- `rtk git diff --check -- CodexDock/Features/Dock/DockView.swift`
  - Result: passed.
- Simulator visual proof:
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Result: passed; launched `com.aelaguiz.CodexDockApp` as pid `45016`.
  - Screenshot: `/tmp/codex-client/20260528T194350Z/dock-header-connectivity-inline.png`
  - Screenshot shows the `Online` pill inline in the Dock header, left of the plus button, with the filter tabs directly below the header and no extra status strip.
- Physical `iPhone 14` install/launch:
  - `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`
  - `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`
  - Result: passed.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.
