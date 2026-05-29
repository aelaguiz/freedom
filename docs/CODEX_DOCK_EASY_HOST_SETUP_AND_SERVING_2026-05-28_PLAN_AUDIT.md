# Plan Audit Log

Plan: docs/CODEX_DOCK_EASY_HOST_SETUP_AND_SERVING_2026-05-28.md
Audit log: docs/CODEX_DOCK_EASY_HOST_SETUP_AND_SERVING_2026-05-28_PLAN_AUDIT.md
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-05-28
Scope: whole plan (plan-readiness mode)
Mode: plan-readiness

## Current Blocking Findings

- [x] PLA-001 - Phase 4 multi-host `app-config` merge is overbuild
  - Lens: elegance-and-code-judo / requirements-constraints-simplicity
  - Evidence: plan Phase 4 + §5.2/§5.3/§6; code `scripts/codex-dock-host-service.mjs:556-579` (single-host emit), `codex-dock-host-service-env.mjs` multi-host `service.env` writer, `Makefile:149` SIMCTL injection, `CodexDock/Configuration/HostRegistry.swift:24-38` (`fromEnvironment` already parses `CODEX_DOCK_HOSTS` list).
  - Required plan repair: drop the merge; handoff = each machine prints its own one-host URL → user adds in-app (device); simulator multi-host already from existing env injection.
  - Status: resolved
  - Resolution evidence: removed from §0.2 (line ~118), §3 capability note (~255), §5.2 (~344) / §5.3 (~352), §6 change map (Installer row replaced with Env-name contract row) + migration notes, Phase 4 Work/Checklist/Verification/Exit/Rollback, §8.1; Decision Log "PLA-001" entry added.

- [x] PLA-002 - Host env-var naming contract has 4 writers + 2 divergent suffix rules (drift)
  - Lens: drift-proof-coupling / canonical-owner-and-ssot
  - Evidence: `Makefile:44-49,83,149` (hand-written names, hardcoded `AMIR_M5`/`HOME`), `scripts/codex-dock-host-service.mjs:194-200` (`hostIDToEnvSuffix` regex), `CodexDock/Configuration/HostRegistry.swift:102-109` (`envKeyComponent` scalar). Rules diverge on repeated non-alphanumerics (`my--host` → Node `MY_HOST` vs Swift `MY__HOST`). The plan's Makefile parametrization forces removing the hardcoded literals, so convergence is required.
  - Required plan repair: make installer `app-config --format env` the single writer the Makefile consumes; delete hardcoded literals; add a Node↔Swift suffix-agreement test + sync comments.
  - Status: resolved
  - Resolution evidence: §5.2 "one env-name writer" bullet, §5.3, §6 new "Env-name contract" row + Make row + migration notes "Env-name source of truth", Phase 3 checklist/verification/exit; Decision Log "PLA-002" entry added.

- [x] PLA-003 - Phase 1 "form-added host survives cold start" not achievable in Phase 1 (proof gate)
  - Lens: depth-first-risk / proof-and-phase-exit
  - Evidence: plan Phase 1 exit vs Phase 2 checklist; code `CodexDock/State/HostSettingsStore.swift:227` (`saveHost` writes a single `LocalRelayConfiguration`; list-write was assigned to Phase 2), `RelayBootstrapStore.swift:44` (env wins on simulator → masks the form path).
  - Required plan repair: move the minimal `saveHost`→list-store write into Phase 1; prove form-add durability via tests (env masks the simulator run); narrow Phase 2 to UI + removeHost + discovery-as-add + live propagation.
  - Status: resolved
  - Resolution evidence: Phase 1 Work + new checklist bullet (saveHost full-list write) + Verification + Exit (durability by test, simulator = preservation check); Phase 2 checklist reworded; Decision Log "PLA-003" entry added.

## Current Non-Blocking Findings

- [x] PLA-004 - `AppConnectivityStore` must reflect added/removed hosts on registry change (not just test status)
  - Lens: caller-invariant-state
  - Required plan repair: add to Phase 2 root-wiring checklist.
  - Status: resolved (Phase 2 checklist now states it; ref audit N1).

- [x] PLA-005 - "optional SSH convenience wrapper" softened blocking-vs-optional scope
  - Lens: requirements-constraints-simplicity
  - Required plan repair: reclassify as a named follow-up (not "optional").
  - Status: resolved (§6 Home-box row + Phase 4 checklist now say "named follow-up, not required").

- [ ] PLA-006 - ATS open-IP for a bare *public* IP literal is the weakest sub-path
  - Lens: security-boundary / docs-contract-drift
  - Note: `NSAllowsLocalNetworking` covers LAN/RFC1918; a public IP **literal** over cleartext `ws://` cannot get a scoped `NSExceptionDomains` entry (ATS keys on domains), so it would need `NSAllowsArbitraryLoads` or `wss`. Plan already recommends hostname (MagicDNS/DNS) addressing for non-LAN; this is sufficient guidance.
  - Status: accepted-risk (covered by the Phase 3 default = address non-LAN hosts by hostname; bare-public-IP cleartext is explicitly the user-opt-in/`wss` branch). Tracked in the Ambiguity/Decision ledger as the ATS posture decision.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path (persistence) | `RelayDiscovery.swift:55-119` (`LocalRelayConfiguration`, `FileLocalDockConfigurationStore`, `defaultFileURL`) | the store to generalize to a list | parent + arch cold-reader | read |
| Bootstrap / precedence | `RelayBootstrapStore.swift:36-56,99-137,179-206,224-253` | precedence + single-save + discovery auto-use | parent + client lens agent | read |
| In-app edit | `HostSettingsStore.swift:84-127,182-252` (`saveHost`, no remove) | the add/edit path + persistence gap | parent + client lens agent | read |
| Multi-host consumer | `DockStore.swift:454-527` (`init(registry:)`, `updateRegistry`, `hosts[0]`), `DockView.swift:35-75` | live propagation reuse + empty-list crash risk | parent + client lens agent | read |
| Registry construction | `HostRegistry.swift:17-86` (`fromEnvironment`, `envKeyComponent`) | env seed + suffix rule | parent + serving lens agent | read |
| URL validator | `DockHostConfiguration.swift:50-65` (`validatedWebSocketURL`) | reused everywhere | parent | read |
| Hosts UI | `Features/Hosts/HostsView.swift:82-288` | add/edit form; remove/token gaps | parent | read |
| Installer | `codex-dock-host-service.mjs:194-233,471-533,556-579,826-853` + `-env.mjs` | profiles, render, app-config, multi-host env writer, suffix rule | parent + serving lens agent | read |
| Relay bind/bonjour | `dock-relay.mjs:673,766`, `dock-relay-bonjour.mjs` | 0.0.0.0 bind + LAN-only mDNS | parent | read |
| Serving wiring | `Makefile:1-53,80-123,145-153` (env-file, app SIMCTL, host-service-args) | profile/host/env writers | parent + serving lens agent | read |
| ATS / Bonjour entitlements | `CodexDockApp/Info.plist`, `project.yml` (`NSAppTransportSecurity`, `NSBonjourServices`, `NSLocalNetworkUsageDescription`) | cleartext ws posture for non-LAN | parent | read |
| Tests | `CodexDockTests/{DockConfigurationTests,DockStoreTests}.swift`, `scripts/codex-dock-host-service.test.mjs`, `dock-relay*.test.mjs` | preservation signals | parent (named) | named, not line-read |
| Relevant code not yet read | exact line-level read of the test bodies; `codex-dock-host-service-runtime.mjs` internals | not needed to validate plan claims | — | unknown (non-blocking) |

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
- [x] Conditional: security-boundary (no secrets on phone; ATS posture; relay-only endpoint)
- [x] Conditional: docs-contract-drift (env var contract; README/AGENTS runbook)
- [n/a] Conditional: agent-capability (not agent-backed; transcription untouched)

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-1 | iOS ATS posture for non-LAN cleartext `ws://` | (a) scoped `NSExceptionDomains` for tailnet/DNS hostnames [default]; (b) `wss` via Tailscale Serve; (c) `NSAllowsArbitraryLoads` | Changes Phase 3 ATS work + whether bare public-IP literals are supported | confirm or change the default during review; Phase 3 spike validates on a real device | user (amir) | Phase 3 checklist/exit + §3.3 + §1.4 record default + named alternatives | open-but-defaulted (not blocking; default is implementable, spike-gated) |

## Pass History

### Pass 1 - 2026-05-28 (find)

- Mode: plan-readiness
- Scope: whole plan
- Agents/lenses run: 2 native Explore lens agents (serving-side overbuild+drift; client-side depth-first+proof) + parent synthesis across all required lenses; 2 earlier cold-read agents during the arch-step consistency-pass.
- Code areas read: see coverage ledger (all read).
- Findings added: PLA-001 (blocking), PLA-002 (blocking), PLA-003 (blocking), PLA-004/005 (non-blocking), PLA-006 (accepted-risk).
- Verdict: not-ready (3 blockers).
- Next audit focus: confirm repairs close PLA-001/002/003 without new drift.

### Pass 2 - 2026-05-28 (repair + verify)

- Mode: plan-readiness
- Scope: whole plan (re-read edited sections §0.2, §3, §5, §6, §7, §8, §10).
- Findings resolved: PLA-001, PLA-002, PLA-003, PLA-004, PLA-005 (each with plan-line evidence above and an append-only Decision Log entry).
- Findings carried forward: PLA-006 (accepted-risk; tracked as DEC-1).
- Structure check: arch-step stage gate still `READY next=implement-loop`; headings 0–10 unique; 8/8 block markers balanced.
- Verdict: ready.
- Next audit focus: none for planning. Switch to `implementation-audit` mode after code exists (start with Phase 1).
