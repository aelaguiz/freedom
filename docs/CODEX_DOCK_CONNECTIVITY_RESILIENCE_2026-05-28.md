---
title: "Codex Dock - Connectivity Resilience - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: phased_refactor
related:
  - docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md
  - docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md
  - docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md
  - README.md
  - docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
  - docs/EPIC_CODEX_DOCK_MVP_2026-05-27.md
---

# TL;DR

Outcome: make Codex Dock resilient enough that short-lived network drops, relay restarts, upstream app-server restarts, app background/resume cycles, and stale live-detail sessions become visible, automatically recoverable states instead of silent dead air. The app must show one compact connectivity indicator across Dock, Archive, Hosts, and Session detail, and the thread detail path must restore live updates after reconnect by resuming the same thread. The default user experience is transparent recovery: the client keeps trying while retry is safe, and the indicator tells the user what is happening.

Problem: connectivity truth is currently split across one-shot list loading, manual host tests, a raw socket actor state, and one thread-detail live-state pill. The raw client can notice some failures, but the UI usually cannot observe them, and no layer owns reconnect/backoff/rehydration or iOS background/foreground transitions as a first-class lifecycle.

Approach: make the app-server connection lifecycle observable, add a single app-level connectivity store for host status and refresh state, add root-owned scene lifecycle coordination for background/resume, teach thread detail to react to connection-state and app-lifecycle changes, and make the relay either preserve upstream live sessions or fail loudly so Swift can reconnect cleanly. Keep UI surfaces as consumers, not separate connectivity authorities.

Plan: first prove transport drops become visible to thread detail, then add reconnect and compact thread rehydration, then build `AppConnectivityStore` plus the root indicator, then add app background/resume suspend-and-recover behavior, then align relay and archive/host surfaces, then verify on unit, integration, and real simulator paths. In the top-level dock, this plan runs after Agents tab/live counts so it can consume the final `DockSessionQuery`/`DockSnapshot` tab-count shape, and before Realtime transcription so voice recovery can use the same lifecycle/status owner.

Non-negotiables: no silent stale state, no hidden fallback path, no second source of connectivity truth, no disconnected streams that leave UI loops idle forever, no late JSON-RPC responses killing healthy connections, no app-wide indicator owned by a tab-local view, and no background/resume path that either spins reconnect loops in the background or returns foreground claiming online without revalidation.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: not_required 2026-05-28 (repo-grounded auto-plan; no separate web external-research stage warranted)
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:0a92e5e9e4f9eba7fa513381edf68df6b214f7946ba55cd6389cf93fef32b38d",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T10:44:32Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:2908bc9bd816548dc5b7363961043352683a748497016c73e7e8fbed2ab13110",
      "completed_at": "2026-05-28T10:45:20Z",
      "doc_hash_after": "sha256:f500152a52b3892a826d624f005b13f5991ca2a8d68d5cde60c1f536ad06b612"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:45:24Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:f500152a52b3892a826d624f005b13f5991ca2a8d68d5cde60c1f536ad06b612",
      "completed_at": "2026-05-28T10:47:28Z",
      "doc_hash_after": "sha256:cf9b20783ad4025f16b95f87ce853ff3f687c1428fa90d024e46aba85b07cbd4"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:47:38Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:cf9b20783ad4025f16b95f87ce853ff3f687c1428fa90d024e46aba85b07cbd4",
      "completed_at": "2026-05-28T10:48:04Z",
      "doc_hash_after": "sha256:fe8efefb4a86e448b2415108726efea0c8169a1ef77f6adac3fb0e82e9fd8fa3"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T10:48:23Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:fe8efefb4a86e448b2415108726efea0c8169a1ef77f6adac3fb0e82e9fd8fa3",
      "completed_at": "2026-05-28T10:49:07Z",
      "doc_hash_after": "sha256:91b25a376724dcae47260268124d2948eeceb8aab861da6c8ff2371fd9f45720"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T10:49:12Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:91b25a376724dcae47260268124d2948eeceb8aab861da6c8ff2371fd9f45720",
      "completed_at": "2026-05-28T10:54:37Z",
      "doc_hash_after": "sha256:d46fe18e537c79a328f5bf15bd0a1067306336575ad003c2652ea82ad20eb94a"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this plan is implemented, Codex Dock has one observable connectivity lifecycle. When the phone loses and regains the app-server path, or when the app is backgrounded and later foregrounded, the app tells the user what is happening, retries with bounded backoff when active, restores list freshness, and re-resumes the open thread detail stream without requiring the user to leave and reopen the screen.

Recoverable drops must not require pressing a reconnect button, switching tabs, or navigating away. Manual action is a fallback only after retry exhaustion, unsafe recovery, missing configuration/authentication, or an unrecoverable protocol/server failure.

Backgrounding is an expected, accepted, recoverable lifecycle state. The app may quiesce live work while iOS backgrounded, but foreground resume must restart root refresh/check loops, reconnect/revalidate reachable hosts, and rehydrate any still-open thread detail before presenting the session as live again.

The claim is false if any of these happen:

- A dropped WebSocket leaves a detail screen showing `Live` while no notifications or server requests can arrive.
- A late JSON-RPC response after timeout or cancellation tears down an otherwise usable connection.
- Dock, Archive, Hosts, and Session detail disagree about whether the configured host is online, checking, stale, partial, or offline.
- The global indicator disappears on any primary app screen.
- Relay upstream failure strands the downstream Swift connection without either re-resuming upstream or making Swift reconnect.
- Relay attention probing or list limiting regresses into large full-resume payloads or hides live loaded rows behind stored history.
- A recoverable drop requires manual user action before the app retries and rehydrates.
- Returning from background leaves stale content labeled `Online` or a detail screen labeled `Live` before foreground revalidation/rehydration succeeds.
- Backgrounding is treated as an unrecoverable error, or the app spins retry/check loops while iOS is backgrounded.

## 0.2 In scope

- App-server client lifecycle: observable connection state, state stream, retry/backoff, receive-loop terminal events, close/error classification, request timeout/cancellation policy, and late-response handling.
- Thread detail lifecycle: live-state updates when transport drops, reconnect attempts, `thread/read` + `thread/turns/list` + `thread/resume` rehydration, request-card preservation, and stale/error UI when recovery fails.
- Transparent client-side recovery: reconnect and rehydrate automatically first; ask the user to act only after retry exhaustion, unsafe recovery, missing configuration/authentication, or unrecoverable protocol/server failure.
- App foreground/background lifecycle: SwiftUI scene-phase observation, background quiescing, foreground resume revalidation, root refresh/check loop restart, live detail rehydrate, relay discovery restart, and safe voice/composer behavior when iOS suspends the app.
- App-wide connectivity state: one root-owned status store across configured hosts, visible refresh/checking/offline/stale/partial states, last-check timestamps, and status derived from real load/test/detail outcomes.
- Global connectivity indicator: a compact colorized label/pill available across Dock, Archive, Hosts, and pushed Session detail screens, preferably mounted from `CodexDockRootView` rather than duplicated per tab.
- Dock/Archive/Hosts integration: keep existing content stores but feed their host outcomes into the shared connectivity model; fix Archive's all-offline empty-state ambiguity.
- Relay bootstrap integration: `CodexDockBootstrapView`, `RelayBootstrapStore`, Bonjour discovery, saved non-secret relay config, and manual relay fallback participate in lifecycle and connectivity state. Discovery/resume must not become a second root status path.
- Agents-plan integration: consume the final `DockSessionQuery(archived:sourceKinds:)`, scoped load failures, counted `DockSnapshot.tabs`, and tab-scoped sections. Do not build connectivity around the pre-Agents `loadSessions(for:archived:)` and `DockFilter` shape.
- Relay behavior: align `scripts/dock-relay.mjs` with the reconnect story because it is the phone endpoint in normal development and simulator runs.
- Verification: focused Swift unit tests, relay tests, existing `swift test`, existing `npm test`, and a real simulator/manual check using the current service targets.

## 0.3 Out of scope

- New product backends beyond the current Codex app-server and Dock relay.
- Account rotation, login/logout, AIMGR, team/admin status, and remote host provisioning.
- Long-running iOS background networking guarantees, background fetch, push notifications, or a background daemon/keepalive layer. This plan handles foreground resume after backgrounding; it does not require WebSockets to stay alive while the app is suspended.
- A new protocol or server replacement.
- Golden visual snapshot tests for the indicator.
- New doc-policing, repo-shape, or keyword-absence gates.

## 0.4 Definition of done (acceptance evidence)

- `AppServerClient` exposes connection-state changes as an async stream or equivalent observable contract, and tests prove connected, offline, error, explicit disconnect, late response, timeout, cancellation, and stream-terminal behavior.
- `ThreadDetailStore` observes connection state or terminal stream events, marks the view stale/reconnecting when live updates stop, retries with bounded backoff, re-runs read/turns/resume, and publishes live again after recovery.
- Scripted transient drops recover without manual user action while the UI reports reconnect progress and then returns to live/online when recovery succeeds.
- Scene lifecycle tests prove backgrounding pauses/cancels refresh and reconnect timers without reporting false unrecoverable errors, and foreground resume restarts checks, reconnects, and rehydrates open thread detail before returning to online/live.
- `CodexDockRootView` owns or receives one `AppConnectivityStore` and shows a compact global indicator across Dock, Archive, Hosts, and Session detail navigation.
- Dock, Archive, and Hosts update the shared connectivity status from real load/test outcomes without becoming competing sources of truth.
- Relay tests prove upstream close either reconnects/re-resumes or closes the downstream WebSocket in a way Swift handles, attention probing uses compact resume, and live loaded rows survive relay list limits.
- README or the relevant live runbook names the new status/recovery behavior and keeps `rtk make services`, `rtk make app-server-status`, and `rtk make dock-relay-status` current.
- `rtk swift test` and `rtk npm test` pass, and the `iPhone 17` simulator can show the global indicator against `ws://192.168.50.117:4510`, background the app, resume it, and return to online/live automatically when services remain reachable.

## 0.5 Key invariants (fix immediately if violated)

- Single source of truth: app-wide connectivity rolls up through `AppConnectivityStore`; tab stores and detail stores report observations into it but do not invent separate global truth.
- Fail loud: a stream ending or socket error must become visible UI state, not a quiet loop exit.
- Automatic first, user action last: recoverable disconnects retry and rehydrate on their own; user affordances appear only after automatic recovery is exhausted or unsafe.
- Background is not failure: expected iOS background suspension becomes `backgrounded`/`resuming` state, not an exhausted retry or protocol error.
- Reconnect has ownership: `AppServerClient` owns protocol/session retry mechanics; `ThreadDetailStore` owns thread-domain rehydration.
- No runtime fallback shims: keep `fallback_policy: forbidden`; the system either reconnects through the chosen path or reports why it cannot.
- No-phone-secret baseline: `DockHostConfiguration.bearerToken == nil` is a valid normal relay host. The app must not label the physical relay path as misconfigured merely because the phone has no bearer token.
- Auth status precision: `auth failed` applies only when a configured bearer/dev/hardening endpoint rejects credentials. It must not mean "the physical phone did not provide a relay bearer."
- UI stays passive: indicator views render state and send user actions; they do not poll sockets or run connection business logic.
- Existing behavior stays preserved: list loading, archive/unarchive, host editing/testing, request cards, voice composer, and newest-first timeline behavior must remain intact.
- Bound retries: reconnect uses bounded exponential backoff with jitter and cancellation, never unbounded tight loops.
- No background spin: root refresh, discovery, and reconnect timers pause or cancel while backgrounded and restart from root/lifecycle state on active foreground.
- Foreground claims need proof: the app must not publish `Online`/`Live` after resume until checks and thread rehydrate have succeeded.
- Relay and Swift agree: the relay cannot hide an upstream death while Swift believes live updates are still attached.

## 0.6 Cross-plan position

This is Phase 2 in `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`.

Inputs from earlier phases:

- the physical iPhone security baseline uses discovered/no-client-auth relay hosts with optional bearer config;
- the Agents plan owns typed origin, `DockSessionQuery`, scoped load failures, counted tabs, and relay live source filtering.

Outputs consumed by later phases:

- `AppServerClient` exposes observable lifecycle state and reconnect policy;
- `ThreadDetailStore` owns thread-domain rehydrate after drops;
- `AppConnectivityStore` is the only app-wide status rollup;
- root scene lifecycle coordinates Dock refresh, Relay discovery, open detail rehydrate, and voice safety;
- relay upstream death is recovered or fails loudly through downstream close.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct live truth: the UI must never claim live connectivity when the app can no longer receive updates.
2. Transparent recoverability: transient drops and foreground resume should reconnect and rehydrate without forcing manual navigation or a manual reconnect action.
3. Lifecycle elegance: backgrounding is an accepted suspended state; foreground resume is a normal recovery path, not a special failure.
4. Single source of truth: global connectivity status must be derived in one place.
5. Small architecture: use the existing app-server client, stores, tests, and service scripts instead of adding a new framework.
6. Clear user surface: the indicator should be compact, colorized, and always present without stealing attention from sessions.
7. Behavior preservation: existing Dock, Archive, Hosts, Session detail, and voice composer features must keep working.

## 1.2 Constraints

- SwiftUI state must update on the main actor; socket work remains outside UI views.
- `ThreadDetailStore` needs connection recovery without losing draft text, request cards, or currently displayed events.
- The relay on `ws://192.168.50.117:4510` is the current app endpoint, so robustness cannot stop at raw Swift code.
- Hosts may be partially reachable in multi-host mode; partial outage is a first-class state, not equivalent to all-offline.
- iOS foreground and foreground-resume behavior are implementation targets; long-running background networking is out of scope.
- Existing services should continue to use `rtk make services` and the `.codex-dock/` runtime files.

## 1.3 Architectural principles (rules we will enforce)

- Put connection mechanics in `CodexDock/AppServer/`, not inside SwiftUI views.
- Put app-wide connectivity rollup in `CodexDock/State/AppConnectivityStore.swift`.
- Put SwiftUI scene-phase translation in a root-owned lifecycle coordinator/store, not in tab-local views.
- Put visible indicator UI in a small reusable view under `CodexDock/Features/Status/`.
- Keep Dock/Archive/Hosts stores as content owners and event reporters, not global status owners.
- Treat receive-loop closure as data: it must produce a state transition.
- Treat foreground resume as data: it must produce revalidation and rehydrate work before live/online status returns.
- Treat thread rejoin as domain work: reconnecting the socket is not enough until `thread/resume` succeeds.
- Prefer typed states over string-only error propagation where the UI needs a decision.

## 1.4 Known tradeoffs (explicit)

- The plan keeps one-shot list/archive/test operations but records their outcomes in a shared store. It does not force all list loading through one persistent socket because thread detail is the high-risk live-update path.
- The first implementation slice adds lifecycle observability before full UI polish because the hidden failure mode is worse than the missing label.
- The relay may either reconnect upstream or close downstream fail-loudly. The preferred design is upstream re-resume when safe, but a fail-loud downstream close is acceptable if reconnecting upstream would duplicate or corrupt thread state.
- The plan does not try to keep WebSockets alive in the iOS background. It chooses deterministic quiesce-on-background and revalidate-on-foreground because that matches iOS process suspension and keeps retry semantics honest.
- Manual simulator verification remains part of final proof because the feature is partly user-visible, but unit and integration tests carry the core behavior.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The app can already connect to the Codex app-server, perform JSON-RPC requests, list sessions, open a thread detail view, receive live notifications and server requests, send text, answer supported request cards, archive/unarchive, test hosts manually, and refresh Dock rows every five seconds while the Dock view is active.

The SwiftUI app entry point and root view do not currently observe `scenePhase`. Backgrounding/resuming is therefore implicit iOS behavior rather than an owned app lifecycle.

Connectivity state exists, but it is local and fragmented:

- `AppServerClient.state` tracks raw socket state inside an actor.
- `DockStoreState` and `DockHostLoadStatus` infer online/offline from `thread/list`.
- `ThreadDetailLiveState` tracks one open detail view.
- `HostConnectionTestStatus` tracks manual host test results in the Hosts tab.

## 2.2 What's broken / missing (concrete)

- There is no reconnect/backoff policy in Swift.
- `ThreadDetailStore` can stop receiving live updates without the UI learning that the stream is dead.
- `AppServerClient` does not expose state transitions as a stream consumed by stores.
- Late responses after timeout/cancellation can be treated as unmatched responses and fail the entire connection.
- The Dock auto-refresh loop is owned by `DockView`, so status freshness is tied to one tab's view lifecycle.
- Archive can show "Archive empty" even when every host failed to load.
- Host settings tests are isolated from Dock/Archive/global status.
- The relay forwards a resumed upstream connection but does not own an upstream reconnect or a clear downstream failure policy.
- There is no app-wide connectivity indicator.
- There is no app-owned background/resume lifecycle: root refresh loops, relay discovery, live detail sessions, and retry timers do not intentionally pause on background or revalidate on active foreground.
- A WebSocket close caused by iOS backgrounding can look like an ordinary transport failure or silent stream end; there is no state that says "backgrounded, will resume."
- Voice capture and composer state have no explicit background transition contract; an in-progress recording must not leave an active audio session or auto-submit stale text after resume.

## 2.3 Constraints implied by the problem

- The fix must converge state ownership rather than add another standalone status pill.
- The raw transport and JSON-RPC session layers need clearer failure semantics before UI can be trusted.
- Reconnect must reestablish both the socket and the domain subscription created by `thread/resume`.
- Foreground resume must reestablish freshness explicitly; it cannot assume the socket, relay discovery, or root refresh task survived backgrounding.
- Multi-host status must preserve partial availability.
- The global indicator must mount above tab-local screens so it survives navigation.
- Root scene-phase observation must feed stores as lifecycle events without making SwiftUI views own connection business logic.
- Tests need to prove terminal and recovery behavior directly; "nothing crashed" is not enough.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- No separate web-based `external-research` stage is required for this auto-plan. The risk is local architecture, state ownership, and known app-server behavior already captured in this repo.
- Adopt the standard resilient-client shape: explicit connection state machine, bounded exponential backoff with jitter, terminal stream events, heartbeat/liveness checks where transport support is practical, and domain-level resubscription after reconnect. This applies because the current app already has a bidirectional WebSocket JSON-RPC client but lacks lifecycle ownership.
- Adopt the standard iOS scene-lifecycle shape: treat `.inactive` as transitional, treat `.background` as an expected quiesced/suspended state, cancel or pause foreground-only timers while backgrounded, and force revalidation plus domain rehydration when returning to `.active`.
- Reject a new sync service, background daemon, push-notification layer, background fetch, or long-running WebSocket keepalive for this plan. Those would add product scope and are not required for the user goal: backgrounding should be a clean recoverable state when the app is foregrounded again.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors (do not reinvent):
  - `CodexDock/AppServer/AppServerClient.swift` - owns the JSON-RPC request IDs, pending continuations, receive loop, raw connection state, notification stream, server-request stream, and `URLSessionWebSocketAppServerTransport`.
  - `CodexDock/AppServer/AppServerMethods.swift` - names the current app-server methods used by the client. The compact detail path already includes `thread/read`, `thread/turns/list`, and `thread/resume`.
  - `CodexDock/State/ThreadDetailStore.swift` - owns the open thread domain: thread identity, compact read/turns/resume flow, live/stale/closed state, event merge, active turn tracking, composer state, and request cards.
  - `CodexDock/State/DockStore.swift` - owns Dock content loading and per-host load outcomes through one-shot `AppServerDockClient.withClient` calls.
  - `CodexDock/State/ArchiveStore.swift` - mirrors Dock loading for archived rows but currently treats zero rows as empty even when all hosts failed.
  - `CodexDock/State/HostSettingsStore.swift` - owns manual host editing and test results, but its `HostConnectionTestStatus` is private to the Hosts tab.
  - `CodexDockApp/CodexDockApp.swift` - app entry point with a plain `WindowGroup` that mounts `CodexDockBootstrapView`.
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift` - owns relay discovery startup and transition into `CodexDockRootView`, but currently only starts discovery from `.task`.
  - `CodexDock/Features/Dock/DockView.swift` - owns `CodexDockRootView`, the root `TabView`, tab store wiring, Dock header plus button, and the view-bound five-second refresh loop.
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift`, `CodexDock/Configuration/RelayBootstrapStore.swift`, and `CodexDock/Configuration/RelayDiscovery.swift` - current startup path for physical iPhone relay discovery, saved no-secret relay config, and manual URL fallback. Connectivity lifecycle must cover this pre-root path too.
  - `CodexDock/Configuration/DockHostConfiguration.swift` - current host config has optional `bearerToken`. Nil bearer is normal for the physical relay and must flow through connectivity probes.
  - `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md` - preceding plan changes Dock loading to `DockSessionQuery`, counted tabs, and scoped load failures. Connectivity should be implemented against that shape.
  - `CodexDock/Features/Session/SessionDetailView.swift` - displays the best live indicator today, but only inside thread detail.
  - `CodexDock/Voice/VoiceCaptureController.swift` - owns the iOS audio session and recording lifecycle used by the thread composer.
  - `scripts/dock-relay.mjs` - owns the normal phone-facing bridge on `ws://192.168.50.117:4510`, live loopback discovery, history/live merge, upstream `thread/resume`, and downstream notification/request forwarding.
  - `README.md` - states `rtk make services` starts the raw app-server on `:4500` and Dock relay on `:4510`; the relay is the app endpoint.
  - `docs/bugs/thread-detail-large-live-thread-message-too-long-2026-05-28.md` - proves compact detail loading is required: `thread/read includeTurns:false`, `thread/turns/list limit:10`, and `thread/resume excludeTurns:true`.
  - `docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md` - proves live loaded rows must outrank stored `Limited` history and that the relay endpoint must remain visible.

- Canonical path / owner to reuse:
  - `CodexDock/AppServer/AppServerClient.swift` - canonical owner for protocol-level lifecycle: observable connection state, receive-loop terminal events, reconnect/backoff, late-response policy, request cancellation semantics, close/error metadata, and transport safety.
  - `CodexDock/State/ThreadDetailStore.swift` - canonical owner for thread-domain recovery after reconnect: compact read, paged turns, compact resume, event/request-card preservation, and live/stale/reconnecting transitions.
  - `CodexDock/State/AppConnectivityStore.swift` - new canonical owner for app-wide host connectivity rollup, refresh/checking state, last checked time, and global status. This should be new because none of the existing stores can own app-wide truth without becoming tab-local or domain-specific.
  - `CodexDock/State/AppLifecycleCoordinator.swift` or a small sibling type inside `AppConnectivityStore.swift` - new canonical owner for translating SwiftUI scene phase into app lifecycle events, background quiescing, foreground-resume generations, and timer restart rules.
  - `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` - new passive UI consumer for the shared connectivity state.
  - `scripts/dock-relay.mjs` - canonical bridge owner for upstream close policy, `excludeTurns:true` attention probing, and live-row-preserving list limits.

- Adjacent surfaces tied to the same contract family:
  - `CodexDockTests/AppServerClientTests.swift` - must add midstream close, stream terminal/state stream, reconnect, timeout/cancel late-response, and real-host smoke coverage.
  - `CodexDockTests/ThreadDetailStoreTests.swift` - must add stream-end and reconnect/rehydration coverage; the fake session must be able to simulate live socket death.
  - `CodexDockTests/DockStoreTests.swift` - must add failure-to-success refresh recovery and status reporting coverage.
  - New `CodexDockTests/AppConnectivityStoreTests.swift` - must prove rollup semantics without coupling to SwiftUI rendering.
  - New `CodexDockTests/AppLifecycleCoordinatorTests.swift` or focused store tests - must prove background pauses timers/retry, active foreground resumes checks, and lifecycle generations reach detail/relay-discovery owners.
  - `scripts/dock-relay.test.mjs` - must grow from helper tests into in-process WebSocket integration tests for auth, merge, resume forwarding, upstream close policy, `excludeTurns:true`, and live-row-preserving limits.
  - `README.md` - must update the runbook so operators understand indicator states and recovery checks.

- Compatibility posture (separate from `fallback_policy`):
  - Preserve the app-server JSON-RPC method contract. Do not invent protocol fallbacks.
  - Cleanly extend the Swift client API with lifecycle/state observation. Existing request methods keep their names and behavior, but callers that need resilience move to the new lifecycle contract.
  - Preserve one-shot Dock/Archive/Hosts content operations while recording their outcomes into `AppConnectivityStore`.
  - Cleanly change `ThreadDetailStore` from one-shot `didLoad` live attachment to a resumable lifecycle. The UI contract remains "open row shows thread detail"; the internal lifecycle becomes reconnectable.
  - Cleanly add app scene lifecycle as an internal root/store contract. Existing launch and host configuration behavior remains the same, but background/resume now produces explicit app lifecycle events instead of relying on implicit SwiftUI task cancellation.
  - Cleanly harden the relay. No dual relay modes or runtime shim are approved.

- Existing patterns to reuse:
  - `@MainActor ObservableObject` stores with `@Published` state in `DockStore`, `ArchiveStore`, `HostSettingsStore`, and `ThreadDetailStore`.
  - Protocol-based test seams: `AppServerTransport`, `DockSessionLoading`, `DockSessionArchiving`, `ThreadDetailSession`, and fake actors in tests.
  - Compact detail loading from `ThreadDetailStore.load()`: `thread/read includeTurns:false`, `thread/turns/list limit:10`, `thread/resume excludeTurns:true`.
  - Root registry propagation in `CodexDockRootView.onChange(of: hostsStore.registry)`.
  - SwiftUI `@Environment(\.scenePhase)` as the standard source for active/inactive/background transitions, with state changes forwarded into root-owned stores/coordinators.
  - Existing service verification commands in `README.md` and `Makefile`.

- Prompt surfaces / agent contract to reuse:
  - Not applicable. This plan hardens a Swift/Node app runtime, not an LLM prompt or agent behavior surface.

- Native model or agent capabilities to lean on:
  - Not applicable.

- Existing grounding / tool / file exposure:
  - `rtk swift test`, `rtk npm test`, `rtk node --check scripts/dock-relay.mjs`, `rtk make services`, `rtk make app-server-status`, `rtk make dock-relay-status`, and `rtk make app SIM='iPhone 17'`.

- Duplicate or drifting paths relevant to this change:
  - `AppServerClient.state`, `DockHostLoadStatus`, `HostConnectionTestStatus`, and `ThreadDetailLiveState` all describe connectivity-like truth from different angles. The plan must converge their app-wide rollup through `AppConnectivityStore` while preserving domain-specific local states.
  - `DockView.runRefreshLoop()` is a view-bound freshness owner. App-wide connectivity cannot depend on this loop staying active.
  - No current code owns scene lifecycle. `CodexDockApp`, `CodexDockBootstrapView`, `CodexDockRootView`, `RelayBootstrapStore`, `ThreadDetailStore`, and root refresh loops can otherwise drift into separate background/resume behavior.
  - `pendingRequestsForActiveThread()` in the relay currently calls `thread/resume` without `excludeTurns:true`, contradicting the large-thread fix.
  - Relay `aggregateThreadList()` sorts and limits after merging; the plan must ensure live loaded rows survive the relay limit instead of being cut out by newer stored history.
  - README still contains stale wording that "status only breaks ties"; current Swift behavior prioritizes live status before stored history.

- Capability-first opportunities before new tooling:
  - Use the existing client actor and store seams before adding any new networking framework.
  - Use focused tests inside the existing Swift and Node test targets before adding a separate harness.
  - Use the relay's existing WebSocket client/server code for integration tests instead of introducing another relay test server framework.

- Behavior-preservation signals already available:
  - `CodexDockTests/AppServerClientTests.swift` already covers request encoding, initialize/initialized, notification/request streams, request timeout, cancellation, typed thread methods, and optional phone-reachable smoke tests.
  - `CodexDockTests/DockStoreTests.swift` already covers load, refresh, offline, multi-host partial failure, filters, metadata, archive/restore, and host settings.
  - `CodexDockTests/ThreadDetailStoreTests.swift` already covers compact read/turns/resume, newest-first display, resume failure stale state, notification merging, server-request cards, composer sends, voice draft behavior, and thread mismatch.
  - `scripts/dock-relay.test.mjs` already covers helper-level attention flags, merge priority, archived-list behavior, and hidden relay source markers.
  - Simulator proof can use the existing app launch target plus iOS home/resume behavior to verify foreground revalidation without adding a background daemon.

## 3.3 Decision gaps that must be resolved before implementation

- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `CodexDock/AppServer/`
  - `AppServerClient.swift` contains the transport protocol, connection state enum, JSON-RPC client actor, receive loop, request multiplexing, typed request helpers, and the production `URLSessionWebSocketAppServerTransport`.
  - `AppServerMethods.swift` contains method-name constants and initialize types.
  - DTO files define thread list, thread detail, and turn method payloads.
- `CodexDock/State/`
  - `DockStore.swift` contains `AppServerDockClient`, one-shot list/archive calls, Dock state, per-host load states, and row projection.
  - `ArchiveStore.swift` mirrors Dock loading for archived rows.
  - `HostSettingsStore.swift` owns host registry editing and manual host test statuses.
  - `ThreadDetailStore.swift` owns the live thread screen lifecycle, compact detail loading, composer state, request cards, and live event merging.
- `CodexDock/Features/`
  - `Dock/DockView.swift` contains `CodexDockRootView`, the root `TabView`, Dock tab UI, the plus button, and the view-bound refresh loop.
  - `Archive/ArchiveView.swift`, `Hosts/HostsView.swift`, and `Session/SessionDetailView.swift` render tab/detail-local state.
- `CodexDockApp/`
  - `CodexDockApp.swift` is a minimal `@main` SwiftUI app that mounts `CodexDockBootstrapView` in a `WindowGroup`.
- `CodexDock/Configuration/`
  - `RelayBootstrapStore.swift` owns relay discovery startup and transition to a ready `HostRegistry`.
- `scripts/dock-relay.mjs`
  - Node WebSocket relay that accepts no phone-side auth by default, enforces bearer auth only in explicit dev/hardening mode, discovers local loopback app-server processes, merges stored history with live loaded rows, and forwards resumed detail notifications/requests.
- Tests and docs
  - `CodexDockTests/*` cover the Swift client, stores, mapping, thread detail, and event normalization.
  - `scripts/dock-relay.test.mjs` covers relay helpers only.
  - `README.md` and `docs/bugs/*` are live runbook/history surfaces for endpoint, relay, live-status, and compact-detail behavior.

## 4.2 Control paths (runtime)

- Dock list refresh:
  - `CodexDockRootView` constructs `DockStore`, `ArchiveStore`, and `HostSettingsStore`.
  - `DockView.body.task` calls `runRefreshLoop()`.
  - `runRefreshLoop()` calls `store.load()`, sleeps five seconds, then calls `store.refresh()` while the Dock view task remains active.
  - `DockStore.reload(showLoading:)` loads local metadata, fans out across configured hosts, and calls `AppServerDockClient.loadSessions`.
  - `AppServerDockClient.withClient` creates a new `AppServerClient`, connects/initializes, performs one operation, then disconnects and finishes streams.
- App bootstrap and scene lifecycle:
  - `CodexDockApp` mounts `CodexDockBootstrapView`.
  - `CodexDockBootstrapView.body.task` calls `RelayBootstrapStore.start()`.
  - `RelayBootstrapStore.start()` is guarded by `didStart`, uses environment configuration when present, otherwise starts Bonjour relay discovery and saved manual URL loading.
  - No root or bootstrap path observes SwiftUI `scenePhase`; there is no owned background, inactive, or foreground-resume flow.
- Archive flow:
  - `ArchiveView.task` loads once.
  - Manual refresh and restore call `ArchiveStore.refresh()` / `restore()`.
  - `ArchiveStore.reload(showLoading:)` uses the same one-shot loader with `archived: true`.
- Thread detail live flow:
  - `DockRowView` navigation creates `ThreadDetailStore(host:row:)`.
  - `ThreadDetailStore.load()` is guarded by `didLoad`.
  - It creates one `AppServerClient`, connects/initializes, starts notification and server-request observation tasks, then calls compact read/turns/resume.
  - Notifications and server requests update `liveState`, events, active turn ID, and request cards.
  - Leaving the view calls `close()`, cancels observation tasks, and disconnects the session.
- Host settings flow:
  - `HostSettingsStore.test(_:)` calls the same one-shot loader and stores `.online`, `.offline`, or `.error` in a private `statuses` dictionary.
  - `CodexDockRootView.onChange(of: hostsStore.registry)` updates Dock and Archive registries.
- Relay flow:
  - `thread/list` reads history and live loaded rows, merges them, sorts, then applies the requested limit.
  - `thread/resume` creates one upstream `JsonRpcWebSocketClient`, forwards upstream notifications/requests to the downstream Swift connection, and stores the upstream client on the downstream session.
  - `turn/start`, `turn/steer`, and `turn/interrupt` require `session.upstream` from a prior `thread/resume`.

## 4.3 Object model + key abstractions

- `AppServerConnectionState`: `.idle`, `.connecting`, `.connected`, `.offline(reason:)`, `.error(message:)`. This is actor-local state, not an observable stream.
- `AppServerTransport`: primitive `connect`, `send`, `receive`, `disconnect` boundary.
- `AppServerClient`: JSON-RPC session actor with `notifications` and `serverRequests` as non-throwing `AsyncStream`s.
- `DockHostLoadStatus`: per-host list result in Dock/Archive snapshots: `.loaded`, `.empty`, `.offline`, `.error`.
- `DockStoreState`: Dock screen state including single-host offline/error and loaded multi-host snapshots.
- `ArchiveStoreState`: Archive screen state with configuration, idle/loading, loaded, and empty.
- `HostConnectionTestStatus`: manual Hosts-tab check status; not shared app-wide.
- `ThreadDetailLiveState`: detail-local `.connecting`, `.live`, `.stale`, `.closed`; no reconnecting state today.
- There is no app lifecycle state model for active/inactive/background/resuming.
- `JsonRpcWebSocketClient` in the relay: Node helper with pending requests, timeout, notification/request callbacks, and close rejection.

## 4.4 Observability + failure behavior today

- `AppServerClient.openTransport()` sets `.connecting`, calls transport `connect()`, and starts the receive loop. It marks `.offline` only if connect throws.
- `connectAndInitialize()` marks `.connected` only after `initialize` and `initialized` succeed.
- `startReceiveLoop()` handles response/error/notification/request messages while transport `receive()` succeeds.
- A `nil` receive marks `.offline("transport closed")`.
- Malformed JSON or receive errors call `failConnection()`, which cancels the receive task, fails pending requests, disconnects transport, and sets `.error`.
- `markOffline()` and `failConnection()` do not emit a public state event to SwiftUI consumers. They also do not reconnect.
- `disconnect()` finishes `notifications` and `serverRequests`, making a single `AppServerClient` incoherent for reuse after explicit disconnect.
- `ThreadDetailStore.startObservation(session:)` loops over `notifications` and `serverRequests`; when either stream ends, the loop exits without marking the detail stale.
- Timeout/cancellation removes pending requests. If the server later sends a response for that retired ID, `handleIncoming` treats it as unmatched and fails the connection.
- `URLSessionWebSocketAppServerTransport` keeps mutable `task` state in an `@unchecked Sendable` class while `sendRequest` sends through an unstructured task that captures the transport.
- Dock and Archive online/offline truth is inferred from a recent one-shot load, not from a durable connection.
- Archive can show empty content when all configured hosts failed because `ArchiveStore.reload` sets `.empty(snapshot)` when `rowCount == 0`.
- SwiftUI backgrounding is not distinguished from a network failure or view-task cancellation. Root refresh, relay discovery, and live detail sessions have no shared contract for quiesce/resume.
- A backgrounded app can return with old snapshots still visible and no immediate app-owned proof that services are reachable.
- If a live detail socket dies while the app is suspended, `ThreadDetailStore` has no background-aware reason or foreground rehydrate trigger.
- If voice capture is active during a background transition, the plan needs an explicit safety rule because `VoiceCaptureController` owns an iOS audio session and `ThreadDetailStore` owns the composer state.
- Relay upstream close rejects pending upstream requests and sets `ws = null`, but the downstream WebSocket can remain open with `session.upstream` present or recently closed until the next command fails.
- Relay attention probing still risks large responses because it calls `thread/resume` without `excludeTurns:true`.
- Relay can cut live loaded rows out of `thread/list` results when sorting/limiting after merging if recent history rows consume the limit.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current high-level structure:

```text
CodexDockRootView
└─ TabView
   ├─ DockView
   │  └─ header: "Dock"                         [+ disabled]
   ├─ ArchiveView
   │  └─ header: "Archive"                      [refresh]
   └─ HostsView
      └─ header/actions: manual host tests

SessionDetailView is pushed from Dock rows and shows detail-local pills:
[Host] [Live/Stale/Closed] [Thread status]
```

Current user-visible gaps:

- No root-level indicator appears across every screen.
- Dock has per-host summary text but no global "checking/stale/reconnecting" indicator.
- Detail shows a live-state pill, but it is not connected to raw socket failure after load.
- Hosts manual test pills do not inform Dock/Archive/global status.
- The app has no visible "backgrounded/resuming" state on foreground return; users can see stale UI with no explanation while reconnection work is implicit or absent.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- `CodexDock/AppServer/AppServerClient.swift`
  - Keep the JSON-RPC actor as the canonical session boundary.
  - Add an observable connection-state stream, a bounded reconnect policy, retired-request ID handling, and clearer terminal-state semantics.
  - Keep `URLSessionWebSocketAppServerTransport` primitive, but make task access safer and expose enough close/error metadata for state decisions.
- `CodexDock/AppServer/AppServerConnectionPolicy.swift` or the same file if small
  - Define retry policy, backoff, jitter, max attempts or max elapsed time, and whether reconnect is disabled or enabled.
- `CodexDock/State/AppConnectivityStore.swift`
  - New root-owned app-wide store for host connectivity rollup and status reporting.
  - Track host ID, display name, endpoint, phase, message, last checked time, last successful check, retry/checking status, and an overall rollup.
- `CodexDock/State/AppLifecycleCoordinator.swift` or a small sibling in `AppConnectivityStore.swift`
  - Translate SwiftUI `scenePhase` into explicit lifecycle events: active, inactive, backgrounded, foreground-resuming.
  - Own background quiesce/resume generation state so root refresh/check loops, relay discovery, and detail rehydrate do not invent separate lifecycle rules.
- `CodexDock/State/ConnectivityReporting.swift` or local protocols in the store file
  - Small protocol used by Dock/Archive/Hosts/ThreadDetail to report outcomes without owning global truth.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
  - Passive SwiftUI indicator rendering the app-wide rollup.
- `CodexDock/State/ThreadDetailStore.swift`
  - Extend the session protocol to expose connection states.
  - Add reconnecting/backgrounded/resuming state and rehydration logic.
- `CodexDock/Configuration/RelayBootstrapStore.swift`
  - Add lifecycle handling so discovery stops or pauses on background and restarts on foreground if the app is still not configured/ready.
- `scripts/dock-relay.mjs`
  - Track downstream session resume state, upstream lifecycle, bounded upstream reconnect/re-resume, `excludeTurns:true`, and live-row-preserving list behavior.
- Tests
  - Add Swift tests for app-server lifecycle, thread reconnect, app connectivity rollup, and Archive all-offline state.
  - Expand relay tests to in-process WebSocket integration coverage.

## 5.2 Control paths (future)

- App launch/root path:
  - `CodexDockBootstrapView` remains the app entry point and participates in lifecycle. It starts with env, Bonjour discovery, or saved non-secret relay config before `CodexDockRootView` exists.
  - `CodexDockRootView` owns `AppConnectivityStore` beside Dock, Archive, and Hosts stores.
  - `CodexDockRootView` or `CodexDockBootstrapView` owns a single app lifecycle coordinator fed by `@Environment(\.scenePhase)`.
  - Every root initializer, including `init(store:)`, `init(registry:)`, and `init(configurationError:)`, creates or receives the same connectivity store so configuration-error startup still shows an app-wide status.
  - Root passes a connectivity reporter into Dock/Archive/Hosts/ThreadDetail creation points.
  - Root starts an app-level connectivity check loop that is independent of the Dock tab's view task.
  - Registry changes update Dock, Archive, Hosts, and connectivity store from one root path.
- App lifecycle path:
  - On `.inactive`, record a transitional state without tearing down healthy live work unless iOS/transport already closes it.
  - On `.background`, mark the lifecycle `backgrounded`, mark connectivity as backgrounded/suspended, pause or cancel root refresh/check timers, pause reconnect backoff timers, stop relay discovery when still in bootstrap, and classify transport closures as expected suspension rather than unrecoverable error.
  - If a detail view is open, preserve displayed events, request cards, draft text, active turn metadata, and failed-send state. Do not auto-replay non-idempotent sends after resume.
  - If voice capture is recording or transcribing, cancel or settle it through the existing `VoiceCaptureControlling` boundary, deactivate the audio session, and leave draft text recoverable; never auto-submit on resume.
  - On `.active` after background, publish `foregroundResuming`, restart root refresh/check loops, restart relay discovery if bootstrap is still discovering, force immediate Dock/Archive/Host reachability revalidation, and tell the open `ThreadDetailStore` to re-run compact read/turns/resume before returning to `.live`.
  - Foreground resume uses the same reconnect/rehydrate path as network recovery where possible so background handling does not become a parallel recovery implementation.
- App-wide indicator path:
  - `GlobalConnectivityIndicatorView` reads `AppConnectivityStore.overallStatus`.
  - The view is mounted from `CodexDockRootView` with a root overlay or top safe-area inset so it remains visible across tabs and navigation.
  - The indicator uses compact colorized labels, for example: `Online`, `Checking`, `Reconnecting`, `Resuming`, `Backgrounded`, `Partial`, `Stale`, `Offline`, `Error`.
- One-shot content path:
  - Dock/Archive/Hosts continue using `DockSessionLoading`.
  - After the Agents plan lands, Dock/Archive/Hosts use `DockSessionQuery(archived:sourceKinds:)`; connectivity reporting consumes scoped load outcomes instead of assuming one load result per host.
  - Each success/failure reports a host outcome to `AppConnectivityStore`.
  - Dock content auto-refresh moves out of `DockView.runRefreshLoop()` into a root-owned scheduler in `CodexDockRootView`; `DockStore` remains a content store exposing `load()` and `refresh()`. Archive can remain manual/on-demand content refresh while still reporting connectivity outcomes.
  - Background refresh state is visible: when a refresh/check is in progress, the indicator can say `Checking` without clearing the last good data.
- Live detail path:
  - `ThreadDetailStore` creates an `AppServerClient` with reconnect enabled.
  - It observes `connectionStates`, app lifecycle events, `notifications`, and `serverRequests`.
  - On transient drop, the store publishes `.reconnecting(message)` while automatic recovery is still allowed, and preserves displayed events, request cards, and composer draft.
  - On background, the store publishes a backgrounded/suspended state or reports that state through `AppConnectivityStore`, pauses retry timers, and treats stream termination as expected suspension while the app remains backgrounded.
  - When the client reconnects, the store reruns compact `thread/read`, `thread/turns/list`, and `thread/resume excludeTurns:true`, then publishes `.live`.
  - On foreground resume, the store follows the same compact rehydrate path even if the transport appears connected, because iOS may have suspended delivery without a clean socket close.
  - If recovery gives up or is unsafe, the store remains stale with an explicit reason and a secondary user retry affordance can call the same reconnect/rehydrate path.
- Relay path:
  - `thread/resume` stores resume params and selected endpoint on the downstream session.
  - Upstream close triggers bounded upstream reconnect/re-resume while the downstream session is still open and resume params are known.
  - If upstream recovery is unsafe or exhausted, the relay closes the downstream WebSocket. It does not rely on a JSON-RPC error as the primary fail-loud contract, because Swift already treats transport close as a lifecycle event.
  - Attention probing uses `thread/resume { threadId, excludeTurns: true }`.
  - `thread/list` preserves live loaded rows before applying the requested limit.
  - Ordinary per-request relay errors can still fail their matching request, but upstream session death is surfaced as downstream transport closure.

## 5.3 Object model + abstractions (future)

- `AppServerConnectionState` becomes the public state model for both polling and live sessions. It should include enough phases to drive UI without string parsing:
  - idle/configuring;
  - connecting;
  - connected;
  - reconnecting with attempt, delay, and reason;
  - offline/permanently disconnected with reason;
  - error with typed category/message;
  - closed for intentional shutdown.
- `AppServerClient.connectionStates` is a nonisolated `AsyncStream<AppServerConnectionState>` or equivalent state update stream.
- `AppServerConnectionPolicy` defines:
  - reconnect disabled for simple one-shot operations by default;
  - reconnect enabled for live detail sessions;
  - bounded exponential backoff with jitter;
  - background-suspended mode that pauses retry timers and does not consume retry budget while iOS is backgrounded;
  - cancellation on explicit disconnect/deinit.
- `AppLifecycleState` or equivalent coordinator state defines:
  - active;
  - inactive/transitional;
  - backgrounded with timestamp and reason;
  - foregroundResuming with generation ID;
  - foregroundActive after required revalidation hooks complete.
- `AppConnectivityStore` defines:
  - `HostConnectivityStatus`: unknown, checking, online, reconnecting, backgrounded, resuming, stale, offline, error.
  - `AppConnectivityOverallStatus`: unconfigured, checking, online, partial, reconnecting, backgrounded, resuming, stale, offline, error.
  - reporting APIs for load outcomes, manual tests, detail connection states, app lifecycle events, registry updates, and periodic probes.
- `ThreadDetailLiveState` adds `.reconnecting(String)` and `.backgrounded`/`.resuming` or otherwise distinguishes reconnect-in-progress, app-suspended, foreground-resuming, and stale/no-retry.
- `ThreadDetailSession` exposes connection states and optionally a reconnect trigger for exhausted/unsafe states. Fakes must support state emission, stream termination, background suspension, and foreground-resume rehydrate.
- Relay session state tracks:
  - `upstream`;
  - `resumeParams`;
  - `endpoint`;
  - `retryTask`;
  - closing/cancelled flag;
  - downstream notification/error behavior.

## 5.4 Invariants and boundaries

- `AppServerClient` owns socket/protocol lifecycle; it does not know thread UI semantics.
- `ThreadDetailStore` owns thread-domain resubscription; it does not implement raw socket backoff.
- `AppConnectivityStore` owns app-wide rollup; tab/detail stores only report facts.
- `AppLifecycleCoordinator` or the chosen root lifecycle type owns scene-phase translation; tab/detail views do not decide whether backgrounding is an error.
- Global indicator UI must not call app-server methods directly.
- Explicit disconnect finishes streams and cancels retry. Transient failure in reconnect-enabled mode emits state and retries instead of silently idling; `connectionStates` is the primary liveness signal.
- Pending requests in flight during transport failure fail loudly; the domain owner decides whether to retry idempotent operations.
- Manual user actions are not part of the happy recovery path. They appear only when automatic retry has stopped or cannot safely proceed.
- Backgrounded transport closures are expected lifecycle events while the app is backgrounded. They become revalidation work on active foreground, not exhausted failures.
- Late responses for timed-out/cancelled/retired request IDs are ignored or logged, not treated as protocol corruption. A response for a never-issued ID remains protocol error.
- `thread/resume` recovery always uses `excludeTurns:true`; history refresh uses `thread/turns/list`.
- Relay must not hide upstream death from Swift. It either restores the upstream and resumes the thread or closes downstream so Swift reconnects through the transport lifecycle.
- Multi-host partial outage stays partial. One live host must remain visible when another host is offline.
- A currently displayed Dock/Archive snapshot remains visible during foreground and foreground-resume connectivity checks. The indicator carries the checking/stale/offline truth; content is not blanked unless the user has no prior data for that surface.
- A currently displayed Dock/Archive/detail snapshot remains visible while backgrounded or resuming, but the indicator must say `Backgrounded`/`Resuming`/`Reconnecting` instead of implying fresh live data.
- Thread detail rehydration must merge or replace events deterministically and must not duplicate request cards after reconnect.
- Reconnect timers are cancelled when the screen or root store closes. No orphan retry loops.
- Refresh, discovery, and reconnect timers are paused/cancelled while backgrounded and restarted only from the root lifecycle path on foreground active.
- No fallback policy exceptions are approved.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Target root shell:

```text
┌─────────────────────────────────────┐
│                               Online│  <- root-level status pill
├─────────────────────────────────────┤
│ Dock                          [+]   │
│ [filters/search]                    │
│ Amir-M5 · ws://...:4510 · 19 live   │
│ rows...                             │
└─────────────────────────────────────┘

Indicator states:
[Online] green
[Checking] blue/secondary
[Reconnecting] orange, optionally with next retry timing
[Resuming] blue/orange
[Backgrounded] gray/secondary
[Partial] orange
[Stale] yellow/orange
[Offline] red
[Error] red
```

Target detail shell:

```text
┌─────────────────────────────────────┐
│                         Reconnecting│  <- same root indicator
├─────────────────────────────────────┤
│ Thread title                        │
│ [Host] [Reconnecting] [Status]      │
│ Reconnecting...                     │
│ events remain visible               │
│ composer draft remains editable     │
└─────────────────────────────────────┘
```

Status text should be informative, not obstructive: `Reconnecting...`, `Resuming...`, `Recovered`, `Offline: retrying in 4s`, or `Recovery stopped`. Retry controls appear only for stopped/exhausted/unsafe recovery, not during ordinary transient drops or normal foreground resume.

The root pill may live in a `.safeAreaInset(edge: .top)` or root overlay. The implementation should choose the least intrusive SwiftUI shape that stays visible across `TabView` and pushed navigation.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| App-server lifecycle | `CodexDock/AppServer/AppServerClient.swift` | `AppServerConnectionState` | Actor-local state with idle/connecting/connected/offline/error. | Add reconnecting/closed or equivalent states needed by UI and stores; keep existing semantic names where possible. | UI and stores need state transitions, not polling actor state. | `AppServerConnectionState` becomes observable state contract. | `AppServerClientTests` |
| App-server lifecycle | `CodexDock/AppServer/AppServerClient.swift` | `notifications`, `serverRequests` | Plain streams; no error state; fail paths do not reliably finish or notify consumers. | Add `connectionStates`; define stream behavior across transient failure and explicit disconnect. | Prevent silent dead-air loops in detail. | Nonisolated `connectionStates: AsyncStream<AppServerConnectionState>`. | `AppServerClientTests`, `ThreadDetailStoreTests` |
| App-server lifecycle | `CodexDock/AppServer/AppServerClient.swift` | `connectAndInitialize`, `openTransport`, `startReceiveLoop`, `failConnection`, `markOffline` | Connect once; no reconnect or backoff. | Add bounded reconnect policy for live clients; emit transitions; reconnect by re-opening transport and re-running initialize/initialized. | Socket recovery belongs at the session boundary. | `AppServerConnectionPolicy`; reconnect-enabled clients. | `AppServerClientTests` |
| App-server lifecycle | `CodexDock/AppServer/AppServerClient.swift` | `handleIncoming(.response/.error)` | Late response after timeout/cancel becomes unmatched and fails connection. | Track retired request IDs briefly; ignore/log late retired responses; fail only never-issued unknown IDs. | Late responses are normal after timeout/cancel and should not kill a healthy session. | Retired request ID policy. | `AppServerClientTests` |
| App-server lifecycle | `CodexDock/AppServer/AppServerClient.swift` | `sendRequest` unstructured send task | Sends through captured transport outside actor isolation. | Make send/receive/disconnect access safe through actor-owned path or transport synchronization. | Avoid races around mutable WebSocket task. | Transport access remains safe under Swift concurrency. | `AppServerClientTests` |
| Transport | `CodexDock/AppServer/AppServerClient.swift` | `URLSessionWebSocketAppServerTransport` | Mutable `task`, `@unchecked Sendable`, string-shaped errors. | Protect task mutation and preserve useful close/error metadata where available. | Better retry and UI decisions. | Typed close/error reason where possible. | `AppServerClientTests` |
| Thread detail | `CodexDock/State/ThreadDetailStore.swift` | `ThreadDetailSession` | Exposes notifications/requests and request methods only. | Add connection-state stream and reconnect/live lifecycle contract. | Store must observe socket state. | `var connectionStates: AsyncStream<AppServerConnectionState> { get }`. | `ThreadDetailStoreTests` |
| Thread detail | `CodexDock/State/ThreadDetailStore.swift` | `ThreadDetailLiveState` | connecting/live/stale/closed. | Add reconnecting or equivalent state; stale remains visible after retry exhaustion or unsafe recovery. | User must know whether recovery is happening or stopped. | `.reconnecting(String)` or explicit state model. | `ThreadDetailStoreTests`, UI checks |
| Thread detail | `CodexDock/State/ThreadDetailStore.swift` | `load()`, `didLoad`, `startObservation` | One-shot load; streams can end silently; no reconnect. | Split initial load from rehydrate; observe state; on drop mark reconnecting and automatically rerun compact read/turns/resume; mark stale only after automatic recovery stops. | This is the highest-risk live update path. | `rehydrateLiveSession()` / state-driven recovery path. | `ThreadDetailStoreTests` |
| Thread detail | `CodexDock/State/ThreadDetailStore.swift` | `sendDraft`, `respond(to:)` | Fails request locally if session send fails. | Preserve draft/request card state through reconnect; do not auto-replay non-idempotent sends unless explicitly submitted again. | Avoid duplicate turn starts or approvals. | Failed sends remain user-visible and recoverable. | `ThreadDetailStoreTests` |
| App connectivity | new | `CodexDock/State/AppConnectivityStore.swift` | No app-wide status owner. | Add root-owned observable store with per-host and overall status, including automatic retry progress where useful. | Single source for global indicator and cross-tab status. | `AppConnectivityStore`, `HostConnectivityStatus`, `AppConnectivityOverallStatus`. | New `AppConnectivityStoreTests` |
| App lifecycle | `CodexDockApp/CodexDockApp.swift`, `CodexDock/Features/Dock/CodexDockBootstrapView.swift`, `CodexDock/Features/Dock/DockView.swift` | `WindowGroup`, `.task`, `CodexDockRootView` | No `scenePhase` owner; background/resume is implicit. | Add root/bootstrap scene-phase forwarding into one lifecycle coordinator/store. | Background/resume must be a first-class recovery state, not hidden SwiftUI behavior. | `AppLifecycleCoordinator` or equivalent root-owned lifecycle state. | New lifecycle/store tests, simulator check |
| Host auth baseline | `CodexDock/Configuration/DockHostConfiguration.swift`, `CodexDock/Configuration/RelayBootstrapStore.swift`, `CodexDock/AppServer/AppServerClient.swift` | `bearerToken: String?`, discovered relay hosts | Nil bearer is the implemented physical relay path. | Keep nil bearer as a valid online/checking/reconnecting host state; do not surface it as missing credentials. | Connectivity status must match the actual no-phone-secret product path. | Optional bearer is normal; auth failures are endpoint-specific. | App connectivity and host tests |
| Dock query baseline | `CodexDock/State/DockStore.swift`, `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md` | `DockSessionLoading.loadSessions` before Agents | Current code has old loader API, while Phase 1 top-level changes it. | Implement connectivity after Agents and report scoped query outcomes from the new `DockSessionQuery`/`DockSnapshot` shape. | Avoid building app-wide status on a loader API that will be removed. | Scoped load reporting into `AppConnectivityStore`. | Dock/connectivity tests |
| App lifecycle | new | `CodexDock/State/AppLifecycleCoordinator.swift` or local root lifecycle type | Missing. | Track active/inactive/backgrounded/resuming state, background timestamp, resume generation, and lifecycle event stream/reporting. | Avoid duplicating lifecycle decisions across root, detail, relay discovery, and connectivity. | `AppLifecycleState`; `handleScenePhase(_:)`; resume generation. | `AppLifecycleCoordinatorTests` or focused store tests |
| Reporting | new | `ConnectivityReporting` protocol | Dock/Archive/Hosts do not report to shared status or lifecycle state. | Add small reporter dependency or root coordination path. | Keep stores decoupled from global UI while sharing facts. | `recordLoadOutcome`, `recordHostTest`, `recordDetailState`, `recordLifecycleState`. | Store tests |
| Root UI | `CodexDock/Features/Dock/DockView.swift` | `CodexDockRootView` | Owns three stores and plain `TabView`. | Add `@StateObject AppConnectivityStore` and lifecycle coordinator; pass reporters; mount global indicator; observe foreground resume. | Indicator and lifecycle recovery must appear across every screen. | Root-level status/lifecycle injection and overlay/inset. | UI/manual, store tests |
| Dock refresh | `CodexDock/Features/Dock/DockView.swift` | `runRefreshLoop()` | View-bound five-second loop. | Move Dock auto-refresh ownership to `CodexDockRootView`; pause/cancel loop on background; restart and force refresh on foreground; keep `DockStore` as a content store with `load()` / `refresh()`; remove the tab-local loop. | Global status and Dock freshness cannot depend on Dock tab task or survive background accidentally. | Root-owned refresh/check loop controlled by lifecycle. | Dock/root/lifecycle tests where practical |
| Dock projection | `CodexDock/State/SessionRowProjector.swift` | Section and row sorting | Current Swift projection prioritizes live statuses before limited history. | Preserve this behavior and keep relay output compatible with it. | Relay should not cut out rows Swift is designed to prioritize. | Live-first row survival contract. | `DockStoreTests`, relay tests |
| Dock UI | `CodexDock/Features/Dock/DockView.swift` | `header` plus button area | Plus button disabled; no status pill. | Keep plus button; global indicator appears near top-right/root top. | User requested status near top area/by plus. | Passive `GlobalConnectivityIndicatorView`. | Manual simulator check |
| Archive | `CodexDock/State/ArchiveStore.swift` / `ArchiveView.swift` | `reload(showLoading:)`, `.empty(snapshot)` | All failures with zero rows can render Archive empty. | Represent all-offline/all-error as unavailable/error or show unavailable message from host states. | Empty archive is false when hosts are unreachable. | Archive state/content distinguishes unavailable from empty. | `DockStoreTests` or new archive tests |
| Host settings | `CodexDock/State/HostSettingsStore.swift` | `statuses` | Manual test status private to Hosts tab. | Report test outcomes to `AppConnectivityStore`; align status vocabulary where useful. | Manual checks should update global indicator. | Reporter dependency or root observation. | Store tests |
| Relay bootstrap | `CodexDock/Configuration/RelayBootstrapStore.swift` | `start()`, discovery callbacks | Starts once from view `.task`; no background/resume handling. | Stop/pause discovery on background; restart discovery or saved-manual handling on foreground if not ready; do not duplicate discovery callbacks. | First-run/manual relay setup must recover from app backgrounding too. | lifecycle-aware bootstrap start/resume API. | `DockStoreTests` or new bootstrap/lifecycle tests |
| Voice capture | `CodexDock/Voice/VoiceCaptureController.swift`, `CodexDock/State/ThreadDetailStore.swift` | recording/transcribing composer state | No background transition contract. | On background, cancel or settle active recording through `VoiceCaptureControlling`, deactivate audio session, and leave draft recoverable without auto-submit. | Backgrounding while recording must not leak audio session or send stale input. | `handleAppBackgrounded()` on detail/composer path. | `ThreadDetailStoreTests` |
| Relay lifecycle | `scripts/dock-relay.mjs` | `JsonRpcWebSocketClient` | Rejects pending on close; no reconnect; downstream not necessarily informed. | Add open-state checks and close callback; support session-level upstream reconnect; close downstream WebSocket when recovery is unsafe or exhausted. | Swift cannot recover if relay hides upstream death. | Upstream lifecycle callback and downstream-close fail-loud policy. | `scripts/dock-relay.test.mjs`, Swift transport-close tests |
| Relay detail | `scripts/dock-relay.mjs` | `resumeThread`, `forwardToActiveUpstream` | Stores upstream only; forward checks object, not open state. | Store resume params/endpoint; re-resume on upstream close when safe; verify upstream open before forwarding; close downstream when not recoverable. | Detail recovery must include relay bridge. | Session resume state plus downstream-close failure contract. | Relay integration tests, Swift transport-close tests |
| Relay attention | `scripts/dock-relay.mjs` | `pendingRequestsForActiveThread` | Calls `thread/resume` without `excludeTurns:true`. | Send `thread/resume` with `excludeTurns:true`. | Prevent returning multi-megabyte turn history during attention probes. | Compact resume is mandatory. | Relay tests |
| Relay list | `scripts/dock-relay.mjs` | `aggregateThreadList` sort/limit | Merges then sorts/limits; live rows can be cut by recent history. | Preserve live loaded rows through limit, then fill with history. Keep Needs-me strict. | First viewport must show live truth. | Live-row-preserving pagination/limit rule. | Relay tests |
| Service runbook | `README.md` | Sorting and service wording | Mentions newest-first and status tie-breaks; does not describe global indicator, reconnect, or background/resume. | Update to live-first status priority, indicator meanings, reconnect/background-resume behavior, and service checks. | Operators need current truth when debugging status. | Runbook aligned with shipped lifecycle. | Manual doc read |
| Tests | `scripts/dock-relay.test.mjs` | Existing helper tests | No in-process WebSocket relay tests. | Add local ws integration tests for auth, readyz, list merge, failures, resume forwarding, upstream close, excludeTurns, limits. | Robustness needs deterministic relay proof. | Node test server helpers inside existing test target. | `rtk npm test` |
| Tests | `CodexDockTests/AppServerClientTests.swift` | Scripted transport | No midstream close/reconnect/state stream coverage. | Add scripted close/error/reconnect cases and late-response cases. | Prove lifecycle contract. | New fake transport scenarios. | `rtk swift test` |
| Tests | `CodexDockTests/ThreadDetailStoreTests.swift` | `FakeThreadDetailSession` | Cannot simulate socket death/reconnect state today. | Extend fake with connection-state stream, stream ending, reconnect success/failure. | Prove detail does not silently stay live. | Fake session lifecycle controls. | `rtk swift test` |
| Tests | new | `CodexDockTests/AppLifecycleCoordinatorTests.swift` or focused root/store tests | Missing. | Add active/inactive/background/foreground-resume tests, including timer pause/restart and resume generation delivery. | Scene lifecycle is a new canonical contract. | lifecycle fake clock/event stream. | `rtk swift test` |
| Docs | `README.md` | Service and sorting/runbook text | Does not explain connectivity indicator/reconnect/background-resume; has stale sorting wording. | Update after implementation. | Live docs must match shipped behavior. | Current runbook for status/recovery. | Manual doc read |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  - Protocol lifecycle: `CodexDock/AppServer/AppServerClient.swift`.
  - App-wide rollup: new `CodexDock/State/AppConnectivityStore.swift`.
  - App lifecycle coordination: new `CodexDock/State/AppLifecycleCoordinator.swift` or a small sibling root lifecycle type, fed by `@Environment(\.scenePhase)` from `CodexDockBootstrapView`/`CodexDockRootView`.
  - Thread rehydration: `CodexDock/State/ThreadDetailStore.swift`.
  - Global indicator UI: new `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`, mounted from `CodexDockRootView`.
  - Relay bridge recovery: `scripts/dock-relay.mjs`.
- Deprecated APIs (if any):
  - None at the product level.
  - Existing `ThreadDetailSession` fake/test conformers must adopt the new connection-state contract.
  - Existing root and bootstrap initializers must adopt lifecycle injection/ownership; do not leave a test-only lifecycle path.
- Delete list (what must be removed; include superseded shims/parallel paths if any):
  - Remove `DockView.runRefreshLoop()` when root-owned Dock refresh is added.
  - Do not keep any duplicate app-wide status calculation inside tab views after `AppConnectivityStore` exists.
  - Do not keep any tab/detail-local scene-phase handling that bypasses the lifecycle coordinator after the root lifecycle path exists.
- Adjacent surfaces tied to the same contract family:
  - Swift tests, relay tests, README, bootstrap discovery, voice capture, bug-doc reality if touched, and app launch/runbook commands.
- Compatibility posture / cutover plan:
  - Preserve external JSON-RPC behavior.
  - Cleanly extend internal Swift protocols/stores; update all fakes and call sites in the same implementation arc.
  - No temporary dual global indicator or alternate connectivity path.
  - Preserve normal app launch/bootstrap behavior while adding scene lifecycle handling as one internal clean cutover.
- Capability-replacing harnesses to delete or justify:
  - None. New tests use existing Swift XCTest and Node `node:test`.
- Live docs/comments/instructions to update or delete:
  - `README.md` must describe the indicator states, reconnect behavior, background/resume behavior, and correct live-row priority.
  - Add high-leverage comments only at new lifecycle boundaries if the retry/resume invariant would otherwise be easy to break.
- Behavior-preservation signals for refactors:
  - `rtk swift test`.
  - `rtk npm test`.
  - `rtk node --check scripts/dock-relay.mjs`.
  - Real simulator check with `rtk make app SIM='iPhone 17'`.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| App-wide status | `DockHostLoadStatus`, `HostConnectionTestStatus`, `ThreadDetailLiveState`, `AppServerConnectionState` | One rollup through `AppConnectivityStore` with domain-specific local states reporting facts. | Prevent four disconnected connectivity truths. | include |
| Live detail recovery | `ThreadDetailStore.load()` and `startObservation()` | State-driven rehydrate path. | Prevent one-shot live attachment after socket drops. | include |
| App lifecycle | `CodexDockBootstrapView`, `CodexDockRootView`, `ThreadDetailStore`, `RelayBootstrapStore`, `VoiceCaptureController` | One root-owned scene-phase coordinator drives background quiesce and foreground resume. | Prevent every screen/store from inventing its own background/resume semantics. | include |
| Compact resume | `ThreadDetailStore`, `scripts/dock-relay.mjs` attention probing and resume forwarding | Always use `excludeTurns:true` for resume where full turns are not explicitly needed. | Prevent large-message regression. | include |
| Live-row priority | `SessionRowProjector`, `scripts/dock-relay.mjs`, README | Live loaded rows outrank stored limited history. | Prevent relay from cutting out rows Swift is supposed to prioritize. | include |
| Root UI state | `CodexDockRootView` | Root owns app-wide state; tabs render content. | Keeps indicator visible across tabs/detail and avoids tab-local status logic. | include |
| Test seams | Existing Swift protocols and Node `node:test` | Extend current seams instead of adding a new harness. | Keeps verification small and idiomatic. | include |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable work. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. No fallbacks/runtime shims - the system must work correctly or fail loudly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates.

## Phase 0 - Top-Level Prerequisite Check

* Goal:
  - Confirm this child plan is starting from the top-level Phase 1 Agents outputs, not from the older Dock loader/filter shape.
* Checklist (must all be done before Phase 1 starts):
  - Do not start Connectivity until `docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md` has landed.
  - Required baseline symbols/behaviors: `DockSessionQuery(archived:sourceKinds:)`, typed `SessionOrigin`, `DockSnapshot.tabs`, `DockScopeLoadFailure`, `DockTabID.includes(_:)`, counted tab labels, and relay live-row `sourceKinds` filtering.
  - If any required Agents output is absent, stop and implement the Agents plan first. Do not adapt Connectivity to the pre-Agents `loadSessions(for:archived:)` / `DockFilter` shape.
* Exit criteria (all required):
  - A focused readback confirms the current branch has the Agents query/snapshot/failure/count model.
  - Any Connectivity implementation notes name the Agents baseline they are consuming.

## Phase 1 - Observable Connection Failure Path

* Goal:
  - Prove the highest-risk seam first: a transport drop after a live detail screen is loaded must become visible state instead of silent dead air.
* Work:
  - Extend the app-server client lifecycle contract enough for stores to observe state changes, then wire thread detail to react to terminal/drop states. This phase does not need full reconnect yet; it proves the app can no longer lie about being live.
* Checklist (must all be done):
  - Add an observable `AppServerClient` connection-state stream or equivalent nonisolated state update surface.
  - Emit state transitions for idle, connecting, connected, transport closed/offline, transport/protocol error, and explicit disconnect.
  - Define stream behavior for transient transport failure versus explicit disconnect: `connectionStates` is primary liveness; explicit disconnect finishes notification/request streams; transient reconnect-enabled failures keep the logical live session observable for reconnect or follow a documented session-replacement path.
  - Fix late timed-out/cancelled response handling so retired request IDs do not fail a healthy connection.
  - Tighten transport task access enough that send/receive/disconnect cannot race on mutable WebSocket task state in the covered paths.
  - Extend `ThreadDetailSession` and test fakes with the connection-state contract.
  - Teach `ThreadDetailStore` to mark the detail stale when the live session drops or its streams end.
  - Preserve existing notification/request-card behavior while adding the new state observation.
* Verification (required proof):
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
* Docs/comments (propagation; only if needed):
  - Add a short code comment at the connection-state boundary only if needed to explain why notification streams alone are not liveness.
* Exit criteria (all required):
  - Tests prove a connected client that receives a midstream close emits an offline/error state.
  - Tests prove explicit disconnect finishes streams and cancels observation cleanly.
  - Tests prove `connectionStates` is the primary liveness signal and emits terminal/drop state even when notification/request streams do not carry errors.
  - Tests prove transient transport failure follows the stream policy Phase 2 relies on: either notification/request streams remain usable across reconnect, or a documented session replacement path recreates them and `ThreadDetailStore` observes that path.
  - Tests prove a late response for a timed-out or cancelled request is ignored/logged as retired, while a response for a never-issued request still fails loudly.
  - Tests prove `ThreadDetailStore` no longer remains `.live` after the session reports a drop or stream end, and handles both connection-state drops and stream terminal events.
  - Existing tests for initialize, request multiplexing, notification delivery, server requests, typed thread methods, composer sends, and request-card responses still pass.
* Rollback:
  - Revert the state-stream and ThreadDetailStore observation changes together. Do not keep a client state stream that no store consumes.

## Phase 2 - Reconnect And Thread Rehydrate

* Goal:
  - Turn visible failure into transparent automatic recovery for the open thread detail path.
* Work:
  - Add bounded reconnect/backoff to live app-server clients and make `ThreadDetailStore` rejoin the same thread after reconnect using the compact detail path.
* Checklist (must all be done):
  - Add `AppServerConnectionPolicy` or equivalent configuration with reconnect disabled for one-shot operations and enabled for live detail sessions.
  - Implement bounded exponential backoff with jitter and cancellation on explicit disconnect/deinit.
  - Re-run `initialize` and `initialized` after reconnect before any domain rehydration.
  - Fail in-flight requests on transport failure; do not auto-replay non-idempotent user sends.
  - Add `ThreadDetailLiveState.reconnecting` or equivalent visible reconnect-in-progress state.
  - Split `ThreadDetailStore.load()` so initial load and reconnect rehydrate can share compact `thread/read includeTurns:false`, `thread/turns/list limit:10`, and `thread/resume excludeTurns:true`.
  - Preserve displayed events, request cards, active turn handling, composer draft, voice state safety, and failed-send recoverability across reconnect.
  - Keep manual retry secondary: automatic reconnect/rehydrate runs first, and the retry action appears only after exhaustion, unsafe recovery, missing configuration/authentication, or unrecoverable protocol/server failure.
* Verification (required proof):
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
* Docs/comments (propagation; only if needed):
  - Add a short boundary comment near rehydrate logic if needed to protect the compact read/turns/resume invariant.
* Exit criteria (all required):
  - Tests prove reconnect-enabled clients transition connected -> reconnecting -> connected after a scripted transport drop.
  - Tests prove reconnect stops when policy is exhausted or explicit disconnect is called.
  - Tests prove `ThreadDetailStore` reruns compact read, paged turns, and compact resume after reconnect.
  - Tests prove a scripted recoverable drop returns to live without manual user action.
  - Tests prove rehydration does not duplicate events or request cards.
  - Tests prove draft text and visible request-card state survive reconnect.
  - Tests prove non-idempotent sends are not silently replayed after transport failure.
* Rollback:
  - Revert reconnect policy and thread rehydrate together; Phase 1 stale visibility must remain if Phase 2 is rolled back independently during development.

## Phase 3 - App-Wide Connectivity Store And Indicator

* Goal:
  - Add one global connectivity source of truth and render it across the whole app.
* Work:
  - Introduce `AppConnectivityStore`, integrate host outcomes from Dock/Archive/Hosts/detail, move app-wide checking to root, and mount a compact root-level indicator.
* Checklist (must all be done):
  - Add `AppConnectivityStore` with per-host status, overall status, message, last checked time, last success time, and checking/reconnecting/stale/offline/error phases.
  - Treat nil bearer as valid host configuration. Connectivity may report auth failure only when a configured bearer endpoint rejects credentials or the relay/raw upstream returns an auth-class error.
  - Carry automatic recovery progress in the status model where useful, including retry attempt and next retry delay.
  - Add a small reporting protocol or root coordination path so Dock/Archive/Hosts/ThreadDetail can report facts without owning global truth.
  - Consume the Agents-plan loader/snapshot shape: default-human and Agents scoped query outcomes, `DockScopeLoadFailure`, and counted tabs should report into connectivity without duplicating tab predicates.
  - Make `CodexDockRootView` own `AppConnectivityStore`.
  - Update every `CodexDockRootView` initializer (`init(store:)`, `init(registry:)`, and `init(configurationError:)`) so each path creates or receives the same connectivity store and mounts the same indicator.
  - Map configuration-error or missing-host startup into the connectivity store as `unconfigured` or `configurationError`.
  - Update root registry-change handling so connectivity hosts stay in sync with Dock and Archive hosts.
  - Add root-level connectivity checking that does not depend on `DockView.runRefreshLoop()`.
  - Move Dock content auto-refresh to `CodexDockRootView` ownership and remove duplicate tab-local refresh ownership.
  - Add `GlobalConnectivityIndicatorView` and mount it from `CodexDockRootView` so it appears on Dock, Archive, Hosts, and pushed Session detail screens.
  - Keep the indicator passive: no direct app-server calls from UI.
  - Report Dock and Archive load successes/failures to the connectivity store.
  - Report Host settings manual test outcomes to the connectivity store.
  - Report Thread detail connection states to the connectivity store.
  - Fix Archive all-offline/all-error rendering so unreachable hosts are not presented as an empty archive.
  - Preserve existing Dock, Archive, Hosts, and Session detail UI behaviors except for the new indicator/status truth.
* Verification (required proof):
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test --filter AppConnectivityStoreTests`
  - `rtk swift test`
* Docs/comments (propagation; only if needed):
  - Add a small comment at the `AppConnectivityStore` rollup if the partial/stale precedence would be easy to misread.
* Exit criteria (all required):
  - Tests prove overall status for all-online, checking, partial outage, all-offline, stale/reconnecting detail, error, and configuration error.
  - Tests prove reconnecting status can report automatic retry progress without requiring a user action.
  - Tests prove manual host tests update the app-wide status.
  - Tests prove Dock/Archive load outcomes update the app-wide status.
  - Tests prove `AppConnectivityStore` consumes post-Agents scoped load outcomes: human/default succeeds + Agents fails, and Agents succeeds + human/default fails, both produce app-wide `partial` without rewriting `DockSnapshot.tabs`.
  - Tests prove connectivity reporting records `DockSnapshot.scopeLoadFailures` / `DockScopeLoadFailure` facts instead of treating a failed scope as `Agents 0`, all-offline, or empty.
  - Tests or focused code review prove Connectivity does not recompute tab counts and does not call `DockFilter.includes`; `DockTabID.includes(_:)` remains the single predicate for visible rows and counts.
  - Tests prove root initializer coverage for registry, legacy `init(store:)`, and configuration-error startup, or equivalent focused coverage proving all root paths mount the same indicator/store.
  - Bootstrap non-ready states (`.starting`, `.discovering`, `.failed`) either receive the same lifecycle/connectivity store and indicator, or are explicitly routed through `CodexDockRootView`; `CodexDockRootView(configurationError:)` alone is not sufficient bootstrap coverage.
  - Tests prove Archive all-offline/all-error does not show a normal empty archive message.
  - The indicator is mounted from root, not from tab-local headers.
  - Code review or focused test coverage proves `DockView.runRefreshLoop()` is removed and the root owns the refresh/check lifecycle.
* Rollback:
  - Revert `AppConnectivityStore` and indicator together. Do not leave tab-local duplicate status pills as a fallback.

## Phase 4 - App Background And Foreground Resume Lifecycle

* Goal:
  - Make iOS backgrounding an expected, elegant recovery state: foreground resume restarts checks, reconnects, and rehydrates without user action or false online/live labels.
* Work:
  - Add one root-owned lifecycle coordinator/store for SwiftUI `scenePhase`, wire it through bootstrap/root/detail/connectivity owners, pause foreground-only timers while backgrounded, and prove foreground resume uses the same reconnect/rehydrate path as transport recovery.
* Checklist (must all be done):
  - Add `AppLifecycleCoordinator` or an equivalent root-owned lifecycle type that models active, inactive, backgrounded, and foreground-resuming with a resume generation.
  - Observe `@Environment(\.scenePhase)` from `CodexDockBootstrapView` and/or `CodexDockRootView` and forward scene changes into the lifecycle owner.
  - Treat `.inactive` as transitional and avoid unnecessary disconnect/reconnect churn.
  - On `.background`, mark connectivity/background lifecycle state explicitly, pause or cancel root refresh/check timers, pause reconnect backoff timers without consuming retry budget, and keep existing snapshots/events visible but not labeled fresh.
  - On `.background`, stop or pause relay discovery when bootstrap has not reached `.ready`, without losing manual URL text or saved relay state.
  - On `.background`, tell open thread detail state that suspension is expected; preserve displayed events, request cards, active turn ID, composer draft, failed-send state, and do not auto-replay non-idempotent sends.
  - On `.background`, handle active voice capture safely through `VoiceCaptureControlling`: stop/cancel recording, deactivate the audio session, keep draft recoverable, and do not auto-submit on foreground resume.
  - On `.active` after background, publish foreground-resuming status, restart root refresh/check timers, restart relay discovery if bootstrap is still discovering, force immediate reachability/list refresh, and trigger open detail compact read/turns/resume before reporting online/live.
  - Keep Relay bootstrap discovery/saved-manual state in the same lifecycle path: foreground resume must restart discovery if bootstrap never reached `.ready`, but must not create duplicate discovery callbacks or lose manual URL text.
  - Route foreground resume through the same app-server reconnect and `ThreadDetailStore` compact rehydrate code paths added in Phases 1-2; do not add a parallel background-only recovery implementation.
  - Keep manual retry secondary: foreground resume should heal automatically when hosts are reachable and recovery is safe.
* Verification (required proof):
  - `rtk swift test --filter AppLifecycleCoordinatorTests` if a new test file exists, otherwise the focused lifecycle/root/store test filter.
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test --filter AppConnectivityStoreTests`
  - `rtk swift test`
* Docs/comments (propagation; only if needed):
  - Add a short comment only where scene-phase handling would otherwise look like an ordinary network failure path.
* Exit criteria (all required):
  - Tests prove background transition emits backgrounded/suspended status and does not report false unrecoverable errors.
  - Tests prove root refresh/check timers pause or cancel while backgrounded and restart with an immediate check on foreground active.
  - Tests prove reconnect backoff pauses while backgrounded and does not consume retry budget until the app is active again.
  - Tests prove foreground resume triggers `ThreadDetailStore` compact read, paged turns, and compact resume before `.live` returns.
  - Tests prove snapshots/events/request cards/draft survive background/resume without duplicate events or request cards.
  - Tests prove active voice capture is safely stopped/cancelled on background and does not auto-submit after resume.
  - Tests or focused code review prove scene-phase changes reach `RelayBootstrapStore` before `CodexDockRootView` exists.
  - Tests or focused code review prove foreground resume restarts Bonjour discovery or saved-manual handling when bootstrap has not reached `.ready`, without duplicate callbacks or lost manual URL text.
  - Tests or focused code review prove relay discovery restarts on foreground if bootstrap is still discovering and does not duplicate callbacks.
  - No tab-local scene-phase side door bypasses the root lifecycle owner.
* Rollback:
  - Revert lifecycle coordination as one unit. Do not leave partial per-screen background handlers, because that would recreate duplicate lifecycle truth.

## Phase 5 - Relay Recovery And Update Delivery Hardening

* Goal:
  - Make the phone-facing relay participate in the same robustness story instead of hiding upstream failures or cutting out live rows.
* Work:
  - Harden `scripts/dock-relay.mjs` and expand relay tests from helper-only coverage to deterministic in-process WebSocket behavior coverage.
* Checklist (must all be done):
  - Add testable relay seams or exports only as needed for in-process Node tests; do not add a second relay implementation.
  - Add upstream close callbacks to `JsonRpcWebSocketClient`.
  - Track downstream session resume params, selected endpoint, retry task, and closing state.
  - On upstream close, attempt bounded upstream reconnect/re-resume when downstream is still open and resume params are known.
  - If upstream recovery is unsafe or exhausted, close the downstream WebSocket explicitly so Swift sees a transport lifecycle event and can reconnect or mark stale.
  - Make `forwardToActiveUpstream` verify the upstream socket is actually open.
  - Change attention probing to call `thread/resume` with `excludeTurns:true`.
  - Change list merge/limit behavior so live loaded rows survive the relay limit before stored history fills remaining slots.
  - Keep `Needs me` strict: only real app-server attention flags or pending request replay can produce it.
  - Preserve auth rejection, `/readyz` / `/healthz`, history/live merge, archived-list history-only behavior, hidden `dockRelaySource`, and route-to-owning-upstream behavior.
* Verification (required proof):
  - `rtk node --check scripts/dock-relay.mjs`
  - `rtk npm test`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
* Docs/comments (propagation; only if needed):
  - Add concise comments only where relay upstream reconnect/re-resume cancellation rules are non-obvious.
* Exit criteria (all required):
  - Relay tests prove `phoneAuth: none` accepts missing `Authorization`, and explicit bearer mode rejects missing or bad `Authorization`.
  - Relay tests prove auth rejection and health endpoints.
  - Relay tests prove `thread/list` merges history and live rows.
  - Relay tests prove history failure with live success and live failure with history success behave as planned.
  - Relay tests prove `thread/turns/list` routes to the owning upstream.
  - Relay tests prove `thread/resume` forwards notifications and server requests downstream.
  - Relay tests prove upstream close is either recovered by re-resume or surfaced by downstream WebSocket close.
  - Swift tests prove the chosen downstream-close failure shape causes connection-state transition and thread detail stale/reconnecting behavior, not only a Node-side relay result.
  - Relay tests prove attention probing sends `excludeTurns:true`.
  - Relay tests prove live loaded rows are not cut out by newer stored history rows when a limit is applied.
* Rollback:
  - Revert relay hardening and tests together. Swift-side reconnect remains useful, but final acceptance cannot pass until relay behavior is restored.

## Phase 6 - Final Verification, Runbook, And Simulator Proof

* Goal:
  - Prove the full destination map and update live documentation so future runs know how connectivity works.
* Work:
  - Run the combined verification set, update live docs, and manually verify the global indicator/reconnect/background-resume behavior on the canonical simulator path.
* Checklist (must all be done):
  - Update `README.md` with global indicator states, reconnect behavior, background/resume behavior, relay/app-server status commands, and correct live-row priority wording.
  - Run `rtk swift test`.
  - Run `rtk node --check scripts/dock-relay.mjs`.
  - Run `rtk npm test`.
  - Run `rtk make services`.
  - Run `rtk make app-server-status`.
  - Run `rtk make dock-relay-status`.
  - Run or explicitly skip with reason the optional real phone-reachable smoke using `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510` with no `CODEX_DOCK_APP_SERVER_BEARER_TOKEN` or `CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE` in the app/test environment. `.codex-dock/app-server.token` stays host-side for `rtk make services` / relay history access only.
  - Run `rtk make app SIM='iPhone 17'`.
  - Manually verify the indicator is visible on Dock, Archive, Hosts, and Session detail.
  - Manually verify a relay/app-server interruption moves the indicator through reconnecting/offline/stale and returns to online/live without user action when services recover and the selected thread remains resumable.
  - Manually background the app from Dock and from an open Session detail, resume it, and verify the indicator moves through backgrounded/resuming/reconnecting as appropriate and returns to online/live without user action when services remain reachable.
* Verification (required proof):
  - Command output from the test/service/status/app commands above.
  - Manual simulator notes with exact date, simulator name, endpoint, background/resume steps, and observed indicator states.
* Docs/comments (propagation; only if needed):
  - README update is required in this phase.
* Exit criteria (all required):
  - All required tests pass, or any skipped real-host smoke has an explicit environment/access reason.
  - README matches the implemented connectivity behavior and no longer carries stale sorting/status wording.
  - `rtk make services`, `rtk make app-server-status`, and `rtk make dock-relay-status` have all run successfully before endpoint-dependent smoke/app checks.
  - Manual simulator check confirms the root indicator appears across every primary screen.
  - Manual simulator check confirms recoverable reconnect is automatic and fail-loud stale behavior is visible only when recovery cannot continue safely.
  - Manual simulator check confirms background/resume is expected and recoverable: root checks restart, detail rehydrates, and no manual reconnect/navigation is required while services are reachable.
  - No unplanned duplicate connectivity status owner remains.
* Rollback:
  - If final verification fails, reopen the phase whose contract failed; do not weaken this phase by editing acceptance criteria down.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. "Non-blocking" here means no extra ceremony or artificial gates; it does not make phase proof optional. Each phase's `Verification` and `Exit criteria` are required for that phase, and Phase 6's final tests/runbook/simulator proof are required for the whole plan. The optional real phone-reachable smoke may be skipped only with an explicit environment or access reason. Prefer existing credible checks that prove the behavior directly. Add focused tests for new lifecycle contracts and reconnection behavior. Keep visual/manual checks short and realistic. Do not add repo-policing scripts, deletion-proof tests, doc inventory gates, or fragile visual constants.

## 8.1 Unit tests (contracts)

- `CodexDockTests/AppServerClientTests.swift`: connection-state stream, stream terminal behavior, late responses after timeout/cancel, reconnect/backoff policy, explicit disconnect, and transport race boundaries.
- `CodexDockTests/ThreadDetailStoreTests.swift`: stale/reconnecting/live transitions, rehydration after reconnect, preserved events/request cards/draft, resume failure after reconnect.
- `CodexDockTests/AppConnectivityStoreTests.swift`: app-wide connectivity rollup from host outcomes, manual host tests, detail reconnect/stale states, configuration error, and partial/all-offline cases.
- `CodexDockTests/AppLifecycleCoordinatorTests.swift` or focused root/store tests: active/inactive/background/foreground-resume transitions, refresh/check timer pause/restart, resume-generation delivery, bootstrap discovery restart, and background status rollup.
- `CodexDockTests/DockStoreTests.swift` or focused store tests: Archive all-offline state and reporting hooks from Dock/Archive/Hosts into the connectivity store.

## 8.2 Integration tests (flows)

- `scripts/dock-relay.test.mjs`: auth, health, history/live merge, partial source failure, owning-upstream routing, resume notification/request forwarding, upstream close/reconnect/downstream fail-loud behavior, compact `excludeTurns:true` attention probing, and live-row-preserving limits.
- Existing `rtk swift test` for the Swift package.
- Existing `rtk npm test` for the relay.

## 8.3 E2E / device tests (realistic)

- `rtk make services` starts/reuses raw app-server plus relay.
- `rtk make app SIM='iPhone 17'` launches the app with `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510`.
- Manual final check: global indicator is visible on Dock, Archive, Hosts, and Session detail; stopping/restarting relay or app-server moves the indicator through reconnect/offline/live and detail returns to live without user action when the thread remains resumable; backgrounding/resuming from Dock and Session detail moves through backgrounded/resuming/reconnecting as appropriate and returns to online/live automatically while services remain reachable.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Implement behind no runtime flag. This is a hardening refactor of the current app behavior, not an alternate mode. Keep the existing host environment variables, service targets, and relay endpoint. Update tests before relying on manual simulator proof.

## 9.2 Telemetry changes

No external telemetry is required. Add local state fields and logs only where they help debug the existing local service path: last checked time, last transition reason, retry attempt, next retry delay, and host endpoint.

## 9.3 Operational runbook

Update `README.md` after implementation to explain:

- what the global connectivity indicator states mean;
- how automatic reconnect behaves for app-server and relay drops, including retry progress and the narrow cases where manual action is required;
- how background/resume behaves, including backgrounded/resuming indicator states and why long-running background WebSocket delivery is not required;
- how to verify services with `rtk make app-server-status` and `rtk make dock-relay-status`;
- how to run the simulator check with `rtk make app SIM='iPhone 17'`.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Section 0 through Section 10, planning passes, auto-plan receipts, and helper-block drift.
  - Owner path consistency across `AppServerClient`, `ThreadDetailStore`, `AppConnectivityStore`, `AppLifecycleCoordinator`, `CodexDockRootView`, `CodexDockBootstrapView`, and `scripts/dock-relay.mjs`.
  - Phase checklist and exit-criteria coverage for reconnect, rehydrate, global indicator, background/resume lifecycle, relay hardening, tests, docs, and simulator proof.
- Findings summary:
  - Cold readers agreed the core architecture is aligned but flagged stale helper metadata, verification wording, missing service-status proof, branchy Dock refresh ownership, missing stream-contract proof, incomplete relay fail-loud Swift proof, and root initializer coverage.
- Integrated repairs:
  - Marked external research as not required for this repo-grounded auto-plan.
  - Clarified Section 8: low bureaucracy does not make phase proof optional.
  - Reordered final verification so services/status checks run before endpoint-dependent smoke/app checks and added `rtk make app-server-status`.
  - Chose `CodexDockRootView` as the recurring Dock refresh/check lifecycle owner and required `DockView.runRefreshLoop()` removal.
  - Made `connectionStates` the primary liveness signal and added Phase 1 stream-contract exit criteria.
  - Chose downstream WebSocket close as the relay fail-loud contract for unrecoverable upstream death and added Swift proof obligations.
  - Required all `CodexDockRootView` initializer paths to create or receive the same `AppConnectivityStore` and required `AppConnectivityStoreTests`.
  - Added a dedicated background/resume lifecycle phase with root-owned scene-phase coordination, foreground revalidation, detail rehydrate, bootstrap discovery restart, voice safety, tests, and simulator proof.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Intent-derived: approved active connectivity resilience plan

Blocker: ArchStep normally leaves a new doc in draft until the North Star is confirmed, but the user directly asked for a full auto-plan path for robust connectivity, update delivery, and global status indication.

Consulted: current user objective, TL;DR, Section 0.

Intent says: the app should be deeply audited, the plan should make connectivity extremely robust, the UI should indicate dropped/connected state on every screen, and ArchStep plus plan-audit should agree the plan is fully formed.

Decision: seed this document as `status: active` and continue through auto-plan receipts without stopping for a separate confirmation question.

Consequences: no product-scope question is needed before research/deep-dive because the requested destination is explicit. If later code evidence reveals a real fork, the plan must record it as a decision gap instead of guessing.

## 2026-05-28 - Intent-derived: root-owned connectivity store

Blocker: The indicator could be mounted inside Dock near the disabled plus button, inside each tab header, or at the app root.

Consulted: TL;DR, Section 0.2, Section 0.5, Section 4.5, and user objective.

Intent says: connectivity status should appear on every screen, and the user specifically wants dropped/connected state visible globally.

Decision: make `CodexDockRootView` own `AppConnectivityStore` and mount one root-level `GlobalConnectivityIndicatorView`. Do not duplicate global status logic inside `DockView`, `ArchiveView`, `HostsView`, or `SessionDetailView`.

Consequences: tab/detail stores report facts to the root-owned store. The indicator can still sit visually near the top-right/plus-button region, but its owner is root-level.

## 2026-05-28 - Intent-derived: relay must not hide upstream death

Blocker: The relay can either reconnect/re-resume upstream itself or fail-loudly by closing downstream so Swift reconnects.

Consulted: TL;DR, Section 0.1, Section 0.5, Section 5.2, and Section 5.4.

Intent says: dropped connections must be restored when possible and must be indicated when not restored.

Decision: the relay should first attempt bounded upstream reconnect/re-resume when the downstream session is still open and the resume params are known. If that cannot be done safely or retry is exhausted, the relay must close the downstream WebSocket so Swift sees a transport lifecycle event and can reconnect or show stale state.

Consequences: relay implementation needs session resume state, upstream close callbacks, cancellation on downstream close, and tests for both recovery and downstream-close fail-loud paths.

## 2026-05-28 - Intent-derived: root owns recurring Dock freshness

Blocker: Dock recurring refresh could live in `CodexDockRootView`, in `DockStore`, or stay in `DockView`.

Consulted: TL;DR, Section 0.5, Section 5.2, Section 6.1, and the current `DockView.runRefreshLoop()` implementation.

Intent says: connectivity should be app-wide and visible on every screen, so freshness cannot depend on the Dock tab view task being mounted.

Decision: `CodexDockRootView` owns the recurring refresh/check lifecycle. `DockStore` remains a content store exposing `load()` and `refresh()`. `DockView.runRefreshLoop()` must be removed.

Consequences: Phase 3 has to update root lifecycle wiring and prove the tab-local loop is gone or no longer authoritative.

## 2026-05-28 - Intent-derived: transparent automatic recovery first

Blocker: The app can ask the user to reconnect when a drop is detected, or it can reconnect automatically while only showing what the client is doing.

Consulted: latest user clarification, TL;DR, Section 0, Section 5.2, Section 5.5, Section 7, and Section 9.3.

Intent says: the client should tell the user what is happening, but if it can figure out a disconnect itself, the user should not have to deal with it.

Decision: automatic retry, reconnect, and thread rehydration are the default for recoverable drops. User action appears only after retry exhaustion, unsafe recovery, missing configuration/authentication, or unrecoverable protocol/server failure.

Consequences: Phase 2 and Phase 6 proof must show that a scripted recoverable drop requires no user action, while the indicator reports progress during recovery.

## 2026-05-28 - Intent-derived: backgrounding is expected lifecycle, not failure

Blocker: Background/resume can be treated as an ordinary transport failure, ignored as implicit iOS behavior, or modeled as an owned app lifecycle state with foreground recovery.

Consulted: latest user clarification, TL;DR, Section 0, Section 2.2, Section 5.2, Section 6.1, Section 7 Phase 4, and current `CodexDockApp`, `CodexDockBootstrapView`, `CodexDockRootView`, `RelayBootstrapStore`, `ThreadDetailStore`, and `VoiceCaptureController` code.

Intent says: backgrounding should be an expected, accepted, elegant get-well-working state. On resume, the app should do the right reconnect/revalidate/rehydrate work automatically and tell the user what is happening.

Decision: add a dedicated background/resume lifecycle phase. Root/bootstrap owns SwiftUI scene-phase translation; background pauses foreground-only refresh/discovery/retry work without spending retry budget or reporting false unrecoverable errors; foreground active restarts checks, relay discovery if needed, and open-thread compact rehydrate before returning to online/live.

Consequences: long-running background WebSocket delivery remains out of scope, but foreground resume is now in scope and must be proven by lifecycle tests plus simulator background/resume notes. The plan must not allow tab-local scene-phase side doors or a separate background-only reconnect implementation.
