# Codex Dock Thread Detail Outbound Duplicate Root Cause

Date: 2026-06-01

Status: local single-host implementation proof complete under the active
2026-06-01 goal; default two-host proof remains blocked until `home` is updated.
This doc began as the root-cause audit plus zero-sunk-cost permanent
architecture proposal for eliminating display identity drift as a class of
bugs. The architecture passed plan review, implementation audit, Composer 2.5
Fast fresh consult, thermonuclear maintainability review, and local-host
iPhone 17 simulator proof. Default two-host proof is not accepted yet because
`home.fairy-salmon.ts.net:4510` still needs the same relay deployment as
`amir-m5.fairy-salmon.ts.net:4510`.

Related:

- `docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md`
  is the 2026-06-02 model-consensus plan that tightens this doc's broader
  architecture into a finish-the-cutover plan and explicitly rejects overbuilt
  pending/optimistic machinery.
- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
  is now the canonical client live-update, projection-runtime, freshness, and
  proof reference. Its section `0.7 Canonical Client Projection Runtime
  Architecture` supersedes this doc where client sync, catch-up, lifecycle, or
  proof ownership differs.
- `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`
- `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`

## 2026-06-02 Supersession Note

The current identity-specific plan is
`docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md`. The current
holistic client runtime plan is
`docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
section `0.7 Canonical Client Projection Runtime Architecture`. Together, they
keep this doc's core invariant, but supersede the broader sections that
required pending-row supersession, `clientMutationID`, transaction grammar,
`archive.cleanup` projection streams, `system.health` projection streams,
`host.registry` projection streams, or a universal projection-row store. Those
sections remain below as historical context.

## 2026-06-01 Current Ask Answer

The most elegant permanent solution is one relay-owned projection system for
every visible Codex Dock object. The system has one identity owner, one ordering
owner, one update ledger, one cache contract, one generated client contract, and
one proof witness source.

The final architecture is:

```text
raw Codex inputs
  -> relay source adapters
  -> pure projection engine
  -> versioned projection store
  -> projection view streams and witnesses
  -> Swift projection renderers
```

No layer after the projection engine may answer "what visible row is this?"
again. Swift may render and validate. Proof may compare. SQLite may store. None
of them may derive production visible identity.

This is the target pattern, not a narrow Thread Detail fix:

1. One projection contract package defines the shared row envelope, snapshot
   envelope, update envelope, view parameters, typed payload schemas, and proof
   witness schemas.
2. The relay projection engine is the only production module allowed to create
   `sourceHostID`, `sourceRef`, `projectionID`, `rowRole`, `displayOrderKey`,
   `revision`, freshness, ledger operations, or diagnostic rows.
3. Dock, Archive, Archive Cleanup, Host Registry, Thread Detail, request rows,
   simulator UI proof, live-filter proof, sync audit, and fixture generation all
   consume that same projection package.
4. Raw `thread/list`, `thread/read`, `thread/turns/list`, `thread/resume`, live
   notifications, and server requests stay as relay-internal source adapters.
   They are never phone-facing display contracts and never proof truth.
5. The app receives projection snapshots and updates only. It keys visible rows
   by relay `projectionID`, applies `snapshot` / `upsert` / `delete` /
   `heartbeat` / `resyncRequired` by `epoch` and `seq`, and sorts by
   `displayOrderKey`.
6. SQLite stores materialized projection rows and view memberships under the
   projection contract version. A contract bump invalidates old materialized
   rows before they can be served as fresh.
7. Request cards are projection rows with request payload. `requestID` is only
   the JSON-RPC response-routing token; it is not visible identity.
8. Local metadata, pins, filters, host settings, previews, and accessibility IDs
   decorate or expose projection rows. They never create a second row set,
   order, freshness state, or identity namespace.
9. Acceptance proof compares simulator accessibility dumps to relay-emitted
   projection witness envelopes from the same run. It does not reconstruct
   expected IDs from raw Codex data or imported ID helpers.
10. CI enforces the contract with schema generation/checking, strict proof
    schemas, forbidden side-door checks, and live temporal tests that exercise
    snapshots, updates, reconnects, resyncs, request resolution, and cache
    invalidation.

Net: the architecture makes identity bugs go away by removing every second
identity owner. If a visible row exists, its identity came from the relay
projection engine or the row is invalid.

## 2026-06-01 Current Repo Evidence

This re-audit reads the dirty local worktree as evidence only. It does not mark
the worktree implementation complete.

The repo is partially moved toward the target:

- `CodexDock/State/ThreadDetailStore.swift` now subscribes and resyncs through
  `thread/detail/subscribe` and `thread/detail/resync`.
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` now applies Thread
  Detail projection rows by `projectionID`, `epoch`, and `seq`.
- `scripts/dock-relay-thread-detail-ledger.mjs` creates Thread Detail
  projection rows with `sourceHostID`, `sourceRef`, `projectionID`,
  `displayOrderKey`, and request payload.
- `scripts/dock-relay-projection-engine.mjs` is the seed of the right pure
  projection package.
- `CodexDock/AppServer/AppServerClient.swift` now hides arbitrary
  `sendRequest(method:)` from public callers, which is the right direction.

The repo still has side doors that the final architecture must close:

- Dock and Archive still have card-shaped vocabulary and stores such as
  `cardsByID`, `DockThreadCardDTO`, `ThreadCardTable`, and card-specific
  fixture helpers. That can be a transition name only; final identity is
  `projectionID`.
- `DockRowViewModel.id` still carries `HostScopedThreadID`, so Dock/Archive UI
  actions still need a full cutover to projection identity plus explicit
  source/action payload.
- Relay proof and diagnostic scripts still contain old stream grammar markers:
  `baseSeq`, `upsertCards`, `deleteCardIDs`, `visibleEventIDs`,
  `thread/read`, `thread/turns/list`, and `thread/resume` as proof-side
  vocabulary.
- `scripts/dock-relay-simulator-ui-sync-proof.mjs` and related tests still
  contain `.freshDock.cards`, local `projectionIDForThread` helpers, and legacy
  `expectedMessageProjectionIDs` fallback behavior.
- `scripts/codex-dock-live-filter-truth.mjs` and
  `scripts/codex-dock-live-filter-compare.mjs` still rebuild detail truth from
  raw `thread/turns/list` vocabulary and `visibleEventIDs`.
- Controlled simulator scripts still require raw `thread/read`,
  `thread/turns/list`, and `thread/resume` in several client-path proof
  scenarios. Those routes are allowed only as relay-internal upstream adapter
  calls, not as client proof routes.
- `CodexDockTests/LegacyThreadDetailRawDTOs.swift` and
  `CodexDockTests/LegacyThreadEventFixtureNormalizer.swift` quarantine legacy
  behavior in tests, but they are still a second expected-output oracle until
  projection fixtures are generated by the projection package.
- Proof schemas under `contract/proof` still use `additionalProperties: true`,
  so stale fields can pass unless semantic checks catch them. Final proof
  schemas must reject unknown identity and route fields by default.
- Request card display now derives from Thread Detail projection rows, with
  phone-only input/status state keyed by `projectionID`. `requestID` remains
  response routing only, not display identity.
- Raw upstream routes still correctly exist in `scripts/dock-relay-thread-data.mjs`
  and `scripts/dock-relay.mjs` as relay source adapters. The architecture must
  keep them there and forbid them everywhere else.

Those findings do not weaken the target architecture. They explain why the
target must be a package-and-contract cutover, not another local patch.

## Non-Negotiable Elegance Test

This architecture is accepted only if the answer to each question is "one":

- How many modules create production visible IDs? One relay projection engine.
- How many wire grammars update visible rows? One projection stream grammar.
- How many durable stores can serve visible projection rows as fresh? One
  versioned projection store.
- How many proof witnesses can define expected visible state? One retained
  relay projection witness from the same run.
- How many Swift display paths consume raw Codex history or live payloads? Zero.
- How many test helpers are allowed to predict production projection IDs beside
  the relay? Zero for acceptance proof; unit tests may call the projection
  package itself, not reimplement it.

Anything else is not elegant; it is a second source of truth with nicer names.

## Composer Tightening Incorporated

The 2026-06-01 Composer 2.5 Fast consult agreed with the architecture and found
no blocking design gap. It did identify five places where the doc needed to be
more normative before implementation. This section is the incorporated answer.

Request rows have one final rule:

- If a server request has proven `turnID` + `itemID` and maps to a supported
  visible item row, the request state attaches to that item row's
  `projectionID`. The relay upserts the same row when canonical history catches
  up.
- If a server request lacks a usable item link, or the item link maps to an
  unsupported item role, the relay emits a standalone request row:
  `host:<sourceHostID>/thread:<threadID>/request:<requestID>/row:request` or,
  when useful for diagnostics,
  `host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/request:<requestID>/row:request`.
- The relay must never emit both an item row and a separate request row for the
  same proven request/item relationship. Request status is `revision` and
  payload state on the chosen `projectionID`, not another row identity.

Projection witness export has one final rule:

- The witness is a retained byte-for-byte copy of projection envelopes after
  the relay has emitted them to the downstream client path.
- The witness route may filter or redact non-identity payload fields for safe
  reporting, but it must not recompute `projectionID`, `displayOrderKey`,
  membership, freshness, route counts, or expected UI rows.
- If the retained witness is missing, stale, malformed, or for a different
  `proofRunID`, proof is `blocked` or `fail`. It must not fall back to raw
  Codex reads, SQLite reconstruction, fixture helpers, or `projectionIDFor*`
  imports.

Phase 1 is a hard architecture gate:

- `contract/projection/**` must exist before any cutover is called complete.
- Node DTOs, Swift DTOs, fixtures, and proof schemas must be generated from or
  checked against that package.
- `contract/dock/dock-thread-card.schema.json` can remain only as migration
  history or be moved into the projection package. It cannot remain a second
  production display schema.

Swift render adapters have one final rule:

- A Swift type named `ThreadEvent` may exist only as a projection-row render
  adapter keyed by relay `projectionID`.
- Production Thread Detail, Dock, Archive, Archive Cleanup, and Host Registry
  render state must reject missing `displayOrderKey` instead of falling back to
  local date/turn/item/event sorting.
- Fallback sorting is allowed only in quarantined legacy tests that prove the
  old path has been retired; it is not allowed in production display stores or
  acceptance proof.

Enforcement is part of the architecture:

- Forbidden-pattern gates are not lint polish. They are the mechanism that
  keeps the architecture from drifting back into multiple identity owners.
- No implementation can be accepted while production display code or acceptance
  proof still contains raw display routes, fixture-computed expected IDs,
  permissive proof schemas, `logicalHostID::threadID` identity, `baseSeq`,
  `upsertCards`, `deleteCardIDs`, `visibleEventIDs`, or request-card display
  IDs derived from `requestID`.

## Architecture Decision

The permanent answer is not "fix one duplicate." The permanent answer is a
single product projection plane:

```text
raw Codex adapters -> relay projection engine -> versioned projection store -> view streams -> Swift renderers
```

Only the relay projection engine answers these questions:

- What visible thing is this?
- What is its stable identity?
- What source fact produced it?
- What order should it render in?
- Is it fresh, stale, partial, or diagnostic?

Every production screen then consumes projection rows. Dock, Archive, Thread
Detail, request cards, simulator proof, and UI dump comparison all use the same
projection grammar. Raw `thread/list`, `thread/read`, `thread/turns/list`,
`thread/resume`, live notifications, and server requests become private input
adapters. They are not display contracts.

This is intentionally zero-sunk-cost. If an existing route, DTO, SQLite table,
test fixture, or proof script lets another layer infer visible identity, it is
not preserved for convenience. It is deleted, quarantined as a non-production
diagnostic, or rewritten to consume projection rows.

## Acceptance Standard

The architecture is accepted only when all of these are true:

- One schema source defines the shared projection envelope and typed view
  payloads.
- Node and Swift consume generated or schema-checked DTOs from that source.
- The relay has one pure projection engine for identity, source refs, order,
  freshness, and ledger operations.
- Dock and Archive cards are projection rows, not a separate `logicalHostID` /
  `host::thread` card grammar.
- Thread Detail messages and request cards are projection rows, not raw Codex
  rows normalized in Swift.
- Relay SQLite stores materialized projections keyed by projection contract
  version, source host, view membership, and projection identity.
- A projection contract version bump invalidates old materialized rows before
  they can be served as fresh.
- Swift display stores apply only projection snapshots and updates by
  `epoch`, `seq`, `projectionID`, and `displayOrderKey`.
- Swift never creates production visible IDs from raw Codex JSON, body text,
  timestamps, local UUIDs, WebSocket request IDs alone, or UI object lifetime.
- Proof scripts compare simulator accessibility state against relay projection
  snapshots or updates, not against a second reconstruction of raw Codex truth.
  Fields such as `expectedMessageEventIDs` are forbidden in acceptance proof
  outputs because they encode a second identity oracle.
- Test fixtures either come from the projection engine or validate against the
  projection schema. They do not invent production message/card IDs, and they
  do not compute expected UI IDs outside the relay-emitted projection ledger.
- Raw routes may exist only as relay-internal adapters, mutation routes, or
  named diagnostics. They cannot feed production display state or acceptance
  proof.

Net: after implementation, identity drift is not a category of app bug because
there is no second production identity owner left.

## Zero-Sunk-Cost Permanent Solution

The objectively clean architecture is a projection system, not a Thread Detail
fix.

The relay owns a single projection contract package. Raw Codex facts enter that
package; versioned projection rows leave it. Every user-visible Dock object is
then just a row in a projection view.

The architecture has seven laws:

1. Raw Codex routes are adapters only.
   `thread/list`, `thread/read`, `thread/turns/list`, `thread/resume`, live
   notifications, and server requests may feed the relay, but they never define
   phone display identity.
2. One pure projection engine owns identity.
   The only production helpers that can create `sourceRef`, `projectionID`,
   `displayOrderKey`, row role, freshness, `identityVersion`, or
   `projectionEngineVersion` live in the relay projection contract package.
3. One ledger model owns updates.
   Dock, Archive, Archive Cleanup, Host Registry, and Thread Detail all use the
   same `snapshot`, `upsert`, `delete`, `heartbeat`, and `resyncRequired`
   semantics with `epoch`, `seq`, `view`, `scope`, `sourceHostID`, and
   `viewParamsKey`.
4. Swift is a renderer and validator.
   Swift decodes generated or schema-checked projection DTOs, validates the
   envelope, rejects gaps/mismatches, renders by `projectionID`, and sorts by
   `displayOrderKey`. It does not reconstruct visible identity from raw JSON,
   body text, timestamps, request IDs, UUIDs, or object lifetime.
5. `requestID` is never display identity.
   JSON-RPC `requestID` routes a response. If a request is visible, the visible
   row is still keyed by relay `projectionID`; request state is payload/revision.
6. Cache validity is part of the identity contract.
   Materialized rows are keyed by
   `schemaVersion + identityVersion + projectionEngineVersion + sourceHostID +
   view + viewParamsKey + projectionID`. A version bump cannot serve old rows as
   fresh.
7. Proof reads the emitted projection stream.
   Simulator/UI proof, live-filter proof, controlled fixtures, and acceptance
   reports compare the app only to relay-emitted projection snapshots/updates or
   a byte-for-byte retained witness export. They do not call `projectionIDFor*`
   helpers or reconstruct expected visible IDs beside the system under test.

That is the elegance test. There can be many raw inputs and many screens, but
there is one place where a visible object becomes a visible object. If a future
feature cannot go through that place, the feature is architecturally incomplete.

This deliberately rejects the cheaper alternatives:

- no Swift-side duplicate suppression;
- no body-text dedupe;
- no "prefer newest route" heuristic;
- no second identity helper in tests;
- no keeping raw routes as hidden display proof paths;
- no accepting stale cache rows because they are "compatible enough."

The end state is simple: the iPhone renders a projection view, and every row on
screen has exactly one relay projection identity.

## User-Visible Bug

When an outbound user message is sent, Thread Detail can show that outbound
message twice.

The intended behavior is simpler:

- One user send produces one visible user-message row.
- That row may move or lose its live badge as canonical history catches up.
- It must not remain as both a live row and a canonical row.

## Root Cause

The original pre-projection Thread Detail path had no single canonical event
identity layer for "the same Codex item" across live notifications and
canonical history reads.

That client path stored `ThreadEvent` rows in `ThreadEventIndex` and merged
only by:

1. Exact `ThreadEvent.id`.
2. A secondary stream key of `turnID + itemID + kind + visibility`.

That works only when every producer gives the same `turnID` and `itemID` in the
same place. The outbound path does not guarantee that.

The dangerous path is:

1. Thread Detail is live through `thread/resume`.
2. A user sends or otherwise creates a user message.
3. The live session can emit an `item/started` or `item/completed` notification.
4. The app turns that live notification into a `ThreadEvent`.
5. The Dock row updates, so Thread Detail does a canonical reread:
   `thread/read` + all pages of `thread/turns/list` + `thread/resume`.
6. That canonical reread is merged into the existing event index, not used as a
   replacement.
7. If the live row and canonical row do not normalize to the same event identity,
   both survive and render as two visible user-message cards.

That was a client-side merge contract bug. The current work-in-progress moves
the direct Thread Detail display path toward relay projection DTOs, but the
broader architecture is not complete until all display surfaces and proof paths
share the same projection identity plane.

## What This Is Not

This does not look like a SwiftUI `ForEach` rendering duplicate. `ForEach` keys
rows by `ThreadEventRenderRow.id`, which is `event.id`.

This does not look like an optimistic-send duplicate. `ThreadDetailStore.sendDraft`
does not add a local pending message row. It sends `turn/start` or `turn/steer`,
then clears the draft and updates `activeTurnID`.

This does not look like a relay "sent the same command twice" bug from the code
path alone. The relay forwards `turn/start` and `turn/steer` to the active
upstream after checking that the downstream detail session is bound to the same
thread. It does not create Thread Detail rows.

The duplicate is produced after the client accepts multiple representations of
the same logical Codex item and fails to collapse them.

## Original Pre-Projection Code Touchpoints

This section records the code shape that caused the duplicate before the
projection work-in-progress began. The later
`Current Drift Points Still Visible In The Repo` section is the authoritative
read of what still needs architectural cleanup.

### Outbound Send Path

`CodexDock/State/ThreadDetailStore.swift`

- `sendDraft()` validates the composer and calls `commandEngine.sendDraft`.
- It does not append a visible message.
- It only records the returned active turn and clears composer state.

Relevant lines read:

- `sendDraft()` starts around line 384.
- `commandEngine.sendDraft(...)` is called around lines 407-413.
- `activeTurnID` is updated around lines 414-415.
- `composer.draft` is cleared around line 416.

Conclusion: the duplicate is not caused by a local optimistic row in
`sendDraft()`.

### Live Notification Path

`CodexDock/State/ThreadDetailStore.swift`

- `handle(notification:)` buffers only during canonical load/recovery.
- `apply(notification:)` passes the notification into `ThreadDetailDataEngine`.
- If the data engine returns a snapshot, the store publishes it.

`CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`

- `apply(notification:)` calls `ThreadEventNormalizer.event(from:)`.
- It then calls `index.appendOrMerge(event)`.

Relevant lines read:

- notification apply path around lines 47-59 in `ThreadDetailDataEngine`.
- index merge path around lines 141-184 in `ThreadDetailDataEngine`.

Conclusion: live notifications create visible rows immediately if the
normalizer returns an event.

### Canonical Reread Path

`CodexDock/State/ThreadDetailStore.swift`

When the Dock row updates, Thread Detail queues a refresh:

- `observeDockRowUpdate(...)` updates the header and queues refresh work.
- `rehydrateAfterDockRowAdvance(...)` rereads full history.
- That reread calls `mergeEvents(from:)`, not `replaceEvents(from:)`.

Relevant lines read:

- dock-row refresh queue around lines 719-767.
- full reread and merge around lines 770-787.
- `mergeEvents(from:)` around lines 826-834.

Conclusion: after live rows are already in memory, the canonical refresh merges
history into that same index. If identity is wrong, it preserves both rows.

### Event Identity Path

`CodexDock/Models/ThreadEvent.swift`

Stored canonical history:

- `events(fromTurn:)` reads turn objects from `thread/turns/list`.
- It reads `turn["id"]`, item `object["id"]`, and creates IDs like
  `turnID-itemID-user`.

Live full-item notifications:

- `event(from notification:)` handles `item/started` and `item/completed`.
- It passes `params["item"]` into the same `events(fromItem:)` helper, with the
  top-level notification params as `turn`.
- `events(fromItem:)` only reads `object["id"]` from the nested item object.
- If the nested item has no `id`, it generates `UUID().uuidString`.

Relevant lines read:

- `item/started` and `item/completed` handling around lines 294-299.
- stored turn normalization around lines 376-390.
- nested item ID read and random fallback around lines 424-425.
- user-message event creation around lines 461-471.

Conclusion: the same logical outbound message can become two different
`ThreadEvent.id` values if live and canonical item identity are not normalized
through one canonical key.

## Why The Existing Tests Miss This

The tests prove pieces, but not the failure path.

Current coverage:

- `ThreadDetailStoreTests.testSendDraftStartsTurnWhenNoActiveTurnAndClearsDraft`
  proves `turn/start` is called and the draft clears.
- `ThreadDetailStoreTests.testSendDraftSteersKnownActiveTurn` proves
  `turn/steer` is called for an active turn.
- `ThreadDetailStreamingMergeTests.testCompletedAgentMessageReplacesLiveDeltaInsteadOfDuplicating`
  proves an agent delta and an agent completed item merge when both paths use
  the same nested item ID.

Missing coverage:

- No test sends a draft and then emits the live user-message notification that
  Codex sends back.
- No test follows that with the Dock-row-triggered canonical reread.
- No test asserts "same outbound user body appears exactly once" after live
  event plus canonical reread.
- No test covers live full-item notifications where identity appears in a
  different place than stored history.
- No simulator proof currently drives the real composer send path and then
  checks Thread Detail visible message-card IDs for duplicates.

That is why the current tests can pass while the phone shows a duplicated
outbound message.

## Evidence Collected

1. The attempted product-code change was reverted. `git diff` for
   `CodexDock/Models/ThreadEvent.swift` and
   `CodexDockTests/ThreadEventNormalizerTests.swift` was clean after undo.
2. The current simulator UI dump command ran successfully:
   `/tmp/codex-client/sim-ui-dump-20260601T172159Z/sim-ui-dump.json`.
   The simulator was on the Dock screen at dump time, so it did not capture the
   duplicated Thread Detail row.
3. Real simulator app logs for thread
   `019e8364-6a39-7f20-8490-dcebe775cf16` show repeated Dock-row-triggered
   Thread Detail refreshes:
   - `thread detail dock row refresh started`
   - `thread detail dock row refresh finished ... events=...`
   This confirms the canonical reread path is active while a live detail view is
   open.
4. Real current Codex history for thread
   `019e7e7d-66ca-7280-9aa0-2e272f1752b1` shows stored user messages have stable
   `turnId` and `itemId` values. That means stored history alone is not forced
   to create random row IDs.
5. `rtk swift test --filter ThreadDetailStreamingMergeTests` passed with one
   test. That confirms the existing test is green, but it only covers the narrow
   agent-message case with stable nested item identity.

## Why The Quick Fallback Fix Was Not Good Enough

The reverted idea was to make `item/started` and `item/completed` use top-level
`params["itemId"]` when nested `item.id` is missing.

That may be part of the eventual fix, but by itself it is too narrow because it
does not establish a single rule for Thread Detail identity. It patches one
shape instead of defining the contract.

The correct fix should define one canonical event identity function and route
all event producers through it:

- stored turn item from `thread/turns/list`
- live streaming delta from `item/*/delta`
- live full item from `item/started` and `item/completed`
- server request rows
- canonical reread merge rows

The merge layer should then merge by that canonical identity, not by whatever
ad hoc `ThreadEvent.id` each producer happens to build.

## Permanent Architecture Proposal

The earlier narrow answer was "put Thread Detail row identity in the relay."
That is directionally right, but it is not the full permanent answer if the bar
is "this whole class of identity issues stops being a concern."

The full answer is one relay-owned projection identity plane for every
user-visible Dock object:

```text
raw Codex state -> relay projection engine -> versioned projection ledger -> Swift renderer
```

Swift, UI proof scripts, simulator fixtures, and tests should never separately
decide what a visible production row/card "is." They can render, validate, and
compare projection rows, but they do not own production identity.

This is a stronger architecture than a Thread Detail-only patch because the
same failure shape has already appeared in several forms:

- Dock cards were ordered from stale thread-level metadata while newer turn
  state existed somewhere else.
- Thread Detail could merge live and canonical rows under different IDs.
- Request cards had their own card/request identity beside message rows.
- Proof scripts reconstructed expected UI IDs instead of reading the relay's
  display ledger.
- Tests used fake/static snapshots that did not exercise real temporal
  convergence.

The permanent fix is therefore not "normalize one more payload field." The
permanent fix is to make visible identity, visible order, freshness, and update
continuity a single projection contract at the relay boundary.

### Current Drift Points Still Visible In The Repo

The current work-in-progress shape is better than the original bug, but it is
not yet the permanent architecture. The strongest local improvement is that
`ThreadDetailStore` now calls `thread/detail/subscribe` and
`thread/detail/resync`, and `ThreadDetailDataEngine` applies projection DTOs.
That closes the most direct duplicate-message path for the main Thread Detail
screen, but it does not close the whole identity-drift class.

Open drift points from the current repo review:

- Thread Detail has `scripts/dock-relay-thread-detail-ledger.mjs`, but Dock and
  Archive still use the separate card stream shape in
  `contract/dock/dock-thread-card.schema.json` and
  `CodexDock/AppServer/DockThreadCardDTO.swift`.
- Dock/Archive card identity is still `logicalHostID` plus `threadID`, with
  `DockThreadCardDTO.id` shaped as `host::thread`. It is not yet the shared
  `projectionID` envelope.
- The relay now has a persisted `sourceHostID` resolver, but Dock/Archive still
  publish host/card identity through `logicalHostID` and the card-v2 DTO
  grammar. Source identity is improved but not yet enforced across every view.
- Relay SQLite has relational `schema_migrations`, but materialized card rows
  are not invalidated by
  `schemaVersion + identityVersion + projectionEngineVersion + sourceHostID`.
- `scripts/dock-relay-state-store.mjs` persists `dock_id` and
  `logical_host_id` as card identity fields. The store has no universal
  projection row table plus view-membership table.
- `CodexDock/AppServer/AppServerMethods.swift` no longer exposes raw
  `thread/read`, `thread/turns/list`, or `thread/resume`, and the main
  `ThreadDetailStore` display path now uses `thread/detail/subscribe` and
  `thread/detail/resync`. That closes the direct product route side door, but
  raw `ThreadRead*`, `ThreadTurnsList*`, and `ThreadResume*` DTO types still live
  in `CodexDock/AppServer/ThreadDetailDTO.swift`, and generic JSON-RPC
  `sendRequest` can still call arbitrary method strings. Final architecture
  removes raw display DTOs from the phone product target or quarantines them as
  explicit relay-internal/test-only adapter fixtures.
- `CodexDock/Models/ThreadEvent.swift` no longer owns the old raw
  `ThreadEventNormalizer`; the legacy normalizer has been moved to
  `CodexDockTests/LegacyThreadEventFixtureNormalizer.swift`. That is directionally
  correct, but it remains a test-only projection oracle. Tests must stop deriving
  production projection rows from a local legacy normalizer and instead consume
  relay projection fixtures or the shared projection contract package.
- `ThreadEventDisplayOrder` still has fallback ordering from dates, turn
  sequence, item sequence, and event id. In the final architecture, missing
  `displayOrderKey` is an invalid DTO that forces resync, not a local sort
  problem.
- `CodexDockTests/ThreadDetailStoreTestSupport.swift` still reconstructs
  projection IDs locally from test convenience objects. That means tests can pass
  against a projection shape the relay does not actually emit.
- `scripts/codex-dock-live-filter-truth.mjs` and
  `scripts/codex-dock-live-filter-compare.mjs` still speak in `eventID` and
  reconstruct Thread Detail truth from raw routes.
- `scripts/dock-relay-controlled-simulator-fixture.mjs` and
  `scripts/dock-relay-controlled-simulator-matrix.mjs` still name raw
  `thread/read`, `thread/turns/list`, and `thread/resume` as required detail
  proof routes in several scenarios. `scripts/dock-relay-sync-audit.mjs` has
  been partially moved to `thread/detail/*`, but its fake upstream fixtures still
  expose raw app-server handlers because the relay must still adapt raw Codex
  inputs internally.
- `scripts/dock-relay-simulator-ui-sync-proof.mjs` now uses
  `expectedMessageProjectionIDs`, not `expectedMessageEventIDs`, but controlled
  fixtures still construct those projection IDs beside the relay by importing
  helper functions. Final proof must read expected visible IDs from
  relay-emitted projection snapshots or updates, not from a parallel fixture
  oracle.
- Request rows in the current Thread Detail ledger are still always request-row
  projections. The stricter final contract attaches command/file/tool requests
  to the item projection when turn/item identity proves that the request is for
  that visible item.
- The schema story is split: Dock has a JSON Schema plus generator, Thread
  Detail DTOs are hand-written Swift/JS, and there is no one projection schema
  package for every view.

Those are not polish issues. They are the remaining places another layer can
answer "what visible thing is this?" after the relay projection engine has
already answered it.

### 2026-06-01 Architecture Re-Audit By Layer

This is the current identity-owner map after re-reading the repo. The permanent
architecture is accepted only when the `Target decision` column is true for
every row.

| Layer | Current identity behavior | Drift risk | Target decision |
| --- | --- | --- | --- |
| Raw app-server adapters | Relay still calls upstream `thread/list`, `thread/read`, `thread/turns/list`, `thread/resume`, live notifications, and server requests. | Safe only if treated as inputs. Dangerous if any phone/proof display path consumes them directly. | Keep as relay-internal adapters only; never phone-facing display truth. |
| Relay source host identity | `scripts/dock-relay.mjs` now resolves `config.hostId` through explicit config/env or `.codex-dock/source-host-id`. | Dock/Archive still expose `logicalHostID` in payload and identity. | Promote `sourceHostID` to the only identity namespace for every projection row; keep display names/endpoints as labels only. |
| Thread Detail relay ledger | `scripts/dock-relay-thread-detail-ledger.mjs` owns `projectionID`, `sourceRef`, `displayOrderKey`, `epoch`, `seq`, and `viewParamsKey` for Thread Detail rows. | It is Thread Detail-only and hand-shaped, not a shared contract package. | Make this the first view-specific client of a universal projection engine and schema package. |
| Dock/Archive relay state | `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-state-engine.mjs`, and `scripts/dock-relay-state-subscriptions.mjs` persist and publish card-v2 `id`, `logicalHostID`, `stateGeneration`, `upsertCards`, and `deleteCardIDs`. | This is a second display identity grammar. | Replace with shared projection rows and view memberships. |
| Relay cache | SQLite stores `threads`, `live_leases`, `turn_cache`, changes, and scopes under schema migrations. | Cache validity is not keyed by projection identity contract version. | Cache key includes `schemaVersion`, `identityVersion`, `projectionEngineVersion`, and `sourceHostID`; invalid rows cannot be served as fresh. |
| Phone-facing routes | `dock/*`, `archive/*`, and `thread/detail/*` exist; the direct Swift method constants for raw `thread/read`, `thread/turns/list`, and `thread/resume` are gone, but raw DTO types and generic `sendRequest` remain. | A future store/proof can still route around projections unless forbidden by contract, tests, and code ownership. | Phone production display protocols expose projection routes only; raw routes are internal adapters or named diagnostics. |
| Swift Thread Detail store | Main display path now subscribes/resyncs through projection DTOs and applies by `projectionID`. | Test support still reconstructs projection rows locally; `ThreadEventDisplayOrder` still has fallback sorting for non-projection events. | Swift display code initializes render rows only from projection DTOs; missing `displayOrderKey` is invalid for production projection rows. |
| Swift Dock/Archive stores | Card stores decode card-v2 DTOs and project `HostScopedThreadID(hostID: logicalHostID, threadID)`. | Dock/Archive can drift from Thread Detail identity and source-host rules. | Dock/Archive render projection rows keyed by `projectionID`. |
| Request cards | Thread Detail projection rows now carry request payloads, but `requestCards` remains a transient array rebuilt from events. | Safe only while it is strictly rebuilt by `projectionID`; risky if it becomes membership/status truth. | Request controls are UI state attached to projection rows; `requestID` is routing only. |
| Automation IDs | Thread message accessibility IDs now use `AutomationID.Session.messageCard(projectionID:)`. | Dock/Archive accessibility still follows card-v2 row identity; proof helpers still know old card IDs. | Every visible row/card ID derives from the relay-emitted `projectionID` with one escaping rule. |
| Simulator/UI proof | `sim-ui-dump` can dump visible state; sync proof now looks for `expectedMessageProjectionIDs`. | Some proof fixtures still compute expected projection IDs locally; live-filter proof still uses raw `eventID` and raw `thread/turns/list` truth. | Proof compares UI only to relay projection snapshots/updates captured from the system under test. |
| Tests | Thread Detail projection tests exist; Dock/Archive tests still assert card-v2 fields; Thread Detail test support still reconstructs projection IDs locally. | Static fixtures can pass while live/canonical convergence is broken. | Tests feed raw sequences through the relay projection engine and assert temporal convergence. |
| Contract docs/schemas | Dock has `contract/dock/dock-thread-card.schema.json`; proof schemas are permissive; Thread Detail projection schema is hand-coded. | Contract drift remains possible because there is no single package. | One projection contract package generates/checks Node, Swift, fixtures, and proof schemas. |

### The Object Model

Use three separate concepts everywhere. Mixing them is what creates duplicates:

| Concept | Owner | Meaning | May change? |
| --- | --- | --- | --- |
| `sourceRef` | Relay normalizer | Stable reference to the raw Codex fact, including host/thread/turn/item/request identity. | No, unless the relay emits a supersession from pending to canonical. |
| `projectionID` | Relay normalizer | Stable visible row/card identity derived from `sourceRef` plus row role. | No. |
| `revision` | Relay ledger | Version of the content for the same `projectionID`. | Yes. |

The renderer keys UI rows by `projectionID`. Content changes, streaming text,
request status changes, and canonical catch-up updates bump `revision`; they do
not create new row identity.

The canonical identity namespace should include host identity, not just
`threadID`, so two relays or two Codex homes cannot collide:

```text
host:<sourceHostID>/row:host
host:<sourceHostID>/thread:<threadID>/row:threadCard
host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/row:<rowRole>
host:<sourceHostID>/thread:<threadID>/request:<requestID>/row:request
host:<sourceHostID>/thread:<threadID>/system:<systemKind>/<stableSourceSequence>
host:<sourceHostID>/thread:<threadID>/diagnostic:<stableHash>/row:unknown
```

Dock and Archive use the same thread-card identity:

```text
host:<sourceHostID>/thread:<threadID>/row:threadCard
```

The route `view` decides whether that row appears in Dock or Archive. Archive
state is payload state, not a separate card identity. The Dock/Archive card
`sourceRef` is:

```text
host:<sourceHostID>/thread:<threadID>
```

The existing Dock `logicalHostID` field is a transition alias for
`sourceHostID`; if a payload
carries both and they disagree, the relay must diagnose or resync instead of
letting Swift choose.

`sourceHostID` is the relay's canonical identity for the Codex source host. It
must be stable across Bonjour name changes, LAN/Tailscale endpoint changes, and
phone saved host config edits. UI labels can change; source identity cannot.

The derivation rule is:

1. Use non-empty `CODEX_DOCK_REAL_HOST_ID` from relay-side configuration.
2. Else use the persisted value in `.codex-dock/source-host-id`.
3. Else create `.codex-dock/source-host-id` once as
   `local-<sha256(platform + user + CODEX_HOME + historyUrl)[0..12]>`.

`sourceHostID` must match `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`. It must not be
derived from endpoint hostnames, Bonjour names, LAN IPs, Tailscale names, saved
phone host config, WebSocket connection IDs, relay process IDs, or
`CODEX_DOCK_RELAY_INSTANCE_ID`.

### Projection Row Envelope

Every user-visible projection row should share one envelope, even when the row
payload is typed differently for Dock cards, Archive cards, Thread Detail
messages, and request cards:

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "threadID": "019e...",
  "projectionID": "host:amir-m5/thread:019e.../turn:t1/item:i1/row:userMessage",
  "sourceRef": "host:amir-m5/thread:019e.../turn:t1/item:i1",
  "rowRole": "userMessage",
  "revision": 7,
  "displayOrderKey": "9998239345599999|0000000000|9999999999|9999999999|...",
  "freshness": {
    "state": "fresh",
    "sourceWatermark": "codex-source-..."
  },
  "payload": {}
}
```

The row-specific payload can stay typed:

- Dock and Archive rows carry card fields.
- Thread Detail rows carry message/request/system fields.
- Request-backed rows carry `requestID` for responses, but the visible row key
  remains `projectionID`.

The shared envelope is what kills identity drift. The screen can vary; the
identity and update rules do not.

### Projection Snapshot And Update Envelope

Each subscribed view should use the same stream grammar:

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "view": "thread.detail",
  "sourceHostID": "amir-m5",
  "threadID": "019e...",
  "epoch": "projection-...",
  "seq": 42,
  "scope": "thread",
  "viewParamsKey": "sha256:...",
  "complete": true,
  "freshness": {
    "state": "fresh",
    "asOf": "2026-06-01T18:00:00.000Z",
    "sourceWatermark": "codex-source-..."
  },
  "rows": []
}
```

Updates are only:

- `snapshot`: replace the declared scope.
- `upsert`: insert or replace rows by `projectionID`.
- `delete`: remove rows by `projectionID`.
- `heartbeat`: prove continuity without changing rows.
- `resyncRequired`: declare continuity broken and force a replacement
  snapshot.

Every update carries `epoch` and `seq`. Swift applies only the active epoch and
monotonic sequence. A new epoch without a snapshot is invalid. A sequence gap is
not "probably fine"; it is stale until resync succeeds.

Every projection snapshot and update also carries `projectionEngineVersion`.
Clients store the active engine version with the active epoch. If an update
arrives with a different `projectionEngineVersion` inside the same epoch, the
client rejects it and requests the matching resync route. A new engine version
is accepted only through a replacement snapshot with a new epoch.

`projectionEngineVersion` is required on every projection snapshot and update
envelope for Dock, Archive, Host Registry, and Thread Detail. Stored projection
rows also carry the engine version as cache metadata. If Swift sees an engine
version mismatch, it must not translate old rows locally; it marks the view
stale and asks the relay for a replacement snapshot.

The existing route names can remain because they are understandable:

- `dock/subscribe`, `dock/update`, `dock/resync`
- `archive/subscribe`, `archive/update`, `archive/resync`
- `thread/detail/read`, `thread/detail/subscribe`, `thread/detail/update`,
  `thread/detail/resync`

The elegant part is not a single generic route name. The elegant part is that
all three route families obey the same projection envelope and identity rules.

### Cross-View Scope And Snapshot Authority

Thread Detail already names `scope: "thread"` and optional `scope: "window"`.
Dock and Archive need the same explicit authority rule so card cutover does not
recreate merge ambiguity under new names.

Accepted projection scopes:

| View | Scope | Meaning | Snapshot replacement rule |
| --- | --- | --- | --- |
| `dock` | `view` | Complete active Dock view for the supplied `viewParamsKey`. | Replace every local `dock` row for that `sourceHostID` and `viewParamsKey` with the snapshot rows. Rows absent from the snapshot are deleted. |
| `archive` | `view` | Complete Archive view for the supplied `viewParamsKey`. | Replace every local `archive` row for that `sourceHostID` and `viewParamsKey` with the snapshot rows. Rows absent from the snapshot are deleted. |
| `archive.cleanup` | `view` | Complete Archive Cleanup candidate view for the supplied `viewParamsKey`. | Replace every local cleanup candidate row for that `sourceHostID` and `viewParamsKey` with the snapshot rows. Rows absent from the snapshot are deleted. |
| `dock` | `host` | Complete active Dock view for one `sourceHostID`. | Replace only rows for that `sourceHostID`, `view`, and `viewParamsKey`. |
| `archive` | `host` | Complete Archive view for one `sourceHostID`. | Replace only rows for that `sourceHostID`, `view`, and `viewParamsKey`. |
| `archive.cleanup` | `host` | Complete cleanup candidate view for one `sourceHostID`. | Replace only cleanup rows for that `sourceHostID`, `view`, and `viewParamsKey`. |
| `dock` / `archive` / `archive.cleanup` | `window` | Bounded key range inside a card-like view. | Replace only rows whose `displayOrderKey` falls inside the declared window bounds. Missing bounds make the snapshot invalid. |
| `host.registry` | `view` | Complete host registry for the supplied `viewParamsKey`. | Replace every local host row for that registry view with the snapshot rows. Rows absent from the snapshot are deleted. |
| `thread.detail` | `thread` | Complete detail view for one thread. | Replace every local row for that `sourceHostID`, `threadID`, and `viewParamsKey`. |
| `thread.detail` | `window` | Bounded key range inside one thread. | Replace only rows whose `displayOrderKey` falls inside the declared window bounds. Missing bounds make the snapshot invalid. |

Dock and Archive stream envelopes omit `threadID` at the snapshot/update
envelope level unless the update is explicitly scoped to one thread. Card rows
carry `payload.threadID` and, when useful for validation, an envelope
`threadID`. Swift must not infer a Dock/Archive snapshot's authority from the
presence or absence of row IDs; it uses `view`, `scope`, `sourceHostID`,
`viewParamsKey`, and window bounds.

For every view:

- `snapshot` with `scope: "view"` or `scope: "host"` is authoritative for its
  declared scope.
- `snapshot` with `scope: "window"` is authoritative only for the declared
  order-key range.
- `upsert` inserts or replaces exact `projectionID`s.
- `delete` removes exact `projectionID`s.
- `heartbeat` proves continuity only; it never changes membership.
- `resyncRequired` makes the active view stale until the matching resync route
  returns a replacement snapshot.

### Dock And Archive Projection DTOs

Dock and Archive use the same required-field rigor as Thread Detail. The only
difference is the typed card payload and default scope.

`DockSnapshotDTO` and `ArchiveSnapshotDTO`:

```json
{
  "kind": "snapshot",
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "dock",
  "epoch": "projection-...",
  "seq": 1,
  "scope": "view",
  "viewParamsKey": "sha256:...",
  "complete": true,
  "order": "displayOrderKeyAscending",
  "freshness": {
    "state": "fresh"
  },
  "rows": []
}
```

`DockUpdateDTO` and `ArchiveUpdateDTO`:

```json
{
  "kind": "upsert",
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "dock",
  "epoch": "projection-...",
  "seq": 2,
  "scope": "view",
  "viewParamsKey": "sha256:...",
  "order": "displayOrderKeyAscending",
  "rows": [],
  "projectionIDs": []
}
```

Required fields by update kind are the same as Thread Detail, with `threadID`
omitted unless the card update is explicitly scoped to one thread. `delete`
uses `projectionIDs`; card streams do not have `deleteCardIDs`. `upsert` uses
`rows`; card streams do not have `upsertCards`.

Thread-card row payload:

```json
{
  "threadID": "019e...",
  "backendSessionID": "019e...",
  "title": "Hill climb experiment",
  "displaySummary": "Current work summary",
  "status": "running",
  "sourceKind": "human",
  "lane": "human",
  "archiveState": "active",
  "repository": "codex-client",
  "workingDirectory": "/Users/aelaguiz/workspace/codex-client",
  "branch": "main",
  "activityAt": "2026-06-01T19:50:00.000Z",
  "activityAtMs": 1780343400000,
  "relationship": "root",
  "forkedFromID": null,
  "hostDisplayName": "Amir M5",
  "hostEndpoint": "amir-m5.fairy-salmon.ts.net:4510"
}
```

`rowRole` for Dock/Archive cards is `threadCard`. The card `projectionID` is:

```text
host:<sourceHostID>/thread:<threadID>/row:threadCard
```

Dock and Archive thread-card `displayOrderKey` is:

```text
<invertedActivityMillis>|<statusPriority>|<safeProjectionID>
```

Field rules:

- `activityMillis` is the relay-proven newest activity time for the thread.
- `invertedActivityMillis = 9999999999999999 - activityMillis`, left-padded to
  16 decimal digits.
- `statusPriority` is left-padded to 4 decimal digits and is relay-owned:
  needs-approval/user-input before running before idle before error before
  unknown/dormant when activity ties exactly.
- `safeProjectionID` is the canonical escaped `projectionID` tie breaker.
- Swift compares the full string only; it never parses it back into fields.

Normative `statusPriority` values:

| Card status | Priority |
| --- | --- |
| `needsInput` | `0000` |
| `needsApproval` | `0000` |
| `running` | `0001` |
| `idle` | `0002` |
| `error` | `0003` |
| `unknown` | `0004` |
| any unrecognized active status | `0004` |
| `dormant` / not loaded | `0005` |

### Archive Cleanup Projection View

Archive Cleanup is its own relay-projected view:

```text
view: "archive.cleanup"
```

Routes:

- `archive/cleanup/read`
- `archive/cleanup/subscribe`
- `archive/cleanup/update`
- `archive/cleanup/resync`

Archive Cleanup rows use the same `threadCard` row payload and the same card
`projectionID` as Dock and Archive:

```text
host:<sourceHostID>/thread:<threadID>/row:threadCard
```

Cleanup membership is view membership, not row identity. The cleanup view
selects active cleanup candidates through relay-owned `viewParams`:

```json
{
  "viewParams": {
    "candidateSource": "activeDock",
    "hostIDs": null,
    "statusKinds": null,
    "olderThan": null,
    "repositorySearch": "",
    "branchSearch": "",
    "textSearch": "",
    "includeDiagnostics": true,
    "sort": "displayOrderKeyAscending"
  }
}
```

`viewParamsKey` is required on every Archive Cleanup snapshot/update. Proof for
Archive Cleanup compares simulator UI to `view: "archive.cleanup"` witness
envelopes with the same `viewParamsKey`. It never treats a raw Dock stream or a
client-filtered Dock list as cleanup truth.

### Host Projection Rows

`host:<sourceHostID>/row:host` is a real projection row, not decorative
metadata. It exists so host identity, labels, connectivity summaries, and proof
state have the same identity law as thread cards and detail rows.

Host row envelope:

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "host.registry",
  "projectionID": "host:amir-m5/row:host",
  "sourceRef": "host:amir-m5",
  "rowRole": "host",
  "revision": 3,
  "displayOrderKey": "host|amir-m5",
  "freshness": {
    "state": "fresh"
  },
  "payload": {
    "sourceHostID": "amir-m5",
    "displayName": "Amir M5",
    "endpointLabels": ["amir-m5.fairy-salmon.ts.net:4510"],
    "connectivityState": "online",
    "lastContactAt": "2026-06-01T19:50:00.000Z"
  }
}
```

Rules:

- host rows are keyed only by `sourceHostID`.
- endpoint, Bonjour, LAN, Tailscale, and saved-phone labels are payload labels,
  never identity.
- phone saved host configs are bootstrap connection records only. They may have
  local config IDs for settings UI, but those IDs never appear in
  `sourceHostID`, `sourceRef`, `projectionID`, `displayOrderKey`, or proof
  witnesses.
- host row ordering is stable label order unless a future host view defines a
  relay-owned `displayOrderKey`.
- thread-card rows reference the host row through `sourceHostID`; they do not
  embed a second host identity namespace.

Host Registry routes use the same projection grammar:

- `host/registry/read`
- `host/registry/subscribe`
- `host/registry/update`
- `host/registry/resync`

`HostRegistrySnapshotDTO` and `HostRegistryUpdateDTO` are the same shared
snapshot/update envelopes with `view: "host.registry"` and host-row payloads.
If the app shows configured endpoints before a relay connection exists, that is
settings UI backed by phone config, not a projection view and not evidence of
Codex source identity. Once connected, any user-visible Codex source identity,
label, connectivity summary, or proof state comes from host projection rows.

### Identity Law

These are architectural laws, not implementation suggestions:

1. No production visible row/card ID may be generated from body text, timestamp,
   list offset alone, local UI state, Swift object lifetime, WebSocket request
   ID alone, `UUID()`, or `crypto.randomUUID()`.
2. A supported raw Codex item without enough identity does not become a normal
   message row. It becomes a stable diagnostic row or a `resyncRequired` update.
3. Live, history, reconnect, canonical reread, server request, request
   resolution, and proof paths all call the same relay projection normalizer.
4. Streaming and settled forms of one Codex item share one `projectionID`.
5. Request controls are attached to the same `projectionID` as their visible
   row. `requestID` is only the response routing key.
6. Sorting is by relay `displayOrderKey` only. Swift does not rebuild newest
   ordering from raw timestamps or turn/item indexes.
7. Local metadata can decorate projection rows, but it cannot create production
   rows or override projection identity/order/freshness.
8. Diagnostics and health routes can explain state, but cannot be accepted as
   data truth for the UI.
9. Test fixtures must use projection DTOs or the relay normalizer. A fake that
   invents message IDs is testing a different product.
10. Proof scripts must compare UI state against relay projection snapshots or
    updates, not against a second reconstruction of raw Codex truth.
11. Acceptance proof cannot contain `expectedMessageEventIDs`, fixture-computed
    visible IDs, or any other expected-ID list that was not emitted by the relay
    projection ledger.
12. Local metadata, including pin, hide, archive, and user filter state, may
    request a relay view or decorate returned rows. It cannot change the row set
    used by acceptance proof outside the relay projection view being proved.

Pin and local metadata rule: cached pinned/local display snapshots are never
authoritative after projection cutover. A pin can render chrome on an existing
projection row, or a future relay-owned pinned view can be added with explicit
`viewParamsKey` and witness proof. Swift cannot use local pin state to create a
second row order, second membership set, or alternate cache of projection rows.

### Relay Projection Engine

The relay should have one pure projection engine that is independent from
WebSockets, timers, SQLite, and Swift:

```text
normalizeRawCodexSource(rawSource, context) -> ProjectionRow[]
applyProjectionOperation(ledger, operation) -> ledger
projectDockView(ledger, scope) -> ProjectionSnapshot<DockCard>
projectArchiveView(ledger, scope) -> ProjectionSnapshot<DockCard>
projectHostRegistryView(ledger, scope) -> ProjectionSnapshot<HostRow>
projectThreadDetailView(ledger, scope) -> ProjectionSnapshot<ThreadDetailRow>
```

That engine has one production module, not one module per screen. The target
module is:

```text
scripts/dock-relay-projection-engine.mjs
```

All production helpers named like `projectionIDFor*`, `sourceRefFor*`,
`displayOrderKeyFor*`, and row-role mappers live there or under that module's
owned package directory. View-specific relay files such as Thread Detail
ledger, Dock state, Archive state, Archive Cleanup, and simulator fixtures may
call the engine; they must not define their own visible identity grammar. Tests
may import the pure engine for unit coverage, but acceptance proof cannot use
that import as its expected-ID oracle. Acceptance proof reads IDs from emitted
projection envelopes only.

Runtime code does I/O:

- read raw app-server state.
- maintain upstream live sessions.
- receive server requests.
- write/read SQLite projection state.
- publish downstream JSON-RPC snapshots and updates.

The projection engine does identity, role mapping, order keys, freshness, and
ledger operations. It has no socket state and no UI state. That is what makes
it testable and prevents "one more path" from becoming another identity owner.

### Reference Architecture Components

The clean permanent architecture has these components and only these
responsibilities:

| Component | Owns | Must not own |
| --- | --- | --- |
| Raw Codex adapters | Fetching and subscribing to raw upstream state: `thread/list`, `thread/read`, `thread/turns/list`, `thread/resume`, live notifications, server requests. | Visible identity, UI order, freshness labels, or Swift DTO shape. |
| Source host identity provider | Stable `sourceHostID` for the Codex source. | Endpoint labels, relay process identity, phone host config, or display names. |
| Projection engine | `sourceRef`, `projectionID`, `rowRole`, `displayOrderKey`, freshness, diagnostics, and ledger operations. | WebSocket lifecycle, SQLite I/O, Swift rendering, or test-only shortcuts. |
| Projection store | Materialized projection rows, view memberships, epochs, sequence numbers, and cache contract versions. | Raw Codex as durable truth or screen-specific identity grammars. |
| View stream routers | `dock/*`, `archive/*`, `archive/cleanup/*`, `host/registry/*`, `thread/detail/*` snapshots, updates, heartbeats, and resyncs over JSON-RPC. | Recomputing row identity or order. |
| Swift projection stores | Applying projection snapshots/updates and publishing render state. | Parsing raw Codex display rows, recovering missing identity, or fallback sorting. |
| Phone saved host config | Bootstrap endpoint list used to connect to relays. | `sourceHostID`, `projectionID`, host row identity, or freshness proof. |
| UI and automation | Rendering projection rows and exposing `projectionID`-based accessibility IDs. | Creating production row IDs. |
| Proof tools | Comparing UI dumps to relay projection snapshots/updates. | Building a second raw Codex oracle for display identity. |

The projection store should not be three unrelated caches. Use one canonical
projection storage model:

```text
projection_contracts
  sourceHostID
  schemaVersion
  identityVersion
  projectionEngineVersion
  createdAt

projection_rows
  sourceHostID
  projectionID
  sourceRef
  rowRole
  revision
  displayOrderKey
  freshness
  payloadJSON
  updatedAt

projection_view_memberships
  sourceHostID
  view
  scope
  projectionID
  membershipState
  displayOrderKey

projection_stream_epochs
  sourceHostID
  view
  scope
  epoch
  seq
  complete
  freshness
```

Dock active rows, Archive rows, and Thread Detail rows are all projection rows
plus view membership. Moving a card from Dock to Archive changes membership or
payload state; it does not invent a second card identity.

The existing SQLite `threads` table can be migrated into this model or replaced
outright. The elegant target is the universal model above because it removes
screen-specific identity storage instead of teaching three tables the same
rules.

### Dock And Archive Migration Is Normative

Dock and Archive are not allowed to stay on a parallel card stream grammar.
They must move from the current card v2 stream to the shared projection stream.

Current card v2 shape:

```text
kind: snapshot | delta | heartbeat
id: <logicalHostID>::<threadID>
logicalHostID
stateGeneration
cards / upsertCards / deleteCardIDs
```

Target projection shape:

```text
kind: snapshot | upsert | delete | heartbeat | resyncRequired
projectionID: host:<sourceHostID>/thread:<threadID>/row:threadCard
sourceHostID
identityVersion
projectionEngineVersion
seq
rows / projectionIDs
```

Normative mapping:

| Current v2 field/concept | Target projection contract |
| --- | --- |
| `DockThreadCardDTO.id` | Removed as independent identity or transition-equal to `projectionID`; final identity is `projectionID`. |
| `logicalHostID` | Payload alias only during migration; must validate one-to-one against `sourceHostID` and cannot appear in identity decisions. |
| `delta` | Replaced by explicit `upsert` and `delete` operations. |
| `upsertCards` | `rows` where each row has the shared projection envelope plus thread-card payload. |
| `deleteCardIDs` | `projectionIDs`. |
| `stateGeneration` | Removed; `epoch` and `seq` are the stream continuity contract. |
| `baseSeq` | Removed unless the shared projection contract later adopts it for all views. Do not keep it Dock-only. |
| `orderKey` | Replaced by `displayOrderKey`, opaque to Swift. |
| `freshness.status` | Replaced by shared `freshness.state`; old names may exist only inside migration fixtures. |
| archive membership | `projection_view_memberships`, not a second card identity. |

Cutover rule:

- A final implementation may use a temporary translation layer inside the relay,
  but the phone-facing production route must emit the target projection shape
  before acceptance.
- `dock/subscribe`, `dock/resync`, `archive/subscribe`, and `archive/resync`
  may keep their route names. Route names are transport. The payload grammar is
  what must converge.
- No Phase 7 pass is allowed while Swift display code, proof scripts, or schema
  fixtures still accept card v2 `delta`/`logicalHostID::threadID` as production
  display truth.
- If a compatibility payload carries both `id` and `projectionID`, they must be
  byte-for-byte equal or the client must reject the payload and request resync.

### Contract Source Of Truth

The contract source should be one schema/generator package, not hand-synced
Swift and JS shapes.

Required artifacts:

- one JSON Schema or equivalent schema source for the shared projection
  envelope.
- typed payload schemas for Dock card rows and Thread Detail rows.
- generated or schema-checked Swift DTOs.
- Node runtime validation for emitted projection snapshots/updates in tests.
- fixture corpus generated from the relay projection normalizer and consumed by
  Swift tests.

Normative package shape:

```text
contract/projection/projection-envelope.schema.json
contract/projection/projection-snapshot.schema.json
contract/projection/projection-update.schema.json
contract/projection/payloads/dock-thread-card.schema.json
contract/projection/payloads/thread-detail-row.schema.json
contract/projection/payloads/host-row.schema.json
contract/projection/fixtures/*.json
scripts/dock-relay-projection-engine.mjs
scripts/generate-projection-contract.mjs
scripts/check-projection-contract.mjs
CodexDock/AppServer/ProjectionDTO.swift
```

The existing `contract/dock/dock-thread-card.schema.json` is card-v2 history
after cutover. It must be replaced or demoted by the projection package above,
not kept as a second phone-facing display schema.

No phone-facing production route, Swift display DTO, proof schema, or acceptance
fixture may keep card-v2 as a parallel display contract after cutover. If
card-v2 fixtures remain for migration history, they must prove byte-for-byte
equivalence to emitted projection rows and must be excluded from acceptance
truth.

This is not a linter. It is a contract gate: if a row shape, identity version,
enum, view name, or update grammar changes, Node and Swift tests fail until the
single source and fixtures move together.

### Cache And Version Rule

The relay SQLite cache must be treated as a materialized projection, not a
source of truth.

Add one projection cache version that combines:

```text
schemaVersion
identityVersion
projectionEngineVersion
sourceHostID
```

If any of those change, existing projection rows for that host/view are invalid
and must be rebuilt from raw Codex state before being served as fresh. The relay
may keep old rows visible only as explicitly stale rows, never as fresh rows
under a new identity contract.

This is the simple permanent version of "delete the caches." Cache invalidation
is not optional cleanup; it is part of identity correctness.

### Revision And Version Bump Policy

`revision`, `schemaVersion`, `identityVersion`, and
`projectionEngineVersion` are separate levers:

| Field | Bump when | Must not be used for |
| --- | --- | --- |
| `revision` | The content, freshness, render state, request status, or payload for the same `projectionID` changes. | Changing identity or cache contract. |
| `schemaVersion` | The projection wire shape changes. | Changing only row identity rules. |
| `identityVersion` | The algorithm for `sourceRef` or `projectionID` changes for any visible row class. | Routine payload/render updates. |
| `projectionEngineVersion` | The projection logic changes output membership, order, freshness, row roles, view params, or payload interpretation without changing wire shape or ID grammar. | Per-row content updates. |

`revision` is monotonic per `projectionID` within a source host and active
projection cache contract. A snapshot may reset local client state, but it must
not make the same `projectionID` appear older than a previously accepted
revision inside the same `epoch` unless the relay starts a new `epoch` and
marks the prior view stale.

Cache validity uses the version tuple, not `revision`:

```text
schemaVersion + identityVersion + projectionEngineVersion + sourceHostID
```

When `identityVersion` or `projectionEngineVersion` changes, old materialized
rows cannot be silently translated by Swift. The relay must rebuild them or
serve them as explicitly stale with a resync path.

### Upsert Invariants

For a given `projectionID`, these envelope fields are immutable inside one
identity version:

- `sourceHostID`
- `sourceRef`
- `rowRole`
- `threadID` when present
- `schemaVersion`
- `identityVersion`
- `view`

If an `upsert` repeats a `projectionID` with any of those fields changed, the
client must reject the update, mark the view stale, and request resync. It must
not choose one source locally.

`revision` must increase when payload, freshness, render state, request status,
or diagnostic content changes for the same `projectionID`. If an `upsert`
inside the same epoch carries a lower `revision`, the client rejects it as stale
or requests resync. If the same `revision` carries different payload content,
the client treats it as a projection contract violation and requests resync.

### Epoch And Watermark Rules

`epoch` is a relay-generated stream generation identifier. It is unique within
`sourceHostID + view + scope + viewParamsKey` and is created by the relay when a
projection stream starts, resyncs after stale state, changes
`identityVersion`, changes `projectionEngineVersion`, or detects unrecoverable
sequence/source loss. A new `epoch` is valid only when delivered with a
replacement snapshot. Updates cannot silently hop epochs.

`sourceWatermark` is upstream freshness evidence, not row identity. It records
the raw Codex history/live point the relay has normalized into the projection
ledger. Swift may display or log it as freshness context, but it cannot use it
to create, sort, dedupe, or delete rows. If the relay cannot prove a watermark
is still compatible with the current projection cache contract, the affected
view is stale until resync.

### Commands Are Not Display Truth

Mutation routes stay separate:

- `turn/start`
- `turn/steer`
- `turn/interrupt`
- request-card responses
- archive/unarchive

Commands can cause the relay projection ledger to change, but commands do not
directly create Swift display rows.

Projection v1 bans Swift-created optimistic display rows. If the product later
wants optimistic outbound rows, that must be a deliberate relay-owned contract
extension, not a local UI shortcut:

```text
clientMutationID -> relay pending projection row -> atomic supersession to canonical sourceRef/projectionID
```

That extension must define the atomic supersession update or equivalent
snapshot replacement before implementation. That avoids recreating the current
duplicate shape as "one optimistic Swift row plus one canonical relay row."

If that extension is added, the contract must include:

- `clientMutationID` generated by the client and sent only as a mutation
  correlation token.
- a relay-created pending `projectionID` in the same `sourceHostID` and
  `threadID` namespace.
- `supersedesProjectionID` or a replacement snapshot that atomically removes
  the pending row when canonical `turnID` and `itemID` arrive.
- proof that pending and canonical states never render at the same time.
- cache invalidation rules for pending rows on reconnect, failed send, and
  relay restart.

Until that extension exists, no Swift screen may create a visible optimistic
message row.

### Post-Cutover Route Policy

After cutover, the phone-facing contract should be:

- projection view routes for data display.
- mutation routes for commands.
- diagnostics routes for diagnostics only.

Raw Codex routes are relay internals. The phone should not call raw
`thread/read`, `thread/turns/list`, or `thread/resume` as display proof. If a
temporary compatibility route is needed during migration, it must be behind a
named migration phase and deleted before acceptance. It cannot be used by
simulator proof or production Thread Detail display.

The same rule applies to generic JSON-RPC escape hatches. Production display
stores and display protocols must not call `AppServerClient.sendRequest(method:)`
or any equivalent arbitrary method-string API for display data. Typed mutation
routes may use generic JSON-RPC plumbing internally, but display reads must go
through typed projection routes and projection DTOs.

Raw Codex DTOs are not display DTOs after cutover. `ThreadRead*`,
`ThreadTurnsList*`, `ThreadResume*`, raw turn/item JSON, and any equivalent
raw-app-server shapes may live only inside relay-internal adapters or
quarantined diagnostics/tests. They must not be decoded by production Swift
display stores, simulator proof oracles, or acceptance fixtures as visible row
truth.

Final post-cutover allow-list for production phone display:

- `dock/subscribe`, `dock/update`, `dock/resync`
- `archive/subscribe`, `archive/update`, `archive/resync`
- `archive/cleanup/read`, `archive/cleanup/subscribe`,
  `archive/cleanup/update`, `archive/cleanup/resync`
- `host/registry/read`, `host/registry/subscribe`,
  `host/registry/update`, `host/registry/resync`
- `thread/detail/read`, `thread/detail/subscribe`,
  `thread/detail/update`, `thread/detail/resync`

Final post-cutover forbidden phone display routes:

- `thread/read`
- `thread/turns/list`
- `thread/resume`

Those raw routes may remain only as relay-internal upstream adapter calls,
loopback-only diagnostics, or explicit migration commands that are not linked
from production Swift display protocols and are not accepted as proof.

Acceptance rule: after projection cutover, any production Swift display method
that can call raw `thread/read`, `thread/turns/list`, or `thread/resume` is a
blocking architecture failure. Those routes may exist only behind relay-internal
adapter boundaries or loopback-only diagnostics with names that make them
impossible to confuse with phone display truth.

Acceptance rule: after projection cutover, any production Swift display method
that can choose an arbitrary display read method string is also a blocking
architecture failure. The app can retain low-level JSON-RPC transport plumbing,
but display repositories/stores expose typed projection operations only.

### Testing Methodology For The Whole Class

The test suite needs to prove time, not only shape.

Required layers:

1. Pure projection normalizer tests: every raw Codex shape maps to exact
   `sourceRef`, `projectionID`, row role, and `displayOrderKey`.
2. Temporal permutation tests: live first, history first, stale snapshot first,
   canonical catch-up, reconnect, duplicate notification, request resolution,
   and cache rebuild all converge to the same ledger.
3. Contract tests: every emitted projection snapshot/update validates against
   the schema and decodes in Swift.
4. Swift store tests: Swift applies snapshots/upserts/deletes/heartbeats by
   epoch and sequence; it never calls raw normalizers for production display.
5. Controlled relay-plus-simulator proof: a fixture app-server emits realistic
   sequences, the real relay publishes projection updates, the installed app
   renders them, and `sim-ui-dump` compares accessibility state to the relay
   projection ledger.
6. Real relay smoke/soak: current Codex sessions are sampled through the same
   projection routes and compared to the current simulator UI dump.

Pass means:

- visible IDs match relay projection IDs.
- order matches relay `displayOrderKey`.
- stale data is labeled stale.
- no proof path reconstructs expected identity from raw Codex payloads.

### Projection Witness Plane

Acceptance proof needs a canonical witness for "what the relay actually emitted
to the app." It cannot use fixture-side helpers that happen to share projection
ID code, because that still leaves a second expected-ID oracle.

The proof witness is a retained stream of relay-emitted projection snapshots
and updates captured during the simulator run:

```text
fixture raw Codex input
  -> relay projection engine
  -> downstream projection route observed by app
  -> projection witness recorder
  -> simulator accessibility dump comparison
```

Required capture mechanism:

- primary path: the proof harness attaches a projection witness recorder to the
  actual downstream JSON-RPC projection stream for the simulator app session
  before opening the UI; or
- the proof harness reads a loopback-only relay diagnostic export, for example
  `projection/witness/read`, for the exact `sourceHostID`, `view`, `scope`,
  `threadID`, `viewParamsKey`, and `epoch` under test.

The second mechanism is diagnostic plumbing, not a display route. It may export
only relay-emitted projection envelopes that already went through the same
projection engine as the app path. It must not compute expected IDs from
fixtures.

`projection/witness/read` is acceptable only if it returns byte-for-byte
equivalent projection envelopes retained from the downstream emitter or a
retained emitter log. It must not rebuild expected rows from SQLite, raw Codex
payloads, fixture JSON, or helper imports at proof time. If downstream capture
and diagnostic export disagree, downstream capture wins and the run fails.

Allowed witness sources:

- the same downstream WebSocket projection snapshots/updates delivered to the
  simulator app;
- a loopback-only relay diagnostic export of retained downstream-emitted
  projection envelopes for the exact `sourceHostID`, `view`, `scope`,
  `threadID`, `viewParamsKey`, and `epoch` under test;
- retained relay structured logs captured at the downstream emitter boundary
  that include the same serialized projection envelope sent downstream, the
  same stream metadata, and an explicit `byteEquivalentToDownstream: true`
  marker, with prompt/body text redacted where required.

The active projection store, SQLite, fixture data, and raw Codex adapters are
not witness sources. They can explain why a projection was emitted, but
acceptance proof compares the UI only to envelopes the relay actually emitted
to the app, or a byte-for-byte retained copy of those envelopes. Downstream
WebSocket capture is the primary witness; diagnostic exports and structured
logs are supplemental retained copies only.

Forbidden witness sources:

- fixture code calling `projectionIDForItem` or `projectionIDForRequest` to
  construct expected IDs;
- raw `thread/read`, `thread/turns/list`, or `thread/resume` truth rebuilt into
  expected UI IDs;
- `expectedMessageEventIDs`;
- `expectedMessageProjectionIDs` unless the field is populated directly from
  the projection witness stream emitted by the relay under test;
- accessibility ID strings reverse-engineered back into expected projection IDs.

Required proof record fields:

```json
{
  "projectionWitness": {
    "source": "downstream-projection-stream",
    "sourceHostID": "amir-m5",
    "view": "thread.detail",
    "scope": "thread",
    "threadID": "019e...",
    "viewParamsKey": "sha256:...",
    "epoch": "projection-...",
    "lastSeq": 42,
    "projectionIDs": []
  }
}
```

The simulator UI comparison consumes `projectionWitness.projectionIDs`. The
fixture may still emit raw Codex input, but it must not separately declare what
the UI should show.

Loopback-only witness export contract:

`projection/witness/read` request:

```json
{
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "scope": "thread",
  "threadID": "019e...",
  "viewParamsKey": "sha256:...",
  "epoch": "projection-...",
  "fromSeq": 1,
  "throughSeq": null
}
```

Response:

```json
{
  "source": "retained-downstream-emitter-log",
  "byteEquivalentToDownstream": true,
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "scope": "thread",
  "threadID": "019e...",
  "viewParamsKey": "sha256:...",
  "epoch": "projection-...",
  "lastSeq": 42,
  "envelopes": [],
  "projectionIDs": []
}
```

Rules:

- `projection/witness/read` is not in the phone production display allow-list.
- It is loopback/local-test only and must fail closed outside test/diagnostic
  configuration.
- `envelopes` are retained emitted projection snapshots/updates, not
  recomputed projections.
- `byteEquivalentToDownstream` must be `true`; otherwise the proof cannot use
  this route as witness evidence.
- `projectionIDs` are derived from `envelopes` by reading emitted row IDs only.

### Why This Is The Permanent Architecture

This architecture removes the cause, not the symptom.

The cause is not one bad field lookup. The cause is multiple code paths being
allowed to answer the same question:

```text
What visible thing is this?
```

The permanent answer is that only the relay projection engine answers that
question. Everything else renders, stores, compares, or transports the answer.

That is the smallest concept count that actually closes the class:

- one identity owner.
- one ordering owner.
- one freshness owner.
- one update grammar.
- one proof source.

Anything less leaves a second place that can drift.

The most elegant permanent fix is to stop making the iPhone infer visible
identity from raw Codex payloads. The relay should own one canonical projection
ledger, and the app should render that ledger.

That sounds bigger than the fallback patch, but it removes the entire class of
bugs instead of moving it around.

### Target Shape

Create one relay-owned projection contract with typed Thread Detail payloads:

- `ThreadDetailEventDTO`
- `ThreadDetailSnapshotDTO`
- `ThreadDetailUpdateDTO`
- one canonical identity function used by every projection producer

The Swift client should no longer build visible message IDs from raw
`thread/turns/list`, `thread/resume` notifications, or server request payloads.
It should receive already-normalized projection rows from the relay, store them
by the relay-provided `projectionID`, and render them.

### Why The Relay Should Own This

The relay is the right architectural owner because it is already the boundary
between the raw Codex app-server and every client path.

Today the identity rules exist in more than one place:

- Swift production code builds `ThreadEvent.id` in
  `CodexDock/Models/ThreadEvent.swift`.
- Swift merge code compares `ThreadEvent.id` and a secondary stream key in
  `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`.
- JS proof code independently predicts projection IDs in
  `scripts/codex-dock-live-filter-truth.mjs`.
- JS simulator proof code independently turns projection IDs into accessibility IDs
  in `scripts/dock-relay-simulator-ui-sync-proof.mjs`.

That is not one contract. It is several parallel guesses.

If the relay emits normalized projection rows, Swift and proof scripts stop
copying identity logic. The proof can compare the UI to the same relay-emitted
projection IDs the app was supposed to render.

### New Source Of Truth

The source of truth should be:

`raw Codex thread data -> relay detail normalizer -> relay projection ledger -> app UI`

The source of truth should not be:

`raw Codex thread data -> Swift normalizer -> app UI`

and also:

`raw Codex thread data -> JS proof normalizer -> expected UI`

The app can still send commands through existing relay routes such as
`turn/start`, `turn/steer`, and `turn/interrupt`. The architectural change is
about display truth, not command transport.

## Detail Event Contract

### `ThreadDetailEventDTO`

Each visible Thread Detail row is one shared projection row DTO with a typed
Thread Detail payload:

Thread Detail uses the shared projection stream field name `rows`. The older
`events` array name is pre-cutover vocabulary only and must not survive in the
final phone-facing projection contract.

The final wire shape uses a nested `payload`. Do not flatten payload fields into
the envelope. A flattened `ThreadDetailEventDTO` is pre-cutover shorthand and
must not be generated by the accepted schema package.

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "threadID": "019e...",
  "projectionID": "host:amir-m5/thread:019e.../turn:019e.../item:item-123/row:userMessage",
  "sourceRef": "host:amir-m5/thread:019e.../turn:019e.../item:item-123",
  "rowRole": "userMessage",
  "revision": 7,
  "displayOrderKey": "9998239345599999|0000000042|9999999999|9999999999|host%3Aamir-m5%2Fthread%3A019e...%2Fturn%3A019e...%2Fitem%3Aitem-123%2Frow%3AuserMessage",
  "freshness": {
    "state": "fresh",
    "sourceWatermark": "codex-source-..."
  },
  "payload": {
    "turnID": "019e...",
    "itemID": "item-123",
    "itemType": "userMessage",
    "visibility": "message",
    "renderKind": "userMessage",
    "title": "User message",
    "body": "message text",
    "eventTime": "2026-06-01T17:30:00.000Z",
    "activityTime": "2026-06-01T17:30:00.000Z",
    "turnOrder": 42,
    "itemOrder": 0,
    "rowOrder": 0,
    "renderState": "settled",
    "requestID": null,
    "diagnostic": null
  }
}
```

The exact spelling should be locked in the protocol doc before implementation.
The required fields are:

- `schemaVersion`: DTO shape version.
- `identityVersion`: identity algorithm version.
- `sourceHostID`: stable Codex source host identity.
- `view`: projection view name. For Thread Detail this is `thread.detail`.
- `threadID`: the thread this row belongs to.
- `projectionID`: stable row identity, generated only by the relay normalizer.
- `sourceRef`: stable raw Codex fact identity used to derive `projectionID`.
- `rowRole`: semantic visible row role.
- `revision`: content revision for the same `projectionID`.
- `displayOrderKey`: opaque relay-generated ascending sort key.
- `freshness`: relay freshness state for this row.
- `payload.turnID`: stable Codex turn identity when the row comes from a turn
  item.
- `payload.itemID`: stable Codex item identity when the row comes from a turn
  item.
- `payload.itemType`: raw Codex item type, for debugging and contract tests.
- `payload.visibility`: message, thinking, tooling, request, system, or
  unknown.
- `payload.renderKind`: Swift-compatible render kind: userMessage, agentMessage,
  command, output, request, system, or unknown.
- `payload.body`: visible text.
- `payload.eventTime`: display time.
- `payload.activityTime`: ordering time.
- `payload.turnOrder`, `payload.itemOrder`, `payload.rowOrder`: debug fields
  used to explain
  `displayOrderKey`; the app must not reconstruct sorting from them.
- `payload.renderState`: live, streaming, settled, stale, or diagnostic.
- `payload.requestID`: only for request-backed rows.
- `payload.diagnostic`: structured non-secret diagnostic metadata only for
  diagnostic rows.

### Row Roles

The first version should include these row roles:

- `userMessage`
- `agentMessage`
- `plan`
- `reasoning`
- `command`
- `commandOutput`
- `fileChange`
- `toolCall`
- `request`
- `system`
- `unknown`

The important rule is that `rowRole` is part of identity. One Codex item can
produce multiple visible rows only when the row role is different. For example,
a `commandExecution` item may produce one `command` row and one `commandOutput`
row.

The relay owns the mapping from `rowRole` to UI semantics:

| `rowRole` | `renderKind` | `visibility` | Identity source |
| --- | --- | --- | --- |
| `userMessage` | `userMessage` | `message` | turn item |
| `agentMessage` | `agentMessage` | `message` | turn item |
| `plan` | `agentMessage` | `thinking` | turn item |
| `reasoning` | `agentMessage` | `thinking` | turn item |
| `command` | `command` | `tooling` | turn item |
| `commandOutput` | `output` | `tooling` | turn item |
| `fileChange` | `request` | `request` | turn item |
| `toolCall` | `command` | `tooling` | turn item |
| `request` | `request` | `request` | server request |
| `system` | `system` | `system` | thread-level event |
| `unknown` | `unknown` | `unknown` | diagnostic only |

### Projection ID Rule

For supported Codex turn items:

```text
host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/row:<rowRole>
```

For server requests:

```text
host:<sourceHostID>/thread:<threadID>/request:<requestID>/row:request
```

For supported item-backed request rows that also carry turn and item identity:

```text
host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/request:<requestID>/row:request
```

For thread-level system rows:

```text
host:<sourceHostID>/thread:<threadID>/system:<systemEventKind>/<sourceSequenceOrTimestamp>
```

For malformed raw data:

```text
host:<sourceHostID>/thread:<threadID>/diagnostic:<stableHash>/row:unknown
```

`stableHash` must be SHA-256 over non-secret structural fields only:

```text
identityVersion
sourceHostID
threadID
raw method or item type
candidate turnID
candidate itemID
candidate requestID
identity error code
```

It must not include prompt text, transcript text, delta text, command output,
raw audio, bearer tokens, or full JSON payloads.

Thread-level system rows use this initial `systemEventKind` catalog:

- `threadStatusChanged`
- `threadClosed`
- `identityGap`
- `identityConflict`
- `resyncRequired`
- `upstreamRecovered`

Adding a new system kind requires updating the protocol reference, relay
normalizer tests, and UI/proof expectations in the same change.

No supported user, agent, command, output, plan, reasoning, tool, file-change,
or request row may use `UUID()` or `crypto.randomUUID()` as visible identity.
Random IDs are allowed only for internal subscription handles, local task
tokens, or diagnostics that never represent a Codex message.

### Missing Identity Rule

If a raw Codex payload claims to be a known message-like item but lacks the
identity needed to produce a stable projection ID, the normalizer must not create a
normal visible message row with a random ID.

It must choose one of these explicit outcomes:

1. Recover identity from another valid location in the same payload.
2. Wait for a later canonical snapshot that has identity.
3. Emit a non-message diagnostic row with a stable hash and `renderState:
   "diagnostic"`.
4. Emit a `resyncRequired` update if the missing identity means the stream is
   no longer trustworthy.

This is the guardrail that prevents duplicates from coming back under a new
shape.

### Identity Recovery Precedence

The relay normalizer must use an explicit ordered identity lookup. It must also
detect conflicts. If two present fields disagree, the normalizer must emit
`resyncRequired` or a diagnostic row; it must not silently choose one.

For historical turn items from `thread/turns/list`:

| Field | Source order |
| --- | --- |
| `threadID` | route param, then thread object id |
| `turnID` | `turn.id`, then `turn.turnId`, then `turn.turnID` |
| `itemID` | `item.id` only |
| `itemType` | `item.type` |

For live deltas such as `item/agentMessage/delta`,
`item/reasoning/textDelta`, and `item/commandExecution/outputDelta`:

| Field | Source order |
| --- | --- |
| `threadID` | `params.threadId` |
| `turnID` | `params.turnId`, then `params.turnID` |
| `itemID` | `params.itemId`, then `params.itemID` |
| `rowRole` | method-to-role table, not method suffix |

For live full item notifications `item/started` and `item/completed`:

| Field | Source order |
| --- | --- |
| `threadID` | `params.threadId` |
| `turnID` | `params.turnId`, then `params.turnID`, then `params.turn.id`, then `params.item.turnId`, then `params.item.turnID` |
| `itemID` | `params.itemId`, then `params.itemID`, then `params.item.id` |
| `itemType` | `params.item.type` |

For server requests:

| Field | Source order |
| --- | --- |
| `threadID` | `params.threadId` |
| `requestID` | JSON-RPC request `id` |
| `turnID` | optional `params.turnId`, then `params.turnID` |
| `itemID` | optional `params.itemId`, then `params.itemID` |

For all rows:

- `projectionID` is generated only after the source identity is resolved.
- a missing required `turnID` or `itemID` for a supported turn item is an
  identity gap.
- a missing `requestID` for a request row is an identity gap.
- conflicting aliases are an identity conflict.
- identity gaps and conflicts are not normal message rows.

### Streaming Rule

Streaming and settled versions of the same Codex item must share the same
`projectionID`.

Examples:

| Raw source | `projectionID` |
| --- | --- |
| `item/agentMessage/delta` with `turnId=t1`, `itemId=i1` | `host:<sourceHostID>/thread:<threadID>/turn:t1/item:i1/row:agentMessage` |
| `item/completed` with nested `item.id=i1`, `item.type=agentMessage` | `host:<sourceHostID>/thread:<threadID>/turn:t1/item:i1/row:agentMessage` |
| `thread/turns/list` item `id=i1`, `type=agentMessage` | `host:<sourceHostID>/thread:<threadID>/turn:t1/item:i1/row:agentMessage` |

The delta method name must never be part of visible `projectionID`. The method only
selects `rowRole`, `renderKind`, and `visibility`.

### Live Delta Method Table

Every supported live delta method must map to a row role through this table:

| Method | `rowRole` | `renderKind` | `visibility` | Text field |
| --- | --- | --- | --- | --- |
| `item/agentMessage/delta` | `agentMessage` | `agentMessage` | `message` | `params.delta` |
| `item/plan/delta` | `plan` | `agentMessage` | `thinking` | `params.delta` |
| `item/reasoning/summaryTextDelta` | `reasoning` | `agentMessage` | `thinking` | `params.delta` |
| `item/reasoning/textDelta` | `reasoning` | `agentMessage` | `thinking` | `params.delta` |
| `item/commandExecution/outputDelta` | `commandOutput` | `output` | `tooling` | `params.delta` |

If a new live delta method is added later, the implementation must update this
table, the relay normalizer, Swift DTO tests, simulator proof expectations, and
the canonical protocol reference in the same change. Unknown live delta methods
are not visible message rows; they are ignored, diagnosed, or trigger resync.

## Relay API Shape

Add relay-owned Thread Detail display routes:

```text
thread/detail/read
thread/detail/subscribe
thread/detail/resync
```

These route names are part of the architecture. Keeping display traffic on raw
`thread/read` and raw `thread/resume` would leave too much room for Swift to
keep parsing raw Codex payloads. Existing raw routes can remain for relay
internals and command/session management, but they must not be the production
Thread Detail display source.

`thread/detail/subscribe` also establishes the downstream thread binding for
`turn/start`, `turn/steer`, and `turn/interrupt`. The relay can keep using
upstream `thread/resume excludeTurns:true` internally, but raw upstream
notifications must be normalized into `ThreadDetailUpdateDTO` before Swift
display state sees them.

`thread/detail/read` returns a complete canonical snapshot for the requested
thread and window:

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "threadID": "019e...",
  "epoch": "projection-...",
  "seq": 1,
  "snapshotID": "detail-snapshot-...",
  "sourceWatermark": "codex-source-...",
  "scope": "thread",
  "viewParamsKey": "sha256:...",
  "window": null,
  "rows": [],
  "complete": true,
  "nextCursor": null
}
```

`thread/detail/subscribe` binds the downstream connection to one thread and
emits:

```json
{
  "kind": "snapshot",
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "threadID": "019e...",
  "epoch": "projection-...",
  "seq": 1,
  "scope": "thread",
  "viewParamsKey": "sha256:...",
  "window": null,
  "rows": [],
  "complete": true,
  "nextCursor": null
}
```

then:

```json
{
  "kind": "upsert",
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "threadID": "019e...",
  "epoch": "projection-...",
  "seq": 2,
  "viewParamsKey": "sha256:...",
  "rows": []
}
```

and, when needed:

```json
{
  "kind": "delete",
  "identityVersion": 1,
  "sourceHostID": "amir-m5",
  "threadID": "019e...",
  "epoch": "projection-...",
  "seq": 3,
  "projectionIDs": []
}
```

or:

```json
{
  "kind": "resyncRequired",
  "identityVersion": 1,
  "sourceHostID": "amir-m5",
  "threadID": "019e...",
  "epoch": "projection-...",
  "seq": 4,
  "reason": "identity_gap"
}
```

The app applies these operations to a local ledger keyed only by `projectionID`.

### Ledger Operation Semantics

Every operation carries `epoch` and monotonic `seq`.

- The client ignores operations whose `epoch` is not the active epoch.
- The client ignores operations whose `seq` is less than or equal to the last
  applied sequence for that epoch.
- The client rejects operations whose `viewParamsKey` does not match the active
  view being rendered.
- A new `snapshot` starts or replaces the local ledger for its declared
  `scope`.
- `scope: "thread"` means the snapshot is authoritative for the open thread;
  local rows for that thread not present in the snapshot are deleted.
- `scope: "window"` means the snapshot is authoritative only for the declared
  window; the DTO must include window bounds so the client does not infer them.
- `upsert` inserts or replaces rows by exact `projectionID`.
- `delete` removes rows by exact `projectionID`.
- `resyncRequired` marks the view stale and requires `thread/detail/resync`.
  After resync, the client replaces the local ledger with the returned
  snapshot.

Epoch and watermark rules:

- `epoch` changes when the relay starts a new detail subscription, changes
  `identityVersion`, detects unrecoverable upstream sequence loss, or
  serves an explicit `thread/detail/resync` after stale state.
- `seq` starts at `1` inside each `epoch` and increases for every
  snapshot, upsert, delete, or resync-required update.
- `snapshotID` is unique per snapshot payload and is used for diagnostics, not
  as merge identity.
- `sourceWatermark` identifies the upstream Codex history/live point the relay
  normalized. It is used for freshness proof and logs; Swift must not use it as
  row identity.
- A new `epoch` means the client drops the old projection ledger for that
  thread and applies the new snapshot.

This explicitly replaces the current Dock-row refresh behavior where
`ThreadDetailStore.rehydrateAfterDockRowAdvance` rereads canonical history and
then calls `mergeEvents`. After this architecture, a Dock-row activity advance
can request `thread/detail/resync`, but it must not merge raw history into a
client-built event index.

### Window Snapshot Fields

`scope: "thread"` is preferred for the first implementation because it has the
fewest edge cases. If `scope: "window"` is implemented, these fields are
required:

```json
{
  "scope": "window",
  "window": {
    "order": "displayOrderKeyAscending",
    "offset": 0,
    "limit": 250,
    "firstDisplayOrderKey": "9998239345599999|...",
    "lastDisplayOrderKey": "9998239345601234|...",
    "completeBefore": true,
    "completeAfter": false
  }
}
```

Client rules for a window snapshot:

- If any `window` field is missing, the snapshot is invalid and the client must
  request `thread/detail/resync`.
- The client replaces only rows for the same `threadID` whose
  `displayOrderKey` is between `firstDisplayOrderKey` and
  `lastDisplayOrderKey`, inclusive.
- Rows outside that key range are retained.
- Rows inside that key range but absent from the snapshot are deleted.
- `completeBefore` and `completeAfter` describe whether more rows exist before
  or after the returned key range in display order.
- The client must not infer window bounds from row count, `offset`, or
  `nextCursor` alone.

### Render State Transitions

`renderState` is a state on the same `projectionID`, not a second identity axis.

Allowed values:

- `streaming`: partial text from a live delta.
- `live`: full live item or request that has not yet been confirmed by
  canonical history.
- `settled`: canonical history has confirmed the row.
- `stale`: relay knows the row may be outdated while waiting for resync.
- `diagnostic`: non-message diagnostic row.

Allowed transitions:

```text
streaming -> live -> settled
streaming -> settled
live -> settled
any non-diagnostic -> stale -> settled
diagnostic -> diagnostic
```

An invalid transition is not a reason to create a new `projectionID`. It is a reason
to upsert the same `projectionID` with the correct state or request resync.

## Relay Normalizer

The relay normalizer should consume every display source:

- `thread/read includeTurns:false`
- paged `thread/turns/list itemsView:full`
- `thread/resume excludeTurns:true`
- live `item/agentMessage/delta`
- live `item/commandExecution/outputDelta`
- live reasoning and plan deltas
- live `item/started`
- live `item/completed`
- server requests sent by upstream Codex over the active detail connection
- request resolutions sent back by the app
- thread status and close notifications

All of those sources must enter the same pure normalizer module before they can
become visible rows.

The normalizer should expose pure functions that tests and runtime both use:

```text
normalizeThreadTurns(threadID, turns) -> ThreadDetailEventDTO[]
normalizeLiveNotification(threadID, notification) -> DetailLedgerOperation[]
normalizeServerRequest(threadID, request) -> DetailLedgerOperation
applyDetailOperation(ledger, operation) -> ledger
```

The normalizer should not depend on WebSocket state, timers, filesystem state,
or UI state. It should be boring and testable.

## Client Architecture

Swift should become a renderer of relay-owned projection rows.

### Keep

- `ThreadDetailStore` as the screen owner.
- composer send behavior.
- request-card interaction behavior.
- accessibility IDs for message cards.
- the current UI layout.

### Replace

Replace `ThreadEventNormalizer` as a production display source.

The app can keep a Swift type named `ThreadEvent`, but it should be initialized
from `ThreadDetailEventDTO`. It should not parse raw Codex item JSON for
production Thread Detail display.

Replace `ThreadEventIndex` merge rules with a simpler ledger:

```text
upsert by projectionID
delete by projectionID
replace snapshot by epoch + sequence + scope
sort by displayOrderKey ascending
```

No secondary "stream key" should be needed in Swift because streaming deltas
and final snapshots share the same relay-generated `projectionID`.

### Request Cards

Request cards should be part of the same identity system.

Today request rendering has its own side index:

- first by `event.id`
- then by `turnID + itemID`

That should collapse into the projection ledger:

- request-backed projection rows carry both `projectionID` and `requestID`.
- the visible row is keyed by `projectionID`.
- the request controls are keyed by `projectionID`.
- `requestID` is used only to send the JSON-RPC response back to the relay.
- relay-owned fields include request method, request body summary, status,
  requested time, resolved time, and non-secret error state.
- client-local fields include the current text typed into a request response
  box and transient send-in-flight UI state.
- request status updates are projection `upsert` operations for the same
  `projectionID`.

Final Swift must not keep request cards as an independent identity store.
Request controls are derived from the current Thread Detail projection rows.
The only client-local request state is transient UI state keyed by
`projectionID`, such as typed input text and the local send/result state while a
response is in flight. It must not own membership, identity, ordering,
freshness, or server request status truth. `requestID` remains a routing token
for the response call, not a display identity.

Request projection identity must follow this precedence:

| Request shape | `projectionID` rule |
| --- | --- |
| command approval with `turnID` and `itemID` | use the item row: `host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/row:command` |
| file-change approval with `turnID` and `itemID` | use the item row: `host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/row:fileChange` |
| tool user-input request with `turnID` and `itemID` | use the item row: `host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/row:toolCall` |
| request has `turnID` and `itemID` but no known item row role | use request row: `host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/request:<requestID>/row:request` |
| request has no usable `turnID` and `itemID` | use request row: `host:<sourceHostID>/thread:<threadID>/request:<requestID>/row:request` |

When a request uses an item row `projectionID`, the relay may create a
placeholder projection row if the canonical item has not arrived yet. When the
canonical item arrives later, it must upsert the same `projectionID`; it must
not add a second request row.

Automation must use the same visible identity:

```text
message card:  codexdock.session.message.<safe(projectionID)>
request card:  codexdock.session.request.<safe(projectionID)>
request input: codexdock.session.request.<safe(projectionID)>.input
status:        codexdock.session.request.<safe(projectionID)>.status
```

This removes a second identity side door from Thread Detail rendering.

### Filters And Local Metadata

Human filters, pins, hides, archive state, and other local metadata must not be
a second display-truth plane.

The target rule is:

- Relay view parameters select the projection view being proved.
- The relay projection ledger owns the resulting row set and order.
- Swift may defensively hide a row only when it violates the projection contract
  for the active view, and that must be logged as invalid data, not treated as
  normal product filtering.
- Acceptance proof compares the simulator UI to the same filtered relay
  projection view the user is seeing, not to the unfiltered full ledger.
- Local metadata can decorate rows or send mutation requests back to the relay.
  It cannot create rows, delete rows from proof truth, change `projectionID`,
  change `displayOrderKey`, or make stale data fresh.

This keeps user-visible filtering explicit without recreating the old hidden
idle-filter class of bugs as a new identity side door.

`thread/detail/read`, `thread/detail/subscribe`, and `thread/detail/resync`
must carry the same `viewParams` shape whenever the user is looking at a
filtered Thread Detail view:

```json
{
  "threadID": "019e...",
  "viewParams": {
    "visibility": "all",
    "rowRoles": null,
    "search": "",
    "includeDiagnostics": true,
    "sort": "displayOrderKeyAscending"
  }
}
```

Rules:

- default `visibility` is `"all"`; no hidden default message-only filter.
- `rowRoles: null` means every row role participates. A non-empty array is a
  positive include filter.
- `search` is part of the relay projection view when it changes the visible row
  set. Swift may keep local text-field state, but accepted proof compares
  against the relay view for that same search string.
- `includeDiagnostics` defaults to `true` in development proof. A production UI
  may hide diagnostics only by asking the relay for `includeDiagnostics: false`
  and proving that filtered view.
- `sort` has one accepted value for v1: `displayOrderKeyAscending`.
- every snapshot/update echoes a canonical `viewParamsKey`, computed as
  stable-key-order JSON over `viewParams`. Swift rejects updates whose
  `viewParamsKey` differs from the active view.

Dock and Archive follow the same rule. Their filtered projection routes use a
typed `viewParams` object; defaults mean "include everything for this view,"
not a hidden product filter:

```json
{
  "viewParams": {
    "hostIDs": null,
    "lanes": null,
    "sourceKinds": null,
    "statusKinds": null,
    "branchSearch": "",
    "repositorySearch": "",
    "textSearch": "",
    "includeDiagnostics": true,
    "sort": "displayOrderKeyAscending"
  }
}
```

Rules:

- `null` arrays mean no filter. Non-empty arrays are positive include filters.
- `statusKinds: null` includes every status, including idle.
- Search strings that change visible membership are relay view params and are
  included in `viewParamsKey`.
- Dock and Archive differ by `view`, not by local client filtering of one broad
  result set.

## Ordering Rule

Ordering should also be relay-owned and deterministic.

The app should sort only by `displayOrderKey` ascending. The relay builds that
key from the canonical newest-first order:

1. `activityTime` descending.
2. `turnOrder` ascending, where `0` is the newest turn in the canonical detail
   window.
3. `itemOrder` descending, where larger values are later items within the same
   turn.
4. `rowOrder` descending, where larger values are later visible rows from the
   same item.
5. `projectionID` ascending.

The relay must encode those rules into `displayOrderKey` so the client does not
rebuild the comparator. `turnOrder`, `itemOrder`, and `rowOrder` are included
for diagnostics and contract tests, not as independent client sort rules.

### Normative `displayOrderKey` Construction

`displayOrderKey` is a string sorted ascending by the client:

```text
<invertedActivityMillis>|<turnOrder>|<invertedItemOrder>|<invertedRowOrder>|<safeProjectionID>
```

Field rules:

- `activityMillis` is Unix epoch milliseconds from `activityTime`.
- `invertedActivityMillis = 9999999999999999 - activityMillis`, left-padded to
  16 decimal digits.
- `turnOrder` is left-padded to 10 decimal digits. `0` is the newest turn in
  the detail window.
- `invertedItemOrder = 9999999999 - itemOrder`, left-padded to 10 decimal
  digits. Larger `itemOrder` values are later within a turn and sort earlier
  inside the same activity/turn tie.
- `invertedRowOrder = 9999999999 - rowOrder`, left-padded to 10 decimal digits.
  Larger `rowOrder` values are later rows from the same item and sort earlier
  inside the same item tie.
- `safeProjectionID` is `projectionID` encoded with the same safe-segment algorithm used
  for accessibility IDs.

Example:

```text
9998239345599999|0000000042|9999999999|9999999999|host%3Aamir-m5%2Fthread%3A019e...%2Fturn%3At1%2Fitem%3Ai1%2Frow%3AuserMessage
```

The app must not parse this key back into fields. It compares the full string.
If a DTO is missing `displayOrderKey`, the DTO is invalid and the client must
request `thread/detail/resync` instead of falling back to local sorting.

The product intention remains:

- newest user-visible activity is at the top.
- no user message is artificially pinned.
- no hidden default filter changes what "newest" means.
- repeated rereads do not reshuffle equivalent rows.

### Projection ID Escaping And Accessibility

`projectionID` is an opaque UTF-8 string. It may contain `:`, `/`, and other
characters that are useful for human debugging. Accessibility IDs must never
use raw `projectionID` directly.

The canonical safe segment algorithm is the current `AutomationID.safeSegment`
contract:

- keep ASCII letters, ASCII digits, `-`, `.`, and `_`.
- percent-encode every other UTF-8 byte as uppercase `%XX`.
- use `_` for an empty segment.

JS proof code and Swift automation code must use the same escaping rule. The
proof is not allowed to invent a different message-card ID format.

## No Side Doors

This architecture only works if the old identity paths are deleted, not left as
quiet fallbacks.

Implementation must remove or demote these side doors:

- Swift production display normalization from raw `thread/turns/list` item JSON.
- Swift production display normalization from raw live notifications.
- Swift random visible IDs for supported Codex items.
- JS proof-side reconstruction of expected projection IDs from raw history.
- simulator proof fields such as `expectedMessageEventIDs`, unless the field
  has been renamed and populated directly from relay-emitted `projectionID`s.
- test-only fixture paths that assert against manually invented message IDs.
- merge paths that compare body text as a dedupe substitute.
- permanent dual routes where one app path renders normalized DTOs and another
  renders raw Codex payloads.
- independent `requestCards` display identity stores outside the projection
  ledger.
- Dock/Archive `logicalHostID::threadID` identity after the migration phase.
- Archive Cleanup preview streams that define identity, membership, recency, or
  freshness outside the projection engine.
- phone `HostRegistry` config IDs used as source identity or proof truth.
- multiple production projection helper modules that can define
  `projectionID`, `sourceRef`, row role, display order, or engine version.

Temporary development flags are acceptable only if they are removed in the same
implementation plan. They must not become a supported fallback.

## Implementation Plan

This is the implementation sequence that preserves the architecture instead of
shipping a narrow patch.

### Phase 1 - Create The Projection Contract Package

Create one contract source for the shared projection envelope and all typed view
payloads.

Required outputs:

- shared projection snapshot/update schema.
- shared projection row envelope schema.
- Dock/Archive thread-card payload schema.
- Thread Detail row payload schema.
- one row wire shape: shared envelope plus typed `payload`, never a second
  flattened row DTO.
- `viewParams` and `viewParamsKey` schema for every filtered projection view.
- generated or schema-checked Swift DTOs.
- Node runtime validators used by relay tests.
- a fixture corpus generated from the projection engine, not hand-authored
  message IDs.

Exit gate:

- changing `schemaVersion`, `identityVersion`, `projectionEngineVersion`,
  route grammar, row roles, view names, or payload enums fails both Node and
  Swift tests until the contract and fixtures move together.

### Phase 2 - Establish Stable Source Host Identity

Implement the `sourceHostID` provider before touching row identity.

Required behavior:

- use `CODEX_DOCK_REAL_HOST_ID` when set.
- otherwise read `.codex-dock/source-host-id`.
- otherwise create `.codex-dock/source-host-id` once from stable local source
  inputs.
- reject endpoint-derived host IDs as source identity.
- keep relay process/session IDs out of `projectionID`.
- keep phone saved host config IDs out of `sourceHostID`, `sourceRef`,
  `projectionID`, and proof witnesses.

Exit gate:

- changing LAN hostname, Bonjour name, Tailscale name, saved phone endpoint, or
  relay restart does not change projection IDs for the same Codex source.

### Phase 3 - Build The Universal Projection Engine And Store

Move identity/order/freshness into one pure projection engine and one
materialized projection store.

Required behavior:

- raw adapters feed the projection engine.
- the engine returns projection operations.
- `scripts/dock-relay-projection-engine.mjs` or its owned package directory is
  the only production module that defines `projectionIDFor*`, `sourceRefFor*`,
  row-role mapping, `displayOrderKeyFor*`, and projection-engine version.
- Thread Detail ledger code, Dock state code, Archive state code, Host Registry
  code, Archive Cleanup code, and proof fixtures call that module; they do not
  fork identity/order logic.
- the store persists projection rows and view memberships.
- cache validity is keyed by
  `schemaVersion + identityVersion + projectionEngineVersion + sourceHostID`.
- invalid cache rows are rebuilt or served only as explicitly stale, never as
  fresh.

Exit gate:

- Dock, Archive, Host Registry, Archive Cleanup, and Thread Detail can all be
  read from projection storage with the same `projectionID`,
  `displayOrderKey`, freshness, epoch, and sequence semantics.

### Phase 4 - Cut Over View Streams

Make `dock/*`, `archive/*`, `archive/cleanup/*`, `host/registry/*`, and
`thread/detail/*` emit the shared projection stream grammar.

Required behavior:

- `snapshot`, `upsert`, `delete`, `heartbeat`, and `resyncRequired` have the
  same meaning for every view.
- Dock and Archive card IDs are `projectionID`s.
- Host Registry rows are `projectionID`s; phone saved host config can bootstrap
  connections but cannot define source identity.
- Thread Detail message/request IDs are `projectionID`s.
- request controls use `projectionID`; `requestID` is only response routing.
- raw Thread Detail routes are no longer production display routes.
- Dock and Archive no longer accept `delta`, `upsertCards`, `deleteCardIDs`,
  `stateGeneration`, or `logicalHostID::threadID` as production display truth.
- Archive Cleanup reads a projection view or a named relay-projected cleanup
  view. It does not open an independent Dock card stream and reinterpret that
  as cleanup truth.

Exit gate:

- a simulator proof can compare Dock, Archive, Host Registry, Archive Cleanup,
  and Thread Detail accessibility IDs directly to relay projection snapshots
  without computing any expected ID from raw Codex JSON.

### Phase 5 - Thin The Swift Client To A Renderer

Remove production raw display normalization from Swift.

Required behavior:

- `ThreadEventNormalizer` is deleted from production code or moved into a
  legacy diagnostic/test-only target that cannot be imported by app display
  stores.
- raw `thread/read`, `thread/turns/list`, and `thread/resume` client helpers
  are removed from production display protocols.
- `HostRegistry` phone config stays a connection/settings store only; app
  display code cannot use it as Codex source identity or projection truth.
- Swift stores reject projection DTOs with missing or mismatched
  `schemaVersion`, `identityVersion`, `sourceHostID`, `view`, `epoch`, `seq`,
  `projectionID`, or `displayOrderKey`.
- missing `displayOrderKey` forces resync; Swift does not locally sort around
  it.

Exit gate:

- `rg` over app display code shows no production path that turns raw Codex JSON
  into visible rows.

### Phase 6 - Replace Proof Oracles

Make proof tools consume the projection contract.

Required behavior:

- `sim-ui-dump` remains the canonical way to dump visible simulator state.
- simulator sync proof compares UI state to relay projection rows captured from
  the downstream projection wire. A loopback witness export is allowed only when
  it replays byte-for-byte equivalent emitted envelopes.
- controlled fixtures emit raw Codex input only into the relay, then read
  expected display truth from the relay projection ledger.
- legacy `eventID` proof vocabulary is removed or renamed to `projectionID`.
- proof reports mark raw-route display oracles as failures.
- proof reports do not contain `expectedMessageEventIDs` or any equivalent
  expected-ID array computed outside the relay projection ledger.
- fixtures may call the pure projection engine to make relay-emitted snapshots
  and updates in unit tests; acceptance proof may not compute expected UI IDs
  beside the relay.
- `codex-dock-live-filter-*` scenarios are rewired to consume
  `projectionWitness` or quarantined as non-acceptance legacy diagnostics.

Exit gate:

- no acceptance proof reconstructs visible IDs from raw Codex routes or
  fixture-side projection helper calls. Expected IDs come from relay-emitted
  projection snapshots/updates retained in the proof witness.
- `expectedMessageProjectionIDs` exists only when populated from the retained
  witness stream. A fixture import of `projectionIDForItem` or
  `projectionIDForRequest` cannot populate acceptance expectations.
- CI forbidden-pattern checks fail if any acceptance path imports
  `projectionIDFor*`, reads raw detail routes as expected UI truth, or uses
  `codex-dock-live-filter-*` without a projection witness.

### Phase 7 - Delete Migration Side Doors

Remove every compatibility path that can become a second identity owner.

Required behavior:

- raw detail display routes are not reachable from production Swift display.
- fixture-only raw normalizers cannot be used by app stores.
- old `logicalHostID` card identity is either a transition alias validated
  one-to-one against `sourceHostID` or removed.
- Archive Cleanup no longer owns an independent preview stream that can define
  card identity, membership, recency, or freshness outside the projection
  engine.
- `HostRegistry` phone config no longer appears in any production
  `projectionID`, `sourceRef`, `sourceHostID`, or proof witness.
- docs and README no longer describe raw routes as the Thread Detail display
  path.

Exit gate:

- a fresh repo search for `eventID`, `logicalHostID` as identity, raw
  `thread/read` display, and local UUID visible-row creation has either zero
  hits or only explicitly quarantined diagnostic/test-only hits.
- CI has explicit forbidden-pattern checks for production display and
  acceptance proof paths. These checks are contract gates, not style lint.

Required forbidden-pattern gates:

| Pattern | Forbidden in | Allowed only when |
| --- | --- | --- |
| `expectedMessageEventIDs` | acceptance proof outputs and simulator sync proof | never; replace with relay-emitted `projectionID`s |
| `ThreadEventNormalizer` imports | production app display stores and production display tests | quarantined legacy diagnostic/test-only target |
| `thread/read`, `thread/turns/list`, `thread/resume` | production Swift display protocols and simulator proof oracles | relay-internal adapters, command/session management, or named diagnostics |
| `AppServerClient.sendRequest(method:)` or arbitrary method-string display reads | production display stores, display protocols, simulator proof oracles | low-level transport plumbing behind typed projection or mutation APIs only |
| raw Codex display DTO decode (`ThreadRead*`, `ThreadTurnsList*`, `ThreadResume*`, raw turn/item JSON) | production Swift display stores, proof oracles, acceptance fixtures | relay-internal adapters or quarantined diagnostics/tests that cannot feed production display truth |
| `UUID()` / `crypto.randomUUID()` for visible rows | app display code, relay projection code, proof fixtures | internal subscription/task handles or non-message diagnostics only |
| `logicalHostID::threadID` | production Dock/Archive identity and proof truth | migration fixture that also proves byte-for-byte equality with `projectionID` |
| local fallback sorting | Swift display stores | never for accepted DTOs; missing `displayOrderKey` forces resync |
| independent `requestCards` identity store | Thread Detail display state | local input/status overlay keyed by `projectionID`; cards are derived from projection rows |
| `ArchiveCleanupDataEngine` independent Dock stream | production Archive Cleanup display and proof truth | never after projection cutover; use relay-projected cleanup view or projection rows |
| phone `HostRegistry` config IDs | `sourceHostID`, `sourceRef`, `projectionID`, proof witnesses | connection/settings UI before relay identity is known |
| multiple production `projectionIDFor*` modules | relay runtime, tests, fixtures, proof | never; use the single projection engine module |
| `codex-dock-live-filter-*` without `projectionWitness` | acceptance proof and simulator sync proof | quarantined legacy diagnostics only |

## Why Simpler Alternatives Are Not Enough

### "Just use top-level `itemId` when nested `item.id` is missing"

This likely fixes one observed duplicate, but only for one live notification
shape. It does not prevent the next raw shape from drifting.

### "Just replace events on every canonical reread"

That can reduce duplicates after history catches up, but it can also drop
live-ahead rows and does not define identity for streaming updates, request
cards, or proof scripts.

### "Just dedupe by body text"

This is wrong because repeated prompts and repeated command output are valid.
Two messages with the same body can be distinct. One message with different
partial and final bodies can be the same event.

### "Just share a Swift identity builder inside the client"

That improves Swift, but it leaves the relay proof scripts and raw app-server
paths able to drift. It also keeps the iPhone responsible for interpreting raw
Codex details.

### "Just generate a TypeScript identity helper and port it to Swift"

That still creates two implementations. It is better than today's code, but it
does not remove the class of bugs. The most stable boundary is a relay-emitted
DTO that already contains identity.

## Test Methodology

The tests must prove convergence over time, not static snapshots only.

### Relay Contract Tests

Add relay tests for the pure normalizer:

- canonical history user message -> one `projectionID`
- live `item/started` user message -> same `projectionID`
- live `item/completed` user message -> same `projectionID`
- outbound send followed by live event followed by canonical history -> one row
- agent delta followed by completed agent item -> one row
- command output deltas followed by completed command item -> command/output
  rows remain stable
- server request followed by request resolution -> one request row with status
  update
- malformed supported item without identity -> diagnostic or resync, not random
  visible message

### Permutation Tests

For every realistic event sequence, test permutations:

- history then live
- live then history
- delta then completed item
- completed item then late delta
- request then history
- history then request
- reconnect then resync
- duplicate upstream notification

Every permutation must converge to the same final ledger:

```text
same projectionID set
same event body for settled rows
same renderState
same request status
same order
```

The outbound duplicate fixture is mandatory, not optional:

1. live outbound user upsert arrives first.
2. canonical history snapshot for the same user item arrives second.
3. the reverse order is tested too.
4. both orders converge to one `projectionID`, one row, one accessibility ID.

### Swift Tests

Swift tests should stop testing raw Codex normalization as production behavior.
They should test:

- DTO decoding.
- ledger upsert/delete/replace.
- sort order from `displayOrderKey`.
- render projection.
- request card attachment by `projectionID`, with `requestID` used only for the
  response call.
- accessibility ID generation from `projectionID`.

There should be one explicit regression test for the outbound duplicate:

1. Start with an empty or old detail snapshot.
2. Apply a live outbound user-message upsert.
3. Apply a canonical snapshot containing the same user message.
4. Assert one visible user-message row and one accessibility message-card ID.

### Simulator Proof

Add a controlled simulator scenario that drives the real UI path:

```text
rtk make sim-ui-scenario-sync-proof \
  SIM='iPhone 17' \
  SIM_UI_SYNC_SCENARIO=outbound-message-identity
```

2026-06-02 latest user instruction: the current simulator proof target is
`SIM='iPhone 17'`. Earlier iPhone 16 runs are historical evidence only; final
sign-off must use iPhone 17.

The scenario must:

1. Open Thread Detail.
2. Send a message through the real composer path or a relay-controlled
   equivalent that exercises the same downstream update path.
3. Emit the live update.
4. Emit the canonical reread state.
5. Dump the visible accessibility tree.
6. Assert the outbound event appears exactly once by `projectionID`.

This proof should compare UI to relay-provided detail projection identity, not to a
separate JS reconstruction of what the UI "should" have done.

### Real Relay Soak

Add a real relay soak that watches an active thread for a short window and
records:

- relay detail snapshot IDs
- emitted projection IDs
- Swift visible accessibility projection IDs from `sim-ui-dump`
- event counts
- duplicate projection IDs
- duplicate source identities
- resync events

The pass condition should not be "the screen has some rows." It should be:

- every visible message card maps to one relay `projectionID`
- no visible message card has a projection ID absent from the relay projection ledger
- no relay message event is shown more than once
- reconnect and reread do not change settled event identity

## Canonical Protocol Reference Gate

This audit doc is the design worklog. It is not allowed to become a permanent
parallel protocol source.

The shared projection identity contract and the Thread Detail payload contract
have been copied into the canonical protocol reference:

- `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`

That canonical section must include:

- `ThreadDetailEventDTO`
- `ThreadDetailSnapshotDTO`
- `ThreadDetailUpdateDTO`
- shared projection row envelope
- `sourceHostID` derivation
- `identityVersion`
- `projectionID` formats
- `displayOrderKey` construction
- `rowRole` mapping
- live delta method table
- identity recovery precedence
- request projection-ID precedence
- projection update operation semantics
- accessibility escaping
- test/proof requirements

Implementation should treat the protocol reference as the source of truth and
this audit doc as historical rationale. If the two disagree, implementation
must stop and reconcile the docs before writing code.

## Acceptance Criteria

This architecture is complete only when all of these are true:

- There is one production identity function for user-visible projection rows.
- The identity function lives at the relay boundary.
- The identity function lives in one production projection engine module used by
  Dock, Archive, Host Registry, Archive Cleanup, Thread Detail, relay tests, and
  fixture generation.
- `sourceHostID` is part of the identity namespace for every projection row.
- Phone saved host config is connection bootstrap only; it never defines
  `sourceHostID`, `sourceRef`, `projectionID`, ordering, freshness, or proof
  truth.
- Swift renders relay projection rows and does not infer visible identity from
  raw Codex payloads.
- Dock and Archive render relay projection rows and do not rebuild identity,
  order, or freshness locally.
- Host Registry renders relay host projection rows when showing Codex source
  identity or connectivity proof.
- Archive Cleanup uses relay-projected rows or a relay-projected cleanup view;
  it does not reinterpret an independent Dock stream as cleanup truth.
- Proof scripts compare UI against relay projection rows and do not reconstruct
  their own expected message IDs.
- Filters are relay view parameters with a canonical `viewParamsKey`; proof
  compares UI to that exact filtered projection view.
- All supported message-like events have deterministic projection IDs.
- No supported message-like event can fall back to UUID/random visible identity.
- Server request rows participate in the same identity system.
- Streaming deltas and final canonical items share projection IDs.
- Streaming delta method names are not part of visible projection IDs.
- Live, history, reread, reconnect, and request paths all converge to one
  ledger.
- Dock-row refresh cannot merge raw canonical history into a client-built
  detail index.
- Request-card UI is keyed by detail `projectionID`; JSON-RPC response routing uses
  `requestID`.
- UI ordering uses relay `displayOrderKey`; Swift does not reconstruct ordering
  from raw turn/item fields.
- Accessibility IDs use the canonical safe-segment escaping rule.
- Tests cover temporal update sequences and permutations, not only static
  snapshots.
- The simulator proof can catch the exact "I sent a message and it shows twice"
  bug.
- Cache/schema/identity version changes cannot serve old rows as fresh.
- Raw Codex routes are relay internals for display purposes after cutover.
- There is no production, proof, fixture, or test-only path that can define
  production visible identity outside the projection engine.
- Quarantined diagnostic/test targets may remain in the repo only when
  production display targets cannot import them and acceptance proof cannot use
  them as visible-identity truth.
- Acceptance proof expected IDs come from the downstream projection witness
  stream, or a byte-for-byte equivalent retained emitter export, never from
  fixture-side `projectionIDFor*` helper calls.
- CI fails if forbidden identity patterns appear in production display or
  acceptance proof paths without an explicit diagnostic/test-only quarantine.
- `expectedMessageEventIDs` and fixture-computed expected visible IDs are gone
  from simulator proof and acceptance reports.

## Fresh Consult Status

Composer 2.5 Fast architecture consults:

- `/tmp/fresh-consult/projection-identity-zero-sunk-20260601T194844Z-Mm2IpR`
  returned `pass-with-notes`, `BLOCKING: none`.
- Notes folded into this doc: Dock/Archive snapshot authority and scopes,
  `row:host` semantics, projection proof witness capture, concrete projection
  contract package paths, `revision` / version bump policy, and relay-owned
  optimistic outbound supersession requirements.
- `/tmp/fresh-consult/projection-identity-final-architecture-20260601T201029Z-YKVogZ`
  returned `pass-with-notes` and raised five plan-blocking specification gaps:
  one shared projection engine module, witness primary capture, Host Registry
  parity/config boundary, Archive Cleanup closure, and fixture expected-ID
  removal.
- `/tmp/fresh-consult/projection-identity-final-architecture-rerun-20260601T201433Z-Sqs56M`
  returned `pass-with-notes`, `BLOCKING: none`; it confirmed the five prior
  blockers were closed and requested non-blocking tightening for Archive
  Cleanup, witness export, live-filter proof migration, pin metadata, and Phase
  1 schema/package gates.
- `/tmp/fresh-consult/projection-identity-final-architecture-final-20260601T201812Z-doPbDf`
  returned `pass-with-notes`, `BLOCKING: none`; it confirmed the architecture is
  the right and most elegant permanent fix, with only schema-tightening and
  enforcement-gate notes.
- `/tmp/fresh-consult/projection-identity-final-architecture-accept-20260601T202033Z-iD2Csb`
  returned `pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`. It stated
  that the architecture is complete and internally consistent for Codex Dock's
  identity/update side-door class and that no blocking architecture gaps remain
  before implementation planning.
- `/tmp/fresh-consult/projection-identity-architecture-current-20260601T212648Z-EI9cbs`
  returned `pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`. It agreed
  the relay projection plane is the right permanent architecture and requested
  non-blocking tightening for generic `sendRequest(method:)`, raw DTO display
  decode, and card-v2 as migration-only history.
- `/tmp/fresh-consult/projection-identity-architecture-rerun-20260601T212857Z-m1Ev9N`
  returned `pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`. It confirmed
  those side-door notes were closed and requested only minor wording fixes for
  the current-drift cross-reference, retained witness source wording, and
  quarantined diagnostic/test language.
- `/tmp/fresh-consult/projection-identity-architecture-final-rerun-20260601T213042Z-fRwIr4`
  returned `pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`. It confirmed
  the updated doc closes the prior notes, specifies a complete zero-sunk-cost
  permanent architecture, and leaves no blocking architecture gaps. Its final
  non-blocking witness wording note has been folded into the Projection Witness
  Plane section.
- `/tmp/fresh-consult/projection-identity-current-architecture-20260601T214835Z-2Y0zge`
  returned `pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`. It agreed
  that the relay-owned universal projection plane is the objectively best
  permanent architecture, then asked for non-blocking tightening around request
  row identity, fail-closed witness export, the Phase 1 projection contract
  package gate, Swift render-adapter limits, and forbidden-pattern CI gates.
- `/tmp/fresh-consult/projection-identity-current-architecture-rerun-20260601T215013Z-q4WjoV`
  returned `pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`. It verified
  that all five tightening points are now normatively resolved in this doc and
  stated there is no better architecture for Codex Dock's constraints. Its
  remaining notes are implementation-state facts: `contract/projection/**` is
  not on disk yet, current code still contains the documented side doors, and
  proof schemas still need to be tightened during implementation.

Final consult status: accepted for implementation planning. Composer 2.5 Fast
agrees the architecture is complete, elegant, and the right permanent fix for
the identity/update side-door class. Remaining work is implementation-phase
execution and gate enforcement, not architecture redesign.

## Bottom Line

The duplicate outbound message is best explained by identity drift between live
Thread Detail updates and canonical history rereads.

The permanent fix is not to patch one missing field. The permanent fix is one
relay-owned projection identity plane for Dock, Archive, Archive Cleanup, Host
Registry, Thread Detail, request cards, proof, and simulator fixtures.

The iPhone renders projection rows. One relay projection engine owns
`sourceHostID`, `sourceRef`, `projectionID`, `displayOrderKey`, freshness,
epoch, sequence, and witness truth. That removes the architectural side doors
that currently let live, history, request cards, caches, local metadata, tests,
and proof scripts disagree about what "the same visible thing" means.
