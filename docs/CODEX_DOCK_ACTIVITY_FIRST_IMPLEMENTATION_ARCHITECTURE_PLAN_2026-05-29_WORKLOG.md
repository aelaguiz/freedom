# Activity-First Dock Implementation Worklog

Plan: `docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md`

This worklog records implementation evidence only. The plan remains the source of truth for scope, phase obligations, and acceptance criteria.

## 2026-05-29 - Implementation Pass

- Replaced the old Dock first screen with the activity-first path: `Newest`, `Host`, `Branch`, one `Filters` surface, full-width search, row-level host/repo/branch identity, and compact connectivity.
- Removed the visible primary `Needs me` workflow bucket and removed `Limited` from Dock status vocabulary.
- Moved Dock list interpretation into `DockSessionProjection`.
- Split archive grouping into `ArchiveSessionProjector` so Archive does not depend on Dock projection.
- Added simulator-observable automation IDs and UI smoke coverage for lenses, filters, Relay settings, and row-to-detail navigation.
- Repaired implementation-audit findings found during continuation:
  - Active filter summary now names host, branch, status, repo, source, idle, search, and partial state instead of collapsing constraints into `N filters`.
  - Filter surface status/source options are present-aware while preserving selected values.
  - Repo filter exposes an explicit `Any` chip.
  - Mixed online-plus-checking connectivity now rolls up as partial count state so the global indicator can show `Online 1/2`.
- Repaired the thermonuclear review finding in the shared Dock test host helper: tests no longer accept a fake display-name parameter or an unused fake host ID when URL owns host identity.

## Proof Ledger

- `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md`
  - Result: `READY next=implement-loop`
- `rtk swift test --filter DockStoreTests`
  - Latest result after continuation repairs: passed, `33` tests, `0` failures.
- `rtk swift test --filter AppConnectivityStoreTests`
  - Latest result after continuation repairs: passed, `13` tests, `0` failures.
- `rtk swift test --filter DockConfigurationTests`
  - Result: passed, `29` tests, `0` failures.
- `rtk swift test --filter AutomationIDTests`
  - Result: passed, `3` tests, `0` failures.
- `rtk git diff --check`
  - Result: passed with no output.
- Old-Dock-vocabulary scans
  - Result: no live `DockTabID`, `DockTabViewModel`, old sort/filter/idle controls, `DockRowStatusKind.failed`, visible `Limited`, or primary `Needs me` path remains in `CodexDock`, `CodexDockTests`, `CodexDockUITests`, or `README.md`.
  - Expected remaining matches: README says `Not loaded` does not mean rate limited; UI/tests contain negative assertions for `Limited` and `Needs me`.
- `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`
  - Result: passed.
  - Result bundle: `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_13-43-11--0500.xcresult`.
  - Simulator: `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`, iOS Simulator `26.5`, OS build `23F77`.
  - Summary: `233` total tests, `228` passed, `5` skipped, `0` failed.
  - Dock UI smoke tests passed:
    - `testDockLensesAndFiltersAreDrivableInSimulator()`
    - `testDockRowOpensSessionDetailByIdentifierWhenRowsExist()`
    - `testDockScreenExposesControlsAndConnectivityByIdentifier()`
    - `testRelaySettingsFormIsDrivableByIdentifier()`
- Plan-audit implementation check
  - Verdict: approve, no open implementation findings.
- Thermonuclear code-quality review
  - Verdict: approve, no open blockers after resolving the misleading test-helper fixture.

## Environment Notes

- `SIM='iPhone 17'` is ambiguous on this Mac because two simulator records match that name. Use the booted iPhone 17 UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` for final simulator proof unless the simulator set changes.
- `rtk make app-test ...` foregrounds Simulator and can steal macOS focus. Do not rerun it casually after a passing proof; rerun only after visible UI/test-hook edits, simulator-proof repair work, or an explicit request.

## Open Code Blockers

None.
