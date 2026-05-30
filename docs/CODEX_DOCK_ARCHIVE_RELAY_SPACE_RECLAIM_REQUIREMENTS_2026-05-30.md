# Codex Dock Archive/Relay Space Reclaim Requirements

Date: 2026-05-30
Status: approved requirements after Composer review; implementation source of truth.

## 1. Source Materials

This requirements doc is derived from the current repo, the UX worklog, and the
generated review mockups.

Primary local sources:

- UX worklog:
  `docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_UX_WORKLOG_2026-05-30.md`
- Mockup package:
  `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/`
- Contact sheet:
  `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/contact-sheet.png`
- Dock-only More menu mock:
  `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/01-dock-more-menu.png`
- System Health sheet mock:
  `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/02-system-health-sheet.png`
- Archive Cleanup sheet mock:
  `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/03-archive-cleanup-sheet.png`
- Archived Threads sheet mock:
  `docs/mockups/codex-dock-archive-relay-space-reclaim-2026-05-30/outputs/04-archived-threads-sheet.png`

Current code anchors:

- Root tabs today:
  `CodexDock/Features/Dock/DockView.swift:125`
- Dock header and controls:
  `CodexDock/Features/Dock/DockView.swift:290`
- Current Archive root tab:
  `CodexDock/Features/Archive/ArchiveView.swift:23`
- Current Relay root tab:
  `CodexDock/Features/Hosts/HostsView.swift:21`
- Connectivity sheet today:
  `CodexDock/Features/Status/ConnectivityDiagnosticsSheet.swift:10`
- Connectivity store and route diagnostics:
  `CodexDock/State/AppConnectivityStore.swift:369`
- Archive commands today:
  `CodexDock/State/AppServerDockClient.swift:60`
- Active Dock page limit:
  `CodexDock/Configuration/CodexDockConstants.swift:16`

External UX sources summarized in the worklog:

- Apple HIG tab bars
- Apple HIG menus and pull-down buttons
- Apple HIG context menus
- Apple HIG sheets and iOS 26 sheet behavior
- Apple Mail batch archive/delete pattern
- NN/g usability heuristics
- NN/g progressive disclosure
- Baymard applied-filter guidance

## 2. Product Decision

Codex Dock should stop treating `Archive` and `Relay` as permanent root tabs.
The daily product is the Dock feed. Archive maintenance, archived-thread
recovery, relay configuration, and connection diagnosis should move into
task-focused menu and sheet surfaces.

Chosen direction:

1. Keep `Dock` as the single primary root screen.
2. Remove the bottom `Dock` / `Archive` / `Relay` tab bar from the daily Dock
   screen.
3. Add a compact top-right More menu on Dock.
4. Make `System Health` the primary diagnostics surface, opened from the
   connectivity chip or More menu.
5. Make `Archive Cleanup` a bulk cleanup sheet opened from More.
6. Make `Archived Threads` a search/restore sheet opened from More and from
   cleanup completion.
7. Move relay host editing into `Relay Settings`, opened from System Health or
   More.

This is not a cosmetic rearrangement. The feature changes information
architecture: rare setup/maintenance work leaves the persistent navigation
surface, and the reclaimed space belongs to live session rows.

Presentation decision:

- Dock owns one active task sheet at a time.
- No task sheet stacks another modal task sheet on top of itself.
- Each task sheet owns an internal `NavigationStack` where it needs subviews.
- `System Health -> Relay Settings` pushes Relay Settings inside the same
  sheet when opened from System Health.
- `Archive Cleanup -> Review list` pushes Review List inside the same Archive
  Cleanup sheet.
- `Archive Cleanup -> View archived` replaces the active task sheet with
  Archived Threads after completion.
- `Restore from Archived Threads` inside Archive Cleanup replaces the active
  task sheet with Archived Threads.
- Host-card chevrons in System Health push Host Health Detail inside the
  System Health sheet.
- More menu is only available from Dock. If a task sheet is already open, the
  user must close it or use an in-sheet cross-link; in-sheet cross-links either
  push inside the current NavigationStack or replace the active task sheet as
  stated above.
- iOS task sheets should use the system sheet presentation with large detent as
  the stable implementation target. System Health may start as medium only if
  the content remains fully reachable and expandable; large detent is acceptable
  for all task sheets.

## 3. Non-Goals

These items are explicitly out of scope for the first implementation unless a
later approved plan says otherwise.

- No new marketing, onboarding, or explanatory landing page.
- No new phone-side secret storage.
- No phone-side relay instance identity persistence.
- No direct physical-phone connection to the raw authenticated `:4500`
  app-server path.
- No raw `xcodebuild`, raw `devicectl`, or raw `simctl install` as the normal
  workflow.
- No visual-pixel golden tests for the mockups.
- No server-side bulk archive protocol in the first implementation.
- No server-side bulk restore protocol in the first implementation.
- No new docs-audit or string-grep enforcement harness.
- No hidden fallback that silently returns to the old `Archive` / `Relay` root
  tabs.

## 4. UX Principles

R-UX-001. The Dock feed is the app's primary work surface.

R-UX-002. Rare maintenance tasks must not consume permanent first-screen space.

R-UX-003. Cleanup must be preview-first. No bulk destructive action can run
without showing count, scope, exclusions, and a confirmation action.

R-UX-004. Diagnostics must answer user questions in plain language:

- What works?
- What is degraded?
- What has not been checked yet?
- What action should I take?

R-UX-005. Raw route names, operation IDs, `/routesz`, JSON-RPC method names, and
relay internals are supporting evidence. They are not the primary user-facing
language.

R-UX-006. Row-level archive and restore actions remain available for small
one-off work.

R-UX-007. Bulk archive and batch restore must be reachable without long-press or
hidden context menus.

R-UX-008. Status colors must be restrained and semantic:

- Green: healthy or online.
- Blue: primary actions and selected controls.
- Gray: not checked or neutral.
- Orange: degraded or partial.
- Red: failed, blocked, or destructive warning.

R-UX-009. The interface must stay dense, calm, and utilitarian. This is an
operational tool, not a product landing page.

R-UX-010. Empty, partial, loading, failed, and completed states are first-class
states. They must not collapse into blank sheets or vague text.

## 5. Information Architecture

### 5.1 Before

Current root structure:

```text
CodexDockRootView
|
+-- TabView
    |
    +-- Dock
    +-- Archive
    +-- Relay
```

Current user-visible result:

```text
-------------------------------------------------
Dock                                      Online
[ Search sessions, repo, branch, host          ]
[ Newest ] [ Host ] [ Branch ] [ filters       ]
Human sessions - active only - Newest activity

[ session row                                      ]
[ session row                                      ]
[ session row                                      ]

-------------------------------------------------
        Dock              Archive            Relay
-------------------------------------------------
```

Problem: `Archive` and `Relay` are always visible at the bottom even when the
user is only scanning the Dock feed.

### 5.2 After

Required root structure:

```text
CodexDockRootView
|
+-- DockRootSurface
    |
    +-- Dock feed
    +-- More menu
    |   |
    |   +-- Archive Cleanup sheet
    |   +-- Archived Threads sheet
    |   +-- System Health sheet
    |   +-- Relay Settings sheet
    |
    +-- Connectivity chip
        |
        +-- System Health sheet
```

Required user-visible result:

```text
-------------------------------------------------
Dock                         Online 2/2     (...)
[ Search sessions, repo, branch, host          ]
[ Newest ] [ Host ] [ Branch ] [ filters       ]
Human sessions - active only - Newest activity

[ session row                                      ]
[ session row                                      ]
[ session row                                      ]
[ session row                                      ]
[ session row                                      ]
[ session row                                      ]
-------------------------------------------------
```

There must be no bottom root tab bar on the daily Dock screen.

## 6. Dock Root Requirements

R-DOCK-001. The Dock screen remains the first usable screen after relay
bootstrap is ready.

R-DOCK-002. The Dock screen must not show the old bottom `Dock` / `Archive` /
`Relay` tab bar.

R-DOCK-003. The top header must include:

- large title `Dock`
- global connectivity chip, such as `Online 2/2`
- compact More button with an ellipsis icon

R-DOCK-004. The More button opens a native compact menu, not a large custom
panel.

R-DOCK-005. The More menu contains these items, in this order:

1. `Archive cleanup`
2. `Archived threads`
3. `System health`
4. `Relay settings`

R-DOCK-006. The More menu item labels must match the mockup names exactly.

R-DOCK-007. The existing full-width Dock search remains visible.

R-DOCK-008. The existing `Newest`, `Host`, and `Branch` lens controls remain
visible.

R-DOCK-009. The existing filter button remains visible.

R-DOCK-010. The active filter summary must stay compact. It may use a single
line, compact chips, or truncation, but it must not routinely consume a tall
multi-line block that pushes rows down.

R-DOCK-011. Session row behavior must be preserved:

- tapping opens detail
- row context menu keeps existing row actions
- row status badges preserve meaning
- local pin/watch/color metadata remains visible where already supported

R-DOCK-012. Row-level `Archive` remains available from the row action menu.

R-DOCK-013. If a host is unavailable, the Dock screen must keep the existing
host error/retry pattern and must include a path to `Relay settings` or
`System health`.

R-DOCK-014. The reclaimed bottom space should result in more visible Dock rows
on the first screen compared with the old three-tab layout.

### 6.1 Dock More Menu ASCII Mockup

Reference mockup:
`outputs/01-dock-more-menu.png`

```text
9:41                                      100%

Dock                         [Online 2/2]  (...)
                                               |
                                               v
                                        +------------------+
[ Search sessions, repo, branch, host ] | Archive cleanup  |
                                        | Archived threads |
[ Newest ] [ Host ] [ Branch ] [ filt ] | System health    |
                                        | Relay settings   |
  Human sessions - active only - Newest +------------------+

+---------------------------------------------------------+
| green | App-server ramp-up                       Active |
|       | Amir-M5 - codex-client - main              now  |
|       | The iPhone 17 simulator is at the home...       |
+---------------------------------------------------------+
| purple| Playables audit                         Active |
+---------------------------------------------------------+
| orange| Scene rendering unification plan        Active |
+---------------------------------------------------------+
| blue  | Implement remount lifecycle               Idle |
+---------------------------------------------------------+
| green | Fix asset disposal race condition          Idle |
+---------------------------------------------------------+
| orange| Add integration tests for remount          Idle |
+---------------------------------------------------------+
```

## 7. System Health Requirements

### 7.1 Entry Points

R-HEALTH-001. Tapping the global connectivity chip opens `System Health`.

R-HEALTH-002. More menu item `System health` opens the same `System Health`
surface.

R-HEALTH-003. `System Health` must replace the current raw
`ConnectivityDiagnosticsSheet` as the primary user-facing diagnostics surface.

R-HEALTH-004. Raw route evidence may remain available inside an expandable
details section, but it must not be the default first impression.

### 7.2 Sheet Layout

R-HEALTH-010. `System Health` is a sheet over Dock, not a root tab.

R-HEALTH-011. The sheet header contains:

- title `System Health`
- close button
- optional drag indicator on iOS

R-HEALTH-012. The top summary contains:

- overall health icon
- overall status label, such as `Online 2/2`, `Partial`, or `Offline`
- last checked text, such as `Last checked now`
- primary action `Run check`

R-HEALTH-013. The main route rollup uses plain user-facing categories:

- `Dock feed`
- `Thread detail`
- `Archive`
- `Voice`
- `Diagnostics`

R-HEALTH-014. Each category shows one of:

- `Healthy`
- `Checking`
- `Not checked`
- `Degraded`
- `Failed`
- `Blocked`
- `Stale`

R-HEALTH-015. The sheet shows one card per configured host.

R-HEALTH-016. Each host card shows:

- display name
- endpoint as secondary text
- connection state
- live session count when known
- last success or last checked text
- the same category rollup badges

R-HEALTH-017. If a category is `Not checked`, the sheet must explain why in
plain language. Example:

```text
Archive has no recent app traffic yet.
It will update after Archive opens or cleanup runs.
```

R-HEALTH-018. If a category is degraded or failed, the sheet must show:

- what user-visible ability is affected
- the most helpful known reason
- one suggested next action

R-HEALTH-019. Tapping a host card chevron opens Host Health Detail inside the
same System Health sheet. It does not open a second modal sheet.

R-HEALTH-020. Host Health Detail shows:

- host display name
- endpoint
- overall host state
- last check and last success
- category rollup
- expandable raw route evidence
- action `Relay settings`
- action `Copy doctor command`

R-HEALTH-021. Raw route evidence is allowed in Host Health Detail, but the
plain category rollup must remain above it.

R-HEALTH-022. The bottom action area contains:

- `Relay settings`
- `Copy doctor command`

R-HEALTH-023. `Copy doctor command` copies a repo-owned diagnostic command when
possible, preferably `rtk make relay-doctor`. It must not copy secrets.

R-HEALTH-024. `Run check` refreshes diagnostics for all configured hosts.

R-HEALTH-025. `Run check` may run only safe probes automatically. Passive-only
routes must not be artificially invoked just to turn gray badges green.

R-HEALTH-026. Unknown or passive-only route evidence must be displayed as
`Not checked`, not as a failure, unless current app evidence proves a failure.

R-HEALTH-027. App-critical failures from route diagnostics must affect the
summary and host card status.

### 7.3 Health Category Mapping

R-HEALTH-030. `Dock feed` summarizes active list and Dock stream evidence:

- `thread/list`
- `dock/subscribe`
- `dock/update`
- `dock/resync`
- current Dock store host state

R-HEALTH-031. `Thread detail` summarizes session detail evidence:

- `thread/read`
- `thread/resume`
- `thread/turns/list`
- live detail reconnect/stale state

R-HEALTH-032. `Archive` summarizes archive and restore evidence:

- archive list load evidence from `ArchiveStore`
- `thread/archive`
- `thread/unarchive`
- archive cleanup progress/failure evidence

R-HEALTH-033. `Voice` summarizes realtime transcription evidence:

- `audio/transcription/start`
- `audio/transcription/append`
- `audio/transcription/commit`
- `audio/transcription/cancel`
- transcription delta/completed/failed/canceled/closed notifications

R-HEALTH-034. `Diagnostics` summarizes diagnostics endpoint evidence:

- `/statusz`
- `/routesz`
- diagnostics fetch failures
- local process/route-health facts already exposed by relay status endpoints

R-HEALTH-035. The UI may still store route diagnostics by raw route name. The
display layer must map those raw routes into the five plain categories above.

### 7.4 System Health ASCII Mockup

Reference mockup:
`outputs/02-system-health-sheet.png`

```text
Dock is dimmed behind the sheet

---------------------------------------------------------
                 System Health                       [x]

+-------------------------------------------------------+
|  [check]  Online 2/2              [ Run check ]       |
|           Last checked now                             |
|                                                       |
| Dock feed     Thread detail   Archive  Voice   Diag   |
| Healthy       Healthy         Not chk  Healthy Healthy |
+-------------------------------------------------------+

+-------------------------------------------------------+
| [desktop] Amir-M5                         Connected > |
|           amir-m5.fairy-salmon.ts.net:4510            |
|           Last success now - 12 live sessions          |
| Dock feed   Thread detail   Archive   Voice   Diag    |
| Healthy     Healthy         Not chk   Healthy Healthy  |
+-------------------------------------------------------+

+-------------------------------------------------------+
| [desktop] Home                            Connected > |
|           home.fairy-salmon.ts.net:4510               |
|           Last success 1m ago - 4 live sessions        |
| Dock feed   Thread detail   Archive   Voice   Diag    |
| Healthy     Healthy         Not chk   Healthy Healthy  |
+-------------------------------------------------------+

+-------------------------------------------------------+
| [i] Archive has no recent app traffic yet.             |
|     It will update after Archive opens or cleanup runs.|
+-------------------------------------------------------+

Relay settings                                            >
Copy doctor command                                       >
---------------------------------------------------------
```

### 7.6 Host Health Detail ASCII Mockup

```text
---------------------------------------------------------
< System Health             Amir-M5

amir-m5.fairy-salmon.ts.net:4510
Connected - last success now - 12 live sessions

Dock feed       Healthy
Thread detail   Healthy
Archive         Not checked
Voice           Healthy
Diagnostics     Healthy

+-------------------------------------------------------+
| [i] Archive has no recent app traffic yet.             |
|     It will update after Archive opens or cleanup runs.|
+-------------------------------------------------------+

Technical evidence
[ Show route details v ]

Relay settings                                            >
Copy doctor command                                       >
---------------------------------------------------------
```

### 7.5 Degraded Health ASCII Mockup

```text
---------------------------------------------------------
                 System Health                       [x]

+-------------------------------------------------------+
|  [!]  Partial                         [ Run check ]   |
|       Dock feed works. Voice is failing on Home.       |
|                                                       |
| Dock feed     Thread detail   Archive  Voice   Diag   |
| Healthy       Healthy         Not chk  Failed  Healthy |
+-------------------------------------------------------+

+-------------------------------------------------------+
| [desktop] Home                              Partial  > |
| Voice failed: transcription upstream timeout.          |
| What this affects: dictation in session detail.        |
| Try: Run check, then restart services if it persists.  |
+-------------------------------------------------------+

Relay settings                                            >
Copy doctor command                                       >
---------------------------------------------------------
```

## 8. Relay Settings Requirements

R-RELAY-001. `Relay settings` is a task surface reachable from:

- Dock More menu
- System Health bottom action
- host cards in System Health when host-specific action is needed

R-RELAY-002. `Relay settings` is not a root tab.

R-RELAY-003. When opened from Dock More, Relay Settings is the root of the
active task sheet.

R-RELAY-004. When opened from System Health, Relay Settings is pushed inside the
existing System Health sheet's internal `NavigationStack`.

R-RELAY-005. The current host add/edit/remove capability must be preserved.

R-RELAY-006. The first view should prioritize saved hosts and their status. The
manual add/edit form must not permanently consume the full visible screen unless
the user is actively adding or editing.

R-RELAY-007. Default relay settings state:

- title `Relay Settings`
- list of saved hosts
- host status and last check text
- `Run check` action
- `Add Relay` action

R-RELAY-008. Add/edit state:

- title changes to `Add Relay` or `Edit Relay`
- fields: `Host`, `Port`
- primary action: `Save Relay`
- secondary action: `Cancel`
- validation errors use the existing endpoint validation language where possible

R-RELAY-009. Removing a host must require a confirmation if removal would leave
zero configured hosts.

R-RELAY-010. Saved app config must remain only a hosts list of `{host, port}`.
Relay identity stays Mac-side in relay status metadata.

R-RELAY-011. Relay settings changes must update the same host registry used by
Dock, System Health, Archive Cleanup, and Archived Threads.

### 8.1 Relay Settings ASCII Mockup

```text
---------------------------------------------------------
                 Relay Settings                     [x]

[ Run check ]                                  [ Add Relay ]

+-------------------------------------------------------+
| Amir-M5                                      Online    |
| amir-m5.fairy-salmon.ts.net:4510                      |
| 12 sessions - last checked now                         |
| [ Test ]                                      [ Edit ] |
+-------------------------------------------------------+

+-------------------------------------------------------+
| Home                                         Online    |
| home.fairy-salmon.ts.net:4510                         |
| 4 sessions - last checked 1m ago                       |
| [ Test ]                                      [ Edit ] |
+-------------------------------------------------------+

---------------------------------------------------------
```

Add Relay state:

```text
---------------------------------------------------------
                    Add Relay                       [x]

Host
[ home.fairy-salmon.ts.net                         ]

Port
[ 4510                                             ]

[ Cancel ]                              [ Save Relay ]
---------------------------------------------------------
```

## 9. Archive Cleanup Requirements

### 9.1 Entry Points

R-CLEAN-001. More menu item `Archive cleanup` opens the Archive Cleanup sheet.

R-CLEAN-002. Archive Cleanup is not a root tab.

R-CLEAN-003. Archive Cleanup must be able to scan more rows than the daily Dock
feed page limit. The daily Dock must keep its fast capped load behavior.

R-CLEAN-004. Archive Cleanup must not make the Dock screen load all historical
threads just to render the daily feed.

### 9.2 Preview State

R-CLEAN-010. Archive Cleanup opens in preview mode.

R-CLEAN-011. The title is `Archive Cleanup`.

R-CLEAN-012. Subtitle is `Preview before anything moves`.

R-CLEAN-013. The age selector contains:

- `30d`
- `90d`
- `1y`
- `Custom`

R-CLEAN-014. Default selected age is `90d`.

R-CLEAN-015. Selecting `Custom` opens a `Custom Age` subview inside the same
Archive Cleanup sheet's internal `NavigationStack`.

R-CLEAN-016. `Custom Age` uses a numeric days field, not a calendar date.

R-CLEAN-017. `Custom Age` field rules:

- label: `Days`
- numeric input only
- minimum: `1`
- maximum: `3650`
- default value: previous custom value when available, otherwise `180`
- validation copy: `Enter 1-3650 days.`

R-CLEAN-018. `Custom Age` actions:

- `Cancel`: returns to Archive Cleanup without changing the current threshold
- `Apply`: saves the custom day count, returns to Archive Cleanup, updates the
  selector label to `Custom: Nd`, and recomputes preview

R-CLEAN-019. Exclusion toggles are visible and default on:

- `Exclude pinned`
- `Exclude running`
- `Exclude needs input`
- `Exclude Watch label`

R-CLEAN-020. A candidate count summary is shown before any archive operation.

R-CLEAN-021. The candidate count summary must include:

- total candidate count
- selected age threshold
- host count

R-CLEAN-022. A host split is shown before any archive operation.

R-CLEAN-023. A short preview list is shown before any archive operation.

R-CLEAN-024. Preview rows must include:

- title
- host
- repo or workspace
- branch
- last activity date
- any exclusion reason if excluded from action

R-CLEAN-025. The footer contains:

- secondary action `Review list`
- primary action `Archive N`
- safety text `Restore from Archived Threads`

R-CLEAN-026. `Restore from Archived Threads` is a link. Activating it replaces
the active Archive Cleanup sheet with Archived Threads.

R-CLEAN-027. `View all` in the preview list is an alias for `Review list`.
Activating it pushes Review List inside the Archive Cleanup sheet.

R-CLEAN-028. Tapping a host split row pushes Review List filtered to that host.
The user can clear that host filter from Review List.

R-CLEAN-029. The primary archive button is disabled while preview is loading,
when candidate count is zero, or when any configured host is still loading.

R-CLEAN-030. Preview failure for one host must not discard successful host
results. Show partial preview with a host-level warning.

R-CLEAN-031. Preview failure for all hosts must show a failure state with:

- plain reason
- `Run check`
- `Relay settings`

### 9.3 Candidate Rules

R-CLEAN-040. Candidates are active, human-scope sessions. Agent/automation
sessions are out of scope for the first implementation.

R-CLEAN-041. Candidate last activity is based on `SessionSummary.lastActivity`.

R-CLEAN-042. The threshold is inclusive of rows older than the chosen age. A row
must be a candidate when:

```text
row.lastActivityDate < now - selectedAge
```

R-CLEAN-043. `Exclude pinned` removes rows where local metadata marks the row
pinned.

R-CLEAN-044. `Exclude running` removes rows with status `Running`.

R-CLEAN-045. `Exclude needs input` removes rows with status `Needs input` or
`Needs approval`.

R-CLEAN-046. `Exclude Watch label` removes rows whose local label is `Watch`.

R-CLEAN-047. Rows with `Error` status are included by default when older than
the threshold and not excluded by another rule. They must show an `Error` badge
in preview/review, and Review List must include a status filter so the user can
deselect or isolate them before archiving.

R-CLEAN-048. `Idle`, `Not loaded`, and `Unknown` rows can be candidates when
older than the selected threshold and not excluded for another reason.

R-CLEAN-049. Candidate rules must be computed from the same row projection model
used by Dock where possible, so pinned/watch/local metadata has one meaning.

### 9.4 Review List State

R-CLEAN-050. `Review list` pushes a Review List subview inside the same Archive
Cleanup sheet's internal `NavigationStack`.

R-CLEAN-051. The review list supports search across title, repo/workspace,
branch, host, summary, and thread ID where data is available.

R-CLEAN-052. The review list supports compact filters:

- host
- status
- label/exclusion
- branch or repo if cheap from current projection

R-CLEAN-053. Review list rows are selectable.

R-CLEAN-054. The default selection is all current candidates.

R-CLEAN-055. Excluded rows are visible only if the user enables an
`Excluded`/`Show excluded` filter.

R-CLEAN-056. The bottom bar updates selected count and action label:

```text
6,842 selected                         Archive 6,842
```

R-CLEAN-057. If the user deselects rows, the action label updates.

R-CLEAN-058. If the user selects zero rows, the archive action is disabled.

### 9.5 Confirmation and Execution

R-CLEAN-060. Starting bulk archive requires explicit user action on
`Archive N`.

R-CLEAN-061. If `N` is greater than 100, the app must show a confirmation step
before execution. The confirmation must repeat:

- count
- age threshold
- exclusions
- host split
- restore path

R-CLEAN-062. During execution, show progress:

- `Archiving X of N`
- current host or phase where useful
- successes
- failures
- `Stop remaining` option

R-CLEAN-063. `Stop remaining` stops work that has not started yet. In-flight
row archive requests may finish and must still be counted accurately.

R-CLEAN-064. The app must never report success for rows that failed.

R-CLEAN-065. Partial success shows:

- archived count
- failed count
- failed rows with reason
- action to retry failures
- action to open Archived Threads

R-CLEAN-066. Full success shows:

- archived count
- host split
- action `View archived`
- action `Done`

R-CLEAN-067. After successful archive, Dock refreshes so archived rows leave the
daily feed.

R-CLEAN-068. Archive Cleanup activity must update System Health `Archive`
category evidence.

R-CLEAN-069. First implementation must use the existing row-level
`thread/archive` contract with bounded concurrency and clear per-row result
tracking. A new server-side bulk archive protocol is out of scope for this
first implementation.

R-CLEAN-070. Bulk archive must not log prompt text, transcript text, raw
payloads, or secrets.

### 9.6 Archive Cleanup ASCII Mockup

Reference mockup:
`outputs/03-archive-cleanup-sheet.png`

```text
Dock is dimmed behind the sheet

---------------------------------------------------------
                 Archive Cleanup                    [x]
                 Preview before anything moves

Older than
[ 30d ] [ 90d ] [ 1y ] [ Custom ]

+-------------------------------------------------------+
| 6,842 threads older than 90 days      2 hosts          |
+-------------------------------------------------------+

[x] Exclude pinned   [x] Exclude running
[x] Exclude needs input   [x] Exclude Watch label

By host
+-------------------------------------------------------+
| Amir-M5                                      4,913  > |
| Home                                         1,929  > |
+-------------------------------------------------------+

Preview (3 of many)                              View all
+-------------------------------------------------------+
| green  App-server ramp-up       Amir-M5 main Apr 15   |
| purple Playables audit          Home controls Apr 12   |
| orange Scene rendering plan     Amir-M5 feat  Apr 10   |
+-------------------------------------------------------+

[ Review list ]                         [ Archive 6,842 ]
          Restore from Archived Threads
---------------------------------------------------------
```

### 9.7 Archive Execution ASCII Mockups

Custom age:

```text
---------------------------------------------------------
< Archive Cleanup          Custom Age

Archive sessions older than:

Days
[ 180                                             ]

Enter a number from 1 to 3650.

[ Cancel ]                                    [ Apply ]
---------------------------------------------------------
```

Custom age validation:

```text
---------------------------------------------------------
< Archive Cleanup          Custom Age

Days
[ 0                                               ]

Enter 1-3650 days.

[ Cancel ]                                    [ Apply disabled ]
---------------------------------------------------------
```

Review list:

```text
---------------------------------------------------------
< Archive Cleanup          Review List

6,842 candidates selected
[ Search candidates                                  ]

[ All hosts v ] [ Status v ] [ Label v ] [ Branch v ]

Older than 90 days - exclusions applied

+-------------------------------------------------------+
| (x) green  App-server ramp-up        Amir-M5  Apr 15  |
|     codex-client - main - Idle                       |
| (x) purple Playables audit           Home    Apr 12   |
|     gw_controls - controls-cleanup - Not loaded       |
| ( ) red    CLI timeout repair        Amir-M5 Apr 09   |
|     codex-client - fix/timeout - Error                |
+-------------------------------------------------------+

6,841 selected                         [ Archive 6,841 ]
---------------------------------------------------------
```

Confirmation:

```text
---------------------------------------------------------
                 Archive 6,842 threads?             [x]

This will archive active human sessions older than 90 days.

Included:
- Amir-M5: 4,913
- Home: 1,929

Excluded:
- pinned
- running
- needs input / needs approval
- Watch label

You can restore them from Archived Threads.

[ Cancel ]                              [ Archive 6,842 ]
---------------------------------------------------------
```

Progress:

```text
---------------------------------------------------------
                 Archive Cleanup                    [x]

Archiving 1,240 of 6,842
[======================-----------------------------]

Succeeded: 1,238
Failed: 2
Current host: Amir-M5

[ Stop remaining ]
---------------------------------------------------------
```

Partial completion:

```text
---------------------------------------------------------
                 Archive Cleanup                    [x]

Archived 6,803 threads.
39 failed and stayed in Dock.

+-------------------------------------------------------+
| thread-abc  Home   transport closed                  |
| thread-def  Amir   request timeout                   |
+-------------------------------------------------------+

[ Retry failed ]       [ View archived ]       [ Done ]
---------------------------------------------------------
```

Full completion:

```text
---------------------------------------------------------
                 Archive Cleanup                    [x]

Archived 6,842 threads.

Amir-M5: 4,913
Home: 1,929

[ View archived ]                         [ Done ]
---------------------------------------------------------
```

## 10. Archived Threads Requirements

### 10.1 Entry Points

R-ARCHIVED-001. More menu item `Archived threads` opens Archived Threads.

R-ARCHIVED-002. Archive Cleanup completion action `View archived` opens
Archived Threads.

R-ARCHIVED-003. Archived Threads is not a root tab.

### 10.2 Layout and Behavior

R-ARCHIVED-010. The title is `Archived Threads`.

R-ARCHIVED-011. Header summary includes:

- total archived count loaded for configured hosts
- host count

R-ARCHIVED-012. The sheet includes a full-width search field:

```text
Search archived threads
```

R-ARCHIVED-013. Compact filter chips include:

- `All hosts`
- one chip per configured host when space allows
- `Last archived` or equivalent sort chip

R-ARCHIVED-014. The sheet includes a visible selection/restore toolbar:

- `Select`
- `Restore selected`

R-ARCHIVED-014A. `Restore selected` in the toolbar is disabled when selection
mode is off or when zero rows are selected.

R-ARCHIVED-014B. Tapping `Select` enters selection mode and changes the toolbar
action to `Cancel`.

R-ARCHIVED-014C. Tapping `Cancel` exits selection mode, clears selected rows,
and leaves search/filter state unchanged.

R-ARCHIVED-015. Rows are grouped by archive/last-activity date buckets, such as:

- `Today`
- `This week`
- `April 2026`

R-ARCHIVED-016. Rows show:

- title
- repo or workspace
- branch
- host
- archived or last-activity date
- visible restore button

R-ARCHIVED-017. Single row restore remains visible.

R-ARCHIVED-018. Selection mode supports batch restore.

R-ARCHIVED-019. Selection mode bottom bar shows:

- selected count
- primary action `Restore N`

R-ARCHIVED-019A. `Restore selected` and bottom `Restore N` run the same restore
operation. The bottom action is the primary thumb-reachable action; the toolbar
action is a secondary convenience action.

R-ARCHIVED-019B. Both restore actions are disabled when zero rows are selected.

R-ARCHIVED-020. Restore success removes rows from the archived list and
refreshes Dock.

R-ARCHIVED-021. Restore partial failure keeps failed rows in Archived Threads
and shows reasons.

R-ARCHIVED-022. Batch restore execution shows progress:

- `Restoring X of N`
- successes
- failures
- `Stop remaining` option

R-ARCHIVED-022A. `Stop remaining` stops restore work that has not started yet.
In-flight restore requests may finish and must still be counted accurately.

R-ARCHIVED-023. Batch restore full success shows restored count and action
`Done`.

R-ARCHIVED-024. Batch restore partial success shows restored count, failed
count, failed rows, `Retry failed`, and `Done`.

R-ARCHIVED-025. Archived Threads search/filter must work locally on loaded rows.
Remote archived search is out of scope for the first implementation.

R-ARCHIVED-026. Archived Threads must preserve the existing
`.archivedHuman` load path but must not force the old root Archive tab to remain.

### 10.3 Archived Threads ASCII Mockup

Reference mockup:
`outputs/04-archived-threads-sheet.png`

```text
Dock is dimmed behind the sheet

---------------------------------------------------------
                 Archived Threads                   [x]

+-------------------------------------------------------+
| 2,138 archived                 Across 2 hosts          |
+-------------------------------------------------------+

[ Search archived threads                              ]

[ All hosts v ] [ Amir-M5 ] [ Home ] [ Last archived v ]

[ Select ]                              [ Restore selected ]

Today
+-------------------------------------------------------+
| (x) App-server ramp-up     codex-client main          |
|     Amir-M5 - archived 2026-05-27 18:14         undo  |
| ( ) UI polish pass        codex-ui refactor           |
|     Home - archived 2026-05-27 16:42            undo  |
+-------------------------------------------------------+

This week
+-------------------------------------------------------+
| (x) Playables audit       gw_controls controls-cleanup |
| ( ) Rate-limit tuning     codex-server perf/tuning    |
| (x) Docs search improvements docs-site search         |
+-------------------------------------------------------+

April 2026
+-------------------------------------------------------+
| ( ) Background sync stabilization                     |
| ( ) Agent onboarding flow                             |
+-------------------------------------------------------+

3 selected                                      [ Restore 3 ]
---------------------------------------------------------
```

Batch restore progress:

```text
---------------------------------------------------------
                 Archived Threads                   [x]

Restoring 2 of 3
[=========================--------------------------]

Succeeded: 2
Failed: 0

[ Stop remaining ]
---------------------------------------------------------
```

Batch restore partial completion:

```text
---------------------------------------------------------
                 Archived Threads                   [x]

Restored 2 threads.
1 failed and stayed archived.

+-------------------------------------------------------+
| thread-def  Home   transport closed                  |
+-------------------------------------------------------+

[ Retry failed ]                              [ Done ]
---------------------------------------------------------
```

## 11. State Requirements

### 11.1 Common Sheet States

Every new task sheet must support these states when applicable:

- idle
- loading
- loaded
- empty
- partial
- failed
- executing
- completed

R-STATE-001. Loading states must show a spinner or progress affordance plus a
plain label.

R-STATE-002. Empty states must explain what the empty result means and provide
one useful action when possible.

R-STATE-003. Failed states must show the failure reason, a retry action, and a
path to System Health or Relay Settings when the failure could be connectivity.

R-STATE-004. Partial states must keep successful data visible and clearly label
which host or operation failed.

R-STATE-005. Sheets must not silently close on failure.

### 11.2 Archive Cleanup States

Archive Cleanup loading preview:

```text
Archive Cleanup
Loading candidate preview...
```

Archive Cleanup empty:

```text
Archive Cleanup
No threads match this cleanup rule.

Try a longer age window or turn off an exclusion.
```

Archive Cleanup partial:

```text
Archive Cleanup
6,842 candidates found.
Home could not be checked: transport closed.

[ Run check ] [ Relay settings ]
```

Archive Cleanup failed:

```text
Archive Cleanup
Could not load cleanup preview.
All configured hosts failed.

[ Try again ] [ System Health ] [ Relay settings ]
```

### 11.3 Archived Threads States

Archived Threads empty:

```text
Archived Threads
No archived threads found.

Archived sessions will appear here after cleanup or row archive.
```

Archived Threads failed:

```text
Archived Threads
Could not load archived threads.

[ Try again ] [ System Health ]
```

### 11.4 System Health States

System Health no evidence:

```text
System Health
Waiting for first check.

[ Run check ]
```

System Health diagnostic fetch failed:

```text
System Health
Diagnostics endpoint could not be reached.
Dock feed may still be online.

[ Run check ] [ Copy doctor command ] [ Relay settings ]
```

## 12. Accessibility Requirements

R-A11Y-001. All new buttons must have accessibility labels.

R-A11Y-002. Icon-only buttons must have labels:

- More
- Close
- Restore
- Run check
- Relay settings

R-A11Y-003. The More menu must be reachable through VoiceOver.

R-A11Y-004. Sheet titles must be exposed as headers.

R-A11Y-005. Status badges must expose text, not color only.

R-A11Y-006. Selection state in Archived Threads and cleanup review must be
spoken as selected/not selected.

R-A11Y-007. Destructive bulk archive confirmation must be reachable and
understandable with VoiceOver.

R-A11Y-008. Dynamic type should not cause text overlap. Long titles and branches
must truncate or wrap only in the row body, not over controls.

## 13. Automation and Test ID Requirements

R-AUTO-001. Existing stable automation IDs should be preserved where the
underlying concept still exists.

R-AUTO-002. The old root tab IDs may be removed only if tests and docs move to
the new surfaces.

R-AUTO-003. Add automation IDs for:

- Dock More button
- More menu commands if possible
- System Health sheet root
- System Health run check
- System Health relay settings action
- System Health copy doctor command action
- Relay Settings sheet root
- Archive Cleanup sheet root
- Archive Cleanup age selector
- Archive Cleanup exclusion toggles
- Archive Cleanup review list action
- Archive Cleanup bulk archive action
- Archive Cleanup progress and completion states
- Archived Threads sheet root
- Archived Threads search field
- Archived Threads select button
- Archived Threads restore selected button
- Archived Threads row restore button

R-AUTO-004. Automation values for bulk actions must include count and major
state where useful, but must not include prompt text, transcript text, or
secrets.

## 14. Data and Contract Requirements

R-DATA-001. Daily Dock active load remains capped by
`CodexDockConstants.Dock.activeSessionMaxPages`.

R-DATA-002. Archive Cleanup uses a separate full-scan query or data path so it
can evaluate stale candidates without changing daily Dock performance.

R-DATA-003. Archive Cleanup full scan must be user-initiated by opening the
sheet or changing cleanup criteria.

R-DATA-004. Candidate preview must load configured hosts concurrently, matching
the existing archive host-load pattern where possible.

R-DATA-005. Bulk archive execution must track per-row result:

- pending
- running
- succeeded
- failed(reason)
- skipped(reason)

R-DATA-006. Bulk archive execution must track per-host totals.

R-DATA-007. Bulk archive must use bounded concurrency. The exact concurrency
limit belongs in `CodexDockConstants.swift` if it is production behavior.

R-DATA-008. Archived Threads may use the existing `.archivedHuman` query path.

R-DATA-009. Batch restore must use bounded per-row `thread/unarchive` calls.
A new server-side bulk restore protocol is out of scope for this first
implementation.

R-DATA-010. `System Health` must not invent health. It must derive health from:

- `AppConnectivityStore`
- route diagnostics snapshots
- Dock store observations
- Archive store observations
- host settings/test observations
- voice/detail observations already reported to connectivity

R-DATA-011. Raw diagnostics should remain available to logs/diagnostic surfaces,
but the main sheet must show categorized status first.

R-DATA-012. All WebSocket URLs must remain `ws://` or `wss://`, include a host,
and must not contain username/password credentials.

R-DATA-013. Saved app config must still contain only `{host, port}` values.

## 15. Security and Privacy Requirements

R-SEC-001. Do not log `OPENAI_API_KEY`.

R-SEC-002. Do not log bearer tokens.

R-SEC-003. Do not log prompt text.

R-SEC-004. Do not log transcript text.

R-SEC-005. Do not log full JSON-RPC payloads.

R-SEC-006. `Copy doctor command` must not include secrets.

R-SEC-007. Relay identity remains Mac-side. Do not persist phone-side
`relayInstanceID` or `CODEX_DOCK_RELAY_INSTANCE_ID`.

R-SEC-008. Bonjour TXT records must remain non-secret.

## 16. Performance Requirements

R-PERF-001. Removing the tab bar must not make Dock slower to launch or refresh.

R-PERF-002. Archive Cleanup full scans must not run on app launch.

R-PERF-003. Archive Cleanup full scans must not run on every Dock refresh.

R-PERF-004. Archive Cleanup preview should show progress for large accounts.

R-PERF-005. Bulk archive must not freeze the main thread.

R-PERF-006. Batch restore must not freeze the main thread.

R-PERF-007. Search/filter in Archived Threads and cleanup review should be local
and responsive for thousands of loaded rows.

R-PERF-008. UI publication should follow existing rendering constants and
patterns; do not add unbounded main-thread row publishes.

## 17. Error Copy Requirements

Use plain copy that tells the user the meaning before the internal evidence.

Required copy examples:

- `Archive has no recent app traffic yet.`
- `It will update after Archive opens or cleanup runs.`
- `Dock feed works. Voice is failing on Home.`
- `Could not load cleanup preview.`
- `All configured hosts failed.`
- `39 failed and stayed in Dock.`
- `You can restore them from Archived Threads.`

Avoid default-first copy like:

- `No route evidence yet`
- `routesz failed`
- `thread/list failed`
- `unknown`

Those raw terms may appear in expanded technical details or copied diagnostics,
not as primary labels.

## 18. Flow Specifications

### 18.1 Flow: Open More Menu

```text
Start: Dock loaded.

1. User taps ellipsis More button.
2. Compact menu opens.
3. User sees Archive cleanup, Archived threads, System health, Relay settings.
4. User taps outside menu.
5. Menu closes; Dock state is unchanged.

Acceptance:
- no bottom root tab bar appears
- More menu does not navigate away by itself
- Dock scroll position is preserved
```

### 18.2 Flow: Open System Health From Connectivity Chip

```text
Start: Dock loaded with connectivity chip.

1. User taps Online/Partial/Offline chip.
2. System Health sheet opens.
3. Sheet refreshes diagnostics.
4. Top summary shows categorized health.
5. Host cards show per-host status.
6. User closes sheet.
7. Dock remains on the same lens/filter/search state.

Acceptance:
- same surface opens from More -> System health
- no raw route-only sheet appears as the default view
```

### 18.3 Flow: Run Health Check

```text
Start: System Health sheet open.

1. User taps Run check.
2. Summary and host cards enter Checking where relevant.
3. App fetches safe diagnostics and uses existing store observations.
4. Healthy routes become Healthy.
5. Passive-only routes without traffic remain Not checked.
6. Failures show plain-language effect and next action.

Acceptance:
- passive-only routes are not invoked just to produce health
- diagnostics fetch failure does not erase a stronger app-critical failure
```

### 18.4 Flow: Open Relay Settings

```text
Start: Dock or System Health.

1. User chooses Relay settings.
2. Relay Settings sheet opens.
3. Saved hosts are shown first.
4. User taps Add Relay.
5. Add form appears.
6. User saves valid host/port.
7. Host registry updates.
8. Dock/System Health/Archive surfaces use the updated registry.

Acceptance:
- editor is not permanently visible when not editing
- saved config stays host/port only
- when opened from System Health, Relay Settings is pushed inside that sheet,
  not stacked as a second modal
```

### 18.5 Flow: Preview Archive Cleanup

```text
Start: Dock loaded.

1. User opens More -> Archive cleanup.
2. Archive Cleanup sheet opens.
3. 90d is selected.
4. Exclusion toggles are on.
5. App loads full active human session scan for cleanup only.
6. Candidate count, host split, and preview rows appear.
7. User changes age or exclusions.
8. Preview recomputes.
9. User taps Custom.
10. Custom Age subview opens.
11. User enters valid day count and taps Apply.
12. Preview recomputes using `Custom: Nd`.

Acceptance:
- no rows are archived during preview
- daily Dock load limit is unchanged
- host failures are shown without hiding successful hosts
- invalid Custom values show `Enter 1-3650 days.`
```

### 18.6 Flow: Review Cleanup List

```text
Start: Archive Cleanup preview loaded.

1. User taps Review list.
2. Review state opens.
3. All candidates are selected.
4. User searches or filters.
5. User deselects rows.
6. Selected count and Archive N button update.
7. User taps back.
8. Archive Cleanup preview keeps the current threshold and exclusions.

Acceptance:
- selected count is exact
- excluded rows are not accidentally selected by default
- user can return to preview without archiving
```

### 18.7 Flow: Execute Bulk Archive

```text
Start: Archive Cleanup review or preview with N selected.

1. User taps Archive N.
2. If N > 100, confirmation appears.
3. User confirms.
4. Progress state appears.
5. App archives selected rows with bounded concurrency.
6. Each row records succeeded or failed.
7. Completion state appears.
8. Dock refreshes.

Acceptance:
- failed rows remain unarchived
- completion numbers match row results
- System Health Archive evidence updates
```

### 18.8 Flow: Open Archived Threads

```text
Start: Dock, More menu, or cleanup completion.

1. User opens Archived Threads.
2. Sheet loads archived rows for configured hosts.
3. Header count and host count appear.
4. User searches, filters, or scrolls grouped rows.
5. User restores one row or enters selection mode.

Acceptance:
- old root Archive tab is not required
- row restore still works
- partial host failure keeps available rows visible
```

### 18.9 Flow: Batch Restore

```text
Start: Archived Threads loaded.

1. User taps Select.
2. User selects rows.
3. Bottom bar shows N selected.
4. User taps Restore N.
5. App restores selected rows with bounded concurrency.
6. Progress state appears.
7. Successful rows leave Archived Threads.
8. Dock refreshes.
9. Failed rows remain with reasons.

Acceptance:
- no successful restore is reported for failed rows
- restore result is visible before sheet closes
```

### 18.10 Flow: Row-Level Archive Still Works

```text
Start: Dock row visible.

1. User opens row context menu.
2. User taps Archive.
3. App archives that row using existing row command path.
4. Dock refreshes.
5. Archived Threads can find/restore the row.

Acceptance:
- existing row-level archive tests still pass or are replaced with equivalent
  coverage
```

## 19. Verification Requirements

These are requirements for the implementation plan, not commands already run by
this requirements pass.

R-TEST-001. For root navigation and Dock changes, use
`rtk swift test --filter DockStoreTests` as the first Swift check where store
logic changes.

R-TEST-002. For app-server client, DTO, JSON-RPC, archive, or diagnostics
contract changes, use:

```sh
rtk swift test --filter AppServerClientTests
```

R-TEST-003. For relay scripts under `scripts/dock-relay*.mjs`, use:

```sh
rtk npm run test:relay
```

R-TEST-004. For connectivity store or diagnostics display model changes, add or
update targeted Swift tests around `AppConnectivityStoreTests` and
`DiagnosticsLoggingTests`.

R-TEST-005. For archive cleanup candidate rules, add focused tests that prove:

- age threshold behavior
- pinned exclusion
- running exclusion
- needs input / needs approval exclusion
- Watch label exclusion
- host split counts
- partial host failure behavior

R-TEST-006. For batch archive execution, add tests that prove:

- all success
- partial failure
- no false success for failed rows
- bounded command path uses expected thread IDs
- Dock refresh happens after successful mutations

R-TEST-007. For Archived Threads batch restore, add tests that prove:

- single restore still works
- batch restore all success
- batch restore partial failure
- Dock refresh after success

R-TEST-008. For generated Xcode project or installed UI behavior changes, use
Makefile-owned commands only:

```sh
rtk make app SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
```

R-TEST-009. If physical-phone proof is required and available, use Makefile
device targets only. If physical Mobile MCP reports
`WebDriverAgent is not running on device`, stop retrying physical Mobile MCP and
record that exact blocker.

R-TEST-010. If a check cannot run because Xcode, simulator, device, signing,
services, or env vars are missing, report the exact command skipped and exact
blocker.

## 20. Acceptance Checklist

The feature is not done until all items below are true.

Product behavior:

- [x] Bottom root tab bar is gone from daily Dock.
- [x] Dock still opens as the primary first screen after relay bootstrap.
- [x] More menu exposes Archive cleanup, Archived threads, System health, and
      Relay settings.
- [x] Connectivity chip opens System Health.
- [x] System Health shows category rollups before raw route evidence.
- [x] Relay settings are reachable but not permanent root navigation.
- [x] Archive Cleanup can preview stale active sessions older than selected age.
- [x] Archive Cleanup default is 90d with all four exclusions on.
- [x] Archive Cleanup can review, select, confirm, execute, and report results.
- [x] Archived Threads can search/filter/select/restore archived rows.
- [x] Existing row-level archive and restore behavior is preserved.
- [x] Dock refreshes after archive/restore changes.

Safety:

- [x] Bulk destructive action has preview and confirmation.
- [x] Partial failures are visible and not counted as success.
- [x] No secrets or raw payloads are logged.
- [x] Saved relay config remains host/port only.
- [x] Passive-only routes are not auto-probed unsafely.

Quality:

- [x] New UI states are testable with automation IDs.
- [x] Store/data logic is separated from SwiftUI view layout.
- [x] Production constants live in `CodexDockConstants.swift`.
- [x] No new hard-coded production timeout/page/concurrency constants outside
      constants files.
- [x] Tests cover candidate rules, batch archive, batch restore, and health
      category display model.
- [x] Relevant `rtk` checks pass or exact blockers are recorded.

Review gates requested by user:

- [x] Requirements doc reviewed in fresh Cursor Agent Composer 2.5 Fast.
- [x] ArcStep auto-plan creates an exhaustive implementation/test plan.
- [x] Implementation plan reviewed in fresh Cursor Agent Composer 2.5 Fast.
- [x] ArcStep auto-implement/implement-loop completes implementation and tests.
- [x] Thermonuclear code quality review runs before any commit/push decision.

Completion evidence:

- Requirements review:
  `/tmp/fresh-consult/codex-dock-requirements-rereview-20260530T212535Z-OnGlop/final.txt`
  reported `VERDICT: pass-with-notes` and `BLOCKING: none`.
- ArcStep ready gate:
  `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_ARCHITECTURE_PLAN_2026-05-30.md`
  reported `READY next=implement-loop`.
- Final plan review:
  `/tmp/fresh-consult/codex-dock-plan-finalcheck2-20260530T215302Z-kpCkh9/final.txt`
  reported `VERDICT: pass` and `BLOCKING: none`.
- Implementation/test proof: `rtk swift test --filter SystemHealthProjectorTests`
  passed 4 tests, `rtk swift test` passed 320 tests with 5 expected skips, and
  `rtk make app-test SIM='iPhone 17'` exited 0.
- Final static proof: `rtk git diff --check` passed, and live app/test/README
  grep found no stale root-tab API or bottom-tab references.
- Thermonuclear review gate ran before any commit/push decision; findings and
  fixes are recorded in
  `docs/CODEX_DOCK_ARCHIVE_RELAY_SPACE_RECLAIM_ARCHITECTURE_PLAN_2026-05-30_WORKLOG.md`.

## 21. Composer Review Contract

The fresh Composer 2.5 Fast review must answer this question:

Does this requirements doc fully and unambiguously specify the intended user
journey, flows, look and feel, states, acceptance criteria, and links back to
the generated mockups and worklog?

Composer should fail the requirements if:

- the chosen information architecture is ambiguous
- any required flow is missing
- any destructive cleanup path lacks preview/confirmation/result handling
- System Health still relies on raw route evidence as the primary UX
- Relay settings remains a permanent root tab
- Archived Threads recovery is not discoverable
- the ASCII mockups are insufficient for implementation planning
- requirements contradict the referenced mockups or worklog
