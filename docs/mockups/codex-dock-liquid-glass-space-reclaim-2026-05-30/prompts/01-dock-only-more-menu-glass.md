Create a polished iPhone 17 portrait UI mockup for Codex Dock.
Use the attached `base-01-dock-more-menu.png` as the primary layout source.
This is a Liquid Glass refinement of the reduced-space Dock direction, not a
return to the old three-tab app shell.

Product direction:
- Dock is the only daily root surface.
- The old bottom `Dock` / `Archive` / `Relay` tab bar is gone.
- The reclaimed bottom space belongs to more visible session rows.
- Archive, Relay, and diagnostics live in a compact More menu.
- Filter state must stay compact and must not consume a tall header block.

Screen state:
- Main screen title: "Dock".
- Top-right glass controls: green status chip "Online 2/2" and a compact More
  button.
- The More menu is open from the top-right button.
- More menu items are exactly:
  "Archive cleanup", "Archived threads", "System health", "Relay settings".
- Full-width search field with placeholder
  "Search sessions, repo, branch, host".
- Compact glass lens row: "Newest", "Host", "Branch", and a filter icon.
- One-line filter summary: "Human sessions · active only · Newest activity".
- Show at least six visible session rows.

Visual treatment:
- Use iOS 26 Liquid Glass for the More button, menu surface, status chip, search
  field, and lens/filter controls.
- Keep session rows solid, readable, and dense. Do not make each row a glass
  card.
- Keep row rails and status chips from the base mock.
- No bottom tab bar. No floating bottom navigation. No marketing hero.
- No decorative gradient blobs. No nested cards.

Exact readable text to include:
- "Dock"
- "Online 2/2"
- "Archive cleanup"
- "Archived threads"
- "System health"
- "Relay settings"
- "Search sessions, repo, branch, host"
- "Newest"
- "Host"
- "Branch"
- "Human sessions · active only · Newest activity"
- "Active"
- "Idle"

Quality:
- Native iOS typography, crisp labels, believable spacing, no garbled text.
- The mock must clearly show that the reduced-space version fits more rows than
  the old tabbed version.
