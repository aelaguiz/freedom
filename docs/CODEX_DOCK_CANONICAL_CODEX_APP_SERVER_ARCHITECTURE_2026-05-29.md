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
external_research_grounding: done 2026-05-29
deep_dive_pass_2: done 2026-05-29
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:c9e58fac92eba870e0dc749b8becf359e8f9932c0d6a400607bc046e9a49468f",
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
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T01:43:03Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:58d6d43ba08f708a474a855488e2b647dd3cfcb49063e1e514c8c7ad2a551667",
      "completed_at": "2026-05-29T01:43:56Z",
      "doc_hash_after": "sha256:acddd2f66168fd9cf2e1b504d5a5f43ada8063d453ac1b466f92da6056bf68da"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-29T01:44:15Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:acddd2f66168fd9cf2e1b504d5a5f43ada8063d453ac1b466f92da6056bf68da",
      "completed_at": "2026-05-29T01:44:52Z",
      "doc_hash_after": "sha256:bec826c4eae1c50964c972d4133fda7f4ab81f5a564a938b89ae9514fcb1f9f7"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-29T01:45:19Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:bec826c4eae1c50964c972d4133fda7f4ab81f5a564a938b89ae9514fcb1f9f7",
      "completed_at": "2026-05-29T01:48:56Z",
      "doc_hash_after": "sha256:7ad5baa231af1f5368d8b9fbad2ffca4b01ea98fd7684f8f64721aefebfb569d"
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
  upstream socket gauges, fd/resource gauges, `/metricsz`, and
  `/debugz/sessions` without secrets.
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
- `ps` discovery must run only inside the `LiveStatusCache` refresh boundary,
  never directly inside `thread/list`, `thread/loaded/list`, `thread/read`,
  `thread/turns/list`, `thread/archive`, `thread/resume`, or shared endpoint
  lookup helpers.
- Compatibility posture: clean cutover for relay list semantics and logical
  host identity. No runtime fallback to live-first merge, endpoint-as-host
  behavior, or old relay response semantics is approved. App-visible DTO
  compatibility is preserved by keeping existing required row fields stable and
  adding optional relay metadata/cursor fields, with matching Swift DTO changes
  landing in the same phase before the relay response is considered stable.
- Relay identity source: generated app-safe config is the canonical identity
  source before network probing. `.codex-dock/host.env` carries
  `CODEX_DOCK_RELAY_INSTANCE_ID=<CODEX_DOCK_REAL_HOST_ID>`, and physical
  `relay-config.json` carries `"relayInstanceID"`. `initialize`, Bonjour TXT
  `relay-id`, and `/statusz` must echo the same non-secret value for
  verification. Swift groups configured aliases by that configured
  `RelayInstanceID`; if a reachable alias reports a different id, the logical
  host becomes config-error/degraded instead of splitting into multiple hosts.
- HTTP diagnostic access: `/readyz`, `/healthz`, and public `/statusz` are
  app-safe and redacted. `/metricsz` and `/debugz/sessions` are loopback-only
  diagnostic endpoints reached by Makefile probes on the Mac side; they are not
  phone-facing or Tailscale-public surfaces.
- App-facing config must reject raw app-server endpoints. `:4500` and any
  raw-authenticated app-server URL are allowed only for Mac-side service internals
  and explicit local test harnesses, never for generated simulator config,
  physical device config, saved app config, Bonjour discovery, or manual Host
  Settings entries.

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
- `scripts/dock-relay-status.mjs` owns current relay status tracking. Deep-dive
  pass 2 anchors: `createRelayStatusTracker` starts at line 61, raw history
  health is recorded at line 87, live discovery health at line 94, upstream
  errors at line 101, and the current status snapshot is assembled at lines
  130-180. Today it exposes broad status and active downstream/upstream counts,
  but it does not yet expose pool-level socket gauges, fd counts, `/metricsz`,
  `/debugz/sessions`, or list-response `liveOverlay` metadata.
- `scripts/codex-dock-host-service.mjs` owns launchd/systemd service rendering,
  generated host env, raw app-server token creation, and host-service status.
- `scripts/codex-dock-host-service-env.mjs` currently treats only
  `CODEX_DOCK_HOSTS` as app-safe (`APP_SAFE_EXACT_ENV_KEYS` at lines 12-14),
  strips old app credential keys at lines 94-105, writes host-side
  `.codex-dock/service.env` with possible Mac-side `OPENAI_API_KEY` at lines
  108-145, and writes app-facing `.codex-dock/host.env` with only app-safe keys
  at lines 148-182.
- `Makefile` already contains exact physical-device profiles:
  `IPHONE_17_PRO_DEVICE` and `IPHONE_17_PRO_RELAY_ENDPOINTS` at lines 47-48,
  and `IPHONE_14_DEVICE` and `IPHONE_14_RELAY_ENDPOINTS` at lines 49-50.
  `device-install` uses a fresh build by default and then configures/launches
  the device at lines 168-170; `device-install-all` calls both device profiles
  at lines 172-174; `device-config-verify` reads back saved app config at
  lines 179-180. Current `.PHONY` entries at line 65 do not yet include
  `relay-probe`, `relay-leak-check`, `relay-doctor`, or
  `device-config-verify-all`.
- `CodexDock/Configuration/HostRegistry.swift` and
  `RelayBootstrapStore.swift` own configured host/endpoints.
  `HostRegistry.fromEnvironment` currently maps every `CODEX_DOCK_HOSTS`
  endpoint to its own `DockHostConfiguration` at lines 24-30, and
  `CodexDockTests/DockConfigurationTests.swift` currently asserts that
  `192.168.50.117:4510, home.local:4511` produces two host ids at lines 49-59.
  That is the concrete endpoint-as-host behavior the implementation must
  replace with logical relay identity plus ordered fallback endpoints.
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
- `RelayStatusTracker` records raw history health, live discovery status,
  last upstream/client/transcription errors, reconnect state, and active
  connection counts, but it does not yet separate history-pool sockets from
  live-pool sockets or report fd/resource pressure.
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

Swift changes stay in the existing owner paths, but the identity migration has
to reach every live reader/writer of configured hosts:

- `DockRelayEndpoint` / `DockHostConfiguration`: validate app-facing relay
  endpoints, reject raw `:4500`, and model one logical host with fallback
  endpoints instead of one host per endpoint.
- `HostRegistry` / `RelayBootstrapStore`: relay instance id plus ordered
  endpoint fallback lists.
- `RelayDiscovery` / `LocalRelayEndpointList`: carry `relayInstanceID` from
  saved config and Bonjour TXT, and persist fallback endpoints under one logical
  host.
- `HostSettingsStore` / `HostsView`: edit one logical host's fallback endpoints
  without creating endpoint-as-host rows.
- `AppServerClient`: DTO support for relay metadata.
- `DockStore` / `ArchiveStore`: one logical host load/restore path; dual scopes
  only over one logical host and one pooled Host Agent.
- `DockLoadResult` / `SessionSummaryMapper` / `DockHostLoadStatus` /
  `AppConnectivityStore`: preserve cursors and live-overlay degradation beyond
  DTO decode so UI state cannot look healthy when live overlay is stale.
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

- `RelayInstanceID`: stable non-secret identity generated into app-safe config
  before probing and echoed by relay initialization, Bonjour TXT `relay-id`, and
  `/statusz`.
- `LogicalHost`: one relay instance plus an ordered endpoint fallback list.
- `HostScopedThreadID`: `(relayInstanceID, threadId)`.
- `LiveOverlay`: compact response metadata with `ok`, `ageMs`, endpoint counts,
  failure counts, and redacted error category. Phase 2 returns a minimal
  non-healthy overlay state such as `disabled` / `unavailable`; Phase 3 upgrades
  it from `LiveStatusCache`.
- `HistoryCursor`: raw upstream cursor state from Codex history.
- `RelayCursor`: opaque cursor carrying per-scope history cursors, sort tuple,
  and live snapshot version when the Host Agent has to merge multiple scopes.
- `RelayStatusStore`: one internal owner for relay health, counters, live-cache
  age, pool gauges, fd/resource gauges, and focused-session state.
- `StatuszSnapshot`: app-safe public health projection. Allowed fields:
  service/version, relay instance id, listen port, history health category,
  live overlay freshness category, pool counts by label, and redacted latest
  error category.
- `MetricsSnapshot`: loopback-only counters/gauges. Allowed fields:
  request counters, error counters, pool socket gauges, fd/resource gauges,
  cache age, and latency histograms without thread IDs, prompts, transcripts,
  tokens, or endpoint credentials.
- `DebugSessionsSnapshot`: loopback-only focused-session projection. Allowed
  fields: hashed/truncated thread/session ids, owner endpoint category, state,
  age, reconnect attempts, and redacted error category. It must not include full
  JSON-RPC payloads, prompt text, transcript text, raw audio, bearer tokens, or
  OpenAI keys.

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
| Previews | `scripts/dock-relay-thread-data.mjs` | `enrichThreadListPreviews` | Per-row turn-list fanout in list path | Delete relay list-time enrichment and preserve Codex history `Thread.preview` from `thread/list` | Stop multiplier while preserving native Codex preview display | history preview passthrough only | Relay/Swift mapping tests |
| Attention | `scripts/dock-relay-thread-data.mjs` | `enrichRowAttention`, `pendingRequestsForActiveThread` | May resume/watch per row | Remove from dashboard hot path | Avoid pinning sessions and fanout | LiveStatusCache active flags only | Relay tests |
| Relay status | `scripts/dock-relay.mjs` | `/statusz`, tracker | Some status exists, but list does not carry degradation | Add public `/statusz`, loopback-only `/metricsz`, loopback-only `/debugz/sessions`, and `liveOverlay` | Make failures obvious without exposing debug data | `StatuszSnapshot`, `MetricsSnapshot`, `DebugSessionsSnapshot`, `LiveOverlay` | Relay status/security tests |
| Relay status tracker | `scripts/dock-relay-status.mjs` | `createRelayStatusTracker`, `snapshot` | Tracks broad health/errors and active connection counts only | Make it the internal store with narrow projections for status, metrics, debug, and list overlay | Avoid split-brain diagnostics and app-facing DTO bloat | `RelayStatusStore` projection methods | Relay status/metrics/debug tests |
| Host service | `scripts/codex-dock-host-service.mjs` | `doctor`, `status` | Checks services and health | Add relay doctor/probe/leak-check support | Make ops Makefile-owned | redacted diagnostics | Node tests |
| Env generation | `scripts/codex-dock-host-service-env.mjs` | generated app-safe env | Only `CODEX_DOCK_HOSTS` app-safe | Preserve no-secret rule; add `CODEX_DOCK_RELAY_INSTANCE_ID` only | Keep secrets Mac-side while giving Swift a grouping key before probing | app-safe keys only | Node tests |
| Makefile | `Makefile` | service/app/device targets | Mostly canonical already | Add `relay-probe`, `relay-leak-check`, `relay-doctor`, `device-config-verify-all`, and `sim-config-verify` targets | No raw Xcode/devicectl workflow | `rtk make ...` only | Command smoke |
| Swift DTO | `CodexDock/AppServer/AppServerMethods.swift`, `AppServerClient.swift` | thread/list response DTOs | No live overlay/cursor metadata awareness | Decode optional `liveOverlay` and preserve cursor metadata without breaking existing row fields | Show degraded state and pagination | `LiveOverlay`, cursor DTOs | `AppServerClientTests` |
| Relay endpoint validation | `DockRelayEndpoint`, `DockHostConfiguration`, `HostSettingsStore`, Makefile device/sim config writers | endpoint parse/save paths | Any syntactically valid port, including `4500`, can be app-facing | Reject raw `:4500` and raw app-server URLs from app-facing config; keep explicit loopback test exceptions local only | Enforce phone-safe relay boundary | app-safe relay endpoint validator | Config/Makefile tests |
| Response metadata propagation | `ThreadListResponseDTO`, `AppServerDockClient`, `DockLoadResult`, `SessionSummaryMapper`, `DockStore`, `DockHostLoadStatus`, `AppConnectivityStore` | list response mapping | Cursors decode but are dropped after DTO mapping; degraded metadata does not exist | Carry cursor and `liveOverlay` from DTO to store snapshot/connectivity | Prevent healthy-looking stale data and make pagination usable | paged/degraded load result | `AppServerClientTests`, `DockStoreTests`, `AppConnectivityStoreTests` |
| Host registry | `DockRelayEndpoint`, `DockHostConfiguration`, `HostRegistry`, `RelayBootstrapStore`, `RelayDiscovery`, `LocalRelayEndpointList`, `HostSettingsStore`, `HostsView`, `CodexDockRootView`, `DockStore`, `ArchiveStore` | saved hosts/endpoints and root propagation | Endpoint aliases can become separate hosts across Dock, Archive, settings, and discovery | Group endpoints by configured relay instance id, then validate echoed id from reachable aliases | Stop duplicate hosts/load before probing | `LogicalHost` with endpoint fallbacks | `DockStoreTests`, `ArchiveStoreTests`, config tests |
| Bootstrap config | `CodexDock/Configuration/RelayBootstrapStore.swift` | saved relay config | Per-device configs exist but must stay isolated | Add saved `relayInstanceID`, enforce iPhone 17 Pro Tailscale profile and iPhone 14 local profile | Test both configurations | profile-specific endpoint list + id | Device config tests |
| Store loading | `CodexDock/State/DockStore.swift`, `CodexDock/State/ArchiveStore.swift` | scope/host loading | Loads scopes per configured host with one `limit=200` page | Request `limit=100`, preserve/use cursors, and expose app-side next-page loading per logical host/scope where lists page | Avoid alias multiplier and make >100 tails reachable | logical host paged load plan | `DockStoreTests`, `ArchiveStoreTests` |
| Projection | `CodexDock/State/DockSessionProjection.swift` | newest sort, idle filter | UI projection after loading | Keep projection but respect history order semantics and degraded state | Avoid hiding root cause | deterministic tie-break | Projection tests |
| README/AGENTS | `README.md`, `AGENTS.md` | runbook | Partially updated | Align with final Makefile and architecture | Prevent stale operator guidance | canonical commands | Readback/status |

## 6.2 Migration notes

- Cleanly cut over relay list behavior; do not keep live-first list ordering as
  a fallback.
- Compatibility posture: relay dashboard semantics are a clean cutover away from
  live-first ordering; the wire DTO preserves existing required fields and adds
  optional `liveOverlay` / cursor metadata. Relay and Swift DTO changes land in
  the same phase. No old live-first or old-shape runtime fallback remains.
- Keep `thread/loaded/list` as a best-effort debug/diagnostic endpoint, not a
  dashboard correctness dependency.
- Delete hot-path preview enrichment. Preserve row preview display by passing
  through Codex's native history `Thread.preview`; a new lazy enriched-preview
  endpoint is out of scope for this plan.
- Use app-safe config as the canonical source for logical relay identity before
  probing. Runtime `initialize`, Bonjour TXT, and `/statusz` are consistency
  checks, not the first grouping source.
- Remove endpoint-derived host identity from Swift's logical host model.
- Migrate every app-side host reader/writer together: discovery, saved config,
  bootstrap, manual settings, root store propagation, Dock, Archive, restore
  routing, connectivity, and tests. Do not leave Archive or settings as
  endpoint-as-host side doors.
- Reject raw `:4500` from generated host env, simulator/device saved config,
  manual Host Settings, saved config migration, and known-device config targets.
  Test harnesses that intentionally use raw loopback must use explicit test-only
  helpers outside app-facing config.
- Keep dual scopes only as a coverage strategy under the `100` row cap, not as
  a socket or host multiplier.
- Preserve cursor state through the Swift loading boundary. The app must not
  treat a single `100`-row page as the whole dashboard when Codex returns a
  cursor.
- Update live docs and comments that imply `limit=200` is honored by Codex.
- Update AGENTS/README only after Makefile/source behavior is true.
- Remove or demote `npm run dock-relay` as a normal operator path; Makefile
  targets are the runnable source of truth.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
|---|---|---|---|---|
| Relay upstream calls | `scripts/dock-relay-thread-data.mjs` and `scripts/dock-relay.mjs` | pooled upstream client per endpoint URL | Prevent new one-off WebSocket helpers from bypassing the bounded pool | include |
| Relay logging | `scripts/dock-relay-logger.mjs` and `DockLog` | structured redacted diagnostics only | Keep secrets and payloads out of logs while making failure state visible | include |
| Relay status | `scripts/dock-relay-status.mjs` | one internal status store with narrow projections for status, metrics, debug, and list overlay | Prevent split-brain diagnostics without leaking broad debug state to app DTOs | include |
| Service diagnostics | `scripts/codex-dock-host-service.mjs`, `Makefile` | Makefile-owned status/probe/doctor commands | Avoid raw Xcode/CoreDevice/service commands becoming the operator path | include |
| App host identity | `HostRegistry`, `RelayBootstrapStore`, `DockStore` | relay instance id plus ordered endpoint fallback list | Prevent alias-based duplicate hosts and multiplied loads | include |
| App host side doors | `RelayDiscovery`, `LocalRelayEndpointList`, `HostSettingsStore`, `HostsView`, `CodexDockRootView`, `ArchiveStore`, `AppConnectivityStore` | same `LogicalHost` model as Dock | Prevent settings/archive/connectivity from preserving endpoint-as-host behavior | include |
| Connectivity UI state | `AppConnectivityStore`, Dock root indicator | connected-but-degraded live overlay state | Prevent history-healthy/live-stale from looking fully healthy | include |
| Physical config | `Makefile` device variables and device config targets | per-device endpoint profiles | Preserve iPhone 17 Pro Tailscale vs iPhone 14 local separation | include |
| Preview text | list rows and future detail/viewport preview path | preserve upstream history `Thread.preview`; delete relay list-time preview enrichment | Avoid returning to per-row list fanout while keeping native Codex preview display | include |
| Codex-native registry | `/Users/aelaguiz/workspace/codex` app-server/daemon code | first-class endpoint/session registry | Ideal long-term replacement for `ps`; outside this repo's immediate implementation | exclude from current repo implementation |

<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

<!-- arch_skill:block:phase_plan:start -->

## Phase 1 - Bounded Upstream Substrate

Status: COMPLETE - implemented and verified 2026-05-29.

Goal:

Make upstream socket growth structurally bounded before changing higher-level
list semantics.

Work:

Introduce a pooled upstream connection substrate for history and live endpoint
calls, and harden JSON-RPC socket timeout/close behavior.

Checklist (must all be done):

- Add `UpstreamConnectionPool` inside `scripts/dock-relay*.mjs`.
- Route history calls through one pooled/multiplexed `HistoryClient`.
- Define the pool boundary so later relay-to-Codex upstream calls must use it;
  forbid new one-off upstream helpers.
- Make request timeout quarantine the socket.
- Make `close()` wait for close or terminate after a bounded deadline.
- Expose open upstream socket counts by pool label in relay status.
- Add `rtk make relay-leak-check` as the Makefile-owned repeated-list leak
  proof for this substrate.

Verification (required proof):

- Relay unit tests for timeout teardown, close force termination, and pool
  max-open behavior.
- Leak-check proof that repeated list requests keep upstream connection count
  flat.
- Regression test proving one `thread/list` request does not open per-row
  history sockets.

Docs/comments (propagation; only if needed):

- Add a short code comment at the pool boundary explaining that JSON-RPC is
  multiplexed and per-row sockets are forbidden.

Exit criteria (all required):

- No list-path code opens a fresh history WebSocket per row.
- No relay upstream helper bypasses the pool for history calls.
- Timed-out sockets cannot remain silently healthy.
- `/statusz` exposes upstream socket counts by pool label.
- `rtk make relay-leak-check` exists and proves repeated `thread/list` calls
  keep upstream socket counts flat, or reports the exact service blocker.

Rollback:

- Revert the pool and restore old direct clients only if tests show functional
  regression before any list semantic phase lands.

## Phase 2 - History-First Dashboard List And Cursor Honesty

Status: COMPLETE - implemented and verified 2026-05-29.

Goal:

Make `thread/list` through the relay correct even when live discovery is down.

Work:

Rewrite dashboard list aggregation so history supplies membership, order, and
cursor. Live status is not consulted for ordering or pagination.

Checklist (must all be done):

- Remove live-first list ordering.
- Remove list-time per-row preview enrichment.
- Preserve Codex history `Thread.preview` in returned rows without relay
  list-time turn fanout.
- Remove list-time per-row attention/resume probing.
- Preserve or encode real upstream cursor state.
- Add deterministic `updatedAt desc`, `threadId` tie-break where relay sorting
  is required.
- Encode the Codex `100` row cap in tests/docs where assumptions matter.
- Update relay/client DTO tests for any cursor response shape change before
  the new relay response is treated as stable.
- Add `rtk make relay-probe` as the Makefile-owned raw-history-vs-relay recency
  and cursor probe.
- Change Swift/Dock loading from one `limit=200` page to `limit=100` pages with
  preserved per-logical-host/per-scope cursors.
- Add app-side continuation loading so rows after the first Codex page are
  reachable through the final Dock loading path.
- Add the minimal Phase 2 `liveOverlay` response shape:
  `{ ok: false, state: "disabled" | "unavailable", ageMs: null }`, and map it
  to connected-but-degraded/stale UI until Phase 3 supplies real cache data.
- Carry `nextCursor`, `backwardsCursor`, and `liveOverlay` through
  `ThreadListResponseDTO` -> `AppServerDockClient` -> `DockLoadResult` ->
  `DockStore.makeSnapshot` / `DockHostLoadStatus` -> `AppConnectivityStore`.

Verification (required proof):

- Relay unit tests prove live overlay changes cannot change dashboard row order
  or membership.
- Relay pagination tests prove `nextCursor` is not clobbered to null.
- Same-second timestamp tests prove deterministic ordering.
- Preview tests prove history `Thread.preview` is passed through and no
  list-time turn calls are made for preview enrichment.
- Client compatibility tests prove Swift can decode the final list response
  shape used by the relay.
- `DockStoreTests` or equivalent Swift tests prove more-than-100 rows are
  reachable through cursor continuation, not only through the relay DTO.

Docs/comments (propagation; only if needed):

- Update comments/docs that imply `limit=200` is honored by Codex.

Exit criteria (all required):

- Relay top-row recency matches raw history for the same scope under
  `relay-probe`.
- More-than-100 thread datasets retain cursor access to the tail.
- Dashboard list membership, order, and cursor remain correct when live
  discovery is unavailable; until Phase 3 lands `liveOverlay`, the relay must
  not report live state as healthy.
- App-visible response shape preserves existing required fields, adds optional
  metadata deliberately, and lands matching Swift DTO changes in the same phase.
- `AppServerDockClient` no longer requests `limit=200`, and `DockStore` does
  not discard `nextCursor` / `backwardsCursor` at the DTO boundary.
- `DockHostLoadStatus` and `AppConnectivityStore` reflect Phase 2
  non-healthy `liveOverlay` instead of reporting a fully healthy list.
- A >100-row fixture proves dashboard tail access through the Swift loading
  contract.

Rollback:

- Revert list semantics as one unit if history-first ordering breaks DTO
  compatibility before Swift updates are in place.

## Phase 3 - LiveStatusCache And Degraded State

Status: COMPLETE - implemented and verified 2026-05-29.

Goal:

Restore live status and routing information without making dashboard list
correctness depend on live discovery.

Work:

Add cached background live discovery/status sweeps and attach compact
`liveOverlay` metadata to list responses and `/statusz`.

Checklist (must all be done):

- Move `ps` discovery out of dashboard request hot paths.
- Add bounded/cached live endpoint scanner.
- Add pooled read-only status sweeps through the Phase 1 pool boundary.
- Add `liveOverlay` response metadata.
- Extend `scripts/dock-relay-status.mjs` as the internal `RelayStatusStore`
  with narrow projection methods for `LiveOverlay`, `StatuszSnapshot`,
  `MetricsSnapshot`, and `DebugSessionsSnapshot`.
- Add loopback-only HTTP handlers for `/metricsz` and `/debugz/sessions`.
- Route `aggregateLoadedList`, `aggregateThreadRead`, `listThreadTurns`,
  `endpointForThread`, `archiveThread`, `resumeThread`, and any future focused
  route through `LiveStatusCache` or `SessionRouter`; only the cache refresh
  boundary may call `discoverLoopbackEndpoints`.
- Keep dashboard sweeps read-only; do not use `thread/resume` for all loaded
  sessions.
- Preserve focused `SessionRouter` resume behavior for open details.

Verification (required proof):

- Relay tests prove live discovery failure returns degraded metadata instead of
  silent history-only success.
- Relay status tests prove `/statusz` includes age, endpoints, failures, and
  redacted error categories.
- Relay status tests prove `/metricsz` and `/debugz/sessions` are loopback-only,
  use the internal status store projections, and do not expose secrets,
  payloads, prompt text, transcript text, raw audio, or full endpoint
  credentials.
- Thread detail tests prove focused resume and turn control still route.

Docs/comments (propagation; only if needed):

- Comment the boundary between read-only status sweeps and focused resume.

Exit criteria (all required):

- Dashboard list requests do not call `ps`.
- No normal request handler calls `discoverLoopbackEndpoints` directly; `ps`
  discovery is reachable only from the bounded cache refresh loop.
- `thread/list` includes explicit degraded `liveOverlay` metadata when live
  discovery fails or is stale.
- `/statusz` makes live status freshness and discovery failure obvious.
- `/metricsz` exposes counters/gauges needed for leak debugging without secret
  or payload data.
- `/debugz/sessions` explains focused upstream ownership and live-cache state on
  loopback only, using hashed/truncated IDs and no full JSON-RPC payloads.
- Focused detail still reconnects or fails loudly.

Rollback:

- Revert Phase 3 live-cache changes as a unit if faulty. Until fixed,
  `thread/list` and `/statusz` must report live overlay as degraded/stale,
  never healthy history-only success.

## Phase 4 - Logical Host Identity And Device Profiles

Status: COMPLETE WITH DEVICE AVAILABILITY NOTE - code implemented and verified
for simulator, iPhone 14, and iPhone 17 Pro profile readback on 2026-05-29.
The all-device aggregate command may not be repeatable now because the user may
unplug the iPhone 17 Pro after the successful install/readback.

Goal:

Stop endpoint aliases and device configs from multiplying load or leaking across
phones.

Work:

Introduce stable relay instance identity and ordered endpoint fallback lists in
Swift and generated config.

Checklist (must all be done):

- Relay advertises stable non-secret instance id via initialization, Bonjour TXT,
  and `/statusz`.
- App-safe config writes `CODEX_DOCK_RELAY_INSTANCE_ID` and physical
  `relay-config.json` writes `relayInstanceID`.
- Swift groups endpoints by configured relay instance id before probing.
- Swift validates `initialize`, Bonjour TXT `relay-id`, and `/statusz` echoed
  ids when available; mismatches become config-error/degraded state, not new
  logical hosts.
- Endpoint aliases are stored as ordered fallback transports.
- `RelayDiscovery`, `LocalRelayEndpointList`, `RelayBootstrapStore`,
  `HostSettingsStore`, `HostsView`, `CodexDockRootView`, `DockStore`,
  `ArchiveStore`, and `AppConnectivityStore` all consume the same logical-host
  model.
- Generated host env, device config, simulator config, saved-config migration,
  and manual Host Settings reject raw `:4500` app-facing endpoints.
- iPhone 17 Pro profile remains Tailscale-only.
- iPhone 14 profile remains local/Bonjour/LAN-only.
- Add `rtk make device-config-verify-all`; it runs both known profiles and
  reports the exact device-tooling blocker if readback cannot run.

Verification (required proof):

- Swift tests prove three aliases for one configured relay instance id produce
  one logical host before network probing.
- Swift tests prove an echoed relay-id mismatch marks the host degraded/config
  error instead of creating a second logical host.
- Archive/store/settings tests prove fallback endpoints do not create multiple
  host rows, archive loads, restore targets, or connectivity records.
- Config tests prove the two physical device profiles stay separate.
- Config and Makefile tests prove raw `:4500` is rejected from app-facing
  simulator/device/manual/saved config while Mac-side service internals still use
  `ws://127.0.0.1:4500`.
- Simulator proof shows one logical host even when multiple endpoints are
  configured.

Docs/comments (propagation; only if needed):

- Update README/AGENTS if command names or endpoint expectations change.

Exit criteria (all required):

- App loads once per logical host, not once per alias.
- Archive loads/restores and connectivity rollups operate once per logical host,
  not once per alias.
- No app-facing config writer or manual settings path can save raw `:4500`.
- Generated `.codex-dock/host.env`, device `relay-config.json`,
  initialization, Bonjour TXT, and `/statusz` agree on the same non-secret relay
  instance id or fail loudly.
- `rtk make device-config-verify-all` exists and reads back both expected
  endpoint lists, or records the exact environmental blocker for each missing
  or unavailable device.

Implementation evidence as of 2026-05-29:

- Relay echoes `relayInstanceID` through `initialize`, Bonjour TXT `relay-id`,
  `/statusz`, `/metricsz`, and `/debugz/sessions`.
- App-safe host env writes `CODEX_DOCK_RELAY_INSTANCE_ID=Amir-M5`.
- Physical `relay-config.json` writes and verifies `relayInstanceID`.
- Swift groups multiple endpoints into one logical host when
  `CODEX_DOCK_RELAY_INSTANCE_ID` or saved `relayInstanceID` is present.
- Swift now rejects multiple endpoint aliases without
  `CODEX_DOCK_RELAY_INSTANCE_ID` / saved `relayInstanceID`, so endpoint aliases
  cannot silently become separate logical hosts.
- Swift validates `initialize` and `/statusz` relay identity for configured
  logical hosts; Bonjour discovery uses `relay-id` as the logical host id.
- Swift saved/env/manual app-facing config and the device-config writer reject
  raw `:4500` app-server endpoints.
- Generated app-facing host env now rejects stale `CODEX_DOCK_HOSTS` entries
  pointing at raw `:4500`; Mac-side service internals still keep
  `ws://127.0.0.1:4500` behind the relay.
- iPhone 14 proof passed again with latest build `20260529033451` and saved config
  `Amir-M5.local:4510,192.168.50.74:4510`, `relayInstanceID=Amir-M5`.
- iPhone 17 Pro proof passed with build `20260529030857` and saved config
  `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`,
  `relayInstanceID=Amir-M5`.
- `rtk make device-config-verify-all` exists. Per-device readback has passed for
  both known devices, but the aggregate command may be blocked later if the
  iPhone 17 Pro is unplugged.

Observed stale-config failure and fix:

- The first iPhone 14 install exposed a real stale-artifact path: copying a
  `CodexDock` directory directly to `Library/Application Support` could leave
  the old saved config in place or create the wrong device-side path shape.
- The Makefile now stages `root/CodexDock/relay-config.json` and copies the
  parent `root` directory to `Library/Application Support`, then reads back
  `Library/Application Support/CodexDock/relay-config.json`.
- `scripts/device-relay-config.mjs` now verifies structured JSON semantically,
  so Swift's JSON key order does not create false stale-config failures.

Rollback:

- Revert Phase 4 app config migration as a unit before release if it blocks
  launch; do not ship endpoint-as-host fallback behavior.

## Phase 5 - Ops, Probes, And Final Verification

Status: PARTIAL - ops targets, docs, simulator config proof, generated Xcode
app-test, relay probe, relay doctor, leak check, single active-session
simulator composer-submit proof, and per-device config readback are implemented
and verified as of 2026-05-29. Multi-concurrent simulator composer-submit proof
remains open, and `device-config-verify-all` may be blocked if the iPhone 17
Pro has been unplugged after its successful readback.

Goal:

Make failures obvious and the Makefile the only normal operation surface.

Work:

Add probe, leak-check, doctor, config verify, and log/status commands that prove
the architecture from the outside.

Checklist (must all be done):

- Run `rtk make relay-probe` as final proof for raw-history-vs-relay recency
  and cursor behavior.
- Run `rtk make relay-leak-check` as final proof for repeated-list resource
  behavior.
- Add `rtk make relay-doctor` as the canonical relay-specific diagnostic
  target. It may call shared host-service code, but the Makefile target must
  exist.
- Add `rtk make sim-config-verify SIM='iPhone 17'`.
- Run `rtk make device-config-verify-all` as final verification using the known
  iPhone 17 Pro and iPhone 14 profiles.
- Ensure app/device/simulator build/install/test paths remain Makefile-owned.
- Update docs to remove stale raw Xcode/devicectl workflow guidance.
- Update README service-path text from live merge over history to history list
  plus cached live overlay.
- Remove `npm run dock-relay` as a normal direct relay startup path, or replace
  it with a failing pointer to `rtk make services`; keep `scripts/dock-relay.mjs`
  callable only as the service implementation used by Makefile/host service.

Verification (required proof):

- `rtk npm run test:relay`.
- `rtk swift test --filter AppServerClientTests`.
- `rtk swift test --filter DockStoreTests`.
- `rtk make app-test SIM='iPhone 17'`.
- Simulator UI composer-submit pass: use the installed app to submit a real
  message through the thread detail interface, including at least one active
  session that is already doing work. A single active-session proof passed; a
  multi-concurrent session proof remains open.
- `rtk make relay-probe`, `rtk make relay-leak-check`, and
  `rtk make relay-doctor` succeed or report exact environmental blockers.
- `rtk make sim-config-verify SIM='iPhone 17'` succeeds or reports the exact
  simulator/config blocker.
- `rtk make device-config-verify-all` succeeds or reports exact per-device
  blockers.

Docs/comments (propagation; only if needed):

- README and AGENTS match Makefile and shipped behavior.

Exit criteria (all required):

- All planned checks either pass or have exact recorded environmental blockers.
- The simulator composer-submit path is either proven against a real active
  thread or carried forward as an explicit open verification blocker with the
  exact failure/blocker recorded.
- No normal workflow requires raw `xcodebuild`, raw `devicectl`, or raw
  `simctl install`.
- The exact normal commands are discoverable from `rtk make help` and match
  README/AGENTS.
- README, AGENTS, and `package.json` no longer teach live-first merge or direct
  npm relay startup as the normal path.
- No secrets appear in app env, saved phone config, Bonjour TXT, or logs.

Implementation evidence as of 2026-05-29:

- `rtk make relay-doctor` exists and passed with status `passed`.
- `rtk make sim-config-verify SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  exists and passed against generated `.codex-dock/host.env`.
- `rtk make help` lists `relay-doctor`, `relay-probe`,
  `relay-leak-check`, `sim-config-verify`, and
  `device-config-verify-all`.
- `package.json` no longer starts `scripts/dock-relay.mjs` through
  `npm run dock-relay`; that script now exits with a pointer to
  `rtk make services`.
- README now describes history-first dashboard list semantics with cached live
  status decoration instead of live-row merge over stored history.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` passed.
- `rtk make relay-probe` passed with top thread
  `019e70b3-6b3b-7af1-a443-900ca409e895`, `rowCount` 20, and
  `nextCursor` `2026-05-28T11:37:48.311Z`.
- `rtk make relay-leak-check` now waits for busy-relay pending requests to
  drain before judging the pool; the final run passed with history pool
  `open: 1`, `pending: 0`, `unhealthy: 0`.
- iPhone 17 Pro Tailscale install/readback passed before the user unplugged it:
  build `20260529030857`, endpoints
  `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`,
  `relayInstanceID=Amir-M5`.
- Thread detail event ordering was corrected from top-pinned newest-first to
  natural conversation flow. Verification passed with
  `rtk swift test --filter ThreadEventNormalizerTests`,
  `rtk swift test --filter ThreadDetailStoreTests`, and
  `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Strict maintainability cleanup split app-server client/session plumbing out
  of `DockStore.swift` and `ThreadDetailStore.swift`; both files are back below
  1,000 lines.
- Config side-door hardening now rejects multiple app-facing endpoints without
  `CODEX_DOCK_RELAY_INSTANCE_ID` and rejects stale generated app host env
  entries that point at raw `:4500`.
- Simulator UI composer-submit into a real active session passed through the
  actual interface. Relay logs showed successful `turn/steer` forwarding to the
  active upstream at `ws://127.0.0.1:59557/`.
- Recovery hardening now applies the same thread-id check during automatic
  upstream recovery and clears stale server-request ids on upstream close.
- Active-agent list loading is bounded below the iOS WebSocket receive ceiling:
  real relay `limit:100` agent pages reached `1332205` bytes, while `limit:50`
  returned all `1171` agent rows with `maxRawBytes=594496`. Swift also sets an
  explicit WebSocket `maximumMessageSize` of `8388608` bytes.
- Live-status cadence now matches the stale threshold: the relay refreshes live
  status every `2500` ms against a `5000` ms stale window, and Swift keeps the
  newest live-overlay value across paginated loads.
- Verification passed with `rtk npm test`, `rtk npm run test:relay`,
  `rtk swift test --filter AppServerClientTests`,
  `rtk swift test --filter DockStoreTests`, `rtk make app`,
  `rtk make app-test`, `rtk make relay-probe`, iPhone 14
  `rtk make device-install`, iPhone 14 `rtk make device-config-verify`, and
  `rtk git diff --check`.

Rollback:

- Revert individual Makefile diagnostics if they fail independently, but do not
  remove service/app/device canonical targets.

## Phase 6 - Composer Submit Routing Root-Cause Investigation

Status: COMPLETE - relay root-cause hardening and multi-concurrent simulator UI
composer-submit proof are complete.

Goal:

Prove and fix the critical report that messages submitted from the client can
land in the wrong running Codex app-server/session.

Work:

Run a deep root-cause investigation across client thread identity, relay
`SessionRouter`, live status cache, raw app-server ownership, `thread/resume`,
`turn/start`, `turn/steer`, and any focused-session routing state. The fix must
repair the ownership/routing model at the root. Do not paper over the issue with
a local client-side hack, a hard-coded endpoint, or a one-off retry rule.

Checklist (must all be done before this phase can close):

- [x] Reproduce or disprove the bug with an installed simulator client submitting
  messages through the real UI into more than one concurrently running Codex
  session.
- [x] Capture non-secret evidence that identifies the intended thread id, selected
  Dock row, relay route, upstream app-server owner, and resulting session that
  received the message.
- [x] Audit the relay focused-session routing path:
  `SessionRouter.endpointForThread`, `LiveStatusCache`, `thread/read`,
  `thread/resume`, `turn/start`, `turn/steer`, and server-request response
  forwarding.
- [x] Audit the Swift submit path:
  `SessionDetailView`, `ComposerView`, `ThreadDetailStore.sendDraft`,
  active-turn tracking, `ThreadDetailSession`, and `AppServerHostConnector`.
- [x] Decide and document the canonical ownership invariant for a submitted message:
  which object owns the selected thread, which relay/app-server endpoint is
  allowed to receive turns for that thread, and how mismatches fail loudly.
- [x] Add tests that would have caught cross-session misrouting before the fix.
- [x] Fix the root cause in the canonical owner path, deleting or failing any side
  door that can route a turn to the wrong running session.

Implementation note:

The relay now treats `thread/resume` as the only binder for a focused downstream
session. A resumed upstream is accepted only if the upstream returns the same
thread id. `turn/start`, `turn/steer`, and `turn/interrupt` must include a
`threadId` that matches the bound resumed thread; otherwise the relay returns
`-32602` before sending anything upstream. Phone responses to app-server
requests are forwarded only when the relay previously forwarded that exact
server request id for the current session generation. A newer `thread/resume`
or an upstream close clears old request ids so stale approval/input responses
cannot land on a new or recovered session. Automatic upstream recovery applies
the same resumed-thread invariant before accepting the recovered upstream.

Verification (required proof):

- Simulator UI composer-submit passed into two simultaneously running sessions:
  thread `019e70b3-6b3b-7af1-a443-900ca409e895` routed to
  `ws://127.0.0.1:61116/`, and thread
  `019e71c0-ec97-70e0-bca8-ce9c16039c52` routed to
  `ws://127.0.0.1:59557/`.
- Focused Swift and relay tests prove a submitted turn cannot be delivered to a
  different thread/session owner when multiple live app-servers exist.
- Redacted relay logs prove intended thread id, selected route, and upstream
  owner stayed aligned: `3af7f2f6d991` matched active thread hash for `61116`,
  and `5110ec7ce75d` matched active thread hash for `59557`.

Exit criteria (all required):

- A client message submitted from thread detail either reaches the selected
  thread's owning app-server/session or fails visibly before sending.
- No fallback route can silently send a user message to a different running
  Codex session.
- The root-cause document explains the bug, the failing invariant, the fix, and
  the proof.

## Phase 7 - Dock Overview Latest-Message Summary

Status: COMPLETE - relay-owned latest-summary cache, Swift mapping, tests, and
simulator UI proof are complete.

Goal:

Make Dock overview rows identify the current thread state by showing the most
recent useful message, not the first message that started the thread hours ago.
User-observed problem: the Dock overview currently makes active threads hard to
recognize when it shows an hours-old opening message instead of the latest
message coming through the thread.

Work:

Audit the row-summary source from raw Codex history through relay
`thread/list`, Swift DTO mapping, `SessionSummary`, and `DockRowView`. Choose an
elegant canonical summary owner so the overview row can show the latest useful
human/agent message without reintroducing per-row turn fanout, stale preview
heuristics, or duplicate summary rules in Swift and relay.

Checklist (must all be done before this phase can close):

- [x] Identify where the current overview text comes from: raw history `preview`,
  relay row shaping, `ThreadListDTO`, `SessionSummaryMapper`, and
  `DockRowView`.
- [x] Prove whether the existing raw app-server `thread/list` response exposes a
  latest-message/preview field that can be used directly.
- [x] If raw history only exposes the first message, design the smallest canonical
  summary path that avoids the old list-time per-row `thread/turns/list` fanout
  problem.
- [x] Decide the summary contract: which event categories count as row-summary
  candidates, how empty/command-only/system-only threads display, and how live
  updates affect the overview text.
- [x] Add tests that prove overview rows prefer the latest useful message while
  preserving history-first order, pagination, and bounded relay resource use.
- [x] Update docs/runbook text so "preview" and "latest summary" are not confused.

Implementation note:

Raw Codex `thread/list` exposes `turns: []` in list rows and preserves
`preview` as the older opening text. The relay now owns a bounded
`ThreadSummaryCache` that decorates history rows with `latestSummary` only when
a cached value is available, then warms missing/stale summaries out of band via
bounded `thread/turns/list` reads against the history client. This preserves the
first `thread/list` response path, keeps dashboard membership/order/cursor on
history truth, and avoids blocking every dashboard list on per-row turn fanout.
Swift maps `ThreadDTO.latestSummary` before falling back to row turns and then
raw `preview`.

Verification (required proof):

- Relay/Swift tests prove row summaries use the latest useful message when
  available.
- Resource proof shows the overview summary fix does not reintroduce per-row
  turn fanout or unbounded app-server calls; `thread/list` decorates from cache
  and warms missing/stale summaries out of band.
- Simulator UI proof shows a thread whose first message is stale but whose
  latest message is new is identifiable from the Dock overview row. Screenshot:
  `/tmp/codex-client/20260529T0400Z/overview-latest-summary-remount.png`.

Exit criteria (all required):

- Dock overview rows show the most recent useful message or an explicit
  well-defined fallback.
- The summary source has one canonical owner and does not fork between relay,
  Swift mapping, and UI rendering.
- The fix preserves the Phase 2 history-first list and bounded-resource
  guarantees.

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
- `rtk make relay-doctor`; it may call shared host-service doctor code, but the
  relay-specific Makefile target is the required diagnostic surface for this
  architecture.
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

## 8.4 Required review gates for this user objective

These gates are outside the implementation phases, but they are required by the
active user objective:

- After this ArcStep AutoPlan is complete, run the `plan-audit` skill on this
  document before code implementation starts.
- After Section 7 implementation is complete, run a fresh consult with
  `Composer 2.5 Fast` to audit code against the plan.
- After the consult is addressed, run a final plan audit, implementation check,
  and thermonuclear code review.

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
rtk make relay-doctor
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

`rtk make host-service-doctor` may remain a broader service diagnostic, but
`rtk make relay-doctor` is the required relay-specific diagnostic target for
this plan.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, planning/helper blocks, phase
    obligations, verification expectations, rollout commands, and decision-log
    drift.
- Findings summary:
  - Fixed branchy DTO compatibility posture by choosing clean semantic cutover
    with stable required row fields plus optional relay metadata/cursor fields.
  - Fixed Phase 2/Phase 3 ordering so `liveOverlay` degraded metadata is proven
    after `LiveStatusCache` exists, while Phase 2 still proves history-first
    correctness when live discovery is unavailable.
  - Fixed stranded preview behavior by preserving Codex native
    `Thread.preview` and deleting relay list-time preview enrichment.
  - Fixed duplicated `device-config-verify-all` ownership and promoted
    `sim-config-verify` and `relay-doctor` into the authoritative phase plan.
  - Fixed rollback language so it cannot imply a hidden runtime fallback to
    healthy history-only live state or endpoint-as-host behavior.
- Integrated repairs:
  - Updated Sections 0.4, 0.5, 6.1, 6.2, 7, 8.2, 8.4, and 9.3.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

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
