---
title: "Thread detail rejects DockThreadCard rows whose logical host id differs from the saved endpoint id"
date: 2026-05-30
status: implemented
owners: [Amir, Codex]
reviewers: []
related:
  - docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md
  - CodexDock/State/ThreadDetailStore.swift
  - CodexDock/State/ThreadCardRowProjector.swift
  - CodexDock/State/DockStore.swift
  - CodexDock/State/DockCardProjection.swift
  - CodexDock/State/ThreadCardTable.swift
  - CodexDock/State/ThreadCardHostSnapshotLoader.swift
  - CodexDock/Dock/DockRenderModels.swift
  - CodexDock/Dock/DockRenderProjector.swift
  - CodexDock/Features/Dock/DockFilterSurfaceView.swift
  - CodexDock/State/ScriptedDockStreamClient.swift
  - CodexDock/Features/Dock/DockViewPreview.swift
  - CodexDock/State/ArchiveStore.swift
  - CodexDock/Archive/ArchiveDataEngine.swift
  - CodexDock/Features/Archive/ArchiveView.swift
  - CodexDock/State/ArchiveCleanupStore.swift
  - CodexDock/Archive/ArchiveCleanupDataEngine.swift
  - CodexDock/Features/Archive/ArchiveCleanupView.swift
  - CodexDock/State/LocalThreadMetadataStore.swift
  - CodexDock/Metadata/LocalMetadataEngine.swift
  - scripts/dock-relay-state-views.mjs
  - scripts/dock-relay-state-store.mjs
  - scripts/generate-dock-thread-card-contract.mjs
  - scripts/check-dock-thread-card-contract.mjs
  - contract/dock/dock-thread-card.schema.json
  - package.json
---

<!-- bugs:block:tldr:start -->

## TL;DR

- Symptom: opening a Dock row can show `This row belongs to host Amir-M5, not amir-m5.fairy-salmon.ts.net...`.
- Impact: Dock rows load from the relay, but thread detail, Dock host filters, archive restore, archive cleanup, and local metadata can treat the same host as two different hosts.
- Root cause: `DockRowViewModel.id.hostID` now comes from `DockThreadCardDTO.logicalHostID` (`Amir-M5`), while `DockHostConfiguration.id` still comes from the saved endpoint (`amir-m5.fairy-salmon.ts.net:4510`). Several call sites still compare those strings directly.
- Fix: one shared `DockHostIdentityResolver` now bridges logical row ids to configured endpoint hosts across Dock, thread detail, Archive, Archive Cleanup, local metadata migration, and relay card identity.
- Status: implemented and locally verified. Relay services need restart after this commit is deployed because `scripts/dock-relay*.mjs` and host-service launch args changed.

<!-- bugs:block:tldr:end -->

<!-- bugs:block:analysis:start -->

## Bug North Star

Opening a Dock row should use the relay endpoint selected from saved app config while preserving the row's stable `logicalHostID` identity. Endpoint text is transport configuration; `logicalHostID` is row identity.

## Bug Summary

The DockThreadCard contract intentionally split two concepts:

- Saved phone/app config remains a host+port endpoint list.
- Relay cards use `logicalHostID` as stable product identity.

The app partially honors that split. Dock row creation uses `logicalHostID`, and Dock row opening uses an alias lookup to find the configured endpoint. But thread detail then re-checks `row.id.hostID == host.id` using exact string equality. That check is still endpoint-era logic, so it rejects a valid logical-host row when the configured host id is endpoint-derived.

Parallel read-only audits found this is not a one-file bug. The same namespace drift exists wherever a row key, filter key, metadata key, archive key, or cleanup key is compared directly to an endpoint-backed configured host id.

## Evidence

User-reported symptom:

```text
This row belongs to host Amir-M5, not amir-m5.fairy-salmon.ts.net
```

Live relay evidence from `ws://amir-m5.fairy-salmon.ts.net:4510`, gathered with `dock/subscribe`:

```json
{
  "schemaVersion": 2,
  "view": "dock",
  "hosts": [
    {
      "id": "Amir-M5",
      "logicalHostID": "Amir-M5",
      "displayName": "Amir-M5",
      "endpoint": null
    }
  ],
  "firstCard": {
    "id": "Amir-M5::019e7b86-303b-75e2-9287-26d51b44085a",
    "logicalHostID": "Amir-M5",
    "hostDisplayName": "Amir-M5",
    "hostEndpoint": null,
    "threadID": "019e7b86-303b-75e2-9287-26d51b44085a"
  }
}
```

Live relay evidence from `ws://home.fairy-salmon.ts.net:4510`, gathered with `dock/subscribe`:

```json
{
  "schemaVersion": 2,
  "view": "dock",
  "hosts": [
    {
      "id": "home",
      "logicalHostID": "home",
      "displayName": "Home",
      "endpoint": null
    }
  ],
  "firstCard": {
    "id": "home::019e7b59-c0c2-7bc0-8df9-5af3a480e320",
    "logicalHostID": "home",
    "hostDisplayName": "Home",
    "hostEndpoint": null,
    "threadID": "019e7b59-c0c2-7bc0-8df9-5af3a480e320"
  }
}
```

Contract evidence:

- `docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md` says `logicalHostID` is stable product host identity.
- The same doc says saved app configs remain host/port endpoint lists.
- Decision 6 explicitly says cards use `logicalHostID`, while saved app configs remain endpoint lists.

Code anchors:

- `CodexDock/State/ThreadCardRowProjector.swift:26-28` builds `DockRowViewModel.id` from `card.logicalHostID`.
- `CodexDock/State/DockStore.swift:31-35` can resolve a row host id by endpoint id, display name, or display endpoint.
- `CodexDock/Features/Dock/DockView.swift:585-590` opens detail by passing that resolved `DockHostConfiguration` plus the selected row.
- `CodexDock/Configuration/DockHostConfiguration.swift:165-169` defines `DockHostConfiguration.id` as the serialized endpoint id.
- `CodexDock/State/ThreadDetailStore.swift:216-224` rejects the detail load unless `row.id.hostID == host.id`.

## Investigation

Current failure chain:

1. App config contains endpoint-style host entries such as `amir-m5.fairy-salmon.ts.net:4510`.
2. `DockHostConfiguration.id` is endpoint-derived, because it returns `endpoint.id`.
3. Relay `dock/subscribe` returns cards whose `logicalHostID` is `Amir-M5`.
4. `ThreadCardRowProjector.makeRow(card:)` sets `row.id.hostID` to `card.logicalHostID`, so the row belongs to `Amir-M5`.
5. `DockStore.hostConfiguration(for:)` resolves `Amir-M5` by matching `host.displayName`, so the row can be tapped.
6. `DockView.selectedDetailDestination` passes the resolved endpoint-backed `DockHostConfiguration` into `ThreadDetailStore`.
7. `ThreadDetailStore.load()` compares exact ids: `row.id.hostID == host.id`.
8. The exact comparison fails because `Amir-M5 != amir-m5.fairy-salmon.ts.net:4510`, so detail renders the reported error before calling `thread/read` or `thread/resume`.

Ranked hypotheses:

1. Confirmed: thread detail still assumes row host id and configured host id are the same namespace. This is the direct root cause.
2. Supporting issue: tests use fixtures where `logicalHostID == host.id`, so they miss the endpoint-vs-logical-host split.
3. Unlikely: relay is emitting the wrong identity. The live payload matches the contract: cards use `logicalHostID`, and endpoint config stays separate.
4. Unlikely: local/home relay is down. Both relays reported healthy before this investigation, and `dock/subscribe` returned valid schema v2 card payloads.

## Parallel Agent Audit Summary

Four read-only audit lenses were run before writing this plan:

- Swift UI/navigation/action boundaries.
- Local metadata, pinned rows, filters, archive, and cleanup selections.
- Relay/contract/schema identity boundaries.
- Test and fixture coverage gaps.

Combined result:

- The immediate thread-detail failure is confirmed.
- The same identity-drift class is confirmed in Dock host filters, Dock host lens grouping, archive filtering, archive restore, archive cleanup review filtering, archive cleanup execution, archive cleanup confirmation copy, and local metadata/pinned-row revival.
- Relay happy path is mostly using `CODEX_DOCK_REAL_HOST_ID` as logical host identity, so the normal `rtk make services` path is not intentionally emitting endpoint-derived card ids.
- Relay host/card endpoint metadata is weak: live payloads can emit `endpoint: null` and `hostEndpoint: null`, and Swift currently ignores stream host metadata as an alias map.
- Tests mostly hide the bug by setting `logicalHostID == host.id`.

## Affected Location Checklist

The implementation touched or explicitly retired every affected location below. A patch that changes only `ThreadDetailStore` would be incomplete.

- [x] `CodexDock/State/ThreadDetailStore.swift:216-224`
  - Direct failure: `row.id.hostID == host.id` compares logical host id to endpoint id and shows the reported error before `thread/read` or `thread/resume`.
  - Required change: replace with a centralized row-to-configured-host resolution check.

- [x] `CodexDock/State/DockStore.swift:31-35`
  - Current alias lookup lives only in `DockStore.hostConfiguration(for:)`.
  - Required change: replace this local helper with the shared resolver, or make it a thin wrapper around the shared resolver.

- [x] `CodexDock/State/ThreadCardRowProjector.swift:12-14`, `:171-200`
  - Duplicate alias logic exists for cached pinned rows, display names, and endpoints.
  - Required change: remove local ad hoc alias matching and use the shared resolver/alias index.

- [x] `CodexDock/State/DockCardProjection.swift:99-122`, `:276-285`
  - Host lens groups rows by `row.id.hostID` but looks them up by endpoint-backed `host.id`.
  - Host filters store endpoint-backed selected host ids and compare them directly to row logical host ids.
  - Required change: host grouping and filter membership must use resolver identity matching, not raw string equality.

- [x] `CodexDock/Features/Dock/DockFilterSurfaceView.swift:47-58`
  - Filter chips store `host.id`, which is endpoint-backed.
  - Required change: keep endpoint-backed chip state for compatibility, but evaluate all selected-host membership through the resolver.

- [x] `CodexDock/Features/Dock/DockView.swift:585-590`, `:905`
  - Detail opening already uses an alias lookup, but that lookup is local to `DockStore`.
  - `hostState(for:)` still searches host state by raw endpoint id.
  - Required change: detail destination and host-state lookup must use the same shared resolver contract.

- [x] `CodexDock/State/ArchiveStore.swift:176-182`
  - Restore uses `hosts.first { $0.id == row.id.hostID }`.
  - Required change: restore must resolve the row logical host id to exactly one configured endpoint host.

- [x] `CodexDock/Features/Archive/ArchiveView.swift:330-335`, `:440-446`
  - Archive host chips store endpoint-backed `host.id`, then filter rows by exact row logical id equality.
  - Required change: archive filters must use resolver membership.

- [x] `CodexDock/State/ArchiveCleanupStore.swift:62`, `:96`, `:129-135`
  - Cleanup selection stores `HostScopedThreadID` values with logical row ids, then execution finds hosts by exact endpoint id equality.
  - Required change: cleanup execution must resolve every selected row id through the shared resolver before sending archive commands.

- [x] `CodexDock/Archive/ArchiveCleanupDataEngine.swift:90-98`, `:153-173`
  - Counts already use a local alias helper, but that helper is not shared and is exact-case only.
  - Required change: delete the local alias helper and use the shared resolver so preview counts, review rows, and execution agree.

- [x] `CodexDock/Features/Archive/ArchiveCleanupView.swift:185`, `:397-402`, `:619-621`, `:694-696`
  - Review drilldown receives endpoint-backed `initialHostID`, filters rows by exact comparison, and confirmation summary groups logical ids then looks them up by endpoint ids.
  - Required change: drilldown filter and confirmation summary must use resolver membership and resolver display labels.

- [x] `CodexDock/Dock/DockModels.swift:239-245`
  - `DockRowViewModel.metadataKey` now persists `LocalThreadMetadataKey.hostID` from the logical row id.
  - Required change: keep new metadata keys logical-host scoped, but provide a migration from old endpoint-keyed metadata.

- [x] `CodexDock/State/LocalThreadMetadataStore.swift:3-10`, `CodexDock/Metadata/LocalMetadataEngine.swift:18-20`
  - Metadata keys persist a raw host string without a namespace marker, and load has no migration.
  - Required change: add an explicit one-time migration path from endpoint/display-name keyed metadata to logical-host keyed metadata once the resolver can map aliases.

- [x] `CodexDock/Archive/ArchiveDataEngine.swift:26-29`, `CodexDock/Archive/ArchiveCleanupDataEngine.swift:26-29`
  - Archive and Archive Cleanup bypass `LocalMetadataEngine` and call `metadataStore.load()` directly.
  - Required change: route Dock, Archive, and Archive Cleanup through one shared resolver-backed metadata migration owner before projecting rows or exclusions.

- [x] `CodexDock/Dock/DockRenderProjector.swift:15-23`
  - Cached pinned rows are excluded only by exact loaded metadata keys.
  - Required change: exclusion must de-duplicate old endpoint-keyed pinned rows against live logical rows during/after migration.

- [x] `CodexDock/State/ThreadCardTable.swift:80-111`, `:226-246`, `CodexDock/Dock/DockRenderModels.swift:3-20`
  - Snapshot/update processing stores card data but does not retain stream host metadata as an alias source.
  - Render input carries cards by endpoint host id but no resolver, no stream-host alias index, and no explicit source configured host id on row-bound cards.
  - Required change: store `hosts`/`upsertHosts` metadata per configured endpoint, retain each card's source configured endpoint, and expose a single `DockHostIdentityResolver`/identity snapshot through render input.

- [x] `CodexDock/AppServer/DockThreadCardDTO.swift:138-151`, `contract/dock/dock-thread-card.schema.json:193-203`
  - Host-level `logicalHostID` is optional even though the architecture says host metadata must carry it.
  - Required change: enforce one contract: stream host `id` is the canonical logical host id, stream host `logicalHostID` is required and must equal `id`, `displayName` is display-only, and `endpoint` is endpoint metadata only.

- [x] `scripts/generate-dock-thread-card-contract.mjs`, `scripts/check-dock-thread-card-contract.mjs`, `package.json`
  - `CodexDock/AppServer/DockThreadCardDTO.swift` is generated, and `rtk npm run test:relay` does not run the contract check.
  - Required change: update schema first, regenerate with `rtk npm run contract:generate`, and keep `rtk npm run contract:check`/`rtk make contract-check` green after schema, fixture, or generated DTO changes.

- [x] `scripts/codex-dock-host-service.mjs:453`, `scripts/dock-relay.mjs:1258`, `scripts/dock-relay-state-views.mjs:45-52`, `:298-316`
  - The host service launches the relay with host id/name but normally does not pass the app-facing endpoint into relay host/card metadata.
  - Required change: make `publicHostFromConfig()` or its direct replacement the single relay identity helper, pass endpoint metadata to it as metadata only, and never let endpoint metadata become logical identity.

- [x] `scripts/dock-relay-state-store.mjs:628-662`
  - `applyArchiveMutation()` reconstructs `dockID` from generic `hostID`.
  - Required change: use a central relay card-id helper with a parameter named `logicalHostID`, or load the existing stored `dock_id`/`logical_host_id`.

- [x] `scripts/dock-relay-state-views.mjs:310-316`, `scripts/dock-relay-thread-fidelity.mjs:1157-1160`, `contract/dock/fixtures/thread-card-stream-snapshot.json`, `contract/dock/fixtures/thread-card-stream-delta.json`
  - Code/fixtures/fidelity currently behave as `logicalHostID::threadID`, while the architecture doc still says card id uses `logicalHostID`, `backendSessionID` when present, and `threadID`.
  - Required change: make `logicalHostID::threadID` the card id rule everywhere. `backendSessionID` remains required card data and metadata-key data, but it is not part of `DockThreadCardDTO.id`.

- [x] `CodexDock/State/ScriptedDockStreamClient.swift:169-172`, `:399-405`, `CodexDock/Features/Dock/DockViewPreview.swift:85-109`
  - Debug/scripted and preview emitters currently model a split but still build card `id` from endpoint-backed `host.id` while using display-name logical ids.
  - Required change: scripted and preview emitters must use the same `logicalHostID::threadID` rule and host metadata contract, even though previews remain non-evidence.

- [x] `CodexDockTests/DockStoreTestSupport.swift:282-347`, `:914-930`
  - Shared test helpers collapse `logicalHostID == host.id`.
  - Required change: add a default or named fixture path where configured endpoint id differs from `logicalHostID`.

- [x] `CodexDockTests/ThreadDetailStoreTests.swift`, `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`, `CodexDockTests/ThreadDetailStreamingMergeTests.swift`, `CodexDockTests/ClientRuntimeTests.swift`
  - Detail tests repeatedly call `makeDetailRow(hostID: host.id, ...)`.
  - Required change: add coverage where `row.id.hostID == "Amir-M5"` and `host.id == "amir-m5.fairy-salmon.ts.net:4510"`, and prove transport still uses the endpoint host.

- [x] `CodexDockTests/DockStoreTestsProjection.swift`, `CodexDockTests/ArchiveScreenStoreTests.swift`, `CodexDockTests/ArchiveCleanupStoreTests.swift`, `CodexDockTests/ArchiveDataEngineTests.swift`
  - Projection, archive, and cleanup tests mostly use endpoint-backed row ids.
  - Required change: add logical-vs-endpoint fixture coverage for host filters, host lens grouping, restore, cleanup preview, cleanup drilldown, cleanup confirmation, and cleanup execution.

## Centralization Contract

The Swift owner is `CodexDock/State/DockHostIdentityResolver.swift`. It should
be a small value-type resolver plus result types, not feature-local matching
logic.

- `HostRegistry` remains the endpoint-list owner.
- `DockHostIdentityResolver` owns every bridge between row identity and configured endpoint identity.
- `ThreadCardTable` owns the live Dock alias lifecycle: it stores stream host metadata from `hosts`/`upsertHosts`, records the source configured endpoint for each card, and rebuilds one resolver snapshot from configured hosts plus stream/card observations.
- `ThreadCardHostSnapshotLoader` must return enough host metadata and source configured endpoint context for Archive and Archive Cleanup to build the same resolver shape before projecting rows.
- `DockRenderInput` must carry the resolver or a resolver-built identity snapshot; projectors and views must not rebuild their own alias maps.
- Rows remain logical-host scoped: `DockRowViewModel.id.hostID`, `HostScopedThreadID.hostID`, and new `LocalThreadMetadataKey.hostID` values should use `DockThreadCardDTO.logicalHostID`.
- Saved config and network clients remain endpoint scoped: `DockHostConfiguration.id`, `DockHostConfiguration.endpoint`, WebSocket connection targets, and command clients should still use host/port endpoint config.
- UI filters may store endpoint ids or resolver-owned selection keys, but evaluation must call the resolver. No feature should compare `row.id.hostID` to `host.id` directly.
- Action callers should pass a `ResolvedDockHost` or equivalent resolver result when they need both logical row identity and endpoint transport identity. Passing naked `DockHostConfiguration` plus a row is allowed only after the resolver has already proved the row belongs to that configured host.
- The resolver must be able to answer:
  - resolve a row logical host id to a logical-host group and a preferred configured endpoint;
  - check whether a row host id belongs to a configured host;
  - list aliases for a configured host;
  - provide a display label and endpoint label for row-facing UI;
  - report missing and ambiguous identity results without routing to a wrong host.
- Alias inputs should include:
  - `DockHostConfiguration.id`;
  - `DockHostConfiguration.displayName`;
  - `DockHostConfiguration.endpoint.displayEndpoint`;
  - stream `DockStreamHostDTO.id`;
  - stream `DockStreamHostDTO.logicalHostID`;
  - stream `DockStreamHostDTO.displayName`;
  - stream `DockStreamHostDTO.endpoint`;
  - card `DockThreadCardDTO.logicalHostID`;
  - card `DockThreadCardDTO.hostDisplayName`;
  - card `DockThreadCardDTO.hostEndpoint`.
- Multiple configured endpoints may map to the same logical host. That is valid failover, not ambiguity.
- Same-logical-host endpoint groups must resolve to one preferred endpoint for actions using this order:
  1. the source configured endpoint that produced the card/row, if still configured;
  2. an endpoint explicitly selected by the current UI context, if it belongs to the same logical-host group;
  3. a currently loaded or connected endpoint in registry order;
  4. the first configured endpoint in registry order for that logical-host group.
- Ambiguity means one alias maps to multiple logical-host groups, not multiple endpoints in the same logical-host group. Ambiguous aliases must fail closed for actions and remain visible as unresolved for display/search.
- Case handling must be explicit. The live Home payload proves `logicalHostID == "home"` while `displayName == "Home"`; the resolver should use exact canonical ids first, then documented case-insensitive alias matching only when it maps to exactly one host.
- Display name is not a primary identity. It can be an alias only when unambiguous.
- Endpoint text is never allowed to become the row logical id as a fallback in new code.
- Delete the old `ThreadCardRowProjector` alias helpers and `ArchiveCleanupDataEngine.hostAliases(_:)`. Keep `DockStore.hostConfiguration(for:)` only as a thin compatibility wrapper around the resolver until all callers move to resolver result types.

## Relay Contract Clarification

The relay should not be changed back to endpoint-derived card ids.

Required relay-side cleanup for this bug class:

- Make `publicHostFromConfig(config)` in `scripts/dock-relay-state-views.mjs`, or a direct replacement with the same callers, the single relay identity helper. Do not add a second identity helper beside it.
- The stream host contract is: `host.id == host.logicalHostID`, `host.logicalHostID` is required, `host.displayName` is display-only, and `host.endpoint` is endpoint metadata only.
- Add one card id helper, for example `dockCardID({ logicalHostID, threadID })`.
- The card id contract is exactly `logicalHostID::threadID`. `backendSessionID` remains required card data but is not part of `DockThreadCardDTO.id`.
- Pass the app-facing endpoint from `scripts/codex-dock-host-service.mjs` to `scripts/dock-relay.mjs` as endpoint metadata so `publicHostFromConfig()` can emit `endpoint` and cards can emit `hostEndpoint`.
- Keep endpoint metadata separate from `logicalHostID`; endpoint metadata must help Swift resolve/label hosts, not become the row identity.
- Tighten `contract/dock/dock-thread-card.schema.json`, `scripts/generate-dock-thread-card-contract.mjs`, and generated `CodexDock/AppServer/DockThreadCardDTO.swift` so host-level `logicalHostID` is required and non-optional.
- Update `docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md` so it no longer says card id includes `backendSessionID`.

## Migration Plan

The local metadata migration is part of the same fix. Without it, users can lose or duplicate labels, rails, and pins after the identity split.

- Expand `CodexDock/Metadata/LocalMetadataEngine.swift` into the shared metadata coordinator used by Dock, Archive, and Archive Cleanup. It may delegate pure key-rewrite logic to a small helper in `CodexDock/Metadata/`, but callers must go through `LocalMetadataEngine`.
- `ArchiveDataEngine` and `ArchiveCleanupDataEngine` must stop calling `metadataStore.load()` directly unless that call goes through the shared migration owner.
- The migration owner loads existing `LocalThreadMetadataKey` values, runs deterministic key normalization with a resolver, persists only when values change, and returns migrated values to every caller.
- No metadata store version envelope is required if the migration is proven idempotent. If a version envelope is added, this plan must update `LocalThreadMetadataStore` tests and file compatibility expectations.
- Migration must run after enough aliases exist:
  - Dock path: load raw metadata, synchronize streams, build resolver from configured hosts plus stream/card observations, run migration, update `DockDataEngine` local metadata, then publish the first loaded snapshot for hosts that returned rows.
  - Archive path: load host snapshots, build resolver from configured hosts plus archive stream/card observations, run migration, then project archive sections.
  - Archive Cleanup path: load cleanup candidate snapshots, build resolver from configured hosts plus stream/card observations, run migration, then compute exclusions, candidates, host summaries, and selected rows.
- For hosts that are offline or returned no stream/card aliases, do not guess. Leave unresolved metadata keys unchanged and render/action through the resolver's missing/ambiguous states.
- For every metadata key whose `hostID` is an endpoint id, display endpoint, or display-name alias for exactly one logical-host group, rewrite it to that group's logical host id while preserving `backendSessionID` and `threadID`.
- If both old and new keys exist for the same logical host/backend session/thread:
  - preserve user-authored values from the newer/logical key when both set the same field;
  - merge non-conflicting label, rail, pin state, pinned order, and last-known display fields;
  - never drop a pinned row silently.
- If a key maps to no host, leave it unchanged.
- If a key maps to multiple hosts, leave it unchanged and record a non-secret diagnostic.
- After migration, live row lookup and cached pinned de-duplication must use logical keys only.

## Implementation Phases

Implemented in this pass.

1. Resolver and fixture baseline
   - Add the central Swift resolver.
   - Add the resolver-owned source endpoint model needed to distinguish a logical-host group from a preferred transport endpoint.
   - Add logical-vs-endpoint test fixtures for `Amir-M5` and `home`/`Home`.
   - Add multi-endpoint same-logical-host fixture coverage, such as `Amir-M5.local:4510` and `192.168.50.74:4510` both mapping to logical host `Amir-M5`.
   - Add tests proving ambiguous display aliases do not route actions.

2. Narrow detail-open gate
   - Replace `DockStore.hostConfiguration(for:)`, detail destination lookup, and `ThreadDetailStore.load()` host guard with resolver calls.
   - Prove detail opens for `Amir-M5` while transport still uses `amir-m5.fairy-salmon.ts.net:4510`.
   - Do not widen to host filters, archive, cleanup, or metadata migration until this gate passes.

3. Dock projection and filters
   - Replace `ThreadCardRowProjector` display/endpoint helpers, Dock host lens grouping, Dock host filters, and `hostState(for:)` with resolver calls.
   - Prove logical rows appear under the configured host lens/filter and same-logical-host multi-endpoint groups do not duplicate rows.

4. Archive and cleanup paths
   - Replace archive filters, archive restore, cleanup review filters, cleanup confirmation summary, cleanup preview alias counting, and cleanup execution with resolver calls.
   - Prove preview counts, drilldown lists, selected rows, confirmation copy, and archive commands all agree for logical-vs-endpoint split hosts.

5. Metadata migration and pinned-row de-duplication
   - Add the shared migration owner and route Dock, Archive, and Archive Cleanup metadata reads through it.
   - Add explicit migration from endpoint/display-name keyed metadata to logical-host keyed metadata after stream/card aliases are known.
   - Add duplicate-key merge behavior.
   - Prove old endpoint-keyed pinned rows do not appear beside new live logical rows for the same thread.

6. Relay/schema/docs convergence
   - Make `publicHostFromConfig()` or its replacement the single relay identity helper.
   - Add the relay card-id helper for `logicalHostID::threadID`.
   - Pass endpoint metadata to relay host/card payloads.
   - Make schema, generator, generated Swift DTOs, fixtures, fidelity checks, scripted emitters, previews, and architecture docs agree on host identity and card id rules.

7. Delete side doors
   - Remove or wrap every local alias helper and raw row-host-to-configured-host comparison listed in the affected checklist.
   - Search for remaining `row.id.hostID == host.id`, `hosts.first { $0.id == row.id.hostID }`, selected host filters that compare directly to row host ids, relay card id reconstruction from generic `hostID`, scripted/preview endpoint-derived card ids, and any new helper beside `publicHostFromConfig()`.

## Proof Plan

Phase-scoped checks:

- Resolver/detail gate:
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test --filter DockStoreTests`
- DTO/schema/contract changes:
  - `rtk npm run contract:generate`
  - `rtk make contract-check`
  - `rtk swift test --filter AppServerClientTests`
- Dock projection/filter changes:
  - `rtk swift test --filter DockStoreTests`
- Archive and cleanup changes:
  - `rtk swift test --filter ArchiveScreenStoreTests`
  - `rtk swift test --filter ArchiveDataEngineTests`
  - `rtk swift test --filter ArchiveCleanupStoreTests`
- Relay and host-service changes:
  - `rtk npm run test:relay`
  - `rtk npm run test:host-service`
  - `rtk npm test`

Final combined checks after all phases:

- `rtk swift test`
- `rtk npm test`

Required behavior proofs:

- A configured host `amir-m5.fairy-salmon.ts.net:4510` with card `logicalHostID: "Amir-M5"` opens thread detail without the host mismatch error.
- Detail transport connects to `ws://amir-m5.fairy-salmon.ts.net:4510`, not `ws://Amir-M5`.
- Dock host lens shows rows for the configured host when row ids are logical.
- Dock host filters include logical rows when endpoint-backed chips are selected, or when resolver-owned selection keys are selected.
- Archive host filters show logical rows under the configured host.
- Archive restore sends the command through the configured endpoint host.
- Archive cleanup preview counts, review drilldown rows, confirmation summary, and execution all agree for the same logical-vs-endpoint host.
- Endpoint-keyed metadata migrates to logical-host keyed metadata without losing labels, rails, pins, pinned order, or last-known display fields.
- Old endpoint-keyed pinned rows do not duplicate live logical rows after migration.
- Ambiguous display-name aliases fail closed with a clear error instead of routing to the wrong host.
- Multiple endpoints for the same logical host are treated as one logical-host group and route actions through a deterministic preferred endpoint.
- Live `home`/`Home` casing is covered.
- Relay emitted host/card endpoint metadata remains metadata only and never replaces `logicalHostID`.
- Stream host `id` equals required `logicalHostID` in schema, generated Swift DTOs, fixtures, relay payloads, scripted emitters, and previews.
- Card ids are exactly `logicalHostID::threadID`; `backendSessionID` remains separate required card data and never enters `DockThreadCardDTO.id`.

<!-- bugs:block:analysis:end -->

<!-- bugs:block:fix_plan:start -->

## Fix Plan

Implemented in this pass.

The fix is not localized to thread detail. The implementation must follow the
`Affected Location Checklist`, `Centralization Contract`, `Relay Contract
Clarification`, `Migration Plan`, `Implementation Phases`, and `Proof Plan`
above.

Non-negotiable fix rules:

- Preserve `row.id.hostID` as the card `logicalHostID`.
- Preserve `DockHostConfiguration.id` as the endpoint id.
- Preserve saved app configs as `{host, port}` endpoint lists only.
- Route every row-to-host action, filter, display fallback, archive/cleanup action, and metadata migration through one shared host identity resolver.
- Do not compare `row.id.hostID` directly to `host.id` outside that resolver.
- Do not change relay card ids back to endpoint-derived ids.
- Do not add a broad old-contract fallback that silently turns endpoint ids into logical ids.
- Fail closed when aliases are missing or ambiguous.
- Treat multiple configured endpoints for the same logical host as one logical-host group with a deterministic preferred endpoint, not as an ambiguity.

Done state:

- Thread detail opens valid logical-host rows and still connects to the configured endpoint.
- Dock host filters and host lens grouping show logical rows under the configured endpoint host.
- Archive restore and archive host filters work for logical rows.
- Archive cleanup preview, review, confirmation, and execution all agree on the same resolved host.
- Local labels, rails, pins, pinned order, and last-known display metadata migrate from endpoint-keyed host ids to logical-host ids without duplicate rows.
- Relay host/card endpoint metadata is emitted as metadata and does not drift into logical identity.
- Tests include at least one fixture where `logicalHostID != DockHostConfiguration.id` and one fixture for the live `home`/`Home` casing.
- Tests include a same-logical-host multi-endpoint fixture and prove the resolver picks the source endpoint first, then the configured fallback order.
- Stream host `logicalHostID` is required and equals stream host `id`.
- Card id is exactly `logicalHostID::threadID`; `backendSessionID` stays separate required card data.
- All local alias helpers and direct logical-vs-endpoint comparisons listed in the checklist are removed or wrapped by the shared resolver.

<!-- bugs:block:fix_plan:end -->

<!-- bugs:block:implementation:start -->

## Implementation

Implemented the full host-identity unification plan:

- Added `CodexDock/State/DockHostIdentityResolver.swift` as the single Swift bridge between row logical host ids and configured endpoint hosts.
- Kept `DockRowViewModel.id.hostID` logical-host scoped and added `sourceHostID` so row actions can prefer the endpoint that produced the row.
- Wired resolver snapshots through `ThreadCardTable`, `DockRenderInput`, `DockSnapshot`, `ArchiveSnapshot`, and `ArchiveCleanupPreviewSnapshot`.
- Replaced thread-detail, Dock open/archive, Dock host lens/filter membership, Archive restore/filtering, Archive Cleanup preview/review/confirmation/execution, and host-state lookup with resolver checks.
- Routed Dock, Archive, and Archive Cleanup metadata through `LocalMetadataEngine.migrateHostAliases(using:)`.
- Made metadata migration idempotent, proof-gated by observed relay logical-host metadata, and collision-safe so existing logical-key metadata wins field conflicts.
- Tightened the relay contract so stream host `logicalHostID` is required and card ids are exactly `logicalHostID::threadID`.
- Passed app-facing endpoint metadata into the relay via `--host-endpoint` / `CODEX_DOCK_HOST_ENDPOINT`.
- Updated scripted/preview emitters, contract generator output, relay card-id helpers, relay archive mutation reconstruction, fixtures/tests, and the architecture doc.

## Verification Run

Commands/evidence gathered during root-cause:

```sh
rg -n "This row belongs|belongs to host|host_mismatch|row.id.hostID|logicalHostID|displayEndpoint|HostScopedThreadID|makeRow\\(|ThreadCardRowProjector|DockThreadCardDTO" CodexDock CodexDockTests scripts contract docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md -g '!CodexDock.xcodeproj/**'
```

```sh
rtk node --input-type=module -e 'import { JsonRpcWebSocketClient } from "./scripts/dock-relay-json-rpc-client.mjs"; for (const url of ["ws://amir-m5.fairy-salmon.ts.net:4510","ws://home.fairy-salmon.ts.net:4510"]) { const client=new JsonRpcWebSocketClient(url); try { await client.connect(); const result=await client.request("dock/subscribe", {}); const card=result.cards?.[0]; console.log(JSON.stringify({url, keys:Object.keys(result).sort(), schemaVersion:result.schemaVersion, view:result.view, hosts:result.hosts, firstCard:card && {id:card.id, logicalHostID:card.logicalHostID, hostDisplayName:card.hostDisplayName, hostEndpoint:card.hostEndpoint, threadID:card.threadID}}, null, 2)); } finally { await client.close(); } }'
```

Implementation proof:

```sh
rtk npm run contract:generate
rtk npm run contract:check
rtk swift test --filter AppServerClientTests
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter DockStoreTests
rtk swift test --filter Archive
rtk swift test --filter DockHostIdentityResolverTests
rtk swift test --filter LocalMetadataEngineTests
rtk swift test
rtk npm test
rtk xcodegen generate --spec project.yml
FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

Latest full checks:

- `rtk swift test`: 315 tests, 5 skipped, 0 failures.
- `rtk npm test`: contract check passed; relay tests 118 passed; host-service tests 34 passed.
- `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'`: passed; generated project built, installed, and launched on the simulator.
- First external `fresh-consult` with Cursor Agent Composer 2.5 Fast returned `FAIL - issues remain`; the cited preview-id and proof-coverage gaps were repaired before the final rerun.
- Final external `fresh-consult` with Cursor Agent Composer 2.5 Fast returned `pass-with-notes` with `BLOCKING: none`; remaining notes are staging and relay restart/deploy hygiene.
- `rtk xcodegen generate --spec project.yml`: passed; generated project includes `DockHostIdentityResolver.swift` and `DockHostIdentityResolverTests.swift`.
- Side-door search for raw row-host endpoint comparisons returned no production matches:

```sh
rg -n "row\\.id\\.hostID\\s*!=\\s*selectedHostID|row\\.id\\.hostID\\s*==\\s*configuredHostID|row\\.id\\.hostID\\s*==\\s*host\\.id|host\\.id\\s*==\\s*row\\.id\\.hostID|hosts\\.first\\s*\\{\\s*\\$0\\.id\\s*==\\s*row\\.id\\.hostID|hostAliases\\(" CodexDock scripts contract -g '!CodexDock.xcodeproj/**'
```

<!-- bugs:block:implementation:end -->
