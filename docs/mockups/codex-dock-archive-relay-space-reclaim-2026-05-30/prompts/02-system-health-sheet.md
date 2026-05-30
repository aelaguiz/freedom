Create a polished iPhone 17 portrait UI mockup for Codex Dock. Use the current
Dock screenshot and legacy Hosts/Relay screenshot as references, but redesign
the Relay experience as a plain-English health sheet instead of a root tab.

Option name: System Health from the connectivity chip.

Screen state:
- The Dock screen is visible behind a partial-height iOS 26 sheet.
- The bottom root tab bar is gone.
- A sheet titled `System Health` is open from the `Online 2/2` connectivity chip.
- Top summary shows:
  - green icon
  - `Online 2/2`
  - `Last checked now`
  - primary button `Run check`
- Below the summary, show a compact route rollup with plain labels:
  - `Dock feed` with green `Healthy`
  - `Thread detail` with green `Healthy`
  - `Archive` with gray `Not checked`
  - `Voice` with green `Healthy`
  - `Diagnostics` with green `Healthy`
- Show two host cards:
  - `Amir-M5`
  - `Home`
- Each host card shows endpoint text in small secondary type, last success, and
  route badges using the same plain route names above.
- Include an issue explainer row for the gray route:
  - `Archive has no recent app traffic yet.`
  - secondary text `It will update after Archive opens or cleanup runs.`
- Bottom actions:
  - `Relay settings`
  - `Copy doctor command`

Design rules:
- Do not show raw JSON.
- Do not make `routesz`, `statusz`, JSON-RPC, or operation IDs prominent.
- It is okay to include endpoint strings, but keep them secondary.
- Use calm system colors: green for healthy, gray for not checked, orange/red only if needed.
- Keep the sheet readable and task-focused.
- No bottom `Archive` or `Relay` root tabs.

Purpose:
Turn the current connectivity diagnostics into an answer to: what works, what is
unknown, and what action should I take?
