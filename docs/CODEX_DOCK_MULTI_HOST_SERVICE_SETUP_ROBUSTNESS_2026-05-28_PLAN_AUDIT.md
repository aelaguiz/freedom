# Plan Audit Log

Plan: `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve
Last reviewed: 2026-05-28T21:38:22Z
Scope: whole plan; latest implementation audit covers Phase 6 README and final non-physical multi-host app smoke

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

None open for the implemented Phase 1A, Phase 2, Phase 1B/3A, Phase 3B, Phase 4A, Phase 3C, and Phase 6 slices.

Reviewed Phase 1A, Phase 2, Phase 1B/3A, Phase 3B, Phase 4A, Phase 3C, and Phase 6 implementation:

- `scripts/codex-dock-host-service.mjs`
- `scripts/codex-dock-host-service-env.mjs`
- `scripts/codex-dock-host-service-runtime.mjs`
- `scripts/codex-dock-host-service.test.mjs`
- `scripts/dock-relay.mjs`
- `scripts/dock-relay-status.mjs`
- `scripts/dock-relay-json-rpc-client.mjs`
- `scripts/dock-relay-phase5.test.mjs`
- `Makefile`
- `package.json`
- `CodexDock/Configuration/DockHostConfiguration.swift`
- `CodexDock/Configuration/HostRegistry.swift`
- `CodexDockTests/DockConfigurationTests.swift`
- `README.md`
- `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28_IMPLEMENTATION_LOG.md`

Scope boundary: approved for dry-run preflight, host-service CLI option hardening, relay-side status/error/upstream robustness, host-service lifecycle core, live Mac launchd wrapper proof, generated two-host env/simulator app consumption, live Linux `home` systemd proof, README runbook update, and final non-physical two-host app behavior proof. Physical-device behavior proof remains deferred manual QA under the parent dock rule. Realtime transcription on `home` is not approved because no OpenAI key is configured there.

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

### Pass 3 - 2026-05-28T19:56:00Z

- Mode: implementation-audit
- Scope: Multi-host Phase 1A preparatory dry-run renderer only
- Baseline reviewed: Multi-host plan Phase 1 plus preparatory exception, implementation log, new host-service script/tests, and package script wiring
- Test/CI context accepted, if supplied: `rtk node --check scripts/codex-dock-host-service.mjs` passed; `rtk npm test` passed 41 relay tests and 9 host-service tests with 0 failures; `rtk git diff --check` passed
- Agents/lenses run: Bernoulli performed plan-backed implementation audit; Confucius performed thermonuclear maintainability review; parent synthesis ran plan-audit implementation-audit checks
- Code areas read: host-service config construction, launchd/systemd rendering, app-config export, redaction, command dispatch, host-service tests, package scripts, implementation log status claims
- Findings added: temporary review findings for CLI missing value handling, redaction by value shape, mutating token writer in dry-run slice, unsupported-command dispatch, and env app-config boundary
- Findings resolved: all temporary findings were fixed before verdict:
  - value-taking CLI options now reject missing values before config creation;
  - redaction now sanitizes credentialed URLs and `OPENAI_API_KEY=value` strings even under generic keys;
  - the mutating token writer was removed from the Phase 1A module and tests;
  - unsupported lifecycle commands are rejected before config hydration;
  - env app-config now includes auth mode and rejects line breaks.
- Findings carried forward:
  - Realtime detailed manual physical `iPhone 14` evidence remains a program gate before claiming final Realtime or Multi-host readiness.
  - Real token creation/reuse remains deferred to the install/start phase because Phase 1A is dry-run only.
- Verdict: approve for Phase 1A only
- Next audit focus: Phase 1B/Phase 2 when real install/status or relay `/statusz` changes land

### Pass 4 - 2026-05-28T20:36:17Z

- Mode: implementation-audit
- Scope: Phase 1A CLI hardening plus Phase 2 relay status/error/upstream-robustness slice
- Baseline reviewed: relay implementation and status helper, upstream JSON-RPC client, focused relay Phase 5 tests, host-service CLI parser/tests, `Makefile` relay status target, child implementation log, and parent physical-device deferral rule
- Test/CI context accepted, if supplied:
  - `rtk node --check scripts/dock-relay.mjs && rtk node --check scripts/dock-relay-status.mjs && rtk node --check scripts/dock-relay-json-rpc-client.mjs && rtk node --check scripts/dock-relay-phase5.test.mjs` passed
  - `rtk node --test scripts/dock-relay-phase5.test.mjs` passed 20 tests with 0 failures
  - `rtk node --check scripts/codex-dock-host-service.mjs && rtk node --check scripts/codex-dock-host-service.test.mjs && rtk npm run test:host-service` passed 9 host-service tests with 0 failures
  - `rtk npm run test:relay` passed 47 relay tests with 0 failures
  - `rtk npm test` passed 47 relay tests and 9 host-service tests with 0 failures
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Agents/lenses run: Ampere performed read-only relay Phase 2 review; Ohm performed read-only host-service Phase 1B/thermonuclear follow-up review; parent synthesis ran implementation-audit checks against the plan's Phase 1/Phase 2 exit evidence
- Code areas read: relay `/readyz`/`/healthz`/`/statusz`, live `thread/resume`, upstream recovery, upstream JSON-RPC error handling, downstream parse-error handling, relay status snapshot, `Makefile` status target, host-service CLI parser, and focused test coverage
- Findings added and resolved during audit:
  - real relay `thread/resume` did not enforce `excludeTurns: true`; fixed by normalizing live resume params and adding focused tests;
  - upstream JSON-RPC `-32001` overload collapsed to generic `-32000`; fixed with `JsonRpcUpstreamError`, retryable overload data, and tests;
  - `/readyz` and `/healthz` had identical static-config bodies; fixed so `/readyz` is process-ready and `/healthz` carries static config;
  - `rtk make dock-relay-status` only printed `/readyz`; fixed to print `/statusz` too;
  - malformed downstream JSON did not update status; fixed and tested;
  - pending upstream request rejection was implemented but unproven; added direct proof;
  - transcription status included extra language/delay fields and always said enabled; narrowed to enabled/model/endpoint host/key-present/last-error;
  - host-service unknown CLI flags were silently accepted; fixed with an explicit boolean-option allowlist and focused tests.
- Findings carried forward at this pass:
  - real launchd/systemd `install`, `start`, `stop`, `restart`, `status`, `logs`, and `doctor` were still unimplemented at Pass 4 and became the next Phase 1B/Phase 3 work;
  - install-scoped token creation/reuse with restrictive permissions was still unimplemented at Pass 4 and became part of the next lifecycle slice;
  - generated two-host app config and app consumption remain unimplemented;
  - final `Amir-M5` plus `home` behavior proof remains unclaimed;
  - physical-device checks are deferred manual QA for Amir under the parent dock rule.
- Verdict: approve for this Phase 1A/Phase 2 slice only
- Next audit focus: service lifecycle adapters, install-scoped token writer, real redacted status/log/doctor surfaces, generated two-host app config, and Makefile wrapper replacement

### Pass 5 - 2026-05-28T20:49:09Z

- Mode: implementation-audit
- Scope: Phase 1B/Phase 3A host-service lifecycle core behind injected launchd/systemd runners
- Baseline reviewed: host-service lifecycle implementation, runtime helper, focused host-service tests, implementation log, child plan Phase 1/3 notes, parent physical-device deferral rule, and read-only subagent findings
- Test/CI context accepted, if supplied:
  - `rtk node --check scripts/codex-dock-host-service-runtime.mjs` passed
  - `rtk node --check scripts/codex-dock-host-service.mjs` passed
  - `rtk node --check scripts/codex-dock-host-service.test.mjs` passed
  - `rtk npm run test:host-service` passed 17 tests with 0 failures
  - `rtk npm test` passed 47 relay tests and 17 host-service tests with 0 failures
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Agents/lenses run: Boyle performed read-only lifecycle-scope review; Mendel performed read-only redaction/security review; parent synthesis ran implementation-audit checks against Phase 1B/Phase 3A exit evidence
- Code areas read: token creation/reuse, service file writes, launchd/systemd command adapters, status health probes, logs/doctor output, redaction helper, child-process environment, CLI option parsing, and focused fake-runner coverage
- Findings added and resolved during audit:
  - systemd install initially used `enable --now`, which made install start services; fixed so install only links/reloads/enables and start owns process startup;
  - systemd stop initially stopped both units in one command without explicit relay-before-raw order; fixed and tested;
  - host-service output put safe token metadata under a `token` key that the redactor hid; fixed by using `appServerAuth.created`;
  - JSON-RPC payload-looking log lines under `params`, `body`, `payload`, `request`, and `response` could leak prompt/transcript text; fixed with payload-container redaction and tests;
  - cookie/session/header values could leak through status/log/doctor output; fixed with key/string redaction and tests;
  - service-manager failure errors could print raw command args; fixed with redacted error construction and tests;
  - service-manager child processes inherited parent env by default; fixed with minimal `HOME`/`PATH`/`LANG` env and tests;
  - script CLI `--env-file` conflicted with Node 25; fixed by renaming the host-service option to `--service-env-file` while keeping rendered relay `--env-file` args.
- Findings carried forward:
  - live launchd/systemd proof is still unclaimed;
  - `Makefile` wrapper replacement is still unimplemented;
  - generated two-host app config and app consumption remain unimplemented;
  - final `Amir-M5` plus `home` behavior proof remains unclaimed;
  - physical-device checks are deferred manual QA for Amir under the parent dock rule.
- Verdict: approve for Phase 1B/Phase 3A fake-runner lifecycle core only
- Next audit focus: actual `Makefile` wrapper cutover, live Mac launchd proof, live Linux systemd proof on `home`, README runbook, generated two-host app config, and app multi-host smoke

### Pass 6 - 2026-05-28T21:07:40Z

- Mode: implementation-audit
- Scope: Phase 3B Makefile wrapper cutover and live Mac launchd proof
- Baseline reviewed: `Makefile`, host-service script/env/runtime/test modules, generated launchd files, live host-service status output, implementation log, parent physical-device deferral rule, and read-only subagent findings
- Test/CI context accepted, if supplied:
  - `rtk node --check scripts/codex-dock-host-service-env.mjs` passed
  - `rtk node --check scripts/codex-dock-host-service-runtime.mjs` passed
  - `rtk node --check scripts/codex-dock-host-service.mjs` passed
  - `rtk node --check scripts/codex-dock-host-service.test.mjs` passed
  - `rtk npm run test:host-service` passed 20 tests with 0 failures
  - `rtk npm run test:relay` passed 47 tests with 0 failures
  - `rtk make services` passed
  - `rtk make app-server-status` passed with bundle `status: ready`
  - `rtk make dock-relay-status` passed with bundle `status: ready`
  - `rtk make host-service-doctor` passed with `status: passed`
  - `rtk npm test` passed 47 relay tests and 20 host-service tests with 0 failures
  - `rtk make app SIM='iPhone 17'` failed before build/launch only because the simulator name matched two devices
  - `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'` passed on the accepted non-Pro simulator
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Agents/lenses run: Peirce performed read-only Makefile wrapper cutover review; Gibbs performed read-only live-proof risk review; parent synthesis ran implementation-audit checks against Phase 3 exit evidence.
- Findings added and resolved during audit:
  - `status` and `doctor` could previously return success for nonready state; fixed and tested before cutover.
  - Host-service install previously passed a relay env file path without owning generated env file writes; fixed with `scripts/codex-dock-host-service-env.mjs`, generated `.codex-dock/service.env`, and non-secret `.codex-dock/host.env`.
  - macOS `start` could force activity instead of reusing loaded services; fixed so running launchd services are reused.
  - Relay status counted HTTP `200` `/statusz` without checking raw-history health; fixed with `snapshotOK` and `historyOK`.
  - Status only proved loopback relay health; fixed so non-simulator profiles also check app-facing relay `/readyz`.
  - Live launchd bootstrap returned exit `5` during old-service cutover; fixed with a retry in the host-service wrapper.
  - A loaded but failing launchd service was being treated as reusable; fixed so install reuses only expected-path services with `state = running`.
  - `codex app-server` rejects `ws://IP:PORT/` for `--listen`; fixed so raw app-server listen URLs render as `ws://IP:PORT`.
  - The Makefile target names still implied separate service ownership; fixed by making `app-server` and `dock-relay` explicit compatibility aliases for the host service bundle and updating help text.
- Findings carried forward:
  - live Linux systemd proof on `home` is still unclaimed;
  - generated two-host app config and app consumption remain unimplemented;
  - README runbook rewrite remains unimplemented;
  - final `Amir-M5` plus `home` app behavior proof remains unclaimed;
  - physical-device checks are deferred manual QA for Amir under the parent dock rule.
- Verdict: approve for Phase 3B Makefile wrapper and live Mac launchd proof only
- Next audit focus: live Linux systemd proof on `home`, generated two-host app config, README runbook, and app multi-host smoke

### Pass 7 - 2026-05-28T21:20:03Z

- Mode: implementation-audit
- Scope: Phase 4A generated two-host env and simulator app consumption
- Baseline reviewed: `Makefile`, `scripts/codex-dock-host-service-env.mjs`, `scripts/codex-dock-host-service.test.mjs`, `DockHostConfiguration.swift`, `HostRegistry.swift`, `DockConfigurationTests.swift`, generated `.codex-dock/host.env`, simulator host-registry logs, implementation log, parent physical-device deferral rule, and read-only subagent findings
- Test/CI context accepted, if supplied:
  - `rtk node --check scripts/codex-dock-host-service-env.mjs && rtk node --check scripts/codex-dock-host-service.mjs` passed
  - `rtk npm run test:host-service` passed 21 tests with 0 failures
  - `rtk swift test --filter DockConfigurationTests` passed 18 tests with 0 failures
  - `rtk make -n app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'` passed as a command-expansion proof
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'` passed
  - Generated `.codex-dock/host.env` contained `Amir-M5` and `home`, both `AUTH_MODE=none`, and no forbidden secret-shaped keys
  - Simulator logs showed `host registry loaded from environment hosts=2` with `bearer_configured=false` for both hosts
  - `rtk swift test --filter DockStoreTests` passed 19 tests with 0 failures
  - `rtk make app-server-status && rtk make dock-relay-status` passed with bundle `status: ready`
  - `rtk npm test` passed 47 relay tests and 21 host-service tests with 0 failures
  - `rtk swift test` passed 187 tests with 5 skipped and 0 failures
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Findings added and resolved during audit:
  - Generated app config was still partly a single-host artifact. Fixed by making `.codex-dock/host.env` copy all app-safe host keys from service env and preserving the existing env-first Swift bootstrap path.
  - Simulator launch still hard-coded per-host env values from Make variables. Fixed so `rtk make app` reads only `.codex-dock/host.env` and exports safe `CODEX_DOCK_*` keys as `SIMCTL_CHILD_CODEX_DOCK_*`.
  - Host env generation could have copied unrelated non-secret-but-not-app keys. Fixed with an explicit app-safe whitelist instead of copying every non-secret key.
  - `HostRegistry` accepted duplicate host IDs and ignored generated `AUTH_MODE`. Fixed with duplicate rejection, `AUTH_MODE=none|bearer` parsing, nil-token behavior for `none`, and explicit token requirement for `bearer`.
- Findings carried forward:
  - live Linux systemd proof on `home` remains unclaimed;
  - README runbook rewrite remains unimplemented;
  - final `Amir-M5` plus `home` app behavior proof remains unclaimed because `home` is configured in app env but the real `home` service is not running yet;
  - physical behavior checks are deferred manual QA for Amir.
- Verdict: approve for Phase 4A generated env and simulator app-consumption proof only
- Next audit focus: live Linux systemd proof on `home`, README runbook, and final app multi-host smoke

### Pass 8 - 2026-05-28T21:31:28Z

- Mode: implementation-audit
- Scope: Phase 3C live Linux systemd proof on `home`
- Baseline reviewed: child plan Phase 3/4 status, implementation log Phase 3C evidence, `Makefile`, host-service script/env/runtime/test modules, remote `home` status/doctor output, generated `home` `.codex-dock/host.env`, parent physical-device deferral rule, and read-only subagent findings
- Test/CI context accepted, if supplied:
  - remote deploy hygiene passed: `/home/aelaguiz/workspace/codex-client` had no `.env`, no `env.bak`, no `.codex-dock/`, and host-service files were present
  - remote toolchain readback: Node `v18.19.1`, npm `9.2.0`, rtk `0.37.2`, `codex-cli 0.135.0-alpha.2`
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk npm ci'` passed with 1 package installed and 0 vulnerabilities
  - remote `rtk node --check` passed for host-service scripts
  - remote `rtk npm run test:host-service` passed 21 tests with 0 failures
  - remote `rtk make services HOST_SERVICE_PLATFORM=linux ... CODEX_DOCK_REAL_HOST_ID=home ... CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510 ...` passed
  - remote `host-service-status` passed with `status: ready`, `serviceManager: systemd-user`, raw app-server active, dock relay active, raw `/readyz` OK, relay `/readyz` OK, relay `/statusz` OK, and app-facing relay `/readyz` OK
  - remote `host-service-doctor` passed with `status: passed` and `problems: []`
  - local Mac `curl -fsS --max-time 5 http://100.66.11.7:4510/readyz` returned `{"ok":true,"service":"codex-dock-relay","auth":"none"}`
  - local Mac `/statusz` proof showed host id `home`, history health `ok: true`, `phoneAuth: none`, `historyCredentialConfigured: true`, and transcription `enabled: false` / `keyPresent: false`
  - generated `home` `.codex-dock/host.env` contained only non-secret `home` host config and no `AMIR_M5` or secret-shaped keys
  - systemd readback showed `codex-dock-app-server.service` and `codex-dock-relay.service` active/running
  - local `rtk npm test` passed 47 relay tests and 21 host-service tests with 0 failures
  - local simulator app launch loaded `Amir-M5` plus `home` from generated env with `bearer_configured=false`
  - `.env` mtime remained `1779986258`
- Findings added and resolved during audit:
  - Linux `systemctl --user link` was not idempotent when linked unit files already existed; fixed by using `systemctl --user link --force`.
  - The service-manager child env was too strict for `systemctl --user`; fixed by preserving only non-secret `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`.
  - Home-only generated app config still carried unlisted host keys; fixed so host-specific app env keys are emitted only for IDs listed in `CODEX_DOCK_HOSTS`.
- Findings carried forward:
  - README runbook rewrite remains unimplemented.
  - final `Amir-M5` plus `home` app behavior proof remains unclaimed.
  - Realtime transcription on `home` remains unclaimed because no `OPENAI_API_KEY` was copied to `home`; relay status correctly reports it disabled.
  - physical behavior checks are deferred manual QA for Amir.
- Verdict: approve for Phase 3C live Linux systemd proof on `home`
- Next audit focus: README runbook and final app multi-host smoke

### Pass 9 - 2026-05-28T21:38:22Z

- Mode: implementation-audit
- Scope: Phase 6 README runbook and final non-physical multi-host app smoke
- Baseline reviewed: child plan Phase 6 exit evidence, implementation log Phase 6 evidence, `README.md`, parent physical-device deferral rule, generated `.codex-dock/host.env`, simulator app logs, Mobile MCP element readbacks, screenshots under `/tmp/codex-client/20260528T213700Z/`, Mac status output, and `home` relay `/readyz`/`/statusz`
- Test/CI context accepted, if supplied:
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'` passed
  - generated `.codex-dock/host.env` contained `Amir-M5` and `home`, both `AUTH_MODE=none`, and no forbidden secret-shaped keys
  - simulator logs showed `host registry loaded from environment hosts=2` and `bearer_configured=false` for both hosts
  - Mobile MCP showed both host cards, `Amir-M5` rows visible, and `Home` source-specific partial status against `ws://100.66.11.7:4510`
  - `rtk make app ... CODEX_DOCK_HOST_HOME_WS='ws://127.0.0.1:9'` passed for deliberate one-host failure proof
  - Mobile MCP showed `Partial: Home: App-server disconnected: Could not connect to the server.`, explicit `Home Dock load failed` / `Home Agents load failed`, and preserved `Amir-M5 / main` rows
  - final restore launch pointed `home` back to `ws://100.66.11.7:4510`
  - `rtk make app-server-status && rtk make dock-relay-status` passed with Mac bundle `status: ready`
  - Mac `curl` proof for `http://100.66.11.7:4510/readyz` and `/statusz` passed
  - `rtk npm test` passed 47 relay tests and 21 host-service tests with 0 failures
  - `rtk swift test --filter DockConfigurationTests` passed 18 tests with 0 failures
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Findings added:
  - none.
- Findings resolved:
  - README runbook now matches the implemented host-service wrapper, generated env split, exact Mac/`home` commands, and physical-device deferral policy.
  - Final non-physical two-host app behavior proof is implemented: both configured hosts load in the simulator, and one-host failure is visible without hiding the healthy host.
- Findings carried forward:
  - physical behavior checks are deferred manual QA for Amir under the parent dock rule.
  - Realtime transcription on `home` remains unclaimed because no `OPENAI_API_KEY` is configured there; relay status correctly reports it disabled.
- Verdict: approve for Phase 6 README and final non-physical multi-host app smoke
- Next audit focus: no agent-side Multi-host implementation blocker remains; keep the parent physical QA checklist current when Amir tests physical devices.
