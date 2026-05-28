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
  voice, AIMGR, or relay was added in Phase 3.
