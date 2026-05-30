---
title: "Codex Dock - Swipe Pinned Top - Architecture Plan"
date: 2026-05-30
status: complete
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex, Composer 2.5 Fast]
doc_type: architectural_change
related:
  - docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/UX_SPEC.md
  - docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/README.md
  - docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/outputs/contact-sheet.png
  - /tmp/fresh-consult/codex-dock-pinned-ux-signoff-20260530T005359Z-ZQYMKQ/final.txt
---

# TL;DR

## Outcome

Codex Dock lets the user swipe a thread row to `Pin`, keeps pinned rows in a
`Pinned` section above `Newest`, `Host`, and `Branch`, and lets the user swipe a
pinned row to `Unpin`.

The 2026-05-30 planning amendment changes the pinned section from a capped,
recency-sorted watchlist with `Manage` into a static, user-ordered list:

- pin order is stable by the order rows were pinned;
- users can long-press a pinned row and drag it to rearrange pinned order with
  native UIKit collection/list movement;
- there is no visible reorder handle or edit-mode affordance;
- tapping the `Pinned` label collapses/expands the section;
- all visible pinned rows render inline, with no `Show all N pinned` button;
- there is no `Manage pinned` dialog or `Manage` button;
- a native divider/section boundary separates pinned rows from the rest of Dock.

The same amendment also changes what a Dock row/card is allowed to summarize
and sort by:

- Dock row preview text must come only from true user/agent message events;
- "true message" means the same predicate as Thread Detail's default
  `Messages` filter;
- tool calls, command output, reasoning/thinking, status, request cards, and
  unknown events must not become the Dock row preview;
- Dock row ordering must use the newest true-message activity, not the newest
  tool/thinking activity;
- the message predicate must be centralized so Thread Detail and Dock cannot
  drift.

## Problem

Dock can show hundreds of rows across hosts and branches. The current UI can
search, filter, group by host, and group by branch, but it has no user-owned way
to keep two or three important threads at the top while still using the normal
Dock lenses.

## Approach

Extend the existing local thread metadata and Dock projection path. Pinning is
device-local user metadata, not relay state. Projection splits visible rows into
`pinnedRows` and body rows, de-duplicates body rows, and the Dock view renders a
single persistent pinned section above the selected lens content.

## Plan

1. Add pinned metadata and projection contracts.
2. Centralize true-message classification and make Dock preview/order use that
   same classifier as Thread Detail's default filter.
3. Add Dock UI rendering, swipe/context/accessibility actions, and stable
   automation IDs.
4. Implement the amended static ordering, native drag reorder, collapse, no
   cap, no Manage dialog, divider separation, and true-message Dock cards.
5. Prove the behavior with focused Swift tests and an iPhone 17 simulator UI
   test using the existing scripted Dock stream path.

## Non-negotiables

- Pinned is a user action, not inferred status.
- No visible `Limited`, `Needs me`, or universal `History` badge.
- No fourth root app tab and no fourth Dock lens.
- No relay/app-server write for pin/unpin.
- No duplicate pinned row in the same rendered Dock view.
- No recency sorting inside the pinned section.
- No visible three-row cap, `Show all N pinned`, `Manage` button, or pinned
  management sheet.
- Reorder must use native UIKit collection/list movement APIs, not a custom
  drag/drop sorting implementation.
- Reorder must be available from the pinned section itself with a long press on
  a pinned row. It must not require a visible reorder indicator, Edit button,
  Manage sheet, or a minimum visible count gate.
- Dock row/card preview and ordering must be based on true messages only,
  using the same centralized predicate as Thread Detail's default `Messages`
  filter.
- The Dock row/card "message only" behavior is a blocking product requirement,
  not a cleanup detail. Implementation is incomplete if a row card can rip
  between the latest true message and a newer tool call, command output,
  reasoning/thinking token, request card, status event, or unknown event.
- Tooling, command output, reasoning/thinking tokens, request cards, status
  events, and unknown events must not replace the Dock row/card preview or
  reorder the Dock list.
- Simulator proof on `iPhone 17` is primary completion evidence.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-30
external_research_grounding: done 2026-05-30 - Apple native list movement, drag/drop, list/table grouping, and Thread Detail message filtering were rechecked for the amendment.
deep_dive_pass_2: done 2026-05-30
consistency_pass: done 2026-05-30
recommended_flow: research -> deep dive pass 1 -> deep dive pass 2 -> phase plan -> consistency pass -> implement-loop
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:0520bf58b6d02e55a671f436d227e4927407328328472e01e07e7c6b106f7880",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-30T01:41:06Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:d9ab298fd6d4c423f9d3bebc181b2034bef00598c2ccbccdc898f806fb0dab4f",
      "completed_at": "2026-05-30T01:41:33Z",
      "doc_hash_after": "sha256:36439b5556d18abd444fc072e3bcc697bb07d7b36367a7f0cc9270b4fd25b0d5"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T01:41:41Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:36439b5556d18abd444fc072e3bcc697bb07d7b36367a7f0cc9270b4fd25b0d5",
      "completed_at": "2026-05-30T01:42:33Z",
      "doc_hash_after": "sha256:c405fc6d4eae29577a8287b9df4f3b6d4591e640470e81d37d43bd1f71a80019"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T01:42:46Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:c405fc6d4eae29577a8287b9df4f3b6d4591e640470e81d37d43bd1f71a80019",
      "completed_at": "2026-05-30T01:43:22Z",
      "doc_hash_after": "sha256:72265880b3848c44c407d990f0fd71219d6e07e57a09bb62e8d7fdfda1f35f40"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-30T01:43:34Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:72265880b3848c44c407d990f0fd71219d6e07e57a09bb62e8d7fdfda1f35f40",
      "completed_at": "2026-05-30T01:44:22Z",
      "doc_hash_after": "sha256:eee024bd73c3ccbd8c92f37a7fb103c563b78d3145c35416a9cde0d659dd08b5"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-30T01:44:56Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:eee024bd73c3ccbd8c92f37a7fb103c563b78d3145c35416a9cde0d659dd08b5",
      "completed_at": "2026-05-30T01:52:41Z",
      "doc_hash_after": "sha256:ce23904eadc15aafeb4e6c4cc86e29c67e04e86e90c28f1a12f5839894f00bd9"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, a real iPhone 17 simulator run can pin a Dock row by
swiping it, see that row in a `Pinned` section above `Newest`, switch to `Host`
and `Branch` while pinned rows remain above the grouped content in stable
user-owned order, long-press a pinned row and drag it to reorder with the native
iOS move interaction and no visible reorder handle, tap `Pinned` to
collapse/expand the section, then swipe a pinned row to unpin it and see it
leave the pinned section.

In the same simulator run, rows that have newer tool output, reasoning deltas,
or request/status noise must keep showing the newest true user/agent message as
their Dock row/card preview and must remain ordered by that true-message
timestamp. Opening the same thread in detail with the default `Messages` filter
must show the same class of events the Dock used for its preview/order.

## 0.2 In scope

- Device-local pin state on Dock rows.
- Persistent pinned section at the top of the Dock content area across
  `Newest`, `Host`, and `Branch`.
- Stable pinned ordering based on order pinned, with newly pinned rows appended
  after existing pins unless the user manually reorders them.
- Native iOS long-press drag-to-reorder inside the expanded pinned section.
- No visible reorder handle, grip, edit button, edit mode, or management
  surface is required to reorder.
- Reorder availability is not gated on a minimum count. A one-row pinned section
  has no useful destination to move to, but the UI architecture must not special
  case reorder behind a "2+ pins" mode.
- Collapsing/expanding the pinned section by tapping the `Pinned` label.
- All visible pinned rows render inline; no inline cap, overflow button, or
  management sheet.
- A native divider/section boundary between pinned rows and the selected lens
  body when both are visible.
- Dock row/card preview text sourced only from true messages, using the same
  predicate as Thread Detail's default `Messages` filter.
- Dock row ordering based on newest true-message activity, not newest
  tool/thinking/request/status activity.
- Shared message-classification logic instead of separate Dock and Thread
  Detail predicates.
- Row de-duplication from the selected lens body when the row is visible in
  `Pinned`.
- Search/filter scoped behavior exactly as defined in the UX spec.
- Context menu and accessibility alternatives for body-row `Pin`; pinned-row
  `Unpin` keeps swipe and accessibility alternatives because long press on a
  pinned row is reserved for native reorder.
- Stable automation IDs for simulator/UI proof.
- Focused model/projection/store tests and iPhone 17 simulator test coverage.

## 0.3 Out of scope

- Cross-device pin sync.
- Relay or app-server mutation for pin state.
- A fourth root tab or fourth Dock lens.
- Replacing the existing filter sheet.
- A `Manage pinned` dialog/sheet/button.
- A custom drag/drop reorder engine.
- Renaming or removing `Mark Watch` as part of this change.
- Adding new analytics infrastructure.

## 0.4 Definition of done (acceptance evidence)

- `DockRowViewModel` exposes pinned state from local metadata, including
  metadata-only pinned rows when a live thread is not currently loaded.
- `DockSessionProjection` exposes pinned rows separately from body rows and
  de-duplicates body content.
- The Dock UI renders `Pinned N` above all three lenses, exposes body-row `Pin`
  through swipe, context menu, and accessibility actions, and exposes
  pinned-row `Unpin` through swipe and accessibility actions without stealing
  the long-press reorder gesture.
- The Dock UI does not cap pinned rows at three and does not render
  `Show all N pinned`, `Manage`, or a pinned management sheet.
- Pinned rows stay in stable user order. Activity updates do not move them.
- Native drag reorder changes persisted pinned order and survives refresh and
  relaunch.
- Reorder starts by long-pressing a row, not tapping a handle. No visible
  reorder indicator is shown.
- Tapping the `Pinned` label collapses and expands the section without changing
  pin membership or order.
- A system-style divider or section boundary visually separates pinned rows
  from body rows/groups.
- Dock rows/cards show the newest true-message preview only. Tool calls,
  command output, reasoning/thinking tokens, status events, request cards, and
  unknown items never replace the row/card preview.
- Dock row sort freshness uses newest true-message activity. Non-message
  activity can update status/progress, but it cannot move a row ahead of a row
  with a newer true message.
- A "no rip" regression fixture proves that a Dock card stays on the same
  true-message preview/order when newer non-message events arrive, while Thread
  Detail's default `Messages` filter shows the same message class the Dock used.
- Thread Detail's default filter and Dock preview/order call the same Swift
  classifier. Relay-side message summary logic, where needed, uses the same
  named rule with fixture coverage so the Node and Swift runtimes stay aligned.
- Pin state persists after refresh/relaunch through the existing local metadata
  store path.
- A pinned thread whose live row is unavailable still renders from its cached
  local display snapshot, or as a clear `Not loaded` placeholder if no snapshot
  exists.
- Focused Swift tests pass for projection, persistence, and action failure
  behavior.
- `rtk make app-test SIM='iPhone 17'` or an equivalent repo-owned iPhone 17
  simulator target proves the swipe flow in the simulator.
- Composer 2.5 Fast code review agrees the code is complete and elegant.
- Thermo-nuclear code quality review finds no unresolved structural blocker.

## 0.5 Key invariants (fix immediately if violated)

- `Pinned` membership has exactly one source of truth: local thread metadata.
- Pin/unpin does not depend on network success.
- A pinned row shown in `Pinned` does not also render in the same body list or
  group.
- Host/Branch lenses do not hide pinned rows; explicit filters/search can.
- Pinned order has its own local metadata field. `pinnedAt` remains an audit and
  compatibility fact, not the primary sort key after the amendment.
- Reordering is available from the visible pinned list without a minimum count
  gate. If search/filter scope hides some pinned rows, movement applies to the
  visible ordered subset without introducing a separate mode or visible handle;
  implementation must define and test how hidden rows retain their relative
  order.
- Pinning does not encode itself as the `Watch` label.
- Existing row labels and rail colors keep working.
- The definition of true message has one Swift owner. Today that means
  `visibilityCategory == .message` and `kind` is `.userMessage` or
  `.agentMessage`, matching `ThreadDetailMessageFilter.default`.
- Dock does not inspect raw event kinds independently when deciding preview or
  order. It consumes a message-derived summary/activity value from the shared
  model/protocol path.
- If a row has only non-message activity newer than its last true message, its
  status can update but its Dock preview/order stay on the last true message.
- Unpinning clears only pin fields, order fields, and cached pin display data;
  it does not erase label or rail metadata.
- No fallback or runtime shim is introduced.

## 0.6 User-opened requirements from 2026-05-30 amendment

`R-DP-001 - Dock cards show only true messages`

The Dock row/card preview line must display only the newest true user/agent
message that Thread Detail's default `Messages` filter would include. Tool
calls, command output, request-card text, reasoning/thinking tokens, status
events, and unknown events must never become the Dock card preview.

`R-DP-002 - Dock ordering follows true-message freshness`

Dock row ordering in `Newest`, host groups, and branch groups must use the
newest true-message timestamp. Newer non-message activity can update row status
or diagnostics, but it must not move the row above another row with a newer
true message.

`R-DP-003 - One shared message classifier`

Thread Detail and Dock must call the same Swift classifier for the meaning of
true message. The relay may mirror that rule in Node only at the stream-summary
boundary, and the mirror must have fixture coverage for included and excluded
event classes.

`R-DP-004 - Pinned reorder uses the native iOS long-press movement pattern`

Pinned reorder must start from a long press on a pinned row and drag to a new
position. There is no reorder handle, no `EditButton`, no edit-mode toggle, and
no visible instruction text. The implementation must use native UIKit
collection/list interactive movement or a simulator-proven equivalent native
SwiftUI movement path; it must not use a homegrown drag/drop sorting engine.

`R-DP-005 - Reorder is not a 2+ item mode`

The pinned section uses the same long-press-capable row surface even when only
one pinned row is visible. A single row has nowhere useful to move, so the store
may no-op the resulting order write, but the UI must not expose a separate
"reorder unavailable until two pins" mode.

`R-DP-006 - "Message" means Thread Detail's default Messages filter`

The Dock card must use the exact same semantic rule as
`ThreadDetailMessageFilter.default`, which is `.messages`, through
`ThreadMessageSemantics.isDefaultVisibleMessage(_:)`. It must not use the
broader `ThreadEventKind.agentMessage` filter, the Thread Detail `All` filter,
the raw relay `preview`, generic `summary` / `latestSummary`, raw `updatedAt`,
or string labels to decide what the visible Dock card says or where the row
sorts. If the Dock stream supplies `messageSummary` and `messageUpdatedAt`,
those fields are valid only because the relay generated them from the mirrored
true-message rule.

Acceptance evidence must prove the user-visible equivalence: for a fixture
thread with a true user/agent message followed by newer tool output, reasoning,
request, status, or unknown activity, the Dock card keeps the true-message
preview/order and opening Thread Detail with the default `Messages` filter shows
that same class of event while excluding the newer non-message activity.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Product clarity: user-chosen pins must be visually obvious and removable.
2. User control: pinned order must be stable, manually rearrangeable, and not
   hijacked by newest activity.
3. Message fidelity: Dock row/card preview and list order must track the same
   true-message concept as Thread Detail, not tools or reasoning.
4. Correct scope: pinned rows stay above all Dock lenses but still respect
   explicit search/filter narrowing.
5. Existing architecture fit: use metadata -> row projection -> Dock projection
   -> SwiftUI rendering.
6. Simulator truth: prove the gesture in the iPhone 17 simulator, not only with
   unit tests.
7. Maintainability: avoid turning `DockView` into an unbounded conditional pile.

## 1.2 Constraints

- For the requested no-handle, no-edit-button long-press reorder, the primary
  native path is UIKit collection/list interactive movement. Apple's
  `UICollectionViewController.installsStandardGestureForInteractiveMovement`
  is the canonical built-in gesture: it installs a standard long-press-based
  recognizer for reordering collection-view items. A SwiftUI wrapper around
  UIKit collection/list movement is acceptable because the movement remains
  system-owned.
- The implementation may use the equivalent `UICollectionView` interactive
  movement calls directly: `beginInteractiveMovementForItem(at:)`,
  `updateInteractiveMovementTargetPosition(_:)`, and
  `endInteractiveMovement()` / `cancelInteractiveMovement()`. This is native
  iOS row movement; the custom code only bridges the gesture result into
  `DockStore.reorderPinnedRows(...)`.
- SwiftUI `List` / `ForEach.onMove(perform:)` is secondary, not primary, for
  this exact UX because Apple's SwiftUI edit-mode path normally exposes edit
  controls. It is acceptable only if iPhone 17 simulator proof shows the same
  long-press row movement with no visible handle, no `EditButton`, and no edit
  mode.
- Reorder must not require an `EditButton`, edit mode, a visible grip, or any
  persistent reorder affordance. The user-facing gesture is long-press row,
  drag, drop.
- Swipe remains the user-facing pin/unpin action. If the existing
  `ScrollView`/`LazyVStack` surface prevents native swipe and native reorder
  from coexisting, the plan must prefer a native collection/list subsection
  over accumulating more custom gesture code.
- Local metadata is asynchronous and may fail; failure must roll back or keep
  the old state with an action error.
- The Dock already has `Mark Watch`, rail color, archive, host grouping, branch
  grouping, search, filters, and host status rows; pinning must compose with
  them rather than replace them.
- Simulator tests need deterministic rows, so scripted Dock stream data is the
  safest proof path.
- The relay/client boundary may add optional read-only message-summary fields
  if needed to avoid sorting by raw `updatedAt`. That is not a relay mutation
  and is in scope for this amendment.
- If message-derived activity is temporarily unknown, do not overwrite a known
  cached message preview/order with non-message activity. Use the last known
  message-derived values when available; otherwise the row must be visibly
  treated as lacking loaded message data rather than pretending tool activity is
  a message.

## 1.3 Architectural principles (rules we will enforce)

- Put durable pin state in `LocalThreadMetadata`.
- Cache the minimum pinned row display data in local metadata so pinned rows can
  survive refresh/relaunch and temporary host/thread absence.
- Store pinned order in local metadata. Use contiguous integer order values as
  the canonical sort key; derive missing order values from old metadata during
  load/projection so existing pinned rows still render deterministically.
- Put row-level `isPinned` and `pinnedAt` on `DockRowViewModel`.
- Put row-level `pinnedOrder` on `DockRowViewModel`.
- Put list splitting and de-duplication in `DockSessionProjection`.
- Put order sorting in `DockSessionProjection`; the view must not sort pinned
  rows itself.
- Put true-message classification in a shared model helper used by
  `ThreadDetailMessageFilter.default`, `SessionSummaryMapper`, and Dock row
  projection. Delete private one-off predicates such as
  `SessionSummaryMapper.isStoredMessageEvent`.
- Put message-derived row preview and message-derived row activity on the
  summary/stream model so Dock projection can sort without opening Thread
  Detail.
- Put reorder mutation in `DockStore`; the view receives a native collection or
  list movement result and the store writes local metadata.
- Keep UI rendering declarative: the view renders projection truth rather than
  recomputing pinned membership.
- Add tiny, named view helpers for the pinned section instead of large inline
  branches in `DockView`.
- Use automation IDs as UI-test handles, not as product logic.

## 1.4 Known tradeoffs (explicit)

- Device-local pins are intentionally simpler than cross-device sync. The UX
  spec says cross-device sync is not required for MVP.
- Search/filter can hide pinned rows by design. This keeps explicit narrowing
  honest even though the default Dock behavior keeps pins always above lenses.
- The earlier capped/Manage design is superseded. The pinned section can become
  taller when the user pins many rows; that is acceptable because pinning many
  rows is an explicit user choice and the section can collapse.
- Native long-press reorder may require embedding a UIKit collection/list
  surface inside the Dock pinned section. That is a larger UI architecture
  change than a custom `DragGesture`, but it is the right tradeoff because the
  user explicitly asked for a canonical iOS reorder implementation with no
  visible reorder indicator.
- The Dock stream may need a small optional DTO addition for
  `messageUpdatedAt`/message-derived summary. That is acceptable because the
  user experience breaks when the client only has raw `updatedAt`, which can be
  advanced by tools, reasoning, or status noise.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Dock loads stream-backed session summaries per configured host, projects them
into `DockRowViewModel`, and renders one of three lenses: `Newest`, `Host`, or
`Branch`. Local metadata currently supports user-owned `label` and `rail`
state. Row actions live in `DockView` as context-menu actions.

## 2.2 What's broken / missing (concrete)

There is no first-class pin state. A user can label a row `Watch`, but that is
just row text and does not keep the row at the top of Dock. The current lens
model helps browse a large list but does not solve the watchlist problem from
the UX spec.

## 2.3 Constraints implied by the problem

Pinning should be local, immediate, and independent from relay/app-server
health. It needs to affect the Dock projection because the same behavior must
hold across all three lenses and must de-duplicate rows from body content.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->

## 3.1 External anchors (papers, systems, prior art)

The UX spec package already records the product research basis:

- Apple Human Interface Guidelines: lists/tables, search/search fields, context
  menus, tab bars, and toolbars.
- Nielsen Norman Group usability heuristics: visibility, user control,
  recognition over recall, consistency.
- Baymard applied-filter guidance: active scope should be visible and
  removable.

Adopted conclusions:

- Swipe actions are a good primary row affordance on iOS when paired with
  accessible/context-menu alternatives.
- A pinned/watchlist section must be visibly owned by the user and removable.
- Pinned state should not become top-level navigation unless it is the app's
  primary destination.
- A huge list benefits from a visible top watchlist, but the watchlist itself
  should obey user-owned ordering once the user explicitly asks for pin order
  and drag reorder.
- Native section/list boundaries are the right first choice for separating a
  pinned section from the body. A divider should clarify structure without
  becoming a heavy visual wall.

2026-05-30 amendment research:

- Apple's public UIKit documentation for collection-view interactive movement
  is the best match for the requested iOS pattern. The
  `UICollectionViewController.installsStandardGestureForInteractiveMovement`
  API installs the standard long-press-based gesture recognizer for item
  reordering.
- Apple's public `UICollectionView.beginInteractiveMovementForItem(at:)`
  documentation says interactive movement starts when the gesture begins,
  updates target position while the gesture changes, and ends or cancels when
  interaction ends. That maps directly to the desired user behavior:
  long-press a pinned row, drag it to a new position, drop it.
- The implementation must therefore prefer native UIKit collection/list
  movement for pinned-row reorder. A SwiftUI `UIViewRepresentable` wrapper is
  allowed because the gesture, item movement, and move callbacks still belong
  to UIKit; the wrapper only connects the native reorder result to SwiftUI
  state.
- Apple's SwiftUI `EditMode` and `onMove(perform:)` APIs remain useful context,
  but they are not the primary path for this requirement because SwiftUI's
  normal list movement is tied to edit-mode move controls. The requested UX
  explicitly rejects visible reorder handles, an `EditButton`, and edit mode.
- `draggable`/`dropDestination` are not the first-choice APIs for this
  pinned-row reorder. They are transfer/drop APIs for moving data between
  sources and destinations. This task is same-list row reordering, so the
  canonical implementation must be native collection/list movement.
- Research links:
  - SwiftUI `onMove(perform:)`:
    <https://developer.apple.com/documentation/swiftui/dynamicviewcontent/onmove%28perform%3A%29>
  - UIKit standard long-press interactive movement:
    <https://developer.apple.com/documentation/uikit/uicollectionviewcontroller/installsstandardgestureforinteractivemovement>
  - UIKit begin interactive movement:
    <https://developer.apple.com/documentation/uikit/uicollectionview/begininteractivemovementforitem%28at%3A%29>
  - UIKit collection-view interactive movement:
    <https://developer.apple.com/documentation/uikit/uicollectionview>
  - Apple HIG drag and drop:
    <https://developer.apple.com/design/human-interface-guidelines/drag-and-drop>
  - Apple HIG lists and tables:
    <https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>
- UIKit still exposes table row movement concepts through table/list editing,
  while older `UITableViewRowAction` APIs are deprecated in favor of modern
  swipe action configuration. The direction is native list/table affordances,
  not custom gesture stacks for core row behavior.
- Apple Human Interface Guidelines for lists/tables emphasize predictable row
  behavior, visible structure, and platform-standard editing affordances. For
  this Dock, the practical read is: use system list movement for reorder and
  system section/separator treatment for visual grouping.
- Apple Human Interface Guidelines for drag and drop say iOS and iPadOS support
  drag/drop through touchscreen gestures and accessibility/keyboard paths, and
  advise alternate ways to accomplish drag/drop actions. For this Dock, the
  row-drag path must be native and the fallback should stay with existing
  context/accessibility actions, not a homegrown visible reorder UI.
- Apple Human Interface Guidelines for lists/tables say lists can support
  reordering and should use appropriate grouping/style for structure. For this
  Dock, the pinned/body boundary should be a native section/separator, not a
  decorative card-within-card treatment.

2026-05-30 user-amended message-classification research:

- `CodexDock/Models/ThreadEvent.swift` already owns the Thread Detail filter
  model. `ThreadDetailMessageFilter.default == .messages`.
- `ThreadDetailMessageFilter.messages.includes(_:)` currently admits only
  events where `event.visibilityCategory == .message` and the kind is
  `.userMessage` or `.agentMessage`.
- `ThreadEventNormalizer` classifies stored and live `userMessage` and
  `agentMessage` items as `.message`. It classifies reasoning/plan deltas as
  `.thinking`, command/tool output as `.tooling`, request cards as `.request`,
  status/closed events as `.system`, and unsupported shapes as `.unknown`.
- `SessionDetailView` applies `selectedMessageFilter.visibleEvents(from:)` to
  the loaded thread before rendering `ThreadMessageListView`, so the visible
  default detail transcript is already defined by that filter.
- Current Swift code already has the intended owner:
  `ThreadMessageSemantics.isDefaultVisibleMessage(_:)`, and
  `ThreadDetailMessageFilter.messages.includes(_:)` calls it.
- Current `SessionSummaryMapper` derives Dock thread-list preview and
  `messageActivityDate` from `ThreadEventNormalizer.events(from:)` plus
  `ThreadMessageSemantics.latestMessage(in:)`. This is the correct direction:
  no Dock-only private predicate should be reintroduced.
- Current stream DTO/model code already carries separate message-derived
  fields: `DockStreamSessionDTO.messageSummary`,
  `DockStreamSessionDTO.messageUpdatedAt`, and
  `SessionSummary.messageActivityDate`.
- Current `DockSessionTable.sortedSessions(for:)`,
  `DockSessionTable.summary(from:)`, `SessionRowProjector.activityDisplay(for:)`,
  and `DockSessionProjection.rowPrecedesByRecency` now run through the
  message-derived row date/summary path. That is the intended no-rip behavior:
  raw `updatedAt` can remain a transport/freshness fact, but it must not be the
  Dock card/order fact when message-derived activity exists.
- Current relay code decorates rows with `messageSummary` and
  `messageUpdatedAt`, and `scripts/dock-relay-thread-summary-cache.mjs` returns
  newest user/agent message text plus timestamp. The remaining hardening is to
  keep that Node predicate named, tested, and aligned with the Swift
  true-message rule so reasoning, plan, tool, output, request, status, and
  unknown items cannot sneak back into Dock cards or ordering.

Rejected conclusions:

- Do not create a separate `Pinned` root app tab or fourth Dock lens. The UX
  spec explicitly rejects that because the normal Dock lenses must remain
  useful.
- Do not rely only on context menus; hidden menus are not enough for primary
  row actions.
- Do not implement reorder with a bespoke `DragGesture`, hover gap detector, or
  custom drop target. The approved route is native UIKit collection/list
  interactive movement, with SwiftUI only wrapping that native control if
  needed.
- Do not render a reorder handle, grip, Edit button, or Manage button merely to
  reveal reorder. The long-press row drag is the affordance.
- Do not keep the earlier `Manage` sheet/cap/overflow design; the new product
  direction says unpin by swipe and reorder by drag.
- Do not create a Dock-only definition of "message" based on labels,
  substrings, row summaries, or DTO source fields.
- Do not let `latestSummary` override the Dock card unless it is explicitly
  known to be produced from the true-message rule.
- Do not sort Dock rows by raw `updatedAt` when a newer non-message event is the
  only reason that timestamp changed.

## 3.2 Internal ground truth (code as spec)

- `docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/UX_SPEC.md` was the
  original product contract for this work.
- The user amendment on 2026-05-30 supersedes the original UX spec wherever it
  says pinned rows sort by newest activity, render only the first three,
  include `Show all N pinned`, or use a `Manage pinned threads` sheet.
- `docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/outputs/contact-sheet.png`
  visually anchors the desired screens.
- `/tmp/fresh-consult/codex-dock-pinned-ux-signoff-20260530T005359Z-ZQYMKQ/final.txt`
  records Composer 2.5 Fast signoff with `BLOCKING: none`.
- `CodexDock/State/LocalThreadMetadataStore.swift` owns local user metadata
  persistence today (`label`, `rail`) and will own pin state plus cached pinned
  display data.
- `CodexDock/Models/ThreadEvent.swift` owns `ThreadEvent`,
  `ThreadEventVisibilityCategory`, `ThreadDetailMessageFilter`, and
  `ThreadEventNormalizer`; it is the correct Swift home for centralized
  true-message semantics.
- `CodexDock/Models/SessionSummaryMapper.swift` maps app-server/relay
  `ThreadDTO` rows into `SessionSummary`; it is where thread-list preview and
  message activity must enter the app model.
- `CodexDock/Models/SessionSummary.swift`,
  `CodexDock/AppServer/DockStreamDTO.swift`, and
  `CodexDock/State/DockSessionTable.swift` carry Dock-stream row summary and
  activity into the app.
- `CodexDock/State/SessionRowProjector.swift` merges local metadata into
  `DockRowViewModel`.
- `CodexDock/State/DockSessionProjection.swift` owns search, filter, lens
  projection, grouping, summary text, facets, and empty reasons.
- `CodexDock/State/DockStore.swift` owns row actions that mutate local metadata
  (`setLabel`, `setRail`) and refresh Dock state after persistence.
- `CodexDock/Features/Dock/DockView.swift` owns the Dock UI, current
  `Newest`/`Host`/`Branch` lens rendering, row context menu actions, and
  `DockRowView` navigation.
- `CodexDock/Features/Dock/DockSharedViews.swift` owns reusable Dock row/card
  views.
- `CodexDock/Automation/AutomationID.swift` owns stable UI automation IDs.
- `CodexDock/State/ScriptedDockStreamClient.swift` and
  `CodexDockUITests/CodexDockAutomationSmokeTests.swift` provide deterministic
  simulator proof paths through `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`.

Canonical owner path:

```text
LocalThreadMetadata
  -> SessionRowProjector
  -> DockRowViewModel.isPinned / pinnedAt
  -> DockSessionProjection.pinnedRows + body rows/groups
  -> DockView pinned section + row actions
```

Canonical true-message path:

```text
ThreadEventNormalizer
  -> ThreadEvent.visibilityCategory / kind
  -> shared true-message classifier
  -> ThreadDetailMessageFilter.default
  -> Thread Detail default transcript

ThreadDTO / turns or relay message-summary DTO
  -> shared true-message classifier
  -> SessionSummary.messagePreview / messageActivity
  -> SessionRowProjector.summary / lastActivityDate
  -> DockSessionProjection row/group ordering
  -> Dock row/card preview and order
```

Relay boundary:

```text
thread/turns/list or relay summary cache
  -> Node-side true-message helper with the same fixture cases
  -> Dock stream message summary + messageUpdatedAt
  -> Swift DTO decode
  -> SessionSummary message fields
```

Compatibility posture:

- Preserve existing local metadata JSON decode compatibility with an explicit
  decoder: missing `isPinned`, `pinnedAt`, and cached display keys decode to
  `isPinned == false`, `pinnedAt == nil`, and no cached display.
- Preserve existing `label` and `rail` behavior.
- Preserve existing row context menu actions.
- Cleanly add `Pin`/`Unpin` actions without a bridge, fallback, or shadow store.

Adjacent surfaces:

- Archive rows use their own metadata path but the UX spec is Dock-only; Archive
  does not render a pinned section or pin/unpin actions.
- `ArchiveView` reuses `DockRowView`, so any visual pin indicator added to the
  shared row view must be opt-in from `DockView` instead of becoming a global
  Archive affordance by accident.
- Archive ordering and time labels keep their existing archive/thread freshness
  semantics unless a separate Archive message-fidelity change is planned. If
  `DockRowViewModel.lastActivityDate` becomes message-derived for Dock rows,
  `ArchiveSessionProjector` must explicitly preserve Archive's raw row activity
  instead of accidentally inheriting Dock ordering semantics.
- Session detail does not need a pin button for MVP because the request is row
  swipe in Dock. `ThreadDetailHeader` may display the selected Dock row's
  message-derived summary/time as launch context, but Thread Detail freshness
  and default transcript truth still come from the detail rehydrate path and
  `ThreadMessageSemantics`.
- Relay/app-server mutation is explicitly out of scope. Read-only Dock stream
  DTO additions for message-derived summary/activity are in scope and required
  for this amendment; app-server protocol changes are out of scope unless a
  later plan explicitly chooses them.
- README/package docs should keep calling `Newest`/`Host`/`Branch` lenses, not
  tabs.

Reusable patterns:

- `DockStore.setLabel` and `DockStore.setRail` are the model for local metadata
  mutation.
- `DockProjectionOptions` is the existing place to pass view options into
  projection.
- `AutomationID.Dock.rowAction(...)` is the existing row action ID pattern.
- Scripted stream UI tests are the existing realistic simulator proof style.

## 3.3 Decision gaps that must be resolved before implementation

None.

The UX spec plus the 2026-05-30 amendment resolve the product decisions that
could otherwise branch:

- Pinned is local user metadata.
- Host/Branch lenses keep pins visible; explicit filters/search may hide them.
- Pinned order is static by pin order and user drag order, not activity order.
- New pins append after existing pins.
- Reorder uses native UIKit collection/list interactive movement.
- Reorder starts from long-pressing a row and dragging; no visible indicator is
  shown.
- Reorder is not gated on "at least two pins" as a mode. With one visible pin,
  there is nothing to move around, but the section does not enter a different
  UI state.
- The `Pinned` label collapses/expands the section.
- There is no pinned cap, overflow button, or management sheet.
- No cross-device sync for MVP.
- No relay mutation.
- Dock row/card preview and row ordering use true-message activity, not raw
  tool/thinking/status activity.
- True-message classification is centralized in Swift and mirrored at the
  Node relay boundary only with fixture tests.
- No fourth tab/lens.
- No `Pinned 0 of N` empty row container when filters hide all pinned rows.

<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->

## 4.1 On-disk structure

```text
CodexDock/State/LocalThreadMetadataStore.swift
  Codable local metadata: label, rail

CodexDock/State/DockStore.swift
  Observable Dock state, local metadata loading/saving, row actions

CodexDock/State/SessionRowProjector.swift
  SessionSummary + local metadata -> DockRowViewModel

CodexDock/Models/ThreadEvent.swift
  Thread events, visibility categories, Thread Detail filters, normalizer

CodexDock/Models/SessionSummaryMapper.swift
  ThreadDTO -> SessionSummary, including current shortEventSummary derivation

CodexDock/Models/SessionSummary.swift
  App-side row summary/activity model consumed by Dock projection

CodexDock/AppServer/DockStreamDTO.swift
  Relay Dock stream session DTO

scripts/dock-relay-thread-summary-cache.mjs
  Relay-side latest summary warming from thread turns

scripts/dock-relay-session-table.mjs
  Relay Dock stream row normalization and updatedAt/summary assignment

CodexDock/State/DockSessionProjection.swift
  Search/filter/lens projection -> rows/groups/summary/facets/empty reason

CodexDock/Features/Dock/DockView.swift
  Dock shell, search, lens controls, projected content, row navigation/actions

CodexDock/Features/Dock/DockSharedViews.swift
  DockRowView and supporting shared row/card views

CodexDock/Automation/AutomationID.swift
  Stable accessibility IDs

CodexDockTests/DockStoreTestsProjection.swift
  Projection behavior tests

CodexDockUITests/CodexDockAutomationSmokeTests.swift
  iPhone 17 simulator UI proof through real app launch
```

## 4.2 Control paths (runtime)

Dock load path:

```text
DockStore.load / refresh
  -> metadataStore.load()
  -> synchronizeStreams()
  -> DockSessionTable.snapshot(hosts, localMetadata, now)
  -> SessionRowProjector.rows(from:)
  -> DockSnapshot.rows
  -> DockSnapshot.project(options:)
  -> DockView.projectedContent(...)
```

Current local metadata action path:

```text
Dock row context menu
  -> DockStore.setLabel / setRail
  -> FileLocalThreadMetadataStore.save(...)
  -> DockStore.refresh()
  -> row reprojects with updated label/rail
```

Current lens rendering:

- `Newest`: `projection.rows`.
- `Host`: `projection.groups` grouped by host.
- `Branch`: `projection.groups` grouped by branch.

Current Thread Detail message rendering:

```text
ThreadDetailStore snapshot.events
  -> SessionDetailView selectedMessageFilter defaults to ThreadDetailMessageFilter.default
  -> ThreadDetailMessageFilter.messages.includes(event)
  -> visibilityCategory == .message && kind in {userMessage, agentMessage}
  -> ThreadMessageListView
```

Current Dock card summary/order path:

```text
thread/list row or dock stream row
  -> ThreadDTO.latestSummary / preview / turns / updatedAt
  -> SessionSummaryMapper or DockSessionTable.summary(from:)
  -> SessionSummary.shortEventSummary + lastActivity
  -> SessionRowProjector.summary + lastActivityDate
  -> DockSessionProjection rowPrecedesByRecency
```

## 4.3 Object model + key abstractions

- `LocalThreadMetadataKey`: `hostID + backendSessionID + threadID`.
- `LocalThreadMetadata`: optional `label`, optional `rail`, `isPinned`,
  `pinnedAt`, `pinnedOrder`, and optional `lastKnownPinnedDisplay`.
- `DockRowViewModel`: row display model with title, host, repo, branch, status,
  last activity, summary, rail, label, origin, and pinned metadata.
- `DockProjectionOptions`: selected lens, search text, filters.
- `DockSessionProjection`: projected rows/groups/summary/facets/empty reason.
- `DockProjectionGroupViewModel`: host/branch groups.

Missing / still requiring proof today:

- The current implementation has `isPinned`, `pinnedAt`, `pinnedOrder`, cached
  pinned display, `pinnedRows`, `Pin`/`Unpin`, and a pinned-section render path.
- The current implementation still must prove the amended UX in the iPhone 17
  simulator: no three-row cap, no `Show all N pinned`, no `Manage pinned`
  sheet/button, collapse by tapping `Pinned`, native long-press reorder, scoped
  reorder under search/filter, and a pinned/body divider.
- Dock card preview and ordering are now wired to message-derived fields in
  Swift, but the implementation is incomplete until tests prove the no-rip
  case: newer tool, thinking, request, status, or unknown activity must not
  replace the Dock preview or move the row ahead of a row with a newer true
  message.
- The relay has message-derived stream fields, but the Node message predicate
  still needs explicit fixture coverage against the same included/excluded
  event classes as the Swift `ThreadMessageSemantics` rule.

## 4.4 Observability + failure behavior today

- Metadata persistence logs through `DockLog.persistence`.
- Metadata save failure currently sets `DockStore.state = .error(...)`.
- Dock action failures for archive use `actionError`; local metadata failures do
  not yet use that less-disruptive banner path.
- App diagnostics must not log prompts or secrets.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current `Newest` shape:

```text
Dock                                  Online 2/2
[Search sessions, repo, branch, host]
[Newest] [Host] [Branch] [filter]
400 shown - Hosts: Any - Branches: Any ...

[row]
[row]
[row]
```

Current `Host` and `Branch` shapes:

```text
Dock controls

[Host group header]
  [row]
  [row]
```

The current implementation has a pinned row section between the filter summary
and selected lens body, but it still needs the amendment changes: static order,
native reorder, collapse, no cap, no Manage, and a clearer divider/section
boundary.

## 4.6 Deep-dive pass 2 refinements

`DockView.swift` is already a large file and owns root tab shell plus Dock
content. Pinning should avoid adding large inline branches there. If the pinned
section needs more than a few lines of layout, it should be a small local view
or shared Dock view helper.

`DockSessionProjection` already has the cleanest point to decide row membership,
body de-duplication, result counts, and hidden pinned counts. Keeping those
decisions there prevents search/filter/lens drift.

`ThreadEvent.swift` already has the cleanest point to decide event semantics.
Keeping true-message classification there prevents Thread Detail, Dock list
mapping, and row projection from quietly developing different meanings of
"message".

<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->

## 5.1 On-disk structure (future)

```text
CodexDock/State/LocalThreadMetadataStore.swift
  add isPinned/pinnedAt/pinnedOrder/lastKnownPinnedDisplay to
  LocalThreadMetadata

CodexDock/Models/ThreadEvent.swift
  add shared true-message semantics used by Thread Detail default filtering and
  Dock row/card preview/order derivation

CodexDock/Models/SessionSummary.swift
  carry message-derived preview and message-derived activity/freshness fields
  separately from raw thread updatedAt if both are needed

CodexDock/Models/SessionSummaryMapper.swift
  replace private message-summary predicate with shared true-message semantics
  and map message-derived preview/activity into SessionSummary

CodexDock/AppServer/DockStreamDTO.swift
  add optional read-only message-derived activity/summary fields if relay stream
  rows cannot otherwise express true-message freshness

scripts/dock-relay-thread-message-semantics.mjs or equivalent
  centralize relay-side true-message item classification at the Node boundary

scripts/dock-relay-thread-summary-cache.mjs
  return latest true-message text plus latest true-message timestamp

scripts/dock-relay-session-table.mjs
  emit Dock stream summary/order fields from true-message data, not raw tool
  updatedAt

CodexDock/State/DockStore.swift
  add setPinned(_:for:) and reorderPinnedRows(...) using existing metadata
  persistence path, capturing pinned row display snapshots and writing
  contiguous pinned order values

CodexDock/State/SessionRowProjector.swift
  project pinned metadata onto DockRowViewModel and synthesize cached
  metadata-only pinned rows when the live summary is absent

CodexDock/State/DockSessionProjection.swift
  expose pinnedRows sorted by pinnedOrder and body rows/groups with
  de-duplication

CodexDock/Features/Dock/DockView.swift
  render pinned section above selected lens body; wire swipe/context actions,
  collapse, native reorder, and pinned/body separation

CodexDock/Features/Dock/DockSharedViews.swift
  add small pinned-section/header helper only if needed

CodexDock/Automation/AutomationID.swift
  add pinned section, collapse/header, reorder, row, and pin/unpin action IDs;
  remove dead Manage/Show-all IDs when implementation deletes those surfaces

CodexDockTests/*
  add projection/store/metadata tests

CodexDockUITests/CodexDockAutomationSmokeTests.swift
  add scripted simulator pin flow
```

## 5.2 Control paths (future)

Pin action:

```text
Dock row swipe/context/accessibility action
  -> DockStore.setPinned(true, for: row)
  -> LocalThreadMetadata.isPinned = true
  -> LocalThreadMetadata.pinnedAt = now()
  -> LocalThreadMetadata.pinnedOrder = next contiguous order value
  -> LocalThreadMetadata.lastKnownPinnedDisplay = compact snapshot of row
  -> save metadata
  -> publish/reproject
  -> DockSessionProjection.pinnedRows includes row
  -> DockView renders row after existing pins in Pinned section above lens body
```

Unpin action:

```text
Pinned row swipe/accessibility action
  -> DockStore.setPinned(false, for: row)
  -> LocalThreadMetadata.isPinned = false / pinnedAt = nil
  -> LocalThreadMetadata.pinnedOrder = nil
  -> LocalThreadMetadata.lastKnownPinnedDisplay = nil
  -> save metadata
  -> publish/reproject
  -> row leaves Pinned section
  -> row appears in body only if it matches current lens/search/filter scope
```

Reorder action:

```text
Long-press a pinned row in the expanded Pinned section
  -> native UIKit collection/list move begins with no visible reorder handle
  -> DockStore.reorderPinnedRows(orderedIDs or source/destination)
  -> store rewrites contiguous pinnedOrder values for the full pinned set
  -> save metadata for affected pinned rows
  -> publish/reproject
  -> DockSessionProjection.pinnedRows keeps the new user order
```

Collapsed section action:

```text
Tap the visible `Pinned` label/header
  -> toggle Dock-local pinned section collapsed state
  -> no metadata or relay mutation
  -> header remains visible with count
  -> pinned rows hide until expanded
```

Projection order:

```text
loaded session summaries + metadata-only pinned rows
  -> search
  -> filters
  -> visibleRows
  -> split visible pinned rows from visible body rows
  -> sort pinned rows by pinnedOrder, then pinnedAt, then stable id
  -> build Newest rows or Host/Branch groups from body rows only
```

Cached pinned row path:

```text
DockSessionTable.snapshot(hosts, localMetadata, now)
  -> SessionRowProjector.rows(from live summaries)
  -> SessionRowProjector.cachedPinnedRows(from metadata, excluding live keys)
  -> DockSnapshot.rows contains live rows plus metadata-only pinned rows
```

True-message classification path:

```text
ThreadEventNormalizer emits ThreadEvent(kind, visibilityCategory)
  -> ThreadMessageSemantics.isDefaultVisibleMessage(event)
  -> ThreadDetailMessageFilter.default.includes(event)
  -> Thread Detail default `Messages` list
```

Dock card preview/order path:

```text
ThreadDTO turns or relay message-summary DTO fields
  -> ThreadMessageSemantics.latestMessage(...)
  -> SessionSummary.messagePreview
  -> SessionSummary.messageActivityDate
  -> SessionRowProjector.summary / lastActivityDate
  -> DockSessionProjection row/group ordering
```

Relay stream path:

```text
thread/list row + optional thread/turns/list warm data
  -> relay true-message helper
  -> summary = newest true-message text
  -> messageUpdatedAt = newest true-message timestamp
  -> DockStreamSessionDTO optional fields
  -> DockSessionTable.summary(from:)
```

Unknown message-data path:

```text
No turns, no relay messageUpdatedAt, no cached message summary
  -> do not promote tool/thinking/status updatedAt into message freshness
  -> keep last known message-derived values if metadata/cache has them
  -> otherwise mark message preview/activity as unknown/not loaded
```

## 5.3 Object model + abstractions (future)

`LocalThreadMetadata` gains:

```swift
var isPinned: Bool
var pinnedAt: Date?
var pinnedOrder: Int?
var lastKnownPinnedDisplay: LocalPinnedDisplaySnapshot?
```

Pinned order semantics:

- `pinnedOrder` is the canonical sort key for pinned rows.
- Lower values render first.
- Pinning a new row appends it after the current maximum pinned order.
- Drag reorder rewrites affected pinned rows to contiguous `0...n-1` values.
- Older metadata with `isPinned == true` and no `pinnedOrder` is migrated in
  memory and on next save by sorting `pinnedAt` ascending, then stable
  host/thread ID. This keeps the phrase "order pinned" literal: first pinned
  stays first.
- `pinnedAt` remains useful for migration, diagnostics, and tie-breaking. It is
  not allowed to reorder an already ordered pinned list when activity changes.

`LocalPinnedDisplaySnapshot` stores only non-secret row display facts needed to
render a pinned row later:

```swift
struct LocalPinnedDisplaySnapshot: Codable, Equatable, Sendable {
    var title: String
    var hostDisplayName: String
    var hostEndpoint: String
    var repository: String
    var branch: String
    var status: DockRowStatusKind
    var lastActivity: String
    var lastActivityDate: Date
    var summary: String
    var rail: DockRowRail
    var label: String?
    var originKind: LocalPinnedDisplayOriginKind
}
```

Because the cached snapshot stores `DockRowStatusKind`, that enum must add
`Codable` conformance as part of the metadata model change.

`DockRowViewModel` gains:

```swift
let isPinned: Bool
let pinnedAt: Date?
let pinnedOrder: Int?
```

`DockSessionProjection` gains:

```swift
let pinnedRows: [DockRowViewModel]
let allPinnedRows: [DockRowViewModel]
let pinnedSummary: DockPinnedSummary
```

`DockPinnedSummary` should be a tiny value type, not UI state:

```swift
struct DockPinnedSummary: Equatable, Sendable {
    let visibleCount: Int
    let totalCount: Int
    let hiddenByScopeCount: Int
}
```

Rationale: the projection owns scope truth. The UI should not recompute whether
pins are hidden by search/filter.

`ThreadMessageSemantics` or an equivalently named shared Swift helper owns the
true-message rule. The current implementation lives in
`CodexDock/Models/ThreadEvent.swift`:

```swift
enum ThreadMessageSemantics {
    static func isDefaultVisibleMessage(_ event: ThreadEvent) -> Bool
    static func latestMessage(in events: [ThreadEvent]) -> ThreadEvent?
    static func activityDate(for event: ThreadEvent) -> Date?
}
```

Small preview/date convenience helpers may be added if they reduce duplication,
but they must call this same classifier rather than introducing a second
Dock-only predicate.

Current required predicate:

```swift
event.visibilityCategory == .message
    && (event.kind == .userMessage || event.kind == .agentMessage)
```

This distinction is deliberate. The current app can normalize some reasoning
or plan events as `kind == .agentMessage` while giving them
`visibilityCategory == .thinking`. Those events are visible under Thread
Detail's explicit `Agent` filter, but they are not visible under the default
`Messages` filter. Dock cards and Dock ordering must match the default
`Messages` filter, not the broader `agentMessage` kind filter.

`ThreadDetailMessageFilter.messages.includes(_:)` must call this helper. The
Dock list path must call the same helper through `SessionSummaryMapper` and row
projection. Do not keep a second predicate in `SessionSummaryMapper`,
`DockSessionProjection`, or `DockView`.

`SessionSummary` should carry message-derived row facts explicitly enough that
Dock does not need to open thread detail to sort:

```swift
let messagePreview: SessionSummaryText
let messageActivityDate: Date?
let activityDate: Date // raw thread freshness if still needed for diagnostics/status
```

If the project keeps existing names for compatibility, the contract still must
be clear:

- the field rendered as Dock row/card `summary` is message-derived;
- the field used as `DockRowViewModel.lastActivityDate` for row/group ordering
  is message-derived;
- raw `updatedAt` remains available only for freshness/status diagnostics, not
  row/card preview or ordering.

Relay DTO fields must make message derivation explicit. The chosen
backward-compatible Dock stream shape is:

```swift
public let summary: String?          // legacy/raw row summary; not a Dock message source
public let messageSummary: String?
public let messageUpdatedAt: Int64?
public let updatedAt: Int64?         // raw thread freshness for diagnostics/status only
```

`messageSummary` is the newest true-message text. `messageUpdatedAt` is the
newest true-message timestamp. `summary` stays decodable for older relay rows
and diagnostics, but Dock row/card preview and ordering must not use `summary`
unless the row also has the explicit message-derived fields or the relay schema
later states that `summary` has become message-derived. Missing
message-derived fields do not allow the client to classify tool/thinking
activity as message activity.

Result count decision:

- `DockProjectionSummary.resultCount` and summary text should count all visible
  rows after search/filter/idle scope, including pinned rows.
- Body group counts should count body rows rendered inside that group, excluding
  visible pinned rows.
- `DockPinnedSummary.totalCount` tracks pinned rows before current search/filter
  scope so `Pinned X of N` is available when some pins are hidden.

Message preview/order decision:

- The Dock row/card summary line displays newest true-message text only.
- The Dock row/card time label and `lastActivityDate` used for sorting should
  represent newest true-message activity when known.
- "Newest true-message text" means the newest event returned by
  `ThreadMessageSemantics.latestMessage(in:)`, which is the same event class
  that `ThreadDetailMessageFilter.default.visibleEvents(from:)` would display.
  It does not mean newest `kind == .agentMessage`, newest `summary`, newest
  relay `preview`, newest request card, or newest raw activity timestamp.
- Non-message activity can still update row status (`running`, `needsApproval`,
  `needsInput`, `idle`, error/offline state) and freshness diagnostics.
- A newer command output, tool call, reasoning delta, request card, or status
  event must not replace the row/card summary or move the row above a row with a
  newer true message.
- If a thread has no loaded true-message evidence yet, keep last known
  message-derived preview/activity from cache. If no cache exists, the row
  should show an explicit not-loaded/unknown message state rather than using
  non-message text as a fake preview.
- Search can still match metadata fields such as title, host, repo, branch,
  label, status, and thread ID. Search should not expose hidden tool/thinking
  text through the Dock card summary.
- Required true-message fixtures:
  - user message: included in Thread Detail default filter, eligible for Dock
    card preview, eligible for Dock ordering;
  - normal agent message: included in Thread Detail default filter, eligible
    for Dock card preview, eligible for Dock ordering;
  - reasoning/plan item, including one normalized as `kind == .agentMessage`
    with `visibilityCategory == .thinking`: excluded from Thread Detail default
    filter, excluded from Dock card preview, excluded from Dock ordering;
  - command/tool/output/request/status/unknown item: excluded from Thread
    Detail default filter, excluded from Dock card preview, excluded from Dock
    ordering.
- Required ordering fixture: if Thread A has a true message at `10:00` and a
  tool output at `10:05`, while Thread B has a true message at `10:03`, Thread
  B sorts above Thread A in `Newest`, `Host`, and `Branch` group recency. Thread
  A may still show a running/error/request status, but it must not borrow the
  `10:05` tool timestamp for message order.

Ordering and reorder decision:

- The pinned section renders every visible pinned row inline when expanded.
- There is no inline cap and no overflow affordance.
- There is no `Manage` button, no `Manage pinned threads` sheet, and no
  `Show all N pinned` button.
- Native iOS reorder is enabled when the section is expanded. It starts with a
  long press on the row; there are no reorder handles to show or hide.
- Reorder is not gated on a minimum pinned count. One visible pinned row has no
  alternative position, but the row uses the same long-press-capable list
  surface as any larger pinned set.
- If a search/filter hides some pinned rows, moving the visible subset must keep
  hidden pinned rows in their previous relative order. The implementation must
  either move the dragged visible row within the full pinned order around the
  nearest visible neighbors or prove a clearer native behavior in the
  simulator. Do not introduce a separate edit mode for scoped reorder.
- If the canonical native reorder path requires a UIKit collection/list
  subsection, use that native subsection even if it means wrapping UIKit inside
  SwiftUI. Do not add custom drag/drop sorting to keep the current
  `ScrollView`/`LazyVStack` shape.
- If native reorder cannot be made to coexist with the current Dock layout in
  the iPhone 17 simulator, stop and reopen planning rather than falling back to
  homebrew drag.

Collapse decision:

- The `Pinned` label/header is a button. Tapping it toggles collapsed/expanded.
- Collapsed state is Dock-local UI state. Persist it with app-local UI storage
  if the existing app pattern supports that cleanly; otherwise keep it stable
  across lens switches during the current app session.
- Collapsed state does not hide the header/count and does not alter pin
  membership, order, search, filters, or body de-duplication.
- When collapsed, body rows/groups still exclude pinned rows because pinned
  membership remains active. The user can expand to see pins again or swipe body
  rows to unpin only if a row is visible there under explicit scope.

Divider/section boundary decision:

- Render a visual separator between the pinned section and the selected lens
  body whenever the pinned section header is visible and body rows/groups or
  host context rows exist below it.
- Prefer native `List` section separation or a single system-style `Divider`.
  Do not use a thick card boundary, decorative band, or text-heavy explanation.
- The divider is visual only and should be accessibility-hidden.

Cached/Not-loaded decision:

- If a pinned thread has a live row, render the live row.
- If a pinned thread has no live row but has `lastKnownPinnedDisplay`, render
  that cached display with current host metadata where available.
- If a pinned thread has no live row and no cached display, render a compact
  row titled `Not loaded` with host/thread identity and pinned affordance so the
  user can still unpin it.

## 5.4 Invariants and boundaries

- Local metadata is the single source of truth for pin membership.
- `ThreadMessageSemantics` is the Swift source of truth for true-message
  membership. Thread Detail and Dock must call it instead of owning separate
  predicates.
- The relay may mirror the same true-message item rule in Node only because it
  cannot import Swift. That mirror must be tiny, named, and covered by shared
  fixture cases.
- Projection is the single place that splits pinned rows from body rows.
- UI actions call `DockStore.setPinned`; they do not edit metadata directly.
- Pin/unpin uses existing persistence and refresh paths.
- Compatibility is preserved for older metadata JSON by defaulting missing
  pinned fields to unpinned.
- `LocalThreadMetadata.isEmpty` is true only when `label == nil`, `rail == nil`,
  `isPinned == false`, `pinnedAt == nil`, `pinnedOrder == nil`, and
  `lastKnownPinnedDisplay == nil`.
- No relay/app-server mutation for pins. Optional read-only relay DTO additions
  for message-derived summary/activity are allowed when backward-compatible.
- No runtime fallback/shim.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Default pinned shape:

```text
Dock                                  Online 2/2
[Search sessions, repo, branch, host]
[Newest] [Host] [Branch] [filter]
400 shown - Hosts: Any - Branches: Any ...

v Pinned 4
  [pin] row title
        host - repo - branch
        newest true-message preview
        now                            >
  [pin] row title
        host - repo - branch
        newest true-message preview
        now                            >
  [pin] row title
        host - repo - branch
        newest true-message preview
        now                            >
  [pin] row title
        host - repo - branch
        newest true-message preview
        now                            >

------------------------------------------------

<selected lens body, excluding visible pinned rows>
```

Collapsed pinned shape:

```text
> Pinned 4
------------------------------------------------
<selected lens body, excluding visible pinned rows>
```

Reorder shape:

```text
v Pinned 4
  row pinned first
  row pinned second
  row pinned third

long-press row pinned third, then drag it above row pinned second
-> store writes new pinnedOrder values
-> rows stay in that order after refresh/relaunch
```

One-row pinned shape:

```text
v Pinned 1
  row pinned first

<same row surface; no visible reorder indicator; no special "reorder disabled"
message>
```

Swipe pin:

```text
[normal row content] | Pin |
```

Swipe unpin:

```text
[pinned row content] | Unpin |
```

Hidden by filters:

```text
<no empty Pinned 0 row container>
<optional text-only hint: Pinned hidden by filters>
```

No Manage/overflow shape:

```text
v Pinned 5
  row 1
  row 2
  row 3
  row 4
  row 5

<no Manage button>
<no Show all 5 pinned button>
<no pinned management sheet>
```

<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->

## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
|---|---|---|---|---|---|---|---|
| True-message classifier | `CodexDock/Models/ThreadEvent.swift` | `ThreadMessageSemantics`, `ThreadDetailMessageFilter.includes` | Shared helper exists and `.messages` calls it | Keep this as the single Swift source of truth; do not reintroduce view/mapper-local predicates | Thread Detail and Dock must mean the same thing by "message" | `isDefaultVisibleMessage(_:)`, latest-message helpers | `ThreadEventNormalizerTests` |
| Thread-list summary mapping | `CodexDock/Models/SessionSummaryMapper.swift` | `ThreadEventNormalizer.events`, `ThreadMessageSemantics.latestMessage` | Mapper derives summary/activity from the shared classifier | Preserve this path; only trust relay summaries when they are explicitly message-derived | Prevent tools/reasoning from becoming Dock cards | `SessionSummary.shortEventSummary`, `messageActivityDate` | `ThreadListMappingTests` |
| Session model | `CodexDock/Models/SessionSummary.swift` | `lastActivity`, `shortEventSummary`, `messageActivityDate` | Raw activity and message-derived activity are separate | Keep Dock UI/order on message-derived preview/activity while preserving raw activity for freshness/diagnostics | Dock order must use message activity, not raw tool freshness | optional `messageActivityDate`; message-derived preview contract | Mapping/projector tests |
| Dock stream DTO | `CodexDock/AppServer/DockStreamDTO.swift` | `DockStreamSessionDTO.updatedAt`, `.summary`, `.messageSummary`, `.messageUpdatedAt` | Stream carries raw activity plus optional message-derived summary/activity | Keep `messageSummary` and `messageUpdatedAt` backward-compatible and make Dock rows prefer them | Relay stream rows need enough data to sort correctly without opening detail | optional `messageSummary`, optional `messageUpdatedAt`, raw `updatedAt` for diagnostics/status | Dock stream decode/backward-compat tests |
| Relay message semantics | `scripts/dock-relay-thread-message-semantics.mjs` or equivalent | new helper or existing predicate extraction | Message classification is still embedded in summary cache | Centralize Node-side item predicate for `userMessage`/`agentMessage`; exclude reasoning, plan, command/tool, request/status/unknown | Relay cannot import Swift but must mirror the named rule | `isDefaultVisibleMessageItem`, latest-message helper | `rtk npm run test:relay` |
| Relay summary cache | `scripts/dock-relay-thread-summary-cache.mjs` | `latestMeaningfulMessageFromTurns`, `latestMeaningfulSummaryFromTurns` | Returns latest user/agent text plus timestamp | Keep timestamped true-message output and add fixture coverage for excluded item types | Dock ordering needs message freshness, not row `updatedAt` | `{ text, timestampSeconds }` or equivalent | relay phase5 tests |
| Relay Dock stream | `scripts/dock-relay-session-table.mjs` | `normalizeThread`, `fetchDockSessionRows` | Emits raw `summary`/`updatedAt` plus message-derived fields when available | Preserve raw fields for compatibility, but require Dock clients to use message-derived fields for cards/order | Prevent Dock stream order from ripping on tools/thinking | stream row message fields | relay session table tests |
| Dock row projection | `CodexDock/State/SessionRowProjector.swift` | `makeRow(summary:)`, `activityDisplay(for:)`, `rowSummary(for:)` | Renders message-derived summary/date in default Dock mode | Keep default `activityMode == .dockMessage`; raw mode must stay diagnostic/test-only | Row/card should match Thread Detail default filter | `row.summary`, `row.lastActivityDate` message-derived | Projection tests |
| Dock projection ordering | `CodexDock/State/DockSessionProjection.swift` | `rowPrecedesByRecency`, `groupPrecedes` | Sorts by row `lastActivityDate`, which default projection makes message-derived | Keep sorting in projection and keep row dates message-derived before projection receives them | Newest/Host/Branch order must track messages | no view-side sorting | Projection tests |
| Metadata model | `CodexDock/State/LocalThreadMetadataStore.swift` | `LocalThreadMetadata` | Stores label/rail plus first-pass pin fields | Add/keep `isPinned`, `pinnedAt`, `pinnedOrder`, and `lastKnownPinnedDisplay` with explicit decode-safe defaults | Pin membership, stable order, and cached display must persist locally | `LocalThreadMetadata(isPinned:pinnedAt:pinnedOrder:lastKnownPinnedDisplay:)` | Metadata compatibility/store tests |
| Cached pin display | `CodexDock/State/LocalThreadMetadataStore.swift` | `LocalPinnedDisplaySnapshot` | Does not exist | Store compact display facts at pin time | Pinned rows must remain useful after refresh/relaunch/offline host | Codable snapshot type | Metadata compatibility/store tests |
| Cached status encoding | `CodexDock/State/DockStore.swift` | `DockRowStatusKind` | `RawRepresentable`, `Equatable`, `Sendable`, `CaseIterable` only | Add `Codable` conformance | `LocalPinnedDisplaySnapshot` stores row status | Codable status enum | Metadata compatibility tests |
| Row projection | `CodexDock/State/SessionRowProjector.swift` | `makeRow(summary:)`, cached pinned projection helper | Applies label/rail and first-pass pin fields | Apply pinned order metadata to live and cached rows | Row UI/projection needs stable order even when live summary is absent | `DockRowViewModel.isPinned`, `.pinnedAt`, `.pinnedOrder` | Projection tests |
| Row model | `CodexDock/State/DockStore.swift` | `DockRowViewModel`; constructors in `CodexDockTests/DockStoreTestsProjection.swift`, `CodexDockTests/DockStoreTestSupport.swift`, `CodexDockTests/ThreadDetailStoreTestSupport.swift` | First-pass pin fields only | Add pinned order display field and update all constructor call sites found by `rg "DockRowViewModel\\("` | Carry stable user-owned order through projection | pinned row fields | Many row test helpers |
| Dock projection | `CodexDock/State/DockSessionProjection.swift` | `DockSessionProjectionProjector.project()` | Splits pinned/body but sorts pinned by activity | Sort pinned rows by `pinnedOrder`; keep body de-duplication; expose visible/all pinned rows | Pinned list must not reorder when activity changes | `pinnedRows`, `allPinnedRows`, `pinnedSummary` | `DockStoreTestsProjection` |
| Groups | `CodexDock/State/DockSessionProjection.swift` | `hostGroups`, `branchGroups` | Groups all visible body rows | Group body rows excluding pinned rows visible above | Avoid duplicate row in one render | body rows only | Host/branch tests |
| Summary | `CodexDock/State/DockSessionProjection.swift` | `summary(for:)` | Counts visible rows | Count visible pinned + body rows after scope | Keep "shown" honest while de-duping body | summary input includes visible pinned and body rows | Projection tests |
| Store action | `CodexDock/State/DockStore.swift` | `setPinned(_:for:)` | Adds/removes pin membership | Ensure pin appends after current pins and unpin clears order | UI action owner | `setPinned(Bool, for:)` | DockStore tests |
| Reorder action | `CodexDock/State/DockStore.swift` | new `reorderPinnedRows(...)` | Does not exist | Persist contiguous `pinnedOrder` values after native move | Drag reorder must survive refresh/relaunch | `reorderPinnedRows(...)` | DockStore tests |
| Store errors | `CodexDock/State/DockStore.swift` | `save(metadata:for:)` | Local metadata save failure sets full error state | Prefer `actionError` for row action failure | Keep Dock usable | no state crash on local save failure | Failure tests |
| Automation IDs | `CodexDock/Automation/AutomationID.swift` | `DockRowAction`, `Dock` IDs | First-pass pin/manage IDs | Keep pin/unpin/pinned section IDs; add collapse/reorder IDs if needed; remove dead Manage/Show-all IDs with UI deletion | Simulator proof | IDs in spec | AutomationIDTests/UI tests |
| UI section | `CodexDock/Features/Dock/DockView.swift` or helper | `projectedContent` | Renders pinned section with cap/Manage | Render all visible pinned rows inline before lens body, with collapsible header and divider | Core UX | `pinnedSection(...)` | UI tests |
| UI reorder | `CodexDock/Features/Dock/DockView.swift` or helper | pinned row list | Does not exist | Use native UIKit collection/list interactive movement for long-press row reorder; no custom drag/drop sort and no visible handle/edit mode | Canonical iOS reorder matching requested gesture | native movement result -> store reorder | UI tests |
| UI row actions | `CodexDock/Features/Dock/DockView.swift` | `dockRow`, `rowActions` | First-pass custom swipe/context pin/unpin | Keep body-row swipe/context/accessibility `Pin`; keep pinned-row swipe/accessibility `Unpin` without attaching a pinned-row context menu that intercepts long-press reorder | Primary gesture + fallback | `pinAction(row)`/`unpinAction(row)` helpers | UI tests |
| Removed management | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/Features/Dock/DockPinnedViews.swift` | `PinnedThreadsManageView`, `pinnedManageButton`, `pinnedShowAllButton` | First pass has Manage sheet and overflow | Delete Manage button/sheet and Show-all button | User rejected this surface; unpin by swipe and reorder by drag replace it | no management API | UI tests assert absence |
| Collapse | `CodexDock/Features/Dock/DockView.swift` or helper | pinned header | Header is static | Tapping `Pinned` toggles collapsed/expanded state | User asked for direct collapse | `isPinnedCollapsed` state | UI tests |
| Divider | `CodexDock/Features/Dock/DockView.swift` or helper | between pinned and body | No explicit contract | Add native section boundary/divider when pinned header and body both render | Visual association/separation | system separator/divider | UI tests or screenshot proof |
| Shared row view | `CodexDock/Features/Dock/DockSharedViews.swift` | `DockRowView` | No visible pin icon | Add optional/opt-in pin icon or compact pinned treatment if needed | Visual clarity in Dock without leaking pin affordance into Archive | `DockView` opts into pin indicator; Archive default remains no pin action/section | Snapshot/manual simulator |
| Archive adjacent surface | `CodexDock/State/ArchiveSessionProjector.swift`, `CodexDock/Features/Archive/ArchiveView.swift` | shared `DockRowViewModel`/`DockRowView` use | Archive rows share row model/view and sort by `lastActivityDate` | Do not add Archive pinned section or Archive pin actions; keep any pin visual opt-in to Dock rendering; preserve Archive raw activity semantics explicitly if Dock row activity becomes message-derived | Dock-only UX must not create an accidental Archive feature or silently change Archive ordering | no Archive pin actions; Archive raw activity remains explicit | Existing Archive tests/visual check |
| Thread detail launch context | `CodexDock/State/ThreadDetailStore.swift`; `ThreadDetailHeader` | `ThreadDetailHeader(host:row:)` copies row summary/activity into header | Header can inherit whatever row opened detail | Keep detail transcript truth on rehydrate + shared message filter; allow header to show selected Dock row message-derived context without using it as detail freshness proof | Dock message semantics must not become a fake Thread Detail data source | no Session detail pin button; detail events still rehydrate from thread APIs | ThreadDetailStore tests |
| Accessibility | `CodexDock/Features/Dock/DockSharedViews.swift`, `CodexDock/Features/Dock/DockView.swift` | row accessibility value/actions, pinned section header | No pinned semantics | Include `Pinned` in pinned row accessibility value; expose `Pin thread` and `Unpin thread`; expose collapsed/expanded header state | Gesture must have accessible equivalents without a Manage surface | accessibility labels/values/actions | UI tests/manual simulator |
| Scripted stream | `CodexDock/State/ScriptedDockStreamClient.swift` | `retention` scenario | Deterministic rows exist | Reuse as UI-test data; no product change unless needed | Reliable simulator proof | none | UI test |
| UI tests | `CodexDockUITests/CodexDockAutomationSmokeTests.swift` | pin flow tests | First-pass pin flow only | Drive swipe Pin, stable order, native reorder, collapse/expand, true-message card/order behavior, no Manage/Show-all, divider presence, lens switch, refresh, relaunch, Unpin | Required proof | new test helper(s) | `rtk make app-test SIM='iPhone 17'` |
| UX docs | `docs/mockups/.../README.md` | package index | Mockup package | Link plan only if useful after implementation | Keep docs discoverable | no stale tab/lens wording | docs readback |

## 6.2 Migration notes

- Metadata compatibility: old JSON entries lacking `isPinned`, `pinnedAt`, or
  `lastKnownPinnedDisplay` decode to unpinned and no cached display through an
  explicit `init(from:)`.
- Metadata compatibility after the amendment: pinned JSON entries lacking
  `pinnedOrder` remain pinned. During projection/store load, synthesize stable
  order from `pinnedAt` ascending and then stable host/thread ID. On the next
  pin/unpin/reorder save, write contiguous `pinnedOrder` values.
- Delete list: none initially. Do not delete `Mark Watch`; pin and label
  coexist.
- Amendment delete list: delete the first-pass `Manage` sheet/button and
  `Show all N pinned` UI. Delete dead automation IDs/tests for those surfaces
  unless still needed as explicit absence assertions.
- Adjacent surfaces explicitly out of scope: relay/app-server pin mutation
  protocol, app-server protocol changes, Archive pinned display, Session detail
  pin button.
- Compatibility posture: preserve existing APIs and add fields/actions; no
  breaking protocol change. Optional read-only relay Dock stream DTO fields
  `messageSummary` and `messageUpdatedAt` are in scope and must decode safely
  when absent.
- Live docs/comments: update this plan/worklog and only touched comments; do
  not create broad docs cleanup work.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

- Do not create a second metadata store for pins.
- Do not compute pinned rows separately in `DockView`.
- Do not make `Pinned` a filter or a lens.
- Do not create a bespoke simulator harness; use existing `app-test` and
  scripted stream patterns.
- Do not add a new service-side metadata path until cross-device pin sync is
  explicitly requested.
- Do not keep the first-pass custom reorder/sort path if native iOS movement is
  available.
- Do not keep any visible pinned cap, management sheet, or overflow affordance.
- Do not keep separate definitions of "message" in Thread Detail, Dock mapping,
  and relay summary cache without a named shared helper and fixture coverage.
- Do not keep raw `updatedAt` as the Dock row/card order key once a
  message-derived activity date is available.
- Do not let fallback title/preview/summary text hide that message data is
  unknown. Unknown/not-loaded message data should remain explicit.

<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving
> the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions
> as the destination map: they preserve final known scope, not a Phase 1
> checklist. Section 7 chooses the first working slice that proves one real path
> through the canonical owner path, highest-risk seam, compatibility or
> migration posture, and verification shape. Phase boundaries are proof gates.
> No fallbacks/runtime shims.

<!-- arch_skill:block:phase_plan:start -->

## Phase 1 - Model, metadata, and projection contract

Status: READY FOR IMPLEMENT-LOOP AFTER 2026-05-30 ORDERING AND TRUE-MESSAGE AMENDMENT

Completed work:

- First pass added local pin metadata, cached pinned display snapshots,
  `DockRowViewModel` pinned fields, cached metadata-only pinned rows, and
  `DockSessionProjection` pinned/body split.
- Added focused projection, cached-row, store persistence, store failure, and
  metadata compatibility tests.
- Reopened because the amendment requires durable `pinnedOrder`, static sort,
  append-on-pin behavior, reorder persistence, and true-message Dock
  preview/order centralization.

Proof:

- `rtk swift test --filter DockStoreTests` passed on 2026-05-30.

Goal: make pinned rows and message-derived row facts first-class model and
projection concepts without changing the UI yet.

Work: extend the existing metadata -> row projection -> Dock projection path so
the rest of the app can consume pinned truth and true-message row facts without
recomputing either in the view.

Checklist (must all be done):

- Add `isPinned`, `pinnedAt`, and `pinnedOrder` to `LocalThreadMetadata` with
  decode-safe defaults.
- Add `lastKnownPinnedDisplay` to `LocalThreadMetadata` and keep `isEmpty`
  semantics precise: empty means no label, no rail, no pin flag, no pinned date,
  no pinned order, and no cached pinned display.
- Add `Codable` conformance to `DockRowStatusKind` because cached pinned display
  snapshots store status.
- Add metadata compatibility coverage proving older label/rail-only JSON
  decodes as unpinned.
- Add cached metadata-only pinned row projection for pinned keys missing from
  the live session summaries, including `Not loaded` fallback behavior when no
  cached display exists.
- Add `isPinned` and `pinnedAt` to `DockRowViewModel` and all test helpers.
- Add `pinnedOrder` to `DockRowViewModel` and all test helpers.
- Keep the shared Swift true-message helper in
  `CodexDock/Models/ThreadEvent.swift`, and keep
  `ThreadDetailMessageFilter.messages.includes(_:)` calling it.
- Keep `SessionSummaryMapper` free of private Dock/list message predicates.
  It must continue to derive message preview/activity through
  `ThreadMessageSemantics`.
- Keep `SessionSummary` and row projection carrying/rendering
  message-derived preview and using message-derived activity for ordering/time.
- Keep `DockStreamSessionDTO` and `DockSessionTable.summary(from:)` carrying
  backward-compatible `messageSummary` and `messageUpdatedAt` fields from the
  relay Dock stream.
- Keep relay-side summary warming returning latest true-message text plus the
  true-message timestamp.
- Add fixture coverage proving Swift and Node classify user/agent messages as
  messages and reasoning/plan/tool/output/request/status/unknown as not
  messages.
- Project local pinned metadata in `SessionRowProjector`.
- Add `pinnedRows`, `allPinnedRows`, and `pinnedSummary` to
  `DockSessionProjection`.
- Split visible rows after search/filter/idle scope into pinned and body rows.
- De-duplicate body rows when those rows are visible in `pinnedRows`.
- Keep `Host` and `Branch` lenses from hiding pinned rows by lens selection.
- Keep explicit search/filter narrowing able to hide pinned rows.
- Count summary results as visible pinned + body rows.
- Add focused projection tests for newest/host/branch pinned behavior,
  de-duplication, search/filter scope, hidden pinned counts, and static
  pinned-order sort.
- Add projection tests for cached pinned rows when a live row is absent and for
  `Not loaded` placeholder rows when no cached display exists.
- Add store/projection tests proving new pins append after existing pins,
  activity changes do not reorder pinned rows, missing legacy `pinnedOrder`
  values migrate deterministically, unpin clears `pinnedOrder`, and drag reorder
  writes persisted order.
- Add mapper/projection tests proving a newer command output, tool call,
  reasoning item, request card, or status event does not replace the Dock
  summary or advance Dock row/group order past the newest true message.
- Add a fixture that exercises the same thread through Thread Detail default
  filtering and Dock projection, proving both surfaces use the same shared
  classifier instead of two predicates that merely look similar.
- Add relay tests proving `thread/turns/list` summary warming and Dock stream
  ordering expose true-message summary/activity, excluding reasoning/tool text.

Verification (required proof):

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadEventNormalizerTests`
- `rtk swift test --filter ThreadListMappingTests`
- `rtk npm run test:relay`

Docs/comments (propagation; only if needed):

- Add a short comment only at the projection split if the pinned/body
  de-duplication logic is not self-explanatory.

Exit criteria (all required):

- Projection tests prove pinned rows remain outside Host/Branch groups while
  visible at top-level.
- Projection tests prove search/filter can hide pinned rows by explicit scope.
- Metadata compatibility tests prove old local metadata files remain readable
  and default to unpinned.
- Metadata compatibility tests prove old pinned metadata without `pinnedOrder`
  remains pinned and sorts deterministically.
- Metadata/store tests prove `LocalThreadMetadata.isEmpty` includes
  `pinnedOrder == nil` and unpin clears stale `pinnedOrder` values.
- Projection tests prove pinned rows can render from cached metadata when live
  data is absent.
- Store tests prove `reorderPinnedRows(...)` persists order and survives reload.
- Thread Detail default filter and Dock mapping use the same Swift helper.
- Dock row projection and ordering use message-derived activity, not raw
  non-message `updatedAt`.
- Relay stream rows expose enough message-derived activity for the app to sort
  without opening every thread detail.
- No UI code computes pinned membership independently.
- No UI code computes true-message membership independently.
- Existing label/rail projection tests still pass.

Rollback:

- Revert metadata fields and projection additions together. Do not leave partial
  pinned fields unused in `DockRowViewModel`.

## Phase 2 - Dock UI actions, pinned section, and automation hooks

Status: READY FOR IMPLEMENT-LOOP AFTER 2026-05-30 UI AND TRUE-MESSAGE AMENDMENT

Completed work:

- First pass added Dock pin/unpin automation IDs, `DockStore.setPinned(_:for:)`,
  recoverable metadata action errors, pinned section rendering,
  overflow/Manage controls, context-menu and accessibility actions, and a
  dedicated `DockPinnedViews.swift` home for swipe and pinned-management UI
  helpers.
- Replaced native row swipe actions with an in-Dock swipe row because the iPhone
  17 simulator proved native `swipeActions` did not expose `Pin` from the
  current `ScrollView`/`LazyVStack` row structure.
- Kept Archive out of the pin surface by making shared pin visuals opt-in from
  Dock.
- Reopened because overflow/Manage, activity sorting, custom gesture-heavy
  structure, and non-message Dock row ripping are no longer the target
  experience.

Proof:

- `rtk swift test --filter DockStoreTests` passed on 2026-05-30.
- `rtk swift test --filter AutomationIDTests` passed on 2026-05-30.

Goal: make the pinned projection and true-message row/card projection real in
the Dock UI with swipe pin/unpin, native iOS reorder, collapsible pinned
header, all-visible inline rows, and accessible fallbacks.

Work: render `Pinned N` above the selected lens body, add swipe/context actions,
and expose stable UI-test hooks.

Checklist (must all be done):

- Add `pin` and `unpin` row action IDs plus pinned section IDs to
  `AutomationID`.
- Add stable automation IDs for collapse state, pinned reorder proof, and the
  pinned/body separator if simulator proof needs direct hooks.
- Add `DockStore.setPinned(_:for:)` using the existing local metadata save path.
- Add `DockStore.reorderPinnedRows(...)` using the existing local metadata save
  path.
- Make local metadata action failure use a recoverable action error instead of
  replacing the whole Dock with an error state.
- Render a `Pinned N` section before the selected lens body when pinned rows are
  visible.
- Render pinned rows with clear pin affordance and enough host/repo/branch
  context.
- Render Dock row/card summary text from the message-derived preview field only.
  Do not display tool calls, command output, reasoning/thinking, request-card
  text, status events, or unknown event text in the Dock card preview.
- Render the row/card time label from message-derived activity when known.
- Render all visible pinned rows inline when the section is expanded.
- Do not render `Show all N pinned`, `Manage`, or any pinned management sheet.
- Make the visible `Pinned` label/header tappable and use it to collapse/expand
  the pinned section.
- Add a native divider or section boundary between pinned rows and body
  rows/groups when both exist.
- Use native iOS movement for reorder. Preferred implementation is UIKit
  collection/list interactive movement because Apple's UIKit collection APIs
  have a standard long-press movement pattern. A SwiftUI wrapper is fine if the
  row movement itself is still UIKit-owned. SwiftUI `List`/`onMove` is allowed
  only if it proves the same no-handle, no-edit-mode long-press behavior in the
  simulator. Do not build custom drag/drop sorting.
- Do not show a reorder handle, grip, Edit button, edit mode, or instructional
  text for reorder.
- Do not gate reorder behind a minimum pinned count. One visible pin has no
  alternate destination, but it should use the same list surface and state model
  as larger pinned sets.
- Define and test scoped reorder when search/filter hides pinned rows: hidden
  pinned rows retain relative order, and moving a visible pinned row updates its
  position relative to the visible neighbors without exposing a separate mode.
- Add trailing `Pin` swipe action for unpinned Dock rows.
- Add trailing `Unpin` swipe action for pinned rows.
- Add body-row context-menu `Pin` without removing existing `Mark Watch`,
  `Clear Label`, `Color`, or `Archive` actions. Do not attach the normal row
  context menu to pinned rows because pinned-row long press owns reorder.
- Add accessibility custom actions for `Pin thread` and `Unpin thread`.
- Add accessible pinned semantics: pinned rows include `Pinned` in their
  accessibility value, the pinned section has a stable header/section ID, and
  the collapsed/expanded state is exposed.
- Add accessible reorder semantics if the native move path exposes them; do not
  fake accessibility-only reorder controls unless native proof fails and the
  plan is reopened.
- Add focused store tests for `setPinned` persistence, unpin clearing behavior,
  refresh/reprojection, reorder persistence, and metadata save failure
  preserving the previous state with an action error.
- Add focused UI/projection tests proving a row with newer tool/thinking noise
  still displays the newest true-message preview and stays ordered by the
  true-message timestamp.
- Keep no-pins UI identical to current Dock body layout.
- Keep no visible `Limited`, `Needs me`, or universal `History` badge.

Verification (required proof):

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AutomationIDTests`

Docs/comments (propagation; only if needed):

- Update the UX package README only if implementation changes lens/wording.

Exit criteria (all required):

- Dock UI can render a pinned section above `Newest`, `Host`, and `Branch`.
- Pinned rows do not duplicate in the body.
- All visible pins render inline when expanded, with no cap and no overflow
  button.
- No `Manage` button/dialog/sheet remains visible or reachable.
- Tapping `Pinned` collapses and expands the section.
- Native long-press drag reorder works in the expanded pinned section and
  persists.
- Scoped reorder works when search/filter hides some pinned rows; hidden pinned
  rows keep their relative order after the scope is cleared.
- Dock row/card preview and visible ordering match true-message data and do not
  rip to tools/reasoning/status events.
- There is no visible reorder indicator or edit-mode requirement.
- A visual divider/section boundary separates pinned rows from the rest of Dock.
- Swipe/context/accessibility `Pin` actions and swipe/accessibility `Unpin`
  actions call the same store mutation path.
- Store tests prove persistence and failure behavior.
- Existing row actions still exist.
- File growth does not push `DockView.swift` over a maintainability cliff; split
  helpers if needed.

Rollback:

- Remove the UI actions and pinned section render path while preserving Phase 1
  projection work only if the UI path is the sole blocker. Otherwise roll back
  both phases together.

## Phase 3 - iPhone 17 simulator proof, review closure, and hardening

Status: READY FOR IMPLEMENT-LOOP AFTER 2026-05-30 AMENDMENT

Completed work:

- Added `testScriptedDockSwipePinPersistsAcrossLensesRefreshRelaunchAndUnpin`
  to prove the north-star flow in the iPhone 17 simulator, including search
  narrowing hiding a pinned row and clearing search restoring the pinned
  section.
- Proved `rtk make app-test SIM='iPhone 17'` passes with the swipe pin/unpin,
  pinned section, Host and Branch lenses, Manage sheet, refresh, relaunch, and
  unpin path.
- Ran the first Composer 2.5 Fast fresh code review. It returned
  `VERDICT: pass-with-notes`, `BLOCKING: none`, and identified only
  non-blocking polish/coverage notes. Parent spot-check found the mockup PNG
  note stale because `docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/outputs/`
  does contain generated PNG files.

Proof so far:

- `rtk make app-test SIM='iPhone 17'` passed on 2026-05-30.
- Passing simulator log:
  `.codex-dock/logs/app-test-20260530022222.log`
- Passing simulator result bundle:
  `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_21-22-23--0500.xcresult`
- Composer 2.5 Fast review run directory:
  `/tmp/fresh-consult/codex-dock-swipe-pinned-review-20260530-kCPuWi`

Amendment impact:

- Prior simulator proof remains useful for swipe pin/unpin and cross-lens
  pinned visibility.
- Prior simulator proof is no longer completion evidence for the final pinned
  section because it exercised now-rejected Manage/overflow behavior and did
  not prove static order, drag reorder, collapse, divider separation, or
  true-message-only Dock cards/order.

Goal: prove the actual user flow in the simulator and pass external review
gates.

Work: add or update deterministic simulator UI coverage, run required checks,
and repair review findings.

Checklist (must all be done):

- Add iPhone 17 simulator UI coverage for pin on `Newest`, pinned persists at
  top on `Host`, pinned persists at top on `Branch`, and unpin removes the row
  from `Pinned`.
- Add iPhone 17 simulator UI coverage that pins at least three rows and proves
  their order stays by pin sequence, not newest activity.
- Add iPhone 17 simulator UI coverage that uses native iOS reorder to move a
  pinned row, refreshes, relaunches, and verifies the new order persists.
- Add iPhone 17 simulator UI coverage that applies search/filter scope to hide
  at least one pinned row, reorders the visible pinned subset, clears scope, and
  verifies the hidden pinned rows kept their relative order.
- Add iPhone 17 simulator UI coverage that taps the `Pinned` label to collapse
  the section and taps it again to expand.
- Add iPhone 17 simulator UI coverage or visual/accessibility proof that
  `Manage`, the pinned management sheet, and `Show all N pinned` are absent.
- Add iPhone 17 simulator UI coverage or screenshot/accessibility proof that a
  divider/section boundary separates pinned rows from body rows/groups.
- Add iPhone 17 simulator UI coverage where a row receives newer
  tool/reasoning/status noise after its newest true message, and verify the Dock
  card preview and row order still use the true message.
- Add iPhone 17 simulator UI coverage that opens that same thread detail and
  verifies the default `Messages` filter exposes the same class of message
  content used by the Dock card.
- The simulator proof must verify the full user-visible failure mode: the Dock
  card text does not rip to tool/thinking/status/request content, and the row
  does not jump above a row with a newer true message.
- Use the repo-owned app-test path; do not use raw simulator install commands
  except for diagnostics.
- Run `rtk make app-test SIM='iPhone 17'` or record the exact blocker.
- Run a full Composer 2.5 Fast code review and address blocking findings.
- Run thermo-nuclear code quality review and address structural blockers.
- Update this plan/worklog with actual proof commands and outcomes.

Verification (required proof):

- `rtk make app-test SIM='iPhone 17'`
- Composer 2.5 Fast code review final verdict with no blocking findings.
- Thermo-nuclear code quality review with no unresolved structural blockers.

Docs/comments (propagation; only if needed):

- If implementation diverges from the UX spec, update the spec or stop for user
  approval before shipping the divergence.

Exit criteria (all required):

- Simulator shows the real swipe pin/unpin behavior on `iPhone 17`.
- Simulator shows native drag reorder on `iPhone 17`.
- Simulator shows scoped reorder preserves hidden pinned relative order after
  search/filter scope is cleared.
- Simulator shows collapse/expand by tapping `Pinned`.
- Simulator shows no Manage/Show-all pinned surface.
- Simulator shows Dock cards/order stay on true messages when tools/reasoning
  are newer.
- Simulator proves order survives refresh and relaunch.
- External review agrees implementation is complete and elegant.
- Thermo review does not identify unresolved maintainability blockers.
- No required plan checklist item remains incomplete.

Rollback:

- If simulator proof fails because the UI behavior is wrong, reopen Phase 2.
- If review finds structural issues, reopen the owning phase and repair before
  claiming completion.

<!-- arch_skill:block:phase_plan:end -->

## Implementation Evidence - 2026-05-30

Status: complete for the app/runtime paths, iPhone 17 simulator proof, and
thermo-nuclear maintainability review.

Implemented:

- `LocalThreadMetadata.pinnedOrder` and `DockRowViewModel.pinnedOrder` now carry
  durable user-owned pin order.
- `DockStore.setPinned` appends new pins after existing pins and normalizes pin
  order.
- `DockStore.reorderPinnedRows` writes reordered visible pinned rows while
  preserving hidden search/filter scoped pinned slots.
- `PinnedMetadataOrdering` owns pin-order normalization, stable ordering,
  uniqueness, and append-order helpers so `DockStore` stays below the
  1,000-line review threshold.
- Pinned metadata writes use one batch save through `LocalThreadMetadataStoring`
  instead of a sequence of partial per-row saves.
- `DockPinnedSectionView` renders all visible pinned rows inline above every
  Dock lens, with collapse/expand on the `Pinned` header.
- The old three-row cap, `Show all`, `Manage`, and pinned management sheet
  paths were removed.
- Pinned reorder uses native UIKit collection interactive movement from a
  long press on the row. No visible reorder handle or edit-mode affordance is
  rendered.
- Pinned rows intentionally do not attach the normal row context menu because
  that menu uses the same long-press gesture as reorder. Pinned-row `Unpin`
  remains available through native trailing swipe and accessibility action.
- A Dock-local left swipe still owns row `Pin` / `Unpin` because the current
  Dock body is a `ScrollView`, not a native `List`.
- `ThreadMessageSemantics` centralizes the true-message predicate used by
  Thread Detail's default `Messages` filter and Dock row/card mapping.
- Relay stream DTOs now carry optional `messageSummary` and `messageUpdatedAt`
  so Dock preview/order can use newest true-message activity instead of raw
  tool/status freshness.
- Archive keeps raw activity semantics through `ArchiveSessionProjector`; Dock
  alone uses message activity for row order/preview.

Verification run after cleanup:

```bash
rtk git diff --check
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter 'ThreadListMappingTests|ThreadEventNormalizerTests|AutomationIDTests'
rtk swift test --filter AutomationIDTests
rtk npm run test:relay
rtk make app-test SIM='iPhone 17'
```

Results:

- `rtk git diff --check`: passed.
- `rtk swift test --filter DockStoreTests`: 48 tests passed.
- `rtk swift test --filter ThreadDetailStoreTests`: 52 tests passed.
- `rtk swift test --filter 'ThreadListMappingTests|ThreadEventNormalizerTests|AutomationIDTests'`: 27 tests passed.
- `rtk swift test --filter AutomationIDTests`: 3 tests passed after the
  preview cleanup compile pass.
- `rtk npm run test:relay`: 105 tests passed.
- `rtk make app-test SIM='iPhone 17'`: passed on iPhone 17 simulator
  `DEF1631B-7125-43C6-BFA3-4423BF103C91` through Makefile-owned app-test
  target with result bundle
  `/tmp/codex-client/app-test-detached-20260530T132652Z/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.30_08-26-54--0500.xcresult`;
  result `Passed`, 260 passed, 0 failed, 5 skipped, 265 total.

Physical install:

```bash
rtk make iphone-17-pro
rtk make device-config-verify DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E
```

Result:

- Installed `com.aelaguiz.CodexDockApp` build `20260530133223` on iPhone 17 Pro
  `CB9FFF0E-89AD-57B5-9C00-6552D814875E`.
- Verified saved relay hosts:
  `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
- Device launch log reported:
  `Launched application with com.aelaguiz.CodexDockApp bundle identifier.`
- `rtk make dock-relay-status` reported the raw app-server and Dock relay ready.

Resolved proof/review notes:

- Earlier simulator failures were harness or gesture-conflict failures, not
  accepted proof: scripted launches reused an existing app process, body-row
  pinning happened too close to the tab bar, and pinned-row long press opened
  the row context menu instead of native movement.
- `CodexDockUITests/CodexDockAutomationSmokeTests.swift` now terminates the app
  before scripted launches, scrolls body rows into a safer swipe area, and
  proves native pinned reorder plus scoped reorder.
- `dockPinnedRow` disables the normal row context menu so long-press starts
  native pinned movement. This preserves the user's no-handle reorder
  requirement.
- Parent thermo-nuclear review found no remaining blocking structural issue:
  `DockStore.swift` is 919 lines, `DockView.swift` is 928 lines,
  `DockPinnedViews.swift` is 412 lines, and pinned ordering lives in the focused
  `PinnedMetadataOrdering` helper.
- Composer 2.5 Fast fresh consult completed at
  `/tmp/fresh-consult/codex-dock-pinned-final-composer-20260530T133301Z-2lk1727q/final.txt`
  with `VERDICT: pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - TL;DR, Sections 0-10, helper blocks, UX spec package, approved mockups,
    Composer 2.5 Fast signoff, and 2026-05-30 amended pin-order/user-order
    requirements.
- Findings summary:
  - Earlier explorer review found optional-looking simulator proof wording,
    orphan persistence/failure obligations, deferred overflow/Manage risk,
    missing cached `Not loaded` pinned row behavior, missing accessibility
    semantics, and vague constructor fallout.
  - Fresh auto-plan repair found four remaining plan-state gaps: the helper
    block still paused for user review, frontmatter used non-canonical
    `reopened-planning`, `pinnedOrder` was missing from the metadata emptiness
    and unpin proof language, and relay proof wording stayed conditional even
    though relay message-derived fields are now part of the plan.
  - Fresh architecture cold-read found three remaining specificity gaps: the
    read-only relay DTO shape was branchy, Archive/detail adjacent activity
    semantics were not dispositioned, and scoped reorder under search/filter
    was missing from phase exit criteria and simulator proof.
- Integrated repairs:
  - Section 7 now includes persistence, metadata compatibility, failure
    behavior, cached pinned display, `Not loaded` fallback rows, accessibility,
    refresh, relaunch, static order, native reorder, collapse, divider, and
    true-message card/order proof.
  - Section 5 now makes cached display snapshots, `allPinnedRows`, explicit
    `isEmpty` semantics, `pinnedOrder`, collapse, divider, native reorder, and
    true-message summary/activity part of the target architecture.
  - Section 6 now names the exact constructor/test helper fallout and requires
    an `rg "DockRowViewModel\\("` implementation sweep.
  - Section 8 now treats simulator and review gates as required completion
    evidence.
  - 2026-05-30 follow-up: the plan now explicitly distinguishes Thread
    Detail's default `Messages` filter from the broader `agentMessage` kind
    filter, because reasoning/plan events can be agent-kind but
    thinking-visible. Dock cards/order must follow the default `Messages`
    filter.
  - 2026-05-30 follow-up: the native reorder research now starts from UIKit
    collection/list standard interactive movement because it directly owns the
    long-press row-move pattern with no visible handle. SwiftUI
    `List`/`ForEach.onMove(perform:)` remains secondary unless simulator proof
    shows it can satisfy the same no-handle/no-edit-mode behavior.
  - 2026-05-30 auto-plan repair: frontmatter is `status: active`; Section 5,
    Section 6, and Phase 1 explicitly include `pinnedOrder` in metadata
    emptiness, unpin cleanup, and store/projection proof.
  - 2026-05-30 auto-plan repair: the relay Dock stream contract now chooses
    optional `messageSummary` and `messageUpdatedAt`, keeps `summary` as a
    legacy/raw field, and requires `rtk npm run test:relay`.
  - 2026-05-30 auto-plan repair: Archive keeps raw archive activity semantics,
    Thread Detail keeps detail freshness on the rehydrate path, and neither
    adjacent surface gains Dock pin UI.
  - 2026-05-30 auto-plan repair: scoped reorder under search/filter now has
    Phase 2 exit criteria and Phase 3 iPhone 17 simulator proof.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes

<!-- arch_skill:block:consistency_pass:end -->

# 8) Verification Strategy (common-sense; required proof gates)

Avoid verification bureaucracy. Prefer existing credible signals that prove the
claim. Unit tests prove projection/store contracts; simulator tests prove the
real gesture and UI behavior. "Common-sense" means no extra ceremony beyond the
named gates; it does not make the proof optional. The Section 7 and Section 8
proof commands are required completion evidence. Do not add bespoke doc-audit
scripts or repo-policing gates for this feature.

## 8.1 Unit tests (contracts)

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadEventNormalizerTests`
- `rtk swift test --filter ThreadListMappingTests`
- `rtk npm run test:relay` when relay summary/stream code changes
- Focused projection tests for pinned split, body de-duplication, lens behavior,
  search/filter scope, and hidden pinned counts.
- Focused store tests for `setPinned` persistence and failure behavior.
- Metadata store compatibility tests for decoding older metadata without pin
  fields.
- Focused mapper/classifier tests proving true-message classification is shared
  by Thread Detail and Dock mapping.
- Focused Dock projection tests proving newer tool/reasoning/request/status
  activity does not change row/card preview or ordering.

## 8.2 Integration tests (flows)

- `rtk make app-test SIM='iPhone 17'`
- Scripted stream UI test drives pin, lens switches, native reorder,
  collapse/expand, refresh, relaunch, unpin, true-message card/order behavior,
  absence of Manage/Show-all, and `Pinned` row accessibility semantics.

## 8.3 E2E / device tests (realistic)

- Primary required proof is the iPhone 17 simulator.
- Physical device install is not required for this feature unless simulator
  proof is blocked by a platform-only behavior difference.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Local app change plus possible relay read/projection change. No app-server
mutation or pin-sync deployment is required. If relay DTO/summary code changes,
`rtk make services` must run the updated relay before simulator proof.

## 9.2 Telemetry changes

No new telemetry is required. Existing `DockLog.persistence` can log metadata
save success/failure without prompts or sensitive payloads.

## 9.3 Operational runbook

If pin state appears stale, refresh Dock or relaunch the app. Since pins are
device-local, deleting the app or app support data removes local pin state.

# 10) Decision Log (append-only)

## 2026-05-30 - Intent-derived: UX spec is the product contract

Blocker: The arch workflow normally stops after bootstrapping for North Star
confirmation.

Consulted: User objective, `UX_SPEC.md`, Composer 2.5 Fast signoff in
`/tmp/fresh-consult/codex-dock-pinned-ux-signoff-20260530T005359Z-ZQYMKQ/final.txt`.

Intent says: The user explicitly asked to auto-plan the UX spec, pass plan
audit, auto-implement, prove in the iPhone 17 simulator, and run external code
reviews.

Decision: Treat `UX_SPEC.md` as approved product intent and this architecture
plan as `status: active`.

Consequences: Planning can proceed without asking for a separate North Star
confirmation, but any attempted scope cut still requires explicit user approval.

## 2026-05-30 - Consistency-derived: no deferred management or cached-row cut

Blocker: Consistency review found the earlier plan could have implemented only
live pinned rows and deferred overflow/management, which would not match the UX
spec or user intent.

Consulted: `UX_SPEC.md`, consistency review findings from the two explorer
agents, and Sections 5-7 of this plan.

Intent says: Pinned rows must be useful across tabs/lenses, refresh/relaunch
must be real, and the user must be able to control the pinned set without a new
root tab.

Decision at that time: Include cached pinned display snapshots, `Not loaded`
placeholders, management/overflow handling, accessibility semantics, and
refresh/relaunch simulator proof in the implementation scope.

Consequences: The feature is slightly larger, but it avoids a misleading
partial implementation that only works while the live row happens to be loaded.

Superseded on 2026-05-30 by the later user amendment: keep cached pinned
display snapshots, `Not loaded` placeholders, accessibility semantics, and
refresh/relaunch proof, but remove the pinned management sheet/button and
overflow cap entirely.

## 2026-05-30 - Intent-derived: ScrollView rows need an in-Dock swipe container

Blocker: The first simulator run showed no `Pin` button after swiping a Dock
row. The Dock body is a `ScrollView`/`LazyVStack`, while SwiftUI
`swipeActions` did not expose the action in that row structure.

Consulted: Section 0 North Star, Section 1.2 constraints, Section 5 target UI,
`CodexDock/Features/Dock/DockView.swift`, and the failing iPhone 17 simulator
run from `rtk make app-test SIM='iPhone 17'`.

Intent says: The actual user action is swipe to pin/unpin in the current Dock
UI. Keeping the existing Dock layout is less disruptive than converting the
whole Dock surface to `List` just to inherit platform swipe behavior.

Decision: Implement a small Dock-local swipe container around rows. It reveals
the same `Pin`/`Unpin` store action and automation ID that context/accessibility
use.

Consequences: The plan still owns one pin mutation path in `DockStore`, but the
gesture implementation is custom because the existing Dock row container is not
a native `List` row.

Superseded on 2026-05-30 for reorder: swipe may remain a Dock-local pin/unpin
action if native swipe still cannot coexist with the current layout, but pinned
row reorder must use native UIKit collection/list interactive movement. If
native reorder requires a native UIKit collection wrapper, prefer that over
adding custom reorder gestures.

## 2026-05-30 - Intent-derived: Dock cards and ordering mean true messages

Blocker: The Dock card can rip between tool calls, thinking tokens, request
cards, status updates, and actual conversation messages if it treats raw
`updatedAt` or generic summaries as the row preview/order source.

Consulted: User amendment, `CodexDock/Models/ThreadEvent.swift`,
`CodexDock/Models/SessionSummaryMapper.swift`,
`CodexDock/State/DockSessionTable.swift`,
`scripts/dock-relay-thread-summary-cache.mjs`, and
`scripts/dock-relay-session-table.mjs`.

Intent says: Dock row/card preview and Dock ordering should mean the same
thing as Thread Detail's default `Messages` filter.

Decision: Centralize true-message classification in Swift, make Thread Detail
and Dock mapping call that same helper, and add relay-side message-summary
fixture coverage where the Node relay must mirror the rule. Dock preview and
order use newest true-message text/activity, not raw tool/thinking/status
freshness.

Consequences: The relay/client DTO path may need optional message-derived
summary/activity fields. Raw `updatedAt` remains useful for freshness and
diagnostics, but it is not the user-facing Dock row/card ordering source once
message-derived activity exists.

## 2026-05-30 - User-directed: amended pin-order plan is accepted for implement-loop

Blocker: The auto-plan gate was blocked because the consistency pass still said
the amended plan was waiting for user review.

Consulted: Current user objective,
`docs/CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30.md`,
the consistency-pass helper block, and two fresh cold-read reviews over the
amended plan.

Intent says: Run `$arch-step auto-plan` on this document and fully plan the
requested improvements, including stable pin order and the related follow-on
items.

Decision: Treat the 2026-05-30 amendments as accepted planning scope. The plan
is active and ready for `implement-loop` once the stage gate confirms readiness.

Consequences: Implementation must remove the stale first-pass capped/Manage
surface, add durable `pinnedOrder`, native reorder, collapse, scoped reorder,
and message-derived Dock preview/order. No scope cut is approved.

## 2026-05-30 - User-directed: long-press reorder means native collection movement

Blocker: Treating SwiftUI `List.onMove` as the default reorder path is too
ambiguous for the requested interaction. The user asked for the well-known iOS
pattern: long-press a row, drag it, drop it, with no visible reorder handle and
no edit mode.

Consulted: Apple's UIKit collection interactive movement docs,
`UICollectionViewController.installsStandardGestureForInteractiveMovement`,
`UICollectionView.beginInteractiveMovementForItem(at:)`,
`CodexDock/Features/Dock/DockPinnedViews.swift`, and the current pinned plan.

Intent says: Reordering should feel like native iOS direct manipulation, not a
homegrown drag/drop list.

Decision: Use native UIKit collection/list interactive movement as the primary
implementation path for pinned reorder. SwiftUI may wrap the native control,
but SwiftUI edit-mode movement is only acceptable if simulator proof shows the
same no-handle long-press behavior.

Consequences: Simulator testing must prove the long-press reorder on
`iPhone 17`. Unit tests can prove store order persistence, but they do not
replace simulator proof for the gesture.

## 2026-05-30 - User-directed: Dock cards must match Thread Detail Messages

Blocker: The phrase "message" is easy to implement incorrectly if Dock treats
generic summaries, raw `updatedAt`, `kind == .agentMessage`, or relay preview
text as equivalent to a visible conversation message.

Consulted: User amendment, `CodexDock/Models/ThreadEvent.swift`,
`ThreadDetailMessageFilter.default`, `ThreadMessageSemantics`,
`CodexDock/Models/SessionSummaryMapper.swift`,
`CodexDock/State/DockSessionTable.swift`,
`CodexDock/State/DockSessionProjection.swift`,
`scripts/dock-relay-thread-summary-cache.mjs`, and Apple UIKit reorder
documentation for the adjacent long-press pin-order requirement.

Intent says: The card at the top-level Dock list should show only true
conversation messages, exactly like the default Thread Detail `Messages`
filter. Dock ordering should use that same true-message freshness so a newer
tool call, thinking token, request card, command output, status update, or
unknown event cannot make the card text rip or move the row.

Decision: Treat `ThreadMessageSemantics.isDefaultVisibleMessage(_:)` as the
Swift source of truth and make every Dock preview/order path consume
message-derived summary/activity produced by that rule. Relay-side Node code may
mirror the rule only to emit explicit `messageSummary` / `messageUpdatedAt`
fields; it may not relabel arbitrary summaries as messages.

Consequences: Tests and simulator proof must compare Dock behavior against
Thread Detail's default filter, not against an invented Dock-only definition.
Any future filter work that changes `ThreadDetailMessageFilter.default` must
update the Dock classifier contract and tests in the same change.

## 2026-05-30 - Intent-derived: pinned-row context menu cannot own long press

Blocker: The iPhone 17 simulator proved that attaching the normal row context
menu to pinned rows steals the same long-press gesture that must start native
reorder.

Consulted: User correction that reorder should start by click-and-hold with no
visible handle, Section 0 North Star, `DockPinnedReorderCollectionView`, and
the failing simulator result from
`Test-CodexDockApp-2026.05.30_08-16-03--0500.xcresult`.

Intent says: The primary pinned-row long press must rearrange the pinned list.
There must be no visible reorder handle, edit mode, Manage sheet, or alternate
management surface.

Decision: Keep context-menu actions on normal Dock rows for `Pin` and the
existing row actions, but do not attach the normal row context menu to pinned
rows. Pinned-row `Unpin` is available through native trailing swipe and the
accessibility custom action.

Consequences: Long-press reorder and pinned-row unpin no longer compete for the
same gesture. The final simulator pass proves native reorder, scoped reorder,
swipe unpin, accessibility IDs, and absence of Manage/Show-all.
