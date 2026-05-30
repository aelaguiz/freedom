Create a polished iPhone 17 portrait UI mockup for Codex Dock using the
provided screenshots as visual references.

Goal: show the "Pinned as a Dock lens" alternative. This is not the primary
recommendation, but it should be a credible option for review.

Keep from the current app:
- large title "Dock"
- green connectivity chip "Online 2/2"
- full-width search field
- light native iOS style
- bottom tabs "Dock", "Archive", "Relay"
- short host names such as "Amir-M5" and "Home"

Main layout:
- The lens row contains "Newest", "Pinned", "Host", and "Branch"; "Pinned" is selected.
- Keep a compact filter icon button if there is room, or place it as a toolbar
  icon near the lens row.
- Below the lens row, show "Pinned 3 · sorted by newest activity".
- Show only pinned rows in this view.
- Use dense rows, not large cards.
- Each row has a filled pin icon, title, host, repo, branch, live/loaded state,
  last activity time, and chevron.
- Use plausible exact row text:
  1. "ramp up on code base..." / "Amir-M5 · freedom · codex-dock-agents-tab-live-counts" / "now"
  2. "psmobile animation engine" / "Amir-M5 · psmobile · feat/anim_stages" / "now"
  3. "relay aggregator architecture" / "Home · codex-client · dock-relay-aggregator" / "2m"
- Include a small empty-state hint at the bottom of the list area, not prominent:
  "Pin a thread from any row or detail screen."

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- no fourth app-level tab
- no giant pinned header

Visual quality:
- crisp native iOS UI
- clear selected lens state
- enough whitespace to scan, but still dense for a large list product
