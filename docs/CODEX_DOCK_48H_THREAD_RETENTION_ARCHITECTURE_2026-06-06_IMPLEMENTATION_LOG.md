# Codex Dock 48h Thread Retention Implementation Log

Date: 2026-06-06
Plan: `docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06.md`
Audit: `docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06_PLAN_AUDIT.md`

## Status

Implementation complete; strict review complete; Node proof, canonical live
simulator proof, real-data realtime simulator proof, relay status, and relay
SQLite retention audit all passed. Relay deploy is pending.

## Slice Log

### IMP-001 Retention Policy Module

Status: complete

Scope:

- Add the production 48-hour retention constant.
- Export the existing relay activity timestamp helper so retention uses the same date semantics as card projection.
- Add a small relay retention policy module with test-only config override support.
- Add focused Node tests for the policy module.

Proof:

- `rtk node --test scripts/dock-relay-thread-retention.test.mjs` passed on 2026-06-06.

Findings:

- None.

### IMP-002 Relay List And Route Integration

Status: complete

Scope:

- Filter `thread/list` rows before `thread/read` enrichment.
- Stop `updated_at desc` pagination once a retained page hits the retention boundary.
- Filter session-index supplement candidates before `thread/read`.
- Keep live rows and hidden-live-child rollup parents through an explicit bypass set.
- Reject old direct routes before turns, archive/name mutations, and user-message persistence.

Proof:

- `rtk node --test scripts/dock-relay-thread-retention.test.mjs` passed on 2026-06-06 with 16 tests.
- `rtk npm run test:relay` passed on 2026-06-06 with 287 tests.

Findings:

- None.

### IMP-003 Full Node And Real Relay Proof

Status: complete

Scope:

- Run the current full Node proof gate.
- Run real relay-backed simulator proof.
- Check live relay status and retention database state.

Proof:

- `rtk npm test` passed on 2026-06-06:
  - `rtk npm run contract:check`
  - `rtk npm run test:docs`
  - `rtk npm run test:relay` with 287 tests
  - `rtk npm run test:host-service` with 37 tests
- `rtk make sim-ui-sync-proof SIM='iPhone 17'` passed on 2026-06-06.
  - Report: `/tmp/codex-client/sim-ui-audit-20260606T120502Z/simulator-ui-sync.md`
  - Relay report: `/tmp/codex-client/sim-ui-audit-20260606T120502Z/relay-client-path.md`
  - OK true; relay client-path OK true; 1440 displayed row checks; UI lag 1507 ms; failures none.
- `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` passed on 2026-06-06.
  - Rename relay report: `/tmp/codex-client/sim-ui-realdata-realtime-20260606T120638Z/rename-title/relay-client-path.md`
  - Rename simulator report: `/tmp/codex-client/sim-ui-realdata-realtime-20260606T120638Z/rename-title/simulator-ui-sync.md`
  - Archive relay report: `/tmp/codex-client/sim-ui-realdata-realtime-20260606T120638Z/archive-toggle/relay-client-path.md`
  - Archive simulator report: `/tmp/codex-client/sim-ui-realdata-realtime-20260606T120638Z/archive-toggle/simulator-ui-sync.md`
  - Rename: relay OK true, simulator OK true, 9225 displayed row checks, UI lag 737 ms, failures none.
  - Archive: relay OK true, simulator OK true, 12358 displayed row checks, UI lag 540 ms, failures none.
- `rtk make dock-relay-status` passed on 2026-06-06 after proof.
  - Local `127.0.0.1:4510/readyz`, local `statusz`, and app-facing `amir-m5.fairy-salmon.ts.net:4510/readyz` were OK.
- Retention database check passed on 2026-06-06.
  - Query result: `offendingCount: 0`.

Findings:

- The first real relay-backed simulator proof found a partial Dock state: retained
  list rows could still be marked incomplete when the route `thread/read`
  response had an older activity timestamp and the activity proof rechecked
  retention from that stale route row.
- Fixed by allowing internal activity proof to use the already accepted retained
  list row as its retention witness. Direct external routes still pass no
  accepted list row, so old non-live direct calls remain rejected before turns,
  mutations, or user-message persistence.
- A later realtime rename proof found a second stale-route witness path:
  `thread/name/set` could select a retained visible Dock card, then reject the
  route when its direct `thread/read` row had older activity.
- Fixed by allowing route assertions to use the authoritative app-facing Dock
  card as a retention witness. The fallback is gated by
  `isRouteAuthoritativeHumanCard`, so arbitrary objects cannot bypass the
  retention guard.
- Real relay-backed simulator proof passed after those fixes.

### IMP-004 Strict Review Follow-Through

Status: complete

Scope:

- Run `$thermo-nuclear-code-quality-review` after implementation and proof.
- Fix strict-review issues before commit.

Proof:

- `rtk node --test scripts/dock-relay-thread-retention.test.mjs` passed on 2026-06-06 with 16 tests.
- `rtk npm test` passed on 2026-06-06 with the full Node contract, docs, relay, and host-service proof gate.
- `rtk make sim-ui-sync-proof SIM='iPhone 17'` passed on 2026-06-06 after the default proof window was raised to `45000` ms UI sampling and `75000` ms relay sampling.
- `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` passed on 2026-06-06.
- Retention database check passed on 2026-06-06 with `offendingCount: 0`.

Findings:

- Strict review found that the app-facing-card fallback could treat an
  active-looking old card as live evidence. Fixed so a visible card only proves
  retention when it is age-retained; true live bypass still requires live route
  evidence or an explicit `dockRelayRetentionBypass` marker.
- Strict review found duplicated cutoff parsing in the thread data path. Fixed
  by centralizing cutoff normalization in
  `resolveThreadRetentionCutoffMs()` inside
  `scripts/dock-relay-thread-retention.mjs`.
- Canonical live simulator proof needed a longer default window under active
  real-data row churn. Fixed `Makefile` defaults so the canonical
  `rtk make sim-ui-sync-proof SIM='iPhone 17'` command now uses the same
  `45000` ms UI sampling and `75000` ms relay sampling that passed reliably.
