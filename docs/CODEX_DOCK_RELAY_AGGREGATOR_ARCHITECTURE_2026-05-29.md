---
title: "Codex Dock - Relay Aggregator Session Table - Architecture Plan"
date: 2026-05-29
status: active
fallback_policy: forbidden
owners: [Amir]
reviewers: [GPT-55X-High, Opus 48 Max]
doc_type: phased_refactor
related:
  - docs/CODEX_DOCK_HOME_REFRESH_NOT_LOADED_ROOT_CAUSE_2026-05-29.md
  - docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md
  - .arch_skill/model-consensus/dock-relay-aggregator-architecture-20260529T194433Z/
  - scripts/dock-relay-thread-data.mjs
  - scripts/dock-relay-live-status-cache.mjs
  - scripts/dock-relay-phase5.test.mjs
  - CodexDock/State/DockStore.swift
  - CodexDock/State/AppServerDockClient.swift
  - CodexDock/AppServer/ThreadListDTO.swift
  - CodexDock/Models/SessionSummaryMapper.swift
---

# TL;DR

Outcome: Dock Home moves to a relay-owned, provider-agnostic session-table stream. Each configured relay host sends a full `hosts[]` + `sessions[]` snapshot first, then ordered deltas, and the iPhone only applies snapshots/deltas, resyncs on gaps, unions normalized tables, and renders.

Problem: today's client calls raw Codex-shaped `thread/list`, fans out across hosts and scopes, decodes provider status/source fields, and publishes destructive partial snapshots. Slow Home refreshes can temporarily show zero Home rows, and Codex `notLoaded` leaks into the product as a confusing visible row status.

Approach: make the relay the stateful aggregator for each host. The relay owns provider adapters, live/history merge, status normalization, last-good atomic JSON persistence, stale-while-refresh semantics, and the clean `dock/*` wire protocol. The client does not decode Codex list rows or runtime concepts.

Plan: build the protocol, relay session table, last-good persistence, and fake-provider proof first; add the Codex adapter; add the Swift stream client/reducer; cut Dock Home over; prove the behavior in simulator; delete the old Home list path; then run physical-device and docs cleanup.

Non-negotiables: no raw `notLoaded` on the Dock Home wire; no destructive row clearing on slow or failed refresh; no provider-specific source/status decoding in the client; no runtime shims or permanent dual Home paths; simulator proof is primary client completion evidence.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-29
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-29
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:bfb660831fec35a74f6a3e827e7f2bd2b75c9e06cd16f367b940ac68b10e54ba",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-29T20:05:51Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:aa1f1858e5fb70ab76d3818953875515cba0e0f243091bd1bd5723fdc9236ba5",
      "completed_at": "2026-05-29T20:05:57Z",
      "doc_hash_after": "sha256:77cbcbe8d5354de54e693b00864221871bb665e5b522006df41c10fdbb561250"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T20:06:03Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:77cbcbe8d5354de54e693b00864221871bb665e5b522006df41c10fdbb561250",
      "completed_at": "2026-05-29T20:06:09Z",
      "doc_hash_after": "sha256:b109ad0c356602629a318282708a0f8f75629700bb35c378ebe5a4efb3a45533"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T20:06:13Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:b109ad0c356602629a318282708a0f8f75629700bb35c378ebe5a4efb3a45533",
      "completed_at": "2026-05-29T20:06:20Z",
      "doc_hash_after": "sha256:2f48e49dd44dcbfdc03c88ec1eae9bbcbb6922ebc0397e1bd082645edd1b54bc"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-29T20:06:24Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:2f48e49dd44dcbfdc03c88ec1eae9bbcbb6922ebc0397e1bd082645edd1b54bc",
      "completed_at": "2026-05-29T20:06:35Z",
      "doc_hash_after": "sha256:321c16b7bc5ad4d65cf86632f145119939603bb7ae38cb1ee763c4f642aac590"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-29T20:06:47Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:321c16b7bc5ad4d65cf86632f145119939603bb7ae38cb1ee763c4f642aac590",
      "completed_at": "2026-05-29T20:13:09Z",
      "doc_hash_after": "sha256:c9e2207aae57096838bc9dbca6a257355c3b3c5fc6231fb3fa7a0a4038ed8827"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this plan is implemented, Dock Home will no longer call raw `thread/list`
for its primary list, will no longer expose raw Codex `notLoaded` as a row
status, and will retain last-known rows when a relay host is slow, stale,
offline, or restarting. A simulator run with a scripted fake relay must prove
that selected Home rows do not drop to zero during slow, stale,
offline/disconnected, reconnect, and resync states while another host continues
updating.

## 0.2 In scope

- New relay-owned `dock/subscribe`, `dock/update`, and `dock/resync` contract.
- Per-host relay `SessionTable` with `epoch`, `seq`, `asOf`, freshness, host
  metadata, and normalized session rows.
- Relay `SyncLoop` that polls provider adapters, merges base/history rows with
  live runtime state, normalizes status/lane/source, diffs rows, and emits
  ordered deltas.
- Last-good normalized table persistence using atomic JSON under `.codex-dock/`.
- Codex provider adapter built from current relay pieces.
- Swift Dock Home stream client, reducer/table store, and mapping into existing
  Dock presentation.
- Deleting or retiring old Dock Home raw `thread/list`, scope fan-out,
  dedupe/conflict, `liveOverlay`, and `notLoaded` product-state paths once the
  new path is simulator-proven.
- Scripted fake relay/simulator hooks needed to prove slow/stale,
  offline/disconnected, reconnect, and resync behavior deterministically.
- Relay and Swift tests that protect the new provider-agnostic wire contract.
- Preserving existing raw detail/control/archive/voice and other non-Home
  flows as explicit non-Home contracts for this plan.

## 0.3 Out of scope

- Implementing the plan in this planning pass.
- Building a coordinator/federation relay in V1.
- Adding Claude Code support in V1; the adapter boundary must allow it later.
- SQLite, persistent event sourcing, CRDTs, message buses, or cross-reconnect
  delta replay logs.
- Renaming all existing `thread/*` methods to `session/*` now.
- Reworking the entire thread detail/event UI.
- Replacing physical device testing with unit tests.
- Introducing runtime fallbacks that keep two permanent Dock Home data paths.

## 0.4 Definition of done (acceptance evidence)

- Relay tests pass with `rtk npm run test:relay`.
- Swift contract tests pass for the new stream DTO/reducer path with the
  smallest relevant `rtk swift test --filter ...` command once concrete test
  ownership exists.
- Generated-project simulator tests run with `rtk make app-test SIM='iPhone 17'`.
- The app launches with `rtk make app SIM='iPhone 17'`.
- Simulator logs from `rtk make sim-logs SIM='iPhone 17'` show:
  - Dock Home subscribing through `dock/subscribe`.
  - Full snapshot application.
  - Ordered delta application.
  - Resync after a forced sequence gap.
  - Rows retained while a host is stale or reconnecting.
  - Rows retained while a host is offline/disconnected.
  - No Dock Home raw `thread/list` paging path.
- A scripted fake relay proves the slow Home case deterministically.
- Physical install path is exercised with `rtk make iphone-17-pro` when the
  simulator path is green and signing/device state allow it.

## 0.5 Key invariants (fix immediately if violated)

- `notLoaded` is an adapter input only; it is not a valid Dock Home wire status.
- Host connection, table freshness, and row runtime status stay separate.
- Failed or slow sync never clears last-known rows.
- `dock/update` deltas are applied per stream only when `epoch` matches and
  `baseSeq` equals that stream's current accepted snapshot/delta `seq`;
  otherwise that stream resyncs.
- Heartbeats report the stream's current `seq`; they do not advance the delta
  sequence.
- The relay persists normalized last-good state only, not raw provider payloads
  or secrets.
- Phone-side configuration remains host/port bootstrap and relay auth only.
- No OpenAI keys, raw app-server bearer tokens, loopback URLs, or
  `dockRelaySource` values cross the phone wire.
- New timeouts, intervals, ports, page sizes, and caps belong in existing
  constants files, not scattered literals.
- Makefile-owned commands remain the mobile build/install source of truth.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Stable user experience under slow, stale, offline, reconnecting, and restart
   states.
2. Clean provider-agnostic client contract.
3. Relay ownership of provider complexity, freshness, retry/backoff, and
   last-good state.
4. Deterministic simulator proof for the slow/stale/offline/resync cases.
5. Minimal topology: per-host relays in V1, coordinator deferred.
6. Delete superseded Home complexity after the new path is proven.
7. Preserve existing non-Home raw detail/control/archive/voice behavior until
   those flows have their own migration plan.

## 1.2 Constraints

- The app normally connects to the Dock relay on `:4510`, not raw app-server
  `:4500`.
- The repo's canonical commands are in `Makefile`, `Package.swift`,
  `package.json`, and `project.yml`.
- Mobile builds and installs must use `rtk make ...` targets.
- Relay changes under `scripts/dock-relay*.mjs` start with
  `rtk npm run test:relay`.
- Installed UI behavior requires simulator or physical-device evidence; unit
  tests alone do not prove the user experience.
- Physical iPhone configuration stays per-device and host/port based.
- Secrets stay relay-side.
- Runtime shims and fallbacks are forbidden unless explicitly approved and
  timeboxed; no such approval exists for this plan.

## 1.3 Architectural principles (rules we will enforce)

- Use one canonical Dock Home data contract: `dock/*` snapshots/deltas.
- Keep provider adapters behind the relay boundary.
- Keep the client reducer mechanical: snapshot replace, delta apply, resync on
  gap.
- Represent freshness explicitly instead of implying it through row presence.
- Delete or retire old Home code paths when the new path is proven.
- Reuse existing relay logging and constants modules.
- Reuse existing app logging under subsystem `com.aelaguiz.CodexDock`.
- Add comments only at sharp contract boundaries: sequence/gap semantics,
  persisted-table schema, and provider adapter normalization.

## 1.4 Known tradeoffs (explicit)

- Push subscription is more work than polling a cached snapshot, but it directly
  satisfies the incremental update and precise staleness requirement.
- Per-host streams mean the client keeps multiple sockets, but the union is only
  normalized UI composition, not raw provider merge logic.
- Atomic JSON persistence is less flexible than SQLite, but it is enough for V1
  and avoids a database migration before the behavior is proven.
- Preserving existing non-Home raw detail/control/archive/voice APIs is an
  explicit compatibility boundary for this plan, not a Dock Home fallback;
  future migration requires a separate plan.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Dock Home loads rows by asking each configured relay for Codex-shaped
`thread/list` data. The Swift client runs active human and active agent scopes,
pages cursors, maps `ThreadListDTO` into `SessionSummary`, deduplicates scoped
rows, builds `DockSnapshot`, and publishes partial snapshots while other hosts
are still checking.

The relay is in the path, but for `thread/list` it still reads history on the
request path, warms a summary cache, and attaches a `liveOverlay` rather than
owning a durable provider-agnostic Dock table.

## 2.2 What's broken / missing (concrete)

- Slow Home refreshes can temporarily produce a selected-host view with zero
  rows because Home has not completed the current refresh yet.
- `notLoaded` is visible as a Dock row status even though it is a Codex runtime
  memory detail.
- The client must understand Codex status, source kind, agent-vs-human
  classification, cursor paging, `liveOverlay`, and partial failures.
- Future Claude Code support would require Swift changes if the client keeps
  decoding provider-specific list rows.
- The current tests lock in some wrong product contracts, especially "history
  status wins" for list rows.

## 2.3 Constraints implied by the problem

- The relay must serve warm state quickly and refresh in the background.
- Failed refresh must become stale metadata, not an empty list.
- The new contract must be provider-agnostic before the client adopts it.
- The old Home path must be deleted or disabled after cutover, or the app will
  keep two sources of truth.
- The slow Home case must be forceable in simulator; relying on real network
  timing is not good enough.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- Local-first stale-while-refresh UI pattern - adopt the core idea that the UI
  renders last-known-good data while freshness updates separately. Reject using
  browser-style polling as the primary mechanism because this product needs
  incremental updates and explicit resync.
- Sequence-based replication contracts - adopt `epoch`, `seq`, `baseSeq`, and
  full-snapshot resync because they are easy to test and make gaps fail loud.
  Reject durable event-sourcing in V1 because the working set is a few hosts and
  hundreds of rows, not a distributed database.
- Provider adapter boundary - adopt the adapter pattern for Codex now and
  Claude Code later. Reject exposing provider-specific list/status/source fields
  to Swift.

Note: no separate external-research command was run for this auto-plan because
the stage gate did not require it, and current repo evidence plus the prior
model-consensus pass resolved the decision gaps. The anchors above are design
principles used to ground the plan, not sourced external citations.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors:
  - `scripts/dock-relay-thread-data.mjs:457` - `aggregateThreadList` is the
    current relay list path; it reads history, decorates summaries, and returns
    `liveOverlay`.
  - `scripts/dock-relay-live-status-cache.mjs:43` - `LiveStatusCache` is the
    current background poller pattern to generalize into a full session table
    sync loop.
  - `scripts/dock-relay-thread-summary-cache.mjs` - current latest-summary
    warming should move behind the relay-owned session table instead of being a
    client-visible timing detail.
  - `scripts/dock-relay-phase5.test.mjs:192` and
    `scripts/dock-relay-phase5.test.mjs:304` - tests currently assert history
    status is preserved and `notLoaded` survives list output; these are
    deliberate contracts to replace for Dock Home.
  - `CodexDock/State/DockStore.swift:569` - current reload path starts a
    client-owned refresh.
  - `CodexDock/State/DockStore.swift:665` - current multi-host loading
    publishes partial snapshots while other hosts are still checking.
  - `CodexDock/State/DockStore.swift:746` and `:876` - current snapshot and
    dedupe/conflict rules belong behind the relay boundary for Dock Home.
  - `CodexDock/State/AppServerDockClient.swift:83` - current Dock list client
    sends raw app-server/relay list requests.
  - `CodexDock/AppServer/ThreadListDTO.swift:257` - Swift currently knows raw
    `notLoaded`.
  - `CodexDock/Models/SessionSummaryMapper.swift:334` - Swift currently maps
    provider status into `SessionSummary`.
  - `CodexDock/State/SessionRowProjector.swift:58` - row status projection
    exposes `notLoaded` into Dock rows.
- Canonical path / owner to reuse:
  - Relay ownership belongs under `scripts/dock-relay*.mjs`, reusing existing
    logger, constants, JSON-RPC client, upstream pool, summary cache, and
    realtime secret boundary patterns.
  - Swift Dock Home state ownership belongs under `CodexDock/State/` and should
    feed existing `CodexDock/Features/Dock/*` views through a normalized table
    or projection, not by adding business logic to views.
- Adjacent surfaces tied to the same contract family:
  - `CodexDock/AppServer/AppServerMethods.swift` - add `dock/*` method names or
    a new method owner while preserving existing raw non-Home method names.
  - `CodexDock/AppServer/JSONRPC.swift` and `AppServerClient.swift` - reuse
    transport/request mechanics for the new stream.
  - `CodexDock/State/AppConnectivityStore.swift` - connectivity labels must not
    collapse host connection, table freshness, and row runtime.
  - `CodexDock/State/HostSettingsStore.swift:152` - host settings currently
    calls `loadSessions` for connection/testing behavior; preserve the existing
    non-Home raw-list contract unless a separate host-settings migration plan
    owns it.
  - `CodexDock/State/ArchiveStore.swift` - raw archive list is not migrated in
    V1 unless required by shared DTO cleanup; keep explicitly out of Dock Home
    cutover.
  - `CodexDock/State/ThreadDetailStore.swift` - raw detail/resume/turn methods
    remain preserved existing non-Home raw contracts in this plan.
  - `CodexDock/Automation/AutomationID.swift:109` -
    `AutomationID.Dock.notLoadedExplanation` must be deleted, renamed, or
    confined when Dock Home removes visible not-loaded state.
  - `CodexDock/Features/Dock/DockFilterSurfaceView.swift:103` and `:181` -
    visible not-loaded filter copy/state must move to the canonical status set
    or disappear from Dock Home.
  - `CodexDock/Features/Dock/DockSharedViews.swift:258` - not-loaded row color
    styling must move to canonical status styling or disappear from Dock Home.
  - `CodexDockTests/*` and `scripts/dock-relay*.test.mjs` - tests that encode
    old Home assumptions must be updated with the contract.
  - `README.md:131` through `:142` currently describes local filtering and old
    not-loaded display behavior; update it after cutover because it will be
    contradicted by the new Dock Home data flow.
  - Any other live docs that describe Dock Home data flow must be updated if
    touched or contradicted by the cutover.
- Compatibility posture (separate from `fallback_policy`):
  - Clean cutover for Dock Home after the new stream path is simulator-proven.
  - Existing non-Home raw detail/control/archive/voice APIs are preserved as
    current contracts in this plan; future migration requires a separate plan.
  - No permanent fallback from `dock/*` Home back to raw `thread/list`.
- Existing patterns to reuse:
  - `scripts/dock-relay-logger.mjs` - structured relay diagnostics.
  - `scripts/dock-relay-constants.mjs` - relay timing and caps.
  - `scripts/dock-relay-json-rpc-client.mjs` and
    `scripts/dock-relay-upstream-pool.mjs` - upstream request mechanics.
  - `scripts/dock-relay-test-helpers.mjs` - relay JSON-RPC test helpers.
  - `CodexDock/AppServer/AppServerClient.swift` - WebSocket JSON-RPC transport.
  - `CodexDock/Diagnostics/Logging.swift` - app log proof surface.
  - `CodexDock/Configuration/HostRegistry.swift` - per-host configuration stays
    the app bootstrap source.
- Duplicate or drifting paths relevant to this change:
  - `DockRowStatusKind.notLoaded`, `DockProjectionEmptyReason.notLoadedOnly`,
    and tests around not-loaded filtering are valid only for the old Home model;
    after cutover they must be deleted, renamed, or explicitly confined outside
    Dock Home.
  - `AppServerDockClient.loadSessions` and `SessionSummaryMapper` remain useful
    for raw compatibility only until Dock Home moves off them.
  - Relay `thread/list` can remain for legacy/detail/archive compatibility but
    must stop being the Dock Home source of truth.
- Behavior-preservation signals already available:
  - `rtk npm run test:relay`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk make app-test SIM='iPhone 17'`
  - `rtk make app SIM='iPhone 17'`
  - `rtk make sim-logs SIM='iPhone 17'`
  - `rtk make iphone-17-pro` when physical signing/device state allows it.

## 3.3 Decision gaps that must be resolved before implementation

- none

Research stage note: current repo anchors were refreshed on 2026-05-29 before
the auto-plan research receipt was completed.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- Relay code lives in `scripts/dock-relay*.mjs`.
- Current list aggregation lives mostly in `scripts/dock-relay-thread-data.mjs`.
- Current live status polling lives in `scripts/dock-relay-live-status-cache.mjs`.
- Swift app-server DTOs and JSON-RPC transport live in `CodexDock/AppServer/`.
- Dock Home state and projection live in `CodexDock/State/DockStore.swift`,
  `DockSessionProjection.swift`, and `SessionRowProjector.swift`.
- Dock Home views live under `CodexDock/Features/Dock/`.

## 4.2 Control paths (runtime)

Current Dock Home flow:

```text
DockView / AppLifecycle -> DockStore.reload
  -> loadAllHostsPublishingPartial
  -> per host, per scope AppServerDockClient.loadSessions
  -> relay thread/list
  -> history app-server thread/list
  -> Swift SessionSummaryMapper
  -> DockStore.makeSnapshot
  -> DockSessionProjection
  -> Dock views
```

The relay's current `thread/list` path is request-time aggregation, not a
durable Dock-state stream.

## 4.3 Object model + key abstractions

- `ThreadListDTO` is Codex-shaped.
- `SessionSummary` is Swift's current mapped row model.
- `DockRowViewModel` is the current presentation row.
- `DockSnapshot` is built by Swift from the currently completed host/scope
  results.
- `ThreadListLiveOverlayDTO` reports live status metadata but does not replace
  the row status.
- `DockRowStatusKind.notLoaded` is a user-visible row status today.

## 4.4 Observability + failure behavior today

- App logs use subsystem `com.aelaguiz.CodexDock`.
- Relay logs use structured JSON logger helpers.
- Slow host refresh produces partial `.loaded` states while still-checking hosts
  have no rows in the current snapshot.
- Live failure can degrade `liveOverlay`; history failure can fail `thread/list`.
- There is no relay-owned last-good Dock table for Home.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Today, a selected host can visually behave like this during refresh:

```text
Home selected
------------------------------------------------
Home       Checking

[empty or filtered-to-zero list while Home loads]
------------------------------------------------
```

The intended user experience is:

```text
Home selected
------------------------------------------------
Home       Stale, refreshing

Existing Home row
Existing Home row
Existing Home row
------------------------------------------------
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

Expected relay additions; exact filenames may change, but owner boundaries are
fixed:

- `scripts/dock-relay-session-table.mjs`
- `scripts/dock-relay-dock-protocol.mjs`
- `scripts/dock-relay-provider-adapter.mjs`
- `scripts/dock-relay-codex-adapter.mjs`
- targeted relay tests for the new protocol, session table, persistence, and
  Codex adapter behavior

Expected Swift additions; exact filenames may change, but owner boundaries are
fixed:

- `CodexDock/AppServer/DockStreamDTO.swift` or equivalent DTO owner
- `CodexDock/State/DockStreamClient.swift` or equivalent stream client
- `CodexDock/State/DockSessionTable.swift` or equivalent reducer/table owner
- focused tests for snapshot/delta/resync behavior

## 5.2 Control paths (future)

Future Dock Home flow:

```text
DockView / AppLifecycle
  -> Dock stream state owner
  -> one DockStreamClient per configured relay host
  -> relay dock/subscribe
  -> full snapshot { hosts[], sessions[] }
  -> ordered dock/update deltas per host stream
  -> resync that stream on epoch/seq gap
  -> normalized union projection
  -> Dock views
```

Relay flow:

```text
SyncLoop tick
  -> ProviderAdapter.listSessions
  -> ProviderAdapter.liveStatus
  -> normalize + merge
  -> SessionTable diff
  -> persist last-good atomic JSON
  -> notify subscribers with snapshot/delta/heartbeat
```

## 5.3 Object model + abstractions (future)

Relay:

- `SessionTable` owns `schemaVersion`, `epoch`, `seq`, `asOf`, `freshness`,
  `hosts`, `sessions`, and `lastError`.
- `ProviderAdapter` hides provider-specific list/live/detail/control behavior.
- `CodexAdapter` converts Codex history/live/runtime facts into normalized
  sessions.
- `SubscriberRegistry` sends snapshots/deltas and coalesces slow subscribers.
- `DockProtocol` serializes provider-agnostic `dock/*` messages.
- `LastGoodStore` atomically persists normalized table JSON.

Wire protocol:

```text
dock/subscribe -> snapshot { kind:"snapshot", schemaVersion, epoch, seq, asOf, freshness, hosts[], sessions[] }
dock/update    -> delta { kind:"delta", epoch, baseSeq, seq, upsertHosts[], upsertSessions[], deleteSessionIDs[] }
dock/update    -> heartbeat { kind:"heartbeat", epoch, seq, asOf, freshness }
dock/resync    -> snapshot { kind:"snapshot", schemaVersion, epoch, seq, asOf, freshness, hosts[], sessions[] }
```

- `dock/subscribe` is a client request. The first full snapshot is the
  `dock/subscribe` response.
- `dock/update` is a server-to-client notification only. Delta updates include
  `baseSeq`; heartbeat updates do not include `baseSeq`.
- `dock/resync` is a client request that returns a full snapshot.
- WebSocket close unsubscribes the client. V1 does not add
  `dock/unsubscribe`.
- `kind` is the required discriminator for snapshot, delta, and heartbeat.
  Clients must not infer message type from the presence or absence of
  `baseSeq`.
- `epoch`, `seq`, and `baseSeq` are scoped per relay stream. A snapshot/resync
  replaces only the rows for the host or hosts represented by that stream; it
  must not clear another relay host's rows from the client union.
- Heartbeats report the stream's current `seq`; they do not advance `seq`.
  Delta `baseSeq` references the last accepted snapshot or delta `seq` for
  that same stream.

Swift:

- `DockStreamDTO` decodes snapshots, deltas, and heartbeats.
- `DockStreamClient` manages the JSON-RPC/WebSocket stream.
- `DockSessionTable` applies snapshots and deltas mechanically.
- Existing Dock views render projected normalized sessions and host metadata.

## 5.4 Invariants and boundaries

- `notLoaded` is not a valid `dock/*` wire status.
- Valid V1 row statuses are exactly: `running`, `needsInput`,
  `needsApproval`, `idle`, `error`, `dormant`, and `unknown`.
- Codex status mapping is exact at the adapter boundary:

| Codex adapter input | Dock Home wire status | Reason |
| ------------------- | --------------------- | ------ |
| `running` / live running equivalent | `running` | Active work is visible. |
| needs-input equivalent | `needsInput` | User action is needed. |
| needs-approval equivalent | `needsApproval` | Approval action is needed. |
| idle / completed / inactive history equivalent | `idle` | Known non-running row. |
| error / failed equivalent | `error` | Failure is user-visible. |
| `notLoaded` | `dormant` | The provider has history, but the runtime is not loaded; this is not a user-facing product state. |
| unknown / unmapped provider status | `unknown` | Adapter could not classify without lying. |

When Codex supplies multiple active flags, the adapter chooses one row status
with this precedence: `needsApproval`, then `needsInput`, then `running`.
`dormant` is a canonical wire value, not a required visible badge. Dock Home may
keep row-badge space for active/actionable states and errors. If this state is
exposed in filters or summaries, the honest product label is `Not loaded`, not
`History`.

- "No provider-specific decoding in the client" means the Dock Home `dock/*`
  stream path. Existing preserved non-Home raw callers may still decode
  provider-shaped DTOs until a separate migration plan owns them.
- `lane` is on the wire as `human` or `agent`.
- `kindLabel` is display-only and not a branching key.
- Host connection, table freshness, and row runtime status are separate fields.
- Raw provider metadata, secrets, loopback URLs, and `dockRelaySource` stay
  relay-side.
- V1 stores last-good state as atomic JSON, not SQLite.
- V1 uses per-host streams and trivial client union; coordinator/federation is
  deferred under the same envelope.
- Dock Home cutover is a clean cutover after proof, not a permanent fallback.

## 5.5 UI surfaces (ASCII mockups, if UI work)

The user-facing shape should make stale state honest without hiding rows:

```text
All hosts
------------------------------------------------
Amir-M5        Fresh        42 rows
Home           Stale        200 rows  Last sync 2m ago

Newest
  Running row                                      Amir-M5
  Background row                                   Home
  Needs approval row                               Amir-M5
------------------------------------------------
```

Selected stale host:

```text
Home
------------------------------------------------
Stale, reconnecting       Last good 14:31:02

Existing row
Existing row
Existing row
------------------------------------------------
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Relay protocol | `scripts/dock-relay.mjs` | request dispatch / downstream sessions | Exposes raw Codex-shaped `thread/*` to the phone | Add `dock/subscribe`, `dock/update`, `dock/resync`, subscriber lifecycle, snapshot/delta sends | Dock Home needs provider-agnostic streaming state | `dock/*` JSON-RPC over WebSocket | `rtk npm run test:relay` |
| Relay state | new `scripts/dock-relay-session-table.mjs` | `SessionTable` | No durable Dock table | Own normalized table, epoch/seq, freshness, diffing | Stable Home list and gap detection | `SessionTable` internal API | New relay table tests |
| Relay persistence | new or existing relay support module | last-good store | No normalized last-good persistence | Atomic JSON write/read under `.codex-dock/` | Fast restart and transient tolerance | persisted schemaVersion table | Relay persistence tests |
| Relay provider boundary | new `scripts/dock-relay-provider-adapter.mjs` | adapter contract | Provider details are scattered through relay/client | Define provider adapter shape | Future Claude Code without Swift rewrite | `ProviderAdapter` | Adapter contract tests |
| Codex adapter | new `scripts/dock-relay-codex-adapter.mjs` plus existing relay modules | Codex list/live/detail/control | `thread/list` history output is returned to client | Normalize Codex base rows and live runtime status into sessions | Hide `notLoaded`, source kinds, live routing | `NormalizedSession` | Codex adapter tests |
| Current relay list | `scripts/dock-relay-thread-data.mjs` | `aggregateThreadList` | Dock Home source of truth | Preserve only for existing non-Home raw contracts, or retire after non-Home callers move in a later plan | Prevent dual Home truth | Raw `thread/list` no longer Home path | Phase 5 relay tests updated |
| Live cache | `scripts/dock-relay-live-status-cache.mjs` | `LiveStatusCache` | Live overlay/status cache only | Generalize useful polling/freshness concepts into session table sync | Whole-table stale-while-refresh | Session table freshness | Relay sync tests |
| Summary cache | `scripts/dock-relay-thread-summary-cache.mjs` | `ThreadSummaryCache` | Decorates rows around request path | Reuse inside Codex adapter/session table | Keep latest summary behavior behind relay | Normalized `preview`/summary | Existing and new summary tests |
| Relay constants | `scripts/dock-relay-constants.mjs` | timing/caps | Owns relay production constants | Add sync cadence, persistence debounce, delta buffer caps if needed | Avoid scattered literals | Constants only | Relay tests |
| Relay diagnostics | `scripts/dock-relay-logger.mjs`, status files | logging/statusz | Logs current relay/list state | Add safe stream/session-table metrics without secrets | Debug stale/resync behavior | Redacted diagnostics | Relay status tests if updated |
| Swift method names | `CodexDock/AppServer/AppServerMethods.swift` | method constants | Raw `thread/*` constants | Add `dock/*` constants or new owner | Avoid stringly methods | `dock/subscribe`, `dock/resync` | AppServerClient tests |
| Swift DTO | new `CodexDock/AppServer/DockStreamDTO.swift` | snapshot/delta DTOs | `ThreadListDTO` is Home DTO | Add provider-agnostic snapshot/delta/host/session DTOs | Stop exposing Codex shape to Home | `DockSnapshotDTO` / `DockDeltaDTO` | DTO decode tests |
| Swift transport | `CodexDock/AppServer/AppServerClient.swift` | JSON-RPC transport | Request/response and notifications exist | Reuse transport for stream subscription, notifications, resync | Avoid new WebSocket stack | Existing JSON-RPC transport | AppServerClient tests |
| Swift Home state | `CodexDock/State/DockStore.swift` | `reload`, `loadAllHostsPublishingPartial`, `makeSnapshot` | Builds snapshots from raw host/scope list calls | Replace Home load source with stream table; remove destructive partial reload for Home | Rows survive slow/stale host | Stream-owned Home state | DockStore tests |
| Swift loader | `CodexDock/State/AppServerDockClient.swift` | `loadSessions` | Loads raw list rows for Dock Home and adjacent callers | Stop using for Dock Home after cutover; preserve only for existing non-Home raw-list callers such as archive/detail/host settings | Remove Home source duplication | `DockStreamClient` | AppServerClient and DockStore tests |
| Swift mapper | `CodexDock/Models/SessionSummaryMapper.swift` | `mapStatus`, origin classification | Decodes Codex source/status for Home | Remove from Home path; confine or delete old mapping once unused | Provider logic belongs relay-side | Normalized sessions | ThreadListMapping tests updated |
| Swift row status | `CodexDock/State/DockStore.swift`, `SessionRowProjector.swift` | `DockRowStatusKind.notLoaded` | User-visible not-loaded status/filter | Remove/rename/constrain after Home cutover | Product state should not show raw `notLoaded` | Canonical statuses | Dock projection tests updated |
| Swift projection | `CodexDock/State/DockSessionProjection.swift` | filters/facets/empty reasons | Filters include `.notLoaded` and `notLoadedOnly` | Update status facets and empty reasons to canonical states | UX clarity | Canonical row status | Projection tests |
| Host settings tester | `CodexDock/State/HostSettingsStore.swift` | `loadSessions` at `:152` | Uses raw list request as a host-settings check | Preserve existing non-Home raw-list tester unless a later plan replaces it | Avoid accidental settings regression | Existing raw-list contract | Host settings/AppServer client tests if touched |
| Automation IDs | `CodexDock/Automation/AutomationID.swift` | `Dock.notLoadedExplanation` | Exposes not-loaded UI identity | Remove, rename, or confine with visible not-loaded UI cleanup | Prevent stale automation contract | Canonical status IDs only | UI/app tests if touched |
| Filter surface | `CodexDock/Features/Dock/DockFilterSurfaceView.swift` | not-loaded copy/filter state at `:103` and `:181` | Shows not-loaded filter/copy | Remove or map to canonical status UI | Product copy must not expose raw runtime state | Canonical filters | Projection/UI tests |
| Shared Dock styling | `CodexDock/Features/Dock/DockSharedViews.swift` | not-loaded color at `:258` | Styles not-loaded as a status | Remove or map to canonical status styling | Avoid hidden visible stale state | Canonical status styling | Projection/UI tests |
| Connectivity | `CodexDock/State/AppConnectivityStore.swift` | overall status | Rolls several stores into labels | Reflect separate host connection and table freshness if Dock state changes | Avoid "online 1/2" confusion | Host/freshness metadata | Connectivity tests |
| Views | `CodexDock/Features/Dock/*` | Dock rows/groups/filter surface | Render current row statuses and host states | Render canonical status/freshness without explanatory copy bloat | Correct visible UX | New view model fields | App/simulator tests |
| Simulator fake relay | new or existing `scripts/*test*` support | deterministic relay | Real timing is not forceable | Add fake relay for snapshot/delta/stale/gap/reconnect | Primary UI proof | `dock/*` fake server | `rtk make app-test SIM='iPhone 17'` |
| Docs | `README.md`, live runbook docs if touched | relay/Home data path docs | May describe raw list path | Update only touched or contradicted live docs | Avoid stale truth | New Dock stream path | Doc review only |

## 6.2 Migration notes

- Canonical owner path / shared code path: relay session table plus provider
  adapter under `scripts/dock-relay*.mjs`; Swift stream/reducer under
  `CodexDock/AppServer/` and `CodexDock/State/`.
- Deprecated APIs: raw `thread/list` as Dock Home's primary source. Existing
  non-Home raw-list callers are preserved as explicit contracts in this plan,
  not as a Dock Home fallback.
- Delete list:
  - Dock Home use of `AppServerDockClient.loadSessions`.
  - Dock Home scope fan-out and dedupe/conflict logic after stream cutover.
  - User-visible `notLoaded` Home status/facet/empty reason after canonical
    statuses land.
  - Relay tests that assert history `notLoaded` survives the Home wire.
- Adjacent surfaces tied to the same contract family:
  - Archive, detail, host settings, and voice are explicit preserved non-Home
    raw API contracts for this plan.
  - Connectivity status must stay aligned with host/freshness split.
  - Relay status/debug output must stay redacted.
- Compatibility posture / cutover plan:
  - Add `dock/*` beside existing raw methods.
  - Use a test-only or simulator-only injection/harness if needed for proof.
    Do not add a production runtime switch or fallback from `dock/*` Home to
    raw `thread/list`.
  - Delete old Home raw path after simulator proof; do not keep it as fallback.
- Live docs/comments/instructions to update or delete:
  - `README.md` relay/Home data flow if contradicted.
  - Code comments around `DockRowStatusKind.notLoaded`, `liveOverlay`, or
    relay `thread/list` if they remain after cutover.
- Behavior-preservation signals for refactors:
  - Keep detail/control tests green while Home moves.
  - Keep archive tests green unless archive is explicitly migrated later.
  - Run simulator proof for Home behavior.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Relay state | `LiveStatusCache` pattern | Background poller with freshness, generalized to session table | Avoid request-path Home latency | include |
| Relay constants | `dock-relay-constants.mjs` | Central timing/cap constants | Avoid scattered production values | include |
| Relay logging | `dock-relay-logger.mjs` | Structured redacted diagnostics | Avoid secret/logging drift | include |
| Swift transport | `AppServerClient` | Existing JSON-RPC WebSocket machinery | Avoid parallel socket stack | include |
| App logs | `DockLog` | Structured simulator-verifiable events | Make UI proof machine-checkable | include |
| Detail APIs | `ThreadDetailStore` raw methods | Preserved existing non-Home raw contract | Keep non-Home behavior stable | defer to later detail migration |
| Archive APIs | `ArchiveStore` raw list/archive path | Preserved existing non-Home raw contract | Avoid broadening scope | defer unless shared DTO cleanup forces it |
| Coordinator relay | none | Same `hosts[]` + `sessions[]` envelope later | Keep topology open without V1 complexity | defer |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
Phase-plan stage note: this Section 7 is the authoritative implementation
frontier for the relay session-table migration.

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable work. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. No fallbacks/runtime shims - the system must work correctly or fail loudly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates.

## Phase 1 - Relay stream contract and session-table core

* Goal: prove the new `dock/*` protocol, sequence/resync rules, normalized table model, subscriber lifecycle, and last-good persistence with a fake provider before touching Swift Home.
* Work: add the relay session table, protocol serialization, subscriber registry, atomic JSON last-good store, and focused relay tests against fake provider data.
* Checklist (must all be done):
  - Add a normalized session/host schema with `schemaVersion`, `epoch`, `seq`, `asOf`, `freshness`, `hosts[]`, and `sessions[]`.
  - Add `dock/subscribe` as a client request whose response is the first full
    snapshot.
  - Add `dock/update` as server-to-client notification only; delta updates
    include `baseSeq`, heartbeat updates do not include `baseSeq`.
  - Add `dock/resync` as a client request that returns a full snapshot.
  - Use WebSocket close as unsubscribe; do not add `dock/unsubscribe` in V1.
  - Add required `kind` discriminators for `snapshot`, `delta`, and
    `heartbeat`; do not rely on structural message inference.
  - Add per-stream `baseSeq` gap semantics and full-snapshot resync.
  - Define heartbeat `seq` as the stream's current sequence value; heartbeats
    do not advance `seq`.
  - Add bounded connected-client delta buffering or coalescing-to-snapshot behavior.
  - Add atomic JSON last-good persistence and stale-on-boot load behavior.
  - Add fake-provider `SyncLoop` tests proving slow refresh and failed refresh
    retain last-good `sessions[]` while `freshness`/`lastError` changes.
  - Add fake-provider tests proving a disconnected/offline provider or relay
    stream retains last-good rows while host freshness/connectivity changes.
  - Add tests proving snapshot, delta, gap, resync, stale metadata, persistence load, and no secret/internal-field serialization.
  - Put production timing/cap/debounce values in `scripts/dock-relay-constants.mjs`.
* Verification (required proof):
  - `rtk npm run test:relay`
* Docs/comments (propagation; only if needed):
  - Add short comments at sequence/gap and persisted-schema boundaries if the code would otherwise be easy to misuse.
* Exit criteria (all required):
  - A fake provider can drive a relay snapshot and ordered delta stream.
  - A client sequence gap gets a full snapshot through `dock/resync`.
  - A relay restart can serve persisted normalized rows as stale before refresh.
  - Slow and failed fake-provider refreshes do not clear last-good rows.
  - Offline/disconnected fake-provider state does not clear last-good rows.
  - Heartbeats cannot create a false delta gap because they do not advance
    `seq`.
  - No raw provider secrets or internal routing metadata appear in `dock/*` payloads.
* Rollback:
  - Remove the new `dock/*` dispatch and session-table modules; existing raw `thread/*` paths remain untouched.

## Phase 2 - Codex adapter and Home contract flip in relay

* Goal: make Codex data produce canonical Dock sessions, with live/history merge and `notLoaded` removed from the client wire.
* Work: build the Codex provider adapter from current `thread/list`, live status, summary cache, and detail routing pieces; update relay tests that currently lock in history status wins.
* Checklist (must all be done):
  - Implement the Codex adapter behind the provider contract.
  - Map Codex source/sourceKind/threadSource/agent metadata into canonical `lane` and `kindLabel`.
  - Map Codex runtime status into the exact V1 canonical enum:
    `running`, `needsInput`, `needsApproval`, `idle`, `error`, `dormant`, and
    `unknown`.
  - Map Codex `notLoaded` to `dormant`; never serialize `notLoaded`.
  - Define Codex active-flag precedence as `needsApproval`, then `needsInput`,
    then `running` when multiple active flags are present.
  - Merge live runtime status into base/history rows before emitting Dock sessions.
  - Reuse `ThreadSummaryCache` inside the adapter/session table path.
  - On Codex adapter refresh failure, keep last-good `sessions[]` and update
    `freshness`/`lastError` instead of clearing rows.
  - Preserve existing raw detail/control/archive/voice behavior that is
    explicitly outside Home cutover.
  - Keep preserved raw `thread/list` compatibility tests separate from new
    `dock/*` normalization tests.
  - Replace relay tests that assert `notLoaded` survives Dock Home/list output
    with tests that assert canonical normalization on `dock/*`.
* Verification (required proof):
  - `rtk npm run test:relay`
* Docs/comments (propagation; only if needed):
  - Comment the Codex `notLoaded` mapping at the adapter boundary.
* Exit criteria (all required):
  - Codex adapter rows are provider-agnostic.
  - `notLoaded` is absent from all `dock/*` session payloads.
  - Multiple Codex active flags collapse to one canonical row status using the
    documented precedence.
  - Codex adapter failed refresh marks freshness/error without clearing
    `sessions[]`.
  - Live rows override or enrich base row runtime status when available.
  - Existing non-Home raw detail/control/archive/voice contracts still pass or
    are not touched in this phase.
* Rollback:
  - Keep `dock/*` fake-provider core from Phase 1 but disable Codex adapter registration.

## Phase 3 - Swift stream client and reducer

* Goal: let Swift consume the clean stream without moving Dock Home yet.
* Work: add snapshot/delta DTOs, method names, a stream client using existing JSON-RPC transport, and a reducer/table owner with tests.
* Checklist (must all be done):
  - Add Swift DTOs for `snapshot`, `delta`, and `heartbeat`.
  - Add `dock/*` method constants or a clear equivalent owner.
  - Model `dock/subscribe` as a client request whose response is the first full
    snapshot.
  - Model `dock/update` as server-to-client notification only; deltas require
    `baseSeq`, heartbeats must not require `baseSeq`.
  - Model `dock/resync` as a client request that returns a full snapshot.
  - Treat WebSocket close as unsubscribe; do not add a V1
    `dock/unsubscribe` client path.
  - Decode required `kind` discriminators for snapshot, delta, and heartbeat.
  - Reuse existing WebSocket/JSON-RPC transport rather than adding a parallel transport stack.
  - Add one long-lived stream/reconnect policy for Dock Home subscriptions;
    do not rely on one-shot request defaults for this stream.
  - Add a table reducer that tracks `epoch/seq/baseSeq` per stream, atomically
    replaces only that stream's represented rows on snapshot, and applies
    deltas only when that stream's `epoch/baseSeq` match.
  - Add resync request behavior for epoch mismatch, sequence gap, reconnect, and schema mismatch.
  - Add app logs for snapshot, delta, resync, host freshness, and retained rows.
  - Add tests for decode, apply, reject-gap, and resync behavior.
* Verification (required proof):
  - `rtk swift test --filter AppServerClientTests` or the smallest new focused Swift test target/filter that owns the stream DTO/client.
  - `rtk swift test --filter DockStoreTests` once reducer/projection state touches Dock state.
* Docs/comments (propagation; only if needed):
  - Comment the reducer's sequence/gap invariant if not self-evident.
* Exit criteria (all required):
  - Swift can subscribe to a fake `dock/*` stream and maintain a normalized table.
  - Per-stream gap and reconnect paths request full-snapshot resync without
    clearing other relay hosts' rows.
  - Heartbeats update freshness without changing rows or requiring `baseSeq`.
  - Heartbeats do not advance the sequence and cannot cause a false gap before
    the next delta.
  - No Swift stream DTO uses raw Codex status/source fields.
* Rollback:
  - Remove the unused stream client/reducer; existing Dock Home remains raw-list based until Phase 4.

## Phase 4 - Dock Home stream integration and preservation proof

* Goal: make Dock Home render from the normalized stream table and prove adjacent non-Home behavior is preserved before simulator deletion work.
* Work: wire the stream table into Dock Home state/projection, update statuses/facets/empty reasons, and confine old Home-specific list mapping so it is not a production Home fallback. Final deletion waits for Phase 5 simulator proof.
* Checklist (must all be done):
  - Replace Dock Home's primary `AppServerDockClient.loadSessions` path with the stream table.
  - Do not add a production runtime switch from `dock/*` Home back to raw
    `thread/list`.
  - Remove destructive partial Home snapshot publication from the active Home path.
  - Update row view models/projection/filter facets to canonical statuses.
  - Remove or confine `DockRowStatusKind.notLoaded` and `notLoadedOnly` so Dock Home no longer exposes raw `notLoaded`.
  - Render `dormant` rows with no default row badge. If the state appears in a
    filter or summary, label it `Not loaded`, not `History`.
  - Confine Home-specific scope fan-out, dedupe/conflict, `liveOverlay`, and
    Codex source/status decoding as unreachable from Dock Home or existing
    non-Home-only code. Delete these after Phase 5 simulator proof.
  - Preserve Thread Detail, Archive, Voice, Host Settings, and non-Home raw APIs;
    do not migrate them in this phase.
  - Use test-only or simulator-only injection/harness if needed for proof; no
    production app build may depend on it as a fallback.
  - Update tests that assert old Home status/facet/partial behavior.
* Verification (required proof):
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter ThreadDetailStoreTests` if detail routing code is touched.
  - `rtk swift test --filter VoiceCaptureControllerTests` if voice capture code is touched.
  - `rtk swift test --filter ComposerVoiceControlsPresentationTests` if voice presentation code is touched.
  - `rtk swift test --filter DockStoreTests` covers `ArchiveStore` raw-list
    preservation unless archive code moves to a separate test owner; if no
    focused archive proof exists after an archive touch, add an app-test smoke
    in Phase 5.
* Docs/comments (propagation; only if needed):
  - Update touched docs/comments that describe Dock Home loading from raw `thread/list`.
* Exit criteria (all required):
  - Dock Home no longer calls raw `thread/list` for its primary list.
  - Dock Home rows survive stale/slow/offline host state in reducer-level tests.
  - No default Dock Home row badge is `History` or `Not loaded`.
  - Non-Home detail/archive/voice/host-settings paths remain green or are
    explicitly untouched with no shared-code risk.
* Rollback:
  - Revert the Phase 4 integration; do not add a runtime fallback switch.

## Phase 5 - Simulator, physical device, and cleanup proof

* Goal: prove the actual user experience on the Makefile-owned app paths, then delete old Home-only raw-list code and remove remaining stale truth surfaces.
* Work: add or use a scripted fake relay for deterministic simulator scenarios, run simulator app/test/log checks, delete old Home-only raw-list code after simulator proof, run physical device install when possible, and sync live docs.
* Checklist (must all be done):
  - Add deterministic fake relay scenarios for initial snapshot, slow Home, stale Home, sequence gap, reconnect, and schema mismatch.
  - Add deterministic fake relay scenarios for offline/disconnected host state.
  - Run simulator proof with `rtk make app-test SIM='iPhone 17'` and
    `rtk make app SIM='iPhone 17'`.
  - Simulator commands must avoid stealing macOS focus during routine
    iteration: `scripts/sim.py boot` background-boots only, `rtk make app`
    reuses an already running `com.aelaguiz.CodexDockApp`, and replacement
    launches require `FORCE_LAUNCH=1`.
  - Capture or inspect simulator logs with `rtk make sim-logs SIM='iPhone 17'`.
  - Prove selected Home rows do not drop to zero during stale/slow refresh.
  - Prove selected Home rows do not drop to zero when a host is
    offline/disconnected.
  - Prove deltas apply in place and gaps trigger resync.
  - Prove heartbeats update freshness without advancing sequence or causing a
    false gap.
  - Prove no Dock Home raw `thread/list` path is active.
  - After simulator proof is green, delete old Home-specific scope fan-out,
    dedupe/conflict, `liveOverlay`, and Codex source/status decoding that no
    preserved non-Home caller owns.
  - Run `rtk make iphone-17-pro` when signing/device state allows it; record exact blocker if not.
  - Update `README.md` or other touched live docs that would otherwise describe stale Home data flow.
* Verification (required proof):
  - `rtk make app-test SIM='iPhone 17'`
  - `rtk make app SIM='iPhone 17'`
  - `rtk make sim-logs SIM='iPhone 17'`
  - `rtk make iphone-17-pro` or exact blocker recorded.
* Docs/comments (propagation; only if needed):
  - Keep only current live docs/comments; Git is the history for removed paths.
* Exit criteria (all required):
  - Simulator proves the target user experience.
  - Simulator proves offline/disconnected row retention, not only stale/slow
    refresh retention.
  - Old Home-only raw-list code is deleted after simulator proof, with preserved
    non-Home raw contracts still green.
  - Physical-device path is either green or blocked by an exact external condition.
  - Live docs/comments touched by the migration match shipped behavior.
  - No permanent Home fallback or shadow contract remains.
* Rollback:
  - Revert the cutover commit range; do not keep a runtime fallback path.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Unit tests (contracts)

- Relay contract tests for snapshots, deltas, resync, sequence gaps,
  persistence, stale-on-boot, adapter normalization, and internal field
  redaction.
- Relay contract tests for heartbeat `seq` semantics, explicit `kind`
  discrimination, per-stream sequencing, offline/disconnected row retention,
  and Codex active-flag precedence.
- Swift DTO/reducer tests for decode, snapshot replace, delta apply, gap reject,
  resync request, reconnect, and schema mismatch.
- Swift reducer tests for per-stream snapshot replacement so one host resync
  cannot clear another host's rows.
- Existing non-Home tests remain behavior-preservation signals when touched.

## 8.2 Integration tests (flows)

- `rtk npm run test:relay`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests` when detail-adjacent code is
  touched.
- `rtk swift test --filter VoiceCaptureControllerTests` when voice capture code
  is touched.
- `rtk swift test --filter ComposerVoiceControlsPresentationTests` when voice
  presentation code is touched.
- `rtk swift test --filter DockStoreTests` covers archive preservation unless
  archive code moves to a separate test owner; if no focused archive proof
  exists after an archive touch, add simulator smoke proof.

## 8.3 E2E / device tests (realistic)

- `rtk make app-test SIM='iPhone 17'`
- `rtk make app SIM='iPhone 17'`
- `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'` only when replacing the
  installed/running simulator app is required for proof.
- `rtk make sim-logs SIM='iPhone 17'`
- `rtk make iphone-17-pro` when physical device/signing state allows it.

The simulator fake relay is required because it makes slow/stale/gap/reconnect
and offline/disconnected states deterministic. Unit tests alone are not
completion evidence for the user experience.

Simulator proof should not make normal agent work obnoxious. The default
Makefile path must boot the selected simulator without `open -a Simulator`, and
must skip build/install/launch when the target app is already running. Use
`rtk make sim SIM=...` only when the Simulator window itself is intentionally
needed.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

1. Land relay `dock/*` protocol and fake-provider tests without changing Dock
   Home.
2. Land Codex adapter and relay normalization tests.
3. Land Swift stream client/reducer without making it the only Home path.
4. Cut Dock Home over to the stream table with unit/preservation proof and no
   production fallback switch.
5. Run simulator proof on the Makefile-owned app paths.
6. Delete old Home-only raw-list code after simulator proof, then run the
   physical-device path and update live docs/comments.

## 9.2 Telemetry changes

Use existing logging systems. Add safe, non-secret diagnostics for:

- subscription opened/closed
- snapshot applied
- delta applied
- delta gap detected
- heartbeat freshness applied without sequence advance
- resync requested/completed
- host freshness changed
- rows retained while stale
- rows retained while offline/disconnected
- persisted table loaded stale-on-boot
- adapter sync failures with redacted error class

Do not log prompt text, transcript text, raw JSON-RPC payloads, tokens, keys,
raw audio, bearer tokens, or provider secrets.

## 9.3 Operational runbook

- Start services with `rtk make services`.
- Check relay health with `rtk make dock-relay-status`.
- Check app-server health with `rtk make app-server-status`.
- Check relay logs with `rtk make dock-relay-logs`.
- Check simulator logs with `rtk make sim-logs SIM='iPhone 17'`.
- For physical device install, use `rtk make iphone-17-pro` or the
  Makefile-owned device-install targets.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - TL;DR, North Star, Target Architecture, Call-Site Audit, phase plan,
    verification, rollout, and decision log for contradictions.
  - Relay protocol semantics for snapshot, delta, heartbeat, resync, sequence
    gaps, and subscription lifetime.
  - Product-state language around `notLoaded`, stale rows, last-good retention,
    and rate-limit confusion.
  - Non-Home raw API preservation for detail, archive, voice, and host settings.
  - Simulator-first proof order and old Home raw-path deletion timing.
- Findings summary:
  - Phase order, status enum, protocol semantics, non-Home raw API posture,
    preservation proof, and adjacent UI surfaces all needed tightening.
- Integrated repairs:
  - Phase order now cuts Dock Home to the stream table, proves the user
    experience in simulator, and deletes old Home-only raw-list code only after
    that proof is green.
  - V1 row status is now a closed enum, and Codex `notLoaded -> dormant` is an
    exact adapter-boundary rule.
  - `dock/subscribe`, `dock/update`, `dock/resync`, heartbeat, `baseSeq`, and
    WebSocket-close semantics are exact in the target architecture and phases.
  - Phase 1 and Phase 2 now require slow/failed refresh proof that retains
    last-good rows while updating `freshness`/`lastError`.
  - Non-Home raw detail/control/archive/voice/host-settings APIs are preserved
    existing contracts in this plan, not a production fallback for Dock Home.
  - Phase 4 now includes explicit preservation proof for detail, archive, voice,
    and host settings before simulator cleanup work.
  - The call-site audit now includes Host Settings, automation IDs, filter
    surface copy/state, and shared Dock status styling.
  - External-research bookkeeping now states that no separate external-research
    command was run and why.
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

# 10) Implementation Audit

<!-- arch_skill:block:implementation_audit:start -->
## 2026-05-29 - Implementation Pass

Scope reviewed: full plan through Phase 5, current worktree.

Implementation status: complete after delegate-reported schema mismatch repair,
with physical-device path externally blocked. The iPhone 17 Pro install was not
run because the user explicitly instructed: do not install on the iPhone 17 Pro.
Simulator proof is the primary client evidence for this plan.

Evidence log: `docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29_WORKLOG.md`
Delegate review:
`/tmp/agent-delegate/dock-relay-aggregator-review-20260529T215921Z-zCXnCH/final.txt`

### Requirement Trace

| Plan obligation | Implementation evidence | Status |
| --- | --- | --- |
| Relay-owned `dock/subscribe`, `dock/update`, and `dock/resync` contract | `scripts/dock-relay-session-table.mjs` defines the protocol owner, subscription lifecycle, snapshot/delta/heartbeat messages, and resync; `scripts/dock-relay.mjs` dispatches `dock/*`. | satisfied |
| Relay session table with `schemaVersion`, `epoch`, `seq`, `asOf`, `freshness`, `hosts[]`, and `sessions[]` | `DockSessionTable.snapshot()` emits the full normalized envelope; deltas include `baseSeq` and heartbeats keep current `seq`. | satisfied |
| Provider boundary and Codex normalization | `CodexDockSessionProvider` owns Codex list reads behind `listSessions()`, and `normalizeThread()` maps Codex rows to canonical sessions. | satisfied |
| Codex `notLoaded` removed from Dock Home wire | `normalizedStatus()` maps raw `notLoaded` to `dormant`; relay tests assert `notLoaded` is absent from `dock/*` payloads. | satisfied |
| Active flag precedence | Relay normalization chooses `needsApproval`, then `needsInput`, then `running`; Swift projection preserves that same display order. | satisfied |
| Last-good atomic JSON persistence and stale-on-boot | `writeLastGoodAtomic()` persists normalized snapshots under `.codex-dock/`; `readLastGood()` rejects incompatible persisted `schemaVersion` data; relay tests cover stale-on-boot rows and incompatible-schema ignore. | satisfied |
| Slow/failed/offline refresh retains rows | Relay table failure path returns a heartbeat with stale freshness and keeps `sessions[]`; Swift table marks stale/offline while retaining rows. | satisfied |
| Slow subscriber protection | `dockUpdateForSubscriber()` coalesces an overloaded subscriber to a fresh snapshot. | satisfied |
| Swift stream DTO/client/reducer path | `DockStreamDTO.swift`, `AppServerDockStreamClient.swift`, and `DockSessionTable.swift` own the provider-agnostic client path. | satisfied |
| Per-stream gap/resync behavior | `DockSessionTable.applyUpdate()` rejects missing/incompatible schema-version, epoch, and base-sequence mismatches, and `DockStore.handleStreamUpdate()` calls `resync()`. | satisfied |
| Heartbeats do not advance sequence | Swift heartbeat handling requires the current `seq` and does not mutate it; relay heartbeat emits the table's current `seq`. | satisfied |
| Dock Home no longer uses raw `thread/list` as primary list | `DockStore` uses `DockStreamConnecting`; `AppServerDockClient.loadSessions()` remains only for archive, host settings, and raw compatibility test support. | satisfied |
| No production fallback from `dock/*` Home back to raw `thread/list` | Production Home initialization passes `AppServerDockStreamClient`; the scripted stream is DEBUG-only and env-gated for simulator proof. | satisfied |
| Remove visible `limited` / old raw not-loaded confusion | `DockRowStatusKind` uses canonical statuses, `dormant` has no default row badge, and the old not-loaded explanation/automation ID was removed. | satisfied |
| Preserve non-Home raw detail/archive/voice/host-settings behavior | Relevant Swift test suites passed; raw list DTO/client tests remain for preserved non-Home contracts. | satisfied |
| Simulator proof is primary client evidence | `rtk make app-test SIM='iPhone 17'` passed after resolver repair; `rtk make app` also passed on simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`; simulator logs show real `dock` subscriptions plus scripted stale/offline retention, sequence-gap resync, and schema-mismatch resync. | satisfied |
| Simulator commands avoid stealing focus | `scripts/sim.py boot` no longer opens Simulator; `rtk make app` reuses a running app and requires `FORCE_LAUNCH=1` for replacement launch; duplicate simulator names resolve to the single booted/booting match when there is one. | satisfied |
| Physical install path | `rtk make iphone-17-pro` not run because user explicitly prohibited installing on the iPhone 17 Pro. | externally blocked |

### Implementation Verdict

Verdict: complete for code, relay, Swift, docs, and simulator proof after
schema mismatch recovery was added and simulator-proven, and after the strict
review's persisted-schema, missing-schema, and failed-open stream lifecycle
findings were fixed.
Physical device proof is not part of this completion because it is blocked by
explicit user instruction.

Open implementation findings: none.

Non-blocking notes:

- The DEBUG scripted stream is intentionally simulator-only and selected by
  `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`; production Home has no fallback switch.
- Raw `thread/list`, `liveOverlay`, and raw `notLoaded` remain in preserved
  non-Home compatibility paths and tests. They are not Dock Home's primary list
  contract.
- The delegate review noted untracked implementation files. That is not treated
  as an implementation defect in this audit because staging/committing was not
  requested; a clean handoff must still include those paths if a commit is made.
<!-- arch_skill:block:implementation_audit:end -->

# 11) Decision Log (append-only)

## 2026-05-29 - Model consensus architecture decisions

Context: GPT-55X-High and Opus 48 Max reviewed the relay-aggregator architecture
from current repo evidence and cross-reviewed the remaining topology and
persistence questions.

Options:

- Client stale cache only.
- Smarter `thread/list` plus `liveOverlay`.
- Relay-owned polling snapshot.
- Per-host relay session-table streams.
- Coordinator/federated relay in V1.

Decision: use per-host relay session-table streams in V1. The wire envelope is
topology-agnostic with `hosts[]` and `sessions[]`, so a coordinator can be added
later without a client model rewrite. Persist last-good normalized table as
atomic JSON in V1. Use push subscription and full-snapshot resync. Remove raw
`notLoaded` from the client wire.

Consequences:

- Dock Home moves off raw `thread/list`.
- Relay owns provider adapters and normalization.
- Client remains simple but keeps one stream per configured relay host.
- Coordinator/federation is deferred.
- SQLite/event sourcing is deferred.

Follow-ups:

- Implement through the phased plan.
- Revisit coordinator only if direct host reachability or socket fan-out becomes
  a real product constraint.

## 2026-05-29 - Intent-derived: architecture doc is approved input for auto-plan

Blocker: `arch-step auto-plan` normally expects an approved canonical full-arch
doc, while this file began as a target-architecture document.

Consulted: the user's explicit objective for this run, TL;DR, and the model
consensus result embedded in the source document.

Intent says: the user asked to run `$arch-step auto-plan` on this exact document
and then have model consensus review the finished plan before a plan audit.

Decision: treat the model-consensus architecture as the approved North Star for
this planning run, convert it in place to the canonical full-arch plan shape,
and continue the gated `auto-plan` stages.

Consequences: no extra confirmation prompt is needed before planning; no code
implementation starts in this pass.

## 2026-05-29 - One-round model feedback hardening

Context: GPT-55X-High and Opus 48 Max reviewed the ready auto-plan once before
plan audit.

Decision: keep the relay-aggregator architecture, but harden the plan before
audit with explicit offline/disconnected row-retention proof, per-stream
`epoch`/`seq`/`baseSeq` scoping, heartbeat sequence semantics, required
snapshot/delta/heartbeat `kind` discriminators, Codex active-flag precedence,
and neutral `dormant` display behavior.

Consequences:

- Offline/disconnected host state is now a required relay, Swift, simulator,
  and logging proof surface.
- Heartbeats report current stream `seq`; they do not advance the delta chain.
- Snapshots/resyncs replace only the rows for their stream's represented host
  or hosts and must not clear another relay host's rows.
- Dock Home must not render default row badges for `dormant`; if that state is
  surfaced in filters or summaries, the product label is `Not loaded`.
