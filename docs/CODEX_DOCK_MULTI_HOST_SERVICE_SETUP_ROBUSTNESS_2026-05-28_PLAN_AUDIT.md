# Plan Audit Log

Plan: `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-05-28T12:01:57Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Resolved Cross-Plan Findings

- [x] CPLA-001 - Multi-host needed an explicit top-level prerequisite gate
  - Lens: depth-first-risk
  - Evidence: Section 7 was internally authoritative and could be read as starting before Agents, Connectivity, and Realtime landed.
  - Required plan repair: State the child plan is deferred behind top-level Phases 1-3 and add a Phase 0 prerequisite check for their outputs.
  - Status: resolved
  - Resolution evidence: Section 7 now opens with the top-level dependency note and Phase 0 gate.

- [x] CPLA-002 - Multi-host still owned Connectivity work
  - Lens: canonical-owner-and-SSOT, existing-pattern-and-convergence
  - Evidence: The plan said to add `AppConnectivityStore`, `AppServerClient` reconnect/state, and `ThreadDetailStore` rehydrate even though the top-level assigns those to Connectivity.
  - Required plan repair: Rewrite Multi-host to consume and verify the Connectivity plan's outputs, adding only host-service config/status inputs.
  - Status: resolved
  - Resolution evidence: Sections 0.6, 5.5, 6.1, Phase 4, and Phase 5 now use the Connectivity-owned store/lifecycle/reconnect contract.

- [x] CPLA-003 - Multi-host preserved one-shot `audio/transcribe`
  - Lens: deletion-and-side-door, drift-proof-coupling
  - Evidence: The plan required preserving relay-owned methods such as `audio/transcribe` even though Realtime must land first.
  - Required plan repair: Treat `audio/transcribe` as current-state evidence only and require final Realtime transcription contract/status after cutover.
  - Status: resolved
  - Resolution evidence: Sections 0.6, 3, 5.4, 6.1, and Phase 0 now require consuming the Realtime contract and not preserving one-shot production fallback.

- [x] CPLA-004 - No-phone-secret baseline still read as optional/future in places
  - Lens: security-boundary
  - Evidence: Old wording treated removing phone-side bearer tokens as later hardening and trusted no-client-auth as conditional on a paired-secret plan.
  - Required plan repair: State the physical path already uses no phone bearer and generated physical app config contains no app-facing secrets.
  - Status: resolved
  - Resolution evidence: Sections 0.5, 1.4, 3.7, 5.8, and Phase 1 carry the no-phone-secret baseline.

- [x] CPLA-005 - Generated app config could leak host-side secrets or token paths
  - Lens: security-boundary, docs-contract-drift
  - Evidence: `app-config` allowed generated env and the plan mentioned redacted token references.
  - Required plan repair: Split host-service config from app config and forbid token values, token file paths, OpenAI keys, raw audio, transcript text, and provider credentials in generated app config.
  - Status: resolved
  - Resolution evidence: Sections 0.5, 3.4, 5.2, 6.3, Phase 1, and Phase 3 exit evidence now define non-secret app config.

## Current Implementation Findings

Not run. This audit reviewed plan readiness, not implementation completion.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Plan artifact | `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md` | Canonical plan under audit. | Codex | read |
| Prior related plans | `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`, `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`, `docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` | Prevents conflicts with existing robustness, personal-device secret, and app-server assumptions. | Codex | read |
| Service lifecycle | `Makefile` | Current service setup is Mac/launchd-specific and hard-coded around one host. | Codex | read |
| Relay server | `scripts/dock-relay.mjs`, `scripts/dock-relay.test.mjs` | Main app-facing server boundary, status/error/reconnect/debug target, and test surface. | Codex | read |
| Swift JSON-RPC client | `CodexDock/AppServer/AppServerClient.swift` | Owns connection state, requests, stream lifecycle, timeout, and late-response behavior. | Codex | read |
| Thread detail live flow | `CodexDock/State/ThreadDetailStore.swift` | Main live-session UI path that must reconnect or fail visibly. | Codex | read |
| Host config and registry | `CodexDock/Configuration/DockHostConfiguration.swift`, `CodexDock/Configuration/HostRegistry.swift` | Host endpoint/auth parsing and multi-host registry contract. | Codex | read |
| Host fanout stores | `CodexDock/State/DockStore.swift`, `CodexDock/State/ArchiveStore.swift`, `CodexDock/State/HostSettingsStore.swift` | Existing partial-host behavior and split host status truth. | Codex | read |
| Root UI owner | `CodexDock/Features/Dock/DockView.swift` | Current root owns Dock/Archive/Hosts stores but no shared connectivity store. | Codex | read |
| Voice/transcription | `CodexDock/Voice/TranscriptionService.swift`, `CodexDock/AppServer/AppServerMethods.swift` | Worktree already has relay-backed transcription, so relay status/error/redaction must include it. | Codex | read |
| App-server protocol source | `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md` | Primary local source for transports, health endpoints, initialization, logging, and backpressure. | Codex | read |
| Current host facts | Local `codex`, `tailscale`, `ssh home` checks | Confirms `Amir-M5` state and `home` missing services on `:4500`/`:4510`. | Codex | read |
| External network facts | Tailscale Serve, MagicDNS, and connect-to-devices docs | Verifies current Tailscale role as optional connectivity/addressing, not service architecture. | Codex | read |

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
- [x] Conditional lens: docs-contract-drift
- [x] Conditional lens: security-boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Is Tailscale required architecture or just a supported setup profile? | Required transport dependency vs configured URL/profile. | Would change Swift/Node/service lifecycle boundaries. | Treat Tailscale as a network profile only. | User | Plan lines 146-147, 167-174, 296-303, 594-609, 656-661, 1092-1102. | resolved |
| DEC-002 | Should server robustness be in this plan or separate? | Separate follow-up vs required multi-host done state. | Would allow services to exist while client silently waits. | Include relay status/logs/errors and Swift reconnect/client-visible failures in scope. | User | Plan lines 103-112, 136-140, 511-548, 550-592, 642-654, 795-834, 919-952. | resolved |

## Audit Synthesis

The plan is implementation-ready. It states a falsifiable outcome, reads the relevant current code, names the current Mac-only and one-host assumptions, keeps Tailscale out of the core architecture, and carries server robustness through relay status, logs, client-visible errors, Swift reconnect, detail rehydration, and UI status.

The highest-risk area is correctly ordered: setup contract and relay diagnostics come before app reconnect work, so the client is not asked to recover from failures the server cannot yet explain. The plan also closes the obvious side doors: hard-coded `192.168.50.117`, Mac-only launchd generation, raw app-server network exposure, split host status truth, relay upstream hangs, and Tailscale-as-architecture drift.

## Pass History

### Pass 1 - 2026-05-28 06:03:20 CDT

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: worktree, current plan artifact, current related planning docs, local app-server docs, current Tailscale docs, and live host checks.
- Test/CI context accepted, if supplied: not supplied; not required for plan-readiness.
- Agents/lenses run: parent Codex audit using all required plan-audit lenses plus docs-contract-drift and security-boundary.
- Code areas read: service lifecycle, Node relay, Swift app-server client, detail store, host registry/config, Dock/Archive/Hosts stores, root Dock view, transcription service, app-server protocol docs.
- Findings added: none.
- Findings resolved during audit: stale transcription code-truth wording repaired in the plan before verdict.
- Findings carried forward: none.
- Verdict: ready.
- Next audit focus: implementation-audit after code changes land for the first two phases.

### Pass 2 - 2026-05-28T12:01:57Z

- Mode: cross-plan plan-readiness
- Scope: Multi-host alignment with top-level Phase 4 ordering, no-phone-secret baseline, Connectivity ownership, and Realtime voice contract
- Baseline reviewed: Multi-host plan after cross-plan prerequisite/security/ownership repairs
- Test/CI context accepted, if supplied: none; docs-only audit pass
- Agents/lenses run: Arendt audited Multi-host independently, Dewey audited cross-plan dependencies/security, and parent synthesis ran all required plan-audit lenses plus docs-contract-drift and security-boundary
- Code areas read: `Makefile`, `README.md`, `scripts/dock-relay.mjs`, `scripts/dock-relay-transcription.mjs`, `DockHostConfiguration.swift`, `HostRegistry.swift`, `RelayBootstrapStore.swift`, `RelayDiscovery.swift`, `AppServerClient.swift`, `ThreadDetailStore.swift`, `TranscriptionService.swift`, top-level plan, Agents plan, Connectivity plan, and Realtime plan
- Findings added: CPLA-001 through CPLA-005
- Findings resolved: CPLA-001 through CPLA-005
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after Multi-host code changes, especially generated app config redaction, service/status separation, and verification that host setup consumes existing Connectivity/Realtime contracts
