# Codex Dock Client Order Root Cause Worklog - 2026-05-30

Status: investigation evidence, no production code changes.
Last updated: 2026-05-30T20:52:43Z.

## Scope

This pass investigated why the iPhone 14 path can show old sessions at the top,
large apparent row counts, and "No message preview" rows even after the relay
state engine had earlier proven full app-server-listable coverage.

Physical iPhone 14 testing was not run in this pass. The evidence below uses
the live local app-server and Dock relay, plus repository source. That is enough
to isolate the data-contract failure before the UI rendering layer.

## Short Answer

The current app-facing relay data is fresh and ordered, but the Swift client
does not preserve that order. The client re-sorts Dock rows by
`messageUpdatedAt`, and the live relay rows currently have no
`messageUpdatedAt` and no `messageSummary` for any session.

That makes "Newest" collapse into a fallback ID/title sort, which can put old
threads first. The same missing field split makes cards display
"No message preview" even though the relay row has a non-empty `summary`.

## Live Evidence

### Service status

Both local services were already up:

```bash
rtk make app-server-status
rtk make dock-relay-status
```

The app-server status check reported the raw app-server ready on
`127.0.0.1:4500`. The Dock relay status check reported `snapshotOK true` on
the relay path at `:4510`.

### Direct app-facing relay stream probe

A direct WebSocket probe against `ws://127.0.0.1:4510` called
`dock/subscribe`, then consumed follow-up `dock/update` catch-up windows for
five seconds.

Observed result:

```text
initial.complete: false
initial.totalRows: 1629
initial.window: { offset: 0, limit: 500, rowCount: 500, nextOffset: 500 }
final.sessionCount: 1629
final.complete: true
final.window: { offset: 1559, limit: 500, rowCount: 70, nextOffset: null }
missing.messageUpdatedAt: 1629
missing.messageSummary: 1629
missing.summary: 0
missing.updatedAt: 0
```

The relay's as-received top rows were recent because each row had fresh
`updatedAt` and the relay preserved its stored Dock order. The Swift-equivalent
client re-sort put old rows first because every `messageUpdatedAt` was `null`,
so the sort fell back to row ID.

Representative old top row after Swift-equivalent sorting:

```text
threadID: 019e5b34-65ab-7183-8da6-641f75464230
updatedAt: 1779646825
messageUpdatedAt: null
```

The key point is not that one field is missing on one row. It is missing on all
1629 live app-facing relay rows in this probe.

A second post-consult probe saved to
`/tmp/codex-client/client-order-live-probe-20260530T2055Z.json` saw one more
thread arrive during the investigation and reproduced the same shape:

```text
observedAt: 2026-05-30T20:52:43.050Z
finishReason: complete
initial.sessionCount: 500
initial.totalRows: 1630
updatesReceived: 13
final.sessionCount: 1630
final.complete: true
missing.summary: 0
missing.updatedAt: 0
missing.messageSummary: 1630
missing.messageUpdatedAt: 1630
```

The second probe also showed the relay's as-received top row was the current
investigation thread, while the Swift-equivalent re-sort started with old
`019e516b...` rows from 2026-05-22-era work.

### Tests

Dock store tests passed:

```bash
rtk swift test --filter DockStoreTests
```

Result: 48 tests passed.

Relay tests passed:

```bash
rtk npm run test:relay
```

Result: 117 tests passed.

These passes do not disprove the bug. Current Swift and relay test fixtures
usually populate `messageSummary` and `messageUpdatedAt`, so the tests exercise
a cleaner contract than the live app-server provides.

### Parity harness

The live parity command was:

```bash
rtk node -- scripts/dock-relay-state-parity.mjs --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-client-order-investigation.json --summary-only
```

It exited 0 but reported `ok: false`.

Important reported values:

```text
relay.threadCount: 1629
active:allSourceKinds.rowCount: 1629
sqlite.count: 1631
sqlite.appServerListable: 1630
sqlite.appServerNotListable: 1
dockParity.sessionCount: 500
expectedActiveListableCount: 1630
missingActiveListableFromDock: 1130
codexOrderStableMismatches: 0
loadedStatusCompared: true
```

The `dockParity.sessionCount: 500` result is a harness limitation for the
current windowed stream contract. The parity harness calls `dock/subscribe` once
and closes the connection. It does not consume the follow-up `dock/update`
catch-up windows. The direct app-facing stream probe did consume those windows
and reached 1629 rows with `complete: true`.

This means the parity harness currently proves only the initial subscribe
window, not the full client stream lifecycle.

## Source Evidence

### Relay order is stored separately from message recency

The relay store returns Dock rows by `dock_order`, then `updated_at_ms`, then
thread ID:

```text
scripts/dock-relay-state-store.mjs:340
ORDER BY t.dock_order ASC, t.updated_at_ms DESC, t.thread_id ASC
```

That means the relay has an explicit app-facing ordering model.

### Relay has `summary`, but message fields depend on missing upstream fields

`normalizeThread` builds `summary` from app-server thread fields, but only
copies `messageSummary` and `messageUpdatedAt` if those fields already exist on
the upstream thread object:

```text
scripts/dock-relay-state-views.mjs:263
summary: firstBoundedText([thread?.latestSummary, thread?.preview]) || titleForThread(thread)

scripts/dock-relay-state-views.mjs:264-265
messageSummary: boundedText(thread?.messageSummary)
messageUpdatedAt: optionalNumber(thread?.messageUpdatedAt)
```

The current Codex app-server protocol `Thread` shape has `preview` and
`updatedAt`, but no `messageSummary` and no `messageUpdatedAt`:

```text
/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts:23
preview: string

/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/schema/typescript/v2/Thread.ts:39
updatedAt: number
```

`ThreadListResponse` is just thread rows plus cursors:

```text
/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/schema/typescript/v2/ThreadListResponse.ts:6
data: Array<Thread>
```

So the relay is expecting optional fields that the live upstream contract does
not currently promise.

### Swift ignores relay order and sorts by missing message recency

`DockSessionTable.sortedSessions(for:)` sorts by `messageUpdatedAt`, not by the
relay's received order, `dock_order`, or `updatedAt`:

```text
CodexDock/State/DockSessionTable.swift:263-268
let lhsUpdated = lhs.messageUpdatedAt ?? Int64.min
let rhsUpdated = rhs.messageUpdatedAt ?? Int64.min
if lhsUpdated != rhsUpdated {
    return lhsUpdated > rhsUpdated
}
return lhs.id < rhs.id
```

When every row has `messageUpdatedAt == nil`, every row receives
`Int64.min`, and the table falls back to sorting by ID.

### Swift display uses message fields, not relay summary

`DockRenderProjector` maps `shortEventSummary` from `session.messageSummary`,
not `session.summary`:

```text
CodexDock/Dock/DockRenderProjector.swift:61-64
shortEventSummary: text(from: session.messageSummary)
messageActivityDate: session.messageUpdatedAt.map { ... }
```

`SessionRowProjector` then shows "No message preview" and "No messages" when
those message fields are absent:

```text
CodexDock/State/SessionRowProjector.swift:99-106
if let eventSummary = nonEmpty(text(summary.shortEventSummary, fallback: "")) {
    return eventSummary
}
guard activityMode == .raw else {
    return "No message preview"
}
```

```text
CodexDock/State/SessionRowProjector.swift:112-115
guard let messageActivityDate = summary.messageActivityDate else {
    return ("No messages", .distantPast)
}
```

So the relay can send useful `summary` values for every row while the visible
client card still reports no preview.

### Current verification masks the live contract gap

Swift helper fixtures fill the missing message fields from the summary:

```text
CodexDockTests/DockStoreTestSupport.swift:271-273
summary: string(from: summary.shortEventSummary)
messageSummary: string(from: summary.shortEventSummary)
messageUpdatedAt: Int64((summary.messageActivityDate ?? summary.lastActivity).timeIntervalSince1970)
```

Another helper always creates message fields too:

```text
CodexDockTests/DockStoreTestSupport.swift:841-843
summary: "Summary for \(title)"
messageSummary: "Summary for \(title)"
messageUpdatedAt: updatedAt
```

Relay `dock/subscribe` tests also include stored rows with explicit
`messageSummary` and `messageUpdatedAt`. That proves pass-through behavior, but
not the live app-server fallback behavior.

### Current parity harness does not consume stream catch-up

The parity verifier currently does a single request:

```text
scripts/dock-relay-state-parity.mjs:2746
return await client.request("dock/subscribe", {});
```

Then it closes the client. Under the current app-facing window contract, that
only reads the first 500 rows when a larger table exists. It does not wait for
`dock/update` catch-up windows to reach `complete: true`.

## Root Causes

### 1. The Dock Home row contract is split across incompatible meanings

There is no single owned contract for what makes a Dock Home row fresh and what
text it should show.

Current meanings:

- Relay order: `dock_order`, backed by app-server `thread/list` order and
  `updatedAt`.
- Relay display summary: `summary`, backed by app-server `latestSummary` or
  `preview`.
- Swift Dock Home order and visible activity: `messageUpdatedAt` and
  `messageSummary`.

Those are not equivalent, and the current code does not define a fallback
bridge between them.

### 2. The client reorders a server-owned stream

The relay has already built an app-facing ordered stream, but the client throws
that ordering away when it stores rows. This is fragile because server-owned
pagination and client-owned sorting must agree exactly, including null-field
behavior, or the UI can show an order that no server-side proof validates.

### 3. Missing optional message fields become a user-visible state

The upstream app-server row has `preview` and `updatedAt`; it does not promise
`messageSummary` and `messageUpdatedAt`. The relay keeps `summary` populated,
but Swift uses only message-specific fields for Dock Home cards.

This turns an integration mismatch into visible "No message preview" and
"No messages" states for valid rows.

### 4. The windowed stream contract is not fully represented in parity proof

`dock/subscribe` is now a windowed stream:

- initial response returns a first window;
- `dock/update` sends catch-up windows;
- `complete: true` marks the table complete.

The parity harness still treats one request response as the whole app-facing
state. This can create false "missing rows" reports, and more importantly it
does not prove the lifecycle the real client depends on.

### 5. Tests exercise a stronger contract than production data provides

Green unit tests are currently compatible with the bug because helper rows
always include message fields. The tests prove that populated message fields
work; they do not prove that live app-server rows without those fields sort and
render correctly.

### 6. Host aliases can still multiply apparent row counts

Host identity is endpoint-string based. Multiple saved aliases that point to
the same relay are treated as distinct hosts, so the same relay rows can appear
under multiple host IDs.

This pass saw 1629 rows, then 1630 rows after one new thread arrived, on one
live relay host path. It did not reproduce a 6800-row count. A 6800-style count
is still plausible if several saved host aliases point at the same relay or if
stale device config duplicates the same Mac service path.

### 7. App-server discovery has real boundary cases

One known stable local thread is readable by ID but not discoverable through the
app-server active list path. That remains a real upstream discovery boundary,
but it is not the immediate cause of old rows floating to the top or cards
showing "No message preview".

## Architecture Implication

This is a fundamental architecture issue, not just a one-line sort bug.

A one-line client fallback from `messageUpdatedAt` to `updatedAt` would likely
improve the symptom, but it would not answer the larger contract questions:

- Is Dock Home order owned by the relay or recomputed by the client?
- Is Dock Home "newest" based on thread update time or message update time?
- Is `summary` the display fallback for missing message summaries?
- Should `dock/update` carry append-only order deltas, full ordered windows, or
  explicit rank values?
- How does verification wait for the stream to become complete?
- How are multiple endpoint aliases to the same relay de-duplicated?

Until those answers are explicit, the repo can keep passing tests while a real
device renders the wrong order.

## Fix Direction, Not Implemented Here

The robust fix should make the contract explicit before changing UI behavior:

1. Pick one canonical Dock Home recency field.
2. Decide whether the relay owns final order, or the client owns final order.
3. If the relay owns order, include stable rank/order in the DTO or preserve
   received order through `DockSessionTable`.
4. If the client owns order, require a non-null sort key or define a mandatory
   fallback from `messageUpdatedAt` to `updatedAt`.
5. Decide that card text falls back from `messageSummary` to `summary`, or make
   the relay populate `messageSummary` from `summary` when app-server lacks a
   message-specific value.
6. Update tests so at least one stream fixture mirrors live app-server rows:
   populated `summary` and `updatedAt`, nil `messageSummary`, nil
   `messageUpdatedAt`.
7. Update `scripts/dock-relay-state-parity.mjs` to consume `dock/update`
   catch-up windows until `complete: true` before comparing app-facing row
   coverage and order.
8. Add a relay/device config check that warns when multiple saved endpoints map
   to the same relay identity.

## Fresh Consult

Completed with Cursor Agent Composer 2.5 Fast.

Run directory:

```text
/tmp/fresh-consult/codex-client-order-20260530T204845Z-480IlE
```

Execution mapping:

```text
runtime=agent
model=composer-2.5-fast
effort=encoded-in-model
```

The consult verdict was:

```text
VERDICT: pass-with-notes
CONFIDENCE: high
```

The consult agreed with the central architecture finding:

```text
Agree - this is an architectural contract split (relay order + `summary`/`updatedAt`
vs client `messageUpdatedAt`/`messageSummary` sort and display), compounded by
parity harness not consuming windowed `dock/update` catch-up and tests/fixtures
that always populate message fields.
```

The consult's strongest caveat was that it did not independently rerun the live
WebSocket probe. That caveat was addressed by the post-consult probe above,
which reproduced the nil-message-field shape on 1630 of 1630 rows while still
reaching stream completion.

Non-blocking consult notes to carry forward:

- `latestSummary` is accepted by relay code but absent from the generated
  upstream `Thread.ts`; live relay `summary` is effectively `preview`-driven.
- "Old threads first" is not a guaranteed oldest-by-time sort. The mechanism is
  nil `messageUpdatedAt` causing a lexicographic ID tie-break, which can surface
  old rows.
- `scripts/dock-relay-thread-summary-cache.mjs` exists, but the consult found
  it is not wired into `scripts/dock-relay-state-engine.mjs` reconciliation.
  That strengthens the conclusion that message fields are not populated on the
  live state path.
- Host alias multiplication is plausible from endpoint-string host identity,
  but this investigation did not prove the exact 6800-row iPhone 14 count.
