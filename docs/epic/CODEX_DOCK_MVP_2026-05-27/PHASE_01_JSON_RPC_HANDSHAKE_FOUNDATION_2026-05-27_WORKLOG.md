# Codex Dock Phase 1 Worklog

Date: 2026-05-28

## 2026-05-28 Correction - Phase Reopened

The implementation below proves the local protocol client, but it does not
satisfy Phase 1 acceptance anymore.

The missing acceptance proof is: the iPhone path must connect to a real Codex
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
  notification streaming, and URLSession WebSocket transport.
- Kept the public client path on `connectAndInitialize` so later callers do not
  bypass the required app-server handshake.
- Added a deterministic test transport in `CodexDockTests` for request/response
  matching, notification delivery, offline/malformed/error paths, and handshake
  proof.

## Tooling

- `swift --version` reported Apple Swift `6.3.2`; no tooling install was
  needed for this phase.
- Xcode `26.5` was available for iPhone simulator verification.
- The `iPhone 17` simulator destination used for verification was
  `DEF1631B-7125-43C6-BFA3-4423BF103C91`.

## Verification

The checks below are local implementation checks. They are no longer sufficient
for Phase 1 completion until the real phone-reachable host proof is added.

- `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_01_JSON_RPC_HANDSHAKE_FOUNDATION_2026-05-27.md`
  returned `READY next=implement-loop`.
- `swift test` passed 12 tests.
- `xcodebuild test -scheme codex-client -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91'`
  passed on the `iPhone 17` simulator.

## Scope Boundary

- Implemented Phase 1 only.
- Did not implement `thread/list`, SwiftUI Dock shell, thread detail, text
  control, multi-host scan behavior, archive/hosts surfaces, voice, or AIMGR.
