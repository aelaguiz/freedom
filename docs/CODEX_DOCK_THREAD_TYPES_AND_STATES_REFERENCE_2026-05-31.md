# Codex Dock Thread Types And States Reference

Date: 2026-05-31

Last source check: 2026-06-04

Status: canonical Dock-side reference for thread type, runtime status, wait
state, input state, and app-facing projection.

Companion UX reference:
[Codex Dock Thread State UX Reference](./CODEX_DOCK_THREAD_STATE_UX_REFERENCE_2026-06-04.md)

Scope: Codex Dock client, Node Dock relay, contract files, tests, and existing
thread-state docs. This doc records the 2026-05-31 human-only implementation and
the 2026-06-04 source-checked wait/input correction.

## Net Answer

There is no single durable `threadType` or `threadState` field that answers the
whole question. The underlying Codex data has several independent axes:
origin, relationship, persistence, archive membership, runtime status, wait
state, request-card state, turn state, goal state, relay freshness, detail live
state, and local UI state.

Yes, human-started, agent-spawned, `codex exec`, app-server/API, forked,
ephemeral, and goal-tracked threads can often be detected from raw Codex
thread data. That raw taxonomy remains useful for diagnostics and future
product work.

For ordinary app-facing Codex Dock UX after the 2026-05-31 manual-fork update,
there is one allowed origin bucket: a thread started from a proven interactive
human source. Manual forks are included because `forkedFromId` is a
relationship signal, not an origin signal. The relay rejects `exec`,
app-server/API, MCP, sub-agent, thread-spawn child, memory/internal, unknown,
missing-source, and contradictory-source rows before they can become Dock,
Archive, detail, resume, focused-turn, or live-lease state.

For diagnostics and internal reasoning, Dock can still describe these
differences:

- `human` vs `agent` vs `unknown` lane.
- `running`, `needsInput`, `needsApproval`, `idle`, `error`, `dormant`,
  `unknown`.
- `active` vs `archived`.
- `fresh`, `stale`, `offline`, `error`, `unknown`.
- Detail `connecting`, `reconnecting`, `live`, `stale`, `closed`.
- Request-card kinds such as command approval, file-change approval,
  permissions approval, user input, and MCP elicitation.

There is no Codex thread status for sub-activity such as "running tests",
"editing files", "reading repo", or "thinking". Those can only be event or item
summaries. They must not be documented or displayed as raw thread states.

For richer UX, such as a future separate machine/agent area, the relay should
add a separate diagnostic or product surface. Normal Dock cards should not
quietly return to mixed human and non-human rows.

## 2026-06-04 Wait/Input Correction

`idle` and `waitingOnUserInput` are separate source-level facts in Codex.

- `idle` means the app-server has a loaded thread with no running turn, no
  pending approval request, no pending user-input request, and no system error.
  It is the normal "ready for the next user turn" runtime state.
- `waitingOnUserInput` is not `idle`. It appears only as an `active.activeFlags`
  entry while a `request_user_input` request is pending inside an active turn.
- `waitingOnApproval` is a separate `active.activeFlags` entry for
  approval-style requests.
- `active` with no flags means Codex has an open/running turn, but it does not
  say what the turn is doing. Testing, editing, searching, and thinking are not
  thread-status values.
- The app-server can express both active flags at once. Dock currently gives
  `waitingOnApproval` precedence, so both flags project to `needsApproval`.
- A thread can be `idle` while a goal is still `active`, `blocked`, or
  `budget_limited`, because goal state is a separate axis from runtime turn
  status.
- According to Codex app-server's `loaded_thread_status`, a thread cannot be
  both `idle` and `waitingOnUserInput` at the same time.

Use this mental model:

| Question | Canonical signal |
| --- | --- |
| Is the loaded thread ready for my next prompt? | Raw `Thread.status.type == "idle"` or Dock card `status == "idle"`. |
| Is an active turn paused because it asked me for typed/chosen input? | Raw `Thread.status.type == "active"` with `activeFlags` containing `waitingOnUserInput`, or Dock card `status == "needsInput"`. |
| Is an active turn paused because it needs an approval decision? | Raw `Thread.status.type == "active"` with `activeFlags` containing `waitingOnApproval`, or Dock card `status == "needsApproval"`. |
| Is the thread only stored on disk, not live in memory? | Raw `Thread.status.type == "notLoaded"` or Dock card `status == "dormant"`. |

## App-Facing Status Projection

For product UI, keep exact source states available in debug, filters, tests, and
diagnostics. The visible app-facing state should stay simple:

- `Codex is working`: Codex is doing things and it is not the user's turn.
- `Your turn`: Codex is done for now, or Codex is blocked until the user acts.
- `Error`: a small badge only when the thread itself is in raw error state.

Do not add a generic catch-all error section, tab, or header state. If a thread
is in error, badge that thread with `Error`. Other health/status surfaces are
out of scope for this focused UX slice.

| Source axis | Source state or fact | App-facing status family | Label or detail |
| --- | --- | --- | --- |
| Raw `Thread.status` | `active` with no flags | `Codex is working` | Optional latest-activity summary from turn/item events |
| Raw `Thread.status` | `active` with `waitingOnApproval` | `Your turn` | `Needs approval`, `Review command`, `Review files`, or `Grant permission` |
| Raw `Thread.status` | `active` with `waitingOnUserInput` | `Your turn` | `Needs answer` |
| Raw `Thread.status` | `active` with both wait flags | `Your turn` | Approval first; show secondary input in detail if needed |
| Raw `Thread.status` | `idle` | `Your turn` | `Ready` |
| Raw `Thread.status` | `notLoaded` | `Your turn` | `Saved` or `Not loaded` |
| Raw `Thread.status` | `systemError` | thread error | `Error` |
| Raw `Thread.status` | unknown status string | diagnostic | `Unknown` |
| Dock row status | `running` | `Codex is working` | Optional latest-activity summary |
| Dock row status | `needsApproval` | `Your turn` | Approval/request-card sublabel |
| Dock row status | `needsInput` | `Your turn` | `Needs answer` |
| Dock row status | `idle` | `Your turn` | `Ready` |
| Dock row status | `dormant` | `Your turn` | `Saved` or `Not loaded` |
| Dock row status | `error` | thread error | `Error` |
| Dock row status | `unknown` | diagnostic | `Unknown` |
| Request card | pending `commandApproval`, `fileChangeApproval`, `permissionsApproval`, `userInput`, `mcpElicitation`, or `unsupported` | `Your turn` | Exact request action |
| Request card | `resolved` | fall back to raw runtime status | No standalone bucket |
| Turn status | `inProgress` | `Codex is working` only if raw runtime status is active without wait flags | Turn status supports, but does not replace, `Thread.status` |
| Turn status | `completed`, `interrupted`, or `failed` | fall back to raw runtime status; `failed` can inform exact error copy | Turn history is lower-level than thread status |
| Goal status | `active`, `paused`, `budget_limited`, `usage_limited`, `complete` | no standalone bucket | Goal state is a separate axis |
| Goal status | `blocked` | future `Your turn` only with a concrete user action | Do not infer from goal state alone today |
| Archive state | archived | `Your turn` | `Saved` |
| Relay freshness | any value | out of scope for this UX slice | Keep available in diagnostics/source inventory only |
| Detail live state | any value | out of scope for this UX slice | Keep available in diagnostics/source inventory only |
| Detail screen state | `loading` | temporary UI loading state, not a Codex bucket | Keep previous bucket if available |
| Detail screen state | `loaded` | use raw runtime bucket | Normal detail state |
| Detail screen state | `error` | out of scope for this UX slice | Detail loading error is not part of the thread-turn status model |

Important collapse rule: `Your turn` has urgent and quiet sublabels. Required
actions such as `Needs answer`, `Review command`, and `Grant permission` are
prominent. Quiet states such as `Ready` and `Saved` should stay quiet by
default.

## Canonical State Axes Inventory

These axes are independent unless a section below says otherwise. Do not collapse
them into one product label.

| Axis | Canonical states or values | Source of truth | Dock card today |
| --- | --- | --- | --- |
| Origin lane | `human`, `agent`/automation, `unknown` | Raw `Thread.source`, `Thread.threadSource`, rollout/session metadata, relay source classifier | `lane`, `sourceKind` |
| Origin subtype | `cli`, `vscode`, custom interactive source, `exec`, `appServer`, MCP, review sub-agent, compact sub-agent, thread-spawn sub-agent, memory/internal, other, unknown | Raw source payload and relay classifier | Collapsed; exact subtype not sent |
| Relationship | `root`, `forked`, `spawned`, `unknown` | `forkedFromId`, `forked_from_id`, `parentThreadId`, `parent_thread_id`, `thread_spawn_edges`, sub-agent source payload | `relationship`, `forkedFromID`; spawn rows are rejected from app-facing cards |
| Persistence | durable, `ephemeral`, unknown | Raw `Thread.ephemeral` and storage behavior | Not sent |
| Archive membership | `active`, `archived`, `unknown` | App-server archive filters, storage archive fields, relay local archive state | `archiveState` |
| Runtime status | `notLoaded`, `idle`, `systemError`, `active` | Raw `Thread.status` | Projected to `dormant`, `idle`, `error`, `running`/attention |
| Active wait flags | none, `waitingOnApproval`, `waitingOnUserInput`, both | Raw `Thread.status.active.activeFlags` | Projected to `running`, `needsApproval`, or `needsInput` |
| Request-card kind | `commandApproval`, `fileChangeApproval`, `permissionsApproval`, `userInput`, `mcpElicitation`, `unsupported` | Server request method | Detail UI only |
| Request-card status | `pending`, `responding`, `resolved`, `failed` | Swift request-card local state plus server request resolution | Detail UI only |
| Request-card action | `accept`, `decline`, `submitInput` | Swift request-card model | Detail UI only |
| Goal status | `active`, `paused`, `blocked`, `usage_limited`, `budget_limited`, `complete` | `thread/goal/get` or `goals_1.sqlite` | Not sent |
| Turn status | `inProgress`, `completed`, `interrupted`, `failed` | Raw `Turn.status` | Not on Dock card |
| Turn item view | `notLoaded`, `summary`, `full` | Raw `Turn.itemsView` / route `itemsView` params | Not on Dock card |
| Event category | `userMessage`, `agentMessage`, `command`, `output`, `request`, `system`, `unknown` | Swift event decoder over raw items/notifications | Detail/timeline only |
| Event visibility group | `message`, `thinking`, `tooling`, `request`, `system`, `unknown` | Swift event projection | Detail/timeline only |
| Relay freshness | `unknown`, `fresh`, `stale`, `offline`, `error` | Relay host health and projection age | `freshness` |
| Relay completeness | `complete`, `partial`, `unknown` | Relay projection/window state | `completeness` |
| Detail live state | `connecting`, `reconnecting`, `live`, `stale`, `closed` | `ThreadDetailLiveState` in Swift | Detail UI only |
| Detail screen state | `idle`, `loading`, `loaded`, `error` | `ThreadDetailScreenState` in Swift | Detail UI only |
| Dock row badge visibility | visible for `running`, `needsInput`, `needsApproval`, `error`; hidden for `idle`, `dormant`, `unknown` | `DockRowStatusKind.showsBadge` in Swift | Derived from `status` |
| Local UI state | selection, filters, search, pinned display cache, composer state, render options | Swift stores | Not Codex thread state |

## App-Facing Human-Only Invariant

Implemented on 2026-05-31.

Ordinary app-facing paths are human-only:

- Dock and Archive streams.
- Relay card storage, counts, cache lookup, and live leases.
- `thread/list`, `thread/search`, `thread/loaded/list`, `thread/read`,
  `thread/turns/list`, `thread/goal/get`, `thread/archive`,
  `thread/unarchive`, and `thread/resume`.
- Focused `turn/start`, `turn/steer`, and `turn/interrupt`.
- Swift stream ingestion, row projection, and cached pinned-row revival.

The canonical app-facing policy lives in
`scripts/dock-relay-human-thread-filter.mjs`. The self-documenting predicate is
`isHumanStartedThread(row)`. Persisted card cleanup and counts keep the same
named app-facing boundary. Direct non-human IDs fail closed with `code:
-32043`, `message: "thread rejected by human-only filter"`, and redacted
`{ threadId, reason }` data.

All-source visibility is diagnostic only. `relay/state/snapshot` defaults to
`app_facing_human_started_threads_only`; callers must opt into
`includeRejectedThreads: true` to inspect rejected rows, and that mode is
labeled `diagnostic_includes_rejected_threads`.

## Vocabulary

`Thread` means the app-server object the Swift client decodes in
`CodexDock/AppServer/ThreadListDTO.swift`. It can carry rich raw fields such as
`source`, `threadSource`, `forkedFromId`, `ephemeral`, `sessionId`,
`agentNickname`, `agentRole`, and `status`.

`Rollout` or `session JSONL` means the durable Codex session file on disk. Its
first `session_meta` record can include fields such as `id`, `forked_from_id`,
`source`, `thread_source`, `originator`, `agent_nickname`, `agent_role`,
`agent_path`, and `memory_mode`.

`Dock card` means the relay-owned row DTO sent to the app by `dock/subscribe`,
`dock/update`, and `dock/resync`. It is not the same shape as raw `Thread`.

`Raw relay routes` means `thread/list`, `thread/search`, `thread/read`,
`thread/turns/list`, `thread/goal/get`, `thread/archive`, and
`thread/unarchive` as routed through the Dock relay.

`Dock stream` means the phone-facing Home or Archive stream. Home uses
`dock/subscribe`, `dock/update`, and `dock/resync`. Archive uses
`archive/subscribe`, `archive/update`, and `archive/resync`.

Archive rows are openable. They use the same `DockRowViewModel` relationship
metadata as Dock rows, so an archived manual fork opens Thread Detail with the
same `Fork` pill instead of falling into the non-human `Thread unavailable.`
path.

## Current Data Path

Codex storage and app-server data are richer than the Dock cards.

Raw app-server and storage evidence can identify detailed origins and
relationships:

- `source`
- `threadSource`
- `forkedFromId` / `forked_from_id`
- `parentThreadId` / `parent_thread_id`
- `ephemeral`
- `sessionId`
- `agentNickname`
- `agentRole`
- `agentPath`
- `thread_spawn_edges(parent_thread_id, child_thread_id, status)`
- `source.subAgent.thread_spawn.parent_thread_id`
- goal rows from `goals_1.sqlite`

The relay currently has two different surfaces:

- Raw thread routes mostly preserve rich app-server thread rows.
- Dock cards convert those rows into a smaller UI projection.

The current Dock card contract contains these origin/state fields:

- `status`: `running`, `needsInput`, `needsApproval`, `idle`, `error`,
  `dormant`, `unknown`.
- `sourceKind`: `human`, `automation`, `unknown`.
- `lane`: `human`, `agent`, `unknown`.
- `archiveState`: `active`, `archived`, `unknown`.
- `freshness`: `unknown`, `fresh`, `stale`, `offline`, `error`.
- `completeness`: `complete`, `partial`, `unknown`.
- `relationship`: `root`, `forked`, `spawned`, `unknown`.
- `forkedFromID`: fork parent thread ID when present.

It does not contain raw `source`, `threadSource`, source subtype, spawn parent,
spawn depth, `ephemeral`, goal status, `agentNickname`, `agentRole`, or
`agentPath`.

## Thread Origin Types

Origin is the closest thing to a "thread type", but it is still only one axis.

| UX bucket | Raw evidence | Current Dock card | Detection quality |
| --- | --- | --- | --- |
| Human interactive | `source == "cli"`, `source == "vscode"`, or custom interactive sources such as `atlas` and `chatgpt` | `lane: human`, `sourceKind: human` | Strong for interactive source. Includes root threads and manual forks. Not proof of the exact human gesture that created it. |
| `codex exec` root | `source == "exec"` | `lane: agent`, `sourceKind: automation` | Strong on raw routes. Exact subtype is lost on Dock cards. |
| App-server/API/MCP root | `source == "appServer"` or `mcp` alias in relay source filtering | `lane: agent`, `sourceKind: automation` | Strong on raw routes. Exact subtype is lost on Dock cards. |
| Spawned sub-agent | `source.subAgent`, `threadSource == "subagent"`, `agentNickname`, `agentRole`, `agentPath`, and sometimes `source.subAgent.thread_spawn.parent_thread_id` | `lane: agent`, `sourceKind: automation` | Strong on raw routes and storage. Parent/depth are lost on Dock cards. |
| Review sub-agent | `source.subAgent.review` or normalized `subAgentReview` | `lane: agent`, `sourceKind: automation` | Strong on raw routes. Exact subtype is lost on Dock cards. |
| Compact sub-agent | `source.subAgent.compact` or normalized `subAgentCompact` | `lane: agent`, `sourceKind: automation` | Strong on raw routes. Exact subtype is lost on Dock cards. |
| Thread-spawn child | `source.subAgent.thread_spawn` with parent id, depth, agent path/nickname/role | `lane: agent`, `sourceKind: automation` | Strong on raw routes and `thread_spawn_edges`. Parent/depth are lost on Dock cards. |
| Memory consolidation/internal | `threadSource == "memory_consolidation"` or internal source variants | Usually filtered out of Dock scopes | Strong when raw metadata is visible. Should not be treated as human. |
| Unknown | Missing, contradictory, hidden, or unrecognized source | `lane: unknown`, `sourceKind: unknown` | Honest fallback. Do not infer human from unknown. |

The relay source classifier already understands more than the Dock card sends:
`cli`, `vscode`, `exec`, `appServer`, `mcp`, `subAgentReview`,
`subAgentCompact`, `subAgentThreadSpawn`, `subAgentOther`, `unknown`, and
internal memory rows. The Dock card collapses this to `human`, `agent`, or
`unknown`.

If app-server `thread/list` omits a recent readable human-started thread, the
relay can use `session_index.jsonl` as a bounded candidate list. Every
candidate still has to pass authoritative `thread/read includeTurns:false`
classification before it can become a Dock card.

## Relationship Types

Relationship is separate from origin.

| Relationship | Raw evidence | Current Dock card | Notes |
| --- | --- | --- | --- |
| Root thread | No `forkedFromId` and no spawn parent evidence | `relationship: "root"` | Root is inferred by absence of parent/fork evidence. |
| Spawned child | `thread_spawn_edges`, `source.subAgent.thread_spawn.parent_thread_id`, `depth`, agent fields | Rejected from app-facing cards | Spawn is automation relationship evidence and remains outside human Dock surfaces. |
| Forked thread | `Thread.forkedFromId` or rollout `forked_from_id` | `relationship: "forked"`, `forkedFromID` | Forking is not the same as spawning. A human-source fork is human-started and appears with a `Fork` badge. |
| Resumed thread | Observed `thread/resume` action or live session binding | Not explicit | Resume is an operation, not a durable thread type. |
| Prompt-started thread | First user message or preview evidence | Not explicit | There is no durable `startedWithPrompt` boolean. Treat this as an inference only. |
| Ephemeral thread | `Thread.ephemeral == true` on app-server thread data | Not explicit | App-server-only evidence. Not in Dock cards. |

## Machine And JSON Threads

There is no durable first-class `machine` or `json` thread type today.

The best current raw evidence for machine-created or automation-created work is
source and storage metadata:

- `source == "exec"`.
- `source == "appServer"`.
- `source` normalized from `mcp`.
- `source.subAgent` variants.
- `originator` in rollout `session_meta`.
- `threadSource`.
- `has_user_event` and `first_user_message` storage metadata, without using
  prompt text in logs or UI classification.
- `dynamic_tools` and agent job tables where present.

JSON or structured output is weaker. `turn/start.outputSchema` is a live
turn-level setting, not a durable thread field. Once the turn is historical,
the client should not assume a thread was "JSON mode" unless it directly
observed the live request or a future durable field is added.

Practical rule: treat `exec`, `appServer`, MCP, and sub-agent sources as
automation. Treat JSON output as a turn behavior, not a thread type.

## Runtime, Wait, And Input States

Raw app-server thread status and Dock card status are related but not identical.
Codex has one raw runtime status union, and `active` can carry zero or more wait
flags.

| Raw app-server status | Raw flag set | Dock card status | Meaning |
| --- | --- | --- | --- |
| `active` | `[]` | `running` | A turn is running and is not currently paused on a known client response. |
| `active` | `["waitingOnApproval"]` | `needsApproval` | A turn is active and blocked on an approval-style request. |
| `active` | `["waitingOnUserInput"]` | `needsInput` | A turn is active and blocked on `request_user_input` / `item/tool/requestUserInput`. |
| `active` | `["waitingOnApproval", "waitingOnUserInput"]` | `needsApproval` | The protocol/runtime model can express both counters at once. Dock gives approval precedence over input. |
| `idle` | none | `idle` | Thread is loaded, no turn is running, no approval/input request is pending, and no system error is set. |
| `systemError` | none | `error` | Loaded runtime is in a thread-level system error state. App-server clears running and pending counters when it records a system error. |
| `notLoaded` | none | `dormant` | Thread is known in history but not loaded into the app-server runtime. |
| unknown string | any | `unknown` | Client should preserve safe fallback behavior. |

Canonical raw enum:

- `ThreadStatus.notLoaded`
- `ThreadStatus.idle`
- `ThreadStatus.systemError`
- `ThreadStatus.active { activeFlags }`

Canonical active flags:

- `ThreadActiveFlag.waitingOnApproval`
- `ThreadActiveFlag.waitingOnUserInput`

Non-canonical thread states:

- `Running tests`
- `Editing files`
- `Reading repo`
- `Thinking`
- `Writing reply`
- Any other label derived from the latest command, file change, plan,
  reasoning row, or streamed assistant message

Those labels can be activity summaries in Thread Detail or row support copy.
They are not values of `Thread.status`.

The app-server status derivation is exact:

1. If `is_loaded == false`, status is `notLoaded`.
2. If pending approval requests exist, add `waitingOnApproval`.
3. If pending user-input requests exist, add `waitingOnUserInput`.
4. If `running == true` or any active flag exists, status is `active`.
5. If `has_system_error == true`, status is `systemError`.
6. Otherwise status is `idle`.

The app-server transition points are also exact:

| App-server event/method | Runtime fact changed | Resulting thread status |
| --- | --- | --- |
| `note_turn_started` | `is_loaded = true`, `running = true`, `has_system_error = false` | `active { activeFlags: [] }` until a wait flag appears |
| `note_permission_requested` | increments the pending permission counter | `active` with `waitingOnApproval` |
| `note_user_input_requested` | increments the pending user-input counter | `active` with `waitingOnUserInput` |
| Permission or input guard drops | decrements the matching pending counter | stays `active` if `running` is true or another flag remains; otherwise resolves through the normal derivation |
| `note_turn_completed` | clears `running` and both pending counters | usually `idle` |
| `note_turn_interrupted` | clears `running` and both pending counters | usually `idle` |
| `note_system_error` | clears `running` and both pending counters, sets `has_system_error = true` | `systemError` |
| next `note_turn_started` after a system error | sets `running = true`, clears `has_system_error` | `active { activeFlags: [] }` |
| `note_thread_shutdown` | clears `running`, clears both pending counters, sets `is_loaded = false` | `notLoaded` |
| `remove_thread` | removes runtime facts | `notLoaded` notification if the previous status was loaded |

`resolve_thread_status` adds one important read-time correction: if the loaded
watch status is `idle` or `notLoaded` but the returned thread contains a live
`inProgress` turn, app-server returns `active { activeFlags: [] }`. This covers
the race where turn history is observed before the runtime watch state catches
up.

The app-server's running-turn count is not the same as "active". It counts only
`runtime.running`. A pending approval or pending user-input request can make
`Thread.status` active without increasing the running-turn count.

That means `idle` is not "waiting on user input" in the active-request sense.
It is "ready for a new turn" in the loaded-runtime sense.

`notLoaded` is important: it is not the same thing as archived, deleted, or
offline. It means the thread is known in history but not currently loaded into
the app-server runtime.

`thread/closed` is also separate. It means a runtime session closed or unloaded.
It is not an archive event.

`thread/loaded/list` is also separate. It returns loaded in-memory thread IDs,
not wait/input status. Use `thread/read`, `thread/list`, or
`thread/status/changed` to read `Thread.status`.

## Archive, Freshness, And Completeness

Archive membership is not `Thread.status`.

Archive can be detected through:

- App-server `thread/list` archive filters.
- Storage `threads.archived` and `archived_at`.
- Archive paths on disk.
- Relay-local `archive_state`.

The relay stores its own projected Dock state in `.codex-dock/relay-state.sqlite`.
That projection uses `archive_state = active|archived|unknown`. Dock excludes
archived rows, and Archive includes archived rows.

Freshness is relay/client health, not Codex thread origin:

- `fresh`: relay has recent, complete-enough data for the host.
- `stale`: host data is old or heartbeat says stale, but last good rows may be
  retained.
- `offline`: host is unavailable.
- `error`: host or stream has an error.
- `unknown`: freshness cannot be established.

Completeness is also relay projection state:

- `complete`: relay believes the current stream/window is complete.
- `partial`: relay knows it has an incomplete projection.
- `unknown`: completeness cannot be established.

## Detail Screen States

Thread Detail has its own live-state model:

- `connecting`
- `reconnecting`
- `live`
- `stale`
- `closed`

Detail also has screen loading state:

- `idle`
- `loading`
- `loaded`
- `error`

The detail path reads stored thread data, drains paged turns, resumes the
thread with `excludeTurns: true`, then treats notifications and server requests
as live events. Detail state should not be collapsed into Dock row status.

## Request-Card States

Server requests are action states inside a thread, not thread types.

Current source-to-card mapping:

| Server request method | App-server wait flag | Swift request-card kind | User action |
| --- | --- | --- | --- |
| `item/commandExecution/requestApproval` | `waitingOnApproval` | `commandApproval` | `accept` or `decline` |
| `item/fileChange/requestApproval` | `waitingOnApproval` | `fileChangeApproval` | `accept` or `decline` |
| `item/permissions/requestApproval` | `waitingOnApproval` | `permissionsApproval` | `accept` or `decline` |
| `item/tool/requestUserInput` | `waitingOnUserInput` | `userInput` | `submitInput` |
| `mcpServer/elicitation/request` | `waitingOnApproval` in app-server source | `mcpElicitation` | Approval-style elicitation response |
| Unknown or unsupported method | No reliable canonical flag | `unsupported` | No specialized action UI |

Current request-card statuses:

- `pending`
- `responding`
- `resolved`
- `failed`

These should drive per-thread action UI such as approval buttons or input
forms. They should not be used as origin labels.

Important relay caveat: `scripts/dock-relay-thread-data.mjs` has a fallback
pending-request enrichment path for cases where the relay sees a server request
before or without an authoritative status update. That fallback currently maps
`mcpServer/elicitation/request` to `waitingOnUserInput`. The Codex app-server
source path uses `note_permission_requested`, so the authoritative app-server
status for MCP elicitation is approval-style waiting. If those disagree, prefer
raw `Thread.status` and treat relay fallback enrichment as best-effort display
state.

## Goal States

Goals are separate from thread status and origin.

The app-server goal API and `goals_1.sqlite` can expose goal state. Observed
goal statuses include:

- `active`
- `paused`
- `blocked`
- `usage_limited`
- `budget_limited`
- `complete`

Dock cards do not currently include goal status. A goal-aware Dock UX would
need a new card field or a per-row goal lookup.

## Turn And Item States

Turns and events are lower-level history inside a thread.

Known turn states from the existing app-server docs:

- `inProgress`
- `completed`
- `interrupted`
- `failed`

Known turn item-loading states:

- `notLoaded`
- `summary`
- `full`

Swift event categories include:

- `userMessage`
- `agentMessage`
- `command`
- `output`
- `request`
- `system`
- `unknown`

Visibility groups include:

- `message`
- `thinking`
- `tooling`
- `request`
- `system`
- `unknown`

Known item or request-adjacent statuses include:

- `CommandExecutionStatus`: `inProgress`, `completed`, `failed`, `declined`.
- `PatchApplyStatus`: `inProgress`, `completed`, `failed`, `declined`.
- `GuardianApprovalReviewStatus`: `inProgress`, `approved`, `denied`,
  `timedOut`, `aborted`.
- `McpToolCallStatus` and `DynamicToolCallStatus`: `inProgress`, `completed`,
  `failed`.

These are useful for Timeline and Detail UX. They are not enough by themselves
to classify thread origin, and they are not `Thread.status` values.

Activity summaries should be derived from this layer, not from the thread-state
field. For example, "last command is still in progress" or "latest visible
event is a reasoning row" can support a separate activity line, but it should
not turn the thread status into `Running tests`, `Editing files`, or `Thinking`.

## What The Relay Sends Today

The relay currently sends different amounts of evidence depending on the route.

### Raw Thread Routes

These routes mostly preserve raw app-server thread evidence:

- `thread/list`
- `thread/search`
- `thread/read`
- `thread/turns/list`
- `thread/goal/get`
- `thread/archive`
- `thread/unarchive`

The Swift `ThreadDTO` can decode rich thread fields, including `source`,
`threadSource`, `forkedFromId`, `ephemeral`, `sessionId`, `agentNickname`,
`agentRole`, and `status`.

### Dock And Archive Streams

These streams send normalized cards:

- `dock/subscribe`
- `dock/update`
- `dock/resync`
- `archive/subscribe`
- `archive/update`
- `archive/resync`

Cards are intentionally smaller. They do not include raw origin, parent/fork,
ephemeral, or goal evidence.

### Relay State Snapshot

The relay snapshot/audit path tracks a richer surface, including fields such as
`source`, `threadSource`, status type, git fields, and agent fields. Treat this
as diagnostic/audit evidence, not the Home screen contract.

## What The Swift Client Can Represent Today

The Swift client has three layers with different precision.

Raw `ThreadDTO` is rich. It can represent app-server status, source,
`threadSource`, fork, ephemeral state, agent nickname, agent role, and raw turns.

`SessionOrigin` is moderately rich. It can represent:

- `humanInteractive`
- `agentOrAutomation`
- `unknown`
- human subtypes `cli`, `vscode`, and custom interactive source
- automation subtypes `exec`, `appServer`, and sub-agent variants

Dock rows are still lossy on exact origin. `ThreadCardRowProjector` maps
`lane: human` to human `.cli`, and `lane: agent` to automation `.exec`. That
means the UI loses the distinction between `exec`, app-server/API, review
sub-agent, compact sub-agent, thread-spawn child, and other sub-agent rows.

Dock rows are no longer lossy on manual fork relationship for accepted
human-started cards. The relay sends `relationship` and `forkedFromID`, Swift
projects them onto row models, and cached pinned display snapshots preserve
the relationship for pinned rows.

## Detectability Matrix

| Question | Detectable from raw Codex/app-server data? | Sent on Dock cards today? | Recommended UX confidence |
| --- | --- | --- | --- |
| Is this human-interactive? | Yes, from `source` and default interactive source rules. | Broadly yes as `human`. | High for broad human. Low for exact human action. |
| Is this `codex exec`? | Yes, from `source == "exec"`. | No exact subtype. | High if using raw route. Not available from card alone. |
| Is this app-server/API/MCP-created? | Yes, from `source == "appServer"` or MCP normalization. | No exact subtype. | High if using raw route. Not available from card alone. |
| Is this a sub-agent? | Yes, from `source.subAgent`, `threadSource`, and agent fields. | Broadly yes as agent/automation. | High for broad agent on card. High exact subtype only on raw route. |
| Is this specifically a thread-spawn child? | Yes, from `source.subAgent.thread_spawn` and `thread_spawn_edges`. | No. | High if using raw route/storage. |
| What parent spawned it? | Yes, from `parent_thread_id` evidence where present. | No. | High when `thread_spawn` evidence exists. |
| Is this forked? | Yes, from `forkedFromId` or rollout `forked_from_id`. | Yes, as `relationship: "forked"` and optional `forkedFromID` for accepted human-started cards. | High for app-facing human-started cards and high if using raw route/storage. |
| Is this resumed? | Only as an observed operation or live binding. | No. | Do not model as a thread type. |
| Was this started with an initial prompt? | Inferred from first user message or preview. | No. | Medium/weak. No durable boolean. |
| Is this JSON/structured-output mode? | Only if observing live `turn/start.outputSchema` or future durable evidence. | No. | Weak. Treat as turn behavior, not thread type. |
| Is this ephemeral? | Yes on raw app-server `Thread.ephemeral`. | No. | High if raw field is present. |
| Is this archived? | Yes from archive filters, storage, and relay archive state. | Yes as `archiveState`. | High. Separate from runtime status. |
| Is this currently active/running? | Yes from raw `Thread.status.active` and relay live leases. | Yes as `running` or attention status. | High for current projection, subject to freshness. |
| Is the loaded thread ready for the next user turn? | Yes from raw `Thread.status.idle`. | Yes as `idle`. | High for loaded runtime state. Separate from goal state. |
| Is an active turn waiting for explicit user input? | Yes from `activeFlags` containing `waitingOnUserInput` or `item/tool/requestUserInput`. | Yes as `needsInput`. | High from raw status. High from card if projection is fresh. |
| Is an active turn waiting for approval? | Yes from `activeFlags` containing `waitingOnApproval` or approval server requests. | Yes as `needsApproval`. | High from raw status. High from card if projection is fresh. |
| Is this MCP elicitation? | Yes from `mcpServer/elicitation/request`. App-server status uses `waitingOnApproval`. | Request card yes as `mcpElicitation`; fallback card attention may be input-style if status is missing. | High from server request kind. Prefer raw status for wait flag. |
| Does it have a goal? | Yes through `thread/goal/get` or goals DB. | No. | High if goal route/DB is consulted. |

## Current Self-Started Classification

This is the current implemented rule for the UX question: "Did I start this,
or did something else start it?"

`self_started` means the raw source proves an interactive human-facing source:

- `cli`
- `vscode`
- `atlas`
- `chatgpt`

`something_else` means the source is not one of those proven interactive
sources. This is intentionally broad. It includes:

- `exec`
- app-server/API-created work
- MCP-created work
- sub-agents
- thread-spawn children
- review or compact helper sessions
- memory/internal work
- unknown or contradictory source metadata

The conservative edge rule is: unknown is not counted as self-started. If the
source cannot prove an interactive human-facing start, it belongs outside the
self-started bucket until we add better evidence.

This is a draft classification, not a permanent product taxonomy. It is meant
to be easy to revise as real examples make the boundary clearer.

Implementation note on `2026-05-31`: this classification is now enforced for
app-facing Codex Dock behavior by
`scripts/dock-relay-human-thread-filter.mjs`. The canonical relay predicates
are named to state the policy directly:

- `classifyThreadOrigin(row)`
- `isHumanStartedThread(row)`
- `filterHumanStartedThreads(rows)`
- `assertHumanStartedThread(row)`
- `humanThreadRejectedError(threadId, reason)`

`forkedFromId` is deliberately handled by relationship helpers, not by origin
helpers. A row with source `cli`, `vscode`, custom `atlas`, or custom
`chatgpt` plus `forkedFromId` is `origin=human`, `relationship=forked`.

The Swift client is a defensive second line, not the source of truth. It drops
stream cards unless `lane == .human` and `sourceKind == .human`, and it only
revives cached pinned rows when the cached display has
`originKind == .human`.

Diagnostic all-source inspection still exists, but it is explicit. The normal
`relay/state/snapshot` result is labeled
`app_facing_human_started_threads_only`; including rejected rows requires
`includeRejectedThreads: true` and is labeled
`diagnostic_includes_rejected_threads`.

Examples:

- If you ask for `$fresh-consult` or `$model-consensus` inside a thread you
  started, that parent thread keeps its own source. If it was `cli`, `vscode`,
  `atlas`, or `chatgpt`, the parent remains `self_started`.
- A `$fresh-consult` Codex child runs through `codex exec --ephemeral`. If it
  appears in Codex thread data while live, classify it as
  `something_else / exec`; because it is ephemeral, it should not be expected
  to produce a durable relay-listable Dock row after completion.
- A `$model-consensus` Codex participant runs through resumable `codex exec`.
  Classify those participant threads as `something_else / exec`.
- `$fresh-consult` or `$model-consensus` Claude Code children and Cursor Agent
  children are not Codex Dock threads by themselves. They should not appear in
  these counts unless they separately create Codex sessions.
- Native delegated sub-agents, such as parallel agents spawned through the
  Dock/Codex sub-agent tool, classify as `something_else / sub-agent
  thread-spawn`, not as `exec`.

Positive confirmation on `2026-05-31`:

- The `$model-consensus` skill contract uses resumable `codex exec` for Codex
  participants, not native sub-agent spawn. Five existing
  `.arch_skill/model-consensus/**/events.jsonl` Codex participant thread IDs
  were cross-checked in `/Users/aelaguiz/.codex/state_5.sqlite`; all five had
  `source = exec`, `thread_source = user`, and `archived = 0`.
- The same five `$model-consensus` thread IDs were read through the live relay
  with `thread/read includeTurns:false`; all five returned `source = exec`,
  `status = notLoaded`, `ephemeral = false`, and no agent nickname or role.
- The `$fresh-consult` skill contract uses `codex exec --ephemeral` for Codex
  consult children. Fifty-one `/tmp/fresh-consult/**/events*.jsonl` Codex
  `thread.started` IDs were checked against `/Users/aelaguiz/.codex/state_5.sqlite`;
  none had a durable storage row. Three sampled IDs also failed live
  `thread/read` after completion with `thread not loaded`, matching the
  ephemeral-child expectation.

## Draft Live Data Breakdown

Collected from the live Dock relay at `ws://127.0.0.1:4510` on
`2026-05-31T11:19:37Z` with paginated raw `thread/list` calls. The request used
the explicit source-kind union `cli`, `vscode`, `exec`, `appServer`,
`subAgent`, `subAgentReview`, `subAgentCompact`, `subAgentThreadSpawn`,
`subAgentOther`, and `unknown`.

Although the request asked for `limit: 250`, the live service returned pages of
100 rows. The count drained cursors until `nextCursor: null`.

Top-level classification by scope:

| Scope | Total | `self_started` | `something_else` |
| --- | ---: | ---: | ---: |
| Active / non-archived relay-listable threads | 1,753 | 253 | 1,500 |
| Archived relay-listable threads | 18 | 4 | 14 |
| Combined relay-listable threads | 1,771 | 257 | 1,514 |

The next table breaks those same rows down by observed source bucket. In this
run, `self_started` is only `cli + vscode`; `atlas` and `chatgpt` had 0 rows.
`something_else` is `sub-agent thread-spawn + exec`; no app-server/API, MCP,
memory/internal, or unknown rows appeared in this relay-listable result.

| Classification | Observed source bucket | Active | Archived | Combined |
| --- | --- | ---: | ---: | ---: |
| `self_started` | `cli` | 160 | 3 | 163 |
| `self_started` | `vscode` | 93 | 1 | 94 |
| `something_else` | sub-agent thread-spawn | 1,394 | 14 | 1,408 |
| `something_else` | `exec` | 106 | 0 | 106 |

Relationship signals in the same relay-listable data:

| Signal | Active | Archived | Combined |
| --- | ---: | ---: | ---: |
| Thread-spawn parent present | 1,394 | 14 | 1,408 |
| Agent nickname or role present | 1,394 | 14 | 1,408 |
| Forked thread id present | 0 | 0 | 0 |
| `ephemeral == true` | 0 | 0 | 0 |

Status signals in the same relay-listable data:

| Status | Active | Archived | Combined |
| --- | ---: | ---: | ---: |
| `notLoaded` | 1,747 | 18 | 1,765 |
| `idle` | 5 | 0 | 5 |
| `active` | 1 | 0 | 1 |

Storage cross-check from `/Users/aelaguiz/.codex/state_5.sqlite` found 1,755
active storage rows and 18 archived storage rows. The active storage count is 2
rows higher than live `thread/list`: 1 empty-preview `cli` row and 1
empty-preview sub-agent row are present in storage but absent from the raw relay
`thread/list` enumeration.

For Dock UX backed by current relay list data, use the relay-listable active
count: 253 `self_started` and 1,500 `something_else`. For full storage
inventory, use 254 `self_started` and 1,501 `something_else` active rows.

The Dock stream itself is more limited. On the same run, `dock/subscribe`
returned a 500-row active window marked incomplete: 59 `human` cards and 441
`agent` cards. That is useful for current UI visibility, but it is not the
complete classification count.

## UX Implications

Safe UX distinctions with the current Dock card stream:

- Human lane vs agent lane vs unknown lane.
- Running vs needs input vs needs approval vs idle vs dormant vs error.
- Active Dock row vs archived Archive row.
- Fresh vs stale/offline/error host projection.
- Detail live/reconnecting/stale/closed state.
- Request-card action state inside Detail.

Unsafe UX distinctions from Dock cards alone:

- `exec` vs app-server/API vs sub-agent.
- Review sub-agent vs compact sub-agent vs thread-spawn child.
- Spawn parent, spawn depth, agent role, or agent path.
- Forked vs root.
- Ephemeral vs persisted.
- Goal active/blocked/complete.
- JSON/structured-output thread.
- "Created by human click" versus "created by another human-facing tool".

To support richer UX on Home without one raw lookup per row, the Dock card
contract should grow a normalized, non-secret origin payload. A practical shape
would include:

- `originCategory`: `human`, `automation`, `internal`, `unknown`.
- `originSubtype`: `cli`, `vscode`, `customInteractive`, `exec`, `appServer`,
  `mcp`, `subAgentReview`, `subAgentCompact`, `subAgentThreadSpawn`,
  `subAgentOther`, `memoryConsolidation`, `unknown`.
- `threadSource`: normalized raw `threadSource` where safe.
- `relationship`: `root`, `spawned`, `forked`, `unknown`.
- `spawnParentThreadID`, `spawnDepth`, `agentNickname`, `agentRole`,
  `agentPath` where present and safe.
- `forkedFromID` where present.
- `ephemeral` where present.
- `goalStatus` if the relay is willing to join goal state into the card.

Do not include raw prompt text, transcript text, full JSON-RPC payloads, bearer
tokens, OpenAI keys, base64 audio, or raw audio bytes in this payload.

## Unsupported Or Weak Facts

These facts are not reliably available today:

- A single canonical thread type.
- A single canonical thread state.
- Durable `createdByUser`.
- Durable `startedWithPrompt`.
- Durable `jsonMode` or `outputSchema` on every historical thread.
- Direct complete thread tree API.
- Subscriber count.
- Realtime active state from stored history alone.
- An `archived` boolean on raw app-server `Thread`.
- Arbitrary custom source filtering in all client paths.
- Current real counts from old audit docs without rerunning the audit.

## Test Coverage Summary

Tests explicitly cover broad human, automation, and unknown origin behavior.
Relay tests cover default interactive sources, explicit agent source scopes,
contradictory source metadata mapping to unknown, internal memory rows being
excluded, and broad/specific sub-agent matching.

Tests explicitly cover Dock row status vocabulary and raw-to-Dock status
mapping:

- active with no waiting flag -> `running`
- active with user input flag -> `needsInput`
- active with approval flag -> `needsApproval`
- `notLoaded` -> `dormant`
- `idle` -> `idle`
- `systemError` -> `error`

Tests also cover stale/offline/error/partial stream behavior, detail live state,
archive/restore behavior, multi-host isolation, sync-gap recovery, and the
controlled simulator `spawn-edge` path.

After the 2026-05-31 human-only implementation and manual-fork update, tests
also cover:

- The relay classifier accepting human-started root rows and human-started
  manual forks, while reporting rejected reason counts.
- Dock reconciliation enriching human-started rows with authoritative
  `thread/read` metadata before publishing cards.
- Dock reconciliation supplementing `thread/list` omissions from
  `session_index.jsonl` only after authoritative `thread/read` confirms a
  human-started row.
- Raw thread list/search ignoring caller-supplied source-kind broadening.
- Direct route preflight rejection for non-human IDs through the shared
  classifier.
- Diagnostic snapshot opt-in for rejected/non-human rows.
- Swift stream snapshots and deltas dropping non-human cards.
- Swift one-shot snapshot collection completing final windows after dropping
  non-human cards.
- Cached pinned rows staying hidden unless the pinned display proves a human
  origin.

The controlled simulator scenarios use real relay/client routes with fake
upstream app-server fixtures. They are good client-path proof, but they do not
prove current live Codex storage contents.

## Source-Checked Evidence From 2026-06-04

This section records the code paths checked for the wait/input correction.

Codex protocol:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
  defines `ThreadStatus` as `notLoaded`, `idle`, `systemError`, or `active {
  activeFlags }`.
- The same file defines `ThreadActiveFlag` as `waitingOnApproval` or
  `waitingOnUserInput`.
- `ThreadStatusChangedNotification` carries `{ threadId, status }`.
- `ServerNotification::ThreadStatusChanged` uses the JSON-RPC method
  `thread/status/changed`.
- `ThreadLoadedListResponse` carries loaded in-memory thread IDs, not the
  status union.
- Generated TypeScript confirms the wire strings:
  `ThreadStatus = { "type": "notLoaded" } | { "type": "idle" } | {
  "type": "systemError" } | { "type": "active", activeFlags: [...] }`;
  `ThreadActiveFlag = "waitingOnApproval" | "waitingOnUserInput"`;
  `TurnStatus = "completed" | "interrupted" | "failed" | "inProgress"`.

Codex app-server runtime status:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs`
  keeps `RuntimeFacts`: `is_loaded`, `running`, pending permission count,
  pending user-input count, and system-error state.
- `note_turn_started` sets `running = true`.
- `note_turn_completed`, `note_turn_interrupted`, and `note_thread_shutdown`
  clear active state.
- `note_system_error` clears running and pending counters, then sets
  thread-level system error.
- `note_permission_requested` increments the approval counter.
- `note_user_input_requested` increments the user-input counter.
- `loaded_thread_status` returns `idle` only after loaded/running/pending/system
  error checks prove there is no active turn, no pending request, and no system
  error.
- `resolve_thread_status` coerces `idle` or `notLoaded` to active with no flags
  when the returned thread still has a live `inProgress` turn.
- App-server tests cover active-with-no-flags, active-with-both-flags,
  user-input-only, system-error reset on the next turn, shutdown to `notLoaded`,
  and the fact that pending requests do not increment the running-turn count.

Codex app-server request handling:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/bespoke_event_handling.rs`
  maps `EventMsg::RequestUserInput` to `note_user_input_requested` and sends
  `item/tool/requestUserInput`.
- The same file maps command execution approval, file-change approval,
  permissions approval, and MCP elicitation through `note_permission_requested`.

Codex core session behavior:

- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/mod.rs` inserts a
  pending user-input request, emits `EventMsg::RequestUserInput`, marks turn
  metadata, and awaits the answer.
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/session/turn.rs` documents
  that `request_user_input` can intentionally pause a turn.

Dock relay and Swift projection:

- `scripts/dock-relay-state-views.mjs` maps raw `active + waitingOnApproval` to
  `needsApproval`, raw `active + waitingOnUserInput` to `needsInput`, raw
  `active` with no flags to `running`, raw `idle` to `idle`, raw `systemError`
  to `error`, and raw `notLoaded` to `dormant`.
- `scripts/dock-relay-thread-data.mjs` gives active waiting rows higher
  aggregation priority than active/running, idle, system error, and not loaded.
- `CodexDock/AppServer/DockThreadCardDTO.swift`,
  `CodexDock/Dock/DockModels.swift`, and
  `CodexDock/State/ThreadCardRowProjector.swift` preserve Dock statuses:
  `running`, `needsInput`, `needsApproval`, `idle`, `error`, `dormant`, and
  `unknown`.
- `CodexDock/Models/ServerRequestCard.swift` preserves request-card kinds:
  `commandApproval`, `fileChangeApproval`, `permissionsApproval`, `userInput`,
  `mcpElicitation`, and `unsupported`.

## Evidence Map

Core docs:

- `docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md`: app-server
  thread fields, `Thread.status`, source taxonomy, spawned-agent detection,
  forked threads, JSON/output-schema limits, turn states, and unsupported facts.
- `docs/CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md`: rollout JSONL,
  state DB, goals DB, spawn edges, archive detection, storage limits, and
  storage/app-server cross-checks.
- `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md`: older conceptual state map.
  It is still useful conceptually, but some UI labels are stale.
- `README.md`: current relay path, Dock stream ownership, and thread detail
  rehydrate flow.

Relay code:

- `scripts/dock-relay-source-filter.mjs`: detailed source classifier and
  default interactive source behavior.
- `scripts/dock-relay-human-thread-filter.mjs`: app-facing human-only policy,
  rejection reasons, and `-32043` JSON-RPC rejection helper.
- `scripts/dock-relay-state-store-human-filter.mjs`: persisted human-only SQL
  guards, rejected-card cleanup, live-lease cleanup, and app-facing state
  counts.
- `scripts/dock-relay-live-status-cache.mjs`: human-only live routing defense
  for endpoint lookup, live row lookup, and loaded-thread IDs.
- `scripts/dock-relay-thread-data.mjs`: raw route aggregation, live row
  collection, attention enrichment, and raw route forwarding.
- `scripts/dock-relay-state-views.mjs`: raw-to-Dock card projection, lane
  mapping, and status normalization.
- `scripts/dock-relay-state-engine.mjs`: active/default/all-source/archive
  reconciliation scopes and live leases.
- `scripts/dock-relay-state-store.mjs`: relay-local card storage, archive
  state, freshness, and card persistence.
- `scripts/dock-relay-state-snapshot.mjs`: richer audit/snapshot surface.
- `scripts/dock-relay.mjs`: JSON-RPC routing for Dock streams, Archive streams,
  raw thread routes, resume, focused turn routing, and server request forwarding.

Swift code:

- `CodexDock/AppServer/ThreadListDTO.swift`: raw thread DTO, source kinds,
  raw thread status, and active flags.
- `CodexDock/AppServer/DockThreadCardDTO.swift`: Dock card stream contract,
  card statuses, lane, source kind, archive state, freshness, and completeness.
- `CodexDock/Models/ThreadIdentityModels.swift`: human/automation/unknown
  origin model and subtypes.
- `CodexDock/State/ThreadCardRowProjector.swift`: current lossy mapping from
  Dock cards into row origins and row statuses.
- `CodexDock/State/HumanThreadCardPolicy.swift`: Swift defensive app-facing
  card and cached pinned display guards.
- `CodexDock/Dock/DockModels.swift`: Dock row statuses and source filters.
- `CodexDock/State/DockCardProjection.swift`: source/status filtering,
  idle hiding, search, and facets.
- `CodexDock/State/LocalThreadMetadataStore.swift`: pinned metadata origin
  cache, currently broad only.
- `CodexDock/State/ThreadDetailStore.swift`: detail load/resume/live/stale
  state model.
- `CodexDock/Models/ServerRequestCard.swift`: request-card kinds and statuses.
- `CodexDock/Models/ThreadEvent.swift`: event kinds and visibility categories.

Contracts and tests:

- `contract/dock/dock-thread-card.schema.json`: Dock card schema and enums.
- `scripts/dock-relay.test.mjs`: source filtering, normalized stream cards,
  live overlay, source scope, and relay route behavior.
- `CodexDockTests/AppServerClientTests.swift`: raw app-server DTO encoding and
  decoding, source kinds, detail/read/resume/archive paths.
- `CodexDockTests/DockStoreTests.swift`: Dock row state behavior and archive
  behavior.
- `CodexDockTests/DockStoreStreamTests.swift`: stream gap, stale, reconnect,
  and multi-host behavior.
- `CodexDockTests/ThreadDetailStoreTests.swift`: detail live and request-card
  behavior.
- `scripts/dock-relay-controlled-simulator-fixture.mjs`: controlled scenarios,
  including `spawn-edge`.
- `scripts/dock-relay-controlled-simulator-matrix.mjs`: required controlled
  simulator scenario list.

## Known Uncertainties

The page-size cap is inconsistent across docs, upstream app-server notes, and
current client relay constants/tests. This does not change the thread type or
state model, but it should be live-verified before relying on exact pagination
limits.

Historical audit counts in older docs are dated evidence. They should not be
quoted as current inventory without rerunning the relevant audit.

LLM-generated card labels are documented as future or planned behavior and are
not part of the current Dock card contract.
