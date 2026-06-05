# Codex Dock App-Server Registry Hard Cut - Worklog

This worklog records implementation evidence for
`docs/CODEX_DOCK_APP_SERVER_REGISTRY_HARD_CUT_2026-06-05.md`. It is not a
second plan.

## 2026-06-05T01:29:30Z - Implementation start

- Branch: `codex-dock-agents-tab-live-counts`.
- Read the full plan and required `$arch-step` implementation references.
- Readiness gate: `READY next=implement-loop`.
- Current frontier: Phase 1, registry seam.
- Starting with registry and upstream-client tests before changing relay request
  handlers or host-service lifecycle.

## 2026-06-05T01:34:04Z - Phase 1 complete

- Added `scripts/dock-relay-app-server-registry.mjs`.
- Added Codex `unix://` to `ws+unix:` upstream support in
  `scripts/dock-relay-json-rpc-client.mjs`.
- Added registry/client tests for daemon history selection, discovered loopback
  live owner leases, and private `stdio://` diagnostics.
- Added registry/performance constants in `scripts/dock-relay-constants.mjs`.
- Focused proof: `rtk node --test scripts/dock-relay-json-rpc-client.test.mjs scripts/dock-relay-app-server-registry.test.mjs`
  passed with 4 tests and 0 failures.
- Phase proof: `rtk npm run test:relay` passed with 206 tests and 0 failures.

## 2026-06-05T01:54:00Z - Hard cut implementation pass

- Relay startup no longer accepts or requires normal `historyUrl`,
  `liveEndpoints`, `--history-url`, or `--history-auth-token-file` wiring.
- `scripts/dock-relay-thread-data.mjs`,
  `scripts/dock-relay-live-status-cache.mjs`, and
  `scripts/dock-relay-state-engine.mjs` now require `appServerRegistry` for
  routing instead of falling back to a single raw history endpoint.
- `scripts/dock-relay-status.mjs` now reports sanitized registry state instead
  of probing a raw `/readyz` history app-server.
- `scripts/codex-dock-host-service.mjs` now renders and manages only the Dock
  relay service. It no longer creates a raw app-server service, raw app-server
  token file, or raw app-server health check.
- `Makefile` host-service arguments no longer pass raw app-server listen,
  history URL, token file, or app-server label settings.
- `README.md` now documents the registry/relay topology and the relay-only home
  deployment commands.
- Added registry route-table coverage for live-owner methods, history methods,
  active-session-only methods, and private stdio owners.
- Proof: focused service/relay command passed with 69 tests and 0 failures.
- Proof: `rtk npm run test:relay` passed with 207 tests and 0 failures.

## 2026-06-05T02:06:08Z - Real machine registry proof

- Real machine process scan found 13 addressable registry endpoints after
  duplicate process rows were deduped.
- Selected history endpoint: Codex daemon `unix://` control socket.
- Real history proof: `thread/list limit=3` succeeded through the daemon Unix
  socket and returned response keys `backwardsCursor`, `data`, and
  `nextCursor`.
- Live endpoint proof: 11 non-Dock loopback WebSocket app-server endpoints were
  discovered and queried for `thread/loaded/list`.
- The old Dock-owned raw port `4500` was not included in registry live
  endpoints.
- Private runtime proof: 15 `stdio://` app-server processes were counted as
  observed private runtimes and were not treated as attachable live owners.
- Live rows proof: the 11 attachable loopback endpoints reported 0 loaded
  threads at proof time, so no live-owner route sample existed on this machine.
- Root-cause fix from real proof: Codex's Unix app-server accepts a no-compress
  WebSocket handshake. Node's default `ws` client advertised compression and
  the real daemon closed with `socket hang up`, so
  `JsonRpcWebSocketClient` now sets `perMessageDeflate: false`.
- Focused regression proof:
  `rtk node --test scripts/dock-relay-app-server-registry.test.mjs scripts/dock-relay-json-rpc-client.test.mjs`
  passed with 7 tests and 0 failures.

## 2026-06-05T02:08:42Z - Discovery tightening proof

- Tightened process discovery so unrelated long command lines that merely
  mention `codex app-server` in prompt text are not classified as app-server
  processes.
- Real machine proof still passed after the tightening:
  - selected history endpoint: Codex daemon `unix://` control socket;
  - history `thread/list limit=3`: succeeded;
  - live endpoints: 11 non-Dock loopback WebSocket app-server endpoints;
  - old Dock-owned raw port `4500`: excluded;
  - private `stdio://` observations: 15;
  - loaded live rows on attachable endpoints at proof time: 0.

## 2026-06-05T02:07:14Z - Full Node suite proof

- Command: `rtk npm test`.
- Contract proof passed: projection contract fixtures/DTO current, 5 proof
  schemas and 5 canonical samples validated.
- Relay proof passed: 209 tests, 0 failures.
- Host-service proof passed: 36 tests, 0 failures.

## 2026-06-05T02:09:03Z - Final full Node suite proof after review fix

- Command: `rtk npm test`.
- Contract proof passed: projection contract fixtures/DTO current, 5 proof
  schemas and 5 canonical samples validated.
- Relay proof passed: 209 tests, 0 failures.
- Host-service proof passed: 36 tests, 0 failures.

## 2026-06-05T02:14:34Z - Deploy cleanup fix for stale raw app-server service

- Real deploy proof found the rendered relay plist had been updated, but
  launchd was still running the old relay process with `--history-url
  ws://127.0.0.1:4500/`.
- After `rtk make dock-relay-restart`, the new relay was ready and registry
  backed, but the old Dock-owned raw app-server launchd job was still running
  on `127.0.0.1:4500`.
- Fixed `scripts/codex-dock-host-service.mjs` so install/start/restart/stop
  remove stale generated raw app-server service files and stop/disable the
  obsolete raw app-server job:
  - macOS launchd label: `com.aelaguiz.codex-dock.app-server`.
  - Linux systemd user unit: `codex-dock-app-server.service`.
- Command: `rtk node --test scripts/codex-dock-host-service.test.mjs`.
  Result: 28 tests, 0 failures.
- Command: `rtk npm test`.
  Result: projection contract fixtures/DTO current, 5 proof schemas and 5
  canonical samples validated; relay 209 tests, 0 failures; host/device
  service 37 tests, 0 failures.
