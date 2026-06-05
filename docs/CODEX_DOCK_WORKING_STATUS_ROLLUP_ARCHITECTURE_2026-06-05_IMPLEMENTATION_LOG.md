# Implementation Log: Working Status Rollup

Plan:
`docs/CODEX_DOCK_WORKING_STATUS_ROLLUP_ARCHITECTURE_2026-06-05.md`

Audit:
`docs/CODEX_DOCK_WORKING_STATUS_ROLLUP_ARCHITECTURE_2026-06-05_PLAN_AUDIT.md`

## Active Scope

Implement relay-owned hidden spawned/private child status rollup onto visible
parent Dock cards. Keep Swift unchanged.

## Code Anchors

- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-state-views.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-live-status-cache.mjs`
- `scripts/dock-relay-card-contract.test.mjs`
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.mjs`
- `Makefile`

## Progress

- 2026-06-05: Plan and audit sidecar created and marked ready.
- 2026-06-05: Implementation started. First slice is relay contract behavior:
  hidden child activity facts preserved, parent status folded before card write,
  child rows still filtered.
- 2026-06-05: Relay rollup implemented. Hidden spawned/private children now
  produce rollup facts keyed by visible parent thread ID; Dock cards keep the
  visible parent identity and session ID while inheriting the child's active or
  approval status.
- 2026-06-05: Controlled simulator scenario
  `spawned-private-child-status-rollup` added to the required matrix.
- 2026-06-05: Full matrix exposed a fixture-only gap in
  `current-work-visible`: the fixture changed `thread/loaded/list` dynamically
  but did not expose a live endpoint for the relay to poll. The scenario now
  registers its fixture WebSocket as a live endpoint only for that case.

## Proof Ledger

- Passed: `node --check scripts/dock-relay-state-views.mjs`
- Passed: `node --check scripts/dock-relay-thread-data.mjs`
- Passed: `node --check scripts/dock-relay-state-engine.mjs`
- Passed: `node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
- Passed: `rtk node --test scripts/dock-relay-card-contract.test.mjs`
  - 25 tests, 25 pass, 0 fail.
- Passed: `rtk node --test scripts/dock-relay-state-subscriptions.test.mjs`
  - 13 tests, 13 pass, 0 fail.
- Passed:
  `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs scripts/dock-relay-controlled-simulator-matrix.test.mjs`
  - 44 tests, 44 pass, 0 fail.
- Passed: `rtk npm run test:relay`
  - 234 tests, 234 pass, 0 fail.
- Passed: `rtk npm run contract:check`
  - Projection contract fixtures and generated Dock DTO are current.
  - Validated 5 proof schemas and 5 canonical samples.
- Not available: `rtk npm run test:docs`
  - `package.json` has no `test:docs` script.
- Passed headless relay scenario:
  `rtk node scripts/dock-relay-controlled-simulator-fixture.mjs --scenario spawned-private-child-status-rollup`
  - Parent `sim-rollup-parent` reported `running`.
  - Hidden child `sim-rollup-private-child` stayed absent.
- Passed focused simulator proof:
  `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=spawned-private-child-status-rollup`
  - 12 of 12 scored UI samples passed.
  - 1 of 1 scenario transitions passed.
  - 0 failures.
  - Observed UI lag: 0 ms.
- Passed focused regression proof:
  `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=current-work-visible`
  - 12 of 12 scored UI samples passed.
  - 2 of 2 scenario transitions passed.
  - 0 failures.
  - Observed UI lag: 1476 ms, under the 2000 ms budget.
- Passed focused regression proof:
  `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=archive-toggle`
  - 12 of 12 scored UI samples passed.
  - 2 of 2 scenario transitions passed.
  - 0 failures.
- Passed full controlled simulator matrix:
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`
  - Report root:
    `/tmp/codex-client/sim-ui-controlled-matrix-run-20260605T160457Z`
  - Matrix JSON:
    `/tmp/codex-client/sim-ui-controlled-matrix-run-20260605T160457Z/controlled-simulator-matrix.json`
  - Matrix Markdown:
    `/tmp/codex-client/sim-ui-controlled-matrix-run-20260605T160457Z/controlled-simulator-matrix.md`
  - 40 reports.
  - 20 required scenarios.
  - 20 passing scenarios.
  - 0 missing scenarios.
  - 0 failed scenarios.
  - 0 findings.
  - Max observed UI lag: 440 ms, under the 2000 ms budget.
- Passed: `git diff --check`
