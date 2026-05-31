Create a polished iPhone 17 portrait UI mockup for Codex Dock.
Use the attached `base-02-system-health-sheet.png` as the primary layout source.
This is a Liquid Glass refinement of the reduced-space System Health direction.

Product direction:
- System Health replaces the old need for a permanent Relay tab.
- The Dock screen stays visible behind the sheet.
- The old bottom `Dock` / `Archive` / `Relay` tab bar is gone.
- Diagnostics are plain-English and user-facing.

Screen state:
- Background Dock screen has no bottom tab bar.
- Present an iOS 26 inset sheet titled "System Health".
- Top summary: "Online 2/2", "Last checked now", "Run check".
- Route rollup: "Dock feed Healthy", "Thread detail Healthy",
  "Archive Not checked", "Voice Healthy", "Diagnostics Healthy".
- Host cards for "Amir-M5" and "Home".
- Actions: "Relay settings", "Copy doctor command".

Exact readable text to include:
- "System Health"
- "Online 2/2"
- "Last checked now"
- "Run check"
- "Dock feed"
- "Thread detail"
- "Archive"
- "Voice"
- "Diagnostics"
- "Healthy"
- "Not checked"
- "Amir-M5"
- "Home"
- "Connected"
- "Relay settings"
- "Copy doctor command"

Visual treatment:
- Use Liquid Glass for the sheet, status chips, route rollup, and action rows.
- Keep the sheet native and calm; no web-dashboard look.
- Do not show raw route IDs, JSON, tokens, OpenAI keys, or bearer values.
- No bottom tab bar.
