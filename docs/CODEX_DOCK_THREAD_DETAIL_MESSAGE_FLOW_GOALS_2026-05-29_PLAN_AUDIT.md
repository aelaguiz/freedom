# Plan Audit - Thread Detail Message Flow

Plan artifact: `docs/CODEX_DOCK_THREAD_DETAIL_MESSAGE_FLOW_GOALS_2026-05-29.md`
Mode: `implementation-audit`
Last updated: 2026-05-29

## 2026-05-29 Implementation Audit

VERDICT: approve-with-notes
Confidence: high
Scope reviewed: full implementation through Phases 1-3
Baseline reviewed: current worktree
Test/CI context accepted: Swift focused tests passed, focused relay diagnostics passed, simulator app/app-test passed, full `rtk npm run test:relay` blocked by repeated phase5 no-output stall in the local multi-app-server environment.

## Blocking Findings

None.

## Non-Blocking Findings

1. Full relay suite evidence is environment-blocked, not code-blocked.
   - Problem: The plan still names `rtk npm run test:relay` as the ideal relay proof, but that exact command repeatedly stalled in `scripts/dock-relay-phase5.test.mjs` while other live Codex app-server processes were discoverable on loopback.
   - Why it matters: A later reader should not confuse this with missing implementation work or a hidden relay regression.
   - Evidence:
     - Plan implementation status records the repeated no-output stall and the focused relay passes.
     - `scripts/dock-relay-thread-data.mjs` discovers loopback `codex app-server --listen ws://127.0.0.1:<port>` processes through `ps`.
   - Required repair: None for this implementation. If exact full-suite relay proof is required later, run it in a clean environment without unrelated loopback Codex app-server processes or make the relay test suite isolate live endpoint discovery.
   - Review lens: proof and phase-exit gaps.

## Scope Review

- Claimed scope: remove the 10-message/turn detail cap, show the full thread newest-first, replace visibility modes with one message-type filter, and merge request actions into one visible message card family.
- Code reviewed:
  - `CodexDock/State/ThreadDetailStore.swift`
  - `CodexDock/Models/ThreadEvent.swift`
  - `CodexDock/Features/Session/SessionDetailView.swift`
  - `CodexDock/Features/Session/ThreadMessageListView.swift`
  - `CodexDock/Features/Session/RequestCardView.swift` deletion
  - `CodexDockTests/ThreadDetailStoreTests.swift`
  - `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`
  - `CodexDockTests/ThreadEventNormalizerTests.swift`
  - `CodexDockTests/AppServerClientTests.swift`
  - `README.md`
  - `docs/CODEX_DOCK_THREAD_EVENT_VISIBILITY_MODES_2026-05-28.md`
  - `CodexDock.xcodeproj/project.pbxproj`
- Code blockers: none.
- Test/CI assumptions accepted:
  - Focused Swift tests passed.
  - Focused relay diagnostics passed.
  - Booted iPhone 17 simulator build/launch/test passed by Makefile-owned targets.
  - Full relay suite blocker accepted as an environment/test-isolation blocker, not a code blocker.
- Phase status recommendations:
  - Phase 1: implemented.
  - Phase 2: implemented.
  - Phase 3: implemented, with full relay-suite proof caveat preserved in the plan/worklog.

## Architecture And Elegance

- Canonical owner: `ThreadDetailStore` owns full-thread loading; `ThreadEvent` owns ordering/filter projection primitives; SwiftUI owns only selected filter state and rendering.
- SSOT status: one detail loading path, one ordering helper, one filter model, one visible message card family.
- Duplicate truth or parallel paths: no old `ThreadEventVisibilityMode`, `VisibilityModeButton`, `RequestCardsView`, or `ThreadEventDisplayOrder.naturalFlow(_:)` path remains in active code.
- Simpler code-judo move: already applied during audit prep by moving filter/list/card UI into `ThreadMessageListView.swift` instead of growing `SessionDetailView.swift`.
- Tiny-team maintainability risk: low. The largest touched screen file is now split into a screen shell and a message-list component.

## Deletes, Side Doors, And Drift

- Required deletes satisfied:
  - `RequestCardView.swift` is deleted.
  - Generated Xcode project removes `RequestCardView.swift` and includes `ThreadMessageListView.swift`.
  - Active code and README no longer reference `ThreadEventVisibilityMode`, `VisibilityModeButton`, `RequestCardsView`, `RequestCardView`, `naturalFlow`, or `limit:10`.
- Old paths still live: only in superseded/planning docs as historical context.
- Side doors still callable: no alternate detail cap or alternate visible request-card stack found in active code.
- Drift-prone shared dependencies: `ThreadDetailMessageFilter` and `ThreadEventDisplayOrder.newestFirst(_:)` are centralized in `ThreadEvent.swift`; tests cover the important ordering/filter cases.
- Docs/prompts/examples/instructions drift: README updated; old visibility-mode plan marked superseded.

## Relevant Code Coverage

- Code areas read: store loading/rehydrate/publish, thread event ordering/filtering, detail UI composition, message list/card, request-card action wiring, changed tests, README/docs, generated project diff.
- Relevant code not yet read: none that blocks this audit.
- Native subagents/lenses run: no subagents used because local tool instructions only permit spawning when the user explicitly asks for sub-agents; lenses run locally: plan-code-fit, outcome-realization, requirement-traceability, canonical-owner-and-SSOT, deletion-and-side-door-closure, drift-proof-coupling, caller-invariant-state, elegance-and-code-judo, test-code-review, docs-contract-drift.
- Coverage blockers: none.

## Recommended Next Move

Proceed to the requested thermonuclear code-quality review. Keep the full relay-suite caveat visible in final reporting unless it is later rerun in an isolated environment and passes.
