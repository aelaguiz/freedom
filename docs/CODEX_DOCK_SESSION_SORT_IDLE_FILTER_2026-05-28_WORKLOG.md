# Codex Dock - Session Sort And Idle Filter - Worklog

Plan: `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md`

## 2026-05-28T22:11:59Z - Implementation Complete

Implemented the Dock session projection and controls required by Phase 1 and
Phase 2.

Code changes:

- Added `CodexDock/State/DockSessionProjection.swift`.
- Added `DockSessionSortMode`, `DockSessionProjectionOptions`, and
  `DockSessionProjection`.
- Added `DockSnapshot.project(options:)` as the single Dock-visible projection
  path for selected tab, search, sort, and Idle visibility.
- Branch mode now keeps branch/host sections but orders sections by the newest
  visible row and orders rows by newest activity.
- Newest mode renders a single flat `Newest` section ordered by newest
  activity.
- Idle rows are hidden by default and become visible only when `Idle` is on.
- Projected tab counts use search plus Idle visibility, not raw snapshot
  counts.
- `DockView` now renders `snapshot.project(options:)` instead of caching or
  separately filtering projected rows.
- `DockView` now shows one normal-width controls row with Search, `Branch` /
  `Newest`, and `Idle`, with a stacked fallback for large Dynamic Type.
- `Idle` is a visible square checkbox button with accessibility label
  `Show idle threads`, value `Off`/`On`, and selected trait when enabled.

Test changes:

- Added `CodexDockTests/DockStoreTestsProjection.swift`.
- Added projection tests for Branch row/section recency, search-driven reorder,
  selected-tab-driven reorder, Idle-driven reorder, refreshed snapshot dates,
  Newest flat sort, projected counts, and expanded search fields.
- Extended `CodexDockTests/DockStoreScopeTests.swift` so projected counts prove
  Idle-hidden and Idle-visible tab counts.

Docs updated:

- `README.md`
- `docs/CODEX_DOCK_THREAD_STATES_2026-05-28.md`
- `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`
- `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md`

Verification:

- `rtk swift test --filter DockStoreTests`
  - Result: passed, 27 tests, 0 failures.
- `rtk swift test --filter DockStoreScopeTests`
  - Result: passed, 7 tests, 0 failures.
- `rtk xcodegen generate --spec project.yml`
  - Result: passed; regenerated `CodexDock.xcodeproj`.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - Result: failed because no simulator named exactly `iPhone 17` exists.
  - Exact blocker: `Unable to find a device matching the provided destination specifier: { platform:iOS Simulator, OS:latest, name:iPhone 17 }`.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`
  - Result: passed on iOS 26.5 simulator `feat_anim_1 - iPhone 17`.
- `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`
  - Result: passed; app installed/launched on the iOS 26.5 simulator.
- `rtk make app-server-status`
  - Result: `status: ready`, raw app-server and dock relay active.
- `rtk make dock-relay-status`
  - Result: `status: ready`, raw app-server and dock relay active.

Mobile MCP proof:

- `mobile_list_available_devices`
  - Physical iPhone `00008110-000E04940240A01E` was online.
  - Simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` was online.
- Physical iPhone `mobile_list_elements_on_screen`
  - Result: `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
  - Per `AGENTS.md`, physical retries stopped and simulator proof was used.
- Simulator fresh launch:
  - `Show idle threads` value was `Off`.
  - Counts were `All 89`, `Running 2`, `Limited 87`, `Agents 92`.
  - Search, Branch/Newest, and Idle appeared in one normal-width row.
- Simulator after tapping `Idle`:
  - `Show idle threads` value was `On`.
  - Counts updated to `All 100`, `Running 13`, `Limited 87`, `Agents 109`.
  - Visible rows included Idle rows.
- Simulator after typing `Done`:
  - Search value was `Done`.
  - Counts updated to `All 29`, `Running 7`, `Limited 22`, `Agents 1`.
- Simulator after tapping `Agents`:
  - `Agents 1` was selected.
  - Search and Idle state stayed applied.
- Simulator after tapping `Newest`:
  - `Newest` was selected.
  - Visible section title became `Newest`.
- Large Dynamic Type check:
  - `rtk xcrun simctl ui BAD95C8E-3E57-4818-9B90-E4ED22593B4B content_size accessibility-extra-large`
  - Result: controls wrapped into the responsive fallback without clipping.
  - Restored with `rtk xcrun simctl ui BAD95C8E-3E57-4818-9B90-E4ED22593B4B content_size large`.

Screenshots:

- `/tmp/codex-client/session-sort-idle/dock-controls-default.png`
- `/tmp/codex-client/session-sort-idle/dock-controls-accessibility-extra-large.png`
- `/tmp/codex-client/session-sort-idle/dock-controls-filtered-newest-idle-on.png`
