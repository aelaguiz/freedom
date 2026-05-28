---
title: "Dock live status filters use the wrong app-server"
date: 2026-05-28
status: resolved
owners: [aelaguiz]
reviewers: [Codex]
related:
  - ../EPIC_CODEX_DOCK_MVP_2026-05-27.md
  - ../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
  - ../../CodexDock/State/DockStore.swift
  - ../../CodexDock/Features/Dock/DockView.swift
  - ../../Makefile
---

# TL;DR
<!-- bugs:block:tldr:start -->
- Symptom: Dock All shows old `Limited` rows, while Needs me and Running show no matches despite active Codex processes on `Amir-M5`.
- Impact: The phone UI is connected to a real host, but not to the live in-memory sessions the user is trying to monitor.
- Most likely cause: `rtk make app` points the simulator at a standalone LAN Codex app-server on `ws://192.168.50.117:4500`; that server has zero loaded threads. The running Codex sessions are attached to separate loopback app-server processes like `ws://127.0.0.1:<port>`, which the phone cannot reach directly.
- Next action: Keep the raw app-server and Dock relay running through `rtk make services`; use `rtk make app SIM=...` to launch the simulator against the relay. Rows stay newest-first; filters use the same refreshed real snapshot.
- Status: resolved.
<!-- bugs:block:tldr:end -->

# Bug North Star
<!-- bugs:block:analysis:start -->
The Dock is correct only when the iPhone path displays real live Codex state from the host. Stored history alone is not enough. If the app has not connected, directly or through a real host relay, to the app-server process that owns the loaded thread state, the work is not done.

# Bug Summary
The Swift UI and filters are mostly reflecting the data they receive:

- `DockStore` calls `thread/list` on one configured host.
- `SessionSummaryMapper` maps `notLoaded` to `SessionStatus.notLoaded`.
- `DockStore.status(for:)` maps `notLoaded` to the visible `Limited` row status.
- `DockFilter.running` only includes `.running`; `DockFilter.needsMe` only includes `.needsMe`.

The wrong part is the source. The configured phone endpoint is an authenticated LAN app-server that can browse persisted history, but it is not the app-server process backing the active Codex sessions.

# Evidence
Live query against the configured phone endpoint `ws://192.168.50.117:4500`:

- `initialize` succeeded with real Codex app-server user agent.
- `thread/list` with the app's params returned 50 rows.
- Status counts were `notLoaded: 50`.
- `thread/loaded/list` returned `0` IDs.
- A larger `thread/list` page returned 100 rows, all `notLoaded`.

Process evidence on `Amir-M5`:

- The phone-visible process is `codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token ...`.
- There are many active private app-servers launched as `codex app-server --listen ws://127.0.0.1:<port> --enable goals`.
- There are corresponding Codex clients using `--remote ws://127.0.0.1:<port>`.

Live query across the discovered loopback app-server processes:

- 12 loopback endpoints were reachable.
- Their `thread/loaded/list` calls returned 28 unique loaded thread IDs.
- `thread/read` on those loaded IDs returned 25 `idle` and 3 `active` rows.
- The active rows included current work in `codex-client` and `lessons_studio`.

# Investigation
The Codex app-server implementation explains the behavior:

- `thread/list` starts from stored thread history and overlays loaded status only for threads loaded in that same app-server process.
- `thread/loaded/list` is process-local and returns only thread IDs currently loaded in memory.
- A separate app-server process can see the same persisted history but cannot see another process's in-memory loaded thread manager.

Therefore, calling `thread/list` on the standalone LAN daemon cannot show active status for sessions loaded in the private loopback app-servers. The iPhone also cannot connect directly to those loopback URLs because `127.0.0.1` from the simulator/device is not the Mac host's loopback app-server.

# Ranked Hypotheses
1. Confirmed: The app is connected to the wrong app-server for live status. The configured LAN daemon reports zero loaded threads, while the loopback fleet reports 28 loaded threads.
2. Confirmed secondary: Needs-me is not expected to be populated from current live evidence unless Codex reports `waitingOnApproval` or `waitingOnUserInput`. The measured loaded fleet currently has active and idle rows, but no waiting flags.
3. Rejected: Swift filter logic alone is not the primary cause of Running being empty. With only `notLoaded` input rows, the Running tab should be empty.
<!-- bugs:block:analysis:end -->

# Fix Plan
<!-- bugs:block:fix_plan:start -->
Add a small host-side relay behind `rtk make services`:

- Listen on a phone-reachable LAN port with bearer-token auth.
- Keep the existing raw Codex LAN app-server running for stored history.
- Discover local loopback Codex app-server processes from the host process table.
- Query each discovered endpoint using supported Codex JSON-RPC methods:
  - `initialize`
  - `thread/loaded/list`
  - `thread/read`
  - `thread/list`
- Merge live loaded rows over stored history by thread ID.
- Return merged rows sorted by newest activity first so All stays chronological.
- Point `.env` and `rtk make app` at the relay endpoint, not the raw history-only daemon.
- Keep all evidence real: no fake rows and no mocked statuses.
<!-- bugs:block:fix_plan:end -->

# Implementation
<!-- bugs:block:implementation:start -->
- Added `scripts/dock-relay.mjs`, an authenticated phone-reachable WebSocket relay.
- Added `package.json` / `package-lock.json` with the `ws` dependency used by the relay.
- Added `rtk make dock-relay`, `dock-relay-status`, `dock-relay-stop`, and `dock-relay-restart`.
- Changed `rtk make services` and `rtk make app SIM=...` so the iPhone app points at `ws://192.168.50.117:4510`, not the raw history-only app-server on `:4500`.
- Kept the raw app-server running on `:4500` as the relay's history source.
- Updated `DockStore` section/row sorting so newest rows and newest branch sections stay first after grouping.
- Added Dock auto-refresh every five seconds while the Dock view is active.
- Updated the runbook to make the relay the canonical app endpoint.
<!-- bugs:block:implementation:end -->

# Verification Plan
- Relay direct query passed against `ws://192.168.50.117:4510`: `thread/list`
  returned 50 newest-first rows with `active: 3`, `idle: 21`, and
  `notLoaded: 26`; `thread/loaded/list` returned 29 real loaded IDs.
- `rtk swift test` passed 33 tests with 3 optional live endpoint tests skipped.
- Phone-reachable live Swift tests passed against the relay with:
  `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510`.
- `rtk make services` rewrote `.env` to the relay endpoint.
- `rtk make app SIM='iPhone 17'` passed and launched `com.aelaguiz.CodexDockApp`.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
  -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath
  .codex-dock/DerivedData` passed.
- Screenshot `/tmp/codex-dock-phase3-relay-recency-refresh.png` shows the
  iPhone 17 simulator Dock rendering `Amir-M5 · 118 sessions` from the relay.
  The All tab is newest-first; the relay proof shows real active rows available
  for the Running filter.
- Raw app-server and relay were left running.

# 2026-05-28 Follow-Up
The same symptom was rechecked while Phase 5 was in progress.

Findings:

- The canonical `iPhone 17` simulator is
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- A second booted simulator named
  `feat_remount-disposal-lifecycle-post-audit - iPhone 17`
  also existed, and a stale `CodexDockApp` process was still visible for it.
- The canonical simulator was connected to the relay at
  `ws://192.168.50.117:4510` and showed real `Running` rows in the All feed.
- A relay query returned `107` real rows: `3 active`, `15 idle`, and
  `89 notLoaded`.
- The active rows all had empty `activeFlags`; no live row reported
  `waitingOnApproval` or `waitingOnUserInput`.
- Therefore an empty `Needs me` filter is correct for the current live data.
  It must not be filled from process presence alone.

Follow-up fix:

- The relay now inspects active live threads for replayed pending app-server
  requests via real `thread/resume` behavior.
- If a pending approval/input/elicitation request exists, the relay merges the
  supported app-server attention flags into that thread's returned status.
- This keeps Dock `Needs me` derived from real pending request signals, not
  mocked rows or guessed process state.
