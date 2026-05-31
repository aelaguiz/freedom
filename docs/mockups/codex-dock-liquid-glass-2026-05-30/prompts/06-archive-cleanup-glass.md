Create a polished iPhone 17 portrait UI mockup for Codex Dock showing Archive
Cleanup after an iOS 26 Liquid Glass modernization. Use the attached legacy
Archive mockup, current Dock screenshot, prior System Health sheet, and compact
controls reference as anchors.

Design goal:
- Show archive cleanup as a focused iOS 26 sheet, not a permanent root tab.
- Make a large-thread cleanup task feel safe: preview before action, exclusions,
  host split, sample rows, and restore path.
- Use Liquid Glass for the sheet, segmented age control, and primary action.
- Keep row previews solid and readable.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41.
- Dock screen visible behind an inset iOS 26 sheet.
- Sheet title: "Archive Cleanup".
- Subtitle: "Preview before anything moves".
- Age segmented control: "30d", "90d", "1y", "Custom"; select "90d".
- Summary metrics: "6,842 older than 90 days" and "2 hosts".
- Exclusion chips: "Exclude pinned", "Exclude running", "Exclude needs input",
  "Exclude Watch label".
- Host split rows: "Amir-M5 4,913" and "Home 1,929".
- Preview list titled "Preview (3 of many)" with three sample threads.
- Bottom actions: secondary "Review list", primary "Archive 6,842".
- Footnote: "Restore from Archived Threads".

Exact readable UI text to include:
- "Archive Cleanup"
- "Preview before anything moves"
- "30d"
- "90d"
- "1y"
- "Custom"
- "6,842"
- "older than 90 days"
- "2 hosts"
- "Exclude pinned"
- "Exclude running"
- "Exclude needs input"
- "Exclude Watch label"
- "Amir-M5"
- "4,913"
- "Home"
- "1,929"
- "Preview (3 of many)"
- "App-server ramp-up"
- "Playables audit"
- "Scene rendering plan"
- "Review list"
- "Archive 6,842"
- "Restore from Archived Threads"

Visual rules:
- The destructive action must be prominent but not scary; use system role color
  with clear preview and reversible path.
- Do not make preview rows translucent. Keep them readable.
- Avoid tiny text; this should be useful as a design review mockup.
