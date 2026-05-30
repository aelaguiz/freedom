---
title: "Codex Dock - Observability Logging Framework - Architecture Plan"
date: 2026-05-28
status: complete
fallback_policy: forbidden
owners: [Amir]
reviewers: [Codex]
doc_type: architectural_change
superseded_by:
  - docs/CODEX_DOCK_OBSERVABILITY_ARCHITECTURE_2026-05-30.md
related:
  - https://developer.apple.com/documentation/os/logging
  - https://developer.apple.com/documentation/os/logger
  - https://developer.apple.com/documentation/os/ossignposter
  - https://developer.apple.com/documentation/metrickit
  - https://nodejs.org/api/process.html
  - https://nodejs.org/api/console.html
---

# TL;DR

Superseded scope note, 2026-05-30: this document remains the historical logging
framework record. The current route-health, trace, bundle, and multi-host
diagnostics source of truth is
`docs/CODEX_DOCK_OBSERVABILITY_ARCHITECTURE_2026-05-30.md`.

- Outcome: Codex Dock has a single, idiomatic logging and diagnostics pattern that lets Amir inspect simulator, physical iPhone, and Mac relay behavior without adding secrets to the app or changing product behavior.
- Problem: The app currently reports user-visible state, but it does not leave a reliable event trail across WebSocket lifecycle, relay discovery, dock/archive loads, thread detail reconnects, voice capture, realtime transcription, local persistence, or relay failures.
- Approach: Use Apple's unified logging system through `OS.Logger` and `OSSignposter` in Swift, use one structured stderr logger for the Node relay, subscribe to MetricKit for crash/hang diagnostics, and document exact capture commands in `AGENTS.md`.
- Plan: First add the central logging primitives and one real end-to-end network slice, then widen through stores, voice, bootstrap/discovery, relay logging, crash diagnostics, and agent instructions.
- Non-negotiables: no raw `OPENAI_API_KEY`, bearer token, audio bytes, base64 audio, prompt text, transcript text, or full JSON-RPC payloads in logs; no global crash recovery; no parallel ad hoc `print` / `console.error` style after the logger exists.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:dc6e1611b78a6ad841238f34bbe703a47b0c1d443ea18e5b02b51eb161a959ed",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T17:50:48Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:9c1f3553683055ad87595de1bddcb4f2daf47e59a0d073644735253e4700c859",
      "completed_at": "2026-05-28T17:51:21Z",
      "doc_hash_after": "sha256:73c1b636783e9e6fad9fc52db03b58650279fd7932a240f19396444a0c019ec2"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T17:51:25Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:73c1b636783e9e6fad9fc52db03b58650279fd7932a240f19396444a0c019ec2",
      "completed_at": "2026-05-28T17:52:53Z",
      "doc_hash_after": "sha256:1679596b4b674c1138619ca9c4c47ec3c5509f4b6981dd14e669a1b0b914d155"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T17:53:01Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:1679596b4b674c1138619ca9c4c47ec3c5509f4b6981dd14e669a1b0b914d155",
      "completed_at": "2026-05-28T17:53:17Z",
      "doc_hash_after": "sha256:15fb316359282e705c1593aa2cdd9a30e5ef2d030008a6e5abc5191aba036e94"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T17:53:23Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:15fb316359282e705c1593aa2cdd9a30e5ef2d030008a6e5abc5191aba036e94",
      "completed_at": "2026-05-28T17:54:18Z",
      "doc_hash_after": "sha256:73f1b7bf5511ef01808ae42fa0efbc29b0e9ec5053232374ab45fbe6d8e774ec"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T17:54:25Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:73f1b7bf5511ef01808ae42fa0efbc29b0e9ec5053232374ab45fbe6d8e774ec",
      "completed_at": "2026-05-28T17:56:21Z",
      "doc_hash_after": "sha256:df25a9cea307c12573dcbd36cebb92a22719cbe1380b84077cec1429bfa116b9"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, a simulator run and a physical iPhone run can both be debugged by filtering one Swift subsystem and the relay log stream. For a failed dock load, stale thread detail, voice/transcription failure, or relay upstream loss, logs should show the high-level sequence, host, method or operation, result, error class, and timing without exposing secrets or user content.

## 0.2 In scope

- Swift logging framework:
  - A central diagnostics/logging owner under `CodexDock/Diagnostics/**`.
  - Static `Logger` categories for app lifecycle, bootstrap/discovery, host configuration, app-server client, dock, archive, thread detail, connectivity, voice capture, realtime transcription, local persistence, and MetricKit diagnostics.
  - `OSSignposter` intervals for high-value async operations where duration matters.
  - Privacy helpers and a short call-site style guide so new logs stay readable and safe.
- Swift call-site instrumentation:
  - App launch and scene/lifecycle transitions.
  - Relay bootstrap and Bonjour discovery.
  - Host registry parsing and manual host testing.
  - App-server WebSocket connect/initialize/send/receive/reconnect/disconnect behavior.
  - Dock/archive loads, partial failures, mapping failures, scope conflicts, archive/unarchive actions, and metadata persistence failures.
  - Thread detail load/read/turns/resume/reconnect/stale transitions, sends, request-card responses, and stream termination.
  - Voice capture permission/start/stop/cancel/interruption/route-change paths.
  - Relay realtime transcription session start/append/commit/cancel/delta/completed/failed/closed paths, using counts and IDs only.
- Node relay instrumentation:
  - One structured logger module for relay events currently printed with `console.error`.
  - Startup, readyz, upgrade/auth, connection open/close, thread/list aggregation, loaded-row discovery, upstream resume/recovery, archive/unarchive, transcription bridge, Bonjour advertisement, shutdown, and fatal-process monitor logs.
  - LaunchAgent-compatible stderr output, because `.codex-dock/dock-relay.err.log` is already the service log path.
- Crash and exception capture:
  - Swift MetricKit subscriber for crash, hang, CPU exception, app launch, and disk write diagnostics where the platform supplies them.
  - Swift precondition/fault pattern: log `fault` immediately before intentional invariant crashes, then let the crash happen.
  - Node `uncaughtExceptionMonitor` / fatal report logging that observes fatal failures without attempting to resume normal relay operation.
- Debug capture:
  - Makefile or README/AGENTS commands for simulator log streaming and physical device log collection.
  - `AGENTS.md` logging instructions authored as concise always-on repo guidance.

## 0.3 Out of scope

- No third-party crash reporter, analytics SaaS, remote upload service, or external dashboard in this pass.
- No in-app debug console, log viewer UI, or "send logs" user workflow.
- No phone-side OpenAI key, relay bearer token, or provider configuration.
- No raw transcript, prompt, audio, full WebSocket frames, full JSON-RPC payloads, or `.env` values in logs.
- No attempt to catch or recover arbitrary Swift crashes or Node uncaught exceptions.
- No broad rewrite of app state architecture just to make logs prettier.

## 0.4 Definition of done (acceptance evidence)

- Swift package checks pass:
  - `rtk swift test`
  - Targeted first checks while implementing: `rtk swift test --filter AppServerClientTests`, `rtk swift test --filter DockStoreTests`, and `rtk swift test --filter ThreadDetailStoreTests`.
- Node relay checks pass:
  - `rtk npm run test:relay`
- App target proof passes when app/project files are touched:
  - `rtk xcodegen generate --spec project.yml`
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Simulator log proof:
  - `rtk make app SIM='iPhone 17'`
  - `rtk xcrun simctl spawn booted log stream --style compact --predicate 'subsystem BEGINSWITH "com.aelaguiz.CodexDock"' --timeout 60`
  - The stream shows app launch, relay/bootstrap, dock refresh, and at least one app-server client operation without secrets or user content.
- Physical device proof:
  - `rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>`
  - `rtk xcrun log collect --device-udid <device-udid> --last 10m --predicate 'subsystem == "com.aelaguiz.CodexDock"' --output /tmp/codex-client/codex-dock-device.logarchive`
  - The collected archive contains the same category pattern after a real relay-backed launch.
- Relay proof:
  - `rtk make services`
  - `rtk make dock-relay-status`
  - `rtk tail -n 80 .codex-dock/dock-relay.err.log`
  - Relay log lines are structured, include operation/result/timing, and do not include bearer tokens, OpenAI keys, prompt text, transcript text, or base64 audio.
- Documentation proof:
  - `AGENTS.md` contains concise logging instructions and exact capture commands.
  - If only `AGENTS.md` changes in the doc phase, read it back and check `rtk git status --short`; app tests are not needed for that docs-only edit.

## 0.5 Key invariants (fix immediately if violated)

- Logs must be useful on simulator and physical iPhone; loopback-only proof is not enough for the phone path.
- Swift logs use `OS.Logger`; no new Swift `print`, `debugPrint`, `dump`, or `NSLog` call sites.
- Relay logs use the relay logger; no new direct `console.error` except inside the logger implementation itself.
- Secrets and user content stay out of logs.
- Error/fault logs include enough stable context to identify the failing operation, but not raw payloads.
- MetricKit and fatal monitors report diagnostics; they do not swallow or recover crashes.
- Logging must not alter app behavior, retry behavior, connection state, or service lifecycle.
- High-volume events must be `debug` / signposted / summarized; they must not flood persistent logs.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Privacy and secret safety.
2. Accurate event sequence across Swift app, physical phone path, and Mac relay.
3. Swift-native elegance: `Logger`, static categories, privacy interpolation, and `OSSignposter`.
4. Minimal custom infrastructure and tiny-team maintainability.
5. Easy capture commands for simulator, physical iPhone, and relay services.
6. Behavior preservation: logs must observe existing code paths without changing outcomes.

## 1.2 Constraints

- The app target is generated from `project.yml`; target/framework changes must update `project.yml` first and regenerate.
- Normal app and phone traffic goes to the Dock relay at `ws://192.168.50.117:4510`, not the raw authenticated app-server at `:4500`.
- `.env` is user-owned and must not be rewritten.
- `OPENAI_API_KEY` and raw app-server bearer tokens stay on the Mac side.
- Simulator/device launch must not pass OpenAI keys or raw app-server bearer tokens into the app.
- Existing tests use fake transports and stores heavily; logging should be injectable only where needed for tests, not through broad dependency plumbing.
- Node relay service logs already land in `.codex-dock/dock-relay.log` and `.codex-dock/dock-relay.err.log` through LaunchAgent paths.

## 1.3 Architectural principles (rules we will enforce)

- The Swift owner is `CodexDock/Diagnostics/**`; callers use `DockLog.<category>` static loggers and import `OS` where direct `Logger`, `OSLogType`, or `OSSignposter` types are needed.
- Do not hide `Logger` behind a generic stringly wrapper that loses compile-time interpolation/privacy behavior.
- Prefer category-specific static loggers plus small privacy/redaction helpers over a custom logging DSL.
- Use signposts for duration boundaries, not as replacements for state-transition logs.
- Log operation boundaries and results; avoid logging raw data.
- Node relay logs are one-line structured records written to stderr by one logger module.
- Fatal diagnostics are observation-only; recovery remains owned by existing app/relay lifecycle code.
- New tests should check redaction/format helpers and behavior preservation, not brittle log text.

## 1.4 Known tradeoffs (explicit)

- We will not add a third-party crash reporter now. MetricKit plus native log collection is enough for local simulator and physical device debugging, and avoids account setup, privacy policy work, and SDK lifecycle cost.
- We will not make an in-app log viewer now. Native log collection is more reliable for crashes and background/system behavior.
- We will accept that `debug` logs may require debug-enabled collection while `error`/`fault` logs are easier to retrieve later.
- We will not test every log line text. The important behavior is safe, centralized logging and observable event coverage.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

- Swift code has clear state machines and error surfaces, but no central logging owner.
- Relay code emits some human text through direct `console.error`, mostly in failure or summary paths.
- Service logs are already routed to `.codex-dock/**.log` files by `Makefile` LaunchAgent targets.
- README and AGENTS explain service paths and verification commands, but not log capture patterns.

## 2.2 What's broken / missing (concrete)

- When a physical iPhone path fails, the app can show offline/stale/error UI but there is no reliable event trace to explain which operation failed.
- WebSocket lifecycle, reconnect loops, stream endings, mapping failures, voice capture failures, and relay upstream recovery are hard to reconstruct after the fact.
- Direct relay `console.error` logs are inconsistent and not centrally redacted.
- Crash diagnostics are not surfaced through a first-party path.
- Future agents have no concise logging guidance, so new debugging output would likely drift into ad hoc `print` / `console.error` calls.

## 2.3 Constraints implied by the problem

- The logging framework must be low-friction enough to use throughout existing code.
- It must support simulator and physical device proof, not just Swift tests.
- It must correlate app and relay behavior without introducing a secret-bearing cross-system telemetry protocol.
- It must make common failures visible without storing user content.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- Apple unified logging, `https://developer.apple.com/documentation/os/logging` - adopt. Apple positions unified logging as the native way to capture app telemetry for debugging and performance analysis, including when a debugger is not attached or issues are intermittent.
- Apple `Logger`, `https://developer.apple.com/documentation/os/logger` - adopt. `Logger` is the Swift-native logging API, supports subsystem/category filtering, severity levels, and privacy-aware interpolation. This should be the app-side core instead of custom file logging or `print`.
- Apple `OSSignposter`, `https://developer.apple.com/documentation/os/ossignposter` - adopt narrowly. Signposts are useful for measuring task intervals in Instruments and logs; they should wrap high-value async operations such as `thread/list`, `thread/read` + `thread/resume`, and transcription commit latency.
- Apple MetricKit, `https://developer.apple.com/documentation/metrickit` - adopt for local crash/hang diagnostics. MetricKit delivers on-device diagnostics and performance reports, including crash diagnostics, without adding a third-party SDK.
- Apple `MXCrashDiagnostic`, `https://developer.apple.com/documentation/metrickit/mxcrashdiagnostic` - adopt as the crash-report object to summarize and persist locally. It exposes exception details and call stack data when the OS delivers a diagnostic payload.
- Node.js `process`, `https://nodejs.org/api/process.html` - adopt for fatal-process observation only. `uncaughtExceptionMonitor` can observe fatal exceptions without changing the default crash behavior; avoid `uncaughtException` recovery because Node documents it as unsafe for normal continuation.
- Node.js `console`, `https://nodejs.org/api/console.html` - adopt the stdout/stderr model, but wrap it. The relay should keep LaunchAgent-compatible stderr output while centralizing formatting/redaction through one logger module.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors (do not reinvent):
  - `Makefile` - canonical service, simulator, physical device, and generated log-file paths. It already routes raw app-server and relay stdout/stderr to `.codex-dock/app-server.log`, `.codex-dock/app-server.err.log`, `.codex-dock/dock-relay.log`, and `.codex-dock/dock-relay.err.log`.
  - `README.md` - product/service runbook, physical-phone rule, relay path, lifecycle behavior, and local service expectations.
  - `AGENTS.md` - repo-wide command map, service-path rules, secret handling, and the exact place to add concise logging instructions.
  - `project.yml` - generated Xcode project source of truth; any app target/framework setting change must be made here first.
  - `Package.swift` - SwiftPM package, iOS 26.0 / Swift 6.0 constraints, and test target wiring.
  - `package.json` - Node relay test entrypoint and dependency set.
- Canonical path / owner to reuse:
  - New `CodexDock/Diagnostics/Logging.swift` - should own Swift subsystem/category construction, privacy helpers, and signposter factories.
  - New `CodexDock/Diagnostics/MetricKitDiagnosticsReporter.swift` - should own MetricKit subscription and local crash/hang diagnostic logging.
  - New `scripts/dock-relay-logger.mjs` - should own relay structured logging and secret-safe formatting.
  - `Makefile` - should own any new log capture targets because it is the runnable command source of truth.
  - Root `AGENTS.md` - should own always-on logging rules and capture commands after implementation.
- Adjacent surfaces tied to the same contract family:
  - `CodexDock/AppServer/AppServerClient.swift` - WebSocket, JSON-RPC, reconnect, pending-request, transport-loss, and stream-ending instrumentation.
  - `CodexDock/AppServer/JSONRPC.swift` and DTO files - contract surface for method names and payload shapes; logs should use method names/counts/IDs, not raw payloads.
  - `CodexDock/State/DockStore.swift` and `CodexDock/State/ArchiveStore.swift` - session-list fan-out, partial failures, mapping failures, archive/unarchive actions, and local metadata read failures.
  - `CodexDock/State/ThreadDetailStore.swift` - compact read/resume flow, live stream observation, reconnect/rehydrate/stale state, sends, server request cards, and voice orchestration.
  - `CodexDock/State/AppConnectivityStore.swift` and `CodexDock/State/AppLifecycleCoordinator.swift` - global connectivity and foreground/background state transitions.
  - `CodexDock/State/HostSettingsStore.swift` - host test and saved host mutation behavior.
  - `CodexDock/Configuration/RelayBootstrapStore.swift` and `CodexDock/Configuration/RelayDiscovery.swift` - environment bootstrap, Bonjour discovery, saved/manual relay configuration, and backgrounded discovery behavior.
  - `CodexDock/State/LocalThreadMetadataStore.swift` and `CodexDock/Configuration/RelayDiscovery.swift` local config store - local Application Support read/write failure points.
  - `CodexDock/Voice/VoiceCaptureController.swift` - microphone permission, simulator rejection path, AVAudioSession/AVAudioEngine startup, interruptions, route changes, stop/cancel, and chunk generation.
  - `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` and `CodexDock/Voice/TranscriptionService.swift` - phone-to-relay transcription session lifecycle and sanitized event logging.
  - `CodexDockApp/CodexDockApp.swift` - app bootstrap hook for diagnostics coordinator / MetricKit subscriber.
  - `scripts/dock-relay.mjs`, `scripts/dock-relay-json-rpc-client.mjs`, `scripts/dock-relay-realtime-transcription.mjs`, and `scripts/dock-relay-bonjour.mjs` - relay startup, JSON-RPC client, OpenAI Realtime bridge, Bonjour advertisement, and current direct `console.error` sites.
  - `CodexDockTests/**` and `scripts/dock-relay*.test.mjs` - behavior-preservation proof surfaces and places to add test doubles for logger formatting/redaction where useful.
- Compatibility posture (separate from `fallback_policy`):
  - Preserve existing runtime contracts. Logging observes existing paths and should not change public Swift APIs except for adding optional/internal logger dependencies if a test needs them.
  - Clean cutover for logging style. Once relay logger exists, direct relay `console.error` call sites should migrate to it in the same implementation arc.
  - No runtime bridge. Existing behavior either emits through the new logging owner or stays uninstrumented until its phase, but no compatibility shim should duplicate logging.
- Existing patterns to reuse:
  - `AppConnectivityStore` reporting pattern - reuse its state knowledge as log context; do not replace it with logging.
  - `AppServerClientError`, `DockLoadFailure`, `ThreadDetailStoreError`, `VoiceCaptureError`, and `RelayRealtimeTranscriptionClientError` - use existing error classification for log severity and messages.
  - Existing fake transports/loaders in tests - use them to prove behavior stays intact after instrumentation.
  - LaunchAgent stderr log files from `Makefile` - keep relay logging compatible with current service management.
- Prompt surfaces / agent contract to reuse:
  - `AGENTS.md` already owns repo-wide agent behavior. Use `agents-md-authoring` guidance to add concise, command-first logging instructions without turning `AGENTS.md` into an architecture essay.
- Native model or agent capabilities to lean on:
  - Not applicable to product behavior. The only agent-facing change is repo instruction text in `AGENTS.md`.
- Existing grounding / tool / file exposure:
  - Simulator logs can be streamed by running `log stream` inside the booted simulator with `rtk xcrun simctl spawn booted log stream ...`.
  - Physical iPhone logs can be collected from a paired device with `rtk xcrun log collect --device-udid <device-udid> ...`.
  - Relay logs can be tailed from `.codex-dock/dock-relay.err.log`.
- Duplicate or drifting paths relevant to this change:
  - Existing direct `console.error` relay call sites will drift unless migrated to one relay logger.
  - New Swift logging must not create a generic wrapper plus direct `Logger` pattern competing for ownership; use static categories and small helpers only.
  - Do not add local text log files for ordinary app events; that would compete with unified logging and add storage/privacy burden.
- Capability-first opportunities before new tooling:
  - Use native `Logger` privacy and OS log collection before adding custom file export.
  - Use MetricKit before adding third-party crash SDK.
  - Use existing LaunchAgent stderr logs before adding a relay log transport.
- Behavior-preservation signals already available:
  - `rtk swift test --filter AppServerClientTests` - JSON-RPC, transport, reconnect, timeout, and failure-state preservation.
  - `rtk swift test --filter DockStoreTests` - dock load, partial failure, archive, multi-host, and mapping behavior.
  - `rtk swift test --filter ThreadDetailStoreTests` - detail load, reconnect/stale/live events, composer, request-card, and voice/transcription flows.
  - `rtk swift test` - broad Swift behavior preservation after cross-cutting instrumentation.
  - `rtk npm run test:relay` - relay behavior preservation after structured logger migration.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build` - generated app target proof when app bootstrap/MetricKit wiring changes.

## 3.3 Decision gaps that must be resolved before implementation

- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- Swift package/app:
  - `CodexDockApp/CodexDockApp.swift` owns the SwiftUI app entrypoint and currently only presents `CodexDockBootstrapView()`.
  - `CodexDock/AppServer/AppServerClient.swift` owns `AppServerClient`, `AppServerTransport`, `URLSessionWebSocketAppServerTransport`, connection state, JSON-RPC request/response matching, timeout handling, receive loop, and live-detail reconnect policy.
  - `CodexDock/AppServer/JSONRPC.swift` owns JSON value/message encoding and decoding.
  - `CodexDock/Configuration/DockHostConfiguration.swift`, `HostRegistry.swift`, `RelayBootstrapStore.swift`, and `RelayDiscovery.swift` own environment parsing, host registry, manual/saved relay config, and Bonjour discovery.
  - `CodexDock/State/DockStore.swift`, `ArchiveStore.swift`, `HostSettingsStore.swift`, `ThreadDetailStore.swift`, `AppConnectivityStore.swift`, `AppLifecycleCoordinator.swift`, and `LocalThreadMetadataStore.swift` own UI state, fan-out, foreground/background behavior, and local persistence.
  - `CodexDock/Voice/VoiceCaptureController.swift`, `TranscriptionService.swift`, and `RelayRealtimeTranscriptionClient.swift` own live audio capture and phone-to-relay transcription sessions.
  - There is no `CodexDock/Diagnostics/**` owner today.
- Node relay:
  - `scripts/dock-relay.mjs` owns service startup, readyz/healthz, phone WebSocket upgrades, JSON-RPC dispatch, live/history aggregation, active upstream resume/recovery, archive/unarchive, transcription manager creation, Bonjour process lifecycle, and shutdown handlers.
  - `scripts/dock-relay-json-rpc-client.mjs` owns upstream WebSocket JSON-RPC client behavior.
  - `scripts/dock-relay-realtime-transcription.mjs` owns OpenAI Realtime transcription bridging, provider-config rejection, audio validation, upstream event handling, and transcription notifications.
  - `scripts/dock-relay-bonjour.mjs` owns `dns-sd` Bonjour advertisement.
  - There is no `scripts/dock-relay-logger.mjs` owner today.
- Repo instructions and commands:
  - `Makefile` is the command source of truth for app, device, services, and LaunchAgent log paths.
  - Root `AGENTS.md` is the always-on agent instruction file that should receive concise logging instructions after implementation.

## 4.2 Control paths (runtime)

- Simulator/local launch:
  - `rtk make app SIM='iPhone 17'` starts/reuses services, regenerates Xcode project, builds, installs, and launches the simulator app with relay host env vars.
  - Swift app starts at `CodexDockApp`, then `CodexDockBootstrapView` creates bootstrap/connectivity/lifecycle stores and eventually `DockView`.
- Physical iPhone launch:
  - `rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>` starts services, regenerates project, builds for device, and installs. Normal app launch relies on saved/manual relay config or Bonjour discovery; it must not receive OpenAI keys or raw app-server bearer tokens.
- Relay bootstrap:
  - `RelayBootstrapStore.start()` first tries `HostRegistry.fromEnvironment`, then Bonjour discovery, then saved manual URL fallback.
  - `BonjourRelayDiscovery` searches `_codexdock._tcp.local.`, resolves NetService records, and creates `DiscoveredRelay` values with non-secret TXT metadata.
- Dock/archive loads:
  - `DockStore.reload()` loads local metadata, fans out active human/agent scopes per host through `DockSessionLoading`, maps rows, deduplicates cross-scope rows, builds `DockSnapshot`, and reports connectivity.
  - `ArchiveStore.reload()` loads archived rows across hosts and reports archive connectivity.
  - `AppServerDockClient.withClient()` opens a short-lived `AppServerClient`, initializes it, performs `thread/list`, `thread/archive`, or `thread/unarchive`, then disconnects.
- Thread detail live path:
  - `ThreadDetailStore.load()` validates host/thread, creates a live-detail `AppServerClient`, connects, starts observation, runs compact `thread/read includeTurns:false`, `thread/turns/list limit:10`, then `thread/resume excludeTurns:true`.
  - Connection state, notifications, and server requests flow through AsyncStreams into `ThreadDetailStore` handlers.
  - Reconnect/rehydrate runs when `AppServerClient` reports reconnect/live states and foreground work is allowed.
- Voice/transcription:
  - `ThreadDetailStore.beginVoiceCapture()` starts a relay realtime transcription session, starts `LiveVoiceCaptureController`, observes transcription events, forwards audio chunks, and updates draft text from partial/final transcript events.
  - `LiveVoiceCaptureController` rejects simulator recording before AVAudioEngine startup, asks microphone permission on device, configures `AVAudioSession`, installs an input tap, emits PCM16 mono 24k chunks, and stops on selected interruptions/route changes.
  - `RelayRealtimeTranscriptionClient` connects to the relay, sends `audio/transcription/*` JSON-RPC methods, validates session IDs and monotonic sequences, and translates relay notifications into `RealtimeTranscriptionEvent`.
- Relay:
  - Phone WebSocket requests enter `startServer()` in `scripts/dock-relay.mjs`.
  - `handleRequest()` dispatches JSON-RPC methods to history app-server, live loopback endpoints, active upstream session, archive/unarchive helpers, or `RealtimeTranscriptionManager`.
  - Realtime transcription uses relay-side OpenAI credentials only and rejects phone-supplied provider config.

## 4.3 Object model + key abstractions

- Swift state uses `@MainActor` `ObservableObject` stores plus actors/protocols for async clients and fakes.
- `AppServerConnectionState` is the central Swift app-server connection lifecycle enum.
- `DockLoadFailure`, `AppServerClientError`, `ThreadDetailStoreError`, `VoiceCaptureError`, `RelayRealtimeTranscriptionClientError`, and `TranscriptionServiceError` are already typed enough to drive log severity.
- `AppConnectivityReporting` is a UI status aggregation protocol, not a diagnostic log. It should remain the UI-facing connectivity source while logs observe the same transitions.
- Node relay has functional helpers and small classes. It currently has no logger abstraction and uses direct string messages.

## 4.4 Observability + failure behavior today

- Swift has no central `Logger`, `OSLog`, `OSSignposter`, `MetricKit`, `print`, `debugPrint`, or `NSLog` usage in app source.
- Swift user-visible failures are preserved in published state and localized errors, but most caught failures are not logged.
- Relay has direct `console.error` calls for aggregate summaries and failures. Output is human-readable but inconsistent and not centrally redacted.
- LaunchAgent service logs already exist:
  - `.codex-dock/app-server.log`
  - `.codex-dock/app-server.err.log`
  - `.codex-dock/dock-relay.log`
  - `.codex-dock/dock-relay.err.log`
- Crash diagnostics are not app-owned today. Physical device crash proof depends on external Xcode/device tooling.

## 4.5 UI surfaces (ASCII mockups, if UI work)

No new UI is planned. Existing user-visible state remains:

```text
GlobalConnectivityIndicatorView
Dock tab / Archive tab / Hosts tab
SessionDetailView live-state chip
Composer voice controls and request cards
```

Logs diagnose those surfaces; they do not replace or add UI.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- New Swift diagnostics owner:
  - `CodexDock/Diagnostics/Logging.swift`
    - Defines `DockLog.subsystem = "com.aelaguiz.CodexDock"`.
    - Defines static `Logger` values by category: `app`, `appLifecycle`, `bootstrap`, `relayDiscovery`, `hostConfiguration`, `appServer`, `dock`, `archive`, `threadDetail`, `connectivity`, `voice`, `transcription`, `persistence`, `metrics`.
    - Defines `DockSignpost` or equivalent `OSSignposter` helpers for high-value intervals.
    - Defines tiny formatting helpers for non-secret IDs, counts, durations, and error summaries only when they reduce repetition.
  - `CodexDock/Diagnostics/MetricKitDiagnosticsReporter.swift`
    - Subscribes to `MXMetricManager` when `MetricKit` is available.
    - Logs crash/hang/CPU/disk/app-launch diagnostic summaries with `DockLog.metrics`.
    - Optionally writes the latest MetricKit JSON payload under Application Support for local support capture.
  - Tests under `CodexDockTests/DiagnosticsLoggingTests.swift` only if there are helper functions or persistence behavior worth testing.
- Node relay diagnostics owner:
  - `scripts/dock-relay-logger.mjs`
    - Exports a small logger with `debug`, `info`, `warn`, `error`, and `fault` methods.
    - Writes newline-delimited JSON or stable key-value records to stderr.
    - Redacts tokens, API keys, authorization headers, base64 audio, transcript/prompt text, and full JSON-RPC payloads.
    - Provides a synchronous fatal logging path for `uncaughtExceptionMonitor`.
  - Existing relay tests receive logger formatting/redaction coverage where low-cost.
- Commands/docs:
  - `Makefile` may add log capture targets if they reduce repeated command errors:
    - `sim-logs`
    - `device-logs`
    - `dock-relay-logs`
  - `AGENTS.md` gets a compact `Logging And Diagnostics` section with exact patterns and commands.
  - `README.md` gets human runbook additions only if Makefile targets are added and the README would otherwise be stale.

## 5.2 Control paths (future)

- Swift app startup:
  - `CodexDockApp` initializes the diagnostics coordinator once at app start.
  - Scene/lifecycle changes emit concise app lifecycle logs and keep existing `AppLifecycleCoordinator` behavior unchanged.
- Swift operation logging:
  - Each major async operation logs `start` and `finish` or `failure` with host ID/name, operation name, method name where applicable, row/count values where useful, and sanitized error class/message.
  - Long operations use signpost intervals:
    - `app-server.connectAndInitialize`
    - `thread/list`
    - `thread/readCompact`
    - `thread/resume`
    - `dock.reload`
    - `archive.reload`
    - `voice.capture`
    - `transcription.commit`
  - High-volume notifications, deltas, audio chunks, and JSON-RPC messages are summarized, not dumped.
- Relay operation logging:
  - Relay startup logs version, listen host/port, history endpoint host/port, phone auth mode, and Bonjour enabled state. It never logs tokens or API keys.
  - WebSocket connection logs include connection lifecycle and close code/reason.
  - JSON-RPC dispatch logs method/result/failure/duration with request ID only when useful.
  - Aggregation logs include counts and endpoint counts.
  - Upstream resume/recovery logs include thread ID, endpoint host/port, attempt, and result.
  - Transcription logs include session ID, sequence counts, byte counts, reason codes, and model/delay/language; never audio/transcript content.
- Crash diagnostics:
  - MetricKit emits summaries after diagnostic delivery.
  - MetricKit delivery is not an instant replacement for a live crash debugger. Treat it as next-available platform diagnostics; simulator/device OS logs and Xcode/device crash reports still matter during active reproduction.
  - Intentional invariant crashes use a nearby `fault` log before `preconditionFailure` / `fatalError` if such paths are introduced later.
  - Node fatal monitor writes one final structured line and allows process termination.

## 5.3 Object model + abstractions (future)

- Swift:
  - `DockLog` is a namespace, not a service dependency.
  - Call sites use direct `Logger` methods so Swift keeps compile-time OSLog interpolation/privacy behavior.
  - Small helpers may normalize error type names, host endpoints, and durations, but no generic "log anything" wrapper is introduced.
  - `MetricKitDiagnosticsReporter` is the only class-like diagnostics object; it owns subscription lifetime and local diagnostic artifact writing.
  - Tests should not require a fake logger unless a helper has meaningful logic. Behavior tests should continue using existing fake transports/loaders.
- Node:
  - `RelayLogger` is a small module, not a framework.
  - The logger accepts an injected writable stream and clock for tests.
  - Normal logs are async/stream-friendly; fatal monitor writes synchronously to stderr.
  - Existing relay functions receive either module-level logger import or a config-injected logger where tests need output capture.

## 5.4 Invariants and boundaries

- Privacy:
  - `OPENAI_API_KEY`, bearer tokens, authorization headers, `.env` values, raw prompts, transcripts, audio bytes, base64 audio, and full JSON payloads are never logged.
  - Public log values are limited to non-secret operation names, method names, counts, category names, host display names/IDs, sanitized endpoints, local thread IDs, result classes, and reason codes.
  - Values that might contain user content stay private/redacted or are omitted.
- Physical-device proof:
  - The plan's device evidence is an installed app connected through the relay-backed host path, plus `log collect --device-udid` output filtered by `com.aelaguiz.CodexDock`.
  - Loopback simulator logs and fake transports can prove code behavior, but they do not prove physical-phone logging works.
- Ownership:
  - Swift categories live in one file.
  - Relay formatting/redaction lives in one file.
  - Capture commands live in `Makefile` and/or `AGENTS.md`.
- Compatibility:
  - Preserve all existing app/server/client contracts.
  - Cleanly cut relay log call sites from `console.error` to `relayLogger`.
  - Do not add runtime fallbacks or behavior-changing recovery.
- Performance:
  - Do not log per audio chunk at persisted levels.
  - Do not log every JSON-RPC frame.
  - Use `debug` or summarized counters for high-volume events.
- Failure behavior:
  - Logging failures must not crash normal app flows. If local MetricKit JSON persistence fails, log that failure once and continue.
  - Fatal diagnostics must not attempt to recover a corrupted process.

## 5.5 UI surfaces (ASCII mockups, if UI work)

No UI surface changes. The user-facing debugging interface is the native log tools and relay log files:

```text
Simulator: xcrun simctl spawn booted log stream ...
Device:    log collect --device-udid ...
Relay:     tail .codex-dock/dock-relay.err.log
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Swift diagnostics | `CodexDock/Diagnostics/Logging.swift` | new `DockLog` / signpost helpers | missing | Add static logger categories, subsystem, signposter helpers, small safe formatting helpers | Canonical Swift logging owner | `DockLog.<category>` and signposter factory | New diagnostics helper tests if helpers contain logic |
| Swift diagnostics | `CodexDock/Diagnostics/MetricKitDiagnosticsReporter.swift` | new MetricKit subscriber | missing | Subscribe to MetricKit, log diagnostic summaries, persist latest JSON if feasible | Captures crash/hang diagnostics without third-party SDK | `MetricKitDiagnosticsReporter.start()` or app-owned singleton | New tests for JSON persistence only if injectable |
| App entry | `CodexDockApp/CodexDockApp.swift` | `CodexDockApp.body` | starts UI only | Initialize diagnostics coordinator once and log app launch | MetricKit needs app bootstrap hook | No UI change | Xcode build |
| Project generation | `project.yml` | `CodexDock` / `CodexDockApp` targets | source folders are already included | Usually no target setting change; update only if MetricKit/app capability wiring requires it, then regenerate | Project file is generated | XcodeGen source of truth | XcodeGen + Xcode build if changed |
| App lifecycle | `CodexDock/State/AppLifecycleCoordinator.swift` | `handle(_:)`, `setPhase` | publishes snapshots | Log phase changes and resume generation | Background/resume bugs need a trace | `DockLog.appLifecycle` | `AppLifecycleCoordinatorTests` |
| Bootstrap | `CodexDock/Configuration/RelayBootstrapStore.swift` | `start`, `handleLifecycle`, discovery/manual/saved URL paths | state-only | Log env config success/failure, discovery start/stop, saved/manual relay selection, persistence failures | Explains why app did or did not find relay | `DockLog.bootstrap` | `DockConfigurationTests`, bootstrap-related tests |
| Discovery | `CodexDock/Configuration/RelayDiscovery.swift` | `start`, `stop`, `add`, `remove`, `resolved` | silent | Log browser start/stop, resolve success/failure, relay count | Physical phone path depends on Bonjour | `DockLog.relayDiscovery` | `DockConfigurationTests` |
| Host config | `CodexDock/Configuration/DockHostConfiguration.swift` and `HostRegistry.swift` | environment parsing and URL validation | throws errors | Log sanitized host IDs/endpoints on success/failure where callers catch | Host setup failures need context | `DockLog.hostConfiguration` | `DockConfigurationTests` |
| App-server client | `CodexDock/AppServer/AppServerClient.swift` | `connectAndInitialize`, `openTransport`, `sendRequest`, `startReceiveLoop`, reconnect functions, `failConnection`, `markOffline`, `disconnect` | state-only | Add operation logs and signposts for connect/init/request/reconnect/loss; summarize methods and request IDs | Highest-risk network seam | `DockLog.appServer`, signposts | `AppServerClientTests` |
| JSON-RPC | `CodexDock/AppServer/JSONRPC.swift` | decode/encode errors | throws | No broad logging inside pure codec; call-site logs decode failures | Keep pure model simple | none | `AppServerClientTests` |
| Dock load | `CodexDock/State/DockStore.swift` | `reload`, `loadAllHosts`, scope load, `archive`, metadata `save` | state/action errors only | Log reload start/end, host/scope outcomes, mapping failure count, conflicts, archive actions, metadata failures | Dock rows are primary user workflow | `DockLog.dock`, signpost | `DockStoreTests` |
| Archive load | `CodexDock/State/ArchiveStore.swift` | `reload`, `loadAllHosts`, `restore` | state/action errors only | Log archive refresh outcomes and restore action results | Archive is a sibling path | `DockLog.archive`, signpost | Archive/Dock tests |
| Local metadata | `CodexDock/State/LocalThreadMetadataStore.swift` | `load`, `save`, `persist` | throws | Log read/write failures and entry counts at store boundary or caller | Persistence failures are currently swallowed in stores | `DockLog.persistence` | `DockStoreTests` |
| Host settings | `CodexDock/State/HostSettingsStore.swift` | `test`, `saveHost` | state/action errors only | Log host test start/result/failure and host save sanitized target | Helps debug host setup | `DockLog.hostConfiguration` | `DockConfigurationTests` |
| Connectivity | `CodexDock/State/AppConnectivityStore.swift` | report methods and `publish` | UI state only | Log overall status transitions and per-host phase changes, deduped if needed | Root indicator is core troubleshooting signal | `DockLog.connectivity` | `AppConnectivityStoreTests` |
| Thread detail | `CodexDock/State/ThreadDetailStore.swift` | `load`, read/resume, observation tasks, reconnect/rehydrate, notifications, requests, sends, close | state/action errors only | Log detail lifecycle, compact read/resume duration, live/stale/reconnect changes, stream endings, send success/failure, request-card responses | Most bug-prone live path | `DockLog.threadDetail`, signposts | `ThreadDetailStoreTests`, lifecycle tests |
| Voice orchestration | `CodexDock/State/ThreadDetailStore.swift` | voice capture methods | state/action errors only | Log voice capture start/stream/finalize/cancel/fail reason codes; omit transcript text | Voice path spans app, audio, relay | `DockLog.voice`, `DockLog.transcription` | `ThreadDetailStoreTests`, voice presentation tests |
| Audio capture | `CodexDock/Voice/VoiceCaptureController.swift` | permission, AVAudioSession, route/interruption, engine start/stop, chunk emitter | mostly silent | Log permission result, simulator recording unavailable path, route/interruption stop reasons, engine start/stop/failure; summarize chunk counts at end only | Device-only mic issues are hard to debug | `DockLog.voice` | `VoiceCaptureControllerTests` |
| Transcription client | `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` | start/append/commit/cancel/notifications/timeouts | state/events only | Log session lifecycle, sequence counts, byte counts, error reason codes, timeout; omit audio/transcript | Relay/OpenAI bridge needs cross-system trace | `DockLog.transcription`, signposts | `AppServerClientTests`, Thread detail voice tests |
| Relay logger | `scripts/dock-relay-logger.mjs` | new module | missing | Add structured redacting stderr logger and fatal sync writer | Canonical relay log owner | `createRelayLogger()` | New/updated relay tests |
| Relay main | `scripts/dock-relay.mjs` | direct `console.error` sites, startup/shutdown, WebSocket connection, request dispatch, aggregation, recovery | scattered text logs | Replace direct logs with logger records; add connection/request duration/result logs | Relay is Mac-side source of truth for phone path | `relayLogger.<level>(event, fields)` | `rtk npm run test:relay` |
| Relay client | `scripts/dock-relay-json-rpc-client.mjs` | connect/request/close/errors | silent except thrown errors | Add optional logger or event callbacks for connect/request timeout/close summaries | Upstream failures need source context | injected logger optional | Relay tests |
| Relay transcription | `scripts/dock-relay-realtime-transcription.mjs` | transcription manager | silent except thrown errors | Log start/append/commit/cancel/fail/close with session IDs/counts/reason codes; no text/audio | High-risk provider bridge | relay logger injected through config/options | Realtime transcription relay tests |
| Relay Bonjour | `scripts/dock-relay-bonjour.mjs` | child process error direct `console.error` | one direct error log | Use relay logger for advertisement failure/start/disabled | Keep one logger path | relay logger | Relay tests if exposed |
| Makefile | `Makefile` | help/services/app/device targets | no log capture targets | Add optional `sim-logs`, `device-logs`, `dock-relay-logs` targets if accepted during implementation | Reduces command mistakes | command targets | No app tests; readback/help check |
| Agent instructions | `AGENTS.md` | repo-wide instructions | no logging section | Add concise logging pattern and capture commands using agents-md-authoring doctrine | Prevents future ad hoc logs | always-on instructions | Readback + `rtk git status --short` if docs-only |
| README | `README.md` | runbook | no logging runbook | Update only if Makefile log targets or capture procedure need human docs | Avoid stale runbook | doc text | Readback if changed |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  - Swift: `CodexDock/Diagnostics/Logging.swift`.
  - Swift crash diagnostics: `CodexDock/Diagnostics/MetricKitDiagnosticsReporter.swift`.
  - Relay: `scripts/dock-relay-logger.mjs`.
  - Commands: `Makefile`.
  - Agent instructions: `AGENTS.md`.
- Deprecated APIs (if any):
  - No public Swift API deprecation is required.
  - Direct relay `console.error` call sites become deprecated by convention after `scripts/dock-relay-logger.mjs` lands.
- Delete list (what must be removed; include superseded shims/parallel paths if any):
  - Remove or migrate direct `console.error` calls in `scripts/dock-relay*.mjs` except inside the logger implementation.
  - Do not add any Swift `print`, `debugPrint`, `dump`, or `NSLog` debugging call sites.
- Adjacent surfaces tied to the same contract family:
  - Swift tests need behavior-preservation coverage but not exact log output.
  - Relay tests should cover logger redaction/format where the logger has logic.
  - `AGENTS.md` must teach both Swift and relay logging patterns.
  - `Makefile` help must mention any new log targets.
- Compatibility posture / cutover plan:
  - Preserve app/server runtime contracts.
  - Clean cutover from direct relay logging to relay logger.
  - No runtime bridge.
- Capability-replacing harnesses to delete or justify:
  - None. Do not add an OSLog parser/test harness just to prove log text.
- Live docs/comments/instructions to update or delete:
  - Add `AGENTS.md` logging instructions.
  - Update `README.md` only if new commands need human runbook coverage.
  - Add code comments only at the diagnostics privacy boundary or the relay logger redaction boundary.
- Behavior-preservation signals for refactors:
  - Swift targeted tests plus `rtk swift test`.
  - Relay tests via `rtk npm run test:relay`.
  - Xcode build when app bootstrap/project wiring changes.
  - Simulator log streaming and physical device log collection after implementation to prove logs are emitted where they need to be captured.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Swift app logs | all Swift source files under `CodexDock/**` and `CodexDockApp/**` | `DockLog` static categories and direct `Logger` methods | Prevents `print`/wrapper drift | include |
| Swift operation timing | `AppServerClient`, `DockStore`, `ArchiveStore`, `ThreadDetailStore`, transcription client | `OSSignposter` for operation intervals | Makes slow operations diagnosable without payload logs | include |
| Crash diagnostics | app bootstrap and diagnostics folder | MetricKit subscriber | Avoids third-party SDK while capturing platform diagnostics | include |
| Relay logs | `scripts/dock-relay*.mjs` | `scripts/dock-relay-logger.mjs` | Prevents scattered `console.error` and redaction drift | include |
| Service logs | `Makefile` and `.codex-dock/**` generated logs | Keep LaunchAgent stderr/stdout paths | Avoids new service-management concepts | include |
| Agent instructions | root `AGENTS.md` | concise logging section | Future agents follow the same pattern | include |
| In-app log UI | new Swift views | none | Would add product surface and storage/privacy work | exclude |
| Remote crash SDK | package dependencies | none | Adds third-party account/privacy/SDK lifecycle work | exclude |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 chooses the first working slice that proves one real path through the canonical owner path, highest-risk seam, physical-device-compatible log capture, and verification shape. Later phases expand along named axes from that proof. `Work` explains the unit only. `Checklist (must all be done)` and `Exit criteria (all required)` are authoritative.

## Phase 1 - Logging primitives plus one relay-backed dock refresh slice

- Goal:
  - Establish the canonical Swift and relay logging owners, then prove one real app-to-relay operation can be traced without secrets.
- Work:
  - Add the smallest `DockLog` category owner and relay logger needed to instrument `DockStore.reload()` -> `AppServerDockClient.loadSessions()` -> `AppServerClient.threadList()` -> relay `thread/list` aggregation.
  - This phase crosses the highest-risk seam early: Swift app logs, app-server client logs, and Mac relay logs must describe the same dock refresh.
- Checklist (must all be done):
  - Add `CodexDock/Diagnostics/Logging.swift` with `DockLog.subsystem`, initial static categories, and signposter support needed for the slice.
  - Instrument `AppServerClient.connectAndInitialize`, `openTransport`, `sendRequest`, `handleTransportLoss`, reconnect state changes, `markOffline`, `failConnection`, and `disconnect` enough to explain connect/init/thread-list success and failure.
  - Instrument `AppServerDockClient.loadSessions` and `DockStore.reload` for refresh start/end/failure, host ID/display name, scope, row count, mapping-failure count, and duration.
  - Add `scripts/dock-relay-logger.mjs` with structured stderr records, injected stream/clock for tests, redaction helpers, and levels.
  - Replace the `thread/list` aggregate summary/failure `console.error` paths in `scripts/dock-relay.mjs` with the new relay logger.
  - Add or update tests only for logger formatting/redaction helpers and behavior-preserving touched paths.
  - Keep raw tokens, OpenAI keys, prompts, transcripts, base64 audio, and full JSON-RPC payloads out of every new log call.
- Verification (required proof):
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk npm run test:relay`
  - Local smoke after implementation when feasible: `rtk make services` then `rtk make dock-relay-status`.
- Docs/comments (propagation; only if needed):
  - Add a short code comment only at the Swift privacy boundary or relay redaction helper if the safe/public value split is not obvious.
- Exit criteria (all required):
  - Swift code has one canonical logging owner and no new ad hoc Swift logging calls.
  - Relay code has one logger module and the migrated `thread/list` logs no longer use direct `console.error`.
  - A dock refresh emits safe operation-level Swift logs and safe relay logs with enough context to connect the two manually.
  - All listed phase checks pass or the exact missing-environment blocker is recorded.
- Rollback:
  - Remove the new diagnostics files and revert only the instrumentation calls from this phase. Runtime behavior should return to the current state because logging does not own business logic.

## Phase 2 - Expand Swift state coverage across bootstrap, connectivity, archive, host, lifecycle, and persistence

- Goal:
  - Widen from the proven dock refresh slice to the rest of the Swift app state paths that explain whether the app is configured, connected, backgrounded, stale, partially loaded, or failing.
- Work:
  - Add category-specific logs and signposts around relay bootstrap/discovery, lifecycle, connectivity rollup, archive loads, host tests/saves, and local persistence.
- Checklist (must all be done):
  - Instrument `RelayBootstrapStore` start/discovery/manual/saved-config paths, lifecycle background/resume behavior, and configuration persistence failures.
  - Instrument `BonjourRelayDiscovery` search start/stop, service add/remove, resolve success/failure, and relay count changes.
  - Instrument `DockHostConfiguration` / `HostRegistry` at caught caller boundaries for sanitized success/failure context.
  - Instrument `AppLifecycleCoordinator` phase and resume-generation changes.
  - Instrument `AppConnectivityStore` overall status transitions and per-host phase changes without flooding repeated identical states.
  - Instrument `ArchiveStore` load/restore outcomes and unavailable/empty/loaded distinctions.
  - Instrument `HostSettingsStore` host test and host save outcomes.
  - Instrument `FileLocalThreadMetadataStore` and local relay config persistence failures at the store or caller boundary.
  - Add signpost intervals around dock/archive/host-test work where duration matters.
- Verification (required proof):
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter AppConnectivityStoreTests`
  - `rtk swift test --filter DockConfigurationTests`
  - Any targeted archive/host/lifecycle test already covering changed code.
- Docs/comments (propagation; only if needed):
  - If a new dedupe helper is added for connectivity logs, comment why it exists at the helper boundary.
- Exit criteria (all required):
  - Bootstrap, discovery, host setup, lifecycle, connectivity, archive, and persistence failures have safe logs at their owner boundaries.
  - Existing UI state behavior remains unchanged by tests.
  - No new logging path stores or prints secrets/user content.
- Rollback:
  - Revert instrumentation call sites and any helper added only for this phase.

## Phase 3 - Expand live thread detail, request-card, composer, voice, and realtime transcription coverage

- Goal:
  - Make the live session and voice paths diagnosable end to end, including stale/reconnect transitions and phone-to-relay transcription failures.
- Work:
  - Instrument `ThreadDetailStore`, `VoiceCaptureController`, `RelayRealtimeTranscriptionClient`, and relay realtime transcription manager with summarized state, counts, IDs, reason codes, and timings.
- Checklist (must all be done):
  - Instrument `ThreadDetailStore.load`, compact `thread/read` + `thread/turns/list` + `thread/resume`, notification/request observation start/end, rehydrate-after-reconnect, stale/reconnect/live/closed transitions, send draft, and request-card response results.
  - Instrument voice orchestration in `ThreadDetailStore` for begin/finish/cancel/failure and active segment lifecycle without transcript text.
  - Instrument `VoiceCaptureController` for microphone permission result, simulator recording-unavailable path, AVAudioSession/engine start/failure/stop, route-change stops, interruption stops, and final chunk count/duration.
  - Instrument `RelayRealtimeTranscriptionClient` for start/append/commit/cancel, completion timeout, session mismatch, invalid event, event stream ended, and final result using IDs/counts/reason codes only.
  - Instrument `scripts/dock-relay-realtime-transcription.mjs` for start/append/commit/cancel, upstream open/failure/close, invalid upstream event, duration exceeded, missing API key, and close reason using IDs/counts/reason codes only.
  - Keep transcript text, partial text, delta text, audio bytes, and base64 audio out of logs.
- Verification (required proof):
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test --filter VoiceCaptureControllerTests`
  - `rtk swift test --filter AppServerClientTests`
  - `rtk npm run test:relay`
- Docs/comments (propagation; only if needed):
  - Add a short comment at any audio/transcript redaction helper if a helper is introduced.
- Exit criteria (all required):
  - Detail load/reconnect/stale behavior remains test-preserved.
  - Voice and realtime transcription failures produce safe reason-code logs on both Swift and relay sides.
  - No content-bearing audio/transcript/prompt values enter logs.
- Rollback:
  - Revert voice/detail/transcription instrumentation while leaving earlier logging primitives intact if Phase 1-2 are already stable.

## Phase 4 - Add crash, hang, and fatal-process diagnostics

- Goal:
  - Capture platform crash/hang diagnostics and relay fatal failures without unsafe recovery behavior.
- Work:
  - Add MetricKit subscription in the app process and fatal-process monitoring in the relay.
- Checklist (must all be done):
  - Add `CodexDock/Diagnostics/MetricKitDiagnosticsReporter.swift` guarded by `canImport(MetricKit)` where needed.
  - Initialize the diagnostics reporter once from `CodexDockApp/CodexDockApp.swift`.
  - Log MetricKit diagnostic summaries for crash, hang, CPU exception, app launch, and disk write payloads where available.
  - Persist the latest MetricKit JSON payload under Application Support only if implementation can do so without secret/user-content risk and without making persistence failure fatal.
  - Add relay `uncaughtExceptionMonitor` fatal logging that writes synchronously and does not install unsafe recovery.
  - Add relay warning/fatal report logging only where it does not change Node default crash behavior.
- Verification (required proof):
  - `rtk swift test`
  - `rtk xcodegen generate --spec project.yml`
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - `rtk npm run test:relay`
- Docs/comments (propagation; only if needed):
  - Comment that MetricKit delivery is OS-timed and not an instant crash hook.
  - Comment the relay fatal monitor to state that it observes and exits, not recovers.
- Exit criteria (all required):
  - App bootstrap registers diagnostics without altering UI launch.
  - Relay fatal monitor logs fatal context without preventing process termination.
  - Crash/hang diagnostics are handled as platform diagnostics, not as app-controlled exception catching.
- Rollback:
  - Remove MetricKit reporter bootstrap and relay fatal monitor. Earlier operation logs remain valid.

## Phase 5 - Add capture commands, agent instructions, and final simulator/device proof

- Goal:
  - Make the logging pattern easy for future agents and for Amir, then prove it on simulator and physical-device-compatible paths.
- Work:
  - Add exact capture commands, concise `AGENTS.md` instructions, and final verification.
- Checklist (must all be done):
  - Evaluate during implementation whether `Makefile` log aliases are worth adding; exact raw capture commands in `AGENTS.md` are required either way. If aliases are added, add `sim-logs`, `device-logs DEVICE=<device-udid>`, and `dock-relay-logs` with help text.
  - Add a compact `Logging And Diagnostics` section to root `AGENTS.md` using `agents-md-authoring` doctrine:
    - Swift logs use `DockLog` / `OS.Logger`.
    - Relay logs use `scripts/dock-relay-logger.mjs`.
    - Never log keys, tokens, prompts, transcripts, audio/base64 audio, or full JSON-RPC payloads.
    - Use exact simulator, device, and relay capture commands.
    - State the smallest relevant tests for logging changes.
  - Update `README.md` only if new Makefile targets or capture commands need human runbook coverage beyond `AGENTS.md`.
  - Run final Swift, relay, generated-project, simulator, and physical-device evidence steps as environment allows.
  - Record exact blockers if physical device, signing, simulator, Xcode, services, or env vars are unavailable.
- Verification (required proof):
  - `rtk swift test`
  - `rtk npm run test:relay`
  - `rtk xcodegen generate --spec project.yml`
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - `rtk make app SIM='iPhone 17'`
  - `rtk xcrun simctl spawn booted log stream --style compact --predicate 'subsystem BEGINSWITH "com.aelaguiz.CodexDock"' --timeout 60`
  - `rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>` when a device and signing are available.
  - `rtk xcrun log collect --device-udid <device-udid> --last 10m --predicate 'subsystem == "com.aelaguiz.CodexDock"' --output /tmp/codex-client/codex-dock-device.logarchive` when a device is available.
  - `rtk tail -n 80 .codex-dock/dock-relay.err.log`
- Docs/comments (propagation; only if needed):
  - `AGENTS.md` is required.
  - `README.md` is conditional on Makefile command changes.
- Exit criteria (all required):
  - Future agents can read `AGENTS.md` and know exactly how to add logs and capture them.
  - Simulator logs show app launch, dock refresh, and app-server operation categories.
  - Relay logs show structured records for the same run.
  - Physical-device proof is captured or the exact blocker is recorded.
  - No implementation phase leaves direct relay `console.error` drift or Swift ad hoc logging drift in touched areas.
- Rollback:
  - Remove Makefile log targets and documentation additions if the command shape is wrong. Do not roll back logging primitives unless final verification exposes a behavior regression.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

- Start with the smallest test family for the touched surface:
  - `rtk swift test --filter AppServerClientTests` for app-server client/logging primitives.
  - `rtk swift test --filter DockStoreTests` for dock/archive/host instrumentation.
  - `rtk swift test --filter ThreadDetailStoreTests` for detail/reconnect/composer/voice instrumentation.
  - `rtk npm run test:relay` for relay logger changes.
- Run `rtk swift test` after broad Swift instrumentation is in place.
- Run `rtk xcodegen generate --spec project.yml` and the Xcode build if app target/project settings or MetricKit app bootstrap changes require generated project validation.
- Use native log collection commands for simulator/device proof; do not invent a custom log export harness for this pass.
- Avoid brittle tests that assert exact OSLog output, absence of strings by grep, or deletion-only proof.

# 9) Rollout / Ops / Telemetry

- Roll out behind no feature flag. Logging is behavior-observing and should be safe by default.
- Default logging should be quiet enough for normal local use:
  - `notice` / `info` for operation boundaries and state changes.
  - `warning` for degraded-but-recovered paths.
  - `error` for user-visible failures.
  - `fault` for invariant violations, MetricKit crash diagnostics, and pre-crash assertions.
  - `debug` for high-volume details needed only during active debugging.
- Capture commands should live in `AGENTS.md` and, if Makefile targets are added, in `Makefile` help text.
- Node relay structured logs continue to be captured by existing LaunchAgent log files.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: self-integrator; Explorer 1 / Explorer 2 split performed inline because current multi-agent tool policy only permits subagents when the user explicitly asks for delegation or parallel agent work.
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, research grounding, current architecture, target architecture, call-site audit, phase plan, verification, rollout, decision log, and helper receipts.
- Findings summary:
  - The plan consistently selects first-party Swift observability (`OS.Logger`, `OSSignposter`, MetricKit), one Node relay stderr logger, and docs-first capture commands.
  - Simulator, physical-device, and relay proof expectations agree with the repo's service-path rules.
  - Secret and content redaction obligations are repeated across the North Star, target architecture, phase plan, rollout, and decision log.
- Integrated repairs:
  - Repaired the Swift logger naming rule so all sections point to `DockLog.<category>` instead of a competing `Logger.codex.<category>` shape.
  - Clarified that `Makefile` log aliases are optional convenience aliases, while exact raw capture commands in `AGENTS.md` are required either way.
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

<!-- arch_skill:block:implementation_audit:start -->
## Implementation Audit

- Reviewed: 2026-05-28T18:27:36Z.
- Verdict: implemented and approved with exact physical log-collection blocker recorded.
- Implementation record: `docs/CODEX_DOCK_OBSERVABILITY_LOGGING_FRAMEWORK_2026-05-28_WORKLOG.md`.
- Thermonuclear review: `docs/CODEX_DOCK_OBSERVABILITY_LOGGING_FRAMEWORK_2026-05-28_THERMONUCLEAR_REVIEW.md`.
- Plan audit: `docs/CODEX_DOCK_OBSERVABILITY_LOGGING_FRAMEWORK_2026-05-28_PLAN_AUDIT.md`.
- Native subagents: not used; current multi-agent tool policy only permits subagents when the user explicitly asks for delegation or parallel agent work.

Implemented phases:

- Phase 1: added `CodexDock/Diagnostics/Logging.swift`, centralized Swift `DockLog`/`DockSignpost`, added `scripts/dock-relay-logger.mjs`, and instrumented the dock refresh/app-server/relay `thread/list` path.
- Phase 2: expanded Swift logs through bootstrap, Bonjour discovery, host configuration, lifecycle, connectivity, archive, host settings, and local persistence owner boundaries.
- Phase 3: expanded thread detail, request-card, composer voice orchestration, `VoiceCaptureController`, Swift realtime transcription client, and relay Realtime transcription logs while keeping audio/transcript content out of logs.
- Phase 4: added `MetricKitDiagnosticsReporter`, app bootstrap registration, and relay fatal-process logging.
- Phase 5: added `sim-logs`, `device-logs`, and `dock-relay-logs` Makefile targets, updated `README.md`, updated root `AGENTS.md`, and captured simulator, relay, and physical install/launch proof.

Verification accepted:

- `rtk npm run test:relay` passed, 39 tests.
- `rtk swift test --filter DiagnosticsLoggingTests` passed, 3 tests.
- `rtk swift test --filter AppServerClientTests` passed, 43 tests, 5 skipped.
- `rtk swift test --filter DockStoreTests` passed, 19 tests.
- `rtk swift test --filter ThreadDetailStoreTests` passed, 50 matching tests.
- `rtk swift test --filter VoiceCaptureControllerTests` passed, 5 tests.
- `rtk swift test --filter AppConnectivityStoreTests` passed, 11 tests.
- `rtk swift test --filter DockConfigurationTests` passed, 14 tests.
- `rtk swift test` passed, 182 tests, 5 skipped.
- `rtk xcodegen generate --spec project.yml` passed.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` passed.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B'` passed.
- `rtk make services`, `rtk make app-server-status`, and `rtk make dock-relay-status` passed with relay endpoint `ws://192.168.50.117:4510`.
- `rtk make app SIM='feat_anim_1 - iPhone 17'` passed and launched `com.aelaguiz.CodexDockApp` against `ws://192.168.50.117:4510`.
- Simulator log proof showed `MetricKit diagnostics reporter started`, `Codex Dock app launch`, `host configuration loaded ... endpoint=ws://192.168.50.117:4510`, `app-server connect initialize finished`, `connectivity overall status=Online message=206 sessions`, and `dock reload finished hosts=1 rows=206 mapping_failures=0 scope_failures=0 conflicts=0`.
- Physical install and launch passed on iPhone 14 device `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`; process listing showed `CodexDockApp` pid `4561`.
- Relay log proof showed structured JSON records for `thread_list.loaded`, `downstream.request_succeeded`, and `downstream.closed` with no secrets in the sampled output.

Recorded blockers and fallbacks:

- Name-based simulator destination `platform=iOS Simulator,name=iPhone 17` failed because no simulator has exact name `iPhone 17`; fallback simulator `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`, passed build/test/launch/log proof.
- Physical log collection command `rtk make device-logs DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC DEVICE_LOG_OUTPUT=/tmp/codex-client/observability-physical-0A4EFF8B-54D8-58FB-B3FB-63263265B9CC.logarchive` failed with `log: Must be root to collect logs from attached device`; physical install/launch/process proof and relay-side physical connection logs were captured, but the device logarchive itself requires root.

Implementation-audit finding summary:

- Blocking findings: none open.
- Resolved during review: invalid physical device log command was replaced with `rtk xcrun log collect --device-udid ...`; Swift/iOS build issues around logging autoclosures were fixed; offline connection failure state was preserved; direct relay `console.error` paths were removed.
- Deferred follow-up: physical device logarchive collection requires root on this machine.
<!-- arch_skill:block:implementation_audit:end -->

# 10) Decision Log (append-only)

- 2026-05-28 - Intent-derived - The user objective explicitly requests a planning-only logging framework plan, not implementation in this turn. The plan may create docs/audit artifacts, but code, project, service, and AGENTS edits wait for a later implementation turn.
- 2026-05-28 - Intent-derived - Use first-party Apple observability (`Logger`, `OSSignposter`, MetricKit) and one local Node stderr logger first. Third-party crash/analytics SDKs are out of scope unless Amir later asks for remote crash collection.
- 2026-05-28 - Intent-derived - Fallback policy is forbidden. Logging must not add runtime shims, recovery paths, or behavior-changing fallback logic.
- 2026-05-28 - Intent-derived - Physical-device completion requires installed-device log collection from the relay-backed host path. Simulator or fake transport logs alone are useful development proof but not phone-path proof.
- 2026-05-28 - Implementation - Physical install/launch proof passed, but physical logarchive collection requires root on this machine; the exact blocker is `log: Must be root to collect logs from attached device`.
