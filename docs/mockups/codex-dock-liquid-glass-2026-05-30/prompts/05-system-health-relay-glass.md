Create a polished iPhone 17 portrait UI mockup for Codex Dock showing a System
Health and Relay settings surface after an iOS 26 Liquid Glass modernization.
Use the attached prior System Health sheet, legacy Hosts/Relay mockup, current
Dock screenshot, and compact controls reference as anchors.

Design goal:
- Show how the old Relay tab can become a focused System Health sheet.
- Translate raw relay diagnostics into plain user-facing status.
- Use iOS 26 sheet and toolbar patterns instead of a permanent root tab.
- Keep host/port settings reachable but not dominant.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41.
- Dock screen visible dimly behind a partial-height iOS 26 Liquid Glass sheet.
- Sheet title: "System Health".
- Top summary card: "Online 2/2", "Last checked now", primary action "Run check".
- Route rollup as small status chips: "Dock feed Healthy", "Thread detail Healthy",
  "Archive Not checked", "Voice Healthy", "Diagnostics Healthy".
- Host cards for "Amir-M5" and "Home" with endpoint, connection state, and
  last success.
- Bottom actions as plain rows: "Relay settings", "Copy doctor command".
- A compact relay settings preview can appear lower in the sheet, but it should
  not crowd the first viewport.

Exact readable UI text to include:
- "System Health"
- "Online 2/2"
- "Last checked now"
- "Run check"
- "Dock feed"
- "Healthy"
- "Thread detail"
- "Archive"
- "Not checked"
- "Voice"
- "Diagnostics"
- "Amir-M5"
- "amir-m5.local:4510"
- "Home"
- "home.local:4510"
- "Connected"
- "12 live sessions"
- "Relay settings"
- "Copy doctor command"

Visual rules:
- Use glass for the sheet, toolbar buttons, and compact status chips.
- Do not show raw JSON, route IDs, bearer tokens, or OpenAI keys.
- Keep plain English diagnosis above implementation details.
- Use green sparingly for healthy status, gray for not checked, blue for actions.
- Make the sheet look native and inset, not like a floating web dashboard.
