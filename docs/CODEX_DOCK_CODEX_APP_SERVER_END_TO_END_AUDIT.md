# Codex App-Server End-To-End Audit For Codex Dock

Status: evergreen reference, with a runtime incident section from 2026-05-29.

Scope:

- Codex source read from `/Users/aelaguiz/workspace/codex`.
- Dock client and relay source read from
  `/Users/aelaguiz/workspace/codex-client`.
- Runtime probes captured under `/tmp/codex-client/20260529T005637Z/`.
- No secrets, bearer tokens, raw prompt text, transcript text, raw audio, or
  full JSON-RPC payloads are quoted here.

## Executive Summary

Codex Dock should treat Codex as two related data planes, not one endpoint:

1. The history plane reads persisted rollout/session data from `~/.codex` via
   `thread/list`, `thread/read`, and `thread/turns/list`.
2. The live plane reads currently loaded in-memory threads from running
   app-server processes via `thread/loaded/list`, `thread/read`, subscriptions,
   and status notifications.

For phones, the intended path is:

```text
iPhone or simulator
  -> ws://<Mac host>:4510
  -> Dock relay
  -> raw history app-server at ws://127.0.0.1:4500
  -> per-session live app-servers at ws://127.0.0.1:<ephemeral-port>
```

The phone should not connect directly to the raw authenticated `:4500`
app-server in the normal local path. The Dock relay owns the raw history bearer
token and presents a phone-safe relay surface on `:4510`.

The 2026-05-29 stale/newest ordering incident is not caused by the raw Codex
history app-server being unable to see current sessions. The raw history
app-server returned current rows. The failure is in the Dock relay and client
projection layer:

- The relay had about 10,900 open upstream WebSocket connections to
  `127.0.0.1:4500`.
- The relay's live endpoint discovery was failing with `spawnSync ps EBADF`.
- `thread/list` in the relay logs live failure but still returns history-only
  rows, which hides the live failure from the app.
- `thread/loaded/list` in the relay fails outright when live discovery fails.
- The relay merge path sorts live rows and history-only rows separately, then
  concatenates live rows before history-only rows. That is not a global recency
  sort.
- The simulator had three aliases for the same relay, which multiplied reload
  load and produced duplicate host views.

## Code Map

Codex source of truth:

- `codex-rs/app-server/src/main.rs`
  - App-server CLI entrypoint.
  - Defines `--listen`, `--session-source`, WebSocket auth flags, and hidden
    `--remote-control`.
- `codex-rs/app-server/src/lib.rs`
  - Runtime startup. Starts stdio, Unix socket, WebSocket, or remote control
    transport.
- `codex-rs/app-server-transport/src/transport/websocket.rs`
  - WebSocket acceptor, connection lifecycle, and close propagation.
- `codex-rs/app-server-transport/src/transport/auth.rs`
  - WebSocket auth modes and token validation.
- `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
  - Thread RPC DTOs, including `ThreadListParams` and
    `ThreadLoadedListResponse`.
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
  - Main implementation of `thread/list`, `thread/loaded/list`,
    `thread/read`, `thread/resume`, `thread/turns/list`, and thread status
    overlay.
- `codex-rs/app-server/src/filters.rs`
  - `sourceKinds` interpretation.
- `codex-rs/thread-store/src/local/list_threads.rs`
  - Local persisted history listing from rollout/state DB data.
- `codex-rs/app-server/src/thread_status.rs`
  - In-memory loaded-thread status tracking.
- `codex-rs/core/src/thread_manager.rs`
  - Current process's loaded thread registry.

Dock source of truth:

- `Makefile`
  - Canonical service, simulator, and physical-device entrypoints.
- `scripts/dock-relay.mjs`
  - Dock relay server entrypoint.
- `scripts/dock-relay-thread-data.mjs`
  - Relay history/live aggregation, endpoint discovery, preview enrichment, and
    merge behavior.
- `scripts/dock-relay-json-rpc-client.mjs`
  - Relay upstream JSON-RPC WebSocket client.
- `CodexDock/State/DockStore.swift`
  - Swift app session loading and `thread/list` params.
- `CodexDock/State/DockSessionProjection.swift`
  - UI filtering and sorting.
- `CodexDock/State/SessionRowProjector.swift`
  - Codex status to Dock row status mapping.

## App-Server Transport Model

The app-server binary supports multiple transports. The CLI in
`codex-rs/app-server/src/main.rs` defines `--listen` with supported values:

```text
stdio://
unix://
unix://PATH
ws://IP:PORT
off
```

It also defines `--session-source`, defaulting to `vscode`, and WebSocket auth
arguments. The default session source matters because source filtering later
classifies threads by `cli`, `vscode`, `exec`, `appServer`, and sub-agent
variants.

Runtime startup in `codex-rs/app-server/src/lib.rs` chooses the transport:

- `stdio://` starts one stdio connection.
- `unix://` starts a Unix domain socket acceptor.
- `ws://IP:PORT` starts a WebSocket acceptor.
- `off` starts no normal transport.
- Remote control can also be enabled when state DB support is available.

There are four app-server modes that matter to Dock's mental model:

- normal app-server: a local transport acceptor plus one in-memory runtime;
- remote-control app-server: the same runtime plus a remote-control WebSocket
  bridge;
- in-process app-server: no OS socket/process boundary, but the same
  `MessageProcessor` semantics over in-memory channels;
- managed daemon: Unix-control-socket app-server launched by the daemon path,
  usually `app-server --listen unix://`, optionally with `--remote-control`.

The current Dock relay live discovery only finds one narrow subset of that
space: command lines matching `codex app-server --listen
ws://127.0.0.1:<port>`. It will not discover stdio, Unix daemon, remote-control
temporary sockets, or in-process app-server clients.

The WebSocket transport refuses unauthenticated non-loopback listeners. In
`codex-rs/app-server-transport/src/transport/websocket.rs`, a non-loopback
WebSocket listener without auth fails with an error requiring either
`--ws-auth capability-token` or `--ws-auth signed-bearer-token`.

The raw Dock-managed history app-server observed during this incident was:

```text
codex app-server --listen ws://127.0.0.1:4500 \
  --ws-auth capability-token \
  --ws-token-file /Users/aelaguiz/workspace/codex-client/.codex-dock/app-server.token
```

That process is intentionally loopback-only. The phone-safe network listener is
the Dock relay on `0.0.0.0:4510`, not this raw app-server.

## WebSocket Auth Model

`codex-rs/app-server-transport/src/transport/auth.rs` supports two app-server
WebSocket auth modes:

- `capability-token`
  - Configured by `--ws-auth capability-token`.
  - Requires either `--ws-token-file` or `--ws-token-sha256`.
  - The client sends a bearer token that matches the configured token or hash.
- `signed-bearer-token`
  - Configured by `--ws-auth signed-bearer-token`.
  - Requires `--ws-shared-secret-file`.
  - Can also validate issuer, audience, and clock skew.

Dock uses `capability-token` for the raw history app-server. The Dock relay
reads the token file and uses it only on the Mac side. Simulator and physical
device launches must not pass the raw app-server token into the app.

## Port System

There are three port classes that matter for Dock.

### Raw History Port

`ws://127.0.0.1:4500` is the Dock-managed raw history app-server.

Its job is to answer history-oriented requests against Codex home and local
state:

- `thread/list`
- `thread/read`
- `thread/turns/list`
- archive/unarchive style operations

Because this endpoint is a single app-server process, its in-memory status view
only covers threads loaded in that one process. It does not automatically know
live statuses held by other app-server processes.

### Dock Relay Port

`ws://<Mac host>:4510` is the phone-facing relay.

Observed advertised/local aliases during this incident:

- `ws://127.0.0.1:4510`
- `ws://192.168.50.117:4510`
- `ws://Amir-M5.local:4510`
- `ws://amir-m5.fairy-salmon.ts.net:4510`

All four aliases reached the same relay during the probe.

The relay is expected to:

- hide raw app-server auth from phones;
- read persisted history from `ws://127.0.0.1:4500`;
- discover live app-server endpoints on loopback;
- query live endpoints for loaded thread IDs and live statuses;
- merge history and live rows into a phone-safe result.

### Live App-Server Ports

Live Codex processes can run their own app-server listeners on random loopback
ports, for example:

```text
codex app-server --listen ws://127.0.0.1:<ephemeral-port>
```

During the incident there were many such processes. The Dock relay discovers
them by running `ps` and matching:

```text
codex app-server --listen ws://127.0.0.1:<port>
```

This discovery is implemented in `scripts/dock-relay-thread-data.mjs`.

This is brittle by design:

- if `ps` fails, live discovery fails;
- if process command lines change, live discovery misses endpoints;
- if the relay runs out of usable descriptors, `spawnSync ps` can fail before
  endpoint collection begins.

## Thread History Model

`thread/list` is not just "what is loaded right now." It lists persisted Codex
threads.

The protocol is defined by `ThreadListParams` in
`codex-rs/app-server-protocol/src/protocol/v2/thread.rs`. Important fields:

- `limit`
- `cursor`
- `sortKey`
- `sortDirection`
- `modelProviders`
- `sourceKinds`
- `archived`
- `cwd`
- `useStateDbOnly`
- `searchTerm`

The processor in
`codex-rs/app-server/src/request_processors/thread_processor.rs` defaults
omitted `sortKey` to `createdAt`. Dock explicitly sends `updatedAt`.

`modelProviders` is subtle:

- omitted means "current configured provider only";
- present but empty means "include all providers."

Dock intentionally sends `modelProviders=[]`, because a phone dashboard should
not hide sessions just because they used a different provider.

`useStateDbOnly` is also important:

- `false` or omitted means scan rollout JSONL files and repair/update state DB
  metadata as needed;
- `true` means read only from the state DB.

Dock does not set `useStateDbOnly`, so the raw history endpoint uses the
scan-and-repair behavior.

The local listing implementation is in
`codex-rs/thread-store/src/local/list_threads.rs`. It calls rollout listing
functions such as `RolloutRecorder::list_threads` and
`RolloutRecorder::list_archived_threads`, then attaches metadata titles from
state DB or legacy rollout-derived title lookup.

Timestamp and pagination details:

- State DB stores millisecond timestamps.
- v2 `Thread.createdAt` and `Thread.updatedAt` are returned as Unix seconds in
  `thread_processor.rs`, so multiple updates within one second can tie on the
  wire.
- Conversation summaries preserve RFC3339 milliseconds, but Dock uses v2
  `Thread` rows for `thread/list`.
- Filesystem rollout cursors are timestamp-only. Rollout filename ordering is
  timestamp plus UUID, but the cursor does not carry the UUID.
- SQLite listing also orders and anchors by timestamp only.

These timestamp details are not the primary cause of the 2026-05-29 incident,
but they are real edge cases near page boundaries and tie-breaking. Relay-side
global sorting should use stable tie-breakers after dedupe.

## Source Kind Filtering

`sourceKinds` defaults are easy to misunderstand.

`codex-rs/app-server/src/filters.rs` implements this rule:

- omitted `sourceKinds` means interactive sources only;
- empty `sourceKinds` also means interactive sources only;
- interactive currently means Codex core `cli`, `vscode`, custom `atlas`, and
  custom `chatgpt`;
- agent/non-interactive variants require a post-filter path.

That means a client that wants agents must explicitly ask for agent source
kinds. Dock does this by issuing two scopes:

- human/default scope with `sourceKinds=nil`;
- agent scope with `exec`, `appServer`, sub-agent variants, and `unknown`.

This is correct. It also doubles the number of list calls per host.

## Status Model

Persisted history and live status are not the same thing.

In `thread_processor.rs`, `thread/list`:

1. reads stored threads through `list_threads_common`;
2. converts stored rows to API `Thread` objects;
3. asks `thread_watch_manager.loaded_statuses_for_threads(...)`;
4. overlays any in-memory loaded status onto those rows.

`ThreadWatchManager` lives inside one app-server process. Its state is
process-local. `thread_status.rs` returns `ThreadStatus::NotLoaded` for an
untracked thread.

That means:

- a fresh row from `thread/list` can still be `notLoaded`;
- `notLoaded` on the raw `:4500` app-server does not prove the real Codex
  session is dead;
- it can mean the live thread is loaded in a different app-server process.

For Dock, this is why the relay must query live per-session app-server
endpoints and overlay live rows/statuses.

## Loaded Thread Model

`thread/loaded/list` is defined as "Thread ids for sessions currently loaded in
memory" in `ThreadLoadedListResponse`.

In `thread_processor.rs`, `thread/loaded/list` returns
`self.thread_manager.list_thread_ids()`. In `codex-rs/core/src/thread_manager.rs`,
that list comes from the current process's loaded threads and filters out
internal session sources.

Important implications:

- `thread/loaded/list` is process-local;
- it is not a global session index;
- it is not sorted by recency;
- a raw history app-server on `:4500` may return few or zero loaded IDs even
  while many other Codex sessions are active in other processes.

The Dock relay's loaded-list endpoint is therefore synthetic: it discovers many
loopback live endpoints, calls each one's `thread/loaded/list`, reads those
threads, and aggregates IDs.

## Thread Lifecycle Model

Loaded status is lifecycle state inside one app-server process.

Starting a thread:

1. `thread/start` loads config from request overrides and project context.
2. It calls `ThreadManager::start_thread_with_options`.
3. It auto-attaches a listener for the request connection.
4. It upserts the thread into `ThreadWatchManager`.
5. It sends a `ThreadStartResponse`.
6. It broadcasts a `ThreadStarted` notification.

Resuming a thread:

1. `thread/resume` first checks whether the requested thread is already loaded
   in that same process.
2. If the thread is already running or loaded, it uses a running-thread resume
   path and attaches the caller to the existing listener.
3. If it is not loaded, it reconstructs the thread from rollout/history and
   calls `ThreadManager::resume_thread_with_history`.
4. It upserts the resumed thread into `ThreadWatchManager`.
5. It sends a `ThreadResumeResponse`.

Unsubscribing:

1. `thread/unsubscribe` removes the connection from that thread's subscription
   set.
2. It does not immediately mean the thread is gone from memory.
3. If the thread is missing from `ThreadManager`, app-server finalizes local
   bookkeeping and returns `notLoaded`.

Idle unload:

- `THREAD_UNLOADING_DELAY` is 30 minutes.
- A loaded thread is eligible to unload only after it has no subscribers and is
  inactive for that delay.
- The unload path removes thread state, shuts the thread down, removes it from
  `ThreadManager`, removes it from `ThreadWatchManager`, and emits
  `ThreadClosed`.
- If shutdown submit fails or times out, the thread can remain loaded.

Dock implication:

- A thread can be current in persisted history but not loaded in the raw history
  app-server.
- A thread can be loaded in a per-session app-server but invisible to raw
  `:4500` loaded state.
- A disconnected UI can leave a loaded idle cache entry for up to 30 minutes.
- A proper Dock "live" view must aggregate all relevant live app-server
  processes, not just the Dock-managed history app-server.

## Read And Turns Model

`thread/read` and `thread/turns/list` can read persisted history, but active
threads may also exist in memory.

For `thread/turns/list`, `thread_processor.rs` first tries `thread_store`.
If the persisted rollout cannot be found, it can fall back to a loaded thread
from `thread_manager`, unless the loaded thread is ephemeral and does not
support persisted turns.

For Dock previews, the relay currently enriches list rows by calling
`thread/turns/list` per row. This is expensive because it creates many upstream
connections when done against the raw history app-server for every app refresh.

## Dock Relay Aggregation Model

The relay implementation in `scripts/dock-relay-thread-data.mjs` does these
steps for normal `thread/list`:

1. Read history rows from the raw history endpoint with `readHistoryThreadList`.
2. Discover live app-server endpoints with `discoverLoopbackEndpoints`.
3. Query each live endpoint with `readLoadedRows`.
4. Filter live rows by requested `sourceKinds`.
5. Merge live and history rows.
6. Enrich previews by calling `thread/turns/list` per row.
7. Return the resulting rows to the app.

The intended model is sound: history gives broad recency, live endpoints give
accurate in-memory status and routing.

The current implementation has three key risks.

### Risk 1: Per-Operation Upstream Connections

`withClient` creates a new `JsonRpcWebSocketClient` for each operation, then
calls `client.close()` in `finally`.

This pattern is used for:

- every history `thread/list`;
- every history `thread/read`;
- every `thread/turns/list` preview lookup;
- live endpoint reads.

For one app refresh, the simulator may have three configured hosts, two scopes
per host, and up to 200 rows per scope. Even with concurrency limits, this can
create a large number of upstream WebSockets repeatedly.

### Risk 2: Weak Close Semantics Under Timeout

`scripts/dock-relay-json-rpc-client.mjs` has two important behaviors:

- `request()` timeout rejects the pending request but does not close or
  terminate the socket.
- `close()` calls `this.ws.close()` and immediately drops `this.ws`; it does not
  wait for a close event or forcefully terminate on timeout.

Under normal conditions this may be enough. Under repeated timeout pressure, it
can leave established sockets behind. That matches the incident evidence: about
10,900 open relay-to-history WebSocket connections.

### Risk 3: Hidden Live Failure

`aggregateThreadList` uses `Promise.allSettled` for history and live collection.
If live collection fails but history succeeds, it logs `thread_list.live_failed`
and returns history-only rows.

That means the app can show plausible rows while live status, loaded status,
and live routing are broken.

By contrast, `aggregateLoadedList` does not catch live collection failure. When
discovery fails, `thread/loaded/list` fails outright.

## Relay Merge Semantics

`mergeThreadListRows` currently:

1. builds a history map by thread ID;
2. freshens live row timestamps from history when history is newer;
3. sorts live rows;
4. sorts history-only rows;
5. returns all sorted live rows first, then enough sorted history-only rows to
   fill the requested limit.

That final concatenation is not a global recency sort. It can put stale live
rows above fresher history-only rows.

This matters for "Newest" because some current sessions can be history-only
when live discovery misses or cannot read their endpoint. Even when live
discovery works, the final page can still be wrong if a stale live row appears
before a newer history-only row.

## Swift App Query And Projection Model

The Swift app does not display raw `thread/list` output directly.

`CodexDock/State/DockStore.swift` sends `thread/list` with:

- `limit=200`
- `sortKey=updatedAt`
- `sortDirection=desc`
- `modelProviders=[]`
- `sourceKinds` from the selected scope
- `archived` from the selected scope

It loads multiple scopes per host:

- interactive/default scope;
- agent scope.

`CodexDock/State/DockSessionProjection.swift` then:

1. flattens all section rows;
2. filters by search text;
3. hides idle rows by default because `showsIdle=false`;
4. filters by selected tab;
5. sorts the remaining rows for "Newest."

`CodexDock/State/SessionRowProjector.swift` maps statuses like this:

- Codex `idle` -> Dock `idle`
- Codex `active` + waiting flag -> Dock `needsMe`
- Codex `active` without waiting flag -> Dock `running`
- Codex `notLoaded` -> Dock `limited`
- Codex `systemError` -> Dock `failed`

So the app's "Newest" list means "newest among visible projected rows," not
"the exact newest raw Codex history rows." If idle is hidden, a truly newest
idle row can disappear from the visible list.

## Runtime Evidence From 2026-05-29

Raw history app-server:

- `ws://127.0.0.1:4500`
- capability-token auth from `.codex-dock/app-server.token`
- process PID observed as `57538` for the actual app-server binary
- wrapper PID observed as `57537`

Dock relay:

- `0.0.0.0:4510`
- advertised as `Amir-M5`
- uses `ws://127.0.0.1:4500/` as history URL
- process PID observed as `57717`

Live app-servers:

- many `codex app-server --listen ws://127.0.0.1:<port>` processes were
  running.

Recent session files:

- `~/.codex/sessions/2026/05/28/*.jsonl` mtimes were current to
  `2026-05-29T00:57Z`.

Direct JSON-RPC probes:

- Raw history interactive/default scope returned 100 rows with newest
  `updatedAt=2026-05-29T01:01:33Z`.
- Raw history agent scope returned 100 rows with newest
  `updatedAt=2026-05-29T01:01:05Z`.
- Dock relay interactive/default scope returned 100 rows with newest
  `updatedAt=2026-05-29T01:01:34Z`.
- Dock relay agent scope returned 109 rows, but the top row in that probe was
  `updatedAt=2026-05-29T00:43:33Z`.

Relay health:

- Relay logs showed `thread_list.live_failed` with `spawnSync ps EBADF`.
- Relay logs then showed `thread_list.loaded` with `historyRows=100`,
  `liveRows=0`, `endpoints=0`, `failedEndpoints=1`, and `returnedRows=100`.
- Direct `thread/loaded/list` through relay failed with
  `thread/loaded/list: spawnSync ps EBADF`.
- Relay PID `57717` had about 10,958 `lsof` rows.
- About 10,900 of those were relay outbound connections to
  `127.0.0.1:4500`.
- Raw history app-server PID `57538` had about 10,961 `lsof` rows.

Device and simulator:

- iPhone 17 Pro was intentionally not touched after Amir said he was using it.
- iPhone 14 ID `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC` had app build
  `20260529004335`.
- iPhone 14 relay config contained only `Amir-M5.local:4510`.
- iPhone 14 config verification failed because the expected Makefile config
  also included an IP fallback.
- Physical device log collection failed with
  `log: Must be root to collect logs from attached device`.
- Simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` had three relay aliases:
  Tailscale domain, LAN IP, and Bonjour `.local`.
- Simulator logs showed successful reloads with `hosts=3`, around 609 to 627
  rows, `mapping_failures=0`, and `scope_failures=0`.

## Ruled-Out Causes

The raw Codex history app-server is not the primary cause.

Evidence:

- direct raw `thread/list` returned current rows;
- recent rollout JSONL mtimes were current;
- public relay aliases all reached the relay and returned current rows.

Tailscale vs Bonjour is not the primary cause.

Evidence:

- local loopback, LAN IP, Bonjour, and Tailscale aliases all reached the same
  relay;
- the stale/wrong view can happen before DNS differences matter because the
  relay's internal live discovery is unhealthy.

Swift mapping decode failure is not the primary cause.

Evidence:

- simulator logs showed `mapping_failures=0`;
- simulator reloads completed successfully;
- the app received hundreds of rows.

iPhone 14 config drift exists, but it is not the root of the stale-sort
incident.

Evidence:

- the iPhone 14 is local-only, which should be fixed for config correctness;
- the same unhealthy relay path is used by every alias;
- raw and public probes show the main data issue inside relay aggregation.

## Root Cause

The Dock relay is doing too much per-row and per-scope upstream WebSocket work
against the raw history app-server, then not closing or terminating those
upstream sockets strongly enough under timeout pressure.

That produces thousands of established relay-to-history sockets. Once the relay
is descriptor-stressed, `spawnSync ps` fails with `EBADF`, so live endpoint
discovery fails. Normal `thread/list` then hides live failure and returns
history-only rows. The app sees a plausible but degraded dataset, with stale or
wrong statuses and possible ordering errors.

There is also an independent merge bug: live rows and history-only rows are not
globally sorted after merging. This can make "Newest" wrong even after the file
descriptor leak is fixed.

The fresh Codex consult also identified two non-primary but real Codex-side
edge cases to keep in the model:

- Dock relay live discovery misses valid app-server modes beyond loopback
  WebSocket processes with one exact argv shape.
- Codex history pagination and v2 timestamps can lose tie precision around
  same-second rows.

Finally, simulator config amplified the issue by registering three aliases for
the same relay. That triples host-scope reload pressure and makes visible
duplicates likely.

## Correct Mental Model For Future Work

Use this model when changing Codex Dock:

- `:4500` is the raw authenticated history endpoint.
- `:4510` is the phone-facing relay endpoint.
- random loopback app-server ports are live session endpoints.
- `thread/list` is persisted history plus process-local status overlay.
- `thread/loaded/list` is process-local loaded IDs, not a global index.
- `notLoaded` from `:4500` can be normal for a live thread loaded elsewhere.
- Dock relay must overlay live process data onto history data.
- Relay live failure must be visible to diagnostics and, when it affects user
  truth, visible to the app.
- A phone-path pass requires relay-backed host path behavior, not loopback-only
  or mock proof.

## Fix Direction

No code fix was implemented as part of this audit. The fix should be driven by
Makefile targets and tested through the relay/app paths.

Required fixes:

1. Stop the relay from opening one upstream history WebSocket per list row.
   Use connection reuse, pooling, batching, or remove per-row preview enrichment
   from the list path.
2. Make `JsonRpcWebSocketClient.close()` await a real close or force terminate
   after a short timeout.
3. On request timeout, close or terminate the upstream socket, because it is no
   longer trustworthy for bounded relay work.
4. Make `aggregateThreadList` expose live failure to diagnostics and possibly to
   the app response metadata instead of silently returning a degraded result.
5. Globally sort the final merged live/history rows by the requested sort key
   and direction after dedupe and timestamp freshening.
6. Deduplicate equivalent host aliases in the app/registry layer or mark them as
   connection fallbacks for one logical host, not three independent hosts.
7. Replace or harden `ps` command-line scraping so Dock can reason about valid
   app-server modes and report what it cannot discover.
8. Repair iPhone 14 config drift so it intentionally uses the correct local
   config for that device.
9. Keep iPhone 17 Pro on the Tailscale config, but do not test it while Amir is
   using it.

Required tests:

1. Relay unit test proving `mergeThreadListRows` globally sorts mixed live and
   history-only rows.
2. Relay unit test proving live discovery failure is surfaced in a structured
   way and does not silently look healthy.
3. Relay client test proving timed-out upstream requests close or terminate the
   socket.
4. Integration or simulator test proving duplicate aliases do not produce three
   logical host sections for the same relay.
5. App projection test proving hidden idle rows can explain why a raw-newest row
   is not visible when `showsIdle=false`.
6. Metadata-only regression test for same-second updated rows, so relay sorting
   and pagination tie-breaks stay deterministic.

Required operational checks after fix:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk npm run test:relay
rtk swift test --filter DockStoreTests
rtk make app SIM='iPhone 17'
rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC DEVELOPMENT_TEAM=<team-id>
```

Use iPhone 14 for physical local-path testing. Do not use iPhone 17 Pro for
automated testing while Amir is using it.

## Diagnostic Commands

Status:

```bash
rtk make app-server-status
rtk make dock-relay-status
```

Find raw history app-server and relay:

```bash
pgrep -fl 'dock-relay.mjs|codex app-server --listen ws://127.0.0.1:4500'
```

Count relay descriptors:

```bash
lsof -nP -p <relay-pid> | wc -l
```

Count relay connections to raw history:

```bash
lsof -nP -p <relay-pid> | awk '/127\.0\.0\.1:[0-9]+->127\.0\.0\.1:4500/ {n++} END {print n+0}'
```

Read relay logs:

```bash
rtk make dock-relay-logs
```

Simulator logs:

```bash
rtk make sim-logs SIM='iPhone 17'
```

Physical iPhone logs:

```bash
rtk make device-logs DEVICE=<device-udid>
```

If physical log collection fails with
`log: Must be root to collect logs from attached device`, record that exact
blocker and continue with simulator/local proof where it is valid.

## Review Checklist

Before claiming this class of issue is fixed:

- raw history `thread/list` has current rows;
- relay `thread/list` has current rows for human and agent scopes;
- relay `thread/loaded/list` succeeds;
- relay logs do not show `spawnSync ps EBADF`;
- relay file descriptor count is stable across repeated app reloads;
- live endpoint count is nonzero when live Codex sessions exist;
- merged relay rows are globally sorted by `updatedAt` for "Newest";
- simulator has one logical host for the relay, even if multiple fallback
  endpoints exist;
- iPhone 14 and iPhone 17 Pro keep intentionally different configs;
- no phone receives raw app-server auth material.
