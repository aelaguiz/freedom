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

## 2026-06-05T02:17:34Z - Force relay restart during service deploy

- Home deploy found the same stale-process shape on systemd: the unit file was
  updated, but `systemctl --user start codex-dock-relay.service` left the
  already-running old relay PID active.
- Fixed `scripts/codex-dock-host-service.mjs` so `host-service-start` makes the
  running relay process current:
  - macOS uses `launchctl kickstart -k` when the loaded launchd job already
    points at the rendered relay plist.
  - Linux uses `systemctl --user restart codex-dock-relay.service` instead of
    `start`.
- Command: `rtk node --test scripts/codex-dock-host-service.test.mjs`.
  Result: 28 tests, 0 failures.
- Command: `rtk npm test`.
  Result: projection contract fixtures/DTO current, 5 proof schemas and 5
  canonical samples validated; relay 209 tests, 0 failures; host/device
  service 37 tests, 0 failures.

## 2026-06-05T03:03:57Z - Plain private Codex CLI session detection

- Root cause found after live-phone mismatch report: plain private Codex CLI
  sessions such as `codex -p yolo` do not expose the thread id in process
  arguments. The thread id is present in the open
  `~/.codex/sessions/**/*.jsonl` file.
- Fixed `scripts/dock-relay-app-server-registry.mjs` to scan open session files
  for Codex runtime PIDs with `lsof -w -Fpn -p <pid list>`, extract the session
  JSONL filename, and record those private owners as
  `ownerKind: "codex-cli-session-file"`.
- Added `APP_SERVER_REGISTRY_OPEN_SESSION_FILE_SCAN_LIMIT` in
  `scripts/dock-relay-constants.mjs`.
- Added regression coverage in
  `scripts/dock-relay-app-server-registry.test.mjs` for the exact
  plain-private-session shape.
- Command: `rtk npm run test:relay`.
  Result: 212 tests, 0 failures.
- Commit pushed:
  `1ee6a2c Detect plain Codex CLI private sessions`.

## 2026-06-05T03:16:00Z - Local and home live relay deploy proof

- Local Mac relay deployed and healthy at
  `ws://amir-m5.fairy-salmon.ts.net:4510`.
- Home relay pulled the pushed branch to `1ee6a2c` and restarted with
  `CODEX_DOCK_REAL_HOST_ID=home`, `CODEX_DOCK_REAL_HOST_NAME=Home`, and
  `APP_SERVER_HOST=home.fairy-salmon.ts.net`.
- Home relay healthy at `ws://home.fairy-salmon.ts.net:4510`.
- Live client-path probe:
  - `ws://amir-m5.fairy-salmon.ts.net:4510`: `281` rows, `10` running,
    `271` dormant.
  - `ws://home.fairy-salmon.ts.net:4510`: `981` total rows, first `250`
    received, `4` running, `246` dormant.

## 2026-06-05T03:20:19Z - Live relay simulator badge proof

- Relaunched the `iPhone 17` simulator against the two live relay hosts:
  `SIM_LAUNCH_HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
- Simulator installed build: `20260605031906`.
- The simulator UI showed `Online 2/2` and visible Dock rows with
  `Codex is working` badges.
- Accessibility dump artifact:
  `/tmp/codex-client/live-badge-ui-dump-20260605T031918Z/sim-ui-dump.json`.
- Screenshot artifact:
  `/tmp/codex-client/live-badge-sim-screenshot-20260605T032019Z.png`.
- The dump target reported blocked metadata because
  `CODEX_DOCK_AUTOMATION_SNAPSHOTS=1` was not set, but the written
  accessibility payload still contained visible row values with
  `status=running` and visible `Codex is working` labels.

## 2026-06-05T03:22:00Z - Physical iPhone blocker

- Physical iPhone app metadata reports installed build
  `20260605003015`, which does not match the simulator proof build
  `20260605031906`.
- Physical config readback command hung and was stopped:
  `rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`.
- Physical log collection failed with the exact blocker:
  `log: Must be root to collect logs from attached device`.
- Added focused bug note:
  `docs/bugs/codex-working-badge-phone-missing-2026-06-05.md`.

## 2026-06-05T03:31:10Z - Thermonuclear maintainability review fix

- Strict maintainability pass found that
  `scripts/dock-relay-app-server-registry.mjs` had grown to `1253` lines and
  mixed process discovery/session-file scanning with registry routing/state.
- Extracted Codex process discovery, endpoint normalization, daemon socket
  helpers, and status sanitization into
  `scripts/dock-relay-app-server-discovery.mjs`.
- Kept `scripts/dock-relay-app-server-registry.mjs` focused on registry
  refresh, owner leases, routing, live-row collection, and route errors.
- Resulting file sizes:
  - `scripts/dock-relay-app-server-registry.mjs`: `750` lines.
  - `scripts/dock-relay-app-server-discovery.mjs`: `537` lines.
- Focused proof:
  `rtk node --test scripts/dock-relay-app-server-registry.test.mjs scripts/dock-relay-json-rpc-client.test.mjs`
  passed with 10 tests and 0 failures.
- Full Node proof: `rtk npm test` passed.
  - Projection contract fixtures and generated Dock DTO are current.
  - Proof contracts: 5 schemas and 5 canonical samples validated.
  - Relay tests: 212 passed, 0 failed.
  - Host/device service tests: 37 passed, 0 failed.

## 2026-06-05T03:39:02Z - Current badge root-cause boundary

- Rechecked the current live relay client path:
  - `ws://amir-m5.fairy-salmon.ts.net:4510`: `282` rows, `11` running,
    `271` dormant.
  - `ws://home.fairy-salmon.ts.net:4510`: first `250` rows received, `4`
    running, `246` dormant.
- Verified iPhone 17 Pro saved relay config:
  `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
- Re-ran the `iPhone 17` simulator against those exact live hosts:
  `SIM_LAUNCH_HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
- Current simulator screenshot:
  `/tmp/codex-client/live-badge-current-sim-20260605T033902Z.png`.
- The screenshot shows `Online 2/2` and multiple visible real relay rows with
  `Codex is working` badges.
- Physical iPhone remains the only failing surface:
  - Installed build: `20260605003015`.
  - `rtk make device-launch DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`
    hung in `devicectl` and was stopped.
  - `rtk make device-debug-bundle DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E DEVICE_DEBUG_BUNDLE_DIR=/tmp/codex-client/device-debug-badge-20260605T034000Z`
    hung in `devicectl` and was stopped.
- Current root-cause boundary: not relay data, not saved phone host config, and
  not current Swift badge rendering. Remaining likely cause is physical
  phone-specific stale runtime/build state, but physical launch/log/diagnostic
  access is blocked from this session.
- Current relay refactor proof before commit:
  - `rtk node --check scripts/dock-relay-app-server-registry.mjs` passed.
  - `rtk node --check scripts/dock-relay-app-server-discovery.mjs` passed.
  - `rtk npm run test:relay` passed with 212 tests and 0 failures.
