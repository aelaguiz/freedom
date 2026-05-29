# Codex Dock Multi-Host Service Setup And Robustness - Thermonuclear Review

Date: 2026-05-28
Scope: Multi-host Phase 1A through Phase 6, latest review covers README and final non-physical multi-host app smoke
Verdict: approve

## Findings

No open thermonuclear findings for the implemented Phase 1A, Phase 2, Phase 1B/3A, Phase 3B, Phase 4A, Phase 3C, or Phase 6 slices.

The review initially found five maintainability and boundary issues. All were repaired before this verdict:

- Missing CLI option values could flow in as booleans. Fixed with an explicit value-taking option list and missing-value errors in `scripts/codex-dock-host-service.mjs`.
- Redaction depended too much on friendly field names. Fixed so generic strings also sanitize credentialed URLs, URL query secrets, bearer strings, `OPENAI_API_KEY=value`, OpenAI-looking keys, and large token-looking values.
- The dry-run module contained an exported mutating token writer. Removed from Phase 1A; token generation/reuse is deferred to the real install phase.
- Unsupported lifecycle commands hydrated config before rejecting. Fixed so `install`, `start`, `stop`, `restart`, `logs`, and `doctor` fail before config construction.
- Env-format app config omitted auth mode and accepted line breaks. Fixed by emitting `CODEX_DOCK_HOST_<ID>_AUTH_MODE` and rejecting line breaks in env values.

## Code Shape

File size was acceptable for the initial Phase 1A slice:

- `scripts/codex-dock-host-service.mjs`: 705 lines
- `scripts/codex-dock-host-service.test.mjs`: 227 lines

The renderer is direct rather than magical. `createHostServiceConfig` builds one typed-ish config object, `renderHostServices` has one platform branch for launchd versus systemd-user, and app-facing config export is separate from service-file rendering. The file is under the 1,000-line threshold and does not need premature decomposition yet.

The important dry-run boundary is now clear:

- `render`, `app-config`, and dry-run `status` are implemented.
- `install`, `start`, `stop`, `restart`, `logs`, and `doctor` fail loudly as not implemented in Phase 1A.
- No Phase 1A CLI command writes token files, service files, `.env`, `.codex-dock/service.env`, launchd state, or systemd state.

## Proof Context

Accepted proof from the parent implementation run:

- `rtk node --check scripts/codex-dock-host-service.mjs`: passed
- `rtk npm test`: passed, with 41 relay tests and 9 host-service tests
- `rtk git diff --check`: passed
- `.env` mtime remained `1779986258`

## Residual Risk

This approval is narrow. It approves the Phase 1A dry-run renderer as a maintainable preflight contract. It does not approve service installation, `Makefile` replacement, `home` host setup, app multi-host proof, or final Multi-host readiness.

## Phase 2 Follow-Up Review - 2026-05-28T20:36:17Z

Verdict: approve for relay status/error/upstream-robustness slice.

No open thermonuclear findings for the implemented relay slice.

The follow-up review initially found concrete correctness and maintainability gaps. They were repaired before this verdict:

- Real relay `thread/resume` trusted caller params for `excludeTurns`. Fixed so the relay enforces `excludeTurns: true` for live subscription resumes and recovery reuses the normalized params.
- Upstream JSON-RPC errors lost their numeric codes. Fixed with `JsonRpcUpstreamError`, preserving overload `-32001` and structured retryable overload data.
- `/readyz` and `/healthz` had identical semantics. Fixed so `/readyz` is process-ready and `/healthz` carries static config.
- Normal relay status only exposed `/readyz`. Fixed so `rtk make dock-relay-status` also prints `/statusz`.
- Malformed downstream messages returned a parse error but did not update status. Fixed so the client-facing parse error appears in `/statusz`.
- Pending upstream request rejection existed in the upstream client but had no direct proof. Added a test that closes the upstream socket while a request is pending and verifies prompt rejection.
- Realtime transcription status exposed extra nonessential fields and always said enabled. Narrowed status to enabled/model/endpoint host/key-present/last-error and made `enabled` reflect key presence.
- Host-service CLI still accepted unknown flags. Fixed with an explicit boolean-option allowlist and rejection tests.

Code shape after the slice:

- `scripts/dock-relay.mjs`: 816 lines
- `scripts/dock-relay-status.mjs`: 250 lines
- `scripts/dock-relay-json-rpc-client.mjs`: 225 lines
- `scripts/codex-dock-host-service.mjs`: 721 lines
- `scripts/codex-dock-host-service.test.mjs`: 247 lines
- `scripts/dock-relay-phase5.test.mjs`: 1,278 lines

The production code remains below the 1,000-line threshold. The large relay Phase 5 test file is acceptable for this slice because it centralizes relay integration proof, but it should be split by behavior area if it grows again or starts hiding failures.

Proof context:

- `rtk node --check scripts/dock-relay.mjs && rtk node --check scripts/dock-relay-status.mjs && rtk node --check scripts/dock-relay-json-rpc-client.mjs && rtk node --check scripts/dock-relay-phase5.test.mjs`: passed
- `rtk node --test scripts/dock-relay-phase5.test.mjs`: passed 20 tests, 0 failures
- `rtk node --check scripts/codex-dock-host-service.mjs && rtk node --check scripts/codex-dock-host-service.test.mjs && rtk npm run test:host-service`: passed 9 tests, 0 failures
- `rtk npm run test:relay`: passed 47 tests, 0 failures
- `rtk npm test`: passed 47 relay tests and 9 host-service tests, 0 failures
- `rtk git diff --check`: passed
- `.env` mtime remained `1779986258`

Residual risk remains outside this approved slice: real service install/start/status/log/doctor behavior, install-scoped token creation, generated two-host config, `home` setup, app multi-host smoke proof, and physical-device behavior checks are still not claimed.

## Phase 1B/3A Follow-Up Review - 2026-05-28T20:49:09Z

Verdict: approve for the fake-runner host-service lifecycle core.

No open thermonuclear findings for the implemented host-service lifecycle core.

The follow-up review initially found correctness, secrecy, and maintainability gaps. They were repaired before this verdict:

- Systemd install started services with `enable --now`. Fixed so install links/reloads/enables only; `start` owns startup.
- Systemd stop did not prove relay-before-raw shutdown order. Fixed and covered with explicit fake-runner tests.
- Safe token metadata was returned under a key named `token`, so strict redaction hid it. Fixed by moving the boolean to `appServerAuth.created`.
- Logs could leak full JSON-RPC payloads under `params`, `body`, `payload`, `request`, or `response`. Fixed with payload-container redaction and regression tests.
- Cookies, session IDs, and headers could leak from log/status/doctor output. Fixed with key and raw-string redaction plus regression tests.
- Service-manager failure errors could print raw command args. Fixed by redacting thrown error messages and saved command results.
- Service-manager subprocesses inherited the parent environment. Fixed by passing a minimal `HOME`/`PATH`/`LANG` env to `launchctl`, `systemctl`, and `journalctl`.
- The host-service CLI option `--env-file` conflicted with Node 25. Fixed by renaming the host-service option to `--service-env-file`; rendered relay service files still pass `--env-file` to the relay script.

Code shape after the slice:

- `scripts/codex-dock-host-service.mjs`: 958 lines
- `scripts/codex-dock-host-service-runtime.mjs`: 226 lines
- `scripts/codex-dock-host-service.test.mjs`: 653 lines

The main host-service script remains under the 1,000-line threshold. Redaction and runtime helpers moved into a dedicated helper module, which keeps lifecycle code readable without splitting the command surface prematurely.

Proof context:

- `rtk node --check scripts/codex-dock-host-service-runtime.mjs`: passed
- `rtk node --check scripts/codex-dock-host-service.mjs`: passed
- `rtk node --check scripts/codex-dock-host-service.test.mjs`: passed
- `rtk npm run test:host-service`: passed 17 tests, 0 failures
- `rtk npm test`: passed 47 relay tests and 17 host-service tests, 0 failures
- `rtk git diff --check`: passed
- `.env` mtime remained `1779986258`

Residual risk remains outside this approved slice: live launchd/systemd proof, `Makefile` wrapper replacement, README runbook rewrite, generated two-host config, `home` setup, app multi-host smoke proof, and physical-device behavior checks are still not claimed.

## Phase 3B Follow-Up Review - 2026-05-28T21:07:40Z

Verdict: approve for Makefile wrapper cutover and live Mac launchd proof.

No open thermonuclear findings for the implemented Mac wrapper slice.

The follow-up review initially found correctness and false-proof risks. They were repaired before this verdict:

- `status` and `doctor` could return `0` when services were not ready. Fixed so `status` returns nonzero unless the bundle is `ready`, and `doctor` returns nonzero unless it `passed`.
- The host-service script passed `--env-file` to the relay but did not generate that file. Fixed with a dedicated env module that writes `.codex-dock/service.env` and non-secret `.codex-dock/host.env`, while treating `.env` as read-only input.
- macOS start/reuse semantics were too close to restart semantics. Fixed so already-running launchd services are reused instead of kicked.
- Relay `/statusz` was previously process-visible even if raw-history health was down. Fixed so host-service status requires both `snapshotOK` and `historyOK`.
- Loopback relay health was not enough proof for the app path. Fixed so non-simulator profiles also probe app-facing relay `/readyz`.
- Live launchd cutover exposed two real Mac issues: bootstrap exit `5` during old-service replacement and a loaded-but-broken app-server job. Fixed with launchd bootstrap retry and "reuse only if expected path and `state = running`" logic.
- `codex app-server` rejects a trailing slash in `--listen`. Fixed so raw app-server listens at `ws://127.0.0.1:4500`, while app-facing URLs can keep normal URL formatting.
- The old Makefile per-service names were misleading after bundle cutover. Fixed by making them explicit compatibility aliases for the host service bundle.

Code shape after the slice:

- `scripts/codex-dock-host-service.mjs`: 1,000 lines
- `scripts/codex-dock-host-service-env.mjs`: 185 lines
- `scripts/codex-dock-host-service-runtime.mjs`: 226 lines
- `scripts/codex-dock-host-service.test.mjs`: 758 lines

The main script is exactly at the threshold, not over it. The new env module prevents additional env-generation logic from expanding the control script beyond the maintainability line. Any next host-service feature should move behavior into a focused module before adding more lines to `scripts/codex-dock-host-service.mjs`.

Proof context:

- `rtk node --check scripts/codex-dock-host-service-env.mjs`: passed
- `rtk node --check scripts/codex-dock-host-service-runtime.mjs`: passed
- `rtk node --check scripts/codex-dock-host-service.mjs`: passed
- `rtk node --check scripts/codex-dock-host-service.test.mjs`: passed
- `rtk npm run test:host-service`: passed 20 tests, 0 failures
- `rtk npm run test:relay`: passed 47 tests, 0 failures
- `rtk make services`: passed
- `rtk make app-server-status`: passed with bundle `status: ready`
- `rtk make dock-relay-status`: passed with bundle `status: ready`
- `rtk make host-service-doctor`: passed with `status: passed`
- `rtk npm test`: passed 47 relay tests and 20 host-service tests, 0 failures
- `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`: passed
- `rtk git diff --check`: passed
- `.env` mtime remained `1779986258`

Residual risk remains outside this approved slice: live Linux systemd proof on `home`, generated two-host app config, README runbook rewrite, final app multi-host behavior proof, and physical-device behavior checks are still not claimed.

## Phase 4A Follow-Up Review - 2026-05-28T21:20:03Z

Verdict: approve for generated two-host env and simulator app-consumption proof.

No open thermonuclear findings for the implemented env-first app config slice.

The follow-up review focused on false proof, secret leakage, and accidental second config paths. The implemented slice is acceptable because it stays on the existing env bootstrap path instead of adding JSON/persistence early:

- `.codex-dock/host.env` is the generated app artifact and is separate from `.codex-dock/service.env`, which may contain relay-side secrets.
- Host env generation uses an explicit app-safe whitelist for `CODEX_DOCK_HOSTS`, per-host `WS`/`APP_SERVER_WS`/`NAME`/`AUTH_MODE`, and non-secret legacy host identity values.
- The generated `host.env` proof contained `Amir-M5` and `home` with both auth modes set to `none`, and the secret scan found no `OPENAI_API_KEY`, token, token-file, bearer, secret, password, cookie, session, transcript, prompt, audio, or payload keys.
- `rtk make app` now reads only `.codex-dock/host.env` and exports its safe `CODEX_DOCK_*` values to `SIMCTL_CHILD_CODEX_DOCK_*`; it does not source `.codex-dock/service.env`.
- `HostRegistry` now rejects duplicate host IDs, rejects invalid per-host auth modes, treats `AUTH_MODE=none` as no app-facing token, and requires scoped token input for explicit `AUTH_MODE=bearer`.
- Simulator logs proved the app actually consumed the generated env: `host registry loaded from environment hosts=2`, with `bearer_configured=false` for `Amir-M5` and `home`.

Code shape after the slice:

- `scripts/codex-dock-host-service.mjs`: 998 lines
- `scripts/codex-dock-host-service-env.mjs`: 222 lines
- `scripts/codex-dock-host-service-runtime.mjs`: 226 lines
- `scripts/codex-dock-host-service.test.mjs`: 819 lines
- `CodexDock/Configuration/HostRegistry.swift`: 120 lines
- `CodexDock/Configuration/DockHostConfiguration.swift`: 129 lines

The main host-service script is now under the threshold after the Linux fixes. Additional behavior landed in the env helper and Swift registry tests, which is the right direction. The next host-service feature must still avoid adding lines to `scripts/codex-dock-host-service.mjs` unless it removes or moves existing logic first.

Proof context:

- `rtk node --check scripts/codex-dock-host-service-env.mjs && rtk node --check scripts/codex-dock-host-service.mjs`: passed
- `rtk npm run test:host-service`: passed 21 tests, 0 failures
- `rtk swift test --filter DockConfigurationTests`: passed 18 tests, 0 failures
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`: passed
- `xcrun simctl spawn BAD95C8E-3E57-4818-9B90-E4ED22593B4B log show --last 3m --style compact --predicate 'subsystem == "com.aelaguiz.CodexDock" AND (eventMessage CONTAINS "host registry" OR eventMessage CONTAINS "host configuration loaded")'`: showed two env-loaded hosts with no bearer configured
- `rtk swift test --filter DockStoreTests`: passed 19 tests, 0 failures
- `rtk make app-server-status && rtk make dock-relay-status`: passed with bundle `status: ready`
- `rtk npm test`: passed 47 relay tests and 21 host-service tests, 0 failures
- `rtk swift test`: passed 187 tests with 5 skipped and 0 failures
- `rtk git diff --check`: passed
- `.env` mtime remained `1779986258`

Residual risk remains outside this approved slice at this pass: live Linux systemd proof on `home`, README runbook rewrite, final two-host app behavior proof, and physical-device behavior checks are still not claimed. The later Phase 3C follow-up below supersedes the Linux part.

## Phase 3C Follow-Up Review - 2026-05-28T21:31:28Z

Verdict: approve for live Linux systemd proof on `home`.

No open thermonuclear findings for the implemented Linux host-service proof.

The follow-up review focused on whether the Linux proof was real service-manager proof, whether it leaked secrets, and whether it quietly depended on Mac-only assumptions. The slice is acceptable because it proved the same wrapper under the Linux user service manager and fixed the Linux-only failures it exposed:

- `rtk make services HOST_SERVICE_PLATFORM=linux ... CODEX_DOCK_REAL_HOST_ID=home ... CODEX_DOCK_HOST_HOME_WS=ws://100.66.11.7:4510 ...` passed on `home`.
- Remote `host-service-status` reported `status: ready`, `serviceManager: systemd-user`, raw app-server active, Dock relay active, raw `/readyz` OK, relay `/readyz` OK, relay `/statusz` OK, and app-facing relay `/readyz` OK.
- Remote `host-service-doctor` reported `status: passed` with `problems: []`.
- Local Mac network proof reached `http://100.66.11.7:4510/readyz` and got `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
- Local Mac `/statusz` proof showed host id `home`, history health OK, `phoneAuth: none`, and `historyCredentialConfigured: true`.
- Realtime transcription on `home` is not claimed. Relay status correctly reports transcription `enabled: false` and `keyPresent: false` because no `OPENAI_API_KEY` was copied to `home`.
- Generated `home` `.codex-dock/host.env` contains only non-secret `home` app config and no stale `AMIR_M5` keys.

Findings fixed during the proof:

- `systemctl --user link` is not idempotent when linked unit files already exist. The wrapper now uses `systemctl --user link --force`.
- `systemctl --user` needs the user-bus coordinates. The service-manager child env now preserves only non-secret `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` while continuing to drop OpenAI keys, bearer tokens, and other secret-shaped values.
- Host-specific app env generation now filters by the IDs in `CODEX_DOCK_HOSTS`, so a home-only generated env file does not carry unused `AMIR_M5` keys.

Code shape after the Linux proof:

- `scripts/codex-dock-host-service.mjs`: 998 lines
- `scripts/codex-dock-host-service-env.mjs`: 222 lines
- `scripts/codex-dock-host-service-runtime.mjs`: 226 lines
- `scripts/codex-dock-host-service.test.mjs`: 819 lines

Proof context:

- remote deploy hygiene passed with no `.env`, no `env.bak`, no `.codex-dock/`, and host-service files present
- remote `rtk npm ci`: passed
- remote `rtk node --check` for host-service scripts: passed
- remote `rtk npm run test:host-service`: passed 21 tests, 0 failures
- remote `rtk make services HOST_SERVICE_PLATFORM=linux ...`: passed
- remote `host-service-status`: passed with `status: ready`
- remote `host-service-doctor`: passed with `status: passed`
- local Mac `curl` proof for `http://100.66.11.7:4510/readyz` and `/statusz`: passed
- local `rtk npm test`: passed 47 relay tests and 21 host-service tests, 0 failures
- simulator launch loaded `Amir-M5` plus `home` from generated env with no bearer configured
- `.env` mtime remained `1779986258`

Residual risk remains outside this approved slice at this pass: README runbook rewrite, final two-host app behavior proof, Realtime transcription on `home`, and physical-device behavior checks are still not claimed. The later Phase 6 follow-up below supersedes the README and app-smoke parts.

## Phase 6 Follow-Up Review - 2026-05-28T21:38:22Z

Verdict: approve for README runbook and final non-physical multi-host app smoke.

No open thermonuclear findings for the final non-physical Multi-host slice.

The review focused on whether the runbook tells the truth about the current service boundary, whether the final app smoke proves real behavior instead of fixture rows, and whether the final proof left the repo in a bad generated state. The slice is acceptable:

- `README.md` now describes the implemented service boundary: raw app-server on loopback, Dock relay as the app-facing endpoint, `.codex-dock/service.env` for host-side service config, and `.codex-dock/host.env` for app-safe config.
- README examples now cover exact Mac service commands and exact `home` Linux service/status/doctor commands.
- README no longer claims the raw app-server is on `ws://192.168.50.117:4500`.
- README carries the physical-device deferral rule instead of making physical proof an agent-side blocker.
- Final simulator proof used the real installed app on `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`, not SwiftUI previews or fixture rows.
- The app loaded both `Amir-M5` and `home` from generated env with no bearer configured.
- The deliberate `home` failure proof used `ws://127.0.0.1:9`, showed clear `Home` failures, and preserved healthy `Amir-M5` rows.
- The final restore launch put `CODEX_DOCK_HOST_HOME_WS` back to `ws://100.66.11.7:4510`.

Code/doc shape:

- No new runtime abstraction was added for README/smoke closeout.
- The main host-service script remains 998 lines.
- The final changes are doc/status/proof updates plus generated-env/runtime proof, not another implementation branch.

Proof context:

- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B CODEX_DOCK_HOSTS='Amir-M5,home' CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`: passed
- `rtk make app ... CODEX_DOCK_HOST_HOME_WS='ws://127.0.0.1:9'`: passed for the one-host failure smoke
- final restore launch with `CODEX_DOCK_HOST_HOME_WS='ws://100.66.11.7:4510'`: passed
- Mobile MCP readback showed both host cards, clear Home errors, and preserved `Amir-M5` rows
- `rtk make app-server-status && rtk make dock-relay-status`: passed
- Mac `curl` proof for `http://100.66.11.7:4510/readyz` and `/statusz`: passed
- generated `.codex-dock/host.env` contains both hosts and no forbidden secret-shaped keys
- `rtk npm test`: passed 47 relay tests and 21 host-service tests, 0 failures
- `rtk swift test --filter DockConfigurationTests`: passed 18 tests, 0 failures
- `rtk git diff --check`: passed
- `.env` mtime remained `1779986258`

Residual risk remains outside this approved slice: physical-device behavior checks are still Amir-owned deferred manual QA, and Realtime transcription on `home` remains unclaimed unless an OpenAI key is intentionally configured there later.
