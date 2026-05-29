---
title: "Codex Dock - Single Endpoint Per Host - Architecture Plan"
date: 2026-05-29
status: implemented
fallback_policy: forbidden
owners: [Amir]
reviewers: []
doc_type: phased_refactor
related:
  - README.md
  - Makefile
  - CodexDock/Configuration/DockHostConfiguration.swift
  - CodexDock/Configuration/HostRegistry.swift
  - CodexDock/Configuration/RelayDiscovery.swift
  - CodexDock/Configuration/RelayBootstrapStore.swift
  - CodexDock/AppServer/AppServerHostConnector.swift
  - scripts/device-relay-config.mjs
---

# TL;DR

Outcome: Codex Dock will have one host entry per relay and one endpoint per host. `Amir-M5` and `Home` become separate hosts everywhere the app, device config, host settings, tests, and docs talk about hosts.

Problem: the current app model treats one logical host as a bundle of endpoints, so `Amir-M5` can carry multiple URLs, silently fall through from one endpoint to another, and display one row with a comma-separated endpoint list.

Approach: delete the multi-endpoint host abstraction instead of preserving it. Keep `DockRelayEndpoint` as the `host:port` value object, make `DockHostConfiguration` own exactly one endpoint, parse host lists into multiple host rows, and remove relay-instance IDs from phone-side host configuration.

Plan: first cut the Swift app model and saved config contract through the real connection path, then update Makefile/device config and Node helpers, then rewrite tests and live docs so no remaining surface teaches endpoint aliases or per-host fallbacks.

Non-negotiables: no endpoint aliases, no fallback endpoint arrays, no `relayInstanceID` grouping on phone-side host config, no compatibility bridge for old saved multi-endpoint JSON, no stale docs preserved for posterity.

<!-- arch_skill:block:implementation_audit:start -->
Implementation audit result: approved 2026-05-29.

Implemented as a clean cutover:

- `DockHostConfiguration` now stores exactly one `endpoint`.
- `HostRegistry` owns host lists, and `CODEX_DOCK_HOSTS=a:4510,b:4510` creates two host rows.
- Saved app config is strict `{ "hosts": [{ "host": "...", "port": 4510 }] }` JSON.
- Old endpoint-list JSON, mixed phone-side `relayInstanceID`, duplicate saved hosts, and raw `:4500` hosts fail loudly.
- Runtime connection, thread detail, dock loads, archive loads, and relay realtime transcription use `host.endpoint` with no same-host endpoint fallback.
- Node device config, host-service app config, Makefile defaults/output, `README.md`, and `AGENTS.md` use host-list language and no phone-side relay identity.

Strict review findings fixed before approval:

- Replaced a misleading duplicate-host error in `DockHostConfiguration.fromEnvironment` with an explicit single-host error.
- Changed `LocalRelayHostList(hosts:)` so duplicate inputs are not silently compacted; validation now fails duplicates loudly.

Verification evidence is recorded in
`docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29_WORKLOG.md`.
<!-- arch_skill:block:implementation_audit:end -->

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-29
external_research_grounding: not needed - local repo contract refactor only
deep_dive_pass_2: done 2026-05-29
recommended_flow: deep dive -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:8bd243780e16098a78a7ae0d6f44b81e13493c2a586547565fa7511835ca0936",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-29T11:33:34Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:e7ee517cb0ac3d8fa82a4b4ef64cb0ed9a3872528dc6ef36ce67411ea4248b32",
      "completed_at": "2026-05-29T11:33:54Z",
      "doc_hash_after": "sha256:517ec477d5f2d8d56a377505cb4bcbef9af3006c5f686fffe10da84c5f96e9f8"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T11:33:59Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:517ec477d5f2d8d56a377505cb4bcbef9af3006c5f686fffe10da84c5f96e9f8",
      "completed_at": "2026-05-29T11:34:58Z",
      "doc_hash_after": "sha256:384641e91362de29969e04d3faa54c66d9a1f0da1784f7e4a4e5e9d9b3ff9471"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T11:35:15Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:384641e91362de29969e04d3faa54c66d9a1f0da1784f7e4a4e5e9d9b3ff9471",
      "completed_at": "2026-05-29T11:35:52Z",
      "doc_hash_after": "sha256:d2ad7f4ebc161234665bc5f207e2b9999260ce447d40028aff39a629b97ff59a"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-29T11:36:00Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:d2ad7f4ebc161234665bc5f207e2b9999260ce447d40028aff39a629b97ff59a",
      "completed_at": "2026-05-29T11:36:49Z",
      "doc_hash_after": "sha256:c87691bed339942634a76b951f2daac26d40738c097462c6bbb6279aaa2470a6"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-29T11:37:06Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:c87691bed339942634a76b951f2daac26d40738c097462c6bbb6279aaa2470a6",
      "completed_at": "2026-05-29T11:37:25Z",
      "doc_hash_after": "sha256:4e7d6bbe3d67eb4d2124128503389fc92fa784a5fc69dc642d3ed6b7c9d0e000"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, no live Codex Dock app or device-config model can represent "one host with multiple endpoints." A comma-separated configured host list may still exist as a list syntax, but each entry becomes its own `DockHostConfiguration` with exactly one `DockRelayEndpoint`.

## 0.2 In scope

- Delete the Swift multi-endpoint host model:
  - `DockHostConfiguration.endpoints`
  - `DockHostConfiguration.webSocketURLs`
  - `DockHostConfiguration.displayEndpointList`
  - `DockHostConfiguration.init(endpoints:relayInstanceID:)`
  - endpoint-alias error and validation paths
- Keep `DockRelayEndpoint` as a strict `host:port` value object.
- Change `HostRegistry.fromEnvironment` so `CODEX_DOCK_HOSTS=a:4510,b:4510` means two hosts, not one host with two endpoints.
- Change saved app config from an endpoint-list contract to a host-list contract. This is a clean cutover, not a migration bridge.
- Remove phone-side `relayInstanceID` from persisted config, launch env verification, device config JSON, host grouping, and duplicate detection.
- Keep relay-side host identity for relay status and Bonjour metadata where it belongs, but treat it as remote metadata, not as a phone-side grouping key.
- Make `AppServerHostConnector`, thread detail sessions, dock loads, archive loads, and relay transcription connect to exactly `host.endpoint`.
- Update host settings so adding a relay always creates a separate host row unless it edits the selected host row.
- Update Makefile device install/config targets so both physical phones receive two independent hosts.
- Update Swift tests, Node tests, README, and live repo instructions that currently describe saved relay endpoints, relay instance IDs, aliases, or fallback endpoints.

## 0.3 Out of scope

- No new product capability beyond the simple host model.
- No new discovery protocol.
- No new relay service topology.
- No new authentication model.
- No raw app-server phone path.
- No timeboxed compatibility bridge for old saved `endpoints` JSON.
- No archival "legacy" files, old model copies, or deprecated code left beside the live path.

## 0.4 Definition of done (acceptance evidence)

- Type-level evidence: `DockHostConfiguration` has exactly one stored endpoint and no stored endpoint array.
- Runtime-path evidence: `AppServerHostConnector` has no endpoint fallback loop; it connects once to `host.endpoint` and fails loudly if that endpoint fails.
- Config evidence: device relay config JSON and host env verification no longer require or write phone-side `relayInstanceID`.
- Physical-device config evidence: the iPhone 17 Pro and iPhone 14 Makefile defaults contain two separate host entries for the `Amir-M5` and `Home` routes, not one relay with endpoint aliases.
- UI evidence: host rows display one endpoint string per host row.
- Test evidence:
  - `rtk swift test --filter DockConfigurationTests`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk npm test`
  - `rtk make sim-config-verify SIM='iPhone 17'`
- App-build evidence when implementation touches launch/config behavior:
  - `rtk make app SIM='iPhone 17'`

## 0.5 Key invariants (fix immediately if violated)

- A host has exactly one endpoint.
- A host endpoint is only `host:port`; no scheme, path, query, credentials, or secret.
- A host list is a list of hosts, not a list of aliases for one host.
- `Amir-M5` and `Home` are never collapsed into one logical host.
- Endpoint connection failure is host failure, not a trigger to try another endpoint from the same host.
- Git is the history. Delete obsolete code, tests, and docs instead of preserving old model copies.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct mental model: one relay host equals one endpoint.
2. Real deletion: remove endpoint arrays, alias merging, and fallback loops instead of hiding them.
3. Fail-loud behavior: if a configured host is down, that host is offline.
4. Minimal config: phone-side host config requires only host and port.
5. Existing path fit: keep the current `HostRegistry`, `DockRelayEndpoint`, Makefile, and device-config ownership boundaries where they still make sense.

## 1.2 Constraints

- `.env` remains user-owned and must not be rewritten.
- Phone config must not receive `OPENAI_API_KEY`, raw app-server bearer tokens, or raw `:4500` endpoints.
- The app-facing relay remains `:4510`.
- `project.yml` changes are not expected unless implementation changes target settings, permissions, Info.plist, or assets.
- Physical phone proof must use Makefile-owned install/config targets, not raw platform install commands.
- Existing dirty worktree changes outside this plan are user-owned and must not be reverted.

## 1.3 Architectural principles (rules we will enforce)

- The Swift type should make the bad state impossible: a `DockHostConfiguration` cannot hold more than one endpoint.
- The registry owns host lists; individual hosts do not own endpoint lists.
- The connector owns a single connection attempt to a host endpoint. Reconnect policy may still exist inside live detail transport, but not as same-host endpoint fallback.
- Device config writer and reader use the same simple host-list contract.
- Relay identity is observation, not configuration grouping.
- Tests should assert behavior and contracts, not absence of strings or doc inventory.

## 1.4 Known tradeoffs (explicit)

- Old saved multi-endpoint JSON will stop loading. That is intentional because this is a clean cutover.
- If `Amir-M5.local:4510` fails, the app will mark that host offline instead of silently trying `192.168.50.74:4510` as an alias. The user should see which host route failed.
- Display names may initially be endpoint-derived until a relay response provides richer metadata. The implementation must not use that metadata to merge rows.
- Keeping `CODEX_DOCK_HOSTS` as a comma-separated list is acceptable because it represents a host list, not a per-host endpoint list.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The app already has a `HostRegistry`, but each `DockHostConfiguration` can own `[DockRelayEndpoint]`. The environment, saved config, Host settings, bootstrap discovery, connector, device config, and tests all know about endpoint arrays.

## 2.2 What's broken / missing (concrete)

- The app can display one host row with two URLs.
- `HostRegistry.fromEnvironment` collapses comma-separated `CODEX_DOCK_HOSTS` into one host when a relay instance ID exists.
- `RelayBootstrapStore` merges environment, saved, and discovered endpoints into aliases for one relay identity.
- `AppServerHostConnector` falls through to the next endpoint after transport-style failures.
- Makefile physical config gives each phone a comma-separated endpoint list plus one relay instance ID.
- Tests assert the old behavior, so they would protect the wrong model.

## 2.3 Constraints implied by the problem

- The fix must be structural. A UI-only display change would leave the bad state alive.
- The saved config and device config contracts must move with the Swift model.
- Any surviving use of "endpoint aliases" or same-host endpoint fallback is a bug.
- Docs must be updated or deleted in the same implementation because stale runbook text would reinstall the wrong model.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
Research result: this is a repo-local contract refactor. The authoritative path starts in `DockHostConfiguration`, flows through `HostRegistry`, `RelayBootstrapStore`, `FileLocalDockConfigurationStore`, `HostSettingsStore`, `AppServerHostConnector`, the Makefile/device-config writer, and then into tests/docs. External research is not needed because the goal is to delete a repo-specific configuration shape, not design a new protocol.

Key internal anchors:

- `CodexDock/Configuration/DockHostConfiguration.swift` currently makes the invalid state possible with `public let endpoints: [DockRelayEndpoint]`, `webSocketURLs`, `displayEndpointList`, and `init(endpoints:relayInstanceID:)`.
- `CodexDock/Configuration/HostRegistry.swift` currently parses `CODEX_DOCK_HOSTS` into endpoints and wraps them in one `DockHostConfiguration`, which collapses a host list into one host.
- `CodexDock/Configuration/RelayDiscovery.swift` persists `LocalRelayEndpointList.endpoints` and turns all saved endpoints into one `DockHostConfiguration`.
- `CodexDock/Configuration/RelayBootstrapStore.swift` currently merges environment, saved, and Bonjour-discovered endpoints into one host when IDs match.
- `CodexDock/AppServer/AppServerHostConnector.swift` loops through `host.endpoints` and retries the next endpoint on transport-style errors.
- `CodexDock/State/HostSettingsStore.swift` treats adding a host to a single relay-identity host as adding an alias endpoint.
- `Makefile` currently names `DEVICE_RELAY_ENDPOINTS`, `IPHONE_17_PRO_RELAY_ENDPOINTS`, and `IPHONE_14_RELAY_ENDPOINTS`, then writes them as one saved config with one relay instance ID.
- `scripts/device-relay-config.mjs` writes JSON shaped as `{ endpoints: [...] }` and verifies `relayInstanceID`.
- `scripts/codex-dock-host-service-env.mjs` merges generated relay endpoints into `CODEX_DOCK_HOSTS`; this must keep host-list behavior without preserving alias semantics.
- `scripts/codex-dock-host-service.mjs` app config currently emits one host endpoint and one relay instance ID. The app-facing `relayInstanceID` should be removed, while relay service-side `hostId` remains.
- Current tests explicitly assert old behavior: fallback endpoint preservation, alias grouping, bootstrap alias merging, host settings alias addition, app-server fallback across endpoints, transcription fallback across endpoints, and device config multiple-endpoint output.
<!-- arch_skill:block:research_grounding:end -->

## 3.1 External anchors (papers, systems, prior art)

No external research is needed. This is an internal configuration-contract refactor governed by the repo's own Makefile, Swift model, Node config writer, and stated product goal.

## 3.2 Internal ground truth (code as spec)

- Canonical Swift owner path: `CodexDock/Configuration/DockHostConfiguration.swift` and `CodexDock/Configuration/HostRegistry.swift`.
- Saved app config owner path: `CodexDock/Configuration/RelayDiscovery.swift`.
- Bootstrap and discovery owner path: `CodexDock/Configuration/RelayBootstrapStore.swift` and `CodexDock/Configuration/RelayDiscovery.swift`.
- Runtime connection owner path: `CodexDock/AppServer/AppServerHostConnector.swift`, reused by `AppServerDockClient`, `AppServerThreadDetailSession`, and `RelayRealtimeTranscriptionClient`.
- Host editing owner path: `CodexDock/State/HostSettingsStore.swift` and `CodexDock/Features/Hosts/HostsView.swift`.
- Device config owner path: `scripts/device-relay-config.mjs`, `scripts/device-relay-config.test.mjs`, and Makefile `device-config` / `device-config-verify` targets.
- Generated host env owner path: `scripts/codex-dock-host-service-env.mjs` and `scripts/codex-dock-host-service.mjs`.
- Live docs and instructions: `README.md`, `AGENTS.md`, and Makefile help text.
- Test surfaces that must be rewritten, not just deleted:
  - `CodexDockTests/DockConfigurationTests.swift`
  - `CodexDockTests/DockStoreTests.swift`
  - `CodexDockTests/AppServerClientTests.swift`
  - `CodexDockTests/DockStoreScopeTests.swift`
  - `CodexDockTests/AppConnectivityStoreTests.swift`
  - `CodexDockTests/ThreadDetailStoreTests.swift`
  - `scripts/device-relay-config.test.mjs`
  - `scripts/codex-dock-host-service.test.mjs`

## 3.3 Decision gaps that must be resolved before implementation

None. The compatibility posture is a clean cutover with `fallback_policy: forbidden`. Old saved multi-endpoint JSON, endpoint aliases, and same-host fallback loops are not supported end states.

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
Current architecture summary: the repo has a host registry in name, but several core types still treat a host as a relay identity plus a list of reachable endpoints. The app saves, displays, edits, connects, and tests that endpoint list as live behavior.

Runtime as-is:

1. `HostRegistry.fromEnvironment` parses `CODEX_DOCK_HOSTS` as a list of endpoints.
2. It creates one `DockHostConfiguration(endpoints:relayInstanceID:)`.
3. `DockHostConfiguration.id` becomes `relayInstanceID` when present, so multiple endpoints can share one logical host row.
4. `RelayBootstrapStore` loads saved endpoints, merges newly discovered endpoints into the existing host, then persists the flattened endpoint list.
5. `HostSettingsStore.saveHost(replacing:nil,...)` adds a new endpoint alias when exactly one relay-identity host exists.
6. `AppServerHostConnector` loops through `host.endpoints` and tries the next endpoint after offline/transport-like failures.
7. UI view models display `displayEndpointList`, so one row can show comma-separated endpoints.
<!-- arch_skill:block:current_architecture:end -->

## 4.1 On-disk structure

- Swift config:
  - `CodexDock/Configuration/DockHostConfiguration.swift`
  - `CodexDock/Configuration/HostRegistry.swift`
  - `CodexDock/Configuration/RelayDiscovery.swift`
  - `CodexDock/Configuration/RelayBootstrapStore.swift`
- Swift runtime users:
  - `CodexDock/AppServer/AppServerHostConnector.swift`
  - `CodexDock/State/AppServerDockClient.swift`
  - `CodexDock/State/AppServerThreadDetailSession.swift`
  - `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`
  - `CodexDock/State/HostSettingsStore.swift`
  - `CodexDock/State/DockStore.swift`
  - `CodexDock/State/AppConnectivityStore.swift`
  - `CodexDock/State/ArchiveStore.swift`
- Node/device config:
  - `scripts/device-relay-config.mjs`
  - `scripts/codex-dock-host-service-env.mjs`
  - `scripts/codex-dock-host-service.mjs`
  - `Makefile`
- Tests and docs:
  - `CodexDockTests/**`
  - `scripts/*.test.mjs`
  - `README.md`
  - `AGENTS.md`

## 4.2 Control paths (runtime)

- Launch env path: `Makefile` writes `.codex-dock/host.env`; simulator launch passes `CODEX_DOCK_HOSTS` and `CODEX_DOCK_RELAY_INSTANCE_ID`; `RelayBootstrapStore.start()` calls `HostRegistry.fromEnvironment`.
- Saved config path: app reads `Library/Application Support/CodexDock/relay-config.json`; `FileLocalDockConfigurationStore` decodes `LocalRelayEndpointList`; bootstrap turns the saved endpoint array into one host.
- Bonjour path: `BonjourRelayDiscovery` publishes `DiscoveredRelay`; relay ID becomes `DiscoveredRelay.id`; bootstrap uses it to upsert/merge endpoints.
- Manual host path: setup and Host settings both create `DockRelayEndpoint` values, but Host settings can add those values as aliases to an existing relay-identity host.
- Connection path: Dock, Archive, Thread detail, and voice transcription all rely on `AppServerHostConnector`, which owns the endpoint fallback loop.

## 4.3 Object model + key abstractions

- `DockRelayEndpoint`: strict `host:port` value object. This part is aligned with the goal.
- `DockHostConfiguration`: currently stores `[DockRelayEndpoint]` and optional `relayInstanceID`. This is the main invalid state.
- `HostRegistry`: stores `[DockHostConfiguration]` but currently accepts one host that owns many endpoints.
- `LocalRelayEndpointList`: persisted saved config shaped around endpoint arrays, not hosts.
- `DiscoveredRelay`: carries `relayInstanceID` from Bonjour TXT and currently uses it as identity.
- `AppServerHostConnector`: bridges a logical host to a connected `AppServerClient`, currently by iterating endpoints.

## 4.4 Observability + failure behavior today

- Logs report endpoint counts in Dock load and voice transcription.
- Connector logs each endpoint attempt under one logical host ID.
- A failed primary endpoint can be hidden by a successful fallback endpoint.
- Relay status validation checks expected `relayInstanceID` only when the local host config carries one.
- Connectivity UI reports per logical host, so endpoint alias failure is not represented as a separate host failure.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current host row can effectively be:

```text
Amir-M5
amir-m5.fairy-salmon.ts.net:4510, home.fairy-salmon.ts.net:4510
Online
```

That is the user-visible model this plan deletes.

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
Target architecture summary: `DockHostConfiguration` becomes a one-endpoint type. A configured list is represented only by `HostRegistry.hosts`. Host identity defaults to the endpoint's stable `host:port` ID; relay-reported identity can decorate or validate a connected relay later, but cannot collapse host entries.

Runtime to-be:

1. `CODEX_DOCK_HOSTS=a:4510,b:4510` parses into two `DockHostConfiguration` values.
2. Saved app config stores `hosts: [{ host, port }, ...]`, not `endpoints`.
3. Bonjour discovery inserts or updates one host for the discovered endpoint. Relay TXT identity does not merge rows.
4. Manual add creates a separate host row; edit replaces only the selected row.
5. Runtime connection uses exactly `host.endpoint`.
6. UI displays exactly one endpoint per host row.

Pass 2 hardening: host identity and relay display identity are intentionally separate. The app's stable host key is the endpoint ID (`host:port`) because that is the only phone-side config data. A relay-reported name such as `Amir-M5` or `Home` may be shown as observed display metadata after Bonjour, `/statusz`, or JSON-RPC initialize sees it, but it must never become the key used to merge two configured hosts.
<!-- arch_skill:block:target_architecture:end -->

## 5.1 On-disk structure (future)

- Keep `DockRelayEndpoint` in `DockHostConfiguration.swift`.
- Refactor `DockHostConfiguration` to:
  - `public let endpoint: DockRelayEndpoint`
  - no endpoint array
  - no `relayInstanceID`
  - no `webSocketURLs`
  - no `displayEndpointList`
- Refactor `HostRegistry.fromEnvironment` to map parsed endpoint entries into `hosts`.
- Replace `LocalRelayEndpointList` with a host-list saved config type, for example `LocalRelayHostList`.
- Update Node device config to write and verify host lists, not endpoint lists.
- Update docs and tests in place. Do not add `legacy`, `old`, `deprecated`, backup, or compatibility files.

## 5.2 Control paths (future)

- Environment:
  - Parse `CODEX_DOCK_HOSTS` as a host list.
  - Do not require `CODEX_DOCK_RELAY_INSTANCE_ID` for app bootstrap or simulator config verification.
- Saved config:
  - Decode only the new host-list contract.
  - Empty host list remains allowed for "no saved relay".
  - Old endpoint-list JSON fails loudly and is replaced by Makefile/device config on next install/config write.
- Discovery:
  - Discovered endpoint becomes one host.
  - Same endpoint updates/replaces same endpoint host.
  - Same relay ID with different endpoint remains a separate host unless the endpoint is the same.
- Connection:
  - `connectAndInitialize`, `withConnectedClient`, and `retainConnectedClient` create one client for `host.endpoint`.
  - No "retry next endpoint" helper remains.

## 5.3 Object model + abstractions (future)

- `DockRelayEndpoint`: unchanged core parser/serializer for one `host:port`.
- `DockHostConfiguration`: one endpoint, display name from endpoint by default.
- `HostRegistry`: only place where a list of hosts exists.
- Saved config type: host-list storage matching `HostRegistry`.
- `DiscoveredRelay`: relay-reported identity remains metadata. Its `id` should not be used to merge different endpoints.
- `AppServerHostConnection`: still records `host`, `endpoint`, initialize response, and client. `endpoint` is always `host.endpoint`.
- Optional observed display metadata:
  - Source: Bonjour TXT `relay-id`, `/statusz` host identity, or initialize response.
  - Owner: connectivity or host-state view model layer, not `DockHostConfiguration`.
  - Rule: display-only. It cannot participate in duplicate checks, saved config identity, registry equality, or row merging.

## 5.4 Invariants and boundaries

- Boundary: parsing may accept comma-separated host lists, but construction of one host never accepts multiple endpoints.
- Boundary: phone-side config accepts host and port only; relay identity is not a required config field.
- Boundary: relay-side `CODEX_DOCK_REAL_HOST_ID` and `/statusz` identity remain Mac/Linux relay concerns.
- Boundary: endpoint failure reports against that host. It does not silently hop to another endpoint.
- Boundary: docs and logs use "hosts" for configured host lists and "endpoint" for the one `host:port` owned by one host.
- Boundary: `Amir-M5` and `Home` are real relays, not static phone-side config labels. The config still contains only the route (`host:port`); observed relay names can improve display once known.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Target host rows:

```text
amir-m5.fairy-salmon.ts.net:4510
amir-m5.fairy-salmon.ts.net:4510
Online

home.fairy-salmon.ts.net:4510
home.fairy-salmon.ts.net:4510
Offline
```

If relay display metadata is later shown, it must not collapse rows:

```text
Amir-M5
amir-m5.fairy-salmon.ts.net:4510

Home
home.fairy-salmon.ts.net:4510
```

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
Call-site audit result: implementation must touch both Swift and Node because the bad model is a shared app/device configuration contract. Swift-only cleanup would leave Makefile/device config reinstalling the old shape. Node-only cleanup would leave the app able to represent aliases.
<!-- arch_skill:block:call_site_audit:end -->

## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
|---|---|---|---|---|---|---|---|
| Swift config | `CodexDock/Configuration/DockHostConfiguration.swift` | `DockHostConfiguration.endpoints` | Host stores endpoint array | Delete stored array | Makes invalid state impossible | `endpoint: DockRelayEndpoint` only | `DockConfigurationTests` |
| Swift config | `CodexDock/Configuration/DockHostConfiguration.swift` | `webSocketURLs`, `displayEndpointList` | Exposes multiple URLs/list display | Delete | Prevents UI and callers from preserving alias model | `webSocketURL`, `endpoint.displayEndpoint` | `DockConfigurationTests`, `DockStoreTests` |
| Swift config | `CodexDock/Configuration/DockHostConfiguration.swift` | `init(endpoints:relayInstanceID:)` | Builds alias host | Delete | Prevents construction of one host with many endpoints | `init(endpoint:)`, `init(host:port:)` | Multiple Swift tests |
| Swift config | `CodexDock/Configuration/DockHostConfiguration.swift` | `relayInstanceID`, `validateRelayInstanceID` | Phone-side grouping and expected identity | Remove from host config | Config must require only host/port | Relay identity is response metadata only | `AppServerClientTests`, config tests |
| Swift registry | `CodexDock/Configuration/HostRegistry.swift` | `fromEnvironment` | Wraps endpoint list into one host | Map each endpoint to one host | Host list becomes real host list | `HostRegistry(hosts: endpoints.map(DockHostConfiguration.init))` | `DockConfigurationTests` |
| Saved config | `CodexDock/Configuration/RelayDiscovery.swift` | `LocalRelayEndpointList` | Persists endpoint array and relayInstanceID | Replace with host-list type | Saved contract must match runtime model | `{ "hosts": [{ "host": "...", "port": 4510 }] }` | `DockConfigurationTests` |
| Discovery | `CodexDock/Configuration/RelayDiscovery.swift` | `DiscoveredRelay.id` | Relay ID can identify row | Use endpoint ID for row identity; keep relay ID metadata if needed | Same relay ID must not merge different endpoints | `id == endpoint.id` | `DockConfigurationTests` |
| Bootstrap | `CodexDock/Configuration/RelayBootstrapStore.swift` | `useEndpoints`, `upsert`, `hosts(for:)` | Saves and merges endpoint arrays | Replace with `useHost` / `upsertHost` over one endpoint | Discovery/saved/env should add hosts, not aliases | Persist registry host list | `DockConfigurationTests` |
| Connector | `CodexDock/AppServer/AppServerHostConnector.swift` | endpoint loops | Retries next endpoint on transport failures | Delete loops and `shouldRetryNextEndpoint` | No per-host fallback | Connect exactly `host.endpoint` | `AppServerClientTests` |
| Dock client | `CodexDock/State/AppServerDockClient.swift` | load logging | Logs `endpoints=count` | Log endpoint string or host endpoint | Keeps diagnostics truthful | one endpoint per host | `DockStoreTests` if asserted |
| Thread detail | `CodexDock/State/AppServerThreadDetailSession.swift` | connector use | Gets fallback indirectly | No direct change beyond connector contract unless tests need update | Detail sessions must inherit no-fallback behavior | one endpoint | `AppServerClientTests`, `ThreadDetailStoreTests` |
| Voice | `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` | `endpointCount` logging | Logs endpoint count and inherits fallback | Remove endpoint count and rely on one endpoint | Voice must not fallback across aliases | one endpoint | `AppServerClientTests`, `ThreadDetailStoreTests` |
| Host settings | `CodexDock/State/HostSettingsStore.swift` | `singleRelayIdentityHost`, `updatedRelayIdentityHost` | Adds aliases to one host | Delete alias path | Add means separate host; edit means replace selected host | registry host list | `DockStoreTests` |
| UI model | `CodexDock/State/DockStore.swift` | `DockHostViewModel.endpoint` | Uses `displayEndpointList` | Use `host.endpoint.displayEndpoint` | One endpoint per row | single endpoint display | Projection/host tests |
| Hosts UI | `CodexDock/Features/Hosts/HostsView.swift` | `HostDraft(host:)` | Reads primary endpoint | Keep, now reads only endpoint | Fits new model | unchanged visible fields | UI compile/tests |
| Device config | `scripts/device-relay-config.mjs` | `parseEndpointList`, `buildRelayConfig` | Builds `{ endpoints, relayInstanceID }` | Build `{ hosts }`; rename helpers or semantics | Device config must be host list only | host-list JSON | `device-relay-config.test.mjs` |
| Host env | `scripts/codex-dock-host-service-env.mjs` | `mergeEndpoints` | Merges endpoint list and preserves old app env values | Make host-list merge semantics explicit; no app-facing relayInstanceID | Generated host env should be host list only | `CODEX_DOCK_HOSTS` only for app | `codex-dock-host-service.test.mjs` |
| Host service | `scripts/codex-dock-host-service.mjs` | `appConfigJSON`, `appConfigEnv` | Emits relayInstanceID to app config | Emit hosts only | Phone config needs only host/port | JSON `{ hosts: [...] }`, env `CODEX_DOCK_HOSTS=...` | `codex-dock-host-service.test.mjs` |
| Makefile | `Makefile` | `DEVICE_RELAY_ENDPOINTS`, iPhone endpoint vars | Treats phone config as endpoint alias list plus relay ID | Rename to host-list language and stop passing relay instance ID to device config | Physical config must install separate hosts | `DEVICE_RELAY_HOSTS` / `IPHONE_*_RELAY_HOSTS` | command behavior |
| README | `README.md` | Physical iPhone and service config sections | Says saved relay endpoints and relayInstanceID | Rewrite to one host entry per relay | Prevents wrong reinstall instructions | host-list docs | docs readback |
| Agent instructions | `AGENTS.md` | Physical endpoint expectations | Requires relayInstanceID and endpoint aliases | Update to simple host-list expectations | Live repo instruction must not contradict plan | host-only phone config | docs readback |
| Tests | `CodexDockTests/**`, `scripts/*.test.mjs` | alias/fallback tests | Assert old model | Rewrite to assert separate hosts and fail-loud single endpoint | Tests should guard new contract | behavior-level checks | Swift/npm tests |

## 6.2 Migration notes

- Compatibility posture: clean cutover.
- Delete list:
  - `DockHostConfiguration.endpoints`
  - `DockHostConfiguration.webSocketURLs`
  - `DockHostConfiguration.displayEndpointList`
  - `DockHostConfiguration.init(endpoints:relayInstanceID:)`
  - `DockHostConfigurationError.missingRelayInstanceIDForEndpointAliases`
  - Swift alias merge helpers in `RelayBootstrapStore` and `HostSettingsStore`
  - endpoint fallback loops and `shouldRetryNextEndpoint` in `AppServerHostConnector`
  - phone-side `relayInstanceID` fields in saved config and device config
  - fallback/alias tests that no longer describe valid behavior
- Replacement contract:
  - Host list syntax can remain comma-separated for environment variables and CLI args.
  - Saved JSON uses `hosts`, not `endpoints`.
  - Each host item is only `{ host, port }`.
- Adjacent surfaces included now:
  - Swift app model
  - saved config reader/writer
  - device config writer/verifier
  - Makefile physical defaults
  - generated app-safe host env
  - host settings UI/store
  - tests
  - README and AGENTS
- Explicitly out of scope:
  - raw relay internals that talk about live upstream app-server endpoints, because those are Mac-side raw Codex session endpoints, not phone-side host endpoints.
  - OpenAI Realtime transcription endpoint config, because it is provider-side and unrelated to Dock relay host config.

Pass 2 consolidation notes:

- Do not create a second host identity layer to preserve friendly names. If observed relay names are displayed, keep them outside saved config and outside `DockHostConfiguration`.
- Do not keep `relayInstanceID` as an optional field on `DockHostConfiguration` "just for validation." That would preserve the old grouping concept. Validation can compare observed metadata at connection time without putting the expected value in phone config.
- Do not leave `parseEndpointList` named as endpoint-list business logic unless its remaining role is clearly host-list parsing at the registry/config boundary. Rename if needed so the code does not teach the old model.
- Device defaults must still carry both real relay routes:
  - iPhone 17 Pro: `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`
  - iPhone 14: `Amir-M5.local:4510` and `192.168.50.74:4510`

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. No fallbacks/runtime shims - the system must work correctly or fail loudly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates.

## Phase 1 - Swift host model cutover and no-fallback runtime path

Goal

Make the invalid Swift state impossible and prove the main runtime seam: one `DockHostConfiguration` has one endpoint, and connection code no longer falls across endpoint aliases.

Work

This is the first real slice because it cuts the canonical owner type and the runtime connector together. It is allowed to touch all Swift callers needed to keep the package compiling because partial preservation of `host.endpoints` would be a parallel path.

Checklist (must all be done)

- Refactor `DockHostConfiguration` so it stores exactly `endpoint: DockRelayEndpoint`.
- Delete the endpoint-array initializer, `webSocketURLs`, `displayEndpointList`, phone-side `relayInstanceID`, relay-instance mismatch validation on local config, and endpoint-alias error case.
- Keep `DockRelayEndpoint` validation for strict `host:port` values and raw `:4500` rejection.
- Refactor `HostRegistry.fromEnvironment` so each parsed `CODEX_DOCK_HOSTS` item becomes one `DockHostConfiguration`.
- Replace `LocalRelayEndpointList` with a saved host-list contract using `hosts: [{ host, port }]`.
- Make old saved endpoint-list JSON fail loudly; do not add a bridge decoder.
- Refactor `RelayBootstrapStore` so saved, manual, and discovered hosts are inserted or updated by endpoint ID, not merged by relay identity.
- Refactor `DiscoveredRelay` identity so different endpoints with the same relay TXT identity stay separate hosts.
- Refactor `HostSettingsStore` so add creates a host row and edit replaces one selected host row. Delete alias-specific helpers.
- Refactor `AppServerHostConnector` to connect to exactly `host.endpoint`; delete endpoint fallback loops and retry-next-endpoint helper logic.
- Update `AppServerDockClient`, `AppServerThreadDetailSession`, and `RelayRealtimeTranscriptionClient` for the one-endpoint connector contract and truthful logging.
- Update `DockHostViewModel`, `AppConnectivityStore`, `ArchiveStore`, and any affected UI/store code to show one endpoint per host.
- Rewrite Swift tests that currently assert alias grouping, endpoint fallback, or phone-side relay-instance config.

Verification (required proof)

- `rtk swift test --filter DockConfigurationTests`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`

Docs/comments (propagation; only if needed)

- Add a short code comment only at the new single-host contract boundary if the endpoint-key versus observed-relay-name split is otherwise easy to misuse.

Exit criteria (all required)

- Swift code compiles with no caller depending on a host endpoint array.
- `HostRegistry.fromEnvironment(["CODEX_DOCK_HOSTS": "a:4510,b:4510"])` creates two hosts.
- App-server connection, thread detail, and voice transcription tests no longer expect same-host endpoint fallback.
- Saved Swift app config writes and reads host lists, not endpoint lists.
- Adding a host in Host settings cannot append an endpoint alias to an existing host.

Rollback

Do not mix old and new Swift contracts. If this phase fails before completion, restore the pre-phase Swift contract from git and retry the phase as one coherent cutover.

## Phase 2 - Generated host/device config cutover

Goal

Make simulator and physical phone config write the same simple host-list contract the Swift app now reads.

Work

This phase expands from in-app correctness to the Makefile and Node tools that install real config onto simulators and devices.

Checklist (must all be done)

- Refactor `scripts/device-relay-config.mjs` from endpoint-list JSON to host-list JSON.
- Remove phone-side `relayInstanceID` from device config write, verify, and verify-env paths.
- Rename command variables and helper names where needed so they say "hosts" instead of "relay endpoints" when the value represents a host list.
- Keep strict `host:port` validation and `:4500` rejection.
- Update `scripts/device-relay-config.test.mjs` to assert two separate hosts for multi-entry input.
- Update `scripts/codex-dock-host-service.mjs` app-facing JSON/env output so app config contains host/port only.
- Update `scripts/codex-dock-host-service-env.mjs` so `CODEX_DOCK_HOSTS` merge behavior is host-list behavior, not alias-list behavior.
- Update `scripts/codex-dock-host-service.test.mjs` to match the new app-safe config.
- Update Makefile defaults and targets:
  - replace `DEVICE_RELAY_ENDPOINTS` language with host-list language;
  - keep the iPhone 17 Pro routes `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`;
  - keep the iPhone 14 routes `Amir-M5.local:4510` and `192.168.50.74:4510`;
  - stop passing a phone-side relay instance ID into device config.
- Update Makefile output strings so they say hosts/host list where that is the actual contract.

Verification (required proof)

- `rtk npm test`
- `rtk make sim-config-verify SIM='iPhone 17'`

Docs/comments (propagation; only if needed)

- Keep Node helper comments minimal. Prefer clear function names over comments that preserve old terminology.

Exit criteria (all required)

- Device config writer outputs host-list JSON without `relayInstanceID`.
- Host-env verification succeeds using only `CODEX_DOCK_HOSTS`.
- Physical device Makefile defaults configure two independent hosts for both current phones.
- Node tests no longer assert endpoint aliases or relay-instance app config.

Rollback

If Node/Makefile config cannot be completed, stop before device install proof and restore Phase 2 files from git. Do not reintroduce a Swift compatibility bridge.

## Phase 3 - Live docs, instructions, and final proof

Goal

Delete stale live instructions and verify that the repo now teaches and proves the new model end to end.

Work

This phase removes the remaining ways a future run could reinstall or re-explain the old alias model. It does not preserve stale docs for posterity.

Checklist (must all be done)

- Update `README.md` so simulator, service, and physical-device sections describe one host entry per relay and one endpoint per host.
- Update `AGENTS.md` so repo instructions no longer require phone-side `relayInstanceID` or endpoint aliases.
- Update Makefile help text if any command description still says saved relay endpoints when it means host list.
- Update this plan's execution status only after implementation begins; do not turn Section 7 into a second worklog.
- Run the full planned verification set that is available in the local environment.
- If Xcode, simulator, device tooling, signing, services, or physical devices block any check, record the exact skipped command and exact blocker.

Verification (required proof)

- `rtk swift test --filter DockConfigurationTests`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk npm test`
- `rtk make sim-config-verify SIM='iPhone 17'`
- `rtk make app SIM='iPhone 17'`
- `rtk make device-config-verify-all` when device access is available
- `rtk make device-install-all` only when physical install proof is explicitly in reach and devices/signing are available

Docs/comments (propagation; only if needed)

- Delete or rewrite stale live docs and instructions. Do not leave legacy explanations beside current instructions.

Exit criteria (all required)

- README and AGENTS agree with the new one-endpoint-per-host model.
- Makefile help and output do not teach endpoint aliases.
- The final verification report names every command run, every command skipped, and each exact blocker if a check could not run.
- No implementation work remains in the approved scope.

Rollback

If docs or final proof uncover a missed implementation surface, reopen the relevant earlier phase rather than patching docs around the miss.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. Prefer existing credible checks that prove the app and config contracts really changed. Do not add deletion-proof tests, stale-term grep gates, repo-structure policing, or doc-inventory checks.

## 8.1 Unit tests (contracts)

- `rtk swift test --filter DockConfigurationTests`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk npm test`

## 8.2 Integration tests (flows)

- `rtk make sim-config-verify SIM='iPhone 17'`
- `rtk make app SIM='iPhone 17'` after implementation reaches app launch/config behavior.

## 8.3 E2E / device tests (realistic)

- `rtk make device-config-verify-all` after physical config code changes.
- `rtk make device-install-all` only when the implementation is ready for physical phone proof and devices/signing are available.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Clean cutover. Regenerated simulator and physical device config replaces old saved config. No runtime bridge is planned for previously saved multi-endpoint JSON.

## 9.2 Telemetry changes

Update log messages that currently report endpoint counts so they report one endpoint per host. Keep redaction behavior unchanged.

## 9.3 Operational runbook

README, Makefile help, device install messages, and repo instructions must describe host lists and one endpoint per host. They must stop saying "saved relay endpoints" when that wording implies one host owns many endpoints.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: self-integrator cold read pass 1, self-integrator cold read pass 2
- Scope checked:
  - frontmatter, TL;DR, North Star, Section 7, verification, rollout, and decision log
  - research, current architecture, target architecture, call-site audit, and Section 7
  - compatibility posture, fallback policy, delete list, docs propagation, and phase exit criteria
- Findings summary:
  - The artifact consistently chooses a clean cutover with `fallback_policy: forbidden`.
  - The artifact consistently treats `CODEX_DOCK_HOSTS` as a host-list syntax, not a per-host endpoint-list model.
  - The only wording risk was "name two separate host entries," which could imply static friendly names in phone config.
- Integrated repairs:
  - Reworded physical-device acceptance evidence to say the defaults "contain" two host entries for the real relay routes.
  - Added an intent-derived decision that `Amir-M5` and `Home` display names are observed metadata, not phone-side config fields.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-29 - User-approved direction: delete multi-endpoint host model

Context

The source goal document says each relay host should have exactly one endpoint, no endpoint list, no fallback endpoints, no aliases, and no multiple-URLs-per-host model.

Options

- Preserve the old endpoint-list contract and hide it in UI.
- Add a compatibility bridge while introducing a new simple host model.
- Delete the old model and use one endpoint per host everywhere.

Decision

Delete the old model and use one endpoint per host everywhere.

Consequences

Old saved multi-endpoint config is not a supported runtime contract. Implementation must update all code, tests, and live docs that currently preserve or teach endpoint aliases.

Follow-ups

Run ArcStep auto-plan to fill research, deep-dive, phase-plan, and consistency-pass sections before implementation.

## 2026-05-29 - Intent-derived: relay display names do not belong in phone config

Blocker:

The source goal says `Amir-M5` and `Home` should be separate hosts, while it also says per-host configuration should require nothing beyond host and port. That could be misread as requiring static friendly names in phone config.

Consulted:

Section 0.2, Section 0.5, TL;DR, Section 5.3, Section 5.4, and Appendix A.

Intent says:

The host config must stay simple: one host entry per relay and one endpoint per host, with no per-host config beyond host and port.

Decision:

Use endpoint ID (`host:port`) as the stable phone-side host key. `Amir-M5` and `Home` can appear as observed relay display metadata after Bonjour, `/statusz`, or initialize sees those names, but the names cannot be saved config fields and cannot merge rows.

Consequences:

The implementation must keep relay identity out of `DockHostConfiguration`, saved phone config, device config JSON, and duplicate checks. Any display-name enrichment must live outside the registry identity path.

# Appendix A) Imported Notes (source goal; preserved)

This section preserves the original goal note that was converted into this canonical plan.

## Goal Behavior

- Each relay host should have exactly one endpoint.
- A host endpoint should be only a host plus a port.
- There should not be a list of endpoints on a host.
- There should not be fallback endpoints on a host.
- There should not be endpoint aliases on a host.
- There should not be a multiple-URLs-per-host model.
- The app should treat each relay as its own host.
- `Amir-M5` should be one host.
- `Home` should be one host.
- `Amir-M5` and `Home` should not be collapsed into one logical host.
- `Amir-M5` and `Home` should not share one host row with two URLs listed.
- The iPhone 17 Pro should receive `Amir-M5` and `Home` as two separate hosts.
- The iPhone 14 should receive `Amir-M5` and `Home` as two separate hosts.
- The per-host configuration should not require anything beyond host and port.
- The host list should be simple: one host entry per relay, one endpoint per host.

## Non-Goals

- This document does not define an implementation plan.
- This document does not diagnose current behavior.
- This document does not assign phases, owners, tests, or code changes.

# Appendix B) Conversion Notes

- Converted the original goals note into the canonical ArcStep plan shape in place because the user named this file as the planning artifact.
- Preserved the exact source goal behavior in Appendix A.
- Treated the user's current request as the North Star approval to proceed with planning rather than stopping at draft status.
