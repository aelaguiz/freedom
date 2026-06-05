---
title: "Codex Dock - Codex App-Server Relationship And Aggregation Architecture"
date: 2026-06-05
status: draft-validation
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [composer-2.5-fast, gpt-55x-high, thermo-nuclear-code-quality-review]
doc_type: architecture_reference_and_cutover_plan_seed
supersedes:
  - docs/CODEX_DOCK_CODEX_APP_SERVER_END_TO_END_AUDIT.md
  - docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29.md
  - docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md
---

# TL;DR

Codex does not run as one global app-server that owns every live session on the
machine. Codex runs many runtimes; an app-server is an API surface around one
runtime, and `thread/loaded/list` reports only the threads loaded in that one
runtime.

Dock's current model is wrong for live status because it starts one private raw
Codex app-server at `ws://127.0.0.1:4500` and asks that one process for live
truth. That process can read shared history from `~/.codex`, but it cannot see
live turns owned by other Codex app-server or CLI runtimes.

The better architecture is a hard cut to a relay-local app-server registry:
Dock relay on `:4510` should aggregate all addressable Codex app-server
instances it can actually connect to, and should stop starting a Dock-owned raw
app-server. The important limitation is that existing `stdio://` app-server
children are private pipes owned by their parent UI; Dock cannot attach to those
from the outside unless Codex exposes a registry, socket, or other attachable
control surface.

The Codex daemon Unix socket is a valid Codex app-server transport. Dock relay
now supports it by adapting `unix://` to the local `ws+unix:` WebSocket shape
and disabling WebSocket compression for upstream app-server handshakes.

# 1) Mental Model

## 1.1 What people expect

```text
Codex UI A --+
Codex UI B --+--> one global Codex app-server --> all history + all live state
Codex CLI ---+
Dock relay --+
```

That is not the current Codex model.

## 1.2 What Codex actually does

```text
shared disk:
  ~/.codex
    persisted history, state DBs, rollout files

live runtimes:
  Codex.app thread A        -> private app-server/runtime A -> ~/.codex
  Codex.app thread B        -> private app-server/runtime B -> ~/.codex
  VS Code / ChatGPT ext     -> app-server/runtime C         -> ~/.codex
  codex app-server daemon   -> unix app-server/runtime D    -> ~/.codex
  codex app-server --listen -> websocket runtime E          -> ~/.codex
  codex -p / codex resume   -> CLI runtime F                -> ~/.codex
  in-process rich client    -> no external transport        -> ~/.codex
```

The law:

```text
~/.codex = shared persisted history
Codex runtime = live owner for one process/session set
Codex app-server = API wrapper around one runtime
Live state = process-local
```

So a process can list/read history from disk and still honestly say a thread is
`notLoaded`, because that same process does not own the running turn.

# 2) Validated Codex Facts

## 2.1 App-server is the rich-client interface, not a global singleton

Codex says `codex app-server` powers rich interfaces such as the VS Code
extension. It supports JSON-RPC over several transports:

- `stdio://`, the default transport.
- `ws://IP:PORT`, currently marked experimental and unsupported.
- `unix://`, using `$CODEX_HOME/app-server-control/app-server-control.sock`.
- `off`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:3`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:22`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:24`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:26`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:27`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:28`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:37`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/main.rs:22`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/main.rs:27`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs:105`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs:106`

This matters because Dock's current stable `ws://127.0.0.1:4500` dependency is
not the native default Codex desktop shape. It is a Dock-created workaround.

## 2.2 `thread/loaded/list` is process-local

Codex's README defines `thread/loaded/list` as currently loaded in memory, not
globally loaded on the machine:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:138`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:374`

The implementation calls this app-server process's `ThreadManager`:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1979`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1984`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1986`

`ThreadManager` owns an in-memory `HashMap<ThreadId, Arc<CodexThread>>`:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:169`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:200`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:201`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:958`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:959`

So the method is exactly the wrong primitive if Dock only calls one app-server
and expects global live truth.

## 2.3 Thread status is also process-local

Codex app-server status uses `ThreadWatchState.runtime_by_thread_id`, another
in-memory map. A thread is `Active` only if runtime facts in this process say it
is running or waiting on user/approval input.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:301`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:303`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:360`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:366`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:429`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:442`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:450`

This explains the user-visible bug: Dock saw `notLoaded` or `dormant` because
Dock was asking a runtime that did not own the live turn.

## 2.4 Codex app-server can rejoin a running thread only if that same app-server knows it

The generated schema says `thread/resume` can rejoin a running thread when
`thread_id` identifies a running thread. That is still scoped to the app-server
process receiving the request, because the process needs the active thread in
its `ThreadManager`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/schema/json/codex_app_server_protocol.schemas.json:17390`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_lifecycle.rs:143`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_lifecycle.rs:145`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:1024`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:1026`

# 3) Current Dock Architecture

## 3.1 Service topology today

Dock currently installs and starts two host services:

```text
raw Dock-owned Codex app-server:
  codex app-server --listen ws://127.0.0.1:4500
  --ws-auth capability-token
  --ws-token-file .codex-dock/app-server.token

Dock relay:
  node scripts/dock-relay.mjs --port 4510
  --history-url ws://127.0.0.1:4500
  --history-auth-token-file .codex-dock/app-server.token
```

Evidence:

- `Makefile:4`
- `Makefile:5`
- `Makefile:18`
- `Makefile:205`
- `scripts/codex-dock-host-service.mjs:261`
- `scripts/codex-dock-host-service.mjs:268`
- `scripts/codex-dock-host-service.mjs:286`
- `scripts/codex-dock-host-service.mjs:457`
- `scripts/codex-dock-host-service.mjs:460`
- `scripts/codex-dock-host-service.mjs:461`
- `scripts/codex-dock-host-service.mjs:463`
- `scripts/codex-dock-host-service.mjs:465`
- `scripts/codex-dock-host-service.mjs:492`
- `scripts/codex-dock-host-service.mjs:494`
- `scripts/codex-dock-host-service.mjs:504`
- `scripts/codex-dock-host-service.mjs:534`

## 3.2 Relay data path today

```text
iPhone / simulator
  -> ws://<host>:4510
  -> Dock relay
  -> historyClientForConfig(config.historyUrl)
  -> ws://127.0.0.1:4500
```

The relay also has a live endpoint list, but normal service wiring does not
discover existing app-servers and feed that list. It accepts manually configured
`CODEX_DOCK_LIVE_APP_SERVER_WS` / `CODEX_DOCK_LIVE_ENDPOINTS` values.

Evidence:

- `scripts/dock-relay.mjs:1564`
- `scripts/dock-relay.mjs:1565`
- `scripts/dock-relay-thread-data.mjs:49`
- `scripts/dock-relay-thread-data.mjs:53`
- `scripts/dock-relay-thread-data.mjs:66`
- `scripts/dock-relay-thread-data.mjs:71`
- `scripts/dock-relay-thread-data.mjs:85`
- `scripts/dock-relay-thread-data.mjs:89`
- `scripts/dock-relay-thread-data.mjs:108`
- `scripts/dock-relay-thread-data.mjs:117`

## 3.3 Existing aggregation skeleton

The relay already has a useful piece: `collectLiveRows` can query multiple
configured endpoints with bounded batching, call each one's `thread/loaded/list`,
read loaded thread rows, merge by thread id, and preserve the owning endpoint in
`dockRelaySource`.

Evidence:

- `scripts/dock-relay-thread-data.mjs:484`
- `scripts/dock-relay-thread-data.mjs:497`
- `scripts/dock-relay-thread-data.mjs:498`
- `scripts/dock-relay-thread-data.mjs:518`
- `scripts/dock-relay-thread-data.mjs:594`
- `scripts/dock-relay-thread-data.mjs:602`
- `scripts/dock-relay-thread-data.mjs:603`
- `scripts/dock-relay-thread-data.mjs:629`
- `scripts/dock-relay-thread-data.mjs:630`
- `scripts/dock-relay-live-status-cache.mjs:171`
- `scripts/dock-relay-live-status-cache.mjs:180`
- `scripts/dock-relay-live-status-cache.mjs:183`

That means the implementation does not need a new conceptual stack. It needs a
hard cut from "configured single upstream plus optional live extras" to
"registry-owned addressable upstream set."

# 4) Runtime Evidence From This Machine

Probe time: `2026-06-05T01:02:23.958Z`.

Command shape:

```sh
ps -axo pid=,ppid=,command=
```

Then a local Node probe connected to each discovered `ws://127.0.0.1:*`
app-server endpoint, sent `initialize`, sent `initialized`, then called
`thread/loaded/list`.

Observed:

- `12` total WebSocket app-server endpoints.
- `1` Dock-owned endpoint: `ws://127.0.0.1:4500`.
- `11` non-Dock WebSocket endpoints.
- `14` `stdio://` Codex.app app-server processes.
- `1` `unix://` remote-control app-server process.
- The `11` non-Dock WebSocket endpoints all accepted the probe and returned
  `loadedCount: 0`.
- Dock's `ws://127.0.0.1:4500` rejected the unauthenticated probe with `401`,
  as expected.
- Dock's `ws://127.0.0.1:4500` accepted the authenticated probe using
  `.codex-dock/app-server.token` and returned `loadedCount: 0`.

Non-Dock WebSocket endpoints observed:

```text
ws://127.0.0.1:54200
ws://127.0.0.1:54344
ws://127.0.0.1:55009
ws://127.0.0.1:57064
ws://127.0.0.1:58962
ws://127.0.0.1:59384
ws://127.0.0.1:61964
ws://127.0.0.1:64010
ws://127.0.0.1:64302
ws://127.0.0.1:64569
ws://127.0.0.1:64792
```

Interpretation:

- Addressable `ws://` app-server aggregation is real and viable.
- The current machine had no loaded threads in the addressable WebSocket
  app-servers at probe time.
- Private `stdio://` processes existed and were not externally attachable by
  URL.
- A registry must distinguish "addressable and queryable" from "observed but
  private/unreachable."

# 5) Where The Old Model Is Wrong

## 5.1 Wrong assumption: Dock-owned `:4500` is "the Codex app-server"

It is one Codex app-server instance. It is not the global app-server.

Bad model:

```text
Dock relay -> ws://127.0.0.1:4500 -> all Codex live sessions
```

Actual model:

```text
Dock relay -> ws://127.0.0.1:4500 -> only :4500 runtime live sessions
other Codex UI/runtime processes       -> their own live sessions
```

## 5.2 Wrong assumption: reading history proves live status

History rows can come from shared disk. Live status comes from the runtime that
owns the turn.

So this can be true at the same time:

```text
thread/read through :4500:
  returns stored thread history

thread/read through :4500:
  status.type = "notLoaded"

another app-server process:
  owns the running turn
```

## 5.3 Wrong assumption: "all app-servers" are connectable

`ws://` and `unix://` app-servers have a transport endpoint. `stdio://`
app-servers do not expose a public attach address; their stdin/stdout pipes are
already owned by the parent client.

Dock can aggregate all addressable app-servers today. Dock cannot honestly claim
it can aggregate private `stdio://` app-servers unless Codex changes the
discovery/attach contract or Codex.app starts children with attachable endpoints.
The same limitation applies even more strongly to Codex in-process app-server
usage, because there is no external socket or process transport to attach to.

# 6) Target Architecture

## 6.1 Hard-cut topology

```text
iPhone / simulator
  -> ws://<host>:4510
  -> Dock relay
        -> AppServerRegistry
        -> Codex daemon unix socket, after relay adds Unix transport support
        -> discovered ws://127.0.0.1:<port> app-servers
        -> future Codex-native registry endpoints, if Codex exposes them
     -> Relay state table
     -> dock/* snapshots, deltas, detail, control, voice
```

Delete this normal path:

```text
Dock relay
  -> Dock-owned raw app-server service at ws://127.0.0.1:4500
```

The relay stays the only phone-facing server. The phone still never connects to
raw Codex app-server endpoints.

## 6.2 AppServerRegistry responsibilities

The relay owns one registry object. It is the only place that discovers,
connects to, classifies, and refreshes upstream Codex app-server instances.

Registry inputs:

- Process table scan for `codex app-server --listen ws://127.0.0.1:<port>`.
- Known Codex daemon Unix socket:
  `$CODEX_HOME/app-server-control/app-server-control.sock`.
- Explicit developer override endpoints only for tests/diagnostics, not the
  normal production path.
- Future Codex-native registry output if upstream Codex exposes one.

Registry outputs:

- `historyEndpoint`: preferred app-server for history operations.
- `liveEndpoints[]`: all addressable app-servers that passed `initialize`.
- `unreachableObserved[]`: observed app-server processes that cannot be attached
  to externally, especially `stdio://`.
- `threadOwnerById`: lease map from `threadId` to the app-server endpoint that
  reported it loaded.
- `diagnostics`: endpoint count, version/userAgent, codexHome, transport,
  discoveredAt, lastSeenAt, lastOkAt, failure reason, loaded row count.

## 6.3 History plane

Preferred history source:

```text
codex app-server daemon -> unix:// -> thread/list, thread/read, thread/turns/list
```

Reason:

- `unix://` is documented as the local app-server control-plane transport.
- It does not require Dock to create an unsupported WebSocket history server.
- It keeps Dock on an official local Codex app-server surface.

Dock relay support:

- `scripts/dock-relay-json-rpc-client.mjs` connects to `ws://`, `wss://`, and
  Codex `unix://` upstreams.
- The `unix://` path adapts to `ws+unix:` and sets
  `perMessageDeflate: false`; the real Codex daemon control socket closes the
  handshake when Node advertises WebSocket compression.
- Keeping Dock's private `:4500` server as a hidden fallback is not allowed.

If the daemon socket is unavailable, the relay must fail loud in `/statusz` and
the app's root connectivity state. It must not silently start a Dock-owned raw
`:4500` app-server as a fallback, because that preserves the broken mental
model.

## 6.4 Live plane

The registry refresh loop queries only addressable app-servers:

```text
for endpoint in addressableAppServers:
  initialize once through the upstream pool
  call thread/loaded/list with LIVE_LOADED_LIST_LIMIT
  call thread/read includeTurns:false for loaded ids only
  store rows as live leases
  store threadId -> endpoint owner
```

The relay must not scan thousands of history rows to infer live status. Live
state is found by asking each runtime for its loaded IDs.

## 6.5 Focused control/detail routing

For a thread with a current owner lease:

```text
thread/detail/subscribe
turn/start
turn/interrupt
approval/request-card responses
thread/turns/list
```

route to the owner endpoint.

For a thread without a current owner lease:

- read-only detail/history routes use the history endpoint;
- starting a new turn resumes through the history endpoint and then that
  endpoint becomes the owner;
- if the thread is actually running in a private `stdio://` app-server, Dock
  must show "observed private app-server, live owner not attachable" rather than
  faking running state.

## 6.6 Private `stdio://` app-server policy

Current policy:

```text
Observed stdio app-server = diagnostic only
Observed stdio app-server != attachable live endpoint
```

The registry records counts and PIDs but does not try to write to another
process's private stdin/stdout pipes.

Best upstream-compatible fix:

- Codex.app should expose a registry of child app-server endpoints, or
- Codex.app should start per-thread app-servers on a local attachable socket and
  register them, or
- Codex daemon should become the central broker for live child runtimes.

Without one of those, a repo-only Dock change cannot see private Codex.app
`stdio://` live state. It can only report that limitation honestly.

## 6.7 Transport matrix

| Transport shape | Dock registry role | Normal-path policy |
|---|---|---|
| `unix://$CODEX_HOME/app-server-control/app-server-control.sock` | Preferred history endpoint after relay adds support | Required for daemon-history hard cut, or relay fails loud |
| `ws://127.0.0.1:<port>` app-server | Live endpoint when discovered and authenticated | Aggregate for live owner leases; still experimental in Codex |
| `stdio://` app-server | Observed private runtime | Count and diagnose only; not attachable |
| in-process app-server | Invisible/private runtime | Not attachable without upstream Codex support |
| Dock-owned `ws://127.0.0.1:4500` | Legacy workaround | Deleted from normal path |

Discovery must filter for `codex app-server`, not every process that happens to
listen on a local WebSocket port. Codex also has other WebSocket-using commands,
including exec-server paths, and those are not valid Dock live endpoints.

# 7) Performance Requirements

This architecture has to work with thousands of persisted Codex threads.

Rules:

- No request-path `ps` scan.
- No request-path endpoint discovery.
- No app-server discovery per row.
- No `thread/read` fanout over every history row just to paint live badges.
- No unbounded WebSocket creation.
- No unbounded snapshot payloads.
- No hidden Swift accessibility or debug payload that serializes every row.
- No fallback that reparses all rollout JSONL files during normal Dock Home
  refresh.

Budgets and caps:

- App-server registry refresh interval stays in relay constants, not scattered
  literals.
- Registry refresh uses bounded endpoint concurrency.
- Per-endpoint loaded-row reads use bounded thread-read concurrency.
- `LIVE_LOADED_LIST_LIMIT` remains an explicit cap, currently `2_000` in
  `scripts/dock-relay-constants.mjs:42`.
- `LIVE_STATUS_REFRESH_INTERVAL_MS` remains explicit, currently `2_500` ms in
  `scripts/dock-relay-constants.mjs:44`.
- `LIVE_STATUS_UPSTREAM_TIMEOUT_MS` remains explicit, currently `5_000` ms in
  `scripts/dock-relay-constants.mjs:45`.
- Upstream pool caps remain explicit, currently `history: 1` and
  `live-status: 4` in `scripts/dock-relay-constants.mjs:48`.

For thousands of history threads, Dock Home should render from the relay state
table and bounded `dock/*` windows, not by asking Swift or the relay to
reconstruct all history on every screen update.

# 8) Hard-Cut Deletion List

Delete or replace these normal-path concepts:

- Dock-owned raw app-server launchd/systemd service.
- `.codex-dock/app-server.token` as a normal service dependency.
- `APP_SERVER_PORT`, `APP_SERVER_LISTEN`, and `DOCK_RELAY_HISTORY_WS` as the
  normal Dock-owned raw server path.
- Relay assumption that `historyUrl` is a single hard-coded
  `ws://127.0.0.1:4500`.
- Service dependency that starts relay after `codex-dock-app-server.service`.
- Tests that require Dock to start a raw `:4500` app-server in the normal path.
- Docs that describe `ws://127.0.0.1:4500` as the canonical Dock history
  service.

Keep or reshape:

- Dock relay `:4510` as the only phone-facing endpoint.
- Relay-owned `dock/*` snapshot/delta/resync contract.
- Bounded upstream connection pool.
- Live status cache, but fed by the registry instead of manual endpoint config.
- Explicit fixture endpoints for tests.
- Raw app-server WebSocket helper only as a test/diagnostic tool, not the normal
  host service.

# 9) Acceptance Evidence For The Architecture

The implementation is not done until these are true:

- `rtk npm run test:relay` proves the registry discovers multiple fake
  app-server endpoints and merges live rows by owner.
- Relay tests prove the Unix app-server upstream path works, or the selected
  Codex proxy path works, before daemon history is treated as the normal path.
- Relay tests prove daemon history failure is loud and visible in `/statusz`
  when no valid history endpoint exists.
- Relay tests prove no Dock-owned raw app-server service is rendered by
  `scripts/codex-dock-host-service.mjs`.
- Relay tests prove private `stdio://` app-server processes are classified as
  observed-but-unreachable, not silently ignored and not treated as live owners.
- Relay tests prove the history endpoint is the Codex daemon Unix socket or an
  explicit test fixture, not `ws://127.0.0.1:4500`.
- Relay tests prove request handlers use cached registry state and do not run
  process discovery directly.
- Relay tests prove bounded behavior with many persisted history rows and many
  discovered endpoints.
- Swift tests prove the app can display registry/route degradation without
  surfacing raw app-server secrets or raw private endpoints to the phone.
- Simulator proof shows a visible live badge for a thread owned by a discovered
  non-Dock app-server endpoint.
- Local runtime proof prints discovered app-server counts and shows the relay is
  querying every addressable app-server instance on the machine.
- Local runtime proof distinguishes attachable `ws://` endpoints from observed
  private `stdio://` and in-process runtimes. It must not claim full-machine
  live coverage when Codex gives Dock no attachable endpoint.
- Home relay proof repeats the same checks on
  `/home/aelaguiz/workspace/codex-client`.

# 10) Decision Log

## 2026-06-05 - Intent-derived - Dock-owned raw app-server is not acceptable

The user explicitly wants a hard cut away from the broken method and no legacy
fallback. The target architecture therefore deletes Dock's private raw
`ws://127.0.0.1:4500` service instead of keeping it as a compatibility bridge.

## 2026-06-05 - Evidence-derived - Aggregation is viable only for addressable app-servers today

Machine probes showed 11 non-Dock WebSocket app-server endpoints were
addressable and queryable. The same machine also had 14 `stdio://` app-server
processes with no attachable URL. The architecture must aggregate addressable
endpoints now and expose private app-server limitations honestly.

## 2026-06-05 - Evidence-derived - Existing relay code has useful pieces but wrong ownership

`collectLiveRows`, `LiveStatusCache`, and `SessionRouter` already model much of
the needed live aggregation. The hard cut should not invent a separate parallel
system; it should move discovery and endpoint ownership into one registry and
delete the raw `:4500` service path.

## 2026-06-05 - Fresh Consult Composer Fast 2.5 - Pass with notes

Fresh Consult validated the core model: app-server live state is process-local,
Dock's private `:4500` app-server can read shared history but not other
runtimes' live state, and private `stdio://` plus in-process runtimes are not
externally attachable. The implementation resolved the Dock-side blockers by
adding `AppServerRegistry` and native Unix upstream support. Discovered
`ws://` app-server endpoints are still experimental in Codex, and live
aggregation still cannot cover private runtimes without upstream Codex attach
or registry support.
