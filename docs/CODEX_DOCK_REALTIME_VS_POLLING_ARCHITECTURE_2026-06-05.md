# Codex Dock Realtime vs Polling Architecture Analysis - 2026-06-05

## North Star

Make Codex Dock feel live without massively increasing overhead.

The right target is not "poll faster" and not "subscribe the phone to every
thread detail stream." The right target is:

- Use WebSocket push from relay to phone for all visible Dock, Archive, and open
  Thread Detail updates.
- Use Codex app-server events as low-latency invalidation signals.
- Do targeted reads only for the one thread that changed when the event does not
  contain enough card data.
- Keep full snapshots/reconciles for boot, recovery, sequence gaps, missed
  events, and historical correctness.

## Short Answer

These parts fundamentally do not have to be polling-driven:

- Phone app to Dock relay: Dock cards, Archive cards, and open Thread Detail can
  all be pushed over the existing WebSocket projection streams.
- Relay to phone: `dock/update`, `archive/update`, and `thread/detail/update`
  are already push notifications when the relay store changes.
- Open, attachable Codex threads: turn start/completion, item progress, command
  progress, approvals, user-input waits, and realtime transcript/audio already
  exist as Codex app-server events on a subscribed/resumed thread.
- Codex lifecycle/status facts: thread started, closed, renamed, archived,
  unarchived, and status-changed are already app-server notifications.

These can be mostly event-driven, but still need targeted reads for missing
fields:

- Dock card status and badges.
- Dock card order/activity time for active or recently changed threads.
- Dock card latest summary/latest message.
- Hidden child or subagent rollups.

These still need snapshots or reads unless Codex adds a broader feed:

- Initial Dock list and Archive list.
- Full recovery after a missed event, socket reconnect, sequence gap, or relay
  restart.
- Arbitrary historical/nonloaded thread latest-message and activity proof.
- Private stdio runtime detail events, because those runtimes are not attachable
  app-server endpoints.
- Process/app-server discovery, unless Codex exposes a registration/event API.

## Diagram

```text
iPhone Codex Dock app
  |
  | WebSocket to ws://<Mac>:4510
  | dock/subscribe, archive/subscribe, thread/detail/subscribe
  v
Dock relay on the Mac
  |
  | Owns one projection store:
  | - Dock cards
  | - Archive cards
  | - live leases/status overlays
  | - Thread Detail projection ledgers
  |
  +--> Codex daemon/history app-server
  |     - request/response: thread/list, thread/read, thread/turns/list
  |     - notifications: thread/name/updated, thread/status/changed, etc.
  |
  +--> attachable live Codex app-server endpoints
  |     - request/response: thread/loaded/list, thread/read, thread/resume
  |     - notifications after initialize/resume/listener attach
  |
  +--> private stdio Codex runtimes
        - visible through process/session metadata only
        - not attachable for live per-thread events
```

## Current System By Layer

### 1. Phone App

The phone app already has the right realtime shape.

`AppServerThreadCardStreamClient` defines a `ThreadCardStreamConnection` with
`subscribe()`, `resync()`, `updates()`, and `close()`; it connects to the relay,
initializes JSON-RPC, subscribes, and listens for notification methods matching
`dock/update` or `archive/update`.

`StreamReconciler` treats pushed envelopes as the main data path. It subscribes,
applies the initial snapshot, then loops over updates. It only resyncs/reconnects
for recovery reasons such as sequence gaps, heartbeat timeout, foreground
resume, manual refresh, or transport reconnect.

Phone-side timers are not the main data path:

- `AppServer.foregroundPollInterval = 250ms` is a foreground-work gate wait.
- `Dock.autoRefreshInterval = 5s` is a reconnect/resync safety delay.
- `Dock.streamHeartbeatTimeout = 15s` detects a dead stream.

Conclusion: the phone does not need polling for normal Dock/Archive/Detail
updates. If the phone is late, it is usually because the relay learned the Codex
fact late or did not emit a projection update.

Source references:

- `CodexDock/State/AppServerThreadCardStreamClient.swift:3`
- `CodexDock/State/AppServerThreadCardStreamClient.swift:113`
- `CodexDock/State/AppServerThreadCardStreamClient.swift:148`
- `CodexDock/State/AppServerThreadCardStreamClient.swift:194`
- `CodexDock/State/AppServerThreadCardStreamClient.swift:266`
- `CodexDock/Projection/StreamReconciler.swift:61`
- `CodexDock/Projection/StreamReconciler.swift:192`
- `CodexDock/Projection/StreamReconciler.swift:248`
- `CodexDock/Configuration/CodexDockConstants.swift:12`
- `CodexDock/Configuration/CodexDockConstants.swift:22`
- `CodexDock/Configuration/CodexDockConstants.swift:23`

### 2. Dock Relay

The relay-to-phone stream is push-based today.

`StateSubscriptionHub.publishDelta()` sends card deltas to subscribers
immediately when the relay store changes. The 5s heartbeat is liveness only.
`subscribeDock()` and `subscribeArchive()` return a snapshot, buffer concurrent
updates, then stream later deltas.

The polling/timer-driven part is how the relay learns facts from Codex:

- App-server endpoint discovery refreshes every 5s.
- Live loaded-row discovery refreshes every 2.5s.
- Full Dock/archive reconciliation runs every 30s, with a 250ms debounce for
  triggered reconciles.
- Dock reconciliation calls `thread/list`, enriches with `thread/read`, reads
  `session_index.jsonl`, then calls `thread/turns/list` to prove activity and
  latest summary.
- Live status discovery calls `thread/loaded/list`, then `thread/read` for each
  loaded id.

The relay already has partial event hooks:

- Upstream JSON-RPC clients support `onNotification` and `onRequest`.
- The upstream pool can keep clients open and deliver notifications.
- Current notification ingestion handles `thread/name/updated` and
  `thread/status/changed`, then schedules reconciliation.
- Open Thread Detail already consumes upstream notifications and server
  requests into a projection ledger.

Conclusion: relay-to-phone does not fundamentally need polling. Relay-to-Codex
currently uses polling for discovery, live status, and full card proof. Some of
that can be replaced by event invalidation plus targeted reads.

Source references:

- `scripts/dock-relay-constants.mjs:36`
- `scripts/dock-relay-constants.mjs:42`
- `scripts/dock-relay-constants.mjs:46`
- `scripts/dock-relay-state-subscriptions.mjs:135`
- `scripts/dock-relay-state-subscriptions.mjs:154`
- `scripts/dock-relay-state-engine.mjs:156`
- `scripts/dock-relay-state-engine.mjs:344`
- `scripts/dock-relay-state-engine.mjs:432`
- `scripts/dock-relay-state-engine.mjs:497`
- `scripts/dock-relay-state-engine.mjs:600`
- `scripts/dock-relay-state-engine.mjs:861`
- `scripts/dock-relay-live-status-cache.mjs:76`
- `scripts/dock-relay-live-status-cache.mjs:95`
- `scripts/dock-relay-app-server-registry.mjs:188`
- `scripts/dock-relay-app-server-registry.mjs:254`
- `scripts/dock-relay-thread-data.mjs:598`
- `scripts/dock-relay-thread-data.mjs:658`
- `scripts/dock-relay-thread-data.mjs:785`
- `scripts/dock-relay-thread-data.mjs:923`
- `scripts/dock-relay-thread-data.mjs:1377`
- `scripts/dock-relay-thread-data.mjs:1436`
- `scripts/dock-relay.mjs:530`
- `scripts/dock-relay.mjs:663`
- `scripts/dock-relay.mjs:736`

### 3. Codex App-Server And Runtime

Codex has real event streams, but not one complete Dock-card feed.

Codex app-server broadcasts global server notifications to initialized clients,
unless a connection opted out of that method. Thread-scoped notifications are
sent to subscribed connections. Starting or resuming a thread attaches a listener
for that connection.

The listener loop reads `conversation.next_event()` and converts core events
into app-server notifications and server requests:

- `turn/started`
- `turn/completed`
- `item/started`
- `item/completed`
- agent message deltas
- reasoning/plan/command-output deltas
- approval requests
- tool/user-input requests
- realtime transcript/audio events

Codex also broadcasts lifecycle/status facts:

- `thread/started`
- `thread/status/changed`
- `thread/archived`
- `thread/unarchived`
- `thread/closed`
- `thread/name/updated`

But the history/list APIs are reads:

- `thread/list`
- `thread/read`
- `thread/loaded/list`
- `thread/turns/list`

The important detail: `Thread.turns` is empty for most list/notification
payloads. Turns are populated only on specific read/resume/fork/rollback paths
when requested. `thread/turns/list` still rebuilds from rollout history on each
request because rollback and compaction can change earlier turns until turn
metadata is indexed separately.

Conclusion: Codex supports realtime for loaded/subscribed thread events and
global lifecycle/status notifications. It does not currently provide a complete
"all Dock cards changed with latest summary/activity proof" subscription.

Source references:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/transport.rs:194`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_state.rs:294`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_state.rs:326`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_state.rs:434`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_lifecycle.rs:137`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_lifecycle.rs:291`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_lifecycle.rs:395`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:579`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1040`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1767`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1973`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:2020`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:2204`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:2315`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:221`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/bespoke_event_handling.rs:136`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs:105`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:962`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1111`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1135`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1157`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1188`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1307`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/turn.rs:357`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:1066`

## Classification

### Already Push-Based

These are already structurally realtime enough and do not need polling as the
normal data path:

- Dock card projection from relay to phone.
- Archive card projection from relay to phone.
- Open Thread Detail projection from relay to phone.
- Open attachable thread events from Codex to relay after `thread/resume`.
- Server requests for approvals, permissions, elicitation, and user input on an
  open/resumed thread.
- Realtime transcription/audio event delivery for an open/resumed thread.

### Can Be Push Or Event-Invalidated

These do not fundamentally require periodic polling, but may require a targeted
read after an event:

- Rename: direct from `thread/name/updated`.
- Archive/unarchive: direct mutation plus `thread/archived` or
  `thread/unarchived`.
- Running/idle/needs approval/needs input badge: direct from
  `thread/status/changed` when the relevant app-server endpoint is observed.
- New thread appearance: direct from `thread/started`, possibly followed by
  `thread/read` to enrich card fields.
- Thread closed/unloaded: direct from `thread/closed`.
- Activity/order for an active thread: `turn/started`, `turn/completed`, and
  item notifications can mark one thread dirty; then relay can read only that
  thread's turns if it needs proven latest activity or summary.
- Hidden child rollup status: child status or private-owner-presence events can
  update the parent rollup without a full list scan, but private runtimes still
  need process/session observation.

### Still Needs Snapshot/Read Backstops

These should not be treated as pure push with the current Codex protocol:

- Initial Dock list.
- Initial Archive list.
- Full historical card correctness for threads that are not loaded.
- "Latest message" for arbitrary non-open threads.
- Activity proof for arbitrary non-open threads.
- Recovery after missed events, reconnects, app restart, relay restart, sequence
  gaps, epoch changes, or schema changes.
- Discovery of attachable app-server endpoints.
- Discovery of private stdio runtimes.
- `session_index.jsonl` supplemental rows, unless replaced with a watcher or a
  Codex app-server API.

## Disk And Local-State Pull Audit

### Bottom Line

Most visible card truth should be app-server-first, but live evidence disproves
the stronger claim that every rollout `session_meta` field is already populated
on app-server `Thread` rows.

For real data on `Amir-M5`, app-server `Thread` rows already cover the normal
card fields: id, session id, title/name, created/updated time, status, path,
cwd, source, and Git info. They also expose enough structured `source` data for
the relay's current human/subagent classifier to make the same decision as the
rollout-enriched row in the sampled data.

The app-server still has two real gaps for a fully pure architecture:

- `thread/list` does not return every real row that `thread/read` can read.
- Current app-server APIs do not expose endpoint discovery or unrelated private
  stdio runtime ownership.

The hard boundary is discovery and private runtime ownership. The relay cannot
ask an app-server where the app-server is before it has found that app-server,
and current private stdio Codex runtimes do not expose an attachable app-server
stream. Those need either local process discovery as a fallback or a new Codex
daemon/registry API.

### Live Evidence From 2026-06-05

Evidence was gathered against the real local Codex home and running relay, not
fixtures.

Commands and artifacts:

- `rtk make app-server-status && rtk make dock-relay-status`
- `curl -sS http://127.0.0.1:4510/statusz`
- Live app-server/disk/process probe written to
  `/tmp/codex-client/app-server-disk-audit-OSv2Mw/evidence.json`
- Follow-up live probes for rollout/app-server classification equivalence,
  session-index missing rows, and unsupported `thread/search`.

Observed registry state:

- Relay was ready on `127.0.0.1:4510`.
- History app-server route was `source=daemon`, `endpointType=history`,
  `transport=unix`, with no failure.
- Registry saw 12 attachable live endpoints and 28 private owners.
- Process discovery found 23 attachable app-server endpoints and 28 private
  thread owners.
- Private owner sources were 25 `codex-cli-session-file` and 3
  `codex-cli-resume`.
- `thread/loaded/list` on the history route did not include the private owner
  ids.
- Live endpoint `thread/loaded/list`/`thread/read` collection returned 0 loaded
  rows at that moment.

Observed app-server list coverage:

- `thread/list` default active scope: 295 rows, complete across 3 pages.
- `thread/list` default archived scope: 74 rows, complete across 1 page.
- `thread/list` all known source kinds, active: 1,854 rows, complete across
  19 pages.
- `thread/list` all known source kinds, archived: 787 rows, complete across
  8 pages.
- `thread/list` rows had `turns.length === 0`, as expected.
- `thread/read(includeTurns: false)` succeeded for 25/25 sampled rows and also
  returned no turns.
- `thread/turns/list(limit: 1)` succeeded for 25/25 sampled rows and returned at
  least one turn for all 25.
- `thread/read(includeTurns: true)` succeeded for the sampled row and returned
  74 turns.

Observed rollout `session_meta` comparison:

- 100 app-server rows with rollout paths were sampled.
- All 100 had a readable rollout `session_meta`.
- All 100 rollout rows had `thread_source` where app-server `threadSource` was
  null.
- 68 rollout rows had `forked_from_id` where app-server `forkedFromId` was null.
- In a larger 500-row follow-up sample, 394 rows had rollout `forked_from_id`
  missing from app-server `forkedFromId`.
- 393 of those 394 were still covered by
  `source.subAgent.thread_spawn.parent_thread_id`.
- One sampled fork relationship was not covered by that source parent path.
- Classification result was identical for 500/500 sampled rows when comparing
  app-server-only rows to rollout-enriched rows.

Observed `session_index.jsonl` comparison:

- `/Users/aelaguiz/.codex/session_index.jsonl` existed, had 229 lines, 221
  unique ids, and 0 malformed lines.
- 15 `session_index.jsonl` ids were missing from app-server `thread/list` even
  when querying all known source kinds and both active/archive scopes.
- 14 of those 15 missing ids had no matching rollout file under
  `$CODEX_HOME/sessions` and `thread/read` failed with `thread not loaded`.
- 1 of those 15 had a rollout file and `thread/read` succeeded, but
  `thread/list` still did not return it after pagination.
- Runtime `thread/search` is not currently available. Calling it returned
  `unknown variant thread/search`, even though protocol source contains a
  `ThreadSearchParams` type.

### Production Pulls From Codex Disk Or Local Machine State

| Current pull | What the relay gets | Current use | Can current app-server provide it? | Correct target |
| --- | --- | --- | --- | --- |
| `$CODEX_HOME/sessions/**/*.jsonl`, first `session_meta` event | `id`, `source`, `thread_source`, `forked_from_id`, `cwd`, Git branch/origin/commit | Human-thread filtering, hidden-child rollup classification, loaded-row enrichment, private-row enrichment | Partly. App-server covers normal card fields and classification was identical in the live 500-row sample. But live rows did not populate `threadSource`, often did not populate `forkedFromId`, and one sampled fork relationship was not recoverable from `source.subAgent.thread_spawn.parent_thread_id`. | Use app-server `Thread` as primary. Parse structured `source` for subagent parent relationships. Keep rollout fallback only for exact fork/thread-source gaps until Codex app-server populates those fields or exposes an equivalent relationship field reliably. |
| `$CODEX_HOME/session_index.jsonl` | thread id, name/title, updated timestamp | Supplements human-started rows that are missing from `thread/list` | Not fully today. `thread/list` returns far more rows overall, but live evidence found one real indexed/readable row missing from `thread/list`; `thread/search` is not available in the running app-server. | Do not use `session_index.jsonl` as primary truth. Treat it as a temporary backstop/diagnostic. The clean fix is a Codex app-server list/index repair or an explicit app-server recent/index API. |
| `thread.path` containing `archived_sessions` | archived vs non-archived classification | Archive/non-archive scoping for supplemental rows | Yes. `thread/list` already accepts `archived`; `Thread.path` is also returned by app-server today. | Prefer app-server archive filtering instead of relay path inference. Keep path inference only for validating legacy supplement rows. |
| `ps -axo pid=,ppid=,command=` | running Codex process list, command-line args, `--listen`, `--ws-token-file`, `codex resume <thread-id>` | Discover app-server endpoints and private stdio thread owners | No. This is bootstrap discovery before a connection exists. | Keep as fallback unless Codex provides a daemon registry/control socket that lists endpoints and private runtimes. |
| `lsof -w -Fpn -p <pids>` over Codex runtime processes | open rollout file paths mapped to active thread ids | Infer private stdio ownership when command-line args do not identify the active thread | No. Current app-server cannot report private runtimes owned by unrelated Codex clients. | Replace only with a new Codex runtime registration/heartbeat API. Until then, this is the best low-overhead private-owner detector. |
| App-server `--ws-token-file` | bearer token for a discovered websocket app-server | Authenticate to discovered live app-server endpoint | No. This is auth bootstrap material, not thread data. | Prefer a central Codex daemon socket or relay-owned launch path that avoids token-file scraping. Do not try to get this from app-server after connection. |
| Unix socket path existence check | whether a daemon/history socket path exists before routing | Mark history endpoint available/unavailable | Not meaningfully. The relay can only connect or fail. | Replace with a connection attempt if desired. This is not a Codex truth source. |

### Relay-Owned Disk Or Config Reads

These are disk reads, but they are not Codex thread truth and should not be
replaced by app-server thread APIs.

| Current pull | What it is | Can app-server provide it? | Correct target |
| --- | --- | --- | --- |
| `.codex-dock/relay-state.sqlite` | Relay projection/cache database | No. It is relay-owned state. | Keep if restart continuity and diagnostics matter; make memory-only only if we accept losing restart continuity. |
| `.codex-dock/source-host-id` | Relay host identity | No. It is Dock relay identity, not Codex thread data. | Keep Mac-side. Do not persist this phone-side as `relayInstanceID`. |
| `.env` and generated service env files | Local config and secrets input | No. App-server should not send relay config or secrets to the phone. | Keep Mac-side; never overwrite `.env`. |
| Controlled fixture/proof files | Test harness data | No. Not production data path. | Keep in tests only; never cite as live proof. |

### Field-By-Field App-Server Availability

| Field currently recovered from disk/local state | Current disk/local source | App-server source today | Pure app-server today? |
| --- | --- | --- | --- |
| Thread id | rollout `session_meta.id`, `session_index.id`, open rollout filename | `Thread.id`, `thread/loaded/list` ids | Yes for persisted/loaded app-server-readable rows. No for private runtime detection without process/lsof or new registry API. |
| Session id | app-server row, not rollout supplement | `Thread.sessionId` | Yes. |
| Name/title | `session_index.thread_name` / `name` | `Thread.name` from `thread/list` and `thread/read`; runtime `thread/search` is not available today | Yes if app-server indexing covers the row. |
| Updated time | `session_index.updated_at` | `Thread.updatedAt`; turn proof through `thread/turns/list` | Yes for app-server-readable rows. |
| Created time | app-server row | `Thread.createdAt` | Yes. |
| Status | app-server row plus private owner inference | `Thread.status`, `thread/status/changed`, `thread/loaded/list` | Yes for attachable app-server rows. No for unrelated private stdio owners without local process discovery or new runtime registry. |
| Source | rollout `session_meta.source` | `Thread.source` | Yes. |
| Thread source | rollout `session_meta.thread_source` | `Thread.threadSource` in schema, but null in live sampled rows | No, not reliably today. Classification can usually derive the needed signal from `Thread.source`; exact field replacement needs Codex app-server population or a fallback. |
| Fork source | rollout `session_meta.forked_from_id` | `Thread.forkedFromId` in schema, plus parent data inside subagent `Thread.source` | Not reliably as `forkedFromId` today. Most sampled subagent parent links were recoverable from `Thread.source`, but exact fork coverage still needs Codex app-server repair or a fallback. |
| Parent thread id | app-server row or nested source payload | `Thread.parentThreadId` in schema; `source.subAgent.thread_spawn.parent_thread_id` in live data | Partly. The nested source payload covered 393/394 sampled rollout fork ids where `forkedFromId` was null. |
| Working directory | rollout `session_meta.cwd` | `Thread.cwd` | Yes. |
| Git branch/origin/commit | rollout `session_meta.git` | `Thread.gitInfo` | Yes. |
| Archive state | path segment `archived_sessions` | `thread/list({ archived })`; app-server `Thread.path` if still needed | Yes. Prefer the archive filter over path inference. |
| Latest message / latest summary | app-server turns read, not direct relay disk read | `thread/turns/list`, or future card-summary event/index | Yes as a targeted read today; not as a complete push feed today. |
| Active private owner | `codex resume` args and open rollout files from `lsof` | None for unrelated private stdio runtime | No. Needs process/lsof fallback or new Codex daemon registration. |
| App-server endpoint URL | process args, daemon socket convention | None before connection | No. Needs discovery fallback or new fixed registry endpoint. |
| App-server bearer token | token file path from process args | None before auth | No. Needs different auth/bootstrap architecture. |

### Replacement Plan By Source

1. Rollout `session_meta` metadata

   Replace this first. For every row obtained from `thread/list`,
   `thread/read`, or `thread/loaded/list` followed by `thread/read`, trust
   app-server `Thread` fields for normal card facts.

   Do not blindly remove every rollout metadata fallback yet. Live data shows
   app-server `threadSource` and `forkedFromId` are not reliably populated.
   The elegant near-term replacement is:

   - derive subagent parent/rollup from structured `Thread.source`,
   - use app-server `cwd`, `source`, `gitInfo`, timestamps, status, path, and
     name directly,
   - keep a narrow diagnostic/fallback path only for exact relationship fields
     that app-server does not yet expose reliably.

2. `session_index.jsonl` supplements

   Replace this only after Codex app-server can list every real row that
   `thread/read` can read. Live evidence found one real readable indexed row
   missing from `thread/list`, and `thread/search` is not available in the
   running app-server.

   Most missing `session_index.jsonl` entries were stale and should not drive
   Dock truth. The one readable-but-unlisted row is the real app-server gap.
   The clean fix is in Codex app-server list/index behavior, not more relay
   scraping.

3. Archive path inference

   Use `thread/list({ archived: false })` for Dock and
   `thread/list({ archived: true })` for Archive. Stop classifying normal rows
   by `thread.path`. Path-based archive checks can remain only for temporary
   supplement validation.

4. Process and `lsof` discovery

   Do not pretend this can be replaced by current app-server calls. It cannot.
   Current app-server APIs help after the relay has a route. Process/lsof is how
   the relay finds some routes and detects private unattachable owners.

   Live evidence on `Amir-M5` had 28 private owners from process/lsof discovery,
   and none of those ids appeared in history `thread/loaded/list` or the live
   app-server loaded-row collection at the time of the probe.

   The clean replacement is a Codex daemon registry that exposes:

   - known app-server endpoints,
   - auth/connect metadata that does not require token-file scraping,
   - loaded thread ids per endpoint,
   - private stdio runtime owners,
   - lifecycle/status events for those owners.

5. Relay cache/config files

   Leave them out of the app-server migration. They are not Codex data.

### Net Architecture Finding

The relay should not be a second Codex history indexer. It should be an
app-server projection bridge.

That means:

- normal card facts come from app-server `Thread` data and app-server events,
- latest activity/summary comes from targeted app-server reads after events,
- startup/recovery uses app-server list/read snapshots,
- rollout/session-index disk reads become narrow temporary diagnostics or
  fallback for proven app-server gaps,
- private runtime and endpoint discovery stay local-machine discovery until
  Codex exposes a daemon registry that can report them.

Source references:

- `scripts/dock-relay-thread-data.mjs:334`
- `scripts/dock-relay-thread-data.mjs:354`
- `scripts/dock-relay-thread-data.mjs:402`
- `scripts/dock-relay-thread-data.mjs:479`
- `scripts/dock-relay-thread-data.mjs:531`
- `scripts/dock-relay-thread-data.mjs:658`
- `scripts/dock-relay-thread-data.mjs:1040`
- `scripts/dock-relay-thread-data.mjs:1114`
- `scripts/dock-relay-app-server-discovery.mjs:48`
- `scripts/dock-relay-app-server-discovery.mjs:252`
- `scripts/dock-relay-app-server-discovery.mjs:305`
- `scripts/dock-relay-app-server-discovery.mjs:373`
- `scripts/dock-relay-app-server-discovery.mjs:400`
- `scripts/dock-relay-app-server-discovery.mjs:439`
- `scripts/dock-relay-app-server-discovery.mjs:461`
- `scripts/dock-relay-app-server-registry.mjs:614`
- `scripts/dock-relay-app-server-registry.mjs:704`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs:105`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:962`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1767`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:3969`

## Clean Target Architecture

### 1. Keep The Relay Projection Store As The Single Truth

Do not create a second Dock truth path. The relay store remains the only thing
that emits `dock/update` and `archive/update`.

Events should update or invalidate that store. The phone should not receive raw
Codex thread events as Dock card truth.

### 2. Add A Codex Event Bridge In The Relay

The relay should maintain long-lived initialized upstream connections for the
Codex app-server endpoints it can attach to:

- One history/daemon connection where available.
- One listener connection per attachable live endpoint when needed.
- Existing active Thread Detail connections remain per open detail session.

The bridge should ingest these notification classes:

- `thread/started`
- `thread/status/changed`
- `thread/name/updated`
- `thread/archived`
- `thread/unarchived`
- `thread/closed`
- `turn/started`
- `turn/completed`
- `item/started`
- `item/completed`
- server requests that imply attention state

This does not mean subscribing the phone to all detail streams. It means the
relay listens for enough Codex events to know which one thread changed.

### 3. Split Events Into Direct Patches And Dirty Marks

Some events are complete enough to patch a card directly:

- Rename.
- Status/badge state.
- Archive/unarchive/delete visibility.
- Closed/unloaded status.

Other events should mark one thread dirty:

- Turn started.
- Turn completed.
- Item completed.
- Agent message delta/completed.
- Command output/approval events.

For dirty marks, debounce per thread and do one targeted read:

- `thread/read(includeTurns: false)` for metadata/status enrichment.
- `thread/turns/list` for latest summary/activity proof only when the card needs
  it.

That changes the latency model from "wait for the next 2.5s/30s poll" to
"event arrives, read one thread, push one card delta."

### 4. Keep Snapshots For Recovery

Snapshots are still necessary and should remain:

- On relay boot.
- On phone subscribe/resync.
- On sequence gaps.
- On heartbeat timeout/reconnect.
- On stale event bridge state.
- On suspected missed event.
- On low-frequency safety intervals.

The difference is that snapshots become a backstop, not the main latency path.

### 5. Do Not Subscribe To Every Thread Detail

Subscribing every visible thread through `thread/resume` would be heavier than
necessary and semantically wrong for cold history. It could also keep more
threads loaded than intended.

Only open Thread Detail needs the full per-thread event ledger. Dock cards need
small lifecycle/status facts plus occasional targeted reads.

### 6. Private Runtime Boundary

Private stdio runtimes remain the hard boundary. They are private to their
parent process by design. The relay can currently observe them through process
metadata and session files, but it cannot receive their per-thread event stream.

For private runtimes, the clean options are:

- Keep presence/status inference through process/session observation.
- Add a Codex-side bridge or daemon registration API later.
- Show status-only/partial-proof card state when live detail is impossible.

## Practical Impact

The low-overhead improvement path is:

1. Keep current phone protocol unchanged.
2. Keep full reconcile for boot/recovery.
3. Expand relay upstream notification ingestion from only
   `thread/name/updated` and `thread/status/changed` to the broader lifecycle
   and turn/item event set.
4. Apply direct card patches when the event has enough data.
5. Otherwise do a targeted one-thread read and emit one `dock/update`.
6. Leave private stdio runtimes as status-only unless Codex exposes an
   attachable bridge.

Net: most visible latency can be made event-driven without turning the Dock into
a full all-thread detail subscriber and without increasing steady-state load by
much. The only unavoidable reads are initial/history/recovery reads and targeted
reads for fields Codex events do not currently carry.
