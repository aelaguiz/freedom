# Codex Dock Observability Architecture Worklog

## 2026-05-30 Implementation Pass

- Added the relay observability contract and route-health owner:
  `scripts/dock-relay-observability-contract.mjs` and
  `scripts/dock-relay-observability.mjs`.
- Wired relay dispatch, Dock aggregation, status, metrics, debug, traces,
  self-test, bundle, host-service doctor, and CLI diagnostics through the
  route-health spine.
- Added `relay-debug-bundle`, `relay-host-compare`, `sim-debug-bundle`, and
  `device-debug-bundle` Makefile targets.
- Added the Swift observability mirror:
  `CodexDock/Diagnostics/ObservabilityContract.swift`,
  `ClientObservabilityStore.swift`, and `RelayDiagnosticsClient.swift`.
- Wired AppServer request tracing, Dock stream subscribe/resync, thread detail,
  archive/unarchive, realtime transcription, route diagnostics fetch, and the
  global connectivity detail sheet.
- Fixed a discovered blind spot where the generic log sanitizer capped
  diagnostic route arrays. `/statusz`, `/metricsz`, and relay bundles now keep
  complete route-health arrays.
- Updated `README.md` to make `/readyz` process-only and route health the app
  path truth. Marked the 2026-05-28 logging plan as superseded for route-health
  diagnostics.

## Verification

- `rtk npm run test:relay`: passed, 111 tests.
- `rtk swift test --filter AppServerClientTests`: passed, 55 tests, 5 skipped.
- `rtk swift test --filter DockStoreTests`: passed, 48 tests.
- `rtk swift test --filter ThreadDetailStoreTests`: passed, 52 tests.
- `rtk swift test --filter AppConnectivityStoreTests`: passed, 15 tests.
- `rtk swift test --filter DiagnosticsLoggingTests`: passed, 7 tests.
- `rtk make sim-debug-bundle SIM='iPhone 14'`: blocked because the simulator app
  data container does not exist. Exact failure:
  `missing simulator app data container for iPhone 14 (com.aelaguiz.CodexDockApp); install the app first with: rtk make app SIM='iPhone 14'`.
- `rtk make app-test SIM='iPhone 17'`: built and ran generated-project tests,
  but failed one unrelated existing swipe/pinned UI smoke. Exact failing test:
  `CodexDockAutomationSmokeTests.testScriptedDockSwipePinPersistsAcrossLensesRefreshRelaunchAndUnpin()`;
  exact assertion: `Inline pinned row did not unpin after swipe.`
- ArcStep implementation audit: `Verdict (code): COMPLETE`; code blockers:
  none.
- Fresh Cursor Agent Composer 2.5 Fast consult: `VERDICT: pass-with-notes`;
  blocking findings: none. Run directory:
  `/tmp/fresh-consult/codex-dock-observability-20260530T142328Z-dx3gWc`.

## Remaining Operational Proof

- Commit the observability change set with explicit paths only.
- Restart and verify the local relay from the committed code.
- Push/pull/deploy as needed, then restart and verify the home relay from the
  committed code.
