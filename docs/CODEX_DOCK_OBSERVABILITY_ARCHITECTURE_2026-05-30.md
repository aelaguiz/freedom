---
title: "Codex Dock - Observability Architecture - Architecture Plan"
date: 2026-05-30
status: active
fallback_policy: forbidden
owners: [Amir]
reviewers: []
doc_type: architectural_change
related:
  - README.md
  - Makefile
  - docs/CODEX_DOCK_OBSERVABILITY_ARCHITECTURE_2026-05-30_WORKLOG.md
  - scripts/dock-relay.mjs
  - scripts/dock-relay-status.mjs
  - scripts/dock-relay-logger.mjs
  - scripts/dock-relay-session-table.mjs
  - scripts/codex-dock-host-service.mjs
  - CodexDock/Diagnostics/Logging.swift
  - CodexDock/AppServer/AppServerClient.swift
  - CodexDock/State/AppServerDockStreamClient.swift
  - CodexDock/State/DockStore.swift
  - CodexDock/State/AppConnectivityStore.swift
---

# TL;DR

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-30
Verdict (code): COMPLETE
Manual QA: pending (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Evidence checked
- Relay contract and route-health owner landed in
  `scripts/dock-relay-observability-contract.mjs` and
  `scripts/dock-relay-observability.mjs`.
- Relay dispatch, status, metrics, debug, traces, self-test, bundle, host doctor,
  and Dock aggregation now read from the route-health spine in
  `scripts/dock-relay.mjs`, `scripts/dock-relay-status.mjs`,
  `scripts/dock-relay-session-table.mjs`, and
  `scripts/codex-dock-host-service.mjs`.
- Relay self-test route probes are bounded by `SELFTEST_ROUTE_TIMEOUT_MS`, so a
  stuck Dock aggregation path cannot hang `/selftestz`.
- Relay bundle/status route arrays stay complete; the generic log sanitizer no
  longer caps the diagnostic route list.
- Swift route vocabulary, operation store, relay diagnostics client, app request
  tracing, Dock stream tracing, thread detail tracing, archive tracing,
  realtime transcription tracing, and connectivity route diagnostics landed in
  `CodexDock/Diagnostics/**`, `CodexDock/AppServer/AppServerClient.swift`,
  `CodexDock/State/**`, `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`,
  and `CodexDock/Features/Status/**`.
- App-owned diagnostics persist under
  `Library/Application Support/CodexDock/Diagnostics/`; relay diagnostics persist
  under `.codex-dock/observability/`.
- Operator bundle and multi-host comparison commands landed in `Makefile` and
  `scripts/dock-relay-diagnostics.mjs`.
- README now teaches `/readyz` as process-only and `/statusz`/`/routesz`/bundles
  as app-path truth. The 2026-05-28 logging plan is marked superseded for
  route-health diagnostics.
- Verification run:
  - `rtk npm run test:relay` passed, 112 tests.
  - `rtk swift test --filter AppServerClientTests` passed, 55 tests, 5 skipped.
  - `rtk swift test --filter DockStoreTests` passed, 48 tests.
  - `rtk swift test --filter ThreadDetailStoreTests` passed, 52 tests.
  - `rtk swift test --filter AppConnectivityStoreTests` passed, 15 tests.
  - `rtk swift test --filter DiagnosticsLoggingTests` passed, 7 tests.
- Fresh Cursor Agent Composer 2.5 Fast consult returned
  `VERDICT: pass-with-notes` with blocking findings: none. Run directory:
  `/tmp/fresh-consult/codex-dock-observability-20260530T142328Z-dx3gWc`.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- `rtk make sim-debug-bundle SIM='iPhone 14'` is blocked until the app is
  installed on that simulator. Exact failure:
  `missing simulator app data container for iPhone 14 (com.aelaguiz.CodexDockApp); install the app first with: rtk make app SIM='iPhone 14'`.
- `rtk make app-test SIM='iPhone 17'` built and ran generated-project tests but
  failed one unrelated existing swipe/pinned UI smoke:
  `CodexDockAutomationSmokeTests.testScriptedDockSwipePinPersistsAcrossLensesRefreshRelaunchAndUnpin()`
  at `CodexDockUITests/CodexDockAutomationSmokeTests.swift:188`, assertion
  `Inline pinned row did not unpin after swipe.`
- Physical iPhone debug-bundle proof was not run in this pass.
<!-- arch_skill:block:implementation_audit:end -->

Outcome: Codex Dock will have one observability spine for its single-user,
multi-host app path. A host can be process-reachable and still fail an
app-critical route, and that exact distinction must be visible from the client,
the relay, CLI probes, and debug bundles.

Problem: current diagnostics are split across Apple unified logs, relay stderr,
host-service status, process health endpoints, and route-specific logs. Those
surfaces can prove that a relay is alive without proving that the route the app
actually uses is working.

Approach: introduce one shared diagnostic contract, one relay observability
owner, one client observability owner, route-health records with evidence-backed
status reasons, operation traces across client-to-relay and relay-to-Codex
boundaries, and bounded app/relay debug bundles. Existing status, doctor, probe,
connectivity, and log surfaces must read from that spine instead of growing
parallel diagnostic systems.

Plan: first build the contract and relay route-health spine through the real
`dock/subscribe` and `thread/list` path, then add safe payload measurement and
route probes, then link the Swift client operation path and connectivity state,
then add app-owned debug bundles and multi-host comparison, then expand coverage
to thread detail, archive, and transcription.

Non-negotiables: single-user multi-host design, no extra diagnostics auth
system, no Codex internals instrumentation, no raw content or secret dumps, no
automatic mutating probes, no magic health score, no competing route-health
model, no new code path that bypasses the existing relay/client dispatch paths,
and no implementation before this plan is accepted.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-30
external_research_grounding: not needed - local repo architecture and operator workflow plan
deep_dive_pass_2: done 2026-05-30
recommended_flow: reformat -> auto-plan -> fresh consult -> implement only after explicit user request
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:b3534cc96b2e3fb41c27eb4f8692975b18bc88b59f9ad71584892b8297e4f70a",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-30T12:30:29Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:25c493954b701e718d0c2813dfcca2ac3be197b3182c0a3f077e87117511eed1",
      "completed_at": "2026-05-30T12:30:40Z",
      "doc_hash_after": "sha256:5c55063f2d47abad975403d9aef25be899937dd71684b9784ff5cd9756437b9e"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T12:30:46Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:5c55063f2d47abad975403d9aef25be899937dd71684b9784ff5cd9756437b9e",
      "completed_at": "2026-05-30T12:31:00Z",
      "doc_hash_after": "sha256:ea47a3d86eb34efc7a4ab02dafdea1f7dba738385ab36a19dc4f4091fc7356a6"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T12:31:05Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:ea47a3d86eb34efc7a4ab02dafdea1f7dba738385ab36a19dc4f4091fc7356a6",
      "completed_at": "2026-05-30T12:31:17Z",
      "doc_hash_after": "sha256:79dfaa27119728df31df3e12f11e40a2acbf9f935f5993469133a6f6cec90509"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-30T12:31:23Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:79dfaa27119728df31df3e12f11e40a2acbf9f935f5993469133a6f6cec90509",
      "completed_at": "2026-05-30T12:31:31Z",
      "doc_hash_after": "sha256:103ff400769f5c4ba60debb7d4d0e0d67549009433b5b5d4555cf9f663166fa0"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-30T12:31:37Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:103ff400769f5c4ba60debb7d4d0e0d67549009433b5b5d4555cf9f663166fa0",
      "completed_at": "2026-05-30T12:32:07Z",
      "doc_hash_after": "sha256:1e45641113390dede6c69197a9d4009109755aecc9ad3657b70f9ba90ba97e9a"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, a person debugging Codex Dock can identify, for each
configured relay host, whether failure is in the app, client transport, relay
downstream route, relay internal aggregation, relay upstream Codex boundary, raw
Codex app-server dependency, host service wrapper, local persistence, device
lifecycle, or network path.

The claim is false if `readyz` or `relay-doctor` can still report a host as
healthy while the app path fails without exposing the exact failing route,
operation ID, failure category, route status reason, last success, and app
impact.

## 0.2 In scope

- Single-user, multi-host observability for configured relay hosts such as
  `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`.
- Relay route-health ownership for app-critical JSON-RPC methods and relay HTTP
  diagnostics.
- Client operation tracing for the routes the app actually invokes.
- Shared diagnostic vocabulary and route config owned by one contract.
- Evidence-backed route status with `statusReasons`; no bare health verdicts.
- Dispatch-level instrumentation so new routes get traced by default.
- Auto-probe-safe versus passive-only route classification.
- Bounded relay and app-owned diagnostic stores.
- Debug bundles from relay, simulator, and physical iPhone app container.
- Multi-host compare command that reports route-level differences per host.
- Existing Makefile, README, Swift tests, and Node tests updated only as needed
  to point at the one diagnostic spine.

Requested behavior scope:

- The normal app can keep compact status such as `Online 1/2`.
- The expanded app state and debug bundle must show the evidence behind that
  compact status.
- Relay CLI diagnostics must make route failure obvious without ad hoc log
  archaeology.
- Physical iPhone debugging must not depend on Apple unified log collection.

Allowed architectural convergence scope:

- Refactor relay status tracking, relay logging, dock session aggregation
  diagnostics, host-service doctor output, Swift connectivity rollup, and app
  route clients so they report through one observability contract.
- Add narrow new files for the shared diagnostic contract and observability
  stores.
- Delete or retire duplicated diagnostic paths only after their surviving
  surface is reading from the new spine.

Compatibility posture:

- App-facing route method names remain stable: `dock/subscribe`, `dock/resync`,
  `thread/read`, `thread/turns/list`, archive, turn, and transcription methods
  do not get renamed.
- Client-to-relay trace metadata is additive and relay-owned. If absent, the
  relay generates operation IDs. This is a preservation path, not a long-lived
  compatibility shim.
- Relay-to-Codex upstream requests must be clean. Trace metadata is stripped
  before every upstream Codex call.
- Existing `/readyz` remains a simple process/liveness endpoint.
- Existing `/statusz` is enhanced into route-aware status instead of replaced by
  a second status endpoint with competing meaning.

## 0.3 Out of scope

- No Codex internals instrumentation.
- No multi-user or tenant authorization model for diagnostics.
- No separate diagnostics token, operator-token system, or product-hardening
  project.
- No raw app-server phone path.
- No automatic probes for mutating or billable operations.
- No broad tracing platform, remote SaaS telemetry sink, OpenTelemetry adoption,
  or external log database.
- No new app feature unrelated to debugging relay-client-Codex interoperation.
- No worktree cleanup, commits, pushes, or implementation in this planning pass.

## 0.4 Definition of done (acceptance evidence)

Planning is done when:

- This document is canonical ArcStep shape with generated auto-plan receipts.
- The phase plan is specific enough for implementation without another design
  choice.
- Section 3.3 says `none`.
- The consistency pass says `Decision-complete: yes`,
  `Unresolved decisions: none`, and `Decision: proceed to implement? yes`.
- `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_OBSERVABILITY_ARCHITECTURE_2026-05-30.md`
  exits 0.
- A fresh Cursor Agent `composer-2.5-fast` consult says the plan is highly
  specified, elegant, converged onto one implementation path, and ready to
  implement.

Implementation will be done only after a later explicit implementation request
and after these evidence categories pass:

- Relay tests prove route-health state, status reasons, trace metadata stripping,
  safe probe classification, payload measurement, and bundle output.
- Swift tests prove client operation tracing, route diagnostics state,
  connectivity detail, and app-owned bundle export.
- Multi-host simulator proof shows one healthy host and one route-failing host
  with exact per-host evidence.
- Physical-device proof uses app-owned files or UI-visible diagnostics, not
  Apple unified log collection.

## 0.5 Key invariants (fix immediately if violated)

- One diagnostic contract owns route names, event names, route status values,
  failure categories, route budgets, and probe safety.
- `readyz` liveness never implies app-path health.
- Every route status has concrete `statusReasons`.
- Every observation has a host identity where host context exists.
- Client operation IDs never leak into upstream Codex payloads.
- Automatic diagnostics do not mutate Codex state or spend tokens.
- Diagnostics summarize content shape, counts, sizes, durations, and error
  categories; they do not store prompts, transcripts, raw audio, headers,
  bearer tokens, API keys, or full payload dumps.
- Debug bundles are easy to obtain for this single user and each configured
  host.
- Existing diagnostics surfaces are refactored onto the observability spine
  instead of left as competing truths.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Route truth over process truth. A live process is useful evidence, but the
   app path is not healthy until the exact route succeeds or has a known
   last-good state.
2. One observability spine. Logs, status endpoints, app connectivity, probes,
   and bundles must report from the same typed observations and route-health
   model.
3. Single-user maintainability. The design should be simple to reason about and
   debug locally across multiple hosts; avoid product-grade security ceremony.
4. Evidence over heuristic verdicts. Compact UI labels are allowed only when
   expandable evidence explains them.
5. Passive by default. Diagnostics may probe read-only routes, but mutating,
   token-spending, and audio-session routes are passive-only unless explicitly
   invoked by the user.
6. Bounded storage. Diagnostics must solve the 1.2 GB log archaeology problem,
   not create a second unbounded store.
7. Physical iPhone realism. The plan must work when device log collection is
   unavailable.

## 1.2 Constraints

- Node relay code is JavaScript modules under `scripts/`.
- Swift client code is in `CodexDock/`; app target source is generated from
  `project.yml`.
- The Makefile is the runnable command source of truth.
- The app normally connects to relay `:4510`, not raw authenticated app-server
  `:4500`.
- `.env` is user-owned and must not be overwritten.
- The relay owns raw app-server bearer tokens; the phone must not receive them.
- The physical iPhone path may not have usable Apple unified log collection.
- Diagnostics must handle multiple configured relay hosts with distinct
  identities and independent route states.

## 1.3 Architectural principles (rules we will enforce)

- Add `scripts/dock-relay-observability-contract.mjs` as the relay-readable
  contract owner and `CodexDock/Diagnostics/ObservabilityContract.swift` as the
  Swift mirror. The mirror must be tested against the same route names and
  status vocabulary.
- Add `scripts/dock-relay-observability.mjs` as the relay runtime owner. Relay
  dispatch, route handlers, status tracker, dock session aggregator, and
  host-service diagnostics must call into it instead of inventing local state.
- Add `CodexDock/Diagnostics/ClientObservabilityStore.swift` as the app-owned
  store and state owner. Swift route clients and `AppConnectivityStore` must
  report through it instead of only writing Apple unified logs.
- Keep `DockLog` and `scripts/dock-relay-logger.mjs` as emission sinks, not as
  the canonical state model.
- Keep `/readyz` simple; put route truth in `/statusz`, `/routesz`, trace
  lookup, and bundles.
- Prefer behavior-level tests over doc/grep policing.
- Any route added later must register route config at dispatch time or fail
  tests that exercise route registration.

## 1.4 Known tradeoffs (explicit)

- We will duplicate the route vocabulary in a small Swift mirror instead of
  adding a code-generation system. Tests must prove parity. This is simpler for
  this repo than introducing a generator.
- We will keep Apple unified logging because it is useful, but it is no longer
  the primary evidence source for physical-device debugging.
- We will enhance existing CLI/status surfaces rather than add a separate
  diagnostics daemon.
- We will accept small local SQLite/JSONL stores because bounded indexed lookup
  is more maintainable than giant stderr logs.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Relay:

- `scripts/dock-relay-logger.mjs` writes structured JSON logs and sanitizes
  known sensitive fields.
- `scripts/dock-relay-status.mjs` tracks raw app-server health, request counts,
  selected upstream errors, transcription errors, and debug sessions.
- `scripts/dock-relay.mjs` serves `/readyz`, `/statusz`, `/metricsz`, and
  `/debugz/sessions`, handles downstream JSON-RPC, forwards upstream Codex
  requests, and records request success/failure.
- `scripts/dock-relay-session-table.mjs` owns `dock/subscribe`,
  `dock/resync`, last-good session persistence, and dock session aggregation.
- `scripts/codex-dock-host-service.mjs` owns service lifecycle, status, doctor,
  and log commands.

Client:

- `CodexDock/Diagnostics/Logging.swift` owns `DockLog` categories, endpoint
  display, public IDs, error summaries, and string clipping.
- `CodexDock/AppServer/AppServerClient.swift` owns JSON-RPC send/receive,
  pending request tracking, reconnect behavior, and method helpers.
- `CodexDock/State/AppServerDockStreamClient.swift` owns Dock stream
  subscription/resync over `dock/subscribe` and `dock/resync`.
- `CodexDock/State/DockStore.swift` owns multi-host Dock stream connection,
  snapshots, resync, host row state, and reconnect scheduling.
- `CodexDock/State/AppConnectivityStore.swift` rolls bootstrap, Dock, archive,
  host-test, thread-detail, and lifecycle observations into compact host and
  global status.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` renders the
  compact connectivity pill.

Ops:

- `Makefile` owns `rtk make services`, `dock-relay-status`, `relay-doctor`,
  `relay-probe`, `relay-thread-fidelity`, `sim-logs`, `device-logs`, and device
  config copy/readback.
- README documents raw app-server versus relay mode and emphasizes that the
  relay is the app-facing endpoint.

## 2.2 What's broken / missing (concrete)

- A relay can be reachable while `dock/subscribe` fails, and the app currently
  compresses that into a poor operator experience such as `Online 1/2`.
- `/readyz` and host-service status can pass without proving app-critical route
  health.
- Route failure is visible in logs only after ad hoc search; it is not indexed
  as route health with last attempt, last success, last failure, and app impact.
- Client and relay observations do not share operation IDs.
- App-side state does not have a durable diagnostics store for physical iPhone
  debugging.
- `relay-probe` is useful but does not prove every app route; `thread/list`
  health does not prove `dock/subscribe` health.
- Large response measurement can itself fail if implemented by stringifying the
  whole response after the fact.
- Diagnostics routes and CLI tools are not yet refactored onto one common
  model, so every new tool risks becoming another partial truth.

## 2.3 Constraints implied by the problem

- Route-health state must be first-class and per-host.
- Status must include app impact, not only service liveness.
- Trace metadata must be designed for JSON-RPC compatibility and stripped before
  upstream Codex.
- Payload measurement must be incremental.
- Physical-device diagnostics must be app-owned and copyable from the app data
  container.
- Mutating routes must not be auto-probed.
- Implementation must converge existing status/log/probe surfaces instead of
  adding an observability layer that nobody consumes.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

No external research is required for this plan. The design uses ordinary
observability ideas already accepted by the local codebase: structured events,
operation correlation, route-specific health, bounded local retention, and
debug bundles. External standards such as OpenTelemetry are intentionally not
adopted because this is a single-user local app and would add more maintenance
surface than value.

Adopt:

- Span-like operation correlation, but implemented as a small local contract.
- Route-level health distinct from process health.
- Bounded local event stores with indexed trace summaries.
- Debug bundles with manifest files.

Reject:

- Remote telemetry pipelines.
- Product-grade diagnostics authorization.
- Generic tracing frameworks.
- Code generation solely for route vocabulary parity.

## 3.2 Internal ground truth (code as spec)

Research pass evidence read for this plan:

- `scripts/dock-relay.mjs`
- `scripts/dock-relay-status.mjs`
- `scripts/dock-relay-logger.mjs`
- `scripts/dock-relay-session-table.mjs`
- `scripts/codex-dock-host-service.mjs`
- `scripts/dock-relay.test.mjs`
- `CodexDock/Diagnostics/Logging.swift`
- `CodexDock/AppServer/AppServerClient.swift`
- `CodexDock/AppServer/AppServerMethods.swift`
- `CodexDock/State/AppServerDockStreamClient.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/State/AppConnectivityStore.swift`
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
- `Makefile`
- `README.md`

| Surface | Evidence | Why it matters |
| --- | --- | --- |
| Relay dispatch | `scripts/dock-relay.mjs` `handleRequest`, WebSocket message loop, `recordRequest`, `classifyRelayRequestError` | Dispatch is the canonical place to create traces and route-health records by default. |
| Relay status | `scripts/dock-relay-status.mjs` `createRelayStatusTracker`, `snapshot`, `metricsSnapshot`, `debugSessionsSnapshot` | Existing status tracker should be folded into the route-health model, not bypassed. |
| Relay logger | `scripts/dock-relay-logger.mjs` `createRelayLogger`, `sanitizeFields` | Keep as a sink and content filter, not as primary state. |
| Dock route | `scripts/dock-relay-session-table.mjs` `DockSessionAggregator`, `handleDockSubscribe`, `dockUpdateForSubscriber` | `dock/subscribe` and `dock/resync` are app-critical and need route health, payload measurement, and last-good evidence. |
| Host service | `scripts/codex-dock-host-service.mjs` `statusHostServices`, `doctorHostServices`, `logsHostServices` | `relay-doctor` must consume route health and app impact. |
| Relay constants | `scripts/dock-relay-constants.mjs` `JSON_RPC_MAX_MESSAGE_BYTES` | Payload limits and size budgets belong in constants and route config. |
| Swift logging | `CodexDock/Diagnostics/Logging.swift` | `DockLog` remains the OS-log sink and content filter. |
| Swift JSON-RPC | `CodexDock/AppServer/AppServerClient.swift` `sendRequest`, `PendingRequest`, `finishPending` | Client operation IDs and trace metadata belong at request construction and completion. |
| Swift route names | `CodexDock/AppServer/AppServerMethods.swift` | Swift route vocabulary must stay in sync with the observability contract. |
| Dock stream client | `CodexDock/State/AppServerDockStreamClient.swift` | This is the direct client path for `dock/subscribe` and `dock/resync`. |
| Dock store | `CodexDock/State/DockStore.swift` `openStream`, `resync`, `handleStreamFailure`, `publishSnapshot` | Multi-host Dock state and reconnect behavior report client route evidence. |
| Connectivity | `CodexDock/State/AppConnectivityStore.swift` | Existing global status is the UI rollup that must expose route evidence. |
| Connectivity UI | `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | Compact UI remains, but detail must be evidence-backed. |
| Device config copy | `Makefile` `device-config` and `device-config-verify` | Physical debug bundle copy can reuse the app data container pattern. |
| Existing tests | `scripts/dock-relay.test.mjs`, `CodexDockTests/AppConnectivityStoreTests.swift`, `CodexDockTests/DiagnosticsLoggingTests.swift`, `CodexDockTests/AppServerClientTests.swift` | Targeted tests can be extended without inventing a new harness. |

Canonical owner paths:

- Relay contract owner: `scripts/dock-relay-observability-contract.mjs`.
- Relay runtime owner: `scripts/dock-relay-observability.mjs`.
- Swift contract mirror: `CodexDock/Diagnostics/ObservabilityContract.swift`.
- Swift runtime owner: `CodexDock/Diagnostics/ClientObservabilityStore.swift`.
- Existing status/log/probe consumers remain where they are but read from the
  new owners.

Adjacent surfaces that move with this plan:

- `scripts/dock-relay.test.mjs` and related relay test files.
- `CodexDockTests/DiagnosticsLoggingTests.swift`.
- `CodexDockTests/AppServerClientTests.swift`.
- `CodexDockTests/DockStoreTests.swift` / `DockStoreStreamTests.swift`.
- `CodexDockTests/AppConnectivityStoreTests.swift`.
- `Makefile`.
- `README.md`.

## 3.3 Decision gaps that must be resolved before implementation

None.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

Relay files:

- `scripts/dock-relay.mjs` owns server startup, HTTP endpoints, downstream
  WebSocket handling, authorization, JSON-RPC dispatch, upstream forwarding, and
  lifecycle.
- `scripts/dock-relay-status.mjs` owns current status snapshots and request
  metrics.
- `scripts/dock-relay-logger.mjs` owns structured stderr logging and content
  filters.
- `scripts/dock-relay-session-table.mjs` owns Dock session rows, last-good
  persistence, aggregator refresh, and `dock/subscribe`.
- `scripts/codex-dock-host-service.mjs` owns service lifecycle, status, doctor,
  logs, app config, launchd/systemd rendering, and health checks.

Client files:

- `CodexDock/Diagnostics/Logging.swift` owns OS log categories and helper
  formatting.
- `CodexDock/AppServer/AppServerClient.swift` owns JSON-RPC request lifecycle.
- `CodexDock/State/AppServerDockStreamClient.swift` adapts AppServerClient into
  Dock stream subscription/resync.
- `CodexDock/State/DockStore.swift` owns multi-host Dock stream orchestration.
- `CodexDock/State/AppConnectivityStore.swift` owns rollup phases and global
  status.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` renders the
  current compact rollup.

Ops files:

- `Makefile` owns runnable service, probe, log, simulator, and device commands.
- `README.md` owns user-facing runbook and endpoint contract.

## 4.2 Control paths (runtime)

Normal Dock path:

```text
App launches
-> HostRegistry provides configured hosts
-> DockStore opens one stream per host
-> AppServerDockStreamClient.connect(to:)
-> AppServerClient.connectAndInitialize()
-> AppServerDockStreamConnection.subscribe()
-> client sends dock/subscribe
-> relay handleRequest()
-> handleDockSubscribe()
-> DockSessionAggregator.refresh()
-> fetchDockSessionRows()
-> thread/list calls to history/raw Codex and live overlay helpers
-> relay returns snapshot/update
-> DockSessionTable applies rows
-> AppConnectivityStore reports compact host/global status
```

Status/doctor path:

```text
rtk make dock-relay-status / relay-doctor
-> codex-dock-host-service.mjs
-> /readyz and /statusz
-> serviceState + health checks
-> summarized status/problems
```

Physical-device config path:

```text
rtk make device-config
-> device-relay-config.mjs writes relay-config.json
-> xcrun devicectl device copy to appDataContainer

rtk make device-config-verify
-> xcrun devicectl device copy from appDataContainer
-> device-relay-config.mjs verify
```

## 4.3 Object model + key abstractions

- `DockHostConfiguration`: phone-side configured host endpoint.
- `AppServerClient`: one JSON-RPC client over WebSocket.
- `AppServerDockStreamConnection`: route adapter for Dock stream methods.
- `DockSessionAggregator`: relay-side session table refresh/subscriber owner.
- `createRelayStatusTracker`: relay-side status and metrics tracker.
- `AppConnectivityStore`: client-side host/global state rollup.
- `DockLog` / relay logger: current log sinks.

## 4.4 Observability + failure behavior today

- Relay logs method success/failure but does not persist indexed traces.
- Relay status tracks requests by method but does not expose full route-health
  state for app-critical routes.
- Dock session refresh failure can surface in relay logs while status remains
  apparently healthy.
- Client logs route attempts, stream failures, and connectivity rollups to Apple
  unified logging.
- Client state can show compact partial/offline status without preserving route
  failure evidence in app-owned storage.
- Physical-device log collection may fail; app-owned diagnostics do not exist.
- The existing useful pieces are real and should be reused, but none of them is
  the canonical evidence spine today.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current compact UI:

```text
Online 1/2
```

Current limitation: this does not say which host failed, which route failed, or
what the relay knew about that route.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

New relay files:

- `scripts/dock-relay-observability-contract.mjs`
  - Route names, event names, route status values, route budgets, probe safety,
    failure categories, payload policies.
- `scripts/dock-relay-observability.mjs`
  - `RelayObservability`
  - `RouteHealthTracker`
  - `OperationTraceStore`
  - `DiagnosticBundleBuilder`
  - incremental payload measurement helpers.
- `scripts/dock-relay-observability.test.mjs`
  - Contract, route-health, transition, trace, and bundle tests.

New Swift files:

- `CodexDock/Diagnostics/ObservabilityContract.swift`
  - Swift mirror of route/status/category vocabulary.
- `CodexDock/Diagnostics/ClientObservabilityStore.swift`
  - Client event store, operation ID generation, route observations, route
    health, and bundle snapshot.
- `CodexDock/Diagnostics/RelayDiagnosticsClient.swift`
  - Read-only HTTP fetch helper for relay diagnostics on the configured
    endpoint.
- `CodexDock/Diagnostics/DiagnosticBundle.swift`
  - App bundle manifest and file export helpers if this is too large for
    `ClientObservabilityStore`.

Existing files to refactor onto the spine:

- `scripts/dock-relay.mjs`
- `scripts/dock-relay-status.mjs`
- `scripts/dock-relay-session-table.mjs`
- `scripts/codex-dock-host-service.mjs`
- `scripts/dock-relay-logger.mjs`
- `CodexDock/AppServer/AppServerClient.swift`
- `CodexDock/State/AppServerDockStreamClient.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/State/AppConnectivityStore.swift`
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`
- `Makefile`
- `README.md`

## 5.2 Control paths (future)

Client-to-relay route:

```text
ClientObservabilityStore.startOperation(route, host)
-> AppServerClient.sendRequest(..., observabilityContext)
-> request params include _codexDockTrace only for client-to-relay route
-> relay dispatch extracts and removes trace metadata
-> RelayObservability.startRoute()
-> handler runs
-> RelayObservability records success/failure, statusReasons, measurements
-> relay response returns normal route result
-> client completes operation and asks relay diagnostics when route failed
-> AppConnectivityStore displays compact rollup with expandable evidence
```

Client relay-diagnostics fetch path:

```text
Route failure or operator opens diagnostics
-> ClientObservabilityStore keeps the original client-side route outcome
-> RelayDiagnosticsClient derives HTTP base from configured DockRelayEndpoint.statusURL
-> GET /statusz, /routesz, or /tracesz/{operationID} on that configured host:port
-> attach relay route evidence to the same configuredHostID
-> diagnostic fetch failure is recorded as extra evidence, not as a replacement
   for the original route failure
```

Relay-to-Codex upstream route:

```text
RelayObservability.startChildSpan(upstreamRoute)
-> build clean Codex params with no _codexDockTrace
-> JsonRpcWebSocketClient sends upstream request
-> record duration, result shape/count, error code/class/category
-> link child span to client/downstream operation
```

Route status:

```text
Observation events
-> OperationTraceStore
-> RouteHealthTracker transition rules
-> /statusz, /routesz, relay-doctor, host-compare, client diagnostics
```

Debug bundle:

```text
App or Makefile command requests bundle
-> app store exports app observations + route health + host config
-> relay host exports statusz/routesz/traces/manifest
-> host compare bundles are grouped by configured host
```

## 5.3 Object model + abstractions (future)

Relay:

- `ObservabilityContract`
  - `routes`
  - `statuses`
  - `failureCategories`
  - `probeSafety`
  - `budgets`
- `RelayObservability`
  - `beginOperation(context)`
  - `finishOperation(result)`
  - `recordEvent(event)`
  - `routeHealth(route, hostID)`
  - `recentTraces(query)`
  - `bundle()`
- `RouteHealthTracker`
  - computes `healthy`, `degraded`, `failed`, `stale`, `partial`, `blocked`,
    `unknown`
  - always records `statusReasons`.
- `OperationTraceStore`
  - bounded JSONL events plus SQLite trace summaries.
- `PayloadMeter`
  - incremental estimate helpers; no full stringify just to measure.

Client:

- `ObservabilityContract`
  - Swift vocabulary mirror.
- `ClientObservabilityStore`
  - operation ID generation
  - local route events
  - host route-health snapshots
  - app bundle export.
- `RelayDiagnosticsClient`
  - read-only HTTP fetch helper for `/statusz`, `/routesz`, and
    `/tracesz/{operationID}` on the configured relay endpoint.
  - derives sibling diagnostics URLs from `DockRelayEndpoint.statusURL`, so the
    app always asks the same `host:port` it is already configured to use.
  - exact derivation rule: take `DockRelayEndpoint.statusURL`, verify its path
    is `/statusz`, preserve scheme/host/port, and replace the path with the
    requested absolute diagnostics path such as `/routesz` or
    `/tracesz/{operationID}`. Do not append sibling paths under `/statusz`.
  - returns diagnostic-fetch success/failure as evidence; it never owns or
    overwrites route health.
- `RouteDiagnosticSnapshot`
  - host ID
  - route
  - operation ID
  - last attempt/success/failure
  - status reasons
  - app impact.
- `AppConnectivityStore`
  - keeps current compact status but stores route evidence in each host record.

## 5.4 Invariants and boundaries

- `scripts/dock-relay-observability-contract.mjs` and
  `CodexDock/Diagnostics/ObservabilityContract.swift` are the only route-health
  vocabulary owners.
- JSON-RPC dispatch owns route tracing by default.
- Route handlers may add measurements; they do not invent route-health state.
- `/readyz` never includes route-health facts.
- `/statusz` includes process, dependency, and route facts.
- `relay-doctor` reads `/statusz` route health instead of recomputing its own
  route model.
- App connectivity reads `ClientObservabilityStore` route facts instead of only
  mapping broad Dock/Archive/ThreadDetail phases.
- Debug bundles read from the same app/relay stores used by live status.
- Automatic probes are limited to `auto-probe-safe` routes.
- Passive-only route health is derived from real traffic unless the user runs an
  explicit mutating probe in a future implementation.

Pass 2 hardening:

- The plan chooses a Swift mirror plus parity tests, not a generator. A
  generator would be a competing maintenance surface for this repo.
- The plan chooses local app/relay stores, not a remote telemetry pipeline.
- The plan chooses existing Makefile commands as the operator surface, not a
  new diagnostics CLI family.
- The plan chooses route-health as the one status model. Existing request
  metrics, logs, and compact connectivity states become consumers or emissions
  of that model.
- The plan keeps diagnostics easy to reach for the single user. Host identity
  and content omission are required; an extra diagnostics auth layer is not.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Compact:

```text
Online 1/2
```

Chosen UI owner:

- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` remains the
  compact entry point.
- Add `CodexDock/Features/Status/ConnectivityDiagnosticsSheet.swift`.
- Tapping or long-pressing the compact indicator opens the sheet.
- The sheet reads `AppConnectivityStore` / `ClientObservabilityStore` snapshots
  and renders per-host route evidence.
- Do not put this in Hosts settings first; host settings can link to the same
  sheet later, but it is not the Phase 3 owner.

Expanded:

```text
Amir-M5
  Endpoint: amir-m5.fairy-salmon.ts.net:4510
  Dock stream: healthy
  Last dock/subscribe: 740ms, 1562 rows

Home
  Endpoint: home.fairy-salmon.ts.net:4510
  Process: reachable
  Dock stream: failed
  Route: dock/subscribe
  Reason: failed: payload.serialization at serialize-response
  Last success: 6:49 AM
  Operation: op_01J...
```

Bundle manifest:

```json
{
  "schema": "codexdock.bundle.v1",
  "createdAt": "2026-05-30T12:00:00Z",
  "appBuild": "20260530120000",
  "hosts": [
    { "hostID": "amir-m5.fairy-salmon.ts.net:4510", "included": true },
    { "hostID": "home.fairy-salmon.ts.net:4510", "included": true }
  ],
  "omitted": [
    "prompts",
    "transcripts",
    "audio",
    "headers",
    "full-jsonrpc-payloads"
  ]
}
```

## 5.6 Wire contracts (implementation shapes)

Host identity rules:

- Client-side `hostID` means the configured endpoint identity,
  `DockRelayEndpoint.id`, shaped as `host:port`.
- Relay-side host identity means the relay-reported instance identity from
  `CODEX_DOCK_REAL_HOST_ID` / `/statusz.host.id`, such as `home` or `Amir-M5`.
- Route-health records and bundles carry both when both are known:
  `configuredHostID` for the app endpoint and `relayHostID` for the relay
  instance.
- The app never merges configured hosts by relay instance identity. Host
  comparison is per configured endpoint.

Trace metadata is client-to-relay only. It is extracted by the relay and removed
before route validation and before any upstream Codex request:

```json
{
  "_codexDockTrace": {
    "schema": "codexdock.trace.v1",
    "traceID": "tr_01J...",
    "operationID": "op_client_01J...",
    "parentOperationID": null,
    "configuredHostID": "home.fairy-salmon.ts.net:4510",
    "route": "dock/subscribe",
    "clientBuild": "20260530120000",
    "platform": "ios"
  }
}
```

Trace metadata rules:

- The client inserts `_codexDockTrace` only when request params are an object.
- For methods with no params, the client may send params containing only
  `_codexDockTrace`.
- For methods with non-object params, no trace metadata is injected until that
  method explicitly defines a scrubber.
- The relay records the extracted trace context and deletes `_codexDockTrace`
  before handler code receives params.
- Upstream Codex params are always built from scrubbed params.

Route health record:

```json
{
  "schema": "codexdock.routeHealth.v1",
  "configuredHostID": "home.fairy-salmon.ts.net:4510",
  "relayHostID": "home",
  "route": "dock/subscribe",
  "probeSafety": "auto-probe-safe",
  "appCritical": true,
  "routeStatus": "failed",
  "statusReasons": [
    {
      "code": "failed:last-attempt",
      "message": "last attempt failed at serialize-response",
      "threshold": null,
      "actual": "payload.serialization",
      "evidenceIDs": ["evt_01J..."]
    }
  ],
  "lastAttempt": {
    "operationID": "op_01J...",
    "at": "2026-05-30T12:00:00Z",
    "durationMs": 41481,
    "outcome": "failed",
    "failureCategory": "payload.serialization",
    "phase": "serialize-response"
  },
  "lastSuccess": {
    "operationID": "op_01J...",
    "at": "2026-05-30T11:49:21Z",
    "durationMs": 740,
    "rowCount": 918,
    "estimatedBytes": 1048576
  },
  "rolling": {
    "attempts": 20,
    "successes": 18,
    "failures": 2,
    "p50Ms": 740,
    "p95Ms": 41000
  },
  "appImpact": [
    {
      "surface": "Dock",
      "severity": "error",
      "message": "Host appears offline for Dock because dock/subscribe failed"
    }
  ]
}
```

`/statusz` route layout:

```json
{
  "ok": false,
  "service": "codex-dock-relay",
  "host": { "id": "home", "displayName": "Home" },
  "process": { "ok": true, "uptimeSeconds": 940 },
  "dependencies": {
    "rawAppServer": { "ok": true, "lastAttempt": {} }
  },
  "routes": {
    "thread/list": { "routeStatus": "healthy", "statusReasons": [] },
    "dock/subscribe": { "routeStatus": "failed", "statusReasons": [] }
  },
  "appImpact": []
}
```

Client route diagnostic snapshot:

```json
{
  "schema": "codexdock.clientRouteDiagnostic.v1",
  "configuredHostID": "home.fairy-salmon.ts.net:4510",
  "relayHostID": "home",
  "route": "dock/subscribe",
  "routeStatus": "failed",
  "operationID": "op_client_01J...",
  "relayOperationID": "op_01J...",
  "lastAttempt": {},
  "lastSuccess": {},
  "statusReasons": [],
  "relayDiagnosisAvailable": true
}
```

Route status transition rules:

- `unknown`: no local or relay attempt exists for this host/route.
- `healthy`: last attempt succeeded, result is fresh within the route budget,
  and no required child route failed.
- `degraded`: last attempt succeeded or last-good data is usable, but at least
  one reason is true: slow duration above route budget, recent non-fatal
  failure, stale-but-usable data, fallback to last-good, or degraded dependency.
- `failed`: last app-critical attempt failed and no usable result exists, or
  the route has reached its configured consecutive-failure threshold.
- `stale`: route is showing last-good data older than the freshness budget.
- `partial`: a composite route has at least one required child/host/page success
  and at least one required child/host/page failure.
- `blocked`: route is waiting on device lifecycle, foreground work gate, user
  approval/input, or another explicit precondition.

Status reason rules:

- A `routeStatus` without at least one `statusReasons[]` entry is invalid unless
  the status is `healthy` or `unknown`.
- Every non-empty status reason includes `code`, `message`, `actual` or
  `threshold`, and at least one evidence ID.
- UI may summarize reasons, but bundles and `/statusz` preserve the structured
  fields.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Relay contract | `scripts/dock-relay-observability-contract.mjs` | new file | No owner | Add route names, statuses, categories, budgets, probe safety | SSOT for relay vocabulary | `OBSERVABILITY_CONTRACT` | new relay tests |
| Swift contract | `CodexDock/Diagnostics/ObservabilityContract.swift` | new file | No mirror | Add Swift mirror of route/status/category/probe vocabulary | Client must render same route truth | `ObservabilityContract` | `DiagnosticsLoggingTests`, new diagnostics tests |
| Relay observability | `scripts/dock-relay-observability.mjs` | new file | No route-health owner | Add events, traces, route health, bounded store, bundle builder | Central spine | `RelayObservability` | new relay observability tests |
| Relay dispatch | `scripts/dock-relay.mjs` | WebSocket message loop, `handleRequest` | Logs success/failure locally | Wrap every downstream request in operation trace and route health | By-default instrumentation | `observability.beginRoute/finishRoute` | `scripts/dock-relay.test.mjs` |
| Trace scrub | `scripts/dock-relay.mjs` | dispatch param parsing | No trace metadata | Extract `_codexDockTrace`, scrub before handler/upstream | Prevent Codex metadata leak | `extractTraceContext()` | relay metadata strip test |
| Request metrics | `scripts/dock-relay-status.mjs` | `recordRequest`, `requestMetrics` | Method counters only | Feed route-health tracker or become adapter over it | Avoid parallel metrics truth | `RouteHealthTracker.recordAttempt` | status tests |
| Error category | `scripts/dock-relay-status.mjs` | `classifyRelayRequestError` | Existing subsystem/code classifier | Map to shared category while preserving original code/subsystem | No duplicate taxonomy | `classifyFailure()` | classifier tests |
| HTTP status | `scripts/dock-relay.mjs` | `/statusz` | Process/dependency status | Include route health, status reasons, app impact | Route truth visible | status schema v2 | relay status tests |
| HTTP health | `scripts/dock-relay.mjs` | `/healthz` | Static config/process health | Keep as process/config diagnostic only; explicitly do not add app route truth | Prevent competing health meaning | process/config health JSON | relay HTTP tests |
| Route endpoint | `scripts/dock-relay.mjs` | `/routesz` | Missing | Add full route-health response | CLI and app diagnostics | route health JSON | relay HTTP tests |
| Trace endpoint | `scripts/dock-relay.mjs` | `/tracesz/recent`, `/tracesz/{id}` | Missing | Add trace lookup | Debug one operation | trace query JSON | relay HTTP tests |
| Self-test | `scripts/dock-relay.mjs` | `/selftestz` | Missing | Probe auto-probe-safe routes only | No mutating diagnostics | probe safety contract | relay selftest tests |
| Bundle endpoint | `scripts/dock-relay.mjs` | `/bundlez` | Missing | Return capped local bundle | Easy single-user debugging | bundle manifest | bundle tests |
| Metrics endpoint | `scripts/dock-relay.mjs`, `scripts/dock-relay-status.mjs` | `/metricsz`, `metricsSnapshot` | Loopback metrics from status tracker | Make it an adapter over route-health counters and trace store summaries | Prevent parallel request metrics truth | metrics projection from `RelayObservability` | relay metrics tests |
| Debug sessions endpoint | `scripts/dock-relay.mjs`, `scripts/dock-relay-status.mjs` | `/debugz/sessions`, `debugSessionsSnapshot` | Loopback runtime/session snapshot | Keep runtime/session debug fields, add operation IDs where useful, and do not compute health independently | Preserve useful runtime view without competing health model | runtime snapshot plus trace links | relay debug endpoint tests |
| Relay logger | `scripts/dock-relay-logger.mjs` | `createRelayLogger`, `sanitizeFields` | Log sink + content filter | Keep sink; add typed observation emission fields if needed | Do not make logs state owner | unchanged sink API or small adapter | logger tests |
| Dock aggregator | `scripts/dock-relay-session-table.mjs` | `DockSessionAggregator.refresh` | Logs refresh success/failure | Record phase, duration, rows, last-good, payload estimate | `dock/subscribe` route evidence | route measurements | dock subscribe tests |
| Dock subscribe | `scripts/dock-relay-session-table.mjs` | `handleDockSubscribe` | Sends snapshot/update | Attach route health, subscriber count, snapshot measurement | App-critical route proof | route measurements | dock stream tests |
| Last good | `scripts/dock-relay-session-table.mjs` | `readLastGood`, `writeLastGoodAtomic` | Last-good persistence only | Record last-good age and availability in route health | Explain stale/fallback | measurement event | aggregator tests |
| Payload size | `scripts/dock-relay-session-table.mjs` | `sortedJSONString`, send path | Full stringify can fail | Add incremental estimate before send | Avoid measurement failure | `PayloadMeter` | payload guardrail tests |
| Host service status | `scripts/codex-dock-host-service.mjs` | `checkRelayStatusz`, `statusHostServices` | Health summary | Preserve summary but include route app impact | CLI proof | route-aware status | host-service tests |
| Host service doctor | `scripts/codex-dock-host-service.mjs` | `doctorHostServices` | Problems from process checks | Include app-critical route failures and evidence | `relay-doctor` cannot pass route failure silently | route appImpact | host-service tests |
| Host service logs | `scripts/codex-dock-host-service.mjs` | `logsHostServices` | Tails logs | Keep for secondary evidence; point users to traces/routes first | Avoid log archaeology as primary path | no new contract | host-service tests if output changes |
| CLI commands | `Makefile` | `relay-probe`, `relay-doctor` | Probe/doctor partial routes | Refactor onto status/routes/traces; add route probe, host compare, debug bundle | One operational model | new make targets | command smoke where practical |
| Relay probe script | `scripts/dock-relay-probe.mjs` | script main, `requestThreadList` | Compares raw history and relay `thread/list` top row/cursor | Keep as raw-vs-relay fidelity probe; do not make it multi-host route health owner | `relay-host-compare` owns multi-host app-path comparison | probe output may include trace IDs later | relay-probe smoke/manual |
| App JSON-RPC | `CodexDock/AppServer/AppServerClient.swift` | `sendRequest`, `PendingRequest`, `finishPending` | Request IDs only | Add operation context, trace metadata injection for client-to-relay, completion event | Client operation spans | `AppServerRequestContext` | `AppServerClientTests` |
| JSONValue params | `CodexDock/AppServer/JSONRPC.swift` | `JSONRPCRequest.params` | Raw params | Preserve JSON-RPC shape; do not top-level `meta` | Protocol compatibility | `_codexDockTrace` in params object | encoding tests |
| Route methods | `CodexDock/AppServer/AppServerMethods.swift` | route constants | Method names only | Ensure contract parity test covers app routes | No drift | contract mirror | new parity test |
| Dock stream client | `CodexDock/State/AppServerDockStreamClient.swift` | `subscribe`, `resync`, `updates` | Logs route attempts | Start/finish client operations and attach host/route diagnostics | Actual app route path | `ClientObservabilityStore` | DockStore stream tests |
| Dock store | `CodexDock/State/DockStore.swift` | `openStream`, `resync`, `handleStreamFailure` | Host load status and reconnect | Publish route-specific failure/success to observability store | App host evidence | `RouteDiagnosticSnapshot` | DockStore tests |
| Session table | `CodexDock/State/DockSessionTable.swift` | host status projection | Loaded/checking/partial/failure | Preserve row behavior; attach route evidence to host status | UI detail | diagnostic field or associated model | DockStore projection tests |
| Connectivity store | `CodexDock/State/AppConnectivityStore.swift` | `HostRecord`, `Observation`, `rollup` | Phase-only rollup | Store route diagnostics per host and preserve compact status | Expandable evidence | `HostRouteDiagnostic` | AppConnectivityStoreTests |
| Connectivity UI entry | `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | compact pill | Label only | Keep compact label and make it open the diagnostics sheet | Avoid clutter while preserving evidence | sheet presentation | UI/view tests if present |
| Connectivity diagnostics UI | `CodexDock/Features/Status/ConnectivityDiagnosticsSheet.swift` | new file | Missing | Render per-host route evidence, operation IDs, status reasons, and export/copy action | One chosen app diagnostics owner | `ConnectivityDiagnosticsViewModel` or direct store snapshot | AppConnectivityStore/UI tests |
| Host settings UI | `CodexDock/Features/Hosts/HostsView.swift` | host rows/settings | Host configuration only | If host settings exposes diagnostics, it must invoke the same `ConnectivityDiagnosticsSheet`; do not create a second diagnostics UI | Avoid competing app diagnostics surfaces | shared sheet invocation | UI/view tests if touched |
| Thread detail store | `CodexDock/State/ThreadDetailStore.swift` | load, turns pagination, reconnect, resume | Logs detail lifecycle and reports broad live state | Record `thread/read`, `thread/turns/list`, and passive-only `thread/resume` route evidence | Partial page failures must be obvious | route diagnostics per child span | ThreadDetailStoreTests |
| Thread detail voice integration | `CodexDock/State/ThreadDetailStore+Voice.swift` | voice start/commit/cancel integration | Coordinates voice actions through thread detail state | Attach voice/transcription route outcomes to the same thread-detail operation tree and client observability store | Voice failures must not look like generic thread-detail failures | route diagnostics linked to active thread operation | ThreadDetailStoreTests |
| Archive store | `CodexDock/State/ArchiveStore.swift` | archived load and host outcomes | Reports archive state to connectivity | Record archive list/load route evidence and passive-only archive mutations from real traffic | Archive failures should not be generic host failures | route diagnostics | DockStore/Archive tests |
| App bundle store | `CodexDock/Diagnostics/ClientObservabilityStore.swift` | new | Missing | Persist bounded observations and route health in Application Support | Physical device proof | app diagnostics store | diagnostics tests |
| Relay diagnostics fetch | `CodexDock/Diagnostics/RelayDiagnosticsClient.swift` | new | Missing | Fetch `/statusz`, `/routesz`, and `/tracesz/{operationID}` from the configured relay endpoint using `DockRelayEndpoint.statusURL` as the base pattern | App can cross-check relay truth for the same host it uses for JSON-RPC | read-only relay diagnostics HTTP client | diagnostics HTTP tests |
| App bundle export | `CodexDock/Diagnostics/DiagnosticBundle.swift` | new or same owner | Missing | Export manifest + route health + observations | Debug bundle | `DiagnosticBundleManifest` | diagnostics tests |
| Realtime transcription client | `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` | realtime transcription JSON-RPC/WebSocket calls | Sends transcription operations through the relay | Record passive route evidence for realtime transcription start/append/commit/cancel/error paths without audio or transcript content | Audio route failures need first-class route evidence | transcription route diagnostics, content omitted | voice/transcription tests |
| Transcription service | `CodexDock/Voice/TranscriptionService.swift` | transcription lifecycle coordinator | Coordinates capture/client state and reports broad lifecycle outcomes | Report start/append/commit/cancel outcomes into `ClientObservabilityStore` without transcript text or audio bytes | Single route spine must include voice, not only dock/thread/archive | route diagnostics only, no content payloads | voice/transcription tests |
| Realtime transcription DTOs | `CodexDock/AppServer/RealtimeTranscriptionDTO.swift` | DTO encoding/decoding | Shapes realtime transcription messages | Ensure route diagnostics reference DTO route/method outcomes without serializing raw audio, transcript text, or provider payload content | Keeps observability useful without content capture | content-omission contract | DTO/encoding tests |
| Voice capture controller | `CodexDock/Voice/VoiceCaptureController.swift` | local audio capture lifecycle | Captures local audio and emits capture state | Emit only local capture state summaries if needed; never store raw audio bytes in route observations or bundles | Debug voice failures while keeping bundles small and content-free | capture summary evidence only | voice tests |
| Device copy | `Makefile` | new `device-debug-bundle` | Only config readback/log collect | Copy app diagnostics from app data container | Avoid Apple log dependency | make target | manual/device proof |
| Simulator copy | `Makefile` | new `sim-debug-bundle` | Simulator logs only | Copy app diagnostics from sim app container and relay hosts | Easier repro | make target | simulator proof |
| README | `README.md` | relay diagnostics/runbook | Logs/status/probe docs | Update to one route-health/bundle workflow | Prevent stale runbook | docs update | readback |
| Tests package | `package.json` | `test:relay` | Existing relay tests | Include new observability tests | Keep command source of truth | npm script | `rtk npm run test:relay` |
| Project config | `project.yml`, `Package.swift` | source inclusion | Directory-based sources | No change expected unless resources are added | Avoid unnecessary XcodeGen churn | n/a | only if resources added |

## 6.2 Migration notes

Canonical owner path:

- Relay runtime truth: `RelayObservability`.
- Client runtime truth: `ClientObservabilityStore`.
- Contract truth: small JS owner plus Swift mirror with parity tests.

Clean cutover:

- Existing status/doctor/probe surfaces are refactored to consume the new route
  model.
- No long-lived compatibility bridge is planned.
- Existing OS/relay logs remain sinks during and after cutover.

Delete/retire list:

- Retire any new local request counters that duplicate route-health counts.
- Retire route-specific ad hoc status fields once route health owns the same
  facts.
- Do not preserve old docs that teach log archaeology as the primary path after
  bundles/traces exist.

Adjacent surfaces:

- README and Makefile move in the same implementation arc.
- Swift and Node test contracts move with the route vocabulary.
- Generated Xcode project changes are not expected because sources are included
  by directory; if project config changes, update `project.yml` first.

Behavior preservation:

- Existing `dock/subscribe` result shape remains unchanged.
- Existing `dock/update` notification shape remains unchanged unless explicit
  route diagnostics fields are added to a separate diagnostics surface.
- Existing compact connectivity labels remain stable unless tests are updated
  for intentionally improved detail.
- Existing raw Codex upstream method params remain clean of trace metadata.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Existing pattern | Disposition | Reason |
| --- | --- | --- |
| `DockLog` categories | Keep as sink | Useful OS-log emission, but not durable route evidence. |
| `scripts/dock-relay-logger.mjs` | Keep as sink/filter | Useful structured stderr; route state moves to `RelayObservability`. |
| `createRelayStatusTracker` | Fold into route health | Existing request metrics should not compete with route-health truth. |
| Host-service doctor checks | Refactor consumer | Doctor should read route health and app impact instead of recomputing health. |
| `AppConnectivityStore` rollups | Extend | Compact labels stay, route evidence becomes expandable host detail. |
| `relay-probe` | Keep as one probe profile | It should not remain the only proof route. |
| Device config app-container copy | Reuse | Same app data container pattern should power physical debug bundles. |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. No fallbacks/runtime shims - the system must work correctly or fail loudly. Prefer programmatic checks per phase; defer manual/UI verification to finalization when appropriate. Avoid negative-value tests and heuristic gates.

<!-- arch_skill:block:phase_plan:start -->
Obligation sweep:

- Contract ownership is in Phase 1 and Phase 3.
- Relay route-health dispatch is in Phase 1.
- Safe probes and trace lookup are in Phase 2.
- Client route evidence is in Phase 3.
- Physical/simulator debug bundles and multi-host compare are in Phase 4.
- Remaining route families and stale-surface convergence are in Phase 5.
- No required implementation work is left only in Sections 5, 6, 8, 9, or the
  Decision Log.

## Phase 1 - Relay route-health spine through the real Dock path

Goal:

Prove the highest-risk seam first: `dock/subscribe` can fail while the relay is
alive, and `/statusz` plus `relay-doctor` can show that route-specific truth
from one canonical relay observability owner.

Work:

Create the relay contract and observability owner, wire it into downstream
dispatch and `dock/subscribe`, and enhance `/statusz`/doctor to consume route
health.

Checklist (must all be done):

- Add `scripts/dock-relay-observability-contract.mjs` with route names,
  statuses, categories, route budgets, and probe safety for at least:
  `readyz`, `statusz`, `thread/list`, `dock/subscribe`, `dock/resync`,
  `thread/read`, `thread/turns/list`, archive, turn, and transcription routes.
- The Phase 1 contract must enumerate every `AppServerMethods` route and
  notification known at implementation time, including `initialize`,
  `initialized`, `thread/list`, `thread/read`, `thread/resume`,
  `thread/turns/list`, `thread/archive`, `thread/unarchive`, `dock/subscribe`,
  `dock/update`, `dock/resync`, `turn/start`, `turn/steer`, `turn/interrupt`,
  `audio/transcription/start`, `audio/transcription/append`,
  `audio/transcription/commit`, `audio/transcription/cancel`,
  `audio/transcription/delta`, `audio/transcription/completed`,
  `audio/transcription/failed`, `audio/transcription/canceled`, and
  `audio/transcription/closed`.
- Notification-only routes such as `dock/update` and transcription push events
  are passive evidence on their parent stream/session operation. They are never
  auto-probe targets and do not need standalone request/response health
  semantics.
- Add `scripts/dock-relay-observability.mjs` with event recording, operation
  lifecycle, route health transition rules, status reasons, and in-memory
  bounded recent traces.
- Wire `scripts/dock-relay.mjs` dispatch so every downstream JSON-RPC request
  starts and finishes a route operation.
- Ensure dispatch records success, JSON-RPC error, thrown error, timeout,
  cancellation/close, and duration.
- Preserve existing `recordRequest` behavior by adapting it to the route-health
  model or calling both from the same dispatch point.
- Wire `dock/subscribe` and `dock/resync` to record refresh phase, row count,
  last-good availability, subscriber count, and failure category.
- Enhance `/statusz` to include route health, `statusReasons`, and `appImpact`
  without changing `/readyz` into a route-health endpoint.
- Keep `/healthz` as process/static-config health only and document that it is
  not app route health.
- Convert `/metricsz` to project counters from `RelayObservability` instead of
  maintaining a separate request-metrics truth.
- Keep `/debugz/sessions` as runtime/session debugging, but link to operation
  IDs rather than computing health independently.
- Update `doctorHostServices` so `relay-doctor` fails or warns on app-critical
  route failure even when process checks pass.
- Add tests for route status transitions and `/readyz` passing while
  `dock/subscribe` route health fails.

Verification (required proof):

- `rtk npm run test:relay`

Docs/comments (propagation; only if needed):

- Add a short code comment at the relay observability owner explaining that
  route health is separate from process health.

Exit criteria (all required):

- `dock/subscribe` route failure is visible in `/statusz.routes` with
  `statusReasons`.
- `relay-doctor` cannot report a clean pass when an app-critical route is
  failing.
- Existing successful `dock/subscribe` tests still prove the response shape is
  unchanged.
- No second route-health model exists outside the relay observability owner.

Rollback:

- Revert the relay observability owner and status/doctor consumers together.
  Do not leave `/statusz` reading half-new, half-old route state.

## Phase 2 - Safe payload measurement, safe probes, and trace lookup

Goal:

Make relay route diagnosis useful for large/slow/partial routes without causing
the act of measuring or probing to break production behavior.

Work:

Add incremental payload measurement, trace lookup endpoints, full route-health
HTTP surfaces, and auto-probe-safe route checks.

Checklist (must all be done):

- Add incremental payload measurement helpers that estimate serialized size
  while building route output; do not use full `JSON.stringify` solely to
  measure large route payloads.
- Add route payload policies for `dock/subscribe`, `thread/list`,
  `thread/read`, `thread/turns/list`, and debug bundles.
- Add `/routesz` for full route health.
- Add `/tracesz/recent` and `/tracesz/{operationID}` for recent trace lookup.
- Add `/selftestz` that invokes only `auto-probe-safe` routes.
- Add safe probe profiles for process-only, app-critical read route, Dock route,
  and sampled thread-detail read route.
- Keep `scripts/dock-relay-probe.mjs` as raw-history versus relay `thread/list`
  fidelity proof; do not turn it into the multi-host app-path proof.
- Add `relay-host-compare` as the multi-host app-path proof over
  `/readyz`, `/statusz`, `/routesz`, and selected safe routes.
- Ensure passive-only routes are never invoked by `/selftestz` or host compare.
- Add tests proving passive-only routes are not auto-probed.
- Add tests proving payload measurement records row count, estimated bytes,
  largest-row estimate, and failure phase without requiring full stringify.

Verification (required proof):

- `rtk npm run test:relay`

Docs/comments (propagation; only if needed):

- Document the auto-probe-safe versus passive-only rule at the contract owner.

Exit criteria (all required):

- A payload serialization failure records a failure phase and available safe
  measurements.
- Trace lookup returns enough evidence to debug one failed operation without
  reading stderr.
- `/selftestz` can never start turns, mutate archive state, or open
  transcription sessions.

Rollback:

- Revert probe and trace endpoints with their tests. Keep Phase 1 route-health
  spine intact only if its tests still pass.

## Phase 3 - Client operation tracing and connectivity evidence

Goal:

Make the client path the user actually sees report the same host/route evidence
as the relay, while keeping the compact UI simple.

Work:

Add the Swift contract mirror and app-owned observability store, then wire the
real client route path from `AppServerClient` through Dock stream and
connectivity rollup.

Checklist (must all be done):

- Add `CodexDock/Diagnostics/ObservabilityContract.swift` with Swift route,
  route-status, failure-category, and probe-safety vocabulary.
- Add tests proving Swift vocabulary parity with the relay contract values used
  by app-critical routes.
- Add `CodexDock/Diagnostics/ClientObservabilityStore.swift` with operation ID
  generation, bounded in-memory route observations, route health snapshots, and
  bundle snapshot primitives.
- Add `CodexDock/Diagnostics/RelayDiagnosticsClient.swift` as a read-only HTTP
  helper that derives `/statusz`, `/routesz`, and `/tracesz/{operationID}` from
  the configured relay endpoint's `DockRelayEndpoint.statusURL` host/port.
- URL derivation is exact: validate the base `statusURL` path is `/statusz`,
  preserve scheme/host/port, replace the path with the requested diagnostics
  path, and never append `/routesz` or `/tracesz` below `/statusz`.
- Extend `AppServerClient.sendRequest` with optional route observability context.
- Inject `_codexDockTrace` only into client-to-relay object params and preserve
  existing request encoding otherwise.
- Add tests proving trace metadata is sent for client-to-relay routes and not
  added to unrelated messages unless requested.
- Wire `AppServerDockStreamClient.subscribe/resync` to create client
  operations for `dock/subscribe` and `dock/resync`.
- Wire `DockStore` stream open/resync/failure handling to report route outcomes
  per host.
- When a route fails or diagnostics are opened, fetch relay-side diagnostics
  for that same configured host endpoint via `/statusz`, `/routesz`, or
  `/tracesz/{operationID}` and attach the result to the existing
  `ClientObservabilityStore` snapshot.
- Record relay-diagnostics fetch failures as additional evidence; never let
  them erase or replace the original client-side route outcome.
- Extend `AppConnectivityStore` host records with route diagnostics while
  preserving compact `overallStatus` behavior.
- Wire `RelayRealtimeTranscriptionClient`, `TranscriptionService`, and
  `ThreadDetailStore+Voice` into the same client route-observation path for
  realtime transcription routes, omitting audio bytes, transcript text, and raw
  provider payload content.
- Update `GlobalConnectivityIndicatorView` so route evidence is one tap/copy
  away without cluttering the compact pill.
- Add `ConnectivityDiagnosticsSheet.swift` as the one app diagnostics detail
  surface opened from the compact indicator.
- If `HostsView` needs a diagnostics affordance, link it to the same sheet
  instead of creating a second diagnostics view.

Verification (required proof):

- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk swift test --filter DiagnosticsLoggingTests`

Docs/comments (propagation; only if needed):

- Add a short comment at the client observability store explaining that Apple
  unified logging is a sink, not the durable evidence source.

Exit criteria (all required):

- The app can represent `Home process reachable, dock/subscribe failed` as a
  host route-diagnostic fact.
- Compact connectivity labels still work for single-host and multi-host states.
- Client operation IDs can be linked to relay route traces.
- Trace metadata injection preserves existing JSON-RPC request behavior when no
  observability context is supplied.

Rollback:

- Revert client observability wiring as one unit. Do not leave trace metadata
  injection without a store that records operation completion.

## Phase 4 - Debug bundles and multi-host operator workflow

Goal:

Make future interop bugs easy to debug from saved artifacts, including physical
iPhone cases where Apple log collection fails.

Work:

Add bounded relay and app diagnostic stores, bundle export, simulator/device
copy commands, and host compare output.

Checklist (must all be done):

- Add bounded relay persistence under `.codex-dock/observability/` for recent
  events, trace summaries, route health, metrics, and bundles.
- Add app-owned diagnostics persistence under
  `Library/Application Support/CodexDock/Diagnostics/`.
- Add relay bundle export with manifest, `statusz`, `routesz`, selected traces,
  route health, and omission list.
- Add app bundle export with manifest, app build, host config, route health,
  recent traces, and omission list.
- Add `rtk make relay-debug-bundle`.
- Add `rtk make relay-host-compare HOSTS=...` using `/readyz`, `/statusz`,
  `/routesz`, and selected safe routes.
- Add `rtk make sim-debug-bundle SIM='iPhone 14'`.
- Add `rtk make device-debug-bundle DEVICE=<device-udid>` using app data
  container copy, modeled on existing device config readback.
- Keep bundle export simple for this single-user app; do not add a diagnostics
  auth subsystem.
- Add tests for bundle manifests, capped output, host identity preservation, and
  content omission.

Verification (required proof):

- `rtk npm run test:relay`
- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk swift test --filter DiagnosticsLoggingTests`
- `rtk make sim-debug-bundle SIM='iPhone 14'` when simulator/app install is
  available; otherwise record exact blocker.

Docs/comments (propagation; only if needed):

- Update `README.md` diagnostics/runbook sections.
- Update `Makefile` help output for new targets.

Exit criteria (all required):

- A saved debug bundle can answer which configured host failed which route and
  why.
- Physical iPhone debugging has an app-owned artifact path that does not depend
  on Apple unified log collection.
- Host compare reports route differences per configured host.
- No new unbounded diagnostics file is introduced.

Rollback:

- Remove new bundle commands and persistence readers/writers together. Keep live
  route health only if previous phases remain green.

## Phase 5 - Extend route coverage and finish convergence

Goal:

Finish the observability spine across thread detail, archive, transcription,
docs, and stale diagnostic surfaces so there are no competing ways to answer
"what happened?"

Work:

Expand route diagnostics to the remaining app-critical paths, retire duplicate
truth surfaces, and finalize tests/docs.

Checklist (must all be done):

- Add client and relay route observations for `thread/read` and
  `thread/turns/list` including partial multi-page failures.
- Add passive-only real-traffic observations for `thread/resume`, `turn/start`,
  `turn/steer`, archive/unarchive, and transcription routes.
- Add thread detail tests proving a failed turns page appears as partial route
  evidence, not a generic host failure.
- Add archive tests proving mutating route failures are observed from real
  traffic but never auto-probed.
- Add transcription tests proving start/append/commit/cancel routes are
  passive-only and content is omitted from diagnostics.
- Update README and any touched docs/comments to teach the new route-health and
  bundle workflow.
- Mark `docs/CODEX_DOCK_OBSERVABILITY_LOGGING_FRAMEWORK_2026-05-28.md` as
  superseded by this plan once the new observability spine is implemented.
- Remove or rewrite stale runbook language that says logs/status alone are the
  primary proof path.
- Run final relevant Swift, Node, and simulator checks.

Verification (required proof):

- `rtk npm run test:relay`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter AppConnectivityStoreTests`
- `rtk make app-test SIM='iPhone 17'` if UI surfaces changed; otherwise
  `rtk make app SIM='iPhone 17'` for build proof if project wiring changed.

Docs/comments (propagation; only if needed):

- README diagnostics runbook.
- Any code comments at observability contract boundaries.

Exit criteria (all required):

- Every route listed in the contract has owner, probe-safety class, and route
  health behavior.
- No current CLI, README, status, or app connectivity surface teaches a
  competing health model.
- Final tests prove route evidence across relay, client, thread detail, and
  multi-host connectivity.
- Implementation audit can validate completion from Section 7 without inventing
  missing requirements.

Rollback:

- Roll back route-family expansions independently only if the core route-health
  spine remains coherent and tests still pass. Do not leave half-migrated route
  families with duplicate diagnostic owners.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. Prefer the existing test commands and behavior
checks that already prove the relevant boundary. Add narrow tests only where the
new observability spine creates a new contract.

## 8.1 Unit tests (contracts)

- Relay contract tests:
  - route names/statuses/categories/probe safety exist for all app routes.
  - status transition rules produce status reasons with evidence IDs.
  - passive-only routes cannot be auto-probed.
  - failure classification maps existing subsystem/code evidence into the new
    category without losing the original fields.
- Swift contract tests:
  - Swift route/status/category vocabulary matches the relay contract for
    app-critical routes.
  - `AppServerClient` preserves old request encoding when no observability
    context is provided.
  - trace metadata injection is scoped and object-param only.
- Content omission tests:
  - diagnostics omit prompts, transcripts, raw audio, headers, bearer tokens,
    API keys, and full payload dumps.

## 8.2 Integration tests (flows)

- Relay WebSocket tests:
  - `dock/subscribe` success preserves existing response shape.
  - `dock/subscribe` failure updates route health and `/statusz`.
  - `thread/list` can be healthy while `dock/subscribe` fails.
  - `/selftestz` only invokes auto-probe-safe routes.
  - trace lookup returns recent failed operation evidence.
- Swift store tests:
  - Dock stream failure creates host route evidence.
  - `AppConnectivityStore` keeps compact multi-host labels while preserving
    route details.
  - Thread detail partial failure is represented as route partial, not generic
    offline.

## 8.3 E2E / device tests (realistic)

- Simulator:
  - `rtk make sim-debug-bundle SIM='iPhone 14'` once target exists.
  - app shows multi-host compact status and route detail for a route-failing
    host.
- Physical iPhone:
  - `rtk make device-debug-bundle DEVICE=<device-udid>` copies app-owned
    diagnostics when device access allows it.
  - If physical copy fails, record the exact blocker and rely on simulator plus
    relay bundle proof until Amir runs manual physical verification.
- Relay hosts:
  - `rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

- Implement behind no product toggle; this is diagnostics infrastructure for the
  existing single-user app path.
- Roll out by phase. Each phase preserves existing app behavior while increasing
  diagnostic evidence.
- Keep existing logs/status surfaces during migration, but make them read from
  the new spine as soon as their phase lands.
- Do not run mutating probes during rollout.

## 9.2 Telemetry changes

- Local-only telemetry:
  - route observations.
  - operation traces.
  - route-health snapshots.
  - bounded metrics.
  - debug bundles.
- No remote telemetry sink.
- No SaaS analytics.
- No new cross-user aggregation.

## 9.3 Operational runbook

Normal future debugging order:

1. Check app expanded connectivity details.
2. Run `rtk make relay-host-compare HOSTS=...`.
3. Inspect `/statusz` and `/routesz` for the failing host.
4. Pull `/tracesz/{operationID}` if the app shows an operation ID.
5. Generate `rtk make relay-debug-bundle`.
6. For simulator/device issues, generate `sim-debug-bundle` or
   `device-debug-bundle`.
7. Use `dock-relay-logs` only as a secondary evidence source.

# 10) Decision Log (append-only)

## 2026-05-30 - Single-user multi-host diagnostics posture

Context

The first observability proposal included extra diagnostics access-control
language. The app is single-user but still multi-host.

Options

- Keep product-style diagnostics auth and loopback gating.
- Simplify diagnostics for local/operator use while preserving host identity,
  bounded bundles, and content omission.

Decision

Simplify. Diagnostics must be easy to export from the app and from each
configured relay host. Do not add a separate operator-token or diagnostics-auth
system.

Consequences

The plan keeps multi-host host identity and bundle manifests, but rejects
product-hardening ceremony that would make this single-user app harder to
maintain.

Follow-ups

Keep content omission and bundle caps because they directly improve local
debugging quality.

## 2026-05-30 - Route health is separate from process health

Context

The home relay incident showed that liveness checks and app-critical route
health can disagree.

Options

- Treat `/readyz` or host-service status as enough.
- Make route health first-class and evidence-backed.

Decision

Make route health first-class. `/readyz` remains liveness only; `/statusz`,
`/routesz`, doctor, traces, bundles, and app connectivity carry route evidence.

Consequences

Every route status must include concrete `statusReasons`. Compact UI labels are
allowed only as summaries of route evidence.

Follow-ups

Phase 1 must prove `readyz` can pass while `dock/subscribe` route health fails.

## 2026-05-30 - No implementation during planning

Context

The user requested a plan ready to implement, and explicitly said do not
implement yet.

Options

- Start coding after the plan looks coherent.
- Stop at a decision-complete implementation plan and external consult approval.

Decision

Do not implement. This document is the deliverable until the user explicitly
requests code changes.

Consequences

ArcStep readiness and fresh consult approval are planning gates, not permission
to change Swift or relay source.

Follow-ups

When implementation is requested, start with Phase 1.

## 2026-05-30 - Composer consult repairs folded into plan

Context

The first Composer 2.5 Fast consult returned `pass-with-notes` and said the
plan was converged but not yet "extremely well specified."

Options

- Treat `pass-with-notes` as enough.
- Fold the notes into the canonical plan and rerun the consult.

Decision

Fold the notes in. Added wire shapes, route-status transition rules, explicit
endpoint dispositions for `/healthz`, `/metricsz`, and `/debugz/sessions`,
`scripts/dock-relay-probe.mjs` disposition, ThreadDetail/Archive call-site rows,
and one chosen app diagnostics UI owner.

Consequences

The plan is more implementation-ready and has fewer places where an implementer
could create a parallel diagnostic path.

Follow-ups

Rerun Composer 2.5 Fast and require a pass that agrees the plan is extremely
well specified and ready to implement.

<!-- arch_skill:block:consistency_pass:start -->
- Scope consistency: TL;DR, Section 0, Section 5, Section 6, and Section 7 all
  describe one single-user, multi-host observability spine. No section requires
  a separate diagnostics auth system, remote telemetry sink, or Codex internals
  instrumentation.
- Owner-path consistency: Section 5 and Section 6 agree on the chosen owners:
  `scripts/dock-relay-observability-contract.mjs`,
  `scripts/dock-relay-observability.mjs`,
  `CodexDock/Diagnostics/ObservabilityContract.swift`, and
  `CodexDock/Diagnostics/ClientObservabilityStore.swift`.
- Phase consistency: every required owner, call site, bundle surface, route
  family, and docs/runbook update appears in exactly one Section 7 phase. The
  phase plan is the only execution checklist.
- Compatibility consistency: existing app-facing route names and normal route
  result shapes are preserved. Trace metadata is additive on the client-to-relay
  path and stripped before upstream Codex calls.
- Verification consistency: Section 8 uses existing `rtk` Swift, Node,
  simulator, and device commands where possible; no doc-grep, absence-check, or
  bespoke verification bureaucracy is required.
- Composer repair consistency: the plan now contains field-level wire shapes,
  explicit route-status transition rules, dispositions for `/healthz`,
  `/metricsz`, `/debugz/sessions`, and `scripts/dock-relay-probe.mjs`, and a
  single chosen app diagnostics sheet owner.
- Overbuild check: the plan explicitly rejects remote telemetry, OpenTelemetry,
  product hardening, a diagnostics-auth subsystem, automatic mutating probes,
  and code generation. The remaining new files are the minimum owner paths
  needed to converge diagnostics onto one model.
- Decision-complete: yes
- Unresolved decisions: none
- Decision: proceed to implement? yes
- Note: "proceed to implement" is ArcStep readiness only. The user explicitly
  requested no implementation in this goal, so code work still requires a later
  implementation request.
<!-- arch_skill:block:consistency_pass:end -->
