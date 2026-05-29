# Codex Dock Thread Event Visibility Modes Worklog

## 2026-05-28

### Readiness

- Stage gate passed with `READY next=implement-loop`:
  - `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_THREAD_EVENT_VISIBILITY_MODES_2026-05-28.md`
- Re-read current task files after repo drift:
  - `CodexDock/Models/ThreadEvent.swift`
  - `CodexDock/Features/Session/SessionDetailView.swift`
  - `CodexDock/State/ThreadDetailStore.swift`
  - `CodexDockTests/ThreadEventNormalizerTests.swift`
  - `CodexDockTests/ThreadDetailStoreTests.swift`
  - `CodexDockTests/ThreadDetailStoreTestSupport.swift`

### Implementation

- Added `ThreadEventVisibilityCategory` and `ThreadEventVisibilityMode` in `CodexDock/Models/ThreadEvent.swift`.
- Added `ThreadEvent.visibilityCategory` with a defensive `.unknown` initializer default.
- Classified stored items, live deltas, live `item/started` / `item/completed` embedded items, server requests, system rows, and malformed/unknown shapes through the model-owned event normalization path.
- Added `ThreadEventVisibilityMode.visibleEvents(from:)`, which filters first and then calls `ThreadEventDisplayOrder.naturalFlow(_:)`; this prevents hidden rows with newer timestamps from moving visible Messages-mode rows while keeping thread detail in normal conversation order.
- Kept `ThreadDetailStore.publishLoaded()` publishing the complete event stream through `ThreadEventDisplayOrder.naturalFlow(_:)`.
- Added local `@State private var visibilityMode: ThreadEventVisibilityMode = .messages` in `SessionDetailView`.
- Kept `RequestCardsView(store:)` outside the timeline filter.
- Added a compact header control that cycles `Messages -> Thinking -> Everything -> Messages`; the accessibility labels remain explicit as `Timeline visibility: Messages`, `Timeline visibility: Messages and Thinking`, and `Timeline visibility: Everything`.
- Updated the timeline empty state so an empty selected mode is distinct from a genuinely empty transcript.

### Verification

- `rtk swift test --filter ThreadEventNormalizerTests`
  - Result: passed.
  - Coverage after initial implementation: 10 tests, 0 failures.
- Thermonuclear review found one structural ordering issue: offset fallback ordering in `ThreadEventDisplayOrder` was not stable when sorting an already display-ordered snapshot again.
  - Fix: fallback ordering now uses stable group/item/event keys.
  - Regression: `testVisibilityProjectionIsStableWhenInputWasAlreadyDisplayOrdered`.
- `rtk swift test --filter ThreadEventNormalizerTests`
  - Final result: passed.
  - Coverage after the review fix: 11 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Result after initial implementation: passed.
  - Coverage: 51 tests, 0 failures. The filter also matched `ThreadDetailStoreTestsLifecycle`.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Final result after the review fix: passed.
  - Coverage: 51 tests, 0 failures. The filter also matched `ThreadDetailStoreTestsLifecycle`.
- `rtk make app SIM='iPhone 17'`
  - Result: failed before build because `iPhone 17` matched multiple simulators:
    - `feat_anim_1 - iPhone 17` / `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` / Booted
    - `feat_remount-disposal-lifecycle-post-audit - iPhone 17` / `DEF1631B-7125-43C6-BFA3-4423BF103C91` / Shutdown
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Initial result: passed; app built, installed, and launched on the booted `iPhone 17` simulator.
  - Final result after the review fix: passed; app built, installed, and launched on the same simulator.
  - Service proof in the app run showed relay readiness at `192.168.50.117:4510`.

### Manual UI Check

- Used mobile automation on simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Opened a real thread from the Dock list.
- Verified the default header control state:
  - `Timeline visibility: Messages`
  - Visible label: `Messages`
  - Message rows visible; reasoning row hidden.
- Cycled to Everything.
  - Accessibility label: `Timeline visibility: Everything`
  - Visible label: `Everything`
  - Reasoning rows visible.
- Cycled to Messages + Thinking.
  - Accessibility label: `Timeline visibility: Messages and Thinking`
  - Visible label: `Thinking`
  - Reasoning rows visible with message rows.
- Confirmed the header/status/thread-id area did not overlap at the tested iPhone width.
- Screenshots:
  - `/tmp/codex-client/20260528T191500Z/thread-detail-messages.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-everything.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-thinking.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-messages.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-everything.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-thinking.png`

### Audit Result

- Implementation audit verdict: code complete.
- Thermonuclear review verdict: approved after fixing the stable projection ordering issue.

## 2026-05-29 Follow-Up

- User observation: the latest user message was pinned at the top of thread
  detail instead of sitting naturally in the message flow.
- Fix: thread detail display ordering now uses `ThreadEventDisplayOrder.naturalFlow(_:)`
  instead of newest-first ordering.
- Verification:
  - `rtk swift test --filter ThreadEventNormalizerTests`: 11 tests passed.
  - `rtk swift test --filter ThreadDetailStoreTests`: 51 tests passed.
  - `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
