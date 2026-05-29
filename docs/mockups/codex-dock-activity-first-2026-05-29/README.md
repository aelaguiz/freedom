# Codex Dock Activity-First Mockups

Date: 2026-05-29

These mockups use `gpt-image-2` through the local `$gpt-image` workflow. The goal is to explore an activity-first Dock UX for a very large multi-host session list, using the live iPhone 17 simulator state and prior Dock screenshots as image inputs.

## Source Inputs

- `inputs/current-dock.png` - fresh iPhone 17 simulator screenshot captured from `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
- `inputs/old-dock-normal-v2.png` - existing Dock screenshot from `docs/mockups/codex-dock-2026-05-27-v2/01-dock-normal.png`
- `inputs/old-hosts-v2.png` - existing host-management screenshot from `docs/mockups/codex-dock-2026-05-27-v2/06-hosts.png`
- `inputs/gw-controls-figma-ref.png` - reference material from `/Users/aelaguiz/workspace/lessons_studio/feat/feat/feat/gw_controls/docs/APP/REF/daily_puzzle_play_again_figma.png`

## Generated Mockups

- `outputs/01-newest-default.png` - default Dock view with newest sessions first, full-width search, host/branch as lenses, and no pinned host blocks.
- `outputs/02-host-lens.png` - host-grouped view where sessions are visually nested under each host without making host cards dominate the screen.
- `outputs/03-branch-lens.png` - branch-grouped view for finding work by branch across hosts.
- `outputs/04-loading-not-loaded.png` - honest loading state using `Not loaded`, never `Limited`, and no rate-limit implication.
- `outputs/05-filters.png` - compact filters surface for host, branch, status, repository, sort order, idle visibility, and archive visibility.

## Requirements Package

- `requirements/README.md` - requirements index, scope, verification gates, and links.
- `requirements/GLOBAL_REQUIREMENTS.md` - product-wide requirements extracted from the strategy doc and all mockups.
- `requirements/screens/01-newest-default.md` - requirements for `outputs/01-newest-default.png`.
- `requirements/screens/02-host-lens.md` - requirements for `outputs/02-host-lens.png`.
- `requirements/screens/03-branch-lens.md` - requirements for `outputs/03-branch-lens.png`.
- `requirements/screens/04-loading-not-loaded.md` - requirements for `outputs/04-loading-not-loaded.png`.
- `requirements/screens/05-filters.md` - requirements for `outputs/05-filters.png`.
- `requirements/screens/06-branch-search-results.md` - requirements for the branch-search result state in the strategy doc.
- `requirements/screens/07-host-offline-partial-failure.md` - requirements for host-local offline/error state in the strategy doc.
- `requirements/screens/08-filtered-empty.md` - requirements for empty results caused by search or filters.
- `requirements/screens/09-not-loaded-filter-results.md` - requirements for a not-loaded-only result state.
- `requirements/TRACEABILITY_MATRIX.md` - source-to-requirement map.

## Kill List

These are product directions we are explicitly no longer doing for this Dock UX:

- No primary `All`, `Needs me`, `Running`, or `Agents` tab row on the Dock first screen.
- No `Needs me` primary tab, top section, default ranking input, or workflow prediction until real data proves the signal works.
- No `Limited` label anywhere in the Dock UX.
- No rate-limit implication for missing thread detail; unknown content is `Not loaded`.
- No branch-grouped default open state; the default Dock lens is `Newest`.
- No pinned host summary cards above the main session list.
- No host status UI that is visually louder than session discovery.
- No raw endpoint strings such as `amir-m5.fairy-salmon.ts.net:4510` in the main scan path.
- No Dock row that requires remembering a host or branch header far above it.
- No cramped iPhone search field squeezed beside sort, status tabs, or idle controls.
- No final-looking zero-count filters during loading, such as `All 0`, `Needs me 0`, `Running 0`, or `Agents 0`.
- No global mystery error for one host failure; offline or failed state attaches to the affected host or scope.
- No automatic active-host, active-branch, active-project, or "important thread" prediction.
- No hidden idle, archived, not-loaded, host, branch, repo, source, or status filtering without visible active state.
- No app-level tab proliferation for Dock lenses; app-level tabs remain `Dock`, `Archive`, and `Relay`.
- No legacy `Branch`/`Newest` sort segmented control separate from the Dock lens model; `Newest`, `Host`, and `Branch` are lenses, while sort belongs in the filter/sort surface.
- No large primary Dock-header add-host affordance unless adding a host is the user's current task.
- No treating `Running` as primary navigation if the signal is frequently zero or unreliable.
- No making `Agents` a giant primary plumbing count; source/agent filtering belongs in filters.
- No burying branch lookup behind free-text search only.
- No implementation that optimizes for a tiny demo list while the real Dock list has thousands of sessions.
- No branch-search result state that hides the active query, result count, or host identity.
- No duplicated filter entry points with separate state; the header filter icon and `Filters` control must lead to the same filter model.
- No ambiguous host-header tap behavior where the same target sometimes filters and sometimes expands.
- No omission of source or agent scope from filters when the data exists.

## Product Notes

- The strongest direction is `01-newest-default.png`: it keeps newest activity as the default surface and turns host/branch into lenses.
- `02-host-lens.png` is useful when the user is mentally working by machine, but it should not be the default because it can hide newest cross-host activity.
- `03-branch-lens.png` is useful for branch recovery and cleanup, especially when the same branch exists across both hosts.
- `04-loading-not-loaded.png` makes unknown data explicit without implying rate limits or degraded access.
- `05-filters.png` keeps filtering explicit and mechanical: host, branch, status, repo, sort, idle, and archive controls, with no predictive workflow bucket.

## Generation Notes

- Model: `gpt-image-2`
- Quality: `medium`
- Size: `portrait`
- Reference approach: current app screenshot + older Dock screenshots + `gw_controls` visual reference + the first generated mockup for style continuity.
- Prompting followed the GPT2 materials under `/Users/aelaguiz/workspace/lessons_studio/feat/feat/feat/gw_controls/docs/APP/REF/GPT2`.
