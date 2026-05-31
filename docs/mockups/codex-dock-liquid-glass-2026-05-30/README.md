# Codex Dock Liquid Glass Mockups

Date: 2026-05-30
Status: GPT-image mockup package for review.

## Fast Review

Start here:

- `outputs/contact-sheet.png` - 2x3 scan sheet for all six generated mocks.

## Intent

This package explores what Codex Dock could look like after a restrained iOS 26
Liquid Glass visual pass.

The key product rule is:

> Use Liquid Glass for navigation, controls, sheets, and the composer. Keep
> session rows, message cards, request cards, and long technical content solid
> and readable.

This is a review package only. It does not change Swift code, project settings,
or app behavior.

## Generated Mockups

- `outputs/01-dock-home-glass.png` - Dock home with glass control/search layer
  and solid session rows.
- `outputs/02-dock-search-filters-sheet.png` - Dock with an inset iOS 26
  Filters sheet.
- `outputs/03-session-detail-composer-glass.png` - Thread detail with glass
  toolbar/composer and solid event cards.
- `outputs/04-session-detail-dictation-request.png` - Thread detail with active
  voice dictation, request card, and composer.
- `outputs/05-system-health-relay-glass.png` - System Health sheet as the
  likely replacement shape for a permanent Relay tab.
- `outputs/06-archive-cleanup-glass.png` - Archive Cleanup sheet with preview,
  exclusions, host split, and destructive action.

## Source Inputs

- `inputs/current-dock-live.png` - current Dock screenshot from the earlier
  archive/relay space-reclaim package.
- `inputs/current-filters-live.png` - current Filters screenshot from the pinned
  threads package.
- `inputs/prior-activity-first-newest.png` - prior activity-first Dock direction.
- `inputs/prior-filters.png` - prior Filters direction.
- `inputs/legacy-session-detail-v2.png` - earlier Session detail visual anchor.
- `inputs/legacy-archive-v2.png` - earlier Archive visual anchor.
- `inputs/legacy-hosts-v2.png` - earlier Relay/Hosts visual anchor.
- `inputs/prior-system-health-sheet.png` - prior System Health direction.
- `inputs/gw-controls-figma-ref.png` - compact control styling reference.

## Recovered GPT Workflow

The old project-local mockup workflow was recovered through `$agent-history` and
confirmed against existing worklogs.

Evidence:

- Runtime: Codex.
- Project: `/Users/aelaguiz/workspace/codex-client`.
- Search window: 2026-05-23 through 2026-05-30 16:32 local time.
- Agent-history run:
  `/var/folders/cr/8sccc69d0rg1b8dsp42v7q900000gn/T/agent-history/20260530T213427Z-search-bfad3211`
- Prior session:
  `019e737d-6708-7982-9c03-228cd5685f5a`.
- Prior workflow file:
  `/Users/aelaguiz/.codex/sessions/2026/05/29/rollout-2026-05-29T06-27-38-019e737d-6708-7982-9c03-228cd5685f5a.jsonl`.

Recovered command shape:

```sh
rtk sh -c 'set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat <prompt>)" -f <output> -i <reference> --model gpt-image-2 --size portrait --quality medium'
```

The workflow rules carried forward:

- Save prompts under `prompts/`.
- Generate with `/Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py`.
- Use `--model gpt-image-2 --size portrait --quality medium` for exploratory
  single-screen UI mocks.
- Pass real and prior app screenshots through repeated `-i` arguments.
- Build a contact sheet with ImageMagick.
- Source `.env` only to read `OPENAI_API_KEY`; do not print secrets.

## Apple Guidance Used

Apple-primary sources checked on 2026-05-30:

- Adopting Liquid Glass:
  <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass>
- Liquid Glass technology overview:
  <https://developer.apple.com/documentation/technologyoverviews/liquid-glass>
- Human Interface Guidelines:
  <https://developer.apple.com/design/human-interface-guidelines/>
- Materials:
  <https://developer.apple.com/design/human-interface-guidelines/materials>
- Tab bars:
  <https://developer.apple.com/design/human-interface-guidelines/tab-bars/>
- Toolbars:
  <https://developer.apple.com/design/human-interface-guidelines/toolbars>
- Searching:
  <https://developer.apple.com/design/human-interface-guidelines/searching>
- Search fields:
  <https://developer.apple.com/design/human-interface-guidelines/search-fields>
- WWDC25, "Meet Liquid Glass":
  <https://developer.apple.com/videos/play/wwdc2025/219/>
- WWDC25, "Build a SwiftUI app with the new design":
  <https://developer.apple.com/videos/play/wwdc2025/323/>

Local repo reference used:

- `docs/CODEX_DOCK_IOS_26_DESIGN_REFERENCES_2026-05-28.md`

## Design Read

Strongest reusable direction:

- `01-dock-home-glass.png`

Why:

- It keeps Dock recognizable and dense.
- It makes controls feel current without turning every content row into glass.
- It preserves the scan path: title, online state, search, lenses, filter chips,
  session rows.

Strongest interaction direction:

- `04-session-detail-dictation-request.png`

Why:

- It shows where custom glass adds real value: active voice state and composer.
- It keeps approvals and command text readable.
- It gives the detail screen a modern feel without becoming a generic chat UI.

Best maintenance direction:

- `05-system-health-relay-glass.png` and `06-archive-cleanup-glass.png`

Why:

- They support the existing archive/relay space-reclaim idea.
- They make secondary jobs reachable as focused sheets.
- They avoid spending permanent first-screen tab space on low-frequency work.

## Known Mockup Limits

- Generated text is design-review quality, not implementation truth.
- Some bottom-tab labels reflect older references, such as `Hosts` instead of
  the current `Relay`.
- `05-system-health-relay-glass.png` includes one lower preview label that reads
  like an illustrative settings line, not a protocol recommendation.
- Treat these mocks as visual intent. The repo source of truth remains Swift
  code, `project.yml`, `Package.swift`, `Makefile`, and the written requirements.

## No-Code Verification

This pass changed only documentation and generated mockup assets. No app build
or Swift/Node test was required.
