# Plan Implementation Log

Plan: `docs/CODEX_DOCK_UNIFIED_ATTACHABLE_APP_SERVER_REGISTRY_2026-06-05.md`
Audit log: `docs/CODEX_DOCK_UNIFIED_ATTACHABLE_APP_SERVER_REGISTRY_2026-06-05_PLAN_AUDIT.md`
Active scope: whole plan implementation
Last updated: 2026-06-05T11:49:27Z
Current checkpoint: implementation reviewed; commit, push, and deployment pending

## Resume Snapshot

- Current state: registry/discovery/proof-target slice is implemented, full Node tests pass, controlled simulator UI proof passes against a Unix live-owner fixture, and thermonuclear implementation review is clean.
- Next useful move: commit, push, and deploy the relay on both hosts.
- Do not redo unless stale: fresh consult at `/tmp/fresh-consult/codex-dock-unified-app-server-registry-20260605T111757Z-5aNFw4` returned `pass-with-notes` with no blocking findings, and accepted notes are carried into the plan.
- Known blockers: none.
- Native subagents used or useful next: none used for implementation; fresh consult completed before implementation.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Transport-neutral attachable endpoint selection | Phase 1 | implemented | `scripts/dock-relay-app-server-registry.mjs`, `scripts/dock-relay-app-server-discovery.mjs`, `scripts/dock-relay-json-rpc-client.mjs` | focused Node pass, full Node pass, simulator Unix fixture pass | thermonuclear review clean |
| Routing and badge truth | Phase 2 | implemented | `scripts/dock-relay-app-server-registry.mjs`, `scripts/dock-relay-state-views.mjs` | focused Node pass, full Node pass, simulator Unix fixture pass | thermonuclear review clean |
| State pipeline and detail proof | Phase 3 | implemented for proof-target guard | `scripts/dock-relay-sync-audit.mjs` | focused Node pass, full Node pass | thermonuclear review clean |
| Docs, deployment, drift closure | Phase 4 | docs updated, deployment pending | bug doc, plan, audit, implementation log, deploy commands | full Node and simulator proof recorded | thermonuclear review clean |

## Code Read Ledger

| Area | Files/symbols read | Why relevant | Fresh until | Notes |
| --- | --- | --- | --- | --- |
| Registry owner path | `scripts/dock-relay-app-server-registry.mjs`: `refresh`, `liveEndpoints`, `privateLiveRows`, `recordLiveRows`, `routeForThreadMethod` | owns endpoint probing, leases, private diagnostics, and routing | registry code changes | Current live filter is WebSocket-only and private routing precedes owner leases. |
| Discovery and Unix normalization | `scripts/dock-relay-app-server-discovery.mjs`: `normalizeAppServerEndpoint`, `unixSocketPathForEndpointURL`, process discovery | owns process endpoint descriptors and socket paths | discovery/client code changes | Current relative `unix://PATH` can normalize differently from upstream. |
| JSON-RPC Unix adapter | `scripts/dock-relay-json-rpc-client.mjs`: `unixSocketPathFromURL`, `webSocketURLForEndpoint` | connects Unix sockets through `ws+unix` | client/discovery code changes | Existing adapter handles Unix, but relative path behavior needs alignment. |
| Detail proof target selection | `scripts/dock-relay-sync-audit.mjs`: `selectDetailTargets`, `probeDetailTargets` | proof must not count private-only rows as healthy running detail | sync-audit code changes | Current selection takes all rows by thread id. |
| Existing tests | `scripts/dock-relay-app-server-registry.test.mjs`, `scripts/dock-relay-json-rpc-client.test.mjs` | focused proof surface for registry/client behavior | tests change | Existing tests cover WebSocket live and Unix history, not Unix owner probing. |

## Proof Freshness Ledger

| Proof | Scope covered | Result/context | Fresh until | Rerun trigger |
| --- | --- | --- | --- | --- |
| Fresh consult | Architecture and test plan | `pass-with-notes`, no blocking findings | plan source truth changes | new architecture decision, new blocking plan finding, or changed test strategy |
| Plan audit | Plan readiness | `ready` after Pass 2 | plan source truth changes | new plan requirement, consult blocker, or implementation-discovered plan gap |
| Focused Node relay tests | Registry, Unix JSON-RPC client, sync-audit detail target selection | `rtk node --test scripts/dock-relay-json-rpc-client.test.mjs scripts/dock-relay-app-server-registry.test.mjs scripts/dock-relay-sync-audit.test.mjs` passed 26/26 | relay registry/client/sync-audit code or tests change | any touched file in that command set, route precedence review finding, or Unix path review finding |
| Focused Unix fixture tests | Registry, Unix JSON-RPC client, controlled simulator fixture | `rtk node --test scripts/dock-relay-json-rpc-client.test.mjs scripts/dock-relay-app-server-registry.test.mjs scripts/dock-relay-controlled-simulator-fixture.test.mjs` passed 34/34 after shared helper extraction and bare `unix://` guard | controlled fixture, registry, JSON-RPC client, or shared test-helper code changes | any touched file in that command set |
| Full Node suite | Relay routing, state, projections, controlled fixture contracts, proof contracts, host-service config | `rtk npm test` passed: relay 217/217 and host-service 37/37. An earlier full run hit the known rename-transition flake, then `scripts/dock-relay-card-contract.test.mjs` passed 13/13 and the next full run passed cleanly. | any Node relay, proof, or host-service code changes | any touched Node relay/proof/host-service file |
| Controlled simulator UI proof | Real simulator app UI through relay with Unix live-owner fixture | `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=live-lease-expiry` passed after the final JSON-RPC edge-case fix; report `/tmp/codex-client/sim-ui-audit-20260605T114855Z/simulator-ui-sync.json` status `pass`, `uiSampleCount=12`, `scenarioTransitionFailures=0`, `failures=0` | Swift UI, controlled fixture, relay state, registry, proof contract, or Makefile proof target changes | any touched app UI/proof/relay path or simulator config change |

## Continuous Review Ledger

| Finding | Source | Status | Repair anchor | Notes |
| --- | --- | --- | --- | --- |
| TN-001 duplicate Unix JSON-RPC fixture server setup | thermonuclear implementation review | resolved | `scripts/dock-relay-test-helpers.mjs`, `scripts/dock-relay-json-rpc-client.test.mjs`, `scripts/dock-relay-app-server-registry.test.mjs`, `scripts/dock-relay-controlled-simulator-fixture.mjs` | Extracted `startUnixJsonRpcServer` so the Unix fixture behavior has one test-helper owner. |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| WebSocket-only `liveEndpoints()` filter | Replaced by attachable owner-probe endpoint rule | `liveEndpoints()` now probes healthy Unix endpoints and live-labeled `ws`/`wss` endpoints | closed | `scripts/dock-relay-app-server-registry.mjs` |
| Private `status.type = "active"` | Private-only rows normalize to Dock `unknown` | `privateLiveRows()` emits `privateUnattachable`, which normalizes to `unknown` | closed | `scripts/dock-relay-app-server-registry.mjs` |
| Private owner routing precedence | Attachable lease wins before private rejection | `routeForThreadMethod()` checks owner lease before private rejection and private rejection only applies when no owner exists | closed | `scripts/dock-relay-app-server-registry.mjs` |
| Detail proof row selection | Private-only `unknown` rows skipped or expected-diagnostic | `selectDetailTargets()` skips `unknown` rows | closed | `scripts/dock-relay-sync-audit.mjs` |

## Decision Carry-Through

| Decision | Owner | Plan carry-through | Code carry-through | Status |
| --- | --- | --- | --- | --- |
| One attachable owner-probe path for Unix endpoints and live `ws`/`wss` endpoints | plan | Requirements 1-4, Target Architecture 1-2 | implemented in registry endpoint selection | implemented |
| `stdio://` remains private diagnostic-only | plan | Requirements 3, 6, Non-Requirements | implemented through private diagnostics and non-running rows | implemented |
| Private-only rows use existing Dock `unknown` status | plan | Target Architecture 4 | implemented with `privateUnattachable` upstream status | implemented |
| Relative Unix paths must not silently resolve to the wrong socket | consult/plan | Requirement 12, Test Plan item 8 | implemented through cwd-aware normalization and diagnostic failure when cwd is unknown | implemented |

## Pass Notes

### 2026-06-05T12:02:00Z - Implementation Start

- Intent: start code implementation from the audited plan.
- Changed: created implementation log only.
- Read: plan, audit log, fresh consult output, registry/discovery/client/sync-audit anchors.
- Proof: no implementation proof run yet.
- Review: no implementation findings opened.
- Next: implement the registry/discovery depth-first slice.

### 2026-06-05T12:12:00Z - Registry And Proof-Target Slice

- Intent: make the core attachability model true before broad verification.
- Changed: registry owner-probe endpoint selection now admits healthy `unix`, `ws`, and `wss`; Unix path normalization handles daemon, absolute, and cwd-known relative sockets; private-only rows emit `privateUnattachable`; owner leases outrank private diagnostics; sync audit skips `unknown` detail targets.
- Read: registry, discovery, JSON-RPC client, thread-data merge, state-view status normalization, sync-audit target selection, focused tests.
- Proof: focused Node relay tests passed 26/26.
- Review: warm self-review found and fixed one real precedence detail where private evidence still blocked history routing despite an owner lease.
- Next: run full relay suite and update audit/docs/proof state.

### 2026-06-05T11:39:24Z - Full Relay And Simulator Proof

- Intent: prove the fix against broad relay behavior and real simulator UI, not only the registry unit seam.
- Changed: controlled simulator `live-lease-expiry` fixture now exposes the live owner over `unix://`; its socket path was moved to `/tmp/codex-client/cdrlive-<pid>-<time>.sock` after the simulator proof exposed macOS `listen EINVAL` on a longer `/var/folders/...` socket path.
- Read: controlled simulator fixture, proof report contracts, Makefile simulator proof target, generated simulator proof reports.
- Proof: `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs scripts/dock-relay-app-server-registry.test.mjs scripts/dock-relay-json-rpc-client.test.mjs` passed 33/33.
- Proof: `rtk npm run test:relay` passed 216/216 after all relay edits. One earlier full-suite run hit an unrelated transient title-transition assertion; `scripts/dock-relay-card-contract.test.mjs` passed 13/13 alone and the next full relay suite passed 216/216.
- Proof: `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=live-lease-expiry` passed. The simulator proof report is `/tmp/codex-client/sim-ui-audit-20260605T113826Z/simulator-ui-sync.json`; it has `status=pass`, `uiSampleCount=12`, `scenarioTransitionCount=1`, `scenarioTransitionFailures=0`, and `failures=0`.
- Review: implementation audit still pending.
- Next: run implementation audit/code review, then commit, push, and deploy.

### 2026-06-05T11:49:27Z - Review Cleanup And Fresh Proof

- Intent: close thermonuclear implementation review before commit.
- Changed: extracted duplicated Unix JSON-RPC fixture setup into `startUnixJsonRpcServer` in `scripts/dock-relay-test-helpers.mjs`, then rewired registry, JSON-RPC client, and controlled simulator fixture tests to use it. Also fixed `unixSocketPathFromURL("unix://")` so a bare Unix URL fails instead of resolving to the relay working directory.
- Read: shared test helpers, registry tests, JSON-RPC client tests, controlled simulator fixture, implementation diff.
- Proof: `rtk node --test scripts/dock-relay-json-rpc-client.test.mjs scripts/dock-relay-app-server-registry.test.mjs scripts/dock-relay-controlled-simulator-fixture.test.mjs` passed 34/34.
- Proof: `rtk node --test scripts/dock-relay-card-contract.test.mjs` passed 13/13 after one full-suite run hit the known rename-transition flake.
- Proof: `rtk npm test` passed; relay tests passed 217/217 and host-service tests passed 37/37.
- Proof: `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=live-lease-expiry` passed. The simulator proof report is `/tmp/codex-client/sim-ui-audit-20260605T114855Z/simulator-ui-sync.json`; it has `status=pass`, `uiSampleCount=12`, `scenarioTransitionCount=1`, `scenarioTransitionFailures=0`, and `failures=0`.
- Review: thermonuclear implementation review found TN-001 duplicate helper setup; it is resolved. No open implementation findings remain.
- Next: commit, push, and deploy.
