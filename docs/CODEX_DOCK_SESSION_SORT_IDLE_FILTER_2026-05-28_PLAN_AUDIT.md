# Plan Audit Log

Plan: docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md
Audit log: docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28_PLAN_AUDIT.md
Current plan verdict: ready
Current implementation code-review verdict: approved
Last reviewed: 2026-05-28T22:11:59Z
Scope: whole plan

## Current Blocking Findings

Open blockers: none.

- [x] PLA-001 - Consistency readiness line could be mistaken for execution authorization
  - Lens: Deletion and side-door closure; proof and phase exit.
  - Evidence: The plan is planning-only and says no implementation before audit in TL;DR and planning metadata. The consistency block also contains `Decision: proceed to implement? yes`, which ArcStep needs for readiness.
  - Required plan repair: Keep the ArcStep readiness value, but carry an explicit no-implementation boundary beside it and in the Decision Log.
  - Status: resolved.
  - Resolution evidence: `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md` now states `Execution authorization: no; this is ArcStep consistency readiness only. The plan still stops after plan-audit until the user explicitly requests implementation.` The Decision Log also says the `Decision: proceed to implement? yes` field is a readiness gate only, not execution authorization.

- [x] PLA-002 - New Swift source file proof omitted XcodeGen regeneration
  - Lens: Code-truth map; canonical owner and single source of truth; proof and phase exit.
  - Evidence: The plan adds `CodexDock/State/DockSessionProjection.swift`. `project.yml` is the source of truth for `CodexDock.xcodeproj`, and the generated project has explicit source entries.
  - Required plan repair: Require `rtk xcodegen generate --spec project.yml` after the new Swift source is added and before generated-project build proof.
  - Status: resolved.
  - Resolution evidence: Phase 1 verification requires `rtk xcodegen generate --spec project.yml` after adding `CodexDock/State/DockSessionProjection.swift`. Phase 2 verification repeats XcodeGen before the generated-project build.

- [x] PLA-003 - Reopened Branch ordering requirement contradicted the old base-order posture
  - Lens: Ambiguity and miscommunication; caller, invariant, and state model; proof and phase exit.
  - Evidence: The user clarified that Branch sort should still show most recently changed work first. The prior plan preserved branch/host grouping but also preserved base section order after filtering, which would keep status-priority-first ordering in Branch mode.
  - Required plan repair: Keep Branch grouping, but make final Dock-visible Branch section and row order newest-visible-activity-first after selected tab, search, and Idle filtering. Record the old posture as superseded, not current.
  - Status: resolved.
  - Resolution evidence: The plan now states that Branch groups are ordered by the newest visible row, Branch rows are ordered by `lastActivityDate` descending, status/title/stable ids are tie-breakers only, and the 2026-05-28 Branch recency Decision Log entry supersedes the old base-order detail.

- [x] PLA-004 - Automatic update requirement needed explicit projection and UI proof
  - Lens: Depth-first implementation risk; code-truth map; proof and phase exit.
  - Evidence: The new requirement says everything automatically updates and orders appropriately. Without a plan requirement against cached projected sections, `DockView` could hold stale order outside the current snapshot/options render path.
  - Required plan repair: Require `DockSessionProjection` to be derived from current `DockSnapshot` plus current `DockSessionProjectionOptions`, and require Phase 2 UI proof that changing selected tab, search, sort, or Idle uses a fresh projection without server reload or stale UI order.
  - Status: resolved.
  - Resolution evidence: Phase 1 now requires Branch order recalculation after search/Idle filtering and snapshot activity-date changes. Phase 2 now requires building projection during the loaded render path, forbids storing projected rows/sections/order in independent `@State`, and requires focused manual/Mobile MCP proof of immediate reordering. The plan also scopes data-driven automatic updates to existing refresh paths that publish new `DockSnapshot` values, explicitly excluding new realtime push, relay method, or backend subscription work.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

Open implementation findings: none.

- [x] IMP-001 - Phase 2 visual proof was not yet proven by runtime evidence
  - Lens: Proof and phase exit.
  - Evidence: Static review showed the normal controls row was shaped as one
    `HStack`, but Phase 2 required simulator or Mobile MCP proof for normal
    iPhone-width one-row layout and large Dynamic Type/no-clipping behavior.
  - Required repair: Capture simulator/Mobile MCP proof before claiming Phase 2
    exit.
  - Status: resolved.
  - Resolution evidence: Mobile MCP simulator proof on
    `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` showed Search, Branch/Newest, and
    `Idle` in one normal-width row. The large Dynamic Type pass with
    `accessibility-extra-large` showed the responsive fallback without control
    clipping. Screenshots were saved under
    `/tmp/codex-client/session-sort-idle/`.

- [x] IMP-002 - Initial Idle control exposed stale accessibility state
  - Lens: Accessibility and proof.
  - Evidence: After tapping `Idle`, the visual checkbox and counts changed, but
    Mobile MCP still reported the control value as `0`.
  - Required repair: Make the Idle control expose explicit, current
    accessibility state.
  - Status: resolved.
  - Resolution evidence: `CodexDock/Features/Dock/DockView.swift` now uses a
    direct checkbox button with accessibility label `Show idle threads`, value
    `Off`/`On`, and selected trait. Mobile MCP reported `Off` on fresh launch
    and `On` after tapping.

- [x] IMP-003 - Selected-tab Branch reorder coverage gap
  - Lens: Caller, invariant, and state model.
  - Evidence: Initial projection tests covered search, Idle, and refreshed
    snapshot dates, but did not directly prove selected-tab changes recompute
    Branch section order from visible rows.
  - Required repair: Add focused test coverage.
  - Status: resolved.
  - Resolution evidence:
    `CodexDockTests/DockStoreTestsProjection.swift` now includes
    `testBranchProjectionReordersAfterSelectedTabChanges`, and
    `rtk swift test --filter DockStoreTests` passed with 27 tests.

- [x] IMP-004 - Search field coverage gap
  - Lens: Drift-proof coupling.
  - Evidence: Initial tests directly covered label, host display name, and
    thread id, while the plan requires more fields.
  - Required repair: Add assertions for more documented search fields.
  - Status: resolved.
  - Resolution evidence:
    `testProjectionSearchMatchesLabelHostAndThreadID` now also covers host id,
    branch, status label, and summary. `rtk swift test --filter DockStoreTests`
    passed with 27 tests.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/Features/Dock/DockView.swift`: `selectedTab`, `searchText`, `controls`, `currentTabs`, `loadedContent`, `filteredSections`, `matchesSearch`, empty copy | Confirms current Dock UI owns tab/search state, full-width search row, UI-only search filtering, and direct raw snapshot usage | Parent, prior audit agents, fresh repo-evidence agent | read |
| Canonical owner path | `CodexDock/State/DockStore.swift`: `DockRowStatusKind.idle`, `DockTabID.includes(_:)`, `DockSnapshot.sections(for:)`, `DockStore.makeSnapshot` | Confirms current tab membership, raw tab counts, snapshot section helper, and base snapshot assembly | Parent, prior audit agents, fresh repo-evidence agent | read |
| Canonical owner path | `CodexDock/State/SessionRowProjector.swift`: `sections(from:)`, `sectionID`, `sectionTitle`, `sectionPrecedes`, `rowPrecedes`, `statusPriority` | Confirms current branch/host grouping and status/newest/title ordering that raw/Archive behavior can preserve while Dock-visible Branch ordering moves to projection | Parent, prior audit agents, fresh repo-evidence agent, fresh reopened-requirement agent | read |
| Caller families | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/State/ArchiveStore.swift` | Confirms Dock renders live rows while Archive reuses `SessionRowProjector.sections(from:)` and should not receive Dock sort controls | Parent, prior audit agents, fresh repo-evidence agent | read |
| Legacy and side-door paths | `DockSnapshot.tabs`, `DockSnapshot.sections(for:)`, `DockView.filteredSections(_:)`, `DockView.matchesSearch(_:)` | Confirms current side doors that can preserve old behavior if Dock UI is not moved to `DockSnapshot.project(options:)` | Parent, prior audit agents, fresh repo-evidence agent | read |
| Adjacent same-contract paths | `README.md`, `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md`, `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`, `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md` | Confirms live docs that can drift after Branch/Newest and Idle visibility behavior lands | Prior audit agents, fresh repo-evidence agent, parent spot-checks by plan anchors | read |
| Comparable patterns | `DockTabID.includes(_:)`, existing SwiftUI segmented picker/search field, `SessionRowProjector` test shape | Confirms the plan uses existing local projection/test style rather than new service/API concepts | Parent, prior audit agents, fresh repo-evidence agent | read |
| Contract/proof surfaces | `CodexDockTests/DockStoreTests.swift`, `CodexDockTests/DockStoreScopeTests.swift`, `Package.swift`, `project.yml`, `CodexDock.xcodeproj/project.pbxproj` | Confirms the named tests, SwiftPM coverage, and XcodeGen regeneration requirement for the new source file | Parent, prior audit agents, fresh repo-evidence agent | read |

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

Conditional lens notes:

- Docs-contract drift is triggered and covered by Phase 3.
- Project/generated artifact drift is triggered by the new Swift file and covered by XcodeGen proof in Phases 1 and 2.
- Physical Mobile MCP is not required for plan readiness; Phase 2 allows simulator/local proof if physical Mobile MCP hits the repo-documented WDA blocker.
- Security/protocol boundary is checked as out of scope: the plan forbids relay, app-server DTO, query, secret, and transport changes.

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Does Idle apply to every Dock tab or change tab membership? | Hide idle everywhere when off; redefine tab buckets; only hide in Running | Could change counts, tab meaning, and agent rows | Toggle applies in every tab, but idle rows reappear only where `DockTabID.includes(_:)` places them | User objective plus repo truth | Sections 0.1, 0.4, 5.3, 5.4, 7 Phase 1/2 | resolved |
| DEC-002 | What happens to old `DockSnapshot.tabs` and `sections(for:)`? | Delete immediately; keep as raw compatibility; route through projection | Could leave Dock UI on old counts/filtering | Keep raw compatibility helpers but stop Dock UI from using them | Agent from repo evidence | Sections 5.2, 6.1, 6.2, 7 Phase 1 | resolved |
| DEC-003 | What fields should search match? | Current narrow row fields; live UX spec fields | Could ship stale search behavior while touching search code | Projection search matches title, repo/cwd, branch, summary, status label, app-local label, host name/id, and thread id | Agent from UX spec evidence | Sections 0.4, 5.3, 6.1, 7 Phase 1 | resolved |
| DEC-004 | Is `Decision: proceed to implement? yes` permission to implement? | Yes, start code; no, ArcStep readiness only | Could violate the user's no-implementation boundary | It is readiness only; implementation remains unauthorized until the user asks | User objective plus ArcStep gate contract | Consistency block and Decision Log | resolved |
| DEC-005 | Does the generated Xcode project need regeneration after the new Swift file? | SwiftPM tests are enough; XcodeGen must run before Xcode build | Could miss the new source in app-target proof | Run `rtk xcodegen generate --spec project.yml` before generated-project build proof | Repo instructions | Phase 1 and Phase 2 verification | resolved |
| DEC-006 | In Branch mode, does grouping preserve old status-priority order or become newest-first? | Preserve old status-first grouped order; keep grouping but order visible groups/rows by recency | Could ship Branch as old status-first behavior despite the user's new instruction | Branch preserves branch/host grouping but orders visible groups and rows by newest activity first | User clarification | Sections 0.2, 0.4, 0.5, 5.2, 5.3, 5.4, 6.1, 7 Phase 1/2, Decision Log | resolved |
| DEC-007 | What does "automatically updates and orders appropriately" require architecturally? | Rely on current render recomputation informally; explicitly forbid cached projected order and test option/snapshot changes | Could leave stale UI order after data/control changes | Projection is derived from current `DockSnapshot` plus current options, and `DockView` must not store projected rows/sections/order in independent `@State` | User clarification plus repo truth | Sections 0.2, 0.5, 5.4, 6.1, 7 Phase 1/2, 8, 9.3, Decision Log | resolved |
| DEC-008 | Does automatic data update imply new realtime infrastructure? | Use existing refresh/published snapshot path; add a new push stream/event subscription | Could accidentally expand this UI plan into relay/backend protocol work | Use existing Dock refresh paths and published loaded snapshots only; no new push stream, relay method, or backend subscription | Repo truth plus scope constraints | Sections 0.2, 0.5, 5.4, 6.1, 7 Phase 2 | resolved |

## Pass History

### Pass 1 - 2026-05-28T18:19:46Z

- Mode: plan-readiness.
- Scope: whole plan.
- Baseline reviewed: current worktree plan at `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md`.
- Test/CI context accepted, if supplied: none; no implementation code exists for this plan yet.
- Agents/lenses run: prior consistency explorers, prior plan-audit explorers, fresh plan-text agent, fresh repo-evidence agent, and parent synthesis; fresh parent re-read of current plan/code anchors before creating this log.
- Code areas read: `DockView`, `DockStore`, `SessionRowProjector`, `ArchiveStore`, `DockStoreTests`, `DockStoreScopeTests`, `project.yml`, plus adjacent live docs named by the plan.
- Findings added: PLA-001, PLA-002.
- Findings resolved: PLA-001, PLA-002.
- Findings carried forward: none.
- Verdict: ready.
- Next audit focus: after implementation exists, run implementation-audit against Phase 1 through the current implemented frontier before claiming code approval.

### Pass 2 - 2026-05-28T18:59:37Z

- Mode: plan-readiness after reopened requirement.
- Scope: Branch ordering, automatic projection update behavior, Section 7 phase fit, and audit freshness.
- Baseline reviewed: current worktree plan at `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md` after the user clarified Branch newest-first and automatic update behavior.
- Test/CI context accepted, if supplied: none; no implementation code exists for this plan yet.
- Agents/lenses run: fresh plan-text reopened-requirement agent, fresh repo-recompute agent, parent synthesis, and ArcStep readiness check.
- Code areas read: `DockView`, `DockStore` / `DockSnapshot`, `SessionRowProjector`, plan Sections 0-10, and prior audit sidecar.
- Findings added: PLA-003, PLA-004.
- Findings resolved: PLA-003, PLA-004.
- Findings carried forward: none.
- Verdict: ready.
- Next audit focus: after implementation exists, verify Phase 1 code makes Dock-visible Branch groups and rows newest-visible-first and verify Phase 2 does not cache projected rows, sections, or order in independent UI state.

### Pass 3 - 2026-05-28T22:11:59Z

- Mode: implementation-audit.
- Scope: implemented Phase 1 and Phase 2 frontier.
- Baseline reviewed: current worktree implementation for
  `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md`.
- Test/CI context accepted:
  - `rtk swift test --filter DockStoreTests` passed with 27 tests.
  - `rtk swift test --filter DockStoreScopeTests` passed with 7 tests.
  - `rtk xcodegen generate --spec project.yml` passed.
  - Exact `iPhone 17` simulator build failed only because no exact simulator
    named `iPhone 17` exists.
  - Closest iOS 26 simulator build passed on
    `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
  - `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'` passed.
  - Mobile MCP physical iPhone path stopped at `WebDriverAgent is not running
    on device`; simulator proof was used per repo instructions.
- Agents/lenses run: parallel implementation-audit subagent, parallel
  thermo-nuclear code-quality subagent, parent static review, parent simulator
  proof review, and parent final synthesis.
- Code areas read: `DockSessionProjection`, `DockView`,
  `DockStoreTestsProjection`, `DockStoreScopeTests`, README, thread-state docs,
  iPhone UX spec, and iOS 26 modernization plan.
- Findings added: IMP-001, IMP-002, IMP-003, IMP-004.
- Findings resolved: IMP-001, IMP-002, IMP-003, IMP-004.
- Findings carried forward: none.
- Verdict: implementation approved.
- Next audit focus: no remaining audit focus for this plan before commit
  readiness.
