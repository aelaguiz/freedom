---
title: "Codex Dock - Text Control Request Cards - Architecture Plan"
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
  - ../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png
---

# TL;DR

- Outcome: Add the first phone-side control loop: type text into the open
  thread and answer minimal supported request cards.
- Problem: Read-only detail still leaves the user unable to steer or unblock a
  Codex session.
- Approach: Extend the proven thread detail store with composer state, turn
  methods, and generic request cards.
- Plan: Add typed send/steer first, then minimal cards for supported
  server-initiated requests.
- Non-negotiables: minimal approvals only, no permission product, no voice, no
  AIMGR.

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
  "digest": "sha256:6ff45f2e8a7d28fd3709aa73077102074203d3024a461d1247c6dbcecfa459a9",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:3aa5bf88e9fdd8f7bb0159e08b8d425f0a0bdafb56664c41a0dfc4b71e3a4cb7",
      "completed_at": "2026-05-28T00:25:39Z",
      "doc_hash_after": "sha256:9c426c0d5d5471b459f0c594e58e349793dd90de140c272b8049b9b63247d6e5"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:9c426c0d5d5471b459f0c594e58e349793dd90de140c272b8049b9b63247d6e5",
      "completed_at": "2026-05-28T00:27:30Z",
      "doc_hash_after": "sha256:e4f538655536ef5933f67a48982c63afcd07751b259bba545e735c76536e750c"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e4f538655536ef5933f67a48982c63afcd07751b259bba545e735c76536e750c",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:cfa87b974a3425a67f2d15db4b3e149e8fb6c87b693a5898480ceabdeb152aba"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:cfa87b974a3425a67f2d15db4b3e149e8fb6c87b693a5898480ceabdeb152aba",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:b2a582a33cded29b06d20b9d020dc8b71ba413239e8323746a987079c36af4f2"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:33Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:b2a582a33cded29b06d20b9d020dc8b71ba413239e8323746a987079c36af4f2",
      "completed_at": "2026-05-28T00:32:11Z",
      "doc_hash_after": "sha256:61a9c0d262a82dc62ba4b33a4f6c28416e760816bd3f083687b4f7f30440b2bd"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

The user can send typed text to a real open thread through the app-server and
can answer supported server-initiated request cards while unsupported requests
stay visible.

## 0.2 In scope

- Composer state.
- `turn/start` / `turn/steer` where protocol state allows.
- Send error preservation.
- Minimal command/file/permission/user-input/MCP elicitation request cards.

## 0.3 Out of scope

- Voice transcription.
- Full MCP custom forms.
- Full permission-management system.
- AIMGR.

## 0.4 Definition of done (acceptance evidence)

- Typed text sends through app-server.
- Failed send preserves user text.
- Supported cards can respond.
- Unsupported request methods render "Needs desktop".

## 0.5 Key invariants (fix immediately if violated)

- Request cards are not silently ignored.
- Composer does not guess unsafe turn state.
- Approval UI remains small.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct send semantics.
2. Preserve user text on failure.
3. Minimal request compatibility.
4. Avoid overbuilt permissions.

## 1.2 Constraints

- User usually runs skipped permissions, but API can still emit requests.
- Server-initiated requests can block progress if ignored.

## 1.3 Architectural principles (rules we will enforce)

- Same composer path later receives voice transcripts.
- Request cards preserve request id/method.
- Unsupported means visible, not dropped.

## 1.4 Known tradeoffs (explicit)

- Cards can be generic.
- Rich command/file detail waits.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Phase 4 can open and observe a thread.

## 2.2 What’s broken / missing (concrete)

The phone cannot yet steer a turn or respond to supported requests.

## 2.3 Constraints implied by the problem

Add text/manual control before voice.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- State-aware composer pattern — send actions derive from runtime turn state,
  preserve user text on failure, and avoid hidden retries.
- Generic request-card pattern — support common request actions without creating
  a permission-management product.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` — `turn/start`,
    `turn/steer`, `turn/interrupt`, and request methods.
  - `../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` — approvals are minimal
    because the user's normal workflow skips permissions.
  - `../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png` and
    `../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png` — visual
    anchors for composer/cards.
- Canonical path / owner to reuse:
  - Phase 4 `ThreadDetailStore` owns composer and request-card state.
- Adjacent surfaces tied to the same contract family:
  - Phase 8 voice inserts text into this composer.
  - Needs-me filter in Phase 6 surfaces request/card attention.
- Compatibility posture:
  - Preserve app-server request contracts and fail visibly for unsupported
    request methods.
- Existing patterns to reuse:
  - Phase 4 event normalization and state store.
- Prompt surfaces / agent contract to reuse:
  - Not a prompt change; this is app-server control.
- Native model or agent capabilities to lean on:
  - None.
- Existing grounding / tool / file exposure:
  - Protocol request-method inventory.
- Duplicate or drifting paths relevant to this change:
  - Avoid separate send paths for typed text and later voice.
- Capability-first opportunities before new tooling:
  - Use app-server turn/request methods directly.
- Behavior-preservation signals already available:
  - Phase 4 detail/read tests remain green.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- Thread detail exists by Phase 4; composer/request models do not.
## Control paths (runtime)
- User can read/watch a thread but cannot steer or answer requests.
## Object model + key abstractions
- No `ComposerState` or `ServerRequestCard`.
## Observability + failure behavior today
- No send error preservation or unsupported request display.
## UI surfaces (ASCII mockups, if UI work)
- Session detail and Needs-me mockups anchor composer/cards.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `AppServerMethods.swift` — add turn and request-response wrappers.
- `Models/ServerRequestCard.swift`.
- `State/ThreadDetailStore.swift` — extend with composer/cards.
- `Features/Session/ComposerView.swift`.
- `Features/Session/RequestCardView.swift`.
## Control paths (future)
1. User types text in composer.
2. Store selects valid turn method and sends.
3. Request notifications render generic cards.
4. Supported cards respond by request id; unsupported show Needs desktop.
## Object model + abstractions (future)
- `ComposerState`, `ServerRequestCard`, `RequestAction`.
## Invariants and boundaries
- One composer send path; unsupported requests visible.
## UI surfaces (ASCII mockups, if UI work)
- Anchors: [Session detail](../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png), [Needs-me filter](../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png).
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Protocol | `AppServerMethods.swift` | turn methods | Missing | Add start/steer/interrupt where supported | Text control | typed methods | Unit |
| State | `ThreadDetailStore.swift` | composer | Missing | Add send state/error preservation | User control | composer state | Unit |
| Requests | `ServerRequestCard.swift` | cards | Missing | Model supported/unsupported requests | Avoid stalls | card model | Unit |
| UI | `ComposerView.swift` / `RequestCardView.swift` | controls | Missing | Render composer/cards | User actions | SwiftUI | Manual |
## Migration notes
* Canonical owner path / shared code path: extend `ThreadDetailStore`.
* Deprecated APIs (if any): none.
* Delete list: none.
* Adjacent surfaces tied to the same contract family: Phase 8 voice composer.
* Compatibility posture / cutover plan: preserve app-server request contracts.
* Capability-replacing harnesses to delete or justify: none.
* Live docs/comments/instructions to update or delete: none.
* Behavior-preservation signals for refactors: Phase 4 detail tests.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Composer | `ThreadDetailStore` | one send path | Later voice reuses it | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: this phase adds typed text control and minimal request cards only;
  voice, full permission management, and AIMGR stay out.
- Adjacent-surface check: voice in Phase 8 must reuse the same composer state,
  so this phase must not bake typed-only assumptions into send logic.
- Failure posture: failed sends preserve draft text, unsupported requests show
  "Needs desktop", and request ids are never discarded.
- Depth-first proof: first prove one valid text send, then add generic supported
  card responses.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: typed composer send

Work: Extend `ThreadDetailStore` with composer state and app-server turn
methods.

Checklist (must all be done):
- Composer tracks draft text, sending state, and last send error.
- Store chooses `turn/start` or `turn/steer` from known runtime state instead of
  guessing unsafe behavior.
- Failed send preserves draft text.
- UI follows the composer area in [Session detail](../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png).

Exit criteria (all required):
- User can send a typed instruction through app-server.
- Send failure keeps the text editable.

## Implementation slice 2: request-card model and notifications

Work: Normalize server-initiated requests into card state.

Checklist (must all be done):
- Request cards preserve request id, method, summary, and supported/unsupported
  status.
- Supported cards expose only minimal approve/respond controls.
- Unsupported methods render "Needs desktop" and are counted for attention.

Exit criteria (all required):
- Request notifications appear in detail without being silently dropped.

## Implementation slice 3: minimal supported card responses

Work: Wire supported request cards to app-server responses.

Checklist (must all be done):
- Supported command/file/permission/user-input/MCP elicitation requests can send
  a response where the API supports it.
- Response errors remain attached to the card.
- Needs-me Dock state can derive from request/card attention, matching
  [Needs-me filter](../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png).

Exit criteria (all required):
- A supported request can be answered.
- Unsupported requests stay visible and do not block the UI thread.
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
- Run composer tests for draft preservation, sending state, and send failure.
- Run app-server method tests for typed turn start/steer behavior.
- Run request-card normalization tests for supported and unsupported methods.
- Manual/screenshot check against [Session detail](../../mockups/codex-dock-2026-05-27-v2/03-session-detail.png)
  and [Needs-me filter](../../mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png).

## Cold-read consistency checks
- Approval UI is intentionally minimal because skipped permissions are the
  user's normal workflow, while API request support still exists.
- Voice remains out but has a clear composer reuse point.
- Unsupported request methods are visible, not silently ignored.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Local control-loop development after read/live detail exists.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Open a real thread and send a short typed instruction.

# 10) Decision Log (append-only)

## 2026-05-27 - Keep approvals minimal

Context
: User normally runs skipped permissions but the app-server API supports
  requests.

Options
: Build a permission product, or render minimal cards.

Decision
: Render minimal cards only.

Consequences
: No policy editor or broad approval system enters V1.
