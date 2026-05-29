---
title: "Codex Dock - Cross-Plan Implementation Dock"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: orchestration_plan
related:
  - docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md
  - docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md
  - docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md
  - docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md
  - docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md
---

# TL;DR

Outcome: the four active Codex Dock implementation plans move as one program, not as four competing plans. The implementation order is: use the already-implemented no-phone-secret relay baseline, then implement Agents tab/live counts, then connectivity resilience, then Realtime transcription streaming, then cross-platform multi-host service setup and final two-host proof.

Why this order: Agents stabilizes the Dock row/query model before connectivity and multi-host status consume it. Connectivity creates the single app-wide lifecycle/status owner before Realtime and multi-host add more failure modes. Realtime settles the relay transcription contract before the multi-host service bundle is made portable across macOS and Linux. Multi-host setup comes after the relay/client contracts are stable so its generated service config does not immediately need a second migration.

Security baseline: the iPhone personal relay work is already implemented and is now the shared foundation. Physical iPhone app config contains only non-secret connection coordinates. The phone-to-relay path uses no client bearer token for the personal trusted LAN/Tailscale V1. The raw Codex app-server token and `OPENAI_API_KEY` stay on the host running the relay. Bearer auth remains an explicit dev/hardening profile, not the physical-phone default.

Physical-device proof target and current policy: the historical acceptance target remains the physical `iPhone 14` path with Xcode destination id `00008110-000E04940240A01E`, but physical-device testing is no longer an agent-side blocking gate for now. Simulator, local, real-relay, service-status, generated-artifact, and test-suite proof is accepted for agent closeout while Amir is away from physical testing. For the Connectivity slice and Realtime visual automation, physical install/launch/process proof passed but physical UI automation is blocked by WebDriverAgent, so visual proof uses the explicitly accepted non-Pro `feat_anim_1 - iPhone 17` simulator fallback with UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`. Basic physical iPhone 14 Realtime audio proof passed by user manual test after the empty-transcript relay fix, the detailed Realtime manual physical checklist is now marked passed by user manual check on 2026-05-28, and the Realtime code/audit/review gates pass after the structural cleanup.

Current physical-device operating rule as of 2026-05-28: no more physical device blocking for now. Physical-device testing owner is Amir, not the agent, until Amir explicitly revokes this rule. Do not require, retry, or wait on physical-device testing, physical Mobile MCP, physical screenshots, physical accessibility readback, or physical install/launch unless Amir explicitly asks for that exact action. Use local, simulator, real-relay, service-status, and generated-artifact proof as far as they can go; assume the physical path works when those checks pass; and record physical-device checks as deferred manual QA for Amir to run later. If any child plan still says physical proof is required or preferred, this top-level rule supersedes that wording until Amir revokes it.

Second physical phone install readiness as of 2026-05-28: current build installed and launched on `Amir's iPhone` / `iPhone 17 Pro` / `CB9FFF0E-89AD-57B5-9C00-6552D814875E` with `rtk make device-install DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E DEVELOPMENT_TEAM=R6B8KXF3QW`, then `rtk xcrun devicectl device process launch --device CB9FFF0E-89AD-57B5-9C00-6552D814875E --terminate-existing com.aelaguiz.CodexDockApp`; process readback showed `CodexDockApp` running as pid `21126`. This is install/launch readiness only; detailed physical behavior remains on the deferred manual QA list.

Non-negotiables: no phone-side OpenAI key, no phone-side raw app-server token, no phone-side relay bearer token, no direct iPhone connection to raw `:4500` in the normal path, no Tailscale dependency in app/relay architecture, no duplicate connectivity truth, no duplicate Dock filter/count predicates, no Dock row summary that only repeats the opening message when a later meaningful message exists, no hidden fallback from Realtime back to file upload, and no host-service setup that prints secrets.

# 0) Scope And Authority

This document is the top-level planning dock for these four child plans:

- `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md`
- `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`
- `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`
- `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`

The child plans remain authoritative for their internal design, call-site inventories, phase checklists, and verification gates. This top-level plan is authoritative for cross-plan order, shared security boundaries, shared ownership, and conflict resolution between plans.

The already-implemented iPhone local relay plan is treated as Phase 0 foundation, not as one of the four remaining implementation plans:

- `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`

That plan's stale filename still says `PAIRING_SECRET`, but its implemented content is the opposite of phone secret pairing: server-owned secrets, Bonjour discovery, optional bearer host config, and no physical-phone client auth.

# 1) Shared Current-State Baseline

Current code baseline on 2026-05-28:

- App bootstrap is `CodexDockBootstrapView` plus `RelayBootstrapStore`, not direct env-only startup.
- `RelayBootstrapStore` first accepts dev env config when present, otherwise starts Bonjour discovery, loads saved non-secret relay config, and builds a `HostRegistry` from `DockHostConfiguration(... bearerToken: nil)`.
- `DockHostConfiguration.bearerToken` is optional.
- `AppServerClient` omits the `Authorization` header when the host bearer token is nil.
- `scripts/dock-relay.mjs` defaults phone auth to `none` unless bearer mode is explicitly configured.
- `rtk make services` starts the relay with `--phone-auth none` and keeps the raw app-server history token Mac-side through `--history-auth-token-file`.
- The relay advertises `_codexdock._tcp` with non-secret TXT records.
- Original voice baseline was one-shot relay transcription through `RelayTranscriptionClient` and `audio/transcribe`. Current Realtime work wires the default voice path to `RelayRealtimeTranscriptionClient`, adds live PCM capture, store forwarding into `RealtimeTranscriptionSession.appendAudio(...)`, hold dictation, tap-to-start/tap-to-stop dictation controls, route/interruption cleanup, deletes direct Swift OpenAI/file-upload side doors, and rejects raw `audio/transcribe` at the relay. Physical iPhone 14 Realtime audio acceptance and the detailed manual closeout checklist now have user-confirmed success.
- `Makefile` still has Mac-only launchd service generation and hard-coded `192.168.50.117` defaults.
- The raw app-server still currently binds `ws://0.0.0.0:4500` in the Mac Makefile path; the target multi-host service contract should move raw app-server to loopback by default and keep the relay as the network boundary.
- Phase 1 now implements the Agents tab/count model. Connectivity Phases 1-5 now add public `AppServerClient.connectionStates`, reconnect policy, stale/reconnecting/rehydrate detail handling, `AppConnectivityStore`, root-mounted `GlobalConnectivityIndicatorView`, root-owned Dock refresh, Archive unavailable handling, app background/foreground lifecycle handling through `AppLifecycleCoordinator`, and relay recovery/fail-loud update delivery in the current working tree. Realtime Phase 1 adds the relay contract, Phase 2 adds the Swift store state machine, Phase 3 adds the typed Swift relay client, Phase 4 adds live capture/audio-forwarding plus accessible hold/tap composer controls, and Phase 5 deletes one-shot file-upload side doors. The real physical Realtime audio path and detailed manual checklist have now passed user manual iPhone 14 testing, and implementation audit/thermonuclear review passed after the structural cleanup.
- Dock row preview/title readability is now in shared scope before final acceptance: list rows must surface the latest meaningful thread message or preview when available, not only the original opening message. The original prompt may remain available in detail/history, but the Dock list must make the current state of each thread legible.

# 2) Dependency Graph

## 2.1 Hard Dependencies

1. No-phone-secret relay baseline -> every plan
   - All future app paths must use `DockHostConfiguration.bearerToken: String?`.
   - Physical iPhone proof must not require `SIMCTL_CHILD_*`, `OPENAI_API_KEY`, raw app-server bearer, or relay bearer on the phone.
   - Child plans must treat bearer auth as an explicit dev/hardening profile only.

2. Agents model/query foundation -> connectivity and multi-host app behavior
   - `DockSessionQuery(archived:sourceKinds:)`, typed origin, scoped load outcomes, and counted tabs change the shape of Dock loading.
   - Connectivity and multi-host status should consume that final loader/query shape rather than build status around the old `loadSessions(for:archived:)` API.

3. Connectivity lifecycle/status -> Realtime and multi-host app UX
   - `AppServerClient` state, `ThreadDetailStore` rehydrate, `AppConnectivityStore`, root-owned refresh/checking, and app background/resume are the canonical recovery path.
   - Realtime voice background/cancel behavior must hook into this lifecycle instead of inventing parallel scene-phase handling.
   - Multi-host setup needs one app-wide status owner before adding more hosts and failure modes.

4. Realtime transcription contract -> final host-service bundle
   - The service bundle should not fossilize one-shot `audio/transcribe` model/env names if Realtime streaming is the intended production voice path.
   - Host-service status and logs should expose the final relay-owned transcription state: Realtime session config, model, key-present boolean, bounds, and sanitized last error.

5. Multi-host service setup -> final two-host acceptance
   - Real `home` acceptance requires Linux systemd user services, generated app config, service status/log helpers, and a reachable relay endpoint.
   - Final proof should run against `Amir-M5` and `home`, with one non-Tailscale route where available and Tailscale only as an optional address/profile.

## 2.2 Soft Dependencies And Conflict Avoidance

- Relay source filtering belongs to the Agents plan. Connectivity and multi-host plans may depend on it, but they should not add a second source-kind matcher.
- Relay upstream fail-loud/reconnect behavior belongs to the Connectivity plan. Multi-host status may expose it, but it should not define a competing upstream policy.
- Relay transcription streaming belongs to the Realtime plan. Multi-host setup may configure and report it, but it should not preserve old file-upload transcription as a production fallback.
- Root app lifecycle belongs to the Connectivity plan. Realtime and multi-host plans may add lifecycle participants, but no tab/detail/local view should create a second scene-phase authority.
- Cross-platform service rendering belongs to the Multi-host plan. Connectivity and Realtime plans should not grow service-manager abstractions.

# 3) Implementation Order

## Phase 0 - No-Phone-Secret Relay Baseline

Status: implemented before this top-level plan.

Source plan:

- `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`

Current proof recorded in:

- `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28_WORKLOG.md`

Contract carried forward:

- Physical iPhone connects to discovered relay with no client bearer token.
- Raw app-server bearer token remains Mac/host-side.
- `OPENAI_API_KEY` remains Mac/host-side.
- Bonjour TXT records stay non-secret.
- Manual relay fallback stores URL/display data only.
- Simulator env launch remains dev-only and cannot be physical acceptance evidence.

## Phase 1 - Agents Tab And Live Counts

Primary plan:

- `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md`

Status:

- Implemented and audited on 2026-05-28. Proof used the physical `iPhone 14` target `00008110-000E04940240A01E`.
- Verification recorded in `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28_IMPLEMENTATION_LOG.md`: `rtk swift test` passed 100 tests with 5 skipped, `rtk npm run test:relay` passed 21 tests, `rtk git diff --check` passed, and physical iPhone build/install/launch passed.

Why first:

- It stabilizes the Dock row model, source query model, scoped failure model, tab-count model, and relay live-row source filtering before later plans use Dock rows as connectivity/status evidence.
- It is mostly independent of service lifecycle and Realtime voice work.

Must preserve from Phase 0:

- Loader/client code must pass optional `host.bearerToken` through unchanged.
- No Agents query or relay source filter may require a phone bearer token.
- Unknown-origin rows should stay visible in Agents; they are not an auth failure and not a hidden fallback.

Exit before Phase 2:

- `SessionSummary` carries typed origin.
- `DockSessionQuery` is the internal loader contract.
- `DockSnapshot` owns counted tab models and scoped failures.
- `DockView` no longer owns business predicates.
- Relay live rows honor `sourceKinds` so default human requests cannot be polluted by live sub-agent or `exec` rows.
- Focused Swift and relay tests pass for this plan.

## Phase 2 - Connectivity Resilience

Primary plan:

- `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`

Status:

- Implemented and accepted for the current agent-side scope as of 2026-05-28. Connectivity Phases 1-6 below are complete; physical visual/navigation checks remain Amir-owned deferred manual QA under Section 5.1.
- Phase 1, Observable Connection Failure Path, is implemented in the current working tree and recorded in `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_IMPLEMENTATION_LOG.md`.
- Focused proof passed on 2026-05-28: `rtk swift test --filter AppServerClientTests` executed 34 tests with 5 skipped and 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 21 tests with 0 failures.
- Phase 2, Reconnect And Thread Rehydrate, is implemented in the current working tree and recorded in `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_IMPLEMENTATION_LOG.md`.
- Focused proof passed on 2026-05-28: `rtk swift test --filter AppServerClientTests` executed 38 tests with 5 skipped and 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 27 tests with 0 failures.
- Phase 3, App-Wide Connectivity Store And Indicator, is implemented in the current working tree and recorded in `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_IMPLEMENTATION_LOG.md`.
- Proof passed on 2026-05-28: `rtk swift test --filter AppConnectivityStoreTests` executed 7 tests with 0 failures; `rtk swift test --filter DockStoreTests` executed 19 tests with 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 27 tests with 0 failures; `rtk swift test` executed 129 tests with 5 skipped and 0 failures.
- Phase 4, App Background And Foreground Resume Lifecycle, is implemented in the current working tree and recorded in `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_IMPLEMENTATION_LOG.md`.
- Proof passed on 2026-05-28: `rtk swift test --filter AppLifecycleCoordinatorTests` executed 3 tests with 0 failures; `rtk swift test --filter AppConnectivityStoreTests` executed 11 tests with 0 failures; `rtk swift test --filter DockConfigurationTests` executed 14 tests with 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 31 tests with 0 failures; `rtk swift test --filter AppServerClientTests` executed 40 tests with 5 skipped and 0 failures; `rtk swift test` executed 147 tests with 5 skipped and 0 failures; `rtk git diff --check` passed.
- Phase 5, Relay Recovery And Update Delivery Hardening, is implemented in the current working tree and recorded in `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_IMPLEMENTATION_LOG.md`.
- Proof passed on 2026-05-28: `rtk node --check scripts/dock-relay.mjs` passed; `rtk node --check scripts/dock-relay-json-rpc-client.mjs` passed; `rtk node --check scripts/dock-relay-test-helpers.mjs` passed; `rtk node --check scripts/dock-relay-phase5.test.mjs` passed; `rtk npm run test:relay` executed 33 tests with 0 failures; `rtk npm test` executed 33 tests with 0 failures; `rtk swift test --filter AppServerClientTests` executed 40 tests with 5 skipped and 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 31 tests with 0 failures; `rtk git diff --check` passed.
- Phase 6 automated/service, physical install/launch, and user-approved simulator visual proof are complete for the current Connectivity closeout and recorded in `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28_IMPLEMENTATION_LOG.md`.
- Proof passed on 2026-05-28: `rtk swift test` executed 147 tests with 5 skipped and 0 failures; `rtk node --check scripts/dock-relay.mjs` passed; `rtk node --check scripts/dock-relay-json-rpc-client.mjs` passed; `rtk node --check scripts/dock-relay-test-helpers.mjs` passed; `rtk node --check scripts/dock-relay-phase5.test.mjs` passed; `rtk npm test` executed 33 tests with 0 failures; `rtk make dock-relay`, `rtk make app-server-status`, and `rtk make dock-relay-status` returned healthy raw app-server and relay status; phone-reachable relay smoke passed handshake, `thread/list`, and `thread/read` plus `thread/resume` with no phone-side bearer env; `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed on physical `iPhone 14`; `xcrun devicectl ... process launch` launched the app and pid `4340` was running after a final non-secret relay-env physical launch.
- Physical UI automation follow-up: Mobile MCP screenshot and accessibility inspection on the real `iPhone 14` still fail because WebDriverAgent is not running on device `00008110-000E04940240A01E`.
- Current accepted visual proof: Mobile MCP on `feat_anim_1 - iPhone 17` simulator UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` captured Dock, Archive, Relay, and Session detail with the root online indicator against `ws://192.168.50.117:4510`; screenshots are under `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/`.
- Follow-up UI fix on 2026-05-28: the root `Online` indicator no longer floats over the Dock header plus button. `CodexDockRootView` passes the shared connectivity store into `DockView`, and `DockView` renders the indicator inline in the Dock header to the left of the plus button with no extra vertical strip; simulator screenshot `/tmp/codex-client/20260528T194350Z/dock-header-connectivity-inline.png` shows the accepted layout, focused `AppConnectivityStoreTests` passed, and the fixed build was installed/launched on physical `iPhone 14` `00008110-000E04940240A01E`.
- Full Connectivity movement to Realtime is no longer blocked by the physical WebDriverAgent issue. Physical `iPhone 14` screen/navigation proof remains deferred until WebDriverAgent is available.

Why second:

- It creates the shared lifecycle/status owner before Realtime voice and multi-host setup add more ways for the relay, raw app-server, discovery, or a host to fail.
- It replaces view-bound refresh and local status islands with root-owned connectivity truth.

Must preserve from Phase 0 and Phase 1:

- Optional/no bearer physical relay hosts are normal configured hosts.
- `auth failed` means a configured bearer/dev/hardened endpoint rejected credentials, not that the physical no-auth relay is missing a phone token.
- Root lifecycle must include `CodexDockBootstrapView`/`RelayBootstrapStore`, because discovery now exists before `CodexDockRootView`.
- Connectivity reporting must consume the final `DockSessionQuery`/`DockSnapshot` shape from Phase 1.

Exit before Phase 3:

- `AppServerClient` exposes observable connection state and handles retired late responses safely.
- `ThreadDetailStore` can move out of false-live state and rehydrate via compact read/turns/resume.
- `AppConnectivityStore` and root-mounted global indicator exist.
- Root owns refresh/check lifecycle; `DockView.runRefreshLoop()` is gone.
- App background/foreground resume is modeled as expected lifecycle.
- Relay upstream death is either recovered or fails loudly through downstream close.
- Focused Swift and relay tests pass for this plan.

## Phase 3 - Realtime Transcription Streaming

Primary plan:

- `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`

Status:

- Closeout accepted for the current installed build. Phase 0 prerequisite readback is complete: the current working tree has `AppConnectivityStore`, `AppLifecycleCoordinator`, root-owned Dock refresh, scene-phase forwarding, and `ThreadDetailStore` lifecycle input from the Connectivity slice.
- Phase 1, Relay Realtime Transcription Contract, is code-complete in the current working tree and recorded in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md`, but it is not accepted from mocks.
- Preflight proof passed on 2026-05-28: `node --check scripts/dock-relay-realtime-transcription.mjs`, `node --check scripts/dock-relay-realtime-transcription.test.mjs`, `node --check scripts/dock-relay.mjs`, `node --test scripts/dock-relay-realtime-transcription.test.mjs` executed 8 tests with 0 failures, `rtk npm run test:relay` executed 41 tests with 0 failures, and focused `rtk git diff --check` passed. These are fake-upstream/mock checks and do not count as acceptance proof.
- Phase 2, Store-Owned Streaming Draft Reconciliation, is code-complete in the current working tree and recorded in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md`, but it is not accepted from fake Swift streaming sessions.
- Phase 2 preflight proof passed on 2026-05-28: `rtk swift test --filter ThreadDetailStoreTests` executed 39 tests with 0 failures; `rtk swift test` executed 156 tests with 5 skipped and 0 failures; focused `rtk git diff --check` passed; Xcode simulator build passed on non-Pro simulator UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`; physical `iPhone 14` install/launch passed on device `00008110-000E04940240A01E` and process `4386` was running.
- Phase 3, Swift Relay Client Integration With Synthetic Audio, is code-complete in the current working tree and recorded in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md`, but it is not accepted from scripted relay notifications.
- Phase 3 preflight proof passed on 2026-05-28: `rtk swift test --filter AppServerClientTests` executed 44 tests with 5 skipped and 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 40 tests with 0 failures. These scripted/fake checks do not count as real voice acceptance.
- Phase 4, Live PCM Capture And Accessible Composer Interaction, is code-complete in the current working tree: the app has an `AVAudioEngine` live capture controller, `ThreadDetailStore` forwards capture chunks into `RealtimeTranscriptionSession.appendAudio(...)`, release stops capture before commit, hold dictation stays mode-scoped, tap-to-start/tap-to-stop dictation uses the same live relay-backed session path, and live capture observes route/interruption cleanup. Real relay/OpenAI proof passed, the physical iPhone 14 Realtime audio path has user-confirmed success, and the detailed manual checklist is marked passed by user manual check for the current installed build.
- Phase 4 preflight proof passed on 2026-05-28: `rtk swift test --filter ThreadDetailStoreTests` executed 42 matching tests with 0 failures; `rtk swift test --filter AppServerClientTests` executed 45 tests with 5 skipped and 0 failures; `rtk swift test` executed 164 tests with 5 skipped and 0 failures; `rtk npm test` executed 42 tests with 0 failures; focused `rtk git diff --check` passed; and the Xcode simulator build passed after regenerating `CodexDock.xcodeproj` from `project.yml`. These fake/scripted checks do not count as real voice acceptance.
- Phase 4 tap-control preflight proof passed on 2026-05-28: `rtk swift test --filter ComposerVoiceControlsPresentationTests` executed 4 tests with 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 49 tests with 0 failures; `rtk swift test` executed 175 tests with 5 skipped and 0 failures; `rtk npm test` executed 42 tests with 0 failures; `rtk xcodegen generate --spec project.yml` passed; `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` passed; `rtk git diff --check` passed. These fake/scripted checks and builds still do not count as successful Realtime voice acceptance.
- Phase 4 physical install/launch proof passed on 2026-05-28: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed the live-capture/tap-control build on physical `iPhone 14`; `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` launched it; process listing showed pid `4434`.
- Physical UI readback remains blocked: Mobile MCP sees the physical `iPhone 14` online, but screenshot and element listing both return `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`. The user-approved non-Pro simulator fallback on `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` launched pid `49381` after the tap-control build and showed the real Dock app connected to `ws://192.168.50.117:4510 · 206 sessions`, with real thread detail controls `Hold to dictate` and `Start dictation`.
- Earlier negative relay-path proof: tapping `Start dictation` in the installed simulator fallback went through the real relay and surfaced `App-server rejected request: OpenAI Realtime transcription key is not configured on the relay`. This proved the app was not using a local fake path, but it was not successful Realtime transcription acceptance.
- Current fallback screenshots: `/tmp/codex-client/20260528T161315Z/realtime-phase4-smoke/001_dock_connected_fallback.png`, `/tmp/codex-client/20260528T163230Z/realtime-phase4-tap-controls-fallback.png`, and `/tmp/codex-client/20260528T163230Z/realtime-phase4-missing-key-fallback.png`.
- Standalone real relay-to-OpenAI proof passed after `.env` was restored and service env generation was changed to preserve `.env`: local JSON-RPC client -> `ws://192.168.50.117:4510` relay -> OpenAI Realtime transcription. Redacted evidence: `PCM_BYTES=123920`, `MODEL=gpt-realtime-whisper`, `CHUNKS=3`, `DELTA_COUNT=9`, `TERMINAL_METHOD=audio/transcription/completed`, `COMPLETED_TEXT_BYTES=47`, `COMPLETED_TEXT_SHA256=a49fef874c839fee25b98c117f0f266d2ae983fdcf0de808e974564019d655ee`, and `CLOSED_SEEN=1`.
- User-approved non-Pro simulator fallback after Realtime crash fix: `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` launched pid `37271`; Mobile MCP tapped `Start dictation` in a real relay-backed thread detail view and the app stayed open with visible error `Voice recording could not start.` Screenshot: `/tmp/codex-client/20260528T164200Z/realtime-real-openai/004_app_simulator_voice_recording_unavailable_no_crash.png`. This is fail-visible simulator proof, not successful voice acceptance.
- Physical iPhone 14 install/launch after the Realtime crash fix passed on 2026-05-28: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed the app, `devicectl ... process launch` launched it, process listing showed pid `4473`, and `.env` mtime stayed unchanged. Physical UI readback still fails because WebDriverAgent is not running.
- Realtime Phase 5 cutover verification passed on 2026-05-28: old one-shot Swift/relay/file-upload side doors were removed or rejected, generated service env is Realtime-only, full Swift and relay tests passed, Xcode build passed by simulator UDID, real relay-to-OpenAI proof passed with legacy `audio/transcribe` rejected, simulator install/launch passed, and the current app build is installed on the physical iPhone 14 target `00008110-000E04940240A01E`.
- Realtime code-shape audit and thermonuclear review passed on 2026-05-28 after the physical audio pass and blue listening UI change: `ThreadDetailStore.swift` was split into a `ThreadDetailStore+Voice.swift` extension (`890`/`556` lines), relay thread-data aggregation moved to `scripts/dock-relay-thread-data.mjs` (`649`/`657` lines), `rtk swift test` passed 183 tests with 5 skipped and 0 failures, `rtk npm test` passed 41 tests with 0 failures, `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` passed, `rtk git diff --check` passed, the updated build installed/launched on physical iPhone 14 `00008110-000E04940240A01E`, relay status was healthy at `ws://192.168.50.117:4510`, and `.env` mtime remained `1779986258`.
- Latest manual-checklist readiness pass on 2026-05-28: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed `com.aelaguiz.CodexDockApp`, `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` launched it, process listing showed pid `4619`, app-server and relay status were healthy, relay stayed at `ws://192.168.50.117:4510` with `phone auth: none`, and `.env` mtime remained `1779986258`. This is readiness only, not manual checklist acceptance.
- Realtime manual physical iPhone 14 closeout is now marked passed by user manual check on 2026-05-28. The source checklist lives in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` under Phase 5 "Verification (required proof)", with the evidence ledger in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md` under "Manual Physical iPhone 14 Closeout Checklist".

Why third:

- It depends on the no-phone-secret relay boundary and benefits from the new root lifecycle/status owner.
- It changes both `ThreadDetailStore` voice state and relay transcription behavior, so it should run after connectivity settles those ownership boundaries.
- It should land before finalizing portable host-service setup so host services encode the final transcription contract instead of the interim one-shot file-upload contract.

Must preserve from earlier phases:

- The phone never receives OpenAI keys, Realtime client secrets, provider bearers, relay bearers, or raw app-server tokens.
- The relay transcription API must use the selected host relay and optional `host.bearerToken`; nil is valid for the physical path.
- Voice background/interruption behavior must report into or use the lifecycle path from Phase 2.
- Realtime streaming supersedes current one-shot `audio/transcribe`; the old one-shot path must not survive as a hidden production fallback.

Exit before Phase 4:

- Relay-owned Realtime transcription methods/events are tested with fake upstream.
- `ThreadDetailStore` owns streaming draft reconciliation and edit locking.
- `RelayRealtimeTranscriptionClient` uses a separate app-to-relay voice WebSocket and typed methods.
- Live PCM capture replaces m4a upload for production dictation.
- Hold and tap dictation modes work in the existing composer.
- Old one-shot app/relay production voice surfaces are deleted or rejected.
- Full Swift and relay tests pass, plus manual device/simulator voice proof where required.

## Phase 4 - Multi-Host Service Setup And Robustness

Primary plan:

- `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`

Status:

- Phase 1A preparatory dry-run renderer is implemented. Realtime code/audit/review gates are clean, and Realtime manual physical iPhone 14 closeout is marked passed by user manual check on 2026-05-28. The Realtime plan owns the source checklist in Phase 5, and the evidence ledger is `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md` under "Manual Physical iPhone 14 Closeout Checklist".
- Multi-host Phase 0 prerequisite readback was recorded on 2026-05-28 in `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28_IMPLEMENTATION_LOG.md`: Agents, Connectivity, and Realtime code contracts exist in the current working tree, including `DockSessionQuery`, `AppConnectivityStore`, `AppServerClient.connectionStates`, compact detail rehydrate, relay `sourceKinds`, Realtime `audio/transcription/*`, `RelayRealtimeTranscriptionClient`, live capture, and raw `audio/transcribe` rejection.
- Gate state: code prerequisites are present and the Realtime detailed manual physical `iPhone 14` checklist is marked passed by user manual check. This clears the Realtime evidence gate for starting Multi-host Phase 1B/Phase 2, but does not claim Multi-host readiness.
- Phase 1A proof passed on 2026-05-28: `scripts/codex-dock-host-service.mjs` dry-renders launchd/systemd service files, emits non-secret app config, defaults raw app-server render to loopback `ws://127.0.0.1:4500`, supports LAN/Tailscale/simulator profile URL generation, reports dry-run status as `not-installed`, and has focused host-service tests wired through `npm run test:host-service` and aggregate `npm test`.
- Phase 2 relay status/error slice passed on 2026-05-28: relay `/statusz` is implemented and redacted; `/readyz` and `/healthz` are split; `rtk make dock-relay-status` prints `/statusz`; relay live `thread/resume` enforces `excludeTurns: true`; upstream overload `-32001` stays visible and retryable; malformed downstream parse errors and pending upstream close are tested; focused relay tests passed 47 tests with 0 failures; focused host-service tests passed 9 tests with 0 failures; `.env` mtime remained `1779986258`.
- Phase 1B/Phase 3A host-service lifecycle core is implemented behind fake-runner proof on 2026-05-28: launchd/systemd `install/start/stop/restart/status/logs/doctor` command paths exist, install creates/reuses the raw app-server token at mode `0600`, systemd install does not start services, start/stop dependency order is tested, status/log/doctor output redacts secrets plus JSON-RPC payloads/cookies/headers, service-manager failures are redacted, child-process env is scrubbed, and the script uses `--service-env-file` to avoid Node 25 `--env-file` interception. Focused host-service tests pass 17 tests with 0 failures; aggregate `rtk npm test` passes 47 relay tests and 17 host-service tests with 0 failures; `rtk git diff --check` passes; `.env` mtime remained `1779986258`.
- Phase 3B Makefile wrapper/live Mac launchd proof passed on 2026-05-28: `rtk make services` now uses the host-service wrapper, `.codex-dock/service.env` and `.codex-dock/host.env` are generated without touching `.env`, live Mac launchd jobs load from `.codex-dock/services/`, raw app-server binds loopback, the relay remains the app-facing endpoint at `ws://192.168.50.117:4510/`, status/doctor fail nonready states, relay `/statusz` requires raw-history health, and non-simulator profiles check app-facing relay `/readyz`. Proof passed for `rtk make services`, `rtk make app-server-status`, `rtk make dock-relay-status`, `rtk make host-service-doctor`, `rtk npm test` with 47 relay tests and 20 host-service tests, `rtk git diff --check`, and simulator launch on `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`; `.env` mtime remained `1779986258`.
- Phase 4A generated two-host env/app-consumption proof passed on 2026-05-28: `.codex-dock/host.env` is the non-secret generated app config for env-first launch, `rtk make app` reads only that host env file for simulator `SIMCTL_CHILD_CODEX_DOCK_*` values, `HostRegistry` validates duplicate hosts and `AUTH_MODE=none|bearer`, and simulator logs on `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` showed `host registry loaded from environment hosts=2` for `Amir-M5` and `home` with `bearer_configured=false`. Proof passed for focused host-service and Dock config tests, `DockStoreTests`, aggregate `rtk npm test`, full `rtk swift test`, service status, simulator launch, and `.env` mtime remained `1779986258`.
- Phase 3C live Linux systemd user proof on `home` passed on 2026-05-28: the current non-secret working tree was deployed to `/home/aelaguiz/workspace/codex-client` without `.env`, `env.bak`, `.codex-dock/`, build outputs, `node_modules/`, or git metadata; `rtk make services HOST_SERVICE_PLATFORM=linux ... CODEX_DOCK_REAL_HOST_ID=home ... CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510 ...` installed and started the `systemd-user` bundle; `host-service-status` reported `status: ready`; `host-service-doctor` reported `status: passed` with `problems: []`; local Mac `curl` proof reached `http://100.66.11.7:4510/readyz` and `/statusz`; and `home` generated `.codex-dock/host.env` contained only non-secret `home` app config. This does not claim Realtime transcription on `home`, because no `OPENAI_API_KEY` was copied there and the relay correctly reports transcription `enabled: false` / `keyPresent: false`.
- Phase 6 README runbook and final simulator multi-host smoke passed on 2026-05-28: `README.md` now describes the cross-platform host-service wrapper, loopback raw app-server, app-facing relay, `.codex-dock/service.env` versus `.codex-dock/host.env`, exact Mac and `home` commands, physical-device deferral, and the generated two-host app config. Simulator proof on `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` launched with `Amir-M5,home`, loaded both hosts from generated env with `bearer_configured=false`, showed both host cards, kept `Amir-M5` rows visible, and showed clear `Home` partial/offline errors. The deliberate one-host failure run used `CODEX_DOCK_HOST_HOME_WS=ws://127.0.0.1:9`, and the final run restored `home` to `ws://100.66.11.7:4510`. Screenshots are under `/tmp/codex-client/20260528T213700Z/`.
- Non-physical Multi-host closeout is accepted. Remaining work outside agent-side closeout: Amir-owned physical manual QA, and Realtime transcription on `home` only if an OpenAI key is intentionally configured there later.
- Do not treat simulator proof, fake relay tests, or physical install/launch alone as permission to claim final Multi-host readiness. Realtime acceptance for the current installed build rests on the real relay/OpenAI proof plus user manual physical iPhone 14 proof recorded in the Realtime evidence ledger.

Why fourth:

- It is the broadest infrastructure plan and should encode the final app, relay, status, and transcription contracts from earlier phases.
- It turns the now-stable relay/client model into repeatable host services on macOS and Linux.

Must preserve from earlier phases:

- The app-facing endpoint remains the relay, not raw `:4500`.
- Physical/default host config is non-secret URL/display/auth-mode data.
- Raw app-server tokens remain host-side only and should be file-path/config inputs for the relay.
- Raw app-server should bind loopback by default in the new portable service contract.
- Tailscale is only an endpoint/profile helper, not a Swift/Node/service-manager dependency.
- Generated app config must not export `OPENAI_API_KEY` or raw app-server tokens to the app.
- Service `/statusz` and logs must reflect final Realtime transcription status without audio/transcript/key leakage.

Exit before final closeout:

- Cross-platform host-service script renders and manages macOS launchd and Linux systemd user service files.
- `Amir-M5` and `home` both expose working relay endpoints.
- Generated app config can include both hosts without phone secrets.
- Relay/raw health/status/log helpers are redacted and actionable.
- The app preserves healthy host rows when another host is down.
- Focused Swift, Node, setup-render, and real host smoke tests pass or environment blockers are recorded exactly.

## Cross-Cutting Final Acceptance - Dock Row Latest-Message Preview

Owner: top-level final acceptance unless a later child plan explicitly absorbs it. This requirement is not considered satisfied by the completed Agents tab/live-counts phase.

Required behavior:

- Dock list rows must surface the latest meaningful thread message or preview when available.
- A row may still retain the original opening prompt in detail/history, but the first-screen row summary/title path must not only repeat the opening prompt after later meaningful messages exist.
- This applies to real relay-backed `SessionSummary` rows, not fixture or SwiftUI preview rows.

Required proof before final closeout:

- Focused Swift tests or mapper/projector tests prove a thread with a later meaningful message displays that later preview in the Dock row.
- Physical `iPhone 14` row-legibility confirmation is deferred manual QA under the temporary physical-device operating rule; do not block implementation on missing physical UI readback while simulator/local/real-relay proof passes.
- `README.md` uses "fixture or SwiftUI preview rows" when warning about fake production evidence, so that wording is not confused with the latest-message row preview requirement.

Current implementation status:

- Implemented on 2026-05-28 in `scripts/dock-relay.mjs` and `CodexDock/Models/SessionSummaryMapper.swift`.
- The relay enriches returned `thread/list` rows from bounded `thread/turns/list` probes and only uses stored `userMessage` / `agentMessage` text for row previews. It does not use reasoning, plan, command, tool, transcript, or output items as Dock row summaries.
- The Swift mapper also uses `ThreadDTO.turns` when turns are present, while keeping the stable `name`-based row title.
- Preflight checks passed on 2026-05-28: `node --check scripts/dock-relay.mjs`, `node --check scripts/dock-relay-phase5.test.mjs`, `rtk swift test --filter ThreadListMappingTests` executed 12 tests with 0 failures, and `rtk npm run test:relay` executed 42 tests with 0 failures. These fake/focused checks are supporting evidence only, not acceptance by themselves.
- Real relay-backed proof passed on 2026-05-28 against `ws://127.0.0.1:4510`: `thread/list` returned a real row whose preview exactly matched the latest real `userMessage`/`agentMessage` text from `thread/turns/list` for thread `019e6f2a-1af2-7c40-9ede-0a3a0a9cded4`.
- Physical `iPhone 14` install/launch proof on 2026-05-28: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` rebuilt and installed the app; `xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing --environment-variables ... com.aelaguiz.CodexDockApp` launched pid `4355` against `ws://192.168.50.117:4510`; the relaunched relay was pid `71847`. Physical visual readback is deferred because Mobile MCP returns `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)` for both element listing and screenshots.

Current supporting evidence:

- Earlier Mobile MCP readback on the accepted Connectivity simulator proof showed real Dock row labels containing later/current preview text, including `Right now it's so spammy because I'm seeing by de...`; this remains supporting evidence only. The focused latest-message implementation proof is the real relay-backed proof recorded above.

## Phase 5 - Integrated Proof And Docs

Goal: prove the whole program, not only each child plan in isolation.

Current status:

- Completed for the current agent-side scope on 2026-05-28. Agents, Connectivity, Realtime, latest-message row previews, and Multi-host are implemented and accepted under the current physical-device deferral rule.
- Parent-side closeout proof includes `rtk npm test`, `rtk swift test --filter DockConfigurationTests`, `rtk git diff --check`, service status checks, real `home` relay `/readyz` and `/statusz` checks, and simulator multi-host smoke on `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Fresh Composer 2.5 consult on 2026-05-28 independently reported `VERDICT: pass-with-notes`, `BLOCKING: none`, and treated the remaining reopen candidates as doc/status drift only. That consult recorded fresh `rtk swift test` and `rtk npm test` passes in `/tmp/fresh-consult/cross-plan-composer-20260528T214554Z/`.
- Remaining physical-device behavior checks are tracked in Section 5.1 as Amir-owned deferred manual QA, not as agent-side blockers.

Required proof:

- `rtk swift test`
- `rtk npm run test:relay`
- `rtk node --check scripts/dock-relay.mjs`
- `rtk node --check scripts/codex-dock-host-service.mjs` if that script name is used.
- `rtk xcodegen generate --spec project.yml` if `project.yml` changed.
- Relevant generated Xcode build/test when app target or metadata changed.
- `rtk make services`
- `rtk make app-server-status`
- `rtk make dock-relay-status`
- Simulator app launch on the accepted non-Pro simulator when installed-app behavior changed.
- Physical iPhone proof is deferred manual QA for Amir for now. Do not run, require, retry, wait on, or ask for physical device install/launch, physical UI automation, physical screenshots, physical accessibility checks, or physical audio checks as an agent gate unless Amir explicitly asks in that turn. If physical validation would normally be needed, run the best simulator/local/real-relay proof available, assume the physical path works for planning purposes, and update the deferred physical checklist instead.
- `Amir-M5` and `home` real-host smoke for multi-host completion.

Docs that must be current before closeout:

- `README.md`
- `Makefile` command behavior
- the four child plans
- any stale iPhone UX/voice docs touched by Realtime
- this top-level plan and its audit log

## 5.1 Deferred Physical Device Manual QA Checklist

Operating rule as of 2026-05-28: these checks are Amir-owned manual QA for later. They do not block current implementation while simulator/local/real-relay proof is available and passing. Agents must not run, require, retry, wait on, or ask for physical iPhone install/launch, Mobile MCP, screenshots, accessibility, audio, or other physical-only proof unless Amir explicitly asks in that turn. If a change creates a physical-only risk, add or update a row here, keep moving with simulator/local/real-relay/service-status proof, and assume the physical path works for planning purposes.

| Area | Deferred physical check | Trigger |
| --- | --- | --- |
| Current build smoke | On physical `iPhone 14` `00008110-000E04940240A01E`, open the installed Codex Dock app, confirm it discovers the relay-backed host path at `ws://192.168.50.117:4510`, loads real Dock rows, opens one Session detail, and returns to Dock without crashing. | Any current build that is marked ready by simulator/local/real-relay proof while physical testing is deferred. |
| Realtime voice | Re-run hold dictation, tap dictation, typed-prefix preservation, editable final draft, explicit Send/no auto-submit, cancel/interruption recovery, VoiceOver labels/hints, hit targets, and large Dynamic Type. | Any future change under `CodexDock/Voice/**`, `ThreadDetailStore+Voice.swift`, `ComposerView.swift`, relay Realtime transcription, or voice logging. |
| Connectivity UI | Open Dock, Archive, Relay, and Session detail; confirm the root indicator is readable, does not overlap the Dock `+` button, and background/resume is visibly recoverable. | Any future connectivity, lifecycle, root navigation, or header/layout change. |
| Dock latest-message rows | Confirm real Dock rows show the latest useful message/preview rather than only the original opening prompt. | Any future relay `thread/list`, `SessionSummaryMapper`, `SessionRowProjector`, Dock row, or list sorting change. |
| Multi-host app behavior | With `Amir-M5` and `home` configured, confirm both hosts appear, healthy rows remain visible when one host is down, host errors are clear, and the app-facing endpoint is the relay, not raw `:4500`. | Multi-host Phase 1B/Phase 2 and later app config/status work. |
| Multi-host service setup | On the real target machines, confirm launchd/systemd install/start/status/log commands work, service logs are redacted, raw app-server binds loopback by default, and relay status/logs expose Realtime health without secrets. | Multi-host service install/status/log implementation. |
| Other plugged-in iPhone | On `Amir's iPhone` `iPhone 17 Pro` `CB9FFF0E-89AD-57B5-9C00-6552D814875E`, confirm the already-installed app opens, discovers the relay, loads real rows, and can perform a basic voice smoke when convenient. Install/launch readiness already passed on 2026-05-28 with process pid `21126`. | When Amir has the second physical phone available for manual behavior checks. |

# 4) Ownership Matrix

| Contract | Owner plan | Canonical files |
| --- | --- | --- |
| Physical no-phone-secret relay security | iPhone local relay baseline | `RelayBootstrapStore`, `RelayDiscovery`, `DockHostConfiguration`, `scripts/dock-relay.mjs`, `Makefile`, `README.md` |
| Session origin and Agents routing | Agents tab/live counts | `SessionSummary`, `SessionSummaryMapper`, `DockSessionQuery`, `SessionRowProjector`, `DockSnapshot`, `DockView`, `scripts/dock-relay.mjs` source-kind helpers |
| App-wide connectivity and lifecycle | Connectivity resilience | `AppServerClient`, `ThreadDetailStore`, `AppConnectivityStore`, `AppLifecycleCoordinator`, `CodexDockRootView`, `RelayBootstrapStore`, `scripts/dock-relay.mjs` upstream lifecycle |
| Realtime voice dictation | Realtime transcription streaming | `CodexDock/Voice/*`, `ThreadDetailStore`, `ComposerView`, typed audio transcription DTOs/methods, `scripts/dock-relay.mjs` Realtime session manager |
| Cross-platform host services | Multi-host service setup | host-service setup script, `Makefile`, launchd/systemd templates, relay `/statusz`, README service runbook |

Rules:

- If two plans name the same owner, the earlier top-level phase owns the base contract and the later phase extends it without forking it.
- `scripts/dock-relay.mjs` is a shared owner. Each child plan may own a distinct relay concern, but there must be one relay process and one JSON-RPC method allowlist.
- `ThreadDetailStore` is a shared owner. Connectivity owns live session recovery. Realtime owns voice/composer dictation state. The two must share lifecycle inputs instead of creating separate background handlers.
- `DockStore` is a shared owner. Agents owns tab/source projection. Connectivity owns reporting load outcomes into global status. Multi-host owns consuming generated host config and preserving partial-host data.

# 5) Cross-Plan Security Rules

- Physical iPhone app config must never contain `OPENAI_API_KEY`, raw Codex app-server token, relay bearer token, OpenAI Realtime client secret, provider bearer, or future provider OAuth token.
- Simulator env may pass non-secret host IDs, names, and WebSocket URLs. It must not pass OpenAI keys or raw app-server bearer tokens into the app.
- Bearer tokens remain allowed for raw app-server history and explicit dev/hardening relay profiles, but they stay on the host side unless a future hardening plan explicitly changes that boundary.
- Bonjour TXT records must remain non-secret. Allowed examples: version, auth mode, scheme, display name. Disallowed examples: tokens, paths with secrets, prompts, transcripts, audio, thread contents.
- Tailscale is an address/profile helper only. Removing Tailscale may change the configured URL, but it must not change app, relay, status, reconnect, or service-manager architecture.
- Relay status/log output may say whether an OpenAI key or raw token is present, but must not print values.
- The normal app path talks to the Dock relay on `:4510`. Direct raw `:4500` access is a local dev/smoke path only, not physical completion evidence.

# 6) Cross-Plan Drift Checks

Before implementation starts on any child plan:

- Read this top-level plan plus the target child plan.
- Confirm the child plan still names the no-phone-secret baseline correctly.
- Confirm the target owner path has not already moved in an earlier phase.
- Confirm the verification commands still match `Makefile`, `Package.swift`, `package.json`, and `project.yml`.

Before marking a child plan complete:

- Check whether it changed a shared contract used by a later child plan.
- Update later child plans when the shared contract changes.
- Do not leave stale references to phone-side OpenAI keys, phone relay bearer tokens, one-shot file upload, Mac-only launchd services, old Dock filters, or view-local connectivity truth.

Before marking the whole program complete:

- Run `plan-audit` on this top-level plan and the four child plans.
- The audit must explicitly inspect cross-plan dependency order, security baseline, shared owners, side doors, and proof gates.
- Any unresolved blocking finding in any child plan keeps the top-level program not ready.

# 7) Decision Log

## 2026-05-28 - Adopt implemented no-phone-secret relay as Phase 0

Decision: All four child plans now build on the implemented iPhone local relay baseline: discovered no-client-auth relay for physical phone, host-side raw app-server/OpenAI secrets, optional bearer for dev/hardening only.

Consequence: Any plan text that implies a physical phone bearer token, phone OpenAI key, or normal direct raw app-server access is stale and must be repaired.

## 2026-05-28 - Implement Agents before Connectivity

Decision: Build typed origin, `DockSessionQuery`, scoped failures, counted tabs, and relay source filtering first.

Consequence: Connectivity and multi-host work consume the final Dock loading/projection shape instead of adapting to old filters and then refactoring again.

## 2026-05-28 - Dock rows must show the latest meaningful message

Problem: Dock row summaries currently show the original message for each thread, so the list does not explain what the user is looking at after the thread has moved on.

Decision: Add Dock row latest-message preview/readability to the dock program scope. Before final acceptance, the row summary/title path must use the latest meaningful thread message or preview when available, while preserving access to the original opening prompt in detail/history.

Consequence: The implementation should land in the child plan that owns row mapping/list readability, or in this parent epic if it crosses plans. Acceptance proof must show thread rows are legible from the latest useful message, not just the first message.

## 2026-05-28 - Implement Connectivity before Realtime

Decision: Build observable connection state, reconnect/rehydrate, root connectivity, and app lifecycle before Realtime voice.

Consequence: Realtime voice can use one lifecycle/status path for interruption/background/recovery instead of inventing separate store/view scene handling.

## 2026-05-28 - Implement Realtime before final Multi-host service setup

Decision: Finish the relay-owned Realtime transcription contract before locking down portable host-service setup and status docs.

Consequence: The cross-platform service bundle reports and configures the final production transcription path, not the temporary one-shot relay upload path.

## 2026-05-28 - Multi-host remains the final infrastructure expansion

Decision: Cross-platform service setup and the `home` host proof come after shared app/relay contracts are stable.

Consequence: The broadest operational work gets the least churn and can focus on actual macOS/Linux service lifecycle, generated app config, status/logs, and real two-host proof.
