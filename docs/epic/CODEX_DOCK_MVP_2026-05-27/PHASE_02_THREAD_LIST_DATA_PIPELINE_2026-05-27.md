---
title: "Codex Dock - Thread List Data Pipeline - Architecture Plan"
date: 2026-05-27
status: complete
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: new_system
related:
  - ../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - ../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
---

# TL;DR

- Outcome: Add `thread/list` and normalize host-scoped session summaries before
  any Dock UI depends on them.
- Problem: The Dock should render a real data model, not raw protocol JSON or
  mock rows.
- Approach: Extend the JSON-RPC client with typed `thread/list`, DTO decoding,
  normalized summaries, and test/dev diagnostics.
- Plan: Add method wrapper, map payloads, prove status/repo/branch extraction,
  and keep the output UI-independent.
- Non-negotiables: preserve Phase 1 client boundary, no UI dependency, no
  AIMGR, and no static production data.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-28
Verdict (code): COMPLETE
Manual QA: complete (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None. Phase 2 is complete.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Evidence checked
- Stage gate: `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_02_THREAD_LIST_DATA_PIPELINE_2026-05-27.md` returned `READY next=implement-loop`.
- SwiftPM/macOS fixture proof: `swift test` passed 24 tests, with live endpoint
  tests skipped when no endpoint env was set.
- SwiftPM/macOS live proof:
  `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4500 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=<temp-token-file> CODEX_DOCK_REAL_HOST_ID=Amir-M5 swift test`
  passed 24 tests with only the loopback-only smoke test skipped.
- iPhone simulator live proof:
  `xcodebuild test -scheme codex-client -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91'`
  passed on the booted `iPhone 17` simulator after simulator env was set for
  the same real `Amir-M5` endpoint.
- Real host proof: started a real Codex app-server on `Amir-M5` with
  `codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file <temp-token-file>`.
- Reachability proof: `curl -i http://192.168.50.117:4500/readyz` returned
  `HTTP/1.1 200 OK`.
- Thread-list proof: macOS SwiftPM and the `iPhone 17` simulator both completed
  `initialize`/`initialized`, called `thread/list`, decoded the live response,
  and mapped it into host-scoped `SessionSummary` values against
  `ws://192.168.50.117:4500`.
- Scope check: implementation added app-server DTOs, a typed `thread/list`
  client method, app-facing `SessionSummary` models, mapper tests, and live
  diagnostic tests only. No Dock UI, thread detail, send/control, archive,
  voice, AIMGR, relay, or production static data was added.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- None for Phase 2.
<!-- arch_skill:block:implementation_audit:end -->

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
  "digest": "sha256:ffa8c9747a638ea5cef27abc19f8ee09f0d34db75440c40232e0804827b13701",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:15f7193560637d99fbe918c7901bd98ddc8e88fcae94169f06167fcaef539157",
      "completed_at": "2026-05-28T00:25:39Z",
      "doc_hash_after": "sha256:86e23469ade68858b47bb7d652fc2bd15729597071ca32979ce5099e943bb3e3"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:86e23469ade68858b47bb7d652fc2bd15729597071ca32979ce5099e943bb3e3",
      "completed_at": "2026-05-28T00:27:30Z",
      "doc_hash_after": "sha256:a2572e0045dcabbb248b01da294bf3f58142f9f82eed0e0b50d0e12dfd99ba5d"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:a2572e0045dcabbb248b01da294bf3f58142f9f82eed0e0b50d0e12dfd99ba5d",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:817e709c0145795ab92201ae7c4afc3a6b29aa0a4cf5628888d9f6b4bb5ad84d"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:817e709c0145795ab92201ae7c4afc3a6b29aa0a4cf5628888d9f6b4bb5ad84d",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:834c7ee89f83d7b1df3a5e793a07375609f02bc7331087020c324c364e1821ec"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:33Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:834c7ee89f83d7b1df3a5e793a07375609f02bc7331087020c324c364e1821ec",
      "completed_at": "2026-05-28T00:32:10Z",
      "doc_hash_after": "sha256:905e5da25a5563e9ae7d11be6e37243cc0dbe797159e25ce13e351373d3bdea1"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

A focused test or diagnostic can call `thread/list` through the Phase 1 client
and produce normalized `SessionSummary` values keyed by host id.

## 0.2 In scope

- `thread/list` wrapper.
- DTOs for thread-list response shape.
- `SessionSummary` normalization.
- Status/repo/branch/last-event projection where data is available.
- Tests with fixture and/or live app-server payloads.

## 0.3 Out of scope

- SwiftUI Dock rendering.
- Multi-host fan-out beyond carrying host id in the model.
- Thread detail, send, archive, voice, AIMGR.

## 0.4 Definition of done (acceptance evidence)

- `thread/list` can be called through `AppServerClient`.
- Response data maps into `SessionSummary`.
- Mapper handles missing repo/branch data without dropping the thread.
- Tests prove host id stays attached.

## 0.5 Key invariants (fix immediately if violated)

- Raw app-server payloads do not leak into future views.
- Mapping failures are visible.
- Host id is part of every summary.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Trustworthy normalized data.
2. Preserve Phase 1 protocol ownership.
3. Handle incomplete session metadata.
4. Keep UI out until Phase 3.

## 1.2 Constraints

- Session data may lack branch or repo fields.
- `thread/list` browses stored sessions but does not load them for continuation.
- Later phases need host-scoped identity.

## 1.3 Architectural principles (rules we will enforce)

- DTOs are protocol-facing; `SessionSummary` is app-facing.
- Missing optional data becomes explicit unknown state.
- Mapping is testable without SwiftUI.

## 1.4 Known tradeoffs (explicit)

- First status derivation can be conservative.
- Detailed turn/event data waits for thread detail phases.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Phase 1 provides the connection and handshake. Before this phase, no session
data pipeline existed.

## 2.2 What’s broken / missing (concrete)

Without normalized summaries, the Dock would either use raw protocol payloads or
demo rows.

## 2.3 Constraints implied by the problem

Build a data pipeline before product UI.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- DTO-to-domain mapping pattern — adopt a protocol-facing DTO layer and an
  app-facing summary model instead of using raw JSON in UI/state.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` — `thread/list` browses
    sessions; `thread/read`/`thread/resume` are separate continuation surfaces.
  - `../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` — Dock rows need host,
    repo/cwd, branch, status, last activity, and a short event summary.
- Canonical path / owner to reuse:
  - Phase 1 `AppServerClient` owns the method call; new mapper owns
    `SessionSummary` projection.
- Adjacent surfaces tied to the same contract family:
  - Phase 3 Dock consumes `SessionSummary`.
  - Phase 6 multi-host store widens the host-scoped identity.
- Compatibility posture:
  - Preserve app-server payload shape and tolerate optional/missing fields.
- Existing patterns to reuse:
  - Phase 1 typed method wrapper pattern.
- Prompt surfaces / agent contract to reuse:
  - Not agent-backed.
- Native model or agent capabilities to lean on:
  - None.
- Existing grounding / tool / file exposure:
  - Protocol ramp-up doc plus live/fixture thread-list payloads.
- Duplicate or drifting paths relevant to this change:
  - Avoid separate row mappers per future screen.
- Capability-first opportunities before new tooling:
  - Use `thread/list` directly before adding a cache or bridge.
- Behavior-preservation signals already available:
  - Phase 1 handshake tests/checks must remain green.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- Phase 1 will provide the client and handshake; no thread-list DTOs/mappers exist.
## Control paths (runtime)
- Handshake can be proven, but no data method is available.
## Object model + key abstractions
- No `SessionSummary` or thread-list DTO exists.
## Observability + failure behavior today
- Method failures would be generic connection/protocol failures only.
## UI surfaces (ASCII mockups, if UI work)
- No UI in scope; data feeds Phase 3.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `CodexDock/AppServer/AppServerMethods.swift` — add `thread/list`.
- `CodexDock/AppServer/ThreadListDTO.swift` — protocol response DTOs.
- `CodexDock/Models/SessionSummary.swift` — app-facing row model.
- `CodexDock/Models/SessionSummaryMapper.swift` — DTO-to-domain mapper.
- `CodexDockTests/ThreadListMappingTests.swift`.
## Control paths (future)
1. Handshake succeeds.
2. Client calls `thread/list`.
3. Mapper produces host-scoped `SessionSummary` values.
4. Diagnostic/test prints or asserts normalized rows.
## Object model + abstractions (future)
- `ThreadListResponseDTO`, `SessionSummary`, `SessionStatus`, `HostScopedThreadID`.
## Invariants and boundaries
- DTOs stay protocol-facing; summaries are app-facing.
## UI surfaces (ASCII mockups, if UI work)
- None; Phase 3 consumes summaries.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Protocol | `AppServerMethods.swift` | `threadList` | Missing | Add typed wrapper | First data method | async list method | Unit |
| DTO | `ThreadListDTO.swift` | response structs | Missing | Decode app-server payload | Preserve protocol boundary | DTOs | Unit |
| Domain | `SessionSummary.swift` | row model | Missing | Add host-scoped summary | Feed UI later | app-facing model | Unit |
| Mapping | `SessionSummaryMapper.swift` | mapper | Missing | Handle missing repo/branch/status | Robust rows | mapper API | Unit |
## Migration notes
* Canonical owner path / shared code path: Phase 1 client plus summary mapper.
* Deprecated APIs (if any): none.
* Delete list: none.
* Adjacent surfaces tied to the same contract family: Dock, multi-host, archive.
* Compatibility posture / cutover plan: preserve app-server payload; tolerate optional fields.
* Capability-replacing harnesses to delete or justify: none.
* Live docs/comments/instructions to update or delete: none.
* Behavior-preservation signals for refactors: Phase 1 tests stay green.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Mapping | `SessionSummaryMapper` | one row mapper | Prevent UI-specific duplicate mapping | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: this phase owns `thread/list` and `SessionSummary` projection only;
  Dock rendering waits for Phase 3.
- Adjacent-surface check: every summary must carry host identity so Phase 3 and
  Phase 6 do not need a second identity model.
- Failure posture: malformed or partial rows are mapped into visible unknown/error
  state without dropping the whole list.
- Depth-first proof: diagnostic/test output is enough when it proves real or
  fixture app-server payloads normalize consistently.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: typed `thread/list` method

Status: COMPLETE

Work: Extend the Phase 1 client with the first real data method while preserving
the protocol boundary.

Checklist (must all be done):
- Add a typed `thread/list` wrapper in `AppServerMethods.swift`.
- Add fixture/live diagnostic coverage for success and method-level failure.
- Keep the API UI-independent.

Exit criteria (all required):
- `thread/list` can be called through `AppServerClient`.
- Phase 1 handshake checks still pass.

Completed work:
- Added `AppServerMethods.threadList` and `AppServerClient.threadList(...)`.
- Added success, method-error, and phone-reachable real-host `thread/list`
  coverage through the Phase 1 client boundary.

## Implementation slice 2: DTO decoding and `SessionSummary`

Status: COMPLETE

Work: Add protocol DTOs and app-facing summary models keyed by host id.

Checklist (must all be done):
- DTOs decode the app-server list payload without leaking into views.
- `SessionSummary` includes host id, backend/thread id, display title, status,
  repo/cwd, branch, last activity, and short event summary when present.
- Missing repo/branch/status becomes explicit unknown state.

Exit criteria (all required):
- Mapping tests cover complete and sparse payloads.
- No mapper drops a valid thread only because optional metadata is absent.

Completed work:
- Added protocol-facing `ThreadListResponseDTO`, `ThreadDTO`, params, status,
  active-flag, git-info, sort, and filter DTOs.
- Added app-facing `HostScopedThreadID`, `SessionSummary`, `SessionStatus`,
  `SessionActiveFlag`, and `SessionSummaryText`.
- Added `SessionSummaryMapper` with explicit unknown states and scoped mapping
  failures.

## Implementation slice 3: data diagnostic proof

Status: COMPLETE

Work: Produce a focused test/dev proof that prints or asserts normalized rows.

Checklist (must all be done):
- Fixture or live app-server payload maps into stable summaries.
- Host id remains attached through all mapping.
- Mapping errors are visible and scoped to the failing row/payload.

Exit criteria (all required):
- Phase 3 can consume `SessionSummary` without raw protocol knowledge.

Completed work:
- Added fixture mapping tests for complete, sparse, malformed, and unknown
  status/flag payloads.
- Added live `thread/list` proof that maps the real app-server payload into
  host-scoped `SessionSummary` rows on macOS and the `iPhone 17` simulator.
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
- Run Phase 1 handshake/client tests unchanged.
- Run `thread/list` method tests with success and method-error fixtures.
- Run mapping tests for complete, sparse, and malformed payloads.
- Verify every `SessionSummary` carries host id and backend/thread identity.

## Cold-read consistency checks
- Scope remains UI-independent data plumbing.
- Missing repo/branch/status is explicit unknown state, not row loss.
- Phase 3 can consume summaries without knowing DTOs or JSON-RPC envelopes.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Developer-only data proof.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Run the thread-list diagnostic/test after Phase 1 handshake is available.

# 10) Decision Log (append-only)

## 2026-05-27 - Keep data before UI

Context
: User asked for depth-first build-up with JSON-RPC as the most fundamental
  proof.

Options
: Render Dock first with mock rows, or build normalized `thread/list` data
  first.

Decision
: Build normalized `thread/list` data first.

Consequences
: Dock UI starts from real app-facing summaries.

## 2026-05-28 - Phase 2 implementation completed

Context
: Phase 2 needed to prove the first real data method and normalized summaries
  before any Dock UI could depend on session rows.

Decision
: Implemented `thread/list` directly through `AppServerClient`, kept app-server
  DTOs protocol-facing, and added `SessionSummary` as the app-facing data model
  for Phase 3.

Consequences
: Phase 3 can consume `SessionSummary` without raw JSON-RPC or protocol DTO
  knowledge. Real-host proof remains on `Amir-M5`; `Home` stays planned for the
  later multi-host phase.
