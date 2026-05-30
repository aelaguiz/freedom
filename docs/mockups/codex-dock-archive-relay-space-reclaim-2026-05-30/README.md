# Codex Dock Archive/Relay Space Reclaim Mockups

Date: 2026-05-30
Status: GPT-image mockup package for review.

## Intent

These mockups explore how Codex Dock can reclaim the vertical space currently
spent on the bottom `Dock` / `Archive` / `Relay` tab bar while keeping archive
cleanup, archived-thread recovery, relay settings, and connectivity diagnostics
reachable.

The product brief is:

`docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_UX_WORKLOG_2026-05-30.md`

## Inputs

- `inputs/current-dock-live.png`: actual current Dock screenshot with bottom
  `Dock` / `Archive` / `Relay` tabs.
- `inputs/legacy-archive.png`: older archive mockup reference.
- `inputs/legacy-hosts.png`: older hosts/relay mockup reference.
- `inputs/prior-activity-first-newest.png`: prior activity-first Dock visual
  direction.
- `inputs/gw-controls-figma-ref.png`: compact control styling reference.

## Generated Outputs

- `outputs/01-dock-more-menu.png`: Dock as the only daily surface, with
  maintenance actions in a compact More menu.
- `outputs/02-system-health-sheet.png`: connectivity chip opens a plain-English
  System Health sheet.
- `outputs/03-archive-cleanup-sheet.png`: age-based bulk archive cleanup with
  preview, exclusions, and safety.
- `outputs/04-archived-threads-sheet.png`: archived-thread browser as a sheet,
  not a root tab.
- `outputs/contact-sheet.png`: four-option comparison board.

## Generation Notes

- Model: `gpt-image-2`
- Size: `portrait`
- Quality: `medium`
- Generated on 2026-05-30.
- Keep the current Codex Dock visual language: iOS 26-style glass, compact
  controls, dense readable session rows, no marketing page.
- Do not draw a bottom root tab bar in the new options unless the prompt
  explicitly asks for it as a before/after reference.

## Commands

The generation command sources `.env` only to read `OPENAI_API_KEY`; it does not
print secrets.

```sh
rtk sh -c 'set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/prompts/01-dock-more-menu.md)" -f docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/01-dock-more-menu.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/current-dock-live.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/prior-activity-first-newest.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/gw-controls-figma-ref.png --model gpt-image-2 --size portrait --quality medium'
```

```sh
rtk sh -c 'set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/prompts/02-system-health-sheet.md)" -f docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/02-system-health-sheet.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/current-dock-live.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/legacy-hosts.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/gw-controls-figma-ref.png --model gpt-image-2 --size portrait --quality medium'
```

```sh
rtk sh -c 'set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/prompts/03-archive-cleanup-sheet.md)" -f docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/03-archive-cleanup-sheet.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/current-dock-live.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/legacy-archive.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/gw-controls-figma-ref.png --model gpt-image-2 --size portrait --quality medium'
```

```sh
rtk sh -c 'set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/prompts/04-archived-threads-sheet.md)" -f docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/04-archived-threads-sheet.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/current-dock-live.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/legacy-archive.png -i docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/gw-controls-figma-ref.png --model gpt-image-2 --size portrait --quality medium'
```

```sh
rtk magick '(' docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/01-dock-more-menu.png -resize 360x540 ')' '(' docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/02-system-health-sheet.png -resize 360x540 ')' '(' docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/03-archive-cleanup-sheet.png -resize 360x540 ')' '(' docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/04-archived-threads-sheet.png -resize 360x540 ')' -background white -gravity center +append docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/contact-sheet.png
```
