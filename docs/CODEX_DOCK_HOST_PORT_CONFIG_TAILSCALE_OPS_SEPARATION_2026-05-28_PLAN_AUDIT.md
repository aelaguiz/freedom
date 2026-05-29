# Plan Audit Log

Plan: docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28.md
Audit log: docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28_PLAN_AUDIT.md
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-05-28T22:37:17Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

Not run. This is a plan-readiness audit, not an implementation audit.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Local instructions | `AGENTS.md`, `/Users/aelaguiz/.codex/RTK.md` | Defines repo commands, doc/code truth, `.env` and service constraints, and `$eli10` style | Codex | read |
| Existing README/runbook | `README.md:62-237`, `README.md:299-326`, `README.md:447-454` | Current docs mix relay endpoint, Tailscale wording, auth mode env, and simulator env examples | Codex | read |
| Runnable service source | `Makefile:1-156` | Command source of truth for service startup, generated env, simulator launch, and current network profile variables | Codex | read |
| Client config owner | `CodexDock/Configuration/DockHostConfiguration.swift:3-129` | Current app-facing model stores URL plus optional bearer token | Codex | read |
| Multi-host env owner | `CodexDock/Configuration/HostRegistry.swift:1-120` | Current env contract includes per-host URL, auth mode, bearer/token, and names | Codex | read |
| Bootstrap/discovery owner | `CodexDock/Configuration/RelayBootstrapStore.swift:1-269`, `CodexDock/Configuration/RelayDiscovery.swift:1-230` | Current bootstrap precedence and one-record persistence are the main side doors | Codex | read |
| Hosts settings UI/store | `CodexDock/State/HostSettingsStore.swift:1-257`, `CodexDock/Features/Hosts/HostsView.swift:1-288` | Current UI asks for WebSocket URL and persistence saves one URL record | Codex | read |
| Runtime caller shape | `CodexDock/State/DockStore.swift:61-162`, `CodexDock/AppServer/AppServerClient.swift:159-190` | Shows URL conversion belongs at transport boundary and multi-host loading already fans out | Codex | read |
| Existing tests | `CodexDockTests/DockConfigurationTests.swift`, `CodexDockTests/DockStoreTests.swift:520-603`, `CodexDockTests/AppServerClientTests.swift:1656-1729` | Confirms current URL/auth/env behavior and realistic proof surfaces to replace | Codex | read |
| Node host-service owner | `scripts/codex-dock-host-service.mjs:1-260`, `scripts/codex-dock-host-service.mjs:540-700`, `scripts/codex-dock-host-service-env.mjs:1-222` | Current generated app config and Tailscale profile branch live here | Codex | read |
| Node tests | `scripts/codex-dock-host-service.test.mjs:1-620` | Current tests assert Tailscale profile URL emission and app config auth mode; plan must retire or rewrite them | Codex | read |
| Project config | `project.yml:36-50` | App Transport Security and Bonjour config source of truth if transport policy changes | Codex | read |
| External ops docs | Tailscale Serve docs, MagicDNS docs, device connection docs | Needed only for runbook command shape; not used to justify app behavior | Codex | read |

Native subagents/lens split: not used because the relevant code slice was small enough to inspect directly in one pass; no broad independent audit slices were needed.

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
- [x] Conditional docs-contract-drift lens
- [x] Conditional security-boundary lens

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Does "host + port" allow full URLs, auth mode, scheme, or network profile in client config? | Endpoint means host+port only; or URL/auth/profile still allowed internally/app-facing | If unresolved, implementation could keep the confusing model | Client app-facing config is host+port only; URL is computed only at transport boundary | Amir, from objective | Plan lines 28-31, 37-48, 65-85, 201-227, 282-305 | resolved |
| DEC-002 | Is Tailscale an app/installer feature or ops setup? | Special Tailscale profile/autodetect in code; or ops recipe that produces a host+port | If unresolved, Node/Swift code can keep Tailscale branches | Tailscale is ops only; remove profile/autodetect from app and host-service code | Amir, from objective | Plan lines 87-102, 179-187, 306-334, 336-418, 511-553 | resolved |
| DEC-003 | How should Tailscale serving be proven? | Direct tailnet route; Tailscale Serve; or app-specific Tailscale support | Could block ops validation or reintroduce special support | Default direct tailnet route; `tailscale serve --tcp` is fallback/explicit ops choice only | Codex, from repo + official docs | Plan lines 362-378, 391-401, 590-627 | resolved |
| DEC-004 | If iOS blocks `ws://` for tailnet hosts, is that Tailscale support? | Add Tailscale-specific config; or make a generic app transport policy decision | Could create a hidden Tailscale feature | Any fix must be generic App Transport Security policy in `project.yml`, not client Tailscale config | Codex, from repo constraints | Plan lines 111-112, 506-509, 644-648 | resolved |

## Plan-Readiness Verdict

Verdict: ready
Confidence: high

Why this is ready:

- The plan states the desired world before tasks: the iPhone client stores only host+port, and Tailscale setup is separate ops work.
- It names the current contradictory code paths and docs with concrete anchors.
- It defines the target model, persistence, env contract, UI shape, Node host-service boundary, docs cleanup, and ops proof.
- It deletes the side doors that would preserve the old confusion: URL entry, auth mode, app bearer fields, Tailscale network profile, Tailscale address env, and stale docs.
- It uses a depth-first sequence: endpoint model first, persistence/bootstrap second, UI third, Node/docs/ops after the client contract is clean.
- It records the only meaningful transport risk, App Transport Security, without turning it into Tailscale support.

## Proper-Audit Checklist Status

- Plan artifact resolved: yes
- Reviewed scope explicit: yes, whole plan
- Local instructions read: yes
- Audit log path exists: yes
- North Star identified: yes
- Done-state requirements identified: yes
- Requirements separated from tasks: yes
- Non-requirements identified: yes
- Constraints and non-constraints identified: yes
- Real ambiguity listed and resolved in plan: yes
- Relevant code coverage complete for plan readiness: yes
- Native subagent non-use justified: yes, too small to split
- Blocking findings include consequence/evidence/repair: none open
- Audit log current: yes

## Pass History

### Pass 1 - 2026-05-28T22:37:17Z

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: repo instructions, README, Makefile, Swift config/bootstrap/discovery/settings/UI/callers/tests, Node host-service/env/tests, project config, and official Tailscale docs for ops commands
- Test/CI context accepted, if supplied: not applicable; this pass audits a planning doc and did not run tests
- Agents/lenses run: plan-audit required lenses; no native subagents because the scoped code map was small enough to inspect directly
- Code areas read: listed in coverage ledger
- Findings added: none
- Findings resolved: Phase 4 host-service proof command was corrected before final verdict from relay-only `rtk npm run test:relay` to full Node `rtk npm test`, because host-service changes must run the host-service suite too.
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code changes land
