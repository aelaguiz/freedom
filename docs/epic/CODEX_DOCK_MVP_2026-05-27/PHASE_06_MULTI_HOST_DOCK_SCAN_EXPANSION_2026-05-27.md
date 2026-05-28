---
title: "Codex Dock - Multi-Host Dock Scan Expansion - Architecture Plan"
date: 2026-05-27
status: complete
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: new_system
related:
  - ../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - ../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png
  - ../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png
---

# TL;DR

- Outcome: Expand the proven single-host list/detail/control path into the
  multi-host scan board: host fan-out, branch grouping, filters, labels, and
  colors.
- Problem: The user runs many Codex sessions across computers; single-host
  control is not enough for the MVP operations board.
- Approach: Widen existing host/thread identity into a multi-host store and add
  app-local metadata on top.
- Plan: Add two-host fan-out first, then grouping/filters, then labels/colors.
- Non-negotiables: one offline host cannot block another, no AIMGR, no backend
  metadata dependency for labels/colors.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-27
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-27
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:38a478c14f27671d59b1f82f03e82d9a16ce841383f7c1b2b2a2a58ff7b51989",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:ddcb8605280d68a3746db4f6da7d1654683da9bd86f81b3769be2acf687a82a2",
      "completed_at": "2026-05-28T00:25:39Z",
      "doc_hash_after": "sha256:024109993548e4b98ebe6ac4a86458721c93c9b5549d9d9a8de1e68f690f44e9"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:024109993548e4b98ebe6ac4a86458721c93c9b5549d9d9a8de1e68f690f44e9",
      "completed_at": "2026-05-28T00:27:30Z",
      "doc_hash_after": "sha256:3cff580f73dfb7806f92cdc022b2df48945bc927d55828ceb50be49013ef6ba2"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:3cff580f73dfb7806f92cdc022b2df48945bc927d55828ceb50be49013ef6ba2",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:e2a679c71a02d3b76feade72b12d7f472d32773ab3acc40c07fa7e15d615f0b3"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:e2a679c71a02d3b76feade72b12d7f472d32773ab3acc40c07fa7e15d615f0b3",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:fdb7ca562c30a669f0ad3d0896fb1d3183c0796055a34da0b9225e73c89a2482"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:33Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:fdb7ca562c30a669f0ad3d0896fb1d3183c0796055a34da0b9225e73c89a2482",
      "completed_at": "2026-05-28T00:32:11Z",
      "doc_hash_after": "sha256:fe4cd97c6348c825b14510f31d9677750352edd12078fc9d84ecaeb8c5952a47"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

The app can show sessions from at least two configured hosts in one Dock,
isolate host failures, filter/group the feed, and persist app-local
labels/colors by host/backend/thread id.

## 0.2 In scope

- Host registry.
- Multi-host session store.
- Offline isolation.
- Host/branch grouping.
- All/Needs me/Running/Limited filters.
- App-local labels/colors.

## 0.3 Out of scope

- Archive and Hosts screen.
- Voice.
- AIMGR / Rotate.
- Claude Code backend.

## 0.4 Definition of done (acceptance evidence)

- Two hosts can be configured.
- One offline host does not blank another host.
- Filters/grouping operate on normalized state.
- Labels/colors persist locally.

## 0.5 Key invariants (fix immediately if violated)

- Host id is part of every key.
- Labels/colors do not mutate backend thread names.
- Existing single-host detail/control still works.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Preserve working single-host path.
2. Isolate failures.
3. Make scanning legible.
4. Keep local metadata simple.

## 1.2 Constraints

- Multi-host usage is real.
- Tailscale is not product model.

## 1.3 Architectural principles (rules we will enforce)

- One normalized multi-host state owner.
- Dock projections derive from state.
- Metadata key includes host/backend/thread.

## 1.4 Known tradeoffs (explicit)

- Label/color sync is post-V1.
- Search can remain basic.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Phase 5 provides one-host scanning and control.

## 2.2 What’s broken / missing (concrete)

The app does not yet answer what is happening across several computers.

## 2.3 Constraints implied by the problem

Widen the existing identity model rather than replace it.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- Multi-source state fan-out pattern — load each host independently, then
  project one UI model.
- Local metadata pattern — keep personal labels/colors app-local until sync is
  explicitly designed.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` — multiple hosts,
    host/branch grouping, filters, labels/colors.
  - `../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png` and
    `../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png` — visual
    anchors.
- Canonical path / owner to reuse:
  - Widen Phase 3 `DockStore` into `MultiHostSessionStore`.
- Adjacent surfaces tied to the same contract family:
  - Phase 7 Archive and Hosts consume the same host/session state.
  - Phase 4/5 detail routes must keep host/thread identity.
- Compatibility posture:
  - Preserve one-host behavior while widening state keys.
- Existing patterns to reuse:
  - Phase 2 `SessionSummary` and Phase 5 attention/request state.
- Prompt surfaces / agent contract to reuse:
  - Not agent-backed.
- Native model or agent capabilities to lean on:
  - None.
- Existing grounding / tool / file exposure:
  - UX spec and mockups.
- Duplicate or drifting paths relevant to this change:
  - Avoid separate Dock, Archive, and Hosts state owners.
- Capability-first opportunities before new tooling:
  - App-local persistence before sync machinery.
- Behavior-preservation signals already available:
  - Phase 1-5 checks remain green.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- One-host Dock/detail/control path exists by Phase 5.
## Control paths (runtime)
- One host loads; no fan-out or cross-host grouping.
## Object model + key abstractions
- Host id exists but no host registry or metadata store.
## Observability + failure behavior today
- One-host offline/error state only.
## UI surfaces (ASCII mockups, if UI work)
- Dock normal and Needs-me mockups anchor expansion.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `Models/HostRegistry.swift`.
- `State/MultiHostSessionStore.swift`.
- `State/LocalThreadMetadataStore.swift`.
- `Features/Dock/DockFilters.swift`.
## Control paths (future)
1. Registry provides enabled hosts.
2. Store loads each host independently.
3. Projection groups/filter rows.
4. Metadata decorates rows by host/backend/thread id.
## Object model + abstractions (future)
- `HostRegistry`, `HostSummary`, `DockFilter`, `LocalThreadMetadata`.
## Invariants and boundaries
- Host failure isolation; metadata app-local.
## UI surfaces (ASCII mockups, if UI work)
- Anchors: [Dock normal](../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png), [Needs-me filter](../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png).
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Hosts | `HostRegistry.swift` | configs | One host | Multiple hosts | MVP scope | registry | Unit |
| State | `MultiHostSessionStore.swift` | load | One host | Fan-out and merge | Operations board | host-scoped state | Unit |
| Filters | `DockFilters.swift` | filters | Minimal | All/Needs/Running/Limited | Scan | projection | Unit |
| Metadata | `LocalThreadMetadataStore.swift` | labels/colors | Missing | Persist local tags | Identify threads | local key | Unit |
## Migration notes
* Canonical owner path / shared code path: widen Dock state; do not fork.
* Deprecated APIs (if any): one-host-only store can become adapter/internal.
* Delete list: production demo rows if any.
* Adjacent surfaces tied to the same contract family: Archive/Hosts in Phase 7.
* Compatibility posture / cutover plan: preserve one-host behavior.
* Capability-replacing harnesses to delete or justify: none.
* Live docs/comments/instructions to update or delete: none.
* Behavior-preservation signals for refactors: Phase 1-5 tests/checks.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Identity | host/backend/thread key | metadata key | Prevent collisions | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: widen the proven Dock/detail/control path to multiple hosts; do
  not add Archive, Hosts, voice, or AIMGR.
- Adjacent-surface check: Archive and Hosts in Phase 7 must consume the same
  host registry and multi-host state instead of introducing parallel stores.
- Failure posture: one offline host reports its own error without blanking rows
  from other hosts.
- Depth-first proof: two-host fan-out works before filters, grouping, labels,
  and colors are treated as complete.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: two-host fan-out

Work: Widen the one-host Dock store into a multi-host state owner.

Checklist (must all be done):
- Host registry can hold at least two enabled hosts.
- Store loads each host independently.
- One offline host surfaces its own error without blanking connected hosts.
- Existing one-host detail/control routes still work.

Exit criteria (all required):
- Dock can show sessions from two configured hosts, or one live host plus one
  intentionally offline host.

## Implementation slice 2: grouping and filters

Work: Add scan projections over normalized multi-host state.

Checklist (must all be done):
- Dock can group by host and branch/cwd where data exists.
- All, Needs me, Running, and Limited filters derive from app state.
- Empty states explain the selected filter without implying data loss.
- Visuals remain aligned to [Dock normal](../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png)
  and [Needs-me filter](../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png).

Exit criteria (all required):
- Filters and grouping work without re-calling raw protocol from views.

## Implementation slice 3: local labels and colors

Work: Add app-local metadata keyed by host/backend/thread id.

Checklist (must all be done):
- Labels/colors persist locally.
- Metadata never mutates backend thread names.
- Collision tests prove host/backend/thread id is part of the key.

Exit criteria (all required):
- A label/color survives app restart or equivalent persistence reload.
- Phase 7 can reuse the host/session state.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

<!-- arch_skill:block:consistency_pass:start -->
# Consistency Pass

## Decision inventory
- Decision-complete:
  - yes
- Unresolved decisions:
  - none
- Decision: proceed to implement? yes

## Verification strategy
- Run store tests for two-host fan-out, one-host offline isolation, and
  one-host regression behavior.
- Run projection tests for host/branch grouping and All/Needs me/Running/Limited
  filters.
- Run metadata persistence tests for host/backend/thread keyed labels/colors.
- Manual/screenshot check against [Dock normal](../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png)
  and [Needs-me filter](../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png).

## Cold-read consistency checks
- Breadth expands only after one-host list/detail/control works.
- Archive and Hosts are assigned to Phase 7 and reuse this state.
- AIMGR and Rotate remain excluded from V1.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Local multi-host development.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Configure two hosts or one live host plus one intentionally offline host.

## 9.4 Implementation evidence

- Implemented `HostRegistry`, multi-host `DockStore` fan-out, per-host load
  states, host/branch grouping, filter projection, and app-local
  host/backend/thread keyed labels/colors.
- `CodexDockApp` now constructs the store from `HostRegistry.fromEnvironment()`.
- `rtk make app` launches with the host-registry env shape, prints endpoint and
  hosts, and terminates stale Codex Dock processes on other booted simulators.
- Real simulator proof used `Amir-M5` live plus `Home` intentionally offline.
- Worklog:
  `PHASE_06_MULTI_HOST_DOCK_SCAN_EXPANSION_2026-05-27_WORKLOG.md`.
- Implementation audit:
  `PHASE_06_MULTI_HOST_DOCK_SCAN_EXPANSION_2026-05-27_PLAN_AUDIT.md`.
- Thermonuclear review:
  `PHASE_06_MULTI_HOST_DOCK_SCAN_EXPANSION_2026-05-27_THERMONUCLEAR_REVIEW.md`.

# 10) Decision Log (append-only)

## 2026-05-27 - Multi-host after control

Context
: The app should deepen a working slice before expanding breadth.

Options
: Build multi-host earlier, or wait until one-host control works.

Decision
: Multi-host starts after one-host text/request control.

Consequences
: Breadth expands from a proven vertical slice.

## 2026-05-28 - Keep `DockStore` as the widened state owner

Context
: The Phase 6 plan named a `MultiHostSessionStore`, but the repo already had a
working `DockStore` that owned single-host state, row projection, refresh, and
detail navigation inputs.

Options
: Add a parallel multi-host store, or widen `DockStore` and keep the single-host
initializer as an adapter.

Decision
: Widen `DockStore` into the canonical multi-host Dock state owner.

Consequences
: Phase 7 must reuse this registry/state path and should extract projection
helpers if Archive/Hosts would otherwise add surface-specific logic to
`DockStore`.

## 2026-05-28 - Surface the real endpoint in the UI

Context
: Live debugging showed that `ws://192.168.50.117:4500` returns only
`notLoaded` history while `ws://192.168.50.117:4510` returns live active rows.
The prior host summary hid the port.

Options
: Keep displaying only the host name, or display the full WebSocket endpoint.

Decision
: Display the full endpoint including scheme, host, port, and path.

Consequences
: The Dock makes wrong-endpoint launches visible instead of turning them into a
status-filter mystery.
