# Plan Audit Log

Plan: `docs/CODEX_DOCK_NEW_AND_FORK_SESSION_ARCHITECTURE_2026-06-06.md`
Audit log: `docs/CODEX_DOCK_NEW_AND_FORK_SESSION_ARCHITECTURE_2026-06-06_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-06-06 13:12 UTC
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

Not run. This is a plan-readiness audit only; no implementation exists in this
task.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/State/DockStore.swift`, `CodexDock/Commands/ClientCommandEngine.swift`, `CodexDock/Runtime/ClientRuntime.swift` | Confirms DockStore and command engine are the correct Swift owners for row-creating commands | Parent, Composer consult | read |
| Existing detail path | `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/State/AppServerThreadDetailSession.swift`, `CodexDock/Features/Session/SessionDetailView.swift`, `CodexDock/Features/Session/ComposerView.swift` | Confirms Thread Detail owns messages after a thread exists, not thread creation | Parent, Composer consult | read |
| Swift app route and DTO surface | `CodexDock/AppServer/AppServerMethods.swift`, `CodexDock/AppServer/AppServerClient.swift`, `CodexDock/AppServer/TurnDTO.swift`, `CodexDock/AppServer/ThreadDTO.swift`, `CodexDock/AppServer/DockThreadCardDTO.swift` | Confirms no create/fork app route exists, existing message params require `threadId`, and card/thread DTOs already carry fork/workspace fields | Parent, Composer consult | read |
| Dock UI callers | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/Features/Dock/DockTaskMenuView.swift`, `CodexDock/Features/Dock/DockRowContextMenu.swift`, `CodexDock/Features/Dock/DockSharedViews.swift` | Confirms visible New Session, row Fork, More-menu, and existing detail navigation surfaces | Parent, Composer consult | read |
| Projection owner path | `CodexDock/State/ThreadCardRowProjector.swift`, `CodexDock/Dock/DockModels.swift`, `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-views.mjs`, `scripts/dock-relay-human-thread-filter.mjs` | Confirms launch should return/upsert `DockThreadCardDTO` and reuse existing projection/cache paths | Parent, Composer consult | read |
| Relay command pattern | `scripts/dock-relay.mjs`, `scripts/dock-relay-user-message-command.mjs`, `scripts/dock-relay-outbound-user-message-store.mjs`, `scripts/dock-relay-thread-data.mjs` | Confirms custom app-facing command, idempotency, validation, routing, and projection catch-up patterns | Parent, Composer consult | read |
| Relay routing owner | `scripts/dock-relay-app-server-registry.mjs`, `scripts/dock-relay-app-server-registry.test.mjs`, `scripts/dock-relay-live-status-cache.mjs` | Confirms route selection belongs in the registry and current method sets need a session-launch helper | Parent, Composer consult | read |
| Observability and route health | `scripts/dock-relay-observability-contract.mjs`, `scripts/dock-relay-observability.test.mjs`, `scripts/dock-relay-diagnostics.mjs` | Confirms `/routesz` metadata must add one app-facing launch route | Parent | read |
| Test and proof surfaces | `docs/TESTING.md`, `package.json`, `Makefile`, `CodexDockTests/AppServerClientTests.swift`, `CodexDockTests/DockStoreTests.swift`, `scripts/dock-relay-user-message-command.test.mjs`, `scripts/dock-relay-card-contract.test.mjs` | Confirms smallest relevant checks and proof levels for relay, Swift, and simulator behavior | Parent | read |
| Upstream Codex protocol | `/tmp/codex-client/codex-managed-app-server-schema-20260606T125327Z/**`, `/tmp/codex-client/codex-app-server-schema-20260606T125242Z/**`, `codex app-server daemon version` | Confirms `thread/start` and `thread/fork` exist, response shape includes `thread`, and path-based fork is unstable | Parent | read |
| UX evidence | Apple HIG Buttons, Toolbars, Context Menus, Sheets, Action Sheets; UXPin progressive disclosure; Microsoft confirmation guidance | Confirms visible primary action, contextual Fork, one scoped sheet, progressive disclosure, and no routine confirmation | Parent | read |
| Native subagent coverage | `multi_agent_v1` availability and policy | Native subagents were not used because tool policy allows spawning only when the user explicitly asks for sub-agents/delegation. Cursor Composer fresh consult was explicitly requested and completed. | Parent | read |

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
| AMB-001 | Should the phone expose upstream `thread/start` and `thread/fork`, or one product route? | Two raw phone routes vs one app-facing launch route mapped inside relay | Could split Swift validation, idempotency, projection, and navigation | Choose one app-facing route | Agent, from repo evidence and Composer consult | Plan lines 169-180 choose `thread/session/launch`; lines 570-612 close raw side doors and list reused concepts | resolved |
| AMB-002 | Should first prompt text be sent during launch? | Auto-send in launch command vs seed local composer draft | Could create a second message-send path and prompt logging risk | Keep prompt text on existing `thread/message/send` path | Agent, from repo evidence and security constraints | Plan lines 48-51, 65-67, 206, 468-471, 572-574 | resolved |
| AMB-003 | What happens when New Session has no working directory context? | Invent a cwd from display labels vs omit cwd | Could create fake/unsafe workspace selection | Omit `cwd` and show "Default workspace" | Agent, after Composer note | Plan lines 439-441 | resolved |
| AMB-004 | How should fork route through private/live owners? | Always history, always live, or registry-owned live preference with private-owner block | Could fork stale private state or scatter routing | Registry helper owns live-owner preference, history fallback, and private-owner block | Agent, from registry code truth | Plan lines 257-275, 477-483, 501-510 | resolved |

## Pass History

### Pass 1 - 2026-06-06 13:12 UTC

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: worktree docs plus read-only code/source evidence
- Test/CI context accepted, if supplied: not applicable; this is a plan audit
- Agents/lenses run: local `$plan-audit` lenses; Cursor Agent Composer 2.5 Fast `$fresh-consult` pass and resume pass. Native subagents not used because the current tool policy requires explicit user request for sub-agent/delegation use.
- Code areas read: Swift app route/DTO/store/UI surfaces; relay dispatch, command, registry, state, observability, tests; upstream generated Codex app-server schemas; repo testing docs and Makefile/package scripts.
- Findings added: none
- Findings resolved: none
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit only after code exists

## Readiness Summary

The plan is ready. It defines a clear outcome, resolves route-shape ambiguity,
extends the repo's existing app-facing relay command pattern, keeps Swift on one
DockStore-owned path, keeps prompt text on `thread/message/send`, reuses
`DockThreadCardDTO` as the projection/navigation boundary, and requires proof at
the relay, Swift store, UI, and real relay-backed simulator seams.
