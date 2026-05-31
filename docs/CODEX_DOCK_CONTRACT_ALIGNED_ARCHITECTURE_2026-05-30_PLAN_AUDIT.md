# Plan Audit Log

Plan: `docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md`
Audit log: `docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-05-30T21:57:16Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

Not run. The user explicitly requested planning and audit only, with no
implementation.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `scripts/dock-relay-state-views.mjs`, `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-subscriptions.mjs`, `scripts/dock-relay.mjs` | Relay owns card truth, ordering, persistence, stream payloads, and route methods. | parent and Composer consult | read |
| Swift stream and Dock callers | `CodexDock/AppServer/DockStreamDTO.swift`, `CodexDock/State/AppServerDockStreamClient.swift`, `CodexDock/State/DockSessionTable.swift`, `CodexDock/Dock/DockRenderProjector.swift`, `CodexDock/State/SessionRowProjector.swift`, `CodexDock/State/DockSessionProjection.swift`, `CodexDock/Dock/DockDataEngine.swift`, `CodexDock/Dock/DockScreenStore.swift`, `CodexDock/State/DockStore.swift`, `CodexDock/Runtime/ClientRuntime.swift` | These files currently decode, sort, project, and route Dock rows. | parent and Composer consult | read |
| Archive caller family | `CodexDock/State/ArchiveStore.swift`, `CodexDock/Archive/ArchiveDataEngine.swift`, `CodexDock/State/ArchiveSessionProjector.swift`, `CodexDock/Archive/ArchiveScreenStore.swift`, `CodexDock/Features/Archive/ArchiveView.swift` | Archive is the main legacy direct-loader side door. | parent and Composer consult | read |
| Host identity and saved config | `CodexDock/Configuration/DockHostConfiguration.swift`, `CodexDock/Configuration/HostRegistry.swift`, `CodexDock/Configuration/RelayDiscovery.swift`, `CodexDock/Configuration/RelayBootstrapStore.swift`, `CodexDock/State/HostSettingsStore.swift`, `scripts/codex-dock-host-service.mjs`, `scripts/codex-dock-host-service-env.mjs`, `scripts/device-relay-config.mjs`, `scripts/device-relay-config.test.mjs`, `Makefile`, `AGENTS.md`, `README.md` | The hard cut depends on logical host identity without persisting relay instance ids into phone config. | parent and Composer consult | read |
| Legacy and side-door paths | `CodexDock/State/AppServerDockClient.swift`, `CodexDock/Models/SessionSummaryMapper.swift`, `CodexDock/Models/SessionSummary.swift`, `CodexDockTests/ThreadListMappingTests.swift`, `scripts/dock-relay-probe.mjs`, `scripts/dock-relay-leak-check.mjs`, `scripts/dock-relay-json-rpc-client.mjs`, `scripts/dock-relay-state-parity.mjs`, `scripts/dock-relay-thread-fidelity.mjs` | These can preserve old `thread/list`, `SessionSummary`, or old stream assumptions. | parent and Composer consult | read |
| Contract/proof surfaces | `package.json`, `Makefile`, `Package.swift`, `project.yml`, `CodexDockTests/AppServerClientTests.swift`, `CodexDockTests/DockStoreTests.swift`, `CodexDockTests/DockStoreStreamTests.swift`, `CodexDockTests/DockStoreTestSupport.swift`, `scripts/dock-relay.test.mjs`, `scripts/dock-relay-state-snapshot.test.mjs`, `scripts/dock-relay-state-parity.test.mjs`, `scripts/dock-relay-observability.test.mjs` | The plan adds schema generation, DTO proof, relay proof, and deletion-sweep proof. | parent and Composer consult | read |
| Docs, prompts, and instructions | `README.md`, `AGENTS.md`, `docs/CODEX_DOCK_CLIENT_ORDER_ROOT_CAUSE_2026-05-30_WORKLOG.md`, `docs/CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30.md` | These can continue teaching old row contracts or mismatched label fields. | parent and Composer consult | read |

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
- [x] Conditional lenses: docs-contract-drift and security-boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PLA-DEC-001 | Should Archive use explicit `archive/*` routes or a generic card-stream method? | Explicit Archive routes vs. generic view-param stream. | Different JSON-RPC API, observability, tests, and Swift method constants. | Use explicit `archive/subscribe`, `archive/update`, and `archive/resync`. | plan author under user hard-cut objective | Plan lines 951 and 1267 carry explicit route decision. | resolved |
| PLA-DEC-002 | How should Host Settings test connection work after deleting `DockSessionLoading`? | Keep raw `thread/list`, use relay status, add new RPC, or use card stream snapshot. | Could regress Host Settings or keep a legacy side door alive. | Use `HostConnectionTesting` with `CardStreamHostConnectionTester`, card stream snapshot, `totalRows`, and no `thread/list`. | plan author under user no-regression objective | Plan lines 815-846, 1013, and 1333-1337 carry the decision. | resolved |

## Resolved During This Audit

- [x] PLA-001 - Host identity support scripts were not initially named.
  - Lens: code-truth map, docs-contract-drift, security-boundary
  - Evidence: `scripts/codex-dock-host-service.mjs` reads `CODEX_DOCK_REAL_HOST_ID`; `scripts/codex-dock-host-service-env.mjs` writes it into generated service env; `scripts/device-relay-config.mjs` enforces host/port-only phone config.
  - Required plan repair: add host service, host service env, RelayDiscovery, RelayBootstrapStore, and device relay config surfaces to the checklist and Phase 4.
  - Status: resolved
  - Resolution evidence: plan lines 927-928, 1009-1021, and 1316-1319.

- [x] PLA-002 - Archive route wording left a generic-stream escape hatch.
  - Lens: ambiguity and miscommunication, caller-invariant-state
  - Evidence: plan already chose explicit Archive routes elsewhere but still allowed a generic method in the AppServerMethods row and Phase 3 note.
  - Required plan repair: remove the generic alternative and carry explicit `archive/*` routes everywhere.
  - Status: resolved
  - Resolution evidence: plan lines 951 and 1267.

## Pass History

### Pass 1 - 2026-05-30T21:57:16Z

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: current worktree plan artifact
- Test/CI context accepted, if supplied: not applicable; no implementation requested
- Agents/lenses run: native subagent tool was available but not used because its tool policy requires the user to explicitly ask for subagents; user did explicitly request Composer 2.5 Fast fresh consult, which was run twice and recorded under `/tmp/fresh-consult/`
- Code areas read: see coverage ledger
- Findings added: PLA-001, PLA-002
- Findings resolved: PLA-001, PLA-002
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code exists, if requested
