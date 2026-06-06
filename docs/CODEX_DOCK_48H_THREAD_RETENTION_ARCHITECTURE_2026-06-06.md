# Codex Dock 48h Thread Retention Architecture

Date: 2026-06-06
Status: implemented; proof complete; strict review complete; deployed to both live relays
Owner repo: `/Users/aelaguiz/workspace/codex-client`

## Direct Answer

Codex Dock should stop collecting, proving, storing, and streaming thread cards
whose cheap activity timestamp is older than 48 hours. The canonical owner is
the Node Dock relay data path, not Swift, because the relay is the first
phone-facing layer that decides which upstream `thread/list`, `thread/read`,
and `thread/turns/list` work is worth paying for.

The elegant implementation is one retention policy used by the relay's list
drain, session-index supplement, targeted route assertions, and state cleanup.
Swift receives fewer `dock/*` and `archive/*` cards; it does not learn a new
filter mode.

## North Star

The normal Dock and Archive views show only retained human app-facing threads:

- active or archived human root threads with activity inside the last 48 hours;
- currently loaded live human threads, even if their stored history timestamp is
  older than 48 hours;
- current hidden-child live rollup parents when the rollup is the only visible
  signal that active work needs attention.

Everything else is excluded at relay acquisition time before expensive
enrichment, turn proof, SQLite projection writes, subscription snapshots, and
detail-route work.

## Done-State Requirements

1. Dock Home and Archive never stream, page, count, or keep visible cards older
   than the retention window unless the card is backed by current live evidence.
2. The relay stops upstream pagination once `thread/list` has crossed the
   retention boundary. Missing live-bypass IDs are handled by direct one-ID
   supplements, not by broad old pagination.
3. Old retained-out rows do not receive `thread/read` enrichment or
   `thread/turns/list` activity proof.
4. Old retained-out rows already present in `.codex-dock/relay-state.sqlite`
   are deleted from the visible scope by the next complete reconciliation.
5. Session-index supplements cannot reintroduce old rows or cause `thread/read`
   for old candidates.
6. Direct downstream routes that can load thread data reject old non-live
   thread IDs before turn pagination or mutation work.
7. Currently loaded live human threads stay visible because live work is the
   one intentional bypass of stored-history age.
8. The behavior is fixed at 48 hours for production. Tests can inject `nowMs`
   or a shorter retention window through config, but production does not gain a
   user-facing toggle.
9. Relay diagnostics log counts and retention decisions without logging prompt
   text, transcript text, raw JSON-RPC payloads, bearer tokens, or thread
   contents.
10. The implementation keeps one source of truth for the policy and does not
    scatter age checks through unrelated relay handlers or Swift stores.
11. The final proof includes focused Node tests, full relay tests, real
    relay-backed simulator proof, real-data relay proof, and post-deploy proof
    on both Mac and `home` relays.

## Requirements

- Retention age is measured from a cheap thread activity timestamp available
  before turn proof:
  `activityAtMs`, `activityAt`, `updatedAtMs`, `updatedAt`, `createdAtMs`,
  `createdAt`, in that order.
- A thread with no parseable cheap activity timestamp is treated as outside the
  retention window unless current live evidence includes it.
- The relay continues to request `thread/list` with:
  `archived`, `limit: THREAD_LIST_MAX_LIMIT`, `sortKey: "updated_at"`,
  `sortDirection: "desc"`, and `modelProviders: []`.
- Early stop is allowed only for newest-first `updated_at` list drains. If a
  future caller uses a different sort, the policy may filter rows but must not
  claim the cursor stream is complete from the retention boundary.
- The 48-hour cutoff is computed once per reconcile or route assertion, then
  passed through the data path so one operation has a stable view of time.
- Live bypass is narrow:
  - live root rows from `thread/loaded/list` may be retained regardless of
    stored age;
  - hidden live rollup target parents may be retained only when the live row
    supplies `dockRelayRollupTargetThreadID`;
  - missing live-bypass parents are resolved by direct `thread/read` by ID,
    not by continuing through old `thread/list` pages;
  - archive view does not get a live bypass because archived threads are
    read-only history.
- Existing card projection contracts remain unchanged. `DockThreadCardDTO` does
  not get a new retention field.
- Existing `dock/*`, `archive/*`, and `thread/detail/*` method names remain
  unchanged.

## Non-Requirements

- Do not delete Codex history files under `$CODEX_HOME`.
- Do not change the upstream Codex app-server API unless current repo evidence
  proves it already supports a lower-cost cutoff parameter. Current evidence
  shows no `updatedAfter` or equivalent `thread/list` parameter.
- Do not add an iOS UI toggle or client-side filter.
- Do not restore the old raw authenticated `ws://127.0.0.1:4500` phone path.
- Do not expose retained-out thread IDs through diagnostics.
- Do not make Realtime transcription behavior depend on the phone.
- Do not run the archive round-trip gate unless explicitly requested with
  `CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP=1`.

## Current Code Truth

Canonical owner path:

- `scripts/dock-relay-state-engine.mjs`
  - `reconcileDock()` drains active history, refreshes live leases, enriches
    human rows, supplements from `session_index.jsonl`, canonicalizes activity,
    writes relay SQLite, and publishes `dock/update`.
  - `reconcileArchive()` does the same for archive rows without live leases.
- `scripts/dock-relay-thread-data.mjs`
  - `drainThreadListRows()` drains paged upstream history `thread/list`.
  - `enrichHumanStartedRows()` does `thread/read includeTurns:false`.
  - `readSessionIndexHumanStartedSupplements()` reads local
    `session_index.jsonl` candidates, then validates each with `thread/read`.
  - `canonicalizeThreadRows()` proves latest card activity through
    `thread/turns/list`.
  - `assertHumanThreadID()`, `aggregateThreadRead()`, `listThreadTurns()`,
    `archiveThread()`, `setThreadName()`, and `unarchiveThread()` are the
    shared route assertion and mutation boundaries.
- `scripts/dock-relay-state-store.mjs`
  - `applyDockReconciliation()` and `applyArchiveReconciliation()` already
    remove previous visible cards missing from a complete reconcile.
  - That existing deletion behavior is the right cleanup path for old visible
    cards.
- `scripts/dock-relay-state-views.mjs`
  - `timestampToMs()` already owns robust timestamp parsing.
  - `normalizeThread()` already maps canonical rows into projection cards.
- `scripts/dock-relay-constants.mjs`
  - production relay timing, size, page, and port constants already live here.
- `scripts/dock-relay.mjs`
  - downstream route handlers call shared helpers; it should not gain scattered
    retention checks.

Upstream app-server truth from repo docs:

- `thread/list` supports `cursor`, `limit`, `sortKey`, `sortDirection`,
  `modelProviders`, `sourceKinds`, `archived`, `cwd`, `useStateDbOnly`, and
  `searchTerm`.
- It does not document `updatedAfter`, `updated_at_after`, `since`, or another
  direct cutoff parameter.

## Target Architecture

### 1. One Policy Module

Add `scripts/dock-relay-thread-retention.mjs`.

It owns:

- `threadRetentionWindowMs(config)`
  - production default from `RELAY_THREAD_RETENTION_WINDOW_MS`;
  - test-only override from `config.threadRetentionWindowMs`.
- `threadRetentionCutoffMs(config, nowMs = Date.now())`
  - returns `nowMs - threadRetentionWindowMs(config)`.
- `cheapThreadActivityMs(thread)`
  - delegates to a newly exported `rowActivityAtMs()` from
    `scripts/dock-relay-state-views.mjs`, or an exported alias with the same
    timestamp order, so retention does not duplicate the existing activity
    parser.
- `isThreadRetainedByAge(thread, cutoffMs)`
  - true when `cheapThreadActivityMs(thread) >= cutoffMs`.
- `retentionBypassThreadIDsFromLive(liveProof)`
  - returns live root IDs plus hidden live rollup target parent IDs.
- `filterThreadsByRetention(rows, { cutoffMs, bypassThreadIDs })`
  - returns retained rows, rejected counts, rejected IDs, and page activity
    facts.
- `threadRetentionRejectedError(threadId, cutoffMs)`
  - reuses client-facing code `-32043` with reason
    `older_than_retention_window`.

The policy module is pure. It does not open sockets, read SQLite, mutate
config, or log by itself.

### 2. Central Constant

Add this to `scripts/dock-relay-constants.mjs`:

```js
const RELAY_THREAD_RETENTION_WINDOW_MS = 48 * 60 * 60 * 1000;
```

Export it beside the other relay state constants. Do not add a production env
var or app setting unless a later explicit rollout decision asks for one.

### 3. History List Drain Gate

Change `drainThreadListRows(config, params, options)` so it accepts:

- `cutoffMs`
- `bypassThreadIDs`
- `retention = true`

Behavior:

1. Build the existing human-only, clamped history params.
2. Request pages exactly as today while `sortKey: "updated_at"` and
   `sortDirection: "desc"` are used.
3. For each page, keep only rows that pass age retention or whose ID is in
   `bypassThreadIDs`.
4. Add only retained rows to `rows`.
5. Track `retentionFilteredRows`, `retentionOldestPageActivityMs`,
   `retentionStoppedAtBoundary`, and rejected IDs.
6. Stop pagination when:
   - the current page is nonempty;
   - every row on the page has cheap activity below cutoff;
   - the caller is using `sortKey: "updated_at"` and
     `sortDirection: "desc"`.
7. Treat retention-boundary stop as complete for the retained scope.
8. Keep repeated-cursor behavior unchanged.

The drain should not call `thread/read` or `thread/turns/list`. It only decides
whether list rows are worth downstream work.

### 4. Dock Reconcile Flow

Change `reconcileDock()` from broad history-first work to retention-aware work:

1. Refresh live leases first.
2. Build `bypassThreadIDs` from live root rows and hidden rollup target parents.
3. Drain active history with a stable `cutoffMs` and `bypassThreadIDs`.
4. Enrich only retained list rows.
5. Add live-bypass direct supplements:
   - if a bypass ID was not present in retained history rows, read
     `thread/read includeTurns:false` for that ID once;
   - classify it with the existing human-started filter;
   - keep it only if it is a live root row or hidden rollup target parent.
6. Read session-index supplements with the same `cutoffMs`; old session-index
   candidates are ignored before `thread/read`.
7. Canonicalize only retained rows and live-bypass rows.
8. Apply reconciliation with `complete: true` when the retained scope is
   complete, so old previously visible cards are removed through the existing
   `projectionIDs` delete path.
9. Log counts only:
   - `retentionCutoffMs`
   - `retentionFilteredRows`
   - `retentionStoppedAtBoundary`
   - `retentionBypassRows`
   - `threadReadCandidates`
   - `turnProofCandidates`

No card fields or Swift contracts change.

### 5. Archive Reconcile Flow

Change `reconcileArchive()` to use the same cutoff but no live bypass:

1. Drain archived history with `cutoffMs`.
2. Enrich only retained archived rows.
3. Read session-index supplements with `cutoffMs`.
4. Canonicalize only retained rows.
5. Apply archive reconciliation with `complete: true` when retained archive
   scope is complete, removing old archive cards from visibility.

### 6. Session-Index Supplement Gate

Change `readSessionIndexCandidates(config, options)` and
`readSessionIndexHumanStartedSupplements(config, existingRows, options)`:

- accept `cutoffMs`;
- discard candidates with `updatedAtMs < cutoffMs`;
- discard candidates with missing or invalid `updatedAtMs`;
- keep the existing per-ID latest-row collapse;
- preserve `HUMAN_THREAD_INDEX_SUPPLEMENT_LIMIT` after filtering;
- log counts only.

This prevents local supplement logic from undoing the cheaper history drain.

### 7. Route Assertion Gate

Add retention checking in the shared route helpers, not in each downstream case:

- `readHumanThreadForRoute()`
- `assertHumanThreadID()`
- `aggregateThreadList()`
- `aggregateThreadRead()`
- `listThreadTurns()`
- `archiveThread()`
- `setThreadName()`
- `unarchiveThread()`

Rules:

- Live owner row first: if the thread is currently live and passes the human
  filter, allow it even when stored timestamps are older than cutoff.
- App-facing card fallback: if a visible Dock or Archive card already exists,
  allow detail, turns, and mutation routes only when that card itself passes
  retention or current live evidence backs it.
- History fallback: after `thread/read includeTurns:false`, reject the thread
  with `older_than_retention_window` if it does not pass the cutoff.
- Rejection must happen before `thread/turns/list` pagination and before
  mutation requests.

This closes the old-ID side door without spreading checks into `dock-relay.mjs`.
It also covers `thread/message/send`, `turn/start`, and `turn/steer`, because
`scripts/dock-relay-user-message-command.mjs` already calls
`assertHumanThreadID()` before upstream delivery.

`aggregateThreadList()` is not a current phone-facing route, but it is exported
and already implements a human-only aggregate list. Apply the same retention
filter there as defense in depth so future callers cannot accidentally restore
a raw old list path.

### 8. Targeted Notification Gate

Keep patching an existing visible retained card as today. For missing cards:

- if the notification carries a full thread row, apply the same retention
  policy before targeted projection;
- if the notification only carries an ID, `readCanonicalThreadForProjection()`
  applies the route assertion gate before it can canonicalize or upsert;
- if the old thread is rejected, return an ignored/hidden result and do not
  publish a card upsert.

This prevents name/status/start notifications for old hidden rows from
reintroducing cards.

### 9. Store Cleanup

Do not add a second cleanup job. Use the existing reconciliation behavior:

- old Dock cards vanish because retained reconcile omits them and
  `applyDockReconciliation()` marks previous missing rows inactive;
- old Archive cards vanish because retained reconcile omits them and
  `applyArchiveReconciliation()` marks previous missing archive rows not
  archived for the archive view;
- rejected or non-human cards still use existing
  `deleteRejectedThreadCards()` and `deleteRejectedLiveLeases()`.

If implementation proves a store helper is needed, it must be a single helper
called only by reconciliation, not a background sweeper.

## Invariants

- The retention cutoff is operation-stable: one reconcile uses one cutoff.
- Retention filtering happens before `thread/read`.
- Turn proof never runs for retained-out rows.
- A live row can bypass age; a plain old stored row cannot.
- Swift cards are a projection of retained relay state, not a second source of
  filtering truth.
- Retained scope completeness is honest: early cutoff means "complete for the
  retained window", not "all historical Codex rows were enumerated".
- Missing timestamps are not silently treated as recent.
- Logs contain counts and route names, not prompts, transcripts, audio, raw
  payloads, or tokens.

## Edge Cases

| Case | Expected behavior |
| --- | --- |
| Thread updated exactly at cutoff | Retained. Use `>= cutoffMs`. |
| Thread with invalid timestamps | Dropped unless live evidence includes it. |
| Old thread currently loaded live | Retained in Dock. |
| Old archived thread | Hidden from Archive and rejected by direct detail route unless a visible retained card exists. |
| Old hidden child has active live status | Parent may be retained only through the live-bypass rollup path. |
| App-server returns a newer row after an old page | Only impossible under the documented `updated_at desc` contract. Tests cover early stop for that contract; non-desc callers must not early-stop. |
| Turn activity is newer than stale thread `updatedAt` | Not discovered unless the thread is live. This is the intentional cost-saving tradeoff because proving turns is the work we are avoiding. |
| Existing SQLite card is old | Removed on the next complete retained reconcile. |
| Direct old thread ID in `thread/detail/subscribe` | Rejected before turn pagination. |
| Old card is visible between startup and next reconcile | Taps may reject before the deletion delta arrives; next complete reconcile removes the card. |
| Old visible card becomes live again | Live lease or notification can reintroduce it through live-bypass proof. |

## Implementation Phases

### Phase 1: Policy And Unit Boundaries

- Add `RELAY_THREAD_RETENTION_WINDOW_MS`.
- Add `scripts/dock-relay-thread-retention.mjs`.
- Add focused tests for timestamp parsing, age checks, missing timestamps,
  cutoff equality, and live bypass IDs.

Exit proof:

```bash
rtk npm run test:relay
```

### Phase 2: Relay Acquisition Cutoff

- Apply retention to `drainThreadListRows()`.
- Apply retention to session-index supplements.
- Add request-log tests proving old rows do not get `thread/read` or
  `thread/turns/list`.
- Add a paged fixture proving `thread/list` stops after the first old page.

Exit proof:

```bash
rtk npm run test:relay
```

### Phase 3: Reconcile, Store Cleanup, And Live Bypass

- Wire retained drains into `reconcileDock()` and `reconcileArchive()`.
- Preserve live-loaded old human rows.
- Preserve current hidden-child rollup parent behavior with a narrow direct
  live-bypass supplement.
- Prove old existing cards emit deletion projection IDs on complete reconcile.

Exit proof:

```bash
rtk npm run test:relay
rtk npm test
```

### Phase 4: Route Side-Door Closure

- Add the shared route assertion gate.
- Prove old direct IDs fail before turn pagination and before mutations.
- Prove visible retained cards and current live rows still allow detail.

Exit proof:

```bash
rtk npm run test:relay
rtk npm test
```

### Phase 5: Real Relay Proof And Deployment

- Run Mac real relay proof.
- Run simulator real-data proof.
- Deploy to `home` only after commit and push.
- Run `home` relay status and host compare.
- Install/configure both physical phones if the deploy changes app behavior or
  saved host config. For this relay-only change, physical install is not
  required unless the simulator or relay proof exposes an iOS contract change.

Exit proof is listed below.

## Test Plan

### Focused Node Tests

Add or extend relay tests to prove:

- policy helper retains exactly cutoff-equal rows and rejects older rows;
- `drainThreadListRows()` filters old rows before enrichment;
- `drainThreadListRows()` stops pagination at the retention boundary for
  `updated_at desc`;
- retained-out active rows do not call `thread/read`;
- retained-out rows do not call `thread/turns/list`;
- session-index supplements reject old candidates before `thread/read`;
- old existing Dock cards are deleted from visible scope on complete reconcile;
- old existing Archive cards are deleted from visible scope on complete
  reconcile;
- current live old root rows remain visible;
- current hidden-child rollup parent rows remain visible through the narrow
  live-bypass supplement;
- direct old `thread/detail/subscribe` rejects before turn pagination;
- direct old `thread/turns/list` rejects before upstream turns call;
- old `thread/name/set`, `thread/archive`, and `thread/unarchive` reject before
  upstream mutation;
- old `thread/message/send`, `turn/start`, and `turn/steer` reject before
  upstream delivery or outbound command persistence;
- visible retained cards still open detail and can be renamed;
- missing timestamps are retained out unless live.

Primary command:

```bash
rtk npm run test:relay
```

Full Node command:

```bash
rtk npm test
```

### Contract And Docs Tests

Run:

```bash
rtk npm run contract:check
rtk npm run test:docs
```

Update `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` only if implementation adds
a new controlled simulator scenario, root bug doc, or newly named failure class.

### Swift Tests

No Swift production code should change. If Swift remains untouched, Swift tests
are not the first proof. If a DTO, app-server client, Dock store, or Archive
store changes anyway, run the smallest matching Swift suite from
`docs/TESTING.md`.

Likely not needed unless Swift changes:

```bash
rtk swift test --filter DockStoreTests
```

### Real Relay Simulator Proof

Run after Node proof passes:

```bash
rtk make services
rtk make dock-relay-status
rtk make sim-ui-sync-proof SIM='iPhone 17'
rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'
```

`sim-ui-sync-proof` proves the installed simulator app reads real relay-backed
Dock rows through `dock/*`. `sim-ui-realdata-realtime-proof` proves rename and
archive behavior still works on real data after the retention cut.

### Real Data Retention Proof

On the Mac relay after `rtk make services`, inspect the relay SQLite state and
relay logs:

```bash
rtk node -e 'const { DatabaseSync } = require("node:sqlite"); const db = new DatabaseSync(".codex-dock/relay-state.sqlite"); const now = Date.now(); const cutoff = now - 48 * 60 * 60 * 1000; const rows = db.prepare("SELECT thread_id, activity_at_ms, status, archive_state, active_scope_present, archived_scope_present FROM threads WHERE source_kind = '\''human'\'' AND lane = '\''human'\'' AND ((active_scope_present = 1 AND archive_state != '\''archived'\'') OR (archived_scope_present = 1 AND archive_state = '\''archived'\'')) AND COALESCE(activity_at_ms, 0) < ? AND status NOT IN ('\''running'\'','\''needsApproval'\'','\''needsInput'\'') AND NOT EXISTS (SELECT 1 FROM live_leases l WHERE l.host_id = threads.host_id AND l.thread_id = threads.thread_id AND l.expires_at_ms >= ?)").all(cutoff, now); console.log(JSON.stringify({ cutoff, oldVisibleNonLiveRows: rows.length, rows }, null, 2)); process.exit(rows.length === 0 ? 0 : 1);'
```

Then confirm relay host health:

```bash
rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
```

### Full Controlled Matrix

Run before final completion if the change touches controlled scenarios or if
real-data proof exposes a live-update regression:

```bash
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
```

This is completion-grade live-update proof for fixture scenarios. It is not a
substitute for real-data proof.

## Plan Audit And Fresh Consult Gates

Before implementation:

1. Run `$plan-audit` in plan-readiness mode on this file.
2. Repair every blocking `PLA-*` finding in this plan.
3. Run `$fresh-consult` with Cursor Agent Composer 2.5 Fast against this plan.
4. Treat the plan as implementation-ready only when:
   - plan-audit verdict is `ready`;
   - Cursor verdict is `pass` or `pass-with-notes`;
   - any Cursor blocking issue is either repaired or spot-checked as wrong.

Fresh consult target:

- runtime: `agent`
- model: `composer-2.5-fast`
- effort: `encoded-in-model`
- mode: `fresh-resumable`
- question: whether the plan is elegant, simple, exhaustively specified, and
  has a clear real-relay test plan.

## Implementation Gate

Use `$plan-implement` after the plan gates pass.

Create:

```text
docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06_IMPLEMENTATION_LOG.md
```

The implementation log should stay short and record:

- active phase;
- files changed;
- proof run;
- stale proof;
- plan-audit or implementation-audit findings opened/resolved;
- remaining deploy blockers.

## Thermo-Nuclear Code Quality Review Gate

Before commit:

1. Run `$plan-audit` in implementation-audit mode against this plan and the
   current diff.
2. Run `$thermo-nuclear-code-quality-review` on the current branch diff.
3. Repair all blocking maintainability findings.
4. Re-run focused tests invalidated by repairs.
5. Only then commit.

The review bar is:

- no scattered age checks;
- no unnecessary new mode flags;
- no file crossing 1000 lines because of this change;
- no duplicate retention truth;
- no new Swift filter path;
- no route side doors for old data;
- no retained-out rows receiving turn proof.

## Commit, Push, And Deploy Plan

Only after all gates pass:

```bash
rtk git status --short
rtk git diff --check
rtk git add docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06.md <explicit changed paths>
rtk git commit -m "Filter Dock threads older than 48h in relay"
rtk git push
```

Do not use `git add .` or `git add -A`.

Deploy Mac relay:

```bash
rtk make services
rtk make dock-relay-status
```

Refresh and deploy `home` from the pushed branch:

```bash
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk git fetch && rtk git pull --ff-only'
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make services HOST_SERVICE_PLATFORM=linux NODE_BIN=/home/aelaguiz/.local/node-v24.16.0-linux-x64/bin/node CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home APP_SERVER_HOST=100.66.11.7 DOCK_RELAY_WS=ws://100.66.11.7:4510'
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-status HOST_SERVICE_PLATFORM=linux NODE_BIN=/home/aelaguiz/.local/node-v24.16.0-linux-x64/bin/node CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home APP_SERVER_HOST=100.66.11.7 DOCK_RELAY_WS=ws://100.66.11.7:4510'
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-doctor HOST_SERVICE_PLATFORM=linux NODE_BIN=/home/aelaguiz/.local/node-v24.16.0-linux-x64/bin/node CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home APP_SERVER_HOST=100.66.11.7 DOCK_RELAY_WS=ws://100.66.11.7:4510'
```

Post-deploy compare:

```bash
rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
```

Run the real-data retention SQLite check on both relays. For `home`, use the
same SQLite query through `rtk ssh home` from
`/home/aelaguiz/workspace/codex-client`.

## Rollback Plan

If deploy breaks relay state or hides current work:

1. Revert the commit on Mac using an explicit revert commit.
2. Push the revert.
3. Redeploy Mac with `rtk make services`.
4. Pull the reverted branch on `home` with `git pull --ff-only`.
5. Redeploy `home` with the documented Linux service command.
6. Run `rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.

Do not reset or clean either checkout unless explicitly asked.

## Open Risks

- App-server `updatedAt` can be stale relative to newer turns. The plan
  intentionally does not pay `thread/turns/list` for rows whose cheap activity
  is already older than cutoff. Live-loaded rows are the safety exception for
  active work.
- If the upstream app-server later adds a true server-side cutoff parameter,
  the relay should move the retention boundary into that request and keep the
  same policy module as the single source of truth.
- If physical Mobile MCP reports `WebDriverAgent is not running on device`,
  physical UI readback is blocked. The deploy can still proceed on Node,
  simulator, relay status, and real-relay proof, with that exact blocker
  recorded.
