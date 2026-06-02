# Plan Implementation Log

Plan: `docs/bugs/pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md`
Bug doc: `docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md`
Active scope: whole plan
Last updated: 2026-06-02
Current checkpoint: implementation proof passed; `$fresh-consult` Composer 2.5 Fast approved with non-blocking notes

## Net Status

The plan is implemented in the current dirty worktree.

- Pinned rows now render through the same SwiftUI swipe row path as body rows.
- Pinned reorder is a dedicated SwiftUI sheet.
- Windowed/incomplete list data is modeled as loaded window metadata, not degraded health.
- True degraded health remains explicit and maps to partial connectivity only when the host is actually degraded.
- System Health no longer turns every category degraded from global partial state without route evidence.
- Simulator UI proof now includes `app.configuredBuildNumber` in the proof contract.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Shared status split | Phase 1 | Complete | `DockHostLoadStatus`, `ThreadCardTable` | Passed | Approved with non-blocking notes |
| Connectivity mapping | Phase 2 | Complete | `DockStore`, `ArchiveStore`, `AppConnectivityStore` | Passed | Approved with non-blocking notes |
| System Health | Phase 3 | Complete | `SystemHealthProjector`, `SystemHealthView` | Passed | Approved with non-blocking notes |
| Pinned row surface | Phase 4 | Complete | `DockPinnedViews`, `DockView` | Passed | Approved with non-blocking notes |
| Reorder surface | Phase 5 | Complete | `DockPinnedReorderView`, UI smoke test | Passed | Approved with non-blocking notes |
| Canonical proof | Phase 6 | Complete | proof schema/test changes | Passed | Approved with non-blocking notes |

## Implementation Notes

### Pinned Rows

- Removed the separate pinned normal `UICollectionView` rendering path.
- `DockPinnedRowsList` renders `DockSwipeActionRow`.
- `DockSwipeActionRow` deliberately closes the action only when semantic row identity or pin state changes. It does not close just because live Dock data refreshed.
- `DockPinnedReorderView` is the only reorder surface. It uses SwiftUI `List` native move behavior in an edit-mode sheet.

### Loaded Window vs Degraded Health

- `DockHostLoadStatus.loaded(rowCount:window:)` carries window/completeness metadata.
- `DockHostLoadStatus.degraded(rowCount:message:)` carries true degraded health.
- `DockHostLoadStatus.partial` is removed.
- Incomplete/windowed streams stay loaded for connectivity and System Health unless route diagnostics provide true degradation evidence.

### System Health

- `SystemHealthView` fetches relay diagnostics when opened.
- `SystemHealthProjector` uses route diagnostics as the source of per-feature degradation.
- Without route evidence, categories stay checking/not checked rather than inheriting a broad global partial state.

### UI Smoke Test Hardening

The full iPhone 17 simulator suite exposed test-harness problems while validating the implementation:

- The Dock-to-detail proof could open a very large pinned real thread first. The test now collapses pinned rows before choosing a body row.
- The archive proof first selected a row and then re-queried that row after navigation. That caused stale accessibility snapshot failures. The test now captures the row identifier before tapping.
- Explicit `app.terminate()` calls inside UI smoke tests produced `Test crashed with signal kill` failures. Those calls were removed; `app.launch()` owns launch for each test.
- A stale orphaned `codex app-server` process held `127.0.0.1:4500` after `rtk make app-server-stop`. I killed only that orphaned PID after verifying it owned the port, then restarted services with `rtk make services`.

## Proof Ledger

| Proof | Scope covered | Result/context | Fresh until |
| --- | --- | --- | --- |
| `rtk swift test --filter DockStoreStreamTests` | Dock stream/status split | Passed, 18 tests | Any Dock stream/status edit |
| `rtk swift test --filter AppConnectivityStoreTests` | App connectivity mapping | Passed, 17 tests | Any connectivity edit |
| `rtk swift test --filter ConnectivityDataEngineTests` | Runtime connectivity mapping | Passed, 3 tests | Any connectivity edit |
| `rtk swift test --filter SystemHealthProjectorTests` | System Health route-evidence behavior | Passed, 5 tests | Any System Health edit |
| `rtk swift test --filter ArchiveScreenStoreTests` | Archive screen status projection | Passed, 4 tests | Any archive/status edit |
| `rtk swift test --filter ArchiveDataEngineTests` | Archive data mapping | Passed, 4 tests | Any archive/status edit |
| `rtk swift test --filter ArchiveCleanupStoreTests` | Archive cleanup pinned/status behavior | Passed, 9 tests | Any archive cleanup edit |
| `rtk swift test --filter AutomationIDTests` | Automation ID contract | Passed, 3 tests | Any automation ID edit |
| `rtk swift test --filter DockStoreTests` | Dock store family | Passed, 54 tests | Any Dock store/projection edit |
| `rtk npm run contract:check` | Projection/proof contract checks | Passed | Any contract/DTO/schema edit |
| `rtk node --test scripts/proof-report-contracts.test.mjs` | Proof contract producer/schema guard | Passed, 2 tests | Any proof contract edit |
| `rtk npm run test:relay` | Relay tests | Passed, 136 tests | Any relay/proof edit |
| `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testPinnedRowsExposeStableSwipeActionAndDedicatedReorderSurface' rtk make app-test SIM='iPhone 17'` | Pinned swipe action and reorder sheet | Passed | Any pinned UI/test edit |
| `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testDockRowOpensSessionDetailByIdentifierWhenRowsExist' rtk make app-test SIM='iPhone 17'` | Dock row to exact thread detail route | Passed after UI-test hardening | Any Dock/detail UI test edit |
| `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testArchivedThreadRowOpensSessionDetailByIdentifierWhenRowsExist' rtk make app-test SIM='iPhone 17'` | Archive row to exact thread detail route | Passed after UI-test hardening | Any Archive/detail UI test edit |
| `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testDockScreenExposesControlsAndConnectivityByIdentifier' rtk make app-test SIM='iPhone 17'` | Basic Dock controls/connectivity hooks | Passed after removing explicit app termination | Any smoke test/Dock UI edit |
| `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testDockLensesAndFiltersAreDrivableInSimulator' rtk make app-test SIM='iPhone 17'` | Lens/filter UI hooks | Passed after removing explicit app termination | Any smoke test/filter UI edit |
| `rtk make app-test SIM='iPhone 17'` | Full generated app and UI suite | Passed; latest log `.codex-dock/logs/app-test-20260602152932.log` | Any UI/project/test edit |
| `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'` | Final install/launch for displayed proof | Passed; build `20260602153216` | Any app/project edit |
| `rtk make sim-ui-dump SIM='iPhone 17'` | Displayed UI dump proof | Passed; `/tmp/codex-client/sim-ui-dump-20260602T153229Z/sim-ui-dump.json` and `.md`; 57 visible elements, Dock screen | Any proof/UI dump edit |

## Transient Failures Resolved

| Failure | Root cause | Resolution |
| --- | --- | --- |
| `Test crashed with signal kill` during overlapping UI proof | Multiple Xcode UI test runners were active against the same simulator | Waited for all runners before rerunning; kept simulator lane single-runner |
| `launchctl bootstrap ... failed with exit 5` | Orphaned `codex app-server` child still held `127.0.0.1:4500` after launchd stop | Stopped services, verified port owner, killed only the orphaned `codex app-server` PID, restarted through `rtk make services` |
| Archive row stale snapshot failure | Test read/re-queried an archive row after tapping into detail | `tapFirstVisibleButton` captures the identifier before tap and returns the plain string |
| Dock-to-detail opened huge pinned thread | Pinned rows can dominate top of live Dock | Dock detail proof collapses pinned rows before selecting the body row |
| `sim-ui-dump` blocked because app was not running | Dump mode intentionally does not launch the app | Ran `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'`, then reran `rtk make sim-ui-dump SIM='iPhone 17'` |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| UIKit pinned normal renderer | Deleted | Removed from pinned rendering path | Complete | `DockPinnedViews` |
| `DockHostLoadStatus.partial` | Deleted | Removed | Complete | `DockHostLoadStatus` |
| Window completeness as health | Removed | Window data is `loaded(rowCount:window:)` | Complete | `ThreadCardTable`, connectivity stores |
| System Health global partial fallback | Deleted | Route evidence drives degradation | Complete | `SystemHealthProjector` |
| Proof producer/schema drift | Closed | Schema and producer include `configuredBuildNumber` | Complete | `sim-ui-dump.schema.json`, `proof-report-contracts.mjs` |

## Fresh Consult Gate

Composer 2.5 Fast fresh consult completed:

- Runtime/model/effort: Cursor Agent `composer-2.5-fast`, effort encoded in model.
- Run directory: `/tmp/fresh-consult/pinned-health-implementation-20260602T153622Z-lyb3qs`
- Final output: `/tmp/fresh-consult/pinned-health-implementation-20260602T153622Z-lyb3qs/final.txt`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Confidence: high

Consult summary:

> The worktree satisfies the architecture plan at the semantic level: pinned rows share SwiftUI `DockSwipeActionRow`, reorder is sheet-only, `DockHostLoadStatus.partial` is gone with window/degraded split wired through connectivity and System Health, and sim-ui-dump shows windowed Dock with online global connectivity. No hacks or major side doors remain for this bug class.

Non-blocking notes recorded for future hardening:

- The pinned UI test waits 2.5 seconds on the live relay-backed simulator instead of deterministically injecting or replaying a Dock update.
- There is no dedicated System Health UI/accessibility test proving windowed Dock categories are not degraded on open.
- `AppConnectivityStore` and `ConnectivityDataEngine` / `ConnectivityRenderProjector` still both exist; this plan intentionally fixed the upstream false signal instead of unifying those rollups.
- `DockSnapshot.isPartial` remains named `isPartial`, though it now means checking/degraded progress context rather than window completeness.

No valid blocking finding requires further implementation in this plan.
