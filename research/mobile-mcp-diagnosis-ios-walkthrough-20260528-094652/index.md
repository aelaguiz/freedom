# Mobile MCP iOS Diagnosis Walkthrough

Device: `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` (`feat_anim_1 - iPhone 17`, iOS simulator 26.5)
Started: Thu May 28 09:47:02 CDT 2026
Scope: Diagnose whether Mobile MCP can discover devices, list apps, launch an app, inspect elements, click by coordinates, take screenshots, and save screenshots.
Status: Completed

| # | File | Screen | Notes |
|---:|---|---|---|
| 001 | 001_codex-dock_launch_dock-tab.png | Codex Dock Dock tab | Mobile MCP launched `com.aelaguiz.CodexDockApp`, listed accessibility elements, and captured the Dock tab with live relay-backed session rows. |
| 002 | 002_codex-dock_tab_archive-empty.png | Codex Dock Archive tab | Coordinate tap from the Mobile MCP element list opened Archive, and screenshot capture saved the empty archive state. |

## Diagnostic Result

- `mobile_list_available_devices`: passed; four online iOS devices were returned.
- `mobile_list_apps`: passed on the selected simulator; `Codex Dock (com.aelaguiz.CodexDockApp)` was installed.
- `mobile_launch_app`: passed for `com.aelaguiz.CodexDockApp`.
- `mobile_list_elements_on_screen`: passed on Dock and Archive screens with labels and coordinates.
- `mobile_click_on_screen_at_coordinates`: passed for the Archive tab at `(201, 822)`.
- `mobile_save_screenshot`: passed for both saved PNG files.
- `mobile_take_screenshot`: passed for quick visual inspection.
- Blockers: none for this diagnosis.
