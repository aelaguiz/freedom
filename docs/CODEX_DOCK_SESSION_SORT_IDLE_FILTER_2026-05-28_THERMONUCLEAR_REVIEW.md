# Codex Dock - Session Sort And Idle Filter - Thermonuclear Review

Plan: `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md`
Worklog: `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28_WORKLOG.md`
Review time: 2026-05-28T22:11:59Z

## Verdict

Approved.

No blocking correctness, stale-ordering, concurrency/state, accessibility, or
test-coverage defect remains for the implemented Phase 1/2 scope.

## Findings

### Resolved - Idle accessibility value reported stale state

Finding:

- The first implementation used a custom `ToggleStyle`. After tapping `Idle`,
  Mobile MCP saw the visual checkbox and tab counts change, but still reported
  the accessibility value as `0`.

Resolution:

- Replaced the custom `ToggleStyle` with a direct checkbox button in
  `CodexDock/Features/Dock/DockView.swift`.
- The control now exposes:
  - visible label: `Idle`
  - accessibility label: `Show idle threads`
  - accessibility value: `Off` / `On`
  - selected trait when enabled

Proof:

- Fresh launch: Mobile MCP reported `Show idle threads` value `Off`.
- After tapping: Mobile MCP reported `Show idle threads` value `On`.
- Counts changed from `All 89`, `Running 2`, `Agents 92` to `All 100`,
  `Running 13`, `Agents 109`.

### Resolved - Selected-tab projection reorder coverage gap

Finding:

- Initial tests covered search, Idle, and refreshed snapshot date changes, but
  did not directly prove selected-tab changes reorder Branch sections from the
  current visible row set.

Resolution:

- Added `testBranchProjectionReordersAfterSelectedTabChanges` to
  `CodexDockTests/DockStoreTestsProjection.swift`.

Proof:

- `rtk swift test --filter DockStoreTests` passed with 27 tests.

### Resolved - Search field coverage gap

Finding:

- Initial projection tests covered app-local label, host display name, and
  thread id, but not every documented search field.

Resolution:

- Extended `testProjectionSearchMatchesLabelHostAndThreadID` to cover host id,
  branch, status label, and summary in addition to label, host display name,
  and thread id.

Proof:

- `rtk swift test --filter DockStoreTests` passed with 27 tests.

## Code-Quality Assessment

- Projection logic is pure and isolated in
  `CodexDock/State/DockSessionProjection.swift`.
- `DockView` stores only user options: selected tab, search text, sort mode,
  and Idle visibility.
- `DockView` derives visible tabs and rows from the current `DockSnapshot` plus
  current `DockSessionProjectionOptions`; it does not cache projected rows,
  projected sections, or sort order in separate UI state.
- Branch and Newest order use the same recency comparator and deterministic
  tie-breakers.
- Raw snapshot helpers remain compatibility surfaces; Dock UI no longer uses
  them for visible row projection.
- No server, relay, DTO, archive, transport, secret, or app-server behavior was
  changed for this plan.

## Verification Reviewed

- `rtk swift test --filter DockStoreTests`
  - Passed, 27 tests, 0 failures.
- `rtk swift test --filter DockStoreScopeTests`
  - Passed, 7 tests, 0 failures.
- `rtk xcodegen generate --spec project.yml`
  - Passed.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - Failed only because no exact simulator named `iPhone 17` exists.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`
  - Passed on iOS 26.5 simulator `feat_anim_1 - iPhone 17`.
- `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`
  - Passed.
- Mobile MCP simulator proof covered default `Idle` off, `Idle` on, `Search`,
  `Agents`, `Newest`, normal iPhone one-line controls, and large Dynamic Type
  fallback.
