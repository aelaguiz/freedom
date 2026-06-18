# Codex Dock New And Fork Session Architecture Work Log

Date: 2026-06-06
Scope: research and architecture planning only; no implementation.

## Goal

Design the simplest canonical architecture for starting new Codex sessions and
forking existing sessions from inside the Codex Dock app, without bifurcated
code paths. Research must cover UX, Swift app flow, Node Dock relay flow, and
the Codex/app-server layer before implementation planning begins.

## Live Log

### 2026-06-06 Initial Setup

- Confirmed required style: `$eli10` for all user-facing updates and final
  replies.
- Confirmed required gates: `$plan-audit` and `$fresh-consult` with Cursor
  Composer 2.5 Fast.
- Confirmed hard stop: do not implement code for new or forked sessions in this
  goal.
- Created this live work log before deep research to preserve the research
  trail.

### 2026-06-06 Repo Orientation Pass

- Read `README.md`, `Makefile`, `Package.swift`, `package.json`, and the source
  inventory.
- Confirmed the app-facing service is the Dock relay on `:4510`; the iPhone
  does not connect directly to raw Codex app-server endpoints.
- Confirmed Swift renders Dock and Archive cards from relay-owned `dock/*` and
  `archive/*` streams, while the relay may use raw upstream Codex routes
  internally.
- Confirmed existing proof commands that will matter to the eventual plan:
  `rtk npm test`, `rtk make sim-ui-sync-proof SIM='iPhone 17'`,
  `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'`, and
  `rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.

### 2026-06-06 Continuation After Relay Deploy Request

- Confirmed the branch and relays were already pushed/deployed at
  `8e9a55b0f2f53943328464bf3cdf8eb450a3d380`.
- Resumed the architecture-only goal with no implementation changes.
- Re-read `$plan-audit` and `$fresh-consult` entry instructions so the final
  plan will be audited as a plan-readiness artifact and checked by Cursor
  Composer 2.5 Fast as requested.
- Confirmed current untracked research artifacts are this worklog and an
  unrelated `.arch_skill/...` directory; they must not be treated as deployed
  feature code.

### 2026-06-06 Swift App Research Pass

- Read the current Swift DTOs and command path:
  `CodexDock/AppServer/AppServerMethods.swift`,
  `CodexDock/AppServer/TurnDTO.swift`,
  `CodexDock/AppServer/ThreadDTO.swift`,
  `CodexDock/AppServer/AppServerClient.swift`,
  `CodexDock/Commands/ClientCommandEngine.swift`,
  `CodexDock/State/AppServerThreadCommandClient.swift`,
  `CodexDock/State/AppServerThreadDetailSession.swift`, and
  `CodexDock/State/ThreadDetailStore.swift`.
- Finding: current phone-facing Swift routes include existing-thread work
  (`thread/message/send`, `turn/start`, `turn/steer`, detail subscribe/resync,
  archive, unarchive, rename), but no `thread/start` or `thread/fork`.
- Finding: `TurnStartParams` and `ThreadMessageSendParams` both require
  `threadId`, so creating a session cannot be represented as a normal composer
  send to a missing thread.
- Read `CodexDock/State/DockStore.swift`,
  `CodexDock/Runtime/ClientRuntime.swift`, `CodexDock/Features/Dock/DockView.swift`,
  `CodexDock/Features/Dock/DockTaskMenuView.swift`,
  `CodexDock/Features/Dock/DockRowContextMenu.swift`,
  `CodexDock/Features/Session/SessionDetailView.swift`, and
  `CodexDock/Features/Session/ComposerView.swift`.
- Finding: `DockStore` is the right Swift owner for creating/forking session
  rows because it already owns Dock mutations, host resolution, local metadata,
  stream reconciliation, and detail navigation refreshes.
- Finding: `ThreadDetailStore` should remain the owner of messages inside an
  existing thread; it should not learn how to create threads.
- Finding: existing display code already understands forked rows through
  `DockThreadCardDTO.relationship`, `forkedFromID`,
  `DockRowThreadRelationship.forked`, row badges, and the detail Fork pill.

### 2026-06-06 Relay And Codex Protocol Research Pass

- Read relay routing and command code:
  `scripts/dock-relay.mjs`,
  `scripts/dock-relay-user-message-command.mjs`,
  `scripts/dock-relay-thread-data.mjs`,
  `scripts/dock-relay-app-server-registry.mjs`, and
  `scripts/dock-relay-state-views.mjs`.
- Finding: the relay dispatch exposes `thread/message/send`, archive,
  unarchive, rename, detail subscribe/resync, Dock/Archive streams, Realtime
  transcription, `turn/start`, and `turn/steer`, but no app-facing
  `thread/start` or `thread/fork`.
- Finding: `RelayUserMessageCommandEngine` is the canonical pattern for command
  ownership: validate input, assert human-thread visibility, route to active or
  ephemeral upstream, persist idempotent command state, return a typed response,
  and let relay projection catch up.
- Finding: `AppServerRegistry` can currently route existing-thread methods, but
  unsupported methods fall through. `thread/start` needs a host-level route to
  the selected history daemon; `thread/fork` needs an existing-thread route to
  the source owner/history endpoint.
- Generated Codex app-server schemas into scratch:
  `/tmp/codex-client/codex-app-server-schema-20260606T125242Z` from local
  `codex-cli 0.136.0-alpha.2` and
  `/tmp/codex-client/codex-managed-app-server-schema-20260606T125327Z` from the
  running managed Mac app-server binary `0.132.0`.
- Finding: both local CLI and managed Mac app-server schemas contain
  `thread/start` and `thread/fork`. `home` also reports schema support for
  `thread/start` and `thread/fork`.
- Finding: `thread/start` accepts optional `cwd`, model/provider/service tier,
  permissions/sandbox, instructions, `ephemeral`, `sessionStartSource`, and
  `threadSource`; it returns `ThreadStartResponse` with a canonical `thread`.
- Finding: `thread/fork` accepts required `threadId`, optional path/overrides,
  and `excludeTurns`; it returns the same response shape and the returned
  `Thread` carries `forkedFromId`.
- Finding: `routesz` currently exposes 32 app-facing routes and no app-facing
  create/fork session command. Later architecture work resolves this as one
  app-facing `thread/session/launch` route, not two phone-owned raw upstream
  routes.

### 2026-06-06 Side-Door And Test Surface Pass

- Searched app, relay, tests, contracts, and docs for `thread/start`,
  `thread/fork`, `ThreadStart`, `ThreadFork`, `forkedFrom`, `routesz`,
  user-message command routes, and Dock/Archive streams.
- Finding: no production app-facing `thread/start` or `thread/fork` route
  exists today in Swift or relay. Existing `thread/started` handling is
  notification/projection plumbing, not a phone command surface.
- Finding: relay state already persists `working_directory`, `relationship`,
  and `forked_from_id` in `scripts/dock-relay-state-store.mjs`, so new/forked
  sessions should reuse the existing card projection cache instead of adding a
  second session list.
- Finding: `scripts/dock-relay-state-engine.mjs` already turns upstream
  `thread/started` notifications into Dock card reconciliation. The planned
  command path should explicitly trigger the same projection update after the
  upstream response, because a create/fork command cannot depend on a live
  subscription event arriving before the app needs to navigate.
- Finding: `scripts/dock-relay-observability-contract.mjs` owns `/routesz`
  route metadata. Adding the app-facing launch route must update this contract
  and its tests so route health does not silently drift.
- Finding: `scripts/dock-relay-user-message-command.test.mjs` already proves
  idempotent relay commands and rejects raw `turn/start` without
  `clientUserMessageId`. A create/fork command must use the same retry-safe
  command discipline because upstream `thread/start` and `thread/fork` create
  new threads and are not safe to blindly replay.
- Finding: `CodexDockTests/DockStoreTests.swift` already covers DockStore
  multi-host loading, branch grouping, and optimistic row mutations. Future
  Swift create/fork tests belong there, not in `ThreadDetailStoreTests`, because
  create/fork changes the Dock row set before a detail composer exists.
- Finding: `CodexDockTests/AppServerClientTests.swift` is the current suite for
  typed JSON-RPC request methods. Future `ThreadSessionLaunchParams` and
  `ThreadSessionLaunchResponseDTO` should be proven there.

### 2026-06-06 UX Research Pass

- Researched current Apple Human Interface Guidelines pages for buttons,
  toolbars, menus, context menus, sheets, and action sheets. Apple guidance
  supports: visible toolbar buttons for frequent view actions, one or two
  prominent actions per view, context menus only for item-relevant commands,
  and sheets for scoped tasks that require a small amount of user input.
- Researched progressive disclosure guidance. The practical takeaway for this
  app is: show the essential create/fork path first, keep advanced fields
  hidden behind an explicit advanced disclosure, and do not make users answer
  model/permissions/path questions unless the default is unsafe or ambiguous.
- Researched confirmation guidance. The takeaway is: do not confirm routine
  create/fork actions. Confirmations are justified for destructive, risky, or
  hard-to-undo actions; create and fork are constructive and can show inline
  progress/error feedback instead.
- UX conclusion: "New Session" should be a visible `+`/compose-style toolbar
  action in Dock Home, not buried in the existing More menu. "Fork" should be
  available from the row context menu and the detail toolbar because it is
  directly tied to a selected source thread. Both should open the same small
  launch sheet with context already filled in.
- UX conclusion: the launch sheet should show host, workspace, branch, and a
  simple optional first draft. Advanced fields such as model, provider,
  permissions, sandbox, `excludeTurns`, or workspace-root overrides should stay
  hidden unless explicitly expanded.
- UX conclusion: the first implementation should create/fork the thread and
  navigate to the normal `SessionDetailView`. If the user entered an initial
  prompt, seed the normal composer draft instead of auto-sending it. This keeps
  all message delivery on the existing idempotent `thread/message/send` path.

### 2026-06-06 Current Relays

- During this research, Amir asked for the current pushed app to be available
  for manual testing.
- Confirmed no new tracked implementation changes were available to commit.
- Confirmed current pushed commit `8e9a55b0f2f53943328464bf3cdf8eb450a3d380`
  was deployed/refreshed on both normal relays:
  `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`.
- Confirmed cross-relay compare passed with report
  `/tmp/codex-client/relay-host-compare-20260606T124926Z.json`.

### 2026-06-06 Architecture Plan Draft

- Wrote `docs/CODEX_DOCK_NEW_AND_FORK_SESSION_ARCHITECTURE_2026-06-06.md`.
- Key architecture decision: add one app-facing relay command,
  `thread/session/launch`, with launch kinds `start` and `fork`. The relay maps
  that command to upstream Codex `thread/start` or `thread/fork` internally.
- Reason for one app-facing command: create/fork need the same Swift owner,
  relay idempotency, host routing, projection upsert, retry behavior, and
  navigation path. Splitting them into two phone-owned raw upstream methods
  would create duplicate app code paths.
- Reason for keeping upstream methods inside the relay: generated Codex schemas
  already support `thread/start` and `thread/fork`, and the relay is already
  the boundary that handles Codex version skew, app-server discovery, live-owner
  routing, private-owner blocking, and projection normalization.
- Added plan constraints: no auto-send for launch-sheet drafts, no path-based
  fork, no branch mutation, no direct raw app-server path, no second projection
  model, and no completion proof from diagnostics-only routes.

### 2026-06-06 Fresh Consult Pass 1

- Ran `$fresh-consult` with Cursor Agent Composer 2.5 Fast:
  `runtime=agent`, `model=composer-2.5-fast`, `effort=encoded-in-model`.
- Chain directory:
  `/tmp/fresh-consult/codex-dock-session-launch-20260606T130709Z-C0iJad`.
- Session id: `9d6760b8-2927-4548-8ae7-286c57bce1ec`.
- Verdict: `pass-with-notes`.
- Blocking findings: none.
- Composer agreed the core architecture is correct: one app-facing
  `thread/session/launch`, `DockStore` ownership, relay-side upstream mapping,
  `DockThreadCardDTO` return/upsert for navigation, and local composer draft
  only.
- Applied the non-blocking notes before audit:
  - added explicit retry/idempotency rules so an existing command id cannot
    double-create after ambiguous or submitted states;
  - named `AppServerRegistry.routeForSessionLaunch` as the routing owner for
    start/fork;
  - specified toolbar New Session with unknown working directory omits `cwd`;
  - fixed worklog wording that previously implied separate phone-facing
    `thread/start` and `thread/fork` routes.

### 2026-06-06 Fresh Consult Pass 2

- Resumed the same Cursor Agent Composer 2.5 Fast consult with captured session
  id `9d6760b8-2927-4548-8ae7-286c57bce1ec`.
- Turn 2 directory:
  `/tmp/fresh-consult/codex-dock-session-launch-20260606T130709Z-C0iJad/turn-02`.
- Verdict: `pass`.
- Blocking findings: none.
- Composer confirmed the prior notes were carried through: explicit
  no-double-create idempotency rules, centralized
  `AppServerRegistry.routeForSessionLaunch`, toolbar New Session omits `cwd`
  when unknown, and worklog route drift was fixed.
- Composer noted one harmless historical wording issue in this worklog around
  future `ThreadStartParams` / `ThreadForkParams`; updated that wording to
  `ThreadSessionLaunchParams` and `ThreadSessionLaunchResponseDTO`.

### 2026-06-06 Plan Audit Pass 1

- Ran `$plan-audit` in plan-readiness mode on
  `docs/CODEX_DOCK_NEW_AND_FORK_SESSION_ARCHITECTURE_2026-06-06.md`.
- Wrote audit log:
  `docs/CODEX_DOCK_NEW_AND_FORK_SESSION_ARCHITECTURE_2026-06-06_PLAN_AUDIT.md`.
- Verdict: `ready`.
- Blocking findings: none.
- Native subagents were not used because the available subagent tool is limited
  to cases where the user explicitly asks for sub-agents or delegation. The
  user explicitly requested `$fresh-consult`, so the Cursor Composer consult
  served as the independent architecture check.

### 2026-06-06 Coverage Ledger And Docs Guard

- Updated `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` with `COV-018` for the
  new/fork session launch failure class.
- The added gap states that implementation proof must cover idempotent relay
  launch, Swift `DockStore` behavior, focused app UI proof, and real
  relay-backed simulator proof before claiming the app behavior works.
- Preserved the existing unrelated swipe-archive coverage changes already
  present in that dirty file.
- Ran `rtk npm run test:docs`.
- Result: pass. The docs guard reported 3 tests, 0 failures.

## Open Questions To Resolve From Evidence

- Resolved: upstream Codex app-server supports `thread/start` and
  `thread/fork` today. Both local `codex-cli 0.136.0-alpha.2` schemas and the
  running managed Mac app-server `0.132.0` schemas include the methods.
- Resolved: forking should use upstream `thread/fork` by `threadId` whenever
  possible. The upstream schema says path-based forking is unstable and that
  `threadId` is preferred.
- Resolved: the relay, not Swift UI, should own routing to live owner versus
  history app-server endpoints. Swift should use typed relay commands against
  the normal `:4510` host.
- Resolved: the simplest UX is one shared launch sheet invoked as visible
  "New Session" from Dock Home and contextual "Fork" from a row/detail.
- Resolved: proof must include relay command tests, Swift typed DTO/store tests,
  and real relay-backed simulator proof before claiming user-visible app
  behavior is done.
