# Codex Dock Live Update Architecture Implementation Worklog

Plan: `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
Status: active implementation evidence, not final completion
Updated: 2026-06-02

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

## Current Remaining Gates

These are still required before this goal can be called complete:

- `rtk npm run contract:check`
- `rtk npm run test:relay`
- `rtk swift test --filter ProjectionReducerTests`
- `rtk swift test --filter ProjectionRuntimeTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `SIM_UI_CONTROLLED_MATRIX_PASSES=2 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 MAX_UI_LAG_MS=2000 rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
- `rtk make sim-ui-dump SIM='iPhone 17'`
- `rtk make app-test SIM='iPhone 17'`
- strict `$fresh-consult` through Cursor Agent `composer-2.5-fast` with no
  pass-with-notes completion.

## Known Current Status

The implementation has moved substantially toward the no-side-door target, but
completion is not yet proven. The remaining work is to finish any audit cleanup,
run the full proof gates, write the authoritative implementation audit block in
the plan, and satisfy a strict fresh consult.
