# Plan Audit Log

Plan: `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve
Last reviewed: 2026-05-28T21:51:05Z
Scope: whole top-level orchestration plan plus child-plan alignment

## Current Blocking Findings

None open.

## Current Non-Blocking Findings

None open for the plan text.

## Current Implementation Findings

- [ ] XIMPL-002 - Physical visual automation is deferred by WebDriverAgent
  - Lens: proof-and-phase-exit
  - Evidence: physical `iPhone 14` install/launch/process proof passed on device `00008110-000E04940240A01E`, relay-backed host smoke passed separately with no phone-side bearer env, and latest-message row preview passed real production-relay proof against `ws://127.0.0.1:4510`. The latest physical app launch ran as pid `4355` against relay pid `71847`, but `mobile_list_elements_on_screen` and `mobile_take_screenshot` both returned `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
  - Current accepted Connectivity proof: Mobile MCP on non-Pro simulator `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`, captured Dock, Archive, Relay, and Session detail with the root online indicator against `ws://192.168.50.117:4510`; screenshots are under `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/`.
  - Consequence: top-level physical behavior checks are Amir-owned deferred manual QA, not an agent-side blocking gate while simulator/local/real-relay/service-status proof passes. This deferral now covers all physical-only checks, not just WebDriverAgent visual automation: do not run, require, retry, wait on, or ask for physical iPhone install/launch, Mobile MCP, screenshots, accessibility, audio, or other physical proof unless Amir explicitly asks in that turn.
  - Required follow-through: keep the parent deferred physical-device manual QA checklist current, assume the physical path works for planning purposes when non-physical proof passes, and do not retry physical Mobile MCP unless Amir explicitly asks.

## Resolved Implementation Findings

- [x] XIMPL-001 - Top-level final acceptance still had unimplemented later phases
  - Lens: phase-frontier-review, requirement-traceability
  - Evidence: Agents, Connectivity, Realtime, latest-message row preview, and Multi-host are implemented/accepted for current non-physical gates. Multi-host now has Phase 1A, Phase 2, Phase 1B/3A fake-runner lifecycle core, Phase 3B Makefile/live Mac launchd proof, Phase 4A generated two-host env/simulator app consumption, Phase 3C live Linux systemd proof on `home`, README runbook, and final simulator multi-host smoke implemented.
  - Consequence: no agent-side implementation blocker remains for the top-level program under the current physical-device deferral rule.
  - Required follow-through: Amir-owned physical manual QA remains tracked under XIMPL-002 and the parent deferred physical-device checklist.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Top-level orchestration | `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md` | Owns cross-plan phase order, shared security rules, ownership matrix, and final proof gates. | Codex | read |
| Child plans | Agents, Connectivity, Realtime, and Multi-host plan files | Must be self-consistent with the top-level order and security baseline. | Codex, Sagan, Raman, Boyle, Arendt, Dewey | read |
| Existing child audit logs | Four child `_PLAN_AUDIT.md` files | Prior readiness findings must not be lost or contradicted by cross-plan edits. | Codex | read |
| No-phone-secret baseline | `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`, `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28_WORKLOG.md` | Phase 0 foundation for all later plans. | Codex | read |
| Host config/security code | `DockHostConfiguration.swift`, `RelayBootstrapStore.swift`, `RelayDiscovery.swift`, `AppServerClient.swift`, `Makefile`, `scripts/dock-relay.mjs`, `scripts/dock-relay-bonjour.mjs` | Confirms optional bearer, nil-bearer physical path, host-side raw token, Bonjour TXT, and relay `phoneAuth=none`. | Codex, child agents | read |
| Dock/Agents current code | `DockStore.swift`, `ArchiveStore.swift`, `HostSettingsStore.swift`, `DockView.swift`, `SessionSummary*`, `scripts/dock-relay.mjs` | Confirms current old loader/filter shape and target Agents dependency for later plans. | Codex, Sagan, Raman, Dewey | read |
| Connectivity current code | `AppServerClient.swift`, `ThreadDetailStore.swift`, `DockView.swift`, `RelayBootstrapStore.swift`, relay upstream paths | Confirms no `AppConnectivityStore`, no public `connectionStates`, view-local refresh, and bootstrap pre-root lifecycle gap. | Codex, Raman, Dewey | read |
| Realtime/current voice code | `TranscriptionService.swift`, `ThreadDetailStore.swift`, `AppServerMethods.swift`, `AppServerClient.swift`, `AudioTranscriptionDTO.swift`, `scripts/dock-relay.mjs`, `scripts/dock-relay-transcription.mjs` | Confirms one-shot relay default, direct OpenAI side door, and `audio/transcribe` cleanup needs. | Codex, Boyle, Arendt, Dewey | read |
| Multi-host/service setup code | `Makefile`, `README.md`, `scripts/dock-relay.mjs`, host registry/config stores | Confirms Mac-only hard-coded service path and generated app-config secret risks. | Codex, Arendt, Dewey | read |

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
| XDEC-001 | What is the authoritative order for the four child plans? | Run independently; or sequence by shared contracts. | Independent execution can duplicate owners and preserve stale contracts. | Phase 0 no-phone-secret baseline, then Agents, Connectivity, Realtime, Multi-host, integrated proof. | Codex from repo/plan evidence | Top-level Sections 2-3; child Section 0.6 and Phase 0 gates | resolved |
| XDEC-002 | Is phone-side relay bearer auth the physical default or a dev/hardening profile? | Physical phone requires bearer; or personal physical path has no phone bearer. | Wrong choice leaks/seeks phone secrets and mislabels valid hosts as auth failures. | Physical path is no phone bearer; bearer remains explicit dev/hardening only. | Codex from implemented code/worklog | Top-level Sections 1, 3, 5; child security invariants and phase checks | resolved |
| XDEC-003 | Who owns app-wide connectivity/lifecycle after Multi-host exists? | Connectivity and Multi-host both create status/reconnect; or Connectivity owns and Multi-host feeds it. | Duplicate truth and conflicting UI/status behavior. | Connectivity owns `AppConnectivityStore` and lifecycle; Multi-host adds service/status inputs and verifies hosts. | Codex from top-level owner matrix | Top-level Sections 2, 4; Multi-host Sections 0.6, 5.5, 7 | resolved |
| XDEC-004 | Can Multi-host preserve `audio/transcribe` as a production fallback? | Preserve old one-shot relay method; or consume Realtime final contract. | Host service setup would fossilize stale voice behavior. | Realtime lands first; Multi-host consumes final Realtime transcription contract and does not preserve `audio/transcribe` as production fallback. | Codex from Realtime plan/code evidence | Top-level Sections 2-3; Realtime Phase 5; Multi-host Sections 0.6, 5.4, 6, 7 | resolved |
| XDEC-005 | Who owns Dock row summaries showing the latest meaningful message instead of only the opening prompt? | Leave to completed Agents phase; attach to Connectivity; or make it a cross-cutting final acceptance requirement. | If unowned, real thread rows stay hard to scan even if tab counts and connectivity work pass. | Top-level final acceptance owns it unless a later child plan explicitly absorbs it. | User clarification + Codex | Top-level non-negotiables, shared baseline, `Cross-Cutting Final Acceptance - Dock Row Latest-Message Preview`, Decision Log "Dock rows must show the latest meaningful message" | resolved |

## Audit Synthesis

The top-level plan is ready. It names a falsifiable cross-plan outcome, identifies Phase 0 as the implemented no-phone-secret relay baseline, assigns shared owners, and orders the four child plans so later work consumes earlier contracts instead of rebuilding them.

The child plans now carry the same order and security boundary: Connectivity has a hard Agents prerequisite, Realtime has a hard Connectivity prerequisite, and Multi-host has hard Agents/Connectivity/Realtime prerequisites. The no-phone-secret physical iPhone model is carried through optional `DockHostConfiguration.bearerToken`, relay `phoneAuth=none`, host-side raw/OpenAI secrets, and non-secret generated app config.

## Pass History

### Pass 1 - 2026-05-28T12:01:57Z

- Mode: plan-readiness
- Scope: top-level orchestration plan plus the four child plans
- Baseline reviewed: current worktree docs after cross-plan repairs
- Test/CI context accepted, if supplied: none; docs-only plan-readiness audit
- Agents/lenses run: Sagan audited Agents, Raman audited Connectivity, Boyle audited Realtime, Arendt audited Multi-host, Dewey audited cross-plan dependencies/security; parent synthesis ran all required plan-audit lenses plus docs-contract-drift and security-boundary
- Code areas read: host config/security baseline, Dock/Agents loading, connectivity/session lifecycle, voice/transcription, relay, Makefile/service setup, README/runbook anchors
- Findings added: cross-plan order/security/ownership findings from Raman, Boyle, Arendt, and Dewey
- Findings resolved: all cross-plan findings were repaired in the top-level plan and child plans before this verdict
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code changes land against any child plan, with special attention to shared owners and side-door closure

### Pass 2 - 2026-05-28T14:25:36Z

- Mode: implementation-frontier audit
- Scope: top-level orchestration state after Agents completion, Connectivity partial Phase 6 proof, and latest-message row preview scope assignment
- Baseline reviewed: current top-level plan, Connectivity plan/log/audit, README, and relay/Swift proof summaries
- Test/CI context accepted, if supplied: Agents proof previously passed; Connectivity proof includes `rtk swift test` 147 tests with 5 skipped and 0 failures, `rtk npm test` 33 tests with 0 failures, `rtk make dock-relay` healthy relay pid `39096`, no-phone-bearer real-host smoke 4 tests with 1 skipped and 0 failures, and physical `iPhone 14` install/launch/process proof
- Agents/lenses run:
  - Zeno audited cross-plan proof drift and scope ownership.
  - Parent ran `plan-audit` implementation-frontier lenses.
- Findings added:
  - XIMPL-001: top-level final acceptance still has future phases and latest-message row-preview work.
  - XIMPL-002: physical visual proof was blocked by WebDriverAgent at this pass; Pass 4 later accepted Connectivity simulator visual proof while keeping physical navigation deferred.
  - XDEC-005 records the latest-message preview ownership decision.
- Findings resolved:
  - The latest-message row-preview requirement is now explicitly in top-level non-negotiables, shared baseline, final acceptance, and decision log.
  - Stale `31`/`32` relay test counts were updated to the current `33`-test proof where this top-level plan summarizes Connectivity.
- Findings carried forward:
  - Realtime and Multi-host are not implemented.
  - Latest-message row preview is scoped but not implemented.
  - At this pass, physical visual proof was blocked by WebDriverAgent; Pass 4 later accepted Connectivity simulator visual proof while keeping physical navigation deferred.
- Verdict: scope-inconclusive for full top-level implementation; ready to keep executing the ordered child plans.
- Next audit focus:
  - After Realtime and Multi-host land, audit the full final acceptance frontier including latest-message row preview and physical `iPhone 14` visual proof.

### Pass 3 - 2026-05-28T14:38:13Z

- Mode: implementation-frontier audit follow-up
- Scope: top-level orchestration after Connectivity Swift blocker repairs
- Baseline reviewed: Connectivity pass 6 audit, current top-level phase status, and physical proof notes
- Test/CI context accepted, if supplied: `rtk swift test` 147 tests with 5 skipped and 0 failures; `rtk npm test` 33 tests with 0 failures; physical `iPhone 14` install/launch/process proof passed; WDA screen inspection was still blocked at this pass
- Findings added:
  - none at the top-level beyond the already-open XIMPL-001 and XIMPL-002.
- Findings resolved:
  - Connectivity's Swift code-review blockers were resolved in the child audit log.
- Findings carried forward:
  - Realtime and Multi-host are still unimplemented.
  - Latest-message row preview remains scoped but unimplemented.
  - At this pass, physical visual proof remained blocked by WebDriverAgent; Pass 4 later accepted Connectivity simulator visual proof while keeping physical navigation deferred.
- Verdict: scope-inconclusive for full top-level implementation; Connectivity code shape is no longer the blocker.
- Next audit focus:
  - Same as Pass 2: final acceptance frontier, latest-message row preview, and physical `iPhone 14` visual proof.

### Pass 4 - 2026-05-28T14:51:10Z

- Mode: implementation-frontier audit follow-up
- Scope: top-level orchestration after Connectivity simulator proof acceptance
- Baseline reviewed: Connectivity implementation log, Connectivity plan audit Pass 7, top-level phase status, and Mobile MCP simulator proof notes
- Test/CI context accepted, if supplied: prior Connectivity full Swift/relay proof remains accepted; `rtk swift test --filter AppConnectivityStoreTests` executed 11 tests with 0 failures after the SwiftUI simulator fix; Mobile MCP simulator proof captured Dock, Archive, Relay, and Session detail
- Findings added:
  - none at the top-level beyond the already-open future-phase frontier.
- Findings resolved:
  - Connectivity visual proof is now accepted through the user-approved non-Pro simulator fallback while physical WebDriverAgent remains unavailable.
- Findings carried forward:
  - Realtime and Multi-host are still unimplemented.
  - Latest-message row preview remains scoped for final top-level acceptance, with current Mobile MCP readback providing supportive evidence on real Dock rows.
  - Physical `iPhone 14` screen/navigation automation remains deferred until WebDriverAgent is available.
- Verdict: scope-inconclusive for full top-level implementation; Connectivity can move forward to Realtime.
- Next audit focus:
  - Realtime implementation and final acceptance frontier after later phases land.

### Pass 5 - 2026-05-28T15:32:47Z

- Mode: implementation-frontier audit follow-up
- Scope: cross-cutting latest-message Dock row preview implementation
- Baseline reviewed: `scripts/dock-relay.mjs`, `scripts/dock-relay-phase5.test.mjs`, `CodexDock/Models/SessionSummaryMapper.swift`, `CodexDockTests/ThreadListMappingTests.swift`, top-level plan row-preview section, README fake-evidence wording, and physical iPhone proof output
- Test/CI context accepted, if supplied:
  - `node --check scripts/dock-relay.mjs` passed.
  - `node --check scripts/dock-relay-phase5.test.mjs` passed.
  - `rtk swift test --filter ThreadListMappingTests` executed 12 tests with 0 failures.
  - `rtk npm run test:relay` executed 42 tests with 0 failures.
  - Real production-relay proof against `ws://127.0.0.1:4510` passed: a real `thread/list` row preview matched the latest real `userMessage`/`agentMessage` text from `thread/turns/list` for thread `019e6f2a-1af2-7c40-9ede-0a3a0a9cded4`.
  - Physical `iPhone 14` `00008110-000E04940240A01E` proof passed for build/install/launch/process: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`, relay pid `71847`, app pid `4355`.
  - Physical visual proof remains blocked: `mobile_list_elements_on_screen` and `mobile_take_screenshot` both report WebDriverAgent is not running.
- Findings added:
  - none beyond the already-open physical WebDriverAgent visual blocker and future Realtime/Multi-host frontier.
- Findings resolved:
  - Latest-message row preview is no longer only scoped; it is implemented and proven on real relay/app-server data.
  - Row preview extraction excludes reasoning, plan, command, tool, transcript, and output items, so this does not reintroduce the thread-detail spam problem into Dock rows.
- Findings carried forward:
  - Realtime and Multi-host are still not final-accepted.
  - Physical `iPhone 14` screen/navigation automation remains deferred until WebDriverAgent is available.
- Verdict: latest-message Dock row data path is implementation-accepted; full top-level implementation remains scope-inconclusive because later phases remain.
- Next audit focus:
  - Realtime real OpenAI/iPhone proof and Multi-host service setup.

### Pass 6 - 2026-05-28T20:49:09Z

- Mode: implementation-frontier audit follow-up
- Scope: top-level orchestration after Realtime acceptance, physical-device deferral policy, and Multi-host Phase 1B/3A lifecycle core
- Baseline reviewed: parent plan Phase 4 status, parent deferred physical QA checklist, Multi-host child plan/log/audit/review, host-service lifecycle scripts/tests, and read-only subagent findings
- Test/CI context accepted, if supplied:
  - `rtk node --check scripts/codex-dock-host-service-runtime.mjs` passed
  - `rtk node --check scripts/codex-dock-host-service.mjs` passed
  - `rtk node --check scripts/codex-dock-host-service.test.mjs` passed
  - `rtk npm run test:host-service` passed 17 tests with 0 failures
  - `rtk npm test` passed 47 relay tests and 17 host-service tests with 0 failures
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258` during the host-service lifecycle slice
- Findings added:
  - none beyond the already-open final Multi-host frontier and deferred physical QA item.
- Findings resolved:
  - Parent and child docs now explicitly record that physical-device testing is not an agent-side blocker for now; physical checks are listed as Amir-owned deferred manual QA.
  - Multi-host has moved past dry-run render/status only: fake-runner proof now covers lifecycle adapters, token creation/reuse, status/log/doctor redaction, payload/cookie/header secrecy, failure redaction, child env scrubbing, and Node 25-safe service env option parsing.
- Findings carried forward:
  - Live launchd/systemd service-manager proof is still unclaimed.
  - `Makefile` wrapper replacement is still unimplemented.
  - Generated two-host app config, README runbook, `home` setup, and final app multi-host smoke remain.
  - Physical behavior checks remain deferred manual QA for Amir.
- Verdict: host-service lifecycle core is implementation-accepted for fake-runner proof only; full top-level implementation remains scope-inconclusive because real Multi-host host/app proof remains.
- Next audit focus:
  - `Makefile` wrapper cutover, live Mac launchd proof, live Linux systemd user proof on `home`, generated app config, README runbook, and app multi-host smoke.

### Pass 7 - 2026-05-28T21:07:40Z

- Mode: implementation-frontier audit follow-up
- Scope: top-level orchestration after Multi-host Makefile wrapper cutover and live Mac launchd proof
- Baseline reviewed: parent Phase 4 status, parent deferred physical QA rule, Multi-host child plan/log/audit/review, `Makefile`, host-service scripts/tests, and live status proof
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
  - `rtk make app SIM='iPhone 17'` failed before build/launch only because two simulators share that name
  - `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'` passed on the accepted non-Pro simulator
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Findings added:
  - none beyond the already-open final Multi-host frontier and deferred physical QA item.
- Findings resolved:
  - Multi-host no longer lacks live Mac launchd proof: `rtk make services` now installs/starts/reuses the host-service bundle through the wrapper and proves raw app-server, relay readyz, relay statusz raw-history health, and app-facing relay readyz.
  - `Makefile` no longer owns duplicate inline launchd render/start logic for the normal service path.
  - Physical-device testing remains explicitly deferred and was not used as an agent-side blocker.
- Findings carried forward:
  - Live Linux systemd proof on `home` remains unclaimed.
  - Generated two-host app config and app consumption remain unimplemented.
  - README runbook rewrite remains unimplemented.
  - Final `Amir-M5` plus `home` app multi-host smoke remains unclaimed.
  - Physical behavior checks remain deferred manual QA for Amir.
- Verdict: Makefile wrapper and live Mac launchd proof are implementation-accepted; full top-level implementation remains scope-inconclusive because Linux/home, generated app config, README, and final app multi-host behavior remain.
- Next audit focus:
  - live Linux systemd proof on `home`, generated app config, README runbook, and app multi-host smoke.

### Pass 8 - 2026-05-28T21:20:03Z

- Mode: implementation-frontier audit follow-up
- Scope: top-level orchestration after Multi-host Phase 4A generated two-host env and simulator app consumption
- Baseline reviewed: parent Phase 4 status, parent deferred physical QA rule, Multi-host child plan/log/audit/review, `Makefile`, host-service env helper/tests, Swift host registry/config tests, generated `.codex-dock/host.env`, simulator app logs, and subagent findings
- Test/CI context accepted, if supplied:
  - `rtk node --check scripts/codex-dock-host-service-env.mjs && rtk node --check scripts/codex-dock-host-service.mjs` passed
  - `rtk npm run test:host-service` passed 21 tests with 0 failures
  - `rtk swift test --filter DockConfigurationTests` passed 18 tests with 0 failures
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'` passed
  - `.codex-dock/host.env` contained `Amir-M5` and `home`, both auth modes `none`, and no forbidden app-secret keys
  - simulator logs showed `host registry loaded from environment hosts=2` and `bearer_configured=false` for both hosts
  - `rtk swift test --filter DockStoreTests` passed 19 tests with 0 failures
  - `rtk make app-server-status && rtk make dock-relay-status` passed with bundle `status: ready`
  - `rtk npm test` passed 47 relay tests and 21 host-service tests with 0 failures
  - `rtk swift test` passed 187 tests with 5 skipped and 0 failures
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Findings added:
  - none beyond the already-open final Multi-host frontier and deferred physical QA item.
- Findings resolved:
  - Generated two-host env config and simulator app consumption are now implemented for the env-first path.
  - The simulator launch path no longer hard-codes app host env or sources service env; it reads `.codex-dock/host.env`.
  - The generated app config path now has focused redaction and Swift validation proof for duplicate hosts and auth modes.
- Findings carried forward:
  - Live Linux systemd proof on `home` remains unclaimed.
  - README runbook rewrite remains unimplemented.
  - Final `Amir-M5` plus `home` app behavior proof remains unclaimed because `home` is configured but not running as a real Dock service yet.
  - Physical behavior checks remain deferred manual QA for Amir.
- Verdict: generated two-host env and simulator app-consumption proof are implementation-accepted; full top-level implementation remains scope-inconclusive because Linux/home, README, and final two-host behavior remain.
- Next audit focus:
  - live Linux systemd proof on `home`, README runbook, and final app multi-host smoke.

### Pass 9 - 2026-05-28T21:31:28Z

- Mode: implementation-frontier audit follow-up
- Scope: top-level orchestration after Multi-host Phase 3C live Linux systemd proof on `home`
- Baseline reviewed: parent Phase 4 status, parent deferred physical QA rule, Multi-host child plan/log/audit/review, `Makefile`, host-service scripts/tests, remote `home` status/doctor output, local Mac relay curl proof, and generated `home` host env
- Test/CI context accepted, if supplied:
  - remote deploy hygiene passed with no `.env`, no `env.bak`, no `.codex-dock/`, and host-service files present
  - remote `rtk npm ci` passed
  - remote host-service syntax checks passed
  - remote `rtk npm run test:host-service` passed 21 tests with 0 failures
  - remote `rtk make services HOST_SERVICE_PLATFORM=linux ... CODEX_DOCK_REAL_HOST_ID=home ... CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510 ...` passed
  - remote `host-service-status` passed with `status: ready` and `serviceManager: systemd-user`
  - remote `host-service-doctor` passed with `status: passed` and `problems: []`
  - local Mac `curl -fsS --max-time 5 http://100.66.11.7:4510/readyz` returned `{"ok":true,"service":"codex-dock-relay","auth":"none"}`
  - local Mac `/statusz` proof showed host id `home`, history health OK, `phoneAuth: none`, and Realtime transcription disabled because no OpenAI key was copied to `home`
  - generated `home` `.codex-dock/host.env` contained only non-secret `home` app config and no stale `AMIR_M5` keys
  - local `rtk npm test` passed 47 relay tests and 21 host-service tests with 0 failures
  - simulator launch loaded `Amir-M5` plus `home` from generated env with no bearer configured
  - `.env` mtime remained `1779986258`
- Findings added:
  - none beyond the already-open final Multi-host frontier and deferred physical QA item.
- Findings resolved:
  - Live Linux systemd proof on `home` is now implemented and accepted.
  - The host-service wrapper works under both macOS launchd and Linux systemd user managers for the current proof level.
  - Physical-device testing remained explicitly deferred and was not used as an agent-side blocker.
- Findings carried forward:
  - README runbook rewrite remains unimplemented.
  - Final `Amir-M5` plus `home` app multi-host smoke remains unclaimed.
  - Realtime transcription on `home` remains unclaimed because `home` intentionally has no copied `OPENAI_API_KEY`.
  - Physical behavior checks remain deferred manual QA for Amir.
- Verdict: live Linux systemd proof on `home` is implementation-accepted; full top-level implementation remains scope-inconclusive because README and final two-host app behavior remain.
- Next audit focus:
  - README runbook and final app multi-host smoke.

### Pass 10 - 2026-05-28T21:38:22Z

- Mode: implementation-frontier audit follow-up
- Scope: top-level orchestration after Multi-host Phase 6 README and final non-physical app smoke
- Baseline reviewed: parent Phase 4/5 status, parent deferred physical QA rule, Multi-host child plan/log/audit/review, `README.md`, generated `.codex-dock/host.env`, simulator app logs, Mobile MCP element readbacks, screenshots, Mac status output, and `home` relay `/readyz`/`/statusz`
- Test/CI context accepted, if supplied:
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'` passed
  - simulator logs showed `host registry loaded from environment hosts=2`, with `bearer_configured=false` for `Amir-M5` and `home`
  - Mobile MCP showed both host cards, `Amir-M5` rows visible, and a source-specific `Home` partial error against the real `home` relay
  - deliberate one-host failure launch with `CODEX_DOCK_HOST_HOME_WS='ws://127.0.0.1:9'` passed and showed clear Home offline errors while preserving `Amir-M5` rows
  - final restore launch pointed `home` back to `ws://100.66.11.7:4510`
  - `rtk make app-server-status && rtk make dock-relay-status` passed with Mac bundle `status: ready`
  - Mac `curl` proof for `http://100.66.11.7:4510/readyz` and `/statusz` passed
  - generated `.codex-dock/host.env` contained both hosts and no forbidden secret-shaped keys
  - screenshots saved under `/tmp/codex-client/20260528T213700Z/`
  - `rtk npm test` passed 47 relay tests and 21 host-service tests with 0 failures
  - `rtk swift test --filter DockConfigurationTests` passed 18 tests with 0 failures
  - `rtk git diff --check` passed
  - `.env` mtime remained `1779986258`
- Findings added:
  - none beyond the already-tracked deferred physical QA item.
- Findings resolved:
  - README runbook rewrite is now implemented.
  - Final non-physical `Amir-M5` plus `home` app smoke is now implemented.
  - XIMPL-001 is resolved for the current agent-side scope.
- Findings carried forward:
  - Physical behavior checks remain deferred manual QA for Amir.
  - Realtime transcription on `home` remains unclaimed unless `OPENAI_API_KEY` is intentionally configured there later.
- Verdict: approve for current top-level agent-side implementation scope; physical proof remains Amir-owned deferred manual QA, not an agent-side blocker.
- Next audit focus:
  - none for agent-side implementation unless Amir revokes the physical-device deferral rule or requests another phase.

### Pass 11 - 2026-05-28T21:51:05Z

- Mode: fresh-consult implementation cross-plan audit follow-up
- Scope: whole top-level implementation plan, child phase closeout status, and stale reopen candidates after Multi-host closeout
- Fresh consult:
  - Runtime: Cursor Agent Composer 2.5 via `/Users/aelaguiz/.local/bin/agent`
  - Model: `composer-2.5-fast`
  - Run directory: `/tmp/fresh-consult/cross-plan-composer-20260528T214554Z`
  - Final report: `/tmp/fresh-consult/cross-plan-composer-20260528T214554Z/final.txt`
  - Verdict: `pass-with-notes`
  - Blocking: none
- Test/CI context accepted, if supplied by the consult:
  - `rtk swift test` passed with 187 tests and 5 skipped
  - `rtk npm test` passed relay and host-service suites
  - `rtk npm run test:relay` passed
  - `rtk make app-server-status` passed
  - `rtk make dock-relay-status` passed
- Findings added:
  - none blocking.
- Findings resolved in this follow-up:
  - Cross-plan Phase 2 no longer says Connectivity is merely in progress after Phases 1-6 were completed.
  - Cross-plan Phase 5 now has an explicit current closeout status and records the Composer consult.
  - Multi-host Section 2.2 no longer lists plan-start broken/missing items as if they are current; each item is marked resolved, deferred, or intentionally unclaimed.
  - Connectivity phase implementation notes no longer say later phases remain outstanding after Phase 6 closeout.
- Findings carried forward:
  - XIMPL-002 remains open as deferred physical manual QA only.
  - Realtime transcription on `home` remains unclaimed unless an OpenAI key is intentionally configured there later.
- Verdict: approve for current top-level agent-side implementation scope; no implementation phase needs to be reopened. The only reopen candidates from Composer were doc-status drift and are resolved here.
