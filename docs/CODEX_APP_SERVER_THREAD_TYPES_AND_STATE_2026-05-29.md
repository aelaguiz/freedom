---
title: "Codex App-Server Thread Types And State"
date: 2026-05-29
status: active
doc_type: reference
owners: [Amir, Codex]
related:
  - docs/CODEX_DOCK_GOALS_2026-05-29.md
  - docs/CODEX_DOCK_RELAY_THREAD_FIDELITY_WORKLOG_2026-05-29.md
  - docs/CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md
---

# Codex App-Server Thread Types And State

This document answers one question: what can a Codex Dock client know about
Codex sessions, threads, spawned agents, live state, goals, JSON-output turns,
and prompt-started sessions through the app-server protocol?

Short answer: the app-server does not expose one single "thread type" field.
It exposes several smaller facts. A client has to combine those facts:

- `Thread.source` says where the session came from, such as CLI, VS Code,
  app-server, `codex exec`, or a sub-agent.
- `Thread.threadSource` is a separate analytics/source label, such as `user`,
  `subagent`, or `memory_consolidation`.
- `Thread.status` says whether the thread is loaded, idle, active, waiting on
  approval, waiting on user input, or in system error.
- `thread/loaded/list`, `thread/closed`, and `Thread.status.type` are the main
  live-vs-stored signals.
- `thread/goal/get` is the authoritative goal API when the goals feature is
  enabled and the thread is persisted, but it is a read-by-thread-ID API. It is
  not a standalone goal listing API and it does not expose SQLite `goal_id`.
- Turn/item history is where prompt starts, spawned-agent tool calls, JSON-ish
  output, review mode, commands, compaction, and user messages can be inspected.

Related goal source: [Codex Dock Goals](CODEX_DOCK_GOALS_2026-05-29.md).

## Scope

This is app-server focused. It treats these protocol surfaces as the truth a
Dock-style client can use:

- app-server v2 JSON-RPC methods such as `thread/list`, `thread/read`,
  `thread/resume`, `thread/fork`, `thread/loaded/list`, `thread/goal/get`,
  `thread/turns/list`, `turn/start`, and `thread/realtime/*`.
- app-server notifications such as `thread/status/changed`, `thread/started`,
  `thread/closed`, `thread/goal/updated`, `thread/goal/cleared`, `turn/*`, and
  `item/*`.
- app-server `Thread`, `Turn`, and `ThreadItem` payloads.

This document deliberately does not treat private local rollout files, state DB
tables, raw core events, relay-only state, or UI labels as first-class client
truth unless the app-server exposes the same fact.

## Terms

Thread:
: The app-server conversation unit. It has an `id`, can have turns and items,
  can be resumed or forked, and may be persisted on disk.

Session tree:
: A root thread plus spawned descendant threads. Live `Thread.sessionId` is the
  identity shared by threads in the same tree.

Turn:
: One unit of user input and assistant work inside a thread. A turn can be
  `inProgress`, `completed`, `interrupted`, or `failed`.

Item:
: A message or event inside a turn, such as a user message, assistant message,
  command execution, file change, plan update, web search, image generation,
  context compaction, or spawned-agent tool call.

Loaded:
: The app-server currently has runtime state for the thread in memory.

Stored:
: The thread exists in persisted rollout/state history. A stored thread may be
  loaded or not loaded.

Ephemeral:
: The thread is memory-only and should not be materialized on disk. Ephemeral
  threads have `Thread.ephemeral == true`, usually no durable `path`, and do
  not support thread goals.

Archived:
: The stored thread is in the archived collection. App-server list/read
  methods expose this by which list you query, not as a boolean on `Thread`.

## Detection Confidence

Use these confidence levels when designing UI or relay metadata:

| Confidence | Meaning | Example |
| --- | --- | --- |
| Strong | Direct protocol field or method. | `Thread.status.type == "active"` or `Thread.source == { "subAgent": ... }`. |
| Live-only | True only while this app-server process tracks runtime state. | `thread/loaded/list` contains the thread ID. |
| Stored-only | True from persisted history, but may lack live tree facts. | `thread/read` returns a stored thread with `status.notLoaded`. |
| Inference | Plausible from history shape, not explicitly encoded. | First item is a `UserMessage`, so the visible preview probably came from the first prompt. |
| Not exposed | App-server does not reliably answer it after the fact. | Whether an old turn used `turn/start.outputSchema`. |

## Main App-Server Surfaces

| Surface | What it tells you | Important limit |
| --- | --- | --- |
| `thread/list` | Stored threads with status overlay, source filters, archived filter, cwd/search/model filters. | Does not populate `turns`; omitted/empty `sourceKinds` only returns interactive sources; rows without a preview are not listable. |
| `thread/search` | Stored threads plus snippets. | Same kind of stored summary as list. |
| `thread/read` | One thread by ID, optionally with turns. | Reads without resuming. Ephemeral history is not generally available once unloaded. |
| `thread/resume` | Loads or rejoins a thread. | If the thread is already running, app-server rejoins the live thread instead of cold-resuming. |
| `thread/start` | Creates a new thread. | It does not contain a prompt field; user work starts through `turn/start`. |
| `thread/fork` | Creates a fork from another thread. | Forks are relationship/type signals through `forkedFromId`, not separate source types. |
| `thread/loaded/list` | IDs currently loaded in memory. | IDs only; use `thread/read` or subscriptions for details. |
| `thread/unsubscribe` | Removes this connection's subscription. | If it was the last subscriber, unload happens after 30 minutes of no subscribers and no activity. |
| `thread/goal/get` | Current persisted goal for a known thread ID, if any. | Requires goals feature and a persisted thread. Ephemeral threads do not support goals. It does not list all goals and does not expose SQLite `goal_id`. |
| `thread/turns/list` | Paged stored turn history. | Experimental; full item hydration is limited by `itemsView`. |
| `turn/start` | Starts a turn, optionally with `outputSchema`. | The schema is a turn request setting; it is not a durable `Thread` field. |
| `thread/realtime/*` | Realtime session actions and notifications. | Realtime active state is not a durable `Thread` summary field. |

Live event note:

- `thread/start`, `thread/resume`, and `thread/fork` auto-subscribe the
  connection to turn/item events for the returned thread.
- `thread/unsubscribe` removes that connection's subscription.
- A client that wants live state should treat the response plus following
  `thread/*`, `turn/*`, and `item/*` notifications as one stream of evidence.

## Canonical Thread Fields

The v2 `Thread` object is the main row shape:

| Field | Meaning | Detection note |
| --- | --- | --- |
| `id` | Concrete thread ID. | Stable thread identity. |
| `sessionId` | Session-tree ID shared by root and descendants. | Strong for live snapshots. Stored summaries may fall back to `id` because stored metadata does not always carry the live tree ID. |
| `forkedFromId` | Source thread ID when created by `thread/fork` or a fork-like spawn path. | Strong fork relation when present. |
| `preview` | Usually first user message. | Useful but not proof of how the thread was launched. |
| `ephemeral` | Whether the thread is memory-only. | Strong signal. |
| `modelProvider` | Provider such as `openai`. | Summary metadata, not thread type. |
| `createdAt` | Unix seconds when created. | Use for age, not live status. |
| `updatedAt` | Unix seconds when last updated. | Use for recency, not live status. |
| `status` | Runtime status. | Primary loaded/active/idle/error signal. |
| `path` | Unstable path to persisted rollout. | `null` is common for ephemeral threads. Do not build product logic that depends only on path format. |
| `cwd` | Working directory. | Useful for grouping and filters. |
| `cliVersion` | Codex version that created it. | Metadata only. |
| `source` | Runtime/product origin. | Main type/origin field. |
| `threadSource` | Optional analytics source classification. | Separate from `source`; values are `user`, `subagent`, `memory_consolidation`. |
| `agentNickname` | Nickname for AgentControl-spawned sub-agent. | Only some sub-agents have it. |
| `agentRole` | Role for AgentControl-spawned sub-agent. | Only some sub-agents have it. |
| `gitInfo` | Optional Git SHA/branch/origin. | Metadata only. |
| `name` | Optional user-facing title. | Not a type. |
| `turns` | Included turn list. | Empty except for `thread/resume`, `thread/rollback`, `thread/fork`, and `thread/read` with `includeTurns: true`. |

## Lifecycle And Live State

The app-server `Thread.status` union is:

```ts
{ "type": "notLoaded" }
{ "type": "idle" }
{ "type": "systemError" }
{ "type": "active", "activeFlags": [...] }
```

`activeFlags` can contain:

- `waitingOnApproval`
- `waitingOnUserInput`

### `notLoaded`

Meaning:

- The thread is not currently tracked as loaded in the app-server runtime.
- It may still be stored on disk and readable through `thread/read`.
- It may be old, but "old" is not the actual state. The real state is "not
  loaded".

Good UI wording:

- Stored
- Not loaded
- Older stored session

Bad UI assumption:

- "Dead", "closed forever", or "failed". A `notLoaded` thread can often be
  resumed.

How to detect:

- `Thread.status.type == "notLoaded"`.
- The ID is absent from `thread/loaded/list`.
- `thread/closed` was observed for the ID on the current connection.

### `idle`

Meaning:

- The thread is loaded in memory.
- It is not running a turn.
- It has no pending approval request and no pending user-input request.
- It is not currently marked as system error.

How to detect:

- `Thread.status.type == "idle"`.
- The ID should normally be present in `thread/loaded/list`.

Important nuance:

- Idle is live memory state, not proof that the user is looking at it or that
  the thread has subscribers. The app-server does not expose subscriber count
  in the `Thread` object.

### `active`

Meaning:

- The app-server thinks work is in flight, or there is a pending request that
  keeps the thread active.
- `activeFlags` tells you whether the activity needs a human.

How to detect:

- `Thread.status.type == "active"`.
- `activeFlags` empty means active but not currently waiting on approval/user
  input.
- `activeFlags` containing `waitingOnApproval` means a command/tool approval
  request is pending.
- `activeFlags` containing `waitingOnUserInput` means a request-user-input style
  prompt is pending.

Important nuance:

- Stored history can contain a stale `inProgress` turn from a crashed or old
  process. App-server read/list code tries to resolve this by preferring live
  active state when available and interrupting stale in-progress turns when the
  thread is no longer active.

### Waiting Flags And Server Requests

The two `activeFlags` are derived from pending server requests.

`waitingOnApproval` can be caused by app-server sending approval-style
server requests such as:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`
- `mcpServer/elicitation/request`, when handled as a permission-style pending
  request by the app-server runtime.

`waitingOnUserInput` can be caused by:

- `item/tool/requestUserInput`

How a client should use this:

- Treat `activeFlags` as the summary signal for row/status UI.
- Treat the actual server request payload as the action surface the user must
  answer.
- Listen for `serverRequest/resolved` and `thread/status/changed` to know when
  the pending request has cleared.
- Do not infer the exact request only from the flag. The flag says the thread
  is waiting; the server request says what it is waiting for.

### `systemError`

Meaning:

- The loaded runtime facts for this thread recorded a system error.
- This is stronger than "turn failed"; it is a thread-level runtime state.

How to detect:

- `Thread.status.type == "systemError"`.
- Listen for `thread/status/changed`.

### `thread/closed`

`thread/closed` is a runtime unload notification.

The normal close path is:

1. A connection unsubscribes with `thread/unsubscribe`.
2. If that was the last subscriber, the server keeps the thread loaded for a
   grace period.
3. After 30 minutes with no subscribers and no activity, app-server unloads it.
4. App-server emits `thread/status/changed` to `notLoaded` and then
   `thread/closed`.

This means `closed` is not an archived/deleted state. It means the loaded
runtime object was unloaded.

## Live Vs Stored Vs Old

Use this decision tree:

1. Call `thread/loaded/list`.
2. If the ID is present, the thread is live in app-server memory.
3. Read or list the thread and inspect `Thread.status`.
4. If `status.type == "active"`, work or a pending human request is active.
5. If `status.type == "idle"`, it is live but idle.
6. If `status.type == "systemError"`, it is live but errored.
7. If the ID is absent from `thread/loaded/list` and `status.type == "notLoaded"`,
   it is stored-only from this app-server's point of view.
8. Use `updatedAt` and `createdAt` to decide whether to call it "old" in UI.

Do not conflate these:

| Question | Correct signal | Not enough by itself |
| --- | --- | --- |
| Is it live in memory? | `thread/loaded/list` plus `Thread.status`. | `updatedAt` recentness. |
| Is it old? | Age from `updatedAt`/`createdAt`. | `notLoaded` alone. |
| Is it active? | `Thread.status.type == "active"`. | A persisted turn that says `inProgress`. |
| Is it waiting on me? | `activeFlags` includes `waitingOnApproval` or `waitingOnUserInput`. | `active` with empty flags. |
| Is it archived? | Returned from `thread/list` with `archived: true`. | `Thread.status`. |
| Is it persisted? | `ephemeral == false`, usually with a `path`, plus successful stored read/list. | Loaded state. |
| Is it memory-only? | `ephemeral == true`. | Missing `path` alone. |

## Archived Threads

Archived is not a field on `Thread`.

How to detect:

- Query `thread/list` with `archived: true` to list archived threads.
- Query `thread/list` with `archived: false` or omit archived, depending client
  intent, to list active stored threads.
- Listen for `thread/archived` and `thread/unarchived`.

Important spawned-agent behavior:

- `thread/archive` archives the selected thread.
- If state DB spawn edges are available, app-server also tries to archive
  spawned descendants.
- The internal table is `thread_spawn_edges(parent_thread_id, child_thread_id,
  status)`, but app-server does not expose a direct "give me this full spawn
  tree" API in the thread summary protocol.

## Thread Source Taxonomy

`Thread.source` is the main origin/type field.

The v2 TypeScript shape is:

```ts
type SessionSource =
  | "cli"
  | "vscode"
  | "exec"
  | "appServer"
  | { "custom": string }
  | { "subAgent": SubAgentSource }
  | "unknown";
```

The generated core `SubAgentSource` shape used inside the app-server source is:

```ts
type SubAgentSource =
  | "review"
  | "compact"
  | {
      "thread_spawn": {
        parent_thread_id: ThreadId,
        depth: number,
        agent_path: AgentPath | null,
        agent_nickname: string | null,
        agent_role: string | null
      }
    }
  | "memory_consolidation"
  | { "other": string };
```

### Interactive Human-ish Roots

These are the sources the app-server treats as the default interactive list:

- `source == "cli"`
- `source == "vscode"`
- `source == { "custom": "atlas" }`
- `source == { "custom": "chatgpt" }`

Important list behavior:

- `thread/list` with omitted `sourceKinds` defaults to those interactive
  sources.
- `thread/list` with `sourceKinds: []` also defaults to those interactive
  sources.
- `ThreadSourceKind` does not have a general custom-source filter, so custom
  sources like `atlas` and `chatgpt` are included by default interactive
  behavior, not by explicit `sourceKinds` values.

Human/user-created confidence:

- Strong negative: if `source` is `{ "subAgent": ... }`, it is not a human root.
- Strong-ish positive: if `source` is `cli`, `vscode`, or custom `atlas` /
  `chatgpt`, it is an interactive root from app-server's list perspective.
- Weaker positive: `threadSource == "user"` can reinforce this, but
  `threadSource` is optional and analytics-oriented.
- Not exposed: app-server does not prove "a human clicked New Session" as a
  durable type.

### `exec`

Meaning:

- The thread came from `codex exec`.
- It is automation/non-interactive by origin.

How to detect:

- `Thread.source == "exec"`.
- Or list/search with `sourceKinds: ["exec"]`.

### `appServer`

Meaning:

- Core source `Mcp` is rendered to app-server clients as `appServer`.
- Threads created through app-server can appear this way depending the
  manager's default source and launch path.

How to detect:

- `Thread.source == "appServer"`.
- Or list/search with `sourceKinds: ["appServer"]`.

Important nuance:

- `thread/start` has no client-supplied `sessionSource` field. It has
  `sessionStartSource`, but that only selects startup vs clear initial history.
  The runtime `source` comes from core/session manager configuration.

### `custom`

Meaning:

- The core session source was `Custom(String)`.
- Known interactive defaults include `atlas` and `chatgpt`.

How to detect:

- `Thread.source == { "custom": "<value>" }`.

Limit:

- `ThreadSourceKind` has no custom value. To find arbitrary custom sources, a
  client may need broader listing plus client-side filtering.
- Upstream's current default interactive set is exactly `cli`, `vscode`,
  custom `atlas`, and custom `chatgpt`. Other custom sources can exist, but
  they are not in that default interactive set unless upstream changes the
  constant.

### `unknown`

Meaning:

- The app-server could not or would not render a more specific source.
- Core internal sources are intentionally mapped to app-server `unknown`.

Important filter nuance:

- A response source of `unknown` can hide core internal source details.
- `sourceKinds: ["unknown"]` matches core `Unknown`, not necessarily every core
  `Internal(...)` source that later renders as app-server `unknown`.

Use `unknown` cautiously in UI. "Unknown source" is honest; "user session" is
not.

## ThreadSource Taxonomy

`Thread.threadSource` is not the same as `Thread.source`.

Values:

- `user`
- `subagent`
- `memory_consolidation`

How to use it:

- Treat it as an analytics/source classification.
- Clients can optionally send `threadSource` on `thread/start` and
  `thread/fork`. Stored/resumed threads can also carry prior `threadSource`
  metadata.
- Use it with `Thread.source`, not instead of `Thread.source`.
- For spawned agents, `source.subAgent` is the stronger signal.
- For user/root sessions, `threadSource == "user"` is helpful when present but
  may be absent.

## User-Created Vs Spawned Sessions

There is no single `createdByUser: true` field.

Use this practical classification:

| Classification | Strong signals | Caveats |
| --- | --- | --- |
| User-created or interactive root | `source` is `cli`, `vscode`, `{ "custom": "atlas" }`, or `{ "custom": "chatgpt" }`; `threadSource` is `user` or `null`; `forkedFromId == null`; not `subAgent`. | Does not prove the exact UI action that created it. |
| App-server/API-created root | `source == "appServer"` or source consistent with the app-server runtime, no sub-agent source, no parent. | App-server does not expose the external caller identity as a durable field. |
| `codex exec` root | `source == "exec"`. | Could still have user-authored prompt content, but the origin is exec. |
| Spawned agent | `source == { "subAgent": ... }`, especially `thread_spawn`; `threadSource == "subagent"`; parent has `CollabAgentToolCall` item with child ID. | Some sub-agent variants are review/compact/other and may not have nickname/role. |
| Forked thread | `forkedFromId != null`. | Forking is a relationship, not necessarily human vs agent. |
| Internal/memory consolidation | `threadSource == "memory_consolidation"`, `source.subAgent == "memory_consolidation"`, or app-server `unknown` for hidden core internal source. | Internal source detail may be intentionally hidden. |

## Spawned Agent Threads

A spawned agent can be detected in several layers.

Strong thread-level signals:

- `Thread.source` is `{ "subAgent": ... }`.
- `Thread.source.subAgent` is `{ "thread_spawn": { ... } }`.
- `Thread.threadSource == "subagent"`.
- `Thread.agentNickname` or `Thread.agentRole` is present.

Strong parent/child signals:

- Parent turn history contains a `CollabAgentToolCall` item.
- The item has `tool`, `senderThreadId`, `receiverThreadIds`, `prompt`,
  `model`, `reasoningEffort`, and `agentsStates`.
- For spawn operations, `receiverThreadIds` are the newly spawned agent thread
  IDs.

Default list caveat:

- Spawned sub-agent threads are not part of the default interactive
  `thread/list` / `thread/search` result set.
- To list them, request a source kind such as `subAgent`,
  `subAgentThreadSpawn`, `subAgentReview`, `subAgentCompact`, or
  `subAgentOther`.

`CollabAgentToolCall.tool` values:

- `spawnAgent`
- `sendInput`
- `resumeAgent`
- `wait`
- `closeAgent`

`CollabAgentToolCall.status` values:

- `inProgress`
- `completed`
- `failed`

Per-agent status values inside `agentsStates`:

- `pendingInit`
- `running`
- `interrupted`
- `completed`
- `errored`
- `shutdown`
- `notFound`

Sub-agent operation meanings:

- `spawnAgent` creates a child agent thread; receiver IDs identify the child
  threads.
- `sendInput` sends more input to an existing child agent.
- `resumeAgent` resumes an existing child agent.
- `wait` waits for one or more child agents and reports their latest states.
- `closeAgent` shuts down or closes child agents from the parent side.

Interactive vs one-shot spawned agents:

- Core has an interactive spawned-agent path that creates the child thread and
  lets later parent operations send input.
- Core also has a one-shot path that creates the child thread and immediately
  submits initial `UserInput`.
- Through app-server thread summaries, both are still sub-agent threads. The
  reliable detection remains `source.subAgent`, `threadSource`, parent
  `CollabAgentToolCall`, child IDs, and child turn history.
- If the one-shot path used a final output schema, it follows the same JSON
  rule as normal turns: it is strong only if the current client observed the
  request/schema; it is not a durable `Thread` field.

### Thread-Spawn Sub-Agent

This is the richest sub-agent source:

```json
{
  "subAgent": {
    "thread_spawn": {
      "parent_thread_id": "parent-thread-id",
      "depth": 1,
      "agent_path": null,
      "agent_nickname": "optional-nickname",
      "agent_role": "optional-role"
    }
  }
}
```

What it tells you:

- `parent_thread_id` gives the parent thread.
- `depth` gives spawn depth.
- `agent_path` can identify a canonical agent path when present.
- `agent_nickname` and `agent_role` may also be lifted into top-level
  `Thread.agentNickname` and `Thread.agentRole`.

### Review Sub-Agent

How to detect:

- `Thread.source == { "subAgent": "review" }`.
- Or list with `sourceKinds: ["subAgentReview"]`.

Meaning:

- The thread was created for review work.

### Compact Sub-Agent

How to detect:

- `Thread.source == { "subAgent": "compact" }`.
- Or list with `sourceKinds: ["subAgentCompact"]`.

Meaning:

- The thread was created for compaction/summarization-style work.

### Memory-Consolidation Sub-Agent

How to detect:

- `Thread.source == { "subAgent": "memory_consolidation" }`, when exposed.
- Or `Thread.threadSource == "memory_consolidation"`.

Limit:

- Core internal memory-consolidation sources can be mapped to app-server
  `unknown`, so not every memory-consolidation path is cleanly visible as a
  sub-agent source.

### Other Sub-Agent

How to detect:

- `Thread.source == { "subAgent": { "other": "<value>" } }`.
- Or list with `sourceKinds: ["subAgentOther"]`.

Known example:

- Agent-job worker threads can use `SubAgentSource::Other("agent_job:<job_id>")`
  internally.

Limit:

- App-server does not provide a specialized `agentJobId` field on `Thread`.
  Treat the string as source metadata, not a stable public schema unless the
  protocol documents it later.

## Forked Threads

A fork is a new thread created from another thread's history.

How to detect:

- `Thread.forkedFromId != null`.
- `thread/fork` response returns the new forked thread.

Important behavior:

- If the source thread is mid-turn, app-server forks an interrupted snapshot so
  the fork does not contain an unmarked partial suffix.
- `thread/fork` accepts `ephemeral: true`, so a fork can be memory-only.
- Forking is independent from user/spawned classification. A human can fork;
  an agent path can also create fork-like descendants through core spawn logic.

## Resumed Threads

Resume is a loading action, not a new thread type.

How to detect:

- You observed a successful `thread/resume`.
- The same `Thread.id` becomes loaded/idle/active.
- `thread/status/changed` may follow.

Important behavior:

- `thread/resume` can resume by `threadId`, history, or path.
- If `threadId` identifies a currently running thread, app-server rejoins that
  live thread instead of making a cold copy.
- For non-running lookup, app-server gives precedence to history, then
  non-empty path, then `threadId`.
- If app-server says the thread is closing, the exact failure can be
  `thread <id> is closing; retry after the thread is closed` or
  `thread <id> is closing; retry thread/resume after the thread is closed`.

## Ephemeral Threads

How to detect:

- `Thread.ephemeral == true`.
- Usually `Thread.path == null`.

Meaning:

- The thread should not be materialized on disk.
- It is a runtime/session object, not durable history.

Limits:

- Thread goals require a persisted thread; ephemeral threads do not support
  goals.
- Stored history APIs are limited or unavailable after an ephemeral thread is
  gone.

## Goals

Goals are thread-scoped persisted objectives.

Authoritative API:

- `thread/goal/get`
- `thread/goal/set`
- `thread/goal/clear`
- `thread/goal/updated`
- `thread/goal/cleared`

Goal statuses:

- `active`
- `paused`
- `blocked`
- `usageLimited`
- `budgetLimited`
- `complete`

Goal fields:

- `threadId`
- `objective`
- `status`
- `tokenBudget`
- `tokensUsed`
- `timeUsedSeconds`
- `createdAt`
- `updatedAt`

Not exposed through app-server goal APIs:

- SQLite `goal_id`.
- A standalone list of every row in `goals_1.sqlite.thread_goals`.

### How To Tell If A Goal Is Running

There is no single perfect `goalIsCurrentlyExecuting` field.

Use this rule:

| Goal API result | Thread status | Meaning |
| --- | --- | --- |
| No goal | Any | No app-server goal exists, or goals are unsupported/disabled. |
| Goal `active` | `active` | A goal exists and the thread currently has active work or a pending request. This is the strongest "goal is running or blocked on interaction" signal. |
| Goal `active` | `idle` | A goal exists but no turn is running right now. Runtime may auto-continue when eligible. |
| Goal `active` | `notLoaded` | A persisted active goal exists, but this app-server is not currently running the thread. Resume may re-emit goal state and continue if eligible. |
| Goal `paused` | Any | A goal exists but should not auto-run. |
| Goal `blocked` | Any | A goal exists and is blocked. |
| Goal `budgetLimited` | Any | Goal hit token budget accounting. |
| Goal `usageLimited` | Any | Goal hit usage limits. |
| Goal `complete` | Any | Goal is done. |

Auto-continuation constraints from core:

- Plan mode ignores goal continuation.
- The thread must be persisted, not ephemeral.
- There must be no active turn.
- There must be no queued user input or trigger-turn mailbox work.
- The goal status must be `active`.
- Runtime needs a state DB for goal storage.

Important API limits:

- If the goals feature is disabled, the goal methods fail with
  `goals feature is disabled`.
- If the thread is ephemeral, goal APIs fail because goals require a persisted
  thread.
- `thread/goal/get` needs a known, materialized thread ID. It cannot discover
  orphan rows that exist in `goals_1.sqlite` but have no current
  `state_5.sqlite.threads` row.
- The model-facing tools can mark a goal `complete` or `blocked`; statuses
  like paused, usage-limited, and budget-limited are controlled by app/server
  policy or external mutation.
- Goal counters and status can change while a thread is running. For an audit,
  treat goal comparisons as non-atomic unless the app-server is quiesced or
  the API provides one snapshot of thread and goal state together.

## Started With A Prompt

There is no durable `startedWithPrompt` field.

Important protocol shape:

- `thread/start` creates the thread.
- `turn/start` sends user input.
- `thread/start` has `sessionStartSource`, but it only supports `startup` and
  `clear`. It does not say "prompt was included at launch".

What a client can know:

- If the first turn contains a `UserMessage`, the thread has user prompt
  content.
- `Thread.preview` is usually the first user message.
- `thread/read` with `includeTurns: true` can show the first turn and first
  user message when persisted history is available.
- `thread/turns/list` can page turn history and inspect first user-message
  content depending `itemsView`.

What a client cannot prove after the fact:

- Whether the frontend created the thread and immediately sent a prompt in one
  user action.
- Whether a thread was created empty and the first prompt arrived later.

Only live instrumentation can prove that distinction, for example observing
`thread/start` and the first `turn/start` together with timing/client metadata.

## JSON Mode / Structured Output Turns

There is no durable "JSON mode session" type in the app-server `Thread`.

The real protocol mechanism is turn-scoped:

- `turn/start.outputSchema` is an optional JSON Schema.
- App-server passes it to core as `final_output_json_schema`.
- Core uses it to constrain the final assistant message for that turn.

What is detectable:

- Strong while sending/observing the request: the client knows it included
  `turn/start.outputSchema`.
- Strong in app-server request logs only if those logs were intentionally and
  safely captured outside normal thread summaries.

What is not reliably detectable later through thread APIs:

- `Thread` has no `jsonMode` or `outputSchema` field.
- `Turn` summaries do not include `outputSchema`.
- Persisted `TurnContextItem` records model, cwd, approval, sandbox,
  collaboration mode, realtime active, effort, and summary, but not
  `final_output_json_schema`.
- Content may look like JSON, but that is only an inference.

Practical UI rule:

- Say "structured-output turn" only when the current client observed
  `outputSchema` on `turn/start`.
- For old sessions, say "assistant output appears to be JSON" if you only infer
  from content.

## Realtime Threads

Realtime is thread-scoped, but not a durable thread type.

App-server methods and notifications:

- `thread/realtime/start`
- `thread/realtime/appendAudio`
- `thread/realtime/appendText`
- `thread/realtime/stop`
- `thread/realtime/listVoices`
- `thread/realtime/started`
- `thread/realtime/sdp`
- `thread/realtime/itemAdded`
- `thread/realtime/transcript/delta`
- `thread/realtime/transcript/done`
- `thread/realtime/outputAudio/delta`
- `thread/realtime/error`
- `thread/realtime/closed`

What is detectable:

- Strong live signal if the client observes realtime notifications or owns the
  request/response flow.
- Persisted turn context can include `realtime_active`, but `Thread` summaries
  do not expose a stable realtime-active boolean.

## Notification Index For Thread State

Notifications are how a subscribed app-server connection learns live changes.
This is the thread-relevant catalog to know about when building state UI.

Thread lifecycle and metadata:

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
- `thread/compacted` is deprecated; prefer `ContextCompaction` items.

Turn lifecycle:

- `turn/started`
- `turn/completed`
- `turn/diff/updated`
- `turn/plan/updated`

Item lifecycle and item streams:

- `item/started`
- `item/completed`
- `item/agentMessage/delta`
- `item/plan/delta`
- `item/commandExecution/outputDelta`
- `item/commandExecution/terminalInteraction`
- `item/fileChange/outputDelta`
- `item/fileChange/patchUpdated`
- `item/mcpToolCall/progress`
- `item/reasoning/summaryTextDelta`
- `item/reasoning/summaryPartAdded`
- `item/reasoning/textDelta`
- `item/autoApprovalReview/started`
- `item/autoApprovalReview/completed`
- `rawResponseItem/completed` is internal-only for Codex Cloud style raw events.

Server-request lifecycle:

- `serverRequest/resolved`

Realtime notifications:

- `thread/realtime/started`
- `thread/realtime/itemAdded`
- `thread/realtime/transcript/delta`
- `thread/realtime/transcript/done`
- `thread/realtime/outputAudio/delta`
- `thread/realtime/sdp`
- `thread/realtime/error`
- `thread/realtime/closed`

Related support notifications that may matter for diagnostics but are not
thread types:

- `error`
- `warning`
- `guardianWarning`
- `deprecationNotice`
- `configWarning`
- `skills/changed`
- `model/rerouted`
- `model/verification`
- `mcpServer/oauthLogin/completed`
- `mcpServer/startupStatus/updated`
- `account/updated`
- `account/rateLimits/updated`
- `app/list/updated`
- `remoteControl/status/changed`
- `externalAgentConfig/import/completed`
- `fs/changed`
- `fuzzyFileSearch/sessionUpdated`
- `fuzzyFileSearch/sessionCompleted`
- `command/exec/outputDelta`
- `process/outputDelta`
- `process/exited`
- `windows/worldWritableWarning`
- `windowsSandbox/setupCompleted`
- `account/login/completed`

Opt-out note:

- Clients can suppress specific notifications per connection using
  `initialize.params.capabilities.optOutNotificationMethods`.
- Opt-out is exact-match by method name.
- Suppressing notifications can make local live-state reconstruction weaker, so
  keep lifecycle notifications enabled unless the client has another source of
  truth.

## Turn States

Turn status values:

- `inProgress`
- `completed`
- `interrupted`
- `failed`

How to use them:

- Use `Thread.status` for current thread runtime state.
- Use `Turn.status` for individual turn history.
- If a stored old turn says `inProgress`, check live thread status before
  showing it as currently running.
- `Turn.itemsView` tells how much item data is present:
  - `notLoaded`: `items` were intentionally not included.
- `summary`: only summary items are included.
- `full`: every available app-server history item is included.

Failed-turn error fields:

- When `Turn.status == "failed"`, `Turn.error` can be populated.
- `Turn.error.message` is the user-facing error string.
- `Turn.error.codexErrorInfo` is an optional structured error code.
- `Turn.error.additionalDetails` is optional extra detail.

`CodexErrorInfo` values:

- `contextWindowExceeded`
- `usageLimitExceeded`
- `serverOverloaded`
- `cyberPolicy`
- `httpConnectionFailed` with optional `httpStatusCode`
- `responseStreamConnectionFailed` with optional `httpStatusCode`
- `internalServerError`
- `unauthorized`
- `badRequest`
- `threadRollbackFailed`
- `sandboxError`
- `responseStreamDisconnected` with optional `httpStatusCode`
- `responseTooManyFailedAttempts` with optional `httpStatusCode`
- `activeTurnNotSteerable` with `turnKind`
- `other`

Common turn/item facts:

- A first `UserMessage` gives the first user-visible prompt.
- `HookPrompt` is hook-injected prompt content, not the same thing as a user
  starting a thread with a prompt.
- An `AgentMessage` gives assistant output.
- `Plan` shows plan text.
- `Reasoning` shows reasoning summary/content when exposed.
- `CommandExecution` shows shell/tool execution.
- `FileChange` shows edits.
- `McpToolCall` and `DynamicToolCall` show tool use.
- `CollabAgentToolCall` shows spawned-agent coordination.
- `WebSearch` shows web-search query/action.
- `ImageView` shows an image path viewed by the model.
- `ImageGeneration` shows image-generation status/result fields.
- `EnteredReviewMode` and `ExitedReviewMode` show review mode transitions.
- `ContextCompaction` shows compaction happened.

## Thread-Scoped Operations That Are Not Thread Types

Several app-server methods change a thread, its next turn, or its history, but
they should not be shown as separate thread types.

| Operation | What it changes | Not a type because |
| --- | --- | --- |
| `thread/settings/update` | Queues next-turn settings for a loaded thread and may emit `thread/settings/updated`. | It changes effective settings, not origin/lifecycle. |
| `turn/start` settings overrides | Can update model, effort, cwd, permissions, sandbox, personality, collaboration mode, and related next-turn settings. | These are turn/runtime settings, not durable source. |
| `thread/memoryMode/set` | Sets persisted memory eligibility to `enabled` or `disabled`. | Memory eligibility is metadata, not live state. |
| `memory/reset` | Clears local memory artifacts and memory-stage state for Codex home. | It is global memory maintenance, not a thread state. |
| `thread/name/set` | Sets user-facing thread title. | Name is label metadata. |
| `thread/metadata/update` | Patches stored metadata such as `gitInfo`. | Metadata is not origin or lifecycle. |
| `thread/compact/start` | Starts compaction; progress appears through normal turn/item notifications. | Compaction is an operation; `ContextCompaction` items are history evidence. |
| `thread/rollback` | Drops the last N turns from in-memory context and persists a rollback marker; response includes populated `turns`. | Rollback changes history shape, not source. |
| `review/start` | Runs automated review on a thread and emits review-mode items plus final assistant output. | It is a turn-like operation, separate from `source.subAgent == "review"`. |
| `thread/shellCommand` | Runs a user-initiated `!` shell command against the thread. | It streams command output, but does not make the thread an exec-origin thread. |
| `thread/backgroundTerminals/clean` | Terminates running background terminals for the thread. | Cleanup action only. |
| `thread/inject_items` | Appends raw Responses API items to loaded model-visible history. | It changes model context without creating a user turn. |
| `turn/steer` | Adds input to an in-flight regular turn. | Same turn remains active; no new thread type. |
| `turn/interrupt` | Requests cancellation of an in-flight turn; completed turn status becomes `interrupted`. | It affects a turn status, not thread source. |
| `thread/increment_elicitation` / `thread/decrement_elicitation` | Adjusts an out-of-band elicitation counter and returns `paused` for timeout accounting. | This `paused` is not `Thread.status` and not goal status `paused`. |

This distinction matters for UI. A thread can be `source == "cli"` and also
have review-mode items, a shell command, a rollback marker, and compacted
history. Those are activity/history facts, not the thread's origin.

### Plan And Collaboration Mode

Plan mode matters because active goals do not auto-continue in plan mode.

What app-server exposes:

- `thread/settings/updated` includes `ThreadSettings.collaborationMode` for a
  loaded thread when effective next-turn settings change.
- `thread/settings/update` and `turn/start` can change collaboration mode when
  the client has the experimental capability.
- The client knows the mode if it sent the mode or observed the settings
  notification.
- `CollaborationMode.mode` values are `default` and `plan`.
- `CollaborationMode.settings` carries the settings object for that mode.

What is not a normal thread summary field:

- `Thread` does not include `collaborationMode`.
- `Turn` does not expose a durable `outputSchema` or full raw
  `TurnContextItem`.
- Raw persisted rollout `TurnContextItem` includes `collaboration_mode`, but a
  Dock client should not treat that private rollout detail as app-server API
  unless a protocol method exposes it.

## SourceKinds For Listing And Search

`ThreadSourceKind` values:

```ts
type ThreadSourceKind =
  | "cli"
  | "vscode"
  | "exec"
  | "appServer"
  | "subAgent"
  | "subAgentReview"
  | "subAgentCompact"
  | "subAgentThreadSpawn"
  | "subAgentOther"
  | "unknown";
```

Filtering rules:

- Omitted `sourceKinds` means interactive defaults:
  `cli`, `vscode`, custom `atlas`, custom `chatgpt`.
- Empty `sourceKinds: []` also means those interactive defaults.
- `subAgent` matches any core sub-agent source.
- `subAgentReview`, `subAgentCompact`, `subAgentThreadSpawn`, and
  `subAgentOther` match those specific sub-agent variants.
- `appServer` matches core `Mcp`.
- `unknown` matches core `Unknown`.

Important caveat:

- Because app-server maps core `Internal(_)` to response `unknown`, a response
  can show `source: "unknown"` even when the source was intentionally hidden.
  But the `unknown` source-kind filter itself matches core `Unknown`, not every
  hidden internal source.

## List And Search Parameters

`thread/list` and `thread/search` are the main stored-thread discovery APIs.

Important listability limit:

- `thread/list` filters out rows with an empty preview. A thread can be
  directly readable by `thread/read` if the caller already knows the ID, while
  still being absent from every `thread/list` page.

`thread/list` parameters:

| Parameter | Meaning |
| --- | --- |
| `cursor` | Opaque pagination cursor from a previous response. |
| `limit` | Optional page size. |
| `sortKey` | `created_at` or `updated_at`; defaults to `created_at`. |
| `sortDirection` | `asc` or `desc`; defaults to descending/newest-first. |
| `modelProviders` | Optional provider filter; present-but-empty means all providers. |
| `sourceKinds` | Optional source filter; omitted or empty means interactive defaults. |
| `archived` | `true` lists archived threads; `false` or `null` lists non-archived threads. |
| `cwd` | One path string or an array of path strings; matches exact session cwd. |
| `useStateDbOnly` | If true, uses state DB without scanning JSONL rollouts to repair metadata. |
| `searchTerm` | Optional substring filter for extracted thread title. |

`thread/search` parameters:

| Parameter | Meaning |
| --- | --- |
| `cursor` | Opaque pagination cursor from a previous response. |
| `limit` | Optional page size. |
| `sortKey` | `created_at` or `updated_at`; defaults to `created_at`. |
| `sortDirection` | `asc` or `desc`; defaults to descending/newest-first. |
| `sourceKinds` | Optional source filter; omitted or empty means interactive defaults. |
| `archived` | `true` searches archived threads; `false` or `null` searches non-archived threads. |
| `searchTerm` | Required substring/full-text query. |

List/search response cursors:

- `nextCursor` continues after the last item in the current page.
- `backwardsCursor` is populated when a page has at least one thread.
- Use `backwardsCursor` with the opposite `sortDirection`; for timestamp sorts,
  it anchors at the start timestamp so same-second updates are not skipped.

## Recipes

### Is This Session Live Or Old?

1. Call `thread/loaded/list`.
2. If the thread ID is listed, it is loaded in memory.
3. Read/list the thread.
4. Interpret `Thread.status`.
5. If the ID is not listed and `status.type == "notLoaded"`, call it
   stored/not-loaded.
6. Use `updatedAt` to decide whether it is old by time.

Recommended UI labels:

- `active`: live and working or waiting.
- `waiting for approval`: active plus `waitingOnApproval`.
- `waiting for input`: active plus `waitingOnUserInput`.
- `idle`: live but no turn running.
- `stored`: not loaded but persisted.
- `archived`: appears in archived list.
- `ephemeral`: memory-only, if still visible.

### Was This Created By A User?

Use strongest-to-weakest evidence:

1. If `source` is `{ "subAgent": ... }`, no.
2. If `source == "exec"`, it is exec-origin, not interactive UI-origin.
3. If `source == "cli"`, `source == "vscode"`, or `source.custom` is `atlas`
   or `chatgpt`, treat it as an interactive root.
4. If `threadSource == "user"`, that supports user/root classification.
5. If `forkedFromId != null`, also label it forked.

Do not claim app-server proves the exact UI gesture.

### Was This Spawned By An Agent?

Check:

1. `Thread.source` is `{ "subAgent": ... }`.
2. `Thread.threadSource == "subagent"`.
3. `Thread.source.subAgent.thread_spawn.parent_thread_id` exists.
4. Parent history has `CollabAgentToolCall` where `receiverThreadIds` contains
   this thread ID.
5. `agentNickname` or `agentRole` exists.

The strongest parent ID is the one in `thread_spawn.parent_thread_id` and/or
the parent `CollabAgentToolCall.senderThreadId`.

### Is A Goal Running?

1. Call `thread/goal/get`.
2. If there is no goal, no goal is running.
3. If goal status is not `active`, it is not currently supposed to run.
4. If goal status is `active`, inspect `Thread.status`.
5. `active` goal plus `active` thread is the best "running now" signal.
6. `active` goal plus `idle` means an active objective exists, but no turn is
   currently running.
7. `active` goal plus `notLoaded` means persisted active goal, not live work.

### Did This Session Start With A Prompt?

Use this wording:

- Strong: "The first turn contains a user message."
- Inference: "The preview came from the first user message."
- Not supported: "This was created through a one-step start-with-prompt flow."

How to inspect:

1. `thread/read` with `includeTurns: true`, or `thread/turns/list`.
2. Find the earliest turn.
3. Look for the first `UserMessage`.
4. Compare it to `Thread.preview`.

### Was This A JSON-Mode Session?

Use this wording:

- Strong: "This turn was started with `turn/start.outputSchema`" only if this
  client observed the request.
- Weak: "The output appears to be JSON" if only history content suggests it.
- Not supported: "This old session was JSON mode" from `Thread` or `Turn`
  summaries alone.

## Things App-Server Does Not Expose Reliably

- A single canonical "thread type" field.
- A durable `createdByUser` boolean.
- A durable `startedWithPrompt` boolean.
- A durable `jsonMode` or `outputSchema` flag on `Thread` or `Turn`.
- Subscriber count.
- A direct public thread-tree API for all spawned descendants.
- A direct `archived` boolean on `Thread`.
- A stable "old" state separate from timestamps and `notLoaded`.
- A stable realtime-active boolean on `Thread`.
- A guaranteed custom-source filter for arbitrary `{ "custom": ... }` values.
- Core internal source details that app-server intentionally maps to `unknown`.

## Suggested Client Classification Model

A Dock client should avoid one overloaded status string. Use separate axes:

```swift
struct ThreadClassification {
    var liveState: LiveState
    var origin: Origin
    var relationship: Relationship
    var persistence: Persistence
    var attention: AttentionState
    var goal: GoalState
    var evidence: [Evidence]
}
```

Suggested axes:

Live state:

- `notLoaded`
- `idle`
- `active`
- `systemError`

Origin:

- `interactiveCli`
- `interactiveVsCode`
- `interactiveCustom(name)`
- `exec`
- `appServer`
- `subAgent(kind)`
- `unknown`

Relationship:

- `root`
- `forked(parentThreadId)`
- `spawned(parentThreadId, depth, nickname, role)`
- `unknownParent`

Persistence:

- `persisted`
- `ephemeral`
- `archived`

Attention:

- `none`
- `waitingOnApproval`
- `waitingOnUserInput`
- `waitingOnApprovalAndInput`

Goal:

- `none`
- `activeLive`
- `activeIdle`
- `activeStored`
- `paused`
- `blocked`
- `usageLimited`
- `budgetLimited`
- `complete`
- `unsupported`
- `featureDisabled`

This keeps UI honest. For example, a thread can be:

- spawned + active + waiting on approval + persisted
- user-root + idle + active goal + persisted
- exec + not loaded + archived
- forked + ephemeral + active

Those combinations are real; a single "thread type" cannot represent them
without losing important facts.

## Evidence From Upstream Codex

Inspected upstream files in `/Users/aelaguiz/workspace/codex`:

- `codex-rs/app-server/README.md`
  - App-server lifecycle methods, `thread/start`, `thread/resume`,
    `thread/fork`, `thread/list`, `thread/loaded/list`, `thread/read`,
    `thread/unsubscribe`, `thread/closed`, goals, realtime, and examples.
- `codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs`
  - `Thread`, `SessionSource`, `ThreadSource`, `Turn`.
- `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
  - `ThreadStartParams`, `ThreadStartSource`, `ThreadGoalStatus`,
    `ThreadSourceKind`, `ThreadStatus`, notifications.
- `codex-rs/app-server-protocol/src/protocol/v2/turn.rs`
  - `TurnStartParams.output_schema`.
- `codex-rs/app-server-protocol/src/protocol/v2/item.rs`
  - `ThreadItem`, `CollabAgentToolCall`, agent statuses.
- `codex-rs/app-server-protocol/src/protocol/v2/realtime.rs`
  - Realtime methods and notifications.
- `codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts`
  - Generated app-server TypeScript `Thread` shape.
- `codex-rs/app-server-protocol/schema/typescript/v2/SessionSource.ts`
  - Generated v2 `SessionSource` shape.
- `codex-rs/app-server-protocol/schema/typescript/SubAgentSource.ts`
  - Generated core `SubAgentSource` shape used inside app-server source.
- `codex-rs/app-server/src/thread_status.rs`
  - Runtime status facts and active-flag derivation.
- `codex-rs/app-server/src/filters.rs`
  - `ThreadSourceKind` filtering and interactive defaults.
- `codex-rs/app-server/src/request_processors/thread_lifecycle.rs`
  - 30-minute unload behavior and closing errors.
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
  - Thread list/read/start/resume/fork/archive behavior, stored-thread
    conversion, session ID fallback, status overlay, spawned descendant archive.
- `codex-rs/app-server/src/request_processors/thread_goal_processor.rs`
  - Goal feature gate, persisted-thread requirement, ephemeral-thread rejection,
    goal get/set/clear behavior.
- `codex-rs/protocol/src/protocol.rs`
  - Core `SessionSource`, `ThreadSource`, `SubAgentSource`,
    `ThreadGoalStatus`, `TurnContextItem`, `Op::UserInput`.
- `codex-rs/core/src/goals.rs`
  - Runtime goal continuation rules and active-goal accounting.
- `codex-rs/core/src/tools/handlers/goal_spec.rs`
  - Model-facing goal tools and allowed model-controlled status updates.
- `codex-rs/core/src/codex_delegate.rs`
  - Interactive and one-shot sub-agent thread spawning.
- `codex-rs/core/src/thread_manager.rs`
  - Thread manager start/resume/spawn/fork behavior.
- `codex-rs/core/src/tools/handlers/agent_jobs.rs`
  - Agent-job worker source metadata.
- `codex-rs/core/src/session/turn_context.rs`
  - Durable turn context fields; no persisted final output schema.
- `codex-rs/core/src/session/turn.rs`
  - Final output schema applied to model prompt.
- `codex-rs/rollout/src/lib.rs`
  - Interactive session source defaults.
- `codex-rs/state/migrations/0021_thread_spawn_edges.sql`
  - Internal spawn-edge table shape.
- `codex-rs/state/src/runtime/threads.rs`
  - Internal spawned-descendant traversal and agent-path lookup.

## Live App-Server Proof On 2026-05-30

Runtime app-server:

```text
/Users/aelaguiz/.local/bin/codex
codex-cli 0.135.0-alpha.2
```

Observed facts:

- `relay/state/snapshot` represented 1514 active app-server-listable threads.
- SQLite had 1515 active thread rows.
- The one missing thread was direct-readable by ID but absent from every
  app-server `thread/list` scope because its preview was empty:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- `dock/subscribe` returned 1514 sessions, exactly matching the active
  app-server-listable set.
- `dock/subscribe` returned 0 archived rows, 0 duplicate session IDs, and 0
  duplicate thread IDs.
- Spawn parent/child parity matched 1189 of 1189 app-server-listable spawned
  rows.

Read-only source check:

- Current `ThreadListParams` has no previewless/exhaustive list option.
- Current SQLite list filtering applies `threads.preview <> ''`.
- Current rollout listing requires session metadata and a discoverable preview.
- Current `thread/read` can read at least some previewless threads when the
  caller already knows the thread ID.

Meaning:

- The relay can be complete for the set app-server can list.
- The relay cannot discover previewless direct-readable threads without a new
  app-server list surface or bypassing app-server, which this project must not
  do.
