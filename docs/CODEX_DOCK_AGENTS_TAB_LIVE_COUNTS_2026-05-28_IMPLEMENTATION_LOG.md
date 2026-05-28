---
title: "Codex Dock - Agents Tab And Live Counts - Implementation Log"
date: 2026-05-28
status: active
plan: docs/CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md
parent: docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md
---

# Implementation Log

## 2026-05-28

- Started Phase 1 implementation on branch `codex-dock-agents-tab-live-counts`.
- Parallelized planning, implementation, and review:
  - Swift source/query and Dock projection call-site explorers audited the owner paths.
  - A relay worker handled `scripts/dock-relay*.mjs` live `sourceKinds` filtering parity.
  - Final plan-audit and thermo-nuclear review reruns checked the repaired Phase 1 diff.
- Local critical path owns Swift model, loader query, Dock snapshot/tab counts, and UI rendering.
- Implemented the Phase 1 frontier across the app and relay:
  - `SessionSummary` now carries typed origin evidence from structured app-server source metadata.
  - `DockSessionQuery` is the loader contract for Dock, Archive, Hosts, previews, and tests.
  - `DockSnapshot` owns counted tabs, tab-scoped sections, scoped load failures, and partial host status.
  - `DockView` renders snapshot-provided tab labels and no longer owns business predicates.
  - Relay live `thread/list` rows now honor `sourceKinds` before merge/pagination.
- Review repairs applied before audit gate:
  - Removed the old no-query loader side door.
  - Classified contradictory source metadata, including conflicting sub-agent variants, as `unknown`.
  - Kept internal/memory source metadata out of default and Agents filtered scopes; the Dock Agents query now uses the explicit non-internal source-kind list and excludes broad `.subAgent`.
  - Removed the broad `SessionOriginSubtype` eraser layer so invalid human/automation subtype combinations cannot be constructed through the public factory API.
  - Made DockStore test loaders fail loudly on unexpected `DockSessionQuery` values instead of silently returning empty Agents rows.
  - Extracted relay source filtering to `scripts/dock-relay-source-filter.mjs`.
  - Split Agents scope tests to `CodexDockTests/DockStoreScopeTests.swift` and configuration/bootstrap tests to `CodexDockTests/DockConfigurationTests.swift`.
- Verification on current implementation:
  - `rtk swift test --filter ThreadListMappingTests` passed: 11 tests.
  - `rtk swift test --filter DockStoreTests` passed: 18 tests.
  - `rtk swift test --filter DockStoreScopeTests` passed: 7 tests.
  - `rtk swift test --filter DockConfigurationTests` passed: 9 tests.
  - `rtk swift test --filter AppServerClientTests` passed: 29 tests, 5 skipped.
  - `rtk swift test --filter ThreadDetailStoreTests` passed: 15 tests.
  - `rtk swift test` passed: 100 tests, 5 skipped.
  - `rtk npm run test:relay` passed: 21 tests.
  - `rtk git diff --check` passed.
- Physical iPhone 14 proof target:
  - Device: `iPhone 14`, Xcode destination id `00008110-000E04940240A01E`.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS,id=00008110-000E04940240A01E' build` passed.
  - `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` passed and installed `com.aelaguiz.CodexDockApp`.
  - `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E com.aelaguiz.CodexDockApp` passed.
- Review gate result:
  - Plan implementation audit rerun verdict: `approve`, no blocking or non-blocking findings.
  - Thermo-nuclear code-quality rerun: no blockers or high-severity findings; medium follow-up risks are source-classification drift across Swift/relay and future `DockStore` decomposition before the next Dock phase.
