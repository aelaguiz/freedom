---
title: "Codex Dock - Pinned Threads UX Options"
date: 2026-05-29
status: draft_for_review
owners: [aelaguiz]
reviewers: [Codex]
doc_type: ux_strategy
related:
  - docs/CODEX_DOCK_PINNED_THREADS_UX_WORKLOG_2026-05-29.md
  - docs/mockups/codex-dock-pinned-threads-2026-05-29/README.md
  - docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md
  - docs/mockups/codex-dock-activity-first-2026-05-29/README.md
---

# Codex Dock - Pinned Threads UX Options

## 0. Bottom Line

Pinned threads should be a tiny user-owned watchlist for the 2-3 sessions that
matter right now.

That means:

- The user chooses the threads.
- The UI keeps those threads easy to monitor while the newest feed still works.
- The user can unpin when the work is done.
- Pins are not an inferred status, not `Needs me`, not `Running`, and not a
  prediction engine.

Recommended direction:

> Add a compact `Pinned` watch strip above the newest feed, backed by explicit
> pin/unpin actions on rows and detail screens. Keep `Newest` as the default
> Dock lens. Hide the strip entirely when there are no pins.

This gives the user a stable place to watch the few threads they care about
without turning the whole Dock into a favorites app and without hiding the
newest activity feed.

## 1. Product Definition

### What `Pinned` Means

`Pinned` means:

> "Keep this thread visible until I remove it."

It does not mean:

- Codex thinks the thread is important.
- The thread needs user input.
- The thread is active or running.
- The thread is rate-limited.
- The thread is loaded or not loaded.
- The thread belongs to a special workflow.
- The thread should be permanently favorited forever.

The feature is closer to a temporary watchlist than a social-media favorite.
The word shown in the UI can be `Pinned`, because that is familiar. The mental
model should be `watch this while I work`.

### Primary User Story

The user is moving across multiple machines and many Codex sessions. Most of
the list is noise most of the time. The user cares about 2-3 threads and wants
to keep them in sight while new sessions continue to appear.

Concrete flow:

1. User sees or opens a thread that matters.
2. User pins it.
3. Dock shows that thread in a compact pinned area.
4. The pinned row keeps updating its status, host, branch, summary, and last
   activity.
5. User opens it repeatedly while working.
6. User unpins when done.

### Product Invariants

- Pinning is explicit user state.
- Pinned state must be visible wherever the thread appears.
- Unpinning must be just as easy as pinning.
- Pins must not reorder the entire main feed in a surprising way.
- Pinned threads must still appear in `Newest` according to real activity, with
  a pin marker. The watch strip is an extra shortcut, not a replacement feed.
- If a host is offline, the pinned thread should remain visible with the host
  state attached. Do not silently remove it.
- If a pinned thread is archived or unavailable, show that honestly and keep a
  direct unpin action.
- If there are zero pinned threads, do not show a dead `Pinned 0` module on the
  default Dock screen.

## 2. Research Summary

### Apple HIG: Lists Need Scannable Rows

Source:
<https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>

Apple's list guidance matters here because Dock is a text-heavy list. A row
should keep text succinct, preserve readability, provide clear selection
feedback, and use list/table structures when rows need to be scanned quickly.

Dock implication:

- Pinned rows should not become giant cards.
- Title, host, repo, branch, status, and time need to remain recognizable at a
  glance.
- A pinned mark should be an icon-level cue, not a noisy text badge on every
  row.

### Apple HIG: Search And Scope Should Be Clear

Sources:

- <https://developer.apple.com/design/human-interface-guidelines/searching>
- <https://developer.apple.com/design/human-interface-guidelines/search-fields>

Apple describes search as a visible way to find content within a collection and
supports scoping/filtering when the collection has attributes. It also
recommends clear placeholder text and visible scope.

Dock implication:

- Pinning should not steal the job of search.
- Search should still search all sessions by default.
- `Pinned` can be a scope/filter, but the default Dock should still show newest
  work across all sessions.

### Apple HIG: Context Menus Are Helpful But Hidden

Source:
<https://developer.apple.com/design/human-interface-guidelines/context-menus>

Apple's context-menu guidance is directly relevant: context menus are good for
commands related to an item, but they are hidden by default and should not be
the only way to access important actions.

Dock implication:

- Long-press `Pin thread` / `Unpin thread` is useful.
- It cannot be the only pinning path.
- Detail view needs a visible toolbar action.
- Row swipe/action affordances should also expose pin/unpin.

### Apple HIG: App-Level Tabs Should Stay Top-Level

Source:
<https://developer.apple.com/design/human-interface-guidelines/tab-bars>

Apple frames tab bars as top-level app navigation. Dock already has the app tabs
`Dock`, `Archive`, and `Relay`.

Dock implication:

- `Pinned` should not become a fourth app-level tab.
- If `Pinned` is a lens, it should be inside Dock.
- Better yet, use a compact watch strip so `Newest` remains the default.

### NN/g: Keep State Visible, Minimize Recall

Source:
<https://www.nngroup.com/articles/ten-usability-heuristics/>

The relevant heuristics are visibility of system status, recognition rather
than recall, user control and freedom, flexibility/efficiency, and aesthetic
minimalism.

Dock implication:

- Pinned state should be visible without remembering which threads were pinned.
- The user should not need to reopen Filters to understand the current scope.
- Unpin should be easy and obvious.
- Hidden shortcuts are useful for speed but cannot carry the whole feature.
- The UI should cap pinned chrome because extra UI competes with the newest
  work list.

### Baymard: Applied Scope Needs An Overview

Sources:

- <https://baymard.com/blog/how-to-design-applied-filters>
- <https://baymard.com/learn/ecommerce-filter-ui>

Baymard's filter research is useful even though Dock is not ecommerce. The
shared problem is a large result list. Their mobile finding is that users need
visible applied-filter context, quick removal, and care that controls do not
push the actual list off-screen.

Dock implication:

- A `Pinned only` filter is useful only if it appears as a removable active
  scope chip.
- A visible pinned strip should be capped at 2-3 items.
- Showing only `Pinned 3` without the actual pinned thread names is not enough
  for monitoring.
- Stacked pinned rows can become too tall. Prefer a compact strip or one dense
  section with a hard cap.

## 3. Current App State, 2026-05-29

Source screenshots:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-dock-live.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-filters-live.png`

Observed current Dock:

- `Newest` is the default lens.
- The app shows `Online 2/2`.
- Search is full-width and useful.
- Filters are visible as an icon button.
- The summary row shows current scope:
  `400 shown · Hosts: Any · Branches: Any · Status: Any · Repo: Any · Source: Any · Idle hidden`
- Rows show short host names such as `Amir-M5`, repo, branch, summary, and last
  activity.
- The bottom tab bar has `Dock`, `Archive`, and `Relay`.

Observed filter sheet:

- Host filters are clear: `Any`, `Amir-M5`, `Home`.
- Branch has search plus many chips.
- Status includes `Running`, `Needs input`, `Needs approval`, `Idle`, and
  `Not loaded`.
- The branch chip grid is large and quickly dominates the first viewport.

UX implication:

- The current default list is a good base for pinning.
- Do not redesign the whole Dock just to add pins.
- Pinning should add a small user-controlled watch surface on top of this
  newest-first structure.

## 4. Option A - Compact Pinned Watch Strip

This is the recommended direction.

### Concept

Show a small `Pinned` section only when the user has pinned threads. Put it
under the search/lens controls and above the main feed. Cap visible items at
2-3 and keep each item dense.

The main feed stays `Newest`. Pinned rows also remain in the feed in their
normal position with a small pin icon.

### Wireframe

```text
+------------------------------------------+
| Dock                         Online 2/2  |
| [ Search sessions, repo, branch, host  ] |
| [Newest] [Host] [Branch]          (filt) |
| 400 shown · Hosts: Any · Idle hidden     |
|                                          |
| Pinned 3                         Manage |
| +--------------------------------------+ |
| | pin  ramp up on code base...    now >| |
| |      Amir-M5 · freedom · dock-counts | |
| +--------------------------------------+ |
| +--------------------------------------+ |
| | pin  psmobile animation engine  2m > | |
| |      Amir-M5 · psmobile · feat/anim  | |
| +--------------------------------------+ |
|                                          |
| Newest                                  |
| +--------------------------------------+ |
| | pin  ramp up on code base...    now >| |
| +--------------------------------------+ |
| |      other newest thread        now >| |
| +--------------------------------------+ |
+------------------------------------------+
```

### Why This Works

- Matches the real user story: watch 2-3 chosen threads while still seeing new
  work.
- Avoids a dead `Pinned 0` tab.
- Does not ask the product to infer importance.
- Does not hide newest activity behind a separate lens.
- Keeps the pinned surface small enough for mobile.

### Details

- Hide the whole pinned strip when count is `0`.
- Show at most 3 pinned rows in the strip.
- If more than 3 are pinned, show `Pinned 7` with the 3 most recently active
  pinned threads and a `Manage` affordance.
- Sort pinned rows by newest activity within the pinned set.
- Include host, repo, branch, status, and time.
- Add a small pin icon to pinned rows in the main feed.
- Do not show a large text badge that says `Pinned` on every pinned row.

### Risks

- Duplicates a pinned thread when it also appears in `Newest`.
- Adds vertical height above the main feed.
- Needs a management surface if the user pins more than the intended 2-3.

Mitigation:

- Keep the strip compact.
- Treat duplication as acceptable because the strip is a shortcut/watch surface
  and the feed remains the truth.
- Make `Manage` a sheet, not a permanent screen.

## 5. Option B - Pinned Dock Lens

### Concept

Add `Pinned` as an internal Dock lens alongside `Newest`, `Host`, and `Branch`.
Selecting it shows only pinned threads.

### Wireframe

```text
+------------------------------------------+
| Dock                         Online 2/2  |
| [ Search sessions, repo, branch, host  ] |
| [Newest] [Pinned] [Host] [Branch] (filt) |
| Pinned 3 · sorted by newest activity     |
|                                          |
| +--------------------------------------+ |
| | pin  ramp up on code base...    now >| |
| |      Amir-M5 · freedom · dock-counts | |
| +--------------------------------------+ |
| +--------------------------------------+ |
| | pin  psmobile animation engine  2m > | |
| |      Amir-M5 · psmobile · feat/anim  | |
| +--------------------------------------+ |
+------------------------------------------+
```

### Why This Works

- Minimal vertical cost on the default newest feed.
- Easy to understand: `Pinned` is a list mode.
- Good for explicit review of all pinned threads.

### Why It Is Weaker Than Option A

- The user has to switch away from newest activity to watch pins.
- On iPhone, adding a fourth segment competes with the existing filter button.
- `Pinned` risks becoming another primary tab-like bucket, which is exactly
  what the product should avoid for untrusted statuses.

Best use:

- Keep this as a secondary path or a `Manage pinned` sheet, not the main
  solution.

## 6. Option C - Pinned Scope Chip / Filter

### Concept

Treat pinned threads as a normal filter. The user can tap `Pinned 3` or select
`Pinned only` in the filter sheet. When active, the summary row shows a
removable scope chip.

### Wireframe

```text
+------------------------------------------+
| Dock                         Online 2/2  |
| [ Search sessions, repo, branch, host  ] |
| [Newest] [Host] [Branch]          (filt) |
| [Pinned: 3  x] [Host: Any] [Idle hidden] |
|                                          |
| +--------------------------------------+ |
| | pin  ramp up on code base...    now >| |
| |      Amir-M5 · freedom · dock-counts | |
| +--------------------------------------+ |
| +--------------------------------------+ |
| | pin  psmobile animation engine  2m > | |
| |      Amir-M5 · psmobile · feat/anim  | |
| +--------------------------------------+ |
+------------------------------------------+
```

### Why This Works

- Fits the current filter architecture.
- Gives clear applied-scope state.
- Easy to combine with host, branch, repo, and status filters.

### Why It Is Weaker Than Option A

- Filtering to pins hides non-pinned newest activity.
- It does not create a persistent watch surface.
- It is useful for management and cleanup, but not enough for the core user
  story.

Best use:

- Add `Pinned only` as a filter and active chip, but do not make it the only
  pinned UX.

## 7. Option D - Bottom Watch Accessory

### Concept

Show a small `Watch 3` accessory above the bottom tab bar. It stays visible
while the user scrolls the feed. Tapping expands a pinned thread sheet.

### Wireframe

```text
+------------------------------------------+
| Dock                         Online 2/2  |
| [ Search sessions, repo, branch, host  ] |
| [Newest] [Host] [Branch]          (filt) |
| 400 shown · Hosts: Any · Idle hidden     |
|                                          |
| +--------------------------------------+ |
| | newest row                       now >| |
| +--------------------------------------+ |
| | newest row                       1m  >| |
| +--------------------------------------+ |
|                                          |
| +--------------------------------------+ |
| | Watch 3  ramp up... now · anim... 2m | |
| +--------------------------------------+ |
| Dock              Archive        Relay   |
+------------------------------------------+
```

### Why This Works

- Pins remain visible even when the user scrolls far down the list.
- Does not push the feed down at the top.
- Similar mental model to a mini player: a persistent compact object that can
  expand.

### Why It Is Risky

- It competes with the tab bar and bottom safe area.
- It can obscure list content.
- It is more custom UI and therefore higher implementation risk.
- It may feel too important for a 2-3-thread helper feature.

Best use:

- Consider later if pinned-thread monitoring becomes a dominant workflow.
- Do not start here.

## 8. Option E - Host/Branch Group Pinning

### Concept

Inside `Host` and `Branch` lenses, show pinned threads at the top of each group
or mark them with a pin icon.

### Wireframe

```text
+------------------------------------------+
| Dock                         Online 2/2  |
| [ Search sessions, repo, branch, host  ] |
| [Newest] [Host] [Branch]          (filt) |
|                                          |
| Amir-M5                         2 pinned |
| +--------------------------------------+ |
| | pin  ramp up on code base...    now >| |
| +--------------------------------------+ |
| |      regular Amir-M5 row        3m  >| |
| +--------------------------------------+ |
|                                          |
| Home                            1 pinned |
| +--------------------------------------+ |
| | pin  relay aggregator...       4m  >| |
| +--------------------------------------+ |
+------------------------------------------+
```

### Why This Works

- Preserves host/branch context.
- Helps when the user is mentally working by machine or branch.
- Makes pinned rows scan well in grouped lenses.

### Why It Is Not Enough

- It does not help the default `Newest` lens.
- The user has to choose the right lens before the pin helps.
- It is supplemental behavior, not the core pinned experience.

Best use:

- Add pin markers and top-of-group behavior inside `Host` and `Branch` lenses
  after Option A exists.

## 9. Interaction Model

### Pin Entry Points

Use at least these:

- Row swipe action: `Pin` / `Unpin` with a pin icon.
- Row context menu: `Pin thread` / `Unpin thread`.
- Detail toolbar button: pin icon toggles pinned state.
- Optional pinned strip item action: `Unpin`.

Context menu alone is insufficient because it is hidden.

### Unpin Entry Points

Use at least these:

- Pinned strip item: visible unpin or menu.
- Detail toolbar: selected pin icon toggles off.
- Context menu: `Unpin thread`.
- Manage pinned sheet: multi-select or per-row unpin.

Unpin should not archive by default. `Done` and `Archive` can be separate
actions later, but the first version should keep pin state simple.

### Visual Language

Recommended:

- Use a `pin` / `pin.fill` style icon for pinned state.
- Use a small icon in the row metadata area or leading status rail.
- Keep row title as the main text.
- Keep host/repo/branch metadata visible.
- Use the existing row color rail for status/source only if it already has a
  meaning; do not overload it as the only pin marker.

Avoid:

- A text badge that says `Pinned` on every row.
- A top-level app tab.
- A permanent `Pinned 0` control on the default screen.
- A huge card section that hides the first newest row.
- Hiding pin/unpin only in long-press.

## 10. State And Data Model Expectations

This doc is UX strategy, not an implementation plan, but the UX depends on a
few state rules.

Pin identity:

- Key pins by stable `(hostID, threadID)`.
- Display short host names, not endpoints, in the watch surface.
- Keep endpoint detail available in Relay/diagnostic surfaces.

Persistence:

- Best user experience: pins follow the user's Dock setup across the user's
  devices.
- If pins are local-only, the UI should not pretend they sync.
- Given this product is across multiple devices, relay-backed or shared metadata
  is the stronger product direction.

Offline and missing data:

- Pinned row remains visible if host goes offline.
- Row shows `Offline`, `Stale`, or `Not loaded` honestly.
- A pinned thread with missing details should still be clickable if there is a
  known thread id and host.
- If the thread no longer exists, show an unavailable state and offer `Unpin`.

Ordering:

- Pinned strip sorts pinned threads by last activity.
- Main newest feed remains newest-first across all threads.
- Pinned rows in the main feed retain their natural newest position.

Count behavior:

- `0`: hide pinned strip.
- `1-3`: show all pinned items.
- `4+`: show top 3 by activity and a `Manage` / `See all` affordance.

## 11. Recommended MVP

Build this shape first:

1. Add explicit pin/unpin metadata keyed by `(hostID, threadID)`.
2. Add pin/unpin actions on row swipe, row context menu, and detail toolbar.
3. Add a compact pinned watch strip above the newest feed when count is greater
   than zero.
4. Add small pin markers to pinned rows in all lenses.
5. Add `Pinned only` to Filters as a normal filter/scope.
6. Add a simple `Manage pinned` sheet only if count exceeds 3 or the user taps
   the pinned header.

Why this MVP:

- It directly serves the "2-3 real threads" use case.
- It is explicit and user-owned.
- It preserves newest-first as the default.
- It keeps host/branch lookup intact.
- It does not lean on unreliable inference.

## 12. Mockup Set To Generate

Use real screenshots from:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-dock-live.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-filters-live.png`

Generate these options:

1. `01-pinned-watch-strip.png`
   - Recommended compact top watch strip.
2. `02-pinned-lens.png`
   - Internal Dock lens alternative.
3. `03-bottom-watch-accessory.png`
   - Persistent bottom accessory alternative.
4. `04-pinned-filter-manage.png`
   - Filter/manage sheet showing pinned-only scope and unpin actions.

Prompt constraints:

- Keep the current iPhone 17 app style.
- Preserve `Dock`, `Online 2/2`, full-width search, `Newest`, `Host`,
  `Branch`, filter button, and bottom tabs unless the option explicitly changes
  a control.
- Use exact visible labels where specified.
- Do not include `Needs me`.
- Do not include `Limited`.
- Do not imply rate limiting.
- Show short host names such as `Amir-M5` and `Home`.
- Keep the UI dense and useful for a large list.
- Make pinned state clear without turning every row into a giant card.

## 13. Recommendation

Choose Option A as the primary product direction:

> Compact pinned watch strip + explicit row/detail pin actions + `Pinned only`
> as a secondary filter.

Keep Option B and Option C as supporting views:

- Option B can become `Manage pinned` or a secondary Dock lens if needed.
- Option C belongs in Filters for cleanup and combinations with host/branch.

Do not start with Option D:

- It is interesting, but it is too custom and too prominent for the first
  version.

Do not make pins predictive:

- The whole point is that the user knows which 2-3 threads matter. The product
  should respect that and give the user a simple, durable handle.
