# Codex Dock Connectivity Resilience - Thermo-Nuclear Review

Date: 2026-05-28

Plan: `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md`

Verdict: approved for current Connectivity closeout with user-approved simulator visual proof. Physical `iPhone 14` visual navigation remains deferred because WebDriverAgent is not running on device `00008110-000E04940240A01E`.

## Blocking Findings

None open.

## Resolved During Review

- [x] RELAY-001 - Initial `thread/resume` could attach a new upstream after the phone socket closed
  - Evidence: `resumeThread` awaited live discovery, `initialize`, and upstream `thread/resume` before assigning `session.upstream`; the downstream close handler could only close an already-assigned upstream.
  - Why it mattered: the relay could leave a raw upstream app-server session alive with no downstream phone client.
  - Fix: `scripts/dock-relay.mjs` now guards initial and recovered upstream work with `session.generation`, `session.closing`, and downstream open-state checks. New upstream clients only attach or forward messages while the same downstream session generation is still active.
  - Proof: `scripts/dock-relay-phase5.test.mjs` adds `thread/resume abandons initial upstream if downstream closes before resume completes`; `rtk npm run test:relay` executed 33 tests with 0 failures.

- [x] RELAY-002 - Relay runtime/test growth needed decomposition
  - Evidence: Phase 5 concentrated JSON-RPC upstream client behavior and in-process relay tests in files that were getting too large to scan.
  - Fix: extracted `scripts/dock-relay-json-rpc-client.mjs`, split Phase 5 tests into `scripts/dock-relay-phase5.test.mjs`, and moved shared helpers into `scripts/dock-relay-test-helpers.mjs`.
  - Result: `scripts/dock-relay.mjs`, `scripts/dock-relay.test.mjs`, `scripts/dock-relay-phase5.test.mjs`, and the new helpers are each under 1k lines.

- [x] SWIFT-001 - Thread detail lifecycle tests were too dense after reconnect/background coverage
  - Evidence: `ThreadDetailStoreTests.swift` had become a mixed surface for baseline detail behavior, reconnect, background/foreground, and support fakes.
  - Fix: split lifecycle-specific tests into `CodexDockTests/ThreadDetailStoreLifecycleTests.swift` and shared fakes/helpers into `CodexDockTests/ThreadDetailStoreTestSupport.swift`.
  - Result: the thread-detail test files are under 1k lines and `rtk swift test --filter ThreadDetailStoreTests` executed 31 tests with 0 failures.

- [x] SWIFT-002 - Reconnect could still open a socket after the app backgrounded during backoff
  - Evidence: `AppServerClient.runReconnectLoop(reason:)` checked the foreground gate before sleeping but not after sleeping.
  - Fix: the reconnect loop now re-checks foreground work after the delay and before opening transport.
  - Proof: `testReconnectDoesNotOpenIfAppBackgroundsDuringBackoffSleep` passes.

- [x] SWIFT-003 - Foreground resume could rehydrate before the socket was connected
  - Evidence: `ThreadDetailStore.handleForegroundResuming(_:)` called compact read/turns/resume immediately, even while the live client was still reconnecting.
  - Fix: `ThreadDetailStore` now tracks latest connection state, waits in `.reconnecting("Resuming")`, and rehydrates only after `.connected`.
  - Proof: `testForegroundResumeWaitsForReconnectBeforeRehydratingDetail` passes.

- [x] SWIFT-004 - App connectivity status was one last-writer-wins slot per host
  - Evidence: Dock, Archive, host tests, thread detail, and lifecycle all wrote into the same host snapshot.
  - Fix: `AppConnectivityStore` now keeps separate observations per source and uses lifecycle as an explicit overlay.
  - Proof: `testThreadDetailStaleIsNotOverwrittenByDockOnline` and `testLifecycleResumingMasksOldStoreFactsUntilActiveClearsIt` pass.

- [x] SWIFT-005 - Bootstrap non-ready states bypassed the global indicator path
  - Evidence: `CodexDockBootstrapView` rendered setup/error states without `AppConnectivityStore` or `GlobalConnectivityIndicatorView`.
  - Fix: bootstrap now owns an `AppConnectivityStore`, reports `RelayBootstrapState`, shows the global indicator while non-ready, and passes the same store into the ready root.
  - Proof: `testBootstrapNonReadyStatesUseGlobalConnectivityStatus` passes.

- [x] SWIFT-006 - Root view initialization mutated published connectivity state during SwiftUI rendering
  - Evidence: the non-Pro simulator initially rendered a blank app surface and repeatedly logged `Publishing changes from within view updates`.
  - Fix: removed `connectivityStore.configure(registry)` from `CodexDockRootView.init(registry:...)` so published connectivity state is not mutated during view construction.
  - Proof: the simulator rendered the Dock normally afterward, no matching SwiftUI render-mutation warnings appeared after relaunch, and `rtk swift test --filter AppConnectivityStoreTests` executed 11 tests with 0 failures.

## Notes

- `CodexDockTests/AppServerClientTests.swift` remains over 1k lines, but it was already over that threshold before this review scope and was not pushed from below 1k to above 1k by the current split.
- The Connectivity implementation now has one clear ownership path: `AppServerClient` owns transport lifecycle, `ThreadDetailStore` owns thread rehydrate, `AppConnectivityStore` owns app-wide status observations and lifecycle overlay, `AppLifecycleCoordinator` owns foreground/background gating, and the relay either recovers upstream or closes downstream loudly.
- The remaining physical-device item is not code shape and is not blocking the current Connectivity closeout. Mobile MCP cannot inspect or screenshot the physical `iPhone 14` until WebDriverAgent is running, but Mobile MCP simulator proof on `feat_anim_1 - iPhone 17` is accepted for this slice.

## Verification Accepted As Context

- `rtk swift test`: 147 tests, 5 skipped, 0 failures.
- `rtk swift test --filter AppConnectivityStoreTests`: 11 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`: 31 tests, 0 failures.
- `rtk swift test --filter AppServerClientTests`: 40 tests, 5 skipped, 0 failures.
- `rtk npm run test:relay`: 33 tests, 0 failures.
- `rtk npm test`: 33 tests, 0 failures.
- `rtk node --check scripts/dock-relay.mjs`: passed.
- `rtk node --check scripts/dock-relay-json-rpc-client.mjs`: passed.
- `rtk node --check scripts/dock-relay-test-helpers.mjs`: passed.
- `rtk node --check scripts/dock-relay-phase5.test.mjs`: passed.
- Physical `iPhone 14` install/launch/process proof passed; relay-backed host smoke passed separately with no phone-side bearer env.
- Physical visual proof is deferred by WebDriverAgent.
- Accepted simulator visual proof: Mobile MCP on `feat_anim_1 - iPhone 17` simulator UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` captured Dock, Archive, Relay, and Session detail screenshots under `/tmp/codex-client/20260528T144220Z/mobile-mcp-proof/`; readback confirmed the root online indicator, `Amir-M5`, `ws://192.168.50.117:4510`, and real rows.
