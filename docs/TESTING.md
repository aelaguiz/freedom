# Codex Dock Testing

Date: 2026-06-05
Status: current-use guide
Related plan: `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`

## Direct Answer

Use this file when you need to know what test or proof command to run today.
`Makefile` remains the runnable source of truth. If this file disagrees with
`Makefile`, `package.json`, `Package.swift`, `project.yml`, or code, the
runnable source wins.

The proposed future umbrella targets `rtk make test-smoke`,
`rtk make test-full`, and `rtk make test-overtime` do not exist yet. They are
specified in `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`.

## Current Commands

Fast Node relay and contract checks:

```bash
rtk npm test
rtk npm run test:relay
rtk npm run test:host-service
rtk npm run test:docs
rtk npm run contract:check
```

Swift package checks:

```bash
rtk swift test
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

Generated Xcode project and simulator checks:

```bash
rtk xcodegen generate --spec project.yml
rtk make app SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
rtk make sim-ui-dump SIM='iPhone 17'
rtk make sim-ui-sync-proof SIM='iPhone 17'
rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
```

Focused simulator proof commands:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-history-request
rtk make sim-ui-controlled-matrix-verify SIM_UI_MATRIX_REPORT_DIRS='<space-separated report dirs>'
rtk make sim-ui-client-rename-proof SIM='iPhone 17'
rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'
```

Physical device checks:

```bash
rtk make iphone-17-pro
rtk make iphone-14
rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>
rtk make device-install-all
rtk make device-config-verify DEVICE=<device-udid>
rtk make device-config-verify-all
```

Service status and diagnostics:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make relay-doctor
rtk make sim-logs SIM='iPhone 17'
rtk make dock-relay-logs
```

## Which Check To Run

Use the smallest relevant check first:

- Relay changes under `scripts/dock-relay*.mjs`: run `rtk npm run test:relay`.
- Contract, proof schema, or report shape changes: run `rtk npm run contract:check`.
- Bug docs, controlled scenario ids, or coverage-ledger changes: run `rtk npm run test:docs`.
- JSON-RPC, DTO, app-server client, or transcription-client changes: start with `rtk swift test --filter AppServerClientTests`.
- Dock, host registry, relay bootstrap, archive, local metadata, or host settings changes: start with `rtk swift test --filter DockStoreTests`.
- Thread detail, live events, composer, voice transcript handling, or request-card responses: start with `rtk swift test --filter ThreadDetailStoreTests`.
- App target, Info.plist, assets, project config, simulator launch, or installed UI behavior: use `rtk make app SIM='iPhone 17'` or `rtk make app-test SIM='iPhone 17'`.
- Live update or visible sync claims: run `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` for fixture matrix coverage, and run `rtk make sim-ui-sync-proof SIM='iPhone 17'` or `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` before claiming live Codex data was tested in the simulator.
- Current-screen visibility only: use `rtk make sim-ui-dump SIM='iPhone 17'`, but do not treat it as live-update acceptance proof.
- Physical iPhone behavior: use `rtk make iphone-17-pro`, `rtk make iphone-14`, `rtk make device-install DEVICE=<device-udid>`, or `rtk make device-install-all`.

If only docs changed, read back the changed docs and check
`rtk git status --short`. App tests are not needed for docs-only changes unless
the docs change runnable commands or generated project wiring.

## Proof Rules

Completion proof must use the same route family the user-facing app uses.

Valid completion proof can include:

- `dock/subscribe`, `dock/update`, and `dock/resync` for Dock Home.
- `archive/subscribe`, `archive/update`, and `archive/resync` for Archive.
- `thread/detail/subscribe`, `thread/detail/update`, and `thread/detail/resync` for Thread Detail.
- Structured simulator accessibility samples compared against relay-owned truth over time.
- Physical installed-app proof through the relay-backed host path on `:4510`.

The following are diagnostics only, not completion proof:

- `rtk make sim-ui-dump SIM='iPhone 17'` by itself.
- `/readyz`, `/statusz`, `/routesz`, `/metricsz`, and service status output.
- Logs, debug bundles, screenshots, and screen recordings.
- SwiftUI preview rows, fixture rows, mocks, scripted transports, Unix sockets, and loopback-only WebSockets.
- The old raw authenticated app-server path on `ws://127.0.0.1:4500`.
- Raw app-server detail side-door routes such as `thread/detail/read`, `thread/read`, `thread/turns/list`, or `thread/resume` as app-display proof.
- `projection/witness/read` as app UI evidence. It is proof-only and must not become a production display route.

If physical Mobile MCP reports `WebDriverAgent is not running on device`, stop
retrying physical Mobile MCP for that task. Record that exact blocker and use
simulator/local proof only where it is valid.

## Adding Tests

Pick the smallest owner that matches the behavior.

Swift unit or store behavior:

- Add tests under `CodexDockTests/**`.
- Reuse local fixtures such as `DockStoreTestSupport.swift`,
  `ThreadDetailStoreTestSupport.swift`, and `ThreadCardFixtureSummary.swift`.
- Use the narrowest suite first: `ProjectionReducerTests` for projection laws,
  `ProjectionRuntimeTests` for reconciler recovery, `DockStoreTests*` for Dock
  state, and `ThreadDetailStoreTests*` for Thread Detail state.

Relay behavior:

- Add or extend a `scripts/*.test.mjs` file.
- Reuse `scripts/dock-relay-test-helpers.mjs`.
- Add new relay test files to `package.json` under `test:relay` or
  `test:host-service`.

Contract or proof shape:

- Update schemas and fixtures under `contract/projection/**` or
  `contract/proof/**`.
- Update `scripts/check-projection-contract.mjs` or
  `scripts/check-proof-report-contracts.mjs` only when the contract checker
  itself needs to understand the change.
- Run `rtk npm run contract:check`.

Failure-class coverage:

- Update `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` when adding a root bug doc
  under `docs/bugs/`, adding or removing a controlled simulator scenario,
  changing a proof rule, or discovering a failure class in an audit/worklog that
  should not regress.
- Add root bug docs to the `coverage:bug-docs` marker block.
- Add controlled simulator scenario ids to the `coverage:controlled-scenarios`
  marker block.
- Mark fixture-supported but non-default-matrix scenarios as
  `fixture-only-gap` until they are matrix-gated or deleted.
- Run `rtk npm run test:docs`.

Current over-time simulator scenario:

- Add the scenario to `SUPPORTED_SCENARIOS` in
  `scripts/dock-relay-controlled-simulator-fixture.mjs`.
- Implement the scenario runner in that file.
- Add matrix requirements in
  `scripts/dock-relay-controlled-simulator-matrix.mjs`.
- Add the scenario to `SIM_UI_CONTROLLED_MATRIX_SCENARIOS` and the timing
  `case` block in `Makefile` if it should be part of the default matrix.
- Add or extend Node tests for the fixture, matrix verifier, and proof report
  contract.

This three-place scenario workflow is current reality, not the desired end
state. The unified framework plan requires one scenario catalog so future
over-time scenarios are added in one place.

## Current Gaps

The current framework is strong but not yet unified:

- There is no current `rtk make test-smoke`, `rtk make test-full`, or
  `rtk make test-overtime` target.
- Scenario knowledge is duplicated across the fixture, matrix verifier, and
  Makefile. `file-change-review` is fixture-supported but not currently part
  of the default matrix.
- There is no first-class large/stale/changing corpus generator for the
  900-thread class of failures.
- Pinned-row action survival during live updates, System Health row-window
  honesty, private-runtime detail capability, and large live Thread Detail
  payload regressions are now documented in
  `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`, but they are not all covered by
  the current default matrix.
- The older exhaustive sync docs are narrower references, not the current
  top-level testing entrypoint.

The plan to fix those gaps is
`docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`.
