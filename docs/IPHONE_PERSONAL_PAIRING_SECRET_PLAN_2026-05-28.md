---
title: "Codex Dock - iPhone Local Relay - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - docs/EPIC_CODEX_DOCK_MVP_2026-05-27.md
---

# TL;DR

## Supersession Note - 2026-05-28

`docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28.md`
supersedes this plan anywhere it describes bootstrap host config as URL-backed
or token-bearing app config. The no-secret phone path now stores only relay
endpoints, accepts Bonjour host+port discovery, and computes the relay
WebSocket URL only at the transport boundary.

- Outcome: A physical iPhone install of Codex Dock can be opened from the home screen, discover the Mac relay on the local network, load sessions, and use voice transcription without any OpenAI key, Codex app-server token, or relay bearer token on the phone.
- Problem: The current app works through simulator launch environment variables. That cannot survive normal physical-device launch because the app bootstrap requires env-provided host/token config, and voice transcription currently reads `OPENAI_API_KEY` on the phone.
- Approach: Make `scripts/dock-relay.mjs` the single phone-facing owner for privileged work. The Mac relay keeps raw Codex and OpenAI secrets, advertises a Bonjour service, accepts the local personal phone path without client auth, and exposes only named app JSON-RPC methods.
- Plan: Prove the relay boundary first, then add iOS Bonjour discovery and no-secret host config, then move voice transcription through the relay, then add the install-only physical-device runbook and docs.
- Non-negotiables: Do not compile, paste, scan, store, or transmit provider/API tokens to the phone; do not treat simulator `SIMCTL_CHILD_*` launch as physical acceptance; do not expose a generic shell, filesystem, raw OpenAI, or raw app-server proxy from the relay.

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
  "digest": "sha256:9fea68b1fb7d72995eb65073498f3ba18789f33ba4efcb6b371d5a6299e97537",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T10:38:12Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:f7191ede99dba880e0ef418f071f5c1e7330a18e674cf31ccec9aa72b8ba5855",
      "completed_at": "2026-05-28T10:42:11Z",
      "doc_hash_after": "sha256:6a2a368bff0147f2ddaa5e617cece76efaf822ce3b9111bb74eaa494556a93fb"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:42:20Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:6a2a368bff0147f2ddaa5e617cece76efaf822ce3b9111bb74eaa494556a93fb",
      "completed_at": "2026-05-28T10:42:29Z",
      "doc_hash_after": "sha256:d96c81ea0350b063860f770ebf07a53f1e5341c1c163a2ac15b322c18cde35aa"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:42:35Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:d96c81ea0350b063860f770ebf07a53f1e5341c1c163a2ac15b322c18cde35aa",
      "completed_at": "2026-05-28T10:42:44Z",
      "doc_hash_after": "sha256:c4478c42ce6ab429a4457d42005939c56adfd0ac301df981c15c297cb6c9d3f8"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T10:43:15Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:c4478c42ce6ab429a4457d42005939c56adfd0ac301df981c15c297cb6c9d3f8",
      "completed_at": "2026-05-28T10:46:10Z",
      "doc_hash_after": "sha256:7db851cc7c102a5d9f467deedc0ca2010a1cfe25571f2f9cd4eef1348a54ac84"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T10:46:14Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:7db851cc7c102a5d9f467deedc0ca2010a1cfe25571f2f9cd4eef1348a54ac84",
      "completed_at": "2026-05-28T10:51:50Z",
      "doc_hash_after": "sha256:874eaca0ec850179287c8cb63a75a61b5f8bbb9bfb77ce264a0e869e4e1bb891"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

Codex Dock is done for this change when a physical iPhone build installed once with an install-only command can later be opened from the iPhone home screen and used against the Mac relay with no Mac-side app launch, no debugger env injection, and no phone-side OpenAI/Codex/relay secret.

## 0.2 In scope

- Requested behavior scope:
  - physical iPhone home-screen launch;
  - automatic discovery of the local Codex Dock relay;
  - Dock, Archive, Hosts/Relay, thread detail, request cards, text composer, and voice transcription all working through the discovered relay;
  - server-side OpenAI transcription through the relay;
  - install-only physical-device build target;
  - simulator env launch kept only as a development convenience.
- Allowed architectural convergence scope:
  - make the relay the only phone-facing privileged path;
  - make `DockHostConfiguration` support a no-client-auth relay path;
  - replace env-only app bootstrap with discovery-capable bootstrap;
  - rework Hosts into a relay connection surface;
  - add non-secret local persistence only where it makes phone launch less brittle;
  - update tests and live docs that currently encode phone-side tokens or simulator-only launch as the route.
- Adjacent surfaces that move with this contract:
  - Makefile service and install targets;
  - XcodeGen project and Info.plist local-network/Bonjour declarations;
  - Swift app bootstrap, host registry/config, stores, Hosts UI, and voice transcription;
  - Node relay auth, method allowlist, OpenAI transcription, Bonjour advertisement, and tests;
  - README and stale docs that still say the phone should receive a token or OpenAI key.
- Compatibility posture:
  - clean cutover for the physical iPhone path to discovered no-client-auth relay;
  - preserve simulator/env host configuration as a dev-only path;
  - preserve Mac-side raw app-server bearer authentication inside the relay.

## 0.3 Out of scope

- App Store distribution, multi-user login, enterprise device management, hostile-network hardening, `wss://`, mTLS, or per-device cryptographic pairing.
- QR pairing carrying secrets, phone-side Keychain storage of provider/API tokens, phone-side OpenAI API calls, or phone-side raw Codex app-server token storage.
- Generic command shell, filesystem browser, raw app-server proxy, raw OpenAI proxy, AIMGR account rotation, or future provider OAuth storage in the phone app.

## 0.4 Definition of done (acceptance evidence)

- Programmatic proof:
  - Node relay tests cover no-client-auth mode, Mac-side history token preservation, unsupported method rejection, server-side transcription success/failure, and secret/audio/transcript log redaction.
  - Swift tests cover optional bearer config, discovery-to-host mapping, physical startup without env config, manual non-secret fallback validation, relay-backed transcription request shape, and composer draft behavior.
  - Existing Swift transport tests still prove optional bearer headers are omitted when token is nil.
  - Build/test commands run clean enough to support the changed paths.
- Manual physical-device proof:
  - run `rtk make services` once on the Mac;
  - install with `rtk make device-install`, which defaults to the paired iPhone 14 and automatic signing team `R6B8KXF3QW`;
  - launch from the iPhone home screen;
  - confirm relay discovery, session load, force-quit/relaunch, phone reboot/relaunch, and voice transcription all work;
  - confirm logs/docs/screenshots do not expose OpenAI key, raw Codex token, relay bearer token, audio payload, or transcript text.

## 0.5 Key invariants (fix immediately if violated)

- The phone never contains, imports, stores, pastes, scans, or receives `OPENAI_API_KEY`, raw Codex app-server token, relay bearer token, or future AI/provider OAuth tokens.
- The physical app path cannot depend on `SIMCTL_CHILD_*`, debugger launch env, Mac-side app launch, or a fake placeholder token.
- The relay remains a narrow app API. Unsupported methods return JSON-RPC `-32601`.
- The raw/history app-server token remains Mac-side only and is used only by the relay to reach the raw app-server.
- OpenAI transcription happens on the Mac relay side and must not log the key, raw audio, base64 audio, transcript text, or full OpenAI response body.
- Relay Realtime transcription enforces chunk and pending-buffer limits so phone microphone streaming cannot turn the JSON-RPC socket into an unbounded memory sink.
- `ws://` is acceptable only for the personal trusted LAN/Tailscale V1 boundary; public or hostile-network exposure is outside this plan.
- Runtime fallback policy is forbidden. The app should either discover/connect through the chosen path, use the explicit dev-only env path, or fail visibly with a setup/offline UI.

## 0.1 Voice Transcription Supersession

As of 2026-05-28, `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` supersedes every voice-transcription instruction in this plan that prescribed completed-file upload, m4a/mp4 payloads, `audio/transcribe`, `gpt-4o-transcribe`, `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL`, or direct Swift OpenAI transcription. Current production voice uses live PCM chunks from the iPhone, relay-owned Realtime methods `audio/transcription/start`, `audio/transcription/append`, `audio/transcription/commit`, and `audio/transcription/cancel`, Mac-side `OPENAI_API_KEY`, Mac-side `CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper`, no phone-supplied provider config, no phone OpenAI secret, no one-shot fallback, and no auto-submit.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Home-screen physical iPhone use with no Mac launch command after install.
2. No phone-side secrets.
3. One Mac relay boundary for all privileged work.
4. Narrow relay API with fail-loud unsupported methods.
5. Minimal personal-use setup: `rtk make services` on the Mac, install once, then open app.
6. Preserve existing Dock, Archive, session detail, request-card, and composer behavior while rerouting config and transcription.

## 1.2 Constraints

- The current app is Swift/iOS 17 and uses `URLSessionWebSocketTask`, which wants a concrete `ws://` or `wss://` URL.
- The existing relay is Node ESM, already depends on `ws`, and currently listens on `:4510`.
- The relay already fronts app-facing JSON-RPC methods and calls the raw/history app-server with a Mac-side bearer token.
- Physical iOS launch cannot rely on simulator-only `SIMCTL_CHILD_*` env injection.
- iOS local-network discovery requires Bonjour permission declarations in app metadata.
- Voice capture streams live PCM chunks; the relay Realtime API must accept those chunks without exposing the OpenAI key or provider config to Swift.

## 1.3 Architectural principles (rules we will enforce)

- Mac relay is the single source of truth for secret-bearing operations.
- Phone config contains connection coordinates only: relay identity/name/URL/status and non-secret manual fallback values.
- Prefer direct behavior boundaries over repo-policing checks. The shipped phone path should have no API surface where a token is required, not merely a test that strings are absent.
- Preserve simulator/env config as a clearly marked dev path, not as a runtime shim for physical use.
- Keep relay methods named and purpose-specific. Realtime voice uses only the `audio/transcription/*` method family; arbitrary OpenAI forwarding and legacy `audio/transcribe` are not allowed.
- Discovery should produce the same `DockHostConfiguration` shape used by Dock, Archive, Hosts, and thread detail so the rest of the app keeps one host contract.

## 1.4 Known tradeoffs (explicit)

- V1 accepts no client auth from the phone to the relay on a trusted private network. That is simpler and safer for this personal use case than moving a bearer token into the phone.
- V1 accepts `ws://` on LAN/Tailscale. `wss://`, mTLS, and device approval are later hardening, not this plan.
- Bonjour discovery is preferred over QR/pairing because the relay can advertise non-secret connection metadata and the phone can connect without any secret transfer.
- Foundation `NetServiceBrowser` is the preferred iOS discovery API for this repo because it resolves a Bonjour service to host/port values that fit the existing `URLSessionWebSocketTask` transport. `NWBrowser` can remain a later refactor if the transport moves to `Network.framework`.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

- `scripts/dock-relay.mjs` is already a phone-facing relay on `:4510`. It authenticates phone WebSocket upgrades with `Authorization: Bearer <token>`, authenticates to the raw/history app-server with a Mac-side bearer token, merges history with live loopback app-server rows, and rejects unsupported JSON-RPC methods.
- `Makefile` starts LaunchAgents for the raw app-server and relay, writes `.env`, and launches simulator builds with `SIMCTL_CHILD_*` variables containing relay URL, bearer token, and OpenAI key.
- `CodexDockApp/CodexDockApp.swift` synchronously constructs `CodexDockRootView(registry: try HostRegistry.fromEnvironment())`; missing env config becomes a configuration-error UI.
- `DockHostConfiguration` requires a non-empty bearer token.
- `HostSettingsStore` and `HostsView` require manual token entry for saved hosts and keep those changes in memory.
- Realtime voice uses the Mac relay; Swift must not read `OPENAI_API_KEY` or send audio directly to OpenAI.

## 2.2 What’s broken / missing (concrete)

- A physical iPhone launched from the home screen does not have the simulator environment variables, so the current startup path cannot configure the relay.
- Putting the OpenAI key or relay/raw app-server token into the phone creates exactly the secret distribution problem the user wants to avoid.
- Voice transcription is currently phone-side, which contradicts the Mac-owned-secret model.
- The relay already exists but still requires a client bearer token, does not advertise itself with Bonjour, and does not own OpenAI transcription.
- The Makefile has no install-only physical-device path; `make app` builds, installs, and launches a simulator with env injection.
- README still describes token/env launch paths as the practical app route.

## 2.3 Constraints implied by the problem

- The physical phone path must be discovery-first and env-independent.
- The app-facing relay path must not require the phone to know a token.
- The raw/history app-server must remain authenticated behind the relay.
- The solution should reuse the relay and existing app host abstractions rather than introduce a second privileged server.
- Tests must distinguish physical acceptance from simulator/dev convenience.

<!-- arch_skill:block:research_grounding:start -->
# 3) Research Grounding (external + internal “ground truth”)

## 3.1 External anchors (papers, systems, prior art)

- Apple local-network/Bonjour platform model - adopt only the product implication: an iOS app that browses Bonjour services needs local-network usage copy and Bonjour service declarations. The implementation should use the existing project metadata path (`project.yml` plus generated Info.plist), not a new build system.
- Bonjour service discovery pattern - adopt service advertisement plus resolution to host/port; reject QR or secret-pairing payloads for V1 because they move setup burden and can tempt token transfer back onto the phone.
- OpenAI Realtime transcription - adopt server-side use through the relay because the iPhone must never receive the OpenAI key or choose provider config. The earlier completed-file transcription model scan in this doc is historical and superseded for production dictation; current production voice uses `gpt-realtime-whisper` through the relay-owned Realtime transcription session.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors:
  - `scripts/dock-relay.mjs` - current Mac relay, app-facing JSON-RPC method allowlist, raw/history app-server bearer use, phone bearer upgrade check, and live/history merge logic.
  - `scripts/dock-relay.test.mjs` - current Node relay tests are pure unit coverage for helper behavior; no server/auth/transcription integration coverage exists yet.
  - `Makefile` - canonical local service lifecycle, LaunchAgent generation, simulator build/install/launch flow, `.env` writing, and current lack of physical install-only target.
  - `CodexDockApp/CodexDockApp.swift` - app bootstrap is env-only today.
  - `CodexDock/Configuration/DockHostConfiguration.swift` - host config requires non-empty bearer token today.
  - `CodexDock/Configuration/HostRegistry.swift` - environment multi-host parsing exists and should remain dev-only.
  - `CodexDock/AppServer/AppServerClient.swift` - transport already supports optional bearer header; this is the Swift transport proof that no-client-auth host configs can work.
  - `CodexDock/State/DockStore.swift`, `CodexDock/State/ArchiveStore.swift`, `CodexDock/State/ThreadDetailStore.swift` - all operational app paths depend on `DockHostConfiguration`, so discovery should feed that same shape.
  - `CodexDock/State/HostSettingsStore.swift` and `CodexDock/Features/Hosts/HostsView.swift` - current Hosts surface is token-centric and in-memory.
  - `CodexDock/Voice/TranscriptionService.swift` - current OpenAI key usage is phone-side env config.
  - `CodexDock/State/LocalThreadMetadataStore.swift` - existing Application Support JSON persistence pattern for non-secret local state.
  - `CodexDockTests/AppServerClientTests.swift` - already proves optional bearer headers are omitted when token is nil.
  - `CodexDockTests/DockStoreTests.swift` - covers env host config, multi-host registry fanout, and token-required HostSettings behavior that must change.
  - `CodexDockTests/ThreadDetailStoreTests.swift` - covers draft insertion, no auto-submit, and recoverable transcription failure; this behavior must survive the relay-backed transcription swap.
  - `README.md` - live runbook currently makes simulator env/token launch the practical route and must be updated.
- Canonical path / owner to reuse:
  - `scripts/dock-relay.mjs` owns phone-facing privileged operations and the OpenAI/Codex secret boundary.
  - `DockHostConfiguration` remains the shared Swift connection contract, but its bearer token becomes optional.
  - A new relay discovery/bootstrap owner under `CodexDock/Configuration/` should produce `DockHostConfiguration` values for Dock, Archive, Hosts, and Thread Detail.
- Adjacent surfaces tied to the same contract family:
  - `project.yml` and `CodexDockApp/Info.plist` must both carry Bonjour service declarations.
  - `Makefile` and README must both separate simulator env launch from physical install/open flow.
  - Swift host-config tests and Hosts UI tests must update when bearer token becomes optional.
  - Relay tests must cover the new no-client-auth mode because the security posture depends on the relay API staying narrow.
- Compatibility posture (separate from `fallback_policy`):
  - Clean cutover for physical iPhone runtime to no-client-auth discovered relay.
  - Preserve env parsing for simulator/dev tests only.
  - Preserve Mac-side raw/history bearer auth in the relay.
- Existing patterns to reuse:
  - `FileLocalThreadMetadataStore` - Application Support JSON file pattern for non-secret local persistence.
  - `URLSessionWebSocketAppServerTransport` - optional bearer header behavior already exists.
  - `AppServerDockClient` and `AppServerThreadDetailSessionFactory` - one place each to pass optional bearer config into list/archive/detail flows.
  - Node `JsonRpcWebSocketClient` in `scripts/dock-relay.mjs` - existing raw app-server request pattern to reuse for relay methods.
- Prompt surfaces / agent contract to reuse:
  - Not applicable. This change is app/relay runtime code, not prompt or model behavior.
- Native model or agent capabilities to lean on:
  - Not applicable for the app architecture. OpenAI Realtime transcription remains a normal API call, now relay-side.
- Existing grounding / tool / file exposure:
  - The relay already has Mac process access to env/files and can read `.env` or process env without involving the phone.
  - The app already has local-network and microphone permission copy in metadata; Bonjour declarations are the missing piece.
- Duplicate or drifting paths relevant to this change:
  - Swift phone-side direct OpenAI/file-upload transcription is a drifting production path once relay Realtime transcription exists and must be deleted or kept out of the app target.
  - Host token editing in Hosts UI becomes stale for the physical path and should move behind dev-only behavior or be removed from the primary UI.
  - README simulator env launch snippets become stale if presented as the phone runbook.
- Capability-first opportunities before new tooling:
  - Reuse existing relay rather than adding a second backend.
  - Reuse existing Swift app-server transport with optional bearer rather than writing a custom WebSocket stack.
  - Reuse Application Support JSON pattern for non-secret relay settings instead of adding Keychain or a database.
- Behavior-preservation signals already available:
  - `rtk swift test` for Swift model/store/transport behavior.
  - `rtk npm test` or `rtk npm run test:relay` for Node relay behavior.
  - Generated-project simulator test/build when XcodeGen/Xcode are available.

## 3.3 Decision gaps that must be resolved before implementation

- none
<!-- arch_skill:block:research_grounding:end -->

<!-- arch_skill:block:current_architecture:start -->
# 4) Current Architecture (as-is)

## 4.1 On-disk structure

- Relay/runtime:
  - `scripts/dock-relay.mjs` - Node relay executable and exported helper functions.
  - `scripts/dock-relay.test.mjs` - Node helper tests.
  - `package.json` / `package-lock.json` - Node dependency surface.
  - `Makefile` - service, simulator, and app-server lifecycle.
- iOS app:
  - `CodexDockApp/CodexDockApp.swift` - app entrypoint.
  - `CodexDock/Configuration/DockHostConfiguration.swift` and `HostRegistry.swift` - env-derived host config.
  - `CodexDock/AppServer/*` - JSON-RPC and WebSocket transport.
  - `CodexDock/State/*` - Dock, Archive, Hosts, Thread Detail, and local metadata stores.
  - `CodexDock/Features/*` - UI.
  - `CodexDock/Voice/*` - live microphone capture and relay-owned Realtime transcription.
  - `project.yml` and `CodexDockApp/Info.plist` - app metadata.
  - `CodexDockTests/*` - Swift tests.

## 4.2 Control paths (runtime)

- Simulator path: `rtk make app` starts services, builds the simulator app, installs it, and launches it with `SIMCTL_CHILD_*` config including relay URL, bearer token, and OpenAI key.
- Physical path today: no install-only/home-screen flow exists; if installed manually, app startup sees no env config and shows configuration error.
- Relay path today: phone connects to relay with `Authorization: Bearer <token>`; relay authenticates to raw/history app-server with the Mac token and forwards only named JSON-RPC methods.
- Token path today: `.codex-dock/app-server.token` is generated by `Makefile`, used by the raw app-server, also used as the relay app-facing auth token, and injected into simulator launch env. That is acceptable as a simulator/debug bridge but is not an acceptable physical-phone secret boundary.
- Voice path today: iPhone captures live PCM chunks, `RelayRealtimeTranscriptionClient` streams them through the relay-owned Realtime contract, and `ThreadDetailStore` reconciles transcript deltas/finals into the composer draft.

## 4.3 Object model + key abstractions

- `DockHostConfiguration` is the app-wide connection object and currently requires `bearerToken: String`.
- `HostRegistry` groups one or more host configs and is currently built from environment variables.
- `AppServerClient` already accepts `bearerToken: String?`, so the lower transport can support no-client-auth.
- `HostSettingsStore` owns editable host registry state in memory and currently validates that tokens exist.
- `ThreadDetailStore` receives a `RealtimeTranscriptionServicing` dependency and defaults it to `RelayRealtimeTranscriptionClient` for the current host.

## 4.4 Observability + failure behavior today

- Relay logs aggregate counts and upstream errors to stderr. It must not start logging secrets/audio/transcripts during this change.
- App store failures surface as configuration/offline/error UI states.
- Missing env config on physical launch becomes a host configuration error, not discovery/setup.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current Hosts tab is token-centric:

```text
Hosts
[test all]

Amir-M5
ws://192.168.50.117:4510
[Test] [Edit]

Add/Edit Host
ID
Name
WebSocket
Token
[Save Host]
```
<!-- arch_skill:block:current_architecture:end -->

<!-- arch_skill:block:target_architecture:start -->
# 5) Target Architecture (to-be)

## 5.1 On-disk structure (future)

- Relay:
  - `scripts/dock-relay.mjs` adds no-client-auth local mode, Bonjour advertisement, `.env`/env OpenAI key loading, and relay-owned Realtime transcription methods.
  - `scripts/dock-relay.test.mjs` expands from helper-only tests to cover server/auth/Realtime transcription boundaries.
  - `package.json` / `package-lock.json` add a Bonjour dependency only if the implementation chooses a Node-managed advertiser instead of a managed `dns-sd` child process.
- iOS:
  - `CodexDock/Configuration/RelayDiscovery.swift` owns Bonjour service browsing/resolution and maps service metadata into non-secret discovered relay values.
  - `CodexDock/Configuration/RelayBootstrapStore.swift` or an equivalent existing-store extension owns startup priority: discovered relay, saved non-secret relay, dev env, setup/offline UI.
  - `DockHostConfiguration` changes `bearerToken` to optional.
  - `HostRegistry` keeps env parsing for simulator/dev but accepts no-token hosts.
  - `HostSettingsStore` and `HostsView` become a relay connection surface with discovery, current relay status, and manual non-secret URL fallback.
  - `TranscriptionService.swift` owns the Realtime transcription abstractions used by `RelayRealtimeTranscriptionClient`.
  - `project.yml` and `CodexDockApp/Info.plist` include `NSBonjourServices`.

## 5.2 Control paths (future)

- Mac setup path:
  - `rtk make services` starts/reuses raw app-server and relay LaunchAgents.
  - The relay reads `OPENAI_API_KEY` from process env or `.env` on the Mac.
  - The relay advertises `_codexdock._tcp` on port `4510` with non-secret TXT metadata only.
- Physical iPhone path:
  - app launches from home screen;
  - bootstrap starts Bonjour discovery;
  - discovered service resolves to `ws://<relay-host>:4510`;
  - bootstrap builds `DockHostConfiguration(id:name:webSocketURL:bearerToken:nil)`;
  - Dock, Archive, Hosts, and Thread Detail use that registry.
- Voice path:
  - iPhone captures live PCM16 mono 24 kHz chunks;
  - `RelayRealtimeTranscriptionClient` sends JSON-RPC `audio/transcription/start`, `audio/transcription/append`, `audio/transcription/commit`, and `audio/transcription/cancel` through the relay;
  - the phone does not choose the OpenAI model, endpoint, delay, language allowlist, or provider config;
  - the relay uses Mac-side `CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL` when set, otherwise defaults to `gpt-realtime-whisper`;
  - relay streams to OpenAI Realtime from the Mac and forwards sanitized delta/completed/failed/canceled/closed events;
  - `ThreadDetailStore` inserts live deltas/finals into the draft and does not auto-submit.
- Simulator/dev path:
  - env parsing remains available for `rtk make app SIM=...`;
  - simulator can still pass tokens if the relay is running in bearer mode for dev tests, but this is not physical acceptance.

## 5.3 Object model + abstractions (future)

- `DockHostConfiguration.bearerToken: String?` is the shared contract.
- `DiscoveredRelay` contains only non-secret fields: stable id/service name, display name, host name/address, port, TXT display metadata, and generated WebSocket URL.
- `RelayDiscovery` provides discovered relay updates and can be faked in tests.
- `RelaySettingsStore` or equivalent stores only non-secret selected/manual relay values under Application Support JSON.
- `RelayRealtimeTranscriptionClient` conforms to `RealtimeTranscriptionServicing` and reuses `AppServerClient`/JSON-RPC instead of raw OpenAI HTTP from Swift.
- Relay config separates:
  - `phoneAuth: none | bearer`;
  - `relayBearerToken` only required when `phoneAuth == bearer`;
  - `historyBearerToken` always required for raw/history app-server access;
  - `openAIAPIKey` loaded Mac-side only.
  - `openAIRealtimeTranscriptionModel` and related Realtime limits/delay loaded Mac-side only.

## 5.4 Invariants and boundaries

- Phone-to-relay V1 auth: none on trusted private network.
- Relay-to-history auth: bearer token from `.codex-dock/app-server.token`.
- Relay API: named app methods only, plus the Realtime `audio/transcription/*` method family; unsupported methods return `-32601`.
- Legacy raw `audio/transcribe` is rejected after the Realtime cutover.
- Realtime transcription accepts bounded PCM chunks and rejects arbitrary files or arbitrary OpenAI parameters.
- The relay default Realtime transcription model is `gpt-realtime-whisper`.
- The phone request cannot set arbitrary OpenAI models or Realtime provider config. Model/delay changes are Mac-side relay config only.
- Relay TXT records must not include tokens, paths, prompts, transcripts, audio, or thread data.
- Swift production path must not construct `OpenAITranscriptionClient` from `OPENAI_API_KEY`.
- Local manual fallback is URL-only and non-secret.
- No runtime bridge is approved where the physical path secretly depends on env or a token field.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Target Hosts/Relay tab:

```text
Relay
[refresh/test]

Current
Amir-M5
ws://Amir-M5.local:4510
Online - 12 sessions

Discovered
Amir-M5  _codexdock._tcp  [Use]

Manual
ws://192.168.50.117:4510
[Use URL]
```

No token field appears in the primary physical-phone flow.
<!-- arch_skill:block:target_architecture:end -->

<!-- arch_skill:block:call_site_audit:start -->
# 6) Call-Site Audit (exhaustive change inventory)

## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Relay auth | `scripts/dock-relay.mjs` | `parseArgs`, `main`, `assertAuthorized`, `server.on("upgrade")` | `--auth-token-file` required; phone must send bearer | Add `--phone-auth none|bearer`; no-client mode skips phone bearer while preserving history token | Physical phone cannot receive relay token | `phoneAuth=none` local V1 | Node relay auth tests |
| Relay raw app-server boundary | `scripts/dock-relay.mjs` | `JsonRpcWebSocketClient`, history calls | History bearer token used Mac-side | Keep required and never expose downstream | Secret stays on Mac | history token only in relay config | Node relay tests |
| Relay discovery | `scripts/dock-relay.mjs`, `package.json` | server startup/shutdown | No Bonjour advertisement | Advertise `_codexdock._tcp` with non-secret TXT | Phone discovers relay without setup | Bonjour service on relay port | Manual/device; unit around metadata builder |
| Relay transcription | `scripts/dock-relay.mjs` | `handleRequest` | Realtime voice methods live behind the relay; legacy `audio/transcribe` is historical | Add/keep relay-owned Realtime methods and reject raw `audio/transcribe` | Removes OpenAI key and provider config from phone and prevents slow upload fallback | JSON-RPC `audio/transcription/*`; relay owns model/delay choice | Node fake OpenAI tests; Swift Realtime relay client tests |
| Relay method boundary | `scripts/dock-relay.mjs` | default method case | Unsupported methods fail `-32601` | Preserve | Avoid generic proxy | named methods only | Existing/new Node tests |
| Build services | `Makefile` | `services`, `dock-relay`, `env-file` | Starts token-auth relay; writes env for simulator, including token/OpenAI key values | Start relay in no-client-auth V1, pass/load OpenAI key only into the relay process, keep secrets out of app-consumed output | One Mac service command | `rtk make services` owns Mac readiness | Make/docs review |
| Device install | `Makefile` | new target | No physical install-only target | Add `device-install` for `iphoneos` build/install without launch/env | User installs app once, opens manually | install-only physical path | Manual proof |
| App metadata | `project.yml`, `CodexDockApp/Info.plist` | local network keys | Local network copy only | Add `NSBonjourServices` for `_codexdock._tcp` | iOS discovery permission | Bonjour declaration | Generated project build |
| App bootstrap | `CodexDockApp/CodexDockApp.swift` | `makeRootView` | Env-only registry | Initialize discovery/bootstrap store | Home-screen launch works | discovery -> registry | Swift startup tests |
| Host config | `CodexDock/Configuration/DockHostConfiguration.swift` | `bearerToken`, `fromEnvironment` | Token required | Make token optional; env token stays dev-only optional | No fake phone token | optional bearer | Swift config tests |
| Host registry | `CodexDock/Configuration/HostRegistry.swift` | env multi-host parser | Scoped hosts require tokens through config | Accept no-token host configs | Discovery builds registry | optional bearer registry | Swift config tests |
| Discovery owner | `CodexDock/Configuration/RelayDiscovery.swift` | new | Missing | Browse/resolve Bonjour and validate manual URLs | Physical startup source | `DiscoveredRelay` | Swift discovery tests |
| Non-secret persistence | `CodexDock/Configuration/RelaySettingsStore.swift` or equivalent | new | Only thread metadata persisted | Store selected/manual relay values only | Reopen without env; support manual fallback | Application Support JSON | Swift persistence tests |
| Hosts UI/store | `CodexDock/State/HostSettingsStore.swift`, `CodexDock/Features/Hosts/HostsView.swift` | token-centric editor | Requires token | Show discovered/current/manual URL; no primary token field | UI matches secret boundary | relay status surface | Swift store/UI-adjacent tests |
| Dock/Archive stores | `CodexDock/State/DockStore.swift`, `CodexDock/State/ArchiveStore.swift`, `CodexDock/Features/Dock/DockView.swift` | consume registry | Work if registry exists | Update from discovery/bootstrap registry | Main app uses discovered relay | same host contract | Existing Dock tests |
| Thread detail | `CodexDock/State/ThreadDetailStore.swift` | default transcription service | Uses relay-backed Realtime client | Keep default physical path relay-backed with no one-shot fallback | Voice no phone key | `RelayRealtimeTranscriptionClient` | ThreadDetail tests |
| Voice service | `CodexDock/Voice/TranscriptionService.swift` | Realtime service/session abstractions | Streams relay Realtime sessions | Delete direct Swift OpenAI/file-upload paths | Server-owned OpenAI key | JSON-RPC Realtime audio client | Swift transcription tests |
| Real-host smoke tests | `CodexDockTests/AppServerClientTests.swift` | phone-reachable handshake/list/detail/archive tests | Treat phone-reachable endpoint as bearer-authenticated and require token env/file | Split raw-auth/dev-only coverage from no-client-auth relay physical-path coverage | Prevent old phone-token proof from remaining canonical | physical relay smoke must work without bearer token | AppServerClient smoke tests |
| README/runbook | `README.md` | service/simulator/app sections | Simulator env token path foregrounded | Document `make services`, `device-install`, home-screen launch, discovery, no phone secrets | Prevent stale operational truth | physical runbook | Docs review |
| UX/product docs | `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` | requirement says `.env` key safe to embed | Stale/conflicting with relay-owned secret plan | Update or annotate as superseded by this plan | Avoid reviving phone key approach | server-owned secret stance | Docs review |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  - `scripts/dock-relay.mjs` owns all secret-bearing phone-adjacent operations.
  - `DockHostConfiguration` remains the Swift app-wide host contract.
  - New discovery/bootstrap code feeds `HostRegistry`; Dock/Archive/Thread Detail should not each discover independently.
- Deprecated APIs (if any):
  - `DockHostConfiguration.bearerToken: String` becomes `String?`.
  - `HostSettingsStore.saveHost(... bearerToken:)` is replaced or relaxed for the no-secret physical route.
  - Completed-file transcription, `audio/transcribe`, and direct Swift OpenAI clients are superseded by relay Realtime voice.
- Delete list:
  - Remove primary physical UI requirement for token entry.
  - Remove physical acceptance language based on simulator env launch.
  - Delete `OpenAITranscriptionClient` and one-shot relay/file-upload voice code once Realtime is the production path.
- Adjacent surfaces tied to the same contract family:
  - Include now: Makefile, README, project metadata, Swift tests, Node tests.
  - Explicitly out of scope: App Store, hostile network, per-device pairing, `wss://`, mTLS.
- Compatibility posture / cutover plan:
  - Physical path cleanly cuts over to no-client-auth discovered relay.
  - Simulator/env path remains dev-only.
  - Raw/history app-server auth remains preserved behind relay.
- Capability-replacing harnesses to delete or justify:
  - None. This is deterministic app/relay runtime code, not an agent capability wrapper.
- Live docs/comments/instructions to update or delete:
  - `README.md` and the stale OpenAI-key statement in `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`.
- Behavior-preservation signals for refactors:
  - Existing Dock/Archive/ThreadDetail tests must still pass.
  - Existing composer voice tests must still prove no auto-submit and draft preservation.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Swift connection config | `DockHostConfiguration`, `HostRegistry`, `AppServerDockClient`, `AppServerThreadDetailSessionFactory` | Optional bearer host config | Prevents fake-token hacks and keeps all app paths on one host contract | include |
| Local non-secret settings | `FileLocalThreadMetadataStore` -> new relay settings store | Application Support JSON | Avoids Keychain/database overbuild and keeps settings non-secret | include |
| Relay method boundary | `scripts/dock-relay.mjs` | named-method allowlist | Prevents generic privileged proxy from creeping in with transcription | include |
| Runbook | `Makefile`, `README.md` | services vs device-install split | Prevents simulator launch from being accepted as phone proof | include |
| Future hardening | device approval, `wss://`, mTLS | explicit later hardening | Avoids setup burden in personal V1 | exclude |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:phase_plan:start -->
# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

## Phase 1 - Relay owns the no-secret phone boundary

* Goal: Prove the Mac relay can be the only phone-facing privileged path without a phone bearer token.
* Status: Implemented and programmatically verified on 2026-05-28.
* Work: Change the relay first because every iPhone change depends on the server boundary being real.
* Checklist (must all be done):
  - Add relay config for `phoneAuth=none|bearer`; default `make services` uses `none` for local personal V1.
  - Keep raw/history app-server bearer token required inside the relay.
  - Preserve unsupported method rejection with JSON-RPC `-32601`.
  - Historical voice note: this phase originally added one-shot `audio/transcribe`; Realtime Phase 5 supersedes that route with `audio/transcription/*` and rejects raw `audio/transcribe`.
  - Default relay Realtime transcription to `gpt-realtime-whisper`; allow only Mac-side `CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL` and `CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY` overrides.
  - Reject phone-supplied OpenAI model/provider selection.
  - Add bounded Realtime chunk and pending-buffer limits.
  - Add safe transcription errors for missing OpenAI key and upstream failures.
  - Ensure relay logging excludes OpenAI key, raw Codex token, relay bearer token, raw audio, base64 audio, transcript text, prompts, thread bodies, and full OpenAI response body.
  - Add Bonjour advertisement for `_codexdock._tcp` with non-secret TXT metadata.
  - Add/extend Node tests for no-client-auth mode, history token boundary, unsupported methods, transcription success/failure, and redaction.
  - Add/adjust real-host smoke coverage so no-client-auth relay physical-path tests do not require bearer token env/file; keep raw-auth coverage marked dev-only.
* Verification (required proof): `rtk npm test` or `rtk npm run test:relay`.
* Docs/comments (propagation; only if needed): Add a short code comment only at any non-obvious auth/transcription boundary.
* Exit criteria (all required):
  - A WebSocket client can connect to the relay with no Authorization header when `phoneAuth=none`.
  - The relay still uses bearer auth for raw/history app-server calls.
  - Realtime transcription returns delta/completed events through the relay and never exposes the OpenAI key to the client.
  - Tests prove the relay uses relay-side Realtime provider config and rejects phone-side provider selection.
  - Oversized or malformed audio chunks fail safely before unbounded buffering.
  - Realtime upstream timeout behavior is tested and returns a safe relay error.
  - `_codexdock._tcp` advertisement is started on the relay port with only non-secret TXT metadata, and advertisement shutdown is owned by the relay lifecycle.
  - Unsupported methods still return `-32601`.
  - Physical-path real-host smoke tests no longer require phone bearer token env/file.
  - Tests prove the above and prove sensitive values are not written to captured logs.
* Rollback: Revert relay changes and keep existing bearer-auth simulator path; do not proceed to iOS physical path until this phase is restored.

## Phase 2 - iPhone discovers and connects without env or token

* Goal: Make physical app startup produce a usable host registry from local relay discovery.
* Status: Implemented and programmatically verified on 2026-05-28.
* Work: Add discovery/bootstrap while keeping existing app stores on the shared host contract.
* Checklist (must all be done):
  - Add Bonjour service declarations to `project.yml` and `CodexDockApp/Info.plist`.
  - Add `DiscoveredRelay` and discovery service under `CodexDock/Configuration/`.
  - Use `NetServiceBrowser`/resolution or an equally simple iOS API that yields host/port values for the existing WebSocket transport.
  - Change `DockHostConfiguration.bearerToken` to optional and update all call sites.
  - Keep `HostRegistry.fromEnvironment()` working as simulator/dev fallback with optional token.
  - Add bootstrap state so physical launch does not fail only because env config is absent.
  - Add non-secret selected/manual relay persistence using the existing Application Support JSON pattern.
  - Update Hosts UI/store into a relay connection surface with discovered/current/manual non-secret URL paths and no primary token field.
  - Ensure Dock, Archive, Hosts, and Thread Detail all use the discovered registry.
  - Add Swift tests for discovery mapping/manual URL validation, optional bearer config, env dev fallback, no-env startup state, and host registry updates.
* Verification (required proof): `rtk swift test`; generated-project build/test if XcodeGen/Xcode are available.
* Docs/comments (propagation; only if needed): Comment the discovery-to-URL boundary if service resolution details are non-obvious.
* Exit criteria (all required):
  - Physical startup can reach setup/discovery UI without env vars.
  - A discovered relay produces `DockHostConfiguration(... bearerToken: nil)`.
  - AppServer transport omits Authorization for nil token and existing bearer tests still pass.
  - Dock, Archive, Hosts, and Thread Detail receive registry updates from the same source.
  - Manual fallback stores only URL/name/id data, never secrets.
* Rollback: Revert Swift discovery/bootstrap/config changes; keep relay Phase 1 intact.

## Phase 3 - Voice uses relay Realtime transcription

* Goal: Remove phone-side OpenAI key dependency from the production voice path while preserving composer behavior.
* Status: Implemented by the Realtime plan and programmatically verified on 2026-05-28.
* Work: Use relay-backed Realtime JSON-RPC for production dictation.
* Checklist (must all be done):
  - Add `RelayRealtimeTranscriptionClient` conforming to `RealtimeTranscriptionServicing`.
  - Add typed `audio/transcription/*` request/notification DTOs.
  - Ensure Swift sends only audio chunks and session control, not OpenAI key, model choice, endpoint, or provider config.
  - Wire `ThreadDetailStore`/session detail construction so the default physical path uses relay-backed Realtime transcription for the current host.
  - Keep transcript insertion, no auto-submit, draft editability, and failure recovery behavior unchanged.
  - Prevent production app bootstrap from constructing direct Swift OpenAI/file-upload transcription with `OPENAI_API_KEY`.
  - Add Swift tests for relay Realtime request/event shape, success, failure, draft preservation, and no auto-submit.
* Verification (required proof): `rtk swift test`.
* Docs/comments (propagation; only if needed): None unless the relay transcription client has a non-obvious payload size or MIME invariant.
* Exit criteria (all required):
  - Voice transcription succeeds through the relay Realtime client in tests.
  - Existing composer voice behavior tests still pass.
  - The production app path has no `OPENAI_API_KEY` dependency.
* Rollback: Revert relay-backed voice wiring; do not reintroduce phone-side key handling to physical acceptance.

## Phase 4 - Physical install/runbook and final proof

* Goal: Make the user-facing workflow install once, open app, use relay.
* Status: Implemented on 2026-05-28. Build/install target and services are implemented; the physical install path works on the paired iPhone 14 with automatic signing team `R6B8KXF3QW`.
* Work: Align build targets, docs, and manual proof with the shipped path.
* Checklist (must all be done):
  - Add `rtk make device-install` or equivalent install-only physical target; this repo defaults to the paired iPhone 14 and automatic signing team `R6B8KXF3QW`.
  - Ensure `device-install` builds for `iphoneos`, applies signing settings, installs the app, and does not launch it or pass env/secrets.
  - Keep `rtk make app SIM=...` as simulator/dev convenience only.
  - Update README with Mac services, physical install, home-screen launch, discovery, voice, and no-phone-secret posture.
  - Update or annotate stale doc text that says the OpenAI key is safe to embed in the iPhone client.
  - Run available programmatic checks.
  - Execute the manual physical-device proof. If device/signing access is unavailable, mark implementation blocked/pending physical proof instead of complete.
  - Check relay/app logs, updated docs, and any screenshots/proof artifacts for OpenAI key, raw Codex token, relay bearer token, raw audio, base64 audio, transcript text, prompts, thread bodies, and full OpenAI response body.
* Verification (required proof): `rtk npm test` or `rtk npm run test:relay`; `rtk swift test`; generated-project build/test where available; manual physical checklist when device/signing are available.
* Docs/comments (propagation; only if needed): README and stale UX spec update are required work.
* Exit criteria (all required):
  - The install target does not launch the app and does not pass env vars or secrets.
  - README gives the user the simple path: start Mac services, install once, open app.
  - Stale phone-key docs are corrected or explicitly superseded.
  - Programmatic checks pass or any environment-only inability is documented.
  - Manual proof confirms home-screen launch, discovery, session load, relaunch/reboot persistence, and relay voice transcription.
  - Final proof artifacts and logs contain no OpenAI key, raw Codex token, relay bearer token, raw audio, base64 audio, transcript text, prompts, thread bodies, or full OpenAI response body.
* Rollback: Revert Makefile/docs target changes only; keep code path if tests remain valid.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (lean but required)

Avoid verification bureaucracy. Prefer existing credible signals that prove shipped behavior: Node relay tests for relay boundaries, Swift tests for config/bootstrap/voice behavior, generated Xcode build/test when available, and one manual physical-device checklist for the actual user workflow. Verification is required where Section 7 and the definition of done require it; "lean" means no ceremony, not optional proof.

## 8.1 Unit tests (contracts)

- Node:
  - no-client-auth accepts missing Authorization only in `phoneAuth=none`;
  - bearer mode still rejects missing/bad Authorization;
  - unsupported methods return `-32601`;
  - Realtime `audio/transcription/*` validates params and handles missing key safely;
  - Realtime transcription uses relay-owned `gpt-realtime-whisper` defaults and does not let the phone choose arbitrary OpenAI models or provider config;
  - timeout and oversized-chunk behavior fail safely before leaking audio or OpenAI details;
  - captured logs do not include keys, tokens, audio, base64 payloads, transcript text, prompts, thread bodies, or full OpenAI responses;
  - Bonjour advertisement metadata contains only non-secret relay name/version/auth-mode values.
- Swift:
  - optional bearer host config;
  - env fallback remains dev-only capable;
  - discovery metadata/manual URL maps into host config;
  - relay settings persistence stores no secrets;
  - relay Realtime transcription event/failure handling;
  - relay Realtime transcription client sends no model or provider choice from the phone.

## 8.2 Integration tests (flows)

- Existing Dock/Archive/ThreadDetail store tests should continue passing after optional bearer migration.
- Composer voice tests should continue proving no auto-submit and draft preservation.
- Relay server tests should exercise a real WebSocket upgrade against the local test server where practical.

## 8.3 E2E / device tests (realistic)

- Manual physical-device checklist is the final proof because the core bug is home-screen launch without Mac-side env injection.
- Simulator remains useful for fast dev smoke checks but cannot complete physical acceptance.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

1. Implement relay boundary first and keep it passing tests.
2. Implement discovery/bootstrap and optional bearer in Swift.
3. Move voice to relay.
4. Add physical install target and runbook.
5. Run checks and physical proof.

This is personal local software. No staged multi-user rollout is needed.

## 9.2 Telemetry changes

- No analytics.
- Relay logs may include service lifecycle, ready state, method names, status counts, and safe error classes.
- Relay logs must not include OpenAI key, raw app-server token, relay bearer token, raw audio, base64 audio, transcript text, prompts, thread bodies, or full OpenAI response body.

## 9.3 Operational runbook

- Mac:
  - `rtk make services`
  - `rtk make dock-relay-status`
  - `rtk make app-server-status`
- Phone:
  - `rtk make device-install`
  - open Codex Dock from the iPhone home screen.
- Dev simulator:
  - `rtk make app SIM='iPhone 17'`

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, helper blocks, receipts state, research/model decision, target architecture, call-site audit, phase obligations, verification, rollout, and decision log.
- Findings summary:
  - Main architecture is consistent: Mac relay owns secrets, physical iPhone uses no client auth, Bonjour is discovery, Realtime transcription is relay-owned, simulator/env is dev-only.
  - Repairs were required for stale helper status, physical proof wording, Section 8 wording, real-host bearer-token smoke tests, Bonjour proof, timeout proof, and full sensitive-output proof.
- Integrated repairs:
  - Marked external research grounding done because the web scan is now in Section 3.
  - Added explicit real-host smoke-test migration for bearer-token assumptions.
  - Added Phase 1 exit proof for Bonjour advertisement, transcription timeout, no-client-auth real-host smoke tests, and full sensitive-output redaction.
  - Made Phase 4 require actual manual physical-device proof before completion, with unavailable device/signing treated as pending proof instead of done.
  - Renamed Section 8 to lean but required verification and carried redaction/Bonjour proof into unit-test strategy.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Server-owned secrets replace phone pairing

Context

The user rejected phone-side pairing/secret storage and pointed to the existing local relay as the elegant owner for privileged work.

Options

- Put OpenAI/Codex/relay secrets in the phone app because this is personal.
- Add QR/Keychain pairing that transfers a relay token to the phone.
- Keep all secrets on the Mac relay and make the phone a discovery-based local UI.

Decision

Keep all secrets on the Mac relay. The physical iPhone path discovers the relay and connects without client bearer auth in V1.

Consequences

- Relay must own OpenAI transcription.
- Relay must advertise itself.
- Phone config must be non-secret.
- Later hardening should be Mac-side device approval, not embedded/pasted phone keys.

Follow-ups

- Implement optional device approval only if the trusted LAN/Tailscale boundary becomes too loose.

## 2026-05-28 - Intent-derived: use resolved Bonjour host/port for existing WebSocket transport

Blocker: The earlier noncanonical draft named `NWBrowser`, but the existing Swift transport takes a `URL` and cannot directly consume an unresolved Bonjour service endpoint.

Consulted: Section 0 requested automatic discovery with minimal setup; TL;DR requires no secret transfer; Section 5 keeps `URLSessionWebSocketTask` as the transport.

Intent says: Discovery is required, but the specific iOS browsing API is not the user-visible product requirement.

Decision: Use `NetServiceBrowser`/service resolution or an equally simple API that yields host/port for a `ws://` URL. This aligns discovery with the existing transport and avoids a custom Network.framework WebSocket rewrite.

Consequences: The plan still uses Bonjour discovery but changes the implementation detail from `NWBrowser` to the simpler resolved-host contract.

## 2026-05-28 - Intent-derived: no phone client auth for personal V1

Blocker: A relay without phone auth is looser than a token-auth relay on the local network.

Consulted: Section 0 non-negotiables; TL;DR; user correction that the app should work by installing/opening rather than running commands or handling keys.

Intent says: The phone must not contain a relay bearer token, and setup must not require secret handling.

Decision: V1 uses no client bearer token for the phone-to-relay hop on trusted LAN/Tailscale. The API remains narrow and the raw/history token remains Mac-side.

Consequences: Hostile-network hardening is out of scope for V1 and listed as later work.

## 2026-05-28 - Independent-web-scan: completed-file transcription model default superseded by Realtime

Context

The user asked to search online, not rely on OpenAI API docs, for the best OpenAI transcription model for this app as of May 2026. This decision applied to the earlier completed-file transcription path and is now superseded for production voice by the Realtime transcription plan.

Options

- `whisper-1` because it is the familiar Whisper API model.
- `gpt-4o-mini-transcribe` because multiple 2026 comparisons call it the cost-first option.
- `gpt-4o-transcribe` because independent 2026 roundups place it above hosted Whisper variants and as the strongest OpenAI-native choice.
- `gpt-4o-transcribe-diarize` because it adds speaker labels.

Decision

Historical decision: use `gpt-4o-transcribe` as the completed-file relay default for composer dictation. Current production voice does not use that path; it uses relay-owned Realtime transcription with `gpt-realtime-whisper`.

Consequences

- Relay owns transcription model choice.
- The phone streams audio chunks only and cannot request arbitrary OpenAI models or provider config.
- The old one-shot model default is not a production fallback after Realtime cutover.
- This is not a claim that OpenAI is the best STT vendor overall; the scan found stronger non-OpenAI leaders, but the requested stack is OpenAI-backed and already has an OpenAI key on the Mac.

Follow-ups

- Re-check independent benchmarks before changing the relay default after 2026-05-28.

# Appendix A) Imported Notes (unplaced; do not delete)

All meaning-bearing content from the previous local-relay draft was re-homed into Sections 0 through 10. No source requirement was intentionally dropped. The stale filename still contains `PAIRING_SECRET` because it is the already-created plan path, but the plan content supersedes phone-side pairing and secret storage.

# Appendix B) Conversion Notes

- Converted the previous noncanonical local-relay plan into the full `arch-step` scaffold on 2026-05-28.
- Kept the source plan's strongest requirements: install once, open app, Bonjour discovery, server-owned OpenAI/Codex secrets, no phone token, no QR secret pairing, no simulator env acceptance, relay-side transcription, and physical-device manual proof.
- Changed the iOS discovery implementation detail from `NWBrowser` to resolved Bonjour host/port because the existing app transport is URL-based. This is recorded in the Decision Log.
- Added the independent-web-scan transcription policy on 2026-05-28 for the old completed-file path; Realtime production voice supersedes it with relay-owned `gpt-realtime-whisper`.
