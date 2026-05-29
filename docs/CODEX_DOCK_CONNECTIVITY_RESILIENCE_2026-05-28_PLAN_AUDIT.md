# Plan Audit Log

Plan: docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md
Audit log: docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_PLAN_AUDIT.md
Current plan verdict: ready
Current implementation code-review verdict: approved for current Connectivity closeout with deferred physical WebDriverAgent follow-up
Last reviewed: 2026-05-28T14:51:10Z
Scope: whole plan

## Current Blocking Findings

None open.

## Current Deferred Follow-Ups

- [ ] CONN-PROOF-001 - Physical visual automation remains deferred by WebDriverAgent
  - Lens: proof-and-phase-exit, docs-contract-drift
  - Evidence: `mobile_list_elements_on_screen` and `mobile_save_screenshot` on physical device `00008110-000E04940240A01E` both returned `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
  - Current accepted proof: Mobile MCP works on the user-approved non-Pro simulator `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`; saved screenshots under `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/` prove Dock, Archive, Relay, and Session detail with the root online indicator against `ws://192.168.50.117:4510`.
  - Consequence: no current Connectivity closeout blocker remains. Physical `iPhone 14` screen/navigation automation is still deferred until WebDriverAgent runs on the real device.
  - Required follow-through: run the physical `iPhone 14` visual proof after WebDriverAgent is running.

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

## Resolved Implementation Findings

- [x] CONN-IMPL-001 - Initial `thread/resume` could outlive a closed downstream phone socket
  - Lens: caller-invariant-state, relay lifecycle, security/network boundary
  - Evidence: `resumeThread` created a new upstream client and awaited `initialize`/`thread/resume` before assigning `session.upstream`; if the phone WebSocket closed during that wait, the close handler only closed the old assigned upstream.
  - Required repair: bind initial resume work to the downstream session generation and close any just-created upstream if the downstream socket closes or a newer resume supersedes it.
  - Status: resolved
  - Resolution evidence: `scripts/dock-relay.mjs` now checks `isSessionActive(...)` before attaching/forwarding upstream clients; `scripts/dock-relay-phase5.test.mjs` adds `thread/resume abandons initial upstream if downstream closes before resume completes`; `rtk npm run test:relay` and `rtk npm test` each executed 33 tests with 0 failures.

- [x] CONN-IMPL-002 - Relay Phase 5 growth needed decomposition before final review
  - Lens: tiny-team-maintainability, elegance-and-code-judo
  - Evidence: relay runtime/test work was large enough to make `scripts/dock-relay.mjs` and relay tests hard to scan.
  - Required repair: split the JSON-RPC upstream client and Phase 5 tests without changing the relay contract.
  - Status: resolved
  - Resolution evidence: `scripts/dock-relay-json-rpc-client.mjs`, `scripts/dock-relay-phase5.test.mjs`, and `scripts/dock-relay-test-helpers.mjs` now own the extracted client, Phase 5 tests, and shared test helpers; current key file sizes stay below 1k lines except pre-existing `CodexDockTests/AppServerClientTests.swift`.

- [x] CONN-IMPL-003 - Latest-message row preview requirement was not assigned to an acceptance owner
  - Lens: cross-plan ownership, docs-contract-drift
  - Evidence: user reported Dock doc summaries show the original message instead of the latest message, and that row readability requirement was not clearly owned by Connectivity.
  - Required repair: place the requirement in the top-level dock plan so it cannot be lost between child plans.
  - Status: resolved for scope assignment
  - Resolution evidence: `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md` now has the non-negotiable, shared baseline bullet, and `Cross-Cutting Final Acceptance - Dock Row Latest-Message Preview` section.

- [x] CONN-IMPL-004 - Reconnect could open a transport after the app backgrounded during backoff sleep
  - Lens: no-background-spin, caller-invariant-state
  - Evidence: `AppServerClient.runReconnectLoop(reason:)` checked the foreground gate before sleeping, but did not re-check it after sleeping and before `openTransport(mode:)`.
  - Required repair: re-check foreground work immediately before reconnect open/initialize.
  - Status: resolved
  - Resolution evidence: `AppServerClient` now waits on `foregroundWorkGate` after backoff and before opening transport; `testReconnectDoesNotOpenIfAppBackgroundsDuringBackoffSleep` covers the race.

- [x] CONN-IMPL-005 - Foreground resume could rehydrate before the socket was connected and strand detail stale
  - Lens: foreground-claims-need-proof, thread-detail lifecycle
  - Evidence: `ThreadDetailStore.handleForegroundResuming(_:)` ran compact read/turns/resume immediately even when the latest connection state was reconnecting.
  - Required repair: track latest connection state, wait in `.reconnecting("Resuming")` until `.connected`, then run compact rehydrate.
  - Status: resolved
  - Resolution evidence: `ThreadDetailStore` now tracks `latestConnectionState`; `testForegroundResumeWaitsForReconnectBeforeRehydratingDetail` proves no read is attempted until `.connected`.

- [x] CONN-IMPL-006 - Root resume could overwrite `Resuming` with old tab/store facts
  - Lens: foreground-claims-need-proof, root lifecycle ownership
  - Evidence: `resumeForegroundWork()` rebound connectivity reporters before refresh work completed, causing stores to replay stale pre-background state.
  - Required repair: keep lifecycle `Resuming` as an overlay until active resume finishes; do not rebind/replay old store state at the start of resume.
  - Status: resolved
  - Resolution evidence: `resumeForegroundWork()` no longer calls `bindConnectivity()`; `AppConnectivityStore` masks source observations with lifecycle `resuming` until `.active`; `testLifecycleResumingMasksOldStoreFactsUntilActiveClearsIt` covers the behavior.

- [x] CONN-IMPL-007 - App-wide connectivity was still last-writer-wins per host
  - Lens: canonical-owner-and-SSOT, drift-proof-coupling
  - Evidence: Dock, Archive, host tests, thread detail, and lifecycle all wrote into the same `records[host.id]` snapshot slot.
  - Required repair: keep separate observations by source and roll them up with explicit precedence.
  - Status: resolved
  - Resolution evidence: `AppConnectivityStore` now stores per-host observations for Dock, Archive, host tests, and thread detail plus a lifecycle overlay; `testThreadDetailStaleIsNotOverwrittenByDockOnline` covers the stale-over-online case.

- [x] CONN-IMPL-008 - Bootstrap non-ready states bypassed the global indicator path
  - Lens: bootstrap lifecycle, global indicator ownership
  - Evidence: `CodexDockBootstrapView` rendered `.starting`, `.discovering`, and `.failed` directly without `AppConnectivityStore`/`GlobalConnectivityIndicatorView`.
  - Required repair: mount the same global indicator/store around non-ready bootstrap and pass that store into root when the registry becomes ready.
  - Status: resolved
  - Resolution evidence: `CodexDockBootstrapView` owns a bootstrap `AppConnectivityStore`, reports `RelayBootstrapState`, overlays `GlobalConnectivityIndicatorView` for non-ready states, and passes that same store into `CodexDockRootView`; `testBootstrapNonReadyStatesUseGlobalConnectivityStatus` covers state mapping.

- [x] CONN-IMPL-009 - Root view initialization mutated published connectivity state during SwiftUI rendering
  - Lens: caller-invariant-state, SwiftUI lifecycle, proof-and-phase-exit
  - Evidence: the non-Pro simulator initially rendered a blank app surface and repeatedly logged `Publishing changes from within view updates`.
  - Required repair: do not call published-state mutators from `CodexDockRootView.init(registry:...)`.
  - Status: resolved
  - Resolution evidence: `CodexDockRootView.init(registry:...)` no longer calls `connectivityStore.configure(registry)` during view construction; the simulator rendered normally afterward; `rtk swift test --filter AppConnectivityStoreTests` executed 11 tests with 0 failures.

## Current Implementation Findings

No open code-review findings against the Connectivity implementation. The remaining open item is a deferred physical-device automation follow-up, not a current Connectivity blocker: physical visual verification waits on WebDriverAgent, as recorded in `CONN-PROOF-001`.

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

### Pass 5 - 2026-05-28T14:25:36Z

- Mode: implementation-audit
- Scope: Connectivity implementation through Phase 6 partial proof
- Baseline reviewed: current worktree after relay generation guards, test split, physical `iPhone 14` relaunch proof, and latest-message row preview scope assignment
- Test/CI context accepted, if supplied: `rtk swift test` executed 142 tests with 5 skipped and 0 failures; `rtk npm run test:relay` executed 33 tests with 0 failures; `rtk npm test` executed 33 tests with 0 failures; no-phone-bearer real-host smoke executed 4 tests with 1 skipped and 0 failures; `rtk make dock-relay` reported relay pid `56959`
- Agents/lenses run:
  - Carver audited the Node relay implementation and found the initial `thread/resume` downstream-close leak; parent fixed and retested it.
  - Zeno audited plan/proof drift and found stale simulator wording, WDA visual-proof blocker, and unassigned latest-message preview scope; parent repaired the docs and kept the WDA blocker open.
  - Parent ran `plan-audit` implementation lenses plus `thermo-nuclear-code-quality-review` maintainability checks.
- Code areas read:
  - `scripts/dock-relay.mjs`
  - `scripts/dock-relay-json-rpc-client.mjs`
  - `scripts/dock-relay.test.mjs`
  - `scripts/dock-relay-phase5.test.mjs`
  - `scripts/dock-relay-test-helpers.mjs`
  - `CodexDock/AppServer/AppServerClient.swift`
  - `CodexDock/State/ThreadDetailStore.swift`
  - `CodexDock/State/AppConnectivityStore.swift`
  - `CodexDock/State/AppLifecycleCoordinator.swift`
  - `CodexDock/Features/Dock/DockView.swift`
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
  - `CodexDockTests/ThreadDetailStoreTests.swift`
  - `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`
  - `README.md`
  - parent/top-level dock plan and implementation log
- Findings added:
  - CONN-PROOF-001 remains open as proof-only blocker.
  - CONN-IMPL-001 through CONN-IMPL-003 were found and resolved during the audit pass.
- Findings carried forward:
  - At this pass, physical visual UI proof still required WebDriverAgent or accepted manual confirmation; Pass 7 later accepted the non-Pro simulator fallback for current Connectivity closeout.
- Verdict: approve-with-notes for code shape at this pass; Pass 7 later approved current Connectivity closeout with deferred physical WebDriverAgent follow-up.
- Next audit focus:
  - Once WebDriverAgent is available, verify the physical `iPhone 14` root indicator across Dock, Archive, Hosts, and Session detail and close `CONN-PROOF-001`.

### Pass 6 - 2026-05-28T14:38:13Z

- Mode: implementation-audit follow-up
- Scope: Swift blockers reported by Bohr after Pass 5
- Baseline reviewed: current worktree after background-reconnect, foreground-rehydrate, connectivity-rollup, root-resume, and bootstrap-indicator repairs
- Test/CI context accepted, if supplied: `rtk swift test` executed 147 tests with 5 skipped and 0 failures; `rtk swift test --filter AppConnectivityStoreTests` executed 11 tests with 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 31 tests with 0 failures; `rtk swift test --filter AppServerClientTests` executed 40 tests with 5 skipped and 0 failures; `rtk swift test --filter DockConfigurationTests` executed 14 tests with 0 failures; `rtk npm test` executed 33 tests with 0 failures; no-phone-bearer real-host smoke executed 4 tests with 1 skipped and 0 failures; physical `iPhone 14` install/launch/process proof passed
- Agents/lenses run:
  - Bohr audited the Swift implementation and reported five blocking findings.
  - Parent fixed each finding and reran focused plus full verification.
- Code areas read:
  - `CodexDock/AppServer/AppServerClient.swift`
  - `CodexDock/State/ThreadDetailStore.swift`
  - `CodexDock/State/AppConnectivityStore.swift`
  - `CodexDock/Features/Dock/DockView.swift`
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
  - `CodexDockTests/AppServerClientTests.swift`
  - `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`
  - `CodexDockTests/AppConnectivityStoreTests.swift`
- Findings added:
  - CONN-IMPL-004 through CONN-IMPL-008.
- Findings resolved:
  - CONN-IMPL-004 through CONN-IMPL-008.
- Findings carried forward:
  - At this pass, CONN-PROOF-001 remained open because WebDriverAgent was still not running on physical device `00008110-000E04940240A01E`; Pass 7 later accepted simulator visual proof for current Connectivity closeout.
- Verdict: approve-with-notes for code shape at this pass; Pass 7 later approved current Connectivity closeout with deferred physical WebDriverAgent follow-up.
- Next audit focus:
  - Physical `iPhone 14` screen/navigation proof after WebDriverAgent is available, plus final latest-message row-preview implementation before top-level acceptance.

### Pass 7 - 2026-05-28T14:51:10Z

- Mode: implementation-audit follow-up
- Scope: user-directed non-Pro simulator proof after physical WebDriverAgent blocker
- Baseline reviewed: current worktree after simulator launch, SwiftUI render-mutation fix, Mobile MCP simulator navigation proof, and doc proof-status repairs
- Test/CI context accepted, if supplied: `rtk swift test --filter AppConnectivityStoreTests` executed 11 tests with 0 failures after the SwiftUI fix; prior full Swift/relay proof from Pass 6 remains accepted context
- Agents/lenses run:
  - Ohm audited proof-status drift across the Connectivity and top-level dock docs.
  - Parent used Mobile MCP on simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` to capture Dock, Archive, Relay, and Session detail proof.
- Code areas read:
  - `CodexDock/Features/Dock/DockView.swift`
  - `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`
  - `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_IMPLEMENTATION_LOG.md`
  - `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_PLAN_AUDIT.md`
  - `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_THERMONUCLEAR_REVIEW.md`
  - top-level dock plan and audit
- Findings added:
  - CONN-IMPL-009 was found and resolved during simulator proof.
- Findings resolved:
  - CONN-IMPL-009.
  - CONN-PROOF-001 is no longer a current Connectivity closeout blocker because Mobile MCP simulator proof is accepted for this slice.
- Findings carried forward:
  - Physical `iPhone 14` screen/navigation automation remains deferred until WebDriverAgent runs on device `00008110-000E04940240A01E`.
- Verdict: approved for current Connectivity closeout with deferred physical WebDriverAgent follow-up.
- Next audit focus:
  - Realtime transcription plan entry, plus later physical `iPhone 14` visual navigation proof when WebDriverAgent is available.
