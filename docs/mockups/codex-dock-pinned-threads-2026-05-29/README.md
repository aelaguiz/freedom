# Codex Dock Pinned Threads Mockups

Date: 2026-05-29

These mockups explore a pinned/favorites feature for Codex Dock. The product
goal is a tiny user-owned watchlist: the user usually cares about 2-3 real
threads, wants to watch them while work continues, and then wants to unpin when
done.

## Strategy Docs

- `docs/CODEX_DOCK_PINNED_THREADS_UX_OPTIONS_2026-05-29.md`
- `docs/CODEX_DOCK_PINNED_THREADS_UX_WORKLOG_2026-05-29.md`

## Source Inputs

- `inputs/current-dock-live.png` - real iPhone 17 simulator screenshot captured
  from `DEF1631B-7125-43C6-BFA3-4423BF103C91`
- `inputs/current-filters-live.png` - real iPhone 17 simulator screenshot of
  the current Filters surface
- `inputs/prior-newest-default.png` - prior activity-first Dock mockup used as
  a style/product reference
- `inputs/prior-filters.png` - prior Filters mockup used as a style/product
  reference
- `inputs/gw-controls-figma-ref.png` - reference material from
  `/Users/aelaguiz/workspace/lessons_studio/feat/feat/feat/gw_controls/docs/APP/REF/daily_puzzle_play_again_figma.png`

## Generated Mockups

- `outputs/contact-sheet.png` - 2x2 review sheet for the four options.
- `outputs/01-pinned-watch-strip.png` - recommended option: compact `Pinned 3`
  watch strip above the newest feed, with pinned rows still marked in the feed.
- `outputs/02-pinned-lens.png` - alternative: `Pinned` as an internal Dock lens
  alongside `Newest`, `Host`, and `Branch`.
- `outputs/03-bottom-watch-accessory.png` - alternative: persistent bottom
  pinned accessory above the app tab bar.
- `outputs/04-pinned-filter-manage.png` - companion surface: Filters sheet with
  `Pinned only` and an inline manage/unpin list.

## Pin/Unpin Flow Mockups

- `outputs/flow-contact-sheet.png` - 2x2 review sheet for the pin/unpin flows.
- `outputs/flow-01-watch-strip-pin-unpin.png` - full Option A flow: pin from a
  row, watch in Dock, open pinned thread, unpin when done.
- `outputs/flow-02-pinned-lens-pin-unpin.png` - full Option B flow: pin from
  detail, use the `Pinned` lens, review pinned rows, unpin from the lens.
- `outputs/flow-03-bottom-watch-pin-unpin.png` - full Option D flow: pin from a
  row, show bottom watch accessory, expand it, unpin from the watch sheet.
- `outputs/flow-04-filter-manage-pin-unpin.png` - full Option C companion flow:
  open Filters, choose `Pinned only`, manage pinned rows, unpin and clear scope.

## Prompt Files

- `prompts/01-pinned-watch-strip.md`
- `prompts/02-pinned-lens.md`
- `prompts/03-bottom-watch-accessory.md`
- `prompts/04-pinned-filter-manage.md`
- `prompts/flows/01-watch-strip-pin-unpin-flow.md`
- `prompts/flows/02-pinned-lens-pin-unpin-flow.md`
- `prompts/flows/03-bottom-watch-pin-unpin-flow.md`
- `prompts/flows/04-filter-manage-pin-unpin-flow.md`

## Generation Notes

- Model: `gpt-image-2`
- Quality: `medium`
- Size: `portrait`
- Reference approach:
  - real current Dock screenshot
  - real current Filters screenshot
  - prior Codex Dock mockup outputs
  - `gw_controls` visual reference
  - `01-pinned-watch-strip.png` reused as a style anchor for later variants
- GPT2 reference docs used:
  - `/Users/aelaguiz/workspace/lessons_studio/feat/feat/feat/gw_controls/docs/APP/REF/GPT2/openai-gpt-image-2-prompting-guide.md`
  - `/Users/aelaguiz/workspace/lessons_studio/feat/feat/feat/gw_controls/docs/APP/REF/GPT2/gpt-image-2-character-scene-consistency-production-guide.md`

Flow mockup generation:

- Model: `gpt-image-2`
- Quality: `high`
- Size: `landscape`
- Reason for `high`: the flow boards have four small iPhone screens and dense
  labels, so text legibility matters more than draft cost.
- Reference approach:
  - same real screenshots as the concept mockups
  - matching concept mockup as the primary style anchor
  - `outputs/contact-sheet.png` as a whole-set consistency anchor
  - `gw-controls-figma-ref.png` as the external visual reference

## Product Read

Strongest direction:

- `01-pinned-watch-strip.png`

Why:

- It matches the actual user story: watch 2-3 chosen threads while `Newest`
  remains the default feed.
- It is explicit user state, not inference.
- It keeps pinning small enough for phone.
- It gives a visible place to unpin/manage.

Strongest full interaction flow:

- `outputs/flow-01-watch-strip-pin-unpin.png`

Why:

- It shows the entire expected loop without changing the Dock's default job:
  pin from row, keep watching in `Newest`, open the pinned thread, then unpin
  when done.

Useful supporting surface:

- `04-pinned-filter-manage.png`

Why:

- It makes `Pinned only` a real filter/scope for cleanup.
- It gives a place to unpin several items without crowding the Dock header.

Risky but interesting:

- `03-bottom-watch-accessory.png`

Why:

- It keeps pins visible while scrolling, but it competes with the bottom tab bar
  and covers list content.

Weakest primary direction:

- `02-pinned-lens.png`

Why:

- It is clean, but it makes the user switch away from `Newest` to watch pins.
  That makes it better as a management/review mode than as the main feature.

## Source Research

- Apple HIG: Lists and tables
  <https://developer.apple.com/design/human-interface-guidelines/lists-and-tables>
- Apple HIG: Searching
  <https://developer.apple.com/design/human-interface-guidelines/searching>
- Apple HIG: Search fields
  <https://developer.apple.com/design/human-interface-guidelines/search-fields>
- Apple HIG: Context menus
  <https://developer.apple.com/design/human-interface-guidelines/context-menus>
- Apple HIG: Tab bars
  <https://developer.apple.com/design/human-interface-guidelines/tab-bars>
- Nielsen Norman Group: 10 Usability Heuristics
  <https://www.nngroup.com/articles/ten-usability-heuristics/>
- Baymard: Applied filters overview
  <https://baymard.com/blog/how-to-design-applied-filters>
- Baymard: Ecommerce filter UI best practices
  <https://baymard.com/learn/ecommerce-filter-ui>
