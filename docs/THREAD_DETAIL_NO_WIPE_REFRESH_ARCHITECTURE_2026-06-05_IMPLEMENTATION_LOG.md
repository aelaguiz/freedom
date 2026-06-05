# Plan Implementation Log

Plan: `docs/THREAD_DETAIL_NO_WIPE_REFRESH_ARCHITECTURE_2026-06-05.md`
Audit log: `docs/THREAD_DETAIL_NO_WIPE_REFRESH_ARCHITECTURE_2026-06-05_PLAN_AUDIT.md`
Active scope: whole plan through simulator proof, commit, push, and relay update if runtime relay code changes
Last updated: 2026-06-05T17:55:00Z
Current checkpoint: implementation complete and verified on `codex-dock-agents-tab-live-counts`

## Resume Snapshot

- Current state: retained Thread Detail reopen is implemented and verified in unit tests plus simulator proof.
- Next useful move: commit, push, and update deployment copies/relays.
- Do not redo unless stale: focused simulator proof at `/tmp/codex-client/sim-ui-audit-20260605T172611Z`; two-pass matrix at `/tmp/codex-client/sim-ui-controlled-matrix-run-20260605T172812Z/controlled-simulator-matrix.json`.
- Known blockers: none.
- Native subagents used or useful next: earlier parallel-agent review informed the plan; implementation and proof were parent-owned.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Store keeps rows while updating | Phase 1 | complete | `ThreadDetailStore.load()`, `refreshRetainedDetail()`, `ThreadDetailStoreModels.swift` | `rtk swift test --filter ThreadDetailStoreTests`; focused SIM proof | TN-001 satisfied: `ThreadDetailStore.swift` is 999 lines |
| View detaches instead of closes | Phase 1 | complete | `SessionDetailView.onDisappear { store.detachView() }` | `ThreadDetailStoreTests`; focused SIM proof | no destructive close on normal pop |
| Retained store cache | Phase 2 | complete | `ThreadDetailStoreCache`, Dock/Archive `openDetail(row:)` | `rtk swift test --filter ThreadDetailStoreCacheTests` | bounded by `CodexDockConstants.ThreadDetail.retainedStoreCapacity` |
| Controlled simulator reopen proof | Phase 3 | complete | `detail-reopen-retains-content` scenario and UI test branch | focused SIM proof; two-pass matrix | proves retained rows, `Updating`, no loading state |
| Commit/push/relay update decision | Completion checklist | pending | pending | verified before commit | no production relay runtime protocol change; deploy still requested |

## Code Read Ledger

| Area | Files/symbols read | Why relevant | Fresh until | Notes |
| --- | --- | --- | --- | --- |
| Detail store owner | `ThreadDetailStore.swift`, `ThreadDetailLiveState`, `load()`, `close()`, `observeDockRowUpdate(_:)` | Canonical content/lifecycle owner. | Store implementation changes. | `ThreadDetailStore.swift` starts at 959 lines. |
| Render path | `ThreadDetailScreenStore`, `ThreadDetailRenderProjector`, `ThreadDetailRenderModels` | Loaded rows can be republished without new row cache. | Render models/projection changes. | No new render cache planned. |
| Reconciler | `StreamReconciler.manualRefresh()`, `requestResync`, freshness mapping | Existing no-wipe resync primitive. | Reconciler changes. | Production route stays `thread/detail/resync`. |
| Callers | `DockView.openDetail`, `ArchiveView.openDetail`, navigation bindings | Current fresh-store creation and selected-store clearing cause reopen wipe. | Dock/Archive caller changes. | Cache helper should keep caller edits tiny. |
| UI proof | `SessionDetailView`, `AutomationID.Session`, displayed sync UI test support | Must prove loaded root, no loading ID, retained message list, `Updating`. | UI/accessibility changes. | No new visible explanatory text. |
| Fixture proof | Controlled simulator fixture, fixture tests, matrix | Must add delayed resync scenario. | Fixture or matrix changes. | Production relay restart only needed if runtime relay changes. |

## Proof Freshness Ledger

| Proof | Scope covered | Result/context | Fresh until | Rerun trigger |
| --- | --- | --- | --- | --- |
| `rtk swift test --filter ThreadDetailStoreTests` | Store semantics and lifecycle tests | passed: 65 tests, 0 failures | Fresh until store/test/reconciler touched. | Store/test/reconciler changes. |
| `rtk swift test --filter ThreadDetailStoreCacheTests` | Retained cache identity, reattach, eviction | passed: 3 tests, 0 failures | Fresh until cache/caller tests touched. | Cache/caller changes. |
| `rtk swift test --filter ThreadDetailScreenStoreTests` | Screen-store stop/start render resumption | passed: 2 tests, 0 failures | Fresh until screen store/render touched. | Screen-store changes. |
| `rtk npm run test:relay` | Relay fixture/matrix/proof tests | passed: 236 tests, 0 failures | Fresh until relay/proof scripts touched. | Any script proof change. |
| `rtk npm run contract:check` | Projection and proof schema contracts | passed: 5 proof schemas and 5 canonical samples | Fresh until schemas/contracts touched. | Contract changes. |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-reopen-retains-content` | End-to-end retained reopen proof | passed; report `/tmp/codex-client/sim-ui-audit-20260605T172611Z/simulator-ui-sync.json` | Fresh until Swift UI/store/fixture/matrix touched. | UI/store/fixture changes. |
| `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` | Controlled simulator matrix | passed; 42 reports, 21/21 scenarios passing, max UI lag 762 ms | Fresh until controlled scenario definitions or covered runtime paths touched. | Fixture/matrix/UI/store changes. |

## Continuous Review Ledger

| Finding | Source | Status | Repair anchor | Notes |
| --- | --- | --- | --- | --- |
| TN-001 - keep `ThreadDetailStore.swift` under 1,000 lines | thermo review | resolved | `ThreadDetailStoreModels.swift` extraction | `rtk wc -l CodexDock/State/ThreadDetailStore.swift` reports `999`. |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| `thread/detail/read` | Not used as phone/app proof route | Forbidden by proof contracts; not a production app route | unchanged | `scripts/proof-report-contracts.mjs` |
| Fresh store creation in Dock/Archive | Replaced by shared cache helper | Retained through `ThreadDetailStoreCache` | complete | `DockView.openDetail`, `ArchiveView.openDetail` |
| `SessionDetailView.onDisappear` | Detach visible work only | Calls `detachView()` | complete | `SessionDetailView` |

## Decision Carry-Through

| Decision | Owner | Plan carry-through | Code carry-through | Status |
| --- | --- | --- | --- | --- |
| Retention is current-process only | Plan author | Non-requirements | `ThreadDetailStoreCache` only | complete |
| Updating is loaded-state status, not loading screen | Plan author | Target Architecture sections 2, 5, 7 | `.loaded(... liveState: .updating)` | complete |
| No relay production protocol change | Plan author | Target Architecture section 6 | existing `thread/detail/resync` | complete |

## Pass Notes

### 2026-06-05T16:48:28Z - Implementation Start

- Intent: start Phase 1 with the smallest integrated no-wipe retained refresh slice.
- Changed: implementation log only.
- Read: plan, audit log, thermo review, store, callers, proof surfaces.
- Proof: none run yet.
- Review: TN-001 remains active.
- Next: edit store models/cache/callers, then unit tests.

### 2026-06-05T17:55:00Z - Implementation Verified

- Intent: complete the no-wipe retained Thread Detail reopen fix and prove it against real simulator UI state.
- Changed: store lifecycle, retained cache, Dock/Archive callers, Session Detail detach behavior, controlled simulator scenario/proof harness, tests, and coverage docs.
- Proof:
  - `rtk wc -l CodexDock/State/ThreadDetailStore.swift` -> `999`.
  - `rtk swift test --filter ThreadDetailStoreTests` -> passed.
  - `rtk swift test --filter ThreadDetailStoreCacheTests` -> passed.
  - `rtk swift test --filter ThreadDetailScreenStoreTests` -> passed.
  - `rtk npm run test:relay` -> passed.
  - `rtk npm run contract:check` -> passed.
  - `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-reopen-retains-content` -> passed; report `/tmp/codex-client/sim-ui-audit-20260605T172611Z/simulator-ui-sync.json`.
  - `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` -> passed; aggregate `/tmp/codex-client/sim-ui-controlled-matrix-run-20260605T172812Z/controlled-simulator-matrix.json`.
- Review: plan exit criteria satisfied. Production relay protocol did not change; deployment still proceeds because requested.
