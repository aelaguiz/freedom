---
title: "Codex Dock - Multi-Host Service Setup And Robustness - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md
  - README.md
  - docs/EPIC_CODEX_DOCK_MVP_2026-05-27.md
  - docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
  - docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md
  - docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md
  - docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md
  - docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md
---

# TL;DR

Outcome: Codex Dock can connect to every machine where the user runs Codex, starting with `Amir-M5` on macOS and `home` on Linux, through the same per-host Dock service shape. The app must work over ordinary configured URLs, including LAN IPs, MagicDNS names, Tailscale IPs, or any other reachable host address, and it must fail visibly with enough diagnostics to fix the host instead of leaving the client stuck.

Problem: the current service setup is Mac-specific, LaunchAgent-specific, and hard-coded to `192.168.50.117`. `home` is reachable over SSH and Tailscale (`100.66.11.7`) but has no Dock relay or raw app-server listening on ports `4510` or `4500`. The app has multi-host UI concepts, but host services, setup, health, reconnect, logs, and client error visibility are not yet an end-to-end cross-machine system.

Approach: make each Codex host run the same local service bundle: a raw Codex app-server on loopback plus a Dock relay as the app-facing endpoint. Add a platform-aware setup script that installs the bundle with launchd on macOS and systemd user services on Linux. Treat Tailscale as a supported endpoint configuration profile, not as a product dependency. Fold host-service robustness into the same plan: health/status endpoints, structured logs, fail-loud relay behavior, and client-visible errors that feed the Connectivity-owned reconnect/rehydration path.

Plan: first create a cross-platform host service contract and setup script, then wire host registry/app config to use the configured endpoints, then add server/client robustness and debug surfaces, then verify both `Amir-M5` and `home` end to end over at least one non-loopback network path, with Tailscale documented as an easy profile rather than the only path. In the top-level dock, this plan runs after Agents, Connectivity, and Realtime so the portable service setup encodes the final Dock query model, app-wide status lifecycle, and relay-owned Realtime transcription contract.

Non-negotiables: no Tailscale dependency in core app architecture, no Mac-only service lifecycle, no hard-coded host IPs in the app path, no silent spinner failure, no relay that hides upstream death, no unredacted secrets in logs/status, no duplicate host status truth, and no runtime fallback shim that pretends a host works when its service is down.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: done 2026-05-28
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:37b85d92c8c27a063afed21ed1204aa5059f543e01768f122997716a2cfa0165",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T10:58:11Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:d9853a9e4a3af0bd912ca8224c41484b7df12fc1532c4919cef4457914028634",
      "completed_at": "2026-05-28T10:59:02Z",
      "doc_hash_after": "sha256:09b093a01ef723f2bb28899ee4e5141160d3f4b7838cbbcaf96d9ee749769857"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:59:05Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:09b093a01ef723f2bb28899ee4e5141160d3f4b7838cbbcaf96d9ee749769857",
      "completed_at": "2026-05-28T11:00:21Z",
      "doc_hash_after": "sha256:aaa193477020e6431f8cacc308d1eeea29ed5646e8aef7b2de84fedb03fb3f54"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T11:00:25Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:aaa193477020e6431f8cacc308d1eeea29ed5646e8aef7b2de84fedb03fb3f54",
      "completed_at": "2026-05-28T11:00:35Z",
      "doc_hash_after": "sha256:64ce3cea8b6aef80709aa96c1365bd0109394eb615ffc291a5da008f87807e6f"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T11:00:40Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:64ce3cea8b6aef80709aa96c1365bd0109394eb615ffc291a5da008f87807e6f",
      "completed_at": "2026-05-28T11:01:16Z",
      "doc_hash_after": "sha256:fe14af6cff4781dc6a03f61f564f03d93550cccabea8938b893028f1874e496e"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T11:01:22Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:fe14af6cff4781dc6a03f61f564f03d93550cccabea8938b893028f1874e496e",
      "completed_at": "2026-05-28T11:01:31Z",
      "doc_hash_after": "sha256:7b0f9af03c0b4979a8e769c2b4fe491c21d1dd960d0b086efbe864156f2ca622"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this plan is implemented, installing Codex Dock host services on `Amir-M5` and `home` gives the app two working configured hosts. Each host reports health and status, survives service restarts, exposes useful redacted diagnostics, and tells the client enough about failures that the UI can say "Home relay is down" or "Amir-M5 upstream app-server closed" instead of waiting forever.

The claim is false if any of these happen:

- The app can only reach `Amir-M5` because host IPs or service files are still hard-coded for that machine.
- `home` cannot be installed and started with the same setup path adapted for Linux.
- Tailscale is required by app code or runtime logic instead of being just one endpoint address choice.
- A host service is down but the app shows an indefinite loading state with no actionable message.
- The relay loses its raw app-server or live upstream and leaves the downstream client believing it is still live.
- A setup/status command prints tokens, OpenAI keys, raw audio, transcript text, or other secrets.

## 0.2 In scope

- Cross-platform host setup:
  - macOS launchd support for `Amir-M5`;
  - Linux systemd user service support for `home`;
  - idempotent install/start/status/stop/restart commands;
  - per-host runtime directory, env file, service files, token files, logs, and generated app config.
- Host service bundle:
  - raw Codex app-server on local loopback for the relay to call;
  - Dock relay as the configured app-facing endpoint;
  - health/status/debug endpoints that redact secrets;
  - structured logs and log-tail helpers.
- Network profiles:
  - direct LAN IP or DNS;
  - Tailscale IP or MagicDNS;
  - manual endpoint URL;
  - simulator/local development endpoint;
  - clear docs that the app only needs a reachable WebSocket endpoint.
- App configuration:
  - host registry generated or imported from setup output;
  - persisted host entries where needed for normal app launch;
  - endpoint display and status that distinguish each host.
- Robustness:
  - relay upstream reconnect or fail-loud downstream close/error;
  - Swift connection-state observation, reconnect, and thread rehydrate;
  - app-wide connectivity rollup and indicator;
  - client-visible errors from server/relay failures.
- Verification:
  - Swift tests, Node relay tests, script/service checks, and real host smoke tests against `Amir-M5` and `home`.
- Cross-plan integration:
  - consume the Agents plan's `DockSessionQuery` and scoped load outcomes;
  - consume the Connectivity plan's `AppConnectivityStore`, root lifecycle, reconnect, and detail rehydrate contracts;
  - consume the Realtime plan's relay-owned transcription methods/status instead of preserving one-shot file upload as the future service contract;
  - preserve the implemented physical no-phone-secret relay baseline.

## 0.3 Out of scope

- Making Tailscale mandatory in app code, app architecture, or relay protocol.
- Public internet exposure, Tailscale Funnel, hostile-network hardening, mTLS, or enterprise device management.
- Replacing Codex app-server or forking its protocol.
- Cross-machine aggregation into one central server. Each host runs its own service bundle.
- Background push notifications or iOS background networking guarantees.
- New CI/doc-policing gates that only prove files exist or strings are absent.

## 0.4 Definition of done (acceptance evidence)

- `rtk make host-setup` or the equivalent setup wrapper can install/update services on macOS and Linux without hand-editing plist or systemd files.
- `Amir-M5` exposes a Dock relay endpoint through a configured non-loopback address and passes raw app-server, relay, health, status, and app smoke checks.
- `home` exposes a Dock relay endpoint through a configured non-loopback address and passes raw app-server, relay, health, status, and app smoke checks.
- The app can load both configured hosts in one registry and preserve one host's rows when the other host is offline.
- The same app/relay behavior works whether the host URL uses LAN addressing or a Tailscale IP/MagicDNS name.
- Server/relay failures produce redacted status/log evidence and client-visible error state.
- Reconnect behavior is covered for Swift live detail and relay upstream handling.
- `rtk swift test`, `rtk node --check scripts/dock-relay.mjs`, and `rtk npm test` pass.
- README documents setup, status, logs, network profiles, Tailscale profile setup, and failure debugging.

## 0.5 Key invariants (fix immediately if violated)

- Network independence: app code depends on configured WebSocket URLs, not on Tailscale APIs, Tailscale status, or tailnet-specific logic.
- One host, one service bundle: every Codex-running machine owns its local raw app-server plus local Dock relay.
- Relay is the app endpoint: the phone/app should not need to talk directly to the raw app-server in normal operation.
- Raw app-server should bind to loopback by default when the relay is local to the host; network exposure belongs at the relay boundary unless the plan explicitly says otherwise.
- Setup is idempotent: rerunning it updates service files and env safely without duplicating services or rotating tokens unnecessarily.
- Status is redacted: status commands and HTTP status endpoints never print bearer tokens, OpenAI keys, raw audio, transcript text, or full secret-bearing env.
- Generated app config is non-secret by default: physical/discovered relay config exports host IDs, display names, endpoint URLs, and auth mode only. It must not export `OPENAI_API_KEY`, raw app-server bearer tokens, or relay bearer tokens to the app.
- Phone auth baseline: `phoneAuth=none` is the implemented personal physical-iPhone default. Bearer phone auth remains an explicit dev/hardening profile, not a hidden requirement.
- Fail loud: service, relay, upstream, and protocol failures must become visible state in logs/status and client UI.
- Tailscale is a profile: easy to configure and document, but removable without changing app architecture.

## 0.6 Cross-plan position

This is Phase 4 in `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`.

Inputs from earlier phases:

- physical iPhone security baseline: no phone OpenAI key, no raw app-server token, no relay bearer token, optional bearer host config, Bonjour/saved-manual relay bootstrap;
- Agents plan: typed origin, `DockSessionQuery`, scoped load failures, counted tabs, relay `sourceKinds` filtering;
- Connectivity plan: `AppConnectivityStore`, root lifecycle, `AppServerClient` state/reconnect, `ThreadDetailStore` rehydrate, relay upstream fail-loud behavior;
- Realtime plan: relay-owned Realtime transcription and deletion/rejection of one-shot production `audio/transcribe` fallback.

Outputs for final proof:

- one repeatable host-service setup contract for macOS and Linux;
- generated non-secret app config for `Amir-M5` and `home`;
- redacted status/log/doctor surfaces;
- real two-host app smoke proof with one host allowed to fail visibly without hiding the other.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Cross-host correctness: `Amir-M5` and `home` must use the same service contract.
2. Clear failures: the app and status commands must explain what is down.
3. Network-agnostic design: LAN, DNS, and Tailscale are endpoint config choices.
4. Robust live behavior: drops reconnect or fail loudly without silent stale UI.
5. Tiny-team operations: one setup command, one status command, obvious logs.
6. Security hygiene: secrets stay on hosts where possible and never appear in status/log output.
7. Behavior preservation: existing Dock, Archive, Hosts, Session detail, request-card, and voice flows keep working.

## 1.2 Constraints

- The current Codex daemon-managed app-server uses a Unix socket and is not phone-reachable.
- Direct `codex app-server --listen ws://...` supports TCP WebSocket listeners and requires websocket auth for non-loopback listeners.
- The current Dock relay is Node ESM using `ws`.
- Current service targets are Mac launchd only and have `APP_SERVER_HOST ?= 192.168.50.117`.
- `home` is Ubuntu Linux with systemd and has Codex, Node, SSH, and Tailscale installed, but no current service on `:4500` or `:4510`.
- The iOS app can use `URLSessionWebSocketTask` for `ws://` and `wss://` URLs.
- Physical or simulator app connectivity only requires a reachable endpoint. Tailscale can provide that endpoint, but the app must not require it.

## 1.3 Architectural principles (rules we will enforce)

- Use generated host config and setup scripts instead of hard-coded IPs in source code.
- Keep platform differences in setup/service generation, not in app networking behavior.
- Keep raw app-server and relay service lifecycle together in host setup/status.
- Use the relay as the debug boundary: health/status should say whether raw app-server, live loopback discovery, history calls, transcription, and upstream resume are healthy.
- Use typed Swift connectivity states and a root-owned connectivity store. UI views render state; they do not poll services directly.
- Prefer existing XCTest, Node `node:test`, Makefile, launchd, and systemd patterns over a new orchestration framework.
- Prefer direct endpoint configuration over discovery magic for this plan; discovery can layer on later if it does not replace explicit host URLs.

## 1.4 Known tradeoffs (explicit)

- The plan does not centralize all machines behind one server. That would add a routing product and a new failure point. The simpler shape is one Dock relay per Codex host.
- Binding the raw app-server to loopback makes the relay the normal network boundary. This is safer than exposing raw app-server on every host, and it works over LAN or Tailscale because clients talk to the relay.
- Tailscale Serve is useful but not required. Direct relay listening on a chosen host interface/port is the baseline; Tailscale IP or MagicDNS can be used as the configured address.
- The implemented physical iPhone path already uses no client bearer token to the relay on a trusted LAN/Tailscale boundary. Multi-host setup should preserve that as the personal default while keeping bearer mode as an explicit dev/hardening profile, and all auth mode/status output must stay redacted.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

- The Swift app can connect to a configured WebSocket endpoint, list sessions, open live thread detail, send text, answer supported request cards, archive/unarchive, edit hosts in memory, and run voice transcription.
- `rtk make services` starts a raw Codex app-server and Dock relay on this Mac using launchd-generated plist files under `.codex-dock/`.
- The raw app-server currently uses `ws://0.0.0.0:4500` with capability-token auth.
- The relay currently listens on `0.0.0.0:4510`, accepts no phone-side auth by default through `--phone-auth none`, uses a host-side raw history token through `--history-auth-token-file`, calls local raw history at `ws://127.0.0.1:4500`, and discovers local loopback Codex app-server processes.
- The current default app endpoint is `ws://192.168.50.117:4510`.
- `CODEX_DOCK_HOSTS` can name multiple hosts, and the Swift stores can fan out across configured host endpoints.
- `home` is online in Tailscale at `100.66.11.7`, SSH-able, and has Codex and Node installed, but it has no running Dock service on the expected ports.

## 2.2 What's broken / missing (concrete)

- Service setup is Mac-only and does not install systemd user services on Linux.
- Host IPs and host IDs are still hard-coded around `Amir-M5`.
- There is no single host setup command that can run on each Codex machine.
- There is no generated multi-host app config artifact that the app/runbook can consume cleanly.
- Tailscale is currently a manual endpoint idea, not a clean setup profile.
- The relay lacks a durable upstream reconnect/fail-loud policy.
- Swift live detail can silently lose updates because stream termination is not surfaced strongly enough to the user.
- App-wide connectivity state is split across raw client state, Dock host load state, Hosts manual test state, and detail live state.
- Status/debug output is not enough to tell whether the raw app-server, relay, live loopback discovery, or app endpoint is broken.
- The current Makefile status checks are coupled to one host and one local runtime directory.

## 2.3 Constraints implied by the problem

- The solution must separate host service lifecycle from client endpoint addressing.
- The same service contract must support macOS and Linux with only platform-specific service-manager adapters.
- The app must accept host URLs that are LAN, DNS, Tailscale, or simulator/dev endpoints.
- Robustness work must include both server-side behavior and client-side visibility.
- Setup/debug docs must be good enough that a future host can be added without rereading the implementation.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->

## 3.1 Source ledger

Internal sources read:

- `README.md`: current runbook describes direct `codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file ...`, `rtk make services`, Mac-local `.codex-dock/`, and environment variables for one real host plus a placeholder `home` host.
- `Makefile`: current service lifecycle is launchd-only, defaults `APP_SERVER_HOST ?= 192.168.50.117`, writes `.env`, starts raw app-server on `:4500`, starts Dock relay on `:4510`, and writes LaunchAgent plist files into `.codex-dock/`.
- `scripts/dock-relay.mjs`: current relay is the app-facing Node WebSocket endpoint, merges live/history thread data, proxies/resumes threads upstream, and has `/readyz` and `/healthz`; it does not yet have a complete status/debug/reconnect contract.
- `scripts/dock-relay.test.mjs`: current Node tests cover helper behavior, merge logic, archived list handling, and source markers, not full WebSocket/service robustness.
- `CodexDock/AppServer/AppServerClient.swift`: current Swift JSON-RPC client has connection state internally, request timeouts, and stream continuations, but no public state stream, reconnect loop, or reusable stream lifecycle after disconnect.
- `CodexDock/State/ThreadDetailStore.swift`: current detail store connects once, reads compact history, resumes with `excludeTurns: true`, and observes notification/request streams; stream end is not yet a strong reconnect/error story.
- `CodexDock/State/DockStore.swift`, `CodexDock/State/ArchiveStore.swift`, `CodexDock/State/HostSettingsStore.swift`, `CodexDock/Configuration/DockHostConfiguration.swift`, `CodexDock/Configuration/HostRegistry.swift`: multi-host config and fanout exist, but persisted host setup, service status, and one app-wide connectivity truth are incomplete.
- `CodexDock/Features/Dock/DockView.swift`: root view owns Dock/Archive/Hosts state, but no root-owned app connectivity rollup.
- `CodexDock/Voice/TranscriptionService.swift`: the worktree currently defaults production voice to one-shot relay transcription through `RelayTranscriptionClient`, while `OpenAITranscriptionClient` still exists as a direct side door. The Realtime plan runs before this plan and supersedes the one-shot production contract; multi-host setup should configure/report the final relay-owned Realtime path, not preserve file upload as a fallback.
- `CodexDock/Configuration/DockHostConfiguration.swift`, `RelayBootstrapStore.swift`, and `RelayDiscovery.swift`: the implemented physical path uses optional bearer host config, Bonjour discovery, saved non-secret relay config, and manual URL fallback. Multi-host generated app config must align with that no-secret shape.
- `docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md`: local doc says daemon-managed app-server is Unix-socket-only for control-plane use, while a direct `codex app-server --listen ws://...` listener is needed for network-visible app access.
- `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md`: preceding top-level phase changes Dock loading to typed source queries and counted tab snapshots; host status/fanout code should use that final loader shape.
- `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`: preceding top-level phase owns Swift reconnect/state stream, ThreadDetail rehydrate, AppConnectivityStore, relay upstream failure behavior, `excludeTurns: true`, root lifecycle, and README updates. This multi-host plan consumes and extends those obligations for host setup/status; it does not create a competing app-wide status owner.
- `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`: implemented plan establishes the stricter no-phone-secret boundary. This multi-host plan must preserve it; it is not a future optional pivot.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md`: primary local Codex app-server protocol source.

Runtime facts checked on 2026-05-28:

- Current Mac: `codex-cli 0.135.0-alpha.2`, macOS on `Amir-M5`, Tailscale IPv4 `100.72.74.74`, Tailscale client `1.96.4`, tailscaled `1.96.2`.
- Current Codex daemon on Mac reports managed app-server version `0.132.0` on Unix socket `/Users/aelaguiz/.codex/app-server-control/app-server-control.sock`.
- `home` over SSH: Linux host `amir-server`, Codex at `/home/aelaguiz/.local/bin/codex`, `codex-cli 0.135.0-alpha.2`, Node `v18.19.1`, systemd `255`, Tailscale IPv4 `100.66.11.7`.
- `home` has no daemon socket at `/home/aelaguiz/.codex/app-server-control/app-server-control.sock` and no listener reachable on `100.66.11.7:4500` or `100.66.11.7:4510`.
- `home` already has unrelated Tailscale Serve config for `home.fairy-salmon.ts.net:443` proxying to `http://127.0.0.1:18789`; this plan must not overwrite it.

External/current sources checked:

- Tailscale Serve docs, last validated `2026-01-20`: `https://tailscale.com/docs/features/tailscale-serve`.
- Tailscale MagicDNS docs: `https://tailscale.com/docs/features/magicdns`.
- Tailscale "Connect to devices" docs, last validated `2026-01-05`: `https://tailscale.com/docs/how-to/connect-to-devices`.
- Local installed `tailscale serve --help` on 2026-05-28 for actual CLI shape on this Mac.

## 3.2 Codex app-server facts that constrain the design

- The app-server protocol is JSON-RPC over transports including `stdio`, `unix`, `ws://IP:PORT`, and `off`.
- WebSocket transport is marked experimental/unsupported in the local app-server README. That means the Dock relay should stay small and observable instead of pretending this is a stable production network surface.
- A `ws://IP:PORT` listener also serves `GET /readyz` and `GET /healthz`. This is enough for setup/status checks on the raw app-server.
- WebSocket clients must initialize once per connection, then send `initialized`, before normal JSON-RPC calls.
- Non-loopback websocket listeners require auth. The current setup uses capability token auth and token files.
- The app-server supports `RUST_LOG` and `LOG_FORMAT=json` for stderr tracing. Host services should set these deliberately or document how to enable them.
- Backpressure can return JSON-RPC error `-32001` with message `Server overloaded; retry later.` Clients should treat that as retryable with exponential backoff and jitter.
- `thread/start`, `thread/resume`, and `thread/fork` can return full turns unless `excludeTurns: true` is used. The Swift detail path already uses `excludeTurns: true`; the relay live-resume path must also do this to avoid giant replay frames.

## 3.3 Tailscale facts that constrain the design

- Tailscale assigns devices Tailscale IPs and MagicDNS names, but it does not start the destination service. The service still has to be running on the target machine and port.
- MagicDNS gives each tailnet machine a fully qualified name of the form `machine.tailnet.ts.net`, and often a short machine name through search domains. It is an address source, not an app protocol.
- Tailscale Serve can proxy a local service to other devices in the tailnet and can add identity/capability headers. It requires tailnet HTTPS certificates for HTTPS Serve flows and is separate from Funnel.
- Tailscale Serve is useful if we want the Dock relay bound to loopback and exposed through Tailscale HTTPS/TCP proxying, but it is optional. The baseline must work with a direct `ws://host:4510` or future `wss://host:4510` endpoint on any reachable network.
- Existing Serve config on `home` means setup must be additive and explicit. A "Tailscale profile" may print recommended commands or manage a named service only when asked; it must not call `tailscale serve reset` or replace unrelated entries.
- Therefore: Tailscale support belongs in endpoint-generation and runbook/profile helpers. Swift app code, Node relay protocol, and service lifecycle must only need a URL and auth mode.

## 3.4 Current implementation risks found during research

- Mac-only lifecycle: all service rendering is inline Makefile plist generation; there is no Linux systemd user path.
- Host lock-in: `APP_SERVER_HOST ?= 192.168.50.117`, `CODEX_DOCK_REAL_HOST_ID=Amir-M5`, and default `CODEX_DOCK_HOSTS ?= Amir-M5` make the current path one-machine-first.
- Raw app-server exposure: current direct app-server binds `0.0.0.0:4500`. The target should bind raw app-server to loopback by default when a relay exists on the same host.
- Relay robustness gap: upstream clients are one-shot; upstream close/error is not clearly translated into a client-visible failure/reconnect state.
- Relay debug gap: `/readyz` and `/healthz` only prove the relay process is alive; they do not prove raw app-server history, live loopback discovery, token file readability, or last upstream failure.
- App client robustness gap: `AppServerClient` has internal `state`, but state changes are not observable by stores/UI, and stream continuations finish on disconnect, making automatic reconnect awkward with the current object shape.
- Detail store robustness gap: `ThreadDetailStore.load()` is guarded by `didLoad`, so reconnect/rehydrate needs a deliberate path rather than calling `load()` again.
- App-wide status gap: Dock/Archive/Hosts/detail each has local status language; there is no single root-owned connectivity store that prevents contradictory "host looks fine here, offline there" UI.
- Secret-surface gap: current `.env` can contain host-service secrets such as `OPENAI_API_KEY` for relay-side use, and `app-server-env` can print raw-token file references for host-side tools. The current simulator launch path does not pass `OPENAI_API_KEY` or raw token env into the app, so the remaining gap is separating host-service config from generated app config and keeping that app config non-secret.

## 3.5 Compatibility posture

- Preserve JSON-RPC protocol usage and the existing Swift DTOs.
- Preserve the Dock relay as the app-facing endpoint.
- Preserve `CODEX_DOCK_HOSTS`/per-host env support during transition, but add a generated/importable host registry artifact so multi-host setup is not hand-edited every time.
- Preserve Makefile convenience commands as wrappers if useful, but move service rendering and cross-platform logic into scripts that can be tested.
- Preserve existing host fanout behavior: if one host fails, the other host's rows remain visible.
- Preserve bearer auth support for explicit dev/hardening profiles. The personal physical-iPhone profile uses no phone bearer token and non-secret app config by default; raw/history bearer auth stays host-side in the relay.

## 3.6 Decisions resolved by research

- Use one local service bundle per Codex host: raw app-server plus Dock relay.
- Bind raw app-server to loopback by default and make the Dock relay the normal app-facing boundary.
- Support macOS launchd and Linux systemd user services through generated service files.
- Treat Tailscale IP, MagicDNS, and Serve as optional endpoint/profile choices only.
- Add status/debug surfaces before or alongside client reconnect so failures are explainable.
- Reuse the existing connectivity resilience plan's client/relay robustness decisions inside this broader multi-host plan.

## 3.7 Decision gaps

None at the architecture level. The no-phone-secret physical path is already the baseline: generated physical app config must not include `OPENAI_API_KEY`, raw app-server bearer tokens, or relay bearer tokens. Future choices may add stricter transport profiles such as `wss://` or Tailscale Serve, but they must preserve the same no-phone-secret app boundary.

<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->

## 4.1 Runtime shape today

The current app path is already a useful prototype, but it is not yet a robust multi-host product:

- The iOS app talks JSON-RPC over WebSocket to a configured app-server-like endpoint.
- In normal Dock use, that endpoint should be the Node Dock relay on `:4510`, not the raw Codex app-server on `:4500`.
- The relay talks to:
  - raw Codex app-server history endpoint at `ws://127.0.0.1:4500`;
  - locally discovered live Codex app-server loopback processes;
  - OpenAI transcription only in the modified/uncommitted relay work that is already present in the tree.
- The app has multi-host host IDs and fanout stores, but the service setup only really provisions `Amir-M5`.
- `home` exists as an intended second host but has no running Dock service.

## 4.2 Service lifecycle today

`Makefile` owns service lifecycle. It is convenient but too narrow:

- It generates launchd plists inline.
- It assumes macOS `launchctl`.
- It assumes local repo paths and Mac binary paths:
  - `CODEX_BIN ?= /Users/aelaguiz/.local/bin/codex`;
  - `NODE_BIN ?= /opt/homebrew/bin/node`.
- It uses `.codex-dock/` as runtime directory for token, pid, service files, and logs.
- It starts raw app-server on `ws://0.0.0.0:4500`.
- It starts Dock relay on `0.0.0.0:4510`.
- It writes `.env` with `CODEX_DOCK_HOSTS=Amir-M5` by default and an empty `CODEX_DOCK_HOST_HOME_WS`.

There is no platform-neutral service contract yet. The setup logic is not reusable on Linux without copying and translating it manually.

## 4.3 App configuration today

The app accepts host configuration through environment:

- `CODEX_DOCK_HOSTS`;
- `CODEX_DOCK_HOST_<ID>_WS`;
- `CODEX_DOCK_HOST_<ID>_BEARER_TOKEN`;
- `CODEX_DOCK_HOST_<ID>_BEARER_TOKEN_FILE`;
- `CODEX_DOCK_HOST_<ID>_NAME`;
- legacy/default `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS` and `CODEX_DOCK_APP_SERVER_WS`.

This is enough for simulator runs, but not enough as an operator-friendly multi-machine setup story. The current path still requires manually knowing which endpoint each machine should use and how tokens map to the app.

## 4.4 Relay behavior today

The relay already does the core routing work:

- It accepts WebSocket clients.
- It enforces relay auth when configured.
- It implements JSON-RPC request/response helpers.
- It lists stored history through the raw app-server history endpoint.
- It discovers local loopback live endpoints from process list.
- It merges active/live rows with stored rows.
- It resumes threads upstream and forwards notifications/requests downstream.

The gaps are the reliability/debug story:

- `/readyz` and `/healthz` only say the relay process is alive.
- There is no `/statusz` with raw app-server, token, live discovery, last upstream, or last client error state.
- Upstream connection close/error is not a clear reconnect or client-visible failure contract.
- Pending upstream requests can hang until timeout when upstream is gone.
- Full-turn replay risk remains where relay resume paths omit `excludeTurns: true`.
- Logs are process stdout/stderr, not a deliberate redacted operational event format.

## 4.5 Swift app behavior today

Swift has good protocol structure, but not a robust connection product:

- `AppServerClient` tracks `idle`, `connecting`, `connected`, `offline`, and `error` state internally.
- It does not expose a durable state stream to the UI.
- It finishes notification and server-request streams on disconnect, so the object is not naturally reusable for reconnect.
- It treats late/unmatched responses as fatal. That is reasonable for protocol bugs, but cancelled/timed-out request responses need a less destructive policy during reconnect.
- `ThreadDetailStore` has a one-shot `load()` guarded by `didLoad`.
- Detail observation tasks stop when streams stop, but that termination is not yet converted into reconnecting/error UI.
- Dock and Archive fanout can keep one host visible when another fails, but app-wide connectivity truth is split between stores.

## 4.6 Network behavior today

Today the app can work over any reachable URL in principle, but the repo defaults do not make that obvious:

- Mac defaults use `192.168.50.117`.
- Tailscale IPs exist for `Amir-M5` and `home`, but no service on `home` listens on Dock ports.
- MagicDNS/Serve are not integrated into setup.
- There is no clean declaration that the app only needs a reachable WebSocket URL.

The architecture risk is accidentally making Tailscale the explanation for connectivity. The real product boundary is "a configured endpoint that resolves and connects"; Tailscale is one way to get such an endpoint.

<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->

## 5.1 High-level shape

Each Codex-running machine gets one local Dock host service bundle:

```text
iOS app / simulator
  -> configured host URL, for example ws://home.local:4510 or ws://100.66.11.7:4510
  -> Dock relay on that host
  -> raw Codex app-server on 127.0.0.1:4500
  -> local Codex sessions, live app-server discovery, optional host-owned services
```

The app does not know whether the URL is LAN, MagicDNS, Tailscale IP, Tailscale Serve, or a manual DNS name. It only knows:

- host ID;
- display name;
- WebSocket URL;
- auth mode;
- last known status from app probes.

## 5.2 Host service contract

Introduce a host-service setup contract that can render and manage services on macOS and Linux.

Required host bundle fields:

- `host_id`: stable app host ID, for example `amir_m5` or `home`.
- `host_name`: display name, for example `Amir-M5` or `Home`.
- `runtime_dir`: default `.codex-dock/` under repo or an explicit absolute path.
- `codex_bin`: resolved Codex binary path.
- `node_bin`: resolved Node binary path.
- `raw_app_server_listen`: default `ws://127.0.0.1:4500`.
- `raw_app_server_health`: default `http://127.0.0.1:4500/readyz`.
- `relay_listen_host`: default `0.0.0.0`.
- `relay_port`: default `4510`.
- `relay_history_url`: default `ws://127.0.0.1:4500`.
- `relay_public_ws_url`: generated from chosen network profile or manually supplied.
- `relay_auth_mode`: `none` for the personal physical-iPhone profile, with `bearer` available only as an explicit dev/hardening profile.
- `token_file`: generated once, reused across reruns unless explicitly rotated.
- `logs`: raw app-server stdout/stderr and relay stdout/stderr paths.
- `service_manager`: `launchd` on macOS, `systemd-user` on Linux.

The setup command must support:

- `render`: print/write service files without starting them.
- `install`: write env/service/token files idempotently.
- `start`: load/start raw app-server and relay.
- `stop`: stop both services.
- `restart`: restart both in dependency order.
- `status`: print redacted JSON plus a human summary.
- `logs`: tail relevant logs without printing secrets.
- `doctor`: run local binary, service manager, port, health, and network checks.
- `app-config`: print generated non-secret `CODEX_DOCK_*` env or a JSON host registry that the app/runbook can consume. It must contain only app-facing fields such as `host_id`, `display_name`, relay WebSocket URL, and auth mode; it must not contain `OPENAI_API_KEY`, raw app-server token values, raw app-server token file paths, relay bearer values, audio, transcript text, or provider credentials.

## 5.3 Platform adapters

macOS adapter:

- Render launchd plist files.
- Use `launchctl bootstrap`, `launchctl bootout`, `launchctl kickstart`, and `launchctl print`.
- Use `KeepAlive` for both raw app-server and relay.
- Write stdout/stderr to `.codex-dock/logs/`.
- Preserve Makefile wrappers as convenience commands that call the setup script.

Linux adapter:

- Render systemd user units, likely:
  - `codex-dock-app-server.service`;
  - `codex-dock-relay.service`.
- Use `systemctl --user daemon-reload`, `enable`, `start`, `stop`, `restart`, `status`.
- Use systemd ordering so relay starts after raw app-server, while still making relay report raw-app-server-down clearly if dependency health fails.
- Use `journalctl --user -u ...` or configured file logs for diagnostics.
- Document lingering only if needed for services to survive logout on `home`; setup should detect and report if user services will not stay alive.

## 5.4 Relay robustness contract

The relay becomes the observable app-facing service boundary.

HTTP endpoints:

- `/readyz`: process is accepting HTTP/WebSocket upgrades.
- `/healthz`: process is alive and can read its static config.
- `/statusz`: redacted JSON with:
  - relay version;
  - host ID/name;
  - uptime;
  - listen address;
  - configured history URL;
  - auth mode, without token values;
  - transcription config state, limited to enabled/disabled, model, endpoint host, and key-present boolean;
  - raw app-server last health result;
  - live discovery last result;
  - active downstream connection count;
  - active upstream connection count;
  - last upstream error;
  - last client-facing error;
  - last transcription error, without audio bytes, transcript text, or OpenAI key material;
  - reconnect attempts/next retry where relevant.

WebSocket failure rules:

- If the relay cannot reach raw history for a request, return a JSON-RPC error with a clear message and structured `data` that includes the failing subsystem, for example `{"subsystem":"history","retryable":true}`.
- If an upstream live session closes while a downstream detail view is active, either reconnect/resume with bounded backoff or close the downstream WebSocket with a code/reason that the Swift client can display.
- Consume the final relay-owned Realtime transcription method/status contract from `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`. Do not preserve one-shot `audio/transcribe` as a production app/relay method or fallback. The relay must never echo base64 audio, transcript text, or OpenAI key material in errors/status/logs.
- Do not leave downstream clients in a state where no more messages arrive and no error is visible.
- Use `excludeTurns: true` for relay `thread/resume` when it only needs live subscription.
- Treat app-server `-32001` overload as retryable with exponential backoff and jitter.
- Reject malformed client messages with JSON-RPC errors when possible, then close only if protocol state is unsafe.

Logging rules:

- Emit structured line-oriented JSON or consistently parseable key/value logs.
- Include subsystem, host ID, event name, retry attempt, duration, and redacted endpoint.
- Never print bearer tokens, OpenAI keys, raw audio, transcript text, or full secret-bearing env.
- Setup/status/log commands must preserve that redaction.

## 5.5 Swift robustness contract consumed from Connectivity

The Connectivity plan owns the app-wide Swift reconnect/status contract before this plan starts. Multi-host setup consumes and verifies that contract against generated host services; it does not add a competing reconnect or lifecycle owner.

Required behavior:

- Require the Connectivity plan's `AppServerClient.connectionStates` or equivalent observable lifecycle contract to exist before Multi-host starts, with states like:
  - `idle`;
  - `connecting`;
  - `connected`;
  - `reconnecting(attempt:nextDelay:reason:)`;
  - `offline(reason:)`;
  - `failed(message:retryable:)`.
- Keep request timeout errors visible to callers through the existing Connectivity error vocabulary.
- Verify late responses, reconnect/backoff, explicit close/cancel, and terminal server errors against `Amir-M5` and `home`; do not redefine those policies here.

`ThreadDetailStore` required behavior:

- Require the Connectivity plan's load/resume lifecycle to exist before Multi-host starts.
- Verify stream termination moves detail state to `reconnecting` or `stale(reason)` immediately.
- Verify reconnect re-runs compact read:
  - `thread/read includeTurns:false`;
  - `thread/turns/list limit:10`;
  - `thread/resume excludeTurns:true`.
- Verify composer draft, request cards, and known events survive reconnect unless the server says the thread no longer exists.
- Verify client-visible error text when reconnect is exhausted.

App-wide required behavior:

- Use the `AppConnectivityStore` created by `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`.
- Multi-host only adds host-service config/status inputs and verifies partial-host behavior across generated `Amir-M5` and `home` hosts.
- Aggregate per-host states from host-service probes, Dock/Archive fanout, and live detail sessions through that one store.
- Render one concise indicator or status surface that can say:
  - `Amir-M5 connected`;
  - `Home relay down`;
  - `Home raw app-server down`;
  - `Session reconnecting`;
  - `Auth failed`;
  - `Server overloaded; retrying`.
- Avoid separate stores inventing contradictory wording for the same host failure.

## 5.6 Network profiles

Network profiles are setup/config choices only:

- `manual`: user supplies the exact relay WebSocket URL.
- `lan`: setup suggests a LAN IP or hostname and writes `ws://<address>:4510`.
- `tailscale`: setup reads `tailscale ip -4` and/or known MagicDNS name, then writes `ws://<tailscale-address>:4510` or prints a Tailscale Serve command if explicitly selected.
- `simulator-local`: setup writes `ws://127.0.0.1:4510` or the Mac host path that the simulator can reach.

Profile rules:

- No Swift code imports or shells out to Tailscale.
- No relay code depends on Tailscale.
- No service lifecycle requires Tailscale.
- Tailscale helper commands must be optional and must not overwrite unrelated Serve configuration.
- Docs must show a non-Tailscale route first or side-by-side, so the architecture remains mentally network-agnostic.

## 5.7 App host registry target

The app needs a clean multi-host config path:

- Continue accepting `CODEX_DOCK_HOSTS` env during transition.
- Add generated JSON or env output from setup, for example `.codex-dock/app-hosts.json` and `rtk make app-server-env`.
- Persist/edit host entries in app state if that is already the local pattern; otherwise keep generated env as the MVP and explicitly defer persistent editing.
- Each host row includes last test result and last successful connection time.
- A host with missing/failed service must not erase another host's sessions.

## 5.8 Security posture for this plan

Baseline:

- Raw app-server bound to loopback.
- Relay is the network boundary.
- Phone-to-relay auth mode defaults to `none` for the implemented personal physical-iPhone path.
- Relay bearer auth stays supported for explicit dev/hardening profiles, but it must not be required for physical app config.
- Raw/history app-server bearer auth stays host-side in the relay.
- Status/log output redacts secrets.
- Tokens are generated once with restrictive file permissions.

Allowed explicit profiles:

- Trusted local/no-client-auth profile for the implemented personal physical-iPhone path.
- Bearer-auth relay profile for explicit dev/hardening use where the phone or simulator is intentionally configured with a relay token.
- Tailscale Serve profile, if explicitly chosen, with docs explaining that tailnet ACLs still apply but app architecture does not depend on them.

Not allowed:

- Tailscale as a required app dependency.
- Public Funnel exposure in this plan.
- Exporting OpenAI keys, raw app-server bearer tokens, or relay bearer tokens into generated app config for the physical path.
- Printing tokens or OpenAI keys in setup/status/log output.

## 5.9 Second-pass hardening: failure path and Tailscale boundary

The implementation must be easy to inspect with one question: "What is down?" The answer has to travel through every layer:

```text
raw app-server down
  -> relay /statusz says raw_app_server.status = down
  -> relay JSON-RPC calls fail with subsystem = history or live-upstream
  -> Swift connection/detail state becomes failed, stale, or reconnecting
  -> UI shows the host-specific problem instead of an endless spinner
```

The same rule applies to relay down, auth failure, network unreachable, upstream live-session close, app-server overload, and malformed protocol messages. A retry loop is acceptable only when the UI/status also says retrying and includes enough redacted detail to debug the host.

Tailscale must pass a second inspection question: "If Tailscale is removed, what changes?" The only acceptable answer is:

- the configured host URL changes;
- optional Tailscale profile helper commands are skipped;
- optional Serve docs are irrelevant;
- the app, relay protocol, service manager, reconnect behavior, and status/error model remain the same.

<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->

## 6.1 Files that must change

| Area | File/path | Required change |
| --- | --- | --- |
| Setup script | `scripts/codex-dock-host-service.mjs` or equivalent new script | Add cross-platform render/install/start/stop/restart/status/logs/doctor/app-config commands. Keep platform-specific service-manager code inside adapters. |
| Setup tests | `scripts/codex-dock-host-service.test.mjs` or equivalent | Test launchd render, systemd render, token reuse, redaction, profile URL generation, and status JSON shape without requiring real service managers. |
| Package scripts | `package.json` if present or Node test command path | Ensure Node tests include relay and host-service setup tests. |
| Make wrappers | `Makefile` | Replace inline Mac-only plist generation with calls into setup script, or keep legacy targets as wrappers. Remove hard-coded `192.168.50.117` defaults from the main path. |
| Relay | `scripts/dock-relay.mjs` | Add `/statusz`, structured/redacted logs, upstream close/error policy, bounded reconnect/fail-loud behavior, `excludeTurns: true` in resume paths, retryable overload handling, and client-visible errors. Preserve current list/archive/request behavior. |
| Relay tests | `scripts/dock-relay.test.mjs` | Add tests for `/statusz`, redaction, upstream down JSON-RPC errors, downstream close/error on upstream death, `excludeTurns: true`, and live-row preservation when history sorting would otherwise drop an active row. |
| App-server methods | `CodexDock/AppServer/AppServerMethods.swift` and related DTO files | Do not preserve one-shot `audio/transcribe` as a production surface after Realtime cutover; status/docs must describe the final `audio/transcription/*` Realtime contract or whatever exact method family Realtime lands. Ensure status/error behavior does not fork method naming between Swift and Node. |
| App client | `CodexDock/AppServer/AppServerClient.swift` | Consume the Connectivity plan's state stream/reconnect contract; verify late-response and retryable-overload behavior against generated hosts without redefining the policy here. |
| App transport | `CodexDock/AppServer/AppServerTransport.swift` or current transport file if split later | Consume the Connectivity plan's recreated transport/close-reason behavior and verify it against multi-host service failures. |
| Detail store | `CodexDock/State/ThreadDetailStore.swift` | Consume the Connectivity plan's reconnect/rehydrate lifecycle; verify service restarts and host failures move visible state correctly without adding a second detail lifecycle. |
| Voice/transcription service | `CodexDock/Voice/TranscriptionService.swift` | Consume the Realtime plan's relay-owned transcription contract on the selected configured host path; ensure transcription errors are client-visible without leaking secrets or audio/transcript payloads. |
| Connectivity store | `CodexDock/State/AppConnectivityStore.swift` or equivalent from Connectivity | Add only host-service config/status inputs and multi-host verification; do not create a second root-owned connectivity truth. |
| Dock store | `CodexDock/State/DockStore.swift` | Feed/consume host connectivity state without losing rows from healthy hosts when another host fails. |
| Archive store | `CodexDock/State/ArchiveStore.swift` | Preserve partial success and report per-host failures consistently. |
| Host settings | `CodexDock/State/HostSettingsStore.swift` | Reuse the same probe/status wording and generated config model. Avoid a separate host-status truth. |
| Host config | `CodexDock/Configuration/DockHostConfiguration.swift` | Add/verify support for auth mode, generated config source, stable host IDs, and redacted display. |
| Host registry | `CodexDock/Configuration/HostRegistry.swift` | Read generated app-host config if implemented, while keeping env compatibility. Validate duplicate/missing hosts clearly. |
| Root view | `CodexDock/Features/Dock/DockView.swift` and nearby views | Own/connect the connectivity store and render client-visible host/service errors without adding confusing duplicate indicators. |
| Swift tests | Existing tests under `CodexDockTests/` | Add focused tests for reconnect state, late responses, host registry parsing, connectivity rollup, detail rehydrate, and partial-host failure. |
| README | `README.md` | Rewrite service setup/runbook around per-host bundle, macOS/Linux commands, status/logs/doctor, generated app config, network profiles, and Tailscale as optional profile. |
| Existing plans | `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md` | Do not duplicate implementation authority. Cross-reference or supersede relevant parts from this broader plan once implementation starts. |

## 6.2 Files likely unchanged unless implementation reveals otherwise

| Area | File/path | Reason |
| --- | --- | --- |
| DTOs | `CodexDock/AppServer/*DTO*.swift` | Existing JSON-RPC DTOs should remain compatible. Only add fields if relay/status API is consumed through typed Swift models. |
| Project spec | `project.yml` | Network permissions already exist. Only update if adding new source files requires explicit project listing under current XcodeGen conventions. |
| Info plist | `CodexDock/Info.plist` or generated config | Local network permissions are already present. No Tailscale-specific entitlement should be added. |
| Voice UI | Voice feature view files | Multi-host service setup does not require changing voice UI layout. The service layer still needs the relay/transcription contract above because the worktree already routes transcription through the relay by default. |

## 6.3 New artifacts and generated files

Expected generated artifacts under `.codex-dock/`:

- `host.env`: host-service config inputs, with secrets as file paths where possible. This file is for the host/relay, not for the phone app.
- `app-server.token`: generated token with restrictive permissions.
- `services/`: rendered plist or systemd unit files.
- `logs/`: raw app-server and relay logs.
- `status.json`: optional latest local status snapshot, redacted.
- `app-hosts.json` or `app.env`: generated app host config export with non-secret relay coordinates only.

These artifacts are runtime outputs and should remain ignored unless there is already a repo convention that commits sample files. Any sample config must use fake tokens and example hostnames.

## 6.4 Behavioral contracts that tests must protect

- Setup render for macOS and Linux is deterministic.
- Setup reruns do not rotate tokens by default.
- Setup status never prints token contents.
- Tailscale profile output changes only endpoint config, not app code paths.
- Relay `/statusz` redacts secrets.
- Relay returns a client-visible JSON-RPC error when raw history is down.
- Relay does not silently hold downstream sockets open after upstream death unless an active reconnect attempt is visible.
- Relay `thread/resume` for live subscription uses `excludeTurns: true`.
- Relay-owned transcription never leaks OpenAI keys, base64 audio, or transcript text through status/log/error surfaces.
- Swift reconnect moves UI out of indefinite loading.
- Swift late responses for timed-out/cancelled requests do not crash the whole session.
- Host fanout preserves healthy host rows while another host fails.

## 6.5 Open call-site questions

None. The implementation has choices about exact file names and whether app config is JSON-first or env-first, but the required behavior is fixed enough to implement without more architecture decisions.

<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->

This child plan is active but deferred behind top-level Phases 1-3. Section 7 is the internal execution order only after Agents, Connectivity, and Realtime have met their exit criteria. Do not start cross-platform host-service setup, generated host config, or final two-host proof until the top-level Phase 4 entry conditions are true.

## Phase 0 - Top-Level Prerequisite Check

Goal: confirm Multi-host starts from the final app/relay contracts rather than rebuilding earlier phases.

Checklist:

- Do not start Multi-host until `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md`, `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`, and `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` have landed.
- Required Agents inputs: `DockSessionQuery`, typed origin, scoped load failures, counted tabs, and relay `sourceKinds` filtering.
- Required Connectivity inputs: `AppConnectivityStore`, root lifecycle, `AppServerClient.connectionStates` or equivalent observable reconnect contract, `ThreadDetailStore` compact rehydrate, and relay upstream fail-loud behavior.
- Required Realtime inputs: final relay-owned transcription method/status contract and deletion/rejection of one-shot production `audio/transcribe` fallback.
- If any input is absent, stop and implement that earlier child plan first. Do not adapt this plan to pre-Agents loaders, pre-Connectivity status, or pre-Realtime file upload voice.

Exit evidence:

- Focused readback confirms all prerequisite symbols/behaviors exist.
- Implementation notes name the final Agents, Connectivity, and Realtime contracts being consumed.

## Phase 1 - Host Service Contract And Rendered Setup

Goal: create the cross-platform service contract without changing app behavior yet.

Top-level dependency note: this plan is implemented after the Agents, Connectivity, and Realtime plans. Phase 1 should render the service contract against their final shared APIs: `DockSessionQuery`/scoped load outcomes, `AppConnectivityStore` status vocabulary, and relay-owned Realtime transcription config/status.

Implementation steps:

- Add a host-service setup script, preferably `scripts/codex-dock-host-service.mjs`, with commands:
  - `render`;
  - `install`;
  - `start`;
  - `stop`;
  - `restart`;
  - `status`;
  - `logs`;
  - `doctor`;
  - `app-config`.
- Model shared config once:
  - host ID/name;
  - runtime dir;
  - Codex/Node binaries;
  - raw app-server loopback listen URL;
  - relay listen host/port;
  - relay public URL;
  - host-service auth mode and host-side token file;
  - physical app config export mode, where `phoneAuth=none` is valid and no app-facing token is emitted;
  - network profile;
  - log paths.
- Add macOS launchd renderer.
- Add Linux systemd user renderer.
- Add token generation/reuse with restrictive permissions.
- Add redaction helpers for URLs/env/status.
- Add network profile URL generation:
  - `manual`;
  - `lan`;
  - `tailscale`;
  - `simulator-local`.
- Keep Tailscale profile limited to reading/suggesting addresses. Do not make service install fail when Tailscale is absent unless the user selected the Tailscale profile and asked for generated Tailscale output.
- Add tests for render output, token reuse, redaction, and profile URL generation.

Files touched:

- new `scripts/codex-dock-host-service.mjs`;
- new setup tests;
- `Makefile` wrappers only after the script exists.

Exit evidence:

- `rtk node --check scripts/codex-dock-host-service.mjs`;
- Node tests pass for setup rendering/redaction;
- rendering launchd and systemd service files does not require macOS/Linux service managers to be active;
- generated raw app-server listen defaults to `ws://127.0.0.1:4500`;
- generated relay public URL can be LAN or Tailscale without changing app code.

Stop condition:

- Do not proceed to real service installation until dry-run render and redaction tests pass.

## Phase 2 - Relay Status, Errors, And Upstream Robustness

Goal: make the server side debuggable and fail-loud before relying on app reconnect.

Implementation steps:

- Add relay config fields for host ID/name and status metadata.
- Add `/statusz` redacted JSON.
- Expand `/healthz` semantics to include static config readability while keeping `/readyz` as process-ready.
- Add structured/redacted event logging.
- Add active downstream/upstream counters.
- Track last raw app-server health, last live discovery result, last upstream error, and last client-facing error.
- Use `excludeTurns: true` for relay live `thread/resume`.
- Add client-visible JSON-RPC errors for:
  - history/raw app-server down;
  - live upstream unavailable;
  - auth failure where protocol permits;
  - overload `-32001`;
  - relay-owned transcription failure;
  - malformed requests.
- Add bounded reconnect for upstream live session where practical. Where reconnect cannot safely resume, close the downstream socket with a clear code/reason so Swift can display it.
- Ensure pending upstream requests are rejected promptly on upstream close/error.

Files touched:

- `scripts/dock-relay.mjs`;
- `scripts/dock-relay.test.mjs`.

Exit evidence:

- `rtk node --check scripts/dock-relay.mjs`;
- `rtk npm test` passes relay tests;
- tests prove `/statusz` redacts tokens;
- tests prove raw history down produces a JSON-RPC error, not a hang;
- tests prove upstream close either reconnects visibly or closes downstream visibly;
- tests prove `thread/resume` includes `excludeTurns: true`;
- tests prove final Realtime transcription status/errors are redacted if relay-owned transcription is enabled;
- tests prove live rows are preserved when one source fails or sorting would otherwise hide active state.

Stop condition:

- Do not proceed to app reconnect work until the relay can explain its own failure states through status/logs and client-visible errors.

## Phase 3 - Make Service Setup Real On Mac And Linux

Goal: replace the Mac-only path with the new setup path and prove both host platforms can run it.

Implementation steps:

- Update `Makefile` targets to call the setup script instead of inline service-file generation:
  - `services`;
  - `app-server`;
  - `dock-relay`;
  - `*-status`;
  - `*-stop`;
  - `*-restart`;
  - `app-server-env`.
- Preserve developer convenience target names so existing workflows still work.
- Install/start on `Amir-M5` through launchd.
- Install/start on `home` through systemd user services.
- Ensure setup detects missing service-manager prerequisites and reports them clearly.
- Ensure `home` setup does not overwrite existing Tailscale Serve config.
- Generate app config for both hosts.

Files touched:

- `Makefile`;
- setup script/tests;
- README partial setup notes if commands materially change during this phase.

Exit evidence:

- `Amir-M5` status shows raw app-server ready and relay ready.
- `home` status shows raw app-server ready and relay ready.
- `curl` or equivalent local checks pass:
  - raw app-server `/readyz`;
  - relay `/readyz`;
  - relay `/statusz`.
- Generated app config includes both hosts with non-empty URLs, auth mode, and no token values or host-side token file paths.
- LAN/manual endpoint proof works for at least one host before Tailscale is considered.
- Tailscale endpoint proof may be run as an additional profile, but is not the only proof.

Stop condition:

- Do not change Swift host UX until both service platforms have a status contract the app can consume or at least display consistently.

## Phase 4 - App Host Config And Connectivity Inputs

Goal: make the app consume multi-host setup cleanly through the Connectivity plan's status owner.

Implementation steps:

- Add generated config parsing if the chosen artifact is JSON. If env remains the first implementation, tighten env validation and document it as generated by setup.
- Update `DockHostConfiguration` and `HostRegistry` to support:
  - stable host IDs;
  - display names;
  - auth mode, with no app-facing token source for the physical profile;
  - redacted endpoint display;
  - duplicate/missing host errors.
- Use the `AppConnectivityStore` created by the Connectivity plan; Multi-host only adds host-service status/probe inputs.
- Feed host probe results and store failures into that one connectivity model.
- Update Dock/Archive/Hosts views to use consistent host status language.
- Ensure partial host failures preserve healthy host data.

Files touched:

- `CodexDock/Configuration/DockHostConfiguration.swift`;
- `CodexDock/Configuration/HostRegistry.swift`;
- existing Connectivity-owned `CodexDock/State/*Connectivity*.swift`;
- `CodexDock/State/DockStore.swift`;
- `CodexDock/State/ArchiveStore.swift`;
- `CodexDock/State/HostSettingsStore.swift`;
- `CodexDock/Features/Dock/DockView.swift`;
- Swift tests.

Exit evidence:

- Swift tests pass for generated/env host registry parsing.
- Swift tests pass for duplicate/missing host validation.
- Swift tests pass for partial host failure preserving healthy host rows.
- UI can show host-specific failure text such as `Home relay down` without erasing `Amir-M5` rows.

Stop condition:

- Do not mark client robustness done until indefinite loading states are eliminated for known server/relay failures.

## Phase 5 - Multi-Host Verification Of Swift Reconnect And Detail Rehydration

Goal: prove the Connectivity-owned reconnect and detail rehydrate contracts work against generated host services.

Implementation steps:

- Require the Connectivity plan's `AppServerClient.connectionStates`/reconnect contract to exist before this phase starts.
- Require the Connectivity plan's `ThreadDetailStore` compact rehydrate path to exist before this phase starts.
- Verify generated `Amir-M5` and `home` services drive those existing states correctly.
- Verify app-server overload remains retryable through the Connectivity policy.
- Verify late timed-out/cancelled responses remain non-fatal unless there is evidence of protocol corruption.
- Verify stream end publishes `reconnecting`/`stale` immediately.
- Verify compact read plus `thread/resume excludeTurns:true` runs after reconnect.
- Verify composer draft, events, and request cards are preserved where safe.
- Verify terminal host failures appear through `AppConnectivityStore` without adding another status rollup.

Files touched:

- `CodexDock/AppServer/AppServerClient.swift`;
- transport implementation file if separated;
- `CodexDock/State/ThreadDetailStore.swift`;
- Connectivity-owned store inputs only;
- Swift tests.

Exit evidence:

- Swift tests pass for state stream/reconnect transitions.
- Swift tests pass for stream end causing visible reconnect/stale state.
- Swift tests pass for rehydrate sequence and preserved composer draft.
- Swift tests pass for late timed-out/cancelled response handling.
- A manual relay restart while detail view is open produces visible reconnect/recovered or visible failed state, not a permanent spinner.

## Phase 6 - Runbook, Real Two-Host Smoke, And Cleanup

Goal: make the work operable from the repo without hidden knowledge.

Implementation steps:

- Rewrite README service setup around:
  - per-host bundle;
  - macOS install/start/status/logs;
  - Linux install/start/status/logs;
  - app config export/import;
  - LAN/manual URL profile;
  - Tailscale IP/MagicDNS profile;
  - optional Tailscale Serve note without making it baseline;
  - common failure debugging.
- Add exact examples for `Amir-M5` and `home`.
- Add a "What if Tailscale is off?" section that says to use LAN/DNS/manual URL and the same service bundle.
- Run final verification commands.
- Remove stale hard-coded IP docs where they would mislead future work.
- Leave unrelated untracked/modified files untouched unless they belong to this plan's implementation.

Exit evidence:

- `rtk swift test` passes.
- `rtk node --check scripts/dock-relay.mjs` passes.
- `rtk node --check scripts/codex-dock-host-service.mjs` passes, if that script name is used.
- `rtk npm test` passes.
- `Amir-M5` service status passes.
- `home` service status passes.
- App launches with both hosts configured.
- One host failure is visible and does not hide the healthy host.
- Tailscale profile works when Tailscale is available, but the documented non-Tailscale profile also works.

## Implementation Order Summary

This is the internal order after top-level Phase 4 entry conditions are true. It does not authorize starting Multi-host before Agents, Connectivity, and Realtime have landed.

1. Build/test setup rendering first.
2. Harden relay status and error propagation second.
3. Replace Mac-only service lifecycle and install both hosts third.
4. Wire app host config and app-wide connectivity fourth.
5. Verify Connectivity-owned Swift reconnect/detail rehydrate against generated hosts fifth.
6. Finish README and real smoke tests sixth.

This order keeps each phase testable. It also prevents a false sense of robustness: reconnect UI is only useful after the server and relay can clearly say what failed.

<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. Prefer existing tests, service health checks, and real host smoke tests. Verification must prove that the host service contract works on both macOS and Linux, that endpoint configuration is network-agnostic, and that failures become visible to users and operators.

## 8.1 Unit tests (contracts)

- Swift app-server lifecycle and connectivity state tests.
- Swift host registry/config parsing and persistence tests.
- Swift app-wide connectivity rollup tests.
- Node relay request, health, status, upstream failure, and log-redaction tests.

## 8.2 Integration tests (flows)

- In-process relay tests using Node `node:test`.
- Setup script dry-run/render tests for macOS launchd and Linux systemd service files.
- Host service status command checks against local endpoints.

## 8.3 E2E / device tests (realistic)

- `Amir-M5` service install/start/status.
- `home` service install/start/status over SSH.
- App launch against both configured hosts.
- One network profile using LAN or manual IP.
- One network profile using Tailscale IP or MagicDNS when available.
- Manual interruption/recovery check for relay/raw app-server failure.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Do not add a feature flag. Replace the Mac-only service path with a host-service setup path that still supports the current Mac. Bring `Amir-M5` up first, then `home`, then update app config and run the two-host app proof.

## 9.2 Telemetry changes

No external telemetry. Add local operational visibility only:

- service status JSON;
- relay `/statusz` JSON;
- redacted env/config summary;
- last startup time;
- last raw app-server health result;
- last upstream/live discovery result;
- last client-facing relay error;
- retry attempt and next retry time where reconnect is active.

## 9.3 Operational runbook

README must explain:

- what runs on each Codex host;
- how to install/start/status/stop/restart host services;
- where service files, env, tokens, logs, and generated app config live;
- how to configure LAN/manual endpoints;
- how to configure Tailscale endpoints without making Tailscale required;
- how to debug raw app-server down, relay down, upstream live-session down, auth failure, and client unreachable states.

<!-- arch_skill:block:consistency_pass:start -->

# Consistency Pass - 2026-05-28

- Decision-complete: yes
- Unresolved decisions: none
- Decision: proceed to implement? yes

Checks performed:

- North Star vs phases: aligned. The phases install the same service bundle on `Amir-M5` and `home`, then prove app behavior against both.
- Tailscale boundary: aligned. Sections 0, 3, 5, 6, 7, 8, and 9 treat Tailscale as a URL/profile helper only. No Swift, Node relay, or service lifecycle requirement depends on Tailscale APIs.
- Server robustness: aligned. Relay `/statusz`, structured logs, upstream reconnect/fail-loud behavior, and client-visible JSON-RPC errors are required before app reconnect work is considered done.
- Client robustness: aligned. Swift connection-state observation, reconnect/backoff, detail rehydration, and app-wide connectivity rollup are required so users are not stuck waiting silently.
- Cross-platform setup: aligned. Platform differences live in setup renderers/adapters for launchd and systemd user services, not in app networking behavior.
- Security/redaction: aligned. Raw app-server binds loopback by default, relay is the network boundary, bearer auth remains supported, and status/log commands must redact secrets.
- Verification: aligned. The plan requires unit tests, script render tests, relay tests, real host health checks, and both non-Tailscale and optional Tailscale endpoint proof.

Implementation may choose exact script and generated config filenames, but it may not change the behavioral contract without updating this plan and recording a new decision.

<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Intent-derived: active multi-host setup plan

Blocker: A new ArchStep plan normally starts as draft until North Star confirmation, but the user directly asked for a new ArcStep auto-plan and clarified the scope in the same goal thread.

Consulted: current user objective, robustness follow-up, and Tailscale clarification.

Intent says: the app should work across the Mac and home server, setup should be repeatable on each device, Tailscale should be supported neatly but not built into core architecture, and robustness/debug visibility are in scope.

Decision: seed this doc as `status: active` and proceed through auto-plan receipts without asking a separate North Star confirmation question.

Consequences: the plan treats Tailscale as a supported endpoint profile only. If implementation discovers a real product fork, it must be recorded as a decision gap rather than silently choosing a narrower behavior.

## 2026-05-28 - Intent-derived: Tailscale is a network profile, not architecture

Blocker: The initial objective mentioned serving over Tailscale, which could be interpreted as making Tailscale a hard dependency.

Consulted: user clarification on 2026-05-28 and Section 0 scope.

Intent says: the app should work without Tailscale; Tailscale should be easy to configure, not fundamental.

Decision: the core architecture is per-host Dock relay endpoints. Tailscale is documented and configured as one supported address source, alongside LAN/DNS/manual endpoints.

Consequences: no Swift, Node, or setup lifecycle code may require Tailscale APIs. Setup may include optional helpers that read `tailscale ip -4`, MagicDNS names, or `tailscale status` to generate config when the user chooses that profile.
