# Codex Dock Thread Sort Root Cause Worklog

Date: 2026-05-29
Scope: Diagnose why simulator, iPhone 14, and iPhone 17 Pro show stale or wrong
newest-thread ordering before implementing a fix.

## Current Stop Rule

- Root-cause only. Do not implement the fix until Amir has read the diagnosis.
- Add diagnostics/tests only if needed to prove the cause.
- Keep raw dumps outside the repo under `/tmp/codex-client/20260529T005637Z/`.

## Evidence Log

### 2026-05-29T00:56Z - Investigation Started

- User reports the running simulator, iPhone 14, and iPhone 17 Pro show stale
  session rows such as `1 hours ago`, `2 hours ago`, or `3 hours ago`, while
  active Codex threads are running on this Mac.
- Hypothesis space: live Codex app-server session discovery, raw app-server
  session listing, Dock relay projection/sorting, Swift client sorting, and
  device-specific endpoint/config drift.

### 2026-05-29T01:00Z - Parallel Codex App-Server Consult Started

- User asked for a fresh GPT/GBT 5.5 xhigh consult to audit Codex itself:
  app-server model, ports, sessions, lifecycle, and Dock-relevant assumptions.
- Resolved `GBT55XI` to `runtime=codex`, `model=gpt-5.5`, `effort=xhigh`
  using `codex debug models`; `gpt-5.5` is available and supports `xhigh`.
- Consult run directory:
  `/tmp/fresh-consult/parallel-codex-app-server-audit-20260529T010032Z-jBDCmE/codex-gpt55xi-app-server-audit`.
- Consult constraints: read-only, no file edits, no service/device mutation, no
  secrets, no raw prompt/transcript/session-content quoting.

### 2026-05-29T01:01Z - Current Runtime Shape From Process Inventory

- There is one Dock-managed raw history app-server on `ws://127.0.0.1:4500`
  launched with bearer/capability token auth and token file
  `.codex-dock/app-server.token`.
- There is one Dock relay on `0.0.0.0:4510`, advertised as `Amir-M5`, forwarding
  phone traffic to the relay and using `ws://127.0.0.1:4500/` as its history
  source.
- There are many additional live `codex app-server --listen
  ws://127.0.0.1:<port>` processes. These look like per-session or per-agent
  live control surfaces, not the single history index endpoint.
- Recent `~/.codex/sessions/2026/05/28/*.jsonl` file mtimes are current to
  `2026-05-29T00:57Z`, which means the disk session layer is actively changing
  even if the UI shows only rows from one or more hours ago.

### 2026-05-29T01:01Z - Raw App-Server And Relay Thread Probes

Raw dump:
`/tmp/codex-client/20260529T005637Z/jsonrpc-thread-probe.json`.

- Raw history app-server, interactive/default scope:
  `thread/list` returned 100 rows. The newest row had
  `updatedAt=2026-05-29T01:01:33Z`, age 0 minutes, status `notLoaded`.
- Raw history app-server, agent scope:
  `thread/list` returned 100 rows. The newest row had
  `updatedAt=2026-05-29T01:01:05Z`, age 0 minutes, status `notLoaded`.
- Dock relay, interactive/default scope:
  `thread/list` returned 100 rows. The newest row had
  `updatedAt=2026-05-29T01:01:34Z`, age 0 minutes, status `active`.
- Dock relay, agent scope:
  `thread/list` returned 109 rows, but the newest row returned by that probe had
  `updatedAt=2026-05-29T00:43:33Z`, age 18 minutes, status `idle`.
- Interpretation: the raw history app-server can see fresh rows. The stale or
  wrong ordering is introduced after the raw history layer, in relay live merge,
  relay health, or client projection.

Raw dump:
`/tmp/codex-client/20260529T005637Z/public-endpoint-probe.json`.

- `ws://127.0.0.1:4510`, `ws://192.168.50.117:4510`,
  `ws://Amir-M5.local:4510`, and
  `ws://amir-m5.fairy-salmon.ts.net:4510` all accepted relay WebSocket
  connections and returned current `thread/list` rows.
- Interpretation: the active failure is not simply "Tailscale vs local DNS can
  not reach the relay." All aliases reach the same unhealthy relay.

### 2026-05-29T01:05Z - Relay Live Discovery Failure And File Descriptor Leak

- Dock relay logs show `thread_list.live_failed` with `spawnSync ps EBADF`, then
  `thread_list.loaded` with `historyRows=100`, `liveRows=0`, `endpoints=0`,
  `failedEndpoints=1`, and `returnedRows=100`.
- A direct relay probe of `thread/loaded/list` failed with:
  `thread/loaded/list: spawnSync ps EBADF`.
- Current descriptor count while investigating:
  - Relay PID `57717`: about 10,958 `lsof` rows.
  - Relay outbound connections to raw history app-server
    `127.0.0.1:4500`: about 10,900.
  - Raw history app-server binary PID `57538`: about 10,961 `lsof` rows.
- Interpretation: the relay and raw app-server are saturated with thousands of
  WebSocket connections between the relay and `ws://127.0.0.1:4500`.
  Once the relay is in this state, live endpoint discovery can no longer run
  `ps`, so live session collection fails before it can query per-session
  app-server endpoints.

### 2026-05-29T01:06Z - Relay Code Path That Explains The Leak And Wrong Merge

Files inspected:

- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-json-rpc-client.mjs`

Relevant behavior:

- `withClient` creates a new `JsonRpcWebSocketClient`, initializes it, runs one
  operation, then calls `client.close()` in `finally`.
- `readHistoryThreadList` opens a fresh WebSocket to the raw history app-server
  for every `thread/list`.
- `enrichThreadListPreviews` opens a separate `thread/turns/list` WebSocket per
  row, with concurrency 16 and a short timeout, to populate previews.
- `JsonRpcWebSocketClient.close()` only calls `this.ws.close()` and immediately
  nulls the reference. It does not wait for the `close` event, force terminate
  on timeout, or reject/drain pending work.
- `request()` timeout rejects the one request but does not close or terminate the
  socket. Under repeated timeout pressure, sockets can remain established.
- `aggregateThreadList` catches live collection failure, logs it, and returns
  history-only rows. That masks live failure from normal app UI reloads.
- `aggregateLoadedList` does not catch live collection failure. That makes
  `thread/loaded/list` fail outright with `spawnSync ps EBADF`.
- `mergeThreadListRows` sorts live rows and history-only rows separately, then
  concatenates all live rows before history-only rows. It does not globally sort
  the final merged page by recency. That can put stale live rows above fresher
  history rows even when live collection is healthy.

### 2026-05-29T01:07Z - Simulator And iPhone 14 Evidence

- iPhone 17 Pro was intentionally not tested after Amir said he was using it.
- iPhone 14 device ID observed:
  `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`.
- iPhone 14 installed app build observed:
  `20260529004335`.
- iPhone 14 app support readback:
  `/tmp/codex-client/20260529T005637Z/iphone14-appsupport/relay-config.json`.
- iPhone 14 relay config contains only:
  `{"endpoints":[{"host":"Amir-M5.local","port":4510}]}`.
- `rtk make device-config-verify DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
  APP_BUILD_NUMBER=probe-202605290104` failed because the Makefile expected
  both `Amir-M5.local:4510` and an IP fallback, while the phone readback only
  had `Amir-M5.local:4510`.
- Physical-device log collection was blocked by macOS permissions:
  `log: Must be root to collect logs from attached device`.
- Simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` had relay config:
  `amir-m5.fairy-salmon.ts.net:4510`, `192.168.50.117:4510`, and
  `Amir-M5.local:4510`.
- Simulator app logs showed repeated successful reloads with `hosts=3`,
  `rows=627` or `rows=609`, `mapping_failures=0`, and `scope_failures=0`.
- Interpretation: the simulator is loading the same relay through three aliases,
  which duplicates rows and multiplies relay load. The iPhone 14 has local-only
  config drift, but the local-only config is not the primary stale-sort cause
  because the same relay answers current rows on every reachable alias.

### 2026-05-29T01:08Z - Swift Client Projection Evidence

Files inspected:

- `CodexDock/State/DockStore.swift`
- `CodexDock/State/DockSessionProjection.swift`
- `CodexDock/State/SessionRowProjector.swift`

Relevant behavior:

- `AppServerDockClient` requests `thread/list` with `limit=200`,
  `sortKey=updatedAt`, `sortDirection=desc`, `modelProviders=[]`, and the
  current scope's `sourceKinds`.
- The Dock store loads both the interactive/default and agent scopes for each
  configured host.
- `DockSessionProjectionOptions` defaults `showsIdle=false`.
- Projection filters idle rows out before applying the selected tab and
  "Newest" sort.
- `SessionRowProjector` maps Codex `idle` to app `idle`, Codex `active` to
  `running` or `needsMe`, and Codex `notLoaded` to app `limited`.
- Interpretation: the app's "Newest" view is newest among visible rows after
  idle hiding, selected-tab filtering, duplicated hosts, and relay status
  projection. It is not a direct view of raw Codex `thread/list` ordering.

### 2026-05-29T01:12Z - Fresh GBT55XI Consult Completed

Consult output:
`/tmp/fresh-consult/parallel-codex-app-server-audit-20260529T010032Z-jBDCmE/codex-gpt55xi-app-server-audit/final.txt`.

- Consult verdict: `pass-with-notes`, confidence high, no blocking findings.
- It independently confirmed the core model:
  - app-server live state is instance-local;
  - `thread/list` is durable history plus per-process status overlay;
  - `thread/loaded/list` is loaded IDs for one app-server process, not a global
    recency or activity index;
  - Dock's history query params are mostly right;
  - relay discovery and relay live-first merge are fragile enough to explain
    stale newest rows without a Swift sorting bug.
- Extra findings folded into the evergreen audit:
  - app-server has normal, remote-control, in-process, and managed-daemon modes;
  - current relay discovery only finds one exact loopback WebSocket argv shape;
  - interactive source defaults currently include `cli`, `vscode`, custom
    `atlas`, and custom `chatgpt`;
  - v2 `Thread.updatedAt` is seconds precision even though state DB stores
    milliseconds;
  - rollout/state DB pagination has timestamp-only cursor/tie edge cases.

## Current Root Cause

The raw Codex app-server history layer is seeing fresh sessions. The wrong or
stale newest view is caused by the Dock relay and client projection layer:

1. The relay opens a large number of upstream WebSocket connections to the raw
   history app-server, especially during per-row preview enrichment.
2. Those upstream connections are not being closed strongly enough under timeout
   and repeated reload pressure, leaving about 10,900 relay-to-history
   connections open.
3. The relay then fails live endpoint discovery with `spawnSync ps EBADF`.
4. Normal `thread/list` hides that live failure and returns history-only rows,
   while `thread/loaded/list` fails outright.
5. When live collection is healthy, the relay still has a separate correctness
   bug: it concatenates sorted live rows before sorted history-only rows instead
   of globally sorting the final merged result.
6. The simulator config triples the same relay under three aliases, multiplying
   load and visible duplicates. The iPhone 14 is local-only and missing the
   expected IP fallback, but that is a separate config drift rather than the
   main app-server/root-sort failure.

No fix has been implemented yet.
