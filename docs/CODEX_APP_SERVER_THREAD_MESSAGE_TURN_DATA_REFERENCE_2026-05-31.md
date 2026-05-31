# Codex App-Server Thread, Turn, Message, And Dock Data Reference

Date: 2026-05-31

Status: authoritative working reference for the current Codex checkout at
`/Users/aelaguiz/workspace/codex` and the current Codex Dock client checkout at
`/Users/aelaguiz/workspace/codex-client`.

Companion UX reference:
[Codex Dock Conversation, Time, And Order UX Reference](./CODEX_DOCK_TIME_ORDER_UX_REFERENCE_2026-05-31.md)

Codex source audited: `/Users/aelaguiz/workspace/codex` at `090144e0ec`

Dock client source audited: `/Users/aelaguiz/workspace/codex-client` at
`7365a68`

Scope: Codex-generated identifiers, timestamps, thread fields, turn fields,
message/item fields, live notifications, server request cards, persisted rollout
history, app-server read/list APIs, and the Dock relay/client projection that
Codex Dock actually consumes.

This document is intentionally field-level. It is meant to answer questions like
"is there a Codex message number?", "are turn IDs UUIDs?", "where do timestamps
come from?", and "which fields are Codex-origin versus Dock-derived?"

## Net Answers

There is no Codex-origin message number attached to every message in a thread.
Codex app-server gives ordered arrays, cursors, string IDs, and timestamps at
thread/turn/lifecycle layers. Dock then derives local display order fields such
as `turnSequence`, `itemSequence`, and `eventSequence`.

Normal app-server turn IDs are UUIDv7 strings. They come from the core
`Submission.id` generated with `Uuid::now_v7()`. The API still types turn IDs as
opaque strings, and some internal or reconstructed turns can be non-UUID strings
such as `auto-compact-0`, `rollout-3`, or synthetic `item-1` item IDs. Clients
must not require all turn or item IDs to parse as UUIDs.

Threads have timestamps. Turns have timestamps. Historical message/item objects
do not have their own per-message timestamp fields. Live item lifecycle
notifications do have millisecond timestamps, and rollout JSONL wrapper lines
have RFC3339 millisecond timestamps, but app-server history reconstruction
drops the wrapper timestamp before producing `ThreadItem` history.

The one monotonic integer sequence in this area is not a message number:
app-server server-to-client request IDs use an atomic integer counter for
request cards, and Dock relay card stream changes have SQLite `seq` values. Both
are transport/projection sequences, not Codex thread message ordinals.

## Source Roots And High-Value Files

Codex source root:

- `/Users/aelaguiz/workspace/codex`

Codex Dock source root:

- `/Users/aelaguiz/workspace/codex-client`

Most important Codex files:

- `codex-rs/protocol/src/thread_id.rs`
- `codex-rs/protocol/src/session_id.rs`
- `codex-rs/protocol/src/protocol.rs`
- `codex-rs/protocol/src/items.rs`
- `codex-rs/protocol/src/models.rs`
- `codex-rs/core/src/session/mod.rs`
- `codex-rs/core/src/session/turn_context.rs`
- `codex-rs/core/src/tasks/regular.rs`
- `codex-rs/core/src/tasks/mod.rs`
- `codex-rs/core/src/turn_timing.rs`
- `codex-rs/core/src/event_mapping.rs`
- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/turn.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/item.rs`
- `codex-rs/app-server-protocol/src/protocol/v2/notification.rs`
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs`
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
- `codex-rs/app-server/src/request_processors/turn_processor.rs`
- `codex-rs/app-server/src/outgoing_message.rs`
- `codex-rs/thread-store/src/types.rs`
- `codex-rs/thread-store/src/thread_metadata_sync.rs`
- `codex-rs/rollout/src/recorder.rs`

Most important Dock files:

- `CodexDock/AppServer/ThreadListDTO.swift`
- `CodexDock/AppServer/ThreadDetailDTO.swift`
- `CodexDock/AppServer/DockThreadCardDTO.swift`
- `CodexDock/Models/ThreadEvent.swift`
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/State/ThreadCardRowProjector.swift`
- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-store.mjs`
- `scripts/dock-relay-state-views.mjs`

Source-of-truth rule:

- App-server protocol Rust types are the primary wire contract.
- Generated TypeScript under
  `codex-rs/app-server-protocol/schema/typescript` is useful for client checks,
  but Rust wins when they disagree.
- Experimental APIs such as `thread/turns/list` and
  `thread/turns/items/list` can be omitted from stable generated schemas unless
  schema generation includes experimental methods.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/export.rs:122`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:1849`

## Wire Naming Rules

Most app-server v2 payload structs use camelCase on the wire through serde
attributes. Examples:

- Rust `thread_id` becomes wire `threadId`.
- Rust `created_at` becomes wire `createdAt`.
- Rust `duration_ms` becomes wire `durationMs`.
- Rust `active_flags` becomes wire `activeFlags`.

Important exceptions and special cases:

- `ThreadSortKey` serializes as `created_at` or `updated_at`.
- `SortDirection` serializes as `asc` or `desc`.
- `ThreadSource` serializes as `user`, `subagent`, or
  `memory_consolidation`.
- `UserInput.text` serializes its text spans as `text_elements`, not
  `textElements`; the Swift outbound DTO maps `textElements` to
  `text_elements`.
- Tagged unions use a `type` field. For example, `ThreadItem::AgentMessage`
  arrives as `{"type":"agentMessage","id":"...","text":"..."}`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs:102`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1029`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1037`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:208`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/turn.rs:263`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/schema/json/v2/TurnStartParams.json:360`
- `/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/TurnDTO.swift:17`

## ID Taxonomy

### Thread IDs

`ThreadId` is a UUID wrapper. `ThreadId::new()` calls `Uuid::now_v7()`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/thread_id.rs:17`
- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/thread_id.rs:20`

Wire shape:

- `Thread.id` is a string.
- `ThreadReadParams.threadId`, `ThreadTurnsListParams.threadId`, and
  `ThreadTurnsItemsListParams.threadId` are strings.
- App-server parses thread IDs back through `ThreadId::from_string`, so a real
  Codex thread ID must parse as a UUID.

Evidence:

- `thread_data.rs:105`
- `thread.rs:1132`
- `thread.rs:1163`
- `thread.rs:1197`
- `thread_processor.rs:2058`
- `thread_id.rs:24`

Meaning:

- A current Codex-created thread ID is a UUIDv7 string.
- UUIDv7 is time-ordered by construction, but Codex clients should still treat
  it as an opaque ID. Use `createdAt` / `updatedAt` and server cursor order for
  chronology, not UUID sorting.

### Session IDs

Codex has a separate `SessionId` wrapper. `SessionId::new()` also uses
`Uuid::now_v7()`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/session_id.rs:19`
- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/session_id.rs:22`

The app-server v2 `Thread.sessionId` field is a string. In the current stored
thread mapping, app-server sets `sessionId` equal to the thread ID for stored
threads.

Evidence:

- `thread_data.rs:107`
- `thread_processor.rs:3932`
- `thread_processor.rs:3935`

For loaded live snapshots, app-server uses the loaded thread's configured
session ID. Core root sessions use `SessionId::from(thread_id)`, while
non-root agent sessions can inherit the parent agent-control session ID.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:4164`
- `thread_processor.rs:4171`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/session.rs:956`
- `session.rs:960`

Dock relay card mapping renames this to `backendSessionID`, falling back to
`threadID` when `sessionId` is absent.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:317`
- `dock-relay-state-views.mjs:329`

Meaning:

- Do not assume `sessionId` is a separate stable tree ID in Dock today. Stored
  app-server rows currently expose it as the same UUID string as `thread.id`.

### Submission IDs And Normal Turn IDs

Core `Submission.id` is documented as the unique ID used to correlate submitted
user requests with events.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/protocol.rs:125`
- `protocol.rs:128`

`Session::submit_with_trace()` generates `Submission.id` with
`Uuid::now_v7().to_string()`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/mod.rs:689`
- `session/mod.rs:694`

Core `Event.id` is the correlated `Submission.id`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/protocol.rs:1142`
- `protocol.rs:1145`

`turn/start` submits an `Op::UserInput` and returns the submission ID as
`turn_id`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/turn_processor.rs:442`
- `turn_processor.rs:451`

Regular turns emit `TurnStartedEvent.turn_id = ctx.sub_id`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/tasks/regular.rs:46`
- `regular.rs:49`

Turn completion emits `TurnCompleteEvent.turn_id = turn_context.sub_id`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/tasks/mod.rs:777`
- `tasks/mod.rs:778`

Meaning:

- For normal app-server turns started through `turn/start`, the turn ID is a
  UUIDv7 string.
- It is the core submission ID, reused as the turn correlation ID.

### Non-UUID Turn IDs

The type is still `String`. Non-UUID turn IDs exist.

`submit_with_id()` accepts caller-provided submission IDs, and those IDs can
flow into turns.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/mod.rs:704`

Internal auto-compaction and realtime text input use
`next_internal_sub_id()`, which returns `auto-compact-{id}`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/mod.rs:1082`
- `session/mod.rs:1086`
- `session/mod.rs:1089`

`new_default_turn()` uses that internal sub ID.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/turn_context.rs:749`
- `turn_context.rs:754`

MCP tool-runner turns can use the original MCP request ID as the submission
ID so emitted events can be correlated with the originating `tools/call`
request.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/mcp-server/src/codex_tool_runner.rs:95`
- `codex_tool_runner.rs:98`

Synthetic turns started for queued pending work use a fresh UUIDv4 sub ID.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/tasks/mod.rs:458`
- `tasks/mod.rs:461`

Historical reconstruction can synthesize turn IDs when no explicit turn ID is
available. The first implicit rollout turn gets a new UUIDv7; later implicit
turns get strings like `rollout-3`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/thread_history.rs:1003`
- `thread_history.rs:1006`
- `thread_history.rs:1008`

Meaning:

- Treat `turn.id` as an opaque string.
- It is usually UUIDv7 for normal app-server turns, but client code should not
  call UUID parsing on every turn ID.

### Thread Item And Message IDs

App-server v2 `ThreadItem` variants all carry an `id: String`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:212`
- `item.rs:215`
- `item.rs:224`
- `item.rs:236`
- `item.rs:248`
- `item.rs:273`
- `item.rs:280`
- `item.rs:298`
- `item.rs:312`
- `item.rs:335`
- `item.rs:342`
- `item.rs:345`
- `item.rs:356`
- `item.rs:359`
- `item.rs:362`

The ID source depends on the item type and whether the item is live/core-origin
or reconstructed history:

- Core `UserMessageItem::new()` uses UUIDv4.
- Core `AgentMessageItem::new()` uses UUIDv4.
- Core `ContextCompactionItem::new()` uses UUIDv4.
- Hook prompt items preserve an incoming ID if provided, otherwise UUIDv4.
- Hook prompt response messages use UUIDv4.
- Assistant message conversion from provider output uses the provider item ID
  when present, otherwise UUIDv4.
- Tool-ish items usually use model/tool call IDs such as `call_id`.
- Reconstructed legacy history can synthesize item IDs like `item-1`,
  `item-2`, etc.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/items.rs:236`
- `items.rs:239`
- `items.rs:433`
- `items.rs:436`
- `items.rs:218`
- `items.rs:221`
- `items.rs:349`
- `items.rs:354`
- `items.rs:383`
- `items.rs:384`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/event_mapping.rs:127`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/thread_history.rs:265`
- `thread_history.rs:279`
- `thread_history.rs:295`
- `thread_history.rs:316`
- `thread_history.rs:392`
- `thread_history.rs:410`
- `thread_history.rs:471`
- `thread_history.rs:516`
- `thread_history.rs:578`
- `thread_history.rs:586`
- `thread_history.rs:1062`

Meaning:

- Message/item IDs are not monotonic.
- Message/item IDs are not one ID format.
- Reconstructed `item-N` IDs are monotonic only inside that reconstruction pass.
  They are not a durable Codex message number.

### Raw Response Item Message IDs

The lower-level `ResponseItem::Message.id` is optional and skipped during
serialization.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/models.rs:752`
- `models.rs:755`
- `models.rs:756`
- `models.rs:758`

Meaning:

- Raw provider message IDs are not a reliable client-facing app-server ordering
  field.
- Do not treat `ResponseItem::Message.id` as the answer to "message number".

### Server Request IDs

App-server server-to-client request cards use `RequestId`. The
`OutgoingMessageSender` owns `next_server_request_id: AtomicI64`, initializes it
to `0`, and returns `RequestId::Integer(fetch_add(1))`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/outgoing_message.rs:95`
- `outgoing_message.rs:97`
- `outgoing_message.rs:215`
- `outgoing_message.rs:282`
- `outgoing_message.rs:283`

Meaning:

- This is monotonic per app-server sender instance.
- It is for server request cards such as command approval and tool input.
- It is not a thread message number and does not order historical messages.

### JSON-RPC Transport IDs

JSON-RPC IDs are transport correlation IDs. They are separate from thread,
turn, item, server-request-card, and Dock relay stream IDs.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/jsonrpc_lite.rs:17`
- `jsonrpc_lite.rs:58`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/outgoing_message.rs:282`

Meaning:

- Client requests can use client-supplied JSON-RPC string or integer IDs.
- Server-originated requests use the app-server `AtomicI64` counter described
  above.
- Notifications have no JSON-RPC ID.
- None of these are Codex message numbers.

### Dock Relay Stream Sequence IDs

Dock relay stores card stream changes in SQLite with `seq INTEGER PRIMARY KEY
AUTOINCREMENT`. `currentSeq()` returns the max `seq`.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:206`
- `dock-relay-state-store.mjs:207`
- `dock-relay-state-store.mjs:356`
- `dock-relay-state-store.mjs:357`

Dock stream update DTOs expose `seq`.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/DockThreadCardDTO.swift:437`
- `DockThreadCardDTO.swift:447`

Meaning:

- Dock has a monotonic stream sequence for card updates.
- It is relay-derived, not Codex-origin.
- It does not identify or order messages inside a Codex thread.

## Timestamp Taxonomy

### Rollout Filename And Session Metadata Timestamps

Rollout filenames include a local-time seconds timestamp in the form
`rollout-YYYY-MM-DDThh-mm-ss-<thread_id>.jsonl`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/recorder.rs:1332`
- `recorder.rs:1348`

`SessionMeta.timestamp` is a UTC timestamp string with milliseconds derived
from the rollout creation timestamp.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/recorder.rs:665`

Meaning:

- The filename gives a coarse local creation time.
- Session metadata gives a UTC creation timestamp with milliseconds.
- App-server v2 still exposes thread `createdAt` and `updatedAt` as Unix
  seconds.

### Thread Timestamps

App-server v2 `Thread.createdAt` and `Thread.updatedAt` are Unix timestamps in
seconds.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs:117`
- `thread_data.rs:120`

Stored thread metadata uses `DateTime<Utc>` for `created_at` and `updated_at`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/types.rs:375`
- `types.rs:378`

When app-server maps a `StoredThread` to v2 `Thread`, it calls
`timestamp()`, so the public app-server `Thread` loses sub-second precision.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:3944`
- `thread_processor.rs:3945`

When creating thread metadata, Codex sets both `created_at` and `updated_at` to
`Utc::now()`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/thread_metadata_sync.rs:52`
- `thread_metadata_sync.rs:53`
- `thread_metadata_sync.rs:68`
- `thread_metadata_sync.rs:69`

When observing rollout session metadata, Codex parses the session metadata
timestamp into `created_at`; when observing appended rollout items, it updates
`updated_at` to `Utc::now()`.

Evidence:

- `thread_metadata_sync.rs:180`
- `thread_metadata_sync.rs:184`
- `thread_metadata_sync.rs:204`
- `thread_metadata_sync.rs:205`

Meaning:

- App-server thread timestamps are second-resolution on the v2 wire.
- The store can carry more precise timestamps internally, but v2 `Thread` does
  not expose those milliseconds.

### Turn Timestamps

App-server v2 `Turn.startedAt` and `Turn.completedAt` are optional Unix
timestamps in seconds. `Turn.durationMs` is milliseconds.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs:163`
- `thread_data.rs:165`
- `thread_data.rs:166`
- `thread_data.rs:168`
- `thread_data.rs:169`
- `thread_data.rs:171`

Core `TurnStartedEvent.started_at` is optional Unix seconds.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/protocol.rs:1871`
- `protocol.rs:1877`
- `protocol.rs:1880`

Core `TurnCompleteEvent.completed_at` is optional Unix seconds, and
`duration_ms` is optional milliseconds.

Evidence:

- `protocol.rs:1853`
- `protocol.rs:1856`
- `protocol.rs:1859`
- `protocol.rs:1860`
- `protocol.rs:1863`

`TurnTimingState.mark_turn_started()` captures current Unix milliseconds and
stores seconds as `started_at_unix_secs`. `completed_at_and_duration_ms()`
returns current Unix seconds plus elapsed duration in milliseconds.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/turn_timing.rs:52`
- `turn_timing.rs:54`
- `turn_timing.rs:57`
- `turn_timing.rs:67`
- `turn_timing.rs:69`
- `turn_timing.rs:72`
- `turn_timing.rs:103`
- `turn_timing.rs:107`

Meaning:

- A historical turn can usually be dated by `startedAt` or `completedAt`.
- Turn timestamps are per-turn, not per-message.

### Item Lifecycle Timestamps

Live item lifecycle notifications have millisecond timestamps:

- `item/started.params.startedAtMs`
- `item/completed.params.completedAtMs`
- auto-approval review started/completed timestamps
- approval request `startedAtMs`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:1058`
- `item.rs:1061`
- `item.rs:1065`
- `item.rs:1067`
- `item.rs:1132`
- `item.rs:1135`
- `item.rs:1139`
- `item.rs:1141`
- `item.rs:1075`
- `item.rs:1079`
- `item.rs:1104`
- `item.rs:1108`
- `item.rs:1112`
- `item.rs:1258`
- `item.rs:1262`
- `item.rs:1334`
- `item.rs:1338`

Core emits item lifecycle timestamps with `now_unix_timestamp_ms()`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/mod.rs:1791`
- `session/mod.rs:1798`
- `session/mod.rs:1804`
- `session/mod.rs:1816`

Meaning:

- Live notifications can place an item more precisely than the historical
  `ThreadItem` object can.
- If the client misses live notifications and later reads persisted history, the
  per-item lifecycle milliseconds are not available on the reconstructed
  `ThreadItem`.

### Rollout JSONL Timestamps

The persisted rollout JSONL wrapper line has a `timestamp` string.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/protocol.rs:2869`
- `protocol.rs:2871`

The rollout writer formats that timestamp as UTC RFC3339-like text with
millisecond precision: `[year]-[month]-[day]T[hour]:[minute]:[second].[subsecond
digits:3]Z`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/recorder.rs:1638`
- `recorder.rs:1640`
- `recorder.rs:1643`
- `recorder.rs:1647`

The rollout loader parses each line into `RolloutLine` and then pushes only the
flattened `RolloutItem`; the wrapper `timestamp` is discarded before app-server
turn reconstruction.

Evidence:

- `recorder.rs:814`
- `recorder.rs:843`
- `recorder.rs:845`
- `recorder.rs:852`
- `recorder.rs:855`
- `recorder.rs:858`
- `recorder.rs:861`
- `recorder.rs:864`

Meaning:

- The raw disk file has per-line timestamps.
- Current app-server `thread/read` and `thread/turns/list` history do not expose
  those per-line timestamps as item timestamps.

### Message Timestamps

App-server v2 `ThreadItem::UserMessage` contains `id` and `content`.
`ThreadItem::AgentMessage` contains `id`, `text`, optional `phase`, and optional
`memoryCitation`. Neither carries a timestamp field.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:213`
- `item.rs:215`
- `item.rs:222`
- `item.rs:224`
- `item.rs:226`
- `item.rs:228`
- `item.rs:230`

Meaning:

- There is no timestamp on the persisted user message object itself.
- There is no timestamp on the persisted agent message object itself.
- For historical display, use the containing turn's timestamps.
- For live display, use lifecycle notification timestamps where present, or the
  local receive time as a UI fallback.

## Thread DTO: App-Server V2

The public app-server v2 `Thread` struct lives in `thread_data.rs`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs:102`
- `thread_data.rs:105`
- `thread_data.rs:147`

Fields:

- `id: String`
  - Codex thread ID, currently UUIDv7 for Codex-created threads.
- `sessionId: String`
  - Session ID shared by threads in the same session tree according to the
    comment, but current stored-thread mapping sets it equal to `thread.id`.
- `forkedFromId: String?`
  - Parent thread ID when this thread was forked.
- `preview: String`
  - Usually the first user message, if available.
- `ephemeral: Bool`
  - Whether the thread is ephemeral and should not be materialized on disk.
- `modelProvider: String`
  - Model provider such as `openai`.
- `createdAt: Int64`
  - Unix seconds.
- `updatedAt: Int64`
  - Unix seconds.
- `status: ThreadStatus`
  - Runtime/load status.
- `path: Path?`
  - Unstable path to the thread on disk.
- `cwd: AbsolutePathBuf`
  - Working directory captured for the thread.
- `cliVersion: String`
  - CLI version that created the thread.
- `source: SessionSource`
  - Runtime origin such as CLI, VSCode, exec, app-server/MCP, custom, sub-agent,
    or unknown.
- `threadSource: ThreadSource?`
  - Optional analytics source classification.
- `agentNickname: String?`
  - Optional nickname for AgentControl-spawned sub-agents.
- `agentRole: String?`
  - Optional role for AgentControl-spawned sub-agents.
- `gitInfo: GitInfo?`
  - Optional git `sha`, `branch`, and `originUrl`.
- `name: String?`
  - Optional user-facing thread title.
- `turns: [Turn]`
  - Populated only by specific APIs.

Important `turns` rule:

- `turns` is populated only on `thread/resume`, `thread/rollback`,
  `thread/fork`, and `thread/read` when `includeTurns` is true.
- Other responses and notifications returning a `Thread` use an empty list.

Evidence:

- `thread_data.rs:143`
- `thread_data.rs:146`

### SessionSource

App-server v2 `SessionSource` is serialized camelCase with variants:

- `cli`
- `vscode`
- `exec`
- `appServer`
- `custom(...)`
- `subAgent(...)`
- `unknown`

Evidence:

- `thread_data.rs:16`
- `thread_data.rs:20`
- `thread_data.rs:21`
- `thread_data.rs:22`
- `thread_data.rs:26`
- `thread_data.rs:27`
- `thread_data.rs:28`
- `thread_data.rs:29`
- `thread_data.rs:30`

Core `SessionSource::Mcp` maps to app-server `AppServer`.

Evidence:

- `thread_data.rs:34`
- `thread_data.rs:40`

### ThreadSource

App-server v2 `ThreadSource` is snake_case with variants:

- `user`
- `subagent`
- `memory_consolidation`

Evidence:

- `thread_data.rs:64`
- `thread_data.rs:67`
- `thread_data.rs:70`

### GitInfo

App-server v2 `GitInfo` has:

- `sha`
- `branch`
- `originUrl`

Evidence:

- `thread_data.rs:93`
- `thread_data.rs:96`
- `thread_data.rs:99`

### ThreadStatus

`ThreadStatus` is a tagged union with `type`:

- `notLoaded`
- `idle`
- `systemError`
- `active { activeFlags: [...] }`

Active flags:

- `waitingOnApproval`
- `waitingOnUserInput`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1106`
- `thread.rs:1110`
- `thread.rs:1111`
- `thread.rs:1112`
- `thread.rs:1113`
- `thread.rs:1116`
- `thread.rs:1121`
- `thread.rs:1125`
- `thread.rs:1126`

Meaning:

- `notLoaded` means no live in-memory session is currently attached.
- `idle` means loaded but not actively running.
- `active` means loaded/running or waiting on a user/action gate.
- `systemError` is a runtime error state.

## Thread Storage And Thread Metadata

The thread store's `StoredThread` is the store-owned metadata used by
list/read/resume responses.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/types.rs:356`
- `types.rs:358`

Fields in `StoredThread`:

- `thread_id`
- `rollout_path`
- `forked_from_id`
- `preview`
- `name`
- `model_provider`
- `model`
- `reasoning_effort`
- `created_at`
- `updated_at`
- `archived_at`
- `cwd`
- `cli_version`
- `source`
- `thread_source`
- `agent_nickname`
- `agent_role`
- `agent_path`
- `git_info`
- `approval_mode`
- `sandbox_policy`
- `token_usage`
- `first_user_message`
- `history`

Evidence:

- `types.rs:359`
- `types.rs:406`

`StoredThreadHistory` contains:

- `thread_id`
- `items: Vec<RolloutItem>` in replay order

Evidence:

- `types.rs:124`
- `types.rs:130`

Thread list params in the store include:

- `page_size`
- `cursor`
- `sort_key`
- `sort_direction`
- `allowed_sources`
- `model_providers`
- `cwd_filters`
- `archived`
- `search_term`
- `use_state_db_only`

Evidence:

- `types.rs:175`
- `types.rs:199`

Metadata sync behavior:

- Create initializes `created_at` and `updated_at` to `Utc::now()`.
- Create captures model provider, source, thread source, agent metadata, cwd,
  CLI version, git info, memory mode, and dynamic tools.
- Rollout observation can backfill `created_at`, source, thread source, agent
  metadata, model provider, CLI version, cwd, git info, memory mode, dynamic
  tools, latest model, effort, approval mode, sandbox policy, preview, title,
  first user message, token usage, and goal objective preview.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/thread_metadata_sync.rs:51`
- `thread_metadata_sync.rs:80`
- `thread_metadata_sync.rs:180`
- `thread_metadata_sync.rs:284`

## App-Server Thread APIs

### Method Map

Relevant methods in app-server protocol:

- `thread/list`
- `thread/search`
- `thread/loaded/list`
- `thread/read`
- `thread/turns/list`
- `thread/turns/items/list`
- `turn/start`
- `turn/steer`
- `turn/interrupt`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/common.rs:567`
- `common.rs:572`
- `common.rs:578`
- `common.rs:583`
- `common.rs:588`
- `common.rs:595`
- `common.rs:745`
- `common.rs:751`
- `common.rs:757`

### `thread/list`

Protocol params:

- `cursor`
- `limit`
- `sortKey`
- `sortDirection`
- `modelProviders`
- `sourceKinds`
- `archived`
- `cwd`
- `useStateDbOnly`
- `searchTerm`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:937`
- `thread.rs:974`

Protocol response:

- `data: [Thread]`
- `nextCursor`
- `backwardsCursor`

Evidence:

- `thread.rs:1045`
- `thread.rs:1049`
- `thread.rs:1052`
- `thread.rs:1057`

Server behavior:

- Default sort key is `created_at`.
- Default sort direction is descending.
- Default archive filter is non-archived (`archived: false`).
- Stored rows are mapped into v2 `Thread`.
- Live statuses are overlaid from the thread watch manager.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1796`
- `thread_processor.rs:1818`
- `thread_processor.rs:1822`
- `thread_processor.rs:1832`
- `thread_processor.rs:1846`
- `thread_processor.rs:1856`
- `thread_processor.rs:1864`

### `thread/read`

Protocol params:

- `threadId`
- `includeTurns`

Evidence:

- `thread.rs:1129`
- `thread.rs:1136`

Protocol response:

- `thread: Thread`

Evidence:

- `thread.rs:1139`
- `thread.rs:1143`

Server behavior:

- Parses `threadId` as `ThreadId`.
- Builds from persisted metadata plus optional live state.
- If `includeTurns` is true, loaded threads reconstruct turns from live
  ThreadStore history; unloaded threads read metadata and history from
  ThreadStore.
- Ephemeral threads reject `includeTurns`.
- Live status is overlaid and stale in-progress turns can be interrupted.

Evidence:

- `thread_processor.rs:2049`
- `thread_processor.rs:2058`
- `thread_processor.rs:2068`
- `thread_processor.rs:2075`
- `thread_processor.rs:2089`
- `thread_processor.rs:2134`
- `thread_processor.rs:2191`
- `thread_processor.rs:2222`
- `thread_processor.rs:2227`

### `thread/turns/list`

Protocol params:

- `threadId`
- `cursor`
- `limit`
- `sortDirection`
- `itemsView`

Evidence:

- `thread.rs:1160`
- `thread.rs:1176`

Protocol response:

- `data: [Turn]`
- `nextCursor`
- `backwardsCursor`

Evidence:

- `thread.rs:1179`
- `thread.rs:1191`

Server behavior:

- Defaults `itemsView` to `summary`.
- Replays the full rollout history on every request, because rollback and
  compaction can change earlier turns.
- If a loaded thread has an active turn not yet persisted, it merges the
  in-memory active turn snapshot before pagination.
- Summary mode keeps only the first user message and final agent message for
  each turn.
- Pagination defaults to limit 25 and clamps to max 100.
- Default sort direction is descending.
- Cursor JSON is shaped like `{ "turnId": "...", "includeAnchor": true/false }`.

Evidence:

- `thread_processor.rs:2233`
- `thread_processor.rs:2244`
- `thread_processor.rs:2253`
- `thread_processor.rs:2263`
- `thread_processor.rs:2273`
- `thread_processor.rs:2287`
- `thread_processor.rs:2299`
- `thread_processor.rs:2316`
- `thread_processor.rs:2320`
- `thread_processor.rs:3581`
- `thread_processor.rs:3582`
- `thread_processor.rs:3608`
- `thread_processor.rs:3615`
- `thread_processor.rs:3630`
- `thread_processor.rs:3657`
- `thread_processor.rs:3673`
- `thread_processor.rs:3677`

Important Dock implication:

- Codex Dock's Swift DTO for `ThreadTurnsListParams` currently sends only
  `threadId`, `cursor`, and `limit`, so Dock relies on app-server defaults:
  descending order and summary items.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/ThreadDetailDTO.swift:13`
- `ThreadDetailDTO.swift:22`

### `thread/turns/items/list`

Protocol params:

- `threadId`
- `turnId`
- `cursor`
- `limit`
- `sortDirection`

Protocol response:

- `data: [ThreadItem]`
- `nextCursor`
- `backwardsCursor`

Evidence:

- `thread.rs:1194`
- `thread.rs:1222`

Current server behavior:

- The method is declared but currently returns method-not-found:
  `thread/turns/items/list is not supported yet`.

Evidence:

- `thread_processor.rs:628`
- `thread_processor.rs:633`

## Turn DTO And Turn APIs

### Turn Fields

App-server v2 `Turn` fields:

- `id: String`
- `items: [ThreadItem]`
- `itemsView: TurnItemsView`
- `status: TurnStatus`
- `error: TurnError?`
- `startedAt: Int64?`
- `completedAt: Int64?`
- `durationMs: Int64?`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs:153`
- `thread_data.rs:171`

### TurnItemsView

Variants:

- `notLoaded`
- `summary`
- `full`

Evidence:

- `thread_data.rs:174`
- `thread_data.rs:184`

Meaning:

- `notLoaded`: `items` intentionally empty.
- `summary`: `items` contains display summary items only.
- `full`: `items` contains every reconstructed `ThreadItem` available from
  persisted app-server history.

### TurnError

Fields:

- `message`
- `codexErrorInfo`
- `additionalDetails`

Evidence:

- `thread_data.rs:187`
- `thread_data.rs:195`

### TurnStatus

Variants:

- `completed`
- `interrupted`
- `failed`
- `inProgress`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/turn.rs:25`
- `turn.rs:33`

### `turn/start`

Protocol params include:

- `threadId`
- `input`
- `responsesapiClientMetadata`
- `additionalContext`
- `environments`
- `cwd`
- `runtimeWorkspaceRoots`
- `approvalPolicy`
- `approvalsReviewer`
- `sandboxPolicy`
- `permissions`
- `model`
- `serviceTier`
- `effort`
- `summary`
- `personality`
- `outputSchema`
- `collaborationMode`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/turn.rs:66`
- `turn.rs:143`

Response:

- `turn: Turn`

Evidence:

- `turn.rs:146`
- `turn.rs:150`

Server behavior:

- Submits the mapped user input as `Op::UserInput`.
- Returns the generated submission ID as the turn ID.

Evidence:

- `turn_processor.rs:442`
- `turn_processor.rs:451`

### `turn/steer`

Protocol params:

- `threadId`
- `input`
- `responsesapiClientMetadata`
- `additionalContext`
- `expectedTurnId`

Response:

- `turnId`

Evidence:

- `turn.rs:153`
- `turn.rs:178`

Meaning:

- `turn/steer` is for adding input to an active turn and includes an active turn
  precondition.

### `turn/interrupt`

Protocol params:

- `threadId`
- `turnId`

Response:

- empty object

Evidence:

- `turn.rs:181`
- `turn.rs:192`

## User Input DTO

App-server v2 `UserInput` is a tagged union with `type`.

Variants:

- `text { text, text_elements }`
- `image { detail?, url }`
- `localImage { detail?, path }`
- `skill { name, path }`
- `mention { name, path }`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/turn.rs:263`
- `turn.rs:293`

`TextElement.byteRange` uses byte offsets in the parent text buffer.

Evidence:

- `turn.rs:221`
- `turn.rs:226`

Dock note:

- Swift outbound input has its own DTOs, but app-server v2 JSON uses the Codex
  v2 field names and tags.

## ThreadItem DTO

`ThreadItem` is a tagged union with `type`, serialized camelCase.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:208`
- `item.rs:212`

Variants and fields:

- `userMessage`
  - `id`
  - `content: [UserInput]`
- `hookPrompt`
  - `id`
  - `fragments`
- `agentMessage`
  - `id`
  - `text`
  - `phase?`
  - `memoryCitation?`
- `plan`
  - `id`
  - `text`
- `reasoning`
  - `id`
  - `summary`
  - `content`
- `commandExecution`
  - `id`
  - `command`
  - `cwd`
  - `processId?`
  - `source`
  - `status`
  - `commandActions`
  - `aggregatedOutput?`
  - `exitCode?`
  - `durationMs?`
- `fileChange`
  - `id`
  - `changes`
  - `status`
- `mcpToolCall`
  - `id`
  - `server`
  - `tool`
  - `status`
  - `arguments`
  - `mcpAppResourceUri?`
  - `pluginId?`
  - `result?`
  - `error?`
  - `durationMs?`
- `dynamicToolCall`
  - `id`
  - `namespace?`
  - `tool`
  - `arguments`
  - `status`
  - `contentItems?`
  - `success?`
  - `durationMs?`
- `collabAgentToolCall`
  - `id`
  - `tool`
  - `status`
  - `senderThreadId`
  - `receiverThreadIds`
  - `prompt?`
  - `model?`
  - `reasoningEffort?`
  - `agentsStates`
- `webSearch`
  - `id`
  - `query`
  - `action?`
- `imageView`
  - `id`
  - `path`
- `imageGeneration`
  - `id`
  - `status`
  - `revisedPrompt?`
  - `result`
  - `savedPath?`
- `enteredReviewMode`
  - `id`
  - `review`
- `exitedReviewMode`
  - `id`
  - `review`
- `contextCompaction`
  - `id`

Evidence:

- `item.rs:213`
- `item.rs:362`

The enum has a shared `id()` accessor covering every variant.

Evidence:

- `item.rs:373`
- `item.rs:391`

Supporting enum values:

- `CommandExecutionStatus`: `inProgress`, `completed`, `failed`, `declined`
- `CommandExecutionSource`: `agent`, `userShell`, `unifiedExecStartup`,
  `unifiedExecInteraction`
- `PatchChangeKind`: `add`, `delete`, `update`
- `PatchApplyStatus`: `inProgress`, `completed`, `failed`, `declined`
- `McpToolCallStatus`: `inProgress`, `completed`, `failed`
- `DynamicToolCallStatus`: `inProgress`, `completed`, `failed`
- `CollabAgentToolCallStatus`: `inProgress`, `completed`, `failed`
- `CollabAgentStatus`: `pendingInit`, `running`, `interrupted`, `completed`,
  `errored`, and related variants in the surrounding struct area
- `WebSearchAction`: `search`, `openPage`, `findInPage`, `other`

Evidence:

- `item.rs:737`
- `item.rs:755`
- `item.rs:872`
- `item.rs:880`
- `item.rs:898`
- `item.rs:907`
- `item.rs:929`
- `item.rs:947`
- `item.rs:975`
- `item.rs:991`
- `item.rs:993`
- `item.rs:1010`

Important plan note:

- `PlanDelta` streaming text is not authoritative. The completed `Plan` item is
  authoritative and may not equal concatenated deltas.

Evidence:

- `item.rs:232`
- `item.rs:235`
- `item.rs:1164`
- `item.rs:1168`

## Historical Turn Reconstruction

App-server reconstructs historical turns from persisted `RolloutItem` entries.
The builder uses `TurnContext.turn_id` when available so rebuilt history
preserves original turn IDs.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/thread_history.rs:74`
- `thread_history.rs:77`
- `thread_history.rs:78`

Important reconstruction behaviors:

- `handle_user_message` creates a reconstructed `userMessage` with a synthetic
  `item-N` ID.
- `handle_agent_message` creates a reconstructed `agentMessage` with a
  synthetic `item-N` ID.
- Reasoning text is aggregated into the last reasoning item when possible.
- `ItemStarted`/`ItemCompleted` only upsert completed `Plan` items; many other
  core `TurnItem` lifecycle events are ignored in this history path because
  legacy event handlers cover the persisted history.
- Web search, command execution, file changes, dynamic tools, MCP tools, image
  view/generation, collab-agent tools, review markers, and compaction markers
  are reconstructed from their event forms.
- Turn started/completed/aborted events update turn status and timing.
- Rollback truncates turns and resets the synthetic item counter.
- Empty implicit turns are dropped unless explicitly opened or carrying a
  compaction marker.
- `next_item_id()` returns `item-{n}`.

Evidence:

- `thread_history.rs:265`
- `thread_history.rs:281`
- `thread_history.rs:285`
- `thread_history.rs:301`
- `thread_history.rs:304`
- `thread_history.rs:342`
- `thread_history.rs:344`
- `thread_history.rs:390`
- `thread_history.rs:392`
- `thread_history.rs:407`
- `thread_history.rs:410`
- `thread_history.rs:423`
- `thread_history.rs:471`
- `thread_history.rs:513`
- `thread_history.rs:516`
- `thread_history.rs:575`
- `thread_history.rs:578`
- `thread_history.rs:605`
- `thread_history.rs:894`
- `thread_history.rs:968`
- `thread_history.rs:980`
- `thread_history.rs:992`
- `thread_history.rs:994`
- `thread_history.rs:999`
- `thread_history.rs:1062`
- `thread_history.rs:1065`

Implications:

- Reconstructed item IDs are display/replay IDs, not source-of-truth provider
  message numbers.
- Reconstructed history is lossy relative to live notifications.
- Some item details are available only while live or only if persisted by the
  limited rollout policy.

## Live Notifications

Server notifications are JSON-RPC-style objects tagged by `method` with
`params`.

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/common.rs:1228`
- `common.rs:1249`

Relevant notification methods include:

- `thread/started`
- `thread/status/changed`
- `thread/archived`
- `thread/unarchived`
- `thread/closed`
- `thread/name/updated`
- `thread/goal/updated`
- `thread/goal/cleared`
- `thread/settings/updated`
- `thread/tokenUsage/updated`
- `turn/started`
- `turn/completed`
- `turn/diff/updated`
- `turn/plan/updated`
- `item/started`
- `item/autoApprovalReview/started`
- `item/autoApprovalReview/completed`
- `item/completed`
- `rawResponseItem/completed`
- `item/agentMessage/delta`
- `item/plan/delta`
- `item/commandExecution/outputDelta`
- `item/commandExecution/terminalInteraction`
- `item/fileChange/patchUpdated`
- `serverRequest/resolved`
- `item/mcpToolCall/progress`
- `item/reasoning/summaryTextDelta`
- `item/reasoning/summaryPartAdded`
- `item/reasoning/textDelta`
- `thread/compacted` (deprecated in favor of context compaction item)
- model/warning/config notifications
- realtime notifications after the visible snippet in `common.rs`

Evidence:

- `common.rs:1469`
- `common.rs:1535`

Turn notification payloads:

- `TurnStartedNotification { threadId, turn }`
- `TurnCompletedNotification { threadId, turn }`
- `TurnDiffUpdatedNotification { threadId, turnId, diff }`
- `TurnPlanUpdatedNotification { threadId, turnId, explanation, plan }`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/turn.rs:350`
- `turn.rs:394`

Item notification payloads:

- `ItemStartedNotification { item, threadId, turnId, startedAtMs }`
- `ItemCompletedNotification { item, threadId, turnId, completedAtMs }`
- `AgentMessageDeltaNotification { threadId, turnId, itemId, delta }`
- `PlanDeltaNotification { threadId, turnId, itemId, delta }`
- `ReasoningSummaryTextDeltaNotification`
- `ReasoningSummaryPartAddedNotification`
- `ReasoningTextDeltaNotification`
- `TerminalInteractionNotification`
- `CommandExecutionOutputDeltaNotification`
- `FileChangePatchUpdatedNotification`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:1058`
- `item.rs:1253`

Error notification payload:

- `error`
- `willRetry`
- `threadId`
- `turnId`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/notification.rs:38`
- `notification.rs:48`

Server request resolved notification:

- `threadId`
- `requestId`

Evidence:

- `notification.rs:50`
- `notification.rs:56`

## Server Request Cards

Server-to-client requests are represented as a typed `ServerRequest` enum with:

- `method`
- request `id`
- `params`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/common.rs:1079`
- `common.rs:1097`
- `common.rs:1102`
- `common.rs:1104`

Request card methods include:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/tool/requestUserInput`
- `mcpServer/elicitation/request`
- `item/permissions/requestApproval`
- `item/tool/call`
- auth/attestation requests
- deprecated legacy patch approval below that block

Evidence:

- `common.rs:1321`
- `common.rs:1378`

Command execution approval params include:

- `threadId`
- `turnId`
- `itemId`
- `startedAtMs`
- `approvalId?`
- `reason?`
- `networkApprovalContext?`
- `command?`
- `cwd?`
- `commandActions?`
- `additionalPermissions?`
- `proposedExecpolicyAmendment?`
- `proposedNetworkPolicyAmendments?`
- `availableDecisions?`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs:1255`
- `item.rs:1313`

File change approval params include:

- `threadId`
- `turnId`
- `itemId`
- `startedAtMs`
- `reason?`
- `grantRoot?`

Evidence:

- `item.rs:1331`
- `item.rs:1348`

Dynamic tool call params include:

- `threadId`
- `turnId`
- `callId`
- `namespace?`
- `tool`
- `arguments`

Evidence:

- `item.rs:1356`
- `item.rs:1366`

Tool request-user-input question fields include:

- `id`
- `header`
- `question`
- `isOther`
- `isSecret`
- `options`

Evidence:

- `item.rs:1400`
- `item.rs:1421`

Meaning:

- Request IDs are monotonic per app-server sender, but they identify pending
  server-to-client prompts, not thread messages.
- Request params often contain `threadId`, `turnId`, and `itemId`, which is how
  clients attach request cards to the current thread detail.

## Thread Goals

Thread goals are thread-level metadata, not message/turn IDs, but they are part
of the thread state surface.

`ThreadGoal` fields:

- `threadId`
- `objective`
- `status`
- `tokenBudget`
- `tokensUsed`
- `timeUsedSeconds`
- `createdAt`
- `updatedAt`

Evidence:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:663`
- `thread.rs:680`

Goal statuses:

- `active`
- `paused`
- `blocked`
- `usageLimited`
- `budgetLimited`
- `complete`

Evidence:

- `thread.rs:652`
- `thread.rs:660`

Methods include:

- `thread/goal/set`
- `thread/goal/get`
- `thread/goal/clear`
- `thread/goal/updated` notification
- `thread/goal/cleared` notification

Dock relay routes `thread/goal/get`, but current Swift app code does not have a
dedicated typed client method for it.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:470`
- `dock-relay-thread-data.mjs:471`

## Dock Client And Relay Projection

Codex Dock consumes two different shapes:

- Home/Dock list: relay card stream DTOs, not raw app-server `Thread` rows.
- Thread Detail: app-server thread APIs routed through relay:
  `thread/read includeTurns:false`, paged `thread/turns/list`, then
  `thread/resume excludeTurns:true`.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadDetailStore.swift:563`
- `ThreadDetailStore.swift:573`
- `ThreadDetailStore.swift:619`

### Swift `ThreadDTO`

Swift decodes app-server/raw thread rows with optional fields so partial rows do
not fail a whole page.

Fields:

- `id`
- `sessionId`
- `forkedFromId`
- `preview`
- `ephemeral`
- `modelProvider`
- `createdAt`
- `updatedAt`
- `status`
- `path`
- `cwd`
- `cliVersion`
- `source`
- `threadSource`
- `agentNickname`
- `agentRole`
- `gitInfo`
- `name`
- `latestSummary`
- `turns`

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/ThreadListDTO.swift:150`
- `ThreadListDTO.swift:172`

Important Dock-only extension:

- `latestSummary` is not part of Codex v2 `Thread` in `thread_data.rs`.
- It is a relay/client enrichment field that Swift can decode when present.

### Swift `ThreadDetailDTO`

`ThreadReadParams` exposes:

- `threadId`
- `includeTurns`

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/ThreadDetailDTO.swift:3`
- `ThreadDetailDTO.swift:10`

`ThreadTurnsListParams` exposes only:

- `threadId`
- `cursor`
- `limit`

Evidence:

- `ThreadDetailDTO.swift:13`
- `ThreadDetailDTO.swift:22`

`ThreadTurnsListResponseDTO` keeps turns as raw `[JSONValue]`.

Evidence:

- `ThreadDetailDTO.swift:25`
- `ThreadDetailDTO.swift:38`

Meaning:

- Dock does not currently send `itemsView=full` or `sortDirection` from Swift.
- Dock receives summary turns by default.
- Dock does not have structured Swift DTOs for every v2 `Turn` or `ThreadItem`;
  it projects raw JSON into UI events.

### Thread Detail Read Flow

Thread detail reads:

1. `thread/read` with `includeTurns: false`
2. all pages of `thread/turns/list`
3. `thread/resume` with `excludeTurns: true`
4. local replacement of `thread.turns` with the drained turns

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadDetailStore.swift:569`
- `ThreadDetailStore.swift:573`
- `ThreadDetailStore.swift:576`
- `ThreadDetailStore.swift:581`
- `ThreadDetailStore.swift:607`
- `ThreadDetailStore.swift:619`
- `ThreadDetailStore.swift:624`

The page drain uses `nextCursor` and detects repeated cursors.

Evidence:

- `ThreadDetailStore.swift:581`
- `ThreadDetailStore.swift:602`

### Dock-Derived Thread Events

`ThreadEvent` is a Dock UI model, not a Codex app-server model.

Fields:

- `id`
- `kind`
- `visibilityCategory`
- `title`
- `body`
- `date`
- `isLive`
- `turnID`
- `itemID`
- `turnSequence`
- `itemSequence`
- `eventSequence`
- `displayGroupDate`
- `isStreamingDelta`

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/Models/ThreadEvent.swift:41`
- `ThreadEvent.swift:56`

Dock derives `turnSequence` and `itemSequence` by enumerating the received
`thread.turns` and turn `items` arrays.

Evidence:

- `ThreadEvent.swift:224`
- `ThreadEvent.swift:228`
- `ThreadEvent.swift:332`
- `ThreadEvent.swift:349`
- `ThreadEvent.swift:356`

Dock uses `eventSequence` to order multiple UI events from one item, such as a
command event and a command output event.

Evidence:

- `ThreadEvent.swift:400`
- `ThreadEvent.swift:480`

Display ordering sorts by:

1. date descending
2. `turnSequence` descending
3. `itemSequence` ascending
4. item key
5. `eventSequence` ascending
6. event ID
7. original offset

Evidence:

- `ThreadEvent.swift:146`
- `ThreadEvent.swift:191`

Important meaning:

- `turnSequence`, `itemSequence`, and `eventSequence` are local Dock projection
  fields.
- They are not Codex-origin IDs.
- They are not stable storage fields.
- Their meaning depends on the order Dock received from `thread/turns/list`.
  Since Swift currently relies on app-server default descending turn order,
  `turnSequence = 0` is normally the first returned turn, not "the first turn
  ever in the thread".

### Dock Historical Event Dates

Dock uses turn-level seconds for historical item events:

- first `startedAt`
- then `completedAt`

Evidence:

- `ThreadEvent.swift:347`

For item event fallback it can look for `startedAtMs` / `completedAtMs` on the
turn JSON, but historical `ThreadItem` does not normally carry those fields.

Evidence:

- `ThreadEvent.swift:392`
- `ThreadEvent.swift:616`
- `ThreadEvent.swift:627`

Live deltas use the local receive time `now`.

Evidence:

- `ThreadEvent.swift:518`
- `ThreadEvent.swift:544`

Server requests become live UI events with local receive time `now`, an ID of
`request-{request.id}`, and `turnId` / `itemId` pulled from params.

Evidence:

- `ThreadEvent.swift:301`
- `ThreadEvent.swift:321`

### Dock Supported Item Projection

Dock currently projects these `ThreadItem.type` values into UI events:

- `userMessage`
- `agentMessage`
- `plan`
- `reasoning`
- `commandExecution`
- `fileChange`
- `mcpToolCall`
- `dynamicToolCall`

Unsupported item types become `unknown` UI events.

Evidence:

- `ThreadEvent.swift:419`
- `ThreadEvent.swift:515`

Live notifications recognized by `ThreadEventNormalizer.event(from:)` are a
subset of server notifications. Unknown notification methods produce no UI
event.

Evidence:

- `ThreadEvent.swift:232`
- `ThreadEvent.swift:297`

### Thread Detail Active Turn Tracking

Dock's `ThreadDetailDataEngine`:

- replaces or merges normalized events from `ThreadDTO`
- tracks active turn ID from in-progress turns
- updates active turn on `turn/started`
- clears active turn on matching `turn/completed`
- merges streaming deltas by `turnID`, `itemID`, kind, and visibility category

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:19`
- `ThreadDetailDataEngine.swift:44`
- `ThreadDetailDataEngine.swift:47`
- `ThreadDetailDataEngine.swift:60`
- `ThreadDetailDataEngine.swift:98`
- `ThreadDetailDataEngine.swift:127`
- `ThreadDetailDataEngine.swift:141`
- `ThreadDetailDataEngine.swift:220`

When sending a draft, Dock records the returned turn ID as active.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadDetailStore.swift:361`
- `ThreadDetailStore.swift:369`

## Dock Relay Thread/Card Fields

### Raw `thread/read` And `thread/turns/list` Routing

Relay `aggregateThreadRead`:

- requires `threadId`
- checks whether there is a live routed row
- applies the human-started thread filter
- if live and `includeTurns` is false, returns sanitized live row directly
- if live and `includeTurns` is true, forwards to the owning endpoint
- otherwise reads history via app-server `thread/read`

Evidence:

- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:753`
- `dock-relay-thread-data.mjs:769`

Relay `listThreadTurns`:

- requires `threadId`
- asserts the ID belongs to a human-started thread
- routes to history or owning live endpoint

Evidence:

- `dock-relay-thread-data.mjs:772`
- `dock-relay-thread-data.mjs:781`

Relay strips downstream `sourceKind` / `sourceKinds` from user-supplied human
thread list params before querying history.

Evidence:

- `dock-relay-thread-data.mjs:219`
- `dock-relay-thread-data.mjs:221`

### Relay Card Projection

Relay normalizes raw app-server thread rows into Dock card rows.

`DockThreadCardDTO` fields:

- `id`
- `logicalHostID`
- `threadID`
- `backendSessionID`
- `hostDisplayName`
- `hostEndpoint`
- `orderKey`
- `activityAt`
- `activityAtMs`
- `displaySummary`
- `title`
- `status`
- `sourceKind`
- `lane`
- `relationship`
- `forkedFromID`
- `archiveState`
- `freshness`
- `completeness`
- `repository`
- `workingDirectory`
- `branch`
- `summarySource`

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/DockThreadCardDTO.swift:342`
- `DockThreadCardDTO.swift:365`

Relay-derived card field meanings:

- `id`: synthetic Dock card ID, `<logicalHostID>::<threadID>`.
- `logicalHostID`: relay host identity.
- `threadID`: Codex `Thread.id`.
- `backendSessionID`: Codex `sessionId`, fallback to `threadID`.
- `activityAtMs`: derived from `thread.activityAt` if present, else
  `updatedAt`, else `createdAt`.
- `activityAt`: ISO string derived from `activityAtMs`.
- `displaySummary`: first available bounded text from `displaySummary`,
  `latestSummary`, `summary`, `preview`, then title fallback.
- `title`: bounded `name`, then `preview`, then cwd basename, then short thread
  fallback.
- `status`: derived from Codex `status.type` and `activeFlags`.
- `sourceKind`: derived from relay lane, not raw Codex source string.
- `lane`: `human` or `agent`.
- `relationship`: `forked` when `forkedFromId` / `forked_from_id` exists,
  otherwise `root`.
- `forkedFromID`: parent thread ID.
- `repository`: derived from `gitInfo.originUrl` or cwd basename.
- `workingDirectory`: first bounded value from `cwd` or `path`.
- `branch`: `gitInfo.branch`.
- `summarySource`: explains which source produced the summary.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:55`
- `dock-relay-state-views.mjs:69`
- `dock-relay-state-views.mjs:91`
- `dock-relay-state-views.mjs:119`
- `dock-relay-state-views.mjs:143`
- `dock-relay-state-views.mjs:150`
- `dock-relay-state-views.mjs:162`
- `dock-relay-state-views.mjs:166`
- `dock-relay-state-views.mjs:192`
- `dock-relay-state-views.mjs:201`
- `dock-relay-state-views.mjs:220`
- `dock-relay-state-views.mjs:224`
- `dock-relay-state-views.mjs:312`
- `dock-relay-state-views.mjs:349`

Relay reconcile requests `thread/list` with:

- `archived: false`
- max list limit
- `sortKey: "updated_at"`
- `sortDirection: "desc"`
- `modelProviders: []`

Evidence:

- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-engine.mjs:249`
- `dock-relay-state-engine.mjs:258`

Dock row projection then maps `DockThreadCardDTO` into UI rows, parsing
`activityAtMs` first and falling back to ISO `activityAt`.

Evidence:

- `/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardRowProjector.swift:27`
- `ThreadCardRowProjector.swift:58`
- `ThreadCardRowProjector.swift:118`
- `ThreadCardRowProjector.swift:130`

Dock UI relationship collapses `spawned` to `root`, while preserving `forked`.

Evidence:

- `ThreadCardRowProjector.swift:188`
- `ThreadCardRowProjector.swift:195`

## Field Origin Cheat Sheet

Codex-origin fields:

- `Thread.id`
- `Thread.sessionId`
- `Thread.forkedFromId`
- `Thread.preview`
- `Thread.ephemeral`
- `Thread.modelProvider`
- `Thread.createdAt`
- `Thread.updatedAt`
- `Thread.status`
- `Thread.path`
- `Thread.cwd`
- `Thread.cliVersion`
- `Thread.source`
- `Thread.threadSource`
- `Thread.agentNickname`
- `Thread.agentRole`
- `Thread.gitInfo`
- `Thread.name`
- `Thread.turns`
- `Turn.id`
- `Turn.items`
- `Turn.itemsView`
- `Turn.status`
- `Turn.error`
- `Turn.startedAt`
- `Turn.completedAt`
- `Turn.durationMs`
- `ThreadItem.type`
- `ThreadItem.id`
- all variant-specific `ThreadItem` fields listed above
- live notification `startedAtMs` / `completedAtMs`
- server request card `id`, `method`, and params

Codex store-only or lower-level fields not fully surfaced in Swift thread DTOs:

- stored `model`
- stored `reasoning_effort`
- stored `agent_path`
- stored `approval_mode`
- stored `sandbox_policy`
- stored `token_usage`
- raw rollout line `timestamp`
- raw `ResponseItem::Message.id`

Dock relay/client-derived fields:

- Dock card `id`
- Dock card `backendSessionID` fallback behavior
- Dock card `orderKey`
- Dock card `activityAt`
- Dock card `activityAtMs`
- Dock card `displaySummary`
- Dock card `title` fallback behavior
- Dock card normalized `status`
- Dock card `sourceKind`
- Dock card `lane`
- Dock card `relationship`
- Dock card `repository`
- Dock card `workingDirectory`
- Dock card `summarySource`
- Dock event `id`
- Dock event `title`
- Dock event `body`
- Dock event `visibilityCategory`
- Dock event `turnSequence`
- Dock event `itemSequence`
- Dock event `eventSequence`
- Dock event `displayGroupDate`
- Dock event `isStreamingDelta`
- Dock relay stream `seq`

## Practical Client Rules

Treat app-server IDs as opaque strings unless a specific Codex API requires a
thread UUID.

Use `Thread.id` as the durable thread key. It is UUIDv7 today, but code should
not sort by it for chronology.

Use `Turn.id` as an opaque turn key. It is normally a UUIDv7 submission ID for
regular app-server turns, but internal and reconstructed turns can be non-UUID.

Do not look for a Codex message number. It does not exist as a public field on
thread messages.

Do not use message/item IDs for chronological ordering. They may be UUIDv4,
provider IDs, tool call IDs, or synthetic `item-N` reconstruction IDs.

Use API array order and cursors for pagination. For `thread/turns/list`, remember
the current app-server default is newest-first (`sortDirection: desc`).

Use `Thread.createdAt` and `Thread.updatedAt` for thread-level display and sort.
They are Unix seconds on the app-server v2 wire.

Use `Turn.startedAt` and `Turn.completedAt` for historical turn/message display.
They are Unix seconds.

Use live `item/started.startedAtMs`, `item/completed.completedAtMs`, and request
card `startedAtMs` when rendering live item/request timing. They are Unix
milliseconds.

Do not expect historical `ThreadItem` objects to carry their own timestamp.

Do not assume `thread.read(includeTurns: true)` and `thread/turns/list` return
the same payload size. `thread/turns/list` defaults to summary mode, while
`includeTurns` reconstructs full available history.

Do not assume persisted history is complete compared with live notifications.
It is a replayable, intentionally limited history.

Do not treat `latestSummary`, Dock card fields, or Dock event sequence fields as
Codex protocol fields. They are relay/client projection fields.

Do not treat app-server server request IDs or Dock relay stream `seq` as message
numbers. They are transport/projection counters.

## Direct Answers To The Original Questions

Do we have a message number from Codex itself, ideally monotonically increasing?

No. Codex does not expose a durable monotonically increasing message number on
each message in a thread. Historical reconstruction can synthesize `item-1`,
`item-2`, etc., but those are local reconstruction IDs, not a Codex message
ordinal. Dock adds `turnSequence`, `itemSequence`, and `eventSequence` for UI
ordering, but those are Dock-derived and depend on received array order.

Do we have a timestamp for each message within a thread?

Not on historical `ThreadItem::UserMessage` or `ThreadItem::AgentMessage`.
Threads have `createdAt` / `updatedAt` in Unix seconds. Turns have optional
`startedAt` / `completedAt` in Unix seconds plus `durationMs`. Live item
lifecycle notifications have `startedAtMs` / `completedAtMs` in Unix
milliseconds. Raw rollout JSONL lines have timestamp strings, but app-server
history reconstruction discards those wrapper timestamps.

Are turn IDs UUIDs?

Normal app-server turn IDs are UUIDv7 strings because `turn/start` returns the
core `Submission.id`, and core generates that with `Uuid::now_v7()`. But the
protocol type is `String`, and internal or reconstructed turns can be non-UUID
strings such as `auto-compact-0` or `rollout-3`. Treat turn IDs as opaque
strings.

Did this audit check Codex itself?

Yes. The primary source is `/Users/aelaguiz/workspace/codex`, especially the
Rust protocol, app-server, core session, thread-store, and rollout code. The
Dock client and relay at `/Users/aelaguiz/workspace/codex-client` were checked
separately to document what Codex Dock receives and what it derives.
