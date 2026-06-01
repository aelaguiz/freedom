---
title: "Codex Dock - Live Update Architecture And Testing - Architecture Reference"
date: 2026-06-01
status: implemented
implementation_allowed: true
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [Composer 2.5 Fast, plan-audit, thermo-nuclear-code-quality-review]
doc_type: phased_refactor
related:
  - docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md
  - docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md
  - docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_WORKLOG.md
  - .arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/
---

# TL;DR

## Outcome

Codex Dock must show current Dock, Archive, and Thread Detail state through one
relay-owned production truth path, and every freshness claim must be proven over
time from source change to rendered iPhone UI state.

## Problem

The app can look connected while the data is stale because liveness,
freshness, current-screen proof, relay state, Swift state, and test evidence are
not all bound to one contract. Static snapshots and route-health checks can
pass while the simulator still shows a stale or wrong Thread view.

## Approach

Make the relay the only owner of card truth, order, freshness, stream identity,
and heartbeat. Make Swift render that contract, reject stale compatible state,
rehydrate Thread Detail when relay recovery invalidates continuity, and expose a
canonical current-simulator UI dump command for what the app is showing right
now. Proof must be retained JSON/Markdown over time, not screenshots,
recordings, or one-shot fixtures.

## Plan

Implementation moved depth-first through the real seams: current-simulator UI
dump, heartbeat/liveness, Swift stream guards, active Archive stream parity,
Thread Detail recovery and full history, relay freshness, proof schemas,
proof cadence, and README/runbook alignment. Final simulator evidence is
retained at
`/tmp/codex-client/sim-ui-controlled-matrix-final3-20260601T055358Z/controlled-simulator-matrix.json`.

## Non-negotiables

- No raw app-server `:4500` phone path for production app behavior.
- No local metadata, diagnostics, preview fixtures, or Thread Detail history as
  Dock or Archive card truth.
- No screenshots or recordings as displayed-state proof.
- No skipped UI proof interpreted as a live-update pass.
- No runtime fallback or compatibility shim unless this doc explicitly changes
  `fallback_policy` and logs the exception.
- No side doors kept for tests.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-06-01
external_research_grounding: done 2026-06-01
deep_dive_pass_2: done 2026-06-01
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:743ccc73a99b608cd1a00149270958d4481b4a06eceadf788c9bc3a521316290",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-01T01:10:29Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:4a7c44cba127600d83e6cbcbf034a5eb8b67e4868204c5034166909731ffcdcf",
      "completed_at": "2026-06-01T01:11:02Z",
      "doc_hash_after": "sha256:ab09f18f8d40ed721117c8e441080bf2605aa7555c625b723bad75edc621d737"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-01T01:11:10Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:ab09f18f8d40ed721117c8e441080bf2605aa7555c625b723bad75edc621d737",
      "completed_at": "2026-06-01T01:13:55Z",
      "doc_hash_after": "sha256:529817a90494ae494df3868cd18f333a07a121928aa429e9b76656fede3a2dd2"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-01T01:14:06Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:529817a90494ae494df3868cd18f333a07a121928aa429e9b76656fede3a2dd2",
      "completed_at": "2026-06-01T01:14:27Z",
      "doc_hash_after": "sha256:625ef0742104839443b16cc4de1912b065c62798bb985a054867a15c06ee1db1"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-01T01:14:38Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:625ef0742104839443b16cc4de1912b065c62798bb985a054867a15c06ee1db1",
      "completed_at": "2026-06-01T01:15:13Z",
      "doc_hash_after": "sha256:45268dedf19924a3dc0b33376cf46ac2eaef4abe1c57b54e6d11f2104cdc3c3c"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-01T01:15:27Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:45268dedf19924a3dc0b33376cf46ac2eaef4abe1c57b54e6d11f2104cdc3c3c",
      "completed_at": "2026-06-01T01:22:43Z",
      "doc_hash_after": "sha256:f16b795a20ceb3ba63baa2d38258f102e952fa3b0c8d85ac30d38624917b551f"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this plan is implemented, a source-state change in real or controlled
Codex data will converge through relay projection, Swift stream/session clients,
and rendered iPhone UI samples within the configured lag budget, and any failure
to prove current data will show as stale, partial, reconnecting, offline,
error, or blocked instead of fresh.

## 0.2 In scope

- Relay-owned Dock and Archive card truth: existence, order, activity time,
  status, archive state, freshness, completeness, and stream identity.
- Swift stream/session handling for `dock/*`, `archive/*`, and Thread Detail
  history/live sessions.
- Heartbeat as the canonical liveness contract for Dock and Archive streams.
- Swift rejection of stale compatible snapshots and stream corruption.
- Thread Detail history path using `thread/read includeTurns:false`, full paged
  `thread/turns/list`, and `thread/resume excludeTurns:true`.
- Relay upstream Thread Detail recovery made visible to Swift by closing the
  downstream socket unless a later sanctioned generation-stamped resync protocol
  is explicitly planned.
- Relay freshness fail-closed behavior for history, live, lease, validation,
  archive, and source-refresh failures.
- Archive as a first-class relay view with its own convergence after
  archive/unarchive.
- Retained proof reports and schemas for relay sync, simulator UI sync,
  controlled fixture, and controlled matrix proof.
- One canonical repo-owned current-simulator UI dump command:
  `rtk make sim-ui-dump SIM='iPhone 17'`.
- README and runbook alignment with Makefile-owned commands.

## 0.3 Out of scope

- A new product feature, new app navigation model, or new Dock filtering model.
- Phone-side direct raw app-server route use as a production truth path.
- A new parallel test framework replacing existing relay and UI proof harnesses.
- A new `detail/resync` protocol in this implementation. It remains a future
  option only if generation-stamped and added everywhere in one later plan.
- Broad doc linting, stale-term greps, screenshot comparison, OCR, or visual
  golden tests as proof.
- Preserving old side doors for compatibility after the canonical path exists.

## 0.4 Definition of done (acceptance evidence)

- Fast checks pass for contract generation/checks, route parity, proof-result
  schemas, relay tests, and Swift state/session tests.
- Relay emits real heartbeat updates for Dock and Archive streams, and Swift
  marks missing heartbeat or stale freshness visibly instead of treating an open
  socket as current data.
- Swift rejects older compatible snapshots by stream generation and resyncs or
  fails visibly.
- Thread Detail requests full turn items on the detail path and rehydrates after
  downstream closure/reconnect.
- Relay source-refresh, live-lease, archive mutation, and upstream recovery
  scenarios have retained machine-readable proof.
- `rtk make sim-ui-dump SIM='iPhone 17'` dumps the current Dock or Thread view
  as structured accessibility JSON plus a short summary.
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` passes for the
  update-path scenarios before simulator behavior is claimed fixed.
- Physical-phone claims are not made without the physical device proof target
  from the repo runbook.
- README and command docs name only executable, Makefile-owned proof paths.

## 0.5 Key invariants (fix immediately if violated)

- Card truth has one production owner: the relay.
- Freshness is data proof, not connection proof.
- Stream identity is observable: `schemaVersion`, `view`, `epoch`, `seq`, and
  `stateGeneration` must move together.
- Heartbeat never mutates rows and never marks failed data fresh.
- Thread Detail live continuity is not trusted across invisible relay upstream
  recovery.
- Simulator displayed-state proof is accessibility/UI-state JSON, not
  screenshots or recordings.
- Current simulator inspection has one canonical path:
  `rtk make sim-ui-dump SIM='iPhone 17'`. It must dump the already-visible Dock
  or Thread Detail accessibility state without relaunching, navigating, seeding,
  or taking screenshots.
- Tests must exercise updates over time where update behavior is the product.
- Simulator UI proof must compare visible top-to-bottom Dock row order and
  Thread Detail message order against relay truth. Membership alone is not
  enough.
- Deleted side doors stay deleted; test-only paths cannot preserve retired
  behavior.

# Implementation Evidence

Final local simulator proof passed on 2026-06-01:

- Matrix report:
  `/tmp/codex-client/sim-ui-controlled-matrix-final3-20260601T055358Z/controlled-simulator-matrix.json`.
- Summary: 12 required scenarios, 12 passing, 0 missing, 0 failed, 0
  unexpected, 0 findings, max observed UI lag 1914 ms.
- Order proof included:
  - Dock visible order checks in `large-list-checkpoint`, `thread-activity`,
    `multi-host-isolation`, `resync-gap`, and `rapid-mutations`.
  - Dock checkpoint sweep order checks in `large-list-checkpoint`,
    `thread-activity`, `multi-host-isolation`, `resync-gap`, and
    `rapid-mutations`.
  - Thread Detail message order checks in `detail-reconnect` and
    `detail-history-request`.
- Contract and unit verification after the final order-proof fixes:
  - `rtk npm run contract:check` passed.
  - `rtk npm run test:relay` passed with 86 tests.
  - `rtk swift test --filter DockStoreTestsProjection` passed with 25 tests.
  - `rtk make app-test SIM='iPhone 17'` passed.
- Current simulator dump evidence after final blocked-artifact validation
  hardening:
  `/tmp/codex-client/sim-ui-dump-20260601T061107Z/sim-ui-dump.json`,
  status `pass`, screen `dock`, 51 visible elements, 4 Dock rows.
- Final Composer 2.5 Fast fresh consult:
  `/tmp/fresh-consult/codex-dock-live-update-implementation-20260601T060601Z-GNhrn8/final.txt`,
  verdict `pass-with-notes`, blocking findings `none`.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. User-visible correctness: the top Dock row and open Thread view must reflect
   the newest provable state or explicitly show why they are stale.
2. Single source of truth: card facts and freshness come from relay stream
   contracts, not local reconstruction.
3. Fail-loud recovery: stale, corrupt, or unproven state must become visible
   and trigger rebuild/resync paths.
4. Realistic proof: source changes must be observed over time in the simulator
   UI and retained as data.
5. Small repo-native implementation: extend existing Makefile, Swift tests,
   Node tests, contract generation, and UI proof harnesses.

## 1.2 Constraints

- Mobile build/test/launch commands are Makefile-owned.
- Production timeouts, intervals, ports, and caps belong in
  `CodexDock/Configuration/CodexDockConstants.swift` or
  `scripts/dock-relay-constants.mjs`.
- Phone paths must not carry raw bearer tokens or OpenAI keys.
- The relay SQLite cache is a projection cache only; Codex/app-server history
  remains durable source history.
- The current worktree is dirty from adjacent work; this plan must not revert
  unrelated edits.

## 1.3 Architectural principles (rules we will enforce)

- Extend the existing `dock/*` and `archive/*` stream contract instead of adding
  a second card-truth API.
- Add behavior-level proof at the route/state/UI boundary instead of broad
  repository policing.
- Keep current-screen inspection canonical and simple: one Makefile target, one
  JSON artifact, one short summary.
- Use code comments only at sharp contract boundaries such as heartbeat,
  generation rejection, and simulator UI dumping.
- Prefer hard cutover and deletes over compatibility shims.

## 1.4 Known tradeoffs (explicit)

- Closing Thread Detail downstream sockets on upstream recovery is blunt, but it
  reuses Swift's existing rehydrate path and avoids a half-designed replay
  protocol.
- Adding proof-result schemas is extra contract work, but it prevents proof
  reports from drifting into unauditable JSON blobs.
- The simulator current-screen dump is operator evidence, not acceptance proof;
  it is intentionally lighter than the full displayed-UI sync proof.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The relay materializes Dock and Archive card projections in SQLite and serves
`dock/subscribe`, `dock/update`, `dock/resync`, `archive/subscribe`,
`archive/update`, and `archive/resync`. Swift consumes those streams through
`AppServerThreadCardStreamClient`, applies them in `ThreadCardTable`, and
renders through `DockStore`, `ArchiveStore`, and screen stores. Thread Detail
loads history with `thread/read`, paged `thread/turns/list`, then
`thread/resume`.

The repo also has relay scenario proof, controlled simulator fixture proof, and
XCTest accessibility sampling through `CodexDockDisplayedSyncProofTests`.

## 2.2 Original broken / missing behavior (concrete)

- Relay schema and Swift understand `kind:"heartbeat"`, but production relay
  subscriptions do not emit periodic heartbeat updates.
- Swift applies compatible snapshots without rejecting older
  `stateGeneration` values.
- Relay upstream Thread Detail recovery can succeed invisibly, leaving the phone
  connected without forcing a rehydrate.
- `ThreadTurnsListParams` has no `itemsView`, so the detail path cannot require
  `itemsView:"full"` even though the proof script can.
- Live endpoint/source failures can be hidden by history completeness instead
  of failing the visible freshness state closed.
- Archive mutation scheduling exists but Archive convergence is not yet a
  first-class invariant equal to Dock convergence.
- Proof harnesses exist but are not fully schema-guarded, scheduled, or
  required for update-path changes.
- There is no repo-owned lightweight command to dump the current simulator Dock
  or Thread visual state on demand.

## 2.3 Current implementation state

The implemented architecture closes the original gaps:

- Production relay subscriptions emit heartbeat updates for Dock and Archive.
- Swift stream application rejects stale compatible generations and uses one
  shared stream lifecycle for Dock and active Archive.
- Archive Cleanup no longer owns a cleanup-only Dock snapshot side door.
- Thread Detail requests full turn items on the visible detail path and
  rehydrates after relay upstream recovery closes the downstream phone socket.
- Live-source refresh failures make relay freshness stale/partial instead of
  publishing falsely fresh state.
- Proof reports are schema-checked and reject raw app-server `:4500` evidence,
  scripted stream side doors, mismatched proof run IDs, and missing route
  evidence.
- `rtk make sim-ui-dump SIM='iPhone 17'` dumps the current simulator screen as
  accessibility JSON/Markdown without relaunching, navigating, seeding, or
  taking screenshots.
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` proves over-time
  convergence from controlled relay truth to visible simulator UI, including
  visible ordering.

## 2.4 Constraints implied by the problem

The fix cannot be a single Swift UI patch. It must bind the relay data contract,
Swift state model, Thread Detail session model, proof artifacts, and Makefile
entrypoints so a stale simulator cannot look "green" because only static or
diagnostic checks ran.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- No external source is required for the architecture decision. This is a
  repo-local protocol and state-convergence problem: the correct anchors are
  the app/relay code, generated contract schema, Makefile, and existing proof
  harnesses.
- Adopt the general distributed-systems rule that a connected transport is not
  data freshness. In this repo that rule is concretely implemented through
  relay-owned freshness fields, heartbeat, stream sequence, and retained
  over-time proof.
- Reject screenshot or recording review as proof. The existing XCTest
  accessibility sampler already exposes the literal rendered UI state as data,
  which is more precise and automatable for this app.

## 3.2 Internal ground truth (code as spec)

Authoritative behavior anchors:

- `README.md` - states the intended service path: phone uses the Dock relay on
  `:4510`; `dock/subscribe` returns snapshots; `dock/update` pushes deltas and
  heartbeats; `dock/resync` replaces state after sequence gaps; diagnostics do
  not prove card freshness.
- `Makefile` - owns app, service, simulator, physical device, and proof
  commands. New operator/proof entrypoints must live here.
- `contract/dock/dock-thread-card.schema.json` - generated stream contract for
  Dock and Archive cards. It already allows `kind:"heartbeat"` and requires
  `schemaVersion`, `view`, `epoch`, and `seq`.
- `CodexDock/AppServer/DockThreadCardDTO.swift` - generated Swift DTO for the
  stream contract. It already models heartbeat, freshness, `stateGeneration`,
  `epoch`, and `seq`.
- `scripts/dock-relay-state-subscriptions.mjs` - current relay subscription
  hub. It creates snapshots and deltas but does not yet emit periodic
  heartbeat updates.
- `scripts/dock-relay-state-engine.mjs` - current relay state engine for Dock,
  Archive, reconciliation, catch-up windows, freshness, and archive mutation
  ingestion.
- `scripts/dock-relay-thread-data.mjs` - current relay bridge to raw app-server
  history and live loaded rows. It owns human filtering, live lease inputs, and
  card activity proof.
- `CodexDock/State/AppServerThreadCardStreamClient.swift` - Swift stream client
  for Dock and Archive subscription/update/resync routes.
- `CodexDock/State/ThreadCardTable.swift` - Swift stream table. It handles
  schema mismatch, stream contract mismatch, epoch mismatch, sequence gap,
  heartbeat, partial windows, and freshness-to-host-status mapping, but it does
  not yet reject older compatible snapshots by `stateGeneration` and currently
  hard-codes `update.view == .dock`.
- `CodexDock/State/DockStore.swift` - Dock stream lifecycle owner. It opens,
  resyncs, applies updates, handles stream failure, reconnects, publishes
  snapshots, and reports connectivity.
- `CodexDock/State/ArchiveStore.swift` and `CodexDock/Archive/ArchiveDataEngine.swift`
  - Archive currently loads snapshots through `archive/subscribe`; it does not
  hold a long-lived stream the same way Dock does.
- `CodexDock/Archive/ArchiveCleanupDataEngine.swift` and
  `CodexDock/State/ArchiveCleanupStore.swift` - Archive Cleanup preview
  currently loads Dock snapshots through `ThreadCardHostSnapshotLoader` and is
  a product UI side door around shared stream freshness.
- `CodexDock/Runtime/ClientRuntime.swift` and
  `CodexDock/Features/Dock/DockView.swift` - current runtime/root wiring
  creates Dock, Archive, and Archive Cleanup stores independently; these call
  sites must move with any shared stream lifecycle extraction.
- `CodexDock/State/ThreadDetailStore.swift` - Thread Detail load and rehydrate
  path. It already reads full history then resumes live, marks stale on stream
  end/errors, and rehydrates on reconnect/foreground. Its `thread/turns/list`
  params do not include `itemsView:"full"`.
- `scripts/dock-relay.mjs` - relay route dispatch and focused Thread Detail
  upstream handling. It currently retries upstream recovery and keeps the
  downstream socket open on successful recovery.
- `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` - current
  accessibility sampler for displayed Dock and Thread Detail state. The capture
  types are private to the proof test and should be extracted/reused for the
  current-screen dump path.
- `scripts/dock-relay-sync-audit.mjs`,
  `scripts/dock-relay-controlled-simulator-fixture.mjs`,
  `scripts/dock-relay-simulator-ui-sync-proof.mjs`, and
  `scripts/dock-relay-controlled-simulator-matrix.mjs` - existing over-time
  proof harness family. The plan should extend these instead of creating a new
  framework.

Canonical path / owner to reuse:

- Dock and Archive card truth: relay state engine/store/subscriptions plus the
  generated `contract/dock` schema and Swift DTOs.
- Swift rendering and local decoration: `DockStore`, `ArchiveStore`,
  `ThreadCardTable`, `DockScreenStore`, local metadata, and projection code.
- Thread Detail completeness: `ThreadDetailStore` via `thread/read`,
  full-paged `thread/turns/list`, and `thread/resume`.
- Current simulator visual state: XCTest accessibility, sharing the capture
  logic currently embedded in `CodexDockDisplayedSyncProofTests`.
- Runnable entrypoints: `Makefile`, not ad-hoc shell commands.

Adjacent surfaces tied to the same contract family:

- `scripts/generate-dock-thread-card-contract.mjs` and
  `scripts/check-dock-thread-card-contract.mjs` must move with any stream schema
  change.
- Relay fixtures under `contract/dock/fixtures/` must remain schema-compatible.
- Swift tests in `CodexDockTests/DockStoreStreamTests.swift`,
  `CodexDockTests/ThreadDetailStoreTests.swift`,
  `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`,
  `CodexDockTests/ArchiveDataEngineTests.swift`, and relay Node tests must cover
  changed state behavior.
- Proof reports from sync audit, simulator UI proof, controlled fixture, and
  matrix need schemas or shared validation so report consumers cannot drift.
- README and the live-update runbooks must name only Makefile-owned commands
  that actually exist.

Compatibility posture (separate from `fallback_policy`):

- Preserve the existing stream schema version unless implementation discovers a
  required payload shape change. Heartbeat already exists in the schema and DTO.
- Add `itemsView` as an optional `ThreadTurnsListParams` field and use
  `itemsView:"full"` on the production Thread Detail path. This preserves
  app-server compatibility while making detail completeness explicit.
- Clean-cutover relay upstream recovery behavior: on upstream recovery success,
  close the downstream Thread Detail socket so Swift's existing rehydrate path
  owns continuity. No runtime bridge.
- Add proof report schemas as new contracts; fail validation when a report is
  malformed instead of accepting loose JSON.
- Add `rtk make sim-ui-dump SIM='iPhone 17'` as a new operator command without
  replacing the existing displayed-UI proof commands.

Existing patterns to reuse:

- Constants live in `CodexDockConstants.swift` and
  `dock-relay-constants.mjs`.
- JSON schema plus generator/checker already exists for Dock card DTOs.
- Relay structured logging goes through `scripts/dock-relay-logger.mjs`; Swift
  app diagnostics go through `DockLog`.
- Makefile targets already write proof artifacts under `/tmp/codex-client/...`
  and detailed build/test logs under `.codex-dock/logs/`.
- XCTest accessibility capture already produces JSONL UI samples; reuse that
  style for the current-screen dump.

Duplicate or drifting paths relevant to this change:

- Route health (`/readyz`, `/statusz`, `/routesz`, `/metricsz`, `/syncz`) can
  still be mistaken for data freshness if docs or UI wording blur the boundary.
- Archive loading uses a snapshot loader rather than the long-lived Dock stream
  lifecycle; the plan must decide exactly how much Archive parity is required
  without inventing unnecessary UI behavior.
- Archive Cleanup uses the same snapshot loader against `.dock`; if it remains
  user-visible, it is also a product side door around card-stream freshness.
- `ThreadCardTable` currently rejects non-Dock stream views; Archive cannot
  share the same application rules until expected view is explicit.
- `dock-relay-sync-audit.mjs` supports `--turn-items-view`, but production
  Thread Detail Swift params do not.
- The simulator UI proof can dump accessibility data only during a proof run;
  operator debugging still lacks a canonical current-screen command.
- The relay sync audit supports `archive-toggle`, but the controlled simulator
  fixture rejects it while `SIM_UI_SYNC_SCENARIO` defaults to it. The plan must
  make that scenario runnable in the controlled simulator path and include it
  in the controlled matrix.

Behavior-preservation signals already available:

- `rtk make contract-check`
- `rtk npm run test:relay`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk make app-test SIM='iPhone 17'`
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`

## 3.3 Decision gaps that must be resolved before implementation

None. The open choices are implementation parameters already bounded by this
plan: exact heartbeat cadence/timeout constants, proof schema filenames, and
the internal shape of the current-screen dump helper. They do not change the
requested behavior, compatibility posture, owner path, or phase order.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- Relay entrypoint and route dispatch: `scripts/dock-relay.mjs`.
- Relay state projection: `scripts/dock-relay-state-engine.mjs`,
  `scripts/dock-relay-state-store.mjs`,
  `scripts/dock-relay-state-subscriptions.mjs`,
  `scripts/dock-relay-state-views.mjs`, and
  `scripts/dock-relay-thread-data.mjs`.
- Relay constants: `scripts/dock-relay-constants.mjs`.
- Dock stream contract: `contract/dock/dock-thread-card.schema.json`,
  generated by `scripts/generate-dock-thread-card-contract.mjs` and checked by
  `scripts/check-dock-thread-card-contract.mjs`.
- Swift DTOs and route names: `CodexDock/AppServer/AppServerMethods.swift`,
  `CodexDock/AppServer/DockThreadCardDTO.swift`, and
  `CodexDock/AppServer/ThreadDetailDTO.swift`.
- Swift stream/state owners: `CodexDock/State/AppServerThreadCardStreamClient.swift`,
  `CodexDock/State/ThreadCardTable.swift`, `CodexDock/Dock/DockDataEngine.swift`,
  `CodexDock/State/DockStore.swift`, `CodexDock/State/ArchiveStore.swift`, and
  `CodexDock/Archive/ArchiveDataEngine.swift`.
- Thread Detail owners: `CodexDock/State/ThreadDetailStore.swift`,
  `CodexDock/State/AppServerThreadDetailSession.swift`, and
  `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`.
- Proof harnesses: `scripts/dock-relay-sync-audit.mjs`,
  `scripts/dock-relay-controlled-simulator-fixture.mjs`,
  `scripts/dock-relay-simulator-ui-sync-proof.mjs`,
  `scripts/dock-relay-controlled-simulator-matrix.mjs`, and
  `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`.
- Command ownership: `Makefile` and `package.json`.

## 4.2 Control paths (runtime)

Dock today:

```text
Swift DockStore
  -> AppServerThreadCardStreamClient.connect
  -> initialize on relay
  -> dock/subscribe
  -> ThreadCardTable.applySnapshot
  -> dock/update notifications
  -> ThreadCardTable.applyUpdate
  -> DockDataEngine/DockScreenStore render
```

Archive today:

```text
Swift ArchiveStore.reload
  -> ThreadCardHostSnapshotLoader
  -> archive/subscribe
  -> ThreadCardStreamSnapshotCollector
  -> ArchiveDataEngine/ArchiveScreenStore render
```

Thread Detail today:

```text
ThreadDetailStore.load
  -> connectAndInitialize relay
  -> thread/read includeTurns:false
  -> thread/turns/list pages, sortDirection:desc
  -> thread/resume excludeTurns:true
  -> notifications/server requests
  -> ThreadDetailDataEngine render newest-first events
```

Relay state today:

```text
app-server thread/list + thread/read + thread/turns/list + live loaded rows
  -> human-started filtering
  -> canonical activity/order proof
  -> SQLite projection
  -> dock/archive snapshots and deltas
```

## 4.3 Object model + key abstractions

- `ThreadCardStreamUpdateDTO` is the Swift carrier for snapshots, deltas, and
  heartbeats.
- `ThreadCardTable.HostStreamState` stores per-host `epoch`, `seq`,
  `freshness`, `complete`, `totalRows`, `window`, hosts, and cards.
- Relay `StateSubscriptionHub` owns subscribers, epoch, snapshots, deltas, and
  update fan-out.
- Relay store `changes.seq` is the stream sequence and currently doubles as
  `stateGeneration`.
- `DockStreamFreshnessDTO` is the stream-level freshness object. Per-card
  `freshness` and `completeness` are relay-owned fields on each card.
- `ThreadDetailStore` keeps live state separately from history events and
  already knows how to mark an open detail stale and rehydrate after reconnect.

## 4.4 Observability + failure behavior today

- Swift logs stream subscribe/update/resync, rows retained under stale/offline
  freshness, Thread Detail load/rehydrate, and voice/transcription state through
  `DockLog`.
- Relay logs reconciliation, upstream recovery, source failures, archive
  reconciliation, and scenario proof through structured loggers.
- Route health endpoints exist, but they are diagnostics only.
- Swift handles sequence gaps, schema mismatch, stream contract mismatch, epoch
  mismatch, partial windows, stale heartbeat payloads, and closed streams.
- Production relay does not emit heartbeat on an interval, so Swift cannot yet
  detect a connected-but-silent subscription by heartbeat timeout.
- Relay upstream recovery can succeed without closing the downstream Thread
  Detail socket, so Swift may not rehydrate history.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Dock current state should be inspectable as data:

```text
Dock
[System Health: Fresh|Partial|Stale|Offline]
[Row title] [host] [branch] [status] [activity]
...
```

Thread Detail current state should be inspectable as data:

```text
Thread
[title]
[host] [Live|Stale|Reconnecting]
[filter] [composer]
[newest visible message/request]
...
```

The UI requirement for this plan is not a redesign. It is that the current
states above have stable accessibility values and can be dumped by
`rtk make sim-ui-dump SIM='iPhone 17'`.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (implemented)

- Add relay heartbeat constants to `scripts/dock-relay-constants.mjs`.
- Add Swift heartbeat timeout constants to
  `CodexDock/Configuration/CodexDockConstants.swift`.
- Extend `scripts/dock-relay-state-subscriptions.mjs` or the owning relay state
  layer with one heartbeat scheduler for Dock and Archive subscribers.
- Extend `ThreadCardTable` and `DockStore`/Archive stream handling with
  generation rejection and heartbeat timeout behavior.
- Parameterize `ThreadCardTable` by expected stream view so Dock and Archive
  use the same apply rules without hard-coded `.dock` acceptance.
- Replace active Archive-screen snapshot-only loading with the same card-stream
  lifecycle used by Dock. Delete `ThreadCardHostSnapshotLoader` from the
  production target after its product users are migrated. If a unit fixture
  still needs similar behavior, it must live under `CodexDockTests/**`, use
  fake DTOs, and never connect to a real relay/app-server.
- Migrate Archive Cleanup preview off `ThreadCardHostSnapshotLoader` and onto
  the same relay-owned card stream state as Dock/Archive.
- Add `itemsView` to `ThreadTurnsListParams` and update Thread Detail load and
  tests to pass `.full` on detail history.
- Add proof report schemas under one contract-owned location, preferably
  `contract/proof/`, plus a narrow Node checker.
- Extract XCTest accessibility capture from
  `CodexDockDisplayedSyncProofTests.swift` into shared UI-test support and add a
  current-screen dump test/config path for `sim-ui-dump`.
- Add Makefile targets for `sim-ui-dump` and fast drift/proof schema checks.
- Update README after behavior exists.

## 5.2 Control paths (implemented)

Dock and Archive heartbeat:

```text
StateSubscriptionHub has Dock or active Archive subscribers
  -> periodic heartbeat per subscribed view
  -> dock/update or archive/update kind:"heartbeat"
  -> Swift applies freshness/liveness without row mutation
  -> missing heartbeat timeout marks stream stale/reconnecting and resubscribes
```

Thread Detail recovery:

```text
relay upstream thread/resume socket closes
  -> relay attempts recovery
  -> on successful recovery, relay closes downstream socket
  -> Swift marks detail reconnecting/stale
  -> Swift rehydrates: thread/read -> full thread/turns/list -> thread/resume
```

Current simulator dump:

```text
rtk make sim-ui-dump SIM='iPhone 17'
  -> resolve simulator UDID
  -> run repo-owned XCTest dump path against current app
  -> attach with XCUIApplication(bundleIdentifier:"com.aelaguiz.CodexDockApp").activate()
  -> never call launch() or terminate() in dump mode
  -> read the visible accessibility state as-is; do not navigate or mutate state
  -> classify the current screen as Dock, Thread Detail, or unknown
  -> include launchMode:"activate", didRelaunch:false, screenBefore, screenAfter
  -> write /tmp/codex-client/.../sim-ui-dump.json and .md
```

## 5.3 Object model + abstractions (implemented)

- Heartbeat is a normal `ThreadCardStreamUpdateDTO` with `kind:.heartbeat`,
  current `schemaVersion`, `view`, `epoch`, current `seq`,
  current `stateGeneration`, `freshness`, and no row changes.
- Swift stores enough per-host stream state to compare snapshot
  `stateGeneration` against current state before replacing rows.
- Swift stream liveness separates transport state from data freshness:
  transport open means connected; heartbeat/update freshness proves current
  rows.
- `ThreadTurnsListParams.itemsView` is an explicit optional enum/string with
  `.full` used only by Thread Detail user-visible history.
- Proof report schemas are contracts for proof artifacts, not doc linters.
- Canonical proof status enum is `pass`, `fail`, `blocked`, and `not_run`.
  Older reference wording such as `outside-contract` is retired for new proof
  reports; represent it as `fail` with reason `outside_contract`.
- Current-screen dump output is a retained JSON object with simulator metadata,
  app/build metadata when available, screen classification, visible
  accessibility elements, Dock rollup, Thread rollup, and raw fallback tree.
- The dump path is canonical and reusable: the displayed-UI proof and
  `sim-ui-dump` must share the same accessibility parser/rollup code so the
  operator view cannot drift from the proof view.
- The shared dump/proof support has named owners:
  `CodexDockUITests/DisplayedUICaptureSupport.swift` owns accessibility
  collection and Dock/Thread rollups, and
  `CodexDockUITests/DisplayedUIArtifactWriter.swift` owns JSON/Markdown dump
  writing. Node proof code may consume the normalized Swift-emitted samples,
  but it must not re-parse raw accessibility into a second truth model.

## 5.4 Invariants and boundaries

- Relay owns Dock and Archive card truth. Swift can filter, group, pin, label,
  and render, but it cannot create/order/freshen card truth from another route.
- Archive uses the same generated card stream contract as Dock and must not
  silently drift in freshness semantics. The active Archive screen uses the
  same stream liveness model as Dock; snapshot-only Archive reads are not a
  user-visible freshness path.
- Archive Cleanup is product UI, not a test helper. This plan keeps it and
  migrates it to the same stream-backed card state; it cannot keep Dock
  snapshot loading as a cleanup-only shortcut.
- Stream corruption or stale generation causes resync/reconnect/fail-visible,
  not silent accept.
- Thread Detail history completeness is explicit: `itemsView:"full"` for
  detail, not for cheap card-order proof.
- Dock and Thread Detail displayed ordering is proof-critical. Accessibility
  samples preserve top-to-bottom frame order; sorting by identifier is forbidden
  because it can hide reversed/newest-first bugs.
- The simulator dump command is an operator inspection tool. It cannot satisfy
  over-time proof gates by itself.
- No compatibility shim is approved. `fallback_policy` remains `forbidden`.

## 5.5 UI surfaces (ASCII mockups, if UI work)

No visible redesign is required. The UI state that already exists must be
machine-inspectable:

```text
sim-ui-dump.json
{
  "screen": "dock" | "thread" | "unknown",
  "elements": [...],
  "dock": { "rootValue": "...", "rows": [...], "hosts": [...] },
  "thread": { "rootValue": "...", "headerValue": "...", "messages": [...] }
}
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Relay constants | `scripts/dock-relay-constants.mjs` | `RELAY_STATE_RECONCILE_INTERVAL_MS` family | Reconcile timing exists; no heartbeat cadence constant | Add heartbeat cadence constant and export it | Avoid scattered timing values | Relay heartbeat cadence | Relay tests |
| Swift constants | `CodexDock/Configuration/CodexDockConstants.swift` | `CodexDockConstants.Dock` | Stream schema and refresh intervals exist; no heartbeat timeout | Add heartbeat timeout/stale budget constants | Swift timeout must be centralized | Swift liveness timeout | Swift Dock stream tests |
| Relay stream hub | `scripts/dock-relay-state-subscriptions.mjs` | `StateSubscriptionHub` | Emits snapshots/deltas only | Emit periodic heartbeat per subscribed view with current seq/generation/freshness | Make documented liveness contract real | `kind:"heartbeat"` update | Relay heartbeat tests |
| Relay stream hub | `scripts/dock-relay-state-subscriptions.mjs` | `sequenceFields`, `cardDelta` | `stateGeneration` uses store seq | Ensure heartbeat carries current `stateGeneration` without incrementing row state | Heartbeat must not mutate rows | Existing schema v2 | Contract/relay tests |
| Swift stream table | `CodexDock/State/ThreadCardTable.swift` | `HostStreamState`, `applySnapshot` | Accepts compatible snapshot regardless of generation age | Store current `stateGeneration`; reject older compatible snapshots with resync reason | Prevent state moving backward | New resync reason such as `staleGeneration` | `DockStoreStreamTests` |
| Swift stream table view | `CodexDock/State/ThreadCardTable.swift` | `acceptsStreamContract` | Hard-codes `update.view == .dock` | Parameterize table or apply call by expected `DockCardStreamViewDTO` | Dock and Archive must share one application rule set | Expected view argument/config | `DockStoreStreamTests`, Archive stream tests |
| Swift stream lifecycle | `CodexDock/State/DockStore.swift` | stream tasks, `handleStreamUpdate`, reconnect | Handles stream close and resync; no heartbeat timeout | Track last update/heartbeat per host; mark stale/reconnect after timeout | Detect connected-but-stale streams | Heartbeat timeout behavior | `DockStoreStreamTests` |
| Archive stream lifecycle | `CodexDock/Archive/ArchiveDataEngine.swift`, `CodexDock/State/ArchiveStore.swift`, `CodexDock/State/ThreadCardHostSnapshotLoader.swift` | Archive loading | Loads Archive via snapshot collector, not long-lived stream | Migrate active Archive loading to the same long-lived stream lifecycle as Dock; delete production `ThreadCardHostSnapshotLoader` or move fake-only fixture behavior under tests | Avoid false Archive heartbeat claims and Archive/Dock drift | Archive uses generated card stream liveness contract | `ArchiveDataEngineTests`, `ArchiveScreenStoreTests`, stream tests |
| Archive Cleanup side door | `CodexDock/Archive/ArchiveCleanupDataEngine.swift`, `CodexDock/State/ArchiveCleanupStore.swift`, `CodexDock/Features/Archive/ArchiveCleanupView.swift` | cleanup preview | Loads Dock snapshots through `ThreadCardHostSnapshotLoader(expectedView:.dock)` | Migrate cleanup preview to shared stream-backed card state | Product UI cannot keep a cleanup-only card-truth shortcut | Cleanup uses same card truth path | `ArchiveCleanupStoreTests`, UI smoke |
| Store/root wiring | `CodexDock/Runtime/ClientRuntime.swift`, `CodexDock/Features/Dock/DockView.swift`, `CodexDock/Features/Dock/CodexDockBootstrapView.swift` | store factories | Dock, Archive, and Cleanup stores are created independently | Wire any shared stream lifecycle through runtime/root factories once | Avoid parallel store construction rules | Shared stream lifecycle injection | Runtime/store tests |
| Thread Detail DTO | `CodexDock/AppServer/ThreadDetailDTO.swift` | `ThreadTurnsListParams` | No `itemsView` field | Add optional `itemsView` with `.full` support | Detail needs full item bodies | `itemsView:"full"` | `AppServerClientTests`, `ThreadDetailStoreTests` |
| Thread Detail load | `CodexDock/State/ThreadDetailStore.swift` | `readAllTurns` | Requests thread turns without `itemsView` | Pass `itemsView:.full` on user-visible detail path | Prevent summary-only detail history | Full detail history path | `ThreadDetailStoreTests`, lifecycle tests |
| Relay pass-through | `scripts/dock-relay.mjs`, `scripts/dock-relay-thread-data.mjs` | `thread/turns/list` forwarding | Forwards params as-is; proof script has separate `--turn-items-view` | Ensure relay preserves phone-supplied `itemsView`; keep card proof cheap | Keep detail and card proof separated | No route fork | Relay tests |
| Thread Detail upstream recovery | `scripts/dock-relay.mjs` | `recoverSessionUpstream` | Keeps downstream open after successful upstream recovery | Close downstream after successful recovery so Swift rehydrates | Avoid invisible missed history | Downstream close on recovery | Relay integration/scenario tests |
| Relay source freshness | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-ingest.mjs`, `scripts/dock-relay-thread-data.mjs` | `reconcileDock`, `refreshLiveLeases`, source-refresh paths | Some failures can be counted but hidden behind history completeness | Mark affected scope stale/partial when live/source proof fails | Freshness fails closed | Freshness semantics | Relay source-refresh tests |
| Archive convergence | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-ingest.mjs`, `scripts/dock-relay-state-store.mjs` | `handleArchiveMutation`, `reconcileArchive` | Archive mutation schedules generic reconciliation | Make Dock and Archive reconciliation/publish after archive mutation first-class | Archive is a first-class view | Archive convergence invariant | Relay archive scenario tests |
| Proof schemas | `contract/proof/**`, `scripts/**` | proof report writers/checkers | Reports have `schemaVersion`/`kind` but no schema guard | Add schemas and validation for sync audit, simulator UI proof, controlled fixture, matrix reports, and `sim-ui-dump`; allowed statuses are `pass`, `fail`, `blocked`, `not_run` | Proof consumers cannot drift | Proof report contracts | `rtk npm run test:relay` or new proof check |
| Proof blocked reports | `Makefile`, `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, proof scripts | skip handling | XCTest can `XCTSkip`; wrappers can fail before writing report | Make wrappers write blocked JSON/Markdown for missing config/app/relay, expired config, sampler timeout, unknown screen, and raw `:4500` endpoint | A skipped proof cannot look green | Blocked proof report contract | UI/proof tests |
| Controlled archive scenario | `Makefile`, `scripts/dock-relay-controlled-simulator-fixture.mjs`, `scripts/dock-relay-controlled-simulator-matrix.mjs`, fixture tests | `archive-toggle` | Relay sync audit supports it, but controlled fixture rejects it; Makefile default names it | Add real controlled `archive-toggle` support and include it in matrix, or change defaults and remove it from controlled acceptance. This plan chooses to add support. | Keep archive proof runnable | Controlled `archive-toggle` scenario | Fixture/matrix tests |
| Simulator current dump | `CodexDockUITests/CodexDockCurrentUIDumpTests.swift`, `Makefile` | no target | Only proof-run UI samples exist | Add `rtk make sim-ui-dump SIM='iPhone 17'` that runs `CodexDockCurrentUIDumpTests/testDumpsCurrentVisibleScreenOnce` and writes JSON/Markdown output | Debug what sim shows right now | Current-screen dump artifact | New UI test/target |
| Simulator current dump config | `CodexDockUITests/**`, `Makefile` | no canonical dump config | Proof config is duration-oriented and scenario-oriented | Add `/tmp/codex-client/codex-dock-sim-ui-dump-config.json` plus `SIM_UI_DUMP_DIR`, `SIM_UI_DUMP_JSON`, `SIM_UI_DUMP_MD`, `EXPECTED_SCREEN`, and `EXPECTED_THREAD_ID`; sample once from the visible app screen, record `launchMode`, `didRelaunch`, `screenBefore`, `screenAfter`, and do not drive navigation | Preserve the user's real "what am I looking at?" evidence | Dump-mode config contract | New dump target test |
| UI accessibility capture | `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, new `CodexDockUITests/DisplayedUICaptureSupport.swift`, new `CodexDockUITests/DisplayedUIArtifactWriter.swift` | private capture structs/helpers | Capture logic cannot be reused | Extract shared capture and artifact writing for proof and dump tests; dump uses `activate()` and never `launch()`/`terminate()` | Avoid duplicated accessibility logic | Shared UITest support | UI proof tests |
| Proof raw endpoint rejection | `Makefile`, proof schemas/checkers, `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-simulator-ui-sync-proof.mjs` | configurable relay URL | Proof commands can be pointed at any WebSocket | Fail proof validation for raw `:4500`, missing relay identity, or route evidence without relay-owned `dock/*`/`archive/*` calls | Phone-path proof must prove relay path | Proof endpoint contract | Proof tests |
| Proof commands | `Makefile`, `package.json` | proof targets and npm scripts | Existing proof targets are opt-in; no aggregate fast drift gate | Add/align Makefile/npm targets for fast gates and proof schema validation | Update-path work needs obvious checks | Makefile-owned commands | Command smoke tests where useful |
| Docs/runbooks | `README.md`, this doc, referenced runbooks | Commands and heartbeat claims | Docs can mention stale/deleted surfaces | Update surviving docs after code behavior exists | Prevent human/agent routing drift | README as runbook source | Doc command check if narrow and executable |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  - Relay state engine/store/subscriptions own stream truth.
  - Swift `ThreadCardTable` owns stream application rules.
  - Dock and active Archive screens use the same stream lifecycle rules for
    freshness, heartbeat, generation rejection, and resync.
  - Archive Cleanup cannot own a separate card truth path; this plan keeps it
    and migrates it to the shared stream-backed card state.
  - `ThreadDetailStore` owns user-visible history completeness.
  - Makefile owns operator/proof entrypoints.
- Deprecated APIs:
  - None approved. Do not add new route variants for compatibility.
- Delete list:
  - Delete or rewrite any test fixture/helper that preserves a retired no-heartbeat,
    no-generation, summary-only detail, or hidden-upstream-recovery assumption.
  - Delete `ThreadCardHostSnapshotLoader` from production code after Archive
    and Archive Cleanup migrate. If tests need fixture behavior, create a
    test-target-only fake helper under `CodexDockTests/**`; it must not connect
    to a real relay/app-server or be used for simulator/phone proof.
  - Delete stale docs that recommend unsupported proof flags or deleted scripts;
    do not leave `old` copies beside live docs.
- Adjacent surfaces tied to the same contract family:
  - Contract schema, generated DTO, relay emission, Swift constants, tests, and
    fixtures move together.
  - Proof report writers, proof report schemas, proof consumers, and Makefile
    commands move together.
  - `ArchiveStore`, `ArchiveDataEngine`, `ArchiveCleanupStore`,
    `ArchiveCleanupDataEngine`, `ClientRuntime`, and `CodexDockRootView` move
    together for any stream lifecycle extraction.
  - README/runbook claims move only after code and checks exist.
- Compatibility posture / cutover plan:
  - Preserve stream schema v2 unless implementation requires a new field.
  - Clean-cutover behavior for upstream recovery and stale generation rejection.
  - Optional `itemsView` parameter preserves route compatibility.
- Capability-replacing harnesses to delete or justify:
  - None. The current-screen dump is deterministic XCTest accessibility capture,
    not a model or agent capability replacement.
- Live docs/comments/instructions to update or delete:
  - `README.md` service, live session, diagnostics, and proof sections.
  - Any runbook named by this plan that mentions stale commands.
  - High-leverage code comments at heartbeat, generation rejection, and UI dump
    boundaries.
- Behavior-preservation signals for refactors:
  - Existing Swift tests, Node relay tests, contract check, simulator UI proof,
    and controlled matrix proof.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| --- | --- | --- | --- | --- |
| Stream contract | `contract/dock` + generated Swift DTO | Existing schema/generator/checker | Prevent Swift/relay schema drift | include |
| Timing constants | Swift and MJS constants files | Central constants | Prevent hidden timeouts | include |
| Relay stream fan-out | `StateSubscriptionHub` | One stream hub emits all stream events | Prevent heartbeat side channel | include |
| Swift stream rules | `ThreadCardTable` | One application table for snapshots/deltas/heartbeat | Prevent per-store drift | include |
| Archive product surfaces | `ArchiveStore` and `ArchiveCleanupStore` | Shared stream-backed card state | Prevent cleanup/archive side doors | include |
| Thread Detail history | `ThreadDetailStore.readAllTurns` | One detail history path | Prevent summary/full split | include |
| Simulator UI state | XCTest accessibility capture | Shared capture support | Prevent proof/dump divergence | include |
| Proof artifacts | Existing proof harness family | Schematized retained reports | Prevent proof report drift | include |
| Docs commands | Makefile source of truth | Narrow executable command checks | Prevent stale runbook commands without broad linting | include |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
## Phase 1 - Canonical Current-Simulator UI Dump

Goal: make "what is the simulator showing right now?" answerable with one repo
command before deeper live-update changes begin.

Changes:

- Extract the accessibility capture and rollup logic from
  `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` into
  `CodexDockUITests/DisplayedUICaptureSupport.swift` and
  `CodexDockUITests/DisplayedUIArtifactWriter.swift`.
- Add a dump-mode UI test path that attaches to/activates the currently
  installed simulator app without relaunching by default, samples once, and
  does not navigate, filter, seed, or mutate app state.
- Add `CodexDockUITests/CodexDockCurrentUIDumpTests.swift` with
  `testDumpsCurrentVisibleScreenOnce`.
- Dump mode must use
  `XCUIApplication(bundleIdentifier: "com.aelaguiz.CodexDockApp").activate()`
  and must not call `launch()` or `terminate()`.
- Add `rtk make sim-ui-dump SIM='iPhone 17'` to `Makefile` help and `.PHONY`.
- Add dump variables:
  `SIM_UI_DUMP_DIR`, `SIM_UI_DUMP_JSON`, `SIM_UI_DUMP_MD`,
  `EXPECTED_SCREEN`, and `EXPECTED_THREAD_ID`.
- Write dump config to
  `/tmp/codex-client/codex-dock-sim-ui-dump-config.json`.
- Write both:
  - `/tmp/codex-client/.../sim-ui-dump.json`
  - `/tmp/codex-client/.../sim-ui-dump.md`
- Include simulator UDID/name, app bundle/build metadata when available,
  timestamp, screen classification (`dock`, `thread`, `unknown`), all visible
  accessibility elements, Dock rollup, Thread Detail rollup, and raw fallback
  tree when structured extraction fails.
- Include `launchMode:"activate"`, `didRelaunch:false`, `screenBefore`,
  `screenAfter`, and the active `threadID` when the current screen is Thread
  Detail.
- Share the parser/rollup with displayed-UI proof; do not create a second
  parser that can drift.

Acceptance:

- `rtk make sim-ui-dump SIM='iPhone 17'` succeeds while the simulator is already
  showing Dock or Thread Detail.
- The JSON says which screen is visible and includes the currently visible
  rows/messages as accessibility data.
- The JSON proves dump mode did not relaunch or navigate:
  `launchMode == "activate"`, `didRelaunch == false`, and `screenBefore` equals
  `screenAfter`.
- When the simulator starts on Thread Detail, the same `threadID` is still
  visible after the dump.
- Unknown screens still produce a raw accessibility dump and a non-fresh
  summary, not a fake pass.
- Missing app, missing config, malformed config, inability to activate without
  relaunch, or failed expected screen/thread match writes a `blocked` or `fail`
  JSON/Markdown artifact and exits nonzero.
- `EXPECTED_SCREEN=thread EXPECTED_THREAD_ID=<id> rtk make sim-ui-dump
  SIM='iPhone 17'` fails if the visible Thread Detail is not that thread.
- The command is documented as operator evidence only; it cannot replace
  over-time update proof.

Checks:

```bash
rtk make sim-ui-dump SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
```

## Phase 2 - Heartbeat And Stale-Stream Vertical Slice

Goal: make a connected card stream prove freshness continuously instead of
trusting an open socket.

Changes:

- Add relay heartbeat cadence constants in `scripts/dock-relay-constants.mjs`.
- Add Swift heartbeat timeout constants in
  `CodexDock/Configuration/CodexDockConstants.swift`.
- Emit `kind:"heartbeat"` updates from `StateSubscriptionHub` for subscribed
  Dock and Archive views with current `schemaVersion`, `view`, `epoch`, `seq`,
  `stateGeneration`, and `freshness`, without row changes.
- Add Swift heartbeat receipt/timeout handling so missing heartbeat marks the
  host stream stale/reconnecting and uses the existing resubscribe/resync path.
- Keep heartbeat separate from row mutation and data freshness. Heartbeat can
  prove the stream is alive; it cannot freshen failed source data.

Acceptance:

- Relay tests prove heartbeat is emitted, stops when no subscribers exist, and
  never increments row state by itself.
- Swift tests prove default connected state can become stale when heartbeats or
  updates stop.
- Existing heartbeat DTO/schema remains the one contract path unless
  implementation proves a schema field is missing.

Checks:

```bash
rtk npm run test:relay
rtk swift test --filter DockStoreTests
```

## Phase 3 - Monotonic Stream State And Shared Dock/Archive Lifecycle

Goal: stop old compatible snapshots from moving the UI backward and remove the
Archive snapshot-only product side path.

Changes:

- Store and compare per-host `stateGeneration` in `ThreadCardTable`.
- Reject older compatible snapshots or deltas with an explicit stale-generation
  resync reason.
- Parameterize `ThreadCardTable` by expected stream view so `.dock` and
  `.archive` use one application table instead of separate accept rules.
- Extract or consolidate the shared stream lifecycle rules used by Dock and the
  active Archive screen: subscribe, apply snapshot, apply delta, apply
  heartbeat, detect stale, resync, reconnect, and expose visible freshness.
- Move active Archive loading off product snapshot-only reads and onto the same
  generated card-stream contract. Delete production `ThreadCardHostSnapshotLoader`;
  if tests need a fake fixture, create it under `CodexDockTests/**` only.
- Move Archive Cleanup preview onto the shared stream-backed card state. Do not
  keep cleanup-specific Dock snapshot loading.
- Make archive/unarchive trigger Dock and Archive reconciliation/publish as one
  first-class state change.

Acceptance:

- Dock and Archive use the same freshness/liveness semantics when visible.
- Tests prove older `stateGeneration` cannot replace newer UI state.
- Tests prove archive/unarchive converges in both Dock and Archive views.
- No product UI path treats `archive/subscribe` as a one-shot freshness answer.
- Archive Cleanup has no separate product card-truth path.

Checks:

```bash
rtk swift test --filter DockStoreTests
rtk swift test --filter ArchiveDataEngineTests
rtk swift test --filter ArchiveCleanupStoreTests
rtk npm run test:relay
```

## Phase 4 - Thread Detail Full History And Visible Recovery

Goal: make open Thread Detail rehydrate when relay live continuity is broken and
make full detail history explicit.

Changes:

- Add optional `itemsView` to `ThreadTurnsListParams`.
- Pass `itemsView:.full` from `ThreadDetailStore.readAllTurns` on the
  user-visible Thread Detail path.
- Preserve `itemsView` through relay pass-through routes.
- Change relay upstream recovery so successful upstream recovery closes the
  downstream phone socket; Swift then uses its existing reconnect/rehydrate
  path.
- Test reconnect/foreground/recovery paths against history changes that occur
  while the prior live session is invalid.

Acceptance:

- Thread Detail requests full turn items for user-visible history.
- The relay never silently swaps a recovered upstream under an unchanged phone
  detail socket.
- Swift marks detail stale/reconnecting and rehydrates before trusting new live
  deltas after recovery.

Checks:

```bash
rtk swift test --filter AppServerClientTests
rtk swift test --filter ThreadDetailStoreTests
rtk npm run test:relay
```

## Phase 5 - Relay Freshness Fails Closed

Goal: make source, live lease, validation, and archive failures visible as
stale/partial/error instead of hidden by old usable rows.

Changes:

- Audit `reconcileDock`, `reconcileArchive`, live lease refresh, source-refresh,
  human-started filtering, and archive mutation paths.
- Convert missing source proof, failed live proof, failed validation, and
  archive publish failure into scoped stale/partial/error freshness.
- Keep old rows only as visibly stale retained rows; never as fresh rows.
- Add controlled simulator scenario coverage for source-refresh failure,
  live-lease expiry, archive-toggle, multi-host isolation, resync gap, and rapid
  mutations. `archive-toggle` is required in the controlled fixture and matrix;
  the existing fixture rejection/default mismatch must be fixed.

Acceptance:

- A proof run cannot call a host/view fresh when the relay failed to prove that
  source scope.
- Retained rows are labeled retained/stale/partial through the existing
  freshness contract.
- Scenario reports include the source of freshness failure.
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` includes
  `archive-toggle` and fails if any named matrix scenario is unsupported.

Checks:

```bash
rtk npm run test:relay
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
```

## Phase 6 - Proof Contracts, Gates, And Runbook Alignment

Goal: make live-update proof hard to misread and hard to drift.

Changes:

- Add proof report schemas under `contract/proof/` for relay sync audit,
  simulator UI proof, controlled fixture reports, controlled matrix reports,
  and `sim-ui-dump`.
- Add a narrow proof-contract checker and wire it into existing npm/Makefile
  checks.
- Update proof writers to emit schema-valid report metadata, freshness status,
  `pass`/`fail`/`blocked`/`not_run` classification, lag budget, route evidence,
  relay identity, endpoint classification, and artifact paths.
- Ensure skipped simulator UI proof is `blocked`, never `pass`. Makefile
  wrappers must write blocked JSON/Markdown for missing config, expired config,
  missing app, missing relay, sampler timeout, unknown screen, or raw endpoint.
- Fail proof validation when the endpoint is raw app-server `:4500`, relay
  identity is missing, or route evidence does not include relay-owned `dock/*`
  or `archive/*` routes for card views.
- Fail proof validation when scripted/debug UI paths such as
  `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`, preview rows, fake local stream
  fixtures, or simulator-only seeded shortcuts are used as live-update proof.
- Update README only after executable commands exist.

Acceptance:

- Existing proof reports validate against schemas.
- A missing config, missing app, missing relay, skipped sampler, or unknown
  screen cannot be reported as live-update success.
- Raw `:4500` endpoint evidence cannot satisfy simulator or phone proof.
- Scripted debug UI paths and preview/fake fixtures cannot satisfy simulator or
  phone proof.
- README names only commands that exist and says route health is not freshness.

Checks:

```bash
rtk make contract-check
rtk npm run test:relay
rtk make sim-ui-dump SIM='iPhone 17'
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
```

## Phase 7 - Final Simulator And Phone-Claim Evidence

Goal: prove the whole local simulator path works before claiming the issue is
fixed, and keep physical-phone claims separate.

Changes:

- Run the full controlled simulator matrix after phases 1-6.
- Use `rtk make sim-ui-dump SIM='iPhone 17'` on the actual screen under manual
  investigation when needed.
- Do not claim physical iPhone correctness unless the physical-device runbook
  proof also runs successfully.

Acceptance:

- Simulator proof reports converge source changes to rendered accessibility UI
  samples within the configured lag budget.
- Simulator proof reports compare visible Dock row order and opened-thread
  Thread Detail message order against relay truth where the scenario expects
  ordering proof.
- The current-screen dump supports machine-checkable expectations such as
  `EXPECTED_SCREEN=thread` and `EXPECTED_THREAD_ID=<id>`; if an expectation is
  supplied and not met, the dump exits nonzero and writes a failed artifact.
- Physical phone status is reported separately as passed, blocked, or not run.

Checks:

```bash
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
rtk make sim-ui-dump SIM='iPhone 17'
```
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (blocking by phase)

## 8.1 Unit tests (contracts)

Use targeted Swift and Node tests for contract, state-machine, DTO, heartbeat,
snapshot generation, Thread Detail pagination, archive convergence, and proof
schema behavior. The checks listed in each phase are required phase-exit gates,
not advisory examples.

## 8.2 Integration tests (flows)

Use relay integration and sync-audit scenarios for real route flows:
`dock/subscribe`, `dock/update`, `dock/resync`, `archive/*`, source-refresh,
live-lease expiry, archive-toggle, detail-reconnect, server-request, and
resync-gap.

## 8.3 E2E / device tests (realistic)

Use simulator displayed-UI proof and controlled matrix proof for update-path
changes. The proof must include visible order checks for Dock rows and Thread
Detail messages in scenarios where ordering is part of the expected behavior.
Use physical phone proof only when making physical phone behavior claims.
Manual simulator inspection may use `rtk make sim-ui-dump SIM='iPhone 17'`, but
that current-screen dump does not replace over-time acceptance proof.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

This is a local app/relay change with no remote migration. Implement behind the
existing development flow, restart relays only when relay code changes, and
invalidate relay SQLite caches only when the implementation changes cache
semantics or schema.

## 9.2 Telemetry changes

Use existing `DockLog` and relay structured logger surfaces. Log heartbeat,
generation rejection, resync, stale freshness, source-refresh failure, archive
convergence, current-screen dump artifact path, and proof report paths without
logging secrets, prompt text, transcript text, raw JSON-RPC payloads, or audio.

## 9.3 Operational runbook

README and Makefile remain the runnable source of truth. The plan must leave
operators with exact commands for fast checks, simulator proof, current UI dump,
relay status/logs, and physical-phone proof.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass - 2026-06-01

- Decision-complete: yes
- Unresolved decisions: none
- Decision: proceed to implement? yes

Integrated consistency findings:

- The canonical current-simulator UI dump is now Phase 1 so it can be used
  during the rest of implementation. It is explicitly accessibility-based,
  non-mutating, non-relaunching, and machine-checkable through
  `launchMode`, `didRelaunch`, `screenBefore`, `screenAfter`, and optional
  expectation fields.
- Archive side doors are closed at the pattern level: active Archive, Archive
  Cleanup, `ThreadCardTable`, `ClientRuntime`, and root store wiring are all in
  scope. Production `ThreadCardHostSnapshotLoader` is deleted after migration;
  any fake fixture must live in tests only and cannot connect to real services
  or count as simulator/phone proof.
- Controlled proof side doors are closed: `archive-toggle` must be implemented
  in the controlled simulator fixture and included in the matrix, and unsupported
  named scenarios fail instead of silently disappearing.
- Proof skip behavior is fail-closed: reports use
  `pass`/`fail`/`blocked`/`not_run`, skipped UI proof is `blocked`, and raw
  app-server `:4500` endpoint evidence cannot satisfy simulator or phone proof.
- Verification is blocking by phase. The listed commands are phase-exit gates,
  not suggestions.

Implementation remains blocked by `implementation_allowed:false` until the
fresh Composer 2.5 Fast consult and `plan-audit` pass requested by the user are
complete.
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-06-01 - Intent-derived: use existing reference as active plan source

Blocker: The source file was an architecture reference, not a canonical
`arch-step` plan, and `arch-step reformat` usually leaves status `draft`.

Consulted: User objective, TL;DR, and source architecture reference.

Intent says: The user explicitly asked to turn this exact document into a real
implementation-ready plan through the `auto-plan` path and not implement yet.

Decision: Convert this file in place and set `status: active`; treat the user's
current objective as approval to proceed through planning stages.

Consequences: No sidecar planning doc is created. Implementation remains
forbidden until the plan receipts, fresh consult, and plan audit are complete.

## 2026-06-01 - Intent-derived: implementation gate opened

Blocker: Frontmatter still said `implementation_allowed:false` after the
planning receipts, Composer consults, and plan-audit passed.

Consulted: User's `$arch-step auto-implement` request, TL;DR implementation
gate, auto-plan receipts, Composer consult summaries, and plan-audit verdict.

Intent says: The implementation gate exists to prevent coding before the
required reviews, not to block the user after those reviews have passed.

Decision: Set `implementation_allowed:true` and start the implementation
worklog.

Consequences: Code changes may proceed under this plan. The plan remains
authoritative; requirements, scope, acceptance criteria, and proof gates are
not weakened.

# Appendix A) Imported Source Reference (exact source retained)

The original source reference starts below. It is retained in this canonical
plan file so source architecture notes remain recoverable while Sections 0-10
become the implementation-ready execution contract.

If Appendix A conflicts with Sections 0-10, Sections 0-10 win. In particular,
the canonical dump path is XCTest accessibility capture with activate-only
semantics, and the canonical proof statuses are `pass`, `fail`, `blocked`, and
`not_run`.

# Codex Dock Live Update Architecture And Testing Reference - 2026-06-01

Status: model-consensus target architecture and ongoing proof methodology. Do
not treat this as an implementation log.

Consensus artifacts:

- `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/round-01/model-a-final.md`
- `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/round-01/model-b-final.md`
- `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/round-02/model-a-final.md`
- `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/round-02/model-b-final.md`

Primary input:

- `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`

## Bottom Line

The architecture is simple: Codex Dock must have one production truth path for
live state, and every important claim about freshness must be proven over time.

The client must not be asked to guess whether a connected socket means current
data. The relay must own app-server decoding, card truth, freshness,
completeness, order, and stream liveness. The client renders that truth and
requests rebuilds when the relay's stream identity changes or falls behind.

The testing strategy is also simple: static snapshots are useful, but they are
not proof that the app works. The proof of record is live convergence:

```text
real or controlled app-server state changes
  -> relay projection and subscriptions
  -> Swift stream/session clients
  -> rendered iPhone UI samples over time
  -> retained machine-readable reports with lag budgets
```

The repo already has much of the live-proof harness. The missing architecture is
that this proof is opt-in, unscheduled, ungated, and partly underspecified. That
is why stale-update bugs can ship while tests pass.

## Canonical Principles

### P1. One Owner Per Fact

Every client-visible fact has exactly one production owner.

| Fact | Canonical owner | Forbidden second owner |
| --- | --- | --- |
| Dock and Archive card existence | Relay `dock/*` and `archive/*` streams | Swift local metadata, diagnostics, preview fixtures, raw app-server routes |
| Card order and recency | Relay `orderKey` / `activityAtMs` | Swift timestamp inference, pins, row text, latest rendered message |
| Card freshness and completeness | Relay freshness/completeness fields | Socket connectivity, HTTP diagnostics, host test success |
| Human-only filtering | Relay human-started filter, with Swift defensive filter | Client-side list reconstruction from broad raw thread routes |
| Thread Detail history | `thread/read includeTurns:false` plus fully paged `thread/turns/list` | Dock cards, raw card summaries, partial resume payloads |
| Thread Detail liveness | Focused `thread/resume` session | Socket state alone |
| Local labels, rails, pins | Swift local metadata | Relay/card truth fields |

Local metadata may decorate visible rows. It must never create a row, change
card order, mark data fresh, change status, change summary, or resurrect a row
that the relay no longer emits.

### P2. Liveness Must Be Re-Proven

A connected WebSocket is not proof that the data is current.

Every stateful relay-owned stream or session must have an identity:

- Dock and Archive streams: `epoch`, `seq`, and `stateGeneration`.
- Thread Detail live session: relay downstream session generation plus the
  active upstream `thread/resume` binding.
- Realtime transcription: transcription `sessionId` plus sequence acceptance.

When that identity changes, the missing state must be rebuilt in an observable
way:

- Dock and Archive must resubscribe or resync.
- Thread Detail must rehydrate from history before trusting live deltas again.
- The UI must show stale/partial/reconnecting when freshness is not proven.

No production path may silently recover a relay upstream session while leaving
the phone thinking its old stream is still complete.

### P3. Proof Is Over-Time Convergence

Proof means the rendered client stays converged with actual source state over a
duration and within a lag budget.

The following are not enough:

- a static fixture that renders once;
- a fake Swift stream that manually yields a good payload;
- a one-shot `dock/subscribe`;
- `/readyz`, `/statusz`, `/routesz`, `/metricsz`, or `/syncz`;
- a green `rtk make app-test SIM='iPhone 17'` when the displayed sync proof
  skipped because its config file was absent.

Those checks can be useful, but they are lower-tier evidence. They do not prove
the live system is current.

## Target Architecture

### Rule 1. Phone Uses Relay Only

The phone connects to the Dock relay on `:4510`, not to the raw authenticated
app-server on `:4500`.

Allowed normal phone paths:

- relay WebSocket for `initialize`, `dock/*`, `archive/*`, Thread Detail,
  composer commands, server requests, and transcription;
- relay-provided host config such as `amir-m5.fairy-salmon.ts.net:4510`,
  `home.fairy-salmon.ts.net:4510`, LAN hostname, or LAN IP.

Forbidden normal phone paths:

- raw app-server `:4500`;
- raw app-server bearer tokens on device;
- phone-side `thread/list`, `thread/loaded/list`, `thread/search`, or broad
  state routes used to rebuild cards;
- relay SQLite/debug/state routes as card truth.

### Rule 2. Relay Owns Card Truth

The relay is the only production card-truth owner for Dock and Archive.

The relay owns:

- app-server history reads;
- live loaded-session scans;
- human-started filtering;
- latest-activity proof;
- card normalization;
- SQLite materialization;
- stream sequence and snapshot generation;
- freshness and completeness;
- `dock/update` and `archive/update` deltas.

Swift owns:

- rendering;
- grouping/filtering/searching of relay rows;
- local decorative metadata;
- resync/resubscribe behavior when the relay stream contract says state is
  incomplete, stale, mismatched, or behind.

Swift must not reconstruct card truth from Thread Detail history or local
metadata.

### Rule 3. Relay Owns Recency

Dock and Archive order are relay-owned. The client renders relay order.

The client must not infer row recency from:

- latest visible message;
- first message;
- pinned status;
- local label;
- local rail;
- Thread Detail events;
- raw timestamps from a side route.

This prevents the same user-facing bug from reappearing under a new local
projection.

### Rule 4. Thread Detail Uses One History Path

Thread Detail history is:

```text
thread/read includeTurns:false
  -> thread/turns/list until nextCursor is empty
  -> thread/resume excludeTurns:true
```

For user-visible detail completeness, `thread/turns/list` must request
`itemsView:"full"` on the detail path.

Important scoping rule:

- Thread Detail history requests should use `itemsView:"full"`.
- Relay card-order activity proof calls should not use `itemsView:"full"`.

The card-order proof needs turn activity timestamps and ordering proof. It does
not need full item bodies. Forcing full item bodies into relay card proof would
mix two separate concerns and increase payload cost.

Current gap to close during implementation: `ThreadTurnsListParams` does not
currently carry `itemsView`, and relay `listThreadTurns` forwards params as-is.
The sync audit has a `--turn-items-view` flag, but the production detail path
does not currently send the field.

### Rule 5. Stateful Recovery Must Be Observable

Stateful paths cannot silently reconnect and keep old state.

Dock and Archive:

- reconnecting the transport is not enough;
- `initialize` replay is not enough;
- the subscription must be restored;
- if subscription continuity is not provable, the stream must resubscribe or
  fail into a visible rebuild path.

Thread Detail:

- if the downstream phone socket closes, Swift already rehydrates;
- if the relay loses and recreates the upstream `thread/resume` session, the
  phone must also observe a rebuild trigger.

Consensus decision: close the downstream Thread Detail socket on relay upstream
recovery unless the app-server provides a proven replay guarantee.

Why close the downstream socket now:

- Swift already has a tested reconnect/rehydrate path.
- It avoids adding a new protocol message before the architecture is stable.
- It prevents the exact stale-detail failure shape: relay recovered upstream,
  phone stayed connected, and missed history was never replayed.

Sanctioned future alternative:

- a `detail/resync` or equivalent notification may exist later only if it is
  `threadId`-stamped, generation-stamped, added to the relay allow-list, added
  to Swift DTO handling, added to proof tests, and documented here in the same
  change.

Until then, invisible upstream recovery is forbidden.

### Rule 6. Heartbeat Is Real Contract

Heartbeat is not decorative. It is the stream liveness signal.

The repo already claims heartbeat in schema, Swift behavior, tests, and README.
The target architecture makes it real instead of leaving a dead contract.

Relay must emit periodic `kind:"heartbeat"` `dock/update` messages with:

- `schemaVersion`;
- `view`;
- `epoch`;
- `seq`;
- `stateGeneration`;
- `freshness`;
- `lastSyncAt` or equivalent freshness timestamp;
- no row changes.

The client uses heartbeat to detect:

- connected-but-unsubscribed streams;
- streams whose relay state is stale even though the socket is open;
- missing updates beyond a bounded timeout.

Heartbeat must never mark failed data fresh. It may keep the transport alive,
but freshness remains a relay data claim.

Bounded implementation parameter:

- heartbeat cadence should align with relay reconcile timing, roughly the
  reconcile interval or a small multiple;
- client stale timeout should be a small multiple of heartbeat cadence;
- exact values belong in constants, not scattered call sites.

Heartbeat is the canonical liveness contract. Any future non-heartbeat
replacement requires a newer canonical architecture reference and equivalent
proof gates.

### Rule 7. Freshness Fails Closed

If the relay cannot prove a source is current, client-visible freshness must be
stale or partial, not fresh.

This applies to:

- raw app-server history failures;
- live endpoint failures;
- live lease scan failures;
- validation failures during human-started filtering;
- repeated turn cursors;
- schema or sequence mismatch;
- incomplete windows;
- failed archive reconciliation.

Current gap to close during implementation: live endpoint failures can be
counted and then effectively hidden by history completeness. The target rule is
that live-scope probe failure marks the relevant scope stale/incomplete and the
client renders that state.

### Rule 8. Snapshots Cannot Move State Backward

Snapshots are full replacements, but they are not allowed to overwrite newer
state with older state.

The relay already has monotonic stream sequence material:

- `seq`;
- `stateGeneration`;
- `epoch`;
- `schemaVersion`.

Swift must reject stale compatible snapshots when their generation is older
than the current host/view state. A compatible schema is not enough.

Current gap to close during implementation: Swift currently applies compatible
snapshots without a stale-generation guard.

### Rule 9. Archive Is A First-Class View

Archive and Dock are separate views with related but distinct freshness.

Archive/unarchive mutations must reconcile and publish both affected views:

- Dock view;
- Archive view.

Archive freshness must not be accidentally coupled to Dock freshness such that
one scope can stale or freshen the other without proof.

Current gap to close during implementation: archive mutation scheduling is
drift-prone because the mutation ingestion path schedules generic reconciliation
but does not make Archive convergence a first-class invariant.

## Owner Map

| Surface | Canonical owner |
| --- | --- |
| Relay route dispatch | `scripts/dock-relay.mjs` |
| Swift route names | `CodexDock/AppServer/AppServerMethods.swift` |
| Dock card wire schema | `contract/dock/dock-thread-card.schema.json` |
| Generated Swift card DTO | `CodexDock/AppServer/DockThreadCardDTO.swift` |
| Card contract generation/check | `scripts/generate-dock-thread-card-contract.mjs`, `scripts/check-dock-thread-card-contract.mjs` |
| Relay card projection | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-state-subscriptions.mjs`, `scripts/dock-relay-thread-data.mjs` |
| Swift Dock stream client | `CodexDock/State/AppServerThreadCardStreamClient.swift` |
| Swift Dock state | `CodexDock/State/DockStore.swift`, `CodexDock/State/ThreadCardTable.swift`, `CodexDock/Dock/DockScreenStore.swift` |
| Thread Detail session | `CodexDock/State/AppServerThreadDetailSession.swift` |
| Thread Detail state | `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` |
| Connectivity display | `CodexDock/Connectivity/**`, `CodexDock/Features/Dock/**` |
| Real relay client-path proof | `scripts/dock-relay-sync-audit.mjs` |
| Simulator displayed UI proof | `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, `scripts/dock-relay-simulator-ui-sync-proof.mjs` |
| Simulator current UI dump | required new `rtk make sim-ui-dump SIM='iPhone 17'` entrypoint, backed by repo-owned XCTest accessibility capture or an equivalent repo-owned simulator accessibility dumper |
| Controlled simulator fixture | `scripts/dock-relay-controlled-simulator-fixture.mjs` |
| Controlled matrix report | `scripts/dock-relay-controlled-simulator-matrix.mjs` |
| Makefile proof entrypoints | `Makefile` |
| Product/runbook docs | `README.md`, docs listed in this file |

New architecture should extend these owners. It should not create a parallel
route map, parallel schema, parallel fixture framework, or parallel proof
report language unless the existing owner demonstrably cannot absorb it.

## Forbidden Side Doors

These are not allowed to count as production card truth or live freshness proof:

- phone calls to raw `:4500`;
- phone-side raw bearer tokens;
- phone-side `thread/list`, `thread/loaded/list`, `thread/search`, or broad
  state routes;
- relay debug/state/diagnostic routes as list truth;
- `/readyz`, `/statusz`, `/routesz`, `/metricsz`, `/syncz` as stream freshness;
- one-shot host connection tests as Dock Home stream health;
- `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO` as live proof;
- Swift preview rows as evidence;
- local metadata as card existence/order/status/freshness truth;
- static JSON fixtures as over-time update proof;
- tests that preserve a retired route "for coverage";
- docs that recommend deleted scripts or unsupported flags;
- proof commands that skip and still let the run be interpreted as freshness
  proof.

Important: a skipped over-time proof is itself a side door. It lets a green
test run masquerade as a live freshness pass.

## Edge And Exception Matrix

| Scenario | Required behavior | Proof surface |
| --- | --- | --- |
| Dock WebSocket reconnects | `dock/subscribe` is restored or stream fails into visible rebuild | Swift stream test plus real relay soak |
| `dock/update` params missing | Treat as stream corruption; resync/fail, not silent ignore | Swift unit plus relay malformed update test |
| Sequence gap | Request `dock/resync` and converge | Swift stream test plus relay integration |
| Epoch mismatch | Request resync and do not apply stale delta | Swift stream test |
| Schema mismatch | Request resync/fail loudly | Swift stream test plus contract test |
| Older compatible snapshot | Reject if generation is older than current state | Swift unit plus relay delayed snapshot scenario |
| Heartbeat arrives | Update liveness/freshness without row mutation | Swift unit plus relay integration |
| Heartbeat stops | Mark stream stale/reconnect within timeout | controlled simulator scenario |
| Raw app-server history down | Relay marks scope stale/partial; UI does not claim fresh | relay integration plus UI proof |
| Live endpoint down | Live scope fails closed; UI shows stale/partial | controlled `source-refresh` / live failure scenario |
| Cold relay SQLite | UI can show empty/partial only with explicit freshness state | relay integration |
| Stale SQLite | Reconcile or show stale; do not present old cache as fresh | soak comparing long-lived stream vs fresh snapshot |
| Partial window | UI marks partial and catch-up completes or restarts | Swift unit plus controlled large-list scenario |
| Large delta fallback | Snapshot fallback preserves monotonic generation | relay integration plus Swift table test |
| Duplicate card IDs | Reject safely; do not crash through `Dictionary(uniqueKeysWithValues:)` | Swift unit |
| Non-human upsert for human card | Delete/resync or reject; do not leave stale human card | relay contract plus Swift table test |
| Archive mutation | Dock and Archive both reconcile and publish relevant updates | relay integration plus UI archive scenario |
| Archive failure | UI surfaces action failure and does not fabricate row state | Swift store test plus relay scenario |
| Host alias/identity change | Resolve configured/stream/logical host identity without duplicating rows | Swift host identity tests |
| Relay host ID changes cache scope | Prune or invalidate old host rows explicitly | relay state-store test |
| Thread Detail initial load | `thread/read`, full paged `thread/turns/list`, then `thread/resume` | ThreadDetailStore tests plus sync audit detail probe |
| Thread Detail repeated cursor | Fail loudly; do not spin or silently truncate | ThreadDetailStore test |
| Thread Detail upstream recovery | Close downstream or send sanctioned resync; Swift rehydrates | relay integration plus UI detail scenario |
| Missing `threadId` in detail notification | Drop or classify explicitly; request-card resolution must not vanish silently | ThreadDetailStore test |
| Multiple active turns | Preserve all visible activity or define single-active-turn UI explicitly | Thread detail event test |
| Server request stale generation | Reject response from stale generation | relay integration |
| `serverRequest/resolved` | Clear matching request card; define missing-thread behavior | ThreadDetailStore test plus controlled fixture |
| Background/foreground | Rehydrate or resync; do not trust stale in-memory state | Swift lifecycle test plus simulator proof |
| Realtime transcription disconnect | Transcription state closes without mutating Dock/Detail truth | voice tests |
| Config rewrite while app runs | Existing streams close/reload or UI exposes old config explicitly | host registry/store test |
| Docs command drift | Doc command gate fails on unsupported flags/deleted scripts | doc-command gate |

## Testing Methodology

The proof system has six tiers. Lower tiers are necessary, but they cannot
replace higher tiers.

### Tier A. Contract And Drift Gates

Purpose: keep protocol surfaces aligned before runtime.

Required gates:

- current card contract checks;
- route registry/dispatch parity;
- Swift `AppServerMethods` parity with allowed relay routes;
- schema version parity across JSON schema, relay emission, and Swift constants;
- generated DTO staleness check;
- proof-result schema validation;
- executable doc-command gate.

Candidate commands:

```bash
rtk npm run contract:check
rtk npm run test:relay
```

New target direction: add one CI-safe aggregate target that runs all fast drift
gates without simulator or physical device dependency.

### Tier B. Swift State Tests

Purpose: prove Swift state machines handle known events correctly.

These tests can use fake streams, but they must be labeled as merge/state proof,
not live proof.

Coverage required:

- snapshot, delta, heartbeat;
- schema/epoch/sequence mismatch;
- resync behavior;
- stale snapshot rejection;
- duplicate card IDs;
- partial window catch-up;
- missing update params;
- Thread Detail pagination;
- Thread Detail rehydrate on reconnect and foreground;
- server request and resolution behavior;
- archive action state transitions.

Representative commands:

```bash
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter AppServerClientTests
```

Interpretation rule: passing Tier B means Swift can handle supplied events. It
does not prove real relay delivery over time.

### Tier C. Relay Integration Tests

Purpose: prove real relay behavior with fake or controlled upstreams.

Coverage required:

- `dock/subscribe` returns canonical snapshot;
- server state mutation emits `dock/update`;
- multi-subscriber updates;
- delete-only delta;
- `dock/resync`;
- Archive mutation emits Dock and Archive convergence;
- live failure fails closed;
- heartbeat is emitted;
- stale snapshot/generation behavior;
- route allow-list rejects unsupported paths.

Representative command:

```bash
rtk npm run test:relay
```

Interpretation rule: passing Tier C proves relay protocol behavior below the UI.
It does not prove the Swift app rendered the update.

### Tier D. Real Relay Client-Path Soak

Purpose: prove long-lived relay streams stay converged with fresh snapshots over
time.

Required properties:

- long-lived `dock/subscribe`;
- periodic fresh `dock/subscribe`;
- comparison of long-lived stream state against fresh snapshot;
- forced `dock/resync`;
- detail probe that runs `thread/read`, full paged `thread/turns/list`, and
  `thread/resume`;
- lag budget;
- retained JSON and Markdown reports.

Representative command family:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode soak --client-path-only --force-dock-resync --max-stream-lag-ms 2000
```

This is a command family, not the exact exhaustive invocation. The runbook owns
the full duration, sample interval, detail, and host parameters, and the
doc-command gate must keep that runbook executable.

Current doc drift to fix during implementation: older docs mention unsupported
or deleted command surfaces such as `--exhaustive` and deleted parity scripts.
The doc-command gate must make that impossible to miss.

### Tier E. Simulator Displayed-UI Proof

Purpose: prove the iPhone simulator actually displays the live state over time.

Required properties:

- app launched without `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`;
- real relay-backed or controlled relay-backed rows;
- structured simulator accessibility/UI-state samples over a duration, not
  screenshots or screen recordings;
- route evidence from relay side;
- row-level and detail-level UI samples that include identifiers, labels,
  values, frames, root values, host summaries, message-card state, request-card
  state, and scroll sweeps where needed;
- transition coverage;
- lag budget;
- retained machine-readable report.

Current owner: `CodexDockDisplayedSyncProofTests` calls
`captureDisplayedUISample(...)` and writes `ui-samples.jsonl` through
`DisplayedUISampleWriter`. `scripts/dock-relay-simulator-ui-sync-proof.mjs`
must consume that file with `--ui-samples` and judge the literal simulator
accessibility state. Screenshots and recordings are allowed only as optional
debug artifacts; they do not count as displayed-state proof.

Canonical current-screen dump requirement: the repo must provide one simple
operator command:

```bash
rtk make sim-ui-dump SIM='iPhone 17'
```

That command must dump the currently visible Codex Dock simulator screen without
requiring a screen recording, screenshot review, proof run, relay scenario, or
manual copy/paste. It must attach to the currently running app when possible and
must not silently relaunch into a different state unless the caller passes an
explicit relaunch option. The output must be machine-readable JSON plus a short
human-readable summary under `/tmp/codex-client/...`, with an override such as
`SIM_UI_DUMP_OUTPUT=...`.

Required dump fields:

- simulator name and UDID;
- active app bundle identifier and app state;
- current high-level screen classification, at minimum `dock`, `thread`, or
  `unknown`;
- all visible accessibility elements with type, identifier, label, value, and
  frame;
- Dock-specific rollup when on Dock: root value, visible row identifiers, row
  labels, row values, host summaries, selected lens/filter state where visible;
- Thread-specific rollup when on Thread Detail: root/header/message-list values,
  thread ID when visible, host/live header values, filter/composer state,
  visible message-card IDs, request-card IDs, and visible message text values;
- raw accessibility tree fallback when structured Dock/Thread rollup cannot be
  classified.

This command is operator evidence, not full acceptance proof: it answers “what
is the simulator showing right now?” The long-running displayed-UI proof still
owns lag budgets, transitions over time, route evidence, and pass/fail
classification. Mobile MCP `mobile_list_elements_on_screen` is a useful
temporary/manual equivalent, but the plan requires a repo-owned command so this
debug path does not depend on the current agent environment.

Representative commands:

```bash
rtk make sim-ui-dump SIM='iPhone 17'
rtk make sim-ui-sync-proof SIM='iPhone 17'
rtk make sim-ui-scenario-sync-proof SIM='iPhone 17'
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17'
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_PASSES=2 MAX_UI_LAG_MS=2000
```

Interpretation rule: `CodexDockDisplayedSyncProofTests` skipping because
`/tmp/codex-client/codex-dock-sim-ui-sync-config.json` is absent is not proof.
For update-path changes, this tier must run or be explicitly reported as
blocked by missing simulator/Xcode infrastructure.

### Tier F. Physical Phone Proof

Purpose: prove the real phone path, including network profile and saved host
configuration.

Representative commands:

```bash
rtk make iphone-17-pro
rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E
rtk make device-logs DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E
```

Interpretation rule: simulator proof is not physical phone proof. Physical
completion requires a real installed app connected through the intended relay
host path.

The UUID above is an example from the current repo runbook. The runbook remains
the owner of the current physical device inventory.

## Ongoing Cadence

The methodology must run continuously enough to catch drift before manual use.

Recommended cadence:

| Trigger | Required proof |
| --- | --- |
| Every source change in update-path files | Tier A plus affected Tier B/C |
| Relay protocol, card DTO, stream, Thread Detail, or proof harness change | Tier A/B/C plus Tier E controlled matrix |
| Daily/nightly on a capable Mac | Tier D soak plus Tier E controlled matrix |
| Before claiming simulator behavior fixed | Tier E on `iPhone 17` |
| Before claiming phone behavior fixed | Tier F |
| Before changing docs/runbooks | Doc-command gate plus affected referenced commands in dry-run or real mode |

Update-path files include:

- `scripts/dock-relay*.mjs`;
- `contract/dock/**`;
- `CodexDock/AppServer/**`;
- `CodexDock/State/**`;
- `CodexDock/ThreadDetail/**`;
- `CodexDock/Features/Dock/**`;
- `CodexDockUITests/**`;
- `Makefile`;
- live-update docs and runbooks.

## Proof Acceptance Rules

Every proof report should classify the run as one of:

- `pass`: required routes, transitions, UI samples, freshness states, and lag
  budgets passed.
- `fail`: the proof ran and found divergence, stale UI, missing route evidence,
  missing transition, forbidden proof evidence, or lag over budget.
- `blocked`: infrastructure was unavailable, such as no simulator, no relay,
  no app-server, missing signing, or physical device unavailable.
- `not_run`: the proof was intentionally not run and cannot count as evidence.

Forbidden proof routes such as scripted fixtures, debug env vars, preview rows,
raw app-server paths, or another non-relay path must be represented as `fail`
with reason code `outside_contract`, not as a separate proof status.

No proof may be counted as pass if:

- it skipped;
- it had no route evidence;
- it lacked structured simulator accessibility/UI-state samples for the
  displayed screen when claiming simulator UI behavior;
- it only compared static snapshots;
- it lacked a retained report;
- it did not validate its report schema;
- it ignored stale/partial freshness;
- it did not sample over time.
- it checked row/message membership but not visible order for an ordering
  scenario.

Required retained report fields:

- `schemaVersion`;
- `kind`;
- `startedAt`;
- `endedAt`;
- `durationMs`;
- source host(s);
- app/server/relay build identifiers where available;
- scenario name(s);
- route counts;
- sampled transitions;
- UI sample count;
- UI sample artifact path, normally `ui-samples.jsonl`;
- displayed Dock root values, visible row identifiers, row labels, row values,
  row frames, host summaries, detail root/header/message-list values,
  message-card identifiers, request-card identifiers, and sweep metadata where
  collected;
- max observed lag;
- lag budget;
- freshness states;
- pass/fail findings;
- artifact paths.

Retained reports must be trendable across runs. At minimum, scheduled proof
history should preserve `maxObservedUiLagMs`, failure counts, scenario names,
and freshness outcomes so slow drift is visible before a manual test finds it.

## Drift Gates

### Gate 1. Route Registry And Dispatch Parity

The relay dispatch switch, relay route registry/observability config, Swift
route names, and docs must agree.

A route must not be silently valid because a helper auto-created an unregistered
route. New routes are allowed only when they update:

- relay dispatch;
- route registry/observability;
- Swift method constants/DTOs if phone-visible;
- tests;
- docs.

### Gate 2. Schema Version And DTO Parity

These values must move together:

- JSON schema `schemaVersion`;
- relay emitted `schemaVersion`;
- Swift `CodexDockConstants.Dock.streamSchemaVersion`;
- generated Swift DTOs;
- tests and fixtures.

Generated DTO staleness is a build failure, not a review note.

### Gate 3. Executable Doc Commands

Docs that name runnable commands must not drift from real CLIs.

This gate should catch:

- unsupported flags such as stale `--exhaustive`;
- deleted scripts such as stale parity helpers;
- Makefile target renames;
- commands that require env/config but do not say so;
- commands that skip by default while being described as proof.

### Gate 4. Proof Result Schemas

Proof reports need schemas just like card DTOs.

Create and enforce schemas for:

- relay sync audit reports;
- simulator UI sync proof reports;
- controlled simulator fixture reports;
- controlled simulator matrix reports.

The current reports have `schemaVersion` and `kind`, but no schema file guards
their shape. That means proof consumers and docs can drift.

### Gate 5. Heartbeat Contract

If schema, README, Swift tests, or docs say heartbeat exists, relay must emit it.

The gate must fail if:

- heartbeat is documented but not emitted;
- heartbeat is emitted but schema/DTO/tests do not allow it;
- heartbeat marks stale data fresh;
- client does not timeout missing heartbeat.

## UX Freshness Contract

The UI should make these states visible and distinct:

| State | Meaning |
| --- | --- |
| Fresh | Relay has current proof for this view/scope. |
| Partial | Relay has usable rows but incomplete proof/window/source coverage. |
| Stale | Relay has old rows but cannot prove current source state. |
| Reconnecting | Stateful stream/session identity is being rebuilt. |
| Offline | No usable relay path is currently available. |
| Blocked | Command/test/proof could not run because infrastructure is missing. |

Global connectivity may summarize transport reachability, but it must not hide
stale stream freshness. A small "online" badge is misleading if the rows are a
day old.

## Rejected Alternatives

### Static Fixtures As Proof Of Record

Rejected because they prove only merge/render behavior for supplied data. They
do not prove that current Codex work reaches the phone.

### Client-Inferred Recency

Rejected because it creates a second card-truth path and reintroduces ordering
bugs.

### Diagnostics As Freshness

Rejected because route health can be green while the long-lived stream is
unsubscribed or stale.

### New Parallel Test Framework

Rejected because the repo already contains the core live-proof harness. The
right move is to make it mandatory, scheduled, schema-validated, retained, and
drift-gated.

### Invisible Thread Detail Upstream Recovery

Rejected because it is the exact stale-detail failure mode.

### Delete Heartbeat Or Replace It In This Architecture

Rejected. Heartbeat is the canonical liveness contract for this architecture.
A future non-heartbeat replacement requires a newer canonical architecture
reference and equivalent proof gates.

### Add `detail/resync` Immediately

Rejected for now because downstream close reuses existing Swift rehydrate
behavior. `detail/resync` is the sanctioned future evolution only if full
evidence shows downstream close is too expensive.

## Implementation Plan Outline

This document does not implement these changes. A future implementation plan
should be phased like this:

1. Update docs/runbooks so command references are executable and this document
   is the canonical live-update architecture reference.
2. Add drift gates that are CI-safe and do not require simulator/device.
3. Make heartbeat real as the canonical liveness contract.
4. Fix stateful recovery: Dock/Archive resubscribe after reconnect and Thread
   Detail upstream recovery closes downstream or triggers sanctioned rehydrate.
5. Add snapshot generation rejection in Swift.
6. Make live failures fail closed in relay freshness.
7. Make Archive reconciliation first-class after archive/unarchive.
8. Add `itemsView:"full"` to Thread Detail history and proof paths, scoped only
   to detail.
9. Add proof-result schemas and validate retained reports.
10. Make update-path changes require the controlled simulator matrix and retain
    reports.
11. Add scheduled soak/matrix runs where infrastructure exists.
12. Add physical phone proof as the completion gate for phone claims.

Each phase must remove or converge old paths. Do not leave a retired side door
alive for tests.

## Canonical Documentation Relationship

This document is the canonical target architecture and ongoing methodology for
live updates.

Relationship to other docs:

- `CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md` remains
  the deep protocol and bug appendix.
- `CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md` remains
  historical evidence for data-contract drift.
- Existing exhaustive sync runbooks/test plans should be updated to remove
  stale commands and align with this methodology.
- README should align with heartbeat reality after implementation.

If another doc disagrees with this target architecture, this doc wins for
live-update architecture intent until a newer explicitly canonical reference
replaces it.

## Final Consensus Statement

Opus 4.8 max and GPT-5.5 xhigh converged on the same architecture:

- one canonical production truth path;
- relay-owned card truth and freshness;
- observable rebuild on stateful identity changes;
- heartbeat as real liveness contract;
- detail history with `itemsView:"full"` only on the detail path;
- live failures fail closed;
- snapshots cannot move state backward;
- Archive is a first-class stream view;
- live proof over time is mandatory, retained, scheduled, schema-validated, and
  gated for update-path changes.

The remaining open value, heartbeat cadence/timeout, is an implementation
parameter. It does not change the architecture.
