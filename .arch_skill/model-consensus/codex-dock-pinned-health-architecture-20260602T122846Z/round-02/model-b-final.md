✅ Model A is architecturally equivalent on the core fix, stronger on proof-contract drift, and slightly weaker on pinned reorder. I agree with its “one owner per fact” framing, but I would not make inline drag-reorder the preferred pinned solution.

**Consensus Architecture**

Pinned rows:

- Normal pinned rows render through the same SwiftUI row action path as body rows: `DockSwipeActionRow` / `DockView.dockRow`.
- Delete the pinned `UICollectionView` bridge from normal rendering. It currently exists for reorder, but it also owns a second swipe path and reloads during updates.
- Use an explicit pinned reorder mode or sheet, backed by SwiftUI native move behavior, and commit through `DockStore.reorderPinnedRows`.
- Do not build a custom inline drag/swipe gesture arbiter as the first architecture. That is a new interaction system and risks recreating this class of bug.

Health:

- Replace overloaded Dock `.partial` with typed Dock meanings.
- Use `loaded(rowCount, window/completeness:)` for fresh-but-windowed data like `Showing 250 of 964`.
- Use a sibling degraded/service state for stale, offline-with-cached-rows, reconnecting, and error.
- Map fresh windowed Dock state to connectivity `.online`, while Dock still displays the window message.
- Keep route diagnostics as the only owner of per-feature System Health degradation.

System Health behavior:

- Auto-fetch route diagnostics on open, debounced or only when missing/stale.
- Until route evidence arrives, categories show `Not checked` or `Checking`, not `Degraded`.
- Keep `Run check` as an explicit refresh.

Proof:

- Canonical proof lives in owner tests, not helper-only paths.
- Add/update `DockStoreStreamTests` for windowed vs degraded Dock status.
- Add/update `AppConnectivityStoreTests` and `ConnectivityDataEngineTests` so the direct and runtime connectivity pipelines agree.
- Add/update `SystemHealthProjectorTests` so route-less categories do not degrade from global partial.
- Add a real `CodexDockUITests` pinned-unpin regression under `rtk make app-test SIM='iPhone 17'`.
- Fix the sim UI dump schema/producer drift in the proof contract path so diagnostic dumps are trustworthy, not optional side evidence.

**Rejected Alternatives**

❌ Inline SwiftUI drag-reorder as the preferred architecture. It preserves the old “reorder competes with swipe” problem in a new form.

❌ Keeping UIKit and making `reloadData()` smarter. That is a patch to the duplicate interaction path, not removal of it.

❌ A generic `.partial(kind:)` health shape. The word is already overloaded; the plan should remove that ambiguity.

❌ Manual-only System Health diagnostics. The screen should collect evidence when opened, while still showing honest `Not checked` before evidence exists.

**Implementation Phases**

1. Update the architecture plan doc only, cross-linked with the bug doc.
2. Refactor pinned rendering to one SwiftUI row action surface and separate reorder mode/sheet.
3. Split Dock window completeness from service degradation in `DockHostLoadStatus` and downstream connectivity mapping.
4. Tighten `SystemHealthProjector` fallback behavior and add on-open diagnostics fetch.
5. Add canonical unit/UI/proof-contract tests.
6. Run the smallest relevant checks first, then `rtk make app-test SIM='iPhone 17'` for UI proof.

**Remaining Blockers**

None. The remaining work is synthesis into the final plan doc, not another architectural decision.