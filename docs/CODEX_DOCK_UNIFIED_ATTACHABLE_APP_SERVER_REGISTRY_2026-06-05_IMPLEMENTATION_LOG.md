# Plan Implementation Log

Plan: `docs/CODEX_DOCK_UNIFIED_ATTACHABLE_APP_SERVER_REGISTRY_2026-06-05.md`
Audit log: `docs/CODEX_DOCK_UNIFIED_ATTACHABLE_APP_SERVER_REGISTRY_2026-06-05_PLAN_AUDIT.md`
Active scope: whole plan implementation
Last updated: 2026-06-05T13:22:13Z
Current checkpoint: implementation committed through `17ca123`, pushed, deployed on Mac and home, and proved in the iPhone 17 simulator against both relay hosts

## Resume Snapshot

- Current state: registry/discovery/proof-target slice is implemented, real-data detail routing is repaired, full relay tests pass, both relay services are ready, and the iPhone 17 simulator shows both hosts online with real rows and working detail drill-in.
- Next useful move: none for this goal.
- Do not redo unless stale: fresh consult at `/tmp/fresh-consult/codex-dock-unified-app-server-registry-20260605T111757Z-5aNFw4` returned `pass-with-notes` with no blocking findings, and accepted notes are carried into the plan.
- Known blockers: none for relay/app behavior. The strict JSON simulator snapshot oracle has a separate stale-snapshot harness issue and was not used as the final product proof.
- Native subagents used or useful next: none used for implementation; fresh consult completed before implementation.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Transport-neutral attachable endpoint selection | Phase 1 | implemented | `scripts/dock-relay-app-server-registry.mjs`, `scripts/dock-relay-app-server-discovery.mjs`, `scripts/dock-relay-json-rpc-client.mjs` | focused Node pass, full Node pass, simulator Unix fixture pass | thermonuclear review clean |
| Routing and badge truth | Phase 2 | implemented | `scripts/dock-relay-app-server-registry.mjs`, `scripts/dock-relay-state-views.mjs` | focused Node pass, full Node pass, simulator Unix fixture pass | thermonuclear review clean |
| State pipeline and detail proof | Phase 3 | implemented for proof-target guard and real-data detail route fallback | `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay.mjs` | focused real-data regression pass, full relay pass, real relay proof, simulator drill-in proof | thermonuclear review clean |
| Docs, deployment, drift closure | Phase 4 | deployed on Mac and home | bug doc, plan, audit, implementation log, deploy commands | full Node, live relay, and iPhone 17 simulator proof recorded | thermonuclear review clean |

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
| Full Node suite | Relay routing, state, projections, controlled fixture contracts, proof contracts, host-service config | `rtk npm run test:relay` passed 222/222 at 2026-06-05T13:17Z after the final detail route option cleanup. Earlier full and focused passes also covered the Unix owner registry and controlled simulator fixture. | any Node relay, proof, or host-service code changes | any touched Node relay/proof/host-service file |
| Focused real-data detail route regressions | Visible human/root cards whose later `thread/read` omits source or reports spawn metadata | `rtk node --test --test-name-pattern "visible human|omits source|reports spawn metadata" scripts/dock-relay-card-contract.test.mjs` passed 2/2 at 2026-06-05T13:17Z. | detail route guard, human filter, card contract, or relay detail routes change | any touched `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay.mjs`, or `scripts/dock-relay-card-contract.test.mjs` path |
| Real relay data proof | Mac and home relay APIs with current real Dock rows and detail routes | 2026-06-05T13:19Z: Mac `ws://127.0.0.1:4510` returned 287 rows, zero false working labels, and six real thread detail subscribe/resync probes succeeded. Home `ws://home.fairy-salmon.ts.net:4510` returned the first 250-row window with zero false working labels, and exact failing IDs `019e92de-05eb-7560-867c-f8d5f9c4a026`, `019e92de-1e46-7471-a7e8-3042ee1d9c2e`, `019e97b3-3438-7ef0-9bf1-51f9d3df04a1`, and `019e9227-85dc-7f73-9488-0e08440684d0` were visible human/root rows and detail subscribe/resync succeeded. | relay process restart, route guard, state projection, or real host config changes | deploy, restart, host config, or source classifier changes |
| Controlled simulator UI proof | Real simulator app UI through relay with Unix live-owner fixture | `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=live-lease-expiry` passed after the final JSON-RPC edge-case fix; report `/tmp/codex-client/sim-ui-audit-20260605T114855Z/simulator-ui-sync.json` status `pass`, `uiSampleCount=12`, `scenarioTransitionFailures=0`, `failures=0` | Swift UI, controlled fixture, relay state, registry, proof contract, or Makefile proof target changes | any touched app UI/proof/relay path or simulator config change |
| iPhone 17 simulator real-host proof | Installed app UI against both live relay hosts | 2026-06-05T13:21Z Mobile MCP on simulator `DEF1631B-7125-43C6-BFA3-4423BF103C91`: `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1 SIM_LAUNCH_HOSTS='127.0.0.1:4510,home.fairy-salmon.ts.net:4510'`; Dock showed `loaded; rows=1271`, `Online 2/2`; Mac group showed 287 sessions; Home group showed 984 sessions; visible Mac and home rows were `status=unknown`, `origin=human`, `relationship=root`, `label=none`; Mac and exact home failing row `019e92de-05eb-7560-867c-f8d5f9c4a026` opened Thread Detail with `Live` and real message rows. | Swift UI, relay host config, deployed relay code, or real host data changes | any app build, relay deployment, or host config change |

## Continuous Review Ledger

| Finding | Source | Status | Repair anchor | Notes |
| --- | --- | --- | --- | --- |
| TN-001 duplicate Unix JSON-RPC fixture server setup | thermonuclear implementation review | resolved | `scripts/dock-relay-test-helpers.mjs`, `scripts/dock-relay-json-rpc-client.test.mjs`, `scripts/dock-relay-app-server-registry.test.mjs`, `scripts/dock-relay-controlled-simulator-fixture.mjs` | Extracted `startUnixJsonRpcServer` so the Unix fixture behavior has one test-helper owner. |
| TN-002 stale detail route option name after real-data fallback expansion | final thermonuclear review | resolved | `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay.mjs` | Renamed `allowAppFacingCardForMissingSource` to `allowAppFacingCardRouteFallback` so the code name matches the policy for both `missing_source` and `not_base_level`. |
| SIM-HARNESS-001 strict JSON simulator snapshot oracle can race stale automation snapshot files | real simulator proof run | recorded separately | simulator proof harness | Product proof used Mobile MCP accessibility and live relay probes. The strict JSON oracle failure is a harness issue, not a relay/app data failure. |

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

### 2026-06-05T13:17:00Z - Final Detail Route Review Cleanup

- Intent: close the real-data detail routing regression without adding a second client path or Swift status.
- Changed: renamed the detail-route policy option from `allowAppFacingCardForMissingSource` to `allowAppFacingCardRouteFallback` after the final review found the old name no longer matched behavior once `not_base_level` fallback was added.
- Read: `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay.mjs`, `scripts/dock-relay-card-contract.test.mjs`, human-thread filter relationship classification, and Thread Detail header projection.
- Proof: `rtk node --test --test-name-pattern "visible human|omits source|reports spawn metadata" scripts/dock-relay-card-contract.test.mjs` passed 2/2.
- Proof: `rtk npm run test:relay` passed 222/222.
- Review: thermonuclear final review found TN-002 stale option naming; it is resolved. No open implementation findings remain.
- Commit: `17ca123` (`Clarify detail route fallback option`) was pushed to `origin/codex-dock-agents-tab-live-counts`.

### 2026-06-05T13:19:00Z - Deploy And Real Relay Proof

- Intent: get the pushed relay code live on both Mac and home and prove current real data routes correctly.
- Changed: restarted the Mac launchd relay with `rtk make dock-relay-restart`; pulled `17ca123` on home with `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && git fetch && git pull --ff-only'`; restarted the home relay with explicit Linux service settings because the Makefile default is macOS.
- Proof: Mac `rtk make dock-relay-status` returned `status=ready`, host `Amir-M5`, endpoint `amir-m5.fairy-salmon.ts.net:4510`, readyz/statusz OK, and no app-critical failures.
- Proof: home `rtk make host-service-status HOST_SERVICE_PLATFORM=linux CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home NODE_BIN=/home/aelaguiz/.local/bin/node APP_SERVER_HOST=home.fairy-salmon.ts.net DOCK_RELAY_WS=ws://home.fairy-salmon.ts.net:4510` returned `status=ready`, host `home`, systemd-user relay active, readyz/statusz OK, and no app-critical failures.
- Proof: real relay probe at 2026-06-05T13:19Z showed Mac 287 rows, zero false working labels, and six real Mac threads opened detail and resynced.
- Proof: real relay probe at 2026-06-05T13:19Z showed home first-page rows had zero false working labels, and exact previously failing home IDs `019e92de-05eb-7560-867c-f8d5f9c4a026`, `019e92de-1e46-7471-a7e8-3042ee1d9c2e`, `019e97b3-3438-7ef0-9bf1-51f9d3df04a1`, and `019e9227-85dc-7f73-9488-0e08440684d0` were visible human/root rows and opened detail/resynced.
- Review: deployment issue found and resolved; home must be invoked with explicit `HOST_SERVICE_PLATFORM=linux` until the Makefile default is made platform-aware.

### 2026-06-05T13:21:00Z - iPhone 17 Simulator Real-Host Proof

- Intent: prove the installed simulator app, not only unit tests or relay APIs.
- Changed: relaunched the iPhone 17 simulator app with `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1 SIM_LAUNCH_HOSTS='127.0.0.1:4510,home.fairy-salmon.ts.net:4510'`.
- Proof: Mobile MCP on simulator `DEF1631B-7125-43C6-BFA3-4423BF103C91` showed Dock root `loaded; rows=1271`, `Online 2/2`, Mac host group with 287 sessions, and Home host group with 984 sessions.
- Proof: visible Mac rows and visible home rows showed `status=unknown`, `origin=human`, `relationship=root`, and `label=none`, so the false `Codex is working` badge was not present for those non-running real rows.
- Proof: tapped real Mac row `019e9482-fe61-7af0-a870-2c2df5089667`; Thread Detail opened with host `127.0.0.1:4510`, `Live`, the exact thread ID, composer controls, and real message rows.
- Proof: tapped exact home row `019e92de-05eb-7560-867c-f8d5f9c4a026`; Thread Detail opened with host `home.fairy-salmon.ts.net:4510`, `Live`, the exact thread ID, composer controls, and real message rows.
- Review: simulator proof used Mobile MCP accessibility because the strict JSON simulator snapshot oracle has a separate stale-snapshot harness issue.
