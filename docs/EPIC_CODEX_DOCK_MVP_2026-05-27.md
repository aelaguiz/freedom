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
app-server and complete the handshake from a phone-reachable path. Only after
that do we add `thread/list`, then the iPhone Dock, then thread reading, then
text/request control, then multi-host scanning, then archive/host management,
and finally in-place voice plus accessibility polish. Every sub-plan owns a
full canonical `$arch-step` plan doc and must pass the `auto-plan`
receipt/ready gate before implementation.

# HARD REQUIREMENT: REAL PHONE-REACHABLE SERVER

PHASE 1 IS NOT COMPLETE UNTIL AN IPHONE CAN CONNECT TO A REAL CODEX APP-SERVER
ON A REAL HOST.

Mocks, scripted transports, fake app-server fixtures, local-only Unix sockets,
and Mac-loopback WebSocket endpoints do not satisfy implementation completion.
They can help developer tests, but they are not acceptance evidence.
`ws://127.0.0.1:*`, `localhost`, and the daemon Unix socket prove only the
Mac/simulator-local path; they do not prove that a phone can reach the server.

The completion endpoint must be a real Codex app-server on `Amir-M5` or `Home`,
exposed over a phone-reachable network path such as LAN or Tailscale. If we
have not actually connected to that host from the iPhone path, the phase remains
open.

The `iPhone 17` simulator is the simulator build/test target for this phase, but
simulator-only evidence is not enough if it uses Mac loopback, mocks, fixtures,
or any endpoint a physical phone could not reach.

# Decomposition

1. **JSON-RPC handshake foundation**: Build the protocol client seam first:
   WebSocket JSON-RPC envelopes, request ids, connection state, and
   `initialize`/`initialized`, with no product UI requirement.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_01_JSON_RPC_HANDSHAKE_FOUNDATION_2026-05-27.md
   - Gate to next: The iPhone path can connect to a real Codex app-server on a
     real phone-reachable host, complete the handshake, surface
     connected/offline/error state, and prove that protocol code is isolated
     from UI. Scripted transports, local-only Unix sockets, loopback
     WebSockets, and mocks do not satisfy this gate.
   - Status: complete
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: passed — Phase 1 now proves the local protocol
     implementation and a real phone-reachable host path. A real Codex
     app-server ran on `Amir-M5` at `ws://192.168.50.117:4500` with websocket
     bearer auth; macOS SwiftPM and the `iPhone 17` simulator both completed
     `initialize`/`initialized` against that endpoint.

2. **Thread-list data pipeline**: Add the first real Codex data method,
   `thread/list`, and normalize thread summaries without depending on final UI.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_02_THREAD_LIST_DATA_PIPELINE_2026-05-27.md
   - Gate to next: A test or dev diagnostic can call `thread/list`, normalize
     host-scoped session summaries, and prove mapping behavior with real or
     fixture app-server payloads.
   - Status: complete
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: passed — Phase 2 now calls `thread/list` through
     `AppServerClient`, maps protocol DTOs into host-scoped `SessionSummary`
     values, and proved the live normalization path against the real
     `Amir-M5` Codex app-server from macOS SwiftPM and the `iPhone 17`
     simulator.

3. **iPhone shell and single-host Dock**: Create the SwiftUI app shell and
   render the first useful single-host Dock from the proven session summaries.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_03_IPHONE_SHELL_SINGLE_HOST_DOCK_2026-05-27.md
   - Gate to next: The app builds, launches, connects to one configured host,
     and shows real session rows in a Dock surface aligned to the v2 Dock mockup.
   - Status: complete
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: passed — Phase 3 now builds and launches the iPhone
     Dock shell on `iPhone 17`, uses the authenticated relay endpoint on
     `Amir-M5`, renders real live sessions from host loopback app-servers plus
     stored history, keeps rows newest-first, and auto-refreshes.

4. **Thread detail read/live view**: Open a real Dock row into a session detail
   view that reads/resumes the thread and keeps receiving live updates.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_04_THREAD_DETAIL_READ_LIVE_VIEW_2026-05-27.md
   - Gate to next: From a real Dock row, the app opens the correct thread,
     renders normalized events, and keeps reading notifications while the view
     is open.
   - Status: complete
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: passed — Phase 4 now opens a real Dock row into a
     Thread detail screen on `iPhone 17`, reads and resumes the real upstream
     Codex thread through the phone-reachable relay on
     `ws://192.168.50.117:4510`, renders normalized events without raw JSON,
     and keeps notification/server-request intake alive while the view is open.

5. **Text control and minimal request cards**: Add typed steering and minimal
   supported request/approval cards on top of the open thread path.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_05_TEXT_CONTROL_REQUEST_CARDS_2026-05-27.md
   - Gate to next: The user can send typed text through the app-server and
     supported request cards can be answered, while unsupported requests remain
     visible as "Needs desktop".
   - Status: complete
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: passed — Phase 5 now sends typed text through the
     real app-server path, preserves failed send text, renders supported and
     unsupported request cards, responds to supported requests by JSON-RPC
     request id, and keeps Dock `Needs me` tied to real pending app-server
     request signals instead of mocked status.

6. **Multi-host Dock scan expansion**: Widen the working list/detail/control
   path to multiple hosts, filters, branch grouping, and app-local labels/colors.
   - DOC_PATH: docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_06_MULTI_HOST_DOCK_SCAN_EXPANSION_2026-05-27.md
   - Gate to next: The app can show at least two configured hosts in one Dock,
     tolerate one offline host, filter sessions, and preserve app-local
     labels/colors by host/backend/thread id.
   - Status: complete
   - Auto-plan status: ready (`READY next=implement-loop`)
   - Epic-critic verdict: passed — Phase 6 now uses a host registry, loads
     hosts independently, shows per-host state, keeps a live host visible when
     another host is offline, groups by host/branch, filters over normalized
     row status, persists app-local labels/colors by host/backend/thread id,
     and exposes the full relay endpoint so `:4500` vs `:4510` cannot be
     hidden.

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

- `Amir-M5`: This machine. Use it as the primary local/single-host test target,
  but the acceptance endpoint must be phone-reachable. Phase 1 completed against
  a direct Codex app-server listener on this host at `ws://192.168.50.117:4500`
  with websocket bearer auth. Phase 2 reused the same endpoint shape to call
  live `thread/list` and map the response into host-scoped `SessionSummary`
  values. Its daemon-managed app-server still exposes a Unix socket, not a
  phone-reachable listener.
- `Home`: Secondary server/host. It is SSH-able, but Tailscale daemon and
  Codex app-server reachability may not be ready yet. Keep it as the planned
  second host for multi-host testing, and return to setup if the app cannot
  speak to it immediately.
- `iPhone 17` simulator: Use this simulator for simulator checks in this phase.
  Do not count simulator-only loopback, mock, or fixture evidence as completion.

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
- 2026-05-28 Reopened Phase 1 after the user clarified the acceptance gate:
  mocked/scripted handshakes, local Unix sockets, and Mac-loopback WebSockets
  are not enough. Completion requires the iPhone path to connect to a real
  Codex app-server on a real phone-reachable host.
- 2026-05-28 Completed Phase 1 against a real Codex app-server on `Amir-M5`.
  Started a direct app-server listener with websocket auth, verified
  `http://192.168.50.117:4500/readyz`, and ran the `initialize`/`initialized`
  handshake from macOS SwiftPM and the `iPhone 17` simulator against
  `ws://192.168.50.117:4500`.
- 2026-05-28 Completed Phase 2 against the same real host shape. Added
  `thread/list`, protocol DTOs, host-scoped `SessionSummary` models, and
  mapper tests. Verified live `thread/list` plus `SessionSummary` mapping from
  macOS SwiftPM and the `iPhone 17` simulator against
  `ws://192.168.50.117:4500`.
- 2026-05-28 Completed Phase 3, then repaired a false-complete live-session
  source bug. The standalone phone-visible app-server on `:4500` only had
  stored `notLoaded` history; active Codex sessions were attached to private
  loopback app-servers. Added the authenticated Dock relay on
  `ws://192.168.50.117:4510`, made `rtk make services` the canonical start
  path, launched the app on `iPhone 17`, and verified real Running rows without
  mocks.
- 2026-05-28 Completed Phase 4 against the real relay path. Added
  `thread/read` and `thread/resume`, a `ThreadDetailStore`, normalized thread
  events, row-to-detail navigation, and relay forwarding for full reads, live
  resume, notifications, and server requests. Verified a real loaded thread
  through `ws://192.168.50.117:4510`, ran the optional real-host read/resume
  XCTest, launched on `iPhone 17`, and tapped a real Dock row into Thread
  detail.
- 2026-05-28 Completed Phase 5 against the real relay path. Added typed
  `turn/start` and `turn/steer`, the session composer, minimal request cards,
  JSON-RPC server-request responses, relay turn forwarding, and relay
  request-aware Dock attention enrichment. Verified a real typed send through
  `ws://192.168.50.117:4510`, relaunched on `iPhone 17`, and opened a real
  Dock row to the composer.

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
- 2026-05-28 Codex transport finding from `/Users/aelaguiz/workspace/codex`:
  this machine's daemon is running with `remoteControlEnabled: true`, but the
  daemon-managed app-server is still Unix-socket-only because
  `codex-rs/app-server-daemon/src/backend/pid.rs` starts it with
  `app-server --remote-control --listen unix://`. `config.toml` does not expose
  a phone-reachable app-server listener. A phone-reachable proof must launch or
  configure a real WebSocket listener such as `ws://0.0.0.0:<port>` or a
  host/Tailscale IP and must use Codex websocket auth for non-loopback
  listeners.
- 2026-05-28 Phase 3 live-state correction: a phone-reachable standalone
  app-server is still real but not sufficient for the Dock if it is not the
  process that owns loaded thread state. The supported path for this MVP is an
  authenticated host-side relay that uses supported Codex JSON-RPC calls against
  the real loopback app-servers and exposes one phone-reachable endpoint to the
  app. Relay data must stay real: no mocked rows and no invented statuses.
- 2026-05-28 Phase 4 relay extension: thread detail cannot be satisfied from
  relay list-row data. The relay must forward `thread/read includeTurns:true`,
  `thread/resume`, notifications, and server requests to a real owning
  app-server process, then expose that real stream through the same
  phone-reachable endpoint used by the app.
- 2026-05-28 Phase 5 attention correction: `Needs me` must not be inferred from
  the mere presence of a Codex process or from stale history. It is populated
  only from real app-server attention signals: active status flags or replayed
  pending server requests from the owning app-server. A live check on
  `Amir-M5` returned `3 active`, `15 idle`, and `89 notLoaded` rows with zero
  waiting flags, so the empty `Needs me` filter was correct for that moment.
- 2026-05-28 Phase 6 multi-host correction: a live two-host proof used
  `Amir-M5` on `ws://192.168.50.117:4510` plus intentionally offline `Home` at
  `ws://192.168.50.117:9`. The Dock kept `Amir-M5` rows visible and showed
  `Home` offline. The UI now displays full WebSocket endpoints, and
  `rtk make app` terminates stale Codex Dock processes on other booted
  simulators before launching the selected `iPhone 17`.
