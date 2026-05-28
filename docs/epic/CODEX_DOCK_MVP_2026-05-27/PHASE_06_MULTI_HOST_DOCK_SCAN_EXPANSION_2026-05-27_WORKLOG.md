# Codex Dock Phase 6 Worklog

Date: 2026-05-28

Plan: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_06_MULTI_HOST_DOCK_SCAN_EXPANSION_2026-05-27.md`

Status: complete

## Summary

Phase 6 widened the proven single-host Dock path into a multi-host scan board
without replacing the working list/detail/control path.

Implemented:

- `HostRegistry` for one-host fallback and scoped multi-host environment
  configuration.
- `DockStore(registry:)` with independent host fan-out.
- Per-host load state so one offline host does not blank rows from another.
- Host/branch section grouping for multi-host Dock state.
- Full endpoint display in host summaries, including the port. This prevents
  hiding `:4500` vs `:4510`, which was the root cause of stale-looking status
  during live debugging.
- Filter projection over normalized row status for All, Needs me, Running, and
  Limited.
- Filter-specific empty-state text so "no matches" does not look like data
  loss.
- App-local metadata keyed by host id, backend session id, and thread id.
- Local label/color context-menu actions on Dock rows.
- File-backed metadata persistence at Application Support:
  `CodexDock/thread-metadata.json`.
- `CodexDockApp` now builds its store from `HostRegistry.fromEnvironment()`.
- `rtk make app` now:
  - uses the host registry env shape,
  - keeps the legacy single-host env for compatibility,
  - prints the launch endpoint and host list,
  - terminates stale Codex Dock app processes on other booted simulators before
    launching the selected simulator.

## Root-Cause Follow-Up

During Phase 6, the stale All / empty Running report was checked again against
real endpoints.

Findings:

- The raw app-server at `ws://192.168.50.117:4500` returned `100` rows, all
  `notLoaded`.
- The relay at `ws://192.168.50.117:4510` returned `108` rows: `3 active`,
  `16 idle`, and `89 notLoaded`.
- That `:4500` result exactly matches the bad UI shape: All looks like old
  Limited history, Running is empty, and Needs me is empty.
- The canonical simulator is the plain `iPhone 17` with UDID
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- A second booted simulator named
  `feat_remount-disposal-lifecycle-post-audit - iPhone 17` had Codex Dock
  installed and stale state.

Corrections made in this phase:

- The Dock host summary now shows `ws://192.168.50.117:4510`, not only the host
  name.
- `rtk make app` terminates Codex Dock on other booted simulators before
  launching the target simulator.
- The bug note was updated:
  `docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md`.

## Real-Host Evidence

Relay direct query:

- Endpoint: `ws://192.168.50.117:4510`.
- Result: `108` rows.
- Status counts: `3 active`, `16 idle`, `89 notLoaded`.

Multi-host simulator proof:

- Command:
  `rtk make app SIM='iPhone 17' CODEX_DOCK_HOSTS='Amir-M5,Home' CODEX_DOCK_HOST_HOME_WS='ws://192.168.50.117:9'`.
- Target simulator:
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- `Amir-M5` loaded real relay rows from `ws://192.168.50.117:4510`.
- `Home` was intentionally offline at `ws://192.168.50.117:9`.
- The Dock still showed live `Amir-M5` rows and a visible `Running` row.
- Screenshot: `/tmp/codex-dock-phase6-multi-host-offline.png`.

Default app launch proof:

- Command: `rtk make app SIM='iPhone 17'`.
- Host list: `Amir-M5`.
- Launch endpoint: `ws://192.168.50.117:4510`.
- Screenshot: `/tmp/codex-dock-phase6-default-live.png`.

## Verification

Commands run:

```sh
rtk swift test
rtk node --check scripts/dock-relay.mjs
rtk npm run test:relay
rtk make app SIM='iPhone 17' CODEX_DOCK_HOSTS='Amir-M5,Home' CODEX_DOCK_HOST_HOME_WS='ws://192.168.50.117:9'
rtk make app SIM='iPhone 17'
rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath .codex-dock/DerivedData
rtk git diff --check
```

Results:

- SwiftPM tests passed: 63 tests, 4 optional live-host tests skipped.
- Relay syntax check passed.
- Relay unit tests passed: 3 tests.
- Multi-host app build/install/launch passed on canonical `iPhone 17`.
- Default app build/install/launch passed on canonical `iPhone 17`.
- Xcode simulator tests passed on canonical `iPhone 17`.
- Whitespace check passed.

## Services Left Running

- Raw history app-server: `ws://192.168.50.117:4500`, pid `93066`.
- Dock relay: `ws://192.168.50.117:4510`, pid `41708`.
- iPhone 17 app process: `com.aelaguiz.CodexDockApp`, latest launch pid
  `32418`.
