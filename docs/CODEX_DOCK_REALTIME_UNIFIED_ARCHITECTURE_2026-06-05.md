---
title: "Codex Dock - Realtime Unified Architecture - Architecture Plan"
date: 2026-06-05
status: active
fallback_policy: forbidden
owners:
  - Amir
  - Codex
reviewers:
  - Fresh Consult Composer 2.5 Fast
doc_type: phased_refactor
related:
  - docs/CODEX_DOCK_REALTIME_VS_POLLING_ARCHITECTURE_2026-06-05.md
  - docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md
  - docs/TESTING.md
---

# TL;DR

Make Codex Dock feel live by moving the normal Dock and Archive update path from
timer-driven full reconciliation to app-server event invalidation plus targeted
per-thread reads. Keep polling only as a named boot, discovery, private-runtime,
and recovery backstop.

Completion means the iPhone simulator receives real relay `dock/update`,
`archive/update`, and Thread Detail updates from real Codex app-server data over
time, with measured latency, no fixture-only acceptance, no raw `:4500` phone
path, and no loss of existing Dock, Archive, Detail, rename, archive,
unarchive, private-runtime rollup, or recovery behavior.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
research: done 2026-06-05
deep_dive_pass_1: done 2026-06-05
deep_dive_pass_2: done 2026-06-05
phase_plan: done 2026-06-05
consistency_pass: done 2026-06-05
recommended_flow: research -> deep dive -> deep dive again -> phase plan -> consistency pass -> Fresh Consult -> implementation later
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:b98b96b60e3786a7100dab7273597e8840bc26dd8e778346e78e3eb65688002b",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-06T00:22:00Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:7daf8f44d8d7b059a0384ab6cbefbdf7c8c15e2d65d23897f6a381cbbaa51188",
      "completed_at": "2026-06-06T00:22:59Z",
      "doc_hash_after": "sha256:6626e0c807294f5c31b5e3d8bdfb7f78efe5c6ca2d5363473d69e392694062b6"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-06T00:23:07Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:6626e0c807294f5c31b5e3d8bdfb7f78efe5c6ca2d5363473d69e392694062b6",
      "completed_at": "2026-06-06T00:24:38Z",
      "doc_hash_after": "sha256:881cc0020964d71755606bfc296215e1e2d1818e6780f716479854d02cb85c72"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-06T00:24:44Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:881cc0020964d71755606bfc296215e1e2d1818e6780f716479854d02cb85c72",
      "completed_at": "2026-06-06T00:25:26Z",
      "doc_hash_after": "sha256:7ac606257942900a56e8428a6a14b3795aeffaac51b7df4d216e1c0e32fd3a87"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-06T00:25:41Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:7ac606257942900a56e8428a6a14b3795aeffaac51b7df4d216e1c0e32fd3a87",
      "completed_at": "2026-06-06T00:26:48Z",
      "doc_hash_after": "sha256:68bb5e116cd6636815d81e54233ef8b79a218bbb5cc4dc6ebbe87554643d4871"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-06T00:27:10Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:68bb5e116cd6636815d81e54233ef8b79a218bbb5cc4dc6ebbe87554643d4871",
      "completed_at": "2026-06-06T00:39:35Z",
      "doc_hash_after": "sha256:921b0199887fd3aa59979ca801cb00cd02277ecb99373580b71855bbe3a026a7"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The Claim (falsifiable)

Codex Dock is realtime enough when a real iPhone 17 simulator, connected to the
normal Dock relay at `ws://<Mac>:4510`, visibly receives Dock, Archive, and open
Thread Detail changes from real Codex app-server data without waiting for the
relay's broad periodic reconcile timer.

The success test is not "the relay eventually knows." The success test is: the
simulator receives the visible projection update for each covered event class,
through the normal app route, with measured event-to-UI latency and real row
identity proof.

## 0.2 Non-Negotiables

- App-server-first: normal card truth comes from Codex app-server APIs and
  app-server notifications, not from the relay acting as a second Codex history
  indexer.
- Relay-owned projection: the phone continues to consume relay projection
  envelopes such as `dock/update`, `archive/update`, and
  `thread/detail/update`. The phone does not subscribe directly to raw Codex
  app-server `:4500` data or bearer tokens.
- Targeted normal path: when one thread changes, the relay updates or
  re-proves one thread, then pushes one projection delta. Broad list scans are
  allowed for boot, recovery, and safety only.
- Real proof: fixture tests may support contract coverage, but completion
  requires real simulator proof against real Codex app-server data and real
  relay routing.
- No functionality loss: Dock, Archive, Thread Detail, rename, archive,
  unarchive, latest activity/order, latest summary, running/approval/input
  badges, hidden-child/private rollup behavior, foreground recovery, sequence
  gap recovery, and stale/offline UI all continue to work.
- Delete old paths: after realtime replacements are proven, delete or demote
  normal-path polling and broad disk-enrichment code instead of leaving parallel
  truth sources.
- Backstops are explicit: local process discovery, `lsof`, token-file
  bootstrap, `session_index.jsonl`, and rollout metadata stay only where current
  Codex app-server APIs provably cannot provide the data yet.

## 0.3 What This Does Not Promise

- It does not make endpoint discovery pure app-server today. The relay cannot
  ask an app-server where the app-server is before it has discovered one.
- It does not make unrelated private `stdio` Codex runtimes attachable. Current
  private runtimes can be detected locally but are not full app-server event
  streams.
- It does not subscribe the phone to every thread's full detail stream.
- It does not remove recovery snapshots. Realtime systems still need catch-up
  after missed events, restart, sequence gaps, and reconnects.

# 1) Key Design Considerations (what matters most)

## 1.1 Responsiveness Is End-To-End

The important metric is event-to-visible-client latency:

```text
Codex event
  -> relay receives or discovers invalidation
  -> relay updates/proves exactly the affected card/detail projection
  -> relay emits dock/update, archive/update, or thread/detail/update
  -> simulator renders the changed visible row/state
```

Relay status endpoints and logs are not enough. A passing implementation needs
structured simulator samples showing the UI changed through the normal app path.

## 1.2 Keep The Existing Client Contract

The Swift client already has a good projection-stream shape:

- `AppServerThreadCardStreamClient` connects to a relay endpoint, subscribes,
  listens for `dock/update` or `archive/update`, and exposes async updates.
- `StreamReconciler` treats pushed envelopes as primary, and resyncs only for
  recovery reasons such as sequence gaps, heartbeat timeout, reconnect,
  foreground resume, or manual refresh.
- `CodexDockConstants` has client recovery timers, but those timers are not the
  normal card truth path.

Therefore the cleanest architecture keeps the phone protocol stable and moves
the latency fix into the relay's upstream learning path.

## 1.3 Do Not Make The Relay A Bigger Poller

The bad fix is "poll faster." That increases load and still leaves visible
latency tied to timer boundaries.

The good fix is "listen broadly enough to know which thread changed, then read
narrowly enough to prove that one card." The relay should spend work
proportional to changed threads, not proportional to total historical rows.

## 1.4 Separate Normal Path From Backstop Path

The architecture needs two clear lanes:

- Normal lane: app-server notification -> event classifier -> direct card patch
  or dirty mark -> targeted read -> projection delta.
- Backstop lane: boot/restart/reconnect/sequence-gap/periodic safety ->
  snapshot reconcile -> projection snapshot or catch-up pages.

If a code path can run every few seconds forever, it must be labeled as
discovery or recovery, not normal visible-update truth.

## 1.5 Exceptions Must Have Owners And Removal Criteria

Current app-server gaps are real, but they are narrow:

- endpoint discovery and bearer-token bootstrap;
- unrelated private `stdio` runtime ownership;
- one observed `thread/list` missing row that `thread/read` could read;
- unreliable `threadSource` and `forkedFromId` population, despite structured
  `Thread.source` covering almost all sampled classification needs.

Those exceptions should be isolated behind named interfaces with tests and
future removal criteria, not mixed into normal card assembly.

# 2) Problem Statement (existing architecture + why change)

Codex Dock already has a push stream from relay to phone, but the relay often
learns Codex changes through polling-style reconciliation.

Current behavior:

- The phone subscribes to `dock/subscribe`, `archive/subscribe`, or
  `thread/detail/subscribe`.
- The relay pushes projection deltas when its SQLite-backed projection store
  changes.
- The relay discovers app-server endpoints on a timer.
- The relay discovers loaded live rows on a timer.
- The relay periodically runs broad Dock and Archive reconciliation.
- Full Dock reconciliation calls `thread/list`, enriches rows, supplements with
  `session_index.jsonl`, reads live leases, calls `thread/turns/list` to prove
  activity/summary, and then publishes changed cards.
- Current relay notification hooks ingest `thread/name/updated` and
  `thread/status/changed`, but those hooks still drive broad reconciliation
  instead of a first-class targeted projection update.

That means the user can see significant delay between real Codex work changing
on the Mac and the phone reflecting it. The delay is not primarily because the
phone cannot receive realtime updates. It is because the relay does not yet use
Codex app-server events as the main Dock-card invalidation mechanism.

The change is worthwhile because Codex app-server already exposes the core
event facts:

- global lifecycle/status notifications for started, renamed, status changed,
  archived, unarchived, and closed threads;
- thread-scoped turn/item/server-request notifications after a connection is
  attached to a thread;
- read APIs for `thread/list`, `thread/read`, `thread/loaded/list`, and
  `thread/turns/list`;
- enough app-server thread fields for most card facts and classification.

The current system is close to the right shape. The missing architectural piece
is an explicit relay event bridge and targeted card projector.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 Ground Rules From Repo Instructions

- `Makefile` is the runnable source of truth.
- The normal phone-facing service is the Dock relay on `:4510`, not a phone
  connection to raw Codex app-server `:4500`.
- Completion-grade live-update proof today is
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`, but controlled
  fixture proof is not enough for this plan's final acceptance because the user
  explicitly requires real simulator proof against real data.
- `sim-ui-dump` is diagnostic visibility only, not live-update acceptance.
- Physical phone proof has separate rules, but this plan's explicit proof target
  is simulator-first.

Repo anchors:

- `AGENTS.md`
- `README.md`
- `Makefile`
- `docs/TESTING.md`

## 3.2 Phone-To-Relay Is Already Push-Shaped

Swift anchors:

- `CodexDock/State/AppServerThreadCardStreamClient.swift`
- `CodexDock/Projection/StreamReconciler.swift`
- `CodexDock/Configuration/CodexDockConstants.swift`

Evidence:

- `AppServerThreadCardStreamClient` subscribes to relay card streams and listens
  for `dock/update` / `archive/update` notifications.
- `StreamReconciler` applies pushed envelopes and triggers resync for recovery
  conditions: sequence gap, relay resync required, heartbeat timeout, foreground
  resume, transport reconnect, buffer overflow, and command-completed
  invalidation.
- `CodexDockConstants.Dock.autoRefreshInterval = 5s` and
  `streamHeartbeatTimeout = 15s` are recovery/liveness settings, not the main
  data path.

Conclusion: a major Swift subscription rewrite is not the primary requirement.
The plan may need simulator proof and small diagnostics, but the main
architecture work belongs in the relay.

## 3.3 Relay-To-Phone Is Already Push-Shaped

Relay anchors:

- `scripts/dock-relay-state-subscriptions.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-store.mjs`

Evidence:

- `StateSubscriptionHub.publishDelta()` sends deltas immediately to matching
  subscribers.
- `subscribeDock()` and `subscribeArchive()` return snapshots, buffer concurrent
  updates, then stream later deltas.
- `RelayStateStore.applyDockReconciliation()` records changed rows and
  projection deletions, and the state engine publishes `dock/update`.
- Heartbeats are liveness updates, not data polling.

Conclusion: the relay already has a projection-stream output contract. The
target should add targeted store mutations and event-driven publishing, not a
parallel phone protocol.

## 3.4 Relay-To-Codex Is The Polling/Timer Boundary

Relay anchors:

- `scripts/dock-relay-constants.mjs`
- `scripts/dock-relay-app-server-registry.mjs`
- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-live-status-cache.mjs`
- `scripts/dock-relay.mjs`

Evidence:

- `RELAY_STATE_RECONCILE_INTERVAL_MS = 30_000`.
- `LIVE_STATUS_REFRESH_INTERVAL_MS = 2_500`.
- `APP_SERVER_REGISTRY_REFRESH_INTERVAL_MS = 5_000`.
- `StateReconciler` schedules boot and periodic broad reconciliation.
- `reconcileDock()` drains `thread/list`, refreshes live leases, enriches human
  rows, reads `session_index.jsonl` supplements, canonicalizes with
  `thread/turns/list`, writes projection cards, then publishes deltas.
- `canonicalizeThreadRows()` proves card activity and summary by calling
  `thread/turns/list`.
- `ingestRelayStateNotification()` currently recognizes
  `thread/name/updated` and `thread/status/changed`, but both paths end in
  reconciliation rather than a narrow event-to-card update.
- Existing upstream clients already support `onNotification` and `onRequest`.

Conclusion: the relay has the plumbing to receive app-server events, but lacks
a unified event bridge and targeted card update engine.

## 3.5 Codex App-Server Has The Needed Event Surface For Most Work

Codex anchors:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/transport.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_state.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/bespoke_event_handling.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs`

Evidence:

- App-server broadcasts notifications to initialized clients unless filtered by
  capability or opt-out settings.
- Protocol includes `ThreadStartedNotification`,
  `ThreadStatusChangedNotification`, `ThreadArchivedNotification`,
  `ThreadUnarchivedNotification`, `ThreadClosedNotification`, and
  `ThreadNameUpdatedNotification`.
- Thread processor sends archive, rename, unarchive, and started
  notifications.
- Bespoke event handling emits `turn/started`, `turn/completed`,
  `item/started`, `item/completed`, server requests, realtime transcript/audio,
  and related progress notifications for attached thread listeners.
- `Thread.turns` is intentionally empty for most list and notification payloads;
  turns are populated on read/resume/fork/rollback paths or via
  `thread/turns/list`.

Conclusion: most visible Dock-card changes can be event-invalidated even when a
targeted read is still needed to prove latest summary/activity.

## 3.6 Live Data Evidence From 2026-06-05

The existing live audit in
`docs/CODEX_DOCK_REALTIME_VS_POLLING_ARCHITECTURE_2026-06-05.md` used real
local Codex data, not fixtures. Raw evidence was written to
`/tmp/codex-client/app-server-disk-audit-OSv2Mw/evidence.json`.

Important findings:

- Relay was ready on `127.0.0.1:4510`.
- History app-server route was daemon/unix and ready.
- Registry saw 12 attachable live endpoints and 28 private owners.
- `thread/list` default active returned 295 rows across 3 pages.
- `thread/list` all-source active returned 1,854 rows across 19 pages.
- `thread/read(includeTurns:false)` succeeded for 25/25 sampled rows.
- `thread/turns/list(limit:1)` succeeded for 25/25 sampled rows.
- App-server-only classification matched rollout-enriched classification for
  500/500 sampled rows.
- `threadSource` and `forkedFromId` were not reliably populated as direct
  fields.
- `source.subAgent.thread_spawn.parent_thread_id` covered 393/394 sampled
  rollout fork ids where `forkedFromId` was null.
- `session_index.jsonl` had 15 ids missing from app-server `thread/list`; 14
  were stale/no rollout/read-failed, but one had rollout and `thread/read`
  succeeded while `thread/list` missed it.
- Runtime `thread/search` was unavailable in the running app-server.

Conclusion: app-server-first is correct for most card data, but pure
app-server-only is not yet correct for all discovery/index/private-runtime
cases.

## 3.7 Current Test Coverage Reality

Anchors:

- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.mjs`
- `scripts/dock-relay-card-contract.test.mjs`

Evidence:

- Controlled simulator scenarios already cover rename notification, status
  notification, archive toggle, private child status rollup, source refresh,
  foreground resume, live lease expiry, and activity/order behavior.
- The coverage ledger now has `COV-016` for the live app-server list/index gap.
- The current default simulator matrix is fixture-backed; it is valuable for
  deterministic regression coverage but cannot be the final proof for this
  realtime architecture.

Conclusion: implementation must add real-data simulator proof instead of only
expanding fixture scenarios.

## 3.8 Research Result

The elegant architecture is not "everything is pure push" and not "poll less
often." It is:

```text
App-server event
  -> relay event bridge
  -> direct patch or per-thread dirty mark
  -> targeted thread/read + thread/turns/list only when needed
  -> relay projection store update
  -> existing phone projection stream
  -> real simulator proof
```

The few things current app-server cannot provide are not the long pole for most
visible updates. They remain narrow boot/discovery/private/recovery exceptions.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 As-Is Data Flow

```text
Real Codex work changes on the Mac
  |
  | Codex app-server may emit notifications:
  | - thread/name/updated
  | - thread/status/changed
  | - thread/started, thread/archived, thread/unarchived, thread/closed
  | - turn/item/server-request events for attached thread listeners
  v
Dock relay
  |
  | Today the relay usually learns card truth through timers:
  | - app-server endpoint registry: every 5s
  | - live loaded status: every 2.5s
  | - broad Dock/Archive reconcile: every 30s plus triggered broad reconciles
  |
  | Broad Dock reconcile:
  | - thread/list
  | - thread/read enrichment
  | - session_index.jsonl supplement
  | - private owner merge
  | - thread/turns/list activity and summary proof
  | - write relay projection store
  v
Relay projection stream
  |
  | Existing push:
  | - dock/update
  | - archive/update
  | - thread/detail/update
  v
iPhone simulator / iPhone app
```

## 4.2 Phone Layer

The phone already consumes projection streams correctly:

- `CodexDock/State/AppServerThreadCardStreamClient.swift`
  - connects to the configured Dock relay endpoint;
  - sends `dock/subscribe`, `archive/subscribe`, `dock/resync`, or
    `archive/resync`;
  - listens for `dock/update` and `archive/update` notifications.
- `CodexDock/Projection/StreamReconciler.swift`
  - applies snapshots and deltas;
  - detects sequence gaps and stream contract errors;
  - uses resync for recovery;
  - treats heartbeat timeout and reconnect as liveness failures.
- `CodexDock/State/DockStore.swift` and
  `CodexDock/State/ArchiveStore.swift`
  - own per-host card reconcilers;
  - render from relay projection rows, not raw app-server rows.
- `CodexDock/State/ThreadDetailStore.swift` and
  `CodexDock/ThreadDetail/ThreadDetailProjectionStream.swift`
  - use a similar projection stream model for open detail routes.

Current client timers are recovery/liveness:

- `CodexDockConstants.AppServer.foregroundPollInterval = 250ms`
- `CodexDockConstants.Dock.autoRefreshInterval = 5s`
- `CodexDockConstants.Dock.streamHeartbeatTimeout = 15s`

Conclusion: the client is not the long pole for Dock-card realtime. The phone
should keep the same projection contract unless implementation evidence proves
otherwise.

## 4.3 Relay Projection Layer

The relay already has one projection store and one push surface:

- `scripts/dock-relay-state-store.mjs`
  - stores cards, freshness, sync scopes, projection changes, live leases, and
    archive state;
  - has broad methods like `applyDockReconciliation()` and
    `applyArchiveReconciliation()`;
  - has `cardForThread()` for current card lookup.
- `scripts/dock-relay-state-subscriptions.mjs`
  - publishes snapshots and deltas to active subscribers;
  - sends heartbeat envelopes for liveness.
- `scripts/dock-relay-state-engine.mjs`
  - orchestrates Dock and Archive reconciliation;
  - publishes `dock/update` and `archive/update` when the store changes;
  - handles current notification paths for rename/status by queueing mutation
    reconciliation.

Current gap: the store and engine are optimized around broad reconciliation.
They do not yet expose a clean "canonicalize one thread, update one card, emit
one delta" path.

## 4.4 Relay Upstream Learning Layer

The relay currently learns upstream facts through a mix of app-server APIs and
local machine reads:

- `scripts/dock-relay-app-server-registry.mjs`
  - discovers history and live endpoints;
  - tracks attachable live owners;
  - tracks private `stdio://` owners;
  - refreshes on a timer.
- `scripts/dock-relay-live-status-cache.mjs`
  - refreshes live loaded rows on a timer;
  - provides route snapshots and live overlays.
- `scripts/dock-relay-thread-data.mjs`
  - reads `thread/list`, `thread/read`, `thread/loaded/list`, and
    `thread/turns/list`;
  - reads rollout/session metadata and `session_index.jsonl`;
  - merges private owner rows;
  - classifies hidden children and rollups;
  - computes latest activity and latest summary.
- `scripts/dock-relay-upstream-pool.mjs` and
  `scripts/dock-relay-json-rpc-client.mjs`
  - already support upstream WebSocket clients and notification callbacks.
- `scripts/dock-relay.mjs`
  - has `ingestRelayStateNotification()` for current rename/status handling;
  - handles Thread Detail upstream notifications and server requests.

Current gap: upstream notifications are treated as hints to schedule existing
reconciliation, not as first-class events that update the projection store.

## 4.5 Codex App-Server Layer

The Codex app-server already provides most event signals needed for visible
realtime:

- initialized clients can receive broadcast notifications;
- protocol includes thread lifecycle/status notifications;
- `thread_processor.rs` sends started/archive/unarchive/rename notifications;
- `thread_status.rs` sends status-change notifications;
- `bespoke_event_handling.rs` sends turn/item/server-request/progress
  notifications for attached thread listeners;
- `thread_data.rs` documents that `Thread.turns` is empty for most list and
  notification payloads.

Current gap: there is no complete all-card summary feed. Latest summary and
proven activity still require targeted reads such as `thread/turns/list`.

## 4.6 Current Polling And Timer Inventory

Production timers that can affect visible latency:

- `APP_SERVER_REGISTRY_REFRESH_INTERVAL_MS = 5_000`
  - needed today for endpoint/private owner discovery.
- `LIVE_STATUS_REFRESH_INTERVAL_MS = 2_500`
  - used today to discover loaded live rows/status overlays.
- `RELAY_STATE_RECONCILE_INTERVAL_MS = 30_000`
  - broad Dock/Archive safety reconcile.
- `RELAY_STATE_RECONCILE_DEBOUNCE_MS = 250`
  - debounce for triggered broad reconcile.
- `RELAY_STATE_HEARTBEAT_INTERVAL_MS = 5_000`
  - relay stream heartbeat; not card truth.
- Swift heartbeat/reconnect/foreground timers
  - recovery and liveness, not normal card truth.

Target stance: keep discovery and recovery timers where needed, but remove broad
periodic reconcile as the normal visible-update mechanism.

## 4.7 Current Disk/Local State Pulls

Current Codex-disk/local pulls:

- rollout `session_meta`
  - currently supplements classification, source fields, fork fields, cwd, and
    Git facts;
  - app-server covers most normal card facts today;
  - direct `threadSource` and `forkedFromId` are not reliable enough to delete
    every fallback yet.
- `session_index.jsonl`
  - currently supplements rows missing from `thread/list`;
  - live evidence found one real readable missing row;
  - should be a narrow backstop until app-server list/index behavior is fixed.
- process list and `lsof`
  - discovers app-server endpoints, token files, and private `stdio` owners;
  - cannot be replaced by current app-server calls because discovery happens
    before connection and private runtimes are not attachable.
- relay-owned `.codex-dock/**`
  - relay cache/config/identity, not Codex thread truth.

Target stance: normal card facts should be app-server-first. Disk/local pulls
remain narrow, named exceptions.

## 4.8 Current Test Surface

Current checks relevant to this plan:

- Relay unit/contract:
  - `rtk npm run test:relay`
  - `rtk npm test`
  - `rtk npm run contract:check`
  - `rtk npm run test:host-service`
- Swift:
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
- Simulator:
  - `rtk make sim-ui-sync-proof SIM='iPhone 17'`
  - `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
  - `rtk make sim-ui-dump SIM='iPhone 17'`
- Current proof constants:
  - `MAX_UI_LAG_MS ?= 2000`
  - `SIM_UI_CONTROLLED_MATRIX_SAMPLE_MS ?= 250`

Current gap: the main matrix is controlled fixture proof. The new architecture
needs a real-data simulator proof target or scenario family. Existing
`sim-ui-sync-proof` is useful as today's real relay-backed displayed-UI
baseline, but it is not event-mutation acceptance for this plan.

## 4.9 Why The Few Missing App-Server Facts Are Not The Long Pole

The missing facts are important, but they do not force most visible updates to
remain polling-driven:

| Missing or partial fact | Does it block normal realtime card updates? | Why |
| --- | --- | --- |
| Endpoint discovery before connection | No for already discovered endpoints; yes for finding new endpoints. | Discovery can stay on a timer or future daemon registry while event bridge clients handle known endpoints in realtime. |
| Private `stdio` runtime ownership | No for attachable app-server threads; yes for private owner rollup discovery. | Private runtime detection remains a local backstop. It does not stop rename/status/turn updates from attachable app-server endpoints. |
| `thread/list` misses one readable indexed row | No for changed known rows; yes for pure app-server initial completeness. | Event-driven dirty reads can update known/readable changed rows. Boot/list completeness still needs a backstop or app-server fix. |
| `threadSource` direct field null | No for sampled classification; possible for exact metadata display. | Structured `Thread.source` covered nearly all sampled parent links and classification matched 500/500. |
| `forkedFromId` direct field null | No for most hidden-child rollups; possible for edge relationships. | `source.subAgent.thread_spawn.parent_thread_id` covered 393/394 sampled rollout fork ids. |
| Latest summary absent from event payload | No. | The event marks one thread dirty; targeted `thread/turns/list` proves summary/activity for that thread. |

Net: the long pole is relay architecture, not those gaps. The gaps define
backstops and future Codex app-server improvements.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 Target Data Flow

```text
Real Codex work changes on the Mac
  |
  | app-server notification where available
  v
Relay CodexEventBridge
  |
  | EventClassifier
  | - direct card patch
  | - per-thread dirty mark
  | - route/discovery/private fallback
  v
TargetedCardProjector
  |
  | direct patch OR targeted reads:
  | - thread/read(includeTurns:false)
  | - thread/turns/list only when latest activity/summary proof is needed
  |
  | one affected thread, not all rows
  v
Relay projection store
  |
  | existing projection stream
  v
dock/update / archive/update / thread/detail/update
  |
  v
Real iPhone 17 simulator visible UI sample within MAX_UI_LAG_MS
```

## 5.2 New Relay Components

### CodexEventBridge

Owns long-lived initialized upstream clients where the relay can attach:

- one history/daemon event connection where available;
- live endpoint event clients when route ownership is known and cheap enough;
- bounded thread listener leases for the active working set, because turn/item
  events are thread-scoped and require an attached connection;
- integration with existing upstream pool limits;
- reconnect/sequence health state;
- no phone secrets and no raw phone `:4500` path.

It ingests:

- `thread/started`
- `thread/name/updated`
- `thread/status/changed`
- `thread/archived`
- `thread/unarchived`
- `thread/closed`
- `turn/started`
- `turn/completed`
- `item/started`
- `item/completed`
- server requests that imply approval/input/attention state

### ThreadListenerLeaseManager

Owns the attach/unsubscribe lifecycle for thread-scoped events. This is the
piece that prevents "latest summary/activity within 2s" from silently depending
on broad polling.

Rules:

- Acquire a lightweight listener lease only for the working set:
  - open Thread Detail rows;
  - visible Dock rows in the current window;
  - rows with running/approval/input status;
  - rows selected by the real-data proof harness;
  - a small recent-active cap if needed.
- Attach through the existing app-server resume/listener path, using compact
  options such as `excludeTurns: true` where supported, then use targeted
  `thread/turns/list` after events for summary/activity proof.
- Do not attach to every historical thread.
- Release leases when:
  - the row leaves the visible/recent working set;
  - the thread closes;
  - the endpoint disappears;
  - an idle TTL expires.
- Track per-endpoint and total listener caps in
  `scripts/dock-relay-constants.mjs`.
- If no lease is held for a non-visible historical thread, do not claim 2s
  turn/item realtime for that thread. It remains covered by status/lifecycle
  events plus recovery/backstop snapshots.

This means the realtime claim is strongest for what the user can see and what
is currently working. Arbitrary deep-history rows remain snapshot/backstop
truth unless they enter the working set.

### EventClassifier

Maps each upstream event into one of four outcomes:

- direct patch:
  - rename/title;
  - status/badge if payload is enough;
  - archive/unarchive visibility;
  - closed/unloaded state.
- targeted dirty:
  - turn start/completion;
  - item start/completion;
  - message/summary-affecting events;
  - events where the payload lacks enough card proof.
- detail ledger:
  - open Thread Detail event handling remains ledger-based and pushes
    `thread/detail/update`.
- backstop:
  - unknown event, route mismatch, missed event, stale bridge, or private owner
    change schedules recovery, not normal full polling.

### ThreadDirtyQueue

Debounces by `{sourceHostID, threadID, reason}` and coalesces bursty events.

Rules:

- direct patches can publish immediately when safe;
- targeted reads are per-thread and bounded by concurrency;
- repeated turn/item events for the same thread collapse into one pending read;
- failure marks only the affected card/scope stale where possible;
- sequence gaps escalate to snapshot resync.

### TargetedCardProjector

Builds one canonical Dock/Archive card from app-server data:

- chooses route through `AppServerRegistry.routeForThreadMethod`;
- calls `thread/read(includeTurns:false)` for metadata/status;
- calls `thread/turns/list` only when order/latest summary/activity proof is
  needed;
- runs the same human/subagent/private classification logic as broad reconcile;
- computes rollups from structured `Thread.source` first;
- uses rollout/session metadata only for named app-server gaps;
- updates exactly one active/archive projection row or projection deletion.

### Targeted Store Mutations

Add relay store methods that are equivalent to broad reconciliation for one
thread:

- upsert one active card;
- upsert one archived card;
- move active -> archived;
- move archived -> active;
- mark one card inactive/closed;
- apply one hidden-child rollup update to the visible parent;
- record one scoped freshness failure without marking the whole stream broadly
  stale unless the failure is route-wide.

These methods must preserve projection IDs, sequence ordering, freshness,
window/catch-up behavior, and subscriber delta semantics.

## 5.3 Backstop Architecture

The plan keeps polling where it is genuinely needed:

- boot snapshot;
- relay restart;
- app foreground/reconnect resync;
- sequence gap recovery;
- periodic low-frequency correctness audit;
- endpoint discovery until Codex provides a registry;
- private `stdio` owner discovery until Codex exposes private runtime
  heartbeats;
- `session_index.jsonl` backstop until app-server list/index equivalence is
  fixed.

Backstop code must be clearly named and lower priority than event-driven card
updates. It must not be the path that makes normal visible changes appear.

## 5.4 Client Target

Keep the existing client projection contract:

- no direct raw `:4500` app-server subscription;
- no phone-side bearer token;
- no phone subscription to every thread detail stream;
- no client-side polling to hide relay latency.

Allowed client work:

- add or improve simulator proof hooks;
- add performance/diagnostic fields that prove update latency and route family;
- fix small freshness-display bugs if the proof reveals a client display issue;
- keep existing recovery behavior.

## 5.5 Event Coverage Target

Realtime or event-invalidated:

- server rename;
- client rename canonical confirmation;
- archive/unarchive;
- status badge changes;
- new thread appearance;
- closed/unloaded thread state;
- running/idle transition;
- approval/input needed;
- turn started/completed activity order;
- latest summary after message/turn completion;
- hidden child running/approval rollup when owner evidence exists;
- open Thread Detail item/message/request events.

Backstop only:

- first full Dock load;
- first full Archive load;
- reconnect after missed events;
- sequence gap catch-up;
- app-server endpoint discovery;
- private `stdio` owner discovery;
- app-server `thread/list` readable-missing-row gap;
- exact `threadSource`/`forkedFromId` gaps until Codex app-server fields are
  reliable.

## 5.6 Desired Latency Budget

Use the existing `MAX_UI_LAG_MS ?= 2000` as the default pass/fail budget for
simulator-visible realtime scenarios.

Expected targets:

- direct patch events: simulator visible within 2s;
- targeted-read events: simulator visible within 2s when upstream read latency
  is healthy;
- recovery/backstop events: not scored as realtime, but must report why the
  normal event path was unavailable.

## 5.7 Deletion Target

After proof passes:

- broad periodic reconcile stops being the normal update path;
- current rename/status "notification -> broad reconcile" code is replaced by
  event classifier + targeted projector;
- normal card classification stops depending on rollout metadata when
  app-server structured source is sufficient;
- `session_index.jsonl` supplement is isolated as a backstop, not mixed into
  every normal Dock/Archive reconcile;
- fixture-only proof claims are deleted or reworded as fixture-only support;
- stale diagnostic side doors remain diagnostic-only and cannot be cited as
  completion proof.

## 5.8 Event Handling Matrix

| Event/fact | Source today | Target relay handling | Target read cost | Client proof |
| --- | --- | --- | --- | --- |
| Server rename | `thread/name/updated` | Direct patch title, then optional targeted verify | 0-1 `thread/read` | Dock row title changes in simulator within 2s. |
| Client rename | `thread/name/set` response plus optional `thread/name/updated` | Optimistic command response remains fast; canonical event updates same projection once | 0-1 `thread/read` | Rename sheet dismisses quickly; canonical title appears once. |
| Status running/idle | `thread/status/changed` | Direct patch badge/status and order key if needed | Usually 0; targeted read if row absent | Working badge appears/disappears within 2s. |
| Approval/input needed | `thread/status/changed` or server request | Direct attention badge; detail ledger handles request card | 0 for card, detail request as existing stream | Dock badge and detail request card visible. |
| New thread | `thread/started` | Targeted card create | `thread/read`, maybe `thread/turns/list` | New real row appears without waiting for 30s reconcile. |
| Archive | `thread/archive` response and `thread/archived` | Move/delete active card, upsert archive card as needed | 0-1 `thread/read` | Row leaves Dock and appears in Archive. |
| Unarchive | `thread/unarchive` response and `thread/unarchived` | Move/delete archive card, upsert active card | 0-1 `thread/read` | Row leaves Archive and appears in Dock. |
| Thread closed | `thread/closed` | Mark closed/inactive or remove live overlay | 0 | Badge/availability changes without timer wait. |
| Turn started | `turn/started` | Mark thread dirty for activity/status | `thread/read`, maybe `thread/turns/list` | Row moves/updates activity within 2s. |
| Turn completed | `turn/completed` | Dirty read for latest summary/activity/status | `thread/read` + `thread/turns/list` | Latest summary/activity updates within 2s. |
| Item started/completed | `item/started`, `item/completed` | Dirty read only for card-affecting item types; detail ledger unchanged | 0 or targeted read | Detail stays live; Dock updates if activity/attention changed. |
| Hidden child rollup | app-server source/status or private owner evidence | Update parent rollup; hide child row | 0-1 targeted reads plus private backstop if needed | Parent badge reflects child; child remains filtered. |
| App-server endpoint appears | process/daemon discovery today | Discovery backstop, future daemon registry | Process scan or registry | Not scored as realtime; must not break existing rows. |
| Private runtime appears | process/`lsof` today | Discovery/private-owner backstop | Process/`lsof` | Parent rollup if evidence exists; detail shows private limitation correctly. |
| Missed event/reconnect | relay/client health | Snapshot/resync | Broad read | UI recovers and records backstop reason. |

## 5.9 Data Availability Matrix

| Card field | App-server primary | Target fallback | Removal condition |
| --- | --- | --- | --- |
| Thread id/session id | `Thread.id`, `Thread.sessionId` | none for app-server-readable rows | Already primary. |
| Title/name | `Thread.name`, rename notification | targeted read if event lacks title | Already primary. |
| Status/badge | `Thread.status`, `thread/status/changed` | private owner detector for private `stdio` rows | Codex exposes private runtime registry/status. |
| Created/updated/activity | `Thread.createdAt`, `Thread.updatedAt`, `thread/turns/list` | session index only for readable-missing list gap | App-server list/index equivalence proven. |
| Latest summary | `thread/turns/list` | none; if read fails mark card partial/stale | App-server card summary feed exists. |
| CWD/Git | `Thread.cwd`, `Thread.gitInfo` | rollout metadata only for missing app-server fields | Live audit proves app-server fields complete. |
| Source/classification | `Thread.source` | rollout metadata for exact unresolved relationships | App-server exposes reliable relationship fields. |
| `threadSource` | `Thread.threadSource` if populated | rollout `thread_source` | Field populated or no longer used. |
| `forkedFromId` | `Thread.forkedFromId` plus `source.subAgent.thread_spawn.parent_thread_id` | rollout `forked_from_id` | Relationship equivalence proven on live corpus. |
| Archive state | `thread/list({archived})`, `Thread.path` as validation | path inference only for backstop rows | App-server archive lists are complete. |
| Endpoint URL/token | none before connection | process/daemon/token-file discovery | Codex daemon registry provides connect metadata. |
| Private owner | none for unrelated `stdio` runtimes | process/`lsof` | Codex runtime registry/heartbeat exists. |

## 5.10 Failure Behavior

Failure must be visible and narrow:

- targeted read fails for one thread:
  - mark that card partial/stale when a prior card exists;
  - do not mark the entire Dock stale unless the route failure is host-wide.
- event bridge loses an endpoint:
  - record bridge stale/offline telemetry;
  - schedule snapshot/backstop reconciliation;
  - keep existing cards but show correct freshness.
- sequence gap or reducer contract failure:
  - use existing client resync path.
- event source says a thread changed but route resolves to private owner:
  - update private capability/rollup if possible;
  - detail route should fall back to history snapshot or show the private
    runtime limitation, not pretend full live detail is attachable.
- backstop detects a different truth than event path:
  - backstop wins after recording a discrepancy metric and proof breadcrumb.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Relay Files To Change Or Audit

### Core State And Projection

- `scripts/dock-relay-state-engine.mjs`
  - add targeted card update entrypoints;
  - replace rename/status broad reconciliation handlers with event classifier
    dispatch;
  - keep broad reconciliation for boot/recovery;
  - wire targeted updates to existing `StateSubscriptionHub`.
- `scripts/dock-relay-state-store.mjs`
  - add one-card active/archive upsert and delete/move APIs;
  - preserve projection change recording and sequence rules;
  - keep `applyDockReconciliation()` / `applyArchiveReconciliation()` for
    snapshots only.
- `scripts/dock-relay-state-subscriptions.mjs`
  - audit delta completeness, oversized update fallback, and catch-up behavior
    for targeted one-card deltas.

### Event Bridge And Upstream Routing

- New or existing relay module:
  - likely `scripts/dock-relay-event-bridge.mjs`;
  - owns upstream event clients, reconnects, event health, and notification
    normalization.
- `scripts/dock-relay.mjs`
  - replace current `ingestRelayStateNotification()` special casing with bridge
    dispatch;
  - keep Thread Detail ledger routing intact;
  - ensure server requests still reach open detail sessions.
- New or existing listener lease module:
  - own bounded `thread/resume`/listener attachment for the working set;
  - release listeners when rows leave the visible/recent set, close, or expire;
  - feed turn/item events into the dirty queue;
  - record when a row is not realtime-scored because no listener lease exists.
- `scripts/dock-relay-upstream-pool.mjs`
  - audit pool labels and limits for bridge clients;
  - prevent bridge clients from starving detail/live-status clients.
- `scripts/dock-relay-json-rpc-client.mjs`
  - audit notification callback and reconnect behavior;
  - no protocol change expected unless bridge needs lifecycle hooks.
- `scripts/dock-relay-app-server-registry.mjs`
  - expose current endpoint snapshots to the event bridge;
  - preserve discovery/private owner timers as backstops;
  - report private owner changes as invalidation signals where possible.

### Thread Data And Classification

- `scripts/dock-relay-thread-data.mjs`
  - extract reusable "canonicalize one thread" function from
    `canonicalizeThreadRows()`;
  - separate app-server-first normal card build from disk fallback supplement;
  - keep `thread/turns/list` latest summary/activity proof for targeted reads;
  - keep private owner and session-index gaps isolated.
- `scripts/dock-relay-origin-classifier*.mjs` or current classifier module
  resolved by imports from `dock-relay-thread-data.mjs`
  - audit classification parity between broad and targeted paths.
- `scripts/dock-relay-projection-engine.mjs`
  - audit `normalizeThread()`, order key generation, hidden rollups, freshness,
    and card contract fields used by one-card updates.
- `scripts/dock-relay-live-status-cache.mjs`
  - decide whether live status cache becomes a backstop/snapshot helper rather
    than normal badge latency path.

### Constants, Logging, Diagnostics

- `scripts/dock-relay-constants.mjs`
  - add bridge debounce/concurrency/health constants;
  - avoid hard-coded intervals elsewhere.
- `scripts/dock-relay-logger.mjs`
  - structured logs for event received, event classified, targeted read start,
    targeted read finished, projection delta emitted, and proof correlation id.
- Relay diagnostics/status routes in `scripts/dock-relay*.mjs`
  - expose bridge health, event counts, dirty queue size, targeted-read latency,
    last backstop reason, and normal-path vs backstop update counts.

## 6.2 Swift Files To Change Or Audit

Expected minimal client code change:

- `CodexDock/State/AppServerThreadCardStreamClient.swift`
  - likely no protocol change;
  - audit performance fields and route observability.
- `CodexDock/Projection/StreamReconciler.swift`
  - likely no behavior change;
  - audit that targeted deltas preserve reducer contract.
- `CodexDock/State/DockStore.swift`
  - audit state rendering after rapid one-card updates.
- `CodexDock/State/ArchiveStore.swift`
  - audit archive/unarchive move behavior.
- `CodexDock/State/ThreadDetailStore.swift`
  - keep current detail stream path;
  - ensure command-completed invalidation still behaves.
- `CodexDock/Dock/DockDataEngine.swift`
  - audit projection row ordering after targeted updates.
- `CodexDock/State/ThreadCardRowProjector.swift`
  - audit new/changed relay fields, if any.
- `CodexDock/Automation/DockAutomationSnapshotStore.swift`
  - add or confirm fields needed for real-data simulator proof.
- `CodexDock/Configuration/CodexDockConstants.swift`
  - no new production interval unless client proof/recovery genuinely needs it.

## 6.3 Simulator And Proof Files To Change Or Audit

- `Makefile`
  - add a current, real-data simulator proof target; do not describe proposed
    targets as current until they exist.
- New proof scripts under `scripts/`
  - create reversible real-data event scenarios;
  - write structured JSON/Markdown proof;
  - fail if data comes only from fixtures.
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
  - keep as deterministic support only.
- `scripts/dock-relay-controlled-simulator-matrix.mjs`
  - keep fixture matrix, but do not allow it to satisfy real-data acceptance.
- `scripts/dock-relay-simulator-ui-sync-proof.mjs`
  - reuse proof report format if compatible.
- `contract/proof/**`
  - add or update proof schemas for real-data event path evidence.
- `docs/TESTING.md`
  - document current real-data proof command after it exists.
- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`
  - add scenarios/failure-class rows for realtime event coverage and app-server
    list/index equivalence.

## 6.4 Relay Tests To Add Or Update

- Notification bridge:
  - app-server notifications create direct patch or dirty mark;
  - unknown events fail closed into backstop;
  - bridge reconnect does not duplicate updates.
- Targeted projector:
  - one changed row emits one `dock/update`;
  - latest activity/order updates after `turn/completed`;
  - latest summary updates through targeted `thread/turns/list`;
  - archive/unarchive moves between Dock and Archive;
  - private child rollup updates visible parent without leaking child row.
- Backstop split:
  - broad reconcile is still used for boot/recovery;
  - normal rename/status/turn events do not require broad reconcile.
- Disk fallback isolation:
  - normal app-server fields bypass rollout/session-index reads where possible;
  - list/index gap backstop is explicit and tested.
- Contract:
  - proof output records event source, route family, real-data flag, simulator
    samples, latency, and pass/fail reason.

## 6.5 Swift Tests To Add Or Update

- `AppServerClientTests`
  - only if DTO/protocol fields change.
- `DockStoreTests`
  - rapid one-row delta ordering;
  - stale/freshness display after targeted failure;
  - archive/unarchive move display if relay envelope shape changes.
- `ThreadDetailStoreTests`
  - only if detail event/freshness behavior changes.
- UI tests
  - add real-data over-time sampler assertions:
    - route is `ws://<Mac>:4510`;
    - rows are real relay projection rows;
    - event mutation happens after initial UI sample;
    - UI sample observes the changed row within 2s;
    - original real data is restored when scenario mutates title/archive state.

## 6.6 Codex App-Server Change Candidates

This plan is relay-first, but two clean upstream fixes may be needed later:

- app-server list/index equivalence:
  - every app-facing readable persisted thread should be returned by
    `thread/list` or an explicit recent/index API;
  - this would retire the `session_index.jsonl` backstop.
- daemon/runtime registry:
  - list app-server endpoints and private runtime owners;
  - expose auth/connect metadata without token-file scraping;
  - retire process/`lsof` discovery for normal operation.

Do not block relay realtime work on these unless implementation proof shows the
missing app-server pieces are the long pole for the specific event class.

## 6.7 Exact Current Call Sites That Must Not Be Left Ambiguous

Relay:

- `RelayStateEngine.start()`
  - still starts broad recovery reconcile, but normal event path must not depend
    on the 30s timer.
- `RelayStateEngine.reconcileDock()`
  - remains boot/recovery/safety snapshot path.
- `RelayStateEngine.reconcileArchive()`
  - remains boot/recovery/safety snapshot path.
- `RelayStateEngine.refreshLiveLeases()`
  - becomes backstop/snapshot support or a private-status aid, not the only
    badge update path.
- `RelayStateEngine.handleThreadNameNotification()`
  - must stop queueing broad Dock+Archive reconciliation as its primary action.
- `RelayStateEngine.handleThreadStatusNotification()`
  - must stop queueing broad Dock reconciliation as its primary action.
- `reconcileThreadNameAfterResponse()` in `scripts/dock-relay.mjs`
  - must route into targeted canonical confirmation.
- `thread/archive` and `thread/unarchive` handlers in `scripts/dock-relay.mjs`
  - currently call `RelayStateEngine.handleArchiveMutation()` after command
    responses;
  - must route archive/unarchive into targeted active/archive moves, with broad
    reconcile demoted to recovery.
- `RelayStateEngine.handleArchiveMutation()`
  - currently queues `reconcileDockAndArchiveAfterMutation()`;
  - must stop being the primary normal path for archive/unarchive visibility.
- `subscribeThreadDetail()` / `resyncThreadDetail()` in `scripts/dock-relay.mjs`
  - must keep existing ledger behavior and private-owner fallback.
- `readLoadedRows()` / `collectLiveRows()` in `scripts/dock-relay-thread-data.mjs`
  - must not remain the only way live status reaches Dock.
- `canonicalizeThreadRows()`
  - must be split or wrapped so one-thread canonicalization shares identical
    proof semantics with broad reconciliation.
- `readSessionIndexHumanStartedSupplements()`
  - must be isolated behind an explicit list/index backstop.

Swift:

- `DockStore.makeReconciler(for:)`
  - must keep the same projection-stream contract.
- `ArchiveStore.makeReconciler(for:)`
  - must keep the same projection-stream contract.
- `ThreadDetailStore.load()` and retained refresh paths
  - must keep detail projection behavior.
- `ThreadCardRowProjector`
  - must continue to require relay projection identity fields.
- `DockAutomationSnapshotStore`
  - must expose enough stable row data for real-data proof.

Tests/proof:

- `scripts/dock-relay-card-contract.test.mjs`
  - add event bridge and targeted projector coverage.
- `scripts/dock-relay-controlled-simulator-matrix.test.mjs`
  - keep fixture coverage but do not treat it as real-data proof.
- `CodexDockUITests/CodexDockDisplayedSyncProofTests`
  - reuse or extend for real-data over-time proof.
- `Makefile`
  - owns all simulator proof commands.

## 6.8 Real-Data Scenario Inventory Required Before Completion

Each scenario must record:

- real relay URL and host id;
- real app-server route source;
- real thread id and title before/after when mutated;
- event timestamp, relay receive timestamp, projection seq, UI observe
  timestamp;
- whether the update used direct patch, targeted read, or backstop;
- whether data was restored.

Required scenarios:

- real server rename notification:
  - rename a sacrificial real thread through app-server/relay and restore it.
- real status transition:
  - use a real active Codex thread or a sacrificial real Codex thread that can
    produce running -> idle.
- real turn completion/latest summary:
  - append or trigger a real turn in a sacrificial real thread, then prove Dock
    latest summary/activity updates;
  - proof must show the relay held a listener lease or record that the scenario
    is not realtime-scored.
- real archive/unarchive:
  - archive and unarchive a sacrificial real thread and restore final state.
- real open Thread Detail:
  - keep detail open while a real event arrives, proving `thread/detail/update`.
- real reconnect/recovery:
  - force stream reconnect or sequence recovery and prove resync still works.
- real app-server list/index audit:
  - compare app-server list/read/session-index enough to prove whether COV-016
    still exists;
  - treat this as a real-data live audit plus UI/backstop visibility proof when
    applicable, not as a 2-second realtime event like rename/status/activity.
- real private runtime capability:
  - if a private owner exists, prove list badge/detail capability are coherent;
  - if unavailable, record exact blocker and do not claim private runtime
    realtime completion.

Sacrificial real thread rule: a test-created Codex thread is acceptable real
data only if it is created through the actual Codex app-server/relay path, not a
fixture server, mock transport, scripted WebSocket, or controlled simulator
fixture.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
## Phase 0 - Baseline Proof Contract And Failing Real-Data Harness

Goal: before changing relay behavior, create proof that can fail against the
current polling-driven behavior and can later prove the realtime fix.

Implementation checklist:

- Add a proposed Makefile-owned proof target, for example
  `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'`.
- The target must start/reuse `rtk make services`, build/launch the app through
  existing Makefile app flow, and connect only to `ws://<Mac>:4510`.
- Add a proof script that selects or creates sacrificial real Codex threads via
  actual app-server/relay paths.
- Add reversible mutations:
  - rename and restore title;
  - archive and unarchive;
  - turn/message activity where feasible;
  - open detail and observe update.
- Add proof JSON/Markdown schemas under `contract/proof/**`.
- Add automation fields to simulator samples if needed:
  - host id;
  - thread id;
  - title/status/archive state/latest summary;
  - projection seq;
  - route family;
  - observed timestamp.
- Mark every scenario as one of:
  - `direct_patch`;
  - `targeted_read`;
  - `backstop`;
  - `blocked`.
- Fail proof if the route is fixture, loopback-only raw app-server, mock
  WebSocket, scripted transport, `projection/witness/read`, or status endpoint
  only.

Tests/checks:

- `rtk npm run contract:check`
- `rtk npm test`
- `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` once the target
  exists.

Exit criteria:

- The proof target exists and is Makefile-owned.
- Proof can identify real-data vs fixture data.
- Current behavior is measured honestly, even if it fails the 2s realtime
  budget before implementation.
- No production behavior has changed in this phase except proof/diagnostic code.

## Phase 1 - One Vertical Slice: Server Rename To Simulator UI

Goal: prove one complete event path end to end before generalizing.

Chosen slice: `thread/name/updated` -> relay targeted title update -> existing
`dock/update` -> simulator row title changes within `MAX_UI_LAG_MS`.

Implementation checklist:

- Add `CodexEventBridge` or the smallest module that will become it.
- Keep one initialized history/daemon upstream event connection where available.
- Normalize app-server notifications into internal event records:
  - source endpoint;
  - method;
  - thread id;
  - received timestamp;
  - event id/correlation id.
- Add `EventClassifier` support for `thread/name/updated`.
- Add store method for one-card direct title patch when a card already exists.
- If a card does not exist, route to targeted read/create instead of broad
  reconcile.
- Replace current primary rename notification path in
  `RelayStateEngine.handleThreadNameNotification()` with this targeted path.
- Preserve `thread/name/set` command behavior:
  - response remains fast;
  - canonical event/targeted verification updates the projection;
  - duplicate title transitions are collapsed.
- Add structured logs:
  - event received;
  - event classified;
  - card patched;
  - projection delta emitted;
  - simulator proof correlation.

Tests/checks:

- Relay unit test: server rename notification patches one row without calling
  broad `reconcileDock()`.
- Relay unit test: unknown/missing card schedules targeted read or backstop.
- Existing rename tests in `scripts/dock-relay-card-contract.test.mjs`.
- Real-data simulator rename scenario.

Exit criteria:

- Simulator sees real rename within 2s through `dock/update`.
- The proof report shows `direct_patch` or `targeted_read`, not broad polling.
- Original real title is restored.
- Existing controlled rename tests still pass.

## Phase 2 - TargetedCardProjector For One-Thread Reads

Goal: create the reusable canonical one-thread builder that all non-direct event
classes use.

Implementation checklist:

- Extract one-thread canonicalization from `canonicalizeThreadRows()` without
  changing broad reconcile semantics.
- Build from app-server-first data:
  - route with `AppServerRegistry.routeForThreadMethod`;
  - read `thread/read(includeTurns:false)`;
  - call `thread/turns/list` only when latest activity/summary/order proof is
    needed.
- Reuse the same classifier and projection normalization as broad reconcile.
- Reuse hidden-child rollup logic.
- Expose one-card store mutations:
  - active upsert;
  - archived upsert;
  - active delete;
  - archive move;
  - unarchive move;
  - stale/partial one-card update.
- Keep broad reconcile as a safety snapshot, not as the normal update path.
- Add per-thread dirty queue with bounded concurrency and debounce constants in
  `scripts/dock-relay-constants.mjs`.

Tests/checks:

- Unit tests compare broad canonicalization and targeted canonicalization for
  the same row.
- Unit tests prove `thread/turns/list` is called for activity/summary events
  and not called for direct-only title/status patches.
- Unit tests prove one thread dirty burst results in one targeted read.
- `rtk npm run test:relay`
- `rtk npm test`

Exit criteria:

- Targeted projector produces byte-equivalent card fields for sampled cases
  except for intentional freshness/correlation metadata.
- Projection sequence and reducer behavior remain compatible with the Swift
  client.
- No broad reconcile is needed for the rename vertical slice anymore.

## Phase 3 - Status, Working Badge, Approval/Input, And Closed Events

Goal: make visible status badges realtime for attachable app-server rows.

Implementation checklist:

- Add event classifier handling for:
  - `thread/status/changed`;
  - server requests implying approval/input state;
  - request resolved;
  - `thread/closed`.
- Direct-patch status when the event payload is enough.
- Fall back to targeted read when:
  - card is missing;
  - status payload is not enough for card contract;
  - hidden child/parent mapping needs proof.
- Replace current primary status notification path in
  `RelayStateEngine.handleThreadStatusNotification()`.
- Keep private runtime status as local backstop until Codex exposes private
  runtime event/registry APIs.

Tests/checks:

- Relay unit test: `thread/status/changed` updates status without broad
  reconcile.
- Relay unit test: root private owner does not falsely turn parent running.
- Relay unit test: private spawned child owner rolls up when evidence exists.
- Real-data simulator status scenario.
- Real-data simulator private capability scenario, or exact blocker.

Exit criteria:

- Working badge appears/disappears in simulator within 2s for a real attachable
  app-server row.
- Approval/input state remains coherent between Dock and open Thread Detail.
- Private runtime limitations are explicit and not falsely shown as full live
  attachability.

## Phase 4 - Activity Order And Latest Summary

Goal: make the Dock row order and latest summary update from real turns without
waiting for a broad list scan.

Implementation checklist:

- Add event classifier handling for:
  - `turn/started`;
  - `turn/completed`;
  - card-affecting `item/started`;
  - card-affecting `item/completed`;
  - message/summary-affecting notifications when they exist.
- Dirty-mark thread on these events.
- Add the `ThreadListenerLeaseManager` before claiming turn/item realtime:
  - lease open detail threads;
  - lease visible/current-work Dock rows;
  - lease proof-selected sacrificial threads;
  - enforce endpoint and global caps;
  - release by visibility, close, endpoint loss, and idle TTL.
- Targeted projector calls `thread/turns/list` and updates:
  - `activityAt`;
  - `activityAtMs`;
  - `displayOrderKey`;
  - `latestSummary`;
  - `displaySummary`;
  - proof fields.
- Preserve current order contract:
  - relay order key first;
  - projection id tie-breaker;
  - no Swift-side order recovery.
- Make failures narrow:
  - one card partial/stale if targeted summary proof fails;
  - host-wide stale only for host-wide route failure.

Tests/checks:

- Relay unit test: no listener lease means no false 2s turn/item realtime
  claim for a non-working-set historical row.
- Relay unit test: listener lease receives turn/item event and dirty-marks only
  that thread.
- Relay unit test: listener leases release on close/off-window/TTL.
- Relay unit test: turn completion updates latest summary through targeted
  `thread/turns/list`.
- Relay unit test: row order updates after targeted activity proof.
- Relay unit test: stale `thread/read` cannot downgrade activity.
- Real-data simulator latest summary/activity scenario.

Exit criteria:

- Real simulator shows latest summary/activity/order update within 2s for a
  sacrificial real Codex thread with a recorded listener lease.
- Proof shows targeted `thread/turns/list` for the changed thread only.
- Existing large-list and root-catchup fixture scenarios still pass.

## Phase 5 - Archive, Unarchive, New Thread, And List/Index Backstop

Goal: cover visibility moves and initial completeness without letting list
polling become the normal update path again.

Implementation checklist:

- Add event handling for:
  - `thread/started`;
  - `thread/archived`;
  - `thread/unarchived`.
- Implement targeted active/archive card creation and moves.
- Reroute `thread/archive` and `thread/unarchive` command follow-up from
  `handleArchiveMutation()` broad Dock+Archive reconciliation to targeted
  active/archive projection moves.
- Ensure archive mutation grace still prevents stale active cards from
  reappearing.
- Keep app-server `thread/list` for boot/recovery.
- Isolate `session_index.jsonl` backstop:
  - named module/function;
  - explicit telemetry;
  - only invoked for list/index gap checks or boot recovery, not every targeted
    event update.
- Add COV-016 test coverage:
  - readable indexed row missing from `thread/list` is either fixed upstream or
    modeled as a backstop case.

Tests/checks:

- Relay unit tests for archive/unarchive moves.
- Relay unit test for new thread create through `thread/started`.
- Relay unit test for list/index backstop isolation.
- Real-data simulator archive/unarchive scenario.
- Live app-server list/index audit scenario.

Exit criteria:

- Real simulator sees archive/unarchive movement within 2s.
- Backstop path is explicit in proof when used.
- No normal event scenario relies on `session_index.jsonl` unless the proof
  records the COV-016 reason.

## Phase 6 - Discovery And Private Runtime Boundaries

Goal: make the remaining polling-driven parts honest, narrow, and cheap.

Implementation checklist:

- Keep app-server endpoint discovery timer until Codex exposes a registry.
- Keep private owner process/`lsof` discovery until Codex exposes private
  runtime heartbeat/registry.
- Reduce or demote live loaded status polling so it is not the normal badge
  latency path for attachable endpoints.
- Add diagnostics:
  - bridge endpoints connected;
  - private owners discovered;
  - attachable vs private counts;
  - last discovery refresh;
  - last event update;
  - last backstop update.
- Ensure private detail behavior:
  - history-backed read when possible;
  - clear private runtime limitation when full live attach is impossible.

Tests/checks:

- `rtk npm run test:host-service`
- registry/private owner unit tests;
- real-data private capability scenario if private owners exist.

Exit criteria:

- Discovery timers are documented as discovery/backstop only.
- Attachable status updates no longer wait for live loaded polling.
- Private runtime behavior is coherent and does not create fake live detail.

## Phase 7 - Delete Old Normal-Path Polling And Mixed Truth

Goal: remove dead/duplicated behavior after event paths and proof pass.

Implementation checklist:

- Delete or demote current "notification -> broad reconcile" normal path.
- Delete duplicate broad-refresh calls after mutation where targeted
  confirmation is now authoritative.
- Delete or demote `handleArchiveMutation()` as a normal archive/unarchive
  visibility path after targeted moves pass proof.
- Remove rollout metadata from normal app-server row assembly where app-server
  structured fields are sufficient.
- Keep disk fallbacks only behind named functions with explicit reason labels:
  - `app_server_list_index_gap`;
  - `private_runtime_discovery`;
  - `relationship_field_gap`;
  - `endpoint_bootstrap`.
- Remove stale docs that claim fixture-only proof is completion proof.
- Update `docs/TESTING.md` and coverage ledger.

Tests/checks:

- `rtk npm run test:relay`
- `rtk npm test`
- `rtk npm run contract:check`
- `rtk npm run test:host-service`
- relevant Swift tests if DTO/client behavior changed.
- controlled fixture matrix as regression support.
- real-data simulator proof as acceptance.

Exit criteria:

- All old normal-path broad polling hooks are gone or labeled recovery.
- No duplicate source of card truth remains.
- Real-data simulator proof passes for required scenarios.
- Controlled fixture tests still pass as deterministic regression support.

## Phase 8 - Optional Codex App-Server Upstream Fixes

Goal: retire remaining backstops when Codex can provide the missing data.

Only pursue if earlier phases prove these gaps are still material:

- Add/fix app-server list/index equivalence so every readable app-facing
  persisted thread is discoverable through app-server APIs.
- Add daemon registry for endpoints, auth/connect metadata, loaded thread ids,
  and private runtime ownership.
- Populate `threadSource` / `forkedFromId` or expose an equivalent structured
  relationship field reliably.

Exit criteria:

- Backstop removal tests pass.
- Live audit proves equivalence on the real corpus.
- Relay fallback code is deleted after replacement proof.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

The heading follows the arch-step artifact contract. For this plan, the
acceptance gates listed below are blocking before implementation can be called
complete.

## 8.1 Current Commands That Exist Today

Use the smallest relevant check first:

- Relay:
  - `rtk npm run test:relay`
  - `rtk npm test`
  - `rtk npm run contract:check`
  - `rtk npm run test:host-service`
- Swift:
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
- Simulator app build/launch:
  - `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`
- Current real relay-backed displayed-UI baseline:
  - `rtk make sim-ui-sync-proof SIM='iPhone 17'`
- Current controlled simulator regression support:
  - `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
- Diagnostic visibility only:
  - `rtk make sim-ui-dump SIM='iPhone 17'`
- Service health:
  - `rtk make services`
  - `rtk make app-server-status`
  - `rtk make dock-relay-status`

Do not cite `sim-ui-dump`, status endpoints, relay logs, raw WebSockets, fixture
rows, or `projection/witness/read` as completion proof.

## 8.2 Proposed New Acceptance Command

Add a Makefile target during implementation:

```bash
rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'
```

This target does not exist yet. It becomes current only after `Makefile`
contains it.

Required behavior:

- starts/reuses real services;
- uses relay host path on `:4510`;
- launches the real app in the iPhone 17 simulator;
- creates or selects sacrificial real Codex threads through actual app-server
  APIs;
- runs reversible event mutations;
- samples real app UI over time;
- writes structured JSON/Markdown proof;
- fails closed if route/data is fixture-only or diagnostic-only.

## 8.3 Required Acceptance Scenarios

Acceptance requires real-data simulator proof for:

- rename;
- status/working badge;
- latest activity/order;
- latest summary;
- archive/unarchive;
- open Thread Detail live update;
- reconnect/resync recovery;
- list/index audit for COV-016;
- private runtime capability if private owners exist, otherwise exact blocker.

The list/index case is not scored as a 2-second realtime event. It is a
real-data live audit plus UI/backstop visibility check when the gap affects
what the app can show.

Each scenario must prove:

- event mutation happened after initial UI observation;
- relay received event or used a named backstop;
- relay emitted projection seq;
- simulator observed the UI change;
- latency was within `MAX_UI_LAG_MS` for realtime scenarios;
- real data was restored where mutated.
- command-triggered client `refresh()` did not satisfy the proof by itself:
  the report must include the relay `dock/update`, `archive/update`, or
  `thread/detail/update` envelope that changed the UI.

## 8.4 Regression Support

Controlled fixtures remain valuable for deterministic edge cases:

- large list;
- rapid mutations;
- source refresh;
- live lease expiry;
- private child rollup;
- foreground resume;
- sequence gaps;
- server request cards.

But fixture pass is not completion. The real-data target is the acceptance gate
for this architecture.

## 8.5 Manual/Physical Boundary

This plan's proof gate is simulator-first because the user asked for simulator
real-data proof. Physical phone proof may still be run later with:

- `rtk make iphone-17-pro`
- `rtk make iphone-14`
- `rtk make device-install-all`

Do not block the architecture plan on physical Mobile MCP. If physical logs or
WebDriverAgent fail, record the exact blocker and rely only on simulator/local
proof where valid.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout Shape

Use a hard architectural cutover in the implementation branch, not a permanent
dual truth system.

Acceptable staged rollout during development:

- build proof harness;
- implement one vertical event path;
- expand event matrix;
- keep broad reconcile as boot/recovery;
- delete old normal-path broad polling hooks once event proof passes.

Not acceptable:

- leave old polling and new event bridge racing as equal sources of truth;
- silently fall back to broad polling for normal event scenarios;
- claim completion from fixture-only proof;
- make the phone talk to raw `:4500`;
- send bearer tokens or OpenAI secrets to the app.

## 9.2 Telemetry Required

Relay diagnostics should expose:

- bridge status:
  - connected endpoints;
  - last event received;
  - reconnect count;
  - stale/offline reason.
- event counters by method:
  - received;
  - classified direct;
  - classified targeted;
  - classified backstop;
  - dropped/unknown.
- dirty queue:
  - pending count;
  - max age;
  - debounce count;
  - targeted read latency.
- projection output:
  - event-to-delta latency;
  - delta-to-simulator latency in proof reports;
  - seq and projection ids.
- backstop use:
  - reason;
  - scope;
  - last run;
  - row count.
- disk/local fallback use:
  - `app_server_list_index_gap`;
  - `private_runtime_discovery`;
  - `relationship_field_gap`;
  - `endpoint_bootstrap`.

## 9.3 Operational Rules

- `rtk make services` remains the canonical service entrypoint.
- `rtk make dock-relay-status` and `rtk make app-server-status` remain status
  checks, not proof.
- Relay logs must use `scripts/dock-relay-logger.mjs`.
- Swift diagnostics must use `DockLog`.
- Never log secrets, tokens, prompt text, transcript text, raw audio, or full
  JSON-RPC payloads.
- `.env` remains user-owned and must not be overwritten.

## 9.4 Success Metrics

Architecture is successful when:

- required real-data scenarios pass within `MAX_UI_LAG_MS` for realtime events;
- broad periodic reconcile is not the normal path for rename/status/turn/card
  activity;
- targeted reads are proportional to changed threads;
- backstop reasons are explicit and rare;
- fixture matrix still passes as regression support;
- no existing Dock/Archive/Detail functionality regresses.

## 9.5 Future Cleanup After Codex Upstream Improvements

When Codex app-server provides a daemon registry, reliable list/index coverage,
and reliable relationship fields:

- delete process/token-file discovery from normal relay operation;
- delete `session_index.jsonl` supplement;
- delete rollout relationship fallback;
- lower or remove discovery timers;
- update coverage ledger and docs.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Explorer 1 checked architecture correctness against relay/client/Codex code
    paths, with emphasis on app-server-first design, event-driven feasibility,
    and discovery/private/list-index exceptions.
  - Explorer 2 checked verification completeness, current command accuracy,
    real simulator proof against real data, fixture-only rejection, and event
    coverage.
  - Self-integrator reread the plan after both reviews, accepted concrete
    issues, patched the doc, and ran the arch-stage status checks.
- Verdicts:
  - Explorer 1: pass-with-notes, no blocking contradiction.
  - Explorer 2: pass-with-notes, no blocking proof-completeness gap.
- Accepted findings:
  - The plan needed to name today's existing
    `rtk make sim-ui-sync-proof SIM='iPhone 17'` command as a real
    relay-backed displayed-UI baseline, while preserving the new stricter
    proposed real-data event-mutation proof target.
  - The Section 8 title contains the arch-step phrase `non-blocking`, so the
    body needed an explicit sentence saying this plan's acceptance gates are
    blocking for completion.
  - The app-server list/index scenario needed clarification: it is a real-data
    live audit plus UI/backstop visibility proof when applicable, not a 2s
    realtime event like rename/status/activity/archive.
  - Turn/item/server-request realtime needed an explicit relay-held listener
    lease strategy because Codex emits those events only to subscribed/attached
    thread connections.
  - The archive/unarchive command path needed to name the current
    `handleArchiveMutation()` broad-reconcile owner so implementation cannot
    miss it.
  - Real-data proof needed to reject client command `refresh()` as the thing
    being measured; proof must show the relay projection update envelope that
    changed the UI.
- Integrated repairs:
  - Added `ThreadListenerLeaseManager` to the target architecture, with bounded
    working-set attach/release rules and an explicit no-lease/no-2s-realtime
    rule for deep historical rows.
  - Added listener-lease requirements and tests to Phase 4.
  - Added `thread/archive`, `thread/unarchive`, and
    `RelayStateEngine.handleArchiveMutation()` to the exact call-site audit.
  - Added archive mutation reroute/delete obligations to Phases 5 and 7.
  - Added `sim-ui-sync-proof` as today's baseline and clarified that
    `sim-ui-realdata-realtime-proof` is proposed and becomes current only after
    `Makefile` contains it.
  - Added proof text requiring relay `dock/update`, `archive/update`, or
    `thread/detail/update` evidence, so post-command client refresh cannot mask
    relay latency.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

- 2026-06-05: Intent-derived decision. The user explicitly set the North Star:
  make as much as possible truly realtime, prove the client sees it in a real
  iPhone 17 simulator against real data, keep architecture unified and clean,
  delete old paths, preserve existing functionality, use arch-step auto-plan,
  gate with Fresh Consult Composer 2.5 Fast, and do not implement in this turn.
- 2026-06-05: Fresh Consult gate passed with Cursor Agent
  `composer-2.5-fast`, effort encoded in model. Verdict was
  `pass-with-notes`, blocking issues were `none`, confidence was `high`, and
  the consult summary approved the plan for implementation. Non-blocking notes
  are already represented in this plan: Phase 0 must add the proposed
  `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` target before
  completion claims; turn/summary realtime is working-set scoped unless a
  listener lease is held; COV-016 and private `stdio` runtime discovery remain
  named backstops; broad-to-targeted canonicalization parity and upstream
  pool/lease caps are the main implementation risks. Consult artifacts:
  `/tmp/fresh-consult/codex-dock-realtime-plan-20260606T004002Z-WvLLWH/turn-01/`.
