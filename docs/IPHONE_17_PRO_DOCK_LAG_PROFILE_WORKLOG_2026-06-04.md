# iPhone 17 Pro Dock Lag Profile Worklog - 2026-06-04

## Scope

Diagnose severe UI lag on Amir's iPhone 17 Pro when Codex Dock is connected to
both the M5 relay and the home relay. The lag is especially visible while
scrolling, but it is also noticeable across normal app interactions.

This pass is diagnosis only. Do not apply performance repairs in this worklog's
scope. Instrumentation should be easy to disable for real builds and should not
log secrets, prompt text, transcript text, raw JSON-RPC payloads, bearer tokens,
or `OPENAI_API_KEY`.

## Known Device And Host Context

- Device: iPhone 17 Pro,
  `CB9FFF0E-89AD-57B5-9C00-6552D814875E`
- Last known installed build before this profiling pass: `20260604163222`
- Expected device hosts:
  - `amir-m5.fairy-salmon.ts.net:4510`
  - `home.fairy-salmon.ts.net:4510`
- User-visible symptom:
  - Scroll lag is frequent.
  - Lag is not limited to scroll; general app interactions feel delayed.

## 2026-06-04T16:42:14Z - Initial Code-Path Findings

The main Dock screen pipeline is a multi-stage path:

1. Each configured host has a `StreamReconciler`.
2. Each host snapshot reaches `DockStore.handleReconcilerSnapshot`.
3. `DockDataEngine.apply(snapshot, host:)` replaces that host's card array.
4. `DockDataEngine.snapshot(now:)` builds one combined Dock snapshot across
   hosts.
5. `DockStore.publishSnapshot()` publishes that combined snapshot to
   `DockScreenStore`.
6. `DockScreenStore.enqueueProjection(snapshot:)` moves render projection onto
   a detached task.
7. The `RenderCoalescer` drops superseded revisions and yields the newest
   render snapshot.
8. `DockScreenStore.start()` assigns `state = .loaded(renderSnapshot)` on the
   main actor.
9. SwiftUI renders the Dock rows.

Important source files already inspected:

- `CodexDock/Diagnostics/Logging.swift`
- `CodexDock/Configuration/CodexDockConstants.swift`
- `CodexDock/Dock/DockScreenStore.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/Dock/DockDataEngine.swift`
- `CodexDock/State/ThreadCardProjectionState.swift`
- `CodexDock/State/ThreadCardRowProjector.swift`
- `CodexDock/State/DockCardProjection.swift`

Early unproven hypotheses:

- Full combined Dock snapshots may be republished once per host event. With
  both `m5` and `home`, a burst from either side can cause repeated projection
  and SwiftUI updates over the combined row set.
- `ThreadCardRowProjector` may become expensive with high row counts. Its
  metadata fallback path can scan local metadata for each card if the exact
  `ThreadMetadataKey` lookup misses.
- `DockCardProjectionProjector.project()` does multiple full-row passes,
  sorting, grouping, and facet derivation. This may be enough to create frame
  pressure with large combined row counts even though it runs off the main
  actor.
- Main-actor publish may still be too heavy if SwiftUI receives large, frequent
  render snapshots. That would show up as scroll lag and general input lag.
- Relay catch-up/window updates may flood the client with snapshot revisions
  during connect or host refresh.

Next instrumentation targets:

- Per-host stream snapshot arrival rate, row counts, and apply duration.
- Combined snapshot generation duration and total row count.
- Metadata projection duration and metadata fallback scan counts.
- Dock card projection duration, sorted/grouped/facet counts, and active filter
  state.
- Render coalescer submit/yield/drop behavior by revision.
- Main-actor publish duration and frequency.
- SwiftUI Dock root/list update timing and visible-row appearance sampling.

## 2026-06-04T16:43:20Z - Scroll/UI Path Findings

The Dock screen uses an outer `ScrollView` and nested `LazyVStack` sections for
rows, pinned rows, grouped rows, and host status rows. It does not use `List` for
the main Dock surface.

That matters because each `DockScreenStore.state = .loaded(renderSnapshot)`
assignment can invalidate SwiftUI's view tree while the user is scrolling. If
host snapshots arrive frequently, a detached data projection is not enough by
itself; the final main-actor state replacement may still interrupt scrolling.

Additional UI cost to measure: `dockScreenValue` builds a long accessibility
value for the Dock root by collecting automation data from visible rows. In the
newest lens this can walk all projected rows, encode each row's automation
value, and concatenate the result. This is useful for tests, but on device it
may amplify the cost of every loaded-state render. This is a suspected cost
only, not yet proven.

Instrumentation additions from this finding:

- Log each loaded Dock render snapshot observed by `DockView`, including
  revision, total rows, visible rows, groups, pinned rows, lens, search state,
  and active filter count.
- Log a sampled `DockRowView.onAppear` stream so scroll appearance can be
  correlated with snapshot churn without logging every row forever.
- Measure accessibility row-value construction in `dockScreenValue` so it can
  be separated from normal row layout cost.

## 2026-06-04T16:50:51Z - Instrumentation Added

Added `CodexDock/Diagnostics/PerformanceProbe.swift`.

The profiler is off by default. It enables only when either:

- `CODEX_DOCK_PERFORMANCE_PROFILING=1`
- `CODEX_DOCK_UI_PROFILING=1`
- `Library/Application Support/CodexDock/performance-profiling.json` contains
  `"enabled": true`

This diagnostic pass temporarily tried a physical-device profiling config path.
That Makefile wiring was removed before the final commit after physical-phone
testing was stopped by user instruction. The final committed profiling launch
path is simulator/local only.

Instrumentation now covers:

- `AppServerThreadCardStreamConnection`: stream notification decode timing and
  subscribe/resync response row counts.
- `StreamReconciler.publish()`: sorted snapshot build timing, yield timing,
  row counts, revision, freshness, and buffered count.
- `DockStore`: host snapshot arrival, host snapshot handling duration,
  metadata alias migration duration, combined snapshot publish duration, and
  per-host synchronize duration.
- `DockDataEngine`: host apply duration, combined snapshot generation duration,
  metadata count, and host identity resolver duration.
- `DockRenderProjector`: row snapshot projection duration and render projection
  duration.
- `ThreadCardRowProjector`: per-host row projection duration, input card count,
  filtered-out count, metadata exact hits, metadata fallback hits, and metadata
  fallback misses.
- `DockCardProjectionProjector`: search, filter, pinned sort, body sort,
  visible sort, all-pinned sort, grouping, summary, facets, and total projection
  duration.
- `RenderCoalescer`: submitted revisions and stale revision drops.
- `DockScreenStore`: render enqueue, detached render completion, queue delay,
  and main-actor publish duration.
- `DockView` / `DockRowView`: loaded visible snapshot revisions, sampled row
  appearances, accessibility value construction duration, and iOS
  `CADisplayLink` frame hitch logs.

Validation so far:

```bash
rtk swift test --filter DockStoreTests
```

Result: passed. The command executed 57 selected tests with 0 failures.

## 2026-06-04T17:03:13Z - Simulator Evidence With Publish Cause

Relaunched simulator profiling after adding `last_kind`:

```bash
SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

Result: succeeded.

Filtered metrics now explicitly show catch-up pages and later heartbeats causing
stream publishes:

```text
stream_reconciler.publish last_kind=page rows=624 source_host_id=home
stream_reconciler.publish last_kind=page rows=978 source_host_id=home
stream_reconciler.publish last_kind=heartbeat rows=978 source_host_id=home
stream_reconciler.publish last_kind=heartbeat rows=268 source_host_id=Amir-M5
```

The UI still receives large visible revisions after those publishes:

```text
dock.view.loaded_revision rows=1246 visible_rows=1246 revision=14
dock.view.loaded_revision rows=1246 visible_rows=1246 revision=15
dock.view.loaded_revision rows=1246 visible_rows=1246 revision=16
```

The main-thread accessibility construction remains row-count scaled and over a
frame budget:

```text
dock.accessibility_value.built duration_ms=20 encoded_length=468819 rows=1246 visible_rows=1246
dock.accessibility_value.built duration_ms=21 encoded_length=468819 rows=1246 visible_rows=1246
dock.accessibility_value.built duration_ms=24 encoded_length=468819 rows=1246 visible_rows=1246
```

Frame hitches continue nearby:

```text
frame.hitch duration_ms=38 target_ms=17
frame.hitch duration_ms=50 target_ms=17
frame.hitch duration_ms=54 target_ms=17
frame.hitch duration_ms=56 target_ms=17
```

Interpretation update: this strengthens the hypothesis that even heartbeat
traffic can trigger visible-state churn across the full combined row set. The
most expensive measured main-thread cost remains `dockScreenValue`
accessibility/automation string generation, not detached card projection.

## 2026-06-04T16:53:55Z - Physical Install Blocked By Device State

Attempted profiling install:

```bash
rtk make iphone-17-pro DEVICE_PERFORMANCE_PROFILING=1
```

First attempt failed before build/install. Xcode reported:

```text
xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available
Device is busy (Connecting to Amir's iPhone)
```

Then `rtk make devices` showed the iPhone 17 Pro as available:

```text
Amir's iPhone  iPhone 17 Pro  CB9FFF0E-89AD-57B5-9C00-6552D814875E  available
```

Retried the same profiling install. It failed before build/install again. Xcode
reported:

```text
xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available
Amir's iPhone may need to be unlocked to recover from previously reported preparation errors
```

This is not physical phone evidence yet. Next step is to use simulator/local
validation to compile and exercise the iOS-only profiling code while the
physical device path is blocked.

## 2026-06-04T16:55:58Z - Simulator Profiling Evidence

Added simulator profiling launch support:

```bash
SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

Simulator build and launch succeeded. This validates that the iOS-only
`CADisplayLink` frame monitor compiles and that the `perf event=...` logs are
emitted. This is simulator evidence, not physical iPhone 17 Pro evidence.

The simulator connected to both configured hosts. Observed row counts:

- `amir-m5.fairy-salmon.ts.net:4510`: 268 rows
- `home.fairy-salmon.ts.net:4510`: 978 rows after catch-up
- Combined Dock rows: 1246 rows

Representative timing at 1246 combined rows:

```text
dock.data_engine.snapshot duration_ms=8 rows=1246
dock.card_projection.project duration_ms=6 rows=1246 visible_rows=1246 facets_ms=3 body_ms=1
dock.render.project duration_ms=7 rows=1246
dock.store.publish_snapshot duration_ms=8 model_ms=8 screen_publish_ms=0 rows=1246
dock.accessibility_value.built duration_ms=20 encoded_length=468819 rows=1246 visible_rows=1246
frame.hitch duration_ms=37-63 target_ms=17
```

Important interpretation:

- The detached data/render projection path is measurable but not the largest
  observed UI-thread cost in this sample. Combined snapshot projection and
  render projection were usually under 10 ms at 1246 rows.
- `dockScreenValue` accessibility construction is a main-thread cost and is
  repeatedly taking about 20 ms at 1246 visible rows. That alone exceeds a
  60 fps frame budget.
- The accessibility value is very large at 1246 rows:
  `encoded_length=468819`.
- Frame hitches are repeatedly logged near these large accessibility-value
  rebuilds, with observed hitch durations from 34 ms to 63 ms.
- The host streams continue to produce full combined publishes on heartbeat and
  update events. Even when a heartbeat carries zero rows, the client currently
  republishes a combined 1246-row Dock snapshot.

This does not yet prove the exact same timings on the physical iPhone 17 Pro,
but it gives a strong diagnosis target for the phone symptom: high-frequency
full-state publishes plus row-count-scaled main-thread accessibility work.

Still unproven and still worth measuring on the physical phone:

- Whether real-device row layout cost is worse than simulator row layout cost.
- Whether physical-device accessibility polling or VoiceOver-related behavior
  triggers even more frequent `dockScreenValue` recomputation.
- Whether the home relay catch-up burst feels worse on device because it adds
  repeated 500-1246 row publish/update cycles while the user is already
  interacting.

## 2026-06-04T16:57:42Z - Third Physical Install Attempt

Checked devices again:

```text
Amir's iPhone  iPhone 17 Pro  CB9FFF0E-89AD-57B5-9C00-6552D814875E  available
```

Retried:

```bash
rtk make iphone-17-pro DEVICE_PERFORMANCE_PROFILING=1
```

The install path still failed before build/install. Xcode reported:

```text
xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available
Device is busy (Connecting to Amir's iPhone)
```

Physical iPhone proof remains blocked by CoreDevice device-preparation state.
The instrumentation is ready for the phone path once the device can be prepared
by Xcode.

## 2026-06-04T16:58:17Z - Additional Validation

Because `AppServerThreadCardStreamClient` was instrumented at the decode and
subscribe/resync response boundary, ran:

```bash
rtk swift test --filter AppServerThreadCardStreamClientTests
```

Result: passed. The command executed 3 selected tests with 0 failures.

## 2026-06-04T17:00:53Z - CoreDevice Diagnostic After Retry

Retried the profiling install again:

```bash
rtk make iphone-17-pro DEVICE_PERFORMANCE_PROFILING=1
```

The install still failed before build/install:

```text
xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available
Device is busy (Connecting to Amir's iPhone)
```

Raw CoreDevice device listing showed the actual state:

```text
Amir's iPhone   Amirs-iPhone.coredevice.local   CB9FFF0E-89AD-57B5-9C00-6552D814875E   connecting    iPhone 17 Pro (iPhone18,1)
```

Raw CoreDevice app-info diagnostics also failed:

```text
ERROR: A connection to this device could not be established. (com.apple.dt.CoreDeviceError error 4000 (0xFA0))
Timed out while attempting to negotiate tunnel parameters (com.apple.dt.RemotePairingError error 1001 (0x3E9))
```

Interpretation: the physical proof is currently blocked below the app layer.
The Mac cannot complete CoreDevice tunnel negotiation with the iPhone 17 Pro, so
the profiling build cannot be installed or launched yet.

## 2026-06-04T17:02:25Z - Added Publish Cause Marker

Added `last_kind` to `stream_reconciler.publish` profiling logs. Future phone
or simulator traces can now show whether a full combined Dock publish was
triggered by a `snapshot`, `page`, `upsert`, `delete`, `heartbeat`, or
`resyncRequired` envelope.

This is diagnostic only. It does not change stream behavior, coalescing,
rendering, row counts, or UI update policy.

Validation:

```bash
rtk swift test --filter DockStoreTests
```

Result: passed. The command executed 57 selected tests with 0 failures.

## 2026-06-04T17:16:31Z - Scroll-Lag Symptom Added To The Diagnosis

User clarified that the lag often shows up as scroll lag, but also feels
noticeable across the whole app.

Interpretation: treat scrolling as a first-class symptom, not as a rename-only
or sync-only problem. The relevant hot paths while scrolling are:

- SwiftUI row creation/destruction as `LazyVStack` virtualizes rows.
- Per-row accessibility value construction through `row.automationValue`.
- The Dock header's large `dockScreenValue`, which includes every visible row's
  encoded automation value.
- Full Dock state publishes caused by host stream updates while the user is
  interacting with the list.

Added more diagnostic coverage:

- `dock.row.disappear` samples alongside `dock.row.appear`.
- `dock.scroll.offset` samples behind `CODEX_DOCK_PERFORMANCE_PROFILING`.
- Device profiling config fields:
  `rowDisappearSampleLimit`, `scrollSampleLimit`, and
  `scrollDeltaThresholdPoints`.
- The scroll probe is iOS-only and observes the underlying
  `UIScrollView.contentOffset`. It is inactive unless performance profiling is
  enabled.

Validation after the instrumentation changes:

```bash
rtk swift test --filter DockStoreTests
```

Result: passed. The command executed 57 selected tests with 0 failures.

Simulator relaunch:

```bash
SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

Result: succeeded.

Mobile MCP swiped the running iPhone 17 simulator. Screenshot evidence was
saved under `/tmp/codex-client/`:

- `/tmp/codex-client/20260604T1210Z-dock-profiler-before-scroll.png`
- `/tmp/codex-client/20260604T1210Z-dock-profiler-after-scroll.png`
- `/tmp/codex-client/20260604T1215Z-dock-profiler-after-uiscrollview.png`

Log slices were saved under `/tmp/codex-client/`:

- `/tmp/codex-client/20260604T1210Z-scroll-profiler.log`
- `/tmp/codex-client/20260604T1212Z-scroll-profiler-global.log`
- `/tmp/codex-client/20260604T1213Z-scroll-profiler-sentinel.log`
- `/tmp/codex-client/20260604T1215Z-scroll-profiler-uiscrollview.log`

Observed during simulator swipe windows:

```text
dock.row.appear ... revision=15 sample=1 ...
dock.scroll.offset delta_y=0 offset_y=-62 revision=15 rows=1246 sample=1 visible_rows=1246
dock.accessibility_value.built duration_ms=20 encoded_length=468825 revision=15 rows=1246 visible_rows=1246
frame.hitch duration_ms=35-65 target_ms=17
stream_reconciler.publish ... last_kind=heartbeat ... rows=268/978
dock.main_publish ... rows=1246 visible_rows=1246
```

Important interpretation:

- The scroll symptom is consistent with the profiler output. During the
  interaction window, row appearances and frame hitches occur while the Dock is
  still repeatedly rebuilding the large 468 KB accessibility value on the main
  thread.
- The offset observer now emits, but it did not produce useful movement deltas
  in the sampled run. The observed offset stayed at `-62`, so the current offset
  probe proves attachment but does not yet prove scroll velocity or distance.
- Even without clean offset deltas, the stronger evidence is still present:
  full 1,246-row publishes caused by `heartbeat` and `upsert` stream events
  trigger repeated `dock.accessibility_value.built` calls around 20 ms each,
  and frame hitches repeatedly land in the 35-65 ms range.
- A 20 ms main-thread accessibility build already exceeds the 16.7 ms frame
  budget for 60 fps. When it repeats several times after each publish, it can
  make both scrolling and general app interaction feel laggy.

Current diagnosis confidence:

- High confidence: the data/render projection work is not the dominant cost in
  the simulator samples. Detached projection remains mostly around 5-10 ms at
  1,246 rows.
- High confidence: the Dock header automation/accessibility string is a
  row-count-scaled main-thread cost and is currently large enough to cause
  visible frame hitches.
- Medium confidence: scroll-specific row virtualization adds additional hitch
  pressure, because row appearances occur during the swipe window.
- Low confidence: exact scroll velocity/distance measurement. The current
  offset probe attaches but needs another refinement if precise scroll
  velocity is required.

This is still diagnostic only. No repair has been applied to the UI/data
architecture.

## 2026-06-04T17:18:20Z - Physical iPhone 17 Pro Retry Still Blocked

Retried the profiling install with the richer scroll sampling config:

```bash
DEVICE_PERFORMANCE_PROFILING=1 DEVICE_PERFORMANCE_SCROLL_SAMPLE_LIMIT=300 rtk make iphone-17-pro
```

Result: failed before install. Xcode could not prepare the physical iPhone
destination:

```text
xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available
Device is busy (Connecting to Amir's iPhone)
```

Build log path:

```text
/Users/aelaguiz/workspace/codex-client/.codex-dock/logs/app-device-build-20260604171710-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log
```

Physical iPhone proof remains blocked below the app layer. The Mac/Xcode
CoreDevice path still cannot make the iPhone 17 Pro available as a destination,
so the new instrumentation has not yet been installed on the physical phone.

## 2026-06-04T17:35:43Z - Corrected Scroll Proof With XCTest Drag

The earlier Mobile MCP swipe evidence was not strong enough. Screenshots changed
after those swipes, but the scroll offset did not move, and live Dock updates
could explain the visible row changes. I treated that as a simulator gesture
proof limitation, not as scroll evidence.

Refined the profiling-only scroll instrumentation:

- The `UIScrollView` observer now retries attachment for longer and prefers the
  largest genuinely scrollable window-level scroll view over an enclosing
  non-scrollable container.
- Added a separate SwiftUI geometry probe with `source=swiftui_geometry`, so
  future logs can separate SwiftUI content movement from UIKit scroll-view
  movement.
- Split scroll offset tracking by `source`, so an early bad sample from one
  probe cannot pollute deltas from another probe.
- Added `CodexDockUITests/CodexDockPerformanceScrollUITests.swift`, a
  diagnosis-only UI test that launches the app with
  `CODEX_DOCK_PERFORMANCE_PROFILING=1` and uses XCTest's drag gesture against
  the app window.

Validation after the probe changes:

```bash
rtk swift test --filter DockStoreTests
```

Result: passed. The command executed 57 selected tests with 0 failures.

```bash
git diff --check
```

Result: passed.

Simulator proof command:

```bash
CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled'
```

Result: passed.

Focused log artifact:

```text
/tmp/codex-client/20260604T_xctest_scroll_perf.log
```

Extracted stats from that log:

```json
{
  "scrollSamples": 107,
  "firstScrollOffset": -62,
  "lastScrollOffset": 1912,
  "minScrollOffset": -62,
  "maxScrollOffset": 1912,
  "minContentHeight": 546,
  "maxContentHeight": 184551,
  "accessibilityMs": { "count": 560, "min": 4, "max": 25, "avg": 19 },
  "frameHitchMs": { "count": 266, "min": 34, "max": 91, "avg": 43 },
  "streamPublishMs": { "count": 147, "min": 0, "max": 11, "avg": 4 },
  "mainPublishMs": { "count": 145, "min": 0, "max": 17, "avg": 0 }
}
```

Key scroll-window facts from the log:

```text
perf event=dock.scroll.offset bounds_height=874 content_height=184551 delta_y=16 offset_y=-46 revision=18 rows=1246 sample=3 source=uiscrollview visible_rows=1246
...
perf event=dock.scroll.offset bounds_height=874 content_height=184250 delta_y=17 offset_y=1912 revision=20 rows=1246 sample=107 source=uiscrollview visible_rows=1246
```

Observed while real scrolling was happening:

- The actual scrolling list is enormous: about `184,000` points of content
  height for `1,246` rows.
- Real scroll offset moved from about `-62` to `1,912`, so this run did prove
  actual list movement.
- Frame hitches continued during and after scroll. Worst observed hitch in the
  focused log was `91 ms`; many hitches were `34-60 ms`.
- `dock.accessibility_value.built` still ran repeatedly on the main thread at
  about `20 ms` for the full `1,246`-row Dock automation payload.
- Host stream events continued during the scroll window. A representative
  heartbeat/upsert caused `stream_reconciler.publish`, `dock.main_publish`,
  then repeated accessibility value rebuilds.

Updated diagnosis:

- The general lag and the scroll lag have the same main driver: every frequent
  Dock publish makes SwiftUI/Accessibility rebuild a huge Dock-level automation
  value containing all visible rows. At `1,246` rows, that encoded payload is
  about `468 KB` and costs about `20 ms` per build on the simulator main
  thread.
- Scroll adds more pressure because row virtualization creates/destroys rows
  while the list is moving, but the profile does not point to row virtualization
  as the root cause by itself.
- The data/render pipeline is still not the dominant cost in these samples.
  Stream publish is usually `0-11 ms` off the main thread, while the
  user-visible hitches line up with main-thread accessibility work.
- The app can hitch even while idle because home and M5 heartbeats/upserts keep
  causing full Dock publishes with no meaningful visible change.

Current confidence after corrected scroll proof:

- High confidence: the user-visible lag is mainly a main-thread accessibility /
  automation payload scaling problem, triggered repeatedly by full Dock
  publishes.
- High confidence: actual scrolling is happening against a very large
  `UIScrollView` content height, and hitches occur during that real scroll.
- Medium confidence: reducing unnecessary publishes or avoiding unchanged
  main-thread automation rebuilds would materially improve both idle and scroll
  feel.
- Still missing: physical iPhone 17 Pro profiling logs, because the Xcode
  CoreDevice destination remains unavailable.

This remains diagnostic only. No performance repair has been applied.

## 2026-06-04T17:36:54Z - Physical iPhone 17 Pro Installed But Launch Blocked By Lock

Retried the physical iPhone 17 Pro profiling path after the corrected scroll
instrumentation and XCTest proof:

```bash
DEVICE_PERFORMANCE_PROFILING=1 DEVICE_PERFORMANCE_SCROLL_SAMPLE_LIMIT=300 rtk make iphone-17-pro
```

Result: failed at device launch, after getting past the earlier CoreDevice
destination-availability blocker.

Exact launch blocker:

```text
ERROR: The application failed to launch. (com.apple.dt.CoreDeviceError error 10002 (0x2712))
BundleIdentifier = com.aelaguiz.CodexDockApp
The request to open "com.aelaguiz.CodexDockApp" failed. (FBSOpenApplicationServiceErrorDomain error 1 (0x01))
BSErrorCodeDescription = RequestDenied
NSLocalizedFailureReason = The request was denied by service delegate (SBMainWorkspace) for reason: Locked ("Unable to launch com.aelaguiz.CodexDockApp because the device was not, or could not be, unlocked").
The operation couldn’t be completed. Unable to launch com.aelaguiz.CodexDockApp because the device was not, or could not be, unlocked. (FBSOpenApplicationErrorDomain error 7 (0x07))
```

Launch log path:

```text
/Users/aelaguiz/workspace/codex-client/.codex-dock/logs/device-launch-20260604173631-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log
```

The command output indicates the device install path reached launch, so the
profiled app build and profiling config may already be on the iPhone 17 Pro.
However, there is still no physical phone performance proof because the app did
not launch and no on-device scroll logs were collected.

## 2026-06-04T17:44:28Z - Normal App Idle Pass Without XCTest

Ran a normal simulator pass with profiling enabled and no XCTest-driven UI
sampling. This was to separate real app work from possible accessibility queries
caused by UI tests.

Command:

```bash
SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

Result: passed. After launch, I left the simulator app untouched and collected
logs.

Log artifacts:

```text
/tmp/codex-client/20260604T_normal_idle_perf.log
/tmp/codex-client/20260604T_normal_idle_postload_perf.log
```

Untouched 60-second normal-app slice:

```json
{
  "dock_accessibility_value_built": { "count": 138, "min": 4, "max": 24, "avg": 18 },
  "frame_hitch": { "count": 48, "min": 34, "max": 63, "avg": 43 },
  "stream_reconciler_publish": { "count": 38, "min": 0, "max": 11, "avg": 4 },
  "dock_main_publish": { "count": 37, "min": 0, "max": 15, "avg": 1 },
  "dock_render_project": { "count": 37, "min": 4, "max": 8, "avg": 6 },
  "dock_card_projection_project": { "count": 37, "min": 3, "max": 8, "avg": 5 },
  "dock_data_engine_snapshot": { "count": 37, "min": 3, "max": 9, "avg": 7 },
  "encodedLength": { "count": 138, "min": 103983, "max": 468821 },
  "rows": { "count": 138, "min": 268, "max": 1246 },
  "streamKinds": { "none": 4, "snapshot": 2, "heartbeat": 22, "page": 8, "upsert": 2 },
  "sourceHosts": { "none": 4, "Amir-M5": 14, "home": 20 }
}
```

Untouched post-load 20-second slice, after the Dock had reached `1,246` rows:

```json
{
  "dock_accessibility_value_built": { "count": 36, "min": 20, "max": 24, "avg": 21 },
  "frame_hitch": { "count": 16, "min": 36, "max": 61, "avg": 43 },
  "stream_reconciler_publish": { "count": 9, "min": 1, "max": 10, "avg": 5 },
  "dock_main_publish": { "count": 9, "min": 0, "max": 0, "avg": 0 },
  "dock_render_project": { "count": 9, "min": 6, "max": 8, "avg": 7 },
  "dock_card_projection_project": { "count": 9, "min": 6, "max": 7, "avg": 7 },
  "dock_data_engine_snapshot": { "count": 9, "min": 8, "max": 11, "avg": 9 },
  "encodedLength": { "count": 36, "min": 468821, "max": 468821 },
  "rows": { "count": 36, "min": 1246, "max": 1246 },
  "streamKinds": { "heartbeat": 8, "upsert": 1 },
  "sourceHosts": { "Amir-M5": 5, "home": 4 }
}
```

Interpretation:

- This proves the main-thread accessibility cost is not just XCTest asking for
  accessibility values. The untouched running app still repeatedly rebuilt the
  full `468,821` character row payload.
- In the clean post-load idle slice, `9` host stream publishes caused `36`
  accessibility rebuilds. That is about 4 giant string rebuilds per publish.
- The post-load rebuild cost was steady: `20-24 ms`, average `21 ms`.
- The app logged `16` frame hitches in the same 20-second idle slice, with a
  worst hitch of `61 ms`.
- Detached render/data work remained lower than the main-thread symptom:
  `dock.render.project` averaged `7 ms`, `dock.card_projection.project`
  averaged `7 ms`, and `dock.data_engine.snapshot` averaged `9 ms`.

Updated diagnosis:

- High confidence increased: the lag driver is present in normal app runtime,
  not only during XCTest proof capture.
- The Dock is doing full UI publish work on frequent heartbeat events even when
  no visible row data meaningfully changes.
- The expensive work is then amplified by `dockScreenValue`, which encodes
  every visible row for the Dock header accessibility value on each loaded-body
  evaluation.

Physical iPhone evidence update:

Verified the physical iPhone relay host config:

```bash
rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E DEVICE_RELAY_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510'
```

Result:

```text
verified CB9FFF0E-89AD-57B5-9C00-6552D814875E config hosts=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
```

Tried to read back the profiling config from the physical app container:

```text
Library/Application Support/CodexDock/performance-profiling.json
```

Result: failed below the app layer. Diagnostic log:

```text
.codex-dock/logs/device-performance-profiling-readback-20260604T1742Z.log
```

Exact error:

```text
ERROR: A connection to this device could not be established. (com.apple.dt.CoreDeviceError error 4000 (0xFA0))
Timed out while attempting to negotiate tunnel parameters (com.apple.dt.RemotePairingError error 1001 (0x3E9))
```

Physical phone performance proof is still missing. The latest evidence from the
phone path proves the relay host config is present, but it does not prove the
profiling config readback or any on-device runtime hitches.

## 2026-06-04T17:57:11Z - Host-Split Idle Scale Pass

Added a simulator launch override so one-host scale tests can run without
rewriting the saved host config:

```bash
SIM_LAUNCH_HOSTS='amir-m5.fairy-salmon.ts.net:4510' SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
SIM_LAUNCH_HOSTS='home.fairy-salmon.ts.net:4510' SIM_PERFORMANCE_PROFILING=1 FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

The override is diagnostic-only. With `SIM_LAUNCH_HOSTS` unset, the existing
simulator launch path still uses `.codex-dock/host.env`.

Log artifacts:

```text
/tmp/codex-client/20260604T_m5_only_idle_postload_perf.log
/tmp/codex-client/20260604T_home_only_idle_postload_perf.log
/tmp/codex-client/20260604T_normal_idle_postload_perf.log
```

Steady-state comparison after each run reached its maximum row count:

```text
M5 only
  maxRows: 269
  accessibility duration count/min-max/avg: 24 / 4-5 / avg 4
  accessibility encoded count/min-max/avg: 24 / 103983-104371 / avg 104355
  frame hitch duration count/min-max/avg: none
  stream publish duration count/min-max/avg: 8 / 1-3 / avg 2
  render project duration count/min-max/avg: 8 / 2-3 / avg 2
  data snapshot duration count/min-max/avg: 8 / 2-3 / avg 2
  main publish duration count/min-max/avg: 8 / 0-0 / avg 0
  streamKinds: upsert 2, heartbeat 6
  sourceHosts: Amir-M5 8

home only
  maxRows: 978
  accessibility duration count/min-max/avg: 40 / 15-18 / avg 16
  accessibility encoded count/min-max/avg: 40 / 349171-364837 / avg 364054
  frame hitch duration count/min-max/avg: 13 / 34-59 / avg 44
  stream publish duration count/min-max/avg: 13 / 6-10 / avg 9
  render project duration count/min-max/avg: 13 / 5-8 / avg 6
  data snapshot duration count/min-max/avg: 13 / 6-8 / avg 7
  main publish duration count/min-max/avg: 13 / 0-0 / avg 0
  streamKinds: page 1, heartbeat 11, upsert 1
  sourceHosts: home 13

both hosts
  maxRows: 1246
  accessibility duration count/min-max/avg: 36 / 20-24 / avg 21
  accessibility encoded count/min-max/avg: 36 / 468821-468821 / avg 468821
  frame hitch duration count/min-max/avg: 16 / 36-61 / avg 43
  stream publish duration count/min-max/avg: 8 / 1-10 / avg 5
  render project duration count/min-max/avg: 9 / 6-8 / avg 7
  data snapshot duration count/min-max/avg: 9 / 8-11 / avg 9
  main publish duration count/min-max/avg: 9 / 0-0 / avg 0
  streamKinds: upsert 1, heartbeat 7
  sourceHosts: Amir-M5 4, home 4
```

Interpretation:

- `M5` alone is comparatively smooth. With about `269` rows, rebuilding the
  Dock header accessibility value costs only `4-5 ms`, and this slice did not
  log frame hitches.
- `home` alone reproduces the noticeable lag pattern. With `978` rows, the same
  main-thread accessibility value rebuild costs `15-18 ms`, and the app logs
  `34-59 ms` frame hitches while idle.
- Both hosts increase the same cost to `20-24 ms` with `1,246` rows and a
  `468,821` character accessibility payload.
- This makes the diagnosis more specific: the problem scales with total visible
  row payload. It is not only a dual-host merge problem, and it is not only a
  scroll gesture problem. Scroll makes the issue easy to see because it competes
  with the same main thread, but idle host updates can trigger the same hitches.

Updated confidence:

- Very high confidence: the dominant user-visible lag comes from repeated
  main-thread SwiftUI/accessibility work proportional to all visible Dock rows.
- Medium confidence: unnecessary publishes on `heartbeat` and unchanged stream
  updates multiply that cost. The host-split pass still shows repeated full
  rebuilds on heartbeats.
- Lower confidence until the phone is available: exact physical iPhone 17 Pro
  timings. Simulator evidence shows the mechanism, but physical runtime logs are
  still missing because CoreDevice/device unlock failures blocked collection.

## 2026-06-04T18:03:45Z - Physical iPhone Retry

Checked physical devices:

```bash
rtk make devices
```

Result:

```text
Amir's iPhone  iPhone 17 Pro  CB9FFF0E-89AD-57B5-9C00-6552D814875E  available
iPhone         iPhone 14      0A4EFF8B-54D8-58FB-B3FB-63263265B9CC  unavailable
iPhone (5)     iPhone 13 Pro  DA37BD8A-A4EA-5377-937F-AB9EFC324F96  unavailable
```

Retried physical install/launch with profiling enabled:

```bash
DEVICE_PERFORMANCE_PROFILING=1 DEVICE_PERFORMANCE_SCROLL_SAMPLE_LIMIT=300 rtk make iphone-17-pro
```

Result: failed before app launch. Diagnostic log:

```text
.codex-dock/logs/app-device-build-20260604180008-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log
```

Exact failure:

```text
xcodebuild: error: Timed out waiting for all destinations matching the provided destination specifier to become available

	Ineligible destinations for the "CodexDockApp" scheme:
		{ platform:iOS, arch:arm64, id:00008150-00054DEC1461401C, name:Amir's iPhone, error:Device is busy (Connecting to Amir's iPhone) }
```

Tried physical log collection:

```bash
rtk make device-logs DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E
```

Result:

```text
log: Must be root to collect logs from attached device
```

Retried physical app-container config readback:

```bash
rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E DEVICE_RELAY_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510'
```

Result: failed below the app layer. Diagnostic log:

```text
.codex-dock/logs/device-config-verify-20260604180130-CB9FFF0E-89AD-57B5-9C00-6552D814875E.log
```

Exact failure:

```text
ERROR: A connection to this device could not be established. (com.apple.dt.CoreDeviceError error 4000 (0xFA0))
       ----------------------------------------
           Timed out while attempting to negotiate tunnel parameters (com.apple.dt.RemotePairingError error 1001 (0x3E9))
```

Checked Mobile MCP as an alternate physical route. It reported the real phone as
online:

```text
{"id":"00008150-00054DEC1461401C","name":"Amir's iPhone","platform":"ios","type":"real","version":"26.3.1","state":"online"}
```

Tried to launch `com.aelaguiz.CodexDockApp` through Mobile MCP. Result:

```text
iOS tunnel is not running, please see https://github.com/mobile-next/mobile-mcp/wiki/. Please fix the issue and try again.
```

Interpretation:

- Physical iPhone runtime proof is still missing.
- The repeated blocker is below Codex Dock: Xcode/CoreDevice cannot consistently
  negotiate the iOS device tunnel, physical log collection requires root, and
  Mobile MCP says its iOS tunnel is not running.
- Simulator evidence still strongly identifies the mechanism, but the exact
  iPhone 17 Pro runtime timing remains uncollected.

## 2026-06-04T18:05:46Z - Physical Testing Stopped By Request

Amir explicitly stopped further physical phone testing:

```text
stop trying to test on the physical phone
```

No additional iPhone 17 Pro install, launch, log, config-readback, or Mobile MCP
attempts should be made for this diagnostic pass unless Amir asks for them
again. The remaining proof standard is now simulator runtime evidence plus
source-level instrumentation coverage.

Instrumentation toggle audit:

- `PerformanceProbe.configuration.enabled` defaults to `false`.
- Simulator profiling turns on only through launch environment such as
  `CODEX_DOCK_PERFORMANCE_PROFILING=1`, wired by
  `SIM_PERFORMANCE_PROFILING=1`.
- App-container profiling can still be enabled if a
  `Library/Application Support/CodexDock/performance-profiling.json` file with
  `"enabled": true` already exists, but the final Makefile no longer writes
  that file to physical devices in this pass.
- `PerformanceProbe.event(...)` returns immediately when disabled.
- `PerformanceFrameMonitor.startIfNeeded()` also returns immediately unless the
  probe is enabled.

Important distinction:

- The probe logging is diagnostic and off by default.
- The expensive `dockScreenValue` construction is not diagnostic overhead. It is
  existing app work, because `DockView` attaches
  `.accessibilityValue(dockScreenValue)` in normal UI construction.
- When the Dock is loaded, `dockScreenValue` walks all automation-visible rows,
  builds `rowValues`, joins the full payload, and returns one large header
  accessibility value. The probe only measures that cost; it does not create the
  cost.

Completion status after this boundary change:

- Deep simulator instrumentation is present across stream ingest, reconciler
  publish, data engine, render projection, screen publish, row lifecycle,
  scroll offsets, accessibility value construction, and frame hitches.
- Worklog evidence identifies the dominant lag mechanism and the scale
  relationship: larger visible Dock row payloads cause larger main-thread
  accessibility rebuilds, which align with frame hitches.
- Further physical proof is intentionally stopped by user instruction, not by a
  decision to ignore that path.

## 2026-06-04T18:08:08Z - Final Simulator Proof After Physical Stop

Ran the relevant no-phone checks:

```bash
git diff --check
rtk make help
rtk swift test --filter DockStoreTests
CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled'
```

Results:

- `git diff --check`: passed.
- `rtk make help`: passed and shows the simulator profiling / diagnostic host
  commands.
- `rtk swift test --filter DockStoreTests`: passed, `57` selected tests, `0`
  failures.
- Simulator UI performance proof: passed.

Collected fresh simulator performance logs after the UI proof:

```text
/tmp/codex-client/20260604T_final_sim_ui_perf.log
```

Full fresh capture:

```text
dock_accessibility_value_built: count 94, min 4, max 22, avg 16
  rows: count 94, min 269, max 1247, avg 992
  encodedLength: count 94, min 104373, max 469211, avg 374054
dock_card_projection_project: count 26, min 2, max 9, avg 5
dock_data_engine_snapshot: count 26, min 3, max 12, avg 7
dock_main_publish: count 26, min 0, max 4, avg 1
dock_render_project: count 26, min 3, max 10, avg 6
dock_scroll_offset: count 144
  offsetY: min -62, max 2570
  contentHeight: min 546, max 185185
frame_hitch: count 50, min 34, max 103, avg 53
stream_reconciler_publish: count 27, min 0, max 10, avg 3
streamKinds: none 4, snapshot 2, page 8, upsert 2, heartbeat 11
sourceHosts: none 4, Amir-M5 8, home 15
scrollSources: swiftui_geometry 1, uiscrollview 143
```

Steady-state slice at the loaded maximum of `1,247` rows:

```text
dock_accessibility_value_built: count 46, min 20, max 22, avg 20
  rows: count 46, min 1247, max 1247, avg 1247
  encodedLength: count 46, min 469211, max 469211, avg 469211
dock_card_projection_project: count 12, min 6, max 9, avg 7
dock_data_engine_snapshot: count 12, min 8, max 12, avg 9
dock_main_publish: count 12, min 0, max 4, avg 1
dock_render_project: count 12, min 7, max 10, avg 8
dock_scroll_offset: count 144
  offsetY: min -62, max 2570
  contentHeight: min 546, max 185185
frame_hitch: count 50, min 34, max 103, avg 53
```

Final diagnostic conclusion:

- The data/projection pipeline is measurable but not the dominant visible lag:
  steady-state `dock.render.project` averaged `8 ms`, `dock.data_engine.snapshot`
  averaged `9 ms`, and `dock.main_publish` averaged `1 ms`.
- The repeated main-thread accessibility value build is the most direct
  measured offender: at `1,247` rows it builds a `469,211` character payload in
  `20-22 ms`, repeatedly.
- Frame hitches occur in the same runtime window, including a fresh max hitch of
  `103 ms`.
- Scroll lag is a symptom of the same main-thread pressure. The app logs hitches
  during loaded/idle update windows too, so the issue is broader than gesture
  handling.
- The likely repair path is to stop building the full all-row automation payload
  as a normal SwiftUI accessibility value and to suppress full Dock publishes
  for heartbeat/no-visible-change events. That repair is intentionally not made
  in this diagnostic pass.

## 2026-06-04T20:50:32Z - Simulator Proof After JSON Snapshot Cutover

Physical-phone testing stayed stopped per user instruction. The proof below is
simulator/local only.

Implemented repair summary:

- Deleted the root `rowValues=` proof payload from normal Dock accessibility
  value construction.
- Moved Dock row proof into a test-only JSON snapshot file written before the
  root advertises `automationRevision`.
- Added equality gates so unchanged Dock snapshots/options do not create new
  screen revisions and unchanged `.loaded` snapshots do not republish through
  `DockStore`.
- Moved collapse state into `DockProjectionOptions` so production rendering and
  proof rows use one projection-owned row-selection contract.
- Made client-side rename UI optimistic/non-blocking as part of the earlier
  rename latency work in this branch.
- Fixed `rtk make app-test` snapshot lookup for Xcode's simulator data
  container swaps: Makefile writes a simulator-visible config, and UI tests
  choose the candidate container that actually contains the advertised snapshot
  JSON file.

Commands run:

```bash
rtk xcodegen generate --spec project.yml
rtk swift test --filter DockScreenStoreTests
rtk swift test --filter DockRenderProjectorTests
rtk swift test --filter DockStoreTests
rtk npm run test:relay
rtk git diff --check
CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled'
```

Results:

- `rtk xcodegen generate --spec project.yml`: passed.
- `rtk swift test --filter DockScreenStoreTests`: passed, `6` selected tests,
  `0` failures.
- `rtk swift test --filter DockRenderProjectorTests`: passed, `6` selected
  tests, `0` failures.
- `rtk swift test --filter DockStoreTests`: passed, `57` selected tests, `0`
  failures.
- `rtk npm run test:relay`: passed, `195` tests, `0` failures.
- `rtk git diff --check`: passed.
- Simulator UI performance proof: passed. Xcode log:
  `.codex-dock/logs/app-test-20260604204929.log`.

Fresh simulator performance evidence at the same `1,247` row load:

```text
perf event=dock.accessibility_value.built duration_ms=0 encoded_length=292 revision=11 rows=1247 visible_rows=1247
perf event=dock.accessibility_value.built duration_ms=0 encoded_length=292 revision=12 rows=1247 visible_rows=1247
perf event=dock.main_publish automation_snapshot=true duration_ms=11 groups=0 hosts=2 pinned_rows=0 revision=12 rows=1247 visible_rows=1247
perf event=dock.card_projection.project all_pinned_ms=0 all_pinned_rows=0 automation_rows=1247 body_ms=1 body_rows=1247 checking_hosts=0 duration_ms=8 facets_ms=4 filter_ms=1 filtered_rows=1247 filters=0 groups=0 groups_ms=0 hosts=2 lens=newest partial=false pinned_ms=0 pinned_rows=0 rows=1247 search=false search_ms=0 searched_rows=1247 summary_ms=0 visible_ms=1 visible_rows=1247
```

Comparison to the diagnostic baseline:

```text
Before:
dock_accessibility_value_built: rows=1247, encodedLength=469211, min=20 ms, max=22 ms, avg=20 ms

After:
dock.accessibility_value.built: rows=1247, encoded_length=292, duration_ms=0
```

Conclusion:

- The specific measured root cause is fixed in the simulator path. The Dock root
  no longer rebuilds a giant all-row accessibility string during normal SwiftUI
  rendering.
- The proof channel remains strict through JSON snapshots; it does not fall
  back to visual scraping or root `rowValues=`.
- The logs still show occasional frame hitches during the run, so this evidence
  should not be read as "every possible hitch is gone." It proves the dominant
  root accessibility payload bottleneck found in this worklog is gone.

## 2026-06-04T21:00:00Z - Final Simulator Proof After Code-Quality Split

Physical-phone testing remains stopped by user instruction. This proof is
simulator/local only.

After the thermo-nuclear code-quality review found that the implementation had
grown two already-large files, the scroll probe and UI-test JSON snapshot reader
were split into focused files:

- `CodexDock/Features/Dock/DockScrollOffsetProbe.swift`
- `CodexDockUITests/DisplayedUIDockAutomationSnapshotSupport.swift`

Final commands run after that split:

```bash
rtk xcodegen generate --spec project.yml
rtk swift test --filter DockScreenStoreTests
rtk swift test --filter DockRenderProjectorTests
rtk swift test --filter DockStoreTests
rtk swift test --filter AppServerThreadCardStreamClientTests
rtk swift test --filter RenderCoalescerTests
rtk npm run test:relay
rtk git diff --check
CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled'
```

Results:

- `rtk xcodegen generate --spec project.yml`: passed.
- `rtk swift test --filter DockScreenStoreTests`: passed, `6` selected tests,
  `0` failures.
- `rtk swift test --filter DockRenderProjectorTests`: passed, `6` selected
  tests, `0` failures.
- `rtk swift test --filter DockStoreTests`: passed, `57` selected tests, `0`
  failures.
- `rtk swift test --filter AppServerThreadCardStreamClientTests`: passed, `3`
  selected tests, `0` failures.
- `rtk swift test --filter RenderCoalescerTests`: passed, `3` selected tests,
  `0` failures.
- `rtk npm run test:relay`: passed, `195` tests, `0` failures.
- `rtk git diff --check`: passed.
- Simulator UI performance proof: passed on the `iPhone 17` simulator. Result
  bundle:
  `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.06.04_15-59-03--0500.xcresult`.
  Xcode test result:
  `CodexDockPerformanceScrollUITests/testDockScrollGestureRunsWithPerformanceProfilingEnabled()`
  passed in `26.796s`.

Fresh simulator performance evidence at `1,248` Dock rows:

```text
perf event=dock.card_projection.project all_pinned_ms=0 all_pinned_rows=0 automation_rows=1248 body_ms=1 body_rows=1248 checking_hosts=0 duration_ms=8 facets_ms=4 filter_ms=1 filtered_rows=1248 filters=0 groups=0 groups_ms=0 hosts=2 lens=newest partial=false pinned_ms=0 pinned_rows=0 rows=1248 search=false search_ms=1 searched_rows=1248 summary_ms=0 visible_ms=1 visible_rows=1248
perf event=dock.main_publish automation_snapshot=true duration_ms=30 groups=0 hosts=2 pinned_rows=0 revision=9 rows=1248 visible_rows=1248
perf event=dock.accessibility_value.built duration_ms=0 encoded_length=289 revision=9 rows=1248 visible_rows=1248
perf event=dock.store.publish_snapshot context=handleReconcilerSnapshot duration_ms=9 hosts=2 model_ms=9 partial=false pending_rename_ms=0 pending_renames=0 published=true rows=1248 screen_publish_ms=0
perf event=dock.store.publish_snapshot context=handleReconcilerSnapshot duration_ms=10 hosts=2 model_ms=9 partial=false pending_rename_ms=0 pending_renames=0 published=false rows=1248 screen_publish_ms=1
```

Final comparison:

```text
Before:
dock_accessibility_value_built: rows=1247, encodedLength=469211, min=20 ms, max=22 ms, avg=20 ms

After:
dock.accessibility_value.built: rows=1248, encoded_length=289, duration_ms=0
```

Conclusion:

- The old root `rowValues=` bottleneck is gone from the tested simulator path.
- Full-row proof is still strict, but it now lives in the test-only JSON
  snapshot file instead of the root accessibility value.
- `screen_publish_ms=0-1` during repeated `1,248`-row publish/no-op windows,
  so the new no-op gate is not moving the old problem into screen publishing.
- Frame hitches can still come from other UI/runtime work, so this is not proof
  that every possible hitch is gone. It is proof that the measured root
  accessibility payload offender is gone.
