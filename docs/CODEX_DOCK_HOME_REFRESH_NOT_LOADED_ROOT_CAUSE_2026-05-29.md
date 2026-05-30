---
title: "Codex Dock - Home Refresh and Not Loaded Root Cause"
date: 2026-05-29
status: investigation
owners: [Amir]
doc_type: root_cause_analysis
source_repo_head: 3ed11ad
scope: investigation_only_no_source_fixes
related:
  - docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md
  - CodexDock/State/DockStore.swift
  - CodexDock/State/AppServerDockClient.swift
  - CodexDock/State/DockSessionProjection.swift
  - CodexDock/State/SessionRowProjector.swift
  - scripts/dock-relay-thread-data.mjs
  - scripts/dock-relay-live-status-cache.mjs
  - /Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md
  - /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs
  - /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs
---

# TL;DR

There are two separate problems that look like one bad UI state.

1. The Home row count flaps because the client rebuilds each refresh from only the hosts that have completed in that refresh. Amir-M5 finishes quickly, so its rows stay visible. Home is slower, so when Home is selected, the current refresh temporarily has zero Home rows and a `Checking` host state until Home's new request finishes.

2. `Not loaded` is coming from the upstream app-server data. Codex app-server intentionally returns `status: { "type": "notLoaded" }` for stored history rows that are not currently loaded in memory. The relay currently does not merge live status into `thread/list` rows; it only attaches a `liveOverlay`. So the app is not inventing `Not loaded`, but it is presenting an upstream implementation detail too loudly.

Home is synced to the same client repo commit as this Mac, `3ed11ad`. The current Home relay is reachable and healthy. The old code and old Home checkout were confounders earlier, but they are not the whole explanation for the current UI behavior.

# Investigation Bounds

This pass did not make source-code changes. It used direct JSON-RPC relay probes, simulator unified logs, repo source reads, and Codex app-server source reads.

No screenshots were used. No simulator UI automation was used. This avoids stealing macOS focus while still proving the timing and data path.

Current code version:

- Local repo: `codex-dock-agents-tab-live-counts`
- Local HEAD: `3ed11ad Bound active Dock session paging`
- Local worktree before writing this doc: clean
- Home repo HEAD: `3ed11ad`
- Home worktree status from `git status --short --untracked-files=all`: clean output

# User-Visible Symptom

When the Dock view is filtered or focused on Home, it can show this loop:

```text
Home: 200 sessions
Home: Checking
Home: 0 shown
Home: 200 sessions
```

Amir-M5 usually looks stable because it finishes first. If the selected host is Amir-M5, the partial snapshot already contains Amir-M5 rows, so there is no visible drop to zero for that selected host.

# Ground Truth Summary

## Current relay health

Both relays were online at the time of the direct probe.

```text
Amir-M5 statusz:
  httpStatus: 200
  ok: true
  host.id: Amir-M5
  history.lastHealth.status: up
  liveStatus.overlayState: ready
  liveStatus.endpoints: 2
  liveStatus.rows: 10
  history pool pending: 0

Home statusz:
  httpStatus: 200
  ok: true
  host.id: home
  history.lastHealth.status: up
  liveStatus.overlayState: ready
  liveStatus.endpoints: 0
  liveStatus.rows: 0
  history pool pending: 3
```

Home's `lastClientFacingError` at the time of the probe was:

```text
at: 2026-05-29T19:16:08.886Z
subsystem: history
method: thread/list
code: ECONNREFUSED
retryable: true
message: connect ECONNREFUSED 127.0.0.1:4500
```

That error lines up with the earlier service restart. The current probe after that error succeeded.

## Current list-call timing and status distribution

Direct JSON-RPC probe at `2026-05-29T19:30:36.358Z`:

```text
Amir-M5 activeHuman:
  durationMs: 484
  rows: 100
  statusTypes: { notLoaded: 100 }
  liveOverlay: ready, endpoints=2, rows=10
  nextCursorPresent: true

Amir-M5 activeAgents:
  durationMs: 159
  rows: 100
  statusTypes: { notLoaded: 100 }
  liveOverlay: ready, endpoints=2, rows=10
  nextCursorPresent: true

Home activeHuman:
  durationMs: 5978
  rows: 100
  statusTypes: { notLoaded: 100 }
  liveOverlay: ready, endpoints=0, rows=0
  nextCursorPresent: true

Home activeAgents:
  durationMs: 3769
  rows: 100
  statusTypes: { notLoaded: 100 }
  liveOverlay: ready, endpoints=0, rows=0
  nextCursorPresent: true
```

Important read:

- Current app behavior loads one page per active scope.
- One page is observed as 100 rows from app-server even though the client asks for `limit: 250`.
- The Dock runs two active scopes per host: human and agents.
- With two hosts, current successful refreshes therefore produce `400` rows:
  - Amir-M5 human: 100
  - Amir-M5 agents: 100
  - Home human: 100
  - Home agents: 100

## Home is slower enough to expose the client bug

At this probe, Home's slowest scope took `5978ms`. Amir-M5's slowest scope took `484ms`.

The client publishes a partial snapshot as soon as the first host finishes. That means the UI can enter a partial state after Amir-M5 finishes, while Home is still loading. In that partial snapshot, Home has a host state of `Checking` and no rows.

## Amir-M5 proves the relay has live knowledge but does not merge it into list rows

Amir-M5 had `10` live loaded rows according to `thread/loaded/list`.

Two of those live row IDs also appeared in the first `thread/list` page, but their list statuses were still `notLoaded`:

```json
{
  "loadedRows": 10,
  "listRows": 100,
  "overlapRows": 2,
  "overlaps": [
    {
      "id": "019e7376-aa6f-7171-85b5-5e63cffb0158",
      "status": "notLoaded",
      "source": "vscode"
    },
    {
      "id": "019e7456-af5f-7561-9cb2-0db296c62b49",
      "status": "notLoaded",
      "source": "vscode"
    }
  ]
}
```

That is the clearest proof that the relay/app-server combination currently does not make `thread/list` a good live-status source.

# Simulator Evidence

The simulator used was the booted `iPhone 17`:

```text
BAD95C8E-3E57-4818-9B90-E4ED22593B4B
```

The simulator logs show this repeated shape:

```text
2026-05-29 14:20:51.857 dock reload started hosts=2 show_loading=true
2026-05-29 14:20:52.543 connectivity overall status=Partial message=Online 1/2, checking 1
2026-05-29 14:20:58.047 connectivity overall status=Online message=2 hosts online
2026-05-29 14:20:58.047 dock reload finished hosts=2 rows=400 duration_ms=6190

2026-05-29 14:21:03.052 dock reload started hosts=2 show_loading=false
2026-05-29 14:21:03.606 connectivity overall status=Partial message=Online 1/2, checking 1
2026-05-29 14:21:07.661 connectivity overall status=Online message=2 hosts online
2026-05-29 14:21:07.661 dock reload finished hosts=2 rows=400 duration_ms=4606

2026-05-29 14:29:25.424 dock reload started hosts=2 show_loading=false
2026-05-29 14:29:25.988 connectivity overall status=Partial message=Online 1/2, checking 1
2026-05-29 14:29:31.071 connectivity overall status=Online message=2 hosts online
2026-05-29 14:29:31.071 dock reload finished hosts=2 rows=400 duration_ms=5647

2026-05-29 14:30:27.324 dock reload started hosts=2 show_loading=false
2026-05-29 14:30:27.872 connectivity overall status=Partial message=Online 1/2, checking 1
2026-05-29 14:30:33.280 connectivity overall status=Online message=2 hosts online
2026-05-29 14:30:33.280 dock reload finished hosts=2 rows=400 duration_ms=5956
```

This proves:

- The app is not staying permanently offline.
- The app is not losing the relay connection.
- The app is repeatedly entering a partial snapshot during normal refresh.
- The partial window often lasts around 3.5 to 6.9 seconds.
- The refresh loop then waits 5 seconds after the refresh completes before starting another refresh.

So the problem is not overlapping refreshes. It is destructive partial refresh state.

# Client Code Path

## Refresh loop

`CodexDock/Features/Dock/DockView.swift`:

- `runDockRefreshLoop()` performs the first `await dockStore.load()`.
- Then it sleeps for `DockStore.defaultAutoRefreshInterval`.
- Then it performs `await dockStore.refresh()`.
- Because it awaits `refresh()`, refreshes are not intentionally concurrent.

`CodexDock/Configuration/CodexDockConstants.swift`:

```swift
public static let autoRefreshInterval: Duration = .seconds(5)
```

Plain meaning: the app waits for a refresh to finish, waits 5 more seconds, then starts the next refresh.

## Partial host load

`CodexDock/State/DockStore.swift` is the main cause of the Home zero-row flicker.

The load starts with a fresh empty outcome list:

```swift
var outcomes: [HostLoadOutcome] = []
var checkingHostIDs = Set(hosts.map(\.id))
```

As each host completes:

```swift
outcomes.append(outcome)
checkingHostIDs.remove(outcome.host.id)
...
if !checkingHostIDs.isEmpty {
    state = .loaded(makeSnapshot(results: outcomes, checkingHostIDs: checkingHostIDs))
}
```

`makeSnapshot(...)` then builds rows only from the current refresh outcomes:

```swift
var summaries: [SessionSummary] = []
...
for outcome in results {
    ...
    summaries.append(contentsOf: hostDedupedSummaries)
}
...
for host in hosts where checkingHostIDs.contains(host.id) {
    hostStatesByID[host.id] = DockHostStateViewModel(host: hostViewModel, status: .checking)
}
...
let rows = projector.rows(from: summaries)
```

The missing piece: there is no "last good rows per host" cache used for a still-checking host. A still-checking host contributes host state only, not stale rows.

## Why Home selected goes to zero

`CodexDock/State/DockSessionProjection.swift` filters visible rows by selected host:

```swift
if !options.filters.selectedHostIDs.isEmpty,
   !options.filters.selectedHostIDs.contains(row.id.hostID) {
    return false
}
```

During a partial refresh:

- Amir-M5 rows are in `snapshot.rows`.
- Home is only in `snapshot.hostStates` as `.checking`.
- Home rows from the previous successful refresh are not carried forward.
- If the selected host filter is Home, the visible row list is empty.

That exactly matches the observed `Home -> 0 -> Checking -> 200` behavior.

## Current paging improvement

At `3ed11ad`, active session paging is bounded:

```swift
public static let activeSessionMaxPages = 1
```

`DockSessionQuery.activeHuman` and `DockSessionQuery.activeAgents` both use that `maxPages`.

`AppServerDockClient.loadSessions(...)` stops after `maxPages`:

```swift
if let maxPages = query.maxPages, pageCount >= maxPages {
    cursor = nil
    break
}
```

This prevents the older active-Dock behavior where the app drained every active cursor from Home before finishing. Earlier in this same work session, an app-shaped full cursor drain against Home showed:

```text
Home human all-pages:
  10 pages
  958 rows
  19324ms

Home agents all-pages:
  reached page 13
  1300 rows
  66601ms
  then timed out at 90s before completion
```

That explains why the pre-`3ed11ad` experience was much worse. It does not fully solve the current UI problem because the current one-page Home request can still take about 4 to 6 seconds, and stale Home rows are still dropped while the new Home request is in flight.

# Relay Code Path

## `thread/list` mostly passes through history rows

`scripts/dock-relay-thread-data.mjs`:

```js
async function aggregateThreadList(config, params = {}) {
  const historyParams = clampThreadListParams(params);
  const history = await readHistoryThreadList(config, historyParams);
  const data = Array.isArray(history.data) ? history.data : [];
  const summaryCache = threadSummaryCacheForConfig(config);
  const dataWithSummaries = summaryCache.decorateRows(data);
  summaryCache.warmRows(data);
  const liveOverlay = history.liveOverlay || liveStatusCacheForConfig(config).liveOverlay();
  return {
    ...history,
    data: dataWithSummaries,
    liveOverlay,
  };
}
```

What this means:

- The relay asks the raw history app-server for `thread/list`.
- It decorates row summaries.
- It warms summaries in the background.
- It attaches `liveOverlay`.
- It does not replace row status with live status.
- It does not insert loaded live rows into the list.
- It does not keep a cached stable host snapshot for the client.

## Live discovery is separate

`scripts/dock-relay-thread-data.mjs` discovers live loopback app-server processes:

```js
const endpoints = discoverLoopbackEndpoints()
  .filter((endpoint) => !excludedURLs.has(canonicalURLString(endpoint.url)));
```

It then calls:

```js
thread/loaded/list
thread/read
```

against those live endpoints and builds a live status cache.

The important Home result was:

```text
Home liveStatus.endpoints: 0
Home liveStatus.rows: 0
```

The important Amir-M5 result was:

```text
Amir-M5 liveStatus.endpoints: 2
Amir-M5 liveStatus.rows: 10
```

If Home is expected to have live Codex sessions, the next investigation should ask why the relay sees zero non-history loopback app-server processes on Home. The relay's discovery regex only sees process lines shaped like:

```text
codex app-server --listen ws://127.0.0.1:<port>
```

If Home's active sessions are launched under a different command shape, different user, container, service manager, or socket shape, this discovery path will miss them.

## Current relay tests protect "do not merge live status into list"

`scripts/dock-relay-phase5.test.mjs` has a test named:

```text
relay thread/list keeps history status while focused detail can still route live
```

The test sets up:

- live row status: `active`
- history row status: `notLoaded`

Then it asserts the list row still says:

```js
assert.equal(rows[0].status.type, "notLoaded");
```

Plain meaning: the relay behavior that makes the Dock list mostly `Not loaded` is not accidental in the current codebase. It is an intentional contract today. The relay can route detail calls to the live owner, but the list remains history-first.

# Raw Codex App-Server Code Path

The upstream Codex app-server source confirms that `notLoaded` is a real state with a narrow meaning.

`/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md`:

```text
thread/list ... Each returned thread includes status (ThreadStatus), defaulting to notLoaded when the thread is not currently loaded.
```

The same README says:

```text
thread/loaded/list - list the thread ids currently loaded in memory.
```

`/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs`:

```rust
status: ThreadStatus::NotLoaded,
```

is the default status assigned when a stored thread is converted into a `Thread`.

Then `thread/list` asks the thread watch manager for loaded statuses:

```rust
let statuses = self
    .thread_watch_manager
    .loaded_statuses_for_threads(status_ids)
    .await;
...
if let Some(status) = statuses.get(&thread.id) {
    thread.status = status.clone();
}
```

`/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs`:

```rust
fn loaded_status_for_thread(&self, thread_id: &str) -> ThreadStatus {
    self.status_for(thread_id)
        .unwrap_or(ThreadStatus::NotLoaded)
}
```

and:

```rust
fn loaded_thread_status(runtime: &RuntimeFacts) -> ThreadStatus {
    if !runtime.is_loaded {
        return ThreadStatus::NotLoaded;
    }
    ...
}
```

Plain meaning: upstream `notLoaded` does not mean "this row is missing basic list data." It means "this thread is not currently loaded in this app-server process's runtime memory."

# Root Cause

## Root cause 1: destructive partial snapshots

The Home zero-row behavior is a client state-management bug.

The Dock should treat a refresh as "new data is being fetched for a host." Instead, it treats a still-checking host as "this host currently contributes no rows." That is why a Home filter can collapse to zero even though the app had good Home rows from the previous refresh.

This is exposed by Home because Home is slower. Amir-M5 is fast enough that its partial period is tiny from the user's point of view.

## Root cause 2: `Not loaded` is technically true but product-hostile as a primary row badge

The upstream meaning is precise: the thread exists in history, but it is not currently loaded in a runtime owner.

For Dock, that status is not very useful as the dominant row state because most history rows will naturally be `notLoaded`. The row still has useful data:

- title or preview
- cwd/repository
- branch
- last activity
- source type
- host

So the row is not "not loaded" in the way a user reads that phrase. It is only "runtime status not loaded."

## Root cause 3: the relay leaves too much list assembly burden on the client

The relay currently gives the client:

- history pages from `thread/list`
- a separate `liveOverlay`
- live routing for detail operations

It does not give the client:

- a stable per-host Dock snapshot
- a stale-while-refresh contract
- merged live statuses for list rows
- a server-side answer to "show me the current Dock list for this host"

So the client is forced to fan out and rebuild the Dock view from lower-level pieces. That is workable for a fast single host. It is brittle when one host is slower and the UI needs stable filtered views.

## Root cause 4: Home has no discovered live rows

Home's live status cache reported:

```text
endpoints: 0
rows: 0
```

That means Home cannot currently upgrade list status from live app-server owners through the relay's live discovery path. This may be expected if Home has no live Codex sessions. If Home does have live sessions, this is a separate relay discovery problem.

# What Is Not The Root Cause

## Not raw connectivity

Both relays responded to `/statusz`. Both relays served `thread/list`. Simulator logs repeatedly recovered to:

```text
Online message=2 hosts online
```

## Not overlapping refreshes

The refresh loop awaits each refresh, then sleeps 5 seconds. There is no evidence that the app is starting a new Dock refresh before the previous one completes in normal foreground operation.

## Not a Swift string-only bug

The Swift mapper maps upstream `notLoaded` to the Dock row status:

```swift
case .notLoaded:
    return .notLoaded
```

The row projector then displays:

```swift
case .notLoaded:
    return .notLoaded
```

The label is confusing, but the data starts upstream.

## Not only the old Home checkout

Earlier, Home was running old code and that was a real confounder. Current evidence after syncing Home to `3ed11ad` still shows:

- Home requests are much slower than Amir-M5.
- Home rows disappear during partial refresh.
- all current list rows return `notLoaded`.

# UX Meaning

The UI should distinguish these concepts:

```text
Host reachability:
  Is the host online?

Host refresh state:
  Are we refreshing this host right now?

Row runtime status:
  Is this thread currently loaded/running/idle in a live app-server?

Row list availability:
  Do we have enough data to show the row in the Dock list?
```

Today those concepts are collapsed in the user's experience:

- A refreshing host looks like it temporarily has no rows.
- A history row whose runtime owner is not loaded looks like the row itself is "not loaded."
- A slow host looks unstable even when it is online.

# Candidate Fixes For Discussion Only

No fix was applied in this investigation pass.

## Option A: client stale-while-refresh per host

Keep each host's last successful rows while a new refresh for that host is in flight.

During refresh:

```text
Home: 200 sessions, refreshing
Rows: still visible from last successful Home snapshot
```

When Home finishes:

```text
Home: 200 sessions
Rows: replaced with fresh Home rows
```

This directly fixes the zero-row flicker. It is probably the smallest product-correct fix for the current symptom.

Primary simulator test requirement:

- Configure two hosts.
- Make one host slow enough to finish after the other.
- Select/filter the slow host after an initial successful load.
- Trigger refresh.
- Verify the slow host keeps its previous rows while its host state indicates refresh/checking.

If current simulator hooks cannot force a slow host, add hooks. This should not rely on unit tests as the primary proof.

## Option B: split `checking` from `refreshing`

Use `checking` for first load or unknown host state only.

Use `refreshing` when the host already has a last-good snapshot.

This makes the UI language match reality:

```text
First load:
  Home: Checking
  Rows: none yet

Later refresh:
  Home: Refreshing
  Rows: retained
```

This is strongly related to Option A and may be part of the same client fix.

## Option C: relay-level Dock snapshot endpoint

Add a relay-owned endpoint shaped for the Dock, for example:

```text
dock/snapshot
```

The relay would own:

- history paging policy
- status merge policy
- stale-while-refresh behavior
- per-host caching
- live status integration

The client would ask for the current host snapshot instead of rebuilding everything from lower-level history and live endpoints.

This is a bigger architectural fix, but it fits the product direction better if the relay is meant to simplify the phone client.

Primary simulator test requirement:

- App connected to real relay.
- Relay snapshot refresh in progress.
- Host-filtered UI remains stable.
- Offline/error states still render correctly when the host path is unavailable.

## Option D: relay merges live status into `thread/list` rows

The relay already knows about live rows on Amir-M5. It could replace `notLoaded` status on matching list rows when a live row exists.

This would change an existing protected behavior. `scripts/dock-relay-phase5.test.mjs` currently asserts that history status wins for `thread/list`, even when live detail routing is available.

So this is not a trivial cleanup. It is a product/API contract decision.

## Option E: reduce `Not loaded` prominence

Even if upstream keeps `notLoaded`, the Dock row badge does not have to present it as the main row status.

Possible UX interpretations:

- Show no status badge for `notLoaded` history rows.
- Show `History` instead of `Not loaded`.
- Show runtime statuses only when they are meaningful: `Running`, `Needs input`, `Error`, maybe `Idle`.
- Move `Not loaded` into a debug/detail field or filter, not the default row badge.

This does not fix the Home zero-row flicker, but it addresses the "everything says Not loaded" product problem.

## Option F: investigate Home live discovery

If Home is expected to have active Codex sessions, inspect why the relay sees:

```text
liveStatus.endpoints: 0
liveStatus.rows: 0
```

The likely checks:

```bash
ps -axo pid,command | rg 'codex app-server --listen ws://127\\.0\\.0\\.1:'
```

and whether Home sessions are launched:

- under the same user as the relay
- with a different command shape
- in a container namespace
- through a non-loopback socket
- without `codex app-server --listen ...`

This is separate from the client stale-row bug. Fixing live discovery would make statuses more useful, but it would not by itself stop stale Home rows from disappearing during refresh.

# Recommended Direction

The clean product path is probably:

1. Fix the client to retain last-good host rows during refresh.
2. Rename the refresh state so first load is `Checking` and later refresh is visibly different.
3. Decide whether `Not loaded` should remain a visible row status at all.
4. Separately decide whether the relay should provide a Dock-shaped snapshot or merge live statuses into list rows.
5. Investigate Home live discovery only if Home should have active live sessions right now.

The first fix should be simulator-proven. A unit test can cover the state reducer behavior, but it should not be treated as completion evidence. The important proof is the visible simulator behavior with a slow host selected.

# Commands Used

Repo state:

```bash
git status --short --untracked-files=all
git rev-parse --short HEAD
git branch --show-current
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && git rev-parse --short HEAD && git status --short --untracked-files=all'
```

Code reads:

```bash
rg -n "loadAllHostsPublishingPartial|makeSnapshot|checkingHostIDs|defaultAutoRefreshInterval|runDockRefreshLoop|SessionStatus|notLoaded|Not loaded|activeSessionMaxPages|activeSessionPageLimit" CodexDock -S
nl -ba CodexDock/State/DockStore.swift | sed -n '430,860p'
nl -ba CodexDock/State/AppServerDockClient.swift | sed -n '1,260p'
nl -ba CodexDock/Features/Dock/DockView.swift | sed -n '120,190p'
nl -ba CodexDock/State/DockSessionProjection.swift | sed -n '1,330p'
nl -ba CodexDock/Models/SessionSummaryMapper.swift | sed -n '300,350p'
nl -ba CodexDock/State/SessionRowProjector.swift | sed -n '1,100p'
nl -ba scripts/dock-relay-thread-data.mjs | sed -n '360,510p'
nl -ba scripts/dock-relay-live-status-cache.mjs | sed -n '1,260p'
nl -ba scripts/dock-relay-phase5.test.mjs | sed -n '192,320p'
```

Codex app-server reads:

```bash
rg -n "thread/list|notLoaded|not_loaded|loaded/list|ThreadStatus|ThreadList|status.*not" /Users/aelaguiz/workspace/codex -S
nl -ba /Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md | sed -n '132,140p'
nl -ba /Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md | sed -n '314,388p'
nl -ba /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs | sed -n '100,130p'
nl -ba /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs | sed -n '360,452p'
nl -ba /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs | sed -n '1790,1880p'
nl -ba /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs | sed -n '3928,4160p'
```

Direct relay probe:

```bash
rtk node --input-type=module
```

The probe connected to:

```text
ws://amir-m5.fairy-salmon.ts.net:4510
ws://home.fairy-salmon.ts.net:4510
http://amir-m5.fairy-salmon.ts.net:4510/statusz
http://home.fairy-salmon.ts.net:4510/statusz
```

It requested:

```json
{
  "limit": 250,
  "sortKey": "updated_at",
  "sortDirection": "desc",
  "modelProviders": [],
  "archived": false
}
```

and the same request with agent source kinds:

```json
{
  "sourceKinds": [
    "exec",
    "appServer",
    "subAgentReview",
    "subAgentCompact",
    "subAgentThreadSpawn",
    "subAgentOther",
    "unknown"
  ]
}
```

Simulator logs:

```bash
xcrun simctl spawn BAD95C8E-3E57-4818-9B90-E4ED22593B4B log show --style compact --last 12m --predicate 'subsystem == "com.aelaguiz.CodexDock"' | rg 'dock reload (started|finished)|connectivity overall status='
```

# Completion State

This document is investigation output only. It does not implement any of the candidate fixes.

