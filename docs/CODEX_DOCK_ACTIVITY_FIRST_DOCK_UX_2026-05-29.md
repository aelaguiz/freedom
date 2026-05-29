---
title: "Codex Dock - Newest-First Host And Branch UX Strategy"
date: 2026-05-29
status: draft_for_review
owners: [aelaguiz]
reviewers: [Codex]
doc_type: ux_strategy
related:
  - docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md
  - docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md
  - README.md
---

# Codex Dock - Newest-First Host And Branch UX Strategy

## 0. TL;DR

The Dock should be a newest-first work index with strong host and branch
lenses. It should not be a host-status header followed by rows that feel
unattached to those hosts.

Live accessibility-tree inspection on the booted iPhone 17 simulator on
2026-05-29 made the recommendation more concrete: the current first screen can
sit for a long time in a loading state with `All 0`, `Needs me 0`,
`Running 0`, `Agents 0`, a squeezed search field, and raw endpoint host names.

Default screen:

- show the newest sessions first
- make host and branch visible on each row
- make host and branch usable as one-tap filters/lenses
- keep host health compact, not pinned as large content above the list
- use short host display names in the scan path, not endpoint strings
- move empty or untrusted status filters out of the primary row
- avoid pretending to know the user's workflow

Important product correction:

- Do not bias the Dock around `Needs me`.
- If `Needs me` is always zero or cannot be trusted, it should not be a primary
  tab, primary section, or ranking assumption.
- A future `Needs input` style signal can exist only if it is backed by a
  reliable server state, is visibly explainable, and proves useful in real use.

The first product question is not "which session needs me?" It is:

> What changed most recently, where is it running, and how do I quickly narrow
> this giant list by host, branch, repo, or status?

## 1. Context

Codex Dock is an iPhone operations surface for many Codex sessions across
multiple personal machines. The user often has a large list of sessions,
multiple hosts, multiple branches, and recent churn that may or may not be
important.

The product must support two different discovery modes:

1. Recency recovery: "Show me the newest thing because I just changed context."
2. Known-target lookup: "Find the thread on this host, branch, repo, or topic."

The current app already has the ingredients, but the information architecture
is not doing enough work:

- `README.md` describes Dock controls for Search, Sort, and `Idle`.
- Search matches title, label, repository or working directory, branch, summary,
  status, host, and thread id.
- Sort has `Branch` and `Newest`.
- `Branch` keeps branch/host grouping and orders visible groups and rows by
  newest activity first.
- `Newest` shows one flat newest-first list.
- `Idle` is off by default.
- The current SwiftUI Dock renders host summaries before sections.
- The current row view shows title, repo, branch, status, summary, and time,
  but it does not visibly show host inside the row.
- The model/search path knows host identity, but the visible row does not make
  that relationship obvious enough.

That mismatch is the UX bug: the system technically knows host and branch, but
the screen does not make the relationship easy to see at scanning speed.

## 2. Research Inputs

### 2.1 Local product research

Read locally:

- `README.md`
- `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`
- `docs/CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md`
- `docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/Features/Dock/DockSharedViews.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/State/DockSessionProjection.swift`
- `CodexDock/State/SessionRowProjector.swift`

Important local findings:

- The original iPhone UX spec says the Dock should answer what is happening
  across sessions and make many sessions scannable.
- It explicitly calls out multiple hosts, branch/server grouping, labels,
  colors, search, archive, and quick phone interaction.
- Prior usage evidence in that spec says the user has hundreds or thousands of
  Codex sessions in recent history and often works across machines.
- The current README already describes a reasonable primitive model:
  search + sort + idle visibility.
- `SessionRowProjector` creates host/branch section titles for multi-host
  lists by using `Host / Branch`.
- `DockSessionProjection` can render either branch-grouped sections or one flat
  newest-first section.
- `DockView.loadedContent` renders all `HostSummaryView` rows before all thread
  sections.
- `DockRowView` does not visibly show host, even though its accessibility value
  and search metadata include host.
- The current `Needs me` status comes from active flags such as
  waiting-on-approval or waiting-on-user-input. If those flags are not populated
  reliably in real usage, the UI must not make `Needs me` the center of the
  product.

### 2.2 Apple HIG: search should start broad and refine

Source:
<https://developer.apple.com/design/human-interface-guidelines/search-fields>

Relevant guidance from Apple:

- A search field searches a collection of content.
- Search fields can use scope controls and tokens to refine scope.
- Placeholder text should describe what can be searched.
- Search can update immediately as a person types.
- Results should prioritize the most relevant items and can be categorized.
- Scope controls help narrow from a broader set to a narrower set.
- Apple recommends defaulting search to a broader scope and letting people
  refine as needed.
- Tokens can represent common filter terms and make filters visible/editable.

Dock implication:

- Search should remain global by default.
- Host and branch should be suggested filter tokens, not hidden implementation
  details.
- The user should be able to search "codex-client main home" without first
  choosing the right mode.
- The screen should show active filters as visible chips/tokens.

### 2.3 Apple HIG: top-level tabs should stay stable and few

Source:
<https://developer.apple.com/design/human-interface-guidelines/tab-bars>

Relevant guidance from Apple:

- Tab bars are for top-level app navigation.
- Fewer tabs are easier to navigate.
- Tabs should not be actions.
- Tabs should remain stable and not disappear because content is unavailable.
- Labels help clarify tab meaning.

Dock implication:

- Do not create top-level app tabs for every Dock lens.
- Keep `Dock`, `Archive`, and `Relay`/`Hosts` as the top-level app model.
- `Newest`, `Host`, and `Branch` are view modes inside Dock, not app tabs.

### 2.4 NN/g: information scent matters

Source:
<https://media.nngroup.com/media/articles/attachments/InformationForaging_SizeLetter.pdf>

Relevant guidance from NN/g:

- Users choose where to go based on perceived information value and perceived
  cost.
- A result that looks promising has strong information scent.
- If the user cannot tell whether a row is relevant quickly, the perceived cost
  rises.

Dock implication:

- A row must show enough identity to be worth tapping.
- Host, branch, repo, status, and last activity are not secondary trivia in this
  product. They are information scent.
- If host identity lives only above the list, the row loses scent when it is
  scanned out of that context.

### 2.5 NN/g: scanning users read the beginning first

Source:
<https://media.nngroup.com/media/reports/free/Social_Media_User_Experience.pdf>

Relevant guidance from NN/g:

- In fast-scanned lists, users often read only the first few characters.
- Items should front-load meaningful identifiers.
- Long or unclear identifiers make users skip or misinterpret list entries.

Dock implication:

- Row titles need to be concise and useful.
- Host and branch labels should be compact.
- Avoid long endpoint strings in the main scan path.
- Put high-value row cues early and consistently.

### 2.6 NN/g: facets help reduce large result sets

Source:
<https://media.nngroup.com/media/reports/free/Designing_for_Young_Adults_3rd_Edition.pdf>

Relevant guidance from NN/g:

- Faceted search helps people reduce large amounts of information into a
  manageable set.
- Counts on facet categories help users decide whether a category is worth
  applying.

Dock implication:

- Host, branch, status, source type, idle visibility, and not-loaded visibility
  should behave like facets.
- Facets should show counts when practical.
- The user should not have to guess whether a host or branch filter will produce
  results.

### 2.7 Baymard: large-list UX depends on filtering, sorting, and list-item info

Source:
<https://baymard.com/research/ecommerce-product-lists>

Relevant guidance from Baymard:

- Large product/result lists become hard to use without the right tools.
- Filtering narrows large generic lists to relevant subsets.
- Sorting speeds exploration by ordering by the attribute the user cares about.
- List-item information, filtering, and sorting must work as one system.

Dock implication:

- Sorting by newest is necessary but not sufficient.
- Filtering by host and branch is necessary but not sufficient.
- Row design must show the same attributes the filters and sorts operate on.
- A Dock row should not ask the user to remember which host group appeared 500
  pixels above it.

### 2.8 Live iPhone 17 accessibility-tree observation, 2026-05-29

Observed through Mobile MCP accessibility elements after repairing a stale
WebDriverAgent runner. No screenshot evidence is required for this section.

Device and app evidence:

- Simulator: `feat_anim_1 - iPhone 17`
- UDID: `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
- App bundle: `com.aelaguiz.CodexDockApp`
- Installed app build reported by `simctl listapps`: `20260529153750`
- Makefile launch command used to avoid stale config:
  `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
- Environment config used by that launch:
  `CODEX_DOCK_HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`
- App logs confirm `host registry loaded from environment hosts=2`.
- App logs confirm connections to both:
  - `amir-m5.fairy-salmon.ts.net:4510`
  - `home.fairy-salmon.ts.net:4510`
- Same-simulator logs showed repeated loaded Dock results:
  - `10:40:43`: `dock reload finished hosts=2 rows=6494 duration_ms=149674`
  - `10:43:16`: `dock reload finished hosts=2 rows=6494 duration_ms=147943`
  - `10:45:59`: `dock reload finished hosts=2 rows=6494 duration_ms=145282`
  - `10:48:26`: `dock reload finished hosts=2 rows=6494 duration_ms=141559`
- A full Mobile MCP accessibility-tree dump works in the loading state, but
  timed out after the 6,494-row loaded state. A narrow XCTest probe also became
  too expensive once it waited on loaded-row descendants. That is not a product
  feature, but it is strong evidence that the Dock surface is operating at
  "huge list" scale.

Visible accessibility state during the current clean launch:

- Header title: `Dock`
- Connectivity element: `codexdock.connectivity.global`, value
  `amir-m5.fairy-salmon.ts.net:4510: Checking`
- Header action: `codexdock.dock.add-host`, label `Add host`
- Primary filters:
  - `codexdock.dock.filter.all`, label `All 0`
  - `codexdock.dock.filter.needsMe`, label `Needs me 0`
  - `codexdock.dock.filter.running`, label `Running 0`
  - `codexdock.dock.filter.agents`, label `Agents 0`
- Search field: `codexdock.dock.search`, value `Search sessions`, visible width
  about 109 points in the accessibility frame.
- Sort mode: `Branch` selected; `Newest` available.
- Idle control: `codexdock.dock.idle-toggle`, value `Off`.
- Loading host row:
  - identifier `codexdock.dock.host.amir-m5.fairy-salmon.ts.net%3A4510`
  - value `amir-m5.fairy-salmon.ts.net:4510; Loading`
  - visible label includes `amir-m5.fairy-salmon.ts.net:4510 · Loading`
- Bottom tabs are readable: `Dock`, `Archive`, `Relay`.

UX reading:

- The current clean-launch first screen is not just visually busy; the
  accessibility tree proves the primary row exposes four zero-count tabs while
  the real list is still loading.
- The current loaded path takes roughly 141-150 seconds for this data set, so
  loading UX is not a transient detail; it is a major part of the real
  experience.
- `Needs me 0` and `Running 0` should not occupy primary first-screen space
  when the app cannot prove they are useful.
- Search is too constrained for a giant-list product; it is narrower than the
  status/sort/filter controls competing beside it.
- `Branch` being selected by default means the screen starts in a grouping lens
  before the user has asked for grouping.
- Raw endpoint strings are the dominant host identity in loading and host rows.
- A single host loading row appears even though app logs confirm the configured
  launch has two hosts; loading state should represent the whole host set
  honestly.
- Long loading duration is itself a Dock UX problem. During a multi-thousand-row
  load, the UI should not show zero-count filters as if they were the real
  state.

What this changes in the strategy:

- Be more explicit that `Newest` should be the default mode.
- Treat `Needs me` and `Running` as secondary filters until the signals are
  trustworthy and non-empty in real use.
- Give search a full-width row or system search placement on iPhone.
- Use short host display names in Dock, with endpoint strings reserved for
  Relay settings and diagnostics.
- Add a real large-list loading state: known hosts, loading progress/status,
  and no misleading zero-count tabs.
- Make first-screen controls reflect what the user can do now, not all internal
  categories the app knows about.

## 3. Product Position

The Dock is not a predictive assistant. It should not assume the user's current
workflow based on weak signals.

The Dock is a fast, explicit, high-information index over sessions.

The best product shape is:

- literal defaults
- strong visible metadata
- fast narrowing
- low trust in unproven inference
- no vague state labels

## 4. Current UX Problem

The current Dock makes host visible in a way that is structurally present but
weak in real scanning.

The screen has host summaries near the top. Those summaries consume space and
communicate service status, but after the user scrolls into sessions, the rows
do not clearly carry host identity.

That creates a bad mental model:

- the host cards look pinned and separate
- sections below feel like a different list
- a row does not always say which machine owns it
- branch grouping can compete with newest-first recovery
- branch lookup works only if the user already understands the projection
- host health appears more prominent than session discovery

The host summary should not be removed as information. It should be moved into
a more compact status/filter role.

## 5. Recommended Information Architecture

Keep the app-level tabs:

```text
+----------------------------+
| Dock | Archive | Relay    |
+----------------------------+
```

Inside Dock, use view modes:

```text
+----------------------------+
| Newest | Host | Branch    |
+----------------------------+
```

These modes are not predictions. They are user-chosen lenses:

- `Newest`: flat list ordered by last activity.
- `Host`: host groups with their threads nested under each host.
- `Branch`: branch groups with host visible on each row.

Default mode:

- `Newest`

Why:

- The user's stated need is to see the newest changed sessions.
- It is literal and explainable.
- It does not depend on unreliable `Needs me` inference.
- It works across hosts and branches.
- It keeps the default experience honest when status signals are zero,
  unreliable, or still loading.

## 6. Recommended Dock Header

The top area should be compact and mostly functional:

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ Search title, repo, branch, host...        ] |
| [Newest] [Host] [Branch]          [Filters]    |
| Host: Any  Branch: Any  Idle: Off             |
+------------------------------------------------+
```

Header rules:

- Keep title, global connectivity, search, mode switch, and active filters.
- Do not render large host cards before the list.
- Host status should be one compact line, pill, or popover.
- Host pills can be tappable filters.
- Active filters should stay visible until cleared.
- Search must not be squeezed into a narrow control beside sort and idle on
  iPhone.
- A disabled or low-value add-host action should not be a large primary control
  in the Dock header.

Host health compact examples:

```text
Online 2/2
Amir-M5 12  Home 7
Hosts: Amir-M5 12, Home 7, Studio offline
```

Avoid:

```text
home
amir-m5.fairy-salmon.ts.net:4510 - 18 sessions

home.fairy-salmon.ts.net:4510
...

[then, far below, unrelated-looking thread rows]
```

Also avoid endpoint strings as primary visible names:

```text
amir-m5.fairy-salmon.ts.net:4510
home.fairy-salmon.ts.net:4510
```

Prefer short display names:

```text
Amir-M5
Home
```

## 7. Row Contract

Every Dock row should be understandable on its own.

Minimum visible row fields:

- title
- status
- last activity time
- host
- branch
- repo or working directory
- short latest summary
- optional local label/color

Recommended row anatomy:

```text
+------------------------------------------------+
| [rail] Thread title              Running   2m  |
|        host: Amir-M5   branch: feature/dock    |
|        repo: codex-client                      |
|        latest useful summary text              |
+------------------------------------------------+
```

Compact row anatomy:

```text
+------------------------------------------------+
| [rail] Thread title              Running   2m  |
|        Amir-M5  /  codex-client  /  feature    |
|        latest useful summary text              |
+------------------------------------------------+
```

Rules:

- Show host on every row when more than one host exists.
- Use display names like `Amir-M5` and `Home`, not long endpoint strings.
- Keep endpoint strings in Relay/Host settings or detail popovers.
- Put branch near repo because the user often looks for work by branch.
- Keep status as a small chip, not the primary organizing principle.
- Keep `Not loaded` visually neutral.

## 8. Newest Mode

Newest mode is the default.

Purpose:

- recover the most recently changed session
- quickly scan across all machines
- avoid hiding useful sessions under host or branch sections

Wireframe:

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ Search title, repo, branch, host...        ] |
| [Newest] [Host] [Branch]          [Filters]    |
| Host: Any  Branch: Any  Idle: Off             |
+------------------------------------------------+
| NEWEST                                         |
|                                                |
| [blue] Render geometry audit       Running 2m  |
|        Amir-M5 / codex-client / dock-ui        |
|        command output updated                  |
|                                                |
| [red ] Account rotation plan       Idle    8m  |
|        Home / aimgr / codex-rotation           |
|        last assistant message                  |
|                                                |
| [gray] Dart animation SSOT         Not loaded  |
|        Amir-M5 / lessons / feature/animation   |
|        content not loaded on this relay        |
|                                                |
| [teal] Play vs AI preview          Running 19m |
|        Home / gw_controls / controls-cleanup   |
|        recent file edits                       |
+------------------------------------------------+
| Dock              Archive              Relay   |
+------------------------------------------------+
```

Ordering rules:

- Primary: newest last activity.
- Secondary: deterministic tie-breakers only.
- Do not secretly lift `Needs me` above recency unless the user chose a status
  filter and the signal is trustworthy.
- Do not let not-loaded or idle rows dominate if the user has explicitly hidden
  them.

## 9. Host Mode

Host mode is for answering:

> What is happening on this machine?

Wireframe:

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ Search title, repo, branch, host...        ] |
| [Newest] [Host] [Branch]          [Filters]    |
+------------------------------------------------+
| v Amir-M5                         12 sessions  |
|   Online   newest 2m   running 4   idle hidden |
|                                                |
|   [blue] Render geometry audit     Running 2m  |
|          codex-client / dock-ui                |
|          command output updated                |
|                                                |
|   [gray] Dart animation SSOT       Not loaded  |
|          lessons / feature/animation           |
|          content not loaded                    |
|                                                |
| v Home                             7 sessions  |
|   Online   newest 8m   running 1   idle hidden |
|                                                |
|   [red ] Account rotation plan     Idle    8m  |
|          aimgr / codex-rotation                |
|          last assistant message                |
+------------------------------------------------+
```

Host mode rules:

- Threads are visually nested under host headers.
- Host headers are compact, collapsible, and count-bearing.
- Each host group sorts by newest activity inside the host.
- Host groups sort by newest visible activity, not static config order, unless
  the user pins a host.
- Offline hosts remain visible but collapsed by default if they have no current
  rows.
- Host endpoint strings stay secondary.

Optional host affordances:

- tap host header: filter to this host
- long press host header: host actions
- collapse/expand host group
- show offline/error detail inline only when needed

## 10. Branch Mode

Branch mode is for answering:

> Where is the thread for this branch?

Wireframe:

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ Search title, repo, branch, host...        ] |
| [Newest] [Host] [Branch]          [Filters]    |
+------------------------------------------------+
| v dock-ui                         3 sessions   |
|   newest 2m   hosts: Amir-M5, Home             |
|                                                |
|   [blue] Render geometry audit     Running 2m  |
|          Amir-M5 / codex-client                |
|          command output updated                |
|                                                |
|   [teal] Host section cleanup      Idle   41m  |
|          Home / codex-client                   |
|          last assistant message                |
|                                                |
| v codex-rotation                 2 sessions    |
|   newest 8m   hosts: Home                      |
|                                                |
|   [red ] Account rotation plan     Idle    8m  |
|          Home / aimgr                          |
|          last assistant message                |
+------------------------------------------------+
```

Branch mode rules:

- Branch groups sort by newest visible activity.
- Rows inside a branch group sort newest-first.
- Host is visible on every row because branch grouping removes host from the
  section title.
- Branch search should be exact and forgiving:
  - `main`
  - `feature/dock`
  - `dock`
  - repo plus branch
  - host plus branch

## 11. Search And Filter Model

Search should remain broad by default.

Search examples that should work:

```text
main
home main
Amir-M5 dock
codex-client host settings
feature/animation
thread id fragment
```

Active search/filter state should be visible:

```text
Host: Amir-M5   Branch: dock-ui   Idle: Off   Clear
```

Filter sheet:

```text
+------------------------------------------------+
| Filters                                  Clear |
+------------------------------------------------+
| Host                                           |
| [Amir-M5 12] [Home 7] [Studio offline]        |
|                                                |
| Branch                                         |
| [ Search branches...                        ] |
| [dock-ui 3] [main 3] [codex-rotation 2]       |
|                                                |
| Status                                         |
| [Running 5] [Idle 14] [Not loaded 9] [Error 1]|
|                                                |
| Source                                         |
| [Human 18] [Agents 25]                        |
|                                                |
| Visibility                                     |
| [ ] Show idle                                  |
| [ ] Show not loaded only                       |
+------------------------------------------------+
| Show 24 sessions                               |
+------------------------------------------------+
```

Rules:

- Search and filters compose.
- Counts update based on current search where practical.
- Filters are explicit and reversible.
- The user should never have to guess what is currently hidden.
- Do not bury branch behind only free-text search; provide branch as a real
  facet because branch lookup is a core use case.

## 12. Status Model

Recommended visible status labels:

- `Running`
- `Idle`
- `Not loaded`
- `Error`
- `Unknown`

Do not use:

- `Limited`

`Not loaded` means:

- the Dock has a thread row or history reference
- the app does not currently know enough loaded thread detail to summarize it
- the row is not necessarily broken, rate-limited, or blocked

`Needs me` guidance:

- Do not make `Needs me` a default tab.
- Do not make `Needs me` a top section.
- Do not use `Needs me` as a ranking primitive until real usage proves the
  signal works.
- If kept for debugging, make it a secondary filter or status chip only.
- If reintroduced later, consider a more literal name like `Needs input` and
  only show it when the underlying event is explicit and inspectable.
- If live accessibility evidence keeps showing `Needs me 0`, remove it from the
  primary Dock surface.

`Running` guidance:

- Do not make `Running` a primary tab if live usage usually shows `Running 0`.
- Keep it as a status filter only if the data is reliable.
- If it is unreliable, move it behind a secondary/debug path until the status
  model is fixed.

`Agents` guidance:

- Agents should be available as a scope/filter.
- Do not let a massive or zero agent count turn the primary tab row into a raw
  plumbing dashboard.

The UI should not predict that a thread is important. It should show the user
the newest sessions and give fast, explicit ways to narrow the list.

## 13. Noise Handling

The Dock list is large. The answer is not hidden prediction. The answer is
user-controlled narrowing plus honest defaults.

Recommended defaults:

- default to newest-first
- hide idle by default if the user has already accepted that behavior
- show `Not loaded` as neutral, not alarming
- show enough rows to preserve trust that the list is complete
- make hidden state visible with chips or copy, for example `Idle off`
- during loading, show known hosts and loading state rather than zero-count
  tabs that look final

Noise controls:

- `Idle` toggle
- host filter
- branch filter
- source filter: human vs agents
- status filter
- text search
- optional pinned host or pinned branch after explicit user action

Avoid:

- auto-predicting the active project
- hiding rows without explaining why
- promoting rows because the app guesses they matter
- letting stale host banners consume the top of the screen

## 14. Optional Pinning

Pinning can be useful, but only as explicit user intent.

Examples:

- pin host `Amir-M5`
- pin branch `dock-ui`
- pin repo `codex-client`

Pinned state should behave like a visible filter:

```text
Pinned: Amir-M5   Clear
```

Pinning should not be automatic in V1.

## 15. Empty And Partial States

Newest empty:

```text
+------------------------------------------------+
| No sessions match these filters                |
| Host: Amir-M5   Branch: dock-ui   Idle: Off    |
|                                                |
| [Clear filters]                                |
+------------------------------------------------+
```

Host offline:

```text
+------------------------------------------------+
| v Studio                          Offline      |
|   Last check failed: connection timed out      |
|   [Retry] [Relay settings]                     |
+------------------------------------------------+
```

Not loaded filter:

```text
+------------------------------------------------+
| NOT LOADED                                     |
| These sessions exist in the list, but Dock     |
| does not have loaded thread detail for them.   |
+------------------------------------------------+
```

Rules:

- Empty states should state what filter or state caused emptiness.
- Offline hosts should not block online hosts.
- Partial failures should be attached to affected host/scope, not presented as
  global mystery.

## 16. ASCII End-To-End Screen Set

### 16.1 Default open

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ Search title, repo, branch, host...        ] |
| [Newest] [Host] [Branch]          [Filters]    |
| Host: Any  Branch: Any  Idle: Off             |
+------------------------------------------------+
| NEWEST                                         |
| [blue] Render geometry audit       Running 2m  |
|        Amir-M5 / codex-client / dock-ui        |
|        command output updated                  |
|                                                |
| [red ] Account rotation plan       Idle    8m  |
|        Home / aimgr / codex-rotation           |
|        last assistant message                  |
|                                                |
| [gray] Dart animation SSOT         Not loaded  |
|        Amir-M5 / lessons / feature/animation   |
|        content not loaded                      |
+------------------------------------------------+
| Dock              Archive              Relay   |
+------------------------------------------------+
```

### 16.2 Host lens

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ Search title, repo, branch, host...        ] |
| [Newest] [Host] [Branch]          [Filters]    |
+------------------------------------------------+
| v Amir-M5                         12 sessions  |
|   Online   newest 2m   running 4   idle hidden |
|   [blue] Render geometry audit     Running 2m  |
|          codex-client / dock-ui                |
|   [gray] Dart animation SSOT       Not loaded  |
|          lessons / feature/animation           |
|                                                |
| v Home                             7 sessions  |
|   Online   newest 8m   running 1   idle hidden |
|   [red ] Account rotation plan     Idle    8m  |
|          aimgr / codex-rotation                |
+------------------------------------------------+
```

### 16.3 Branch lens

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ Search title, repo, branch, host...        ] |
| [Newest] [Host] [Branch]          [Filters]    |
+------------------------------------------------+
| v dock-ui                         3 sessions   |
|   newest 2m   hosts: Amir-M5, Home             |
|   [blue] Render geometry audit     Running 2m  |
|          Amir-M5 / codex-client                |
|   [teal] Host section cleanup      Idle   41m  |
|          Home / codex-client                   |
|                                                |
| v codex-rotation                  2 sessions   |
|   newest 8m   hosts: Home                      |
|   [red ] Account rotation plan     Idle    8m  |
|          Home / aimgr                          |
+------------------------------------------------+
```

### 16.4 Branch search

```text
+------------------------------------------------+
| Dock                              Online 2/2   |
| [ dock-ui                                      ]|
| [Newest] [Host] [Branch]          [Filters]    |
| Search: dock-ui                 Clear          |
+------------------------------------------------+
| 3 sessions                                      |
| [blue] Render geometry audit       Running 2m  |
|        Amir-M5 / codex-client / dock-ui        |
| [teal] Host section cleanup        Idle   41m  |
|        Home / codex-client / dock-ui           |
| [gray] Old dock audit              Not loaded  |
|        Amir-M5 / codex-client / dock-ui        |
+------------------------------------------------+
```

### 16.5 Filter sheet

```text
+------------------------------------------------+
| Filters                                  Clear |
+------------------------------------------------+
| Host                                           |
| [Amir-M5 12] [Home 7] [Studio offline]        |
|                                                |
| Branch                                         |
| [ Search branches...                        ] |
| [dock-ui 3] [main 3] [codex-rotation 2]       |
|                                                |
| Status                                         |
| [Running 5] [Idle 14] [Not loaded 9] [Error 1]|
|                                                |
| Source                                         |
| [Human 18] [Agents 25]                        |
|                                                |
| Visibility                                     |
| [ ] Show idle                                  |
| [ ] Show not loaded only                       |
+------------------------------------------------+
| Show 24 sessions                               |
+------------------------------------------------+
```

## 17. Product Anti-Patterns To Avoid

Avoid pinned host cards above the main list:

- They take space from the actual work list.
- They imply the rows below belong to a separate area.
- They make host status visually louder than session discovery.

Avoid `Needs me` as a foundation:

- The user reports it always shows zero.
- It is not currently trusted.
- A broken priority signal is worse than no priority signal.

Avoid vague or overloaded labels:

- `Limited` looked like rate limiting but actually meant missing/not-loaded
  data.
- This kind of label breaks trust because it suggests a specific failure mode
  the app does not know.

Avoid purely predictive ranking:

- The app should not guess the user's current machine or branch unless the user
  explicitly pins or filters it.
- Recency and explicit filters are easier to understand and correct.

Avoid branch-only default grouping:

- Branch grouping is useful for lookup.
- It can be worse for "what changed newest?" because it splits the feed into
  groups before the user has chosen that lens.

Avoid raw endpoint names in the scan path:

- They wrap.
- They are visually noisy.
- They make the Dock feel like service diagnostics instead of a session index.
- Keep them in Relay settings, diagnostics, or detail surfaces.

Avoid cramped control rows:

- A narrow search field is a bad tradeoff in a giant-list product.
- Search should get a full row or system search placement on iPhone.
- Sort, filters, and idle visibility can sit below search or behind a compact
  filter control.

Avoid misleading loading counts:

- `All 0`, `Needs me 0`, `Running 0`, and `Agents 0` should not look like final
  list counts while the app is still loading.
- Loading state should say what is being loaded and which hosts are involved.

## 18. Implementation Consequences For A Later Plan

This doc is UX strategy only, not an implementation plan, but it implies these
future product changes:

- Make `Newest` the default Dock view mode.
- Keep `Host` and `Branch` as explicit modes.
- Move host summaries out of the main row flow.
- Add visible host metadata to Dock rows when more than one host exists.
- Add host/branch/status filters with visible active chips.
- Remove `Needs me` as a primary tab unless the signal is proven reliable.
- Remove `Running` as a primary tab if it is also usually zero or unreliable.
- Move `Agents` into a clear source/scope filter instead of a primary tab if it
  competes with normal session scanning.
- Give search enough width on iPhone.
- Replace endpoint strings with short host display names in Dock rows, section
  headers, and host groups.
- Make the large-list loading state honest: known hosts, loading status, no
  final-looking zero-count tabs.
- Reduce or remove the large disabled header add-host button from Dock.
- Keep `Not loaded`; do not use `Limited`.
- Preserve `Idle` as an explicit visibility control.

## 19. Review Criteria

A future design or implementation should pass these checks:

- On app open, the first visible session row is a recent session, not a host
  status card.
- Every visible row can be understood without remembering a header far above it.
- Host mode clearly nests threads under host headers.
- Branch mode clearly nests threads under branch headers and still shows host.
- Search can find a known branch quickly.
- Filters visibly explain what is hidden.
- `Needs me` is absent from primary UX unless real data proves it works.
- `Not loaded` is shown as lack of data, not as a scary failure.
- Offline host information is available but does not block scanning online
  sessions.

## 20. Open Questions

These are review questions, not implementation blockers:

1. Should `Needs me` be removed entirely from Dock until its underlying signal
   works, or kept as a secondary/debug-only filter?
2. Should `Newest` hide idle rows by default forever, or should the app remember
   the user's last `Idle` visibility setting?
3. Should explicit host/branch pins persist across launches?
4. Should host headers in Host mode sort by newest visible row or by manual host
   order?
5. Should `Not loaded` rows be visible by default, or should they be visible
   only when the user enables a filter?

## 21. Source Links

- Apple Human Interface Guidelines, Search Fields:
  <https://developer.apple.com/design/human-interface-guidelines/search-fields>
- Apple Human Interface Guidelines, Tab Bars:
  <https://developer.apple.com/design/human-interface-guidelines/tab-bars>
- Apple SwiftUI Search API:
  <https://developer.apple.com/documentation/swiftui/search>
- NN/g Information Foraging:
  <https://media.nngroup.com/media/articles/attachments/InformationForaging_SizeLetter.pdf>
- NN/g Social Media User Experience:
  <https://media.nngroup.com/media/reports/free/Social_Media_User_Experience.pdf>
- NN/g Designing for Young Adults, faceted navigation guidance:
  <https://media.nngroup.com/media/reports/free/Designing_for_Young_Adults_3rd_Edition.pdf>
- Baymard Product Lists and Filtering UX:
  <https://baymard.com/research/ecommerce-product-lists>
