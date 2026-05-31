# Codex Dock Thread Types And States Reference

Date: 2026-05-31

Status: definitive working reference for current UX planning.

Scope: Codex Dock client, Node Dock relay, contract files, tests, and existing
thread-state docs. This doc records the 2026-05-31 human-only implementation.

## Net Answer

There is no single durable `threadType` or `threadState` field that answers the
whole question. The underlying Codex data has several independent axes:
origin, relationship, runtime status, archive membership, persistence, goal
state, request-card state, turn state, and relay freshness.

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

For richer UX, such as a future separate machine/agent area, the relay should
add a separate diagnostic or product surface. Normal Dock cards should not
quietly return to mixed human and non-human rows.

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

## Runtime Status States

Raw app-server thread status and Dock card status are related but not identical.

| Raw app-server status | Raw flag | Dock card status | UX meaning |
| --- | --- | --- | --- |
| `active` | `waitingOnApproval` | `needsApproval` | Agent is blocked on an approval request. |
| `active` | `waitingOnUserInput` | `needsInput` | Agent is blocked on user input. |
| `active` | no waiting flag | `running` | Agent is actively running or live. |
| `idle` | none | `idle` | Thread is loaded but not currently active. |
| `systemError` | none | `error` | Backend has a thread-level system error. |
| `notLoaded` | none | `dormant` | Thread is stored but not loaded into runtime. |
| unknown string | any | `unknown` | Client should preserve safe fallback behavior. |

`notLoaded` is important: it is not the same thing as archived, deleted, or
offline. It means the thread is known in history but not currently loaded into
the app-server runtime.

`thread/closed` is also separate. It means a runtime session closed or unloaded.
It is not an archive event.

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

Current request-card kinds:

- `commandApproval`
- `fileChangeApproval`
- `permissionsApproval`
- `userInput`
- `mcpElicitation`
- `unsupported`

Current request-card statuses:

- `pending`
- `responding`
- `resolved`
- `failed`

These should drive per-thread action UI such as approval buttons or input
forms. They should not be used as origin labels.

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

These are useful for Timeline and Detail UX. They are not enough by themselves
to classify thread origin.

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
| Is this currently active/running? | Yes from raw `Thread.status.active` and relay live leases. | Yes as `running`/attention status. | High for current projection, subject to freshness. |
| Is it waiting on the user? | Yes from active flags or pending server requests. | Yes as `needsInput` or `needsApproval`. | High for current projection, subject to freshness. |
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
