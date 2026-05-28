---
title: "Codex Dock - iPhone Shell Single-Host Dock - Architecture Plan"
date: 2026-05-27
status: complete
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: new_system
related:
  - ../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - ../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png
---

# TL;DR

- Outcome: Build the first iPhone app shell and render a single-host Dock from
  the real `SessionSummary` pipeline.
- Problem: UI should arrive only after RPC and data are proven.
- Approach: Add SwiftUI app target, root navigation, Dock store/view, and
  single-host loading using Phase 1 and 2 modules.
- Plan: Build app shell, wire one host, render connection/list state, then align
  the Dock to the v2 mockup.
- Non-negotiables: no static production rows, no AIMGR, no final breadth before
  one live Dock works.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-28
Verdict (code): COMPLETE
Manual QA: complete

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- 2026-05-28: Reopened the live-session source after real use showed the Dock
  was connected to the phone-visible history app-server but not to the live
  loopback app-servers that own loaded Codex sessions. Fixed with the
  authenticated Dock relay and kept Phase 3 complete after proof.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Evidence checked
- Stage gate: `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_03_IPHONE_SHELL_SINGLE_HOST_DOCK_2026-05-27.md` returned `READY next=implement-loop`.
- Tooling: installed XcodeGen 2.45.4 with `rtk brew install xcodegen`; this is allowed by the epic-level permission to install needed tools.
- Project generation: `rtk xcodegen generate --spec project.yml` created `CodexDock.xcodeproj` from the checked-in `project.yml`.
- Service runbook: `rtk make services` is the canonical start path. It
  starts/reuses the raw authenticated LAN app-server for history and the
  authenticated Dock relay for live loaded sessions, leaving both running with
  plist/PID/token/log files under `.codex-dock/`.
- SwiftPM proof: `rtk swift test` passed 33 tests with 3 optional live endpoint
  tests skipped when no endpoint env was set.
- iOS build proof: `rtk make app SIM='iPhone 17'` passed on simulator
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` and launched
  `com.aelaguiz.CodexDockApp` against the relay endpoint.
- iOS generated-project test proof: `rtk xcodebuild test -project
  CodexDock.xcodeproj -scheme CodexDockApp -destination
  'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath
  .codex-dock/DerivedData` passed.
- Real host proof: started a real Codex app-server on `Amir-M5` with `rtk codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file <temp-token-file>`.
- Reachability proof: `rtk curl -i --max-time 5 http://192.168.50.117:4500/readyz` returned `HTTP/1.1 200 OK`.
- Real data proof: `rtk env CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4500 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=<temp-token-file> CODEX_DOCK_REAL_HOST_ID=Amir-M5 swift test --filter AppServerClientTests/testPhoneReachableRealHost` passed the phone-reachable handshake and `thread/list` tests.
- App live-host proof: installed and launched `com.aelaguiz.CodexDockApp` on
  the booted `iPhone 17` simulator with
  `SIMCTL_CHILD_CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510`,
  bearer token, and host env. Screenshot
  `/tmp/codex-dock-phase3-relay-recency-refresh.png` showed `Amir-M5`,
  `192.168.50.117`, and 118 real sessions from the relay-backed live loopback
  app-server scan.
- App offline proof: stopped the same real app-server, relaunched the installed app against the same endpoint, and screenshot `/tmp/codex-dock-phase3-offline.png` showed `Amir-M5 · Offline` plus the transport error instead of demo rows.
- Source correction proof: direct relay query against `ws://192.168.50.117:4510`
  returned 50 newest-first rows with `active: 3`, `idle: 21`, and
  `notLoaded: 26`; `thread/loaded/list` returned 29 real loaded IDs from
  discovered loopback Codex app-servers. No mocked rows or invented statuses
  were used.
- Ordering and refresh proof: `DockStore` keeps rows and branch sections
  newest-first with status only as a tie-breaker, and `DockView` auto-refreshes
  every five seconds plus pull-to-refresh.
- Scope check: implementation added app target/project generation, app host
  configuration, `DockStore`, Dock SwiftUI views, store/config tests, and the
  required host-side relay/runbook. No thread detail, multi-host fan-out,
  Archive implementation, Hosts implementation, voice, AIMGR, or production
  static rows were added.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- None for Phase 3.
<!-- arch_skill:block:implementation_audit:end -->

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-27
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-27
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:cad45581c9d7443082c46d4e5e4bc7ce97da905ed097bca41f7ba97452ca01cc",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:7990e70496d2178fab5bf76f6c8ea8a531a86b3f7ca88d0ab503d4e37f817cce",
      "completed_at": "2026-05-28T00:25:39Z",
      "doc_hash_after": "sha256:d5781952b674304d718e1b810409e2a0b619a4325ea95e0122e77cf69ff0e9c1"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:d5781952b674304d718e1b810409e2a0b619a4325ea95e0122e77cf69ff0e9c1",
      "completed_at": "2026-05-28T00:27:30Z",
      "doc_hash_after": "sha256:445051043f33dfb4600a8d28ebd9f36c6bfd7d1ba54479e3291b29831f8b7be3"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:445051043f33dfb4600a8d28ebd9f36c6bfd7d1ba54479e3291b29831f8b7be3",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:8de948347672570c4c391869b01513d9848ff119f122ab2bdc7e664f0bad9184"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:8de948347672570c4c391869b01513d9848ff119f122ab2bdc7e664f0bad9184",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:60826980374fb2c7076f04db62aa2d2419c0bb29357b8fbd665f269d93304bad"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:33Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:60826980374fb2c7076f04db62aa2d2419c0bb29357b8fbd665f269d93304bad",
      "completed_at": "2026-05-28T00:32:11Z",
      "doc_hash_after": "sha256:68cf15b3b61f568eb40c3c41d097eaabe9ac3aac4d818cc3b76a01051167d35d"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

The iPhone app builds, launches, connects to one configured host, calls the
existing thread-list pipeline, and renders real session rows in the Dock.

## 0.2 In scope

- SwiftUI app shell.
- Root tab/navigation shape.
- One configured host in app state.
- Phone-reachable service path that returns real loaded sessions for that host.
- Dock loading/empty/error states.
- Dock normal-state UI anchored to v2 mockup.

## 0.3 Out of scope

- Thread detail.
- Multi-host.
- Archive, Hosts, voice, AIMGR.

## 0.4 Definition of done (acceptance evidence)

- App target builds.
- Dock launches and uses Phase 1/2 runtime modules.
- Real rows appear when the host has sessions, including loaded/running rows
  from the app-server process that owns them.
- More recent threads sort first; status is only a tie-breaker.
- The Dock refreshes itself after launch and still supports manual refresh.
- Offline/error state appears when the host is unavailable.

## 0.5 Key invariants (fix immediately if violated)

- Views read normalized state.
- Preview data stays isolated from production runtime.
- Dock UI does not own protocol calls directly.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Runnable iPhone app.
2. Real data in the first Dock.
3. Calm scan-friendly layout.
4. Future multi-host without rewrite.

## 1.2 Constraints

- The Dock mockup is visual guidance, not a golden asset.
- The app must remain personal/local, no login.

## 1.3 Architectural principles (rules we will enforce)

- Store/view separation.
- Host id exists from the first UI.
- Bottom tabs may exist but only Dock needs real content in this phase.

## 1.4 Known tradeoffs (explicit)

- Some visual polish can wait for final phase.
- Search/filter controls can be visible but minimally functional until later.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Phase 1/2 provide protocol and data seams. No iPhone app shell exists.

## 2.2 What’s broken / missing (concrete)

There is no user-visible way to see sessions on a phone.

## 2.3 Constraints implied by the problem

The first UI should consume real summaries, not invent a separate data path.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- SwiftUI app shell and observable state patterns — adopt standard app/view/store
  structure rather than a custom UI framework.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` — Dock normal state,
    density, host/branch grouping, status/label separation.
  - `../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png` — visual anchor
    for the single-host Dock surface.
- Canonical path / owner to reuse:
- Phase 1 client and Phase 2 `SessionSummary`; new `DockStore` projects UI
  state.
- `scripts/dock-relay.mjs` is the host-side bridge required to expose live
  loopback-loaded sessions to the phone path without inventing unsupported Codex
  daemon behavior.
- Adjacent surfaces tied to the same contract family:
  - Phase 6 reuses Dock state for multi-host.
  - Phase 4 navigation depends on stable host/thread row identity.
- Compatibility posture:
  - Preserve Phase 1/2 APIs; UI consumes normalized summaries only.
- Existing patterns to reuse:
  - Standard SwiftUI app target conventions.
- Prompt surfaces / agent contract to reuse:
  - Not agent-backed.
- Native model or agent capabilities to lean on:
  - None.
- Existing grounding / tool / file exposure:
  - v2 Dock mockup and UX spec.
- Duplicate or drifting paths relevant to this change:
  - Avoid production static rows; preview data only in previews.
- Capability-first opportunities before new tooling:
  - Use normal SwiftUI previews/manual checks; no visual-golden harness.
- Behavior-preservation signals already available:
  - Phase 1/2 protocol/data tests.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- Protocol/data modules are planned; no iOS app shell or Dock view exists.
## Control paths (runtime)
- Data can be proven by diagnostics, not yet by app UI.
## Object model + key abstractions
- `SessionSummary` exists from Phase 2; no `DockStore` or SwiftUI view.
## Observability + failure behavior today
- No app-level loading/empty/error UI exists.
## UI surfaces (ASCII mockups, if UI work)
- Dock normal v2 mockup is the anchor.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `project.yml` as the source of truth for generating `CodexDock.xcodeproj`.
- `CodexDockApp/CodexDockApp.swift`.
- `CodexDock/State/DockStore.swift`.
- `CodexDock/Features/Dock/DockView.swift`.
- `CodexDockTests/DockStoreTests.swift`.
- `scripts/dock-relay.mjs`.
- `Makefile` service targets.
- `package.json` / `package-lock.json` for the relay's `ws` dependency.
## Control paths (future)
1. App launches.
2. `rtk make services` keeps the raw history app-server and relay running.
3. DockStore loads one host through Phase 1/2 modules pointed at the relay.
4. DockView renders connection state and real summaries, then periodically
   refreshes.
## Object model + abstractions (future)
- `DockStore`, `DockSection`, `DockRowViewModel`.
## Invariants and boundaries
- Views consume summaries/view models only.
## UI surfaces (ASCII mockups, if UI work)
- Direct anchor: [Dock normal](../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png).
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| App | `CodexDockApp.swift` | app entry | Missing | Create app root | Runnable UI | app entry | Build |
| State | `DockStore.swift` | `load()` | Missing | Load one host summaries | UI data owner | observable state | Unit |
| State | `DockStore.swift` | `refresh()` | Missing | Refresh without fake rows or manual reload only | Auto-updating Dock | observable state | Unit/manual |
| UI | `DockView.swift` | Dock | Missing | Render host/filter/search/rows and schedule refresh | First product screen | SwiftUI view | Manual/build |
| Relay | `scripts/dock-relay.mjs` | relay endpoint | Missing | Merge real loaded loopback sessions over history | Phone path needs live state | JSON-RPC relay | Node check/live query |
| Ops | `Makefile`, `README.md` | service start | Raw app-server only | Start/reuse raw app-server plus relay | Idempotent app launch | `rtk make services` | live status |
| Tests | `DockStoreTests.swift` | store tests | Missing | Prove load/error states | Protect UI state | test transport | Unit |
## Migration notes
* Canonical owner path / shared code path: `DockStore` over Phase 1/2 modules;
  host-side live-state fan-in belongs to `scripts/dock-relay.mjs`.
* Deprecated APIs (if any): none.
* Delete list: production static rows if introduced; app launch pointing at the
  raw `:4500` history-only endpoint.
* Adjacent surfaces tied to the same contract family: Phase 4 row navigation.
* Compatibility posture / cutover plan: preserve Phase 1/2 APIs; cleanly cut
  the app endpoint over to the relay because the raw app-server cannot observe
  other processes' loaded thread state.
* Capability-replacing harnesses to delete or justify: no visual-golden tests.
* Live docs/comments/instructions to update or delete: document build command if needed.
* Behavior-preservation signals for refactors: protocol/data tests stay green.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| UI state | `DockStore` | normalized app state | Prevent views calling protocol directly | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: this phase makes one live Dock usable; no detail screen, archive,
  voice, AIMGR, or multi-host fan-out enters yet.
- Adjacent-surface check: Dock rows keep stable host/thread identity for Phase 4
  navigation and Phase 6 widening.
- Failure posture: loading, empty, offline, and protocol error states render in
  the Dock instead of crashing or showing demo rows.
- Depth-first proof: the app shell is complete only when it builds and renders
  real summaries from the Phase 2 pipeline.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: runnable SwiftUI shell

Work: Create the app target/root and the minimum navigation container needed for
Dock-first operation.

Checklist (must all be done):
- App builds and launches in simulator or local device.
- Root navigation exposes Dock as the primary first screen.
- Preview/demo data stays isolated from production runtime.

Exit criteria (all required):
- Build command succeeds.
- Launch shows a real Dock container, not a marketing or placeholder page.

## Implementation slice 2: single-host Dock store

Work: Add `DockStore` that uses Phase 1/2 modules to load one configured host.

Checklist (must all be done):
- Store loads summaries from the configured host.
- Store exposes loading, empty, offline, and error states.
- Store tests use a fake client/test transport rather than static production rows.
- Refresh updates the loaded snapshot without relying on user pull-to-refresh.

Exit criteria (all required):
- A real or fake host can drive rows through the store.
- Protocol calls remain outside SwiftUI views.
- Newest rows and newest branch sections appear first.

## Implementation slice 3: Dock UI aligned to v2 normal mockup

Work: Render the scan-friendly single-host Dock surface.

Checklist (must all be done):
- Rows show host/cwd or repo, branch, status, last activity, and short summary
  where available.
- Search/filter controls can be present at MVP level but must not imply
  unsupported multi-host breadth.
- Visual density follows [Dock normal](../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png).

Exit criteria (all required):
- Real session rows render in the Dock.
- Offline host state does not show demo rows as if connected.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

<!-- arch_skill:block:consistency_pass:start -->
# Consistency Pass

## Decision inventory
- Decision-complete:
  - yes
- Unresolved decisions:
  - none
- Decision: proceed to implement? yes

## Verification strategy
- Build and launch the iPhone app target.
- Run `DockStore` tests for loading, empty, offline, and error states.
- Run `DockStore` tests for newest-first ordering and refresh.
- Run `node --check scripts/dock-relay.mjs`.
- Query `ws://192.168.50.117:4510` and confirm real loaded rows come from
  discovered loopback app-servers.
- Manual/screenshot check against [Dock normal](../../mockups/codex-dock-2026-05-27-v2/01-dock-normal.png).
- Verify production Dock rows come from `SessionSummary`, not static demo data.

## Cold-read consistency checks
- UI starts only after protocol and data are available.
- This phase stays single-host; multi-host and detail are assigned later.
- Row identity is stable enough for Phase 4 navigation.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Local simulator/device development.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Run the app against one configured app-server host.

Required runtime env:

- `CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`: phone/simulator-reachable `ws://`
  or `wss://` endpoint.
- `CODEX_DOCK_APP_SERVER_BEARER_TOKEN` or
  `CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE`: websocket auth token.
- `CODEX_DOCK_REAL_HOST_ID`: stable host id, currently `Amir-M5` for this
  machine.
- `CODEX_DOCK_REAL_HOST_NAME`: display name, currently `Amir-M5`.

Phase 3 simulator target: `iPhone 17`
`DEF1631B-7125-43C6-BFA3-4423BF103C91`.

Tooling note: Phase 3 uses XcodeGen. If missing, install it with
`rtk brew install xcodegen`; this was done during implementation.

Canonical service start:

- `rtk make services`: start or reuse the authenticated raw LAN app-server and
  authenticated Dock relay, leaving both running under launchd.
- `rtk make app-server-status`: check raw app-server PID and `/readyz` without
  restarting.
- `rtk make dock-relay-status`: check relay PID and `/readyz` without
  restarting.
- `rtk make app-server-env`: print environment variables for Swift tests and
  app launch.
- `rtk make app-server-stop` and `rtk make dock-relay-stop`: stop services only
  when intentionally done with them.

# 10) Decision Log (append-only)

## 2026-05-27 - UI waits for protocol and data

Context
: The revised epic makes JSON-RPC and `thread/list` earlier proof gates.

Options
: Keep UI first, or make UI Phase 3 after data.

Decision
: UI starts only after protocol and session summary data are planned.

Consequences
: Dock implementation can be thinner and more truthful.

## 2026-05-28 - Phase 3 implementation completed

Context
: Phase 3 needed the first real iPhone app shell and a single-host Dock backed
  by live `SessionSummary` data.

Decision
: Use XcodeGen for the generated Xcode project and keep `project.yml` checked in
  as the editable source of truth. Configure the app at launch from environment
  variables rather than adding unsupported Codex daemon behavior.

Consequences
: The app can be built, installed, and launched on `iPhone 17`; production rows
  come from the real app-server pipeline, while preview rows remain isolated to
  SwiftUI previews.

## 2026-05-28 - Phone-visible history server was not enough for live Dock state

Context
: Real use showed the standalone phone-visible app-server returned stored
  `notLoaded` history while active Codex sessions lived in private loopback
  app-server processes.

Decision
: Add an authenticated host-side Dock relay, keep the raw app-server as the
  history source, and make `rtk make services` / `rtk make app SIM=...` point
  the app at the relay.

Consequences
: The iPhone path now sees real loaded/running rows from `Amir-M5` without
  unsupported Codex daemon configuration, fake rows, or mocked statuses.

## 2026-05-28 - Dock ordering and refresh policy

Context
: The Dock must stay useful while sessions change, and the user explicitly
  required newer threads first.

Decision
: Sort rows and sections by last activity descending first, using status only as
  a tie-breaker, and auto-refresh the Dock every five seconds while the view is
  active.

Consequences
: `All` stays newest-first, filters still work from the same loaded snapshot,
  and the user does not need to manually pull to refresh live state.
