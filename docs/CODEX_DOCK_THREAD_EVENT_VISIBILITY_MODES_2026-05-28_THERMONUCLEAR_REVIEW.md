# Thread Event Visibility Modes Thermonuclear Review

Date: 2026-05-28

## Verdict

Approved after one structural fix.

## Finding Fixed

- `ThreadEventDisplayOrder.naturalFlow(_:)` superseded the old newest-first timeline order and uses stable group/item/event keys instead of treating array offset as semantic order. That keeps the visibility projection stable when `SessionDetailView` receives an already display-ordered snapshot and then asks `ThreadEventVisibilityMode.visibleEvents(from:)` to sort the projected rows again.
  - Fix: `ThreadEventDisplayOrder` now keeps thread detail rows in natural conversation flow and falls back to stable group/item/event keys.
  - Regression test: `ThreadEventNormalizerTests.testVisibilityProjectionIsStableWhenInputWasAlreadyDisplayOrdered`.

## Structural Review

- Model ownership is correct. `ThreadEventVisibilityCategory`, `ThreadEventVisibilityMode.includes(_:)`, and `ThreadEventVisibilityMode.visibleEvents(from:)` live at the event model boundary, not as ad hoc SwiftUI filtering.
- Store ownership is preserved. `ThreadDetailStore.publishLoaded()` still publishes one complete event stream and does not know the selected UI mode.
- UI ownership is local and bounded. `SessionDetailView` owns only local presentation state, header control labels, and the filtered projection call.
- Request-card independence is preserved. `RequestCardsView(store:)` remains outside `EventTimelineView` and outside the visibility filter.
- The implementation does not add relay, app-server, DTO, secret, or project-wiring changes for this feature.
- No touched file crossed the 1,000-line threshold because of this implementation:
  - `CodexDock/Models/ThreadEvent.swift`: 662 lines.
  - `CodexDock/Features/Session/SessionDetailView.swift`: 452 lines.
  - `CodexDockTests/ThreadEventNormalizerTests.swift`: 489 lines after the final regression test.
  - `CodexDockTests/ThreadDetailStoreTests.swift` was already over 1,000 lines before this work; this implementation only added a focused request-event category assertion there.

## Checks

- `rtk swift test --filter ThreadEventNormalizerTests`
  - Final result: passed, 11 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Final result: passed, 51 tests, 0 failures.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Final result: passed; app built, installed, and launched.

## Manual UI Evidence

- Final installed-app check on simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` confirmed:
  - `Timeline visibility: Messages` appears by default.
  - `Timeline visibility: Everything` is reachable and shows tooling/debug rows.
  - `Timeline visibility: Messages and Thinking` is reachable and shows thinking rows with messages.
  - Header/status/thread-id text does not overlap at the tested iPhone width.
- Final screenshots:
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-messages.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-everything.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-thinking.png`
