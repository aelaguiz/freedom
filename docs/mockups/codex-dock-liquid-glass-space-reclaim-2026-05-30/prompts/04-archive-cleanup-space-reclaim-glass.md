Create a polished iPhone 17 portrait UI mockup for Codex Dock.
Use the attached `base-03-archive-cleanup-sheet.png` as the primary layout
source. This is a Liquid Glass refinement of the reduced-space Archive Cleanup
direction.

Product direction:
- Archive Cleanup is a focused task sheet, not a root tab.
- The old bottom `Dock` / `Archive` / `Relay` tab bar is gone.
- Cleanup is safe: preview before action, exclusions, host split, and restore
  path.

Screen state:
- Background Dock screen has no bottom tab bar.
- Inset sheet title: "Archive Cleanup".
- Subtitle: "Preview before anything moves".
- Age segmented control: "30d", "90d", "1y", "Custom"; select "90d".
- Metrics: "6,842 older than 90 days", "2 hosts".
- Exclusion chips: "Exclude pinned", "Exclude running",
  "Exclude needs input", "Exclude Watch label".
- Host split rows: "Amir-M5 4,913" and "Home 1,929".
- Preview list: "Preview (3 of many)", "App-server ramp-up",
  "Playables audit", "Scene rendering plan".
- Bottom actions: "Review list", "Archive 6,842".
- Footnote: "Restore from Archived Threads".

Visual treatment:
- Use Liquid Glass for the sheet, segmented control, chips, and bottom actions.
- Keep preview rows solid and readable.
- Destructive action is prominent but grounded in the preview.
- No bottom tab bar. No permanent Archive root destination.
- No nested cards.
