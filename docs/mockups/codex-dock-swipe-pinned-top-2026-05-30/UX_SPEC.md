# Codex Dock Swipe Pins UX Spec

Date: 2026-05-30

Status: amended for implementation - static pin order, native reorder, and
true-message Dock cards

Package:
`docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/`

Primary mockup scan:
`outputs/contact-sheet.png`

## One Line

Let the user swipe any Dock thread row to pin it, then keep pinned threads in a
small persistent `Pinned` section at the top of Dock across `Newest`, `Host`,
and `Branch` in user-owned order until the user swipes to unpin.

Dock row cards and Dock ordering use true user/agent messages only, using the
same rule as Thread Detail's default `Messages` filter. Tool output,
reasoning/thinking deltas, request cards, status events, and unknown events are
not Dock card previews and do not move rows ahead of newer true messages.

Important implementation meaning: "agent message" alone is not the rule. Some
Codex reasoning/plan records can normalize as `kind == .agentMessage` while
their `visibilityCategory` is `.thinking`; those are visible only when the user
chooses a broader detail filter. The Dock card/order contract is the Thread
Detail default `Messages` filter contract: `visibilityCategory == .message`
and kind is `.userMessage` or `.agentMessage`.

## Product Intent

Pinned threads are a user-owned watchlist for the few sessions that matter
right now.

They are not inferred importance, not `Needs me`, not a Codex runtime status,
not rate limiting, not a hidden filter, and not a fourth app tab. The user is
saying: "I care about these threads. Keep them easy to reach while I keep using
the normal Dock."

The feature should make the big Dock list feel controllable without taking away
the Dock's main job: show newest true-message activity across configured hosts.

## User Problem

The Dock can contain hundreds of sessions from multiple hosts, repositories,
branches, sources, and status states. The user often cares about a small number
of active threads while still needing to browse the rest of the list by newest
activity, host, or branch.

Today, the user has to remember where the important rows are, search for them,
or re-find them inside a large list. Host and branch grouping help exploration,
but they do not solve "keep these two or three specific threads in front of me."

The row/card preview has a separate trust problem: if the card keeps ripping
between tool output, thinking text, request cards, and messages, the Dock stops
being a readable session index. The Dock card should mean "latest real
conversation message" by the same definition Thread Detail uses by default.

## UX Contract

This feature is correct only if all of these are true:

- `Pin` is a deliberate user action on a thread row.
- `Unpin` is equally direct and available from the pinned row.
- Pinned rows appear at the top of the Dock on `Newest`.
- The same pinned rows appear at the top of the Dock on `Host`.
- The same pinned rows appear at the top of the Dock on `Branch`.
- Switching lenses never moves pinned rows under a host group or branch group.
- Pinned rows keep enough metadata to remain visually understandable outside
  their normal host or branch context.
- Search and explicit filters still behave predictably.
- The UI never uses `Limited`, `History`, `Needs me`, or rate-limit language for
  this feature.
- Pinning never requires the relay or app-server to mutate thread state.
- Pinned order is stable by order pinned. Newly pinned rows append after
  existing pinned rows.
- Pinned rows can be reordered by long-pressing a pinned row and dragging it
  within the pinned list, using native iOS list or collection movement.
- Reorder does not require a visible drag handle, grip, `Edit` button, `Manage`
  button, management sheet, or a minimum pinned count.
- Tapping the `Pinned` label collapses or expands the pinned section.
- All visible pinned rows render inline. There is no three-row cap and no
  `Show all N pinned` button.
- A divider or native section boundary separates pinned rows from the selected
  lens body.
- Dock row/card preview text comes only from true messages.
- Dock row ordering uses newest true-message activity, not raw row `updatedAt`
  when that timestamp was advanced by tools, thinking, request cards, status
  events, or unknown events.
- Thread Detail's default `Messages` filter and Dock row/card preview/order
  call the same shared message-classification logic.
- The Dock must not define "message" by inspecting raw item type strings in
  `DockView`, `DockSessionProjection`, or a Dock-only mapper. It consumes a
  message-derived preview/activity value produced by the shared classifier.

## Vocabulary

`Dock`: The root session list screen under the bottom `Dock` tab.

`Lens`: One of the in-Dock segmented controls: `Newest`, `Host`, or `Branch`.
Lenses change the presentation of the loaded session list. They are not
separate app tabs.

`Pinned`: A local, user-chosen state saying this thread belongs in the top
watchlist.

`Pinned section`: The persistent top section that renders pinned rows before
the selected lens content.

`Body content`: The normal content below the pinned section: newest rows, host
groups, or branch groups.

`Thread row`: A visible Dock row representing a `SessionSummary`/`DockRowViewModel`
with title, host, repository or working directory, branch, status, summary, last
activity, and chevron.

## Non-Goals

Do not add a top-level `Pinned` app tab.

Do not add a fourth Dock lens called `Pinned`.

Do not replace `Newest`, `Host`, or `Branch`.

Do not make pinning an inferred status from Codex, relay freshness, "needs
attention", runtime activity, rate limits, or message contents.

Do not call the state `Watch`, `Favorite`, `Limited`, `History`, or `Needs me`
in the main UI.

Do not require a confirmation modal for ordinary pin or unpin.

Do not make the pinned area a giant hero, carousel, or decorative card.

Do not hide pin/unpin solely in a long-press context menu.

Do not make pin/unpin depend on successful network calls to the relay.

Do not add a `Manage pinned` dialog/sheet/button for this flow.

Do not cap the visible pinned list at three rows.

Do not add `Show all N pinned`.

Do not sort pinned rows by newest activity after the user pins them.

Do not implement pinned reorder with a custom `DragGesture`, homemade hover gap,
or custom drop-target sorting system unless the architecture plan is explicitly
reopened because native iOS list and collection movement both proved impossible
in simulator.

Do not let tool output, command output, reasoning/thinking text, status
updates, request cards, or unknown events become Dock card previews or Dock
ordering inputs.

## Source Artifacts

Use the generated mockups as visual intent, not as pixel-perfect screenshots:

- `outputs/01-swipe-to-pin-newest.png`: unpinned row swiped left, blue `Pin`.
- `outputs/02-newest-pinned-top.png`: `Pinned 2` shown above `Newest` content.
- `outputs/03-host-pinned-top.png`: same `Pinned 2` above `Host` groups.
- `outputs/04-branch-pinned-top.png`: same `Pinned 2` above `Branch` groups.
- `outputs/05-swipe-to-unpin.png`: pinned row swiped left, red `Unpin`.
- `outputs/06-flow-board.png`: storyboard of the core interaction.

Existing product facts from the repo:

- Dock currently opens to `Newest`.
- `Host` and `Branch` are Dock lenses, not root app tabs.
- Search is full width and searches session title, label, repository or working
  directory, branch, summary, status, host display name, host id, source, and
  thread id.
- Filters cover host, branch, status, repository or working directory, source,
  idle visibility, and fixed `Newest message activity` sorting.
- `Not loaded` is the visible label for unknown thread contents.
- `Limited` should not be visible for unknown thread data.
- Local per-thread metadata already exists conceptually for user-owned row
  state such as label and rail color.

## Research Basis

This spec leans on the existing research already captured in the package's
prior worklog and options docs:

- Apple Human Interface Guidelines: lists and tables, search, search fields,
  context menus, tab bars, and toolbars.
- Nielsen Norman Group: usability heuristics, especially visibility of system
  status, user control, recognition over recall, and consistency.
- Baymard Institute: applied filters and visible active scope patterns.

Applied takeaways:

- Hidden context menus are useful accelerators, but not enough for primary row
  actions.
- A huge list benefits from visible user-owned scope and removable state.
- Search and filters should remain predictable and visible when active.
- Top-level navigation should stay small; this is a row affordance and a Dock
  section, not a new app destination.
- The user needs a fast escape hatch. `Unpin` must be as easy to discover as
  `Pin`.
- Apple SwiftUI's native list-move API family is the first implementation path
  for pinned reorder: `DynamicViewContent.onMove(perform:)`,
  `EditActions.move`, and `List`/`ForEach` move support.
- If SwiftUI cannot prove the requested no-handle long-press interaction in the
  simulator, Apple's UIKit collection-view interactive movement is the native
  fallback. `UICollectionViewController.installsStandardGestureForInteractiveMovement`
  installs the standard long-press reorder gesture.
- Apple's Human Interface Guidelines treat lists/tables as containers that can
  support selection, deletion, and reordering, and treat drag/drop as a
  platform-level interaction with accessibility and keyboard alternatives.
- For Codex Dock, that means use native `List`/`ForEach.onMove` behavior first,
  or UIKit's standard collection/list movement if SwiftUI cannot satisfy the
  gesture. Persist the resulting order. Do not invent a custom drag/drop sorter
  for pinned rows.
- For this specific in-list reorder, `List` + `ForEach.onMove(perform:)` is the
  starting point. Apple's SwiftUI drag-source guidance says list reordering can
  be enabled with `onMove` and performed by long-pressing a row and dragging it
  to a new location. Do not start with `draggable`/`dropDestination` or a custom
  gesture sorter for the pinned list.
- Context menus remain secondary actions. Apple guidance also warns that hidden
  context menus are not enough for primary behavior, so `Pin`/`Unpin` stay
  visible through row swipe and accessibility actions.
- Research anchors:
  - <https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove%28perform%3A%29>
  - <https://developer.apple.com/documentation/swiftui/editactions>
  - <https://developer.apple.com/documentation/uikit/uicollectionviewcontroller/installsstandardgestureforinteractivemovement>
  - <https://developer.apple.com/documentation/uikit/uicollectionview>
  - <https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>
  - <https://developer.apple.com/design/human-interface-guidelines/drag-and-drop>
  - <https://developer.apple.com/design/human-interface-guidelines/context-menus>

## Information Architecture

Pinned is a Dock-level overlay section that sits above the selected lens
content.

Hierarchy:

```text
Codex Dock App
  Root tabs
    Dock
      Header and global connectivity
      Search
      Lens controls: Newest | Host | Branch | Filters
      Active scope summary
      Action and mapping banners, if any
      Pinned section, if any visible or known pinned rows exist
      Selected lens body
    Archive
    Relay
```

Pinned is not part of any single lens. `Newest`, `Host`, and `Branch` each
render below the same pinned section.

## Default Layout

When at least one pinned row exists and matches the current search/filter
scope, the Dock vertical order is:

```text
Dock                                      Online 2/2

[ Search sessions, repo, branch, host           ]

[ Newest ] [ Host ] [ Branch ]             [filter]

400 shown - Hosts: Any - Branches: Any - ...

Pinned 2
  [pin] ramp up on code base...
        Amir-M5 - freedom - codex-dock-agents-tab-live-counts
        Latest real user/agent message...
        message now                              >
  [pin] psmobile animation engine
        Amir-M5 - psmobile - feat/anim_stages
        Latest real user/agent message...
        message 2m                               >
----------------------------------------

<selected lens content continues here>
```

The pinned section is visually compact and subordinate to the Dock controls.
It should feel like a watchlist strip, not a page header.

The `Pinned` label is tappable. Tapping it collapses or expands the pinned
section without changing membership or order.

## Empty Pinned State

When no rows are pinned, do not show an empty pinned section.

The Dock should look exactly like the normal Dock until the user pins something.
No empty "Pinned" placeholder belongs above the feed.

The only educational affordance should be discoverable through native row
swipe behavior, context menu actions, and optional first-use coachmark if the
app already has a coachmark pattern. Do not add instructional paragraphs to the
Dock.

The generated mockups include a small one-line swipe hint in some states. Treat
that as a disposable first-use cue, not as persistent Dock copy. The final UI
should not reserve permanent row space for instructions.

## Normal Row Swipe To Pin

A trailing swipe on an unpinned Dock row reveals `Pin`.

Wireframe:

```text
+----------------------------------------+--------+
| ramp up on code base...                |        |
| Amir-M5 - freedom - codex-dock...      |  Pin   |
| The iPhone 17 simulator is at...       |        |
| now                                  > |        |
+----------------------------------------+--------+
```

Visual:

- Action background: system blue.
- Action label: `Pin`.
- Action icon: `pin.fill` or nearest native pin symbol.
- Placement: trailing swipe action.
- Role: non-destructive.
- Full-swipe: allowed if it behaves like normal iOS non-destructive swipe
  completion and does not conflict with navigation.

Behavior:

- The row pins immediately when the user taps `Pin` or completes a full swipe.
- The row moves into the pinned section without requiring a network round trip.
- The pinned section appears in the same scroll position, directly above body
  content.
- A subtle haptic can fire on success if the app already uses haptics.
- No modal appears.
- No toast is required for pin success because the row visibly moves to the top.

## Pinned Row Swipe To Unpin

A trailing swipe on a pinned row reveals `Unpin`.

Wireframe:

```text
Pinned 2
+----------------------------------------+--------+
| [pin] ramp up on code base...          |        |
|       Amir-M5 - freedom - codex...     | Unpin  |
|       Latest real user/agent...        |        |
|       message now                    > |        |
+----------------------------------------+--------+
```

Visual:

- Action background: system red.
- Action label: `Unpin`.
- Action icon: `pin.slash.fill`, `pin.slash`, or closest native symbol.
- Placement: trailing swipe action.
- Role: destructive enough to use red because it removes the row from the
  persistent top section, but it does not delete or archive the thread.
- Full-swipe: allowed only if accidental full-swipe risk feels acceptable in
  simulator testing. If it feels too easy to trigger, disable full-swipe for
  `Unpin`.

Behavior:

- The row unpins immediately.
- The row leaves the pinned section.
- If it still matches the current lens/search/filter body content, it appears
  in its normal body position after unpin.
- If it does not match the current body content, it simply disappears from the
  visible list.
- Show a small undo-capable toast if the app has a toast/snackbar pattern:
  `Unpinned` with optional `Undo`.
- If no toast/undo pattern exists yet, no new snackbar system is required for
  MVP. The context menu and row can be pinned again.

## Context Menu Actions

Swipe is the primary gesture. Context menu is the secondary precision path.

For an unpinned row, the context menu includes:

- `Pin` with pin icon.
- Existing row actions such as color, label, and archive.

For a pinned row, the context menu includes:

- `Unpin` with unpin icon.
- Existing row actions such as color, label, and archive.

Do not make `Pin` a label named `Watch`. Pin state is separate from label text.

## Pin Versus Mark Watch

The current Dock code has an existing context-menu action named `Mark Watch`
that stores the label `Watch`. Pinning must not reuse that label as its data
model.

Coexistence rules:

- A row can be pinned with or without the `Watch` label.
- A row can have the `Watch` label without being pinned.
- If both are present, the row shows the pinned affordance and may also show the
  existing label treatment.
- Context menus can show both `Pin`/`Unpin` and existing label actions.
- The primary visible pinned state is the pin icon plus membership in the
  `Pinned` section, not the word `Watch`.

Future cleanup can rename or remove `Mark Watch`, but that is a separate product
decision. This spec does not require that cleanup before implementing swipe
pinning.

## Header, Collapse, And Reorder

The pinned section header is:

```text
Pinned N
```

Rules:

- Use `Pinned 1` for one item.
- Use `Pinned N` for multiple items.
- The word `Pinned` is the collapse/expand control.
- Tapping the `Pinned` label collapses the rows and leaves a compact header.
- Tapping it again expands the rows in the same persisted order.
- There is no `Manage` button, no `Manage pinned threads` sheet, and no
  management dialog.
- There is no `Show all N pinned` button. All visible pinned rows render inline
  when expanded.
- A native divider, section separator, or equivalent system-style boundary
  separates pinned rows from the selected lens body.

Pinned reorder rules:

- A pinned row can be long-pressed and dragged within the pinned section.
- Reorder uses native iOS list movement through SwiftUI `List`/`ForEach.onMove`
  or UIKit's standard collection/list interactive movement.
- Reorder must not depend on a visible reorder handle, edit mode, `Edit` button,
  or a custom drag/drop sorter.
- Reorder is not gated behind "two or more pins." A one-row pinned section has
  nowhere useful to move, but it should use the same list architecture and not
  enter a separate mode.
- The saved order is static. Message activity, tool activity, host activity,
  refreshes, and relaunches must not rearrange pinned rows.

## Row Content In The Pinned Section

Pinned rows use the same visual language as normal Dock rows, but can be
slightly denser.

Required content:

- Pin icon.
- Title.
- Host display name.
- Repository or working directory short name.
- Branch.
- Latest true-message summary or a clear fallback summary.
- True-message activity time when known.
- Chevron if tapping opens detail.

Status:

- Preserve meaningful status badges for `Running`, `Needs input`,
  `Needs approval`, and `Error`.
- Do not show badges for background states like `Idle`, `Not loaded`, or
  `Unknown` unless the row itself is a placeholder for missing pinned data.
- Never show `History` as a badge on every pinned row.
- Never show `Limited`.
- Never let tool output, command output, reasoning/thinking text, status text,
  request-card text, or unknown event text replace the pinned row's
  true-message summary.

Color:

- Preserve the existing left rail color.
- Pin icon should not replace the rail; rail color remains user-owned row
  metadata.

Touch target:

- Each pinned row remains large enough to tap reliably on iPhone.
- Row height can be compact, but should not drop below native comfortable touch
  target guidance.

## De-Duplication

A pinned row appears once in the current Dock render.

If a row is visible in the pinned section, remove it from the body content below
for that render. This keeps the phone list from wasting space and prevents the
user from seeing the same thread twice in one viewport.

Body group counts should reflect rows rendered in that body group, not hidden
pinned rows. If this causes confusion in simulator review, add a subtle group
detail such as `2 pinned above` only for groups that lost rows to the pinned
section.

Do not duplicate pinned rows inside host or branch groups by default.

## Ordering And Message Activity

Pinned section sort:

1. `pinnedOrder` ascending.
2. If old metadata has no `pinnedOrder`, migrate/synthesize deterministic order
   from existing pin metadata during load/projection.
3. If order values tie because of legacy or corrupt metadata, use `pinnedAt`
   and then stable host/thread id as a repair path.

Reason:

- Pinning chooses membership.
- Order pinned chooses default priority.
- Long-press drag reorder chooses manual priority.
- Activity updates must not hijack that manual priority.

Dock body ordering:

- Body rows and groups use newest true-message activity when that value is
  known.
- Raw tool/thinking/status/request/unknown activity can update status or detail,
  but it cannot move a row ahead of a row with a newer true message.
- If true-message activity is unknown and no cached message-derived value
  exists, the row should be treated as lacking loaded message data rather than
  pretending non-message activity is a message.
- Thread Detail's default `Messages` filter and Dock row/card preview/order
  must call the same Swift classifier.

## Capacity And Collapse

Behavior by count:

- 0 pinned: no pinned section.
- 1+ pinned and expanded: show all visible pinned rows inline.
- 1+ pinned and collapsed: show only the compact `Pinned N` header.

The pinned section can become taller if the user pins many rows. That is an
explicit user choice, and collapse is the escape hatch. Do not add a hidden cap
or overflow button.

## Lens Behavior

Lens selection never hides pinned rows. Explicit search/filter scope can hide
pinned rows. This distinction is central: `Host` and `Branch` are ways to look
at the Dock, while host and branch filters are user-selected narrowing rules.

### Newest

`Newest` shows:

```text
Pinned section
Newest body rows, newest true-message activity first, excluding rows already shown in Pinned
Host context rows for checking/partial/offline hosts, when relevant
```

The `Newest` body keeps the existing scan goal, but freshness is based on
true-message activity when known, not raw tool/thinking/status activity.

### Host

`Host` shows:

```text
Pinned section
Host groups, excluding rows already shown in Pinned
```

Pinned rows stay above host groups even if all pinned rows belong to one host.
This is the core behavior the user asked for.

Host group headers should remain useful but visually quieter than the pinned
section. Host groups must not look pinned merely because they contain pinned
rows.

### Branch

`Branch` shows:

```text
Pinned section
Branch groups, excluding rows already shown in Pinned
Host context rows for checking/partial/offline hosts, when relevant
```

Pinned rows stay above branch groups even if all pinned rows belong to one
branch.

Long branch names should not push the pinned section off screen or cause text
overlap.

## Search Behavior

Search is an explicit narrowing action, so it applies to pinned rows and body
rows.

Rules:

- If search is empty, show pinned rows normally.
- If search is non-empty, the pinned section remains in the same top position
  but contains only pinned rows matching the search.
- If no pinned rows match search, hide the pinned rows and show body matches.
- If some pinned rows are hidden by search, header text may become `Pinned 1 of
  3` to explain the narrowed state.
- Clearing search immediately restores all pinned rows.

Search matching should use the same fields as body rows:

- title
- host display name
- host id
- repository or working directory
- branch
- summary
- status label
- label
- source
- thread id

Do not create a separate pinned-only search system in the Dock screen.

## Filter Behavior

Explicit filters are also narrowing actions, so they apply to pinned rows.

Rules:

- If no filters are active, show all pinned rows.
- If filters are active, show only pinned rows that match the filters.
- If filters hide some pinned rows, use `Pinned X of N` in the pinned header
  when space allows.
- If filters hide every pinned row, do not show an empty pinned section above
  the body. The active filter summary already explains scope. If simulator
  testing proves that hidden pins are confusing, show a compact text-only hint
  such as `Pinned hidden by filters`; do not render an empty `Pinned 0 of N`
  row container.
- There is no management sheet that bypasses scope. The Dock render stays honest
  about the current search/filter scope.

Important distinction:

- `Host` and `Branch` lens selection does not hide pinned rows.
- Host and branch filters in the filter sheet do hide pinned rows because the
  user explicitly asked to narrow the dataset.

## Empty And Hidden States

No rows at all:

```text
No sessions
No sessions are loaded on reachable hosts.
```

Pinned rows exist but are hidden by search:

```text
No pinned rows match search
```

Only show that message inside the pinned section if the body has visible search
matches and the hidden pinned state would otherwise be confusing. Prefer
keeping the UI quiet.

Pinned rows exist but are hidden by filters:

```text
Pinned hidden by filters
```

Only show this if pinned state disappearance would be surprising in simulator
testing. The safer first implementation is `Pinned X of N` when partial and no
pinned section when zero pinned rows match.

Host offline with cached pinned rows:

- Show cached pinned rows in the pinned section.
- Show host freshness through existing global/host status UI.
- Do not erase pins.
- Do not show raw endpoint strings.

Pinned row has no loaded row data:

- If a last-known display snapshot exists, show the cached display snapshot and
  a quiet `Not loaded` status line.
- If no display snapshot exists, show a compact placeholder:

```text
[pin] Not loaded
      Amir-M5 - thread <short id>
      This pinned thread is not loaded yet.
```

The exact visible state is `Not loaded`, never `Limited`.

## Persistence

Pin state persists across:

- Pull to refresh.
- Stream reconnect.
- App foreground/background.
- App relaunch.
- Host temporary offline/online transitions.

MVP persistence can be device-local. It should use the same local metadata
ownership as existing user-owned row state.

Recommended local key:

```text
hostID + backendSessionID + threadID
```

Recommended metadata fields:

```text
isPinned: Bool
pinnedAt: Date
pinnedOrder: Int
lastKnownPinnedDisplay: optional cached row display data
```

Cross-device sync is not required for MVP unless the product explicitly adds a
relay-side user metadata layer. The UI must not imply cross-device sync until
that exists.

## Data Freshness

Pinned membership is local and immediate.

Pinned row content comes from the latest loaded or retained session summary, but
the card preview line comes only from true-message data. When live stream
updates change status or raw activity, the row can update in place without
changing pinned order and without replacing the message preview with tool or
thinking text.

Body row/order freshness should use true-message activity when known. If the
relay or app server cannot provide true-message activity for a row yet, preserve
the last known message-derived preview/order when available; otherwise show a
clear fallback such as `Not loaded` rather than treating non-message activity as
a message.

## Network And Error Behavior

Pin and unpin should not require a network request.

Failure modes:

- Local metadata save fails.
- Host no longer configured.
- Row identity is malformed.
- App reload races with the row action.

Required behavior:

- On successful local save, update the UI immediately.
- On failure, keep or restore the prior pin state.
- Show existing `ActionErrorBanner` style copy.
- Do not show a crash, empty screen, or raw Swift/JSON error.

Suggested error copy:

```text
Could not update pinned thread.
```

Do not say the relay failed unless the relay was actually involved.

## Accessibility

Pinned rows must be usable without swipe gestures.

VoiceOver/accessibility requirements:

- Pinned section has an accessibility header: `Pinned N`.
- Each pinned row includes `Pinned` in its accessibility value.
- Unpinned rows expose a custom accessibility action: `Pin thread`.
- Pinned rows expose a custom accessibility action: `Unpin thread`.
- Context menu offers the same actions.
- The pinned header exposes collapsed/expanded state.
- Native list movement should expose system reorder behavior where the platform
  supports it.
- The `Pin` swipe action has label `Pin`.
- The `Unpin` swipe action has label `Unpin`.

Suggested automation identifiers:

```text
codexdock.dock.pinned.section
codexdock.dock.pinned.header
codexdock.dock.pinned.divider
codexdock.dock.pinned.row.<hostID>.<threadID>
codexdock.dock.row.<hostID>.<threadID>.action.pin
codexdock.dock.row.<hostID>.<threadID>.action.unpin
```

Use existing `AutomationID.safeSegment` behavior for dynamic path segments.

## Visual Design

Use the existing Dock visual system:

- Grouped iOS background.
- 16 pt horizontal page padding.
- 8 pt card radius.
- Full-width search field.
- Existing segmented lens row.
- Existing row typography and metadata hierarchy.
- Existing color rail behavior.

Pinned section details:

- Header text uses compact subheadline or caption weight.
- Pin icon is blue for pinned state.
- Pinned rows can be 1-2 lines shorter than full body rows if summary remains
  readable.
- No `Manage` text button appears.
- Divider/separator treatment is native and quiet, not a heavy rule or nested
  card.
- Do not nest cards inside cards.
- Do not use decorative gradients, blobs, or marketing-style hero treatment.

Swipe actions:

- `Pin`: blue.
- `Unpin`: red.
- Keep action blocks large enough to read on iPhone 17.

## Copy

Allowed visible copy:

- `Pinned 1`
- `Pinned N`
- `Pin`
- `Unpin`
- `Unpinned`
- `Not loaded`

Disallowed visible copy for this feature:

- `Limited`
- `History` as a universal row badge
- `Needs me`
- `Rate limited`
- `Watch` as the primary pin state
- `Favorite` unless the product is explicitly renamed later
- `Manage`
- `Show all N pinned`
- `Manage pinned threads`

## State Machine

Per row:

```text
Unpinned
  swipe Pin / context Pin / accessibility Pin
    -> Pin save pending
      success -> Pinned
      failure -> Unpinned + action error

Pinned
  swipe Unpin / context Unpin / accessibility Unpin
    -> Unpin save pending
      success -> Unpinned
      failure -> Pinned + action error

Pinned
  long-press row / drag inside pinned section / drop
    -> Reorder save pending
      success -> Pinned with updated pinnedOrder
      failure -> Pinned with prior pinnedOrder + action error

Expanded pinned section
  tap Pinned label
    -> Collapsed pinned section

Collapsed pinned section
  tap Pinned label
    -> Expanded pinned section
```

Loaded row visibility:

```text
All loaded rows
  -> search
  -> filters
  -> split into pinned and body
  -> sort pinned by pinnedOrder
  -> sort/body group by selected lens
  -> render pinned section above body if pinned rows are visible
```

Dock card/order data:

```text
Thread events / relay summary
  -> shared true-message classifier
  -> newest true-message text + timestamp
  -> Dock card preview + Dock ordering freshness
```

## Simulator Acceptance Criteria

Simulator testing is the primary proof for this UX.

Run against `rtk make app SIM='iPhone 17'` or the repo's current simulator test
target. Do not claim completion from projection unit tests alone.

Required simulator checks:

- On `Newest`, swipe a normal row left and see blue `Pin`.
- Tap `Pin`; the row appears under `Pinned 1` at the top.
- Switch to `Host`; the pinned row remains above host groups.
- Switch to `Branch`; the pinned row remains above branch groups.
- Pin at least three rows; verify the pinned section shows all visible pinned
  rows and no `Show all N pinned` button.
- Verify newly pinned rows append after older pinned rows.
- Long-press a pinned row and drag it above another pinned row; verify order
  changes and survives refresh/relaunch.
- Verify reorder does not require a visible handle, `Edit` button, `Manage`
  button, or a minimum count mode.
- Tap `Pinned`; verify the pinned rows collapse. Tap `Pinned` again; verify
  the same rows expand in the same order.
- Swipe the pinned row left and see red `Unpin`.
- Tap `Unpin`; the row leaves the pinned section.
- Relaunch the app after pinning; the pinned row remains pinned.
- Pull to refresh after pinning; the pinned row remains pinned.
- Activate a host filter that excludes the pinned row; the pinned row is hidden
  and no empty pinned row container is shown. If the implementation adds a hint,
  it is text-only, such as `Pinned hidden by filters`.
- Clear filters; the pinned row returns.
- Search for text matching the pinned row; pinned row remains at top.
- Search for text not matching the pinned row but matching body rows; pinned
  row is hidden while body search results remain.
- Use a scripted row where tool/reasoning/status activity is newer than the
  newest true user/agent message. Verify the Dock card preview still shows the
  true message and the row order still follows true-message time.
- Open the same thread in detail with the default `Messages` filter and verify
  the Dock preview came from the same class of events.
- No visible UI shows `Limited`.
- No visible UI shows universal `History` badges on every row.
- No visible UI shows `Manage`, `Manage pinned threads`, or `Show all N pinned`.

Useful supporting unit tests:

- Projection splits pinned rows from body rows.
- Pinned rows are de-duplicated from body content.
- Pinned rows persist across metadata reload.
- Pinned order persists across metadata reload.
- Pin/unpin failure rolls back UI state.
- Reorder failure keeps the prior order.
- Search and filters apply to pinned and body rows consistently.
- Shared true-message classifier is used by Thread Detail and Dock mapping.
- Tool/reasoning/status/request/unknown events do not produce Dock card previews
  or Dock order freshness.

## Implementation Ownership Notes

These are notes for whoever implements the spec, not a separate architecture.

Likely owner paths:

- `CodexDock/State/LocalThreadMetadataStore.swift`: add pinned metadata.
- `CodexDock/Models/ThreadEvent.swift`: own shared true-message semantics used
  by Thread Detail and Dock.
- `CodexDock/Models/SessionSummaryMapper.swift`: map thread-list/relay rows to
  message-derived preview and activity without private Dock-only predicates.
- `CodexDock/State/DockStore.swift`: add `setPinned(_:for:)`,
  `reorderPinnedRows(...)`, and persistence handling.
- `CodexDock/State/DockSessionProjection.swift`: split visible rows into
  pinned rows and body rows, then sort pinned rows by pinned order.
- `CodexDock/Features/Dock/DockView.swift`: render pinned section above lens
  body, attach swipe actions, implement collapse, and use native list movement
  for pinned reorder.
- `CodexDock/Features/Dock/DockSharedViews.swift`: add pinned row/header view
  variants only if existing row view cannot stay readable.
- `CodexDock/Automation/AutomationID.swift`: add pin/unpin actions and pinned
  section identifiers; do not preserve dead Manage/Show-all IDs once those UI
  surfaces are deleted.
- `scripts/dock-relay-thread-summary-cache.mjs` and related relay stream code:
  when relay summary data is needed for ordering, emit true-message summary and
  true-message timestamp instead of raw updated-at summaries.
- `CodexDockTests/DockStoreTestsProjection.swift`: projection and filtering
  coverage.
- `CodexDockUITests/...`: simulator proof of swipe behavior.

Keep pinning local unless cross-device sync is explicitly added later.

## Implementation Risks

Risk: pinned rows duplicate in the body and make the first viewport noisier.

Mitigation: de-duplicate rows shown in the pinned section from body content.

Risk: filters hiding pinned rows feels like pinning is broken.

Mitigation: use `Pinned X of N` when some pinned rows are hidden and keep the
active filter summary visible.

Risk: pinned section grows too tall.

Mitigation: make the `Pinned` label collapse/expand the section. Do not cap the
visible rows or add overflow management.

Risk: manual order gets accidentally replaced by activity order.

Mitigation: persist `pinnedOrder` and make `DockSessionProjection` the only
place that sorts pinned rows. Activity updates must not change `pinnedOrder`.

Risk: Dock cards keep ripping between messages, tools, thinking, and status.

Mitigation: centralize true-message semantics in Swift, mirror the rule in the
relay only for DTO production, and add tests proving Dock preview/order match
Thread Detail's default `Messages` filter.

Risk: `Pin` conflicts with existing `Mark Watch` label behavior.

Mitigation: treat pin as separate metadata; do not encode pinning as a label.

Risk: user loses context because pinned rows are outside host/branch groups.

Mitigation: every pinned row must include host, repository or working
directory, and branch.

Risk: offline host makes pinned state look lost.

Mitigation: preserve local pinned state and show cached row or `Not loaded`
placeholder.

## Final Product Read

The best version of this feature is small and boring in the right way.

The user swipes a row, taps `Pin`, and that row is now always near the top of
Dock. New pins append after existing pins. If the order is wrong, the user
long-presses a pinned row and drags it into the right place. If the pinned area
gets tall, tapping `Pinned` collapses it.

The Dock card stays readable because it shows the newest true user/agent
message, not whatever tool, thinking, status, or request event happened last.
The same definition is used by Thread Detail's default `Messages` filter, so
the list and detail screen do not disagree about what counts as conversation.

The user can still use `Newest` for newest message activity, `Host` for machine
context, and `Branch` for branch context. The pinned rows stay above all of
those views because pinned is a personal watchlist, not a grouping category.

When the thread stops mattering, the user swipes it and taps `Unpin`. No
filter ceremony, no rate-limit language, no mystery status, no extra app tab.
