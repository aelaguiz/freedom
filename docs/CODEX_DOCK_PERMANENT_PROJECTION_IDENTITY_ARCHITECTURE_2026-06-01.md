# Codex Dock Permanent Projection Identity Architecture

Date: 2026-06-01
Status: proposal for review; do not implement from this document until explicitly approved

## Fresh Consult Status

Cursor Agent Composer 2.5 Fast reviewed this proposal through five read-only
consult passes. The final pass reported:

```text
VERDICT: pass-with-notes
BLOCKING: none
CONFIDENCE: high
```

Final consult artifact:

```text
/tmp/fresh-consult/projection-identity-permanent-architecture-finalaccept-20260601T230713Z-0Hf8iq
```

Earlier consult passes found doc-level gaps around host side-channel arrays,
window mutation scope, `clientMutationID`, route authority, stream sequence
continuity, cross-view fan-out, request-card display truth, composer/voice
quarantine, and temporal proof. Those findings are folded into this document.

## Bottom Line

Codex Dock should have exactly one display identity architecture:

```text
raw Codex facts
  -> relay projection engine
  -> versioned projection ledger
  -> typed projection streams
  -> one Swift projection table
  -> render-only UI
```

The phone should never decide whether two visible things are "the same thing."
The relay should emit one stable `projectionID` for every visible row, and the
client should key, update, delete, sort, prove, and dump UI state by that
`projectionID`.

Net: identity bugs go away architecturally when every other identity path is
removed, not patched. Thread IDs, request IDs, JSON-RPC IDs, host endpoint IDs,
raw event IDs, card IDs, list indexes, timestamps, body text, accessibility IDs,
and local fixture IDs are not visible row identity.

## Related Documents

- `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`
  explains the outbound duplicate symptom and why local dedupe is the wrong
  fix.
- `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`
  is the broad protocol reference; this document supersedes any older
  card-v2/delta/baseSeq/raw Thread Detail identity sections.
- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
  covers live-update and real-phone proof methodology; this document tightens
  its identity requirements.
- `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`
  records the drift that made stale Dock data possible.
- `README.md` remains the runnable entry point and should point at the final
  approved architecture once implemented.

## User Experience Target

The intended experience is simple:

1. The Dock shows the newest relevant work first.
2. Opening a thread shows the latest visible thread rows first.
3. Sending a message never creates duplicate visible rows.
4. Live updates, canonical history, reconnects, cache reads, and proof tooling
   all converge to the same visible rows.
5. If the relay cannot prove identity or freshness, the app shows an explicit
   stale/diagnostic state instead of guessing.

The user should not need to understand Codex upstream quirks, relay caches,
lease state, request IDs, or host aliasing to trust what is on the phone.

## Current Architecture Findings

The repo is now partway through the right migration. That is exactly why the
architecture has to become stricter: a half-projection system is still two
identity systems.

### What Is Already Directionally Right

- `scripts/dock-relay-projection-engine.mjs` is the seed of the correct pure
  projection package. It owns the current `sourceRefFor*`, `projectionIDFor*`,
  `displayOrderKey`, version constants, and source-host segment escaping.
- `scripts/dock-relay-thread-detail-ledger.mjs` creates Thread Detail projection
  rows with `sourceHostID`, `sourceRef`, `projectionID`, `rowRole`,
  `displayOrderKey`, `revision`, `epoch`, and `seq`.
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` now validates Thread
  Detail projection envelopes and applies `snapshot`, `upsert`, `delete`,
  `heartbeat`, and `resyncRequired` by `projectionID`.
- `CodexDock/State/ThreadCardTable.swift` now rejects Dock/Archive rows missing
  projection identity/order/source-host fields before rendering.
- `CodexDock/Models/ThreadEvent.swift` now treats `displayOrderKey` as required
  for production Thread Detail rows instead of falling back to local turn/date
  sorting.
- `CodexDock/State/ThreadCardRowProjector.swift` maps Dock rows with
  `DockRowViewModel.id == projectionID`, which is the right visible-row identity
  direction.
- Proof scripts have started moving from legacy `cards`/`cardIDs`/
  `visibleEventIDs` vocabulary toward `rows`/`projectionIDs` and retained
  projection witnesses.

### Remaining Drift Points

These are architecture gaps, not cleanup trivia. The permanent design must make
them impossible or explicitly quarantine them outside production display and
acceptance proof.

| Area | Current shape | Why it can still drift |
| --- | --- | --- |
| Dock/Archive DTO shape | `DockThreadCardDTO` now carries required projection fields, but it still flattens payload fields beside envelope fields and still carries transition fields such as top-level `id` and `logicalHostID`. | The boundary still permits old and new identity concepts to coexist. Validation later is weaker than making the invalid shape unrepresentable. |
| Dock/Archive storage names | Swift and SQLite still use card-era names such as `cardsByID`, `cardsByHostID`, `DockThreadCardDTO`, `ThreadCardTable`, and the SQLite `threads` table. | Names are not bugs by themselves, but they keep the old mental model alive and make it easy to add another card-specific path instead of the shared projection path. |
| View params | Current Dock/Archive code still uses simple `viewParamsKey` strings like `dock:<host>`, while the target architecture needs a stable hash of canonical view params. | If two layers do not agree on view membership identity, a stream can look fresh while representing a different query. |
| Request cards | `ServerRequestCard.make(from: JSONRPCRequest)` still exists and can create a display card from a JSON-RPC request if a production path calls it directly. The projection path correctly rebuilds request controls from `ThreadEvent.id == projectionID`. | `requestID` is a routing token. Any visible row keyed by request ID is a second identity owner. |
| Host identity | `sourceHostID` exists, but `logicalHostID`, configured host IDs, endpoint labels, and alias resolver code still coexist in display code. | Same Mac through a different endpoint can still become two apparent hosts unless source-host identity is handshake-owned and validated before stream apply. |
| Cache | SQLite still stores screen-shaped materialization such as `threads`, `sync_scopes`, `changes`, and `turn_cache` instead of one projection-row/view-membership model keyed by projection contract fingerprint. | Old projection rows can look valid after identity semantics change unless cache validity is tied to the projection contract. |
| Proof oracles | Controlled simulator and sync proof are moving toward witnesses, but some tests and fixtures still compute expected projection IDs locally or carry old field names as negative fixtures. | Acceptance proof must check what the relay actually emitted, not run a second projection implementation beside the relay. |
| Test fixture builders | Swift and Node test helpers still construct projection IDs directly in some places. | Unit tests may test the projection engine, but acceptance proof must not use local expected-ID builders as display truth. |
| Docs | Older docs still describe `baseSeq`, `stateGeneration`, `upsertCards`, `deleteCardIDs`, `logicalHostID::threadID`, and raw Thread Detail display reads. | Future work can copy stale architecture and reintroduce side doors. |

## Architectural Decision

Adopt one universal projection identity plane for every visible Codex Dock
object.

## Non-Negotiable Elegance Test

The architecture is not done because the main path works. It is done only when
there is exactly one answer to each identity question:

| Question | Only acceptable owner |
| --- | --- |
| Who creates production visible row IDs? | Relay projection package. |
| Who creates production visible row order? | Relay projection package. |
| Who says a cache row is valid? | Projection contract fingerprint. |
| Who proves what the UI should show? | Retained relay projection witness. |
| Who applies stream operations on the phone? | One Swift projection table. |
| Who may read raw Codex history for display? | Relay adapters only; never Swift production display. |
| Who may construct expected UI IDs in tests? | Projection-engine unit tests and generated fixtures only; proof tests use witnesses. |
| Who may use request IDs as identity? | Nobody; request IDs route responses only. |
| Who may use endpoint host names as source identity? | Nobody; endpoint host names are routing labels only. |

If any implementation path answers one of these questions differently, that
path is a side door and the cutover is incomplete.

### Three Concepts Must Stay Separate

| Concept | Owner | Meaning | Can it change? |
| --- | --- | --- | --- |
| `sourceRef` | Relay projection engine | Stable reference to the upstream Codex fact: host, thread, turn, item, request, system row, or diagnostic fact. | Only through an explicit supersession operation. |
| `projectionID` | Relay projection engine | Stable visible row identity derived from `sourceRef` plus row role. | No. A new `projectionID` means a new visible row. |
| `revision` | Relay projection ledger | Content version for the same `projectionID`. | Yes. Streaming, settled text, request status, and stale/fresh changes are revisions. |

This split is the core fix. Without it, request IDs, thread IDs, event IDs, and
row bodies keep competing to answer "same row or new row?"

### Revision Apply Law

`revision` is monotonic for one `projectionID` under one
`sourceHostID + identityVersion + projectionEngineVersion` namespace.

Rules:

1. The relay increments `revision` whenever payload, freshness, render state, or
   request status changes for a `projectionID`.
2. Swift stores the latest accepted revision for each `projectionID`.
3. An `upsert` with a higher revision replaces the current row.
4. An `upsert` with the same revision is idempotent only if the retained row
   content hash matches. Same revision plus different content is a projection
   contract error that forces resync.
5. An `upsert` with a lower revision is stale and cannot replace the current
   row. The table reports a stale-update/resync condition instead of silently
   moving backward.
6. A `snapshot` may replace a scope only when its rows are not older than
   already accepted rows in the same projection namespace. If the stream epoch
   changes because the contract fingerprint changed, the table clears the old
   namespace before applying the snapshot.
7. `delete` removes by `projectionID` regardless of revision, but the delete
   still obeys stream `epoch` and `seq`.

This prevents stale cache materialization from overwriting newer live state.

### Version Bump Policy

`revision`, `schemaVersion`, `identityVersion`, and
`projectionEngineVersion` are separate levers:

| Field | Bump when | Must not be used for |
| --- | --- | --- |
| `revision` | The content, freshness, render state, request status, or payload for the same `projectionID` changes. | Changing identity or cache contract. |
| `schemaVersion` | The projection wire shape changes. | Changing only row identity rules. |
| `identityVersion` | The algorithm for `sourceRef` or `projectionID` changes for any visible row class. | Routine payload/render updates. |
| `projectionEngineVersion` | Projection logic changes output membership, order, freshness, row roles, view params, or payload interpretation without changing wire shape or ID grammar. | Per-row content updates. |

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
- `view`
- `threadID` when present
- `schemaVersion`
- `identityVersion`

If an `upsert` repeats a `projectionID` with any of those fields changed, the
client rejects the update, marks the view stale, and requests resync. It does
not choose one source locally.

`revision` must increase when payload, freshness, render state, request status,
or diagnostic content changes for the same `projectionID`. If an `upsert`
inside the same epoch carries a lower `revision`, the client rejects it as stale
or requests resync. If the same `revision` carries different payload content,
the client treats it as a projection contract violation and requests resync.

### Epoch And Watermark Rules

`epoch` is a relay-generated stream generation identifier. It is unique within
`sourceHostID + view + scope + viewParamsKey` and is created by the relay when a
projection stream starts, resyncs after stale state, changes `identityVersion`,
changes `projectionEngineVersion`, or detects unrecoverable sequence/source
loss. A new `epoch` is valid only when delivered with a replacement snapshot.
Updates cannot silently hop epochs.

`sourceWatermark` is upstream freshness evidence, not row identity. It records
the raw Codex history/live point the relay normalized into the projection
ledger. Swift may display or log it as freshness context, but it cannot use it
to create, sort, dedupe, or delete rows. If the relay cannot prove a watermark
is compatible with the current projection cache contract, the affected view is
stale until resync.

## Canonical Projection Row

Every displayed thing should use one envelope shape:

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "thread.detail",
  "projectionID": "host:amir-m5/thread:019e.../turn:t1/item:i1/row:userMessage",
  "sourceRef": "host:amir-m5/thread:019e.../turn:t1/item:i1",
  "rowRole": "userMessage",
  "displayOrderKey": "9998239345599999|0000000000|9999999999|9999999999|host%3Aamir-m5...",
  "revision": 4,
  "freshness": {
    "state": "fresh",
    "asOf": "2026-06-01T00:00:00.000Z"
  },
  "payload": {}
}
```

View payloads can differ. The identity, order, version, freshness, and update
fields cannot.

## Schema Single Source Of Truth

The final contract source of truth should move to `contract/projection/**`.
View-specific schemas can live under that package, but they must share one
projection envelope schema.

Required package shape:

```text
contract/projection/projection-envelope.schema.json
contract/projection/projection-snapshot.schema.json
contract/projection/projection-update.schema.json
contract/projection/projection-witness.schema.json
contract/projection/row-role.schema.json
contract/projection/view-params.schema.json
contract/projection/payloads/dock-thread-card.schema.json
contract/projection/payloads/thread-detail-row.schema.json
contract/projection/payloads/host-row.schema.json
contract/projection/payloads/system-health-row.schema.json
contract/projection/fixtures/*.json
scripts/generate-projection-contract.mjs
scripts/check-projection-contract.mjs
CodexDock/AppServer/ProjectionDTO.swift
```

Rules:

1. `contract/projection/projection-envelope.schema.json` owns the common
   envelope.
2. `contract/projection/projection-snapshot.schema.json` and
   `contract/projection/projection-update.schema.json` own snapshot/upsert/
   delete/transaction/heartbeat/resync operation shape.
3. Payload schemas live under `contract/projection/payloads/*.schema.json`.
4. Swift DTOs and any Node validation types are generated from those schemas.
5. `contract/dock/dock-thread-card.schema.json` cannot remain a second
   production display schema after cutover. It must either be deleted, moved
   under the projection contract, or marked historical/test-only.
6. Schema validation rejects unknown envelope identity fields with
   `additionalProperties: false`.
7. The contract generator fails if legacy names such as `cards`,
   `upsertCards`, `deleteCardIDs`, `baseSeq`, `stateGeneration`, `orderKey`, or
   `logicalHostID` appear in a production projection envelope.
8. `contract/projection/row-role.schema.json` owns all row roles. Generated
   Swift/Node enums must use it rather than hand-maintained role strings.

This is not a prose preference. It is how we prevent Swift, relay code, tests,
and proof scripts from drifting into separate DTO dialects again.

No phone-facing production route, Swift display DTO, proof schema, or
acceptance fixture may keep card-v2 or raw Thread Detail as a parallel display
contract after cutover. Historical fixtures may remain only when they are named
as migration history and excluded from acceptance truth.

### Row Role Registry

Initial row roles:

| View family | Roles |
| --- | --- |
| Thread cards | `threadCard` |
| Thread Detail messages | `userMessage`, `agentMessage`, `plan`, `reasoning`, `command`, `commandOutput`, `fileChange`, `toolCall`, `request`, `system`, `unknown` |
| Host registry | `host` |
| System health | `healthRow` |
| Diagnostics | `unknown`, plus payload diagnostic code |

Adding a role is a contract change: update the row-role schema, regenerate DTOs,
update the projection engine, and add negative tests for unknown production
roles.

### View Payloads

| View | Row role examples | Payload owns | Payload must not own |
| --- | --- | --- | --- |
| `dock` | `threadCard` | title, summary, status, repo, branch, relationship, archive state | row identity, source host identity, display order |
| `archive` | `threadCard` | same thread-card payload, archive membership | separate card identity |
| `archive.cleanup` | `threadCard`, `cleanupCandidate` if needed | cleanup-specific metadata | separate cleanup row identity for the same thread card |
| `thread.detail` | `userMessage`, `agentMessage`, `plan`, `reasoning`, `command`, `commandOutput`, `fileChange`, `toolCall`, `request`, `system`, `unknown` | visible text, request controls, render state, diagnostics | request-card identity, event identity, sort order |
| `host.registry` | `host` | labels, endpoints, health summary | source host identity |
| `system.health` | `healthRow` | route health, lag, freshness, proof status | source data identity |

### Secondary View Routes

Every visible view gets the same projection contract and the same witness
requirement. These routes are part of the target architecture, not optional
nice-to-have cleanup:

| Route | View | Required proof |
| --- | --- | --- |
| `dock/subscribe`, `dock/resync`, `dock/update` | `dock` | Projection witness plus simulator UI dump. |
| `archive/subscribe`, `archive/resync`, `archive/update` | `archive` | Projection witness plus simulator UI dump. |
| `archive.cleanup/subscribe`, `archive.cleanup/resync`, `archive.cleanup/update` | `archive.cleanup` | Projection witness plus simulator UI dump. |
| `host/registry/subscribe`, `host/registry/resync`, `host/registry/update` | `host.registry` | Projection witness plus simulator UI dump. |
| `system/health/subscribe`, `system/health/resync`, `system/health/update` | `system.health` | Projection witness plus simulator UI dump. |
| `thread/detail/read`, `thread/detail/subscribe`, `thread/detail/resync`, `thread/detail/update` | `thread.detail` | Projection witness plus simulator UI dump. |

If a view is not yet implemented, it must be explicitly out of the current
implementation phase. It cannot remain as a parallel non-projection display
path.

### Initial Read Route Law

Routes named `read`, `load`, `refresh`, `resync`, or `subscribe` are transport
entry points only. They do not get separate identity semantics.

Rules:

1. If a phone-facing route can populate a visible screen, it must return the
   same `ProjectionRow` envelope and snapshot/update grammar as the
   corresponding stream route.
2. `thread/detail/read` may remain only as an initial projection snapshot for
   `view: "thread.detail"`. It must not return raw Codex history, raw events,
   request cards, local fixture rows, or a screen-shaped DTO with different
   identity rules.
3. A route that cannot produce the projection contract must be diagnostic-only
   or relay-internal. Swift production display stores and simulator acceptance
   proof cannot call it.
4. Route names do not define display truth. `sourceHostID`, `view`, `scope`,
   `viewParamsKey`, `epoch`, `seq`, `projectionID`, `sourceRef`, `rowRole`,
   `displayOrderKey`, and `revision` define display truth.

## Canonical Stream Envelope

Every relay-owned visible stream should use the same operation grammar:

```json
{
  "kind": "snapshot",
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "amir-m5",
  "view": "dock",
  "scope": "view",
  "viewParamsKey": "sha256:...",
  "epoch": "stream-epoch",
  "seq": 42,
  "order": "displayOrderKeyAscending",
  "complete": true,
  "totalRows": 10,
  "window": {
    "offset": 0,
    "limit": 50,
    "rowCount": 10,
    "nextOffset": null,
    "bounds": {
      "firstDisplayOrderKey": "9998239345599999|...",
      "lastDisplayOrderKey": "9998239345609999|..."
    }
  },
  "freshness": {},
  "rows": [],
  "projectionIDs": []
}
```

Allowed operations:

- `snapshot`: replace the declared scope/window with `rows`.
- `upsert`: insert or replace rows by `projectionID`.
- `delete`: remove rows by `projectionID`.
- `transaction`: apply an ordered `operations` array atomically inside one
  stream `seq`.
- `heartbeat`: update stream/freshness state without row mutation.
- `resyncRequired`: invalidate local table state and request a snapshot.

### Stream Sequence Continuity Law

For each active stream keyed by
`sourceHostID + view + scope + viewParamsKey + epoch`, Swift maintains
`lastAcceptedSeq`.

Rules:

1. A replacement `snapshot` establishes `epoch` and `lastAcceptedSeq`.
2. Every non-snapshot mutation operation must carry
   `seq == lastAcceptedSeq + 1`.
3. A duplicate `seq` with byte-for-byte identical payload is idempotent.
4. A duplicate `seq` with different payload is a contract violation that forces
   resync.
5. A gap (`seq > lastAcceptedSeq + 1`) or backward sequence invalidates the
   stream and requests snapshot resync.
6. Heartbeats carry the current `seq` and freshness state without mutating row
   membership.
7. A `transaction` consumes exactly one `seq` no matter how many ordered
   operations it contains.

Forbidden in the final architecture:

- `delta`
- `baseSeq`
- `stateGeneration`
- `cards`
- `cardIDs`
- `upsertCards`
- `deleteCardIDs`
- `sessions`
- `upsertSessions`
- `deleteSessionIDs`
- raw `event=` identity in proof output
- `messageCardIDs`
- `requestCardIDs`

If a compatibility bridge is temporarily required, it must be outside the
production app path, time-boxed, and rejected by contract/proof gates before the
architecture is considered complete.

### Cross-View Scope And Snapshot Authority

Snapshot replacement authority is determined only by `sourceHostID`, `view`,
`scope`, `viewParamsKey`, and declared window/thread bounds. It is never
inferred from row IDs.

| View/scope | Replacement authority |
| --- | --- |
| Any view with `scope: "view"` | Replace all local rows for `sourceHostID + view + viewParamsKey`. Rows absent from the snapshot are deleted from that view membership. |
| Dock/Archive/Archive Cleanup with `scope: "host"` | Replace all local rows for `sourceHostID + view + viewParamsKey` for that source host. |
| Any list view with `scope: "window"` | Replace only rows whose `displayOrderKey` falls inside `window.bounds.firstDisplayOrderKey...window.bounds.lastDisplayOrderKey`. Missing or malformed bounds invalidate the snapshot and force resync. |
| Thread Detail with `scope: "thread"` | Replace all rows for `sourceHostID + threadID + viewParamsKey`. Rows absent from the snapshot are deleted from that thread view. |

Swift must not merge snapshot rows with retained out-of-scope rows by guessing.
If the snapshot does not declare enough scope/window/thread authority, Swift
rejects it and requests resync.

### Mutation Scope Law

Window bounds constrain snapshot replacement only. They do not change mutation
identity.

Rules:

1. `upsert` always inserts or replaces the exact `projectionID`s named by the
   operation within the active `sourceHostID + view + viewParamsKey + epoch`
   namespace.
2. `delete` always removes the exact `projectionID`s named by the operation
   within the active `sourceHostID + view + viewParamsKey + epoch` namespace.
3. Swift must not reject, trim, or reinterpret an `upsert` only because its
   `displayOrderKey` falls outside the previous snapshot's `window.bounds`.
4. Swift must not delete rows by omission from an `upsert`; omission deletes
   rows only in a replacement `snapshot` whose scope/window/thread authority
   explicitly covers those rows.
5. The relay owns whether a mutation belongs on a windowed stream. If the relay
   emits it on that stream, the client applies it by `projectionID` or rejects
   the whole envelope for a contract violation.

This prevents windowed views from becoming local membership heuristics. The
stream tells the phone the exact rows that changed; snapshots tell the phone
what range can be replaced by absence.

### Cross-View Update Authority

Cross-view consistency is relay-owned.

Rules:

1. Production Swift must not trigger projection resync or row replacement for
   view A based only on activity observed in view B.
2. Dock row activity advancing while Thread Detail is open is handled by the
   relay projection ledger emitting the appropriate projection operations to
   every subscribed view.
3. Client-side cross-view resync heuristics are forbidden after cutover.
4. Manual user navigation may request the target view's snapshot/resync, but it
   must not merge or reinterpret another view's rows.

This removes the current class of timing bug where one screen notices activity
and asks another screen to rebuild itself through a different path.

### View Params Key Registry

`viewParamsKey` is the stable hash of the query that defines a stream's row
membership. It is not a display label.

Computation rule:

```text
viewParamsKey = "sha256:" + sha256(stableStringify(canonicalViewParams))
```

`stableStringify` sorts object keys, preserves array order, and serializes nulls
explicitly. Every view must publish its canonical params in docs and tests.

Initial registry:

| View | Canonical params |
| --- | --- |
| `dock` | `{ "view": "dock", "archiveState": "active", "visibility": "appFacingHuman", "sort": "displayOrderKeyAscending" }` |
| `archive` | `{ "view": "archive", "archiveState": "archived", "visibility": "appFacingHuman", "sort": "displayOrderKeyAscending" }` |
| `archive.cleanup` | `{ "view": "archive.cleanup", "archiveState": "archived", "mode": "cleanupCandidates", "sort": "displayOrderKeyAscending" }` |
| `thread.detail` | `{ "view": "thread.detail", "threadID": "<threadID>", "visibility": "all", "rowRoles": null, "search": "", "includeDiagnostics": true, "sort": "displayOrderKeyAscending" }` |
| `host.registry` | `{ "view": "host.registry", "sort": "sourceHostIDAscending" }` |
| `system.health` | `{ "view": "system.health", "scope": "appCriticalRoutes", "sort": "routeAscending" }` |

If filters become relay-side in the future, the filter params are part of
`canonicalViewParams`. If filters remain local UI decoration, they are not.

## Relay Ownership

The relay owns all visible identity because it is the only layer that sees all
inputs:

- raw Codex thread list state;
- raw Codex thread history;
- live app-server notifications;
- active JSON-RPC server requests;
- local relay cache state;
- source host identity;
- freshness and completeness proof;
- stream sequence and reconnect state.

Swift sees only the projection contract. That is intentional. The client should
not repair identity because it cannot know enough to do it correctly.

### Reference Component Boundaries

The clean permanent architecture has these components and only these
responsibilities:

| Component | Owns | Must not own |
| --- | --- | --- |
| Raw Codex adapters | Fetching and subscribing to raw upstream state: `thread/list`, `thread/read`, `thread/turns/list`, `thread/resume`, live notifications, and server requests. | Visible identity, UI order, freshness labels, Swift DTO shape, or proof truth. |
| Source host identity provider | Stable `sourceHostID` for the Codex source. | Endpoint labels, relay process identity, phone host config IDs, or display names. |
| Projection engine | `sourceRef`, `projectionID`, `rowRole`, `displayOrderKey`, freshness classification, diagnostics, pending/canonical supersession, and ledger operations. | WebSocket lifecycle, SQLite I/O, Swift rendering, or test-only shortcuts. |
| Projection store | Materialized projection rows, view memberships, epochs, sequence numbers, and cache contract versions. | Raw Codex as durable truth or screen-specific identity grammars. |
| View stream routers | `dock/*`, `archive/*`, `archive/cleanup/*`, `host/registry/*`, `system/health/*`, and `thread/detail/*` snapshots, updates, heartbeats, and resyncs over JSON-RPC. | Recomputing row identity or order. |
| Swift projection table | Applying projection snapshots/updates and publishing render state. | Parsing raw Codex display rows, recovering missing identity, fallback sorting, or deduping by body/request ID. |
| Screen projectors | Turning payloads plus local decoration into view models. | Creating row membership, row identity, order, freshness, or cache validity. |
| Phone saved host config | Bootstrap endpoint list used to connect to relays. | `sourceHostID`, `sourceRef`, `projectionID`, host row identity, or freshness proof. |
| UI and automation | Rendering projection rows and exposing `projectionID`-based accessibility IDs. | Creating production row IDs or acting as proof truth. |
| Proof tools | Comparing UI dumps to retained relay projection witnesses. | Building a second raw-Codex oracle for expected display identity. |

The projection engine is the only identity brain. Runtime code does I/O. Swift
applies and renders. Proof compares. SQLite stores. None of those layers answer
"is this the same visible row?" again.

### Universal Projection Store

The projection store should not be a Dock cache, an Archive cache, and a Thread
Detail cache with similar rules. Use one canonical storage model:

```text
projection_contracts
  sourceHostID
  schemaVersion
  identityVersion
  projectionEngineVersion
  projectionContractFingerprint
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

projection_pending_rows
  sourceHostID
  threadID
  stablePendingID
  pendingProjectionID
  clientMutationID
  upstreamNotificationID
  firstObservedAt
  expiresAt

projection_ledger_operations
  sourceHostID
  ledgerSeq
  projectionContractFingerprint
  transactionID
  reason
  operationsJSON
  affectedViewsJSON
  emittedAt

projection_view_memberships
  sourceHostID
  view
  scope
  viewParamsKey
  projectionID
  membershipState
  displayOrderKey

projection_stream_epochs
  sourceHostID
  view
  scope
  viewParamsKey
  epoch
  seq
  complete
  freshness
```

Dock active rows, Archive rows, Archive Cleanup rows, Host Registry rows, System
Health rows, and Thread Detail rows are all projection rows plus view
membership. Moving a thread from Dock to Archive changes membership or payload
state; it does not invent a second card identity.

The existing SQLite `threads` table can be migrated or replaced. The elegant
target is the universal model above because it removes screen-specific identity
storage instead of teaching multiple tables the same rules.

### Ledger Timeline Decision

The relay should have one append-only projection ledger per `sourceHostID`.
Client streams can still have per-view `epoch` and `seq` because a phone
subscribes to views, not to every row in the source host.

Rules:

1. Raw Codex changes, local metadata changes, request-state changes, archive
   mutations, and pending supersessions become projection ledger operations
   before they are emitted to any phone-facing display route.
2. `projection_ledger_operations.ledgerSeq` is the relay's source-host-wide
   ordering evidence. It is useful for witnesses, diagnostics, and fan-out, but
   it is not visible row identity.
3. Per-view stream `seq` is transport continuity for one subscribed
   `sourceHostID + view + scope + viewParamsKey + epoch`.
4. A route may filter ledger operations by view membership to emit a per-view
   stream, but it must not invent or rewrite identity/order while doing so.
5. Snapshots are materialized from the same projection rows and memberships
   produced by the ledger. Initial reads, resyncs, and live updates do not get
   separate projection code paths.

This keeps the relay internally elegant: one source-host timeline feeds every
view, while the phone receives only the view-specific stream it can validate.

### Projection Engine Boundary

There should be one production module that owns all helpers named like:

- `sourceRefFor*`
- `projectionIDFor*`
- `displayOrderKeyFor*`
- row-role mapping
- source-host segment escaping
- projection-engine version constants
- source alias/supersession rules

Today that is closest to `scripts/dock-relay-projection-engine.mjs`. The final
architecture should promote it from a helper file to the projection package that
feeds all relay views and all contract fixtures.

No production code outside that package should create a `projectionID` or
`displayOrderKey`.

## Host Binding Law

`sourceHostID` is the stable identity of the Codex source host. It is not:

- the phone's saved endpoint;
- the relay process instance ID;
- Bonjour/Tailscale/LAN address text;
- a display name;
- a Swift `DockHostConfiguration.id` alias.

The binding contract is:

1. The relay resolves `sourceHostID` once from explicit config/env or a stable
   relay-owned source-host file.
2. `initialize` exposes the authoritative `sourceHostID` and projection
   contract fingerprint for the connected route before any display stream
   subscription is accepted.
3. Every projection row includes `sourceHostID`.
4. Every projection stream includes `sourceHostID`.
5. Swift projection tables partition and validate by `sourceHostID`, not by the
   endpoint config ID.
6. Multiple saved endpoints may point to one source host. They must converge to
   one `sourceHostID` and one row namespace.
7. `DockHostIdentityResolver`-style client alias logic may help route actions or
   display endpoint labels, but it must not own row membership or visible row
   identity.
8. A row whose `sourceHostID` does not match the connected relay source host is
   rejected as a stream contract error.
9. Endpoint and display names are labels only.

Required `initialize` response fields:

```json
{
  "relayInstanceID": "process-instance-for-diagnostics-only",
  "sourceHostID": "amir-m5",
  "projectionSchemaVersion": 1,
  "projectionIdentityVersion": 1,
  "projectionEngineVersion": 1,
  "projectionContractFingerprint": "sha256:..."
}
```

`relayInstanceID` can change across restarts and is never display identity.
`sourceHostID` is the display identity namespace. The client records the
handshake values before subscribing to projection streams and rejects streams
whose version or `sourceHostID` differs.

Client rejection behavior:

1. If `initialize` lacks `sourceHostID`, `projectionSchemaVersion`,
   `projectionIdentityVersion`, `projectionEngineVersion`, or
   `projectionContractFingerprint`, Swift must not subscribe to projection
   display streams.
2. If any stream envelope differs from the handshake `sourceHostID` or version
   tuple, Swift rejects the envelope, marks that view stale, and requests
   resync. It does not render partial rows from that envelope.
3. If a reconnect produces a different `sourceHostID` for the same saved
   endpoint, Swift treats it as a different Codex source host and clears the old
   projection namespace before rendering the new one.

This prevents "same Mac through a different URL" from becoming two visual
hosts.

### Host Metadata Channel Law

Host identity and host display metadata are projection data too.

Rules:

1. Production display streams must not carry parallel host arrays such as
   `hosts`, `upsertHosts`, `deleteHostIDs`, or host-scoped identity maps outside
   projection rows.
2. Host Registry display truth comes from `view: "host.registry"` projection
   rows keyed by `sourceHostID`.
3. Thread-card payloads may include denormalized host display labels for
   convenience, but those labels are payload text only. They cannot create host
   membership, source identity, or row identity.
4. Swift may cache host labels as local render decoration keyed by
   `sourceHostID + projectionID` or by the Host Registry row's `projectionID`,
   but it must not build a second host table from Dock/Archive stream side
   fields.
5. Any route that still needs connection/bootstrap host choices must keep them
   outside display truth. Connection endpoints help the phone reach a relay;
   they do not define the relay's source host.

This closes the remaining endpoint-alias side door: one source host cannot be
split into multiple visual hosts by a side-channel host list.

## Pending Supersession Grammar

The outbound-message duplicate class requires one explicit rule:

If the relay sees a live fact before canonical history has enough identity, it
must not invent a permanent independent row.

Allowed cases:

1. The live fact contains enough source identity.
   The relay emits the final `projectionID` immediately.

2. The live fact is provably pending but not canonical yet.
   The relay emits a pending projection row under a pending source ref, then
   later emits an explicit atomic supersession transaction that deletes the
   pending `projectionID`, upserts the canonical `projectionID`, and preserves
   request/composer status as payload state where appropriate.

3. The live fact cannot be tied to a source identity.
   The relay emits a diagnostic row or marks the stream stale. It does not emit
   a normal user/agent/request row.

Pending rows use a distinct source-ref namespace:

```text
host:<sourceHostID>/thread:<threadID>/pending:<stablePendingID>/row:<rowRole>
```

`stablePendingID` must come from a relay-observed stable fact such as a client
turn start token, upstream notification ID, or relay-generated pending ledger ID.
It must not be body text, timestamp, array index, or request ID alone.

Stable pending ID precedence is first match wins:

1. `clientMutationID` from the mutation route, when present.
2. Upstream live notification ID, when present and unique within
   `sourceHostID + threadID`.
3. Relay pending-ledger ID assigned at first observation.

Body text, timestamps, array indexes, and `requestID` alone must never be used
as `stablePendingID`.

`clientMutationID` contract:

1. `turn/start` and any future client-initiated outbound-content mutation must
   include `clientMutationID` when the phone/client expects an optimistic or
   live-ahead visible row.
2. `clientMutationID` is an opaque string unique within
   `sourceHostID + threadID` for the in-flight mutation.
3. The relay echoes `clientMutationID` in the mutation response and stores it in
   the pending ledger.
4. The relay uses `clientMutationID` as `stablePendingID` precedence #1.
5. The relay rejects or ignores body text, timestamps, array indexes, and
   `requestID` as pending identity.

Canonical rows use canonical source refs:

```text
host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/row:<rowRole>
host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/request:<requestID>/row:request
host:<sourceHostID>/thread:<threadID>/request:<requestID>/row:request
```

Supersession is an explicit ledger transaction, not a client merge heuristic:

```json
{
  "kind": "transaction",
  "transactionID": "supersession:host%3Aamir-m5%2Fthread%3At%2Fpending%3Ap%2Frow%3AuserMessage",
  "reason": "supersession",
  "operations": [
    {
      "kind": "delete",
      "projectionIDs": ["host:amir-m5/thread:t/pending:p/row:userMessage"]
    },
    {
      "kind": "upsert",
      "supersedesProjectionID": "host:amir-m5/thread:t/pending:p/row:userMessage",
      "rows": [
        {
          "projectionID": "host:amir-m5/thread:t/turn:turn-1/item:item-1/row:userMessage",
          "sourceRef": "host:amir-m5/thread:t/turn:turn-1/item:item-1"
        }
      ]
    }
  ]
}
```

Version 1 uses `transaction` with ordered `operations[]` for supersession.
Separate delete-at-`seq=N` plus upsert-at-`seq=N+1` is not acceptable for
pending-to-canonical replacement because it creates a user-visible gap and a
proof ambiguity.

Supersession apply rule:

1. Swift applies pending-to-canonical supersession as one logical row
   transition inside one projection-table transaction.
2. The UI must not show both pending and canonical rows in the same render
   generation.
3. The UI must not publish an intermediate render between transaction
   operations.
4. The intermediate delete may become user-visible only if the relay explicitly
   marks the pending row stale or failed before deleting it.

The phone never merges pending and canonical rows by body text, request ID, or
timestamp. The ledger tells it exactly what to delete and upsert.

## Request Row Identity Law

Request controls are payload state attached to projection rows.

`requestID` is only the JSON-RPC response-routing token. It may be stored in
payload so the app can answer the request, but it must not be visible row
identity.

Final rule:

- `ServerRequestCard.id == projectionID`.
- `AutomationID.RequestCard.*` uses the projection row ID.
- `respond(to:)` accepts projection row ID, looks up payload.requestID, and
  sends the JSON-RPC response by request ID.
- No production path renders `ServerRequestCard.make(from: JSONRPCRequest)` as
  a standalone visible card.
- Swift must not maintain a parallel `requestCards` collection as display
  truth. Request controls render from Thread Detail projection rows filtered by
  `rowRole == request` or request payload on item rows. Transient
  `responding`/`failed` UI state may exist only when keyed by `projectionID`.
- `ThreadDetailScreenStore` and render projectors must not accept a parallel
  `requestCards` collection as display truth. Request-card render adapters may
  be rebuilt from projection rows, but they cannot be passed around as a second
  row source.

Decision tree:

1. If a request is provably attached to a visible thread item, the request
   controls attach to that item's projection row payload, unless the row role
   needs to be `request` for the product experience.
2. If a request is a visible request row, its projection ID includes the
   canonical item identity when known:

   ```text
   host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/request:<requestID>/row:request
   ```

3. If a request is thread-scoped and not tied to a turn/item, its projection ID
   is:

   ```text
   host:<sourceHostID>/thread:<threadID>/request:<requestID>/row:request
   ```

4. The same proven request/item relationship can never produce both an
   item-attached control row and a standalone request row.
5. If a request starts as standalone and later becomes item-attached, the relay
   emits explicit supersession/delete+upsert operations.

This removes the current split where a request can be `request-\(request.id)` in
one path and `event.id` in another path.

## Mutation Routes Are Not Display Truth

Commands can cause the projection ledger to change, but commands do not render
rows directly.

Mutation routes include:

- `turn/start`
- `turn/steer`
- `turn/interrupt`
- JSON-RPC request responses
- archive/unarchive
- local label and pin edits

Rules:

1. A mutation returns command status, not display rows.
2. The relay updates the projection ledger after the mutation changes raw Codex
   state, request state, local metadata, or archive membership.
3. The phone sees the result through the relevant projection stream or an
   explicit projection resync.
4. Swift must not insert a local "optimistic" visible row unless the relay first
   emits a projection row for that optimistic state.
5. A local failure leaves command UI/error state; it does not create fallback
   display identity.
6. Composer draft text, send-in-flight UI, voice capture phase, transcript
   staging, and dictation state are local command UI state. They must not create
   Thread Detail visible rows, `projectionID`s, or proof-oracle rows.

This prevents `turn/start` or request response plumbing from becoming another
hidden row source.

## Swift Client Architecture

Swift should have one generic projection table, not one reducer per screen.

```text
ProjectionStreamDTO<RowPayload>
  -> ProjectionTable<RowPayload>
  -> ScreenProjector<RowPayload, ViewModel>
  -> SwiftUI render
```

The table owns:

- schema/version validation;
- source host validation;
- view/viewParamsKey validation;
- stream state partitioning by handshake `sourceHostID`, never phone config
  host ID;
- epoch/seq continuity;
- snapshot/window replacement;
- upsert/delete by `projectionID`;
- heartbeat/freshness state;
- duplicate `projectionID` rejection;
- row ordering by `displayOrderKey`, then `projectionID`.

The screen projector owns:

- payload-to-view-model mapping;
- user-selected filters;
- local UI-only decorations such as pin state, labels, and rail colors;
- action routing from row payload to commands.

The SwiftUI view owns:

- layout;
- buttons;
- accessibility exposure of the already-owned `projectionID`.

SwiftUI must not:

- infer identity from a thread ID, request ID, raw event ID, or list index;
- infer recency from timestamps when `displayOrderKey` is missing;
- suppress duplicates by body text;
- keep stale duplicate accessibility nodes through nested `.id` modifiers;
- treat a JSON-RPC request as a row unless it arrived inside a projection row.

### Subscribe And Resync Buffering Law

While a view awaits its first post-handshake snapshot or an epoch-replacement
snapshot, Swift may buffer projection envelopes but must not apply row mutations
to the projection table or publish render state from them.

Rules:

1. Buffered envelopes are applied only after a valid replacement snapshot
   establishes `sourceHostID`, `view`, `viewParamsKey`, `epoch`, and `seq`.
2. Buffered envelopes are discarded on epoch change, resync failure, handshake
   mismatch, viewParamsKey mismatch, or sequence gap.
3. No buffered row mutation may create visible UI before the base snapshot is
   accepted.

### Swift Render Adapter Law

Types such as `ThreadEvent`, `DockRowViewModel`, and `ServerRequestCard` are
render adapters. They are not identity sources.

Rules:

1. Production render adapters are initialized only from validated projection
   rows.
2. Render adapter `id` equals `projectionID`.
3. Missing `displayOrderKey` is a projection contract failure, not a fallback
   sort opportunity.
4. `ThreadEventDisplayOrder` can exist only as projection-row ordering by
   `displayOrderKey`, then `projectionID`, for production data.
5. Any legacy raw-event ordering helper must live under explicit test-only
   names and must not be reachable from production stores.
6. Preview rows must use generated projection fixtures, not hand-built raw
   event identity.

### Local Decoration Law

Pins, filters, labels, rail colors, search text, selected status chips, and
accessibility exposure decorate projection rows. They do not create rows.

Rules:

1. Durable local metadata is keyed by `sourceHostID + projectionID`.
2. Manual pinning can change group placement only through explicit local UI
   decoration; it does not alter relay `displayOrderKey`.
3. Filters hide or show already-projected rows. They do not request a different
   identity namespace unless the viewParamsKey explicitly changes.
4. Accessibility IDs expose `projectionID`; they do not become another identity
   source.
5. `HostScopedThreadID`, configured host ID, endpoint label, and `logicalHostID`
   must not be used as durable decoration keys in production after cutover.
6. Alias resolution may map an action target to a `projectionID` at command
   time only. It must not create a parallel decoration namespace.
7. Durable local metadata must migrate to
   `LocalProjectionDecorationKey { sourceHostID, projectionID }`.
   `LocalThreadMetadataKey` lookups are allowed only as one-shot migration reads
   that resolve to exactly one current `projectionID`.

## DTO And Schema Shape

The final DTO should make old identity impossible at decode time.

Recommended direction:

1. Replace `DockThreadCardDTO` as the stream row type with a generated
   `ProjectionRowDTO<DockThreadCardPayloadDTO>` equivalent, or the closest
   Swift-compatible non-generic generated form.
2. Make `schemaVersion`, `identityVersion`, `projectionEngineVersion`,
   `sourceHostID`, `view`, `projectionID`, `sourceRef`, `rowRole`, and
   `displayOrderKey` required, not optional.
3. Move old card fields into `payload`.
4. Remove `orderKey` from the projection envelope. If a legacy order value is
   needed for diagnostics, put it in a diagnostic payload field that cannot be
   used for sorting.
5. Remove `logicalHostID` from the projection envelope. Source identity is
   `sourceHostID`. If old logical-host text must be shown for diagnostics, it is
   payload text only and never a lookup key.
6. Generate Swift DTOs from the schema. Do not hand-maintain parallel Swift
   shapes.
7. Reject additional properties in schema for projection envelopes and rows.
8. Either delete top-level `id` or enforce `id === projectionID` in schema and
   generated Swift. The preferred final state is no separate top-level `id`.

The important point is not the exact class name. The important point is that
the generated DTO has one identity vocabulary, not old and new fields side by
side.

### Dock And Archive Cutover Is Normative

Dock and Archive are not allowed to stay on a parallel card stream grammar. They
must move from the transition card stream to the shared projection stream.

Current transition shape:

```text
DockThreadCardDTO
id
logicalHostID
rows carrying card payload fields beside projection fields
```

Target projection shape:

```text
ProjectionRow<DockThreadCardPayload>
projectionID: host:<sourceHostID>/thread:<threadID>/row:threadCard
sourceHostID
identityVersion
projectionEngineVersion
displayOrderKey
payload: { title, summary, status, repo, branch, archiveState, ... }
```

Normative mapping:

| Current field/concept | Target projection contract |
| --- | --- |
| `DockThreadCardDTO.id` | Removed as independent identity. During migration it may exist only when byte-for-byte equal to `projectionID`. |
| `logicalHostID` | Payload alias only during migration; it must validate one-to-one against `sourceHostID` and cannot appear in identity decisions. |
| card payload fields beside envelope fields | Move under `payload`. Envelope fields stay common across all views. |
| `delta` | Replaced by explicit `upsert` and `delete` operations everywhere. |
| `upsertCards` | `rows` where each row has the shared projection envelope plus a typed payload. |
| `deleteCardIDs` | `projectionIDs`. |
| `stateGeneration` | Removed; `epoch` and `seq` are the stream continuity contract. |
| `baseSeq` | Removed unless the shared projection contract later adopts it for all views. Do not keep it Dock-only. |
| archive membership | `projection_view_memberships`, not a second card identity. |

Cutover rules:

1. A temporary translation layer may exist inside the relay, but the
   phone-facing production route must emit the target projection shape before
   acceptance.
2. `dock/subscribe`, `dock/resync`, `archive/subscribe`, and `archive/resync`
   may keep their route names. Route names are transport; payload grammar is
   what must converge.
3. No final pass is allowed while Swift display code, proof scripts, or schema
   fixtures accept card-v2 `delta`, `logicalHostID::threadID`, flattened card
   identity, or card-specific delete/update grammar as production truth.
4. If a compatibility payload carries both `id` and `projectionID`, they must
   be byte-for-byte equal or the client must reject the payload and request
   resync.

## Cache Architecture

Persistent cache must not own visible identity. It may store source facts and
projection materialization, but every stored value must be tied to the same
projection contract fingerprint.

The fingerprint is:

```text
schemaVersion
+ identityVersion
+ projectionEngineVersion
+ sourceHostID
+ view
+ viewParamsKey
```

Rules:

1. Raw source cache can survive projection version bumps only if it stores raw
   upstream facts and is reprojected before serving.
2. Projection row cache cannot be served unless its fingerprint matches the
   active projection engine.
3. Relay startup invalidates or ignores projection cache rows with stale
   fingerprints.
4. SQLite migrations are not allowed to reinterpret old projection rows as new
   rows.
5. A cache miss is acceptable; a stale identity hit is not.

The simplest robust version is:

- persist raw upstream facts and source-host metadata;
- rebuild projection rows deterministically through the projection engine;
- persist projection rows only as a same-version performance cache.

## Proof And Testing Architecture

The proof system should compare three facts, all in the same identity plane:

1. Relay projection stream says these `projectionID`s exist in this order.
2. Swift projection table accepted those same `projectionID`s.
3. Simulator accessibility dump shows those same `projectionID`s on screen.

Proof tooling must not compute its own expected display identity. It can decode
and validate a `projectionID` format, but expected IDs must come from relay
projection witnesses or contract fixtures generated by the projection engine.

### Projection Witness Law

Every end-to-end proof run must have a retained projection witness.

Schema path:

```text
contract/projection/projection-witness.schema.json
```

Witness rules:

1. The relay writes or serves the exact projection envelopes it emitted on the
   client path after projection and before transport serialization.
2. The witness is bound to a `proofRunID`, route, `sourceHostID`, view,
   viewParamsKey, epoch, seq range, and timestamp range.
3. The witness contains `rows`, `projectionIDs`, `displayOrderKey`, freshness,
   completeness, and route evidence exactly as the client path saw them.
4. The witness schema rejects unknown identity fields with
   `additionalProperties: false`.
5. Proof scripts may filter or redact non-identity payload fields for safe
   reporting, but they must not recompute `projectionID`, `sourceRef`,
   `displayOrderKey`, view membership, freshness, or expected UI order.
6. Missing witness means proof is blocked or failed. It does not fall back to
   raw Codex reads, SQLite reconstruction, local fixtures, accessibility IDs,
   or imported `projectionIDFor*` helpers.
7. Acceptance proof captures the relay witness for the full `epoch + seqRange`
   before collecting the simulator UI dump.
8. If the UI dump timestamp precedes the witness `seqRange.last`, proof status
   is `blocked`.
9. Proof fails if the witness `viewParamsKey` differs from the view params the
   simulator UI was rendering.
10. Proof commands pass a `proofRunID` to the relay through a non-secret
    request parameter or header. The relay includes that `proofRunID` in every
    witness artifact emitted for that run. A witness without the requested
    `proofRunID` is not valid proof.

### Temporal Convergence Law

Live acceptance proof must prove convergence over time, not a lucky static
sample.

Rules:

1. Proof polls simulator UI dumps until the witness `seqRange.last` is reflected
   in accessibility identifiers or until `maxUiLagMs` elapses.
2. Proof status is `blocked` when the UI dump precedes the witness sequence
   range.
3. Proof status is `failed` when the UI never converges within the configured
   budget.
4. No live scenario passes on a single pre-mutation snapshot.
5. `maxUiLagMs` is part of the proof run config and is recorded in the proof
   artifact.

Required witness artifact fields:

```json
{
  "proofRunID": "uuid",
  "capturedAt": "2026-06-01T00:00:00.000Z",
  "sourceHostID": "amir-m5",
  "projectionContractFingerprint": "sha256:...",
  "routes": [
    {
      "route": "dock/subscribe",
      "view": "dock",
      "viewParamsKey": "sha256:...",
      "epoch": "stream-epoch",
      "seqRange": { "first": 0, "last": 3 },
      "emittedEnvelopes": []
    }
  ]
}
```

Retention rule: proof commands write the witness beside the proof report under
the run artifact directory, for example
`/tmp/codex-client/<run-id>/projection-witness.json`. A checked-in fixture may
also use this schema, but checked-in fixtures are not proof for a live run.

The witness is what prevents proof tooling from becoming a second projection
engine.

### Enforcement Architecture

This architecture should be enforced by contracts and negative tests, not by
trusting future readers to remember the prose.

Required gates:

- Schema validation rejects legacy stream and identity keys.
- Contract generation fails if generated Swift differs from schema.
- Relay tests prove old routes/fields cannot be emitted on production display
  paths.
- Swift tests prove missing projection identity/order/source host/view/version
  fails before render.
- Proof-report validation rejects old proof fields such as `visibleEventIDs`,
  `messageCardIDs`, and `requestCardIDs`.
- Simulator proof fails if it cannot compare UI dump rows to a relay witness.
- Repo checks fail if production code outside the projection package creates
  `projectionID` or `displayOrderKey`.
- Negative tests cover each forbidden compatibility path.

These gates apply to production code, acceptance proof, simulator proof, and
all end-to-end display integration tests. They are architecture tests, not ad
hoc style lint. They exist because this bug class is caused by accidental
second sources of truth.

Required forbidden-pattern gates:

| Pattern | Forbidden in | Allowed only when |
| --- | --- | --- |
| `expectedMessageEventIDs` or fixture-computed expected visible IDs | Acceptance proof outputs and simulator sync proof | Never; expected IDs come from relay-emitted `projectionID`s. |
| `ThreadEventNormalizer` imports | Production app display stores and production display tests | Quarantined legacy diagnostic/test-only target. |
| `thread/read`, `thread/turns/list`, `thread/resume` as UI truth | Production Swift display protocols and simulator proof oracles | Relay-internal adapters, command/session management, or named diagnostics. |
| Arbitrary `AppServerClient.sendRequest(method:)` display reads | Production display stores and display protocols | Low-level transport plumbing behind typed projection or mutation APIs only. |
| Raw Codex display DTO decode | Production Swift display stores, proof oracles, and acceptance fixtures | Relay-internal adapters or quarantined diagnostics/tests that cannot feed production display truth. |
| `UUID()` / `crypto.randomUUID()` for visible rows | App display code, relay projection code, and proof fixtures | Internal subscription/task handles or non-message diagnostics only. |
| `logicalHostID::threadID` | Production Dock/Archive identity and proof truth | Migration fixture that also proves byte-for-byte equality with `projectionID`. |
| Local fallback sorting | Swift display stores | Never for accepted DTOs; missing `displayOrderKey` forces resync. |
| Independent request-card identity store | Thread Detail display state | Transient UI fields rebuilt from projection rows by `projectionID`. |
| Independent Archive Cleanup stream identity | Production Archive Cleanup display and proof truth | Never after projection cutover; use a relay-projected cleanup view or shared projection rows. |
| `hosts`, `upsertHosts`, `deleteHostIDs`, or host identity maps in display streams | Production Dock, Archive, Thread Detail, Host Registry, System Health, proof truth | Connection/bootstrap diagnostics only; host display truth uses `host.registry` projection rows or denormalized payload labels that are not identity. |
| Phone `HostRegistry` config IDs | `sourceHostID`, `sourceRef`, `projectionID`, proof witnesses | Connection/settings UI before relay identity is known. |
| Multiple production `projectionIDFor*` modules | Relay runtime, tests, fixtures, proof | Never; use the single projection engine module. |
| `codex-dock-live-filter-*` without `projectionWitness` | Acceptance proof and simulator sync proof | Quarantined legacy diagnostics only. |

### Required Test Classes

| Class | What it proves |
| --- | --- |
| Projection engine unit tests | Same raw source fact always maps to same `sourceRef`, `projectionID`, row role, and `displayOrderKey`; pending/canonical supersession is explicit. |
| Contract generation tests | JSON schema, generated Swift DTOs, fixtures, and relay output all use the same required fields and reject old fields. |
| Swift projection table tests | Snapshot/upsert/delete/transaction/heartbeat/resync semantics are identical for Dock, Archive, Cleanup, Host Registry, System Health, and Thread Detail. |
| Request payload tests | Request controls keep `projectionID` as UI identity and `requestID` only as routing token. |
| Cache invalidation tests | A projection engine version bump cannot serve old projection rows. |
| Relay end-to-end tests | Raw thread list/history/live/request inputs produce one projection ledger with no duplicates. |
| Simulator live tests | A running simulator receives live updates through the relay path and exposes the same `projectionID`s via accessibility dumps. |
| Reconnect tests | Dropped updates, stale epochs, seq gaps, relay restart, and cache rebuild lead to resync, not duplicated or stale rows. |
| Negative side-door tests | Old fields and raw routes fail contract/proof validation. |

### Required Real-Life Scenarios

The permanent test suite should include these as live update scenarios, not
only static snapshots:

1. Send outbound message while Thread Detail is open.
2. Receive streaming agent response, then settled canonical history.
3. Receive request card, respond on phone, then receive resolved history.
4. Open Dock while relay cache is cold.
5. Open Dock while relay cache is warm after projection version bump.
6. Relay restart while app is open.
7. App background/foreground during active thread updates.
8. Same source host through different endpoint labels.
9. Dock row activity advances while Thread Detail is open.
10. Archive/unarchive while Dock and Archive views are both subscribed.
11. Seq gap and stale epoch.
12. Unknown raw item shape.
13. Pending outbound row supersedes to canonical history through one atomic
    `transaction`.
14. Dock, Archive, Archive Cleanup, Host Registry, System Health, and Thread
    Detail are subscribed together and receive interleaved updates without
    identity, order, freshness, or membership drift.

Each scenario passes only if the final UI dump and relay witness agree by
`projectionID`, order, freshness, route evidence, and source host identity.

## Accessibility And UI Dump Contract

Simulator proof should not depend on screenshots. The app should expose a
canonical accessibility dump surface:

- Dock rows expose `projection=<projectionID>`, `sourceHost=<sourceHostID>`,
  `thread=<threadID>`, `status=<status>`, and freshness state.
- Thread Detail message/request rows expose `projection=<projectionID>`,
  `kind=<rowRole/renderKind>`, `visibility=<visibility>`, request status if
  present, and live/settled state.
- Host/status rows expose `projection=<projectionID>` and source host identity.

The dump command should attach to the currently running simulator app and write
structured JSON. It should not relaunch the app unless explicitly requested.

The proof oracle is the relay projection witness, not screenshots and not a
second projection helper in the proof script.

## Documentation Architecture

After approval and implementation:

1. `README.md` should summarize the projection identity law and link here or to
   the final canonical protocol reference.
2. `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`
   should remove or mark superseded all old `baseSeq`, `stateGeneration`,
   `upsertCards`, `deleteCardIDs`, and `logicalHostID::threadID` sections.
3. Old dated docs should remain history, but each stale one should have a short
   "superseded by projection identity architecture" note near the top if it is
   likely to be copied.
4. Tests and contract files should be treated as more authoritative than prose.

## Implementation Shape

This is a design proposal, not an implementation instruction. If approved, the
elegant implementation should happen as a full pattern cutover, not a pile of
local patches.

### Phase 0: Freeze The Target

- Treat this document as the current proposal and
  `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md` as
  the eventual canonical protocol home.
- Reconcile any disagreement between those docs before implementation.
- During this cutover, this document supersedes older card-v2/raw-detail
  sections in `README.md`,
  `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`,
  and
  `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`.
- Do not accept partial implementation as proof that the architecture is done.
- Do not add new compatibility paths while implementing the cutover.

Completion bar: the team has one written target and no active plan depends on
keeping a second identity owner alive.

### Phase 1: Contract First

- Define the universal projection envelope schema.
- Define the projection witness schema.
- Define the generated row-role schema.
- Define typed payload schemas for Dock, Archive, Thread Detail, Host Registry,
  and System Health.
- Define the viewParamsKey registry fixtures.
- Generate Swift DTOs from those schemas.
- Make old identity fields unrepresentable in production DTOs.
- Add fixture generation from the projection engine.
- Add contract checks proving `contract/dock/dock-thread-card.schema.json` and
  raw Thread Detail DTOs cannot remain a second production display schema.

Completion bar: the generated contract rejects old stream grammar and old
identity fields before Swift render code runs.

### Phase 2: Relay Projection Package

- Promote `scripts/dock-relay-projection-engine.mjs` to the only production
  projection identity package.
- Move Dock/Archive card projection, Thread Detail projection, request rows,
  system rows, and diagnostics onto it.
- Add source alias/supersession rules for pending-to-canonical transitions.
- Implement atomic `transaction`/`operations[]` supersession for v1 streams.
- Increment and persist per-row revisions.
- Ensure projection cache fingerprinting happens before any row is served.
- Keep raw Codex adapters outside this package. They feed facts in; they do not
  own projection IDs or order keys.

Completion bar: every visible relay route emits rows from the same projection
engine and ledger semantics.

### Phase 3: Swift Projection Table

- Replace per-screen stream reducers with one projection table rule set.
- Parameterize by expected view and payload type.
- Reject missing `projectionID`, `displayOrderKey`, source host, view, version,
  or viewParamsKey.
- Store per-row revision and reject stale same-namespace updates.
- Remove production fallback sorting and duplicate suppression.
- Require the source-host handshake and projection contract fingerprint before
  accepting production projection streams.

Completion bar: Swift cannot render a production visible row without a relay
projection envelope.

### Phase 4: Request Controls As Row Payload

- Remove production standalone request-card display paths.
- Make request controls render only from Thread Detail projection row payload.
- Keep `requestID` only as response-routing data.
- Assert `ServerRequestCard.id == projectionID` wherever request controls are
  used.

Completion bar: one request can never produce both a request-card row and a
message/request event row.

### Phase 5: Proof And Simulator Dump

- Make relay witness exports first-class proof artifacts.
- Make simulator UI dumps compare against relay-emitted `projectionID`s.
- Remove proof-side expected-ID generators except projection-engine unit tests.
- Reject raw endpoint proofs and legacy identity keys.
- Make live-filter proof consume projection witnesses or mark it as
  non-acceptance legacy diagnostics.

Completion bar: a real simulator proof catches stale cache, wrong host identity,
  wrong order, missing live update, duplicate rows, and route side doors.

### Phase 6: Delete Legacy Surface

- Rename or remove card-v2-specific DTOs and helpers once payload migration is
  complete.
- Quarantine legacy raw fixtures under explicit test-only names.
- Mark stale docs as superseded.
- Remove compatibility acceptors from production.

Completion bar: repo search for old identity grammar finds only historical docs
  and explicit negative tests.

## Non-Negotiable Acceptance Criteria

The architecture is complete only when all of these are true:

1. No production code outside the relay projection package creates a
   `projectionID` or `displayOrderKey`.
2. No production Swift code renders a row without a projection envelope.
3. No production Swift code sorts visible Codex rows by fallback timestamps,
   titles, request IDs, event IDs, or list indexes.
4. No production path renders a JSON-RPC request as a standalone row.
5. No relay route emits `cards`, `cardIDs`, `upsertCards`, `deleteCardIDs`,
   `baseSeq`, `stateGeneration`, or raw event identity.
6. No cache row can cross a projection contract fingerprint boundary.
7. No proof script computes expected visible IDs independently of the relay
   witness.
8. No simulator proof can pass without comparing visible UI dump rows to relay
   `projectionID`s.
9. No host endpoint alias can change visible source host identity.
10. No compatibility path remains in production "just for tests."
11. No second production schema defines visible display rows outside
    `contract/projection/**`.
12. No request row can be both item-attached and standalone for the same proven
    request/item relationship.
13. No pending row can become canonical without an explicit relay supersession
    operation.
14. No local decoration can create row membership, row identity, freshness, or
    order.
15. No same-namespace lower revision can overwrite a higher revision.
16. No live proof can pass without a
    `contract/projection/projection-witness.schema.json` artifact bound to the
    proof run.
17. No projection stream can be accepted before the client has an authoritative
    `sourceHostID` and projection contract fingerprint from handshake.
18. No view can invent a viewParamsKey outside the registry and stable hash
    rule.
19. No production row role can appear outside the generated row-role schema.
20. No snapshot can replace or retain rows outside its declared
    `sourceHostID + view + scope + viewParamsKey` authority.
21. No pending-to-canonical replacement can be represented as separate
    user-visible delete/upsert events; it must be an atomic projection
    `transaction`.
22. No client-initiated outbound visible row can rely on body text, timestamp,
    array index, or `requestID` for pending identity; it must use
    `clientMutationID` or a relay pending-ledger ID.
23. No durable local decoration can remain keyed by `HostScopedThreadID`,
    configured host ID, endpoint label, or `logicalHostID` after cutover.
24. No production client may use cross-view resync heuristics to update display
    truth; the relay projection ledger must fan out the right operations.
25. No stream may accept sequence gaps, duplicate divergent sequence payloads,
    or buffered row mutations before a valid base snapshot.
26. No live proof may pass without polling for witness-to-UI convergence within
    a recorded `maxUiLagMs` budget.
27. No composer, voice, transcript, or dictation local UI state may create a
    projection row or proof-oracle row.
28. No phone-facing `read`, `load`, `refresh`, `subscribe`, or `resync` route
    may populate visible UI unless it returns the shared projection contract for
    that view.
29. No production display stream may carry `hosts`, `upsertHosts`,
    `deleteHostIDs`, or host identity maps as display truth outside projection
    rows.
30. No windowed stream may use `window.bounds` to reject, trim, or infer
    identity for `upsert`/`delete`; mutations apply by exact `projectionID`
    inside the active stream namespace.
31. No phone-facing display route may bypass the source-host projection ledger
    and build rows directly from raw Codex, cache, requests, or local metadata.

## Why This Is Better Than Narrow Fixes

A narrow fix would dedupe outbound messages, remove one stale fallback, or
special-case request rows. That would treat each symptom as separate.

This architecture removes the shared cause: multiple layers owning visible
identity. Once the relay projection engine is the only identity owner and Swift
only applies projection operations, this class of bugs has nowhere normal to
hide.

Net: the permanent fix is not smarter duplicate detection. The permanent fix is
making duplicate identity ownership impossible.
