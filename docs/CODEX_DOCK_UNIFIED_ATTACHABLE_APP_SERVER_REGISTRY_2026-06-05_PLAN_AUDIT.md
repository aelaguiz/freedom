# Plan Audit Log

Plan: `docs/CODEX_DOCK_UNIFIED_ATTACHABLE_APP_SERVER_REGISTRY_2026-06-05.md`
Audit log: `docs/CODEX_DOCK_UNIFIED_ATTACHABLE_APP_SERVER_REGISTRY_2026-06-05_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: pass
Last reviewed: 2026-06-05T13:22:13Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

None. Thermonuclear implementation review found TN-001 duplicate Unix JSON-RPC fixture helper setup and TN-002 stale detail-route option naming after the real-data fallback expansion; both are resolved.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `scripts/dock-relay-app-server-registry.mjs`: `refresh`, `liveEndpoints`, `privateLiveRows`, `collectLiveRows`, `readLoadedRowsFromEndpoint`, `routeForThreadMethod` | Owns endpoint selection, live owner leases, private diagnostics, and thread route selection | parent | read |
| Discovery and endpoint normalization | `scripts/dock-relay-app-server-discovery.mjs`: `normalizeAppServerEndpoint`, `discoverAppServerEndpointsFromProcesses` | Shows Unix is normalized but process-discovered Unix app-servers are classified as history | parent | read |
| Transport adapter | `scripts/dock-relay-json-rpc-client.mjs`, `scripts/dock-relay-json-rpc-client.test.mjs` | Proves Dock already has a transport adapter for Unix app-server JSON-RPC | parent | read |
| Relay caller families | `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay.mjs` | Shows live status, detail subscribe, detail resume, and thread method callers already route through the registry | parent | read |
| Card status and badge contract | `scripts/dock-relay-state-views.mjs`, `CodexDock/Dock/DockModels.swift`, `CodexDock/AppServer/DockThreadCardDTO.swift`, `CodexDock/State/ThreadCardRowProjector.swift` | Shows `active` becomes Dock `running`, and `running` renders as `Codex is working` | parent | read |
| Observability and route health | `scripts/dock-relay-observability-contract.mjs`, `scripts/dock-relay-observability.mjs`, `scripts/dock-relay-status.mjs` | Shows `thread/detail/subscribe` is passive-only but app-critical and contributes to status failures | parent | read |
| Proof/detail target selection | `scripts/dock-relay-sync-audit.mjs`, `scripts/proof-report-contracts.mjs` | Shows detail probes select Dock rows and passing proof must include relay-owned client routes | parent | read |
| Existing relay tests | `scripts/dock-relay-app-server-registry.test.mjs`, `scripts/dock-relay-json-rpc-client.test.mjs` | Shows current WebSocket live-owner tests, Unix history tests, private owner tests, and gap for Unix live-owner tests | parent | read |
| Upstream Codex transport and owner semantics | `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md`, `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs`, `/Users/aelaguiz/workspace/codex/codex-rs/app-server-client/src/remote.rs`, `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs`, `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs`, `/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs` | Grounds the plan in Codex's actual supported transports, process-local loaded thread state, and remote Unix support | parent | read |
| Runtime evidence | `codex app-server --help`, `ps`, `rtk make dock-relay-status`, `rtk make app-server-status`, `~/.codex/app-server-control/app-server-control.sock` | Confirms installed Codex supports the planned transports and current status is failing at live-upstream detail route | parent | read |
| Docs and drift surfaces | `README.md`, `docs/bugs/private-codex-runtime-thread-detail-unavailable-2026-06-05.md`, `docs/CODEX_DOCK_APP_SERVER_REGISTRY_HARD_CUT_2026-06-05.md`, `docs/CODEX_DOCK_APP_SERVER_REGISTRY_HARD_CUT_2026-06-05_WORKLOG.md` | Shows current docs still teach WebSocket-only live owners and capture the bug evidence | parent | read |

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses, if triggered

Conditional lenses run:

- `docs-contract-drift`, because the plan changes README/runbook language and proof expectations.
- `security-boundary`, because endpoint discovery touches local sockets, loopback policy, bearer tokens, and process diagnostics.

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Should private-only rows get a new Swift status or reuse an existing one? | Add a new `private`/`unattachable` status, or reuse an existing non-running status. | New status increases Swift/contract churn; reused status fixes false badge faster. | Reuse existing Swift contract and make private-only rows normalize to Dock `unknown`. | agent, based on repo evidence and user goal | Plan lines requiring Dock `unknown` for private-only rows and no new Swift status unless product copy demands it. | resolved |
| DEC-002 | Should the registry create a separate Unix live path? | Add Unix-specific routing, or make live-owner probing transport-neutral. | Separate path preserves bifurcation and risks drift. | Use one attachable owner-probe path for `unix`, `ws`, and `wss`. | agent, based on repo evidence and user goal | Plan North Star, endpoint role rule, and one owner lease path. | resolved |
| DEC-003 | Can Dock attach to `stdio://` runtimes? | Treat `stdio://` as live because the process is active, or diagnostic-only because parent owns the stream. | Incorrect attachability creates false running status and impossible detail opens. | `stdio://` remains private diagnostic-only unless upstream Codex exposes a shareable endpoint. | agent, based on Codex transport evidence | Plan requirements and non-requirements. | resolved |

## Pass History

### Pass 1 - 2026-06-05T11:27:00Z

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: current worktree plus upstream Codex checkout under `/Users/aelaguiz/workspace/codex`
- Test/CI context accepted, if supplied: current status checks show relay process alive but route health not ready because `thread/detail/subscribe` failed at `live-upstream`
- Agents/lenses run: parent-only audit; native subagents not used because the current plan scope is narrow and a required independent fresh consult follows this pass
- Code areas read: see coverage ledger
- Findings added: PLA-NB-001
- Findings resolved: DEC-001, DEC-002, DEC-003
- Findings carried forward: PLA-NB-001
- Verdict: ready
- Next audit focus: re-audit after the `gpt-5.5` `xhigh` fresh consult output is folded into the plan

### Pass 2 - 2026-06-05T11:58:00Z

- Mode: plan-readiness after fresh consult
- Scope: whole plan plus fresh consult output
- Fresh consult command: `codex exec --ephemeral --disable codex_hooks -C /Users/aelaguiz/workspace/codex-client --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --model gpt-5.5 -c model_reasoning_effort='"xhigh"' --json`
- Fresh consult run directory: `/tmp/fresh-consult/codex-dock-unified-app-server-registry-20260605T111757Z-5aNFw4`
- Fresh consult verdict: `pass-with-notes`
- Blocking findings from consult: none
- Non-blocking notes accepted:
  - proof must skip or expected-fail private-only `unknown` rows instead of counting them as healthy detail proof;
  - add same-thread private-plus-attachable merge/status tests;
  - decide and test relative `unix://PATH` handling;
  - repair README/bug-doc/runbook wording before implementation exits;
  - use `rtk ssh home` for home deployment from the Mac checkout.
- Plan repairs made:
  - added Requirement 12 for upstream-matching Unix URL normalization and relative-path diagnostics;
  - tightened Phase 2 proof wording for private-only detail probes;
  - expanded focused Node tests for same-thread merge status and Unix path normalization;
  - tightened controlled simulator proof language for Unix detail routing;
  - replaced the raw `ssh home` deployment command with `rtk ssh home`.
- Findings resolved: PLA-NB-001
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation audit after code and tests are changed

### Pass 3 - 2026-06-05T11:49:27Z

- Mode: implementation code-review
- Scope: implemented relay registry/discovery/client/proof-target changes plus tests and docs
- Review style: thermonuclear implementation review, focused on structural quality, hidden bifurcation, side doors, duplicate helpers, and proof quality
- Tests/proof accepted:
  - `rtk node --test scripts/dock-relay-json-rpc-client.test.mjs scripts/dock-relay-app-server-registry.test.mjs scripts/dock-relay-controlled-simulator-fixture.test.mjs` passed 34/34.
  - `rtk node --test scripts/dock-relay-card-contract.test.mjs` passed 13/13 after one full-suite run hit the known rename-transition flake.
  - `rtk npm test` passed; relay tests passed 217/217 and host-service tests passed 37/37.
  - `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=live-lease-expiry` passed with report `/tmp/codex-client/sim-ui-audit-20260605T114855Z/simulator-ui-sync.json`, `status=pass`, `uiSampleCount=12`, `scenarioTransitionFailures=0`, and `failures=0`.
- Implementation finding opened: TN-001 duplicate Unix JSON-RPC fixture server setup across tests and controlled simulator fixture.
- Repair made: extracted shared `startUnixJsonRpcServer` in `scripts/dock-relay-test-helpers.mjs`; registry tests, JSON-RPC client tests, and controlled simulator fixture now share it. The final review also caught and fixed a bare `unix://` JSON-RPC client guard.
- Findings carried forward: none
- Verdict: pass
- Next audit focus: deployment verification on Mac and home relay servers

### Pass 4 - 2026-06-05T13:22:13Z

- Mode: final implementation/deployment audit
- Scope: final real-data detail routing fix, naming cleanup, real relay proof, and iPhone 17 simulator proof
- Review style: thermonuclear implementation review focused on structural drift, hidden second paths, over-broad fallback, stale naming, and proof quality
- Code areas read: `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay.mjs`, `scripts/dock-relay-card-contract.test.mjs`, `scripts/dock-relay-human-thread-filter.mjs`, `scripts/dock-relay-state-views.mjs`, `CodexDock/State/ThreadDetailStore.swift`, and `CodexDock/Features/Session/SessionDetailView.swift`
- Tests/proof accepted:
  - `rtk node --test --test-name-pattern "visible human|omits source|reports spawn metadata" scripts/dock-relay-card-contract.test.mjs` passed 2/2.
  - `rtk npm run test:relay` passed 222/222.
  - Mac relay was restarted and `rtk make dock-relay-status` returned `status=ready` with no app-critical failures.
  - Home relay pulled `17ca123`, restarted through systemd-user with explicit Linux service settings, and `host-service-status` returned `status=ready` with no app-critical failures.
  - Real relay probe showed Mac 287 rows with zero false working labels and six real Thread Detail subscribe/resync probes succeeding.
  - Real relay probe showed exact home failing IDs `019e92de-05eb-7560-867c-f8d5f9c4a026`, `019e92de-1e46-7471-a7e8-3042ee1d9c2e`, `019e97b3-3438-7ef0-9bf1-51f9d3df04a1`, and `019e9227-85dc-7f73-9488-0e08440684d0` as visible human/root rows with detail subscribe/resync succeeding.
  - iPhone 17 simulator `DEF1631B-7125-43C6-BFA3-4423BF103C91` showed `loaded; rows=1271`, `Online 2/2`, Mac group 287 sessions, Home group 984 sessions, no false working label on visible non-running rows, and working detail drill-in for both a Mac row and exact home failing row `019e92de-05eb-7560-867c-f8d5f9c4a026`.
- Implementation finding opened: TN-002 stale option name `allowAppFacingCardForMissingSource` after fallback grew from `missing_source` to `missing_source` plus `not_base_level`.
- Repair made: renamed the option to `allowAppFacingCardRouteFallback`; focused and full relay tests passed after the rename.
- Deployment finding opened: home Makefile defaults to macOS service settings, so a plain `rtk make host-service-restart` on home attempted `launchctl` and failed with exit 127.
- Repair made: restarted home with explicit `HOST_SERVICE_PLATFORM=linux`, `CODEX_DOCK_REAL_HOST_ID=home`, `CODEX_DOCK_REAL_HOST_NAME=Home`, `NODE_BIN=/home/aelaguiz/.local/bin/node`, `APP_SERVER_HOST=home.fairy-salmon.ts.net`, and `DOCK_RELAY_WS=ws://home.fairy-salmon.ts.net:4510`.
- Findings carried forward: none for relay/app behavior. SIM-HARNESS-001 remains a separate strict JSON snapshot oracle issue and is not a product relay blocker.
- Verdict: pass
- Next audit focus: none for this goal
