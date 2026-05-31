# Plan Implementation Log

Plan: `docs/bugs/thread-detail-logical-host-id-mismatch-2026-05-30.md`
Audit log: `docs/bugs/thread-detail-logical-host-id-mismatch-2026-05-30_PLAN_AUDIT.md`
Active scope: whole plan
Last updated: 2026-05-31T02:00:23Z
Current checkpoint: implemented, local review, final external consult, Swift/npm checks, and simulator app build complete; pending commit, push, home pull, and relay restart

## Resume Snapshot

- Current state: implementation is complete in the worktree. Swift, relay, contract, archive, cleanup, metadata, docs, and tests have been updated. The first external `fresh-consult` findings are repaired; the final external consult has no blocking findings; generated simulator app build passed.
- Next useful move: commit/push, pull on the home server, and restart/verify relays.
- Known blockers: none.
- Native subagents used or useful next: Cursor Agent Composer 2.5 Fast final rerun returned `pass-with-notes` with `BLOCKING: none`; remaining notes are commit/deploy hygiene only.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Canonical resolver and narrow detail gate | `Centralization Contract`, phase 2 | implemented | `CodexDock/State/DockHostIdentityResolver.swift`, `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/State/DockStore.swift`, `CodexDock/Features/Dock/DockView.swift` | `rtk swift test --filter ThreadDetailStoreTests`; `rtk swift test --filter DockStoreTests`; `rtk swift test` | plan-audit clean; thermo review found and fixed metadata merge edge case |
| Dock projection/filter convergence | phase 3 | implemented | `ThreadCardTable`, `DockRenderInput`, `DockRenderProjector`, `ThreadCardRowProjector`, `DockCardProjection`, `DockView` | `rtk swift test --filter DockStoreTests`; static side-door search | plan-audit clean |
| Archive/Cleanup convergence | phase 4 | implemented | `ArchiveStore`, `ArchiveDataEngine`, `ArchiveView`, `ArchiveCleanupStore`, `ArchiveCleanupDataEngine`, `ArchiveCleanupView` | `rtk swift test --filter Archive`; static side-door search | plan-audit caught UI filter side door; fixed; fresh-consult requested split-host archive/cleanup proofs, added |
| Metadata migration | phase 5 | implemented | `LocalMetadataEngine.migrateHostAliases(using:)`; Dock, Archive, and Cleanup data engines route through it | `rtk swift test --filter LocalMetadataEngineTests`; `rtk swift test` | thermo review caught logical-key collision precedence; fixed |
| Relay/schema/docs convergence | phase 6 | implemented | `dock-thread-card.schema.json`, generated `DockThreadCardDTO.swift`, `dock-relay-state-views.mjs`, `dock-relay-state-store.mjs`, `dock-relay.mjs`, `codex-dock-host-service.mjs`, architecture doc | `rtk npm run contract:generate`; `rtk npm test` | plan-audit clean |
| Side-door deletion/search | phase 7 | implemented | resolver-backed call sites across Dock, Archive, Cleanup, metadata, and relay helper code | `rg` searches for raw row-host comparisons and stale card-id wording | plan-audit clean |

## Code Read Ledger

| Area | Files/symbols read | Why relevant | Fresh until | Notes |
| --- | --- | --- | --- | --- |
| Direct failure path | `DockStore.hostConfiguration`, `DockView.selectedDetailDestination`, `ThreadDetailStore.load` | Proves logical rows open through endpoint transport | code changes | Resolver is passed into detail store; guard uses `contains(rowHostID:sourceConfiguredHostID:in:)`. |
| Dock projection and filters | `ThreadCardTable`, `DockRenderInput`, `ThreadCardRowProjector`, `DockCardProjection` | Owns row projection, host lens, source endpoint, and filters | code changes | Stream/card observations now build one resolver snapshot. |
| Archive and cleanup | `ArchiveStore`, `ArchiveDataEngine`, `ArchiveView`, `ArchiveCleanupStore`, `ArchiveCleanupDataEngine`, `ArchiveCleanupView` | Same logical-vs-endpoint class outside Dock | code changes | Restore, preview counts, review filters, confirmation summary, and execution use resolver matching. |
| Metadata | `LocalMetadataEngine`, `LocalThreadMetadataStore`, `ThreadCardRowProjector` | Prevents lost labels/pins and duplicate pinned rows | code changes | Migration rewrites only when stream/card observations prove the logical host id. |
| Relay and contract | `dock-relay-state-views.mjs`, `dock-relay-state-store.mjs`, `dock-relay.mjs`, `codex-dock-host-service.mjs`, schema, generator, DTO | Keeps logical identity and endpoint metadata separated | code changes | `dockCardID(logicalHostID, threadID)` is the card-id helper; `hostEndpoint` is metadata. |

## Proof Freshness Ledger

| Proof | Scope covered | Result/context | Fresh until | Rerun trigger |
| --- | --- | --- | --- | --- |
| `rtk npm run contract:generate` | schema/generator/generated DTO | passed; regenerated `CodexDock/AppServer/DockThreadCardDTO.swift` | schema/generator/DTO changes | any contract change |
| `rtk swift test --filter ThreadDetailStoreTests` | detail open, host guard, detail lifecycle | passed after rerun; 53 tests, 0 failures | Swift detail changes | detail/session changes |
| `rtk swift test --filter DockStoreTests` | Dock projection, filters, host grouping, local metadata behavior | passed; 48 tests, 0 failures | Dock changes | Dock projection/store changes |
| `rtk swift test --filter Archive` | Archive and Archive Cleanup store/data-engine paths | passed; 24 tests, 1 skipped, 0 failures | archive/cleanup changes | Archive/Cleanup changes |
| `rtk swift test --filter DockHostIdentityResolverTests` | resolver case, multi-endpoint, and ambiguous alias behavior | passed; 3 tests, 0 failures | resolver changes | resolver changes |
| `rtk swift test --filter LocalMetadataEngineTests` | migration, no-guessing, collision merge precedence | passed; 5 tests, 0 failures | metadata changes | metadata changes |
| `rtk npm test` | contract check, relay, host-service | passed; contract current, 118 relay tests, 34 host-service tests | JS/contract changes | relay/host-service/contract changes |
| `rtk swift test` | full Swift package | passed; 315 tests, 5 skipped, 0 failures | Swift changes | any Swift change |
| `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'` | generated Xcode project app build/install/launch | passed; simulator app built, installed, and launched | app/project/source changes | generated project or app target changes |
| Side-door search | raw row-host comparisons and stale contract wording | production search returned no raw `row.id.hostID == host.id` / selected-host filter matches; stale `backendSessionID` card-id wording removed | code/doc changes | identity or contract changes |

## Continuous Review Ledger

| Finding | Source | Status | Repair anchor | Notes |
| --- | --- | --- | --- | --- |
| UI archive filters still compared `row.id.hostID` directly to selected endpoint host id | implementation audit side-door search | fixed | `ArchiveView.filteredSections`, `ArchiveCleanupReviewList.matchesFilters`, `ArchiveCleanupView.confirmationHostSummary` | Replaced with resolver membership checks. |
| Metadata collision merge could let old endpoint-keyed metadata beat already-logical metadata if endpoint key sorted first | thermo review | fixed | `LocalMetadataEngine.migrateHostAliases(using:)`, `testMigrateHostAliasesPreservesLogicalMetadataOnCollision` | Logical-key metadata now wins conflicting fields; pin order is normalized. |
| Architecture doc still said card id included `backendSessionID` | implementation audit contract/doc check | fixed | `docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md` | Now states card id is exactly `logicalHostID::threadID`. |
| First `fresh-consult` returned `FAIL - issues remain`: preview ID drift plus missing resolver/archive/cleanup split-host proof | Cursor Agent Composer 2.5 Fast | fixed | `DockViewPreview`, `DockHostIdentityResolverTests`, `ArchiveScreenStoreTests`, `ArchiveCleanupStoreTests` | Preview card ids use `logicalHostID::threadID`; resolver case, multi-endpoint, and ambiguous alias behavior have explicit tests; archive restore, cleanup preview, and cleanup execution have logical-vs-endpoint tests. |
| Final `fresh-consult` returned deployment notes only | Cursor Agent Composer 2.5 Fast | accepted | `/tmp/fresh-consult/codex-client-host-id-final-20260531T015713Z-wqiG5W/final.txt` | Verdict `pass-with-notes`, `BLOCKING: none`, confidence high; notes are explicit staging, Xcode project regeneration, and relay restart after deploy. Xcode project was regenerated. |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| Local alias helpers | Deleted or resolver-backed | resolver-backed | complete | `ThreadCardRowProjector`, `ArchiveCleanupDataEngine` |
| Direct row-host comparisons | Removed or resolver-backed | no production raw comparison matches in side-door search | complete | `rg` proof in Proof Freshness Ledger |
| Relay card id reconstruction | Central helper with logical host parameter | `dockCardID(logicalHostID, threadID)` | complete | `scripts/dock-relay-state-views.mjs`, `scripts/dock-relay-state-store.mjs` |
| Contract optional host logical id | Required and generated non-optional | `DockStreamHostDTO.logicalHostID: String` | complete | schema, generator, generated DTO |

## Decision Carry-Through

| Decision | Owner | Plan carry-through | Code carry-through | Status |
| --- | --- | --- | --- | --- |
| Host metadata identity | plan | `host.id == host.logicalHostID`; required logical host id | schema requires host `logicalHostID`; generated DTO is non-optional; relay emits logical host metadata | complete |
| Card id rule | plan | `logicalHostID::threadID` | relay helper and fidelity wording use `logicalHostID::threadID`; architecture doc updated | complete |
| Same logical host multi-endpoint behavior | plan | valid failover group with deterministic preferred endpoint | resolver prefers source endpoint, then preferred endpoint, then loaded/partial/empty endpoint, then registry order | complete |
| Metadata migration owner | plan | `LocalMetadataEngine` shared entrypoint | Dock, Archive, and Archive Cleanup route metadata through resolver-backed migration | complete |

## Pass Notes

### 2026-05-31T01:20:00Z - Implementation Start

- Intent: start from the narrow detail-open gate.
- Changed: implementation log created.
- Read: plan, plan-audit log, required skill docs, current git status.
- Proof: none yet.
- Review: none yet.
- Next: read resolver-adjacent Swift models and implement the first code slice.

### 2026-05-31T01:45:53Z - Implementation Complete Locally

- Changed: added `DockHostIdentityResolver`, propagated resolver snapshots through Dock/Archive/Cleanup/detail, migrated metadata through `LocalMetadataEngine`, tightened schema/generated DTOs, updated relay endpoint metadata and card-id helper, updated architecture docs, and added logical-vs-endpoint tests.
- Proof: `rtk swift test` passed with 309 tests, 5 skipped, 0 failures. `rtk npm test` passed contract check, 118 relay tests, and 34 host-service tests.
- Review: plan-audit implementation check and thermo review found no remaining blockers after the UI filter, architecture-doc, and metadata-collision fixes.
- Next: final `$fresh-consult` with `composer-2.5-fast`, then commit/push and relay restart/pull verification.

### 2026-05-31T01:55:47Z - First Fresh Consult Findings Repaired

- Changed: kept preview card ids on `logicalHostID::threadID`, added resolver edge tests, added archive restore and archive-cleanup preview/execution split-host tests, and marked the affected-location checklist complete.
- Proof: `rtk swift test --filter DockHostIdentityResolverTests` passed with 3 tests, 0 failures; `rtk swift test --filter Archive` passed with 24 tests, 1 skipped, 0 failures; `rtk swift test --filter DockStoreTests` passed with 48 tests, 0 failures; `rtk swift test --filter ThreadDetailStoreTests` passed after rerun with 53 tests, 0 failures; `rtk npm test` passed contract check, 118 relay tests, and 34 host-service tests; `rtk swift test` passed with 315 tests, 5 skipped, 0 failures.
- Review: Cursor Agent Composer 2.5 Fast returned `FAIL - issues remain`; all cited findings were repaired.
- Next: rerun `$fresh-consult` with `composer-2.5-fast`, then commit/push, pull home, and restart/verify relays.

### 2026-05-31T02:00:23Z - Final Fresh Consult And Build Gates Complete

- Changed: regenerated `CodexDock.xcodeproj` from `project.yml` so the new resolver source and resolver tests are in the generated project.
- Proof: `rtk swift test` passed with 315 tests, 5 skipped, 0 failures. `rtk npm test` passed contract check, 118 relay tests, and 34 host-service tests. `rtk xcodegen generate --spec project.yml` completed successfully. `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'` built, installed, and launched the simulator app.
- Review: final Cursor Agent Composer 2.5 Fast consult returned `VERDICT: pass-with-notes`, `BLOCKING: none`, and high confidence. Remaining notes are explicit staging and relay restart/deploy hygiene.
- Next: commit/push, pull home, and restart/verify relays.
