# Remove Duplicate Idle Filter Implementation Log

Plan: user-pasted plan, "Remove Duplicate Idle Filtering"
Audit log: none
Active scope: remove client-side `showsIdle` / hidden-idle behavior; do not change relay status semantics
Last updated: 2026-05-31 17:29 America/Chicago

## Resume Snapshot

- Current state: implementation complete; requested checks passed after one simulator rerun.
- Next useful move: manual check on the iPhone 17 simulator if desired.
- Do not redo unless stale: `rg` confirmed the live code touchpoints are under `CodexDock/`, `CodexDockTests/`, `CodexDockUITests/`, and `README.md`.
- Known blockers: none.
- Native subagents used or useful next: prior planning turn used read-only Composer consults; no new subagents needed for implementation.

## Scope Ledger

| Item | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- |
| Remove duplicate idle visibility state | Complete | `CodexDock/Dock/DockModels.swift` | Swift tests | Reviewed |
| Collapse projection to one status-aware filter path | Complete | `CodexDock/State/DockCardProjection.swift` | Swift tests | Reviewed |
| Remove idle visibility UI and copy | Complete | `CodexDock/Features/Dock/` | app-test | Reviewed |
| Update tests and README | Complete | `CodexDockTests/`, `CodexDockUITests/`, `README.md` | Swift tests + app-test | Reviewed |

## Code Read Ledger

| Area | Files/symbols read | Why relevant | Fresh until | Notes |
| --- | --- | --- | --- | --- |
| Filter model and projection | `DockFilterState`, `DockCardProjectionProjector` | Owns hidden idle behavior | Any touched projection/model code changes | `showsIdle` is the duplicate gate. |
| Dock UI | `DockFilterSurfaceView`, `DockGroupRows`, `DockView`, `AutomationID` | Owns visible toggle/copy/a11y hooks | Any Dock UI code changes | Status chip already exposes `Idle`. |
| Tests/docs | Projection tests, Dock store tests, UI smoke test, `README.md` | Must encode new behavior | Any test/doc changes | Old assertions expect `Idle hidden`. |

## Proof Freshness Ledger

| Proof | Scope covered | Result/context | Fresh until | Rerun trigger |
| --- | --- | --- | --- | --- |
| `rtk swift test --filter DockStoreTestsProjection` | Projection behavior | Passed 24 tests | Model/projection/tests unchanged | Touching Dock projection/model/tests |
| `rtk swift test --filter DockStoreTests` | Dock store integration | Passed 53 selected tests | Dock store/projection unchanged | Touching Dock store/projection/tests |
| `rtk swift test --filter ThreadDetailStoreTests.testHoldAndTapVoiceControlsDoNotCreateDuplicateStreams` | App-test failure triage | Passed 1 test | Voice test unchanged | Only rerun if app-test fails there again |
| `rtk make app-test SIM='iPhone 17'` | iPhone 17 simulator build/test path | First run failed in unrelated voice test; second run passed | App target/UI test/config unchanged | Touching app target/UI tests/project config |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| `showsIdle` | Deleted | Deleted | Complete | `DockFilterState` |
| `hiddenIdle*` projection plumbing | Deleted | Deleted | Complete | `DockCardProjection` |
| `Show idle` toggle | Deleted | Deleted | Complete | `DockFilterSurfaceView` |
| `filterIdleToggle` automation ID | Deleted | Deleted | Complete | `AutomationID.Dock` |

## Pass Notes

### 2026-05-31 - Start Implementation

- Intent: implement the pasted plan exactly, without relay/cache/persistence changes.
- Changed: log created.
- Read: model/projection/UI/test touchpoints.
- Proof: pending requested checks.
- Review: pending after edits.
- Next: remove production `showsIdle` path.

### 2026-05-31 - Complete Implementation

- Intent: remove the duplicate idle visibility filter and keep Status as the only idle filter.
- Changed: deleted `showsIdle`, hidden-idle projection counts/copy, filter toggle, automation ID, and README stale filter description; updated projection/UI tests.
- Read: final grep over `CodexDock` and `README.md` found no `showsIdle`, `hiddenIdle`, `idleHidden`, `filterIdleToggle`, `Show idle`, `Idle hidden`, or `Idle shown`.
- Proof: `DockStoreTestsProjection` passed 24 tests; `DockStoreTests` passed 53 selected tests; `ThreadDetailStoreTests.testHoldAndTapVoiceControlsDoNotCreateDuplicateStreams` passed directly after the first app-test run failed there; second `rtk make app-test SIM='iPhone 17'` passed.
- Review: behavior now has one filter path; idle remains a normal status facet.
- Next: none for implementation.
