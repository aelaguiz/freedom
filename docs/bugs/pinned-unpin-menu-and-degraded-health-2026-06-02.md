---
title: Pinned unpin menu instability and degraded health on clean rebuild
date: 2026-06-02
status: root-cause-found
owners:
  - Codex
reviewers: []
related:
  - ./pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md
  - ../CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md
  - ../CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md
  - ../CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md
---

# Pinned Unpin Menu And Degraded Health

## TL;DR

<!-- bugs:block:tldr -->

Symptom: On Amir's physical iPhone 17 Pro after app startup, five pinned rows were visible. Two could be unpinned, then the remaining three were stuck. Swiping a pinned row no longer reliably exposed the `Unpin` action; sometimes the action appeared briefly and disappeared before it could be tapped. The same clean rebuild also showed partially connected health: Dock feed degraded, thread detail degraded, archive degraded, voice degraded, and diagnostics degraded.

Impact: Pinned rows can become effectively impossible to unpin from the primary Dock UI, and the system health UI can report broad degradation even after relays were restarted, making it unclear whether the client is live, stale, or only partially connected.

Most likely cause: two separate client-side problems. First, the pinned section is a custom `UICollectionView` bridge that calls `reloadData()` on every SwiftUI update; live Dock updates or height/layout updates during a swipe can close UIKit swipe actions, matching the "menu pops in and out" symptom. Second, the health UI is treating a capped Dock row window (`Home: Showing 250 of 964`) as global service degradation, then applying that same fallback to Dock feed, thread detail, archive, voice, and diagnostics when no route evidence has been loaded.

Next action: review the cross-linked architecture plan before implementing. Do not patch production code yet. The physical iPhone 17 Pro is explicitly out of scope for remote commands.

Status: root cause found; fix not implemented.

<!-- /bugs:block:tldr -->

## Bug North Star

The app should let a user unpin any visible pinned Dock row with a stable, tappable action. Live stream updates, route-health refreshes, layout recalculation, worker activity, or startup recovery should not make the swipe action disappear before the user can tap it.

The health UI should distinguish "relay process is reachable but route proof is not yet available" from true degradation. A clean rebuild against restarted healthy relays should not show every major feature as degraded unless there is concrete route-level failure evidence.

Architecture plan: [pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md](./pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md).

## Scope And Constraints

- Do not query, install to, launch on, log from, or otherwise control the physical iPhone 17 Pro during this investigation.
- Use source code, local relay diagnostics, logs, and the `iPhone 17` simulator for reproduction.
- Analyze first. Do not modify production code until the bug is fix-ready and Amir asks for the fix.
- Keep this document as the source of truth for evidence and decisions.

## Evidence

<!-- bugs:block:analysis -->

### User-Reported Evidence

- Physical iPhone 17 Pro cannot be remotely controlled for this diagnosis.
- After startup, five pinned rows were visible.
- Two pinned rows could be unpinned successfully.
- Three pinned rows remained stuck.
- Swiping a stuck pinned row does not reliably show the `Unpin` menu.
- Sometimes the `Unpin` menu appears and disappears before it can be tapped.
- Same app state reports partially connected health:
  - Dock feed degraded
  - Thread detail degraded
  - Archive degraded
  - Voice degraded
  - Diagnostics degraded
- This happened after a clean rebuild and relay restarts.

### Current Repo/Runtime Baseline

- Time captured: `2026-06-02T12:03:10Z`.
- Repo: `/Users/aelaguiz/workspace/codex-client`.
- Branch commit at the time of investigation start was previously deployed as `e048b5d Unify Dock projection identity`.
- The first diagnostic pass used source reads only and avoided all physical-device commands after Amir unplugged the iPhone 17 Pro.

### Runtime Evidence: Relay Health Was Not The Broad Failure

Relay route summaries were collected from both configured hosts:

- `http://amir-m5.fairy-salmon.ts.net:4510`
- `http://home.fairy-salmon.ts.net:4510`

Both relays returned `/syncz` as:

```json
{"ok":true,"service":"codex-dock-relay","schema":"codexdock.syncz.v1","state":"available"}
```

The route summaries did not show app-critical failures. They showed a mix of healthy exercised routes and unknown passive/manual routes:

- `dock/resync`, `dock/subscribe`, and `initialize` had healthy evidence on at least the local host path.
- `dock/update`, `thread/detail/*`, archive mutation/update routes, and voice routes were mostly `unknown` because they are passive/manual routes and had not been exercised.
- `appCriticalFailures` was `[]` on both hosts.

Inference: the relays were reachable. Unknown route evidence exists, but that is not the same as a failed relay. The user-visible "everything degraded" screen needed client-side explanation.

### Simulator Evidence: Health Degradation Is A Dock Window Fallback

The `iPhone 17` simulator was launched with:

```bash
FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

Accessibility dump evidence from the Dock screen:

- `codexdock.dock.root` value:
  - `loaded; rows=487; pinned=0; lens=newest; search=false; filters=0; 487 shown ... Partial`
- `codexdock.connectivity.global` label:
  - `Online 2/2`
- `codexdock.connectivity.global` value:
  - `Partial: Home: Showing 250 of 964`

After opening System Health from the global indicator, accessibility showed:

- Summary:
  - `Partial`
  - `Home: Showing 250 of 964`
- `codexdock.system-health.category.dockFeed`:
  - `Degraded. Home: Showing 250 of 964 Run check or open host details.`
- `codexdock.system-health.category.threadDetail`:
  - `Degraded. Home: Showing 250 of 964 Run check or open host details.`
- `codexdock.system-health.category.archive`:
  - `Degraded. Home: Showing 250 of 964 Run check or open host details.`
- `codexdock.system-health.category.voice`:
  - `Degraded. Home: Showing 250 of 964 Run check or open host details.`
- `codexdock.system-health.category.diagnostics`:
  - `Degraded. Home: Showing 250 of 964 Run check or open host details.`

Opening the `Home` host detail showed:

- `State, Showing 250 of 964`
- `Technical Evidence`
- `No route evidence yet.`

Conclusion: the System Health screen degraded every category without route-level evidence. It copied the global Dock row-window partial message into unrelated feature categories.

### Code Anchor: Dock Row Windows Become Connectivity Partial

The row-window state originates in `CodexDock/State/ThreadCardTable.swift`.

Relevant source anchors:

- `CodexDock/State/ThreadCardTable.swift:428-435`: if a stream snapshot is not complete, `hostStatus(...)` returns `.partial(rowCount: visibleRows, message: "Showing \(visibleRows) of \(knownTotal)")`.
- `CodexDock/State/ThreadCardTable.swift:364`: `DockRenderInput.isPartial` becomes true if any host is checking or partial.
- `CodexDock/State/DockStore.swift:278-296`: loaded Dock snapshots are reported to `AppConnectivityStore`.
- `CodexDock/State/AppConnectivityStore.swift:419-437`: `.partial(_, message)` Dock host status becomes `HostConnectivityPhase.partial(message)`.
- `CodexDock/State/AppConnectivityStore.swift:610-616`: if all hosts are online-like but at least one is partial, the global status becomes `.partial("\(host): \(message)")`.

This means `Home: Showing 250 of 964` is currently treated as global connectivity partiality even though it is actually a data-window completeness fact.

### Code Anchor: System Health Falls Back From Global Partial To Every Category

Relevant source anchors:

- `CodexDock/Features/Status/SystemHealthView.swift:66-68`: System Health projects from `store.hosts` and `store.overallStatus`.
- `CodexDock/Features/Status/SystemHealthView.swift:50-57`: route diagnostics are only fetched by tapping `Run check`; they are not fetched on open.
- `CodexDock/Features/Status/SystemHealthProjector.swift:31-35`: if a category has no route diagnostics, it uses `fallbackStatus(for:overallStatus:)`.
- `CodexDock/Features/Status/SystemHealthProjector.swift:78-79`: global `.partial(message)` maps to category `.degraded(message, nextAction: "Run check or open host details.")`.

This is the exact code path that reproduced in the simulator: the `Home` row-window partial became a global `.partial`, then every category with no route evidence displayed `Degraded`.

### Code Anchor: Pinned Rows Are A Custom UIKit Collection View

Pinned rows do not use the normal SwiftUI `DockSwipeActionRow` path. In `CodexDock/Features/Dock/DockView.swift`, body rows use `dockRow(row, resetToken:)`, but pinned rows use `dockPinnedRow(row)` inside `DockPinnedSectionView`.

Relevant source anchors:

- `CodexDock/Features/Dock/DockView.swift:729`: renders `DockPinnedSectionView` when `projection.pinnedRows` is not empty.
- `CodexDock/Features/Dock/DockView.swift:733`: pinned reorder callback calls `Task { await store.reorderPinnedRows(rows) }`.
- `CodexDock/Features/Dock/DockView.swift:734`: pinned unpin callback calls `Task { await store.setPinned(false, for: row) }`.
- `CodexDock/Features/Dock/DockView.swift:859`: `dockPinnedRow(_:)` renders only `dockRowContent`, with `showsContextMenu: false`.
- `CodexDock/Features/Dock/DockPinnedViews.swift:219`: pinned rows render through `DockPinnedReorderCollectionView`.
- `CodexDock/Features/Dock/DockPinnedViews.swift:274`: `makeUIView` creates a `UICollectionView`.
- `CodexDock/Features/Dock/DockPinnedViews.swift:279`: trailing swipe actions are provided by `UICollectionLayoutListConfiguration.trailingSwipeActionsConfigurationProvider`.
- `CodexDock/Features/Dock/DockPinnedViews.swift:310`: `updateUIView` runs on SwiftUI updates.
- `CodexDock/Features/Dock/DockPinnedViews.swift:315-320`: when not moving, `updateUIView` assigns `workingRows = rows`, calls `collectionView.reloadData()`, invalidates layout, forces layout, and reports measured height.
- `CodexDock/Features/Dock/DockPinnedViews.swift:425-428`: the `Unpin` contextual action calls `parent.onUnpin(row)` and completes.

First inference: any SwiftUI update to the pinned section while a UIKit trailing swipe action is open can cause `reloadData()`. UIKit list reloads close open swipe actions. This matches the user-visible symptom where the menu appears briefly and disappears.

### Code Anchor: Body Rows Use A Separate Swipe Implementation

Body rows use `DockSwipeActionRow`, a SwiftUI view with local `offset` state.

Relevant source anchors:

- `CodexDock/Features/Dock/DockPinnedViews.swift:8`: `DockSwipeActionRow`.
- `CodexDock/Features/Dock/DockPinnedViews.swift:16`: local `@State private var offset`.
- `CodexDock/Features/Dock/DockPinnedViews.swift:30`: `.simultaneousGesture(dragGesture)`.
- `CodexDock/Features/Dock/DockPinnedViews.swift:42-50`: row ID, pin state, and render revision changes close the action.
- `CodexDock/Features/Dock/DockView.swift:832`: body rows use `DockSwipeActionRow`.

First inference: pinned rows and body rows use materially different interaction implementations. A bug in pinned unpin can exist even if body row pin/unpin behaves normally.

### Code Anchor: Pin/Unpin Is Local Metadata

Relevant source anchors:

- `CodexDock/State/DockStore.swift:208`: `setPinned(_:for:)`.
- `CodexDock/State/DockStore.swift:209-215`: pin/unpin persists through `persistMetadataChange`.
- `CodexDock/Metadata/LocalMetadataEngine.swift:93-100`: setting pinned updates `pinnedAt` and `pinnedOrder`; unpin clears both.

First inference: the stuck swipe menu is likely an interaction/rendering issue before the `setPinned(false, for:)` action fires. The user's report says the menu often cannot be tapped; that is different from tapping `Unpin` and having persistence fail.

### Simulator Evidence: Five Pinned Rows Survive Startup

The simulator initially had no metadata file:

- App container: `.../Library/Application Support/CodexDock`
- `thread-metadata.json`: absent

To approximate the physical-phone startup state without touching the physical phone, five current `Amir-M5` Dock rows were seeded into the simulator's own app data as pinned local metadata. Each entry used the real app key shape:

- `hostID`
- `backendSessionID`
- `threadID`
- `isPinned`
- `pinnedAt`
- `pinnedOrder`

After relaunching with:

```bash
FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'
```

Accessibility showed:

- `codexdock.dock.root` value:
  - `loaded; rows=487; pinned=5; lens=newest; search=false; filters=0; ... Partial`
- `codexdock.dock.pinned.toggle` value:
  - `Expanded, Pinned 5`
- `codexdock.dock.pinned.header` text:
  - `Pinned 5`

Conclusion: persisted local pin metadata is loaded and projected correctly after startup in the simulator. The remaining bug is not "pins vanish on restart"; it is the pinned interaction surface becoming unstable after pins are present.

### Simulator Evidence: Pinned Section Accessibility Shape Is Suspicious

With five pins seeded, the accessibility tree showed:

- Pinned header at `y=303`.
- Only one visible pinned row element was exposed at `y=782`.
- That row had value ending in `Pinned`.

This does not by itself prove a layout bug, because accessibility listing only reports visible elements and the embedded collection is tall. But it reinforces that the pinned section is a large embedded UIKit surface with its own cell layout, not the same simple SwiftUI row stack used by body rows.

### Testing Tool Drift: `sim-ui-dump` Contract Is Not Trustworthy Right Now

Before seeded pins, `rtk make sim-ui-dump SIM='iPhone 17'` produced useful files but exited nonzero because the proof schema rejected the dump:

```text
proof report contract check failed: /tmp/codex-client/sim-ui-dump-20260602T120545Z/sim-ui-dump.json/app: must NOT have additional properties
```

This means the simulator dump producer and `contract/proof/sim-ui-dump.schema.json` have drifted. The dump still wrote:

- `/tmp/codex-client/sim-ui-dump-20260602T120545Z/sim-ui-dump.json`
- `/tmp/codex-client/sim-ui-dump-20260602T120545Z/sim-ui-dump.md`

After seeding five pinned rows, a second `rtk make sim-ui-dump SIM='iPhone 17'` hung during the current visible screen XCTest path and had to be killed. The lower-level Mobile MCP accessibility dump still worked and captured the pinned state. This is relevant because the formal proof path is currently weak around exactly the UI state under investigation.

## Investigation Log

### 2026-06-02T12:03Z Initial Source Triage

Actions:

- Confirmed active goal and physical iPhone 17 Pro no-touch constraint.
- Searched source for `pin`, `pinned`, `unpin`, `swipeActions`, `contextMenu`, degraded health, and route-health terms.
- Read `DockPinnedViews.swift`, `DockView.swift`, `DockStore.swift`, and `DockCardProjection.swift`.

Learned:

- Pinned rows are implemented as a custom UIKit `UICollectionView` list with trailing swipe actions and long-press reorder.
- Pinned rows call `reloadData()` on every SwiftUI update when not actively moving.
- Body rows use a separate SwiftUI offset-based swipe row and are not equivalent to pinned rows.
- Pinned row content intentionally disables the normal context menu.
- Unpin persistence is local metadata; the observed failure is probably before persistence because the action cannot be stably tapped.

### 2026-06-02T12:07Z Relay And Health Evidence

Actions:

- Queried local and home relay health endpoints.
- Opened System Health in the `iPhone 17` simulator through accessibility, not screenshots.
- Opened `Home` host detail inside System Health.
- Read `ThreadCardTable`, `AppConnectivityStore`, `SystemHealthView`, and `SystemHealthProjector`.

Learned:

- Relays were reachable and `/syncz` returned `state=available`.
- The simulator global indicator showed `Online 2/2`, but value `Partial: Home: Showing 250 of 964`.
- System Health showed every category degraded for the same reason: `Home: Showing 250 of 964`.
- The `Home` host detail said `No route evidence yet.`
- Code confirms route diagnostics are not auto-fetched when System Health opens; the `Run check` button is the fetch path.
- Code confirms global `.partial` falls back to category `.degraded` when a category has no route evidence.

Conclusion:

The broad degraded UI is a client classification bug. A capped Dock row window is being presented as feature degradation across unrelated categories.

### 2026-06-02T12:11Z Simulator Pinned-State Reproduction

Actions:

- Confirmed simulator app data had no existing `thread-metadata.json`.
- Fetched current Dock cards from the relay card stream to avoid guessing metadata keys.
- Seeded five simulator-only local metadata pins using real `hostID/backendSessionID/threadID` keys.
- Relaunched the app with `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'`.
- Dumped visible simulator accessibility via Mobile MCP against the simulator UDID.

Learned:

- The simulator Dock loaded with `pinned=5`.
- The pinned header displayed `Pinned 5`.
- At least one pinned row was visible and carried accessibility value `Pinned`.
- Pin persistence and projection survived restart.

Conclusion:

The remaining pinned problem is focused on the interaction layer: exposing and tapping `Unpin` on pinned rows.

### 2026-06-02T12:13Z Formal UI Dump Gap

Actions:

- Ran `rtk make sim-ui-dump SIM='iPhone 17'` after seeded pins.
- Stopped the dump after it hung.

Learned:

- The first dump before seeded pins already revealed schema drift: top-level `app` exists in produced JSON but is rejected by the proof schema.
- The second dump hung in `CodexDockCurrentUIDumpTests/testDumpsCurrentVisibleScreenOnce`; only config was written under `/tmp/codex-client/sim-ui-dump-20260602T121309Z/`.
- Mobile MCP accessibility dumping still worked.

Conclusion:

Our simulator proof path has blind spots in this class of bug. It can fail schema validation or hang in the precise pinned/high-text accessibility state we need to diagnose.

## Ranked Hypotheses

### H1: Pinned UIKit `reloadData()` closes swipe actions during live updates

Confidence: high after source triage plus simulator pinned-state reproduction; not yet instrumented with a swipe-open timestamp.

Mechanism:

- User swipes a pinned row.
- UIKit opens the trailing `Unpin` action.
- A live Dock update, projection revision, health state update, height measurement callback, or other SwiftUI state change re-runs `updateUIView`.
- `updateUIView` calls `collectionView.reloadData()`.
- UIKit closes the open swipe action.
- User sees the menu pop in and out before it can be tapped.

Why it fits:

- The symptom is instability of the menu, not a failed `Unpin` action after tap.
- It can be worse after startup, when streams/health/status updates are still settling.
- It can be worse with live work happening, because updates keep arriving.
- It is specific to pinned rows because pinned rows use a collection view bridge.

What would prove it:

- Simulator reproduction where opening a pinned-row swipe action followed by a live Dock update or forced render update closes the action.
- Logs/instrumentation showing `DockPinnedReorderCollectionView.updateUIView`/`reloadData()` happens while the swipe action is open.
- A UI dump or XCTest proof showing `Unpin` action appears and disappears across samples without user tapping it.

Current evidence:

- The exact code path calls `collectionView.reloadData()` on every `updateUIView` while not moving.
- The simulator reproduced the same five-pinned startup state.
- The app is live and continuously receiving Dock stream/health changes.
- UIKit list reloads are known to close active cell swipe actions.

This is the most direct explanation for the reported "appears then disappears" menu behavior.

### H2: Long-press reorder recognizer competes with swipe recognizer

Confidence: medium.

Mechanism:

- Pinned rows add a `UILongPressGestureRecognizer` for drag reorder with `minimumPressDuration = 0.35`.
- The recognizer has `cancelsTouchesInView = true`.
- Gesture delegate returns false for simultaneous recognition when either gesture is a long press.
- Slow/hesitant swipes could be interpreted as long press/reorder attempts, canceling the swipe action.

Why it fits:

- User describes inconsistent menu behavior.
- Pinned rows uniquely combine swipe actions and long-press reordering.

What would prove it:

- Simulator reproduction where slow swipes fail but fast swipes work.
- Gesture logs showing long-press began/canceled near failed swipe attempts.

### H3: Hidden pinned rows by filter/scope are being mistaken for stuck pinned rows

Confidence: low-medium.

Mechanism:

- `DockCardProjection` computes `pinnedRows` only from filtered rows.
- `allPinnedRows` includes all pinned rows.
- If filters/scope hide pinned rows, header can show `Pinned X of Y`.

Why it partially fits:

- User had five pinned, then two unpinned, leaving three.
- Existing UI has hidden pinned summary paths.

Why it does not fit well:

- User says the three rows are visible and swipe actions are unstable, not hidden.
- This does not explain the swipe menu appearing and disappearing.

What would prove/disprove it:

- UI dump showing header/title, visible pinned row count, active filters, and actual pinned summary.

### H4: Unpin persistence fails after tap

Confidence: low based on current report.

Mechanism:

- `metadataEngine.setPinned(false, for:)` throws.
- `persistMetadataChange` sets an action error and pinned state remains.

Why it does not fit well:

- User specifically reports not getting a stable unpin menu.
- Need evidence of a tap completing and a persistence error before elevating this.

What would prove it:

- `DockLog` action error or metadata write error after tapping `Unpin`.

### H5: Health categories are degraded because route health is unproven/unknown after restart

Confidence: superseded.

This was the first health hypothesis, but the simulator proved a different specific path. Unknown route evidence is real, but unknown-only diagnostics are not what caused the observed broad degraded labels. The observed labels happened because no route evidence had been loaded into the System Health view, so it fell back from global `.partial`.

### H6: Dock row-window partiality is incorrectly reused as broad service degradation

Confidence: high; reproduced in simulator and confirmed in code.

Mechanism:

- Home relay has more rows than the current Dock stream window limit.
- `ThreadCardTable.hostStatus(...)` returns `.partial(rowCount: 250, message: "Showing 250 of 964")`.
- `AppConnectivityStore.reportDockState` records that as `HostConnectivityPhase.partial("Showing 250 of 964")`.
- Overall connectivity becomes `.partial("Home: Showing 250 of 964")`.
- System Health opens without route diagnostics because `refreshRelayDiagnostics()` only runs from `Run check`.
- `SystemHealthProjector` sees no category route diagnostics and maps global `.partial` to `.degraded` for every category.

Why it fits:

- Simulator exactly displayed this state.
- Host detail exactly showed `No route evidence yet`.
- Every category used the same Dock window message.
- Relay `/syncz` was available and app-critical failures were empty.

What would prove it further:

- A unit test where `SystemHealthProjector.snapshot(hosts: [Home partial window], overallStatus: .partial("Home: Showing 250 of 964"))` with empty `routeDiagnostics` proves every category is currently degraded.
- A corrected test where row-window partiality no longer maps to service degradation.

## Verification Plan

1. Inspect health category mapping in Swift and route-health semantics in relay scripts.
2. Capture current local and home relay `/statusz`, `/routesz`, and `/syncz` payload summaries.
3. Run `rtk make app SIM='iPhone 17'` or `FORCE_LAUNCH=1 rtk make app SIM='iPhone 17'` as needed.
4. Use simulator UI dump before and after pinning/unpinning where possible:
   - `rtk make sim-ui-dump SIM='iPhone 17'`
5. Create or use existing UI automation/accessibility path to pin several rows, restart/relaunch the simulator app, and sample pinned-row action visibility.
6. Capture simulator logs:
   - `rtk make sim-logs SIM='iPhone 17'`
7. Update this doc with proved root cause, disproved theories, and fix-ready status only when evidence is strong.

## Fix Plan

<!-- bugs:block:fix_plan -->

Not implemented. Proposed shape for review:

1. Split "Dock data window is partial" from "connectivity/service health is degraded."
   - `Showing 250 of 964` is a Dock data completeness/status message.
   - It should not drive global connectivity or System Health feature degradation by itself.
   - Keep the message visible in Dock where row-window completeness matters.
2. Make System Health route-evidence based.
   - Opening System Health should either fetch route diagnostics automatically or clearly show `Not checked` until the user runs a check.
   - A category should be `Degraded` only for direct failed/degraded/stale evidence in that category, not because Dock has a capped row window.
3. Replace the pinned row interaction path with one stable implementation.
   - Preferred permanent fix: stop using the custom embedded `UICollectionView` for pinned rows if reorder can be achieved with a SwiftUI-native list/stack path, or at least stop unconditional `reloadData()` during normal updates.
   - If keeping UIKit temporarily, update only changed rows with diffable data source or batch updates and never call `reloadData()` while a swipe action is open.
   - Reevaluate the long-press reorder recognizer so it does not cancel swipe actions.
4. Add tests for live-like behavior, not static snapshots only.
   - Pinned row UI test: seed or pin 5 rows, relaunch, open a pinned row swipe action, inject/replay a Dock update, assert `Unpin` remains visible long enough to tap.
   - Health projector test: capped Dock row window does not mark thread detail/archive/voice/diagnostics degraded.
   - System Health UI/accessibility test: with no route evidence, categories show `Not checked` or route-specific healthy/degraded states, not copied Dock window text.
   - Fix `sim-ui-dump` schema drift and add a regression so producer and schema cannot drift.

<!-- /bugs:block:fix_plan -->

## Implementation

<!-- bugs:block:implementation -->

No code changes made in analyze mode.

<!-- /bugs:block:implementation -->
