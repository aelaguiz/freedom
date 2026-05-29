# Plan Audit Log

Plan: docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md
Audit log: docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29_PLAN_AUDIT.md
Current plan verdict: complete
Current implementation code-review verdict: approve
Last reviewed: 2026-05-29T18:45:41Z
Scope: whole plan

## Current Blocking Findings

None open.

## Current Non-Blocking Findings

None open.

## Current Implementation Findings

None open.

## Resolved Implementation Findings

- [x] IMP-001 - Active filter summary hid active constraints behind `N filters`
  - Problem: The first implementation could tell the user that filters were active without naming which host, branch, status, repo, source, idle, or search constraint was hiding rows.
  - Repair: `DockSessionProjection.summary(for:)` now names host, branch, status, repo, source, idle visibility, search text, result count, and partial state.
  - Evidence: `CodexDock/State/DockSessionProjection.swift`, `CodexDockTests/DockStoreTestsProjection.swift`.
  - Status: resolved in implementation

- [x] IMP-002 - Mixed online-plus-checking connectivity hid loaded-host truth
  - Problem: When at least one host had loaded and another was still checking, the global rollup could collapse to a generic checking state instead of telling the user that some real rows were already online.
  - Repair: `AppConnectivityStore` now rolls mixed online/checking hosts up to partial count copy such as `Online 1/2, checking 1`; all-checking still reports `Checking N hosts`.
  - Evidence: `CodexDock/State/AppConnectivityStore.swift`, `CodexDockTests/AppConnectivityStoreTests.swift`.
  - Status: resolved in implementation

- [x] THERMO-001 - Shared Dock test helper exposed fake host identity knobs
  - Problem: The shared test host helper accepted a fake display name and fake host ID path that production host identity does not use.
  - Repair: `DockStoreTestSupport.makeHost` now derives identity from a real relay endpoint only.
  - Evidence: `CodexDockTests/DockStoreTestSupport.swift`, `CodexDockTests/DockStoreScopeTests.swift`, `CodexDockTests/DockStoreTests.swift`.
  - Status: resolved in implementation

## Resolved Plan-Readiness Findings

- [x] PLA-001 - Partial-loading host-state seam was too late in the phase order
  - Lens: depth-first implementation risk / caller, invariant, and state model
  - Problem: The first draft put important mixed loaded-plus-checking UI behavior in Phase 5, after projection, lenses, and filters already needed that state.
  - Repair: Phase 1 now owns all-host idle/loading state, partial snapshot publication, loaded-subset projection, partial result counts, connectivity rollup updates, and tests before visible lenses widen.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1196`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1230`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1234`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1260`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1282`.
  - Status: resolved in plan

- [x] PLA-002 - First visible UI cutover lacked phase-local app proof
  - Lens: proof and phase exit
  - Problem: The first visible Dock cutover could have stopped at Swift unit tests.
  - Repair: Phase 2 now requires `rtk make app-test SIM='iPhone 17'` as primary blocking proof. `rtk make app SIM='iPhone 17'` is diagnostic only, unit tests are supporting only, and missing simulator observability must be fixed with hooks before the phase can pass.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1349`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1361`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1362`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1363`.
  - Status: resolved in plan

- [x] PLA-003 - Old Dock UI automation could keep the legacy IA alive
  - Lens: deletion and side-door closure / drift-proof coupling
  - Problem: `CodexDockUITests/CodexDockAutomationSmokeTests.swift` was not originally explicit enough as a cutover surface.
  - Repair: Phase 2 and the test inventory now require replacing old sort picker, idle toggle, old `DockTabID`, and old filter-tab usage, plus asserting old controls are absent.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1136`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1138`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1332`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1360`.
  - Status: resolved in plan

- [x] PLA-004 - Not-loaded filtering had two possible owners
  - Lens: ambiguity and miscommunication / canonical owner and SSOT
  - Problem: A separate not-loaded visibility mode plus status filtering would let two controls answer the same question.
  - Repair: `DockFilterState.statusKinds` is the only V1 owner. Default status `Any` includes `Not loaded`; not-loaded-only is selected by `Status: Not loaded`; there is no separate visibility control in V1.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:686`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:698`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1208`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1449`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1486`.
  - Status: resolved in plan

- [x] PLA-005 - Branch search ownership was ambiguous
  - Lens: canonical owner and SSOT / requirements, constraints, and simplicity
  - Problem: The first plan could be read as having both global row search and a branch-query field inside the filter model.
  - Repair: Global `searchText` owns branch lookup for actual rows. Branch chip search is local filter-surface option search only. `DockFilterState.selectedBranches` is the actual branch facet.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:626`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:633`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:637`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1056`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1442`.
  - Status: resolved in plan

- [x] PLA-006 - Partial host failure was not carried through every lens
  - Lens: caller, invariant, and state model / proof and phase exit
  - Problem: The plan said failures were local, but it did not say how `Newest`, `Host`, and `Branch` each render failed-host context.
  - Repair: The target architecture now has a per-lens partial-host-failure table; Phase 3 requires Newest feed rows, Host failed groups, Branch failed-host context, and tests.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:965`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:969`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1390`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1419`.
  - Status: resolved in plan

- [x] PLA-007 - Not-loaded rows needed explicit title/thread-id fallback
  - Lens: ambiguity and miscommunication / proof and phase exit
  - Problem: Unknown thread detail rows can have weak title data, so the implementation needed a visible identity fallback.
  - Repair: Phase 1 requires display title, then stable thread id or short thread-id fragment fallback, plus tests.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1223`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1253`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1293`.
  - Status: resolved in plan

- [x] PLA-008 - Host running-count requirement was undecided
  - Lens: requirements, constraints, and simplicity
  - Problem: Running remains an approved row status/filter, but host headers did not say whether they should surface running counts.
  - Repair: Host group headers show a running count when at least one visible row is `Running`; Phase 3 requires tests.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1377`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1397`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1412`.
  - Status: resolved in plan

- [x] PLA-009 - Loading skeleton behavior was undecided
  - Lens: requirements, constraints, and simplicity / outcome north star
  - Problem: Skeleton rows could look like fake sessions during a long relay load.
  - Repair: V1 explicitly rejects fake session skeleton rows and uses per-host loading rows plus neutral loading copy.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1509`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1510`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1533`.
  - Status: resolved in plan

- [x] PLA-010 - Relay settings host-display owner was under-named
  - Lens: code-truth map / canonical owner and SSOT
  - Problem: The plan described Relay settings behavior without naming the concrete state/view owners.
  - Repair: The plan now names `HostSettingsStore` and `HostsView`, and states the rule: short host name is title; endpoint remains visible detail.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:582`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1083`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1087`.
  - Status: resolved in plan

- [x] PLA-011 - Row-model changes missed `ThreadDetailStoreTestSupport.swift`
  - Lens: caller, invariant, and state model / drift-proof coupling
  - Problem: Changing `DockRowViewModel` without naming test support helpers risks compile failures outside Dock tests.
  - Repair: The test inventory and Phase 1 now require updating `CodexDockTests/ThreadDetailStoreTestSupport.swift` and shared test row factories.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1146`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1264`.
  - Status: resolved in plan

- [x] PLA-012 - Archive grouping was a projection side door
  - Lens: deletion and side-door closure / canonical owner and SSOT
  - Problem: `SessionRowProjector.sections(from:)` could keep Archive coupled to Dock's old grouping or be accidentally rewritten by Dock projection work.
  - Repair: The plan requires a canonical Dock `rows(from:)` path and preserves Archive grouping through archive-only section ownership or `ArchiveSessionProjector.sections(from:)`.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1069`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1071`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1226`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1227`.
  - Status: resolved in plan

- [x] PLA-013 - `lastActivity` mapping was stated too narrowly
  - Lens: code-truth map
  - Problem: The plan said `lastActivity` was mapped from `updatedAt`, but code also falls back to `createdAt`.
  - Repair: The plan now states that `SessionSummary.lastActivity` is the only normalized list date and current mapping prefers `updatedAt` while falling back to `createdAt`.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:121`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:180`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:312`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1725`.
  - Status: resolved in plan

- [x] PLA-014 - Simulator proof could still be downgraded to launch or unit-test evidence
  - Lens: proof and phase exit / testability
  - Problem: The prior audit wording still allowed a blocker-plus-launch substitute path, which left room to call user-visible Dock work complete without simulator UI/accessibility/log assertions.
  - Repair: The plan now makes `rtk make app-test SIM='iPhone 17'` the primary blocking proof for user-visible Dock behavior. Unit tests are supporting only; `rtk make app SIM='iPhone 17'` is diagnostic only; missing accessibility IDs, accessibility values, UI-test hooks, or log/accessibility exposure must be added; external simulator/Xcode/signing/service blockers leave the phase incomplete and unproven.
  - Evidence: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:117`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:118`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:147`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:149`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:150`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:151`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:330`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1585`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1658`, `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md:1659`.
  - Status: resolved in plan

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical mockup/spec | `docs/mockups/codex-dock-activity-first-2026-05-29/README.md`, requirements files | Source request for the activity-first Dock UX, filter surface, screens, and kill list. | Codex + fresh consult | read |
| Prior UX strategy | `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md` | Live iPhone 17 observation and UX reasoning input. | Codex | read |
| Architecture plan | `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md` | Whole-plan readiness target. | Codex + plan-audit agents + fresh consult | read and patched |
| Requirement disposition | `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md` | Exhaustive ID-level disposition for every formal `G-*` and `Sxx-*` requirement in the mockup package. | Codex + final fresh consult | generated and verified |
| Dock root/UI | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/Features/Dock/DockSharedViews.swift` | Current old tabs, search, sort, idle, host summary, row rendering, loading, and failure surfaces. | Codex + plan-audit agents | read |
| Dock store/projection | `CodexDock/State/DockStore.swift`, `CodexDock/State/DockSessionProjection.swift`, `CodexDock/State/SessionRowProjector.swift` | Canonical owners for status vocabulary, rows, grouping, loading, filtering, and list ordering. | Codex + plan-audit agents | read |
| Data mapping | `CodexDock/Models/SessionSummary.swift`, `CodexDock/AppServer/ThreadListDTO.swift`, `CodexDock/State/AppServerDockClient.swift` | Confirms `lastActivity` shape, `updatedAt`/`createdAt` mapping, and no relay DTO change. | Codex + plan-audit agents | read |
| Host/settings/connectivity | `CodexDock/Configuration/DockHostConfiguration.swift`, `CodexDock/State/HostSettingsStore.swift`, `CodexDock/Features/Hosts/HostsView.swift`, `CodexDock/State/AppConnectivityStore.swift`, `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | Host display-name ownership, Relay settings endpoint detail, and compact connectivity state. | Codex + plan-audit agents | read |
| Archive side door | `CodexDock/State/ArchiveStore.swift`, `CodexDock/Features/Archive/ArchiveView.swift` | Ensures Dock projection cutover does not rewrite archive grouping accidentally. | Codex + plan-audit agents | read |
| Automation/tests | `CodexDock/Automation/AutomationID.swift`, `CodexDockUITests/CodexDockAutomationSmokeTests.swift`, `CodexDockTests/DockStoreTests*.swift`, `CodexDockTests/AutomationIDTests.swift`, `CodexDockTests/ThreadDetailStoreTestSupport.swift` | Confirms old UI automation side doors and compile surfaces are named in the plan. | Codex + plan-audit agents | read |
| Runnable commands | `Makefile`, `project.yml`, `Package.swift`, `package.json` | Confirms Makefile-owned simulator-first proof and relevant supporting test commands. | Codex + plan-audit agents | read |
| External UX grounding | Apple HIG search/tab guidance, NN/g scanning/information scent/faceted navigation, Baymard large-list guidance as summarized in the plan | Validates the UX premise: search first, explicit facets, stable tabs, row-level scent. | Codex + fresh consult | read/summarized |

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
- [x] Conditional lens: docs-contract-drift
- [x] Conditional lens: security-boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Decision | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- |
| ADL-001 | What does `Not loaded` filtering mean? | It is status filtering only; no rate-limit or second visibility model. | Plan lines 698-704, 1449-1451, 1485-1487. | resolved |
| ADL-002 | Which search owns branch lookup? | Global `searchText` filters rows; local branch chip search only finds chips; selected branch chips filter rows. | Plan lines 626-639, 1442-1459. | resolved |
| ADL-003 | Does Dock V1 include archived sessions? | No. Archive stays in `ArchiveStore`/`Archive` tab; Dock has no fake archive toggle. | Plan lines 128, 710-713, 1452-1453. | resolved |
| ADL-004 | How does loading represent unknown rows? | Per-host loading rows and neutral copy; no fake session skeletons. | Plan lines 1509-1510, 1533. | resolved |
| ADL-005 | What date does default newest use? | `SessionSummary.lastActivity`; current mapping prefers `updatedAt` and falls back to `createdAt`; no created-date sort in V1. | Plan lines 121, 180, 252, 1725. | resolved |

## Fresh Consult Check

Runtime: Cursor Agent `composer-2.5-fast`

Initial run directory: `/tmp/fresh-consult/codex-dock-activity-plan-20260529T171134Z-FyTOFT`

Final re-check run directory: `/tmp/fresh-consult/codex-dock-activity-final-recheck-20260529T173150Z-go6rrR`

Initial verdict: `pass-with-notes`

Final re-check verdict: `pass-with-notes`

Blocking findings: none.

Initial notes handled in this audit:

- Requirements disposition matrix is assigned to Phase 6.
- External research grounding was marked done in the plan receipt block.
- Optional host-count shortcut pills, debounce, and pinning were decided out of V1 or invisible implementation detail.

Final re-check result:

- The repaired plan package satisfies the exhaustiveness bar for planning.
- The requirement-disposition sidecar now enumerates all 394 formal source requirement IDs.
- The five prior final-check notes are repaired: requirement matrix, `S01-012`, `S06-007`, `S06-025`, and `G-103`.
- The only final non-blocking note was sidecar count metadata; it was corrected after the re-check from 397 to 394 formal IDs.

## Audit Synthesis

VERDICT: complete
Confidence: high
Scope reviewed: whole plan plus activity-first Dock implementation

The plan is implemented for the simulator-first V1 scope. The shipped code follows the core product decision, keeps one projection owner, keeps explicit filter/search ownership, and removes the major side doors that could preserve the old Dock IA: legacy primary tabs, old sort picker, status-priority ordering, UI smoke tests that drive old controls, archive grouping through Dock projection, and ambiguous not-loaded filtering.

The proof model stayed simulator-first. `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'` passed with `233` total tests, `228` passed, `5` skipped, and `0` failed. Supporting Swift checks also passed for Dock store/projection, connectivity, host configuration, and automation IDs.

The plan package now includes `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md`, which maps all 394 formal source requirement IDs to a V1 disposition, owner/proof path, or explicit out-of-V1/N/A decision.

Physical iPhone validation is not claimed in this audit. The implementation work changed Swift app/test files, the generated Xcode project, README, and this plan/audit/worklog package; it did not change the relay protocol, app-server DTOs, secrets, `.env`, Makefile, or Node relay behavior.

## Pass History

### Pass 1 - Arch-Step Auto Plan - 2026-05-29T16:53:39Z to 2026-05-29T17:11:14Z

- Mode: `$arch-step auto-plan`
- Scope: whole activity-first Dock implementation plan
- Receipts completed: `research`, `deep-dive-pass-1`, `deep-dive-pass-2`, `phase-plan`, `consistency-pass`
- Stage-gate result before audit repairs: `READY next=implement-loop`
- Agents/lenses run: arch consistency explorers plus self-integrator
- Verdict: ready for external/readiness audit

### Pass 2 - Fresh Consult - 2026-05-29T17:11Z

- Mode: `$fresh-consult`
- Runtime/model: Cursor Agent `composer-2.5-fast`
- Run directory: `/tmp/fresh-consult/codex-dock-activity-plan-20260529T171134Z-FyTOFT`
- Scope: exhaustiveness versus the mockup spec and repo code
- Verdict: `pass-with-notes`
- Blocking findings: none
- Notes resolved or assigned: research grounding marked done, optional shortcuts/pinning/debounce decisions recorded, requirement disposition assigned to Phase 6

### Pass 3 - Plan Audit - 2026-05-29T17:23:26Z

- Mode: `$plan-audit`
- Scope: whole plan
- Baseline reviewed: architecture plan, mockup package, relevant Dock/Store/Projection/Archive/Host/Connectivity/Test code surfaces, Makefile/project/package command owners
- Agents/lenses run:
  - `019e74ba-1665-77c1-8b4a-c4b650a352d5` / Heisenberg: code-truth map and canonical owner/SSOT
  - `019e74ba-195b-73f1-a79c-e088f0b84545` / Parfit: requirements, constraints, simplicity, ambiguity, and miscommunication
  - `019e74ba-1c16-7063-84fb-ea7c4bf8988f` / Archimedes: depth-first risk, proof/phase exit, deletion/side-door closure
- Findings added: `PLA-001` through `PLA-013`
- Findings resolved: `PLA-001` through `PLA-013`
- Findings carried forward: none
- Verdict: ready

### Pass 4 - Final Fresh-Consult Re-check And Audit Update - 2026-05-29T17:33:47Z

- Mode: `$fresh-consult` re-check plus plan-audit ledger update
- Runtime/model: Cursor Agent `composer-2.5-fast`
- Run directory: `/tmp/fresh-consult/codex-dock-activity-final-recheck-20260529T173150Z-go6rrR`
- Scope: final repaired plan package, requirement-disposition sidecar, source requirements, and prior fresh-consult notes
- Fresh-consult verdict: `pass-with-notes`
- Blocking findings: none
- Non-blocking notes: sidecar count metadata overstated formal requirement IDs as 397 rather than 394; `S01-012` still permits a bounded accessibility-only/non-wasting label if implementation proof needs it
- Repairs after re-check: sidecar regenerated with a strict formal requirement-ID parser; verified `source_unique_ids 394`, `sidecar_rows 394`, `missing []`, `extra []`
- Verdict: ready

### Pass 5 - Simulator-First Strengthening - 2026-05-29T17:40:02Z

- Mode: user-directed plan strengthening plus audit-ledger update
- Scope: verification gates, Phase 2 proof, Phase 6 final proof, Section 8 verification strategy, rollout proof language
- Findings added: `PLA-014`
- Findings resolved: `PLA-014`
- Findings carried forward: none
- Verdict: ready

### Pass 6 - Initial Implementation Audit - 2026-05-29T18:31:35Z

- Mode: implementation audit after first activity-first Dock code cut
- Scope: Dock projection, Dock UI, filter surface, host/branch grouping, not-loaded vocabulary, simulator hooks, docs, and generated Xcode project
- Code findings added: none in the first pass
- Code blockers carried forward: none in the first pass
- Supporting check: `rtk swift test --filter DockStoreTests`
  - Result: passed at that point, `32` tests, `0` failures.
- Primary simulator proof at that point: `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`
  - Result: passed.
  - Result bundle: `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_13-30-00--0500.xcresult`
  - Summary: `230` total tests, `225` passed, `5` skipped, `0` failed.
- Follow-up: continuation review later tightened active-filter summary, mixed checking/online connectivity, and shared test-helper fidelity, then reran the final simulator proof.

### Pass 7 - Final Implementation Audit And Thermonuclear Review - 2026-05-29T18:45:41Z

- Mode: implementation-audit check plus thermonuclear code-quality review
- Scope: full activity-first Dock implementation, including plan, audit log, worklog, `DockStore`, `DockSessionProjection`, `SessionRowProjector`, `DockView`, `DockFilterSurfaceView`, `DockGroupRows`, `DockSharedViews`, `AppConnectivityStore`, `DockHostConfiguration`, `ArchiveSessionProjector`, `ArchiveStore`, `AutomationID`, UI smoke tests, DockStore/AppConnectivity/DockConfiguration/AutomationID tests, README, and generated Xcode project wiring
- Findings added and resolved: `IMP-001`, `IMP-002`, `THERMO-001`
- Findings carried forward: none
- Supporting checks:
  - `rtk swift test --filter DockStoreTests` passed, `33` tests, `0` failures.
  - `rtk swift test --filter AppConnectivityStoreTests` passed, `13` tests, `0` failures.
  - `rtk swift test --filter DockConfigurationTests` passed, `29` tests, `0` failures.
  - `rtk swift test --filter AutomationIDTests` passed, `3` tests, `0` failures.
  - `rtk git diff --check` passed with no output.
- Primary simulator proof:
  - Command: `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`
  - Result: passed.
  - Result bundle: `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_13-43-11--0500.xcresult`
  - Simulator: `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`, iOS Simulator `26.5`, OS build `23F77`.
  - Summary: `233` total tests, `228` passed, `5` skipped, `0` failed.
  - Dock UI smoke tests passed: `testDockLensesAndFiltersAreDrivableInSimulator()`, `testDockRowOpensSessionDetailByIdentifierWhenRowsExist()`, `testDockScreenExposesControlsAndConnectivityByIdentifier()`, and `testRelaySettingsFormIsDrivableByIdentifier()`.
- Environment note: `SIM='iPhone 17'` is ambiguous on this Mac because two simulators match that name, so final proof used the booted iPhone 17 UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Operator note: app UI tests foreground and drive Simulator, so they can steal macOS focus. The plan now records that these tests should not be rerun casually after a passing proof.
- Verdict: approve / complete

## Commands Run For Audit

- `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md`
  - Result: `READY next=implement-loop`
- `rtk rg` and exact `rtk sed`/`rtk nl` reads over the plan and relevant docs
- Stale-marker search over the plan doc for unresolved placeholders, old not-loaded owner names, old branch query state, vague exit wording, and stale date-mapping claims.
  - Result: no matches
- Stale simulator-proof downgrade search over the plan and audit log for known old downgrade wording.
  - Result: no matches
- Simulator-proof language review over the plan and audit log for `unit tests alone`, `diagnostic only`, `not completion proof`, and `app-test`.
  - Result: only the intended strict-proof and diagnostic-only language remains
- `rtk rg -n '[ \t]+$' docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29_PLAN_AUDIT.md docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md`
  - Result: no trailing whitespace matches
- `rtk git diff --check -- docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29_PLAN_AUDIT.md docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md`
  - Result: clean
- Requirement-ID diff after sidecar generation:
  - Result: `source_unique_ids 394`, `sidecar_rows 394`, `missing []`, `extra []`
- Fresh consult command recorded in `/tmp/fresh-consult/codex-dock-activity-plan-20260529T171134Z-FyTOFT`
- Final fresh-consult re-check command recorded in `/tmp/fresh-consult/codex-dock-activity-final-recheck-20260529T173150Z-go6rrR`

Implementation follow-up commands were run after the docs-only planning pass:

- `rtk swift test --filter DockStoreTests`
  - Final result: passed, `33` tests, `0` failures.
- `rtk swift test --filter AppConnectivityStoreTests`
  - Final result: passed, `13` tests, `0` failures.
- `rtk swift test --filter DockConfigurationTests`
  - Final result: passed, `29` tests, `0` failures.
- `rtk swift test --filter AutomationIDTests`
  - Final result: passed, `3` tests, `0` failures.
- `rtk git diff --check`
  - Final result: passed with no output.
- Old-Dock-vocabulary scans over `CodexDock`, `CodexDockTests`, `CodexDockUITests`, and `README.md`
  - Final result: no live `DockTabID`, `DockTabViewModel`, old sort/filter/idle controls, `DockRowStatusKind.failed`, visible `Limited`, or primary `Needs me` path remained. Remaining matches were expected README/product clarification and negative assertions.
- `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`
  - Result: passed.
  - Final result bundle: `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_13-43-11--0500.xcresult`
  - Final summary: `233` total tests, `228` passed, `5` skipped, `0` failed.
