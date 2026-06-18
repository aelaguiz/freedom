# Codex Dock Check State Audit

Date: 2026-06-06
Status: audit only, no implementation
Scope: user-message delivery state shown as `Check` in Thread Detail

## Direct Answer

`Check` is the current Swift UI label for `failedAmbiguous`.

It exists because the app and relay sometimes cannot prove whether a submitted
message reached Codex. That uncertainty can be real in a networked write path,
but the current `Check` badge is a bad user-facing state: it is vague, it can be
terminal, and the current code overuses it for errors that are actually
definite.

Net: an internal uncertainty state is still useful, but a permanent visible
`Check` state should not be the normal product behavior. With a stronger relay
outbox, queryable command status, mandatory `clientUserMessageId`
reconciliation, and better Swift error handling, the user should usually see
`Sending`, `Sent`, or a concrete `Failed`, not `Check`.

Follow-up architecture audit:
`docs/CODEX_DOCK_THREAD_CONTROL_ARCHITECTURE_AUDIT_2026-06-06.md`.

That deeper audit supersedes any framing that this is mainly a UX-label issue.
The underlying architecture problem is that Dock can show threads that are
history-readable or private-runtime-visible but not actually controllable from
the phone.

## Why This Audit Exists

Manual testing showed sent messages appearing with a `Check` badge and then not
going through. That is a bad journey for two separate reasons:

- `Check` does not tell the user what happened.
- The state appears to get stuck instead of reconciling to `Sent` or a concrete
  failure.

This document audits why that happens end to end and what the better intended
approach should be. It intentionally does not implement fixes.

## Current User-Visible Symptom

The user writes text in Thread Detail, taps Send, sees a pending user-message
row, and then the row gets a yellow `Check` badge.

From the user's point of view, `Check` can mean any of these today:

- The phone timed out waiting for the relay.
- The relay timed out or lost transport while sending to Codex.
- The relay returned an ambiguous delivery result.
- The relay returned a definite server error, but Swift flattened it into
  ambiguous state.
- The message might actually have reached Codex, but projection did not
  reconcile it.
- The message definitely could not be sent, but the UI did not preserve that
  reason as a concrete `Failed` state.

That is too many meanings for one tiny word.

## Current State Names

The current delivery states live in
`CodexDock/ThreadDetail/OutboundUserMessage.swift`:

| Swift state | Current label | Meaning today |
| --- | --- | --- |
| `pendingLocal` | `Pending` | Swift accepted Send locally and created a pending row. |
| `acceptedByRelay` | `Accepted` | The relay persisted or deduped the command. |
| `submittedUpstream` | `Sending` | The relay submitted to upstream Codex or has upstream delivery evidence. |
| `canonicalObserved` | `Sent` | The canonical projection showed the same `clientUserMessageId`. |
| `failedDefinite` | `Failed` | Delivery failed in a way considered safe to present as failed. |
| `failedAmbiguous` | `Check` | Delivery is uncertain. |

The problem is not just the word `Check`. The problem is that
`failedAmbiguous` is used as a terminal bucket for too many cases.

## Current Send Path

The current send flow is:

1. `ThreadDetailStore.sendDraftInBackground()` validates the draft.
2. Swift creates `ClientUserMessageID.make()`, shaped like
   `dock-msg:<uuid-v4>`.
3. Swift inserts a `PendingOutboundMessage` with state `pendingLocal`.
4. Swift clears the composer.
5. Swift calls `thread/message/send` through `ClientCommandEngine`.
6. The relay handles `thread/message/send` in
   `scripts/dock-relay-user-message-command.mjs`.
7. The relay persists the command in `outbound_user_messages` as
   `acceptedByRelay`.
8. The relay chooses upstream `turn/steer` when it sees an active turn,
   otherwise `turn/start`.
9. On stale active-turn steering errors, the relay falls back from
   `turn/steer` to `turn/start`.
10. On upstream success, the relay marks the row `submittedUpstream`.
11. When detail projection later contains a user-message row with matching
    `payload.clientID`, the relay marks `canonicalObserved`.
12. Swift also prunes its pending row when a canonical `ThreadEvent.clientID`
    matches the pending `clientUserMessageId`.

The intended identity key is `clientUserMessageId`. Message body and timestamp
are not supposed to be used for reconciliation.

## Why `Check` Exists

There is a real distributed-systems problem underneath this:

1. The phone sends a command.
2. The relay may receive and persist it.
3. The relay may send it upstream to Codex.
4. Codex may accept it.
5. The connection may close before the response reaches the phone or relay.

At that moment, the sender cannot know from the broken request alone whether
Codex accepted the message. Retrying blindly could duplicate the user's message.

That is why an internal uncertainty concept exists. The current relay already
tries to avoid duplicates by requiring `clientUserMessageId` and deduping
commands in `outbound_user_messages`.

But the current app should not stop at `Check`. Once there is a stable
`clientUserMessageId`, the better behavior is to reconcile by command id until
the system can prove `Sent` or prove `Failed`.

## Places That Create `Check`

### 1. Relay Returns `failedAmbiguous`

In `scripts/dock-relay-user-message-command.mjs`, the relay classifies errors
with `ambiguousDeliveryError(error)`.

It returns ambiguous when the error message includes:

- `timed out`
- `websocket closed`
- `socket`
- `transport`
- `not connected`

For those cases, the relay marks the durable row `failedAmbiguous` and returns
a normal command response. Swift maps that response to `failedAmbiguous`, which
the UI labels `Check`.

This is a real uncertainty case when the relay cannot tell whether upstream
Codex saw the request.

### 2. Swift Converts Any Thrown Send Error To `failedAmbiguous`

In `ThreadDetailStore.deliverPendingOutboundMessage(...)`, any thrown error from
`commandEngine.sendUserMessage(...)` goes to
`handlePendingOutboundMessageFailed(...)`.

That method always does this:

```swift
pendingMessage.deliveryState = .failedAmbiguous(message)
```

This is too broad.

If the relay throws a definite JSON-RPC error with command data, Swift still
labels it `Check`. That means a concrete failure can become a vague uncertainty
badge.

### 3. Definite Relay Errors Can Be Lost In Swift

The relay marks some errors `failedDefinite` and throws a JSON-RPC error with
`data.command`.

Example from live local relay state on 2026-06-06:

| State | Error code | Error message |
| --- | --- | --- |
| `failedDefinite` | `-32020` | `thread ... is owned by a private Codex runtime` |

That is not ambiguous. It means the phone-facing relay could not send to that
private runtime path.

But because Swift does not inspect `AppServerClientError.server(error).data`,
the visible app row can still become `Check` when that error is thrown through
the send task.

## Current Reconciliation Behavior

Reconciliation exists, but it is incomplete.

### What Works

The relay calls `markCanonicalRows(rows)` when a detail snapshot or update
contains rows with `payload.clientID`.

Swift prunes pending outbound messages when canonical `ThreadEvent.clientID`
matches the pending `clientUserMessageId`.

That means the good path works when all of these are true:

- Codex accepts `clientUserMessageId`.
- Projection includes the resulting user-message row.
- The projected row includes the same client id.
- Swift receives the projection update or resync result.

Local relay state on 2026-06-06 showed three prior messages in
`canonicalObserved`, so the identity-based path can work.

### What Does Not Work Enough

The failure path does not actively reconcile.

On successful command response, Swift calls:

```swift
await reconciler?.commandCompletedInvalidation()
```

On thrown send failure, Swift marks `failedAmbiguous`, but does not call that
same invalidation path. If the failure was a timeout or transport loss after
Codex accepted the message, the app should aggressively resync by
`clientUserMessageId`; instead, it can leave the row sitting at `Check`.

Also, the relay has durable outbound command state, but Thread Detail does not
currently appear to load that durable command state as part of the normal
detail snapshot. Swift pending rows are phone-local/in-memory. The command
state lives in relay SQLite, but the app does not have a clear `get message
delivery status by client id` recovery surface.

## Current Relay State Evidence

Checked local Mac relay SQLite table `.codex-dock/relay-state.sqlite` on
2026-06-06, without reading message bodies:

| State | Count |
| --- | --- |
| `canonicalObserved` | 3 |
| `failedDefinite` | 1 |

The recent `failedDefinite` row was a private-runtime-owner failure:

```text
thread ... is owned by a private Codex runtime
```

Checked `home` relay SQLite table on 2026-06-06; `outbound_user_messages`
appeared empty at the time of audit.

Both relays were otherwise health-check `ready`:

- `amir-m5.fairy-salmon.ts.net:4510`
- `home.fairy-salmon.ts.net:4510`

This evidence points to a likely current user-visible failure mode:

- The relay may know a send failed definitely.
- Swift may still show `Check`.
- Or Swift may have a local pending row that cannot recover from relay state.

## Is `Check` Absolutely Necessary?

As a user-visible terminal state: no.

As an internal temporary concept: yes, unless Codex and the relay can provide a
strict end-to-end delivery receipt for every send.

The distinction matters:

- If the transport fails after a write, uncertainty is real.
- If the app has a stable idempotency key and a queryable relay outbox, the user
  should not have to live in uncertainty.
- If Codex always persists `clientUserMessageId` and exposes projection/status
  by that id, the app can usually resolve uncertainty automatically.
- If Codex does not expose any receipt and the projection never returns the
  client id, some internal uncertainty remains unavoidable.

So the better question is not "can uncertainty exist?" It can. The better
question is "does the user need to see `Check` as the final answer?" Usually
no.

## What Would Remove The Need For User-Visible `Check`

The app can avoid visible terminal `Check` if these contracts are true:

1. Every user send has a stable `clientUserMessageId`.
2. The relay persists that id before attempting upstream delivery.
3. The relay can retry or reconcile the same id without creating a duplicate.
4. Codex accepts the id and treats duplicate ids idempotently, or at least
   echoes the id in canonical projection.
5. The relay exposes command status to the phone after the original request
   times out or disconnects.
6. Thread Detail resync includes enough pending outbound command state to
   recover after app restart, reconnect, or view reopen.
7. Projection rows always include `clientID` for phone-submitted user messages.
8. Definite errors stay definite all the way to the UI.

The current repo has pieces of this already:

- Swift creates `clientUserMessageId`.
- Relay persists an outbound command row before upstream delivery.
- Relay dedupes same id and input hash.
- Relay can mark canonical rows when projection includes `payload.clientID`.
- Swift prunes pending rows by `clientID`.

The missing pieces are:

- A phone-visible command-status recovery route or detail snapshot field.
- Failure-path resync from Swift.
- Better parsing of relay JSON-RPC error `data.command`.
- A non-vague UI label and action model.
- Strong proof that Codex projection always returns `clientID`.
- Tests for ambiguous transport failure followed by canonical reconciliation.

## Better Product Model

The product should not use `Check` as a normal terminal badge.

Recommended user-facing states:

| Better UI state | Meaning |
| --- | --- |
| `Pending` | The phone accepted the message locally. |
| `Sending` | The relay owns the command or is sending/reconciling it. |
| `Sent` | Canonical projection contains the matching `clientUserMessageId`. |
| `Failed` | The system knows the message did not go through or cannot go through. |
| `Delivery uncertain` | Rare fallback after reconciliation attempts fail; must include explanation and action. |

`Delivery uncertain` should be a rare expanded state, not a small `Check`
badge. It should say something like:

```text
Delivery is uncertain. The relay is checking whether Codex received this.
Do not send a duplicate unless you mean to.
```

For definite failures, examples should be concrete:

```text
Cannot send from phone: this thread is owned by a private Codex runtime.
```

```text
Cannot send: relay is offline.
```

```text
Cannot send: this message id was already used for different text.
```

## Better Technical Model

### 1. Relay-Owned Outbox

Make the relay outbox authoritative for submitted messages.

The phone should create a local pending row immediately, but after that the
relay should own command status:

- `acceptedByRelay`
- `deliveringUpstream`
- `submittedUpstream`
- `reconcilingProjection`
- `canonicalObserved`
- `failedDefinite`
- `deliveryUncertain`

The phone should be able to re-open Thread Detail and recover these states from
the relay.

### 2. Fast Relay Ack, Async Delivery

The phone request should not need to wait for Codex's full upstream behavior.

A better flow:

1. Phone sends `thread/message/send`.
2. Relay persists the command.
3. Relay immediately returns `acceptedByRelay`.
4. Relay delivers upstream in the background.
5. Relay emits command-status updates or includes pending command status in
   Thread Detail projection.
6. Canonical projection resolves the row to `Sent`.

This removes the 120-second phone request as the main source of truth.

### 3. Mandatory Reconcile By `clientUserMessageId`

Every uncertain delivery should trigger a reconciliation loop:

1. Query projection for the thread.
2. Look for matching `payload.clientID`.
3. If found, mark `canonicalObserved`.
4. If not found and upstream definitely failed before send, mark
   `failedDefinite`.
5. If not found but upstream might have received it, keep reconciling with a
   clear timeout/backoff policy.

Do not merge by text.

### 4. Preserve Definite Errors

Swift should distinguish:

- Relay command response says `failedAmbiguous`.
- Relay command response says `failedDefinite`.
- JSON-RPC error includes `data.command.state = failedDefinite`.
- JSON-RPC error is pure transport timeout/disconnect.
- Swift client cannot send because the thread session is not connected.

Only the true transport-uncertain cases should become internal uncertainty.

### 5. Queryable Command Status

The relay should expose one of these:

- Include pending outbound command rows in `thread/detail/subscribe` and
  `thread/detail/resync`.
- Add a route like `thread/message/status` keyed by `threadId` and
  `clientUserMessageId`.
- Emit `thread/message/status` notifications on the existing detail connection.

The app needs some way to recover after the original send request times out,
the WebSocket reconnects, or the view closes.

### 6. Codex Receipt Upgrade

If Codex can be upgraded, the ideal upstream contract is:

- `turn/start` and `turn/steer` accept `clientUserMessageId`.
- They return a durable accepted receipt quickly.
- Repeating the same id and same input returns the same receipt, not a
  duplicate turn/message.
- Repeating the same id with different input returns a collision error.
- `thread/detail` projection always includes the id on the canonical
  user-message row.
- A status/read route can answer "what happened to client id X?"

With that contract, the app does not need user-visible terminal `Check`.

## Likely Root Causes For "Check And Never Goes Through"

Based on the code and current relay state, the most likely causes are:

1. **Swift over-flattens failures.** A definite relay error becomes
   `failedAmbiguous`, so the user sees `Check`.
2. **Failure path does not trigger resync.** A timeout/transport failure after
   upstream acceptance can remain unresolved.
3. **No phone-visible durable command status.** Relay SQLite knows more than the
   app can reload.
4. **Projection may not contain `clientID`.** If Codex or the adapter drops the
   id, pending rows cannot merge.
5. **Private runtime ownership blocks send.** The relay can know this
   definitely, but the app may present it ambiguously.
6. **The label is bad.** Even when uncertainty is real, `Check` is not
   self-explanatory.

## Test Coverage Gaps

Current tests cover:

- Swift creates a pending row immediately.
- Swift submits through `thread/message/send`.
- Relay dedupes the same `clientUserMessageId`.
- Relay falls back from stale `turn/steer` to `turn/start`.
- Canonical projection with matching `clientID` prunes the pending row.

Missing or weak tests:

- Relay ambiguous transport failure followed by later canonical projection.
- Swift thrown server error with `data.command.state = failedDefinite`.
- Private runtime send failure should render concrete `Failed`, not `Check`.
- Send timeout should trigger projection resync/reconcile.
- App reload should recover relay outbox command state.
- Projection row without `clientID` should become a named reconciliation
  failure, not silent forever-`Check`.
- Real relay-backed simulator proof that a sent user message never leaves a
  terminal `Check` badge without a concrete explanation.

## Decision

Keep an internal uncertainty concept.

Do not keep `Check` as the normal user-facing final state.

The target behavior should be:

- A message stays `Sending` while the system is actively reconciling.
- It becomes `Sent` when canonical projection confirms the client id.
- It becomes `Failed` when the system has a concrete failure reason.
- It shows `Delivery uncertain` only when reconciliation is exhausted and the
  system truly cannot know whether Codex accepted the message.

The product should treat terminal uncertainty as an exception requiring an
explanation, not as a one-word badge.

## Recommended Plan, Still Not Implemented

1. Rename the user-visible `Check` label to `Delivery uncertain` immediately in
   product intent.
2. Teach Swift to parse relay command state from thrown JSON-RPC errors.
3. On any send failure or timeout, trigger Thread Detail resync before settling
   the visible state.
4. Add relay command-status recovery in Thread Detail snapshots or a dedicated
   status route.
5. Add relay background reconciliation for uncertain rows.
6. Add proof that Codex projection preserves `clientUserMessageId`.
7. Add tests for the missing coverage gaps above.
8. Only after those are in place, consider removing visible terminal
   uncertainty from normal UI.

## Files Read

- `CodexDock/ThreadDetail/OutboundUserMessage.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/Features/Session/ThreadMessageListView.swift`
- `CodexDock/Commands/ClientCommandEngine.swift`
- `CodexDock/AppServer/AppServerClient.swift`
- `CodexDock/AppServer/TurnDTO.swift`
- `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`
- `scripts/dock-relay-user-message-command.mjs`
- `scripts/dock-relay-outbound-user-message-store.mjs`
- `scripts/dock-relay.mjs`
- `scripts/dock-relay-thread-detail-projection-adapter.mjs`
- `CodexDockTests/ThreadDetailStoreTests.swift`
- `scripts/dock-relay-user-message-command.test.mjs`
- `docs/CODEX_DOCK_CANONICAL_USER_JOURNEY.md`
- `.codex-dock/relay-state.sqlite`
- `/home/aelaguiz/workspace/codex-client/.codex-dock/relay-state.sqlite`

## Commands Run

```bash
rtk rg -n "\bCheck\b|failedAmbiguous|failedDefinite|pendingLocal|acceptedByRelay|submittedUpstream|canonicalObserved|OutboundMessageDeliveryState|clientUserMessageId|thread/message/send" CodexDock CodexDockTests scripts package.json Package.swift Makefile
rtk rg -n "ambiguous|delivery is uncertain|Message delivery|thread/message/send|turn/start|turn/steer|clientUserMessageId" scripts CodexDock CodexDockTests docs/CODEX_DOCK_CANONICAL_USER_JOURNEY.md
rtk sqlite3 -header -column .codex-dock/relay-state.sqlite "SELECT state, COUNT(*) AS count FROM outbound_user_messages GROUP BY state ORDER BY state; SELECT substr(client_user_message_id,1,22) AS client_id_prefix, state, upstream_method, codex_turn_id IS NOT NULL AS has_turn, codex_item_id IS NOT NULL AS has_item, last_error_code, last_error_message, created_at, updated_at FROM outbound_user_messages ORDER BY updated_at DESC LIMIT 20;"
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && sqlite3 -header -column .codex-dock/relay-state.sqlite "SELECT state, COUNT(*) AS count FROM outbound_user_messages GROUP BY state ORDER BY state; SELECT substr(client_user_message_id,1,22) AS client_id_prefix, state, upstream_method, codex_turn_id IS NOT NULL AS has_turn, codex_item_id IS NOT NULL AS has_item, last_error_code, last_error_message, created_at, updated_at FROM outbound_user_messages ORDER BY updated_at DESC LIMIT 20;"'
rtk make dock-relay-status
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make dock-relay-status HOST_SERVICE_PLATFORM=linux NODE_BIN=/home/aelaguiz/.local/bin/node'
```
