---
title: "Codex Dock - Human-Only Thread Filtering - Architecture Plan"
date: 2026-05-31
status: implemented
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [fresh-consult, thermo-nuclear-code-quality-review]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md
  - /tmp/fresh-consult/human-only-thread-filter-20260531T113112Z-w8uhbk/final.txt
  - /tmp/fresh-consult/human-only-thread-filter-r2-20260531T113408Z-NieUSV/final.txt
  - /tmp/fresh-consult/human-only-implementation-20260531T122616Z-sSlkaH/final.txt
---

# TL;DR

- Outcome: Codex Dock app-facing surfaces show, cache, route, archive, resume, and monitor only base/root threads that Amir started through an interactive human-facing source.
- Problem: current relay state mixes human rows with sub-agent, exec, unknown, and other machine-created rows, so non-human work dominates list paging, live leases, stream state, archive state, Swift filtering, and detail routing.
- Approach: make the relay the canonical human-only gate, use one shared classifier for every app-facing state and route path, clean stale non-human relay state, then keep a Swift defensive guard so bad payloads fail closed.
- Plan: prove the classifier first, cut over Dock and Archive state to human-only inputs, gate raw/detail/live routes, add Swift rejection defenses, then update contracts, fixtures, simulator proof, and live proof.
- Non-negotiables: no app-facing non-human cards, no all-source Dock hot-path paging, no treating unknown as human, no archive/detail/live-routing back doors, no prompt text or raw payload logging, and no runtime fallback that silently reintroduces non-human rows.

# Implementation Status

Implemented on 2026-05-31.

The relay now uses self-documenting policy names in
`scripts/dock-relay-human-thread-filter.mjs`:
`classifyThreadOrigin`, `isHumanBaseThread`, `filterHumanBaseThreads`,
`assertHumanBaseThread`, `humanThreadRejectedError`, and
`threadSpawnParentIDFromSource`. Store cleanup and counts use
`scripts/dock-relay-state-store-human-filter.mjs`, whose exported SQL helpers
make the persisted app-facing invariant explicit without pushing
`scripts/dock-relay-state-store.mjs` past 1,000 lines. The Swift defensive
guard mirrors the app-card boundary with `isAppFacingHumanThreadCard` and
`hasAppFacingHumanPinnedDisplay`.

App-facing relay behavior is human-only by default:

- Dock reconciliation drains only the default interactive active scope, then
  filters with `filterHumanBaseThreads` before state persistence.
- The state store lists, counts, archives, live-leases, and card lookups only
  where `lane == "human"` and `source_kind == "human"`.
- Raw app-facing routes strip caller-supplied source-kind broadening and reject
  direct non-human IDs with `code: -32043`,
  `message: "thread rejected by human-only filter"`, and redacted
  `{ threadId, reason }` data.
- `thread/resume` preflights the target with `assertHumanThreadID`, and focused
  turn forwarding also requires the active session to have an accepted human
  thread ID.
- `relay/state/snapshot` defaults to
  `app_facing_human_base_threads_only`; rejected rows require
  `includeRejectedThreads: true` and are labeled
  `diagnostic_includes_rejected_threads`.
- Swift stream ingestion drops non-human stream cards, one-shot snapshot
  collection completes final windows after defensive filtering, and cached
  pinned rows are revived only when the cached display proves a human origin.

Verification completed on 2026-05-31:

- `rtk npm run test:relay` passed: 216 tests, 0 failures.
- `rtk swift test --filter DockStoreTests` passed: 48 tests, 0 failures.
- `rtk swift test --filter DockStoreStreamTests` passed: 12 tests, 0 failures.
- `rtk swift test --filter DockDataEngineTests` passed: 3 tests, 0 failures.
- `rtk swift test --filter DockRenderProjectorTests` passed: 4 tests, 0 failures.
- `rtk swift test --filter ArchiveDataEngineTests` passed: 3 tests, 0 failures.
- `rtk git diff --check` passed.

Post-implementation fresh consult at
`/tmp/fresh-consult/human-only-implementation-20260531T122616Z-sSlkaH/final.txt`
returned `pass-with-notes`, `BLOCKING: none`, and high confidence. Its
highest-signal notes were folded back into the implementation: direct
`-32043` route-matrix tests, explicit `state/query` / `relay/state/snapshot`
visibility labeling, human-only spawn-edge diagnostics, `active:interactiveDefault`
parity wording, and Swift projection/pinned-display guards.

No contract files, generated DTO files, app target settings, assets, or
physical-device paths changed in this implementation. `ThreadDetailStoreTests`,
`AppServerClientTests`, `contract:check`, and simulator/device Makefile checks
were not required for the touched surfaces. The relay now owns direct-ID
rejection before Thread Detail can load non-human data; a dedicated Thread
Detail unavailable-state polish pass can be added later without changing this
human-only boundary.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-31
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-31
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:cde3d8d6878acefaa9828939e6c1924d47f799a9194348d962401efb8e4f9455",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-31T11:44:20Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:18f803bbbdc76df194a053c498ca9db7eeb489ed411258660a7b055f87a89795",
      "completed_at": "2026-05-31T11:46:13Z",
      "doc_hash_after": "sha256:29c2c639cf95e0fa686ba9c96ca0212b6a192f1b61a86478edba4dcb2d019f08"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-31T11:46:19Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:29c2c639cf95e0fa686ba9c96ca0212b6a192f1b61a86478edba4dcb2d019f08",
      "completed_at": "2026-05-31T11:49:09Z",
      "doc_hash_after": "sha256:48a6fea421a4b8ec4e22db2b4be8f3fd5752dc1c29666b83fdfeff2a1659c694"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-31T11:49:15Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:48a6fea421a4b8ec4e22db2b4be8f3fd5752dc1c29666b83fdfeff2a1659c694",
      "completed_at": "2026-05-31T11:49:55Z",
      "doc_hash_after": "sha256:ee7ea2a1cedc6608be2d1593240b63ce3bc451bf53aa0fc620fdbbf732d9f83a"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-31T11:50:05Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:ee7ea2a1cedc6608be2d1593240b63ce3bc451bf53aa0fc620fdbbf732d9f83a",
      "completed_at": "2026-05-31T11:51:49Z",
      "doc_hash_after": "sha256:b947bd540a23ca0ff7ab5ef0c8beac8801e175f0727344f10278c4575826c6a9"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-31T11:52:03Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:b947bd540a23ca0ff7ab5ef0c8beac8801e175f0727344f10278c4575826c6a9",
      "completed_at": "2026-05-31T11:56:27Z",
      "doc_hash_after": "sha256:e5fc6018f7f7d2e591a38e34dfe0f831050491fb236f02de7d51559568ee05f8"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this change, every ordinary Codex Dock app-facing path is human-only: a
base/root thread with source `cli`, `vscode`, custom `atlas`, or custom
`chatgpt` may appear; `exec`, app-server/API, MCP, sub-agent, memory/internal,
unknown, missing-source, contradictory-source, forked, and spawned child
threads may not appear or be routed.

The claim is false if any normal Dock, Archive, live routing, detail, resume,
turn, raw client route, Swift state, or controlled UI proof exposes a rejected
thread.

## 0.2 In scope

- Relay classification for Codex raw thread rows and live rows.
- Dock state reconciliation, streaming, persisted cards, and cleanup.
- Archive state reconciliation, streaming, archive/unarchive mutation handling,
  and cleanup.
- Live lease collection, loaded-thread lists, session routing, live row lookup,
  focused forwarding, and lease expiry publishing.
- App-facing raw relay routes used by the phone/client:
  `thread/list`, `thread/search`, `thread/loaded/list`, `thread/read`,
  `thread/turns/list`, `thread/goal/get`, `thread/resume`, `turn/start`,
  `turn/steer`, `turn/interrupt`, `thread/archive`, and `thread/unarchive`.
- `state/query` and `relay/state/snapshot` only where they are used by
  diagnostics or future client flows; app-facing use must be human-only, while
  all-source snapshots must be explicitly diagnostic/oracle-only.
- Swift Dock, Archive, Thread Detail, local metadata, pinned state, filters,
  previews, and test fixtures that can display, cache, or navigate to thread
  cards.
- Contract and simulator fixtures that currently model agent/spawn rows as
  app-facing rows.
- Diagnostic-only all-source views, but only when clearly separated from
  client paths.

## 0.3 Out of scope

- Deleting non-human Codex sessions from Codex storage.
- Removing the underlying raw thread taxonomy reference.
- Removing existing enum values from DTOs in the first cut.
- Treating spawned child threads, forks, or unknown-source rows as human in
  this implementation.
- Adding a second UI mode for agents or machine-created threads.
- Building a new product feature around rejected-row analytics beyond the
  minimal diagnostic proof needed to validate this migration.

## 0.4 Definition of done (acceptance evidence)

- `rtk npm run test:relay` passes with classifier, relay state, live routing,
  archive, raw route, and diagnostic separation tests.
- `rtk swift test --filter DockStoreTests` passes with client-side rejection,
  filtering, pinned metadata, and fixture updates.
- `rtk swift test --filter ThreadDetailStoreTests` passes with rejected detail
  and resume behavior.
- `rtk swift test --filter AppServerClientTests` passes with the `-32043`
  rejection contract where Swift decodes or surfaces it.
- `rtk npm run contract:check` passes if contract or generated DTO surfaces are
  touched.
- A controlled simulator/client-path proof expects spawn/exec/unknown rows to
  stay absent instead of appear as automation.
- A live data proof against local services shows Dock/Archive rows are all
  `sourceKind: human` and `lane: human`, while diagnostics can still count
  rejected rows out of band.
- Live/direct-route proof samples rejected IDs and verifies `thread/read` and
  `thread/resume` reject with `-32043`; relay route tests cover the full
  direct-route matrix for turns, goal, archive, unarchive, and focused turn
  commands.

## 0.5 Key invariants (fix immediately if violated)

- The relay is the source of truth for app-facing human-only filtering.
- Swift is a defensive guard, not the performance or correctness owner.
- Unknown, missing, and contradictory source evidence is rejected.
- Forked and spawned child rows are rejected because this plan means base/root
  threads only.
- Archive, detail, loaded-list, resume, live lease, and turn forwarding cannot
  bypass the same classifier used by Dock state.
- Diagnostic all-source data must never feed Dock, Archive, client UI, live
  leases, or client-path proof counts.
- No raw source payloads, prompt text, transcript text, bearer tokens, base64
  audio, raw audio bytes, or full JSON-RPC payloads may be logged.
- Runtime fallbacks and shims are forbidden. The system either routes through
  the canonical classifier or fails closed.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correctness: non-human-created threads cannot reach app-facing state or
   route surfaces.
2. Performance: normal Dock reconciliation must stop paging through all-source
   sub-agent and exec rows.
3. Single source of truth: one relay-owned classifier and one policy gate shape
   are reused everywhere.
4. Fail-closed behavior: unknown or incomplete source evidence is rejected.
5. Compatibility: keep DTO enum cases and app decoding stable while changing
   the app-facing invariant.
6. Operability: diagnostic counts remain available without polluting the hot
   path.

## 1.2 Constraints

- The phone/client normally connects to the Dock relay on `:4510`; it must not
  talk directly to the raw authenticated `:4500` app-server path for normal
  behavior.
- The relay owns bearer tokens and raw app-server access; source classification
  belongs there.
- Existing Swift decoders and fixtures understand `sourceKind:
  human|automation|unknown` and `lane: human|agent|unknown`; the first
  implementation should preserve those enum values.
- Relay state already contains stale non-human normalized cards, so cleanup is
  required in addition to view filtering.
- Some diagnostic scripts intentionally inspect all-source truth; they need a
  labeled diagnostic path, not removal.
- Tests must use behavior-level proof, not keyword absence or file-deletion
  proof.

## 1.3 Architectural principles (rules we will enforce)

- Reuse `scripts/dock-relay-source-filter.mjs` normalization. Do not create a
  second ad hoc source parser.
- Add one app-facing policy module, expected as
  `scripts/dock-relay-human-thread-filter.mjs`, and route every relay
  app-facing decision through it.
- Make the code self-documenting first: use explicit names such as
  `isHumanBaseThread`, `classifyThreadOrigin`, `filterHumanBaseThreads`,
  `assertHumanBaseThread`, `deleteRejectedThreadCards`, and
  `humanOnly`/`diagnosticAllSource` where that distinction matters. Avoid vague
  names like `filterRows`, `allowed`, or `specialCase` at the policy boundary.
- Filter before storing, leasing, routing, or publishing whenever possible;
  query-time guards are defense in depth, not the primary boundary.
- State cleanup deletes stale rejected cards and leases. It does not hide them
  behind UI filters.
- App-facing JSON-RPC rejection is typed and redacted:
  `code: -32043`, `message: "thread rejected by human-only filter"`,
  `data: { threadId, reason }`.
- The Swift client drops rejected stream cards and logs only redacted
  diagnostics with `DockLog`.
- Add comments sparingly and only where names are not enough: the base/root
  exclusion, unknown-fails-closed stance, diagnostic all-source separation, and
  direct-ID route assertion are the likely comment-worthy edges.
- Update necessary docs when touched behavior changes public or developer truth.
  Required docs updates are limited to this plan, the thread type/state
  reference, README/runbook sections or Makefile help touched by a new proof
  target, and any live comments or fixtures that would otherwise describe
  non-human rows as normal Dock rows.

## 1.4 Known tradeoffs (explicit)

- Human-created forks are excluded for now. If product behavior later wants
  them, revise the base/root clause and tests deliberately.
- `sourceKind: automation` and `lane: agent` stay in schemas for compatibility,
  but normal app-facing stream cards must not use them.
- Diagnostic all-source counts may still require all-source paging, so they
  must be opt-in and outside Dock/Archive hot paths.
- The live router may need to reject rows whose source metadata is incomplete;
  this is preferable to accidentally exposing machine-created rows.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The reference doc recorded live relay-listable active data on
2026-05-31T11:19:37Z:

- 1,753 active rows visible to the relay.
- 253 classified as self-started.
- 1,500 classified as something else.
- Active source breakdown: `cli` 160, `vscode` 93, sub-agent thread-spawn
  1,394, and `exec` 106.
- Archived rows: 18 total, 4 self-started, 14 something else.

The current relay and Swift app still have explicit support for showing and
filtering agent/automation/unknown cards. Dock state fetches default
interactive rows and an explicit all-source/agent-like scope, then merges both
into normalized cards. Swift exposes source filters for Any, Human, Agents,
and Unknown.

## 2.2 What's broken / missing (concrete)

- Non-human rows consume relay list pages and dominate current active volume.
- Non-human cards can be normalized into Dock and Archive state.
- Live leases and loaded-list state can keep machine-created rows alive.
- Detail routing and raw app-facing routes can bypass a UI-only filter.
- Existing persisted relay state can continue to contain stale non-human cards.
- Swift filters, pinned metadata, previews, fixtures, and tests currently treat
  agent rows as normal first-class app rows.

## 2.3 Constraints implied by the problem

- A UI-only filter cannot satisfy the performance or invariant requirement.
- Relay fetch scope, state store, live router, Archive, and raw routes must
  change together.
- Swift still needs a fail-closed guard because relay bugs or stale state can
  otherwise leak rows into UI state.
- The implementation must separate diagnostic all-source truth from app-facing
  state instead of deleting all diagnostic capability.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal "ground truth")

## External anchors (papers, systems, prior art)

- None adopted - this is not a general distributed-systems design problem. The
  authoritative truth is local: the user's product definition, raw Codex thread
  source metadata, relay route/state behavior, Swift state behavior, and the
  existing test contracts.

## Internal ground truth (code as spec)

- Authoritative behavior anchors (do not reinvent):
  - `scripts/dock-relay-source-filter.mjs` - currently owns raw source
    normalization. It already maps `cli`, `vscode`, custom `atlas`, custom
    `chatgpt`, `exec`, `appServer`, `mcp`, sub-agent variants,
    memory/internal, unknown, nested `source`, `sourceKind`, `source_kind`,
    `type`, `kind`, `custom`, and contradictory multi-signal rows into a
    normalized source.
  - `scripts/dock-relay-state-engine.mjs` - currently owns Dock reconciliation.
    `reconcileDock` drains `ACTIVE_ALL_SOURCE_SCOPE` plus the default
    interactive scope, merges both, normalizes cards, and records
    `active:allSourceKinds` and `active:interactiveDefault` scopes.
  - `scripts/dock-relay-state-views.mjs` - currently owns `orderedDockRows`,
    live overlay projection, `normalizeThread`, `lane`, and `sourceKind`
    projection. Primary rows keep their source-derived lane; default
    interactive rows are forced to `human`.
  - `scripts/dock-relay-state-store.mjs` - persists normalized `threads` rows
    with `lane`, `source_kind`, `archive_state`, active/archive scope flags,
    raw card JSON, and `live_leases`. It owns `applyDockReconciliation`,
    `upsertThreadCard`, `applyArchiveMutation`, `cardForThread`, and
    `upsertLiveLease`.
  - `scripts/dock-relay-live-status-cache.mjs` - owns `LiveStatusCache` and
    `SessionRouter`. `endpointForThread`, `rowForThread`, and
    `loadedThreadIDs` currently read source-blind live rows.
  - `scripts/dock-relay-thread-data.mjs` - owns aggregate app-facing helpers.
    `aggregateThreadList`, `aggregateThreadSearch`, `aggregateLoadedList`,
    `aggregateThreadRead`, `aggregateThreadGoalGet`, `listThreadTurns`,
    `endpointForThread`, `archiveThread`, and `unarchiveThread` currently do
    not share a human-only assertion.
- `scripts/dock-relay.mjs` - owns JSON-RPC dispatch. It routes
    `thread/list`, `thread/search`, `thread/goal/get`, `thread/loaded/list`,
    `thread/read`, `thread/turns/list`, `thread/resume`, archive/unarchive,
    `state/query`, `relay/state/snapshot`, and focused `turn/start` /
    `turn/steer` / `turn/interrupt` without an app-facing human-only gate
    today.
  - `CodexDock/AppServer/ThreadListDTO.swift` - defines
    `ThreadSourceKind.dockAgentScopeKinds`, so Swift tests currently have a
    normal production concept of active agent scopes.
  - `CodexDock/AppServer/DockThreadCardDTO.swift` - defines stable
    `DockThreadCardSourceKind` and `DockThreadCardLane` enum values that should
    remain decodable in the first cut.
  - `CodexDock/State/ThreadCardStreamSnapshotCollector.swift` - applies
    snapshot/delta stream cards into a Swift card table without source/lane
    rejection today.
  - `CodexDock/Dock/DockDataEngine.swift` and
    `CodexDock/Archive/ArchiveDataEngine.swift` - load stream cards and project
    them into Dock/Archive snapshots.
  - `CodexDock/State/ThreadCardRowProjector.swift` - maps `.agent` and
    `.automation` into normal `.agentOrAutomation(.exec)` rows, and also
    revives pinned cached rows from local metadata.
  - `CodexDock/Metadata/LocalMetadataEngine.swift` and
    `CodexDock/State/LocalThreadMetadataStore.swift` - persist pinned display
    snapshots, including `LocalPinnedDisplayOriginKind.automation` and
    `.unknown`.
  - `CodexDock/Dock/DockModels.swift` - exposes `DockSourceFilter.any`,
    `.human`, `.agents`, and `.unknown`, so visible filter UX can still reveal
    non-human rows if any survive upstream.
  - `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` and
    `CodexDock/State/ThreadDetailStore.swift` - own detail load/merge/resume
    behavior after a thread ID is selected. Detail must rely on relay rejection
    plus Swift error handling for direct-ID restored paths.

- Canonical path / owner to reuse:
  - `scripts/dock-relay-source-filter.mjs` remains the canonical raw source
    normalizer.
  - New `scripts/dock-relay-human-thread-filter.mjs` should be the canonical
    app-facing policy boundary. It should consume the source normalizer rather
    than parse source evidence again.
  - Relay state and route code must call the new classifier before state
    persistence, live lease creation, stream publication, raw route response,
    focused forwarding, and archive mutation effects.

- Adjacent surfaces tied to the same contract family:
- `scripts/dock-relay-state-snapshot.mjs`,
    `scripts/dock-relay-state-parity.mjs`,
    `scripts/dock-relay-sync-audit.mjs`,
    `scripts/dock-relay-thread-fidelity.mjs`, and simulator proof scripts
    intentionally inspect all-source truth. They should be kept, but labeled as
    diagnostic/oracle surfaces and prevented from defining app-facing row
    expectations.
  - Contract files, generated Swift DTOs, fixtures, and preview/scripted
    clients must preserve enum compatibility while changing normal app-facing
    examples to human-only rows.
  - `CodexDockTests/DockStoreScopeTests.swift`,
    `CodexDockTests/DockStoreTestSupport.swift`, and archive cleanup tests
    currently encode `.activeAgents` as a normal fixture scope; those
    expectations must become rejection/legacy compatibility fixtures only.

- Compatibility posture (separate from `fallback_policy`):
  - Preserve DTO enum compatibility and existing Swift decoding.
  - Cleanly cut over app-facing behavior: normal stream cards, archive cards,
    loaded-list IDs, raw route results, focused turn commands, and detail paths
    must be human-only.
  - No runtime bridge may allow non-human rows into app-facing state.

- Existing patterns to reuse:
  - Current JSON-RPC route dispatch in `scripts/dock-relay.mjs`.
  - Current state-store cleanup and listing patterns in
    `scripts/dock-relay-state-store.mjs`.
  - Current redacted relay logging via `scripts/dock-relay-logger.mjs`.
  - Current Swift stream snapshot/delta collection and row projection paths,
    with a small human-card guard inserted at the card boundary.

- Prompt surfaces / agent contract to reuse:
  - Not applicable. This is deterministic relay/client routing behavior, not an
    LLM prompt behavior.

- Native model or agent capabilities to lean on:
  - Not applicable for shipped behavior. Fresh consult and code review are
    planning/review aids only.

- Existing grounding / tool / file exposure:
  - `docs/CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md` records
    the live data classification and confirms fresh-consult/model-consensus
    spawned work is classified as "something else" for this UX.
  - Fresh consult round 2 at
    `/tmp/fresh-consult/human-only-thread-filter-r2-20260531T113408Z-NieUSV/final.txt`
    returned no blocking planning gaps for the pre-arch-step draft.

- Duplicate or drifting paths relevant to this change:
- `threadMatchesSourceKinds` is a source-scope helper, but it is not enough
    as the app-facing policy gate because it can intentionally include agent
    and unknown source kinds.
  - `SessionRouter` and `aggregateThreadRead` are side doors that can expose
    live rows even if Dock card streams are later filtered.
  - `state/query` and `relay/state/snapshot` can drift into app-facing
    expectations unless they are either human-only for app-facing use or
    clearly diagnostic/oracle-only for all-source truth.
  - `collectLiveRows` currently reads metadata for every loaded thread ID
    before the relay can classify. The plan must filter before leases/routes
    and should avoid unnecessary upstream reads where enough metadata already
    exists.
  - Local pinned snapshots can resurrect automation/unknown origin rows without
    a current stream card.
  - Diagnostic all-source proof scripts can drift into app-facing expectations
    unless their role is made explicit.

- Capability-first opportunities before new tooling:
  - Use the existing source normalizer instead of building a new parser.
  - Use existing route/state tests and Swift store/detail tests before adding
    new harnesses.
  - Add a live human-only proof script only if existing relay/simulator proof
    paths cannot sample rejected IDs and assert route rejection directly.

- Behavior-preservation signals already available:
  - `rtk npm run test:relay` covers relay source filtering, state, route,
    live, simulator, parity, and observability tests.
  - `rtk swift test --filter DockStoreTests` covers Dock state/projection/local
    metadata behavior.
  - `rtk swift test --filter ThreadDetailStoreTests` covers detail and resume
    behavior.
  - `rtk swift test --filter AppServerClientTests` covers JSON-RPC request and
    DTO behavior.
  - `rtk npm run contract:check` protects contract/generator consistency if
    those surfaces are touched.

## Decision gaps that must be resolved before implementation

- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

Relay state and route ownership is split across:

- `scripts/dock-relay-source-filter.mjs` - raw source normalization plus
  `threadMatchesSourceKinds`.
- `scripts/dock-relay-state-engine.mjs` - reconciliation, stream snapshots,
  stream deltas, archive snapshots, archive mutation handling, and live lease
  reconciliation.
- `scripts/dock-relay-state-views.mjs` - Dock ordering, live overlay, card
  normalization, lane projection, and stored-card normalization.
- `scripts/dock-relay-state-store.mjs` - SQLite `threads`, `sync_scopes`,
  `live_leases`, `changes`, and related state persistence.
- `scripts/dock-relay-live-status-cache.mjs` - live status cache and
  `SessionRouter`.
- `scripts/dock-relay-thread-data.mjs` - app-facing thread list/search/read,
  loaded-list, turns, goal, archive, unarchive, and live endpoint helpers.
- `scripts/dock-relay.mjs` - JSON-RPC method dispatch and live upstream
  forwarding.
- Diagnostic and proof scripts under `scripts/dock-relay-state-snapshot.mjs`,
  `scripts/dock-relay-state-parity.mjs`, `scripts/dock-relay-sync-audit.mjs`,
  `scripts/dock-relay-thread-fidelity.mjs`, and controlled simulator scripts.

Swift state and UI ownership is split across:

- `CodexDock/AppServer/ThreadListDTO.swift` and
  `CodexDock/AppServer/DockThreadCardDTO.swift` for DTO enums and stream card
  shape.
- `CodexDock/State/ThreadCardStreamSnapshotCollector.swift`,
  `CodexDock/Dock/DockDataEngine.swift`,
  `CodexDock/Archive/ArchiveDataEngine.swift`, and
  `CodexDock/State/ThreadCardTable.swift` for stream card collection and cache.
- `CodexDock/State/ThreadCardRowProjector.swift`,
  `CodexDock/State/ArchiveThreadCardProjector.swift`, and
  `CodexDock/Dock/DockRenderProjector.swift` for visible row projection.
- `CodexDock/Metadata/LocalMetadataEngine.swift` and
  `CodexDock/State/LocalThreadMetadataStore.swift` for pinned/local metadata.
- `CodexDock/State/ThreadDetailStore.swift` and
  `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` for detail load,
  stream merge, and resume behavior.
- `CodexDock/Dock/DockModels.swift` and Dock/Archive feature views for visible
  filters and navigation.

## 4.2 Control paths (runtime)

Dock reconciliation today:

```text
RelayStateEngine.reconcileDock
  -> refreshLiveLeases()
  -> drainThreadListScope(... ACTIVE_ALL_SOURCE_SCOPE)
  -> drainThreadListScope(... ACTIVE_DEFAULT_SCOPE)
  -> orderedDockRows(primaryRows, interactiveRows, liveRows)
  -> normalizeThread(row, host, lane)
  -> store.applyDockReconciliation(...)
  -> dock/subscribe snapshot or dock/update delta
```

`ACTIVE_ALL_SOURCE_SCOPE` uses `EXPLICIT_SOURCE_KINDS` from
`scripts/dock-relay-state-snapshot.mjs`, so Dock reconciliation intentionally
pulls explicit non-human source families today. In the error path, the engine
also marks `active:allSourceKinds` stale, confirming that all-source is a
first-class Dock scope today.

`orderedDockRows` currently accepts a primary all-source row set and a default
interactive row set. Primary rows keep the lane from `dockLaneForThread(row)`;
interactive rows are forced to `human`. That means non-human primary rows can
become normal cards before Swift sees them.

Live routing today:

```text
collectLiveRows
  -> upstream thread/loaded/list
  -> upstream thread/read for each loaded ID
  -> LiveStatusCache.state.rows
  -> SessionRouter.endpointForThread / rowForThread / loadedThreadIDs
  -> aggregateLoadedList / aggregateThreadRead / listThreadTurns / resume
```

`SessionRouter` currently finds rows only by thread ID. It does not check
source evidence before returning a live endpoint or live row.

Raw route dispatch today:

```text
dock-relay.mjs handleRequest
  -> thread/list        -> aggregateThreadList
  -> thread/search      -> aggregateThreadSearch
  -> thread/goal/get    -> aggregateThreadGoalGet
  -> thread/loaded/list -> aggregateLoadedList
  -> thread/read        -> aggregateThreadRead
  -> thread/turns/list  -> listThreadTurns
  -> thread/resume      -> resumeThread
  -> thread/archive     -> archiveThread + handleArchiveMutation
  -> thread/unarchive   -> unarchiveThread + handleArchiveMutation
  -> relay/state/snapshot -> buildRelayStateSnapshot
  -> state/query        -> relay state view snapshot
  -> turn/start|steer|interrupt -> forwardToActiveUpstream
```

Those route branches do not share an app-facing human-only assertion today.

Swift stream state today:

```text
AppServerThreadCardStreamClient
  -> ThreadCardStreamSnapshotCollector
  -> ThreadCardTable
  -> DockDataEngine / ArchiveDataEngine
  -> ThreadCardRowProjector / ArchiveThreadCardProjector
  -> DockScreenStore / ArchiveScreenStore / views
```

`ThreadCardStreamSnapshotCollector` applies every decoded stream card.
`ThreadCardRowProjector.origin(for:)` maps `.agent` to
`.agentOrAutomation(.exec)` and maps `.automation` sourceKind to automation
when lane is unknown. Cached pinned rows also revive origin from local
metadata.

## 4.3 Object model + key abstractions

- Raw source rows are normalized by `normalizedThreadSource(row)` in
  `scripts/dock-relay-source-filter.mjs`.
- Default interactive source matching already means `cli`, `vscode`, custom
  `atlas`, and custom `chatgpt`.
- Explicit sourceKinds can match `exec`, `appServer`, sub-agent variants, and
  `unknown`.
- `sourceFromSignals` collapses conflicting source families/kinds to
  `unknown`; this is exactly the behavior the human-only classifier should
  treat as rejected/contradictory.
- Relay cards carry `lane` and `sourceKind`, but the SQLite store does not
  persist raw source evidence for old rows, so cleanup must use normalized card
  fields for stale data.
- Swift `DockThreadCardSourceKind` and `DockThreadCardLane` decode unknown
  string values as `.unknown`, so preserving enum compatibility is cheap.

## 4.4 Observability + failure behavior today

- Relay diagnostics can compare Dock state with all-source app-server truth.
- Some parity/sync/fidelity scripts assume app-facing Dock should align with
  active all-source listable rows. Those checks become wrong for this product
  invariant unless they distinguish diagnostic all-source truth from
  app-facing human-only truth.
- Relay logs are structured and should remain redacted through
  `scripts/dock-relay-logger.mjs`.
- Swift diagnostics should continue to use `DockLog`.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current behavior still has visible concepts for agent/unknown rows:

```text
Dock source filters
  Any | Human | Agents | Unknown

Possible row origins
  Human interactive
  Agent or automation
  Unknown

Pinned row cache
  may revive human, automation, or unknown origin
```

Target UI must collapse normal app-facing rows to human-only while preserving
legacy enum decoding and rejection fixtures in tests.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- Add `scripts/dock-relay-human-thread-filter.mjs` as the single app-facing
  policy boundary.
- Export the source normalizer needed by that module from
  `scripts/dock-relay-source-filter.mjs` rather than duplicating parser logic.
- Update `scripts/dock-relay-state-engine.mjs`,
  `scripts/dock-relay-state-views.mjs`,
  `scripts/dock-relay-state-store.mjs`,
  `scripts/dock-relay-state-ingest.mjs`,
  `scripts/dock-relay-live-status-cache.mjs`,
  `scripts/dock-relay-thread-data.mjs`, and `scripts/dock-relay.mjs` to use the
  classifier on app-facing paths.
- Add a small Swift card policy, either as `DockThreadCardDTO` extension or a
  state-layer helper, so stream collection/projection can drop rejected cards.
- Prefer self-explaining code structure over explanatory comments: classifier
  reason names, route assertion names, cleanup helper names, and Swift guard
  names should show that the system is intentionally human-only at app-facing
  boundaries.
- Update fixtures, previews, simulator proof, contracts, and tests so
  non-human rows are rejection/diagnostic fixtures, not normal Dock rows.

## 5.2 Control paths (future)

Dock reconciliation future:

```text
RelayStateEngine.reconcileDock
  -> refresh human-only live leases
  -> drain default interactive active scope only
  -> filterHumanBaseThreads(default rows)
  -> orderedDockRows(accepted human rows, accepted human rows, human live rows)
  -> normalizeThread(... lane="human")
  -> cleanup rejected stale cards/leases
  -> store/app-facing stream contains human rows only
```

Raw app-facing route future:

```text
route request by thread ID or row set
  -> resolve enough metadata to classify
  -> if accepted: continue through existing helper
  -> if rejected: throw -32043 with { threadId, reason }
```

Diagnostic future:

```text
explicit diagnostic route/script
  -> may page all-source data
  -> produces counts or oracle comparisons
  -> never feeds Dock, Archive, Swift UI, live leases, or client-path proof rows
```

Swift future:

```text
stream card decoded
  -> isHumanAppFacingCard(card)
  -> accepted cards enter ThreadCardTable
  -> rejected cards are dropped with redacted DockLog warning
```

## 5.3 Object model + abstractions (future)

Relay classifier contract:

```text
classifyThreadOrigin(row) -> {
  allowed: boolean,
  category: "human_base" | "rejected",
  reason:
    | "human_cli"
    | "human_vscode"
    | "human_custom_atlas"
    | "human_custom_chatgpt"
    | "exec"
    | "app_server"
    | "mcp"
    | "sub_agent"
    | "sub_agent_thread_spawn"
    | "memory_internal"
    | "unknown"
    | "missing_source"
    | "contradictory_source"
    | "forked"
    | "not_base_level",
  sourceKind?: string
}

isHumanBaseThread(row) -> boolean
filterHumanBaseThreads(rows) -> { acceptedRows, rejectedCounts }
threadSpawnParentIDFromSource(source) -> string | null
assertHumanBaseThread(rowOrThreadIDContext) -> row or throws -32043
```

Classifier rules:

- Accept only default interactive human sources: `cli`, `vscode`, custom
  `atlas`, and custom `chatgpt`.
- Reject missing source, unknown source, internal source, contradictory source,
  any automation source, any sub-agent source, `threadSource: subagent`,
  `threadSource: memory_consolidation`, non-empty `forkedFromId` /
  `forked_from_id`, and source shapes with thread-spawn parent evidence.
- When a route only has a thread ID, resolve metadata through the same route
  family before returning app-facing data. If metadata cannot prove human-base,
  reject.
- `threadSpawnParentIDFromSource` already exists in diagnostic scripts such as
  `scripts/dock-relay-state-parity.mjs` and
  `scripts/dock-relay-sync-audit.mjs`. The implementation should move the
  canonical helper into the classifier module, then update diagnostic scripts
  to import it instead of keeping parallel thread-spawn parsing.
- Direct-ID gates should not resume or stream a rejected thread just to find out
  whether it is rejected. For historical IDs, first read minimal metadata with
  `thread/read` / `includeTurns: false` or reuse already-loaded row metadata;
  for live IDs, use the live row metadata already returned by `SessionRouter`.
  Only accepted rows may proceed to turns, resume, archive, unarchive, or
  focused turn forwarding.
- Live collection should classify as early as the available upstream data
  allows. If a loaded-list or live row already carries source evidence, reject
  before `thread/read`; if the source evidence is only available from
  `thread/read`, reject immediately after that read and before lease/router
  persistence.

Swift card contract:

```text
isHumanAppFacingCard(card) =
  card.lane == .human
  AND card.sourceKind == .human
```

## 5.4 Invariants and boundaries

- `classifyThreadOrigin` is the app-facing source of truth.
- `threadMatchesSourceKinds` remains a lower-level source-scope helper.
- `ACTIVE_ALL_SOURCE_SCOPE` is removed from Dock reconciliation.
- `ACTIVE_ALL_SOURCE_SCOPE` or equivalent all-source paging may appear only in
  explicit diagnostic/oracle scripts.
- `relay/state/snapshot` and `state/query` must not become app-facing
  all-source side doors. If used for diagnostics, they must label all-source
  data as diagnostic/oracle-only; if used by a client path, they must return
  human-only rows.
- Stored non-human cards and live leases are deleted or ignored during startup
  and reconciliation cleanup.
- `listDockCards`, `listArchiveCards`, and `cardForThread` must not return a
  rejected card to app-facing callers.
- `thread/archive` and `thread/unarchive` must reject non-human IDs before
  archive mutation state can publish a card.
- `turn/start`, `turn/steer`, and `turn/interrupt` must prove the focused
  resumed thread was accepted human-base before forwarding. The session should
  carry that accepted-thread fact after `thread/resume` succeeds.
- Resume recovery may reuse the already accepted session binding, but a new
  `thread/resume` request must run the classifier again before binding a fresh
  upstream.
- Swift treats non-human cards as invalid payloads and drops them.
- Compatibility posture: preserve DTO enum decoding; cleanly cut over visible
  app-facing behavior.

## 5.5 UI surfaces (ASCII mockups, if UI work)

```text
Dock
  [human thread]
  [human thread]

Source filters
  Any | Human
  Agents/Unknown hidden in normal data because no rows survive

Archive
  [archived human thread]

Rejected deep link / restored ID
  Thread unavailable
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Relay source policy | `scripts/dock-relay-source-filter.mjs` | `normalizedThreadSource`, `threadMatchesSourceKinds` | Normalizes raw source and matches interactive/agent scopes, but exports only `threadMatchesSourceKinds` | Export/reuse normalization needed by a human-base classifier; keep `threadMatchesSourceKinds` as a source-scope helper | Avoid a second parser and preserve existing tested source semantics | normalizer consumed by `dock-relay-human-thread-filter.mjs` | `scripts/dock-relay.test.mjs` source tests |
| Relay source policy | `scripts/dock-relay-human-thread-filter.mjs` | new module | Missing | Add `classifyThreadOrigin`, `isHumanBaseThread`, `filterHumanBaseThreads`, `threadSpawnParentIDFromSource`, and rejection error helper | One app-facing policy owner | accepted/rejected reason contract | new classifier tests |
| Thread-spawn parsing | `scripts/dock-relay-state-parity.mjs`, `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-thread-fidelity.mjs` | local thread-spawn/source helpers | Diagnostic scripts duplicate source parsing and parent extraction | Move reusable parent extraction into the classifier/source-policy layer and import it | Prevent diagnostic and app-facing parsing drift | shared helper | parity/sync/fidelity tests |
| Dock reconciliation | `scripts/dock-relay-state-engine.mjs` | `ACTIVE_ALL_SOURCE_SCOPE`, `reconcileDock` | Drains all-source and default interactive active scopes | Remove all-source Dock fetch; drain default interactive only; defensively filter accepted rows | Main performance win and invariant owner | human-only cards/scopes | relay state tests |
| Dock reconciliation error path | `scripts/dock-relay-state-engine.mjs` | `markScopeStale("active:allSourceKinds")` | Treats all-source as normal Dock scope | Replace with human/default scope semantics | Avoid stale app-facing scope truth | no app-facing all-source scope | relay failure tests |
| Live leases | `scripts/dock-relay-state-engine.mjs` | `refreshLiveLeases`, `liveLeaseFromRow` | Creates leases for collected live rows | Filter live rows before `upsertLiveLease`; delete/expire stale rejected leases | No live lease side door | human-only live leases | live lease tests |
| Relay ordering/projection | `scripts/dock-relay-state-views.mjs` | `orderedDockRows`, `normalizeThread`, `sourceKindFromThread`, `dockLaneForThread` | Can project primary non-human rows into cards | Project app-facing rows as human only after classifier gate | Prevent stream leaks | `sourceKind: human`, `lane: human` for app cards | projection tests |
| Relay store schema/use | `scripts/dock-relay-state-store.mjs` | `threads`, `source_kind`, `lane`, `live_leases` | Persists normalized cards and leases, not raw origin evidence for old rows | Add cleanup that deletes rows/leases with non-human normalized fields; optionally persist redacted origin reason for new diagnostics | Stale state cannot leak | cleanup helpers | store cleanup tests |
| Relay store listing | `scripts/dock-relay-state-store.mjs` | `listDockCards`, `listArchiveCards`, `cardForThread` | Can return stored non-human cards | Defensively filter human cards for app-facing callers | Defense in depth | human-only result invariant | store/list tests |
| Archive mutation | `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-ingest.mjs` | `applyArchiveMutation`, `handleArchiveMutation`, notification ingest | Mutations can move any known card into Archive | Reject/ignore/delete non-human archive mutations | Archive cannot become a parking lot | classifier assertion | archive tests |
| Live routing | `scripts/dock-relay-live-status-cache.mjs` | `SessionRouter.endpointForThread`, `rowForThread`, `loadedThreadIDs` | Source-blind thread ID lookup | Return only human-base live rows/IDs; missing source rejects | Prevent route side door | human-only router | live route tests |
| Thread route helpers | `scripts/dock-relay-thread-data.mjs` | `aggregateLoadedList`, `aggregateThreadRead`, `aggregateThreadGoalGet`, `listThreadTurns`, `endpointForThread`, `archiveThread`, `unarchiveThread` | ID-based helpers do not share classifier assertion | Assert human before live fast path, history fallback, turns, goal, archive, and unarchive | Detail/raw routes align with Dock | `-32043` rejection | raw route tests |
| Resume binding | `scripts/dock-relay.mjs` | `resumeThread`, `recoverSessionUpstream`, `forwardToActiveUpstream`, `assertFocusedRequestTargetsBoundThread` | Resume binds an upstream after endpoint lookup and only checks returned thread ID | Classify before fresh resume; store accepted-thread binding on session; focused turn commands require that accepted binding | Prevent live upstream side door | accepted focused session | phase5/live tests |
| List/search routes | `scripts/dock-relay-thread-data.mjs` | `aggregateThreadList`, `aggregateThreadSearch` | Forwards caller params and returns history rows | Force app-facing human/default scope and filter returned rows | Caller cannot request agents | human-only data arrays | list/search tests |
| JSON-RPC dispatch | `scripts/dock-relay.mjs` | `handleRequest`, `forwardToActiveUpstream`, `resumeThread` | Dispatches app-facing routes and focused turn commands without human assertion | Gate app-facing methods and focused turn forwarding through same classifier/focused-thread assertion | One route boundary | redacted `-32043` errors | route tests |
| State query/snapshot routes | `scripts/dock-relay.mjs`, `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-snapshot.mjs` | `state/query`, `relay/state/snapshot`, `buildRelayStateSnapshot` | Can expose relay state or all-source oracle data | Make app-facing state query human-only; label all-source snapshot data diagnostic/oracle-only and keep it out of client state | Prevent diagnostic routes from becoming back doors | diagnostic vs app-facing contract | route/snapshot tests |
| Diagnostics | `scripts/dock-relay-state-snapshot.mjs`, `scripts/dock-relay-state-parity.mjs`, `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-thread-fidelity.mjs` | all-source oracle scripts | Some checks expect Dock to match active all-source rows | Split diagnostic all-source truth from app-facing human-only truth | Preserve observability without false failures | diagnostic-only labeling | parity/sync/fidelity tests |
| Controlled simulator | `scripts/dock-relay-controlled-simulator-fixture.mjs`, `scripts/dock-relay-controlled-simulator-matrix.mjs`, `scripts/dock-relay-simulator-ui-sync-proof.mjs` | spawn/exec scenarios expect visible automation rows | Change scenarios to assert rejected absence from client path | UI proof matches new invariant | human-only absence proof | simulator tests |
| Contract/generator | `contract/dock/*`, `scripts/generate-dock-thread-card-contract.mjs`, `CodexDock/AppServer/DockThreadCardDTO.swift` | Enums allow human/automation/unknown and human/agent/unknown | Preserve enum decoding; document normal app-facing invariant and update normal fixtures | Compatibility | app-facing cards human only | contract check |
| Swift stream collection | `CodexDock/State/ThreadCardStreamSnapshotCollector.swift` | Applies every decoded card | Drop rejected cards during snapshot/delta apply or before table insertion | Bad relay payload cannot cache | `isHumanAppFacingCard` | stream/DockStore tests |
| Swift Dock cache | `CodexDock/Dock/DockDataEngine.swift`, `CodexDock/State/ThreadCardTable.swift` | Caches stream cards | Ensure only accepted cards enter or remain in table | Defense in depth | human card table | DockStore tests |
| Swift Archive cache | `CodexDock/Archive/ArchiveDataEngine.swift`, `CodexDock/State/ArchiveThreadCardProjector.swift` | Projects archive stream cards | Drop rejected archive cards | Archive invariant | human-only archive sections | Archive tests |
| Swift projection | `CodexDock/State/ThreadCardRowProjector.swift` | Projects `.agent`/`.automation` into normal rows and cached pins | Return no row for rejected stream cards; suppress rejected cached pins | No visible row bypass | compact-map projection or prefilter | projection tests |
| Swift filters | `CodexDock/Dock/DockModels.swift`, Dock views/screen store | Exposes Any/Human/Agents/Unknown | Hide unavailable agent/unknown facets or keep only legacy injection support | UX matches data | human-only visible filters | filter tests |
| Swift local metadata | `CodexDock/Metadata/LocalMetadataEngine.swift`, `CodexDock/State/LocalThreadMetadataStore.swift` | Persists pinned automation/unknown snapshots | Delete/suppress automation and unknown pinned snapshots during load/migration/projection | Pins cannot resurrect rejected rows | metadata cleanup | metadata tests |
| Swift detail | `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`, `CodexDock/Features/Dock/DockView.swift` | Opens selected/restored thread IDs and resumes | Handle `-32043` as unavailable; avoid resume after rejection; clear restored rejected navigation | No direct-ID bypass | rejected detail state | ThreadDetailStore tests |
| Swift fixtures/previews | `CodexDock/State/ScriptedDockStreamClient.swift`, `CodexDock/Features/Dock/DockViewPreview.swift`, `CodexDockTests/**` | Normal fixtures/previews include automation rows | Move non-human rows to rejection tests only | Normal examples are truthful | human-only fixtures | Swift tests |
| Live proof | `Makefile`, optional `scripts/dock-relay-human-only-proof.mjs` | No dedicated proof | Add only if existing proof cannot sample rejected IDs | Validate live data safely | redacted diagnostic proof | make/script tests if added |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  `scripts/dock-relay-human-thread-filter.mjs` using source normalization from
  `scripts/dock-relay-source-filter.mjs`.
- Deprecated APIs (if any): none. Keep DTO enum values and sourceKinds types in
  the first cut.
- Delete list:
  stale non-human rows in relay `threads`; stale non-human `live_leases`; normal
  preview/fixture rows that show automation as visible Dock rows; all-source
  Dock reconciliation usage.
- Adjacent surfaces tied to the same contract family:
  state engine, views, store, ingest, live status, thread-data helpers, route
  dispatch, diagnostics, controlled simulator, contract fixtures/generator,
  Swift stream table, row projectors, filters, metadata, detail, and tests.
- Compatibility posture / cutover plan:
  preserve external DTO shape; cleanly cut over app-facing behavior to
  human-only; reject non-human direct IDs instead of shimming or hiding late.
- Capability-replacing harnesses to delete or justify:
  none. Use existing tests and proof paths where they can assert behavior.
- Live docs/comments/instructions to update or delete:
  this plan, the thread type reference if final classification changes, and any
  touched comments/docs that describe agent/automation rows as ordinary Dock
  rows.
- Behavior-preservation signals for refactors:
  `rtk npm run test:relay`, targeted Swift tests, contract check if touched,
  controlled simulator/client-path proof, and live proof.
- Self-documenting code requirement:
  boundary APIs, test names, fixture names, route helper names, and rejection
  reason names must make the human-only policy visible without needing a reader
  to know this plan first. Comments are reserved for non-obvious policy edges,
  not for restating what the function name already says.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Relay source policy | `scripts/dock-relay-human-thread-filter.mjs` | One classifier reused by state, route, live, archive, and diagnostics | Prevents each route from inventing slightly different "human" rules | include |
| Relay source parser | `scripts/dock-relay-source-filter.mjs` | Export normalization instead of reparsing | Prevents source taxonomy drift | include |
| Relay app-facing routes | `scripts/dock-relay-thread-data.mjs` and `scripts/dock-relay.mjs` | Shared assert/reject helper returning `-32043` | Prevents route-specific error shapes and bypasses | include |
| Relay diagnostics | parity/snapshot/sync/fidelity scripts | Explicit diagnostic all-source labeling | Prevents old all-source expectations from failing human-only app behavior | include |
| Swift card policy | DTO extension or state helper | One `isHumanAppFacingCard` guard | Prevents Dock, Archive, and previews from each filtering differently | include |
| Swift metadata | `LocalMetadataEngine` / projector | Suppress/delete rejected pinned snapshots | Prevents local cache bypass | include |
| Contract enums | generated DTO and schemas | Preserve enum values but update app-facing fixture invariant | Prevents breaking older decoders while changing behavior | include |
| Product feature expansion | Separate machine/agent UX | No new visible non-human mode | User requested human-only now | exclude |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving
> the path early. Section 7 is the execution checklist. Each phase must satisfy
> every checklist item and every exit criterion before the next phase relies on
> it.

## Phase 1 - Canonical classifier plus Dock subscribe slice

* Goal:
  Prove the core policy on one real app-facing path: raw rows enter the relay,
  the classifier accepts only human-base rows, Dock reconciliation stops
  all-source hot-path paging, and `dock/subscribe` returns human cards only.

* Work:
  Add the classifier and wire the first real stream slice through
  `RelayStateEngine.reconcileDock`.

* Checklist (must all be done):
  - Export or expose the existing source normalization needed from
    `scripts/dock-relay-source-filter.mjs`.
  - Add `scripts/dock-relay-human-thread-filter.mjs` with
    `classifyThreadOrigin`, `isHumanBaseThread`, `filterHumanBaseThreads`, and
    `threadSpawnParentIDFromSource`.
  - Cover accepted sources: `cli`, `vscode`, custom `atlas`, and custom
    `chatgpt`.
  - Cover rejected sources: `exec`, app-server/API, MCP, every sub-agent
    variant, memory/internal, unknown, missing source, contradictory source,
    thread-spawn parent evidence, `threadSource: subagent`,
    `threadSource: memory_consolidation`, `forkedFromId`, and
    `forked_from_id`.
  - Move or import shared thread-spawn parent extraction from diagnostic
    duplicate code into the classifier/source-policy layer.
  - Change Dock reconciliation so it does not call `ACTIVE_ALL_SOURCE_SCOPE`
    or equivalent explicit agent sourceKinds for normal Dock state.
  - Filter default interactive active rows defensively with
    `isHumanBaseThread`.
  - Ensure normalized Dock cards from this slice have `lane: "human"` and
    `sourceKind: "human"`.
  - Use self-documenting helper, fixture, and test names that say `humanBase`,
    `rejected`, `diagnosticAllSource`, or equivalent concrete terms where
    those concepts are the behavior.
  - Add one short boundary comment near the classifier if the source/fork/base
    logic is not self-evident.
  - Update this plan/reference doc if the implementation changes final
    classification or proof commands.
  - Update relay tests that currently expect combined/all-source Dock paging.

* Verification (required proof):
  - `rtk npm run test:relay`

* Docs/comments (propagation; only if needed):
  - Checklist owns required naming/comment/doc work. This section is only for
    extra touched stale comments discovered during implementation.

* Exit criteria (all required):
  - Classifier tests prove every accepted and rejected reason family.
  - `dock/subscribe` tests prove no all-source Dock fetch and no non-human
    stream card in the first Dock slice.
  - Existing human Dock ordering and live status overlay still work for human
    rows.
  - No normal Dock state test still treats all-source rows as required Dock
    output.
  - Boundary names and tests make the human-base policy obvious without
    opening this plan.

* Rollback:
  Revert the classifier and Dock reconciliation slice together. Do not leave a
  classifier that is unused by app-facing state.

## Phase 2 - Complete relay state, Archive, live leases, and cleanup

* Goal:
  Expand the proven relay slice across every stored/app-facing state surface:
  Dock store, Archive store, archive mutations, notification ingest, live
  leases, loaded-list rows, and `SessionRouter`.

* Work:
  Move filtering earlier than persistence and leasing, then delete stale
  rejected state so old non-human rows cannot leak through query paths.

* Checklist (must all be done):
  - Add cleanup helpers for rejected persisted cards and live leases, using
    existing normalized `lane` / `source_kind` fields for old rows.
  - Run cleanup at startup or first state use, and after successful
    reconciliation.
  - Gate `upsertThreadCard`, `applyDockReconciliation`, or their callers so
    non-human cards are not persisted as app-facing cards.
  - Make `listDockCards`, `listArchiveCards`, and `cardForThread` defensively
    human-only for app-facing callers.
  - Gate notification ingest and `handleArchiveMutation` so non-human archive
    changes are ignored or cleaned rather than published.
  - Make `archive/subscribe`, `archive/update`, and `archive/resync` return
    only human cards.
  - Filter live rows before `upsertLiveLease`.
  - Classify live rows before upstream `thread/read` when loaded-list/live data
    already contains enough source evidence; otherwise classify immediately
    after the read and before lease/router persistence.
  - Remove or expire existing live leases for rejected rows.
  - Make `SessionRouter.endpointForThread`, `SessionRouter.rowForThread`, and
    `SessionRouter.loadedThreadIDs` ignore/reject non-human live rows.
  - Make live lease expiry publication incapable of publishing a non-human
    card.
  - Name cleanup helpers so the code reads as deletion of rejected state, not a
    cosmetic view filter.
  - Update comments near relay state cleanup if they would otherwise imply
    non-human rows are merely hidden.
  - Update observability tests that hard-code `active:allSourceKinds` as a
    healthy app-facing Dock scope.

* Verification (required proof):
  - `rtk npm run test:relay`

* Docs/comments (propagation; only if needed):
  - Checklist owns required naming/comment work. This section is only for extra
    touched stale comments discovered during implementation.

* Exit criteria (all required):
  - Stored Dock and Archive cards exposed to app-facing callers are human-only.
  - Stale non-human cards and leases are deleted from relay app-facing state;
    query/listing guards are defense in depth, not a substitute for cleanup.
  - Archive mutation paths cannot create a visible non-human archive card.
  - Non-human live rows cannot create leases, loaded IDs, router endpoints, or
    stream updates.
  - Live collection avoids avoidable non-human `thread/read` calls when source
    evidence is already available before the read.
  - Diagnostic/oracle surfaces still have an explicit path to inspect
    all-source truth when requested.
  - Cleanup code and tests read as rejected-state deletion, not UI filtering.

* Rollback:
  Revert state cleanup and live/archive expansion as one phase. If rollback is
  needed after cleanup has run, the relay can repopulate human cards from raw
  app-server state.

## Phase 3 - Raw route, detail, resume, and focused-turn gates

* Goal:
  Close direct-ID and raw JSON-RPC side doors after state surfaces are
  human-only.

* Work:
  Add one route assertion path that resolves enough metadata to classify a
  thread ID, then rejects non-human IDs before returning, resuming, archiving,
  unarchiving, or forwarding focused turn commands.

* Checklist (must all be done):
  - Add a redacted typed rejection helper:
    `code: -32043`,
    `message: "thread rejected by human-only filter"`,
    `data: { threadId, reason }`.
  - Gate `thread/list` so phone/client paths cannot request agent sourceKinds
    and returned rows are human-only.
  - Gate `thread/search` so returned results are human-only.
  - Gate `thread/loaded/list` so returned IDs are human-only.
  - Gate `thread/read` before both live-row fast path and history fallback
    response.
  - Gate `thread/turns/list` by classifying the thread ID before requesting or
    returning turns.
  - Gate `thread/goal/get` by classifying the thread ID before returning goal
    state.
  - Gate `thread/resume` before making a new upstream binding; do not resume a
    rejected thread just to classify it.
  - Store accepted-thread state on the live session after successful resume.
  - Require accepted focused-thread state for `turn/start`, `turn/steer`, and
    `turn/interrupt` in addition to the existing thread-ID match.
  - Gate `thread/archive` and `thread/unarchive` before upstream mutation and
    before local archive mutation.
  - Gate `state/query` for app-facing use or explicitly mark it diagnostic-only
    with human-only app-facing snapshots.
  - Keep `relay/state/snapshot` all-source behavior diagnostic/oracle-only and
    prevent its output from feeding app-facing state.
  - Ensure upstream notifications and server requests after resume cannot
    resurrect or switch to a rejected thread.
  - Name route assertions and tests so it is obvious that direct thread IDs are
    human-only app-facing boundaries.
  - Update route comments/tests that describe `sourceKinds` as a caller-driven
    app-facing route feature.

* Verification (required proof):
  - `rtk npm run test:relay`

* Docs/comments (propagation; only if needed):
  - Checklist owns required naming/comment work. This section is only for extra
    touched stale comments discovered during implementation.

* Exit criteria (all required):
  - Every app-facing raw route either returns human data or throws `-32043`.
  - `state/query` cannot expose non-human rows to app-facing callers, and
    `relay/state/snapshot` all-source data is labeled diagnostic/oracle-only.
  - Sampled `exec`, sub-agent, unknown, missing-source, forked, and spawned
    child IDs are rejected from read, turns, goal, resume, archive, unarchive,
    and focused turn paths.
  - Existing human read, turns, goal, resume, archive, unarchive, and focused
    turn tests still pass.
  - No raw route logs prompt text, transcript text, raw payloads, or raw source
    blobs while rejecting.
  - Route helper and test names make direct-ID human-only boundaries obvious.

* Rollback:
  Revert raw route gates together. Do not leave partial gates where some
  direct-ID routes reject and others still forward.

## Phase 4 - Swift defensive filtering, pinned metadata, filters, and detail UX

* Goal:
  Make the Swift client fail closed if a relay bug, stale payload, preview, or
  local metadata row contains non-human data.

* Work:
  Add one Swift human-card guard and route Dock, Archive, projection, pinned
  metadata, filters, and restored detail behavior through it.

* Checklist (must all be done):
  - Add `isHumanAppFacingCard` or equivalent in one Swift state/DTO boundary.
  - Drop rejected cards during Dock snapshot/delta apply or before
    `ThreadCardTable` stores them.
  - Drop rejected cards during Archive snapshot loading/projection.
  - Log a redacted `DockLog` warning for dropped cards without prompt,
    transcript, token, or raw payload content.
  - Suppress or delete pinned cached snapshots with automation or unknown
    origin.
  - Prevent rejected stream cards from being pinned or cached.
  - Hide unavailable Agents/Unknown filter facets in normal Dock UX, or keep
    them only as legacy/test injection controls that cannot reveal rows.
  - Decode/surface relay `-32043` as a short unavailable detail state.
  - Clear rejected restored navigation state and do not call resume after
    rejection.
  - Update previews and scripted stream fixtures so normal visible rows are
    human-only and non-human cards exist only as rejection fixtures.
  - Update `.activeAgents` fixture/test support so it is rejection or legacy
    compatibility input, not normal production loading.
  - Use Swift helper/test names that make rejected-card dropping and
    human-only app-facing cards obvious without a reader opening this plan.
  - Update touched Swift comments/previews that describe automation rows as
    normal visible Dock rows.

* Verification (required proof):
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test --filter AppServerClientTests`

* Docs/comments (propagation; only if needed):
  - Checklist owns required naming/comment work. This section is only for extra
    touched stale comments discovered during implementation.

* Exit criteria (all required):
  - Rejected cards cannot enter Dock or Archive visible state.
  - Rejected pinned snapshots cannot create cached visible rows.
  - Search and filters cannot reveal rejected rows.
  - Restored/deep-linked rejected IDs show unavailable state and are not
    resumed.
  - Existing human-card rendering, pinning, archive restore, and detail flows
    still pass their tests.
  - Swift guard and test names make rejected-card dropping and human-only
    app-facing behavior obvious.

* Rollback:
  Revert Swift defensive filtering as one phase. If rollback is necessary,
  relay phases still keep production app-facing streams human-only.

## Phase 5 - Contracts, diagnostics, simulator, live proof, and docs sync

* Goal:
  Align proof tooling and documentation with the final invariant, then prove
  the behavior against controlled and live paths.

* Work:
  Keep schema compatibility while changing normal examples and proof
  expectations from "agent rows appear" to "non-human rows are rejected from
  client paths." Keep all-source truth available only as diagnostic/oracle
  evidence.

* Checklist (must all be done):
  - Update contract fixtures and generator output if contract files are touched.
  - Ensure normal contract fixtures for app-facing Dock/Archive cards are
    human-only.
  - Keep non-human contract/fixture examples only where they test rejection or
    decoder compatibility.
  - Update controlled simulator `spawn-edge` expectations so spawned child rows
    are absent from app-facing streams and rejected from direct client routes.
  - Update sync-audit/parity/fidelity/snapshot wording and checks that
    previously expected `dock/subscribe` to match active all-source rows.
  - Update `state/query` / `relay/state/snapshot` proof language so
    app-facing rows are human-only and all-source data is explicitly
    diagnostic/oracle-only.
  - Preserve explicit diagnostic all-source proof for rejected counts and
    source taxonomy.
  - Add `scripts/dock-relay-human-only-proof.mjs` and a Makefile target only if
    existing proof scripts cannot directly prove live human-only behavior.
  - Run service status checks before live proof.
  - Update this doc and the thread type reference only where implementation
    changes final classification or proof commands.
  - Update README, Makefile help, or runbook text only if a new proof command
    or changed verification command becomes part of the developer workflow.
  - Delete or rewrite touched stale comments/docs instead of preserving old
    behavior notes beside new truth.
  - Do not add broad narrative docs for the sake of it; update only docs that
    would otherwise become wrong or that explain a new command/surface.

* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk npm run contract:check` if contracts or generated DTOs changed.
  - `rtk make app-test SIM='iPhone 17'` if installed UI behavior, generated
    project wiring, or simulator UI proof changed.
  - `rtk make app-server-status`
  - `rtk make dock-relay-status`
  - Live human-only proof command or documented manual JSON-RPC proof if a new
    script is not added.

* Docs/comments (propagation; only if needed):
  - Checklist owns required doc work. This section is only for extra touched
    stale comments discovered during implementation.

* Exit criteria (all required):
  - Contract checks remain green when contract surfaces are touched.
  - Controlled proof treats rejected rows as expected absence from client paths.
  - Diagnostic proof can still count rejected rows without feeding app state.
  - Live proof shows no live leases for sampled rejected thread IDs.
  - Live proof shows Dock/Archive app-facing rows are all human and sampled
    rejected IDs fail `thread/read` and `thread/resume`.
  - Final docs match the implemented behavior and do not describe agent rows as
    normal Dock/Archive rows.

* Rollback:
  Revert proof/docs updates with the behavior they document. Do not leave proof
  scripts asserting human-only behavior if the implementation is rolled back.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

- Start with `rtk npm run test:relay` after relay classifier/state/route work.
- Run `rtk swift test --filter DockStoreTests` for Dock, Archive, filters,
  fixtures, and local metadata behavior.
- Run `rtk swift test --filter ThreadDetailStoreTests` for detail navigation,
  rejected IDs, and resume behavior.
- Run `rtk swift test --filter AppServerClientTests` for JSON-RPC rejection
  handling and route parameters.
- Run `rtk npm run contract:check` only if contracts, generated DTOs, or
  fixtures are changed.
- Run `rtk make app-test SIM='iPhone 17'` only when installed UI behavior,
  generated project wiring, or simulator proof paths are touched.
- Run `rtk make app-server-status` and `rtk make dock-relay-status` before live
  proof.
- Live proof must show no `lane: agent`, no `sourceKind: automation`, no
  unknown rows, no live leases for sampled rejected thread IDs, and `-32043`
  rejection for sampled rejected IDs through `thread/read` and `thread/resume`.
  The relay test suite must cover the broader direct-route matrix:
  `thread/turns/list`, `thread/goal/get`, archive/unarchive, and focused turn
  commands.

# 9) Rollout / Ops / Telemetry

- This is a local relay/app behavior change, not a Codex storage deletion.
- Existing non-human rows in relay state are cleanup targets, not migration
  sources.
- Diagnostic counts may be cached from the last explicit diagnostic run.
- The Dock stream must not carry rejected counts or rejected rows.
- Relay diagnostics must use `scripts/dock-relay-logger.mjs` and redacted data.
- Swift diagnostics must use `DockLog` and never include prompt text,
  transcript text, tokens, raw payloads, or source payload blobs.
- If physical device testing is required, use Makefile device targets and the
  documented relay-backed host path, not raw `xcodebuild` or direct `:4500`.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, helper blocks, direct-route coverage,
    live routing, cleanup semantics, diagnostic all-source separation,
    self-documenting-code requirements, and necessary docs updates.
- Findings summary:
  - Explorer 1 found that Phase 2 exit criteria softened required cleanup from
    deletion into "deleted or suppressed"; this contradicted Section 1.3.
  - Explorer 1 found final acceptance/verification summaries omitted the live
    direct-route rejection proof already required by Phase 5.
  - Explorer 2 found required self-documenting-code and doc-update work was
    partly stranded under `Docs/comments` instead of phase checklist/exit
    criteria.
  - Explorer 2 found Phase 5 did not explicitly carry the Section 8 live-lease
    absence proof.
- Integrated repairs:
  - Phase 2 exit criteria now require deletion from relay app-facing state;
    query/listing guards are explicitly defense in depth.
  - Section 0.4 and Section 8 now require sampled rejected `thread/read` and
    `thread/resume` rejection, plus relay test coverage for the broader
    direct-route matrix.
  - Self-documenting-code, comment, and necessary-doc obligations now appear in
    relevant phase checklists and exit criteria.
  - Phase 5 exit criteria now require live proof that sampled rejected IDs have
    no live leases.
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

- 2026-05-31 - User intent: classify "I started" as base/root interactive
  human-created threads and classify everything else holistically as not
  user-started for the Dock UX. The plan therefore rejects fresh-consult,
  model-consensus, sub-agent, exec, API, machine, missing, contradictory,
  forked, and spawned-child rows from app-facing surfaces.
- 2026-05-31 - Compatibility posture: preserve existing DTO enum values in the
  first implementation, but cleanly cut over app-facing stream behavior to
  `sourceKind == "human"` and `lane == "human"`.
- 2026-05-31 - Fresh consult round 1 identified blocking gaps around live
  routing, loaded-list/read fast paths, route audit harnesses, and stale
  `.activeAgents` expectations. Those gaps were patched into this plan.
- 2026-05-31 - Fresh consult round 2 returned `VERDICT: pass-with-notes`,
  `BLOCKING: none`, and `CONFIDENCE: high` for the pre-arch-step draft.
- 2026-05-31 - Reformat: converted the draft into the canonical arch-step
  scaffold in place so auto-plan receipts can govern the final planning pass.
- 2026-05-31 - Self-documenting-code and doc-update requirement: implementation
  should make the human-only policy obvious through explicit names, helper
  boundaries, rejection reasons, fixture/test names, and sparse comments only
  at non-obvious policy edges. Necessary docs updates are required when
  implementation changes public/developer truth; broad docs churn is not.
- 2026-05-31 - Fresh consult arch-plan signoff:
  `/tmp/fresh-consult/human-only-arch-plan-20260531TXpyA0J/final.txt`
  returned `VERDICT: pass-with-notes`, `BLOCKING: none`, and `CONFIDENCE:
  high`. Non-blocking notes about `state/query` / `relay/state/snapshot`
  diagnostic labeling and early live-row classification were folded into the
  plan before implementation.
- 2026-05-31 - Implementation completed: the relay enforces
  `isHumanBaseThread` across Dock state, Archive state, live leases, raw thread
  list/search/read/loaded/goal/turn/archive routes, resume, and focused turn
  forwarding. Swift now defensively drops non-human stream cards and refuses
  cached pinned rows without human display evidence.

# Appendix A) Classification Reference

Allowed `self_started` sources:

- `cli`
- `vscode`
- custom `atlas`
- custom `chatgpt`

Rejected sources:

- `exec`
- app-server/API
- MCP
- sub-agent
- sub-agent review
- sub-agent compact
- sub-agent thread-spawn
- sub-agent other
- memory/internal
- unknown
- missing source
- contradictory source metadata

Base-level means the thread is not a spawned child and not a fork.

Initial allow predicate:

```text
isHumanBaseThread(row) =
  normalizedSource(row) is cli, vscode, custom:atlas, or custom:chatgpt
  AND normalizedSource(row) is not unknown
  AND normalizedSource(row) is not internal
  AND normalizedSource(row) is not automation
  AND normalizedSource(row) is not subAgent
  AND row.threadSource/thread_source is not subagent
  AND row.threadSource/thread_source is not memory_consolidation
  AND row.source does not contain subAgent/thread_spawn evidence
  AND row.forkedFromId/forked_from_id is empty
```

# Appendix B) Conversion Notes

- The previous draft's Objective, Definition, Required Invariant, Relay Design,
  Swift Client Design, Contract Design, Harness and Verification Plan,
  Performance Acceptance Criteria, Implementation Phases, Rollout Notes, and
  Fresh Consult Gate were re-homed into the canonical arch-step sections.
- Instruction-bearing obligations were preserved as explicit invariants,
  call-site audit rows, phase obligations, verification bullets, rollout rules,
  and Appendix A classification rules.
- Auto-plan receipts now govern the final planning state. Appendix A preserves
  the compact classification rule; Sections 3-7 are the implementation source
  of truth.
