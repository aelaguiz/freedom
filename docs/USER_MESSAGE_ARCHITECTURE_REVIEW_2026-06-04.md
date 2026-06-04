# User Message Delivery Architecture Plan

Date: 2026-06-04
Repo: `/Users/aelaguiz/workspace/codex-client`
Branch: `codex-dock-agents-tab-live-counts`
Baseline reviewed commit: `1c316fa`
Codex CLI protocol checked with: `codex-cli 0.136.0-alpha.2`

## Verdict

The old architecture is not acceptable for reliable human-message delivery.

The app currently treats a submitted user message as:

```text
text field -> JSON-RPC request -> later projection row, maybe
```

The correct architecture is:

```text
clientUserMessageId -> relay-owned message command -> Codex turn call ->
ThreadItem.userMessage.clientId -> projection reconciliation
```

Net: the client must own the user's local intent, the relay must own delivery
and dedupe, and Codex's `clientUserMessageId` must be the bridge between local
pending UI and canonical history.

## North Star

When Amir taps Send from Codex Dock, the app immediately accepts the message,
clears the composer, shows the submitted user message as pending, and continues
navigation without waiting for Codex. Relay then delivers the message exactly
once per client intent as far as the relay can control, forwards Codex's
`clientUserMessageId`, and reconciles the pending client row with the canonical
Codex `ThreadItem.userMessage.clientId` row when projection catches up.

If the wire, relay, or upstream Codex session fails mid-send, the system must
not pretend the message is definitely lost or blindly send a duplicate. It must
keep the same client message ID, show the status plainly, and retry/reconcile
through the same identity.

## Done-State Requirements

The plan is complete only when all of these are true:

1. Swift generates one `clientUserMessageId` for each user send intent.
2. Swift clears the draft immediately after local acceptance, not after network
   completion.
3. Swift renders a pending outbound user-message row immediately.
4. Swift retries an ambiguous or failed pending message with the same
   `clientUserMessageId`, never by creating a new text-field send.
5. Normal phone sends use relay method `thread/message/send`.
6. Relay owns message delivery state, not the Thread Detail view subscription.
7. Relay persists message command state in the existing relay SQLite database
   at `.codex-dock/relay-state.sqlite`.
8. Relay deduplicates by `(hostID, threadID, clientUserMessageId)`.
9. Relay forwards `clientUserMessageId` to Codex `turn/start` or `turn/steer`.
10. Relay decides start-versus-steer at delivery time.
11. Relay wraps or rejects old phone-facing direct `turn/start` / `turn/steer`
    paths so the app cannot bypass the message command owner.
12. Relay projection exposes Codex `ThreadItem.userMessage.clientId`.
13. Swift canonical rows expose that client ID and merge pending rows by ID,
    not by body text or timestamps.
14. Request-card responses keep their existing server-request identity path and
    are not merged into the user-message command model.
15. Tests prove the identity, pending UI, projection merge, relay dedupe, retry,
    and stale active-turn behavior.
16. Simulator proof shows a real app send is immediately visible and later
    reconciles with canonical projection.

## Non-Requirements

These are intentionally not part of this repair:

- Do not change raw Codex app-server semantics.
- Do not make the iPhone connect directly to raw authenticated app-server
  `:4500`.
- Do not move OpenAI keys or app-server bearer tokens into the app.
- Do not merge request-card responses into the human-message send model.
- Do not add a generic job framework, queue runner, or background worker
  platform.
- Do not introduce a second persistence system outside the existing relay state
  SQLite database.
- Do not make text-body matching a fallback reconciliation strategy.

## Hard Constraints

- Codex's generated protocol uses `clientUserMessageId` on `turn/start` and
  `turn/steer`.
- Codex history stores the value as `ThreadItem.userMessage.clientId`.
- Swift app diagnostics must not log prompt text, transcript text, full
  JSON-RPC payloads, bearer tokens, or `OPENAI_API_KEY`.
- Relay diagnostics must use `scripts/dock-relay-logger.mjs`, not direct
  `console.error`.
- Production timing and port constants stay in
  `CodexDock/Configuration/CodexDockConstants.swift` and
  `scripts/dock-relay-constants.mjs`.
- Mobile app build/install/test flows are Makefile-owned.

## Non-Constraints

- The app does not need to wait for network completion before clearing the
  draft.
- The relay does not need a new database; it already has
  `.codex-dock/relay-state.sqlite`.
- The client does not need to know whether the send becomes `turn/start` or
  `turn/steer`.
- The first correct UI state does not need to be canonical. It only needs a
  stable client ID and a clear pending status.
- Old relay `turn/start` / `turn/steer` routes do not need to remain the normal
  phone-facing send API.

## Current Code Truth

### Swift Send Path

Current `ComposerView` starts an async send task directly:

- `CodexDock/Features/Session/ComposerView.swift:117`

Current `ThreadDetailStore.sendDraft()`:

- reads `composer.draft`
- sets `composer.isSending = true`
- calls `ClientCommandEngine.sendDraft(...)`
- clears `composer.draft` only after the JSON-RPC call succeeds
- has no pending outbound message model

Anchors:

- `CodexDock/State/ThreadDetailStore.swift:362`
- `CodexDock/State/ThreadDetailStore.swift:386`
- `CodexDock/State/ThreadDetailStore.swift:395`

Current `ClientCommandEngine.sendDraft(...)` chooses `turn/steer` when Swift
has `activeTurnID`, otherwise `turn/start`:

- `CodexDock/Commands/ClientCommandEngine.swift:57`

Current Swift `TurnStartParams` and `TurnSteerParams` omit
`clientUserMessageId`:

- `CodexDock/AppServer/TurnDTO.swift:21`
- `CodexDock/AppServer/TurnDTO.swift:43`

### Swift Projection And Render Path

`ThreadDetailStore.applyProjectionSnapshot(...)` replaces local events from
projection rows and records `activeTurnID` from the projection:

- `CodexDock/State/ThreadDetailStore.swift:617`

`ThreadDetailRenderProjector` renders only projection rows:

- `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift:3`

`ThreadDetailEventDTO` exposes `turnID` and `itemID`, but no Codex client ID:

- `CodexDock/AppServer/ThreadDetailDTO.swift:141`
- `CodexDock/AppServer/ThreadDetailDTO.swift:199`

### Relay Send Path

Relay `thread/detail/subscribe` resumes an upstream session:

- `scripts/dock-relay.mjs:613`
- `scripts/dock-relay.mjs:270`

Relay currently forwards `turn/start`, `turn/steer`, and `turn/interrupt`
through that active upstream:

- `scripts/dock-relay.mjs:809`
- `scripts/dock-relay.mjs:878`

Relay upstream recovery closes the phone WebSocket with
`1012 "upstream recovered; rehydrate"`:

- `scripts/dock-relay.mjs:740`
- `scripts/dock-relay.mjs:773`

That is good stream recovery, but weak message delivery.

### Relay State Store Pattern

The relay already has a canonical SQLite state store:

- `scripts/dock-relay-state-store.mjs:150`

It creates tables in `RelayStateStore.migrate()` and uses a synchronous
transaction helper:

- `scripts/dock-relay-state-store.mjs:163`
- `scripts/dock-relay-state-store.mjs:453`

This is the correct persistence owner for message commands.

### Codex Protocol Reality

Generated Codex protocol includes `clientUserMessageId`:

- `/tmp/codex-client/user-message-architecture-schema-20260604/ts/v2/TurnStartParams.ts:16`
- `/tmp/codex-client/user-message-architecture-schema-20260604/ts/v2/TurnSteerParams.ts:7`

Generated Codex `ThreadItem` stores it as `clientId`:

- `/tmp/codex-client/user-message-architecture-schema-20260604/ts/v2/ThreadItem.ts:26`

Codex `turn/steer` requires the expected turn to match the current active turn:

- `/tmp/codex-client/user-message-architecture-schema-20260604/ts/v2/TurnSteerParams.ts:16`

## Target Architecture

### Owner Chain

There is one normal human-message send path:

```text
ComposerView
  -> ThreadDetailStore.submitDraftLocally()
  -> PendingOutboundMessage
  -> AppServerClient.threadMessageSend(...)
  -> relay thread/message/send
  -> RelayUserMessageCommandEngine
  -> RelayStateStore.outbound_user_messages
  -> Codex turn/start or turn/steer with clientUserMessageId
  -> relay thread-detail projection with clientId
  -> ThreadDetailStore canonical merge
```

Ownership rules:

- `ThreadDetailStore` owns local pending user intent and render merge.
- `ComposerState` owns only the editable draft and voice state.
- `ClientCommandEngine` owns Swift command calls, but not message delivery
  state.
- `RelayUserMessageCommandEngine` owns delivery, route selection, dedupe,
  retry classification, and stale-turn fallback.
- `RelayStateStore` owns durable command rows.
- Codex owns canonical thread history.
- Projection owns canonical rows and includes `clientId`.

### Client Message ID

Swift creates a string ID with this shape:

```text
dock-msg:<uuid-v4>
```

Rules:

- One ID per user send intent.
- Retrying the same pending message reuses the same ID.
- Sending the same text twice intentionally creates two IDs.
- The ID is safe to log because it contains no prompt text.
- The ID is not the JSON-RPC request ID.

### Swift Pending Message Model

Add a focused model, preferably near Thread Detail state:

```swift
public struct ClientUserMessageID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
}

public enum OutboundMessageDeliveryState: Equatable, Sendable {
    case pendingLocal
    case acceptedByRelay
    case submittedUpstream
    case canonicalObserved
    case failedDefinite(String)
    case failedAmbiguous(String)
}

public struct PendingOutboundMessage: Identifiable, Equatable, Sendable {
    public let id: ClientUserMessageID
    public let threadID: String
    public let input: [TurnUserInputDTO]
    public let createdAt: Date
    public var deliveryState: OutboundMessageDeliveryState
    public var canonicalTurnID: String?
    public var canonicalItemID: String?
}
```

Render rule:

```text
visible rows =
  canonical projection rows
  + pending outbound rows whose clientUserMessageId is not present in canonical rows
```

Ordering rule:

- Pending rows use `createdAt` as activity time.
- Canonical rows keep projection order.
- If a canonical row has matching `clientId`, it replaces the pending row.

Filter rule:

- Pending outbound rows are `ThreadEventKind.userMessage`.
- They participate in the same message filters as canonical user messages.

Composer rule:

- `ComposerState.isSending` must no longer mean "the whole composer is blocked
  while one message is in flight."
- The send button may briefly protect against double-submitting the exact same
  draft during local acceptance, but network delivery must continue in the
  background.
- Voice capture remains blocked while voice is busy.

### Swift Wire DTOs

Add `clientUserMessageId` to existing turn DTOs for compatibility and raw
Codex pass-through:

```swift
public struct TurnStartParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let clientUserMessageId: String?
    public let input: [TurnUserInputDTO]
}

public struct TurnSteerParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let clientUserMessageId: String?
    public let input: [TurnUserInputDTO]
    public let expectedTurnId: String
}
```

Add the normal phone-facing relay command:

```swift
public struct ThreadMessageSendParams: Codable, Equatable, Sendable {
    public let threadId: String
    public let clientUserMessageId: String
    public let input: [TurnUserInputDTO]
}

public struct ThreadMessageSendResponseDTO: Codable, Equatable, Sendable {
    public let clientUserMessageId: String
    public let state: String
    public let turnId: String?
    public let itemId: String?
    public let error: String?
}
```

### Relay Phone-Facing API

Normal app sends call:

```json
{
  "method": "thread/message/send",
  "params": {
    "threadId": "thread-1",
    "clientUserMessageId": "dock-msg:...",
    "input": [
      { "type": "text", "text": "Run tests", "text_elements": [] }
    ]
  }
}
```

Response shape:

```json
{
  "clientUserMessageId": "dock-msg:...",
  "state": "submittedUpstream",
  "turnId": "turn-1",
  "itemId": null,
  "error": null
}
```

Allowed states:

- `acceptedByRelay`
- `submittedUpstream`
- `canonicalObserved`
- `failedDefinite`
- `failedAmbiguous`

### Relay Persistent Command Table

Add this table to `RelayStateStore.migrate()`:

```sql
CREATE TABLE IF NOT EXISTS outbound_user_messages (
  host_id TEXT NOT NULL,
  thread_id TEXT NOT NULL,
  client_user_message_id TEXT NOT NULL,
  input_json TEXT NOT NULL,
  input_hash TEXT NOT NULL,
  state TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  upstream_endpoint_url TEXT,
  upstream_method TEXT,
  upstream_request_id TEXT,
  codex_turn_id TEXT,
  codex_item_id TEXT,
  last_error_code TEXT,
  last_error_message TEXT,
  PRIMARY KEY (host_id, thread_id, client_user_message_id)
);
```

Store API:

- `upsertOutboundUserMessageAccepted(command)`
- `markOutboundUserMessageSubmitted(command, result)`
- `markOutboundUserMessageCanonicalObserved(command, canonicalRef)`
- `markOutboundUserMessageFailed(command, failure)`
- `outboundUserMessageForClientID(hostID, threadID, clientUserMessageID)`

Idempotency rule:

- Same `(hostID, threadID, clientUserMessageId)` and same `input_hash`: return
  current command state.
- Same key and different `input_hash`: reject with client ID collision.

### Relay Delivery Engine

Add `scripts/dock-relay-user-message-command.mjs`.

Responsibilities:

1. Validate `threadId`, `clientUserMessageId`, and `input`.
2. `assertHumanThreadID(config, threadId)`.
3. Insert or read command in `RelayStateStore`.
4. If the command is already `submittedUpstream` or `canonicalObserved`, return
   stored status.
5. Resolve route using the current active detail upstream when it matches the
   thread, otherwise use `SessionRouter.endpointForThread(threadId)`.
6. Choose `turn/steer` only when the matched active session has a current
   active turn ID.
7. On stale-turn precondition failure, retry as `turn/start` with the same
   `clientUserMessageId`.
8. On upstream timeout or socket loss after a send attempt, mark
   `failedAmbiguous`.
9. On validation or definite Codex rejection, mark `failedDefinite`.
10. Return command status to Swift.

The engine must not log input text.

### Old Route Convergence

The relay must close the old side door:

- Normal Swift sends stop calling phone-facing `turn/start` / `turn/steer`.
- Relay `turn/start` and `turn/steer` with `clientUserMessageId` are wrapped
  through the command owner for compatibility.
- Relay `turn/start` and `turn/steer` without `clientUserMessageId` are rejected
  with a typed relay error telling the caller to use `thread/message/send`.
- Raw Codex app-server still supports its own protocol; this rule applies to
  phone-facing relay routes.

### Projection Contract

Relay projection must carry Codex `ThreadItem.userMessage.clientId`.

Projection payload adds:

```js
clientID: item.clientId || null
```

Swift DTO adds the matching field. Use one wire spelling and test it. The plan
prefers `clientID` to match existing `turnID` / `itemID` DTO style.

When relay projection observes a userMessage with `clientId`, the relay also
marks the matching outbound command `canonicalObserved` in `RelayStateStore`.

### Failure Semantics

| Failure | State | User-visible behavior | Retry behavior |
| --- | --- | --- | --- |
| Local empty draft | no command | Nothing changes | No retry |
| Relay validation fails before upstream send | `failedDefinite` | Pending row shows failed | Retry creates a new command only if user edits/resubmits |
| Duplicate same ID and same input | existing state | Existing pending/canonical row remains | No new upstream call |
| Duplicate same ID and different input | `failedDefinite` collision | Pending row shows failed | No automatic retry |
| Upstream timeout after send attempt | `failedAmbiguous` | Pending row shows ambiguous/retryable | Retry same ID after checking existing command state |
| Downstream socket closes during send | `failedAmbiguous` or existing stored state | Pending row survives locally | Reconnect/resync reconciles by same ID |
| Stale active turn on steer | internal fallback | User should not see failure | Retry as `turn/start` with same ID |
| Canonical row arrives later | `canonicalObserved` | Pending row becomes normal canonical row | No retry |

## Depth-First Implementation Plan

### Phase 1 - Identity Crosses The Whole Seam

Goal: one message ID moves from Swift to relay to Codex params to projection
DTO shape through the final owner path. This phase must introduce the real
`RelayUserMessageCommandEngine`; it must not add a temporary relay send path
that Phase 3 replaces later.

Work:

1. Add Swift `clientUserMessageId` fields to turn DTOs.
2. Add `ThreadMessageSendParams` / `ThreadMessageSendResponseDTO`.
3. Add `AppServerMethods.threadMessageSend = "thread/message/send"`.
4. Add `RelayUserMessageCommandEngine` with the store-backed accept, dedupe,
   route, and upstream-submit path.
5. Add relay `thread/message/send` handler that delegates to that engine.
6. Add projection `clientID`.
7. Add Swift DTO `clientID`.
8. Add tests proving all fields encode/decode/pass through.

Exit proof:

```bash
rtk swift test --filter AppServerClientTests
rtk npm run test:relay
```

### Phase 2 - Client Pending Row And Non-Blocking Send

Goal: tapping Send is immediate and visible before projection catches up.

Work:

1. Add `PendingOutboundMessage`.
2. `ThreadDetailStore.sendDraft()` becomes local accept plus background
   delivery.
3. Draft clears immediately after pending row creation.
4. Render merges pending rows with canonical projection rows by `clientID`.
5. Composer no longer stays globally blocked for network delivery.
6. Add retry for `failedAmbiguous` using the same ID.

Exit proof:

```bash
rtk swift test --filter ThreadDetailStoreTests
```

Tests must cover:

- pending row appears immediately
- canonical row with matching `clientID` replaces pending row
- repeated identical text creates separate IDs
- retry uses the same ID
- send does not wait for network completion before clearing draft

### Phase 3 - Relay Delivery Ownership And Side-Door Closure

Goal: harden the relay owner added in Phase 1 so no normal app path can bypass
it and ambiguous delivery cases have typed states.

Work:

1. Route via active detail upstream when safe, or endpoint router otherwise.
2. Keep start-versus-steer decision inside relay for all normal phone sends.
3. Add stale-turn fallback from steer to start.
4. Wrap/reject old relay `turn/start` and `turn/steer` side doors.
5. Mark commands `canonicalObserved` from projection rows.
6. Add recovery classification for upstream close after an attempted send.

Exit proof:

```bash
rtk npm run test:relay
rtk swift test --filter AppServerClientTests
rtk swift test --filter ThreadDetailStoreTests
```

Relay tests must cover:

- duplicate same ID/same input does not re-forward upstream
- duplicate same ID/different input fails
- old no-ID relay `turn/start` / `turn/steer` reject
- wrapper route with ID uses command owner
- upstream close after attempt is ambiguous, not definite
- stale steer falls back to start with same ID

### Phase 4 - Simulator Proof

Goal: real installed simulator app proves the user-facing behavior.

Run:

```bash
rtk make services
rtk make app SIM='iPhone 17' FORCE_LAUNCH=1
```

Proof requirements:

- Send from Thread Detail.
- Draft clears immediately.
- Pending user row appears immediately.
- App remains navigable while relay/Codex responds.
- Canonical projection replaces pending row.
- No duplicate row appears after resync.

### Phase 5 - Review, Commit, Deploy

1. Run `$plan-audit` implementation-audit mode against the implemented code and
   this plan.
2. Run `$thermo-nuclear-code-quality-review`.
3. Repair any blockers.
4. Run final focused tests and simulator proof if repairs touched behavior.
5. Commit explicit paths.
6. Push the branch.
7. Pull latest on `home`.
8. Restart local and home relays.
9. Verify both relay statuses.

## Side Doors To Close

- Swift `ThreadDetailStore` must not call `turn/start` or `turn/steer` for
  normal human sends.
- Relay phone-facing `turn/start` and `turn/steer` must not keep accepting
  anonymous no-ID user sends.
- Projection must not drop `clientId`.
- Tests must not keep asserting "no row after send until projection arrives."
- Docs must not describe failed user sends as merely unreplayed without also
  describing the pending command identity.

## Proof Matrix

| Requirement | Proof |
| --- | --- |
| Swift encodes `clientUserMessageId` | `rtk swift test --filter AppServerClientTests` |
| Relay forwards and dedupes IDs | `rtk npm run test:relay` |
| Projection carries `clientID` | relay projection/ledger tests and Swift DTO tests |
| Pending UI is immediate | `rtk swift test --filter ThreadDetailStoreTests` |
| Non-blocking send behavior | `ThreadDetailStoreTests` plus simulator proof |
| Stale steer fallback | relay command tests |
| Old side door closed | relay route tests |
| Real app behavior | `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1` plus simulator interaction proof |

## Architecture Quality Bar

This plan should be rejected if the implementation:

- adds a second relay persistence system
- makes Swift choose start-versus-steer for normal sends
- matches pending rows by message body
- leaves no-ID relay `turn/start` / `turn/steer` as a normal phone-facing send
  path
- blocks the composer until network completion
- creates generic queue infrastructure instead of a small user-message command
  owner
- logs prompt text, transcript text, full JSON-RPC payloads, bearer tokens, or
  `OPENAI_API_KEY`
- leaves duplicate tests/docs teaching the old "projection only after send"
  behavior as desired
