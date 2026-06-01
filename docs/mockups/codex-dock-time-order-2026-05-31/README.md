# Codex Dock Time And Order UX Mockups

Date: 2026-05-31
Status: GPT-image mockup package for review.

Companion UX reference:
[Codex Dock Time And Order UX Reference](../../CODEX_DOCK_TIME_ORDER_UX_REFERENCE_2026-05-31.md)

Companion data reference:
[Codex App-Server Thread, Turn, Message, And Dock Data Reference](../../CODEX_APP_SERVER_THREAD_MESSAGE_TURN_DATA_REFERENCE_2026-05-31.md)

## Fast Review

Start here:

- `outputs/contact-sheet.png` - 2x2 scan sheet for all four generated mocks.

## Generated Mockups

- `outputs/01-dock-time-order-cards.png` - Dock cards as an activity inbox:
  explicit sort, pinned section, unread counts, first/newest unread age,
  waiting state, running duration, and top-right activity time.
- `outputs/02-thread-first-unread-timeline.png` - Thread detail as an
  oldest-to-newest timeline with date divider, first-unread divider, group
  timestamps, approval card, and visible order mode.
- `outputs/03-thread-new-messages-while-reading.png` - Thread detail while the
  user is reading older content and new messages arrive; the viewport stays in
  place and a floating `3 new messages · latest 2m ago` control appears.
- `outputs/04-exact-timestamp-inspector.png` - Exact timestamp detail sheet for
  an event, showing relative time, exact local time, timezone, arrival time,
  seen time, and context.

## Source Inputs

Fresh screenshots captured during this pass:

- `inputs/current-sim-thread-detail-2026-05-31.png` - fresh iPhone 17 simulator
  screenshot after `rtk make app SIM='iPhone 17'`.
- `inputs/current-sim-archive-2026-05-31.png` - fresh iPhone 17 simulator
  screenshot after returning from the thread detail screen.

Newest available Dock screenshot used:

- `inputs/current-dock-live-2026-05-30.png` - copied from
  `../codex-dock-liquid-glass-space-reclaim-2026-05-30/inputs/current-dock-live.png`.
  The fresh simulator opened into Thread/Archive state, so this remained the
  newest usable live Dock screenshot for Dock-card mocks.

Style anchors:

- `inputs/prior-dock-home-glass.png` - copied from the May 30 Liquid Glass
  package.
- `inputs/prior-thread-detail-composer-glass.png` - copied from the May 30
  Liquid Glass package.
- `inputs/gw-controls-figma-ref.png` - compact controls reference reused from
  prior mockup packages.

## Recovered GPT Workflow

The prior repo-local mockup workflow was checked through `$agent-history` and
the existing `docs/mockups/**` packages.

Evidence:

- Runtime: Codex.
- Project: `/Users/aelaguiz/workspace/codex-client`.
- Agent-history run:
  `/var/folders/cr/8sccc69d0rg1b8dsp42v7q900000gn/T/agent-history/20260531T142903Z-search-bfad3211`.
- Prior package:
  `../codex-dock-liquid-glass-2026-05-30/README.md`.
- Prior command shape:

```sh
rtk sh -c 'set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat <prompt>)" -f <output> -i <reference> --model gpt-image-2 --size portrait --quality medium'
```

This package keeps the same structure:

- prompts under `prompts/`
- generated images under `outputs/`
- reference screenshots under `inputs/`
- `gpt-image-2` through
  `/Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py`
- real app screenshots passed through repeated `-i` image arguments
- contact sheet generated with ImageMagick
- `.env` sourced only for `OPENAI_API_KEY`; secrets were not printed

This pass used `--quality high` because the mocks are text-heavy and meant for
design review.

## Representative Commands

Fresh simulator launch:

```sh
rtk make app SIM='iPhone 17'
```

Fresh thread screenshot equivalent:

```sh
rtk sh -c 'set -eu; out="docs/mockups/codex-dock-time-order-2026-05-31/inputs"; mkdir -p "$out"; udid="$(python3 scripts/sim.py resolve "iPhone 17")"; rtk xcrun simctl io "$udid" screenshot "$out/current-sim-thread-detail-2026-05-31.png"'
```

The archive screenshot was saved through Mobile MCP after tapping back from the
thread detail screen:

```text
mobile_save_screenshot DEF1631B-7125-43C6-BFA3-4423BF103C91 -> inputs/current-sim-archive-2026-05-31.png
```

Example GPT-image command used for this package shape:

```sh
rtk sh -c 'set -eu; set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat docs/mockups/codex-dock-time-order-2026-05-31/prompts/01-dock-time-order-cards.md)" -f docs/mockups/codex-dock-time-order-2026-05-31/outputs/01-dock-time-order-cards.png -i docs/mockups/codex-dock-time-order-2026-05-31/inputs/current-dock-live-2026-05-30.png -i docs/mockups/codex-dock-time-order-2026-05-31/inputs/prior-dock-home-glass.png -i docs/mockups/codex-dock-time-order-2026-05-31/inputs/gw-controls-figma-ref.png --model gpt-image-2 --size portrait --quality high'
```

Contact sheet:

```sh
rtk sh -c 'set -eu; d=docs/mockups/codex-dock-time-order-2026-05-31/outputs; tmp=/tmp/codex-client/time-order-contact-sheet; mkdir -p "$tmp"; rtk magick "$d/01-dock-time-order-cards.png" -resize 420x630 "$tmp/01.png"; rtk magick "$d/02-thread-first-unread-timeline.png" -resize 420x630 "$tmp/02.png"; rtk magick "$d/03-thread-new-messages-while-reading.png" -resize 420x630 "$tmp/03.png"; rtk magick "$d/04-exact-timestamp-inspector.png" -resize 420x630 "$tmp/04.png"; rtk magick "$tmp/01.png" "$tmp/02.png" +append "$tmp/row1.png"; rtk magick "$tmp/03.png" "$tmp/04.png" +append "$tmp/row2.png"; rtk magick "$tmp/row1.png" "$tmp/row2.png" -append "$d/contact-sheet.png"'
```

## Design Read

The strongest direction is the combined system shown across `01`, `02`, and
`03`:

- Dock behaves like an activity inbox.
- Thread detail reads oldest-to-newest.
- First unread is a physical place in the timeline.
- New live messages do not steal the viewport.
- Exact timestamps are available through an inspector instead of cluttering the
  default view.

## Known Mockup Limits

- Generated text is design-review quality, not implementation truth.
- Some labels may need hand correction before becoming a literal SwiftUI spec.
- `03-thread-new-messages-while-reading.png` includes a bottom tab bar because
  the model blended older Dock references with the current thread screenshot.
- The Dock-card mock uses the newest available live Dock screenshot from
  2026-05-30 as its primary Dock reference because the fresh 2026-05-31
  simulator state was on Thread/Archive screens.
- Treat these images as visual intent. The repo source of truth remains Swift
  code, `project.yml`, `Package.swift`, `Makefile`, and the written references.

## No-Code Verification

This pass changed only documentation and generated mockup assets. No Swift,
Node, Xcode, or relay tests were required for the mockup package.
