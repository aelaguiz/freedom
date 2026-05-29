# Worklog

Plan doc: docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29.md
Plan audit: docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29_PLAN_AUDIT.md

## Initial entry
- Run started: 2026-05-29T01:55:12Z.
- Current phase: Phase 1 - Bounded Upstream Substrate.
- ArcStep AutoPlan status: `READY next=implement-loop`.
- Plan audit status: ready; blockers PLA-001 through PLA-011 resolved in the plan before implementation.

## 2026-05-29T02:24Z - Phase 1 through Phase 3 implementation slice

Implemented:

- Phase 1 bounded upstream substrate:
  - Added `scripts/dock-relay-upstream-pool.mjs`.
  - Routed durable history calls through pooled `HistoryClient` with one
    `history` socket.
  - Hardened JSON-RPC timeout, unhealthy socket quarantine, pending-count
    gauges, and bounded close/terminate behavior.
  - Added `rtk make relay-leak-check`.
- Phase 2 history-first dashboard list:
  - Removed list-time live merge, preview fanout, and attention resume probing
    from `thread/list`.
  - Preserved history membership/order/cursors and Codex's `100` row cap.
  - Added Swift cursor continuation and optional `liveOverlay` propagation from
    relay DTO through Dock connectivity state.
  - Added `rtk make relay-probe`.
- Phase 3 live status cache:
  - Added `LiveStatusCache` and `SessionRouter`.
  - Moved `ps` discovery behind the cache refresh boundary.
  - Routed loaded-list, read, turns, archive, and resume through
    `LiveStatusCache`/`SessionRouter`.
  - Made live status sweeps read-only: `thread/loaded/list` plus `thread/read`,
    no dashboard-wide `thread/resume`.
  - Added `/statusz` live-status projection plus loopback-only `/metricsz` and
    `/debugz/sessions`.
  - Added request counters, upstream pool gauges, hashed session/thread debug
    IDs, and redacted diagnostic projections.
- Host-service correction:
  - Fixed launchd `start` to re-bootstrap loaded-but-not-running services
    instead of kickstarting stale loaded state.
  - This fixed the real restart blocker where Codex rejected stale
    `--listen ws://127.0.0.1:4500/`.

Verification passed:

- `rtk npm run test:relay`: 53 tests passed.
- `node --test scripts/codex-dock-host-service.test.mjs`: 22 tests passed.
- `rtk swift test --filter AppServerClientTests`: 44 tests passed, 5 skipped.
- `rtk swift test --filter DockStoreTests`: 28 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests`: 51 tests passed.
- `rtk make dock-relay-restart`: passed after the launchd re-bootstrap fix.
- `rtk make dock-relay-status`: ready; raw app-server and relay active.
- `rtk make relay-probe`: passed against
  `ws://amir-m5.fairy-salmon.ts.net:4510`, top thread
  `019e70b3-6b3b-7af1-a443-900ca409e895`, `rowCount` 20,
  `nextCursor` `2026-05-28T11:37:48.311Z`.
- `rtk make relay-leak-check`: passed 25 iterations; `history` pool stayed
  `open: 1`, `pending: 0`, `unhealthy: 0`.

Current next phase:

- Phase 4 - Logical Host Identity And Device Profiles.

## 2026-05-29T02:45Z - Phase 4 implementation slice

Implemented:

- Added stable logical relay identity across relay and app config:
  - Relay `initialize` returns `relayInstanceID`.
  - `/statusz`, `/metricsz`, and `/debugz/sessions` expose non-secret
    `host.relayInstanceID`.
  - Bonjour TXT advertises non-secret `relay-id`.
  - Host-service app config writes `CODEX_DOCK_RELAY_INSTANCE_ID`.
- Added multi-endpoint logical hosts in Swift:
  - `DockHostConfiguration` now owns ordered `endpoints`.
  - `HostRegistry.fromEnvironment` groups endpoint aliases when
    `CODEX_DOCK_RELAY_INSTANCE_ID` exists.
  - `LocalRelayEndpointList`, `RelayDiscovery`, `RelayBootstrapStore`, and
    `HostSettingsStore` preserve `relayInstanceID`.
  - `AppServerDockClient` tries endpoints in order and validates relay identity
    from both `initialize` and `/statusz` when a logical relay id is configured.
- Closed app-facing raw app-server side doors:
  - Environment, saved config, manual host settings, and device config reject
    raw `:4500` endpoints.
  - Mac-side internals still use raw `ws://127.0.0.1:4500` behind the relay.
- Made physical config write/readback Makefile-driven and stale-proof:
  - Added `scripts/device-relay-config.mjs`.
  - Added structured semantic readback verification so Swift JSON key ordering
    does not cause false failures.
  - Fixed the device copy shape by staging
    `root/CodexDock/relay-config.json` and copying the parent `root` directory
    to `Library/Application Support`.
- Updated `AGENTS.md` with the physical phone profiles:
  - iPhone 17 Pro uses Tailscale endpoints.
  - iPhone 14 uses `Amir-M5.local:4510,192.168.50.74:4510`.
  - Both carry `relayInstanceID=Amir-M5`.

Verification passed:

- `node --check scripts/device-relay-config.mjs` plus relay/status/host-service
  syntax checks passed.
- `rtk swift test --filter DockConfigurationTests`: 29 tests passed.
- `rtk swift test --filter AppServerClientTests`: 44 tests passed, 5 skipped.
- `rtk swift test --filter DockStoreTests`: 29 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests`: 51 tests passed.
- `rtk npm run test:relay`: 53 tests passed.
- `rtk npm run test:host-service`: 27 tests passed.
- `rtk make dock-relay-restart`: passed.
- `rtk make dock-relay-status`: ready; raw app-server and relay active.
- Live `/statusz` proof showed `host.relayInstanceID` as `Amir-M5`.
- Live WebSocket `initialize` proof returned `relayInstanceID: Amir-M5`.
- `rtk make relay-probe`: passed against
  `ws://amir-m5.fairy-salmon.ts.net:4510`, top thread
  `019e70b3-6b3b-7af1-a443-900ca409e895`, `rowCount` 20,
  `nextCursor` `2026-05-28T11:37:48.311Z`.
- `rtk make relay-leak-check`: passed 25 iterations; `history` pool stayed
  `open: 1`, `pending: 0`, `unhealthy: 0`.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed after
  `SIM='iPhone 17'` was found ambiguous.
- `rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  DEVICE_RELAY_ENDPOINTS='Amir-M5.local:4510,192.168.50.74:4510'
  DEVICE_RELAY_INSTANCE_ID='Amir-M5'`: passed.
- iPhone 14 installed build: `20260529024408`.
- `rtk make device-config-verify DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  DEVICE_RELAY_ENDPOINTS='Amir-M5.local:4510,192.168.50.74:4510'
  DEVICE_RELAY_INSTANCE_ID='Amir-M5'`: passed after the semantic verifier fix.

Blockers / not run:

- `rtk make device-logs DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  LOG_LAST=5m` failed with `log: Must be root to collect logs from attached
  device`.
- iPhone 17 Pro Tailscale install/readback was not run in this slice because
  the user said they were using that phone.

## 2026-05-29T02:53Z - Phase 5 ops surface slice

Implemented:

- Added `rtk make relay-doctor` as the relay-focused Makefile diagnostic entry.
  It uses the existing redacted host-service doctor rather than a second
  service-status implementation.
- Added `rtk make sim-config-verify SIM='iPhone 17'`, backed by
  `scripts/device-relay-config.mjs verify-env`, to verify generated
  `.codex-dock/host.env` without exposing secrets or raw app-server endpoints.
- Extended `scripts/device-relay-config.mjs` to verify app-facing host env
  files and reject secret-looking keys plus raw `:4500` endpoints.
- Demoted `npm run dock-relay` so it exits with a pointer to
  `rtk make services` instead of starting `scripts/dock-relay.mjs` directly.
- Updated README and AGENTS so the normal runbook says history-first dashboard
  list plus cached live overlay, Makefile-owned app/device/sim commands, and
  `.codex-dock/logs/dock-relay.err.log`.
- Hardened `rtk make relay-leak-check`: the first final run failed with
  `history upstream pending requests did not drain: 1` while recent app/test
  clients were still clearing. Metrics showed those pending requests drained a
  few seconds later, so the leak check now waits up to
  `CODEX_DOCK_LEAK_CHECK_DRAIN_TIMEOUT_MS=10000` before judging the pool.

Verification passed:

- `node --check scripts/device-relay-config.mjs`: passed.
- `node --check scripts/dock-relay-leak-check.mjs`: passed.
- `rtk npm run test:host-service`: 29 tests passed.
- `rtk npm run test:relay`: 53 tests passed.
- `rtk make relay-doctor`: passed with status `passed`.
- `rtk make sim-config-verify
  SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make help`: listed `relay-doctor`, `relay-probe`,
  `relay-leak-check`, `sim-config-verify`, and `device-config-verify-all`.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make relay-probe`: passed against
  `ws://amir-m5.fairy-salmon.ts.net:4510`, top thread
  `019e70b3-6b3b-7af1-a443-900ca409e895`, `rowCount` 20,
  `nextCursor` `2026-05-28T11:37:48.311Z`.
- Final `rtk make relay-leak-check`: passed; history pool before drain had
  `open: 1`, `pending: 2`, `unhealthy: 0`, and after drain had `open: 1`,
  `pending: 0`, `unhealthy: 0`.

Still pending:

- iPhone 17 Pro Tailscale install/readback was still pending at this point
  because the user said they were using that phone.

## 2026-05-29T03:10Z - Shared endpoint fallback and iPhone 17 Pro install

Implemented:

- Added `CodexDock/AppServer/AppServerHostConnector.swift` as the shared Swift
  owner for ordered endpoint fallback and relay identity validation.
- Routed dashboard list/archive, thread detail sessions, and relay realtime
  transcription through the same connector instead of letting each path use the
  first endpoint differently.
- Changed `DockHostConfiguration.fromEnvironment` to preserve the full
  endpoint list instead of dropping fallback endpoints.
- Tightened `HostSettingsStore` so a one-host `relayInstanceID` registry keeps
  added endpoints as aliases on that logical host instead of creating
  endpoint-as-host side doors.

Verification passed:

- `rtk swift test --filter DockConfigurationTests`: 29 tests passed.
- `rtk swift test --filter AppServerClientTests`: 46 tests passed, 5 explicit
  real-host smoke tests skipped because their opt-in env vars were not set.
- `rtk swift test --filter DockStoreTests`: 30 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests`: 51 tests passed.
- `rtk make device-install
  DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E
  DEVICE_RELAY_ENDPOINTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
  DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed.
- iPhone 17 Pro installed build: `20260529030857`.
- iPhone 17 Pro device install log:
  `.codex-dock/logs/app-device-install-20260529030857-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log`.
- iPhone 17 Pro launch log:
  `.codex-dock/logs/device-launch-20260529030857-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log`.
- `rtk make device-config-verify
  DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E
  DEVICE_RELAY_ENDPOINTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
  DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed and read back the Tailscale profile.
- `rtk make sim-config-verify SIM='iPhone 17'` failed because the simulator
  name is ambiguous: `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` and
  `DEF1631B-7125-43C6-BFA3-4423BF103C91` both match.
- `rtk make sim-config-verify
  SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make app-test
  SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.

Runtime observation to investigate if it persists:

- The user observed the client toggling between `Partial` and `Online`.
  This may be expected while services/tests are running because live-overlay
  state can move between degraded and healthy, but it should be checked during
  the final simulator pass if it continues after services are stable.
- The user observed the latest user message getting stuck at the top of thread
  details instead of sitting naturally in the chronological message flow. This
  is confusing and should be fixed in the thread-detail event ordering/rendering
  path, not just remembered.
- The user asked to explicitly test submitting messages through the simulator
  UI, especially into an active session that is already doing work. This is open
  verification because the current automated checks prove build/config paths but
  do not prove the composer submit path against an in-progress thread.

Current physical-device posture:

- iPhone 17 Pro is now installed and read back with the correct Tailscale
  profile. The user may unplug it, so remaining checks should not depend on
  that phone staying attached.

## 2026-05-29T03:20Z - Thread detail natural-flow correction

Implemented:

- Changed thread detail event ordering from newest-first grouping to natural
  conversation flow through `ThreadEventDisplayOrder.naturalFlow`.
- Updated visibility filtering so Messages / Messages + Thinking / Everything
  project their filtered rows through the same natural-flow ordering.
- Updated `ThreadDetailStore.publishLoaded()` to publish natural-flow events,
  so the newest user message is not pinned at the top of thread details.
- Updated the visibility-mode plan doc to stop teaching `newestFirst` as the
  current detail timeline contract.
- Split `AppServerDockClient` into
  `CodexDock/State/AppServerDockClient.swift` and
  `AppServerThreadDetailSessionFactory` into
  `CodexDock/State/AppServerThreadDetailSession.swift` after the strict
  maintainability pass showed `DockStore.swift` and `ThreadDetailStore.swift`
  had crossed 1,000 lines.

Verification passed:

- `rtk swift test --filter ThreadEventNormalizerTests`: 11 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests`: 51 tests passed.
- `rtk swift test --filter ThreadDetailStoreTestsLifecycle`: 10 tests passed.
- `rtk swift test --filter DockStoreTests`: 30 tests passed.
- `rtk swift test --filter AppServerClientTests`: 46 tests passed, 5 explicit
  real-host smoke tests skipped because their opt-in env vars were not set.
- `rtk make app-test
  SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.

File-size result:

- `CodexDock/State/ThreadDetailStore.swift`: 870 lines.
- `CodexDock/State/DockStore.swift`: 789 lines.
- `CodexDock/State/AppServerThreadDetailSession.swift`: 177 lines.
- `CodexDock/State/AppServerDockClient.swift`: 217 lines.

Still open:

- Simulator UI composer-submit still needs an actual interface test, especially
  submitting into an active session that is already doing work.
- Critical follow-up phase added: client-submitted messages may route to the
  wrong running Codex app-server/session. This needs a deep root-cause
  investigation and canonical routing fix, not a local hack.
- Open follow-up phase added: Dock overview rows currently surface the first
  stale thread message instead of the latest useful message. This needs an
  elegant canonical summary fix that does not reintroduce per-row turn fanout.
- The `Partial` ↔ `Online` status toggle still needs a stable-service simulator
  pass if it persists.

## 2026-05-29T03:35Z - Config side-door hardening and implementation audit

Implemented:

- Closed the remaining endpoint-as-host fallback path for alias lists:
  `DockHostConfiguration`, `HostRegistry.fromEnvironment`,
  `LocalRelayEndpointList.hostConfigurations`, and
  `FileLocalDockConfigurationStore` now require `relayInstanceID` when a config
  contains multiple endpoints.
- Kept single-endpoint legacy/manual configs valid, but made multi-endpoint
  alias configs fail loudly without `CODEX_DOCK_RELAY_INSTANCE_ID`.
- Updated `RelayBootstrapStore` so no-id discovery does not flatten multiple
  logical hosts into one ambiguous persisted endpoint list.
- Hardened generated app-facing host env so stale `CODEX_DOCK_HOSTS` entries
  pointing at raw `:4500` fail instead of reaching the installed app.
- Hardened `--relay-public-url` so the app-facing relay URL cannot be raw
  `:4500`.

Implementation audit result:

- Fresh consult verdict: `pass-with-notes`, with no blocking findings after the
  endpoint-alias and raw-`:4500` side doors were fixed.
- Native read-only explorer flagged the same two real blockers:
  multi-endpoint/no-relay-id fallback and generated app host env raw-`:4500`.
  Both are now fixed and covered by tests.

Verification passed:

- `rtk swift test --filter DockConfigurationTests`: 31 tests passed.
- `rtk swift test --filter DockStoreTests`: 30 tests passed.
- `rtk swift test --filter AppServerClientTests`: 46 tests passed, 5 explicit
  real-host smoke tests skipped because their opt-in env vars were not set.
- `rtk swift test --filter ThreadDetailStoreTests`: 51 tests passed.
- `rtk npm run test:host-service`: 31 tests passed.
- `rtk npm run test:relay`: 53 tests passed.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make device-install
  DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  DEVICE_RELAY_ENDPOINTS=Amir-M5.local:4510,192.168.50.74:4510
  DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed.
- iPhone 14 installed build: `20260529033451`.
- iPhone 14 device install log:
  `.codex-dock/logs/app-device-install-20260529033451-0A4EFF8B-54D8-58FB-B3FB-63263265B9CC.log`.
- iPhone 14 launch log:
  `.codex-dock/logs/device-launch-20260529033451-0A4EFF8B-54D8-58FB-B3FB-63263265B9CC.log`.
- `rtk make device-config-verify
  DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  DEVICE_RELAY_ENDPOINTS=Amir-M5.local:4510,192.168.50.74:4510
  DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed and read back the local profile.

Still open:

- Simulator UI composer-submit still needs an actual interface test, especially
  submitting into an active session that is already doing work.
- Phase 6 remains open for the critical report that client-submitted messages
  can reach the wrong running Codex app-server/session.
- Phase 7 remains open for replacing stale first-message Dock overview previews
  with the latest useful thread summary.
- The `Partial` ↔ `Online` status toggle still needs a stable-service simulator
  pass if it persists.

## 2026-05-29T03:45Z - Phase 6/7 relay hardening

Implemented:

- Hardened the relay focused-session route. A downstream WebSocket is bound by
  `thread/resume`; the relay now rejects the binding if the upstream returns a
  different thread id.
- Hardened submit forwarding. `turn/start`, `turn/steer`, and `turn/interrupt`
  now require `params.threadId` to match the current resumed thread before the
  relay forwards the request upstream.
- Hardened phone responses to upstream server requests. The relay now tracks
  forwarded server request ids by session generation, clears them on a newer
  `thread/resume`, and rejects stale or unknown phone responses instead of
  sending them to whatever upstream is currently active.
- Added a relay-owned `ThreadSummaryCache` for Dock overview latest-message
  summaries. It decorates `thread/list` rows with `latestSummary` only from
  cached data, then warms missing/stale summaries out of band with bounded
  `thread/turns/list` history reads.
- Added Swift decoding/mapping for `ThreadDTO.latestSummary`, with
  `SessionSummaryMapper` preferring `latestSummary`, then inline turns, then
  raw history `preview`.

Non-secret runtime finding:

- Raw app-server `thread/list` rows include a `turns` key, but the list value is
  an empty array. A real probe showed the raw `preview` and the latest
  meaningful message are different, so the overview problem cannot be solved by
  Swift reading existing list-row turns alone.

Verification passed:

- `rtk npm run test:relay`: 56 tests passed.
- `rtk swift test --filter ThreadListMappingTests`: 13 tests passed.
- `rtk swift test --filter AppServerClientTests`: 46 tests passed, 5 explicit
  real-host smoke tests skipped because their opt-in env vars were not set.
- `rtk swift test --filter DockStoreTests`: 30 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests`: 51 tests passed.
- `rtk make dock-relay-restart`: passed, loading the changed relay script into
  the running launchd service.
- `rtk make dock-relay-status`: passed after restart.
- `rtk make relay-probe`: passed, with raw history and relay top row/cursor
  matching.
- Redacted real-relay summary proof: after one cache-warm delay, a relay
  `thread/list limit:5` response had `rowsWithLatestSummary=5`; the top row's
  `preview` hash and `latestSummary` hash differed, proving the overview
  summary is not just the stale opening preview.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed and
  launched simulator build `20260529034753`.
- `rtk make sim-config-verify
  SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make device-install
  DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  DEVICE_RELAY_ENDPOINTS=Amir-M5.local:4510,192.168.50.74:4510
  DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed and installed iPhone 14 build
  `20260529034816`.
- `rtk make device-config-verify
  DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  DEVICE_RELAY_ENDPOINTS=Amir-M5.local:4510,192.168.50.74:4510
  DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed.
- `rtk git diff --check`: passed.

Still open:

- Simulator UI composer-submit still needs an actual interface test, especially
  submitting into an active session that is already doing work.
- Simulator UI proof still needs to show a stale-opening thread is identifiable
  from the Dock overview row using the latest useful summary.
- The `Partial` ↔ `Online` status toggle still needs a stable-service simulator
  pass if it persists.

## 2026-05-29T03:55Z - Recovery invariant hardening and Composer consult

Implemented:

- Closed an additional focused-routing side door in upstream recovery. The
  relay now clears `pendingServerRequests` when the focused upstream closes, so
  old phone responses cannot be forwarded into a recovered upstream.
- Applied the same resumed-thread invariant during automatic recovery that the
  initial `thread/resume` binder already used. A recovered upstream is accepted
  only if `thread/resume` returns the requested thread id.
- Added relay regression tests for wrong-thread recovery binding and stale phone
  responses after upstream recovery.

Independent review:

- Cursor Agent `composer-2.5-fast` fresh consult ran from
  `/tmp/fresh-consult/codex-dock-composer-impl-audit-20260529T035327Z-BsL6u3`
  and returned `pass-with-notes`.
- The consult independently flagged the recovery thread-id check as a
  non-blocking hardening item; this pass fixed it before final approval.
- Thermonuclear maintainability review was recorded at
  `docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29_THERMONUCLEAR_REVIEW.md`
  and approved the implementation after the recovery fix.

Simulator UI evidence:

- Mobile MCP opened a simulator live thread detail, typed a smoke-test message
  into the real composer, tapped send, and the composer cleared without a
  visible error.
- Relay logs showed the UI submit as `turn/steer` forwarded successfully to the
  active upstream at `ws://127.0.0.1:59557/`.
- This closes the single active-session UI-submit proof gap. Multi-concurrent
  session UI proof remains open.

Verification passed:

- `rtk npm run test:relay`: 58 tests passed.
- `rtk npm test`: relay 58 tests passed; host-service/device-config 31 tests
  passed.
- `rtk make dock-relay-restart`: passed, loading the recovery hardening into the
  running Makefile-owned service.
- `rtk make dock-relay-status`: passed with service status `ready`.
- `rtk make relay-probe`: passed with `liveOverlay.state=ready`, 2 live
  endpoints, and 8 live rows.
- `rtk git diff --check`: passed.

Still open:

- Simulator UI proof across multiple concurrent sessions is still needed for
  CPA-OPEN-002.
- Simulator UI proof still needs to show a stale-opening thread is identifiable
  from the Dock overview row using the latest useful summary.
- The `Partial` ↔ `Online` status toggle still needs a stable-service simulator
  pass if it persists.

## 2026-05-29T04:16Z - Remaining proof gaps closed

Root cause found:

- The simulator `Partial` state had two independent causes:
  - Agent `thread/list` pages were too large for iOS. A real relay scan showed
    active-agent `limit:100` pages up to `1332205` bytes, while the local SDK
    default `URLSessionWebSocketTask.maximumMessageSize` is `1048576` bytes.
    That matches the observed `Message too long` failure.
  - Live status refreshed every `30000` ms but became stale after `5000` ms, so
    `Partial: Amir-M5: Live status stale` was expected during normal operation.

Implemented:

- `AppServerDockClient` now uses `limit:50` for `.activeAgents` and keeps
  `limit:100` for human/history scopes.
- `URLSessionWebSocketAppServerTransport` now sets an explicit
  `maximumMessageSize` of `8388608` bytes.
- `liveStatusCacheForConfig` no longer overrides the `LiveStatusCache`
  `2500` ms default refresh cadence.
- `AppServerDockClient` now keeps the newest live-overlay value across
  paginated loads.
- Relay focused-submit logging now records safe route proof for focused turn
  requests: method, endpoint URL, thread hash, active-thread hash, and
  generation. It does not log prompt text or JSON-RPC payloads.

Runtime proof:

- Real relay payload scan after the agent page-size fix:
  `limit:50`, `pages=24`, `rows=1171`, `maxRawBytes=594496`, `over1m=0`.
- Simulator Mobile MCP showed the installed app online after the fix:
  `Online: 1384 sessions`, `All 213`, `Agents 1171`, and host row
  `amir-m5.fairy-salmon.ts.net:4510 · 1384 sessions`.
- Screenshot:
  `/tmp/codex-client/20260529T0415Z/overview-online-after-message-size-fix.png`.
- Simulator log proof:
  `connectivity overall status=Online message=1384 sessions`.
- Relay log proof:
  active-agent `limit:50` pages returned `liveOverlayState":"ready"`.
- `rtk make relay-probe` passed with `liveOverlay.state=ready`, `ageMs=2474`,
  2 endpoints, and 8 live rows.

UI route proof:

- Simulator UI submit to thread `019e70b3-6b3b-7af1-a443-900ca409e895`
  reached active upstream `ws://127.0.0.1:61116/`; the message arrived in this
  session as `UI routing smoke 61116 from simulator. Please ignore.`
- Relay log for that submit:
  `focused_request.route_verified` with matching `threadIDHash` and
  `activeThreadIDHash` of `3af7f2f6d991`.
- Simulator UI submit to thread `019e71c0-ec97-70e0-bca8-ce9c16039c52`
  reached active upstream `ws://127.0.0.1:59557/`.
- Relay log for that submit:
  `focused_request.route_verified` with matching `threadIDHash` and
  `activeThreadIDHash` of `5110ec7ce75d`, followed by
  `downstream.request_succeeded` for `turn/steer`.

Overview proof:

- Simulator search for `remount` showed a Dock overview row whose opening title
  was old while the row summary showed the latest useful message beginning
  `The main production source-proof is now clean...`.
- Screenshot:
  `/tmp/codex-client/20260529T0400Z/overview-latest-summary-remount.png`.

iPhone 14 proof:

- `rtk make device-install
  DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  DEVELOPMENT_TEAM=R6B8KXF3QW`: passed and installed build
  `20260529041420`.
- `rtk make device-config-verify
  DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`: passed and read back
  `Amir-M5.local:4510,192.168.50.74:4510` with `relayInstanceID=Amir-M5`.
- Physical Mobile MCP UI inspection was not available. Exact blocker:
  `WebDriverAgent is not running on device`. Per `AGENTS.md`, physical MCP
  retries stopped and simulator/local proof is the valid automated UI proof.
- The iPhone 17 Pro was not touched in this pass.

Verification passed:

- `rtk swift test --filter AppServerClientTests`: 48 tests passed, 5 explicit
  real-host smoke tests skipped because their opt-in env vars were not set.
- `rtk npm run test:relay`: 59 tests passed.
- `rtk npm test`: relay 59 tests passed; host-service/device-config 31 tests
  passed.
- `rtk swift test --filter DockStoreTests`: 30 tests passed.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed and
  launched simulator build `20260529041311`.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make dock-relay-status`: passed with service status `ready`.
- `rtk make relay-probe`: passed.
- `rtk git diff --check`: passed.

Closed:

- CPA-OPEN-002: multi-concurrent simulator UI submit proof.
- CPA-OPEN-003: stale-opening Dock overview latest-summary UI proof.
- CPA-OPEN-004: `Partial` / `Online` toggle root cause and stable-service
  simulator proof.
