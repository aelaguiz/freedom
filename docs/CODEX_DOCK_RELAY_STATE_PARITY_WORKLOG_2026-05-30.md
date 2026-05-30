---
title: "Codex Dock Relay State Parity Worklog"
date: 2026-05-30
status: active
doc_type: worklog
owners: [Amir, Codex]
related:
  - docs/CODEX_DOCK_GOALS_2026-05-29.md
  - docs/CODEX_DOCK_RELAY_THREAD_FIDELITY_WORKLOG_2026-05-29.md
  - docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md
  - docs/CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md
---

# Codex Dock Relay State Parity Worklog

## Objective

Make the relay capable of representing Codex app-server state one-to-one before
client work continues.

The relay must not bypass the app-server and read Codex disk or SQLite as a
runtime workaround. Disk and SQLite can be used by audit tooling to verify the
app-server-backed relay state, but the relay state itself must come from the
app-server.

## Current Relay Truth Bar

- The relay knows every Codex thread the app-server can expose.
- The relay represents each Codex thread exactly once in its canonical thread
  index, while preserving every app-server scope where that thread appears.
- The relay preserves Codex list order inside each app-server scope.
- The relay can drain paginated Codex lists without silently truncating rows.
- The relay can drain paginated Codex turns without losing order.
- The relay records whether its view is complete.
- The relay exposes gaps as gaps instead of hiding them as product behavior.

## First Gap Found

`dock/subscribe` is not an exhaustive relay truth model. It is a compact
app-facing table:

- active only;
- currently capped by `THREAD_LIST_MAX_LIMIT`;
- split into human and automation list requests;
- normalized into `DockStreamSessionDTO`;
- sorted for UI consumption;
- missing many underlying Codex fields;
- not designed to prove one-to-one parity with every app-server-exposed thread.

That is fine as an app stream, but it cannot be the proof surface for the relay
state objectives.

## Work Done

Added a new app-server-only relay state method:

```text
relay/state/snapshot
```

Implemented in:

```text
scripts/dock-relay-state-snapshot.mjs
```

Wired through:

```text
scripts/dock-relay.mjs
```

Tested by:

```text
scripts/dock-relay-state-snapshot.test.mjs
```

The new method:

- calls app-server `thread/list`;
- drains every page until `nextCursor` is absent;
- preserves each row's page index, row index, and ordinal;
- checks for repeated cursors and marks the scope incomplete instead of
  pretending the result is complete;
- separates active and archived list scopes;
- separates the app-server default interactive source scope from explicit
  `sourceKinds`;
- records every scope where a thread appears;
- optionally calls app-server `thread/read`;
- optionally calls routed relay `thread/read` so live-owner detail can be
  compared with history detail;
- optionally drains app-server `thread/turns/list` pages and preserves turn
  order exactly as returned by Codex.

The new method does not read Codex disk or SQLite.

## Method Shape

Example request:

```json
{
  "method": "relay/state/snapshot",
  "params": {
    "includeArchived": true,
    "includeThreadReads": true,
    "includeTurns": false
  }
}
```

For focused tests:

```json
{
  "method": "relay/state/snapshot",
  "params": {
    "includeArchived": true,
    "includeThreadReads": true,
    "includeLoaded": false,
    "sourceScopes": ["interactiveDefault", "exec"],
    "limit": 2
  }
}
```

The response is explicit about order and completeness:

```json
{
  "kind": "relayStateSnapshot",
  "source": "app-server-only",
  "complete": true,
  "order": {
    "sortKey": "updated_at",
    "sortDirection": "desc",
    "preservedWithinEachScope": true
  }
}
```

Each scope carries:

```json
{
  "name": "active:interactiveDefault",
  "archived": false,
  "sourceScope": "interactiveDefault",
  "complete": true,
  "pages": [
    {
      "cursor": null,
      "nextCursor": "page-2",
      "rowCount": 2
    }
  ],
  "threadIDsInCodexOrder": ["thread-a", "thread-b"]
}
```

When turns are included, they are represented in app-server order:

```json
{
  "turns": {
    "complete": true,
    "turnsInCodexOrder": [
      { "ordinal": 0, "pageIndex": 0, "rowIndex": 0 },
      { "ordinal": 1, "pageIndex": 0, "rowIndex": 1 }
    ]
  }
}
```

## Verification

Focused checks run:

```bash
rtk node --check scripts/dock-relay-state-snapshot.mjs
rtk node --check scripts/dock-relay.mjs
rtk node --test scripts/dock-relay-state-snapshot.test.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --check scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk npm run test:relay
```

Result:

- `scripts/dock-relay-state-snapshot.mjs`: syntax check passed.
- `scripts/dock-relay.mjs`: syntax check passed.
- `scripts/dock-relay-state-snapshot.test.mjs`: 2 tests passed.
- `scripts/dock-relay-state-parity.mjs`: syntax check passed.
- `scripts/dock-relay-state-parity.test.mjs`: syntax check passed.
- `scripts/dock-relay-state-parity.test.mjs`: 5 tests passed.
- `rtk npm run test:relay`: 81 tests passed.

The focused tests prove:

- `relay/state/snapshot` drains multiple app-server `thread/list` pages.
- It preserves Codex list order inside the source/archive scope.
- It preserves archived and active scopes separately.
- It preserves source scopes separately.
- It can call app-server `thread/read` for every indexed thread.
- With `includeTurns: true`, it drains multiple `thread/turns/list` pages and
  preserves the app-server turn order.

Real relay focused proof:

```bash
rtk make dock-relay-restart
rtk make dock-relay-status
```

Then requested `relay/state/snapshot` from `ws://127.0.0.1:4510` with:

```json
{
  "includeArchived": false,
  "includeThreadReads": false,
  "includeLoaded": false,
  "sourceScopes": ["interactiveDefault"],
  "limit": 250
}
```

Result:

```json
{
  "complete": true,
  "scopeCount": 1,
  "threadCount": 227,
  "scope": "active:interactiveDefault",
  "pages": 3,
  "rowCount": 227,
  "first": "019e75f9-c6d7-7283-8c12-1c942468c33b",
  "last": "019e516b-a1d1-7c30-a5ac-50c70c3fc240"
}
```

Full focused output:

```bash
/tmp/codex-client/relay-state-snapshot-focused-20260530.json
```

Real relay all-scope app-server snapshot:

```bash
/tmp/codex-client/relay-state-snapshot-all-scopes-20260530.json
```

Result:

```json
{
  "complete": true,
  "scopeCount": 22,
  "threadCount": 1502,
  "nonEmptyScopes": {
    "active:interactiveDefault": 227,
    "active:cli": 147,
    "active:vscode": 80,
    "active:exec": 98,
    "active:subAgent": 1177,
    "active:subAgentThreadSpawn": 1177
  }
}
```

All archived scopes returned zero rows. That matches the local
`state_5.sqlite.threads.archived` count observed in this audit.

Added the disk/SQLite parity verifier:

```text
scripts/dock-relay-state-parity.mjs
```

Tested by:

```text
scripts/dock-relay-state-parity.test.mjs
```

The verifier:

- asks the relay for `relay/state/snapshot`;
- reads `$CODEX_SQLITE_HOME/state_5.sqlite` separately;
- compares relay-discovered thread IDs to SQLite thread IDs;
- compares active/archive and source-scope membership;
- compares important list-row metadata such as cwd, path, source,
  modelProvider, timestamps, git metadata, and agent metadata;
- optionally includes `thread/loaded/list` state;
- probes SQLite rows missing from list discovery with direct `thread/read` so
  we know whether the app-server can read the thread by ID;
- writes sanitized reports with fingerprints for title, preview, and
  first-user-message text.

Real parity command:

```bash
rtk node scripts/dock-relay-state-parity.mjs --include-loaded --json-out /tmp/codex-client/relay-state-parity-20260530.json --summary-only
```

Result:

```json
{
  "ok": false,
  "relayComplete": true,
  "relayThreadCount": 1502,
  "sqliteThreadCount": 1503,
  "missingFromRelay": 1,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "directReadProbes": 1,
  "findings": 92,
  "errors": 59,
  "warnings": 33
}
```

SQLite source/archive counts at that moment:

```json
{
  "active": 1503,
  "archived": 0,
  "sourceKinds": {
    "cli": 148,
    "vscode": 80,
    "exec": 98,
    "subAgent:threadSpawn": 1177
  }
}
```

The missing SQLite thread:

```json
{
  "id": "019e56d4-4339-76a1-9ef3-37f081af3f08",
  "archived": false,
  "sourceKind": "cli",
  "hasUserEvent": false,
  "firstUserMessagePresent": false,
  "rolloutPath": "/Users/aelaguiz/.codex/sessions/2026/05/23/rollout-2026-05-23T16-53-31-019e56d4-4339-76a1-9ef3-37f081af3f08.jsonl"
}
```

Direct-read probe result:

```json
{
  "threadID": "019e56d4-4339-76a1-9ef3-37f081af3f08",
  "threadReadByID": true,
  "status": "notLoaded"
}
```

Meaning: the app-server can read that thread if the relay already knows the ID,
but the thread is absent from all app-server `thread/list` scopes used by the
relay state snapshot. That is a real list-discovery blind spot.

Other parity findings from the same run:

- 58 cwd mismatches where app-server list metadata and SQLite `threads.cwd`
  disagree.
- 22 updatedAt mismatches where app-server list metadata and SQLite updated
  time disagree.
- 10 loaded-state warnings where `thread/loaded/list` included a thread but all
  relay list rows for that thread reported `notLoaded`.
- 165 current goal rows exist in `goals_1.sqlite`, but
  `relay/state/snapshot` does not yet expose goal state.

## Latest Audit Update

The relay snapshot now includes a combined source scope:

```text
active:allSourceKinds
archived:allSourceKinds
```

Meaning: one explicit app-server `thread/list` request using every known
`sourceKinds` value, so Codex's combined list order is preserved instead of only
preserving separate source lanes.

The parity verifier now also reads rollout `session_meta` from disk as audit
evidence only. The relay still does not read disk at runtime.

The audit disk read is intentionally narrow:

- first JSONL line only;
- `session_meta` fields only;
- no prompt text, base instructions, transcript text, or full payloads;
- title, preview, and first-user-message text remain fingerprinted in reports.

Upstream Codex source checked:

- app-server/SQLite list filters out previewless rows with
  `threads.preview <> ''`;
- filesystem rollout listing also requires `summary.preview.is_some()`;
- direct `thread/read` can still read a previewless thread by ID.

That explains the earlier missing thread:

```text
019e56d4-4339-76a1-9ef3-37f081af3f08
```

It is a real Codex row and direct-readable, but it has no app-server-listable
preview, so `thread/list` does not enumerate it. This is an app-server
list-discovery limit, not a relay pagination bug.

Latest list-only parity command:

```bash
rtk node scripts/dock-relay-state-parity.mjs --include-loaded --json-out /tmp/codex-client/relay-state-parity-20260530-v4.json --summary-only
```

Result:

```json
{
  "relayComplete": true,
  "relayThreadCount": 1507,
  "sqliteThreadCount": 1508,
  "sqliteAppServerListableThreadCount": 1507,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "storageDisagreements": 169,
  "listRowInconsistencies": 49,
  "errors": 0,
  "warnings": 668,
  "info": 2
}
```

Meaning:

- the relay currently matches every SQLite thread that app-server `thread/list`
  can enumerate: 1507 of 1507;
- there is still one real Codex thread outside list discovery because Codex
  hides previewless rows from list;
- the audit has no remaining hard error in the list-discovery proof;
- the remaining findings are meaning/conflict work, not missing list rows.

Latest thread-read parity command:

```bash
rtk node scripts/dock-relay-state-parity.mjs --include-thread-reads --include-loaded --json-out /tmp/codex-client/relay-state-parity-20260530-v7-thread-reads.json --summary-only
```

Result:

```json
{
  "relayComplete": true,
  "relayThreadCount": 1507,
  "sqliteThreadCount": 1508,
  "sqliteAppServerListableThreadCount": 1507,
  "appServerNotListable": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "storageDisagreements": 180,
  "listRowInconsistencies": 46,
  "readDetailDisagreements": 18,
  "errors": 0,
  "warnings": 687,
  "info": 2
}
```

Disk/session-meta coverage in that run:

```json
{
  "attempted": 1508,
  "found": 1508,
  "missingOrInvalid": 0
}
```

Latest goal parity command:

```bash
rtk node scripts/dock-relay-state-parity.mjs --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-v10-goals.json --summary-only
```

Result:

```json
{
  "relayComplete": true,
  "relayThreadCount": 1507,
  "sqliteThreadCount": 1508,
  "sqliteAppServerListableThreadCount": 1507,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "storageDisagreements": 178,
  "listRowInconsistencies": 47,
  "readDetailDisagreements": 0,
  "goalParity": {
    "included": true,
    "relayGoalCount": 142,
    "sqliteGoalCount": 165,
    "sqliteGoalsWithThreadRow": 142,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelay": 23,
    "missingFromRelayWithThreadRow": 0,
    "extraInRelay": 0,
    "goalReadErrors": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "errors": 0,
  "warnings": 677,
  "info": 25
}
```

Goal meaning from this run:

- `thread/goal/get` is now captured in `relay/state/snapshot` for every
  app-server-exposed persisted thread.
- Every goal attached to a current `state_5.sqlite.threads` row matched through
  app-server: 142 of 142.
- `goals_1.sqlite` has 23 additional goal rows whose `thread_id` is absent from
  current `state_5.sqlite.threads`.
- App-server exposes goals by known thread ID. It does not expose a standalone
  goal list, and it does not expose SQLite `goal_id`.
- The 23 missing SQLite goal rows are therefore storage/app-server blind spots,
  not relay misses for current threads.

Latest combined full-state command:

```bash
rtk node scripts/dock-relay-state-parity.mjs --include-thread-reads --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-v13-full-state.json --summary-only
```

Result:

```json
{
  "relayComplete": true,
  "relayThreadCount": 1507,
  "sqliteThreadCount": 1508,
  "sqliteAppServerListableThreadCount": 1507,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "directReadProbes": 1,
  "storageDisagreements": 179,
  "listRowInconsistencies": 47,
  "readDetailDisagreements": 18,
  "goalParity": {
    "included": true,
    "relayGoalCount": 142,
    "sqliteGoalCount": 165,
    "sqliteGoalsWithThreadRow": 142,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelay": 23,
    "missingFromRelayWithThreadRow": 0,
    "extraInRelay": 0,
    "goalReadErrors": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "sqliteStableGoalsDuringAudit": false,
  "sqliteGoalRowsChangedDuringAudit": 3,
  "sqliteGoalRowsAddedDuringAudit": 0,
  "sqliteGoalRowsRemovedDuringAudit": 0,
  "errors": 0,
  "warnings": 684,
  "info": 25
}
```

Combined-run meaning:

- all app-server-listable thread rows are represented by the relay;
- all current thread goal rows that have matching `state_5.sqlite.threads`
  rows are reachable through app-server `thread/goal/get`;
- the audit is not atomic for goal counters because 3 goal rows changed while
  the audit was running;
- the remaining blocker is not a missing listable row, but unresolved meaning:
  previewless rows, stale/current metadata conflicts, routed live status versus
  history status, and goal rows not attached to current thread rows.

Current meanings learned:

- `thread/list` is the app-server source for list discovery and list order.
- `thread/list` is not guaranteed to expose every real SQLite row, because
  previewless rows are filtered out upstream.
- `thread/read` can read at least some rows that `thread/list` cannot discover.
- `thread/goal/get` is the app-server source for current per-thread goal state,
  but only when the caller already knows the thread ID.
- `thread/read.updatedAt` is not a reliable "last touched" proof. Codex direct
  read currently calls rollout summary without a file mtime input, so many
  direct-read rows fall back to created time.
- Routed relay `thread/read` can show live status such as `active` or `idle`,
  while history `thread/read` can show `notLoaded` for the same thread.
- Some app-server list scopes can return different metadata for the same
  thread. Example class: one scope can return rollout `session_meta.cwd`, while
  another returns SQLite `threads.cwd`.
- SQLite and rollout `session_meta` can disagree on durable metadata such as
  `cwd` and git fields. The audit now records this as `codex.storage`, not as a
  relay runtime workaround.

Current proof state:

- Good: app-server-listable thread coverage is exact: 1510 of 1510.
- Good: archived thread count is currently zero in both relay archived scopes
  and SQLite.
- Good: combined app-server order is captured in `active:allSourceKinds`.
- Good: goal coverage for current app-server-exposed thread rows is exact:
  142 of 142.
- Good: spawned parent/child relationship coverage is exact for current
  app-server-listable spawned rows: 1185 of 1185, with 0 parent mismatches.
- Good: the combined verifier now reports whether goal rows changed during the
  audit. The latest run found 3 changed goal rows, 0 added, and 0 removed.
- Good: the app-facing `dock/subscribe` path now has explicit relay tests
  proving both normal session lanes request `thread/list` with
  `archived: false` and drain every `nextCursor` page.
- Good: the parity verifier now checks app-facing `dock/subscribe`; latest
  run returned 1510 sessions, matching the 1510 app-server-listable active
  thread rows from the same audit.
- Good: `rtk npm run test:relay` passed after these changes: 93 tests, 0
  failures.
- Not done: previewless direct-readable rows need an explicit relay/app-server
  meaning because list cannot discover them.
- Not done: SQLite `goal_id` and the 23 orphan goal rows in `goals_1.sqlite`
  are not available through app-server goal APIs.
- Not done: the relay must expose canonical detail/conflict meaning so clients
  do not unknowingly consume stale list metadata.

## v14 App-Facing Session Pagination Proof

Finding:

- The proof snapshot already drained all `thread/list` pages, but
  app-facing `dock/subscribe` still needed its own proof.
- `dock/subscribe` is what the client uses for the normal session table, so it
  cannot silently stop at Codex's first 250-row page.

Change:

- `scripts/dock-relay-session-table.mjs` now loops `thread/list` until
  `nextCursor` is absent for the default human lane and the automation lane.
- It rejects a repeated cursor instead of looping forever.
- `scripts/dock-relay.test.mjs` now includes
  `dock/subscribe drains all active thread/list pages for both lanes`.

Verification:

```text
rtk node --check scripts/dock-relay-session-table.mjs
rtk node --check scripts/dock-relay.test.mjs
rtk node --test scripts/dock-relay.test.mjs
# 27 tests, 0 failures

rtk npm run test:relay
# 89 tests, 0 failures
```

Meaning:

- The normal app session stream no longer truncates after the first
  app-server page for either normal lane.
- The session stream still only covers app-server-listable session rows. It
  does not solve previewless rows, orphan goal rows, or the full detail/meaning
  parity problem by itself.

Live service verification:

```text
rtk make dock-relay-restart
rtk make dock-relay-status

rtk node --input-type=module --eval '<dock/subscribe count probe>'
```

Result after restart:

```json
{
  "sessionCount": 1507,
  "archivedCount": 0,
  "lanes": {
    "human": 227,
    "agent": 1280
  }
}
```

Meaning:

- Live `dock/subscribe` now matches the parity audit's 1507
  app-server-listable active rows.
- The one missing SQLite row is still missing because app-server `thread/list`
  does not enumerate previewless rows.

## v15 Spawn Relationship Parity Proof

Finding:

- One of the fundamental requirements is that spawned parent/child
  relationships are real, not inferred from names or UI lanes.
- SQLite stores the durable edge in `state_5.sqlite.thread_spawn_edges`.
- App-server list/read rows expose the same relationship through the structured
  `Thread.source.subAgent.threadSpawn.parentThreadId` payload when the thread
  is listable.

Change:

- `scripts/dock-relay-state-parity.mjs` now reads
  `state_5.sqlite.thread_spawn_edges`.
- It compares each child edge against the relay/app-server thread source parent
  ID.
- It reports missing child rows, parent mismatches, relay parents with no
  SQLite edge, and SQLite source-vs-edge disagreements.
- `scripts/dock-relay-state-parity.test.mjs` now proves both the matching case
  and the mismatch case without exposing prompt text.

Verification:

```text
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --check scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
# 13 tests, 0 failures

rtk npm run test:relay
# 91 tests, 0 failures

rtk node scripts/dock-relay-state-parity.mjs --include-thread-reads --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-v15-spawn-parity.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1507,
  "sqliteThreadCount": 1508,
  "sqliteAppServerListableThreadCount": 1507,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "goalParity": {
    "relayGoalCount": 142,
    "sqliteGoalsWithThreadRow": 142,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0
  },
  "spawnParity": {
    "included": true,
    "sqliteSpawnEdgeCount": 1182,
    "sqliteSpawnEdgesWithChildThreadRow": 1182,
    "sqliteSpawnEdgesWithRelayChild": 1182,
    "missingRelayChildForSpawnEdge": 0,
    "parentMismatches": 0,
    "relaySourceParentsWithoutEdge": 0,
    "storageSourceParentMismatches": 0
  },
  "storageDisagreements": 180,
  "listRowInconsistencies": 46,
  "readDetailDisagreements": 18,
  "sqliteStableGoalsDuringAudit": false,
  "sqliteGoalRowsChangedDuringAudit": 3,
  "findings": 709,
  "errors": 0,
  "warnings": 684,
  "info": 25
}
```

Meaning:

- Spawned session relationship parity is now proven for current app-server
  listable rows.
- This does not fix the previewless active CLI thread, goal orphan rows, or
  metadata meaning conflicts.

## v16 App-Facing Dock Parity Proof

Finding:

- The parity audit previously proved `relay/state/snapshot`, but not the normal
  app-facing `dock/subscribe` stream in the same report.
- That was a real blind spot: before restarting the host service bundle, the
  live process still returned an old capped `dock/subscribe` result.

Change:

- `scripts/dock-relay-state-parity.mjs` now requests `dock/subscribe` by
  default.
- The verifier compares `dock/subscribe.sessions[*].threadID` against the
  active app-server-listable SQLite thread set.
- It reports missing active rows, extra dock rows, duplicate sessions, and
  archived threads appearing in the normal app-facing stream.
- `--no-dock-subscribe` is available for runs that intentionally skip this
  app-facing proof.

Verification:

```text
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --check scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
# 15 tests, 0 failures

rtk npm run test:relay
# 93 tests, 0 failures

rtk node scripts/dock-relay-state-parity.mjs --include-thread-reads --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-v16-dock-parity.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1510,
  "sqliteThreadCount": 1511,
  "sqliteAppServerListableThreadCount": 1510,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "goalParity": {
    "relayGoalCount": 142,
    "sqliteGoalsWithThreadRow": 142,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1185,
    "sqliteSpawnEdgesWithRelayChild": 1185,
    "parentMismatches": 0
  },
  "dockParity": {
    "included": true,
    "sessionCount": 1510,
    "expectedActiveListableCount": 1510,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "lanes": {
      "agent": 1283,
      "human": 227
    }
  },
  "storageDisagreements": 179,
  "listRowInconsistencies": 48,
  "readDetailDisagreements": 18,
  "sqliteStableGoalsDuringAudit": false,
  "sqliteGoalRowsChangedDuringAudit": 3,
  "findings": 725,
  "errors": 0,
  "warnings": 700,
  "info": 25
}
```

Meaning:

- The normal app-facing stream is now proven complete for active
  app-server-listable rows.
- It is also proven to exclude archived rows in the current real state.
- This still does not make previewless rows listable, because app-server
  `thread/list` does not expose that row.

## Known Gaps After This Step

This is progress, not completion.

- The relay state snapshot is the full debug/state proof path. The normal
  app-facing `dock/subscribe` stream now drains all list pages and matches the
  app-server-listable active count, but it is still a compact session view, not
  the full state/detail/goal parity model.
- The snapshot now has a parity verifier, and the verifier found a real gap:
  one SQLite thread is directly readable by ID but not discoverable through
  app-server `thread/list`.
- Several list-row metadata fields disagree between app-server and SQLite. The
  next step is deciding which source is canonical for each field and whether
  those differences are upstream app-server bugs, SQLite/backfill facts, or
  acceptable stale/live projections.
- `thread/goal/get` is included in the relay state snapshot, but app-server
  does not expose SQLite `goal_id` and does not expose a goal list for orphan
  goal rows.
- Goal counters can move while the audit runs. The verifier now reports this,
  but a true point-in-time proof still needs a quiesced app-server or an
  app-server snapshot API that reads threads and goals atomically.
- App-server notifications such as `thread/archived`, `thread/unarchived`,
  `thread/goal/updated`, and `thread/goal/cleared` are not yet represented in
  the snapshot model.
- The default exhaustive source-scope set includes app-server default
  interactive plus every known explicit `sourceKinds` enum. If Codex can store a
  custom source that is neither in default interactive nor addressable by
  `sourceKinds`, the app-server may not expose an exhaustive list path for that
  source. That must be verified against real Codex state and app-server source
  semantics.
- Loaded/live discovery can still be incomplete if `thread/loaded/list` exceeds
  the relay page cap. The snapshot marks that incomplete; it does not hide it.
- The snapshot preserves order per app-server scope. It does not invent a
  single global order across scopes unless Codex exposes one.

## Next Required Work

- Explain or fix the missing list-discovery case for
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- Classify the v16 metadata findings: 179 storage disagreements, 48 list-row
  inconsistencies, and 18 read-detail disagreements into true bugs vs known
  app-server projection semantics.
- Decide whether orphan rows in `goals_1.sqlite` should be ignored, cleaned up,
  exposed by a new app-server goal-list API, or treated as historical storage
  facts outside current thread state.
- Decide whether app-server should expose SQLite `goal_id`, or whether relay
  should explicitly define goal identity as `thread_id` only.
- Define and test the exact meanings of every state/detail exposed in the
  snapshot.
- Decide whether the app-server has a true "all source kinds" list surface. If
  not, record that as an app-server limitation instead of making the relay read
  disk at runtime.

## v17 Correction: No Codex Source Changes

Correction:

- I briefly changed `/Users/aelaguiz/workspace/codex` while investigating the
  previewless-row gap.
- That was wrong for this audit because the running app-server is
  `/Users/aelaguiz/.local/bin/codex`, not a binary built from that source tree.
- Amir requested a hard reset of the Codex repo.
- `/Users/aelaguiz/workspace/codex` was reset with:

```text
git reset --hard HEAD
```

Result:

```text
HEAD is now at 090144e0ec [codex] Fix hyperlink-aware key-value table rendering (#24825)
```

Current rule:

- The relay can read Codex source only as reference.
- The relay must not depend on Codex source modifications.
- Runtime relay behavior must stay compatible with the installed app-server
  binary.

Cleanup:

- Removed the invalid `includePreviewless` relay request parameter from:
  - `scripts/dock-relay-state-snapshot.mjs`
  - `scripts/dock-relay-session-table.mjs`
  - related tests
- Restored the parity definition of "app-server-listable" to mean a current
  SQLite thread row whose `preview` is non-empty, matching the current Codex
  app-server list contract.
- Kept the valid `dock/subscribe` pagination fix. The app-facing stream still
  drains all `thread/list` pages for the human and automation lanes.

Verification:

```text
rtk node --check scripts/dock-relay-state-snapshot.mjs
rtk node --check scripts/dock-relay-session-table.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --check scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay-state-snapshot.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay.test.mjs
rtk npm run test:relay
```

Result:

- `scripts/dock-relay-state-snapshot.test.mjs`: 3 tests passed.
- `scripts/dock-relay-state-parity.test.mjs`: 15 tests passed.
- `scripts/dock-relay.test.mjs`: 27 tests passed.
- `rtk npm run test:relay`: 93 tests passed.

## v18 Live Proof After Correction

Runtime identity:

- Installed app-server binary:

```text
/Users/aelaguiz/.local/bin/codex
codex-cli 0.135.0-alpha.2
```

- Raw app-server launchd command:

```text
/Users/aelaguiz/.local/bin/codex app-server --listen ws://127.0.0.1:4500 --ws-auth capability-token --ws-token-file /Users/aelaguiz/workspace/codex-client/.codex-dock/app-server.token
```

- Relay launchd command:

```text
/opt/homebrew/bin/node /Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs --listen-host 0.0.0.0 --port 4510 --phone-auth none --env-file /Users/aelaguiz/workspace/codex-client/.codex-dock/service.env --bonjour-name Amir-M5 --host-id Amir-M5 --host-name Amir-M5 --history-url ws://127.0.0.1:4500/ --history-auth-token-file /Users/aelaguiz/workspace/codex-client/.codex-dock/app-server.token
```

Read-only Codex source check:

- `ThreadListParams` in current Codex source has no `includePreviewless` or
  equivalent exhaustive previewless option.
- SQLite thread list filtering applies `threads.preview <> ''`.
- Rollout list filtering requires session metadata and a discoverable preview.
- `thread/read` can still read a stored thread with an empty preview when the
  caller already knows the thread ID.

Live service refresh:

```text
rtk make dock-relay-restart
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- Raw app-server ready on `ws://127.0.0.1:4500`.
- Dock relay ready on `ws://127.0.0.1:4510`.

Live parity command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --include-thread-reads --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-live-after-cleanup.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1512,
  "sqliteThreadCount": 1513,
  "sqliteAppServerListableThreadCount": 1512,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "directReadProbes": 1,
  "storageDisagreements": 178,
  "listRowInconsistencies": 47,
  "readDetailDisagreements": 20,
  "goalParity": {
    "relayGoalCount": 142,
    "sqliteGoalCount": 165,
    "sqliteGoalsWithThreadRow": 142,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1187,
    "sqliteSpawnEdgesWithRelayChild": 1187,
    "parentMismatches": 0,
    "relaySourceParentsWithoutEdge": 0,
    "storageSourceParentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1512,
    "expectedActiveListableCount": 1512,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "lanes": {
      "agent": 1285,
      "human": 227
    }
  },
  "errors": 0,
  "warnings": 687,
  "info": 25,
  "sqliteStableGoalsDuringAudit": false,
  "sqliteGoalRowsChangedDuringAudit": 3
}
```

Meaning:

- The relay snapshot is complete for every current app-server-listable thread.
- The app-facing `dock/subscribe` stream is complete for every current active
  app-server-listable thread.
- `dock/subscribe` returned no archived rows, no duplicate session IDs, and no
  duplicate thread IDs.
- Spawn parent/child parity is exact for current app-server-listable spawned
  rows: 1187 of 1187 child edges matched.
- The one missing SQLite thread is not app-server-listable because its preview
  is empty, but it is direct-readable by ID:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.

Remaining non-completion facts:

- Current app-server `thread/list` does not expose the previewless direct-
  readable thread, so the relay cannot discover it without bypassing
  app-server.
- `thread/goal/get` exposes goal state by thread ID, but app-server does not
  expose SQLite `goal_id`.
- There are 23 SQLite goal rows whose `thread_id` is absent from
  `state_5.sqlite.threads`; app-server does not expose a standalone orphan-goal
  list.
- Goal rows changed during the live audit, so goal state was not an atomic
  point-in-time proof.
- SQLite/current app-server metadata disagrees with older rollout
  `session_meta` for 178 threads, mostly `cwd`, `updatedAt`, and git metadata.
- App-server list scopes returned inconsistent field values for 47 fields
  across the same thread ID, mostly `cwd`, `updatedAt`, and `createdAt`.
- `thread/read` detail still disagreed with rollout metadata or routed live
  detail for 20 fields.

Current plain-English status:

- For rows app-server can list, the relay now has exact coverage, exact
  deduping, exact archive exclusion from the app-facing stream, and exact
  spawned parent coverage.
- Full 100% completion is still not proven because some true Codex storage facts
  are either not app-server-discoverable or do not yet have a defined canonical
  meaning across app-server list, app-server read, SQLite, and rollout
  `session_meta`.

## v19 Metadata Breakdown In Parity Report

Finding:

- The live audit had hundreds of warnings, but the previous summary did not
  show whether each metadata disagreement was app-server/SQLite winning,
  rollout `session_meta` winning, or neither.
- That made the remaining "metadata meaning" problem too vague.

Change:

- `scripts/dock-relay-state-parity.mjs` now adds:
  - `summary.storageDisagreementAlignment`
  - `summary.listRowInconsistencyFields`
  - `summary.readDetailDisagreementFields`
- `scripts/dock-relay-state-parity.test.mjs` now checks those breakdowns.

Verification:

```text
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
```

Result:

- `scripts/dock-relay-state-parity.test.mjs`: 15 tests passed.

Live parity command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --include-thread-reads --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-live-metadata-breakdown-v2.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1514,
  "sqliteThreadCount": 1515,
  "sqliteAppServerListableThreadCount": 1514,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "storageDisagreements": 179,
  "storageDisagreementAlignment": {
    "total": 179,
    "relayMatchesSQLite": 142,
    "relayMatchesRollout": 36,
    "relayMatchesNeither": 1,
    "byField": {
      "cwd": {
        "total": 164,
        "relayMatchesSQLite": 135,
        "relayMatchesRollout": 29
      },
      "git.branch": {
        "total": 1,
        "relayMatchesSQLite": 1
      },
      "git.sha": {
        "total": 4,
        "relayMatchesSQLite": 4
      },
      "updatedAt": {
        "total": 10,
        "relayMatchesSQLite": 2,
        "relayMatchesRollout": 7,
        "relayMatchesNeither": 1
      }
    }
  },
  "listRowInconsistencies": 47,
  "listRowInconsistencyFields": {
    "cwd": 29,
    "updatedAt": 14,
    "createdAt": 4
  },
  "readDetailDisagreements": 20,
  "readDetailDisagreementFields": {
    "status.type": 10,
    "git.sha": 8,
    "git.branch": 2
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1514,
    "expectedActiveListableCount": 1514,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0
  },
  "sqliteGoalRowsChangedDuringAudit": 4
}
```

Meaning:

- Most storage disagreements are not random: 142 of 179 current relay/app-server
  values match SQLite rather than old rollout `session_meta`.
- 36 of 179 match rollout `session_meta` instead of SQLite.
- One `updatedAt` disagreement currently matches neither source within the
  timestamp tolerance.
- The main unresolved field is `cwd`: 164 storage disagreements and 29 list-row
  cross-scope inconsistencies.
- Live-vs-history status is still visible as 10 `status.type` read-detail
  disagreements; these are expected when routed live reads see active/idle state
  and history reads see `notLoaded`, but the relay still needs to define that
  meaning explicitly for clients.

## v20 Turn Order And Surface-Conflict Proof

Finding:

- The relay could already drain `thread/turns/list`, but the parity command did
  not include that surface, so message/turn order was not proven in the live
  audit.
- `thread/turns/list` defaults to descending order in Codex app-server.
- `thread/turns/list` can return message text when `itemsView` is `summary` or
  `full`, so the parity proof should not write raw turn items to disk.

Change:

- `relay/state/snapshot` now records the turn request shape:
  `sortDirection` and `itemsView`.
- When turns are requested, the relay asks app-server for
  `itemsView: "notLoaded"` by default, so reports can prove turn IDs, order,
  status, and completeness without carrying prompt or response text.
- `scripts/dock-relay-state-parity.mjs` now supports:

```text
--include-turns
--turn-sort-direction <asc|desc>
--turn-items-view <notLoaded|summary|full>
```

- The parity summary now includes:
  - `summary.turnParity`
  - `summary.appServerSurfaceConflicts`
  - `relay.surfaceMeanings`
  - `relay.turnCoverage`
  - `relay.surfaceConflicts`

Service gotcha:

- `rtk make dock-relay-restart` twice failed with:

```text
launchctl bootstrap gui/501 /Users/aelaguiz/workspace/codex-client/.codex-dock/services/com.aelaguiz.codex-dock.app-server.plist failed with exit 5
```

- In both cases, `rtk make services` recovered the raw app-server and relay.
- After recovery, both checks passed:

```text
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- Raw app-server ready on `ws://127.0.0.1:4500`.
- Dock relay ready on `ws://127.0.0.1:4510`.

Focused verification:

```text
rtk node --check scripts/dock-relay-state-snapshot.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --test scripts/dock-relay-state-snapshot.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk npm run test:relay
git diff --check
```

Result:

- `scripts/dock-relay-state-snapshot.test.mjs`: 3 tests passed.
- `scripts/dock-relay-state-parity.test.mjs`: 16 tests passed.
- `rtk npm run test:relay`: 94 tests passed.
- `git diff --check`: passed.

Live turn-order command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --include-turns --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-live-turns.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1514,
  "sqliteThreadCount": 1515,
  "sqliteAppServerListableThreadCount": 1514,
  "appServerNotListable": 1,
  "missingListableFromRelay": 0,
  "appServerSurfaceConflicts": {
    "threadsCompared": 1514,
    "threadsWithConflicts": 41,
    "fieldConflicts": 47,
    "byField": {
      "createdAt": 4,
      "cwd": 29,
      "updatedAt": 14
    }
  },
  "turnParity": {
    "included": true,
    "source": "thread/turns/list",
    "requestedSortDirection": "desc",
    "requestedItemsView": "notLoaded",
    "threadsChecked": 1514,
    "completeThreads": 1514,
    "incompleteThreads": 0,
    "threadsWithTurns": 1514,
    "totalTurns": 5754,
    "totalPages": 1514,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0,
    "statusCounts": {
      "completed": 5039,
      "inProgress": 3,
      "interrupted": 712
    },
    "itemsViewCounts": {
      "notLoaded": 5754
    }
  },
  "dockParity": {
    "sessionCount": 1514,
    "expectedActiveListableCount": 1514,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0
  }
}
```

Meaning:

- For every app-server-listable thread, the relay can now prove complete
  `thread/turns/list` coverage in the app-server's returned order.
- The latest live turn proof covered 5754 app-server turns across 1514 threads.
- No app-server turn pages were incomplete.
- No duplicate turn IDs were found inside a thread.
- No relay ordinal mismatches were found; the relay preserved the returned
  page order.
- The proof did not write raw turn item text to the report.
- This is an app-server turn-order proof, not a raw rollout-event
  reconstruction proof.

Live full read/detail command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --include-thread-reads --include-loaded --include-goals --json-out /tmp/codex-client/relay-state-parity-20260530-live-full-after-turns.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1514,
  "sqliteThreadCount": 1515,
  "sqliteAppServerListableThreadCount": 1514,
  "appServerNotListable": 1,
  "missingListableFromRelay": 0,
  "storageDisagreements": 179,
  "listRowInconsistencies": 47,
  "readDetailDisagreements": 21,
  "readDetailDisagreementFields": {
    "status.type": 11,
    "git.sha": 8,
    "git.branch": 2
  },
  "appServerSurfaceConflicts": {
    "threadsCompared": 1514,
    "threadsWithConflicts": 1514,
    "fieldConflicts": 1742,
    "byField": {
      "createdAt": 53,
      "cwd": 164,
      "status.type": 11,
      "updatedAt": 1514
    }
  },
  "goalParity": {
    "relayGoalCount": 143,
    "sqliteGoalCount": 166,
    "sqliteGoalsWithThreadRow": 143,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1514,
    "expectedActiveListableCount": 1514,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0
  },
  "sqliteGoalRowsChangedDuringAudit": 4
}
```

Meaning:

- Exact app-server-listable thread coverage is still proven: 1514 of 1514.
- App-facing `dock/subscribe` still excludes archived rows and matches the
  active app-server-listable set exactly.
- Current-thread goal coverage is exact through `thread/goal/get`: 143 of 143.
- Spawn parent edges are exact for app-server-listable spawned rows: 1189 of
  1189.
- App-server surface conflicts are now explicit instead of hidden. With
  thread/read included, every thread has an `updatedAt` disagreement between at
  least two app-server surfaces, which confirms `thread/read.updatedAt` still
  needs a defined meaning before clients can treat it as canonical freshness.

Current non-completion facts after v20:

- One real SQLite thread is still direct-readable but not discoverable through
  app-server `thread/list` because its preview is empty:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- App-server still does not expose SQLite `goal_id`.
- `goals_1.sqlite` still has 23 goal rows whose `thread_id` is absent from
  current `state_5.sqlite.threads`.
- Goal rows changed during both live audits, so goal parity is not an atomic
  point-in-time proof.
- Metadata meaning conflicts remain across app-server list scopes,
  app-server read surfaces, SQLite, and rollout `session_meta`.

## v21 Exhaustive Full-Item Audit And Moving-State Correction

Finding:

- The v20 turn proof used `itemsView: "notLoaded"`, so it proved turn IDs,
  order, status, and completeness, but not full turn item availability.
- A first full-item run exceeded the verifier's fixed 120 second JSON-RPC
  timeout:

```text
relay-state-parity failed: timed out waiting for relay/state/snapshot from ws://127.0.0.1:4510
```

- Relay logs showed that request eventually completed in about 150533 ms, but
  the verifier had already disconnected, so no report was written.
- A later run also caught a real moving-state case: a new app-server-listable
  SQLite thread appeared while the audit was running. That must be marked as
  audit movement, not a relay miss.

Change:

- `scripts/dock-relay-state-parity.mjs` now supports:

```text
--exhaustive
--request-timeout-ms <n>
```

- `--exhaustive` includes thread reads, loaded state, goals, turns,
  `dock/subscribe`, and full turn item availability.
- Full turn items are requested from app-server, but the report stores only
  counts and item type counts. It does not write prompt text, response text, or
  raw turn items.
- The parity verifier now separates stable relay misses from thread rows that
  were added or removed while the audit was running:
  - `sqliteThreadRowsAddedDuringAudit`
  - `sqliteThreadRowsRemovedDuringAudit`
  - `missingFromRelayDueToAuditMovement`
  - `missingListableFromRelayDueToAuditMovement`
  - `extraInRelayDueToAuditMovement`
  - `dockParity.missingActiveListableFromDockDueToAuditMovement`

Focused verification:

```text
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
```

Result:

- `scripts/dock-relay-state-parity.test.mjs`: 19 tests passed.

Live exhaustive command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v2.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1515,
  "sqliteThreadCount": 1516,
  "sqliteAppServerListableThreadCount": 1515,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingFromRelayDueToAuditMovement": 0,
  "missingListableFromRelay": 0,
  "missingListableFromRelayDueToAuditMovement": 0,
  "extraInRelay": 0,
  "extraInRelayDueToAuditMovement": 0,
  "sqliteStableIDsDuringAudit": true,
  "sqliteThreadRowsAddedDuringAudit": 0,
  "sqliteThreadRowsRemovedDuringAudit": 0,
  "turnParity": {
    "included": true,
    "requestedItemsView": "full",
    "threadsChecked": 1515,
    "completeThreads": 1515,
    "incompleteThreads": 0,
    "threadsWithTurns": 1515,
    "totalTurns": 5761,
    "totalItems": 217418,
    "turnsWithItems": 5648,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0,
    "itemsViewCounts": {
      "full": 5761
    },
    "itemTypeCounts": {
      "agentMessage": 76925,
      "commandExecution": 102,
      "contextCompaction": 3460,
      "fileChange": 55487,
      "hookPrompt": 14,
      "mcpToolCall": 6962,
      "plan": 183,
      "reasoning": 69110,
      "userMessage": 4413,
      "webSearch": 762
    }
  },
  "goalParity": {
    "relayGoalCount": 143,
    "sqliteGoalCount": 166,
    "sqliteGoalsWithThreadRow": 143,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1515,
    "expectedActiveListableCount": 1515,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "missingActiveListableFromDockDueToAuditMovement": 0,
    "extraDockSessions": 0
  },
  "errors": 0,
  "warnings": 697,
  "sqliteGoalRowsChangedDuringAudit": 3
}
```

Meaning:

- The current exhaustive app-server proof is exact for stable
  app-server-listable threads: 1515 of 1515.
- Normal app-facing `dock/subscribe` exactly matched the active
  app-server-listable set and excluded archived threads.
- Full turn item availability is proven through app-server
  `thread/turns/list`: 217418 returned items across 5761 turns.
- The report still avoids storing raw prompt or response text.
- Thread IDs were stable during the successful exhaustive run.
- Goal rows still changed during the run, so goal state is still not an atomic
  point-in-time proof.

Current non-completion facts after v21:

- The stable missing thread is still the previewless direct-readable CLI thread
  outside app-server `thread/list` discovery:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- App-server still does not expose SQLite `goal_id`.
- `goals_1.sqlite` still has 23 goal rows whose `thread_id` is absent from
  current `state_5.sqlite.threads`.
- Metadata meaning conflicts remain across app-server list scopes,
  app-server read surfaces, SQLite, and rollout `session_meta`.

## v22 Dock Order Proof And Freshness Movement Classification

Finding:

- `dock/subscribe` had proven the right active session set, but it had not
  proven order.
- The first live order check found a real problem:
  `dock/subscribe` returned 1515 of 1515 active app-server-listable sessions,
  but it had 20 order mismatches against app-server
  `active:allSourceKinds` order.
- After changing the relay to build `dock/subscribe` from one combined
  app-server `thread/list` source scope, the mismatch count dropped but did not
  disappear. The remaining differences were caused by active rows changing
  `updatedAt` between the relay snapshot read and the later dock snapshot read.

Change:

- `scripts/dock-relay-session-table.mjs` now builds the main app-facing session
  order from a single combined app-server `thread/list` request using explicit
  source kinds:

```text
cli, vscode, exec, appServer, subAgent, subAgentReview, subAgentCompact,
subAgentThreadSpawn, subAgentOther, unknown
```

- Default interactive rows are still fetched as an extra source so custom
  interactive rows can be included if Codex exposes them there but not through
  explicit `sourceKinds`.
- `dock/subscribe` snapshots now refresh before returning instead of relying
  only on the periodic cached table.
- `scripts/dock-relay-state-parity.mjs` now checks `dock/subscribe` order
  against app-server `active:allSourceKinds` order and separates:
  - stable order mismatches, which are relay bugs;
  - freshness movement, where compared rows changed timestamps during the audit.

Focused verification:

```text
rtk node --check scripts/dock-relay-session-table.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --test scripts/dock-relay.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk npm run test:relay
git diff --check
```

Result:

- `scripts/dock-relay.test.mjs`: 27 tests passed.
- `scripts/dock-relay-state-parity.test.mjs`: 21 tests passed.
- `rtk npm run test:relay`: 99 tests passed.
- `git diff --check`: passed.

Service reload:

```text
rtk make dock-relay-restart
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- `rtk make dock-relay-restart` succeeded after one earlier known launchd
  bootstrap failure that was recovered with `rtk make services`.
- Both status targets reported `status: "ready"` with active raw app-server and
  Dock relay services.

Latest live exhaustive command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v4-dock-order-fix.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1515,
  "sqliteThreadCount": 1516,
  "sqliteAppServerListableThreadCount": 1515,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "sqliteThreadRowsAddedDuringAudit": 0,
  "sqliteThreadRowsRemovedDuringAudit": 0,
  "turnParity": {
    "included": true,
    "requestedItemsView": "full",
    "threadsChecked": 1515,
    "completeThreads": 1515,
    "incompleteThreads": 0,
    "threadsWithTurns": 1515,
    "totalTurns": 5765,
    "totalItems": 217981,
    "turnsWithItems": 5652,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0
  },
  "goalParity": {
    "relayGoalCount": 143,
    "sqliteGoalCount": 166,
    "sqliteGoalsWithThreadRow": 143,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1515,
    "expectedActiveListableCount": 1515,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "codexOrderCompared": true,
    "codexOrderComparableThreads": 1515,
    "codexOrderMismatches": 3,
    "codexOrderStableMismatches": 0,
    "codexOrderMismatchesDueToFreshnessMovement": 3
  },
  "errors": 0,
  "warnings": 686,
  "sqliteGoalRowsChangedDuringAudit": 4
}
```

Meaning:

- Stable app-facing order bugs are now at zero in the latest exhaustive run.
- The three order differences were not stable order bugs; they were explicitly
  classified as active row timestamp movement during the audit.
- Full turn item availability is still proven through app-server
  `thread/turns/list`: 217981 returned items across 5765 turns.
- The relay still cannot call this whole state 100% complete because the
  underlying Codex state moves while the audit runs and because the app-server
  still has the previewless, goal identity, orphan goal, and metadata meaning
  gaps listed below.

Current non-completion facts after v22:

- The stable missing thread is still the previewless direct-readable CLI thread
  outside app-server `thread/list` discovery:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- App-server still does not expose SQLite `goal_id`.
- `goals_1.sqlite` still has 23 goal rows whose `thread_id` is absent from
  current `state_5.sqlite.threads`.
- Goal rows changed during the exhaustive audit, so goal parity is not an
  atomic point-in-time proof.
- Metadata meaning conflicts remain across app-server list scopes,
  app-server read surfaces, SQLite, and rollout `session_meta`.

## v23 App-Server Thread Search Surface And Missing-Thread Probe

Finding:

- Raw Codex app-server exposes `thread/search`, and the relay did not forward
  it yet.
- `thread/search` is not a replacement for global enumeration because it
  requires a non-empty `searchTerm`.
- A raw app-server probe did not find the stable previewless missing thread by
  thread ID, cwd basename, branch/path text, or git SHA prefix.

Change:

- `scripts/dock-relay-thread-data.mjs` now forwards `thread/search` to the
  configured history app-server through the same Mac-side app-server token path
  as `thread/list`.
- `scripts/dock-relay.mjs` now accepts the JSON-RPC method `thread/search`.
- Relay search responses preserve app-server search order and pagination
  fields, while stripping relay-only `dockRelaySource` data from returned
  thread rows.
- `scripts/dock-relay-state-parity.mjs` now probes SQLite rows missing from
  relay `thread/list` through relay `thread/search` using safe known terms:
  thread ID, cwd basename, git branch, and git SHA prefix. The report stores
  fingerprints for the searched terms and thread IDs for returned rows, not
  raw prompt text or search snippets.

Focused verification:

```text
rtk node --check scripts/dock-relay-thread-data.mjs
rtk node --check scripts/dock-relay.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --check scripts/dock-relay-state-snapshot.mjs
rtk node --test scripts/dock-relay.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay-state-snapshot.test.mjs
```

Result:

- `scripts/dock-relay.test.mjs`: 28 tests passed.
- `scripts/dock-relay-state-parity.test.mjs`: 22 tests passed.
- `scripts/dock-relay-state-snapshot.test.mjs`: 3 tests passed.

Service reload:

```text
rtk make dock-relay-restart
rtk make services
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- `rtk make dock-relay-restart` hit the known launchd failure:
  `launchctl bootstrap gui/501 /Users/aelaguiz/workspace/codex-client/.codex-dock/services/com.aelaguiz.codex-dock.app-server.plist failed with exit 5`.
- `rtk make services` recovered and both status targets reported
  `status: "ready"`.

Latest live exhaustive command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v5-thread-search.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1515,
  "sqliteThreadCount": 1516,
  "sqliteAppServerListableThreadCount": 1515,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "sqliteThreadRowsAddedDuringAudit": 0,
  "sqliteThreadRowsRemovedDuringAudit": 0,
  "directReadProbes": 1,
  "searchProbeAttempts": 8,
  "searchProbeRows": 1,
  "missingSearchDiscoverable": 0,
  "missingSearchNotDiscoverable": 1,
  "turnParity": {
    "included": true,
    "requestedItemsView": "full",
    "threadsChecked": 1515,
    "completeThreads": 1515,
    "incompleteThreads": 0,
    "totalTurns": 5774,
    "totalItems": 217784,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0
  },
  "goalParity": {
    "relayGoalCount": 143,
    "sqliteGoalCount": 166,
    "sqliteGoalsWithThreadRow": 143,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1515,
    "expectedActiveListableCount": 1515,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "codexOrderCompared": true,
    "codexOrderComparableThreads": 1515,
    "codexOrderMismatches": 5,
    "codexOrderStableMismatches": 0,
    "codexOrderMismatchesDueToFreshnessMovement": 5
  },
  "errors": 0,
  "warnings": 681,
  "sqliteGoalRowsChangedDuringAudit": 3
}
```

Meaning:

- The relay now has a clean app-server-backed `thread/search` method.
- The stable missing thread is direct-readable by `thread/read`, but it was not
  found by relay `thread/search` using safe known terms in either default
  interactive or explicit all-source scopes.
- That means the remaining missing thread is still an app-server discovery gap,
  not a reason for the relay to read disk.
- Stable app-facing order bugs are still zero. The five order differences were
  timestamp movement during the audit.
- Full turn item availability is still proven through app-server
  `thread/turns/list`: 217784 returned items across 5774 turns.

Current non-completion facts after v23:

- The stable missing thread is still the previewless direct-readable CLI thread
  outside app-server `thread/list` discovery and outside the safe-term
  `thread/search` probe results:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- App-server still does not expose SQLite `goal_id`.
- `goals_1.sqlite` still has 23 goal rows whose `thread_id` is absent from
  current `state_5.sqlite.threads`.
- Goal rows changed during the exhaustive audit, so goal parity is not an
  atomic point-in-time proof.
- Metadata meaning conflicts remain across app-server list scopes,
  app-server read surfaces, SQLite, and rollout `session_meta`.

## v24 Direct App-Server Goal Read Surface And Capability Boundaries

Finding:

- Codex app-server protocol exposes `thread/goal/get`, and the relay snapshot
  was already using it internally, but the relay did not expose it as a normal
  client-callable JSON-RPC method.
- Codex app-server `ThreadGoal` exposes `threadId`, `objective`, `status`,
  `tokenBudget`, `tokensUsed`, `timeUsedSeconds`, `createdAt`, and
  `updatedAt`. It does not expose SQLite `goal_id`.
- Codex SQLite goal state includes `goal_id`, but
  `api_thread_goal_from_state` intentionally maps only the app-server fields.
- `thread/goal/get` is keyed by a known `threadId` and requires a materialized
  thread. It is not a standalone goal list, so orphan goal rows whose
  `thread_id` is absent from `state_5.sqlite.threads` are outside the current
  app-server goal surface.
- `thread/search` is a required-term rollout-content search, not a global
  enumeration surface.
- `thread/read` can read the stable missing previewless thread when the ID is
  already known, but app-server `thread/list` and safe-term `thread/search`
  still do not discover it.
- App-server thread read/list/search/turn/goal responses do not include one
  shared snapshot ID, revision, transaction token, or other cross-surface
  atomicity marker.
- Metadata conflict meaning is now narrowed: `thread/list` and `thread/search`
  map `StoredThread` rows through `thread_from_stored_thread`, while
  `thread/read` loads persisted metadata, optionally overlays live state, and
  can follow a different metadata path for the same thread. The relay can
  report those disagreements, but Codex does not expose a canonical conflict
  winner field.
- Codex protocol lists `thread/turns/items/list`, but current app-server code
  returns `method_not_found` with
  `thread/turns/items/list is not supported yet`; this is not an exposed
  app-server detail surface yet.

Codex source evidence read-only:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:666`
  defines `ThreadGoal` without `goal_id`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:726`
  defines `ThreadGoalGetParams` as only `thread_id`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_goal_processor.rs:251`
  reads goals by `threadId` through `thread_goal_get_inner`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_goal_processor.rs:339`
  requires a materialized thread before goal access.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_goal_processor.rs:483`
  maps state goals to the app-server API shape and omits `goal_id`.
- `/Users/aelaguiz/workspace/codex/codex-rs/state/src/model/thread_goal.rs:59`
  shows SQLite/state `ThreadGoal` does have `goal_id`.
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/search_threads.rs:35`
  requires a non-empty search term and searches rollout content paths.
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/read_thread.rs:48`
  shows `thread/read` can return SQLite metadata for a known previewless
  rollout-backed thread.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1048`
  through `:1191` show the thread list/search/loaded/read/turn responses carry
  data and cursors, not a shared audit snapshot or transaction marker.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1796`
  shows `thread/list` reads from `list_threads_common`, maps `StoredThread`
  rows with `thread_from_stored_thread`, and overlays loaded statuses.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:1877`
  shows `thread/search` maps search results through the same
  `thread_from_stored_thread` API shape.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:2049`
  shows `thread/read` goes through `read_thread_view`, which may use persisted
  metadata, live state, or both.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:628`
  returns `method_not_found` for `thread/turns/items/list`.

Change:

- `scripts/dock-relay-thread-data.mjs` now exposes
  `aggregateThreadGoalGet`.
- `scripts/dock-relay.mjs` now accepts the relay method `thread/goal/get`.
- The relay routes `thread/goal/get` to the owning live app-server when a
  thread is loaded there, and falls back to the history app-server for stored
  threads.
- `scripts/dock-relay-status.mjs` now classifies `thread/search` and
  `thread/goal/get` failures as history-style retryable app-server reads.
- `scripts/dock-relay-state-parity.mjs` blind-spot wording now says a run did
  not include goal reads, instead of implying the relay cannot expose
  `thread/goal/get`.

Focused verification:

```text
rtk node --check scripts/dock-relay-thread-data.mjs
rtk node --check scripts/dock-relay.mjs
rtk node --check scripts/dock-relay-status.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --check scripts/dock-relay-phase5.test.mjs
rtk node --test scripts/dock-relay.test.mjs
rtk node --test scripts/dock-relay-phase5.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk npm run test:relay
```

Result:

- `scripts/dock-relay.test.mjs`: 29 tests passed.
- `scripts/dock-relay-phase5.test.mjs`: 33 tests passed.
- `scripts/dock-relay-state-parity.test.mjs`: 22 tests passed.
- Full relay suite: 103 tests passed.

Service reload:

```text
rtk make dock-relay-restart
rtk make services
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- `rtk make dock-relay-restart` hit the known launchd failure:
  `launchctl bootstrap gui/501 /Users/aelaguiz/workspace/codex-client/.codex-dock/services/com.aelaguiz.codex-dock.app-server.plist failed with exit 5`.
- `rtk make services` recovered.
- Both status targets reported `status: "ready"`.

Direct live relay proof:

```text
ws://127.0.0.1:4510 thread/goal/get threadId=019e7456-af5f-7561-9cb2-0db296c62b49
```

Result:

```json
{
  "goalPresent": true,
  "threadId": "019e7456-af5f-7561-9cb2-0db296c62b49",
  "fields": [
    "createdAt",
    "objective",
    "status",
    "threadId",
    "timeUsedSeconds",
    "tokenBudget",
    "tokensUsed",
    "updatedAt"
  ]
}
```

Latest live exhaustive command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v6-direct-goal-get.json --summary-only
```

Real-run result:

```json
{
  "relayThreadCount": 1516,
  "sqliteThreadCount": 1517,
  "sqliteAppServerListableThreadCount": 1516,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "sqliteThreadRowsAddedDuringAudit": 0,
  "sqliteThreadRowsRemovedDuringAudit": 0,
  "directReadProbes": 1,
  "searchProbeAttempts": 8,
  "searchProbeRows": 1,
  "missingSearchDiscoverable": 0,
  "missingSearchNotDiscoverable": 1,
  "turnParity": {
    "threadsChecked": 1516,
    "completeThreads": 1516,
    "incompleteThreads": 0,
    "totalTurns": 5781,
    "totalItems": 218131,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0
  },
  "goalParity": {
    "relayGoalCount": 145,
    "sqliteGoalCount": 168,
    "sqliteGoalsWithThreadRow": 145,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "goalReadErrors": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1516,
    "expectedActiveListableCount": 1516,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "codexOrderCompared": true,
    "codexOrderComparableThreads": 1516,
    "codexOrderMismatches": 4,
    "codexOrderStableMismatches": 0,
    "codexOrderMismatchesDueToFreshnessMovement": 4
  },
  "storageDisagreements": 177,
  "listRowInconsistencies": 46,
  "readDetailDisagreements": 19,
  "errors": 0,
  "warnings": 690,
  "sqliteGoalRowsChangedDuringAudit": 4
}
```

Meaning:

- The relay now has clean app-server-backed read methods for `thread/list`,
  `thread/search`, `thread/read`, `thread/turns/list`, `thread/loaded/list`,
  `thread/goal/get`, `dock/subscribe`, and `relay/state/snapshot`.
- The latest live proof has zero missing app-server-listable threads, zero
  duplicate app-facing session/thread IDs, zero archived app-facing sessions,
  zero turn order/id failures, zero spawned parent mismatches, and zero stable
  dock-order mismatches.
- The latest live proof is still not 100% complete against true Codex storage
  because the remaining gaps are app-server capability or meaning boundaries,
  not relay disk-reading problems.

Current non-completion facts after v24:

- The stable missing thread is still the previewless direct-readable CLI thread
  outside app-server `thread/list` discovery and outside the safe-term
  `thread/search` probe results:
  `019e56d4-4339-76a1-9ef3-37f081af3f08`.
- App-server still does not expose SQLite `goal_id`.
- `goals_1.sqlite` still has 23 goal rows whose `thread_id` is absent from
  current `state_5.sqlite.threads`.
- Four goal rows changed during the exhaustive audit, so goal parity is not an
  atomic point-in-time proof.
- Metadata meaning conflicts remain across app-server list scopes,
  app-server read surfaces, SQLite, and rollout `session_meta`.

## v25 - Prompt Shape And Output-Schema History Boundary

Question closed in this pass:

- The goals doc said the relay must know true mode/start shape when Codex
  exposes it, including JSON/output-schema turns and prompt-started work.
- The previous exhaustive run proved full turn order and item counts, but did
  not separately report what could be known from those items about prompt shape
  or output-schema mode.

Codex source evidence, read-only:

- `codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
  - `ThreadStartSource` is `startup | clear`.
  - `ThreadStartParams.session_start_source` is a start request parameter.
  - That field is not part of historical thread list/read/turn response rows.
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
  - `session_start_source` only selects `InitialHistory::New` or
    `InitialHistory::Cleared` while starting the thread.
- `codex-rs/app-server-protocol/src/protocol/v2/turn.rs`
  - `TurnStartParams.output_schema` is a turn-start request parameter.
- `codex-rs/app-server/src/request_processors/turn_processor.rs`
  - `params.output_schema` is passed into core as
    `final_output_json_schema`.
- `codex-rs/app-server-protocol/src/protocol/thread_history.rs`
  - historical user prompts become `ThreadItem::UserMessage` items in turns.
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadItem.ts`
  - the generated historical `ThreadItem` union has `userMessage`,
    `agentMessage`, `reasoning`, `commandExecution`, `fileChange`,
    `mcpToolCall`, and related item variants, but no output-schema field.

Relay audit changes:

- `scripts/dock-relay-state-parity.mjs`
  - now reports `summary.turnParity.startShape`;
  - counts threads with any `userMessage` item;
  - counts whether the oldest returned turn has a `userMessage` item;
  - reports threads with no turns;
  - now reports `summary.turnParity.outputSchemaEvidence`;
  - checks only top-level turn/item field names for output-schema evidence, so
    user JSON or tool arguments cannot create false JSON-mode evidence.
- `scripts/dock-relay-state-snapshot.mjs`
  - now documents that full `thread/turns/list` items expose user-message
    evidence for prompt-shape inference, not a formal historical start source.
- `scripts/dock-relay-state-parity.test.mjs`
  - now proves the new counters without leaking prompt text, response text, or
    schema text.
- `scripts/dock-relay-state-snapshot.test.mjs`
  - updated the surface meaning assertion.

Verification:

```text
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --check scripts/dock-relay-state-snapshot.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay-state-snapshot.test.mjs
git diff --check
rtk npm run test:relay
```

Result:

- `scripts/dock-relay-state-parity.test.mjs`: 22 passed.
- `scripts/dock-relay-state-snapshot.test.mjs`: 3 passed.
- `rtk npm run test:relay`: 103 passed.
- `git diff --check`: passed.

Live service status before the proof run:

```text
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- Both reported `"status": "ready"`.
- Raw app-server `http://127.0.0.1:4500/readyz` was `200`.
- Dock relay `http://127.0.0.1:4510/readyz` was `200`.
- Dock relay `statusz` had `"snapshotOK": true`.

Latest live exhaustive command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v7-start-shape-output-schema.json --summary-only
```

Real-run result:

```json
{
  "generatedAt": "2026-05-30T03:10:37.836Z",
  "relayThreadCount": 1516,
  "sqliteThreadCount": 1517,
  "sqliteAppServerListableThreadCount": 1516,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "turnParity": {
    "threadsChecked": 1516,
    "completeThreads": 1516,
    "incompleteThreads": 0,
    "totalTurns": 5784,
    "totalItems": 218594,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0,
    "itemsViewCounts": {
      "full": 5784
    },
    "startShape": {
      "threadsWithAnyUserMessageItem": 1492,
      "threadsWithoutUserMessageItem": 24,
      "threadsWithOldestTurnUserMessage": 1419,
      "threadsWithOldestTurnNoUserMessage": 97,
      "threadsWithoutTurns": 0
    },
    "outputSchemaEvidence": {
      "threadsWithEvidence": 0,
      "turnsWithEvidence": 0,
      "itemsWithEvidence": 0,
      "historicalStateObserved": false
    }
  },
  "goalParity": {
    "relayGoalCount": 145,
    "sqliteGoalCount": 168,
    "sqliteGoalsWithThreadRow": 145,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "goalReadErrors": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1516,
    "expectedActiveListableCount": 1516,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "codexOrderMismatches": 2,
    "codexOrderStableMismatches": 0,
    "codexOrderMismatchesDueToFreshnessMovement": 2
  },
  "storageDisagreements": 178,
  "listRowInconsistencies": 46,
  "readDetailDisagreements": 19,
  "errors": 0,
  "warnings": 689,
  "sqliteGoalRowsChangedDuringAudit": 4
}
```

Meaning:

- The relay can now objectively show app-server-exposed prompt-shape evidence
  from full `thread/turns/list` items without storing prompt text.
- The relay cannot honestly claim historical JSON/output-schema mode from
  current app-server read surfaces. The request exists at `turn/start`, but the
  historical app-server item/turn shape does not expose it.
- The 100% objective is still not complete because the remaining misses are
  real app-server capability or meaning boundaries:
  previewless discovery, goal ID, orphan goals, non-atomic goal movement,
  formal historical start source, historical output-schema mode, and metadata
  conflict meaning.

## v26 - Relay Canonical App-Server Metadata Projection

Problem:

- The audit already showed app-server list/read surface conflicts, but it did
  not expose a deterministic relay-owned winner for each metadata field.
- That left the relay with conflict evidence but not a clean app-server
  projection a client or verifier could inspect.

Change:

- `scripts/dock-relay-state-snapshot.mjs`
  - now adds `surfaceSummary.canonicalProjection` for each thread;
  - projection meaning: deterministic relay app-server projection only;
  - no disk or SQLite data is used;
  - field priority is explicit:
    1. `routed thread/read`
    2. `history thread/read`
    3. `thread/list:allSourceKinds`
    4. `thread/list:interactiveDefault`
    5. other `thread/list`
  - each projected field includes the value, winning source surface,
    `valueCount`, and `hasConflict`.
- `scripts/dock-relay-state-parity.mjs`
  - now summarizes the projection as `summary.relayCanonicalProjection`;
  - counts compared threads, projected threads, missing projections, field
    counts, conflict fields, and winning source surface counts.
- `scripts/dock-relay-state-snapshot.test.mjs`
  - proves the projection picks `routed thread/read` over stale list metadata.
- `scripts/dock-relay-state-parity.test.mjs`
  - proves the parity summary counts canonical projection conflicts.

Verification:

```text
rtk node --check scripts/dock-relay-state-snapshot.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --test scripts/dock-relay-state-snapshot.test.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
git diff --check
rtk npm run test:relay
```

Result:

- `scripts/dock-relay-state-snapshot.test.mjs`: 3 passed.
- `scripts/dock-relay-state-parity.test.mjs`: 22 passed.
- `rtk npm run test:relay`: 103 passed.
- `git diff --check`: passed.

Service reload:

```text
rtk make dock-relay-restart
```

Result:

- Failed with the known launchd bootstrap blocker:
  `launchctl bootstrap gui/501 /Users/aelaguiz/workspace/codex-client/.codex-dock/services/com.aelaguiz.codex-dock.app-server.plist failed with exit 5`.

Recovery:

```text
rtk make services
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- `rtk make services` recovered and installed/started the services.
- `rtk make app-server-status` reported `"status": "ready"`.
- `rtk make dock-relay-status` reported `"status": "ready"`.
- Raw app-server and dock relay health checks both returned `200`.

Latest live exhaustive command:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v8-canonical-projection.json --summary-only
```

Real-run result:

```json
{
  "generatedAt": "2026-05-30T03:16:46.984Z",
  "relayThreadCount": 1516,
  "sqliteThreadCount": 1517,
  "sqliteAppServerListableThreadCount": 1516,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "relayCanonicalProjection": {
    "included": true,
    "threadsCompared": 1516,
    "threadsWithProjection": 1516,
    "missingProjectionThreads": 0,
    "threadsWithCanonicalConflicts": 1516,
    "projectedFields": 22731,
    "conflictingProjectedFields": 1742,
    "priority": [
      "routed thread/read",
      "history thread/read",
      "thread/list:allSourceKinds",
      "thread/list:interactiveDefault",
      "thread/list"
    ],
    "sourceCounts": {
      "routed thread/read": 22731
    },
    "conflictFields": {
      "createdAt": 53,
      "cwd": 164,
      "status.type": 9,
      "updatedAt": 1516
    }
  },
  "turnParity": {
    "threadsChecked": 1516,
    "completeThreads": 1516,
    "incompleteThreads": 0,
    "totalTurns": 5786,
    "totalItems": 218589,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1516,
    "expectedActiveListableCount": 1516,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "codexOrderMismatches": 0,
    "codexOrderStableMismatches": 0,
    "codexOrderMismatchesDueToFreshnessMovement": 0
  },
  "goalParity": {
    "relayGoalCount": 145,
    "sqliteGoalCount": 168,
    "sqliteGoalsWithThreadRow": 145,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "goalReadErrors": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1189,
    "sqliteSpawnEdgesWithRelayChild": 1189,
    "parentMismatches": 0
  },
  "storageDisagreements": 177,
  "listRowInconsistencies": 44,
  "readDetailDisagreements": 19,
  "errors": 0,
  "warnings": 689,
  "sqliteGoalRowsChangedDuringAudit": 4
}
```

Meaning:

- Relay-side app-server metadata projection is now clean and objective:
  every compared thread has a deterministic field winner and source surface.
- In this live run, every projected field was won by `routed thread/read`.
- The projection does not claim to solve Codex storage truth when SQLite and
  rollout `session_meta` disagree. It solves the relay's app-server-surface
  ambiguity.
- The remaining non-completion facts are now narrower:
  previewless discovery, app-server goal ID, orphan goals, non-atomic goal
  movement, formal historical start source, historical output-schema mode, and
  Codex storage metadata meaning.

## v27 - Dock Live Status Parity And Completion Boundary

Problem:

- `thread/loaded/list` proved which sessions were loaded/live, but
  `dock/subscribe` could still normalize those same app-facing rows as
  `dormant` because the session table used stored `thread/list` rows only.
- The parity report also had no single machine-readable answer for "are all
  app-server-exposed relay requirements complete?"

Change:

- `scripts/dock-relay-session-table.mjs`
  - now overlays live `status` and live `sessionId` from app-server live rows
    onto the app-facing `dock/subscribe` row for the same thread;
  - preserves stored `thread/list` row order, `updatedAt`, summary, title, and
    inclusion set;
  - does not add disk/SQLite reads to relay runtime.
- `scripts/dock-relay-state-parity.mjs`
  - compares `dock/subscribe` status against `thread/loaded/list` plus the best
    relay status evidence, preferring routed `thread/read`;
  - stops treating intentionally stored `thread/list` status as the live-status
    source when routed `thread/read` is available;
  - adds `summary.completionBoundary` with app-server-exposed checks, moving
    state, outside-app-server-support facts, and storage meaning conflicts.
- `scripts/dock-relay.test.mjs`
  - proves `dock/subscribe` overlays live status while preserving stored Codex
    order and stored summary/update metadata.
- `scripts/dock-relay-state-parity.test.mjs`
  - proves the parity audit flags a loaded app-server session shown as
    `dormant` by `dock/subscribe`.
- `docs/CODEX_DOCK_GOALS_2026-05-29.md`
  - now separates app-server-exposed completion from app-server-not-provided
    boundaries;
  - records the v10 stable live exhaustive audit as app-server-exposed complete.

Verification:

```text
rtk node --check scripts/dock-relay-session-table.mjs
rtk node --check scripts/dock-relay-state-parity.mjs
rtk node --test scripts/dock-relay-state-parity.test.mjs
rtk node --test scripts/dock-relay.test.mjs
git diff --check
rtk npm run test:relay
rtk make dock-relay-restart
rtk make app-server-status
rtk make dock-relay-status
```

Result:

- `scripts/dock-relay-state-parity.test.mjs`: 23 passed.
- `scripts/dock-relay.test.mjs`: 30 passed.
- `rtk npm run test:relay`: 105 passed.
- `git diff --check`: passed.
- `rtk make dock-relay-restart`: succeeded through launchd.
- `rtk make app-server-status`: `status: "ready"`.
- `rtk make dock-relay-status`: `status: "ready"`.

First live exhaustive proof after the patch:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v9-dock-live-status.json --summary-only
```

Important result:

- `dockParity.loadedStatusCompared`: `true`.
- `dockParity.loadedThreadCount`: `11`.
- `dockParity.loadedDockSessionsCompared`: `11`.
- `dockParity.loadedDockStatusMismatches`: `0`.
- `dockParity.staleLiveDockSessions`: `0`.
- v9 was not a stable completion proof because 3 app-server-listable spawned
  rows appeared during the audit.

Stable live exhaustive proof:

```text
rtk node -- scripts/dock-relay-state-parity.mjs --exhaustive --request-timeout-ms 600000 --json-out /tmp/codex-client/relay-state-parity-20260530-live-exhaustive-full-items-v10-stability-rerun.json --summary-only
```

Real-run result:

```json
{
  "generatedAt": "2026-05-30T03:29:56.383Z",
  "relayThreadCount": 1519,
  "sqliteThreadCount": 1520,
  "sqliteAppServerListableThreadCount": 1519,
  "appServerNotListable": 1,
  "missingFromRelay": 1,
  "missingListableFromRelay": 0,
  "extraInRelay": 0,
  "sqliteStableIDsDuringAudit": true,
  "relayCanonicalProjection": {
    "threadsCompared": 1519,
    "threadsWithProjection": 1519,
    "missingProjectionThreads": 0,
    "projectedFields": 22776,
    "conflictingProjectedFields": 1747,
    "sourceCounts": {
      "routed thread/read": 22776
    }
  },
  "turnParity": {
    "threadsChecked": 1519,
    "completeThreads": 1519,
    "incompleteThreads": 0,
    "totalTurns": 5797,
    "totalItems": 219595,
    "duplicateTurnIDThreads": 0,
    "duplicateTurnIDs": 0,
    "ordinalMismatches": 0
  },
  "dockParity": {
    "sessionCount": 1519,
    "expectedActiveListableCount": 1519,
    "archivedThreadCount": 0,
    "duplicateSessionIDs": 0,
    "duplicateThreadIDs": 0,
    "missingActiveListableFromDock": 0,
    "extraDockSessions": 0,
    "codexOrderStableMismatches": 0,
    "codexOrderMismatchesDueToFreshnessMovement": 5,
    "loadedStatusCompared": true,
    "loadedThreadCount": 11,
    "loadedDockSessionsCompared": 11,
    "loadedDockStatusMismatches": 0,
    "staleLiveDockSessions": 0
  },
  "goalParity": {
    "relayGoalCount": 145,
    "sqliteGoalCount": 168,
    "sqliteGoalsWithThreadRow": 145,
    "sqliteGoalsWithoutThreadRow": 23,
    "missingFromRelayWithThreadRow": 0,
    "extraInRelay": 0,
    "goalReadErrors": 0,
    "appServerDoesNotExposeGoalID": true
  },
  "spawnParity": {
    "sqliteSpawnEdgeCount": 1192,
    "sqliteSpawnEdgesWithRelayChild": 1192,
    "missingRelayChildForSpawnEdge": 0,
    "parentMismatches": 0
  },
  "completionBoundary": {
    "appServerExposedParityComplete": true,
    "failedAppServerChecks": [],
    "movingState": [
      "SQLite goal rows changed during this audit; app-server provides no shared snapshot ID to make cross-surface goal proof atomic."
    ]
  }
}
```

Meaning:

- App-server-exposed relay parity is now complete in the v10 stable live audit.
- The relay still does not work around app-server by reading disk or SQLite at
  runtime.
- Remaining facts are app-server boundaries, not relay implementation gaps:
  previewless global enumeration, SQLite `goal_id`, orphan goal enumeration,
  cross-surface atomic snapshot IDs, historical start source, historical
  output-schema mode, `thread/turns/items/list`, and Codex storage
  SQLite-vs-rollout meaning.
