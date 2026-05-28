# Codex Dock Phase 5 Worklog

Date: 2026-05-28

Plan: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_05_TEXT_CONTROL_REQUEST_CARDS_2026-05-27.md`

Status: complete

## Summary

Phase 5 added the first phone-side control path on top of the Phase 4 real
thread detail path.

Implemented:

- Typed `turn/start`, `turn/steer`, and `turn/interrupt` method constants.
- Typed turn DTOs for app-server text input.
- `AppServerClient.turnStart`, `turnSteer`, and `sendResponse`.
- `ComposerState` in `ThreadDetailStore`.
- Composer send behavior:
  - trims empty drafts
  - starts a new turn when no active turn is known
  - steers the known active turn when one is known
  - clears draft only on success
  - preserves draft and displays the error on failure
- `ServerRequestCard` model for command approval, file approval, permission
  approval, user input, MCP elicitation, and unsupported request methods.
- Request card UI in thread detail.
- JSON-RPC server-request response sending by request id.
- Relay forwarding for `turn/start`, `turn/steer`, `turn/interrupt`, and raw
  server-request responses after `thread/resume`.
- Relay list resilience when the history source times out but live rows are
  available.
- Relay request-aware attention enrichment: active rows can be marked
  `Needs me` from real replayed pending app-server requests, never from fake
  rows or guessed process state.

## Root-Cause Follow-Up

During Phase 5, the Dock filters were rechecked because the user reported that
All looked stale and Needs me / Running were empty.

Findings:

- The canonical `iPhone 17` simulator is
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- A second booted simulator named
  `feat_remount-disposal-lifecycle-post-audit - iPhone 17`
  also existed.
- The canonical simulator was connected to the relay endpoint
  `ws://192.168.50.117:4510`.
- The relay returned real live state: `107` rows, with `3 active`, `15 idle`,
  and `89 notLoaded`.
- No active row had `waitingOnApproval` or `waitingOnUserInput`, so an empty
  `Needs me` filter was correct for the current live data.
- The app must not fill `Needs me` from process presence alone.

The root-cause note was appended to
`docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md`.

## Real-Host Evidence

Real typed-send smoke:

- Endpoint: `ws://192.168.50.117:4510`.
- Host: `Amir-M5`.
- Thread: `019e6c7f-7bce-76a0-8db9-131b8905c9a5`.
- Sent `turn/start` text through the relay.
- Response turn: `019e6c9a-0664-7fc3-a8cb-fd243120af30`.
- Observed `turn/completed`.

Simulator evidence:

- `rtk make app SIM='iPhone 17'` launched `com.aelaguiz.CodexDockApp` on
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- The Dock showed real `Running` rows from the relay.
- A real Dock row opened into Thread detail with the composer visible.
- Screenshot: `/tmp/codex-dock-phase5-root-cause-composer.png`.

## Verification

Commands run:

```sh
rtk node --check scripts/dock-relay.mjs
rtk npm run test:relay
rtk swift test
rtk make dock-relay-restart
rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath .codex-dock/DerivedData
rtk make app SIM='iPhone 17'
rtk git diff --check
```

Results:

- Relay syntax check passed.
- Relay unit tests passed: 3 tests.
- SwiftPM tests passed: 56 tests, 4 optional live-host tests skipped.
- Xcode simulator tests passed on `iPhone 17`.
- App build/install/launch passed on `iPhone 17`.
- Whitespace check passed.

## Services Left Running

- Raw history app-server: `ws://192.168.50.117:4500`, pid `93066`.
- Dock relay: `ws://192.168.50.117:4510`, pid `41708`.
- iPhone 17 app process: `com.aelaguiz.CodexDockApp`, latest launch pid
  `61376`.
