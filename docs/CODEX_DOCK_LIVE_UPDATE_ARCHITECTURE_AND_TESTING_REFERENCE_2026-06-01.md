---
title: "Codex Dock - Client Communication, Catch-Up, And Live Projection Architecture"
date: 2026-06-01
status: complete
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [Composer 2.5 Fast, arch-step]
doc_type: phased_refactor
related:
  - docs/CODEX_DOCK_USER_INTENTION_2026-06-01.md
  - docs/CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md
  - docs/CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md
  - docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md
  - docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md
  - docs/CODEX_DOCK_THREAD_019E8833_APP_VS_CODEX_LIVE_AUDIT_WORKLOG_2026-06-02.md
  - docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md
  - docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md
  - docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md
  - .arch_skill/model-consensus/codex-dock-client-robustness-20260602T201428Z/
---

# TL;DR

Codex Dock needs one live projection runtime. The relay owns visible truth; the
Swift client owns rendering and local input state; one Swift reconciler owns
subscribe, reconnect, refresh, catch-up, heartbeat, stale, and replay behavior.

The current code can get stuck because Dock, Archive, Thread Detail, transport
reconnect, command sends, lifecycle resume, connectivity, tests, and proof tools
each contain pieces of that runtime. This plan removes those side doors instead
of patching around them.

This file is the canonical plan for client communication, refresh, catch-up,
and live projection testing. Older dated docs remain history only when they
conflict with this file. Git is the archive; implementation must delete dead
runtime paths instead of preserving them beside the canonical path.

Non-negotiables:

- No phone production path to raw authenticated app-server `:4500`.
- No production display route that bypasses relay projection rows.
- No store-owned subscribe, resync, replay, heartbeat, or freshness state
  outside the canonical reconciler.
- No local reconstruction of visible identity, order, revision, or freshness.
- No test-only or preview-only legacy implementation kept alive.
- No "connected" or "live" UI claim unless the rendered view caught up through
  the same projection route the user is looking at.
- No screenshots or recordings as primary proof; proof must dump structured
  visible UI state and compare it to the relay projection state over time.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-06-03
Verdict (code): COMPLETE
Manual QA: n/a (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Completion evidence
- Shared contract and side-door gates:
  - `rtk npm run contract:check` passed on 2026-06-03: projection contract
    fixtures and generated Dock DTO were current; 5 proof schemas and 5
    canonical samples validated.
  - `rtk npm run test:relay` passed on 2026-06-03 with 172 tests.
  - `rtk swift test` passed on 2026-06-03 with 350 tests, 5 opt-in real-host
    tests skipped by environment.
  - Side-door sweep found no live `ThreadCardStreamLifecycle`,
    `ThreadCardTable`, `ThreadDetailLiveEventBuffer`,
    `ManualThreadCardStreamClient`, `LegacyThreadEventFixtureNormalizer`,
    `ThreadEventNormalizerTests`, or typed Swift `threadDetailRead` production
    path in `CodexDock/**`, `CodexDockTests/**`, or `CodexDockUITests/**`.
  - Remaining `thread/detail/read` references are rejection tests, proof
    contract rejection, sync-audit non-client-route accounting, or controlled
    fixture forbidden-route accounting. Remaining `projection/witness/read`
    references are proof-only route code/tests/scripts.
- Structured UI dump and no alternate Dock proof oracle:
  - [CodexDock/Features/Dock/DockView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockView.swift)
    exposes rendered Dock row payloads through `rowValues=` for structured UI
    dump/proof state.
  - [CodexDockUITests/DisplayedUICaptureSupport.swift](/Users/aelaguiz/workspace/codex-client/CodexDockUITests/DisplayedUICaptureSupport.swift)
    now treats the Dock root `rowValues` payload as the single Dock proof path.
    If that payload is missing, normal samples expose zero Dock rows and
    checkpoint sweep returns `rootRowsMissing`; strict proof fails instead of
    reconstructing row truth from accessibility-tree scrolling.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs scripts/proof-report-contracts.test.mjs`
    passed on 2026-06-03 with 54 tests.
- Real simulator proof:
  - `SIM_UI_CONTROLLED_MATRIX_PASSES=2 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 MAX_UI_LAG_MS=2000 rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
    passed on 2026-06-03.
  - Matrix report:
    `/tmp/codex-client/sim-ui-controlled-matrix-run-20260603T140848Z/controlled-simulator-matrix.md`.
  - Matrix result: `OK: true`, 34 reports, 17 required scenarios, 17 passing
    scenarios, 0 missing, 0 failed, max observed UI lag 469 ms against a
    2000 ms budget, findings: none.
  - `large-list-checkpoint` passed 2/2 with checkpoint Dock order coverage,
    proving the large-list row dump/order gate that previously failed.
- Simulator smoke and current-screen dump:
  - `rtk make app-test SIM='iPhone 17'` exited 0 on 2026-06-03.
  - The first `rtk make sim-ui-dump SIM='iPhone 17'` correctly failed closed
    because `com.aelaguiz.CodexDockApp` was not running and dump mode must not
    launch the app.
  - After `rtk make app SIM='iPhone 17'` exited 0, `rtk make sim-ui-dump
    SIM='iPhone 17'` passed on 2026-06-03.
  - Passing dump report:
    `/tmp/codex-client/sim-ui-dump-20260603T143234Z/sim-ui-dump.md`.
  - Dump result: `status: pass`, app `runningForeground -> runningForeground`,
    screen `dock -> dock`, 54 visible elements, 253 Dock rows.
  - `rtk git diff --check` passed on 2026-06-03 after the final UI dump proof
    changes.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- Physical-phone validation is required before claiming actual physical iPhone
  behavior. This audit claims code completeness and simulator proof on
  `iPhone 17`; it does not claim a physical-device pass.
<!-- arch_skill:block:implementation_audit:end -->

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-06-02
external_research_grounding: not run - repo-local architecture and protocol refactor
deep_dive_pass_2: done 2026-06-02
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This doc was rebuilt on 2026-06-02 because stale auto-plan receipts and historical implementation evidence no longer represented the requested no-side-door architecture.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:665d055ac5f5d929acdca214160bd3b53757610486ca0092830bd0753d4e081c",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-02T22:00:12Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:a69d1974ef5a8099bf279b1cd786c8b565ecf035e97e0981bd1e27acff05febb",
      "completed_at": "2026-06-02T22:00:45Z",
      "doc_hash_after": "sha256:c030d0abe7e326c69f26283784cddac3dee9167f456bdfd5367754a2ebc8c655"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-02T22:00:49Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:c030d0abe7e326c69f26283784cddac3dee9167f456bdfd5367754a2ebc8c655",
      "completed_at": "2026-06-02T22:02:16Z",
      "doc_hash_after": "sha256:e2bf83c18942344e655bd895ca9c21d1438190d7cc01c7e1f6b8f538e5ce69d2"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-02T22:09:33Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e2bf83c18942344e655bd895ca9c21d1438190d7cc01c7e1f6b8f538e5ce69d2",
      "completed_at": "2026-06-02T22:11:36Z",
      "doc_hash_after": "sha256:f6ad49f2ad7c10f3f84112dae89a0c71b69f809fb1f6acf2a2dfe9b587c85782"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-02T22:11:46Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:f6ad49f2ad7c10f3f84112dae89a0c71b69f809fb1f6acf2a2dfe9b587c85782",
      "completed_at": "2026-06-02T22:12:49Z",
      "doc_hash_after": "sha256:58f51d524e13f42f21c03ddf8a36cb042aaf0ef8ebcd37b15926928beb39f0c0"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-02T22:12:56Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:58f51d524e13f42f21c03ddf8a36cb042aaf0ef8ebcd37b15926928beb39f0c0",
      "completed_at": "2026-06-02T22:20:22Z",
      "doc_hash_after": "sha256:df1ba21be14f902151953f6da557a288151983c872786f4555408f5cd5ec6977"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The Claim

When a user opens Dock, Archive, or Thread Detail on the iPhone simulator or a
phone, the visible rows are the relay's current projection for that exact view.
If the app cannot prove that projection is current, the view says it is catching
up, stale, offline, or failed. It never silently shows old state as live.

The falsifiable version:

- A relay projection change for a subscribed view reaches Swift through one
  typed stream route.
- Swift applies it through one projection reducer.
- Swift renders it through one render projector.
- A structured UI dump can prove the rendered state matches the relay view.
- If any step breaks, the view fails closed instead of looking live.

## 0.2 Intended User Experience

The user intent is simple:

- Newest real work appears at the top.
- Thread Detail shows the same current conversation Codex is producing now.
- Sending a message does not create a duplicate row.
- Opening a screen does not require the user to know whether the app is loading,
  resuming, reconnecting, catching up, or replaying buffered updates.
- If the app is not current, it says so clearly.

## 0.3 In Scope

- Swift communication from `AppServerClient` through Dock, Archive, Thread
  Detail, connectivity, lifecycle, command sends, and render projection.
- Relay routes, subscriptions, projection witnesses, state store, catch-up
  windows, heartbeats, and contract generation that Swift consumes.
- Simulator and phone proof methodology for real updates over time.
- Tests, fakes, previews, and diagnostics that could preserve a second path.
- Documentation and comments needed to stop future reintroduction of side
  doors.

## 0.4 Out Of Scope

- Changing what Codex means by statuses such as `idle`.
- Building a long-term migration system for cached old state.
- Adding new product affordances beyond correct live projection behavior.
- Reworking voice capture or transcription except where their tasks cross
  Thread Detail lifecycle and command state.

## 0.5 Definition Of Done

Implementation is done only when all of these are true:

- Dock, Archive, and Thread Detail use the same projection runtime shape.
- One Swift `StreamReconciler` or equivalent owns view subscription lifecycle,
  reconnect, refresh, catch-up, replay buffering, heartbeat, sequence gaps,
  stale state, and close semantics.
- One shared projection reducer owns envelope validation, identity, ordering,
  revision, duplicate detection, sequence continuity, snapshot, page, upsert,
  delete, heartbeat, and `resyncRequired` handling.
- Stores are adapters: they request a view, render reducer output, and own only
  screen-local input state.
- Relay catch-up has an explicit contract that Swift tests consume exactly.
- Command success triggers projection invalidation or wait-for-projection; it
  never creates production visible rows.
- Tests and proof tools use the same production projection routes, reducer, and
  identity rules as the app.
- Structured UI dumps prove simulator-visible state against the relay
  projection over time.
- Legacy side doors are deleted, not merely unused.

# 1) Key Design Considerations

## 1.1 Priorities

1. Correctness over local smoothness. Stale live UI is worse than an explicit
   catching-up state.
2. One owner per concern. Transport health, projection freshness, render state,
   and local composer/request-card state must not collapse into each other.
3. Clean cutover over compatibility shims. The plan intentionally breaks and
   replaces old paths where preserving them would keep drift possible.
4. Proof over optimism. A passing unit test is not enough if the simulator can
   still show stale or duplicated rows.
5. Deletion over preservation. Test fixtures must move to the new runtime
   instead of keeping the old runtime alive.

## 1.2 Constraints

- The relay is the Mac-side owner of raw Codex credentials and raw Codex access.
- Phone and simulator app behavior normally goes through relay `:4510`.
- SwiftUI rendering still needs local screen stores and local draft/request-card
  form state.
- Some platform bridges remain unavoidable, such as URLSession WebSocket,
  AVFoundation voice capture, and Apple lifecycle notifications.
- Strict concurrency is a gate for projection runtime code. Any
  `@unchecked Sendable`, lock-backed mutable bridge, or platform callback escape
  must live in a named bridge/quarantine file such as URLSession WebSocket,
  AVFoundation voice capture, MetricKit, or lifecycle notification glue, and it
  must not own projection freshness or row truth.
- Physical-device proof can be blocked by device state; simulator proof must
  still be strong enough to catch architecture bugs before phone testing.

## 1.3 Architecture Rules

- Transport reconnect is not data catch-up.
- Route health is not projection freshness.
- Command acknowledgement is not visible UI truth.
- A heartbeat proves only that the stream route is alive for the current
  projection generation; it does not advance user data.
- A snapshot replaces a view; a page extends a bounded catch-up window; a delta
  mutates a live projection; these are distinct contracts.
- Render projectors may filter or format rows, but they must not invent
  identity, order, freshness, or recovery behavior.
- Debug and proof routes cannot be imported by production app code.

# 2) Problem Statement

The app is a live monitor. The bug class came from an older client architecture
that behaved like a collection of mostly-independent live monitors:

- `AppServerClient` reconnects the socket and emits connection states.
- Dock and Archive used `ThreadCardStreamLifecycle` and `ThreadCardTable`.
- Thread Detail used `ThreadDetailStore`, `ThreadDetailDataEngine`, and
  `ThreadDetailLiveEventBuffer`.
- Dock row changes can trigger Thread Detail rehydrate attempts.
- Foreground resume can trigger a separate Thread Detail recovery path.
- Relay `resyncRequired`, client sequence gaps, heartbeat timeouts, command
  sends, and route diagnostics each touch freshness through different code.
- Tests included useful static fixtures that did not prove the full real-life
  chain from relay projection change to visible simulator state over time.

That split explains the bugs the user was seeing and the regressions this plan
must keep preventing:

- The relay can have current Codex data while the current Thread Detail view
  stays stale.
- The socket can be connected while screen catch-up is blocked.
- A command can succeed while the visible row does not arrive, arrives twice, or
  arrives under a different identity.
- Dock or Archive catch-up can disagree with Swift sequence handling.
- Tests can pass when they validate isolated snapshots instead of the whole live
  runtime.

# 3) Research Grounding

<!-- arch_skill:block:research_grounding:start -->
## 3.1 Internal Ground Truth

This is a repo-local protocol and runtime refactor. The runnable source of truth
is the code, tests, `Makefile`, `project.yml`, `Package.swift`, `package.json`,
and README. Existing dated docs are inputs only.

Swift runtime sources:

- `CodexDock/AppServer/AppServerClient.swift`: JSON-RPC request/response,
  transport reconnect, notification streams, connection state, and typed route
  helpers such as `threadDetailSubscribe` and `threadDetailResync`.
- `CodexDock/AppServer/AppServerMethods.swift`: route name registry.
- `CodexDock/AppServer/AppServerThreadCardStreamClient.swift`: thin Dock and
  Archive projection transport adapter used by the reconciler.
- `CodexDock/Projection/ProjectionReducer.swift`: shared projection envelope law,
  row identity, ordering, revision, duplicate detection, sequence continuity,
  catch-up page, live mutation, heartbeat, and `resyncRequired` handling.
- `CodexDock/Projection/StreamReconciler.swift`: shared subscription lifecycle
  owner for subscribe, resync, reconnect intent, foreground resume, heartbeat
  timeout, bounded buffering, catch-up replay, stale/offline/failed state, and
  close semantics.
- `CodexDock/State/DockStore.swift` and `CodexDock/State/ArchiveStore.swift`:
  store adapters around reconciler output plus local filter, lens, archive, and
  metadata decoration state.
- `CodexDock/State/ThreadDetailStore.swift`: store adapter around reconciler
  output plus local composer, voice, request-card, and command state.
- `CodexDock/State/AppConnectivityStore.swift` and
  `CodexDock/State/SystemHealthProjector.swift`: route health and user-facing
  health presentation, separate from view-specific projection freshness.
- `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift` and
  `CodexDock/ThreadDetail/ThreadEventDisplayOrder.swift`: render projection and
  visible ordering.

Relay and protocol sources:

- `scripts/dock-relay.mjs`: JSON-RPC route dispatch, detail routes, mutation
  routes, proof/debug routes, and app-server bridging.
- `scripts/dock-relay-state-engine.mjs`: relay state reconciliation, live lease
  expiry, Dock/Archive snapshots, catch-up window creation, and publish triggers.
- `scripts/dock-relay-state-subscriptions.mjs`: root stream subscribe, resync,
  update method names, delta kind selection, heartbeat publication, and
  soft-limit snapshot replacement.
- `scripts/dock-relay-state-store.mjs`: persisted relay state and sequence
  counters.
- `scripts/dock-relay-state-views.mjs`: visible Dock/Archive row ordering and
  window construction.
- `scripts/dock-relay-thread-detail-ledger.mjs`,
  `scripts/dock-relay-thread-detail-projection.mjs`, and
  `scripts/dock-relay-thread-detail-projection-adapter.mjs`: detail projection
  ledger, row identity, order, and update generation.
- `contract/**` and generation/check scripts: schema, DTO, and proof contract
  surfaces that can either prevent or allow drift.

Testing and proof sources:

- `CodexDockTests/**`: Swift store, reducer, DTO, connectivity, and route tests.
- `CodexDockUITests/**`: simulator-visible UI and accessibility proof helpers.
- `Makefile`: canonical app, simulator, service, device, proof, and dump
  commands.
- `scripts/proof*.mjs` and `contract/proof/**`: structured proof report and UI
  dump contracts.
- `README.md`: canonical runbook after implementation.

## 3.2 Architecture Anchors

External web research is not needed for the core decision; this is a local
distributed-state bug with known constraints. The plan uses these engineering
anchors:

- One state machine owns a live subscription. Multiple partial state machines
  are the root failure mode.
- Transport availability and data freshness are different facts.
- A visible row must have one stable identity from relay projection to UI dump.
- Recovery is a finite protocol, not an unbounded retry side effect.
- Test doubles must implement the same contract as production or they preserve
  drift.

## 3.3 Decisions Already Made

- Relay projection is the only visible row truth.
- Swift has exactly one projection runtime shape for Dock, Archive, and Thread
  Detail.
- Stores do not own subscribe/resync/replay/heartbeat state.
- `thread/detail/read` is not a production display path after cutover.
- `projection/witness/read` is proof-only and cannot be imported by app UI.
- Catch-up pages are distinct from same-sequence live upserts.
- Old runtime paths are deleted, including test paths that keep them alive.

## 3.4 Decision Gaps

None. The implementation still needs design details, but no product or
architecture decision remains open before planning the phases.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture

<!-- arch_skill:block:current_architecture:start -->
## 4.1 Current Runtime Shape

The current client has one projection runtime shape, with transport and render
code kept as adapters around it:

| Area | Current owner | What it owns today | Drift boundary |
| --- | --- | --- | --- |
| JSON-RPC transport | `AppServerClient` | WebSocket open/close, reconnect, initialize, pending requests, notifications | It proves socket state only. View freshness remains reconciler-owned. |
| Projection apply law | `ProjectionReducer<Row>` | Envelope validation, identity, ordering, revision, duplicates, sequence continuity, snapshot, page, upsert, delete, heartbeat, and `resyncRequired` | No store or renderer may rebuild these rules. |
| Projection lifecycle | `StreamReconciler<Row>` | Subscribe, resync, reconnect intent, foreground resume, heartbeat timeout, bounded buffering, catch-up replay, stale/offline/failed state, and close | Transport reconnect and route health cannot mark a view live. |
| Dock and Archive | `DockStore` and `ArchiveStore` | Host/view-key setup, rendering from reconciler snapshots, local filters, archive actions, metadata decoration | Relay projection owns row existence, order, identity, and freshness. |
| Thread Detail | `ThreadDetailStore` | Rendering from reconciler snapshots plus composer, voice, request-card, and command-local state | Visible rows arrive only through relay projection. |
| Connectivity | `AppConnectivityStore`, `SystemHealthProjector` | Route health, configured host health, and user-facing status copy | Health is evidence, not row truth. |
| Render projection | `DockCardProjection`, `ThreadEventDisplayOrder`, screen stores | Filtering, formatting, row mapping, and UI state | Render code may format and filter; it may not invent identity, order, or freshness. |
| Proof and tests | XCTest, UI tests, proof scripts | Reducer/reconciler tests, relay contract tests, structured UI dumps, and controlled simulator proof | Acceptance proof must use relay-owned projection routes and visible accessibility state over time. |

Additional current contributors:

- Bootstrap and host registry state can change the host list from environment,
  saved config, Bonjour discovery, or manual settings, which can rebuild the
  root UI and reset stream state.
- Host identity appears as configured host ID, relay `sourceHostID`, DTO
  `logicalHostID`, local metadata aliases, and action host IDs.
- Local metadata can pin, group, or decorate relay rows. It must stay
  decoration only.
- `RenderCoalescer` drops intermediate render revisions by design. That is
  fine for UI, but it is not event-history proof.
- Voice/transcription opens a separate retained relay session. It affects draft
  text and send readiness, not projection truth.

## 4.2 Current Client Communication Flow

Dock and Archive:

1. Store builds one `StreamReconciler<DockThreadCardDTO>` per configured host
   and view.
2. The reconciler connects through `AppServerThreadCardStreamClient`.
3. The connection subscribes to `dock/subscribe` or `archive/subscribe`.
4. `ProjectionReducer<DockThreadCardDTO>` applies the initial snapshot.
5. The reconciler consumes `dock/update` or `archive/update` notifications.
6. Heartbeat timeout, sequence gap, foreground resume, stream close, buffer
   overflow, or relay `resyncRequired` takes the reconciler resync path.
7. Store publishes a rendered snapshot from reconciler rows and local UI state.

Thread Detail:

1. `SessionDetailView` creates `ThreadDetailStore`.
2. `ThreadDetailStore.load()` creates a projection session and starts one
   `StreamReconciler<ThreadDetailEventDTO>` for the thread view key.
3. The connection subscribes to `thread/detail/subscribe`.
4. `ProjectionReducer<ThreadDetailEventDTO>` applies the initial snapshot.
5. Later `thread/detail/update` notifications flow through the same reconciler
   and reducer.
6. Foreground resume, transport reconnect intent, sequence gap, heartbeat
   timeout, command-completed invalidation, and relay `resyncRequired` all call
   reconciler resync.

Transport:

1. `AppServerClient` opens the WebSocket and initializes.
2. If the transport fails and a reconnect policy exists, it reconnects the
   socket and initializes again.
3. It emits connection states and notifications.
4. It does not decide whether any subscribed screen caught up after reconnect.

## 4.3 Current Relay Communication Flow

Dock and Archive:

1. `RelayStateEngine` reconciles raw Codex/session state into the state store.
2. `StateSubscriptionHub.snapshot()` returns a projected window.
3. `StateSubscriptionHub.cardDelta()` chooses `upsert`, `delete`, or
   `heartbeat`.
4. `publishDelta()` sends the delta or a replacement snapshot if the payload is
   too large.
5. Heartbeats are produced while subscribers exist.

Thread Detail:

1. `thread/detail/subscribe` builds or resumes relay detail projection state.
2. `thread/detail/update` notifications carry live projection updates.
3. `thread/detail/resync` rebuilds the canonical detail state.

Relay source boundaries still worth keeping explicit:

- Dock/Archive projection truth is SQLite-backed through `RelayStateStore` and
  `StateSubscriptionHub`; Thread Detail projection truth is held by
  `ThreadDetailLedger`. Both emit the shared projection envelope law.
- `projection/witness/read` is proof-only and disabled unless explicitly
  enabled for proof.
- Relay window catch-up uses explicit `page` updates instead of same-sequence
  live `upsert` payloads.
- `session_index.jsonl`, live leases, live status cache, raw `thread/list`, raw
  `thread/read`, raw `thread/turns/list`, and live loaded sessions are relay
  input sources only before the projection collapse point. None may become
  Swift-visible truth.
- Unsupported debug, state, raw app-server, or loopback-only routes must stay
  unavailable to production app display and acceptance proof.

## 4.4 Route Classification

Production display routes today:

- `dock/subscribe`
- `dock/update`
- `dock/resync`
- `archive/subscribe`
- `archive/update`
- `archive/resync`
- `thread/detail/subscribe`
- `thread/detail/update`
- `thread/detail/resync`

Production command and adjacent routes:

- `thread/archive`
- `thread/unarchive`
- `turn/start`
- `turn/steer`
- `turn/interrupt`
- `audio/transcription/start`
- `audio/transcription/append`
- `audio/transcription/commit`
- `audio/transcription/cancel`

Diagnostic HTTP routes:

- `/readyz`
- `/healthz`
- `/statusz`
- `/metricsz`
- `/routesz`
- `/syncz`

Proof-only route:

- `projection/witness/read`

Unsupported or legacy app-facing routes must remain unavailable to production
display code:

- `thread/list`
- `thread/search`
- `thread/goal/get`
- `thread/loaded/list`
- `relay/state/snapshot`
- `state/query`
- `/statez`
- `/dbz`
- `/debugz/sessions`
- `/subscriptionsz`
- `/tracesz/*`
- `/selftestz`
- `/bundlez`

## 4.5 Current Test And Proof Pattern

The current repo now has behavior-level proof for the shared runtime and the
`iPhone 17` simulator acceptance path:

- Swift unit tests prove the shared reducer, shared reconciler, Thread Detail
  command invalidation, Dock/Archive stream behavior, and lifecycle recovery
  through projection envelopes.
- Relay tests prove route side doors are unsupported, projection witness fails
  closed unless enabled, root/detail streams share the projection envelope law,
  raw routes stay upstream-only, and proof reports reject side-door evidence.
- `rtk make app-test SIM='iPhone 17'` proves the app can run UI tests with relay
  host env; it is a smoke gate, not enough by itself for live-update acceptance.
- `rtk make sim-ui-dump SIM='iPhone 17'` dumps the current accessibility state
  without screenshots, navigation, or relaunch. It is diagnostic evidence, not
  over-time acceptance by itself.
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` is the canonical
  over-time simulator gate. Makefile defaults now require two passes, checkpoint
  sweep, the full required controlled-scenario set, and `MAX_UI_LAG_MS=2000`.
- Proof schemas use strict top-level report fields plus allow-listed nested
  proof keys and route keys. Passing live-update proof must include relay-owned
  client route evidence and cannot count `projection/witness/read` as a
  simulator-app route.
- Live-filter truth reads `projection/witness/read`, requires
  byte-equivalent retained downstream envelopes, and rejects raw
  `thread/detail/read` as acceptance truth.

The implementation audit block is the canonical evidence ledger for the latest
executed commands and artifact paths. This section describes the current proof
architecture; it is not a second moving gate checklist.

## 4.6 Current Failure Pattern

The confirmed class of failure was not just "old cache." It was:

- relay has current data;
- transport may be connected;
- one screen-specific client state machine can wait, go stale, block, or fall
  out of sequence;
- another layer still reports acceptable connection health;
- tests do not force the whole path to prove visible catch-up.

The current code addresses this class by routing each production screen through
`StreamReconciler` and `ProjectionReducer`, with unsupported legacy reads
failing loud and simulator proof required to observe visible convergence over
time instead of accepting static snapshots.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture

<!-- arch_skill:block:target_architecture:start -->
## 5.1 Canonical Pipeline

The target pipeline is:

```text
raw Codex/session adapters
  -> relay projection engine
  -> relay projection store and witness
  -> typed projection stream envelopes
  -> Swift StreamReconciler
  -> shared Swift ProjectionReducer
  -> render projectors
  -> SwiftUI
  -> structured visible UI dump
```

Every production display row must pass through that pipeline.

## 5.2 Canonical Swift Owners

`AppServerClient` owns only JSON-RPC transport mechanics:

- connect;
- initialize;
- send typed request;
- receive notifications;
- report transport state.

It does not own projection freshness or per-screen catch-up.

`StreamReconciler` owns one projection view key:

```text
sourceHostID + view + scope + viewParamsKey
```

It owns:

- initial subscribe;
- manual refresh;
- foreground resume;
- transport reconnect intent;
- heartbeat timeout;
- relay `resyncRequired`;
- client-detected sequence gap;
- buffer overflow;
- command-completed invalidation;
- finite catch-up;
- close/cancel.

`ProjectionReducer<Row>` owns:

- schema version;
- identity version;
- projection engine version;
- source host;
- view;
- scope;
- view params key;
- order contract;
- epoch;
- sequence;
- generation;
- snapshot;
- page;
- upsert;
- delete;
- heartbeat;
- `resyncRequired`;
- duplicate `projectionID`;
- duplicate source identity;
- immutable identity;
- stale revision;
- row order.

Stores own only:

- view selection;
- filter/lens choices;
- local draft text;
- local voice/dictation state;
- local request-card input text;
- local command status overlay;
- render binding to reconciler output.

## 5.3 Canonical Relay Owners

The relay owns visible projection truth:

- row identity;
- source identity;
- row revision;
- newest-first order via `displayOrderKey`;
- status and relationship as display data;
- projection freshness;
- stream epoch and sequence;
- catch-up page contract;
- heartbeat and `resyncRequired`;
- projection witnesses used by proof tools.

Projection-relevant relay routes after cutover:

- Production display routes:
  - `dock/subscribe`
  - `dock/update`
  - `dock/resync`
  - `archive/subscribe`
  - `archive/update`
  - `archive/resync`
  - `thread/detail/subscribe`
  - `thread/detail/update`
  - `thread/detail/resync`
- Production command routes:
  - `turn/start`
  - `turn/steer`
  - `turn/interrupt`
  - `thread/archive`
  - `thread/unarchive`
  - server request response route through JSON-RPC response handling
- Proof-only route:
  - `projection/witness/read`

Kept adjacent non-projection routes:

- `audio/transcription/start`
- `audio/transcription/append`
- `audio/transcription/commit`
- `audio/transcription/cancel`
- `audio/transcription/delta`
- `audio/transcription/completed`
- `audio/transcription/failed`
- `audio/transcription/canceled`
- `audio/transcription/closed`

These routes may affect draft text, voice state, command readiness, or upstream
Codex mutations. They do not emit production display rows and cannot define
projection freshness.

Forbidden after cutover:

- app UI calling `thread/detail/read` for production display;
- app UI calling `projection/witness/read`;
- app UI or tests reconstructing expected visible rows from raw app-server
  history;
- proof scripts using a route that production app display cannot use, except
  proof-only witness comparison.

The relay witness must read from the same emitter used for Dock, Archive, and
Thread Detail. It must capture the exact downstream envelopes, including
`snapshot`, `page`, `upsert`, `delete`, `heartbeat`, and `resyncRequired`
events. A detail-only witness is not enough.

## 5.4 Catch-Up Contract

The plan chooses this catch-up law:

- `snapshot` is a complete replacement for the subscribed visible window at a
  specific epoch and sequence.
- `page` is a distinct catch-up window-extension update. It carries the base
  epoch, base sequence, generation, offset, limit, row count, total row count,
  and rows. It is accepted only while `StreamReconciler` is in catch-up for that
  generation.
- `upsert` and `delete` are live mutations and must advance stream sequence.
- `heartbeat` keeps the current sequence and updates route/freshness evidence.
- `resyncRequired` never mutates rows; it moves the reconciler into recovery.
- Same-sequence `upsert` catch-up pages are forbidden.

This explicitly fixes the relay/Swift mismatch where catch-up window rows can
look like live deltas while Swift expects `seq == currentSeq + 1`.

## 5.5 Freshness Contract

View freshness is derived from the reconciler for the exact view key. It is
`live` only when:

- transport is connected;
- the view is subscribed;
- the reducer has accepted the current generation;
- no catch-up, resync, replay, or buffer overflow recovery is pending;
- heartbeat is within budget;
- the render projector has consumed the accepted reducer state.

Route health can be `connected` while view freshness is `catchingUp` or
`stale`. System health must show that distinction.

## 5.6 Command Contract

Sending a draft or answering a request card is a command, not visible truth.

- Command success may clear the local draft or mark a local request-card overlay
  as sent.
- Command success must enqueue a projection invalidation or wait-for-projection
  intent.
- The visible outbound message row appears only when relay projection emits it.
- If the projection does not arrive inside budget, the UI reports that the view
  is catching up or stale; it does not create an optimistic production row.

## 5.7 Proof Contract

The canonical proof path is structured data:

1. Drive the app through the production route on `iPhone 17`.
2. Drive relay-side projection changes or replay recorded real scenarios.
3. Dump the visible simulator UI state through accessibility/debug hooks.
4. Fetch the relay projection witness for the same source host, view, scope, and
   view params key.
5. Compare identity, order, revision, freshness, and visible labels over time.

Screenshots remain diagnostic only.

Final proof defaults must fail closed:

- no skip when the strict UI sync config is absent in a gate target;
- at least two controlled matrix passes for live-update acceptance;
- checkpoint sweep enabled;
- `MAX_UI_LAG_MS=2000` or stricter unless this doc is amended;
- no raw `thread/detail/read` oracle for production display comparison;
- no broad schema properties for identity, order, freshness, or route truth;
- no locally minted expected projection IDs.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Required Change Inventory

| Path | Current role | Required target state |
| --- | --- | --- |
| `CodexDock/AppServer/AppServerClient.swift` | Transport, reconnect, typed requests, subscribe, and resync helpers | Keep transport and typed requests. Reconnect emits intents; it does not imply view freshness. |
| `CodexDock/AppServer/AppServerMethods.swift` | Central app-facing route strings | Keep only canonical production display and command routes. Do not import raw app-server or proof-only side-door routes into app code. |
| `CodexDock/AppServer/AppServerHostConnector.swift` | One-shot and retained raw client construction | Keep as transport factory only. It cannot be a bypass around projection runtime for display truth. |
| `CodexDock/Diagnostics/ObservabilityContract.swift` | Swift route diagnostics for canonical app-facing routes | Keep `thread/detail/subscribe`, `thread/detail/update`, and `thread/detail/resync` app-critical. Do not re-add `thread/detail/read`. |
| `CodexDock/AppServer/AppServerThreadCardStreamClient.swift` | Thin Dock/Archive projection transport adapter | Keep only as a connection adapter used by `StreamReconciler`; it cannot own stream lifecycle or row truth. |
| `CodexDock/State/ThreadCardStreamLifecycle.swift` | Deleted root-stream lifecycle state machine | Remain deleted. No test fixture keeps it alive. |
| `CodexDock/State/ThreadCardTable.swift` | Deleted Dock/Archive projection table | Remain deleted. `ProjectionReducer<Row>` owns projection apply law. |
| `CodexDock/State/DockStore.swift` | Root screen store and stream delegate | Become a store adapter around reconciler output and local filter/lens state. |
| `CodexDock/State/ArchiveStore.swift` | Archive screen store and stream delegate | Same as Dock. |
| `CodexDock/State/DockDataEngine.swift` and archive equivalents | Current row/projector support | Keep only render/local metadata logic that does not decide projection truth, or fold into render projectors. |
| `CodexDock/State/ThreadDetailStore.swift` | Detail store adapter, command owner, and local input owner | Keep composer, voice, request-card inputs, command calls, and render binding. Do not reintroduce subscribe/resync/replay/heartbeat/freshness ownership. |
| `CodexDock/State/ThreadDetailLiveEventBuffer.swift` | Deleted detail-only replay buffer | Remain deleted. Reconciler owns bounded buffering and catch-up. |
| `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` | Deleted detail-only projection reducer | Remain deleted. Shared `ProjectionReducer<Row>` owns projection apply law. |
| `CodexDock/ThreadDetail/ThreadEventDisplayOrder.swift` | Relay-order rendering | Keep as render-only; do not use it to recover missing order. |
| `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift` | Render coalescing and screen model | Keep render-only behavior; no communication or freshness authority. |
| `CodexDock/State/ClientCommandEngine.swift` | Command routes | Keep command execution. Add canonical projection invalidation/wait integration through reconciler. |
| `CodexDock/State/ThreadDetailRequestCardPresentation.swift` | Local request-card form overlays | Keep only local input/status overlay keyed by projection identity. |
| `CodexDock/State/AppConnectivityStore.swift` | Aggregates route/screen health | Consume reconciler freshness. Do not infer projection freshness from transport alone. |
| `CodexDock/State/SystemHealthProjector.swift` | User-facing health summary | Show route health separately from view freshness/catch-up. |
| `CodexDock/State/AppLifecycleCoordinator.swift` | Foreground/background gate | Emit lifecycle intents to reconciler. Stores do not run independent rehydrate logic. |
| `CodexDock/Configuration/RelayBootstrapStore.swift`, `HostRegistry.swift`, `RelayDiscovery.swift`, `DockHostConfiguration.swift` | Host selection, saved endpoints, Bonjour discovery, raw-port rejection | Keep host configuration. Collapse runtime identity to configured relay endpoint plus relay `sourceHostID`; no UI action path chooses among alternate host IDs. |
| `CodexDock/Metadata/LocalMetadataEngine.swift`, `PinnedMetadataOrdering.swift` | Local pin/group/alias decoration | Keep decoration only. Alias migration can read old metadata, but cannot define production row identity/order/freshness. |
| `CodexDock/Rendering/RenderCoalescer.swift` | Drops intermediate render revisions and publishes newest render | Keep render coalescing only. It is never an event log or freshness proof. |
| `CodexDock/Voice/**` | Separate transcription transport and composer draft mutation | Keep as command-adjacent draft input. It cannot influence projection freshness or visible row truth. |
| `CodexDock/Automation/AutomationID.swift` | UI proof identifiers | Keep stable IDs for structured UI dumps and proof. Remove IDs only tied to deleted side doors. |
| `CodexDockUITests/DisplayedUICaptureSupport.swift` | Current visible UI extraction | Make this the canonical structured dump producer for Dock and Thread Detail, not screenshot proof. |
| `scripts/dock-relay.mjs` | Route dispatch and bridge | Remove production display reliance on raw/detail read side doors. Keep witness proof route proof-only. |
| `scripts/dock-relay-observability-contract.mjs`, `scripts/dock-relay-status.mjs` | Relay route diagnostics and route status | Keep only canonical app-facing projection routes as app-critical display evidence. Do not re-add `thread/detail/read`. |
| `scripts/dock-relay-state-engine.mjs` | Relay root projection, reconciliation, catch-up | Emit explicit `page` catch-up contract. No same-sequence catch-up upsert. |
| `scripts/dock-relay-state-subscriptions.mjs` | Subscription hub and heartbeats | Support canonical update kinds and exact route/view identity. |
| `scripts/dock-relay-state-store.mjs` | State persistence and sequence | Own projection sequence/generation for each view. Cache invalidation must be deterministic for contract bumps. |
| `scripts/dock-relay-thread-detail-*` | Detail projection and ledger | Use the same envelope/update law as root streams. |
| `scripts/dock-relay-thread-data.mjs`, `dock-relay-live-status-cache.mjs`, `dock-relay-thread-summary-cache.mjs` | Raw source collapse, live leases, summary helpers | Treat as relay input or delete if unused. None can emit Swift-visible truth outside projection. |
| `contract/**` | Schema and DTO truth | Generate one projection envelope/update contract consumed by relay, Swift DTOs, tests, and proof. |
| `scripts/proof*.mjs` and `contract/proof/**` | Proof reports and UI dump contracts | Compare simulator-visible state to relay witness for the same view key. Strictly allow-list proof fields and route evidence. |
| `scripts/codex-dock-live-filter-truth.mjs`, `codex-dock-live-filter-compare.mjs`, and related tests | Live-filter proof oracle reads projection witness | Keep projection witness as the truth source and reject raw `thread/detail/read` as acceptance proof. |
| `CodexDockTests/**` | Unit/integration coverage | Migrate to shared reducer and reconciler fixtures. Delete tests that instantiate old lifecycle/table paths as behavior owners. |
| `CodexDockUITests/**` | Simulator proof | Exercise live change, reconnect, catch-up, stale, and duplicate scenarios through production app routes. |
| `README.md` | Canonical runbook | Update after implementation with one runtime, one proof path, and no stale side-door instructions. |

## 6.2 Side Doors That Must Close

- `ThreadDetailStore.recoveryTask` as an independent rehydrate gate.
- `ThreadDetailLiveEventBuffer` as a detail-only replay buffer.
- `ThreadCardStreamLifecycle` as a root-only stream lifecycle.
- `ThreadCardTable` as a separate projection apply law.
- `ThreadCardTable.applySnapshot` accepting non-snapshot updates.
- `thread/detail/read` for production display.
- `projection/witness/read` from app UI.
- same-sequence catch-up `upsert` payloads.
- command success treated as visible row proof.
- route health displayed as data freshness.
- one-shot host tests displayed as proof of current screen catch-up.
- skipped UI sync tests counted as a pass.
- proof schema deny-lists used instead of strict allow-lists for identity,
  order, freshness, and route truth.
- proof scripts accepting `thread/detail/read` as the visible truth oracle.
- proof code retaining legacy expected projection ID or expected message ID
  paths.
- `thread/detail/read` marked app-critical in Swift or relay observability after
  cutover.
- live-filter proof scripts using `thread/detail/read` as relay truth.
- raw DTO fixtures that bypass projection envelopes.
- previews or tests that reconstruct visible rows from local metadata or raw
  Codex history.
- fake Swift stream/session types that instantiate deleted production state
  machines instead of the new reconciler.
- legacy relay helper routes or dormant SQLite tables treated as fallback
  production state.

## 6.3 Migration Notes

The migration is a replacement, not an adapter stack:

- Build the shared reducer and relay stream contract first.
- Build the reconciler against that contract.
- Cut one vertical slice to Thread Detail because that is where the user-visible
  stuck bug is most obvious.
- Cut Dock and Archive to the same runtime next.
- Delete the old lifecycle, buffer, and side-door tests in the same phase that
  replaces them.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan

<!-- arch_skill:block:phase_plan:start -->
This is the authoritative implementation checklist. A phase is not complete
while legacy runtime code, fixtures, proof routes, or docs can still support the
old path.

## Phase 1 - Shared Projection Contract And Reducer

Work:

- Define one projection envelope/update grammar for Dock, Archive, and Thread
  Detail.
- Add the explicit `page` catch-up update kind and remove same-`seq` catch-up
  `upsert` semantics.
- Generate/update relay schemas and Swift DTOs from the shared contract.
- Implement `ProjectionReducer<Row>` with typed row policies for card rows and
  detail rows.
- Move duplicate validation from `ThreadCardTable` and
  `ThreadDetailDataEngine` into the shared reducer.
- Add one short source comment at the reducer boundary: visible projection
  identity, order, revision, freshness, and catch-up semantics are relay-owned;
  stores and render projectors must not reimplement them.

Deletes in this phase:

- Any schema compatibility `$ref` or generated DTO field that preserves
  pre-projection row identity for production display.
- Tests that validate old same-`seq` catch-up `upsert` as acceptable behavior.
- Raw DTO fixtures that bypass projection envelopes instead of using generated
  projection fixtures.

Exit criteria:

- Shared reducer tests cover snapshot, page, upsert, delete, heartbeat,
  `resyncRequired`, epoch change, sequence gap, duplicate `projectionID`,
  duplicate source identity, immutable identity change, stale revision, wrong
  source host, wrong view, wrong view params key, wrong order, and malformed
  window.
- `ThreadCardTable.applySnapshot` no longer accepts non-snapshot updates, or
  `ThreadCardTable` is gone.
- `ThreadDetailDataEngine` either delegates to the shared reducer or is gone.
- Contract checks prove Swift and relay use the same update-kind grammar.
- Fixture tests prove expected production rows come from the projection contract,
  not raw Codex DTO shortcuts.

Blocking proof:

```bash
rtk npm run contract:check
rtk swift test --filter ProjectionReducerTests
rtk swift test --filter DockDataEngineTests
rtk swift test --filter ThreadDetailStoreTests
```

## Phase 2 - Relay Projection Stream Contract Cutover

Work:

- Update `RelayStateEngine`, `StateSubscriptionHub`, and Thread Detail ledger
  code to emit the shared update grammar from Phase 1.
- Convert root catch-up to explicit `page` updates or an equivalent distinct
  page contract generated from schema.
- Make Thread Detail use the same envelope/update law as root streams before
  the Swift Thread Detail cutover tries to prove against production routes.
- Make the projection witness record exact downstream envelopes for Dock,
  Archive, and Thread Detail.
- Make raw Codex inputs, live leases, live status cache, `session_index.jsonl`,
  and summary helpers source metadata only before projection collapse.
- Make contract bumps deterministically invalidate incompatible relay state
  caches.
- Keep `projection/witness/read` proof-only and unavailable to app UI.
- Reclassify `thread/detail/read` across Swift and relay observability so it is
  not app-critical production display evidence. If retained at all, it is
  manual diagnostic-only and cannot be used by acceptance proof.

Deletes in this phase:

- Same-`seq` `upsert` catch-up emission.
- Detail-only witness recording.
- Production display access to `thread/detail/read`.
- App-critical `thread/detail/read` entries in
  `CodexDock/Diagnostics/ObservabilityContract.swift` and
  `scripts/dock-relay-observability-contract.mjs`.
- Proof/status acceptance of `thread/detail/read` in
  `scripts/dock-relay-status.mjs`, `scripts/proof-report-contracts.mjs`
  `CLIENT_CARD_ROUTES`, and related tests.
- Legacy helper routes or dormant DB paths treated as fallback projection state.

Exit criteria:

- Relay tests prove one envelope grammar for root and detail streams.
- Projection witness can reproduce the exact downstream stream envelopes for the
  view key under test.
- Relay contract checks fail if `thread/detail/read` is accepted as a production
  display route.
- Observability/status/proof checks no longer classify `thread/detail/read` as
  app-critical production display evidence.
- Cache contract bump invalidates incompatible stored state by definition.
- Raw source helpers are reachable only before relay projection collapse.

Blocking proof:

```bash
rtk npm run contract:check
rtk npm run test:relay
```

## Phase 3 - Canonical StreamReconciler Core

Work:

- Implement one `StreamReconciler` actor or equivalent owner per
  `sourceHostID + view + scope + viewParamsKey`.
- Move initial subscribe, manual refresh, foreground resume, transport
  reconnect intent, heartbeat timeout, sequence gap, relay `resyncRequired`,
  buffer overflow, command-completed invalidation, finite catch-up, and close
  into the reconciler.
- Make `AppServerClient` transport-only for liveness: it emits transport
  events, but it does not decide projection freshness.
- Add bounded buffering with a replay cutoff. Live events arriving during
  catch-up are replayed after the cutoff; overflow forces one canonical resync.
- Add a reconciler freshness state that distinguishes `connecting`,
  `subscribing`, `live`, `catchingUp`, `stale`, `offline`, `failed`, and
  `closed`.

Deletes in this phase:

- Any new store-owned `Task?` state machine for subscribe/resync/heartbeat.
- Any reconnection rule that treats socket reconnect as view freshness.

Exit criteria:

- Reconciler unit tests cover initial subscribe, reconnect, foreground resume,
  manual refresh, heartbeat timeout, sequence gap, relay `resyncRequired`,
  buffer overflow, close, command invalidation, stale deadline, and replay under
  sustained updates.
- `AppServerClientTests` still prove request/response and transport reconnect,
  but no test asserts that transport reconnect alone makes a view live.
- Strict concurrency warnings are quarantined to named platform bridge files
  only: URLSession WebSocket transport, AVFoundation voice capture, MetricKit,
  and lifecycle notification glue. Projection runtime, reducers, stores, and
  render projectors cannot use quarantine exceptions.

Blocking proof:

```bash
rtk swift test --filter AppServerClientTests
rtk swift test --filter ProjectionRuntimeTests
```

## Phase 4 - Thread Detail Cutover

Work:

- Move `ThreadDetailStore.load()`, notification observation, rehydrate,
  foreground recovery, Dock-row-triggered refresh, relay `resyncRequired`, and
  stale/live labels onto `StreamReconciler`.
- Keep local composer, voice, request-card input, and command status in
  `ThreadDetailStore`.
- Command sends enqueue projection invalidation or wait-for-projection intent;
  visible rows still arrive only through relay projection.
- Replace `ThreadDetailLiveEventBuffer` with reconciler-owned bounded buffering.
- Make `thread/detail/read` unavailable to production display code.

Deletes in this phase:

- `ThreadDetailLiveEventBuffer.swift`.
- `ThreadDetailStore.recoveryTask` and direct rehydrate loops.
- Detail tests that fake old store recovery instead of driving the reconciler.

Exit criteria:

- Opening a busy real or controlled Thread Detail view catches up through the
  reconciler while live updates continue.
- Sequence gap, heartbeat timeout, foreground resume, and relay
  `resyncRequired` all take the same recovery path.
- Sending an outbound message cannot duplicate visible rows because visible row
  creation is relay-only.
- Request-card local overlays remain keyed by relay projection identity.

Blocking proof:

```bash
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter ThreadDetailStoreLifecycleTests
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SCENARIO=detail-reconnect MAX_UI_LAG_MS=2000
```

## Phase 5 - Dock And Archive Cutover

Work:

- Move Dock and Archive stream ownership from `ThreadCardStreamLifecycle` to
  `StreamReconciler`.
- Make `DockStore` and `ArchiveStore` adapters over reconciler output plus local
  filter/lens/pin/archive UI state.
- Keep local metadata decoration, but keep identity, row existence, order,
  freshness, and action identity from relay projection.
- Move archive/unarchive command convergence into reconciler invalidation or
  wait-for-projection, not separate refresh assumptions.
- Ensure host registry changes close obsolete reconcilers and open new view
  keys deterministically.

Deletes in this phase:

- `ThreadCardStreamLifecycle.swift`.
- Production use of `AppServerThreadCardStreamClient` as an independent stream
  owner.
- Tests that instantiate `ManualThreadCardStreamClient` or old lifecycle/table
  paths as the production behavior owner.

Exit criteria:

- Dock and Archive use the same reconciler and reducer semantics as Thread
  Detail.
- Host add/remove, foreground resume, stream close, heartbeat timeout,
  sequence gap, and catch-up page all converge through one path.
- Local pin/group/filter behavior never changes canonical row identity or
  freshness.

Blocking proof:

```bash
rtk swift test --filter DockStoreTests
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SCENARIO=resync-gap MAX_UI_LAG_MS=2000
```

## Phase 6 - Connectivity, Health, And Lifecycle Cutover

Work:

- Derive view freshness only from reconciler state.
- Keep route diagnostics and `/routesz` as evidence, not truth.
- Update `AppConnectivityStore`, `ConnectivityDataEngine`,
  `ConnectivityRenderProjector`, and `SystemHealthProjector` to show route
  health separately from view freshness.
- Route foreground/background and scene-phase changes into reconciler intents.
- Ensure one-shot host tests do not count as proof that the current screen is
  caught up.

Deletes in this phase:

- Any status copy or logic that equates WebSocket connected with screen live.
- Any health rollup that hides view-specific stale/catching-up state.

Exit criteria:

- UI can show route connected while a specific view is catching up or stale.
- UI cannot show a view as live until the exact view key has converged.
- Lifecycle tests cover Dock, Archive, and Thread Detail through one path.

Blocking proof:

```bash
rtk swift test --filter AppConnectivityStoreTests
rtk swift test --filter SystemHealthProjectorTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

## Phase 7 - Proof, Fixtures, And Simulator Oracle Cutover

Work:

- Make structured UI dump the canonical current-screen diagnostic for Dock and
  Thread Detail.
- Make strict simulator sync proof compare visible UI to relay projection
  witness for the same `sourceHostID + view + scope + viewParamsKey`.
- Remove skipped-proof success paths from gate targets.
- Replace broad proof schema deny-lists with strict allow-lists for identity,
  order, freshness, route truth, and visible row fields.
- Remove legacy expected-message/projection ID proof code.
- Tighten `Makefile` proof defaults so bare
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` uses strict
  acceptance settings, or rename the loose path to an explicit diagnostic target
  and make the strict target canonical. Loose defaults must not share the
  acceptance command name.
- Migrate `scripts/codex-dock-live-filter-truth.mjs`,
  `scripts/codex-dock-live-filter-compare.mjs`, and
  `CodexDockLiveFilterProofTests.swift` to projection-witness truth, or mark
  the live-filter path as diagnostic-only and unavailable as acceptance proof.
- Move test fakes behind the same reconciler/reducer contract.
- Add controlled scenarios for:
  - `detail-replay-pressure`
  - `current-work-visible`
  - `root-catchup-window-contract`
  - `mutation-ack-projection-refresh-failure`
  - `foreground-resume-all-surfaces`
- Register those scenarios in the controlled fixture, matrix runner, and
  canonical `SIM_UI_CONTROLLED_MATRIX_SCENARIOS` set so they run by default in
  strict acceptance proof.

Deletes in this phase:

- Proof acceptance through one-shot `sim-ui-dump`.
- Proof acceptance through screenshots or recordings.
- Proof oracle paths using raw `thread/detail/read`.
- Live-filter proof acceptance that reads `thread/detail/read`.
- Fake stream/session fixtures that preserve deleted runtime owners.
- Preview rows used as freshness evidence.

Exit criteria:

- `app-test` can still run smoke/UI tests, but live-update acceptance requires
  the strict proof command.
- Missing sync config fails strict proof targets instead of skipping.
- Controlled matrix runs at least two passes, checkpoint sweep enabled, with
  `MAX_UI_LAG_MS=2000` or stricter.
- The Makefile-owned canonical matrix command uses those strict settings by
  default, or the only acceptance command is a named strict target with those
  settings baked in.
- Structured UI dumps include enough detail to diagnose visible Thread Detail
  and Dock state without screenshots.
- Live-filter proof either uses the same projection witness as the strict sync
  proof or is explicitly non-acceptance diagnostics.

Blocking proof:

```bash
SIM_UI_CONTROLLED_MATRIX_PASSES=2 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 MAX_UI_LAG_MS=2000 rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
rtk make sim-ui-dump SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
```

`sim-ui-dump` in this phase is required diagnostic evidence for what the app is
showing now. It is not acceptance proof unless the same run also passes strict
relay-witness comparison over time.

## Phase 8 - Documentation And Deletion Sweep

Work:

- Update `README.md` as the canonical runbook.
- Update code comments at the reducer/reconciler boundaries.
- Cross-link this plan from related bug/root-cause docs.
- Delete or rewrite stale docs that still instruct old runtime paths if they
  would mislead implementation.
- Retire
  `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md`
  before implementation starts if it still claims an old phase ledger is
  complete.
- Audit the implementation by reading actual call sites and tests, not by
  relying on a keyword grep.
- Run the physical-phone rollout gate when making a real phone behavior claim.
  If the device is unavailable, busy, locked, missing WebDriverAgent, or blocked
  by signing, record the exact blocker and do not claim physical-phone
  completion.

Deletes in this phase:

- Stale "implemented" claims that refer to old partial live-update fixes.
- Any `old`, `legacy`, backup, alternate runtime, or copy file introduced
  during implementation.
- Any test-only side path that lets old production behavior compile.

Exit criteria:

- README tells one story: relay projection stream, Swift reconciler, shared
  reducer, strict UI proof.
- No source file outside the reconciler/reducer/transport bridge owns
  subscribe/resync/replay/heartbeat/freshness for production display.
- No production app code imports proof-only routes.
- No test fixture instantiates deleted lifecycle/buffer/table owners.
- Physical iPhone validation either passes through repo-owned device commands
  or is explicitly marked blocked with the exact command and blocker.
- Strict concurrency exceptions are limited to named platform bridge files and
  do not appear in projection runtime, reducers, stores, or render projectors.
- Fresh consult and implementation audit agree no side doors remain.

Blocking proof:

```bash
rtk make device-install-all
rtk make device-config-verify-all
```

If only one phone is available for the claim, use the specific repo-owned target:

```bash
rtk make iphone-17-pro
rtk make iphone-14
```
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy

Verification must be staged with the implementation phases in section 7. The
final suite must include these blocking checks:

- Contract and schema checks for relay projection envelopes, update kinds,
  row identity, proof dumps, and generated Swift DTOs.
- Relay tests for snapshot, page, upsert, delete, heartbeat, `resyncRequired`,
  source-host identity, projection witness, command-triggered invalidation, and
  sustained update pressure during catch-up.
- Swift reducer tests shared by Dock, Archive, and Thread Detail.
- Swift reconciler tests for initial subscribe, manual refresh, foreground
  resume, transport reconnect, heartbeat timeout, sequence gap, buffer
  overflow, route close, relay `resyncRequired`, screen close, and command
  completion.
- Store tests proving stores cannot bypass the reconciler.
- UI/proof tests that open real simulator views, drive projection changes over
  time, dump structured visible state, and compare it to the relay projection.
- Physical-phone checks for any claim about actual iPhone behavior, with exact
  blocker language if device state prevents validation.

Representative commands:

```bash
rtk npm run contract:check
rtk npm run test:relay
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
SIM_UI_CONTROLLED_MATRIX_PASSES=2 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 MAX_UI_LAG_MS=2000 rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
rtk make sim-ui-dump SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
rtk make device-config-verify-all
```

`sim-ui-dump` is listed here as the canonical current-screen diagnostic command,
not as proof that live updates converged.

# 9) Rollout / Ops / Telemetry

Rollout is a clean local-development cutover, not a compatibility migration.

- The implementation branch may break old tests while phases are in progress,
  but no phase may claim complete while old side doors still compile as
  production runtime.
- Service restart and simulator reinstall are required only when code changes
  touch relay runtime, service config, generated DTOs, app target settings, or
  installed UI behavior.
- Logs must continue to avoid secrets, prompt text, transcript text, audio, raw
  bearer tokens, and full JSON-RPC payloads.
- Telemetry must distinguish route health from projection freshness and must
  report catch-up state for the exact view key.
- README is the canonical runbook after implementation; dated planning docs are
  history.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, sections 0 through 10, helper blocks, route
    classification, phase order, proof gates, call-site audit, and stale sidecar
    audit metadata.
- Findings summary:
  - First cold reader found phase-order drift, missing phone proof gate,
    ambiguous target route list, stale sidecar audit metadata, incomplete strict
    concurrency boundary, and a raw DTO fixture exit gap.
  - Second cold reader found the same phase-order problem plus exact
    `thread/detail/read` diagnostics/proof side doors, live-filter proof oracle
    drift, and a weaker Section 8 matrix command.
- Integrated repairs:
  - Moved relay projection stream contract cutover before Swift client cutovers
    so production proof has the producer contract it requires.
  - Replaced ambiguous command route names with actual `turn/*` route names and
    added kept command-adjacent and audio/transcription route buckets.
  - Added explicit `thread/detail/read` migrations for Swift diagnostics, relay
    observability, route status, proof report contracts, live-filter scripts,
    and related tests.
  - Made strict simulator matrix proof command consistent everywhere:
    `SIM_UI_CONTROLLED_MATRIX_PASSES=2 SIM_UI_SYNC_CHECKPOINT_SWEEP=1
    MAX_UI_LAG_MS=2000 rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`.
  - Added physical-phone proof or exact-blocker gate for real iPhone claims.
  - Added strict concurrency quarantine boundary and final exit criteria.
  - Added raw DTO fixture deletion to Phase 1 and Phase 7 coverage.
  - Retired the stale sidecar plan audit file as non-authoritative.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log

## 2026-06-02 - Rebuilt This Doc As The Canonical Plan

The previous version mixed a newer architecture section with older
implementation evidence and a stale phase plan. This rewrite removes that
material from the live plan surface. Git retains the history.

## 2026-06-02 - Clean Cutover, No Test Side Doors

The implementation must delete legacy production paths and migrate tests to the
new runtime. Test-only preservation of old subscribe, resync, buffering,
identity, ordering, or proof paths is explicitly rejected.

## 2026-06-02 - Relay Projection Is The Visible Source Of Truth

Swift may hold local draft, voice, request-card input, and transient command
status, but visible conversation/card rows come from relay projection rows.

## 2026-06-02 - Catch-Up Pages Are A Distinct Contract

Catch-up window extension must not masquerade as a same-sequence `upsert`.
Implementation must add or formalize a distinct page-style update contract and
test it end to end.

## 2026-06-02 - Relay Contract Before Client Cutovers

The relay stream grammar, catch-up `page` contract, and projection witness must
land before Thread Detail, Dock, or Archive cutovers can claim production proof.
Client proof cannot precede the producer contract it is proving against.

## 2026-06-02 - `thread/detail/read` Is Not Acceptance Truth

`thread/detail/read` may survive only as manual diagnostics if implementation
keeps it at all. It is not production display truth, not app-critical display
evidence, and not an acceptance proof oracle after cutover.

## 2026-06-02 - Strict Proof Means Strict Defaults

Live-update acceptance uses the strict controlled matrix command with two
passes, checkpoint sweep enabled, and `MAX_UI_LAG_MS=2000` or stricter. A
one-shot UI dump remains diagnostic only.

## 2026-06-02 - Physical Phone Claims Need Physical Phone Proof

Simulator proof gates architecture bugs, but claims about actual iPhone behavior
require repo-owned device commands or an exact recorded device blocker.
