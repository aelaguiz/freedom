# Codex Dock Identity Drift Elimination Plan

Date: 2026-06-02

Status: plan only; do not implement from this document until explicitly
approved.

## Related Documents

- `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`
  is the bug doc this plan is cross-linked from. It records the outbound
  duplicate-message symptom and the earlier, broader architecture proposal.
- `docs/CODEX_DOCK_PERMANENT_PROJECTION_IDENTITY_ARCHITECTURE_2026-06-01.md`
  is directionally correct but overbuilt in places. This plan tightens it into
  the smallest permanent architecture that closes the class of identity drift
  bugs.
- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
  is the canonical client live-update, projection-runtime, freshness, and proof
  reference as of 2026-06-02. Its section `0.7 Canonical Client Projection
  Runtime Architecture` supersedes this document wherever client runtime,
  catch-up, freshness, lifecycle, or proof ownership differs.
- `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`
  remains broad protocol history.
- `.arch_skill/model-consensus/codex-dock-identity-architecture-20260602T140852Z/`
  contains the Opus 4.8 Max and GPT-5.5 xhigh consensus run used to produce
  this plan.
- `.arch_skill/model-consensus/codex-dock-client-robustness-20260602T201428Z/`
  contains the follow-on Opus 4.8 Max and GPT-5.5 xhigh consensus run that
  broadened identity into the canonical client projection-runtime plan.

## Bottom Line

The most elegant fix is not a Swift dedupe patch and not a broad rebuild. The
right architecture is to finish the relay-owned projection cutover that already
exists, make it the only identity path, and close every remaining side door
where the client, cache, proof, or tests can invent visible row identity.

The permanent rule is:

```text
If a visible row exists, its identity, order, and freshness came from the relay
projection engine, or the row is invalid.
```

That rule kills the duplicate-message class by removing the second identity
owner. It also protects Dock, Archive, Thread Detail, request controls,
reconnect, cache reads, simulator proof, and live proof from drifting apart.

## Model Consensus Result

Model consensus converged on a finish-the-cutover plan.

Both models agreed on these points:

1. `scripts/dock-relay-projection-engine.mjs` must be the only production owner
   of `sourceRef`, `projectionID`, `displayOrderKey`, `rowRole`, and freshness.
2. Swift should render and validate projection rows. It must not merge,
   identify, sort, or dedupe visible rows by body text, request ID, timestamp,
   thread ID, endpoint label, or local fixture ID.
3. Live Thread Detail and canonical history must produce the same
   `projectionID` for the same upstream item.
4. Proof must compare simulator-visible IDs to retained relay projection
   witnesses from the same run. It must not reconstruct expected IDs from raw
   Codex reads or local helper functions.
5. The remaining work is a strict cutover plus side-door removal, not a new
   optimistic/pending-message subsystem.

The meaningful consensus correction to the earlier architecture doc is:

```text
"One Swift projection table" means one shared apply law.
It does not require a giant generic rewrite if the same law can be enforced
cleanly through a shared core used by the existing engines.
```

## Intended User Experience

The user experience target is simple:

1. The Dock shows the newest relevant work first.
2. Opening a thread shows the latest visible thread rows first.
3. Sending a message never creates duplicate visible rows.
4. Live updates, canonical history, reconnects, cache reads, and proof tooling
   all converge to the same visible rows.
5. If identity or freshness cannot be proven, the app shows an explicit stale,
   offline, error, or diagnostic state. It never silently guesses.

The user should not need to understand Codex upstream notifications, relay
caches, request IDs, host aliases, or simulator proof internals to trust the
phone.

## Final Architecture Shape

The final architecture is:

```text
raw Codex adapters
  -> relay projection engine
  -> projection cache/store keyed by sourceHostID + view + viewParamsKey + contractFingerprint
  -> projection streams: thread-card, thread-detail
  -> Swift projection appliers
  -> render-only SwiftUI
  -> retained relay witness proof
```

There are only two display projection families:

1. `thread-card`: Dock and Archive rows.
   The row identity is `host:<sourceHostID>/thread:<threadID>/row:threadCard`.
   Dock and Archive are view memberships over that row family.
2. `thread-detail`: opened-thread rows.
   The row identity is
   `host:<sourceHostID>/thread:<threadID>/turn:<turnID>/item:<itemID>/row:<role>`.
   Request controls are payload on the projected row. `requestID` is response
   routing only, never visible row identity.

`archive.cleanup`, `system.health`, and `host.registry` are not display
projection families for this plan. Current evidence shows they are local
filters, local status projections, or configuration. Turning them into streamed
projection views would add machinery without closing this identity bug class.

## Non-Negotiable Laws

### 1. One Identity Owner

Only `scripts/dock-relay-projection-engine.mjs` may construct production
visible identity and order:

- `sourceRef`
- `projectionID`
- `displayOrderKey`
- `rowRole`
- projection freshness

Everything after that layer can carry, store, validate, render, or compare
those values. Nothing after that layer can derive them.

Done means the repo has a gate that fails if production app code, proof code,
or fixtures build `host:.../row:...` IDs outside the projection engine package,
except in explicitly quarantined negative tests.

### 2. One Stream Grammar

Projection streams use only:

- `snapshot`
- `upsert`
- `delete`
- `heartbeat`
- `resyncRequired`

The stream is keyed by `epoch + seq` within:

```text
sourceHostID + view + scope + viewParamsKey
```

There is no production display `delta`, `card-v2`, `baseSeq`, `upsertCards`,
`deleteCardIDs`, or `transaction` grammar.

### 3. One Client Apply Law

Swift applies every visible projection stream with the same rule:

1. Reject rows missing `sourceHostID`, `projectionID`, `sourceRef`,
   `displayOrderKey`, or `revision`.
2. Key rows by `projectionID`.
3. Sort rows by opaque relay `displayOrderKey`.
4. Apply same-row content changes by monotonic row `revision`.
5. Reject sequence gaps, mismatched `epoch`, mismatched `sourceHostID`,
   mismatched `viewParamsKey`, and duplicate rows.
6. Never merge by body text, request ID, turn/item fallback, date, timestamp,
   thread ID, endpoint label, local fixture ID, or accessibility ID.
7. Never optimistic-insert a visible row that the relay has not projected.

This law can be implemented as one generic table, one shared apply-rule core,
or another small local abstraction. The architecture requires one law, not a
large rewrite for its own sake.

### 4. Live Equals Canonical

Live Thread Detail events and canonical history must hit the same relay
projection function and therefore produce the same `projectionID`.

If the relay receives a live event without enough canonical identity, it emits
an explicit diagnostic row or requires resync. It never lets the client guess a
pending row and later dedupe it.

### 5. Host Identity Comes From The Relay Handshake

`initialize` must return the authoritative `sourceHostID` and projection
contract fingerprint. `relayInstanceID` is diagnostics only.

The client must capture that handshake and reject or invalidate streams whose
`sourceHostID` or contract fingerprint does not match it.

Endpoint labels, Bonjour names, Tailscale names, LAN addresses, and display
names are action-routing or UI labels. They are not durable visible row
identity.

### 6. One Cache Contract

The projection cache is valid only under:

```text
contractFingerprint + sourceHostID + view + viewParamsKey
```

When that fingerprint changes, old materialized projection rows are wiped or
made unreachable before they can be served as fresh. The cache may store rows,
but it may not derive identity.

### 7. Proof Uses Retained Relay Witnesses

Acceptance proof compares the simulator UI dump against retained relay
projection witnesses from the same proof run.

The proof path must not:

- read raw Codex as the expected UI oracle
- import local projection ID helpers as the expected UI oracle
- accept legacy proof keys by deny-list only
- allow arbitrary identity-shaped fields in witness rows

## Side Doors To Close

### 1. `initialize` Does Not Carry The Projection Identity Contract

Current evidence:

- `scripts/dock-relay.mjs` returns `relayInstanceID` on `initialize`.
- `CodexDock/AppServer/AppServerMethods.swift` decodes `relayInstanceID`.
- The client does not receive authoritative `sourceHostID` plus projection
  contract fingerprint at handshake.

Fix:

- Add `sourceHostID` and `contractFingerprint` to `initialize`.
- Keep `relayInstanceID` only as diagnostics.
- Store the handshake in the host connector/session state.
- Reject or invalidate projection streams whose `sourceHostID` or fingerprint
  does not match the handshake.

Done means the same Mac reached through two endpoint labels cannot create two
display identity namespaces.

### 2. `logicalHostID` Keeps A Second Host Namespace Alive

Current evidence:

- `DockHostIdentityResolver` can fall back to configured host IDs.
- Some DTOs and local paths still carry `logicalHostID` style transition
  vocabulary.

Fix:

- Make `sourceHostID` the only durable namespace.
- Delete `logicalHostID` outright where practical.
- If a live migration risk is proven, allow one transition window where
  `logicalHostID` is a validated alias that must equal `sourceHostID`, then
  delete it.
- Demote `DockHostIdentityResolver` to action-routing, label, or migration
  helper only. It cannot define display identity.

Done means visible row identity never depends on endpoint configuration.

### 3. Dock And Archive Lack Row-Level `revision`

Current evidence:

- Thread Detail has per-row `revision`.
- Dock/Archive card streams and Swift card apply paths do not carry equivalent
  row-level revision.

Fix:

- Add `revision` to projected thread-card rows.
- Require it in the thread-card schema.
- Apply it in Swift with the same monotonic same-row update law as Thread
  Detail.

Done means Dock/Archive and Thread Detail share the same update semantics.

### 4. `viewParamsKey` Has More Than One Grammar

Current evidence:

- Thread Detail uses a canonical `sha256:` style key.
- Dock/Archive use plain strings such as `dock:<host>`.

Fix:

- Canonicalize every `viewParamsKey` through the projection engine.
- Use the same hash grammar for all views.

Done means view identity cannot drift when parameters grow beyond simple host
labels.

### 5. Projection Envelope Schemas Must Be Closed

Current evidence:

- Some projection envelope schema paths are closed.
- The model-consensus review still found schema-side risk around permissive
  envelope or witness objects and older docs treating this as incomplete.

Fix:

- Ensure every projection envelope schema has `additionalProperties: false` at
  every identity-bearing object boundary.
- Allow open payload bags only where the payload schema explicitly owns that
  openness.

Done means new identity-shaped fields cannot silently pass schema validation.

### 6. Projection Witness Schemas Must Be Closed

Current evidence:

- The witness path is the correct proof oracle.
- Witness schemas still allow arbitrary fields in places that can carry
  identity-like data.

Fix:

- Close witness envelopes and witness rows by allow-list.
- Permit opacity only inside payload areas that are not identity or order.

Done means the proof oracle cannot smuggle a second identity vocabulary.

### 7. Proof Reports Must Use Allow-Lists, Not Deny-Lists

Current evidence:

- Proof reports reject some legacy keys through deny-lists such as forbidden
  key names.
- A newly invented drift field could pass until code notices it.

Fix:

- Convert proof report schemas to closed allow-list objects.
- Keep deny-lists only as extra diagnostics, not the primary guard.
- Make route labels distinguish phone-facing relay routes from relay-internal
  raw upstream routes.

Done means acceptance proof cannot pass through a new side-door field name.

### 8. Tests And Fixtures Still Mint Projection IDs Locally

Current evidence:

- Some Swift test support and request-card tests build `projectionID` strings
  directly.
- Some legacy fixture normalizers preserve old event identity construction.

Fix:

- Generate test projection IDs through the same projection engine package or
  through engine-generated fixtures.
- Add a repo gate that fails on direct `host:.../row:...` ID construction
  outside the engine package and explicit negative-test fixtures.

Done means tests cannot assert a shape that production no longer emits.

## Explicitly Rejected Work

These are not part of the permanent fix unless the product requirements change.

1. Pending-row tables, `clientMutationID`, atomic `transaction` operations, and
   pending-to-canonical supersession machinery.

   Reason: the current product does not optimistic-insert visible rows, and
   live Thread Detail already has canonical turn/item identity. Building a
   pending subsystem would add a second identity lifecycle to solve a problem
   this product does not currently have.

2. New streamed projection views for `archive.cleanup`, `system.health`, and
   `host.registry`.

   Reason: these are not current display identity drift sources. Archive
   cleanup is a local view over Dock/Archive rows. System health is local
   status projection. Host registry is configuration; host identity is solved
   by the `initialize` handshake.

3. A universal `projection_rows` SQLite rewrite as a prerequisite.

   Reason: the current cache can be valid if it stores relay-projected identity
   under the contract fingerprint. A universal store may be a cleanup, but it
   is not required to kill this bug class.

4. Mandating a new generic `ProjectionTable<RowPayload>` or `ProjectionDTO.swift`
   shape.

   Reason: the required architecture is one apply law. A generic table may be
   the cleanest implementation, but the plan should not smuggle in a rewrite if
   a small shared core enforces the same law better.

5. Wholesale renaming of every "card" symbol.

   Reason: names matter only where they preserve a second contract or mental
   model. The load-bearing fix is making old identity fields unrepresentable,
   not renaming working local symbols for vocabulary alone.

6. Swift-side dedupe by body text, request ID, timestamp, turn/item fallback,
   latest date, or thread ID.

   Reason: that treats one duplicate symptom after identity drift has already
   happened. The permanent fix prevents drift at the identity boundary.

## Implementation Plan

### Phase 1: Contract And Handshake Authority

1. Add `sourceHostID` and `contractFingerprint` to the relay `initialize`
   result.
2. Add matching Swift decode fields.
3. Store handshake identity in the active host connection.
4. Make projection stream handlers validate `sourceHostID` and fingerprint
   against the handshake.
5. Keep `relayInstanceID` as diagnostics only.

Verification:

- Unit tests prove two endpoint labels for the same relay use one
  `sourceHostID`.
- Stream tests prove mismatched `sourceHostID` or fingerprint fails closed.

### Phase 2: Uniform Projection Apply Law

1. Add row `revision` to thread-card projection payloads.
2. Require `revision` in the thread-card schema.
3. Apply row `revision` in `ThreadCardTable` or a shared projection apply core.
4. Canonicalize `viewParamsKey` for Dock and Archive through the projection
   engine.
5. Consolidate the stream validation rules used by `ThreadCardTable` and
   Thread Detail so they cannot drift.

Verification:

- Tests cover stale card revisions, duplicate card rows, wrong
  `viewParamsKey`, wrong `sourceHostID`, sequence gaps, and resync.
- Thread Detail and thread-card tests assert the same law with different
  payloads.

### Phase 3: Remove Host Namespace Side Doors

1. Delete `logicalHostID` where possible.
2. If migration risk is proven, retain it only as a temporary alias that must
   equal `sourceHostID`.
3. Demote `DockHostIdentityResolver` to routing/label/migration helper.
4. Ensure local metadata keys are expressed in `sourceHostID` terms.

Verification:

- Same source host through Tailscale, Bonjour, LAN, or display name does not
  split pins, Dock rows, Archive rows, or Thread Detail rows.

### Phase 4: Strict Witness And Proof Contracts

1. Close all projection envelope identity objects.
2. Close witness envelope and row identity objects.
3. Convert proof report schemas from deny-list protection to allow-list
   protection.
4. Keep deny-list checks only as extra diagnostics.
5. Remove fixture-built expected projection IDs from acceptance proof.

Verification:

- Contract tests reject unknown identity fields.
- Proof report tests reject newly invented legacy-style fields, not only known
  bad field names.
- Simulator proof compares UI IDs to retained relay witnesses from the same
  run.

### Phase 5: Test Fixture Quarantine

1. Replace local projection-ID builders in Swift test support with
   engine-generated fixtures or imported engine helpers.
2. Add a repo gate for direct `host:.../row:...` construction outside the
   projection engine package and explicit negative-test fixtures.
3. Mark old fixture normalizers as legacy-only or delete them once tests move.

Verification:

- Test code cannot invent the same visible row identity production owns.
- Negative tests remain allowed only when they intentionally assert rejection.

## Required Test Methodology

The test methodology must exercise time, not just static snapshots.

At minimum, implementation is not done until these pass:

1. Relay engine determinism:
   the same raw Codex fact from history, live notification, reconnect, and
   resync produces the same `sourceRef`, `projectionID`, and `displayOrderKey`.
2. Thread Detail outbound convergence:
   send a message, receive live row data, resync canonical history, and assert
   one visible user row by `projectionID`.
3. Dock/Archive convergence:
   live card updates, canonical refresh, archive membership changes, and cache
   reads converge to one thread-card row identity.
4. Host identity convergence:
   the same relay reached by multiple endpoint labels produces one
   `sourceHostID` namespace and one visible row set.
5. Cache invalidation:
   changed contract fingerprint makes stale materialized rows unreachable
   before they can render as fresh.
6. Proof equality:
   simulator accessibility dump equals retained relay projection witnesses
   from the same proof run.
7. Negative contract tests:
   unknown identity fields, legacy proof fields, mismatched source hosts,
   mismatched fingerprints, stale revisions, sequence gaps, and fixture-built
   expected IDs fail.

## Acceptance Definition

This plan is complete when all of the following are true:

1. Production visible row identity is constructed only in the relay projection
   engine package.
2. The `initialize` handshake gives the client authoritative `sourceHostID` and
   projection contract fingerprint.
3. Dock, Archive, and Thread Detail all apply `snapshot`, `upsert`, `delete`,
   `heartbeat`, and `resyncRequired` under the same identity, order, revision,
   host, view, and sequence law.
4. `requestID`, endpoint IDs, local host IDs, accessibility IDs, raw event IDs,
   timestamps, body text, and fixture IDs cannot become visible row identity.
5. Cache validity is tied to the projection contract fingerprint and
   `sourceHostID`.
6. Acceptance proof uses retained relay witnesses as the only expected UI
   oracle.
7. Schema and repo gates prevent new side doors, including test-only side
   doors.
8. The duplicate outbound-message scenario, live-before-canonical scenario,
   canonical-before-live scenario, reconnect scenario, stale-cache scenario,
   two-host scenario, and Dock/Archive membership scenario all pass through the
   real simulator path.

Net: once this is implemented correctly, identity drift stops being a recurring
bug class because the system has only one place where visible identity can be
made.
