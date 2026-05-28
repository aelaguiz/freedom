# Phase 4 Worklog - Thread Detail Read/Live View

Date: 2026-05-28

## Implementation Summary

- Added typed app-server support for `thread/read` and `thread/resume`.
- Added `ThreadDetailDTO` for read/resume params and responses.
- Changed `AppServerClient` so server-initiated JSON-RPC requests are surfaced
  on `serverRequests` instead of killing the connection.
- Added `ThreadEvent` and `ThreadEventNormalizer` to project stored turns,
  live notifications, command output, request-like server requests, status
  changes, and unknown event shapes into app-facing events.
- Added `ThreadDetailStore` as the one owner for open-thread lifecycle:
  identity validation, connect, read, resume, stale/error state, notification
  merge, and server request merge.
- Added `SessionDetailView` and wired Dock rows to navigate into detail with the
  real `DockHostConfiguration` and host-scoped thread id.
- Extended `scripts/dock-relay.mjs` so the phone-reachable relay can read full
  thread turns, resume a real upstream thread, and forward upstream
  notifications/server requests to the app.

## Real Host Proof

- Host: `Amir-M5`.
- Raw history endpoint: `ws://192.168.50.117:4500`.
- Phone-reachable relay endpoint: `ws://192.168.50.117:4510`.
- Token file:
  `/Users/aelaguiz/workspace/codex-client/.codex-dock/app-server.token`.
- `rtk make dock-relay-restart` restarted the relay after code changes and left
  the raw app-server running.
- Direct relay probe selected real loaded thread
  `019e6c34-d435-7a51-ba98-7d9bb3ced865`, read it with
  `includeTurns:true`, resumed it, and observed upstream
  notifications/server messages after the resume response.
- The optional live XCTest
  `AppServerClientTests/testPhoneReachableRealHostThreadReadAndResumeWhenEndpointIsProvided`
  passed against `ws://192.168.50.117:4510`.

## Simulator Proof

- Simulator: `iPhone 17`
  (`BAD95C8E-3E57-4818-9B90-E4ED22593B4B`).
- `rtk make app SIM='iPhone 17'` built, installed, and launched
  `com.aelaguiz.CodexDockApp` with relay env.
- Tapped a real Dock row in the simulator and opened the matching Thread detail
  screen.
- Screenshot: `/tmp/codex-dock-phase4-detail.png`.
- The detail screen showed `Amir-M5`, `Live`, the row thread, and normalized
  transcript cards instead of raw JSON.

## Verification

- `rtk swift test` passed 45 tests; 4 optional real-host tests skipped when
  endpoint env was absent.
- `rtk env CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=/Users/aelaguiz/workspace/codex-client/.codex-dock/app-server.token CODEX_DOCK_REAL_HOST_ID=Amir-M5 CODEX_DOCK_REAL_HOST_NAME=Amir-M5 swift test --filter AppServerClientTests/testPhoneReachableRealHostThreadReadAndResumeWhenEndpointIsProvided`
  passed.
- `rtk node --check scripts/dock-relay.mjs` passed.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
  -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath
  .codex-dock/DerivedData` passed.
- `rtk make app SIM='iPhone 17'` passed.

## Scope Notes

- No text send/steer UI was added.
- No request-card response UI was added.
- Server requests are visible to the store as normalized request events, but
  answering them is Phase 5.
- No production mocks or fake thread data were added.
- The relay remains a real-host bridge over supported Codex JSON-RPC methods;
  it does not invent rows, statuses, or transcripts.
