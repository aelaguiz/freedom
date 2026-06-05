# Plan Audit Log

Plan: `docs/THREAD_DETAIL_NO_WIPE_REFRESH_ARCHITECTURE_2026-06-05.md`
Audit log: `docs/THREAD_DETAIL_NO_WIPE_REFRESH_ARCHITECTURE_2026-06-05_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: ready
Last reviewed: 2026-06-05T17:56:00Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

No blocking implementation findings.

Implementation review checked the retained Thread Detail owner, caller cache, proof harness, and route evidence against the plan. `ThreadDetailStore.swift` remains under the 1,000-line guard at 999 lines.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/State/ThreadDetailStore.swift`; `ThreadDetailStore.load()`, `close()`, `observeDockRowUpdate(_:)`, `ThreadDetailLiveState`, lifecycle handlers | Owns detail content, local state, projection session, repeated load behavior, and the destructive close path the plan changes. | Parent | read |
| Render owner path | `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift`; `ThreadDetailRenderProjector`; `ThreadDetailRenderModels` | Proves loaded rows can remain visible while live state changes, without adding a parallel view-model cache. | Parent | read |
| Projection/resync owner path | `CodexDock/Projection/StreamReconciler.swift`; `ThreadDetailProjectionStreamConnector` | Confirms existing `manualRefresh()` and `thread/detail/resync` already implement no-wipe catchup. | Parent | read |
| Caller families | `CodexDock/Features/Dock/DockView.swift`; `CodexDock/Features/Archive/ArchiveView.swift`; `CodexDock/Runtime/ClientRuntime.swift` | Dock and Archive currently create fresh stores and clear selected store on pop; runtime factory stays the existing creation path. | Parent | read |
| UI state/proof surfaces | `CodexDock/Features/Session/SessionDetailView.swift`; `CodexDock/Automation/AutomationID.swift`; `CodexDockUITests/DisplayedUICaptureSupport.swift`; `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` | Confirms `loading` automation ID, header live value, message list value, and controlled UI capture can prove retained content. | Parent | read |
| Contract and side-door paths | `CodexDock/AppServer/AppServerMethods.swift`; `scripts/dock-relay-app-server-registry.mjs`; `scripts/proof-report-contracts.mjs`; `scripts/dock-relay.mjs` route handlers by search | Confirms production detail routes stay `thread/detail/subscribe`, `thread/detail/update`, and `thread/detail/resync`; `thread/detail/read` remains a forbidden proof side door. | Parent | read |
| Controlled simulator fixture surfaces | `scripts/dock-relay-controlled-simulator-fixture.mjs`; `scripts/dock-relay-controlled-simulator-fixture.test.mjs`; `scripts/dock-relay-controlled-simulator-matrix.mjs` | Confirms existing scenario harness can add a delayed resync and matrix route expectations. | Parent | read |
| Tests | `CodexDockTests/ThreadDetailStoreTests.swift`; `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`; `CodexDockTests/ThreadDetailScreenStoreTests.swift`; `CodexDockTests/ProjectionRuntimeTests.swift`; relay fixture/matrix tests by search | Confirms focused unit coverage already exists around store lifecycle, reconnect, projection catchup, and controlled proof contracts. | Parent | read |
| Constants/config | `CodexDock/Configuration/CodexDockConstants.swift`; repo `AGENTS.md` instructions | Confirms production cache capacity must live under constants and simulator/device proof must use Makefile-owned commands. | Parent | read |

Native subagents were not used for this audit pass because the current tool policy only allows spawning agents when the current user explicitly asks for subagents or parallel agents in the active task. The audit used local parallel file reads instead.

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

Conditional lenses:

- `docs-contract-drift`: triggered because stable automation values and test coverage docs may change. The plan names the affected UI test and docs surfaces.
- `security-boundary`: lightly triggered because relay/app-server routes and phone paths are in scope. The plan keeps secrets Mac-side and makes no raw app-server or `thread/detail/read` phone path.
- `agent-capability`: not triggered; no prompts, agents, MCP, or model-facing behavior changes.

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| AD-001 | Should retained detail survive app termination? | Persist to disk vs retain only in current app process. | Persistence would add cache serialization, invalidation, and privacy scope. | Current process only. | Plan author | Non-requirements say no persistence across app termination. | resolved |
| AD-002 | Should updating be a new loading screen or a loaded-state status? | Blank progress view vs header pill on existing content. | Blank progress repeats the bug. | Loaded-state status only. | Plan author | Target Architecture sections 2, 5, and 7 require `Updating` without `.loading`. | resolved |
| AD-003 | Should the relay change? | Add route/cache vs reuse `thread/detail/resync`. | Relay changes would increase protocol drift and deployment risk. | No relay protocol change. | Plan author | North Star and Target Architecture section 6 keep the existing resync route. | resolved |

## Pass History

### Pass 1 - 2026-06-05T16:46:53Z

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: worktree at branch `codex-dock-agents-tab-live-counts`
- Test/CI context accepted, if supplied: none
- Agents/lenses run: local parent audit; no native subagents due tool policy constraint noted above
- Code areas read: see coverage ledger
- Findings added: none
- Findings resolved: plan was patched before audit to put retained cache capacity under `CodexDockConstants.ThreadDetail.retainedStoreCapacity` and to forbid duplicate retained refreshes
- Findings carried forward: none
- Verdict: ready
- Next audit focus: after implementation, run `plan-audit` in implementation-audit mode against the code and this plan

### Pass 2 - 2026-06-05T16:47:49Z

- Mode: plan-readiness follow-up after thermo-nuclear design review
- Scope: Phase 1 file-size guard
- Baseline reviewed: `ThreadDetailStore.swift` line count is 959 before implementation
- Test/CI context accepted, if supplied: none
- Agents/lenses run: thermo-nuclear maintainability lens locally
- Code areas read: `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/Features/Dock/DockView.swift`, `CodexDock/Features/Archive/ArchiveView.swift`
- Findings added: none
- Findings resolved: plan now requires keeping `ThreadDetailStore.swift` below 1,000 lines and extracting pure state/model declarations first if retained-refresh code would cross that boundary
- Findings carried forward: none
- Verdict: ready
- Next audit focus: after implementation, confirm file-size guard and cache extraction were honored

### Pass 3 - 2026-06-05T17:56:00Z

- Mode: implementation-audit
- Scope: completed retained Thread Detail no-wipe implementation
- Baseline reviewed: worktree on `codex-dock-agents-tab-live-counts`
- Test/CI context accepted:
  - `rtk wc -l CodexDock/State/ThreadDetailStore.swift` -> `999`
  - `rtk swift test --filter ThreadDetailStoreTests` -> passed
  - `rtk swift test --filter ThreadDetailStoreCacheTests` -> passed
  - `rtk swift test --filter ThreadDetailScreenStoreTests` -> passed
  - `rtk npm run test:relay` -> passed
  - `rtk npm run contract:check` -> passed
  - `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-reopen-retains-content` -> passed
  - `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` -> passed; aggregate report `/tmp/codex-client/sim-ui-controlled-matrix-run-20260605T172812Z/controlled-simulator-matrix.json`
- Code areas read: retained store model extraction, `ThreadDetailStore`, `ThreadDetailStoreCache`, Dock/Archive callers, Session Detail lifecycle, simulator proof harness, relay proof evaluator, test coverage docs
- Findings added: none
- Findings resolved: TN-001 file-size guard satisfied; retained reopen proof shows `thread/detail/subscribe: 1` and retained `thread/detail/resync`
- Findings carried forward: none
- Verdict: ready
- Next audit focus: deployment verification after push
