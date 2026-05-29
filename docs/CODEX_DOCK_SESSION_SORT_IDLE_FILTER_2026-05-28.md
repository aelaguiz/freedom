---
title: "Codex Dock - Session Sort And Idle Filter - Architecture Plan"
date: 2026-05-28
status: implemented
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28_PLAN_AUDIT.md
  - docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28_WORKLOG.md
  - docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28_THERMONUCLEAR_REVIEW.md
  - docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md
  - docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md
  - README.md
---

# TL;DR

- Outcome: Dock gets one compact controls row where the search field is narrower, a canonical sort control sits to its right, and an unchecked `Idle` checkbox controls whether idle rows are visible across every Dock filter tab.
- Problem: The current Dock screen has a full-width custom search row and only one built-in projection: rows are grouped by branch/host and ordered by status priority plus newest activity. A user who wants newest active sessions first has no control, and idle rows are always mixed into the active-work tabs.
- Approach: Add a small Dock projection contract that owns sort mode, Branch/Newest ordering, live reordering, and idle visibility before rows are rendered. Keep the server query, archive behavior, host fan-out, and row model unchanged.
- Plan: First move branch/newest ordering and idle filtering into a pure model/store projection path with tests, then wire one SwiftUI control row that applies the same settings to all Dock filter tabs, then do a focused build/manual pass before the glass modernization plan touches the same control surface.
- Non-negotiables: no server/API sort change, no new app tab, no persistence unless explicitly added later, no tab count advertising rows hidden by search or Idle, no UI-only duplicate sorting rules, and no implementation before this plan is audited.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: not required for this local UI/model change
deep_dive_pass_2: done 2026-05-28
recommended_flow: research -> deep dive -> phase plan -> consistency-pass -> plan-audit -> stop until implementation is explicitly requested
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions, plan-audit findings, or the user's no-implementation boundary.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:85093a59c53be48a01a1be5d43ec631807e589b0582cdc5f0cfafb8ef39cc2b0",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T17:38:45Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:b27c5caacaf304e119a71d522edece23155741e78cc83cc423e142e153c7275c",
      "completed_at": "2026-05-28T17:39:11Z",
      "doc_hash_after": "sha256:71ad9ab47b2f485055f0815c85904b36375e5c4ad59a7010d8bb473acdfa4176"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T17:39:16Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:71ad9ab47b2f485055f0815c85904b36375e5c4ad59a7010d8bb473acdfa4176",
      "completed_at": "2026-05-28T17:40:57Z",
      "doc_hash_after": "sha256:e93949611fe51917642f8b59ce235d979824c723ae5a06e0e74f796fb34ec22d"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T17:41:02Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e93949611fe51917642f8b59ce235d979824c723ae5a06e0e74f796fb34ec22d",
      "completed_at": "2026-05-28T17:41:48Z",
      "doc_hash_after": "sha256:3573bbc105cffbf69368b76961d63a6e53cce42df0c696ac7dce24679790911b"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T17:41:55Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:3573bbc105cffbf69368b76961d63a6e53cce42df0c696ac7dce24679790911b",
      "completed_at": "2026-05-28T17:42:36Z",
      "doc_hash_after": "sha256:b262004d81b8265737b34b6fe5d1e1a5cb49bb419d99964213aa0b221f3ca6f2"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T17:42:41Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:b262004d81b8265737b34b6fe5d1e1a5cb49bb419d99964213aa0b221f3ca6f2",
      "completed_at": "2026-05-28T18:00:50Z",
      "doc_hash_after": "sha256:f8cfc107c21fe3c4fe16114130a0df8da60631a5084f452e4c4d26eb610c08ac"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this plan is implemented, a user on the Dock screen can keep using the
existing filter tabs, search sessions with a smaller field, choose either
Branch grouping or Newest ordering from a single sort control, and toggle an
unchecked `Idle` checkbox to include idle rows. The Idle toggle applies in
every Dock tab: unchecked hides `.idle` rows, and checked makes `.idle` rows
eligible only in the tabs where `DockTabID.includes(_:)` places them.

## 0.2 In scope

- Dock screen controls in `CodexDock/Features/Dock/DockView.swift`.
- A canonical Dock projection model for:
  - sort mode: Branch and Newest
  - idle visibility: unchecked by default, show idle only when enabled
  - search predicate
  - selected Dock filter tab
- Preserve current branch/host grouping as the Branch sort mode.
- In Branch mode, preserve branch/host grouping but order branch groups by the
  newest visible row in each group and order rows inside each branch by newest
  activity first.
- Add Newest sorting so the most recently active visible sessions appear first
  without branch section grouping.
- Apply sort mode, search, selected tab, and idle visibility as one projection
  across All, Needs me, Running, Limited, and Agents tabs.
- Recompute the projection automatically whenever loaded Dock rows, selected
  tab, search text, sort mode, or Idle visibility changes; do not keep a stale
  cached order.
- Automatic data updates use the existing Dock refresh/published snapshot path;
  this plan does not add a new push stream, timer, relay event, or backend
  subscription.
- Update Dock tab counts to match the same projection settings the user sees,
  rather than counting rows hidden by the idle toggle.
- Add focused tests for the projection behavior and the default idle-hidden
  state.
- Place this work before the iOS 26 glass/design modernization touches Dock
  search and controls.

## 0.3 Out of scope

- Implementing the iOS 26 glass/design modernization itself.
- Replacing the top-level app tabs: Dock, Archive, Relay.
- Changing relay protocol, `thread/list` query params, page limits, archive
  semantics, source-scope fan-out, or host routing.
- Persisting sort mode or idle visibility across app launches.
- Adding a new backend filter, API-level idle suppression, or server-side sort.
- Changing Thread detail, Archive, Relay settings, voice, transcription, or
  request-card behavior.
- Adding screenshot-golden infrastructure.

## 0.4 Definition of done (acceptance evidence)

- A new Dock projection API owns Branch/Newest ordering and idle visibility
  rules in one place.
- Default visible Dock rows exclude `.idle` status rows across every Dock filter
  tab.
- The Idle toggle applies in every Dock filter tab: when off it hides all
  `.idle` rows, and when on `.idle` rows are eligible only in tabs where
  `DockTabID.includes(_:)` places them.
- Branch mode preserves branch/host section behavior while ordering branch
  groups by newest visible activity first and ordering rows inside each branch
  by newest activity first.
- Newest mode renders a flat newest-first session list without branch section
  grouping.
- Search still matches title, repository or working directory, branch, summary,
  status label, app-local label, host display name or id, and thread id.
- Dock tab counts reflect the current search and idle visibility projection.
  Sort mode never changes counts.
- The controls row keeps Search, Sort, and Idle on the same line where width
  allows and degrades cleanly on small widths/Dynamic Type.
- `rtk swift test --filter DockStoreTests` passes after behavior changes.
- `rtk swift test --filter DockStoreScopeTests` passes.
- The generated app target builds after UI changes with the relevant Xcode
  build command from `AGENTS.md`.

## 0.5 Key invariants (fix immediately if violated)

- Dock projection rules are single-source, not duplicated between SwiftUI and
  tests.
- The server remains asked for broad active human and agent scopes; this change
  only changes local visibility and ordering.
- Search, sort, selected tab, and idle visibility compose deterministically.
- Projection output is derived from the current snapshot plus current UI
  options every time the Dock renders; no separate cached order can go stale.
- "Automatically updates" means every render derives from current UI state and
  every newly published loaded snapshot reorders on the next projection; it does
  not mean adding realtime push infrastructure.
- The default UI must not show idle threads.
- Branch mode remains recognizable as the current host/branch grouped Dock.
- Branch mode uses recency as the primary order inside the grouped model:
  branch groups and visible rows are newest-activity-first, with deterministic
  tie-breaks only after recency.
- Newest mode must not reorder by branch before recency.
- Hidden idle rows must not silently change archive, metadata, or navigation
  behavior; they are filtered from visibility, not deleted.
- No runtime fallback or shim path is introduced.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Make newest-first scanning fast for active work.
2. Hide idle rows by default without losing them when the user asks for them.
3. Keep one canonical projection path for search, tab filtering, sort, and idle.
4. Keep Branch mode grouped but still newest-first within that grouped shape.
5. Preserve existing Dock loading, scope deduplication, host, archive, and local
   metadata behavior.
6. Keep the controls compact and compatible with the upcoming iOS 26 design
   modernization.
7. Use small, behavior-level tests rather than brittle UI screenshots.

## 1.2 Constraints

- Current Dock UI stores `selectedTab` and `searchText` as local SwiftUI state.
- Current `DockSnapshot.sections(for:)` filters rows by `DockTabID`.
- Current `SessionRowProjector` groups rows into branch/host sections before
  the UI applies search.
- Current README and UX spec describe branch grouping as a first-class Dock
  behavior.
- This plan must not implement code yet.

## 1.3 Architectural principles (rules we will enforce)

- Projection before presentation: rows visible to the user come from one pure
  projection contract, then SwiftUI renders them.
- Derived projection, not cached UI state: Branch/Newest order must update from
  current snapshot rows and current UI options whenever either changes.
- UI state stays UI-local unless persistence is explicitly required.
- Local projection only: no relay, app-server, DTO, or server query changes.
- Counts and rows use the same filtering inputs.
- Controls use familiar SwiftUI primitives: text field/search container, menu
  or picker for sort mode, and checkbox/toggle for Idle.
- Verification proves behavior, not string absence or repo shape.

## 1.4 Known tradeoffs (explicit)

- Hiding idle by default changes the current All and Running visible rows, but
  that is the requested outcome.
- Keeping the sort choice UI-local is simpler and avoids adding preferences
  before there is a request for persistence.
- Newest mode can use a single section such as `Newest` to reuse the current
  `DockSectionViewModel` shape, but the UI should not present branch headers in
  that mode.
- Adding this before the glass port means the iOS 26 design plan should treat
  the new controls row as the surface to modernize later, not replace it with a
  competing search-only design.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

- Dock has a segmented filter picker, then a full-width custom `Search sessions`
  row.
- `DockView` applies search after selecting a tab from `DockSnapshot`.
- `SessionRowProjector` groups rows by branch, or host plus branch for multiple
  hosts.
- Sections and rows sort by status priority first, then newest activity, then
  title.
- `DockTabID.running` currently includes idle human rows as part of the active
  work bucket.

## 2.2 What's broken / missing (concrete)

- There is no UI control for choosing Branch grouping versus Newest ordering.
- The search row consumes the whole controls width, leaving no room for sort or
  idle visibility controls.
- Idle rows are visible by default even when the user wants active work first.
- Search, tab filtering, counts, idle visibility, and sort can drift if they
  stay split between `DockView`, `DockSnapshot`, and `SessionRowProjector`.
- The upcoming glass/design plan already intends to touch Dock search, so this
  behavior work needs to land first and become the new canonical surface.

## 2.3 Constraints implied by the problem

- The plan must preserve the current branch grouping behavior as an explicit
  sort mode while changing Branch-mode order to newest visible activity first.
- The Newest mode must be real, not branch sections reordered by recency.
- The Idle checkbox must affect all Dock filter tabs.
- The implementation should avoid adding new protocol parameters or relying on
  server behavior.
- Tests need to cover pure projection behavior so future visual work can safely
  restyle the controls.

# 3) Research Grounding (design + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 Design anchors and downstream docs

- Apple Human Interface Guidelines: Search fields and Searching - adopt the
  user-facing search purpose, placeholder clarity, and compact predictable
  control behavior. Reject adding a custom search subsystem; this Dock feature
  remains local filtering over already loaded rows.
- Apple Human Interface Guidelines: Menus, Pickers, and Toggles - adopt
  familiar native controls for compact option selection and boolean state.
  The sort control should be a menu-style picker or equivalent compact native
  control; Idle should be a toggle/checkbox semantic control, not a stateless
  button.
- Existing iOS 26 design modernization plan -
  `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md` - is a
  downstream doc that must be updated after this behavior lands, because its
  later glass pass should modernize the new Search/Sort/Idle row instead of
  reintroducing a search-only replacement.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors:
  - `CodexDock/Features/Dock/DockView.swift` - owns Dock screen state today:
    `selectedTab` and `searchText`, the segmented tab picker, the custom search
    row, empty-copy behavior, and row rendering.
  - `CodexDock/State/SessionRowProjector.swift` - owns row projection from
    `SessionSummary` into `DockRowViewModel`, branch/host section grouping,
    section sorting, row sorting, status mapping, relative time text, and rail
    defaults.
  - `CodexDock/State/DockStore.swift` - owns `DockTabID`, tab inclusion rules,
    tab counts, `DockSnapshot.sections(for:)`, host fan-out, scope
    deduplication, and snapshot assembly.
  - `CodexDockTests/DockStoreTests.swift` - pins branch grouping, section/row
    ordering by status priority plus newest activity, live rows before limited
    rows, empty tab labels, local metadata, archive behavior, and current tab
    inclusion semantics.
  - `CodexDockTests/DockStoreScopeTests.swift` - pins human/agent scope fan-out,
    no-leak tab behavior, deduplication, partial failure behavior, and current
    tab counts.
  - `README.md` - describes current Dock behavior as live loaded rows before
    stored history rows, then newest activity inside groups.
  - `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md` - documents that the Running
    tab is a human-work bucket and currently can include Idle rows.
  - `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` - documents host/branch
    grouping, search over sessions, app-local label, repo/cwd, branch, host,
    and thread id, and session status visibility.
- Canonical path / owner to reuse:
  - `CodexDock/State/SessionRowProjector.swift` owns base row construction,
    Branch-mode branch/host grouping, current base section/row construction,
    row status mapping, relative activity text, and row construction. Dock UI
    Branch ordering must be owned by `DockSessionProjection`, not by relying on
    the current status-priority base order.
  - `CodexDock/State/DockSessionProjection.swift` owns the Dock UI projection:
    search, sort mode, idle visibility, selected-tab filtering, projected tab
    labels, and hidden-idle empty-state metadata.
  - `DockSnapshot.project(options:)` is the UI-facing entrypoint that passes
    base sections and host display names into `DockSessionProjection`.
  - `CodexDock/Features/Dock/DockView.swift` should own UI-local control state:
    selected tab, search text, selected sort mode, and show-idle toggle. It
    should not own duplicate row-sorting rules.
- Adjacent surfaces tied to the same contract family:
  - `DockSnapshot.sections(for:)` and `DockStore.makeSnapshot` currently split
    tab filtering and tab counts from `SessionRowProjector`. The Dock UI must
    move to `DockSnapshot.project(options:)`; retained old snapshot helpers are
    raw compatibility surfaces only.
  - `DockTabID.includes(_:)` remains the source of tab membership by origin and
    status, but the idle visibility setting must layer on top consistently.
  - `ArchiveStore` uses `SessionRowProjector` for archived rows. It must keep
    branch grouping and current behavior unless the new projection API would
    otherwise force Archive to adopt Dock-specific sort/idle controls.
  - `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md` must remain
    true after this plan: later design work should modernize the new controls
    row instead of planning to replace it with search-only behavior.
  - `README.md`, `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md`, and
    `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` may need small live-doc
    updates after implementation if they still describe branch-only grouping or
    idle visibility as default.
- Compatibility posture (separate from `fallback_policy`):
  - Preserve wire/service contracts and store load behavior. This is a clean
    local projection cutover for the Dock UI only: no backend sort parameter,
    relay change, DTO change, or archive query change. Default visible Dock
    behavior intentionally changes in the requested ways: idle rows are hidden
    by default, and Branch mode remains grouped but becomes newest-first within
    the grouped model.
- Existing patterns to reuse:
  - Current local SwiftUI state in `DockView` for `selectedTab` and
    `searchText`; add sort and idle state beside it so SwiftUI body
    recomputation asks the projection for fresh visible rows whenever any input
    changes.
  - Current `DockTabViewModel.label` count-bearing segmented picker labels.
  - Current `DockSectionViewModel` shape can represent Branch sections and a
    single Newest section without adding a parallel row renderer.
  - Current tests use fake `SessionSummary` rows and deterministic dates; reuse
    that style for projection tests.
- Duplicate or drifting paths relevant to this change:
  - Current search filtering lives in `DockView.filteredSections(_:)`, while
    tab filtering/counts live in `DockSnapshot`/`DockStore`, and grouping/sort
    lives in `SessionRowProjector`. Adding sort/idle only in `DockView` would
    create a second projection path and likely count drift.
  - Current Running tab includes idle rows. The new unchecked Idle control must
    hide idle rows without rewriting `DockTabID.running` into a different
    membership concept; otherwise tab semantics and docs/tests drift.
- Behavior-preservation signals already available:
  - `rtk swift test --filter DockStoreTests` - protects Dock rows, grouping,
    ordering, archive, metadata, and tab inclusion behavior.
  - `rtk swift test --filter DockStoreScopeTests` - protects human/agent scope
    fan-out, tab counts, no-leak tab behavior, deduplication, and partial
    failure behavior.
  - Generated app Xcode build - protects SwiftUI control wiring and app target
    compile.

## 3.3 Decision gaps that must be resolved before implementation

- None. User intent settles the main UX decisions: search, sort, and Idle are
  one same-line control group at normal phone width; Idle is unchecked by
  default; idle rows are hidden unless checked; settings apply across all Dock
  tabs; this lands before glass modernization; and this run is planning-only.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `CodexDock/Features/Dock/DockView.swift`
  - `DockView` owns visible Dock controls, local UI state, row rendering,
    empty-state copy, context menus, and navigation into `SessionDetailView`.
  - Local state today is `selectedTab: DockTabID` and `searchText: String`.
  - `controls` is a vertical stack: segmented `Picker("Filter")`, then a
    full-width custom search row with `Image(systemName: "magnifyingglass")`
    and `TextField("Search sessions")`.
  - `filteredSections(_:)` applies only search after
    `snapshot.sections(for: selectedTab)` has already applied tab filtering.
- `CodexDock/State/SessionRowProjector.swift`
  - `SessionRowProjector.sections(from:)` converts summaries to rows, groups
    them by branch/host, sorts rows, sorts sections, maps statuses, computes
    relative activity text, and applies local row metadata.
  - One host groups by branch. Multiple hosts group by `hostID::branch` and
    display `Host Name / branch`.
  - Section sorting uses best status priority, newest row activity, then title.
  - Row sorting uses status priority, newest activity, then title.
- `CodexDock/State/DockStore.swift`
  - `DockTabID.includes(_:)` owns tab membership by origin and status.
  - `DockSnapshot.sections(for:)` filters projected sections by selected tab.
  - `DockStore.makeSnapshot` flattens projected rows and computes count-bearing
    `DockTabViewModel` labels using `DockTabID.includes(_:)`.
  - `AppServerDockClient.loadSessions` asks `thread/list` for
    `sortKey: .updatedAt` and `sortDirection: .desc`, but the local Dock
    projection reorders after mapping.
- `CodexDockTests/DockStoreTests.swift`
  - Pins branch grouping/order, live rows before limited rows, empty labels,
    local metadata, archive behavior, and current `DockTabID.includes(_:)`
    behavior.
- `CodexDockTests/DockStoreScopeTests.swift`
  - Pins human/agent load scopes, tab counts, no-leak tab behavior,
    deduplication, and partial failure behavior.
- Live docs:
  - `README.md` currently describes Dock ordering as live loaded rows before
    stored history rows, then newest activity/status/thread id.
  - `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md` says the Running tab can
    include Idle rows.
  - `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` says the feed should group
    by host and branch when data is available and supports search by title,
    label, repo/cwd, branch, host, and thread id.
  - `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md` currently
    plans to replace or modernize the Dock search row during the later visual
    pass.

## 4.2 Control paths (runtime)

Current loaded Dock path:

```text
DockView
  @State selectedTab
  @State searchText
  store.state == .loaded(snapshot)
    snapshot.sections(for: selectedTab)
      DockSnapshot filters rows by DockTabID.includes
    DockView.filteredSections
      filters rows by searchText only
    DockView renders every remaining section title and row
```

Current snapshot path:

```text
DockStore.reload
  loadAllHosts()
    load active human scope
    load active agents scope
  deduplicate host summaries
  SessionRowProjector.sections(from: summaries)
    make DockRowViewModel
    group by branch or host/branch
    sort sections by status priority, newest activity, title
    sort rows by status priority, newest activity, title
  allRows = sections.flatMap(\.rows)
  tabs = DockTabID.allCases.map { count allRows.filter(tab.includes) }
```

Current sort and idle behavior:

- Server fetch is newest-updated first, but local projection is not pure newest
  first.
- Branch grouping is always on.
- Idle rows are first-class row status `.idle`.
- Human idle rows appear in All and Running. Agent or unknown-origin idle rows
  appear in Agents.
- There is no sort mode, no idle visibility setting, and no canonical object
  that composes search, tab, sort, and idle visibility together.

## 4.3 Object model + key abstractions

- `DockRowStatusKind.idle` is the user-facing idle row state.
- `DockTabID` is a tab bucket enum, not a sort enum.
- `DockSectionViewModel` is the section container used by both Dock and
  Archive.
- `DockTabViewModel` is the count-bearing tab label.
- `SessionRowProjector` is package-internal and therefore a good home for pure
  projection rules with focused tests under `@testable import CodexDock`.

## 4.4 Current failure / empty behavior

- Empty copy distinguishes search-driven empty states from tab empty states.
- Host load failures, mapping failures, and scope conflicts render before rows
  and should not be affected by sort or idle visibility.
- Hidden rows are not deleted or archived; they are only absent from the visible
  Dock projection.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- Keep the behavior model in `CodexDock/State`.
- Add small projection types in a sibling file:
  `CodexDock/State/DockSessionProjection.swift`:
  - `DockSessionSortMode`
  - `DockSessionProjectionOptions`
  - `DockSessionProjection`
- Keep `SessionRowProjector` focused on converting loaded summaries into base
  row/section data.
- `DockSessionProjection` becomes the UI projection layer over those base
  rows/sections.
- Keep `DockView` as the UI owner for control state and rendering:
  - `@State selectedTab`
  - `@State searchText`
  - `@State sortMode = .branch`
  - `@State showsIdle = false`
- Keep `DockStore` as the owner of loading, host state, deduplication, archive,
  local metadata, and snapshot assembly.
- Do not change app-server DTOs, relay scripts, archive store behavior, or
  host settings.

## 5.2 Control paths (future)

Target loaded Dock path:

```text
DockView
  builds DockSessionProjectionOptions(
    selectedTab,
    searchText,
    sortMode,
    showsIdle
  )
  asks `DockSnapshot.project(options:)` for visible tab labels + visible sections
  renders:
    segmented Dock tabs
    same-line Search + Sort + Idle controls
    projected sections/rows
```

Target projection path:

```text
SessionRowProjector
  make rows from summaries
  make base branch sections using today's Branch grouping and row model

DockSnapshot.project(options)
  DockSessionProjection.project(baseSections, hostNameByID, options)
  apply showsIdle visibility
  apply search predicate
  derive tab labels from search + showsIdle + DockTabID membership
  apply selected tab membership
  apply sortMode:
    .branch -> host/branch grouping with newest-visible branch groups and rows
    .newest -> one flat newest-first row list with no branch grouping
  produce visible sections and tab labels from the same options
```

Chosen shape:

- `DockSnapshot.project(options:) -> DockSessionProjection` is the UI-facing
  projection method.
- `DockSessionProjection.project(baseSections:hostNameByID:options:)` owns the
  pure logic, including host-name search.
- `DockView` uses `projection.tabs` and `projection.sections` instead of using
  `snapshot.tabs` plus `snapshot.sections(for:)` directly.
- Existing stored `DockSnapshot.tabs` and `DockSnapshot.sections(for:)` remain
  raw, unprojected compatibility helpers for tests and non-UI callers that need
  base tab membership. They do not know about search, sort, or Idle visibility,
  and the Dock UI must stop using them.

## 5.3 Object model + abstractions (future)

`DockSessionSortMode`:

- `.branch`
  - User label: `Branch`
  - Preserves current branch/host section grouping.
  - Orders branch/host sections by each section's newest visible row activity
    descending.
  - Orders rows inside each branch/host section by newest activity descending.
  - Uses status priority, title, and stable ids only as deterministic
    tie-breakers after recency.
- `.newest`
  - User label: `Newest`
  - Produces one ungrouped visible session list ordered by
    `lastActivityDate` descending.
  - Ties use status priority and title for deterministic order.
  - Does not show branch section headers.

`DockSessionProjectionOptions`:

- `selectedTab: DockTabID`
- `searchText: String`
- `sortMode: DockSessionSortMode`
- `showsIdle: Bool`

`DockSessionProjection`:

- `tabs: [DockTabViewModel]`
- `sections: [DockSectionViewModel]`
- `hiddenIdleMatchCount: Int`, counting tab-eligible rows that match the search
  but are hidden only because `showsIdle == false`.

Search contract:

- The projection predicate searches title, repository or working-directory
  display text, branch, summary, status label, app-local label, host display
  name or id, and thread id.
- This folds the live UX spec's broader search requirement into the new
  canonical projection instead of preserving the current narrower UI-only
  predicate.

Branch ordering contract:

- Branch mode applies selected tab, search, and Idle visibility first, then
  removes empty sections.
- Branch mode preserves branch/host grouping, but it recomputes ordering from
  the remaining visible rows.
- Branch sections are ordered by the newest `lastActivityDate` among their
  visible rows, descending.
- Rows inside each Branch section are ordered by `lastActivityDate`
  descending.
- Status priority, title, and stable ids are tie-breakers only after recency.
- If search or Idle hides the newest row in a branch, that branch's position is
  recalculated from the newest remaining visible row. If a refreshed snapshot
  changes row activity dates, Branch mode automatically reorders on the next
  projection.

`showsIdle` contract:

- Default is `false`.
- When `false`, rows with `row.status == .idle` are hidden from every tab,
  including tabs whose membership would otherwise include idle rows.
- When `true`, idle rows are eligible for the tab where
  `DockTabID.includes(_:)` says they belong.
- Idle filtering is visibility filtering only; it does not change row status,
  source scope, archive behavior, metadata, or server load.

Controls row contract:

- Search, Sort, and Idle are one logical row under the segmented tab picker.
- On normal iPhone width, they should render on the same line:
  - a narrower search field
  - a compact sort control to the right
  - a checkbox/toggle labeled exactly `Idle`
- The Idle control should have accessibility text that makes the meaning clear,
  such as "Show idle threads", while the visible label remains `Idle`.
- At large Dynamic Type or too-small widths, the row may wrap or stack to avoid
  clipping. The fallback layout is responsive layout, not a separate feature
  mode.

## 5.4 Invariants and boundaries

- `DockTabID.includes(_:)` remains membership by bucket. Idle visibility is a
  separate projection option layered after membership.
- Sort mode is a local presentation choice. It does not change app-server
  `thread/list` params.
- Branch mode preserves branch/host grouping by default, but its visible order
  changes to newest-first inside that grouped model and idle rows are hidden by
  default.
- Projection is derived, not cached: changes to loaded snapshot rows, selected
  tab, search text, sort mode, or Idle visibility must produce a fresh order
  without a server reload or a manual refresh beyond the data update itself.
- Data-driven automatic updates ride on the existing refresh paths that publish
  new `DockSnapshot` values. Do not add a new event stream, relay protocol, or
  push subscription for this feature.
- Newest mode is not branch mode with reordered sections; it is a flat newest
  projection.
- Displayed tab counts should be derived from search text, idle visibility, and
  `DockTabID.includes(_:)` so a tab label does not advertise hidden rows as
  visible. Sort mode must not change counts.
- Archive may continue using branch grouping without adopting Dock UI options.
- Later glass/design work must modernize this new controls row instead of
  introducing a competing search/sort/idle surface.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Dock UI state | `CodexDock/Features/Dock/DockView.swift` | `@State selectedTab`, `searchText` | Tracks selected tab and search text only | Add `sortMode` defaulting to Branch and `showsIdle` defaulting to false | User needs sort choice and unchecked Idle toggle | `DockSessionProjectionOptions` inputs | Xcode build/manual |
| Dock controls | `CodexDock/Features/Dock/DockView.swift` | `controls`, `searchField` | Segmented picker plus full-width search row | Shrink search width and add same-line Sort control plus `Idle` checkbox/toggle | Requested UI surface | Search + sort + idle one logical row; responsive wrap only to prevent clipping | Xcode build/manual |
| Dock filtering | `CodexDock/Features/Dock/DockView.swift` | `filteredSections`, `matchesSearch` | UI applies search after tab filtering and searches only the current narrow row fields | Move search into canonical projection, expand it to title, repository/cwd display text, branch, summary, status label, app-local label, host display name/id, and thread id, then delete duplicate UI-only section filtering | Prevent count/sort/filter drift and align with the live UX search contract | Projection-owned search predicate | `DockStoreTests` and `DockStoreScopeTests` |
| Base row owner | `CodexDock/State/SessionRowProjector.swift` | `sections(from:)`, row helpers | Always branch/host groups; sorts by status priority, newest, title | Keep base row mapping and grouping here; preserve Archive/current raw behavior, but do not make Dock Branch mode depend on base status-priority order | Preserve current branch grouping path and archive reuse while allowing Dock-visible Branch order to change | Base branch sections | `DockStoreTests` |
| UI projection owner | `CodexDock/State/DockSessionProjection.swift` | new pure projection type | Does not exist | Add projection options and Branch/Newest/Idle/Search composition, including Branch newest-first group and row ordering | Canonical local visibility/order owner | `DockSessionSortMode`, `DockSessionProjectionOptions`, `DockSessionProjection` | `DockStoreTests`, `DockStoreScopeTests` |
| Tab membership | `CodexDock/State/DockStore.swift` | `DockTabID.includes(_:)` | Defines All, Needs me, Running, Limited, Agents membership; Running includes idle | Keep membership semantics; apply idle visibility separately | Avoid redefining tab buckets while hiding idle by default | Membership first, visibility second | `DockStoreTests`, `DockStoreScopeTests` |
| Snapshot visible sections | `CodexDock/State/DockStore.swift` | `DockSnapshot.sections(for:)` | Filters base sections by tab only | Add `DockSnapshot.project(options:)` and move Dock UI to it; keep `sections(for:)` only as a raw compatibility helper, not a Dock UI path | Same settings must apply across tabs | `DockSnapshot.project(options:)` | `DockStoreTests`, `DockStoreScopeTests` |
| Tab counts | `CodexDock/State/DockStore.swift` / `DockSessionProjection` | `DockStore.makeSnapshot` tab labels | Counts all base rows per tab, independent of UI-local search/idle | Derive displayed tab labels from projection rules using search + idle + tab membership | Avoid labels counting hidden rows | Projection-derived `DockTabViewModel` labels; sort-independent counts | `DockStoreScopeTests` |
| Newest display | `CodexDock/State/SessionRowProjector.swift` and `DockView` row rendering | UI always renders every section header | Newest mode should render a flat newest-first list without branch headers | User asked to sort without the branch thing | Single Newest section or section-header suppression for newest mode | `DockStoreTests`, manual |
| Automatic reordering | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/State/DockSnapshot`, `DockSessionProjection` | Current visible order is rebuilt as SwiftUI renders from `store.state`, `selectedTab`, and `searchText`, but there is no sort/idle projection owner | Keep projected sections as derived output from current snapshot plus `DockSessionProjectionOptions`; do not cache visible rows or order in `@State` | Rows and groups must automatically update when data or controls change | Projection call from render path, no stale cached order | Projection tests plus manual |
| Existing refresh boundary | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/State/DockStore.swift` | Dock refreshes through existing load, auto-refresh, foreground, pull-to-refresh, and metadata-save paths that publish new snapshots | Use newly published snapshots as projection input; do not add new realtime/push infrastructure | Keeps "automatic update" scoped to current app architecture | Current `@Published state` plus render-time projection | Xcode build/manual |
| Empty copy | `CodexDock/Features/Dock/DockView.swift` | `emptyStateTitle`, `emptyStateMessage` | Distinguishes search empty from tab empty | Use projection metadata when rows are hidden only because Idle is off and guide the user to enable `Idle` | Avoid confusing no-session copy | `hiddenIdleMatchCount` from `DockSessionProjection` | Projection tests plus manual/build |
| Archive projection | `CodexDock/State/ArchiveStore.swift` | `SessionRowProjector.sections(from:)` | Uses branch grouping for archive rows | Preserve current archive behavior; pass default Branch/show-idle behavior only if API signature changes | Avoid leaking Dock controls into Archive | Backward-compatible projection entrypoint | `DockStoreTests` archive tests if touched |
| README | `README.md` | Dock ordering paragraph | Describes current live/history/newest/status ordering | Update after implementation if branch/newest user sort changes live behavior | Avoid live-doc drift | Mention local sort control and Idle visibility | Docs readback |
| Thread states doc | `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md` | Dock tab section | Says Running can include Idle rows | Update after implementation to explain Idle toggle visibility | Avoid state-doc drift | Tab membership versus visibility distinction | Docs readback |
| UX spec | `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` | FR-LIST branch/search requirements | Branch grouping is expected when branch data exists; search includes label, repo/cwd, branch, host, and thread id | Update after implementation if Newest mode changes default visible grouping, if Branch mode's newest-first grouped order conflicts with existing wording, or if the final search field list differs | Avoid old branch-only, status-first Branch, or stale-search assumptions | Branch remains a sort mode; projection search is canonical | Docs readback |
| iOS 26 design plan | `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md` | Phase 1 Dock search/control work | Plans to replace/modernize Dock search row | Update after this behavior lands so glass pass modernizes the new controls row | Preserve sequencing before glass port | New controls row is canonical | Docs readback |

## 6.2 Migration notes

* Canonical owner path / shared code path:
  * `SessionRowProjector` owns base row/branch projection.
  * `SessionRowProjector` does not own final Dock-visible Branch ordering;
    `DockSessionProjection` re-sorts visible Branch sections and rows after
    applying selected tab, search, sort mode, and Idle visibility.
  * `DockSessionProjection` in `CodexDock/State` owns UI projection from base
    sections plus `DockSessionProjectionOptions`.
  * `DockView` owns state and rendering only.
* Deprecated APIs (if any):
  * Stop using `DockView.filteredSections(_:)` once search moves into the
    projection contract.
  * Stop direct Dock UI use of `DockSnapshot.sections(for:)`; use
    `DockSnapshot.project(options:)`.
  * Keep `DockSnapshot.tabs` and `DockSnapshot.sections(for:)` as raw
    compatibility helpers only. They are not routed through default projection
    because they lack search, sort, and `showsIdle` inputs.
* Delete list:
  * Delete duplicate UI-only sorting/filtering helpers once the projection path
    owns them.
  * Do not keep a second Newest sorting helper in `DockView`.
* Adjacent surfaces tied to the same contract family:
  * Dock UI, Dock snapshot counts, tab membership, row projection, Dock tests,
    scope tests, README, thread-states doc, UX spec, and the iOS 26 design plan.
* Compatibility posture / cutover plan:
  * Preserve service and load contracts. Clean local UI projection cutover.
    Existing default visual behavior changes only where the user requested it:
    Idle is hidden by default, and Branch remains grouped while becoming
    newest-first inside that grouped model.
* Capability-replacing harnesses to delete or justify:
  * None. This is local deterministic UI/model behavior.
* Live docs/comments/instructions to update or delete:
  * Update live docs after implementation if they teach branch-only default
    grouping or idle visibility as always-on.
* Behavior-preservation signals for refactors:
  * `rtk swift test --filter DockStoreTests`
  * `rtk swift test --filter DockStoreScopeTests`

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Dock projection | `DockSessionProjection` | One `DockSessionProjectionOptions` input path | Prevents search/sort/idle/count drift | include |
| Tab membership | `DockTabID.includes(_:)` | Membership first, visibility second | Keeps Running bucket semantics distinct from hidden idle rows | include |
| Branch sorting | Projection helper | Preserve branch/host grouping but sort visible groups and rows by recency | Prevents Branch mode from staying status-priority-first after the new requirement | include |
| Newest sorting | Projection helper | Sort all visible rows by recency, then status/title ties | Prevents branch grouping from leaking into Newest mode | include |
| Controls row | `DockView.controls` | One compact row with Search, Sort, Idle | Establishes behavior surface before glass styling | include |
| Archive | `ArchiveStore` / `SessionRowProjector` | Preserve current Branch-style archive grouping | Avoids product creep into Archive | exclude from user-facing sort controls; include only compatibility adaptation if API changes |
| Server query | `AppServerDockClient.loadSessions` | Keep `updatedAt desc` load query | Local projection can sort visible rows without protocol drift | exclude |
| Visual glass | iOS 26 design plan | Modernize this new row later | Keeps behavior plan ahead of visual plan | defer to design plan |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. No fallbacks/runtime shims - the system must work correctly or fail loudly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates.

## Phase 1 - Canonical Dock projection contract

* Goal:
  Establish and test the single source of truth for Dock-visible rows, tab
  labels, Branch/Newest sort modes, automatic reordering, search, and idle
  visibility before touching SwiftUI layout.
* Work:
  Add `DockSessionProjection` under `CodexDock/State`, keep
  `SessionRowProjector` as the base row/branch section owner, and add
  `DockSnapshot.project(options:)` as the UI-facing projection method.
* Checklist (must all be done):
  - Add `DockSessionSortMode` with exactly the user-facing modes `Branch` and
    `Newest`.
  - Add `DockSessionProjectionOptions` with `selectedTab`, `searchText`,
    `sortMode`, and `showsIdle`.
  - Add `DockSessionProjection` with projected `tabs` and `sections`.
  - Add `hiddenIdleMatchCount` or an equivalent projection-owned field that
    reports tab-eligible search matches hidden only by `showsIdle == false`.
  - Add `DockSnapshot.project(options:)` and make it delegate to the pure
    projection helper with host display names available for search.
  - Keep `DockSnapshot.tabs` and `DockSnapshot.sections(for:)` as raw
    compatibility helpers only; do not route Dock UI through them.
  - Keep `SessionRowProjector.sections(from:)` preserving base branch/host
    grouping and current raw/archive behavior, but do not use its
    status-priority order as Dock Branch mode's final visible order.
  - Implement `showsIdle == false` so `.idle` rows are excluded from every
    projected tab and visible section.
  - Implement `showsIdle == true` so idle rows reappear only in tabs where
    `DockTabID.includes(_:)` accepts them.
  - Implement `Branch` mode by applying selected tab, search, and idle
    visibility first, then preserving branch/host grouping while recomputing
    section order from the newest remaining visible row in each section.
  - Implement `Branch` row order inside each visible branch/host section as
    `lastActivityDate` descending, with status priority, title, and stable ids
    only as tie-breakers.
  - Ensure Branch order is recalculated when search or Idle hides the newest
    row in a branch, and when a refreshed snapshot changes row activity dates.
  - Implement `Newest` mode as one flat newest-first section without branch
    grouping; ties use status priority and title for deterministic order.
  - Implement search in the projection path across title, repository or working
    directory display text, branch, summary, status label, app-local label, host
    display name or id, and thread id.
  - Derive projected tab labels from search text, idle visibility, and
    `DockTabID.includes(_:)`; sort mode must not change tab counts.
  - Keep service query, source scope, host fan-out, deduplication, archive, and
    metadata behavior unchanged.
  - Add or update focused `DockStoreTests` / `DockStoreScopeTests` cases for:
    default idle hidden, idle enabled, Branch mode preserving current grouping
    while ordering branch groups and rows by newest visible activity, Branch
    order recalculating after search/Idle filtering changes visible rows,
    Branch order recalculating after snapshot activity dates change, Newest
    mode flattening and sorting by `lastActivityDate`, projected tab counts,
    broader search composition, hidden-idle empty metadata, raw snapshot helper
    compatibility, and Branch newest-first order after filtering.
* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests`.
  - Run `rtk swift test --filter DockStoreScopeTests`.
  - Run `rtk xcodegen generate --spec project.yml` after adding
    `CodexDock/State/DockSessionProjection.swift` so the generated Xcode
    project includes the new Swift source.
* Docs/comments (propagation; only if needed):
  - Add one short code comment only if needed to explain membership versus
    visibility, especially why `DockTabID.includes(_:)` still allows idle while
    projection can hide it.
* Exit criteria (all required):
  - One pure projection path owns search, sort, idle visibility, selected-tab
    membership, and projected tab labels.
  - `DockView` has not gained duplicate sorting/filtering rules.
  - Branch mode output matches today's grouped branch behavior except for
    user-controlled idle visibility/search and the requested newest-first group
    and row ordering.
  - Branch mode orders visible branch/host sections by newest visible row
    activity descending and orders rows inside each section by newest activity
    descending.
  - Branch mode recomputes ordering from the current visible rows when search,
    Idle visibility, selected tab, or loaded snapshot activity dates change.
  - Newest mode output is not grouped by branch and orders visible rows newest
    first.
  - With default options, `.idle` rows are hidden from All, Running, Limited,
    Needs me, and Agents; tabs that cannot contain idle by membership remain
    empty of idle rows for that membership reason.
  - With `showsIdle == true`, `.idle` rows reappear in the tabs where
    `DockTabID.includes(_:)` places them.
  - Projected tab counts do not count rows hidden by search or idle visibility.
  - `hiddenIdleMatchCount` or equivalent metadata is correct when idle rows are
    the only tab-eligible search matches hidden by the default.
  - `DockSnapshot.tabs` and `DockSnapshot.sections(for:)` are no longer Dock UI
    sources and are documented/tested as raw compatibility helpers if retained.
  - Store load, host status, scope conflict, mapping failure, archive, and
    metadata behavior are unchanged.
* Rollback:
  Remove the new projection types and tests, and return `DockSnapshot` /
  `SessionRowProjector` to their current Branch-only projection path.

## Phase 2 - Dock controls row integration

* Goal:
  Connect the proven projection contract to the real Dock UI with one compact
  same-line controls row: narrower Search, Sort to its right, and an unchecked
  `Idle` checkbox/toggle.
* Work:
  Add sort and idle UI state to `DockView`, replace local `filteredSections`
  use with `snapshot.project(options:)`, and reshape `controls` so the
  segmented filter remains above a single logical row containing Search, Sort,
  and Idle. Keep projected sections as render-time derived output, not separate
  `@State`, so control changes and store snapshot changes automatically
  re-order the visible list.
* Checklist (must all be done):
  - Add local UI state in `DockView`: `sortMode = .branch` and
    `showsIdle = false`.
  - Build projection options from `selectedTab`, `searchText`, `sortMode`, and
    `showsIdle`.
  - Build the projection from the current loaded `snapshot` and current options
    during rendering; do not store projected rows, projected sections, or sort
    order in independent `@State`.
  - Treat newly published loaded snapshots from existing refresh paths as the
    data-change trigger for automatic reordering; do not add a new push stream,
    relay method, or backend subscription.
  - Replace direct `snapshot.tabs` usage with `projection.tabs`.
  - Replace direct `snapshot.sections(for:)` plus `filteredSections(_:)` usage
    with `projection.sections`.
  - Remove `DockView.filteredSections(_:)` when it is no longer the canonical
    path.
  - Keep `matchesSearch` only if it is moved into or delegated by the
    projection helper; do not leave a second UI-only predicate.
  - Shrink the visible search field so Sort and Idle fit to its right at normal
    iPhone width.
  - Add a compact native sort control with visible choices `Branch` and
    `Newest`.
  - Add a checkbox/toggle whose visible label is exactly `Idle`, unchecked by
    default, and whose accessibility label/value explains that it shows idle
    threads when enabled.
  - Keep Search, Sort, and Idle in one same-line logical row at normal phone
    width.
  - Allow responsive wrapping/stacking only for small widths, very large
    Dynamic Type, or accessibility sizes where a single row would clip.
  - Mark decorative search icon imagery accessibility-hidden if the row is
    touched.
  - Preserve empty/error/offline/mapping-failure/scope-failure banners and row
    navigation/context menus.
  - Use projection-owned hidden-idle metadata so an empty result caused only by
    unchecked `Idle` guides the user to enable `Idle` rather than implying
    sessions are gone.
* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests`.
  - Run `rtk swift test --filter DockStoreScopeTests`.
  - Run `rtk xcodegen generate --spec project.yml` before the generated-project
    build, even if it already ran in Phase 1, so `CodexDock.xcodeproj` is
    current after the final source edits.
  - Run `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`, or report the exact destination blocker and run the closest available iOS 26 simulator build.
  - Run a focused simulator manual or Mobile MCP pass covering Branch, Newest,
    Idle unchecked, Idle checked, search, at least one non-All Dock tab, normal
    iPhone-width same-line layout, large Dynamic Type/no-clipping behavior, and
    immediate visual reordering when Sort, Search, tab, or Idle changes.
    If physical Mobile MCP reports `WebDriverAgent is not running on device`,
    stop physical retries per `AGENTS.md` and use simulator/local UI proof.
* Docs/comments (propagation; only if needed):
  - Update a short code comment only if the final control layout has a
    non-obvious accessibility or responsive-layout rule.
* Exit criteria (all required):
  - The Dock screen shows the segmented Dock tabs, then one logical row with
    Search, Sort, and `Idle`.
  - Search is visibly narrower than the old full-width row at normal iPhone
    width.
  - Sort changes between Branch and Newest without reloading from the server.
  - Branch mode shows branch groups and rows newest-first, and reorders
    immediately when Search, tab, Sort, or Idle changes the visible row set.
  - When `store.state` receives a refreshed loaded snapshot with newer
    `lastActivityDate` values, the visible Branch/Newest order reflects the
    new dates without keeping stale UI order.
  - `Idle` is unchecked by default and hides idle rows across All, Running,
    Limited, Needs me, and Agents according to membership.
  - Checking `Idle` shows idle rows across those same tabs where membership
    allows them.
  - Switching tabs preserves the same sort and Idle settings.
  - Search still applies with the selected sort and Idle settings.
  - An empty result caused only by unchecked `Idle` tells the user that enabling
    `Idle` will reveal hidden idle rows.
  - Focused simulator manual or Mobile MCP evidence proves the control row fits
    at normal iPhone width and degrades without clipping at large Dynamic Type.
  - No relay, app-server, archive, host settings, thread detail, voice, or
    request-card behavior changes.
* Rollback:
  Revert `DockView` control integration while leaving Phase 1 projection code
  only if tests still pass and no UI path uses it; otherwise revert Phase 1 and
  Phase 2 together.

## Phase 3 - Live docs and pre-glass handoff

* Goal:
  Keep live docs and the later iOS 26 glass/design plan aligned with the new
  Dock behavior before any visual-modernization implementation begins.
* Work:
  Update only live documentation that would otherwise teach old Dock behavior:
  current README ordering, thread-state tab/idle semantics, the UX spec's
  branch-grouping requirement, and the iOS 26 design plan's Dock search/control
  phase.
* Checklist (must all be done):
  - Update `README.md` if its Dock ordering paragraph is stale after Branch /
    Newest and Idle controls land.
  - Update `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md` if it still says Idle
    is simply visible in Running without mentioning the Idle visibility toggle.
  - Update `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` if branch grouping is
    still described as the only Dock feed shape rather than the Branch sort
    mode, or if it implies Branch mode is status-priority-first instead of
    newest-first within each grouped branch view.
  - Update `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` if its Dock search
    contract no longer matches the implemented canonical projection fields.
  - Update `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md` so the
    future glass port modernizes the new Search/Sort/Idle controls row instead
    of planning a search-only replacement.
  - Do not rewrite passive history, worklogs, or completed audit docs.
* Verification (required proof):
  - Read back the touched doc snippets.
  - Run `rtk git status --short` and confirm only intended plan/code/doc files
    are part of this work, ignoring unrelated dirty files already present.
  - If docs-only edits happen after Phase 2 verification, no extra app tests are
    required unless code changes again.
* Docs/comments (propagation; only if needed):
  - This phase is the docs propagation phase.
* Exit criteria (all required):
  - Live docs no longer imply branch grouping is the only Dock display mode.
  - Live docs no longer imply Branch mode uses status priority before recency;
    they describe Branch as grouped and newest-first within the visible grouped
    rows.
  - Live docs no longer imply idle rows are always visible by default.
  - Live docs describe Dock search fields consistently with the projection
    implementation.
  - The iOS 26 design plan clearly treats this Search/Sort/Idle row as the
    behavior surface to restyle during the glass port.
  - No passive history docs are churned.
* Rollback:
  Revert the doc updates if the implementation is rolled back before shipping.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (required proof where triggered)

Checks named in Section 7 are required phase proof. If a required command or
device path cannot run because of Xcode, simulator, physical-device signing,
Mobile MCP, services, or env state, report the exact skipped command and exact
blocker before using the closest valid proof.

## 8.1 Unit tests (contracts)

- Use `rtk swift test --filter DockStoreTests` for projection, Branch
  newest-visible group/row ordering, Newest flat ordering, automatic recompute
  from changed options or snapshot data, counts, and idle visibility behavior.
- Use `rtk swift test --filter DockStoreScopeTests` for projected tab counts,
  no-leak tab behavior, and human/agent membership preservation.

## 8.2 Integration tests (flows)

- Use the generated app Xcode build after SwiftUI changes:
  `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- If this machine lacks an exact `iPhone 17` simulator, use the closest
  available iOS 26 simulator and report the destination mismatch exactly.

## 8.3 E2E / device tests (realistic)

- A focused manual or Mobile MCP check is required for Dock controls after
  implementation: Branch mode, Newest mode, Idle unchecked, Idle checked,
  search query, at least one non-All Dock filter tab, normal iPhone-width
  same-line layout, large Dynamic Type/no-clipping behavior, and immediate
  reordering when Search, Sort, tab, or Idle changes.
- No full visual-golden suite is required.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Ship as a normal local app UI update before the iOS 26 glass/design
modernization. No service rollout is required.

## 9.2 Telemetry changes

No telemetry changes are required. Sort mode and idle visibility are local UI
state.

## 9.3 Operational runbook

If rows disappear or order looks stale after implementation, debug projection
inputs in this order: selected tab, `showsIdle`, search text, sort mode, then
loaded snapshot rows and `lastActivityDate` values. Do not debug this by
changing relay endpoints or app-server query parameters.

If visible ordering is stale, first verify `DockView` is calling
`snapshot.project(options:)` from the current loaded render path and is not
storing `projection.sections` separately from `selectedTab`, `searchText`,
`sortMode`, `showsIdle`, or `snapshot` changes.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, helper blocks, and the current
    `auto_plan_receipts` stage state.
  - Sections 3-7 against current `DockView`, `DockStore`,
    `SessionRowProjector`, `ArchiveStore`, Dock tests, scope tests, README,
    thread-states doc, UX spec, and iOS 26 design plan.
- Findings summary:
  - Verification wording made required checks look optional.
  - Manual/Mobile MCP UI proof was stranded outside authoritative Phase 2.
  - Idle wording mixed "every tab" with membership-gated tab placement.
  - Section 3 contradicted Sections 5-7 on the canonical owner split.
  - Old `DockSnapshot.tabs` / `sections(for:)` API fate was branchy.
  - Search scope conflicted with the live UX spec.
  - Hidden-idle empty-state handling was optional even though default-hidden
    idle can create an otherwise confusing empty screen.
  - Branch-mode ordering after filtering was underspecified.
  - Helper planning metadata and rollout naming drifted.
- Integrated repairs:
  - Made verification required where named, and moved the focused
    simulator/manual/Mobile MCP pass into Phase 2 proof.
  - Normalized Idle semantics: the toggle applies in every tab; off hides all
    `.idle` rows; on makes idle rows eligible only where `DockTabID.includes`
    places them.
  - Clarified the owner split: `SessionRowProjector` owns base rows and Branch
    grouping, `DockSessionProjection` owns Dock UI projection, and
    `DockSnapshot.project(options:)` is the UI entrypoint.
  - Chose the old snapshot API posture: keep `tabs` and `sections(for:)` only
    as raw compatibility helpers, not Dock UI paths.
  - Expanded the projection search contract to include label, host display
    name/id, and thread id so the live UX search contract is carried forward.
  - Made hidden-idle metadata and empty-state copy explicit phase obligations.
  - Earlier consistency repair specified that Branch mode preserved base section
    order after filtering; the later user requirement below supersedes that
    with newest-visible Branch ordering.
  - Updated helper flow, mandatory `DockStoreScopeTests`, and `showsIdle`
    naming.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
- Execution authorization:
  - no; this is ArcStep consistency readiness only. The plan still stops after
    plan-audit until the user explicitly requests implementation.
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Treat user objective as North Star confirmation for auto-plan

Context

The user requested ArcStep `new` plus auto-plan and explicitly said not to
implement yet. The objective names the desired Dock behavior, states that it
should happen before the glass port, and asks for plan audit before stopping.

Options

- Stop after a draft `new` document for separate confirmation.
- Treat the explicit current objective as confirmation and continue the
  requested planning-only auto-plan sequence.

Decision

Proceed with `status: active` and run the ArcStep auto-plan receipts against
this document. Do not implement code in this planning run.

Consequences

The plan can advance through research, deep-dive, phase-plan, consistency-pass,
and plan-audit in one run while preserving the user's "do not implement yet"
boundary.

## 2026-05-28 - Consistency-pass decisions

Context

Two cold-read consistency passes found real ambiguity in owner split, old
snapshot API posture, search scope, hidden-idle empty copy, UI proof, and Branch
ordering after filtering.

Options

- Keep the earlier broad language and leave implementers to choose details.
- Make the plan's implementation posture explicit before audit.

Decision

Use `SessionRowProjector` for base row construction and Branch grouping, use
`DockSessionProjection` for Dock UI projection, keep old snapshot helpers as
raw compatibility surfaces only, expand search to the live UX spec fields,
require hidden-idle empty-state metadata, and require simulator/manual or
Mobile MCP UI proof in Phase 2. The later 2026-05-28 Branch recency decision
supersedes this pass's earlier base-order posture.

Consequences

Implementation has one unambiguous owner path and proof bar. The plan still
does not authorize implementation before the requested plan audit is complete
and the user asks to implement.

The consistency-pass `Decision: proceed to implement? yes` field is a readiness
gate for ArcStep only, not execution authorization.

## 2026-05-28 - Branch mode recency and automatic projection updates

Context

The user clarified that Branch sort should still show the most recently changed
work first, and that ordering should update automatically as sessions and
controls change.

Options

- Keep the prior plan's Branch behavior: preserve base section order after
  filtering, with Newest as the only recency-first scan mode.
- Preserve Branch grouping but make recency the primary order inside the
  grouped model, and require projection output to be derived from current
  snapshot rows plus current UI options.

Decision

Preserve branch/host grouping in Branch mode, but order branch groups by their
newest visible row and order rows inside each branch by newest activity first.
Use status priority, title, and stable ids only as tie-breakers after recency.
Recompute projection output from the current snapshot and current
`DockSessionProjectionOptions`; do not cache visible rows, projected sections,
or order in separate UI state.

Consequences

Phase 1 now owns Branch newest-visible ordering and tests for order changes
after search, Idle, selected-tab, and snapshot activity-date changes. Phase 2
must wire `DockView` so SwiftUI re-renders through `snapshot.project(options:)`
instead of holding stale projected rows. The plan remains planning-only until
the user explicitly requests implementation.
