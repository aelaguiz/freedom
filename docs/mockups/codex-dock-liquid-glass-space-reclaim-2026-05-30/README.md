# Codex Dock Liquid Glass Space-Reclaim Mockups

Date: 2026-05-30
Status: corrected GPT-image mockup package for review.

## Fast Review

Start here:

- `outputs/contact-sheet.png` - 5-mock scan sheet for the corrected
  reduced-space Liquid Glass direction.

## Correction

This package supersedes the earlier broad glass package for this specific design
question:

- Earlier broad package:
  `docs/mockups/codex-dock-liquid-glass-2026-05-30/`
- Correct base package for this pass:
  `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/`

The important correction is that the active design direction is the
space-reclaim version:

- The bottom `Dock` / `Archive` / `Relay` tab bar is gone.
- `Dock` is the only daily root surface.
- `Archive cleanup`, `Archived threads`, `System health`, and `Relay settings`
  live behind More or focused sheets.
- Filter state stays compact so session rows get the reclaimed space.

## Generated Outputs

- `outputs/01-dock-only-more-menu-glass.png` - Dock-only root with More menu,
  no bottom tab bar, compact filter summary, and more visible rows.
- `outputs/02-dock-compact-filter-sheet-glass.png` - compact Filters sheet
  over the Dock-only root.
- `outputs/03-system-health-space-reclaim-glass.png` - System Health sheet
  replacing the old need for a permanent Relay tab.
- `outputs/04-archive-cleanup-space-reclaim-glass.png` - Archive Cleanup sheet
  with age rule, exclusions, preview, and restore path.
- `outputs/05-archived-threads-space-reclaim-glass.png` - Archived Threads
  sheet with search, compact filters, selection, and restore.

## Source Inputs

Primary reduced-space references:

- `inputs/base-01-dock-more-menu.png` copied from
  `../codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/01-dock-more-menu.png`
- `inputs/base-02-system-health-sheet.png` copied from
  `../codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/02-system-health-sheet.png`
- `inputs/base-03-archive-cleanup-sheet.png` copied from
  `../codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/03-archive-cleanup-sheet.png`
- `inputs/base-04-archived-threads-sheet.png` copied from
  `../codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/04-archived-threads-sheet.png`
- `inputs/base-contact-sheet.png` copied from
  `../codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/contact-sheet.png`

Supporting references:

- `inputs/current-dock-live.png`
- `inputs/current-filters-live.png`
- `inputs/gw-controls-figma-ref.png`

## Generation Notes

- Model: `gpt-image-2`
- Size: `portrait`
- Quality: `medium`
- Workflow: local `$gpt-image` CLI, same as the earlier project mockup packs.
- Generated on 2026-05-30.

Command shape:

```sh
rtk sh -c 'set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat <prompt>)" -f <output> -i <base-mock> --model gpt-image-2 --size portrait --quality medium'
```

The command sources `.env` only to read `OPENAI_API_KEY`; it does not print
secrets.

## Product Read

Strongest corrected direction:

- `outputs/01-dock-only-more-menu-glass.png`

Why:

- It keeps the reduced-space product decision visible.
- It shows six-plus rows by removing the bottom tab bar.
- It keeps filtering as a compact scope line instead of a tall control block.
- It keeps maintenance actions reachable without spending permanent screen
  space.

Best companion surfaces:

- `outputs/03-system-health-space-reclaim-glass.png`
- `outputs/04-archive-cleanup-space-reclaim-glass.png`
- `outputs/05-archived-threads-space-reclaim-glass.png`

Why:

- They keep Relay and Archive as focused tasks.
- They preserve the Dock-first daily experience.
- They use Liquid Glass where it helps: sheets, status chips, segmented
  controls, action bars, and transient controls.

## Known Mockup Limits

- These are generated design mocks, not implementation truth.
- Some fine text may be approximate.
- Treat the mockups as visual intent. The source of truth for implementation is
  still the Swift code, `project.yml`, `Package.swift`, `Makefile`, and the
  archive/relay space-reclaim requirements and architecture docs.

## No-Code Verification

This pass changed only documentation and generated mockup assets. No Swift,
Node, XcodeGen, simulator, or app tests were required.
