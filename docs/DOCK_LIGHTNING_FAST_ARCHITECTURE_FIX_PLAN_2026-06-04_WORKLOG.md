---
title: "Codex Dock - Lightning-Fast Dock Rendering - Implementation Worklog"
date: 2026-06-04
status: active
plan: docs/DOCK_LIGHTNING_FAST_ARCHITECTURE_FIX_PLAN_2026-06-04.md
---

# Worklog

## 2026-06-04 - Implementation status

Implemented the accepted architecture from
`docs/DOCK_LIGHTNING_FAST_ARCHITECTURE_FIX_PLAN_2026-06-04.md`.

Code changes:

- `DockScreenStore` gates equal `(DockSnapshot, DockProjectionOptions)` before
  revision bumps, projection, or coalesced render work.
- `DockStore` skips unchanged loaded snapshot publishes and treats client-side
  thread renames as optimistic, non-blocking UI updates.
- `DockCardProjection` owns the projected row set and automation rows.
- `DockAutomationSnapshotStore` writes the test-only JSON row oracle and prunes
  old snapshots.
- `DockView` root accessibility no longer carries `rowValues=`.
- UI proof reads JSON automation snapshots instead of reconstructing Dock row
  truth from root accessibility text.
- `Makefile` simulator proof targets annotate the UI sync config with simulator
  UDID, app bundle id, and app data container through
  `scripts/sim-ui-sync-config.mjs`.
- `CodexDockDisplayedSyncProofTests` captures one baseline Dock sample before
  controlled fixtures mutate state.

## 2026-06-04 - Plan sign-off

`$fresh-consult composer-2.5-fast` accepted the full arch-step plan.

Evidence:

- `/tmp/fresh-consult/dock-lightning-fast-arch-plan-20260604T211426Z-gpvW9n/final.txt`
- Verdict: `pass`
- Blocking findings: `none`
- Confidence: `high`

## 2026-06-04 - Simulator and local proof

Passed checks:

- `rtk xcodegen generate --spec project.yml`
- `rtk swift test --filter DockScreenStoreTests`
- `rtk swift test --filter DockRenderProjectorTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AppServerThreadCardStreamClientTests`
- `rtk swift test --filter RenderCoalescerTests`
- `rtk npm run test:relay`
- `rtk git diff --check`
- `rtk node scripts/sim-ui-sync-config.mjs annotate --path <config.json>
  --simulator-udid <udid> --app-bundle-id <bundle-id> --app-data-container
  <path>`
- `rtk make app-test SIM='iPhone 17'
  APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled'`
- `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17'
  SIM_UI_SYNC_SCENARIO='mutation-ack-projection-refresh-failure'
  SIM_UI_SYNC_DURATION_MS=10000 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500
  SIM_UI_SYNC_CHECKPOINT_SWEEP=1`
- `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17'
  SIM_UI_SYNC_SCENARIO='spawn-edge' SIM_UI_SYNC_DURATION_MS=10000
  SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_CHECKPOINT_SWEEP=1`
- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`

Controlled matrix proof:

- JSON:
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260604T221252Z/controlled-simulator-matrix.json`
- Markdown:
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260604T221252Z/controlled-simulator-matrix.md`
- Reports: `36`
- Required scenarios: `18`
- Passing scenarios: `18`
- Failed scenarios: `0`
- Missing scenarios: `0`
- Max observed UI lag: `446 ms`
- UI lag budget: `2000 ms`

Performance proof:

```text
perf event=dock.card_projection.project all_pinned_ms=0 all_pinned_rows=0 automation_rows=1248 body_ms=1 body_rows=1248 checking_hosts=0 duration_ms=8 facets_ms=4 filter_ms=1 filtered_rows=1248 filters=0 groups=0 groups_ms=0 hosts=2 lens=newest partial=false pinned_ms=0 pinned_rows=0 rows=1248 search=false search_ms=1 searched_rows=1248 summary_ms=0 visible_ms=1 visible_rows=1248
perf event=dock.main_publish automation_snapshot=true duration_ms=30 groups=0 hosts=2 pinned_rows=0 revision=9 rows=1248 visible_rows=1248
perf event=dock.accessibility_value.built duration_ms=0 encoded_length=289 revision=9 rows=1248 visible_rows=1248
perf event=dock.store.publish_snapshot context=handleReconcilerSnapshot duration_ms=9 hosts=2 model_ms=9 partial=false pending_rename_ms=0 pending_renames=0 published=true rows=1248 screen_publish_ms=0
perf event=dock.store.publish_snapshot context=handleReconcilerSnapshot duration_ms=10 hosts=2 model_ms=9 partial=false pending_rename_ms=0 pending_renames=0 published=false rows=1248 screen_publish_ms=1
```

The previous measured offender was a `469,211` character root accessibility
`rowValues=` payload taking `20-22 ms` to rebuild around `1,247` rows. The
tested simulator path now has a bounded root accessibility value and JSON row
proof.

## 2026-06-04 - Physical phone testing

Physical phone testing and installation are intentionally stopped by user
instruction. Completion evidence for this run is simulator and local relay
evidence only.

## 2026-06-04 - Thermo-nuclear review

Result: passed after one proof-harness fix.

Finding:

- The new baseline Dock sample reused `sampleIndex` as the Dock lens rotation
  counter, so the first post-ready loop sample could skip the first configured
  lens when multiple lenses were configured.

Fix:

- `CodexDockDisplayedSyncProofTests` now uses a separate `lensIndex`, so sample
  numbering stays monotonic and lens rotation still starts with the first
  configured lens after the ready file is written.

Post-fix proof:

- `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` passed with `36`
  reports, `18` passing required scenarios, `0` failures, and max observed UI
  lag `446 ms`.
- `rtk make app-test SIM='iPhone 17'
  APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled'`
  passed. Result bundle:
  `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.06.04_17-34-22--0500.xcresult`.

## 2026-06-04 - Remaining rollout

Remaining work before marking this worklog complete:

- Commit and push explicit touched paths.
- Pull the pushed branch into the `home` deployment checkout.
- Restart and verify the Mac/local relay and `home` relay.
