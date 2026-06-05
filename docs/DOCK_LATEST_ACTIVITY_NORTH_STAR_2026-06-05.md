# Dock Latest Activity North Star

Date: 2026-06-05

This document records the goal, pre-implementation code facts, audited plan,
and implementation result for the low-overhead Dock latest-activity fix.

## North Star

Dock cards should answer this question without opening Thread Detail:

> What is the most recent meaningful thing happening in this Codex session?

The card should update through the existing Dock stream:

```text
iPhone Dock list
  -> relay dock/subscribe
  <- DockThreadCardDTO rows
  <- dock/update rows when card facts change
```

The solution must not subscribe to every thread detail stream. It should reuse
the relay's existing card projection and bounded history reads.

## User-Visible Goal

Today a Dock card can move and change status, but its visible summary may still
come from old thread-list preview data. The target behavior is:

- The row order still follows newest real activity.
- The row summary should prefer the newest meaningful user or assistant message
  when the relay can prove it cheaply.
- If the relay cannot prove a latest message, the row should honestly fall back
  to existing `displaySummary`, `latestSummary`, `summary`, `preview`, or title
  behavior.
- The iPhone should not need to open Thread Detail just to make the Dock card
  truthful.

## Pre-Implementation Code Facts

### Verification Result

Verified on 2026-06-05 against the local `Amir-M5` relay and real Codex
history data.

Probe shape:

```text
dock/subscribe
  -> choose visible Dock rows
thread/turns/list
  -> exact activity-proof params: { threadId, limit: 250 }
  -> no itemsView:"full"
  -> redact all message text
```

Result:

```text
sampledRows: 290
errors: 0
routes: history 290
itemsViewValues: summary
rowsWithTurns: 289
rowsWithAnyItems: 286
rowsWithMessageItems: 286
rowsWithExtractableMessageText: 286
rowsAlreadyUsingLatestSummary: 0
rowsStillUsingPreview: 289
totalMessageItems: 5451
totalExtractableMessageItems: 5451
```

Conclusion:

```text
The relay already receives extractable user/agent message text in the exact
thread/turns/list call used for Dock activity proof. The current code uses that
response to compute activityAtMs, then discards the message text.
```

### 1. Swift Dock cards only render the relay card projection

Swift receives `DockThreadCardDTO` rows from the thread-card stream and projects
`card.displaySummary` into `DockRowViewModel.summary`.

Code:

- `CodexDock/State/AppServerThreadCardStreamClient.swift:60` calls the
  card-stream `subscribe`.
- `CodexDock/AppServer/DockThreadCardDTO.swift:326` defines the card DTO.
- `CodexDock/AppServer/DockThreadCardDTO.swift:344` has `displaySummary`.
- `CodexDock/AppServer/DockThreadCardDTO.swift:357` has `summarySource`.
- `CodexDock/State/ThreadCardRowProjector.swift:88` maps
  `card.displaySummary` to the visible Dock row summary.

Current card DTO has no dedicated fields such as:

```text
latestMessageText
latestMessageRole
latestMessageAt
```

So if we only want better visible text, the lowest-change contract is to improve
`displaySummary` relay-side. If we want role/time/source UI, the DTO and Swift
model need optional new fields.

### 2. Relay Dock card truth is already centralized

`RelayStateEngine.reconcileDock` builds Dock cards. It:

- reads history rows with `thread/list`;
- reads live loaded rows / leases;
- filters human-started threads;
- proves newest activity;
- normalizes cards;
- stores them in SQLite;
- publishes `dock/update`.

Code:

- `scripts/dock-relay-state-engine.mjs:340` starts `reconcileDock`.
- `scripts/dock-relay-state-engine.mjs:351` gathers live proof and history list
  rows.
- `scripts/dock-relay-state-engine.mjs:374` merges ordered rows.
- `scripts/dock-relay-state-engine.mjs:378` calls `canonicalizeThreadRows`.
- `scripts/dock-relay-state-engine.mjs:384` normalizes canonical rows into
  cards.
- `scripts/dock-relay-state-store.mjs:620` applies Dock reconciliation.
- `scripts/dock-relay-state-store.mjs:676` writes changed cards.

This is the right place to solve card summaries. Swift should not bypass this
path by calling raw app-server routes.

### 3. The relay already fetches message-bearing turn data for unopened Dock rows,
but only uses it for activity timestamps

`canonicalizeThreadRows` calls `readNewestTurnActivity` for each candidate row.
That function calls `thread/turns/list`, scans turn timestamps, and returns only
`newestTurnActivityAtMs`. Runtime verification shows that this same response
usually already contains extractable `userMessage` / `agentMessage` summary
text.

Code:

- `scripts/dock-relay-thread-data.mjs:1381` starts `readNewestTurnActivity`.
- `scripts/dock-relay-thread-data.mjs:1390` calls `listThreadTurns`.
- `scripts/dock-relay-thread-data.mjs:1404` loops over returned turns.
- `scripts/dock-relay-thread-data.mjs:1405` keeps only the max activity time.
- `scripts/dock-relay-thread-data.mjs:1443` writes `activityAtMs` into the
  canonical row.

This explains the confusing part:

```text
Dock can reorder unopened threads
  because relay proves activityAtMs from thread/turns/list.

Dock does not show latest message text today
  because the current code discards turn message text and only keeps activityAtMs.
```

### 4. Live-status scans intentionally avoid full turns

The relay's live loaded-row scan uses `thread/loaded/list`, then
`thread/read includeTurns:false`.

Code:

- `scripts/dock-relay-thread-data.mjs:677` calls `thread/loaded/list`.
- `scripts/dock-relay-thread-data.mjs:682` calls `thread/read`.
- `scripts/dock-relay-thread-data.mjs:684` sets `includeTurns:false`.

So live-status state can update card status and loaded-session facts without
carrying full transcript data.

### 5. Detail subscriptions are separate and full-detail

When the iPhone opens one Thread Detail, the relay builds a
`ThreadDetailLedger` for that one thread.

Code:

- `scripts/dock-relay.mjs:663` starts `subscribeThreadDetail`.
- `scripts/dock-relay.mjs:684` creates/loads the detail ledger.
- `scripts/dock-relay.mjs:601` applies live detail notifications to that
  ledger.
- `scripts/dock-relay.mjs:700` resyncs detail.

This is not a global per-card transcript cache. It is per opened detail
session.

### 6. There was an existing summary cache helper, but it was not wired into Dock
reconciliation

Before implementation, `ThreadSummaryCache` knew how to read bounded turns and
extract a latest meaningful user/agent message.

Code:

- `scripts/dock-relay-thread-summary-cache.mjs:78` extracts the latest
  meaningful message from turns.
- `scripts/dock-relay-thread-summary-cache.mjs:117` defines
  `ThreadSummaryCache`.
- `scripts/dock-relay-thread-summary-cache.mjs:137` decorates rows with
  `latestSummary` / `displaySummary`.
- `scripts/dock-relay-thread-summary-cache.mjs:155` warms cache entries.
- `scripts/dock-relay-thread-summary-cache.mjs:221` reads bounded turns.
- `scripts/dock-relay-thread-data.mjs:119` creates a cache via
  `threadSummaryCacheForConfig`.

But `rg` showed no call site for:

```text
threadSummaryCacheForConfig(...)
warmRows(...)
decorateRows(...)
```

outside the factory and cache module. So this was a dormant second path, not
active production behavior.

## What The Relay Has Today

For unopened Dock threads, the relay has:

- thread identity;
- title;
- current `displaySummary` source fallback;
- status;
- repository / working directory / branch;
- proven `activityAtMs`;
- card ordering key;
- freshness / completeness.

For unopened Dock threads, the relay does not currently store:

- full detail rows;
- full transcript;
- a structured latest message object;
- role/time/source for the latest message.

During reconciliation, the relay may read `thread/turns/list` for unopened
threads. Current code uses that data for timestamps and then discards it.

## Design Constraints

- Do not subscribe to every `thread/detail/subscribe`.
- Do not keep full transcript ledgers for every Dock card.
- Do not make Swift call raw `thread/list`, `thread/read`, or
  `thread/turns/list` for Dock truth.
- Do not turn stale or failed latest-message reads into fake fresh card state.
- Keep route count and memory bounded.
- Preserve current card ordering behavior.
- Keep current `dock/*` and `archive/*` streams as the app-visible source of
  truth.

## Plan Iterations

### Plan A: Subscribe to every detail stream

Reject.

This would give the relay message rows for every visible thread, but it is the
wrong shape:

- one live upstream session per card;
- much more memory;
- much more reconnect behavior;
- more privacy/logging risk;
- harder failure modes;
- duplicates Thread Detail's job.

This violates the low-overhead requirement.

### Plan B: Add latest-message extraction to the existing activity proof path

Promising.

Current reconciliation already calls `thread/turns/list` through
`readNewestTurnActivity`. The lowest-overhead version is:

1. While scanning turns for `activityAtMs`, also extract the newest meaningful
   user/agent text if that response already contains enough item text.
2. Attach it to the canonical row as `latestSummary`.
3. Let `displaySummaryForThread` prefer `latestSummary`, which it already does
   after `displaySummary`.
4. Store the resulting short string in the existing card store through
   `displaySummary` / `summarySource`.
5. Publish a normal `dock/update` when the card summary changes.

Cost:

- no new subscription type;
- no full detail ledger per card;
- no new iPhone-side data fetch;
- minimal extra memory: one bounded summary string per card.

Verification:

- Done on 2026-06-05.
- The exact activity-proof response uses `itemsView:"summary"`.
- It already contains extractable `userMessage` / `agentMessage` text for 286
  of 290 sampled Dock rows.
- So Plan B does not need an extra read for normal rows.

### Plan C: Wire `ThreadSummaryCache` into Dock reconciliation

Reject for this fix.

`ThreadSummaryCache` is currently dormant. Wiring it in would create a second
card-summary source beside the existing activity proof path. The real-data
verification above showed the activity proof response already contains message
text for normal rows, so a cache fallback is unnecessary overhead and an
unnecessary architecture split.

Retire the dormant cache path instead of making it production behavior. Keep a
single pure latest-message extractor, and call it only from the existing
activity proof path.

## Decision

Use Plan B only:

1. Extract latest summary in `readNewestTurnActivity` with no extra route count.
2. Keep existing fallback text when no extractable message text exists.
3. Retire the unused `ThreadSummaryCache` class/factory so there is one Dock
   card summary path.
4. Keep the public card contract simple:

```text
DockThreadCardDTO.displaySummary = latest meaningful summary when proven
DockThreadCardDTO.summarySource = "latest_summary"
```

5. Add optional richer fields only in a later UI change if the UI needs
   role/time/source:

```text
latestMessageText
latestMessageRole
latestMessageAtMs
latestMessageSource
```

This keeps the work inside relay-owned card truth and avoids mass detail
subscriptions, cache warming, and full transcript storage.

## Done-State Requirements

The implementation is done only when all of these are true:

- `readNewestTurnActivity` still proves `activityAtMs` from bounded
  `thread/turns/list` pages.
- The same turn pages also produce the latest meaningful `userMessage` or
  `agentMessage` summary when available.
- The canonical Dock row carries that text through existing card fields:
  `latestSummary`, `displaySummary`, and `summarySource:"latest_summary"`.
- If no latest message text is extractable, the existing fallback chain remains:
  `displaySummary`, `latestSummary`, `summary`, `preview`, title.
- A failed turn read still marks the row/stream partial or stale exactly as
  today; latest-summary extraction must not hide activity-proof failures.
- Swift does not call raw `thread/list`, `thread/read`, `thread/turns/list`, or
  `thread/detail/subscribe` for Dock card summaries.
- No mass detail subscriptions are introduced.
- No full transcript cache is introduced.
- No normal-path route is added beyond the existing activity proof
  `thread/turns/list` call.
- The dormant `ThreadSummaryCache` class/factory is removed or left unreachable
  only if a test proves it is intentionally dead code. The preferred outcome is
  removal.

## Recommended Implementation Shape

Implement the smallest relay-only change:

1. Move the pure turn-message extraction helpers out of
   `scripts/dock-relay-thread-summary-cache.mjs` into a non-cache module such
   as `scripts/dock-relay-thread-summary.mjs`:

```text
latestMeaningfulMessageFromTurns(turns)
latestMeaningfulSummaryFromTurns(turns)
```

2. Delete the unused `ThreadSummaryCache` class and the unused
   `threadSummaryCacheForConfig` factory. Do not replace them with another
   cache.

3. Extend `readNewestTurnActivity` to return:

```text
{
  newestTurnActivityAtMs,
  latestSummary,
  latestSummaryAtMs
}
```

4. Track latest summary across all pages already read for activity proof.
   Compare candidates by timestamp and stable page order, and do not read a
   separate route just for text.

5. Add `latestSummary`, `displaySummary`, and
   `summarySource:"latest_summary"` to the canonical row before
   `normalizeThread` when a non-empty latest summary exists.

6. Keep `displaySummaryForThread` as the final fallback gate:

```text
displaySummary
latestSummary
summary
preview
title
```

7. Store only bounded card facts in SQLite. Do not store full turn payloads.

8. Publish through normal `dock/update` deltas. Do not invent a second client
   route.

## Test Plan

### Relay Unit Tests

Add or extend tests for `latestMeaningfulMessageFromTurns`:

- prefers newest user/agent message over older text;
- ignores non-message turn items;
- handles string content and array content;
- handles missing timestamps deterministically;
- returns `timestampMs` and keeps `timestampSeconds` for existing callers.

### Relay Contract Tests

Extend `scripts/dock-relay-card-contract.test.mjs`:

- `dock/subscribe` orders cards by newest turn activity and sets
  `displaySummary` to newest meaningful message when the raw thread `preview`
  is stale.
- `dock/update` moves a row and updates `displaySummary` when a new turn appears
  in an unopened thread.
- failed latest-summary extraction does not delete the card.
- failed latest-summary extraction marks the row/stream partial or stale only if
  it means activity proof also failed; otherwise it should fall back without
  lying.
- summary extraction does not require `thread/detail/subscribe`.

### Overhead Tests

Add route-count assertions:

- no extra route count beyond the existing `thread/turns/list` activity proof;
- No test should pass by opening detail subscriptions for every card.

### Simulator Proof

Extend the controlled simulator fixture:

- create an existing row whose stored `preview` is old;
- return a newer turn message through the relay's chosen low-overhead path;
- require the Dock row summary to update through `dock/update`;
- assert route evidence includes `dock/subscribe` / `dock/update`;
- assert route evidence does not include mass `thread/detail/subscribe`.

Existing related proof points:

- `scripts/dock-relay-card-contract.test.mjs:298` already proves ordering by
  newest turn activity.
- `scripts/dock-relay-card-contract.test.mjs:1194` already proves partial/stale
  behavior when newest-turn proof fails.
- `scripts/dock-relay-sync-audit.mjs:3278` already checks `displaySummary`
  updates in a thread-activity scenario.
- `scripts/dock-relay-controlled-simulator-fixture.mjs:2099` already checks the
  simulator-visible `displaySummary` after a row moves.

## First Verification Before Implementation

Done on 2026-06-05. Plan B can extract latest summary from the existing
activity-proof response. No cache fallback is needed for normal rows.

## Implementation Result

Implemented on 2026-06-05:

- Added `scripts/dock-relay-thread-summary.mjs` as a pure latest-message
  extractor.
- Removed the dormant `scripts/dock-relay-thread-summary-cache.mjs` cache class.
- Removed `threadSummaryCacheForConfig` from `scripts/dock-relay-thread-data.mjs`.
- Extended `readNewestTurnActivity` to return `latestSummary` and
  `latestSummaryAtMs` from the same `thread/turns/list` pages it already reads
  for `activityAtMs`.
- Updated `canonicalizeThreadRows` to set `latestSummary`, `displaySummary`,
  and `summarySource:"latest_summary"` when a latest message is proven.
- Added relay tests for pure extraction, `dock/subscribe`, `dock/update`, route
  count, and no `thread/detail/subscribe`.
- Updated the controlled simulator `thread-activity` fixture so the visible
  row summary must come from turn item text rather than stale preview text.

No Swift client change was needed because the existing Swift path already
renders `DockThreadCardDTO.displaySummary`.
