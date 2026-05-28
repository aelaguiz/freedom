# Phase 1 Plan Audit Log

## 2026-05-28 - Completion Audit After Real-Host Proof

Mode: `implementation-audit`

Verdict: `complete`

The reopened Phase 1 gate is now satisfied. The client completed
`initialize` then `initialized` against a real Codex app-server on `Amir-M5`
using the supported direct WebSocket listener with websocket auth.

Accepted evidence:

- Real host: `Amir-M5`.
- Bind address: `ws://0.0.0.0:4500`.
- Client endpoint: `ws://192.168.50.117:4500`.
- Codex listener mode:
  `codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file <token-file>`.
- Health check: `GET http://192.168.50.117:4500/readyz` returned `200 OK`.
- macOS selected real-host test passed with
  `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4500`.
- `iPhone 17` simulator selected real-host test passed against the same
  endpoint after setting simulator environment with `simctl launchctl setenv`.
- Full `swift test` passed with the phone-reachable endpoint configured.
- Full `xcodebuild test -scheme codex-client -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91'`
  passed on the `iPhone 17` simulator with the phone-reachable endpoint
  configured.

Rejected evidence remains rejected:

- Mocks, scripted transports, Unix sockets, `localhost`, `127.0.0.1`, `::1`,
  and Mac-loopback WebSockets still do not count as Phase 1 acceptance.

## 2026-05-28 - Completion Correction

Mode: `implementation-audit-correction`

Verdict: `reopened`

Superseded by the 2026-05-28 completion audit above after the real-host proof
passed. The correction remains here to document why the earlier local-only
evidence was rejected.

The previous `approve` verdict was too weak for the real requirement. It
accepted local protocol evidence, including deterministic test transports and
`iPhone 17` simulator tests. That evidence is still useful, but it does not
prove that an iPhone can connect to a real Codex app-server on a real host.

New blocking acceptance requirement:

- The iPhone path must complete `initialize` then `initialized` against a real
  Codex app-server on `Amir-M5` or `Home`.
- The endpoint must be phone-reachable over LAN, Tailscale, or another real
  network path.
- Mocks, scripted transports, Unix sockets, `localhost`, `127.0.0.1`, and `::1`
  do not count.
- Codex non-loopback WebSocket listeners require websocket auth, so the client
  must support that auth before this proof can pass.

Transport evidence:

- This machine's daemon is running with socket path
  `/Users/aelaguiz/.codex/app-server-control/app-server-control.sock`.
- `/Users/aelaguiz/.codex/app-server-daemon/settings.json` has
  `remoteControlEnabled: true`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-daemon/src/backend/pid.rs`
  hardcodes daemon startup to `--listen unix://`, including the remote-control
  case.

## 2026-05-28 - Implementation Audit

Mode: `implementation-audit`

Scope: Phase 1 only,
`docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_01_JSON_RPC_HANDSHAKE_FOUNDATION_2026-05-27.md`.

Verdict: `approve`

Test context accepted:

- `swift test` passed 12 tests.
- `xcodebuild test -scheme codex-client -destination 'id=DEF1631B-7125-43C6-BFA3-4423BF103C91'`
  passed on `iPhone 17`.

Code areas read:

- `Package.swift`
- `CodexDock/AppServer/JSONRPC.swift`
- `CodexDock/AppServer/AppServerMethods.swift`
- `CodexDock/AppServer/AppServerClient.swift`
- `CodexDockTests/AppServerClientTests.swift`

Obligations checked:

- JSON-RPC request, response, notification, request id, and error envelopes
  exist and are Codable.
- Request ids are explicit and support integer and string ids.
- Unknown JSON fields do not break response decoding.
- Malformed payloads fail loudly.
- Test transport proves request/response matching without WebSocket.
- Client has one app-server boundary, `AppServerClient`, with explicit
  connection state.
- WebSocket transport uses `URLSessionWebSocketTask` behind the client
  transport boundary.
- Receive loop continues after responses and yields notifications.
- Timeout, cancellation, offline, malformed message, and server-error paths are
  explicit errors/states.
- `connectAndInitialize` sends `initialize`, handles the result, then sends the
  `initialized` notification.
- Public client API does not expose a raw app-server method path that can skip
  the required initialize handshake.
- No Phase 2+ behavior was implemented.

Findings added: none.

Findings resolved during audit:

- Tightened the public client API so the raw transport connect path is not the
  future app's public client entry point.
- Fixed a simulator-only race in the in-flight request test by matching
  responses to request ids/methods instead of task send order.

Next audit focus:

- Phase 2 should add `thread/list` through the same `AppServerClient`
  request boundary without introducing raw JSON-RPC in callers.
