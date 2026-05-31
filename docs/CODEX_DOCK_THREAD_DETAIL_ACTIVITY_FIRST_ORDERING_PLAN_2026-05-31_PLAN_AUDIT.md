# Plan Audit Log

Plan: `docs/CODEX_DOCK_THREAD_DETAIL_ACTIVITY_FIRST_ORDERING_PLAN_2026-05-31.md`
Audit log: `docs/CODEX_DOCK_THREAD_DETAIL_ACTIVITY_FIRST_ORDERING_PLAN_2026-05-31_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve-with-notes
Last reviewed: 2026-05-31 11:09:52 CDT
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

No blocking implementation findings.

Non-blocking notes:

- `CodexDock/State/ThreadDetailStore.swift` is 997 lines after the patch. The
  implementation only adds the explicit `sortDirection: .desc` call-site and a
  single shared `receivedAt` timestamp, so it does not push the file over 1,000
  lines or add new store-owned ordering logic. Future thread-detail work should
  avoid putting more behavior in this file without extraction.
- Native read-only implementation-audit explorers were spawned for independent
  event/model and store/request slices, but both timed out and were closed with
  `previous_status=running`. Parent review still read the relevant code directly,
  so this is not a coverage blocker.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/Models/ThreadEvent.swift`: `ThreadEvent`, `ThreadMessageSemantics`, `ThreadEventDisplayOrder`, `ThreadEventNormalizer`; `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`: `ThreadDetailDataEngine`, `ThreadEventIndex` | Owns event normalization, recency, ordering, and live merge | Parent, Hume, Zeno, Ramanujan | read |
| Render caller path | `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`; `CodexDock/Features/Session/ThreadMessageListView.swift`; `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift` | Confirms rendering trusts event order and should not own sorting | Parent, Hume, Zeno, Ramanujan | read |
| Store/live/request path | `CodexDock/State/ThreadDetailStore.swift`; `CodexDock/State/ThreadDetailStore+Voice.swift`; `CodexDock/Models/ServerRequestCard.swift`; `CodexDock/Commands/ClientCommandEngine.swift` | Confirms request cards are controls, live requests enter as events, and pinning does not sort detail rows | Parent, Zeno, Ramanujan | read |
| App-server DTO/protocol path | `CodexDock/AppServer/ThreadDetailDTO.swift`; `CodexDock/AppServer/JSONRPC.swift`; `CodexDock/AppServer/AppServerClient.swift`; `scripts/dock-relay*.mjs`; app-server data reference docs | Confirms `thread/turns/list` shape, default descending order, and missing per-message timestamps | Parent, Ramanujan | read |
| Tests/proof surfaces | `CodexDockTests/ThreadEventNormalizerTests.swift`; `CodexDockTests/ThreadDetailDataEngineTests.swift`; `CodexDockTests/ThreadDetailRenderProjectorTests.swift`; `CodexDockTests/ThreadDetailStoreTests.swift`; `CodexDockTests/ThreadDetailStreamingMergeTests.swift`; `CodexDockTests/AppServerClientTests.swift`; `CodexDockTests/ServerRequestCardTests.swift` | Confirms current wrong behavior is test-encoded and identifies required proof | Parent, Hume, Zeno, Ramanujan | read |
| Legacy/side-door paths | Dock row pinning paths in `ThreadCardRowProjector`, `ThreadCardTable`, `DockThreadCardDTO`, and prior audit doc | Confirms manual Dock pinning is separate from detail order | Parent, Zeno | read |

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses, if triggered

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| None | None | None | None | None | None | None | resolved |

## Plan-Readiness Verdict

VERDICT: ready
Confidence: high

Blocking findings: none.

Why ready:

- The plan states the intended user experience before implementation detail:
  most recent meaningful thread detail activity appears first.
- The plan names the exact non-goals that prevent feature creep: no Dock list
  pinning changes, no new UI mode, no raw rollout parsing, and no server/relay
  protocol change.
- The plan identifies the current bug with code anchors: shared turn-level date,
  ascending `itemSequence`, unsafe `turnSequence`, and streaming-delta merge
  timestamp retention.
- The target architecture keeps one owner path: `ThreadEvent` normalization and
  `ThreadDetailDataEngine` ordering.
- The plan removes fake complexity by adding one explicit sort concept,
  `activityDate`, instead of adding a new side channel or UI-only sort.
- The plan makes the implicit server default explicit by adding
  `sortDirection: "desc"` to Swift detail reads.
- The proof plan covers normalizer, data engine, render prefix behavior,
  store/live behavior, DTO encoding, and iPhone 17 simulator runtime proof.

## Pass History

### Pass 1 - 2026-05-31 10:39:39 CDT

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed:
  `docs/CODEX_DOCK_THREAD_DETAIL_ACTIVITY_FIRST_ORDERING_PLAN_2026-05-31.md`
- Test/CI context accepted, if supplied: not supplied; no implementation exists
- Agents/lenses run:
  native parallel code review slices for event ordering/rendering,
  store/live/request behavior, and app-server/protocol data truth
- Code areas read:
  `ThreadEvent`, `ThreadDetailDataEngine`, render projector, message list,
  store/live/request path, DTO/protocol path, focused tests, and Dock pinning
  side-door paths
- Findings added: none
- Findings resolved:
  the plan already carried through the audit concerns found during review:
  exact `activityDate` field, explicit `sortDirection: "desc"`, streaming merge
  recency update, and no detail sorting from Dock pin/request-card sidecars
- Findings carried forward: none
- Verdict: ready
- Next audit focus:
  after implementation, run implementation-audit against this plan and verify
  the code still has one ordering owner and no UI-side sort workaround

### Pass 2 - 2026-05-31 10:42:56 CDT

- Mode: plan-readiness reconciliation after fresh consult
- Scope: whole plan
- Baseline reviewed:
  `docs/CODEX_DOCK_THREAD_DETAIL_ACTIVITY_FIRST_ORDERING_PLAN_2026-05-31.md`
- Test/CI context accepted, if supplied: not supplied; no implementation exists
- Agents/lenses run:
  Cursor Agent `composer-2.5-fast` fresh consult from
  `/tmp/fresh-consult/codex-dock-activity-first-ordering-20260531T154022Z-hRdQDt`
- Code areas read:
  fresh consult reported reading the plan, audit log, app-server data
  reference, `ThreadEvent`, `ThreadDetailDataEngine`, render projector,
  `ThreadDetailStore`, `ThreadDetailDTO`, Dock pinning path, and focused tests
- Findings added: none blocking
- Findings resolved:
  fresh consult notes were carried into the plan:
  params-level live `startedAtMs` / `completedAtMs`, request `startedAtMs`
  fallback to `now`, explicit `turnSequence` comparator direction, and
  streaming merge `activityDate` semantics
- Findings carried forward: none
- Verdict: ready
- Next audit focus:
  after implementation, verify the code reads timestamps from notification and
  request params, flips the same-date `turnSequence` tie-break under desc pages,
  updates streaming merge recency, and does not introduce a second ordering path

### Pass 3 - 2026-05-31 11:00:52 CDT

- Mode: implementation-audit
- Scope: whole plan
- Baseline reviewed: current worktree diff
- Test/CI context accepted, not verified by this mode:
  - `rtk swift test --filter ThreadEventNormalizerTests` passed
  - `rtk swift test --filter ThreadDetailDataEngineTests` passed
  - `rtk swift test --filter ThreadDetailRenderProjectorTests` passed
  - `rtk swift test --filter AppServerClientTests` passed
  - `rtk swift test --filter ThreadDetailStreamingMergeTests` passed
  - `rtk swift test --filter ServerRequestCardTests` passed
  - `rtk swift test --filter ThreadDetailStoreTests` passed
  - focused `ThreadDetailStoreTests` ordering/request tests passed individually
  - `rtk make app SIM='iPhone 17'` passed after the final comparator fallback
    cleanup
- Native subagents/lenses run:
  - parent ran implementation-audit lenses directly
  - read-only explorer `019e7ec4-ba92-7ac0-8ce5-08db4c576012` was spawned for
    event/model/render review, timed out, and was closed
  - read-only explorer `019e7ec4-e7f5-7eb2-b9aa-c0aa227ee759` was spawned for
    store/live/request side-door review, timed out, and was closed
- Code areas read:
  `ThreadEvent`, `ThreadEventDisplayOrder`, `ThreadEventNormalizer`,
  `ThreadDetailDataEngine`, `ThreadDetailRenderProjector`, `ThreadDetailStore`,
  `ThreadTurnsListParams`, `ServerRequestCard`, and the changed focused tests
- Findings added:
  no blocking code-review findings; one non-blocking maintainability note for
  `ThreadDetailStore.swift` being close to 1,000 lines
- Findings resolved during audit:
  `displayGroupDate` now has an explicit code comment that it is a display
  grouping fallback and ordering should prefer `activityDate`; missing
  `turnSequence` values now sort after known turn-sequence values on exact
  timestamp ties
- Findings carried forward:
  avoid adding more behavior to `ThreadDetailStore.swift` without extraction
- Verdict: approve-with-notes
- Why approved:
  - `ThreadEvent.activityDate` is the single new sort concept, and
    `ThreadMessageSemantics.activityDate(for:)` is the shared source used by
    `ThreadEventDisplayOrder`.
  - Historical `userMessage` rows use turn `startedAt`, while `agentMessage`,
    reasoning, command, file-change, and tool rows use turn `completedAt` with a
    `startedAt` fallback.
  - Live `item/started`, live `item/completed`, and JSON-RPC request rows use
    protocol timestamps when present and local receive time only as fallback.
  - Request events and `ServerRequestCard` share the same resolved request time
    through one `receivedAt` value at the store call-site.
  - `ThreadTurnsListParams` now carries `sortDirection`, and
    `ThreadDetailStore.readAllTurns` passes `.desc`.
  - Tie-breakers no longer encode "earlier user prompt wins"; under descending
    turn pages, lower `turnSequence` wins on exact date ties, and later
    `itemSequence` / `eventSequence` wins within the same tie.
  - `ThreadDetailDataEngine` remains the ordered event-index owner, and
    `ThreadDetailRenderProjector` still only filters and takes the visible
    prefix.
  - No Dock pinning, request-card array order, relay stream sequence, raw JSONL,
    local metadata, or UI-side ordering path was added.

## Thermo-Nuclear Code Quality Review

VERDICT: approve-with-notes
Confidence: high
Scope reviewed: current branch changes for the activity-first ordering patch

Blocking findings: none.

Non-blocking maintainability note:

- `CodexDock/State/ThreadDetailStore.swift` is close to the 1,000-line review
  threshold at 997 lines. This patch does not cross the threshold and does not
  move the ordering policy into the store, so no decomposition is required for
  this change. The next store behavior change should extract before adding more
  store-owned flow.

Architecture/elegance result:

- The implementation uses the existing model-owner path instead of adding a
  second detail ordering path.
- The new abstraction is not a wrapper layer; `activityDate` removes ambiguity
  between row display time and recency sort time.
- The comparator cleanup is direct and local; there are no scattered special
  cases in SwiftUI views or request-card code.
- Streaming-delta merge recency is handled at the merge point, so active output
  does not rely on caller-side reordering.
- The patch keeps request cards as controls attached to request events, not as a
  sorting source.
