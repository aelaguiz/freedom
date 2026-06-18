# Codex Dock New And Fork Session Architecture Plan

Date: 2026-06-06
Status: architecture plan, not implemented
Work log: `docs/CODEX_DOCK_NEW_AND_FORK_SESSION_ARCHITECTURE_2026-06-06_WORKLOG.md`

## Direct Answer

Add one app-facing "session launch" command path owned by the Dock relay and
DockStore. That command supports two launch kinds: start a new Codex thread and
fork an existing Codex thread.

The phone still talks only to the Dock relay on `:4510`. The relay maps the
single app command to upstream Codex `thread/start` or `thread/fork`, writes the
normal Dock card projection, returns the projected card, and Swift opens the
existing `SessionDetailView`.

## Stop Boundary

This document is research and architecture only. Do not implement the feature
as part of this plan-writing pass.

## North Star

A user can create a new Codex session or fork the selected session from inside
Codex Dock without learning app-server internals, choosing a transport, or
waiting for a hidden refresh. The new row appears through the same Dock card
projection as every other human thread, and opening it uses the existing Thread
Detail and composer path.

## Done-State Requirements

- Dock Home has a visible New Session action. It is not buried in the More menu.
- A human app-facing row and its detail screen expose Fork as a contextual
  action.
- New Session and Fork open the same small launch sheet. The sheet shows host,
  working directory, and observed branch context, with advanced fields hidden.
- The app sends one typed relay command with a `clientSessionCommandId`.
- The relay owns idempotency, validation, host routing, upstream method choice,
  and projection refresh.
- The relay uses upstream Codex `thread/start` for new threads and
  `thread/fork` by `threadId` for forks.
- The relay never asks the phone to connect to raw authenticated app-server
  `:4500`, pass OpenAI keys, or choose relay-side secrets.
- The relay returns a normal `DockThreadCardDTO` for the created/forked thread
  and also writes/emits that card through the same Dock projection path.
- Swift opens the normal `SessionDetailView` for the returned row.
- If the user typed a first prompt in the launch sheet, Swift seeds the normal
  composer draft. It does not auto-send the prompt during launch.
- The existing `thread/message/send` path remains the only app path that sends
  user message text to Codex.
- The plan does not create a second session list, second projection model, or
  direct Swift route to upstream Codex internals.

## Non-Requirements

- Do not implement cross-host or cross-relay forks. A fork is host-scoped.
- Do not support upstream path-based fork in the app. The upstream schema marks
  path forking unstable and says `threadId` is preferred.
- Do not make the phone mutate git state, run `git checkout`, or guarantee that
  a displayed branch name is still the current branch at launch time. The app
  can pass `cwd`; Codex captures actual git state when the new thread starts.
- Do not expose model/provider/permissions/sandbox choice in the first visible
  flow. Defaults should come from the Mac-side Codex/app-server configuration.
- Do not auto-send the launch-sheet draft. Message sending stays on
  `thread/message/send` to preserve the existing idempotent message path and to
  avoid logging or transporting prompt text through a new command.
- Do not restore the old raw `ws://127.0.0.1:4500` phone path.

## Evidence Read

### Swift App

- `CodexDock/AppServer/AppServerMethods.swift` currently lists detail, Dock,
  archive, rename, message, turn, and transcription routes, but no session
  create/fork route.
- `CodexDock/AppServer/TurnDTO.swift` has `TurnStartParams` and
  `ThreadMessageSendParams`; both require `threadId`, so they cannot create a
  missing thread.
- `CodexDock/AppServer/ThreadDTO.swift` already models `forkedFromId`, `cwd`,
  `gitInfo`, `threadSource`, and `sessionId`.
- `CodexDock/Commands/ClientCommandEngine.swift` owns app commands for archive,
  rename, user-message send, and server-request response.
- `CodexDock/State/DockStore.swift` owns Dock mutations, host resolution,
  stream reconciliation, local metadata, and row publication. It is the right
  Swift owner for launch.
- `CodexDock/State/ThreadDetailStore.swift` owns message sending inside an
  existing thread and requires an existing `row.threadID`.
- `CodexDock/Runtime/ClientRuntime.swift` is the injection point for DockStore
  command clients.
- `CodexDock/Features/Dock/DockView.swift` already has one navigation path:
  `openDetail(row:)` creates a `ThreadDetailStore` and shows
  `SessionDetailView`.
- `CodexDock/Features/Dock/DockTaskMenuView.swift` contains More menu actions
  only; New Session does not belong there.
- `CodexDock/Features/Dock/DockRowContextMenu.swift` contains row actions and
  is the right Dock-row surface for Fork.
- `CodexDock/Features/Session/SessionDetailView.swift` already has a toolbar
  action area and already displays a Fork pill for forked rows.
- `CodexDock/State/ThreadCardRowProjector.swift` maps
  `DockThreadCardDTO.relationship == .forked` into row relationship `.forked`.
- `CodexDock/AppServer/DockThreadCardDTO.swift` already carries
  `relationship`, `forkedFromID`, `workingDirectory`, `repository`, and
  `branch`.

### Relay

- `scripts/dock-relay.mjs` dispatches app-facing methods but has no start/fork
  session command today.
- `scripts/dock-relay-user-message-command.mjs` is the command pattern to
  follow: validate, assert app-facing human thread, route through active
  session or registry, persist idempotency, and return a typed command result.
- `scripts/dock-relay-app-server-registry.mjs` can route existing-thread
  methods to a live owner or history app-server. It needs a host-level history
  route for new starts and a fork-safe route for existing source threads.
- `scripts/dock-relay-state-store.mjs` already stores the normal Dock card
  projection with `working_directory`, `relationship`, and `forked_from_id`.
- `scripts/dock-relay-state-engine.mjs` already reconciles
  `thread/started` notifications into Dock cards. Launch commands should also
  trigger the same projection update after the upstream response.
- `scripts/dock-relay-observability-contract.mjs` owns route-health metadata.
  The new app-facing route must be listed there and tested.

### Codex/App-Server

- Local CLI: `codex-cli 0.136.0-alpha.2`.
- Running managed Mac app-server: `0.132.0`.
- Generated schemas from both local CLI and managed app-server include
  `thread/start` and `thread/fork`.
- `ThreadStartParams` has no required fields in JSON schema. It accepts optional
  `cwd`, model/provider/service tier, permissions/sandbox, instructions,
  `ephemeral`, `sessionStartSource`, `threadSource`, environments, and dynamic
  tools.
- `ThreadForkParams` requires `threadId`. Optional path forking is explicitly
  unstable; the schema says to prefer `threadId`.
- `ThreadStartResponse` and `ThreadForkResponse` both return a required
  `thread`.
- Upstream `Thread` carries `id`, `sessionId`, `forkedFromId`, `cwd`,
  `gitInfo`, `threadSource`, status, and timestamps.

### UX Sources

- Apple Human Interface Guidelines, Buttons: buttons should be easy to
  recognize, prominent style should be limited, and toolbar buttons are for
  contextual actions in the current view.
  https://developer.apple.com/design/human-interface-guidelines/buttons
- Apple Human Interface Guidelines, Toolbars: toolbars provide convenient access
  to frequently used commands and actions for the view's content.
  https://developer.apple.com/design/human-interface-guidelines/toolbars
- Apple Human Interface Guidelines, Context menus: context menus are hidden, so
  their items should also be available in the main interface; they should stay
  relevant and short.
  https://developer.apple.com/design/human-interface-guidelines/context-menus
- Apple Human Interface Guidelines, Sheets: sheets fit scoped tasks that need
  specific information before returning to the parent view.
  https://developer.apple.com/design/human-interface-guidelines/sheets
- Apple Human Interface Guidelines, Action sheets: action sheets are for
  choices related to an intentional action.
  https://developer.apple.com/design/human-interface-guidelines/action-sheets
- UXPin progressive disclosure guide, 2026: show only what matters first and
  reveal complex options on demand.
  https://www.uxpin.com/studio/blog/what-is-progressive-disclosure/
- Microsoft confirmation guidance: avoid routine confirmations; use them for
  risky, consequential, hard-to-undo, or frequently mistaken actions.
  https://learn.microsoft.com/en-us/windows/win32/uxguide/mess-confirm

## Architecture Decision

Use one app-facing command: `thread/session/launch`.

The app-facing route is not upstream Codex. It is the Dock product command,
like the existing `thread/message/send` command. It carries a stable
`clientSessionCommandId`, a launch `kind`, and the minimal context needed to
launch. The relay maps it to upstream `thread/start` or `thread/fork`.

Do not expose raw `thread/start` and `thread/fork` as two separate phone-owned
paths. That looks canonical at the method-name level, but it would force Swift
and app-facing route health to duplicate validation, idempotency, projection,
navigation, and retry semantics. The canonical upstream method names still
exist inside the relay, where routing and version skew already belong.

## App-Facing Command Contract

Add `AppServerMethods.threadSessionLaunch = "thread/session/launch"`.

Swift request shape:

```swift
public struct ThreadSessionLaunchParams: Codable, Equatable, Sendable {
    public let clientSessionCommandId: String
    public let kind: ThreadSessionLaunchKind
    public let hostContext: ThreadSessionLaunchHostContext?
    public let start: ThreadSessionStartLaunchParams?
    public let fork: ThreadSessionForkLaunchParams?
}
```

The relay validates the invariant:

- `kind == .start` requires `start` and forbids `fork`.
- `kind == .fork` requires `fork.sourceThreadId` and forbids `start`.
- `clientSessionCommandId` is required for both kinds.
- `cwd` is optional and must be a relay-side safe string. The relay forwards it
  only when non-empty.
- `threadSource` should be `"user"` when the upstream version accepts it.
- `initialDraft` is not part of this command. It remains local Swift state.

Swift response shape:

```swift
public struct ThreadSessionLaunchResponseDTO: Codable, Equatable, Sendable {
    public let clientSessionCommandId: String
    public let kind: ThreadSessionLaunchKind
    public let state: ThreadSessionLaunchState
    public let thread: ThreadDTO?
    public let card: DockThreadCardDTO?
    public let sourceThreadId: String?
    public let upstreamMethod: String?
    public let error: String?
}
```

The success state must include both `thread` and `card`. Swift navigates from
the `card`, not from a hand-built row. This keeps Dock display tied to
`DockThreadCardDTO`.

## Relay Architecture

Add `scripts/dock-relay-session-launch-command.mjs` with one exported engine:
`RelaySessionLaunchCommandEngine`.

The engine owns:

- parameter validation
- launch-kind invariant validation
- stable JSON payload hashing
- idempotency persistence
- upstream endpoint selection
- upstream method selection
- upstream response normalization
- Dock card projection upsert
- route-health and structured logging
- safe relay errors

### Relay Routing

For `kind: "start"`:

- ensure `AppServerRegistry` is ready
- route to the selected history app-server endpoint through a registry helper,
  for example `routeForSessionLaunch({ kind: "start" })`
- call upstream `thread/start`
- forward only stable upstream fields, initially `cwd` and `threadSource`
- omit model/provider/permissions/sandbox unless a later explicit design adds
  them behind advanced controls

For `kind: "fork"`:

- validate `sourceThreadId` is a human app-facing thread using
  `assertHumanThreadID`
- route through the same registry helper, for example
  `routeForSessionLaunch({ kind: "fork", sourceThreadId })`
- treat upstream `thread/fork` as live-owner-preferred, matching existing
  thread methods that should use an attachable live owner when present
- fall back to the history app-server when there is no live owner
- if a known private owner shadows the source thread and no attachable live
  owner is available, block the fork unless a future code proof demonstrates
  that history forking is current and safe for that owner state
- call upstream `thread/fork` with `threadId: sourceThreadId`
- pass `excludeTurns: true` unless the app genuinely needs turns in the launch
  response; Thread Detail will load turns through the existing detail route

Do not scatter this routing logic in the command engine. The command engine
asks the registry for a route; the registry owns history endpoint selection,
live-owner preference, and private-owner blocking.

### Relay Idempotency

Add a relay state-store table for session launch commands, for example
`session_launch_commands`.

The table records:

- `host_id`
- `client_session_command_id`
- `kind`
- canonical payload hash
- state
- source thread id
- created thread id
- upstream method
- upstream endpoint URL
- last error code/message
- created/updated timestamps

Rules:

- same `clientSessionCommandId` plus same payload returns the existing result
  and never creates a duplicate thread
- same `clientSessionCommandId` plus different payload returns a collision
  error before any upstream call
- ambiguous transport failure records an ambiguous state and does not blindly
  replay on automatic reconnect
- a later retry with the same id can return the stored result if a created
  thread has been observed by projection
- if an existing command already has `created_thread_id` or a projected card,
  retry returns that card and never calls upstream again
- if an existing command is `failedAmbiguous`, retry first reconciles the Dock
  projection for the expected created thread when known; if no created thread
  is found, return the ambiguous command state instead of replaying upstream
- if an existing command is `submittedUpstream` without a created thread id,
  retry reconciles projection and returns either the observed card or the
  nonterminal command state; it does not call upstream again
- only a fresh command record that has never attempted upstream submission may
  call upstream
- if a user wants to intentionally create another new/forked thread after an
  ambiguous result, that is a new launch command with a new
  `clientSessionCommandId`

This mirrors the existing retry discipline in `thread/message/send`.

### Projection Update

After upstream returns `thread`:

1. Normalize the upstream thread through the existing relay thread-card
   canonicalization path.
2. Upsert the card into `relayStateStore.upsertThreadCard`.
3. Emit the normal `dock/update` change for subscribers.
4. Return the same `DockThreadCardDTO` in
   `ThreadSessionLaunchResponseDTO.card`.
5. Schedule ordinary reconciliation so the row converges with history/live
   truth if the immediate upstream response was partial.

There must be no separate launch-result row model in relay.

### Observability And Logs

Add `thread/session/launch` to
`scripts/dock-relay-observability-contract.mjs`.

Route health should record:

- app-facing route: `thread/session/launch`
- upstream method: `thread/start` or `thread/fork`
- route source: history, live-owner, or active-session when applicable
- result state: created, duplicate, collision, failed definite, failed
  ambiguous

Do not log prompt text, initial drafts, bearer tokens, OpenAI keys, raw JSON-RPC
payloads, or full upstream responses.

## Swift Architecture

### Command Client

Extend the existing command-client pattern instead of adding route calls inside
views.

Add:

- `ThreadSessionLaunchCommanding`
- `AppServerThreadSessionLaunchClient`
- `ThreadSessionLaunchParams`
- `ThreadSessionLaunchResponseDTO`
- `ClientSessionCommandID`

`AppServerThreadSessionLaunchClient` should use
`AppServerHostConnector().withConnectedClient(for:)`, matching
`AppServerThreadCommandClient`.

`ClientCommandEngine` should gain a session launcher dependency and one method:

```swift
func launchSession(
    _ launch: ThreadSessionLaunchRequest,
    on host: DockHostConfiguration
) async throws -> ThreadSessionLaunchResponseDTO
```

This keeps view code from choosing JSON-RPC routes.

### DockStore Owner

`DockStore` should own launch state and expose one public method:

```swift
@discardableResult
public func launchSessionInBackground(
    _ request: DockSessionLaunchRequest
) -> Bool
```

`DockSessionLaunchRequest` is the UI-level request:

- `kind: .start | .fork`
- `host`
- optional source row
- optional `cwd`
- observed branch/repository text for display only
- optional local `initialDraft`

DockStore responsibilities:

- resolve the host using existing host identity rules
- generate one `ClientSessionCommandID`
- call `ClientCommandEngine.launchSession`
- project returned `DockThreadCardDTO` through `ThreadCardRowProjector`
- publish/update the Dock snapshot so the row is visible immediately
- return the row, or publish an action error

Do not put launch in `ThreadDetailStore`. Thread Detail has no valid thread row
until launch succeeds.

### Row Context

Add `workingDirectory` to `DockRowViewModel`, populated from
`DockThreadCardDTO.workingDirectory`.

Why:

- `repository` is display text and can be a repo name, not an absolute path.
- upstream `thread/start.cwd` needs a working directory path.
- the launch sheet must not fake branch context from display-only text.

The branch label is display/context only. The actual branch is whatever Git
reports in `cwd` when Codex starts the new thread.

### UI Flow

Dock Home:

- Add a visible toolbar button using a plus/compose-style icon for New Session.
- Keep More menu for secondary app tasks: archive cleanup, archived threads,
  system health, and relay settings.
- In branch-grouped views, optionally expose a small "New Session" icon in the
  branch group header only when the group has an unambiguous host and
  `workingDirectory`.
- If the toolbar action has no row or branch-group context, the launch sheet
  must show "Default workspace" and omit `cwd` from the relay command. Do not
  synthesize a path from `repository`, `branch`, search text, or display labels.

Row:

- Add Fork to `DockRowContextMenu`.
- Add New Session Here only if the source row has a usable `workingDirectory`.
  This is secondary to the visible toolbar action and can be deferred if the
  first slice already supports branch-context creation through group headers.

Detail:

- Add a toolbar Fork icon beside Rename.
- Keep the existing Fork pill as status display only.

Launch sheet:

- One sheet component for both New Session and Fork.
- Title reflects kind: "New Session" or "Fork Session".
- Show host, working directory, and observed branch.
- Optional draft text field.
- Advanced disclosure is collapsed by default.
- Primary button says "Create" for new and "Fork" for fork.
- Disable primary while the command is in flight and show progress.
- No routine confirmation.

After success:

- Dismiss sheet.
- Open the returned row with existing `openDetail(row:)`.
- If `initialDraft` is non-empty, seed the existing composer draft after the
  detail store is created.

## Error Model

Validation errors:

- missing `clientSessionCommandId`
- invalid launch kind combination
- missing source thread for fork
- source thread is not app-facing human
- source thread belongs to another host
- no usable endpoint for selected host
- private unattachable owner blocks fork

User-facing behavior:

- show inline sheet error while the sheet is still open
- do not create a local fake row on definite failure
- on ambiguous failure, keep the command id and offer Retry; retry uses the
  same id
- once a created card is observed, retry returns/navigates to that row instead
  of creating another thread

## Implementation Slices

These slices are for future implementation. They are ordered depth-first so the
highest-risk relay-to-Codex seam is proven early.

### Slice 1: Relay Command, Projection, Node Tests

- Add `thread/session/launch` dispatch in `scripts/dock-relay.mjs`.
- Add `RelaySessionLaunchCommandEngine`.
- Add idempotency storage.
- Add `AppServerRegistry.routeForSessionLaunch`.
- Normalize returned upstream thread into `DockThreadCardDTO`.
- Upsert and emit through existing Dock projection.
- Add route-health metadata and tests.
- Add relay tests for duplicate command id, payload collision, ambiguous
  delivery without double-create, start routing to history, fork routing to live
  owner, fork fallback to history, and private-owner fork blocking.

Proof:

```bash
rtk npm run test:relay
rtk npm run contract:check
```

### Slice 2: Swift DTO And DockStore Command Path

- Add Swift DTOs and method constant.
- Add `ThreadSessionLaunchCommanding`.
- Add `AppServerThreadSessionLaunchClient`.
- Inject launcher through `ClientRuntime.makeDockStore`.
- Add DockStore launch state and returned-card projection.
- Add `workingDirectory` to `DockRowViewModel`.

Proof:

```bash
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
```

### Slice 3: UI Shell

- Add New Session toolbar action.
- Add shared launch sheet.
- Add Fork in row context menu and detail toolbar.
- On success, reuse `openDetail(row:)`.
- Seed the existing composer draft when provided.

Proof:

```bash
rtk make app-test SIM='iPhone 17'
```

### Slice 4: Real Relay Proof

- Run the feature against the normal relay-backed simulator path.
- Prove the created/forked row appears through `dock/subscribe` or
  `dock/update`, then opens through normal Thread Detail.
- Compare both normal relays after deployment.

Proof:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17'
rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
```

If implementation adds controlled simulator scenarios or root bug docs, also
update `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` and run:

```bash
rtk npm run test:docs
```

## Side Doors To Keep Closed

- No direct Swift call to raw upstream `thread/start` or `thread/fork`.
- No app-facing raw `turn/start` for initial prompts.
- No fake local row that bypasses relay projection.
- No path-based fork from Swift.
- No phone-supplied OpenAI keys, bearer tokens, model-provider secrets, or raw
  app-server endpoint details.
- No direct physical-phone path to raw `:4500`.
- No completion claim based only on `/routesz`, `/statusz`, logs, screenshots,
  fixture rows, or `projection/witness/read`.

## Simplicity Check

Concepts added:

- one app-facing route: `thread/session/launch`
- one relay engine: `RelaySessionLaunchCommandEngine`
- one idempotency record family: session launch commands
- one Swift command client/protocol: `ThreadSessionLaunchCommanding`
- one UI sheet: launch sheet
- one extra row field: `workingDirectory`

Concepts reused:

- upstream `thread/start`
- upstream `thread/fork`
- app-facing relay command pattern from `thread/message/send`
- `AppServerRegistry`
- `relayStateStore.upsertThreadCard`
- `DockThreadCardDTO`
- `ThreadCardRowProjector`
- `DockStore`
- `SessionDetailView`
- `thread/message/send` for actual message text

Concepts intentionally not added:

- no second card projection
- no raw upstream route selection in Swift
- no separate fork detail screen
- no first-prompt auto-send path
- no branch mutation path
