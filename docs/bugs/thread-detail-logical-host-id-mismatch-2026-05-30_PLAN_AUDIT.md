# Plan Audit Log

Plan: `docs/bugs/thread-detail-logical-host-id-mismatch-2026-05-30.md`
Audit log: `docs/bugs/thread-detail-logical-host-id-mismatch-2026-05-30_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: pass
Last reviewed: 2026-05-31T01:55:47Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Resolved Blocking Findings

- [x] PLA-001 - Host metadata contract was still a choice
  - Lens: Ambiguity and contract clarity.
  - Evidence: The plan previously allowed either requiring `hosts[].logicalHostID` or treating `hosts[].id` as the only logical id.
  - Required plan repair: Choose one host metadata contract and carry it through schema, DTOs, relay payloads, fixtures, and proofs.
  - Status: resolved.
  - Resolution evidence: The plan now states stream host `id` is the canonical logical host id, stream host `logicalHostID` is required and must equal `id`, `displayName` is display-only, and `endpoint` is endpoint metadata only.

- [x] PLA-002 - Card id rule was undecided
  - Lens: Ambiguity and contract clarity.
  - Evidence: The plan previously left room to reintroduce `backendSessionID` into card ids.
  - Required plan repair: State the exact card id rule.
  - Status: resolved.
  - Resolution evidence: The plan now states card id is exactly `logicalHostID::threadID`; `backendSessionID` remains separate required card data and metadata-key data.

- [x] PLA-003 - Metadata migration timing and alias source were underspecified
  - Lens: Ambiguity, state lifecycle, and data preservation.
  - Evidence: The plan required migration from endpoint-keyed metadata to logical-host-keyed metadata but did not say when stream/card aliases had to exist or whether rendering could happen before migration.
  - Required plan repair: Define resolver lifecycle, migration timing, unresolved-key handling, and completion conditions.
  - Status: resolved.
  - Resolution evidence: The plan now requires a shared migration owner, runs migration after configured hosts plus stream/card observations exist, runs it before Dock's first loaded snapshot and before Archive/Archive Cleanup projection, and leaves unresolved/offline keys unchanged.

- [x] PLA-004 - Same-logical-host multi-endpoint configs conflicted with fail-closed ambiguity
  - Lens: Constraints and local repo behavior.
  - Evidence: The plan treated duplicate aliases as ambiguity without deciding whether two saved endpoints may point at the same logical host.
  - Required plan repair: Decide whether same-logical-host endpoint lists are valid and define tie-breaking.
  - Status: resolved.
  - Resolution evidence: The plan now treats multiple configured endpoints for one logical host as valid failover and defines endpoint preference order: source endpoint, UI-selected endpoint, loaded/connected endpoint in registry order, then first configured endpoint.

- [x] PLA-005 - Proof checks did not cover contract, host-service, archive, or cleanup work
  - Lens: Proof and phase exit.
  - Evidence: The plan previously listed only `ThreadDetailStoreTests`, `DockStoreTests`, and `test:relay`.
  - Required plan repair: Make proof phase-scoped and include contract, DTO, host-service, archive, and cleanup checks.
  - Status: resolved.
  - Resolution evidence: The plan now includes `rtk npm run contract:generate`, `rtk make contract-check`, `rtk swift test --filter AppServerClientTests`, archive/cleanup test filters, `rtk npm run test:host-service`, `rtk npm run test:relay`, and final `rtk swift test` / `rtk npm test`.

- [x] PLA-006 - Resolver owner and alias-index lifecycle were ambiguous
  - Lens: Canonical owner and tiny-team maintainability.
  - Evidence: The plan previously said the resolver would live "likely" in `Configuration` or `State` and did not say who stores stream/card aliases.
  - Required plan repair: Name the canonical owner and lifecycle.
  - Status: resolved.
  - Resolution evidence: The plan now names `CodexDock/State/DockHostIdentityResolver.swift`, keeps `HostRegistry` as endpoint-list owner, assigns live alias lifecycle to `ThreadCardTable`, requires `ThreadCardHostSnapshotLoader` to return enough metadata for Archive/Cleanup, and requires `DockRenderInput` to carry the resolver or resolver-built identity snapshot.

- [x] PLA-007 - Phase 2 widened before an end-to-end detail proof
  - Lens: Depth-first implementation risk.
  - Evidence: The plan previously changed detail, row projection, grouping, and filters in one batch.
  - Required plan repair: Add a hard narrow gate for row tap -> resolver -> detail -> endpoint transport before widening.
  - Status: resolved.
  - Resolution evidence: The plan now has a "Narrow detail-open gate" phase and blocks widening to filters, archive, cleanup, or metadata migration until it passes.

- [x] PLA-008 - Metadata migration had no single owner across Dock, Archive, and Cleanup
  - Lens: Side-door closure and data preservation.
  - Evidence: Archive and Archive Cleanup read `metadataStore.load()` directly while Dock uses `LocalMetadataEngine`.
  - Required plan repair: Name one shared migration owner and force all readers through it.
  - Status: resolved.
  - Resolution evidence: The plan now requires a shared resolver-backed metadata migration owner and says Archive/Archive Cleanup must stop direct `metadataStore.load()` unless it goes through that owner.

- [x] PLA-009 - Generated contract coupling was underspecified
  - Lens: Generated artifact and drift-proof coupling.
  - Evidence: The plan previously named schema and generated DTO but not the generator, checker, or package scripts.
  - Required plan repair: Add generator/checker/package surfaces and proof.
  - Status: resolved.
  - Resolution evidence: The plan now includes `scripts/generate-dock-thread-card-contract.mjs`, `scripts/check-dock-thread-card-contract.mjs`, `package.json`, `rtk npm run contract:generate`, and `rtk make contract-check`.

- [x] PLA-010 - Debug/scripted emitters and relay helper side doors were still open
  - Lens: Side-door closure and drift-proof coupling.
  - Evidence: `ScriptedDockStreamClient` and `DockViewPreview` could keep emitting stale card-id/logical-id shapes, and the plan could add a second helper beside `publicHostFromConfig()`.
  - Required plan repair: Include debug/preview emitters and make one relay identity helper the only owner.
  - Status: resolved.
  - Resolution evidence: The plan now requires scripted/preview emitters to follow `logicalHostID::threadID` and makes `publicHostFromConfig()` or its direct replacement the single relay identity helper.

## Current Implementation Findings

None.

## Resolved Implementation Findings

- [x] IMP-001 - Logical metadata could lose field precedence during alias collision
  - Lens: data preservation and migration collision behavior.
  - Evidence: `LocalMetadataEngine.migrateHostAliases(using:)` sorted old endpoint keys before some logical keys, then merged into the first value. If both old endpoint-keyed and new logical-keyed metadata existed, the old label/rail could win field conflicts.
  - Required repair: when the incoming key is already the target logical key, treat it as the authoritative current value and merge old endpoint data only into empty fields.
  - Status: resolved.
  - Resolution evidence: `LocalMetadataEngine` now gives logical-key entries precedence on collisions, and `LocalMetadataEngineTests.testMigrateHostAliasesPreservesLogicalMetadataOnCollision` proves logical label/rail/pin order survive.

- [x] IMP-002 - Archive UI filters still compared selected endpoint chips to logical row ids
  - Lens: side-door closure.
  - Evidence: `ArchiveView.filteredSections` and `ArchiveCleanupReviewList.matchesFilters` still compared `row.id.hostID` directly to `selectedHostID`.
  - Required repair: evaluate archive and cleanup host filters through `DockHostIdentityResolver.contains(...)`.
  - Status: resolved.
  - Resolution evidence: `ArchiveView`, `ArchiveCleanupReviewList`, and archive-cleanup confirmation summary now use the snapshot resolver; side-door search returns no production matches for direct row-host endpoint comparisons.

- [x] IMP-003 - First fresh consult found preview and proof gaps before commit
  - Lens: external cold-read completion check.
  - Evidence: Cursor Agent Composer 2.5 Fast returned `FAIL - issues remain`: keep preview card ids on `logicalHostID::threadID`, add resolver edge proofs, and add stronger archive/cleanup split-host proofs.
  - Required repair: fix preview/test/doc drift, then rerun the external consult before commit.
  - Status: resolved.
  - Resolution evidence: `DockViewPreview` emits logical card ids; `DockHostIdentityResolverTests` covers case, same-logical multi-endpoint, and ambiguous display aliases; `ArchiveScreenStoreTests.testArchiveStoreRestoreResolvesLogicalHostRowToEndpointHost`, `ArchiveDataEngineTests.testEngineBuildsResolverForLogicalHostRowsLoadedFromEndpointHost`, and `ArchiveCleanupStoreTests.testPreviewAndArchiveSelectedResolveLogicalHostRowToEndpointHost` cover split logical-vs-endpoint archive/cleanup paths; the affected-location checklist is marked complete; explicit staging will include `DockHostIdentityResolver.swift`.

- [x] IMP-004 - Final fresh consult deployment notes before commit
  - Lens: commit/deploy hygiene.
  - Evidence: final Cursor Agent Composer 2.5 Fast consult returned `VERDICT: pass-with-notes`, `BLOCKING: none`, confidence high. Notes: stage untracked resolver/test/docs, regenerate Xcode project, restart relays after deploy.
  - Required repair: regenerate `CodexDock.xcodeproj` from `project.yml`, stage explicit task paths, and restart relays after home pull.
  - Status: resolved for code/doc review; deployment steps remain in the execution plan.
  - Resolution evidence: `rtk xcodegen generate --spec project.yml` completed and `CodexDock.xcodeproj/project.pbxproj` now references `DockHostIdentityResolver.swift` and `DockHostIdentityResolverTests.swift`.

## Implementation Audit Summary

Verdict: pass.

- The direct reported failure is fixed: thread detail now accepts a row whose `row.id.hostID` is logical (`Amir-M5`) while the transport host remains endpoint-backed (`amir-m5.fairy-salmon.ts.net:4510`).
- The same identity contract is carried through Dock projection/filtering, Archive restore/filtering, Archive Cleanup preview/review/confirmation/execution, metadata migration, relay host/card metadata, generated DTOs, and architecture docs.
- No production direct comparisons remain for the searched side-door patterns: raw `row.id.hostID == host.id`, selected endpoint chip versus logical row id, old `hostAliases(...)`, or archive `hosts.first { $0.id == row.id.hostID }`.
- Proof is green: `rtk swift test` passed 315 tests with 5 skips after fresh-consult repairs; `rtk swift test --filter DockHostIdentityResolverTests` passed 3 tests; `rtk swift test --filter Archive` passed 24 tests with 1 skip; `rtk npm test` passed contract check, 118 relay tests, and 34 host-service tests.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Direct failure path | `ThreadCardRowProjector.makeRow`, `DockStore.hostConfiguration(for:)`, `DockView.selectedDetailDestination`, `ThreadDetailStore.load()` | Proves logical row id reaches exact endpoint-id guard | Parent, parallel agents | read |
| Dock filters and host lens | `DockCardProjection`, `DockFilterSurfaceView`, `DockView.hostState(for:)` | Same direct logical-vs-endpoint comparisons in UI filters/grouping | Parent, parallel agents | read |
| Archive and cleanup | `ArchiveStore`, `ArchiveView`, `ArchiveCleanupStore`, `ArchiveCleanupDataEngine`, `ArchiveCleanupView`, `ArchiveDataEngine` | Same drift class in restore, filtering, preview, confirmation, and execution | Parent, parallel agents | read |
| Metadata and pinned rows | `DockModels.metadataKey`, `LocalThreadMetadataStore`, `LocalMetadataEngine`, `DockRenderProjector`, `PinnedMetadataOrdering` | User data can split or duplicate after identity shift | Parent, parallel agents | read |
| Stream host alias lifecycle | `ThreadCardTable`, `ThreadCardHostSnapshotLoader`, `DockRenderModels`, `DockRenderProjector` | Resolver needs stream host/card metadata and source endpoint context | Parent, plan-audit agents | read |
| Relay identity and card id | `dock-relay-state-views.mjs`, `dock-relay-state-store.mjs`, `dock-relay-state-engine.mjs`, `codex-dock-host-service.mjs`, `dock-relay.mjs` | Determines logical host id, endpoint metadata, and card id | Parent, parallel agents | read |
| Contract generation | `contract/dock/dock-thread-card.schema.json`, `DockThreadCardDTO.swift`, `generate-dock-thread-card-contract.mjs`, `check-dock-thread-card-contract.mjs`, `package.json` | Generated DTO/schema drift risk | Parent, plan-audit agents | read |
| Tests and fixtures | `DockStoreTestSupport.swift`, `ThreadDetailStoreTests.swift`, `DockStoreTestsProjection.swift`, `ArchiveScreenStoreTests.swift`, `ArchiveCleanupStoreTests.swift`, contract fixtures | Current tests collapse `logicalHostID == host.id`; new proofs need split fixtures | Parallel agents | read |
| Debug and preview emitters | `ScriptedDockStreamClient.swift`, `DockViewPreview.swift`, `CodexDockBootstrapView.swift` | Non-production emitters can keep stale identity rules alive | Plan-audit agents | read |

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses: generated contract coupling, metadata migration, multi-endpoint host failover, debug/preview emitters

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | What is host metadata identity? | `host.logicalHostID` required vs `host.id` only | Schema/DTO/relay/Swift resolver drift | `host.id == host.logicalHostID`; `logicalHostID` required | Plan owner | Centralization and relay contract sections | resolved |
| DEC-002 | What is card id shape? | `logicalHostID::threadID` vs including `backendSessionID` | Relay card ids, fixtures, fidelity, Swift diffing | `logicalHostID::threadID`; `backendSessionID` separate | Plan owner | Affected checklist, relay contract, proof plan | resolved |
| DEC-003 | When can metadata migrate? | Before stream aliases, after stream aliases, or per-reader ad hoc | Lost/duplicated pins and labels | Shared owner runs after aliases exist and before projection/render for loaded hosts | Plan owner | Migration plan and phase 5 | resolved |
| DEC-004 | Are multiple endpoints for one logical host valid? | Invalid ambiguity vs valid failover group | Phone configs with LAN plus local endpoints | Valid logical-host group with deterministic preferred endpoint | Plan owner | Centralization contract and proof plan | resolved |

## Pass History

### Pass 1 - 2026-05-30

- Mode: plan-readiness.
- Scope: whole bug worklog and future implementation plan.
- Baseline reviewed: repo code, live relay `dock/subscribe` payloads, contract doc, schema, Swift generated DTOs, tests/fixtures.
- Agents/lenses run: Swift UI/navigation/action boundaries; local metadata/pinned/filter/archive/cleanup; relay/contract/schema; test/fixture coverage.
- Code areas read: direct failure path, Dock projection/filtering, Archive, Archive Cleanup, metadata, relay identity, tests/fixtures.
- Findings added: direct thread detail root cause plus broader same-class affected-location checklist.
- Verdict: not-ready until centralization plan was written.
- Next audit focus: plan readiness.

### Pass 2 - 2026-05-31T01:16:55Z

- Mode: plan-readiness.
- Scope: whole plan.
- Baseline reviewed: updated plan plus targeted repo anchors from Pass 1.
- Agents/lenses run: ambiguity/done-state; code-truth/side-door/drift; proof/phase/tiny-team.
- Code areas read: host registry, stream table, render input, metadata read paths, generator/checker/package scripts, debug/preview emitters, Makefile and AGENTS command guidance.
- Findings added: PLA-001 through PLA-010.
- Findings resolved: PLA-001 through PLA-010 after plan edits.
- Findings carried forward: none.
- Verdict: ready.
- Next audit focus: implementation-audit after code changes exist.

### Pass 3 - 2026-05-31T01:18:06Z

- Mode: plan-readiness.
- Scope: final wording and ambiguity cleanup after clean re-audit.
- Baseline reviewed: updated plan text.
- Agents/lenses run: parent final proper-audit check only; prior re-audit lenses were already clean.
- Code areas read: no new code areas.
- Findings added: none.
- Findings resolved: removed remaining vague wording in plan text by pinning Dock filter state, helper deletion/wrapping, and `LocalMetadataEngine` as the shared metadata coordinator entrypoint.
- Findings carried forward: none.
- Verdict: ready.
- Next audit focus: implementation-audit after code changes exist.

### Pass 4 - 2026-05-31T01:45:53Z

- Mode: implementation-audit.
- Scope: whole implementation diff against the plan.
- Baseline reviewed: resolver, Dock, Archive, Archive Cleanup, metadata migration, relay/schema/generator/host-service, fixtures/tests, architecture doc, side-door searches, and local test output.
- Agents/lenses run: parent plan-audit implementation pass plus thermo-nuclear code quality review.
- Code areas read: direct failure path, resolver lifecycle, projection/filtering, archive/cleanup action paths, metadata collision merge, relay card-id helper, host endpoint metadata, generated DTO/schema, and docs.
- Findings added: IMP-001 and IMP-002.
- Findings resolved: IMP-001 and IMP-002.
- Findings carried forward: none.
- Verdict: pass.
- Next audit focus: fresh-consult external check, then deployment/restart verification.

### Pass 5 - 2026-05-31T01:54:59Z

- Mode: external-consult repair audit.
- Scope: Cursor Agent Composer 2.5 Fast `pass-with-notes` findings.
- Baseline reviewed: fresh-consult final output, preview emitter, shared test fixture stream helper, archive restore tests, archive data-engine tests, archive cleanup store tests, affected-location checklist, and targeted test output.
- Agents/lenses run: parent repair pass after external consult.
- Code areas read: `DockViewPreview`, `DockStoreTestSupport`, `ArchiveScreenStoreTests`, `ArchiveDataEngineTests`, `ArchiveCleanupStoreTests`, and bug doc checklist.
- Findings added: IMP-003.
- Findings resolved: IMP-003 code/test/doc repairs complete; final fresh-consult rerun still required.
- Findings carried forward: final external consult verdict and deployment/restart verification.
- Verdict: pass pending rerun.
- Next audit focus: final fresh-consult verdict, full checks, commit/push, home pull, relay restart verification.

### Pass 6 - 2026-05-31T01:58:42Z

- Mode: final external-consult audit.
- Scope: whole implementation diff after first consult repairs.
- Baseline reviewed: final Composer output, current diff, side-door searches, resolver, detail, Dock, Archive, Archive Cleanup, metadata, relay/schema, generated DTO, scripted/preview emitters, tests, and bug docs.
- Agents/lenses run: Cursor Agent Composer 2.5 Fast final fresh consult.
- Code areas read: direct failure path, resolver wiring, production row-to-host comparisons, Archive/Cleanup action paths, metadata migration, relay card-id helper, schema/DTO, scripted/preview emitters, and split-host tests.
- Findings added: IMP-004.
- Findings resolved: IMP-004 code/project hygiene complete; staging and relay restart remain execution tasks.
- Findings carried forward: commit/push, home pull, local/home relay restart verification.
- Verdict: pass; external consult has no blocking findings.
- Next audit focus: deployment verification only.
