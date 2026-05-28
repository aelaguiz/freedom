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
- Symptom: Dock All can still look stale, and Running can show no matches, even when many Codex CLI/app-server processes exist on `Amir-M5`.
- Impact: The phone path is real and relay-backed, but the Dock projection hides loaded live sessions behind stored `Limited` history and only treats currently active turns as `Running`.
- Most likely cause: The old endpoint bug is fixed, but the UI semantics are too narrow: Codex reports most open loaded sessions as `idle`, while Dock `Running` only includes `.running` rows derived from Codex `active` status. All also sorts primarily by last activity, so recent stored `notLoaded` history can appear above live loaded rows.
- Next action: Keep `Needs me` tied to real app-server attention flags only; `Running` now includes loaded live sessions and All now puts live loaded rows before stored `Limited` history.
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

# 2026-05-28 Follow-Up 2
The symptom was rechecked again after the user reported that All still looked
old and Needs me / Running showed no matches.

Findings:

- `ws://192.168.50.117:4510` returned `108` real rows: `3 active`, `16 idle`,
  and `89 notLoaded`.
- `ws://192.168.50.117:4500` returned `100` real rows, all `notLoaded`.
- That raw `:4500` shape exactly matches the bad UI: All looks like old
  Limited history, Running is empty, and Needs me is empty.
- The canonical plain `iPhone 17` simulator was
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Another booted simulator named
  `feat_remount-disposal-lifecycle-post-audit - iPhone 17` had Codex Dock
  installed and a stale process, but no relay socket.
- A process socket check confirmed the canonical simulator app had previously
  connected to `:4510`; the stale duplicate simulator was a plausible source
  of operator confusion.

Guardrail fix:

- The Dock host summary now displays the full WebSocket endpoint including the
  port, for example `ws://192.168.50.117:4510`.
- `rtk make app SIM='iPhone 17'` now terminates Codex Dock on other booted
  simulators before launching the selected simulator.
- `rtk make app` prints `launch endpoint: ws://192.168.50.117:4510` during
  launch, so a raw `:4500` launch is visible in command output.

Verification:

- `rtk swift test` passed 56 tests with 4 optional live endpoint tests skipped.
- `rtk npm run test:relay` passed all 3 relay tests.
- `rtk make app SIM='iPhone 17'` rebuilt, installed, and launched
  `com.aelaguiz.CodexDockApp` on
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Screenshot `/tmp/codex-dock-root-cause-after-make-app.png` shows All with a
  visible `Running` row and the host summary endpoint
  `ws://192.168.50.117:4510`.

# 2026-05-28 Follow-Up 3
The symptom was rechecked again after the user reported many running Codex
processes, but stale All / empty Running / empty Needs me in the Dock.

Findings:

- The relay itself is not empty: `ws://192.168.50.117:4510` returned `108`
  real rows: `1 active`, `18 idle`, and `89 notLoaded`; `thread/loaded/list`
  returned `19` real loaded IDs.
- The raw history endpoint still cannot represent the active loopback fleet:
  the latest recheck of `ws://192.168.50.117:4500` returned `100` rows with
  `99 notLoaded` and `1 idle`, while `thread/loaded/list` returned only `1`
  loaded ID.
- The host process table has many real loopback Codex app-server/client pairs
  such as `codex app-server --listen ws://127.0.0.1:<port> --enable goals`
  and clients using `--remote ws://127.0.0.1:<port>`.
- Codex app-server's own protocol separates `thread/loaded/list` from
  `ThreadStatus`: loaded sessions can be `idle`, `active`, `systemError`, or
  `notLoaded`.
- Codex app-server status code returns `Idle` for loaded sessions that have no
  running turn and no pending app-server request, and only returns `Active`
  when `runtime.running` or real pending approval/user-input flags exist.
- The Dock projection maps Codex `idle` to Dock `.idle`, then
  `DockFilter.running` only includes `.running`. That excludes most real
  loaded Codex sessions from the Running tab.
- The Dock ordering currently uses last-activity time before status priority.
  A recently touched `notLoaded` history row can therefore appear above loaded
  live rows in All, making the first viewport look stale.
- The current `iPhone 17` simulator was also still running an older build at
  accessibility-extra-large Dynamic Type; screenshots showed stale header
  layout and heavy truncation. Rebuilding/relaunching is required after the
  source fix, but stale build state is secondary to the filter semantics bug.

Fix-ready verdict:

- `Needs me` must remain grounded in real app-server attention flags or replayed
  pending requests. There is no evidence in the current live relay response for
  fake Needs-me rows, so the fix must not infer Needs-me from process presence.
- `Running` should represent loaded live Codex sessions for this Dock, not only
  model turns actively streaming at the exact refresh moment.
- All should prioritize live loaded statuses before stored `Limited` history so
  the first viewport answers "what is alive right now?"

Implementation:

- Changed `DockFilter.running` so Running includes loaded live row statuses:
  `needsMe`, `running`, `idle`, and `failed`; it still excludes `limited`
  stored history.
- Changed Dock section and row ordering to sort by status priority before last
  activity. `Limited` history no longer outranks loaded live rows in All just
  because its stored timestamp is newer.
- Kept `Needs me` strict: only real app-server attention flags / pending
  request enrichment can put a row there.
- Updated Dock projection tests to encode this contract.

Verification:

- `rtk swift test` passed 72 tests with 5 optional live-host tests skipped.
- `rtk npm run test:relay` passed all 5 relay tests.
- `rtk node --check scripts/dock-relay.mjs` passed.
- `rtk make app SIM='iPhone 17'` rebuilt, installed, and relaunched
  `com.aelaguiz.CodexDockApp` on
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` against
  `ws://192.168.50.117:4510`.
- Screenshot `/tmp/codex-dock-bug-fixed-all.png` shows All headed by real
  live rows from `ws://192.168.50.117:4510`, with the first viewport showing
  `Running` / `Idle` rows instead of old `Limited` history.
- A direct relay verification after the patch returned `108` rows:
  `19 idle`, `1 active`, and `88 notLoaded`. The new Running filter therefore
  has `20` real rows, while Needs me correctly has `0` because no current row
  reported `waitingOnApproval` or `waitingOnUserInput`.
- `rtk make app SIM='iPhone 17'` was rerun after the fix and printed
  `launch endpoint: ws://192.168.50.117:4510`.
- Screenshot `/tmp/codex-dock-root-cause-latest.png` shows All headed by live
  rows on the relay endpoint, not stored `Limited` history.
- Screenshot `/tmp/codex-dock-root-cause-running-tab-correct.png` shows the
  Running tab populated with the same real loaded live rows.
- Screenshot `/tmp/codex-dock-root-cause-needs-me-tab.png` shows Needs me empty
  with the correct message because the real relay data has zero attention
  flags.
