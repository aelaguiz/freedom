---
title: Private Codex runtime rows open as thread unavailable
date: 2026-06-05
status: fix-ready
owners:
  - Codex Dock
reviewers: []
related:
  - scripts/dock-relay.mjs
  - scripts/dock-relay-app-server-registry.mjs
  - scripts/dock-relay-thread-data.mjs
---

<!-- bugs:block:tldr -->
## TL;DR

- Symptom: many visible Dock rows open to `thread unavailable` instead of a
  usable thread detail screen.
- Specific repro row: `Snap hack`, thread
  `019e94b6-0f84-7881-8242-27ded669eafd`, reported as owned by a private
  Codex runtime.
- Impact: the Dock can say a session is live while detail navigation cannot
  attach to that live owner.
- Root cause: the relay merges private `stdio://` Codex runtime owners into the
  live Dock list, so the row gets `status=running` and `Codex is working`; the
  detail path then calls `thread/detail/subscribe` -> `thread/resume`, which
  requires an attachable live app-server owner. The owning process for `eafd`
  is a standalone `codex -p yolo` process with a private stdio transport, not
  any `codex app-server --listen ws://...` endpoint.
- Next action: no fix in this pass. The issue is fix-ready if/when product
  behavior is selected.
- Status: fix-ready analysis only. No product code was changed.

<!-- bugs:block:analysis -->
## Bug North Star

If a Dock row is visible and actionable, opening it should either attach to a
real Codex runtime and stream the real thread, or clearly explain why that
runtime cannot be attached. A live badge must not imply capabilities the relay
does not actually have.

## Bug Summary

This investigation is scoped to rows that appear in Dock but fail when opened,
especially rows whose owner is described as a private Codex runtime. The task is
to understand the exact ownership model and failure path, not to patch behavior.

## Evidence

### User-Reported Symptom

- User reports many rows open as thread unavailable.
- User reports `Snap hack`, ending in `eafd`, says it is owned by a private
  Codex runtime.

### Simulator Reproduction

Commands and artifacts:

- Launched simulator app against the real relay hosts:
  `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1 SIM_LAUNCH_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510'`.
- Used Mobile MCP on simulator
  `DEF1631B-7125-43C6-BFA3-4423BF103C91`, searched for `Snap hack`, and tapped
  the exact row.
- Captured the detail screen with:
  `rtk make sim-ui-dump SIM='iPhone 17' SIM_UI_DUMP_DIR='/tmp/codex-client/private-runtime-snap-hack-sim-ui-dump' EXPECTED_SCREEN='thread' EXPECTED_THREAD_ID='019e94b6-0f84-7881-8242-27ded669eafd'`.
- Artifact:
  `/tmp/codex-client/private-runtime-snap-hack-sim-ui-dump/sim-ui-dump.json`
  and
  `/tmp/codex-client/private-runtime-snap-hack-sim-ui-dump/sim-ui-dump.md`.

Simulator proof result:

- The Dock search showed exactly 1 visible row:
  `Snap hack`, `thread=019e94b6-0f84-7881-8242-27ded669eafd`,
  `status=running`, `Amir-M5 - snap - main`, and visible text
  `Codex is working`.
- After tapping the row, the detail screen was active for the exact thread id.
- The detail header still showed `Codex is working`, but live state was `Stale`.
- The error element was:
  `Thread unavailable, App-server rejected request: thread 019e94b6-0f84-7881-8242-27ded669eafd is owned by a private Codex runtime`.
- The captured artifact passed with:
  `screenAfter=thread`,
  `activeThreadID=019e94b6-0f84-7881-8242-27ded669eafd`, and
  `expectedThreadID=019e94b6-0f84-7881-8242-27ded669eafd`.
- The artifact's detail rollup had:
  `rootValue=error; host=amir-m5.fairy-salmon.ts.net:4510; thread=019e94b6-0f84-7881-8242-27ded669eafd; live=stale`
  and
  `headerValue=host=amir-m5.fairy-salmon.ts.net:4510; thread=019e94b6-0f84-7881-8242-27ded669eafd; live=Stale; status=Codex is working; relationship=root`.

### Live Relay Probe

Relay: `ws://amir-m5.fairy-salmon.ts.net:4510`.

Fresh probe result on 2026-06-05:

- `initialize` returned `relayInstanceID=Amir-M5`.
- `dock/subscribe` returned `dockTotalRows=290`.
- The target row was present:
  - `title=Snap hack`
  - `threadID=019e94b6-0f84-7881-8242-27ded669eafd`
  - `status=running`
  - `logicalHostID=Amir-M5`
  - `hostEndpoint=amir-m5.fairy-salmon.ts.net:4510`
  - `repository=snap`
  - `workingDirectory=/Users/aelaguiz/workspace/snap`
  - `branch=main`
- `thread/detail/subscribe` failed with:
  - `code=-32020`
  - `message=thread 019e94b6-0f84-7881-8242-27ded669eafd is owned by a private Codex runtime`
  - `data.subsystem=live-upstream`
  - `data.retryable=true`

Route health result:

- `rtk make dock-relay-status` and `rtk make app-server-status` exited with
  code 2 because the relay was `not-ready`.
- The failing app-critical route was `thread/detail/subscribe`.
- `/routesz` reported `routeStatus=failed`, `phase=live-upstream`,
  `errorCode=-32020`, and the same private-runtime error for `eafd`.

Attachable app-server probe:

- The relay had 11 live WebSocket app-server endpoints.
- Each endpoint responded to `thread/loaded/list` with `loadedCount=0`.
- None of the 11 attachable WebSocket endpoints included
  `019e94b6-0f84-7881-8242-27ded669eafd`.

This rules out "wrong Swift tap parameters" and "one attachable app-server owns
the thread but the relay picked the wrong one" for this repro.

### Process Ownership

The owning rollout file is:

`/Users/aelaguiz/.codex/sessions/2026/06/04/rollout-2026-06-04T17-17-00-019e94b6-0f84-7881-8242-27ded669eafd.jsonl`

`lsof` showed PID `60045` holding that file open for write:

`codex 60045 aelaguiz 44w ... rollout-2026-06-04T17-17-00-019e94b6-0f84-7881-8242-27ded669eafd.jsonl`

`ps -p 60045 -o pid=,ppid=,command=` showed:

`60045 60044 /opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex -p yolo`

That process is a Codex runtime, not an attachable app-server command. By
contrast, attachable processes expose a named Unix socket or loopback WebSocket,
for example:

`codex app-server --listen unix://`

`codex app-server --listen unix:///tmp/codex-app-server.sock`

`codex app-server --listen ws://127.0.0.1:<port> --enable goals`

PID `60045` had no TCP listener:

`rtk lsof -Pan -p 60045 -iTCP -sTCP:LISTEN` returned no rows.

PID `60045` only showed anonymous Unix socket pairs under `lsof -a -U`; there
was no named control socket to attach to.

## Investigation Log

- 2026-06-05: Started analyze-only pass. Created this worklog before making any
  source changes. No code fix is in progress.
- 2026-06-05: Reproduced on iPhone 17 simulator by searching for `Snap hack`
  and tapping the exact `eafd` row. The app showed `Thread unavailable` with
  the private Codex runtime error.
- 2026-06-05: Captured simulator proof at
  `/tmp/codex-client/private-runtime-snap-hack-sim-ui-dump/sim-ui-dump.json`.
- 2026-06-05: Queried the real relay directly. The list row is `running`, but
  `thread/detail/subscribe` fails with `-32020 private Codex runtime`.
- 2026-06-05: Queried all 11 attachable WebSocket app-server endpoints. None
  had the `eafd` thread loaded.
- 2026-06-05: Confirmed PID `60045` owns the rollout file and is a private
  `codex -p yolo` runtime with no TCP listener.
- 2026-06-05: Read Dock relay, Swift detail, and upstream Codex app-server
  source. The observed behavior matches current code paths.

## Hypotheses

1. Confirmed - private runtime attachability mismatch: the relay is using
   process/open-file evidence to label a row as live, but thread detail needs an
   attachable Codex app-server owner and rejects private owners.
2. Rejected for this repro - host identity mismatch: the simulator detail
   artifact shows the expected host
   `amir-m5.fairy-salmon.ts.net:4510` and exact active thread id.
3. Rejected for this repro - stale live ownership only: PID `60045` currently
   holds the rollout file open, and the row's timestamp was fresh during the
   simulator repro.
4. Rejected for this repro - Swift sends the wrong thread id: the simulator dump
   shows active detail thread id exactly
   `019e94b6-0f84-7881-8242-27ded669eafd`, and the relay direct call with the
   same id returns the same error.

## Codex Source Notes

- Upstream Codex app-server transports are `Stdio`, `UnixSocket`,
  `WebSocket`, and `Off`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs:66`).
- Supported `--listen` URLs include `stdio://`, `unix://`, `ws://IP:PORT`, and
  `off`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs:84`).
- The default app-server listen URL is `stdio://`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs:105` and
  `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/main.rs:22`).
- In stdio mode, Codex treats the app-server as single-client:
  `single_client_mode = matches!(&transport, AppServerTransport::Stdio)`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/lib.rs:662`).
- Stdio app-server startup creates one connection with
  `ConnectionOrigin::Stdio` and reads from process stdin/writes to process
  stdout
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/stdio.rs:24`).
- Codex live loaded threads are process-local. `ThreadManagerState` owns
  `threads: Arc<RwLock<HashMap<ThreadId, Arc<CodexThread>>>>`
  (`/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:200`).
- Each `ThreadManager::new` creates a fresh in-memory `HashMap`
  (`/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:279`).
- `thread/loaded/list` returns `self.thread_manager.list_thread_ids()`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1979`).
- `list_thread_ids()` reads that process-local map
  (`/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:958`).
- `get_thread()` also reads that process-local map and returns
  `ThreadNotFound` if the thread is absent
  (`/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:990`).
- `thread_resume_inner` first tries `resume_running_thread`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:2436`).
- `resume_running_thread` rejoins an already-running thread only if
  `self.thread_manager.get_thread(existing_thread_id)` succeeds in that same
  app-server process
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:2737`).

Meaning: an external client can attach only to a process that exposes a
connectable app-server transport and whose in-memory `ThreadManager` owns the
thread. A separate WebSocket app-server that does not have `eafd` loaded cannot
magically attach to the private stdio runtime that owns it.

## Dock Source Notes

- The relay treats `thread/detail/subscribe` as a live-owner-preferred method
  (`scripts/dock-relay-app-server-registry.mjs:31`).
- Only `thread/turns/list` is allowed to use history for private owners
  (`scripts/dock-relay-app-server-registry.mjs:47`).
- Process-discovered `stdio` endpoints are marked with failure reason
  `private_transport` and message
  `stdio app-server transport is private to its parent process`
  (`scripts/dock-relay-app-server-registry.mjs:302` and
  `scripts/dock-relay-app-server-registry.mjs:346`).
- The registry selects live endpoints only when they are `ws`/`wss` and not
  failed
  (`scripts/dock-relay-app-server-registry.mjs:313`).
- `privateLiveRows()` intentionally turns private owners into list rows with
  `source=cli`, active status, `endpointType=private`, `transport=stdio`,
  and `url=stdio://`
  (`scripts/dock-relay-app-server-registry.mjs:503`).
- `routeForThreadMethod()` rejects a private owner unless the method is
  explicitly history-safe for private owners
  (`scripts/dock-relay-app-server-registry.mjs:706`).
- The thrown error is exactly:
  `thread ${threadId} is owned by a private Codex runtime`, with reason
  `private_owner_unattachable`
  (`scripts/dock-relay-app-server-registry.mjs:711`).
- The list path merges private live rows into live rows:
  `mergePrivateLiveRows(live, config.appServerRegistry)`
  (`scripts/dock-relay-thread-data.mjs:87` and
  `scripts/dock-relay-thread-data.mjs:640`).
- The detail path calls `resumeThread(...)` before reading detail ledger for
  non-archived rows
  (`scripts/dock-relay.mjs:633` and `scripts/dock-relay.mjs:644`).
- `resumeThread()` calls `endpointForThread()` before it can initialize an
  upstream app-server client
  (`scripts/dock-relay.mjs:271`).
- `endpointForThread()` delegates to `routeForThreadMethod()`
  (`scripts/dock-relay-thread-data.mjs:1148`).
- The relay discovers private owners from Codex runtime processes:
  a Codex process without `app-server` args is treated as a runtime
  (`scripts/dock-relay-app-server-discovery.mjs:206`), `codex resume <id>` is
  parsed as an active private owner
  (`scripts/dock-relay-app-server-discovery.mjs:214`), and open session files
  are scanned with `lsof`
  (`scripts/dock-relay-app-server-discovery.mjs:355`).
- The Swift Dock row tap creates a `ThreadDetailStore` from the tapped row and
  resolved host
  (`CodexDock/Features/Dock/DockView.swift:659`).
- `ThreadDetailStore.load()` opens a
  `ThreadDetailProjectionStreamConnector` for `row.threadID`
  (`CodexDock/State/ThreadDetailStore.swift:246`).
- If the connector/reconciler fails, Swift sets `.error(header, message)`
  (`CodexDock/State/ThreadDetailStore.swift:300`).
- `SessionDetailView` renders that error as title `Thread unavailable`
  (`CodexDock/Features/Session/SessionDetailView.swift:76`).
- Swift uses the relay/app-server localized error description when available
  (`CodexDock/State/ThreadDetailStore.swift:847`).

Meaning: Swift is not inventing the private-runtime failure. It is faithfully
showing the relay error below a generic `Thread unavailable` title.

## Simulator Reproduction

Reproduced on simulator.

Steps:

1. Launch simulator app with real relay hosts:
   `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1 SIM_LAUNCH_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510'`.
2. Search Dock for `Snap hack`.
3. Confirm exactly one visible row:
   `codexdock.dock.row.Amir-M5.019e94b6-0f84-7881-8242-27ded669eafd`.
4. Confirm row shows `Codex is working`.
5. Tap row.
6. Observe detail screen:
   - title: `Snap hack`
   - thread id:
     `019e94b6-0f84-7881-8242-27ded669eafd`
   - host: `Amir-M5`
   - live state: `Stale`
   - status: `Codex is working`
   - error title: `Thread unavailable`
   - error message:
     `App-server rejected request: thread 019e94b6-0f84-7881-8242-27ded669eafd is owned by a private Codex runtime`
7. Capture proof with `rtk make sim-ui-dump ...`.

Artifact summary:

- `/tmp/codex-client/private-runtime-snap-hack-sim-ui-dump/sim-ui-dump.md`
  reports `status: pass`.
- `screen: thread -> thread`.
- `activeThreadID: 019e94b6-0f84-7881-8242-27ded669eafd`.
- `expectedThreadID: 019e94b6-0f84-7881-8242-27ded669eafd`.
- `detailMessages: 0`, `detailRequests: 0`, because the screen is an error
  state, not a streamed detail ledger.

## Root Cause Verdict

There are two different meanings of "live" in the current system:

1. List/live-row meaning: a Codex runtime process appears active for a thread.
   The relay can infer this from process args or open session files, even if the
   process is private.
2. Detail/attach meaning: the Dock can connect to an app-server owner and call
   live methods such as `thread/resume`, `thread/detail/subscribe`, and
   `thread/detail/resync`.

`Snap hack` satisfies the first meaning but not the second.

The exact failure chain is:

1. PID `60045` is running `codex -p yolo` and holds the `eafd` rollout file open.
2. The relay's process discovery records that as a private stdio owner.
3. The relay's list path merges that private owner into Dock rows as an active
   CLI row.
4. The app renders the row as `Codex is working`.
5. Tapping the row starts `thread/detail/subscribe`.
6. The relay first tries `thread/resume` for non-archived detail rows.
7. The router sees the private owner and rejects it with
   `private_owner_unattachable` because the owner is `stdio://` and not
   externally attachable.
8. Swift renders the rejected request as `Thread unavailable`.

This is why closing the original Codex session makes the badge/row go away: the
private owner evidence disappears. While the private process is open, the relay
has enough evidence to say "a Codex session exists", but not enough capability
to attach Dock detail to that session.

## Product Contract Gap

The current product contract is internally inconsistent:

- The list UI treats private `stdio://` ownership as enough to show
  `Codex is working`.
- The detail UI requires an attachable app-server owner.

The implementation is behaving as written. The bug is the capability mismatch
between what the row badge implies and what the detail path can actually do.

<!-- bugs:block:fix_plan -->
## Fix Plan

No fix plan selected because the user explicitly asked not to fix it in this
pass.

Selected follow-up fix:

- Stop labeling private-unattachable rows as fully `Codex is working`.
- Keep the rows visible as private diagnostics, but normalize them to Dock
  `unknown` so they do not show a running badge.
- Teach the relay to aggregate attachable Codex app-server transports
  (`unix`, `ws`, `wss`) through one owner-probe path while keeping private
  `stdio://` owners out of live/detail-capable status.
- Prefer attachable owner leases over private diagnostic evidence when both
  exist for the same thread.

<!-- bugs:block:implementation -->
## Implementation

The initial root-cause pass made no product code changes. The follow-up fix in
this branch changes the relay registry so Unix and WebSocket app-server owners
share one attachable owner-probe path, private-only rows normalize to Dock
`unknown`, and private evidence cannot block an attachable owner lease.

Only this worklog was created/updated:

`docs/bugs/private-codex-runtime-thread-detail-unavailable-2026-06-05.md`

## Verification Plan

- Query the live relay for the `Snap hack` Dock row and owner metadata.
- Call the same detail route the app uses and capture the returned failure.
- Read the Codex app-server source to determine which runtime owners are
  attachable from outside the original Codex process.
- Try to reproduce the same failed open path in the simulator.

Completed verification:

- Direct relay list/detail probe against
  `ws://amir-m5.fairy-salmon.ts.net:4510`.
- Direct route-health check through `/routesz`.
- Direct attachable-endpoint check against 11 WebSocket app-server endpoints.
- OS process ownership check with `lsof` and `ps`.
- Simulator reproduction on iPhone 17 simulator.
- Simulator artifact capture with `rtk make sim-ui-dump`.
- Dock relay, Swift detail, and upstream Codex app-server source-code reads.
