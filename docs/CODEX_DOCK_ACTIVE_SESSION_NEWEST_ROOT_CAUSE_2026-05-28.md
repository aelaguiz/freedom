---
title: "Codex Dock - Active Session Newest Ordering Fix - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md
  - README.md
---

# TL;DR

- Outcome: active Codex sessions that are changing right now keep their fresh
  `updatedAt` through the Dock relay and therefore appear at the top of the
  app's `Newest` list.
- Problem: the relay currently combines fresh history/list rows with stale
  live `thread/read includeTurns:false` rows by keeping the live row wholesale
  and dropping the history row for the same thread id.
- Approach: keep the live row as the canonical row for status, active flags,
  endpoint routing, and live-only metadata, but merge in fresher history/list
  activity timestamps for the same thread id before sorting and limiting the
  relay `thread/list` result.
- Plan: first encode the merge contract and regression test at the pure relay
  merge helper, then prove the real relay `thread/list` path with a mocked
  live/history WebSocket integration test, then run the relay test target and a
  local relay smoke check against `ws://127.0.0.1:4510/`.
- Non-negotiables: no Swift sort workaround, no extra timer or push stream, no
  phone-side backend change, no direct iPhone connection to raw `:4500`, no
  runtime shim, and no upstream Codex repo edit in this client-side fix.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: not required for this local relay merge fix
deep_dive_pass_2: done 2026-05-28
recommended_flow: research -> deep dive -> phase plan -> consistency-pass -> plan-audit -> auto-implement -> thermo-nuclear review -> tests
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:5bb0cd950b150cb26e526e23e34097b668645306f61561a1240aba09b932903f",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T23:07:21Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:10798abc84efbc4d2881b209b6bfaf8a71862b71ac4e618c6a1e48dfdb64cfd1",
      "completed_at": "2026-05-28T23:07:42Z",
      "doc_hash_after": "sha256:e30b4e8bbc1f8ae39a98350d97716d57a47b85e5d7ae504ceef07a0ddcdbf96e"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T23:07:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e30b4e8bbc1f8ae39a98350d97716d57a47b85e5d7ae504ceef07a0ddcdbf96e",
      "completed_at": "2026-05-28T23:08:32Z",
      "doc_hash_after": "sha256:43cb302f1496992f9c8e02ce1979ee83ab43fdf3a97fb14a20a943d2e1f004bd"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T23:08:38Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:43cb302f1496992f9c8e02ce1979ee83ab43fdf3a97fb14a20a943d2e1f004bd",
      "completed_at": "2026-05-28T23:08:50Z",
      "doc_hash_after": "sha256:a397e0e92ab7e8d02fa9d18f3781cb9c09293ff22d4411c10ed0f041a8cb96bc"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T23:08:55Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:a397e0e92ab7e8d02fa9d18f3781cb9c09293ff22d4411c10ed0f041a8cb96bc",
      "completed_at": "2026-05-28T23:09:22Z",
      "doc_hash_after": "sha256:940edcb11542fcc4db9930bf710b6c54b15e37ccd919477aecaf970989ef116b"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T23:09:28Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:940edcb11542fcc4db9930bf710b6c54b15e37ccd919477aecaf970989ef116b",
      "completed_at": "2026-05-28T23:13:02Z",
      "doc_hash_after": "sha256:cef3784f45a66596b5ce87b2b2e5191455b179825a7733394f9745e50ffe168d"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this plan is implemented, a relay `thread/list` response for a currently
loaded active thread uses the freshest known activity timestamp from either the
live row or the matching history/list row. If history reports
`updatedAt = 2026-05-28T22:42Z` for thread `T` and live `thread/read
includeTurns:false` reports stale `updatedAt = 2026-05-28T11:49Z` for that same
thread `T`, the relay returns one row for `T` whose status remains live/active
and whose `updatedAt` is the fresh `2026-05-28T22:42Z` value.

## 0.2 In scope

- Relay `thread/list` aggregation in `scripts/dock-relay-thread-data.mjs`.
- Pure merge behavior in `mergeThreadListRows`.
- Relay integration behavior through `startServer` and mocked history/live
  app-server WebSockets.
- Tests under `scripts/dock-relay*.test.mjs`.
- This diagnosis/plan document and its plan-audit/worklog/review companions as
  required by the requested workflow.
- Preservation of the existing Swift Dock projection behavior: Swift still maps
  `ThreadDTO.updatedAt` into `SessionSummary.lastActivity`, and
  `DockSessionProjection` still sorts by `lastActivityDate`.

## 0.3 Out of scope

- Editing `~/workspace/codex` upstream app-server or thread-store code.
- Changing the app's Branch/Newest/Idle UI controls.
- Adding a new backend subscription, timer, polling loop, push stream, or
  phone-side freshness repair.
- Changing app-server protocol method names or DTO shapes.
- Making the iPhone connect directly to raw authenticated `:4500`.
- Changing archive semantics. Archived `thread/list` must continue to skip live
  loopback merging.
- Persistence, telemetry schema changes, or screenshot-golden UI tests.

## 0.4 Definition of done (acceptance evidence)

- `mergeThreadListRows` returns one row per thread id when history and live
  contain the same id.
- For same-id rows, live status and live endpoint routing metadata are
  preserved internally until sanitization, but the returned client row uses the
  fresher activity timestamp.
- A fresher history row can move a live active row ahead of other live rows in
  relay sorting.
- An older history row cannot downgrade a fresher live row.
- History-only rows still fill the list after live rows according to the
  existing relay limit policy.
- `dockRelaySource` is never returned to the app.
- Archived `thread/list` still does not merge live loopback rows.
- Focused Node relay tests cover the pure merge contract and the real
  relay-server `thread/list` path.
- `rtk npm run test:relay` passes.
- A local relay smoke query to `ws://127.0.0.1:4510/` shows active rows can be
  returned with fresh relay-visible timestamps when the backend is available.

## 0.5 Key invariants (fix immediately if violated)

- The relay merge path, not Swift UI code, owns reconciliation between stale
  live metadata and fresh history/list metadata.
- The live row remains authoritative for loaded status, active flags, and live
  endpoint routing.
- The newest timestamp is monotonic across same-id live/history rows: merging
  must never replace a fresher row timestamp with an older one.
- The merge is deterministic and side-effect free.
- The app receives sanitized rows only; relay-only endpoint metadata stays
  private.
- The relay keeps the existing fail-soft source policy: history and live are
  queried independently, and either side can still provide rows if the other
  side fails.
- No fallback runtime path or duplicate sorting layer is introduced.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Preserve the true freshest activity timestamp for active loaded sessions.
2. Keep live status and endpoint ownership intact.
3. Keep the fix local to the existing relay merge owner.
4. Avoid extra upstream calls, timers, or Swift-side compensating logic.
5. Preserve existing relay behavior when history or live discovery fails.
6. Keep tests behavior-level and tied to the bug.

## 1.2 Constraints

- The simulator and phone normally connect to the relay at
  `ws://192.168.50.117:4510`, not directly to raw `ws://127.0.0.1:4500`.
- The relay already fetches both history rows and live rows for normal
  unarchived `thread/list`.
- Live rows are currently built from `thread/loaded/list` plus
  `thread/read includeTurns:false`; this is where stale timestamps enter the
  relay.
- Swift correctly sorts by the timestamp it receives. A Swift-only fix would
  duplicate relay responsibility and still leave relay clients wrong.
- The existing relay tests assert that live rows stay inside the relay limit
  before history-only fill rows.

## 1.3 Architectural principles (rules we will enforce)

- Reconcile same-thread facts at the relay boundary before client sorting.
- Prefer the data already fetched by the relay over adding another upstream
  request path.
- Preserve source ownership: history can provide freshness, live can provide
  status and routing.
- Preserve existing failure isolation between history and live collection.
- Use one merge helper for both pure tests and the relay server path.
- Prove behavior with Node relay tests, not UI screenshots or doc grep gates.

## 1.4 Known tradeoffs (explicit)

- This client-side fix does not repair the upstream Codex `thread/read
  includeTurns:false` timestamp regression. It makes the Dock relay robust
  against that known upstream behavior using data the relay already has.
- The existing live-first limit policy remains in place. This plan fixes stale
  timestamps for matching live/history ids without redesigning relay paging.
- If a live row has no matching history row, the relay cannot synthesize a
  fresher timestamp without adding another upstream source. That is out of
  scope for this fix.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The simulator is talking to the real relay-backed backend. The bad list order is
not a mock-data, disconnected-simulator, Idle-filter, or OpenAI-account problem.

The relay builds normal unarchived `thread/list` from two sources:

1. history `thread/list` on the configured raw app-server, with bearer auth
2. discovered live loopback app-server rows, currently from `thread/loaded/list`
   plus `thread/read includeTurns:false`

Swift maps `ThreadDTO.updatedAt ?? ThreadDTO.createdAt` to
`SessionSummary.lastActivity` and `DockSessionProjection` sorts `Newest` rows by
`lastActivityDate` descending.

## 2.2 What's broken / missing (concrete)

The smoking-gun root cause is a timestamp regression in the live-row path:

1. Codex itself has the correct current timestamp in `thread/list` and
   `~/.codex/state_5.sqlite`.
2. Codex `thread/read` for the same loaded active thread returns an old
   `updatedAt` equal to the thread creation time.
3. The Dock relay builds live rows by calling `thread/read includeTurns:false`,
   so it receives the stale timestamp.
4. The relay then de-duplicates by thread id and drops the fresh history/list
   row for that same active thread.
5. Dock sorts by that stale `updatedAt`, so active sessions receiving messages
   right now sort below newer `notLoaded` rows that render as `Limited`.

At `2026-05-28T22:42:51Z`, direct calls showed the same thread with two
different timestamps depending on which Codex API path was used.

For active thread `019e6e6a-d156-7d03-85b1-c49a55539c90`:

| Source | Status | `updatedAt` | Meaning |
| --- | --- | --- | --- |
| `/Users/aelaguiz/.codex/state_5.sqlite` | local truth | `2026-05-28T22:42:27Z` | State DB knows this thread is current. |
| JSONL file mtime | local truth | `2026-05-28T22:42:23.585Z` | The rollout file is being written right now. |
| JSONL latest line timestamp | local truth | `2026-05-28T22:42:23.584Z` | The active session is receiving new events. |
| Raw history `thread/list` on `ws://127.0.0.1:4500/` | `notLoaded` | `2026-05-28T22:42:48Z` | The list endpoint correctly puts this row at the top. |
| Live endpoint `thread/list` on `ws://127.0.0.1:58764` | `active` | `2026-05-28T22:43:22Z` | The live app-server list endpoint also sorts it first. |
| Live endpoint `thread/read includeTurns:false` on `ws://127.0.0.1:58764` | `active` | `2026-05-28T11:49:14Z` | The read endpoint incorrectly reports the creation time as last activity. |
| Relay `thread/list` on `ws://127.0.0.1:4510/` | `active` | `2026-05-28T11:49:14Z` | The relay kept the stale live read row and dropped the fresh history/list row. |

For active thread `019e7001-4ab8-7842-a327-89e0da6a5877`, the same pattern
reproduced:

| Source | Status | `updatedAt` |
| --- | --- | --- |
| `/Users/aelaguiz/.codex/state_5.sqlite` | local truth | `2026-05-28T22:42:26Z` |
| JSONL latest line timestamp | local truth | `2026-05-28T22:42:23.592Z` |
| Raw history `thread/list` | `notLoaded` | `2026-05-28T22:42:46Z` |
| Live endpoint `thread/read includeTurns:false` | `active` | `2026-05-28T19:13:13Z` |
| Relay `thread/list` | `active` | `2026-05-28T19:13:13Z` |

## 2.3 Constraints implied by the problem

- The current active sessions do show up in the data plane. The fix is not
  discovery, account, Idle filter, or simulator connectivity.
- The relay sees both useful facts for same-id rows: fresh history timestamp
  and live active status.
- The relay must merge those facts instead of choosing one whole row and
  discarding the other.
- The fix must preserve relay endpoint metadata until preview enrichment and
  detail routing are done, then sanitize before returning data to Swift.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- No external standard is needed. This is a local relay data-reconciliation
  bug with enough runtime and code evidence in the repo. External research
  would add ceremony without changing the design.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors:
  - `scripts/dock-relay-thread-data.mjs`:
    - `readLoadedRows` calls `thread/loaded/list`, then
      `thread/read { includeTurns: false }` for each loaded id. This is where
      the stale live `updatedAt` enters the relay.
    - `aggregateThreadList` already reads history `thread/list` and live rows
      in parallel for normal unarchived lists.
    - `mergeThreadListRows` is the first existing owner that has both same-id
      rows at once, so it is the canonical place to reconcile liveness and
      freshness.
    - `sanitizeRelayFields` removes `dockRelaySource` before rows are returned
      to phone clients.
  - `scripts/dock-relay.mjs` re-exports `mergeThreadListRows`, so the pure
    helper can be tested directly without a second test-only API.
  - `scripts/dock-relay.test.mjs` already has pure relay merge tests for source
    filtering, live-priority limit behavior, and relay-field sanitization.
  - `scripts/dock-relay-phase5.test.mjs` already has mocked history/live
    WebSocket app-server tests using `spawnLoopbackAppServerMarker`,
    `startServer`, and `jsonRpcRequest`.
  - `CodexDock/Models/SessionSummaryMapper.swift` maps
    `thread.updatedAt ?? thread.createdAt` into `SessionSummary.lastActivity`.
  - `CodexDock/State/DockSessionProjection.swift` sorts `Newest` rows by
    `lastActivityDate` descending. This confirms Swift is using the DTO value
    it receives instead of inventing the bad order.
- Canonical path / owner to reuse:
  - `scripts/dock-relay-thread-data.mjs::mergeThreadListRows` owns row
    reconciliation for `thread/list`.
  - `scripts/dock-relay-thread-data.mjs::aggregateThreadList` owns the normal
    unarchived relay list flow and should keep calling the same merge helper.
- Adjacent surfaces tied to the same contract family:
  - `scripts/dock-relay.test.mjs` must pin the pure same-id merge contract.
  - `scripts/dock-relay-phase5.test.mjs` must pin the real relay server path
    because the bug happened across history/live source aggregation, not only
    in a local sort helper.
  - `README.md` already says the relay merges live loaded rows over stored
    history and that `Newest` is a flat newest-first list. It does not require
    a wording change unless implementation changes those claims.
  - `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md` remains the
    Swift projection plan and stays out of this code change.
  - `~/workspace/codex/...` upstream code explains why `thread/read
    includeTurns:false` can be stale, but this client repo does not own that
    upstream bug.
- Compatibility posture (separate from `fallback_policy`):
  - Preserve the existing relay `thread/list` contract and row shape. The fix
    changes row correctness for duplicate live/history ids; it does not add
    fields, remove fields, change method names, or require a client migration.
- Existing patterns to reuse:
  - Use the existing pure helper plus exported test pattern in
    `scripts/dock-relay.test.mjs`.
  - Use the existing fake WebSocket app-server integration pattern in
    `scripts/dock-relay-phase5.test.mjs`.
  - Use relay logger paths only if diagnostics are needed; this plan does not
    require new logging.
- Duplicate or drifting paths relevant to this change:
  - Swift UI sorting is not a duplicate owner and must not become one.
  - Live endpoint `thread/list` also showed fresh timestamps in the diagnosis,
    but adding that call is unnecessary because history `thread/list` is
    already fetched in the normal relay path.
- Capability-first opportunities before new tooling:
  - Not applicable. This is deterministic relay data reconciliation, not an
    agent or model-facing behavior.
- Behavior-preservation signals already available:
  - `rtk npm run test:relay` covers the relay scripts.
  - Existing tests already cover archived-list live exclusion, source filtering,
    history failure fallback, live failure fallback, preview enrichment, and
    `thread/read` live routing.

## 3.3 Decision gaps that must be resolved before implementation

- None. The owner path, timestamp source, compatibility posture, upstream
  boundary, source filtering boundary, and proof path are all resolved from the
  diagnosis, repo code, existing tests, and the user's requested fix.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `scripts/dock-relay-thread-data.mjs` owns relay-side thread aggregation,
  live endpoint discovery, history reads, row merging, preview enrichment,
  detail endpoint routing, and archive/unarchive forwarding.
- `scripts/dock-relay.mjs` owns server startup and JSON-RPC method dispatch,
  then re-exports selected helper functions for tests.
- `scripts/dock-relay.test.mjs` owns pure relay helper tests.
- `scripts/dock-relay-phase5.test.mjs` owns integration-style relay tests with
  fake history/live WebSocket app-servers and loopback process markers.
- `CodexDock/Models/SessionSummaryMapper.swift` and
  `CodexDock/State/DockSessionProjection.swift` consume the relay DTO
  timestamp. They do not own live/history timestamp reconciliation.

## 4.2 Control paths (runtime)

Normal unarchived `thread/list` currently flows as:

```text
phone/simulator
  -> Dock relay `thread/list`
  -> aggregateThreadList(config, params)
       -> readHistoryThreadList(config, params)
            -> history app-server `thread/list`
       -> collectLiveRows()
            -> discoverLoopbackEndpoints()
            -> readLoadedRows(endpoint)
                 -> live app-server `thread/loaded/list`
                 -> live app-server `thread/read includeTurns:false`
       -> source-filter live rows
       -> build endpointByThreadId from live rows
       -> mergeThreadListRows(historyRows, filteredLiveRows, params)
       -> enrichThreadListPreviews(...)
       -> return sanitized rows
```

Current duplicate-id behavior:

```text
history row: id=T, status=notLoaded, updatedAt=fresh
live row:    id=T, status=active,    updatedAt=stale
        ↓
mergeThreadListRows computes liveIds={T}
        ↓
historyOnlyRows filters out id=T
        ↓
sortedLiveRows returns the stale live row
```

Archived `thread/list` is intentionally different: when `params.archived ===
true`, `shouldCollectLiveRowsForThreadList` returns false and the relay reads
history only.

## 4.3 Object model + key abstractions

- `Thread` rows are plain JavaScript objects matching app-server DTO shape.
- `statusPriority(thread)` sorts attention-active rows before plain active,
  then idle, error, unknown, and notLoaded.
- `rowTimestamp(thread)` currently returns
  `Number(thread?.updatedAt ?? thread?.createdAt ?? 0)`.
- `preferThread(candidate, existing)` is live-vs-live de-duplication. It
  prefers higher status priority first, then newer timestamp. It is not the
  right abstraction for live-vs-history fusion because history can have the
  freshness while live has the correct status and endpoint ownership.
- `dockRelaySource` is internal metadata that points a live thread at the
  upstream endpoint. It is needed for preview enrichment and detail routing but
  must be removed by `sanitizeRelayFields` before returning rows to clients.

## 4.4 Observability + failure behavior today

- `aggregateThreadList` reads history and live rows with `Promise.allSettled`.
  If one side fails, the other can still provide rows.
- If both history and live fail, the relay throws a combined failure.
- Existing logs summarize row counts and endpoint failures with
  `thread_list.loaded`.
- No existing log exposes full JSON-RPC payloads or secrets for this path, and
  this fix does not require new logging.

## 4.5 UI surfaces (ASCII mockups, if UI work)

No UI change is planned.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- `scripts/dock-relay-thread-data.mjs` gains one small pure helper for
  same-id live/history row reconciliation.
- `mergeThreadListRows` calls that helper before sorting live rows and before
  removing history-only duplicates.
- `scripts/dock-relay.test.mjs` gains pure merge tests.
- `scripts/dock-relay-phase5.test.mjs` gains one integration test for the
  diagnosed relay path.
- No Swift, package manifest, project config, or app UI files are expected to
  change for this fix.

## 5.2 Control paths (future)

Normal unarchived `thread/list` keeps the same high-level flow, but same-id
history/live rows are fused before sorting:

```text
history rows + filtered live rows
        ↓
historyById indexes valid history ids
        ↓
live rows map through mergeLiveRowWithHistoryFreshness(live, historyById[id])
        ↓
freshened live rows sort by rowTimestamp
        ↓
historyOnlyRows excludes ids present in freshened live rows
        ↓
returned rows preserve live status and fresh activity timestamps
```

## 5.3 Object model + abstractions (future)

The target helper contract:

```text
mergeLiveRowWithHistoryFreshness(liveRow, historyRow)
```

Required behavior:

- If no matching history row exists, return the live row unchanged.
- Compute the live activity timestamp with the existing `rowTimestamp(liveRow)`.
- Compute the history activity timestamp with the existing
  `rowTimestamp(historyRow)`.
- If the history timestamp is not finite or is less than or equal to the live
  timestamp, return the live row unchanged.
- If the history timestamp is newer, return a new row that preserves the live
  row's fields but sets `updatedAt` to the fresh history activity timestamp.
- Preserve live `status`, `activeFlags`, `source`, `threadSource`,
  `dockRelaySource`, and other live-only routing facts.
- Do not mutate either input row.

This deliberately copies the freshness field, not the whole history row. A
whole-history replacement would lose live status and routing. A generic field
overlay would add ambiguity about which side owns each field.

Pass 2 hardening: the helper should not copy display/list fields such as
`preview`, `name`, `cwd`, `gitInfo`, or `sessionId` as part of this fix. The
diagnosed failure is `updatedAt`; preview freshness is already handled by
`enrichThreadListPreviews`, and broad field overlay would create a new
ownership matrix without proving a needed behavior.

## 5.4 Invariants and boundaries

- Canonical owner path:
  `scripts/dock-relay-thread-data.mjs::mergeThreadListRows`.
- Compatibility posture:
  preserve the existing `thread/list` row shape and relay API.
- Fallback policy:
  forbidden. This is a deterministic merge correction, not a runtime fallback.
- Source filtering:
  `aggregateThreadList` continues to filter live rows by `sourceKinds` before
  merging and sanitizing.
- Limit policy:
  live rows still occupy the relay limit before history-only fill rows, but
  duplicate live/history ids produce one slot, not two.
- Archived lists:
  unchanged and history-only.
- Secrets:
  no new secret handling and no raw payload logging.

## 5.5 UI surfaces (ASCII mockups, if UI work)

No UI change is planned. The visible effect is that existing `Newest` sorting
receives a correct relay `updatedAt`.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Relay merge | `scripts/dock-relay-thread-data.mjs` | `mergeThreadListRows` | Drops same-id history rows whenever live row exists, even if history timestamp is fresher | Build `historyById`, freshen matching live rows, then sort/sanitize as today | This is the exact place where fresh history and live status meet | Same client row shape; same-id live rows may borrow fresher `updatedAt` | `scripts/dock-relay.test.mjs`, `scripts/dock-relay-phase5.test.mjs` |
| Relay merge helper | `scripts/dock-relay-thread-data.mjs` | new private helper | No live/history fusion helper exists | Add pure `mergeLiveRowWithHistoryFreshness`-style helper | Keeps the merge rule explicit and testable through `mergeThreadListRows` | Helper is internal; no exported API required | Pure merge tests |
| Relay source filter | `scripts/dock-relay-thread-data.mjs` | `aggregateThreadList` live filter before merge | Filters live rows before `mergeThreadListRows` | Preserve | Avoids widening the user-visible source scope | No change | Existing source filter tests plus new integration test |
| Relay preview/detail routing | `scripts/dock-relay-thread-data.mjs` | `endpointByThreadId`, `enrichThreadListPreviews`, `endpointForThread` | Depends on `dockRelaySource` before sanitization | Preserve `dockRelaySource` on freshened live rows until sanitization | Avoid breaking live detail/turn routing | Internal-only metadata preserved | Existing phase5 tests |
| Pure tests | `scripts/dock-relay.test.mjs` | merge tests near existing `mergeThreadListRows` coverage | Tests source filtering, sanitization, and live-limit fill behavior but not duplicate freshness | Add same-id timestamp fusion, no-downgrade, active-flag preservation, duplicate slot, and live ordering cases | Prevents the exact regression from returning | Existing helper export only | `rtk npm run test:relay` |
| Integration tests | `scripts/dock-relay-phase5.test.mjs` | mocked history/live relay tests | Covers source filtering and one-side failure paths | Add one test where history row is fresh `notLoaded`, live row is stale `active`, and relay returns active with fresh timestamp | Proves the real JSON-RPC path, not only a helper | No protocol change | `rtk npm run test:relay` |
| Swift mapping | `CodexDock/Models/SessionSummaryMapper.swift` | `thread.updatedAt ?? thread.createdAt` | Correctly maps relay timestamp into app model | No change | Swift should not compensate for stale relay DTOs | Preserve | Existing Swift tests are not the focused gate |
| Swift projection | `CodexDock/State/DockSessionProjection.swift` | `rowPrecedesByRecency` | Correctly sorts by `lastActivityDate` | No change | Sorting is already correct for correct timestamps | Preserve | Existing Dock projection tests remain sufficient |
| Root-cause plan doc | `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md` | full doc | Diagnosis-only document | Keep it as canonical plan, audit, implementation, and review ledger for this fix | User requested this path as the fix plan | Canonical arch-step artifact | Plan-audit and implementation audit |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  `scripts/dock-relay-thread-data.mjs::mergeThreadListRows`.
- Deprecated APIs:
  none.
- Delete list:
  none. The fix replaces no live code path and adds no compatibility shim.
- Adjacent surfaces tied to the same contract family:
  relay helper tests and relay server tests move now; Swift projection stays
  intentionally unchanged; upstream Codex stays explicitly out of scope.
- Compatibility posture / cutover plan:
  preserve existing relay method names, response shape, source filtering,
  archived-list behavior, and live-first limit policy.
- Capability-replacing harnesses to delete or justify:
  none.
- Live docs/comments/instructions to update or delete:
  this document is updated. `README.md` already describes newest-first and
  relay merge behavior at the level needed for this fix.
- Behavior-preservation signals for refactors:
  `rtk npm run test:relay`.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Relay list merge | `mergeThreadListRows` | same-id fact fusion at relay boundary | Prevents Swift and relay from developing competing freshness rules | include |
| Swift Dock projection | `DockSessionProjection` | use relay-provided `lastActivityDate` only | Prevents UI workaround drift | exclude from code changes |
| Upstream Codex timestamp bug | `~/workspace/codex/...` | upstream `thread/read` should eventually preserve fresh metadata | The real upstream bug remains documented but is not required for client fix | defer outside this repo |
| Live endpoint `thread/list` | discovered app-server endpoint | extra live list call as alternate freshness source | Adds network cost and failure modes for data already available from history | exclude |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

## Pre-Implementation Gate - Plan audit and readiness

Status: COMPLETE

Completed work:

- `$plan-audit` produced
  `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_PLAN_AUDIT.md`
  with verdict `ready`.
- `arch_stage_gate.py ready` returned `READY next=implement-loop`.

* Goal:
  - Satisfy the requested `$plan-audit` gate and prove the canonical plan is
    ready before any code changes.
* Work:
  - Audit this file as the plan artifact and repair all blocking findings
    before running `$arch-step auto-implement`.
* Checklist (must all be done):
  - Run `$plan-audit` against this plan.
  - Create/update
    `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_PLAN_AUDIT.md`.
  - Resolve every blocking plan-audit finding in this plan before editing code.
  - Run
    `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`
    and require it to pass.
* Verification (required proof):
  - Plan audit verdict is `ready`.
  - Stage-gate readiness exits 0.
* Docs/comments (propagation; only if needed):
  - Update this plan and its plan-audit sidecar only.
* Exit criteria (all required):
  - No blocking plan-audit findings remain.
  - The stage gate reports the doc is ready for `implement-loop` /
    `auto-implement`.
  - No code files have been edited before this gate is satisfied.
* Rollback:
  - Repair or revert only the planning/audit doc edits from this gate.

## Phase 1 - Pure relay merge contract

Status: COMPLETE

Completed evidence:

- `scripts/dock-relay-thread-data.mjs` now builds a same-id history map in
  `mergeThreadListRows`, freshens live rows before sorting, and only overwrites
  `updatedAt` when history has a fresher timestamp.
- `scripts/dock-relay.test.mjs` covers fresher-history wins, older-history does
  not downgrade live, duplicate same-id rows consume one slot, live status and
  source survive, and `dockRelaySource` stays sanitized.
- Final focused check: `rtk npm run test:relay` passed with `51` tests,
  `51` pass, `0` fail, `duration_ms 7520.262041`.

* Goal:
  - Make `mergeThreadListRows` preserve live status/routing while borrowing
    fresher same-id history activity timestamps.
* Work:
  - Add the smallest internal helper needed in
    `scripts/dock-relay-thread-data.mjs` and prove it through the exported
    `mergeThreadListRows` helper.
* Checklist (must all be done):
  - Add a pure same-id freshness helper in
    `scripts/dock-relay-thread-data.mjs`.
  - Build `historyById` inside `mergeThreadListRows`.
  - Freshen live rows before sorting live rows.
  - Preserve the existing history-only fill behavior after live rows.
  - Preserve `sanitizeRelayFields` behavior so `dockRelaySource` does not leak
    to returned rows.
  - Add pure tests in `scripts/dock-relay.test.mjs` covering:
    - fresher history `updatedAt` wins for same-id live/history rows
    - live status and active flags survive
    - older history cannot downgrade live timestamp
    - duplicate same-id rows consume one returned row slot
    - matching history timestamps reorder live rows by freshness
    - live rows without matching history stay unchanged except sanitization
* Verification (required proof):
  - `rtk npm run test:relay` must pass before the phase can be marked complete.
* Docs/comments (propagation; only if needed):
  - Add no comment unless the helper name and tests are insufficient to explain
    why history can update only the activity timestamp.
* Exit criteria (all required):
  - `mergeThreadListRows` returns a single active row with fresh `updatedAt`
    for the diagnosed same-id stale-live/fresh-history case.
  - The active row keeps live `status.type`, active flags, `source`, and
    internal `dockRelaySource` until sanitization.
  - The client-visible row does not include `dockRelaySource`.
  - Existing live-first limit behavior remains true for history-only rows.
  - No Swift file changes are needed for this phase.
* Rollback:
  - Revert only the helper/local merge change and its tests.

## Phase 2 - Real relay `thread/list` regression proof

Status: COMPLETE

Completed evidence:

- `scripts/dock-relay-phase5.test.mjs` now has
  `relay thread/list preserves active status with fresher history timestamp`.
- The test proves the real relay `thread/list` path returns one active row with
  fresh history `updatedAt`, strips `dockRelaySource`, preserves active flags,
  and keeps same-thread `thread/turns/list` routed to the live endpoint.
- Final focused check: `rtk npm run test:relay` passed with `51` tests,
  `51` pass, `0` fail, `duration_ms 7520.262041`.

* Goal:
  - Prove the real relay JSON-RPC path returns a fresh active row when history
    is fresh and live `thread/read includeTurns:false` is stale.
* Work:
  - Add one integration-style relay test using the existing fake history/live
    WebSocket app-server pattern.
* Checklist (must all be done):
  - Add a `scripts/dock-relay-phase5.test.mjs` test where:
    - fake history `thread/list` returns id `T` with `status.notLoaded` and
      fresh `updatedAt`
    - fake live `thread/loaded/list` returns id `T`
    - fake live `thread/read includeTurns:false` returns id `T` with
      `status.active` and stale `updatedAt`
    - relay `thread/list` returns one row for `T`
  - Assert returned row `status.type === "active"`.
  - Assert returned row `updatedAt` equals the fresh history timestamp.
  - Assert returned data does not include duplicate `T` rows.
  - Assert returned data does not include `dockRelaySource`.
* Verification (required proof):
  - `rtk npm run test:relay` must pass.
* Docs/comments (propagation; only if needed):
  - Update this plan/worklog with test evidence during implementation.
* Exit criteria (all required):
  - The mocked end-to-end path reproduces the bug before the fix and passes
    after the fix.
  - The test uses existing relay test helpers rather than a new harness.
  - Source filtering, archived list behavior, and one-side failure tests remain
    unchanged and passing.
* Rollback:
  - Revert the integration test and Phase 1 code/test change together.

## Phase 3 - Post-implementation review and runtime smoke

Status: COMPLETE

Completed evidence:

- Worklog:
  `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_WORKLOG.md`.
- Thermo-nuclear review:
  `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_THERMONUCLEAR_REVIEW.md`.
- Runtime smoke through `ws://127.0.0.1:4510/` found `100` relay rows,
  `100` history rows, `2` active duplicate rows, and `0`
  `staleActiveDuplicates`.
- Final focused check: `rtk npm run test:relay` passed with `51` tests,
  `51` pass, `0` fail, `duration_ms 7520.262041`.
- Final status check: `rtk make dock-relay-status` returned `status: "ready"`
  with raw app-server `:4500` and Dock relay `:4510` active.

* Goal:
  - Complete the requested workflow after implementation: truthful worklog
    evidence, thermo-nuclear review, focused tests, and runtime proof.
* Work:
  - Keep `DOC_PATH` and `WORKLOG_PATH` truthful while running the proof gates.
* Checklist (must all be done):
  - Create/update
    `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_WORKLOG.md`
    with implementation evidence.
  - Run the `$thermo-nuclear-code-quality-review` quality pass on the actual
    implementation and record the result.
  - Run `rtk npm run test:relay`.
  - Run a local relay smoke query against `ws://127.0.0.1:4510/` when the relay
    is available and check for active rows whose relay-visible `updatedAt`
    reflects fresh activity rather than stale creation time.
* Verification (required proof):
  - `rtk npm run test:relay` passes.
  - The local relay smoke query either demonstrates active rows with fresh
    relay-visible `updatedAt` or records the exact backend/service blocker that
    prevents that proof.
  - The implementation audit block says `Verdict (code): COMPLETE`.
* Docs/comments (propagation; only if needed):
  - Update this doc's implementation audit block and worklog.
  - Do not broaden README or Swift docs unless implementation changes those
    surfaces, which this plan does not expect.
* Exit criteria (all required):
  - Thermo-nuclear review has no unresolved structural blockers.
  - Focused relay tests pass.
  - Runtime smoke evidence specifically addresses active-row timestamp
    freshness through `ws://127.0.0.1:4510/`, or an exact external blocker is
    named.
  - No unrelated dirty worktree changes are reverted, staged, or normalized.
* Rollback:
  - Revert only files touched by this implementation pass.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Unit tests (contracts)

- Add focused Node tests for `mergeThreadListRows` covering same-id timestamp
  fusion, no timestamp downgrade, limit behavior, and sanitization.

## 8.2 Integration tests (flows)

- Add a relay-server test with mocked history and live WebSocket app-servers:
  history `thread/list` returns a fresh `notLoaded` row, live
  `thread/read includeTurns:false` returns the same id as stale `active`, and
  relay `thread/list` returns one active row with the fresh timestamp.

## 8.3 E2E / device tests (realistic)

- Run `rtk npm run test:relay`.
- Run a local relay smoke query against `ws://127.0.0.1:4510/` when services
  are up.
- Simulator UI proof is useful but not required for code completion because
  this fix is a relay data contract and the Swift sort path is already covered
  by existing Dock projection tests.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

- Ship as a relay-only code change. No project generation, signing, app target,
  or Info.plist changes are planned.
- Existing `rtk make services` users pick up the fix after the relay process is
  restarted or relaunched by the normal service flow.

## 9.2 Telemetry changes

- No new telemetry is required.
- Existing `thread_list.loaded` logging remains sufficient because this fix
  changes row correctness, not service health accounting.

## 9.3 Operational runbook

- Check service health with `rtk make app-server-status` and
  `rtk make dock-relay-status`.
- Avoid stopping services unless verification specifically requires a restart.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: Euclid, Harvey, self-integrator.
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, planning receipts, phase obligations,
    relay owner path, Swift no-change boundary, verification, rollout, and
    decision log.
- Findings summary:
  - Product architecture is coherent: the fix belongs in relay
    `mergeThreadListRows`, not Swift, not an upstream `thread/list` call, and
    not a runtime shim.
  - Three workflow/wording issues were repaired before implementation:
    pre-implementation plan-audit gate placement, smoke-proof specificity, and
    helper-vs-inline branchiness.
- Integrated repairs:
  - Added a `Pre-Implementation Gate - Plan audit and readiness` before code
    phases.
  - Removed "or equivalent local logic" so Phase 1 requires the helper chosen
    by Section 5.
  - Strengthened Phase 3 smoke proof to require active-row timestamp freshness
    through `ws://127.0.0.1:4510/` or an exact blocker.
  - Aligned the workflow wording on `$arch-step auto-implement`.
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

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit

Verdict (code): COMPLETE

Reviewed at: 2026-05-28T23:22:21Z

Scope:

- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay.test.mjs`
- `scripts/dock-relay-phase5.test.mjs`
- Verification artifacts for this plan/worklog/review

Plan conformance:

- Relay owner path used: `mergeThreadListRows` in
  `scripts/dock-relay-thread-data.mjs`.
- Same-id duplicate rows return one live row, preserving live status, source,
  active flags, and internal routing metadata until sanitization.
- Only fresher history activity time is copied into the live row by setting
  `updatedAt`; no broad field overlay was added.
- History-only fill and live-first limit behavior remain in the same merge
  path.
- Archived `thread/list` remains history-only.
- No Swift, DTO, protocol, upstream Codex, timer, push stream, or extra live
  `thread/list` call was added for this fix.

Proof:

- `rtk npm run test:relay` passed with `51` tests, `51` pass, `0` fail,
  `duration_ms 7520.262041`.
- Runtime smoke through `ws://127.0.0.1:4510/` returned `activeDuplicates: 2`
  and `staleActiveDuplicates: 0`.
- `rtk make dock-relay-status` returned `status: "ready"` after the relay
  process was reloaded.
- Thermo-nuclear review has no unresolved structural blockers.

Open findings:

- None.

Notes:

- `rtk make dock-relay-restart` did restart the launchd services but its
  `host-service-wait` step hit an existing host-service restart issue after
  `bootout`; direct `launchctl bootstrap` of the two generated plists restored
  both services. This is recorded as operational evidence, not part of this
  relay merge fix.
- The worktree had many unrelated dirty and untracked files before this
  implementation; this pass did not revert, stage, or normalize them.
<!-- arch_skill:block:implementation_audit:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Use relay merge freshness instead of Swift workaround

Context

The root-cause evidence shows Swift sorting is using the stale timestamp that
the relay returns. The relay already has both live and history rows during
normal `thread/list` aggregation.

Options

- Patch Swift `Newest` sorting or UI display.
- Add another live polling or timer path.
- Edit upstream Codex `thread/read`.
- Merge the freshest same-id timestamp into the existing relay live row.

Decision

Use the existing relay merge owner. Keep live status/routing from the live row,
copy in fresher same-id activity timestamps from history/list, then sort and
sanitize through the current relay path.

Consequences

The fix is local, testable, and does not add a second sorting source of truth.
The upstream Codex timestamp regression remains documented but does not block
Dock correctness for the normal relay path.

Follow-ups

- An upstream Codex fix can still be filed separately if desired, but this plan
  does not edit `~/workspace/codex`.

## 2026-05-28 - Intent-derived: timestamp-only overlay

Blocker:

Whether the relay should copy the whole fresher history row, copy multiple
history list/display fields, call live endpoint `thread/list`, or copy only the
fresh activity timestamp.

Consulted:

Section 0.1, Section 0.5, Section 1.1, Section 5.3, and the read-only sidecar
reviews of the relay merge code.

Intent says:

The user-visible failure is that active sessions sort old because live
`thread/read includeTurns:false` supplies stale `updatedAt`. The relay must keep
live status/routing and avoid new complexity.

Decision:

Copy only the fresher activity timestamp into the live row. Do not replace the
row wholesale and do not add a new live endpoint `thread/list` request.

Consequences:

The implementation stays small, the ownership boundary stays clear, and tests
can assert the exact contract: live status survives, fresh `updatedAt` wins, and
older history cannot downgrade live.

# Appendix A) Imported Notes (unplaced; do not delete)

All meaning-bearing root-cause evidence from the original diagnosis was mapped
into Sections 2 through 6. No unplaced original notes remain.

# Appendix B) Conversion Notes

- Converted the diagnosis-only document into the canonical `$arch-step`
  `DOC_PATH` because the user supplied this exact path for the fix plan.
- The original "diagnosis only" status is intentionally replaced by an active
  architecture plan status because the current goal explicitly asks to plan,
  audit, implement, review, and test the fix.
- The diagnosis tables were preserved in Section 2 because they are the
  falsifying evidence for the implementation.
