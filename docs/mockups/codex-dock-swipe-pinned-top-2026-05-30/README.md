# Codex Dock Swipe Pins, Pinned Always On Top Mockups

Date: 2026-05-30

This package explores the option Amir asked for: swipe a thread row to pin or
unpin it, then show pinned threads at the top of the Dock no matter which Dock
lens is active.

## Product Shape

The behavior shown here is intentionally simple:

- A normal thread row can be swiped left to reveal a blue `Pin` action.
- Pinned rows appear in a small `Pinned` section directly under search, lenses,
  and filter summary.
- The same `Pinned` section remains visible on `Newest`, `Host`, and `Branch`.
- A pinned row can be swiped left to reveal a red `Unpin` action.
- The main lens content continues below pinned rows, so host and branch browsing
  still work without making pinned items feel tied to a specific group.

## Outputs

- `UX_SPEC.md` - exhaustive UX spec for the swipe-to-pin, persistent pinned-top
  behavior.
- `outputs/contact-sheet.png` - scan sheet of all generated mockups.
- `outputs/01-swipe-to-pin-newest.png` - `Newest` lens with a thread row swiped
  left and a blue `Pin` action exposed.
- `outputs/02-newest-pinned-top.png` - `Newest` lens after pinning, with pinned
  rows at the top.
- `outputs/03-host-pinned-top.png` - `Host` lens with the same pinned rows still
  at the top and host groups underneath.
- `outputs/04-branch-pinned-top.png` - `Branch` lens with the same pinned rows
  still at the top and branch groups underneath.
- `outputs/05-swipe-to-unpin.png` - pinned row swiped left, exposing `Unpin`.
- `outputs/06-flow-board.png` - landscape flow board showing the interaction
  sequence.

## Inputs

The mockups were grounded in current and prior Codex Dock screenshots:

- `inputs/current-dock-live.png`
- `inputs/current-filters-live.png`
- `inputs/prior-pinned-watch-strip.png`
- `inputs/prior-watch-strip-flow.png`
- `inputs/gw-controls-figma-ref.png`

## Generation

Generated with GPT Image 2 via the local `$gpt-image` skill.

Portrait states used:

```bash
python3 /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py --model gpt-image-2 --size portrait --quality medium
```

The landscape flow board used:

```bash
python3 /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py --model gpt-image-2 --size landscape --quality high
```

Prompt files are stored in `prompts/`.

## Read

This option treats pinning as a Dock-level affordance, not as a filter or a
host-specific grouping. The pinned section is small, persistent, and removable
with the same direct manipulation gesture that created it. That matches the
request intent: swipe to pin or unpin, then keep pinned rows at the top of Dock
no matter which Dock lens is active.
