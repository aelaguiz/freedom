# Thermo-Nuclear Code Quality Review

Plan: `docs/THREAD_DETAIL_NO_WIPE_REFRESH_ARCHITECTURE_2026-06-05.md`
Review time: 2026-06-05T16:47:49Z
Scope: planned no-wipe Thread Detail retained refresh implementation before code changes.
Verdict: approved for implementation after plan repair

## Blocking Findings

None remaining.

## Finding Repaired During Review

### TN-001 - Do not push `ThreadDetailStore.swift` over 1,000 lines

Problem:

- `CodexDock/State/ThreadDetailStore.swift` is already 959 lines before the new behavior.
- Adding retained-refresh state, `detachView()`, and reload handling directly into this file would likely push it over the 1,000-line maintainability limit.

Why it mattered:

- The store is already the canonical owner for detail lifecycle, composer state, projection reconciliation, request-card state, and voice lifecycle.
- Letting it grow further would make the right architecture harder to scan and would normalize file sprawl in the hottest state owner.

Required repair:

- Keep `ThreadDetailStore.swift` below 1,000 lines.
- If retained-refresh implementation would cross that line, first move pure state/model declarations into a focused Thread Detail model file.
- Keep caller edits tiny in `DockView.swift` and `ArchiveView.swift`; the cache belongs in its own `ThreadDetailStoreCache` type.

Resolution evidence:

- The plan now names `CodexDock/ThreadDetail/ThreadDetailStoreModels.swift` as the extraction path when needed.
- The plan now explicitly requires keeping `ThreadDetailStore.swift` under 1,000 lines.

## Architecture Quality Notes

- The strongest design move is to reuse `StreamReconciler.manualRefresh()` and the existing `ThreadDetailStore` content state instead of adding a second cache of rows, DTOs, or rendered view models.
- `ThreadDetailStoreCache` is justified because it removes duplicate caller lifecycle logic from Dock and Archive and gives eviction one owner.
- The implementation should not add a caller flag like `load(retained:)`; `load()` should remain the single caller API and internally choose first load vs retained refresh.
- The production relay should not change. The plan correctly keeps the protocol surface at `thread/detail/subscribe`, `thread/detail/update`, and `thread/detail/resync`.

## Approval Bar For Implementation

- No new side cache for detail rows.
- No new relay detail route.
- No caller-owned lifecycle flags.
- No special-case branches scattered through Dock and Archive.
- `ThreadDetailStore.swift` remains below 1,000 lines after implementation.
- New retained-store logic lives in one small cache helper keyed by `HostScopedThreadID`.
