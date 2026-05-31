Create a polished iPhone 17 portrait UI mockup for Codex Dock showing the
reduced-space Dock with a compact Filters sheet open.
Use the attached `base-01-dock-more-menu.png` as the primary layout source and
`current-filters-live.png` only as reference for the available filter concepts.

Product direction:
- Dock remains the only daily root surface.
- The old bottom `Dock` / `Archive` / `Relay` tab bar is gone.
- Filters are a focused sheet, not permanent header real estate.
- Active filter state outside the sheet is one compact line or compact chips.

Screen state:
- Background Dock screen still has no bottom tab bar.
- Background header shows "Dock", "Online 2/2", search, "Newest", "Host",
  "Branch", and filter icon.
- Present an inset iOS 26 Liquid Glass sheet from the bottom.
- Sheet title: "Filters".
- Sheet result count: "400 shown".
- Compact filter sections:
  "Host", "Branch", "Status", "Source", "Idle".
- Use compact controls rather than tall grids.
- Bottom actions: "Reset" and "Apply".

Exact readable text to include:
- "Dock"
- "Online 2/2"
- "Filters"
- "400 shown"
- "Host"
- "Any host"
- "Amir-M5"
- "Home"
- "Branch"
- "feat/remount"
- "main"
- "Status"
- "Active"
- "Idle"
- "Not loaded"
- "Source"
- "Human"
- "Agent"
- "Hide idle"
- "Reset"
- "Apply"

Visual treatment:
- Use Liquid Glass for the sheet, drag handle, filter chips, and bottom action
  bar.
- Keep the sheet compact enough that the Dock context remains visible.
- Do not show the old bottom tab bar anywhere.
- Do not let branch/status controls dominate the entire first viewport.
- No nested cards. Use sheet sections with clear dividers or soft grouped bands.
