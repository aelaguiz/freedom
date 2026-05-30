Create a polished iPhone 17 portrait UI mockup for Codex Dock. Use the current
Dock screenshot and legacy Archive screenshot as references, but make archived
thread recovery a sheet launched from More, not a root tab.

Option name: Archived Threads sheet.

Screen state:
- The Dock screen is visible behind an iOS 26 sheet.
- The bottom root tab bar is gone.
- Sheet title is exactly `Archived Threads`.
- Header summary shows:
  - `2,138 archived`
  - `Across 2 hosts`
- Include a full-width search field with placeholder `Search archived threads`.
- Include compact filter chips:
  - `All hosts`
  - `Amir-M5`
  - `Home`
  - `Last archived`
- Show a toolbar row with:
  - `Select`
  - `Restore selected`
- Show archive rows grouped by date:
  - `Today`
  - `This week`
  - `April 2026`
- Rows show title, repo/path, branch, host, archived date, and a visible restore icon button.
- Put three rows in selected state and show a bottom selection bar:
  - `3 selected`
  - `Restore 3`

Design rules:
- The sheet is for finding and restoring archived threads.
- Do not make it a permanent bottom tab.
- Keep row density high and readable.
- Use clear native selection controls.
- No bottom `Archive` or `Relay` root tabs.
- No decorative background.

Purpose:
Show that archived-thread recovery remains fast and discoverable after removing
the permanent Archive tab.
