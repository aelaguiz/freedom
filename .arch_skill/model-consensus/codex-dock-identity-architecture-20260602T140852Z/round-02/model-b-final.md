Yes, I converge with Model A. The elegant fix is not a bigger projection framework. It is to make the already-built relay projection path permanent, close the remaining side doors, and reject speculative machinery.

**1. Where I Agree**
- One owner for visible identity: `scripts/dock-relay-projection-engine.mjs` owns `sourceRef`, `projectionID`, and `displayOrderKey` ([line 96](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-projection-engine.mjs:96), [line 153](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-projection-engine.mjs:153)).
- Live Thread Detail already uses canonical `turnId + itemId`, then emits the same projection ID as history ([adapter line 450](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-detail-projection-adapter.mjs:450), [line 721](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-detail-projection-adapter.mjs:721)).
- Swift already avoids optimistic visible rows during send ([ThreadDetailStore.swift:388](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadDetailStore.swift:388)).
- Swift apply logic is mostly right: Thread Detail applies by projection stream ops and revision checks ([ThreadDetailDataEngine.swift:41](/Users/aelaguiz/workspace/codex-client/CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:41), [line 284](/Users/aelaguiz/workspace/codex-client/CodexDock/ThreadDetail/ThreadDetailDataEngine.swift:284)); Dock cards require `id == projectionID` ([ThreadCardTable.swift:276](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardTable.swift:276)).
- Model A is right to reject pending rows, `clientMutationID`, `transaction`, and extra streamed health/archive-cleanup/host-registry views.

**2. Where I Still Object**
- I would not say proof/cache are fully done. The runtime direction is right, but projection witness schemas still allow arbitrary fields ([projection-witness.schema.json:151](/Users/aelaguiz/workspace/codex-client/contract/projection/projection-witness.schema.json:151)), and proof reports still rely partly on forbidden-key deny-lists ([proof-report-contracts.mjs:36](/Users/aelaguiz/workspace/codex-client/scripts/proof-report-contracts.mjs:36)).
- I would not call it “three real view families.” Final projection display families should be two: `thread-card` and `thread-detail`. Archive cleanup, system health, and host registry are local/config-derived today ([ArchiveCleanupDataEngine.swift:10](/Users/aelaguiz/workspace/codex-client/CodexDock/Archive/ArchiveCleanupDataEngine.swift:10), [SystemHealthProjector.swift:6](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Status/SystemHealthProjector.swift:6), [HostRegistry.swift:3](/Users/aelaguiz/workspace/codex-client/CodexDock/Configuration/HostRegistry.swift:3)).
- I agree to collapse version complexity conceptually, but I’d write the plan as “one projection contract fingerprint plus row `revision`.” Existing `schemaVersion`, `identityVersion`, and `projectionEngineVersion` can be transitional inputs, not separate policy levers.

**3. Exact Final Architecture Shape**
```text
raw Codex adapters
-> relay projection engine
-> projection cache/store keyed by sourceHostID + view + viewParamsKey + contractFingerprint
-> projection streams: thread-card, thread-detail
-> Swift projection appliers
-> render-only SwiftUI
-> retained relay witness proof
```

Rules:
- `sourceHostID` comes from the relay handshake, not endpoint labels.
- `projectionID` is visible row identity.
- `displayOrderKey` is visible order.
- `revision` is same-row content change.
- `requestID` is response routing only, never row identity.
- Proof compares UI accessibility IDs to relay-retained witnesses from the same run.

**4. Side Doors To Close**
1. Close projection envelope schemas with `additionalProperties: false` ([projection-envelope.schema.json:1](/Users/aelaguiz/workspace/codex-client/contract/projection/projection-envelope.schema.json:1)).
2. Close witness/proof schemas by allow-list, not deny-list.
3. Add handshake authority: `initialize` must return `sourceHostID` and contract fingerprint; today Swift and relay expose only `relayInstanceID` ([AppServerMethods.swift:81](/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/AppServerMethods.swift:81), [dock-relay.mjs:740](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:740)).
4. Demote `logicalHostID` and `DockHostIdentityResolver` to migration/action-label help only; today it falls back to configured host id ([DockHostIdentityResolver.swift:84](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockHostIdentityResolver.swift:84)).
5. Remove local projection-ID builders from acceptance truth and fixtures; tests still mint IDs directly ([ThreadDetailStoreTestSupport.swift:563](/Users/aelaguiz/workspace/codex-client/CodexDockTests/ThreadDetailStoreTestSupport.swift:563)).

**5. Work I Explicitly Reject As Overbuild**
- Pending-row tables, `clientMutationID`, atomic `transaction`, and supersession machinery.
- New streamed projection views for `archive.cleanup`, `system.health`, and `host.registry`.
- Three independent version levers as architecture. Use one contract fingerprint plus row `revision`.
- A universal ledger/store rewrite as a prerequisite.
- Proof from raw Codex reads, fixture-computed expected IDs, or local `projectionIDFor*` helpers.

**6. Signoff**
Yes. I sign off that this is the most elegant permanent architecture for this bug class: keep one relay-owned projection identity plane, close the five side doors, and do not build machinery for a pending/optimistic path the product does not currently have.

No files edited. No tests run, per read-only round-2 instructions.