# Plan Audit Log

Plan: `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve-with-notes
Last reviewed: 2026-05-28T13:15:05Z
Scope: whole plan plus Phase 1 implementation

## Current Blocking Findings

- [x] PLA-001 - Dual-scope Dock loading needed a partial-state contract
  - Lens: caller-invariant-state, proof-and-phase-exit
  - Evidence: The plan loads human/default and Agents scopes per host, but a mixed success/failure could otherwise be misread as `Agents 0`, empty, or fully healthy.
  - Required plan repair: Define host/snapshot behavior for both scopes succeeding, human success plus Agents failure, Agents success plus human failure, and both scopes failing; define `rowCount` semantics; add tests for mixed outcomes.
  - Status: resolved
  - Resolution evidence: Section 5.2 now defines the scoped load outcome contract, `DockHostLoadStatus.partial(rowCount:message:)`, `DockSnapshot.scopeLoadFailures`, deduped `rowCount`, and empty-state rules. Section 6 adds the Store change-map row. Phase 2 checklist and exit criteria require mixed-failure tests and count semantics.

- [x] PLA-002 - Restore-triggered count proof was assigned to the wrong layer
  - Lens: proof-and-phase-exit, code-truth-map
  - Evidence: `DockStore.refresh()` can recompute counts, but the restore trigger is root UI wiring in `CodexDockRootView`, not a DockStore behavior by itself.
  - Required plan repair: Keep DockStore count recomputation proof in Phase 2, and move restore-success wiring proof to Phase 4.
  - Status: resolved
  - Resolution evidence: Phase 2 now covers normal DockStore state transitions only. Phase 4 now requires a targeted root-wiring test seam or state-level assertion proving Archive restore success invokes `DockStore.refresh()`, plus the final physical `iPhone 14` manual check for visible count updates after restore.

- [x] PLA-003 - Memory/internal rows were promised without a fetch contract
  - Lens: code-truth-map, ambiguity-and-miscommunication
  - Evidence: Upstream `ThreadSourceKind.unknown` matches `CoreSessionSource::Unknown`, not `CoreSessionSource::Internal(_)`; memory-consolidation rows are internal and current `sourceKinds` cannot select them.
  - Required plan repair: Remove memory/internal as a promised Agents result, mark upstream support out of scope, and keep only defensive unknown handling for rows that do reach the client.
  - Status: resolved
  - Resolution evidence: Section 0.3 excludes upstream memory/internal support. Section 0.4 and Phase 1 no longer require memory/internal fixture proof. Section 3 records the upstream limitation. The Decision Log includes `Audit-derived: exclude memory/internal maintenance threads from this plan`.

- [x] PLA-004 - Tab predicate input was still ambiguous
  - Lens: canonical-owner-and-ssot, drift-proof-coupling
  - Evidence: Allowing either a row wrapper or direct row origin could split origin filtering and status filtering into two paths.
  - Required plan repair: Choose one exact input shape and require counts and visible rows to use the same predicate.
  - Status: resolved
  - Resolution evidence: Section 5.1 and Section 5.3 now require `DockRowViewModel.origin` directly. Section 5.3 requires `DockTabID.includes(_ row: DockRowViewModel)` as the single predicate. Section 6 and Phase 2 require tests that fail if status and origin filtering split.

## Current Non-Blocking Findings

- [x] PLB-001 - “No mocked production rows” conflicted with required fixture proof
  - Lens: proof-and-phase-exit
  - Evidence: The plan needs fixtures to prove structured source metadata, but the TL;DR wording could be read as banning fixtures entirely.
  - Required plan repair: Clarify that fixtures are allowed when they preserve real app-server DTO/source shapes.
  - Status: resolved
  - Resolution evidence: The TL;DR now says fixtures must not mock away structured source metadata.

## Current Implementation Findings

- [x] IMP-001 - Broad `.subAgent` in the Agents query could select out-of-scope memory/internal history rows
  - Severity: blocker
  - Lens: plan-code-fit, source-contract drift, side-door closure
  - Evidence: The initial implementation included broad `.subAgent` in `ThreadSourceKind.dockAgentScopeKinds`, even though the plan excludes memory/internal maintenance rows from Phase 1. Broad upstream sub-agent matching can include `memory_consolidation` rows.
  - Required implementation repair: Remove `.subAgent` from the Dock Agents source-kind list and prove the explicit non-internal list.
  - Status: resolved
  - Resolution evidence: `ThreadSourceKind.dockAgentScopeKinds` now uses `.exec`, `.appServer`, `.subAgentReview`, `.subAgentCompact`, `.subAgentThreadSpawn`, `.subAgentOther`, and `.unknown`. `DockStoreScopeTests.testAgentsQueryUsesExplicitNonInternalSourceKinds` pins the exact list. Relay tests use the same explicit list and assert `memory_consolidation` is excluded.

- [x] IMP-002 - Query-blind DockStore test fakes could hide loader-query regressions
  - Severity: high
  - Lens: test-code-review, caller-invariant-state
  - Evidence: Early test fakes returned an empty result for `.activeAgents`, so old tests could pass without proving the query set.
  - Required implementation repair: Make test loaders query-aware, record every `DockSessionQuery`, and fail unexpected queries loudly.
  - Status: resolved
  - Resolution evidence: `DockStoreTests` fakes now configure explicit active-human/active-agents/archived-human results and throw `DockLoadFailure.error("Unexpected query ...")` for unconfigured queries. Scope tests assert recorded query lists.

- [x] IMP-003 - Broad origin subtype eraser allowed invalid human/automation construction
  - Severity: medium
  - Lens: caller-invariant-state, type-boundary cleanliness
  - Evidence: The initial `SessionOriginSubtype` layer let factories accept broad subtype values, then crash through `preconditionFailure` if the subtype family was wrong.
  - Required implementation repair: Remove the broad subtype layer and make factories accept `SessionHumanOriginSubtype` or `SessionAgentOriginSubtype` directly.
  - Status: resolved
  - Resolution evidence: `SessionOrigin` now exposes typed `humanSubtype` and `automationSubtype` accessors and factories take the concrete subtype family.

- [ ] IMN-001 - Source-classification drift can return as Swift and relay evolve separately
  - Severity: medium, non-blocking for Phase 1
  - Lens: drift-proof coupling, tiny-team maintainability
  - Evidence: Swift and Node must both understand the app-server source contract, and they live in different languages. The current Dock path limits production drift because Swift sends the explicit non-internal list and relay tests pin that list, but future source variants still require coordinated updates.
  - Follow-up: Before adding more source variants, add a small shared contract fixture/table or mirrored test cases covering `cli`, `vscode`, `atlas`, `chatgpt`, `exec`, `appServer`, `mcp`, broad sub-agent, explicit sub-agent variants, `unknown`, missing source, contradictions, and memory/internal.
  - Status: accepted follow-up

- [ ] IMN-002 - `DockStore` now carries several pure Phase 1 policies
  - Severity: medium, non-blocking for Phase 1
  - Lens: elegance-and-code-judo, tiny-team maintainability
  - Evidence: `DockStore.swift` owns scope fan-out, partial-state assembly, row dedupe/conflict policy, tab counts, and snapshot construction.
  - Follow-up: Before the next Dock-heavy phase lands, consider extracting pure helpers such as `DockScopeLoader`, `DockSnapshotBuilder`, and a dedupe/conflict policy helper so `DockStore` stays the observable coordinator.
  - Status: accepted follow-up

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/Models/SessionSummary.swift`, `CodexDock/Models/SessionSummaryMapper.swift`, `CodexDock/State/SessionRowProjector.swift`, `CodexDock/State/DockStore.swift` | Source metadata must be preserved, projected, counted, and displayed from one state path. | parent, initial UI/state explorer, Nash, Zeno | read |
| App-server contract | `CodexDock/AppServer/ThreadListDTO.swift`, `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs`, `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/filters.rs`, `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/lib.rs` | Defines `sourceKinds`, default interactive filtering, and the internal/memory limitation. | parent, session-contract explorer, Nash, Zeno | read |
| Caller families | `CodexDock/State/ArchiveStore.swift`, `CodexDock/State/HostSettingsStore.swift`, `CodexDock/Features/Dock/DockView.swift`, preview loaders and test fakes found through repo search | Loader API migration must not leave old call sites or UI-local predicates. | parent, initial UI/state explorer, consistency readers | read |
| Legacy and side-door paths | `scripts/dock-relay.mjs`, `scripts/dock-relay.test.mjs` | Relay live merge can reintroduce rows that app-server history filtering excluded. | parent, relay/code-truth readers, Nash | read |
| Adjacent same-contract paths | `README.md`, archive restore wiring in `CodexDockRootView`, real session metadata under `/Users/aelaguiz/.codex/sessions` | Docs and restore flow can drift from the new source-routing/count behavior. | parent, Zeno | read |
| Contract/proof surfaces | `CodexDockTests/ThreadListMappingTests.swift`, `CodexDockTests/DockStoreTests.swift`, `scripts/dock-relay.test.mjs`, `Package.swift`, `package.json` | Identifies exact test surfaces and the real relay test command `rtk npm run test:relay`. | parent, initial explorers, consistency readers | read |

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
| ADL-001 | Should memory/internal maintenance rows be part of Agents? | Include them via current `unknown` source kind, or exclude until upstream source filtering supports them. | Including them would create a false acceptance promise. | Exclude memory/internal support from this plan. | Codex, from repo evidence | Section 0.3, Section 3, Decision Log | resolved |
| ADL-002 | What is the one predicate input for tab counts and visible rows? | Direct `DockRowViewModel.origin`, or a wrapper around the row. | A wrapper leaves room for split filtering logic. | Require `DockRowViewModel.origin` and `DockTabID.includes(_ row: DockRowViewModel)`. | Codex, from plan-audit repair | Sections 5.1, 5.3, 6, Phase 2 | resolved |

## Pass History

### Pass 1 - 2026-05-28 06:13 CDT

- Mode: plan-readiness
- Scope: whole repo-backed plan
- Baseline reviewed: `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md` after ArchStep auto-plan and consistency-pass
- Test/CI context accepted, if supplied: none supplied; no implementation tests run for this docs-only audit
- Agents/lenses run: native subagents Nash and Zeno ran independent plan-readiness lenses; parent synthesized and spot-checked findings
- Code areas read: Swift model/mapper/projector/store/UI, Archive/Hosts callers, app-server DTO/filters/defaults, relay merge path, test surfaces, real session metadata
- Findings added: PLA-001, PLA-002, PLA-003, PLA-004, PLB-001
- Findings resolved: PLA-001, PLA-002, PLA-003, PLA-004, PLB-001
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code changes are made against this plan

### Pass 2 - 2026-05-28T12:01:57Z

- Mode: cross-plan plan-readiness
- Scope: Agents plan alignment with `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`
- Baseline reviewed: Agents plan after adding top-level related links, no-phone-secret baseline, and cross-plan position
- Test/CI context accepted, if supplied: none; docs-only audit pass
- Agents/lenses run: Sagan ran the independent Agents slice and found no actionable findings; parent synthesis ran outcome, dependency-order, SSOT, proof-exit, docs-contract-drift, and security-boundary lenses
- Code areas read: same core Dock/model/relay coverage as Pass 1, plus `DockHostConfiguration`, `RelayBootstrapStore`, `RelayDiscovery`, `AppServerClient` optional authorization handling, `Makefile` relay auth defaults, and the top-level plan
- Findings added: none
- Findings resolved: none
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after Agents code changes, especially source-kind filtering, scoped load failures, tab-count SSOT, and nil-bearer preservation

### Pass 3 - 2026-05-28T13:15:05Z

- Mode: implementation-audit plus thermo-nuclear code-quality rerun
- Scope: Phase 1 Agents Tab And Live Counts implementation only
- Baseline reviewed: current worktree Phase 1 diff; `Package.swift`, `project.yml`, and `CodexDock.xcodeproj/project.pbxproj` deployment-target/generated-project drift explicitly excluded as unrelated and not part of the Phase 1 commit
- Test/CI context accepted, if supplied: `rtk swift test` passed 100 tests with 5 skipped; `rtk npm run test:relay` passed 21 tests; `rtk git diff --check` passed; physical `iPhone 14` build/install/launch passed on destination id `00008110-000E04940240A01E`
- Agents/lenses run: Poincare ran plan-backed implementation audit and approved with no findings; Locke ran thermo-nuclear review and found no blockers or high-severity issues after repairs
- Code areas read: Swift source/query/origin/store/UI paths, changed Swift tests, relay source filtering and tests, Phase 1 docs, parent plan
- Findings added: IMP-001, IMP-002, IMP-003, IMN-001, IMN-002
- Findings resolved: IMP-001, IMP-002, IMP-003
- Findings carried forward: IMN-001 and IMN-002 as non-blocking follow-up before later source or Dock-heavy phases
- Verdict: approve-with-notes
- Next audit focus: connectivity plan implementation should consume the final `DockSessionQuery`/`DockSnapshot` shape without adding duplicate source classification or tab-count predicates
