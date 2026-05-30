Create a polished iPhone 17 portrait UI mockup for Codex Dock using the
provided screenshots as visual anchors.

Option name: "Swipe pins, pinned always on top"

Screen state:
- Dock is open.
- "Host" is selected.
- The exact same pinned section still appears at the top of Dock before host
  groups.
- This proves pinned rows are universal at the top, no matter which Dock lens
  the user is using.

Core layout:
- Header shows "Dock" and green "Online 2/2".
- Search field is full width.
- Lens row shows "Newest", "Host", "Branch", and filter icon.
- "Host" is selected in blue.
- Under scope summary, show compact "Pinned 2" section with the same two pinned rows:
  1. "ramp up on code base..." / "Amir-M5 · freedom · codex-dock-agents-tab-live-counts" / "now"
  2. "psmobile animation engine" / "Amir-M5 · psmobile · feat/anim_stages" / "now"
- Below pinned section, show host group content:
  - "Amir-M5"
  - a few rows nested under the host
  - "Home"
  - at least one row under Home if space allows

Exact visible labels:
- "Dock"
- "Online 2/2"
- "Host"
- "Pinned 2"
- "Amir-M5"
- "Home"

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- do not hide the pinned section inside a host group
- do not duplicate host summary cards above pinned rows
