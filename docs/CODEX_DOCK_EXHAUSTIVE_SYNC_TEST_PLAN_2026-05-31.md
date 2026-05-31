# Codex Dock Exhaustive Sync Test Plan

> 2026-05-31 implementation note: this draft references older parity/oracle
> routes as historical context. Current card proof must observe `dock/subscribe`,
> `dock/update`, `dock/resync`, `archive/subscribe`, `archive/update`, and
> `archive/resync`. Deleted routes such as `relay/state/snapshot`, `state/query`,
> `thread/search`, `thread/goal/get`, app-facing `thread/loaded/list`, `/statez`,
> `/dbz`, and `/explainz` must not be reintroduced as test-only or diagnostic
> card proof paths.

Date: 2026-05-31
Status: Draft for audit
Doc type: Implementation plan
Owners: Amir, Codex

Related docs:

- `README.md`
- `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md`
- `docs/CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md`
- `docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md`
- `docs/CODEX_DOCK_CODEX_APP_SERVER_END_TO_END_AUDIT.md`
- `docs/CODEX_DOCK_RELAY_STATE_PARITY_WORKLOG_2026-05-30.md`

## Direct Answer

The repo already has a strong one-shot parity foundation in
`scripts/dock-relay-state-parity.mjs`, but it does not yet prove that the Dock
client stays in sync with the actual local Codex state over time.

The missing piece is a long-running sync harness that keeps the Dock stream open,
clicks through or protocol-loads thread detail, watches real changes happen, and
compares all client-visible state back to local Codex storage and app-server
state on every pass.

Eventual sync is not enough. If client-visible state catches up only after a
noticeable delay, the exhaustive plan must treat that as a failure because the
installed client feels stale while the lag is happening.

This document specifies that harness and the ongoing loop. It is a plan only.
No implementation is included in this document.

## Goal

Build a repeatable sync-test mechanism that proves Codex Dock stays aligned with
the actual local Codex instance over time and stays close enough to real time
that user-visible lag is not hidden as a passing result.

The mechanism must cover both client surfaces:

1. The Dock/Home list: the cards, ordering, archive membership, source grouping,
   live status, goals, and host identity shown before opening a thread.
2. The click-through thread detail: the exact thread opened from a Dock row, its
   metadata, all historical turns, live events, server request cards, reconnect
   behavior, and stale/error states.

The final proof has three legs:

1. Codex storage and app-server truth to relay projection.
2. Relay projection to actual client-exercised protocol routes.
3. Actual simulator client display, using the `iPhone 17` simulator, so the
   test proves what is literally visible in the app stays complete, correct, and
   close to real time over time.

The third leg is mandatory, not optional follow-up work. After the
Codex-to-relay path and relay-to-client-route path are green, the work must
continue through the real simulator client display before this goal is called
done. A result is not complete if the app screen is missing data, showing stale
data, showing the wrong row/detail state, or showing the right data only after a
lag the user can feel.

Before the goal can be called complete, a passing first and second leg must
roll directly into the third simulator-display leg. A relay/client-route pass is
not enough if the actual app screen can still miss data, show stale data, or
lag beyond the client-visible budget.

The mechanism must compare four planes of truth:

1. Local Codex durable storage under `CODEX_HOME`, including SQLite metadata,
   rollout JSONL session files, archived session files, goals, and spawn edges.
2. Raw Codex app-server behavior exposed through relay-side app-server calls,
   including `thread/list`, `thread/read`, `thread/turns/list`,
   `thread/goal/get`, `thread/loaded/list`, notifications, and server requests.
3. Dock relay projection behavior, including the relay SQLite projection,
   `dock/subscribe`, `dock/update`, `dock/resync`, reconciliation freshness,
   windowing, and stale-scope handling.
4. Swift client state and rendered simulator UI, including `DockStore`,
   `AppServerThreadCardStreamClient`, `ThreadDetailStore`,
   `ThreadDetailDataEngine`, visible `DockThreadCard` rows, detail content,
   stale/error states, and literal screen proof when required.

## Non-Goals

- Do not implement the harness in this plan.
- Do not make the iPhone connect directly to the raw authenticated
  `ws://127.0.0.1:4500` app-server for normal proof.
- Do not add relay runtime reads from Codex disk as a production shortcut.
  Disk reads are allowed for the verifier oracle only.
- Do not use preview rows, mocks, or scripted transports as completion evidence
  for physical or installed-client behavior.
- Do not log `OPENAI_API_KEY`, bearer tokens, base64 audio, raw audio bytes,
  prompt text, transcript text, or full JSON-RPC payloads.
- Do not claim unsupported Codex facts are verified. Unsupported facts must be
  named as product-contract gaps or app-server gaps.

## Current State

As of the 2026-05-31 single-source contract cleanup, card proof must run through
the same client path the app renders: `dock/subscribe`, `dock/update`, and
`dock/resync`. The deleted oracle routes `relay/state/snapshot`, `state/query`,
`thread/search`, `thread/goal/get`, and `thread/loaded/list` must not return as
app-facing or test-only card proof paths.

The remaining relay sync audit is client-path-only. It may use raw Codex facts
as upstream fixture/verifier inputs, but the observed relay output for Dock
cards is the Dock stream contract.
That foundation still needs over-time proof for these behaviors:

- A long-lived `dock/subscribe` stream stays correct across many
  reconciliations.
- `dock/update` deltas stay gap-free and are correctly resynced after sequence
  breaks.
- Relay stale rows are retained only while a source refresh is incomplete and
  removed after a complete refresh proves they are gone.
- Swift `DockStore` state keeps matching the relay projection across many
  updates.
- A real Dock row click opens the exact matching thread detail.
- The detail store cannot drop live events between historical read, turn
  pagination, and `thread/resume`.
- Server requests that matter to the user are visible as both timeline events
  and request cards.
- Reconnect and foreground rehydrate restore truth before declaring `.live`.

## Existing Architecture Evidence

### Storage Truth

Durable local Codex state exists in `CODEX_HOME`.

The verifier must use these storage sources:

- `state_5.sqlite.threads`: indexed thread metadata mirror.
- `state_5.sqlite.thread_spawn_edges`: normalized parent-child spawn tree.
- `goals_1.sqlite.thread_goals`: current persisted goal state.
- `$CODEX_HOME/sessions/**/*.jsonl`: rollout session history.
- `$CODEX_HOME/archived_sessions/**/*.jsonl`: archived rollout session history.
- `session_index.jsonl`: append-only name sidecar.

Known storage limits:

- `state_5.sqlite.threads` does not expose every live app-server fact.
- It does not contain an ordinary normalized turn table.
- It does not expose `forked_from_id` or a live app-server `session_id`.
- Goal storage exposes goal rows, but app-server `thread/goal/get` does not
  expose `goal_id`.

### App-Server Truth

The app-server is the bridge between local Codex storage and live process state.

The verifier must use these app-server surfaces through the Dock relay:

- `thread/list`
- `thread/read`
- `thread/turns/list`
- `thread/goal/get`
- `thread/loaded/list`
- `thread/resume`
- app-server notifications
- server requests

Known app-server limits:

- There is no single authoritative thread-type field. The verifier must combine
  `Thread.source`, `Thread.threadSource`, `Thread.status`,
  `thread/loaded/list`, `thread/goal/get`, and notification data.
- `thread/list` is persisted history plus process-local status overlay, not a
  global live index.
- `thread/search` is term-bound and cannot be used as exhaustive enumeration.
- No current API gives a single atomic snapshot ID across `thread/list`,
  `thread/read`, `thread/turns/list`, `thread/goal/get`, SQLite, and
  `dock/subscribe`.

### Relay Truth

The relay serves the client-facing stream.

Important relay evidence:

- `scripts/dock-relay-state-store.mjs:69` identifies the relay-owned projection
  while Codex durable state remains the source of truth.
- `scripts/dock-relay-state-engine.mjs:79` starts the periodic reconciler.
- `scripts/dock-relay-constants.mjs:35` sets
  `RELAY_STATE_RECONCILE_INTERVAL_MS = 30_000`.
- `scripts/dock-relay-state-engine.mjs:219` drains live leases, active
  all-source rows, and default interactive rows.
- `scripts/dock-relay-state-snapshot.mjs:145` drains paged `thread/list`.
- `scripts/dock-relay-state-store.mjs:508` deletes missing rows only after a
  complete refresh.
- `scripts/dock-relay-state-engine.mjs:284` keeps last good rows when refresh
  fails and marks scopes stale.
- `scripts/dock-relay-state-views.mjs:273` overlays live status without changing
  stored Codex order.
- `scripts/dock-relay-state-engine.mjs:609` abandons partial catch-up if store
  sequence changes mid-catchup.

### Swift Client Truth

The Swift app consumes relay state.

Important Dock list evidence:

- `CodexDock/State/AppServerThreadCardStreamClient.swift:19` connects to the
  Dock relay without a raw bearer token.
- `CodexDock/State/AppServerThreadCardStreamClient.swift:65` subscribes with
  `dock/subscribe`.
- `CodexDock/State/AppServerThreadCardStreamClient.swift:95` handles
  `dock/update` and `dock/resync`.
- `CodexDock/State/DockStore.swift:295` opens a stream per host.
- `CodexDock/State/DockStore.swift:364` handles incompatible updates by
  resyncing.
- `CodexDock/State/DockStore.swift:467` publishes host snapshots to the UI.

Important thread detail evidence:

- `CodexDock/State/ThreadDetailStore.swift:245` creates a detail session.
- `CodexDock/State/ThreadDetailStore.swift:249` connects and starts
  observation.
- `CodexDock/State/ThreadDetailStore.swift:556` calls
  `thread/read(includeTurns: false)`.
- `CodexDock/State/ThreadDetailStore.swift:568` drains `thread/turns/list`
  pages.
- `CodexDock/State/ThreadDetailStore.swift:606` calls
  `thread/resume(excludeTurns: true)`.
- `CodexDock/State/ThreadDetailStore.swift:611` publishes `.live` after resume.
- `CodexDock/State/ThreadDetailStore.swift:628` rehydrates after reconnect.
- `CodexDock/State/ThreadDetailStore.swift:689` applies thread notifications.
- `CodexDock/State/ThreadDetailStore.swift:711` applies server requests.
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:47` merges thread
  notifications.
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:62` merges server
  requests.
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:138` normalizes client
  presentation with `ThreadEventDisplayOrder.newestFirst`.

## Definition Of Fully In Sync

The harness must define sync in user-visible terms.

### Dock/Home Sync

For every app-server-listable, stable Codex thread, the Dock client must show
exactly one matching card in the expected host and source scope.

A card is matching only when these fields agree with the selected oracle:

- thread id
- source and thread source
- archive membership
- title
- preview, when Codex exposes preview data
- model provider and model, when exposed
- current working directory
- CLI version, when exposed
- timestamps used for ordering
- parent or spawn relationship, when exposed
- goal status, when exposed
- live status
- error or offline state
- host identity

Ordering is matching only when:

- the Dock order equals the app-server active all-source order for stable rows,
  or
- the report classifies a timestamp movement between before/after snapshots and
  proves the movement explains the ordering difference.

The Dock list is not in sync when:

- a stable expected card is missing;
- a card is duplicated;
- a non-archived row appears in the archived view or an archived row appears in
  the active view;
- a card belongs to a different host;
- a stale relay row is shown as fresh after a complete source refresh omitted it;
- live status stays present after the live lease expires;
- `DockStore` believes a stream is fresh while the relay reports a stale or
  incomplete source scope.

### Thread Detail Sync

Clicking a Dock row must open the exact same thread id from the same host.

The detail view is matching only when:

- `thread/read(includeTurns: false)` returns metadata for that thread id;
- all `thread/turns/list` pages are drained without duplicate turn ids or
  repeated cursors;
- client presentation is newest-first, matching
  `ThreadEventDisplayOrder.newestFirst`; the verifier may request app-server
  turns with `--turn-sort-direction desc`, but the final client order must be
  compared against the client presentation order;
- all turns exposed by app-server appear in client state;
- live notifications after the chosen boundary are applied exactly once;
- complete live snapshots replace partial events correctly;
- server requests after the chosen boundary appear as timeline events and
  request cards;
- resolved server request notifications update the matching request card;
- reconnect and foreground rehydrate reload history before declaring `.live`;
- `.live` is published only after read, turn drain, and
  `thread/resume(excludeTurns: true)` succeed.

The detail view is not in sync when:

- the opened detail thread id differs from the Dock row thread id;
- a historical turn page is skipped;
- a repeated cursor is accepted;
- a live event is dropped during initial load;
- a live event is applied twice;
- a notification for another thread mutates the detail view;
- a server request is visible in app-server but absent from the UI state;
- reconnect publishes `.live` using old state without a fresh compact read;
- resume fails but the UI reports the thread as live.

### Time-Based Sync

One snapshot is not enough. The harness must prove convergence over time, and it
must prove that convergence happens within an explicit near-real-time budget.
The test cannot pass merely because the client eventually reaches the right
state.

For each scenario, the harness must record:

- `t0`: before the local Codex or app-server change.
- `t_change`: when the change is made or observed by app-server.
- `t_relay_seen`: when the relay projection first includes the change.
- `t_dock_seen`: when the long-lived `dock/subscribe` stream or Swift
  `DockStore` first includes the change.
- `t_detail_seen`: when the detail probe or Swift `ThreadDetailStore` first
  includes the change.
- `t_display_seen`: when the actual rendered simulator client first displays
  the required Dock row, detail item, stale/error state, request state, or
  ordered transition. This timestamp is mandatory for Phase 6 and must come
  from the `iPhone 17` simulator app path, not from relay-only or protocol-only
  evidence.
- `t_stable`: when at least two consecutive checks agree across all required
  planes.

For each scenario, the harness must also compute and report:

- `lag_change_to_relay_ms`: `t_relay_seen - t_change`.
- `lag_relay_to_dock_ms`: `t_dock_seen - t_relay_seen`.
- `lag_dock_to_detail_ms`: `t_detail_seen - t_dock_seen`, when detail is in
  scope.
- `lag_relay_to_display_ms`: `t_display_seen - t_relay_seen`, when rendered UI
  proof is in scope.
- `lag_change_to_display_ms`: `t_display_seen - t_change`, when rendered UI
  proof is in scope.
- `lag_change_to_stable_ms`: `t_stable - t_change`.

The default convergence budget is:

- one successful relay reconciliation interval for relay projection changes;
- `dock/update` delivery within the configured client-visible lag budget after
  relay projection changes;
- one explicit resync cycle after a detected sequence gap or schema mismatch;
- one complete detail rehydrate after reconnect or foreground.

The default client-visible lag budget for the Dock stream is 2,000 ms, exposed
by the audit tool as `--max-stream-lag-ms`. A stricter run may lower this
budget. Any run that exceeds the configured lag budget must fail even if a later
sample eventually matches.

For Phase 6, the same rule applies all the way through the rendered simulator
client. A relay or protocol client-route pass does not pass Phase 6 unless the
literal app screen displays the same required state within the configured
client-visible lag budget.

If a source scope is stale or incomplete, the client may show stale data only
when the stale or partial state is explicit in the report and client state. It
must not be counted as a fresh pass.

### Unsupported Facts

Unsupported facts cannot be silently ignored.

The report must classify each unsupported fact as one of:

- `outside_app_server_contract`: local storage has the fact but no app-server API
  exposes it.
- `outside_client_contract`: app-server exposes the fact but the Dock client is
  not intended to show it.
- `product_gap`: the user-visible contract needs the fact, but the app-server or
  client cannot currently prove it.

The harness must fail final completion if a `product_gap` exists for any
client-required field.

## Initial Tool Build

The first implementation phase should build a canonical audit tool, not a
parallel copy of the existing parity logic.

### Planned Tool

Add a new planned script:

```text
scripts/dock-relay-sync-audit.mjs
```

This script should orchestrate the complete sync audit. It should reuse or
factor logic from:

- `scripts/dock-relay-state-parity.mjs`
- `scripts/dock-relay-state-snapshot.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-store.mjs`
- `scripts/dock-relay-state-views.mjs`
- `scripts/dock-relay-thread-fidelity.mjs`

The existing `scripts/dock-relay-state-parity.mjs` should become either:

- a wrapper around shared collector and comparator modules, or
- the source module that exports collectors and comparators for the new audit
  script.

Do not create a second definition of storage truth, relay truth, source-scope
truth, or diff classification.

### Planned CLI Shape

One-shot exhaustive audit:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --mode one-shot \
  --exhaustive \
  --detail all \
  --json-out /tmp/codex-client/sync-audit/one-shot.json \
  --summary-out /tmp/codex-client/sync-audit/one-shot.md \
  --fail-on-diff
```

Long-running soak audit:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --mode soak \
  --duration-ms 900000 \
  --sample-interval-ms 30000 \
  --max-stream-lag-ms 2000 \
  --exhaustive \
  --detail sampled \
  --json-out /tmp/codex-client/sync-audit/soak.json \
  --summary-out /tmp/codex-client/sync-audit/soak.md \
  --fail-on-diff
```

Controlled scenario audit with isolated Codex home:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --mode scenario \
  --scenario all \
  --codex-home /tmp/codex-client/sync-audit/codex-home \
  --relay-url ws://127.0.0.1:4510 \
  --exhaustive \
  --detail all \
  --json-out /tmp/codex-client/sync-audit/scenario.json \
  --summary-out /tmp/codex-client/sync-audit/scenario.md \
  --fail-on-diff
```

Read-only personal Codex home audit:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --mode read-only-real-home \
  --relay-url ws://127.0.0.1:4510 \
  --exhaustive \
  --detail sampled \
  --json-out /tmp/codex-client/sync-audit/real-home.json \
  --summary-out /tmp/codex-client/sync-audit/real-home.md \
  --fail-on-diff
```

The exact flags can change during implementation, but the tool must support
these four capabilities.

### Tool Components

#### 1. Storage Oracle

The storage oracle reads local Codex durable state before and after each audit
sample.

Inputs:

- `CODEX_HOME`
- `state_5.sqlite`
- `goals_1.sqlite`
- rollout session files
- archived rollout session files
- `session_index.jsonl`

Outputs:

- stable thread rows
- archived thread rows
- previewless rows
- thread metadata
- goal rows
- spawn edges
- rollout `session_meta`
- storage movement between before and after samples
- unsupported fields

Rules:

- Treat storage as durable truth, not live truth.
- Treat movement between before/after snapshots as a classification input, not a
  pass by default.
- Do not fail on previewless rows being absent from `thread/list` unless the
  product contract requires them in the Dock.
- Do fail if an app-server-listable stable row is absent from Dock after the
  convergence budget.
- Never log prompt text or full JSONL payloads.

#### 2. App-Server Oracle

The app-server oracle collects raw Codex facts only as verifier inputs. It must
not expose those facts as app-facing card routes or compare an app-facing card
against a relay state snapshot side door.

Inputs:

- direct routed `thread/read`
- direct history `thread/read`
- `thread/turns/list`

Outputs:

- app-server-listable thread set
- source-scope membership
- archive membership
- read metadata
- turns
- routed-vs-history conflicts
- incomplete scopes
- repeated cursor failures

Rules:

- `--exhaustive` must imply thread reads, turns, Dock subscribe, and full enough
  turn evidence for the selected detail mode.
- A repeated cursor in `thread/turns/list` is a hard detail-read failure.
- A missing routed read can be acceptable only when a history read succeeds and
  the report classifies why routed live state is unavailable.
- `thread/search` cannot be used as exhaustive enumeration.

#### 3. Relay Projection Probe

The relay projection probe observes the relay state store and stream contract.

Inputs:

- `relay/state/snapshot`
- `dock/subscribe`
- `dock/update`
- `dock/resync`
- relay status metadata
- relay state freshness metadata

Outputs:

- projected card rows
- window slices
- update sequences
- stale scopes
- incomplete scopes
- live status overlay
- catch-up results
- resync requests

Rules:

- Open at least one long-lived `dock/subscribe` stream for the duration of soak
  mode.
- Record every sequence number received.
- Force a resync when the stream contract says to resync.
- Fail if a gap is not detected.
- Fail if a detected gap does not converge after resync.
- Fail if the long-lived stream takes longer than `--max-stream-lag-ms` to
  match a fresh client-path `dock/subscribe` view after divergence is detected.
- Gap injection should reuse the Swift patterns in
  `CodexDockTests/DockStoreStreamTests.swift` for client behavior and add a
  test-only Node relay stream harness if protocol-level gap injection is needed.
  Do not add a production-only debug endpoint for this.
- Fail if stale rows survive after a complete refresh that omits them.
- Fail if live leases do not expire from client-visible state.

#### 4. Dock Client Probe

The Dock client probe validates Swift-visible state.

First implementation can start with protocol-level Dock stream proof. Final
completion must include Swift store proof for the same contract.

Inputs:

- `DockStore`
- `AppServerThreadCardStreamClient`
- simulator app state or a test harness using real relay protocol

Outputs:

- host snapshot rows
- stream health
- last sequence
- stale/offline state
- visible ordering
- selected row identity for click-through

Rules:

- A protocol-level pass proves relay behavior, not full Swift UI behavior.
- A Swift store pass is required before claiming the Dock client itself stays in
  sync.
- A simulator screenshot can support UI proof, but it cannot replace state
  comparison.
- Physical phone proof must use relay-backed host paths, not raw app-server
  loopback.

#### 5. Thread Detail Probe

The detail probe validates click-through state for selected threads.

Inputs:

- selected Dock row thread id and host id
- `thread/read(includeTurns: false)`
- all `thread/turns/list` pages
- `thread/resume(excludeTurns: true)`
- `session.notifications`
- `session.serverRequests`
- reconnect and foreground triggers

Outputs:

- opened thread id
- detail metadata
- historical turn list
- live event list
- active turn id
- request cards
- resume state
- reconnect state

Rules:

- Select detail targets from actual Dock rows, not from arbitrary ids only.
- Verify row thread id equals detail thread id.
- Verify host identity is unchanged.
- Verify `thread/read`, all turn pages, and `thread/resume` complete before
  `.live`.
- Record a live boundary before applying live deltas.
- Either prove app-server gives an atomic boundary or buffer live events until
  historical load completes and replay them.
- Follow the `ThreadDetailStore.startObservation` pattern: collect
  `session.notifications` and `session.serverRequests` as async streams, not as
  one-time polls.
- Fail on live event loss between observation start, history replace, turn
  pagination, and resume.
- Fail if a server request visible after the boundary is missing from the
  timeline or request-card state.
- Fail if reconnect publishes `.live` before a fresh compact read succeeds.

#### 6. Scenario Driver

The scenario driver creates controlled changes in an isolated Codex home.

Modes:

- read-only real-home audit: observes the user's current Codex home without
  creating or mutating threads.
- isolated scenario audit: creates a temporary `CODEX_HOME` under
  `/tmp/codex-client/...` and drives known state transitions.

Required scenarios:

1. Existing idle active thread appears in Dock.
2. Existing archived thread appears only in archived views.
3. New thread is created and appears within the convergence budget.
4. Existing thread receives a new turn and moves order correctly.
5. Active live thread appears as live and later expires when no longer live.
6. Thread is archived and disappears from active Dock after complete refresh.
7. Thread is unarchived and reappears in active Dock after complete refresh.
8. Goal state changes and matches app-server-visible goal state.
9. Subagent spawn edge appears where app-server and client contracts expose it.
10. Server request appears in detail as both event and request card.
11. Server request resolution updates the card.
12. Relay source refresh fails and stale state is explicit.
13. Relay source refresh recovers and stale rows are reconciled.
14. Stream sequence gap triggers resync and converges.
15. Reconnect reloads thread detail before `.live`.
16. Multi-host configuration keeps rows isolated by host.
17. Rapid repeated client-visible mutations on the same thread preserve every
    ordered transition and each transition reaches the relay, Dock stream, and
    simulator display within the lag budget.

Scenario actuator contract:

- Each scenario must declare the exact actuator used to create the state change:
  Codex CLI command, app-server RPC, relay test fixture, or direct isolated
  storage fixture.
- For the stream-gap/resync case, the harness may put the client-side probe
  into the same "needs resync" state a detected sequence gap would create, but
  the recovery proof only counts if it uses the real `dock/resync` relay route
  and then converges with a fresh `dock/subscribe` snapshot. Synthetic relay
  rows or synthetic `dock/update` payloads do not count as client-path proof.
- Prefer real Codex CLI or app-server flows when the goal is end-to-end
  behavior. Use direct storage fixtures only for storage-edge cases that cannot
  be produced through supported APIs.
- The isolated scenario runner must document how `CODEX_HOME` is pointed at the
  temporary directory. If `rtk make services` cannot accept that environment
  directly, implementation must add a Makefile-owned wrapper instead of using
  raw service startup commands as the normal path.
- Isolated scenario services must isolate both Codex state and relay-owned
  cache/state. The relay state database must live under the temporary service
  runtime, such as `/tmp/codex-client/.../service/relay-state.sqlite`, and must
  not reuse repo-level `.codex-dock/relay-state.sqlite`.
- Server-request scenarios must name the request source and the expected request
  resolution path before they can count as completion evidence.
- Repeated-transition scenarios must name the repetition count, record each
  mutation separately, and fail if any intermediate transition is missed or
  only the final state converges.

#### 7. Reporter

The reporter writes sanitized machine-readable and human-readable output.

Required outputs:

- JSON report
- Markdown summary
- failing invariant list
- unsupported fact list
- stale or incomplete scope list
- movement classification
- event timeline
- selected detail target list
- exact commands used
- exact service endpoints used
- exact app build or relay commit when available

Required redaction:

- no bearer tokens
- no `OPENAI_API_KEY`
- no raw prompts
- no transcript text
- no raw audio
- no full JSON-RPC payloads

## Invariants

Every audit report must evaluate these invariants.

### Storage Invariants

`S-01`: The storage oracle can open the expected `CODEX_HOME` databases and
session directories, or the report fails with the exact missing path.

`S-02`: Every `state_5.sqlite.threads` row is classified as active, archived,
previewless, unsupported, or outside the client contract.

`S-03`: Every rollout `session_meta` thread id is either matched to SQLite,
classified as archived-only, classified as previewless, or reported as a storage
disagreement.

`S-04`: Every `goals_1.sqlite.thread_goals` row is matched to a thread id or
reported as an orphan goal.

`S-05`: Every `thread_spawn_edges` edge references known parent and child ids or
is reported as a storage disagreement.

`S-06`: Before/after storage movement is recorded and cannot silently mask a
client mismatch.

### App-Server Invariants

`A-01`: `thread/list` drains all requested source scopes without repeated
cursors.

`A-02`: The client-path relay report includes active, archived, default
interactive, reads, and turns for the selected audit mode without using
`relay/state/snapshot` or `state/query`.

`A-03`: Every app-server-listable stable thread maps to a storage row or a
clearly classified app-server-only live row.

`A-04`: Every app-server read result agrees with list metadata for id, archive
state, source, thread source, cwd, model/provider, and timestamps when both
surfaces expose the field.

`A-05`: Routed read and history read conflicts are reported with both values and
the selected canonical projection.

`A-06`: `thread/turns/list` either drains all pages or fails the detail audit.

`A-07`: `thread/goal/get` results agree with goal storage for all exposed goal
fields. Missing `goal_id` is recorded as an app-server contract limit.

`A-08`: `thread/loaded/list` live state agrees with relay live overlay after
lease rules are applied.

### Relay Projection Invariants

`R-01`: Relay state scopes report freshness, completeness, and last successful
refresh time.

`R-02`: Relay active projection includes every stable app-server active thread
after a successful complete refresh.

`R-03`: Relay archived projection includes every stable app-server archived
thread after a successful complete refresh.

`R-04`: Relay does not delete rows after incomplete refreshes.

`R-05`: Relay deletes or reclassifies rows after complete refreshes prove they
are gone or archived.

`R-06`: Relay order matches app-server active all-source order for stable rows,
except movement classified by before/after snapshots.

`R-07`: Relay live overlay does not change stored Codex order.

`R-08`: Relay live overlay expires stale leases.

`R-09`: Relay catch-up windows contain no duplicate ids, skipped rows, or
incorrect offsets.

`R-10`: Relay sequence gaps are detectable by clients.

### Dock Stream Invariants

`D-01`: `dock/subscribe` returns a complete initial window or explicitly marks
the relevant scope stale/incomplete.

`D-02`: `dock/update` sequences are strictly increasing per stream.

`D-03`: The long-lived stream receives every relay projection change after the
change is committed.

`D-04`: If the stream misses a change, it emits or requires `dock/resync`.

`D-05`: After `dock/resync`, the stream converges to the relay projection.

`D-06`: Windowed streams preserve exact offsets, total counts, and row identity.

`D-07`: Active and archived windows never leak rows across archive boundaries
after a complete refresh.

`D-08`: Host identity in every card matches the subscribed host.

### Swift DockStore Invariants

`C-01`: `DockStore` opens a stream for each configured host and does not collapse
host state.

`C-02`: `DockStore` publishes the same card set as `dock/subscribe` plus applied
updates.

`C-03`: `DockStore` preserves update order and resyncs on incompatible updates.

`C-04`: `DockStore` reports stale, offline, and reconnecting states instead of
presenting stale data as fresh.

`C-05`: `DockStore` keeps one-host failures isolated from other hosts.

`C-06`: Visible row order matches the relay projection for stable rows.

### Thread Detail Invariants

`T-01`: The selected Dock row thread id equals the opened detail thread id.

`T-02`: The selected Dock row host equals the detail session host.

`T-03`: Detail load calls `thread/read(includeTurns: false)`.

`T-04`: Detail load drains every `thread/turns/list` page.

`T-05`: Repeated turn cursors fail the load and prevent `.live`.

`T-06`: Duplicate turn ids fail the load.

`T-07`: Turn ordering matches the documented presentation contract.

`T-08`: `.live` is published only after read, turns, and resume succeed.

`T-09`: Resume failure leaves the view loaded but stale, not live.

`T-10`: Live notifications for other thread ids do not mutate this detail state.

`T-11`: Live partial deltas merge into the right turn/event.

`T-12`: Complete live snapshots replace partial event state correctly.

`T-13`: Live events emitted during initial load are either included in the
historical read or buffered and replayed.

`T-14`: Server requests after the live boundary appear as timeline events.

`T-15`: Server requests after the live boundary appear as request cards.

`T-16`: Server request resolutions update the matching request cards.

`T-17`: Reconnect and foreground rehydrate run a fresh compact read before
publishing `.live`.

`T-18`: Rehydrate does not duplicate historical events.

### Soak Invariants

`K-01`: Every sampled cycle records storage before, app-server state, relay
state, Dock stream state, selected detail state, and storage after.

`K-02`: Every intentional scenario mutation reaches stable agreement or fails
with a named invariant.

`K-03`: At least two consecutive samples after convergence remain in agreement.

`K-04`: Failures include first-bad timestamp, last-good timestamp, and affected
thread ids.

`K-05`: A stale/incomplete source scope cannot be counted as a fresh pass.

`K-06`: Long-running stream state is compared to fresh one-shot state on every
sample.

## Ongoing Test Loop

The ongoing process is the real answer to the over-time question. The team
should not rely on a single parity command.

### Preflight

Run the canonical services:

```bash
rtk make services
```

Check service state:

```bash
rtk make app-server-status
rtk make dock-relay-status
```

If service checks fail, stop the sync audit and record the exact failing command
and blocker.

### Baseline One-Shot

Run the exhaustive one-shot audit:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --mode one-shot \
  --exhaustive \
  --detail sampled \
  --fail-on-diff
```

Purpose:

- prove the current state is not already divergent;
- discover unsupported fields before the soak starts;
- choose detail targets from real Dock rows.

During migration from the current parity tool, also run the existing baseline:

```bash
rtk node scripts/dock-relay-state-parity.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --exhaustive \
  --fail-on-diff
```

Purpose:

- prove the new tool has not weakened today's one-shot parity coverage;
- keep `dock-relay-state-parity.mjs` useful until the shared collectors fully
  replace duplicate one-shot logic.

### Soak Run

Run the long-lived stream audit:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --mode soak \
  --duration-ms 900000 \
  --sample-interval-ms 30000 \
  --exhaustive \
  --detail sampled \
  --fail-on-diff
```

Purpose:

- keep `dock/subscribe` open;
- observe `dock/update` over many reconciliation intervals;
- compare every sample to fresh app-server and storage truth;
- open detail for selected rows during the run;
- verify reconnect and resync paths when injected or naturally triggered.

### Controlled Scenario Run

Run isolated scenarios in a temporary Codex home:

```bash
rtk node scripts/dock-relay-sync-audit.mjs \
  --mode scenario \
  --scenario all \
  --codex-home /tmp/codex-client/sync-audit/codex-home \
  --relay-url ws://127.0.0.1:4510 \
  --exhaustive \
  --detail all \
  --fail-on-diff
```

Purpose:

- prove known transitions, not only whatever happens to exist in the user's
  personal Codex home;
- produce deterministic failure cases;
- test archive, unarchive, live lease expiry, server requests, reconnect, and
  resync.

### Swift Client Proof

For Swift store changes or final client confidence, run the smallest relevant
tests first:

```bash
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter AppServerClientTests
```

For installed simulator UI behavior:

```bash
rtk make app-test SIM='iPhone 17'
```

If only the sync-audit script or relay code changes, start with:

```bash
rtk npm run test:relay
```

Do not run raw `xcodebuild`, raw `simctl install`, or raw `devicectl device
install app` as the normal workflow.

### Triage Rule

Every failed loop must end in one of these states:

- fixed and rerun to pass;
- classified as an app-server contract gap;
- classified as outside the client contract;
- classified as an infrastructure blocker with the exact command and error;
- classified as a product gap that blocks claiming full sync.

Do not close a loop with "probably fine" or "known flaky" unless the failure is
also attached to a named invariant and a follow-up fix.

## Report Schema

The JSON report should include these top-level fields:

```json
{
  "schemaVersion": 1,
  "mode": "one-shot",
  "startedAt": "2026-05-31T00:00:00Z",
  "endedAt": "2026-05-31T00:15:00Z",
  "relayUrl": "ws://127.0.0.1:4510",
  "codexHome": "/Users/aelaguiz/.codex",
  "serviceStatus": {},
  "storage": {},
  "appServer": {},
  "relay": {},
  "dockStream": {},
  "swiftClient": {},
  "threadDetails": [],
  "scenarios": [],
  "invariants": [],
  "unsupportedFacts": [],
  "failures": [],
  "redactions": []
}
```

Every invariant result should include:

- id
- status: `pass`, `fail`, `blocked`, `outside_contract`, or `not_applicable`
- affected thread ids
- first observed timestamp
- last observed timestamp
- expected source
- actual source
- short human summary

## Failure Taxonomy

Use stable failure codes so regressions can be compared over time.

Required failure codes:

- `storage_unavailable`
- `storage_disagreement`
- `app_server_scope_incomplete`
- `app_server_repeated_cursor`
- `app_server_list_read_conflict`
- `missing_from_relay_projection`
- `unexpected_relay_projection_row`
- `missing_from_dock_stream`
- `unexpected_dock_stream_row`
- `dock_duplicate_card`
- `dock_order_mismatch`
- `dock_archive_boundary_mismatch`
- `dock_host_mismatch`
- `dock_stale_reported_fresh`
- `dock_sequence_gap_unrecovered`
- `dock_window_mismatch`
- `live_status_stale`
- `live_status_missing`
- `detail_wrong_thread`
- `detail_missing_turn`
- `detail_duplicate_turn`
- `detail_turn_order_mismatch`
- `detail_resume_failed`
- `detail_live_event_dropped`
- `detail_live_event_duplicated`
- `detail_foreign_thread_event_applied`
- `detail_request_card_missing`
- `detail_request_resolution_missing`
- `detail_reconnect_stale_live`
- `unsupported_required_fact`
- `redaction_violation`

## Phase Plan

### Phase 1: Shared Collectors And Comparator

Goal: avoid duplicate truth logic.

Tasks:

- Factor or export storage collectors from `dock-relay-state-parity.mjs`.
- Factor or export relay snapshot collectors.
- Factor or export Dock subscribe comparison logic.
- Keep existing parity command behavior working.
- Add a shared report model for invariant results and failure codes.

Exit criteria:

- Existing parity command still passes its current tests.
- `rtk npm run test:relay` passes for relay changes.
- New shared modules can produce the same one-shot report as the current parity
  script.

### Phase 2: Long-Lived Dock Stream Watcher

Goal: prove the Dock stream stays aligned over time.

Tasks:

- Add a watcher that keeps `dock/subscribe` open.
- Record every `dock/update` sequence.
- Compare long-lived state to fresh relay snapshot on each sample.
- Inject or simulate sequence gaps where current test helpers allow it.
- Force `dock/resync` and verify convergence.
- Track stale and incomplete source scopes.

Exit criteria:

- Long-lived stream reaches the same stable state as one-shot
  `dock/subscribe`.
- Sequence gaps are detected and recovered.
- Stale scopes are never counted as fresh.

### Phase 3: Detail Click-Through Verifier

Goal: prove row-to-detail sync.

Tasks:

- Select detail targets from actual Dock rows.
- Open detail through the same protocol path used by `ThreadDetailStore`.
- Drain `thread/read` and all `thread/turns/list` pages.
- Resume with `thread/resume(excludeTurns: true)`.
- Keep observation open for notifications and server requests.
- Prove or fix the initial-load live-event race.
- Verify request cards and resolution.
- Verify reconnect rehydrate.

Exit criteria:

- Every selected row opens the same thread id and host.
- Historical turns match app-server truth.
- Live events are not dropped or duplicated.
- Request cards match server requests.
- `.live` is never published before read, turns, and resume succeed.

### Phase 4: Controlled Scenario Runner

Goal: prove known transitions, not just passive current state.

Tasks:

- Create an isolated `CODEX_HOME` under `/tmp/codex-client/...`.
- Start services against that isolated home.
- Drive the required scenarios.
- Record timestamps for every mutation and convergence point.
- Keep reports sanitized.

Exit criteria:

- Required scenarios pass twice in a row.
- Failures are deterministic and attached to invariant ids.
- Real-home read-only audit still works separately.

### Phase 5: Swift Client Proof

Goal: prove the actual client state, not only relay protocol state.

Tasks:

- Add or extend Swift tests around `DockStore` long-lived sync.
- Add or extend Swift tests around `ThreadDetailStore` row-to-detail sync.
- Verify stale, offline, reconnecting, and resync UI states.
- Use simulator app proof where behavior crosses store and UI boundaries.

Exit criteria:

- `rtk swift test --filter DockStoreTests` passes.
- `rtk swift test --filter ThreadDetailStoreTests` passes.
- `rtk swift test --filter AppServerClientTests` passes when JSON-RPC or DTO
  behavior changes.
- `rtk make app-test SIM='iPhone 17'` passes when installed UI behavior is in
  scope.

### Phase 6: Simulator Displayed-UI End-To-End-To-End Proof

Goal: prove what is literally displayed in the simulator stays in sync over
time. This is the third leg after Codex-to-relay proof and relay-to-client-route
proof.

This is the required third stage of the exhaustive sync goal. It must produce a
reusable over-time end-to-end-to-end harness that can be run again after future
changes, not just a one-off manual simulator check.

This phase is required before the overall goal can be called complete. It must
use the `iPhone 17` simulator and the normal relay-backed app path, not mocks,
preview rows, direct raw app-server connections, or scripted transports that the
client does not exercise.

After the Codex-to-relay path and relay-to-client-route improvements are green,
the work must continue into this phase. Relay-level proof alone is not a done
state because the user feels stale, missing, wrong, or lagged data through the
literal simulator client display.

Handoff requirement: when legs 1 and 2 pass, the implementation work must move
directly into this third simulator-display leg before claiming completion. The
final reusable harness must prove, over time, that the actual app screen stays
in sync end to end: no missing client-required data, no wrong Dock row or detail
state, no stale display state presented as fresh, and no convergence lag beyond
the configured real-time budget.

Mandatory third-stage note: this phase is the point where the harness stops
being only Codex-to-relay or relay-to-client-route proof and becomes
end-to-end-to-end proof through the actual simulator client. The result must be
a reusable over-time harness that can always be rerun to prove the literal app
display stays in sync, does not miss data, does not show stale or wrong data as
fresh, and does not lag enough for the client to feel behind.

Before implementing this phase, run `$model-consensus` with the requested model
pair, Opus 4.8 Max and GPT-5.5 X-High, to design the most elegant
end-to-end-to-end harness and the invariants it must enforce. Do not start this
phase until that consensus design exists and is recorded. The consensus result
is recorded at
`.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/summary.md`.

This consensus call is a Phase 6 entry gate: do not invoke it while legs 1 and
2 are still being finished, but do not claim the overall goal complete until
the consensus design has run and the resulting simulator-display harness is
implemented.

Consensus correction: passive real-home simulator observation is not enough for
completion-grade lag proof because it can pass without any observed content
change. Completion-grade proof requires a deterministic isolated-`CODEX_HOME`
scenario actuator that produces real app-server, relay, and client-visible
changes through normal routes. Passive real-home display proof remains useful
smoke and regression evidence, but it cannot close this phase by itself.

Tasks:

- Launch the app through Makefile-owned simulator flows such as
  `rtk make sim-ui-sync-proof SIM='iPhone 17'`,
  `rtk make sim-ui-scenario-sync-proof SIM='iPhone 17'`,
  `rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17'`,
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`,
  `rtk make app-test SIM='iPhone 17'`, or the matching app launch target.
- Configure the simulator app to use the relay-backed host path on `:4510`.
- Run the relay sync audit recorder and simulator displayed-UI sampler
  concurrently so the UI samples and relay truth share the same time window.
- Do not stimulate client-observed data through a route the client itself never
  exercises and count that as displayed-client proof. Fixtures may create
  controlled upstream changes, but the observed app behavior must come through
  normal relay-backed client routes and actual simulator UI interactions.
- Observe the literal Dock/Home UI over time and compare displayed
  `DockThreadCard` rows to the same Codex, app-server, relay, and client-route
  report used by the earlier phases.
- Open displayed Dock rows in the simulator and compare the literal detail UI to
  `thread/read`, `thread/turns/list`, `thread/resume`, live notifications, and
  server-request truth.
- Measure lag all the way through the rendered UI, not only through the relay
  stream. A pass requires the displayed simulator state to converge within the
  configured client-visible lag budget.
- Treat fast UI samples as visible/watched-row proof plus root row-count proof.
  Run bounded full-scroll sweeps only at stable checkpoints for missing,
  unexpected, duplicate, and order checks; full sweeps are not the fast lag
  clock.
- Paired simulator proof targets should run checkpoint sweeps by default through
  `SIM_UI_SYNC_CHECKPOINT_SWEEP=1`. A sweep is stable checkpoint evidence for
  missing, unexpected, duplicate, and order errors; it is not the high-frequency
  lag clock.
- Use only redaction-safe fingerprints for one-to-one visible fields that must
  match, such as Dock row title and detail event title/body. Do not fingerprint
  client-derived preview/summary fields as if they were relay truth.
- Capture enough simulator evidence, such as accessibility snapshots,
  screenshots, app logs, and audit timestamps, to explain the first bad visible
  row, missing detail item, stale state, or lag violation.
- Keep the test running over time across multiple samples. A single screenshot
  or one-shot UI check is not enough.
- The reusable completion harness must include a scenario-driven simulator leg:
  start the actual simulator UI sampler first, apply real app-server/relay
  mutations through client-exercised routes, then prove the rendered UI observes
  the same changes within the lag budget.

Exit criteria:

- The simulator Dock list displays every client-required card exactly once,
  with correct host, archive membership, status, ordering, and stale/error
  state, using visible over-time samples plus checkpoint sweeps for full-list
  coverage.
- Opening a visible Dock row displays the same thread id and complete
  client-required detail state.
- The rendered UI does not miss client-required data that exists in Codex,
  app-server, relay, or the client-route probe.
- The rendered UI does not exceed the configured lag budget.
- Completion-grade lag proof includes a deterministic isolated-`CODEX_HOME`
  scenario with an observed change and isolated relay state DB/cache; passive
  real-home observation alone is not sufficient.
- The deterministic isolated fixture can seed multiple active
  `sessions/...` threads, for example with `SIM_UI_ISOLATED_THREAD_COUNT`, so
  checkpoint sweeps prove full-list behavior and do not accidentally treat
  `archived_sessions/...` rollouts as active client rows.
- The simulator proof runs over time and produces a reusable report that can be
  run again as a regression harness.
- The controlled simulator matrix can be run as one Makefile-owned proof loop,
  and the two-pass completion gate must use distinct report directories so the
  same artifact cannot count as multiple independent passes.
- The `$model-consensus` design result is attached or referenced before this
  phase is implemented.

### Phase 7: Runbook And Continuous Loop

Goal: make the harness usable repeatedly.

Tasks:

- Document the one-shot, soak, scenario, Swift proof, and simulator displayed-UI
  proof commands in `README.md` or a dedicated runbook.
- Define where reports go under `/tmp/codex-client/...`.
- Add CI-safe subsets if possible.
- Keep real-home audits local-only unless sanitized report artifacts are
  intentionally shared.

Exit criteria:

- A developer can run the loop without reading source code.
- The loop clearly says pass, fail, blocked, or outside-contract.
- Reports preserve exact commands and exact blockers.

## Completion Gate

The mechanism is complete only when all of these are true:

1. One-shot audit passes on a real local service stack.
2. Soak audit passes across multiple reconciliation intervals.
3. Controlled scenario audit passes for required transitions.
4. Dock stream proof includes `dock/subscribe`, `dock/update`, and
   `dock/resync`.
5. No sample exceeds the configured client-visible lag budget.
6. Detail proof starts from actual Dock rows and validates `thread/read`,
   `thread/turns/list`, `thread/resume`, notifications, and server requests.
7. Swift store tests pass for Dock list and thread detail state.
8. `$model-consensus` with Opus 4.8 Max and GPT-5.5 X-High has designed the
   simulator displayed-UI harness and invariant list.
9. Simulator displayed-UI proof passes on `iPhone 17` and verifies the literal
   app screen over time, including checkpoint sweeps for full-list coverage.
10. Simulator displayed-UI proof uses actual client-exercised paths and fails
   on missing data, stale displayed data, wrong detail data, or lag beyond the
   configured budget.
11. Unsupported facts are explicitly classified.
12. No client-required field is classified as `product_gap`.
13. Reports are sanitized and contain stable invariant ids.
14. The ongoing loop has been run at least twice with the same passing result.

## Open Risks

### No Atomic Cross-Plane Snapshot

There is no single snapshot id across storage, app-server, relay, Dock stream,
and Swift client state.

Mitigation:

- take storage before and after;
- record app-server, relay, stream, and detail timestamps;
- classify movement;
- require two stable samples after convergence.

### Detail Initial-Load Race

`ThreadDetailStore` starts observation before historical read and turn drain, but
history replacement can overwrite state. A live event could be emitted during
the initial load window.

Mitigation:

- choose and record a live boundary;
- prove app-server history includes all events before the boundary, or buffer
  live events until the history load completes and replay them;
- add a targeted test before claiming detail sync.

### Previewless Rows

Storage can contain previewless rows outside current `thread/list` behavior.

Mitigation:

- classify previewless rows separately;
- do not require Dock cards for rows outside app-server list support unless the
  product contract changes.

### Orphan Goals

`goals_1.sqlite` can contain goal rows app-server cannot list globally.

Mitigation:

- compare `thread/goal/get` for known thread ids;
- report orphan goals as unsupported or storage disagreement;
- do not claim global goal exhaustiveness until app-server exposes it.

### Historical Prompt Start And Output Schema

Some historical prompt-start and output schema details are not reliably exposed
through app-server APIs.

Mitigation:

- keep those facts out of client-required sync unless APIs expose them;
- classify them as `outside_app_server_contract` when encountered.

## Plan Audit Requirement

Before implementation starts, this plan must pass:

1. `$plan-audit` against this file and the relevant code paths.
2. `$fresh-consult` using Cursor Agent `composer-2.5-fast`.

Before Phase 6 starts, the simulator displayed-UI harness design must pass
`$model-consensus` using Opus 4.8 Max and GPT-5.5 X-High. That consensus must
define the end-to-end-to-end approach, the exact invariants, how literal
simulator display state is observed, and how over-time lag is measured through
the rendered client.

Both reviews must agree that the plan fully defines:

- the initial tool build;
- the long-running over-time sync loop;
- Dock/Home list comparison;
- click-through thread detail comparison;
- storage, app-server, relay, and Swift client truth boundaries;
- unsupported facts and product gaps;
- proof gates and exact commands.
