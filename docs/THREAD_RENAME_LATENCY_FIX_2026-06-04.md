---
title: "Codex Dock - Client Rename Latency Fix"
date: 2026-06-04
status: implemented
owners: [Amir, Codex]
doc_type: implementation_plan
scope: make client-initiated thread rename submit immediately, display optimistically, and reconcile through the existing relay card stream
---

# TL;DR

Concrete answer:
- Client rename is slow because one Save tap waits for too much synchronous work.
- Current Swift waits for `thread/name/set`, then calls `DockStore.refresh()`.
- Current relay waits for app-server `thread/name/set`, then performs full Dock and Archive reconciliation before replying to the client.
- The UI sheet remains blocked until those steps finish, so a title change can feel frozen and can time out when reconciliation is slow.

Target behavior:
- Save is submit-and-move-on.
- The sheet closes immediately after valid input is submitted.
- The Dock row and open detail header show the new title optimistically right away.
- The app-server command runs in the background.
- The canonical `dock/update` / `archive/update` stream remains the durable truth and confirms the optimistic title later.
- On command failure, the optimistic title is rolled back and the existing action error path shows the failure.

# 0. Implementation Result

Implemented on 2026-06-04.

- Dock rename now uses an in-app rename editor, closes the editor on Save, and runs `DockStore.rename(...)` in a background task.
- `DockStore` publishes an in-memory optimistic title overlay before the server command returns, does not persist that overlay, does not call `refresh()` after successful rename, and rolls back on command failure.
- Relay `thread/name/set` now replies after app-server acceptance and runs Dock/Archive reconciliation after the response.
- The existing `thread/name/updated` notification path remains the canonical stream confirmation path.

Passing proof:

```bash
rtk make sim-ui-client-rename-proof SIM='iPhone 17'
```

Proof artifact:

```text
/tmp/codex-client/sim-ui-client-rename-20260604T121424Z/client-rename-latency.json
```

Measured result:
- UI editor gone: 586 ms against a 700 ms budget.
- Optimistic Dock title visible: 650 ms against a 700 ms budget.
- Fake app-server ACK delay: 1501 ms.
- Canonical `dock/update` with the server title: observed.

Verification commands:

```bash
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk npm run test:relay
rtk make sim-ui-client-rename-proof SIM='iPhone 17'
```

Verification results:
- `DockStoreTests`: 57 tests, 0 failures.
- `ThreadDetailStoreTests`: 64 tests, 0 failures.
- Relay tests: 190 tests, 0 failures.
- Simulator latency proof: pass, 0 findings.

# 1. Current Root Cause

## 1.1 Swift blocks the sheet on server and refresh work

Current path:

```text
DockRenameThreadSheet Save
  -> DockView.saveRename(...)
  -> await DockStore.rename(...)
  -> await AppServerThreadCommandClient.renameThread(...)
  -> await DockStore.refresh()
  -> dismiss sheet only after Bool returns
```

Code evidence:
- `CodexDock/Features/Dock/DockRenameThreadSheet.swift` calls async `onSave` from the Save button.
- `CodexDock/Features/Dock/DockView.swift` keeps `isRenameInFlight = true` while awaiting `store.rename(...)`.
- `CodexDock/State/DockStore.swift` calls `await refresh()` after the command succeeds.
- `DockStore.refresh()` calls `reload(showLoading: false)`, which drives stream manual refresh and snapshot publication.

Consequence:
- Even if app-server accepts the rename quickly, the user waits for client-side reload work before the sheet closes.
- The row cannot show the new title until a refresh or stream update reaches `DockSnapshot`.

## 1.2 Relay blocks the command response on broad reconciliation

Current relay route:

```text
thread/name/set request
  -> setThreadName(...)
  -> app-server thread/name/set
  -> await RelayStateEngine.handleThreadNameMutation(...)
  -> reconcileDock()
  -> reconcileArchive()
  -> response returns to iPhone
```

Code evidence:
- `scripts/dock-relay.mjs` awaits `relayStateEngineForConfig(config).handleThreadNameMutation(...)` before returning the route result.
- `scripts/dock-relay-state-engine.mjs` handles thread-name mutation by reconciling Dock and Archive.
- `reconcileDock()` drains thread lists, refreshes live leases, validates human-started rows, reads session-index supplements, and canonicalizes rows with `thread/read` plus `thread/turns/list`.
- `reconcileArchive()` repeats broad archived-list validation and canonicalization.

Consequence:
- Rename request latency includes a full card-projection refresh.
- If any thread-list/read/turns endpoint is slow, the rename request can be slow or time out.

## 1.3 Existing server-side rename sync is the right confirmation path

The prior server-initiated rename work already made `thread/name/updated` flow through:

```text
app-server notification
  -> relay state ingest
  -> RelayStateEngine.handleThreadNameNotification(...)
  -> same Dock/Archive reconciliation helper
  -> dock/update / archive/update
  -> Swift card stream
```

That path should remain the final confirmation path for both client and host/server renames.

# 2. North Star

When a user renames a thread from the iPhone:

```text
tap Save
  -> sheet dismisses quickly
  -> row title updates immediately from an in-memory optimistic rename
  -> command is sent in the background
  -> relay returns after app-server accepts thread/name/set, not after full reconciliation
  -> existing stream reconciliation confirms the canonical server title
  -> if the command fails, optimistic title rolls back and an action error is shown
```

Done-state latency goals:
- UI submit latency: rename sheet disappears within 1 second in controlled simulator proof.
- Optimistic visible title latency: Dock row shows the submitted title within 1 second in controlled simulator proof.
- Relay command ack latency: controlled relay test proves `thread/name/set` response is not gated on slow Dock/Archive reconciliation.
- Canonical stream latency: controlled simulator proof still observes the server-confirmed title through `dock/update` within the existing relay lag budget.

# 3. Design

## 3.1 Swift: make rename optimistic and non-blocking

Change `DockView.saveRename(...)`:
- Validate non-empty and changed name synchronously.
- Close the rename sheet immediately.
- Start the rename command in a `Task` instead of awaiting it from the sheet.
- Do not keep the sheet open behind a spinner for the network command.

Change `DockStore.rename(...)`:
- Keep the existing async API so tests and detail toolbar callers can still await if needed.
- Before awaiting the command, publish an optimistic title overlay for the target row.
- Do not call `await refresh()` after successful rename.
- On command success, leave the optimistic overlay active until the card stream publishes the same canonical title, then clear it.
- On command failure, remove the optimistic overlay, republish the last canonical snapshot, and set `actionError`.

Implementation shape:
- Add an in-memory `pendingRenameTitles` dictionary keyed by `HostScopedThreadID`.
- Add a small `DockRowViewModel` copy helper such as `withTitle(_:)`.
- Apply `pendingRenameTitles` only during snapshot publication, never in local metadata and never in relay DTOs.
- Clear a pending title when a fresh projected row for that thread already carries the same title.
- Do not persist pending rename titles.

Why this is still safe:
- The server stream remains the durable title source.
- The optimistic title is a temporary UI affordance, not a second stored truth.
- Failure rolls back to the last canonical snapshot.

## 3.2 Relay: do not wait for broad reconciliation before command response

Change `scripts/dock-relay.mjs` `thread/name/set` route:
- Still validate and forward `setThreadName(config, params)`.
- Return the app-server result to the client as soon as `setThreadName` succeeds.
- Fire-and-forget `relayStateEngineForConfig(config).handleThreadNameMutation({ threadId })`.
- Log reconcile failure with sanitized fields only.

Keep:
- `RelayStateEngine.handleThreadNameMutation(...)` as the shared reconciliation helper.
- `thread/name/updated` notification ingest using the same helper.
- Dock/Archive stream updates as the canonical confirmation path.

Do not:
- Skip human-thread validation in `setThreadName`.
- Write `params.name` directly into relay card state.
- Add a second client-facing rename notification route.

## 3.3 Reconcile dedupe is optional unless tests prove it is needed

The app-server may emit `thread/name/updated` after `thread/name/set`, so the relay can receive both:
- the explicit post-command invalidation
- the server notification invalidation

Current projection-change suppression prevents duplicate visible title transitions. If command latency improves but background load becomes wasteful, add a small mutation coalescer inside `RelayStateEngine` as a follow-up in this change. Do not introduce it until a test proves duplicate background reconciles are a real problem.

# 4. Implementation Steps

1. Add a relay helper for post-response mutation reconciliation.
   - Name it narrowly, for example `ingestRelayStateMutationAfterResponse`.
   - It should call the existing engine method and catch/log sanitized failures.

2. Change `thread/name/set` route to return after app-server ack.
   - Keep `setThreadName(...)` awaited.
   - Move `handleThreadNameMutation(...)` to fire-and-forget after ack.

3. Add optimistic rename overlay in `DockStore`.
   - Store by `HostScopedThreadID`.
   - Publish immediately before awaiting command.
   - Remove on failure.
   - Clear on canonical match during snapshot publication.

4. Change Dock rename sheet flow to submit and move on.
   - Close the sheet immediately after valid Save.
   - Start `store.rename(...)` in a background `Task`.
   - Remove or minimize `isRenameInFlight` behavior for the Dock sheet.

5. Keep detail toolbar consistent.
   - Detail rename uses the same sheet and save path.
   - `ThreadDetailStore.observeDockRowUpdate(...)` already updates the header when Dock rows change; focused tests must keep this true.

# 5. Test Plan

## 5.1 Relay tests

Add/adjust Node tests in `scripts/dock-relay-card-contract.test.mjs`:
- `thread/name/set responds before slow projection reconciliation finishes`
  - Stub `handleThreadNameMutation` or delay reconciliation.
  - Assert JSON-RPC response returns quickly after fake app-server `thread/name/set`.
  - Assert `dock/update` still arrives later with the renamed title.
- Existing tests must still prove:
  - client `thread/name/set` forwards to app-server
  - server `thread/name/updated` refreshes Dock without client rename
  - command plus notification produces one visible title transition

Run:

```bash
rtk npm run test:relay
```

## 5.2 Swift tests

Update/add tests in `CodexDockTests/DockStoreTests.swift`:
- `testRenamePublishesOptimisticTitleBeforeServerReturns`
  - Use a delayed renamer.
  - Start rename in a task.
  - Assert loaded Dock snapshot shows the submitted title before the renamer completes.
- `testSuccessfulRenameDoesNotManualRefresh`
  - Use a loader that would fail or count extra loads if `refresh()` is called after rename.
  - Assert rename succeeds without a second loader call.
- `testFailedRenameRollsBackOptimisticTitle`
  - Use a failing delayed renamer.
  - Assert title returns to canonical title and `actionError` is set.
- Keep `ThreadDetailStoreTests` passing so open detail header still follows Dock row title updates.

Run:

```bash
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

## 5.3 Simulator proof

Add a controlled simulator proof for client rename latency.

Preferred path:
- Reuse `CodexDockThreadRenameUITests` because it already knows how to open the rename sheet through the Dock row context menu and detail toolbar.
- Add a controlled fixture command/Make target that starts a fake app-server with a known host/thread/title and supplies:
  - `CODEX_DOCK_UI_TEST_HOSTS`
  - `CODEX_DOCK_RENAME_PROOF_HOST_ID`
  - `CODEX_DOCK_RENAME_PROOF_THREAD_ID`
  - `CODEX_DOCK_RENAME_PROOF_ORIGINAL_TITLE`
  - `CODEX_DOCK_RENAME_PROOF_NEW_TITLE`
  - latency budget env vars
- Extend the UI test to record:
  - time from Save tap to sheet dismissal
  - time from Save tap to visible optimistic title
  - time from Save tap to server-confirmed title via the fixture/relay proof
- Fail if sheet dismissal or optimistic title exceeds 1 second in the controlled simulator proof.
- For the latency proof, clear Dock search before opening the context menu.
  - The existing real-thread rename helper searches by title to find the row, which is useful for manual proof but wrong for latency proof because an optimistic title can hide the row from an old-title search.
  - The controlled latency proof must find the target row by stable `AutomationID.Dock.row(hostID:threadID)` and then check the visible row label/title after Save with search still clear.
- Write two separate proof artifacts:
  - UI latency artifact from the UI test: Save tap timestamp, sheet dismissal timestamp, optimistic title visible timestamp, and pass/fail against the latency budget.
  - Relay/fixture artifact from the controlled fake app-server: `thread/name/set` request count, fake app-server title mutation timestamp, `dock/update` canonical title timestamp, route counts, and proof that no raw rename notification was used as a client route.
- Treat the proof as failed unless both artifacts pass:
  - UI artifact proves "submit and move on" and immediate display.
  - Relay/fixture artifact proves canonical server confirmation still arrives through the existing card stream.

Run a concrete proof command, expected shape:

```bash
rtk make sim-ui-client-rename-proof SIM='iPhone 17'
```

If a new Make target is too large, use an equivalent explicit `xcodebuild test-without-building` command only as a temporary proof command and document it in the audit log. The preferred final state is a Makefile-owned proof target.

# 6. Acceptance Checklist

- [x] Plan audit sidecar exists at `docs/THREAD_RENAME_LATENCY_FIX_2026-06-04_PLAN_AUDIT.md`.
- [x] Plan audit verdict is `ready`.
- [x] Client Save no longer waits for relay projection reconciliation.
- [x] Client row title updates optimistically before the command returns.
- [x] Rename editor dismisses immediately after valid Save.
- [x] Successful rename no longer calls `DockStore.refresh()`.
- [x] Failed rename rolls back optimistic title and shows action error.
- [x] Relay `thread/name/set` response is not gated on Dock/Archive reconciliation.
- [x] Canonical server stream still confirms the final title.
- [x] Server-side `thread/name/updated` path remains unified with client rename confirmation.
- [x] `rtk npm run test:relay` passes.
- [x] `rtk swift test --filter DockStoreTests` passes.
- [x] `rtk swift test --filter ThreadDetailStoreTests` passes.
- [x] iPhone 17 simulator proof shows editor dismissal and visible title under the latency budget.
- [x] Simulator proof has separate UI-latency and relay-confirmation artifacts.

# 7. Non-Goals

- Do not persist optimistic titles as local metadata.
- Do not add a phone-side raw `thread/name/updated` route.
- Do not weaken human-thread validation for rename commands.
- Do not change archive behavior unless tests prove the same user-facing latency problem there.
- Do not rewrite the projection engine.

# 8. Risks

## R1 - Optimistic title becomes stale

Mitigation:
- Roll back on command failure.
- Clear when canonical stream matches the submitted title.
- Keep the overlay in memory only.

## R2 - Relay fire-and-forget hides reconciliation failure

Mitigation:
- Log sanitized failure with route, method, and thread hash.
- Keep client command success scoped to app-server acceptance, not stream confirmation.

## R3 - Simulator proof measures test overhead instead of app latency

Mitigation:
- Measure from immediately before Save tap to sheet disappearance and visible title.
- Use a controlled fixture with predictable app-server delay.
- Keep budgets realistic for simulator automation while still proving the old blocking path would fail.
