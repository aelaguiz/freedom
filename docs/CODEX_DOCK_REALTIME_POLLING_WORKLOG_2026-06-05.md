# Codex Dock Realtime vs Polling Work Log - 2026-06-05

## Purpose

Investigate the full path from the Codex Dock iPhone client, through the Dock
relay, down into the local Codex app-server/runtime source, and determine which
latency-sensitive parts are inherently polling-driven versus which could be
event-driven or realtime.

Requested deliverables:

- Keep this work log updated during the investigation.
- Save full findings in a new architecture analysis document.
- Read the Codex source under `/Users/aelaguiz/workspace/codex`, not only this
  client repo.

## 2026-06-05T23:22:07Z - Investigation Started

Current Codex Dock repo:

- Path: `/Users/aelaguiz/workspace/codex-client`
- Branch: `codex-dock-agents-tab-live-counts`
- Current HEAD after prior deployment: `9afa751 Fix private runtime rename and activity rollups`

Pre-existing dirty/untracked files still present before this investigation:

- `AGENTS.md`
- `README.md`
- `.arch_skill/model-consensus/codex-dock-unified-testing-framework-20260605T110717Z/`
- `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`
- `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05_PLAN_AUDIT.md`
- `docs/TESTING.md`

Local Codex source found:

- Path: `/Users/aelaguiz/workspace/codex`
- Branch: `main`
- Repo has its own `AGENTS.md`.
- Existing untracked Codex repo files are present under `.codex/` and `docs/`;
  this investigation is read-only for that repo.

Initial hypothesis to verify from source:

- Phone-to-relay Dock and Thread Detail paths are persistent WebSocket
  subscriptions.
- Relay-to-Codex state discovery has multiple polling layers.
- Some computer-side Codex events may already have an event stream in the
  Codex app-server layer, but Dock relay currently does not subscribe to all of
  it.

## 2026-06-05T23:33:24Z - Client Stream Path Read

Files read:

- `CodexDock/Configuration/CodexDockConstants.swift`
- `CodexDock/State/AppServerThreadCardStreamClient.swift`
- `CodexDock/Projection/StreamReconciler.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/ThreadDetail/ThreadDetailProjectionStream.swift`

Confirmed client behavior:

- The phone-to-relay Dock list path is a persistent WebSocket subscription:
  `dock/subscribe`, `dock/resync`, and pushed `dock/update` notifications.
- The archive list uses the same pattern with `archive/subscribe`,
  `archive/resync`, and `archive/update`.
- The open Thread Detail path uses `thread/detail/subscribe`,
  `thread/detail/resync`, and pushed `thread/detail/update` notifications.
- `StreamReconciler` treats the socket stream as the primary data path. It
  resyncs on sequence gaps, heartbeat timeout, epoch/schema mismatch, command
  completion invalidation, foreground resume, or manual refresh.
- `Dock.autoRefreshInterval = 5s` is used as a reconnect/resync safety delay,
  not as the normal way card data moves while the socket is healthy.
- `AppServer.foregroundPollInterval = 250ms` is a foreground-work gate wait in
  the Swift app, not a data polling interval.

Client-side conclusion:

- Dock, archive, and open Thread Detail fundamentally do not need to be
  polling-driven on the phone. The client already has the transport shape for
  realtime updates.
- The client can only show what the relay emits. If the relay learns about a
  Codex change late, the phone will also show it late even though the
  phone-facing transport is realtime.

## 2026-06-05T23:44:52Z - Relay Stream And Polling Path Read

Files read:

- `scripts/dock-relay-state-subscriptions.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-live-status-cache.mjs`
- `scripts/dock-relay-app-server-registry.mjs`
- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-thread-detail-projection-adapter.mjs`
- `scripts/dock-relay-thread-detail-ledger.mjs`
- `scripts/dock-relay-upstream-pool.mjs`
- `scripts/dock-relay-json-rpc-client.mjs`
- `scripts/dock-relay.mjs`

Confirmed relay-to-phone behavior:

- `StateSubscriptionHub.publishDelta()` pushes `dock/update` and
  `archive/update` immediately to subscribed downstream WebSocket clients when
  the relay store changes.
- The relay heartbeat timer defaults to `RELAY_STATE_HEARTBEAT_INTERVAL_MS =
  5_000`. It is a liveness signal, not the normal data refresh mechanism.
- `thread/detail/subscribe` opens a per-thread live upstream route through
  `thread/resume` when the thread is attachable, builds a detail ledger, then
  emits `thread/detail/update` rows as upstream notifications and server
  requests arrive.
- If the thread is archived or owned by a private unattachable runtime, detail
  can fall back to history reads. That path is not live.

Confirmed relay polling/currently-timed behavior:

- `AppServerRegistry.start()` refreshes Codex app-server endpoint discovery on
  `APP_SERVER_REGISTRY_REFRESH_INTERVAL_MS = 5_000`.
- `LiveStatusCache.start()` refreshes loaded/live rows on
  `LIVE_STATUS_REFRESH_INTERVAL_MS = 2_500`.
- `StateReconciler.start()` runs a full Dock/archive reconciliation every
  `RELAY_STATE_RECONCILE_INTERVAL_MS = 30_000`, with a 250ms debounce for
  triggered runs.
- A full Dock reconcile calls `thread/list`, enriches rows with `thread/read`,
  supplements with `session_index.jsonl`, and canonicalizes activity/latest
  summary through `thread/turns/list`.
- Live status scans call `thread/loaded/list` and then `thread/read` for loaded
  thread ids.
- Registry discovery currently reads Codex daemon history plus process-list
  discovery of attachable/private runtimes.

Confirmed event hooks already present in the relay:

- `JsonRpcWebSocketClient` supports `onNotification` and `onRequest`.
- `UpstreamConnectionPool` can keep upstream JSON-RPC clients open and pass
  notifications to the relay.
- `dock-relay.mjs` installs `config.upstreamNotificationHandler`, which ingests
  `thread/name/updated` and `thread/status/changed`.
- `NotificationIngestor` currently treats those notifications as reasons to
  reconcile, not as complete direct card updates.
- Open Thread Detail turns upstream notifications and server requests into
  projected rows immediately through the detail ledger.

Relay-side conclusion so far:

- The relay-to-phone transport does not fundamentally need polling.
- Open Thread Detail does not fundamentally need polling when the thread is
  attachable because it already has a live upstream socket.
- Dock list truth is still polling-heavy because the relay does not maintain a
  complete always-on event subscription to every relevant Codex runtime/thread.
- Some Dock fields could become event-driven with low overhead by using
  already-open upstream sockets and targeted notifications as invalidation
  triggers. Fields that require `thread/turns/list` proof still need either
  Codex to emit the needed activity/summary event or the relay to do targeted
  reads after an event.

## 2026-06-05T23:28:34Z - Codex App-Server And Runtime Source Read

Codex repo path: `/Users/aelaguiz/workspace/codex`.

Files read:

- `codex-rs/app-server/README.md`
- `codex-rs/app-server/src/lib.rs`
- `codex-rs/app-server/src/transport.rs`
- `codex-rs/app-server/src/message_processor.rs`
- `codex-rs/app-server/src/outgoing_message.rs`
- `codex-rs/app-server/src/thread_state.rs`
- `codex-rs/app-server/src/thread_status.rs`
- `codex-rs/app-server/src/request_processors/thread_lifecycle.rs`
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
- `codex-rs/app-server/src/request_processors/turn_processor.rs`
- `codex-rs/app-server/src/bespoke_event_handling.rs`
- `codex-rs/core/src/thread_manager.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/turn.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/item.rs`

Confirmed Codex behavior:

- The Codex app-server is bidirectional JSON-RPC. Broadcast notifications are
  routed only to initialized connections that have not opted out of that method.
- `thread/start` auto-attaches a listener for the starting connection, returns a
  `ThreadStartResponse`, then broadcasts `thread/started`.
- `thread/resume` attaches the caller to the loaded thread and returns the
  thread snapshot. That connection then receives that thread's turn/item/server
  request events.
- The listener loop reads `conversation.next_event()` and maps core events into
  typed app-server notifications such as `turn/started`, `turn/completed`,
  `item/started`, `item/completed`, realtime transcript/audio notifications, and
  approval/user-input server requests.
- `thread/status/changed` is broadcast by `ThreadWatchManager` when loaded
  thread status changes.
- `thread/name/updated`, `thread/archived`, `thread/unarchived`,
  `thread/closed`, and `thread/started` are broadcast notifications.
- `thread/list`, `thread/read`, `thread/loaded/list`, and `thread/turns/list`
  are request/response reads. They are not subscriptions.
- `Thread.turns` is intentionally empty for most list/notification payloads and
  is only populated for specific read/resume/fork/rollback paths when turns are
  requested.
- `thread/turns/list` still rebuilds from rollout history on every request
  because earlier turns can change after rollback/compaction until turn metadata
  is indexed separately.

Codex-side conclusion:

- Loaded/subscribed threads have real event streams. They do not fundamentally
  need polling for turn progress, item progress, approvals, user-input waits, or
  realtime transcript/audio.
- Codex already emits useful global lifecycle/status notifications for
  initialized app-server clients. Relay can use these for low-latency Dock
  invalidation without opening detail streams for every thread.
- Codex does not currently expose one complete "all thread card changes with
  latest message/activity proof" subscription. Full historical Dock truth still
  requires snapshots/reads unless Codex adds a broader indexed notification or
  card-summary feed.
- Private stdio runtimes are intentionally not attachable app-server endpoints.
  Relay can observe their presence through process/session metadata, but cannot
  receive their private per-thread event stream without a Codex-side bridge.
