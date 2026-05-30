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
- Fixed a discovered `/selftestz` hang where the Dock session snapshot had no
  timeout. Self-test route probes now use `SELFTEST_ROUTE_TIMEOUT_MS`.
- Fixed a discovered route-health blind spot where a hung in-flight operation
  could stay `unknown`. Active app routes now fail after
  `OBSERVABILITY_ACTIVE_ROUTE_TIMEOUT_MS`.
- Updated `README.md` to make `/readyz` process-only and route health the app
  path truth. Marked the 2026-05-28 logging plan as superseded for route-health
  diagnostics.

## Verification

- `rtk npm run test:relay`: passed, 113 tests.
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

- None for the observability implementation.

## 2026-05-30 Deployment Verification

- Committed and pushed final relay observability code through
  `b7d13be Surface stuck relay route operations`.
- Local `Amir-M5` relay restarted from `b7d13be`.
  - `rtk make relay-doctor`: passed.
  - `/statusz`: 37 routes, no app-critical failures.
  - `/selftestz`: passed, 6 safe diagnostic routes.
  - Relay debug bundle:
    `/tmp/codex-client/local-relay-debug-bundle-20260530T143900Z.json`.
- `home` repo fast-forwarded to `b7d13be` and `systemd-user` services restarted.
  - `readyz`, `statusz`, and `routesz` answer from `http://100.66.11.7:4510`.
  - `/statusz`: 37 routes.
  - `/selftestz`: reports `dock/subscribe self-test timed out after 5000ms`.
  - A real WebSocket `dock/subscribe` probe to
    `ws://home.fairy-salmon.ts.net:4510` timed out after 35002ms.
  - `/statusz`, `/tracesz/recent`, and on-disk
    `.codex-dock/observability/route-health.json` now agree that
    `dock/subscribe` is app-critical failed with
    `failed:in-flight-timeout`.
  - `rtk make host-service-doctor ...` now fails for the right reason:
    `relay-statusz app-critical route dock/subscribe is failed`.
- Multi-host compare artifact:
  `/tmp/codex-client/relay-host-compare-20260530T143800Z.json`.
  - `amir-m5.fairy-salmon.ts.net:4510`: ready, 37 routes, no app-critical
    failures, self-test passed.
  - `home.fairy-salmon.ts.net:4510`: ready, 37 routes, app-critical
    `dock/subscribe` failure, self-test timed out.
