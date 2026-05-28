---
title: "Codex Dock - JSON-RPC Handshake Foundation - Architecture Plan"
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

- Outcome: Prove the fundamental runtime seam before UI: a Swift client can
  connect to Codex app-server over WebSocket JSON-RPC, complete
  `initialize`/`initialized`, and report connection state.
- Problem: Starting with a Dock shell hides the hardest unknown. The app is only
  real once JSON-RPC communication works.
- Approach: Build a small protocol module with envelope encoding, request id
  correlation, WebSocket lifecycle, and a test/development handshake path.
- Plan: First create testable envelopes, then connection lifecycle, then
  initialize/initialized, then visible diagnostic evidence.
- Non-negotiables: no product UI dependency, no AIMGR, no custom proxy, and no
  raw JSON-RPC in future SwiftUI views.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-28
Verdict (code): COMPLETE
Manual QA: n/a (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Evidence checked
- Stage gate: `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_01_JSON_RPC_HANDSHAKE_FOUNDATION_2026-05-27.md` returned `READY next=implement-loop`.
- SwiftPM/macOS: `swift test` passed 12 tests.
- iPhone simulator: `xcodebuild test -scheme codex-client -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91'` passed on the booted `iPhone 17` simulator.
- Scope check: implementation contains JSON-RPC envelope/client/handshake code and tests only; no `thread/list`, Dock UI, AIMGR, archive, voice, or later-phase product behavior was implemented.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- Real host app-server smoke testing against `Amir-M5` or `Home` remains optional setup work outside the Phase 1 code-completeness gate because this phase permits a locally simulated handshake proof.
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
  "digest": "sha256:a1c53c65a5a5367753e1b3efd012138a37d88c305ab847822b1a6cfdfe5b9d91",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:e817f175b3cd91a51bfceb6edc789a3494577d3f38cf747aebb8b907bab79edf",
      "completed_at": "2026-05-28T00:25:38Z",
      "doc_hash_after": "sha256:2056cacd7fc8bb5875bacad221ca3f8a7b32e0c1440ca6b4e81aadc3190c9b94"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:2056cacd7fc8bb5875bacad221ca3f8a7b32e0c1440ca6b4e81aadc3190c9b94",
      "completed_at": "2026-05-28T00:27:29Z",
      "doc_hash_after": "sha256:5abcf17fec90918ff39181b491acead1cf367d0be9e84257becc8aa0b2c3fe6b"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:5abcf17fec90918ff39181b491acead1cf367d0be9e84257becc8aa0b2c3fe6b",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:460dcb9ec2e6b9cdc7baad87a699bad76f72fef649843e83dff675c3aaa772da"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:460dcb9ec2e6b9cdc7baad87a699bad76f72fef649843e83dff675c3aaa772da",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:a6c102e1edddcd9195ddbc1f4ac6dd85362120e8f8a9b107b0fcfceab3e89675"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:32Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:a6c102e1edddcd9195ddbc1f4ac6dd85362120e8f8a9b107b0fcfceab3e89675",
      "completed_at": "2026-05-28T00:32:10Z",
      "doc_hash_after": "sha256:62a894b84f3d8e0654ad2806da2c1b77b5a42e6a2e6d49374ea12ea228f40d04"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

A developer can run a focused test or local dev diagnostic that connects to a
Codex app-server endpoint, completes the initialization handshake, and surfaces
connected/offline/error state without any product UI.

## 0.2 In scope

- Protocol module or Swift package inside the future app tree.
- JSON-RPC envelope types.
- Request id correlation.
- WebSocket connect/read/send lifecycle.
- `initialize` and `initialized`.
- Diagnostic/test evidence for success and failure.

## 0.3 Out of scope

- `thread/list`.
- SwiftUI Dock or app navigation.
- Thread detail, text send, archive, voice, multi-host.
- AI Manager / AIMGR.

## 0.4 Definition of done (acceptance evidence)

- Protocol envelope unit tests pass.
- A test transport proves request/response matching.
- A real or locally simulated WebSocket path completes the handshake.
- Failures are represented as explicit connection states.

## 0.5 Key invariants (fix immediately if violated)

- Protocol code is isolated behind `AppServerClient`.
- No SwiftUI view constructs raw JSON-RPC.
- Unsupported connection failures fail loud.
- No bridge daemon is introduced for this proof.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Real JSON-RPC handshake proof.
2. Testable transport boundary.
3. Small API that later phases can reuse.
4. No UI breadth before protocol proof.

## 1.2 Constraints

- App-server uses WebSocket-framed JSON-RPC, not raw JSONL.
- The repo is new and can choose a clean Swift layout.
- The protocol client must support later request and notification work.

## 1.3 Architectural principles (rules we will enforce)

- One JSON-RPC owner.
- Typed method wrappers sit above generic envelopes.
- Connection state is explicit.
- No runtime fallback or shim.

## 1.4 Known tradeoffs (explicit)

- This phase can be test/diagnostic-only with no product screen.
- It may create the minimum project/package layout needed for protocol tests,
  leaving app shell decisions to Phase 3.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The repo has docs and mockups, but no app code. The app-server protocol is
documented in `../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md`.

## 2.2 What’s broken / missing (concrete)

No client exists that can talk to Codex app-server. UI work before this would
risk building a shell around an unproven transport.

## 2.3 Constraints implied by the problem

The first implementation proof must be JSON-RPC communication itself.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- WebSocket JSON-RPC client pattern — adopt a single transport boundary that
  owns request ids, response matching, and notification reads.
- Swift concurrency / URLSessionWebSocketTask — adopt platform primitives first;
  do not introduce a custom bridge or daemon for the first proof.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` — app-server uses
    WebSocket-framed JSON-RPC, starts with `initialize` then `initialized`, and
    requires clients to keep reading notifications.
  - `../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` — V1 excludes AIMGR and
    needs a mobile client over Codex app-server.
- Canonical path / owner to reuse:
  - New `AppServerClient` module owns all JSON-RPC framing and transport.
- Adjacent surfaces tied to the same contract family:
  - Phase 2 extends this client with `thread/list`.
  - Phase 4 and Phase 5 depend on the same notification/request stream.
- Compatibility posture:
  - Preserve existing app-server protocol; no server-side protocol changes.
- Existing patterns to reuse:
  - None in app code because the repo has no implementation yet.
- Prompt surfaces / agent contract to reuse:
  - Not agent-backed; this is protocol transport.
- Native model or agent capabilities to lean on:
  - None.
- Existing grounding / tool / file exposure:
  - Protocol ramp-up doc and current app-server endpoints.
- Duplicate or drifting paths relevant to this change:
  - None yet; prevent future drift by making one client owner.
- Capability-first opportunities before new tooling:
  - Use the app-server protocol directly before considering any host bridge.
- Behavior-preservation signals already available:
  - New behavior; use envelope tests, test transport, and local handshake check.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- Planning docs and mockups exist; no Swift protocol module exists.
## Control paths (runtime)
- No runtime path exists yet.
## Object model + key abstractions
- Protocol concepts exist only in docs: JSON-RPC request/response,
  notification, initialize lifecycle.
## Observability + failure behavior today
- No connection state or diagnostics exist.
## UI surfaces (ASCII mockups, if UI work)
- No UI is in scope for this phase.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `CodexDock/AppServer/AppServerClient.swift` — single JSON-RPC transport owner.
- `CodexDock/AppServer/JSONRPC.swift` — envelopes, ids, errors.
- `CodexDock/AppServer/AppServerMethods.swift` — `initialize`/`initialized`.
- `CodexDockTests/AppServerClientTests.swift` — envelope and handshake tests.
## Control paths (future)
1. Diagnostic/test creates a host endpoint.
2. `AppServerClient` opens WebSocket.
3. Client sends `initialize`, receives result, sends `initialized`.
4. Client exposes connected/offline/error state.
## Object model + abstractions (future)
- `JSONRPCRequest`, `JSONRPCResponse`, `JSONRPCNotification`,
  `AppServerClient`, `AppServerConnectionState`.
## Invariants and boundaries
- One protocol owner, no raw JSON in views, no host bridge.
## UI surfaces (ASCII mockups, if UI work)
- None; downstream UI starts in Phase 3.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Protocol | `CodexDock/AppServer/JSONRPC.swift` | envelopes | Missing | Add Codable request/response/notification | Protocol foundation | Typed JSON-RPC | Unit |
| Protocol | `CodexDock/AppServer/AppServerClient.swift` | client | Missing | Add WebSocket send/read and id matching | Highest-risk seam | async client API | Unit/integration |
| Methods | `CodexDock/AppServer/AppServerMethods.swift` | handshake | Missing | Add initialize/initialized | Required app-server lifecycle | typed method wrappers | Unit/integration |
| Tests | `CodexDockTests/AppServerClientTests.swift` | protocol tests | Missing | Add test transport and handshake tests | Proves first phase | test transport | Unit |
## Migration notes
* Canonical owner path / shared code path: `AppServerClient`.
* Deprecated APIs (if any): none.
* Delete list: none.
* Adjacent surfaces tied to the same contract family: all later app-server methods.
* Compatibility posture / cutover plan: preserve app-server protocol.
* Capability-replacing harnesses to delete or justify: none.
* Live docs/comments/instructions to update or delete: none.
* Behavior-preservation signals for refactors: new code; protocol tests.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Protocol | `AppServerClient` | single transport owner | Prevent duplicate JSON-RPC callers | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: this phase stops at protocol handshake proof. It must not create
  Dock UI, thread-list mapping, or account-rotation support.
- Adjacent-surface check: later phases reuse `AppServerClient`; this phase must
  expose typed connection and request boundaries instead of leaking raw JSON.
- Failure posture: offline, handshake failure, malformed response, and
  notification read failure become explicit states; no silent fallback transport.
- Depth-first proof: implementation can end with tests/diagnostic evidence only,
  because the next phase owns the first data method.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: JSON-RPC envelopes and test transport

Work: Add typed request, response, notification, id, and error envelopes plus a
test transport that can feed responses and notifications deterministically.

Checklist (must all be done):
- `JSONRPC.swift` defines Codable envelopes with explicit id and error handling.
- Unit tests cover request encoding, response decoding, notification decoding,
  unknown fields, and malformed payload failure.
- Test transport can prove request/response matching without WebSocket.

Exit criteria (all required):
- Envelope tests pass.
- No SwiftUI/product UI file depends on raw JSON-RPC types.

## Implementation slice 2: WebSocket connection lifecycle

Work: Add `AppServerClient` with connect, send, receive, disconnect, connection
state, and request id correlation.

Checklist (must all be done):
- `AppServerClient` owns the WebSocket task and pending requests.
- Connection state distinguishes idle, connecting, connected, offline, and error.
- Receive loop keeps reading after request responses so notifications are not
  starved.
- Request timeout/cancellation behavior fails visibly.

Exit criteria (all required):
- Test transport proves multiple in-flight request ids resolve correctly.
- Offline and malformed-response paths surface explicit errors.

## Implementation slice 3: initialize/initialized handshake proof

Work: Add typed `initialize` and `initialized` wrappers and a focused
diagnostic/local test path.

Checklist (must all be done):
- Client sends `initialize`, handles the result, then sends `initialized`.
- Diagnostic/test can run against a local or simulated app-server endpoint.
- Success and failure are visible without product UI.

Exit criteria (all required):
- A test or local dev run proves the handshake.
- Phase 2 can call methods through the same client boundary.
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
- Run envelope unit tests for Codable request/response/notification shapes.
- Run test-transport checks for id correlation and malformed payload failures.
- Run a local or simulated handshake diagnostic proving `initialize` then
  `initialized`.
- Confirm no product UI depends on raw JSON-RPC.

## Cold-read consistency checks
- Scope matches the epic: first proof is JSON-RPC communication, not UI.
- No AIMGR, thread-list, Dock, or voice behavior is assigned to this phase.
- Phase 2 has a clear reusable client boundary to build on.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Developer-only protocol proof.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Run the focused protocol test or diagnostic against a reachable app-server.

# 10) Decision Log (append-only)

## 2026-05-27 - North Star approved from revised epic objective

Context
: User corrected the epic so the first proof is JSON-RPC communication, not UI.

Options
: Keep UI shell first, or split protocol proof into its own first sub-plan.

Decision
: Make JSON-RPC handshake the first sub-plan.

Consequences
: UI waits until the protocol seam is proven.

## 2026-05-28 - Implementation tooling check

Context
: Phase 1 implementation needs Swift package/test tooling.

Options
: Install missing tooling, or use existing local tooling if already present.

Decision
: `swift --version` reports Apple Swift `6.3.2`, so no tool installation is
  required for this phase. The implementation will use SwiftPM with no external
  package dependencies.

Consequences
: Phase 1 can build and test locally without adding dependency-manager or
  bootstrap setup.

## 2026-05-28 - iOS simulator verification target

Context
: Phase 1 is protocol-first, but the client code is intended for the future
  iPhone app.

Options
: Treat macOS SwiftPM tests as the only verification target, or also run the
  package against the intended iPhone simulator.

Decision
: Use the `iPhone 17` simulator as the Phase 1 iOS simulator verification
  target when running simulator checks. Other installed iPhone simulators are
  not the intended target for this phase unless `iPhone 17` is unavailable.

Consequences
: Phase 1 verification should include macOS SwiftPM tests plus an iOS simulator
  build/test pass on `iPhone 17` when Xcode exposes that destination.
