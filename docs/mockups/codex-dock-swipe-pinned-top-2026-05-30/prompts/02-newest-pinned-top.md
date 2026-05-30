Create a polished iPhone 17 portrait UI mockup for Codex Dock using the
provided screenshots as visual anchors.

Option name: "Swipe pins, pinned always on top"

Screen state:
- Dock is open.
- "Newest" is selected.
- The same pinned section appears at the top of Dock.
- This is the default place pinned threads live after a swipe pin.

Core layout:
- Header shows "Dock" and "Online 2/2".
- Search field is full width.
- Lens row shows "Newest", "Host", "Branch", and the filter icon button.
- Under the scope summary, show a compact section titled "Pinned 2".
- "Pinned 2" contains two dense rows:
  1. "ramp up on code base..." / "Amir-M5 · freedom · codex-dock-agents-tab-live-counts" / "now"
  2. "psmobile animation engine" / "Amir-M5 · psmobile · feat/anim_stages" / "now"
- Below the pinned section, show the "Newest" feed continuing normally.
- Pinned rows may also appear in the feed with a small filled pin marker.

Interaction cue:
- Include a subtle hint that the pinned row can be swiped to unpin, but do not
  show a large instruction paragraph.

Exact visible labels:
- "Dock"
- "Online 2/2"
- "Newest"
- "Pinned 2"
- "Manage"
- "400 shown"

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- no giant pinned cards
- no app-level pinned tab
