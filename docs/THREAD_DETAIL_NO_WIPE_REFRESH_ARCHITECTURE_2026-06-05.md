# Thread Detail No-Wipe Refresh Architecture

Status: Ready for plan audit
Date: 2026-06-05
Scope: Swift Thread Detail reopen behavior, retained detail state, visible updating refresh, and simulator proof.

## North Star

When a user reopens a thread they already opened in the current app session,
Thread Detail must keep the existing message list on screen immediately. It
must not fall back to the blank `Loading` screen. The header should show
`Updating` while the app asks the relay for the latest canonical detail
snapshot, then the existing rows should update in place when the server data
arrives.

This is a Swift client architecture change. The relay already has the canonical
route the app needs: `thread/detail/resync`.

## User-Visible Done State

- First-time Thread Detail open can still show the existing `Loading` state.
- Reopening a thread that has a retained loaded snapshot must never show
  `codexdock.session.state.loading`.
- Reopening a retained detail must show the previous message rows immediately.
- While the retained detail refresh is in flight, the existing live/status pill
  must show `Updating`.
- When the relay returns the new `thread/detail/resync` snapshot, the detail
  rows update in place and the pill returns to `Live`, `Stale`, or `Closed`
  according to relay freshness.
- Draft text, message filter, pending outbound message state, request-card
  local input, request-card local status, and file-change review local state
  are not lost by a back-and-reopen cycle.
- The same retained-detail behavior is used from Dock and Archive entrypoints.

## Current Failure

Current app behavior collapses two different concepts into one state:

- `ThreadDetailStoreState.loading` means "no content yet."
- Reopening a previously loaded detail also routes through `loading`.

That makes a reopen look like a full wipe even though the correct operation is
"keep what we have and update it."

Current code anchors:

- `CodexDock/Features/Session/SessionDetailView.swift`
  - `.task { await store.load() }`
  - `.onDisappear { store.close() }`
  - `loading` renders the blank progress view.
- `CodexDock/State/ThreadDetailStore.swift`
  - `load()` sets `state = .loading(header)` before subscribing.
  - `close()` disconnects the session and closes the reconciler.
  - A later open creates a new store through Dock or Archive and starts over.
- `CodexDock/Features/Dock/DockView.swift`
  - `openDetail(row:)` always creates a fresh `ThreadDetailStore`.
  - Navigation pop clears `selectedDetailStore`.
- `CodexDock/Features/Archive/ArchiveView.swift`
  - Same fresh-store pattern as Dock.
- `CodexDock/Projection/StreamReconciler.swift`
  - Already supports the correct no-wipe operation: `manualRefresh()` turns
    current rows into `catchingUp` while `resync()` fetches a new snapshot.

## Target Architecture

### 1. One Owner For Detail Content

`ThreadDetailStore` remains the source of truth for detail content, local
composer state, local request-card state, file-change review state, connection
state, and projection reconciliation.

No new row cache, DTO cache, view-model cache, or relay-side cache is allowed.
The retained content is the existing `ThreadDetailStore` state.

### 2. Separate Content Availability From Refresh Activity

The state model must keep these concepts separate:

- Content availability: no detail rows yet, loaded rows exist, failed to load.
- Refresh activity: initial loading, updating existing content, reconnecting,
  stale, live, closed.

Implementation shape:

- Keep `ThreadDetailStoreState.loading` only for first-load/no-content cases.
- Add a refresh-display state that can represent `Updating` while loaded rows
  remain visible.
- The visible header uses the existing live/status pill to show `Updating`.
- `Updating` must not force the view through `.loading`.

Expected mapping from `StreamReconcilerFreshnessState`:

- `.connecting` and `.subscribing` before first content: `Connecting`.
- `.catchingUp(.manualRefresh)`: `Updating`.
- `.catchingUp(.foregroundResume)`: `Updating`.
- `.catchingUp(.commandCompletedInvalidation)`: `Updating`.
- `.catchingUp(.relayResyncRequired)`, `.catchingUp(.sequenceGap)`,
  `.catchingUp(.bufferOverflow)`, `.catchingUp(.streamContract)`: `Updating`
  unless the transport itself is reconnecting.
- Transport reconnect still shows `Reconnecting`.
- `.live`, `.stale`, `.offline`, `.failed`, and `.closed` keep their current
  meanings.

### 3. Retain Detail Stores By Thread Identity

Dock and Archive should not create a new `ThreadDetailStore` every time the
same row is opened. They should use a small shared helper:

`ThreadDetailStoreCache`

Responsibilities:

- Key entries by `HostScopedThreadID`.
- Return the retained store when a row is reopened.
- Update the retained store with the latest Dock/Archive row via
  `observeDockRowUpdate(_:)`.
- Create a store through the existing factory path when no retained store
  exists.
- Keep a bounded least-recently-used set of stores.
- Read its production capacity from
  `CodexDockConstants.ThreadDetail.retainedStoreCapacity`.
- Close evicted stores through `ThreadDetailStore.close()`.
- Close all stores when the owning screen deinitializes.

This helper is shared by Dock and Archive. The helper owns retention policy;
`DockView` and `ArchiveView` only ask it for a store.

### 4. View Disappear Means Detach, Not Destroy

`SessionDetailView.onDisappear` must not call `ThreadDetailStore.close()` for
normal navigation pop. That is the direct wipe cause.

Replace it with a lighter detach operation:

`ThreadDetailStore.detachView()`

Responsibilities:

- Stop screen rendering work that only matters while the view is visible.
- Cancel active voice capture/dictation safely if the user leaves mid-capture.
- Keep canonical detail events, pending outbound messages, request-card local
  state, file-change review state, composer draft, session, and reconciler.
- Do not close the projection stream or delete rows.

Full close remains available for cache eviction and owning-screen teardown.

### 5. Reopen Means Publish Existing Rows Then Resync

`ThreadDetailStore.load()` becomes "ensure visible detail session," not
"always first load."

Required behavior:

- If no successful snapshot exists yet, use current first-load flow:
  `loading -> thread/detail/subscribe -> loaded`.
- If loaded rows already exist:
  - restart the screen render stream if needed,
  - publish the current loaded snapshot immediately,
  - set refresh display to `Updating`,
  - call `StreamReconciler.manualRefresh()`,
  - apply the returned `thread/detail/resync` snapshot in place.
- If the previous first load failed before any rows existed, a later `load()`
  may retry through the first-load path.
- If a retained refresh is already in flight, another `load()` must not start a
  duplicate refresh. It can republish the current loaded snapshot and rely on
  the existing `StreamReconciler` coalescing.

This keeps caller behavior simple: SwiftUI still calls `await store.load()`
from `.task`, but the store chooses initial load vs retained update internally.

### 6. No Relay Protocol Change

The production protocol stays:

- `thread/detail/subscribe` for first detail open.
- `thread/detail/update` for live updates.
- `thread/detail/resync` for refreshing already-loaded detail.

No phone-side raw `thread/read`, no local mock route, no second detail data
path, and no new relay DTO are needed.

### 7. Stable Automation Contract

Add stable UI proof visibility:

- Existing detail root accessibility value must keep reporting `loaded` while
  reopening retained detail.
- Existing header accessibility value must expose `live=Updating` while the
  retained refresh is in flight.
- Existing message-list accessibility value must keep exposing the previous
  projection IDs during the update.
- `codexdock.session.state.loading` must be absent during retained reopen.

No visible explanatory text is added to the app. The only user-visible change
is the live/status pill saying `Updating` while existing content remains on
screen.

## Implementation Plan

### Phase 1 - Store Semantics

Files:

- `CodexDock/State/ThreadDetailStore.swift`
- New `CodexDock/ThreadDetail/ThreadDetailStoreModels.swift` if needed to keep
  `ThreadDetailStore.swift` below 1,000 lines.
- `CodexDock/ThreadDetail/ThreadDetailRenderModels.swift`
- `CodexDock/Features/Session/SessionDetailView.swift`
- `CodexDock/Automation/AutomationID.swift` only if a new stable ID is needed.

Work:

- Keep `ThreadDetailStore.swift` under 1,000 lines. If the retained-refresh
  code would cross that line, first move pure state/model declarations out to a
  focused Thread Detail model file.
- Add the `Updating` refresh display state.
- Keep loaded rows visible during retained refresh.
- Change `load()` so repeated calls on loaded content publish current content
  and call `manualRefresh()` instead of returning early.
- Add `detachView()` and use it from `SessionDetailView.onDisappear`.
- Keep `close()` as the destructive eviction path.

Proof:

- `rtk swift test --filter ThreadDetailStoreTests`
- Add a unit test proving a second `load()`:
  - does not publish `.loading`,
  - keeps existing events visible while resync is delayed,
  - shows `Updating`,
  - calls `thread/detail/resync`,
  - applies the new rows when resync finishes.

### Phase 2 - Retained Store Cache

Files:

- New `CodexDock/ThreadDetail/ThreadDetailStoreCache.swift` or nearest
  existing Thread Detail owner path.
- `CodexDock/Configuration/CodexDockConstants.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/Features/Archive/ArchiveView.swift`
- `CodexDock/Runtime/ClientRuntime.swift` only if factory shape must stay
  centralized.

Work:

- Add a bounded LRU cache keyed by `HostScopedThreadID`.
- Add `CodexDockConstants.ThreadDetail.retainedStoreCapacity` and use it as
  the only production cache capacity.
- Use it in Dock and Archive detail opening.
- On row updates, feed updated rows into the retained store.
- On eviction/deinit, close retained stores.

Proof:

- Focused store/cache unit tests.
- `rtk swift test --filter DockStoreTests` only if host identity or row
  projection behavior changes.
- `rtk swift test --filter ThreadDetailStoreTests`.

### Phase 3 - Controlled Simulator Reopen Proof

Files:

- `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`
- `CodexDockUITests/DisplayedUICaptureSupport.swift`
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-controlled-simulator-fixture.test.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.mjs`
- `Makefile`
- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`

Work:

- Add controlled scenario `detail-reopen-retains-content`.
- Fixture provides one visible Dock row and an initial detail snapshot.
- UI test opens detail, captures loaded detail, navigates back, reopens the
  same row, captures detail immediately, and only then lets fixture continue.
- Fixture delays the reopen resync long enough for the simulator sample to
  prove retained content during `Updating`.
- Fixture then returns a new detail snapshot so proof also verifies in-place
  update after resync.

Scenario must fail if:

- Reopen emits a second `thread/detail/subscribe` instead of
  `thread/detail/resync`.
- Reopen exposes `codexdock.session.state.loading`.
- Reopen loses the initial message projection row before the new snapshot
  arrives.
- Header/root accessibility does not show `Updating` during the delayed
  retained refresh.
- The updated row never appears after resync completes.

Proof:

- `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-reopen-retains-content`
- Add scenario to the controlled simulator matrix after the focused proof
  passes.
- Run:
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`

## Non-Requirements

- No persistence across app termination.
- No background refresh while the app process is dead.
- No new relay production route.
- No migration of archived detail protocol behavior beyond using the same
  retained-store helper in `ArchiveView`.
- No user-facing explanatory banner or tutorial text.
- No hard-coded host or thread IDs in production Swift.

## Constraints

- Mobile builds and simulator proof remain Makefile-owned.
- Existing projection contract stays canonical.
- No raw app-server route can become a phone path.
- Keep secrets on the Mac side; no OpenAI key or raw bearer token enters the
  app.
- Keep Swift state updates on `@MainActor`.
- Do not add new production timeout, retry, capacity, or interval constants
  outside `CodexDock/Configuration/CodexDockConstants.swift`.

## Risks And Required Tests

| Risk | Required proof |
| --- | --- |
| Reopen still wipes to loading | Unit test plus simulator scenario must observe no `codexdock.session.state.loading` on retained reopen. |
| Stale retained rows never update | Unit test and simulator scenario must observe `thread/detail/resync` and updated row after delayed response. |
| Cache leaks live sessions forever | Cache capacity test must prove eviction calls `close()`. |
| Dock and Archive diverge | Both callers must use the same cache helper. |
| Reopen preserves rows but loses local state | Unit tests must cover draft, request-card input/status, and message filter preservation. |
| Updating is confused with reconnecting | State mapping tests must prove manual/detail resync shows `Updating`; transport reconnect still shows `Reconnecting`. |
| Simulator proof only proves mocks | Controlled scenario must use app-facing relay path and forbid raw `thread/detail/read` side doors, matching existing proof rules. |

## Completion Checklist

- [ ] Plan audit verdict is `ready`.
- [ ] Thermo-nuclear code-quality review runs before implementation begins.
- [ ] `ThreadDetailStore` keeps loaded rows visible across repeated `load()`.
- [ ] `SessionDetailView` detaches instead of destructively closing on normal
  disappear.
- [ ] Dock and Archive use the shared retained detail cache.
- [ ] `Updating` is visible in the header while retained refresh is in flight.
- [ ] Focused Swift tests pass.
- [ ] Focused controlled simulator scenario passes on `iPhone 17`.
- [ ] Full controlled simulator matrix passes on `iPhone 17`.
- [ ] Commit and push are done after proof.
- [ ] Relays are updated only if relay/runtime scripts changed.
