# Codex Dock iPhone UX Specification

Date: 2026-05-27
Status: MVP UX requirements and wireframe spec
Owner: aelaguiz
Audience: future Swift/iOS implementer

Supersession note, 2026-05-28: the personal physical-iPhone runtime now uses
the Mac-side relay plan in
`docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`. Any legacy "Hosts",
"Add Host", "Edit Host", token, or phone-side OpenAI-key language in this UX
wireframe should be read as the current Relay connection surface with no
phone-side secrets.

## 1. North Star

Build a simple iPhone client, "Codex Dock", for one operator to monitor and
interact with Codex sessions running on several personal computers.

The app is a mobile dock, not a replacement for the full Codex TUI. It should
answer one question fast:

> What is happening across my Codex sessions, which ones need me, and what can
> I do from my phone with one or two taps?

The MVP should feel like a calm operations board:

- one flat, scan-friendly feed
- grouped enough to make many sessions understandable
- tap into a thread when action is needed
- type or hold the mic to dictate a quick instruction in place
- archive completed sessions
- leave room for later host-side automation, without making that part of V1

It is personal software. It does not need account signup, team management,
enterprise permission screens, or a marketing surface.

## 2. Captured User Requirements

These are the requirements from the user prompt, normalized but intentionally
kept explicit so they are not lost during implementation.

### 2.1 Product And Platform

- Build a user-interface specification for a simple Swift client.
- The target client is an iPhone app.
- The app connects to multiple computers owned by the user.
- Each computer may run the Codex App Server.
- The app lets the user view and interact with individual Codex sessions from
  the iPhone.
- The repo is blank/new, so this document is the starting product spec.
- Save the requirements/spec as a new document in `docs/`.

### 2.2 Usage Grounding

- Read existing Codex sessions to understand the user's usage pattern.
- Inspect the home server too, because the user also runs Codex there.
- Assume Codex is used on several servers at once.
- The computers are reachable over the user's private network. Tailscale is
  just the current addressing layer and must not be deeply embedded into the
  product model.

### 2.3 Home Feed

- The interface should be very simple.
- It should show a view by server.
- It should probably be broken out by git branch.
- It should be one flat view that is neatly organized.
- It must not feel too crammed.
- It should allow quick swiping and navigation.
- It should make it easy to identify a thread quickly on the phone.

### 2.4 Thread Identity

- Provide easy ways to colorize threads.
- Provide easy ways to label threads.
- Labels/colors should help the user quickly identify a thread.

### 2.5 Thread Interaction

- The user can tap/click a thread.
- The user can type into a thread.
- The user can push to talk.
- Push-to-talk is not a separate screen in MVP.
- Push-to-talk happens in place from the session/thread screen composer.
- The user presses and holds the mic while speaking.
- When the user releases the mic, the app transcribes the audio into the same
  composer text box.
- The app must not submit the transcript automatically. The user can edit the
  transcribed text, then taps Send when ready.
- Push-to-talk should use OpenAI speech transcription through the Mac relay.
- Superseded on 2026-05-28: the OpenAI key stays in the Mac environment or repo
  `.env`; it is not embedded in, pasted into, stored by, or sent to the iPhone
  client.
- The user can manage Codex sessions while on the road.

### 2.6 Archive

- The user can swipe to archive a thread once done.
- The user can unarchive threads from some archive view.

### 2.7 Future Backends

- Assume other backends may be integrated later, such as Claude Code.
- Do not build those in the initial MVP.
- Do think about the UX model so future backends can fit without redesigning
  the whole app.

### 2.8 Scope Discipline

- Design a full requirements stack for user experience.
- Include wireframe mockups.
- Put implementation details mostly aside.
- Root the UX in what is possible through the Codex JSON-RPC protocol.
- Do not boil the ocean with features.
- Think depth-first for now.
- Keep it a simple user experience that can expand later.
- It is just for the user, so login/logout is not needed.
- Work until a plan-audit pass says the MVP UX is well-defined, not too broad,
  and likely workable.

### 2.9 AI Manager Account Rotation, Post-V1

- The user rotates many Codex accounts through AI Manager.
- `aim codex use` is the primary command the user uses to rotate Codex
  accounts.
- AI Manager is out of scope for V1.
- The current plan does not understand AI Manager deeply enough to specify a
  V1 implementation safely.
- Post-V1, do a separate AI Manager discovery pass before implementing account
  rotation.
- If account rotation is added later, assume the iPhone app can reach the host
  over SSH and should expose only a simple Rotate button, not command entry.
- The iPhone UI should not require the user to type, spell, or edit
  `aim codex use`.
- Do not manage AIMGR accounts or labels in this app. The only possible future
  scope is changing the active AIM account for Codex through the host-side
  tool.
- Existing mockups may continue to show Rotate affordances as exploratory
  future-state UI, but those affordances are not V1 requirements.

### 2.10 Approval And Sandbox Scope

- The user's normal Codex setup runs with dangerously skipped permissions /
  unsandboxed behavior.
- Because of that, command/file/permission approval UI is usually not on the
  critical path for this user.
- The app should still support a minimal approval interface because the Codex
  app-server API supports server-initiated approval requests.
- Do not overbuild approvals into a large policy or permission-management
  system.
- MVP approval UX should be limited to showing the request context and letting
  the user tap Approve, Deny, or Needs desktop.

## 3. Evidence Read

This spec is grounded in these current-state sources.

### 3.1 Codex App Server Protocol

Read: `docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md`.

Important protocol facts used by this spec:

- App-server is bidirectional JSON-RPC.
- The local daemon Unix socket is WebSocket-framed, not raw JSONL.
- A connection must send `initialize`, then `initialized`.
- Sessions are `Thread`s.
- Agent runs are `Turn`s.
- Work inside a turn arrives as `Item` notifications.
- `thread/start`, `thread/resume`, `thread/list`, `thread/loaded/list`,
  `thread/read`, `thread/archive`, `thread/unarchive`, `thread/name/set`,
  `turn/start`, `turn/steer`, and `turn/interrupt` map cleanly to the core
  mobile UX.
- Clients must keep reading notifications after requests.
- A serious client must not ignore server-initiated requests. For MVP, handle
  the common approval path with simple cards and show "Needs desktop" for
  unsupported request types.
- `thread/list`, `thread/read`, and `thread/turns/list` browse stored sessions
  but do not load them for continuation. To continue, call `thread/resume`,
  then `turn/start`.
- `thread/loaded/list` shows only in-memory loaded threads in one app-server
  process.
- One daemon can serve multiple clients, but thread subscriptions are
  connection-scoped.
- `account/rateLimits/read` exists for Codex account status.
- Filesystem, command, process, MCP, review, config, model, goal, realtime, and
  plugin surfaces exist, but most are out of MVP scope.

### 3.2 Local Codex Session Usage

Read through `agent-history` against local Codex history across all projects for
the last 7 days.

Relevant evidence:

- Local Codex had 1090 sessions in the last 7 days.
- Prompt extraction found 11311 prompt records in the last 7 days.
- Recent sessions include many read-only audits, implementation audits,
  plan-backed implementation goals, app-server research, and active `/goal`
  use.
- The user frequently launches parallel audit agents/sessions against the same
  repo areas.
- The user uses explicit goal pause/resume flows.
- The user asks recovery questions like which plan or file the current thread is
  operating from.
- The user interrupts or redirects agent turns when scope is off.

Implication for the UI:

- The app must optimize scanning many threads, not a small chat list.
- Status, repo, branch, labels, and "needs me" signals matter more than full
  transcript previews on the home feed.
- The detail view must make it easy to send a short correction or instruction.

### 3.3 Home Server Codex Usage

Read over SSH alias `home`, host `amir-server`.

Relevant evidence:

- `~/.codex/` exists on the home server.
- The home server has app-server daemon state under `~/.codex/app-server-daemon`.
- The home server has recent Codex session files on 2026-05-26 and 2026-05-27.
- The home server `~/.codex/history.jsonl` had 14750 rows at inspection time.
- Recent prompts show the same patterns: planning, implementation, branch work,
  corrections, rate-limit/account concerns, and status recovery.

Implication for the UI:

- Multi-host is not theoretical. The first screen must show host identity.
- Host health and Codex rate-limit state should be visible without opening
  every thread when the app-server exposes it.
- The app should tolerate one host being offline without blocking the rest of
  the feed.

### 3.4 AI Manager Usage, Discovery Needed

Read:

- `/Users/aelaguiz/workspace/agents/docs/AI_MANAGER_APP_REFERENCE.md`
- `~/workspace/agents/work/aimgr/repo/aimgr/README.md` on SSH alias `studio`
- `~/workspace/agents/work/aimgr/repo/aimgr/docs/codex-overnight-account-rotation-proposals-2026-05-23.md` on SSH alias `studio`

Important AI Manager facts captured for later:

- CLI name is `aim`.
- `aim codex use` is the primary command for rotating the active Codex account.
- `aim status` and `aim status --json` can report whether the Codex target is
  healthy and what happened during the last Codex selection.
- Codex account activation affects the next Codex process. It is not a live
  hot-swap for an already-running Codex process.

V1 implication:

- AI Manager is not in V1 scope.
- The current spec should not pretend to understand AI Manager deeply enough to
  implement it.
- Do not build AIMGR rotation, status parsing, account labels, or account
  selection in V1.

Post-V1 implication:

- The iPhone app should not invent account-management rules.
- If rotation is added later, the iPhone app should expose one primary host
  action over SSH: `aim codex use`.
- `aim status --json` is useful only as a lightweight status source. It must not
  turn the app into an account or label management UI.
- The UI should explain that rotation applies to the next Codex process unless
  a host-side process is already managing restart/resume.

## 4. MVP Definition

### 4.1 MVP Goal

The MVP is a personal iPhone dashboard and lightweight control surface for
already-running Codex app-server hosts.

It must support:

- multiple hosts
- session list
- branch/server grouping
- thread labels and colors
- thread detail view
- text reply
- push-to-talk reply
- minimal approval/request handling because the API supports it, not a deep
  permission-management surface
- swipe archive and archive recovery

### 4.2 MVP Non-Goals

The MVP does not include:

- user signup
- login/logout UX
- team accounts
- shared workspace permissions
- a rich permission-management system
- building or managing Tailscale
- a generalized SSH terminal
- full Codex TUI parity
- full filesystem browser
- full diff viewer
- review-mode authoring
- app/plugin/marketplace management
- custom MCP tool UIs beyond generic request cards
- Claude Code support as a working backend
- AI Manager integration
- AIMGR account rotation from the phone
- AIMGR status parsing
- automatic silent account rotation from the phone
- AIMGR account or label management
- explicit account-label picking
- AIMGR watch/tender controls
- live hot-swapping the account inside an already-running unmanaged Codex
  process

## 5. Product Model

### 5.1 Objects

Host:

- A computer the phone can reach.
- Examples: laptop, home server, Mac Studio.
- V1 has a display name, endpoint, health, optional SSH alias, and one or more
  Codex app-server connections.
- Post-V1 may add AIMGR availability after a separate discovery pass.

Backend:

- A session provider on a host.
- MVP backend: Codex App Server.
- Future backend: Claude Code or other agent runtime.

Thread:

- A Codex app-server thread/session.
- Has id, title, host, backend, cwd, repo name, git branch, archive state, loaded
  state, current turn state, last activity, and optional app-local label/color.

Turn:

- One active or completed Codex agent run inside a thread.

Item:

- A message, command execution, file change, reasoning summary, approval
  request, tool call, or output event inside a turn.

### 5.2 Backend-Neutral UX Principle

The UI should use "sessions" in the visual model where possible, with "Codex"
as a provider label. Do not over-abstract the MVP, but do not hard-code the
home feed around only Codex words if a neutral word is equally clear.

Examples:

- Good: "Sessions", "Needs me", "Running", "Archived", "Host".
- Good: provider pill says "Codex".
- Avoid: a top-level screen named "Codex Threads Forever" that makes future
  Claude Code support awkward.

## 6. Information Architecture

The app has three primary user-facing areas and one action surface.

1. Dock
   - Primary home feed.
   - Flat list grouped by host and branch.
   - Shows active, recent, and needs-attention sessions.

2. Session
   - Thread detail.
   - Shows messages/events and the input composer.
   - Handles text, push-to-talk, approvals, and interruption.

3. Archive
   - Browse archived sessions.
   - Unarchive by swipe or tap action.

4. Hosts
   - Small host settings/status area.
   - Add/edit host endpoint and SSH alias.
   - See app-server health.

Post-V1 rotation action surface

- Not part of V1.
- Not a tab if added later.
- Appears primarily as a Dock host/header or limited-row Rotate button.
- May also appear in the session overflow and Hosts screen.
- Tap-based AIMGR rotation runs `aim codex use` behind the button.
- The user should not have to type, spell, or edit shell commands from the
  phone.
- Existing mocks can keep this exploratory surface, but implementation should
  skip it for V1.

Recommended bottom navigation:

```text
Dock | Archive | Hosts
```

Do not add more tabs in MVP.

## 7. Visual And Interaction Principles

### 7.1 Overall Feel

- Quiet, dense enough for operations, not decorative.
- Built for repeated scanning on a phone.
- One-handed use should work for common actions.
- Prefer clear labels over clever visual metaphors.
- Use color sparingly and consistently.

### 7.2 Layout Density

The feed should show roughly 5 to 8 meaningful session rows on a standard
iPhone screen, depending on Dynamic Type size.

Rows should not be tiny. The app is for quick decisions while moving.

### 7.3 Status Over Transcript

Home rows should prioritize:

- needs attention
- running/idle/failed/limited
- host
- repo and branch
- user label/color
- last activity age
- last meaningful event summary

Do not show large transcript snippets on the Dock screen.

### 7.4 Color Use

Thread colors are user labels, not semantic statuses. Keep semantic status
separate.

Thread color:

- left rail or small swatch
- manually chosen
- stable per thread

Status color:

- small pill/dot
- system-defined
- consistent across hosts

Suggested semantic status mapping:

```text
Needs me      red
Running       blue
Idle          gray
Done          green
Limited       orange
Offline       gray with slash
Error         red
Archived      muted gray
```

### 7.5 Gestures

Dock row:

- Tap: open session.
- Swipe left: archive.
- Swipe right: quick label/color.
- Long press: quick actions.

Session screen:

- Pull down: refresh.
- Swipe from left edge: back to Dock.
- Tap and hold mic: push to talk in place on the session screen.
- Release mic: transcribe speech into the composer text box.
- Tap send: send typed/transcribed text only after the user explicitly submits.

Archive row:

- Swipe right or tap action: unarchive.

## 8. Main Wireframes

Wireframes are approximate iPhone portrait layouts. They describe hierarchy,
not pixel-perfect UI.

Scope note: these wireframes and generated mockups may still show AIMGR/Rotate
affordances from the exploration pass. Leave those visuals as-is for now, but
do not treat AI Manager rotation as a V1 implementation requirement.

### 8.1 Dock, Normal State

```text
+------------------------------------------------+
| Dock                                  + Host    |
| All  Needs me  Running  Limited                |
| Search sessions, repo, branch                  |
+------------------------------------------------+
| home                         Codex  AIM ready  |
| main
| | blue | Render geometry audit        Running  |
| |      | lessons_studio  main                 |
| |      | last: command output 2m ago          |
| | red  | Account rotation plan        Needs me |
| |      | aimgr  codex-rotation               |
| |      | approval requested 8m ago            |
| feature/animation-engine                         |
| | gold | Dart animation SSOT          Idle     |
| |      | lessons_studio  feature/...          |
| |      | last agent msg 19m ago               |
+------------------------------------------------+
| laptop                    Codex  AIM low Rotate|
| gw_controls                                     |
| | teal | Play vs AI preview           Limited  |
| |      | gw_controls  controls-cleanup        |
| |      | rate limit hit                 [Rotate]|
+------------------------------------------------+
| Dock              Archive              Hosts   |
+------------------------------------------------+
```

Notes:

- The screen is still one feed.
- Host headers and branch headers organize the feed.
- Branch headers are light separators, not separate pages.
- AIM status and the Rotate button are visible at host level when useful,
  especially on the Dock, but this is post-V1 exploration.
- The row's left color rail is the user's manual thread color.
- Status pills are separate from thread colors.

### 8.2 Dock, Needs-Me Filter

```text
+------------------------------------------------+
| Dock                                  + Host    |
| All  Needs me  Running  Limited                |
+------------------------------------------------+
| Needs me across 3 hosts                         |
|                                                |
| home / aimgr / codex-rotation                  |
| | red | Account rotation plan        Approval  |
| |      | Command approval requested            |
| |      | [Review] [Deny] [Approve]             |
|                                                |
| studio / agents / main                         |
| | blue | OpenClaw account audit      Input     |
| |      | Agent asked for a decision            |
| |      | [Open]                                |
|                                                |
| laptop / lessons_studio / feature/...          |
| | gold | Dart animation SSOT         Limited   |
| |      | Rotate active Codex account           |
| |      | [Rotate]                              |
+------------------------------------------------+
| Dock              Archive              Hosts   |
+------------------------------------------------+
```

Notes:

- Needs-me is the fastest mobile triage mode.
- Approval and rotate buttons can appear inline for one-tap handling.
- Approval UI stays minimal because the user's normal setup skips permission
  prompts, but the API can still request approvals.
- The Rotate button should not ask the user to type or spell `aim codex use`.
- Rotate is post-V1, not part of the V1 acceptance criteria.

### 8.3 Session Detail

```text
+------------------------------------------------+
| < Dock        Dart animation SSOT        ...    |
| home / lessons_studio / feature/animation      |
| Codex  Running  color: gold                    |
+------------------------------------------------+
| Agent                                           |
| I found the remaining Dart-owned recipe paths. |
|                                                |
| Command                                         |
| rtk rg "table.pocket_cards" apps/flutter       |
| output collapsed: 42 lines             [Open]  |
|                                                |
| Agent                                           |
| Next I need to patch the bridge and run the    |
| focused tests.                                 |
|                                                |
| Approval needed                                |
| Run command?                                   |
| rtk flutter test apps/flutter/test/...         |
| [Deny]                         [Approve]       |
+------------------------------------------------+
| Type message...              Hold mic   Send   |
+------------------------------------------------+
```

Notes:

- Command output is collapsed by default.
- Approval cards are first-class because the app-server protocol can stall
  without client responses.
- The composer stays simple.
- Push-to-talk does not open a blue modal or separate recording screen.
- While the mic is held, the composer can show an inline recording state.
- On release, transcription fills the composer text field.
- Voice becomes editable text before sending.
- The transcript must not auto-send in MVP.
- MVP uses OpenAI speech transcription through the Mac relay. The UI calls it
  "Dictate" or "Push to talk"; implementation should not expose provider/model
  names in the phone UI.
- Superseded on 2026-05-28: OpenAI transcription uses the Mac-side key from env
  or `.env`. The phone sends audio to the relay and never receives the key or
  chooses the OpenAI transcription model.

### 8.4 Archive

```text
+------------------------------------------------+
| Archive                                Search   |
| home  laptop  studio  all                       |
+------------------------------------------------+
| Yesterday                                      |
| | gray | App-server ramp-up          home      |
| |      | codex-client  main                    |
| |      | archived 2026-05-27 18:14             |
|                                                |
| | teal | Playables audit             laptop    |
| |      | gw_controls  controls-cleanup         |
+------------------------------------------------+
| Swipe right to unarchive                       |
+------------------------------------------------+
| Dock              Archive              Hosts   |
+------------------------------------------------+
```

### 8.5 Hosts

```text
+------------------------------------------------+
| Hosts                                  Add      |
+------------------------------------------------+
| home                                           |
| Codex app-server       Connected       12 live |
| AIMGR                  Ready                   |
| SSH                    home                    |
| [Test] [Rotate] [Edit]                         |
|                                                |
| laptop                                         |
| Codex app-server       Connected        4 live |
| AIMGR                  Ready                   |
| SSH                    laptop                  |
| [Test] [Rotate] [Edit]                         |
|                                                |
| studio                                         |
| Codex app-server       Offline                 |
| AIMGR                  Unknown                 |
| SSH                    studio                  |
| [Test] [Edit]                                  |
+------------------------------------------------+
| Dock              Archive              Hosts   |
+------------------------------------------------+
```

### 8.6 Dock Rotation Feedback

```text
+------------------------------------------------+
| Dock                                  + Host    |
| All  Needs me  Running  Limited                |
+------------------------------------------------+
| laptop                    Codex  AIM low Rotate|
| gw_controls                                     |
| | teal | Play vs AI preview           Limited  |
| |      | rate limit hit                 [Rotate]|
|                                                |
| Rotated Codex account on laptop                |
| Applies to the next Codex process.             |
+------------------------------------------------+
| Dock              Archive              Hosts   |
+------------------------------------------------+
```

Notes:

- Account rotation, if added after V1, should be available directly from the
  Dock.
- The user should not type, spell, or edit shell commands from the phone.
- The implementation command is `aim codex use`, but the main UI is a Rotate
  button plus success/failure feedback.
- The "next process" rule should be visible in the result or detail text.
- V1 does not implement this flow.
- A later version must not expose AIMGR account labels or account-management
  controls unless a separate discovery pass explicitly changes that scope.

## 9. Functional Requirements

### 9.1 Host Management

FR-HOST-001: The app must let the user define multiple hosts.

FR-HOST-002: Each host must have a user-facing name.

FR-HOST-003: Each host must have a Codex app-server endpoint configuration.

FR-HOST-004: Each host may have an SSH alias or SSH connection configuration for
transport packaging if the implementation chooses an SSH-based path.

FR-HOST-005: The app must show each host's connection health independently.

FR-HOST-006: One offline host must not block viewing sessions from other hosts.

FR-HOST-007: The UX must treat the network address as a generic endpoint, not a
Tailscale-specific concept.

### 9.2 Session List

FR-LIST-001: The Dock must show sessions from multiple hosts in one flat feed.

FR-LIST-002: The feed must group sessions by host.

FR-LIST-003: Within a host, the feed should group or visually separate sessions
by git branch when branch data is available.

FR-LIST-004: Sessions with missing branch data must remain visible under an
"Unknown branch" or repo-only grouping.

FR-LIST-005: The row must show host, provider, title/label, repo or cwd, branch,
status, last activity, and at least one short event summary.

FR-LIST-006: The feed must include filters for all sessions, needs-me sessions,
running sessions, and limited/rate-limit-warning sessions.

FR-LIST-007: The feed must support pull-to-refresh.

FR-LIST-008: The feed must support search by title, app-local label, repo/cwd,
branch, host, and thread id.

### 9.3 Thread Labels And Colors

FR-LABEL-001: The app must let the user assign a short label to a thread.

FR-LABEL-002: The app must let the user assign a color to a thread.

FR-LABEL-003: The Dock row must show the color without confusing it with status.

FR-LABEL-004: Labels and colors must be editable from the row quick action menu
and from session detail.

FR-LABEL-005: MVP storage may be app-local, keyed by host id plus backend plus
thread id.

FR-LABEL-006: If future app-server metadata safely supports custom client
metadata, label/color sync may be added later, but the MVP must not depend on
that to work.

### 9.4 Session Detail And Messaging

FR-SESSION-001: Tapping a session opens its detail view.

FR-SESSION-002: If the thread is not loaded, the app must resume it before
sending a new turn.

FR-SESSION-003: The detail view must show user messages, assistant messages,
command items, file-change items, reasoning summaries when available, and
approval/request cards.

FR-SESSION-004: Long command output must be collapsed by default.

FR-SESSION-005: The user must be able to type and send text to the thread.

FR-SESSION-006: The user must be able to interrupt an active turn.

FR-SESSION-007: The user should be able to steer an active turn when protocol
state allows it.

FR-SESSION-008: The app must stream item and turn updates while the session is
open.

FR-SESSION-009: The app must show when the phone is subscribed to live updates
versus looking at a stale snapshot.

### 9.5 Push-To-Talk

FR-VOICE-001: The session composer must include push-to-talk.

FR-VOICE-002: Push-to-talk must be an in-place hold gesture on the session
composer, not a separate screen.

FR-VOICE-003: The user must be able to record speech by holding the mic and
receive a text transcript when releasing the mic.

FR-VOICE-004: The transcript must be inserted into the composer text field and
remain editable before sending in MVP.

FR-VOICE-005: The app must not auto-submit transcribed text. The user must tap
Send explicitly.

FR-VOICE-006: The app must send the final transcript as normal text input to
Codex.

FR-VOICE-005: The app must show transcription failure clearly and preserve the
recording long enough for retry when practical.

FR-VOICE-006: The UX should not expose Whisper implementation detail unless it
helps diagnose an error.

### 9.6 Archive

FR-ARCHIVE-001: Swiping left on a session row must offer archive.

FR-ARCHIVE-002: Archiving must call the backend archive primitive when the
backend supports it.

FR-ARCHIVE-003: Archived sessions must disappear from the default Dock feed.

FR-ARCHIVE-004: Archive must be reversible.

FR-ARCHIVE-005: The Archive screen must show archived sessions by host and
support search.

FR-ARCHIVE-006: Swipe or tap action must unarchive a session.

### 9.7 Server-Initiated Requests

FR-REQ-001: The app must render command approval requests with a minimal card.

FR-REQ-002: The app must render file-change approval requests with a minimal
card.

FR-REQ-003: The app must render permission approval requests with a minimal
card.

FR-REQ-004: The app must render request-user-input prompts.

FR-REQ-005: MVP may show generic cards for MCP elicitations and dynamic tool
calls, but it must not silently ignore them.

FR-REQ-006: If a request type is unsupported, the app must show "Needs desktop"
or equivalent, with the method name and thread.

FR-REQ-007: Resolved requests must leave the needs-me state after the server
confirms resolution.

FR-REQ-008: Approval UX must stay lightweight in MVP because the user's normal
Codex setup runs with dangerously skipped permissions / unsandboxed behavior.

FR-REQ-009: MVP must not include a broad policy editor, permission rules
builder, or approval-management dashboard.

### 9.8 AI Manager Codex Rotation, Post-V1

AI Manager integration is out of V1 scope. The requirements below are captured
only as future notes and must not be included in V1 acceptance criteria.

FUT-AIM-001: Before implementation, run a separate AI Manager discovery pass.

FUT-AIM-002: Each host may declare that AIMGR is available over SSH.

FUT-AIM-003: The app may query `aim status --json` for lightweight availability
and last-result context when AIMGR is configured.

FUT-AIM-004: Host AIMGR availability may be summarized on the Dock host header
or Hosts screen.

FUT-AIM-005: A session or host with rate-limit pressure may surface a
low-energy Rotate action directly on the Dock.

FUT-AIM-006: The Rotate action should run `aim codex use` on the selected host over
SSH.

FUT-AIM-007: The Rotate action should not ask the user to choose or manage
AIMGR accounts or labels unless a later discovery pass changes that scope.

FUT-AIM-008: The iPhone UI must not require the user to type, spell, or edit the
rotation command. The command remains an implementation detail documented here.

FUT-AIM-009: The app should clearly state that rotation affects the next Codex
process, not a live hot-swap of an unmanaged running process.

FUT-AIM-010: The app should show command completion as success, failure, SSH
unavailable, or AIMGR unavailable.

FUT-AIM-011: If AIMGR returns a structured result, the app may show its status,
but parsing detailed account labels is not required.

FUT-AIM-012: The app must not ask the user to type shell commands for normal
account rotation.

FUT-AIM-013: The app must not store AI provider tokens directly in the iPhone
app. AIMGR remains on the host.

### 9.9 Future Backend Readiness

FR-FUTURE-001: The UI model must allow a future backend provider label per
session.

FR-FUTURE-002: The feed should not assume every session has Codex-specific
thread semantics in visible copy.

FR-FUTURE-003: Backend-specific actions may appear in provider-specific menus.

FR-FUTURE-004: Claude Code integration is out of MVP, but the UX should be able
to show Claude sessions beside Codex sessions later.

## 10. Codex Protocol Mapping

This section maps UI behavior to app-server protocol surfaces.

### 10.1 Connection

For each Codex host:

1. Open configured transport.
2. Send `initialize`.
3. Send `initialized`.
4. Keep a read loop active for responses, notifications, and server-initiated
   requests.

MVP connection capability:

```json
{
  "clientInfo": {
    "name": "codex_dock_ios",
    "title": "Codex Dock",
    "version": "0.1.0"
  },
  "capabilities": {
    "experimentalApi": true
  }
}
```

Transport note:

- Daemon Unix sockets require WebSocket framing.
- For phones, the practical deployment will likely expose a reachable
  WebSocket endpoint or an SSH-mediated bridge/tunnel.
- The UX spec does not require a Tailscale-specific setup screen.

### 10.2 Dock Feed

Use:

- `thread/list` for stored sessions
- `thread/loaded/list` for currently loaded sessions
- `thread/read` for detail previews when needed
- app-server notifications for live loaded-thread updates after subscription

Important rule:

- Browsing a thread is not the same as resuming it. Do not imply the session is
  active just because it appears in the feed.

### 10.3 Opening A Session

If thread is already loaded:

- subscribe/rejoin as needed through `thread/resume` when live continuation is
  needed

If thread is stored but not loaded:

- call `thread/resume`
- then show detail

### 10.4 Sending Text Or Voice Transcript

If no active turn:

- `turn/start` with text input

If active regular turn and steering is allowed:

- `turn/steer`

If active turn cannot be steered:

- show "Turn is busy" and offer interrupt or wait

### 10.5 Interrupt

Use:

- `turn/interrupt`

### 10.6 Archive

Use:

- `thread/archive`
- `thread/unarchive`

### 10.7 Rename

Use:

- `thread/name/set`

App-local label is separate from thread name. Thread name changes the backend
name. App-local labels are personal visual tags.

### 10.8 Approval And Request Cards

Handle server-to-client JSON-RPC requests by id.

Required MVP request methods:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`
- `item/tool/requestUserInput`
- `mcpServer/elicitation/request`

Approval handling is intentionally small in MVP. The user normally runs Codex
with permissions skipped, so approval cards exist to satisfy the app-server
contract when a request appears, not to become a full permission product.

Generic unsupported request behavior:

- render method name
- render safe summary of params
- show "Needs desktop" if the app cannot safely answer
- keep thread in needs-me state

### 10.9 Rate Limits

V1 Codex source:

- `account/rateLimits/read`

Post-V1 AIMGR source:

- SSH command `aim codex use` to rotate the active Codex account.
- Optional SSH command `aim status --json` to check AIMGR availability and show
  the last Codex selection result.

AI Manager is not part of V1. The V1 UI may show Codex rate-limit state from
the app-server if available, but it should not execute AIMGR commands.

If AIMGR is added later, the UI should not expose AIMGR account/label
management. The Dock should show a plain Rotate button when rotation is useful;
it should not ask the user to type or edit the command.

## 11. Detailed UX Requirements

### 11.1 Dock Header

The Dock header must include:

- title: Dock
- add host button
- segmented filters: All, Needs me, Running, Limited
- search

The header should stay compact.

### 11.2 Host Section

Host header must include:

- host display name
- provider status, such as Codex connected/offline
- optional loaded session count
- no AIMGR status in V1

Tapping host header opens a host summary sheet.

### 11.3 Branch Section

Branch separator should include:

- branch name
- optional repo name if branch names repeat across repos

Do not use heavy cards for branch headers.

### 11.4 Session Row

Row must include:

- color rail
- title or thread name
- app-local label if set
- status pill
- repo/cwd
- branch
- host/provider if not obvious from section
- last activity age
- one short last-event summary
- small attention indicator when there is an unresolved server request
- small rate-limit indicator when the session is blocked or likely blocked by
  rate limits

Row must avoid:

- showing raw JSON
- showing long command output
- using only color to signal status
- mixing thread color with status color

### 11.5 Row Quick Actions

Swipe left:

- Archive

Swipe right:

- Label
- Color

Long press:

- Open
- Rename thread
- Edit local label
- Change color
- Copy thread id
- Archive

### 11.6 Session Header

Session header must show:

- back button
- title
- host
- repo/cwd
- branch
- provider
- status
- color/label affordance
- overflow menu

Overflow menu:

- Rename
- Label/color
- Interrupt turn
- Archive
- Copy thread id

### 11.7 Event Rendering

Default event display:

- user message: normal chat bubble
- assistant message: normal chat bubble
- command: collapsed technical block
- command output: collapsed, expandable
- file change: compact diff summary, expandable later
- reasoning summary: small muted block when available
- approval request: prominent card
- rate-limit event: prominent warning card

MVP does not need a full syntax-highlighted diff viewer.

### 11.8 Composer

Composer states:

- Idle: text field, mic, send
- Recording: inline held-mic state in the composer
- Transcribing: inline spinner/status in or near the composer
- Transcript ready: editable text inserted into the composer and send
- Active turn: steer if allowed, otherwise wait/interrupt
- Offline host: disabled with retry
- Needs approval: composer remains available, but approval card stays prominent

### 11.9 Account Rotation UX, Post-V1

Account rotation is not part of V1. Existing mockups can keep Rotate
affordances as future-state exploration.

If added after V1, account rotation may appear in three places:

- Dock host header status/action
- limited session row action
- session overflow menu

The Dock rotation action should answer:

- Which host will change?
- Why is rotation suggested?
- Does it affect this running session or only the next Codex process?
- What happened after the command?

Do not make account rotation a command-entry UX. The command is documented for
the implementation, but the app presents a Rotate button and simple feedback.

Minimum future rotation outcomes:

- Success
- Failure, with reason when available
- SSH unavailable
- AIMGR unavailable

## 12. State Model

### 12.1 Session Status

The app should derive a small mobile status from app-server signals in V1.
AIMGR-derived statuses are post-V1 only.

```text
Needs me:
  unresolved server request, approval needed, user input needed, blocked tool,
  or explicit agent question

Running:
  active turn or recent streaming output

Idle:
  loaded or stored thread with no active turn and no unresolved request

Done:
  completed turn with no pending work and recent completion signal

Limited:
  account/rate-limit signal from Codex app-server, when available

Offline:
  host/app-server unreachable

Error:
  transport/protocol error or failed request
```

### 12.2 Host Status

```text
Connected:
  app-server initialized and responding

Degraded:
  app-server reachable but some APIs fail

Offline:
  app-server unreachable

Rotation suggested:
  post-V1 only; Codex or AIMGR signal suggests account rotation may be useful

Rotation blocked:
  post-V1 only; `aim codex use` failed or AIMGR is unavailable
```

### 12.3 Label/Color Storage

MVP local storage key:

```text
host_id + backend_id + thread_id
```

Stored values:

```text
localLabel
color
isPinnedToTop
lastSeenStatus
localNotes optional later
```

No cloud sync required for MVP.

## 13. Empty, Loading, Error, And Offline States

### 13.1 First Launch

```text
No hosts yet

Add a host to see Codex sessions on this iPhone.

[Add Host]
```

### 13.2 Host Offline

```text
home is offline

Last seen: 12m ago
Sessions from other hosts are still visible.

[Retry] [Edit Host]
```

### 13.3 No Sessions In Filter

```text
No sessions need you right now.

Running and idle sessions are still in All.
```

### 13.4 AIMGR Unavailable, Post-V1 Only

```text
AIMGR not available on laptop

Codex sessions are still available. Account rotation needs SSH and aim.

[Retry] [Edit Host]
```

### 13.5 Unsupported Server Request

```text
This session needs a desktop action

Codex requested: item/tool/call
Codex Dock cannot safely answer this request yet.
```

## 14. Accessibility Requirements

ACC-001: All row actions must be available without swipe gestures.

ACC-002: Color labels must also have text labels.

ACC-003: Status must not rely on color alone.

ACC-004: Push-to-talk must have an alternate tap-to-start/tap-to-stop mode.

ACC-005: Dynamic Type must not break row layout.

ACC-006: Buttons in approval cards and rotation feedback must have clear
labels.

ACC-007: Voice transcript must be editable with normal iOS text controls.

## 15. Security And Privacy Requirements

SEC-001: MVP does not implement user login/logout.

SEC-002: Host access configuration is local to the iPhone.

SEC-003: The app must not store AI provider OAuth tokens directly for AIMGR
rotation if AIMGR is added after V1.

SEC-004: If AIMGR is added after V1, AIMGR remains the account-rotation
authority on the host.

SEC-005: If SSH rotation actions are added after V1, they must show the host
and plain-language action before running. The exact implementation command is
documented as `aim codex use`, but the phone UI should not require command
entry.

SEC-006: Destructive or broad commands must not be exposed as generic shell.

SEC-007: Approval cards must show enough command/file context to avoid blind
approval, while staying minimal for the skipped-permissions primary workflow.

SEC-008: The app must not log full transcripts, command output, or secrets to
analytics in MVP.

SEC-009: If a host endpoint is unreachable, do not leak endpoint details into
third-party services.

SEC-010: Superseded on 2026-05-28. The `.env` OpenAI API key is Mac-side only.
Implementation must not embed it in the iPhone client, store it on the phone,
send it to the phone, or print it in docs, logs, telemetry, screenshots, or
error messages.

## 16. MVP Acceptance Criteria

The UX spec is satisfied when an implementer can build the first app version
that does all of this:

1. Add at least two host configurations.
2. Connect to each host's Codex app-server.
3. Show sessions from both hosts in one Dock feed.
4. Group the feed by host and branch.
5. Identify running, idle, needs-me, limited, offline, and archived sessions.
6. Add/edit a local thread label.
7. Add/edit a local thread color.
8. Tap a session and view the conversation/event stream.
9. Send typed text to a session.
10. Hold the mic on the session screen, release to transcribe into the composer,
    edit the transcript, and manually tap Send.
11. Show minimal command/file/permission approval cards and let the user answer
    supported ones when the API produces them.
12. Swipe to archive a session.
13. Open Archive and unarchive a session.
14. Continue to work when one host is offline.

## 17. Depth-First MVP Slice

Build in this order when implementation starts:

1. Read-only Dock
   - one host
   - `initialize`
   - `thread/list`
   - basic rows

2. Multi-host Dock
   - two hosts
   - independent offline state
   - host and branch grouping

3. Session Detail
   - `thread/resume`
   - message/event rendering
   - live notification loop

4. Send Text
   - `turn/start`
   - `turn/steer` where allowed
   - `turn/interrupt`

5. Mobile Control Essentials
   - labels/colors
   - archive/unarchive
   - approval cards

6. Voice
   - in-place push-to-talk from the session composer
   - release-to-transcribe into the text box
   - transcript edit
   - manual send as text

Do not start with a broad backend abstraction. Keep the provider boundary small
and let the Codex path prove the product.

## 18. Future Expansion

These are intentionally not MVP:

- Claude Code backend.
- Rich diff viewer.
- Review mode launch.
- MCP tool-specific custom forms.
- Realtime audio conversation with Codex.
- Push notifications.
- Cross-device label/color sync.
- AI Manager / AIMGR rotation support.
- Automatic background account rotation from the phone.
- AIMGR account/label browser.
- Explicit AIMGR label picker.
- AIMGR watch/tender management.
- App-server daemon bootstrap/start/stop controls.
- File browser.
- Command execution outside a session.

When Claude Code is added, it should map into the same visible session concepts:

- host
- backend provider
- repo/cwd
- branch when available
- session title
- status
- needs-me signal
- archive/hide
- text/voice input if supported

## 19. Open Decisions

No outcome-blocking decisions remain for MVP UX.

Implementation-time decisions:

1. Transport packaging
   - Decide whether iPhone reaches app-server by TCP WebSocket, SSH tunnel, or a
     small host bridge.
   - UX does not change.

2. Label/color sync
   - Start app-local.
   - Later decide whether to sync through app-server metadata.

3. Notification strategy
   - MVP can be foreground-only.
   - Push notifications can be a later feature.

4. AI Manager discovery
   - AI Manager is out of V1 scope.
   - Later, inspect the real AIMGR workflow again before implementing any
     account-rotation UI.
   - Existing mockups can keep Rotate affordances as future-state exploration.

## 20. Requirement Traceability

| User requirement | Spec location |
| --- | --- |
| Simple Swift iPhone client | Sections 1, 2.1, 4 |
| Connect to multiple computers | Sections 2.1, 5, 9.1 |
| View/interact with Codex sessions | Sections 8.3, 9.4, 10 |
| Read usage pattern | Section 3 |
| Include home server usage | Section 3.3 |
| Do not deeply embed Tailscale | Sections 2.2, 9.1 |
| Simple interface | Sections 1, 4, 7 |
| Colorize/label threads | Sections 2.4, 9.3, 12.3 |
| Quickly identify a thread | Sections 7, 8.1, 11.4 |
| Click/tap into thread | Sections 8.3, 9.4 |
| Type | Sections 8.3, 9.4 |
| Push-to-talk with Whisper/OpenAI transcription | Sections 8.3, 9.5 |
| Swipe to archive | Sections 8.4, 9.6 |
| Unarchive | Sections 8.4, 9.6 |
| View by server | Sections 8.1, 9.2 |
| Broken out by git branch | Sections 8.1, 9.2 |
| One flat organized view | Sections 6, 8.1, 9.2 |
| Swipe around and navigate | Sections 7.5, 11.5 |
| Manage on the road | Sections 1, 4, 8 |
| Future Claude Code/backend support | Sections 5.2, 9.9, 18 |
| Rooted in Codex JSON-RPC | Sections 3.1, 10 |
| Do not boil the ocean | Sections 4.2, 17, 18 |
| No login/logout | Sections 4.2, 15 |
| AI Manager support moved out of V1 | Sections 2.9, 3.4, 4.2, 9.8, 19 |
| Tap-based account rotation as post-V1 exploration | Sections 8.6, 9.8, 11.9 |
| SSH access to host for post-V1 AIMGR | Sections 2.9, 9.8 |
| No command-entry rotation UI | Sections 2.9, 8.6, 9.8, 11.9 |
| Minimal approvals because permissions are skipped | Sections 2.10, 9.7, 10.8 |
