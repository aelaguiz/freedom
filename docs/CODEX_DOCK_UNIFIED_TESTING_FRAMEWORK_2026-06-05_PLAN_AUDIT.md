# Plan Audit Log

Plan: `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`
Audit log: `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-06-05
Scope: whole plan plus `docs/TESTING.md`, `AGENTS.md`, `README.md`, and the referenced command/script surfaces

## Current Blocking Findings

None.

## Current Non-Blocking Findings

- [ ] PLA-001 - Framework work is not implemented yet
  - Lens: proof and phase exit
  - Evidence:
    - `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md` states `test-smoke`, `test-full`, and `test-overtime` are future targets.
    - `docs/TESTING.md` states those targets do not exist yet.
  - Required plan repair: none. The plan is an implementation plan, and the current guide keeps runnable commands truthful.
  - Status: accepted-risk
  - Resolution evidence: not applicable

- [ ] PLA-002 - Scale proof runtime and artifact size are unknown until implementation
  - Lens: proof and phase exit
  - Evidence:
    - The plan requires first implementation of `test-overtime` to record observed wall-clock runtime and artifact size.
  - Required plan repair: none. The plan carries the measurement requirement before default local recommendation.
  - Status: accepted-risk
  - Resolution evidence: not applicable

- [ ] PLA-003 - Docs-mined runtime gaps still need behavior tests
  - Lens: proof and phase exit
  - Evidence:
    - `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` marks pinned action survival,
      System Health row-window honesty, private runtime capability, large live
      Thread Detail payload, and physical stale-build proof as not fully
      default-matrix-covered today.
    - `scripts/codex-dock-test-scenario-coverage.test.mjs` keeps the coverage
      ledger from drifting, but it does not run the simulator or physical
      device.
  - Required plan repair: none after the 2026-06-05 docs-mined pass. The plan
    now names those runtime gaps and carries them into `test-overtime` and the
    coverage ledger.
  - Status: accepted-risk
  - Resolution evidence: not applicable

## Current Implementation Findings

Not run. This audit is `plan-readiness`, not implementation review.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Current guide and plan | `docs/TESTING.md`, `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md` | Plan artifact and current-use guide | parent, model-consensus, fresh consult | read |
| Docs-mined coverage ledger | `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`, `scripts/codex-dock-test-scenario-coverage.test.mjs`, `package.json` | Ensures root bug docs and controlled scenario ids are represented in coverage | parent | read |
| Historical docs inventory | 280 Markdown docs under `README.md`, `AGENTS.md`, `docs/**`, and `research/**` | Mines historical failure classes into the coverage ledger | parent | read |
| Agent and human routing | `AGENTS.md`, `README.md` | Discoverability for future agents and humans | parent, fresh consult | read |
| Runnable command source | `Makefile`, `package.json`, `Package.swift`, `project.yml` | Confirms current commands and missing future targets | parent, model-consensus, fresh consult | read |
| Scenario owners | `scripts/dock-relay-controlled-simulator-fixture.mjs`, `scripts/dock-relay-controlled-simulator-matrix.mjs`, `Makefile` | Confirms current three-place scenario workflow and `file-change-review` drift | parent, model-consensus, fresh consult | read |
| Large corpus owner | `scripts/codex-dock-isolated-home.mjs` | Confirms current clone-only support and missing stale/change profile | model-consensus, fresh consult | read |
| Contract/proof surfaces | `contract/projection/**`, `contract/proof/**`, `scripts/check-projection-contract.mjs`, `scripts/check-proof-report-contracts.mjs`, `scripts/proof-report-contracts.mjs` | Confirms proof doctrine, schemas, and route evidence guardrails | parent, model-consensus, fresh consult | read |
| Swift test owners | Representative `CodexDockTests/**` files named in the plan | Confirms add-a-test ownership | parent, model-consensus | read |
| UI proof owners | `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, `CodexDockUITests/DisplayedUICaptureSupport.swift` | Confirms structured simulator proof owner path | model-consensus | read |

Native subagents were not used for this audit. The available subagent tool says
it may be used only when the user explicitly asks for subagents or delegation.
The parent read the relevant docs and command surfaces directly.

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and source of truth
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Docs-contract drift
- [x] Security boundary, limited to proof routes, raw app-server path, and secret handling

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Should `docs/TESTING.md` exist now or only after the framework lands? | Create current-use guide now; or wait for future targets. | Affects discoverability and risk of teaching non-existent commands. | Create it now, but list only current commands and mark future targets as non-existent. | Codex, with model consensus sign-off | `docs/TESTING.md`; `AGENTS.md`; `README.md` | resolved |
| DEC-002 | What should the over-time tier be called? | `test-realtime`; `test-live-sync`; `test-overtime`. | `test-realtime` collides with OpenAI Realtime transcription naming. | Use `test-overtime`. | Codex, with model consensus sign-off | Plan target list and README/AGENTS wording | resolved |
| DEC-003 | Should old sync docs be deleted now? | Delete now; demote and fold later. | Deleting now could remove still-accurate runbook detail. | Demote now, fold/delete after framework lands. | Codex, with model consensus sign-off | Delete/demote/fold ledger | resolved |
| DEC-004 | Should latency proof targets be folded immediately? | Fold into matrix now; keep bespoke until signal-equivalent. | Premature fold could lose optimistic UI and ack-latency proof. | Keep bespoke until catalog/matrix carries equivalent assertions. | Codex, with model consensus sign-off | Delete/demote/fold ledger and target framework | resolved |

## Plan-Readiness Verdict

VERDICT: ready
Confidence: high

The plan is ready as an implementation plan. It does not claim that the
framework exists today. It distinguishes current commands from future targets,
keeps `Makefile` as the public command owner, gives scenario unification and
large/stale corpus work concrete owners, preserves strict proof doctrine, and
adds discoverable current-use documentation through `docs/TESTING.md`,
`AGENTS.md`, and `README.md`.

## North Star And Done-State Requirements

- North Star outcome: future agents can discover how to run proof and how to
  add tests without searching dated history.
- Done-state truths:
  - `Makefile` owns `test-smoke`, `test-full`, and `test-overtime`.
  - `docs/TESTING.md` is the living current-use guide.
  - Scenario ids and requirements are defined once.
  - A large/stale/changing corpus can exercise the 900-thread class through the
    real relay/projection path.
  - Weak proof paths stay diagnostic-only.
  - Old dated plan/runbook docs are folded or retired after replacement.
  - `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` maps every current root bug doc
    and controlled scenario id to current, planned, gap, fixture-only,
    physical-only, or diagnostic-only coverage.

## Depth-First Implementation Risk

- First integrated slice: add Makefile tier targets as wrappers around existing
  commands and update `docs/TESTING.md`.
- Highest-risk seam: `test-overtime`, because it crosses corpus generation,
  relay projection, simulator UI sampling, and matrix judgment under large data.
- Proof before widening: make the scenario catalog drive fixture, matrix, and
  Makefile for one scenario before migrating all scenarios.
- Breadth-first risk: building a large corpus before the judge can distinguish
  app lag from capture skew.
- Widening sequence: tier targets, scenario catalog, corpus generator, judge
  hardening, full overtime matrix, cleanup.

## Deletion, Drift, And Side Doors

- Delete now: none.
- Close or migrate:
  - Scenario list duplication across fixture, matrix, and Makefile.
  - Fixture-only `file-change-review` drift.
  - Old dated sync docs after content is folded.
  - This dated plan after implementation is folded into `docs/TESTING.md`.
  - Coverage-ledger gaps are migrated into the scenario catalog or explicit
    Swift/UI/physical proof gates.
- Explicitly out of scope now:
  - Implementing the new Makefile targets.
  - Implementing `scripts/dock-relay-scenarios.mjs`.
  - Implementing the 900-thread corpus generator.
- Drift risks:
  - Future target docs could become stale if `Makefile` changes without
    `docs/TESTING.md`.
  - Scenario catalog must become the only owner or the drift remains.

## Proof And Phase-Exit Gaps

- Integration proof needed:
  - `test-overtime` must prove real relay/projection/UI convergence over time.
  - Large profile must use the real relay and projection path, not a mock path.
  - Pinned action survival, System Health row-window honesty, private runtime
    capability mismatch, large live detail payloads, and physical stale-build
    proof must become behavior proof before an exhaustive claim.
- Low-value tests to avoid:
  - `sim-ui-dump` alone.
  - Status endpoints alone.
  - Screenshots, mocks, preview rows, loopback-only paths, raw `:4500`, and raw
    detail side doors as completion proof.
- Phase-exit gap:
  - None for plan readiness. Implementation phases still need their own proof.

## Pass History

### Pass 1 - 2026-06-05

- Mode: plan-readiness
- Scope: whole plan and discoverability docs
- Baseline reviewed: worktree docs plus current command/script owners
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent audit, model-consensus, fresh Composer 2.5 Fast consult
- Code areas read: see relevant code coverage ledger
- Findings added: PLA-001, PLA-002
- Findings resolved: none
- Findings carried forward: PLA-001 and PLA-002 as accepted plan-scope risks
- Verdict: ready
- Next audit focus: implementation-audit after Phase 1 or scenario catalog work

### Pass 2 - 2026-06-05

- Mode: plan-readiness plus docs-mined regression coverage pass
- Scope: whole plan, current testing guide, coverage ledger, package scripts,
  current controlled scenario owners, root bug docs, and repo Markdown inventory
- Baseline reviewed: 280 Markdown docs under `README.md`, `AGENTS.md`,
  `docs/**`, and `research/**`; `Makefile`; `package.json`; controlled
  simulator fixture and matrix owners
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent audit only; native subagents unavailable for this
  prompt because the tool requires explicit user authorization
- Code areas read: coverage ledger guard, current matrix/fixture scenario
  lists, current Node test manifest
- Findings added: PLA-003
- Findings resolved: no blocking findings
- Findings carried forward: PLA-001, PLA-002, PLA-003 as accepted
  implementation-scope risks
- Verdict: ready
- Next audit focus: implementation-audit after Phase 1, scenario catalog work,
  or runtime coverage for any `gap` row in
  `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`
