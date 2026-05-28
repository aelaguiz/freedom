# Plan Audit Log

Plan: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_05_TEXT_CONTROL_REQUEST_CARDS_2026-05-27.md`
Audit log: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_05_TEXT_CONTROL_REQUEST_CARDS_2026-05-27_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve-with-notes
Last reviewed: 2026-05-28 03:35 UTC
Scope: Phase 5 implementation audit

## Current Blocking Findings

None.

## Current Non-Blocking Findings

- [ ] IMP-001 - Relay request-attention enrichment intentionally probes active
  rows with `thread/resume`
  - Lens: tiny-team maintainability, security-boundary, docs-contract-drift
  - Scope: Phase 5 relay list/status behavior
  - Plan expects: Needs-me Dock state can derive from request/card attention
    without mocks or invented status.
  - Code reality: `scripts/dock-relay.mjs` enriches active live rows by
    replaying pending requests from the owning app-server and merging supported
    `activeFlags`. This is real app-server state, but it does make
    `thread/list` perform short-lived `thread/resume` probes for active rows.
  - Anchors: `scripts/dock-relay.mjs` `pendingRequestsForActiveThread`,
    `enrichRowAttention`, `attentionFlagsForServerRequest`.
  - Required implementation repair: none for Phase 5. Watch this in Phase 6 if
    active-row counts grow enough that multi-host polling needs caching or a
    dedicated app-server request-inspection API.
  - Status: accepted-risk
  - Resolution anchor: worklog real-host counts and relay unit tests.

## Current Implementation Findings

No blocking implementation findings.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Protocol client | `CodexDock/AppServer/AppServerClient.swift`, `AppServerMethods.swift`, `TurnDTO.swift` | turn methods and JSON-RPC response path | Codex | read |
| Detail owner | `CodexDock/State/ThreadDetailStore.swift` | composer, request-card state, active turn tracking | Codex | read |
| Request model | `CodexDock/Models/ServerRequestCard.swift` | supported/unsupported request normalization and response payloads | Codex | read |
| UI | `CodexDock/Features/Session/ComposerView.swift`, `RequestCardView.swift`, `SessionDetailView.swift` | phone composer/card rendering | Codex | read |
| Relay | `scripts/dock-relay.mjs`, `scripts/dock-relay.test.mjs` | real host turn forwarding and Dock attention enrichment | Codex | read |
| Tests | `CodexDockTests/AppServerClientTests.swift`, `ThreadDetailStoreTests.swift`, `ServerRequestCardTests.swift` | changed behavior and contract fixtures | Codex | read |
| Docs/run path | `Makefile`, `.env`, bug doc, epic doc | canonical app/relay launch path and root-cause carry-through | Codex | read |

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
- [x] Conditional lenses: security boundary and docs-contract drift

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Should Needs me be filled from running process presence? | Process exists means needs attention vs only app-server request/flag means needs attention | Fake Needs me rows would violate the real-server requirement | Use only real app-server attention signals | aelaguiz/Codex | Phase 5 plan evidence, bug doc follow-up, relay request-aware enrichment | resolved |

## Pass History

### Pass 1 - 2026-05-28 03:35 UTC

- Mode: implementation-audit
- Scope: Phase 5 code and docs
- Baseline reviewed: worktree
- Test/CI context accepted: `node --check`, `npm run test:relay`,
  `swift test`, `xcodebuild test`, `make app`, direct real-host typed-send
  smoke, and simulator screenshot reported in worklog
- Agents/lenses run: parent-agent plan-audit implementation lenses
- Code areas read: protocol client, detail store, request model, composer/card
  UI, relay, tests, docs/run path
- Findings added: IMP-001
- Findings resolved: none
- Findings carried forward: IMP-001 accepted risk for Phase 6 scale watch
- Verdict: approve-with-notes
- Next audit focus: Phase 6 multi-host expansion should check relay polling
  cost and whether request-attention probing needs caching or upstream API
  support.

# Plan Implementation Audit Verdict

VERDICT: approve-with-notes
Confidence: high
Mode: implementation-audit
Scope reviewed: Phase 5
Plan artifact: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_05_TEXT_CONTROL_REQUEST_CARDS_2026-05-27.md`
Audit log: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_05_TEXT_CONTROL_REQUEST_CARDS_2026-05-27_PLAN_AUDIT.md`
Baseline reviewed: worktree
Test/CI context: accepted from worklog; not independently executed by this audit mode

## Blocking Findings

None.

## Non-Blocking Findings

1. Relay attention enrichment has polling cost to watch in Phase 6.
   - Problem: `thread/list` now inspects active live rows by rejoining them
     briefly to catch replayed pending app-server requests.
   - Why it does not block: this uses supported real app-server behavior, only
     applies to active rows without attention flags, and is the smallest real
     way to satisfy Phase 5's Needs-me contract without fake status.
   - Plan expects: request/card attention can feed Needs me.
   - Code reality: the relay derives extra attention from replayed pending
     requests and merges app-server-supported active flags.
   - Anchors: `scripts/dock-relay.mjs` `pendingRequestsForActiveThread`,
     `enrichRowAttention`.
   - Required implementation repair: none before Phase 5 commit; revisit
     caching/API shape during Phase 6 if multi-host active-row count grows.
   - Review lens: tiny-team maintainability.

## Scope Review

- Claimed scope: typed text control plus minimal request cards.
- Code reviewed: protocol methods, DTOs, client, detail store, composer/card
  views, relay turn/request forwarding, relay status enrichment, changed tests,
  run docs.
- Code blockers: none.
- Test/CI assumptions accepted: supplied verification from worklog.
- Phase status recommendation: complete.

## Architecture And Elegance

- Canonical owner: `ThreadDetailStore` owns detail, composer, active turn, and
  request-card state.
- SSOT status: turn and request methods remain in `AppServerClient`; UI does
  not speak JSON-RPC directly.
- Duplicate truth or parallel paths: none found for typed send. Voice remains
  able to reuse the same composer path later.
- Simpler code-judo move: no obvious simpler Phase 5 design without either
  faking Needs me or waiting for an upstream pending-request list API.
- Tiny-team maintainability risk: relay active-row probing is the only notable
  scaling watch item.

## Deletes, Side Doors, And Drift

- Required deletes satisfied: no old control path existed.
- Old paths still live: read-only detail remains as the same detail owner, now
  extended with controls.
- Side doors still callable: unsupported server request methods stay visible
  and unanswerable on phone instead of being dropped.
- Drift-prone shared dependencies: request method names are duplicated between
  Swift card normalization and relay attention classification; tests cover the
  relay classifier and Swift request-card payloads.
- Docs/prompts/examples/instructions drift: bug doc and epic were updated.

## Relevant Code Coverage

- Code areas read: listed in coverage ledger.
- Relevant code not yet read: none required for Phase 5.
- Native subagents/lenses run: parent-agent implementation audit lenses only;
  scope was small enough not to split.
- Coverage blockers: none.

## Recommended Next Move

Commit Phase 5, then start Phase 6 with an explicit check of relay polling cost
and multi-host attention semantics.
