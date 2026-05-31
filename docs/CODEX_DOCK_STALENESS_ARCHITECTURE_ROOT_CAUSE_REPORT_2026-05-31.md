# Codex Dock Staleness Architecture Root Cause Report - 2026-05-31

## Bottom line

The simulator and phone can look online while showing stale Dock data because the architecture treats transport health and data freshness as separate things, then the client UI rolls stale Dock freshness up as `partial`, and `partial` counts as online-like.

That is the architectural bug: a stale retained list is not elevated to a first-class stale app state. It is allowed to keep rendering cached rows under a global badge that can say `Online 2/2`.

No implementation fix was made in this investigation.

## User-visible symptom

Current simulator evidence captured at `/tmp/codex-client/staleness-root-cause-20260531/sim-current.png` showed:

- global badge: `Online 2/2`
- Dock summary text: `Partial`
- top visible row age: `2h ago`

The app log captured at `/tmp/codex-client/staleness-root-cause-20260531/sim-log-signal-tail.txt` repeatedly showed:

```text
dock stream rows retained host_id=home.fairy-salmon.ts.net:4510 freshness=stale rows=961
dock stream rows retained host_id=amir-m5.fairy-salmon.ts.net:4510 freshness=stale rows=188
dock render input exceeds main publish row budget rows=1149 budget=600
```

So this is not just a display typo. The client knows the stream is stale and is intentionally retaining old rows.

## Current relay evidence

Direct `dock/subscribe` probes were saved at `/tmp/codex-client/staleness-root-cause-20260531/dock-subscribe-combined.json`.

At capture time:

- `amir` returned `freshness.status=stale`, `complete=true`, `totalRows=188`, `lastError=human-started thread validation failed`, top activity `2026-05-31T14:56:09.000Z`.
- `home` returned `freshness.status=stale`, `complete=false`, `totalRows=961`, `lastError=websocket closed: ws://127.0.0.1:4500/`, top activity `2026-05-30T16:28:28.000Z`.

Both `/statusz` snapshots reported relay service health as OK and raw app-server health as up. That proves the important split:

- The relay can be reachable.
- The raw app-server can pass health checks.
- The Dock list can still be stale.

## Why current work is not showing

This is the sharper missing piece: current turn data exists, but the thread-list summary timestamp is not moving.

On a later probe of the active thread `019e7e7d-66ca-7280-9aa0-2e272f1752b1`:

- `thread/read` returned `updatedAt=1780238608`, which is `2026-05-31T14:43:28Z`.
- `thread/turns/list` returned newer turns, including:
  - `startedAt=1780249079`, which is `2026-05-31T17:37:59Z`
  - `startedAt=1780246962`, which is `2026-05-31T17:02:42Z`

So the newer work is reachable through the turn/history API, but the thread summary API still says the thread was last updated around `14:43Z`.

That matters because the Dock overview is built from relay card projections backed by `thread/list` / thread-level summary fields, not by scanning `thread/turns/list` for every visible card. If the turn stream advances but the thread row `updatedAt` does not, the Dock has no current activity timestamp to sort by and no current summary timestamp to publish.

In simple terms: the new messages are in the thread detail data, but the Dock card source is still seeing an old thread-level timestamp.

## Immediate stale causes seen today

### Amir

The Amir relay is stuck stale because Dock reconciliation is incomplete.

Evidence from `/tmp/codex-client/staleness-root-cause-20260531/amir-dock-relay-tail.log`:

```text
human_started_thread.session_index_validation_failed
thread/read: thread not loaded: <thread-id>
state.reconcile_incomplete ... validationFailures=14 ... error=human-started thread validation failed
```

The code path is:

- `scripts/dock-relay-thread-data.mjs` validates session-index supplement candidates by calling `thread/read`.
- If any candidate read rejects, `validationFailures` increments.
- `scripts/dock-relay-state-engine.mjs` sets the whole Dock reconciliation `complete=false` when `totalValidationFailures !== 0`.
- `scripts/dock-relay-state-store.mjs` reports host freshness as `stale` when any sync scope is incomplete.

This means a supplemental validation failure can poison the whole host freshness even when the relay still has 188 rows to show.

### Home

The Home relay had a stale `dock/subscribe` response with `lastError=websocket closed: ws://127.0.0.1:4500/`. A later relay log showed `state.reconcile_succeeded` with `rows=961`, so Home recovered during the investigation.

That still proves the architecture problem: clients can sit on retained cached rows during stale windows and the global status can still present the host path as online-like.

## Architecture that allows this

### 1. The relay intentionally keeps stale rows visible

The README already describes this contract: Dock uses relay-owned `dock/*` methods, the relay materializes projections in `.codex-dock/relay-state.sqlite`, and it keeps stale rows visible when a source refresh fails.

Code references:

- `scripts/dock-relay-state-store.mjs`
  - `freshnessForHost(...)` returns `stale` if any sync scope is incomplete.
  - `markScopeStale(...)` records the scope as incomplete.
  - `listDockCards(...)` still returns cached cards from SQLite.
- `scripts/dock-relay-state-engine.mjs`
  - `snapshotDock(...)` returns cached cards plus `freshness`.
  - `reconcileDock(...)` publishes a delta with stale freshness on failure instead of clearing rows.

This is not automatically wrong. Keeping old rows can be useful. The bug is that the rest of the system does not make stale state loud enough.

### 2. The Swift client maps stale Dock freshness to `partial`, not `stale`

In `CodexDock/State/ThreadCardTable.swift`, `hostStatus(...)` maps:

- `.fresh` to `.loaded`
- `.stale` to `.partial(rowCount: message:)`
- `.offline` with rows to `.partial(rowCount: "Offline: ...")`

So a stale host with rows becomes partial, not stale.

Existing test coverage confirms this behavior:

- `CodexDockTests/DockStoreStreamTests.swift` expects a stale heartbeat to retain rows and produce `.partial(rowCount: 1, message: "refresh failed")`.

### 3. Connectivity treats `partial` as online-like

In `CodexDock/State/AppConnectivityStore.swift`, `HostConnectivityPhase.isOnlineLike` returns true for:

- `.online`
- `.partial`

Then `GlobalConnectivityIndicatorView` displays partial multi-host states using an online-count label:

- `.partial` -> `hostCountLabel(prefix: "Online")`

That is why the screen can say `Online 2/2` even when the list is stale or incomplete.

### 4. Existing relay tests explicitly allow healthy routes with stale state

This is not an accidental edge case. Existing tests encode it:

- `scripts/dock-relay-observability.test.mjs`: `readyz can pass while dock state freshness is stale after upstream failure`
- The same test asserts `dock/subscribe` can be route-healthy while `state.counts.incomplete >= 1`.
- `scripts/dock-relay.test.mjs` asserts `markScopeStale(...)` keeps the existing row visible.

So the repo currently has a deliberate design where service readiness, route success, cached-row visibility, and source freshness are separate. The missing piece is a user-facing stale contract.

## Why this affects both simulator and phone

The simulator and phones all use the same app code path:

- `DockStore`
- `AppServerThreadCardStreamClient`
- relay `dock/subscribe`, `dock/update`, and `dock/resync`

Phone config verification passed:

```text
rtk make device-config-verify-all
```

Verified iPhone 17 Pro hosts:

- `amir-m5.fairy-salmon.ts.net:4510`
- `home.fairy-salmon.ts.net:4510`

Verified iPhone 14 hosts:

- `Amir-M5.local:4510`
- `192.168.50.74:4510`

So the phone and simulator inherit the same architectural behavior. I did not reinstall or modify either phone.

## Root cause

The root cause is not one missing refresh call. It is two freshness contracts failing to line up:

First, the Dock overview trusts thread-level projection data, but current turn-level activity can be newer than the thread row's `updatedAt`. That is why current work can exist in `thread/turns/list` without appearing as a current Dock card.

Second, the relay is allowed to serve cached rows with `freshness.status=stale`. The Swift Dock store converts that stale freshness into `partial`. The connectivity layer counts `partial` as online-like. The global UI then shows `Online 2/2`, while the only stale signal is small summary text, host detail, logs, or direct relay diagnostics.

Net: the app currently proves "I can talk to the relay" much more loudly than it proves "this list is fresh."

## What would need to be defined before fixing

No fix was made here, but the architectural decision should be explicit before implementation:

- Should stale Dock freshness be a distinct `HostConnectivityPhase.stale` instead of `.partial`?
- Should global status say `Stale`, `Partial`, or `Online 1/2` when any visible Dock host is stale?
- Should retained rows show a clear stale age or source freshness warning near the list, not just inside host details?
- Should a supplemental session-index validation failure make the whole host stale, or only mark those supplemental candidates failed?
- Should there be a max acceptable source age, so a list cannot keep looking usable forever after the last successful sync?
