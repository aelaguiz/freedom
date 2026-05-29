---
title: "Codex Dock - Host+Port Client Config And Tailscale Ops Separation - Architecture Plan"
date: 2026-05-28
status: complete
fallback_policy: forbidden
owners: [amir]
reviewers: [amir]
doc_type: architectural_change
supersedes_conflicting_direction:
  - docs/CODEX_DOCK_EASY_HOST_SETUP_AND_SERVING_2026-05-28.md
  - docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md
  - README.md Tailscale profile wording
related:
  - docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28_IMPLEMENTATION_LOG.md
  - docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28_THERMONUCLEAR_REVIEW.md
  - README.md
  - Makefile
  - project.yml
  - Package.swift
  - package.json
  - CodexDock/Configuration/DockHostConfiguration.swift
  - CodexDock/Configuration/HostRegistry.swift
  - CodexDock/Configuration/RelayBootstrapStore.swift
  - CodexDock/Configuration/RelayDiscovery.swift
  - CodexDock/State/HostSettingsStore.swift
  - CodexDock/State/DockStore.swift
  - CodexDock/Features/Hosts/HostsView.swift
  - CodexDock/AppServer/AppServerClient.swift
  - scripts/codex-dock-host-service.mjs
  - scripts/codex-dock-host-service-env.mjs
  - scripts/dock-relay.mjs
  - scripts/dock-relay-bonjour.mjs
  - CodexDockTests/DockConfigurationTests.swift
  - CodexDockTests/DockStoreTests.swift
  - CodexDockTests/AppServerClientTests.swift
  - scripts/codex-dock-host-service.test.mjs
---

# TL;DR

Codex Dock currently mixes two different jobs: iPhone relay connection config and Tailscale operating procedure. This plan turns the app-facing config into plain `host` + `port`, while Tailscale becomes only a way an operator can make a host reachable.

The target is deliberately small: the app stores relay endpoints, computes `ws://<host>:<port>` only at the transport boundary, persists multiple endpoints, and never receives tokens, auth modes, URLs, network profiles, or Tailscale-specific settings.

Implementation was completed on 2026-05-28 from this architecture plan. The
worklog is
`docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28_IMPLEMENTATION_LOG.md`.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-28
Verdict (code): COMPLETE
Manual QA: pending (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- Physical iPhone proof remains deferred manual QA unless explicitly requested.
- Remote `home` tailnet proof was not required for this local code-completeness audit; current code and generated config emit endpoint values only.

Current evidence:

- `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28.md` - `READY next=implement-loop`
- `rtk npm test` - 51 relay tests and 21 host-service tests passed.
- `rtk swift test --filter DockConfigurationTests` - 23 tests passed.
- `rtk swift test --filter DockStoreTests` - 27 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests` - 51 tests passed.
- `rtk swift test --filter AppConnectivityStoreTests` - 11 tests passed.
- `rtk swift test --filter AppServerClientTests` - 43 tests executed, 5 expected skips, 0 failures.
- `rtk swift test` - 200 tests executed, 5 expected skips, 0 failures.
- `rtk make app-server-status` - service bundle status `ready`, app endpoint `{host: "192.168.50.117", port: 4510}`.
- `rtk make dock-relay-status` - service bundle status `ready`, app endpoint `{host: "192.168.50.117", port: 4510}`.
- `rtk make app-server-env` - app-facing output begins with `CODEX_DOCK_HOSTS=192.168.50.117:4510`; URL/token exports are test-only transport smoke helpers.
- `.codex-dock/host.env` - contains only `CODEX_DOCK_HOSTS=192.168.50.117:4510`.
- `rtk make app SIM='iPhone 17'` - failed because the simulator name matched multiple devices.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` - passed.
<!-- arch_skill:block:implementation_audit:end -->

<!-- arch_skill:block:planning_passes:start -->
planning_passes:
  research: done 2026-05-28
  deep_dive_pass_1: done 2026-05-28
  deep_dive_pass_2: done 2026-05-28
  phase_plan: done 2026-05-28
  consistency_pass: done 2026-05-28
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:2232f9fe925e69c37d9c53809b121cacfa461a707b71abc0528f75a5929ddea3",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T22:48:27Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:bd80b2ed3e7f8c295bec91c740c75cf1eae903037c7956fceef92c26a4e6fe39",
      "completed_at": "2026-05-28T22:48:51Z",
      "doc_hash_after": "sha256:894cdf5776490484d52c3da6485cf76aed5405f25b38e0a0b87b2dc0af3a15f4"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T22:48:56Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:894cdf5776490484d52c3da6485cf76aed5405f25b38e0a0b87b2dc0af3a15f4",
      "completed_at": "2026-05-28T22:50:26Z",
      "doc_hash_after": "sha256:fc65dfa6bdeeb6c637704af61ef3cfb5b536f0de36e8deeff3564cc3df0e2470"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T22:50:30Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:fc65dfa6bdeeb6c637704af61ef3cfb5b536f0de36e8deeff3564cc3df0e2470",
      "completed_at": "2026-05-28T22:51:13Z",
      "doc_hash_after": "sha256:70a0d445d9cff9144d5290b11482e9d6023d1c27ba8e468bad34cd4b8eaf0a01"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T22:51:20Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:70a0d445d9cff9144d5290b11482e9d6023d1c27ba8e468bad34cd4b8eaf0a01",
      "completed_at": "2026-05-28T22:52:21Z",
      "doc_hash_after": "sha256:221bed34a1bc3f0d7466d544c9fbbf435f7837289727ebfe2d3ebf7bfe131198"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T22:52:41Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:221bed34a1bc3f0d7466d544c9fbbf435f7837289727ebfe2d3ebf7bfe131198",
      "completed_at": "2026-05-28T22:59:38Z",
      "doc_hash_after": "sha256:482de20abcb652cabaa3cbff97acbf979dd9cb7b98f7c36dbcb9679d9abbddf9"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

From a clean app install and a clean service setup:

- The iPhone app can add one or more relay endpoints using only `host` and `port`.
- Valid `host` values include LAN IPs, `.local` names, MagicDNS names, full tailnet DNS names, Tailscale IPs, normal DNS names, and bracketed IPv6 literals.
- Valid `port` values are integers in `1...65535`; the normal Dock relay port is `4510`.
- The app computes the relay WebSocket URL internally as `ws://<host>:<port>` at the point where `AppServerClient` is created.
- The app persists the endpoint list and reloads it after a cold start.
- The app can keep using one reachable endpoint when another endpoint is offline.
- The app never asks for, stores, or receives a WebSocket URL, bearer token, auth mode, network profile, Tailscale profile, Tailscale address, or Tailscale setting.
- The Mac and the `home` Linux server can each expose the Dock relay over Tailscale, but that setup lives in documentation and shell commands. It does not change Swift app behavior or app-facing generated config.

Falsifiable failure signs:

- The app still has a "WebSocket URL" field instead of separate `Host` and `Port` fields.
- `DockHostConfiguration` remains the app-facing source of truth with `webSocketURL` or `bearerToken`.
- Generated app env still contains `CODEX_DOCK_HOST_<ID>_AUTH_MODE`, bearer/token fields, URL fields, or Tailscale-specific variables.
- `scripts/codex-dock-host-service.mjs` still supports `HOST_SERVICE_NETWORK_PROFILE=tailscale`, `--tailscale-address`, `TAILSCALE_IP`, `TAILSCALE_ADDRESS`, or `TS_IP` for app config.
- README tells people to enable "Tailscale support" in the client or host service instead of entering the Tailscale-reachable host and port.
- A Tailscale endpoint requires client code other than entering its resolved `host` and `port`.

# 1) Key Design Considerations (what matters most)

The key product decision is separation of concerns. The app should know where to connect. It should not know why that address is reachable.

The key security decision is keeping secrets on the Mac side. `OPENAI_API_KEY`, raw app-server bearer tokens, provider choices, and transcription settings remain relay-side or host-side. The phone path should keep using the Dock relay on `:4510`, not the raw authenticated app-server on `:4500`.

The key compatibility decision is a clean cutover with one-time migration. Existing URL-based app config can be parsed into endpoint records once, but URL/auth-mode/token env should not remain as a permanent app-facing compatibility layer.

The key operations decision is that Tailscale direct connectivity is the default. Tailscale Serve can be documented as an optional operator fallback for making a local relay reachable inside the tailnet, but no repo code should branch on "tailscale".

The key implementation risk is partial conversion. The URL/auth/profile shape is currently spread across Swift config, persistence, UI, Node host-service generation, README examples, and tests. The plan must retire all app-facing URL/auth/profile call sites together.

# 2) Problem Statement (existing architecture + why change)

## 2.1 Existing Architecture

The app today treats a relay as a full WebSocket URL plus optional auth metadata. Environment import, saved manual config, Bonjour discovery, host settings UI, and generated host-service app config all converge into `DockHostConfiguration` records that carry `webSocketURL` and sometimes token or auth-mode concepts.

The Node host-service also knows about network profiles, including a `tailscale` profile. That made sense as a convenience while the relay path was being proven, but it now creates the wrong abstraction: Tailscale looks like a product feature instead of an operator-managed network path.

## 2.2 Why Change

The desired user model is simpler than the current implementation. The person using the app should enter a host and a port. If the host happens to be a Tailscale MagicDNS name or Tailscale IP, that is not a different app mode.

The current shape also expands the phone-side trust surface. Auth modes, bearer/token env names, and full URLs encourage future changes to pass host-side secrets or transport policy into the app. The relay is already the phone endpoint; it should own upstream auth and provider settings.

## 2.3 What Must Be True Afterward

The new architecture must make it hard to reintroduce the old split-brain model. Swift app config, generated app env, persistence, host settings UI, docs, and tests should all say the same thing: app connection config is endpoint-only.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External Ground Truth

Tailscale direct device access:

- Source: <https://tailscale.com/docs/how-to/connect-to-devices>
- Finding: Tailscale assigns devices stable Tailscale IPs and MagicDNS names, but it does not run the destination service. The destination service must already be running.
- Finding: Connecting to a service means selecting the device name or Tailscale IP and the service port.
- Architecture implication: Codex Dock does not need a Tailscale client feature. The app only needs the reachable host and the relay port.

Tailscale MagicDNS:

- Source: <https://tailscale.com/docs/features/magicdns>
- Finding: MagicDNS lets signed-in devices use machine names or full tailnet DNS names instead of raw Tailscale IPs.
- Finding: MagicDNS names are normal host input from the app's point of view.
- Architecture implication: `home`, `home.<tailnet>.ts.net`, and `100.x.y.z` are all just `host` values. The Swift app should not parse tailnet names beyond generic host validation.

Tailscale Serve:

- Source: <https://tailscale.com/docs/features/tailscale-serve>
- Finding: Serve can expose a local service to other devices in the tailnet and can proxy a local port.
- Finding: Serve is an operator command; access control and HTTPS/tailnet setup are managed by Tailscale, not by the destination app.
- Finding: Serve is distinct from Funnel, which exposes publicly. This plan does not use Funnel.
- Architecture implication: `tailscale serve` may appear in README as an optional ops fallback, but no Swift or Node app-config code should branch on Serve or Tailscale.

Apple App Transport Security and local networking:

- Source: <https://developer.apple.com/documentation/Security/preventing-insecure-network-connections>
- Finding: `NSAppTransportSecurity` config controls exceptions such as `NSAllowsLocalNetworking`.
- Current repo evidence: `project.yml` already contains `NSAppTransportSecurity: NSAllowsLocalNetworking: true`.
- Architecture implication: if endpoint-only `ws://<host>:<port>` needs broader iOS transport handling, that is a generic app transport decision in `project.yml`, not a Tailscale endpoint field.

## 3.2 Internal Ground Truth

Runnable command source:

- `Makefile` is the repo command source of truth.
- `rtk make services` starts or reuses the raw app-server and Dock relay.
- The normal phone endpoint is the Dock relay on `:4510`, not the raw authenticated app-server on `:4500`.
- `project.yml` is the XcodeGen source of truth for app target settings and local networking permissions.

Swift app config today:

- `CodexDock/Configuration/DockHostConfiguration.swift` stores `webSocketURL: URL` and `bearerToken: String?`.
- `DockHostConfiguration.validatedWebSocketURL(_:)` validates full `ws://` or `wss://` URLs.
- `DockHostConfiguration.fromEnvironment` reads URL and bearer-token inputs such as `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`, `CODEX_DOCK_APP_SERVER_WS`, token env, and token file env.
- `CodexDock/Configuration/HostRegistry.swift` reads scoped per-host env, including `_WS`, `_APP_SERVER_WS`, `_AUTH_MODE`, token, and token-file variants.

Persistence and bootstrap today:

- `LocalRelayConfiguration` stores a `displayName` and `webSocketURL`.
- `FileLocalDockConfigurationStore.defaultFileURL()` stores `relay-config.json` under app support.
- `RelayBootstrapStore.start()` prefers env hosts, then discovery/saved manual URL.
- Discovery/manual bootstrap currently collapses to `HostRegistry(hosts: [host])`, so a discovered relay can replace the full user list.
- `HostSettingsStore.saveHost(...)` saves one `LocalRelayConfiguration`, even when the in-memory registry contains more than one host.

UI and transport today:

- `HostsView` exposes relay ID/name/WebSocket fields.
- `DockStore` creates `AppServerClient(webSocketURL: host.webSocketURL, bearerToken: host.bearerToken)`.
- `AppServerClient` already accepts a URL plus optional bearer token; the endpoint-to-URL conversion can remain outside the JSON-RPC protocol and close to this boundary.

Node service generation today:

- `scripts/codex-dock-host-service.mjs` accepts `--network-profile <lan|manual|tailscale|simulator-local>` and `--tailscale-address`.
- The same script resolves Tailscale address env such as `TAILSCALE_IP`, `TAILSCALE_ADDRESS`, and `TS_IP`.
- `scripts/codex-dock-host-service-env.mjs` treats host `_WS`, `_APP_SERVER_WS`, `_NAME`, and `_AUTH_MODE` as app-safe env.
- `package.json` has `npm test`, `npm run test:relay`, and `npm run test:host-service`.

Tests today:

- `CodexDockTests/DockConfigurationTests.swift` covers URL env, token file loading, auth modes, generated host env, duplicate hosts, bootstrap discovery, manual URL validation, and URL persistence.
- `CodexDockTests/DockStoreTests.swift` covers `HostSettingsStore` save/edit/test behavior, including URL validation.
- `CodexDockTests/AppServerClientTests.swift` has optional real-host smoke tests keyed by URL env.
- `scripts/codex-dock-host-service.test.mjs` covers app-config output, host env generation, network profiles, and Tailscale URL generation.

Docs today:

- `README.md` teaches relay URLs and host-service Tailscale profile examples.
- `docs/CODEX_DOCK_EASY_HOST_SETUP_AND_SERVING_2026-05-28.md` and `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md` contain related host-service setup direction that conflicts with endpoint-only client config where they recommend Tailscale profiles.

## 3.3 Research Decisions

- Resolved: app-facing config is endpoint-only: `host` + `port`.
- Resolved: generated app config must not include tokens, auth modes, URL fields, network profiles, or Tailscale fields.
- Resolved: Tailscale direct connectivity and MagicDNS are operator networking details.
- Resolved: Tailscale Serve is allowed only as an optional ops/runbook fallback.
- Resolved: existing URL persistence gets one-time migration, not a permanent app-facing compatibility layer.
- Unresolved decisions: none.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 Runtime Service Shape

The repo has two Mac-side services:

- Raw Codex app-server: currently documented at `ws://192.168.50.117:4500` for the local service path.
- Dock relay: currently documented at `ws://192.168.50.117:4510` and treated as the normal iPhone endpoint.

The app should connect to the Dock relay. The relay owns upstream auth and forwards to Mac-side app-server/session owners. This architecture is already stated in repo instructions and README, but app config still exposes lower-level URL/auth concepts that make the boundary blurry.

## 4.2 Swift Config Shape

Current source of truth:

- `DockHostConfiguration` has `id`, `displayName`, `webSocketURL`, and `bearerToken`.
- `DockHostConfigurationError` includes bearer-token and auth-mode errors.
- `validatedWebSocketURL(_:)` accepts a full URL with `ws` or `wss`, requires a host, and rejects username/password.
- `fromEnvironment` reads legacy single-host URL env and token env.

Current multi-host shape:

- `HostRegistry.fromEnvironment` reads `CODEX_DOCK_HOSTS`.
- For each host ID, it reads scoped `_WS`, `_APP_SERVER_WS`, `_NAME`, `_AUTH_MODE`, `_BEARER_TOKEN`, `_TOKEN`, `_BEARER_TOKEN_FILE`, and `_TOKEN_FILE`.
- The generated-host path currently sets `_AUTH_MODE=none`, but the app parser still owns the concept.

Problem:

- The client config contract is URL+auth, not endpoint-only.
- "No auth" is still an app config option, which makes future token leakage easier.
- `wss://`, paths, query strings, and URL formatting are app-facing even though the desired product input is host+port.

## 4.3 Persistence Shape

Current persisted manual/discovered config:

- `LocalRelayConfiguration` stores `displayName` and `webSocketURL`.
- `FileLocalDockConfigurationStore` writes `relay-config.json` under application support.
- The store persists only one relay config, not a durable endpoint list.

Problem:

- Multi-host state can exist in memory but is not fully durable.
- Existing persistence serializes the old URL model.
- A one-time migration is required because users may already have `relay-config.json`.

## 4.4 Bootstrap And Discovery Shape

Current bootstrap order:

- `RelayBootstrapStore.start()` tries environment config first.
- It then considers Bonjour discovery and saved manual URL.
- `useConfiguration` saves one config and sets `HostRegistry(hosts: [host])`.

Current discovery:

- `DiscoveredRelay` already has `hostName`, `port`, and `webSocketURL`.
- Bonjour discovery uses `_codexdock._tcp.local.` and resolves host+port through `NetService`.

Problem:

- Discovery already gives the target primitive, but the app converts it back into full URL config.
- Discovery/manual bootstrap can collapse the registry to one host.
- Saved manual config and env config are different sources of truth instead of converging into one endpoint list.

## 4.5 Host Settings UI Shape

Current UI:

- `HostsView` labels the configuration surface as "Relay".
- The edit form uses `Relay ID`, `Name`, and `WebSocket`.
- The store API saves `displayName` and `webSocketURL`.
- Invalid credential URLs are rejected today, which is useful but will become a host validation test instead.

Problem:

- The UI asks users to understand WebSocket URL syntax.
- It exposes ID/name concepts that are not part of the desired connection contract.
- It does not model "enter host and port" as the primary path.

## 4.6 Transport And Multi-Host Runtime Shape

Current transport boundary:

- `DockStore` calls `AppServerDockClient.withClient(for:)`.
- That helper constructs `AppServerClient(webSocketURL: host.webSocketURL, bearerToken: host.bearerToken)`.
- `AppServerClient` itself is a JSON-RPC/WebSocket transport client and should continue accepting a URL.
- `ThreadDetailStore` also constructs app-server clients from selected host config.
- `RelayRealtimeTranscriptionClient` uses the selected host's `webSocketURL` and `bearerToken` for relay-backed transcription sessions.
- App connectivity/status support tests and projections build `DockHostConfiguration` fixtures directly.

Current multi-host behavior:

- `DockStore` can fan out across host records and represent per-host errors.
- One host failure does not need to block other hosts if the registry is built correctly.

Problem:

- The right transport boundary already exists, but the URL is stored too early.
- The plan should keep URL construction near `AppServerClient`, not push endpoint parsing into JSON-RPC request code.
- Endpoint conversion must update every selected-host consumer, not just the Dock list surface.

## 4.7 Node Host-Service Shape

Current host-service app-config generation:

- `scripts/codex-dock-host-service.mjs` emits JSON app config with `webSocketURL` and `authMode`.
- It emits env app config with `CODEX_DOCK_HOSTS`, `CODEX_DOCK_HOST_<ID>_WS`, `CODEX_DOCK_HOST_<ID>_NAME`, and `CODEX_DOCK_HOST_<ID>_AUTH_MODE`.
- It accepts `--network-profile <lan|manual|tailscale|simulator-local>`.
- It accepts `--tailscale-address`.
- Its relay URL resolution has a `tailscale` branch and Tailscale env fallback names.

Current env writer:

- `scripts/codex-dock-host-service-env.mjs` classifies host `_WS`, `_APP_SERVER_WS`, `_NAME`, and `_AUTH_MODE` as app-safe.
- It writes app-safe config and service-only config separately.

Problem:

- Node generation is the most visible place where Tailscale became a product/config profile.
- The generated app config still serializes URLs and auth modes.
- App-safe env includes settings the app should not know.

## 4.8 Docs And Tests Shape

Current docs:

- README explains service setup, relay status, simulator launch, and device paths.
- README currently includes LAN-or-Tailscale URL examples and Linux `home` Tailscale profile setup.
- Related docs from 2026-05-28 include conflicting Tailscale-profile direction.

Current tests:

- Swift config tests assert URL env, token files, auth modes, generated no-auth host env, duplicate IDs, invalid auth mode, bootstrap discovery/saved URL, manual URL validation, and file store URL persistence.
- Dock store tests assert host settings save/edit/test behavior through URL config.
- App-server client tests use URL env for optional real-host smoke tests.
- Node host-service tests assert app-config URL/auth shape and Tailscale network profile behavior.

Problem:

- The test suite currently protects the old contract.
- Docs and tests must change in the same implementation, otherwise future agents will rebuild the wrong abstraction.
- Several historical docs under `docs/epic/**` and audit/worklog sidecars mention the old URL env contract as passive history. Those should not be rewritten broadly unless the implementation touches them for active runbook correctness.

## 4.9 As-Is Summary

The current code can connect to the right service, but it makes the wrong thing configurable. The correct architecture is not "add better Tailscale support"; it is "remove network-specific support from app config and make every reachable relay look like host+port."

## 4.10 Deep-Dive Pass 2 Additions

The second sweep found extra non-obvious consumers beyond the initial config/UI/service surfaces:

- `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` depends on `host.webSocketURL` and `host.bearerToken`.
- `CodexDock/State/ThreadDetailStore.swift` constructs clients from host URL config.
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift` renders discovered relay URLs.
- `CodexDock/Features/Dock/DockView.swift` contains preview URL host fixtures.
- `CodexDockTests/DockStoreScopeTests.swift`, `CodexDockTests/AppConnectivityStoreTests.swift`, `CodexDockTests/DockStoreTestsProjection.swift`, and `CodexDockTests/ThreadDetailStoreTestSupport.swift` create URL-backed host fixtures.

These are required implementation surfaces. Leaving them on the old model would either fail compilation or preserve a shadow URL/auth contract.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 Canonical App Model

Introduce one canonical endpoint model for app-facing relay config:

```swift
public struct DockRelayEndpoint: Equatable, Sendable, Identifiable, Codable {
    public let host: String
    public let port: Int

    public var id: String { serializedEndpoint }
    public var serializedEndpoint: String { /* host:port, bracketed IPv6 when needed */ }
}
```

Names can follow repo style during implementation, but the model must not grow fields for:

- scheme
- full URL
- URL path
- query string
- fragment
- username/password
- bearer token
- auth mode
- network profile
- Tailscale profile
- Tailscale address
- Tailscale Serve state

The model may expose computed helpers:

- `displayEndpoint`: human-readable `host:port`, with IPv6 bracketed when rendered.
- `webSocketURL`: computed `ws://<host>:<port>` for the transport boundary only.
- `normalizedHost`: canonical host token used for identity and persistence.

## 5.2 Endpoint Validation

Validation rules:

- Trim leading/trailing whitespace.
- Reject empty host.
- Reject any host containing a scheme marker such as `://`.
- Reject slash path, query, fragment, username/password, and whitespace.
- Accept DNS names, `.local` names, MagicDNS machine names, full tailnet DNS names, IPv4 literals, and IPv6 literals.
- Accept bracketed IPv6 input such as `[fd7a:115c:a1e0::1]`.
- Store IPv6 internally in one canonical form and render it bracketed when serialized with a port.
- Reject port values outside `1...65535`.
- Reject missing ports in generated endpoint lists.

Implementation guidance:

- Prefer `URLComponents` only for building the final WebSocket URL.
- Do not validate host by requiring a public DNS suffix; local and tailnet names are valid.
- Do not add Tailscale-specific host parsing.
- Keep validation error messages plain: invalid host, invalid port, or invalid endpoint.

## 5.3 Canonical Persistence

Replace the single URL config store with an endpoint-list store:

```swift
public struct PersistedRelayEndpoint: Codable, Equatable, Sendable {
    public let host: String
    public let port: Int
}

public struct LocalRelayEndpointList: Codable, Equatable, Sendable {
    public let endpoints: [PersistedRelayEndpoint]
}
```

Persistence requirements:

- Store all user endpoints, not just the last edited relay.
- Preserve endpoint order.
- Deduplicate by normalized endpoint key.
- Persist only host+port.
- Do not persist display names, URLs, auth modes, bearer tokens, network profiles, or Tailscale fields.
- Implement one-time migration from existing `relay-config.json` by parsing the saved URL host and explicit port.
- Migrate only legacy `ws://` URLs with an explicit port and no username/password, path, query, or fragment.
- Reject legacy `wss://` config with a visible migration error. Do not silently convert `wss://host:443` to `ws://host:443`.
- Reject legacy URLs with missing ports. The new app config is explicit host+port, not scheme-default ports.
- Leave the legacy file untouched when migration fails so the failure can be diagnosed.
- After successful migration, future writes must use the new endpoint-list shape.

## 5.4 Canonical Environment / Generated App Config

Generated app config should be endpoint-only:

```text
CODEX_DOCK_HOSTS=192.168.50.117:4510,home:4510,home.example.ts.net:4510,100.66.11.7:4510
```

For IPv6, serialize endpoints with brackets:

```text
CODEX_DOCK_HOSTS=[fd7a:115c:a1e0::1]:4510
```

Remove app-facing support for:

- `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`
- `CODEX_DOCK_APP_SERVER_WS`
- `CODEX_DOCK_APP_SERVER_BEARER_TOKEN`
- `CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE`
- `CODEX_DOCK_HOST_<ID>_WS`
- `CODEX_DOCK_HOST_<ID>_APP_SERVER_WS`
- `CODEX_DOCK_HOST_<ID>_AUTH_MODE`
- `CODEX_DOCK_HOST_<ID>_BEARER_TOKEN`
- `CODEX_DOCK_HOST_<ID>_TOKEN`
- token-file variants
- app-facing `CODEX_DOCK_HOST_<ID>_NAME`

The implementation may keep internal helper names while transitioning tests, but the public app env contract after the phase is a comma-separated endpoint list only.

## 5.5 Registry And Bootstrap

The registry should represent endpoints, not URL/auth host configs.

Required behavior:

- Load endpoint list from generated env.
- Load endpoint list from persisted local config.
- Upsert Bonjour-discovered endpoints into the same list.
- Preserve existing user endpoints when a new relay is discovered.
- Preserve multi-host runtime behavior and per-host offline/error UI.
- Build `AppServerClient` inputs by converting an endpoint to `ws://<host>:<port>` at the transport boundary.

The current `HostRegistry` name may remain if that reduces churn, but its stored values must become endpoint-only. If a rename is cheap and improves clarity, use a name such as `RelayEndpointRegistry`.

## 5.6 Host Settings UI

The Hosts screen should become an endpoint editor.

Required UI fields:

- `Host`
- `Port`

Required UI actions:

- Add endpoint
- Edit endpoint
- Remove endpoint
- Test endpoint

Required UI behavior:

- Display endpoints as `host:port`.
- Show validation errors for invalid host or port.
- Keep `Test` behavior attached to the selected endpoint.
- Do not expose relay ID, auth mode, token, URL, network profile, or Tailscale controls.
- If the UI needs a stable identity for SwiftUI lists, use the normalized endpoint key internally.

## 5.7 Node Host-Service / Makefile Contract

The host service should emit endpoint-only app config.

Required behavior:

- Keep host-side secrets in service env only.
- Keep `OPENAI_API_KEY`, raw app-server bearer token, and provider settings off the phone.
- Remove `tailscale` from `HOST_SERVICE_NETWORK_PROFILE`.
- Remove `--tailscale-address`.
- Remove Tailscale env fallback names from app-config resolution.
- Replace generated app URL/auth output with `CODEX_DOCK_HOSTS=<endpoint-list>`.
- Use a generic advertised host and advertised port when producing app config.

Acceptable generic inputs:

- `APP_SERVER_HOST` may remain if changing it creates unnecessary churn, but docs must explain it as the advertised host for local service examples, not as a network profile.
- A clearer `DOCK_RELAY_PUBLIC_HOST` or `DOCK_RELAY_ADVERTISED_HOST` may be introduced if the implementation can update Makefile/docs/tests in one pass.

Forbidden inputs:

- `HOST_SERVICE_NETWORK_PROFILE=tailscale`
- `--tailscale-address`
- `TAILSCALE_IP`
- `TAILSCALE_ADDRESS`
- `TS_IP`
- any app-config field named `webSocketURL` or `authMode`

## 5.8 Tailscale Ops Boundary

Documentation should present Tailscale as an operator setup path:

1. Install/sign in to Tailscale on the phone and target machine.
2. Confirm the target machine can be reached by MagicDNS name or Tailscale IP.
3. Confirm the Dock relay is running on port `4510`.
4. In Codex Dock, enter the host and port.

Direct tailnet access is the default path. `tailscale serve` is optional fallback documentation only, for cases where the operator chooses to proxy a local service within the tailnet.

The app must not know whether the entered host is LAN, Bonjour, MagicDNS, full tailnet DNS, Tailscale IP, or any other reachable DNS/IP host.

## 5.9 Security Boundary

The phone receives no OpenAI key, raw app-server bearer token, or relay upstream token.

The relay remains the trust boundary for:

- upstream raw app-server auth
- OpenAI Realtime settings
- audio/transcript redaction
- JSON-RPC forwarding
- host-side session ownership

The app remains responsible only for:

- storing local endpoint list
- connecting to the selected relay endpoint
- showing per-endpoint status and errors

## 5.10 Compatibility Boundary

Compatibility is migration, not permanent dual contract.

Allowed:

- Parse old saved `relay-config.json` URL once into host+port.
- Update tests to assert migration from old saved URL.
- Mention old env vars in README only as removed/deprecated if needed for cleanup notes.

Not allowed:

- Continue accepting old URL/auth env as normal app config.
- Keep Tailscale profile support with a different name.
- Keep auth-mode app config with a default value.
- Keep URL fields in generated app JSON/env.

## 5.11 Selected-Host Consumer Boundary

Every feature that receives a selected host should receive endpoint-only host config.

Required behavior:

- Dock list loading converts endpoint to URL at client construction.
- Thread detail loading converts endpoint to URL at client construction.
- Relay-backed transcription converts endpoint to URL at client construction.
- Logging uses redacted endpoint display derived from host+port.
- Status and error models key by normalized endpoint ID.
- Tests and previews create endpoint fixtures, not URL fixtures.

This keeps `AppServerClient` as the WebSocket transport owner while preventing feature stores from treating URL/auth config as product state.

## 5.12 Historical Docs Boundary

Active docs and current runbooks must be corrected. Historical plans, audits, and worklogs should not be mass-rewritten just to remove old terms.

Required docs distinction:

- Rewrite `README.md` and active setup docs that future agents or users will follow.
- Mark superseded current plans when they recommend Tailscale profiles or URL/auth app config.
- Leave dated worklogs and old epic phase artifacts as history unless they are linked as active instructions.
- Do not use broad docs search as a blocking proof gate; use it to find active docs that need correction.

## 5.13 Endpoint Identity And Display

Endpoint identity must not preserve the old display-name/config-ID layer.

Required behavior:

- Endpoint ID is the normalized serialized endpoint.
- Display text is derived from `host:port`.
- `displayName` is removed from app config or becomes computed-only from the endpoint.
- Session rows, detail headers, archive rows, connectivity rows, logs, and status views use derived endpoint display.
- Composite SwiftUI IDs must not split endpoint IDs on `:` because IPv6 can contain `::`.
- Any user-facing label feature would be a separate future product decision and must not change the connection contract.

## 5.14 Phone-Readable Config Vs Operator Diagnostics

The endpoint-only rule is absolute for phone-readable configuration surfaces:

- generated app env/JSON
- persisted app config
- Host settings UI
- bootstrap manual entry
- Bonjour TXT records
- Swift view models that drive app-visible host config

Those surfaces must not expose auth mode, bearer/token data, URLs, network profiles, scheme fields, or Tailscale state.

Operator-only diagnostics are different:

- relay `/readyz`, `/healthz`, and `/statusz`
- host-service `status`, `doctor`, and dry-run status
- local service env under `.codex-dock/service.env`

Operator diagnostics may continue to show redacted internal relay/upstream state such as `phoneAuth` or raw upstream history URL when needed for debugging, but they must not be consumed by the app as configuration and must not be written into `.codex-dock/host.env`.

Bonjour is not operator-only. It is a phone discovery surface, so `auth=` and `scheme=ws` TXT records should be removed unless a later security plan reintroduces a non-secret discovery field with a specific app use.

## 5.15 Test-Only Transport URL Inputs

The app-facing env contract must become endpoint-only. Tests must not keep teaching `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS` as phone app config.

Allowed:

- Transport-only tests may still instantiate `AppServerClient(webSocketURL:bearerToken:)` directly.
- Optional real-host transport smoke tests may use a clearly test-only URL env name, such as `CODEX_DOCK_TEST_APP_SERVER_WS`, if deriving from `CODEX_DOCK_HOSTS` would obscure the transport behavior under test.
- App-like smoke tests should derive the transport URL from `CODEX_DOCK_HOSTS`.

Not allowed:

- App config tests continuing to read `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`.
- README or active runbooks presenting `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS` as app launch config.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Swift Configuration And Bootstrap

| Path | Current role | Required change |
| --- | --- | --- |
| `CodexDock/Configuration/DockHostConfiguration.swift` | URL/auth host config model and validation | Replace or shrink to endpoint-only model; remove bearer-token/auth-mode app config; add host/port validation and URL computation helper |
| `CodexDock/Configuration/HostRegistry.swift` | Loads URL/auth multi-host env | Load endpoint list from `CODEX_DOCK_HOSTS`; parse comma-separated `host:port`; remove scoped URL/auth/token/name env parsing |
| `CodexDock/Configuration/RelayDiscovery.swift` | Discovery and local URL config store | Keep Bonjour host/port discovery; make `DiscoveredRelay.webSocketURL` computed or remove it; replace `LocalRelayConfiguration` URL store with endpoint-list store; add strict legacy `ws://` URL migration |
| `CodexDock/Configuration/RelayBootstrapStore.swift` | Env/discovery/saved URL/manual bootstrap | Merge env, persisted, and discovered endpoints without replacing the full list; replace `manualURLText`, `connectManually()`, and URL validation with manual host+port entry; publish endpoint registry |
| `CodexDock/State/HostSettingsStore.swift` | Saves/edits/tests URL hosts | Save/edit/remove/test endpoint records; persist full endpoint list; remove displayName/webSocketURL API |
| `CodexDock/State/DockStore.swift` | Uses host registry to create clients and statuses | Convert endpoint to WebSocket URL at `AppServerClient` boundary; keep per-endpoint status/error behavior |
| `CodexDock/State/ThreadDetailStore.swift` | Creates clients for thread read/live/detail flows | Convert selected endpoint to URL at the same boundary; remove bearer-token propagation from app host config |
| `CodexDock/State/AppConnectivityStore.swift` | Stores host config and builds global connectivity view models | Update host/status models to endpoint-only; display derived endpoint text; remove URL/bearer fixture assumptions |
| `CodexDock/State/ArchiveStore.swift` | Uses registry hosts for archive load/restore/connectivity | Update archived-session host references and restore actions to endpoint-only host config |
| `CodexDock/State/SessionRowProjector.swift` | Projects host display name into rows | Replace `displayName` dependence with derived endpoint display |
| `CodexDock/State/DockSessionProjection.swift` | Carries host display text through projections | Replace display-name config with derived endpoint display |
| `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` | Starts relay transcription sessions from selected host URL/auth | Convert endpoint to URL; keep provider/model/delay relay-side only; remove app bearer-token use |
| `CodexDock/AppServer/AppServerClient.swift` | WebSocket JSON-RPC transport | Prefer no behavior change; keep accepting URL; adjust only if tests need a clearer factory boundary |
| `CodexDock/Configuration/RelayBootstrapStore.swift` previews/test helpers | May construct URL hosts | Update fixtures to endpoint-only |

## 6.2 Swift UI

| Path | Current role | Required change |
| --- | --- | --- |
| `CodexDock/Features/Hosts/HostsView.swift` | Shows relay ID/name/WebSocket form | Replace with host/port endpoint form; add remove affordance if missing; keep test/edit behavior |
| `CodexDock/Features/Dock/CodexDockBootstrapView.swift` | Displays discovered relay URL text and manual URL entry | Render discovered endpoint as host+port; replace manual URL field with host+port entry; avoid teaching URL config |
| `CodexDock/Features/Dock/DockView.swift` | Contains preview URL-backed host fixtures | Update previews to endpoint fixtures |
| `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | Shows global/host connectivity status | Display derived endpoint text; remove display-name assumptions |
| `CodexDock/Features/Archive/ArchiveView.swift` | Shows archive host/session rows | Display derived endpoint text; preserve archive behavior |
| `CodexDock/Features/Session/SessionDetailView.swift` | Shows selected host/detail labels | Display derived endpoint text; remove display-name config dependence |
| Any preview/provider code under `CodexDock/Features/Hosts` | Supplies URL host fixtures | Use endpoint fixtures; do not treat previews as production evidence |
| Any status row using display name | User-visible host identity | Display `host:port`; do not require user-entered labels |

## 6.3 Node Host-Service And Relay Scripts

| Path | Current role | Required change |
| --- | --- | --- |
| `scripts/codex-dock-host-service.mjs` | Generates app config; owns network profiles | Remove `tailscale` profile, `--tailscale-address`, Tailscale env fallback, app-config URL/auth fields; emit endpoint-only app config |
| `scripts/codex-dock-host-service-env.mjs` | Splits app-safe and service-only env | Remove app-safe `_WS`, `_APP_SERVER_WS`, `_AUTH_MODE`, `_NAME`; write endpoint-only `CODEX_DOCK_HOSTS`; keep secrets service-only |
| `scripts/codex-dock-host-service.mjs` status/dry-run/doctor output | Emits `appEndpoint.webSocketURL` and `authMode` today | Change app endpoint output to endpoint-shaped host+port or label old URL fields as operator-only; no generated app endpoint output may contain `webSocketURL` or `authMode` |
| `scripts/dock-relay.mjs` | Phone relay and upstream forwarding; `/readyz` and `/healthz` expose auth status | Keep phone endpoint on `:4510` and host-side upstream auth; treat HTTP health as operator diagnostics, not app config; update tests only if output shape changes |
| `scripts/dock-relay-status.mjs` | `/statusz` aggregation includes `history.url` and `auth.phoneAuth` | Keep as operator diagnostics if redacted/non-secret; do not let app consume it as endpoint config |
| `scripts/dock-relay-logger.mjs` | Structured relay diagnostics | No planned behavior change; continue using it for relay diagnostics |
| `scripts/dock-relay-bonjour.mjs` | Bonjour advertisement includes `auth` and `scheme` TXT | Remove `auth=` and `scheme=ws` TXT from phone discovery; Bonjour host+port is enough for endpoint discovery |

## 6.4 Makefile, Project, Package

| Path | Current role | Required change |
| --- | --- | --- |
| `Makefile` | Canonical service/app commands and env generation | Remove Tailscale network-profile examples and app URL/auth env; generate `CODEX_DOCK_HOSTS=<endpoint-list>` for app launch |
| `Makefile` `HOST_SERVICE_ARGS` | Passes `--network-profile` and `--relay-public-url` | Remove Tailscale profile use; decide whether `--relay-public-url`/`DOCK_RELAY_WS` survive only as operator health inputs or are replaced by advertised host+port |
| `Makefile` `app-server-env` | Prints old URL/token-file smoke env | Split from app config; either remove old app-facing names or rename to clearly test-only transport smoke env |
| `project.yml` | XcodeGen source of truth for app target and permissions | No planned change; only touch if endpoint testing proves a generic ATS/local-network setting must change |
| `Package.swift` | SwiftPM target/test definition | No planned change |
| `package.json` | Node test scripts | No planned change unless test file names/scripts change |

## 6.5 Tests

| Path | Current coverage | Required change |
| --- | --- | --- |
| `CodexDockTests/DockConfigurationTests.swift` | URL env, bearer token files, auth modes, generated host env, duplicate IDs, discovery/saved URL | Replace with endpoint parsing, endpoint env loading, invalid host/port, IPv6 serialization, dedupe, legacy URL migration, discovery upsert |
| `CodexDockTests/DockStoreTests.swift` | Host settings save/edit/test through URL config | Update to host/port save/edit/remove/test; assert persistence retains all endpoints |
| `CodexDockTests/DockStoreScopeTests.swift` | URL-backed host fixtures for scoped store behavior | Update fixtures to endpoint-only and keep scope behavior unchanged |
| `CodexDockTests/AppConnectivityStoreTests.swift` | URL-backed host fixtures for connectivity status | Update fixtures and status labels to endpoint display |
| `CodexDockTests/DockStoreTestsProjection.swift` | URL-backed projection fixtures | Update fixtures to endpoint-only |
| `CodexDockTests/ThreadDetailStoreTestSupport.swift` | URL-backed test host support | Update helpers to endpoint-only |
| `CodexDockTests/ThreadDetailStoreLifecycleTests.swift` | Uses `makeDetailHost()` URL fixture | Update fixture to endpoint-only and keep lifecycle behavior unchanged |
| `CodexDockTests/AppServerClientTests.swift` | Transport and optional URL real-host smoke env | App-like smoke tests must derive URL from endpoint env; transport-only tests may use a clearly test-only URL env name; remove `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS` as app config |
| `scripts/codex-dock-host-service.test.mjs` | URL/auth app config and Tailscale network profile | Replace with endpoint-only app config, no app-safe auth/token/name, no Tailscale profile, generic advertised host+port |
| `scripts/dock-relay*.test.mjs` | Relay behavior, Bonjour TXT, status diagnostics | Update Bonjour TXT tests to remove phone-readable auth/scheme; keep or adjust status tests according to operator-diagnostic decision |

## 6.6 Docs

| Path | Current role | Required change |
| --- | --- | --- |
| `README.md` | Product orientation and runbook | Rewrite phone config examples to host+port; remove Tailscale profile as client/service feature; keep Tailscale only in ops section |
| `docs/CODEX_DOCK_EASY_HOST_SETUP_AND_SERVING_2026-05-28.md` | Related host setup plan | Mark superseded where it conflicts or update to endpoint-only/Tailscale-ops boundary |
| `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md` | Related robustness plan | Mark superseded where it conflicts or update to endpoint-only/Tailscale-ops boundary |
| `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` | Active plan references `host.webSocketURL`/`host.bearerToken` | Add supersession note or repair active instruction to endpoint-only selected-host config |
| `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md` | Active plan references URL smoke env | Add supersession note or repair active instruction to endpoint env/test-only URL env |
| `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md` | Active plan references URL-backed bootstrap config | Add supersession note or repair active instruction to endpoint-only bootstrap |
| `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md` | Cross-plan context with older profile wording | Do not rewrite broadly; add a short supersession note only if implementation docs point users here |
| `docs/epic/**` dated worklogs/plans | Passive history | Leave as historical evidence unless a current instruction points to them |
| This plan doc | Authoritative architecture plan | Keep receipts and final `READY next=implement-loop` state |
| `AGENTS.md` | Repo instructions | No planned change |

## 6.7 Local Files And Generated Artifacts

| Path/class | Current role | Required change |
| --- | --- | --- |
| `.env` | User-owned secrets/input | Do not overwrite, normalize, truncate, or refresh |
| `.codex-dock/service.env` | Generated service env | May contain service-only secrets/upstream settings; remove or ignore old app-facing host URL/auth/name keys so they cannot repopulate host env |
| `.codex-dock/host.env` | Generated app launch env | Should contain endpoint-only `CODEX_DOCK_HOSTS` for app launch |
| App support `relay-config.json` | Existing local URL persistence | One-time migrate to endpoint-list shape; do not delete blindly |
| `.build`, `.swiftpm`, `node_modules`, logs | Generated/passive artifacts | Do not edit as implementation source |

## 6.8 Search Terms For Implementation Audit

Use these as review aids after code edits:

- `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`
- `CODEX_DOCK_APP_SERVER_WS`
- `CODEX_DOCK_HOST_.*_WS`
- `CODEX_DOCK_HOST_.*_AUTH_MODE`
- `BEARER_TOKEN`
- `AUTH_MODE`
- `network-profile`
- `tailscale-address`
- `TAILSCALE_IP`
- `TAILSCALE_ADDRESS`
- `TS_IP`
- `webSocketURL`
- `LocalRelayConfiguration`
- `auth=`
- `scheme=ws`
- `appEndpoint`
- `phoneAuth`
- `CODEX_DOCK_PHONE_AUTH`
- `CODEX_DOCK_RELAY_PHONE_AUTH`
- `status.auth`
- `history.url`
- `relay-public-url`
- `DOCK_RELAY_WS`

Do not treat zero matches as the only success condition. Some terms may remain in migration tests, historical docs, or internal transport code with a valid reason.

## 6.9 Pass 2 Sweep Evidence

The second deep-dive used exact search over active source/test/runbook surfaces for:

```text
CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS
CODEX_DOCK_APP_SERVER_WS
CODEX_DOCK_HOST_.*_(WS|AUTH_MODE|BEARER_TOKEN|TOKEN|NAME)
network-profile
tailscale-address
TAILSCALE_IP
TAILSCALE_ADDRESS
TS_IP
webSocketURL
LocalRelayConfiguration
```

Additional required implementation surfaces found by that sweep:

- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/State/AppConnectivityStore.swift`
- `CodexDock/State/ArchiveStore.swift`
- `CodexDock/State/SessionRowProjector.swift`
- `CodexDock/State/DockSessionProjection.swift`
- `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
- `CodexDock/Features/Archive/ArchiveView.swift`
- `CodexDock/Features/Session/SessionDetailView.swift`
- `scripts/dock-relay-bonjour.mjs`
- `scripts/dock-relay-status.mjs`
- `scripts/codex-dock-host-service.mjs` status/dry-run output
- `Makefile` `app-server-env`
- `CodexDockTests/DockStoreScopeTests.swift`
- `CodexDockTests/AppConnectivityStoreTests.swift`
- `CodexDockTests/DockStoreTestsProjection.swift`
- `CodexDockTests/ThreadDetailStoreTestSupport.swift`
- `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`
- `scripts/dock-relay*.test.mjs`

The same sweep confirmed that many old-contract mentions live in dated docs and worklogs. Those mentions are not all implementation blockers; active runbooks and conflicting current plans are the blocker class.

## 6.10 Consistency-Pass Repairs Integrated

The consistency review added these constraints:

- Bonjour TXT is phone-readable discovery config; remove `auth=` and `scheme=ws`.
- Relay HTTP status can remain operator diagnostics if not consumed as app config.
- Host-service `appEndpoint` status/dry-run output must become endpoint-shaped or explicitly operator-only.
- `.codex-dock/service.env` must not be a hidden source that regenerates old phone URL/auth env.
- Manual bootstrap URL entry must become manual host+port entry.
- `DiscoveredRelay.webSocketURL` must be removed or computed, not stored app config.
- Legacy `wss://` saved config migration is rejected rather than silently downgraded to `ws://`.
- App-like real-host tests must use endpoint env; URL env is allowed only for clearly test-only transport smoke.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
Implementation must proceed depth-first. Do not start broad README/UI cleanup before the endpoint model, migration, and tests prove the new contract.

## Phase 1 - Endpoint Model, Parsing, And Transport Boundary

Goal:

Establish the endpoint-only Swift contract and keep URL construction at the WebSocket transport boundary.

Work:

- Replace or shrink `DockHostConfiguration` into an endpoint-only model.
- Add endpoint parsing/validation for host+port.
- Add endpoint serialization for `host:port`, including bracketed IPv6 rendering.
- Add computed WebSocket URL creation using `ws://<host>:<port>`.
- Remove app-facing bearer-token and auth-mode fields from the host model.
- Update `DockStore`, `ThreadDetailStore`, `ArchiveStore`, `AppConnectivityStore`, and `RelayRealtimeTranscriptionClient` to use endpoint-only host config.
- Keep `AppServerClient` itself URL-based unless a small factory helper improves local clarity.
- Replace display-name/config-ID usage with derived endpoint display everywhere selected host state is shown.

Checklist (must all be done):

- [ ] Endpoint model stores `host` and `port` only.
- [ ] Endpoint ID is stable and derived from normalized endpoint serialization.
- [ ] Host validation rejects schemes, paths, query strings, fragments, username/password, whitespace, and empty values.
- [ ] Port validation rejects missing, non-integer, zero, negative, and `>65535` values.
- [ ] DNS, `.local`, MagicDNS, full tailnet DNS, IPv4, and IPv6 inputs are accepted.
- [ ] IPv6 endpoint serialization is unambiguous with brackets.
- [ ] `webSocketURL` is computed, not persisted as app config truth.
- [ ] No app host model field stores bearer token, token file, auth mode, network profile, or Tailscale value.
- [ ] `DockStore` compiles against endpoint-only config.
- [ ] `ThreadDetailStore` compiles against endpoint-only config.
- [ ] `ArchiveStore` compiles against endpoint-only config.
- [ ] `AppConnectivityStore` compiles against endpoint-only config.
- [ ] `RelayRealtimeTranscriptionClient` compiles against endpoint-only config.
- [ ] Logs render redacted endpoint display without needing URL app config.
- [ ] `displayName` is removed or computed from endpoint display, not stored as app config.
- [ ] Composite SwiftUI IDs do not split endpoint IDs on `:`.

Verification (required proof):

- [ ] Run `rtk swift test --filter DockConfigurationTests`.
- [ ] If selected-host consumers are touched, also run the smallest relevant test filters: `rtk swift test --filter DockStoreTests`, `rtk swift test --filter ThreadDetailStoreTests`, `rtk swift test --filter AppConnectivityStoreTests`, or `rtk swift test --filter AppServerClientTests`.
- [ ] Record exact skipped command and blocker if Swift/Xcode tooling is unavailable.

Docs/comments (propagation; only if needed):

- Add code comments only around non-obvious IPv6 serialization or legacy parsing.
- Do not update README in this phase unless a public command changes immediately.

Exit criteria (all required):

- [ ] Swift package compiles for the changed config and selected-host consumers.
- [ ] Endpoint parsing tests cover valid and invalid host/port cases.
- [ ] App host config can no longer carry client bearer/auth-mode fields.
- [ ] URL construction exists only as a computed/boundary behavior.

Rollback:

- Revert this phase's Swift model and direct consumer changes together.
- Do not leave a mixed state where some stores expect endpoints and others expect URL/auth host config.

## Phase 2 - Persistence, Migration, Bootstrap, And Registry Convergence

Goal:

Make endpoint lists durable and make env, saved config, and Bonjour discovery converge without wiping user endpoints.

Work:

- Replace `LocalRelayConfiguration` URL persistence with endpoint-list persistence.
- Add one-time migration from legacy `relay-config.json`.
- Update `FileLocalDockConfigurationStore` or its replacement to load/save endpoint lists.
- Update `HostRegistry` or rename to an endpoint registry.
- Update `RelayBootstrapStore` to load persisted endpoints, env endpoints, and discovered endpoints into the same registry.
- Make Bonjour discovery upsert endpoint records instead of replacing the list.
- Preserve endpoint order and dedupe by normalized endpoint key.

Checklist (must all be done):

- [ ] Persisted local config contains only endpoint records.
- [ ] Existing `ws://host:port` `relay-config.json` URL config migrates to endpoint list.
- [ ] Existing `wss://...` legacy config fails migration visibly and is not silently converted.
- [ ] Legacy URLs without explicit ports fail migration visibly.
- [ ] Failed migration is visible and does not delete the legacy file.
- [ ] Environment endpoint list can seed the registry.
- [ ] Saved endpoint list can seed the registry without env.
- [ ] Bonjour-discovered endpoint can be added without clearing saved endpoints.
- [ ] Duplicate endpoints are deduped consistently across env, saved config, and discovery.
- [ ] Registry exposes enough display data for UI/status without adding labels to app config.
- [ ] Per-endpoint offline/error behavior remains possible.
- [ ] Old URL/auth env parsing is removed from normal app config path.

Verification (required proof):

- [ ] Run `rtk swift test --filter DockConfigurationTests`.
- [ ] Run `rtk swift test --filter DockStoreTests` if host settings/store behavior changes in this phase.
- [ ] Include tests for legacy saved URL migration, env endpoint parsing, duplicate endpoint rejection/dedupe, and discovery upsert.

Docs/comments (propagation; only if needed):

- Add a short migration comment in the persistence code if the legacy JSON branch is not self-explanatory.
- Do not edit `.env`.
- Do not delete app support files as part of tests; use temp stores.

Exit criteria (all required):

- [ ] A user can save two endpoints and both survive reload.
- [ ] A discovered relay does not erase saved endpoints.
- [ ] Existing saved URL config has a tested migration path.
- [ ] Normal app env contract is endpoint-only.

Rollback:

- Restore the previous URL persistence and bootstrap code together.
- If migration code has run locally, keep old files for diagnosis instead of deleting them.

## Phase 3 - Host Settings And Bootstrap UI

Goal:

Make the installed app experience match the endpoint-only model.

Work:

- Replace URL form fields in `HostsView` with `Host` and `Port`.
- Replace manual URL bootstrap state and form fields with `Host` and `Port`.
- Add or preserve Add/Edit/Remove/Test endpoint actions.
- Update bootstrap/discovery views to display host+port instead of WebSocket URL.
- Update previews and local UI fixtures to endpoint-only hosts.
- Keep validation errors plain and actionable.
- Ensure text fits in compact/mobile layouts.

Checklist (must all be done):

- [ ] Hosts UI has no WebSocket URL field.
- [ ] Hosts UI has no relay ID, auth mode, token, network profile, or Tailscale controls.
- [ ] Add endpoint works with host+port.
- [ ] Edit endpoint works with host+port.
- [ ] Remove endpoint works and persists.
- [ ] Test endpoint uses the selected endpoint.
- [ ] Invalid host shows host validation error.
- [ ] Invalid port shows port validation error.
- [ ] Discovery/bootstrap display does not teach URL entry.
- [ ] Manual bootstrap entry no longer uses `manualURLText` or URL validation.
- [ ] Previews compile with endpoint fixtures.

Verification (required proof):

- [ ] Run `rtk swift test --filter DockStoreTests`.
- [ ] If UI/app target compilation is touched beyond SwiftPM-covered files, run `rtk xcodegen generate --spec project.yml` and `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- [ ] Use `rtk make app SIM='iPhone 17'` only if installed-app behavior is materially changed and services are available.

Docs/comments (propagation; only if needed):

- No in-app explanatory copy about "how this feature works"; the UI labels should be enough.
- Comments only for non-obvious validation/state behavior.

Exit criteria (all required):

- [ ] User-facing host config is host+port only.
- [ ] App can add, edit, remove, test, persist, and reload endpoints.
- [ ] No visible Tailscale-specific app concept exists.
- [ ] UI tests or store tests prove invalid URL-style input is rejected.

Rollback:

- Revert UI and host settings store changes together.
- Do not leave UI collecting host+port while store saves URL-only config.

## Phase 4 - Node Host-Service, Generated App Config, And Makefile Cutover

Goal:

Make generated app config and local service commands produce endpoint-only phone config with no Tailscale profile.

Work:

- Update `scripts/codex-dock-host-service.mjs` app config output.
- Update `scripts/codex-dock-host-service-env.mjs` app-safe env filtering/generation.
- Update `Makefile` app/service env generation to use endpoint-only `CODEX_DOCK_HOSTS`.
- Update host-service status/dry-run/doctor app endpoint output to stop exposing URL/auth as app endpoint config.
- Update Bonjour TXT records to stop advertising phone-readable auth/scheme config.
- Remove `HOST_SERVICE_NETWORK_PROFILE=tailscale`.
- Remove `--tailscale-address` and Tailscale env fallback address code.
- Keep service-only secrets in `.codex-dock/service.env`.
- Keep `.codex-dock/host.env` app-safe and endpoint-only.
- Preserve relay status and service lifecycle behavior as operator diagnostics.

Checklist (must all be done):

- [ ] Host-service app JSON emits endpoint-only data or removes JSON app-config if no longer used.
- [ ] Host-service app env emits `CODEX_DOCK_HOSTS=<endpoint-list>`.
- [ ] Generated app env has no `_WS`, `_APP_SERVER_WS`, `_AUTH_MODE`, `_NAME`, token, or bearer fields.
- [ ] Service env may keep host-side secrets but does not push them into host env.
- [ ] Service env removes or ignores old app-facing host URL/auth/name keys so they cannot repopulate host env.
- [ ] `network-profile` no longer includes `tailscale`.
- [ ] `--tailscale-address` is removed from usage, parsing, and tests.
- [ ] `TAILSCALE_IP`, `TAILSCALE_ADDRESS`, and `TS_IP` are removed from app-config resolution.
- [ ] Makefile `app` target injects endpoint-only `SIMCTL_CHILD_CODEX_DOCK_HOSTS`.
- [ ] Makefile `app-server-env` does not present old URL/token env as phone app config.
- [ ] `--relay-public-url`/`DOCK_RELAY_WS` are either replaced by advertised host+port or retained only as operator-health/internal inputs.
- [ ] Host-service status/dry-run output has no `appEndpoint.webSocketURL` or `appEndpoint.authMode`.
- [ ] Bonjour TXT has no `auth=` or `scheme=ws`.
- [ ] Relay `/readyz`, `/healthz`, and `/statusz` are documented/tested as operator diagnostics, not app config sources.
- [ ] Makefile does not overwrite `.env`.
- [ ] Status/doctor commands still work.

Verification (required proof):

- [ ] Run `rtk npm test` unless changes are proven limited enough for `rtk npm run test:host-service`.
- [ ] Run `rtk make app-server-status`.
- [ ] Run `rtk make dock-relay-status`.
- [ ] If app launch env changed, run `rtk make app SIM='iPhone 17'` when simulator/services are available.
- [ ] Record exact skipped commands and blockers if services or simulator are unavailable.

Docs/comments (propagation; only if needed):

- Update command help text and README in the same phase or immediately after; command output must not advertise removed Tailscale options.
- Do not log secrets while debugging env generation.

Exit criteria (all required):

- [ ] Generated app config matches the Swift endpoint parser.
- [ ] Node tests no longer assert URL/auth/Tailscale profile app config.
- [ ] Node tests no longer assert phone-readable Bonjour auth/scheme TXT.
- [ ] Makefile and host-service agree on endpoint serialization.
- [ ] `.codex-dock/host.env` is phone-safe and endpoint-only.

Rollback:

- Revert host-service, env writer, Makefile, and tests together.
- Do not leave Makefile generating a shape Swift no longer accepts.

## Phase 5 - Active Docs And Supersession Cleanup

Goal:

Make the active instructions teach the new boundary and stop future agents from rebuilding Tailscale support in app config.

Work:

- Rewrite README service/app config examples.
- Add a clear Tailscale ops section.
- Mark conflicting current plans as superseded or update their active guidance.
- Leave passive historical worklogs alone.
- Ensure AGENTS instructions remain accurate; update only if service-path instructions become wrong.

Checklist (must all be done):

- [ ] README says app config is host+port.
- [ ] README says phone connects to Dock relay on `:4510`, not raw `:4500`.
- [ ] README removes `HOST_SERVICE_NETWORK_PROFILE=tailscale`.
- [ ] README removes app-facing URL/auth env examples.
- [ ] README documents direct Tailscale reachability as host+port entry.
- [ ] README documents `tailscale serve` only as optional ops fallback, not code support.
- [ ] `docs/CODEX_DOCK_EASY_HOST_SETUP_AND_SERVING_2026-05-28.md` conflict is marked superseded or repaired.
- [ ] `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md` conflict is marked superseded or repaired.
- [ ] `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` conflict is marked superseded or repaired.
- [ ] `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md` conflict is marked superseded or repaired.
- [ ] `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md` conflict is marked superseded or repaired.
- [ ] Historical docs are not broadly churned.

Verification (required proof):

- [ ] Read back changed README sections with `rtk sed -n`.
- [ ] Run targeted `rtk rg` searches for removed active-runbook phrases.
- [ ] Check active-doc search hits for `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`, `host.webSocketURL`, `host.bearerToken`, `HOST_SERVICE_NETWORK_PROFILE=tailscale`, and app-facing `_AUTH_MODE`.
- [ ] Run `rtk git status --short` to list changed files.
- [ ] No app tests are required for docs-only changes in this phase.

Docs/comments (propagation; only if needed):

- This phase is docs propagation.
- Keep wording direct: Tailscale produces a reachable host; the app accepts host+port.

Exit criteria (all required):

- [ ] Active docs no longer instruct URL/auth/profile app config.
- [ ] Active docs no longer present Tailscale as a client or host-service profile.
- [ ] Current conflicting docs are clearly superseded or corrected.

Rollback:

- Revert docs changes only if they misstate the implemented command shape.
- Do not restore removed Tailscale profile instructions after code is cut over.

## Phase 6 - Ops Proof For Mac And `home`

Goal:

Prove that Tailscale setup works as operations output without adding app-specific Tailscale support.

Work:

- On each target machine, run or document the relay service using normal service commands.
- Confirm direct tailnet reachability to relay port `4510` where available.
- If direct access is not available or not desired, document the chosen `tailscale serve` command as an operator-owned fallback.
- Feed the app only host+port endpoints.

Checklist (must all be done):

- [ ] Mac relay reachable on a normal LAN or tailnet host and port.
- [ ] `home` relay reachable on a normal tailnet host/IP and port, if `home` is part of this implementation run.
- [ ] No Swift or Node app-config code checks Tailscale state.
- [ ] Tailscale commands are documented as manual/ops steps.
- [ ] Direct tailnet path is tried before Serve unless the operator explicitly chooses Serve.
- [ ] Serve examples do not imply public Funnel.

Verification (required proof):

- [ ] Run `rtk make services` on the Mac when service disruption is acceptable for the task.
- [ ] Prefer `rtk make app-server-status` and `rtk make dock-relay-status` during normal verification.
- [ ] For `home`, use the documented remote service/status commands if available.
- [ ] Use `curl http://<host>:4510/readyz` or the repo status target to prove relay health where appropriate.
- [ ] If physical phone proof is requested and Mobile MCP reports `WebDriverAgent is not running on device`, stop retrying physical Mobile MCP and record that exact blocker.

Docs/comments (propagation; only if needed):

- Add exact commands that were proven.
- Keep machine-specific values as examples, not hard-coded app behavior.

Exit criteria (all required):

- [ ] The ops proof produces endpoint values, not app config profiles.
- [ ] The app can be configured with those endpoint values.
- [ ] Tailscale remains absent from Swift/Node app-config code.

Rollback:

- Remove or correct only the failing ops instructions.
- Do not reintroduce Tailscale profile code as a workaround.

## Phase 7 - Final Integration And Readiness Audit

Goal:

Prove the whole cutover is coherent and ready for normal use or the next focused fix.

Work:

- Run the smallest complete set of Swift and Node tests touched by the implementation.
- Run generated project checks if project settings changed.
- Launch simulator if app config or UI behavior changed.
- Check active docs and generated env for old app-facing URL/auth/profile contract.
- Record blockers exactly.

Checklist (must all be done):

- [ ] Swift tests covering config/persistence/UI store pass or have exact blocker.
- [ ] Node tests covering host-service config pass or have exact blocker.
- [ ] Generated Xcode project is regenerated if `project.yml` changed.
- [ ] Simulator launch is attempted if installed-app behavior changed and environment supports it.
- [ ] One endpoint offline does not block another endpoint when multi-host behavior is in scope.
- [ ] Active docs match the implemented commands.
- [ ] `.env` remains untouched unless Amir explicitly asked for `.env` changes.
- [ ] `git status --short` is reviewed for final changed-file summary.

Verification (required proof):

- [ ] Start with `rtk swift test --filter DockConfigurationTests`.
- [ ] Run `rtk swift test --filter DockStoreTests` for host settings and persistence changes.
- [ ] Run `rtk swift test --filter ThreadDetailStoreTests` if thread detail/live selected-host behavior changed.
- [ ] Run `rtk swift test --filter AppConnectivityStoreTests` if global connectivity host status changed.
- [ ] Run `rtk swift test --filter AppServerClientTests` if client construction or smoke env changed.
- [ ] Run `rtk npm test` for host-service/relay script changes.
- [ ] Run `rtk xcodegen generate --spec project.yml` and the relevant Xcode build/test if project settings changed.
- [ ] Run `rtk make app SIM='iPhone 17'` when installed-app behavior matters and services/simulator are available.

Docs/comments (propagation; only if needed):

- Final docs should name endpoint-only config once and avoid implementation tutorial text inside the app.
- Any skipped physical-device proof must be reported with the exact blocker.

Exit criteria (all required):

- [ ] The repo has one active app-facing relay config contract: host+port.
- [ ] Tailscale exists only as ops documentation.
- [ ] Tests protect the new endpoint-only contract.
- [ ] Active runbooks and Makefile agree.
- [ ] No required verification failure is hidden.

Rollback:

- Roll back by phase in reverse order.
- If final integration fails because of mixed contracts, revert to the last phase whose tests passed rather than adding compatibility shims.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Verification will be tied to the phase that owns each behavior. The implementation should start with the smallest relevant check and only broaden when the touched surface requires it.

Planned verification families:

- Swift endpoint parsing/config tests: `rtk swift test --filter DockConfigurationTests`
- Dock and host settings behavior: `rtk swift test --filter DockStoreTests`
- App-server client transport boundary behavior when touched: `rtk swift test --filter AppServerClientTests`
- Node host-service and relay config generation: `rtk npm test` or the smallest relevant script-level test
- Generated project checks only if `project.yml`, app permissions, assets, schemes, or installed-app behavior changes
- Manual simulator or physical-phone proof only when implementation reaches installed-app behavior

String searches such as `rtk rg 'tailscale|AUTH_MODE|BEARER_TOKEN|_WS|webSocketURL'` are review aids. They are not proof by themselves because unrelated docs, historical artifacts, and internal transport names may legitimately remain.

Additional review-aid terms for this plan:

- `auth=`
- `scheme=ws`
- `appEndpoint`
- `phoneAuth`
- `status.auth`
- `history.url`
- `relay-public-url`
- `DOCK_RELAY_WS`

# 9) Rollout / Ops / Telemetry

Rollout should be a clean local cutover, not a public compatibility program. This repo is local and repo instructions say to assume the repo is not precious by default.

Operational output after implementation:

- Start services with the normal repo entrypoint: `rtk make services`.
- Confirm the relay is healthy with `rtk make dock-relay-status`.
- For LAN use, enter the LAN host and port `4510`.
- For Tailscale use, first make the target machine reachable on the tailnet, then enter that MagicDNS name, full tailnet DNS name, or Tailscale IP plus port `4510`.
- If direct tailnet port access is blocked or not desired, document an operator-owned `tailscale serve` setup as an optional fallback; the app still receives only host+port.

# 10) Implementation Closeout

Implementation status: complete on 2026-05-28.

Worklog:

- `docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28_IMPLEMENTATION_LOG.md`

Implemented outcomes:

- Swift app-facing relay config is endpoint-only: host + port.
- `DockHostConfiguration` no longer stores bearer tokens, auth mode, or a
  persisted WebSocket URL.
- `ws://<host>:<port>` is computed for transport use only.
- Local persistence stores an endpoint list and migrates supported legacy
  `ws://host:port` saved config.
- Bootstrap merges environment, saved, and discovered endpoints into one
  registry instead of replacing the list.
- Bootstrap, Bonjour discovery, Hosts UI, Dock, Archive, Thread Detail,
  Realtime transcription, and connectivity display use endpoint-derived
  identity/display.
- Host-service generated app env emits only `CODEX_DOCK_HOSTS=<endpoint-list>`.
- Host-service `tailscale` network profile and `--tailscale-address` are
  removed.
- Bonjour TXT no longer exposes phone-readable `auth=` or `scheme=ws`.
- README and active conflicting docs now point to the endpoint-only boundary.

Verification passed:

- `rtk swift test --filter DockConfigurationTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test` - 200 tests, 5 expected skips, 0 failures
- `rtk npm run test:host-service`
- `rtk npm run test:relay`
- `rtk npm test` - 51 relay tests and 21 host-service tests passed
- `rtk make app-server-status`
- `rtk make dock-relay-status`
- `rtk make app-server-env`
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`

Known verification note:

- `rtk make app SIM='iPhone 17'` was attempted first and failed because the
  simulator name matched multiple devices. The rerun with the booted simulator
  ID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` passed.

Active-doc audit note:

- README no longer contains the removed app-facing URL/auth/Tailscale-profile
  examples.
- The related active plans still contain historical old-contract wording in
  their bodies, but each now has an explicit supersession note pointing back to
  this implemented endpoint-only plan.

<!-- arch_skill:block:consistency_pass:start -->
- Reviewers:
  - Explorer 1: Swift/client surfaces.
  - Explorer 2: Node/docs/ops surfaces.
  - Parent integrator: full artifact and stage-gate consistency.
- Scope checked:
  - Swift endpoint model, registry, persistence, discovery, bootstrap, host settings, Dock, thread detail, archive, connectivity, voice, display, and Swift tests.
  - Node host-service, env writer, relay status, Bonjour, Makefile, package tests, README, active docs, generated env, and Tailscale ops boundary.
- Findings integrated:
  - Added strict legacy URL migration rule: migrate only explicit-port `ws://`; reject `wss://` and missing-port legacy URLs.
  - Added endpoint identity/display rules so `displayName` does not remain shadow config.
  - Added AppConnectivity, Archive, projection, bootstrap manual-entry, Bonjour, relay status, host-service status, and Makefile smoke-env call sites.
  - Added phone-readable config versus operator-diagnostic boundary.
  - Added generated `.codex-dock/service.env` cleanup requirement.
  - Added active-doc disposition rows beyond README/easy-host/multi-host.
  - Added test-only transport URL env rule so app-facing env stays endpoint-only.
  - Added Node and Swift verification lines for the newly found surfaces.
- Remaining inconsistencies: none
- Unauthorized scope cuts: none
- Unresolved decisions: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 11) Decision Log (append-only)

- 2026-05-28 - Intent-derived: app-facing relay config is `host` + `port` only.
- 2026-05-28 - Intent-derived: Tailscale is operations only, not a Swift or generated-app-config concept.
- 2026-05-28 - Intent-derived: phone path stays on the Dock relay at `:4510`; raw app-server auth and OpenAI keys remain Mac-side.
- 2026-05-28 - Compatibility posture: migrate existing URL config once, then remove URL/auth/profile as app-facing config.
- 2026-05-28 - Migration: legacy saved `wss://` URLs are rejected with a visible migration error instead of being silently downgraded to `ws://`.
- 2026-05-28 - Discovery: Bonjour TXT is phone-readable config, so it must not advertise `auth=` or `scheme=ws`.
- 2026-05-28 - Diagnostics: relay HTTP status and host-service status are operator diagnostics, not app config sources.
- 2026-05-28 - Tests: app-like smoke tests use endpoint env; URL env is allowed only for explicitly transport-only tests.
