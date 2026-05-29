# Plan Audit Log

Plan: `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: complete
Last reviewed: 2026-05-28T23:22:21Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

- [x] PLA-001 - Pre-implementation gate was originally inside the last phase.
  - Lens: proof and phase exit
  - Evidence: consistency pass found the plan-audit gate after implementation
    phases.
  - Required plan repair: move plan-audit and stage-gate readiness before code
    phases.
  - Status: resolved
  - Resolution evidence:
    `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md` now has
    `Pre-Implementation Gate - Plan audit and readiness` before Phase 1.

- [x] PLA-002 - Runtime smoke proof was too broad outside Section 0.
  - Lens: proof and phase exit
  - Evidence: consistency pass found the Phase 3 smoke wording weaker than the
    Section 0 acceptance evidence.
  - Required plan repair: require active-row timestamp freshness through
    `ws://127.0.0.1:4510/`, or name the exact blocker.
  - Status: resolved
  - Resolution evidence:
    Phase 3 verification and exit criteria now require active-row timestamp
    freshness through `ws://127.0.0.1:4510/`.

- [x] PLA-003 - Helper-vs-inline implementation choice was branchy.
  - Lens: canonical owner and SSOT
  - Evidence: Section 5 chose a helper, while Section 7 briefly allowed
    equivalent inline logic.
  - Required plan repair: require the helper chosen by the target architecture.
  - Status: resolved
  - Resolution evidence:
    Phase 1 now requires a pure same-id freshness helper in
    `scripts/dock-relay-thread-data.mjs`.

## Current Implementation Findings

None.

Implementation audit evidence now lives in:

- `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`
- `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_WORKLOG.md`
- `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_THERMONUCLEAR_REVIEW.md`

Final focused check: `rtk npm run test:relay` passed with `51` tests,
`51` pass, `0` fail, `duration_ms 7520.262041`.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `scripts/dock-relay-thread-data.mjs`: `readLoadedRows`, `collectLiveRows`, `aggregateThreadList`, `mergeThreadListRows`, `sanitizeRelayFields` | Owns the stale live row and duplicate live/history merge path | self, Mencius, Harvey | read |
| Caller families | `scripts/dock-relay.mjs`: JSON-RPC `thread/list` dispatch and helper exports | Confirms server path and pure helper test access | self, Harvey | read |
| Legacy and side-door paths | `shouldCollectLiveRowsForThreadList`, archived `thread/list`, `endpointByThreadId`, `endpointForThread` | Ensures archived behavior and live detail routing stay unchanged | self, Harvey | read |
| Adjacent same-contract paths | `CodexDock/Models/SessionSummaryMapper.swift`, `CodexDock/State/DockSessionProjection.swift` | Confirms Swift consumes/sorts relay timestamps and should not own this fix | self, Sagan, Harvey | read |
| Comparable patterns | `scripts/dock-relay.test.mjs`, `scripts/dock-relay-phase5.test.mjs`, `scripts/dock-relay-test-helpers.mjs` | Provides pure merge and fake WebSocket relay test patterns | self, Mencius, Harvey | read |
| Contract/proof surfaces | `package.json`, `AGENTS.md`, `README.md`, `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md` | Confirms `rtk npm run test:relay`, service path, and existing Swift projection plan | self, Sagan | read |

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
- [x] Conditional lenses: docs-contract-drift and security-boundary checked;
  agent-capability not applicable.

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Which layer owns the fix? | Swift workaround, upstream Codex repair, relay merge repair | Could create duplicate sorting/freshness rules | Use relay merge owner | plan | TL;DR, Sections 0, 3, 5, 6, and Decision Log | resolved |
| DEC-002 | Which fields are copied from history? | Whole row, broad list-field overlay, live `thread/list`, timestamp-only overlay | Could lose live status/routing or add unnecessary complexity | Copy only fresher activity timestamp into live row | plan | Section 5.3 and Decision Log timestamp-only overlay entry | resolved |
| DEC-003 | Does this change protocol shape? | Preserve existing `thread/list`, or add fields/methods | Would require Swift/DTO migration | Preserve row shape and method names | plan | Sections 0.3, 3.2, 5.4, 6.2 | resolved |

## Pass History

### Pass 1 - 2026-05-28T23:15:00Z

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed:
  `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`
- Test/CI context accepted, if supplied:
  not supplied; this was pre-implementation
- Agents/lenses run:
  Mencius for relay fix/tests, Sagan for plan requirements, Helmholtz for
  architecture choice, Euclid and Harvey for consistency pass, self for parent
  synthesis
- Code areas read:
  relay merge path, relay server dispatch, relay tests, Swift DTO mapping,
  Swift Dock projection, package test command, service path docs
- Findings added:
  PLA-001, PLA-002, PLA-003, all resolved before this verdict
- Findings resolved:
  PLA-001, PLA-002, PLA-003
- Findings carried forward:
  none
- Verdict:
  ready
- Next audit focus:
  implementation-audit after `$arch-step auto-implement`

## Plan Audit Verdict

VERDICT: ready
Confidence: high
Scope reviewed: whole plan
Plan artifact: `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_PLAN_AUDIT.md`

## Blocking Findings

None.

## Stronger Architecture Move

The simplest architecture is the one already chosen by the plan: reconcile the
same-id row at `mergeThreadListRows` by preserving live status/routing and
copying only the fresher activity timestamp from history. This avoids a Swift
workaround, avoids a new live `thread/list` call, preserves live-first limit
behavior, and uses data the relay already fetched.

## North Star And Done-State Requirements

- North Star outcome:
  active loaded sessions keep fresh `updatedAt` through the relay and sort at
  the top of `Newest`.
- Done-state truths:
  duplicate live/history ids return one active row with the freshest timestamp;
  older history does not downgrade live; `dockRelaySource` does not leak;
  archived behavior and source filtering stay unchanged; relay tests pass.
- User-facing or outcome-facing requirements:
  the app's existing `Newest` sort receives correct relay timestamps.
- Code-quality requirements:
  one small relay helper, no protocol change, no Swift workaround, no runtime
  shim, no extra polling or live list call.
- Outcome that remains unproven until implementation:
  relay code and tests actually satisfy the plan.

## Relevant Code Coverage

- Code areas read:
  listed in the coverage ledger above.
- Relevant code not yet read:
  none known for plan readiness.
- Coverage blockers:
  none.

## Depth-First Implementation Risk

- First integrated slice:
  pure `mergeThreadListRows` same-id freshness behavior.
- Highest-risk seam:
  combining live status/routing with history freshness without changing
  filtering, sanitization, or limit policy.
- Proof required before widening:
  pure merge tests, then a real relay `thread/list` mocked WebSocket test.
- Breadth-first scaffolding risks:
  adding Swift compensations, new upstream calls, or generic field overlay.
- Widening sequence:
  helper and pure tests, then integration test, then review/runtime smoke.

## Deletion, Drift, And Side Doors

- Delete now:
  none.
- Close or migrate:
  duplicate live/history rows now merge through one owner.
- Explicitly out of scope:
  upstream Codex repair, Swift UI changes, timers, push streams, protocol
  changes, archived behavior changes.
- Drift risks:
  Swift workaround and broad field overlay are the main risks; both are
  explicitly rejected by the plan.
- Needs decision:
  none.

## Proof And Phase-Exit Gaps

None remain. The phase plan carries the pre-implementation gate, pure merge
proof, integration proof, test target, thermo-nuclear review, and local relay
smoke proof in checklist and exit criteria.

## Coverage Notes

- Lenses run:
  all required plan-readiness lenses, plus docs-contract-drift and
  security-boundary.
- Lenses not run:
  agent-capability, because this is deterministic relay code.
- Audit log updated:
  yes.
- Proper-audit checklist status:
  complete for plan readiness.
- What was not checked:
  implementation correctness, because code changes had not started yet.

## Recommended Next Move

Run `$arch-step auto-implement` against
`docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`.
