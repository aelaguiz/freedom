# Phase 1 Thermonuclear Code Quality Review

Date: 2026-05-28

Verdict: `approve`

Completion correction: this review still approves the local code structure, but
it does not approve Phase 1 completion. Phase 1 is reopened until the iPhone
path connects to a real Codex app-server on `Amir-M5` or `Home`. Mocks,
scripted transports, Unix sockets, and Mac-loopback WebSocket endpoints are not
completion evidence.

## Findings

- No blocking structural findings.
- No file crosses the 1,000-line threshold. Current largest files are
  `CodexDock/AppServer/AppServerClient.swift` and
  `CodexDockTests/AppServerClientTests.swift`, both under 500 lines.
- No UI, `thread/list`, AIMGR, archive, voice, or later-phase behavior leaked
  into the Phase 1 implementation.
- The main code-quality risk found during review was a public raw client
  `connect()` path that could let future callers skip the app-server
  `initialize` handshake. That was removed from the public `AppServerClient`
  API; the public path is now `connectAndInitialize`.
- The second risk found during review was an order-dependent in-flight request
  test that passed on macOS but failed on the `iPhone 17` simulator. The test now
  maps responses by request id/method, which tests the actual protocol
  invariant.

## Structure Reviewed

- `JSONRPC.swift` owns JSON-RPC value/envelope shapes and does not know about
  WebSocket, app lifecycle, or future UI.
- `AppServerMethods.swift` owns the typed `initialize`/`initialized` payload
  shapes.
- `AppServerClient.swift` owns request ids, pending request correlation,
  connection state, notification streaming, failure handling, and the
  URLSession WebSocket transport.
- `AppServerClientTests.swift` uses one deterministic test transport rather
  than duplicating transport behavior across test cases.

## Maintainability Judgment

The implementation is direct and phase-sized. The abstractions earn their keep:
`JSONValue` handles arbitrary protocol payloads, `JSONRPCMessage` owns envelope
classification, `AppServerTransport` creates the test seam, and
`AppServerClient` is the single app-server boundary later phases can extend.

No cleaner code-judo move is obvious without either under-building the planned
transport seam or over-building Phase 2 concerns early.
