---
title: "Codex Dock - Relay State Engine Hard Cutover - Architecture Plan"
date: 2026-05-30
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: ["Composer 2.5 Fast"]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_GOALS_2026-05-29.md
  - docs/CODEX_DOCK_RELAY_STATE_PARITY_WORKLOG_2026-05-30.md
  - docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md
  - docs/CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md
  - docs/CODEX_DOCK_OBSERVABILITY_ARCHITECTURE_2026-05-30.md
  - README.md
  - Makefile
  - scripts/dock-relay.mjs
  - scripts/dock-relay-session-table.mjs
  - scripts/dock-relay-state-snapshot.mjs
  - scripts/dock-relay-thread-data.mjs
  - scripts/dock-relay-live-status-cache.mjs
  - scripts/dock-relay-observability-contract.mjs
  - CodexDock/AppServer/DockStreamDTO.swift
  - CodexDock/State/DockStore.swift
  - CodexDock/State/DockSessionTable.swift
  - CodexDock/State/ArchiveStore.swift
---

# TL;DR

Outcome: replace the current relay session-table prototype with a real
relay-owned SQLite state engine. The normal app path reads indexed,
host-scoped relay state and bounded view changes; it never rebuilds truth by
parsing `.codex-dock/dock-session-table.json` or crawling Codex history inside
`dock/subscribe`.

Problem: the current relay mixes source collection, live discovery, UI row
projection, subscription fanout, persistence, diagnostics, and fallback
snapshots in one hot path. That path is already wrong for roughly 1519
app-server-listable threads and 219595 app-server turn items, and it will fail
harder as the dataset grows.

Approach: hard-cut the runtime relay to one state engine:
app-server-backed collectors write transactional SQLite rows, materialized view
queries serve Dock/Archive/Agents/Activity/detail surfaces, subscriptions
stream bounded deltas, and explicit audit tooling compares runtime state
against Codex disk/SQLite without mixing audit facts into normal app rows.

Plan: first cut over Dock end-to-end through the new state engine and delete the
old JSON/session-table runtime; then expand the same engine to Archive, live
leases, detail/activity facts, observability/explain surfaces, and audit parity;
then remove stale docs, constants, tests, and code paths that still describe or
depend on the retired model.

Non-negotiables: no runtime shims, no last-good JSON primary store, no
`ps`-based correctness, no silent caps, no disk/SQLite facts in normal runtime
rows, no full-history mirror in relay SQLite, no diagnostic endpoint that
mutates app state, no partial snapshot sent to a client that will treat it as
complete, and no implementation before this plan is accepted.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-30
external_research_grounding: not needed - local relay architecture plus official SQLite/Node grounding
deep_dive_pass_2: done 2026-05-30
recommended_flow: auto-plan -> Composer 2.5 Fast alignment -> implement only after explicit user request
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:257f961bcaead165bf9145e0308b845189d54ab217f8f92a5df40df5414b9d44",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-30T15:27:00Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:3294bed1dc1b85a31f225b57d1dc8ffabc3ffa5767f3f974092ff47909e1d4bc",
      "completed_at": "2026-05-30T15:27:11Z",
      "doc_hash_after": "sha256:6ca5324d41a9d4ba89fc08283cf3acfc45d1786fe4e41deae26e87ab11b1f87c"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T15:27:15Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:6ca5324d41a9d4ba89fc08283cf3acfc45d1786fe4e41deae26e87ab11b1f87c",
      "completed_at": "2026-05-30T15:27:29Z",
      "doc_hash_after": "sha256:f27b64f768a0ed9c628907a596f28d8385ce03a370d1242a1201c98b4972abf5"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T15:27:33Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:f27b64f768a0ed9c628907a596f28d8385ce03a370d1242a1201c98b4972abf5",
      "completed_at": "2026-05-30T15:27:46Z",
      "doc_hash_after": "sha256:f3fe5bea1d929e7d9d6622644b2cbef9b14d9d66f13a78aac3084df7a238e26f"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-30T15:27:49Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:f3fe5bea1d929e7d9d6622644b2cbef9b14d9d66f13a78aac3084df7a238e26f",
      "completed_at": "2026-05-30T15:28:05Z",
      "doc_hash_after": "sha256:d92c7a8d5cbd1117dc1cbc5bb90c2b79a155957416dba341ccf4a916fc4552f4"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-30T15:28:23Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:d92c7a8d5cbd1117dc1cbc5bb90c2b79a155957416dba341ccf4a916fc4552f4",
      "completed_at": "2026-05-30T15:34:04Z",
      "doc_hash_after": "sha256:2bd37f205ef03a5290168424fb26a5acea825e2ae3fd740af17d3711b66b8d9d"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, Codex Dock's relay runtime has exactly one production
state path for app-visible Codex thread truth: app-server collectors write
host-scoped SQLite rows, materialized views read those rows, and client
subscriptions stream bounded changes from those rows.

The claim is false if any of these remain true:

- `dock/subscribe` can crawl app-server history before answering a client.
- `.codex-dock/dock-session-table.json` remains a production state source.
- `DockSessionAggregator` or an equivalent whole-table in-memory/JSON path can
  still serve the normal app view.
- live owner routing depends on scanning `ps` output as a correctness source.
- Archive, Dock, Agents, Activity, or detail screens infer missing state instead
  of receiving known, stale, incomplete, conflict, or unknown markers.
- disk/SQLite audit facts silently create or modify normal app runtime rows.
- a diagnostic endpoint runs source sync or mutates Dock state as part of a
  health check.

## 0.2 In scope

- The Node Dock relay on `:4510`.
- The app-server-backed runtime truth boundary documented in
  `docs/CODEX_DOCK_GOALS_2026-05-29.md`.
- A relay-owned SQLite state database at `.codex-dock/relay-state.sqlite`.
- Hard cutover from `DockSessionAggregator` and
  `.codex-dock/dock-session-table.json`.
- Existing app-server command authority: `thread/list`, `thread/read`,
  `thread/turns/list`, `thread/loaded/list`, `thread/goal/get`,
  `thread/archive`, `thread/unarchive`, `thread/resume`, `turn/start`,
  `turn/steer`, and `turn/interrupt`.
- Runtime collectors for app-server list/read/turn/goal/live facts.
- Hot updates from relay-owned command responses, open detail/live connections,
  app-server notifications already observed on those connections, and validated
  live leases.
- Warm reconciliation for boot, reconnect, sequence gaps, archive mutations,
  command completion, explicit resync, and a slower state-engine cadence owned
  by relay constants rather than the old five-second whole-table loop.
- Cold audit commands that compare app-server-backed relay state with Codex
  disk/SQLite.
- Dock, Archive, Agents, Activity, and Thread Detail view contracts that read
  from the state engine or proxy app-server detail through state-engine
  routing.
- Swift DTO/client changes needed to make bounded/windowed state explicit.
- Relay observability changes needed to explain the same state the app uses.
- README, Makefile, constants, tests, and live docs that currently describe the
  retired JSON/aggregator model.

## 0.3 Out of scope

- Modifying Codex itself or relying on private changes to the Codex binary.
- Making Codex disk/SQLite the normal runtime source of app-visible rows.
- Building a central cloud sync service.
- Adding multi-user auth, tenancy, permissions, or privacy ceremony.
- Mirroring every turn item for every thread into relay SQLite as durable
  product state.
- Preserving the old relay session-table implementation as a compatibility
  path.
- Adding repo-policing tests that prove deletion by string absence.
- Physical-phone verification during planning.

## 0.4 Definition of done (acceptance evidence)

- `dock/subscribe`, `dock/update`, and `dock/resync` read from the relay state
  engine and cannot trigger app-server history drains in the request path.
- The relay starts only if the SQLite state engine initializes successfully and
  migrations are current; state-store failure is fail-loud.
- `.codex-dock/dock-session-table.json` is no longer read or written by relay
  production code.
- `DockSessionAggregator` and its tests are removed or replaced by
  state-engine tests.
- Normal Dock rows exclude archived threads by a stored app-server archive
  state or by an explicit unknown/incomplete marker, never by disappearance
  from one list.
- The relay can answer counts for active, archived, live, spawned, stale,
  incomplete, and conflict rows without reading a giant JSON file.
- Loaded/live app-server rows remain visibly live, waiting, or unknown through
  the Dock stream after the hard cutover; absence of a validated lease is never
  downgraded to a false dormant state.
- `thread/read` and `thread/turns/list` detail paths drain opened-thread turns
  to cursor exhaustion or expose the exact stop point.
- `relay/state/snapshot` remains an audit/export surface or is replaced by a
  state-engine audit surface; it is not the runtime store.
- `/selftestz` reads health only and does not call `dock/subscribe`, force warm
  reconciliation, or write relay state.
- Existing relay tests are rewritten around the new state engine and pass with
  `rtk npm run test:relay`.
- Swift stream reducer tests pass with the final DTO contract using
  `rtk swift test --filter DockStoreTests`.
- Detail path tests pass with `rtk swift test --filter ThreadDetailStoreTests`
  when detail contracts change.
- App-server DTO/client tests pass with
  `rtk swift test --filter AppServerClientTests` when protocol DTOs change.
- Composer 2.5 Fast agrees that the plan is a hard-cutover state-engine plan,
  not a sunk-cost extension of the JSON aggregator.

## 0.5 Key invariants (fix immediately if violated)

- Runtime truth is app-server-exposed truth only.
- Disk and SQLite are audit-only unless the product goal is explicitly changed.
- One production relay state store owns materialized runtime state.
- Host scope is part of every persistent state key.
- No silent caps: any bounded view must expose `totalRows`, `complete`, and a
  cursor/window contract.
- Live status is explicit lease state: live, waiting, needs input, stale, or
  unknown. Unknown is acceptable; falsely dormant is not.
- Unknown is a first-class state, not a hidden default.
- Stale and incomplete are visible product states, not reasons to lie.
- Diagnostics read state; they do not refresh state.
- Hard cutover means deleted production paths, not a runtime bridge.
- Fallback policy is forbidden.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct one-to-one representation of every app-server-exposed thread per
   host.
2. Clear authority boundaries: app-server runtime, disk/SQLite audit, relay
   projection, client presentation.
3. Bounded app startup and subscription behavior regardless of total history
   size.
4. Queryable, transactional state with per-field provenance and freshness.
5. Hard deletion of retired runtime paths so the old model cannot reappear.
6. Multi-host correctness through `(host_id, thread_id)` identity.
7. Lean verification that proves behavior without adding ceremony.
8. Operator clarity through `/statusz`, `/routesz`, `/statez`, `/syncz`,
   `/subscriptionsz`, `/dbz`, `/explainz`, and bounded bundles.

## 1.2 Constraints

- Current local Node is `v25.9.0`; `node:sqlite` is available locally. The
  implementation must either require a Node runtime with `node:sqlite` or stop
  relay startup with an exact runtime error.
- `package.json` currently has only `ws` as a dependency. The preferred plan is
  to use built-in `node:sqlite`, not add a native npm dependency, unless the
  implementation runtime proves `node:sqlite` cannot meet the contract.
- App-server `thread/list` page size is clamped to `THREAD_LIST_MAX_LIMIT` 250.
- App-server does not expose one global atomic snapshot revision across
  `thread/list`, `thread/read`, `thread/turns/list`, and `thread/goal/get`.
- App-server notifications are connection-scoped; relay-owned hot ingest must
  use command responses, open detail/live connections, and validated live
  leases rather than inventing an all-thread notification feed.
- Swift currently treats `DockStreamUpdateDTO.kind == snapshot` as a complete
  replacement. Partial/windowed snapshots require an explicit DTO/client change
  before the relay sends them.
- The first hard-cut Dock slice must include explicit completeness/window fields
  and a real serialized-size check, so it cannot assume today's roughly 1519
  rows will always fit under the soft transport budget.
- The first hard-cut Dock slice must also preserve loaded/live status from
  app-server evidence. The later live-routing phase can harden command routing,
  but Phase 1 may not make known live sessions look dormant.
- Physical-phone proof is not part of this planning pass.

## 1.3 Architectural principles (rules we will enforce)

- The relay process owns exactly one `RelayStateEngine` instance.
- Every source collector writes through the same SQLite transaction API.
- Every client view reads through named view queries, not through source
  collectors.
- The old JSON table is deleted as a production state source.
- Route handlers do not perform source drains except explicit source/audit
  commands.
- Background reconciliation writes row-level changes, not whole-table
  replacement blobs.
- Live state is a lease overlay with expiry and validation, not a replacement
  for durable identity.
- App-server field conflicts are preserved in provenance.
- Source gaps remain visible as `unknown`, `stale`, `incomplete`, or `conflict`.
- Constants for state budgets, windows, intervals, and DB paths live in
  `scripts/dock-relay-constants.mjs`.

## 1.4 Known tradeoffs (explicit)

- Hard cutover is more disruptive than a hidden bridge, but it prevents the
  old JSON/aggregator path from staying around as a second source of truth.
- Using `node:sqlite` makes the relay simpler and avoids native npm install
  risk, but it requires the host runtime to support the module.
- Runtime SQLite will not mirror all turn items. Opened-thread detail remains
  complete by draining app-server pages on demand, while cold audit can perform
  exhaustive full-history drains.
- Archive and Activity become state-engine views, which requires more relay
  contract work up front but removes repeated client-side list crawls.
- `ps` discovery is convenient during local development, but it is too
  accidental for correctness. Explicit endpoint ownership is a better failure
  mode: unregistered live owners become unknown, not guessed.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The relay currently has a prototype state path centered on
`scripts/dock-relay-session-table.mjs`.

That file:

- defines `DockSessionAggregator`;
- periodically refreshes every 5000ms by default;
- drains active `thread/list` pages for explicit source kinds and default
  interactive scope;
- overlays live status from `LiveStatusCache`;
- normalizes rows into `DockStreamSessionDTO`;
- keeps an in-memory `DockSessionTable`;
- writes `.codex-dock/dock-session-table.json` as the last-good snapshot;
- serves `dock/subscribe`, `dock/update`, and `dock/resync`.

The relay also has an audit-grade app-server snapshot path in
`scripts/dock-relay-state-snapshot.mjs`. That path can drain scopes, preserve
order, read details, and optionally drain turns, but it returns one snapshot
object. It is not a runtime state store.

Swift currently has two app-facing list paths:

- Dock uses `AppServerDockStreamClient` and `DockStore` to subscribe to
  `dock/*`.
- Archive uses `ArchiveStore` and `AppServerDockClient` to call
  `thread/list archived:true` through the relay.

Thread detail uses `AppServerThreadDetailSession`, `ThreadDetailStore`, and raw
app-server methods through the relay.

## 2.2 What's broken / missing (concrete)

- `dock/subscribe` can wait on a source refresh before returning the first
  screen.
- Whole-table JSON persistence is not indexed, transactional, row-addressable,
  or provenance-aware.
- The relay cannot answer state questions cheaply without rebuilding or reading
  the whole table.
- The old table represents only a compact Dock view, not every
  app-server-exposed runtime fact.
- Archive still uses a separate client list path instead of a materialized
  relay view.
- Live owner routing currently depends on loopback process discovery through
  `ps`, which is endpoint discovery at best and not correctness.
- `/selftestz` currently special-cases `dock/subscribe` by calling the
  aggregator snapshot path, which can create app-path load.
- Summary warming is tied to `aggregateThreadList`, so route reads can trigger
  unrelated background work.
- `ThreadSummaryCache` is a second turn-adjacent cache outside the proposed
  state engine and must be deleted from the hot list path or re-homed under the
  bounded state-engine `turn_cache`.
- The current `512MB` JSON-RPC payload limit is a failure guard but can become
  an architectural crutch if large snapshots are tolerated.
- Spawn, prompt-start, JSON-mode, provenance, stale, incomplete, and conflict
  states are not represented as first-class runtime state.

## 2.3 Constraints implied by the problem

- The solution must change where state lives, not only where refresh work runs.
- The app path must become a bounded read from already-materialized state.
- Source collection must be separated from view serving.
- Runtime and audit authority must stay separate.
- The implementation must delete the old runtime path so the relay cannot drift
  between two answers.
- Swift must understand any window/partial contract before the relay sends one.

<!-- arch_skill:block:research_grounding:start -->
# 3) Research Grounding (external + internal “ground truth”)

## 3.1 External anchors (papers, systems, prior art)

- SQLite WAL mode - adopt. SQLite documents `PRAGMA journal_mode=WAL;` as the
  WAL activation path and describes the WAL file as part of persistent database
  state while open. This supports a small local transactional state index with
  normal checkpoint/backup care.
- Node `node:sqlite` - adopt if the target runtime supports it. Official Node
  docs say `node:sqlite` provides `DatabaseSync`; local `node --version` is
  `v25.9.0` and local import of `node:sqlite` succeeds. The relay should use
  the built-in module unless implementation discovers a hard runtime blocker.
- Event-store architecture - reject for this relay. The relay needs current
  materialized Codex state with provenance, not a full append-only rewrite of
  Codex history.

Grounding links:

- SQLite WAL: `https://www.sqlite.org/wal.html`
- Node SQLite API: `https://nodejs.org/download/release/latest-v24.x/docs/api/sqlite.html`
- Current local runtime proof: `node --version` returned `v25.9.0`; importing
  `node:sqlite` exposed `DatabaseSync`, `Session`, `StatementSync`, `backup`,
  `constants`, and `default`.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors:
  - `scripts/dock-relay.mjs` - owns the phone-facing WebSocket/HTTP relay,
    method dispatch, upstream routing, `/statusz`, `/routesz`, `/selftestz`,
    `/bundlez`, and relay startup lifecycle.
  - `scripts/dock-relay-session-table.mjs` - owns the current prototype
    Dock stream, old JSON persistence, refresh loop, and `DockSessionAggregator`;
    this is the primary delete/replace target.
  - `scripts/dock-relay-state-snapshot.mjs` - owns proven app-server scope
    draining, repeated-cursor detection, archive/source separation, canonical
    field projection, and optional turn drains; reuse its collector logic, not
    its one-giant-object runtime shape.
  - `scripts/dock-relay-thread-data.mjs` - owns app-server reads, live status
    cache construction, live endpoint discovery, summary decoration, and
    thread command helpers; split source access from view materialization here.
  - `scripts/dock-relay-live-status-cache.mjs` - owns current live overlay and
    session routing; replace `ps` endpoint discovery with explicit endpoint
    configuration plus validated leases.
  - `scripts/dock-relay-observability-contract.mjs` and
    `scripts/dock-relay-observability.mjs` - own route-health vocabulary and
    bounded traces; extend this spine with state-engine health instead of
    adding a competing diagnostic model.
  - `CodexDock/AppServer/DockStreamDTO.swift` - owns the current
    `dock/subscribe` snapshot/delta/heartbeat DTO.
  - `CodexDock/State/DockSessionTable.swift` - owns Swift stream reduction;
    it currently assumes snapshots are complete replacement tables.
  - `CodexDock/State/DockStore.swift` - owns multi-host Dock stream lifecycle.
  - `CodexDock/State/ArchiveStore.swift` - owns the current direct archived
    list path and must converge to the state-engine view contract.
  - `docs/CODEX_DOCK_GOALS_2026-05-29.md` - defines the runtime completion
    boundary as app-server-exposed truth, with disk/SQLite as explicit audit.

- Canonical path / owner to reuse:
  - `scripts/dock-relay.mjs` remains the relay process boundary.
  - New `scripts/dock-relay-state-store.mjs` should own schema, migrations,
    transactions, and row-level writes.
  - New `scripts/dock-relay-state-engine.mjs` should own lifecycle,
    collectors, reconciliation scheduling, view materialization, and
    subscription sequence.
  - New `scripts/dock-relay-state-ingest.mjs` should own hot row mutations from
    relay-owned command responses, opened detail/live notifications, and stale
    scope marking. It must not depend on a global notification feed.
  - New `scripts/dock-relay-state-views.mjs` should own Dock/Archive/Agents/
    Activity/detail query projections.
  - New `scripts/dock-relay-state-subscriptions.mjs` should own bounded
    snapshot/delta/resync semantics.
  - New `scripts/dock-relay-state-explain.mjs` should own explain/debug
    projections over runtime and audit state.

- Adjacent surfaces tied to the same contract family:
  - `README.md` - replace text that says the relay keeps the current session
    table warm and persists the last-good table under `.codex-dock/`.
  - `scripts/dock-relay-constants.mjs` - remove old session-table constants and
    add state DB, budget, reconciliation, cache, and window constants.
  - `scripts/dock-relay.test.mjs`,
    `scripts/dock-relay-state-snapshot.test.mjs`,
    `scripts/dock-relay-state-parity.test.mjs`,
    `scripts/dock-relay-observability.test.mjs`, and
    `scripts/dock-relay-phase5.test.mjs` - update from aggregator/JSON
    expectations to state-engine behavior.
  - `CodexDock/AppServer/AppServerMethods.swift` - add the
    `state/query/subscribe` method family when Archive or future state views
    move onto the shared relay contract.
  - `CodexDock/AppServer/DockStreamDTO.swift` - add explicit window/completeness
    fields before any partial snapshot is sent.
  - `CodexDock/State/DockSessionTable.swift` and `DockStore.swift` - keep
    sequence semantics but reject incompatible partial snapshots unless the DTO
    marks them as windowed.
  - `CodexDock/State/ArchiveStore.swift` - stop using direct archived
    `thread/list` for normal Archive rows once Archive is a state-engine view.
  - `CodexDock/State/HostSettingsStore.swift` - stop using direct active
    `thread/list` row count as host proof once state/status health exists.
  - `CodexDock/State/ScriptedDockStreamClient.swift`,
    `CodexDock/Features/Dock/DockViewPreview.swift`, and
    `CodexDockTests/DockStoreTestSupport.swift` - update DTO fixtures to match
    the final stream contract.

- Compatibility posture (separate from `fallback_policy`):
- Clean hard cutover for relay internals. No runtime bridge keeps
  `DockSessionAggregator` or the JSON table alive.
- Preserve existing `dock/subscribe`, `dock/update`, and `dock/resync` method
  names long enough to avoid needless app shell churn, but change their
  implementation to state-engine reads only.
- Break/extend DTOs only when needed for explicit windowing. The relay must
  fail loudly rather than send partial data to a legacy client that treats it
  as complete.
- Composer 2.5 Fast alignment is a planning gate before implementation. It is
  not a Phase 7 implementation-audit option.

- Existing patterns to reuse:
  - `relay/state/snapshot` scope drain and canonical projection logic.
  - `UpstreamConnectionPool` labels and request initialization.
  - `RelayObservability` route-health records and bounded bundle pattern.
  - Swift `DockSessionTable` epoch/baseSeq/seq resync reducer.
  - Existing `rtk npm run test:relay` and focused Swift test filters.

- Duplicate or drifting paths relevant to this change:
  - `DockSessionAggregator` vs `relay/state/snapshot` vs raw `thread/list`.
  - Swift Dock stream vs Swift Archive direct list path.
  - live status `ps` endpoint discovery vs host-service/explicit endpoint
    ownership.
  - route self-test as health read vs route self-test as app-state mutator.

- Behavior-preservation signals already available:
  - `rtk npm run test:relay`.
  - `rtk swift test --filter DockStoreTests`.
  - `rtk swift test --filter ThreadDetailStoreTests`.
  - `rtk swift test --filter AppServerClientTests`.
  - `rtk make dock-relay-status` and `rtk make relay-doctor` for service-level
    checks after implementation.

Research pass result:

- The canonical owner is the relay process, not Codex itself and not the Swift
  client.
- The current code already contains the two halves we need to converge:
  `dock-relay-session-table.mjs` is the runtime path to delete, and
  `dock-relay-state-snapshot.mjs` is the scope-drain logic to reuse.
- The cleanest storage implementation is built-in SQLite with a startup
  runtime check, not a new native dependency and not another JSON file.

## 3.3 Decision gaps that must be resolved before implementation

- none
<!-- arch_skill:block:research_grounding:end -->

<!-- arch_skill:block:current_architecture:start -->
# 4) Current Architecture (as-is)

## 4.1 On-disk structure

- `.codex-dock/dock-session-table.json` is the current last-good whole-table
  Dock persistence file.
- `.codex-dock/observability/` stores bounded route-health evidence.
- `.codex-dock/service.env`, `.codex-dock/host.env`, service logs, and token
  files belong to service runtime, not state materialization.
- Codex's own `$CODEX_HOME` and SQLite DBs are outside the relay and are audit
  sources only.

## 4.2 Control paths (runtime)

Current Dock path:

```text
iOS DockStore
  -> AppServerDockStreamClient
  -> dock/subscribe
  -> DockSessionAggregator.snapshot()
  -> refreshNow()
  -> thread/list active explicit sourceKinds + thread/list active default
  -> live status overlay
  -> normalize rows
  -> write .codex-dock/dock-session-table.json
  -> return complete snapshot
```

Current update path:

```text
setInterval(5000ms)
  -> DockSessionAggregator.refreshNow()
  -> full source drain
  -> whole-table diff
  -> dock/update delta or heartbeat
```

Current Archive path:

```text
iOS ArchiveStore
  -> AppServerDockClient.loadSessions(query: archivedHuman)
  -> thread/list archived:true
  -> Swift projection
```

Current Detail path:

```text
iOS ThreadDetailStore
  -> AppServerThreadDetailSession
  -> relay thread/read + thread/turns/list + thread/resume
  -> relay routes to history or live endpoint
```

Current audit path:

```text
relay/state/snapshot
  -> app-server scope drains
  -> optional thread/read
  -> optional thread/turns/list full drain
  -> one snapshot response
```

## 4.3 Object model + key abstractions

- `DockSessionAggregator` is the current production state owner for Dock.
- `DockSessionTable` in Node is an in-memory table with epoch/seq and freshness.
- `DockSessionTable` in Swift is the stream reducer.
- `LiveStatusCache` discovers loopback endpoints through `ps`, calls
  `thread/loaded/list`, validates rows with `thread/read`, and feeds
  `SessionRouter`.
- `ThreadSummaryCache` decorates list rows and warms summaries from turns.
- `RelayObservability` owns route-health records and bounded traces.

## 4.4 Observability + failure behavior today

- `/readyz` proves process liveness only.
- `/statusz` and `/routesz` expose route health.
- `/selftestz` currently treats `dock/subscribe` specially by calling the
  aggregator snapshot path, which can refresh app state.
- Failed Dock refreshes leave stale rows visible through the last-good table.
- Slow clients can be sent a full snapshot when `bufferedAmount` exceeds
  `DOCK_SESSION_CLIENT_BUFFER_LIMIT_BYTES`.
- JSON-RPC max payload is `512MB`, which is too high to be a design budget.

Deep-dive pass 1 conclusion: the broken part is not only persistence. The bad
shape is that source collection, view projection, persistence, subscription,
and diagnostics all meet inside the request-adjacent session-table owner. The
replacement must therefore cut the owner path, not only swap JSON for SQLite.

## 4.5 UI surfaces (ASCII mockups, if UI work)

This plan is not a visual redesign. The user-visible state contract is:

```text
Dock      active app-visible rows, never archived rows
Archive   proven archived rows
Agents    spawned/source grouping over runtime evidence
Activity  activity view over materialized thread/message/live facts
Detail    opened-thread complete app-server detail drain or explicit stop point
```
<!-- arch_skill:block:current_architecture:end -->

<!-- arch_skill:block:target_architecture:start -->
# 5) Target Architecture (to-be)

## 5.1 On-disk structure (future)

Primary runtime state:

```text
.codex-dock/relay-state.sqlite
.codex-dock/relay-state.sqlite-wal
.codex-dock/relay-state.sqlite-shm
```

Diagnostic exports only:

```text
.codex-dock/debug-bundles/*.json
.codex-dock/observability/*
```

Deleted as production state:

```text
.codex-dock/dock-session-table.json
```

Core SQLite tables:

- `schema_migrations`
- `hosts`
- `threads`
- `thread_field_provenance`
- `sync_scopes`
- `live_leases`
- `spawn_edges`
- `goals`
- `turn_cache`
- `subscriptions`
- `changes`
- `conflicts`
- `audit_runs`
- `audit_findings`

The `threads` table is the canonical row per `(host_id, thread_id)`. It stores
app-server-exposed identity, lifecycle, archive state, source/origin, repo/cwd,
branch, status, live overlay summary, sort timestamps, freshness,
completeness, and compact current projection fields. Raw full source payloads
do not become permanent product state.

`turn_cache` is a bounded LRU for recently opened detail pages. It is not a
durable full-turn mirror.

## 5.2 Control paths (future)

State-engine startup:

```text
relay start
  -> open SQLite
  -> PRAGMA journal_mode=WAL
  -> run migrations
  -> create RelayStateEngine
  -> start hot lease validation
  -> schedule warm reconciliation
  -> expose routes only after DB is ready
```

Dock subscribe path:

```text
dock/subscribe
  -> RelayStateEngine.subscribe(view: dock)
  -> SQL view read
  -> bounded snapshot or explicit windowed snapshot
  -> changes seq recorded in subscriptions
```

Warm reconciliation path:

```text
boot/reconnect/resync/archive command/sequence gap
  -> drain app-server scopes using relay/state/snapshot collector logic
  -> transactionally upsert source rows
  -> update sync_scopes generation/completeness
  -> emit row-level changes
```

Hot path:

```text
relay-owned command responses + open live/detail notifications + live validation
  -> row-level state mutations
  -> coalesced changes
  -> dock/update or future state/query/subscribe updates
```

This hot path deliberately does not assume a global all-thread notification
feed. If app-server later exposes one, it can plug into `NotificationIngestor`,
but the implementation plan must work with the surfaces already present in this
repo: command responses, open live/detail upstream events, validated loaded
lists, and warm reconciliation.

Cold audit path:

```text
explicit audit command/script
  -> read runtime SQLite projection
  -> read app-server exhaustive snapshot and/or Codex disk/SQLite
  -> write audit_runs/audit_findings
  -> expose audit report
```

## 5.3 Object model + abstractions (future)

- `RelayStateStore`
  - Opens SQLite.
  - Owns migrations.
  - Exposes transaction helpers.
  - Exposes typed row upserts, deletes, and query methods.
  - Emits monotonic `changes` rows inside the same transaction as state writes.

- `RelayStateEngine`
  - Owns collector scheduling, materialization, subscription hub, and engine
    lifecycle.
  - Starts only after `RelayStateStore` is ready.
  - Is the only production owner used by `dock/*` view routes.

- `AppServerCollectors`
  - Reuse scope drain, repeated-cursor detection, archive separation, source
    separation, field projection, and turn drain logic from
    `dock-relay-state-snapshot.mjs`.
  - Write row-level facts to `RelayStateStore`.

- `LiveLeaseCollector`
  - Uses explicit configured upstream endpoints and `UpstreamConnectionPool`.
  - Calls `thread/loaded/list` and validates candidates with `thread/read`.
  - Writes expiring `live_leases`.
  - Does not scan `ps` as correctness.

- `NotificationIngestor`
  - Ingests notifications already seen on relay-owned live/detail upstream
    connections.
  - Ingests command responses that mutate thread state.
  - Coalesces by `(host_id, thread_id)`.
  - Marks scopes stale and schedules warm reconciliation when the live source
    disconnects.
  - Does not require or invent a global notification API that the current
    app-server contract does not expose.

- `StateReconciler`
  - Owns boot, reconnect, command-completion, archive-mutation, sequence-gap,
    explicit-resync, and periodic reconciliation scheduling.
  - Uses relay constants for cadence and scope budgets.
  - Runs slower periodic scope checks than the old five-second whole-table
    crawl, because hot ingest and explicit invalidation carry the immediate
    updates.

- `StateViewQueries`
  - Own SQL projections for Dock, Archive, Agents, Activity, detail metadata,
    and diagnostics.

- `StateSubscriptionHub`
  - Owns `epoch`, `seq`, subscriber window, change retention, coalescing, lag,
    and resync decisions.

- `StateExplain`
  - Explains why a row exists, why it is visible/hidden, which app-server
    surface won each field, and what is unknown, stale, incomplete, or in
    conflict.

## 5.4 Invariants and boundaries

- Runtime authority: app-server.
- Audit authority: Codex disk/SQLite plus explicit app-server exhaustive
  snapshots.
- Relay authority: materialized projection state and freshness/completeness.
- Client authority: presentation state only.
- Compatibility posture: hard internal cutover, method-name preservation only
  where it does not preserve old implementation.
- State-store failure: fail relay startup.
- Migration failure: fail relay startup with a precise DB/schema error.
- Source collector failure: keep previous rows, mark affected scope
  stale/incomplete, and emit freshness changes.
- Subscriber lag: coalesce to bounded snapshot/window or require resync from
  SQLite; never crawl app-server in resync.
- Oversized snapshot: do not send a partial complete-looking table.
- Unknown origin/mode/parentage: expose `unknown` or `unproven`.
- Disk-only thread: audit finding, not normal runtime row.
- Temporary construction during implementation may exist only behind focused
  tests before route dispatch changes. Once a production route reads the state
  engine, the old production route owner must be deleted in the same phase.

## 5.5 UI surfaces (ASCII mockups, if UI work)

The UI should not change shape during the relay cutover. What changes is the
state contract underneath:

```text
Dock row
  title
  host
  status
  source/origin
  live lease if present
  freshness/completeness/conflict flags available for diagnostics

Archive row
  same identity/projection
  archive_state = archived

Detail header
  state-engine metadata first
  app-server detail drain proof
  live owner lease if present
```
<!-- arch_skill:block:target_architecture:end -->

<!-- arch_skill:block:call_site_audit:start -->
# 6) Call-Site Audit (exhaustive change inventory)

## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Relay state | `scripts/dock-relay-session-table.mjs` | `DockSessionAggregator`, `DockSessionTable`, `readLastGood`, `writeLastGoodAtomic`, `handleDockSubscribe` | Owns production Dock state with in-memory table plus whole JSON persistence | Delete/replace with state-engine implementation; no production reads/writes of `.codex-dock/dock-session-table.json` | Removes giant JSON failure point and hot-path source crawl | `RelayStateEngine.subscribeDock`, `RelayStateEngine.resyncView` | `scripts/dock-relay.test.mjs`, new state-engine tests |
| Relay constants | `scripts/dock-relay-constants.mjs` | `DOCK_SESSION_*`, `JSON_RPC_MAX_MESSAGE_BYTES` | Session table constants and huge payload guard | Remove old session constants; add DB path, schema version, WAL/checkpoint, change retention, window, cache, and soft payload budgets | Makes budgets explicit and centralized | `RELAY_STATE_*` constants | relay constants tests if added, relay suite |
| Relay dispatch | `scripts/dock-relay.mjs` | `handleRequest` for `dock/subscribe`, `dock/resync`, `relay/state/snapshot` | Dispatches Dock to aggregator and audit snapshot to one-shot builder | Dispatch Dock to state engine; keep audit/export explicit; no source sync in app subscribe | App requests read materialized state | `dock/*` state-backed handlers | `scripts/dock-relay.test.mjs` |
| Relay lifecycle | `scripts/dock-relay.mjs` | `startServer`, `close` | Starts live cache and upstream pool; aggregator lazy-starts | Initialize DB/state engine before accepting WebSockets; close engine cleanly | Fail loud and avoid lazy hidden state owner | `config.stateEngine` | relay lifecycle tests |
| Source access | `scripts/dock-relay-thread-data.mjs` | `aggregateThreadList`, `threadSummaryCacheForConfig`, `collectLiveRows`, `discoverLoopbackEndpoints` | List reads decorate summaries and live discovery scans `ps` | Split raw app-server reads from materialization; remove `ps` correctness; explicit live endpoints only | Source reads should not mutate unrelated caches; live routing must be explicit | `AppServerCollectors`, `LiveLeaseCollector` | relay thread-data/phase5 tests |
| Summary cache | `scripts/dock-relay-thread-summary-cache.mjs` | `ThreadSummaryCache`, `warmRows`, `decorateRows` | List reads can trigger summary warming/decoration outside the state engine | Remove from hot list/read path; either retire it or re-home bounded summary materialization under state-engine `turn_cache` in Phase 3 | Prevents a second turn-adjacent cache from living outside SQLite ownership | no summary warming in source collector; optional state-engine summary materializer | relay summary/state tests |
| Snapshot collector | `scripts/dock-relay-state-snapshot.mjs` | `buildRelayStateSnapshot` and helpers | Builds one audit snapshot object | Extract reusable collector/projection helpers used by warm reconciliation; keep method audit-only | Reuse proven scope logic without whole-object runtime | `drainThreadListScope`, canonical field winner helpers | state snapshot/parity tests |
| Hot ingest | `scripts/dock-relay-state-ingest.mjs` | new `NotificationIngestor` | No central owner today; command responses and live/detail events are handled near route code | Ingest command responses, archive mutations, opened detail/live notifications, and stale-scope markers into SQLite row mutations | Keeps immediate state updates out of source collectors and subscriptions | `NotificationIngestor` | relay command/state tests |
| Reconciliation scheduler | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-constants.mjs` | new `StateReconciler`, `RELAY_STATE_*_INTERVAL_MS` | Aggregator refreshes the whole table every 5000ms | Schedule boot, reconnect, explicit resync, command completion, archive mutation, sequence-gap, and slower periodic scope reconciliation | Removes the old hot-loop bottleneck while keeping state eventually checked | `StateReconciler` | relay scheduler/state tests |
| Live leases | `scripts/dock-relay-live-status-cache.mjs` | `LiveStatusCache`, `SessionRouter` | Maintains memory rows from discovered loopback app-servers | Replace or wrap with SQLite-backed `live_leases`; route commands by validated lease | Live state becomes queryable and explainable | `LiveLeaseCollector`, `StateSessionRouter` | `scripts/dock-relay-phase5.test.mjs` |
| Observability | `scripts/dock-relay-observability-contract.mjs` | `ROUTE_NAMES`, probe safety | Route health only | Add state health route names and probe safety for `/statez`, `/syncz`, `/subscriptionsz`, `/dbz`, `/explainz` | Health reads same state as app | extended observability contract | observability tests |
| Self-test | `scripts/dock-relay.mjs` | `runSelfTest` | Can call aggregator snapshot for `dock/subscribe` | Change to read route/state health only; no source sync or writes | Diagnostics must not mutate app state | `/selftestz` passive contract | observability tests |
| Status/bundle | `scripts/dock-relay-status.mjs`, `scripts/dock-relay-diagnostics.mjs` | status and bundle builders | Runtime snapshot is sockets/live cache | Include DB generation, sync scope freshness, subscription lag, state counts, WAL/db health | Debug future issues without custom one-off probes | state-backed status sections | observability/diagnostics tests |
| Swift DTO | `CodexDock/AppServer/DockStreamDTO.swift` | `DockStreamUpdateDTO` | Snapshot means complete replacement; no window metadata | Add explicit `complete`, `totalRows`, `window`, `view`, `stateGeneration`, and maybe provenance summary fields before sending partial windows | Prevent silent partial table | versioned Dock stream DTO | `AppServerClientTests`, `DockStoreTests` |
| Swift methods | `CodexDock/AppServer/AppServerMethods.swift` | `dockSubscribe`, `dockUpdate`, `dockResync` | Dock-only stream names | Preserve names for Dock; add `state/query/subscribe` for Archive and future shared state views | Avoid needless Dock method churn while giving non-Dock views one explicit contract | state-backed methods | AppServerClientTests |
| Swift reducer | `CodexDock/State/DockSessionTable.swift` | `applySnapshot`, `applyUpdate` | Reduces complete snapshots and deltas | Understand window metadata or reject partial snapshots; keep epoch/seq gap behavior | Client correctness under bounded transport | explicit window/resync semantics | DockStoreTests |
| Swift Dock | `CodexDock/State/DockStore.swift` | stream lifecycle | Opens per-host Dock stream | Keep stream lifecycle; consume new DTO fields; expose freshness/completeness diagnostics | Client should not infer relay truth | state-backed Dock stream | DockStoreTests |
| Swift Archive | `CodexDock/State/ArchiveStore.swift`, `CodexDock/State/AppServerDockClient.swift` | `loadSessions(.archivedHuman)` | Direct archived thread/list path | Move Archive to `state/query/subscribe` with `view: archive` | Archive should share same state truth as Dock | `state/query/subscribe` | DockStoreTests/Archive tests |
| Archive commands | `CodexDock/State/DockStore.swift`, `CodexDock/State/ArchiveStore.swift`, `CodexDock/State/AppServerDockClient.swift`, `scripts/dock-relay.mjs`, `scripts/dock-relay-thread-data.mjs` | `archive(_:)`, `restore(_:)`, `thread/archive`, `thread/unarchive` | Commands mutate Codex, then clients refresh through current paths | Route command completion through state engine: update affected `archive_state`, invalidate active/archive scopes, and emit state changes | Prevents stale Dock/Archive rows after hard cutover | command mutation -> state invalidation contract | DockStoreTests, relay command tests |
| Thread detail | `CodexDock/State/AppServerThreadDetailSession.swift`, `CodexDock/State/ThreadDetailStore.swift` | detail read/resume/turn flow | Proxies through relay to app-server | Keep app-server detail authority; add state-engine metadata/freshness and explicit drain stop markers | Detail proves opened-thread completeness | detail metadata/proof DTO if needed | ThreadDetailStoreTests |
| Host settings diagnostics | `CodexDock/State/HostSettingsStore.swift` | `tester.loadSessions(.activeHuman)` | Host test uses direct active list count | Move to relay status/state health or explicitly state-backed test count | Prevents settings diagnostics from preserving direct list truth as app proof | host test reads `/statusz` or state-backed count | DockStoreTests |
| Scripted/previews | `CodexDock/State/ScriptedDockStreamClient.swift`, `CodexDock/Features/Dock/DockViewPreview.swift`, `CodexDockTests/DockStoreTestSupport.swift` | `DockStreamUpdateDTO` fixtures | Construct old complete snapshots | Update fixtures/previews to final DTO/window fields | Keeps test and preview contract honest | final Dock stream DTO | DockStore tests/previews |
| Tests | `scripts/dock-relay.test.mjs` | aggregator tests | Assert JSON table and aggregator behavior | Replace with state-store migration, collector, materialized view, subscription, and no-hot-crawl tests | Tests follow new owner | state engine test suite | `rtk npm run test:relay` |
| Docs | `README.md`, related docs | service/runbook text | Describes current session table and last-good JSON | Rewrite to state-engine truth; delete stale live docs/comments rather than preserving legacy explanations | No stale product truth | README state-engine runbook | doc readback/status |

## 6.2 Migration notes

Canonical owner path / shared code path:

- `scripts/dock-relay-state-engine.mjs` and
  `scripts/dock-relay-state-store.mjs` become the runtime lifecycle and storage
  owner.
- `scripts/dock-relay-state-ingest.mjs` owns hot row mutations from command
  responses and already-observed upstream events.
- `scripts/dock-relay-state-subscriptions.mjs` owns snapshot/delta/window
  subscription semantics and is called by `RelayStateEngine`.
- `scripts/dock-relay-state-explain.mjs` owns explain/debug projections and is
  called by HTTP diagnostic routes.
- `scripts/dock-relay.mjs` owns process startup and route dispatch only.
- `scripts/dock-relay-state-snapshot.mjs` becomes collector/audit logic, not
  runtime state storage.

Deprecated APIs if any:

- No public method-name deprecation is required for Phase 1 Dock because
  `dock/subscribe`, `dock/update`, and `dock/resync` can remain names.
- The old internal `DockSessionAggregator` API is deleted, not deprecated.

Delete list:

- `DockSessionAggregator` production path.
- Node in-memory `DockSessionTable` production path in
  `scripts/dock-relay-session-table.mjs`.
- `.codex-dock/dock-session-table.json` read/write code.
- `DOCK_SESSION_PERSISTENCE_FILE`, `DOCK_SESSION_REFRESH_INTERVAL_MS`, and
  old JSON table schema constants.
- `ps` discovery as correctness for live owner routing.
- `/selftestz` behavior that calls app-state refresh.
- Tests whose only purpose is old aggregator/JSON behavior.

Adjacent surfaces tied to the same contract family:

- Swift Dock reducer and DTOs must move with relay snapshot/window semantics.
- Archive must move from direct list crawl to state-engine archived view.
- Observability must read state-engine health instead of probing app routes.
- README and goals docs must stay aligned with app-server runtime/disk audit
  boundary.

Compatibility posture / cutover plan:

- Hard internal cutover. The implementation may build new modules under tests,
  but production route dispatch switches once and old runtime code is removed
  in the same cutover phase.
- Existing method names can survive as protocol names. Existing implementation
  cannot survive as fallback.

Capability-replacing harnesses to delete or justify:

- None. This is not an agent-backed feature.

Live docs/comments/instructions to update or delete:

- `README.md` service and Dock stream description.
- Any comments or tests that describe `dock-session-table.json` as production
  state.
- Any docs that say `relay-doctor` or `/selftestz` proves Dock by refreshing
  Dock.

Behavior-preservation signals for refactors:

- `rtk npm run test:relay`.
- `rtk swift test --filter DockStoreTests`.
- `rtk swift test --filter AppServerClientTests`.
- `rtk swift test --filter ThreadDetailStoreTests` when detail DTOs/routes
  change.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Runtime state | `scripts/dock-relay-session-table.mjs` | SQLite state engine | Prevents JSON table and aggregator from remaining as parallel truth | include |
| Audit snapshot | `scripts/dock-relay-state-snapshot.mjs` | Collector helpers write through store | Reuses proven drain logic without giant runtime snapshot | include |
| Archive | `CodexDock/State/ArchiveStore.swift` | State-engine view/query | Prevents archived rows from using a separate truth path | include |
| Live routing | `scripts/dock-relay-live-status-cache.mjs` | Validated SQLite-backed live leases | Prevents `ps` from deciding correctness | include |
| Observability | `scripts/dock-relay-observability-contract.mjs` | State health as route-health extension | Prevents a second diagnostics model | include |
| Full historical turns | `turn_cache` | Bounded opened-thread cache only | Avoids second Codex archive | include |
| Disk/SQLite parity | `scripts/dock-relay-state-parity.mjs` | Explicit audit lane | Keeps disk facts out of runtime rows | include |
| Host settings | `CodexDock/State/HostSettingsStore.swift` | State/status-backed host proof | Prevents host settings from preserving direct list crawls as proof | include |
| Test fixtures/previews | `ScriptedDockStreamClient`, `DockViewPreview`, `DockStoreTestSupport` | Final Dock stream DTO | Prevents tests/previews from encoding old snapshot assumptions | include |

Deep-dive pass 1 conclusion: every surface above is required for hard cutover.
None is optional cleanup, because each one otherwise leaves a second path that
can answer a state question differently from the relay state engine.

Deep-dive pass 2 hardening: the plan must not depend on undocumented Codex
server capabilities. Hot ingest uses currently observed relay-owned traffic and
validated live leases. Warm reconciliation remains the source that confirms
durable list/read state after reconnects, disconnects, or missed events.
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:phase_plan:start -->
# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

Obligation sweep result:

- Runtime state cutover, JSON deletion, aggregator deletion, constants cleanup,
  app route dispatch, minimum DTO/window fields, minimum live-status overlay,
  state-store failure behavior, and README truth sync all belong to Phase 1
  because the cutover is not real unless those move together.
- Advanced DTO/window hardening is Phase 2 because the first Dock slice needs
  an explicit complete/window contract immediately, while broader lag,
  oversized-window, and multi-view budget behavior can be expanded after the
  SQLite owner path is proven.
- Archive/Agents/Activity convergence is Phase 3 because those surfaces depend
  on the state engine but do not need to block the first Dock cutover proof.
- Live command routing is Phase 4 because it replaces a distinct correctness
  flaw and needs focused validation tests. A minimal `live_leases` overlay for
  Dock row status belongs to Phase 1 so live sessions do not regress to
  dormant after the hard cutover.
- Observability is Phase 5 because it must read the new state engine after the
  engine exists.
- Audit parity is Phase 6 because it compares runtime truth against disk/SQLite
  and must not feed runtime rows.
- Cleanup is Phase 7 because it proves no active truth surface still describes
  the retired architecture.

## Phase 1 - Hard-cut Dock stream to SQLite state engine

* Goal:
  Replace the production Dock stream internals with SQLite-backed state in one
  vertical slice and remove the JSON/aggregator runtime path.
* Work:
  Build the minimum complete state engine needed for Dock: DB open/migrate,
  active scope reconciliation, minimal live lease overlay, row projection,
  change sequencing, explicit complete/window DTO fields, `dock/subscribe`,
  `dock/update`, `dock/resync`, fail-loud startup, and old path deletion.
* Checklist (must all be done):
  - Add `scripts/dock-relay-state-store.mjs` with `node:sqlite` open,
    migration, WAL setup, transaction helpers, and schema tables required for
    Dock: `hosts`, `threads`, `thread_field_provenance`, `sync_scopes`,
    `live_leases`, `subscriptions`, `changes`, and `conflicts`.
  - Add `scripts/dock-relay-state-engine.mjs` to own lifecycle, active
    app-server scope reconciliation, and Dock view reads.
  - Add `StateReconciler` scheduling inside the state engine with relay
    constants for boot, reconnect, explicit resync, command completion,
    archive mutation, sequence gap, and slower periodic scope reconciliation.
    Do not recreate the old five-second whole-table loop.
  - Add `scripts/dock-relay-state-subscriptions.mjs` to own sequence numbers,
    subscriber state, coalescing, and snapshot/delta fanout.
  - Add `scripts/dock-relay-state-ingest.mjs` so relay-owned command
    responses, archive command results, opened detail/live notifications, and
    disconnects produce row mutations or stale-scope marks in SQLite.
  - Add `scripts/dock-relay-state-views.mjs` with a Dock projection that
    excludes archived rows by explicit state and preserves app-server active
    order/freshness rules.
  - Add minimum `LiveLeaseCollector` support for Dock row status from
    configured app-server/live endpoints: call `thread/loaded/list`, validate
    candidates with `thread/read`, write expiring `live_leases`, and expose
    live/waiting/needs-input/stale/unknown. This phase does not yet route live
    commands through leases.
  - Define the Phase 1 live endpoint bootstrap explicitly: seed lease checks
    from `config.historyUrl`/`historyBearerToken` and any explicit in-process
    endpoint list passed to the relay config or tests. Do not scan `ps`, do not
    accept phone-supplied live endpoints, and do not require the Phase 4
    host-service/env label surface before Dock cutover.
  - Extract or reuse `relay/state/snapshot` drain logic for active default and
    all-source app-server scopes without returning one giant runtime object.
  - Extend `DockStreamUpdateDTO` in Swift and relay JSON with at least `view`,
    `complete`, `totalRows`, `window`, and `stateGeneration`, and update the
    Swift Dock reducer so it cannot treat a partial table as complete.
  - Add a real serialized-size check before route cutover. If the real Dock
    snapshot is too large, send an explicit windowed snapshot under the new DTO
    contract; do not raise `512MB` into a normal design budget.
  - Wire `scripts/dock-relay.mjs` so `dock/subscribe`, `dock/update`, and
    `dock/resync` read only from `RelayStateEngine`.
  - Wire `thread/archive` and `thread/unarchive` command completion so the
    state engine updates the affected thread's archive state, invalidates
    active/archive scopes, and emits row changes.
  - Remove `ThreadSummaryCache` warming/decoration from `aggregateThreadList`
    and the Dock subscribe/update hot path. Either delete it from runtime or
    leave summary materialization unimplemented until it is re-homed under the
    bounded state-engine `turn_cache` in Phase 3.
  - Make relay startup fail if SQLite initialization or migration fails.
  - Delete production reads/writes of `.codex-dock/dock-session-table.json`.
  - Delete `DockSessionAggregator` as a production runtime path.
  - Remove or replace `DOCK_SESSION_PERSISTENCE_FILE`,
    `DOCK_SESSION_REFRESH_INTERVAL_MS`, and old session-table schema constants.
  - Replace old aggregator tests with state-engine tests for migration,
    active-scope drain, materialized Dock rows, stale/incomplete scope handling,
    sequence gaps, subscriber coalescing, and no source crawl inside subscribe.
  - Update README text that says the relay keeps the current session table warm
    or persists last-good Dock JSON.
* Verification (required proof):
  - `rtk node --check scripts/dock-relay.mjs`
  - `rtk npm run test:relay`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
* Docs/comments (propagation; only if needed):
  - Add one short code comment at the state-store boundary explaining that
    runtime rows are app-server projections and disk/SQLite is audit-only.
  - Update README service path documentation to name
    `.codex-dock/relay-state.sqlite`.
* Exit criteria (all required):
  - `dock/subscribe` cannot call app-server source drain functions directly.
  - `dock/resync` rereads SQLite state or schedules/awaits explicit state-engine
    reconciliation; it does not resurrect the old aggregator path.
  - Boot, reconnect, explicit resync, command completion, archive mutation,
    sequence gap, and periodic reconciliation are scheduled through the state
    engine and constants, not a five-second whole-table loop.
  - No production code reads or writes `.codex-dock/dock-session-table.json`.
  - A fresh relay with an empty DB can reconcile app-server active rows and
    serve Dock from SQLite.
  - A reconciliation failure keeps prior rows and marks affected scope
    stale/incomplete instead of clearing rows or lying.
  - Normal Dock rows exclude proven archived rows.
  - Loaded/live rows show live/waiting/needs-input/stale/unknown from validated
    lease evidence; missing live proof is not represented as dormant.
  - Phase 1 Dock live overlay has an explicit endpoint source. If a live owner
    is not in `config.historyUrl` or the explicit in-process endpoint list, the
    row is unknown/stale until Phase 4 endpoint labels exist; it is not guessed
    through `ps`.
  - Command responses and opened live/detail notifications either mutate
    SQLite rows or mark affected scopes stale for reconciliation.
  - List/subscribe reads do not warm `ThreadSummaryCache`, read turns, or create
    turn-adjacent summary state outside the state engine.
  - The Dock stream always includes explicit complete/window metadata, and the
    Swift reducer rejects any partial snapshot that lacks that contract.
  - Real serialized-size proof exists for the first Dock snapshot/window.
  - Archiving a Dock row removes or marks that row through state-engine changes
    without requiring a direct client-side list crawl.
  - Unarchiving an Archive row updates active/archive state through the same
    state-engine mutation/invalidation path.
  - The old JSON/aggregator tests are replaced by state-engine behavior tests.
* Rollback:
  Stop the relay and revert the phase commit. There is no runtime fallback path.

## Phase 2 - Harden windows, budgets, and lag behavior across views

* Goal:
  Expand the Phase 1 Dock complete/window contract into a reusable bounded
  transport policy so no current or future state view can force giant
  complete-looking snapshots.
* Work:
  Harden payload budgets, subscriber lag handling, missed-sequence resync, and
  reusable window semantics for Dock and the shared state view contract.
* Checklist (must all be done):
  - Tune relay constants for normal snapshot soft budget, update soft budget,
    change retention, window size, and slow-client coalescing in
    `scripts/dock-relay-constants.mjs`.
  - Generalize the Phase 1 `view`, `complete`, `totalRows`, `window`, and
    `stateGeneration` fields so shared state views can reuse them.
  - Update relay subscription code so every state view sends full snapshots
    only under budget and explicit windows otherwise.
  - Add resync behavior for missed sequences that reads from SQLite, not
    app-server.
  - Add tests for oversized snapshots, windowed snapshots, legacy-client
    rejection/fail-loud behavior, subscriber lag, and coalesced updates.
* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
* Docs/comments (propagation; only if needed):
  - Document the Dock stream window contract in README only if the operator
    needs to understand partial rows during debugging.
* Exit criteria (all required):
  - The relay never sends a partial table that an old client would treat as a
    complete table.
  - Full snapshots over budget become explicit windows or fail loudly for every
    state-backed view, not only Dock.
  - Swift tests prove snapshot/delta/window/sequence semantics.
  - `512MB` remains only a guardrail, not the ordinary design target.
* Rollback:
  Revert this phase with Phase 1 still using explicit Dock complete/window
  metadata. Do not reintroduce JSON persistence.

## Phase 3 - Converge Archive, Agents, Activity, and pinned/detail metadata views

* Goal:
  Stop app-facing surfaces from using separate list/projection truth paths.
* Work:
  Add state-engine views for Archive, Agents, Activity, and detail metadata;
  move Swift Archive off direct `thread/list archived:true`; keep local pinned
  metadata as client presentation state. Agents and Activity are relay
  view/query contracts in this phase; adding visible Swift tabs for them is
  out of scope until client work explicitly asks for those surfaces.
* Checklist (must all be done):
  - Extend reconciliation to active and archived app-server scopes.
  - Add `archive_state`, `origin`, `spawn_edges`, `goals`, and activity fields
    needed by Archive, Agents, Activity, and detail headers.
  - Add Archive view query and the `state/query/subscribe` contract with
    `view: archive`.
  - Update `ArchiveStore` to consume `state/query/subscribe` for Archive instead
    of `AppServerDockClient.loadSessions(.archivedHuman)`.
  - Add Agents grouping over app-server-exposed spawn/source/fork evidence and
    mark parentage `unproven` when runtime evidence is missing.
  - Add Activity projection from thread timestamps, hot notifications,
    bounded `turn_cache`, and live leases without full durable turn mirror.
  - Add bounded `turn_cache` creation/population for opened detail pages,
    including cache byte/thread limits and eviction that never changes whether
    app-server can be queried for full detail.
  - Update `AppServerThreadDetailSession`, `ThreadDetailStore`, and any detail
    DTOs needed so opened-thread drains expose `complete`, cursor exhaustion,
    and exact stop/error point.
  - Add state-engine detail metadata/freshness to the detail header without
    making relay SQLite the durable turn-history authority.
  - Keep `LocalThreadMetadataStore` as client-owned presentation metadata and
    do not mix it into relay runtime truth.
  - Update `HostSettingsStore` to use state/status-backed host proof instead
    of direct active list count.
  - Update scripted stream clients, Dock previews, and test fixtures for the
    final Dock stream DTO fields.
  - Update tests for Archive exclusion/inclusion, spawned grouping, activity
    sort source, detail drain completeness/stop markers, pinned metadata
    preservation, host settings proof, DTO fixtures, and multi-host identity.
* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - Archive-focused Swift tests if they exist or focused `DockStoreTests` cases
    that cover Archive integration.
* Docs/comments (propagation; only if needed):
  - Update README Archive/Dock descriptions to say both are state-engine views.
* Exit criteria (all required):
  - Dock and Archive cannot disagree because one used active list and the other
    used a separate direct archived list path.
  - Archive rows are included only with proven archived state.
  - Agents grouping is evidence-backed or marked unproven.
  - Activity does not require durable mirroring of all turn items.
  - Opened detail views expose app-server turn-drain completeness or the exact
    stop/error point.
  - `turn_cache` is bounded and cannot become a durable full-history mirror.
  - Host settings no longer use direct list crawling as app-path proof.
  - Scripted/previews/tests construct the final stream DTO contract.
  - Client local metadata remains presentation-only.
* Rollback:
  Revert this phase and keep Phase 1/2 Dock state-engine cutover. Do not
  restore the old Dock JSON path.

## Phase 4 - Replace live-owner guessing with validated leases

* Goal:
  Make live routing queryable, explainable, and independent of process-list
  guesses.
* Work:
  Build on the Phase 1 `live_leases` Dock overlay and make leases the command
  routing authority. Replace `ps`-based endpoint discovery as correctness with
  explicit upstream endpoints and SQLite-backed live leases. Route live turn
  commands only through validated leases. Route read-only stored detail reads
  to the history app-server when no live lease exists; that is the normal
  app-server read path, not a compatibility fallback.
* Checklist (must all be done):
  - Add config/env parsing for explicit live upstream endpoint labels.
  - Update `scripts/codex-dock-host-service.mjs` and host-service env output so
    configured live upstream endpoint labels are visible and exact.
  - Update host-service docs/env output so configured live endpoints are visible
    and exact.
  - Expand Phase 1 `live_leases` writes from `thread/loaded/list` plus
    `thread/read` validation into the full routing lease contract.
  - Store lease expiry, endpoint label, backend session ID, active turn ID,
    status, waiting state, command capability, and validation time.
  - Replace `SessionRouter` routing reads with state-engine lease lookup plus
    validation.
  - Remove `discoverLoopbackEndpoints`/`ps` as correctness. If kept at all, it
    must be a manual diagnostic only and never a production lease source.
  - Add tests for lease expiry, stale lease refusal, thread mismatch, live
    detail routing, turn command routing, and explicit unknown when no endpoint
    is registered.
* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk swift test --filter ThreadDetailStoreTests`
* Docs/comments (propagation; only if needed):
  - Update README and service env docs to describe explicit live endpoints and
    unknown-live behavior.
* Exit criteria (all required):
  - No production turn/detail routing decision depends on `ps`.
  - A live command cannot route to an endpoint that has not recently validated
    ownership of the target thread.
  - Missing live owner evidence becomes unknown/stale, not guessed.
  - Read-only detail/history routes may use the history app-server only when
    the request does not require a live lease.
  - Live turn commands fail loudly when no validated lease owns the thread.
  - Existing detail reconnect behavior still passes tests.
* Rollback:
  Revert this phase. Do not reintroduce JSON Dock persistence.

## Phase 5 - Add state-backed observability, explain, and passive self-test

* Goal:
  Make the relay explain the exact state the client sees without causing
  refreshes or mutations.
* Work:
  Add state health routes and wire them into the existing route-health spine.
* Checklist (must all be done):
  - Add `scripts/dock-relay-state-explain.mjs` for explain/debug projections
    over runtime state and audit findings.
  - Add `/statez`, `/syncz`, `/subscriptionsz`, `/dbz`, and
    `/explainz/thread/<threadID>` routes.
  - Extend `scripts/dock-relay-observability-contract.mjs` with probe safety
    for state routes.
  - Update `/statusz` to summarize DB generation, state counts, stale scopes,
    subscription lag, and route health.
  - Update `/bundlez` to include bounded state diagnostics with no secrets, raw
    prompts, transcripts, audio, or full JSON-RPC payloads.
  - Change `/selftestz` so it reads health only and never calls
    `dock/subscribe`, warm reconciliation, or state writes.
  - Add tests that prove diagnostics do not trigger source sync or state writes.
* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk make dock-relay-status` after implementation when services are safe to
    run.
* Docs/comments (propagation; only if needed):
  - Update README diagnostics section and keep `/readyz` as process-only.
* Exit criteria (all required):
  - Operator can see active, archived, live, spawned, stale, incomplete, and
    conflict counts from state routes.
  - `explainz` can say why a row is visible or hidden without running a full
    audit.
  - `/selftestz` is passive.
  - Debug bundles remain bounded and secret-safe.
* Rollback:
  Revert observability additions only. State-engine runtime remains intact.

## Phase 6 - Integrate explicit audit parity without runtime contamination

* Goal:
  Keep the proof power of disk/SQLite audits while preserving app-server-only
  runtime truth.
* Work:
  Make existing parity tooling compare against relay SQLite runtime state and
  record audit findings without changing normal app rows.
* Checklist (must all be done):
  - Update `scripts/dock-relay-state-parity.mjs` to compare app-server
    exhaustive state with relay SQLite rows.
  - Keep Codex disk/SQLite reads in explicit audit commands/scripts only.
  - Add `audit_runs` and `audit_findings` writes for disk-only,
    app-server-readable-but-not-listable, archive mismatch, spawn mismatch,
    goal mismatch, and turn-drain mismatch findings.
  - Expose audit findings through audit-scoped explain/report output.
  - Add tests proving audit findings do not create or mutate normal runtime
    rows.
* Verification (required proof):
  - `rtk npm run test:relay`
  - Real explicit audit command only when requested or when implementation
    reaches final verification.
* Docs/comments (propagation; only if needed):
  - Update goals/worklog docs if audit command names or result shapes change.
* Exit criteria (all required):
  - Runtime rows remain app-server-backed.
  - Disk-only facts appear as audit findings, not normal Dock/Archive rows.
  - Full app-server turn coverage can be audited without persistent full-turn
    mirroring.
  - Audit reports can cross-check the client-visible relay view.
* Rollback:
  Revert audit integration only. Runtime state engine remains intact.

## Phase 7 - Final hard-cut cleanup and generated project verification

* Goal:
  Remove stale live truth surfaces and prove the repo no longer carries the old
  architecture as executable or instructional truth.
* Work:
  Final cleanup of code, tests, docs, constants, generated project state if
  touched, and service runbooks.
* Checklist (must all be done):
  - Remove dead exports, imports, constants, tests, docs text, and comments that
    still present the old JSON/aggregator runtime as live truth.
  - Keep only historical docs/worklogs as passive history when they are clearly
    dated and not current runbook truth.
  - Update `README.md`, `Makefile` help text if needed, and any active
    architecture/goals docs touched by this cutover.
  - Run XcodeGen only if `project.yml` changes.
  - Run the full relevant verification set.
* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk xcodegen generate --spec project.yml` only if `project.yml` changed.
* Docs/comments (propagation; only if needed):
  - Update live docs; do not preserve legacy explanation in current runbook
    paths.
* Exit criteria (all required):
  - The active runbook describes SQLite state engine, not JSON session table.
  - No production import/export path can instantiate the old aggregator.
  - The verification commands required by touched areas pass or have exact
    blockers recorded.
  - The implementation audit can validate each phase without guessing.
* Rollback:
  Revert the cleanup commit only if it accidentally removes live truth. Do not
  restore old runtime code as fallback.

Phase-plan result: this is a hard-cut execution order. Phase 1 must not leave
the old Dock runtime alive; later phases widen the same state engine rather
than preserving the old implementation as a safety net.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. Use existing behavior-level checks first. Add
state-engine tests only where they prove shipped behavior or real contracts.

Do not add tests whose main job is proving deleted strings are absent, policing
folder shape, or auditing docs. Deletion is proven by code review plus the fact
that runtime behavior no longer imports or calls the old path.

## 8.1 Unit tests (contracts)

- SQLite migration and schema tests for `RelayStateStore`.
- Collector tests for paginated drains, repeated cursors, incomplete scopes,
  archive/source separation, and provenance conflict records.
- View-query tests for Dock, Archive, Agents, Activity, and explain outputs.
- Subscription tests for epoch/seq/baseSeq, lag, coalescing, windows, resync,
  and slow clients.
- Live lease tests for validation, expiry, stale refusal, and thread mismatch.

## 8.2 Integration tests (flows)

- `rtk npm run test:relay` remains the main relay proof.
- `rtk swift test --filter AppServerClientTests` for DTO/method changes.
- `rtk swift test --filter DockStoreTests` for client stream reduction.
- `rtk swift test --filter ThreadDetailStoreTests` for detail routing and
  opened-thread completeness behavior.
- `rtk make dock-relay-status` and `rtk make relay-doctor` after implementation
  when services need real process proof.

## 8.3 E2E / device tests (realistic)

- Simulator proof can use `rtk make app SIM='iPhone 17'` or
  `rtk make app-test SIM='iPhone 17'` only when UI/runtime behavior changed.
- Physical iPhone proof is not required for planning and should not use the
  physical phone during this planning work.
- Manual real-host proof after implementation should confirm the app can see
  both configured hosts, stale/offline states remain explicit, and archived
  threads do not appear in normal Dock.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

- This is a hard cutover in a single-user repo.
- The relay must stop on DB migration or `node:sqlite` failure instead of
  falling back to JSON.
- The first implementation pass may create the SQLite DB from app-server
  reconciliation; it does not need to migrate `.codex-dock/dock-session-table.json`.
- Existing generated JSON files can be ignored or manually removed after
  cutover; they are not read as state.
- Home server rollout requires the configured `NODE_BIN` to support
  `node:sqlite`; if not, upgrade Node or fail loudly.

## 9.2 Telemetry changes

- State generation, last successful reconciliation, stale scopes, incomplete
  scopes, conflicts, active/archive/live/spawned counts, subscriber lag, DB
  schema version, WAL state, and DB size become relay telemetry.
- Route health continues to use existing observability vocabulary.
- Logs use `scripts/dock-relay-logger.mjs` and must not include secrets, raw
  prompts, transcript text, audio, or full JSON-RPC payloads.

## 9.3 Operational runbook

- Start services with `rtk make services`.
- Check process/route/state health with:

```bash
rtk make app-server-status
rtk make dock-relay-status
rtk make relay-doctor
```

- Inspect relay logs with:

```bash
rtk make dock-relay-logs
```

- Future debug flow:
  1. `/readyz` proves process liveness only.
  2. `/statusz` proves app route and state health summary.
  3. `/statez` and `/syncz` prove state counts and freshness.
  4. `/explainz/thread/<threadID>` explains a specific row.
  5. Explicit audit commands compare runtime app-server truth with disk/SQLite.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers:
  - explorer 1: frontmatter, TL;DR, Sections 0-2, 7-10, helper drift
  - explorer 2: Sections 3-7, architecture/call-site/phase consistency
  - self-integrator
  - Composer 2.5 Fast final alignment reviewer
- Scope checked:
  - Outcome, requested behavior scope, allowed convergence scope, hard cutover,
    fallback policy, canonical owner paths, required deletes, subscriptions,
    Archive command mutation, detail drain proof, live endpoint ownership,
    observability, audit parity, rollout, and decision log.
- Findings summary:
  - Composer 2.5 Fast was both a required planning gate and a conditional Phase
    7 implementation option.
  - Phase 4's "history fallback when appropriate" wording was incompatible
    with `fallback_policy: forbidden`.
  - Archive command state mutation was required by architecture but missing
    from the call-site audit and Phase 1 checklist.
  - Detail metadata, `turn_cache`, and drain-stop proof were required by target
    architecture but not fully represented in Phase 3 checklist/exit criteria.
  - Subscription and explain/debug module ownership was ambiguous.
  - Live endpoint config remained branchy even though repo evidence says host
    service does not expose a live upstream endpoint list today.
  - Host settings and scripted/previews/test fixtures were adjacent DTO/list
    surfaces that needed disposition.
  - Composer 2.5 Fast later rejected the first aligned draft because Phase 1
    could regress live rows to dormant, `ThreadSummaryCache` had no phase
    owner, hot ingest and reconciliation cadence were architected but not
    phased, Archive still had a branchy contract name, and Agents/Activity
    sounded like immediate Swift UI work.
- Integrated repairs:
  - Made Composer 2.5 Fast alignment a pre-implementation planning gate only.
  - Replaced "history fallback" with precise read-only history routing rules
    and fail-loud live-command lease rules.
  - Added Archive command mutation call-site coverage, Phase 1 checklist items,
    and Phase 1 exit criteria.
  - Added detail metadata, bounded `turn_cache`, opened-thread drain
    completeness/stop markers, and `ThreadDetailStore`/DTO work to Phase 3.
  - Made `scripts/dock-relay-state-subscriptions.mjs` and
    `scripts/dock-relay-state-explain.mjs` explicit owner modules.
  - Made live upstream endpoint config/env parsing required in Phase 4.
  - Added HostSettings and scripted/previews/test fixtures to adjacent-surface
    coverage and Phase 3.
  - Moved minimum live lease overlay, explicit Dock complete/window fields,
    serialized-size proof, `ThreadSummaryCache` hot-path removal, hot ingest,
    and reconciliation scheduling into Phase 1.
  - Chose `state/query/subscribe` as the Archive and future shared state-view
    contract.
  - Clarified that Phase 3 Agents/Activity are relay contracts only, not
    immediate Swift tab work.
  - Added Phase 1 live endpoint bootstrap from `config.historyUrl`,
    `historyBearerToken`, and explicit in-process endpoint config; missing
    proof remains unknown/stale and `ps` is not used.
  - Composer 2.5 Fast final pass returned `STATUS: ready`,
    `FOLLOW-UP NEEDED: none`, and `AGREEMENT: yes`.
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

# 10) Decision Log (append-only)

## 2026-05-30 - Hard cutover replaces the JSON relay table

Context

The previous architecture review concluded that the relay should become a
state engine, not an asynchronous version of the old five-second JSON crawl.
The user then explicitly requested an `arch-step auto-plan` hard cutover with
"no legacy" runtime paths left around.

Options

- Keep the old JSON/aggregator path as a fallback while adding SQLite.
- Build SQLite as a second diagnostic copy beside the existing app path.
- Hard-cut production runtime state to SQLite and delete the old path.

Decision

Hard-cut production runtime state to SQLite and delete the old path.

Consequences

Implementation is more invasive, but the relay has one source of runtime
projection truth and cannot drift between JSON, memory, and SQLite answers.

Follow-ups

Composer 2.5 Fast must agree with this plan before implementation is
considered planned.

## 2026-05-30 - Runtime truth remains app-server-backed

Context

Disk and Codex SQLite can prove durable facts that app-server may not expose,
but the app's normal runtime boundary was already defined as
app-server-exposed truth.

Options

- Mix disk/SQLite facts into normal runtime rows to fill app-server gaps.
- Keep disk/SQLite as explicit audit-only evidence.

Decision

Keep disk/SQLite as explicit audit-only evidence.

Consequences

Runtime rows remain honest about app-server boundaries. Disk-only threads and
spawn/goal gaps become audit findings, not silent product rows.

Follow-ups

Audit commands must be able to compare the runtime view with disk/SQLite
without mutating normal app rows.

## 2026-05-30 - Use built-in SQLite when runtime supports it

Context

Local Node is `v25.9.0`, and `node:sqlite` imports successfully. Adding a
native npm SQLite dependency would add install and cross-host friction.

Options

- Use `node:sqlite`.
- Add a native npm SQLite dependency.
- Keep JSON persistence.

Decision

Use `node:sqlite` for the planned state store, and fail relay startup with an
exact runtime error if the configured host Node cannot import it.

Consequences

The relay stays dependency-light, but host runtimes must be modern enough.

Follow-ups

Implementation must check home/server Node support before deployment and update
service runbooks if a Node upgrade is required.

## 2026-05-30 - Consistency pass repairs before Composer alignment

Context

Two arch-step cold readers found that the plan was directionally right but not
yet decision-complete.

Options

- Treat the findings as non-blocking and proceed to Composer review.
- Repair the main artifact first, then run Composer against the corrected plan.

Decision

Repair the main artifact first.

Consequences

Composer alignment will review the actual final planning contract: Composer is
a pre-implementation planning gate; live turn commands require validated
leases; read-only stored detail may use the history app-server as the normal
read path; Archive command mutation, detail drain proof, subscriptions, explain
routes, live endpoint config, HostSettings, and scripted/previews all have
explicit owner-path and phase coverage.

Follow-ups

Run the arch-step receipt gate, then run Composer 2.5 Fast alignment.

## 2026-05-30 - Composer blocker repairs before final alignment

Context

Composer 2.5 Fast agreed with the core state-engine direction but rejected the
draft because several correctness obligations were still stranded outside the
phase plan.

Options

- Treat those issues as implementation details.
- Move the obligations into explicit phase checklists and exit criteria before
  asking Composer for final agreement.

Decision

Move them into the plan before final alignment.

Consequences

Phase 1 now includes minimum live lease overlay for Dock status, explicit
endpoint bootstrap from `config.historyUrl` plus any in-process configured
endpoints, explicit Dock complete/window metadata, real serialized-size proof,
hot ingest, reconciliation scheduling, and `ThreadSummaryCache` removal from
the hot list path. Phase 3 uses the single `state/query/subscribe` contract for
Archive and future shared state views, while Agents/Activity remain relay
contracts until client UI work explicitly asks for visible surfaces.

Follow-ups

Run the arch-step ready gate again and re-run Composer 2.5 Fast. The plan is
not done until Composer returns agreement.

## 2026-05-30 - Composer final alignment reached

Context

After the Phase 1 live endpoint bootstrap repair, Composer 2.5 Fast performed
a final read-only review of the full architecture plan.

Options

- Proceed with the plan as implementation-ready.
- Treat remaining concerns as blockers and revise again.

Decision

Proceed with the plan as implementation-ready.

Consequences

Composer returned `STATUS: ready`, `BLOCKERS: none`,
`FOLLOW-UP NEEDED: none`, and `AGREEMENT: yes`. The plan is now ready for a
future implementation request; no source code was changed during planning.

Follow-ups

Do not implement until explicitly asked.
