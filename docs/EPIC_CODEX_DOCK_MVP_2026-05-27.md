---
title: Epic — Codex Dock MVP depth-first implementation plan
date: 2026-05-27
doc_type: epic
status: active
raw_goal: |
  Now, I want you to break these further apart. Phase one is way too huge. There should be like eight phases here. use ArcEpic divide it up further auto plan all the phases get it through the plan audit depth first, depth first build up. I would suggest the most fundamental thing is is not actually a UI. It's actually JSON RPC communication working. but you know whatever you think is best
raw_goal_sha256: 7511c828665d9fbf4a77bcdf31c494ea3bb4c3169a372bff191f7b4f37b80383
sub_plans_approved: true
critic_runtime: null
critic_model: null
critic_effort: null
models_sha256: null
auto_execution: null
---

# TL;DR

Build the Codex Dock MVP through eight smaller depth-first sub-plans. The first
proof is not UI: it is a JSON-RPC client that can connect to a Codex
app-server and complete the handshake. Only after that do we add `thread/list`,
then the iPhone Dock, then thread reading, then text/request control, then
multi-host scanning, then archive/host management, and finally in-place voice
plus accessibility polish. Every sub-plan owns a full canonical `$arch-step`
plan doc and must pass the `auto-plan` receipt/ready gate before implementation.

# Decomposition

1. **JSON-RPC handshake foundation**: Build the protocol client seam first:
   WebSocket JSON-RPC envelopes, request ids, connection state, and
   `initialize`/`initialized`, with no product UI requirement.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_01_JSON_RPC_HANDSHAKE_FOUNDATION_2026-05-27.md
   - Gate to next: A test or local dev run can connect to a Codex app-server,
     complete the handshake, surface connected/offline/error state, and prove
     that protocol code is isolated from UI.
   - Status: complete
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: passed — Phase 1 implementation, plan-audit
     implementation check, thermonuclear review, macOS SwiftPM tests, and
     `iPhone 17` simulator tests are complete; no Phase 2+ scope was built.

2. **Thread-list data pipeline**: Add the first real Codex data method,
   `thread/list`, and normalize thread summaries without depending on final UI.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_02_THREAD_LIST_DATA_PIPELINE_2026-05-27.md
   - Gate to next: A test or dev diagnostic can call `thread/list`, normalize
     host-scoped session summaries, and prove mapping behavior with real or
     fixture app-server payloads.
   - Status: planning
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: —

3. **iPhone shell and single-host Dock**: Create the SwiftUI app shell and
   render the first useful single-host Dock from the proven session summaries.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_03_IPHONE_SHELL_SINGLE_HOST_DOCK_2026-05-27.md
   - Gate to next: The app builds, launches, connects to one configured host,
     and shows real session rows in a Dock surface aligned to the v2 Dock mockup.
   - Status: planning
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: —

4. **Thread detail read/live view**: Open a real Dock row into a session detail
   view that reads/resumes the thread and keeps receiving live updates.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_04_THREAD_DETAIL_READ_LIVE_VIEW_2026-05-27.md
   - Gate to next: From a real Dock row, the app opens the correct thread,
     renders normalized events, and keeps reading notifications while the view
     is open.
   - Status: planning
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: —

5. **Text control and minimal request cards**: Add typed steering and minimal
   supported request/approval cards on top of the open thread path.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_05_TEXT_CONTROL_REQUEST_CARDS_2026-05-27.md
   - Gate to next: The user can send typed text through the app-server and
     supported request cards can be answered, while unsupported requests remain
     visible as "Needs desktop".
   - Status: planning
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: —

6. **Multi-host Dock scan expansion**: Widen the working list/detail/control
   path to multiple hosts, filters, branch grouping, and app-local labels/colors.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_06_MULTI_HOST_DOCK_SCAN_EXPANSION_2026-05-27.md
   - Gate to next: The app can show at least two configured hosts in one Dock,
     tolerate one offline host, filter sessions, and preserve app-local
     labels/colors by host/backend/thread id.
   - Status: planning
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: —

7. **Archive and Hosts surfaces**: Add reversible archive/unarchive and the
   Hosts screen after multi-host state exists.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_07_ARCHIVE_HOSTS_SURFACES_2026-05-27.md
   - Gate to next: A session can be archived out of the Dock and restored from
     Archive, and the Hosts screen uses the same host registry/state without
     introducing AIMGR.
   - Status: planning
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: —

8. **Voice, accessibility, and final MVP polish**: Add in-place push-to-talk
   transcription, accessibility hardening, visual polish, and final acceptance.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_08_VOICE_ACCESSIBILITY_FINAL_POLISH_2026-05-27.md
   - Gate to next: Last sub-plan.
   - Status: planning
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: —

# Test Host Notes

- `Amir-M5`: This machine. Use it as the primary local/single-host test target.
- `Home`: Secondary server/host. It is SSH-able, but Tailscale daemon and
  Codex app-server reachability may not be ready yet. Keep it as the planned
  second host for multi-host testing, and return to setup if the app cannot
  speak to it immediately.

# Mockup Index

These v2 mockups are visual anchors for implementation plans. They are not
golden-test assets. Phase 1 and Phase 2 are intentionally non-UI and therefore
reference the mockups only as downstream context.

- Dock normal: [01-dock-normal.png](mockups/codex-dock-2026-05-27-v2/01-dock-normal.png)
- Needs-me filter: [02-dock-needs-me.png](mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png)
- Session detail: [03-session-detail.png](mockups/codex-dock-2026-05-27-v2/03-session-detail.png)
- Inline dictation: [04-session-dictation-inline.png](mockups/codex-dock-2026-05-27-v2/04-session-dictation-inline.png)
- Archive: [05-archive.png](mockups/codex-dock-2026-05-27-v2/05-archive.png)
- Hosts: [06-hosts.png](mockups/codex-dock-2026-05-27-v2/06-hosts.png)
- Dock rotation feedback, post-V1 exploratory only: [07-dock-rotation-feedback.png](mockups/codex-dock-2026-05-27-v2/07-dock-rotation-feedback.png)

# Orchestration Log

- 2026-05-27 Replaced the previous four-sub-plan epic with an eight-sub-plan
  decomposition after the user said the first phase was too large and that the
  first proof should be JSON-RPC communication, not UI.
- 2026-05-27 Ran `$arch-step auto-plan` receipts for all eight phase docs:
  research, deep-dive-pass-1, deep-dive-pass-2, phase-plan, and
  consistency-pass.
- 2026-05-27 Verified all eight phase docs with generated ready gates:
  `READY next=implement-loop`.
- 2026-05-28 Implemented Phase 1 only: JSON-RPC envelopes, app-server client
  boundary, request correlation, connection state, initialize/initialized
  handshake, deterministic test transport, and focused tests. Ran
  `swift test` and `xcodebuild test` on the `iPhone 17` simulator.

# Decision Log

- 2026-05-27 Planning-only epic scope: this epic is complete when all eight
  sub-plan docs pass `$arch-step auto-plan` readiness and the epic plan audit is
  ready. Implementation remains separate future work.
- 2026-05-27 AIMGR remains post-V1: v2 mockups may show Rotate affordances, but
  V1 implementation plans must not include AI Manager integration or account
  rotation.
- 2026-05-28 Tool installation is explicitly permitted for this epic. If a
  phase needs missing CLI tools, SDKs, package managers, simulators, test
  runners, or other local development dependencies, install the needed tooling
  instead of designing around the absence of the tool. Record material installs
  in the relevant phase plan/worklog.
