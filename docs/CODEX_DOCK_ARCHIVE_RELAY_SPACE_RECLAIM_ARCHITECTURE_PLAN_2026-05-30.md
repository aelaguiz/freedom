---
title: "Codex Dock - Archive Relay Space Reclaim - Architecture Plan"
date: 2026-05-30
status: complete
fallback_policy: forbidden
owners: [Amir]
reviewers: [Composer 2.5 Fast, thermonuclear-code-quality-review]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_REQUIREMENTS_2026-05-30.md
  - docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_UX_WORKLOG_2026-05-30.md
  - docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/contact-sheet.png
  - docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/01-dock-more-menu.png
  - docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/02-system-health-sheet.png
  - docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/03-archive-cleanup-sheet.png
  - docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/04-archived-threads-sheet.png
---

# TL;DR

Outcome:
Codex Dock will reclaim the bottom tab-bar space by making `Dock` the single
daily root surface and moving Archive, Relay, and diagnostics work into
task-focused More-menu sheets.

Problem:
The current `TabView` spends permanent vertical space on `Archive` and `Relay`,
but those tabs are setup/maintenance surfaces. Archive also lacks the user's real
cleanup workflow for thousands of threads, and Relay diagnostics expose raw-ish
evidence without clear user action.

Approach:
Replace the root `TabView` with a Dock-owned task-sheet router; refactor Archive
and Relay surfaces into reusable sheets; add Archive Cleanup and Archived
Threads task flows; replace raw connectivity diagnostics with a plain-language
System Health sheet backed by the existing connectivity and route evidence.

Plan:
First clear the pre-implementation plan gates, then prove the root IA and task
sheet routing, complete System Health and Relay Settings, move Archived Threads
into its recovery sheet, add Archive Cleanup preview/review/execution, then
harden automation IDs, tests, docs, simulator evidence, and final review.

Non-negotiables:
No bottom `Archive`/`Relay` root tabs, no phone-side secrets or relay identity,
no unsafe passive-route probing, no hidden fallback to old tabs, no server-side
bulk archive/restore protocol in the first implementation, and no destructive
bulk archive without preview, confirmation, progress, and truthful partial
failure reporting.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-30
external_research_grounding: done 2026-05-30
deep_dive_pass_2: done 2026-05-30
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:95e9d27f3f56b46d0f658a65f2a75bf3b1e55e3e763fd28e60bd27da0b28a6aa",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-30T21:30:15Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:826c11a677e63cd863b8bc841608d09cda9900fcf74d8742f37ca5a89062cea9",
      "completed_at": "2026-05-30T21:30:59Z",
      "doc_hash_after": "sha256:3651e039a995c83e7caa7f867c604b8ba3efcf727ed3530ff007efa55cefcf85"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T21:31:07Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:3651e039a995c83e7caa7f867c604b8ba3efcf727ed3530ff007efa55cefcf85",
      "completed_at": "2026-05-30T21:32:28Z",
      "doc_hash_after": "sha256:272e413899da162140edad4fe822d04fd92436e10d3488d167131682e994541f"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T21:32:38Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:272e413899da162140edad4fe822d04fd92436e10d3488d167131682e994541f",
      "completed_at": "2026-05-30T21:33:03Z",
      "doc_hash_after": "sha256:28b27ed4e54517a884a45d045c90c89b1ae55b13a28918ca34a53d5398e2aff6"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-30T21:33:14Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:28b27ed4e54517a884a45d045c90c89b1ae55b13a28918ca34a53d5398e2aff6",
      "completed_at": "2026-05-30T21:34:23Z",
      "doc_hash_after": "sha256:78a08c79b83675347cbb15fad787ea41f2e141fdedf1d746bceac2d89dda68dc"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-30T21:34:45Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:78a08c79b83675347cbb15fad787ea41f2e141fdedf1d746bceac2d89dda68dc",
      "completed_at": "2026-05-30T21:42:32Z",
      "doc_hash_after": "sha256:292d375ed4ef5776e4b0589fa800058dee61912e6a4c2f11f5790c1c8ecf479b"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, the installed app's daily Dock screen no longer has the
bottom `Dock` / `Archive` / `Relay` tab bar, exposes `Archive cleanup`,
`Archived threads`, `System health`, and `Relay settings` from a compact More
menu, and supports a safe age-based archive cleanup flow with categorized
connectivity diagnostics.

## 0.2 In scope

Requested behavior scope:

- Replace root three-tab navigation with Dock-first task-sheet IA.
- Preserve the existing Dock feed, search, lenses, filters, row navigation,
  row-level archive, pin/watch/color metadata, and host error affordances.
- Add a Dock More menu with exactly:
  - `Archive cleanup`
  - `Archived threads`
  - `System health`
  - `Relay settings`
- Add `System Health` as the user-facing diagnostics sheet from the connectivity
  chip and More menu.
- Add `Archive Cleanup` with `30d`, `90d`, `1y`, and `Custom` age selection,
  default `90d`, preview, exclusions, review list, confirmation, progress,
  completion, partial failure, and Dock refresh.
- Add `Archived Threads` as a task sheet with search, host/date filters,
  selection, single restore, and batch restore.
- Move Relay host management into `Relay Settings`, not a root tab.
- Add or update tests and automation IDs for the new flows.

Allowed architectural convergence scope:

- Refactor SwiftUI root navigation and shared sheet content to avoid duplicate
  Archive/Relay implementations.
- Add focused state/data models for System Health, Archive Cleanup, and
  Archived Threads.
- Reuse the existing app-server `thread/list`, `thread/archive`, and
  `thread/unarchive` contracts.
- Reuse existing route diagnostics, host settings, archive store, Dock store,
  local metadata, and row projection concepts where they already own the data.
- Update live README/docs only where touched behavior would otherwise become
  stale.

Adjacent surfaces in scope:

- `AutomationID` constants and tests.
- Swift store tests for candidate rules, archive/restore batches, and health
  category projection.
- App-server client tests when query or route usage changes.
- Simulator app build/test target if UI target wiring changes.

Compatibility posture:

- Clean UI cutover from root tabs to Dock-owned task sheets.
- Preserve network contracts for first ship: no new server-side bulk
  archive/restore method.
- Preserve local relay config shape as host/port only.
- Preserve existing row-level archive/restore behavior.

## 0.3 Out of scope

- Server-side bulk archive or restore protocol.
- Phone-side secrets or relay identity persistence.
- Direct physical-phone connection to raw authenticated `:4500`.
- Marketing/onboarding surface.
- Visual golden tests for generated mockups.
- Repo-policing doc scanners, absence checks, or grep gates.
- Raw platform build/install commands as normal workflow.

## 0.4 Definition of done (acceptance evidence)

- Requirements doc has Composer 2.5 Fast `BLOCKING: none`.
- ArcStep stage gate reports `READY next=implement-loop`.
- This implementation plan has Composer 2.5 Fast `BLOCKING: none` before code
  implementation begins.
- The implementation removes root Archive/Relay tabs and exposes all task
  surfaces from Dock.
- Archive Cleanup candidate rules, preview, confirmation, progress, and partial
  failure are covered by targeted Swift tests.
- Archived Threads single and batch restore are covered by targeted Swift tests.
- System Health category mapping and diagnostics fetch behavior are covered by
  targeted Swift tests.
- Relevant `rtk swift test --filter ...` and `rtk npm run test:relay` checks pass
  where touched code requires them.
- If UI target wiring changes, `rtk make app-test SIM='iPhone 17'` or an exact
  blocker is recorded.
- Thermonuclear code review runs before any commit/push decision.

## 0.5 Key invariants (fix immediately if violated)

- The daily Dock screen has no bottom `Archive` or `Relay` root tabs.
- There is one active task sheet at a time.
- Task sheets use internal `NavigationStack` pushes or explicit sheet
  replacement, never stacked modal sheets.
- Bulk archive and restore report per-row truth; failed rows are never counted
  as success.
- Daily Dock active load remains capped and fast.
- Cleanup full scan is user-initiated and separate from daily Dock refresh.
- Passive-only routes are not auto-probed just to make UI green.
- Saved relay config remains `{host, port}` only.
- Secrets, prompts, transcripts, raw audio, and full JSON-RPC payloads are not
  logged.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Reclaim first-screen vertical space for Dock rows.
2. Make diagnostics understandable before exposing raw route evidence.
3. Make archive cleanup safe enough for thousands of threads.
4. Preserve existing Dock behavior and relay configuration invariants.
5. Keep implementation direct and testable without inventing speculative
   protocols or harnesses.

## 1.2 Constraints

- Current daily Dock load is intentionally capped by
  `CodexDockConstants.Dock.activeSessionMaxPages`.
- Cleanup needs a separate full-scan path.
- Existing app-server archive/restore contracts are row-level.
- Connectivity evidence is already split across app observations, route
  diagnostics, host tests, archive state, detail state, and voice state.
- Physical-phone proof has specific relay path expectations and may be blocked
  by device/WebDriverAgent availability.

## 1.3 Architectural principles (rules we will enforce)

- Keep business rules in stores/data engines, not in SwiftUI layout code.
- Keep production timing/page/concurrency constants in
  `CodexDockConstants.swift`.
- Reuse `AppConnectivityStore`, `RelayDiagnosticsClient`, `ArchiveStore`,
  `DockStore`, `HostSettingsStore`, and row projection models instead of
  creating parallel data truth.
- Prefer clean cutover over runtime shims.
- Treat route names as data; map them to plain UI categories at a display-model
  boundary.
- Use bounded per-row archive/restore execution for first ship.

## 1.4 Known tradeoffs (explicit)

- Client-side bulk archive over row-level `thread/archive` is less efficient
  than a server bulk method, but it avoids new relay/app-server protocol risk.
- Removing root Archive/Relay tabs breaks existing automation IDs tied to root
  tabs; tests must move to task-surface IDs.
- A full cleanup scan can be expensive; it is user-initiated and isolated from
  Dock refresh.
- System Health may show `Not checked` for passive-only routes; this is more
  honest than manufacturing synthetic green status.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

`CodexDockRootView` is a three-tab `TabView` with `Dock`, `Archive`, and
`Relay`. Dock is the main feed. Archive is a root tab for archived-row restore.
Relay is a root tab for host settings and a narrow active-list test. The
connectivity chip opens a raw diagnostics sheet with endpoint, status, route
rows, and "No route evidence yet" when evidence is missing.

## 2.2 What's broken / missing (concrete)

- Bottom tabs consume vertical space on the only screen the user checks often.
- Archive is not useful for a user with thousands of stale active threads
  because it only browses already archived rows.
- Relay settings are setup/maintenance controls but stay permanently visible in
  root navigation.
- Diagnostics expose internal evidence without translating it into impact and
  next action.
- There is no bulk cleanup flow for "archive anything older than a period with
  exclusions."

## 2.3 Constraints implied by the problem

- The fix must change root information architecture, not only restyle tabs.
- Archive cleanup must be destructive-safe and progress-aware.
- Relay settings and diagnostics must remain reachable.
- The current archive/restore contracts should be preserved for first ship.
- Tests must prove both preserved existing behavior and new bulk behavior.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- Apple HIG tab bars - adopt. Tab bars are for primary app destinations. Archive
  and Relay are not daily destinations in this product, so persistent bottom
  navigation is the wrong information architecture.
- Apple HIG menus / pull-down buttons - adopt. Secondary commands such as
  Archive cleanup, Archived threads, System health, and Relay settings belong
  in a compact More command surface.
- Apple HIG sheets / iOS 26 sheet behavior - adopt. Focused maintenance tasks
  fit sheet presentation over the current Dock context.
- Apple context menus - adopt for row-level supplemental archive, reject as the
  only cleanup path. A 7,000-thread cleanup workflow needs visible preview and
  batch controls.
- Apple Mail batch archive/delete pattern - adopt. Selection plus batch action
  is a familiar iOS pattern for list cleanup.
- NN/g usability heuristics - adopt. System status and error recovery must be
  visible and understandable, not raw endpoint/route evidence.
- NN/g progressive disclosure - adopt. Relay setup and archive maintenance stay
  discoverable but move behind task surfaces.
- Baymard applied filters - adopt. Applied filter state must stay readable and
  compact so content is not pushed below the fold.

## 3.2 Internal ground truth (code as spec)

Authoritative behavior anchors:

- `CodexDock/Features/Dock/DockView.swift:125` - current root `TabView` owns
  `Dock`, `Archive`, and `Relay` root tabs.
- `CodexDock/Features/Dock/DockView.swift:290` - Dock layout is a scroll stack
  of header, controls, and content. This is the daily surface to preserve.
- `CodexDock/Features/Dock/DockView.swift:331` - Dock header currently places
  `GlobalConnectivityIndicatorView` beside the title.
- `CodexDock/Features/Dock/DockView.swift:951` - row-level archive action
  already exists and must be preserved.
- `CodexDock/Features/Archive/ArchiveView.swift:23` - Archive is currently a
  full root tab with its own `NavigationStack`.
- `CodexDock/Features/Archive/ArchiveView.swift:172` - single-row restore is
  visible in Archive and must be preserved in Archived Threads.
- `CodexDock/Features/Hosts/HostsView.swift:21` - Relay settings are currently a
  full root tab.
- `CodexDock/Features/Hosts/HostsView.swift:122` - host editor is always visible
  when configured; target Relay Settings must hide it until add/edit.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift:3` -
  connectivity chip is the existing entry point to diagnostics.
- `CodexDock/Features/Status/ConnectivityDiagnosticsSheet.swift:10` - current
  diagnostics UI is raw evidence-first and should be replaced by System Health.
- `CodexDock/State/AppConnectivityStore.swift:145` - connectivity rollup already
  collects host status, observations, and route diagnostics.
- `CodexDock/State/AppConnectivityStore.swift:369` - `refreshRelayDiagnostics`
  fetches `/routesz` and records route snapshots.
- `CodexDock/Diagnostics/ObservabilityContract.swift:50` - route safety and
  app-critical metadata already exist and must govern System Health.
- `CodexDock/State/AppServerDockClient.swift:25` - `DockSessionQuery` controls
  active/archived list queries and page caps.
- `CodexDock/State/AppServerDockClient.swift:60` - archive/restore contracts are
  row-level `archiveThread` / `unarchiveThread`.
- `CodexDock/Archive/ArchiveDataEngine.swift:44` - archive already loads hosts
  concurrently, a pattern to reuse for cleanup preview.
- `CodexDock/State/ArchiveSessionProjector.swift:3` - archived rows reuse row
  projection and grouping.
- `CodexDock/Dock/DockModels.swift:121` - Dock filter state deliberately has no
  archive facet; Archived Threads should stay a task sheet, not a Dock filter.
- `CodexDock/Automation/AutomationID.swift:81` - root tab automation IDs exist
  and must be migrated to task-surface IDs.
- `CodexDock/Configuration/CodexDockConstants.swift:16` - production Dock
  constants must own page and concurrency values.

Canonical path / owner to reuse:

- Root IA owner: `CodexDock/Features/Dock/DockView.swift`.
- Dock visual/content owner: `DockView`, `DockScreenStore`, and existing row
  projection/store types.
- System Health owner: new display model and view under
  `CodexDock/Features/Status/`, backed by `AppConnectivityStore` and
  `RelayDiagnosticsClient`.
- Archive Cleanup owner: new data engine/store/view under
  `CodexDock/Archive/`, `CodexDock/State/`, and `CodexDock/Features/Archive/`
  as appropriate, reusing `DockSessionLoading`, `DockSessionArchiving`, local
  metadata, and row projection.
- Archived Threads owner: refactor existing `ArchiveStore` / `ArchiveView`
  behavior into a task sheet instead of root tab.
- Relay Settings owner: refactor existing `HostsView` / `HostSettingsStore`
  behavior into an embeddable settings sheet.

Adjacent surfaces tied to the same contract family:

- `CodexDockTests/AutomationIDTests.swift` - root tab and new task IDs.
- `CodexDockTests/DockStoreTests.swift` - archive/restore and host settings
  preservation.
- `CodexDockTests/ArchiveScreenStoreTests.swift` and
  `CodexDockTests/ArchiveDataEngineTests.swift` - archived-row loading,
  grouping, restore, and preservation behavior.
- `CodexDockTests/HostSettingsScreenStoreTests.swift` - host add/edit/remove,
  test, validation, and config-shape preservation.
- `CodexDockTests/AppConnectivityStoreTests.swift` - health rollup behavior.
- `CodexDockTests/ConnectivityDataEngineTests.swift` - connectivity host
  observations and fetch behavior.
- `CodexDockTests/DiagnosticsLoggingTests.swift` - diagnostics client and route
  evidence behavior.
- `CodexDockTests/AppServerClientTests.swift` - JSON-RPC archive/restore/query
  contracts if query constants change.
- `scripts/dock-relay*.mjs` and relay tests - only in scope if route contracts
  or relay observability change.
- `README.md` - update if root navigation, System Health, or archive cleanup
  runbook text becomes stale.

Compatibility posture (separate from `fallback_policy`):

- Clean UI cutover from root tabs to task sheets.
- Preserve app-server JSON-RPC contracts.
- Preserve saved local relay config as host/port only.
- Preserve row-level archive/restore behavior and tests while adding batch
  orchestration around the same contracts.

Existing patterns to reuse:

- Host-concurrent loading from `ArchiveDataEngine.loadAllHosts`.
- Connectivity observation rollup from `AppConnectivityStore`.
- Diagnostics URL derivation and route decoding from `RelayDiagnosticsClient`.
- Shared row rendering from `DockRowView`.
- Local metadata integration from `SessionRowProjector` and metadata store.
- Store/screen-store separation used by Dock, Archive, and Relay.

Prompt surfaces / agent contract to reuse:

- Not applicable. This feature is not agent-backed at runtime.

Native model or agent capabilities to lean on:

- Not applicable for product runtime. Fresh Composer and thermonuclear review are
  process gates, not shipped app behavior.

Existing grounding / tool / file exposure:

- Mockups and requirements are local docs/images under `docs/`.
- Build/test command source of truth is `Makefile`.
- `project.yml` remains the XcodeGen source of truth if target wiring changes.

Duplicate or drifting paths relevant to this change:

- `ArchiveView` as root tab versus target Archived Threads task sheet.
- `HostsView` as root tab versus target Relay Settings task sheet.
- `ConnectivityDiagnosticsSheet` raw evidence view versus target System Health.
- Root tab automation IDs versus task-surface automation IDs.

Capability-first opportunities before new tooling:

- Reuse existing row-level archive/restore contracts with bounded client
  orchestration instead of adding a bulk server protocol.
- Reuse route evidence and app observations with a display-model mapping instead
  of creating new diagnostics endpoints.
- Reuse existing stores and row views before inventing duplicate view models.

Behavior-preservation signals already available:

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ArchiveScreenStoreTests`
- `rtk swift test --filter ArchiveDataEngineTests`
- `rtk swift test --filter HostSettingsScreenStoreTests`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk swift test --filter ConnectivityDataEngineTests`
- `rtk swift test --filter DiagnosticsLoggingTests`
- `rtk npm run test:relay` if relay scripts change
- `rtk make app-test SIM='iPhone 17'` if generated app UI wiring changes

## 3.3 Decision gaps that must be resolved before implementation

- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

Relevant SwiftUI surfaces:

- `CodexDock/Features/Dock/DockView.swift` - root `CodexDockRootView`,
  `DockView`, root tab state, Dock header, controls, row content, row context
  menu archive action, host unavailable affordances.
- `CodexDock/Features/Archive/ArchiveView.swift` - root Archive tab view and
  row restore UI.
- `CodexDock/Features/Hosts/HostsView.swift` - root Relay tab view and always
  visible host editor.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` -
  connectivity chip that currently owns diagnostics sheet presentation.
- `CodexDock/Features/Status/ConnectivityDiagnosticsSheet.swift` - raw
  diagnostics sheet.
- `CodexDock/Features/Dock/DockFilterSurfaceView.swift` - filter sheet pattern
  and compact chip layout.

Relevant state/data owners:

- `CodexDock/State/DockStore.swift` - active Dock load, row archive action,
  refresh after archive.
- `CodexDock/State/ArchiveStore.swift` - archive list load and restore.
- `CodexDock/Archive/ArchiveDataEngine.swift` - concurrent archived host load.
- `CodexDock/State/ArchiveSessionProjector.swift` - archived row grouping.
- `CodexDock/State/HostSettingsStore.swift` - saved relay host add/edit/remove
  and active-list test.
- `CodexDock/State/AppConnectivityStore.swift` - global host status and route
  diagnostic rollup.
- `CodexDock/Diagnostics/RelayDiagnosticsClient.swift` - `/routesz` and
  `/statusz` client.
- `CodexDock/Diagnostics/ObservabilityContract.swift` - route safety and
  app-critical route contract.
- `CodexDock/State/AppServerDockClient.swift` - list/archive/unarchive
  JSON-RPC client.

Relevant tests:

- `CodexDockTests/DockStoreTests.swift`
- `CodexDockTests/DockStoreScopeTests.swift`
- `CodexDockTests/AppConnectivityStoreTests.swift`
- `CodexDockTests/DiagnosticsLoggingTests.swift`
- `CodexDockTests/AppServerClientTests.swift`
- `CodexDockTests/AutomationIDTests.swift`

## 4.2 Control paths (runtime)

Root startup today:

```text
CodexDockApp
-> CodexDockBootstrapView
-> RelayBootstrapStore ready
-> CodexDockRootView
-> TabView
   -> DockView
   -> ArchiveView
   -> HostsView labeled "Relay"
```

Dock archive today:

```text
Dock row context menu
-> DockStore.archive(row)
-> ClientCommandEngine.archive(row, host)
-> DockSessionArchiving.archiveThread(threadID, host)
-> AppServerDockClient.threadArchive
-> refresh Dock
-> onArchiveSucceeded refreshes ArchiveStore
```

Archive restore today:

```text
Archive tab
-> ArchiveStore.load()
-> ArchiveDataEngine.loadAllHosts(.archivedHuman)
-> ArchiveView row Restore
-> ArchiveStore.restore(row)
-> ClientCommandEngine.unarchive
-> AppServerDockClient.threadUnarchive
-> refresh Archive
-> onRestoreSucceeded refreshes Dock
```

Relay settings/test today:

```text
Relay tab
-> HostsView
-> HostSettingsStore.rows
-> Test / Test all
-> HostSettingsStore.test(hostID)
-> DockSessionLoading.loadSessions(.activeHuman)
-> reportHostTest into AppConnectivityStore
```

Connectivity diagnostics today:

```text
GlobalConnectivityIndicatorView
-> owns @State showsDiagnostics
-> presents ConnectivityDiagnosticsSheet(hosts)
-> task refreshRelayDiagnostics()
-> RelayDiagnosticsClient.fetchRoutes(/routesz)
-> AppConnectivityStore.reportRouteDiagnostic
-> sheet lists endpoint/status/raw routes
```

## 4.3 Object model + key abstractions

- `DockSessionQuery` defines active/archived list shape and page caps.
- `DockSessionLoading` loads summaries per host and query.
- `DockSessionArchiving` archives/unarchives one row at a time.
- `DockRowViewModel` is the shared row display model with host, repo, branch,
  status, last activity, local label, rail, and pin metadata.
- `DockFilterState` covers active Dock facets and deliberately has no archive
  facet.
- `ArchiveSnapshot` and `DockSectionViewModel` represent archived rows.
- `HostSettingsRowViewModel` represents saved host settings rows.
- `HostConnectivitySnapshot` plus `RouteDiagnosticSnapshot` represent
  connectivity evidence.

## 4.4 Observability + failure behavior today

- Dock/Archive/Host settings report observations to `AppConnectivityStore`.
- App-critical failed route diagnostics can make a host partial even when a
  process looks online.
- Diagnostics fetch failure is stored as a non-app-critical `routesz` failed
  diagnostic and should not replace stronger route failures.
- Archive and Dock map host failures into unavailable/partial states.
- Logging already uses `DockLog`; direct console logging is not the Swift path.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current daily Dock:

```text
Dock                                  Online 2/2
[ Search sessions, repo, branch, host          ]
[ Newest ] [ Host ] [ Branch ] [ filters       ]
Human sessions - active only - Newest activity

[ row ]
[ row ]
[ row ]

------------------------------------------------
          Dock          Archive          Relay
```

Current Archive:

```text
Archive                                      refresh

[ host summary ]
[ archived row ]                             Restore
[ archived row ]                             Restore

------------------------------------------------
          Dock          Archive          Relay
```

Current Relay:

```text
Relay                                      test all

[ host row: Test Edit Remove ]
[ host row: Test Edit Remove ]

Add Relay
Host [ ... ]
Port [ ... ]
[ Save Relay ]

------------------------------------------------
          Dock          Archive          Relay
```

Current diagnostics:

```text
Connectivity

Host
Endpoint: ...
Status: Waiting for first check
No route evidence yet

or raw route rows:
dock/subscribe failed
operationID...
reason...
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

Root and task routing:

- `CodexDock/Features/Dock/DockView.swift`
  - remove root `TabView`
  - introduce Dock-owned active task sheet routing
  - pass task-opening closures into `DockView`
- `CodexDock/Features/Dock/DockTaskSheet.swift` or equivalent local type
  - `archiveCleanup`
  - `archivedThreads`
  - `systemHealth`
  - `relaySettings`

System Health:

- `CodexDock/Features/Status/SystemHealthView.swift`
- `CodexDock/Features/Status/SystemHealthModels.swift`
- `CodexDock/Features/Status/SystemHealthProjector.swift`
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - in the ready Dock root, chip tap delegates to the Dock task router and opens
    `SystemHealthView`
  - outside the ready Dock root or bootstrap-only contexts, any local
    presentation must show the same `SystemHealthView`, never the raw
    diagnostics sheet as the primary UX

Archive Cleanup:

- `CodexDock/Archive/ArchiveCleanupDataEngine.swift`
- `CodexDock/State/ArchiveCleanupStore.swift`
- `CodexDock/Features/Archive/ArchiveCleanupView.swift`
- optionally `ArchiveCleanupModels.swift` if model size warrants it

Archived Threads:

- Refactor `ArchiveView` into embeddable content or add
  `ArchivedThreadsView` that reuses `ArchiveStore`.
- Preserve `ArchiveStore` restore semantics and make batch restore explicit.

Relay Settings:

- Refactor `HostsView` into embeddable `RelaySettingsView`.
- Preserve `HostSettingsStore`.
- Hide add/edit form until explicit add/edit.

Shared contracts:

- `AutomationID.swift` grows task/sheet IDs and deprecates root tab IDs when no
  longer used.
- `CodexDockConstants.swift` owns cleanup/restore concurrency and page limits if
  new production constants are needed.

## 5.2 Control paths (future)

Root:

```text
CodexDockRootView
-> DockView
   -> header More menu
   -> activeTaskSheet item
      -> ArchiveCleanupView
      -> ArchivedThreadsView
      -> SystemHealthView
      -> RelaySettingsView
```

Connectivity chip:

```text
GlobalConnectivityIndicatorView tap in ready Dock root
-> Dock root callback sets activeTaskSheet = .systemHealth
-> SystemHealthView
-> Run check calls AppConnectivityStore.refreshRelayDiagnostics()
```

Outside the ready Dock root, bootstrap-only/local presentation is allowed only
when needed to keep the chip usable, and it must present the same
`SystemHealthView`. It must not preserve a separate primary raw diagnostics
sheet.

System Health display:

```text
AppConnectivityStore.hosts + overallStatus
+ RouteDiagnosticSnapshot
+ current app observations
-> SystemHealthProjector
-> SystemHealthSnapshot
-> SystemHealthView
```

Archive Cleanup preview:

```text
ArchiveCleanupView appears
-> ArchiveCleanupStore.loadPreview(rule)
-> ArchiveCleanupDataEngine.loadAllHosts(query: full active human scan)
-> SessionRowProjector + local metadata
-> candidate filter/exclusion engine
-> preview snapshot
```

Archive Cleanup execution:

```text
ArchiveCleanupStore.archiveSelected(ids)
-> bounded task group
-> ClientCommandEngine / DockSessionArchiving.archiveThread
-> per-row result state
-> completion snapshot
-> DockStore.refresh()
-> AppConnectivityStore archive evidence update
```

Archived Threads:

```text
ArchivedThreadsView
-> ArchiveStore.load(.archivedHuman)
-> local search/filter/select
-> row restore or batch restore
-> bounded unarchive calls
-> ArchiveStore refresh + DockStore refresh
```

Relay Settings:

```text
RelaySettingsView
-> HostSettingsStore rows
-> Run check / Test / Edit / Add / Remove
-> save LocalRelayHostList(hosts)
-> shared host registry updates dependent stores
```

## 5.3 Object model + abstractions (future)

Task routing:

```swift
enum DockTaskSheet: Identifiable {
    case archiveCleanup
    case archivedThreads
    case systemHealth
    case relaySettings
}
```

System Health display model:

```swift
enum SystemHealthCategory: CaseIterable {
    case dockFeed
    case threadDetail
    case archive
    case voice
    case diagnostics
}

enum SystemHealthCategoryStatus {
    case healthy
    case checking
    case notChecked
    case degraded(String)
    case failed(String)
    case blocked(String)
    case stale(String)
}
```

Archive Cleanup model:

```swift
struct ArchiveCleanupRule {
    var age: ArchiveCleanupAge
    var excludesPinned: Bool
    var excludesRunning: Bool
    var excludesNeedsInput: Bool
    var excludesWatchLabel: Bool
}

enum ArchiveCleanupAge {
    case days30
    case days90
    case year1
    case custom(days: Int)
}

enum ArchiveCleanupRowState {
    case candidate
    case excluded(reason: String)
    case selected
    case archiving
    case archived
    case failed(String)
}
```

Batch execution model:

- Track pending/running/succeeded/failed/skipped per row.
- Track per-host totals.
- Stop remaining means no new row work is started; in-flight work may finish.
- Refresh Dock after successful archive/restore mutations.

## 5.4 Invariants and boundaries

- SwiftUI views render snapshots and send user actions; stores own business
  logic.
- System Health category mapping is a display-model boundary over existing
  route diagnostics and app observations.
- Archive Cleanup full scan is never coupled to daily Dock refresh.
- Batch archive/restore uses row-level contracts and bounded concurrency.
- Relay settings writes only host/port config.
- Raw route evidence is secondary/expandable.
- Existing row-level archive/restore remains available.

Second-pass hardening:

- Do not let `GlobalConnectivityIndicatorView` keep an independent raw sheet
  presentation path on the Dock root. In the ready Dock root, it delegates tap
  handling to the root task router. Non-Dock/bootstrap-only local presentation,
  if still needed, presents the same `SystemHealthView`.
- Do not keep old `ArchiveView` and a new `ArchivedThreadsView` as two live
  implementations of the same archive browser. Refactor shared content or fully
  replace the root-only view.
- Do not keep `HostsView` and `RelaySettingsView` as two live implementations
  of host settings. Refactor the existing view into reusable content or rename
  it cleanly.
- Do not add a Dock archive filter as a substitute for Archived Threads; the
  requirements intentionally make archive recovery a task sheet.
- Do not let cleanup candidate logic use raw `SessionSummary` in one path and
  `DockRowViewModel` in another with different metadata semantics. Exclusions
  must share the row/local-metadata meaning used by Dock.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Target Dock:

```text
Dock                         [Online 2/2]  (...)
[ Search sessions, repo, branch, host          ]
[ Newest ] [ Host ] [ Branch ] [ filters       ]
Human sessions - active only - Newest activity

[ row ]
[ row ]
[ row ]
[ row ]
[ row ]
[ row ]
```

More menu:

```text
(...)
+------------------+
| Archive cleanup  |
| Archived threads |
| System health    |
| Relay settings   |
+------------------+
```

System Health:

```text
System Health
[ Online 2/2 ]                         [ Run check ]
Dock feed Healthy | Thread detail Healthy | Archive Not checked
[ Amir-M5 host card > ]
[ Home host card > ]
[ Archive has no recent app traffic yet. ]
Relay settings >
Copy doctor command >
```

Archive Cleanup:

```text
Archive Cleanup
Older than [30d] [90d] [1y] [Custom]
6,842 threads older than 90 days | 2 hosts
[x] Exclude pinned [x] Exclude running
[x] Exclude needs input [x] Exclude Watch label
By host: Amir-M5 4,913 | Home 1,929
Preview rows...
[ Review list ] [ Archive 6,842 ]
```

Archived Threads:

```text
Archived Threads
2,138 archived | Across 2 hosts
[ Search archived threads ]
[ All hosts ] [ Amir-M5 ] [ Home ] [ Last archived ]
[ Select ] [ Restore selected ]
date-grouped rows...
3 selected [ Restore 3 ]
```

Relay Settings:

```text
Relay Settings
[ Run check ] [ Add Relay ]
[ host row Test Edit ]
[ host row Test Edit ]
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Root IA | `CodexDock/Features/Dock/DockView.swift` | `CodexDockRootView.body` | Three-tab `TabView` | Replace with Dock-first root and task-sheet routing | Reclaim bottom space | `DockTaskSheet` active sheet enum | UI/app tests, AutomationID tests |
| Root IA | `CodexDock/Features/Dock/DockView.swift` | `selectedRootTab` | Switches tabs | Remove or replace with `activeTaskSheet` | No root Archive/Relay tabs | `@State var activeTaskSheet` | AutomationID tests |
| Dock header | `DockView.header` | title/status row | Title + connectivity chip | Add More menu and sheet-opening closures | Entry to maintenance tasks | `onOpenArchiveCleanup`, etc. | UI tests if present |
| Connectivity chip | `GlobalConnectivityIndicatorView` | internal sheet | Presents raw diagnostics | Delegate ready-Dock taps to root task router; any non-Dock/bootstrap-only local presentation shows the same System Health view | Plain diagnostics | `SystemHealthView` | AppConnectivityStore/ConnectivityDataEngine/diagnostics tests |
| Diagnostics UI | `ConnectivityDiagnosticsSheet.swift` | raw route list | Primary diagnostics sheet | Replace primary use with System Health; keep raw evidence as host detail expansion if useful | User-facing diagnosis | `SystemHealthProjector` | AppConnectivityStoreTests |
| Health models | new | `SystemHealthCategory` | none | Map route/app observations to Dock feed, Thread detail, Archive, Voice, Diagnostics | Plain categories | category status model | new health tests |
| Health projector tests | new `CodexDockTests/SystemHealthProjectorTests.swift` | category-mapping tests | none | Own focused System Health category, degraded, partial, and next-action copy coverage | Keep connectivity store tests focused on data collection | `SystemHealthProjector` contract | health tests |
| Archive cleanup preview | new | `ArchiveCleanupStore.loadPreview` | none | Load full active human scan per host and compute candidates | 7k cleanup workflow | `ArchiveCleanupRule`, preview snapshot | new cleanup tests |
| Archive cleanup engine | new | `ArchiveCleanupDataEngine` | none | Concurrent host full-scan using `DockSessionLoading` | Reuse archive host pattern | full-scan query | DockStore/AppServerClient tests |
| Archive cleanup store tests | new `CodexDockTests/ArchiveCleanupStoreTests.swift` | cleanup candidate/execution tests | none | Own focused cleanup preview, selection, execution, and result-state coverage | Keep broad Dock tests from becoming overloaded | cleanup store state contract | cleanup tests |
| Query model | `AppServerDockClient.swift` | `DockSessionQuery` | active capped, archived uncapped | Add named cleanup full-scan query if needed | Avoid changing daily Dock cap | `.activeHumanFullScan = DockSessionQuery(archived: false, sourceKinds: nil, maxPages: nil)` or exact explicit equivalent | AppServerClientTests |
| Candidate projection | existing/new | `SessionRowProjector` usage | Dock/archive row projection | Reuse for cleanup rows and metadata exclusions | One meaning for pinned/watch/status | cleanup row model | candidate rule tests |
| Bulk archive | `DockStore`/new store | single `archive(row)` | one row | Add bounded batch execution in cleanup store using existing archiver | Safe bulk cleanup | per-row result model | batch archive tests |
| Archive evidence | `AppConnectivityStore` | archive state observations | Archive tab load only | Report cleanup preview/execution archive evidence | System Health Archive category | archive evidence method if needed | health tests |
| Archived Threads | `ArchiveView.swift`, `ArchiveScreenStore.swift` | root tab | root archive browser | Refactor to sheet content with search/select/batch restore | No root Archive tab | `ArchivedThreadsView` | ArchiveScreenStore/ArchiveDataEngine tests |
| Archived Threads tests | `CodexDockTests/ArchiveScreenStoreTests.swift` or new `CodexDockTests/ArchivedThreadsStoreTests.swift` | archive browser tests | single restore/load coverage | Add batch restore, selection, progress, Stop remaining, retry, and Dock refresh coverage | Keep recovery flow test-owned | archive/recovery store contract | restore tests |
| Batch restore | `ArchiveStore`/new helper | single restore | one row | Add bounded batch restore | Restore selected | per-row restore result | restore tests |
| Relay settings | `HostsView.swift`, `HostSettingsScreenStore.swift` | root Relay tab | always visible editor | Refactor to embeddable Relay Settings with hidden editor until add/edit | No root Relay tab | `RelaySettingsView` | HostSettingsScreenStore tests |
| Host settings store | `HostSettingsStore.swift` | rows/test/save | root-owned | Reuse unchanged where possible | Preserve config behavior | no config shape change | DockStoreTests |
| Constants | `CodexDockConstants.swift` | Dock constants | no batch concurrency | Add cleanup/restore concurrency if needed | no hard-coded production constants | `ArchiveCleanup.archiveConcurrency` | compile/tests |
| Automation IDs | `AutomationID.swift` | Root tab IDs, Archive/Relay roots | IDs for root tabs | Add task sheet IDs; remove/update root tab test expectations | Testability | `AutomationID.Task`, etc. | AutomationIDTests |
| UI automation tests | `CodexDockUITests/CodexDockAutomationSmokeTests.swift` | `tapRootTab(.relay)` and root tab helpers | Drives Relay root tab by ID | Migrate root-tab smoke paths to More-menu task sheets or remove stale root-tab helpers | UI proof must match shipped IA | task-sheet automation IDs | UI smoke tests/app-test |
| README | `README.md` | root indicator/tabs wording | mentions Dock/Archive/Hosts | Update if implementation changes user-visible nav/docs | Avoid stale live docs | docs only | readback/status |
| Project config | `project.yml` | target files | current files auto-included? | Update only if XcodeGen needs explicit file wiring | Xcode source truth | no behavior contract | `rtk xcodegen`, app-test if needed |
| Relay scripts | `scripts/dock-relay*.mjs` | row archive routes | row archive/unarchive | No first-ship change unless tests reveal route evidence gap | Avoid protocol creep | unchanged | `rtk npm run test:relay` only if touched |

## 6.2 Migration notes

Canonical owner path / shared code path:

- Root presentation: `CodexDockRootView`.
- System Health display: new Status feature model/view backed by
  `AppConnectivityStore`.
- Cleanup candidate and execution logic: new Archive/State store and engine,
  not SwiftUI view code.
- Archived restore browsing: existing `ArchiveStore` semantics reused in a sheet.
- Relay settings: existing `HostSettingsStore` reused in a sheet.

Deprecated APIs if any:

- Root tab presentation and root tab automation IDs become obsolete once the
  clean UI cutover lands.

Delete list:

- Remove the root `TabView` from `CodexDockRootView`.
- Remove old root-tab-only navigation closures such as `selectedRootTab = .relay`.
- Remove or retire raw `ConnectivityDiagnosticsSheet` as the default chip sheet;
  keep only if embedded behind technical details.

Adjacent surfaces tied to the same contract family:

- Automation IDs and tests move with root IA.
- README navigation/diagnostics wording moves with root IA.
- AppConnectivityStore tests move with System Health category behavior.
- AppServerClient tests move only if query constants or JSON-RPC calls change.

Compatibility posture / cutover plan:

- Clean UI cutover.
- Preserve wire protocols.
- Preserve row-level archive/restore.
- Preserve config file shape.

Capability-replacing harnesses to delete or justify:

- None. No agent-backed runtime behavior.

Live docs/comments/instructions to update or delete:

- Update README if it still says the app has Archive/Hosts root tabs.
- Keep AGENTS instructions untouched unless implementation changes their command
  guidance, which is not expected.

Behavior-preservation signals for refactors:

- Existing `DockStoreTests` archive/restore tests.
- Existing `ArchiveScreenStoreTests` and `ArchiveDataEngineTests` load/grouping
  and restore tests.
- Existing `HostSettingsScreenStoreTests` save/edit/test/validation tests.
- Existing `AppConnectivityStoreTests` and `ConnectivityDataEngineTests` route
  failure and host observation tests.
- Existing `AppServerClientTests` archive/unarchive tests.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Sheet routing | `CodexDockRootView` | one active task sheet enum | avoids stacked modal drift | include |
| Status projection | new `SystemHealthProjector` | category display model | keeps raw routes out of UI copy | include |
| Host loading | `ArchiveDataEngine` pattern | concurrent per-host task group | avoids bespoke serial scans | include |
| Batch results | new cleanup/restore execution model | per-row result states | truthful partial failure | include |
| Relay settings | `HostSettingsStore` | reuse store, refactor view | avoids duplicate host config logic | include |
| Archived rows | `ArchiveStore` | reuse archive load/restore | avoids parallel archive browser | include |
| Constants | `CodexDockConstants` | production numeric SSOT | avoids hidden magic constants | include |
| Relay protocol | `scripts/dock-relay*.mjs` | keep row-level routes | avoids server protocol creep | exclude |

Second-pass obligation sweep:

- Include task-sheet router and connectivity chip changes in the first working
  slice, because they prove the root cutover and System Health entry path.
- In that first slice, every More-menu item opens a real titled task sheet root
  with close behavior and no destructive dead-end action, even when later phases
  fill in final behavior.
- Include raw diagnostics replacement early enough that no root chip still opens
  the old raw sheet after the cutover.
- Place Archived Threads before Archive Cleanup links and completion depend on
  it, because cleanup needs a real recovery path.
- Place Archive Cleanup candidate preview before archive execution, because the
  candidate model is the highest-risk destructive-data contract.
- Place cleanup batch execution after preview/review, because it depends on
  candidate IDs, selection, exclusion truth, and the recovery sheet.
- Place Relay Settings refactor after root routing is proven but before final UI
  verification, because System Health links depend on it.
- Update README and automation IDs in the same implementation arc; stale root
  tab docs/tests would otherwise contradict shipped behavior.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable work. `Work` is explanatory only. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. No fallbacks/runtime shims - the system must work correctly or fail loudly.

## Phase 0 - Pre-implementation planning gates

Goal:

Prove the plan is complete before any code implementation begins.

Work:

This phase is planning-only. It completes the ArcStep auto-plan receipt gate and
the user-requested fresh Composer 2.5 Fast plan review before Phase 1 code work.

Checklist (must all be done):

- Run the ArcStep ready gate for this `DOC_PATH`.
- Run fresh Cursor Agent Composer 2.5 Fast review against this plan, the
  requirements doc, the worklog, and the mockup folder.
- Spot-check any blocking Composer finding against repo evidence before editing.
- Patch this plan for every verified blocking finding.
- Rerun Composer review until the plan review reports `BLOCKING: none`.
- Record the final no-blocker plan-review run directory in the Decision Log or
  implementation handoff notes.
- Do not edit Swift, Node, project config, README, or production code in this
  phase.

Verification (required proof):

- `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_ARCHITECTURE_PLAN_2026-05-30.md`
- Fresh Composer 2.5 Fast plan review final output says `BLOCKING: none`.

Docs/comments (propagation; only if needed):

- Append a Decision Log entry if Composer feedback changes phase order, scope,
  compatibility posture, or acceptance evidence.

Exit criteria (all required):

- ArcStep ready gate returns `READY next=implement-loop`.
- Composer plan review reports `BLOCKING: none`.
- No implementation code changed before both gates passed.
- No unresolved plan-shaping decision remains.

Rollback:

No code rollback applies. If a gate fails, keep patching the plan instead of
starting implementation.

## Phase 1 - Root task router plus real task-sheet roots

Status: COMPLETE - implementation evidence recorded in the worklog; final
review gate remains Phase 6.

Goal:

Prove the highest-risk UI cutover: Dock becomes the only root daily surface, the
bottom tab bar disappears, and every More-menu destination opens through one
Dock-owned task-sheet router.

Work:

This phase removes the root `TabView` dependency, creates the shared
presentation mechanism, and establishes real sheet roots for all four tasks.
Later phases fill final behavior into those same surfaces; Phase 1 must not
leave dead menu items or destructive actions without their safety layers.

Checklist (must all be done):

- Remove `TabView` root presentation from `CodexDockRootView`.
- Add one active task sheet state for `archiveCleanup`, `archivedThreads`,
  `systemHealth`, and `relaySettings`.
- Add Dock header More button and menu with exact labels:
  `Archive cleanup`, `Archived threads`, `System health`, `Relay settings`.
- Make each More-menu item open a real titled task sheet root with close
  behavior:
  - `ArchiveCleanupView`
  - `ArchivedThreadsView` or refactored `ArchiveView` sheet content
  - `SystemHealthView`
  - `RelaySettingsView` or refactored `HostsView` sheet content
- Use the requirements presentation contract for task sheets, including the
  large-detent target unless an existing iOS constraint forces an exact blocker
  to be recorded.
- Keep non-final sheet roots safe: no bulk archive/restore action is enabled
  until the phase that implements its preview/progress/result state.
- Add accessibility labels/traits for the More button, menu entries, sheet
  close controls, and initial task-sheet roots introduced in this phase.
- Preserve Dock search, lenses, filter button, active filter summary, row list,
  row navigation, and row context menu archive action.
- Rewire existing host-failure / `onOpenRelaySettings` paths from
  `selectedRootTab = .relay` to `activeTaskSheet = .relaySettings` or the
  appropriate System Health path, preserving the ability to recover from relay
  setup failures.
- Change the ready-Dock connectivity chip path so it delegates to the root task
  router and opens `SystemHealthView`.
- Remove the old primary raw `ConnectivityDiagnosticsSheet` presentation from
  the ready-Dock chip path, including the local `showsDiagnostics` sheet path in
  `GlobalConnectivityIndicatorView` when the chip is used from the ready Dock
  root.
- Add initial `SystemHealthView` shell with title, close, top summary, Run
  check, category rollup placeholders from existing store data, host cards, and
  actions.
- Add `SystemHealthProjector`/models that map existing
  `AppConnectivityStore.hosts` and `overallStatus` to the five required
  categories.
- Add task-surface automation IDs needed by this phase.
- Update or remove root-tab-specific automation expectations that no longer
  match shipped UI.

Verification (required proof):

- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk swift test --filter ConnectivityDataEngineTests`
- `rtk swift test --filter AutomationIDTests`
- `rtk swift test --filter DockStoreTests` if Dock root/store signatures change
- `rtk make app-test SIM='iPhone 17'` if root navigation or sheet routing cannot
  be proven by package tests after the `TabView` removal

Docs/comments (propagation; only if needed):

- Add a concise code comment only at the task-router boundary if the one-active
  sheet invariant is not obvious from the enum/state shape.

Exit criteria (all required):

- No daily Dock root `TabView` remains.
- There is no bottom `Archive` / `Relay` root tab path in the app root.
- More menu labels and ordering match requirements.
- Every More-menu item opens a real sheet root; none is a dead tap.
- Sheet presentation behavior matches the requirements detent/close rules or
  records the exact platform blocker.
- Connectivity chip in the ready Dock root opens System Health, not raw
  `ConnectivityDiagnosticsSheet`.
- Host-failure / relay-not-configured recovery paths open Relay Settings or
  System Health through the new task router instead of old root-tab selection.
- Existing Dock row archive action still compiles and has preserved coverage.
- Task roots cannot perform unsafe bulk mutation before later safety phases.
- Initial task-sheet roots expose accessible labels/traits for their primary
  controls.
- Required tests for touched surfaces pass or exact blockers are recorded.

Rollback:

Revert the root task-router and task-sheet-root changes together. Do not keep a
half-cutover state with both root tabs and task sheets.

## Phase 2 - Complete System Health and Relay Settings task surface

Goal:

Make diagnostics and relay setup useful without restoring Relay as a root tab.

Work:

This phase completes the plain-language health model, host detail drilldown,
safe diagnostics refresh, copy doctor command, and embeddable Relay Settings.

Checklist (must all be done):

- Implement full route-to-category mapping:
  - Dock feed
  - Thread detail
  - Archive
  - Voice
  - Diagnostics
- Make passive-only/unknown route evidence show `Not checked` unless app
  evidence proves failure.
- Make app-critical route failures affect host and overall display status.
- Show degraded/partial host and category states with plain impact and next
  action copy, not just raw route failure names.
- Add Host Health Detail pushed inside System Health for host-card chevrons.
- Include expandable technical route evidence only below plain category status.
- Wire `Run check` to `AppConnectivityStore.refreshRelayDiagnostics()`.
- Implement non-secret `Copy doctor command`, preferably `rtk make relay-doctor`.
- Refactor `HostsView` into an embeddable Relay Settings surface or replace it
  cleanly with `RelaySettingsView` backed by `HostSettingsStore` and
  `HostSettingsScreenStore`.
- Hide Add/Edit Relay editor until explicit add/edit.
- Confirm before removing the final saved relay host.
- Preserve host test, add, edit, remove, save validation, and host/port-only
  config behavior.
- Push Relay Settings inside System Health when opened from System Health; open
  it as the root task sheet when opened from Dock More.
- Delete or retire any old root Relay-only UI path.
- Add/update automation IDs for System Health, host detail, and Relay Settings.
- Add accessibility labels/traits for health categories, host cards, Run check,
  Copy doctor command, and Relay Settings add/edit/test/remove controls.
- Add `SystemHealthProjectorTests` for category mapping, passive `Not checked`,
  degraded/partial impact copy, next actions, and app-critical route failures.
- Ensure `CodexDockBootstrapView` chip behavior is accounted for: either it
  presents the same `SystemHealthView` locally during bootstrap or delegates to
  the task router once the ready Dock root is active; it must not preserve a
  separate primary raw diagnostics sheet.

Verification (required proof):

- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk swift test --filter ConnectivityDataEngineTests`
- `rtk swift test --filter SystemHealthProjectorTests`
- `rtk swift test --filter DiagnosticsLoggingTests`
- `rtk swift test --filter HostSettingsScreenStoreTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AutomationIDTests`

Docs/comments (propagation; only if needed):

- Update README diagnostics/root-navigation wording if it still describes
  Archive/Hosts/Relay root tabs.

Exit criteria (all required):

- System Health displays all five category statuses from existing evidence.
- Raw route names are not the first-level UX.
- Degraded and partial states explain impact plus the next action in plain
  language.
- System Health category mapping, passive `Not checked`, degraded/partial copy,
  and app-critical route failures have focused projector tests.
- Bootstrap connectivity-chip behavior does not leave a separate primary raw
  diagnostics path after the ready Dock root is available.
- Host Health Detail is reachable from every host-card chevron.
- Technical route evidence appears only below the plain category status.
- `Run check` refreshes route diagnostics and preserves passive-route safety.
- `Copy doctor command` exposes a non-secret command.
- Relay Settings is reachable from More and System Health but is not a root tab.
- Host test, add, edit, remove, save validation, and existing host rows still
  work.
- Removing the final saved relay host requires confirmation.
- Add/edit form is hidden until add/edit.
- Saved config remains host/port only.
- Required tests pass or exact blockers are recorded.

Rollback:

Revert System Health completion and Relay Settings refactor together if
settings cannot be reached without the old root tab.

## Phase 3 - Archived Threads task sheet and batch restore

Goal:

Replace the root Archive tab with a discoverable recovery sheet before cleanup
depends on recovery links.

Work:

This phase refactors the existing archive browser into the `Archived Threads`
task surface, adds search/filter/select, implements bounded batch restore, and
preserves existing single-row restore behavior.

Checklist (must all be done):

- Refactor `ArchiveView` root-tab behavior into reusable Archived Threads sheet
  content or replace it cleanly.
- Remove old root Archive-only navigation path.
- Preserve `.archivedHuman` load path and current archive unavailable/empty
  behavior.
- Preserve existing `ArchiveScreenStore` load/group/restore behavior or migrate
  it into the new sheet owner without changing semantics.
- Add header count/host count.
- Add full-width archived search.
- Add compact host/date filter chips.
- Add date-grouped archived rows with visible row restore.
- Preserve single row restore behavior.
- Add selection mode:
  - Select enters selection mode.
  - Cancel exits selection mode and clears selection.
  - Toolbar Restore selected is disabled when zero selected.
  - Bottom Restore N is primary and disabled when zero selected.
  - Both restore actions run the same operation.
- Add bounded per-row batch restore using existing `thread/unarchive`.
- Put any new production concurrency value in `CodexDockConstants.swift`.
- Add batch restore progress, Stop remaining, full success, partial success,
  Retry failed, and Done states.
- Refresh Dock after successful restore mutations.
- Add/update automation IDs for Archived Threads search, filters, select/cancel,
  row restore, restore selected, progress, Stop remaining, retry failed, and
  completion states.
- Add accessibility labels/traits for archived search, filters, selection mode,
  selected counts, row restore, batch restore, progress, Stop remaining, Retry
  failed, and Done controls.

Verification (required proof):

- Existing `ArchiveScreenStoreTests` still pass or are migrated to equivalent
  Archived Threads tests.
- Existing `ArchiveDataEngineTests` still pass if archive loading is refactored.
- Batch restore tests live in `ArchiveScreenStoreTests` when the existing store
  remains the owner; if implementation creates a separate store, add
  `ArchivedThreadsStoreTests` and put selection/progress/result coverage there.
- Batch restore tests:
  - all success
  - partial failure
  - no false success for failed rows
  - Stop remaining does not start new rows
  - retry failed only retries failed rows
  - Dock refresh after success
- `rtk swift test --filter ArchiveScreenStoreTests`
- `rtk swift test --filter ArchiveDataEngineTests`
- `rtk swift test --filter ArchivedThreadsStoreTests` if a new store owns batch
  restore
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AutomationIDTests`

Docs/comments (propagation; only if needed):

- Update README if it still describes Archive as a root tab.

Exit criteria (all required):

- Archived Threads is reachable from More.
- There is no required root Archive tab to browse archived rows.
- Search, host/date filters, and date grouping work inside the sheet.
- Selection enter/cancel/clear and zero-selected disabled states match
  requirements.
- Single restore and batch restore work with truthful result states.
- Stop remaining, retry failed, full success, and partial success states are
  covered.
- Dock refreshes after restore.
- Required tests pass or exact blockers are recorded.

Rollback:

Revert Archived Threads refactor and restore Archive root only if the full root
IA cutover is also reverted. Do not keep both root Archive and Archived Threads
as live competing browsers.

## Phase 4 - Archive Cleanup preview, Custom age, and Review List

Goal:

Build the destructive-work safety layer without executing archive mutations yet.

Work:

This phase creates the full-scan preview path, candidate/exclusion rules, host
split, Custom age subview, Review List, local search/filter/selection, and
empty/partial/failure states. Archived Threads already exists, so cleanup links
can route to the real recovery sheet.

Checklist (must all be done):

- Add cleanup-specific full active human scan query without changing daily Dock
  `activeSessionMaxPages`; prefer a named
  `.activeHumanFullScan = DockSessionQuery(archived: false, sourceKinds: nil,
  maxPages: nil)` or the exact explicit equivalent at the call site.
- Add `ArchiveCleanupRule`, age model, candidate row/result models, and preview
  snapshot.
- Add `ArchiveCleanupDataEngine` using concurrent per-host loading.
- Reuse row projection/local metadata semantics for status, pinned, Watch label,
  host, repo/workspace, branch, and last activity.
- Implement default rule: `90d`, exclude pinned, running, needs input/approval,
  and Watch label.
- Implement `30d`, `90d`, `1y`, and Custom.
- Implement Custom Age subview with numeric days 1-3650, default 180, Apply,
  Cancel, validation copy, and preview recompute.
- Implement candidate rules exactly:
  - older than selected age
  - active human-scope first implementation
  - human scope confirmed client-side from the mapped session origin/source
    classification; do not rely on `sourceKinds: nil` alone to mean human-only
  - pinned exclusion
  - running exclusion
  - needs input / needs approval exclusion
  - Watch label exclusion
  - Error rows included by default with Error badge/filter visibility
- Implement preview count, host split, preview rows, View all/Review list alias,
  Restore from Archived Threads link, loading, empty, partial, and failed states.
- Implement host split row tap to Review List filtered to that host.
- Implement Review List pushed inside Archive Cleanup with search, filters,
  selectable rows, all-candidates-selected default, selected count, disabled
  zero-selected archive action, back behavior, and excluded-row visibility.
- Keep the primary `Archive N` action disabled while any host preview is still
  loading or unresolved.
- Wire Restore from Archived Threads links by replacing the active task sheet
  with Archived Threads.
- Add automation IDs for cleanup preview, age selector, custom age, exclusions,
  review list, filters, selection, links, and disabled archive state.
- Add accessibility labels/traits for age selection, Custom age validation,
  exclusions, host split rows, Review List filters, selected counts, disabled
  archive state, and recovery links.

Verification (required proof):

- New focused cleanup candidate tests for age, custom age validation, exclusions,
  Error-row inclusion, host split, partial host failure, Archived Threads links,
  and selected counts.
- New `ArchiveCleanupStoreTests` for cleanup preview, selection, disabled
  archive states, and result-state transitions.
- `rtk swift test --filter ArchiveCleanupStoreTests`
- `rtk swift test --filter DockStoreTests` if cleanup touches Dock refresh or
  shared Dock state.
- `rtk swift test --filter AppServerClientTests` if a named query constant or
  query behavior changes.
- `rtk swift test --filter AutomationIDTests`

Docs/comments (propagation; only if needed):

- Add a short comment at the cleanup full-scan query boundary if needed to make
  clear it must not be used for daily Dock refresh.

Exit criteria (all required):

- Opening Archive Cleanup does not archive anything.
- Daily Dock load cap is unchanged.
- Preview computes correct candidates and exclusions.
- Custom age is fully validated and recomputes preview.
- Review List can select/deselect/filter/search candidates.
- `Archive N` is disabled while any host preview is still loading.
- Host split rows open Review List filtered to that host.
- Restore from Archived Threads link switches to the existing Archived Threads
  sheet.
- Partial host failure keeps successful host preview visible.
- No batch mutation code is required for this phase to pass.
- Required tests pass or exact blockers are recorded.

Rollback:

Remove the cleanup preview/review surface and models as one unit. Do not leave a
visible Archive Cleanup entry that cannot preview safely.

## Phase 5 - Archive Cleanup execution and Archive health evidence

Goal:

Turn the preview/review model into truthful bounded bulk archive execution.

Work:

This phase adds confirmation, progress, Stop remaining, per-row result tracking,
partial/full completion, retry failed, Dock refresh, `View archived` routing to
the existing recovery sheet, and Archive category health evidence using the
existing row-level `thread/archive` contract.

Checklist (must all be done):

- Implement confirmation when `N > 100` with count, threshold, exclusions, host
  split, and restore path.
- Implement bounded per-row archive execution using existing
  `DockSessionArchiving.archiveThread`.
- Put any new production concurrency value in `CodexDockConstants.swift`.
- Track per-row pending/running/succeeded/failed/skipped state.
- Track per-host totals and total progress.
- Implement `Stop remaining` so not-started work stops and in-flight work is
  counted accurately.
- Implement full success state with counts, host split, `View archived`, and
  `Done`.
- Implement partial success state with archived count, failed count, failed row
  reasons, `Retry failed`, `View archived`, and `Done`.
- Wire `View archived` to replace the active task sheet with Archived Threads.
- Refresh Dock after successful archive mutations.
- Update System Health Archive category evidence from cleanup preview/execution
  or existing archive state observations.
- Ensure archive execution logs only safe IDs/counts/durations, never prompt
  text, transcript text, secrets, raw audio, or full payloads.
- Add automation IDs for confirmation, progress, stop remaining, retry failed,
  full completion, partial completion, and `View archived`.
- Add accessibility labels/traits for confirmation, progress, Stop remaining,
  Retry failed, full/partial completion, Done, and View archived controls.

Verification (required proof):

- Batch archive tests:
  - all success
  - partial failure
  - no false success for failed rows
  - Stop remaining does not start new rows
  - retry failed only retries failed rows
  - Dock refresh after success
  - System Health Archive evidence updates
  - `View archived` routes to Archived Threads
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk swift test --filter AutomationIDTests`

Docs/comments (propagation; only if needed):

- No broad docs unless README mentions archive capability.

Exit criteria (all required):

- `Archive N` cannot mutate without preview and required confirmation.
- Progress and completion counts match per-row results.
- Stop remaining prevents not-started rows from starting and reports in-flight
  rows truthfully.
- Retry failed retries only failed rows.
- Failed rows stay unarchived and visible.
- `View archived` opens the existing Archived Threads sheet.
- Dock refreshes after successful archive mutations.
- System Health Archive category reflects archive evidence.
- Archive execution logging is safe and contains no prohibited content.
- Confirmation, progress, stop, retry, full completion, partial completion, and
  View archived automation IDs exist.
- Required tests pass or exact blockers are recorded.

Rollback:

Disable/remove execution actions while preserving preview only if execution is
unsafe. Do not leave a visible Archive button that does not run truthfully.

## Phase 6 - Final integration, generated project proof, docs, and review gates

Status: COMPLETE - final verification and review evidence is recorded in the
worklog.

Goal:

Prove the complete product journey and clear the user-requested review gates
before any commit/push decision.

Work:

This phase runs the broadest needed checks, updates live docs that would be
stale, and performs the thermonuclear code review gate required by the user.
The Composer plan review already happened in Phase 0 and must not be deferred to
this final phase.

Checklist (must all be done):

- Run the smallest relevant Swift tests from earlier phases and expand to full
  `rtk swift test` if shared behavior changed broadly.
- Run `rtk npm run test:relay` if relay scripts changed.
- Run `rtk xcodegen generate --spec project.yml` only if project target/config
  changed outside Makefile-owned app targets.
- Run `rtk make app-test SIM='iPhone 17'` if generated app UI behavior or target
  wiring needs simulator proof.
- Migrate or delete stale `CodexDockUITests/CodexDockAutomationSmokeTests.swift`
  root-tab helpers such as `tapRootTab(.relay)` so UI smoke tests drive the
  More-menu task sheets.
- Capture exact blocker if simulator, Xcode, signing, services, or env are
  unavailable.
- Update README or live docs for the new Dock-only root, System Health,
  Archive Cleanup, Archived Threads, and Relay Settings if stale.
- Audit final accessibility labels/traits for every new task sheet, status,
  destructive confirmation, progress state, disabled control, and recovery
  action introduced by the feature.
- After implementation and tests, run thermonuclear code quality review before
  any commit/push decision.
- Do not commit, stage, or push unless the user explicitly asks.

Verification (required proof):

- Phase 0 stage-gate proof retained in final report:
  `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_ARCHITECTURE_PLAN_2026-05-30.md`
- Phase 0 fresh Composer plan review result with `BLOCKING: none`.
- Test command outputs recorded in the final report or worklog.
- Thermonuclear review findings resolved or explicitly reported.

Docs/comments (propagation; only if needed):

- README updates for changed user-visible navigation/diagnostics.
- The plan and worklog must reflect actual implementation/test truth after
  implementation begins.

Exit criteria (all required):

- Every acceptance item from the requirements doc is implemented or explicitly
  blocked with exact evidence.
- All required tests/checks pass or exact blockers are recorded.
- Composer plan review had no blocking findings before implementation.
- Thermonuclear review has run before commit/push.
- No stale live doc still says Archive/Relay are root tabs.
- No unauthorized scope cut exists.

Rollback:

If final checks expose a systemic problem, reopen the earliest phase whose exit
criteria are contradicted. Do not patch the plan to make missing work disappear.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. Prefer the smallest checks that prove behavior.
The phase `Verification` and `Exit criteria` entries above are required proof;
`common-sense; non-blocking` means do not add ceremony that does not prove the
feature. Use simulator/device checks only when UI target or installed behavior
needs them.

## 8.1 Unit tests (contracts)

- Candidate rule tests for age/exclusions/counts.
- Health category projection tests.
- System Health projector tests for category mapping, degraded/partial copy, and
  next actions.
- Batch archive/restore state machine tests.
- Archived Threads batch-restore tests in `ArchiveScreenStoreTests` or
  `ArchivedThreadsStoreTests`, depending on final store ownership.
- Automation ID stability tests.

## 8.2 Integration tests (flows)

- App-server client query/archive/restore tests if contracts change.
- Dock/Archive/Host settings store tests for preserved behavior and new
  refresh/reporting behavior.
- Relay tests only if relay scripts or observability contracts change.

## 8.3 E2E / device tests (realistic)

- `rtk make app-test SIM='iPhone 17'` if app target UI wiring changes enough to
  require generated Xcode proof.
- Physical device checks only through Makefile-owned device targets when
  explicitly needed and available.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Clean cutover in the app UI. No feature flag or fallback tab mode.

## 9.2 Telemetry changes

Use existing `DockLog` categories and connectivity reporting. Add only
sanitized event/count logging for cleanup execution if it helps diagnose
failures. Do not log secrets, prompts, transcripts, raw audio, or full payloads.

## 9.3 Operational runbook

Existing service checks remain canonical:

```sh
rtk make app-server-status
rtk make dock-relay-status
rtk make relay-doctor
```

System Health `Copy doctor command` should copy a non-secret command such as
`rtk make relay-doctor`.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Section 0 scope/acceptance, Section 3 internal anchors,
    Section 5 target architecture, Section 6 call-site audit, Section 7 phase
    order and exit criteria, Section 8 verification, Section 9 rollout, and
    Section 10 decisions.
  - User-requested gates: requirements review, ArcStep auto-plan readiness,
    fresh Composer plan review before implementation, auto-implement after plan
    approval, and thermonuclear review before any commit/push decision.
- Findings summary:
  - Pre-implementation gates were incorrectly parked in the final integration
    phase.
  - Archived Threads was scheduled after cleanup links and completion paths that
    already depended on it.
  - Phase 1 exposed four More-menu tasks before the plan guaranteed every entry
    opened a real sheet root.
  - Some phase exit criteria were weaker than their own checklists, especially
    host-detail evidence, Relay Settings preservation, Stop remaining, Retry
    failed, safe logging, and automation IDs.
  - Current-architecture preservation tests under-named `ArchiveScreenStore`,
    `ArchiveDataEngine`, `HostSettingsScreenStore`, and `ConnectivityDataEngine`.
  - Ready-Dock connectivity-chip routing needed one canonical owner path.
- Integrated repairs:
  - Added Phase 0 for ArcStep ready and fresh Composer 2.5 Fast plan review
    before any implementation.
  - Reordered implementation so Archived Threads and batch restore land before
    Archive Cleanup preview/execution links rely on the recovery sheet.
  - Required Phase 1 to create real titled task-sheet roots for all four More
    menu entries, with unsafe bulk actions disabled until their safety phases.
  - Tightened Phase 2, Phase 3, and Phase 5 exit criteria for host detail,
    technical evidence placement, doctor command, Relay Settings preservation,
    selection disabled states, Stop remaining, Retry failed, safe logging, and
    automation IDs.
  - Added the missing screen-store/data-engine preservation anchors and test
    filters.
  - Made the ready-Dock connectivity chip delegate to the root task router; any
    non-Dock/bootstrap local presentation must show the same `SystemHealthView`.
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

# 10) Decision Log (append-only)

## 2026-05-30 - Composer plan review accepted implementation plan

Context

The user required a fresh Composer 2.5 Fast review of the implementation/test
plan before ArcStep implementation could begin.

Options

- Treat the first `BLOCKING: none` result as sufficient and start
  implementation.
- Fold in non-blocking Composer feedback, rerun the plan review, and record the
  final accepted run directory.

Decision

Fold in the feedback and proceed only after the exact current plan receives a
fresh Composer 2.5 Fast result with `BLOCKING: none`.

Evidence

- First plan review:
  `/tmp/fresh-consult/codex-dock-plan-review-20260530T214254Z-dWgZrr/final.txt`
  - `VERDICT: pass-with-notes`
  - `BLOCKING: none`
- Second plan review after folding first-pass notes:
  `/tmp/fresh-consult/codex-dock-plan-rereview-20260530T214610Z-SISZhK/final.txt`
  - `VERDICT: pass-with-notes`
  - `BLOCKING: none`
- Final acceptance check after folding second-pass notes:
  `/tmp/fresh-consult/codex-dock-plan-finalcheck-20260530T215024Z-QNEbf4/final.txt`
  - `VERDICT: pass-with-notes`
  - `BLOCKING: none`
- Exact-current-plan acceptance check after recording final review evidence:
  `/tmp/fresh-consult/codex-dock-plan-finalcheck2-20260530T215302Z-kpCkh9/final.txt`
  - `VERDICT: pass`
  - `BLOCKING: none`

Consequences

Implementation may begin under the approved ArcStep plan. Non-blocking notes
were folded into the plan where they clarified phase checklists, owner paths,
test homes, and review evidence.

Follow-ups

ArcStep auto-implement/implement-loop has completed for this feature. Final
verification and thermonuclear review evidence is recorded in the worklog before
any commit/push decision.

## 2026-05-30 - Implementation, verification, and review gates complete

Context

Implementation followed the approved ArcStep plan after the requirements and
plan Composer gates reported no blocking findings.

Decision

Mark the plan complete because the root task-router cutover, System Health,
Relay Settings, Archived Threads, Archive Cleanup, tests, docs, and
thermonuclear review gate are complete under the accepted scope.

Evidence

- Worklog:
  `docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_ARCHITECTURE_PLAN_2026-05-30_WORKLOG.md`
- Requirements checklist:
  `docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_REQUIREMENTS_2026-05-30.md#20-acceptance-checklist`
- `rtk swift test --filter SystemHealthProjectorTests` - passed; 4 tests, 0 failures.
- `rtk swift test` - passed; 320 tests, 5 expected skips, 0 failures.
- `rtk make app-test SIM='iPhone 17'` - passed; command exited 0.
- `rtk git diff --check` - passed.
- Root-tab stale-code grep over `CodexDock`, `CodexDockTests`,
  `CodexDockUITests`, and `README.md` found no matches.
- Thermonuclear review findings were fixed and re-verified before any
  commit/push decision.

Consequences

No root Archive/Relay fallback remains in the shipped app path. `rtk npm run
test:relay` was not required because this implementation did not touch relay
scripts. No files were staged, committed, or pushed.

## 2026-05-30 - Consistency pass repaired phase ordering and gates

Context

Two cold readers found that the plan still had execution-order contradictions:
Composer plan review was in the final phase instead of before implementation,
Archived Threads landed after cleanup links depended on it, and some phase exit
criteria were less complete than their checklists.

Options

- Keep the old phase order and rely on later implementation judgment.
- Move pre-implementation gates and recovery-sheet dependencies into the
  authoritative phase order now.

Decision

Repair the plan before implementation: Phase 0 now owns ArcStep ready plus
Composer plan review, Phase 1 creates real task sheet roots for every More
entry, Phase 3 implements Archived Threads before cleanup links use it, Phase 4
builds cleanup preview/review, and Phase 5 implements cleanup execution.

Consequences

The implementation order is longer but no longer requires dead menu entries,
missing recovery links, or late plan approval after code has already started.
The plan remains a clean UI cutover with no root Archive/Relay fallback.

Follow-ups

Completed: ArcStep consistency receipt, readiness gate, and fresh Composer 2.5
Fast plan review all finished before implementation started.

## 2026-05-30 - Requirements approved for ArcStep planning

Context

The user requested a requirements doc from the worklog and mockups, then a fresh
Composer 2.5 Fast review before ArcStep planning.

Options

- Ask the user to approve the North Star after Composer review.
- Treat the user's explicit pipeline instruction plus Composer `BLOCKING: none`
  as approval to proceed into ArcStep auto-plan.

Decision

Proceed into ArcStep auto-plan using this plan as `DOC_PATH`.

Consequences

The plan moved from `status: active` to `status: complete` after implementation,
verification, and review gates finished without unauthorized scope cuts.

Follow-ups

No follow-up is required for this feature's accepted scope. Do not commit,
stage, or push unless the user explicitly asks.
