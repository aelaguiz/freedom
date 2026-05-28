# Plan Audit Log

Plan: docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md
Audit log: docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_PLAN_AUDIT.md
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-05-28T12:01:57Z
Scope: whole plan

## Current Blocking Findings

None open.

## Current Non-Blocking Findings

None open.

## Resolved Cross-Plan Findings

- [x] CPLA-001 - Connectivity needed a hard Agents prerequisite gate
  - Lens: depth-first-risk, code-truth-map
  - Evidence: Section 0.6 said Connectivity consumes Agents outputs, but Section 7 could start from the pre-Agents `loadSessions(for:archived:)` / `DockFilter` shape.
  - Required plan repair: Add a Phase 0 prerequisite check requiring `DockSessionQuery`, typed origin, scoped failures, counted tabs, and relay `sourceKinds` filtering before Connectivity starts.
  - Status: resolved
  - Resolution evidence: Phase 0 now requires the Agents baseline before Phase 1 starts.

- [x] CPLA-002 - Connectivity proof did not explicitly protect Agents scoped failures and counted tabs
  - Lens: proof-and-phase-exit, canonical-owner-and-SSOT
  - Evidence: Phase 3 consumed the Agents model but could pass without proving scoped failures, `DockSnapshot.tabs`, or the single `DockTabID.includes(_:)` predicate.
  - Required plan repair: Add Phase 3 exit criteria for scoped partial outcomes, `DockScopeLoadFailure`, and no duplicate tab-count predicate.
  - Status: resolved
  - Resolution evidence: Phase 3 exit criteria now require those exact tests or focused code review.

- [x] CPLA-003 - Bootstrap non-ready states could bypass the root lifecycle/status proof
  - Lens: caller-invariant-state, proof-and-phase-exit
  - Evidence: `CodexDockBootstrapView` starts discovery before `CodexDockRootView`; root-only indicator/lifecycle coverage could miss `.starting`, `.discovering`, and `.failed`.
  - Required plan repair: Require bootstrap non-ready states and pre-root `RelayBootstrapStore` scene-phase handling in Phase 3/4 exit criteria.
  - Status: resolved
  - Resolution evidence: Phase 3 and Phase 4 exit criteria now include bootstrap coverage and foreground-resume discovery behavior.

- [x] CPLA-004 - Relay auth wording implied bearer auth was the normal phone path
  - Lens: security-boundary
  - Evidence: The plan said the relay authenticates the phone-facing endpoint and the optional smoke referenced `.codex-dock/app-server.token` ambiguously.
  - Required plan repair: State `phoneAuth: none` accepts missing `Authorization`, explicit bearer mode rejects bad/missing auth, and the raw token remains host-side.
  - Status: resolved
  - Resolution evidence: Section 4.1, Phase 5 exit criteria, and Phase 6 smoke wording now carry this through.

## Current Implementation Findings

Not run. This audit is plan-readiness only; implementation has not started from this plan.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/AppServer/AppServerClient.swift`, `AppServerTransport`, `AppServerConnectionState`, `URLSessionWebSocketAppServerTransport` | Owns JSON-RPC lifecycle, state, receive loop, pending requests, and transport boundary. | Codex + explorer | read |
| Thread live owner | `CodexDock/State/ThreadDetailStore.swift`, `ThreadDetailSession`, `ThreadDetailLiveState`, `startObservation`, compact read/turns/resume path | Owns open-thread updates and recovery after reconnect. | Codex + explorer | read |
| App/root UI owner | `CodexDock/Features/Dock/DockView.swift`, `CodexDockRootView`, `DockView.runRefreshLoop`, Dock header | Root is the only correct owner for app-wide status and recurring freshness. | Codex + explorer | read |
| App lifecycle owner path | `CodexDockApp/CodexDockApp.swift`, `CodexDock/Features/Dock/CodexDockBootstrapView.swift`, `CodexDock/Features/Dock/DockView.swift`, `RelayBootstrapStore.swift`, `ThreadDetailStore.swift`, `VoiceCaptureController.swift` | Background/resume scope needs one scene-phase owner, bootstrap discovery restart, detail rehydrate, timer pause/restart, and voice safety. | Codex | read |
| Content stores | `CodexDock/State/DockStore.swift`, `ArchiveStore.swift`, `HostSettingsStore.swift`, `SessionRowProjector.swift` | Dock/Archive/Hosts provide host outcomes and must not become separate global status owners. | Codex + explorer | read |
| Session/detail UI | `CodexDock/Features/Session/SessionDetailView.swift`, `ComposerView.swift`, `RequestCardView.swift` | Detail currently has local live UI and must preserve composer/request behavior. | Codex + explorer | read |
| Relay bridge | `scripts/dock-relay.mjs`, `JsonRpcWebSocketClient`, `aggregateThreadList`, `pendingRequestsForActiveThread`, `resumeThread`, `forwardToActiveUpstream` | Relay is the phone-facing bridge and must not hide upstream death or cut out live rows. | Codex + explorer | read |
| Tests and proof surfaces | `CodexDockTests/AppServerClientTests.swift`, `DockStoreTests.swift`, `ThreadDetailStoreTests.swift`, future `AppConnectivityStoreTests.swift`, future `AppLifecycleCoordinatorTests.swift`, `scripts/dock-relay.test.mjs` | Existing tests define preservation surface and missing proof obligations; lifecycle scope adds a new focused proof surface. | Codex + explorer | read |
| Live docs/runbooks | `README.md`, `docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md`, `docs/bugs/thread-detail-large-live-thread-message-too-long-2026-05-28.md`, `docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` | Docs capture relay endpoint, compact detail path, live-row priority, and app-server protocol constraints. | Codex + explorer | read |
| Comparable patterns | Existing `@MainActor ObservableObject` stores, protocol test seams, root registry propagation, Node `node:test` helpers | Target architecture should extend local patterns, not add a new framework. | Codex | read |
| Contract/proof surfaces | `Package.swift`, `Makefile`, `README.md` service targets, optional real-host tests | Defines available verification commands and simulator/service proof. | Codex + explorer | read |

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
- [x] Conditional lenses: docs-contract-drift and security/network boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Is the app-wide indicator tab-local or root-owned? | Dock header only vs root overlay/inset | Determines state owner and visibility across screens. | Root-owned `AppConnectivityStore` and root-mounted indicator. | Agent, from user intent + repo truth | Plan Section 5.2; Decision Log "root-owned connectivity store" | resolved |
| DEC-002 | Who owns recurring Dock freshness after app-wide status exists? | Keep `DockView.runRefreshLoop` vs root lifecycle | Determines whether status freshness depends on current tab. | `CodexDockRootView` owns recurring refresh/check lifecycle; remove `DockView.runRefreshLoop`. | Agent, from user intent + repo truth | Plan Section 5.2, Section 6.2 delete list, Phase 3 checklist/exit, Decision Log "root owns recurring Dock freshness" | resolved |
| DEC-003 | What is the relay fail-loud contract after unrecoverable upstream death? | JSON-RPC error vs downstream WebSocket close | Determines whether Swift sees lifecycle state or only a request failure. | Relay closes downstream WebSocket after unsafe/exhausted upstream recovery. | Agent, from repo truth + existing Swift transport lifecycle | Plan Section 5.2, Section 6.1, Phase 5 checklist/exit, Decision Log "relay must not hide upstream death" | resolved |
| DEC-004 | Should a recoverable disconnect require user action? | Ask user to reconnect vs retry automatically while showing status | Determines whether reconnect is a recovery system or a manual workflow. | Transparent automatic recovery first; status is informational; manual action only after exhaustion, unsafe recovery, missing configuration/authentication, or unrecoverable protocol/server failure. | User clarification + agent carry-through | Plan TL;DR, Section 0, Section 5.2, Section 5.5, Phase 2, Phase 3, Phase 6, Section 9.3, Decision Log "transparent automatic recovery first" | resolved |
| DEC-005 | Is app background/resume in scope, and who owns it? | Treat as ordinary transport failure, ignore as implicit iOS behavior, or model as root-owned lifecycle with foreground recovery | Determines whether resume is reliable and whether backgrounding creates duplicate state/retry side paths. | Background/resume is in scope as expected lifecycle; root/bootstrap scene-phase coordination owns it; foreground resume revalidates/reconnects/rehydrates automatically. | User clarification + repo truth | Plan TL;DR, Section 0, Section 3, Section 5.2, Section 6.1, Phase 4, Phase 6, Section 9.3, Decision Log "backgrounding is expected lifecycle, not failure" | resolved |

## Pass History

### Pass 1 - 2026-05-28 05:55:12 CDT

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: current worktree plan after ArchStep auto-plan and consistency-pass repairs.
- Test/CI context accepted, if supplied: no implementation tests run for this plan-readiness audit.
- Agents/lenses run:
  - Three read-only code explorers covered UI/store state, app-server/session lifecycle, and relay/tests/docs.
  - Two consistency cold readers covered frontmatter/TL;DR/Sections 0-2/7-10 and Sections 3-7 architecture/call-site alignment.
  - Parent synthesis ran the required plan-audit lenses and proper-audit checklist.
- Code areas read:
  - `CodexDock/AppServer/AppServerClient.swift`
  - `CodexDock/AppServer/AppServerMethods.swift`
  - `CodexDock/State/DockStore.swift`
  - `CodexDock/State/ArchiveStore.swift`
  - `CodexDock/State/HostSettingsStore.swift`
  - `CodexDock/State/ThreadDetailStore.swift`
  - `CodexDock/State/SessionRowProjector.swift`
  - `CodexDock/Features/Dock/DockView.swift`
  - `CodexDock/Features/Archive/ArchiveView.swift`
  - `CodexDock/Features/Hosts/HostsView.swift`
  - `CodexDock/Features/Session/SessionDetailView.swift`
  - `scripts/dock-relay.mjs`
  - `scripts/dock-relay.test.mjs`
  - `CodexDockTests/AppServerClientTests.swift`
  - `CodexDockTests/DockStoreTests.swift`
  - `CodexDockTests/ThreadDetailStoreTests.swift`
  - `README.md`
  - `docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md`
  - `docs/bugs/thread-detail-large-live-thread-message-too-long-2026-05-28.md`
- Findings added:
  - Helper metadata and consistency receipt were incomplete during the consistency stage.
  - Section 8 wording could make required proof sound optional.
  - Phase 5 omitted explicit `rtk make app-server-status` and ordered endpoint smoke before service checks.
  - Dock refresh ownership was branchy.
  - Phase 1 did not fully carry stream-contract proof obligations.
  - Relay fail-loud behavior did not explicitly choose downstream WebSocket close and Swift proof.
  - Phase 3 did not require every root initializer path or required `AppConnectivityStoreTests`.
- Findings resolved:
  - The plan now marks external research as not required for this repo-grounded auto-plan.
  - Section 8 now states phase proof is required and low-bureaucracy only removes ceremony.
  - Final verification now runs `rtk make services`, `rtk make app-server-status`, and `rtk make dock-relay-status` before endpoint-dependent checks.
  - `CodexDockRootView` is the chosen recurring refresh/check lifecycle owner and `DockView.runRefreshLoop()` must be removed.
  - Phase 1 now requires explicit stream-contract proof for connection-state liveness and transient failure behavior.
  - Relay fail-loud now means downstream WebSocket close after unsafe/exhausted upstream recovery, with Swift proof.
  - Phase 3 now requires all root initializer paths and `AppConnectivityStoreTests`.
- Findings carried forward:
  - None.
- Verdict: ready
- Next audit focus:
  - After implementation begins, run `plan-audit` in implementation-audit mode against the code changes and this plan.

### Pass 2 - 2026-05-28 05:58:35 CDT

- Mode: refinement-readiness
- Scope: user clarification that recovery should be transparent and automatic when possible.
- Baseline reviewed: plan after explicit transparent-recovery edits.
- Findings added:
  - None.
- Findings resolved:
  - The TL;DR, Section 0, Section 5.2, Section 5.5, Phase 2, Phase 3, Phase 6, Section 9.3, and Decision Log now consistently state that recoverable drops retry and rehydrate automatically while the UI reports progress.
  - Manual retry is now secondary and appears only after exhaustion, unsafe recovery, missing configuration/authentication, or unrecoverable protocol/server failure.
- Findings carried forward:
  - None.
- Verdict: ready
- Next audit focus:
  - During implementation, prove with tests and simulator notes that a recoverable interruption returns to live/online without user action while the indicator shows progress.

### Pass 3 - 2026-05-28 06:12:51 CDT

- Mode: scope-expansion-readiness
- Scope: adding app background/foreground resume as an expected recoverable lifecycle state.
- Baseline reviewed: plan after background/resume lifecycle edits.
- Test/CI context accepted, if supplied: no implementation tests run for this plan-readiness audit.
- Agents/lenses run:
  - Parent read-through of the current app lifecycle owner path and plan-audit lenses; no new subagents because the scope change is narrow and code anchors are local.
- Code areas read:
  - `CodexDockApp/CodexDockApp.swift`
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
  - `CodexDock/Features/Dock/DockView.swift`
  - `CodexDock/Configuration/RelayBootstrapStore.swift`
  - `CodexDock/State/ThreadDetailStore.swift`
  - `CodexDock/Voice/VoiceCaptureController.swift`
  - `CodexDockTests/ThreadDetailStoreTests.swift`
  - `README.md`
- Findings added:
  - None.
- Findings resolved:
  - Background/resume is now explicitly in scope in the TL;DR, North Star, target architecture, call-site audit, phased plan, verification strategy, runbook, and Decision Log.
  - The former foreground-only constraint is now narrowed correctly: long-running background networking remains out of scope, but foreground resume after backgrounding is required.
  - Phase 4 now owns scene-phase coordination, timer pause/restart, relay discovery restart, detail rehydrate, voice safety, and lifecycle tests.
  - Final verification is now Phase 6 and requires simulator background/resume proof from Dock and open Session detail.
- Findings carried forward:
  - None.
- Verdict: ready
- Next audit focus:
  - During implementation, prove that foreground resume cannot publish online/live until root checks and open-thread compact rehydrate have succeeded, and that no tab-local scene-phase side door remains.

### Pass 4 - 2026-05-28T12:01:57Z

- Mode: cross-plan plan-readiness
- Scope: Connectivity alignment with top-level Phase 2 ordering and no-phone-secret baseline
- Baseline reviewed: Connectivity plan after cross-plan prerequisite/security/lifecycle repairs
- Test/CI context accepted, if supplied: none; docs-only audit pass
- Agents/lenses run: Raman audited Connectivity independently; parent synthesis ran all required plan-audit lenses plus docs-contract-drift and security-boundary
- Code areas read: `DockStore.swift`, `DockView.swift`, `CodexDockBootstrapView.swift`, `RelayBootstrapStore.swift`, `RelayDiscovery.swift`, `DockHostConfiguration.swift`, `AppServerClient.swift`, `ThreadDetailStore.swift`, `scripts/dock-relay.mjs`, `Makefile`, top-level plan, and Agents plan anchors
- Findings added: CPLA-001 through CPLA-004
- Findings resolved: CPLA-001 through CPLA-004
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after Connectivity code changes, especially Agents scoped-outcome preservation, bootstrap lifecycle coverage, and `phoneAuth: none` proof
