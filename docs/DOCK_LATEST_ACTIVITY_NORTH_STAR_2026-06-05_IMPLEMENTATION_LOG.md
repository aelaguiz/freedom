# Dock Latest Activity Implementation Log

Date: 2026-06-05

Plan:

```text
docs/DOCK_LATEST_ACTIVITY_NORTH_STAR_2026-06-05.md
```

Audit:

```text
docs/DOCK_LATEST_ACTIVITY_NORTH_STAR_2026-06-05_PLAN_AUDIT.md
```

## Status

- Plan audit: ready
- Implementation: complete
- Verification: focused relay tests, full relay tests, and full controlled
  simulator matrix passed

## Work Log

- Created an audited implementation plan with one relay-owned summary path.
- Added `scripts/dock-relay-thread-summary.mjs` as the pure extractor.
- Removed the dormant `scripts/dock-relay-thread-summary-cache.mjs` cache path.
- Updated `readNewestTurnActivity` to keep latest message text from the same
  bounded turn pages used for activity proof.
- Updated canonical Dock rows to publish proven latest text through existing
  `displaySummary` / `summarySource` card fields.
- Added helper and card-contract tests for latest-summary projection.
- Updated the controlled simulator `thread-activity` fixture to prove stale
  preview text is replaced by latest turn item text.
- Fixed the simulator fixture response shape so fixture-only `turnItems` stay
  internal and do not leak into public `thread/list` / `thread/read` rows.

## Verification So Far

```text
rtk node --test scripts/dock-relay-thread-summary.test.mjs scripts/dock-relay-card-contract.test.mjs
pass: 30
```

```text
rtk node --test scripts/dock-relay-thread-summary.test.mjs scripts/dock-relay-card-contract.test.mjs scripts/dock-relay-controlled-simulator-fixture.test.mjs scripts/dock-relay-controlled-simulator-matrix.test.mjs
pass: 75
```

```text
rtk npm run test:relay
pass: 241
```

```text
rtk npm test
contract:check passed
test:relay pass: 241
test:host-service pass: 37
```

```text
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=thread-activity
ok: true
uiSampleCount: 12
relaySampleCount: 3
scenarioTransitionFailures: 0
displayedRowChecks: 33
dockVisibleOrderChecks: 12
dockSweepOrderChecks: 1
observedLagMs: 0
```

```text
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
ok: true
reports: 42
requiredScenarioCount: 21
passingScenarioCount: 21
failedScenarioCount: 0
missingScenarioCount: 0
maxObservedUiLagMs: 788
uiLagBudgetMs: 2000
findings: 0
report: /tmp/codex-client/sim-ui-controlled-matrix-run-20260605T193445Z/controlled-simulator-matrix.json
```

First full matrix attempt exposed a fixture hygiene bug, not a product
regression:

```text
archive-toggle failed because fixture-only turnItems leaked into public report fields.
Fixed by stripping turnItems from public fixture thread/list and thread/read rows.
```

`package.json` currently has no `test:docs` script:

```text
rtk npm run test:docs
npm error Missing script: "test:docs"
```

## Strict Code Quality Review

`$thermo-nuclear-code-quality-review` pass result: no blocking structural
issues found.

- The change deletes the dormant `ThreadSummaryCache` path instead of adding a
  second summary source.
- Latest-summary extraction lives in one pure helper and is called only from
  the existing activity proof path.
- No mass detail subscription, transcript cache, Swift side route, or new
  client-facing stream was added.
- `scripts/dock-relay-card-contract.test.mjs` and
  `scripts/dock-relay-controlled-simulator-fixture.mjs` were already above
  1000 lines before this change. The new assertions stayed in those files
  because they are the current owners for card-contract and controlled-sim
  scenario proof; splitting them is a larger test-architecture cleanup.
