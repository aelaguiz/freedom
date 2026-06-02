# Model Consensus Summary

## Status

Converged.

## Participants

- Model A: `claude-opus-4-8`, effort `max`, role `collaborator`
- Model B: `gpt-5.5`, effort `xhigh`, role `collaborator`

## User Goal

Define the best architectural fix for the pinned unpin instability and false broad degraded System Health state. The requested output is a plan on disk, cross-linked with the bug doc. Production code must not be implemented as part of this planning step.

## Consensus

The permanent fix is subtractive: remove duplicate meanings and duplicate interaction paths.

1. Pinned Dock rows must use the same SwiftUI row-action owner as body rows. Delete the normal-rendering `UICollectionView` pinned path instead of making its reload behavior smarter.
2. Pinned reorder must move to a dedicated SwiftUI reorder surface, backed by native move behavior and committed through `DockStore.reorderPinnedRows`.
3. A capped Dock data window such as `Showing 250 of 964` must be represented as loaded window metadata, not as connectivity or service degradation.
4. `DockHostLoadStatus.partial` should be removed as a host-load status because it currently mixes benign windowing with stale/offline/error retained-row states.
5. System Health should degrade a category only from matching route evidence or true service failure. Missing route evidence should render as `Not checked` or `Checking`, not copied global degradation.
6. Proof must include over-time UI behavior and proof-schema validation. Static snapshots alone are not enough for this bug class.

## Plan Document

The consensus plan is recorded at:

`docs/bugs/pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md`

The source bug is recorded at:

`docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md`

Those documents are cross-linked.

## Rejected Alternatives

- Keep UIKit and make `reloadData()` smarter.
- Suppress reload only while a swipe action is open.
- Pause live Dock updates while swiping.
- String-match `Showing` in System Health.
- Fetch all rows to hide the windowed-data message.
- Use `partial(kind:)` instead of removing the overloaded host-load status.
- Prefer inline custom drag reorder on the normal live row surface.
- Leave old UIKit reorder or rendering as a hidden fallback.

## Evidence That Shaped The Plan

- `docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md`
- `CodexDock/Features/Dock/DockPinnedViews.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/State/ThreadCardTable.swift`
- `CodexDock/Dock/DockModels.swift`
- `CodexDock/State/AppConnectivityStore.swift`
- `CodexDock/Connectivity/ConnectivityDataEngine.swift`
- `CodexDock/Connectivity/ConnectivityRenderProjector.swift`
- `CodexDock/State/ArchiveStore.swift`
- `CodexDock/Features/Status/SystemHealthProjector.swift`
- `CodexDock/Features/Status/SystemHealthView.swift`
- `contract/proof/sim-ui-dump.schema.json`
- `scripts/proof-report-contracts.mjs`
- `CodexDockUITests/*DisplayedUI*`

## Remaining Decisions

No architectural decision remains open. The implementation can choose sheet versus pushed screen for the dedicated reorder surface based on local UI convention, but not whether a dedicated reorder surface exists.
