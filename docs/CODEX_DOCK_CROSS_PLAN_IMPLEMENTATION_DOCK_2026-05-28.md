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

Physical-device proof target: implementation and acceptance for this dock program use the physical iPhone 14 path, not simulator-only evidence. Current device target is `iPhone 14` with Xcode destination id `00008110-000E04940240A01E`.

Non-negotiables: no phone-side OpenAI key, no phone-side raw app-server token, no phone-side relay bearer token, no direct iPhone connection to raw `:4500` in the normal path, no Tailscale dependency in app/relay architecture, no duplicate connectivity truth, no duplicate Dock filter/count predicates, no hidden fallback from Realtime back to file upload, and no host-service setup that prints secrets.

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
- Voice production default is currently one-shot relay transcription through `RelayTranscriptionClient` and `audio/transcribe`; `OpenAITranscriptionClient` still exists as non-default reusable code.
- `Makefile` still has Mac-only launchd service generation and hard-coded `192.168.50.117` defaults.
- The raw app-server still currently binds `ws://0.0.0.0:4500` in the Mac Makefile path; the target multi-host service contract should move raw app-server to loopback by default and keep the relay as the network boundary.
- Phase 1 now implements the Agents tab/count model. There is still no `AppConnectivityStore`, no public `AppServerClient.connectionStates`, no reconnect policy, no `AppLifecycleCoordinator`, and no Realtime streaming transcription.

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

## Phase 5 - Integrated Proof And Docs

Goal: prove the whole program, not only each child plan in isolation.

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
- Physical app launch on `iPhone 14` when installed-app behavior changed.
- Physical iPhone proof is required for this dock program; simulator/env proof is not enough for physical paths.
- `Amir-M5` and `home` real-host smoke for multi-host completion.

Docs that must be current before closeout:

- `README.md`
- `Makefile` command behavior
- the four child plans
- any stale iPhone UX/voice docs touched by Realtime
- this top-level plan and its audit log

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

## 2026-05-28 - Implement Connectivity before Realtime

Decision: Build observable connection state, reconnect/rehydrate, root connectivity, and app lifecycle before Realtime voice.

Consequence: Realtime voice can use one lifecycle/status path for interruption/background/recovery instead of inventing separate store/view scene handling.

## 2026-05-28 - Implement Realtime before final Multi-host service setup

Decision: Finish the relay-owned Realtime transcription contract before locking down portable host-service setup and status docs.

Consequence: The cross-platform service bundle reports and configures the final production transcription path, not the temporary one-shot relay upload path.

## 2026-05-28 - Multi-host remains the final infrastructure expansion

Decision: Cross-platform service setup and the `home` host proof come after shared app/relay contracts are stable.

Consequence: The broadest operational work gets the least churn and can focus on actual macOS/Linux service lifecycle, generated app config, status/logs, and real two-host proof.
