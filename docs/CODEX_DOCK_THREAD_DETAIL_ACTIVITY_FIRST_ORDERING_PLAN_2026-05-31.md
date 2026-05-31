# Codex Dock Thread Detail Activity-First Ordering Plan

Date: 2026-05-31

Status: implemented, reviewed, and verified.

## Intention

Opening a thread shows the most recent meaningful thing first, period.

That means:

- If Codex just replied, the Codex reply is at the top.
- If Codex is waiting on the user, the request is at the top.
- If the user just sent a message and Codex has not answered yet, the user
  message is at the top.
- Older messages never appear above newer meaningful activity.
- Manual Dock row pinning is separate. It does not affect thread detail order.

## Scope

This plan covers the default thread detail message list in the iOS client.

In scope:

- Historical thread detail rows built from `thread/turns/list`.
- Live rows built from item notifications and JSON-RPC server requests.
- The default visible message filter, which shows user messages, agent
  messages, and request rows.
- The ordering model that decides which row appears first.

Out of scope:

- Dock list card pinning.
- Dock list grouping, search, and filters.
- New UI toggles or timeline modes.
- A server or relay protocol change for the first patch.
- Raw rollout JSONL parsing from Swift.
- Full conversation redesign or turn-grouped transcript UI.

## Current Problem

The current client can show an older user prompt above newer Codex activity.
That is not manual pinning. It comes from the thread detail event ordering code.

Root cause:

- `CodexDock/Models/ThreadEvent.swift:347` picks one historical date for a whole
  turn using `startedAt` before `completedAt`.
- `CodexDock/Models/ThreadEvent.swift:392` and
  `CodexDock/Models/ThreadEvent.swift:415` give every item in that turn the
  same row date and `displayGroupDate`.
- `CodexDock/Models/ThreadEvent.swift:162` sorts rows newest-first by that date.
- When dates tie, `CodexDock/Models/ThreadEvent.swift:173` to
  `CodexDock/Models/ThreadEvent.swift:176` puts lower `itemSequence` first.
  Historical turns usually put the user item before the agent item.
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:137` and
  `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:190` keep the index in
  that computed order.
- `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift:10` takes the
  prefix of that already-ordered event list, so a bad top row becomes the
  visible top row.

The user-visible result is wrong: the top row can mean "first item in the
newest turn group," not "latest meaningful activity."

There are three additional risky paths:

- Live `item/started` and `item/completed` notifications currently normalize
  with the local receive time when a protocol timestamp is not used.
- When those notifications replace an existing historical event by id or by
  stream merge key, an old event can be reinserted as if it just happened.
- Streaming delta merge appends new text to the existing row body but keeps the
  first delta's timestamp. That can leave active Codex output below a newer
  request or message even after Codex has just produced text.
- `turnSequence` is a Dock projection index, not a chronology. Because
  `thread/turns/list` defaults to descending order, `turnSequence = 0` normally
  means "first returned turn," not "oldest turn." It can only be used as a
  deterministic fallback after real dates, and its direction must match the
  received API order.

## Data Truth

The best available data source is still `thread/turns/list` plus live
notifications.

Facts from the local data reference:

- `thread/turns/list` defaults to newest-first turn pagination and summary
  items.
- Swift currently sends only `threadId`, `cursor`, and `limit` through
  `ThreadTurnsListParams` in `CodexDock/AppServer/ThreadDetailDTO.swift:13`.
- Historical `ThreadItem::UserMessage` and `ThreadItem::AgentMessage` do not
  carry their own timestamps.
- Historical turns do carry `Turn.startedAt` and `Turn.completedAt` in Unix
  seconds.
- Live item lifecycle notifications can carry `startedAtMs` and
  `completedAtMs` in Unix milliseconds.
- Request cards are live JSON-RPC requests and have the local `requestedAt`
  time in `ServerRequestCard`.

Therefore the canonical client-side ordering inputs are:

- user-message historical time: containing turn `startedAt`
- agent-message historical time: containing turn `completedAt`, falling back to
  `startedAt`
- historical file-change/request-looking row time: containing turn
  `completedAt`, falling back to `startedAt`
- live item time: `completedAtMs` for completed items, `startedAtMs` for
  started items, read from the notification params, then local receive time only
  as a fallback
- live request time: request params `startedAtMs` when present, then local
  receive time, with the same value used by the corresponding request event and
  request card
- explicit turn page direction: request `sortDirection: "desc"` from
  `thread/turns/list` so local same-date tie-breakers are tied to an explicit
  API contract, not an unstated server default

Do not use these as chronological truth:

- item ids
- request ids
- Dock `turnSequence`, `itemSequence`, or `eventSequence`
- Dock card pin state
- relay stream sequence numbers
- `latestSummary`

## Target Ordering Contract

The default detail list is activity-first.

Ordering rules:

1. Filter to meaningful rows first: user messages, agent messages, and request
   rows.
2. Sort by each row's activity time descending.
3. If two rows have the same activity time, use deterministic tie-breaks only
   to keep the UI stable. Ties must not encode "user prompt before agent
   answer" as a recency rule.
4. Keep visible timestamps honest. Do not fake a user prompt's display time as
   the agent answer completion time just to sort it lower.

Historical summary-turn examples:

- Completed turn with user prompt and final Codex answer:
  - user row activity time = `startedAt`
  - Codex row activity time = `completedAt`
  - expected top row = Codex answer
- In-progress turn with only a user prompt:
  - user row activity time = `startedAt`
  - expected top row = user message until Codex produces newer activity
- In-progress turn with a live Codex delta or completed item:
  - Codex row activity time = live item timestamp or local receive fallback
  - expected top row = Codex activity
- Live request:
  - request row activity time = request receive time
  - expected top row = request if it is newest

## Elegant Path

Keep the fix in the existing thread detail model path.

The owner should stay:

- `CodexDock/Models/ThreadEvent.swift`
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`
- focused tests under `CodexDockTests`

Do not add a new service, cache, screen mode, relay endpoint, or parallel
ordering pipeline.

Recommended implementation shape:

1. Separate display time from activity sort time.

   Add `activityDate: Date?` to `ThreadEvent`. Keep `date` as the visible row
   timestamp. Make `ThreadMessageSemantics.activityDate(for:)` and
   `ThreadEventDisplayOrder` use `activityDate` first, then fall back to
   `displayGroupDate`, then `date`.

   Reason: the app needs to sort a user prompt by when it happened without
   pretending the prompt happened at the answer completion time.

2. Assign historical activity dates by item meaning.

   In `ThreadEventNormalizer.events(fromTurn:)`, derive:

   - `turnStartedAt = startedAt`
   - `turnCompletedAt = completedAt`

   In `events(fromItem:)`, set row activity time by item type:

   - `userMessage`: `turnStartedAt`
   - `agentMessage`: `turnCompletedAt ?? turnStartedAt`
   - `plan` and `reasoning`: `turnCompletedAt ?? turnStartedAt`
   - `commandExecution` command/output rows: `turnCompletedAt ?? turnStartedAt`
   - `fileChange` request-looking row: `turnCompletedAt ?? turnStartedAt`
   - unknown rows: existing fallback, because they are not default visible

   This preserves the best available historical meaning without needing
   per-message timestamps that the protocol does not expose.

3. Make turn pagination direction explicit.

   Add `sortDirection` to Swift `ThreadTurnsListParams` and pass `"desc"` from
   `ThreadDetailStore.readAllTurns`. This uses an existing app-server parameter;
   it is not a relay or server protocol change.

   Reason: same-date fallback order can only be stable if the client pins the
   page direction it expects.

4. Use live protocol timestamps when present.

   For `item/started`, prefer params-level `startedAtMs`.
   For `item/completed`, prefer params-level `completedAtMs`.
   Use local `now` only when the notification does not carry a protocol
   timestamp.

   This prevents an old historical event from being promoted just because a
   replacement notification arrived later.

   For JSON-RPC server requests, prefer params-level `startedAtMs` when present,
   then fall back to `now`. Use the same resolved request time for both
   `ThreadEventNormalizer.event(from request:)` and
   `ServerRequestCard.make(from:)`.

5. Make tie-breakers stable, not semantic.

   After activity date, keep deterministic tie-breaks for stable UI ordering.
   Same-turn equal-date ties in the default message view should not force the
   user prompt above the agent answer.

   Tie-break requirements:

   - Do not treat `turnSequence` as a Codex-origin chronological field.
   - When `thread/turns/list` returns newest-first turns, lower turn sequence is
     the newer returned turn.
   - Change the same-date cross-turn comparator accordingly; the current
     `leftTurn > rightTurn` direction is wrong under descending turn pages.
   - For same-turn equal-date ties in an activity-first list, later
     `itemSequence` should beat earlier `itemSequence`.
   - For multiple UI events from one item, later `eventSequence` should beat
     earlier `eventSequence` when the two rows represent later output after
     earlier command/request context.

6. Keep filtering and rendering simple.

   `ThreadDetailRenderProjector` should keep filtering and taking the visible
   prefix. It should not learn ordering rules. The ordered event list should
   arrive from `ThreadDetailDataEngine`.

7. Update streaming merge recency.

   When two streaming deltas merge, preserve the combined body and update the
   row's `activityDate` to the newest delta's activity date. If the streaming
   row's visible `date` still represents "last updated," update that too;
   otherwise keep visible `date` separate and honest. This keeps live Codex
   output at the top when it is actively arriving without turning display time
   into fake history.

8. Leave protocol expansion as a named follow-up.

   If exact historical per-item ordering becomes necessary, the better server
   improvement is to expose item-level `activityAtMs` from app-server history.
   That is not needed for the first client patch because turn `startedAt` and
   `completedAt` already fix the visible wrong-order bug.

## Complexity To Remove Or Avoid

Avoid:

- A new "latest message" side channel.
- A second detail list sorted differently from the event index.
- UI-only sorting in SwiftUI views.
- A user preference or toggle for this.
- Relay-side card changes.
- Raw rollout JSONL reads in the phone app.
- Ordering by ids, request ids, stream sequence numbers, or Dock pin metadata.
- Broad DTO modeling of every app-server thread item just to fix ordering.
- New persistent local metadata for message timestamps.
- Relying on implicit app-server defaults when the Swift client depends on
  newest-first turn pages.

Clean up while implementing:

- Rename or document `displayGroupDate` if it remains, because it currently
  acts like a sort date and a display grouping date at the same time.
- Update tests that currently assert same-turn `userMessage` above
  `agentMessage`.
- Keep request event and request card timestamps aligned so the row and controls
  do not drift.

## Test Plan

Smallest useful test pass:

```bash
rtk swift test --filter ThreadEventNormalizerTests
rtk swift test --filter ThreadDetailDataEngineTests
rtk swift test --filter ThreadDetailRenderProjectorTests
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter AppServerClientTests
```

Manual/runtime proof after the Swift change:

```bash
rtk make services
rtk make app SIM='iPhone 17'
```

Required test cases:

- Historical completed turn with `userMessage` then `agentMessage`, where
  `startedAt` is much older than `completedAt`: Codex answer sorts above user
  prompt.
- Historical in-progress turn with only `userMessage`: user message sorts top
  when it is newest meaningful activity.
- Historical newer request row: request sorts above older messages.
- `ThreadTurnsListParams` encodes `sortDirection: "desc"` for detail reads.
- Live request event and `ServerRequestCard` share the same requested time.
- Live request event and `ServerRequestCard` use params-level `startedAtMs`
  before local `now` when the request includes it.
- Live `item/started` uses params-level `startedAtMs` when present.
- Live `item/completed` uses params-level `completedAtMs` when present.
- Replacing a streaming delta with a full completed item keeps the item ordered
  by lifecycle timestamp, not accidental receive time when protocol time exists.
- Merging a later streaming delta updates the row's activity time while keeping
  the merged body.
- Filtering with `ThreadDetailMessageFilter.default` keeps activity-first order
  after hiding thinking/tooling rows.
- Same-second turns remain stable and respect the received newest-first turn
  page order.
- Opening a pinned versus unpinned Dock row for the same thread produces the
  same detail event order.

## Parallel Review Ledger

Native parallel review was requested and started on 2026-05-31.

Scopes:

- Event ordering and render projection:
  `CodexDock/Models/ThreadEvent.swift`,
  `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`,
  `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`,
  `CodexDock/Features/Session/ThreadMessageListView.swift`, and focused tests.
- Thread detail store, live merge, requests, and reconnect behavior:
  `CodexDock/State/ThreadDetailStore.swift`,
  `CodexDock/State/ThreadDetailStore+Voice.swift`,
  `CodexDock/Models/ServerRequestCard.swift`,
  `CodexDock/Commands/ClientCommandEngine.swift`, and focused tests.
- App-server data and protocol source of truth:
  `docs/CODEX_APP_SERVER_THREAD_MESSAGE_TURN_DATA_REFERENCE_2026-05-31.md`,
  `docs/CODEX_DOCK_TIME_ORDER_UX_REFERENCE_2026-05-31.md`,
  `CodexDock/AppServer/ThreadDetailDTO.swift`,
  `CodexDock/AppServer/JSONRPC.swift`, and relay docs/scripts when relevant.

Synthesis:

- All review slices agreed that manual Dock row pinning does not affect thread
  detail event order.
- All review slices agreed that the owner should stay in the existing
  `ThreadEvent` / `ThreadDetailDataEngine` path.
- Event ordering review confirmed the current tests encode the wrong behavior:
  same-turn `userMessage` appears above later `agentMessage`.
- Store/live review confirmed request cards should stay sidecar controls only;
  request-card array order, Dock pin order, and Dock card order should not sort
  detail rows.
- Store/live review also found the streaming-delta merge recency problem:
  merged deltas keep the first delta's timestamp.
- Protocol review confirmed there is no durable per-message timestamp or
  message ordinal from Codex history, so the client must derive order from turn
  timestamps and live lifecycle/request timestamps for now.
- Protocol review also confirmed `thread/turns/list` defaults to newest-first
  turns, which means Dock's `turnSequence` is a local received-order index and
  must not be treated as "larger means newer."

## External Review Results

`$plan-audit` result:

- Verdict: `ready`
- Audit log:
  `docs/CODEX_DOCK_THREAD_DETAIL_ACTIVITY_FIRST_ORDERING_PLAN_2026-05-31_PLAN_AUDIT.md`
- Blocking findings: none

`$fresh-consult` result:

- Runtime/model/effort:
  `runtime=agent`, `model=composer-2.5-fast`,
  `effort=encoded-in-model`
- Verdict: `pass-with-notes`
- Run directory:
  `/tmp/fresh-consult/codex-dock-activity-first-ordering-20260531T154022Z-hRdQDt`
- Blocking findings: none
- Non-blocking notes folded into this plan:
  params-level live item timestamps, request `startedAtMs` fallback to local
  receive time, explicit same-date `turnSequence` comparator direction, and
  streaming merge `activityDate` semantics.

## Review Status

Completed:

- Native parallel agent synthesis.
- `$plan-audit` plan-readiness audit:
  `docs/CODEX_DOCK_THREAD_DETAIL_ACTIVITY_FIRST_ORDERING_PLAN_2026-05-31_PLAN_AUDIT.md`
  verdict `ready`.
- `$fresh-consult` using Cursor Agent `composer-2.5-fast`:
  `/tmp/fresh-consult/codex-dock-activity-first-ordering-20260531T154022Z-hRdQDt`
  verdict `pass-with-notes`, blockers `none`.
- Implementation in Swift model/store/test paths.
- `$plan-audit` implementation check.
- `$thermo-nuclear-code-quality-review`.
- Final focused Swift test pass and `rtk make app SIM='iPhone 17'` pass.

Pending:

- None for the implementation plan.
