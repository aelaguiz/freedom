---
title: "Codex Dock - Activity-First Implementation - Architecture Plan"
date: 2026-05-29
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: phased_refactor
related:
  - docs/mockups/codex-dock-activity-first-2026-05-29/README.md
  - docs/mockups/codex-dock-activity-first-2026-05-29/requirements/GLOBAL_REQUIREMENTS.md
  - docs/mockups/codex-dock-activity-first-2026-05-29/requirements/TRACEABILITY_MATRIX.md
  - docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md
  - docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md
  - README.md
  - Makefile
  - project.yml
  - Package.swift
---

# TL;DR

- Outcome: Replace the current Dock first screen with an activity-first session index: `Newest` opens by default, `Host` and `Branch` are explicit Dock lenses, `Filters` is one shared filter surface, rows carry their own host/branch/repo identity, and loading/failure states tell the truth without `Limited`, `Needs me`, or final-looking zero-count tabs.
- Problem: The current iPhone Dock uses primary `All`/`Needs me`/`Running`/`Agents` tabs, starts in branch grouping, pins host summary blocks above the list, squeezes search into a narrow row, shows endpoint-heavy host text, and still lets unreliable workflow/status signals shape the scan path.
- Approach: Move list interpretation into one projection model, make `DockView` a thin renderer of that projection, derive short host display names once, retire the legacy tab/sort vocabulary from primary Dock UX, and keep relay/app-server contracts unchanged.
- Plan: Ship this as a depth-first refactor across projection, row models, Dock header/list UI, filters, multi-host loading/failure, docs, supporting tests, and simulator-first proof.
- Non-negotiables: No `Limited`, no primary `Needs me`, no hidden filter state, no raw endpoint strings in the main scan path, no branch-grouped default, no pinned host cards above the default list, no app-level tab proliferation, no new relay protocol, no fallback/shim UI paths, and no unit-test-only completion claim for user-visible Dock work.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-29
external_research_grounding: done 2026-05-29
deep_dive_pass_2: done 2026-05-29
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:c29897c4b75380d91900cc45d4d06b5c14af9d50420414149550dcea33ca7b2f",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-29T16:53:39Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:1095c3a50fbb8db946d64593c01a2ba1c7ae4fadb4a132e2ea58a27490b0e2bd",
      "completed_at": "2026-05-29T16:55:00Z",
      "doc_hash_after": "sha256:e6d0e382c701b756af1991e926fe9ebec6036c5ca275208cd1370080848e7f03"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T16:55:02Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e6d0e382c701b756af1991e926fe9ebec6036c5ca275208cd1370080848e7f03",
      "completed_at": "2026-05-29T17:00:46Z",
      "doc_hash_after": "sha256:010cc28dab4ac46520773dd6700245d0f0c964175ff2061733a9a2b00d19518b"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T17:00:53Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:010cc28dab4ac46520773dd6700245d0f0c964175ff2061733a9a2b00d19518b",
      "completed_at": "2026-05-29T17:01:37Z",
      "doc_hash_after": "sha256:db78677db0ce198f6a122b78d3d7f7f564e8ca6e3856873028bb0bf98c32a97e"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-29T17:01:44Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:db78677db0ce198f6a122b78d3d7f7f564e8ca6e3856873028bb0bf98c32a97e",
      "completed_at": "2026-05-29T17:03:44Z",
      "doc_hash_after": "sha256:a832ff4de9325e255a3d39f1210b03bc7313f50fdc0f638724d24f2e8b92eda1"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-29T17:03:54Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:a832ff4de9325e255a3d39f1210b03bc7313f50fdc0f638724d24f2e8b92eda1",
      "completed_at": "2026-05-29T17:11:14Z",
      "doc_hash_after": "sha256:0c3231bc57c00ea85547dc107c66fd00976272ac733db25fd5544e7c91f2ede9"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, a user opening Codex Dock on an iPhone 17 with two configured relays can immediately scan the newest real sessions across both hosts, then intentionally narrow by host, branch, status, repo, source, idle visibility, and text search without the UI guessing their workflow or hiding why rows disappeared.

## 0.2 In scope

- The Dock first screen in `CodexDock/Features/Dock/DockView.swift`.
- Shared Dock row, host, banner, filter, loading, and empty-state views in `CodexDock/Features/Dock/DockSharedViews.swift` and new sibling files if splitting keeps the view readable.
- The Dock projection model in `CodexDock/State/DockSessionProjection.swift`, including lenses, explicit filters, search composition, result counts, grouping, and deterministic ordering.
- The Dock view model surface in `CodexDock/State/DockStore.swift`, including visible status vocabulary, host display names, loading state shape, and snapshot metadata needed by the new projection.
- Row creation in `CodexDock/State/SessionRowProjector.swift`, including short host names, approved status labels, row searchable fields, and no default `Needs me` priority.
- Connectivity display copy in `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` and `CodexDock/State/AppConnectivityStore.swift` only as needed to show compact truth like `Online 2/2`, `Checking 2 hosts`, or `Online 1/2`.
- Root-level navigation coordination in `CodexDock/Features/Dock/DockView.swift` only as needed to let Dock host-failure UI open the existing `Relay` tab.
- Accessibility identifiers in `CodexDock/Automation/AutomationID.swift` for new lenses, filter controls, active-filter summary, host groups, branch groups, loading rows, retry actions, Relay settings actions, and empty-state clear actions.
- Supporting unit tests under `CodexDockTests/**` that own Dock projection, Dock store state, row projection, host display names, accessibility IDs, and killed terms. These tests are required support checks, not the primary proof that the Dock works in real UI.
- App README updates where it describes old Dock controls.
- Simulator verification commands owned by `Makefile`, with `rtk make app-test SIM='iPhone 17'` as the required primary UI proof when the code is implemented.
- Testability hooks required for simulator proof: if the simulator cannot assert a required visible/accessibility behavior because the app lacks accessibility IDs, state values, UI-test entry points, or log/accessibility exposure, implementation must add those hooks and rerun simulator proof. Missing hooks are implementation work, not a reason to downgrade to unit tests.

## 0.3 Out of scope

- No relay protocol change in `scripts/dock-relay*.mjs`.
- No Codex app-server JSON-RPC DTO change unless a compiler/test failure proves an existing field is insufficient. The known list date for this plan is `SessionSummary.lastActivity`; the current mapper prefers server `updatedAt` and falls back to `createdAt`.
- No OpenAI API key, bearer-token, `.env`, Bonjour TXT, relay-auth, or transcription behavior changes.
- No direct iPhone connection to the raw authenticated `:4500` app-server.
- No new top-level app tabs beyond existing `Dock`, `Archive`, and `Relay`.
- No attempt to make `Needs me` reliable. The primary Dock UX removes it instead of improving that signal.
- No rate-limit detection or rate-limit UI. `Not loaded` is about unknown thread detail, not API limits.
- No automatic "active host", "important branch", "current project", or "thread needs the user" prediction.
- No archive-list merge into Dock V1. The `Archive` tab remains the canonical archived-session surface unless a later product decision explicitly asks Dock and Archive to share one result set.
- No persistence of custom display names or pinned hosts in V1. Host display names are deterministic derived labels from configured endpoints; Relay settings still show endpoint strings.
- No raw `xcodebuild`, `simctl install`, `devicectl install`, or manual platform install commands as normal verification.

## 0.4 Definition of done (acceptance evidence)

- First app open shows `Dock`, compact connectivity, full-width search, `Newest` selected, `Host`, `Branch`, and one `Filters` entry point. It does not show primary `All`, `Needs me`, `Running`, or `Agents` tabs.
- Default loaded state is a flat newest-first list across hosts. Rows show title, short host display name when more than one host exists, repo or working directory, branch, status, last activity, and latest summary when available.
- `Host` lens shows compact expandable host groups with short host names, status/count/latest metadata, local failure state, and nested rows ordered newest-first.
- `Branch` lens shows compact expandable branch groups with branch name, count, latest activity, host availability, and rows that still show host.
- `Filters` opens one shared Dock filter surface, composes with the selected lens and search, shows visible active-filter summary/counts, and can clear/reset explicit filters.
- Search remains global by default, composes with filters, updates the visible result count, and matches title, repo/working directory, branch, host display name, latest summary, status, local label, and thread id fragment.
- Loading state names every configured host, uses short host display names, avoids final-looking zero counts, keeps the header/search/lens controls stable, and can show loaded hosts while others are still checking.
- One offline host does not clear or block rows from online hosts. Failure UI attaches to the failed host, offers Retry, and offers a path to Relay settings.
- Visible Dock output and accessibility output do not contain `Limited`.
- Primary Dock output and filter surface do not contain `Needs me`.
- `Not loaded` appears only as neutral row/status/filter/explanatory copy for unknown thread detail.
- Supporting Swift tests pass for the model/store/config/connectivity/automation surfaces they touch, but unit tests alone never prove this plan complete.
- `rtk swift test --filter AppServerClientTests` is run only if DTO/client behavior changes.
- `rtk make app-test SIM='iPhone 17'` passes and proves the installed simulator UI behavior. The proof must inspect simulator UI/accessibility/log state, not only compile or launch.
- If simulator proof cannot assert a required behavior because a hook is missing, the implementation adds the hook and reruns `rtk make app-test SIM='iPhone 17'`.
- If the simulator itself is unavailable because of Xcode, simulator runtime, signing, or service infrastructure, the phase is blocked, not complete. Record the exact command and exact blocker; `rtk make app SIM='iPhone 17'` may be run as a diagnostic launch check but is not completion proof.

## 0.5 Key invariants (fix immediately if violated)

- `Newest` is the default Dock lens.
- The default row list is ordered by `lastActivity` descending with deterministic tie-breakers, not status priority.
- `Needs me` is not a visible primary Dock tab, lens, status chip, top section, default ranking input, or filter in V1.
- `Limited` is not visible or accessible copy anywhere in Dock.
- `Not loaded` never implies rate limiting, provider failure, user blocking, or broken access.
- Raw endpoint strings stay in Relay settings, diagnostics, logs, or detail/tooltip contexts; the Dock scan path uses short display names.
- Every visible narrowing rule is reflected in search text, selected lens, active filter chips/summary, or the filter surface. No hidden constraints.
- There is one filter model. Header filter icon/control and `Filters` lens/control cannot drift.
- Projection owns list membership, grouping, counts, and ordering. Views render projection output and do not reimplement filtering.
- Relay/app-server DTO contracts remain stable.
- Failure is local where the product can attribute it to a host or scope.
- No compatibility fallback, shadow old UI, feature flag, or migration bridge is allowed under this plan.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Trustworthy product language: literal state labels, no misleading `Limited`, no unsupported rate-limit wording, no predictive `Needs me` default.
2. Newest-first recovery: opening Dock answers what changed most recently across all configured hosts.
3. Known-target lookup: host, branch, repo, status including `Not loaded`, source, idle visibility, and text search are explicit ways to narrow a huge list.
4. Scan speed on iPhone 17 portrait: row identity must survive scrolling, grouping, and thousands of sessions.
5. Multi-host honesty: both configured hosts appear in loading, loaded, partial, and failure states.
6. Performance at thousands of rows: projection is deterministic and list rendering uses lazy containers where SwiftUI needs them.
7. Accessibility as product proof: selected lens, active filters, host/branch groups, loading state, and killed terms are verifiable without relying on screenshots.
8. Minimal protocol blast radius: all changes stay app-side unless code truth forces otherwise.

## 1.2 Constraints

- Current live evidence shows `6,494` rows and roughly `141-150` second reloads on the iPhone 17 simulator path. Loading and large-list behavior are first-order requirements.
- `SessionSummary` has `lastActivity`, not separate public `createdAt`/`updatedAt` fields. Server DTOs have both, but the normalized Dock model currently exposes only last activity; the current mapper prefers `updatedAt` and falls back to `createdAt`.
- Existing active queries load human and agent scopes from the relay-backed app-server through `DockSessionQuery.activeHuman` and `.activeAgents`; archived sessions are loaded by `ArchiveStore`, not Dock.
- Physical iPhone completion evidence must use relay-backed host paths on `:4510`, not `127.0.0.1:4500`, mocks, or Unix sockets.
- App service and install workflows are Makefile-owned. Normal checks use `rtk make ...`, not raw platform commands.
- `.env` is user-owned and cannot be modified.
- SwiftUI row layout must avoid clipped text and overlapping controls on iPhone 17 portrait.
- The repo already has dirty/generated history under `docs/**`; this plan only adds/updates canonical planning docs and later implementation files.
- App-level tabs must remain stable: `Dock`, `Archive`, `Relay`.

## 1.3 Architectural principles (rules we will enforce)

- One projection owner: `DockSessionProjection` is the only place that decides visible rows, lens grouping, active-filter counts, hidden counts, and sort order.
- Thin views: `DockView` can select lens/filter/search state and render view models, but it must not contain duplicate filter predicates or grouping logic.
- Literal vocabulary in types: status labels are represented by enum cases that match product language (`running`, `idle`, `notLoaded`, `error`, `unknown`), not by ad hoc display strings.
- Deterministic derivation: host display names are derived through one helper/model path used by Dock, Archive, Relay connectivity, tests, and accessibility values.
- Fail local: host and scope failures stay attached to their host/scope unless every configured host fails.
- Keep contracts stable: `AppServerDockClient`, `ThreadListDTO`, and relay scripts are preservation surfaces, not design playgrounds for this UX refactor.
- Cut over cleanly: delete or replace old primary tab/sort UI instead of leaving it hidden or parallel.
- Simulator-first proof: user-visible Dock behavior is primarily proven in the iPhone 17 simulator through generated app UI tests, accessibility output, and app logs. Unit tests support internal logic, but they do not substitute for simulator proof.

## 1.4 Known tradeoffs (explicit)

- We will remove `Needs me` from primary Dock UX even though `SessionStatus.needsAttention` and active flags exist. The product trust win is higher than preserving an unreliable workflow bucket.
- We will keep archived sessions in the existing `Archive` tab for this plan. Adding `Show archived` to Dock would require merging `ArchiveStore` and `DockStore` result sets and changing list meaning; that is a separate product decision.
- We will derive short host names instead of adding persisted custom host aliases. That avoids config migration and keeps Relay settings as the endpoint source of truth.
- We will make default sort "newest last activity" only. Created-date sort is not promised until `SessionSummary` exposes a distinct created date.
- We will use immediate filter application with visible reset/clear in V1. Staged Apply is out of scope unless a future user-approved scope change records it.
- We will keep row summaries compact. The Dock is an index; thread detail remains the place for full content.
- We will not optimize reload duration in this plan except for rendering/projection cost. Network pagination, relay performance, and server-side filtering can be future work after the UX surface is correct.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

- `CodexDockRootView` owns app-level tabs: `Dock`, `Archive`, and `Relay`.
- `DockView` owns UI state: `selectedTab: DockTabID = .all`, `searchText`, `sortMode: DockSessionSortMode = .branch`, and `showsIdle = false`.
- `DockView.controls` renders a segmented primary tab row (`All`, `Needs me`, `Running`, `Agents`), then a cramped horizontal row with a search field fixed around `154` points, a `Branch`/`Newest` sort picker, and an `Idle` button.
- `DockView.loadedContent` renders all `snapshot.hostStates` as `HostSummaryView` rows before any session rows.
- `DockView.content` has single-host `idle`, `loading`, `offline`, and `error` states, even though loaded snapshots support multiple host states.
- `DockSessionProjectionOptions` contains `selectedTab`, `searchText`, `sortMode`, and `showsIdle`.
- `DockSessionProjection` filters all rows by search, idle visibility, and selected tab, then returns either branch sections or a flat `Newest` section.
- `SessionRowProjector` builds branch/host section titles and currently sorts by status priority before recency in its base section construction.
- `SessionRowProjector.status(for:)` maps active waiting-on-user/input flags to `.needsMe`.
- `DockRowStatusKind` currently includes `.needsMe`, `.running`, `.idle`, `.notLoaded`, `.failed`, and `.unknown`; `.failed` displays as `Error`.
- `DockRowView` displays title, status chip, `repository · branch`, optional label, summary, and relative activity time. It does not visibly show host.
- `DockHostConfiguration.displayName` currently returns the endpoint display string, so Dock host names are endpoint-heavy.
- `AppServerDockClient` loads active human and active agent scopes per host, sorted by server `updated_at` descending, and maps rows to `SessionSummary.lastActivity`.
- `ArchiveStore` separately loads archived human sessions for the `Archive` app tab.

## 2.2 What's broken / missing (concrete)

- The default Dock state is not the user's actual recovery task. It starts with primary status/source tabs and branch grouping instead of newest activity.
- The old primary tabs look final even while loading. On iPhone 17 accessibility output, they appear as `All 0`, `Needs me 0`, `Running 0`, and `Agents 0` during a long load.
- `Needs me` is product-hostile in this context because the signal is not reliable enough to deserve first-screen navigation or ranking.
- Search is visibly squeezed beside other controls instead of being a first-class giant-list affordance.
- Host summaries are detached and pinned above the list, consuming first-viewport space while rows below still fail to carry host identity.
- Raw endpoint strings dominate host identity in the scan path.
- Multi-host loading is dishonest: `.loading(host)` names one host while configuration can contain two or more.
- The view contains old projection concepts (`DockTabID`, `DockSessionSortMode`) that no longer match the target IA (`Newest`, `Host`, `Branch`, `Filters`).
- Filtering is split across selected tab, sort mode, search, and idle button instead of one explicit filter model with one visible summary.
- Empty-state copy is keyed to old tabs, including `Nothing needs you`.
- Status priority currently affects ordering before recency in base projections; default newest must not let status silently outrank last activity.
- The existing row model lacks a visible host display field, so branch and newest views cannot make rows self-contained without view-level host lookup.

## 2.3 Constraints implied by the problem

- The implementation must be a clean IA cutover, not an incremental visual tweak to old tabs.
- Projection and tests must move together because existing tests assert old tab counts and old branch/newest behavior.
- Loading/failure model changes must preserve current connectivity reporting behavior enough that `GlobalConnectivityIndicatorView` still receives accurate host status.
- Row display changes must not break thread navigation, archive action, local labels, local rail colors, or thread detail store construction.
- Search and filters must be modeled below SwiftUI views so future UI controls can reuse the same logic.
- Since archived sessions are separate today, the filter plan must explicitly say that archive visibility is conditional/out of Dock V1.
- Since `createdAt` is not normalized into `SessionSummary`, the sort surface must not expose created date in V1.

# 3) Research Grounding (external + internal "ground truth")

## 3.1 External anchors (papers, systems, prior art)

<!-- arch_skill:block:research_grounding:start -->

- Apple Human Interface Guidelines, Search Fields:
  - Adopted: broad search should come first, with scope/filter refinement layered on top.
  - Dock consequence: search is global by default, full-width on iPhone, and active filters are visible as chips/summary.
- Apple Human Interface Guidelines, Tab Bars:
  - Adopted: tabs are stable top-level destinations, not content modes or actions.
  - Dock consequence: app-level tabs stay `Dock`, `Archive`, `Relay`; `Newest`, `Host`, `Branch`, and `Filters` are Dock-internal controls.
- Nielsen Norman Group information foraging / information scent:
  - Adopted: users choose rows by perceived value and cost.
  - Dock consequence: rows must carry title, host, repo, branch, status, and recency so the user can judge relevance without remembering a far-away header.
- Nielsen Norman Group scanning behavior:
  - Adopted: large lists are scanned quickly and identifiers must be compact and front-loaded.
  - Dock consequence: short host display names beat endpoint strings; row metadata must be predictable and compact.
- Faceted navigation research from NN/g and Baymard large-list work:
  - Adopted: large result sets need explicit facets, counts where practical, and visible reversible narrowing.
  - Dock consequence: host, branch, status including `Not loaded`, repo/working directory, source, and idle visibility are filters/facets, not hidden rankers.
- Existing strategy doc `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md`:
  - Adopted: live iPhone 17 observation proves this is not theoretical. The current surface can spend minutes loading thousands of rows while showing zero-count tabs, cramped search, endpoint-heavy host identity, and one-host loading copy for a two-host config.

## 3.2 Internal ground truth (code as spec)

- Canonical UX/spec input:
  - `docs/mockups/codex-dock-activity-first-2026-05-29/README.md`
  - `docs/mockups/codex-dock-activity-first-2026-05-29/requirements/GLOBAL_REQUIREMENTS.md`
  - `docs/mockups/codex-dock-activity-first-2026-05-29/requirements/TRACEABILITY_MATRIX.md`
  - `docs/mockups/codex-dock-activity-first-2026-05-29/requirements/screens/*.md`
- Current Dock UI owner:
  - `CodexDock/Features/Dock/DockView.swift`
  - Owns the header, old controls, list rendering, loading/offline/error/loaded UI, root tab content, and row context actions.
- Shared Dock UI owner:
  - `CodexDock/Features/Dock/DockSharedViews.swift`
  - Owns `HostSummaryView`, banners, `DockMessageView`, `DockRowView`, row color/status style, and `DockRowViewModel.automationValue`.
- Projection owner:
  - `CodexDock/State/DockSessionProjection.swift`
  - Must become the canonical owner for lens, filter, search, count, grouping, and sort decisions.
- Store/snapshot owner:
  - `CodexDock/State/DockStore.swift`
  - Owns `DockRowStatusKind`, `DockTabID`, `DockRowViewModel`, `DockSectionViewModel`, `DockHostViewModel`, `DockSnapshot`, host state models, load/reload flow, scope load failure models, and action persistence.
- Row normalization owner:
  - `CodexDock/State/SessionRowProjector.swift`
  - Owns conversion from `SessionSummary` to row view models, relative time, status mapping, branch/host section titles, row ordering, and rail defaults.
- Host config owner:
  - `CodexDock/Configuration/DockHostConfiguration.swift`
  - Owns relay endpoint parsing and current `displayName`, which is presently just `endpoint.displayEndpoint`.
- Connectivity owner:
  - `CodexDock/State/AppConnectivityStore.swift`
  - Owns host rollup and overall status label/message.
  - `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` renders the chip.
- Automation owner:
  - `CodexDock/Automation/AutomationID.swift`
  - Must gain stable IDs for lenses, filters, group headers, loading rows, clear actions, retry, and Relay settings.
- Data-contract owner:
  - `CodexDock/Models/SessionSummary.swift` exposes `lastActivity`, `repository`, `workingDirectory`, `branch`, `status`, and `origin`.
  - `CodexDock/AppServer/ThreadListDTO.swift` has `createdAt` and `updatedAt`, but current normalized Dock list exposes only `lastActivity`; mapping prefers `updatedAt` and falls back to `createdAt`.
  - `CodexDock/State/AppServerDockClient.swift` requests `sortKey: .updatedAt`, `sortDirection: .desc`, active human/agent scopes, and archived false for Dock.
- Archive owner:
  - `CodexDock/State/ArchiveStore.swift` and `CodexDock/Features/Archive/ArchiveView.swift` own archived sessions.
  - Dock V1 does not merge these rows.
- Existing tests to rewrite/extend:
  - `CodexDockTests/DockStoreTests.swift`
  - `CodexDockTests/DockStoreScopeTests.swift`
  - `CodexDockTests/DockStoreTestsProjection.swift`
  - `CodexDockTests/ThreadListMappingTests.swift` only if normalized dates/status fields change.
  - `CodexDockTests/AutomationIDTests.swift` for new identifiers.
- Runnable command truth:
  - `Makefile`, `Package.swift`, `project.yml`, and `package.json`.
  - Use `rtk swift test --filter DockStoreTests` first for Dock/store/projection changes.
  - Use `rtk make app-test SIM='iPhone 17'` for installed simulator UI behavior. `rtk make app SIM='iPhone 17'` is diagnostic only and cannot replace app-test completion proof.
- Canonical owner path for this change:
  - `DockStore` loads and stores raw host/session state.
  - `SessionRowProjector` normalizes `SessionSummary` into row view models.
  - `DockSessionProjection` turns rows plus explicit user controls into renderable sections/groups/counts.
  - `DockView` renders only the selected projection state and forwards actions back to stores.

## 3.3 Decision gaps that must be resolved before implementation

- None.

Resolved implementation decisions:

- `Archive` remains a separate app tab in V1; the Dock filter surface must not expose a fake `Show archived` toggle unless Dock actually includes archived rows.
- Archive-visibility requirement disposition: `G-047` applies only when archived sessions can appear in Dock results. `S05-038`, the `05-filters` archive acceptance bullet, and `S06-008` archive-filter preservation are not applicable to Dock V1 because archived sessions remain exclusively in `ArchiveStore` and the `Archive` tab.
- `Filters` applies immediately in V1 and offers reset/clear. There is no inert Apply button.
- The only V1 sort is newest last activity. Created-date sort is not exposed until `SessionSummary` carries a distinct created date.
- `Needs me` is removed from primary Dock vocabulary. Waiting-on-user/approval active flags map to `Running` for Dock rows until a future explicit product signal is designed.
- Host display names are deterministic derived labels. Persisted aliases and pinned host order are out of scope.
- Retry attached to a failed host may call the existing full Dock refresh in V1; per-host retry is not required unless it falls out naturally from store refactoring.
- Header host-count shortcut pills from `G-029A`/`G-029B` are not in V1. Compact global connectivity and explicit Host lens/filter controls cover the required host lookup without adding another first-screen shortcut.
- Search updates results as the user types through local projection. Debounce is allowed only as a performance implementation detail and must not require a submit action.
- Pinning from `G-156` is out of V1; if it returns later, it must be explicit visible user intent.

<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->

## 4.1 On-disk structure

- `CodexDock/Features/Dock/DockView.swift`
  - `CodexDockRootView`: root app tab container.
  - `DockView`: current Dock screen, header, controls, content state switch, loaded list renderer, row actions, and empty-state copy.
  - `PreviewDockSessionLoader`: old preview rows, including a `preview-needs-me` row.
- `CodexDock/Features/Dock/DockSharedViews.swift`
  - `HostSummaryView`: old host block/card-like summary.
  - `MappingFailureBanner`, `ActionErrorBanner`, `ScopeLoadFailureBanner`, `ScopeConflictBanner`.
  - `DockMessageView`.
  - `DockRowView`.
  - `DockRowViewModel.automationValue`.
- `CodexDock/State/DockStore.swift`
  - Public view models used by Dock and tests: `DockRowStatusKind`, `DockTabID`, `DockTabViewModel`, `DockRowViewModel`, `DockSectionViewModel`, `DockHostViewModel`, `DockSnapshot`, `DockHostLoadStatus`, `DockHostStateViewModel`, `DockSessionScope`, `DockScopeLoadFailureViewModel`, `DockScopeConflictViewModel`, and `DockStoreState`.
  - `DockStore` load, refresh, archive, local metadata, snapshot construction, and host/scope failure mapping.
- `CodexDock/State/DockSessionProjection.swift`
  - `DockSessionSortMode` with `.branch` and `.newest`.
  - `DockSessionProjectionOptions` with `selectedTab`, `searchText`, `sortMode`, `showsIdle`.
  - `DockSessionProjection` with `tabs`, `sections`, `hiddenIdleMatchCount`.
  - Private projector with search, idle filtering, selected-tab filtering, branch/newest section output, and recency ordering.
- `CodexDock/State/SessionRowProjector.swift`
  - Normalizes `SessionSummary` to rows and initial branch/host sections.
  - Current ordering prioritizes status before recency in base sections.
- `CodexDock/State/AppServerDockClient.swift`
  - Loads active human and agent scopes from app-server.
  - Uses `ThreadListParams(sortKey: .updatedAt, sortDirection: .desc, archived: query.archived)`.
- `CodexDock/State/ArchiveStore.swift` and `CodexDock/Features/Archive/ArchiveView.swift`
  - Separate archived-session store and surface.
- `CodexDock/Configuration/DockHostConfiguration.swift`
  - Endpoint parsing and host config.
  - `displayName` currently equals `endpoint.displayEndpoint`.
- `CodexDock/State/AppConnectivityStore.swift` and `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - Connectivity rollup and chip rendering.
- `CodexDock/Automation/AutomationID.swift`
  - Current Dock IDs cover root, filter picker, search field, sort picker, idle toggle, add-host button, state, old filter tabs, host summary, section, scope banners, rows, and row actions.
- `CodexDockTests/**`
  - Existing Dock tests assert old tabs, old selected-tab semantics, old sort modes, old status priority, old empty-state assumptions, and old projection shape.

## 4.2 Control paths (runtime)

Current app-open path:

1. `CodexDockRootView` initializes `DockStore`, `ArchiveStore`, `HostSettingsStore`, `AppConnectivityStore`, and `AppLifecycleCoordinator`.
2. `TabView` selects `.dock` by default.
3. `DockView` starts with local UI state:
   - `selectedTab = .all`
   - `searchText = ""`
   - `sortMode = .branch`
   - `showsIdle = false`
4. `CodexDockRootView.task` binds connectivity and calls `runDockRefreshLoop`.
5. `DockStore.load()` calls `reload(showLoading: true)`.
6. `DockStore.reload` sets `.loading(DockHostViewModel(host: hosts[0]))` even when `hosts.count > 1`.
7. `DockStore.loadAllHosts()` loads each configured host in parallel.
8. Each host loads every `DockSessionScope` in parallel:
   - `.human` -> `.activeHuman`
   - `.agents` -> `.activeAgents`
9. `DockStore.makeSnapshot(results:)` deduplicates cross-scope rows per host, creates host states, mapping failure banners, scope failure banners, conflicts, and sections.
10. `SessionRowProjector.sections(from:)` maps each `SessionSummary` into `DockRowViewModel`, groups by branch or host/branch, and sorts by status priority then last activity.
11. `DockView.loadedContent` calls `snapshot.project(options:)`.
12. `DockSessionProjectionProjector` applies search, idle visibility, selected old tab, and sort mode.
13. `DockView.loadedContent` renders host summary rows, banners, old sections, rows, and row context menus.

Current interaction path:

- Search modifies local `searchText`; projection recomputes.
- Sort picker changes `.branch` or `.newest`; projection recomputes.
- Idle button toggles `showsIdle`; projection recomputes and reports hidden idle count.
- Old primary filter picker changes `DockTabID`; projection recomputes.
- Row tap builds `ThreadDetailStore(host: rowHost, row: row, ...)`.
- Row archive action calls `DockStore.archive(row)` then refreshes `ArchiveStore`.
- Relay settings are only reachable through the app-level `Relay` tab; Dock failure UI has no direct path there.

## 4.3 Object model + key abstractions

Current status model:

- `SessionStatus`
  - `.unknown`
  - `.notLoaded`
  - `.idle`
  - `.systemError`
  - `.active(activeFlags:)`
- `DockRowStatusKind`
  - `.needsMe` -> visible `Needs me`
  - `.running` -> visible `Running`
  - `.idle` -> visible `Idle`
  - `.notLoaded` -> visible `Not loaded`
  - `.failed` -> visible `Error`
  - `.unknown` -> visible `Unknown`
- `SessionRowProjector.status(for:)`
  - `.active` with waiting flags -> `.needsMe`
  - `.active` without waiting flags -> `.running`
  - `.notLoaded` -> `.notLoaded`
  - `.systemError` -> `.failed`

Current navigation/filter model:

- `DockTabID`
  - `.all`: human interactive rows
  - `.needsMe`: human interactive `.needsMe`
  - `.running`: human interactive `.needsMe`, `.running`, `.idle`, `.failed`
  - `.agents`: non-human rows
- `DockSessionSortMode`
  - `.branch`: grouped sections
  - `.newest`: flat newest section
- `showsIdle`
  - hides or shows idle rows.
- `searchText`
  - matches title, repo, branch, summary, status label, local label, host display name/id, and thread id.

Current list model:

- `DockSnapshot.sections` are already grouped before projection.
- `DockSessionProjection.sections` either preserves branch sections or flattens rows into `Newest`.
- `DockSnapshot.tabs` and projection `tabs` are old tab count models.
- `DockRowViewModel` has no `hostDisplayName`, `hostEndpoint`, `hostStatus`, `sourceLabel`, or `visibility` fields.

Current host model:

- `DockHostConfiguration.id` is endpoint id.
- `DockHostConfiguration.displayName` is endpoint display string.
- `DockHostViewModel.displayName` is therefore endpoint-like.
- `DockHostViewModel.endpoint` is also endpoint display string.
- There is no distinction between primary host display name and diagnostic endpoint.

Current failure model:

- Single-host complete failure becomes `.offline(host, message)` or `.error(host, message)`.
- Multi-host complete/partial failures stay in `.loaded(snapshot)` and host states/banners.
- `DockScopeLoadFailureViewModel` can attribute a scope failure to host and scope.
- `DockHostStateViewModel` can represent `.loaded`, `.partial`, `.empty`, `.offline`, `.error`.
- Loading state does not yet use multi-host host states.

## 4.4 Observability + failure behavior today

- `DockStore` logs reload start/finish, host count, rows, mapping failures, scope failures, conflicts, and duration through `DockLog`.
- `AppServerDockClient` logs host load start/finish, archived flag, source kinds, rows, mapping failures, and duration.
- `AppConnectivityStore` logs host phases and overall status.
- `GlobalConnectivityIndicatorView` exposes `overallStatus.label` visibly and `overallStatus.message` as accessibility value.
- Current loading accessibility can expose one host as checking/loading and old zero-count tabs.
- Current loaded accessibility can become expensive with thousands of descendants.
- Physical Mobile MCP may fail with `WebDriverAgent is not running on device`; if it does, repo instructions require stopping physical Mobile MCP retries and using simulator/local proof where valid.
- Real phone-path completion requires relay-backed `:4510` host paths and real `SessionSummary` rows.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current first screen, simplified:

```text
+------------------------------------------------+
| Dock                              [Online] [+] |
| [All 0] [Needs me 0] [Running 0] [Agents 0]    |
| [tiny Search] [Branch|Newest] [Idle]           |
|                                                |
| [desktop] amir-m5.fairy-salmon.ts.net:4510     |
|           amir-m5.fairy-salmon.ts.net:4510 ... |
|                                                |
| [spinner or sections]                          |
+------------------------------------------------+
| Dock              Archive              Relay   |
+------------------------------------------------+
```

Current loaded shape, simplified:

```text
+------------------------------------------------+
| Host summary block for host A                  |
| Host summary block for host B                  |
| warning / failure banners                      |
|                                                |
| HOST A / branch-one                            |
| [row title]                       [status]     |
| repo - branch                                  |
| summary                                        |
| 2m ago                                      >  |
|                                                |
| HOST B / branch-two                            |
| [row title]                       [status]     |
| repo - branch                                  |
| summary                                        |
+------------------------------------------------+
```

Problems visible in the current ASCII:

- Host identity is detached from rows.
- Search is not sized like the primary large-list tool.
- Old zero-count tabs dominate loading.
- `Needs me` is primary.
- Branch grouping is the default.
- Endpoint strings are first-class visible identity.

<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->

## 5.1 On-disk structure (future)

Preferred file ownership after implementation:

- `CodexDock/Features/Dock/DockView.swift`
  - Keep `CodexDockRootView`.
  - Keep top-level `DockView`.
  - Remove old primary tab/sort/idle control composition.
  - Add `onOpenRelaySettings` closure from root to Dock.
  - Keep row navigation and row context actions.
- `CodexDock/Features/Dock/DockSharedViews.swift`
  - Keep generic banners and `DockRowView`.
  - Replace or retire old `HostSummaryView` for primary Dock scan path.
  - Add or extract `DockHeaderView`, `DockLensPicker`, `DockSearchField`, `DockActiveFilterSummaryView`, `DockFilterSurfaceView`, `DockHostGroupHeaderView`, `DockBranchGroupHeaderView`, `DockLoadingHostRowView`, `DockHostFailureView`, `DockFilteredEmptyView`, and `DockNotLoadedExplanationView`.
  - If the file gets unwieldy, split to sibling files under `CodexDock/Features/Dock/` with narrow names; do not create a new feature module.
- `CodexDock/State/DockStore.swift`
  - Keep store/loading/action ownership.
  - Replace old visible tab models with new lens/filter support types.
  - Add multi-host loading state support.
  - Add short host display model support.
- `CodexDock/State/DockSessionProjection.swift`
  - Replace `DockSessionSortMode` and `DockSessionProjectionOptions.selectedTab` with `DockLensID`, `DockFilterState`, `DockSortOrder`, `DockProjectionOptions`, `DockProjection`, and grouped section/group view models.
- `CodexDock/State/SessionRowProjector.swift`
  - Add row host metadata and new status mapping.
  - Stop using status priority ahead of recency for default ordering.
- `CodexDock/Configuration/DockHostConfiguration.swift`
  - Add a deterministic display-name helper without changing endpoint persistence.
- `CodexDock/State/HostSettingsStore.swift`
  - Preserve Relay/settings ownership of endpoint rows and saved host configuration.
- `CodexDock/Features/Hosts/HostsView.swift`
  - Use the short host display name as the settings row title and keep the endpoint string visible as detail text.
- `CodexDock/State/AppConnectivityStore.swift`
  - Adjust overall status copy to expose host counts compactly.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - Render compact labels such as `Online 2/2`, `Checking 2 hosts`, and `Online 1/2`.
- `CodexDock/Automation/AutomationID.swift`
  - Add IDs for the target control and state model.
- `README.md`
  - Replace stale Dock controls documentation.
- `CodexDockTests/**`
  - Rewrite affected tests to target the new architecture.

## 5.2 Control paths (future)

Future app-open path:

1. `CodexDockRootView` still initializes the same stores and starts the same refresh loop.
2. `DockView` starts with local UI state:
   - `selectedLens = .newest`
   - `searchText = ""`
   - `filterState = .default`
   - `isFilterSurfacePresented = false`
   - `collapsedHostGroupIDs` and `collapsedBranchGroupIDs` derived from current projection defaults.
3. `DockStore.load()` enters `.loading([DockHostViewModel])`.
4. Loading UI renders stable Dock header/search/lens controls, compact checking connectivity, one loading row per configured host using short display names, and no final old tab counts.
5. `DockStore.loadAllHosts()` continues loading hosts/scopes in parallel.
6. `DockStore` publishes partial loaded snapshots as host outcomes complete, so loaded host rows can render while unfinished hosts remain checking.
7. `DockStore.makeSnapshot(results:)` builds `DockSnapshot` with rows, host states, scope failures, conflicts, mapping failures, per-host metadata, and a partial-loading marker when any configured host is still checking.
8. `SessionRowProjector` emits row view models that already include host display metadata and approved status vocabulary.
9. `DockView` builds `DockProjectionOptions(lens: selectedLens, searchText: searchText, filters: filterState)`.
10. `DockSessionProjection` returns one `DockProjection` containing visible rows, active filter summary, visible result count, hidden/available counts, lens-specific groups or flat rows, and empty/failure context.
11. `DockView` renders the projection:
    - `.newest`: flat newest-first rows.
    - `.host`: host groups with nested rows and host-local failure/loading/empty state.
    - `.branch`: branch groups with nested rows and host names retained in rows.
    - filter surface: same `filterState`, not a separate model.
12. Retry action calls `store.refresh()` in V1 and keeps the host-local UI copy attached to the host whose failure initiated it.
13. Relay settings action calls `onOpenRelaySettings`, implemented by root as `selectedRootTab = .relay`.

Future search/filter path:

- Search text is global, applies before lens grouping, and is the first-screen branch search for result rows.
- Search matching is case-insensitive in V1 unless a later explicit product decision makes branch search case-sensitive.
- Filters compose in this order: search, host filter, branch selected-values filter, status filter including `Not loaded`, repo/working-directory filter, source filter, and idle visibility.
- Lens changes preserve `searchText` and `filterState`.
- Clear search clears only search.
- Clear filters resets `filterState` only.
- Reset all resets search, filters, and lens only if the control explicitly says it resets all; default clear-filter action must not surprise the user.

Branch search ownership:

| User intent | Owning state | Result effect | Clear behavior |
| --- | --- | --- | --- |
| Find rows by typing `dock-ui`, `feature/dock`, repo plus branch, or host plus branch from the main Dock screen | `DockView.searchText` passed to `DockProjectionOptions` | Filters the actual visible result rows, then preserves the selected lens grouping over the matched subset | `Clear search` only clears `searchText` |
| Find a branch chip inside the filter surface | Local `DockFilterSurfaceView` state, not `DockFilterState` | Narrows the chip/options list only; it does not filter rows until the user selects a branch | Closing or clearing the chip search does not clear selected branch filters |
| Filter rows to one or more known branches | `DockFilterState.selectedBranches` | Filters visible rows and groups to those branches, composed with search and all other filters | `Clear filters` clears selected branches without clearing `searchText` |

Branch-search presentation decision:

- V1 preserves the selected lens grouping while applying global branch/search text.
- V1 does not sometimes flatten and sometimes group.
- If a future design chooses a flattened branch-search result mode, it must replace this rule and update the requirement disposition sidecar.

## 5.3 Object model + abstractions (future)

New or revised enums:

```swift
enum DockLensID: String, CaseIterable, Identifiable, Sendable {
    case newest
    case host
    case branch
}

enum DockSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newestActivity
}

enum DockSourceFilter: String, CaseIterable, Identifiable, Sendable {
    case any
    case human
    case agents
    case unknown
}
```

Status vocabulary:

```swift
public enum DockRowStatusKind: String, Equatable, Sendable, CaseIterable {
    case running
    case idle
    case notLoaded
    case error
    case unknown
}
```

Rules:

- Delete `.needsMe` from visible Dock row status.
- Rename `.failed` to `.error`; do not keep `.failed` as an internal alias.
- Map `SessionStatus.active(activeFlags:)` to `.running` for Dock row status.
- Keep `SessionStatus.needsAttention` only if other non-Dock code uses it; do not surface it in Dock primary UX.

Filter model:

```swift
struct DockFilterState: Equatable, Sendable {
    var hostIDs: Set<String>                  // empty means Any
    var selectedBranches: Set<String>         // empty means Any
    var statusKinds: Set<DockRowStatusKind>   // empty means Any
    var repoQuery: String                     // empty means Any
    var selectedRepositories: Set<String>     // empty means Any
    var source: DockSourceFilter              // default .any
    var showsIdle: Bool                       // default false
    var sortOrder: DockSortOrder              // default .newestActivity
}
```

Not-loaded filter ownership:

- `statusKinds` is the only V1 result-filter owner for `Not loaded`.
- Default status `Any` includes `Not loaded` rows.
- Selecting only `Not loaded` in the status filter produces not-loaded-only results and shows the explanatory copy.
- There is no separate three-way not-loaded visibility control in V1.
- Hiding not-loaded rows, if wanted later, must be a future explicit product decision because a second owner would make the filter surface harder to reason about.

Source default:

- Decision: default V1 source is `.any` for rows that Dock already loads, because the mockup package removes `Agents` as primary plumbing. The filter surface exposes `Human` and `Agents`. If product wants agents hidden by default later, it must be visible as `Source: Human`, not hidden old `All`.

Archive:

- No `showArchived` field in V1 `DockFilterState` because Dock does not load archived rows.
- If a future plan merges archived rows into Dock, add `archiveVisibility`, loader changes to fetch `.archivedHuman`, row field `isArchived`, and Archive/Dock action reconciliation.

Projection output:

```swift
struct DockProjection: Equatable, Sendable {
    let lens: DockLensID
    let rows: [DockRowViewModel]
    let groups: [DockProjectionGroup]
    let activeSummary: DockActiveFilterSummary
    let resultCount: Int
    let hiddenCounts: DockHiddenCounts
    let availableFacets: DockAvailableFacets
    let emptyReason: DockEmptyReason?
}

struct DockProjectionGroup: Equatable, Identifiable, Sendable {
    let id: String
    let kind: DockProjectionGroupKind
    let title: String
    let subtitle: String?
    let rows: [DockRowViewModel]
    let hostIDs: [String]
    let status: DockGroupStatus?
    let newestActivityDate: Date?
    let visibleCount: Int
    let hiddenIdleCount: Int
    let isCollapsedByDefault: Bool
}
```

Row model additions:

```swift
public struct DockRowViewModel: Equatable, Identifiable, Sendable {
    public let id: HostScopedThreadID
    public let backendSessionID: String
    public let title: String
    public let hostDisplayName: String
    public let hostEndpoint: String
    public let repository: String
    public let branch: String
    public let status: DockRowStatusKind
    public let lastActivity: String
    public let lastActivityDate: Date
    public let summary: String
    public let rail: DockRowRail
    public let label: String?
    public let origin: SessionOrigin
}
```

Host display name derivation:

- Add a helper, for example `DockHostDisplayNameResolver`.
- Input: `DockRelayEndpoint.host`.
- Output rules:
  - strip port,
  - strip `.fairy-salmon.ts.net`,
  - strip `.local`,
  - convert `amir-m5` to `Amir-M5`,
  - convert `home` to `Home`,
  - preserve IP literals if there is no better name,
  - preserve unknown host labels after trimming domain suffixes and capitalizing hyphenated tokens conservatively.
- `DockHostViewModel.displayName` uses this helper and becomes the short display name for app UI.
- `DockHostViewModel.endpoint` remains endpoint display string for diagnostics/settings.
- `DockHostConfiguration.displayName` also returns the short display name so thread-detail headers and store view models do not regress to endpoint-heavy labels.
- `DockRelayEndpoint.displayEndpoint` remains the endpoint string for Relay settings detail rows, diagnostics, and logs.

Connectivity labels:

- Add a display label path that can say `Online 2/2`, `Online 1/2`, `Checking 2 hosts`, `Offline`, `Error`, or `Config error`.
- Accessibility value keeps more detail, including host names and messages.

Expansion state:

- Expansion lives in `DockView` local state as sets of collapsed host/branch group IDs.
- Projection supplies stable group IDs and collapse defaults.
- UI expansion state must not change filtering membership.

## 5.4 Invariants and boundaries

- `DockSessionProjection` takes all rows plus options and returns all derived visible state. No view-level list filtering.
- `DockView` never constructs its own row arrays except by reading `projection.rows` or `projection.groups`.
- `SessionRowProjector` can normalize row fields but does not know selected lens/filter/search.
- `DockStore` can know host load state but not UI-selected lens/filter/search.
- `ArchiveStore` remains separate and is not coupled to Dock filters in V1.
- `DockHostConfiguration` remains host+port persistence; display-name derivation must not mutate saved endpoints.
- Accessibility IDs are stable API; dynamic IDs use safe host/thread/group IDs only.
- Relay settings, diagnostics, logs, and details are the places where endpoint strings remain visible. Relay settings may use the short host name as the row title and the endpoint as the detail line.
- Local metadata (`rail`, `label`) survives because row `metadataKey` remains host/session/thread based.
- Thread navigation remains host-scoped by `row.id.hostID`.
- Row archive action continues to call `DockStore.archive(row)` and refresh Archive on success.
- No feature flag for old Dock. Once implemented, old primary tabs and sort controls are gone from the primary UI.

Large-list rendering boundary:

- `DockView` must render session rows and groups through `LazyVStack` inside the existing scroll container or an equivalent lazy SwiftUI list container.
- Header, search, lens controls, and active-filter summary remain outside the lazy row stack so they do not get recycled as row content.
- Projection should avoid repeated O(n) work inside row bodies; facets and counts are computed once per projection.
- Group expansion/collapse should filter already-projected group rows during render, not rerun network loads.
- Accessibility values should expose counts and selected state without forcing tests to traverse thousands of row descendants.

State ownership boundary:

- Store state answers "what data and host status do we have?"
- Projection answers "what rows/groups should the current Dock controls show?"
- View state answers "which lens/filter/search/expanded groups has the user selected?"
- Connectivity state answers "what is the compact global connection summary?"
- No one else answers those questions.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Default newest:

```text
+------------------------------------------------+
| Dock                                  Online 2/2 |
| [ Search sessions, repo, branch, host        ] |
| [Newest] [Host] [Branch]            [Filters] |
| Host: Any  Branch: Any  Source: Any  Idle: Off|
| 6,494 shown                                    |
+------------------------------------------------+
| [blue] Render geometry audit      Running  2m |
|        Amir-M5 / codex-client / dock-ui       |
|        command output updated                 |
|                                                |
| [red ] Account rotation plan      Idle     8m |
|        Home / aimgr / codex-rotation          |
|        last assistant message                 |
|                                                |
| [gray] Dart animation SSOT        Not loaded  |
|        Amir-M5 / lessons / feature/animation  |
|        Thread detail is not loaded yet.       |
+------------------------------------------------+
| Dock              Archive              Relay   |
+------------------------------------------------+
```

Host lens:

```text
+------------------------------------------------+
| Dock                                  Online 2/2 |
| [ Search sessions, repo, branch, host        ] |
| [Newest] [Host] [Branch]            [Filters] |
| Host: Any  Branch: Any  Source: Any  Idle: Off|
+------------------------------------------------+
| v Amir-M5                  Online   3,202 shown|
|   newest 2m   idle hidden                      |
|   [blue] Render geometry audit    Running  2m |
|          codex-client / dock-ui                |
|                                                |
| v Home                    Online   3,292 shown |
|   newest 8m   idle hidden                      |
|   [red ] Account rotation plan    Idle     8m |
|          aimgr / codex-rotation                |
+------------------------------------------------+
```

Branch lens:

```text
+------------------------------------------------+
| Dock                                  Online 2/2 |
| [ Search sessions, repo, branch, host        ] |
| [Newest] [Host] [Branch]            [Filters] |
| Host: Any  Branch: dock-ui  Idle: Off          |
+------------------------------------------------+
| v dock-ui                       18 sessions    |
|   Amir-M5, Home   newest 2m                    |
|   [blue] Render geometry audit    Running  2m |
|          Amir-M5 / codex-client                |
|                                                |
| v feature/animation             6 sessions     |
|   Amir-M5        newest 19m                    |
|   [gray] Dart animation SSOT      Not loaded   |
|          Amir-M5 / lessons                     |
+------------------------------------------------+
```

Filter surface:

```text
+------------------------------------------------+
| Dock filters                         1,178 shown|
| [ Search sessions, repo, branch, host        ] |
| Host        [Any] [Amir-M5] [Home]             |
| Branch      [ Search branches ]                |
|             [main] [dock-ui] [feature/anim...] |
| Status      [Any] [Running] [Idle] [Not loaded]|
| Repo        [Any] [codex-client] [lessons]     |
| Source      [Any] [Human] [Agents]             |
| Visibility  [ ] Idle                           |
| Sort        Newest activity                    |
| [Clear filters]                                |
+------------------------------------------------+
```

Loading:

```text
+------------------------------------------------+
| Dock                              Checking 2 hosts|
| [ Search sessions, repo, branch, host        ] |
| [Newest] [Host] [Branch]            [Filters] |
| Host: Any  Branch: Any  Source: Any  Idle: Off|
+------------------------------------------------+
| Checking hosts                                  |
| [desktop] Amir-M5                    Checking  |
| [desktop] Home                       Checking  |
|                                                |
| Sessions not loaded yet. Waiting for relay     |
| responses.                                     |
+------------------------------------------------+
```

Partial host failure:

```text
+------------------------------------------------+
| Dock                               Online 1/2 |
| [ Search sessions, repo, branch, host        ] |
| [Newest] [Host] [Branch]            [Filters] |
+------------------------------------------------+
| [blue] Render geometry audit      Running  2m |
|        Amir-M5 / codex-client / dock-ui       |
|                                                |
| > Home                          Offline       |
|   Last check failed: connection timed out      |
|   [Retry] [Relay settings]                    |
+------------------------------------------------+
```

Filtered empty:

```text
+------------------------------------------------+
| Dock                                  Online 2/2 |
| [ dock-ui                                   x ] |
| [Newest] [Host] [Branch]            [Filters] |
| Host: Home  Branch: dock-ui  Idle: Off         |
+------------------------------------------------+
| No sessions match these filters                |
| Host: Home                                     |
| Branch: dock-ui                                |
| Search: dock-ui                                |
| Idle: Off                                      |
| [Clear search] [Clear filters]                 |
+------------------------------------------------+
```

Partial host failure rendering by lens:

| Lens | Required behavior |
| --- | --- |
| `Newest` | Show online rows in newest order and include a compact failed-host row in the feed. The failed-host row names the short host display name, status, concise message, Retry, and Relay settings. It must not hide rows from online hosts. |
| `Host` | Show every configured host group. Failed hosts with no visible rows remain visible, collapsed by default, and keep Retry and Relay settings accessible. Online host groups remain usable. |
| `Branch` | Show branch groups for loaded rows and retain host identity in each row. Also show compact failed-host context so the user knows a branch/search/filter result may be incomplete because a host failed. |
| Filtered/search states | Keep the selected lens, search text, and filters intact. If active constraints could exclude rows from a failed host, the empty or partial-result copy must say the data is incomplete rather than implying the host has no matching sessions. |

<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->

## 6.1 Canonical spec and docs

- `docs/mockups/codex-dock-activity-first-2026-05-29/README.md`
  - Input only for implementation; do not overwrite.
  - Each kill-list item must be traceable to code/test/doc changes.
- `docs/mockups/codex-dock-activity-first-2026-05-29/requirements/GLOBAL_REQUIREMENTS.md`
  - Use as acceptance checklist.
- `docs/mockups/codex-dock-activity-first-2026-05-29/requirements/screens/*.md`
  - Use for state-specific acceptance.
- `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md`
  - Use as research backing and live observation record.
- `README.md`
  - Replace old Search/Sort/Idle description with new Newest/Host/Branch/Filters model.
  - Remove documentation that says Branch sort is a primary control.
  - Keep service/relay/device runbooks unchanged unless wording now conflicts with UI behavior.
- `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md`
  - Canonical requirement-by-requirement disposition sidecar for the mockup package.
  - Enumerates every `G-*` and `Sxx-*` requirement ID found under `docs/mockups/codex-dock-activity-first-2026-05-29/requirements/**`.
  - Implementation must keep this sidecar current when changing scope, adding a not-applicable decision, or satisfying/deleting a requirement differently from this plan.
  - Phase 6 verifies every in-scope requirement row is satisfied and every out-of-scope/N/A row has a matching decision-log entry.

## 6.2 Dock root and navigation

- `CodexDock/Features/Dock/DockView.swift`
  - In `CodexDockRootView`, pass `onOpenRelaySettings` to `DockView` and implement it as `selectedRootTab = .relay`.
  - Preserve `Dock`, `Archive`, `Relay` tabs and tags.
  - In `DockView`, replace `selectedTab` with `selectedLens`.
  - Replace `sortMode` with `filterState.sortOrder`, default `.newestActivity`.
  - Replace `showsIdle` standalone state with `filterState.showsIdle`.
  - Add `filterState`, `isFilterSurfacePresented`, and expansion state sets for host/branch groups.
  - Replace `controls`, `currentTabs`, `projectionOptions`, old empty-state title/message, and old `dockScreenValue`.
  - Replace the current `ScrollView` child `VStack` row renderer with `LazyVStack` for row/group content.
  - Keep header/search/lens controls stable above row content during loading, empty, loaded, and failure states.
  - Render the default active summary with host scope, branch scope, idle visibility, and visible result count even when filters are at defaults.
  - Keep `rowActions`, `rowContextMenu`, archive/label/color behavior, and `.refreshable`.
  - Preview rows must not include a visible `Needs me` concept.

## 6.3 Shared Dock views

- `CodexDock/Features/Dock/DockSharedViews.swift`
  - Stop using `HostSummaryView` as pinned primary content above default list.
  - Remove `Text("\(host.endpoint) · \(subtitle)")` from primary Dock scan path.
  - Update `DockRowView` to include host display metadata when more than one host exists.
  - Replace `repository · branch` with `host / repository / branch` for multi-host, or `repository / branch` for single host.
  - Ensure `Not loaded` chip is neutral.
  - Remove `.needsMe` status color and update `.failed` references to `.error`.
  - Add or split the new header, lens, filter, host group, branch group, loading, failure, filtered empty, and not-loaded explanation views.
  - Keep mapping failure, action error, scope load failure, and conflict banners, but review placement so they do not bury first rows.

## 6.4 Store and public view models

- `CodexDock/State/DockStore.swift`
  - `DockRowStatusKind`: delete `.needsMe`, rename `.failed` to `.error`, and keep labels exactly `Running`, `Idle`, `Not loaded`, `Error`, `Unknown`.
  - Delete `DockTabID` and `DockTabViewModel` after the Phase 2 UI no longer references them.
  - `DockRowViewModel`: add `hostDisplayName`, add `hostEndpoint`, preserve `metadataKey`.
  - `DockSnapshot`: remove `tabs`; carry base rows plus host states/failures/conflicts/mapping failures, with projection creating groups.
  - `DockStoreState`: change `.idle(DockHostViewModel)` and `.loading(DockHostViewModel)` to all-host equivalents.
  - `reload(showLoading:)`: when `showLoading`, publish all configured hosts and report all checking hosts.
  - `makeSnapshot(results:)`: create row models with host display data and no old tabs.
  - `save(metadata:)` error path: update for new state shape.
  - Preserve the single-host `.offline`/`.error` full-screen path only when there is exactly one configured host and that host completely fails.
  - For multi-host total failure, prefer a loaded-style projection shell with host-local failure rows over a global mystery screen so the user still sees both host identities.

## 6.5 Projection

- `CodexDock/State/DockSessionProjection.swift`
  - Replace old file contents with new lens/filter projection.
  - Add `DockLensID`, `DockFilterState`, `DockSortOrder`, `DockProjectionOptions`, `DockProjection`, `DockActiveFilterSummary`, `DockAvailableFacets`, `DockHiddenCounts`, and `DockEmptyReason`.
  - Implement predicates for search, host, selected branches, status including `Not loaded`, repo, source, and idle visibility.
  - Implement grouping for Newest, Host, and Branch.
  - Implement deterministic row ordering by `lastActivityDate` descending, title, then `hostID::threadID`.
  - Do not use status priority by default.
  - Implement visible result count, hidden idle count, not-loaded status counts, and per-facet counts where practical.
  - Search values include title, host display name, host id, repository, branch, summary, status label, label, source label, and thread id.
  - Empty reasons must distinguish:
    - no loaded rows at all,
    - no rows because search matched nothing,
    - no rows because explicit filters exclude all rows,
    - idle rows hidden,
    - status filter selected only `Not loaded`,
    - host/scope data unavailable.
  - Global branch search uses `searchText` and preserves the selected lens grouping over matched rows.
  - Branch chip search inside `DockFilterSurfaceView` is local option-search state only; it must not be added to `DockFilterState`.

## 6.6 Row projection

- `CodexDock/State/SessionRowProjector.swift`
  - Add host display lookup.
  - Populate `DockRowViewModel.hostDisplayName` and `hostEndpoint`.
  - Map active waiting flags to `.running`, not `.needsMe`.
  - Map `.systemError` to `.error`.
  - Keep `.notLoaded` and `.unknown`.
  - Remove `statusPriority` from the default projection path.
  - Return canonical rows for `DockSnapshot`; projection owns final grouping.
  - Add a `rows(from:)` or equivalent row-normalization API as the canonical Dock path.
  - Do not let Dock's new projection depend on `sections(from:)` as the final grouping source.
- `CodexDock/State/ArchiveStore.swift` and `CodexDock/Features/Archive/ArchiveView.swift`
  - Preserve archive grouping separately from Dock's activity-first projection.
  - If `SessionRowProjector.sections(from:)` currently serves archive rows, either keep it as an archive-only helper or rename/split it to an `ArchiveSessionProjector.sections(from:)` path before Dock removes section ownership.
  - Add or update archive tests if the section helper split touches archive behavior.

## 6.7 Host configuration and display names

- `CodexDock/Configuration/DockHostConfiguration.swift`
  - Add display resolver helper.
  - Keep endpoint parsing and `webSocketURL` untouched.
  - Change `DockHostConfiguration.displayName` to resolver output.
  - Preserve `DockRelayEndpoint.displayEndpoint` for endpoint diagnostics.
- `CodexDock/State/HostSettingsStore.swift` and `CodexDock/Features/Hosts/HostsView.swift`
  - Relay settings rows use `DockHostViewModel.displayName` or the same resolver output as the row title.
  - Relay settings rows use `DockHostViewModel.endpoint` / `DockRelayEndpoint.displayEndpoint` as the visible detail line.
  - Tests must prove settings still show the endpoint detail after the title changes to a short host name.
- Cross-surface display rule:
  - `DockHostViewModel.displayName` is the user-facing title in Dock, Archive host summaries, thread detail headers, connectivity labels, and Relay settings row titles.
  - `DockHostViewModel.endpoint` and `DockRelayEndpoint.displayEndpoint` are the visible detail/diagnostic strings in Relay settings, accessibility values where useful, diagnostics, and logs.
  - Archive host summaries and thread detail headers use short display name.
  - Connectivity chip/host snapshots use short display name for user-facing labels and retain endpoint in accessibility/log detail where appropriate.
- Add tests for:
  - `amir-m5.fairy-salmon.ts.net:4510` -> `Amir-M5`
  - `home.fairy-salmon.ts.net:4510` -> `Home`
  - `Amir-M5.local:4510` -> `Amir-M5`
  - `192.168.50.74:4510` -> `192.168.50.74`

## 6.8 Connectivity

- `CodexDock/State/AppConnectivityStore.swift`
  - Update `reportDockState` for multi-host `.idle`/`.loading`.
  - Update rollup display behavior or add a display label that can say `Online 2/2` and `Online 1/2`.
  - Preserve detailed message for accessibility.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - Use compact host-count label.
  - Keep system images/colors behavior.
  - Keep `AutomationID.Connectivity.globalIndicator`.

## 6.9 Automation IDs and accessibility

- `CodexDock/Automation/AutomationID.swift`
  - Add IDs for lens picker, lens values, filters button, filter surface, active filter summary, filter chips, clear filter/search buttons, host groups, host toggles, branch groups, branch toggles, loading host rows, host retry buttons, and host Relay settings buttons.
  - Remove tests that require old filter tab IDs.
  - Delete old Dock filter/sort/idle IDs after primary UI removal, unless a surviving non-primary owner is explicitly named in the test.

## 6.10 Tests

- `CodexDockTests/DockStoreTestsProjection.swift`
  - Replace old branch/newest sort tests with lens projection tests: default newest, recency-beats-status ordering, host lens grouping, branch lens grouping, search values, filter composition, idle hidden count, `Status: Not loaded` only state, filtered empty, and source filter behavior.
  - Add a test where the newest row is `Not loaded` and the older row is `Running`; newest still wins unless the user explicitly filters status.
  - Add a test where an agent row and human row both exist; default `.any` source shows both, and explicit `Human`/`Agents` filters split them.
  - Add a test where branch search finds `feature/dock` by exact, partial, slash, repo plus branch, and host plus branch inputs.
  - Add a test proving branch chip search is local filter-surface option search and `selectedBranches` is the only branch facet state in `DockFilterState`.
- `CodexDockTests/DockStoreTests.swift`
  - Update empty/loading/snapshot tests for no old tabs and multi-host loading.
  - Update status mapping tests for no `.needsMe`.
  - Add loading-state tests proving every configured host is represented.
  - Add single-host total failure and multi-host partial failure tests.
  - Preserve archive action, mapping failure, and scope failure tests.
- `CodexDockTests/DockStoreScopeTests.swift`
  - Update old tabs/scope count expectations to new source filter/facet behavior.
  - Preserve dedupe/conflict behavior.
- `CodexDockTests/AutomationIDTests.swift`
  - Add expected IDs for new Dock controls.
  - Remove old filter-tab expectations if no code references them.
- `CodexDockUITests/CodexDockAutomationSmokeTests.swift`
  - Update in Phase 2 because generated-project tests include `CodexDockUITests`.
  - Replace old sort picker, idle toggle, old `DockTabID`, and old filter-tab usage with new lens/filter automation IDs.
  - Add UI smoke assertions that old primary tabs/sort/idle controls are absent from the first Dock screen after the cutover.
  - Replace the old `.agents` tab navigation with the new source filter path or default `.any` row path.
- `CodexDockTests/ThreadListMappingTests.swift`
  - No change expected unless `SessionSummary` adds `createdAt` or a new row field.
- `CodexDockTests/AppServerClientTests.swift`
  - No change expected because relay/app-server query shape should remain stable.
- Add host display-name tests in `CodexDockTests/DockConfigurationTests.swift`.
- `CodexDockTests/ThreadDetailStoreTestSupport.swift`
  - Update every direct `DockRowViewModel` helper or initializer call when row host fields/status cases change.
  - Prefer one shared test row factory if the initializer surface becomes noisy.
- Archive tests that cover `ArchiveStore`/`ArchiveView`
  - Update only if the `SessionRowProjector.sections(from:)` split touches archive grouping.
  - Preserve archive row grouping and archive action behavior.

## 6.11 Build and project config

- `project.yml`
  - Update only if new Swift files are not automatically included by existing groups/targets.
  - If changed, regenerate with `rtk xcodegen generate --spec project.yml`.
- `Package.swift`
  - Update only if package target source discovery requires explicit entries. Current SwiftPM likely does not.
- `Makefile`
  - No expected change.

## 6.12 Relay, scripts, and Node tests

- `scripts/dock-relay*.mjs`
  - No expected change.
- `package.json`
  - No expected change.
- `rtk npm run test:relay`
  - Not required unless relay files change unexpectedly.

## 6.13 Negative search audit after implementation

The final implementation diff should not leave visible Dock primary UI references to:

- `Limited`
- `Needs me`
- `All 0`
- `Needs me 0`
- `Running 0`
- `Agents 0`
- `Branch` as a primary sort control separate from the lens model.

This is not a substitute for tests, because some strings may remain in history/docs or non-Dock contexts. The implementation review should inspect live code paths and accessibility output.

<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map. Phase boundaries are proof gates, not release promises. Each phase must keep the project compiling, must not add a runtime fallback to the old UX, and must move toward one canonical Dock path. `Checklist (must all be done)` is authoritative inside each phase. `Exit criteria (all required)` is the audit surface.

## Phase 1 - Semantic And Loading Contract Cutover

* Goal:
  Establish the canonical data, projection, and multi-host loading path before rebuilding the visible UI. This phase proves the highest-risk seam: real `SessionSummary` rows become self-contained Dock rows, one projection owner turns rows into newest/host/branch/filter results, and the store can publish one loaded host while another configured host is still checking, all without `Needs me`, `Limited`, old tab counts, or status-based default ranking.

* Work:
  This is a model, store-state, and test phase. It may leave the old SwiftUI screen visually intact while the new projection/loading contract compiles and is tested, but it must not create a second final source of truth. Any temporary coexistence is only source-level sequencing inside the implementation branch; the final Dock path remains the new projection and all-host loading model.

* Checklist (must all be done):
  - Add `DockLensID` with exactly `newest`, `host`, and `branch`.
  - Add `DockSortOrder.newestActivity` as the only V1 sort order.
  - Add `DockSourceFilter` with `any`, `human`, `agents`, and `unknown`.
  - Add `DockFilterState.default` with host any, no selected branches, status any including `Not loaded`, repo any, source any, idle hidden, and sort order `newestActivity`.
  - Keep branch chip search as local `DockFilterSurfaceView` state only; do not add chip-search text to `DockFilterState`.
  - Use `DockFilterState.statusKinds` as the only V1 owner for `Not loaded` filtering.
  - Do not add a separate not-loaded mode enum or visibility result filter in V1.
  - Stop emitting `.needsMe` from every new row/projection path.
  - Rename `DockRowStatusKind.failed` to `.error` and update all switch statements/tests that referenced `.failed`.
  - Ensure the visible status labels are exactly `Running`, `Idle`, `Not loaded`, `Error`, and `Unknown`.
  - Change `SessionRowProjector.status(for:)` so all `.active(activeFlags:)` rows map to `.running`.
  - Preserve `.notLoaded`, `.idle`, `.systemError`/`Error`, and `.unknown` mappings.
  - Add deterministic host display-name derivation in the host configuration/model path.
  - Change `DockHostConfiguration.displayName` to use the shared short-name resolver.
  - Ensure `DockHostViewModel.displayName` uses the short display-name resolver.
  - Preserve endpoint strings in `DockHostViewModel.endpoint`.
  - Ensure Dock rows/groups/loading/failure UI, Archive host summaries/rows, Thread detail headers, and connectivity host labels consume the shared short display-name path.
  - Ensure Relay settings rows preserve endpoint strings as the visible detail line through `DockRelayEndpoint.displayEndpoint`.
  - Add `hostDisplayName` and `hostEndpoint` to `DockRowViewModel`.
  - Populate row host fields in `SessionRowProjector`.
  - Ensure row title fallback uses non-empty `summary.displayTitle`, then a stable visible thread id or short thread-id fragment, so `Not loaded` rows still have usable row identity.
  - Preserve `DockRowViewModel.metadataKey`.
  - Add a canonical base-row path to `DockSnapshot` so projection can consume rows without relying on old branch-pre-grouped sections as the final grouping source.
  - Add `SessionRowProjector.rows(from:)` or an equivalent canonical Dock row-normalization API.
  - Preserve archive grouping by keeping `SessionRowProjector.sections(from:)` archive-only or splitting it to an `ArchiveSessionProjector.sections(from:)` path before Dock removes section ownership.
  - Add host-state/checking metadata to `DockSnapshot` so projection and UI can distinguish fully loaded, partially loaded, checking, offline, and error host states.
  - Leave existing `DockSnapshot.tabs` only as legacy compile support until Phase 2 removes the old UI; do not use it in the new projection path.
  - Change `DockStoreState.idle` and `.loading` to carry all configured hosts.
  - Update `DockStore` initializers and `updateRegistry` for all-host idle/loading state.
  - Update `DockStore.reload(showLoading:)` to publish all-host loading before network work.
  - Change host loading aggregation so completed host outcomes can publish before every configured host finishes.
  - Publish a partial snapshot when at least one host has completed and at least one configured host is still checking.
  - Preserve loaded rows, host states, scope failures, conflicts, and mapping failures across partial snapshot updates.
  - Update `AppConnectivityStore.reportDockState` for all-host idle/loading state.
  - Implement `DockProjectionOptions(lens:searchText:filters:)`; sort comes from `filters.sortOrder`.
  - Implement `DockProjection` with rows, groups, active summary, result count, hidden counts, available facets, and empty reason.
  - Implement case-insensitive projection search over title, host display name, host id, repository, branch, summary, status label, local label, source/origin, and thread id.
  - Implement host filter, selected-branches filter, status filter including `Not loaded`, repo query/selection filter, source filter, and idle visibility.
  - Implement newest lens as flat rows ordered by `lastActivityDate` descending, then title, then `hostID::threadID`.
  - Implement host lens groups sorted by newest visible row, with rows sorted newest-first.
  - Implement branch lens groups sorted by newest visible row, with rows sorted newest-first and host display names preserved in rows.
  - Ensure no default projection path uses status priority before recency.
  - Compute hidden idle count and visible result count from the same filtered row set the UI will render.
  - Compute a partial-result flag/count when any configured host is still checking.
  - Compute available host, branch, status, repo, and source facets from loaded rows.
  - Model empty reasons for no data, no search matches, no filter matches, idle hidden, status filter selected only `Not loaded`, and host/scope unavailable.
  - Update projection unit tests for all three lenses.
  - Update tests proving `Needs me` is not emitted by row status projection.
  - Update tests proving `Not loaded` remains neutral and can be filtered by selecting only `Not loaded` in the status filter.
  - Update tests proving there is no separate not-loaded result-filter owner.
  - Add tests proving row title fallback for not-loaded rows uses a stable thread id or short thread-id fragment when display title is empty.
  - Update tests proving newest recency beats status.
  - Update tests proving host display-name derivation.
  - Put host display-name resolver tests in `CodexDockTests/DockConfigurationTests.swift`.
  - Update tests proving source `.any`, `.human`, and `.agents` behavior.
  - Update tests proving search matches host display name, branch, repo, status, label, summary, and thread id.
  - Update tests proving search and branch lookup are case-insensitive.
  - Add tests for all-host idle/loading state.
  - Add tests for mixed loaded-plus-checking publication.
  - Add tests proving projection works over the currently loaded subset while another host is still checking.
  - Add tests for partial visible result counts.
  - Add tests for connectivity rollup labels/messages that depend on all-host loading state.
  - Update `CodexDockTests/ThreadDetailStoreTestSupport.swift` and any row test factories for the new `DockRowViewModel` initializer fields.
  - Update archive tests if the row/section projector split touches `ArchiveStore` or `ArchiveView`.

* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests`.
  - Run `rtk swift test --filter DockConfigurationTests`.
  - Run `rtk swift test --filter AppConnectivityStoreTests`.

* Docs/comments (propagation; only if needed):
  - Add short code comments only at non-obvious boundaries: host display-name derivation and projection ordering/filter composition.
  - Do not update user-facing README yet unless old docs become false for code that is already visible after this phase.

* Exit criteria (all required):
  - `rtk swift test --filter DockStoreTests` passes and is the compile proof for this phase.
  - `rtk swift test --filter DockConfigurationTests` passes.
  - `rtk swift test --filter AppConnectivityStoreTests` passes.
  - Projection tests cover newest, host, branch, search, filters, source, idle, `Status: Not loaded`, and deterministic tie-breakers.
  - Branch chip search is not stored in `DockFilterState`; global branch search is `searchText`.
  - Search and branch lookup are case-insensitive.
  - Initial loading state can represent every configured host.
  - Loaded host rows can appear in store/projection state while another configured host is still checking.
  - Partial result count/state is available before the visible UI consumes it.
  - No new projection or row-model test expects `Needs me`.
  - Any remaining `.needsMe` enum/call-site references are old compile support only and are explicitly scheduled for deletion in Phase 2.
  - No projection output includes old tab models as the authoritative result.
  - Host display names for `amir-m5.fairy-salmon.ts.net`, `home.fairy-salmon.ts.net`, `Amir-M5.local`, and `192.168.50.74` match Section 6.7.
  - Dock rows/groups/loading/failure UI, Archive host summaries/rows, Thread detail headers, and connectivity host labels all use the shared short display-name path.
  - Relay settings still show endpoint strings as visible detail text.
  - `SessionStatus.active(activeFlags:)` maps to visible `Running`.
  - Archive grouping has an explicit owner separate from Dock's activity-first projection.
  - Empty-title/not-loaded rows still expose stable visible row identity.

* Rollback:
  Revert the Phase 1 model/projection/test edits as a unit. Because no runtime fallback or persistence migration is introduced, rollback is source-only.

## Phase 2 - Dock First Screen Cutover: Header, Newest Rows, Lazy List

* Goal:
  Replace the visible default Dock screen with the activity-first shell: compact header, full-width search, internal lenses, visible filter summary, newest-first row list, host identity on rows, and no old primary tabs/sort row.

* Work:
  This phase turns the projection contract into the first real visible path. It should make first app open materially correct even before the full filter surface and all host/branch polish are complete.

* Checklist (must all be done):
  - Replace `DockView` local state `selectedTab`, `sortMode`, and standalone `showsIdle`.
  - Add `selectedLens = .newest`, `searchText`, `filterState`, `isFilterSurfacePresented`, `collapsedHostGroupIDs`, and `collapsedBranchGroupIDs`.
  - Replace `controls` with a header stack containing title, compact connectivity, full-width search, lens controls, and active filter summary.
  - Remove the primary `All`/`Needs me`/`Running`/`Agents` segmented picker from Dock UI.
  - Remove the old visible `Branch`/`Newest` sort segmented control from Dock UI.
  - Delete remaining `DockTabID` and `DockTabViewModel` usage from primary Dock.
  - Delete `DockRowStatusKind.needsMe` and update all switch statements, colors, tests, previews, and old tab predicates that referenced it.
  - Remove `DockSnapshot.tabs` once old tab usage is gone.
  - Delete unused old Dock filter/sort/idle automation IDs after the UI no longer references them, or document the surviving non-primary owner in code comments and tests.
  - Remove the standalone old `Idle` button and represent idle visibility in the active filter summary and later filter surface.
  - Remove the large Dock-header add-host button from the Dock first screen; host management remains in `Relay`.
  - Render default `Newest` projection as the first loaded content after controls.
  - Do not render a visible `NEWEST` section header in the default feed unless implementation proves it improves accessibility or scanability without wasting vertical space.
  - Do not render pinned `HostSummaryView` blocks before default newest rows.
  - Render row content through `LazyVStack`.
  - Update `DockRowView` to show host display name when more than one host exists.
  - Update `DockRowView` metadata line to include host/repo/branch for multi-host rows.
  - Keep title, status chip, summary, last activity, local label, rail color, row navigation, and context menu behavior.
  - Ensure `Not loaded` status chip is visually neutral.
  - Remove visible/accessibility `Needs me` from Dock rows, empty states, and header controls.
  - Remove visible/accessibility `Limited` from Dock rows and states.
  - Update `dockScreenValue` to expose state, lens, result count, search, and filter summary.
  - Update `AutomationID.Dock` with IDs for lens picker, lens buttons, filter button, active filter summary, and clear search/filters affordances used in this phase.
  - Update `AutomationIDTests` for new IDs.
  - Update `CodexDockUITests/CodexDockAutomationSmokeTests.swift` in the same cutover:
    - replace `AutomationID.Dock.sortPicker` and `AutomationID.Dock.idleToggle` assertions with new lens/filter/header assertions,
    - remove `DockTabID` usage and old filter-tab helper usage,
    - assert old primary tab/sort/idle controls are absent,
    - replace `.agents` tab navigation with the new source filter path or default `.any` row path,
    - assert default `Newest`, full-width search, row host identity when rows exist, and absence of primary `Needs me`/`Limited`.
  - Update Dock preview data so it does not include `preview-needs-me`.
  - Keep row archive, mark/clear label, and color actions working.

* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests` as supporting model/store proof.
  - Run `rtk swift test --filter AutomationIDTests` as supporting automation-ID proof.
  - Run `rtk make app-test SIM='iPhone 17'` after updating `CodexDockUITests/CodexDockAutomationSmokeTests.swift`; this is the primary blocking proof for the visible cutover.
  - If `rtk make app-test SIM='iPhone 17'` fails because required UI state is not observable in the simulator, add the missing accessibility IDs, accessibility values, UI-test hooks, or log/accessibility exposure in this phase and rerun app-test.
  - If `rtk make app-test SIM='iPhone 17'` cannot run because of an external simulator/Xcode/signing/service infrastructure failure, record the exact command and exact blocker. Do not mark Phase 2 complete from unit tests or launch-only proof.

* Docs/comments (propagation; only if needed):
  - No README update required until filters/lenses are complete enough to document fully, unless old docs directly contradict the app after this phase.

* Exit criteria (all required):
  - First Dock loaded state no longer has old primary tabs.
  - First Dock loaded state no longer has the old `Branch`/`Newest` sort picker.
  - Default selected lens is `Newest`.
  - Default active summary shows host scope, branch scope, idle visibility, and visible result count.
  - Rows appear before any host status blocks in default loaded state.
  - Rows show host identity when more than one host exists.
  - Row navigation and row actions still compile and tests for archive/metadata still pass.
  - The list renderer is lazy for row/group content.
  - There is no primary visible `Needs me` or `Limited` in the changed Dock UI path.
  - Old primary tab IDs and old sort picker IDs are not used by the primary Dock UI.
  - `CodexDockUITests/CodexDockAutomationSmokeTests.swift` no longer imports or drives `DockTabID`, old Dock filter tabs, old sort picker, or old idle toggle.
  - `rtk make app-test SIM='iPhone 17'` passes and proves the visible cutover in the simulator.
  - Missing simulator-observable hooks have been added before exit; no required behavior is left "unit-tested only."

* Rollback:
  Revert the Dock view/header/row rendering edits and associated tests. Phase 1 projection changes can remain if Phase 2 is rolled back independently during implementation.

## Phase 3 - Host And Branch Lenses: Grouping, Expansion, Local Failures

* Goal:
  Make `Host` and `Branch` first-class lenses instead of old sort modes. Host mode answers what is happening by machine; Branch mode answers where branch work lives across hosts.

* Work:
  This phase expands the visible UI along the lens axis using the projection model already proven in Phase 1 and the header/list shell from Phase 2.

* Checklist (must all be done):
  - Wire `DockLensPicker` so `Newest`, `Host`, and `Branch` are selectable and accessibly selected.
  - Render host lens groups from `DockProjection.groups`.
  - Render branch lens groups from `DockProjection.groups`.
  - Add compact host group headers with short display name, connection state when known, visible count, newest visible activity, running count when `Running` rows are visible, hidden idle indicator when relevant, and expand/collapse control.
  - Add compact branch group headers with branch name, visible count, newest visible activity, host display names present in group, and expand/collapse control.
  - Ensure host headers use short display names and do not use endpoint strings as primary labels.
  - Ensure branch rows show host display name.
  - Ensure rows inside host and branch groups sort newest-first.
  - Ensure host groups and branch groups sort by newest visible row.
  - Implement expansion/collapse local state using stable group IDs.
  - Ensure tapping expand/collapse is separate from filtering.
  - Ensure any host filter affordance is explicit and not ambiguous with expand/collapse.
  - Render offline/error/partial host state locally in host groups when snapshot host states include failures.
  - Keep offline/error hosts visible in Host lens even when they have no visible rows.
  - Collapse offline/error host groups by default when they have no visible rows, while leaving their status, Retry, and Relay settings actions accessible.
  - Keep online host rows usable when another host has a failure.
  - In Newest lens, render a compact failed-host row in the feed without hiding online rows.
  - In Branch lens, keep loaded branch groups visible and render compact failed-host context so search/filter results do not look complete when a host failed.
  - Add Retry action to host failure UI, calling `store.refresh()` in V1.
  - Add Relay settings action to host failure UI through `onOpenRelaySettings`.
  - Add automation IDs for host groups, host toggles, branch groups, branch toggles, retry, and Relay settings actions.
  - Update `AutomationIDTests` for host group, host toggle, branch group, branch toggle, retry, and Relay settings action IDs.
  - Add tests proving host lens grouping, branch lens grouping, group ordering, row ordering, and failure attachment.
  - Add tests proving host running counts and lens-specific failed-host placement.

* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests`.
  - Run `rtk swift test --filter AutomationIDTests`.

* Docs/comments (propagation; only if needed):
  - Add a brief comment only if group ID stability or host-failure placement is not obvious from code.

* Exit criteria (all required):
  - Selecting `Host` renders host groups from `DockProjection.groups`.
  - Selecting `Branch` renders branch groups from `DockProjection.groups`.
  - `Newest`, `Host`, and `Branch` each expose accessible selected state.
  - Host and Branch lenses preserve newest ordering within rows/groups.
  - Host and Branch lenses preserve row host identity.
  - Host group headers show visible running count when at least one visible row is `Running`.
  - Host groups are visually and accessibly distinguishable from rows.
  - Branch groups are visually and accessibly distinguishable from rows.
  - Host and branch group expansion state is visible/accessibility-exposed.
  - Rows remain self-contained with host/repo/branch/status/time.
  - Offline or error host state attaches to the affected host and does not hide online host rows.
  - Offline or error hosts with no visible rows remain visible and collapsed by default in Host lens.
  - Newest lens shows a compact failed-host row while preserving online newest rows.
  - Branch lens shows failed-host context when branch/search/filter results may be partial.
  - No host group or branch group uses raw endpoint strings as primary labels.
  - No Host/Branch lens UI shows `Needs me` or `Limited`.

* Rollback:
  Revert host/branch lens rendering and related tests. The default newest UI from Phase 2 remains usable because it does not depend on expanded group rendering.

## Phase 4 - Filters, Search States, Empty States, Not-Loaded Explanation

* Goal:
  Complete explicit narrowing for the huge Dock list: one shared filter surface, visible active-filter summary, branch lookup, source/status/repo/host facets, idle visibility, `Not loaded` status filtering, and honest empty recovery.

* Work:
  This phase expands along the filter/search axis. It intentionally does not add archive visibility to Dock because archived sessions are not in Dock's result set in V1.

* Checklist (must all be done):
  - Implement `DockFilterSurfaceView` as the in-Dock filter surface.
  - Make the header `Filters` control and any filter icon/button open the same surface/state.
  - Ensure `Filters` selected state reflects `isFilterSurfacePresented` and its active badge/count reflects non-default filters.
  - Keep full-width global search visible above or inside the filter context.
  - Render visible result summary, for example `1,178 shown`.
  - Render host filter with `Any` and each configured host by short display name.
  - Render branch filter with local chip search and selectable branch chips/results.
  - Keep branch chip search local to `DockFilterSurfaceView`; selecting branch chips updates only `DockFilterState.selectedBranches`.
  - Render status filter with `Any`, `Running`, `Idle`, `Not loaded`, `Error` when present, and `Unknown` when present.
  - Do not render `Needs me` as a filter.
  - Render repo/working-directory filter with `Any` and available repos/workdirs.
  - Render source filter with `Any`, `Human`, `Agents`, and `Unknown` when present.
  - Render idle visibility control.
  - Keep `Not loaded` available as a status filter.
  - Support not-loaded-only results by selecting only `Not loaded` in the status filter.
  - Do not render a separate three-way not-loaded visibility control in V1.
  - Do not render archive visibility in Dock V1.
  - Display an explicit not-applicable requirement note in implementation review docs/checklist: archive visibility is excluded because archived sessions cannot appear in Dock results in this plan.
  - Render sort as `Newest activity` only.
  - Implement immediate filter application.
  - Provide `Clear filters`; do not show an inactive/misleading Apply button.
  - Ensure filters compose with search and selected lens.
  - Ensure global search supports case-insensitive branch lookup by exact, partial, slash branch names, repo plus branch, and host plus branch.
  - Ensure local branch chip search finds exact, partial, and slash branch names without changing visible rows until a chip is selected.
  - Ensure active filter summary outside the surface reflects host, branch, status including `Not loaded`, repo/source, idle, search, and visible result count.
  - Ensure active filter summary shows host scope, branch scope, idle visibility, and visible result count even at default filters.
  - Implement clear search without clearing filters.
  - Implement clear filters without clearing search unless the control explicitly says it clears both.
  - Implement filtered empty state with active constraints and clear actions.
  - Implement not-loaded-only explanation copy exactly as `These sessions exist in the list, but Dock does not have loaded thread detail for them.`
  - Add automation IDs for filter surface controls, chips, clear actions, empty state, and not-loaded explanation.
  - Update `AutomationIDTests` for filter surface controls, chips, clear actions, empty state, and not-loaded explanation IDs.
  - Add tests for filter composition, active summary, clear behavior, global branch search, local branch chip search, filtered empty, and not-loaded-only explanation.
  - Add a short code comment near `DockFilterState.default` explaining why source defaults to `.any` and archive visibility is absent from Dock V1.

* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests`.
  - Run `rtk swift test --filter AutomationIDTests`.

* Docs/comments (propagation; only if needed):
  - No additional docs/comments beyond the required `DockFilterState.default` comment in the checklist.

* Exit criteria (all required):
  - There is exactly one Dock filter model.
  - Header filter entry and `Filters` entry share state.
  - Search composes with all filters and lenses.
  - Search and branch lookup are case-insensitive.
  - Active filter summary always exposes host scope, branch scope, idle visibility, visible result count, and every non-default filter.
  - Clear search and clear filters behave differently when both are active.
  - Filter surface contains host, branch, status, repo/workdir, source, idle visibility, and sort controls.
  - Status filter includes `Not loaded`.
  - Selecting only `Not loaded` in the status filter is the only V1 not-loaded-only path.
  - There is no separate not-loaded visibility control in V1.
  - Filter surface does not contain `Needs me`, `Limited`, or fake archive visibility.
  - Empty states explain the active constraints that caused emptiness.
  - Not-loaded-only results explain what `Not loaded` means without rate-limit language.

* Rollback:
  Revert filter surface and filter-state UI wiring. Lenses and default newest UI remain functional with default filters.

## Phase 5 - Host Failure Actions And Connectivity Polish

* Goal:
  Finish host-local failure behavior and connectivity presentation on top of the all-host loading contract established in Phase 1. Failures should be local and actionable; connectivity should summarize host counts compactly.

* Work:
  This phase expands along the host-state and failure-action axis after the first-screen UI, lenses, and filters already consume the all-host/partial-loading state model.

* Checklist (must all be done):
  - Render all-host loading state using the Phase 1 all-host loading model.
  - Render mixed loaded-plus-checking state using the Phase 1 partial snapshot model: loaded host rows/groups appear while unfinished hosts remain visible as checking/loading host rows.
  - Ensure loading rows use short display names and checking/loading status.
  - Ensure loading state keeps Dock title, search, lens controls, active filter summary, and app bottom tabs stable.
  - Ensure loading state does not show old zero-count primary tabs.
  - Ensure loading state includes neutral copy such as `Sessions not loaded yet` and `Waiting for relay response`.
  - Use per-host loading rows instead of fake session skeleton rows in V1; do not render placeholder session content that could be mistaken for real threads.
  - Preserve search, lens, and filter behavior over the currently loaded subset while unfinished hosts are still checking.
  - Mark visible result count as partial while any configured host is still checking.
  - Update single-host total failure rendering to keep existing clear full-screen behavior.
  - Update multi-host partial/total failure rendering to show host-local failure rows/groups, not a global mystery state.
  - Add Retry action to every host failure UI.
  - Add Relay settings action to every host failure UI.
  - Update `GlobalConnectivityIndicatorView` label path to show compact host count status.
  - Preserve detailed accessibility value for failure messages.
  - Add tests for loading UI rendering from all-host state, mixed loaded-plus-checking UI rendering, connectivity rollup labels/messages, single-host complete failure, multi-host partial failure, and retry/Relay settings accessibility IDs.

* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests`.
  - Run `rtk swift test --filter AppConnectivityStoreTests`.

* Docs/comments (propagation; only if needed):
  - Add code comments only if multi-host total failure behavior is not obvious.

* Exit criteria (all required):
  - Visible loading UI represents every configured host from Phase 1 all-host loading state.
  - Visible UI shows loaded host rows while another configured host is still checking.
  - Visible result count indicates partial data while any host is still checking.
  - Loading UI does not show `All 0`, `Needs me 0`, `Running 0`, or `Agents 0`.
  - Loading UI uses host loading rows and neutral copy, not fake session skeleton content.
  - Connectivity can display compact host-count state.
  - One failed host does not clear online rows.
  - Host failure UI names the short host display name, shows explicit status/copy, and exposes Retry plus Relay settings.
  - Host failure UI does not use `Not loaded` for transport failures.
  - No loading/failure state shows `Limited` or primary `Needs me`.

* Rollback:
  Revert state-shape/connectivity/loading changes together. Because this phase changes published state shape, rollback must include all call sites that switch over `DockStoreState`.

## Phase 6 - Documentation, Final Verification, Simulator Proof

* Goal:
  Remove stale live documentation, verify the implementation against the spec package, and produce primary simulator proof on `iPhone 17` using the repo-owned commands.

* Work:
  This phase is not a dumping ground for unfinished implementation. It only closes docs, tests, and runtime proof after Phases 1-5 have completed.

* Checklist (must all be done):
  - Update `README.md` Dock UI/control documentation to describe `Newest`, `Host`, `Branch`, `Filters`, full-width search, active filters, source filtering, idle visibility, not-loaded status, and compact host connectivity.
  - Remove stale README claims that Dock has primary `All`, `Needs me`, `Running`, `Agents`, or a separate `Branch`/`Newest` sort control.
  - Ensure docs do not imply Dock connects directly to raw `:4500`.
  - Ensure docs do not imply rate limiting for `Not loaded`.
  - Run `rtk swift test --filter DockStoreTests`.
  - Run `rtk swift test --filter DockConfigurationTests`.
  - Run `rtk swift test --filter AppConnectivityStoreTests`.
  - Run `rtk swift test --filter AutomationIDTests`.
  - Run `rtk swift test --filter AppServerClientTests` only if AppServer DTO/client code changed.
  - Run `rtk npm run test:relay` only if relay scripts changed.
  - Run `rtk xcodegen generate --spec project.yml` if `project.yml` changed.
  - Run `rtk make app-test SIM='iPhone 17'` for generated app target UI behavior. This is mandatory final proof, not a nice-to-have.
  - Use simulator accessibility/log proof to confirm default selected `Newest`, full-width search, no old primary tabs, rows with host, no visible/accessibility `Limited`, and no primary visible/accessibility `Needs me`.
  - If simulator accessibility/log proof cannot assert any required behavior because the app lacks hooks, add the required accessibility IDs, accessibility values, UI-test hooks, or log/accessibility exposure and rerun `rtk make app-test SIM='iPhone 17'`.
  - If `rtk make app-test SIM='iPhone 17'` cannot run because of an external simulator/Xcode/signing/service infrastructure failure, record the exact command and exact blocker. The implementation remains unproven and must not be marked complete until simulator proof runs.
  - `rtk make app SIM='iPhone 17'` may be used only as a diagnostic launch command while repairing simulator proof; it is not a substitute for `rtk make app-test SIM='iPhone 17'`.
  - Do not use physical Mobile MCP if it reports `WebDriverAgent is not running on device`; record that exact blocker and leave physical manual test to Amir.
  - Update and verify `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md` against every global requirement and screen requirement in the mockup package: each in-scope `MUST` is satisfied, and each not-applicable/out-of-V1 requirement is named with its Decision Log entry.
  - Confirm `Archive` app tab still works if Dock archive action or docs changed.
  - Confirm `Relay` app tab still works if `onOpenRelaySettings` changed root navigation.

* Verification (required proof):
  - Required primary UI proof: `rtk make app-test SIM='iPhone 17'`.
  - Required supporting baseline: `rtk swift test --filter DockStoreTests`.
  - Required supporting host config proof: `rtk swift test --filter DockConfigurationTests`.
  - Required supporting connectivity proof: `rtk swift test --filter AppConnectivityStoreTests`.
  - Required supporting automation ID proof: `rtk swift test --filter AutomationIDTests`.
  - Conditional proof: `rtk swift test --filter AppServerClientTests`, `rtk npm run test:relay`, and `rtk xcodegen generate --spec project.yml` only when their owned files changed.

* Docs/comments (propagation; only if needed):
  - `README.md` is required in this phase.
  - No new implementation doc should replace the mockup README or this architecture plan as source of truth.

* Exit criteria (all required):
  - `README.md` matches the implemented Dock UX.
  - Required simulator app-test proof passes.
  - Supporting tests pass.
  - Simulator proof explicitly confirms default `Newest`, full-width search, no old primary tabs, rows with host, no visible/accessibility `Limited`, and no primary visible/accessibility `Needs me`.
  - No required behavior is left unverifiable in the simulator because of missing hooks.
  - Primary Dock UI has no visible/accessibility `Limited`.
  - Primary Dock UI has no primary visible/accessibility `Needs me`.
  - Default Dock opens to `Newest`.
  - Host lens renders grouped rows with local failure state, newest ordering, expansion/collapse, short host names, and accessible selected state.
  - Branch lens renders branch groups with host identity, newest ordering, expansion/collapse, and accessible selected state.
  - Filter surface shares `DockFilterState` with the header filter entry, applies immediately, composes with search/lens, exposes active summary and result count, supports clear search separately from clear filters, and contains required facets.
  - Every in-scope mockup `MUST` requirement is satisfied; every not-applicable or out-of-V1 requirement is named in the requirement disposition sidecar and has a matching Decision Log entry.
  - Loading state names all configured hosts.
  - Partial host failure leaves online rows usable.
  - Relay settings path from failure UI opens the existing `Relay` tab.

* Rollback:
  Revert final docs and verification-only code touchups. If final verification exposes a behavioral regression, roll back the responsible phase edits rather than adding a fallback path.

<!-- arch_skill:block:phase_plan:end -->

# 8) Simulator-First Verification Strategy (blocking)

Simulator proof is the primary completion gate for user-visible Dock work. Unit tests are supporting checks for internal logic; they cannot complete or approve a phase that changes the Dock UI, accessibility output, loading behavior, filters, lenses, or row rendering.

Verification is layered by risk and ownership, but the layer that matters most is the installed simulator UI. Use the smallest meaningful supporting check while implementing, then prove the real surface with `rtk make app-test SIM='iPhone 17'`.

Required checks by touched area:

- Dock projection, row model, host display names, loading state, host failure state, filter state, active summary, and store behavior:
  - `rtk swift test --filter DockStoreTests`
- Host display-name resolver and host configuration behavior:
  - `rtk swift test --filter DockConfigurationTests`
- Connectivity rollup labels/messages and host-count state:
  - `rtk swift test --filter AppConnectivityStoreTests`
- Automation identifiers:
  - `rtk swift test --filter AutomationIDTests`
- App-server DTO, JSON-RPC, session mapping, or `AppServerDockClient` request behavior:
  - `rtk swift test --filter AppServerClientTests`
- Thread detail, live events, composer, voice transcript, or request-card response behavior:
  - `rtk swift test --filter ThreadDetailStoreTests`
  - Not expected for this plan.
- Relay scripts under `scripts/dock-relay*.mjs`:
  - `rtk npm run test:relay`
  - Not expected for this plan.
- Generated project config, target settings, app permissions, Info.plist, assets, or added source wiring requiring `project.yml`:
  - `rtk xcodegen generate --spec project.yml`
  - `rtk make app-test SIM='iPhone 17'`
- Installed UI behavior on simulator:
  - `rtk make app-test SIM='iPhone 17'`
  - If app-test cannot assert required UI state because the app lacks hooks, add the missing accessibility IDs, accessibility values, UI-test hooks, or log/accessibility exposure and rerun app-test.
  - If app-test is blocked by external simulator/Xcode/signing/service infrastructure, record the exact command and exact blocker. Do not treat `rtk make app SIM='iPhone 17'`, unit tests, screenshots, or grep as completion proof.
  - `rtk make app SIM='iPhone 17'` is diagnostic only; it may help debug launch, but it does not satisfy installed UI behavior proof.
- Physical device behavior:
  - Use `rtk make iphone-17-pro`, `rtk make iphone-14`, or the documented device targets only when the task explicitly requires physical install proof.
  - If physical Mobile MCP reports `WebDriverAgent is not running on device`, stop physical Mobile MCP retries and record that exact blocker.

Behavior evidence to collect or assert:

- Default selected lens is `Newest`.
- Search is full-width or equivalent system placement on iPhone.
- Old primary tabs are absent.
- Old separate Branch/Newest sort control is absent.
- `Limited` is absent from primary Dock visible/accessibility output.
- Primary `Needs me` is absent from Dock visible/accessibility output.
- Rows include host display names when multiple hosts are configured.
- Host/Branch lenses preserve host identity and newest ordering.
- Filter state is shared between header entry and filter surface.
- Clear search and clear filters are distinct.
- Loading names all configured hosts.
- One host failure leaves online rows visible and usable.
- Retry and Relay settings actions are visible/accessibility-exposed on host failure UI.
- Archive action still refreshes Archive on success.

What not to use as proof:

- Preview rows.
- Raw loopback `127.0.0.1:4500` app-server paths.
- Unit tests alone for any user-visible Dock behavior.
- Launch-only simulator proof without UI/accessibility/log assertions.
- Screenshots alone when accessibility/state tests can prove the behavior more directly.
- Keyword-only grep as a substitute for tests or accessibility proof. Grep can help review killed terms, but it cannot prove runtime behavior.

# 9) Rollout / Ops / Telemetry

Rollout posture:

- Clean cutover in the local app code. No runtime feature flag, hidden old tabs, old sort control, or compatibility shim.
- Relay and app-server contracts are preserved.
- Archive remains a separate app tab.
- Endpoint persistence remains unchanged.
- Host display-name derivation is deterministic and reversible because endpoint remains stored and logged as before.

Operational behavior:

- Existing Dock reload and app-server client logs remain the operational source for load duration, host count, row count, mapping failures, scope failures, conflicts, and errors.
- Do not log secrets, bearer tokens, `OPENAI_API_KEY`, prompts, transcripts, full JSON-RPC payloads, raw audio, or base64 audio.
- New diagnostics should use `DockLog`, not direct console prints.
- Connectivity logs should continue to redact or summarize host messages as existing code does.

Telemetry and logging additions, if needed:

- It is acceptable to add structured log fields for selected lens, visible row count, host count, and filter activity only if they do not include prompt/session content.
- Do not log search text, branch query text, repo query text, or thread summaries unless existing logging policy explicitly allows them. Treat them as user content.
- If logging selected lens/filter state, use coarse booleans or counts such as `has_search=true`, `host_filter_count=1`, `status_filter_count=2`, and `visible_rows=1178`.

Rollback and recovery:

- Because there is no persistence migration, rollback is source-level.
- If host display names are wrong, endpoint strings remain available in Relay settings and logs for diagnosis.
- If simulator UI proof is blocked by services, Xcode, or simulator state, record the exact command and exact blocker. Do not substitute raw platform install commands, unit tests, launch-only checks, or screenshots as completion proof.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, planning receipts, current/target architecture, call-site audit, authoritative phase plan, verification, rollout, and decision log.
  - Mockup requirement package alignment, especially archive visibility, partial loading, host display names, not-loaded filtering, filter application mode, old-status deletion, automation IDs, and test-owner commands.
- Findings summary:
  - Initial cold-read findings found unresolved partial-loading scope, ambiguous archive-visibility disposition, host display-name owner drift, not-loaded UI ambiguity, inconsistent expansion-state naming, vague exit criteria, and missing exact test-owner commands.
  - Initial phase plan also left some required obligations only in prose or Docs/comments sections.
- Integrated repairs:
  - Required partial loaded-plus-checking publication and visible partial counts.
  - Marked archive visibility requirements not applicable to Dock V1 because archived sessions remain in `ArchiveStore` and the `Archive` tab.
  - Made `DockHostConfiguration.displayName` and `DockHostViewModel.displayName` use the shared short-name resolver while preserving endpoint detail through `DockRelayEndpoint.displayEndpoint`.
  - Standardized expansion state as `collapsedHostGroupIDs` and `collapsedBranchGroupIDs`.
  - Added `sortOrder` to `DockFilterState` and made immediate filter application the only V1 behavior.
  - Collapsed not-loaded filtering to the status filter: status `Any` includes `Not loaded`, and not-loaded-only is `Status: Not loaded`.
  - Made global `searchText` the first-screen branch search; branch chip search inside filters is local option search only.
  - Split Dock row normalization from Archive grouping so the activity-first projection cannot accidentally rewrite archive behavior.
  - Added the requirement-by-requirement disposition sidecar so every `G-*` and `Sxx-*` ID in the mockup package has a V1 disposition before implementation starts.
  - Made the branch-search presentation decision explicit: preserve selected lens grouping while filtering matched rows.
  - Required case-insensitive search and branch lookup.
  - Decided the default Newest feed does not render a visible `NEWEST` section header unless it improves accessibility/scanability without wasting vertical space.
  - Added Relay settings owner paths for short host titles plus endpoint detail preservation.
  - Required title/thread-id fallback for empty-title not-loaded rows.
  - Required lens-specific failed-host rendering and host running counts.
  - Rejected fake session skeleton rows in favor of per-host loading rows and neutral loading copy.
  - Strengthened verification to simulator-first: `rtk make app-test SIM='iPhone 17'` is the primary UI proof; unit tests are supporting only; missing simulator-observable hooks must be added.
  - Required `.failed` to become `.error` with no internal alias.
  - Added exact owner tests for `DockConfigurationTests`, `AppConnectivityStoreTests`, and `AutomationIDTests`.
  - Tightened Phase 3, Phase 4, Phase 5, and Phase 6 exit criteria to be audit-ready.
  - Moved required filter-default comment and automation ID test obligations into authoritative phase checklists.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

- 2026-05-29: Created this plan as the canonical implementation architecture document for `docs/mockups/codex-dock-activity-first-2026-05-29/README.md`.
- 2026-05-29: Chose clean Dock IA cutover: no runtime fallback to old primary tabs or old Branch/Newest sort control.
- 2026-05-29: Chose `Newest` as default lens and `lastActivity` as the only V1 sort basis because `SessionSummary` exposes last activity, not a distinct created date; current mapping prefers server `updatedAt` and falls back to `createdAt`.
- 2026-05-29: Chose to remove `Needs me` from primary Dock vocabulary and map active waiting flags to visible `Running` until a future reliable product signal exists.
- 2026-05-29: Chose not to expose archive visibility in Dock V1 because archived sessions are owned by `ArchiveStore` and the `Archive` tab.
- 2026-05-29: Chose immediate filter application with clear/reset controls instead of staged Apply.
- 2026-05-29: Chose deterministic host display-name derivation instead of persisted host aliases.
- 2026-05-29: Marked Dock archive visibility requirements not applicable to V1 because archived sessions remain in `ArchiveStore` and the `Archive` tab; no fake archive toggle is allowed in Dock filters.
- 2026-05-29: Required partial loading publication so loaded host rows can appear while other configured hosts are still checking.
- 2026-05-29: Collapsed not-loaded result filtering into `DockFilterState.statusKinds`; default status `Any` includes `Not loaded`, and not-loaded-only is selected by `Status: Not loaded`.
- 2026-05-29: Required `.failed` to be renamed to visible enum case `.error`; no internal `.failed` alias.
- 2026-05-29: Excluded optional header host-count shortcut pills from V1; host lookup is handled by Host lens, host filter, row host identity, and compact connectivity.
- 2026-05-29: Search updates through local projection as the user types; debounce can be added only as an invisible performance detail.
- 2026-05-29: Pinning is out of V1 and requires a future explicit product decision.
- 2026-05-29: Made global `searchText` the row-result branch search; branch chip search in `DockFilterSurfaceView` is local option search and is not stored in `DockFilterState`.
- 2026-05-29: Required Dock row normalization to split from archive section grouping so Dock's activity-first projection cannot rewrite Archive behavior by accident.
- 2026-05-29: Required host group headers to show a running count when visible `Running` rows exist.
- 2026-05-29: Rejected fake session skeleton rows for V1 loading; use one loading row per host plus neutral loading copy.
- 2026-05-29: Added `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_REQUIREMENT_DISPOSITION_2026-05-29.md` as the canonical V1 disposition for every `G-*` and `Sxx-*` requirement ID in the mockup package.
- 2026-05-29: Chose branch-search presentation for V1: global search filters rows and preserves the selected lens grouping; it does not sometimes flatten and sometimes group.
- 2026-05-29: Required search and branch lookup to be case-insensitive in V1.
- 2026-05-29: Chose not to render a visible `NEWEST` section header by default because selected lens state and active summary already identify the mode; an accessibility-only or non-wasting label remains allowed if implementation proof requires it.
- 2026-05-29: Chose stricter deletion for `Needs me`: no debug-only Dock path in V1.
- 2026-05-29: Strengthened completion proof to simulator-first. `rtk make app-test SIM='iPhone 17'` is mandatory primary proof for user-visible Dock behavior; unit tests are supporting checks only, and missing simulator test hooks must be implemented rather than used as an excuse to downgrade proof.
