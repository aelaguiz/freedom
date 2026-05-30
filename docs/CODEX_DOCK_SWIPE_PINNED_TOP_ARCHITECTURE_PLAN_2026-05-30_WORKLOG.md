# Codex Dock Swipe Pinned Top Worklog

Plan: `docs/CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30.md`
Date: 2026-05-30
Status: complete

## 2026-05-30 Implementation Closeout

- Removed the capped pinned-list model, `Show all`, `Manage`, and the pinned
  management sheet.
- Added durable `pinnedOrder` metadata and static user-owned pinned ordering.
- Added native UIKit collection interactive movement for long-press pinned-row
  reorder with no visible handle or edit mode.
- Added collapse/expand on the `Pinned` header and a divider between pinned
  rows and the selected Dock body.
- Centralized true-message classification in `ThreadMessageSemantics` and made
  Dock preview/order use message-derived summary/activity.
- Added relay `messageSummary` / `messageUpdatedAt` fixture coverage.
- Extracted pin-order normalization into `PinnedMetadataOrdering` so
  `DockStore.swift` stays below 1,000 lines.
- Disabled the normal row context menu on pinned rows after simulator proof
  showed it intercepted the required long-press reorder gesture.

## Verification Evidence

- `rtk git diff --check`: passed.
- `rtk swift test --filter DockStoreTests`: 48 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests`: 52 tests passed.
- `rtk swift test --filter 'ThreadListMappingTests|ThreadEventNormalizerTests|AutomationIDTests'`: 27 tests passed.
- `rtk swift test --filter AutomationIDTests`: 3 tests passed after the final
  pinned-row context-menu fix.
- `rtk npm run test:relay`: 105 tests passed.
- `rtk make app-test SIM='iPhone 17'`: passed with result bundle
  `/tmp/codex-client/app-test-detached-20260530T132652Z/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.30_08-26-54--0500.xcresult`;
  result `Passed`, 260 passed, 0 failed, 5 skipped, 265 total.
- `rtk make iphone-17-pro`: installed and launched build `20260530133223` on
  iPhone 17 Pro `CB9FFF0E-89AD-57B5-9C00-6552D814875E`.
- `rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`:
  verified hosts `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.

## Review Evidence

- Parent thermo-nuclear maintainability review found no blocking structural
  issue after:
  - `DockStore.swift` dropped to 919 lines.
  - `DockView.swift` stayed under 1,000 lines at 928 lines.
  - `DockPinnedViews.swift` stayed focused at 412 lines.
  - `PinnedMetadataOrdering.swift` owns pure pin-order normalization.
  - Native reorder, native trailing unpin swipe, and no-handle UI were proven
    by the iPhone 17 simulator pass.
- Composer 2.5 Fast fresh consult:
  `/tmp/fresh-consult/codex-dock-pinned-final-composer-20260530T133301Z-2lk1727q/final.txt`
  returned `VERDICT: pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`.
