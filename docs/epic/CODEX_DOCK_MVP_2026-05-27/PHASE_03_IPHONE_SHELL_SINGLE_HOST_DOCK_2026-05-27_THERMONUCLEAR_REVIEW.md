# Phase 3 Thermonuclear Code Quality Review

Date: 2026-05-28
Scope: Phase 3 iPhone shell and single-host Dock implementation
Verdict: approve

## Blocking Findings

- None.

## Repairs Made During Review

- Tightened ATS configuration in `project.yml` and regenerated
  `CodexDockApp/Info.plist`: removed broad `NSAllowsArbitraryLoads` and kept
  only `NSAllowsLocalNetworking`. The app was rebuilt and relaunched against
  the real `Amir-M5` LAN app-server after this change; screenshot
  `/tmp/codex-dock-phase3-live-host-no-arbitrary-loads.png` still showed 50
  real sessions.

## Structural Review

- `DockStore` is the correct owner for app-facing Dock state. SwiftUI views do
  not call `AppServerClient`, `thread/list`, or JSON-RPC directly.
- `AppServerDockClient` is a narrow adapter over the existing Phase 1/2 client
  and mapper. It does not introduce a second protocol stack or duplicate DTO
  parsing.
- `DockHostConfiguration` keeps launch-time host configuration explicit and
  fail-loud. Missing endpoint/token states become UI configuration errors rather
  than falling back to fake rows.
- Preview data is isolated to the SwiftUI preview loader in `DockView.swift`.
  Production app construction in `CodexDockApp.swift` uses environment-derived
  host config only.
- The generated Xcode project has a checked-in source of truth,
  `project.yml`, which avoids hand-edited project drift.
- The app-server start path now has a checked-in `Makefile` target. The target
  uses launchd instead of a fragile background shell process, so verification
  can reuse one persistent authenticated LAN listener.

## Maintainability Review

- File sizes are acceptable for this phase: `DockStore.swift` is 352 lines,
  `DockView.swift` is 467 lines, `DockStoreTests.swift` is 183 lines, and no
  file crosses the 1k-line threshold.
- The UI file is dense but cohesive: all private row/banner/empty-state views
  are local to the Dock feature. No extraction is required before Phase 4, but
  row navigation may justify splitting row/detail components then.
- The state model is explicit enough for current scope: configuration error,
  idle, loading, loaded, empty, offline, and protocol error are separate cases.
  There is no nullable mode flag or hidden partial state.
- Search/filter logic is local UI projection over normalized row view models,
  not a second data-fetch path.
- Archive and Hosts tabs are inert placeholders, not parallel implementations
  or fake data paths. The phase boundary remains intact.

## Risk Notes

- `DockView.swift` should be watched in Phase 4. Adding row navigation, detail
  loading, and live thread content in the same file would start to make it too
  broad; Phase 4 should introduce detail-specific files instead.
- `DockStore` currently loads a single page of 50 sessions. That matches Phase
  3 proof, but Phase 6 multi-host expansion should make pagination and
  refresh policy explicit before widening.
- Host configuration currently comes from process environment. That is fine for
  MVP simulator/device development, but Phase 7 Hosts work should replace it
  with a real persisted host source rather than adding more env branches.

## Approval Bar

Approved. The implementation is direct, uses the existing Phase 1/2 boundaries,
does not add production mocks, avoids unsupported Codex daemon assumptions, and
does not introduce obvious spaghetti growth or an unnecessary abstraction layer.
