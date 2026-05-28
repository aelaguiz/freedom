# Phase 3 Worklog - iPhone Shell Single-Host Dock

Date: 2026-05-28

## Implementation Summary

- Added `project.yml` and generated `CodexDock.xcodeproj` with XcodeGen.
- Added real iOS app target `CodexDockApp` with `CodexDockApp/CodexDockApp.swift`.
- Added `DockHostConfiguration` for launch-time host/token configuration.
- Added `DockStore` as the UI state owner over the Phase 1/2 app-server and
  `SessionSummary` pipeline.
- Added SwiftUI Dock shell with Dock, Archive, and Hosts tabs; only Dock has
  real Phase 3 content.
- Added Dock rows grouped by branch with host, repo/cwd, branch, status, last
  activity, and short summary.
- Added Dock loading, empty, offline, and error states.
- Added `DockStoreTests` for loaded, empty, offline, error, and configuration
  failure behavior.

## Tooling

- Installed XcodeGen 2.45.4 with `rtk brew install xcodegen`.
- XcodeGen is required to regenerate `CodexDock.xcodeproj` from `project.yml`.
- Added `Makefile` app-server targets so `rtk make app-server` is the canonical
  start path. The target installs/uses a per-repo LaunchAgent for the
  authenticated LAN listener and keeps plist/PID/token/log files under
  `.codex-dock/`.

## Verification

- `rtk swift test` passed 31 tests; 3 optional live endpoint tests skipped when no
  endpoint env was present.
- `rtk xcodegen generate --spec project.yml` created `CodexDock.xcodeproj`.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91' -derivedDataPath /tmp/codex-dock-phase3-derived build` passed.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91' -derivedDataPath /tmp/codex-dock-phase3-derived` passed.
- Real-host focused SwiftPM proof passed with
  `rtk env CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4500`,
  `CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=<temp-token-file>`, and
  `CODEX_DOCK_REAL_HOST_ID=Amir-M5`.

## Real Host Proof

- Host: `Amir-M5`.
- Endpoint: `ws://192.168.50.117:4500`.
- Server command:
  `rtk make app-server` for the canonical persistent start path. The underlying
  LaunchAgent runs `codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file .codex-dock/app-server.token`.
- Reachability: `rtk curl -i --max-time 5 http://192.168.50.117:4500/readyz`
  returned `HTTP/1.1 200 OK`.
- App proof: installed and launched `com.aelaguiz.CodexDockApp` on the booted
  `iPhone 17` simulator with simulator child env pointing at the real host.
- Live screenshot: `/tmp/codex-dock-phase3-live-host-no-arbitrary-loads.png`
  showed `Amir-M5`, `192.168.50.117`, and 50 real sessions after ATS was
  tightened to local networking only.
- Offline screenshot: `/tmp/codex-dock-phase3-offline.png` showed the same host
  in `Offline` state after the real app-server was stopped.

## Scope Notes

- Preview/demo rows exist only in SwiftUI preview code.
- No production fallback rows were added.
- No thread detail, multi-host, Archive implementation, Hosts implementation,
  voice, or AIMGR was added in Phase 3.

## False-Complete Repair: Live Session Source

- Root cause: the phone-visible raw app-server on `ws://192.168.50.117:4500`
  was real, but it only exposed stored history from its own process. The active
  Codex sessions were attached to private loopback app-servers, so the Dock saw
  old `Limited` rows and no `Running` rows.
- Added `scripts/dock-relay.mjs`, an authenticated host-side relay on
  `ws://192.168.50.117:4510`. It discovers real loopback Codex app-server
  processes, calls supported JSON-RPC methods, and merges live loaded rows over
  stored history.
- Changed `rtk make services`, `.env`, and `rtk make app SIM=...` so the app
  uses the relay endpoint while the raw app-server remains the relay's history
  source.
- Updated Dock ordering so rows and branch sections are newest-first; status is
  only a tie-breaker.
- Added Dock auto-refresh every five seconds while the Dock view is active, plus
  the existing pull-to-refresh path.
- Verification added for newest-first ordering and refresh in
  `DockStoreTests`.
- Current proof after the repair:
  - `rtk swift test` passed 33 tests with 3 optional live endpoint tests skipped.
  - Relay direct query against `ws://192.168.50.117:4510` returned 50
    newest-first rows with `active: 3`, `idle: 21`, and `notLoaded: 26`;
    `thread/loaded/list` returned 29 real loaded IDs.
  - Relay-backed live Swift tests passed with
    `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510`.
  - `rtk make app SIM='iPhone 17'` built, installed, and launched the app.
  - `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
    -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath
    .codex-dock/DerivedData` passed.
  - Screenshot `/tmp/codex-dock-phase3-relay-recency-refresh.png` showed
    `Amir-M5 · 118 sessions` on the `iPhone 17` simulator.
