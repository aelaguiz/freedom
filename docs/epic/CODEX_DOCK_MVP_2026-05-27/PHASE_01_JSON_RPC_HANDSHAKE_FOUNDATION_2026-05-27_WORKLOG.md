# Codex Dock Phase 1 Worklog

Date: 2026-05-28

## 2026-05-28 Completion - Real Host Proof

Phase 1 is complete.

Implemented the missing supported transport work:

- Added bearer-token support to the URLSession WebSocket transport so the Swift
  client can send `Authorization: Bearer <token>` during the Codex WebSocket
  upgrade.
- Added tests proving the auth header is sent when configured and omitted when
  no token is configured.
- Kept loopback smoke testing separate from phone-reachable acceptance.
- Kept the phone-reachable acceptance test rejecting `localhost`, `127.0.0.1`,
  `::1`, Unix sockets, mocks, and scripted transports.

Real host evidence:

- Host: `Amir-M5`.
- Listener: `codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file <temp-token-file>`.
- Network endpoint used by tests: `ws://192.168.50.117:4500`.
- Health check: `curl -i http://192.168.50.117:4500/readyz` returned
  `HTTP/1.1 200 OK`.
- macOS SwiftPM real-host handshake passed against `ws://192.168.50.117:4500`
  with bearer auth.
- `iPhone 17` simulator real-host handshake passed against
  `ws://192.168.50.117:4500` with bearer auth.
- The temporary listener was stopped, simulator test environment variables were
  cleared, and the temporary token file was removed after verification.

## 2026-05-28 Correction - Phase Reopened

The implementation below originally proved the local protocol client, but it did
not satisfy Phase 1 acceptance until the real-host proof above landed.

The missing acceptance proof was: the iPhone path must connect to a real Codex
app-server on a real phone-reachable host, currently `Amir-M5` or `Home`.
Mocks, scripted transports, local-only Unix sockets, and Mac-loopback WebSocket
endpoints do not count.

Transport investigation found that this machine's daemon is running, but its
managed app-server is still Unix-socket-only:

- `/Users/aelaguiz/.codex/app-server-daemon/settings.json` has
  `remoteControlEnabled: true`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-daemon/src/backend/pid.rs`
  starts the managed app-server with `--listen unix://`.
- A phone-reachable listener must use a real WebSocket endpoint on LAN or
  Tailscale and must use Codex websocket auth for non-loopback listeners.

## Implementation

- Added a SwiftPM package with a `CodexDock` library target and
  `CodexDockTests`.
- Added `CodexDock/AppServer/JSONRPC.swift` for JSON-RPC request,
  notification, response, error response, request-id, and JSON value handling.
- Added `CodexDock/AppServer/AppServerMethods.swift` for typed
  `initialize`/`initialized` payloads.
- Added `CodexDock/AppServer/AppServerClient.swift` for the app-server client,
  request correlation, explicit connection state, timeout/cancellation errors,
  notification streaming, URLSession WebSocket transport, and bearer auth for
  Codex non-loopback WebSocket listeners.
- Kept the public client path on `connectAndInitialize` so later callers do not
  bypass the required app-server handshake.
- Added a deterministic test transport in `CodexDockTests` for request/response
  matching, notification delivery, offline/malformed/error paths, and handshake
  proof.
- Added optional loopback and phone-reachable real-host handshake tests. The
  phone-reachable test requires bearer auth and rejects loopback endpoints.

## Tooling

- `swift --version` reported Apple Swift `6.3.2`; no tooling install was
  needed for this phase.
- Xcode `26.5` was available for iPhone simulator verification.
- The `iPhone 17` simulator destination used for verification was
  `DEF1631B-7125-43C6-BFA3-4423BF103C91`.

## Verification

The checks below include both local implementation checks and the real
phone-reachable host proof.

- `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_01_JSON_RPC_HANDSHAKE_FOUNDATION_2026-05-27.md`
  returned `READY next=implement-loop`.
- `swift test` passed 16 tests with the phone-reachable real-host env set; the
  loopback smoke test skipped because no loopback env was set.
- `xcodebuild test -scheme codex-client -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91'`
  passed on the `iPhone 17` simulator with the phone-reachable real-host env set.

## Scope Boundary

- Implemented Phase 1 only.
- Did not implement `thread/list`, SwiftUI Dock shell, thread detail, text
  control, multi-host scan behavior, archive/hosts surfaces, voice, or AIMGR.
