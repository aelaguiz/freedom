# Codex Dock Archive/Relay Space Reclaim UX Worklog

Date: 2026-05-30
Status: Research and mockup brief. No app implementation in this pass.

## Scope

This worklog documents the current Codex Dock user experience around the bottom
`Dock` / `Archive` / `Relay` tabs, then turns that evidence into mockup briefs.
The goal is to reclaim vertical room for the session feed, make archive cleanup
useful for thousands of threads, and turn relay/connectivity status into a clear
diagnostic surface instead of raw internal evidence.

## Current UX Facts

### Root structure

- `CodexDockRootView` is a three-tab `TabView`.
- The root tabs are `Dock`, `Archive`, and `Relay`.
- `Dock` is the daily work surface. `Archive` and `Relay` are permanent
  top-level destinations even though they are maintenance/setup surfaces.
- Source: `CodexDock/Features/Dock/DockView.swift:125`.

### Dock screen

- The Dock screen uses a `NavigationStack` with a vertical `ScrollView`.
- The scroll stack is `header`, `controls`, then `content`, with 16 point
  horizontal padding, 14 point top padding, and 24 point bottom padding.
- The header shows large `Dock` text and a global connectivity chip when a
  connectivity store is available.
- The controls are full-width search, the `Newest` / `Host` / `Branch` lens row,
  a filter button, and an active-filter summary line.
- The current live screenshot shows the active-filter summary can consume two
  lines. Combined with the floating bottom tab bar, this reduces visible row
  count on the first screen.
- Sources:
  - `CodexDock/Features/Dock/DockView.swift:290`
  - `CodexDock/Features/Dock/DockView.swift:331`
  - `CodexDock/Features/Dock/DockView.swift:351`
  - `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/inputs/current-dock-live.png`

### Archive screen

- `ArchiveView` is a full root tab with its own `NavigationStack` and
  `ScrollView`.
- The header is large `Archive` text plus a refresh button.
- Empty state says: `Archived sessions from configured hosts will appear here.`
- Loaded state shows host summaries, action errors, mapping failures, sections,
  archived rows, and per-row `Restore`.
- There is no current Archive search field, no bulk archive action, no age rule,
  no preview count, no select mode, and no cleanup flow.
- Sources:
  - `CodexDock/Features/Archive/ArchiveView.swift:23`
  - `CodexDock/Features/Archive/ArchiveView.swift:48`
  - `CodexDock/Features/Archive/ArchiveView.swift:81`
  - `CodexDock/Features/Archive/ArchiveView.swift:131`

### Relay screen

- `HostsView` is presented as the `Relay` root tab.
- The header is large `Relay` text plus a checkmark button that runs
  `store.testAll()`.
- When configured, the content always shows host rows and the host editor.
- The host editor always occupies screen space with `Add Relay` / `Edit Relay`,
  `Host`, `Port`, and `Save Relay`.
- This makes setup/edit controls permanently visible even after setup is done.
- Sources:
  - `CodexDock/Features/Hosts/HostsView.swift:21`
  - `CodexDock/Features/Hosts/HostsView.swift:40`
  - `CodexDock/Features/Hosts/HostsView.swift:74`
  - `CodexDock/Features/Hosts/HostsView.swift:122`

### Connectivity and diagnostics

- The app has one root connectivity indicator. The README names states such as
  `Unconfigured`, `Checking`, `Online`, `Partial`, `Reconnecting`,
  `Backgrounded`, `Resuming`, `Stale`, `Offline`, `Error`, and `Config error`.
- Tapping the global connectivity chip presents `ConnectivityDiagnosticsSheet`
  and refreshes relay diagnostics.
- The current diagnostics sheet lists `Endpoint`, `Status`, `Last success`, and
  route rows. If there is no route evidence it says `No route evidence yet`.
- This is useful internal evidence, but it does not yet answer the user question:
  "What is broken, what still works, and what should I do next?"
- Source:
  - `README.md:146`
  - `README.md:199`
  - `CodexDock/Features/Status/ConnectivityDiagnosticsSheet.swift:10`
  - `CodexDock/State/AppConnectivityStore.swift:369`

### Archive command model

- The Swift archive protocol has only two operations:
  `archiveThread(_:, on:)` and `unarchiveThread(_:, on:)`.
- Dock row context menus expose a destructive row-level `Archive` command.
- `DockStore.archive(_:)` archives one row, clears the action error, and refreshes.
- A repo search found no current bulk archive command, no age-based cleanup
  command, and no production `archive cleanup` flow.
- Sources:
  - `CodexDock/State/AppServerDockClient.swift:60`
  - `CodexDock/Features/Dock/DockView.swift:951`
  - `CodexDock/State/DockStore.swift:189`

### Relay test model

- `HostSettingsStore.testAll()` loops through saved hosts and calls `test(_:)`.
- `test(_:)` only loads `.activeHuman` sessions through the configured relay host.
- That validates the active session list path, but it does not by itself explain
  the health of archive, detail, voice/transcription, route evidence, or relay
  process health.
- Sources:
  - `CodexDock/State/HostSettingsStore.swift:140`
  - `CodexDock/State/HostSettingsStore.swift:156`
  - `CodexDock/State/HostSettingsStore.swift:172`
  - `README.md:199`

## Current UX Diagnosis

Net: the app gives permanent navigation space to low-frequency jobs while the
high-frequency job, scanning active sessions, is vertically constrained.

- `Dock` is the primary surface. It needs maximum visible session rows.
- `Archive` is currently a recovery browser for already archived rows. It is not
  the cleanup tool the user needs for roughly 7,000 threads.
- `Relay` is currently a settings editor plus a narrow active-list test. It is
  valuable, but it is not a daily destination.
- The connectivity chip is the right entry point, but the sheet should translate
  raw route evidence into diagnosis, severity, last check, and concrete next
  actions.
- The tab bar is the biggest visible space cost because it stays present on the
  most important screen.

## External UX Research

### Apple tab bars

Apple describes tab bars as navigation between top-level app sections. Apple also
says to weigh extra tabs against how often people need each section, and notes
that iOS 26 tab bars float on Liquid Glass above content.

Implication for Codex Dock: `Archive` and `Relay` should earn top-level tab
placement only if the user switches to them often. For this app, they read more
like secondary tasks than primary destinations.

Source: https://developer.apple.com/design/human-interface-guidelines/tab-bars/

### Apple menus and pull-down buttons

Apple describes menus as space-efficient places for commands, and pull-down
buttons as a way to expose related actions without adding more visible buttons.
Apple specifically calls out More-style pull-down buttons for items that do not
need prominent positions in the main interface.

Implication for Codex Dock: `Archive cleanup`, `Archived threads`,
`System health`, and `Relay settings` can live behind a compact top-right More
button or toolbar item.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/menus
- https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons

### Apple context menus

Apple describes context menus as a way to expose actions related to an item
without cluttering the interface. Context menus work for supplemental row actions,
but a core cleanup workflow should not be available only by long-pressing one
row at a time.

Implication for Codex Dock: keep row archive as a row action, but add a visible
bulk cleanup path for large archives.

Source: https://developer.apple.com/design/human-interface-guidelines/context-menus

### Apple sheets

Apple sheets are temporary surfaces for focused tasks. iOS 26 partial-height
sheets are inset by default and use Liquid Glass styling.

Implication for Codex Dock: `Archive Cleanup`, `Archived Threads`, and
`System Health` are good sheet candidates because they are focused tasks that do
not need permanent bottom navigation.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/sheets
- https://developer.apple.com/videos/play/wwdc2025/323

### Apple Mail batch archive/delete pattern

Apple Mail on iPhone supports list selection and batch archive/delete through
`More` -> `Select`, then selected-row actions. Apple also documents swipe and
context-menu paths for single-message actions.

Implication for Codex Dock: use a familiar pattern: single-row archive stays
available, but bulk cleanup should use select/preview/confirm.

Source: https://support.apple.com/en-lamr/102428

### NN/g usability heuristics

NN/g's heuristics are directly relevant here:

- Visibility of system status: the app should say what is going on quickly.
- User control and freedom: destructive cleanup needs cancel, preview, and undo
  where possible.
- Recognition rather than recall: users should not need to remember what
  `routesz`, route names, or relay internals mean.
- Aesthetic and minimalist design: rarely needed UI competes with the primary
  content.
- Help users diagnose and recover from errors: diagnostics should use plain
  language and suggest a fix.

Source: https://www.nngroup.com/articles/ten-usability-heuristics/

### NN/g progressive disclosure

Progressive disclosure defers advanced or rarely used features to secondary
screens so the main app is easier to learn and less error-prone.

Implication for Codex Dock: relay setup and archive maintenance should be
available, but not as permanent first-screen chrome.

Source: https://www.nngroup.com/articles/progressive-disclosure/

### Baymard applied filters

Baymard's filter research stresses that applied filters should be easy to see,
review, and clear without pushing primary content too far down.

Implication for Codex Dock: keep the active filter summary compact. If the
summary needs two lines, prefer chips, truncation, or a sheet state that keeps
session rows visible.

Source: https://baymard.com/blog/how-to-design-applied-filters

## Design Constraints

- Keep `Dock` as the fast first screen.
- Reclaim the bottom tab bar area for more session rows.
- Keep archive recovery discoverable, but make cleanup task-oriented.
- Keep relay configuration available, but move it behind `System Health` or
  `More`.
- Avoid making route names, JSON-RPC method names, or app-server internals the
  main UI language.
- Any destructive bulk archive flow needs preview, exclusions, progress, and a
  clear reversal story.
- Do not persist relay identity on the phone. Saved app configs should stay as
  host/port lists only, per the repo instructions.
- Do not treat loopback paths or mock transports as physical-phone completion
  proof.

## Recommended Direction

### Option A: Dock-only root with More menu

Make `Dock` the only persistent daily screen. Replace the bottom `Archive` and
`Relay` tabs with a compact top-right More menu:

- `Archive cleanup`
- `Archived threads`
- `System health`
- `Relay settings`

This keeps low-frequency work reachable without spending permanent bottom space.

### Option B: System Health sheet from connectivity chip

Make the connectivity chip open a richer `System Health` sheet:

- top summary: `Online 2/2`, `Last checked now`
- route rollup in plain language: `Dock feed healthy`, `Thread detail healthy`,
  `Archive not checked`, `Voice healthy` or `Voice not checked`
- per-host cards with endpoint, last success, route badges, and one clear issue
  if degraded
- actions: `Run check`, `Relay settings`, `Copy doctor command`

This unifies the Relay tab, connectivity chip, and README `relay-doctor` mental
model into one app surface.

### Option C: Archive Cleanup sheet

Add a task flow for the user's real cleanup need:

- age rules: `30d`, `90d`, `1y`, custom
- exclusions: pinned, running, needs input, watch label
- preview count before action
- host split before action
- sample rows before action
- primary action: `Archive N threads`
- safe completion: progress, result summary, and undo or restore path

This should not be buried inside the existing Archive recovery browser.

### Option D: Archived Threads as a sheet/filter

Move archive browsing from a root tab to a task surface:

- `Archived Threads` opens from More or Archive Cleanup completion.
- Search is prominent.
- Host/date filters are compact chips.
- Row-level restore remains.
- Select mode supports batch restore.

This keeps archive recovery discoverable while preserving the Dock-first layout.

## Mockup Package

Mockups for these options live under:

`docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/`

Generated outputs:

- `outputs/01-dock-more-menu.png`
- `outputs/02-system-health-sheet.png`
- `outputs/03-archive-cleanup-sheet.png`
- `outputs/04-archived-threads-sheet.png`
- `outputs/contact-sheet.png`

## Open Implementation Questions

- Should `Archive Cleanup` call one row-level `thread/archive` per selected
  thread, or should the relay/app-server gain a bulk command?
- What is the safe default age threshold for this user: `90d`, `180d`, or `1y`?
- Can the app offer true undo after bulk archive, or should it offer a
  post-action `Recently archived` restore list?
- Which relay routes should count as app-critical for the top health summary?
- Should `System Health` run app-initiated route checks, or only display passive
  route evidence plus safe probes?

## No-Code Verification

This pass is documentation and generated mockups only. App build and test
commands are not required unless source code changes follow.
