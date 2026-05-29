# Codex Dock UI Automation Accessibility Hooks Worklog

Plan: `docs/CODEX_DOCK_UI_AUTOMATION_ACCESSIBILITY_HOOKS_2026-05-29.md`

## 2026-05-29T13:07:39Z

- Implemented the shared `AutomationID` namespace and `codexAutomationID(_:)` SwiftUI helper.
- Added `CodexDockUITests` through `project.yml` and regenerated `CodexDock.xcodeproj`.
- Added simulator UI smoke coverage for Dock controls/connectivity, Relay settings fields, and Dock row to Session detail using accessibility identifiers.
- Added IDs and accessibility values across bootstrap, root tabs, Dock, Archive, Relay settings, Session detail, Composer, message cards, request cards, and visible state/error surfaces.
- Added UI-test launch support so `CODEX_DOCK_HOSTS` is the complete requested host list and saved or discovered hosts do not change the test surface.
- Updated `README.md` to document accessibility-tree proof as the primary simulator automation path.
- Removed the visible Dock row action menu after user feedback. Dock row actions remain in the existing context menu with stable action IDs; the Dock card UI no longer gets a new visible control.

Verification run:

- `rtk swift test` — passed, 224 tests executed, 5 skipped, 0 failures.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` — passed; latest result bundle reports 222 passed, 5 skipped, 0 failed in `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_08-05-23--0500.xcresult`.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` — passed.
- `rg -n "accessibilityIdentifier\\(" CodexDock CodexDockApp CodexDockTests CodexDockUITests` — only `CodexDock/Automation/AutomationID.swift` contains the raw platform call.

Environment note:

- `SIM='iPhone 17'` was not usable as an exact local command because `scripts/sim.py resolve "iPhone 17"` found two matching simulators. The passing runs used the concrete simulator UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.

## 2026-05-29T13:12:34Z

- Strict code-quality review flagged that `CodexDock/Features/Dock/DockView.swift` had grown from 933 lines to 1,128 lines.
- Split reusable Dock row, host summary, message, banner, and navigation chrome helpers into `CodexDock/Features/Dock/DockSharedViews.swift`.
- `DockView.swift` is now 795 lines; `DockSharedViews.swift` is 334 lines.

Verification rerun:

- `rtk swift test` — passed, 224 tests executed, 5 skipped, 0 failures.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` — passed; latest result bundle reports 222 passed, 5 skipped, 0 failed in `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_08-11-01--0500.xcresult`.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` — passed.
