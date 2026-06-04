---
title: "Codex Dock - Server-Initiated Thread Rename Sync"
date: 2026-06-04
status: implemented-and-verified
owners: [Amir, Codex]
doc_type: architectural_change_plan
scope: relay and client ingest of host-side thread rename notifications
---

# TL;DR

Concrete answer:
- Today, Codex app-server emits `thread/name/updated` when a host-side Codex CLI instance changes a thread name.
- Today, Codex Dock does not ingest that notification as a Dock card update. Client-initiated renames work because the relay handles `thread/name/set` and then explicitly refreshes Dock and Archive projections.
- This plan makes host/server-initiated renames use the same relay projection path as client-initiated renames, so the iPhone app keeps consuming only `dock/update` and `archive/update`.

North Star:
- If any initialized upstream Codex app-server connection observed by the relay receives `thread/name/updated` for a human-started thread, every subscribed Dock client sees the updated title through the existing `dock/update` card stream without a local title shadow or a raw `thread/name/updated` client-side path.

Core architecture:
- Treat `thread/name/updated` as an invalidation signal, not as card truth.
- Relay notification ingest extracts only `threadId`, then calls the same `RelayStateEngine` reconcile method used after `thread/name/set`.
- Reconciliation rereads canonical app-server state and publishes `dock/update` / `archive/update` only when the projected card state actually changes.
- Swift remains unchanged unless tests reveal a missing row-driven detail update. The client should not learn a new raw rename notification route.

Implementation result:
- Relay now ingests `thread/name/updated` from history/live pooled upstream clients and active detail upstream clients.
- Client-initiated `thread/name/set` and server-initiated `thread/name/updated` share the same Dock and Archive reconciliation helper.
- The iPhone client still consumes `dock/update` / `archive/update`; raw rename notifications are not exposed as a phone-side route.
- Verified on 2026-06-04 with Node relay tests, focused Swift Dock tests, full Node test suite, and the controlled iPhone 17 simulator proof.
- Completion audit on 2026-06-04 also verified `ThreadDetailStoreTests`, standalone `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`, pushed commit state, and local/home relay readiness.

# 1. Current Behavior

## 1.1 What works now

Client-initiated rename already has an end-to-end path:

```text
Swift rename UI
  -> DockStore.rename(...)
  -> AppServerThreadCommandClient.renameThread(...)
  -> relay "thread/name/set"
  -> Codex app-server "thread/name/set"
  -> RelayStateEngine.handleThreadNameMutation(...)
  -> reconcileDock + reconcileArchive
  -> dock/update / archive/update
  -> DockRowViewModel.title
```

Code evidence:
- `CodexDock/AppServer/AppServerMethods.swift` defines `thread/name/set`.
- `CodexDock/State/AppServerThreadCommandClient.swift` sends the typed rename command.
- `CodexDock/State/DockStore.swift` validates the draft name, invokes the command engine, and refreshes after success.
- `scripts/dock-relay.mjs` dispatches `thread/name/set`.
- `scripts/dock-relay-thread-data.mjs` forwards `thread/name/set` to the owning endpoint.
- `scripts/dock-relay-state-engine.mjs` reconciles Dock and Archive after `handleThreadNameMutation`.
- `scripts/dock-relay-card-contract.test.mjs` proves client rename refreshes the card title from server state.

## 1.2 What does not work now

Server-initiated rename is not wired into relay state:

```text
Host Codex CLI / another app-server client
  -> Codex app-server emits "thread/name/updated"
  -> relay upstream JsonRpcWebSocketClient can receive notifications
  -> no relay state ingest handles this method
  -> detail projection adapter returns [] for this method
  -> Swift card stream ignores it because it only consumes dock/update/archive/update
```

Code evidence:
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md` documents that `thread/name/set` emits `thread/name/updated`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs` sends `ServerNotification::ThreadNameUpdated` after the rename response.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs` defines `ThreadNameUpdatedNotification { thread_id, thread_name? }` with camelCase wire shape `{threadId, threadName?}`.
- `scripts/dock-relay-thread-detail-projection-adapter.mjs` has a default `eventsFromNotification` branch that returns `[]`; it does not handle `thread/name/updated`.
- `scripts/dock-relay.mjs` handles active detail upstream notifications by applying them to the detail ledger first; if the ledger accepts the message, raw forwarding stops.
- `CodexDock/State/AppServerThreadCardStreamClient.swift` intentionally filters to the card stream route for its view, so raw `thread/name/updated` is ignored by the client.

## 1.3 Why polling is not enough

The relay reconciler eventually polls:

```text
StateReconciler.start()
  -> boot reconcile
  -> periodic reconcile every RELAY_STATE_RECONCILE_INTERVAL_MS
```

That means a rename may eventually appear after the next periodic pass, but that is not event sync. The desired behavior is event-driven invalidation when the relay is already connected to an initialized upstream that receives the notification.

# 2. Requirements

## 2.1 User-facing requirements

- A thread renamed on the host Codex CLI appears renamed in the iPhone Dock list without the user initiating the rename from the app.
- If thread detail is open for that row, its header title updates from the existing Dock row update path.
- No app UI regression: client-initiated rename keeps working exactly as it does now.
- Duplicate upstream notifications must not create duplicate visible card updates when the card content is unchanged.
- If reconciliation fails, the relay logs a sanitized warning and leaves the current card title unchanged until a later successful reconciliation.

## 2.2 Code-quality requirements

- One source of displayed title truth: `DockThreadCardDTO.title` from relay projection.
- One rename invalidation path in relay state: client command and server notification both end at the same reconcile helper.
- No client-side raw `thread/name/updated` handling unless a test proves the existing `dock/update` path cannot satisfy the requirement.
- No local metadata title field, no optimistic row retitle, no notification title cache.
- No direct app connection to raw authenticated app-server `:4500`.
- No log lines containing raw thread names, prompt text, transcript text, bearer tokens, `OPENAI_API_KEY`, or full JSON-RPC payloads.

## 2.3 Non-requirements

- Do not change the Codex app-server protocol. Upstream already exposes `thread/name/updated`.
- Do not add new rename UI.
- Do not make `thread/name/updated` a public phone-facing route.
- Do not update the archived-only UI rename behavior beyond the projection refresh already used by `archive/update`.
- Do not solve every upstream notification type. This plan handles thread name changes only.

# 3. Target Architecture

## 3.1 Event flow

```text
Codex app-server notification
  method: "thread/name/updated"
  params: { threadId, threadName? }

relay upstream client onNotification
  -> ingestRelayStateNotification(config, message, source)
  -> RelayStateEngine.handleThreadNameNotification(message)
  -> NotificationIngestor.ingestThreadNameUpdated(message)
  -> RelayStateEngine.handleThreadNameMutation({
       threadId,
       reason: "thread/name/updated"
     })
  -> reconcileDock({ reason })
  -> reconcileArchive({ reason })
  -> StateSubscriptionHub publishes dock/update/archive/update if changed
  -> Swift AppServerThreadCardStreamClient receives dock/update/archive/update
  -> DockStore row update
  -> selected ThreadDetailStore.observeDockRowUpdate(updatedRow)
```

## 3.2 Canonical owner split

- `scripts/dock-relay-json-rpc-client.mjs`: already owns low-level notification callbacks. No change expected except tests if needed.
- `scripts/dock-relay-upstream-pool.mjs`: owns pooled long-lived upstream clients. It should accept and pass `onNotification` to `JsonRpcWebSocketClient`.
- `scripts/dock-relay-thread-data.mjs`: owns history/live upstream client construction. It should pass `config.upstreamNotificationHandler` into history, live-status, and live-lease upstream clients.
- `scripts/dock-relay-state-ingest.mjs`: owns relay state invalidation ingestion. It should parse `thread/name/updated` and return a small mutation descriptor.
- `scripts/dock-relay-state-engine.mjs`: owns reconciliation. It should make `handleThreadNameMutation` accept a reason and add `handleThreadNameNotification`.
- `scripts/dock-relay.mjs`: owns runtime wiring. It should create one sanitized upstream notification handler and call it from active detail upstream notifications before the detail ledger consumes the message.
- Swift state stays owned by `dock/update` card streams and `observeDockRowUpdate`.

## 3.3 Why not use `threadName` directly

The notification includes `threadName`, but the relay should not write that value into cards directly.

Reasons:
- Card title fallbacks live in `scripts/dock-relay-state-views.mjs`, not in notification handling.
- A rename can affect both Dock and Archive projection state, freshness, ordering metadata, and completeness.
- Reusing `reconcileDock` and `reconcileArchive` keeps client-initiated and server-initiated renames on the same code path.
- If app-server wire shape changes, canonical reads fail or adapt in one place instead of leaving stale direct writes.

## 3.4 Duplicate handling

Client-initiated rename may produce two relay invalidations:

```text
1. downstream phone request "thread/name/set" returns success
2. relay calls handleThreadNameMutation(reason: "thread/name/set")
3. upstream app-server also emits "thread/name/updated"
4. relay calls handleThreadNameMutation(reason: "thread/name/updated")
```

This is acceptable only if the second reconcile is visible-no-op when card content is unchanged. Tests must prove one visible title transition for the subscribed client, not two duplicate `dock/update` mutations with identical rows.

Do not remove the direct post-command reconcile. It is the safest path for one-shot live endpoint calls where the temporary upstream client may close before it can observe the notification.

# 4. Implementation Plan

## Phase 1 - Add relay notification ingest

Files:
- `scripts/dock-relay-state-ingest.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-subscriptions.test.mjs`

Changes:
- Add `NotificationIngestor.ingestThreadNameUpdated(message)`.
- Accept only `message.method === "thread/name/updated"`.
- Extract `params.threadId`; optionally tolerate `params.threadID` only if existing local helpers already do so nearby, but do not invent broad casing magic.
- Return `{ threadId, reason: "thread/name/updated" }`.
- Add `RelayStateEngine.handleThreadNameNotification(message)`.
- Change `handleThreadNameMutation({ threadId, reason = "thread/name/set" })`.
- Keep reconciliation implementation shared by direct command and notification paths.

Proof:
- Unit test valid notification -> Dock and Archive reconcile with reason `thread/name/updated`.
- Unit test unrelated notification -> no reconcile.
- Unit test missing `threadId` -> no reconcile.
- Existing client command test still expects reason `thread/name/set`.

Exit:
- Focused Node tests pass for state engine and notification ingest.

## Phase 2 - Wire upstream notifications into relay state

Files:
- `scripts/dock-relay.mjs`
- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-upstream-pool.mjs`
- `scripts/dock-relay-live-status-cache.mjs` only if constructor shape requires explicit propagation

Changes:
- Add a small helper in `dock-relay.mjs`, for example:

```js
function ingestRelayStateNotification(config, message, source = {}) {
  if (message?.method !== "thread/name/updated") {
    return;
  }
  relayStateEngineForConfig(config)
    .handleThreadNameNotification(message)
    .catch((error) => relayLogger(config).warn("state.thread_name_notification_ingest_failed", {
      method: message?.method,
      threadIDHash: shortHash(message?.params?.threadId || message?.params?.threadID),
      source: source.label || source.url || null,
      error,
    }));
}
```

- The actual code should avoid logging raw thread names or full params.
- Call this helper from `makeSessionUpstreamClient(...).onNotification` before `handleDetailNotification`.
- Set `config.upstreamNotificationHandler` during `startServer` before any code can create `config.upstreamPool`, `config.liveStatusCache`, `config.sessionRouter`, `config.historyClient`, or auto-start `config.relayStateEngine`.
- Pass `config.upstreamNotificationHandler` into `HistoryClient`, pooled clients, live-status collection, and `collectLiveRows` / `readLoadedRows` client creation.
- Extend `UpstreamConnectionPool.clientFor` and `request` to accept `onNotification` when creating a new `JsonRpcWebSocketClient`.
- Do not mutate callback behavior of an already-open pooled client unless the local pool already has a callback update pattern. Production must create the callback before first client open; tests must cover this startup order.

Proof:
- Relay startup-order test proves the first history pooled client is created with `onNotification`.
- Relay card contract test where the fake app-server sends `thread/name/updated` to the relay's history connection after its row state changes. Assert a subscribed phone client receives `dock/update` with the new title without sending `thread/name/set`.
- Active detail/live upstream test where an initialized resumed session receives `thread/name/updated`; assert the notification is ingested even though the detail projection adapter produces no row for the raw method.
- Test sanitized failure logging does not include raw `threadName`.

Exit:
- `rtk npm run test:relay` passes.

## Phase 3 - Preserve Swift client simplicity

Files:
- `CodexDock/State/AppServerThreadCardStreamClient.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDockTests/ThreadDetailStoreTests.swift`
- `CodexDockTests/DockStoreTests.swift`

Expected change:
- Prefer no production Swift change.

Validation:
- Confirm card stream client still only ingests `dock/update` for Dock and `archive/update` for Archive.
- Confirm `DockView.syncSelectedDetail` still calls `ThreadDetailStore.observeDockRowUpdate(updatedRow)`.
- Confirm `ThreadDetailHeader.title` still comes from `DockRowViewModel.title`.

Add tests only if the existing coverage is not explicit enough:
- Thread detail header updates when `observeDockRowUpdate` receives a row with a new title.
- Dock row stream update path replaces a row title from `dock/update` without any raw rename notification.

Exit:
- `rtk swift test --filter DockStoreTests` passes.
- `rtk swift test --filter ThreadDetailStoreTests` passes if any detail test or production detail file changes.

## Phase 4 - Controlled simulator proof

Files:
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.mjs`
- related tests if the controlled matrix needs a new scenario

Required proof:
- Add a controlled scenario named `server-rename-notification`.
- Fake app-server starts with a row title like `Before server rename`.
- The fixture mutates server row state and sends `thread/name/updated`.
- Relay publishes `dock/update`.
- Simulator UI proof asserts the visible Dock row changes to `After server rename`.
- If detail is open, assert the detail header changes too.

Additional real-service sanity proof:
- Run `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`.
- Start real services with `rtk make services`.
- Use a real host Codex CLI or a narrow relay-side proof script to rename a real human-started thread outside the app.
- Verify app-server read, relay `dock/update`, and simulator UI all show the new title.
- Restore the original name after the proof.
- If the real-service proof is blocked by missing simulator/device/service prerequisites, record the exact command and exact blocker. The controlled simulator scenario remains required unless its own Makefile-owned target is blocked by the environment.

Exit:
- Simulator evidence is real app UI evidence, not only Node integration.
- No preview rows are used as completion evidence.

## Phase 5 - Review, commit, push, and restart relays

Review:
- Run `$thermo-nuclear-code-quality-review` as a code review against the branch changes.
- Fix every blocking maintainability issue.
- Re-run relevant tests after fixes.

Git:
- Check `rtk git status --short`.
- Stage explicit paths only.
- Commit with a message that names server rename notification sync.
- Push the current branch.

Local relay:
- Run `rtk make services` or the smallest relay restart command that reloads the updated code.
- Check `rtk make dock-relay-status`.

Home relay:
- SSH to `home`.
- In `/home/aelaguiz/workspace/codex-client`, run `git fetch` and `git pull --ff-only` from the pushed branch.
- If home-only dirt blocks the pull, report exact dirty paths and the cleanup command before discarding anything.
- Restart home services with the Linux Makefile overrides documented in repo instructions.
- Check home host service / relay status.

# 5. Test Matrix

## 5.1 Node relay tests

Required:
- `NotificationIngestor.ingestThreadNameUpdated` accepts a valid notification.
- `NotificationIngestor.ingestThreadNameUpdated` ignores unrelated methods.
- `NotificationIngestor.ingestThreadNameUpdated` ignores missing thread id.
- `RelayStateEngine.handleThreadNameNotification` reconciles Dock and Archive with reason `thread/name/updated`.
- Existing `handleThreadNameMutation` for client command still reconciles Dock and Archive with reason `thread/name/set`.
- Fake history app-server emits `thread/name/updated`; subscribed relay client receives one `dock/update` with the new title.
- Startup-order test proves the first history pooled upstream client has the relay notification handler installed.
- Fake active detail app-server emits `thread/name/updated`; relay ingests it even though detail ledger does not render the raw notification.
- Duplicate command-plus-notification path does not produce duplicate unchanged visible updates.
- Reconcile failure logs sanitized fields and does not leak raw `threadName`.

Command:

```bash
rtk npm run test:relay
```

## 5.2 Swift tests

Required if production Swift does not change:
- Existing Dock and detail tests must still pass.
- Add narrow tests only where current coverage does not explicitly prove row-driven header rename.

Commands:

```bash
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

## 5.3 Simulator tests

Required:
- `iPhone 17` simulator launches the updated app.
- Controlled server-side rename changes visible Dock title through relay-backed host config.
- Real-service server-side rename sanity proof runs when the local simulator/service environment allows it.
- Detail header updates if detail is open for the renamed row.

Commands:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make app SIM='iPhone 17' FORCE_LAUNCH=1
```

If a controlled simulator scenario is added:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=server-rename-notification
```

# 6. Risk Register

## R1 - Upstream notification callback is missing on pooled clients

Risk:
- The relay may observe notifications only on active detail sessions and miss history/live-status pooled connections.

Mitigation:
- Add `onNotification` to `UpstreamConnectionPool.clientFor`, `UpstreamConnectionPool.request`, `HistoryClient`, `clientForEndpoint`, `readLoadedRows`, and `collectLiveRows`.
- Add tests that prove the history pooled client receives and ingests the notification.

## R2 - Detail ledger swallows the notification

Risk:
- Active detail sessions call `handleDetailNotification`; unknown notifications can be consumed and not forwarded.

Mitigation:
- Call relay state ingest before detail ledger handling.
- Keep detail projection unchanged unless product UI needs a system row, which this plan does not require.

## R3 - Direct notification title creates duplicate truth

Risk:
- Writing `params.threadName` directly into cards bypasses projection rules.

Mitigation:
- Treat the notification as invalidation only.
- Tests assert app-server row state is reread before the visible title changes.

## R4 - Client command path double-publishes after app-server notification

Risk:
- Client rename may trigger explicit reconcile and notification reconcile.

Mitigation:
- Keep both invalidations, but require unchanged projection suppression.
- Add duplicate command-plus-notification test.

## R5 - Reconcile uses broad refresh instead of thread-targeted refresh

Risk:
- Full Dock and Archive reconcile may be heavier than necessary.

Mitigation:
- Accept full reconcile for this change because it is the existing mutation pattern and preserves correctness.
- Do not add a thread-targeted fast path until there is measured pressure.

## R6 - Logs leak thread names

Risk:
- Failure logs may include raw notification params or raw names.

Mitigation:
- Log method, source label/url, short thread hash, and error summary only.
- Add a test or code assertion around sanitized logging if a new log path is introduced.

# 7. Acceptance Checklist

- [x] Plan audit sidecar exists at `docs/THREAD_RENAME_SERVER_SYNC_2026-06-04_PLAN_AUDIT.md`.
- [x] Plan audit verdict is `ready` before implementation starts.
- [x] Relay ingests `thread/name/updated` from history pooled upstream clients.
- [x] Relay ingests `thread/name/updated` from active detail upstream clients before detail ledger handling.
- [x] Client-initiated `thread/name/set` still refreshes via the same reconcile helper.
- [x] Server-initiated rename publishes `dock/update` with the new title.
- [x] Duplicate command-plus-notification does not duplicate visible unchanged updates.
- [x] Swift client still consumes card streams, not raw rename notifications.
- [x] Open detail header updates from `observeDockRowUpdate`.
- [x] `rtk npm run test:relay` passes.
- [x] `rtk swift test --filter DockStoreTests` passes.
- [x] `rtk swift test --filter ThreadDetailStoreTests` passes.
- [x] `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1` passes.
- [x] Simulator proof shows a server-side rename visible in the app.
- [x] Thermonuclear review has no blocking findings.
- [x] Changes are committed and pushed.
- [x] Local relay is restarted on updated code.
- [x] Home checkout is fast-forwarded and home relay is restarted on updated code.
