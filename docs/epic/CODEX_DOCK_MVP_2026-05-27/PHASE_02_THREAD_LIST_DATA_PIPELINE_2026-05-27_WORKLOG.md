# Phase 2 Worklog - Thread List Data Pipeline

Date: 2026-05-28

## Implementation Summary

- Added the first real data method: `AppServerClient.threadList(...)`.
- Added protocol-facing `thread/list` DTOs and params in
  `CodexDock/AppServer/ThreadListDTO.swift`.
- Added app-facing host-scoped summary models in
  `CodexDock/Models/SessionSummary.swift`.
- Added `SessionSummaryMapper` in `CodexDock/Models/SessionSummaryMapper.swift`
  so future UI can consume summaries without raw JSON-RPC or app-server DTOs.
- Added fixture, method-error, sparse payload, malformed-row, unknown-status,
  host-id, and live real-host tests.
- No tooling installs were needed for this phase.

## Real Host Proof

- Host: `Amir-M5`.
- Bind address: `ws://0.0.0.0:4500`.
- Client endpoint: `ws://192.168.50.117:4500`.
- Server mode:
  `codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file <temp-token-file>`.
- Health check: `GET http://192.168.50.117:4500/readyz` returned `200 OK`.
- macOS SwiftPM called `thread/list` against the real endpoint and mapped the
  response into `SessionSummary`.
- The `iPhone 17` simulator called `thread/list` against the same real endpoint
  and mapped the response into `SessionSummary`.

## Verification

- `swift test` passed 24 tests with no live endpoint env set; the three optional
  live endpoint tests skipped.
- Live macOS verification passed:
  `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4500 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=<temp-token-file> CODEX_DOCK_REAL_HOST_ID=Amir-M5 swift test`
  executed 24 tests, skipped only the loopback-only smoke test, and passed the
  Phase 1 real-host handshake plus Phase 2 real-host `thread/list` mapping test.
- Live `iPhone 17` simulator verification passed:
  `xcodebuild test -scheme codex-client -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91'`
  with simulator env set for the same endpoint. The Phase 1 real-host handshake
  and Phase 2 real-host `thread/list` mapping test both passed.

## Cleanup

- Stopped the temporary app-server on port `4500`.
- Cleared the simulator env vars:
  `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`,
  `CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE`, and `CODEX_DOCK_REAL_HOST_ID`.
- Removed the temporary token file.

## Notes

- `Home` was not tested in this phase. Phase 2 required one real host proof and
  used `Amir-M5`; `Home` remains the planned second host for the multi-host
  phase.
- The implementation did not add a relay, mock production data, Dock UI,
  thread detail, control/send behavior, archive, voice, or AIMGR.
