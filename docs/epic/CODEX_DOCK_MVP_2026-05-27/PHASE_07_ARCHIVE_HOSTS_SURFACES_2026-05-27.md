---
title: "Codex Dock - Archive Hosts Surfaces - Architecture Plan"
date: 2026-05-27
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: new_system
related:
  - ../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - ../../mockups/codex-dock-2026-05-27-v2/05-archive.png
  - ../../mockups/codex-dock-2026-05-27-v2/06-hosts.png
---

# TL;DR

- Outcome: Add the remaining non-voice MVP surfaces: reversible archive and the
  Hosts screen.
- Problem: Once the Dock can scan many sessions, the user needs to clear done
  work and inspect host health/configuration.
- Approach: Use app-server archive/unarchive methods and the existing host
  registry/state to build Archive and Hosts.
- Plan: Add archive/unarchive first, then Hosts screen/status/config basics.
- Non-negotiables: archive is reversible, Hosts reuses existing state, no AIMGR.

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
  "digest": "sha256:5b6d8b8e546fd798e5ccdce52e36ab64df99ab06b19975afd243a314022e5047",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:f1c730414d6209fa41ddaa07430d76b3e1e6c9b2ba1eed3352fadc6b54d8cb38",
      "completed_at": "2026-05-28T00:25:39Z",
      "doc_hash_after": "sha256:8d3b40796df4f79359e469c5fc86cf7f4ba5cebe1fdae66a32560b0b39e02d37"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:8d3b40796df4f79359e469c5fc86cf7f4ba5cebe1fdae66a32560b0b39e02d37",
      "completed_at": "2026-05-28T00:27:30Z",
      "doc_hash_after": "sha256:7aa9a061c0eef60290941ee03b54c31cb6bbae03e9780a33927d96bfbbc1c630"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:7aa9a061c0eef60290941ee03b54c31cb6bbae03e9780a33927d96bfbbc1c630",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:7864c028a05908f360c8700c390929538251fb66dd5cfff7bc81b199364a0bbf"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:7864c028a05908f360c8700c390929538251fb66dd5cfff7bc81b199364a0bbf",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:ae4518b0cc939ebbf7fd46ce7143c04815f5d9861fd958c8dc629dd6a5664dd5"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:33Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:ae4518b0cc939ebbf7fd46ce7143c04815f5d9861fd958c8dc629dd6a5664dd5",
      "completed_at": "2026-05-28T00:32:11Z",
      "doc_hash_after": "sha256:cdd5cd32679f1fd0679dbaf620d081dbcf55feb80bd4b477bb447887ea2e65b9"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

A session can be archived out of the Dock and restored from Archive, and the
Hosts screen shows/edit/tests configured Codex app-server hosts without AIMGR.

## 0.2 In scope

- `thread/archive` and `thread/unarchive`.
- Archive screen.
- Hosts screen.
- Host add/edit/test at MVP utility level.

## 0.3 Out of scope

- AIMGR status/Rotate.
- General SSH terminal.
- Push notifications.
- Voice.

## 0.4 Definition of done (acceptance evidence)

- Archive removes from default Dock after success.
- Unarchive restores.
- Hosts screen uses same host registry/state.
- No AIMGR code ships.

## 0.5 Key invariants (fix immediately if violated)

- Archive is reversible.
- Host identity survives archive.
- Hosts does not introduce separate host state.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Reversible cleanup.
2. Host state consistency.
3. Utility over settings sprawl.
4. AIMGR exclusion.

## 1.2 Constraints

- App-server has archive/unarchive methods.
- Hosts screen should stay small.

## 1.3 Architectural principles (rules we will enforce)

- Archive and Dock share session state.
- Hosts reuses host registry.
- Actions fail visibly.

## 1.4 Known tradeoffs (explicit)

- Edit host flow can be utilitarian.
- Advanced host diagnostics are post-V1.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Phase 6 provides multi-host Dock scanning and labels/colors.

## 2.2 What’s broken / missing (concrete)

The user cannot clear done sessions or manage host settings from the app.

## 2.3 Constraints implied by the problem

Archive and Hosts should use the same state model rather than parallel lists.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- Reversible archive pattern — only remove from default list after success or
  with explicit rollback.
- Settings/status screen pattern — keep host configuration utilitarian.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` — `thread/archive` and
    `thread/unarchive`.
  - `../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` — Archive and Hosts V1
    scope, AIMGR out of V1.
  - `../../mockups/codex-dock-2026-05-27-v2/05-archive.png` and
    `../../mockups/codex-dock-2026-05-27-v2/06-hosts.png` — visual anchors.
- Canonical path / owner to reuse:
  - Phase 6 host/session state and host registry.
- Adjacent surfaces tied to the same contract family:
  - Dock, Archive, and Hosts use the same state model.
- Compatibility posture:
  - Preserve app-server archive semantics and local metadata identity.
- Existing patterns to reuse:
  - Phase 6 multi-host state.
- Prompt surfaces / agent contract to reuse:
  - Not agent-backed.
- Native model or agent capabilities to lean on:
  - None.
- Existing grounding / tool / file exposure:
  - UX spec and protocol ramp-up doc.
- Duplicate or drifting paths relevant to this change:
  - Avoid separate archived-session list owner.
- Capability-first opportunities before new tooling:
  - Use app-server archive methods before local-only hiding.
- Behavior-preservation signals already available:
  - Phase 6 multi-host tests/checks remain green.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- Multi-host Dock state exists by Phase 6; Archive/Hosts views do not.
## Control paths (runtime)
- Sessions can be scanned but not archived/restored.
## Object model + key abstractions
- Host registry exists; no ArchiveStore.
## Observability + failure behavior today
- Host connection state exists; host config utility is absent.
## UI surfaces (ASCII mockups, if UI work)
- Archive and Hosts mockups anchor surfaces.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `State/ArchiveStore.swift`.
- `Features/Archive/ArchiveView.swift`.
- `Features/Hosts/HostsView.swift`.
- `AppServerMethods.swift` — archive/unarchive wrappers.
## Control paths (future)
1. Dock action calls archive.
2. Success removes from default Dock.
3. Archive screen lists archived sessions and unarchives.
4. Hosts screen reads/edits/tests host registry entries.
## Object model + abstractions (future)
- `ArchiveStore`, `HostSettingsState`.
## Invariants and boundaries
- Archive reversible; Hosts shares registry; no AIMGR.
## UI surfaces (ASCII mockups, if UI work)
- Anchors: [Archive](../../mockups/codex-dock-2026-05-27-v2/05-archive.png), [Hosts](../../mockups/codex-dock-2026-05-27-v2/06-hosts.png).
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Protocol | `AppServerMethods.swift` | archive methods | Missing | Add archive/unarchive | Reversible cleanup | typed methods | Unit |
| State | `ArchiveStore.swift` | archive state | Missing | Own archive list/actions | Recovery | store API | Unit |
| UI | `ArchiveView.swift` | archive screen | Missing | List/restore archived rows | User workflow | SwiftUI | Manual |
| UI | `HostsView.swift` | hosts screen | Missing | Show/edit/test host config | Host utility | SwiftUI | Unit/manual |
## Migration notes
* Canonical owner path / shared code path: Phase 6 host/session state.
* Deprecated APIs (if any): none.
* Delete list: any local-only archive hiding if app-server archive works.
* Adjacent surfaces tied to the same contract family: Dock row archive action.
* Compatibility posture / cutover plan: preserve app-server archive semantics.
* Capability-replacing harnesses to delete or justify: none.
* Live docs/comments/instructions to update or delete: none.
* Behavior-preservation signals for refactors: Phase 6 multi-host checks.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Host state | `HostRegistry` | shared owner | Prevent Hosts/Dock drift | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: Archive and Hosts are V1 utility surfaces; AIMGR status, Rotate,
  SSH terminal behavior, and push notifications remain out.
- Adjacent-surface check: Dock, Archive, and Hosts must share host/session state
  so archive state and host health cannot drift.
- Failure posture: archive/unarchive actions fail visibly and preserve row
  identity; local-only hiding is a fallback only if app-server archive is absent.
- Depth-first proof: archive/unarchive round trip works before Hosts editing is
  treated as complete.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: archive/unarchive methods and state

Work: Add reversible archive operations on top of the existing host/session
state.

Checklist (must all be done):
- `AppServerMethods.swift` exposes archive and unarchive wrappers where the
  server supports them.
- `ArchiveStore` reuses host/session identity from Phase 6.
- Dock removes an archived session only after success or with explicit rollback.
- Failed archive/unarchive keeps the row recoverable.

Exit criteria (all required):
- A real or fake session archives out of Dock and unarchives back.

## Implementation slice 2: Archive screen

Work: Build the archive list and restore workflow.

Checklist (must all be done):
- Archive screen lists archived sessions with host/repo/branch/status context.
- Restore action calls unarchive and updates Dock/Archive state consistently.
- Visuals follow [Archive](../../mockups/codex-dock-2026-05-27-v2/05-archive.png).

Exit criteria (all required):
- Archive and Dock cannot disagree about the same restored session.

## Implementation slice 3: Hosts screen without AIMGR

Work: Build the MVP host utility surface from the same host registry.

Checklist (must all be done):
- Hosts screen shows host name/address, connection status, and last check.
- Add/edit/test host flow is utilitarian and uses existing registry state.
- No AIMGR status, Rotate button behavior, or account switching ships in V1.
- Visuals follow [Hosts](../../mockups/codex-dock-2026-05-27-v2/06-hosts.png)
  minus any post-V1 AIMGR behavior.

Exit criteria (all required):
- Host changes affect Dock through the shared registry.
- `rg` over implementation finds no AIMGR/Rotate integration in V1 code.
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
- Run archive/unarchive method tests and state tests for success, failure, and
  restore consistency.
- Run host registry tests for add/edit/test host behavior.
- Manual/screenshot check against [Archive](../../mockups/codex-dock-2026-05-27-v2/05-archive.png)
  and [Hosts](../../mockups/codex-dock-2026-05-27-v2/06-hosts.png).
- Verify V1 code does not implement AIMGR status, Rotate behavior, or account
  switching.

## Cold-read consistency checks
- Archive is reversible and uses app-server semantics first.
- Hosts shares the same registry as Dock.
- AIMGR is explicitly post-V1 even if a mockup shows exploratory affordance.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Local utility-surface development.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Archive/restore a real session and test a host connection.

# 10) Decision Log (append-only)

## 2026-05-27 - AIMGR excluded from Hosts

Context
: Hosts mockup may show Rotate exploration, but AI Manager is out of V1.

Options
: Include AIMGR status, or keep Hosts to Codex app-server health/config.

Decision
: Keep AIMGR out of V1 Hosts.

Consequences
: Hosts remains smaller and avoids unknown account-rotation scope.
