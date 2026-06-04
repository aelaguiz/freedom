---
title: "Codex Dock - Lightning-Fast Dock Rendering - Architecture Plan"
date: 2026-06-04
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [model-consensus, composer-2.5-fast, thermo-nuclear-code-quality-review]
doc_type: architectural_change
related:
  - docs/IPHONE_17_PRO_DOCK_LAG_PROFILE_WORKLOG_2026-06-04.md
  - docs/DOCK_LIGHTNING_FAST_ARCHITECTURE_FIX_PLAN_2026-06-04_WORKLOG.md
  - .arch_skill/model-consensus/dock-lightning-fast-20260604T181258Z/round-03/model-a-final.md
  - .arch_skill/model-consensus/dock-lightning-fast-20260604T181258Z/round-03/model-b-final.md
  - /tmp/fresh-consult/dock-lightning-fast-plan-rerun-20260604TRzTiNn/final.txt
  - /tmp/fresh-consult/dock-lightning-fast-arch-plan-20260604T211426Z-gpvW9n/final.txt
---

# TL;DR

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-06-04
Verdict (code): COMPLETE
Manual QA: n/a (non-blocking)

## Code blockers (why code is not done)
- none

## Reopened phases (false-complete fixes)
- none

## Missing items (code gaps; evidence-anchored; no tables)
- none

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- Relay rollout remains a deployment obligation under Phase 6, not missing code.
- Physical phone testing is intentionally out of scope for this goal by user
  instruction.
<!-- arch_skill:block:implementation_audit:end -->

## Outcome

Dock interactions must stay fast under large multi-host datasets. Heartbeats and
unchanged host events must not create new Dock screen frames, and no normal
SwiftUI or accessibility path may build all-row proof data.

## Problem

Profiling showed the main user-visible lag was not a generic scroll problem. At
about `1,247` rows, `DockView.dockScreenValue` built a `469,211` character
`rowValues=` accessibility payload in `20-22 ms`, repeatedly, while ordinary
host traffic could still republish unchanged Dock state.

## Approach

Keep the existing owner model and make it stricter:

- `DockScreenStore` remains the only presentation owner and gates accepted
  `(DockSnapshot, DockProjectionOptions)` before revision bumps, projection, or
  `RenderCoalescer` submission.
- `DockStore` remains the data/action owner and stops publishing unchanged
  `.loaded` snapshots into either `DockStore.state` or `DockScreenStore`.
- `DockView` deletes root `rowValues=` forever. The root accessibility value is
  bounded scalar state only.
- UI proof moves to one test-only JSON snapshot per accepted render revision.
  The app writes it before advertising `automationRevision=R`; XCUITest reads
  that single row oracle and fails loud on missing, stale, malformed, or
  mismatched snapshots.
- Collapse state that affects the proof row set moves into
  `DockProjectionOptions`, so `DockScreenStore`, `DockView`, and the JSON
  snapshot use one row-selection truth.

## Plan

Use `$arch-step auto-plan` on this document, then `$fresh-consult
composer-2.5-fast` until it agrees the plan is exhaustive and unified. Then use
`$arch-step auto-implement`, test in simulator only, run
`$thermo-nuclear-code-quality-review`, fix review findings, commit/push, and
update both relay deployments from the pushed branch.

## Non-negotiables

- No root `rowValues=` fallback, not even in tests.
- No hidden or visible bulk accessibility element.
- No visual scraping fallback for Dock row truth.
- No duplicate Dock row oracle.
- No display fingerprints in the first implementation; use exact `Equatable`.
- No `DockRowWindow` in the first implementation unless post-fix profiling
  proves full arrays still hitch.
- No physical-phone testing for this goal.
- Git is the archive: delete stale code, test helpers, docs, and comments rather
  than preserving legacy paths beside the new path.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-06-04
external_research_grounding: not required 2026-06-04 (repo-local architecture and local profiling evidence only)
deep_dive_pass_2: done 2026-06-04
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:81ba152b4e695ab2a1583861b03ded93f3f364eb3eaa9cb02e26ea1fa9d9e9c5",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-04T19:07:31Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:83cacb912e262784e26c5f906ad051e55b37b0331cf1e3380b50a89d315f7c31",
      "completed_at": "2026-06-04T19:07:42Z",
      "doc_hash_after": "sha256:1a29a174bef0e337c8ca4465fe4bd432dd9cfc36c7297aac081c194660299e0d"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-04T19:07:47Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:1a29a174bef0e337c8ca4465fe4bd432dd9cfc36c7297aac081c194660299e0d",
      "completed_at": "2026-06-04T19:08:02Z",
      "doc_hash_after": "sha256:e1d8b46b214ee2a8b082c6181f5858516cbe68486c05dd6c26f7e881ca507a6b"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-04T19:08:08Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e1d8b46b214ee2a8b082c6181f5858516cbe68486c05dd6c26f7e881ca507a6b",
      "completed_at": "2026-06-04T19:08:23Z",
      "doc_hash_after": "sha256:2321e8341039cc69a2729b148b7db271895906d3f9e97a8b7ac4a43480d4b456"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-04T19:08:28Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:2321e8341039cc69a2729b148b7db271895906d3f9e97a8b7ac4a43480d4b456",
      "completed_at": "2026-06-04T19:08:45Z",
      "doc_hash_after": "sha256:7b245469a703b0cfb5f7613dfcdf972ac6dfa38454b66ad07c24317e9f673835"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-04T19:21:54Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:a64fb08215fe3329fe7f8c99d1a3a7aac028c17897d34450e2352baf5fbdd262",
      "completed_at": "2026-06-04T19:22:04Z",
      "doc_hash_after": "sha256:9bd61e4df20e8d5c6e1f62903b5971d54e2accc61ba68ec341f1a4724face425"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this change, a heartbeat or unchanged host event cannot bump the Dock
render revision, cannot run Dock projection, cannot submit to
`RenderCoalescer`, cannot publish a new `.loaded` Dock screen frame, and cannot
make SwiftUI rebuild all-row automation proof data. A loaded Dock root with
`10,000` rows still has a bounded accessibility value, and simulator proof still
compares ordered Dock rows against relay truth through one strict row oracle.

## 0.2 In scope

- Gate unchanged Dock render inputs inside `DockScreenStore.enqueueProjection`.
- Equality-guard `DockStore.state = .loaded(...)` and `screenStore.publish(...)`
  so unchanged displayed snapshots do not invalidate the root view.
- Route optimistic rename publishes through the same guarded publish funnel.
- Delete root `rowValues=` construction from `DockView.dockScreenValue`.
- Delete or replace `dockAutomationRows(in:)`, `automationEncoded(_:)`, and
  `DisplayedUICaptureSupport.dockRowsFromRootValue(_:)`.
- Add one test-only `DockAutomationSnapshotStore` that writes JSON snapshots for
  accepted `DockRenderSnapshot` revisions only.
- Move pinned/group collapse state out of private `DockView` state and into the
  projection options contract before JSON proof is written.
- Add a compact root value with `revision`, `automationRevision`, and a
  bounded `automationSnapshotPath` only when snapshot mode is enabled.
- Update XCUITest displayed-UI capture to read the JSON snapshot and populate
  `DisplayedUISample.dockRows` from that one oracle.
- Update proof scripts/tests/docs so no test depends on root `rowValues=`.
- Replace `DockView.syncSelectedDetail` linear row lookup with a
  `Dictionary` or equivalent `O(1)` map keyed by `row.id`.
- Keep useful performance telemetry only if it remains a real shipped
  diagnostic; delete temporary profiling-only code that is not part of the
  final architecture.
- Verify with simulator and local relay checks only.

## 0.3 Out of scope

- Physical iPhone testing or physical Mobile MCP testing.
- New product UX, paging controls, "show more" rows, or explicit row-window UI.
- New relay protocol features.
- Display hash/fingerprint gates in the first implementation.
- Runtime compatibility shims or old/new row-oracle bridges.
- Any second row-discovery path based on visual scraping, visible row
  enumeration, or a hidden accessibility payload.

## 0.4 Definition of done (acceptance evidence)

- `$arch-step auto-plan` returns `READY next=implement-loop` for this doc.
- `$fresh-consult composer-2.5-fast` returns `VERDICT: pass`, with
  `BLOCKING: none`, after the arch-step plan is in canonical form.
- `$arch-step auto-implement` completes all Section 7 phases and its
  implementation audit is clean.
- `rtk swift test --filter DockScreenStoreTests` passes.
- `rtk swift test --filter DockStoreTests` passes, or the narrower named Dock
  store tests that cover changed behavior pass if the full filter is too broad.
- `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests'`
  passes.
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` passes or reports a
  precise non-code blocker from existing services/simulator state.
- `rtk npm run test:relay` passes after proof-contract updates.
- `git diff --check` passes.
- `$thermo-nuclear-code-quality-review` finds no blocking structural findings,
  or every blocking finding is fixed and re-reviewed.
- The final commit is pushed, then the Mac/local relay and `home` relay
  deployment copy are updated from that pushed branch and restarted.

## 0.5 Key invariants (fix immediately if violated)

- `DockScreenStore` is the only owner that decides whether a snapshot becomes a
  rendered Dock screen frame.
- `DockStore` never writes an unchanged `.loaded` snapshot just to mirror a
  heartbeat.
- `DockProjectionOptions` owns every UI state bit that changes full-row proof:
  lens, search, filters, pinned collapse, host-group collapse, and branch-group
  collapse.
- Production never builds full Dock row proof data.
- UI-test mode never puts full Dock row proof data in the accessibility tree.
- The JSON automation snapshot is the only full-row Dock proof oracle.
- The root accessibility value is bounded by scalar screen state, not row count.
- Snapshot revision ordering is fail-loud: file for revision `R` exists before
  root advertises `automationRevision=R`.
- Missing, stale, malformed, or mismatched automation snapshots fail proof; no
  fallback is allowed.
- Exact equality is the correctness gate. Hashing is only a future precheck with
  exact equality fallback if equality itself profiles hot.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Main-thread interaction speed under huge Dock datasets.
2. Strict displayed-UI proof that still catches drift against relay truth.
3. One owner path for publish eligibility and one owner path for row proof.
4. Minimal architecture: reuse `DockScreenStore`, `DockStore`,
   `DockRenderSnapshot`, `DockSnapshot`, and `RenderCoalescer`.
5. Clean cutover: old root `rowValues=` code, tests, and docs are deleted.
6. Preserve existing Dock UX and sorting/filtering behavior.

## 1.2 Constraints

- Mobile builds, simulator tests, and generated Xcode project checks are
  Makefile-owned.
- `project.yml` is the XcodeGen source of truth if target wiring changes.
- Production timing and size constants belong in `CodexDockConstants` if they
  become production configuration.
- `.env` and secrets are not part of this change.
- UI proof currently writes JSONL samples through `DisplayedUIArtifactWriter`
  and compares `sample.dockRows[]` in `scripts/dock-relay-simulator-ui-sync-proof.mjs`.
- The app normally connects to the Dock relay on `:4510`, not the raw app
  server.

## 1.3 Architectural principles (rules we will enforce)

- Put the no-op render gate at the existing render funnel, not at individual
  call sites.
- Make no-op suppression structural: equal input means no revision, no
  projection, no coalescer submit, no publish.
- Keep automation proof off the accessibility tree; root accessibility carries
  only bounded scalar state and a bounded snapshot pointer in test mode.
- Use a hard cutover. Delete old root row proof code and any test fallback that
  reconstructs row truth another way.
- Prefer behavior-level tests that prove shipped behavior over greps that merely
  prove strings are absent.
- Add only high-leverage comments at the new ownership boundary.

## 1.4 Known tradeoffs (explicit)

- Exact equality is `O(total rows)` in the worst case, but it runs before
  projection and is collision-safe. It is the right first gate because current
  evidence shows the main-thread root payload is the dominant cost.
- Full row arrays stay in the first implementation. `LazyVStack` already bounds
  materialized views, and changing to a row window would add new UX/proof
  semantics without evidence that it is required.
- JSON proof adds test-only file plumbing, but it removes the entire class of
  accessibility-tree bulk payload failure and matches the existing JSONL proof
  pipeline.
- Root exposes a test-only snapshot path. That is bounded scalar proof metadata,
  not row proof data, and it is absent in production.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

`DockStore` receives host stream snapshots, updates `DockDataEngine`, creates a
combined `DockSnapshot`, applies pending local rename overlays, writes
`DockStore.state = .loaded(...)`, and calls `screenStore.publish(snapshot:)`.

`DockScreenStore.publish(snapshot:)` calls `enqueueProjection`, which always
increments `latestRevision`, projects off-main with `DockRenderProjector`, and
submits to `RenderCoalescer`. `DockScreenStore.start()` publishes coalesced
snapshots as `.loaded`.

`DockView.dockScreenValue` is attached to the Dock root accessibility value.
When loaded, it gathers all projected Dock automation rows, percent-encodes each
row's `automationValue`, joins them into `rowValues=...`, and returns one large
root string. `DisplayedUICaptureSupport` parses that root field back into
`DisplayedUISample.dockRows`.

## 2.2 What's broken / missing (concrete)

- The root value is proportional to total displayed rows and was measured at
  `469,211` characters for `1,247` rows.
- Building that root payload cost `20-22 ms`, repeatedly, on normal body /
  accessibility evaluation.
- Heartbeat/no-visible-change events can still write `.loaded` and trigger the
  projection/publish path.
- UI proof has coupled full row truth to the same accessibility value that
  SwiftUI touches during ordinary rendering.
- Tests and README currently describe root `rowValues=` as the strict row proof
  source, making the slow path look intentional.

## 2.3 Constraints implied by the problem

- Fixing only the relay heartbeat rate is insufficient because any unchanged
  upsert or local no-op can reintroduce the publish storm.
- Fixing only `rowValues=` is insufficient because unchanged publishes would
  still cause avoidable work and future drift.
- Strict proof must remain structured and deterministic; a visual scrape is not
  a valid replacement.
- The root proof contract must be cleanly cut over. Keeping both old and new row
  oracles guarantees drift.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- SwiftUI/lazy list practice: keep expensive whole-dataset derivations out of
  `body` and accessibility values. Adopt: row views may carry per-row bounded
  values because `LazyVStack` materializes a viewport-sized subset, but root
  screen values must stay scalar.
- Event-sourced UI projection practice: publish only accepted revisions and
  make no-op revision suppression structural at the projection boundary. Adopt:
  `DockScreenStore.enqueueProjection` is the existing boundary and should own
  this rule.
- Test artifact practice: large deterministic proof payloads belong in
  structured files, not accessibility labels. Adopt: the existing proof pipeline
  already consumes JSON/JSONL artifacts, so JSON is the smallest robust route.

## 3.2 Internal ground truth (code as spec)

- Auto-plan research pass, 2026-06-04: verified the current owner paths with
  `rg` and exact reads of `DockStore`, `DockScreenStore`, `DockView`,
  `DisplayedUICaptureSupport`, Makefile simulator proof targets, and relay proof
  scripts before declaring decision gaps resolved.
- Authoritative behavior anchors:
  - `CodexDock/State/DockStore.swift` - owns host stream ingestion, local
    metadata overlays, pending rename overlays, `state`, and calls into
    `screenStore.publish(snapshot:)`.
  - `CodexDock/Dock/DockScreenStore.swift` - owns `DockScreenState`,
    `DockProjectionOptions`, render revision creation, off-main projection, and
    `RenderCoalescer` consumption.
  - `CodexDock/Dock/DockRenderProjector.swift` - pure projection from
    `DockSnapshot` plus `DockProjectionOptions` to `DockCardProjection`.
  - `CodexDock/Dock/DockModels.swift` - `DockSnapshot` and `DockRowViewModel`
    are already `Equatable`.
  - `CodexDock/State/DockCardProjection.swift` - `DockProjectionOptions` is
    already `Equatable`.
  - `CodexDock/Dock/DockRenderModels.swift` - `DockRenderSnapshot` carries
    revision, source snapshot, and projection.
  - `CodexDock/Features/Dock/DockView.swift` - current root `rowValues=`
    construction and `syncSelectedDetail` row scan live here.
  - `CodexDock/Features/Dock/DockSharedViews.swift` - current
    `DockRowViewModel.automationValue` semantics used by row views and proof.
  - `CodexDockUITests/DisplayedUICaptureSupport.swift` - current root
    `rowValues=` parser and displayed-UI sample capture.
  - `scripts/dock-relay-simulator-ui-sync-proof.mjs` - consumes
    `sample.dockRows[]` from UI JSONL and compares it to relay truth.
  - `README.md` - documents `rowValues=` as the current row proof oracle.
  - `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
    - also documents root `rowValues=` / `sim-ui-dump` proof behavior and must
      not continue teaching the old oracle after cutover.
  - `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md`
    - records `rowValues=` as the current proof route and must be marked
      historical or rewritten so it cannot be mistaken for the live contract.
- Canonical path / owner to reuse:
  - `DockScreenStore.enqueueProjection` owns render eligibility.
  - `DockScreenStore.start()` owns accepted render revisions and is the correct
    hook for test-only automation snapshots before publishing `.loaded`.
  - `DockStore.publishSnapshot` and `publishCurrentSnapshotWithPendingRenames`
    own displayed data publication and must share one equality-guarded funnel.
  - `DisplayedUICaptureSupport.captureDisplayedUISample` owns converting live UI
    evidence into `DisplayedUISample.dockRows`.
- Adjacent surfaces tied to the same contract family:
  - `CodexDockUITests/DisplayedUICaptureSupport.swift` must delete root parser
    and read the JSON snapshot.
  - `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` must launch the
    app with snapshot mode for proof runs.
  - `CodexDockUITests/CodexDockPerformanceScrollUITests.swift` must launch with
    snapshot mode if it captures displayed samples.
  - `CodexDockUITests/CodexDockLiveFilterProofTests.swift` calls
    `captureDisplayedUISample(..., includeDetailSweep:)` and must receive the
    same snapshot row oracle.
  - Every copied UI-test launcher must set the same snapshot flag when its test
    can call `captureDisplayedUISample` or relies on row proof:
    `CodexDockDisplayedSyncProofTests.launchRelayBackedApp`,
    `CodexDockAutomationSmokeTests.launchRelayBackedApp`,
    `CodexDockThreadRenameUITests.launchRelayBackedApp`,
    `CodexDockLiveFilterProofTests.launchRelayBackedApp`, and
    `CodexDockUserMessageLatencyUITests.launchRelayBackedApp`.
  - Prefer deleting those copied launch helpers in favor of one shared UI-test
    launch helper so `CODEX_DOCK_HOSTS` and
    `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1` cannot drift across test files.
  - All direct `captureDisplayedUISample` callers must be migrated:
    `CodexDockDisplayedSyncProofTests`, `CodexDockPerformanceScrollUITests`,
    `CodexDockLiveFilterProofTests`, and `CodexDockCurrentUIDumpTests`.
  - `scripts/dock-relay-simulator-ui-sync-proof.test.mjs` and
    `scripts/proof-report-contracts.test.mjs` must stay compatible with
    `sample.dockRows[]` without assuming root `rowValues=`.
  - `README.md` must describe JSON snapshots as the row proof oracle.
  - `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
    must either be updated to the JSON snapshot oracle or explicitly marked as
    historical evidence that is no longer the current proof contract.
  - `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md`
    must also be marked historical or updated where it describes root
    `rowValues=` as the current proof route.
  - Temporary profiling files must either become permanent telemetry or be
    deleted before the final commit.
- Compatibility posture:
  - Clean cutover. Root `rowValues=` is removed from production and tests in the
    same implementation. Existing downstream proof scripts keep the
    `DisplayedUISample.dockRows` JSONL shape, so the external proof report
    contract is preserved while the row source changes.
- Existing patterns to reuse:
  - Application Support writes with atomic file replacement:
    `RelayDiscovery.swift`, `LocalThreadMetadataStore.swift`,
    `ClientObservabilityStore.swift`, and `PerformanceProbe.swift`.
  - JSONL UI sample artifact writing:
    `DisplayedUIArtifactWriter`.
  - Coalesced render stream:
    `RenderCoalescer`.
  - Existing `Equatable` data models for exact input equality.
- Duplicate or drifting paths relevant to this change:
  - `DockView.dockAutomationRows(in:)` duplicates row truth only for root proof.
  - `DisplayedUICaptureSupport.dockRowsFromRootValue(_:)` duplicates proof
    decoding in the UI test layer.
  - README text names old root proof as canonical.
- Behavior-preservation signals already available:
  - `DockScreenStoreTests`, `DockStoreTests`, `DockStoreStreamTests`,
    `RenderCoalescerTests`, and `DockRenderProjectorTests`.
  - `CodexDockPerformanceScrollUITests`.
  - `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`.
  - `rtk npm run test:relay` for proof report and relay script contracts.

## 3.3 Decision gaps that must be resolved before implementation

None. Resolved decisions:

- Snapshot mode launch flag: `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1` in the app
  launch environment for UI tests that need Dock row proof.
- Snapshot file name: `dock-automation-snapshot-<revision>.json`.
- Snapshot directory: app Application Support
  `CodexDock/DockAutomationSnapshots`; root test metadata exposes the exact
  bounded path as `automationSnapshotPath=<percent-encoded path>` when snapshot
  mode is enabled.
- Snapshot retention: keep the latest `5` accepted revisions.
- Cutover: no old root `rowValues=` parser, writer, doc, or fallback remains.
- Collapse semantics: promote pinned/group collapse state into
  `DockProjectionOptions`; do not redefine proof as an uncollapsed hidden model
  and do not let `DockView` keep a second row-selection truth.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `CodexDock/State/DockStore.swift` - data/action store and stream owner.
- `CodexDock/Dock/DockScreenStore.swift` - presentation store and render
  revision owner.
- `CodexDock/Dock/DockRenderProjector.swift` - off-main row/group projection.
- `CodexDock/State/DockCardProjection.swift` - projected row/group result and
  `DockProjectionOptions`.
- `CodexDock/Features/Dock/DockView.swift` - SwiftUI screen, root
  accessibility value, row rendering, rename/detail interactions.
- `CodexDock/Features/Dock/DockSharedViews.swift` - row automation value.
- `CodexDockUITests/DisplayedUICaptureSupport.swift` - displayed UI sample
  capture and root row parser.
- `scripts/dock-relay-simulator-ui-sync-proof.mjs` - proof comparison.

## 4.2 Control paths (runtime)

Deep-dive pass 1 verified this path directly from current source before the
auto-plan receipt was completed.

1. Host stream emits `StreamReconcilerSnapshot`.
2. `DockStore.handleReconcilerSnapshot` applies it to `DockDataEngine`.
3. `DockStore.publishSnapshot` builds `DockSnapshot`, applies pending renames,
   writes `DockStore.state`, calls `screenStore.publish`, and reports
   connectivity.
4. `DockScreenStore.enqueueProjection` increments revision and starts detached
   projection.
5. Detached projection submits a `DockRenderSnapshot` to `RenderCoalescer`.
6. `DockScreenStore.start()` publishes coalesced snapshots as `.loaded`.
7. `DockView.body` reads `.loaded`; root accessibility evaluates
   `dockScreenValue`.
8. `dockScreenValue` currently walks all automation rows and builds `rowValues=`.
9. UI tests parse `rowValues=` back into `DisplayedUISample.dockRows`.

Current caveat to delete: the old row oracle also depends on private
`DockView` collapse state (`isPinnedCollapsed`, `collapsedHostGroupIDs`,
`collapsedBranchGroupIDs`). The target architecture cannot write JSON from
`DockScreenStore` until that state is part of `DockProjectionOptions`.

## 4.3 Object model + key abstractions

- `DockSnapshot`: full combined Dock input; equatable.
- `DockProjectionOptions`: lens, search, filters; equatable.
- `DockRenderSnapshot`: accepted render revision plus input snapshot and
  projection; equatable.
- `DockCardProjection`: projected rows/groups/pinned rows for SwiftUI.
- `RenderRevision`: monotonically increasing local render revision.
- `RenderCoalescer`: async coalescing stream that keeps only the newest render
  snapshot when projection bursts race.

## 4.4 Observability + failure behavior today

- Profiling instrumentation currently logs render enqueue, detached projection,
  main publish, data snapshot, and root accessibility value build timings.
- A missing `rowValues=` payload leaves `dockRows` empty in displayed UI samples
  so strict proof eventually fails, but the capture layer still treats root
  parsing as the only row source.
- No-op snapshots are observable as repeated render enqueue/projection/publish
  events even when visible Dock truth did not change.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current visible UI stays the same:

```text
Dock
  [Newest] [Host] [Branch] [Filters]
  pinned rows...
  grouped or flat Dock rows...
```

Only the invisible automation contract changes.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- `CodexDock/Dock/DockScreenStore.swift`
  - Add last-accepted render input tracking.
  - Add optional `DockAutomationSnapshotStore` dependency.
  - Write automation snapshots in `start()` before publishing `.loaded`.
- `CodexDock/Automation/DockAutomationSnapshotStore.swift`
  - New test-only snapshot writer and DTO owner.
- `CodexDock/Runtime/ClientRuntime.swift` and `CodexDock/State/DockStore.swift`
  - Resolve `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1` once at store construction and
    inject the optional writer into `DockScreenStore`.
- `CodexDock/State/DockStore.swift`
  - Add equality-guarded displayed snapshot publishing.
  - Route pending rename publish through that same funnel.
- `CodexDock/State/DockCardProjection.swift`
  - Add `DockProjectionExpansionState` or equivalent fields to
    `DockProjectionOptions`.
  - Add a projected `automationRows` / `proofRows` list that applies lens,
    search, filters, pinned collapse, and group collapse.
- `CodexDock/Features/Dock/DockView.swift`
  - Remove root all-row proof construction.
  - Add bounded scalar root value fields.
  - Bind pinned/group collapse controls to screen options instead of private
    `@State` that can affect proof rows.
  - Use indexed selected-detail lookup.
- `CodexDockUITests/DisplayedUICaptureSupport.swift`
  - Replace root parser with snapshot-file reader.
- UI-test launch helpers
  - Introduce or reuse one shared helper, such as
    `CodexDockUITests/RelayBackedAppLaunchSupport.swift`, and delete the copied
    `launchRelayBackedApp` bodies where practical.
  - The shared helper sets `CODEX_DOCK_HOSTS` and
    `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1` whenever a test can exercise row proof.
  - If any copied launcher must temporarily remain, it must call the shared
    helper and must not reimplement snapshot flag logic.
- UI-test sample callers
  - Verify `captureDisplayedUISample` reads JSON snapshots for
    `CodexDockDisplayedSyncProofTests`, `CodexDockPerformanceScrollUITests`,
    `CodexDockLiveFilterProofTests`, and `CodexDockCurrentUIDumpTests`.
- Makefile UI-test environment
  - Export `CODEX_DOCK_UI_TEST_SIMULATOR_UDID=$$udid`,
    `CODEX_DOCK_UI_TEST_APP_BUNDLE_ID=$(APP_BUNDLE_ID)`, and
    `CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER=<resolved data container>` on
    Makefile-owned simulator `xcodebuild test` / `test-without-building`
    commands that can read automation snapshots.
  - Required Makefile targets include `app-test`, `sim-ui-dump`,
    `sim-ui-sync-proof`, `sim-ui-scenario-sync-proof`, and
    `sim-ui-controlled-scenario-sync-proof`; other simulator UI proof targets
    that later read row snapshots must use the same exports.
  - `sim-ui-dump` may continue to provide the same values through
    `DisplayedUICurrentDumpConfig`; the resolver must prefer explicit dump
    config when that target is active and use the environment values otherwise.
- `README.md`
  - Replace root `rowValues=` proof text with JSON snapshot proof contract.
- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
  - Replace current-contract claims about root `rowValues=` or mark those
    passages as dated historical evidence.
- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md`
  - Mark `rowValues=` passages historical or update them to avoid teaching the
    old proof route as current.

## 5.2 Control paths (future)

1. `DockStore` builds a displayed `DockSnapshot`.
2. `DockStore` compares it to the current loaded state. If equal, it skips
   `state = .loaded`, skips `screenStore.publish`, and only updates side
   channels that genuinely changed.
3. `DockScreenStore.enqueueProjection` compares
   `(DockSnapshot, DockProjectionOptions)` to the last accepted pair before
   touching `latestRevision`.
4. Equal pair: return immediately.
5. Different pair: store it as last accepted, bump revision, project off-main,
   and submit to `RenderCoalescer`.
6. `DockScreenStore.start()` receives accepted coalesced revisions.
7. If `DockAutomationSnapshotStore` is enabled, write revision `R` JSON
   atomically and prune old snapshots.
8. Publish `.loaded(renderSnapshot)` only after the revision `R` snapshot write
   succeeds or after snapshot mode is disabled.
9. `DockView.dockScreenValue` returns bounded scalar state:

```text
loaded; rows=N; visibleRows=V; pinned=P; lens=L; search=false; filters=0; revision=R; automationRevision=R; automationSnapshotPath=<encoded-path>; ...
```

10. XCUITest reads root scalar state, decodes `automationRevision` and
    `automationSnapshotPath`, resolves the app data container for the simulator,
    reads the JSON file, checks revision equality, and fills
    `DisplayedUISample.dockRows`.
11. `scripts/dock-relay-simulator-ui-sync-proof.mjs` continues to compare
    `sample.dockRows[]` against relay truth.

## 5.3 Object model + abstractions (future)

- `DockRenderInputKey`
  - Internal equatable value or tuple containing `DockSnapshot` and
    `DockProjectionOptions`.
  - Stored by `DockScreenStore` as the last accepted input.
- `DockProjectionExpansionState`
  - Equatable/sendable state for `isPinnedCollapsed`,
    `collapsedHostGroupIDs`, and `collapsedBranchGroupIDs`.
  - Stored inside `DockProjectionOptions` so collapsed row truth is no longer
    private to `DockView`.
- `DockCardProjection.automationRows`
  - Ordered full-row proof list after lens, search, filters, and expansion
    state are applied.
  - This replaces `DockView.dockAutomationRows(in:)`.
- `DockAutomationSnapshotStore`
  - Constructed only when `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1`.
  - Encodes `DockAutomationSnapshot`.
  - Owns snapshot directory creation, atomic writes, path construction, and
    latest-5 pruning.
  - Writes under app Application Support
    `CodexDock/DockAutomationSnapshots/dock-automation-snapshot-<revision>.json`.
  - Returns an Application Support relative path for root metadata, not a second
    row source.
- `DockAutomationSnapshotFileResolver`
  - Test-only helper inside `DisplayedUICaptureSupport.swift` or a colocated UI
    test support file.
  - For `sim-ui-dump`, reads simulator UDID and app bundle id from
    `DisplayedUICurrentDumpConfig`.
  - For normal UI tests, reads `CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER`, resolved
    by Makefile with the same
    `xcrun simctl get_app_container <udid> <bundle-id> data` pattern already
    used by diagnostics.
  - Joins the data container with
    `Library/Application Support/<automationSnapshotPath>`.
  - Fails loud when the simulator UDID, bundle id, metadata, data container, or
    JSON file is unavailable; it never falls back to root `rowValues=` or
    visible-row scraping.
- `DockAutomationSnapshot`
  - `schemaVersion`
  - `revision`
  - `createdAt`
  - `rows`
  - `visibleRows`
  - `pinned`
  - `lens`
  - `search`
  - `filters`
  - ordered rows using the same semantics as `row.automationValue`
- `DockAutomationSnapshotRow`
  - `identifier`
  - `value`
  - `label`
  - `frame`
  - `frame` can remain synthetic, matching current proof behavior
    (`minY=index`, `width=1`, `height=1`) because row order is the proof target.
- `DockRootAutomationState`
  - Small helper is allowed if it keeps `dockScreenValue` legible and bounded.
- `DockAutomationSnapshotConfiguration`
  - Small environment/factory helper that reads
    `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1` and constructs the writer.

## 5.4 Invariants and boundaries

- `DockAutomationSnapshotStore` is test-only by environment flag and absent in
  production default runs.
- `DockAutomationSnapshotStore` is the only full-row proof writer.
- `DisplayedUICaptureSupport` is the only full-row proof reader.
- `DockProjectionOptions` owns every UI state bit that can change the full-row
  proof set: lens, search, filters, pinned collapse, host-group collapse, and
  branch-group collapse.
- Root `rowValues=` has no writer and no reader after cutover.
- `DockStore` and `DockScreenStore` both use exact equality, not hashes, for
  first-pass correctness.
- Host status/freshness changes still publish because `DockSnapshot.hostStates`
  participates in equality.
- Renames remain optimistic and non-blocking: local overlay publishes once if it
  changes display state; server ack or failure later either confirms or reverts
  through the same guarded funnel.
- Compatibility posture is clean cutover inside repo code/tests/docs. The
  external proof-report JSONL `sample.dockRows` shape is preserved.
- New architecture must not add a second `@Published` presentation owner; if a
  helper is extracted, it stays an internal collaborator of `DockScreenStore`.
- `sim-ui-dump` is allowed to be blocked when it attaches to an already-running
  app that was not launched with automation snapshots. It must not relaunch the
  app and must not fall back to visible row scraping.

## 5.5 UI surfaces (ASCII mockups, if UI work)

No visible UI change. The hidden automation contract changes:

```text
Before:
Dock root accessibility value
  rowValues=<all rows>

After:
Dock root accessibility value
  revision=42
  automationRevision=42
  automationSnapshotPath=<bounded test-only path>

JSON snapshot file
  rows=[all ordered row proof records]
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Render gate | `CodexDock/Dock/DockScreenStore.swift` | `enqueueProjection(snapshot:)` | Always bumps revision and starts projection | Compare incoming `(DockSnapshot, DockProjectionOptions)` to last accepted input first; equal returns without revision/projection/coalescer | Stops no-op render storms at owner boundary | Exact equality input gate | `DockScreenStoreTests` |
| Accepted publish | `CodexDock/Dock/DockScreenStore.swift` | `start()` coalescer loop | Publishes `.loaded` immediately | In test snapshot mode, write JSON for accepted revision before `.loaded`; expose snapshot metadata for root value | Prevents read-before-write proof flake | `DockAutomationSnapshotStore.write(renderSnapshot:options:)` | UI proof tests |
| Snapshot writer | `CodexDock/Automation/DockAutomationSnapshotStore.swift` | new type | Does not exist | Add test-only JSON writer with atomic write and latest-5 pruning | Moves bulk row proof off accessibility | `DockAutomationSnapshot` schema v1 | New unit tests |
| Snapshot wiring | `CodexDock/State/DockStore.swift` | all three initializers | Constructs `DockScreenStore` without snapshot writer | Resolve optional writer from `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1` and inject into `DockScreenStore`; keep test override possible | One construction owner, no branchy env reads | `DockAutomationSnapshotConfiguration.makeIfEnabled` | Store/screen tests |
| Runtime factory | `CodexDock/Runtime/ClientRuntime.swift` | `makeDockStore(...)` | Does not name automation writer wiring | Add optional writer/config override only if tests need it; otherwise document that `DockStore` owns the default environment factory | Keeps app wiring obvious | Store construction contract | `ClientRuntimeTests` if signature changes |
| Store publish | `CodexDock/State/DockStore.swift` | `publishSnapshot(context:)` | Always writes `.loaded` and publishes to screen store | Use one equality-guarded `publishDisplayedSnapshot` helper | Removes duplicate invalidation channel | No-op displayed snapshot publishes nothing | `DockStoreTests`, `DockStoreStreamTests` |
| Rename overlay | `CodexDock/State/DockStore.swift` | `publishCurrentSnapshotWithPendingRenames()` | Writes `.loaded` and screen publishes directly | Route through same guarded helper | Keeps rename path fast and structurally consistent | Same publish funnel | Rename/store tests |
| Connectivity | `CodexDock/State/DockStore.swift` | `publishConnectivity(for:)` call sites | Called after every publish path | Preserve real connectivity updates; do not depend on no-op `.loaded` writes for liveness | Host state changes still publish through snapshot equality | Connectivity remains tied to real state | Connectivity/store tests |
| Root accessibility | `CodexDock/Features/Dock/DockView.swift` | `dockScreenValue` | Builds all-row `rowValues=` payload | Return bounded scalar state only; include revision and test-only snapshot metadata | Removes dominant 20-22 ms main-thread work | Bounded root contract | UI/unit perf tests |
| Old root row helper | `CodexDock/Features/Dock/DockView.swift` | `dockAutomationRows(in:)` | Builds full row list for root value | Delete | No full-row proof in view body | None | Compile/tests |
| Old root encoder | `CodexDock/Features/Dock/DockView.swift` | `automationEncoded(_:)` | Percent-encodes root row payload | Delete if no remaining use | Old root proof path gone | None | Compile/tests |
| Detail sync | `CodexDock/Features/Dock/DockView.swift` | `syncSelectedDetail(with:)` | Scans `snapshot.rows.first(where:)` | Use dictionary/equivalent O(1) map keyed by `row.id` | Removes remaining known main-thread O(n) row touch | Indexed lookup | Unit/UI smoke |
| Row proof semantics | `CodexDock/Features/Dock/DockSharedViews.swift` | `DockRowViewModel.automationValue` | Per-row semicolon value | Keep semantics; JSON rows reuse the exact meaning | Avoids second row schema drift | Same value semantics | Proof tests |
| Collapse state | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/State/DockCardProjection.swift` | `isPinnedCollapsed`, `collapsedHostGroupIDs`, `collapsedBranchGroupIDs`, `DockProjectionOptions` | Collapse state is private to `DockView` and old root row helper | Move collapse state into projection options and use projected `automationRows` for UI proof | JSON writer can match row proof without calling view code | `DockProjectionExpansionState` | Dock view/projection tests |
| UI capture | `CodexDockUITests/DisplayedUICaptureSupport.swift` | `captureDisplayedUISample` | Parses root `rowValues=` | Read root revision/path, resolve simulator app data container, load JSON, fail loud on errors, fill `dockRows` | Single strict row oracle without root bulk | `dockRowsFromAutomationSnapshot(rootValue:)` plus test-only file resolver | UI proof tests |
| UI capture old parser | `CodexDockUITests/DisplayedUICaptureSupport.swift` | `dockRowsFromRootValue(_:)` | Parses old root field | Delete | No fallback, even in tests | None | Compile/tests |
| Checkpoint sweep | `CodexDockUITests/DisplayedUICaptureSupport.swift` | `checkpointDockSweep` | Uses root rows as fast path | Use JSON snapshot path for full row proof; do not visible-scrape fallback | Same oracle for normal and sweep samples | Snapshot-backed sweep | Matrix proof |
| UI test launch | `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, `CodexDockUITests/CodexDockAutomationSmokeTests.swift`, `CodexDockUITests/CodexDockThreadRenameUITests.swift`, `CodexDockUITests/CodexDockLiveFilterProofTests.swift`, `CodexDockUITests/CodexDockUserMessageLatencyUITests.swift`, `CodexDockUITests/CodexDockPerformanceScrollUITests.swift`, shared UI-test support file | each `launchRelayBackedApp(...)` helper or inline app launch | Duplicated helpers or inline launches pass host env only | Introduce one shared relay-backed app launcher that sets `CODEX_DOCK_HOSTS` and `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1`; copied helpers and inline launches must call it or be deleted | Prevents snapshot flag drift | Shared launch helper | Displayed proof, smoke, rename, live-filter, user-message latency, performance |
| UI test snapshot container config | `Makefile`, `CodexDockUITests/DisplayedUICaptureSupport.swift`, `CodexDockUITests/CodexDockCurrentUIDumpTests.swift` | simulator test commands, `DisplayedUICurrentDumpConfig`, snapshot resolver | `sim-ui-dump` config carries UDID/bundle, other UI tests do not | Export `CODEX_DOCK_UI_TEST_SIMULATOR_UDID`, `CODEX_DOCK_UI_TEST_APP_BUNDLE_ID`, and `CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER`; resolver uses dump config first and env second | Makes snapshot file lookup deterministic without shelling out from Swift UI tests | Test-only container resolver contract | UI proof tests |
| Performance UI test | `CodexDockUITests/CodexDockPerformanceScrollUITests.swift` | app launch | Captures displayed samples but no snapshot flag | Add snapshot flag or avoid row capture if not needed | Prevents missing oracle after root cutover | Test-only flag | Performance test |
| Current UI dump | `CodexDockUITests/CodexDockCurrentUIDumpTests.swift` | `testDumpsCurrentVisibleScreenOnce` | Attaches to already-running app and calls `captureDisplayedUISample` | If app lacks snapshot metadata, write a blocked dump explaining it was not launched with automation snapshots; do not relaunch or scrape rows | Preserves dump no-relaunch contract and no-fallback rule | Blocked dump reason for missing snapshot mode | `rtk make sim-ui-dump` |
| Live filter proof | `CodexDockUITests/CodexDockLiveFilterProofTests.swift` | `captureDisplayedUISample(index:includeDetailSweep:)` | Samples rows and optional detail sweep | Use the shared JSON snapshot reader for rows and keep detail sweep unchanged | Covers the direct caller fresh consult found | Same row oracle, existing detail proof | Live filter proof |
| Proof scripts | `scripts/dock-relay-simulator-ui-sync-proof.mjs` | sample reader | Already consumes `sample.dockRows[]` | Keep shape; update tests/docs that mention old root source | Preserve external proof contract | No script API change expected | `rtk npm run test:relay` |
| Proof tests | `scripts/dock-relay-simulator-ui-sync-proof.test.mjs`, `scripts/proof-report-contracts.test.mjs` | fixtures | Some fixtures mention root rows/count; root `rowValues=` no longer valid | Ensure fixtures provide `dockRows[]` directly and root has only scalar state | Tests must not preserve old oracle | JSONL shape unchanged | Relay tests |
| README | `README.md` | simulator proof section | Says rows read from root `rowValues=` | Replace with JSON snapshot proof contract | Live docs match shipped proof | Documentation truth | Readback |
| Live-update architecture docs | `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`, `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md` | `rowValues=` / `sim-ui-dump` proof passages | Document old proof route as current | Rewrite to JSON snapshot oracle or mark as dated historical evidence | Avoids stale docs reviving the old oracle | Documentation truth | Readback |
| Generated project | `project.yml`, `CodexDock.xcodeproj` | target sources | New file may require regen | Use `rtk xcodegen generate --spec project.yml` if generated project changes | Keep Xcode project current | XcodeGen-owned | Build/test |
| Telemetry | `CodexDock/Diagnostics/PerformanceProbe.swift` and callers | Profiling changes exist in worktree | Keep only useful bounded diagnostics; delete temporary profiling-only code if not final | Avoid shipping debug clutter | Permanent events only if valuable | Tests/build |
| Relay rollout | `Makefile`, `scripts/dock-relay.mjs`, deployment checkouts | User requested update both servers after push | No relay runtime code is expected to change, but rollout remains required by user objective | Treat as deployment requirement, not architecture dependency | Pull/restart from pushed branch | Relay status checks |

## 6.2 Migration notes

- Auto-plan deep-dive pass 2, 2026-06-04: hardened this migration around the
  explicit cutover requirement. Old root row proof is not allowed to remain as
  a test helper, compatibility bridge, hidden element, fixture dependency, or
  fallback path.
- Canonical owner path / shared code path:
  - `DockScreenStore.enqueueProjection` owns render acceptance.
  - `DockStore.publishDisplayedSnapshot` (new helper) owns displayed snapshot
    equality and publishes to `DockStore.state` plus `DockScreenStore`.
  - `DockProjectionOptions` owns pinned/group collapse state that affects row
    proof.
  - `DockCardProjection.automationRows` owns the ordered proof row list.
  - `DockAutomationSnapshotStore` owns JSON proof writes.
  - `DisplayedUICaptureSupport` owns JSON proof reads.
- Deprecated APIs:
  - Root `rowValues=` contract is removed, not deprecated.
  - `dockRowsFromRootValue(_:)` is deleted, not kept as fallback.
- Delete list:
  - `DockView.dockAutomationRows(in:)`.
  - Private `DockView` collapse state as row-proof-affecting truth; the
    controls remain, but their state source moves to projection options.
  - `DockView.automationEncoded(_:)` if no non-root use remains.
  - Root `rowValues=` string assembly.
  - Root row parser in UI tests.
  - README/docs statements naming root `rowValues=` as row proof.
  - Any test fallback that reconstructs Dock rows from visible row enumeration
    when JSON snapshot proof is missing.
  - Any fixture comment or helper that implies root `rowValues=` is an accepted
    Dock row source after the cutover.
- Adjacent surfaces tied to the same contract family:
  - UI sample writer remains unchanged at the JSONL boundary.
  - Node proof report contract remains `sample.dockRows[]`.
  - Simulator proof Makefile targets remain the final E2E signal.
  - `sim-ui-dump` remains a no-relaunch diagnostic and reports `blocked` when
    row snapshots are unavailable.
- Compatibility posture / cutover plan:
  - Clean internal cutover. No runtime bridge.
  - Preserve the external `DisplayedUISample.dockRows` JSONL contract.
- Capability-replacing harnesses to delete or justify:
  - None. This is not agent-backed and does not add OCR/fuzzy/parser harnesses.
- Live docs/comments/instructions to update or delete:
  - README proof section.
  - UI test comments that say root payload is the only row source.
  - Any new code comments should live only at `DockScreenStore` gate and
    `DockAutomationSnapshotStore` snapshot-ordering boundary.
- Behavior-preservation signals for refactors:
  - Dock store/screen unit tests for no-op and real-change publish behavior.
  - Existing projection and coalescer tests.
  - Simulator proof for user-visible sync.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Dock render revisions | `DockScreenStore.enqueueProjection` | Last accepted exact input gate | Stops scattered call-site throttles | include |
| Collapse state | `DockProjectionOptions` | Projection-owned expansion state | Prevents `DockView` from owning hidden row proof truth | include |
| Store publishes | `DockStore.publishSnapshot`, rename path | One equality-guarded publish helper | Prevents future no-op paths | include |
| Automation row proof | `DockAutomationSnapshotStore` | One JSON writer keyed by revision | Prevents accessibility payload drift | include |
| UI row proof read | `DisplayedUICaptureSupport` | One JSON reader keyed by root revision | Prevents visual scrape/root fallback | include |
| Thread Detail proof | `DisplayedUICaptureSupport.visibleDetail` | Leave current visible-frame proof unchanged | Different surface and not the lag source | exclude |
| Archive row proof | `ArchiveView` row accessibility | Leave per-row bounded values unchanged | Lazy/materialized rows are not root bulk | exclude |
| Future row windowing | `DockRowWindow` | Only after post-fix profiling proves need | Avoids premature UX/proof complexity | defer |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable work. `Work` explains the coherent unit and is explanatory only. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. No fallbacks/runtime shims: the system must work correctly or fail loudly.

Obligation sweep, 2026-06-04: every required item from Sections 5-6 is placed
in a phase checklist or exit criterion. Required old-code deletes live in Phase
3, remaining main-thread cleanup lives in Phase 4, simulator proof and telemetry
cleanup live in Phase 5, and commit/push/relay rollout lives in Phase 6.

## Phase 1 - Structural no-op publish gate

* Goal:
  - Prove the canonical owner path can suppress unchanged Dock screen work
    before any accessibility proof migration.
* Work:
  - Add exact input gating in `DockScreenStore`.
  - Add equality-guarded publish helper in `DockStore`.
* Checklist (must all be done):
  - Add last accepted `(DockSnapshot, DockProjectionOptions)` tracking in
    `DockScreenStore`.
  - Ensure equal inputs return before `latestRevision.next()`, detached
    projection, and `RenderCoalescer.submit`.
  - Preserve option changes: changed `DockProjectionOptions` must publish.
  - Preserve host liveness: changed `DockSnapshot.hostStates` must publish.
  - Add one `DockStore` helper that applies pending rename overlays, compares
    displayed snapshots, writes `state`, calls `screenStore.publish`, and
    reports connectivity only through the intended path.
  - Route `publishSnapshot(context:)` and
    `publishCurrentSnapshotWithPendingRenames()` through that helper.
  - Add or update tests proving equal heartbeat/no-change input skips publish
    and real row/status/host-state/option changes publish.
  - Add one short comment at the `DockScreenStore` input gate explaining that it
    is the only render-eligibility boundary.
* Verification (required proof):
  - `rtk swift test --filter DockScreenStoreTests`
  - Targeted `DockStoreTests` or `DockStoreStreamTests` covering heartbeat skip,
    real host-state publish, row publish, and optimistic rename publish.
* Docs/comments (propagation; only if needed):
  - Add one short comment at the `DockScreenStore` input gate explaining that it
    is the only render-eligibility boundary.
* Exit criteria (all required):
  - Equal input does not change `RenderRevision`.
  - Equal input does not submit to `RenderCoalescer`.
  - Changed options, changed rows, changed host states, and changed pending
    renames still publish.
  - No publish path bypasses the guarded helper.
  - The render-gate comment exists at the canonical boundary, not scattered at
    call sites.
* Rollback:
  - Revert the gate/helper changes together; do not leave one without the other.

## Phase 2 - Test-only JSON row oracle

* Goal:
  - Replace full-row root accessibility proof with one strict JSON row oracle
    while preserving `DisplayedUISample.dockRows[]`.
* Work:
  - Add `DockAutomationSnapshotStore`.
  - Write accepted revision snapshots before `.loaded` publish in test mode.
  - Read those snapshots from XCUITest capture.
* Checklist (must all be done):
  - Add `DockAutomationSnapshotStore` with schema version `1`, atomic writes,
    latest-5 pruning, deterministic filenames, and Application Support
    directory ownership.
  - Enable it only when `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1`.
  - Add a single environment/configuration owner for snapshot writer creation in
    the `DockStore` / `DockScreenStore` construction path.
  - Move pinned/group collapse state into `DockProjectionOptions` through
    `DockProjectionExpansionState` or equivalent.
  - Add `DockCardProjection.automationRows` or equivalent projected proof rows
    using lens, search, filters, and collapse state.
  - Bind Dock collapse controls to the projection options state instead of
    private `DockView` row-proof-affecting `@State`.
  - Hook snapshot writing into `DockScreenStore.start()` before
    `state = .loaded(renderSnapshot)`.
  - Add bounded root fields `revision`, `automationRevision`, and
    test-only `automationSnapshotPath`.
  - Ensure root does not advertise revision `R` until JSON for `R` exists.
  - Make `automationSnapshotPath` an Application Support relative path and
    resolve it in XCUITest with either `DisplayedUICurrentDumpConfig`
    (`sim-ui-dump`) or `CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER` (normal UI
    tests). Makefile, not Swift UI-test code, runs
    `xcrun simctl get_app_container <udid> <bundle-id> data`.
  - Encode rows with the current `row.automationValue` semantics and stable row
    identifiers.
  - Replace `DisplayedUICaptureSupport` root parser with a JSON reader keyed by
    root `automationRevision` and `automationSnapshotPath`.
  - Make missing/malformed/stale/revision-mismatched snapshots fail loud.
  - Add a shared relay-backed UI-test launch helper that sets
    `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1`; migrate
    `CodexDockDisplayedSyncProofTests`, `CodexDockAutomationSmokeTests`,
    `CodexDockThreadRenameUITests`, `CodexDockLiveFilterProofTests`, and
    `CodexDockUserMessageLatencyUITests` to use it when those tests use or can
    call row capture.
  - Export snapshot resolver environment from Makefile-owned simulator test
    commands that can read row snapshots.
  - Validate all current direct `captureDisplayedUISample` callers:
    `CodexDockDisplayedSyncProofTests`, `CodexDockPerformanceScrollUITests`,
    `CodexDockLiveFilterProofTests`, and `CodexDockCurrentUIDumpTests`.
  - Add unit tests for writer enablement, disabled production default, pruning,
    atomic revision filenames, and row schema.
  - Add one short comment in `DockAutomationSnapshotStore` explaining
    write-before-root advertise ordering.
* Verification (required proof):
  - `rtk swift test --filter DockScreenStoreTests`
  - `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests'`
* Docs/comments (propagation; only if needed):
  - Short comment in `DockAutomationSnapshotStore` explaining write-before-root
    advertise ordering.
* Exit criteria (all required):
  - Production default has no automation snapshot writer and no snapshot path in
    root value.
  - UI-test snapshot mode writes JSON for accepted revisions only.
  - Snapshot writer construction has one owner and no branchy env reads.
  - Row-proof UI-test launch has one shared snapshot flag owner, not five copied
    environment branches.
  - Collapse state that affects proof rows lives in projection options, not
    private `DockView` row-selection state.
  - Root value is bounded and contains no row payload.
  - XCUITest row capture has exactly one full-row source: JSON snapshot.
  - Snapshot file resolution is explicit and simulator-container-based, not an
    implied path lookup.
  - No root parser fallback remains.
  - The snapshot-ordering comment exists at the canonical boundary.
* Rollback:
  - Revert JSON proof migration as a unit. Do not restore `rowValues=` as a
    partial fallback.

## Phase 3 - Delete old root row oracle everywhere

* Goal:
  - Make the cutover irreversible in code, tests, and docs.
* Work:
  - Delete old writer/parser helpers and stale proof descriptions.
* Checklist (must all be done):
  - Delete `DockView.dockAutomationRows(in:)`.
  - Delete private `DockView` collapse state as proof-row truth after controls
    are bound to projection options.
  - Delete `DockView.automationEncoded(_:)` if only used by old root proof.
  - Delete `DisplayedUICaptureSupport.dockRowsFromRootValue(_:)`.
  - Update `CodexDockCurrentUIDumpTests` / `sim-ui-dump` so an already-running
    app without snapshot metadata produces a blocked dump instead of relaunching
    or scraping rows.
  - Delete or rewrite comments that say root payload is the row proof source.
  - Update README simulator proof section to name the JSON snapshot oracle.
  - Update
    `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
    so current-contract text no longer names root `rowValues=` as the proof
    route; dated historical snippets must be clearly marked as historical.
  - Update
    `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md`
    with the same historical/current-contract boundary.
  - Update JS proof tests so fixtures never imply `rowValues=` is required.
  - Regenerate `CodexDock.xcodeproj` with `rtk xcodegen generate --spec project.yml`
    if new source files changed project membership.
* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk swift test --filter DockScreenStoreTests`
  - `git diff --check`
* Docs/comments (propagation; only if needed):
  - README must describe the new proof route and fail-loud behavior.
* Exit criteria (all required):
  - No shipped code path writes or reads root `rowValues=`.
  - Tests do not use root `rowValues=` as a compatibility bridge.
  - `sim-ui-dump` has explicit blocked behavior for apps not launched with
    automation snapshots.
  - README and comments no longer teach the old oracle.
  - Adjacent docs do not teach root `rowValues=` as the current proof contract.
* Rollback:
  - Revert to the pre-cutover branch state. Do not re-add only the old parser.

## Phase 4 - Remove remaining main-thread row-scale touch

* Goal:
  - Remove the known remaining `O(total rows)` main-thread lookup after the root
    payload is gone.
* Work:
  - Replace `syncSelectedDetail` scan with indexed lookup.
* Checklist (must all be done):
  - Add or reuse a dictionary/equivalent map keyed by `row.id` for
    `renderSnapshot.snapshot.rows`.
  - Replace `first(where:)` in `syncSelectedDetail`.
  - Keep selected detail behavior identical when row still exists.
  - Keep behavior identical when selected row disappears.
* Verification (required proof):
  - Targeted unit or UI test covering selected detail update, or existing Thread
    Detail/Dock tests that exercise this path.
  - `rtk swift test --filter ThreadDetailStoreTests` if touched behavior
    affects detail invalidation.
* Docs/comments (propagation; only if needed):
  - None unless the index becomes a new helper with a non-obvious invariant.
* Exit criteria (all required):
  - `syncSelectedDetail` no longer scans all rows.
  - Detail invalidation still fires for changed selected rows.
* Rollback:
  - Revert the indexed lookup only if detail behavior regresses.

## Phase 5 - Verification, telemetry cleanup, and simulator proof

* Goal:
  - Prove the architecture is fast and strict, then remove temporary clutter.
* Work:
  - Run the simulator proof path, keep useful diagnostics, delete temporary
    profiling-only code, and update the plan/worklog truth.
* Checklist (must all be done):
  - Run `rtk swift test --filter DockScreenStoreTests`.
  - Run relevant `DockStoreTests` / `DockStoreStreamTests`.
  - Run `rtk npm run test:relay`.
  - Run `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests'`.
  - Run `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`.
  - Inspect performance output/logs for absence of root all-row rebuilds and
    heartbeat-driven render revisions.
  - Decide whether existing `PerformanceProbe` instrumentation stays as
    permanent telemetry or is deleted before commit.
  - Update this doc and the worklog with exact command results.
* Verification (required proof):
  - Commands above.
  - `git diff --check`.
* Docs/comments (propagation; only if needed):
  - Final doc/worklog status updates only. No stale debug runbook text.
* Exit criteria (all required):
  - Tests/proof either pass or any failure is a precise external blocker, not an
    architecture/code gap.
  - Temporary diagnostics not justified as permanent are deleted.
  - No physical phone test is run or claimed.
* Rollback:
  - If simulator proof fails due code behavior, reopen the earliest responsible
    phase instead of weakening proof.

## Phase 6 - Final quality review, commit, push, and relay rollout

* Goal:
  - Ship the fix through code-quality review and update both relay deployments
    from the pushed branch.
* Work:
  - Run `$thermo-nuclear-code-quality-review`, fix blockers, commit, push, pull
    on deployment copy/copies, and restart relays. Relay rollout is required by
    the current user objective even if the relay runtime code itself is
    unchanged.
* Checklist (must all be done):
  - Run thermo-nuclear review against current branch diff.
  - Fix every blocking structural finding.
  - Rerun affected tests after fixes.
  - Stage only touched files with explicit paths.
  - Commit with a message that names the Dock render/proof cutover.
  - Push the current branch from `/Users/aelaguiz/workspace/codex-client`.
  - Update the Mac/local relay runtime from the pushed checkout as applicable.
  - Update `home` at `/home/aelaguiz/workspace/codex-client` with `git fetch`
    and `git pull --ff-only` from the pushed branch.
  - Restart the relay services required by the deployed code.
  - Copy/read `.env` only as needed for Mac-side service env; never put secrets
    into phone/simulator launch config.
  - Mark this plan and the worklog complete only after rollout proof.
* Verification (required proof):
  - `git status --short` before commit is understood.
  - `git push` succeeds.
  - `rtk make dock-relay-status` and, when reachable, the equivalent `home`
    relay status/restart output show the updated code is running.
* Docs/comments (propagation; only if needed):
  - Mark this plan/worklog complete only after rollout proof.
* Exit criteria (all required):
  - Thermo review has no unresolved blockers.
  - Commit is pushed.
  - Both relay deployments are updated from the pushed branch and restarted.
  - Plan/worklog status reflects the final shipped state.
  - No unrelated dirty work was reverted.
* Rollback:
  - Use normal git revert/redeploy if post-rollout behavior regresses. Do not
    hot-edit the `home` deployment copy as source.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. Prefer behavior-level checks that prove the
runtime contract.

## 8.1 Unit tests (contracts)

- `DockScreenStoreTests`
  - equal `(DockSnapshot, DockProjectionOptions)` skips revision/projection.
  - changed rows, host states, and options publish.
  - automation snapshots write only when enabled and only for accepted
    revisions.
- `DockStoreTests` / `DockStoreStreamTests`
  - heartbeat/no-visible-change path skips displayed publish.
  - pending rename overlay publishes once if it changes display state.
  - rename failure rollback publishes through the guarded helper.
- Snapshot writer tests
  - atomic filename shape.
  - schema version.
  - latest-5 pruning.
  - disabled production default.
- UI capture tests where practical
  - missing root `automationRevision`, missing file, malformed file, stale file,
    and revision mismatch fail loud.

## 8.2 Integration tests (flows)

- `rtk npm run test:relay` after proof fixture updates.
- Existing SwiftPM filters for Dock store/screen behavior.
- Generated Xcode project tests for UI paths after XcodeGen regeneration.

## 8.3 E2E / device tests (realistic)

- Simulator only:
  - `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests'`
  - `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
- Physical phone testing is explicitly out of scope for this goal.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

1. Finish all Section 7 phases locally.
2. Run quality review and final tests.
3. Commit and push from the Mac authoritative checkout.
4. Pull the pushed branch into the `home` deployment checkout with
   `git fetch` and `git pull --ff-only`.
5. Restart the local/Mac relay and the `home` relay from their deployment
   checkouts.

## 9.2 Telemetry changes

- Keep render enqueue / skip / publish counters if they are low-cardinality and
  useful for future regressions.
- Keep root accessibility value duration telemetry only if it is bounded and
  does not itself add measurable work.
- Delete one-off profiling code that only supported the investigation and does
  not help operate the shipped app.
- Never log `OPENAI_API_KEY`, raw app-server bearer tokens, prompt text,
  transcript text, base64 audio, or full JSON-RPC payloads.

## 9.3 Operational runbook

- Local status:

```bash
rtk make app-server-status
rtk make dock-relay-status
```

- Local restart only when rollout requires it:

```bash
rtk make dock-relay-restart
```

- `home` rollout uses `/home/aelaguiz/workspace/codex-client` as a pull-and-run
  deployment copy only. Do not author commits there.

## 9.4 Implementation proof

Final simulator/local proof after the JSON snapshot cutover and code-quality
split:

- `rtk xcodegen generate --spec project.yml` passed.
- `rtk swift test --filter DockScreenStoreTests` passed with `6` selected
  tests and `0` failures.
- `rtk swift test --filter DockRenderProjectorTests` passed with `6` selected
  tests and `0` failures.
- `rtk swift test --filter DockStoreTests` passed with `57` selected tests and
  `0` failures.
- `rtk swift test --filter AppServerThreadCardStreamClientTests` passed with
  `3` selected tests and `0` failures.
- `rtk swift test --filter RenderCoalescerTests` passed with `3` selected tests
  and `0` failures.
- `rtk npm run test:relay` passed with `195` tests and `0` failures.
- `rtk git diff --check` passed.
- `rtk node scripts/sim-ui-sync-config.mjs annotate --path <config.json>
  --simulator-udid <udid> --app-bundle-id <bundle-id> --app-data-container
  <path>` passed against a scratch config and wrote the expected simulator
  metadata.
- `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17'
  SIM_UI_SYNC_SCENARIO='mutation-ack-projection-refresh-failure'
  SIM_UI_SYNC_DURATION_MS=10000 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500
  SIM_UI_SYNC_CHECKPOINT_SWEEP=1` passed after simulator app-container metadata
  moved into the JSON proof config.
- `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17'
  SIM_UI_SYNC_SCENARIO='spawn-edge' SIM_UI_SYNC_DURATION_MS=10000
  SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_CHECKPOINT_SWEEP=1` passed after
  the Dock sampler recorded one baseline sample before advertising ready.
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` passed. Matrix
  report:
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260604T221252Z/controlled-simulator-matrix.json`;
  summary report:
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260604T221252Z/controlled-simulator-matrix.md`.
  The matrix produced `36` reports across `18` required scenarios, with `18`
  passing scenarios, `0` failed scenarios, `0` missing scenarios, and max
  observed UI lag `446 ms` against the `2000 ms` budget.
- `rtk make app-test SIM='iPhone 17'
  APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled'`
  passed on the `iPhone 17` simulator after the final proof-sampler review fix.
  Result bundle:
  `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.06.04_17-34-22--0500.xcresult`;
  log:
  `.codex-dock/logs/app-test-20260604223420.log`.

Fresh simulator log proof at `1,248` Dock rows:

```text
perf event=dock.card_projection.project all_pinned_ms=0 all_pinned_rows=0 automation_rows=1248 body_ms=1 body_rows=1248 checking_hosts=0 duration_ms=8 facets_ms=4 filter_ms=1 filtered_rows=1248 filters=0 groups=0 groups_ms=0 hosts=2 lens=newest partial=false pinned_ms=0 pinned_rows=0 rows=1248 search=false search_ms=1 searched_rows=1248 summary_ms=0 visible_ms=1 visible_rows=1248
perf event=dock.main_publish automation_snapshot=true duration_ms=30 groups=0 hosts=2 pinned_rows=0 revision=9 rows=1248 visible_rows=1248
perf event=dock.accessibility_value.built duration_ms=0 encoded_length=289 revision=9 rows=1248 visible_rows=1248
perf event=dock.store.publish_snapshot context=handleReconcilerSnapshot duration_ms=9 hosts=2 model_ms=9 partial=false pending_rename_ms=0 pending_renames=0 published=true rows=1248 screen_publish_ms=0
perf event=dock.store.publish_snapshot context=handleReconcilerSnapshot duration_ms=10 hosts=2 model_ms=9 partial=false pending_rename_ms=0 pending_renames=0 published=false rows=1248 screen_publish_ms=1
```

This proves the old root `rowValues=` bottleneck is removed from the tested
simulator path: the root accessibility value no longer carries the
`469,211`-character row payload and no longer spends `20-22 ms` rebuilding that
payload at `1,248` rows. The controlled matrix additionally proves the relay to
client displayed-state path stayed inside the `2000 ms` UI lag budget for all
required simulator scenarios. Frame hitches can still come from other
UI/runtime work, but this specific measured offender is gone and the simulator
contract now fails loud through JSON snapshot evidence instead of root-row
accessibility scraping.

Physical-phone testing is intentionally stopped by user instruction. This proof
section is simulator/local only.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-2, Sections 7-10, helper-block readiness.
  - Sections 3-7 against repo owner paths, call-site coverage, old-oracle
    deletion, proof semantics, and rollout scope.
- Findings summary:
  - Explorer 1 found the expected missing consistency-pass helper block and
    required-looking comment/worklog obligations living only under
    `Docs/comments`.
  - Explorer 2 found that JSON snapshots written from `DockScreenStore` could
    not match old row oracle semantics while collapse state stayed private to
    `DockView`.
  - Explorer 2 found environment-flag wiring owner was underspecified.
  - Explorer 2 found `sim-ui-dump` was missing from the row-proof capture
    migration.
  - Explorer 2 noted relay rollout was user-requested but not an architecture
    dependency of the Swift proof migration.
- Integrated repairs:
  - Moved required comment/worklog obligations into phase checklists and exit
    criteria.
  - Promoted collapse state into the target `DockProjectionOptions` contract and
    added `DockCardProjection.automationRows` as the canonical proof row list.
  - Added `DockStore` construction / optional writer injection as the snapshot
    environment owner.
  - Added `CodexDockCurrentUIDumpTests` / `sim-ui-dump` blocked behavior for
    already-running apps without snapshot metadata.
  - Recorded relay rollout as an intent-derived deployment requirement, not a
    relay-runtime architecture dependency.
  - Re-read the integrated plan after opening the generated receipt and found
    no new contradictions in implementation scope, test proof, or rollout
    scope.
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

## 2026-06-04 - Use existing DockScreenStore as render owner

Context

The first draft considered a new `DockPresentationPipeline` /
`DockScreenFrame` layer.

Options

- Add a new presentation pipeline.
- Put the gate inside the existing render funnel.

Decision

Use `DockScreenStore.enqueueProjection` as the single render-eligibility owner.

Consequences

Less architecture, no second owner, and the no-op rule lives where snapshot plus
projection options are both visible.

Follow-ups

Phase 1 implements the gate and tests it.

## 2026-06-04 - Exact equality before fingerprints

Context

Display fingerprints could make comparisons smaller but can collide.

Options

- Use a hash/fingerprint gate first.
- Use exact `Equatable` models first.

Decision

Use exact equality first. Consider row hashes only later as a precheck with
exact equality fallback if equality itself profiles hot.

Consequences

No real update can be dropped by a hash collision.

Follow-ups

Phase 5 profiling decides whether future row hashes are needed.

## 2026-06-04 - JSON snapshot over accessibility element

Context

Model B initially preferred a dedicated non-hidden test-only accessibility
element. Model A and final fresh consult preferred JSON.

Options

- Dedicated bulk accessibility element.
- Test-only JSON snapshot keyed by revision.

Decision

Use JSON as the single full-row proof oracle. Root carries only bounded scalar
metadata and a test-only path pointer.

Consequences

Full row proof leaves the accessibility tree entirely. XCUITest must fail loud
if the matching JSON snapshot is unavailable or mismatched.

Follow-ups

Phase 2 implements writer/reader and Phase 3 deletes the old root parser.

## 2026-06-04 - Intent-derived: current user goal confirms arch-step path

Blocker:

`arch-step reformat` normally stops for explicit North Star confirmation before
auto-plan continues.

Consulted:

Current user objective, TL;DR, Section 0, Section 7.

Intent says:

The user explicitly asked to turn this doc into a full `$arch-step auto-plan`,
then use `$arch-step auto-implement`, test in simulator, run thermo review,
commit/push, and update relay servers.

Decision:

Treat the current objective as explicit North Star confirmation and set
`status: active` instead of stopping for a redundant question.

Consequences:

The plan can proceed through auto-plan receipts without asking for confirmation
already present in the current goal.

Follow-ups:

None.

## 2026-06-04 - Resolve automation snapshot implementation details

Context

Earlier plan versions left launch flag, filename, and retention as
implementation details.

Options

- Leave them open until coding.
- Resolve them in the arch-step plan so implementation has no branch.

Decision

Use `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1`,
`dock-automation-snapshot-<revision>.json`, app Application Support
`CodexDock/DockAutomationSnapshots`, an Application Support relative root
`automationSnapshotPath`, XCUITest simulator-container resolution through
`CODEX_DOCK_UI_TEST_SIMULATOR_UDID` plus
`CODEX_DOCK_UI_TEST_APP_BUNDLE_ID` and
`xcrun simctl get_app_container <udid> <bundle-id> data`, and latest-5
retention.

Consequences

Implementation can proceed without reopening the proof-channel design, and
XCUITest does not have to infer whether the app wrote an absolute path, a host
path, or a simulator-internal path.

Follow-ups

Phase 2 implements this exact contract.

## 2026-06-04 - Make UI-test snapshot wiring explicit

Context

Fresh consult found that the plan named simulator-container lookup but did not
fully say how ordinary UI tests receive the simulator UDID and app bundle id,
and that copied `launchRelayBackedApp` helpers could drift.

Options

- Let each UI test infer its own simulator/container inputs.
- Reuse only `sim-ui-dump`'s JSON config.
- Add one shared UI-test launch helper plus Makefile-exported resolver
  environment for normal UI tests.

Decision

Use one shared relay-backed UI-test launch helper for
`CODEX_DOCK_AUTOMATION_SNAPSHOTS=1`. `sim-ui-dump` resolves snapshot files from
`DisplayedUICurrentDumpConfig`. Normal Makefile-owned simulator UI tests resolve
snapshot files from `CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER`, exported beside
the existing `xcodebuild` commands after Makefile resolves the path with
`xcrun simctl get_app_container`.

Consequences

The row proof channel has one launch flag owner, and file lookup no longer
depends on undocumented Xcode environment behavior.

Follow-ups

Phase 2 adds the shared helper, Makefile exports, and snapshot file resolver.

## 2026-06-04 - Resolve stale Xcode-installed simulator containers by file existence

Context

`xcodebuild test` can replace the simulator app data container after Makefile
has resolved `CODEX_DOCK_UI_TEST_APP_DATA_CONTAINER`. The first failing proof
showed config pointing at an old container while the app wrote
`dock-automation-snapshot-<revision>.json` in the new container.

Options

- Trust the pre-test container path.
- Shell out from Swift UI tests.
- Let the UI test resolver try all known simulator containers and choose the
  one that contains the advertised snapshot file.

Decision

Keep Makefile as the shell owner. `app-test` writes a simulator-visible JSON
config with simulator UDID, bundle id, and any pre-test container path.
`DisplayedUICaptureSupport` then tries the configured container, the discovered
simulator app container, and env-provided containers, and selects the candidate
where the advertised snapshot file actually exists.

Consequences

The strict JSON proof remains file-based and deterministic even when Xcode
reinstalls the app into a fresh simulator data container during `xcodebuild
test`. Swift UI tests still do not run `xcrun`.

Follow-ups

Keep the resolver strict: if no candidate contains the advertised snapshot file,
the proof fails loud instead of reconstructing Dock truth from the accessibility
tree.

## 2026-06-04 - Projection-owned collapse state

Context

The old root `rowValues=` oracle depends on private `DockView` collapse state.
A JSON writer in `DockScreenStore` cannot reproduce that row set while collapse
state remains private to the view.

Options

- Redefine JSON proof as uncollapsed projection rows.
- Promote collapse state into `DockProjectionOptions` and make projection own
  proof rows.

Decision

Promote collapse state into the projection options contract and add projected
automation/proof rows.

Consequences

`DockScreenStore` can write the exact proof rows without `DockView` building
all-row data or owning hidden row-selection truth.

Follow-ups

Phase 2 moves the state and Phase 3 deletes the old view helper.

## 2026-06-04 - Intent-derived: relay rollout remains required

Blocker:

The Swift/UI proof migration may not change relay runtime code, but the current
user objective explicitly requires updating both servers with latest code/relay.

Consulted:

Current user objective, TL;DR Plan, Section 7 Phase 6, Section 9.

Intent says:

After implementation and review, commit/push and update both servers with latest
code/relay.

Decision:

Keep relay update/restart as a rollout requirement, but record it as a
user-requested deployment obligation rather than an architectural dependency of
the Swift proof migration.

Consequences:

Phase 6 must update both deployments from the pushed branch even if no relay
source file changes.

Follow-ups:

Use the Mac checkout as source of truth and `home` only as a pull-and-run
deployment copy.

## 2026-06-04 - Composer 2.5 Fast auto-plan sign-off

Context

The current user objective requires `$fresh-consult composer-2.5-fast` to agree
that this plan is exhaustively specified, unified, and deletes old row-proof
paths with no test exceptions before `$arch-step auto-implement` proceeds.

Consulted

`/tmp/fresh-consult/dock-lightning-fast-arch-plan-20260604T211426Z-gpvW9n/final.txt`

Decision

Accept the consult as the required Composer 2.5 Fast sign-off. It returned
`VERDICT: pass`, `BLOCKING: none`, and `CONFIDENCE: high`.

Consequences

The plan has passed both the generated `$arch-step auto-plan` receipt gate and
the user-requested independent Composer gate. Implementation can proceed through
`$arch-step auto-implement` against current repo state.

Follow-ups

Create or update the implementation worklog during `$arch-step auto-implement`
and use the implementation audit block as the authoritative code-completeness
verdict.

## 2026-06-04 - Make simulator UI proof config self-contained

Context

The controlled simulator proof failed because `xcodebuild test-without-building`
did not reliably forward the custom shell environment that the UI test used to
locate the app data container. The product path was correct, but the proof
sampler could not always find the JSON automation snapshot after Xcode
reinstalled the simulator app.

Options

- Keep relying on process environment.
- Shell out from Swift UI tests.
- Store simulator UDID, app bundle id, and optional app data container in the
  existing simulator UI sync JSON config.

Decision

Keep Makefile as the shell owner and annotate the existing simulator UI sync
config through `scripts/sim-ui-sync-config.mjs`. The UI test resolver now reads
that config before process environment and still fails loud if no candidate
container contains the advertised snapshot file.

Consequences

Simulator proof no longer depends on undocumented `xcodebuild` environment
forwarding, and Swift UI tests still avoid shelling out.

Follow-ups

None.

## 2026-06-04 - Sample baseline before controlled fixture mutation

Context

The `spawn-edge` controlled simulator proof briefly exceeded the `2000 ms`
transition budget because the Dock-only UI sampler marked itself ready before it
had captured any Dock sample. The controlled fixture could mutate immediately,
so the judge measured from the relay transition timestamp to the first later UI
sample instead of from an already-observed baseline.

Options

- Increase the UI lag budget.
- Add a scenario-specific delay.
- Capture one baseline Dock sample before writing the ready file.

Decision

Capture one baseline sample before `DisplayedUIArtifactWriter.markReady(...)`
in the Dock-only sampler branch.

Consequences

The fixture mutates only after the sampler has real UI evidence. Targeted
`spawn-edge` proof passed, and the final full controlled matrix passed with max
observed UI lag `446 ms`.

Follow-ups

None.

# Appendix B) Conversion Notes

- This document was converted in place from the previous
  `DOCK_LIGHTNING_FAST_ARCHITECTURE_FIX_PLAN_2026-06-04.md` so it remains the
  one canonical `DOC_PATH`.
- Prior `$model-consensus` and `$fresh-consult` outcomes were preserved in
  frontmatter, decisions, and the target architecture.
- The old `Open Questions` section was resolved because the current user goal
  requires an exhaustive arch-step plan before implementation.
