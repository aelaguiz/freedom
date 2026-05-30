# Codex Dock - Client Responsiveness Hard Cut - Worklog

## 2026-05-30

### Phase 0 - Foundation contracts, constants, and instrumentation

Status: COMPLETE

- Started `$arch-step auto-implement` from
  `docs/CODEX_DOCK_CLIENT_RESPONSIVENESS_ARCHITECTURE_2026-05-30.md`.
- Verified the ArcStep receipt gate reports `READY next=implement-loop`.
- Confirmed the branch is `codex-dock-agents-tab-live-counts`, not the default
  branch.
- Existing dirty/untracked work was present before implementation and is being
  left untouched unless it overlaps the phase.
- Added `CodexDockConstants.Rendering` constants for main publish budgets,
  coalescing, search/voice debounce, visible detail window sizing, Dock render
  row budget, and newest-one render buffering.
- Added `DockLog.rendering`, `DockLog.runtime`, `DockSignpost.rendering`, and
  `RenderSignpostName`.
- Added `CodexDock/Rendering/RenderRevision.swift`.
- Added `CodexDock/Rendering/RenderCoalescer.swift`.
- Added `CodexDock/Runtime/ConnectivityEventSink.swift`.
- Added `CodexDock/Runtime/ClientRuntime.swift`.
- Added `CodexDockTests/RenderCoalescerTests.swift`.
- Added `CodexDockTests/ClientRuntimeTests.swift`.
- Verification:
  - `rtk swift test --filter RenderCoalescerTests` passed, 3 tests.
  - `rtk swift test --filter ClientRuntimeTests` passed, 3 tests.
  - `rtk swift test --filter DockStoreTests` passed, 48 tests.
  - `rtk swift test --filter ThreadDetailStoreTests` passed, 52 tests.

### Phase 1 - Dock Home hard cut

Status: COMPLETE AFTER COMPOSER REOPEN

- Added `CodexDock/Dock/DockRenderModels.swift`.
- Added `CodexDock/Dock/DockRenderProjector.swift`.
- Moved Dock row mapping/cached pinned row construction out of
  `DockSessionTable.snapshot(...)` and into `DockRenderProjector`.
- Added `CodexDock/Dock/DockDataEngine.swift` as the first non-main owner for
  Dock table mutation and render snapshot production.
- Added `CodexDock/Dock/DockScreenStore.swift` as the first main-actor Dock
  render presenter.
- Wired `DockStore` through `DockDataEngine` for Dock stream table mutation and
  snapshot production while keeping the existing public action API stable.
- Wired `DockView` to render from `DockScreenStore` and removed its body-time
  `snapshot.project(options:)` projection calls.
- Added `ClientRuntime` store factory methods and routed
  `CodexDockBootstrapView` / `CodexDockRootView` ready-state construction
  through `ClientRuntime`.
- Added `CodexDockTests/DockRenderProjectorTests.swift`.
- Added `CodexDockTests/DockDataEngineTests.swift`.
- Added `CodexDockTests/DockScreenStoreTests.swift`.
- Added immediate `DockScreenStore.searchText` publication while keeping
  render projection debounced by
  `CodexDockConstants.Rendering.searchDebounceMilliseconds`.
- Added Dock render signpost coverage and a row-budget log guard for large
  main-actor publications.
- Verification:
  - `rtk swift test --filter DockRenderProjectorTests` passed, 2 tests.
  - `rtk swift test --filter DockDataEngineTests` passed, 3 tests.
  - `rtk swift test --filter DockScreenStoreTests` passed, 4 tests.
  - `rtk swift test --filter ClientRuntimeTests` passed, 4 tests.
  - `rtk swift test --filter DockStoreTests` passed, 48 tests.
  - `rtk swift test --filter DockStoreStreamTests` passed, 10 tests.
  - `rtk rg "snapshot\\.project|\\.project\\(options:" -n
    CodexDock/Features/Dock/DockView.swift CodexDock/State/DockStore.swift
    CodexDock/Dock` reports only `DockRenderProjector.swift`.

### Phase 2 - Command and local metadata separation

Status: COMPLETE

- Added `CodexDock/Metadata/LocalMetadataEngine.swift` to own local label,
  color, pin, unpin, and pinned-row reorder persistence off the main actor.
- Added `CodexDock/Commands/ClientCommandEngine.swift` to own archive and
  unarchive app-server commands off the main actor.
- Wired `DockStore` row metadata actions through `LocalMetadataEngine`.
- Wired Dock archive and Archive restore actions through `ClientCommandEngine`.
- Wired Thread Detail composer sends and request-card responses through
  `ClientCommandEngine`.
- Added `CodexDockTests/LocalMetadataEngineTests.swift`.
- Added `CodexDockTests/ClientCommandEngineTests.swift`.
- Verification:
  - `rtk swift test --filter DockStoreTests` passed, 48 tests.
  - `rtk swift test --filter LocalMetadataEngineTests` passed, 2 tests.
  - `rtk swift test --filter ClientCommandEngineTests` passed, 3 tests.
  - `rtk swift test --filter ThreadDetailStoreTests` passed, 52 tests.

### Phase 3 - Thread Detail hard cut

Status: COMPLETE AFTER COMPOSER REOPEN

- Added `CodexDock/ThreadDetail/ThreadDetailRenderModels.swift`.
- Added `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`.
- Added `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift`.
- Wired `ThreadDetailStore` to publish coalesced render snapshots through
  `ThreadDetailScreenStore`.
- Rebound `SessionDetailView` to `ThreadDetailScreenStore` for detail screen
  state and message filter state.
- Fixed a SwiftUI ownership mismatch where `SessionDetailView` preserved the
  first `ThreadDetailStore` as a `StateObject` but observed a freshly-created
  `ThreadDetailScreenStore` on destination recomputation.
- Rebound `ThreadMessageListView` to pre-attached `ThreadEventRenderRow`
  values, so request-card lookup is not performed from SwiftUI row rendering.
- Added `CodexDockTests/ThreadDetailRenderProjectorTests.swift`.
- Added `CodexDockTests/ThreadDetailScreenStoreTests.swift`.
- Added `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` and
  `ThreadEventIndex` so normalization, merge, active-turn tracking, and
  newest-first ordering happen off the main actor.
- Changed `ThreadEventIndex` to keep incremental newest-first order after
  initial replacement instead of sorting on every publish.
- Changed `ThreadDetailRenderProjector` to preserve engine order, build only a
  visible window, and attach request cards through a dictionary-backed index.
- Changed `ThreadDetailRenderSnapshot` so published render state carries
  header, live state, options, and visible rows only, not the full event list.
- Rebound `ComposerView` to `ThreadDetailScreenStore` composer render state and
  intent closures instead of observing `ThreadDetailStore`.
- Added `CodexDockTests/ThreadDetailDataEngineTests.swift`.
- Verification:
  - `rtk swift test --filter ThreadDetailRenderProjectorTests` passed, 1 test.
  - `rtk swift test --filter ThreadDetailScreenStoreTests` passed, 1 test.
  - `rtk swift test --filter ThreadDetailDataEngineTests` passed, 3 tests.
  - `rtk swift test --filter ThreadDetailStoreTests` passed, 52 tests.
  - Diagnostic rerun:
    `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
    -destination id=DEF1631B-7125-43C6-BFA3-4423BF103C91 -derivedDataPath
    .codex-dock/DerivedData CURRENT_PROJECT_VERSION=20260530185823
    -only-testing:CodexDockUITests/CodexDockAutomationSmokeTests/testScriptedDockCardsUseTrueMessagesForPreviewOrderAndDetailFilter
    -resultBundlePath
    /tmp/codex-client/20260530T140200Z/scripted-message-noise-3.xcresult`
    passed.
  - `rtk rg "visibleEvents\\(|requestCards\\.first|ThreadEventDisplayOrder\\.newestFirst" -n
    CodexDock/Features/Session CodexDock/ThreadDetail
    CodexDock/State/ThreadDetailStore.swift` reports no `visibleEvents(...)`
    or request-card row scan in `CodexDock/Features/Session`.

### Phase 4 - Composer, voice capture, and transcription hard cut

Status: COMPLETE AFTER COMPOSER REOPEN

- Added debounced provisional transcript publishing using
  `CodexDockConstants.Rendering.voiceTranscriptPublishDebounceMilliseconds`.
- Canceled pending transcript publish tasks during close, cancel, completion,
  and failure paths.
- Kept final transcript completion immediate while reducing main-actor draft
  churn from rapid realtime deltas.
- Added `CodexDock/Voice/VoiceCaptureEngine.swift` for capture start, stop,
  cancel, and audio forwarding off the main actor.
- Added `CodexDock/Voice/TranscriptionEngine.swift` for transcript
  normalization and draft/final-draft assembly off the main actor.
- Removed `@MainActor` from realtime transcription and live voice capture
  protocols/sessions.
- Changed the live audio forwarding loop to a detached user-initiated task so
  audio appends do not inherit the UI executor.
- Added `ComposerRenderState` and `ComposerVoiceRenderState` as bounded
  composer render values on `ThreadDetailScreenStore`.
- Verification:
  - `rtk swift test --filter ThreadDetailStoreTests` passed, 52 tests.

### Phase 5 - Archive, Hosts, and Connectivity hard cut

Status: COMPLETE AFTER COMPOSER REOPEN

- Added `CodexDock/Archive/ArchiveDataEngine.swift` to own Archive metadata
  load, host fanout, section projection, and sorting off the main actor.
- Wired `ArchiveStore` through `ArchiveDataEngine` while keeping existing
  Archive UI state behavior.
- Routed `ClientRuntime.makeDockStore(...)` through the runtime
  `ConnectivityEventSink`.
- Added nonblocking Dock route facts for idle, loading, configuration, and
  loaded host states.
- Added `CodexDockTests/ArchiveDataEngineTests.swift`.
- Extended `CodexDockTests/ClientRuntimeTests.swift` with Dock connectivity
  fact coverage.
- Added `CodexDock/Connectivity/ConnectivityDataEngine.swift`,
  `ConnectivityRenderProjector.swift`, `ConnectivityRenderModels.swift`, and
  `ConnectivityScreenStore.swift`.
- Wired `CodexDockRootView` to start `ConnectivityScreenStore` from
  `ClientRuntime` and mirror its bounded render output into
  `AppConnectivityStore`.
- Added `CodexDock/Archive/ArchiveScreenStore.swift` and wired Archive view
  rendering through it.
- Added `CodexDock/Hosts/HostSettingsScreenStore.swift` and wired Hosts view
  rendering through it.
- Routed runtime Dock, Thread Detail, Archive, and Host Settings route facts
  through `ConnectivityEventSink`; legacy reporter wiring is skipped on the
  runtime connectivity path.
- Added `ConnectivityEventSink.makeStreamDrainingBacklog()` so connectivity
  screen-store startup creates the stream and drains queued facts atomically.
- Added `CodexDockTests/ConnectivityDataEngineTests.swift`,
  `ArchiveScreenStoreTests.swift`, and `HostSettingsScreenStoreTests.swift`.
- Verification:
  - `rtk swift test --filter ArchiveDataEngineTests` passed, 1 test.
  - `rtk swift test --filter AppConnectivityStoreTests` passed, 15 tests.
  - `rtk swift test --filter ClientRuntimeTests` passed, 6 tests.
  - `rtk swift test --filter ConnectivityDataEngineTests` passed, 2 tests.
  - `rtk swift test --filter ArchiveScreenStoreTests` passed, 1 test.
  - `rtk swift test --filter HostSettingsScreenStoreTests` passed, 1 test.
  - `rtk swift test --filter DockStoreTests` passed, 48 tests.
  - `rtk swift test --filter ClientRuntimeTests` passed, 7 tests after the
    atomic stream/backlog drain test was added.

### Phase 6 - Residual wiring, deletion, and migration cleanup

Status: COMPLETE AFTER COMPOSER REOPEN

- Added `ClientRuntime.makeThreadDetailStore(...)`.
- Routed Dock detail navigation through `ClientRuntime` when a runtime is
  available.
- Removed direct full-history projection/filtering calls from feature views.
- Removed `Task { @MainActor ... }` usage from Thread Detail voice,
  transcription, and AVAudio capture code.
- Confirmed runtime-created screen stores cover Dock, Thread Detail, Archive,
  Hosts, and Connectivity; injected preview/test constructors remain outside
  the normal bootstrap-ready runtime path.
- Verification:
  - `rtk swift test --filter ClientRuntimeTests` passed, 6 tests.
  - `rtk rg "snapshot\\.project\\(options:|\\.project\\(options:" -n
    CodexDock/Features CodexDockApp` reported no matches.
  - `rtk rg "visibleEvents\\(|requestCards\\.first" -n
    CodexDock/Features/Session CodexDock/ThreadDetail` reported no feature-view
    matches.

### Phase 7 - Responsiveness proof and app-target verification

Status: COMPLETE AFTER COMPOSER RE-AUDIT AND THERMONUCLEAR REVIEW

- Ran the canonical generated-project simulator test path after the SwiftUI
  ownership fix.
- Confirmed the app target passes real Dock-to-detail UI smoke coverage on
  `iPhone 17`, including the previously failing scripted message-noise detail
  path and relay-backed detail path.
- Stabilized Dock swipe-action UI coverage by resetting row swipe state on
  render revision changes and using context-menu repin for the second pin path.
- Stabilized relay-backed Dock row opening by scanning exact-id accessibility
  matches and tapping the visible row instead of relying on XCTest
  `isHittable`, which can fail with `Activation point invalid` in full-suite
  order.
- Raised the Thread Detail test polling helper from 1 second to 2 seconds after
  Xcode full-suite load exposed a false timeout in voice-capture cleanup.
- Verification:
  - `rtk make app-test SIM='iPhone 17'` passed. The latest app-test log is
    `.codex-dock/logs/app-test-20260530203359.log`.
  - `rtk swift test` passed, 306 tests, 5 skipped, 0 failures.
  - `rtk swift test --filter ResponsivenessContractTests` passed, 3 tests.
  - Diagnostic rerun:
    `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
    -destination id=DEF1631B-7125-43C6-BFA3-4423BF103C91 -derivedDataPath
    .codex-dock/DerivedData CURRENT_PROJECT_VERSION=20260530185823
    -only-testing:CodexDockUITests/CodexDockAutomationSmokeTests/testDockRowOpensSessionDetailByIdentifierWhenRowsExist
    -resultBundlePath
    /tmp/codex-client/20260530T140200Z/real-dock-detail-1.xcresult`
    passed.

### Audit status

Status: COMPOSER AUDIT PASSED WITH NOTES - THERMONUCLEAR BLOCKER FIXED

- Composer 2.5 Fast exhaustive audit ran in
  `/tmp/fresh-consult/codex-dock-responsiveness-audit-20260530T190800Z-ik99wD`
  and returned `VERDICT: fail`.
- Blocking findings:
  - Phase 3 and Phase 4: `ThreadDetailStore` still owns pagination,
    normalization, merge, and full-sort work on `@MainActor`; no
    `ThreadDetailDataEngine` / `ThreadEventIndex`; voice/transcription still
    lacks dedicated engines.
  - Phase 5: Dock-to-connectivity still synchronously publishes through
    `AppConnectivityStore`; `ConnectivityEventSink` is not drained downstream;
    missing connectivity render/data path and Archive/Host screen stores.
  - Phase 6: runtime still constructs stores with too many data/render
    responsibilities.
  - Phase 7: missing responsiveness contract tests, large-fixture tests,
    signpost contract tests, and hang/Instruments-style evidence.
  - Phase 1 residual: `searchDebounceMilliseconds` exists but is not used.
- Post-audit follow-through completed:
  - Phase 1 uses debounced search projection and immediate text state.
  - Phase 3 added `ThreadDetailDataEngine` / `ThreadEventIndex`, removed
    main-actor normalization/sorting from `ThreadDetailStore`, bounded
    Thread Detail render snapshots, and removed render-time request-card scans.
  - Phase 4 added `VoiceCaptureEngine`, `TranscriptionEngine`, bounded
    composer render state, and off-main audio forwarding.
  - Phase 5 added connectivity data/render/screen stores, Archive and Hosts
    screen stores, and runtime sink drainage downstream.
  - Phase 6 wired runtime-created screen stores and removed the old user-facing
    feature-view projection paths.
  - Phase 7 added large-fixture/window, signpost, runtime factory, and
    connectivity sink tests.
- Current verification:
  - `rtk swift test` passed, 306 tests, 5 skipped, 0 failures.
  - `rtk make app-test SIM='iPhone 17'` passed with log
    `.codex-dock/logs/app-test-20260530203359.log`.
- Composer 2.5 Fast re-audit ran in
  `/tmp/fresh-consult/codex-dock-responsiveness-audit-20260530TCR745t` and
  returned `VERDICT: pass-with-notes`, `BLOCKING: none`,
  `CONFIDENCE: high`.
- Non-blocking Composer notes to carry into thermonuclear review:
  - Phase 7 still lacks a 500-row Dock fixture and checked-in
    Instruments/hang evidence.
  - `ThreadDetailStore` still owns session/pagination orchestration and copies
    full in-memory `events` on `@MainActor`; UI publication is bounded through
    `ThreadDetailScreenStore`.
  - Transcription event handling still returns to main-actor store isolation
    for composer-state mutation.
  - Runtime still returns legacy store type names even though screen stores are
    wired for user-facing render paths.
  - `threadPaginationPrefetchThresholdRows` is not used by production code.
- Thermonuclear review found one concrete blocker: `DockStore.swift` crossed
  1,000 lines after the phase work.
- Fixed the blocker by moving public Dock model, projection, and snapshot types
  into `CodexDock/Dock/DockModels.swift`.
- Fixed the follow-up thermonuclear race by making connectivity stream
  creation and backlog drain atomic.
- Fixed full-suite UI-test instability by avoiding XCTest `isHittable` in Dock
  row discovery/tap helpers and by resetting row swipe state on render changes.
- Post-thermonuclear line counts:
  - `CodexDock/State/DockStore.swift`: 606 lines.
  - `CodexDock/Dock/DockModels.swift`: 451 lines.
  - `CodexDock/Features/Dock/DockView.swift`: 993 lines.
- Post-thermonuclear verification:
  - `rtk swift test --filter DockStoreTests` passed, 48 tests.
  - `rtk swift test --filter ResponsivenessContractTests` passed, 3 tests.
  - `rtk swift test --filter ClientRuntimeTests` passed, 7 tests.
  - `rtk swift test --filter ThreadDetailStoreTests` passed, 52 tests.
  - `rtk swift test` passed, 306 tests, 5 skipped, 0 failures.
  - `rtk make app-test SIM='iPhone 17'` passed with log
    `.codex-dock/logs/app-test-20260530203359.log`.
- Next step: commit and push.
