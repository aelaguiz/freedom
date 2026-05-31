Create a polished iPhone 17 portrait UI mockup for Codex Dock showing the Dock
search and filter experience after an iOS 26 Liquid Glass modernization.
Use the attached current Dock screenshot, current Filters screenshot, prior
Filters mockup, and compact controls reference as anchors.

Design goal:
- Show the Dock screen behind an iOS 26 partial-height Filters sheet.
- Search and filtering should feel system-native, compact, and easy to scan.
- Use Liquid Glass for the sheet, search/control surfaces, and toolbar actions.
- Keep session rows behind the sheet readable enough to prove this is the same app.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41 status bar, no frame.
- Background Dock screen uses the same refreshed Dock home from the package:
  title "Dock", glass connectivity chip "Online 2/2", session rows behind.
- Present a partial-height inset iOS 26 sheet with rounded glass background.
  Content should peek around the sheet edges.
- Sheet title: "Filters".
- Sheet subtitle: "400 shown".
- Top row has search field "Search filters" and Done button.
- Filter groups use compact chips, segmented controls, and menus:
  "Host", "Branch", "Status", "Source", "Idle".
- Active chips should be visible and easy to clear.
- Bottom action row: secondary "Reset" and primary glass button "Apply".

Exact readable UI text to include:
- "Filters"
- "400 shown"
- "Search filters"
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
- "Idle"
- "Hide idle"
- "Reset"
- "Apply"
- "Done"

Visual rules:
- This should look like a native SwiftUI sheet, not a custom modal card.
- Use Liquid Glass sparingly: sheet chrome, chips, and action buttons.
- Do not make nested cards inside cards. Use full-width sheet sections with
  clean dividers or soft grouped bands.
- Keep tap targets believable for iPhone. Avoid tiny branch chips.
- Text must be crisp; avoid decorative microtext and invented labels.
