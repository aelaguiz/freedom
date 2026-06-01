# Codex Dock Client Card And Thread Detail Complexity Audit

Date: 2026-05-31

Current UX intention:
[CODEX_DOCK_USER_INTENTION_2026-06-01.md](CODEX_DOCK_USER_INTENTION_2026-06-01.md),
[CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md](CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md)
and
[CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md](CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md).

Scope:

- Dock list cards and local list projection.
- Pinned row behavior.
- Thread detail event loading, rendering, filtering, and request-card behavior.
- Client-facing Swift plus the relay code that directly shapes card DTOs.

Net:

- The Dock list is not a simple flat list. It is a relay-backed card stream,
  a per-host stream table, local metadata, host alias resolution, a render
  projector, local filters, grouping lenses, and a separate pinned section.
- Pinning is thread-row metadata, not message metadata. I found no client logic
  that pins a row because a thread item is a `userMessage`.
- Separately from manual pinned rows, the detail screen can put a user prompt
  at the top even when it is not the latest message. That comes from the
  thread-detail event ordering code, not from Dock pinning.
- Thread detail is also not a flat transcript. It reads thread metadata, pages
  turns, resumes live events, buffers notifications during load, merges stream
  deltas, attaches request-card controls, filters events, and keeps stale rows
  visible across disconnects.

## What Is Not Happening

There is no SwiftUI view named `DockThreadCard`. The network shape is
`DockThreadCardDTO`, and the rendered UI row is `DockRowView`.

There is no client-side rule like "if the latest item is a user message, pin
the card." The Dock list does not inspect turn items at all before showing
overview rows. Overview rows come from relay-supplied `DockThreadCardDTO`
values, then Swift filters and projects those into `DockRowViewModel`.

User-message logic exists in thread detail, but it is filter/render logic:
`ThreadEventMessageFilter.messages` shows user messages, agent messages, and
request events by default. It does not pin anything.

There is, however, an artificial top-row behavior in thread detail. The top
visible message is not guaranteed to be the most recent message. For historical
turn data, the app can put the user prompt for the newest turn above the later
agent output in that same turn.

## Dock Card Pipeline

The Dock card path is:

1. Relay builds stream cards from thread list/read state, live leases, archive
   state, freshness, attention flags, source/lane inference, and summary
   fallback.
2. Swift subscribes with `dock/subscribe`, consumes `dock/update`, and requests
   `dock/resync` when the local stream contract is violated.
3. `ThreadCardTable` stores per-host stream state and applies snapshots/deltas.
4. `ThreadCardRowProjector` maps `DockThreadCardDTO` plus local metadata into
   `DockRowViewModel`.
5. `DockCardProjection` applies search, filters, idle hiding, pinned-row
   separation, newest/host/branch lenses, groups, summaries, and facets.
6. `DockView` renders pinned rows above the regular list, then renders the
   selected lens body.

Important code:

- `CodexDock/AppServer/AppServerMethods.swift`: method names such as
  `dock/subscribe`, `dock/update`, `dock/resync`, `thread/read`,
  `thread/turns/list`, `thread/resume`, `turn/start`, and `turn/steer`.
- `CodexDock/AppServer/DockThreadCardDTO.swift`: card DTO, card status,
  freshness, lane/source, relationship, and stream update DTO.
- `CodexDock/State/AppServerThreadCardStreamClient.swift`: stream
  subscription, update notification decode, and resync calls.
- `CodexDock/State/ThreadCardTable.swift`: per-host stream table, snapshot
  apply, delta apply, sequence/schema/window checks, stale/offline/error
  retention.
- `CodexDock/State/ThreadCardRowProjector.swift`: DTO-to-row projection and
  cached pinned row projection.
- `CodexDock/State/DockCardProjection.swift`: filters, search, pinned/body
  split, grouping, summaries, facets, and ordering.
- `CodexDock/Features/Dock/DockView.swift`: search, lenses, filters, pinned
  section, row tap navigation into detail.
- `CodexDock/Features/Dock/DockSharedViews.swift`: visual row card renderer.
- `scripts/dock-relay-state-views.mjs`: relay-side card normalization,
  title/summary fallback, status, source/lane, relationship, and ordering.
- `scripts/dock-relay-thread-data.mjs`: attention flags such as waiting on
  approval or user input.

## Human-Only Card Gate

The client defensively drops non-human cards even if the relay sends them.

`HumanThreadCardPolicy` allows only:

```swift
card.lane == .human && card.sourceKind == .human
```

That policy is applied in multiple places:

- Snapshot and delta handling in `ThreadCardTable`.
- Row projection in `ThreadCardRowProjector`.
- Cached pinned display revival in `HumanThreadCardPolicy`.

This means the source filter UI can still contain concepts such as agent or
unknown sources, but the normal production row pipeline filters those out before
they become visible rows.

## Pinned Row Behavior

Pinning is local metadata. It is not part of the relay protocol and not based
on thread turns.

Pinned state lives in `LocalThreadMetadata`:

- `isPinned`
- `pinnedAt`
- `pinnedOrder`
- `lastKnownPinnedDisplay`

When a row is pinned, `LocalMetadataEngine.setPinned` stores a cached display
snapshot. When a row is unpinned, it clears the pin fields and cached pinned
display. Pinned rows can also be reordered locally; `PinnedMetadataOrdering`
normalizes sparse or legacy order values into stable `0...n` ordering.

The display behavior is special:

- Pinned rows are split out of the normal body in `DockCardProjection`.
- The pinned section is rendered globally above the selected lens.
- Pinned rows are not duplicated inside `Newest`, host groups, or branch
  groups.
- Pinned rows have their own order: `pinnedOrder`, then `pinnedAt`, then stable
  identity.
- Pinned rows can remain visible when idle rows are otherwise hidden.
- Pinned rows can still be hidden by search/filter, and the UI shows a hidden
  pinned count.
- Cached pinned rows can reappear even when the live stream no longer has that
  card, as long as the cached display was human-facing and the host can still
  be resolved.

This is the main reason the Dock list feels more complex than a flat list. A
thread can be visible because it is live in the stream, or because local pinned
metadata revived a cached display.

## Filtering, Search, Grouping, And Sorting

`DockCardProjection` builds several row sets at once:

- Search-matched rows.
- Rows filtered with idle policy applied.
- Pinned rows.
- Hidden idle rows.
- Body rows, which exclude pinned rows.
- Visible rows used for summary accounting.
- Host groups.
- Branch groups.

Search checks fields such as title, host display name, host id, repository,
branch, summary, status label, local label, source/origin, and thread id.

Filters include:

- Host.
- Branch.
- Status.
- Repository query.
- Selected repositories.
- Source.
- Idle visibility.

The code exposes `DockFilterState.sortOrder`, and the filter UI exposes sort,
but projection effectively uses newest-first ordering. That looks misleading:
there is a sort setting shape, but I did not find multiple active sort modes in
the projection path.

Facets are built from all snapshot rows, not only the post-filtered rows. That
is reasonable for filter UI, but it means the filter surface can describe rows
that are not currently visible.

## Relay Influence On Cards

The relay does meaningful shaping before Swift ever sees a card.

Important relay behavior:

- `normalizedStatus` maps active state plus flags into `running`,
  `needsApproval`, `needsInput`, `idle`, `error`, `dormant`, or `unknown`.
- Attention flags such as waiting on approval or waiting on user input can make
  a thread appear active.
- `displaySummaryForThread` falls back through `displaySummary`,
  `latestSummary`, `summary`, `preview`, and title.
- The relay can infer `human` or `agent` lane/source.
- The relay currently emits root/fork-style relationship information.

So the client card is not a neutral raw thread record. It is already a relay
view model, then Swift applies another local projection layer.

## Thread Detail Pipeline

The detail screen is `SessionDetailView`, not `ThreadDetailView`.

The main path is:

1. `DockView` stores a tapped `DockRowViewModel` as `selectedDetailRow`.
2. Navigation creates `SessionDetailView` with the selected host, session, and
   thread identity.
3. `ThreadDetailStore.load()` connects and initializes the app-server client.
4. It starts observing connection state, live notifications, and JSON-RPC
   server requests.
5. It starts buffering live notifications.
6. It calls `thread/read` with `includeTurns: false`.
7. It pages all turns with `thread/turns/list`.
8. It normalizes historical thread/turn data into `ThreadEvent` values.
9. It calls `thread/resume` with `excludeTurns: true`.
10. It replaces/merges events, marks the detail live, then replays buffered
    live notifications.

Important code:

- `CodexDock/State/ThreadDetailStore.swift`: state machine, load, reconnect,
  background/foreground, live notification buffering, request-card state,
  composer state, request responses.
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`: event normalization
  storage, merge behavior, stream delta merging, active turn tracking.
- `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift`: render coalescing
  and filter state.
- `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`: event filtering,
  visible row cap, and request-card attachment.
- `CodexDock/Models/ThreadEvent.swift`: event kinds, message filters,
  newest-first ordering, historical item normalization, live notification
  normalization, and request-event normalization.
- `CodexDock/Models/ServerRequestCard.swift`: JSON-RPC server request to UI
  card mapping and response payloads.
- `CodexDock/Features/Session/SessionDetailView.swift`: detail shell, header,
  stale banner, composer, message list.
- `CodexDock/Features/Session/ThreadMessageListView.swift`: filter menu,
  event rows, and request controls.
- `CodexDock/Commands/ClientCommandEngine.swift`: `turn/start`, `turn/steer`,
  and JSON-RPC request responses.

## Thread Detail Event Filtering

The default detail filter is `Messages`.

That default shows:

- User messages.
- Agent messages.
- Request events.

It hides by default:

- Thinking/reasoning.
- Tooling.
- Command/output details.
- System rows.
- Unknown rows.

Those hidden rows can still exist in the normalized event list. The UI simply
does not show them until a broader filter is selected.

Ordering is newest-first using display date/group date, turn sequence, item
sequence, item key, event sequence, and id. This is a deliberate render order,
not just the input array order.

## Simulator Confirmation: Detail Message Order Is Wrong

I ran the app on the iPhone 17 simulator and confirmed the behavior in the
real UI.

Commands used:

```bash
rtk make services
rtk make app SIM='iPhone 17'
```

Device/app checked:

- Simulator: `iPhone 17`
- Simulator UDID: `DEF1631B-7125-43C6-BFA3-4423BF103C91`
- App bundle: `com.aelaguiz.CodexDockApp`
- Dock root accessibility value during the check: `pinned=0`

Observed behavior:

- In thread `019e7e31-e732-7962-893e-49915e2e16d2`, the first visible detail
  card under the composer was `User message`, and the next visible card below
  it was `Agent message`.
- In thread `019e79b7-2eb3-7302-91aa-4cd50f2d8094`, the same pattern appeared:
  `User message` was the first visible card, then `Agent message` appeared
  below it.
- In thread `019e7dad-b846-7773-bfa5-61216840ad3d`, the same user-above-agent
  pattern appeared again. The underlying turn data for that thread also showed
  a long turn lasting `3154` seconds, with item types `userMessage,
  agentMessage`. That is the production shape that makes an older user prompt
  look stuck above later agent work.
- The Dock rows were not manually pinned. The Dock root reported `pinned=0`,
  and the tapped rows reported `Not pinned`.

Screenshot evidence was saved outside the repo:

- `/tmp/codex-client/20260531T-thread-detail-order-audit/amir-thread-top-user-then-agent.png`
- `/tmp/codex-client/20260531T-thread-detail-order-audit/home-thread-top-user-then-agent.png`
- `/tmp/codex-client/20260531T-thread-detail-order-audit/codex-thread-types-top-user-above-agent.png`

Root cause:

- `ThreadEventNormalizer.events(fromTurn:)` picks one `defaultDate` for the
  whole turn from `startedAt` or `completedAt`.
- `ThreadEventNormalizer.events(fromItem:)` gives every item in that turn the
  same `date` and `displayGroupDate`.
- `ThreadEventDisplayOrder` sorts by date descending first. When dates tie, it
  sorts by newer `turnSequence`, then lower `itemSequence`.
- Historical turn items usually have the user prompt first and the agent answer
  later. Because lower `itemSequence` wins, the user prompt sits above the agent
  answer inside that turn.
- This is not limited to the first message in a thread. If a turn runs for a
  long time, the first user item in that turn can be old while later agent work
  in the same turn is much more recent. The client still keeps the old user item
  above the later same-turn rows because it has no per-item display timestamp
  and uses ascending item order as the tie-break.
- `ThreadDetailRenderProjector` takes `filteredEvents.prefix(visibleLimit)`.
- `ThreadMessageListView` renders those rows in order.

So the visible top row means "first visible item in the newest display-dated
turn group," not "latest message in the transcript." In long back-and-forth
threads, that can put an older user prompt above the actual recent agent work.
That is artificial ordering from the client code. It is separate from manual
Dock pinning.

Additional risky path:

- Live `item/started` and `item/completed` notifications are normalized with
  `defaultDate: now`.
- If one of those notifications matches an existing historical event by exact
  event id or by `(turnID, itemID, kind, visibility)`, `ThreadEventIndex`
  replaces the old event with the newly normalized event.
- That can also promote an older event to the top because the replacement event
  carries the notification receive time, not the original item time.

This behavior is also encoded in tests. `ThreadEventNormalizerTests` builds a
newer turn containing `userMessage`, `agentMessage`, and command output, then
expects display order equivalent to user request first, agent answer second,
and command/output after that.

## Active Turn And Composer Behavior

The composer does not always start a new turn.

`ClientCommandEngine.sendDraft` does this:

- If `activeTurnID` exists, send `turn/steer`.
- If no active turn exists, send `turn/start`.

`ThreadDetailDataEngine` sets `activeTurnID` from in-progress turn status and
live turn notifications. So a user draft can become a steer command into an
active turn instead of a new user message.

This is another separate "special with user messages" behavior. It is not
pinning and it is not the top-row issue, but it is still non-flat behavior: the
same composer text maps to different protocol calls depending on live turn
state.

## Request Cards

Request cards are two-layered:

- `ThreadEvent` can contain a `.request` event row.
- `ServerRequestCard` stores the interactive controls and response state.

`ThreadDetailRenderProjector` attaches a request card to an event by exact
request id or by a stream key based on turn/item identity. This means an event
can exist without controls, and controls can exist only when a matching card is
available.

Supported request card kinds include:

- Command approval.
- File change approval.
- Permissions approval.
- User input.
- MCP elicitation.
- Unsupported request.

Historical `fileChange` thread items normalize as `.request` events, but they
do not automatically get live controls unless a matching JSON-RPC server request
card also exists.

## Stale, Offline, And Recovery Behavior

The client keeps data visible instead of clearing it when state gets stale.

Examples:

- Dock rows can remain while host status becomes partial, stale, offline, or
  error.
- Thread detail preserves events and draft state across connection loss.
- Backgrounding marks loaded detail stale with a background reason.
- Foreground/reconnect rehydrates by reading and resuming again.
- Resume failure keeps historical read events and marks the detail stale.

This is useful, but it means the UI can show rows that are no longer fully live.
That is intentional in the current design.

## Suspicious Or High-Risk Complexity

These are not all bugs. They are places where behavior is surprising, brittle,
or easy to misread.

1. Pinned rows are global, not part of the selected lens body.

   They render above newest/host/branch views and are excluded from normal body
   rows. A caller looking only at `projection.rows` will miss pinned rows.

2. Pinned idle rows override the normal idle-hiding behavior.

   An idle pinned row can stay visible even when idle rows are hidden. This is
   tested behavior, but it can make the list look inconsistent.

3. Cached pinned rows can revive rows that are absent from the live stream.

   This is intentional and tested. It also means the UI can show a row because
   local metadata remembers it, not because the relay currently streams it.

4. Summary counts include pinned/body concepts differently than the row arrays.

   `visibleRows` is built from pinned plus body rows for summary accounting,
   while `rows` for a lens excludes pinned rows. That split is easy to misuse.

5. Sort settings look broader than actual sort behavior.

   `DockFilterState.sortOrder` and filter UI shapes exist, but projection uses
   newest/order-key behavior. This can confuse future work.

6. Source filters can imply agent/unknown rows, but production projection drops
   non-human cards before rows exist.

   Tests cover non-human dropping. Some source filter surfaces still carry
   concepts that may not produce rows in the normal app path.

7. `DockThreadCardRelationship.spawned` decodes but is effectively collapsed.

   Swift maps `.spawned` to `.root`, and the relay appears to emit root/forked
   relationship values. If spawned becomes meaningful, the current UI will hide
   that distinction.

8. `summarySource` is decoded but not surfaced.

   Swift mostly uses `displaySummary`. Search and rows do not expose whether a
   summary came from preview, latest summary, title fallback, or another source.

9. Detail rehydrate merges instead of replacing.

   If the server removes an event, reconnect may keep a stale local row because
   the rehydrate path merges normalized events into the existing event index.

10. Buffered live events can be lost from the stale view when initial resume
    fails.

    The load path buffers live notifications during the initial read/resume
    window. On resume failure, it keeps read events and marks stale, but the
    buffered live events are not applied in that failure path.

11. The detail render window is capped.

    `ThreadDetailRenderProjector` takes a prefix of the filtered events using
    the visible limit. I did not find a load-more path in this render layer, so
    older rows can exist in state but not in the visible list.

12. User-input request cards may hide useful prompt text.

    `ServerRequestCard.make` stores user-input prompt text in card fields, but
    the row renderer primarily shows the event title/body and card detail. If
    those fields do not line up, the actual question can be less visible than
    expected.

13. Active-turn steering depends on a protocol string.

    The active-turn detector checks for `inProgress`. If the protocol spelling
    changes, composer sends could start new turns instead of steering the active
    turn.

14. Historical request-looking events and live request controls are separate.

    This is flexible, but it means request rows and actionable controls can get
    out of sync if ids or turn/item keys differ.

15. Host identity aliasing affects local metadata.

    Local pin/label/rail metadata can migrate across host aliases. This is
    necessary for logical host ids and endpoint ids, but it makes pin
    persistence dependent on host identity resolution.

16. Detail ordering can promote older user prompts above newer work.

    The simulator confirms the detail UI can put a user prompt above later
    agent output from the same turn. The cause is turn-level dates plus
    ascending item order inside equal-date turns. In a long turn, that user
    prompt can be much older than the rows beneath it.

17. Live full-item notifications can refresh old event timestamps.

    `item/started` and `item/completed` notifications use `now` as their
    fallback display date. When they replace an existing historical event, the
    old event can be reinserted as if it were newly current.

## Tests That Pin Down Current Behavior

Useful tests:

- `CodexDockTests/DockStoreStreamTests.swift`: stream snapshots/deltas,
  non-human card dropping, window partial state, and stream resync behavior.
- `CodexDockTests/DockStoreTestsProjection.swift`: newest ordering, host/branch
  grouping, idle hiding, pinned split, hidden pinned counts, cached pinned rows,
  logical host resolution, and fork badges.
- `CodexDockTests/ThreadDetailStoreTests.swift`: load path, live notification
  buffering, paged turns, repeated cursor failure, resume failure, human-only
  rejection, reconnect behavior, server requests, draft send behavior, and
  voice behavior.
- `CodexDockTests/ThreadDetailDataEngineTests.swift`: event sorting, stream
  delta merging, and active turn tracking.
- `CodexDockTests/ThreadDetailRenderProjectorTests.swift`: request-card
  attachment to request rows.
- `CodexDockTests/ThreadEventNormalizerTests.swift`: default message filter,
  hidden event kinds, and live event normalization.
- `CodexDockTests/ServerRequestCardTests.swift`: request-card kind mapping and
  response payloads.
- `CodexDockTests/ClientCommandEngineTests.swift`: `turn/start`, `turn/steer`,
  and server request response calls.
- `scripts/dock-relay*.test.mjs`: relay card contract, state parity, and
  stream behavior.

## Short Version

The odd behavior is real, but it is not "pin user messages."

The Dock list has a complex local projection layer. Pinned rows are local
thread metadata with cached display snapshots and their own global section.
Thread detail has a separate complex state machine for historical reads, live
resume, stream deltas, request cards, filtering, active-turn steering, voice,
and stale/offline retention.

The specific ordering issue is confirmed in the iPhone 17 simulator: thread
detail can put an older user prompt above newer agent work. That happens
because the client gives every item in a historical turn the same display date
and then sorts tied items by ascending item sequence. A second risky path can
also promote old rows when live full-item notifications replace historical
events with `now` as the display date.

If the goal is to make the client easier to reason about, the biggest
simplification targets are pinned cached row revival, pinned/body split
semantics, unused-looking sort/source concepts, request-event/request-card
duplication, detail event ordering, and the detail rehydrate merge behavior.
