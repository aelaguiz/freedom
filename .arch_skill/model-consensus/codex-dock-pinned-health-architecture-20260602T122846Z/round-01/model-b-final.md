✅ My collaborator pass: the clean architecture is to remove the two duplicate meanings.

1. Pinned rows should not have a private UIKit unpin path.
2. Dock row-window completeness should not be exported as connectivity degradation.

I did not edit files or write the final plan doc in this pass because consensus has not happened yet.

**Proposed Plan**

Save the consensus doc at:

`docs/bugs/pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md`

Cross-link it to:

`docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md`

Pinned rows:

- Render pinned rows through the same SwiftUI row action owner as normal rows: `DockSwipeActionRow` / `DockView.dockRow`.
- Remove `UICollectionView` from normal pinned-row rendering.
- Move pinned reordering into a separate SwiftUI reorder owner, likely a small reorder mode or sheet that calls `DockStore.reorderPinnedRows`.
- Keep pin persistence exactly where it is: `DockStore.setPinned`, `LocalMetadataEngine.setPinned`, and `PinnedMetadataOrdering`.

Health:

- Split `DockHostLoadStatus.partial` into typed meanings:
  - data-window state: `Showing 250 of 964`
  - service degradation: stale, offline-with-cached-rows, reconnecting, error
- Keep Dock window state visible in Dock summaries.
- Map fresh windowed Dock state to connectivity `.online`, not `.partial`.
- Make `SystemHealthProjector` degrade categories only from matching route diagnostics or true service failure, not from a global partial fallback.

**Evidence Read**

- Bug doc: [pinned-unpin-menu-and-degraded-health-2026-06-02.md](/Users/aelaguiz/workspace/codex-client/docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md:1)
- Pinned UIKit reload path: [DockPinnedViews.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockPinnedViews.swift:310)
- Normal row swipe owner: [DockPinnedViews.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockPinnedViews.swift:8)
- Pinned row bypass: [DockView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockView.swift:859)
- Dock window becomes partial: [ThreadCardTable.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardTable.swift:428)
- Connectivity partial mapping: [AppConnectivityStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/AppConnectivityStore.swift:419)
- System Health fallback degradation: [SystemHealthProjector.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Status/SystemHealthProjector.swift:78)
- Runtime connectivity pipeline: [ConnectivityDataEngine.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Connectivity/ConnectivityDataEngine.swift:40)

**Alternatives Rejected**

❌ Do not string-match `"Showing "` in System Health.

❌ Do not just stop `reloadData()` or add UI retries. That keeps two row-action systems.

❌ Do not pause live Dock updates while swiping. The row UI should survive normal updates.

❌ Do not fetch all rows just to avoid `Showing 250 of 964`. Windowing is intentional.

**Risks / Open Questions**

⚠️ Reorder UX needs one decision: separate SwiftUI reorder sheet/mode versus inline SwiftUI drag. I prefer separate reorder mode because it cleanly removes reorder from the live row action surface.

⚠️ The exact health type shape should be chosen carefully. I prefer `loaded(rowCount, window:)` plus `degraded(rowCount, message:)`, not `partial(kind:)`, because it removes the overloaded word.

**Need From Other Model**

I need the other model to challenge two points:

1. Is a separate pinned reorder editor acceptable, or must inline drag remain?
2. Should global `.partial` ever degrade route categories without route diagnostics?

Net: keep the current data model, but split the overloaded UI and health boundaries.