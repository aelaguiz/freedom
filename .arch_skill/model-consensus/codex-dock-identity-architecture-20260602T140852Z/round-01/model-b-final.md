✅ Model B view: the existing projection-identity architecture is basically the right permanent fix. I would not replace it; I would tighten it into a stricter cutover plan and close the remaining side doors.

**Proposed Architecture**
One relay-owned projection plane:

```text
raw Codex adapters
-> relay projection engine
-> versioned projection ledger/store
-> retained projection witnesses
-> one Swift ProjectionTable
-> render-only screens
```

The key rule: after the relay projection engine emits `projectionID`, `sourceRef`, `displayOrderKey`, `revision`, `sourceHostID`, and view membership, no Swift screen, cache, test fixture, proof script, or DTO helper gets to answer “what row is this?” again.

**Evidence Read**
- Bug doc: [CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md:1)
- Existing proposal: [CODEX_DOCK_PERMANENT_PROJECTION_IDENTITY_ARCHITECTURE_2026-06-01.md](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_PERMANENT_PROJECTION_IDENTITY_ARCHITECTURE_2026-06-01.md:28)
- Relay identity owner: [dock-relay-projection-engine.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-projection-engine.mjs:1)
- Thread Detail relay ledger: [dock-relay-thread-detail-ledger.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-detail-ledger.mjs:1)
- Swift Thread Detail apply law: [ThreadDetailDataEngine.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:23)
- Dock/Archive transition table: [ThreadCardTable.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardTable.swift:1)
- Request-card projection path: [ServerRequestCard.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Models/ServerRequestCard.swift:179)
- Projection contracts/proof gates: [contract/projection](/Users/aelaguiz/workspace/codex-client/contract/projection), [proof-report-contracts.mjs](/Users/aelaguiz/workspace/codex-client/scripts/proof-report-contracts.mjs:1)

**Owner Paths**
Adopt:
- `contract/projection/**` as the schema source.
- `scripts/dock-relay-projection-engine.mjs` as the only production ID/order helper.
- `scripts/dock-relay-thread-detail-ledger.mjs` pattern as the first real ledger model.
- A future `CodexDock/AppServer/ProjectionDTO.swift` plus `ProjectionTable` as the Swift owner. The proposal names this file, but it does not exist yet.

Retire or quarantine:
- `DockThreadCardDTO`, `ThreadCardTable`, `cardsByID`, `cardsByHostID`, SQLite `threads`, and `logicalHostID` as final identity concepts.
- Raw Thread Detail DTO/test oracles outside explicit legacy tests.
- Acceptance proof that imports `projectionIDFor*` instead of reading relay witnesses.

**Side Doors To Close**
- `initialize` still returns only `relayInstanceID`, not full `sourceHostID` plus projection version/fingerprint handshake.
- Dock/Archive lack row-level `revision`.
- `viewParamsKey` is not yet canonical `sha256:` everywhere.
- Proof witnesses allow extra nested fields.
- Some proof/fixture labels still blur phone-facing routes with relay-internal raw upstream routes.
- `ServerRequestCardTests` locally invent request projection IDs; production request identity should be witness/projection driven.

**Rejected Alternatives**
- Swift dedupe by body text, request ID, timestamp, or turn/item fallback: rejects the symptom, not the cause.
- Thread Detail-only fix: leaves Dock, Archive, request cards, cache, proof, and host identity with second identity paths.
- Keeping card-v2 as a “compatible” parallel contract: that preserves the old mental model.
- Proof from raw Codex reads or fixture-built IDs: that creates a second oracle.

**Tests / Proof**
The acceptance proof should compare simulator accessibility IDs to retained relay projection witnesses from the same `proofRunID`. It must cover live-before-canonical, canonical-before-live, reconnect/resync, request resolution, stale cache invalidation, two-host identity, Dock/Archive move, and UI duplicate checks by `projectionID`.

**Convergence**
Yes, I’m ready to converge. Net: keep the existing architecture, but make the plan stricter: one projection engine, one projection contract, one Swift projection table, one cache contract, and one witness-based proof source. I did not write the on-disk plan because this pass explicitly said `Do not edit files`.