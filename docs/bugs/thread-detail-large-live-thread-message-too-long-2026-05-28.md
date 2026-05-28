---
title: "Thread detail fails on large live threads with Message too long"
date: 2026-05-28
status: resolved
owners: [aelaguiz]
reviewers: [Codex]
related:
  - ../EPIC_CODEX_DOCK_MVP_2026-05-27.md
  - ../CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
  - ../../CodexDock/State/ThreadDetailStore.swift
  - ../../scripts/dock-relay.mjs
---

# TL;DR
<!-- bugs:block:tldr:start -->
- Symptom: Opening a real live Dock row could show `Thread unavailable: App-server transport failed: The operation couldn't be completed. Message too long`.
- Impact: The Dock list was real and relay-backed, but some real rows could not be opened on iPhone because the detail path pulled a multi-megabyte WebSocket message.
- Most likely cause: `ThreadDetailStore` used `thread/read includeTurns:true` and `thread/resume` without `excludeTurns`, so large active threads returned full turn history in one response.
- Next action: Use Codex's supported compact detail path: `thread/read includeTurns:false`, `thread/turns/list limit:10`, then `thread/resume excludeTurns:true`.
- Status: resolved.
<!-- bugs:block:tldr:end -->

# Bug North Star
<!-- bugs:block:analysis:start -->
Opening a Dock row is only correct if the app connects to the real owning Codex app-server path and loads the real thread without mocking, truncating by accident, or depending on an oversized single WebSocket response.

# Evidence
- The failure was reproduced on `iPhone 17` simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` while opening the first real live row from `ws://192.168.50.117:4510`.
- The failing thread was `019e6c01-7f74-7460-a3d7-d35e32b41162`.
- Direct relay probes showed:
  - `thread/read includeTurns:false`: `722` bytes.
  - `thread/read includeTurns:true`: `2,057,855` bytes.
  - `thread/resume` without `excludeTurns`: `2,396,384` bytes.
  - `thread/resume excludeTurns:true`: `1,111` bytes.
- Direct upstream probing showed `thread/turns/list limit:3` returned a small paged response (`7,114` bytes) for the same active thread.

# Investigation
Codex supports separate browsing and resume APIs:

- `thread/read` can return metadata without turns.
- `thread/turns/list` pages turn history.
- `thread/resume excludeTurns:true` rejoins the live thread without returning full turn history.

The app was using the full-history path for initial detail load. That worked for small threads but failed on real large active sessions because the iOS WebSocket transport rejected the oversized single message.

# Ranked Hypotheses
1. Confirmed: Full-history `thread/read` / `thread/resume` responses can exceed the iOS WebSocket message size limit on real active threads.
2. Rejected: The relay endpoint was disconnected or mocked. The relay returned real rows, and compact direct probes succeeded.
3. Rejected: The row itself was invalid. The same thread opened after switching to compact read, paged turns, and compact resume.
<!-- bugs:block:analysis:end -->

# Fix Plan
<!-- bugs:block:fix_plan:start -->
- Add typed support for `thread/turns/list`.
- Add `excludeTurns` to typed `thread/resume` params.
- Forward `thread/turns/list` through the Dock relay to the same real upstream selected for `thread/read` / `thread/resume`.
- Change `ThreadDetailStore` to load detail using compact read, a small real turn page, and compact resume.
- Keep the composer and live subscription on the real resumed thread.
<!-- bugs:block:fix_plan:end -->

# Implementation
<!-- bugs:block:implementation:start -->
- Added `ThreadTurnsListParams` and `ThreadTurnsListResponseDTO`.
- Added `ThreadResumeParams.excludeTurns`.
- Added `AppServerClient.threadTurnsList`.
- Added relay forwarding for `thread/turns/list`.
- Changed `ThreadDetailStore.load()` to call:
  - `thread/read` with `includeTurns:false`
  - `thread/turns/list` with `limit:10`
  - `thread/resume` with `excludeTurns:true`
- Kept active-turn steering behavior by deriving events and active turn IDs from the paged real turns.
<!-- bugs:block:implementation:end -->

# Verification
- `rtk swift test` passed 72 tests with 5 optional live-host tests skipped.
- `rtk npm run test:relay` passed all 5 relay tests.
- `rtk env CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=.codex-dock/app-server.token CODEX_DOCK_REAL_HOST_ID=Amir-M5 CODEX_DOCK_REAL_HOST_NAME=Amir-M5 swift test --filter AppServerClientTests/testPhoneReachableRealHost` passed the real phone-reachable handshake, list, detail read, paged turns, and resume smoke tests.
- Direct relay probe returned compact real calls for a loaded thread:
  - `thread/read includeTurns:false`: `693` bytes.
  - `thread/turns/list limit:10`: `13,444` bytes.
  - `thread/resume excludeTurns:true`: `1,076` bytes.
- `rtk make app SIM='iPhone 17'` rebuilt and relaunched against `ws://192.168.50.117:4510`.
- Screenshot `/tmp/codex-dock-after-detail-fix-open-row.png` shows the real live row open with `Live`, composer controls, and real paged turn events instead of `Thread unavailable`.
