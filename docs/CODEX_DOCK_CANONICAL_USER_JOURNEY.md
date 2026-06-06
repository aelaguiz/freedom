# Codex Dock Canonical User Journey

Status: canonical intended behavior
Audience: product, design, implementation, test, and review work

## Direct Answer

Codex Dock is a personal mobile operations board for Codex sessions running on
the user's own computers. It should let the user answer one question quickly:

> What is happening across my Codex sessions, which ones need me, and what can
> I safely do from my phone right now?

This document describes intended behavior. It does not describe current code
behavior when the code is wrong. When implementation, tests, dated plans, or old
UX specs disagree with this document about the user journey, this document is
the product-intent source of truth. Runnable commands, project settings, and
build/test wiring are still owned by `Makefile`, `project.yml`,
`Package.swift`, and `package.json`.

## First Principles

Codex Dock is not a replacement for the full Codex terminal UI. It is the phone
surface for fast monitoring, lightweight intervention, and safe recovery.

The app is for one operator. It does not need account signup, team management,
marketing pages, enterprise roles, or phone-side provider secrets.

The user should be able to:

- See active and historical Codex work across configured relays.
- Identify which sessions are running, idle, stale, blocked, or waiting for the
  user.
- Open one session and read enough context to act.
- Send text or dictated text from the normal composer.
- Answer supported approval and input requests.
- Review file changes enough to avoid blind approval.
- Archive finished work and restore it later.
- Add, edit, test, and remove relay hosts.
- Understand whether the app is online, partial, stale, offline, or
  misconfigured.
- Start a new Codex session or fork an existing one once that planned feature is
  implemented.

The app should not:

- Ask the phone user to understand raw Codex app-server internals.
- Connect the phone directly to the raw authenticated app-server on `:4500`.
- Store `OPENAI_API_KEY`, raw app-server bearer tokens, prompt text, transcript
  text, raw audio, or full JSON-RPC payloads in phone-visible diagnostics.
- Pretend status endpoints, screenshots, mocks, or loopback-only routes prove
  real app behavior.
- Hide unsupported server requests.
- Auto-send dictated or launch-sheet text without the user pressing Send.
- Let one broken host make the whole app feel broken when other hosts are
  still usable.

## Mental Model

### Host

A host is one saved relay endpoint, such as `amir-m5.fairy-salmon.ts.net:4510`
or `home.fairy-salmon.ts.net:4510`. A host represents a computer-side Dock
relay, not a raw Codex app-server.

### Relay

The relay is the phone-facing service on `:4510`. It discovers Codex session
owners on the Mac or Linux machine, normalizes them, and exposes app-safe
routes to the phone.

### Session

A session is one human-visible Codex thread. The phone should show it as a Dock
row with title, host, repo or workspace, branch, status, summary, and last
activity.

### Dock Card

A Dock card is the normalized row truth for Dock Home and Archive. Swift should
render session lists from relay-owned `dock/*` and `archive/*` projection
routes, not from raw diagnostic routes.

### Thread Detail

Thread Detail is the per-session work surface. It shows message/event history,
live state, request cards, file-change cards, and the composer.

### User-Controlled Text

Text from typing, dictation, or a future launch sheet stays under user control
until the user presses Send. The app can draft text for the user, but it must
not submit it automatically.

## App Map

The canonical app surface is:

- Bootstrap and Relay Setup
- Dock Home
- Search, Lenses, and Filters
- Pinned Sessions
- Row Actions
- New Session and Fork Session
- Thread Detail
- Composer
- Voice Dictation
- Request Cards
- File Change Review
- Archive
- Archive Cleanup
- System Health
- Relay Settings
- Foreground, Background, and Reconnect
- Error, Empty, Partial, and Stale States
- Accessibility
- Privacy and Security
- Proof and Acceptance

## 1. Bootstrap And Relay Setup

### Intent

The user should reach Dock Home with the least possible setup. The app should
prefer saved relay hosts, discover visible relays, and always allow manual
entry.

### Journey

1. The app starts.
2. If launch environment host config exists, the app uses it.
3. Otherwise, the app loads saved relay hosts from local phone config.
4. While loading saved config, the app starts Bonjour relay discovery.
5. If a saved host exists, the app uses it and keeps discovery available for
   additional visible relays.
6. If no saved host exists, the app shows discovered relays when available.
7. If discovery finds nothing, the app shows manual relay entry.
8. The user can type host and port, then tap Connect.
9. A valid relay host is saved locally and becomes part of the Host Registry.
10. Once a registry exists, the app enters Dock Home.

### Required Behavior

- The setup screen must say what it is doing: connecting, discovering, ready,
  or failed.
- The user must be able to recover from discovery failure with manual host and
  port entry.
- The host field must not autocorrect, autocapitalize, or treat hostnames as
  prose.
- The port field must accept numeric relay ports.
- Saved app config should contain host/port pairs only.
- A missing phone-side bearer token is normal for the personal relay path and
  must not be shown as missing credentials.
- Backgrounding during setup pauses discovery instead of burning retry budget.
- Foreground resume restarts discovery or saved-host loading when needed.

### Empty And Error States

- No visible relay: show "Searching" and manual relay entry.
- Saved relay unreadable: keep discovery/manual entry available.
- Invalid manual endpoint: show the validation error without erasing the typed
  host.
- Relay found but save failed: show a clear relay-save failure.

### Do Not

- Do not require login.
- Do not ask for `OPENAI_API_KEY`.
- Do not ask the phone user for raw app-server tokens.
- Do not store relay instance identity on the phone.
- Do not hard-code one physical phone's host list into the product model.

## 2. Dock Home

### Intent

Dock Home is the main screen. It should be a calm, scan-friendly operations
board that answers: what is running, what needs me, what changed recently, and
which host or branch is involved?

### Default Journey

1. The app opens to Dock Home.
2. The default lens is `Newest`.
3. The user sees one flat newest-first list across all configured hosts.
4. Each row gives enough identity to recognize the session without opening it.
5. Host problems appear inline without blocking healthy hosts.
6. Pull-to-refresh asks the relay for fresh projection truth.
7. Live updates change rows in place without losing scroll position, pinned
   state, labels, or visible actions.

### Row Content

Each session row should show:

- Session title.
- Host display name.
- Repository or working directory.
- Branch, or an honest unknown/repo-only fallback.
- Status when attention is needed.
- Fork marker when the session is forked.
- Local label, when set.
- Local color rail, when set.
- Short summary of latest meaningful activity.
- Last activity time.
- Stable open affordance.

### Status Meaning

The phone status should be small and mobile-readable:

- `Codex is working`: active turn or live work.
- `Needs answer`: Codex or a tool is waiting for user text.
- `Needs approval`: a supported approval is waiting.
- `Ready`: session is available and not actively waiting.
- `Saved`: session exists in history but is not actively loaded.
- `Error`: transport, protocol, or command failure.
- `Unknown`: relay cannot classify the session yet.

Idle, saved, and unknown rows should remain visible unless the user filters
them out. The app should not spend row-badge space on background implementation
states such as raw Codex `notLoaded`; the relay should normalize those into
mobile-meaningful status.

### Host Behavior

- Multiple hosts appear in one Dock.
- One offline host must not hide rows from another online host.
- Host-specific failures should appear as host context rows with Retry and
  Relay Settings actions.
- Partial or degraded hosts should be visible as partial/degraded, not as fully
  healthy.
- Host names and logical host identity must stay stable across endpoint aliases
  such as LAN, `.local`, and Tailscale names.

### Empty States

- No sessions: "No sessions are loaded on reachable hosts."
- No search matches: "No sessions match this search."
- No filter matches: "No sessions match the active filters."
- Selected host unavailable: show the unavailable host and recovery actions.

### Do Not

- Do not use diagnostics-only routes as Dock row truth.
- Do not claim the Dock is fresh when the relay reports stale, partial, or
  failed projection evidence.
- Do not collapse all host failure into one vague global error.
- Do not make users choose a backend transport before they can read sessions.

## 3. Search, Lenses, And Filters

### Intent

Search, lenses, and filters should help the user find the right session quickly
without turning Dock Home into a dashboard full of knobs.

### Search

Search is full-width and available on Dock Home.

It should match:

- Session title.
- Local label.
- Repository.
- Working directory.
- Branch.
- Summary.
- Status.
- Host display name.
- Host id.
- Source.
- Thread id.

Search should preserve the selected lens and filters. Clearing search should
return the user to the same lens and filter state.

### Lenses

The canonical Dock lenses are:

- `Newest`: one flat newest-first list across configured hosts.
- `Host`: sessions grouped by host, preserving newest-first order inside each
  group.
- `Branch`: sessions grouped by host/branch or branch context, preserving
  newest-first order inside groups.

Group headers should show title, count, running count when present, and newest
activity. Groups should be collapsible.

### Filters

Filters live in one shared filter surface.

Filter categories:

- Host.
- Branch.
- Status.
- Repo or workspace.
- Source.
- Sort.

Filter behavior:

- `Any` host means all configured hosts.
- `Any` status includes idle/ready rows.
- Branch search narrows branch chips.
- Repo search finds repository or workspace text.
- Source can include all, human, agents/automation, or unknown.
- Current sort is `Newest activity`.
- Active filters show a compact summary on Dock Home.
- Clear returns filters to the default state.

### Do Not

- Do not create separate tabs for every filter.
- Do not make Host and Branch lenses replace the global search.
- Do not use a filter to silently hide attention-needed rows without the user
  seeing the active-filter summary.

## 4. Pinned Sessions

### Intent

Pinned sessions are the user's local watch list. They should stay easy to find
without changing the session's true status or activity order.

### Journey

1. The user pins a row from a visible row action.
2. The row appears in a Pinned section at the top of the current Dock scope.
3. The user can collapse or expand Pinned.
4. The user can unpin from the pinned row or row actions.
5. If there are multiple pinned rows, the user can reorder them.
6. Search and filters can hide pinned rows, but the app should say pinned rows
   are hidden by the current scope.

### Required Behavior

- Pinning is local metadata.
- Pinning must not change the session status.
- Pinned order must survive live updates.
- Pinned rows must still open the normal Thread Detail.
- Pinned rows must still have non-swipe accessible actions.

### Do Not

- Do not let live row reorders duplicate pinned accessibility rows.
- Do not hide pinned rows silently when filters/search exclude them.
- Do not use pin color or position as a substitute for status.

## 5. Row Actions

### Intent

Row actions should be fast but not hidden behind one gesture. Every swipe action
must also exist through a visible or accessible action path.

### Primary Row Actions

The user should be able to:

- Open Thread Detail.
- Pin or unpin.
- Rename.
- Mark Watch.
- Clear label.
- Assign a color.
- Clear color.
- Archive.
- Fork the session when session launch is implemented.
- Start a new session in this workspace when a reliable working directory is
  known and session launch is implemented.

### Archive Intent

Archive is the intended completion action for a finished session. A row-level
archive should remove the row from Dock Home after relay confirmation or
refresh, and the row should appear in Archived Threads.

### Rename Intent

Rename should:

- Open a focused Rename Thread sheet.
- Start with the current row title.
- Trim whitespace.
- Reject empty names.
- Disable Save when unchanged.
- Optimistically keep the user's pending title visible.
- Show an action error if the relay/server rename fails.

### Labels And Colors

Labels and colors should help identify work quickly:

- `Watch` is a lightweight local label.
- Color rail is local and decorative but useful.
- Status must still be readable without color.
- Labels and colors should be preserved across refreshes and live updates.

### Do Not

- Do not make a swipe-only action.
- Do not archive without a restore path.
- Do not let local labels/colors override the truth of host, repo, branch,
  status, or activity.

## 6. New Session And Fork Session

### Intent

The user should be able to create a new Codex session or fork an existing one
from inside the app without learning the upstream app-server protocol.

This is planned behavior. The canonical architecture is one app-facing relay
command, `thread/session/launch`, with `kind: start | fork`.

### New Session Journey

1. The user taps a visible New Session action on Dock Home.
2. If the action is launched from a branch or row context, the sheet shows the
   known host, working directory, and observed branch context.
3. If there is no trustworthy working directory, the sheet shows Default
   workspace and omits `cwd`.
4. The user can optionally type an initial draft.
5. The user taps Create.
6. The relay creates the upstream Codex thread through `thread/start`.
7. The relay writes and emits the normal Dock card projection.
8. The app opens the normal `SessionDetailView`.
9. If the user typed an initial draft, it appears in the normal composer.
10. The user edits and presses Send when ready.

### Fork Session Journey

1. The user opens a row action or Thread Detail action for an existing human
   session.
2. The user chooses Fork.
3. The sheet shows source session, host, working directory, and branch context.
4. The user taps Fork.
5. The relay routes to the correct live/history Codex owner.
6. The relay calls upstream `thread/fork` by `threadId`.
7. The relay writes and emits the normal Dock card projection.
8. The app opens the forked thread through normal Thread Detail.

### Required Behavior

- Start and fork use one product command path on the phone.
- The relay owns idempotency, validation, routing, upstream method choice, and
  projection update.
- Swift owns one `DockStore` launch path.
- The response returns a normal `DockThreadCardDTO`.
- Initial prompt text is not sent during launch.
- Retrying the same launch command id must not double-create.
- Fork is host-scoped.
- Path-based fork is not a phone feature.

### Do Not

- Do not expose raw `thread/start` and `thread/fork` as two separate
  phone-owned product paths.
- Do not create a second session list or fork-specific detail screen.
- Do not let the phone choose model/provider/secrets in the first visible flow.
- Do not synthesize a working directory from branch, repo label, search text,
  or display-only metadata.

## 7. Thread Detail

### Intent

Thread Detail is where the user reads and acts on one Codex session. It should
preserve context, show live/stale truth, and keep the composer close to the
messages.

### Journey

1. The user taps a Dock or Archive row.
2. The app opens Thread Detail for that row's host/thread identity.
3. The header shows title, host, repo/workspace, branch, thread id, status,
   relationship, and last activity.
4. The detail connects to relay-owned `thread/detail/*` projection routes.
5. The app renders messages, commands, output, system rows, requests, and file
   changes.
6. The user can filter the visible event list by message type.
7. The composer stays visible above the event list.
8. Live updates append or update rows without wiping the visible transcript.
9. If live updates stop, the detail keeps visible history and marks itself
   stale.

### Live State

Thread Detail live state should be explicit:

- `Connecting`: opening or subscribing.
- `Updating`: catching up while retaining visible content.
- `Reconnecting`: transport is reconnecting.
- `Live`: subscribed and current.
- `Stale`: visible data is retained but no longer claimed fresh.
- `Closed`: session detail connection is closed.

### Header

The header should show:

- Title.
- Host pill.
- Live-state pill.
- Fork pill when forked.
- Status pill when attention is needed or useful.
- Repository/workspace and branch.
- Thread id and last activity.

### Message List

The event list should:

- Show user messages.
- Show Codex/assistant messages.
- Show command rows.
- Show output rows.
- Show request rows.
- Show file-change rows.
- Show system rows when selected.
- Preserve selection/copy for text content.
- Keep large or noisy output compact enough for phone use.
- Show "No transcript" only when there are no readable events.
- Show "No rows match this filter" only when a filter hides existing events.

### Stale And Error Behavior

- A stale detail must keep visible rows.
- A stale detail must show why live updates stopped.
- Reconnect/resync should refresh without wiping content first.
- If the host is no longer configured, show Thread unavailable.
- Failed sends must show failed/ambiguous delivery state, not silently replay.

### Do Not

- Do not use raw full-turn reads as the phone-facing detail contract.
- Do not blank the transcript during refresh.
- Do not label stale retained history as live.
- Do not open a special archived-detail or fork-detail screen when the normal
  detail path can work.

## 8. Composer

### Intent

The composer is the single place where user-authored message text becomes a
Codex input. Typed text, dictated text, and launch-sheet drafts all converge
here before Send.

### Input Truth Layers

Input has three separate truth layers. The UI must keep them separate:

1. `Draft`: editable local text in the composer. This is not submitted.
2. `Pending outbound message`: the user pressed Send, Swift created a
   `clientUserMessageId`, and the message is visible locally before canonical
   server history catches up.
3. `Canonical event`: the relay/Codex projection contains the real user-message
   row, identified by the same `clientUserMessageId`.

The app must never merge messages by body text or timestamp. Reconciliation is
by `clientUserMessageId`.

### Composer Ownership Contract

The composer owns only local draft state. The message list owns submitted
message state. The server projection owns canonical history.

- A draft can be edited, selected, pasted into, dictated into, cleared, or
  preserved across a refresh.
- A pending outbound message cannot be edited in place because it is already a
  submitted user intent.
- A canonical message cannot be changed by the phone.
- A failed pending message can expose retry/copy/edit-as-new actions, but those
  actions must be visually different.
- A new draft typed after Send is unrelated to older pending rows.
- A live projection update must never overwrite the current composer draft.
- A server reconnect must reconcile pending rows, not push pending text back
  into the composer.

The user should always be able to answer one question from the screen:

> Is this text still my editable draft, or did I already submit it?

### Manual Typing State Machine

| State | Composer field | Send button | Message list | User can do |
| --- | --- | --- | --- | --- |
| Empty draft | Placeholder such as `Message Codex` | Disabled | No new pending row | Type, start voice, answer request cards |
| Editing draft | User text visible and editable | Enabled when trimmed text is non-empty and connection allows send | No new pending row | Keep typing, start voice append, Send, navigate away with draft preserved |
| Whitespace-only draft | Whitespace may be visible while editing | Disabled | No new pending row | Keep editing; pressing Send should do nothing |
| Dictation busy | Draft field stays visible but read-only | Disabled | No new pending row from voice | Wait, stop/finalize voice, cancel by leaving/backgrounding |
| Local submit accepted | Draft clears immediately | Disabled until a new non-empty draft exists | New pending user-message row appears immediately | Start a new draft, navigate, wait for delivery state |
| Relay accepted | Draft remains independent | Based on current draft, not prior pending row | Pending row badge says `Accepted` | Keep working; no duplicate send needed |
| Submitted upstream | Draft remains independent | Based on current draft | Pending row badge says `Sending` | Keep working; wait for canonical projection |
| Canonical observed | Draft unaffected | Based on current draft | Pending row merges into the canonical user-message row; duplicate pending row disappears | Continue normally |
| Definite failure | Draft is not automatically restored | Based on current draft | Pending row badge says `Failed` with reason | Retry same client intent, edit/copy and send as a new intent, or leave it visible |
| Ambiguous failure | Draft is not automatically restored | Based on current draft | Pending row badge says `Check` or `Delivery uncertain` with reason | Refresh/reconcile first; explicit retry must reuse same client id or clearly warn about duplicate risk |
| Detail stale/offline after submit | Draft remains independent | Disabled if no send-capable session is connected | Pending row remains visible with last known delivery state | Refresh/reconnect; do not auto-replay |

### Pre-Submit Input Details

Before Send, the text is still draft text. It should look and behave like a
normal phone text input, with clear disabled reasons.

- Empty, unfocused draft: show the placeholder, disable Send, keep mic available
  when voice is available.
- Empty, focused draft: keep Send disabled; do not show an error just because
  the user has not typed.
- Whitespace-only draft: allow the whitespace while editing, but trim-check it
  as empty for Send.
- Normal draft: show exactly what the user typed, including line breaks that
  are supported by the field.
- Pasted draft: treat pasted text the same as typed text; do not auto-send.
- Long draft: keep the composer usable, cap growth to a phone-safe height, and
  let the text scroll inside the field after the cap.
- Selected text: typing, paste, delete, and dictation insertion should respect
  the normal text-selection model where the platform supports it.
- Keyboard submit: same as tapping Send. It must run the same validation and
  create at most one `clientUserMessageId`.
- Keyboard dismiss: never clears the draft.
- Live update while typing: keep the draft exactly as-is and update the message
  list around it.
- Navigation away before Send: preserve the draft if Thread Detail stays in
  memory; if preservation is not possible, never submit it implicitly.
- Relay reconnect before Send: keep the draft and recompute whether Send is
  allowed.
- Request-card input: stays separate from the composer draft and never becomes
  a normal user message unless the user explicitly copies it into the composer.

### Send Gesture Contract

The Send gesture is the boundary between draft and submitted intent.

1. Validate that the trimmed draft is non-empty.
2. Validate that no voice state is Starting, Streaming, or Finalizing.
3. Validate that the current thread has a send-capable relay session.
4. Atomically snapshot the submitted text.
5. Create exactly one `clientUserMessageId`.
6. Clear the composer.
7. Insert the pending outbound row.
8. Start `thread/message/send`.

If any validation fails, the draft stays in the composer and no pending row is
created.

### Manual Typing Journey

1. The user types into Message Codex.
2. The text field grows within the compact composer limit.
3. The user can edit normally while no dictation segment is active.
4. Send becomes enabled only when:
   - trimmed draft text is non-empty;
   - no voice capture/transcription phase is busy;
   - Thread Detail has a send-capable relay session.
5. The user taps Send or submits from the keyboard.
6. Swift trims the draft.
7. Swift creates one `clientUserMessageId` with the shape
   `dock-msg:<uuid-v4>`.
8. Swift creates a pending outbound user-message row immediately.
9. Swift clears the composer draft immediately.
10. The pending row appears in the message list even if the relay has not
    answered yet.
11. Delivery continues in the background through `thread/message/send`.
12. The user can start typing the next draft without waiting for the previous
    message to become canonical.
13. When the canonical projection arrives with the same `clientUserMessageId`,
    the pending row is replaced by or merged into the canonical event.

### Visual Rules Before Send

- Draft text belongs only in the composer.
- The message list must not show a user-message row before Send.
- Send should not show a long spinner while the user is only editing.
- Empty or whitespace-only drafts cannot submit.
- Request cards can remain visible while the user drafts a normal message.
- If the detail is stale but still readable, the draft stays editable where
  safe; Send is disabled or fails visibly until the app has a send-capable
  session.
- If the host is unavailable before Send, the draft must stay in the composer
  and the error must appear near the composer or detail state.

### Visual Rules Immediately After Send

Immediately after local acceptance, before the relay has confirmed anything:

- The composer draft clears.
- A pending user-message card appears with the submitted text.
- The pending card shows `Pending`.
- The Send button is disabled only because the new draft is empty, not because
  the previous message is pending.
- The user can begin another draft.
- The app must not wait for the relay before showing the pending card.
- The app must not navigate away or scroll in a way that hides the pending
  message from the user.

This is the key "submitted, but not registered with the server yet" state.
The user should see their message as locally accepted, but not yet server
confirmed.

### Submitted But Not Registered With Server

This state begins after Swift has accepted the Send gesture and ends when the
relay/Codex projection shows a canonical user-message row with the same
`clientUserMessageId`.

The intended screen in this window:

- The submitted text appears in the message list as a user-message row.
- The row status is `Pending`, `Accepted`, or `Sending`.
- The row is visually lighter than a hard failure but still clearly not fully
  canonical.
- The composer is empty unless the user has already started typing a new draft.
- The Send button reflects the new draft, not the pending message.
- The detail can show a small delivery indicator on the row, not a full-screen
  blocking state.
- The user can keep reading the thread.
- The user can type the next message.
- The app does not say `Sent` until `canonicalObserved`.

What must not happen in this window:

- Do not leave the submitted text in the composer and also show it as pending.
- Do not hide the submitted text until the server confirms it.
- Do not block all composer use just because one message is pending.
- Do not create a second send if the user double-taps the same cleared draft.
- Do not merge by matching body text if the server later shows similar text.
- Do not show success wording for `acceptedByRelay` or `submittedUpstream`;
  those are delivery progress, not canonical registration.
- Do not silently retry if the network drops after upstream submission might
  have happened.

### Not-Yet-Registered Timing Expectations

The user does not need exact milliseconds, but the app should communicate the
phase honestly:

| Phase | Trigger | User-facing meaning | Intended look |
| --- | --- | --- | --- |
| `pendingLocal` | Send was accepted in Swift | The app has the message, but relay evidence is not back | Pending row with `Pending` |
| `acceptedByRelay` | Relay accepted or deduped the command | The relay owns the intent | Same row with `Accepted` |
| `submittedUpstream` | Relay submitted upstream or has upstream delivery evidence | Codex may be working, but the canonical row has not appeared | Same row with `Sending` |
| Long `submittedUpstream` | Projection is late or stale | The user should wait, refresh, or inspect stale state before retrying | Same row plus stale/detail status if needed |
| `canonicalObserved` | Projection includes matching `clientUserMessageId` | Server history now owns the row | Pending styling disappears or becomes `Sent` briefly |

### Relay And Server Delivery States

The intended delivery labels are:

- `Pending`: Swift accepted the user intent locally, but relay command evidence
  is not back yet.
- `Accepted`: the relay persisted/deduped the command but has not proven
  upstream Codex submission yet.
- `Sending`: the relay submitted upstream or has upstream delivery evidence,
  but the canonical projected row has not appeared yet.
- `Sent`: the canonical projected row with the same `clientUserMessageId` has
  appeared. The transient badge can disappear after the row is clearly
  canonical.
- `Failed`: delivery is definitely not complete and the relay knows it is safe
  to retry the same client intent.
- `Check`: delivery is ambiguous; the app cannot know whether Codex received
  the message.

### Delivery Transition Contract

- `pendingLocal` may move to `acceptedByRelay`, `submittedUpstream`,
  `canonicalObserved`, `failedDefinite`, or `failedAmbiguous`.
- `acceptedByRelay` may move to `submittedUpstream`, `canonicalObserved`,
  `failedDefinite`, or `failedAmbiguous`.
- `submittedUpstream` may move to `canonicalObserved` or `failedAmbiguous`.
- `canonicalObserved` is terminal for that client message.
- `failedDefinite` can retry the same client message id.
- `failedAmbiguous` is not safe to auto-retry.
- A later canonical projection with the same `clientUserMessageId` wins over a
  stale failure state.
- A reconnect should ask the relay/projection for truth before changing a
  pending row into a duplicate new send.

### Pending Row Behavior

- Pending rows are normal visible user-message rows, not toast-only status.
- Pending rows must include the submitted body text.
- Pending rows must include status, but the status should not overpower the
  message.
- Pending rows sort with the same newest-first detail ordering as other events.
- Pending rows stay visible across projection refreshes until a canonical event
  with the same `clientUserMessageId` arrives.
- If canonical projection arrives, the app must not show both pending and
  canonical copies of the same client message.
- If the canonical event has the same client id but different server metadata,
  keep the server metadata and remove the pending duplicate.
- If a matching body appears without `clientUserMessageId`, the app must not
  silently merge by text. It can show both or mark reconciliation uncertain.

### Multiple Sends

- Sending the same text twice intentionally creates two different
  `clientUserMessageId` values.
- A rapid double tap on Send for one visible draft should not create two
  messages. Local acceptance should atomically clear the draft and disable that
  exact send affordance.
- A second message typed after the first draft cleared is a new user intent and
  gets a new id.
- Multiple pending messages can coexist. Each has its own id, status, and
  canonical reconciliation.

### Retry And Recovery

- Definite failure can offer Retry. Retry must reuse the same
  `clientUserMessageId`.
- Ambiguous failure must not auto-retry. The UI should say the message may have
  reached Codex.
- If the user chooses to retry an ambiguous message, the app must either reuse
  the same `clientUserMessageId` or make the duplicate risk explicit.
- A separate "send this text again" action creates a new message id and should
  feel like a new send, not a retry.
- Refresh/resync should try to reconcile pending rows before encouraging
  duplicate sends.
- Background/foreground resume must not replay pending messages blindly.
- Reopening Thread Detail should recover canonical events from projection and
  any durable relay command state that is available.

### Active Turn And Routing

- The user should not choose `turn/start` versus `turn/steer`.
- The relay decides whether the message starts a new turn or steers an active
  turn.
- If the active turn changes while the message is in flight, the relay should
  reconcile and route safely.
- If steering is impossible, the pending row should show a clear failed or
  ambiguous state. The app should not hide the message.

### Composer Edge Cases

- If Send is tapped while there is no connected session, keep the draft and
  show `Thread is not connected.` or an equivalent visible error.
- If Send is attempted while dictation is busy, keep the draft and show
  `Finish dictation before sending.` or an equivalent visible error.
- If the relay disconnects after local submit, keep the pending row and mark
  delivery state based on the best evidence.
- If projection catches up late, merge by `clientUserMessageId` even after the
  row sat pending for a while.
- If the user navigates away after Send, pending state should not vanish just
  because the view changed.
- If the user edits a new draft while an older pending row fails, do not replace
  the new draft with the older failed text automatically.
- If a request card is pending at the same time as a user message, the two
  states remain separate. Request-card responses use request ids, not
  `clientUserMessageId`.
- If a launch-sheet initial draft exists after New Session or Fork, it becomes
  ordinary composer draft text and follows this same state machine.
- If the user pastes a very large message, the composer should stay responsive
  and Send validation should fail visibly only if the relay/app has a real size
  limit.
- If a pending row fails while the user is typing a new draft, the failure must
  not steal focus or replace the new draft.
- If Thread Detail is archived, restored, renamed, or recolored while the user
  has a draft, the draft remains draft text and should not be submitted or
  cleared by the metadata action.
- If the user switches host configuration while a draft exists, keep the draft
  but require a send-capable thread before Send.
- If the server returns `acceptedByRelay` for a duplicate
  `clientUserMessageId`, update the existing pending row, not a new row.
- If the relay reports `clientUserMessageId collision`, show a definite error
  and do not generate a hidden replacement id for that same Send gesture.
- If the app process dies after local acceptance but before relay evidence, the
  recovery path should reconcile from relay/projection state when possible. It
  should not create a new id from the same remembered text.
- If the canonical projection includes the client id but the message body is
  normalized differently, trust the canonical row and remove the pending row.
- If the canonical projection never includes the client id, keep the pending
  row in `Check` or equivalent uncertain state rather than pretending it is
  sent.

### Do Not

- Do not create another hidden send path for voice, launch sheets, request
  cards, or raw turn routes.
- Do not auto-submit text after dictation.
- Do not wait for canonical projection before showing the user's sent text.
- Do not restore a sent draft into the composer on failure if the user has
  already started a new draft.
- Do not silently retry ambiguous user messages.
- Do not lose the draft because a live update arrives.
- Do not merge pending and canonical rows by message body.

## 9. Voice Dictation

### Intent

Voice is a text drafting tool. It should help the user draft a normal message
quickly, not create a separate voice-chat mode.

Voice has no special send semantics. It only changes the composer draft.
After final text lands in the composer, manual typing and voice text follow the
same Send state machine in Section 8.

Voice is therefore always pre-submit until the user presses Send. A transcript
can look like message text, but it is not a message row, has no
`clientUserMessageId`, and has not touched Codex.

### Voice State Machine

| State | Composer field | Mic controls | Send button | Message list | User can do |
| --- | --- | --- | --- | --- | --- |
| Idle, no draft | Empty and editable | Hold and tap enabled if voice-capable | Disabled | No new row | Type or start dictation |
| Idle, draft exists | Draft editable | Hold and tap enabled if voice-capable | Enabled if connected | No new row | Edit, dictate append, or Send |
| Starting | Field visible but read-only | Active mode shows starting; other voice mode disabled | Disabled | No new row | Wait or leave/background to cancel |
| Streaming | Provisional transcript appears in the same field | Active mode shows listening; stop/release finalizes | Disabled | No new row | Speak; stop/release when done |
| Finalizing | Latest transcript remains visible, read-only | Mic disabled or finalizing | Disabled | No new row | Wait for final transcript |
| Final text ready | Final transcript inserted into editable draft | Mic enabled again | Enabled if final draft is non-empty and connected | No new row until Send | Edit text or Send manually |
| Voice failed before transcript | Original draft restored | Mic enabled if available | Based on restored draft | No new row | Try again, type, or Send restored draft |
| Voice failed after useful partial | Best provisional transcript remains editable with error | Mic enabled if available | Based on retained draft | No new row | Edit retained text, retry dictation, or Send |
| Detail closed/backgrounded | Active voice canceled | No active voice | No auto-send | No new row | Reopen; draft should preserve safe text |

### Voice Visual Details By Phase

- Idle: the composer behaves like normal manual typing.
- Starting: the mic control shows a busy state immediately so the user knows the
  press or tap registered.
- Starting failure: return to Idle quickly, preserve the draft, and show the
  voice error near the composer.
- Streaming: provisional transcript appears inline in the composer, but the
  field is locked against manual edits until dictation stops.
- Streaming with no words yet: show listening status without inserting fake
  text.
- Streaming with partial words: show the best current transcript and replace
  that active segment as better text arrives.
- Finalizing: audio capture has stopped; keep the latest text visible, keep
  Send disabled, and wait for final transcript or failure.
- Finalized: remove the busy state, unlock the composer, and leave the final
  text as editable draft text.
- Canceled: preserve the base draft or useful partial text, then unlock the
  composer.
- Failed: preserve the safest draft text, show one recoverable error, and do
  not create a message row.

### Hold Mode Journey

Hold mode:

1. The user presses and holds the mic button.
2. The app snapshots the current draft as the base draft.
3. The composer enters Starting.
4. User edits are locked while the voice segment is active.
5. The app starts live microphone capture and relay-owned Realtime
   transcription.
6. The composer enters Streaming.
7. Cumulative transcript deltas replace only the active dictation segment.
8. Existing typed prefix text stays before the dictated segment.
9. The user releases the mic.
10. The composer enters Finalizing.
11. The app stops capture, commits the transcription session, and waits for the
    final transcript.
12. Final text replaces the active dictation segment.
13. Voice returns to Idle.
14. The text field becomes editable again.
15. The user presses Send manually.

### Tap Mode Journey

1. The user taps the mic button once.
2. The app snapshots the current draft as the base draft.
3. The composer enters Starting, then Streaming.
4. The tap button changes to Stop dictation.
5. Provisional text streams into the composer.
6. The user taps Stop dictation.
7. The composer enters Finalizing.
8. Final text lands in the composer.
9. Voice returns to Idle.
10. The user edits and presses Send manually.

### Draft Reconciliation Rules

- There is one active dictation segment at a time.
- The active segment starts from the current draft.
- If the base draft is empty, the transcript becomes the draft.
- If the base draft is non-empty and does not end in whitespace, the transcript
  is appended with one separating space.
- If the base draft ends in whitespace, the transcript is appended directly.
- Partial transcript updates replace the active segment; they do not append
  repeatedly.
- Final transcript replaces the active segment one last time.
- Stale transcription events from an old session id must be ignored.
- User edits are locked while voice is Starting, Streaming, or Finalizing so
  typed edits cannot race transcript updates.
- After voice returns to Idle, the draft is ordinary editable text.
- If the user selected text before starting voice, the intended behavior is to
  replace that selected range with the voice segment where the platform can
  preserve selection reliably. If not reliable, append to the draft.
- If the user starts voice after typing a prefix such as `Ask it to`, the
  transcript should naturally produce `Ask it to <transcript>`, not overwrite
  the prefix.
- If the user starts a second dictation after finalizing the first, the second
  transcript appends to or replaces the current draft according to the same
  rules. It does not reopen the old voice session.
- If the transcript service sends duplicate partial events, the visible draft
  should remain one coherent segment, not repeated words from re-appending the
  same delta.

### Voice Status Copy

The user-visible voice states should be short:

- Idle: no status unless there is a last voice error.
- Starting: `Starting dictation`.
- Streaming with hold mode: `Listening. Release to finalize.`
- Streaming with tap mode: `Listening. Tap stop to finalize.`
- Finalizing: `Finalizing`.
- Failure: a short recoverable error, such as `Realtime transcription stopped.
  Try again.`

### Voice Failure Rules

- Microphone permission denied: preserve the draft, show a mic error, keep Send
  based on the existing draft.
- Microphone unavailable or simulator capture failure: preserve the draft and
  show a visible voice error.
- Relay transcription unavailable or key missing: preserve the draft and show a
  visible voice error.
- Realtime session fails before any useful transcript: restore the base draft.
- Realtime session fails after useful provisional text: keep the best visible
  provisional text as editable draft and show the error.
- Audio append fails after capture started: stop capture, cancel the realtime
  session, preserve safe draft text, and show the error.
- Event stream closes while voice is busy: stop capture, preserve safe draft
  text, and show a recoverable error.
- Empty final transcript: restore the base draft or keep useful provisional
  text, show an error, and do not auto-send.
- Detail close: cancel voice, preserve safe draft text, show that dictation
  stopped because Thread Detail closed when the user returns.
- App background: cancel voice, preserve safe draft text, show that dictation
  stopped because the app moved to the background.
- Route interruption, input-device change, or iOS audio interruption: stop
  capture safely and show a recoverable error when it affects dictation.
- Duplicate `audio/transcription/start`: reject or ignore the second start and
  keep the current active dictation visible.
- Out-of-order `audio/transcription/append` sequence: stop or fail the active
  voice session, preserve safe draft text, and show a recoverable error.
- Audio queue full: stop accepting more audio for that session, finalize or fail
  clearly, and preserve safe text.
- `audio/transcription/canceled`: return to Idle with preserved safe text.
- `audio/transcription/closed`: return to Idle only after completed, failed, or
  canceled truth has been applied.

### Voice And Manual Typing Edge Cases

- User taps Send during voice Starting, Streaming, or Finalizing: Send remains
  disabled; a forced keyboard submit shows `Finish dictation before sending.`
- User releases hold immediately before any audio is useful: finalize to the
  base draft and show no pending message.
- User starts tap mode and forgets to stop: keep showing Listening, do not
  submit, and rely on normal app lifecycle cancellation if the view closes or
  backgrounds.
- User has an older pending message and starts voice for the next message:
  allow it when the thread is send-capable; the new voice draft has no link to
  the older pending row.
- User receives a live assistant update while dictating: keep the active voice
  draft stable and update the message list without stealing focus.
- User answers a request card while voice is active: request-card state remains
  separate; it must not append to or submit the voice draft.
- User navigates back during voice: cancel capture, preserve safe draft text,
  and never send.
- User backgrounds during voice: cancel capture, preserve safe draft text, and
  never send.
- User starts voice when the relay is offline: preserve the draft and show a
  voice/connection error before capture becomes misleading.
- User starts voice when OpenAI relay-side transcription config is unavailable:
  preserve the draft and show a voice error; do not expose model/API-key
  settings on the phone.

### Voice And Send Interaction

- Send is disabled while voice is Starting, Streaming, or Finalizing.
- Keyboard submit during active voice should not send.
- If a forced send attempt happens during active voice, the error should say to
  finish dictation before sending.
- Final transcript text is not a submitted message.
- The message list does not get a user-message row until the user presses Send.
- After Send, the message uses the manual typing state machine and a normal
  `clientUserMessageId`.
- A previous pending message should not prevent starting a new voice draft if
  the detail session is otherwise send-capable.

### Required Behavior

- Hold and tap modes must both exist so voice is accessible without a sustained
  press.
- Voice status appears inline: starting, listening, finalizing, or error.
- The app should preserve any text that existed before dictation and append the
  transcript naturally.
- If transcription fails after useful provisional text exists, keep as much
  useful draft text as possible.
- Closing Thread Detail or backgrounding the app cancels active dictation
  without submitting.
- OpenAI Realtime transcription config and API keys stay on the relay side.
- Voice uses purpose-specific `audio/transcription/*` relay methods, not a
  generic OpenAI proxy and not old one-shot `audio/transcribe`.

### Do Not

- Do not send audio to Codex as a message.
- Do not expose transcription model choice on the phone.
- Do not pass `OPENAI_API_KEY` to the app.
- Do not log base64 audio, raw audio bytes, prompt text, or transcript text.
- Do not auto-submit the transcript.
- Do not allow user edits to race active transcript replacement.
- Do not create a separate voice screen.
- Do not show a pending user-message row for dictated text before manual Send.

## 10. Request Cards

### Intent

When Codex asks the client for approval or input, the phone must not ignore it.
The phone should show a clear, minimal card and support the request types that
are safe enough for mobile.

### Supported Request Types

The app should render:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`
- `item/tool/requestUserInput`
- `mcpServer/elicitation/request`

Unsupported request methods should still appear as Needs desktop, with enough
method/thread context for the user to understand why work is blocked.

### Journey: Approval Request

1. A request appears in Thread Detail.
2. The row shows a request status badge.
3. The card shows the request title, summary, and enough detail to avoid blind
   action.
4. The user taps Approve or Decline.
5. The card moves to Sending.
6. The relay sends a response by request id.
7. The card becomes Resolved after success or Failed with a visible reason.

### Journey: User Input Request

1. The card shows the question.
2. The user types an answer in the card input.
3. Send is enabled only when the answer is non-empty.
4. The card sends the answer and moves to Resolved or Failed.

### Journey: MCP Elicitation

MCP elicitation should be visible. In the minimal phone flow, decline is the
safe supported response unless a future plan defines richer structured input.

### Required Behavior

- Resolved requests should leave the needs-me state after server confirmation.
- Failed request responses should stay visible with failure text.
- Unsupported request types should not disappear.
- Request cards should stay linked to the real Thread Detail event row.

### Do Not

- Do not blind-approve without context.
- Do not hide unsupported request types.
- Do not answer a request without its real JSON-RPC request id.
- Do not make a generic shell-command UI from request cards.

## 11. File Change Review

### Intent

File-change review should make mobile approval safer. The phone does not need
to be a full desktop diff tool, but it must show enough about changed files to
avoid blind approval.

### Journey

1. A file-change request appears in Thread Detail.
2. The row shows changed-file count, additions, deletions, limited-diff warning
   when needed, and approval status.
3. The user taps Review changes.
4. A file list sheet opens.
5. The user can filter All or Unviewed.
6. The user opens each renderable file.
7. The diff view marks files as viewed when opened.
8. The user can navigate hunks and expand hidden context.
9. The approval bar remains available.
10. The user approves or declines.

### Approval Rules

- If all renderable files have been viewed and no diff is limited, Approve
  changes can send directly.
- If files are unviewed, unavailable, generated, binary, too large, missing,
  unsupported, or truncated, the app must ask for confirmation before approve.
- Decline should ask for confirmation because it sends a real decline response.
- An explicit Approve anyway confirms the risk for that request only.

### Required Behavior

- Changed file status should be clear: added, deleted, moved, modified, or
  changed.
- File counts, additions, deletions, and truncation/availability must be visible.
- The app should show unavailable diff reasons plainly.
- Binary/generated/too-large/missing diffs can be acknowledged but are still
  limited evidence.
- Request status should be reflected in both the card and approval bar.

### Do Not

- Do not let limited diff approval look identical to fully reviewed approval.
- Do not require desktop-grade syntax highlighting for the MVP.
- Do not hide failed approval responses.

## 12. Archive

### Intent

Archive is how the user clears completed work from Dock Home without losing the
ability to inspect or restore it.

### Archive Journey

1. The user archives a row from a row action or intended swipe action.
2. The relay performs the archive command.
3. Dock Home refreshes or receives projection update.
4. The row disappears from Dock Home.
5. The row appears in Archived Threads.

### Archived Threads Journey

1. The user opens More, then Archived Threads.
2. Archived rows load across configured hosts.
3. The user can search archived rows.
4. The user can filter by host.
5. The user can filter by all dates, last 30 days, or last 90 days.
6. The user can open an archived row's normal Thread Detail.
7. The user can restore one row.
8. The user can enter selection mode, select multiple rows, and restore
   selected rows.
9. Batch restore shows progress, supports Stop remaining, Retry failed, and
   Done.
10. Restored rows return to Dock Home after refresh/projection update.

### Required Behavior

- Archive is reversible.
- Archive search should match title, repository, branch, summary, host display
  name, and thread id.
- Failed restores should stay visible with error context.
- Stop remaining should stop future restore attempts, not corrupt completed
  ones.
- Archive should have host status context so one offline host does not hide
  archived rows from online hosts.

### Do Not

- Do not treat Archive as delete.
- Do not claim restore succeeded until the relay/server confirms or projection
  evidence catches up.
- Do not block archived detail reading when the normal detail path is available.

## 13. Archive Cleanup

### Intent

Archive Cleanup is a preview-first batch tool. It should help the user archive
old low-risk sessions without accidentally moving important active work.

### Journey

1. The user opens More, then Archive Cleanup.
2. The screen runs a preview.
3. The user chooses an age rule: 30 days, 90 days, 1 year, or custom days.
4. The user chooses exclusions.
5. The preview updates before anything moves.
6. The user reviews host summaries and candidate rows.
7. The user opens Review list for detailed selection.
8. The user can filter candidates by host, status, branch, search, and show
   excluded rows.
9. The user selects or unselects candidates.
10. The user taps Archive selected.
11. Large batches ask for confirmation.
12. The app shows progress.
13. The user can Stop remaining.
14. Failed rows remain available for Retry failed.
15. Completed archive moves appear in Archived Threads.

### Safety Exclusions

Archive Cleanup should support:

- Exclude pinned.
- Exclude running.
- Exclude needs input/approval.
- Exclude Watch label.

These exclusions protect work that is likely still important.

### Custom Age

Custom age should accept 1 through 3650 days. Invalid custom values should not
apply.

### Required Behavior

- Preview before move is mandatory.
- The candidate count and excluded count must be visible.
- Host-level counts must be visible.
- Selection count must be visible.
- Confirmation should explain that archived rows can be restored.
- Failed rows stay in Dock or remain selectable; they do not disappear silently.

### Do Not

- Do not batch archive without preview.
- Do not hide exclusions.
- Do not include pinned/running/needs-me/Watch rows when their exclusion toggles
  are on.
- Do not make Archive Cleanup look like deletion.

## 14. System Health

### Intent

System Health explains connectivity and relay route evidence. It helps the user
diagnose why the app is stale, partial, offline, or misconfigured.

System Health is not a replacement for app-visible proof. A green route check
does not prove Dock rows are complete, fresh, correctly ordered, or visible in
the app.

### Journey

1. The user taps the global connectivity indicator or opens System Health from
   More.
2. The sheet shows overall status.
3. The sheet shows category cards.
4. The sheet shows host cards.
5. The user can Run check.
6. The user can open a host detail page for technical route evidence.
7. The user can open Relay Settings.
8. The user can copy `rtk make relay-doctor`.

### Categories

System Health should summarize:

- Dock feed.
- Thread detail.
- Archive.
- Voice.
- Diagnostics.

### Overall Status

The global indicator should use clear labels:

- Unconfigured.
- Checking.
- Online.
- Partial.
- Reconnecting.
- Backgrounded.
- Resuming.
- Stale.
- Offline.
- Error.
- Config error.

For multiple hosts, online/partial labels should include host count when useful,
such as Online 1/2 or Partial 1/2.

### Required Behavior

- The indicator opens System Health.
- Host cards show display name, endpoint, and current phase message.
- Host details show route diagnostics when present.
- No route evidence yet should be explicit.
- Relay Settings is the recovery path for host config problems.

### Do Not

- Do not claim route health proves app screen correctness.
- Do not expose card rows or stored card state through HTTP diagnostics.
- Do not show Mac-side secrets in diagnostics.

## 15. Relay Settings

### Intent

Relay Settings is where the user manages saved relay hosts. It is a host list
editor, not a credentials manager.

### Journey

1. The user opens More, then Relay Settings, or opens it from System Health.
2. Existing relay hosts are listed.
3. Each host row shows display name, endpoint, status, and status detail.
4. The user can Test one host.
5. The user can Test all hosts.
6. The user can Edit a host.
7. The user can Add Relay.
8. The user can Remove a host.
9. Removing the final relay asks for confirmation because it leaves the app
   without a saved relay host.
10. Saving a valid host updates the Host Registry and refreshes Dock, Archive,
    Cleanup, and Health.

### Required Behavior

- Host and port fields must not autocorrect or autocapitalize.
- Save validates WebSocket-safe relay endpoint shape.
- Test actions should show not checked, testing, online, offline, or error.
- Removing one host should not erase others.
- Host changes should update all app surfaces that depend on hosts.

### Do Not

- Do not store OpenAI keys here.
- Do not store raw app-server bearer tokens here.
- Do not let `ws://user:pass@host` style credentials into endpoint config.
- Do not require command-line knowledge to add or edit a relay.

## 16. Foreground, Background, And Reconnect

### Intent

The app should respect iOS lifecycle. When backgrounded, it should preserve the
visible state and stop work that cannot safely continue. When foregrounded, it
should rehydrate cleanly.

### Background Journey

1. iOS backgrounds the app.
2. Root refresh and reconnect attempts pause.
3. Dock and Archive keep visible rows but stop claiming fresh updates.
4. Open Thread Detail keeps visible events, request state, and draft text.
5. Active voice capture is canceled without auto-submitting.
6. Connectivity status becomes Backgrounded or stale as appropriate.

### Foreground Journey

1. iOS foregrounds the app.
2. Connectivity moves through Resuming or Reconnecting when needed.
3. Dock refreshes from root projection.
4. Archive refreshes.
5. Open Thread Detail rehydrates through detail resync.
6. Fresh/live labels return only after app-route evidence catches up.

### Required Behavior

- Resume should not double-send pending messages.
- Resume should not wipe visible detail rows.
- Resume should not auto-submit voice or draft text.
- One stale surface should not force unrelated surfaces to pretend stale if
  they have fresh evidence.

### Do Not

- Do not spend retry budget while backgrounded.
- Do not call stale retained data live.
- Do not drop request-card state just because the app went inactive.

## 17. Error, Empty, Partial, And Stale States

### Intent

The app should fail loudly enough for the user to understand what is unavailable
while preserving every trustworthy piece of data.

### Empty

Empty means there is no matching content after applying real scope:

- No configured hosts.
- No sessions on reachable hosts.
- No search matches.
- No filter matches.
- No archived rows.
- No cleanup candidates.
- No transcript.
- No rows match message filter.

Empty should not be used for offline, stale, failed, or unconfigured states.

### Partial

Partial means some evidence is usable and some is missing, degraded, stale, or
blocked. The app should show the usable part and label the missing/degraded
part.

### Stale

Stale means the app retained visible data but cannot claim it is fresh. Stale
data should remain visible with clear stale text and recovery action.

### Offline

Offline means a host or route cannot be reached. Other online hosts should keep
working.

### Error

Error means a command, route, protocol, or config failed. The error should be
near the affected action or surface.

### Required Behavior

- Errors should be specific enough to act on.
- Action errors should not erase content.
- Failed batch operations should show which rows failed.
- Stale and partial states should avoid false reassurance.
- Retry and Relay Settings should be available when they are meaningful.

### Do Not

- Do not hide stale data when it is the best available context.
- Do not call an empty list "success" if the host failed.
- Do not reduce all errors to "try again" without host/route/action context.

## 18. Accessibility

### Intent

The app must remain usable without precise gestures, without color vision, and
with large text.

### Required Behavior

- Every row action must be available without swipe gestures.
- Color rails must have text-equivalent labels or controls.
- Status must not rely on color alone.
- Voice dictation must support tap-to-start/tap-to-stop as well as hold.
- Dynamic Type must not break row layout.
- Buttons in approval cards must have clear labels.
- Voice transcript must be editable with normal text controls.
- Search, filters, request cards, host rows, and health categories need useful
  accessibility labels/values.

### Do Not

- Do not make important actions icon-only without accessible names.
- Do not make text overlap or truncate the only useful identity.
- Do not require a long press, swipe, or drag as the only path for a task.

## 19. Privacy And Security

### Intent

Codex Dock is personal software, but it still handles sensitive work context.
The phone should receive only app-safe data and should never become the place
where Mac-side secrets live.

### Required Behavior

- The phone connects only to the Dock relay on `:4510` for the normal path.
- WebSocket URLs must be `ws://` or `wss://`, include a host, and not include
  username/password credentials.
- `OPENAI_API_KEY` stays Mac-side.
- Raw Codex app-server bearer tokens stay Mac-side.
- OpenAI Realtime transcription provider/model config stays relay-side.
- Bonjour TXT records stay non-secret.
- Logs must not include provider keys, bearer tokens, base64 audio, raw audio,
  prompt text, transcript text, or full JSON-RPC payloads.
- Approval cards should show enough context for safe user decisions without
  turning the app into a generic shell runner.

### Do Not

- Do not make the iPhone connect directly to raw authenticated `:4500`.
- Do not add a phone-side API-key field.
- Do not expose app-server private runtime details as user-facing session truth.
- Do not treat personal-network trust as permission to log sensitive content.

## 20. Proof And Acceptance

### Intent

Tests should prove the intended journey through the real app paths. They should
not prove only that diagnostics, fixtures, or side routes work.

### Current Proof Rule

For user-visible Dock, Archive, Thread Detail, rename, archive, message,
request-card, voice, or relay-settings behavior, proof should exercise the
same app-facing route family the user depends on.

### Completion-Grade Proof Examples

- Dock live update proof should use real Dock projection routes.
- Thread Detail proof should use real detail projection routes.
- Archive proof should use archive projection and restore/archive commands.
- Voice proof should show transcript text entering the normal composer and
  remaining editable before manual Send.
- Request-card proof should show card status from the rendered detail list.
- New/fork session proof, once implemented, should prove `thread/session/launch`
  creates/forks through relay projection and opens normal Thread Detail.
- Real-data simulator proof is required before claiming live-data app behavior.
- Physical-phone claims need installed-phone proof or the exact blocker.

### Do Not Count As Completion Proof

- Status endpoints alone.
- `/readyz` alone.
- `/routesz` alone.
- Screenshots alone.
- Mock rows.
- SwiftUI preview rows.
- Loopback-only WebSockets.
- Unix socket-only checks.
- Raw `ws://127.0.0.1:4500`.
- Direct diagnostic side-door routes.
- Relay-only subscribe counts without app UI proof.

## Canonical Journey Checklist

This is the high-level intended journey coverage. A future implementation or
test plan should be able to point each row to app behavior and proof.

| Experience | Intended outcome |
| --- | --- |
| First launch | The app finds saved or discovered relays, or lets the user enter one manually. |
| Relay setup failure | The user sees the specific problem and can retry or manually connect. |
| Dock Home | The user sees one newest-first session board across configured hosts. |
| Host lens | The user can understand sessions by host without losing recency. |
| Branch lens | The user can understand sessions by branch/workspace without losing recency. |
| Search | The user can find sessions by title, label, repo/cwd, branch, host, summary, status, or thread id. |
| Filters | The user can narrow by host, branch, status, repo/workspace, source, and newest activity. |
| Pinned sessions | The user can keep watch-list sessions at the top, collapse, unpin, and reorder them. |
| Row actions | The user can open, pin, rename, label, color, archive, and later fork/start from context. |
| Rename | The user can rename a thread with validation and visible failure. |
| Labels/colors | The user can locally mark rows without confusing metadata with status. |
| New Session | The user can create a session through the relay and land in normal Thread Detail. |
| Fork Session | The user can fork a session by thread id through the relay and land in normal Thread Detail. |
| Thread Detail | The user can read messages/events, see live/stale truth, and act. |
| Message filter | The user can narrow detail rows without losing the underlying transcript. |
| Composer | The user can draft locally, submit once, see pending/server delivery state, and avoid double-send. |
| Voice dictation | The user can dictate as editable draft text, recover failures, and manually send through the normal composer. |
| Request card | The user can answer supported approvals/input and see unsupported requests. |
| File change review | The user can review changed files and approve only with appropriate risk confirmation. |
| Archive | The user can remove completed rows from Dock and restore them later. |
| Archived Threads | The user can search, filter, open, restore one, or restore many archived rows. |
| Archive Cleanup | The user can preview, filter, safely exclude, and batch archive old rows. |
| System Health | The user can understand relay/route health without mistaking it for app proof. |
| Relay Settings | The user can add, edit, test, and remove saved relay hosts. |
| Background | The app pauses work, preserves context, and cancels active voice without sending. |
| Foreground resume | The app refreshes Dock, Archive, and Detail before claiming fresh/live truth. |
| Offline host | Online hosts keep working and the offline host shows recovery actions. |
| Partial/stale data | The app keeps usable context visible and labels it honestly. |
| Accessibility | The user can operate important actions without swipe-only or color-only cues. |
| Security | Secrets stay Mac-side and sensitive content is not logged. |

Net: Codex Dock should feel like a trustworthy phone dock for personal Codex
work. It should be simple on the surface because the relay and app own the hard
parts: identity, routing, projection truth, recovery, and safe command
boundaries.
