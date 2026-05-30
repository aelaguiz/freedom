# Codex Dock Relay State Engine Worklog - 2026-05-30

## Implementation

- Replaced `scripts/dock-relay-session-table.mjs` with a relay-owned SQLite state engine at `.codex-dock/relay-state.sqlite`.
- Added state modules for storage, projections, notification ingest, subscriptions, and reconciliation:
  - `scripts/dock-relay-state-store.mjs`
  - `scripts/dock-relay-state-views.mjs`
  - `scripts/dock-relay-state-engine.mjs`
  - `scripts/dock-relay-state-ingest.mjs`
  - `scripts/dock-relay-state-subscriptions.mjs`
- Added HTTP diagnostics: `/statez`, `/syncz`, `/subscriptionsz`, `/dbz`, and `/explainz/thread/<threadID>`.
- Changed `dock/subscribe` to return explicit state snapshots/deltas with `view`, `complete`, `totalRows`, `window`, and `stateGeneration`.
- Updated Swift stream DTOs and reducers so the app treats missing stream window metadata as a contract failure instead of silently accepting an incomplete table.
- Kept full thread history on Codex detail routes; Dock list state stores bounded UI projection fields so oversized list previews cannot bloat SQLite or WebSocket payloads.
- Added catch-up `dock/update` windows after partial snapshots so a client can receive every Dock row without forcing the first `dock/subscribe` response to carry the full table.
- Kept `/statez` freshness separate from `/statusz` route health: stale cached state is visible as incomplete sync state, but `dock/subscribe` is healthy when it serves the stream contract successfully.

## Home Findings

- `home` uses `/usr/bin/node` v18.19.1 by default, which cannot load `node:sqlite`.
- Installed and used `/home/aelaguiz/.local/node-v24.16.0-linux-x64/bin/node` for relay service and tests.
- Home Codex `thread/list` includes very large preview strings:
  - all-source max measured `preview` length: 988,833 characters
  - default interactive max measured `preview` length: 468,897 characters
- The state projection now bounds list text fields:
  - title: 240 characters
  - summary/message text: 4,096 characters
- A failed pre-cap run left the home SQLite file at 1.55 GB. After bounding projections and running `VACUUM` plus `PRAGMA wal_checkpoint(TRUNCATE)`, the DB dropped to 37 MB.

## Verification

- Local `rtk npm run test:relay`: 117 tests, 117 passed.
- Local `rtk swift test --filter AppServerClientTests`: 55 tests executed, 5 skipped, 0 failures.
- Local `rtk swift test --filter DockStoreTests`: 48 tests executed, 0 failures.
- Local `rtk swift test --filter DockStoreStreamTests`: 10 tests executed, 0 failures.
- Local `rtk swift test --filter ThreadDetailStoreTests`: 52 tests executed, 0 failures.
- Local `rtk make relay-doctor`: passed.
- Local `dock/subscribe` proof through `ws://127.0.0.1:4510`:
  - response: 55 ms
  - initial rows: 500
  - `totalRows`: 1616
  - final unique rows after streamed catch-up: 1616
  - updates: 11
  - complete signal: `dock/update` with `complete: true`
  - final `/statez`: `active: 1616`, `archived: 0`, `incomplete: 0`
  - `/statusz.appCriticalFailures`: none
  - `/explainz/thread/<firstThreadID>`: found and visible in Dock.
- Home `rtk make host-service-doctor` with Node v24 overrides: passed.
- Home `dock/subscribe` proof through `ws://home.fairy-salmon.ts.net:4510`:
  - response: 101 ms
  - initial rows: 250
  - `totalRows`: 5206
  - final unique rows after streamed catch-up: 5206
  - updates: 94
  - complete signal: `dock/update` with `complete: true`
  - `/statusz.appCriticalFailures`: none
  - `/explainz/thread/<firstThreadID>`: found and visible in Dock.
- Home `/statez` after background reconciliation settled:
  - `active`: 5206
  - `archived`: 0
  - `incomplete`: 0
  - `active:allSourceKinds`: complete
  - `active:interactiveDefault`: complete

## Review Gates

- Composer 2.5 Fast unbiased code review:
  - run directory: `/tmp/fresh-consult/relay-state-composer-final-20260530T165937Z-UNHQrU`
  - verdict: `pass-with-notes`
  - blocking findings: none
  - non-blocking findings addressed here: `/explainz/thread/<threadID>` is now row-specific and `state/query/subscribe` is no longer exposed as a fake subscription alias.
- Composer 2.5 Fast final delta review:
  - run directory: `/tmp/fresh-consult/relay-state-composer-final-delta-20260530T170717Z-2GFl2o`
  - verdict: `pass-with-notes`
  - code blockers: none
  - commit blocker: stage the five new `scripts/dock-relay-state-*.mjs` modules before committing.
  - independently re-ran `rtk npm run test:relay`: 117 tests, 117 passed.
- `$thermo-nuclear-code-quality-review` local pass:
  - no file crossed from under 1000 lines to over 1000 lines.
  - `scripts/dock-relay.mjs` was already over 1000 lines before this work (`1230` at `HEAD`, `1293` after this change).
  - strict cleanup removed the fake `state/query/subscribe` route, made `/explainz/thread/<threadID>` use a single-row explanation instead of a whole state dump, and prunes change-log rows after stale-scope writes.
