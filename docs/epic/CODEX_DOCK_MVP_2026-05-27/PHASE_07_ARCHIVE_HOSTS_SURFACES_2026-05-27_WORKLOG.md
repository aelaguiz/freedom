# Codex Dock Phase 7 Worklog

Date: 2026-05-28

Plan: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_07_ARCHIVE_HOSTS_SURFACES_2026-05-27.md`

Status: complete

## Summary

Phase 7 adds the remaining non-voice MVP surfaces on the real app-server path:
Archive and Hosts.

Implemented:

- Typed Swift wrappers for `thread/archive` and `thread/unarchive`.
- `AppServerDockClient` archive/unarchive calls against the configured host.
- `thread/list` archived filtering through `DockSessionLoading`.
- Relay support for:
  - archived `thread/list` without merging live loopback rows,
  - `thread/archive`,
  - `thread/unarchive`.
- `SessionRowProjector` so Dock and Archive share row/section projection instead
  of growing `DockStore` with archive-specific projection.
- `ArchiveStore` that loads archived rows with host/session identity intact and
  restores through `thread/unarchive`.
- Dock row archive action. A row is removed only after app-server archive
  succeeds and Dock refreshes.
- Failed archive/unarchive actions publish visible action errors and keep the
  row recoverable.
- `ArchiveView` tab with host state, archived rows, and restore action.
- `HostSettingsStore` with shared registry state, add/edit host, and host test.
- `HostsView` tab with host name, endpoint, connection status, last check, and
  utilitarian add/edit/test controls.
- `CodexDockRootView` now owns Dock, Archive, and Hosts stores and propagates
  host registry changes back into Dock/Archive.

Out of V1:

- No AIMGR status.
- No Rotate behavior.
- No account switching.

## Real-Host Evidence

Phone-reachable relay:

- Endpoint: `ws://192.168.50.117:4510`.
- Raw history app-server behind relay: `ws://127.0.0.1:4500`.
- Host: `Amir-M5`.
- Simulator: `iPhone 17`,
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.

Archive/unarchive round trip:

- Command:
  `rtk env CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=.codex-dock/app-server.token CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP=1 swift test --filter AppServerClientTests/testPhoneReachableRealHostArchiveUnarchiveRoundTripWhenExplicitlyEnabled`
- Result: passed.
- Behavior proven:
  - selected a real non-loaded thread from default `thread/list`,
  - called real `thread/archive`,
  - verified the thread appeared in `thread/list` with `archived: true`,
  - called real `thread/unarchive`,
  - verified the thread returned to default `thread/list`.

Simulator proof:

- Command: `rtk make app SIM='iPhone 17'`.
- App launch endpoint: `ws://192.168.50.117:4510`.
- Dock screenshot: `/tmp/codex-dock-phase7-dock.png`.
- Archive screenshot: `/tmp/codex-dock-phase7-archive.png`.
- Hosts screenshot before test: `/tmp/codex-dock-phase7-hosts.png`.
- Hosts screenshot after real host test:
  `/tmp/codex-dock-phase7-hosts-tested.png`.
- Hosts test result shown in app: `Amir-M5` online with `108 sessions`.

## Verification

Commands run:

```sh
rtk swift test
rtk node --check scripts/dock-relay.mjs
rtk npm run test:relay
rtk make dock-relay-restart
rtk env CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=.codex-dock/app-server.token CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP=1 swift test --filter AppServerClientTests/testPhoneReachableRealHostArchiveUnarchiveRoundTripWhenExplicitlyEnabled
rtk make app SIM='iPhone 17'
rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath .codex-dock/DerivedData
rtk rg "AIMGR|Rotate|account switching|AI Manager" CodexDock CodexDockApp scripts -n
rtk git diff --check
```

Results:

- SwiftPM tests passed: 69 tests, 5 optional live-host tests skipped.
- Relay syntax check passed.
- Relay unit tests passed: 5 tests.
- Relay was restarted and left running with Phase 7 archive/unarchive support.
- Explicit real-host archive/unarchive round trip passed.
- App build/install/launch passed on canonical `iPhone 17`.
- Xcode simulator tests passed on canonical `iPhone 17`.
- V1 implementation code contains no AIMGR/Rotate/account-switching integration.
- Whitespace check passed.

## Services Left Running

- Raw history app-server: `ws://192.168.50.117:4500`, pid `93066`.
- Dock relay: `ws://192.168.50.117:4510`, pid `49737`.
- iPhone 17 app process: `com.aelaguiz.CodexDockApp`, latest launch pid
  `52985`.
