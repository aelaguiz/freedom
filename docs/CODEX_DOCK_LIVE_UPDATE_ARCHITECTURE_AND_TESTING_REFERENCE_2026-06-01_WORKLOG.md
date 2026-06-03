# Codex Dock Live Update Architecture Implementation Worklog

Plan: `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
Status: active implementation evidence, not final completion
Updated: 2026-06-03

This worklog is execution evidence only. The plan above is the authoritative
architecture and checklist. The older 2026-06-01 phase ledger was removed from
this file because it described a superseded partial architecture as complete;
Git keeps that history.

## Current Cutover Evidence

- `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py status --doc docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
  reported `READY next=implement-loop`.
- `e9444d6 Add shared projection reducer contract` added the shared projection
  contract/reducer foundation.
- `4b65e8b Add thread detail projection reconciler` moved Thread Detail onto
  the projection reconciler path.
- `0fc85bd Continue projection runtime cutover` continued migration toward the
  shared runtime.
- `d284661 Finish projection runtime cutover` deleted
  `CodexDock/State/ThreadCardStreamLifecycle.swift`,
  `CodexDock/State/ThreadCardTable.swift`, and old manual stream fixture names,
  and migrated Dock/Archive/runtime tests to the reconciler path.
- `3ae2a19 Tighten projection witness proof path` removed the typed Swift
  `threadDetailRead` client helper, stopped `thread/detail/read` from seeding
  projection witness truth, and moved live-filter truth sampling to
  `projection/witness/read`.
- `e888676 Remove legacy thread detail test side doors` removed old raw Thread
  Detail fixture paths from tests.
- `d921f9a Finish projected thread detail test cleanup` removed
  `LegacyThreadEventFixtureNormalizer.swift` and
  `ThreadEventNormalizerTests.swift`; projected rows/events are now the test
  fixture path.
- `be5a786 Tighten live update proof contracts` switched proof route evidence to
  a strict allow-list, removed legacy `expectedMessage*` /
  `expectedProjection*` proof fields, and kept `thread/detail/read` only as
  rejected failure evidence.

## Current Source Truth

- `CodexDock/Projection/ProjectionReducer.swift` owns projection identity,
  ordering, revision, stream contract validation, page catch-up, live mutation,
  heartbeat, and `resyncRequired` handling.
- `CodexDock/Projection/StreamReconciler.swift` owns subscribe, reconnect,
  manual refresh, foreground resume, heartbeat timeout, sequence-gap recovery,
  command-completed invalidation, bounded buffering, catch-up, stale/offline,
  and close behavior for one projection view key.
- `CodexDock/State/ThreadDetailStore.swift`,
  `CodexDock/State/DockStore.swift`, and `CodexDock/State/ArchiveStore.swift`
  are now adapters over `StreamReconciler` output plus screen-local state.
- `scripts/codex-dock-live-filter-truth.mjs` reads
  `projection/witness/read` and fails closed when retained witness envelopes
  are absent or not byte-equivalent to downstream.
- `scripts/proof-report-contracts.mjs` rejects `thread/detail/read` as passing
  live-update proof evidence.
- `Makefile` defaults `sim-ui-controlled-matrix-proof` to two passes,
  checkpoint sweep, `MAX_UI_LAG_MS=2000`, and the full required controlled
  scenario set.
- `README.md` documents `rtk make sim-ui-dump SIM='iPhone 17'` as the canonical
  structured current-screen dump and `rtk make sim-ui-controlled-matrix-proof
  SIM='iPhone 17'` as the over-time simulator proof.

## Verification Run So Far

- `node --check scripts/codex-dock-live-filter-truth.mjs` passed.
- `node --check scripts/codex-dock-live-filter-compare.mjs` passed.
- `node --check scripts/dock-relay.mjs` passed.
- `rtk npm exec -- node --test scripts/dock-relay-card-contract.test.mjs scripts/codex-dock-live-filter-truth.test.mjs scripts/codex-dock-live-filter-compare.test.mjs scripts/dock-relay-observability.test.mjs`
  passed with 29 tests.
- `rtk npm exec -- node --test scripts/dock-relay-card-contract.test.mjs scripts/codex-dock-live-filter-truth.test.mjs scripts/codex-dock-live-filter-compare.test.mjs`
  passed with 21 tests.
- `rtk swift test --filter AppServerClientTests` passed 51 tests, with 5
  opt-in real-host tests skipped by environment.
- `git diff --check` passed before commit `3ae2a19`.
- `rtk npm run contract:check` passed on 2026-06-03:
  projection contract fixtures and generated Dock DTO were current, and 5 proof
  schemas plus 5 canonical samples validated.
- `rtk npm run test:relay` passed on 2026-06-03 with 165 tests.
- `rtk swift test --filter ProjectionReducerTests` passed on 2026-06-03 with 14
  tests.
- `rtk swift test --filter ProjectionRuntimeTests` passed on 2026-06-03 with 13
  tests.
- `rtk swift test --filter DockStoreTests` passed on 2026-06-03 with 54 tests.
- `rtk swift test --filter ThreadDetailStoreTests` passed on 2026-06-03 with 61
  tests.
- `rtk swift test --filter AppServerClientTests` passed on 2026-06-03 with 51
  tests and 5 opt-in real-host tests skipped by environment.
- `rtk swift test --filter AppConnectivityStoreTests` passed on 2026-06-03 with
  17 tests.
- `rtk swift test --filter SystemHealthProjectorTests` passed on 2026-06-03 with
  5 tests.
- `rtk swift test --filter DockDataEngineTests` passed on 2026-06-03 with 2
  tests.
- `rtk git diff --check` passed on 2026-06-03 after the documentation truth
  update.

## Current Remaining Gates

These are still required before this goal can be called complete:

- `SIM_UI_CONTROLLED_MATRIX_PASSES=2 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 MAX_UI_LAG_MS=2000 rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
- `rtk make sim-ui-dump SIM='iPhone 17'`
- `rtk make app-test SIM='iPhone 17'`
- authoritative `arch_skill:block:implementation_audit` in the plan with
  current repo evidence.
- strict `$fresh-consult` through Cursor Agent `composer-2.5-fast` with no
  pass-with-notes completion.

## Known Current Status

The implementation has moved substantially toward the no-side-door target, but
completion is not yet proven. The remaining work is to finish any audit cleanup,
run the full proof gates, write the authoritative implementation audit block in
the plan, and satisfy a strict fresh consult.
