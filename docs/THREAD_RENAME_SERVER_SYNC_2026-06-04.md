---
title: "Codex Dock - Thread Rename Server Sync - Architecture Plan"
date: 2026-06-04
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [Composer 2.5 Fast, thermo-nuclear-code-quality-review]
doc_type: architectural_change
related:
  - https://developer.apple.com/design/human-interface-guidelines/context-menus
  - https://developer.apple.com/design/human-interface-guidelines/edit-menus
  - https://developer.apple.com/design/human-interface-guidelines/sheets
  - https://developer.apple.com/design/human-interface-guidelines/alerts
  - /Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/common.rs
  - /Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs
  - /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs
---

# TL;DR

Outcome:
- Codex Dock lets a user rename a human-started thread from the Dock list or thread detail view, sends the rename to Codex through `thread/name/set`, and displays the server-returned title after the Dock card stream refreshes.

Problem:
- Codex already owns thread names, but Codex Dock has no UI, Swift command path, relay route, or tests for `thread/name/set`. Local metadata can label, pin, and color rows, but it must not become a second title store.

Approach:
- Add one typed mutation path: Swift UI -> `DockStore.rename` -> `ClientCommandEngine.rename` -> `AppServerThreadCommandClient.renameThread` -> relay `thread/name/set` -> Codex app-server `thread/name/set`.
- After Codex accepts the mutation, the relay reconciles Dock and Archive projections so `ThreadDTO.name` becomes `DockThreadCardDTO.title`, then `DockRowViewModel.title`.
- Keep the UI subtle but discoverable: a row context-menu action plus a detail toolbar pencil both open the same focused rename sheet.

Plan:
- Add the relay route and projection refresh.
- Add Swift DTO/client/command/store/UI support.
- Add targeted Swift and Node tests, then prove the full path in the iPhone 17 simulator against real relay data.
- Run the requested fresh consults, thermonuclear review, commit/push, update the `home` checkout, and restart/update the local relay.

Non-negotiables:
- No local title shadow. The Dock card stream remains the only displayed title truth.
- No app direct connection to raw authenticated `:4500`; app traffic stays relay-backed on `:4510`.
- No raw names, prompt text, bearer tokens, or payload dumps in logs.
- No compatibility shim or alternate route. The route is `thread/name/set`.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-06-04
external_research_grounding: done 2026-06-04
deep_dive_pass_2: done 2026-06-04
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:824a6612681cd425c4e6c40918f7d6832f9a57072809eae0a7c24f7b668992da",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-04T03:07:58Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:1ed2ca413a0125c93bcba7ad0f2ea000d4710db4b124276942af8205070e5e79",
      "completed_at": "2026-06-04T03:08:05Z",
      "doc_hash_after": "sha256:010add0067ab131217afda45b465345f8227f8da1b541eb127b2e0f42747662c"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-04T03:08:09Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:010add0067ab131217afda45b465345f8227f8da1b541eb127b2e0f42747662c",
      "completed_at": "2026-06-04T03:08:48Z",
      "doc_hash_after": "sha256:b56e91f4ff74f48d77bb397686efcff876d71abdbbed8030a19a50a1bca38229"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-04T03:08:53Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:b56e91f4ff74f48d77bb397686efcff876d71abdbbed8030a19a50a1bca38229",
      "completed_at": "2026-06-04T03:09:02Z",
      "doc_hash_after": "sha256:65f9947786d662d0c9c6a881f302a13e95e544843b6bb33cdfa1b510b5f4ae29"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-04T03:09:11Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:65f9947786d662d0c9c6a881f302a13e95e544843b6bb33cdfa1b510b5f4ae29",
      "completed_at": "2026-06-04T03:09:19Z",
      "doc_hash_after": "sha256:7be2ebeec0964ebf948ff3d887527cc5368dc8794ab83c0baf28726fc95aebbf"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-04T03:09:24Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:7be2ebeec0964ebf948ff3d887527cc5368dc8794ab83c0baf28726fc95aebbf",
      "completed_at": "2026-06-04T03:09:35Z",
      "doc_hash_after": "sha256:b65a1ca199696da0f320bb87368a8d8f180fd3d3fffea2f356a8f1a070d3c1c1"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

If a user renames a Dock row to a non-empty name from either the row menu or the thread detail toolbar, Codex Dock sends exactly one `thread/name/set` JSON-RPC request with `{threadId, name}` through the relay to the owning Codex app-server session. After success, the visible Dock row and open detail header show the name returned by the relay's refreshed card stream, and a fresh read from Codex reports the same name.

## 0.2 In scope

- Add rename entry points to the active Dock row context menu and open thread detail toolbar.
- Add one focused rename sheet with a text field, Cancel, and Save.
- Add typed Swift request/response DTOs and `AppServerClient.threadSetName`.
- Add command/store wiring so rename uses the existing host resolution and action-error pattern.
- Add relay support for `thread/name/set`, including human-thread validation and endpoint routing through the owning live or history app-server.
- Reconcile Dock and Archive projections after a successful rename.
- Add focused Swift, Node, and simulator evidence.
- Commit/push and refresh both the `home` deployment checkout and local running relay after the implementation is verified.

## 0.3 Out of scope

- Renaming archived-only rows from the archive UI. Codex `thread/name/set` currently updates non-archived metadata only; archived rows continue to display whatever name Codex already stores.
- Batch rename, auto-generated names, inline list editing, keyboard shortcuts, undo/redo, or a separate title database.
- Any app-server protocol changes in `/Users/aelaguiz/workspace/codex`; that repo already exposes `thread/name/set`.
- Any phone-side persistence of relay identity or raw app-server bearer tokens.

## 0.4 Definition of done (acceptance evidence)

- Fresh consult #1, `Cursor Agent composer 2.5 fast`, reviews the pre-implementation plan.
- `$arch-step auto-plan` receipts show research, deep-dive pass 1, deep-dive pass 2, phase-plan, and consistency-pass complete.
- Fresh consult #2, `Cursor Agent composer 2.5 fast`, reviews the completed arch-step plan.
- `rtk npm run test:relay` passes.
- `rtk swift test --filter AppServerClientTests` passes.
- `rtk swift test --filter DockStoreTests` passes.
- `rtk swift test --filter ThreadDetailStoreTests` passes if detail UI/store plumbing changes touch thread detail behavior.
- `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1` passes.
- Simulator proof against real data shows: open real Dock row -> rename through app UI -> app sends `thread/name/set` through relay -> Codex read returns new name -> Dock row/detail title update from `dock/update` or refresh.
- Thermonuclear code review runs and all must-fix findings are repaired or explicitly re-reviewed clean.
- Mac branch is committed and pushed.
- `/home/aelaguiz/workspace/codex-client` is fast-forwarded from the pushed branch.
- The local Dock relay is running the updated code.

## 0.5 Key invariants (fix immediately if violated)

- Dock title source of truth is relay card truth only.
- The app never persists rename state in local metadata.
- Rename failures are fail-loud and visible through existing action-error UI.
- Relay validates human-started thread identity before forwarding rename.
- The app sends WebSocket requests to the Dock relay, not the raw authenticated app-server.
- Logs may include public IDs and route names, but not raw user-entered thread names.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correctness: the name must change in Codex, not only in Codex Dock.
2. Single source of truth: the UI must wait for server card truth instead of inventing a local title.
3. Discoverable, quiet UX: rename is available where users naturally look, without turning every row into an editor.
4. Contract unity: Swift, relay, tests, and observability use the exact `thread/name/set` route and `{threadId, name}` shape.
5. Operational proof: simulator evidence must use real relay/app-server data, not preview rows.

## 1.2 Constraints

- Codex app-server already normalizes and validates names; the client should trim obvious whitespace and disable empty Save, but server remains authoritative.
- Relay must route to the owning endpoint because loaded live sessions may be owned by a live app-server, while unloaded history sessions are owned by the history app-server.
- Archive projection refresh after rename is cheap and keeps card truth consistent, but archive UI rename is not introduced.
- UI must avoid large new surfaces in `DockView.swift`, which is already large.
- Existing Makefile targets are the runnable source of truth.

## 1.3 Architectural principles (rules we will enforce)

- Add typed route wrappers instead of sending raw JSON-RPC route strings from stores or views.
- Keep user input validation at the UI/store boundary and canonical validation at Codex app-server.
- Keep UI state transient. Only the server-owned card stream can make a renamed title durable in the app.
- Reuse `AppServerHostConnector`, `ClientCommandEngine`, and `DockStore` action patterns.
- Use existing relay logger and observability contracts; do not add direct `console.error`.

## 1.4 Known tradeoffs (explicit)

- A sheet is one extra tap versus inline editing, but it avoids accidental list edits, works well on iPhone, and gives a clear Save/Cancel boundary.
- Context menu alone is too hidden; adding a detail toolbar pencil makes the action discoverable without cluttering dense Dock rows.
- Refreshing both Dock and Archive after rename is slightly more work than Dock-only, but prevents stale card truth when the same thread moves between views.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

- Codex app-server supports `thread/name/set` and emits `thread/name/updated`.
- Codex Dock reads `ThreadDTO.name`.
- The relay maps thread names into card titles.
- `ThreadCardRowProjector` maps `DockThreadCardDTO.title` into `DockRowViewModel.title`.
- Dock local metadata owns pin, label, rail, and order only.

## 2.2 What's broken / missing (concrete)

- No Swift method constant for `thread/name/set`.
- No typed Swift DTO/client function for `{threadId, name}`.
- No command/store method that renames via the selected row host.
- No app UI to initiate rename.
- No relay handler to forward `thread/name/set`.
- No post-rename projection reconciliation.
- No tests proving rename reaches Codex and returns through UI card truth.

## 2.3 Constraints implied by the problem

- Do not solve this by changing local metadata; that would create a second title owner.
- Do not call Codex directly from the app; the relay owns bearer credentials and session routing.
- Do not implement a custom app-server route; Codex already has the route.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- Apple Human Interface Guidelines, Context menus: context menus provide item-specific actions without cluttering the interface, but they are hidden by default and should also be available in the main interface. Adopted: row context menu plus detail toolbar action.
- Apple Human Interface Guidelines, Edit menus: custom commands should be short verbs or verb phrases and use system interactions. Adopted: menu label `Rename`.
- Apple Human Interface Guidelines, Sheets: official page is JavaScript-rendered, but the iOS pattern is appropriate for a bounded editing task that needs focused input and Cancel/Save.
- Apple Human Interface Guidelines, Alerts: alerts can include text fields, but alerts are better for urgent situations or resolving a problem. Rejected for rename because this is a normal editing flow, not an exceptional warning.
- Fresh consult #1 run directory:
  `/tmp/fresh-consult/thread-rename-plan-20260604T000000Z-ODiajQ`.
  Result: `VERDICT: pass-with-notes`, `BLOCKING: none`; non-blocking notes are
  folded into DTO placement, reconcile-only relay state, and projection-owned
  test assertions.

## 3.2 Internal ground truth (code as spec)

- Codex protocol:
  - `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/common.rs` maps `ThreadSetName` to `thread/name/set`.
  - `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs` defines `ThreadSetNameParams { thread_id: String, name: String }` with TypeScript casing `{threadId, name}`.
  - `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs` normalizes names, rejects empty names, writes metadata, and emits `thread/name/updated`.
- Swift client:
  - `CodexDock/AppServer/AppServerMethods.swift` owns route constants.
  - `CodexDock/AppServer/AppServerClient.swift` owns typed JSON-RPC wrappers.
  - `CodexDock/AppServer/ThreadDTO.swift` already includes `name`.
  - `CodexDock/AppServer/ThreadDetailDTO.swift` owns the existing archive and
    unarchive mutation DTOs, so rename mutation DTOs should live there too.
  - `CodexDock/State/AppServerThreadCommandClient.swift` owns app-server thread mutations.
  - `CodexDock/State/DockStore.swift` owns row actions and action errors.
  - `CodexDock/Features/Dock/DockRowContextMenu.swift` owns row contextual actions.
  - `CodexDock/Features/Session/SessionDetailView.swift` owns the visible thread detail toolbar/header surface.
- Relay:
  - `scripts/dock-relay.mjs` owns downstream method dispatch.
  - `scripts/dock-relay-thread-data.mjs` owns endpoint routing and app-server calls.
  - `scripts/dock-relay-state-engine.mjs` owns post-mutation projection reconciliation.
  - `scripts/dock-relay-state-views.mjs` already turns `thread.name` into card title.

## 3.3 Decision gaps that must be resolved before implementation

- None. Repo evidence and requested behavior settle the route, source of truth, UI entry points, and proof scope.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `CodexDock/AppServer/**`: typed JSON-RPC route constants, DTOs, and client wrappers.
- `CodexDock/State/**`: app state stores, command clients, stream reconcilers, and projection projectors.
- `CodexDock/Features/Dock/**`: Dock list, filters, row view, row context menu, and task sheets.
- `CodexDock/Features/Session/**`: thread detail and composer.
- `scripts/dock-relay*.mjs`: relay method dispatch, app-server routing, projection state, controlled fixtures, and tests.
- `CodexDockTests/**`: Swift unit tests and test support.

## 4.2 Control paths (runtime)

- Current title read path:
  - Codex app-server thread metadata -> relay thread read/list -> `normalizeThread` -> `DockThreadCardDTO.title` -> Swift stream client -> `ThreadCardRowProjector` -> `DockRowViewModel.title` -> Dock row/detail header.
- Current mutation path:
  - Archive/unarchive use `DockStore.archive` or archive stores -> `ClientCommandEngine` -> `AppServerThreadCommandClient` -> `AppServerClient` -> relay -> Codex.
- Missing rename path:
  - There is no UI action, typed command, or relay route for rename.

## 4.3 Object model + key abstractions

- `DockRowViewModel.title` is display-only projected card truth.
- `LocalThreadMetadata` intentionally excludes title.
- `ThreadArchiveCommanding` is the current thread mutation protocol, but its name is too archive-specific once rename is added.
- `RelayStateEngine.handleArchiveMutation` is the existing example for mutation-triggered projection reconciliation.

## 4.4 Observability + failure behavior today

- Swift route observability is listed in `CodexDock/Diagnostics/ObservabilityContract.swift`.
- Relay route observability is listed in `scripts/dock-relay-observability-contract.mjs`.
- Dock action failures appear in `ActionErrorBanner` through `DockStore.actionError`.
- Relay diagnostics must use `scripts/dock-relay-logger.mjs`.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Dock row context menu:

```text
Thread row
  long press / secondary click
    Pin
    Rename
    Mark Watch
    Clear Label
    Archive
    Color >
```

Detail toolbar:

```text
< Back          Thread          [pencil]

Terminal icon   Current Title
                repo - branch
```

Rename sheet:

```text
Rename Thread
[ Name text field prefilled with current title ]

Cancel                              Save
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- Add `CodexDock/Features/Dock/DockRenameThreadSheet.swift` for the shared sheet and draft model.
- Update existing Swift route/client/store/UI files in place.
- Update existing relay method/routing/state files in place.
- Update existing test files in place, adding new tests beside archive and projection tests.

## 5.2 Control paths (future)

Rename command path:

```text
Dock row context menu OR detail toolbar
  -> DockRenameThreadSheet
  -> DockStore.rename(row, to:)
  -> ClientCommandEngine.rename(row, to:on:)
  -> AppServerThreadCommandClient.renameThread(threadID, name:on:)
  -> AppServerClient.threadSetName(params:)
  -> relay handleRequest("thread/name/set")
  -> setThreadName(config, params)
  -> owning Codex app-server "thread/name/set"
  -> RelayStateEngine.handleThreadNameMutation
  -> reconcile Dock and Archive projections
  -> dock/update / dock/resync
  -> ThreadCardRowProjector
  -> visible row/detail title
```

## 5.3 Object model + abstractions (future)

- Add `ThreadSetNameParams` with Swift properties `threadId` and `name` beside
  the existing archive/unarchive mutation DTOs in `ThreadDetailDTO.swift`.
- Add `ThreadSetNameResponseDTO` for the empty result shape Codex returns.
- Split or broaden the mutation protocol so archive and rename are both thread commands without adding parallel command clients.
- Keep the rename draft as transient SwiftUI state only.

## 5.4 Invariants and boundaries

- Rename success means the server accepted the mutation; visible title success means the Dock projection refreshed with the server name.
- The app may optimistically keep the sheet busy, but it must not replace row titles locally.
- Empty names are blocked in the sheet/store and still rejected by Codex if somehow sent.
- Relay endpoint routing follows `endpointForThread`; direct history-only forwarding is not enough for live-loaded sessions.
- `RelayStateEngine.handleThreadNameMutation` is reconcile-only: it should
  reconcile Dock and Archive with reason `thread/name/set`, not write local card
  title state itself.
- `thread/name/set` is app-critical and passive-only for probing because it mutates state and cannot be auto-probed.

## 5.5 UI surfaces (ASCII mockups, if UI work)

The production UI remains dense and work-focused:

```text
Dock
Search...

[row] "Investigate relay timeout"        Needs input
      repo - branch                      2m ago

Context menu: Rename opens the same sheet as detail pencil.
Detail pencil is icon-only with accessibility label "Rename Thread".
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Surface | File | Disposition |
| --- | --- | --- |
| Swift route constants | `CodexDock/AppServer/AppServerMethods.swift` | Add `threadNameSet = "thread/name/set"`. |
| Swift DTOs | `CodexDock/AppServer/ThreadDetailDTO.swift` | Add `ThreadSetNameParams` and `ThreadSetNameResponseDTO` beside archive/unarchive mutation DTOs. |
| Swift JSON-RPC client | `CodexDock/AppServer/AppServerClient.swift` | Add typed `threadSetName`. |
| Swift observability | `CodexDock/Diagnostics/ObservabilityContract.swift` | Add passive-only app-critical rename route. |
| Swift system health | `CodexDock/Features/Status/SystemHealthProjector.swift` | Include `thread/name/set` in the app-critical thread mutation health grouping. |
| Thread command client | `CodexDock/State/AppServerThreadCommandClient.swift` | Add rename command using existing host connector and request failure mapping. |
| Command engine | `CodexDock/Commands/ClientCommandEngine.swift` | Add rename method and missing-command error wording. |
| Dock store | `CodexDock/State/DockStore.swift` | Add `rename(row,to:)`, validate non-empty, call command engine, refresh on success. |
| Dock row menu | `CodexDock/Features/Dock/DockRowContextMenu.swift` | Add `Rename` action with `pencil` icon. |
| Dock view | `CodexDock/Features/Dock/DockView.swift` | Hold rename sheet state, pass row-menu callback, and pass detail-toolbar callback into `SessionDetailView`; keep additions small. |
| Rename sheet | `CodexDock/Features/Dock/DockRenameThreadSheet.swift` | New focused sheet component. |
| Detail view | `CodexDock/Features/Session/SessionDetailView.swift` | Add optional toolbar rename button that calls back with `store.row`; no command execution in detail view. |
| Automation IDs | `CodexDock/Automation/AutomationID.swift` | Add row rename action and sheet/button/field IDs. |
| Relay dispatch | `scripts/dock-relay.mjs` | Add `thread/name/set` case. |
| Relay app-server routing | `scripts/dock-relay-thread-data.mjs` | Add `setThreadName` beside archive/unarchive. |
| Relay state engine | `scripts/dock-relay-state-engine.mjs` | Add reconcile-only post-rename Dock/Archive reconciliation method with reason `thread/name/set`. |
| Relay observability | `scripts/dock-relay-observability-contract.mjs` | Add route config. |
| Swift tests | `CodexDockTests/AppServerClientTests.swift`, `CodexDockTests/DockStoreTests.swift`, `CodexDockTests/ClientCommandEngineTests.swift`, `CodexDockTests/DiagnosticsLoggingTests.swift`, `CodexDockTests/SystemHealthProjectorTests.swift`, maybe detail/UI tests | Add typed request, store behavior, command wiring, observability, and health grouping coverage. |
| Node tests | `scripts/dock-relay-state-subscriptions.test.mjs`, `scripts/dock-relay-card-contract.test.mjs` | Add reconciliation and end-to-end relay rename projection coverage. |
| Simulator proof | Makefile-owned simulator commands | Use `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1` and real relay data proof. |

## 6.2 Migration notes

- Prefer adding a separate `ThreadRenameCommanding` protocol and injecting it only where rename is needed, so archive-only stores and archive-only test fakes do not grow unnecessary rename behavior.
- No persisted schema migration is needed because no local title field is introduced.
- No Codex app-server change is needed.
- No XcodeGen project update is needed for a Swift file under `CodexDock`; `project.yml` includes the whole folder.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

- Existing archive mutation pattern is the template for rename mutation wiring.
- Existing Dock action-error and refresh pattern is the template for rename failure and success handling.
- Existing card stream projection remains the only display update path.
- Existing route observability contracts must include rename wherever archive/unarchive are listed.
- Existing system-health route grouping must include rename wherever thread mutations are summarized for app-critical health.
- Tests for rename title changes must assert projection refresh from relay/server
  state, not a local Swift title mutation.
- Deep-dive pass 1 disposition: include both row context menu and detail toolbar
  entry points because they share one sheet and one store command, so the
  discoverability improvement does not create a second mutation path.
- Deep-dive pass 2 disposition: keep `handleThreadNameMutation` reconcile-only
  and place all visible title proof in relay card projection tests; this
  preserves the single title source while still proving post-mutation refresh.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
## Phase 0 - Planning And External Review

Status: COMPLETE

Work:
- Lock this plan with current repo evidence, external UX research, and Codex app-server route proof.
- Fresh consult #1 is complete with `BLOCKING: none`.
- `$arch-step auto-plan` receipts are complete and the stage gate reports
  `READY next=implement-loop`.
- Fresh consult #2 is complete with `BLOCKING: none`.

Checklist (must all be done):
- Fresh consult #1 reviews the draft plan with `agent --model "composer-2.5-fast"`.
- `$arch-step auto-plan` receipts are minted for all required planning stages.
- Fresh consult #2 reviews the completed arch-step plan with `agent --model "composer-2.5-fast"`.

Exit criteria (all required):
- Section 3.3 has no unresolved decisions.
- `arch_stage_gate.py ready --doc docs/THREAD_RENAME_SERVER_SYNC_2026-06-04.md` exits 0.

## Phase 1 - Relay Route And Projection Truth

Status: COMPLETE

Work:
- Implement `thread/name/set` relay forwarding and post-mutation projection reconciliation.

Checklist (must all be done):
- Add `setThreadName(config, params)` with threadId/name validation, `assertHumanThreadID`, and `endpointForThread` routing.
- Add `thread/name/set` dispatch in `scripts/dock-relay.mjs`.
- Add `RelayStateEngine.handleThreadNameMutation`.
- Add relay route observability.
- Add Node tests proving rename forwards and card title refreshes from server state.

Exit criteria (all required):
- `rtk npm run test:relay` passes after Phase 1 and remains passing after later phases.

## Phase 2 - Swift Command And UI

Status: COMPLETE

Work:
- Implement typed Swift route support and the row/detail rename UX.

Checklist (must all be done):
- Add route constant, DTOs, and typed app-server client method.
- Add command client/store rename path.
- Add `DockRenameThreadSheet`.
- Add row context menu `Rename`.
- Add detail toolbar pencil `Rename Thread`.
- Pass detail rename intent from `SessionDetailView` back to `DockView`; keep command execution in `DockStore`.
- Add automation identifiers for the sheet and rename controls.

Exit criteria (all required):
- Save is disabled for empty trimmed names.
- Cancel dismisses without mutation.
- Success dismisses the sheet and refreshes Dock card truth.
- Failure keeps the user in a recoverable state and shows action error.

## Phase 3 - Focused Automated Tests

Status: COMPLETE

Work:
- Cover the new route and store behavior without broad snapshot churn.

Checklist (must all be done):
- AppServerClient test asserts method `thread/name/set` and params `{threadId, name}`.
- ClientCommandEngine test asserts rename uses the injected renamer and keeps archive/unarchive wiring intact.
- DockStore test asserts rename command call, refresh, and server-owned title update.
- DockStore test asserts failure shows action error and does not locally retitle the row.
- DiagnosticsLogging test asserts observability coverage includes `thread/name/set`.
- SystemHealthProjector test asserts rename failure maps into the intended app-critical health category without exposing raw route names.
- Relay state test asserts rename mutation reconciles Dock and Archive.
- Relay card contract test asserts rename response plus `dock/update` carries the new server title.
- Run `rtk swift test --filter AppServerClientTests`.
- Run `rtk swift test --filter DockStoreTests`.
- Run `rtk swift test --filter ThreadDetailStoreTests` if detail store behavior changes.
- Run `rtk npm run test:relay`.

Exit criteria (all required):
- All required focused checks pass with current code.

## Phase 4 - Simulator Proof Against Real Data

Status: COMPLETE

Work:
- Prove the shipped app path on `iPhone 17` against the real local relay/app-server.

Checklist (must all be done):
- Start or reuse services with `rtk make services`.
- Confirm `rtk make app-server-status` and `rtk make dock-relay-status`.
- Launch updated app with `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`.
- Use simulator UI to rename a real Dock thread through app controls, not preview rows.
- Verify relay/app-server state reports the new name.
- Verify Dock row/detail UI reflects the new server name.
- Restore the thread name if the proof uses a temporary unique name on an existing real thread.

Exit criteria (all required):
- Simulator evidence proves the full UI -> relay -> Codex -> UI loop.

## Phase 5 - Review, Commit, Push, And Deploy Relay

Status: IN PROGRESS

Work:
- Run the requested final review, commit, push, and update runtime deployments.

Checklist (must all be done):
- Run thermonuclear code review.
- Repair all must-fix findings and re-run impacted checks.
- Stage explicit touched paths only.
- Commit with a clear message.
- Push the Mac branch.
- Fast-forward `/home/aelaguiz/workspace/codex-client` from the pushed branch.
- Restart or refresh the local running Dock relay so it uses the new code.
- Verify relay status after update.

Exit criteria (all required):
- `rtk git status --short` shows no uncommitted task changes except user-owned unrelated work if intentionally left.
- Home checkout and local relay report the pushed implementation.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

- Unit route proof:
  - `rtk swift test --filter AppServerClientTests`
- Store/action proof:
  - `rtk swift test --filter DockStoreTests`
- Detail regression proof when touched:
  - `rtk swift test --filter ThreadDetailStoreTests`
- Relay proof:
  - `rtk npm run test:relay`
- App build/launch proof:
  - `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`
- Real simulator proof:
  - Use the installed app against the local Dock relay and real Codex app-server data.
  - Verify the server state after rename, not just UI text.
- Review proof:
  - Fresh consults before implementation and after arch-step plan.
  - Thermonuclear review after implementation and tests.

# 9) Rollout / Ops / Telemetry

- No feature flag is planned; this is a small additive command on an existing Codex route.
- Observability route contracts must list `thread/name/set` as app-critical and passive-only.
- Failure handling uses existing user-visible action error UI.
- Local relay update happens after commit/push by restarting or refreshing the Makefile-managed service.
- Home deployment update must be a fast-forward pull from the pushed Mac branch.

# 10) Decision Log (append-only)

- 2026-06-04 - Intent-derived: Use `thread/name/set` because Codex app-server already defines and implements this exact route. No custom Codex-side route is needed.
- 2026-06-04 - Intent-derived: Keep Dock title server-owned. Local metadata remains limited to label, pin, rail, and order.
- 2026-06-04 - Intent-derived: Use row context menu plus detail toolbar pencil. Apple context menu guidance says context menus avoid clutter but are hidden, so the same command also needs a main-interface path.
- 2026-06-04 - Intent-derived: Exclude archived-only rename UI because Codex `thread/name/set` updates non-archived metadata; adding archive rename would require a different app-server behavior decision.
- 2026-06-04 - Fresh consult #1: Composer 2.5 Fast returned `VERDICT: pass-with-notes`, `BLOCKING: none`. Adopted its non-blocking notes by making mutation DTO placement follow `ThreadDetailDTO.swift`, documenting `handleThreadNameMutation` as reconcile-only, and keeping title-change tests projection-owned.
- 2026-06-04 - Fresh consult #2: Composer 2.5 Fast returned `VERDICT: pass-with-notes`, `BLOCKING: none`, and confirmed the stamped plan is ready for implementation. Adopted its doc-drift note by marking Phase 0 complete.
- 2026-06-04 - Implementation proof: Relay, Swift command/UI, focused tests, simulator real-data rename proof, and post-proof title restoration completed. The simulator proof covered both row context-menu rename and Thread Detail toolbar rename against real relay-backed thread `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- 2026-06-04 - Final review: Thermonuclear review found and repaired two maintainability issues: the opt-in UI proof moved out of the smoke test file, and `ClientCommandEngine` now uses explicit rename wiring instead of a runtime cast. Fresh consult #3 returned `VERDICT: pass-with-notes`, `BLOCKING: none`; its detail-toolbar UI proof note was closed before commit.

<!-- arch_skill:block:consistency_pass:start -->
- Decision-complete: yes
- Unresolved decisions: none
- Decision: proceed to implement? yes
- Notes: The plan has a single upstream route, a single projected title source,
  resolved active-vs-archive scope, resolved row/detail UX entry points,
  reconcile-only relay mutation handling, and explicit Swift, Node, simulator,
  review, commit, push, and home-update proof gates.
<!-- arch_skill:block:consistency_pass:end -->
