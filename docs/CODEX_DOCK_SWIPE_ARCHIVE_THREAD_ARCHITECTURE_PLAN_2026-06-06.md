---
title: "Codex Dock - Swipe Archive Thread Architecture Plan"
date: 2026-06-06
status: ready-plan-audit-and-consult-passed
fallback_policy: forbidden
owners: [Amir]
reviewers: [Codex, Composer 2.5 Fast, Cursor Composer 2.5 Fast]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30.md
  - docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_ARCHITECTURE_PLAN_2026-05-30.md
  - docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_REQUIREMENTS_2026-05-30.md
  - docs/TESTING.md
---

# TL;DR

Outcome:
Dock rows get two deliberate horizontal swipe actions. The existing trailing
swipe keeps `Pin` / `Unpin`; the opposite leading swipe reveals `Archive`.
Tapping `Archive` sends the same `thread/archive` command path already used by
the context menu and archive cleanup, and the relay moves the row from the Dock
stream to the Archive stream.

Architecture:
Do not add a new archive protocol, local `isArchived` metadata, direct phone
connection to raw `:4500`, or a second row truth. Pin remains local metadata.
Archive remains Codex app-server state projected through the Dock relay on
`:4510`.

Plan:
First make one active Dock row archive through the opposite-direction swipe and
prove it crosses the full UI -> Swift store -> relay -> Codex app-server ->
Dock/Archive stream path. Then widen that same action to pinned rows, context
menu, accessibility, automation IDs, and simulator proof.

Non-negotiables:

- One swipe direction is pin/unpin; the other direction is archive.
- Archive is explicit tap after reveal. No destructive full-swipe archive.
- Swipe archive, context-menu archive, and accessibility archive call one
  Dock-level action closure, which calls `DockStore.archive(row)`.
- `DockStore.archive(row)` remains the active-row owner and routes through
  `ClientCommandEngine` and `AppServerThreadCommandClient`.
- `ArchiveCleanupStore` may keep its batch progress loop, but it must keep using
  the same `ThreadArchiveCommanding` boundary and `thread/archive` route.
- Pin metadata is not silently cleared by archive. A pinned row disappears from
  active Dock because the relay moves it to archive; if restored later, the
  local pin can still apply.
- Archive visibility is proven through `archive/subscribe` or `archive/update`,
  not through local UI fakery.

# 0) North Star

After implementation, an iPhone 17 simulator run can:

1. Open Dock with real relay-backed rows.
2. Swipe an active row trailing and reveal `Pin` or `Unpin`.
3. Swipe that same class of row leading and reveal `Archive`.
4. Tap `Archive`.
5. See the row remain until the archive command succeeds, then leave active
   Dock through the relay-backed Dock stream.
6. Open `Archived threads` and see the archived row through the relay-backed
   Archive stream.
7. Restore that row and see it return to active Dock through `thread/unarchive`
   and the Dock stream.

The route evidence must include the existing Codex/Dock route family:

- `thread/archive`
- `thread/unarchive`
- `dock/subscribe` / `dock/update`
- `archive/subscribe` / `archive/update`

# 1) Scope

## 1.1 In Scope

- Add an archive swipe action to active Dock rows.
- Preserve the existing pin/unpin swipe direction and labels.
- Make the archive swipe use the opposite horizontal direction from pin/unpin.
- Use an explicit `Archive` button tap after the swipe reveal.
- Add `Archive thread` accessibility action for rows that can be archived.
- Keep the existing context-menu `Archive` action available.
- Refactor Dock row archive invocation so swipe, context menu, and
  accessibility call one `DockView` action function.
- Keep active row archive owned by `DockStore.archive(row)`.
- Preserve Archive sheet restore behavior through `ArchiveStore.restore(row)`.
- Preserve archive cleanup batch behavior through `ArchiveCleanupStore`, while
  keeping the same `ThreadArchiveCommanding` command boundary.
- Update automation IDs only where the bidirectional swipe needs distinct test
  handles.
- Add or update focused tests and simulator proof for the new UI action path.

## 1.2 Out Of Scope

- No implementation in this planning turn.
- No new Codex app-server method.
- No new relay archive route.
- No server-side bulk archive method.
- No local `isArchived` or `archivedAt` user metadata.
- No direct iPhone connection to raw authenticated `:4500`.
- No phone-side `OPENAI_API_KEY`, raw app-server bearer token, or relay
  instance identity persistence.
- No Dock archive filter or fourth Dock lens.
- No replacement of the existing Archived Threads sheet.
- No destructive full-swipe archive in the first implementation.

# 2) Ground Truth Read For This Plan

## 2.1 Installed Codex App-Server Protocol

Local Codex install:

- `rtk codex --version` reported `codex-cli 0.136.0-alpha.2`.
- `rtk which codex` resolved to `/Users/aelaguiz/.local/bin/codex`, which
  points through the Homebrew/npm install at
  `/opt/homebrew/lib/node_modules/@openai/codex`.

Codex CLI exposes saved-session archive commands:

- `rtk codex archive --help` says `codex archive <SESSION>` archives a saved
  session by id or session name.
- `rtk codex unarchive --help` says `codex unarchive <SESSION>` unarchives a
  saved session by id or session name.

Codex app-server schema was generated read-only into scratch with:

```bash
rtk codex app-server generate-json-schema --out /tmp/codex-client/swipe-archive-plan-20260606T000000Z/codex-schema --experimental
```

The generated schema confirms:

- `v2/ThreadArchiveParams.json`: `thread/archive` requires `threadId`.
- `v2/ThreadArchiveResponse.json`: archive response is an empty object.
- `v2/ThreadUnarchiveParams.json`: `thread/unarchive` requires `threadId`.
- `v2/ThreadUnarchiveResponse.json`: unarchive response returns `thread`.
- `v2/ThreadListParams.json`: `archived: true` returns archived threads;
  `false` or `null` returns non-archived threads.
- `v2/ThreadArchivedNotification.json` and
  `v2/ThreadUnarchivedNotification.json`: both notifications carry `threadId`.

Conclusion:
The app should use the existing archive/unarchive protocol. New DTOs or relay
methods would add drift without adding capability.

## 2.2 Swift Command Path

Current method constants live in
`CodexDock/AppServer/AppServerMethods.swift`:

- `thread/archive`
- `thread/unarchive`
- `dock/subscribe`
- `dock/update`
- `archive/subscribe`
- `archive/update`

`CodexDock/AppServer/AppServerClient.swift` already exposes typed
`threadArchive(params:)` and `threadUnarchive(params:)`.

`CodexDock/AppServer/ThreadDetailDTO.swift` already defines:

- `ThreadArchiveParams { threadId }`
- `ThreadArchiveResponseDTO`
- `ThreadUnarchiveParams { threadId }`
- `ThreadUnarchiveResponseDTO { thread }`

`CodexDock/Commands/ClientCommandEngine.swift` is the command actor. Its
archive methods call `ThreadArchiveCommanding.archiveThread` and
`ThreadArchiveCommanding.unarchiveThread`.

`CodexDock/State/AppServerThreadCommandClient.swift` is the app-server command
client. It maps archive and restore to `AppServerMethods.threadArchive` and
`AppServerMethods.threadUnarchive` with normal request timeout and observability
context.

`CodexDock/State/DockStore.swift` owns active-row archive. It resolves the host,
calls `commandEngine.archive(row,on:)`, clears or reports the action error, and
refreshes Dock after success.

`CodexDock/State/ArchiveStore.swift` owns restore. It resolves the host, calls
`commandEngine.unarchive(row,on:)`, supports batch restore, and refreshes
Archive after successful restore.

## 2.3 Swift Row UI

`CodexDock/Features/Dock/DockPinnedViews.swift` currently has
`DockSwipeActionRow`, a single-direction custom row action:

- It stores one `offset`.
- It uses `ZStack(alignment: .trailing)`.
- A negative horizontal drag opens one trailing button.
- The button label is `Pin` or `Unpin`.
- The action calls `onTogglePinned`.

`CodexDock/Features/Dock/DockView.swift` uses `DockSwipeActionRow` for normal
body rows. It passes `store.setPinned(!row.isPinned, for: row)`.

`CodexDock/Features/Dock/DockPinnedViews.swift` also uses
`DockSwipeActionRow` inside `DockPinnedRowsList` for pinned rows, where the
action is `Unpin`.

`CodexDock/Features/Dock/DockRowContextMenu.swift` already has a destructive
`Archive` context-menu action that calls:

```swift
if await store.archive(row) {
    await onArchiveSucceeded()
}
```

Conclusion:
The right UI change is to extend the row swipe wrapper to support two named
directions and to centralize the archive invocation in `DockView`. Do not add a
second gesture implementation beside `DockSwipeActionRow`.

## 2.4 Relay Projection Path

`scripts/dock-relay.mjs` handles `thread/archive` and `thread/unarchive` by
calling relay thread data functions, then
`relayStateEngineForConfig(config).handleArchiveMutation(...)`.

`scripts/dock-relay-thread-data.mjs` routes:

- `archiveThread(config, params)` to `thread/archive`, preferring the live owner
  when one exists.
- `unarchiveThread(config, params)` to history `thread/unarchive`.

`scripts/dock-relay-app-server-registry.mjs` confirms that:

- `thread/unarchive` is in `HISTORY_ROUTE_METHODS`.
- `thread/archive` is in `LIVE_OWNER_PREFERRED_METHODS`.

`scripts/dock-relay-state-engine.mjs` has one shared archive mutation path:

- `handleArchiveMutation({ threadId, archived })`
- `store.applyThreadArchiveMove(...)`
- `publishTargetedArchiveMove(...)`

`scripts/dock-relay-state-store.mjs` moves the projection card between views:

- from `dock` to `archive` when archived
- from `archive` to `dock` when unarchived
- emits a delete for the old view and an upsert for the new view

`scripts/dock-relay-state-ingest.mjs` explicitly says archive commands are
inputs to the canonical projection and must not write card order or freshness
directly.

Conclusion:
The relay already owns the right state transition. Swift should request the
mutation and then consume Dock/Archive stream truth.

## 2.5 Contract And Generated DTO Path

`CodexDock/AppServer/DockThreadCardDTO.swift` is generated from
`contract/projection/projection-thread-card-stream.schema.json`.

The generated stream DTOs already model:

- `ThreadCardStreamView.dock`
- `ThreadCardStreamView.archive`
- `DockThreadCardArchiveState.active`
- `DockThreadCardArchiveState.archived`
- `DockThreadCardDTO.archiveState`
- `displayOrderKey`
- `sourceHostID`

`CodexDock/State/AppServerThreadCardStreamClient.swift` chooses the stream
methods by view:

- `.dock` uses `dock/subscribe`, `dock/update`, `dock/resync`.
- `.archive` uses `archive/subscribe`, `archive/update`, `archive/resync`.

`CodexDock/State/ThreadCardRowProjector.swift` projects relay cards into
`DockRowViewModel`; local metadata decorates the row, but relay owns title,
status, activity, freshness, and archive state.

`CodexDock/State/LocalThreadMetadataStore.swift` documents that labels, rails,
and pins are local while archive state must come from relay card streams.

Conclusion:
The generated projection contract already carries the archive split. The plan
must not add local archive filtering or client-inferred archive status.

# 3) Target Architecture

## 3.1 State Ownership

Archive has one source of truth:

```text
Codex app-server archive state
-> Dock relay card projection
-> dock/* and archive/* streams
-> Swift stream clients
-> DockStore / ArchiveStore render state
```

Pin has one source of truth:

```text
LocalThreadMetadata
-> LocalMetadataEngine
-> ThreadCardRowProjector / Dock projection
-> SwiftUI row affordances
```

These states are intentionally independent:

- Pinning does not call the relay.
- Archiving does not rewrite local pin metadata.
- A pinned archived row does not render in active Dock because the relay no
  longer presents it in the Dock stream.
- If the row is restored later, local pin metadata may make it appear in the
  pinned section again.

## 3.2 User Action Matrix

| Row state | Gesture | Revealed action | Action owner | Server mutation | Full swipe |
| --- | --- | --- | --- | --- | --- |
| Active, unpinned | trailing / current pin direction | `Pin` | `DockStore.setPinned(true, for:)` | no | existing pin behavior |
| Active, pinned | trailing / current pin direction | `Unpin` | `DockStore.setPinned(false, for:)` | no | existing unpin behavior |
| Active, any pin state | leading / opposite direction | `Archive` | `DockView.archiveRow(_:) -> DockStore.archive(row)` | `thread/archive` | no |

For iOS handedness/readability, "leading" means the opposite horizontal drag
from the existing pin/unpin drag. The implementation should preserve the
current pin direction so existing muscle memory and current tests do not flip.

## 3.3 UI Component Shape

Refactor `DockSwipeActionRow` from a single hard-coded pin action into a
small bidirectional row-action wrapper.

Target concept:

```swift
struct DockRowSwipeAction {
    let id: AutomationID
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let tint: Color
    let allowsFullSwipe: Bool
    let perform: () -> Void
}
```

`DockSwipeActionRow` should accept:

- `trailingAction: DockRowSwipeAction?`
- `leadingAction: DockRowSwipeAction?`

The wrapper owns:

- signed horizontal offset
- one open side at a time
- stable action width
- tap-to-close when an action is open
- row tap/open behavior when no action is open
- automation ID on each button
- no archive full-swipe

The wrapper does not own app-server logic. It only invokes action closures.

Do not create a second row gesture component for archive. That would split row
behavior, tests, and gesture failure modes.

## 3.4 DockView Action Owner

Add one private `DockView` archive action function, then route every row-level
archive affordance through it:

```swift
@MainActor
private func archiveRow(_ row: DockRowViewModel) {
    Task {
        if await store.archive(row) {
            await onArchiveSucceeded()
        }
    }
}
```

Callers:

- Leading swipe `Archive`
- Context-menu `Archive`
- Accessibility action `Archive thread`

This removes duplicate `Task { if await store.archive(row) ... }` bodies from
row UI. It also gives future diagnostics or pending-row state one Dock-level
place to attach without changing each affordance.

## 3.5 Normal And Pinned Rows

Normal body rows:

- Keep trailing `Pin` / `Unpin`.
- Add leading `Archive`.
- Keep context menu.
- Add accessibility actions for `Pin` / `Unpin`, `Archive thread`, and
  `Rename thread`.

Pinned rows:

- Keep trailing `Unpin`.
- Add leading `Archive`.
- Keep context menu off if it would conflict with pinned-row reorder behavior.
- Add accessibility actions for `Unpin thread`, `Archive thread`, and
  `Rename thread`.

If the current pinned-row reorder surface makes swipe and reorder compete,
preserve reliable swipe/archive first and keep reorder behavior exactly where
the existing pinned plan/code owns it. Do not add a new custom drag/drop engine
to solve archive.

## 3.6 Archive Command Sequence

The desired sequence is:

```text
Dock row leading swipe
-> Archive button tap
-> DockView.archiveRow(row)
-> DockStore.archive(row)
-> DockStore.hostConfiguration(for: row)
-> ClientCommandEngine.archive(row, on: host)
-> AppServerThreadCommandClient.archiveThread(row.threadID, on: host)
-> AppServerClient.threadArchive(ThreadArchiveParams(threadId: row.threadID))
-> Dock relay thread/archive
-> Codex app-server thread/archive
-> relayStateEngine.handleArchiveMutation({ archived: true })
-> StateStore.applyThreadArchiveMove(...)
-> dock/update delete + archive/update upsert
-> Dock stream removes row
-> Archive stream includes row
```

The app should not locally insert the row into Archive and should not locally
delete it from Dock before the server/relay state path succeeds.

## 3.7 Failure Behavior

Failure behavior stays conservative:

- If host resolution fails, keep the row and show the existing action error.
- If relay/app-server request fails, keep the row and show the existing action
  error.
- If archive succeeds but stream movement is delayed, `DockStore.archive(row)`
  may keep its post-success `refresh()` as catch-up proof.
- Do not infer success from the user tapping the swipe button.
- Do not mark archived locally.

## 3.8 Archived Threads

Archived rows should appear through the existing Archived Threads path:

```text
Archive task sheet
-> ArchiveStore.refresh/load
-> AppServerThreadCardStreamClient(view: .archive)
-> archive/subscribe
-> archive/update
-> ArchiveDataEngine / ArchiveThreadCardProjector
-> ArchiveView rows
```

Restore continues through:

```text
ArchiveStore.restore(row)
-> ClientCommandEngine.unarchive(row, on: host)
-> AppServerThreadCommandClient.unarchiveThread(...)
-> thread/unarchive
-> relay targeted archive move back to dock
```

# 4) Existing Paths To Move, Keep, Or Leave Different

| Path | Classification | Reason |
| --- | --- | --- |
| `DockSwipeActionRow` single-action implementation | move now | It is the existing row swipe owner; extending it avoids a second gesture path. |
| `DockRowContextMenu` archive `Task` body | move now | Context menu and swipe should call the same `DockView.archiveRow(_:)` closure. |
| `DockStore.archive(row)` | keep canonical | It owns active row archive, host resolution, error state, and refresh. |
| `ClientCommandEngine.archive` | keep canonical | It is the central command actor for row archive. |
| `AppServerThreadCommandClient.archiveThread` | keep canonical | It is the app-server archive client. |
| `ArchiveStore.restore(row)` | keep canonical | It owns archive restore. |
| `ArchiveCleanupStore.archiveRows` | leave different at orchestration layer | Batch cleanup needs progress, skip, retry, and per-row results, but it must continue using `ThreadArchiveCommanding`. |
| `codex archive` / `codex unarchive` CLI | out of app scope | CLI confirms Codex capability; the iPhone app must still use the relay path. |
| Direct `ws://127.0.0.1:4500` phone path | forbidden | Repo instructions require phone/app traffic through Dock relay `:4510`. |

# 5) Requirements

## 5.1 Product Requirements

R-SA-001. Active Dock rows expose `Pin` / `Unpin` by the existing swipe
direction.

R-SA-002. Active Dock rows expose `Archive` by the opposite horizontal swipe
direction.

R-SA-003. `Archive` requires tapping the revealed button; no destructive
archive full-swipe is enabled for first ship.

R-SA-004. Archived rows leave active Dock only after the archive command
succeeds and relay stream truth moves the card.

R-SA-005. Archived rows appear in Archived Threads through the Archive stream.

R-SA-006. Restore continues to move rows back to active Dock through
`thread/unarchive`.

R-SA-007. Pin metadata remains local and is not cleared by archive.

R-SA-008. Row-level archive is available without long-press: swipe and
accessibility are primary; context menu stays as an accelerator.

## 5.2 Architecture Requirements

R-ARCH-001. No new archive method is added to Codex app-server or Dock relay.

R-ARCH-002. No local archive state is added to `LocalThreadMetadata`.

R-ARCH-003. Swift archive mutations use `DockStore.archive(row)`.

R-ARCH-004. The command path remains
`ClientCommandEngine -> ThreadArchiveCommanding -> AppServerThreadCommandClient`.

R-ARCH-005. Relay stream projection remains the source for Dock/Archive row
membership.

R-ARCH-006. Swipe, context menu, and accessibility call one Dock-level archive
function.

R-ARCH-007. Archive cleanup keeps batch-specific state but shares the same
`ThreadArchiveCommanding` boundary.

R-ARCH-008. Production timeouts, page sizes, ports, and other constants are not
hard-coded in new files.

## 5.3 Proof Requirements

R-PROOF-001. Unit/store tests prove archive success removes the Dock row only
after command success and refresh/stream reconciliation.

R-PROOF-002. Unit/store tests prove archive failure keeps the row recoverable.

R-PROOF-003. UI or simulator proof exercises the new opposite-direction swipe
archive action, not only context-menu archive.

R-PROOF-004. Relay proof exercises the Dock/Archive stream transition with
real data. It does not substitute for swipe proof unless the test actually
drives the app UI swipe.

R-PROOF-005. Real relay-backed simulator proof runs before claiming live-data
completion:

```bash
rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'
```

R-PROOF-006. Generated app UI proof must drive the new swipe action. After the
focused UI test exists, the preferred command shape is:

```bash
rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testSwipeArchiveMovesRowToArchivedThreadsAndRestoreReturnsIt'
```

If the final test lands under a different class or method name, use the exact
`APP_TEST_ONLY` value for that test.

R-PROOF-007. If broader app target UI behavior changes enough to need full
generated Xcode proof, run:

```bash
rtk make app-test SIM='iPhone 17'
```

# 6) Phase Plan

## Phase 0 - Plan, Audit, And Fresh Consult

Purpose:
Prove the architecture before code changes.

Checklist:

- Write this plan from current code and generated Codex schema.
- Run plan-audit until verdict is `ready`.
- Run fresh consult reviews with Composer 2.5 Fast and Cursor Composer 2.5 Fast.
- Repair the plan until both reviews agree there is no blocking architecture
  issue.

Exit criteria:

- Audit log verdict is `ready`.
- Fresh consult verdicts have `BLOCKING: none`.
- No code implementation has been done.

## Phase 1 - One Integrated Swipe Archive Path

Purpose:
Cross the highest-risk seam early: one row action must move through UI, Swift
store, relay mutation, and Dock/Archive streams.

Work:

- Refactor `DockSwipeActionRow` into a bidirectional wrapper.
- Add leading `Archive` action for normal Dock rows.
- Add `DockView.archiveRow(_:)`.
- Route context-menu archive through the same closure.
- Keep archive full-swipe disabled.

Verification:

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ClientCommandEngineTests`
- `rtk swift test --filter AppServerClientTests`
- Add or update the smallest UI automation proof for the new leading swipe.
- Preferred focused UI proof after the test exists:
  `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testSwipeArchiveMovesRowToArchivedThreadsAndRestoreReturnsIt'`.

Exit criteria:

- A normal row can be archived by leading swipe.
- The same archive function is used by swipe and context menu.
- A failed archive leaves the row visible and recoverable.
- No local archive state exists.

## Phase 2 - Pinned Row And Accessibility Coverage

Purpose:
Make the action available everywhere the user sees an active Dock row, without
breaking pin/unpin or pinned-row behavior.

Work:

- Add leading `Archive` action to pinned rows.
- Add `Archive thread` accessibility action for normal and pinned rows.
- Keep pinned row context-menu behavior intentionally unchanged if context menu
  conflicts with reorder.
- Confirm archive does not clear local pin metadata.
- Update automation IDs only if existing `rowAction(... .archive)` cannot
  uniquely identify the new button in UI tests.

Verification:

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AutomationIDTests`
- Focused UI/simulator proof for body row and pinned row swipe actions.

Exit criteria:

- Normal and pinned active rows expose archive by the opposite swipe direction.
- Pin/unpin still uses the existing swipe direction.
- Accessibility can archive without swipe.
- Pinned metadata survives archive/restore unless the user explicitly unpins.

## Phase 3 - Stream And Archive Recovery Proof

Purpose:
Prove that archived rows go to Archive through the relay projection, not local
UI manipulation.

Work:

- Keep Archive sheet backed by `ArchiveStore` and
  `AppServerThreadCardStreamClient(view: .archive)`.
- Do not add local `ArchiveStore.insertArchivedRow`.
- Ensure `onArchiveSucceeded` refreshes Archive only as a catch-up path; it must
  not synthesize row membership.
- Preserve restore through `ArchiveStore.restore(row)`.

Verification:

- `rtk swift test --filter ArchiveScreenStoreTests`
- `rtk swift test --filter ArchiveDataEngineTests`
- `rtk npm run test:relay` if relay scripts are touched.
- Focused app UI proof for swipe archive and restore:
  `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testSwipeArchiveMovesRowToArchivedThreadsAndRestoreReturnsIt'`.
- `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'`.

Exit criteria:

- The row appears in Archived Threads through `archive/subscribe` or
  `archive/update`.
- Restore moves it back through `thread/unarchive`.
- App UI proof drove the actual swipe archive action.
- Live-data simulator proof includes archive/unarchive route evidence. This is
  route/stream proof; it is not counted as swipe proof unless it drove the app
  UI gesture.

## Phase 4 - Final Integration, Docs, And Review

Purpose:
Close side doors and prove shipped behavior.

Work:

- Update README/docs only if the user-facing swipe behavior or testing guidance
  becomes stale.
- Update `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` only if a new root bug
  doc, controlled scenario, or new failure class is introduced.
- Remove any duplicate archive action body left in row UI.
- Run a code-review pass after implementation.

Verification:

- Smallest relevant Swift tests from prior phases.
- `rtk npm run test:relay` if relay scripts changed.
- `rtk make app-test SIM='iPhone 17'` if UI target behavior changed.
- `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` before claiming
  live-data behavior.

Exit criteria:

- All row-level archive affordances use one Dock action path.
- All archive mutations use existing `thread/archive`.
- No direct phone app-server path or local archive truth was added.
- Required proof commands pass or exact blockers are recorded.

# 7) Test And Proof Map

Existing useful tests:

- `CodexDockTests/DockStoreTests.swift`
  - archive success removes Dock row after server success and refresh
  - archive failure keeps Dock row recoverable
  - ArchiveStore loads archived rows and restore refreshes
- `CodexDockTests/ArchiveScreenStoreTests.swift`
  - batch restore, partial failure, stop remaining, host resolution
- `CodexDockTests/ArchiveCleanupStoreTests.swift`
  - cleanup selection, archive execution, retry, stop remaining, host resolution
- `CodexDockTests/ClientCommandEngineTests.swift`
  - archive/unarchive route through command actor
- `CodexDockTests/AppServerClientTests.swift`
  - typed `thread/archive` and `thread/unarchive` requests
  - opt-in real-host archive round trip gated by
    `CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP=1`
- `scripts/dock-relay-state-subscriptions.test.mjs`
  - archive mutations move one card without broad reconcile
- `scripts/dock-relay-sync-audit.mjs`
  - `archive-toggle` scenario validates `thread/archive` and
    `thread/unarchive`

Recommended implementation checks:

```bash
rtk swift test --filter DockStoreTests
rtk swift test --filter ClientCommandEngineTests
rtk swift test --filter AppServerClientTests
rtk swift test --filter ArchiveScreenStoreTests
rtk swift test --filter AutomationIDTests
rtk npm run test:relay
rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testSwipeArchiveMovesRowToArchivedThreadsAndRestoreReturnsIt'
rtk make app-test SIM='iPhone 17'
rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'
```

Run the smallest relevant subset first. Expand when a change touches shared
behavior, generated app UI, relay contracts, or stream projection.

# 8) Risks And Mitigations

Risk:
Archive swipe and pin swipe compete in the same gesture recognizer.

Mitigation:
Use one signed-offset row wrapper with one open side at a time. Do not stack a
second gesture recognizer around the row.

Risk:
Archive becomes optimistic local UI state.

Mitigation:
Do not remove the row locally before command success. Do not insert into
Archive locally. Let relay stream truth move the row; use refresh only as
catch-up.

Risk:
Pinned row archive accidentally clears local pin metadata.

Mitigation:
Keep archive and pin as independent owner paths. Add a test if implementation
touches metadata during archive.

Risk:
Context-menu archive and swipe archive drift.

Mitigation:
Route both through `DockView.archiveRow(_:)`.

Risk:
Cleanup, context menu, and swipe become three command paths.

Mitigation:
Keep all server archive mutations behind `ThreadArchiveCommanding`; keep
single-row Dock archive behind `DockStore.archive(row)`; keep cleanup different
only for batch progress/results.

Risk:
Simulator proof only exercises a fixture and not live data.

Mitigation:
Use fixture UI proof for deterministic swipe coverage, then run
`rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` before claiming
live-data behavior.

Risk:
Real-data route proof is mistaken for UI-swipe proof.

Mitigation:
Keep the proof names separate. `sim-ui-realdata-realtime-proof` proves live
Dock/Archive stream behavior for archive/unarchive; the focused `app-test`
proof must drive the actual leading swipe and tap the revealed `Archive`
button.

# 9) Fresh Consult And Audit Status

Plan audit:

- Status: ready.
- Audit log:
  `docs/CODEX_DOCK_SWIPE_ARCHIVE_THREAD_ARCHITECTURE_PLAN_2026-06-06_PLAN_AUDIT.md`

Fresh consult:

- Parallel group:
  `/tmp/fresh-consult/parallel-codex-dock-swipe-archive-20260606T125906Z-rwpK8p`
- Composer 2.5 Fast:
  - Runtime/model/effort: `agent`, `composer-2.5-fast`,
    `encoded-in-model`
  - Run directory:
    `/tmp/fresh-consult/parallel-codex-dock-swipe-archive-20260606T125906Z-rwpK8p/composer-25-fast/turn-01`
  - Session ID: `fdd524d6-9927-47b7-87d9-0e0ef5d25ef2`
  - Verdict: `pass-with-notes`
  - Blocking: `none`
  - Summary: the plan is ready to implement; it unifies swipe, context menu,
    and accessibility archive through `DockView.archiveRow` ->
    `DockStore.archive` -> existing `thread/archive`; pin remains local and
    independent; proof correctly separates leading-swipe UI tests from
    `archive-toggle` relay/stream proof.
- Cursor Composer 2.5 Fast:
  - Runtime/model/effort: `agent`, `composer-2.5-fast`,
    `encoded-in-model`
  - Run directory:
    `/tmp/fresh-consult/parallel-codex-dock-swipe-archive-20260606T125906Z-rwpK8p/cursor-composer-25-fast/turn-01`
  - Session ID: `e94103ae-f6c4-427e-bb17-379583f96ead`
  - Verdict: `pass-with-notes`
  - Blocking: `none`
  - Summary: the bidirectional swipe wrapper is the simplest correct UI move;
    the plan keeps archive on relay/app-server streams, avoids local archive
    truth, and has strong proof gates if the new leading-swipe UI test is built
    and not substituted by existing route proof.

Readiness:

- Plan audit verdict is `ready`.
- Both fresh consults reported `BLOCKING: none`.
- Scenario coverage ledger was updated with `COV-017` for the route-proof vs.
  UI-swipe-proof gap, and `rtk npm run test:docs` passed.
- No implementation was done in this planning pass.
