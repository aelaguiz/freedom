---
title: "Codex Disk And Database Thread Types And State"
date: 2026-05-29
status: active
doc_type: reference
owners: [Amir, Codex]
related:
  - docs/CODEX_DOCK_GOALS_2026-05-29.md
  - docs/CODEX_DOCK_RELAY_THREAD_FIDELITY_WORKLOG_2026-05-29.md
  - docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md
---

# Codex Disk And Database Thread Types And State

This document answers one question: what can we prove by looking at Codex's
local rollout files and SQLite databases, without trusting only the app-server?

Short answer: disk is best for durable history, SQLite is best for fast indexed
metadata, and the app-server is still required for live state. A thread can be
stored on disk and not loaded, loaded in the app-server, archived, spawned by
another thread, forked, goal-tracked, or prompt-started. No single storage field
answers all of that.

Related goal source: [Codex Dock Goals](CODEX_DOCK_GOALS_2026-05-29.md).

## Scope

This is the storage-side companion to
`docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md`.

It covers these local Codex storage surfaces:

- rollout JSONL files under `$CODEX_HOME/sessions/**`;
- archived rollout JSONL files under `$CODEX_HOME/archived_sessions/**`;
- the append-only thread-name sidecar at `$CODEX_HOME/session_index.jsonl`;
- the thread metadata DB at `$CODEX_SQLITE_HOME/state_5.sqlite`;
- the thread goals DB at `$CODEX_SQLITE_HOME/goals_1.sqlite`;
- relevant `state_5.sqlite` helper tables such as `thread_spawn_edges`,
  `thread_dynamic_tools`, `backfill_state`, `agent_jobs`, and
  `agent_job_items`.

It deliberately does not treat local logs, relay memory, simulator UI state, or
preview rows as completion evidence. Those can help debug, but they are not the
canonical durable thread record.

## Terms

Codex home:
: The directory that stores Codex rollout files and sidecars. In normal local
  use this is `$HOME/.codex`, unless Codex was started with a different
  `codex_home`.

SQLite home:
: The directory that stores Codex's SQLite DB files. Codex resolves it from
  config `sqlite_home`, then `$CODEX_SQLITE_HOME`, then `$CODEX_HOME`.

Rollout:
: A JSONL file containing persisted session metadata, turn context, messages,
  compacted history markers, selected events, tool calls, and response items.
  This is the durable replay/history source.

State DB:
: `state_5.sqlite`. This mirrors rollout metadata into indexed SQLite tables so
  listing, searching, filtering, and spawn-tree lookup can be fast.

Goals DB:
: `goals_1.sqlite`. Current persisted thread goals live here, not in
  `state_5.sqlite`.

Session index:
: `session_index.jsonl`. This is an append-only sidecar for user-facing thread
  names. The newest entry for a thread ID wins.

Loaded:
: The app-server process currently has runtime state for the thread in memory.
  Storage alone cannot prove loaded state.

Archived:
: The rollout file was moved from the active `sessions` collection to the
  `archived_sessions` collection, and the DB row should have `archived = 1`.

## One-Page Answer

Use this rule of thumb:

| Question | Strongest local proof | What storage cannot prove |
| --- | --- | --- |
| Does the thread exist durably? | A rollout file with `type: "session_meta"` and matching `payload.id`, or a valid `threads` row whose `rollout_path` still exists. | Whether the app-server currently has it loaded. |
| Is it active or archived? | Active path under `$CODEX_HOME/sessions/**`; archived path under `$CODEX_HOME/archived_sessions/**`; DB `threads.archived`. | Whether a live app-server still has an old copy loaded. |
| Is it live now? | No local storage-only proof. | Live/idle/active/waiting requires app-server `Thread.status` and `thread/loaded/list`. |
| Is it user-created? | `SessionMeta.source` plus `thread_source`; DB `threads.source` plus `thread_source`. | "User-created" is a product interpretation, not one universal stored boolean. |
| Is it spawned? | DB `thread_spawn_edges`; rollout `source.subagent.thread_spawn`; `agent_nickname`, `agent_role`, `agent_path`; `thread_source = "subagent"`. | Live session-tree `sessionId`. |
| Is it forked? | Rollout `payload.forked_from_id` in the `session_meta` line. | `state_5.sqlite.threads` does not have a `forked_from_id` column. |
| Did it start with a prompt? | First persisted user message in rollout; DB `first_user_message` and `preview`. | Whether that prompt came in the same RPC that created the thread. |
| Was it a JSON-mode turn? | Usually not durable for normal turns. `final_output_json_schema` lives in the turn runtime path, not `TurnContextItem` or `threads`. | Old JSON-mode use after the fact. |
| Does it have a current goal? | `goals_1.sqlite.thread_goals`. | Ephemeral thread goals, because ephemeral threads do not get persisted goals. App-server cannot list orphan goal rows by itself. |
| What is the current goal status? | `goals_1.sqlite.thread_goals.status`. | Whether a currently running turn is about to change it. Goal rows can change while an audit is running. |
| What turns/items happened? | Rollout JSONL. | Some live events are intentionally not persisted. |
| Is realtime active now? | App-server live state. Rollout `turn_context.realtime_active` is only last persisted turn context. | Current realtime state from disk alone. |

## Storage Map

Default locations:

```bash
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_SQLITE_HOME="${CODEX_SQLITE_HOME:-$CODEX_HOME}"
```

Important files:

```text
$CODEX_HOME/sessions/YYYY/MM/DD/rollout-YYYY-MM-DDThh-mm-ss-<thread-id>.jsonl
$CODEX_HOME/archived_sessions/rollout-YYYY-MM-DDThh-mm-ss-<thread-id>.jsonl
$CODEX_HOME/session_index.jsonl
$CODEX_SQLITE_HOME/state_5.sqlite
$CODEX_SQLITE_HOME/goals_1.sqlite
$CODEX_SQLITE_HOME/logs_2.sqlite
$CODEX_SQLITE_HOME/memories_1.sqlite
```

`state_5.sqlite` and `goals_1.sqlite` may be under a custom SQLite home. Codex
uses this resolution order:

1. `sqlite_home` in config.
2. `$CODEX_SQLITE_HOME`, if set and non-empty. A relative env var path is
   resolved against the process cwd.
3. `$CODEX_HOME`.

`logs_2.sqlite` and `memories_1.sqlite` are real runtime DBs, but they are not
the primary source for thread type, source, archive, spawn, or goal checks.

## Authority Rules

Use these when storage and app-server disagree:

| Area | Prefer | Reason |
| --- | --- | --- |
| Full message/history replay | Rollout JSONL | It is the durable history stream. |
| Fast list/search/filter rows | `state_5.sqlite` | It is the indexed metadata mirror. |
| Current persisted goal | `goals_1.sqlite` | Current goal rows live there. |
| Goal event trail | Rollout JSONL | `thread_goal_updated` events show what was emitted over time. |
| User-facing name | `threads.title`, then `session_index.jsonl` | DB stores current title when available; sidecar is the legacy append-only name index. |
| Spawn tree lookup | `thread_spawn_edges` | It is normalized and easier than parsing `source` JSON text. |
| Fork source | Rollout `session_meta.payload.forked_from_id` | The current state DB schema does not store fork parent ID. |
| Live/loaded/active/waiting | App-server | No local DB table is the live runtime state table. |
| Ephemeral threads | App-server | Ephemeral means memory-only; absence from disk is not enough proof by itself. |

The state DB can be stale. Codex backfills it from rollouts and also read-repairs
some stale paths, but the rollout file is still the stronger source for history.
If a DB row points at a missing file, treat the DB row as stale until a scan or
repair confirms otherwise.

## Rollout File Layout

Active rollouts are nested by local date:

```text
$CODEX_HOME/sessions/YYYY/MM/DD/rollout-YYYY-MM-DDThh-mm-ss-<thread-id>.jsonl
```

Archived rollouts are moved to a flat archive collection:

```text
$CODEX_HOME/archived_sessions/rollout-YYYY-MM-DDThh-mm-ss-<thread-id>.jsonl
```

When unarchived, Codex restores the file into the dated `sessions/YYYY/MM/DD`
directory using the date embedded in the filename.

Important filename details:

- The filename suffix UUID is the thread ID in normal files.
- The directory and filename timestamp are created from local time.
- The `session_meta.payload.timestamp` value is written as UTC with
  millisecond precision.
- A newly created session may not have a rollout file yet. Codex precomputes
  the path, but file creation is deferred until the writer is asked to persist
  or flush materialized items.

## Rollout Line Shape

Every rollout line is one JSON object. The outer object has a write timestamp
and a flattened `RolloutItem`:

```json
{
  "timestamp": "2026-05-29T20:10:11.123Z",
  "type": "session_meta",
  "payload": {
    "id": "00000000-0000-0000-0000-000000000000",
    "timestamp": "2026-05-29T20:10:11.000Z",
    "cwd": "/path/to/workspace",
    "originator": "codex_cli_rs",
    "cli_version": "0.0.0",
    "source": "cli",
    "thread_source": "user",
    "model_provider": "openai"
  }
}
```

The line `type` can be:

| `type` | Meaning |
| --- | --- |
| `session_meta` | Session/thread metadata. Usually the first durable line. |
| `turn_context` | Persisted model/runtime context for a turn. |
| `event_msg` | Selected persisted event, such as user message, assistant message, token count, turn started/completed, goal update, or command end in extended mode. |
| `response_item` | Persisted Responses API item, such as message, reasoning, tool call, tool output, web search, or image generation. |
| `compacted` | A compaction marker and optional replacement history. |

Codex does not persist every live event. In limited persistence mode it keeps
core history events such as user messages, assistant messages, token counts,
goal updates, context compaction, turn start/complete, web search end, image
generation end, and some completed plan events. Extended mode adds more debug
events such as command end, view image, collaboration agent events, dynamic tool
call events, and errors. Many begin/delta/progress events are intentionally not
durable.

## Session Metadata Fields

The rollout `session_meta.payload` is the main durable metadata header:

| Field | Meaning |
| --- | --- |
| `id` | Thread ID. |
| `forked_from_id` | Fork parent thread ID, if this was created as a fork. |
| `timestamp` | Session creation timestamp. |
| `cwd` | Working directory. |
| `originator` | Codex originator string. |
| `cli_version` | Codex CLI/package version. |
| `source` | Session source, such as `cli`, `vscode`, `exec`, `mcp`, custom string, internal source, or sub-agent source. |
| `thread_source` | Optional analytics classification: `user`, `subagent`, or `memory_consolidation`. |
| `agent_nickname` | Optional spawned-agent nickname. |
| `agent_role` | Optional spawned-agent role. |
| `agent_path` | Optional canonical spawned-agent path. |
| `model_provider` | Model provider ID, such as `openai`. |
| `base_instructions` | Session base instructions. |
| `dynamic_tools` | Dynamic tool specs available to the thread. |
| `memory_mode` | Memory mode, commonly absent or `disabled`. |
| `git` | Optional Git SHA, branch, and origin URL. This is sibling data inside the `payload`, not inside the `meta` object. |

For simple sources, `source` is usually a string such as `cli`, `vscode`,
`exec`, or `mcp`. For complex sources, such as spawned agents, it serializes as
structured JSON.

## SQLite Files

Codex opens four runtime DBs under SQLite home:

| File | Main purpose |
| --- | --- |
| `state_5.sqlite` | Thread metadata, dynamic tools, spawn edges, backfill state, agent jobs, some non-thread runtime tables. |
| `goals_1.sqlite` | Current per-thread goals. |
| `logs_2.sqlite` | Structured logs. Not the canonical thread-type source. |
| `memories_1.sqlite` | Memory runtime data. Not the canonical thread-type source. |

The storage cross-check usually needs only `state_5.sqlite`,
`goals_1.sqlite`, and the rollout file.

## `state_5.sqlite` Tables

### `threads`

`threads` is the indexed mirror of rollout thread metadata.

Important columns:

| Column | Meaning |
| --- | --- |
| `id` | Thread ID. |
| `rollout_path` | Absolute path to the rollout JSONL file. |
| `created_at`, `updated_at` | Legacy Unix second timestamps. |
| `created_at_ms`, `updated_at_ms` | Unix millisecond timestamps used for ordering. |
| `source` | Stringified `SessionSource`. Simple values are plain strings; complex values may be JSON text. |
| `thread_source` | Optional `user`, `subagent`, or `memory_consolidation`. |
| `agent_nickname`, `agent_role`, `agent_path` | Optional spawned-agent metadata. |
| `model_provider` | Provider ID. |
| `model` | Latest observed model slug from `turn_context`. |
| `reasoning_effort` | Latest observed reasoning effort from `turn_context`. |
| `cwd` | Normalized working directory. |
| `cli_version` | Codex version that created the thread. |
| `title` | User-facing title/name where known. |
| `preview` | Latest available preview. Often first user message, but can be a goal objective or assistant message. |
| `sandbox_policy` | Latest observed sandbox policy from `turn_context`. |
| `approval_mode` | Latest observed approval policy from `turn_context`. |
| `tokens_used` | Last observed total token count. |
| `first_user_message` | First persisted user message preview. |
| `archived` | `1` when archived, `0` when active. |
| `archived_at` | Unix second archive timestamp, if archived. |
| `git_sha`, `git_branch`, `git_origin_url` | Git metadata. |
| `memory_mode` | Thread memory mode, default `enabled`. |

Important absence:

- There is no `forked_from_id` column in `threads`.
- There is no live `session_id` column.
- There is no normalized turns/items table for ordinary thread history.

### `thread_dynamic_tools`

This table stores dynamic tools from `session_meta.payload.dynamic_tools`.

Columns:

```text
thread_id
position
namespace
name
description
input_schema
defer_loading
```

This tells you which dynamic tools were available to a thread. It does not mean
the thread was in JSON-output mode.

### `thread_spawn_edges`

This table stores normalized parent-child relationships for spawned threads.

Columns:

```text
parent_thread_id
child_thread_id
status
```

`status` is one of:

```text
open
closed
```

This is the best DB-side proof that a child thread was spawned from a parent
thread. It is also easier to query than parsing `threads.source`.

### `backfill_state`

This table tracks whether SQLite has finished scanning rollout files into
`state_5.sqlite`.

Columns:

```text
id
status
last_watermark
last_success_at
updated_at
```

If `status` is not `complete`, the DB mirror may be incomplete. In that case,
prefer scanning rollout files for cross-checks.

### `agent_jobs` And `agent_job_items`

These tables describe batch agent jobs, not normal interactive thread turns.

`agent_jobs` includes:

```text
id
name
status
instruction
output_schema_json
input_headers_json
input_csv_path
output_csv_path
auto_export
max_runtime_seconds
created_at
updated_at
started_at
completed_at
last_error
```

`agent_job_items` includes:

```text
job_id
item_id
row_index
source_id
row_json
status
assigned_thread_id
attempt_count
result_json
last_error
created_at
updated_at
completed_at
reported_at
```

`agent_jobs.output_schema_json` is a job-level output schema. Do not treat it
as proof that an ordinary app-server `turn/start.outputSchema` was used.

## `goals_1.sqlite`

Current per-thread goals live in `goals_1.sqlite`, table `thread_goals`.

Columns:

```text
thread_id
goal_id
objective
status
token_budget
tokens_used
time_used_seconds
created_at_ms
updated_at_ms
```

Goal statuses:

```text
active
paused
blocked
usage_limited
budget_limited
complete
```

`state_5.sqlite` used to have a `thread_goals` table in older migrations, but
the current state migrations drop it. For current storage, check
`goals_1.sqlite`.

Observed storage caveat from the 2026-05-30 relay parity audit:

- `goals_1.sqlite.thread_goals` can contain rows whose `thread_id` is absent
  from current `state_5.sqlite.threads`.
- App-server `thread/goal/get` can read a goal for a known materialized thread
  ID, but app-server does not expose a standalone goal-list API.
- App-server goal payloads do not include SQLite `goal_id`.
- For current app-server-reachable threads, compare by `thread_id` and goal
  content. For orphan goal rows, storage can prove the row exists, but the
  app-server cannot discover it without a thread list/read path for that ID.

## `session_index.jsonl`

Thread names can also be stored in this append-only sidecar:

```json
{
  "id": "00000000-0000-0000-0000-000000000000",
  "thread_name": "A sharper name",
  "updated_at": "2026-05-29T20:10:11Z"
}
```

The newest entry for a thread ID wins. Codex can use this sidecar when DB title
metadata is missing or when finding a thread by name.

## Detection Matrix

### Thread Exists

Strong disk proof:

- A rollout file exists.
- It contains a `session_meta` line.
- `session_meta.payload.id` equals the thread ID.

Strong DB proof:

- `state_5.sqlite.threads.id` has a row.
- `threads.rollout_path` points to a file that still exists.

Caveat:

- A DB row with a missing `rollout_path` is stale until repaired.
- A newly created but never persisted session may have a precomputed path but
  no file.

### Active Vs Archived

Disk proof:

- Active: path starts with `$CODEX_HOME/sessions/`.
- Archived: path starts with `$CODEX_HOME/archived_sessions/`.

DB proof:

- Active: `threads.archived = 0`.
- Archived: `threads.archived = 1` and `threads.archived_at IS NOT NULL`.

Caveat:

- Archive/unarchive moves the file and updates DB metadata when state DB is
  available. If a move happened while DB was unavailable, the path is stronger
  than the stale DB row.

### Live Vs Old

Storage-only answer:

- You can know last durable update time.
- You can know whether the thread is active collection or archived collection.
- You cannot know whether it is loaded, idle, active, waiting on approval, or
  waiting on user input right now.

Cross-check rule:

- If app-server says loaded and DB says active, it is live and durable.
- If app-server says `notLoaded` and DB/file exists, it is stored but not
  loaded.
- If DB/file exists but app-server cannot read it, check `rollout_path`,
  archive status, backfill state, and parse errors.
- If app-server shows `ephemeral: true`, absence from DB/file is expected.

### User-Created Vs Spawned

Storage fields:

- Rollout `session_meta.payload.source`.
- Rollout `session_meta.payload.thread_source`.
- DB `threads.source`.
- DB `threads.thread_source`.
- DB `thread_spawn_edges`.

Source values are the product/runtime origin. Known `SessionSource` variants
include:

```text
cli
vscode
exec
mcp
custom string
internal memory_consolidation
subagent review
subagent compact
subagent thread_spawn
subagent memory_consolidation
subagent other
unknown
```

Important distinction:

- `source` says where the session came from.
- `thread_source` is a smaller analytics label: `user`, `subagent`, or
  `memory_consolidation`.
- A Dock-created user thread may have `source = "mcp"` because app-server
  startup source aliases map to MCP.
- The default interactive rollout listing treats `cli`, `vscode`, custom
  `atlas`, and custom `chatgpt` as interactive session sources.

Strong spawned proof:

- `thread_spawn_edges.child_thread_id = <thread-id>`.
- Or `source` is a structured sub-agent thread-spawn value with a
  `parent_thread_id`.
- Or `thread_source = "subagent"` plus populated `agent_nickname`,
  `agent_role`, or `agent_path`.

Weak spawned hint:

- The preview or name says it is an agent. Names are not reliable type fields.

### Spawn Tree

Best DB query:

```sql
SELECT parent_thread_id, child_thread_id, status
FROM thread_spawn_edges
WHERE parent_thread_id = '<thread-id>'
   OR child_thread_id = '<thread-id>'
ORDER BY parent_thread_id, child_thread_id;
```

If the edge row exists, it is better than inferring from UI labels.

Storage cannot prove live `sessionId`. The app-server can expose a live session
tree ID, but the persisted DB does not have a separate `session_id` column.
For stored-only trees, reconstruct the tree from `thread_spawn_edges`,
`source.subagent.thread_spawn.parent_thread_id`, and fork IDs.

### Forked Threads

Strong disk proof:

- The rollout `session_meta.payload.forked_from_id` is present.

DB limitation:

- `state_5.sqlite.threads` does not store `forked_from_id`.

Cross-check rule:

- If app-server `Thread.forkedFromId` exists, it should match rollout
  `session_meta.payload.forked_from_id`.
- If DB has no fork parent, that is expected with the current schema.

### Started With A Prompt

Strongest storage hints:

- First persisted `event_msg` with `payload.type = "user_message"`.
- DB `threads.first_user_message`.
- DB `threads.preview`, if it matches the first user message.

Caveat:

- `thread/start` and first user input are separate app-server concepts.
- Storage can show that the first durable turn had user text.
- Storage cannot prove that the thread was created and prompted in the same
  RPC or user gesture.

### JSON Mode / Structured Output Turns

Normal turn JSON schema is not reliably recoverable from storage.

Why:

- Runtime user input supports `final_output_json_schema`.
- Prompt construction passes that schema to the model as `output_schema`.
- Persisted `TurnContextItem` does not include `final_output_json_schema`.
- `state_5.sqlite.threads` has no JSON-output-mode column.

What can be checked:

- App-server live/request history, if available.
- Actual assistant output shape, as an inference only.
- `agent_jobs.output_schema_json`, but only for batch agent jobs.

Do not mark an old ordinary thread as JSON-mode just because the assistant's
message happens to be JSON.

### Realtime

Storage has only weak historical evidence:

- `turn_context.payload.realtime_active` can show the value captured for a
  persisted turn context.

It is not current state. Use app-server realtime methods and notifications for
current realtime state.

### Goals

Current persisted goal:

- `goals_1.sqlite.thread_goals`.

Goal event trail:

- Rollout `event_msg` lines with `payload.type = "thread_goal_updated"`.

Expected app-server match:

- `thread/goal/get` should match `goals_1.sqlite.thread_goals` for persisted
  threads when the goals feature is enabled and the thread has a current
  materialized thread row.

Caveats:

- Ephemeral threads do not support persisted goals.
- A rollout may contain older goal-update events even after the current goal
  changed.
- `thread_goal_updated` events are history. `goals_1.sqlite.thread_goals` is
  the current persisted row.
- `goals_1.sqlite` can contain orphan goal rows whose `thread_id` is absent
  from `state_5.sqlite.threads`.
- App-server does not expose SQLite `goal_id` and does not expose a
  goal-list API. It only exposes current goal state by known thread ID.
- Goal rows can change while the app-server is running. A storage-vs-app-server
  audit must either quiesce the app-server or record before/after goal row
  stability.

### Turn State

There is no ordinary normalized turn table in `state_5.sqlite`.

Stored turn state is reconstructed from rollout history:

- `event_msg.payload.type = "task_started"` or alias `turn_started`;
- `event_msg.payload.type = "task_complete"` or alias `turn_complete`;
- `event_msg.payload.type = "turn_aborted"`;
- persisted response items and event items grouped by turn IDs where present.

Caveat:

- A persisted started event without a complete event is not proof that the turn
  is still live. The process may have crashed, exited, or not flushed later
  state.
- Current `inProgress`, `active`, waiting approval, and waiting user input
  states require app-server live state.

### Model, Reasoning, Approval, Sandbox, CWD

Disk proof:

- Latest persisted `turn_context` line.

DB proof:

- `threads.model`;
- `threads.reasoning_effort`;
- `threads.approval_mode`;
- `threads.sandbox_policy`;
- `threads.cwd`.

Caveat:

- These are latest observed persisted values, not necessarily a future turn's
  values.

### Dynamic Tools

Disk proof:

- `session_meta.payload.dynamic_tools`.

DB proof:

- `thread_dynamic_tools`.

Caveat:

- Dynamic tools are available tools, not proof that a specific tool was called.
- They are also not proof of JSON-output mode.

### Token Usage

Disk proof:

- Latest persisted `event_msg.payload.type = "token_count"`.

DB proof:

- `threads.tokens_used`.

Caveat:

- DB stores the last observed total token count.
- If a live turn is running, app-server live events may be ahead of DB.

## Cross-Check Recipes

These commands assume default paths. If config `sqlite_home` is set, replace
`$CODEX_SQLITE_HOME` with that directory.

Set the common variables:

```bash
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
export CODEX_SQLITE_HOME="${CODEX_SQLITE_HOME:-$CODEX_HOME}"
export THREAD_ID="<thread-id>"
```

### Check DB Backfill Health

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT id, status, last_watermark, last_success_at, updated_at FROM backfill_state WHERE id = 1;"
```

Interpretation:

- `status = complete`: DB mirror should be usable for normal lookup.
- Anything else: prefer rollout scan for truth and treat DB listing as
  possibly incomplete.

### Read The Thread Metadata Row

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT
     id,
     source,
     thread_source,
     agent_nickname,
     agent_role,
     agent_path,
     rollout_path,
     archived,
     archived_at,
     datetime(created_at_ms / 1000, 'unixepoch') AS created_at_utc,
     datetime(updated_at_ms / 1000, 'unixepoch') AS updated_at_utc,
     model_provider,
     model,
     reasoning_effort,
     cwd,
     cli_version,
     title,
     preview,
     first_user_message,
     tokens_used,
     memory_mode
   FROM threads
   WHERE id = '$THREAD_ID';"
```

### Get The Rollout Path From DB

```bash
export ROLLOUT_PATH="$(
  rtk sqlite3 -noheader "$CODEX_SQLITE_HOME/state_5.sqlite" \
    "SELECT rollout_path FROM threads WHERE id = '$THREAD_ID';"
)"
```

Then check whether the DB path still exists:

```bash
rtk test -f "$ROLLOUT_PATH"
```

If this fails, the DB row is stale or the file was moved/deleted.

### Find The Rollout File From Disk

Use the thread ID suffix in the filename:

```bash
rtk sh -c 'for root in "$1/sessions" "$1/archived_sessions"; do
  [ -d "$root" ] && find "$root" -name "rollout-*-$2.jsonl" -print
done' sh "$CODEX_HOME" "$THREAD_ID"
```

If this finds a file under `sessions`, it is active storage. If it finds a file
under `archived_sessions`, it is archived storage.

### Read The Session Metadata Header

```bash
rtk jq -s 'map(select(.type == "session_meta") | .payload)[0]' "$ROLLOUT_PATH"
```

Check these fields against app-server `Thread` fields:

| Rollout field | App-server field |
| --- | --- |
| `id` | `Thread.id` |
| `forked_from_id` | `Thread.forkedFromId` |
| `source` | `Thread.source` |
| `thread_source` | `Thread.threadSource` |
| `agent_nickname` | `Thread.agentNickname` |
| `agent_role` | `Thread.agentRole` |
| `agent_path` | `Thread.agentPath` |
| `cwd` | `Thread.cwd` |
| `cli_version` | `Thread.cliVersion` |
| `model_provider` | `Thread.modelProvider` |
| `git` | `Thread.gitInfo` |

### Check Whether It Is Archived

From DB:

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT id, archived, archived_at, rollout_path FROM threads WHERE id = '$THREAD_ID';"
```

From disk path:

```bash
rtk sh -c 'case "$1" in
  "$2"/sessions/*) echo active ;;
  "$2"/archived_sessions/*) echo archived ;;
  *) echo outside-codex-thread-collections ;;
esac' sh "$ROLLOUT_PATH" "$CODEX_HOME"
```

If DB says active but the file is under `archived_sessions`, trust the file path
and treat DB as stale.

### Check Spawn Parent And Children

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT parent_thread_id, child_thread_id, status
   FROM thread_spawn_edges
   WHERE parent_thread_id = '$THREAD_ID'
      OR child_thread_id = '$THREAD_ID'
   ORDER BY parent_thread_id, child_thread_id;"
```

If this returns a row where `child_thread_id = '$THREAD_ID'`, the thread is a
spawned child.

If the edge table is empty but the DB `source` looks like JSON, inspect source:

```bash
rtk sqlite3 -noheader "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT source FROM threads WHERE id = '$THREAD_ID';"
```

Complex spawned sources can include a structured `subagent.thread_spawn`
payload with `parent_thread_id`, `depth`, and optional agent metadata.

### Check Fork Parent

Use rollout JSONL, not the `threads` table:

```bash
rtk jq -r -s 'map(select(.type == "session_meta") | .payload.forked_from_id // empty)[0]' "$ROLLOUT_PATH"
```

If the command prints a thread ID, this thread was forked from that parent.
If it prints nothing, no fork parent is stored in the rollout header.

### Check First Prompt / First User Message

From DB:

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT first_user_message, preview, title FROM threads WHERE id = '$THREAD_ID';"
```

From rollout:

```bash
rtk jq -r -s '
  [.[] | select(.type == "event_msg" and .payload.type == "user_message") | .payload.message][0] // empty
' "$ROLLOUT_PATH"
```

If the rollout value starts with Codex's internal user-message marker, strip
that marker before comparing it to DB `first_user_message` or app-server
`Thread.preview`.

### Check Current Goal

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/goals_1.sqlite" \
  "SELECT
     thread_id,
     goal_id,
     objective,
     status,
     token_budget,
     tokens_used,
     time_used_seconds,
     datetime(created_at_ms / 1000, 'unixepoch') AS created_at_utc,
     datetime(updated_at_ms / 1000, 'unixepoch') AS updated_at_utc
   FROM thread_goals
   WHERE thread_id = '$THREAD_ID';"
```

Compare that to app-server `thread/goal/get`.

### Check Goal Event History

```bash
rtk jq -s '
  [.[] | select(.type == "event_msg" and .payload.type == "thread_goal_updated") | .payload.goal]
' "$ROLLOUT_PATH"
```

This is event history, not necessarily the current goal.

### Check Dynamic Tools

From DB:

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT position, namespace, name, description, defer_loading, input_schema
   FROM thread_dynamic_tools
   WHERE thread_id = '$THREAD_ID'
   ORDER BY position;"
```

From rollout:

```bash
rtk jq -s 'map(select(.type == "session_meta") | .payload.dynamic_tools // null)[0]' "$ROLLOUT_PATH"
```

### Check Latest Turn Context

```bash
rtk jq -s '
  [.[] | select(.type == "turn_context") | .payload] | last
' "$ROLLOUT_PATH"
```

Compare the result to DB columns:

| Turn context field | DB column |
| --- | --- |
| `model` | `threads.model` |
| `effort` | `threads.reasoning_effort` |
| `cwd` | `threads.cwd` |
| `approval_policy` | `threads.approval_mode` |
| `sandbox_policy` | `threads.sandbox_policy` |
| `realtime_active` | No current DB column; historical context only. |

### Check Token Usage

From rollout:

```bash
rtk jq -s '
  [.[] | select(.type == "event_msg" and .payload.type == "token_count") | .payload.info.total_token_usage.total_tokens] | last
' "$ROLLOUT_PATH"
```

From DB:

```bash
rtk sqlite3 -noheader "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT tokens_used FROM threads WHERE id = '$THREAD_ID';"
```

### Check Stored Turn Markers

```bash
rtk jq -s '
  [.[] | select(.type == "event_msg"
    and (.payload.type == "task_started"
      or .payload.type == "turn_started"
      or .payload.type == "task_complete"
      or .payload.type == "turn_complete"
      or .payload.type == "turn_aborted"))
   | .payload]
' "$ROLLOUT_PATH"
```

This helps reconstruct stored turn state, but it is not proof of current live
state.

### Check Thread Name

From DB:

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT id, title, preview, first_user_message FROM threads WHERE id = '$THREAD_ID';"
```

From sidecar:

```bash
rtk rg --fixed-strings "\"id\":\"$THREAD_ID\"" "$CODEX_HOME/session_index.jsonl"
```

If the same thread appears multiple times in `session_index.jsonl`, the newest
matching line wins.

## App-Server Cross-Check

Use this mapping when comparing app-server output to storage:

| App-server fact | Storage cross-check |
| --- | --- |
| `Thread.id` | `threads.id`; rollout `session_meta.payload.id`; filename UUID suffix. |
| `Thread.path` | `threads.rollout_path`; actual file path. |
| `Thread.source` | rollout `session_meta.payload.source`; DB `threads.source`. |
| `Thread.threadSource` | rollout `session_meta.payload.thread_source`; DB `threads.thread_source`. |
| `Thread.agentNickname` | rollout `agent_nickname`; DB `agent_nickname`. |
| `Thread.agentRole` | rollout `agent_role`; DB `agent_role`. |
| `Thread.agentPath` | rollout `agent_path`; DB `agent_path`. |
| `Thread.forkedFromId` | rollout `forked_from_id`; no current `threads` column. |
| `Thread.preview` | DB `preview`; rollout first preview-capable event. |
| `Thread.name` | DB `title`; `session_index.jsonl`. |
| `Thread.modelProvider` | rollout `model_provider`; DB `model_provider`. |
| `Thread.model` | latest rollout `turn_context.model`; DB `model`. |
| `Thread.reasoningEffort` | latest rollout `turn_context.effort`; DB `reasoning_effort`. |
| `Thread.cwd` | rollout `cwd`; DB `cwd`. |
| `Thread.cliVersion` | rollout `cli_version`; DB `cli_version`. |
| `Thread.gitInfo` | rollout `git`; DB `git_sha`, `git_branch`, `git_origin_url`. |
| `Thread.status` | App-server only for current live state. |
| `Thread.ephemeral` | App-server only; no durable row expected. |
| `Thread.sessionId` | App-server live session tree only; no durable DB column. |
| `thread/goal/get` | `goals_1.sqlite.thread_goals`. |
| `thread/turns/list` | Reconstructed from rollout JSONL, not normalized in `state_5.sqlite`. |

## Common Mismatch Cases

### App-Server Shows Thread, DB Has No Row

Possible explanations:

- The thread is ephemeral.
- The rollout has not materialized yet.
- SQLite backfill is incomplete.
- The app-server has live runtime state ahead of the DB mirror.
- SQLite failed to initialize, and Codex fell back to filesystem scanning.

Check:

```bash
rtk sqlite3 -header -column "$CODEX_SQLITE_HOME/state_5.sqlite" \
  "SELECT status, last_watermark FROM backfill_state WHERE id = 1;"
```

Then search disk by thread ID.

### DB Has Row, App-Server List Does Not Show It

Possible explanations:

- The row is archived and the app-server active list is filtering archived
  threads out.
- The row's `preview` is empty; DB listing filters out empty-preview rows.
- The row uses a source not included by the app-server list source filter.
- The DB path is stale or missing.
- The thread is stored but `notLoaded`, and the app-server UI is only showing
  loaded sessions.

Check `archived`, `source`, `preview`, and `rollout_path`.

### Rollout Exists, DB Has No Row

Possible explanations:

- Backfill is incomplete.
- The rollout has parse errors.
- The state runtime was unavailable.
- The rollout is empty or missing a usable session meta line.

Disk remains the stronger source for history. The DB should repair or backfill
when Codex scans the rollout successfully.

### DB Source Looks Weird

Simple `SessionSource` values are strings. Complex values can be JSON text
because Codex stringifies enum values before storing them.

Examples:

- `cli`
- `vscode`
- `exec`
- `mcp`
- `atlas`
- `chatgpt`
- `{"subagent":{"thread_spawn":{...}}}`

Do not parse `threads.source` with string-prefix checks only. Prefer Codex's
own parser, or use `thread_spawn_edges` for spawned-thread relations.

### Goal Events And Goal DB Disagree

Expected rule:

- Rollout goal events are historical events.
- `goals_1.sqlite.thread_goals` is the current persisted goal row.

If a goal was updated several times, old rollout events will not match the
current goal row.

### Goal DB Has Row, App-Server Cannot Show It

Possible explanations:

- The goal row's `thread_id` is absent from `state_5.sqlite.threads`.
- The thread exists only as stale historical storage.
- The app-server has no standalone goal list API and cannot discover goal rows
  without a current known thread ID.
- The thread is ephemeral, in which case a persisted goal row would be
  unexpected.

Check whether the thread ID exists in `state_5.sqlite.threads`, whether its
`rollout_path` exists, and whether `thread/read` can read the ID directly.

### JSON Mode Cannot Be Found

Expected rule:

- Normal turn `final_output_json_schema` is not stored in rollout
  `TurnContextItem` or `state_5.sqlite.threads`.
- If you need exact JSON-mode proof for a current turn, use app-server/request
  state while the turn is live, or inspect the client call that started it.
- `agent_jobs.output_schema_json` only proves a batch agent job schema.

## Suggested Cross-Check Algorithm

For one thread ID:

1. Ask the app-server for `thread/read` and, if relevant, `thread/loaded/list`.
2. Query `state_5.sqlite.threads` by `id`.
3. Verify `threads.rollout_path` exists.
4. If the DB path is missing, find the rollout by filename under both
   `sessions` and `archived_sessions`.
5. Read rollout `session_meta.payload`.
6. Compare `id`, `source`, `thread_source`, agent fields, cwd, model provider,
   cli version, Git info, and fork parent.
7. Query `thread_spawn_edges` for parent/child relationships.
8. Query `goals_1.sqlite.thread_goals` for current goal state.
9. Use rollout JSONL for message/turn/event history.
10. Treat live status, ephemeral status, realtime current state, and current
    waiting flags as app-server-only facts.

For a list page:

1. Check `backfill_state.status`.
2. Query `threads` with the same archive/source/model/cwd/search filters.
3. Verify each returned `rollout_path` exists.
4. Compare app-server list rows to DB rows by `id`.
5. For mismatches, check whether the app-server list is filtering out archived,
   empty-preview, non-interactive-source, or not-loaded rows.

## Evidence From Upstream Codex

This document is based on the upstream Codex files inspected on
2026-05-29:

- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/lib.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/recorder.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/list.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/metadata.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/state_db.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/search.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/session_index.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/rollout/src/policy.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/lib.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/runtime.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/runtime/threads.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/runtime/goals.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/model/thread_metadata.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/model/thread_goal.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/model/agent_job.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/migrations/*.sql`
- `/Users/aelaguiz/workspace/codex/codex-rs/state/goals_migrations/0001_thread_goals.sql`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/types.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/read_thread.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/list_threads.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/archive_thread.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/unarchive_thread.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/turn_context.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/turn.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/protocol/src/protocol.rs`

## Net

Disk and DB can answer "what was persisted?" and "what metadata did Codex
index?" They cannot answer "is this live right now?" by themselves.

For durable truth, start with the rollout JSONL. For fast metadata and spawn
edges, use `state_5.sqlite`. For current goals, use `goals_1.sqlite`. For live
state, loaded state, ephemeral threads, realtime current state, and exact
JSON-mode turn requests, cross-check with the app-server.

## Live Cross-Check On 2026-05-30

Latest full parity report:

```text
/tmp/codex-client/relay-state-parity-20260530-live-after-cleanup.json
```

Observed durable storage facts:

- `state_5.sqlite.threads` contained 1515 active thread rows.
- 1514 of those rows were app-server-listable.
- 1 row had an empty preview and was outside current app-server list
  discovery:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- `thread_spawn_edges` contained 1189 child edges with current child thread
  rows, and all 1189 matched the relay/app-server spawned-source parent.
- `goals_1.sqlite.thread_goals` contained 165 rows.
- 142 goal rows had matching current thread rows and were visible through
  app-server `thread/goal/get`.
- 23 goal rows pointed at thread IDs absent from `state_5.sqlite.threads`.

Observed mismatch classes:

- 179 storage metadata disagreements between SQLite/current app-server values
  and rollout `session_meta`, mostly `cwd`, `updatedAt`, and git metadata.
- 47 app-server list-row inconsistencies where the same thread returned
  different field values across list scopes.
- 20 read-detail disagreements between app-server read surfaces, rollout
  metadata, or live routed detail.

Meaning:

- Disk/DB proves one true thread exists that app-server cannot enumerate by
  list, even though app-server can read it by known ID.
- Disk/DB also proves current goal rows are not an atomic app-server-listable
  thread-only set, because orphan goal rows exist.
