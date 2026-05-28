---
title: "Codex Dock - Thread Detail Read Live View - Architecture Plan"
date: 2026-05-27
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: new_system
related:
  - ../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - ../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
  - ../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png
---

# TL;DR

- Outcome: Tapping a real Dock row opens a session detail view that reads or
  resumes the thread and keeps receiving live updates.
- Problem: The Dock is useful for scanning, but the user needs to inspect what a
  session is doing before steering it.
- Approach: Add thread route state, thread read/resume methods, event
  normalization, notification merge, and session detail UI.
- Plan: Open read-only details first, then add live notification handling.
- Non-negotiables: no text send yet, no voice, no raw JSON in views, no AIMGR.

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
  "digest": "sha256:c29d8a3b9e62f6e97aabc8fe150cbfd4ef01a59611c99773b8301302e7b03276",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:fd71dd940081368775da6f670fb2380f02adca9320f17e354a2bcccd0f08e100",
      "completed_at": "2026-05-28T00:25:39Z",
      "doc_hash_after": "sha256:e9f5fd5911154e37c6ade7dc03afaa1670dd9c40d20f1e4e16cc48da48df089e"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e9f5fd5911154e37c6ade7dc03afaa1670dd9c40d20f1e4e16cc48da48df089e",
      "completed_at": "2026-05-28T00:27:30Z",
      "doc_hash_after": "sha256:a899d0472e7b3c35fae81d80a58b00f0145dcfddddbf7c1306614b816a2fb4c6"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:a899d0472e7b3c35fae81d80a58b00f0145dcfddddbf7c1306614b816a2fb4c6",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:9e18bd3772d522025cdb2c6c1b4819d41760106fba1fb7d73b5379f4036681b0"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:9e18bd3772d522025cdb2c6c1b4819d41760106fba1fb7d73b5379f4036681b0",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:12022a58ece197961648baae257a672f6389ae723c0a307ecb0832bd36d04848"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:33Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:12022a58ece197961648baae257a672f6389ae723c0a307ecb0832bd36d04848",
      "completed_at": "2026-05-28T00:32:11Z",
      "doc_hash_after": "sha256:29e8594dbaed8778ae3229c369407d95858771a451e6ca5d6ac9c62a8e6fc69a"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

From a real Dock row, the app opens the correct thread, renders normalized
events, and updates the event stream while notifications arrive.

## 0.2 In scope

- Navigation from Dock row.
- `thread/read`, `thread/resume`, and related read methods.
- Event normalization.
- Live notification loop for open thread.
- Session detail UI.

## 0.3 Out of scope

- Text send/steer.
- Request-card responses.
- Multi-host breadth beyond preserving host/thread id.
- Voice, AIMGR.

## 0.4 Definition of done (acceptance evidence)

- Real Dock row opens correct detail.
- Detail shows message/command/output/request-ish event summaries.
- Live/stale state is visible.
- Phase 3 Dock still works.

## 0.5 Key invariants (fix immediately if violated)

- Notification reading does not stop after initial requests.
- Events are normalized before UI.
- Host/thread identity is preserved.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct thread identity.
2. Reliable event rendering.
3. Live update correctness.
4. Simple readable detail UI.

## 1.2 Constraints

- Stored thread browsing and continuation use different methods.
- Notifications are connection-scoped.

## 1.3 Architectural principles (rules we will enforce)

- `ThreadDetailStore` owns open-thread lifecycle.
- `AppServerClient` continues to own protocol.
- UI never answers requests in this phase.

## 1.4 Known tradeoffs (explicit)

- Command output can be collapsed.
- Rich diff rendering waits.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Phase 3 gives a single-host Dock backed by real sessions.

## 2.2 What’s broken / missing (concrete)

Rows cannot be inspected, so the app cannot yet tell the user what a session is
actually doing.

## 2.3 Constraints implied by the problem

Read/live detail should come before text control.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- List/detail navigation pattern — adopt standard SwiftUI navigation from row
  identity into detail state.
- Streaming event merge pattern — normalize notifications into event state
  before rendering.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` — `thread/read`,
    `thread/resume`, `thread/turns/list`, item notifications, and
    connection-scoped subscriptions.
  - `../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png` — detail UI
    anchor.
- Canonical path / owner to reuse:
  - Phase 1 client for methods/notifications; new `ThreadDetailStore` for open
    thread state.
- Adjacent surfaces tied to the same contract family:
  - Phase 5 composer and request cards extend this same detail store.
  - Phase 6 host identity must keep detail navigation stable.
- Compatibility posture:
  - Preserve app-server thread semantics; do not fake continuation from
    `thread/list`.
- Existing patterns to reuse:
  - Phase 2 DTO/domain mapping style.
- Prompt surfaces / agent contract to reuse:
  - Codex app-server events are the agent/runtime contract.
- Native model or agent capabilities to lean on:
  - None.
- Existing grounding / tool / file exposure:
  - Protocol ramp-up method/event map.
- Duplicate or drifting paths relevant to this change:
  - Avoid a second notification reader in detail UI.
- Capability-first opportunities before new tooling:
  - Use protocol notifications before polling-only fallbacks.
- Behavior-preservation signals already available:
  - Phase 1-3 tests/build remain green.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- Dock list exists by Phase 3; no detail store/view or thread-read methods.
## Control paths (runtime)
- Row data is visible; row tap cannot inspect a thread.
## Object model + key abstractions
- `SessionSummary` has host/thread identity; no `ThreadEvent`.
## Observability + failure behavior today
- No detail loading/stale/error state.
## UI surfaces (ASCII mockups, if UI work)
- Session detail v2 mockup anchors layout.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `AppServerMethods.swift` — add thread read/resume/turn list wrappers.
- `Models/ThreadEvent.swift`.
- `State/ThreadDetailStore.swift`.
- `Features/Session/SessionDetailView.swift`.
- `CodexDockTests/ThreadDetailStoreTests.swift`.
## Control paths (future)
1. Dock row tap passes host/thread identity.
2. Store reads/resumes thread.
3. Notifications merge into event list.
4. View renders events and live/stale state.
## Object model + abstractions (future)
- `ThreadEvent`, `ThreadDetailStore`, `LiveSubscriptionState`.
## Invariants and boundaries
- One notification reader, normalized events before UI.
## UI surfaces (ASCII mockups, if UI work)
- Direct anchor: [Session detail](../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png).
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Protocol | `AppServerMethods.swift` | thread read/resume | Missing | Add wrappers | Open thread | typed methods | Unit |
| State | `ThreadDetailStore.swift` | detail lifecycle | Missing | Own read/live state | Detail owner | observable state | Unit |
| Events | `ThreadEvent.swift` | event model | Missing | Normalize messages/commands/output | UI clarity | event enum | Unit |
| UI | `SessionDetailView.swift` | detail screen | Missing | Render event stream | Inspect work | SwiftUI | Manual |
## Migration notes
* Canonical owner path / shared code path: `ThreadDetailStore` over `AppServerClient`.
* Deprecated APIs (if any): none.
* Delete list: none.
* Adjacent surfaces tied to the same contract family: Phase 5 composer/cards.
* Compatibility posture / cutover plan: preserve app-server thread semantics.
* Capability-replacing harnesses to delete or justify: none.
* Live docs/comments/instructions to update or delete: none.
* Behavior-preservation signals for refactors: Phase 1-3 tests/build.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Detail state | `ThreadDetailStore` | one open-thread owner | Prevent duplicated event merge logic | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: this phase is read/live detail only. Composer send, request-card
  responses, and voice remain later phases.
- Adjacent-surface check: `ThreadDetailStore` becomes the single open-thread
  owner so Phase 5 can add control without duplicating event merge logic.
- Failure posture: read/resume errors, stale live subscription, and unsupported
  event shapes remain visible in detail state.
- Depth-first proof: row-to-detail routing must work from a real Dock row before
  live updates are counted as complete.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: row-to-detail route

Work: Add stable navigation from a real Dock row into a thread detail state.

Checklist (must all be done):
- Dock row tap passes host id and backend/thread id.
- Detail route rejects missing or stale identity visibly.
- Phase 3 Dock still loads after navigation is added.

Exit criteria (all required):
- A real Dock row opens the matching detail screen.

## Implementation slice 2: read/resume and event normalization

Work: Add thread read/resume wrappers, event DTOs, and app-facing `ThreadEvent`
projection.

Checklist (must all be done):
- `AppServerMethods.swift` exposes typed thread read/resume methods.
- `ThreadDetailStore` owns loading/error/event state.
- Events normalize message, command, output, and request-like shapes before UI.
- Unsupported event shapes remain visible as unknown events.

Exit criteria (all required):
- Stored thread events render without raw JSON in the view.
- Read/resume failures surface in detail state.

## Implementation slice 3: live notification merge

Work: Keep the open detail subscribed to connection notifications and merge
updates into the current thread.

Checklist (must all be done):
- Notification loop continues after initial read.
- Store ignores notifications for other host/thread ids.
- Live/stale state is visible.
- Layout follows [Session detail](../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png).

Exit criteria (all required):
- A local/live proof shows the open detail updating after initial load.
- Phase 5 can extend the same store for composer and cards.
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
- Run row-routing tests for host/thread identity.
- Run event normalization tests for message, command, output, request-like, and
  unknown event shapes.
- Run store tests for read/resume success, failure, live updates, and stale
  state.
- Manual/screenshot check against [Session detail](../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png).

## Cold-read consistency checks
- Composer send and request responses remain Phase 5.
- Notification ownership stays in the client/store boundary, not the view.
- Detail state gives Phase 5 one place to extend.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Local simulator/device development after Dock works.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Open a real Dock row and observe a live or stored session.

# 10) Decision Log (append-only)

## 2026-05-27 - Split read/live from send

Context
: Thread control is too large for one step.

Options
: Combine detail read, live updates, and send; or prove read/live first.

Decision
: This sub-plan proves read/live only.

Consequences
: Text control becomes the next smaller sub-plan.
