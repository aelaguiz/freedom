# Codex Dock Conversation, Time, And Order Mockups

Date: 2026-05-31
Status: GPT-image mockup package for review.

Companion UX reference:
[Codex Dock Conversation, Time, And Order UX Reference](../../CODEX_DOCK_TIME_ORDER_UX_REFERENCE_2026-05-31.md)

Companion data reference:
[Codex App-Server Thread, Turn, Message, And Dock Data Reference](../../CODEX_APP_SERVER_THREAD_MESSAGE_TURN_DATA_REFERENCE_2026-05-31.md)

Companion thread-state reference:
[Codex Dock Thread Types And States Reference](../../CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md)

## Fast Review

Start here:

- `outputs/contact-sheet.png` - 2x2 scan sheet for all four generated mocks.

## Generated Mockups

- `outputs/01-dock-conversation-time-order-cards.png` - Dock cards combining
  relative activity time, reply/work unread separation, hidden-work counts, and
  needs-me prioritization.
- `outputs/02-thread-conversation-default.png` - Thread detail defaulting to
  `Conversation`, with first-unread placement, oldest-to-newest order, hidden
  work summary, and a visible approval card.
- `outputs/03-thread-work-inspector.png` - The same thread with `Work`
  selected, per-turn work chips, and a command detail inspector that preserves
  thread context.
- `outputs/04-thread-activity-debug-modes.png` - Activity/Debug depth view with
  exact timestamps, event-type filters, readable event labels, and contained raw
  debug details.

## Source Inputs

Fresh or newest available app screenshots copied from
`../codex-dock-time-order-2026-05-31/inputs/`:

- `inputs/current-dock-live-2026-05-30.png`
- `inputs/current-sim-thread-detail-2026-05-31.png`
- `inputs/current-sim-archive-2026-05-31.png`

Style and product anchors copied from prior packages:

- `inputs/prior-dock-home-glass.png`
- `inputs/prior-thread-detail-composer-glass.png`
- `inputs/gw-controls-figma-ref.png`
- `inputs/prior-01-dock-time-order-cards.png`
- `inputs/prior-02-thread-first-unread-timeline.png`
- `inputs/prior-03-thread-new-messages-while-reading.png`
- `inputs/prior-04-exact-timestamp-inspector.png`

## Design Read

This package shows the combined target experience:

- Dock cards answer what changed, how long ago it changed, and whether it was a
  reply, work update, or needs-me request.
- Thread detail defaults to the actual conversation instead of a raw event
  stream.
- Hidden work is counted and disclosed through `Show work`, work chips, and
  deeper modes.
- `Conversation`, `Work`, `Files`, `Activity`, and `Debug` form a density
  ladder.
- Exact timestamps are available in inspectors and Activity/Debug without
  cluttering the default conversation.

## Representative Generation Command

```sh
rtk sh -c 'set -eu; set -a; [ -f .env ] && . ./.env; set +a; uv run /Users/aelaguiz/.codex/skills/gpt-image/scripts/generate.py -p "$(cat docs/mockups/codex-dock-conversation-time-order-2026-05-31/prompts/02-thread-conversation-default.md)" -f docs/mockups/codex-dock-conversation-time-order-2026-05-31/outputs/02-thread-conversation-default.png -i docs/mockups/codex-dock-conversation-time-order-2026-05-31/inputs/current-sim-thread-detail-2026-05-31.png -i docs/mockups/codex-dock-conversation-time-order-2026-05-31/inputs/prior-02-thread-first-unread-timeline.png -i docs/mockups/codex-dock-conversation-time-order-2026-05-31/inputs/prior-thread-detail-composer-glass.png --model gpt-image-2 --size portrait --quality high'
```

## Known Mockup Limits

- Generated text is design-review quality, not implementation truth.
- Treat the images as visual intent. The written references and Swift/relay
  source remain the product and implementation source of truth.
- The generated screens may simplify some labels or compress long chips to fit
  the phone screen.

## No-Code Verification

This pass changed documentation and generated mockup assets only. No Swift,
Node, Xcode, or relay tests are required for the mockup package.
