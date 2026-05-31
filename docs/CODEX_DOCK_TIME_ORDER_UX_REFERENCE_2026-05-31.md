# Codex Dock Conversation, Time, And Order UX Reference

Date: 2026-05-31

Companion technical reference:
[Codex App-Server Thread, Turn, Message, And Dock Data Reference](./CODEX_APP_SERVER_THREAD_MESSAGE_TURN_DATA_REFERENCE_2026-05-31.md)

Purpose: define the best user experience for conversation readability,
message-type density, time, order, recency, unread state, and "where am I in the
conversation?" in Codex Dock, independent of the current technical limitations.

This is not an implementation plan. It is the product and interaction-design
target: the experience the app should provide so the user never has to infer
what came in, what order it came in, what changed while they were away, or how
old each visible thread/message is.

## Net

Codex Dock should treat time and order as first-class content, not metadata.
Every card and every thread should answer three questions without effort:

- What changed most recently?
- What did I miss since I last looked?
- When exactly did this happen if I need to audit it?

The best UX is a two-layer time system:

- The default surface shows relative time because it is fast to scan:
  `now`, `7m ago`, `2h ago`, `Yesterday`, `May 31`.
- The detail surface always exposes exact local time, date, and timezone:
  `Today at 2:14:32 PM CDT`.

The best UX is also a two-layer order system:

- Dock cards behave like an inbox, sorted by newest meaningful activity by
  default.
- Thread detail behaves like a readable conversation, with a stable message
  order, visible day dividers, a clear first-unread divider, and a floating
  "new messages" affordance when the user is not at the live edge.

The user should never have to remember, guess, or reverse-engineer time. The UI
should show it, label it, and keep it accessible.

The same is true for message density. Codex does not produce a simple chat
transcript; it produces turns that can contain user messages, assistant
messages, plans, reasoning summaries, command executions, file changes, tool
calls, web searches, image events, review-mode markers, compaction markers, and
sub-agent coordination. The best UX is not to show all of those as equal chat
messages.

Default thread detail should be a conversation view: what I said, what the
primary thread agent said back, and any active request that needs me. Everything
else should be available through clear progressive disclosure.

## Research Base

The findings below synthesize current design-system and messaging-product
patterns from:

- Nielsen Norman Group progressive disclosure:
  https://www.nngroup.com/articles/progressive-disclosure/
- Apple Human Interface Guidelines disclosure controls:
  https://developer.apple.com/design/human-interface-guidelines/disclosure-controls
- Primer RelativeTime guidelines and accessibility guidance:
  https://primer.style/product/components/relative-time/guidelines/
  and https://primer.style/product/components/relative-time/accessibility/
- Cloudscape timestamp pattern:
  https://cloudscape.design/patterns/general/timestamps/
- Atlassian date and time writing guidelines:
  https://atlassian.design/content/writing-guidelines/writing-guidelines/date-and-time-guideline/
- Slack unread and screen reader behavior:
  https://slack.com/help/articles/226410907-View-all-your-unread-messages
  and https://slack.com/help/articles/360000411963-Use-Slack-with-a-screen-reader
- Stream Chat date separator guidance:
  https://getstream.io/chat/docs/sdk/react/components/utility-components/date-separator/
- MUI X Chat message-list patterns:
  https://mui.com/x/react-chat/material/message-list/
- Intercom Inbox conversation events:
  https://www.intercom.com/help/en/articles/13334840-conversation-events-in-the-inbox
- GitHub timeline-events API:
  https://docs.github.com/en/rest/issues/timeline
- GOV.UK accordion and tabs guidance:
  https://design-system.service.gov.uk/components/accordion/
  and https://design-system.service.gov.uk/components/tabs/
- Microsoft Fluent 2 drawer and Responsible AI guidance:
  https://fluent2.microsoft.design/components/web/react/core/drawer/usage
  and https://fluent2.microsoft.design/responsible-AI
- IBM Carbon filtering and Carbon for AI guidance:
  https://carbondesignsystem.com/patterns/filtering/
  and https://carbondesignsystem.com/guidelines/carbon-for-ai/
- PatternFly log-viewer guidance:
  https://www.patternfly.org/extensions/log-viewer/
- Atlassian lozenge guidance:
  https://atlassian.design/components/lozenge
- OpenAI Agents SDK human-in-the-loop and tracing guidance:
  https://openai.github.io/openai-agents-python/human_in_the_loop/
  and https://openai.github.io/openai-agents-python/tracing/
- OpenAI reasoning-model guidance:
  https://developers.openai.com/api/docs/guides/reasoning
- Material Design list guidance:
  https://m1.material.io/components/lists.html
- Maersk timeline/activity-log guidance:
  https://designsystem.maersk.com/components/timeline/
- Nielsen Norman Group usability heuristics summary:
  https://media.nngroup.com/media/articles/attachments/Heuristic_Summary1_A4_compressed.pdf

The strong common pattern:

- Relative timestamps are easier to scan for recency.
- Exact timestamps must remain available.
- Date dividers are standard in message lists.
- Unread boundaries are standard in high-volume messaging.
- Auto-scroll should pause when the user has moved away from the live edge.
- Good timeline UIs make actor, event, timestamp, and order visible in a
  repeatable pattern.
- Complex products separate the main conversation from background events.
- Progressive disclosure is the right model when common content and advanced
  detail both matter.
- Hidden detail controls are only appropriate for content users do not always
  need; approvals, failures, and blocked states must remain visible.
- Large details need an inspector or drawer so the user can inspect depth without
  losing the thread.
- Raw debug detail should use log/trace patterns, not chat-card patterns.
- Accessibility requires more than hover-only tooltips.

## The Core UX Problem

The current user feeling is: "I have no sense of time and order."

That is not a small formatting problem. It is a trust problem.

When time and order are unclear, the user cannot answer basic questions:

- Did Codex reply after I sent my last message?
- Is this thread active now or stale?
- Did a tool request arrive before or after the assistant response?
- Did I already see this message?
- Which thread needs attention first?
- Is a Dock card at the top because it is pinned, unread, running, or actually
  newer?
- Am I reading new content or scrolling through old content?
- Did the app just receive new messages while I was reading older ones?
- Is this row an actual assistant reply, or just the agent's hidden work log?

Best-in-class UX fixes this by giving the user visible anchors at every level:

- card-level recency
- card-level unread state
- thread-level last activity
- thread-level first-unread boundary
- message-level timestamp affordances
- date dividers
- live-edge state
- clear sort labels
- exact timestamp access
- accessible read order

The deeper issue is that time/order and message-type density are linked. If
tool calls, reasoning, plans, and compaction markers appear as peer "messages,"
the user loses the actual back-and-forth even when the raw order is technically
correct.

## Design Principles

### 1. Time Is Content

Do not treat timestamps as decorative gray text. In Dock, time tells the user
where to spend attention.

Every visible thread card needs a time label. Every thread detail needs a last
activity label. Every message group needs a time anchor. Every unread boundary
needs a timestamp.

### 2. Recency And Exactness Are Different Jobs

Relative time answers "how old is this?"

Exact time answers "when exactly did this happen?"

Both are needed. The dock and timeline should use relative time for scanning,
with exact time one tap, long press, detail row, or accessible label away.

### 3. Order Must Be Visible, Not Inferred

If a list is newest-first, the UI must make that clear.

If a thread reads oldest-to-newest, the UI must make that clear.

If a card is pinned or grouped above newer content, the UI must still show its
real activity age so the user does not mistake placement for recency.

### 4. Unread Is A Place, Not Just A Count

Unread count is useful, but not enough. A user needs to land exactly where new
content starts.

Best-in-class behavior:

- the card says how many new messages/events exist
- opening the thread lands at the first unread message
- the timeline shows a "New since you last looked" divider
- the user can jump to first unread again
- reading does not erase orientation too early

### 5. Live Updates Must Not Steal Context

When the user is at the live edge, new messages can appear inline and the view
can follow them.

When the user has scrolled away, new messages should not yank the viewport.
Instead, show a floating affordance such as:

- `3 new messages`
- `Jump to latest`
- `Codex replied 2m ago`

MUI X Chat documents this same pattern: auto-scroll while the user is near the
bottom, but pause automatic scrolling when the user has moved away so they can
read earlier content without interruption.

### 6. Accessibility Is Part Of The Timestamp

A hover-only timestamp is not enough.

Primer specifically warns that relying only on a native `title` tooltip leaves
keyboard and screen reader users without reliable access to the precise time.
Cloudscape and Atlassian both reinforce the pattern: relative labels are useful,
but exact timestamps must remain reachable.

For Dock, every relative label must have:

- a visible exact equivalent in details, or
- an accessible action, tooltip, popover, or inspector that works without mouse
  hover, and
- a screen-reader label that includes the exact time when the relative label is
  ambiguous.

### 7. Conversation Is The Primary Layer

Codex Dock should not make the user parse an event stream to find the
conversation.

The default layer should show:

- user-authored `userMessage` content
- primary thread-agent `agentMessage` content
- active request cards that need the user's decision or answer
- small, collapsed work summaries attached to the relevant turn

The default layer should not show every command, tool call, reasoning item, web
search, file-change detail, sub-agent coordination event, context compaction, or
review-mode marker as a full-height peer row.

### 8. Hidden Detail Must Be Counted

Progressive disclosure fails if hidden content disappears without a trace.

If the conversation view hides work/activity rows, the UI should say so:

- `6 work events hidden`
- `3 commands, 1 file change, 1 web search`
- `Show activity`
- `Show raw events`

This protects trust: the main view stays readable, but the user knows the
underlying event stream has more detail.

### 9. Requests Pierce The Filter

Anything that requires the user should break through the default filter.

Examples:

- command approval
- file-change approval
- permission approval
- tool/user-input request
- MCP elicitation

These are not conversational replies, but hiding them behind an activity filter
would make the mobile app miss its most important job.

## Recommended Mental Model

Use three distinct time concepts in the UX language:

### Activity Time

What most users mean by "last updated."

Examples:

- `Codex replied 4m ago`
- `Needs approval since 12m ago`
- `You sent 1h ago`

Use this on Dock cards and in the thread header.

### Message Time

When a specific message, tool event, request, or response happened.

Examples:

- `Today at 2:14 PM`
- `2:14:32 PM CDT`
- `May 31 at 2:14 PM`

Use this inside thread detail and timestamp detail affordances.

### Seen Time

Where the user left off.

Examples:

- `New since 2:09 PM`
- `You last read here`
- `4 unread events`

Use this as an explicit divider in thread detail and as a badge/count on Dock
cards.

These concepts should not be collapsed into a single vague timestamp.

## Message-Type UX Model

Codex app-server v2 exposes `ThreadItem` as a tagged union with a camelCase
`type` field. The companion data reference documents the field-level contract.
This UX section defines how those item types should feel to a user.

Net: the product should treat raw Codex items as source material, not as the UI
taxonomy.

### Source Truth From Codex

The app-server v2 source defines these `ThreadItem.type` values in
`/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/item.rs`:

| `ThreadItem.type` | What Codex is exposing | UX classification | Default treatment |
| --- | --- | --- | --- |
| `userMessage` | User input content, including text and possible image inputs. | Primary conversation. | Show in Conversation. |
| `agentMessage` | Assistant-authored text, with optional `phase` such as `commentary` or `final_answer`. | Primary conversation, but phase matters. | Show in Conversation. Make final answers more prominent than commentary. |
| `hookPrompt` | Hook-generated user-role prompt fragments reconstructed from persisted provider messages. | Internal/system prompt context. | Hide by default; show in Activity or Debug. |
| `plan` | Proposed or completed plan text. Codex marks this as experimental and separate from `agentMessage`. | Work planning / thinking. | Hide by default or show as a collapsed turn note. |
| `reasoning` | Reasoning summary text and optional raw reasoning content. | Work/thinking detail. | Hide by default; disclose through a `Reasoning` section when allowed and useful. |
| `commandExecution` | Shell or unified-exec command, cwd, parsed actions, status, output, exit code, duration. | Work/tooling. | Collapse under Work; surface failures and long-running commands. |
| `fileChange` | Patch/file update changes and apply status. | Work/artifact. | Show compact artifact summary; surface approval/failure. |
| `mcpToolCall` | MCP server/tool invocation, arguments, status, result/error, duration. | Work/tooling/integration. | Collapse under Work; surface failures and user-relevant app results. |
| `dynamicToolCall` | Dynamic tool invocation with namespace/tool/arguments/status/output/success/duration. | Work/tooling/integration. | Collapse under Work; surface failures and user-visible results. |
| `collabAgentToolCall` | Parent/child agent coordination: spawn, send input, wait, close, resume, receiver thread IDs, prompt/model/statuses. | Sub-agent activity. | Collapse under Work; show a link to sub-agent detail when useful. |
| `webSearch` | Web search/open/find action and query. | Research activity. | Collapse as `Searched web`; show source details on expand. |
| `imageView` | Image path viewed by the agent. | Attachment/reference activity. | Show only if user-facing; otherwise collapse under Work. |
| `imageGeneration` | Image-generation status, revised prompt, result, saved path. | Artifact generation. | Show output artifact if it is the answer; otherwise collapse under Work. |
| `enteredReviewMode` | Marker that review mode began, with review text. | Mode/system marker. | Hide from Conversation; show in Activity. |
| `exitedReviewMode` | Marker that review mode ended, with review output/fallback text. | Mode/system marker. | Hide from Conversation; show in Activity. |
| `contextCompaction` | Internal context/history compaction marker. | System/history management. | Hide from Conversation; show in Debug or a low-noise Activity marker. |

The source split is important:

- core `codex_protocol::items::TurnItem` has a smaller persisted set:
  `UserMessage`, `HookPrompt`, `AgentMessage`, `Plan`, `Reasoning`,
  `WebSearch`, `ImageView`, `ImageGeneration`, `FileChange`, `McpToolCall`, and
  `ContextCompaction`
- app-server v2 `ThreadItem` adds UI/runtime-facing types such as
  `commandExecution`, `dynamicToolCall`, `collabAgentToolCall`,
  `enteredReviewMode`, and `exitedReviewMode`
- the history builder in
  `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/thread_history.rs`
  reconstructs many v2 items from persisted events and live event replay, so a
  `Turn.items` array is a display reconstruction, not raw provider output

Codex also has lower-level `ResponseItem` values such as provider `message`,
`reasoning`, `local_shell_call`, `function_call`, `tool_search_call`,
`web_search_call`, `image_generation_call`, compaction items, and output items.
Those are not the correct primary UI layer for Dock. Dock should base thread
detail on app-server `Turn` and `ThreadItem` data, then optionally expose raw
provider details in Debug.

### How Codex Creates These Items

For UX, the creation path matters because it tells us how much confidence the UI
can place in each row.

Codex reconstructs historical thread detail this way:

- `UserMessageEvent` becomes `userMessage` with a synthetic sequential item id
  like `item-1`.
- `AgentMessageEvent` becomes `agentMessage` with synthetic sequential item ids.
- `AgentReasoningEvent` and raw reasoning content become `reasoning`; adjacent
  reasoning chunks can be merged into one reasoning item.
- `ItemStartedEvent` and `ItemCompletedEvent` mainly update `plan` items in the
  history builder.
- `WebSearchBeginEvent` and `WebSearchEndEvent` upsert `webSearch` by call id.
- `ExecCommandBeginEvent` and `ExecCommandEndEvent` upsert
  `commandExecution` by call id and turn id.
- guardian/approval events can create `commandExecution` rows with declined or
  failed states.
- `ApplyPatchApprovalRequestEvent`, `PatchApplyBeginEvent`, and
  `PatchApplyEndEvent` upsert `fileChange`.
- `DynamicToolCallRequest` and `DynamicToolCallResponseEvent` upsert
  `dynamicToolCall`.
- `McpToolCallBeginEvent` and `McpToolCallEndEvent` upsert `mcpToolCall`.
- image view/generation events become `imageView` or `imageGeneration`.
- collaboration events become `collabAgentToolCall` entries for spawn, send
  input, wait, close, and resume actions.
- review-mode events become `enteredReviewMode` and `exitedReviewMode`.
- compaction events become `contextCompaction`.

Design implication: a row's `type` is less important than its user job. The UI
should not let a synthetic item id, tool-call id, or reconstructed event decide
whether something looks like a chat reply.

### What The Current Dock Client Already Does

Current Swift rendering is already moving in the right direction:

- `ThreadDetailMessageFilter.default` is `.messages`.
- `.messages` includes `ThreadEventVisibilityCategory.request`.
- `.messages` also includes `ThreadEventVisibilityCategory.message` when the
  event kind is `userMessage` or `agentMessage`.
- `userMessage` maps to a user message row.
- `agentMessage` maps to an agent message row.
- `plan` and `reasoning` map to `agentMessage` kind but `thinking` visibility,
  so they are hidden from the default filter.
- `commandExecution` maps to `command` and possible `output` tooling rows.
- `fileChange` maps to a request-category event, so it is currently
  default-visible.
- `mcpToolCall` and `dynamicToolCall` map to tooling rows.
- `hookPrompt`, `collabAgentToolCall`, `webSearch`, `imageView`,
  `imageGeneration`, `enteredReviewMode`, `exitedReviewMode`, and
  `contextCompaction` currently fall through as unsupported/unknown events.
- live `item/agentMessage/delta` maps to a visible message update.
- live plan/reasoning deltas map to thinking rows.
- server requests map to visible request cards.

The main product gap is naming and hierarchy. `Messages` is too ambiguous for a
filter that intentionally means "conversation plus active requests." The best
label is `Conversation`. The full raw event view should not be named `All`
alone; it should be named `Activity` or `Full Timeline`, with `Debug` reserved
for IDs and raw payload details.

The other product gap is supported-but-nonprimary item coverage. Unknown rows
should be rare in user-facing modes. Newer Codex item types should map to
readable Work/Activity labels even when hidden from Conversation.

Recommended current-client corrections:

- Rename `.messages` UI copy from `Messages` to `Conversation`.
- Rename `.all` UI copy from `All` to `Activity`.
- Add a real `Debug` mode before exposing raw or unsupported labels.
- Keep active `ServerRequestCard` rows default-visible.
- Reclassify resolved `fileChange` as Work, while active file-change approvals
  remain request/attention rows.
- Add explicit render support for `webSearch`, `imageView`, `imageGeneration`,
  `collabAgentToolCall`, `enteredReviewMode`, `exitedReviewMode`,
  `contextCompaction`, and `hookPrompt` in Activity/Debug.
- Preserve `agentMessage.phase` in the render model so commentary and final
  answer can be styled differently.
- Use protocol `startedAtMs` / `completedAtMs` for live item lifecycle timing
  when present instead of always falling back to local receive time.

### Default View: Conversation

Default Thread Detail should be `Conversation`.

It should answer one human question:

```text
What did I say, what did the primary thread agent say back, and does anything
need me right now?
```

Visible by default:

- `userMessage`
- `agentMessage`
- live `item/agentMessage/delta`
- active `ServerRequestCard` rows
- compact inline work summary chips when a turn contains hidden work

Not visible as full rows by default:

- `hookPrompt`
- `plan`
- `reasoning`
- `commandExecution`
- `fileChange` details after approval is resolved
- `mcpToolCall`
- `dynamicToolCall`
- `collabAgentToolCall`
- `webSearch`
- `imageView` unless it is a user-visible attachment/artifact
- `imageGeneration` unless the generated image is the user-visible result
- `enteredReviewMode`
- `exitedReviewMode`
- `contextCompaction`
- unknown/raw provider events

The default should be intentionally opinionated. A user who opens a thread on a
phone usually wants the readable back-and-forth, not the full agent execution
trace.

### Assistant Message Phases

`agentMessage.phase` should shape the row, not decide whether the row exists.

Recommended behavior:

| `phase` | Meaning | Conversation treatment | Dock card unread wording |
| --- | --- | --- | --- |
| `final_answer` | Terminal answer text for the turn. | Prominent assistant reply. | `Codex replied 4m ago`. |
| `commentary` | Mid-turn assistant text or progress narration. | Visible but lower emphasis, grouped under the turn. | Usually `Codex updated 4m ago`, unless no final answer exists yet. |
| `nil` | Legacy or provider-unknown phase. | Treat as an assistant reply for compatibility. | `Codex replied 4m ago`. |

If both commentary and a final answer exist in the same turn, the final answer
should be the main reply. Commentary should not inflate the user's sense that
there were multiple complete answers.

### Turn Grouping

Conversation should be grouped by turn, not by raw item type.

A good turn shape:

```text
Today

You                                                    2:09 PM
Summarize the message-type UX issue.

Work hidden: plan, 2 commands, 1 file change, web search
Show activity

Codex                                                 2:12 PM
The right model is Conversation by default, Activity on demand...
```

Turn grouping rules:

- Use `Turn.id` for grouping and deep links.
- Use `Turn.status` to label `running`, `failed`, `interrupted`, or `completed`.
- Use `Turn.startedAt` as the best historical anchor for user input.
- Use `Turn.completedAt` as the best historical anchor for final assistant
  answer when per-message timestamps are unavailable.
- Use item order inside `Turn.items` to preserve cause/effect.
- Keep hidden work counts attached to the turn where the work happened.
- If a turn has no user message, show it only in Activity unless it needs user
  attention.

This lets the user understand "my prompt caused this work and this answer"
without reading every tool event.

### Work Summary Under A Turn

Hidden work should become a compact summary, not a mystery.

Recommended summary examples:

- `Work hidden: plan, 3 commands, 1 file change`
- `Searched web and edited 2 files`
- `Ran 4 tools - 1 failed`
- `Asked 2 sub-agents - both complete`
- `Context compacted during this turn`

The summary should be clickable/tappable:

- collapsed state: one line
- expanded state: chronological Activity rows for that turn only
- full mode: all turns show Activity rows inline

Failures, unresolved approvals, and active waits should be promoted:

- `Command failed`
- `Waiting for approval`
- `Sub-agent still running`
- `Tool needs input`

### View Modes

Dock should expose clear modes. This avoids trying to make one feed serve every
job.

| Mode | Purpose | Includes | Default order |
| --- | --- | --- | --- |
| `Conversation` | Read the actual human/primary-agent exchange. | User messages, agent messages, active requests, hidden-work summaries. | Oldest to newest. |
| `Work` | Understand what the agent did without raw noise. | Conversation plus collapsed/expanded plan, commands, file changes, tools, web search, artifacts, sub-agent activity. | Oldest to newest within turns. |
| `Files` | Inspect changed files and diffs without reading the whole activity trace. | File-change summaries, changed paths, diff previews, apply status, related commands. | Grouped by turn, then path. |
| `Activity` | Audit the full event timeline. | Every supported `ThreadItem` and live lifecycle event, with type labels. | User-selectable; default oldest to newest for thread context. |
| `Debug` | Diagnose protocol/data issues. | Raw IDs, `ThreadItem.type`, `turnId`, `itemId`, sequence fields, JSON payload excerpts, timestamp provenance. | Stable source order with explicit sequence labels. |

Recommended control labels:

- `Conversation`
- `Work`
- `Files`
- `Activity`
- `Debug`

Avoid:

- `Messages` when it really includes requests
- `All` when the difference is not explained
- `Checks` if it mixes commands, tools, approvals, and activity without a clear
  model

Tabs are appropriate only when these modes are peers. They should not hide
critical content that needs to be read in order, and they should not be nested
inside disclosure groups. If the user needs to compare details while staying in
the conversation, use an inspector/drawer instead of forcing a mode switch.

### Per-Turn Disclosure And Inspector

Small optional detail belongs inside the turn. Large optional detail belongs in
an inspector.

Per-turn disclosure should use compact labeled chips with counts:

- `Plan`
- `Reasoning summary`
- `Commands 3`
- `Tools 4`
- `Files 5`
- `Web 2`
- `Sub-agents 2`
- `Debug`

Collapsed chips should show status:

- `Commands 3`
- `Commands 3 - 1 failed`
- `Files 5 - applied`
- `Web 2 - sources`
- `Sub-agents 2 - running`

Expanded per-turn detail should stay short. If the content is long, open a
detail inspector rather than pushing the conversation far away.

Inspector/drawer content:

- selected turn summary
- selected event type and status
- command text, cwd, exit code, duration, and output
- file paths, patch status, and diff preview
- tool name, server/namespace, arguments summary, result/error summary
- web query/action/source details
- approval request, decision, risk/context, and result
- sub-agent sender/receiver thread IDs, prompt summary, model, status
- raw payload and IDs only behind Debug controls

The inspector should preserve the thread position. Closing it should return the
user to the same turn and scroll location.

### Approvals, Errors, And Blockers Are Not Optional Detail

Progressive disclosure should not hide content that the user needs to act on.

Always surface:

- active approvals
- active input requests
- failed commands or tools when the turn depends on them
- blocked/waiting states
- interrupted or failed turns
- final file-change outcome when file edits are the user's requested result

These can still have expandable details, but the existence of the issue must be
visible in Conversation.

### Raw Debug And Trace View

Debug is a different product surface from Conversation.

Debug should use a log/trace pattern:

- monospace payload sections
- exact timestamps and timestamp provenance
- `threadId`, `turnId`, `itemId`, request id, event id
- `ThreadItem.type`
- sequence fields
- source route/method
- search and event-type filters
- severity/status filters
- line wrapping toggle
- copy event / copy JSON / export visible trace
- sensitive-data warnings where raw payloads may include prompts, outputs, or
  tool arguments

Raw JSON should never be the default representation of agent work.

### Reasoning Summary Treatment

Reasoning is not a normal assistant reply.

Recommended behavior:

- show `Reasoning summary` as a collapsed Work chip when present
- keep raw reasoning/debug payloads out of Conversation
- label summaries as summaries, not as the agent's answer
- show reasoning timing/order inside the turn when Activity is enabled
- never use reasoning text as the Dock card headline when an `agentMessage`
  exists

This keeps the answer and the work explanation separate.

### Search Scopes

Search should default to the same mental model as the screen.

Default:

- search user text
- search assistant text
- search visible request summaries

Explicit scopes:

- `Conversation`
- `All activity`
- `Commands`
- `Files`
- `Tools`
- `Web`
- `Reasoning`
- `Raw IDs`

For large activity/debug datasets, filters should support an explicit apply
step. Live-updating every checkbox change can make the trace feel unstable and
slow, especially when the user is selecting multiple event categories.

Search results should disclose when matches are hidden by the current view:

```text
3 matches in hidden work activity
Show activity matches
```

This prevents the user from thinking content is missing.

### Unread Semantics By Type

Unread should distinguish replies from background activity.

Recommended categories:

| Category | Counts as | Card wording |
| --- | --- | --- |
| User/agent conversation | Primary unread. | `Codex replied 4m ago`, `1 new reply`. |
| Active request | Primary attention. | `Needs approval since 12m ago`. |
| Failed work | Secondary attention unless it blocks the turn. | `Command failed 3m ago`. |
| Hidden work completed | Activity unread. | `5 work events hidden`. |
| System/compaction/review marker | Debug/activity unread only. | Do not promote unless it explains a visible state. |

This avoids a noisy Dock card that jumps to the top because a background command
emitted output after the actual answer was already read.

### Primary Thread Agent Versus Sub-Agents

The default conversation should show the primary thread agent, not every
sub-agent's internal transcript merged into one feed.

When `collabAgentToolCall` appears:

- show a compact work line such as `Asked design-review agent - complete`
- include child `receiverThreadIds` as links when available
- show prompt/model/reasoning effort only in Work/Activity/Debug
- do not count child-agent chatter as primary conversation unread unless the
  parent agent surfaces it in an `agentMessage`

This keeps "what Codex told me" separate from "how Codex coordinated work."

### Attachments And Artifacts

Some non-message item types become user-visible content when they are the actual
answer.

Rules:

- User images inside `userMessage.content` are part of Conversation.
- `imageView` is usually Work unless the image is being shown back to the user
  as context.
- `imageGeneration` should be a Conversation artifact only when the generated
  image/result is the user-facing response.
- File changes should be summarized in Conversation when they are the outcome:
  `Edited 3 files`, with details in Work.
- Command output should never become the main assistant reply unless the agent
  explicitly includes it in `agentMessage`.

### Event Density Ladder

Use an event-density ladder instead of a binary filter.

```text
Conversation
  You / Codex / needs me

Work
  Conversation + what the agent did

Files
  File changes and diffs

Activity
  Every supported event, readable labels

Debug
  Raw protocol fields and IDs
```

The ladder should be persistent per thread or per user preference, but new users
should always start at `Conversation`.

### Why This Matches Best Practice

This model matches current UX research and production patterns:

- NN/g progressive disclosure says to show the most important options first and
  reveal specialized details only when users ask for them.
- Apple disclosure guidance says advanced or less-used information should sit
  behind clearly labeled disclosure controls.
- Intercom Inbox explicitly focuses conversation view on messages by default
  and lets users toggle conversation/ticket events to see technical background
  actions.
- GitHub issue timelines mix comments and many event types, but the UI and API
  keep event type, actor, and timestamp explicit instead of pretending every
  event is a comment.
- Slack unread triage separates scanning, sorting, filtering, jumping into the
  conversation, marking read, undo, and leaving content unread for later.
- MUI X Chat keeps the message list centered on chat behavior: date dividers,
  streaming, auto-scroll only near the live edge, scroll-to-bottom affordance,
  and history loading that preserves position.

### Message-Type Anti-Patterns

Do not:

- render every `ThreadItem` as a same-weight chat card
- label plan/reasoning/tool output as if it were the assistant's reply
- make `Messages` include hidden work without saying so
- hide active approval/input requests behind an Activity filter
- let command output become the Dock card's main unread headline when a real
  assistant reply exists
- count `contextCompaction` as a user-visible unread message
- merge sub-agent transcripts into the primary conversation without attribution
- show unknown item types only as `Unsupported event` in default Conversation
- omit hidden-work counts
- make users switch to Debug just to know whether work happened

## Dock Card UX

The Dock card is an inbox row. It should make the newest important change
obvious at a glance.

### Required Card-Level Signals

Every card should show:

- title or thread label
- current status
- last meaningful activity actor/source
- whether that activity is a reply, a request, work activity, or system activity
- relative activity age
- unread count if any
- unread category, especially `reply` versus `work`
- first unread age if different from last activity age
- running/waiting state when applicable
- exact timestamp available on long press, context menu, details popover, or
  accessibility label

Best card examples:

- `Codex replied 4m ago`
- `Needs approval since 12m ago`
- `You sent 1h ago`
- `2 replies - newest 4m ago`
- `5 work events hidden`
- `3 new - newest 2m ago`
- `Running for 8m`
- `Last activity Yesterday 4:12 PM`

Weak card examples:

- `Active`
- `Updated`
- `Today`
- `May 31`
- blank timestamp
- a timestamp hidden behind hover only

### Card Layout Recommendation

Use a compact, repeatable structure:

```text
Thread title                                      4m ago
Codex replied - 3 new                            Running
repo / branch / host
```

Or when attention is required:

```text
Thread title                                  Needs input
Approval requested 12m ago - 1 new
repo / branch / host
```

The top-right time should be the last meaningful activity age, not just created
time. The subtitle should name the thing that happened.

If both a reply and background work happened recently, the card should prefer the
reply as the human-facing headline and show work as secondary:

```text
Thread title                                      4m ago
Codex replied - 5 work events hidden             Running
repo / branch / host
```

If there is no new reply but work changed, label it as work:

```text
Thread title                                      2m ago
Work updated - command completed
repo / branch / host
```

### Card Relative-Time Ladder

For Dock cards, space is tight, but the labels still need to be readable.

Recommended visible labels:

- `< 10s`: `now`
- `10s-59s`: `just now`
- `1m-59m`: `7m ago`
- `1h-23h`: `2h ago`
- yesterday: `Yesterday`
- 2-6 days: `Mon`, `Tue`, etc.
- same year older than 6 days: `May 31`
- older year: `May 31, 2025`

Accessibility label should expand compact forms:

- visible `7m ago`
- accessible `7 minutes ago, today at 2:14 PM CDT`

This follows the shared direction from Primer, Cloudscape, and Atlassian:
relative time is best for scanning, but exact time must be available.

### Card Sort UX

Default sort should be `Activity: newest first`.

The sort should be visible and user-changeable:

- `Newest activity`
- `Unread first`
- `Needs input first`
- `Oldest unread`
- `Pinned`

When pinned cards are above newer activity, pinned status must be visually
separate from recency:

```text
Pinned
Thread A                                      2d ago

Newest activity
Thread B                                      2m ago
```

Do not silently mix pinned, unread, running, and newest-first ordering in one
undifferentiated list. The user will assume vertical position means recency.

### Card Unread UX

Unread needs both a count and an age.

Recommended card states:

- `1 new - 4m ago`
- `3 new - newest 2m ago`
- `New since 1:42 PM`
- `Unread approval - 12m ago`

For high activity, show both:

- first unread time: where the user should resume
- newest unread time: how fresh the latest update is

Example:

```text
7 new since 1:42 PM - latest 2m ago
```

This prevents the user from seeing `2m ago` and missing that the unread block
started much earlier.

### Card Active/Streaming UX

Active threads need elapsed duration, not just a status label.

Recommended labels:

- `Running for 4m`
- `Streaming now`
- `Tool running for 38s`
- `Waiting for approval for 12m`
- `No output for 6m`

This follows Primer's distinction between normal relative timestamps and
elapsed/remaining time for running tasks.

### Card Exact-Time Access

Every card timestamp should expose exact time:

- tap or long press time label
- context menu item: `Show timestamps`
- details popover:
  - `Last activity: Today at 2:14:32 PM CDT`
  - `First unread: Today at 2:09:10 PM CDT`
  - `Created: May 31, 2026 at 1:58 PM CDT`

Do not rely only on hover. It fails touch and keyboard usage.

## Thread Detail UX

Thread detail is where the user rebuilds context. It should behave like a chat
plus an audit trail.

### Thread Header

The header should always answer:

- current state
- last activity
- unread count
- current view mode
- hidden work/activity count
- exact time access
- order mode

Recommended header:

```text
Thread title
Running - last reply 2m ago - 4 new - 6 work events hidden
Conversation - oldest -> newest - Local time: CDT
```

Header actions:

- `Jump to first unread`
- `Jump to latest`
- `View: Conversation / Work / Files / Activity / Debug`
- `Show exact timestamps`
- `Order: Oldest first / Newest first`

Even if the default order is fixed, the order label should exist while the
product is earning trust.

### Default Thread Order

For conversation reading, default to oldest-to-newest inside a thread.

Reason:

- user messages and assistant replies form cause/effect chains
- reading top-to-bottom matches the mental model of a conversation
- first unread can be inserted cleanly
- live messages naturally appear at the bottom

For a separate activity-log mode, newest-first can be useful. Maersk's timeline
guidance calls out reverse chronology as appropriate for activity logs where
the user is reviewing recent completed events quickly.

The key rule: do not silently switch ordering. Conversation mode and activity
log mode should be visibly different.

### Date Dividers

Thread detail should include date dividers by default.

Examples:

- `Today`
- `Yesterday`
- `Monday, May 25`
- `May 31, 2026`

Dividers should be sticky while scrolling when possible, so the user always
knows which day they are reading.

This matches common chat SDK patterns. Stream Chat injects a date separator
between messages and recommends disabling separators only when another clear
time grouping exists. MUI X Chat automatically renders date dividers when
messages span calendar dates.

### First-Unread Divider

Thread detail needs a persistent first-unread marker:

```text
New since you last looked - Today at 2:09 PM
```

Properties:

- appears above the first unread message/event
- stays visible until the unread block is fully read or intentionally cleared
- includes exact local time in its detail/accessibility label
- can be jumped to from header or card
- can be restored by `Mark unread from here`

Slack's screen reader behavior provides a strong model: one preference starts
users where they left off and places focus at the first unread message, then
lets users read chronologically.

### New Messages While Reading

When the user is at the bottom/live edge:

- append new events inline
- keep scroll pinned to latest
- announce updates politely

When the user has scrolled away:

- do not move the viewport
- show a floating pill:
  - `1 new message`
  - `3 new events`
  - `Codex replied 2m ago`
- clicking/tapping it jumps to the first new event after the current viewport,
  not necessarily the absolute bottom

This matches MUI X Chat's buffer-gated auto-scroll pattern.

### Message Grouping

Group adjacent messages/events when they share the same actor and are close in
time, but do not hide time entirely.

Recommended grouping:

- first item in a group shows actor and group time
- subsequent items can suppress repeated actor labels
- every item has exact time available on tap/long press/accessibility
- if the gap between two items exceeds a threshold, start a new visual group

Suggested thresholds:

- same actor within 2 minutes: group
- same actor after 2 minutes: new group with timestamp
- different actor: new group immediately
- tool or approval event: always visible as its own event if it affects user
  action

### Message-Level Timestamp Display

Best default:

- show exact clock time on each visible group, not necessarily every bubble
- show exact timestamp for each item on selection, details, or expanded mode
- provide a global `Show exact timestamps` toggle for audit mode

Examples:

```text
You                                             2:09 PM
Summarize the thread ordering issue.

Codex                                          2:10 PM
I found the issue...
```

For dense operational events:

```text
2:10:14 PM  Command started
2:10:19 PM  Output received
2:10:22 PM  Command completed
```

### Exact Timestamp Detail

Each event detail popover or inspector should include:

- relative time: `7 minutes ago`
- exact local time: `Today at 2:14:32 PM CDT`
- date: `May 31, 2026`
- timezone: `America/Chicago / CDT`
- source label:
  - `message sent`
  - `assistant response completed`
  - `approval requested`
  - `tool output received`
  - `Dock observed`

For best-in-class audit trust, the detail view should be able to show multiple
timestamps when they differ:

- event time: when Codex says the event happened
- arrival time: when Dock received it
- seen time: when the user first viewed it

Even if the main UI only shows one, the names must be clear in details.

### Timeline Status States

Use visible event states, not just colors:

- `sent`
- `received`
- `streaming`
- `completed`
- `waiting for approval`
- `failed`
- `interrupted`
- `edited`
- `replayed from history`
- `order uncertain`

For uncertain or recovered history, say so plainly:

```text
Earlier history restored from transcript. Exact item times unavailable.
```

This keeps trust. A blank or misleading timestamp is worse than an honest
uncertainty label.

## Best-In-Class Interaction Patterns

### Jump Controls

Thread detail should support:

- `Jump to first unread`
- `Jump to latest`
- `Jump to previous day`
- `Jump to next day`
- `Jump to previous unread`
- `Jump to next unread`
- `Mark unread from here`
- `Copy link to event`

Slack exposes keyboard movement between messages, jump-to-first-unread, and
day navigation. Dock should treat these as power-user requirements, not extras.

### Timeline Minimap

For long threads, add a slim timeline/minimap on the right edge or in a drawer:

- day blocks
- unread block
- active/running events
- errors/approvals
- current viewport position

This is useful when a thread is long enough that scrolling loses context.

### Sticky Day Header

When scrolling through thread detail, a sticky header should show:

```text
Today - 17 events - 4 unread
```

or:

```text
May 29, 2026 - 8 events
```

It answers "where am I?" without requiring the user to scroll to the nearest
divider.

### Time Display Toggle

Provide a local or global display option:

- `Compact time`
- `Readable time`
- `Exact timestamps`

Compact example:

- `7m`

Readable example:

- `7 minutes ago`

Exact example:

- `Today 2:14:32 PM CDT`

Default should be readable on thread detail and compact on Dock cards, with
accessible expanded labels everywhere.

### Search Results And Timeline Anchoring

Search results should show time and position:

```text
May 31, 2026 at 2:14 PM - 3 messages after your prompt
```

Clicking a result should open the thread with nearby context and a highlight,
not isolate the message in a way that hides before/after order.

Search must also respect message density. Default search should search the
Conversation layer. If matches exist outside that layer, show a scoped result
summary rather than silently omitting them:

```text
2 conversation matches
7 hidden activity matches
```

Tapping `hidden activity matches` should switch to `Activity` with the same query
preserved.

### Copy/Paste And Share

When copying a range of messages/events, include timestamp and actor metadata
by default:

```text
[2026-05-31 14:09:12 CDT] You: Summarize the thread ordering issue.
[2026-05-31 14:10:03 CDT] Codex: I found the issue...
```

This matters because externalizing a conversation without timestamps destroys
the user's ability to preserve order.

## Formatting Rules

### Dock Card Relative Time

Use compact relative labels, expanded by accessibility:

| Age | Visible | Accessible label |
| --- | --- | --- |
| 0-9 seconds | `now` | `just now, today at 2:14 PM CDT` |
| 10-59 seconds | `just now` | `45 seconds ago, today at 2:14 PM CDT` |
| 1-59 minutes | `7m ago` | `7 minutes ago, today at 2:14 PM CDT` |
| 1-23 hours | `2h ago` | `2 hours ago, today at 12:14 PM CDT` |
| Yesterday | `Yesterday` | `Yesterday at 4:12 PM CDT` |
| 2-6 days | `Mon` | `Monday at 4:12 PM CDT` |
| Same year older | `May 31` | `May 31 at 4:12 PM CDT` |
| Older year | `May 31, 2025` | `May 31, 2025 at 4:12 PM CDT` |

### Thread Detail Time

Use readable labels:

| Context | Visible |
| --- | --- |
| group timestamp today | `2:14 PM` |
| group timestamp yesterday | `Yesterday 2:14 PM` |
| date divider today | `Today` |
| date divider yesterday | `Yesterday` |
| date divider older same year | `Monday, May 31` |
| date divider older year | `May 31, 2025` |
| exact inspector | `May 31, 2026 at 2:14:32 PM CDT` |

### Do Not Use These As Primary UI

- raw Unix seconds
- UUIDs
- internal sequence IDs
- unexplained ISO strings
- bare `updated`
- bare `active`
- hover-only exact times
- unlabelled timestamp columns
- inconsistent date formats in the same view

ISO timestamps are useful for exports, logs, and developer details, not primary
consumer-facing chronology.

## Accessibility Requirements

The accessible experience should be at least as clear as the visual experience.

Required:

- timestamps are reachable by keyboard and screen reader
- relative labels have exact-time alternatives
- date dividers use semantic separator behavior where available
- thread message list uses a live region carefully, such as polite updates
- auto-scroll does not steal focus while reading older messages
- new-message affordance is focusable
- first-unread divider is focusable or announced
- screen reader order matches visual order
- compact labels expand in accessibility text
- user can navigate by message, unread block, and day

Do not rely on:

- color alone
- hover alone
- position alone
- hidden titles alone
- animation alone

Primer's accessibility guidance is especially relevant here: exact timestamp
access must work for all users, not only mouse users.

## Product North Star

The best Dock experience feels like this:

1. I open Dock and immediately see which thread changed most recently.
2. I can tell whether the newest thing is a reply, a request, work, or system
   activity.
3. Every card says how old its latest meaningful activity is.
4. Unread cards show how many new things exist and when they started.
5. Opening a thread defaults to the readable conversation: what I said and what
   Codex said back.
6. Hidden work is counted and available without taking over the main transcript.
7. Opening an unread thread takes me to the first thing I have not seen.
8. A divider tells me exactly where new content begins.
9. The timeline has date separators, stable order, and message group times.
10. If new content arrives while I am reading older content, the viewport stays
   still and a "new messages" control appears.
11. I can jump to latest, first unread, previous day, next day, or exact event.
12. I can switch to Work, Files, Activity, or Debug when I need more than the
    conversation.
13. I can inspect exact timestamps whenever I care.
14. If exact order/time is unavailable, the UI tells me honestly instead of
    pretending.

## Concrete UX Spec

### Dock Card

Every card:

- must show last activity relative age
- must include a label for what happened
- must show unread count when greater than zero
- must show waiting/running elapsed duration when applicable
- must expose exact local timestamp
- must not rely on vertical position alone to communicate recency

Recommended fields:

- `title`
- `activitySummary`
- `activityKind`
- `relativeActivityAge`
- `exactActivityTime`
- `unreadCount`
- `unreadReplyCount`
- `unreadWorkCount`
- `firstUnreadTime`
- `latestUnreadTime`
- `hiddenWorkCount`
- `state`
- `stateElapsed`

Recommended visible pattern:

```text
Title                                            4m ago
Codex replied - 3 new                           Running
repo / branch / host
```

### Thread Header

Every thread header:

- must show last activity age
- must show unread count
- must show current view mode
- must show hidden work/activity count when the current view hides events
- must show whether the view is at latest
- must show current order mode
- must expose exact timestamp details

Recommended visible pattern:

```text
Thread title
Running - last reply 2m ago - 4 new - 6 work events hidden
Conversation - oldest -> newest - Local time: CDT
```

### View Mode Control

Every thread detail should expose the density ladder:

- `Conversation`: user messages, agent messages, active requests, hidden-work
  summaries
- `Work`: Conversation plus readable agent work summaries/details
- `Files`: changed files and diffs grouped by turn/path
- `Activity`: all supported event types in a readable timeline
- `Debug`: raw IDs, type tags, sequence fields, JSON excerpts, timestamp
  provenance

The default is `Conversation`. The control should be visible near the header,
use peer-mode tabs or a segmented control, and preserve scroll position where
possible when switching modes.

Do not put critical content only in a hidden tab. If a command is blocked,
approval is pending, or a file edit failed, Conversation should show the status
and let the user open the relevant mode/inspector for detail.

### Thread Timeline

Every timeline:

- must have stable visual order
- must include date dividers
- must include a first-unread divider when unread exists
- must expose group timestamps
- must show whether hidden work exists in the current view
- must expose per-event exact timestamps on demand
- must keep new arrivals from stealing scroll when the user is reading older
  content
- must show a jump affordance when new content arrives offscreen
- must show history gaps or uncertainty explicitly

Recommended event pattern:

```text
Today

You                                             2:09 PM
Summarize the ordering issue.

Work hidden: plan, 2 commands, web search

New since you last looked - 2:10 PM

Codex                                          2:10 PM
I found the issue...
```

### Event Inspector

Every event inspector:

- must show exact local timestamp
- should show relative time
- should show actor/source
- should show event type
- should show current view classification: conversation, request, work,
  activity, system, or debug
- should show sequence/context position in human terms
- should show copy link/copy event

Recommended inspector:

```text
Assistant message
7 minutes ago
May 31, 2026 at 2:14:32 PM CDT
After your 2:09 PM prompt
Source: Codex
```

## Research Findings Mapped To Dock

### Relative Time Is Best For Scanning

Primer, Cloudscape, Atlassian, and Maersk all support relative time for recent
activity. The reason is simple: a user triaging a list wants age, not a calendar
math problem.

Dock application:

- Dock cards should default to relative activity age.
- Thread activity summaries should use relative age for recent items.
- Running/waiting states should show elapsed time.

### Exact Time Must Always Be Available

Primer and Atlassian both state that relative time needs a route to exact time.
Cloudscape's accessibility guidance also points to exposing absolute
human-readable timestamps.

Dock application:

- exact timestamp in event inspector
- exact timestamp in card details
- exact timestamp available by keyboard and screen reader
- exact timestamp included in copied/exported messages

### Date Dividers Are A Standard Chat Pattern

Stream Chat treats date separators as part of message list behavior and says to
disable them only if another clear time grouping already exists. MUI X Chat
shows date dividers as a built-in part of message lists.

Dock application:

- date dividers should be on by default in thread detail
- dividers should be sticky for long threads
- dividers should be semantic separators for accessibility

### First-Unread Is The Right Landing Point

Slack's screen-reader defaults show the right principle: when catching up,
users often need to start where they left off and read chronologically.

Dock application:

- opening unread thread should land at first unread
- header keeps `Jump to first unread`
- unread divider persists until explicitly cleared or the unread block is read

### Unread Triage Needs Sorting And Filtering

Slack's unread view supports sorting by newest activity or oldest activity and
filtering unread conversations.

Dock application:

- Dock should have visible sort mode
- unread-first and needs-input-first should be explicit modes
- default should be newest meaningful activity

### Auto-Scroll Must Respect Reading

MUI X Chat gates auto-scroll by whether the user is near the bottom. This is the
right behavior for Codex Dock because assistant output can stream while the user
is reading older context.

Dock application:

- if user is at latest, follow new messages
- if user scrolled away, freeze viewport and show `N new`
- if user sends a message, returning to live edge is acceptable

### Timeline Content Must Be Repeatable

Maersk's timeline guidance emphasizes repeatable content patterns, attribution,
timestamps, and progressive disclosure for complex details.

Dock application:

- every event row should follow a predictable structure
- actor/source should be clear
- exact details should be expandable
- long tool output should be collapsed but not remove time/order anchors

### Conversation-First Is A Proven Pattern

NN/g's progressive disclosure guidance fits Codex Dock directly: show the small
set of things most users need first, and reveal specialized detail on request.
For Dock, the frequent task is reading the user/primary-agent exchange; the
specialized task is auditing how the agent worked.

Intercom Inbox is the closest product pattern found in research. Its default
conversation view focuses on messages, while conversation and ticket events can
be toggled on to inspect assignments, tags, AI-agent actions, workflow changes,
SLA changes, side conversations, and other background activity. That is the same
shape Dock needs: the message stream is primary, the full lifecycle event stream
is available, and technical events use consistent icons/text when shown.

GitHub issue timelines are a useful audit analogy. Timeline data can include
comments plus labels, locks, renames, assignments, and other events. The key
lesson is not that every event should be a comment; it is that mixed event types
need explicit type, actor, and timestamp treatment.

Dock application:

- default to Conversation, not raw Activity
- use Work/Files/Activity/Debug for increasing detail
- use Files when diffs are a first-class inspection task
- keep the path to hidden detail obvious
- label hidden counts so Conversation never feels lossy
- style event types differently instead of pretending every item is a message
- expose approvals, failures, and blocked states even when work detail is hidden

### Filters, Drawers, And Logs Have Different Jobs

Filtering is for narrowing a large set. A drawer/inspector is for inspecting one
selected thing without losing context. A log viewer is for raw trace/debug data.

Dock application:

- use filters in Activity/Debug for event types and severity/status
- use a drawer/inspector for command output, file diffs, tool payloads, web
  details, approval records, and trace spans
- use a log viewer pattern only in Debug
- keep the conversation visible when possible while inspecting details
- provide copy/export in Debug and Activity

### AI Transparency Should Be Useful, Not Noisy

AI-agent transparency is not the same as showing every raw internal event.

Dock application:

- label AI work summaries plainly: `Used web`, `Edited files`, `Asked sub-agent`
- expose sources/results when they affect trust
- show approvals and user-control states prominently
- warn before exposing raw payloads that may include sensitive prompt or tool
  data
- keep raw trace data out of the default thread

### Status Chips Should Carry Meaning

Compact badges work when they communicate state, not decoration.

Recommended chips:

- `Running`
- `Needs approval`
- `Failed`
- `Interrupted`
- `Edited files`
- `Used web`
- `Sub-agent`
- `Reasoning summary`
- `Debug`

Each chip should either explain a visible state or open related detail.

### Visibility Beats Memory

Nielsen Norman Group's heuristics reinforce the core issue: the system should
show state and reduce memory load. A time/order UI that asks users to remember
what they last saw has already failed.

Dock application:

- show "new since"
- show current sort order
- show live-edge state
- show timestamp labels
- show order uncertainty instead of hiding it
- show hidden event counts when the current view is filtered

## Anti-Patterns To Avoid

Do not:

- show only raw `createdAt`/`updatedAt` without saying what event it describes
- show relative time with no exact-time access
- use hover-only exact timestamps
- hide unread boundaries after opening the thread
- auto-scroll while the user is reading older messages
- show unread count without a first-unread place
- mix newest-first and oldest-first sections without labels
- put pinned cards above newer cards without a pinned section label
- use abbreviated timestamps where there is space for readable labels
- let cards sit blank because a timestamp is missing
- silently reorder messages after history loads
- collapse tool events so much that the user cannot tell when they happened
- let hidden work activity masquerade as unread conversation
- label a dense raw event stream as `Messages`
- force a user into Debug to see web search, sub-agent, image, or compaction
  activity
- show unsupported/unknown event rows in default Conversation when the item type
  is known to Codex
- copy message text without actor/time metadata

## Open Product Questions

These are UX decisions, not current technical blockers:

- Should thread detail default to oldest-to-newest for every thread, or offer a
  separate activity-log mode for newest-first review?
- Should the default filter be renamed from `Messages` to `Conversation` in the
  app UI?
- Should `Work` be a separate density mode, or should it be an expansion state
  inside Conversation?
- Should unread state clear when a message becomes visible, when the user
  reaches the bottom, or only when the user explicitly marks read?
- Should work/activity unread count separately from conversation unread?
- Should exact timestamps be always visible in an audit mode?
- Should Dock cards show first unread time, latest unread time, or both when
  unread count is high?
- Should cards prioritize `needs input` over newer passive activity by default?
- Should running threads show elapsed time from turn start, last output, or
  both?

Recommended answers:

- Conversation mode should be oldest-to-newest.
- Activity log mode can be newest-first, but must be explicitly labeled.
- Rename the default filter to `Conversation`; it is the user's actual mental
  model.
- Add `Work` as either a mode or a per-turn expansion, but do not require full
  Activity just to inspect what Codex did.
- Unread should clear conservatively, not just because a thread opened.
- Conversation unread and work unread should be tracked separately in the UX,
  even if the first implementation computes them from the same event stream.
- Cards should show latest unread by default and reveal first unread in the
  subtitle or details when count is more than one.
- Needs-input should be a visible lane or sort mode, not a silent override.
- Running threads should show both elapsed run time and last output age when
  output has gone quiet.

## Relationship To The TurnData Reference

The companion data reference documents what Codex and Dock currently expose:

- no Codex-origin per-message monotonic number
- thread-level timestamps
- turn-level timestamps
- live item lifecycle timestamps
- `ThreadItem.type` values for user messages, agent messages, thinking, tooling,
  artifacts, sub-agent work, and system markers
- Dock-derived event sequence fields
- relay-derived card fields

This UX document intentionally does not accept those limitations as the product
target. Instead, it defines the experience the product should provide.

The bridge between the two documents is:

- The data reference answers "what fields exist and where do they come from?"
- This UX reference answers "what must the user be able to understand?"

If the data is incomplete, the UX answer is not to hide time/order. The UX
answer is to label what is known, show the best available order, preserve the
user's reading position, and explicitly disclose uncertainty.

For message types, the bridge is equally strict:

- The data reference says Codex exposes many `ThreadItem.type` values.
- This UX reference says only `userMessage` and `agentMessage` are the default
  transcript.
- Server request cards are not transcript, but they must pierce the default view
  because they require action.
- Everything else should be progressively disclosed as Work, Files, Activity, or
  Debug.

## Source Notes

Useful source takeaways:

- NN/g progressive disclosure: show the most important features first; reveal
  specialized or rarely used detail only when the user asks; label the path to
  more detail clearly.
- GOV.UK accordion: hidden detail is risky for content everyone needs; do not
  hide approvals, failures, or blockers just because they are technically work
  activity.
- GOV.UK tabs: use tabs for peer sections that regular users switch between;
  avoid tabs when users need to read all content in order or compare details
  across sections.
- Apple disclosure controls: put common controls/content at the top of the
  hierarchy and hide advanced detail behind clearly related disclosure controls.
- Primer RelativeTime: relative time is concise and accessible; use readable
  long formats where possible; exact timestamps are required when precision
  matters; elapsed time is useful for running work.
- Primer RelativeTime accessibility: native `title` tooltip is not enough for
  keyboard or screen-reader users; exact time needs an accessible path.
- Cloudscape timestamps: choose relative, absolute human-readable, or ISO based
  on user need; label what event the timestamp describes; relative time is
  recommended for most user-facing recency cases; provide absolute access.
- Atlassian date/time: speak naturally when exactness is less important; always
  provide a route to the actual timestamp; avoid hardcoded locale formatting.
- Slack unread: unread triage needs sorting/filtering, mark-read controls,
  undo, refresh for new messages, and direct jump from unread item to
  conversation.
- Slack screen reader: first unread is a first-class navigation target, and
  reading chronologically from that point is an explicit supported mode.
- Stream Chat: date separators are a normal message-list component and should
  be removed only when another clear grouping exists.
- MUI X Chat: message lists combine date dividers, message groups, streaming
  indicators, auto-scroll, scroll-to-bottom affordances, and accessibility
  semantics.
- Intercom Inbox conversation events: the default conversation focuses on
  messages, while background conversation/ticket events can be toggled on; event
  rows use icons, consistent structure, and readable truncation.
- GitHub timeline events: a lifecycle timeline can contain comments plus many
  non-comment event types; mixed timelines need explicit event labels, actor, and
  timestamps.
- Fluent drawer: larger secondary detail belongs in a supplemental surface
  related to the main content, so thread context can stay visible.
- Fluent Responsible AI and Carbon for AI: AI assistance should be transparent
  enough to verify, but transparency should be structured and understandable.
- Carbon filtering: high-volume data needs event-type/status filtering; use
  batch apply behavior when live filtering would be slow or unstable.
- PatternFly log viewer: raw logs need their own search/filter/copy/wrap/debug
  affordances, not chat bubbles.
- Atlassian lozenge: compact status indicators are useful when they carry clear
  state.
- OpenAI Agents SDK human-in-the-loop: sensitive tool calls can pause execution
  for approval and resume after a decision, so approvals must be prominent.
- OpenAI Agents SDK tracing: generation, tool call, handoff, guardrail, custom,
  and other spans are observability data; Dock should summarize them before raw
  Debug.
- OpenAI reasoning guidance: reasoning summaries are distinct response items and
  should not be rendered as normal final answers.
- Material Design lists: list rows are for scanning homogeneous items; timestamp
  is support metadata, not the main content.
- Maersk timeline: activity logs are best when repeatable, timestamped,
  attributable, and scannable; reverse chronology fits activity review; exact
  timestamps matter for long processes.
- Nielsen Norman Group heuristics: visibility of system status and recognition
  over recall are the core usability principles behind this whole feature.

## Final Recommendation

Build the UX as an "activity inbox plus chronological conversation reader."

Dock cards should answer "what changed and how long ago?" Thread detail should
answer "what did I say, what did Codex say back, where did I leave off, and what
happened next?" Every relative time needs an exact timestamp path. Every unread
count needs a physical place in the timeline. Every hidden work event needs a
visible count and a path to inspect it. Every live update needs to respect the
user's current reading position.

Net: the product should make conversation, time, and order impossible to miss,
not merely possible to reconstruct.
