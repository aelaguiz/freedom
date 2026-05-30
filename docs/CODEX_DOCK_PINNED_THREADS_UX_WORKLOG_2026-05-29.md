---
title: "Codex Dock - Pinned Threads UX Worklog"
date: 2026-05-29
status: active
owners: [aelaguiz]
reviewers: [Codex]
doc_type: worklog
related:
  - docs/CODEX_DOCK_PINNED_THREADS_UX_OPTIONS_2026-05-29.md
  - docs/mockups/codex-dock-pinned-threads-2026-05-29/README.md
  - docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md
  - docs/mockups/codex-dock-activity-first-2026-05-29/README.md
---

# Codex Dock - Pinned Threads UX Worklog

## Goal

Design a favorites/pinned threads feature for Codex Dock from first principles.
The user goal is narrow and practical: most of the time only 2-3 real threads
matter, and the user wants to watch those threads over time, then unpin them
when done.

Deliverables for this pass:

- online UX research
- a new UX options doc in `docs/`
- at least a few distinct product ideas
- ASCII wireframes
- real current app screenshots as GPT Image 2 inputs
- GPT Image 2 mockups saved for review

## 2026-05-29 Progress

### Repo and skill setup

- Read repo instructions from `AGENTS.md`, `README.md`, and the Makefile
  command surface.
- Read `$agent-history`:
  `/Users/aelaguiz/.agents/skills/agent-history/SKILL.md`
- Read `$gpt-image`:
  `/Users/aelaguiz/.codex/skills/gpt-image/SKILL.md`
- Read `$gpt-image` UI/craft references:
  - `/Users/aelaguiz/.codex/skills/gpt-image/references/gallery.md`
  - `/Users/aelaguiz/.codex/skills/gpt-image/references/gallery-ui-ux-mockups.md`
  - `/Users/aelaguiz/.codex/skills/gpt-image/references/craft.md`
- Read the prior mockup index:
  `docs/mockups/codex-dock-activity-first-2026-05-29/README.md`

### Agent-history findings

Used `$agent-history` with current runtime, current project, and today
(`2026-05-29`) as the time window.

Relevant evidence:

- Search run:
  `/tmp/codex-client/agent-history-pinned-c/20260529T234940Z-search-bfad3211`
- Prior session:
  `019e737d-6708-7982-9c03-228cd5685f5a`
- Prior workflow evidence:
  `/Users/aelaguiz/.codex/sessions/2026/05/29/rollout-2026-05-29T06-27-38-019e737d-6708-7982-9c03-228cd5685f5a.jsonl`
- The earlier Dock mockup workflow:
  - read `gw_controls/docs/APP/REF/GPT2`
  - copied old Dock screenshots and `daily_puzzle_play_again_figma.png`
  - captured a fresh iPhone 17 simulator screenshot
  - used `/Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py`
  - used `--model gpt-image-2 --size portrait --quality medium`
  - passed multiple reference images with repeated `-i`

Confidence: exact for command/tool evidence and generated artifact paths.

### GPT2 reference lookup

Confirmed the repo-local GPT2 reference path from the prior workflow:

- `/Users/aelaguiz/workspace/lessons_studio/feat/feat/feat/gw_controls/docs/APP/REF/GPT2/openai-gpt-image-2-prompting-guide.md`
- `/Users/aelaguiz/workspace/lessons_studio/feat/feat/feat/gw_controls/docs/APP/REF/GPT2/gpt-image-2-character-scene-consistency-production-guide.md`

Important prompt guidance to carry forward:

- use real screenshots as anchors
- separate what must stay fixed from what should change
- keep UI prompts specific, with exact labels and layout zones
- use medium quality for exploratory UI mockups
- do not rely on seeds or hidden style knobs for consistency

### Online UX research

Sources opened or searched:

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
- Apple HIG: Toolbars
  <https://developer.apple.com/design/human-interface-guidelines/toolbars>
- Nielsen Norman Group: 10 Usability Heuristics
  <https://www.nngroup.com/articles/ten-usability-heuristics/>
- Baymard: Applied filters overview
  <https://baymard.com/blog/how-to-design-applied-filters>
- Baymard: Ecommerce filter UI best practices
  <https://baymard.com/learn/ecommerce-filter-ui>

Research takeaways for pinned threads:

- A pin should be user-owned state, not an inferred status bucket.
- In a huge list, visible scope matters. If a pin/filter is active, show it as
  an explicit removable chip or clearly labeled section.
- The pinned area must be capped because every extra row above newest activity
  pushes the actual feed down.
- Pin/unpin needs at least two entry points: a visible affordance on the row or
  detail screen, plus a contextual shortcut such as long-press.
- Context menus are useful for row-local actions, but Apple warns that hidden
  context menus are not enough by themselves.
- Search should remain broad by default and can use scopes/tokens to refine.
- Top-level tabs should stay stable and few; pins should not become a fourth
  app-level tab unless the product meaning is truly top-level.
- User control and freedom matter: unpin must be obvious, reversible, and not a
  deep management chore.

### Current iPhone 17 simulator evidence

Device selected from Mobile MCP:

- Simulator name:
  `feat_remount-disposal-lifecycle-post-audit - iPhone 17`
- UDID:
  `DEF1631B-7125-43C6-BFA3-4423BF103C91`
- App bundle:
  `com.aelaguiz.CodexDockApp`

Launch command:

```bash
rtk make app SIM=DEF1631B-7125-43C6-BFA3-4423BF103C91
```

Screenshot commands:

```bash
rtk xcrun simctl io DEF1631B-7125-43C6-BFA3-4423BF103C91 screenshot docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-dock-live.png
rtk xcrun simctl io DEF1631B-7125-43C6-BFA3-4423BF103C91 screenshot docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-filters-live.png
```

Captured inputs:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-dock-live.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/current-filters-live.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/prior-newest-default.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/prior-filters.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/inputs/gw-controls-figma-ref.png`

Current screen observations:

- Dock is `Online 2/2`.
- Dock lens defaults to `Newest`.
- Search is full-width.
- Filters are a large round icon button to the right of the lens row.
- Active summary reads:
  `400 shown · Hosts: Any · Branches: Any · Status: Any · Repo: Any · Source: Any · Idle hidden`
- Rows now show short host names such as `Amir-M5`, repository, and branch.
- The first visible thread is the active Codex thread, which proves this is a
  "watch ongoing work" problem, not just a static archive problem.
- The filters surface exposes host, branch, and status well, but the long
  branch grid dominates the first viewport.

### Product position emerging

Pinned threads should mean:

> I chose these sessions as a tiny watchlist. Keep them easy to see until I say
> they are done.

Pinned threads should not mean:

- important according to Codex
- needs me
- running
- not loaded
- a rate limit state
- a top-level app mode
- a permanent favorite folder full of old threads

### Next actions

- Complete final artifact audit and report paths.

### UX options doc

Created:

- `docs/CODEX_DOCK_PINNED_THREADS_UX_OPTIONS_2026-05-29.md`

The doc includes:

- first-principles product definition
- online research summary
- current iPhone 17 simulator observations
- five UX options
- ASCII wireframes
- recommended MVP shape
- mockup generation plan

### GPT Image 2 generation

Created prompt files:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/01-pinned-watch-strip.md`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/02-pinned-lens.md`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/03-bottom-watch-accessory.md`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/04-pinned-filter-manage.md`

Generated with:

```bash
OPENAI_API_KEY="$(awk -F= '$1=="OPENAI_API_KEY"{sub(/^[^=]*=/,""); print; exit}' .env)" uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py --model gpt-image-2 --size portrait --quality medium ...
```

Generated outputs:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/01-pinned-watch-strip.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/02-pinned-lens.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/03-bottom-watch-accessory.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/04-pinned-filter-manage.png`

Visual review:

- `01-pinned-watch-strip.png` is the strongest primary direction.
- `02-pinned-lens.png` is coherent but weaker as a default because it hides the
  newest feed.
- `03-bottom-watch-accessory.png` clearly shows the always-visible monitoring
  benefit and the bottom-space cost.
- `04-pinned-filter-manage.png` is useful as the management/filter companion.

Created mockup index:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/README.md`

## 2026-05-29 Follow-up: Pin/Unpin Flow Mockups

User asked for the full pin UX to go with the concept mockups: how to pin,
where the pinned state appears, and how to unpin for each variation.

Created flow prompt files:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/flows/01-watch-strip-pin-unpin-flow.md`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/flows/02-pinned-lens-pin-unpin-flow.md`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/flows/03-bottom-watch-pin-unpin-flow.md`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/prompts/flows/04-filter-manage-pin-unpin-flow.md`

Generated with the same GPT Image 2 path, but `--quality high` and
`--size landscape` because these are dense multi-screen flow boards:

```bash
OPENAI_API_KEY="$(awk -F= '$1=="OPENAI_API_KEY"{sub(/^[^=]*=/,""); print; exit}' .env)" uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py --model gpt-image-2 --size landscape --quality high ...
```

Generated flow outputs:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/flow-01-watch-strip-pin-unpin.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/flow-02-pinned-lens-pin-unpin.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/flow-03-bottom-watch-pin-unpin.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/flow-04-filter-manage-pin-unpin.png`
- `docs/mockups/codex-dock-pinned-threads-2026-05-29/outputs/flow-contact-sheet.png`

Visual review:

- `flow-01-watch-strip-pin-unpin.png` clearly shows pin from row, pinned strip,
  opening the pinned thread, and unpin feedback.
- `flow-02-pinned-lens-pin-unpin.png` clearly shows pin from detail, the
  `Pinned` lens appearing, review mode, and row unpin.
- `flow-03-bottom-watch-pin-unpin.png` clearly shows row pinning, bottom
  accessory appearance, expanded watch sheet, and unpin from the sheet.
- `flow-04-filter-manage-pin-unpin.png` clearly shows opening Filters, selecting
  `Pinned only`, managing pinned rows, and unpinning/clearing scope.

Updated:

- `docs/mockups/codex-dock-pinned-threads-2026-05-29/README.md`
