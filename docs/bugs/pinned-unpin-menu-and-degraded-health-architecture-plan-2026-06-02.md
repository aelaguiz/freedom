---
title: Architecture plan for pinned unpin stability and honest health state
date: 2026-06-02
status: planned
owners:
  - Codex
reviewers:
  - model-consensus: Opus 4.8 Max
  - model-consensus: GBD-55XI
related:
  - ./pinned-unpin-menu-and-degraded-health-2026-06-02.md
  - ../CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md
  - ../CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md
  - ../CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md
  - ../../.arch_skill/model-consensus/codex-dock-pinned-health-architecture-20260602T122846Z/
---

# Architecture Plan: Pinned Unpin Stability And Honest Health State

## TL;DR

This is not a tiny tweak plan. The permanent fix is to remove the two duplicated meanings that caused this class of bugs:

1. Pinned rows must not have a private UIKit interaction path. Normal rows and pinned rows should use one SwiftUI row-action owner.
2. A capped data window like `Showing 250 of 964` must not be represented as service or connectivity degradation.

The model-consensus result is: enforce one owner per fact. Delete the pinned `UICollectionView` bridge from normal rendering, move reorder into a dedicated SwiftUI reorder surface, split the shared host load status so window completeness is not health, make System Health route-evidence based, and add canonical over-time proof so this cannot silently drift again.

No production code was implemented for this plan.

## Source Bug

This plan is cross-linked with [pinned-unpin-menu-and-degraded-health-2026-06-02.md](./pinned-unpin-menu-and-degraded-health-2026-06-02.md).

That bug doc established two client-side failures:

- Pinned `Unpin` can appear and disappear because pinned rows render through a custom `UICollectionView` bridge that reloads during SwiftUI updates.
- System Health can mark Dock feed, thread detail, archive, voice, and diagnostics degraded because a Dock row-window message (`Home: Showing 250 of 964`) is escalated into global connectivity partiality and then into per-category degradation.

## Model Consensus

Consensus artifact directory:

`../../.arch_skill/model-consensus/codex-dock-pinned-health-architecture-20260602T122846Z/`

Participants:

- `Opus 4 8 Max` resolved as `claude-opus-4-8` with max effort.
- `GBD-55XI` resolved as `gpt-5.5` with xhigh effort.

Both models independently converged on the same core fix:

- Remove the duplicate pinned interaction path.
- Remove the overloaded `partial` meaning from host load state.
- Keep route diagnostics as the only owner of per-feature System Health degradation.
- Add proof that observes live updates over time, not only static snapshots.

The main round-2 refinement was:

- Prefer an explicit pinned reorder mode or sheet using native SwiftUI move behavior.
- Do not make custom inline drag reorder the first architecture, because that risks recreating a second gesture system on the same live row surface.

## North Star

The app should behave like this:

- If a row is visible, the user can swipe it and use the same stable row actions whether the row is pinned or unpinned.
- Live Dock updates, layout updates, health ticks, and startup recovery do not close an action the user is actively trying to tap.
- A host can be online and still show only the first window of a large data set.
- `Showing 250 of 964` means "this view is windowed." It does not mean "the relay, thread detail, archive, voice, and diagnostics are degraded."
- System Health says `Degraded` only when it has direct route evidence or a true service failure signal.
- If route evidence has not been fetched yet, System Health says `Not checked` or `Checking`, not `Degraded`.

## Architectural Principle

One owner per fact:

| Fact | Canonical owner | Current violation | Permanent fix |
| --- | --- | --- | --- |
| Row swipe action state | `DockSwipeActionRow` local SwiftUI state | Pinned rows use a separate UIKit collection/list path | Pinned and body rows use one SwiftUI row-action path |
| Pinned ordering | `DockStore.reorderPinnedRows` and `LocalMetadataEngine.reorderPinnedRows` | UIKit owns reorder gesture and normal pinned rendering | Dedicated SwiftUI reorder surface calls the existing reorder owner |
| Data-window completeness | Thread-card stream `complete`, `totalRows`, and `window` fields | Converted into `DockHostLoadStatus.partial` | Store as a window annotation on a loaded host state |
| Service degradation | Relay freshness and route diagnostics | Shares the same `partial` word as window completeness | Represent as a distinct degraded/offline/error status |
| Per-feature System Health | Route diagnostics from the relay/client observability path | Global partial fallback degrades every category | Categories degrade only from matching route evidence or true service failure |
| UI proof contract | `contract/proof/*.schema.json` plus the real producer | Producer/schema drift only appears during simulator dump | Fast producer-to-schema contract test plus live over-time UI proof |

## Plan Part 1: One Dock Row Interaction Surface

### Decision

Pinned rows and body rows should render through the same SwiftUI row action component:

- Keep `DockSwipeActionRow` as the row-action owner.
- Keep `DockView.dockRow(...)` / row content as the shared content path.
- Delete `DockPinnedReorderCollectionView`, `PinnedCollectionView`, its `Coordinator`, UIKit long-press recognizer, height-measurement loop, and normal pinned `UICollectionView` rendering.

### Why

The current pinned path uses `UICollectionView.reloadData()` during SwiftUI updates. UIKit reloads can close open swipe actions. That is the wrong architecture for a live-updating Dock surface.

The correct architecture is not "reload more carefully." The correct architecture is that row actions have one owner, and that owner is stable across render updates unless the row identity or action state actually changes.

### Reorder Decision

Pinned reorder should move to a dedicated reorder surface:

- Entry point: pinned section header action, for example `Reorder`.
- Surface: sheet or pushed screen, chosen by normal app UI conventions during implementation.
- Implementation direction: native SwiftUI move behavior, such as `List` with `EditMode` / `.onMove`.
- Commit path: call existing `DockStore.reorderPinnedRows(_:)`.

Do not make inline drag-reorder on the normal live row surface the primary architecture. Inline drag would put swipe and reorder back into one gesture-arbitration surface, which is the class of problem this plan is removing.

Do not keep UIKit behind a flag or as a fallback for normal pinned rendering. That would leave the side door open.

### Owner Paths

- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/Features/Dock/DockPinnedViews.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/Metadata/LocalMetadataEngine.swift`

## Plan Part 2: Split Window Completeness From Health

### Decision

Replace the overloaded shared host status shape. The key architectural move is to remove `DockHostLoadStatus.partial(rowCount:message:)` rather than add more special cases around it.

Target shape:

```swift
public struct DockHostWindow: Equatable, Sendable {
    public let visibleRows: Int
    public let totalRows: Int
}

public enum DockHostLoadStatus: Equatable, Sendable {
    case checking
    case loaded(rowCount: Int, window: DockHostWindow?)
    case empty
    case degraded(rowCount: Int, message: String)
    case offline(String)
    case error(String)
}
```

The exact type and property names can move during implementation, but the semantic split should not:

- `loaded(..., window:)` means the service is usable and the view is intentionally windowed.
- `degraded(...)` means the service path has a real problem but retained rows still exist.
- `offline` and `error` remain true unavailable states.
- `window` is display metadata. It is never connectivity evidence.

Do not keep `DockHostLoadStatus.partial` as a compatibility alias. Removing it is valuable because the compiler forces every producer and consumer to declare which meaning it intended.

### Why

Right now `ThreadCardTable.hostStatus(...)` can return `.partial("Showing X of Y")` before freshness is consulted. That merges two unrelated facts:

- data completeness: "the current view is only a window"
- health: "the service path is impaired"

That overloaded value then flows into connectivity and System Health. The elegant fix is to sever the leak at the source, not string-match `Showing`.

### Required Reclassification

Every current `DockHostLoadStatus.partial` producer must be reclassified:

- Fresh but windowed stream snapshot -> `.loaded(rowCount: visible, window: ...)`
- Stale heartbeat with retained rows -> `.degraded(rowCount: retained, message: ...)`
- Offline-with-cached rows -> `.degraded(rowCount: retained, message: ...)`
- Error-with-cached rows -> `.degraded(rowCount: retained, message: ...)`
- Refreshing/unknown transient with rows -> non-degrading checking or loaded state, depending on the actual freshness contract

This split must live in the shared status type because Archive has the same status/phase pattern. A Dock-only workaround would leave the class of bug alive.

### Owner Paths

- `CodexDock/Dock/DockModels.swift`
- `CodexDock/State/ThreadCardTable.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/State/ArchiveStore.swift`
- `CodexDock/Features/Dock/DockSharedViews.swift`
- `CodexDock/Features/Dock/DockGroupRows.swift`
- `CodexDock/Archive/ArchiveCleanupModels.swift`

## Plan Part 3: Sever Completeness From Connectivity

### Decision

Connectivity rollups should never consume the `window` annotation.

Fresh windowed data should map to online/loaded connectivity, while Dock still displays the window message.

Only true service states should map into connectivity concern:

- `.degraded` -> partial/degraded connectivity, if retained rows exist
- `.offline` -> offline connectivity
- `.error` -> error connectivity
- `.loaded(window:)` -> online connectivity

`HostConnectivityPhase.partial` can still exist for true partial service availability. It must not mean "this view is windowed."

### Why

The repo currently has more than one connectivity rollup path:

- `AppConnectivityStore`
- `ConnectivityDataEngine` / `ConnectivityRenderProjector`

That duplication is a separate architectural smell, but this plan does not need to unify both rollups to fix the reported bug. Cutting the false signal upstream means both rollups receive the right fact.

### Owner Paths

- `CodexDock/State/AppConnectivityStore.swift`
- `CodexDock/Connectivity/ConnectivityDataEngine.swift`
- `CodexDock/Connectivity/ConnectivityRenderProjector.swift`
- `CodexDock/Runtime/ConnectivityEventSink.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/State/ArchiveStore.swift`

## Plan Part 4: Make System Health Evidence-Based

### Decision

System Health should use route diagnostics as the owner of per-feature health.

Required behavior:

- On open, automatically fetch route diagnostics through the existing diagnostics path.
- Debounce or skip the fetch if diagnostics are already fresh enough.
- While fetching, show `Checking`.
- If there is no route evidence yet, show `Not checked`.
- If route diagnostics fail to load, show a diagnostics fetch error or `Not checked` with clear action text.
- A category becomes `Degraded` only from matching route evidence or true service failure.

Remove the fallback that turns global `.partial` into every category being `Degraded`.

### Why

Opening System Health is diagnostic intent. The user should not need to tap `Run check` before the screen can tell the truth. But the screen must also not invent degradation before evidence exists.

The manual `Run check` action should remain as an explicit refresh.

### Owner Paths

- `CodexDock/Features/Status/SystemHealthView.swift`
- `CodexDock/Features/Status/SystemHealthProjector.swift`
- `CodexDock/State/AppConnectivityStore.swift`
- `CodexDock/Diagnostics/ObservabilityContract.swift`

## Plan Part 5: Canonical Proof, Not Side Tests

### Decision

This class of bug needs proof that the app behaves correctly while updates happen over time. Static snapshot tests are not enough.

Proof must live in canonical owner tests and proof-contract paths, not as one-off helper scripts.

### Required Tests

Fast Swift tests:

- `DockStoreStreamTests`
  - fresh windowed snapshot is loaded with a window annotation, not partial/degraded
  - stale/offline/error retained-row cases become degraded
  - no `DockHostLoadStatus.partial` remains
- `ArchiveStore` tests
  - Archive uses the same status split and does not convert a fresh window into connectivity degradation
- `AppConnectivityStoreTests`
  - fresh windowed Dock and Archive hosts report online
  - true degraded retained-row hosts report partial/degraded connectivity
- `ConnectivityDataEngineTests`
  - runtime connectivity path agrees with `AppConnectivityStore`
- `SystemHealthProjectorTests`
  - route-less categories show `Not checked`, not `Degraded`
  - fresh windowed Dock status does not degrade thread detail, archive, voice, or diagnostics
  - true route degradation affects only the matching category

UI and live-update proof:

- `CodexDockUITests`
  - seed or pin multiple rows
  - relaunch the `iPhone 17` simulator
  - open a pinned row swipe action
  - inject or replay a Dock update
  - assert `Unpin` remains present and tappable across samples
- Existing over-time displayed UI harness
  - extend the canonical harness instead of adding a separate proof path
  - a skipped or hung dump is blocked, not green

Proof contract:

- `contract/proof/*.schema.json` remains the schema owner.
- Add a fast producer-to-schema test for the Swift displayed-state producer, including `DisplayedUIAppMetadata`.
- Decide once whether `configuredBuildNumber` belongs in the schema and make producer and schema agree.
- `rtk make sim-ui-dump SIM='iPhone 17'` should be trustworthy after the contract is fixed.

### Required Commands

Use the smallest relevant checks first:

```bash
rtk swift test --filter DockStoreStreamTests
rtk swift test --filter AppConnectivityStoreTests
rtk swift test --filter ConnectivityDataEngineTests
rtk swift test --filter SystemHealthProjectorTests
rtk swift test --filter ArchiveScreenStoreTests
rtk swift test --filter ArchiveDataEngineTests
rtk swift test --filter ArchiveCleanupStoreTests
rtk make app-test SIM='iPhone 17'
rtk make sim-ui-dump SIM='iPhone 17'
```

If production relay code is not changed, `rtk npm run test:relay` is not required for this plan. If implementation touches relay DTO or contract code, run the relay tests too.

## Implementation Phases

These phases are intentionally ordered so each cut removes a class of ambiguity.

### Phase 1: Shared Status Split

- Introduce the window annotation type.
- Replace `DockHostLoadStatus.partial` with explicit loaded/degraded meanings.
- Update every producer and consumer until the compiler has no `partial` cases left for `DockHostLoadStatus`.
- Include Dock and Archive in the same cut.

Done when:

- Fresh windowed data is `loaded(window:)`.
- Retained-row service failures are `degraded`.
- No code can accidentally treat window completeness as health through `DockHostLoadStatus`.

### Phase 2: Connectivity Mapping

- Update Dock and Archive connectivity event production.
- Ensure both connectivity paths treat `loaded(window:)` as online.
- Keep true service degradation mapped to connectivity concern.

Done when:

- `Showing 250 of 964` can still render in Dock.
- The global connectivity indicator does not become partial solely because of that window.

### Phase 3: System Health

- Remove the global partial fallback that degrades every category.
- Fetch route diagnostics on open.
- Keep `Run check` as manual refresh.
- Render `Checking` / `Not checked` honestly while evidence is missing.

Done when:

- Route-less categories do not show copied Dock window text.
- Categories degrade only from route evidence or true service failure.

### Phase 4: Pinned Row Surface

- Render pinned rows through the same SwiftUI row-action path as body rows.
- Delete normal pinned `UICollectionView` rendering and the reload-driven UIKit bridge.
- Preserve pin/unpin persistence paths.

Done when:

- A pinned row and body row use the same swipe-action implementation.
- Live updates do not close the pinned row action just because the section re-rendered.

### Phase 5: Reorder Surface

- Add a dedicated pinned reorder surface using native SwiftUI move behavior.
- Commit order through `DockStore.reorderPinnedRows(_:)`.
- Do not restore UIKit or custom inline drag as a hidden fallback.

Done when:

- Pinned rows can be reordered without sharing the live swipe surface.
- Reorder has no path that can reload and close normal pinned row actions.

### Phase 6: Canonical Proof

- Add the fast unit tests listed above.
- Add the live pinned interaction-survival UI proof.
- Fix displayed UI producer/schema drift.
- Run the simulator proof paths.

Done when:

- A fresh windowed host proves online and non-degraded across unit and UI paths.
- Pinned `Unpin` survives an update in the actual `iPhone 17` simulator app.
- UI dump producer and schema cannot drift silently.

## Rejected Alternatives

Rejected because they preserve the bug class:

- Keeping UIKit and making `reloadData()` smarter.
- Suppressing reloads only while a swipe is open.
- Pausing live Dock updates while a row action is open.
- Adding string checks for `Showing` in System Health.
- Fetching all rows so the Dock window message disappears.
- Using `partial(kind:)` as the health shape. The word `partial` is already overloaded; removing the word from host load status is cleaner.
- Building custom inline drag/swipe arbitration as the first reorder architecture.
- Leaving old UIKit reorder as a hidden fallback for testing or emergency use.

## Non-Goals

This plan does not:

- Change relay status semantics.
- Make the iPhone connect directly to the raw app server.
- Query or control the physical iPhone 17 Pro.
- Implement production code.
- Rewrite the whole connectivity subsystem.

The two connectivity rollup paths are a real follow-up risk. The consensus view is that severing the false signal at `DockHostLoadStatus` fixes the reported bug across both paths without expanding this plan into a broader rewrite.

## Final Consensus Statement

The elegant permanent solution is subtractive:

- one row-action surface
- one reorder owner
- one typed meaning for data-window completeness
- one typed meaning for service degradation
- one evidence owner for System Health
- one canonical over-time proof path

If this is implemented as specified, the current pinned unpin instability and false broad health degradation should be eliminated as an architectural class, not just patched at the observed symptoms.
