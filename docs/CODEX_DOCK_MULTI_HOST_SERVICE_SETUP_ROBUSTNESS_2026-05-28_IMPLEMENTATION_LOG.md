# Codex Dock Multi-Host Service Setup And Robustness - Implementation Log

Date: 2026-05-28
Status: active
Parent: `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`

## Resume Snapshot

- Current slice: Phase 1A preparatory dry-run renderer is complete; Phase 1B/Phase 2 are now the next implementation frontier.
- Result: the required Agents, Connectivity, and Realtime code contracts exist in the current working tree, and Phase 1A now adds a dry-run host-service renderer plus tests. The parent dock now records the Realtime acceptance proof gate as cleared by user manual physical `iPhone 14` check on 2026-05-28. The source checklist lives in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` under Phase 5 "Verification (required proof)", and evidence is recorded in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md`.
- Boundary: do not claim Multi-host readiness, `Amir-M5`/`home` service proof, or real service installation from this preflight slice.
- Next implementation slice: Phase 1B/Phase 2 service hardening around real install/status and relay `/statusz`.

## Parallel Read-Only Frontier Mapping

Used three read-only subagents to accelerate mapping. They did not edit files, touch `.env`, run destructive git commands, or use physical Mobile MCP.

- Multi-host frontier agent:
  - Earliest Multi-host item is Phase 0 prerequisite readback.
  - Smallest useful implementation slice is Phase 1A dry-run renderer only: config model, launchd/systemd render, redaction, profile URL generation, and tests.
  - Do not install/start services, claim physical proof, change Swift UX, or rely on simulator proof for Multi-host acceptance in that slice.
- Latest-message preview agent:
  - Cross-cutting latest-message preview can stay marked implemented.
  - Relay enrichment, Swift mapping, projector/display path, focused tests, and real relay-backed proof are enough for implementation status.
  - Parent should keep the physical visual-readback blocker explicit as deferred manual QA, not an implementation stop condition: `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
- Structural review agent:
  - The clean setup owner should be `scripts/codex-dock-host-service.mjs`.
  - `Makefile` should become wrappers after the script lands.
  - Avoid duplicate service truth, hard-coded IP drift, app-facing secret leakage, Tailscale-only proof, a second status rollup, and line-count sprawl.

## Phase 0 - Top-Level Prerequisite Readback

Status: code-symbol readback complete; final Realtime acceptance evidence is marked passed by user manual physical iPhone 14 check.

Agents inputs found:

- `DockSessionQuery` exists in `CodexDock/State/DockStore.swift`.
- `ThreadSourceKind.dockAgentScopeKinds` and `sourceKinds` routing exist in Swift DTO/store code and relay source filtering.
- Counted tabs exist through `DockTabID`, `DockTabViewModel`, and `DockSnapshot` in `CodexDock/State/DockStore.swift`.
- Relay source filtering is covered by `scripts/dock-relay-source-filter.mjs` and relay tests around `sourceKinds`.

Connectivity inputs found:

- `AppConnectivityStore` exists at `CodexDock/State/AppConnectivityStore.swift`.
- `AppLifecycleCoordinator` exists at `CodexDock/State/AppLifecycleCoordinator.swift`.
- `AppServerClient.connectionStates` exists in `CodexDock/AppServer/AppServerClient.swift`.
- `ThreadDetailStore` uses compact read/turns plus `thread/resume excludeTurns:true` for rehydrate/resume behavior.
- Relay fail-loud update delivery and live resume compactness are covered in `scripts/dock-relay-phase5.test.mjs`.
- The root `GlobalConnectivityIndicatorView` remains root-owned. The 2026-05-28 header collision fix passes the shared connectivity store into `DockView` and renders the indicator inline in the Dock header, left of the plus button, so it no longer covers the button and does not add a vertical strip.

Realtime inputs found:

- Relay-owned Realtime methods exist: `audio/transcription/start`, `audio/transcription/append`, `audio/transcription/commit`, and `audio/transcription/cancel`.
- Swift Realtime client exists at `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`.
- Live capture exists at `CodexDock/Voice/VoiceCaptureController.swift`.
- Production raw `audio/transcribe` is rejected by relay test coverage after the Realtime cutover.
- Realtime implementation audit and thermonuclear review have no current code/design blocking findings.

Gate result:

- Code prerequisites are present.
- Full Realtime closeout is marked complete for the current installed build because the remaining manual physical `iPhone 14` checklist evidence passed by user manual check.
- Phase 1A dry-run renderer is now implemented as preparatory contract work only. It does not install/start services, configure `home`, prove a non-loopback endpoint, run app smoke tests, or claim Multi-host readiness.

## Proof Run During This Readback

- `rtk swift test --filter AppConnectivityStoreTests`
  - Result: passed.
  - Executed 11 tests, 0 failures.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Result: passed for the Dock header indicator collision fix.
  - Launched simulator app as pid `45016`.
- `xcrun simctl io BAD95C8E-3E57-4818-9B90-E4ED22593B4B screenshot /tmp/codex-client/20260528T194350Z/dock-header-connectivity-inline.png`
  - Result: passed.
  - Visual result: `Online` pill is inline in the Dock header, left of the plus button, with no extra vertical strip.
- `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`
  - Result: passed; installed the fixed build on the physical `iPhone 14`.
- `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`
  - Result: passed.
- `rtk git diff --check -- CodexDock/Features/Dock/DockView.swift`
  - Result: passed.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.

## Next Slice

Phase 1A is implemented:

- Added `scripts/codex-dock-host-service.mjs`.
- Added `scripts/codex-dock-host-service.test.mjs`.
- Added `npm run test:host-service` and made `npm test` run both relay and host-service Node tests.
- Kept the first slice dry-run/render only.
- Default raw app-server render is `ws://127.0.0.1:4500`.
- Generated app-facing config contains host ID, display name, public relay WebSocket URL, and auth mode only.
- App config does not emit `OPENAI_API_KEY`, raw app-server bearer token, relay bearer token, token file paths, audio, transcript text, or full payloads.
- `status` returns `not-installed` / `checked:false`, so dry-run output does not pretend services are ready.
- Token file creation/reuse remains deferred to the real install phase; Phase 1A service render may reference token file paths in service files, but no Phase 1A CLI command writes token files.

Phase 1A proof:

- `rtk node --check scripts/codex-dock-host-service.mjs`
  - Result: passed.
- `rtk npm run test:host-service`
  - Result: passed.
  - Executed 9 tests, 0 failures.
- `rtk npm run test:relay`
  - Result: passed.
  - Executed 41 tests, 0 failures.
- `rtk npm test`
  - Result: passed.
  - Executed 41 relay tests and 9 host-service tests, 0 failures.
- `rtk git diff --check`
  - Result: passed.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.
- Plan-backed implementation audit:
  - `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28_PLAN_AUDIT.md`
  - Result: approve for Phase 1A only.
- Thermonuclear review:
  - `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28_THERMONUCLEAR_REVIEW.md`
  - Result: approve for Phase 1A only after CLI boundary, redaction, dry-run mutation, and env app-config repairs.

Still not claimed:

- No launchd or systemd service was installed or started by this slice.
- No `Makefile` service target was replaced.
- No `home` host endpoint was configured or proven.
- No app smoke test was run for Multi-host.
- Multi-host Phase 1B+ is no longer gated by Realtime manual physical iPhone 14 evidence. Physical-device verification for future Multi-host behavior is now deferred to Amir; implementation should proceed with simulator/local proof and maintain a physical test list.

## 2026-05-28 - Physical Device Testing Deferral

- User instruction: no more physical-device blocking for now. If implementation needs physical-device testing, proceed with simulator/local/real-relay proof, assume the physical path works when those checks pass, and list physical checks for Amir to run later.
- Do not use missing physical UI automation or missing manual device evidence as a stop condition for Multi-host Phase 1B/Phase 2.
- Do not retry physical Mobile MCP unless Amir explicitly asks.
- Keep future physical test items in the parent dock deferred physical device test list.
- The current app build was installed and launched on the second plugged-in phone, `Amir's iPhone` / `iPhone 17 Pro` / `CB9FFF0E-89AD-57B5-9C00-6552D814875E`; process readback showed `CodexDockApp` running as pid `21126`. This is install/launch readiness only, not Multi-host behavior proof.

## 2026-05-28 - Phase 2 Relay Status/Error Slice

Scope implemented:

- Added the relay status helper module `scripts/dock-relay-status.mjs`.
- Added `/statusz` to `scripts/dock-relay.mjs` with redacted host metadata, listen config, history URL, auth mode, Realtime transcription config state, raw app-server health, live discovery status, active downstream/upstream counters, last upstream/client-facing/transcription errors, and reconnect state.
- Split `/readyz` and `/healthz`: `/readyz` is process-ready, while `/healthz` includes static config readability.
- Updated `rtk make dock-relay-status` to print `/readyz` and `/statusz`.
- Added relay host ID/name CLI wiring and host metadata propagation from `scripts/codex-dock-host-service.mjs`.
- Forced relay-owned live `thread/resume` calls to include `excludeTurns: true`; the phone/client no longer has to remember that compact live-subscription detail.
- Preserved upstream JSON-RPC error codes with `JsonRpcUpstreamError`, including app-server overload `-32001`, and added retryable overload error data.
- Changed upstream recovery delay to bounded exponential backoff with jitter.
- Recorded malformed downstream parse errors in relay status.
- Added direct proof that pending upstream requests reject promptly when the upstream socket closes.
- Kept Realtime transcription status/error output redacted and limited to enabled/model/endpoint host/key-present/last-error state.
- Hardened Phase 1A host-service CLI parsing so unknown flags are rejected and value-taking options reject missing or empty values.

Proof:

- `rtk node --check scripts/dock-relay.mjs && rtk node --check scripts/dock-relay-status.mjs && rtk node --check scripts/dock-relay-json-rpc-client.mjs && rtk node --check scripts/dock-relay-phase5.test.mjs`
  - Result: passed.
- `rtk node --test scripts/dock-relay-phase5.test.mjs`
  - Result: passed.
  - Executed 20 tests, 0 failures.
- `rtk node --check scripts/codex-dock-host-service.mjs && rtk node --check scripts/codex-dock-host-service.test.mjs && rtk npm run test:host-service`
  - Result: passed.
  - Host-service executed 9 tests, 0 failures.
- `rtk npm run test:relay`
  - Result: passed.
  - Executed 47 tests, 0 failures.
- `rtk npm test`
  - Result: passed.
  - Executed 47 relay tests and 9 host-service tests, 0 failures.
- `rtk git diff --check`
  - Result: passed.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.

Parallel review results incorporated:

- Relay review found Phase 2 gaps around real `thread/resume excludeTurns`, overload `-32001`, `/readyz` versus `/healthz`, `Makefile` status visibility, malformed message status, pending upstream request proof, and logging/status shape. The implemented slice fixes those concrete gaps.
- Host-service review confirmed the original Phase 1A repairs were present and found that unknown CLI flags were still accepted. That was fixed in the Phase 2 slice; the follow-on lifecycle/token/status/log core is recorded in the next section.

Still not claimed:

- No live launchd/systemd host proof exists yet; the fake-runner lifecycle core is recorded in the next section.
- No `Makefile` service target was replaced.
- No `home` host endpoint is configured or proven.
- No generated two-host app config is wired into the app.
- No final Multi-host app behavior proof is claimed.
- Physical-device checks remain deferred manual QA for Amir under the parent dock operating rule.

## 2026-05-28 - Phase 1B/3A Host-Service Lifecycle Core

Scope implemented:

- Added `scripts/codex-dock-host-service-runtime.mjs` for bounded runtime helpers: atomic file writes, token creation/reuse, command running, JSON health reads, log tailing, and shared redaction.
- Implemented real command surfaces in `scripts/codex-dock-host-service.mjs`: `install`, `start`, `stop`, `restart`, `status`, `logs`, and `doctor`.
- `install` creates/reuses the raw app-server token with mode `0600`, writes rendered launchd/systemd service files, and runs the platform service-manager adapter through an injected runner.
- macOS paths use launchd `bootout`, `bootstrap`, `kickstart`, and `print`.
- Linux paths use `systemctl --user link`, `daemon-reload`, `enable`, `start`, `stop`, and `is-active`; install enables units without `--now`, start runs raw app-server before relay, and stop runs relay before raw app-server.
- `status` combines service-manager state with raw app-server `/readyz`, relay `/readyz`, and relay `/statusz`.
- `logs` reads macOS log files or Linux `journalctl --user` output through the same redactor.
- `doctor` reports inactive services and unhealthy endpoints without starting/stopping services.
- Replaced the host-service script's own CLI `--env-file` option with `--service-env-file` so Node 25 does not intercept it before the script runs. The rendered relay service still correctly passes `--env-file` to `scripts/dock-relay.mjs`.
- Tightened secret hygiene:
  - redacts bearer values, OpenAI keys, token/secret paths, credentialed URLs, base64 audio, transcript/prompt text, JSON-RPC payload containers, request/response/body/params, headers, cookies, sessions, and large token-looking strings;
  - redacts command failure messages and saved command results;
  - passes a minimal `HOME`/`PATH`/`LANG` environment to `launchctl`, `systemctl`, and `journalctl` rather than inheriting parent secrets.

Proof:

- `rtk node --check scripts/codex-dock-host-service-runtime.mjs`
  - Result: passed.
- `rtk node --check scripts/codex-dock-host-service.mjs`
  - Result: passed.
- `rtk node --check scripts/codex-dock-host-service.test.mjs`
  - Result: passed.
- `rtk npm run test:host-service`
  - Result: passed.
  - Executed 17 tests, 0 failures.
- `rtk npm test`
  - Result: passed.
  - Executed 47 relay tests and 17 host-service tests, 0 failures.
- `rtk git diff --check`
  - Result: passed.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.

Parallel review results incorporated:

- Lifecycle review confirmed the smallest useful slice was the service-manager lifecycle core and identified command surfaces, service ordering, token reuse, and fake-runner tests.
- Redaction/security review found blockers around JSON-RPC payload leakage, cookie/session/header leakage, Node 25 `--env-file` interception, raw failure stderr, and child-process env inheritance. The implemented slice fixes those blockers and adds regression tests.

Still not claimed:

- No live launchd or systemd user service was installed, started, stopped, or restarted by this slice.
- No `Makefile` service target was cut over to the new setup script.
- No live `Amir-M5` status proof from the new service-manager path is claimed.
- No `home` host endpoint is configured or proven.
- No generated two-host app config is wired into the app.
- No README service runbook rewrite is claimed.
- No final Multi-host app behavior proof is claimed.
- Physical-device checks remain deferred manual QA for Amir under the parent dock operating rule.

## 2026-05-28 - Phase 3B Makefile Wrapper And Live Mac Launchd Proof

Scope implemented:

- Cut `rtk make services` over to the host-service wrapper: generated `.codex-dock/service.env`, `node-deps`, host-service `install`, host-service `start`, and a status wait gate.
- Reframed `app-server` and `dock-relay` Makefile targets as compatibility aliases for the two-service host bundle.
- Replaced `app-server-status` and `dock-relay-status` with host-service bundle status, which fails nonzero unless all required local and app-facing health checks pass.
- Added `host-service-doctor`, `host-service-logs`, and host-service lifecycle Makefile targets.
- Added `scripts/codex-dock-host-service-env.mjs` so install writes generated service env and non-secret host env files under `.codex-dock/` while reading user `.env` only as input.
- Kept `.env` user-owned: `ENV_FILE` defaults to `.codex-dock/service.env`, `env-file` refuses `.env`, and `.env` mtime stayed unchanged.
- Fixed live Mac launchd cutover issues found during proof:
  - launchd bootstrap exit `5` after old-service bootout is retried in the host-service wrapper;
  - loaded-but-broken launchd jobs are not treated as reusable unless they are loaded from the expected path and `state = running`;
  - raw app-server `--listen` URLs render as `ws://IP:PORT` without a trailing slash because `codex app-server` rejects `ws://IP:PORT/`.
- Tightened status proof:
  - `status` and `doctor` return nonzero when not ready/failed;
  - relay `/statusz` only counts healthy when the snapshot is OK and raw-history health is OK;
  - non-simulator profiles also check app-facing relay `/readyz`, not just loopback relay readiness.

Proof:

- `rtk node --check scripts/codex-dock-host-service-env.mjs`
  - Result: passed.
- `rtk node --check scripts/codex-dock-host-service-runtime.mjs`
  - Result: passed.
- `rtk node --check scripts/codex-dock-host-service.mjs`
  - Result: passed.
- `rtk node --check scripts/codex-dock-host-service.test.mjs`
  - Result: passed.
- `rtk npm run test:host-service`
  - Result: passed.
  - Executed 20 tests, 0 failures.
- `rtk npm run test:relay`
  - Result: passed.
  - Executed 47 tests, 0 failures.
- `rtk make services`
  - Result: passed.
  - Live Mac launchd services are installed/loaded from `.codex-dock/services/`.
- `rtk make app-server-status`
  - Result: passed.
  - Status was `ready` with raw app-server `/readyz`, relay `/readyz`, relay `/statusz` with `snapshotOK: true` and `historyOK: true`, and app-facing relay `/readyz` all healthy.
- `rtk make dock-relay-status`
  - Result: passed with the same ready bundle status.
- `rtk make host-service-doctor`
  - Result: passed with `status: passed` and no problems.
- `rtk npm test`
  - Result: passed.
  - Executed 47 relay tests and 20 host-service tests, 0 failures.
- `rtk make app SIM='iPhone 17'`
  - Result: failed before build/launch because `iPhone 17` matched two simulators. This is a simulator-name ambiguity, not an app/service failure.
- `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`
  - Result: passed.
  - Used the accepted non-Pro simulator `feat_anim_1 - iPhone 17`.
- `rtk git diff --check`
  - Result: passed.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.

Parallel review results incorporated:

- Wrapper-cutover review said not to pretend old per-service Makefile targets still control one service. The implementation makes those old target names compatibility aliases for the bundle and updates help text.
- Live-proof review said not to cut over until status failed nonready states, service env files were generated, launchd start reused running jobs, and app-facing relay reachability was checked. The implementation fixes those blockers before claiming live Mac proof.

Still not claimed:

- No live Linux systemd user service was installed on `home`.
- No generated two-host app config is wired into the app.
- No README service runbook rewrite is claimed.
- No final `Amir-M5` plus `home` app multi-host behavior proof is claimed.
- Physical-device checks remain deferred manual QA for Amir under the parent dock operating rule.

## 2026-05-28 - Phase 4A Generated Two-Host Env And Simulator App Consumption

Scope implemented:

- Made `.codex-dock/host.env` the first generated non-secret app config artifact.
- `scripts/codex-dock-host-service-env.mjs` now copies only app-safe host keys into `host.env`:
  - `CODEX_DOCK_HOSTS`;
  - `CODEX_DOCK_HOST_<suffix>_WS`;
  - `CODEX_DOCK_HOST_<suffix>_APP_SERVER_WS`;
  - `CODEX_DOCK_HOST_<suffix>_NAME`;
  - `CODEX_DOCK_HOST_<suffix>_AUTH_MODE`;
  - `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`;
  - `CODEX_DOCK_REAL_HOST_ID`;
  - `CODEX_DOCK_REAL_HOST_NAME`.
- `host.env` explicitly does not copy OpenAI keys, bearer/token values, token file paths, provider config, prompt/transcript/audio/payload text, cookies, sessions, or passwords.
- `Makefile` now passes `--host-env-file "$(CURDIR)/$(HOST_ENV_FILE)"` to the host-service script and adds per-host `AUTH_MODE` values to generated `.codex-dock/service.env`.
- `rtk make app` now loads only `.codex-dock/host.env` for simulator launch, exports each safe `CODEX_DOCK_*` line as `SIMCTL_CHILD_CODEX_DOCK_*`, and no longer hard-codes the simulator host list into the launch command.
- `HostRegistry.fromEnvironment(...)` now rejects duplicate `CODEX_DOCK_HOSTS`, parses per-host `CODEX_DOCK_HOST_<suffix>_AUTH_MODE=none|bearer`, ignores app-facing tokens when auth mode is `none`, and requires a scoped token/token-file when auth mode is explicitly `bearer`.
- Added focused host-service and Swift config tests for generated two-host no-auth config, duplicate hosts, missing scoped endpoints, invalid auth modes, and app-safe `host.env` redaction.

Proof:

- `rtk node --check scripts/codex-dock-host-service-env.mjs && rtk node --check scripts/codex-dock-host-service.mjs`
  - Result: passed.
- `rtk npm run test:host-service`
  - Result: passed.
  - Executed 21 tests, 0 failures.
- `rtk swift test --filter DockConfigurationTests`
  - Result: passed.
  - Executed 18 tests, 0 failures.
- `rtk make -n app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`
  - Result: passed as a dry-run command expansion.
  - Confirmed simulator launch reads `.codex-dock/host.env` and does not source `.codex-dock/service.env`.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`
  - Result: passed.
  - Generated `.codex-dock/host.env` with `CODEX_DOCK_HOSTS=Amir-M5,home`, `CODEX_DOCK_HOST_AMIR_M5_WS=ws://192.168.50.117:4510/`, `CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510`, and both host auth modes set to `none`.
- App host env secret check:
  - `rg -n 'OPENAI_API_KEY|TOKEN|TOKEN_FILE|BEARER|SECRET|PASSWORD|COOKIE|SESSION|TRANSCRIPT|PROMPT|AUDIO|PAYLOAD' .codex-dock/host.env`
  - Result: no matches.
- Simulator app log proof:
  - `xcrun simctl spawn BAD95C8E-3E57-4818-9B90-E4ED22593B4B log show --last 3m --style compact --predicate 'subsystem == "com.aelaguiz.CodexDock" AND (eventMessage CONTAINS "host registry" OR eventMessage CONTAINS "host configuration loaded")'`
  - Result: logs showed `host configuration loaded host_id=Amir-M5 ... bearer_configured=false`, `host configuration loaded host_id=home ... bearer_configured=false`, `host registry created hosts=2`, and `host registry loaded from environment hosts=2`.
- `rtk swift test --filter DockStoreTests`
  - Result: passed.
  - Executed 19 tests, 0 failures.
- `rtk make app-server-status && rtk make dock-relay-status`
  - Result: passed.
  - Bundle status was `ready` with raw app-server, relay, statusz, and app-facing relay health passing.
- `rtk npm test`
  - Result: passed.
  - Executed 47 relay tests and 21 host-service tests, 0 failures.
- `rtk swift test`
  - Result: passed.
  - Executed 187 tests, 5 skipped, 0 failures.
- `rtk git diff --check`
  - Result: passed.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.

Still not claimed:

- No live Linux systemd user service was installed on `home`.
- No README service runbook rewrite is claimed.
- No final `Amir-M5` plus `home` app multi-host behavior proof is claimed because `home` is configured in app env but the real `home` service is not running yet.
- Physical-device checks remain deferred manual QA for Amir under the parent dock operating rule.

## 2026-05-28 - Phase 3C Live Linux Systemd Proof On `home`

Scope implemented:

- Deployed the current working tree to `/home/aelaguiz/workspace/codex-client` on `home`, excluding `.env`, `env.bak`, `.codex-dock/`, build outputs, `node_modules/`, and git metadata.
- Installed Node dependencies on `home` with `rtk npm ci`.
- Proved the same Makefile host-service wrapper can install/start/status the Linux service bundle with explicit Linux overrides:
  - `HOST_SERVICE_PLATFORM=linux`;
  - `CODEX_BIN=/home/aelaguiz/.local/bin/codex`;
  - `NODE_BIN=/usr/bin/node`;
  - `CODEX_DOCK_REAL_HOST_ID=home`;
  - `CODEX_DOCK_REAL_HOST_NAME=Home`;
  - `CODEX_DOCK_HOSTS=home`;
  - `DOCK_RELAY_WS=ws://100.66.11.7:4510`;
  - `APP_SERVER_LISTEN=ws://127.0.0.1:4500`;
  - `DOCK_RELAY_HISTORY_WS=ws://127.0.0.1:4500`.
- Live systemd proof exposed and fixed two real Linux-only issues:
  - `systemctl --user link` is not idempotent when linked unit files already exist; fixed by using `systemctl --user link --force`.
  - The service-manager child env was too strict for `systemctl --user`; fixed by preserving only the non-secret user-bus coordinates `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` while still excluding OpenAI keys and bearer tokens.
- Tightened `host.env` generation so host-specific app env keys are emitted only for host IDs listed in `CODEX_DOCK_HOSTS`. This removed unused `AMIR_M5` keys from the home-only generated app config.

Proof:

- Remote deploy hygiene:
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && pwd && test ! -e .env && echo no-dotenv && test ! -e env.bak && echo no-env-bak && test ! -e .codex-dock && echo no-runtime && test -f scripts/codex-dock-host-service.mjs && test -f scripts/codex-dock-host-service-env.mjs && test -f Makefile && echo host-service-files-present'`
  - Result: passed with `no-dotenv`, `no-env-bak`, `no-runtime`, and `host-service-files-present`.
- Remote toolchain:
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && node --version && npm --version && rtk --version && /home/aelaguiz/.local/bin/codex --version'`
  - Result: `node v18.19.1`, `npm 9.2.0`, `rtk 0.37.2`, `codex-cli 0.135.0-alpha.2`.
- Remote dependency install:
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk npm ci'`
  - Result: passed; 1 package installed, 0 vulnerabilities.
- Remote syntax/tests:
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk node --check scripts/codex-dock-host-service.mjs && rtk node --check scripts/codex-dock-host-service-env.mjs && rtk node --check scripts/codex-dock-host-service-runtime.mjs'`
  - Result: passed.
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk npm run test:host-service'`
  - Result: passed.
  - Executed 21 tests, 0 failures.
- Live Linux wrapper proof:
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make services HOST_SERVICE_PLATFORM=linux CODEX_BIN=/home/aelaguiz/.local/bin/codex NODE_BIN=/usr/bin/node CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home CODEX_DOCK_HOSTS=home CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510 APP_SERVER_HOST=100.66.11.7 DOCK_RELAY_WS=ws://100.66.11.7:4510 APP_SERVER_LISTEN=ws://127.0.0.1:4500 DOCK_RELAY_HISTORY_WS=ws://127.0.0.1:4500 HOST_SERVICE_NETWORK_PROFILE=tailscale'`
  - Result: passed.
  - Installed and started the `systemd-user` host-service bundle.
- Live Linux status:
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-status ...'`
  - Result: passed with `status: ready`, `serviceManager: systemd-user`, raw app-server active, dock relay active, raw app-server `/readyz` OK, relay `/readyz` OK, relay `/statusz` OK with `snapshotOK: true`, `historyOK: true`, and app-facing relay `/readyz` OK at `ws://100.66.11.7:4510/`.
- Live Linux doctor:
  - `rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-doctor ...'`
  - Result: passed with `status: passed` and `problems: []`.
- App-facing relay network proof from `Amir-M5`:
  - `curl -fsS --max-time 5 http://100.66.11.7:4510/readyz`
  - Result: `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
  - `curl -fsS --max-time 5 http://100.66.11.7:4510/statusz`
  - Result: `ok: true`, host id `home`, history health `ok: true`, `phoneAuth: none`, `historyCredentialConfigured: true`, and Realtime transcription `enabled: false` / `keyPresent: false` because no OpenAI key was copied to `home`.
- Home generated app env:
  - `.codex-dock/host.env` on `home` contains only `CODEX_DOCK_HOSTS=home`, `CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510/`, `CODEX_DOCK_HOST_HOME_NAME=Home`, `CODEX_DOCK_HOST_HOME_AUTH_MODE=none`, and non-secret host identity values.
  - `rg -n 'OPENAI_API_KEY|TOKEN|TOKEN_FILE|BEARER|SECRET|PASSWORD|COOKIE|SESSION|TRANSCRIPT|PROMPT|AUDIO|PAYLOAD|AMIR_M5|STALE' .codex-dock/host.env`
  - Result: no matches.
- Systemd readback:
  - `systemctl --user status codex-dock-app-server.service codex-dock-relay.service --no-pager`
  - Result: both units active/running under the user manager.
- Local regression after Linux fixes:
  - `rtk node --check scripts/codex-dock-host-service.mjs && rtk npm run test:host-service`
  - Result: passed; 21 tests, 0 failures.
  - `rtk npm test`
  - Result: passed; 47 relay tests and 21 host-service tests, 0 failures.
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`
  - Result: passed after the env-filter change.
  - Simulator logs showed `host registry loaded from environment hosts=2` for `Amir-M5` and `home`, both `bearer_configured=false`.
  - `scripts/codex-dock-host-service.mjs` is 998 lines after the Linux fixes.
  - `.env` mtime remained `1779986258`.

Still not claimed:

- README service runbook rewrite is not claimed.
- Final app multi-host behavior proof is not claimed. The simulator has loaded both generated hosts from env, and both services are up, but a full app UI smoke for two-host behavior and one-host failure remains.
- Realtime transcription on `home` is not claimed because no `OPENAI_API_KEY` was copied to `home`; the relay correctly reports `enabled: false` and `keyPresent: false`.
- Physical-device checks remain deferred manual QA for Amir under the parent dock operating rule.

## 2026-05-28 - Phase 6 README And Final Simulator Multi-Host Smoke

Scope implemented:

- Updated `README.md` to match the current host-service wrapper:
  - raw app-server on loopback `ws://127.0.0.1:4500`;
  - Dock relay as the app-facing endpoint;
  - macOS launchd and Linux systemd user service files under `.codex-dock/services/`;
  - `.codex-dock/service.env` as host-side service config that may contain secrets;
  - `.codex-dock/host.env` as non-secret app config;
  - exact Mac service commands;
  - exact `home` Linux service/status/doctor commands;
  - physical-device testing deferral and manual QA handoff.
- Ran final simulator multi-host smoke on accepted simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Ran a deliberate one-host failure smoke without stopping real services by relaunching the simulator with `CODEX_DOCK_HOST_HOME_WS=ws://127.0.0.1:9`, then restored `home` to `ws://100.66.11.7:4510`.

Proof:

- README hygiene:
  - `rtk git diff --check`
  - Result: passed.
- Final focused regression after smoke:
  - `rtk npm test`
  - Result: passed.
  - Executed 47 relay tests and 21 host-service tests with 0 failures.
  - `rtk swift test --filter DockConfigurationTests`
  - Result: passed.
  - Executed 18 tests, 0 failures.
- Final two-host app launch:
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`
  - Result: passed.
  - Generated `.codex-dock/host.env` contained `Amir-M5` and `home`, both `AUTH_MODE=none`, and no forbidden secret-shaped keys.
  - Simulator logs showed `host registry loaded from environment hosts=2`, with `bearer_configured=false` for both hosts.
  - Mobile MCP element readback showed both host cards:
    - `Amir-M5`, `ws://192.168.50.117:4510 · 209 sessions`;
    - `Home`, `ws://100.66.11.7:4510 · 100 sessions, partial: Agents: App-server disconnected: The operation couldn’t be completed. Message too long`.
  - Mobile MCP readback also showed `Amir-M5 / main` rows still visible below the `Home` partial error.
- One-host failure app launch:
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://127.0.0.1:9'`
  - Result: passed.
  - Mobile MCP showed `Partial: Home: App-server disconnected: Could not connect to the server.`
  - Mobile MCP showed `Home Dock load failed` and `Home Agents load failed` with the same connection error.
  - Mobile MCP showed `Amir-M5 / main` rows still visible after the `Home` failure.
- Restore run:
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`
  - Result: passed.
  - Final `.codex-dock/host.env` again points `CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510`.
- Service proof:
  - `rtk make app-server-status && rtk make dock-relay-status`
  - Result: passed with Mac bundle `status: ready`.
  - `curl -fsS --max-time 5 http://100.66.11.7:4510/readyz`
  - Result: `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
  - `curl -fsS --max-time 5 http://100.66.11.7:4510/statusz`
  - Result: `ok: true`, host id `home`, history health OK, `phoneAuth: none`, `historyCredentialConfigured: true`, and transcription `enabled: false` / `keyPresent: false`.
- Screenshots:
  - `/tmp/codex-client/20260528T213700Z/multi-host-smoke-001-two-host-partial.png`
  - `/tmp/codex-client/20260528T213700Z/multi-host-smoke-002-home-offline.png`
  - `/tmp/codex-client/20260528T213700Z/multi-host-smoke-003-restored-home.png`
- Secret hygiene:
  - `.env` mtime remained `1779986258`.

Still not claimed:

- Physical-device checks remain deferred manual QA for Amir under the parent dock operating rule.
- Realtime transcription on `home` is not claimed because no `OPENAI_API_KEY` was copied to `home`; relay status correctly reports it disabled.
