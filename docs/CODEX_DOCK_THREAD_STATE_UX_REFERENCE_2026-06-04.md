# Codex Dock Thread State UX Reference

Date: 2026-06-04

Last source and research check: 2026-06-04

Status: canonical product UX reference for presenting Dock and Thread Detail
thread status, attention state, and request state to a human user.

Companion technical reference:
[Codex Dock Thread Types And States Reference](./CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md)

Companion time/order UX reference:
[Codex Dock Conversation, Time, And Order UX Reference](./CODEX_DOCK_TIME_ORDER_UX_REFERENCE_2026-05-31.md)

Companion mockup package:
[Codex Dock Thread State UX Mockups](./mockups/codex-dock-thread-state-ux-2026-06-04/README.md)

This document owns the user-facing state model. It does not replace the raw
state reference. The raw reference remains the source of truth for Codex,
relay, DTO, and Swift state axes.

## Net Answer

Codex Dock should not show every raw thread state as a top-level user label,
and it should not add a generic catch-all error bucket. The best focused UX is
a simple status model:

- `Codex is working`: Codex is doing things and it is not the user's turn.
- `Your turn`: Codex is either done for now or blocked until the user acts.

Everything else is either a sublabel under those routine states or, for this
focused slice, a small `Error` badge on the affected thread:

- `Your turn · Ready`: Codex finished the current turn and can accept the next
  prompt.
- `Your turn · Needs answer`: Codex asked for typed or chosen input.
- `Your turn · Needs approval`: Codex needs approval, file review, command
  review, or permission.
- `Your turn · Saved`: the thread is historical, archived, or not loaded.
- `Error`: the thread itself is in a raw `systemError` / Dock `error` state.

Do not show a top-level catch-all error chip, section, filter, or header state
by default. If one thread has an error, badge that thread or its Thread Detail
with `Error`. Other health/status surfaces are outside this focused UX slice.

The app should stop treating `idle` as if it means "waiting for user input."
It does not. `idle` means ready for the next user turn. User-input waiting is an
active wait flag and should project to `Your turn · Needs answer`.

Anything outside in-app thread status is outside this focused cut. It should
not drive the Dock or Thread Detail status model.

Net: the main UI should answer: is Codex working, is it my turn, or is this
thread in the raw error state? `idle` is `Your turn · Ready`; it is not
`waitingOnUserInput`, not `waitingOnApproval`, and not an interruption trigger
by itself.

## First Implementation Scope

The first shipping slice is intentionally smaller than the full product model
in this reference.

Ship now:

- Dock row badges use existing row status badges only:
  `Codex is working`, `Needs answer`, `Needs approval`, or `Error`.
- Ready Dock rows stay quiet and do not get a loud badge.
- Thread Detail uses the existing header badge as the status surface:
  `Codex is working`, `Your turn · Ready`, `Your turn · Needs answer`,
  `Your turn · Needs approval`, or `Error`.
- Thread Detail does not add a duplicate status banner below the header badge.

Do not ship in this slice:

- a new structural Dock `Your turn` section;
- exact Dock-row request subtype badges such as `Review command`,
  `Review files`, or `Grant permission`;
- host offline, network error, stale stream, reconnecting, or relay-health UX;
- a generic `Problem` bucket, section, tab, header, or banner.

Exact request subtype copy belongs to Thread Detail request cards until a
future relay/DTO expansion is planned.

## Most Common Full-Permissions State

The most common state, especially in full-permissions mode, is not approval,
blocking, or user-input waiting.

The common loop is:

1. The user gives Codex a task.
2. Codex runs without asking for approval.
3. Codex finishes the turn.
4. The thread is now sitting there, ready for the next user instruction.

That state is source-level `idle`, projected to `Your turn · Ready`.

Default UX for this case:

- Dock says nothing is urgent: `Nothing needs you`.
- Recent ready rows do not get loud badges.
- Row support copy can say `Finished · Ready for next prompt` or
  `Done executing · waiting for your next instruction`.
- Thread Detail shows a quiet `Your turn · Ready` state and a final assistant
  response.
- Thread Detail should not add a duplicate ready banner below the header badge.
- The composer is the primary next action.
- Raw `idle` appears only in `State details` or Debug, not as the headline.

This is the default happy path. `Your turn · Needs answer` and
`Your turn · Needs approval` are the interruption paths.

## Actual Codex Active State Contract

Codex does not have a thread state for "running tests", "editing files",
"reading repo", "thinking", or "writing reply".

The real source-level thread status is only:

- `notLoaded`
- `idle`
- `systemError`
- `active { activeFlags }`

The only source-level active flags are:

- `waitingOnApproval`
- `waitingOnUserInput`

That means the header status should answer the turn/attention question, not the
activity-summary question.

| Source state | User-facing state | Meaning |
| --- | --- | --- |
| `active` with no flags | `Codex is working` | Codex has an open turn and does not currently need the user. |
| `active` with `waitingOnApproval` | `Your turn · Needs approval` or exact request copy | Codex is blocked on an approval-style decision. |
| `active` with `waitingOnUserInput` | `Your turn · Needs answer` or exact request copy | Codex is blocked on typed/chosen user input. |
| `active` with both flags | `Your turn · Needs approval` first, plus secondary input detail if visible | The protocol can express both; Dock gives approval precedence. |
| `idle` | `Your turn · Ready` | Codex finished the current turn and can accept the next user instruction. |
| `systemError` | `Error` | App-server recorded a thread-level system error; badge only the affected thread/detail. |
| `notLoaded` | `Your turn · Saved` or `Not loaded` | Thread is known in history but not loaded into app-server runtime. |

`Running` is still a faithful projection of raw `active` with no flags, but it
is not the best human label. `Codex is working` is clearer because it means
"Codex is busy and it is not your turn."

### Header Fields

Thread Detail should keep these fields separate:

| Question | Header/UI answer | Source |
| --- | --- | --- |
| Whose turn is it? | `Codex is working` or `Your turn` | Raw `Thread.status` projected by relay/Swift |
| Why is it your turn? | `Ready`, `Needs answer`, `Needs approval`, `Review files`, `Review command`, or `Saved` | Raw flags plus request card kind |
| Is there a concrete request? | Exact request-card title and action buttons | `ServerRequestCard` |
| Is this thread in raw error state? | `Error` | Raw `systemError` or Dock `error` |

Do not use latest events to rename the thread state. Latest events can support a
separate activity summary, but that summary must be labeled as activity, not as
state.

### Optional Activity Summary

If Thread Detail needs more than `Codex is working`, show activity as normal
thread content or compact support copy. Do not add a second status banner below
the header badge.

Good examples:

- `Latest activity: command still in progress`
- `Latest activity: file-change request pending`
- `Latest activity: reasoning update 18s ago`
- `Latest activity: assistant message streaming`
- `No recent activity from the live stream`

Bad examples:

- Header state: `Running tests`
- Dock badge: `Editing`
- Raw state label: `Thinking`

Those are not supported Codex thread states.

### Slow Active State

If the source state remains active but no event has updated recently, keep the
state source-backed and make the activity evidence explicit.

Use:

- state: `Codex is working`
- activity: `No recent activity from the live stream`

This is more honest than turning an old event into a confident current state.

## Source-Checked Current App Facts

This UX recommendation is grounded in the current source as of 2026-06-04:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
  defines the actual Codex `ThreadStatus` union as `notLoaded`, `idle`,
  `systemError`, or `active { activeFlags }`.
- The same Codex protocol file defines the only active flags:
  `waitingOnApproval` and `waitingOnUserInput`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs`
  derives `idle` only when the thread is loaded, no turn is running, no
  approval or user-input request is pending, and no system error is set.
- The same app-server source derives `active` when `running == true` or any
  active flag is present. It does not derive test/edit/read/think sub-states.
- `resolve_thread_status` in app-server source can coerce `idle` or `notLoaded`
  to active with no flags if the returned thread still contains a live
  `inProgress` turn.
- `TurnStatus`, command status, patch status, reasoning rows, plan rows, and
  agent-message deltas are lower-level turn/item/event signals. They can support
  a separate activity summary, but they are not `Thread.status`.
- `CodexDock/Dock/DockModels.swift` defines Dock row status values:
  `running`, `needsInput`, `needsApproval`, `idle`, `error`, `dormant`, and
  `unknown`.
- The same file already hides visible row badges for `idle`, `dormant`, and
  `unknown`, while showing badges for `running`, `needsInput`, `needsApproval`,
  and `error`.
- `scripts/dock-relay-state-views.mjs` maps raw active wait flags to Dock row
  statuses. `waitingOnApproval` becomes `needsApproval`;
  `waitingOnUserInput` becomes `needsInput`; active work without those flags
  becomes `running`; raw `idle` remains `idle`; `notLoaded` becomes `dormant`;
  `systemError` becomes `error`.
- `scripts/dock-relay-state-engine.mjs` already stores `waitingState` only for
  `needsApproval` and `needsInput`.
- `CodexDock/Models/ServerRequestCard.swift` has the actionable request kinds:
  command approval, file-change approval, permissions approval, user input, MCP
  elicitation, and unsupported.
- `ThreadDetailHeader.statusLabel` currently comes from
  `row.status.visibleBadgeLabel`, so a raw active row becomes a generic
  `Running` header pill.
- Thread Detail event projection includes activity clues:
  `plan` and `reasoning` rows as `thinking`; `commandExecution` rows as
  `tooling`; `fileChange` rows as request/file-change detail; tool calls as
  `tooling`; and agent-message deltas as message updates. These are event
  categories, not thread states.
- `CodexDock/Automation/AutomationID.swift` already has row actions for `pin`
  and `unpin`, plus request-card automation IDs for approve, decline, send,
  input, and unsupported states.

The current source is already partly aligned with this UX direction: quiet
states have no visible badge. The missing product layer is a clear human label
system, an attention-first Dock layout, and a small `Error` badge only when the
thread itself is in raw error state.

## Research Base

The findings below synthesize established UX guidance for visible status,
progress feedback, progressive disclosure, text-first badges, and accessibility.

- Nielsen Norman Group, Visibility of System Status:
  https://www.nngroup.com/articles/visibility-system-status/
- Nielsen Norman Group, Response Times:
  https://www.nngroup.com/articles/response-times-3-important-limits/
- Nielsen Norman Group, Progress Indicators:
  https://www.nngroup.com/articles/progress-indicators/
- Nielsen Norman Group progressive disclosure:
  https://www.nngroup.com/articles/progressive-disclosure/
- Apple Human Interface Guidelines, Feedback:
  https://developer.apple.com/design/human-interface-guidelines/feedback
- Apple Human Interface Guidelines, Progress indicators:
  https://developer.apple.com/design/human-interface-guidelines/progress-indicators/
- Material Design progress indicators:
  https://m2.material.io/components/progress-indicators
- Material Design confirmation and acknowledgement:
  https://m2.material.io/design/communication/confirmation-acknowledgement.html
- Atlassian Design System lozenges:
  https://developer.atlassian.com/platform/forge/ui-kit/components/lozenge/
- W3C WCAG 2.2, Status Messages:
  https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html
- W3C WCAG 2.2, Use of Color:
  https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
- Microsoft Human-AI Interaction Design Guidelines:
  https://www.microsoft.com/en-us/research/articles/guidelines-for-human-ai-interaction-eighteen-best-practices-for-human-centered-ai-design
- Microsoft HAX Toolkit:
  https://www.microsoft.com/en-us/haxtoolkit/
- Linear Docs, Inbox:
  https://linear.app/docs/inbox
- Linear Docs, Triage:
  https://linear.app/docs/triage

The common pattern is consistent:

- Users need timely system status, but backstage implementation states should
  come frontstage only when they affect action, trust, or orientation.
- Complex systems need progressive disclosure: plain top-level labels, exact
  technical detail on demand, and no hidden critical actions.
- Status badges must be short, textual, and not color-only.
- AI interfaces should show why the system needs the user and make it easy to
  accept, decline, answer, or dismiss.
- Attention surfaces should work like an inbox: show what needs action first,
  then ongoing work, then history.
- Raw thread error should stay local and small: an `Error` badge on the affected
  thread row/detail.

## Research Implications

These research findings translate into concrete Codex Dock rules:

- NN/g visibility of system status: show whether Codex is working, whether it is
  the user's turn, or whether this exact thread is in raw error state. Do not
  make the user infer state from row order, color rails, or old message text.
- NN/g progressive disclosure: show the few states users need on the first
  screen; keep raw flags, goal status, turn status, relay freshness, and debug
  fields one layer deeper.
- NN/g response-time and progress guidance: `Codex is working` should show
  immediate feedback and, for long work, a reason or latest step. A spinner
  without context is weak for long-running agent work.
- Atlassian lozenge guidance and WCAG color guidance: badges need short words
  and cannot rely on hue alone. Orange cannot be the only meaning of "my turn."
- Microsoft human-AI guidance: Codex should explain what it needs and let the
  user answer, approve, decline, or open desktop without noisy state clutter.
- Linear/Triage patterns: use an action-inbox shape for required user action,
  not for every error or historical row.

## Focused UX Research: Dock And Thread Detail

This section is the narrow 2026-06-04 pass for the current product question. It
only covers in-app Dock row status and Thread Detail status treatment.

The focused question:

How should Dock rows and Thread Detail headers answer the user's three real
questions?

1. Is Codex doing things?
2. Did Codex finish, so it is my turn now?
3. Is this specific thread in raw error state?

Source-backed conclusions:

- NN/g visibility-of-system-status guidance says current state matters because
  users need to know what to do next and whether the system heard them. For
  Codex Dock, the main routine state label should answer
  `Codex is working` or `Your turn`; raw thread error should stay a small
  `Error` badge on the affected thread/detail.
  Source: https://www.nngroup.com/articles/visibility-system-status/
- NN/g response-time and progress guidance says long waits need feedback that
  the system is still working. For Codex Dock, `Codex is working` can show a
  small latest-activity line, but that line must not become a fake thread state
  such as `Running tests`.
  Sources:
  https://www.nngroup.com/articles/response-times-3-important-limits/ and
  https://www.nngroup.com/articles/progress-indicators/
- NN/g progressive-disclosure guidance says the first screen should show the
  few important facts, with deeper detail available on request. For Codex Dock,
  the row/header gets the bucket; `idle`, `activeFlags`, relay freshness, turn
  status, request IDs, and raw event categories belong in `State details`,
  filters, tests, or debug.
  Source: https://www.nngroup.com/articles/progressive-disclosure/
- Apple feedback guidance says feedback should match the significance of the
  information. For Codex Dock, quiet `Your turn · Ready` should be calm because
  it is the normal full-permissions completion path, while required-action
  `Your turn` needs stronger placement on the row it affects.
  Source: https://developer.apple.com/design/human-interface-guidelines/feedback
- Apple progress-indicator guidance says progress indicators are transient and
  should make clear that the app is not stalled. For Codex Dock, the active
  state can use a small spinner or pulse, but the persistent truth remains
  `Codex is working`.
  Source:
  https://developer.apple.com/design/human-interface-guidelines/progress-indicators/
- W3C color guidance and Atlassian lozenge guidance both point to text-first
  status, not color-only meaning. For Codex Dock, status badges must be written
  words, optionally reinforced with color/icon.
  Sources: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html and
  https://developer.atlassian.com/platform/forge/ui-kit/components/lozenge/
- W3C status-message guidance says visible waiting/progress/error status changes
  need an accessible way to reach assistive technology. For Codex Dock, row and
  header changes should update accessibility values with the bucket and action,
  but should avoid noisy announcements for every low-level event.
  Source: https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html

Practical UI rule:

- The main status field is a turn/attention field. It answers:
  `Codex is working` or `Your turn`.
- Activity is separate: `Latest activity: command in progress`,
  `Last update 8s ago`, or `No recent live activity`.
- Required action is separate but nested under `Your turn`: `Needs answer`,
  `Review command`, `Review files`, or `Grant permission`.
- Raw thread error is a small local badge: `Error`.

For Dock:

- Show required-action `Your turn` rows first only when there are real pending
  request cards or wait flags.
- Show `Codex is working` rows as active but calm.
- Show quiet `Your turn · Ready` rows in normal recency order with no loud row
  badge.
- Do not add a generic catch-all error row group. If a thread is in raw error
  state, badge only that thread with `Error`.

For Thread Detail:

- Replace the raw `Running` status pill with the routine-state projection:
  `Codex is working` or `Your turn`.
- The header badge is the status surface. Do not repeat the same status in a
  banner or panel below it.
- If the bucket is `Codex is working`, activity evidence can appear as normal
  thread content, not a status banner.
- If the bucket is `Your turn · Ready`, make the composer the obvious next
  action. Do not add a duplicate ready banner.
- If the bucket is `Your turn` with a required action, pin the request card near
  the top or composer.
- If the thread is in raw error state, preserve the last useful content and show
  only the small `Error` badge plus raw details in `State details`.

## The Core UX Need

The raw state model answers engineering questions. The user needs different
answers:

- Do I need to do something?
- Is Codex still working?
- Is it done for now?
- Did something fail?
- Can I safely ignore this row?

The current raw words are too implementation-shaped for the main UI:

- `idle` sounds like inactivity, but in this product it means ready.
- `dormant` and `notLoaded` are storage/runtime facts, not user jobs.
- `unknown` is diagnostic, not a useful badge.
- `waitingOnUserInput` and `waitingOnApproval` are separate raw flags, but both
  mean the user must unblock the thread.
- `blocked` can also appear as goal state, which is a different axis from turn
  runtime state and cannot be assumed to mean the same thing as a pending
  request card.

Best-in-class UX keeps these facts separate internally and collapses them
externally.

## UX Principles

### 1. Attention Before State

The Dock is an action inbox before it is a state inspector.

The first question is not "what enum is this?" The first question is "does this
need me?"

### 2. Quiet States Should Be Quiet

`idle`, `dormant`, and `unknown` should not compete visually with active work or
pending user action.

Use no badge in the default row. Show exact status in detail, filters, debug,
accessibility labels, and inspector surfaces.

### 3. Human Labels Should Be Verbs Or Plain Outcomes

Prefer:

- `Codex is working`
- `Your turn · Ready`
- `Needs answer`
- `Needs approval`
- `Review files`
- `Open on Mac`
- `Error`

Avoid in primary UI:

- `idle`
- `dormant`
- `MCP elicitation`
- `waitingOnUserInput`
- `notLoaded`

The technical words can appear in Debug or State details.

### 4. Request Cards Are The Action Source Of Truth

If a Dock row says `Your turn` because action is required, thread detail must
show the concrete pending request card near the top or pinned above the
composer.

A state badge without an action target is not enough.

### 5. State Changes Matter More Than Steady State

Make meaningful transitions visible: `Codex is working` to `Your turn`, or
`Your turn · Ready` to `Needs answer`.

Do not make a row louder just because it remains in the same state.

### 6. Keep Other Health States Out Of This Slice

Other health states are real product problems, but they are not part of this
focused status mockup pass.

This slice answers "what is this thread doing?" and "is it my turn?"

### 7. Color Is Secondary

Use color to reinforce priority, not to be the only meaning. WCAG and Atlassian
guidance both point the same direction: pair color with text, shape, icon, or
position.

### 8. AI State Needs User Control

Microsoft's human-AI guidance emphasizes timely interruption, contextual
information, efficient invocation, and efficient dismissal. For Codex Dock, that
means:

- show why Codex stopped,
- show what action is needed,
- let the user answer, approve, decline, or open desktop,
- do not create noisy badges for ordinary hidden work.

## Canonical User-Facing Status Model

These are the visible statuses the user should see. There are two routine turn
states. Raw thread error is a small badge on the affected thread/detail, not a
separate product mode.

| Status family | User meaning | Current source signals | Visible labels | Visual behavior |
| --- | --- | --- | --- | --- |
| `Codex is working` | Codex is doing things and it is not the user's turn. | Dock `running`; raw `active` without wait flags. | `Codex is working`; optional activity summary such as `Latest activity: command in progress`. | Active but calm row/header badge. |
| `Your turn` | Codex is done for now, or Codex is blocked until the user acts. | Dock `idle`, `dormant`, `needsInput`, or `needsApproval`; raw `idle`, `notLoaded`, or `active` with wait flags; pending request cards. | `Ready`, `Needs answer`, `Needs approval`, `Review command`, `Review files`, `Grant permission`, `Open on Mac`, `Saved`. | Required actions are prominent. Quiet `Ready`/`Saved` usually get no Dock row badge. |
| `Error` | This thread is in raw error state. | Dock `error`; raw `systemError`. | `Error`. | Small badge on the affected thread row or Thread Detail. Do not create an error section or broader health model. |

## Canonical Visual Weight Policy

Raw state is not visual weight. Visual weight is a product decision about how
much user attention a state deserves.

Use these tiers everywhere:

| Weight tier | Meaning | States in tier | Allowed surfaces |
| --- | --- | --- | --- |
| Interruptive | The user needs to act because Codex is waiting on them. | `Your turn` with a pending required action and request ID. | Dock top section, row badge, detail pinned request card. |
| Prominent | The user should notice while using the app. | `Your turn` with required action. | Dock top group for required actions, row badge, detail request card. |
| Active but calm | The state matters for orientation but should not steal focus. | `Codex is working`. | Row badge, spinner/progress text, detail header. |
| Quiet | The state is useful context but not an action. | `Your turn · Ready`, `Your turn · Saved`. | Recency text, normal row placement, detail copy if useful. |
| Diagnostic | The state is mainly for debugging or support. | `Unknown`, raw `idle`, raw `notLoaded`, goal status, turn status, relay freshness internals. | Debug, state details, filters, accessibility diagnostics. |

This is the main collapse rule:

- `needsInput` and `needsApproval` collapse upward into `Your turn`.
- Request kind expands downward into the exact action: `Needs answer`,
  `Review command`, `Review files`, `Grant permission`, `External tool
  question`, or `Open on Mac`.
- `idle` collapses to `Your turn · Ready`.
- `notLoaded` and archive/history collapse to `Your turn · Saved`.
- `unknown` becomes `Unknown` only if the main UI must show it; otherwise it
  stays in diagnostics.
- Raw thread error becomes `Error` only on the affected thread row/detail.

The Dock can still expose raw filters because they are useful for power users
and tests. The default scan path should not make the user learn raw enum names.

### Why `Ready` Instead Of `Idle`

`Ready` tells the user what they can do next. `Idle` tells the engineer what the
runtime is not doing.

The app can still preserve `idle` in accessibility diagnostics and debug views,
but the main product copy should use `Ready` only when a visible label is needed.
On Dock rows, no label is usually better.

### Why `Your turn` As The Parent

`needsInput` and `needsApproval` differ technically, but both require user
attention. Raw `idle` also means the user can act next, just without urgency.
The Dock should group them under `Your turn`, then expose the exact sublabel:

- `Ready`
- `Needs answer`
- `Needs approval`
- `Review command`
- `Review files`
- `Grant permission`
- `Answer external-tool prompt`
- `Saved`

This keeps the main list scannable while preserving exactness in detail. The
visual weight separates urgent `Your turn` rows from quiet `Your turn · Ready`
or `Your turn · Saved` rows.

## Request Card UX Mapping

Current Swift request-card kinds map to user-facing actions like this:

| Request kind | Current technical title | Recommended user copy | Primary action | Secondary action |
| --- | --- | --- | --- | --- |
| `userInput` | `Input requested` or question header | `Needs answer` | `Send answer` | None unless request supplies choices. |
| `commandApproval` | `Command approval` | `Review command` | `Approve` | `Decline` |
| `fileChangeApproval` | `File change approval` | `Review file changes` | `Approve changes` | `Decline` |
| `permissionsApproval` | `Permission approval` | `Grant permission` | `Allow for this turn` | `Decline` |
| `mcpElicitation` | `MCP elicitation` | `External tool question` | Usually `Decline` today; richer answers later if supported. | `Open details` |
| `unsupported` | `Needs desktop` | `Open on Mac` | None on phone. | None |

Default UI should avoid `MCP` unless the user opens details. "External tool
question" is clearer on a phone.

## Wait And Input Families

The UX should distinguish "Codex is waiting" from "the loaded thread is ready."

| Family | Source-level signal | Top-level bucket | Sublabel | User action | Notes |
| --- | --- | --- | --- | --- | --- |
| Ready for next turn | Raw `idle` or Dock `idle` | `Your turn` | `Ready` or no row badge | Optional: send a new prompt. | This is not a waiting-on-user request. |
| Typed answer needed | `waitingOnUserInput`; request kind `userInput` | `Your turn` | `Needs answer` | Type or choose an answer and send it. | Use the question header/body, not raw method names. |
| Command approval needed | `waitingOnApproval`; request kind `commandApproval` | `Your turn` | `Review command` | Approve or decline. | Show safe command summary and working directory when useful. |
| File approval needed | `waitingOnApproval`; request kind `fileChangeApproval` | `Your turn` | `Review file changes` | Approve or decline. | Use a diff/file count view, not raw JSON. |
| Permission approval needed | `waitingOnApproval`; request kind `permissionsApproval` | `Your turn` | `Grant permission` | Allow for this turn or decline. | Keep the scope explicit. |
| External-tool prompt | request kind `mcpElicitation` | `Your turn` | `External tool question` | Decline today; richer response later if supported. | Keep `MCP` in details/debug unless the user knows the term. |
| Unsupported mobile request | request kind `unsupported` | `Your turn` | `Open on Mac` | Continue on desktop. | Still counts as `Your turn` if the thread cannot continue without desktop action. |
| Goal blocked | goal status `blocked` | No default Dock bucket yet | none | Only if a concrete request/action exists. | Goal state is separate from runtime state and is not currently sent on Dock cards. |

If multiple wait flags or request cards are present, show one parent `Your turn`
group and an action queue in detail. Approval should sort before free-form input
when both are pending because approval prompts can gate filesystem, command, or
permission work.

## Raw-To-UX Projection Rules

Use these projection rules for product surfaces.

| Raw or Dock fact | Visible status family | Label or detail | Notes |
| --- | --- | --- | --- |
| Raw `active` with `waitingOnApproval` | `Your turn` | `Needs approval` or exact request kind | Approval has priority if both approval and input flags are present. |
| Raw `active` with `waitingOnUserInput` | `Your turn` | `Needs answer` | Not the same as `idle`. |
| Raw `active` with no wait flags | `Codex is working` | optional activity summary | Show elapsed or last activity if available. |
| Raw `idle` / Dock `idle` | `Your turn` | `Ready` | Usually no row badge. |
| Raw `notLoaded` / Dock `dormant` | `Your turn` | `Saved` | Usually no row badge. |
| Raw `systemError` / Dock `error` | thread error | `Error` | Small badge on the affected thread row/detail. |
| Dock `unknown` | diagnostic | `Unknown` | Keep out of the primary UX unless the app cannot safely hide it. |
| Goal `active` | keep runtime-derived bucket | no goal sublabel by default | Goal state is separate from runtime turn state. |
| Goal `blocked` | Future `Your turn` only with clear action reason | Required action only | Do not infer from current Dock card; goal status is not currently sent on cards. |
| Other health/status state | out of scope for this slice | none | Do not design it in this pass. |

## Dock UX

The Dock should work like a compact action inbox.

Recommended order:

1. `Your turn` with required action, such as `Needs answer`,
   `Needs approval`, `Review command`, or `Review files`
2. `Codex is working`
3. pinned rows, if any are not already in the top groups
4. quiet `Your turn · Ready` rows
5. quiet `Your turn · Saved` rows through Archive or explicit filters

There is no catch-all error section. If one thread has an error, it stays in the
list as that thread with a small `Error` badge.

### Dock Row Rules

Each row should answer:

- title
- repo/branch/host
- latest meaningful activity
- user-facing state only if it matters
- whether it is pinned
- whether the action is mine

Recommended row state labels:

| Situation | Row badge | Row support text |
| --- | --- | --- |
| Needs typed input | `Needs answer` | "Codex asked a question." |
| Needs command approval | `Review command` | Show command summary if safe and short. |
| Needs file approval | `Review files` | Show file count or root, not raw JSON. |
| Needs permission | `Grant permission` | Show scope and turn if available. |
| Active work | `Codex is working` | "Last activity 2m ago" or active step summary. |
| Ready | none | Recency text is enough. |
| Saved/not loaded | none | Archive/history placement is enough. |
| Raw thread error | `Error` | Keep it small; do not create a separate error section. |

### Your-Turn Section

If any thread needs required user action, the Dock should show a top section:

`Your turn 3`

Rows in this section should be actionable. Tapping a row opens the exact detail
request card, not just the thread top.

### Filters

Current filters expose raw statuses. Keep raw filters available, but make the
first-class filter human:

- `Your turn`
- `Codex is working`

Advanced filters can expand to raw values:

- `needsInput`
- `needsApproval`
- `idle`
- `dormant`
- `running`
- `error`
- `unknown`

Error filtering is out of scope for this slice. A raw thread error only gets an
`Error` badge on the affected row.

## Thread Detail UX

Thread detail should preserve exact action detail.

### Header

The header state should show one concise label:

- `Codex is working`
- `Your turn · Ready`
- `Your turn · Needs answer`
- `Your turn · Review command`
- `Your turn · Review files`
- `Your turn · Grant permission`
- `Error` only when the thread itself is in raw error state

Other health/status states are outside this slice. Do not merge those with the
turn/status model in this pass.

### Pending Request Placement

When there is a pending request card:

- pin it above the composer or near the top of the message list,
- preserve the card while the thread is visible,
- show one primary action and one clear decline/cancel action where supported,
- keep detailed JSON/debug behind disclosure,
- keep the user's draft if the app backgrounds or reconnects.

### Detail Copy

Recommended copy:

| Current idea | Better user copy |
| --- | --- |
| `Input requested` | `Codex needs an answer` |
| `Command approval` | `Review command` |
| `File change approval` | `Review file changes` |
| `Permission approval` | `Grant permission` |
| `MCP elicitation` | `External tool question` |
| `Needs desktop` | `Open on Mac` |
| `Idle` | `Ready for your next message` |
| `Not loaded` | `Saved thread` |

## Scope Boundaries

Anything outside in-app thread status is intentionally out of scope for this
focused status cut.

The current UX target is simpler:

- Dock rows show the thread's own status when a status matters.
- Other health/status surfaces are out of scope for this status slice.
- Quiet ready rows stay quiet.

## Accessibility Rules

State UI must be accessible without color.

Rules:

- Every state badge has text.
- Important state changes have VoiceOver-accessible announcements.
- Dynamic status messages use appropriate accessibility APIs.
- Do not use orange alone to mean "my action is required."
- Do not use red alone to mean "error."
- Keep badges to one or two words to avoid truncation.
- If a row is actionable, its accessibility value should include the exact
  action: `Needs answer`, `Review command`, or `Review file changes`.
- Avoid screen-reader noise for every progress tick. Announce meaningful
  transitions, not every low-level event.

WCAG status-message guidance maps well to native app behavior: if the UI adds a
status message without moving focus, assistive technology still needs to learn
about it.

## Visual System

Use a restrained status grammar:

| UX state | Shape/icon | Color role | Label |
| --- | --- | --- | --- |
| `Your turn` | hand/alert/checklist icon for required action; no badge for quiet ready/saved rows | orange or amber for required action; neutral for quiet rows | `Needs answer`, `Review files`, `Review command`, `Ready`, `Saved` |
| `Codex is working` | spinner/progress dot | green or blue-green | `Codex is working` |
| `Error` | small warning badge | red only as secondary support | `Error` |

Avoid a rainbow of low-value states. The user should learn one grammar:

- warm color means my action,
- active color means Codex working,
- red means this thread is in raw error state,
- neutral means safe to ignore.

## Anti-Patterns

Do not:

- show `Idle` as a prominent row badge,
- call `idle` "waiting on user input,"
- make a row louder when it simply remains in the same waiting state,
- badge every active turn update,
- expose `MCP elicitation` as default phone copy,
- use one orange badge for every request without saying what action is needed,
- use color-only rails as the only signal,
- bury pending approvals below long logs,
- add a generic error chip, tab, section, or header state when an exact
  thread `Error` badge would do.

## Open Implementation Questions

These are product/engineering questions for the implementation phase, not
blockers for this UX model:

- Should `Your turn` required-action section order be by request age, thread
  recency, or action type priority?
- Should `needsApproval` always outrank `needsInput` when both flags exist, or
  should the detail surface show a grouped action queue?
- What new relay card fields are needed to safely expose request ID, request
  kind, and pending timestamp?
- Should goal `blocked` become a first-class card attention reason, and if so,
  what user action proves it is resolvable from the phone?

## Recommended Focused Build Slice

The smallest high-value product slice is:

1. Add a user-facing projection layer over `DockRowStatusKind`.
2. Use that projection in Dock rows and row accessibility values.
3. Add a `Your turn` Dock section or top group only for required actions.
4. Rename default visible row copy:
   - `needsInput` -> `Needs answer`
   - `needsApproval` -> action-specific approval copy when known
   - `idle` -> no badge
   - `dormant` -> no badge
5. Replace Thread Detail's raw row-status pill with the same projection:
   `Codex is working`, `Your turn · Ready`, or required-action `Your turn`.
6. Do not add duplicate Thread Detail status banners below the header badge.
7. Show raw thread error only as a small `Error` badge on the affected row or
   Thread Detail.
8. Keep other health/status surfaces out of this slice.
9. Keep activity copy separate from state copy.
10. Keep raw state in filters/debug/`State details`.

Anything outside in-app thread status is a later slice. It should not be part of
the focused Dock/Thread Detail mockups for this pass.

## Mockup Brief

The companion mockup package lives at:

`docs/mockups/codex-dock-thread-state-ux-2026-06-04/`

The written model in this document is canonical. The current mockup package uses
deterministic SVG/PNG renders so the status labels remain exact.

It uses fresh simulator screenshots captured on 2026-06-04:

- `inputs/current-sim-latest-2026-06-04.png`
- `inputs/current-sim-thread-detail-2026-06-04.png`
- `inputs/current-sim-filters-2026-06-04.png`

The focused status mockups for this pass should show four source-backed
screens:

1. Dock overview with required-action `Your turn`, active `Codex is working`,
   quiet ready rows, and one affected thread row badged `Error`.
2. Thread Detail while Codex is active: header badge `Codex is working`, no
   duplicate status banner, and activity evidence as normal thread content.
3. Thread Detail after Codex finishes: header badge `Your turn · Ready`, no
   duplicate ready banner, final assistant message, and composer as the main
   next action.
4. Thread Detail raw error state: a small `Error` badge, last useful content
   preserved, no error banner, and raw `systemError` visible only in
   `State details`.

Do not include other health/status surfaces in these focused mockups.

Generated images are design-review artifacts only. This document and source
code remain the product and implementation references.
