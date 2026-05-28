---
title: "Codex Dock - Agents Tab And Live Counts - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md
  - docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md
  - docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md
  - docs/EPIC_CODEX_DOCK_MVP_2026-05-27.md
  - docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
  - docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md
---

# TL;DR

- Outcome: Codex Dock separates human-started interactive sessions from structured machine-origin Codex sessions, keeps sub-agents and non-interactive automation rows out of the main human tabs, and shows live counts in every Dock tab/filter label.
- Problem: The app-server already exposes session-origin metadata, but the Dock drops it while mapping rows, the relay can merge live sub-agent/non-interactive rows into normal results, and filter counts are not owned by shared state.
- Approach: Preserve source/origin metadata in the app-facing model, classify rows once, project counted Dock tabs from the same predicates used by the UI, and teach the relay to honor `sourceKinds` for live rows.
- Plan: First prove source classification and no-leak behavior in the data pipeline, then wire counted Dock tabs, then verify relay and UI behavior against fixture and live-shaped rows. In the top-level dock, this plan runs after the implemented no-phone-secret iPhone relay baseline and before connectivity resilience, because connectivity should consume the final Dock query/snapshot/count model instead of the old UI-local filters.
- Non-negotiables: no JSON-mode guessing, no prompt-content heuristics, no duplicate filter predicates, no fixtures that mock away structured source metadata, and no runtime fallback that hides unknown origin.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:a873194c2cc19d39f9439cd095c43bdb89e9e4f0ee03b29a9966d687265eb6bb",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T10:47:45Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:fbf60c165d548fe62a1e0e8ef36f1e241679420aeee3e21b271a44abcfb45de7",
      "completed_at": "2026-05-28T10:48:15Z",
      "doc_hash_after": "sha256:51ea03b0db038e6939561dfa889fccce5daf1a0a5d81fe414b6d6a53efb9c3c3"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:49:57Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:51ea03b0db038e6939561dfa889fccce5daf1a0a5d81fe414b6d6a53efb9c3c3",
      "completed_at": "2026-05-28T10:53:30Z",
      "doc_hash_after": "sha256:6a1f0e9e98f32f3365f471c166529e4e05c3a355a38bc12d191583ce7a2c919b"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:53:38Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:6a1f0e9e98f32f3365f471c166529e4e05c3a355a38bc12d191583ce7a2c919b",
      "completed_at": "2026-05-28T10:55:07Z",
      "doc_hash_after": "sha256:01ab858dd6e448c0cebfd61f0396802be8cfd59dcf9e03629150d931bfa81be1"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T10:55:12Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:01ab858dd6e448c0cebfd61f0396802be8cfd59dcf9e03629150d931bfa81be1",
      "completed_at": "2026-05-28T10:56:36Z",
      "doc_hash_after": "sha256:6b342dcb1aa1ff4b1ddcd47d5657f014705fde5a576533ae033eb78fe9e97635"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T10:56:41Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:6b342dcb1aa1ff4b1ddcd47d5657f014705fde5a576533ae033eb78fe9e97635",
      "completed_at": "2026-05-28T11:02:08Z",
      "doc_hash_after": "sha256:94b5926281206019958d3e17e47ad2373f95afc858e8b664b6e6837549c3aa35"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

The Dock is correct when a row whose app-server metadata identifies it as a Codex-created sub-agent or other structured non-interactive Codex source appears only in the Dock's Agents scope, never in the main human scope, and every visible Dock tab/filter label displays a count derived from the currently loaded rows and refreshed on the same cadence as the Dock.

## 0.2 In scope

- Preserve response-side origin metadata from `ThreadDTO.source`, `threadSource`, `agentNickname`, and `agentRole` into the app-facing session model.
- Classify sessions into `humanInteractive`, `agentOrAutomation`, and `unknown` at one canonical mapping/projection boundary.
- Filter Codex-initiated sub-agents and other structured non-interactive Codex sources out of the main human Dock tabs.
- Add an `Agents` Dock tab for structured machine-origin rows, including Codex sub-agent variants plus explicit non-interactive root sources such as `exec` and app-server/MCP rows.
- Add live counts to the Dock tabs/filters: examples include `All 14`, `Needs me 5`, `Running 4`, `Limited 3`, and `Agents 2`.
- Keep counts updated by deriving them from `DockSnapshot` after each load, refresh, metadata save, archive, restore, or host-registry update.
- Update the relay so live loopback rows honor the same source-kind filtering as stored history, preventing live sub-agent leaks.
- Extend focused Swift and relay tests for mapping, classification, counts, and no-leak behavior.
- Preserve the implemented physical-iPhone security baseline while changing the Dock loader and relay list behavior:
  - `DockHostConfiguration.bearerToken` is optional;
  - a nil bearer is the normal discovered relay path;
  - relay `phoneAuth=none` is valid for the personal V1;
  - app code must not reintroduce a phone-side relay token, raw app-server token, or OpenAI key.

## 0.3 Out of scope

- Adding a new Codex app-server protocol field; the existing source fields are enough for this change.
- Inferring origin from prompt text, JSON output mode, command-line shape, cwd, model, or private message content.
- Changing the semantics of `Needs me`; it remains tied to real pending approval/input flags.
- Replacing the existing Archive and Hosts app tabs.
- Building a new background monitor, analytics pipeline, or custom session scanner.
- Adding upstream Codex protocol support for selecting memory/internal maintenance threads; current `ThreadSourceKind` cannot fetch those rows, so this plan does not promise them.
- Broad redesign of session detail, archive, host settings, voice, or request-card behavior.

## 0.4 Definition of done (acceptance evidence)

- Fixture mapping proves human rows, sub-agent rows, non-interactive `exec`/app-server rows, and unknown rows classify deterministically from structured metadata.
- Store/projection tests prove main human rows exclude agent-origin rows and Agents rows include them.
- Count tests prove Dock tab counts use the same predicates as UI filtering.
- Relay tests prove `sourceKinds` is applied to live loopback rows as well as stored history rows.
- A snapshot-level assertion proves tab labels are generated with counts without duplicating count logic in `DockView`.
- Existing `rtk swift test` and `rtk npm run test:relay` pass for the changed surfaces.

## 0.5 Key invariants (fix immediately if violated)

- Structured source metadata is the single source of truth for human-vs-agent/automation routing.
- Sub-agent rows must not leak into the main human Dock scope.
- Explicit non-interactive `exec` and app-server/MCP rows must not be guessed from flags or prompt text; they route from structured `source` only.
- Unknown origin must stay visible and auditable; it must not be silently treated as a trusted human row.
- The UI must not own a second copy of status/scope predicates.
- Counts must be derived from the same row set and predicates used for display.
- The relay must not undo client-side source separation by merging unfiltered live rows.
- Source filtering must behave the same whether the downstream phone connects with no Authorization header or an explicit bearer-auth dev/hardening profile.
- Loader/query changes must preserve optional bearer host configs; a missing phone bearer token is not an error for the physical relay path.
- Fallback policy is forbidden: if source metadata cannot be decoded, classify as `unknown` and show that truth rather than guessing.

## 0.6 Cross-plan position

This is Phase 1 in `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`.

Inputs from Phase 0:

- the physical iPhone app reaches the relay through Bonjour/bootstrap without phone secrets;
- `DockHostConfiguration.bearerToken` is optional;
- relay `phoneAuth=none` is a supported app-facing path;
- raw app-server/OpenAI secrets stay on the Mac/host.

Outputs consumed by later plans:

- `DockSessionQuery(archived:sourceKinds:)` becomes the loader contract that connectivity and multi-host code must use;
- `DockSnapshot` owns counted tab models and scoped failures;
- `DockTabID.includes(_:)` is the single predicate for counts and visible rows;
- relay live source filtering prevents connectivity/multi-host refreshes from seeing rows that the selected source scope should exclude.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct origin separation from structured Codex metadata.
2. One shared projection path for rows, filters, and counts.
3. Relay/live parity with stored history.
4. Small changes that fit the existing SwiftUI/Store/Projector architecture.
5. Clear tests that protect the no-leak invariant without brittle UI goldens.

## 1.2 Constraints

- App-server `thread/list` omits non-interactive sources by default when `sourceKinds` is omitted or empty.
- Requesting only `.cli` and `.vscode` would accidentally drop interactive custom sources such as `atlas` and `chatgpt`.
- The Dock's live relay currently merges loopback rows over history and must apply any source filtering itself.
- Existing `Running` means loaded live work, not only active turns; it includes `.needsMe`, `.running`, `.idle`, and `.failed` rows.
- The app already has multi-host state, archive state, local metadata, and auto-refresh; the change should reuse those paths.

## 1.3 Architectural principles (rules we will enforce)

- Map raw protocol fields into a typed app model before UI code sees them.
- Put tab/status predicates in state/model projection code, then let SwiftUI render the result.
- Preserve the default human query path for interactive sources; add a separate agent query/scope only where needed.
- Keep relay source filtering behavior-level and testable with plain row objects.
- Prefer explicit `unknown` classification over guessing from weak markers.

## 1.4 Known tradeoffs (explicit)

- A separate Agents scope is clearer than expanding the existing `All` filter to include both humans and agents, because the user explicitly wants sub-agents out of the main tab.
- The plan uses structured `source == "exec"` as a non-interactive automation signal, but does not rely on `thread_source: "user"`, JSON mode, shell flags, cwd, or prompt headers to decide that.
- Counts should ignore search text by default so tab labels represent the loaded state, while the empty state can still explain search/filter misses.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Codex Dock already loads sessions through `thread/list`, maps them into `SessionSummary`, projects rows with `SessionRowProjector`, and renders a Dock list with status filters. The protocol DTO already decodes source fields, but the app model drops them. The relay merges live rows from loopback app-servers over stored history.

## 2.2 What’s broken / missing (concrete)

- Human, sub-agent, and non-interactive automation sessions can be indistinguishable once they reach `SessionSummary`.
- The main Dock has no typed way to exclude Codex-created sub-agent or automation rows.
- There is no Agents scope/tab that collects structured machine-origin Codex sessions.
- Filter predicates live in `DockView`, so counts added there would drift from store/tests.
- The relay can collect live rows without applying `sourceKinds`, which can reintroduce rows the app intended to separate.

## 2.3 Constraints implied by the problem

The fix must start at the source/model boundary, carry typed origin through projection, and put counts in the same state/projection layer as filtering. UI-only filtering or string heuristics would be too late and too weak.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- None needed. This change is governed by existing Codex app-server protocol metadata and the local Dock architecture, not by external prior art.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors (do not reinvent):
  - `CodexDock/AppServer/ThreadListDTO.swift` - `ThreadListParams.sourceKinds` already models server-side source filtering, and `ThreadDTO` already decodes `source`, `threadSource`, `agentNickname`, and `agentRole`.
  - `CodexDock/Models/SessionSummaryMapper.swift` - the canonical Swift boundary that maps raw protocol DTOs into app-facing `SessionSummary`; this is where raw source metadata should become typed app origin.
  - `CodexDock/Models/SessionSummary.swift` - the app-facing row model currently lacks origin/source fields, which is why downstream state cannot distinguish humans from agents.
  - `CodexDock/State/SessionRowProjector.swift` - the canonical projection boundary for row status, display grouping, sort priority, rail selection, and local metadata decoration.
  - `CodexDock/State/DockStore.swift` - the owner of `DockSnapshot`, refresh cadence, multi-host fan-out, and state publication; this is where canonical count models should live after rows are projected.
  - `CodexDock/Features/Dock/DockView.swift` - current UI owner of `DockFilter`; it should render scope/filter/count projections rather than own business predicates.
  - `scripts/dock-relay.mjs` - the host-side relay that merges stored history with live loopback rows; it must apply source filtering to live rows or it can reintroduce sub-agent rows into human results.
  - `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs` - app-server `Thread` exposes `source`, `threadSource`, `agentNickname`, and `agentRole`.
  - `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs` - `ThreadListParams.sourceKinds` and `ThreadSourceKind` define the supported filter contract.
  - `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/filters.rs` - server-side source filtering distinguishes `Cli`, `VsCode`, `Exec`, `AppServer`, sub-agent variants, and `Unknown`.
  - `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/protocol.rs` - core `SessionSource` and `ThreadSource` define structured source semantics, including `SubAgent` and `ThreadSource::Subagent`.
  - `/Users/aelaguiz/workspace/codex/codex-rs/core/src/codex_delegate.rs` - Codex-spawned sub-agent sessions are created with `SessionSource::SubAgent(...)` and `thread_source: Some(ThreadSource::Subagent)`.
  - `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/lib.rs` - omitted/empty source filters default to interactive sources (`Cli`, `VSCode`, `atlas`, `chatgpt`), so the main human query should preserve that default instead of narrowing to only `.cli` and `.vscode`.
  - `/Users/aelaguiz/workspace/codex/codex-rs/memories/write/src/runtime.rs` creates memory-consolidation rows with an internal source, but current `ThreadSourceKind` cannot select internal rows; this plan treats memory/internal as out of scope instead of fixture-only proof.
- Canonical path / owner to reuse:
  - `SessionSummaryMapper` owns DTO-to-app origin normalization.
  - `SessionRowProjector` owns row projection and should expose or reuse shared tab/status predicates.
  - `DockSnapshot` owns count state derived from projected rows.
  - `dock-relay.mjs` owns live-row source filtering parity before rows reach the phone.
- Adjacent surfaces tied to the same contract family:
  - `CodexDockTests/ThreadListMappingTests.swift` must cover origin decoding and mapping.
  - `CodexDockTests/DockStoreTests.swift` must cover scope filtering and counts at the store/projection boundary.
  - `scripts/dock-relay.test.mjs` must cover source filtering for live merged rows.
  - `CodexDock/State/ArchiveStore.swift` also uses `SessionRowProjector`; it can carry origin fields without inheriting Dock-specific human/agent scope UI.
  - `CodexDock/State/HostSettingsStore.swift` also depends on `DockSessionLoading`; host connection tests must use the new default-human `DockSessionQuery` while staying a Hosts-tab smoke check, not an Agents UI.
  - `CodexDock/Configuration/DockHostConfiguration.swift` now has `bearerToken: String?`; all loader and relay-call code must preserve nil bearer as the normal physical-iPhone relay path.
  - `CodexDock/Configuration/RelayBootstrapStore.swift` and `CodexDock/Configuration/RelayDiscovery.swift` now produce non-secret discovered relay hosts. This plan must not regress bootstrap back to env-only or token-required host config.
  - `README.md` or runbook docs should be updated only if implementation changes the operator-facing meaning of Dock/Agents labels or relay query debugging.
- Compatibility posture (separate from `fallback_policy`):
  - Preserve existing app-server request/response contracts. Add Swift-side typed interpretation and relay-side filtering behavior using existing `sourceKinds`; do not add protocol fields or runtime shims.
- Existing patterns to reuse:
  - `SessionSummaryMapper.map(response:hostID:)` already converts sparse app-server rows into typed app model plus scoped mapping failures.
  - `SessionRowProjector.sections(from:)` already centralizes row status, sorting, grouping, metadata decoration, and relative time.
  - `DockSnapshot.rowCount` already derives count from sections; extend this idea to counted tab view models.
  - `DockStore.loadAllHosts()` already fans out across hosts and refreshes every five seconds via `DockView.runRefreshLoop()`.
  - Relay helpers such as `statusPriority`, `preferThread`, and `shouldCollectLiveRowsForThreadList` already make row-level behavior testable in Node.
- Prompt surfaces / agent contract to reuse:
  - No prompt change is needed for the app behavior. Codex sub-agent creation already writes structured session metadata; the Dock should consume that metadata directly.
- Native model or agent capabilities to lean on:
  - Native Codex session metadata and app-server source filtering are the capability to lean on. The plan should not introduce message-content parsers or model-output heuristics.
- Existing grounding / tool / file exposure:
  - Real session files under `/Users/aelaguiz/.codex/sessions` show recent sub-agent rows with `source.subagent.thread_spawn`, `thread_source: "subagent"`, and agent nickname/role fields.
  - Real interactive rows show `source: "cli"` or `source: "vscode"` with `thread_source: "user"` and no agent metadata.
  - Real `exec` rows show `source: "exec"` with `thread_source: "user"`, which confirms `thread_source == user` is not enough to decide human-vs-machine.
  - A local summary of 1,135 session metadata rows found hundreds of structured sub-agent rows plus string-source CLI/VSCode/exec rows, which confirms `source` and sub-agent metadata are stronger signals than JSON output mode.
  - Current upstream filtering does not make `ThreadSourceKind.unknown` match core internal/memory sources, so Agents cannot promise memory/internal rows without an upstream contract change that is out of scope here.
- Duplicate or drifting paths relevant to this change:
  - `DockFilter.includes` currently lives in `DockView`, while `SessionRowProjector.status(for:)` owns the status projection. Adding counts in SwiftUI without extracting the predicate would create duplicate truth.
  - `dock-relay.mjs` forwards `thread/list` params to history but collects live loopback rows independently. That live path must not ignore `sourceKinds`.
- Capability-first opportunities before new tooling:
  - Use existing `threadSource`/`source` metadata and existing `sourceKinds` filtering before any bespoke scanner.
  - Use the existing app refresh loop and store snapshot before adding a background count monitor.
  - Use existing Swift and Node tests before adding new harnesses.
- Behavior-preservation signals already available:
  - `CodexDockTests/ThreadListMappingTests.swift` protects sparse DTO mapping and status decoding.
  - `CodexDockTests/DockStoreTests.swift` protects row grouping, filtering semantics, multi-host fan-out, metadata persistence, archive behavior, and host settings.
  - `scripts/dock-relay.test.mjs` protects relay merge/filter helpers.
  - `rtk swift test` and `rtk npm run test:relay` are the focused verification commands for changed Swift and relay surfaces.

## 3.3 Decision gaps that must be resolved before implementation

- None. Repo truth plus the user objective settle the main choices: structured metadata is authoritative; main human scope excludes Codex sub-agent and non-interactive automation rows; Agents scope owns structured machine-origin rows; counts come from shared projected state; relay live rows must honor source filters.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `CodexDock/AppServer/ThreadListDTO.swift` already defines the request-side `ThreadListParams.sourceKinds` and the response-side `ThreadDTO.source`, `threadSource`, `agentNickname`, and `agentRole` fields.
- `CodexDock/Models/SessionSummary.swift` is the app-facing session row model. It currently carries status, repository, cwd, branch, timestamps, and display text, but no source/origin fields.
- `CodexDock/Models/SessionSummaryMapper.swift` is the canonical DTO-to-model boundary. It maps required identifiers, status, timestamps, repository, branch, title, and summary text, but currently drops origin metadata.
- `CodexDock/State/SessionRowProjector.swift` is the canonical row projection boundary. It maps `SessionStatus` into `DockRowStatusKind`, assigns row rails, groups by branch/host, and sorts by status priority and activity.
- `CodexDock/State/DockStore.swift` owns multi-host loading, local metadata, snapshot publication, archive refresh, and five-second refresh cadence.
- `CodexDock/Features/Dock/DockView.swift` owns the visible Dock shell and currently owns `DockFilter`, including the status predicates.
- `CodexDock/State/ArchiveStore.swift` reuses the same loader and projector for archived rows. It is adjacent because model/API changes must compile through it, but the Agents tab UX is Dock-only.
- `scripts/dock-relay.mjs` merges history `thread/list` rows with live loopback `thread/loaded/list`/`thread/read` rows. It currently forwards `thread/list` params to history but does not filter live rows by `sourceKinds`.
- `CodexDockTests/ThreadListMappingTests.swift`, `CodexDockTests/DockStoreTests.swift`, and `scripts/dock-relay.test.mjs` are the focused behavior-test surfaces for this change.

## 4.2 Control paths (runtime)

1. `DockView.runRefreshLoop()` calls `store.load()` once and `store.refresh()` every five seconds.
2. `DockStore.reload(showLoading:)` loads local metadata, fans out across configured hosts, builds a `DockSnapshot`, and publishes `.loaded`, `.empty`, `.offline`, or `.error`.
3. `AppServerDockClient.loadSessions(for:archived:)` calls `thread/list` with `limit`, `updated_at desc`, `modelProviders: []`, and `archived`, but omits `sourceKinds`. In Codex app-server, omitted/empty `sourceKinds` means the interactive default (`cli`, `vscode`, `atlas`, `chatgpt`), not all sessions.
4. `SessionSummaryMapper.map(response:hostID:)` maps each `ThreadDTO` into `SessionSummary`. Origin fields are available on the DTO but are discarded here.
5. `SessionRowProjector.sections(from:)` turns summaries into rows and sections. Its private `status(for:)` is the real status projection, but `DockView.DockFilter.includes` separately owns filter predicates.
6. `DockView.loadedContent(_:)` filters projected sections by `DockFilter.includes(row)` plus search text. Counts are not modeled, so the segmented picker renders static labels.
7. `scripts/dock-relay.mjs` reads stored history with the caller's params, independently collects every live loopback row, merges live over history, sorts, and returns the page. Because the live path ignores `sourceKinds`, live sub-agent or non-interactive rows can leak into an otherwise human-default request.

## 4.3 Object model + key abstractions

- `ThreadSourceKind` already has `cli`, `vscode`, `exec`, `appServer`, sub-agent variants, and `unknown`.
- `ThreadDTO.source` is a `JSONValue?` because server/source shapes can be string or structured object.
- `ThreadDTO.threadSource` is useful subtype evidence, but not a human-vs-machine classifier by itself. Real `exec` rows can carry `threadSource: "user"`.
- `SessionSummary` currently cannot answer "human, agent, automation, or unknown" after mapping.
- `DockRowStatusKind` is the current normalized status concept: `.needsMe`, `.running`, `.failed`, `.idle`, `.unknown`, `.limited`.
- `DockSnapshot.rowCount` counts only currently projected sections. There is no tab-count model and no preserved raw row set for multiple tab scopes.

## 4.4 Observability + failure behavior today

- Mapper failures are scoped and visible through `MappingFailureBanner`; malformed rows do not fail the whole page.
- Unknown statuses and active flags are preserved as `.unknown(...)` at the DTO/model boundary and remain visible.
- Host failures are surfaced as offline/error states per host.
- The relay logs history/live/returned counts but not source-filter exclusion counts.
- There is no explicit failure mode for unknown origin because origin is dropped before state/UI sees it.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current Dock control shape:

```text
Dock

[ All | Needs me | Running | Limited ]
[ Search sessions                         ]

Host summary
Section title
  Row
  Row
```

Current behavior gap:

```text
[ Running ]
  live human row
  live sub-agent row   <- can leak through relay live merge
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- Add typed origin/source models beside `SessionSummary` in `CodexDock/Models/SessionSummary.swift` or a small sibling model file:
  - `SessionOrigin`
  - `SessionSourceKind`
  - `SessionAgentMetadata`
- Update `SessionSummaryMapper` to normalize `ThreadDTO.source`, `threadSource`, `agentNickname`, and `agentRole` into `SessionOrigin`.
- Move Dock tab/filter predicates out of `DockView` into state/projection code, either in `SessionRowProjector.swift` or a small `DockTabProjector` sibling under `CodexDock/State`.
- Add `SessionOrigin` directly to `DockRowViewModel`; the row view model is the single predicate input and carries both row status and origin.
- Extend `DockSnapshot` with tab view models, tab-scoped sections, and `DockScopeLoadFailure` records. Keep `DockView` as renderer only.
- Update `AppServerDockClient`, `DockStore`, `ArchiveStore`, `HostSettingsStore`, preview loaders, and test fakes to pass a typed source query through the existing `ThreadListParams.sourceKinds` field.
- Update `scripts/dock-relay.mjs` with testable source-kind helpers that mirror the app-server filter behavior for live rows.

## 5.2 Control paths (future)

1. `DockStore` requests two source scopes per host for active Dock rows through one typed query object:
   - human/default scope: `sourceKinds: nil`, preserving app-server's interactive default (`cli`, `vscode`, `atlas`, `chatgpt`).
   - agents scope: explicit non-interactive kinds, excluding broad `.subAgent` so internal/memory sub-agent history rows cannot leak through: `[.exec, .appServer, .subAgentReview, .subAgentCompact, .subAgentThreadSpawn, .subAgentOther, .unknown]`.
2. `AppServerDockClient` remains protocol-compatible with the app-server. It only passes existing `ThreadListParams.sourceKinds`; no server protocol fields are added.
3. `SessionSummaryMapper` classifies every mapped row from structured fields. It never inspects prompt text, JSON mode, cwd, command flags, or message content.
4. `DockStore.makeSnapshot` dedupes host-scoped rows across the two query results, preserving the more specific machine/agent origin if the same thread appears from both paths.
5. Scoped load outcome contract:
   - both human/default and Agents queries succeed: host is `.loaded(rowCount:)` when the deduped total is nonzero and `.empty` only when all tab scopes have zero rows.
   - human/default succeeds and Agents fails: host is visible as `DockHostLoadStatus.partial(rowCount:message:)` with loaded human rows/counts plus an explicit Agents-scope failure in `DockSnapshot.scopeLoadFailures`; it is not silently shown as `Agents 0`.
   - Agents succeeds and human/default fails: host is visible as `DockHostLoadStatus.partial(rowCount:message:)` with loaded Agents rows/counts plus an explicit human/default failure in `DockSnapshot.scopeLoadFailures`; it is not treated as all-offline or empty.
   - both queries fail: keep the existing single-host `.offline`/`.error` behavior, choosing offline only when the failures are offline-class failures and error otherwise.
   - `DockSnapshot.rowCount` and `DockHostLoadStatus.loaded(rowCount:)` count deduped total known rows across all successful tab scopes, not the selected tab and not human rows only.
6. `SessionRowProjector` projects rows once into `DockRowViewModel`, then a shared `DockTabID.includes(_ row: DockRowViewModel)` predicate derives:
   - `All <n>`: human/interactive rows, all statuses.
   - `Needs me <n>`: human/interactive rows with `.needsMe`.
   - `Running <n>`: human/interactive rows included by the current running predicate (`needsMe`, `running`, `idle`, `failed`).
   - `Limited <n>`: human/interactive rows with `.limited`.
   - `Agents <n>`: agent/automation/unknown-origin rows, all statuses.
7. `DockView` binds selected tab state to the snapshot's tab IDs and renders the tab labels supplied by the snapshot. It still applies search text locally against the currently selected tab sections.
8. `scripts/dock-relay.mjs` applies `params.sourceKinds` to live loopback rows before merging them with history:
   - omitted/empty `sourceKinds` uses the same interactive default semantics as history.
   - explicit agent/non-interactive filters return only matching live rows.
   - archived requests continue to skip live rows.

## 5.3 Object model + abstractions (future)

Canonical origin model:

```swift
public enum SessionOrigin: Equatable, Sendable {
    case humanInteractive(SessionOriginEvidence)
    case agentOrAutomation(SessionAgentOrigin)
    case unknown(SessionOriginEvidence)
}

public struct SessionAgentOrigin: Equatable, Sendable {
    public let kind: SessionAgentOriginKind
    public let nickname: String?
    public let role: String?
}

public enum SessionAgentOriginKind: Equatable, Sendable {
    case exec
    case appServer
    case subAgentReview
    case subAgentCompact
    case subAgentThreadSpawn
    case subAgentOther
    case unknownMachine
}
```

Required classification rules:

- `source` matching sub-agent shapes classifies as `.agentOrAutomation` with the explicit sub-agent variant; generic sub-agent or `agentNickname`/`agentRole` evidence classifies as the explicit other-sub-agent variant.
- `source == "exec"` classifies as `.agentOrAutomation(kind: .exec)`. This is structured non-interactive source metadata, not a guess from `--json` or command shape.
- `source == "mcp"` / app-server-equivalent classifies as `.agentOrAutomation(kind: .appServer)`.
- `source == "cli"`, `source == "vscode"`, and known interactive custom sources classify as `.humanInteractive`.
- missing, unrecognized, or internally contradictory source metadata classifies as `.unknown`; unknown rows are visible in the `Agents` tab and not silently trusted as human.
- `threadSource == "user"` alone does not classify a row as human because real `exec` rows also use it.

Tab/filter model:

```swift
public enum DockTabID: String, CaseIterable, Sendable {
    case all
    case needsMe
    case running
    case limited
    case agents
}

public struct DockTabViewModel: Equatable, Identifiable, Sendable {
    public let id: DockTabID
    public let title: String
    public let count: Int
    public var label: String { "\(title) \(count)" }
}
```

Scope-load failure model:

```swift
public enum DockSessionScope: String, Equatable, Sendable {
    case humanDefault
    case agents
}

public struct DockScopeLoadFailure: Equatable, Sendable {
    public let hostID: String
    public let scope: DockSessionScope
    public let message: String
}
```

`DockSessionQuery` is the internal loader contract:

```swift
public struct DockSessionQuery: Equatable, Sendable {
    public let archived: Bool
    public let sourceKinds: [ThreadSourceKind]?
}
```

`DockRowViewModel.origin` is the required predicate input:

```swift
public struct DockRowViewModel: Equatable, Identifiable, Sendable {
    public let origin: SessionOrigin
    // existing row display fields stay unchanged
}
```

`DockTabID.includes(_ row: DockRowViewModel)` is the single predicate used by both counts and visible rows. There is no wrapper or second predicate layer; tests must fail if origin filtering and status filtering split apart.

## 5.4 Invariants and boundaries

- Source/origin is normalized exactly once at the DTO-to-model boundary.
- UI code does not classify origin and does not own status predicates.
- The human tabs preserve app-server default interactive semantics; they do not narrow to only `.cli` and `.vscode`.
- The Agents tab is a visibility surface for structured non-interactive Codex rows. It must not rely on JSON mode, prompt headers, cwd, or shell flags.
- Unknown-origin rows are visible and auditable in Agents; they are not hidden and not counted as human.
- Relay live-row filtering must match the history/app-server `sourceKinds` semantics closely enough that a source-filtered `thread/list` result cannot be polluted by live rows.
- Counts are based on the loaded snapshot before search filtering. Search can produce an empty selected view without changing tab counts.
- `DockSnapshot.rowCount` means total deduped known rows across all successful scopes, and host `.loaded(rowCount:)`/`.partial(rowCount:message:)` use the same count meaning.
- Mixed-scope load failures stay visible through `DockSnapshot.scopeLoadFailures`; a failed scope must not become a false zero count or a false empty state.
- Archive and Hosts app tabs remain as they are. Archive and Host connection testing carry the model/API changes needed to compile; Archive does not gain the Agents Dock tab, and Hosts testing remains a default-human connectivity smoke check.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Target Dock control shape:

```text
Dock

[ All 14 | Needs me 5 | Running 4 | Limited 3 | Agents 2 ]
[ Search sessions                                             ]

Host summary
Section title
  Row
  Row
```

Target no-leak behavior:

```text
[ All 14 ]
  human/interactive rows only

[ Agents 2 ]
  codex exec automation row
  codex sub-agent row
```

Empty states stay tab-specific:

```text
[ Agents 0 ]
No agent sessions
No structured machine-origin Codex sessions are visible on reachable hosts.
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| DTO | `CodexDock/AppServer/ThreadListDTO.swift` | `ThreadSourceKind`, `ThreadDTO.source/threadSource/agentNickname/agentRole` | Decodes the fields needed for this feature. | Keep as protocol boundary; add any tiny helpers only if needed by mapper tests. | Existing protocol already has the contract. | No protocol field additions. | `ThreadListMappingTests`, `AppServerClientTests` if encoding fixtures change. |
| Model | `CodexDock/Models/SessionSummary.swift` | `SessionSummary` | Drops source/origin metadata. | Add typed `origin` field and supporting origin/evidence types. | Downstream state needs deterministic routing. | `SessionSummary.origin: SessionOrigin`. | `ThreadListMappingTests`, `DockStoreTests` fixture helpers. |
| Mapper | `CodexDock/Models/SessionSummaryMapper.swift` | `map(thread:hostID:index:)` | Ignores `source`, `threadSource`, `agentNickname`, and `agentRole`. | Normalize structured origin once while mapping each row. | Prevent UI heuristics and duplicate truth. | `SessionOrigin` classification rules. | New mapper tests for CLI/VSCode, exec, appServer/MCP, sub-agent object/string variants, agent metadata, missing/unknown. |
| Loader API | `CodexDock/State/DockStore.swift` | `DockSessionLoading.loadSessions` | Accepts only `host` and `archived`. | Replace with `loadSessions(for:query:)` and update all adopters in one cutover. | Dock must request human and agent scopes intentionally without positional API drift. | `DockSessionQuery(archived:sourceKinds:)`. | `DockStoreTests`, `ArchiveStore` tests, fake loaders. |
| App-server client | `CodexDock/State/DockStore.swift` | `AppServerDockClient.loadSessions` | Omits `sourceKinds` for all calls. | Pass `query.sourceKinds` into `ThreadListParams`; pass `query.archived` to `archived`. Human calls pass `nil`; Agents calls pass explicit non-interactive kinds. | Preserve interactive default while loading Agents. | Existing `ThreadListParams.sourceKinds`. | `AppServerClientTests` request encoding; `DockStoreTests` loader request capture. |
| Store | `CodexDock/State/DockStore.swift` | `loadAllHosts()`, `makeSnapshot(results:)`, `DockHostLoadStatus`, `DockSnapshot.rowCount` | Loads one result set per host and builds one section list. | Load human and Agents scopes per host, dedupe by host/thread, build tab models, tab-scoped sections, `DockScopeLoadFailure`, `DockHostLoadStatus.partial(rowCount:message:)`, and scoped empty handling. | Counts and rows must share predicates, and partial scope failures must not be hidden. | `DockSnapshot.tabs`, selected-tab-compatible section lookup, deduped total row count, scoped load failure model, partial host status. | New count/no-leak/scoped-failure tests; existing multi-host tests updated for host counts. |
| Projection | `CodexDock/State/SessionRowProjector.swift` | `sections(from:)`, private `status(for:)`, `DockRowViewModel` | Projects status but does not expose shared tab predicates, and rows do not carry origin. | Add `origin` to `DockRowViewModel`; pair with `DockTabProjector` so `DockTabID.includes(_ row: DockRowViewModel)` is the one predicate for counts and visible rows. | Avoid duplicate status/origin logic in SwiftUI or store code. | `DockTabID.includes(_ row: DockRowViewModel)`, `DockTabViewModel`. | Replace `testDockFiltersUseNormalizedRowStatus` with state/projector predicate tests that fail if origin and status are filtered separately. |
| UI | `CodexDock/Features/Dock/DockView.swift` | `DockFilter`, `controls`, `filteredSections`, empty-state copy | Owns filter enum, static labels, and predicates. | Render snapshot tabs with counts; keep only local selected tab ID and search text. | UI should not own business predicates. | `Picker` over `snapshot.tabs`; label from `DockTabViewModel.label`. | Snapshot-level assertion for counted tab labels. |
| Archive | `CodexDock/State/ArchiveStore.swift` | `loadAllHosts()` | Uses same loader without source query. | Update to new loader API with `DockSessionQuery(archived: true, sourceKinds: nil)`. | Compile and preserve existing Archive behavior exactly: archived interactive/default rows only. | Archive remains Dock-tab-neutral. | Existing archive restore test. |
| Hosts | `CodexDock/State/HostSettingsStore.swift` | `test(_:)` | Uses `tester.loadSessions(for:archived: false)` as a connection/default row-count smoke test. | Update to `DockSessionQuery(archived: false, sourceKinds: nil)` and keep it as human/default connectivity testing, not Agents UI. | Clean loader API cutover must include every production caller. | Hosts use default interactive semantics. | Existing host-settings test plus query capture. |
| Preview | `CodexDock/Features/Dock/DockView.swift` | `PreviewDockSessionLoader` | Conforms to old `DockSessionLoading` API. | Update to `loadSessions(for:query:)` and provide human/Agents-shaped preview rows only if needed for compiler-visible UI state. | Protocol cutover must include preview conformers. | Preview loader follows `DockSessionQuery`. | Compiler plus Swift tests. |
| Relay | `scripts/dock-relay.mjs` | `collectLiveRows`, `aggregateThreadList`, `shouldCollectLiveRowsForThreadList` | Collects all live rows for non-archived `thread/list`, regardless of source filters. | Add live source-kind matcher; pass `params.sourceKinds`; default nil/empty to interactive sources. | Prevent live sub-agent/non-interactive leaks, including broad `.subAgent` matching specific sub-agent variants. | `threadMatchesSourceKinds(row,kinds)`, `interactive default`. | New relay tests for default excludes sub-agent/exec, explicit Agents includes them, archived still skips live. |
| Relay exports | `scripts/dock-relay.mjs` | bottom test exports | Exports current helpers only. | Export source-kind helpers for unit tests. | Keep relay behavior testable without WebSocket integration. | Helper exports only. | `scripts/dock-relay.test.mjs`. |
| Tests | `CodexDockTests/ThreadListMappingTests.swift` | DTO/model fixtures | Covers status and sparse mapping, not origin. | Add structured source fixtures and classification assertions. | Protect no-heuristic classification. | Origin assertions. | Same file. |
| Tests | `CodexDockTests/DockStoreTests.swift` | fake loaders and filter tests | Fakes accept old loader API; filter test calls `DockFilter.includes`. | Update fakes to record source queries; assert human/Agents tab counts and no-leak rows. | Protect store-level truth. | Query capture plus `DockSnapshot.tabs`. | Same file. |
| Docs/runbook | `README.md` or existing runbook docs if touched | Relay/Dock behavior notes | May mention current Dock/relay behavior. | Update only if implementation changes operator-facing setup or debugging instructions. | Avoid stale live docs; avoid doc churn otherwise. | No new doc required unless touched. | None unless updated. |

## 6.2 Migration notes

- Canonical owner path / shared code path: `SessionSummaryMapper` owns origin normalization; `SessionRowProjector` or a sibling state projector owns tab predicates and counts; `DockSnapshot` owns the computed tab labels/sections.
- Deprecated APIs (if any): the old UI-local `DockFilter.includes` predicate is retired. The internal loader API is updated to `DockSessionQuery` in one cutover rather than carried as a parallel path.
- Delete list: remove `DockFilter.includes` from `DockView`; remove any duplicated count/filter predicates introduced during implementation before finalizing.
- Adjacent surfaces tied to the same contract family: `ArchiveStore`, `HostSettingsStore`, preview loaders, fake loaders, app-server request tests, relay live merge, and mapping/store tests move with the source-query/model contract.
- Compatibility posture / cutover plan: preserve the app-server protocol contract; clean-cut internal Swift API migration for loader/store/projector types; no runtime shim.
- Capability-replacing harnesses to delete or justify: none. This is deterministic metadata consumption, not an LLM behavior harness.
- Live docs/comments/instructions to update or delete: update only touched comments/docs that would become false; add one concise code comment at the origin classifier if the `threadSource == user`/`exec` gotcha is not obvious from code.
- Behavior-preservation signals for refactors: existing mapper/store/archive/host-settings tests continue to pass; new focused tests prove origin routing, scoped load failure visibility, and counts.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Filter predicates | `DockView.DockFilter` -> state/projector | Centralize tab/status predicates outside SwiftUI. | Counts and rendered rows cannot disagree. | include |
| Row predicate input | `DockRowViewModel` | Carry origin on the same object used for status-based tab filtering. | Prevent origin filtering in one layer and status filtering/counting in another. | include |
| Source filtering | `scripts/dock-relay.mjs` live merge | Mirror app-server `sourceKinds` semantics for live rows. | Relay cannot undo server/client source separation. | include |
| Model origin | `SessionSummary` and mapper | Carry typed origin past DTO boundary. | Later state/UI code does not parse raw JSON. | include |
| Archive rows | `ArchiveStore` | Compile through origin/query API without adding Dock Agents UX. | Shared model/API stays honest while Archive scope stays unchanged. | include |
| Host connection tests | `HostSettingsStore` | Use the same `DockSessionQuery` cutover with `sourceKinds: nil`. | Hosts stays a default-human connection smoke check and does not retain the old loader API. | include |
| Skill prompt/header heuristics | Any scanner or history parser | Do not add. | Prompt text and JSON mode are brittle and privacy-hostile for this job. | exclude |
| Upstream Codex protocol | `/Users/aelaguiz/workspace/codex` | No new field required for current feature. | Existing metadata is sufficient. | exclude |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. No fallbacks/runtime shims: the system must work correctly or fail loudly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid deletion-proof tests, visual constants, doc-driven gates, keyword absence gates, and repo-shape policing.

## Phase 1 — Origin Classifier And Source Query Contract

* Goal: Prove the highest-risk seam first: raw app-server source metadata becomes typed app origin, and source filters can be passed through the existing app-server contract without adding protocol fields.
* Work: This phase owns the DTO-to-model classification path and the internal loader-query cutover. It does not build the final Dock UI yet.
* Checklist (must all be done):
  - Add `SessionOrigin`, origin evidence, and agent/automation subtype types to `CodexDock/Models`.
  - Add `SessionSummary.origin` and update every test/helper initializer that constructs `SessionSummary`.
  - Update `SessionSummaryMapper` to classify CLI, VSCode, known interactive custom sources, `exec`, app-server/MCP, sub-agent object/string shapes, agent nickname/role evidence, and unknown/malformed source.
  - Add the `DockSessionQuery(archived:sourceKinds:)` internal API and update `DockSessionLoading`, `AppServerDockClient`, `ArchiveStore`, `HostSettingsStore`, `PreviewDockSessionLoader`, existing fake loaders, and every existing loader call site to compile against it.
  - Keep `DockSessionQuery` and every updated loader call compatible with `DockHostConfiguration.bearerToken == nil`; do not add a token requirement to human/default or Agents queries.
  - Preserve app-server protocol compatibility by only passing `DockSessionQuery.sourceKinds` into existing `ThreadListParams.sourceKinds`.
  - Add mapper tests covering human interactive rows, `exec` automation rows, app-server/MCP rows, sub-agent rows with nickname/role, sparse missing-source rows, unknown source rows, and the `threadSource == "user"`/`source == "exec"` gotcha.
  - Add or update request/loader tests proving human/default queries pass `sourceKinds: nil`, Hosts testing uses `DockSessionQuery(archived: false, sourceKinds: nil)`, Archive uses `DockSessionQuery(archived: true, sourceKinds: nil)`, and Agents queries can pass the explicit non-interactive source-kind list.
* Verification (required proof):
  - `rtk swift test --filter ThreadListMappingTests`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
* Docs/comments (propagation; only if needed): Add one concise code comment at the origin classifier explaining that `threadSource == "user"` is not a human signal when `source == "exec"`.
* Exit criteria (all required):
  - `SessionSummary` carries typed origin for every mapped row.
  - Classification uses only structured DTO fields and never prompt text, JSON mode, cwd, or shell flags.
  - Unknown source metadata maps to `.unknown` without dropping the row.
  - The internal loader contract is `DockSessionQuery`, not parallel old/new load APIs.
  - Focused mapper, request-encoding, and loader-caller tests pass.
* Rollback: Revert the model, mapper, loader-query, and related test changes from this phase; the app returns to the existing human-default single-query behavior.

## Phase 2 — Store Snapshot Tabs, Counts, And No-Leak Rows

* Goal: Build the first working app-state slice that produces counted Dock tabs and proves machine-origin rows do not appear under human tabs.
* Work: This phase expands from typed origin into `DockStore`, `DockSnapshot`, and row projection. It creates the state shape the UI will render in Phase 4.
* Checklist (must all be done):
  - Update `DockStore.loadAllHosts()` to load both human/default and Agents source scopes per host for active Dock rows.
  - Use `DockSessionQuery(archived: false, sourceKinds: nil)` for human/default active rows.
  - Use the explicit Agents source-kind list for Agents active rows: `.exec`, `.appServer`, `.subAgentReview`, `.subAgentCompact`, `.subAgentThreadSpawn`, `.subAgentOther`, and `.unknown`; do not include broad `.subAgent` because it can select internal/memory sub-agent history rows.
  - Deduplicate rows by host/thread identity after both scopes load, preserving agent/automation/unknown origin over human origin if a row appears from both paths.
  - Add `DockTabID`, `DockTabViewModel`, and tab-scoped sections/counts to `DockSnapshot`.
  - Add `SessionOrigin` directly to `DockRowViewModel` before any tab predicate/count code runs.
  - Move the current `DockFilter` status predicates into the state/projector layer and make `DockTabID.includes(_ row: DockRowViewModel)` drive both tab counts and visible tab sections.
  - Keep the current `Running` predicate semantics: `needsMe`, `running`, `idle`, and `failed`.
  - Keep counts based on the loaded snapshot before search filtering.
  - Add an explicit scoped load outcome model for each host covering both scopes succeed, human succeeds/Agents fails, Agents succeeds/human fails, and both scopes fail.
  - Show mixed-scope failures as `DockHostLoadStatus.partial(rowCount:message:)` plus `DockSnapshot.scopeLoadFailures`; never collapse a failed scope to `Agents 0` or a false all-healthy host.
  - Define `DockSnapshot.rowCount` and host `loaded(rowCount:)` as deduped total known rows across all successful tab scopes; define empty as both required scopes succeeding with zero total rows.
  - Recompute tab counts from `DockSnapshot` after every existing DockStore state transition that changes loaded rows or metadata: initial load, normal refresh after rows change, local metadata save, archive success, and host-registry update.
  - Preserve multi-host grouping, local label/rail metadata, archive refresh, and existing all-failed offline/error behavior.
  - Update `DockStoreTests` to prove tab counts, no-leak routing, Agents inclusion for sub-agent and `exec` rows, unknown-origin visibility in Agents, predicate tests over `DockTabID.includes(_ row: DockRowViewModel)`, human success plus Agents failure, Agents success plus human failure, both scopes loaded, both scopes failed, Agents-only rows, human-only rows, multi-host partial failure, count recomputation after normal refresh, metadata save, archive success, host-registry update, and ArchiveStore's archived default query.
* Verification (required proof): `rtk swift test --filter DockStoreTests`
* Docs/comments (propagation; only if needed): Keep comments at the tab predicate boundary only if they explain a non-obvious invariant such as search not changing counts.
* Exit criteria (all required):
  - `DockSnapshot.tabs` contains `All`, `Needs me`, `Running`, `Limited`, and `Agents` labels with counts.
  - Human tabs exclude `.agentOrAutomation` and `.unknown` rows.
  - `Agents` includes `.agentOrAutomation` and `.unknown` rows.
  - Counts and visible rows use the same status-plus-origin tab predicates.
  - Partial scoped query failures are visible and tested; empty is only possible when all required scopes succeed with zero total rows.
  - `DockSnapshot.rowCount`, host `.loaded(rowCount:)`, and host `.partial(rowCount:message:)` use deduped total known rows across successful scopes.
  - Count recomputation is covered for load, normal refresh after rows change, metadata save, archive success, and host-registry update.
  - Existing store behaviors named in the checklist are preserved by tests.
* Rollback: Revert store/projector/snapshot changes and restore the single-section snapshot shape after Phase 1 remains independently valid.

## Phase 3 — Relay Live Source Filtering Parity

* Goal: Close the live-row side door so the relay cannot reintroduce non-human rows into human/default `thread/list` results.
* Work: This phase changes only the Node relay source-filtering path and its tests.
* Checklist (must all be done):
  - Add `threadMatchesSourceKinds(row, sourceKinds)` as the direct matcher for default, explicit Agents, and sub-agent variant requests. The relay may still recognize broad `.subAgent` for protocol parity, but the Dock Agents query must send only the explicit non-internal list above.
  - Keep the matcher independent of downstream auth. It must filter rows the same way for the implemented physical `phoneAuth=none` relay path and for explicit bearer-auth dev/hardening paths.
  - Match app-server default semantics for live rows: omitted or empty `sourceKinds` means interactive sources only, not all live rows.
  - Treat structured live rows with `source: "cli"`, `source: "vscode"`, and known interactive custom sources as default-human matches.
  - Treat live `exec`, app-server/MCP, sub-agent, and unknown source rows as excluded from default-human requests and included when explicitly requested by Agents source kinds.
  - Pass `params.sourceKinds` from `aggregateThreadList()` into live collection/filtering before merge and pagination.
  - Preserve archived behavior: archived `thread/list` still skips live rows.
  - Export only the small relay helper functions needed by `scripts/dock-relay.test.mjs`.
  - Add relay tests for default filtering, explicit Agents filtering with the same non-internal source-kind list as Swift, broad `.subAgent` compatibility when requested directly, unknown handling, merge sanitization, and archived skip behavior.
* Verification (required proof): `rtk npm run test:relay`
* Docs/comments (propagation; only if needed): Add a short relay comment only if the default interactive-source rule would otherwise be easy to break.
* Exit criteria (all required):
  - A default `thread/list` response cannot include a live sub-agent or `exec` row through the relay merge path.
  - An explicit Agents source-kind request can include live sub-agent and `exec` rows.
  - Existing relay attention and merge-priority behavior remains covered.
  - Relay tests pass.
* Rollback: Revert relay helper/filter changes and relay tests; Swift phases remain valid but the feature is not complete until this side door is closed.

## Phase 4 — Dock UI Rendering, Cleanup, And Final Proof

* Goal: Render the counted tabs in the Dock, remove the old UI-owned predicate path, and run the complete verification set.
* Work: This phase connects the Phase 2 snapshot to SwiftUI and performs final reality-sync for touched docs/comments.
* Checklist (must all be done):
  - Replace `DockView.DockFilter` usage with snapshot-provided `DockTabViewModel` labels and a selected `DockTabID`.
  - Render `All <n>`, `Needs me <n>`, `Running <n>`, `Limited <n>`, and `Agents <n>` from `DockSnapshot.tabs`.
  - Use tab-scoped sections from the snapshot before applying search text locally.
  - Update empty-state titles/messages so `Agents` has a clear empty state and existing human tab messages remain accurate.
  - Remove UI-owned business predicates from `DockView`; SwiftUI should not recalculate counts.
  - Add a snapshot-level/UI-facing assertion proving tab labels include counts from `DockSnapshot` rather than static `DockFilter.rawValue`.
  - Prove the root Archive restore callback invokes `DockStore.refresh()` after restore success through a targeted root-wiring test seam or state-level assertion.
  - Inspect `README.md`, touched code comments, and touched docs for stale Dock/relay source-routing text; update any false live truth in the same change.
  - Run the complete Swift and relay checks.
  - Manually check the app on the physical `iPhone 14` against the relay endpoint after tests pass.
* Verification (required proof):
  - `rtk swift test`
  - `rtk npm run test:relay`
  - Manual physical `iPhone 14` check: human tabs show human/interactive rows with counts; `Agents` shows structured sub-agent and non-interactive automation rows with count; search does not change tab counts; archive restore returns to Dock with updated counts.
* Docs/comments (propagation; only if needed): Update touched docs/comments that would otherwise become false; do not add a new runbook unless implementation changes operator setup.
* Exit criteria (all required):
  - The visible Dock tab row shows live counts for every tab.
  - `DockView` renders tab state from `DockSnapshot` and has no separate copy of origin/status predicates.
  - Human tabs and `Agents` tab show the row sets promised by Section 5.
  - Search filters the selected tab's visible rows without changing tab counts.
  - Restore-triggered Dock refresh is proven at the root wiring level by test or state assertion, and the final manual iPhone flow records that the count update is visible after restore.
  - Full Swift tests and relay tests pass.
  - The manual iPhone check is recorded in the implementation worklog when implementation begins.
* Rollback: Revert Dock UI changes to the prior static filter picker while preserving lower-layer tests to keep the regression visible.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Unit tests (contracts)

- Mapper tests for structured origin classification.
- Projector/store tests for tab/status predicates and counts.
- Relay unit tests for source filtering over live rows.

## 8.2 Integration tests (flows)

- `rtk swift test` for Swift model/store/UI-facing state changes.
- `rtk npm run test:relay` for relay behavior.

## 8.3 E2E / device tests (realistic)

- Manual final check on the physical `iPhone 14` after implementation: the Dock main tabs show human/interactive rows with counts, the Agents tab shows structured sub-agent and non-interactive automation rows with counts, and the endpoint remains the relay path.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Ship as a hard behavior change in the local Dock app: the main Dock stops showing Codex sub-agent and structured non-interactive automation rows, and Agents becomes the explicit place to inspect them.

## 9.2 Telemetry changes

No new telemetry is required for this app-side plan. Existing app-server source fields are used as runtime data.

## 9.3 Operational runbook

Keep using the relay-backed endpoint from the current runbook. If counts or source routing look wrong, query `thread/list` through the relay and inspect `source`, `threadSource`, `agentNickname`, and `agentRole` fields before debugging UI code.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Explorer 1 checked frontmatter, TL;DR, Sections 0-2, Sections 7-10, helper-block drift, and count-refresh obligations against repo paths.
  - Explorer 2 checked Sections 3-7, owner paths, call-site completeness, loader-query migration, relay parity, cleanup, and verification alignment against repo paths.
  - Self-integrator reread the full artifact and integrated accepted findings into the main plan before writing this block.
- Findings summary:
  - Blocking finding accepted: loader API cutover omitted `HostSettingsStore` and preview loader surfaces from the explicit call-site inventory.
  - Blocking finding accepted: Section 0's count-refresh triggers were not all represented in Section 7 checklist and exit criteria.
- Integrated repairs:
  - Added `HostSettingsStore`, `PreviewDockSessionLoader`, and all loader call sites to Sections 3, 5, 6, and Phase 1, with default-human `DockSessionQuery` expectations.
  - Added explicit count recomputation obligations for load, normal refresh, metadata save, archive success, and host-registry update to Phase 2; restore root wiring proof lives in Phase 4.
  - Tightened relay and UI test wording so helpers and counted-label assertions are named concretely.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Use structured source metadata instead of JSON-mode heuristics

Context

The user suspected JSON mode might be a dead giveaway for machine-started Codex sessions but asked for a cleaner way.

Options

- Infer from JSON mode, command shape, prompt contents, or cwd.
- Use app-server and rollout metadata that already classifies thread/session source.

Decision

Use structured app-server metadata: `threadSource`, `source`, `agentNickname`, and `agentRole`.

Consequences

The plan avoids brittle heuristics and keeps origin routing tied to the Codex protocol/session metadata that already exists.

Follow-ups

None.

## 2026-05-28 - Audit-derived: exclude memory/internal maintenance threads from this plan

Blocker: Current upstream `ThreadSourceKind` filtering cannot select core internal/memory-consolidation rows. `ThreadSourceKind.unknown` maps to `CoreSessionSource::Unknown`, not `CoreSessionSource::Internal(_)`.

Consulted: `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/filters.rs`, `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs`, and `/Users/aelaguiz/workspace/codex/codex-rs/memories/write/src/runtime.rs`.

Decision: Do not promise memory/internal maintenance rows in the Agents tab as part of this plan. Keep unknown/unrecognized client rows visible in Agents, but do not add upstream protocol work.

Consequences: The plan stays implementable against the current app-server contract, and memory/internal support remains a separate upstream protocol change if needed later.

## 2026-05-28 - Intent-derived: route structured exec/app-server rows to Agents

Blocker: Real `exec` rows carry `thread_source: "user"`, so treating `threadSource` alone as human would hide machine-started `codex exec` sessions, while treating command flags or JSON mode as machine would be heuristic.

Consulted: TL;DR, Section 0.2, Section 0.5, Section 1.2, Section 3.2, and the user's clarification to filter Codex-initiated sub-agents.

Intent says: separate human-started sessions from machine/sub-agent-started Codex sessions, use a cleaner signal than JSON mode, and keep non-human rows out of the main human view.

Decision: Use structured `source` for top-level routing. `source == "exec"` and app-server/MCP source rows go to `Agents` as non-interactive automation rows; sub-agent source rows go to `Agents` as sub-agent rows; `threadSource == "user"` alone does not override `source`.

Consequences: The plan covers the user's skill-spawned `codex exec` shape without prompt/history heuristics, and the UI can still distinguish sub-agent subtype from non-interactive automation subtype inside the same Agents tab if needed later.

## 2026-05-28 - Intent-derived: use one counted Dock tab row

Blocker: The request could be implemented as nested scope tabs plus status filters, or as one flat counted tab row that adds `Agents` beside the existing Dock filters.

Consulted: TL;DR, Section 0.2, Section 1.4, current `DockView` filter shape, and the user's examples: `All 14`, `Needs me 5`, `Running 4`, `Agents 2`.

Intent says: keep human rows separate from agents and display counts in the visible tabs/filters.

Decision: Keep the existing Dock segmented-control shape and make it counted: `All`, `Needs me`, `Running`, and `Limited` apply to human/interactive rows; `Agents` is the machine-origin tab. All labels come from `DockSnapshot` tab view models.

Consequences: The UI matches the user's examples, avoids adding nested controls, and keeps status/scope predicates centralized outside SwiftUI.

## 2026-05-28 - Treat user objective as North Star confirmation for auto-plan

Context

The user asked for a new ArcStep auto plan and said planning is not done until plan audit agrees the plan is fully formed.

Options

- Stop after a draft North Star and ask for confirmation.
- Treat the explicit objective and follow-up clarification as the approved planning intent for this planning run.

Decision

Proceed with `status: active` and run the auto-plan sequence against this document.

Consequences

The artifact can advance through research, deep-dive, phase-plan, consistency-pass, and plan audit in this turn without narrowing the requested behavior.

Follow-ups

None.
