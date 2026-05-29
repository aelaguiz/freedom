# Codex Dock Status Labels

Date: 2026-05-29

This note records what the visible `Needs me` and `Partial` labels mean in
Codex Dock, where they come from, and which parts are app-defined versus
Codex-defined.

## `Needs me`

`Needs me` is not a native Codex thread status. It is a Codex Dock UI label.

The real input state is:

- `SessionStatus.active(activeFlags:)`
- with `activeFlags` containing either `waitingOnApproval` or
  `waitingOnUserInput`

The Swift model defines those flags in
`CodexDock/Models/SessionSummary.swift`. `SessionSummary.needsAttention`
returns true when an active session has either flag.

The row projector turns that into the visible dock row state:

- `CodexDock/State/SessionRowProjector.swift`
- `status(for:)`
- active plus `waitingOnApproval` or `waitingOnUserInput` becomes
  `DockRowStatusKind.needsMe`
- active without those flags becomes `DockRowStatusKind.running`

The visible label itself is defined in:

- `CodexDock/State/DockStore.swift`
- `DockRowStatusKind.needsMe.label == "Needs me"`
- `DockTabID.needsMe.title == "Needs me"`

The `Needs me` tab includes only human-interactive rows whose projected row
status is `.needsMe`. The `Running` tab also includes `.needsMe`, so these rows
can appear in both places.

### How the relay can synthesize it

The relay can add attention flags for active live rows when the raw row does
not already carry them.

That logic is in `scripts/dock-relay-thread-data.mjs`:

- `pendingRequestsForActiveThread(...)` resumes the thread with
  `excludeTurns: true`
- it waits briefly for server requests tied to that `threadId`
- `attentionFlagsForServerRequest(...)` maps certain server request methods to
  `waitingOnApproval` or `waitingOnUserInput`
- `mergeActiveFlags(...)` writes those flags back into the row

Methods currently mapped to `waitingOnApproval`:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`
- `applyPatchApproval`
- `execCommandApproval`

Methods currently mapped to `waitingOnUserInput`:

- `item/tool/requestUserInput`
- `mcpServer/elicitation/request`
- `item/tool/call`
- `account/chatgptAuthTokens/refresh`
- `attestation/generate`

The first two `waitingOnUserInput` methods are clearly user-input style
requests. The last three are more questionable as a blanket rule unless every
one of those requests is genuinely user-blocking in practice.

## `Partial`

The orange top-level `Partial` label is not a row status, not a Codex thread
status, and not the voice transcription "partial" concept.

It is the global app connectivity/load rollup:

- `CodexDock/State/AppConnectivityStore.swift`
- `AppConnectivityOverallStatus.partial(String)`
- visible label: `"Partial"`
- attached message: the string stored in `.partial(...)`

In plain English, top-level `Partial` means:

> Codex Dock has some usable data, but the overall app state is not clean
> because at least one configured host, dock scope, or live overlay is failing
> or degraded.

### When it appears

The app rolls per-host state into one global status in
`AppConnectivityStore.rollup(...)`.

It returns `Partial` in two main cases:

1. Every host is "online-like", but at least one host is itself partial.

   Example: a host loaded rows, but one scope failed. The global status becomes
   `Partial` with a message like:

   - `<host display name>: Agents: offline`
   - `<host display name>: Dock: Dock unreachable`
   - `<host display name>: Live status disabled`

2. Some hosts are online-like, and at least one configured host is not.

   Example: two hosts are configured. One loads successfully, and the other is
   offline or timing out. The global status becomes `Partial` with the failing
   host's message, because the app is usable but not fully healthy.

If all configured hosts are offline or errored, the rollup becomes `Offline` or
`Error` instead of `Partial`.

### Where host partial comes from

`DockStore` produces `DockHostLoadStatus.partial(rowCount:message:)` when it
has usable rows for a host but some part of the load failed.

That happens when:

- the human dock scope loads but the agents scope fails
- the agents scope loads but the human dock scope fails
- live status overlay data is degraded, such as `Live status disabled`

The partial host subtitle is:

```text
<rowCount> sessions, partial: <message>
```

`AppConnectivityStore.record(...)` converts that host load status into
`HostConnectivityPhase.partial(message)`, and the global rollup can then show
top-level `Partial`.

### Why it is orange

The color comes from `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift`.

`GlobalConnectivityIndicatorView` maps these overall statuses to orange:

- `partial`
- `reconnecting`
- `backgrounded`
- `resuming`
- `stale`

So the orange `Partial` pill means "degraded but not dead", not "everything is
offline".

### Why the pill feels vague

The visible top pill only shows `store.overallStatus.label`, which is just
`Partial`.

The useful detail is in `store.overallStatus.message`, and the view currently
puts that message into the accessibility value. If the normal UI only shows the
word `Partial`, the human-visible screen is hiding the part that explains the
problem.

The actionable UI issue is that `Partial` should expose its message in a normal
visible place, or the pill should open the host/scope detail that already has
the message.

## Current interpretation

`Needs me` means "Codex Dock believes this active human-interactive session is
waiting for approval or user input."

`Partial` at the top means "Codex Dock loaded enough to be usable, but at least
one configured host or one part of the dock load is unhealthy."

