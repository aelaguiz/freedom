Create a polished iPhone 17 portrait UI mockup for Codex Dock. Use the current
Dock screenshot and legacy Archive screenshot as references, but redesign archive
as a task-oriented bulk cleanup sheet.

Option name: Archive Cleanup.

Screen state:
- The Dock screen is visible behind a large iOS 26 sheet.
- The bottom root tab bar is gone.
- Sheet title is exactly `Archive Cleanup`.
- Subtitle says `Preview before anything moves`.
- Show a compact segmented control under `Older than` with:
  - `30d`
  - `90d`
  - `1y`
  - `Custom`
- `90d` is selected.
- Show a large count card or summary strip:
  - `6,842 threads`
  - `older than 90 days`
  - `2 hosts`
- Show exclusion toggles with checkmarks:
  - `Exclude pinned`
  - `Exclude running`
  - `Exclude needs input`
  - `Exclude Watch label`
- Show host split:
  - `Amir-M5` `4,913`
  - `Home` `1,929`
- Show a small preview list with three realistic Codex session rows and dates.
- Bottom action area:
  - secondary button `Review list`
  - primary button `Archive 6,842`
  - small safety text `Restore from Archived Threads`

Design rules:
- This is a preview and confirmation flow, not an archive browser.
- Make the destructive action prominent but not scary.
- Use Apple-style selection, toggles, segmented controls, and bottom action area.
- No bottom `Archive` or `Relay` root tabs.
- No raw command names.
- Keep text legible and inside containers.

Purpose:
Show the missing product feature for a user with thousands of stale sessions:
safe age-based bulk archive with exclusions and preview.
