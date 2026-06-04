# Codex Dock Thread State UX Mockups

Date: 2026-06-04
Status: focused exact-status mockup package for Dock and Thread Detail.

Companion UX reference:
[Codex Dock Thread State UX Reference](../../CODEX_DOCK_THREAD_STATE_UX_REFERENCE_2026-06-04.md)

Companion technical reference:
[Codex Dock Thread Types And States Reference](../../CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md)

## Fast Review

Start here:

- `outputs/status-focused-contact-sheet.png` - 2x2 scan sheet for the focused
  Dock and Thread Detail mockups.

## Focused Mockups

- `outputs/07-status-dock-overview.png` - Dock overview using the existing list
  shape with row-level status badges: `Needs approval`, `Needs answer`,
  `Codex is working`, `Error`, and a quiet ready row with no badge.
- `outputs/08-thread-detail-working.png` - Thread Detail while Codex is active:
  header badge `Codex is working`, no duplicate status banner, and normal
  thread content below.
- `outputs/09-thread-detail-ready.png` - Thread Detail after Codex finishes the
  turn: header badge `Your turn · Ready`, no duplicate ready banner, final
  agent message, and composer as the primary next action.
- `outputs/10-thread-detail-error.png` - Thread Detail with raw thread error:
  a small `Error` badge, no error banner, last useful content preserved, and raw
  state detail visible.

Each PNG has a matching exact-text SVG source in `outputs/`.

## Source Inputs

Fresh simulator screenshots captured on 2026-06-04:

- `inputs/current-sim-latest-2026-06-04.png`
- `inputs/current-sim-thread-detail-2026-06-04.png`
- `inputs/current-sim-filters-2026-06-04.png`

Style and product anchors copied from prior packages:

- `inputs/gw-controls-figma-ref.png`
- `inputs/prior-conversation-time-order-contact-sheet.png`
- `inputs/prior-pinned-watch-contact-sheet.png`

The refreshed focused mocks are deterministic SVG/PNG renders from:

- `sources/render-status-mockups.mjs`

This replaced earlier prompt-generated assets because the status labels are the
product decision here, so exact text is more important than generative polish.

## Design Read

This package shows the recommended status UX:

- The Dock and Thread Detail expose routine turn status as `Codex is working`
  or `Your turn` without adding a new Dock section in this first slice.
- The common full-permissions completion path is explicit:
  `Your turn · Ready`.
- Required-action Dock rows use coarse badges available from the current Dock
  card status contract: `Needs answer` or `Needs approval`.
- Quiet ready rows do not get loud Dock badges.
- `Codex is working` is active but calm. It may show latest-activity evidence,
  but not fake thread states such as `Running tests`.
- Raw thread error is a small local badge: `Error`.
- Thread Detail uses the header badge as the status surface. It does not repeat
  `Codex is working`, `Your turn · Ready`, or `Error` in a second banner below.
- Other health/status surfaces are intentionally absent from this focused pass.
- There is no top-level catch-all error group, tab, or global header badge in
  this focused pass.
- Exact request subtype copy such as `Review command`, `Review files`, or
  `Grant permission` remains a Thread Detail request-card concern, not a Dock
  row badge in this implementation slice.

## Render Command

```sh
rtk node docs/mockups/codex-dock-thread-state-ux-2026-06-04/sources/render-status-mockups.mjs
```

## PNG And Contact Sheet Command

Use `sips` for SVG-to-PNG conversion on this machine. ImageMagick can resize
the resulting raster files, but its SVG text renderer cannot find fonts here.

```sh
rtk sh -c 'set -eu; d=docs/mockups/codex-dock-thread-state-ux-2026-06-04/outputs; for n in 07-status-dock-overview 08-thread-detail-working 09-thread-detail-ready 10-thread-detail-error; do sips -s format png "$d/$n.svg" --out "$d/$n.png" >/tmp/codex-client/sips-$n.out; done; tmp=/tmp/codex-client/thread-status-focused-contact-sheet; rm -rf "$tmp"; mkdir -p "$tmp"; for n in 07-status-dock-overview 08-thread-detail-working 09-thread-detail-ready 10-thread-detail-error; do rtk magick "$d/$n.png" -resize 420x630 "$tmp/$n.png"; done; rtk magick "$tmp/07-status-dock-overview.png" "$tmp/08-thread-detail-working.png" +append "$tmp/row1.png"; rtk magick "$tmp/09-thread-detail-ready.png" "$tmp/10-thread-detail-error.png" +append "$tmp/row2.png"; rtk magick "$tmp/row1.png" "$tmp/row2.png" -append "$d/status-focused-contact-sheet.png"'
```

## Known Mockup Limits

- These are design-review artifacts, not implementation truth.
- The written references and source code remain the product and implementation
  source of truth.
- The screens simplify iconography and some metadata to keep the status model
  readable.

## No-Code Verification

This pass changed documentation, deterministic mockup sources, and generated
mockup assets only. No Swift, Node relay, Xcode, or app-server tests are
required for the mockup package.
