---
title: "Codex Dock - Canonical Codex App-Server Architecture - Architecture Plan"
date: 2026-05-29
status: active
fallback_policy: forbidden
owners: [Amir]
reviewers: [GBT55X-Hi, Opus Max, Codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_CODEX_APP_SERVER_END_TO_END_AUDIT.md
  - docs/CODEX_DOCK_THREAD_SORT_ROOT_CAUSE_2026-05-29_WORKLOG.md
  - .arch_skill/model-consensus/codex-dock-app-server-architecture-20260529T012239Z/
---

# TL;DR

Outcome:

Codex Dock will use one Mac-side Host Agent on `:4510` that is aligned with
Codex's real app-server model: history is the dashboard list source of truth,
live state decorates rows and routes focused sessions, and phones never touch
the raw authenticated app-server.

Problem:

The current relay path mixes history, live discovery, previews, scopes,
endpoint aliases, and per-row upstream WebSockets in request hot paths. That
created about 10,900 open relay-to-history WebSockets, `spawnSync ps EBADF`,
hidden live failures, duplicate host loads, stale-looking newest rows, and
cursor loss.

Approach:

Rebuild the relay as a Host Agent with four explicit pieces:
`HistoryClient`, `LiveStatusCache`, `SessionRouter`, and
`TranscriptionProxy`. Dashboard `thread/list` membership, order, and cursor
come from the Dock-owned history app-server at `ws://127.0.0.1:4500`; live
state may repaint status and diagnostics, but it must not move, filter, insert,
or page dashboard rows.

Plan:

First make the Host Agent's upstream connection model bounded and observable,
then make list semantics history-first and cursor-honest, then add background
live status, then repair host identity and device endpoint isolation, then add
ops probes and device/simulator proof.

Non-negotiables:

- Phone path is always relay `:4510`; raw `:4500` stays Mac-side.
- Raw app-server bearer tokens and `OPENAI_API_KEY` never reach simulator or
  phone.
- `thread/list` hard-clamps to `100`; the plan must not assume larger Codex
  pages.
- Endpoint aliases are ordered failover transports for one logical relay host,
  not separate hosts or separate load sources.
- A timed-out upstream JSON-RPC socket is untrusted and must be closed or
  terminated within a bounded deadline.
- Live discovery failure must be visible in response metadata and `/statusz`,
  not hidden behind plausible history-only rows.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-29
external_research_grounding: not started
deep_dive_pass_2: not started
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:da42313702ef36891ee14d7f3480ea891d4a22235826adb6d6ee00b42b4c828b",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-29T01:39:59Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:5fa94a51795652f08d7b2bd7dc7fb53b7d52dd0be7c9e8fc097f3360bc66c188",
      "completed_at": "2026-05-29T01:40:26Z",
      "doc_hash_after": "sha256:5f23285749ab5667b99de671ff4ba1acb284e6a82ac4cccda0c4e35ca9542921"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T01:40:37Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:5f23285749ab5667b99de671ff4ba1acb284e6a82ac4cccda0c4e35ca9542921",
      "completed_at": "2026-05-29T01:40:57Z",
      "doc_hash_after": "sha256:58d6d43ba08f708a474a855488e2b647dd3cfcb49063e1e514c8c7ad2a551667"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, repeated simulator and physical-phone reloads through the
Dock relay will keep upstream socket counts bounded, return dashboard rows in
history-plane newest order with honest pagination, surface live-status
degradation explicitly, and preserve separate endpoint profiles for the iPhone
17 Pro and iPhone 14.

This claim is false if:

- relay reloads grow relay-to-history WebSocket counts without bound;
- `thread/list` through relay silently drops Codex cursors;
- live discovery failure still looks like a healthy list response;
- endpoint aliases create multiple logical hosts for one relay;
- the iPhone 17 Pro local/Tailscale profile leaks into the iPhone 14 profile or
  vice versa;
- any phone receives a raw app-server token or `OPENAI_API_KEY`.

## 0.2 In scope

- Node Host Agent / relay data architecture under `scripts/dock-relay*.mjs`.
- Host service and generated app-safe config under `scripts/codex-dock-host-service*.mjs`
  and `Makefile`.
- Swift host identity, endpoint fallback, connectivity, list loading, and row
  projection under `CodexDock/Configuration/**`, `CodexDock/State/**`, and
  `CodexDock/AppServer/**`.
- Tests that prove relay behavior, Swift projection/config behavior, simulator
  behavior, and physical-device install/config readiness.
- Docs and AGENTS runbook updates where the shipped truth changes.

## 0.3 Out of scope

- Rewriting Codex itself in this repo.
- Sending phones directly to `ws://127.0.0.1:4500` or any raw authenticated
  app-server endpoint.
- Moving `OPENAI_API_KEY` or raw app-server bearer tokens into app launch env,
  simulator env, saved device config, Bonjour TXT records, or logs.
- Treating SwiftUI previews, mocks, loopback-only probes, or Unix sockets as
  physical-phone completion evidence.
- Creating a second planning source of truth outside this document.

## 0.4 Definition of done (acceptance evidence)

- `rtk npm run test:relay` proves connection pooling, timeout close/terminate,
  history-first list order, cursor honesty, live degraded metadata, and
  no per-row preview fanout in the hot path.
- `rtk swift test --filter DockStoreTests` proves logical-host grouping,
  fallback endpoints, degraded metadata mapping, and row projection.
- `rtk swift test --filter AppServerClientTests` proves DTO/client compatibility
  for new response metadata.
- `rtk make app-test SIM='iPhone 17'` proves the generated Xcode app path under
  the Makefile still builds and tests.
- Service proof shows `/statusz` exposes history health, live discovery health,
  upstream socket gauges, and fd/resource gauges without secrets.
- A leak check proves repeated relay `thread/list` calls do not grow
  relay-to-history socket counts.
- `rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`
  verifies the iPhone 17 Pro endpoint profile when that phone is available.
- `rtk make device-config-verify DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`
  verifies the iPhone 14 endpoint profile when that phone is available.

If physical-device automation is blocked by signing, device availability,
Mobile MCP, or macOS log permissions, the exact skipped command and exact
blocker are recorded, and simulator/service proof is used only for the part it
actually proves.

## 0.5 Key invariants (fix immediately if violated)

- Dashboard `thread/list` membership, order, and cursor are history-plane truth
  from `ws://127.0.0.1:4500`.
- Live status may repaint `status`, `attention`, `ownerEndpoint`, and
  degradation metadata only. It must not add, remove, move, filter, or page
  dashboard rows.
- Codex `thread/list` hard-clamps `limit` to `[1,100]`. Dock must never assume
  a larger page.
- The Host Agent forwards real history pagination cursors. It must never return
  `nextCursor: null` after reading a paginated upstream.
- Exactly one logical host exists per relay instance id.
- Endpoint aliases are ordered failover transports for that host, never
  separate hosts and never separate load sources.
- iPhone 17 Pro `CB9FFF0E-89AD-57B5-9C00-6552D814875E` uses the Tailscale
  endpoint profile: `amir-m5.fairy-salmon.ts.net:4510`,
  `home.fairy-salmon.ts.net:4510`.
- iPhone 14 `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC` uses the local endpoint
  profile: `Amir-M5.local:4510`, `192.168.50.74:4510`.
- The two device profiles are separate saved app configs and must not leak into
  each other.
- A timed-out upstream JSON-RPC socket is untrusted: it must be quarantined and
  closed or terminated within a bounded deadline.
- `ps` discovery is transitional only. It may feed `LiveStatusCache`, but it
  must be cached, bounded, visible in `/statusz`, and absent from dashboard
  request hot paths.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct Codex mental model: history plane for dashboard membership/order,
   live plane for runtime decoration and focused routing.
2. Bounded resource use: no per-row or per-request upstream socket storm.
3. Fail-loud diagnostics: degraded live state must be visible in app responses,
   logs, and status endpoints.
4. Device correctness: iPhone 17 Pro Tailscale config and iPhone 14 local config
   must remain intentionally different.
5. Makefile-owned operations: build, install, service, config, and diagnostics
   should be runnable through canonical `rtk make ...` targets.
6. Behavior preservation where Swift is already correct: keep rendering,
   search/filter/projection, and focused detail flow unless the new contract
   requires a change.

## 1.2 Constraints

- The raw Dock-owned history app-server is `ws://127.0.0.1:4500` and uses
  capability-token auth from `.codex-dock/app-server.token`.
- The phone-facing relay listens on `:4510`.
- Codex live app-server processes are process-local; `thread/loaded/list` is
  not a global recency index.
- Codex `thread/list` hard-clamps `limit` to `100`.
- Current live discovery can only discover a subset of live app-server shapes;
  it cannot see every stdio, Unix-socket, in-process, remote-control, or daemon
  mode.
- `.env` is user-owned; generated env belongs under `.codex-dock/`.

## 1.3 Architectural principles (rules we will enforce)

- One hot-path history request should not become N per-row or per-scope
  upstream sockets.
- The Host Agent owns Codex history/live aggregation semantics; Swift consumes
  one app-safe logical-host API.
- Status is decoration; recency order is not.
- Discovery is background state; dashboard requests do not run process scans.
- All secrets stay Mac-side.
- Diagnostics are product behavior, not ad hoc shell rescue.
- Clean cutover is preferred over runtime shims. No fallback path may hide
  broken live state or reintroduce endpoint-as-host behavior.

## 1.4 Known tradeoffs (explicit)

- Background live status can lag by one sweep, but it avoids pinning every
  Codex session loaded and protects Codex idle unload behavior.
- A single union `sourceKinds` query is simpler, but under Codex's `100` row cap
  it can starve one tab. Until honest pagination and per-tab coverage exist,
  dual scopes over the pooled `HistoryClient` are safer.
- Keeping the dedicated `:4500` history app-server means Dock still runs a
  Dock-owned app-server process, but it gives stable isolated history access
  without depending on the daemon's Unix socket lifecycle.
- `ps` discovery remains imperfect as a transitional scanner. The architecture
  requires it to be cached and visible, then eventually replaced by a
  Codex-native endpoint/session registry.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Codex Dock currently uses a Node Dock relay on `:4510` in front of a raw
Dock-managed history app-server on `ws://127.0.0.1:4500`. The relay also tries
to discover live Codex app-server processes by scanning local process command
lines for `codex app-server --listen ws://127.0.0.1:<port>`.

The Swift app can load multiple configured host endpoints, request multiple
scopes, project rows into UI sections, hide idle rows by default, and open
focused thread detail sessions through the relay.

## 2.2 What's broken / missing (concrete)

- The relay opens too many upstream WebSockets to the raw history app-server,
  especially during list preview enrichment.
- Timeouts and `close()` do not guarantee upstream sockets are closed or
  terminated.
- Live endpoint discovery runs in request paths and can fail with
  `spawnSync ps EBADF` under descriptor pressure.
- Normal `thread/list` hides live discovery failure and returns plausible
  history-only rows.
- Relay list merging currently lets live rows outrank fresher history rows.
- Relay pagination currently drops upstream cursor truth.
- Simulator/app config can treat endpoint aliases for one relay as separate
  logical hosts.
- Current docs and commands were already moving toward Makefile-owned
  workflows, but the architecture needs to make that the enforceable path.

## 2.3 Constraints implied by the problem

- The fix cannot be only Swift-side sorting; the relay must stop corrupting the
  data path.
- The fix cannot be only a restart; descriptor growth must be structurally
  impossible or bounded.
- The fix cannot make live discovery required for dashboard list correctness.
- The fix must preserve the phone-safe relay boundary and Mac-side secrets.
- The fix must make degraded state visible enough to debug from
  `rtk make ...` commands.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->

## 3.1 External anchors (papers, systems, prior art)

No external web research is required for the architecture decision. The
authoritative source is local Codex code plus this repo's runtime evidence.
The chosen pattern is a standard split between:

- authoritative persisted history,
- cached/background live status,
- focused live session routing,
- bounded connection pooling,
- explicit health and metrics endpoints.

The model-consensus run rejected importing a new broker or controller because
the current repo already owns the phone-safe boundary in the relay and the
requested robustness comes from clearer ownership, not a new system family.

## 3.2 Internal ground truth (code as spec)

Codex source of truth:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs`
  defines `stdio://`, `unix://`, `ws://IP:PORT`, and `off`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/auth.rs`
  and `websocket.rs` enforce non-loopback WebSocket auth.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs`
  defines `THREAD_LIST_MAX_LIMIT = 100`, request clamping, `thread/list`,
  `thread/read`, `thread/resume`, and `thread/loaded/list`.
  Research receipt anchors: `THREAD_LIST_MAX_LIMIT` is at line 7, direct
  `thread/list` clamping is at line 1817, search listing clamping is at line
  1897, and `thread/loaded/list` response cursor handling is at lines
  2004-2045.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs`
  overlays process-local loaded status onto persisted rows.
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs`
  owns process-local loaded thread IDs and session lifecycle.
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/list_threads.rs`
  owns persisted local thread listing.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
  owns the v2 thread DTO contract.
  Research receipt anchors: `ThreadListParams` is at line 937,
  `source_kinds` is at line 957, `use_state_db_only` is at line 970, and
  response cursor fields are at lines 1052 and 1057.

Codex Dock source of truth:

- `Makefile` owns services, simulator app build/install/test, physical device
  install/config/verify, and logging targets.
- `README.md` and `AGENTS.md` define the service path and physical iPhone
  endpoint expectations.
- `scripts/dock-relay.mjs` owns the phone-facing WebSocket relay, session
  upstream routing, transcription proxying, and HTTP health endpoints.
- `scripts/dock-relay-thread-data.mjs` owns current history/live aggregation,
  live endpoint discovery, preview enrichment, and merge behavior.
  Research receipt anchors: `discoverLoopbackEndpoints` is at line 249,
  `withClient` is at line 267, `mergeThreadListRows` is at line 458,
  `enrichThreadListPreviews` is at line 494, `aggregateThreadList` is at line
  532, and current `nextCursor: null` behavior is at line 598.
- `scripts/dock-relay-json-rpc-client.mjs` owns upstream JSON-RPC WebSocket
  connection lifecycle.
  Research receipt anchors: `JsonRpcWebSocketClient` starts at line 17,
  request timeout handling is at line 165, and `close()` calls `ws.close()` at
  lines 206-208.
- `scripts/codex-dock-host-service.mjs` owns launchd/systemd service rendering,
  generated host env, raw app-server token creation, and host-service status.
- `CodexDock/Configuration/HostRegistry.swift` and
  `RelayBootstrapStore.swift` own configured host/endpoints.
- `CodexDock/State/DockStore.swift` owns Swift session loading.
- `CodexDock/State/DockSessionProjection.swift` owns app-side search, sorting,
  grouping, and idle filtering.

Model consensus:

- Codex `gpt-5.5/xhigh` and Claude `opus/max` both signed off on the Host Agent
  split, history-first dashboard list, bounded upstream connections, background
  live status, alias-as-failover identity, and Makefile-owned ops.
- Required edits from consensus were incorporated: exact per-device endpoint
  profiles and the Codex `100` row cap plus pagination implications.

## 3.3 Decision gaps that must be resolved before implementation

None.

Implementation may discover code-level sequencing details, but the architecture
choices are settled:

- Keep dedicated Dock-owned `:4500` history anchor.
- Keep phone-facing Host Agent on `:4510`.
- Dashboard list membership/order/cursor are history-plane truth.
- Live state is repaint/routing metadata only for dashboard rows.
- Use dual scopes over the pooled `HistoryClient` until pagination guarantees
  per-tab coverage under the `100` row cap.
- Endpoint aliases are failover transports for one relay instance id.

<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->

## 4.1 On-disk structure

- `scripts/dock-relay.mjs`: relay entrypoint, downstream WebSocket handling,
  request dispatch, session upstream recovery, `/readyz`, `/healthz`, and
  `/statusz`.
- `scripts/dock-relay-thread-data.mjs`: current live endpoint discovery,
  history reads, preview enrichment, live aggregation, merge, archive, and turn
  list helpers.
- `scripts/dock-relay-json-rpc-client.mjs`: WebSocket JSON-RPC client used for
  upstream raw history and live app-server calls.
- `scripts/codex-dock-host-service*.mjs`: generated env and service manager
  install/start/status/doctor behavior.
- `CodexDock/AppServer/AppServerClient.swift`: Swift JSON-RPC client and DTO
  request path.
- `CodexDock/State/DockStore.swift`: multi-host and multi-scope session loading.
- `CodexDock/State/DockSessionProjection.swift`: UI sorting/filtering.
- `CodexDock/Configuration/HostRegistry.swift`: saved host identities and
  endpoints.

## 4.2 Control paths (runtime)

Current list path:

```text
Swift -> relay :4510 thread/list
relay -> raw history :4500 thread/list
relay -> ps scan for live endpoints
relay -> live endpoints thread/loaded/list + thread/read
relay -> per-row preview/turn calls
relay -> merge live/history rows
Swift -> projection/search/idle filtering/sort
```

Current focused detail path:

```text
Swift -> relay thread/read
Swift -> relay thread/turns/list
Swift -> relay thread/resume
relay -> selected upstream live endpoint or raw history endpoint
relay -> forwards live notifications and requests to Swift
```

## 4.3 Object model + key abstractions

- Codex `threadId` is the durable thread identity.
- Dock `hostId` is supposed to be logical host identity, but current endpoint
  alias handling can effectively turn endpoint strings into host identities.
- Codex `notLoaded` from `:4500` only means not loaded in the history app-server
  process; it does not prove the thread is inactive elsewhere.
- Swift projection currently treats `idle` as hidden by default.

## 4.4 Observability + failure behavior today

- Relay writes structured JSON logs to `.codex-dock/logs/dock-relay.err.log`.
- App logs use Apple unified logging subsystem `com.aelaguiz.CodexDock`.
- `/statusz` exists, but live failure is not attached to normal list responses.
- The descriptor leak was visible only through manual process inspection during
  the incident.
- `thread/list` can mask live failure by returning history-only rows.

## 4.5 UI surfaces (ASCII mockups, if UI work)

No new primary UI surface is required. Existing Dock list and connectivity
indicator remain, but the list needs a distinct connected-degraded state:

```text
[Online]        history and live overlay healthy
[Partial]       history healthy, live overlay degraded/stale
[Offline/Error] relay or selected host path unavailable
```

<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->

## 5.1 On-disk structure (future)

The implementation may split the current relay modules, but the canonical owner
remains `scripts/dock-relay*.mjs`:

- `HistoryClient`: pooled/multiplexed upstream access to `:4500`.
- `UpstreamConnectionPool`: bounded connection lifecycle, timeouts,
  quarantine, close/terminate, gauges.
- `LiveStatusCache`: cached discovery and read-only status sweeps.
- `SessionRouter`: focused detail `thread/resume` connection ownership and
  turn control routing.
- `TranscriptionProxy`: existing relay-side OpenAI Realtime ownership.
- `RelayStatusTracker`: redacted status, metrics, live overlay, and debug
  snapshot state.

Swift changes stay in the existing owner paths:

- `HostRegistry` / `RelayBootstrapStore`: relay instance id plus ordered
  endpoint fallback lists.
- `AppServerClient`: DTO support for relay metadata.
- `DockStore`: one logical host load path; dual scopes only over one logical
  host and one pooled Host Agent.
- `DockSessionProjection`: preserve UI projection, but make newest order
  deterministic and do not hide degradation state.

## 5.2 Control paths (future)

Dashboard list:

```text
Swift
  -> Host Agent :4510 thread/list
  -> HistoryClient pooled :4500 thread/list
  -> optional LiveStatusCache read from memory only
  -> response rows in history order + liveOverlay/degraded metadata
```

Live status cache:

```text
timer
  -> cached live endpoint discovery
  -> pooled live endpoint read-only calls
  -> threadId -> status/attention/ownerEndpoint table
  -> /statusz and thread/list liveOverlay
```

Focused detail:

```text
Swift opens thread detail
  -> SessionRouter chooses owner endpoint from LiveStatusCache or :4500
  -> thread/read includeTurns:false
  -> thread/turns/list limit:10
  -> thread/resume excludeTurns:true
  -> turn/start, turn/steer, turn/interrupt use that focused upstream
```

Physical phone:

```text
iPhone 17 Pro -> Tailscale endpoints -> Host Agent :4510
iPhone 14     -> Bonjour/LAN endpoints -> Host Agent :4510
```

No phone connects to `:4500`.

## 5.3 Object model + abstractions (future)

- `RelayInstanceID`: stable identity advertised by relay initialization,
  Bonjour TXT, and `/statusz`.
- `LogicalHost`: one relay instance plus an ordered endpoint fallback list.
- `HostScopedThreadID`: `(relayInstanceID, threadId)`.
- `LiveOverlay`: compact response metadata with `ok`, `ageMs`, endpoint counts,
  failure counts, and redacted error category.
- `HistoryCursor`: raw upstream cursor state from Codex history.
- `RelayCursor`: opaque cursor carrying per-scope history cursors, sort tuple,
  and live snapshot version when the Host Agent has to merge multiple scopes.

## 5.4 Invariants and boundaries

- Dashboard list membership and order are history-only.
- Live status never reorders dashboard rows.
- Focused detail may resume a thread and pin that one thread while open.
- Dashboard status sweeps must not use `thread/resume`; they use read-only
  calls so they do not keep every thread loaded.
- Under the `100` row cap, dual scopes over one pooled `HistoryClient` are the
  baseline until relay pagination guarantees per-tab coverage.
- A single union `sourceKinds` query is permitted only when pagination can
  guarantee per-tab coverage under the cap.
- `.env` remains user-owned; generated `.codex-dock/service.env` may contain
  Mac-side secrets; `.codex-dock/host.env` must stay app-safe.

## 5.5 UI surfaces (ASCII mockups, if UI work)

The Dock list stays the first screen. It needs a clear degraded live-overlay
state:

```text
Host: Amir-M5          Online
Rows: history current  Live: stale 12s, 1 endpoint failed

[Search] [Sort: Newest] [Idle]
Session rows...
```

This is status text/state, not a new landing page or marketing surface.

<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->

## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
|---|---|---|---|---|---|---|---|
| Relay upstream lifecycle | `scripts/dock-relay-json-rpc-client.mjs` | `JsonRpcWebSocketClient.request`, `close` | Timeout rejects request but can leave socket established; `close()` does not await close or force terminate | Add bounded close/terminate, timeout quarantine, pending rejection, observable state | Prevent descriptor leaks | `close({forceAfterMs})`, timeout marks socket unhealthy | Relay unit tests |
| Relay connection ownership | `scripts/dock-relay-thread-data.mjs` | `withClient`, history helpers | Opens fresh upstream WebSocket per operation | Replace with pooled `HistoryClient` and `UpstreamConnectionPool` | Bound upstream sockets | Pool keyed by endpoint URL | Relay unit, leak check |
| Dashboard list | `scripts/dock-relay-thread-data.mjs` | `aggregateThreadList` | Combines history, live discovery, previews, and merge in hot path | History-first response with live overlay from cache only | Make list correctness independent of live discovery | `liveOverlay` metadata | Relay unit, Swift DTO |
| Live discovery | `scripts/dock-relay-thread-data.mjs` | `discoverLoopbackEndpoints`, `collectLiveRows` | Runs `ps` and live calls from requests | Move to cached background `LiveStatusCache` | Avoid `spawnSync ps EBADF` in hot path | cache snapshot with age/failure | Relay unit/status tests |
| Merge/sort | `scripts/dock-relay-thread-data.mjs` | `mergeThreadListRows` | Live rows sorted separately and returned before history-only rows | Remove live-first ordering for dashboard; order from history, deterministic tie-break | Fix newest correctness | `updatedAt desc`, `threadId` tie-break | Relay property tests |
| Pagination | `scripts/dock-relay-thread-data.mjs` | response cursor handling | Drops upstream cursor | Forward or encode real cursors; never clobber to null | More than 100 rows exist | `RelayCursor` opaque payload | Relay pagination tests |
| Previews | `scripts/dock-relay-thread-data.mjs` | `enrichThreadListPreviews` | Per-row turn-list fanout in list path | Remove from hot path; lazy/bounded preview later | Stop multiplier | Deferred/lazy preview endpoint or field | Relay tests |
| Attention | `scripts/dock-relay-thread-data.mjs` | `enrichRowAttention`, `pendingRequestsForActiveThread` | May resume/watch per row | Remove from dashboard hot path | Avoid pinning sessions and fanout | LiveStatusCache active flags only | Relay tests |
| Relay status | `scripts/dock-relay.mjs` | `/statusz`, tracker | Some status exists, but list does not carry degradation | Add stable health, metrics, debug fields and `liveOverlay` | Make failures obvious | `/statusz`, `/metricsz`, `/debugz/sessions` | Relay status tests |
| Host service | `scripts/codex-dock-host-service.mjs` | `doctor`, `status` | Checks services and health | Add relay doctor/probe/leak-check support | Make ops Makefile-owned | redacted diagnostics | Node tests |
| Env generation | `scripts/codex-dock-host-service-env.mjs` | generated app-safe env | Only `CODEX_DOCK_HOSTS` app-safe | Preserve no-secret rule; add instance/fallback metadata only if non-secret | Keep secrets Mac-side | app-safe keys only | Node tests |
| Makefile | `Makefile` | service/app/device targets | Mostly canonical already | Add probe/leak/doctor/config-verify-all targets as needed | No raw Xcode/devicectl workflow | `rtk make ...` only | Command smoke |
| Swift DTO | `CodexDock/AppServer/AppServerMethods.swift`, `AppServerClient.swift` | thread/list response DTOs | No live overlay/cursor metadata awareness | Decode metadata without breaking existing fields | Show degraded state and pagination | `LiveOverlay`, cursor DTOs | `AppServerClientTests` |
| Connectivity state | `CodexDock/State/AppConnectivityStore.swift` | root status model | Existing states cover online/partial/stale/offline, but not necessarily relay live-overlay freshness | Map `liveOverlay` degradation into connected-but-partial/stale state | Prevent healthy-looking stale data | degraded live overlay status | `AppConnectivityStoreTests` |
| Host registry | `CodexDock/Configuration/HostRegistry.swift` | saved hosts/endpoints | Endpoint aliases can become separate hosts | Group endpoints by relay instance id, ordered fallback | Stop duplicate hosts/load | `LogicalHost` with endpoints | `DockStoreTests`, config tests |
| Bootstrap config | `CodexDock/Configuration/RelayBootstrapStore.swift` | saved relay config | Per-device configs exist but must stay isolated | Enforce iPhone 17 Pro Tailscale profile and iPhone 14 local profile | Test both configurations | profile-specific endpoint list | Device config tests |
| Store loading | `CodexDock/State/DockStore.swift` | scope/host loading | Loads scopes per configured host | Load once per logical host; dual scopes through one Host Agent until pagination covers tabs | Avoid alias multiplier | logical host load plan | `DockStoreTests` |
| Projection | `CodexDock/State/DockSessionProjection.swift` | newest sort, idle filter | UI projection after loading | Keep projection but respect history order semantics and degraded state | Avoid hiding root cause | deterministic tie-break | Projection tests |
| README/AGENTS | `README.md`, `AGENTS.md` | runbook | Partially updated | Align with final Makefile and architecture | Prevent stale operator guidance | canonical commands | Readback/status |

## 6.2 Migration notes

- Cleanly cut over relay list behavior; do not keep live-first list ordering as
  a fallback.
- Keep `thread/loaded/list` as a best-effort debug/diagnostic endpoint, not a
  dashboard correctness dependency.
- Delete or bypass hot-path preview enrichment. If previews remain, make them
  lazy, bounded, pooled, and not part of list correctness.
- Remove endpoint-derived host identity from Swift's logical host model.
- Keep dual scopes only as a coverage strategy under the `100` row cap, not as
  a socket or host multiplier.
- Update live docs and comments that imply `limit=200` is honored by Codex.
- Update AGENTS/README only after Makefile/source behavior is true.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
|---|---|---|---|---|
| Relay upstream calls | `scripts/dock-relay-thread-data.mjs` and `scripts/dock-relay.mjs` | pooled upstream client per endpoint URL | Prevent new one-off WebSocket helpers from bypassing the bounded pool | include |
| Relay logging | `scripts/dock-relay-logger.mjs` and `DockLog` | structured redacted diagnostics only | Keep secrets and payloads out of logs while making failure state visible | include |
| Service diagnostics | `scripts/codex-dock-host-service.mjs`, `Makefile` | Makefile-owned status/probe/doctor commands | Avoid raw Xcode/CoreDevice/service commands becoming the operator path | include |
| App host identity | `HostRegistry`, `RelayBootstrapStore`, `DockStore` | relay instance id plus ordered endpoint fallback list | Prevent alias-based duplicate hosts and multiplied loads | include |
| Connectivity UI state | `AppConnectivityStore`, Dock root indicator | connected-but-degraded live overlay state | Prevent history-healthy/live-stale from looking fully healthy | include |
| Physical config | `Makefile` device variables and device config targets | per-device endpoint profiles | Preserve iPhone 17 Pro Tailscale vs iPhone 14 local separation | include |
| Preview text | list rows and future detail/viewport preview path | lazy/bounded preview outside dashboard correctness | Avoid returning to per-row list fanout | defer until after history-first list |
| Codex-native registry | `/Users/aelaguiz/workspace/codex` app-server/daemon code | first-class endpoint/session registry | Ideal long-term replacement for `ps`; outside this repo's immediate implementation | exclude from current repo implementation |

<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

<!-- arch_skill:block:phase_plan:start -->

## Phase 1 - Bounded Upstream Substrate

Goal:

Make upstream socket growth structurally bounded before changing higher-level
list semantics.

Work:

Introduce a pooled upstream connection substrate for history and live endpoint
calls, and harden JSON-RPC socket timeout/close behavior.

Checklist (must all be done):

- Add `UpstreamConnectionPool` or equivalent inside `scripts/dock-relay*.mjs`.
- Route history calls through one pooled/multiplexed `HistoryClient`.
- Make request timeout quarantine the socket.
- Make `close()` wait for close or terminate after a bounded deadline.
- Expose open upstream socket counts in relay status.

Verification (required proof):

- Relay unit tests for timeout teardown, close force termination, and pool
  max-open behavior.
- Leak-check proof that repeated list requests keep upstream connection count
  flat.

Docs/comments (propagation; only if needed):

- Add a short code comment at the pool boundary explaining that JSON-RPC is
  multiplexed and per-row sockets are forbidden.

Exit criteria (all required):

- No list-path code opens a fresh history WebSocket per row.
- Timed-out sockets cannot remain silently healthy.
- `/statusz` exposes upstream socket counts.

Rollback:

- Revert the pool and restore old direct clients only if tests show functional
  regression before any list semantic phase lands.

## Phase 2 - History-First Dashboard List And Cursor Honesty

Goal:

Make `thread/list` through the relay correct even when live discovery is down.

Work:

Rewrite dashboard list aggregation so history supplies membership, order, and
cursor. Live status is not consulted for ordering or pagination.

Checklist (must all be done):

- Remove live-first list ordering.
- Remove list-time per-row preview enrichment.
- Remove list-time per-row attention/resume probing.
- Preserve or encode real upstream cursor state.
- Add deterministic `updatedAt desc`, `threadId` tie-break where relay sorting
  is required.
- Encode the Codex `100` row cap in tests/docs where assumptions matter.

Verification (required proof):

- Relay unit tests prove live overlay changes cannot change dashboard row order
  or membership.
- Relay pagination tests prove `nextCursor` is not clobbered to null.
- Same-second timestamp tests prove deterministic ordering.

Docs/comments (propagation; only if needed):

- Update comments/docs that imply `limit=200` is honored by Codex.

Exit criteria (all required):

- Relay top-row recency matches raw history for the same scope under
  `relay-probe`.
- More-than-100 thread datasets retain cursor access to the tail.
- Dashboard list succeeds with explicit degraded metadata when live discovery
  fails.

Rollback:

- Revert list semantics as one unit if history-first ordering breaks DTO
  compatibility before Swift updates are in place.

## Phase 3 - LiveStatusCache And Degraded State

Goal:

Restore live status and routing information without making dashboard list
correctness depend on live discovery.

Work:

Add cached background live discovery/status sweeps and attach compact
`liveOverlay` metadata to list responses and `/statusz`.

Checklist (must all be done):

- Move `ps` discovery out of dashboard request hot paths.
- Add bounded/cached live endpoint scanner.
- Add pooled read-only status sweeps.
- Add `liveOverlay` response metadata.
- Keep dashboard sweeps read-only; do not use `thread/resume` for all loaded
  sessions.
- Preserve focused `SessionRouter` resume behavior for open details.

Verification (required proof):

- Relay tests prove live discovery failure returns degraded metadata instead of
  silent history-only success.
- Relay status tests prove `/statusz` includes age, endpoints, failures, and
  redacted error categories.
- Thread detail tests prove focused resume and turn control still route.

Docs/comments (propagation; only if needed):

- Comment the boundary between read-only status sweeps and focused resume.

Exit criteria (all required):

- Dashboard list requests do not call `ps`.
- `/statusz` makes live status freshness and discovery failure obvious.
- Focused detail still reconnects or fails loudly.

Rollback:

- Disable the status sweep while preserving history-first list behavior if live
  cache behavior is faulty.

## Phase 4 - Logical Host Identity And Device Profiles

Goal:

Stop endpoint aliases and device configs from multiplying load or leaking across
phones.

Work:

Introduce stable relay instance identity and ordered endpoint fallback lists in
Swift and generated config.

Checklist (must all be done):

- Relay advertises stable non-secret instance id via initialization, Bonjour TXT,
  and `/statusz`.
- Swift groups endpoints by relay instance id.
- Endpoint aliases are stored as ordered fallback transports.
- iPhone 17 Pro profile remains Tailscale-only.
- iPhone 14 profile remains local/Bonjour/LAN-only.
- Add Makefile verification for all known device configs where feasible.

Verification (required proof):

- Swift tests prove three aliases for one relay produce one logical host.
- Config tests prove the two physical device profiles stay separate.
- Simulator proof shows one logical host even when multiple endpoints are
  configured.

Docs/comments (propagation; only if needed):

- Update README/AGENTS if command names or endpoint expectations change.

Exit criteria (all required):

- App loads once per logical host, not once per alias.
- Device config verify commands read back the exact expected endpoint list when
  the device is available.

Rollback:

- Roll back Swift grouping only if config migration blocks launch, while
  keeping relay Host Agent semantics intact.

## Phase 5 - Ops, Probes, And Final Verification

Goal:

Make failures obvious and the Makefile the only normal operation surface.

Work:

Add probe, leak-check, doctor, config verify, and log/status commands that prove
the architecture from the outside.

Checklist (must all be done):

- Add `rtk make relay-probe` or equivalent target.
- Add `rtk make relay-leak-check` or equivalent target.
- Add `rtk make relay-doctor` or extend `host-service-doctor`.
- Add config verify-all target if device tooling supports it.
- Ensure app/device/simulator build/install/test paths remain Makefile-owned.
- Update docs to remove stale raw Xcode/devicectl workflow guidance.

Verification (required proof):

- `rtk npm run test:relay`.
- `rtk swift test --filter AppServerClientTests`.
- `rtk swift test --filter DockStoreTests`.
- `rtk make app-test SIM='iPhone 17'`.
- Service status/probe/leak commands succeed or report exact environmental
  blockers.

Docs/comments (propagation; only if needed):

- README and AGENTS match Makefile and shipped behavior.

Exit criteria (all required):

- All planned checks either pass or have exact recorded environmental blockers.
- No normal workflow requires raw `xcodebuild`, raw `devicectl`, or raw
  `simctl install`.
- No secrets appear in app env, saved phone config, Bonjour TXT, or logs.

Rollback:

- Revert individual Makefile diagnostics if they fail independently, but do not
  remove service/app/device canonical targets.

<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Unit tests (contracts)

- Relay tests for pooled upstream connection count, timeout termination,
  history-first ordering, cursor forwarding, live degraded metadata, and
  no per-row preview/attention hot-path fanout.
- Swift client tests for metadata decoding and backward-compatible DTO behavior.
- Swift store/config tests for logical host grouping, endpoint fallback order,
  device profile isolation, and degraded connectivity state.

## 8.2 Integration tests (flows)

- `rtk make services`.
- `rtk make app-server-status`.
- `rtk make dock-relay-status`.
- `rtk make host-service-doctor` or `rtk make relay-doctor`.
- Relay probe comparing raw `:4500` recency with relay `:4510` recency.
- Relay leak check across repeated list calls.

## 8.3 E2E / device tests (realistic)

- `rtk make app-test SIM='iPhone 17'` for generated Xcode app test path.
- `rtk make app SIM='iPhone 17'` when installed simulator behavior matters.
- `rtk make device-install DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`
  only when the iPhone 17 Pro is available and Amir is not using it.
- `rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`
  for iPhone 14 local endpoint proof.
- Physical Mobile MCP is not required unless the user explicitly asks in that
  turn. If `WebDriverAgent is not running on device`, stop retrying physical
  Mobile MCP and record the exact blocker.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Use clean cutover inside this local repo. Do not keep the old live-first merge
or endpoint-as-host behavior as a runtime fallback. Phase order should preserve
working service startup and app launch after each slice.

## 9.2 Telemetry changes

Relay logs and status must include redacted:

- `requestId`
- `method`
- `logicalHostId`
- `historyRows`
- `liveRows`
- `returnedRows`
- `historyLatencyMs`
- `liveLatencyMs`
- `liveOverlay.ok`
- `liveOverlay.ageMs`
- `failedLiveEndpoints`
- `cursorPresent`
- `upstreamSocketCount`
- `fdCount`
- `cacheAgeMs`

Never log `OPENAI_API_KEY`, bearer tokens, raw prompt text, transcript text, raw
audio bytes, base64 audio, or full JSON-RPC payloads.

## 9.3 Operational runbook

Canonical commands remain Makefile-owned:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make host-service-doctor
rtk make app SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>
rtk make device-install-all
rtk make device-config-verify DEVICE=<device-udid>
```

New or extended diagnostic commands should cover:

```bash
rtk make relay-probe
rtk make relay-leak-check
rtk make relay-doctor
rtk make device-config-verify-all
rtk make sim-config-verify SIM='iPhone 17'
```

# 10) Decision Log (append-only)

## 2026-05-29 - Model consensus architecture

Context:

The user requested a model consensus between GBT55X-Hi and Opus for Max before
planning or implementation.

Options:

- Patch current relay behavior in place.
- Replace the relay entirely.
- Keep the relay boundary but rebuild it as a disciplined Host Agent aligned
  with Codex history/live planes.

Decision:

Keep the relay boundary and rebuild its data model as a Host Agent with
`HistoryClient`, `LiveStatusCache`, `SessionRouter`, and `TranscriptionProxy`.

Consequences:

The relay remains the phone-safe `:4510` boundary, but dashboard ordering and
pagination move to history-first semantics, live state becomes decoration and
focused routing metadata, and upstream sockets must be pooled and bounded.

Follow-ups:

Run ArcStep AutoPlan, plan audit, implementation, Composer 2.5 Fast audit,
implementation audit, and thermonuclear review.

## 2026-05-29 - Intent-derived: North Star active after model alignment

Blocker:

ArchStep's normal `new` command stops for North Star confirmation, but the user
explicitly requested that once the two models were aligned on the architecture
document, the work should proceed to ArcStep AutoPlan.

Consulted:

TL;DR, Section 0, model-consensus round 02 outputs, and the original objective.

Intent says:

The user wanted model agreement on the architecture document before planning,
not a separate pause after consensus.

Decision:

Mark this document `status: active` because both named models converged with
required edits and those edits were incorporated.

Consequences:

ArcStep AutoPlan may proceed against this document without waiting for an
additional confirmation turn.

## 2026-05-29 - History-first dashboard list

Context:

Current relay merge behavior can place stale live rows above fresher history
rows and can hide live discovery failure.

Options:

- Globally sort merged live/history rows after dedupe.
- Make dashboard membership, ordering, and cursor pure history truth and let
  live state repaint only.

Decision:

Dashboard membership, ordering, and cursor are history-plane truth. Live state
may repaint metadata only.

Consequences:

This prevents live discovery and live status bugs from corrupting dashboard
recency. Focused detail remains the place where live session routing and resume
semantics matter.

## 2026-05-29 - Codex 100-row cap and scope strategy

Context:

Consensus round 02 verified Codex `thread/list` hard-clamps `limit` to `100`.
Dock's request for `200` rows does not produce 200 rows from one Codex scope.

Options:

- Use one union `sourceKinds` query immediately.
- Keep dual scopes until relay pagination guarantees per-tab coverage.

Decision:

Dual scopes over one pooled `HistoryClient` are the baseline until honest relay
pagination guarantees per-tab coverage under the `100` row cap. A single union
query is allowed only after that guarantee exists.

Consequences:

Scopes may remain as a coverage tool, but they cannot multiply upstream sockets
or logical hosts.

## 2026-05-29 - Device endpoint profiles

Context:

The iPhone 17 Pro is on Tailscale and the iPhone 14 is not on Tailscale.

Options:

- Collapse both devices into one endpoint profile.
- Keep separate per-device profiles.

Decision:

Keep separate per-device profiles:

- iPhone 17 Pro `CB9FFF0E-89AD-57B5-9C00-6552D814875E`:
  `amir-m5.fairy-salmon.ts.net:4510`, `home.fairy-salmon.ts.net:4510`.
- iPhone 14 `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`:
  `Amir-M5.local:4510`, `192.168.50.74:4510`.

Consequences:

The two configs become an explicit test of whether Codex Dock supports different
physical-device network profiles without hard-coded host assumptions.
