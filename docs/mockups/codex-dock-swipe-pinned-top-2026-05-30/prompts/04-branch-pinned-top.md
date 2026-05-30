Create a polished iPhone 17 portrait UI mockup for Codex Dock using the
provided screenshots as visual anchors.

Option name: "Swipe pins, pinned always on top"

Screen state:
- Dock is open.
- "Branch" is selected.
- The same pinned section still appears at the top of Dock before branch groups.
- This proves pinned rows are universal at the top across Dock lenses.

Core layout:
- Header shows "Dock" and "Online 2/2".
- Search field is full width.
- Lens row shows "Newest", "Host", "Branch", and filter icon.
- "Branch" is selected in blue.
- Under scope summary, show compact "Pinned 2" section with:
  1. "ramp up on code base..." / "Amir-M5 · freedom · codex-dock-agents-tab-live-counts" / "now"
  2. "psmobile animation engine" / "Amir-M5 · psmobile · feat/anim_stages" / "now"
- Below pinned section, show branch group content:
  - "codex-dock-agents-tab-live-counts"
  - rows in that branch
  - "feat/anim_stages"
  - rows in that branch

Exact visible labels:
- "Dock"
- "Online 2/2"
- "Branch"
- "Pinned 2"
- "codex-dock-agents-tab-live-counts"
- "feat/anim_stages"

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- do not hide pinned rows inside branch groups
- do not make branch headers visually louder than pinned rows
