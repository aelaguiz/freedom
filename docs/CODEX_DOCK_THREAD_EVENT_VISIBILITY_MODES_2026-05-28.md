---
title: "Codex Dock - Thread Event Visibility Modes - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [Plan Audit]
doc_type: architectural_change
related: []
---

# TL;DR

- Outcome: Opening a thread shows only the human-visible conversation by default, with a compact in-thread control that cycles through Messages, Messages + Thinking, and Everything without losing request cards, composer behavior, or live updates.
- Problem: `SessionDetailView` currently renders every normalized `ThreadEvent`, and `ThreadEventNormalizer` maps reasoning, plan, command, output, tool, request, system, and unknown items into the same visible stream, making real messages hard to scan and leaving ordering concerns under-specified.
- Approach: Add a first-class `ThreadEventVisibilityMode` and event classification contract owned by the thread-event model layer; have the store continue publishing the complete event list in deterministic order, and have the detail UI derive and order the visible timeline from the selected mode.
- Plan: First prove message-only filtering and ordering in the model path, then integrate the compact SwiftUI cycle control in the header without changing store ownership, then finish with focused tests and an installed-app visual pass.
- Non-negotiables: Default mode is Messages, request cards stay separate and actionable, ordering is deterministic across stored and live events, no raw app-server secrets move to the app, and no parallel timeline renderer is introduced.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-28
Verdict (code): COMPLETE
Manual QA: complete (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- Installed UI check completed on simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Evidence screenshots:
  - `/tmp/codex-client/20260528T191500Z/thread-detail-messages.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-everything.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-thinking.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-messages.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-everything.png`
  - `/tmp/codex-client/20260528T191500Z/thread-detail-final-thinking.png`
<!-- arch_skill:block:implementation_audit:end -->

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:72f59388b5937fb7068010a20e342be88dd1a302134d62b10919c33874db799d",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T12:36:00Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:572269ea824a8a0efb121b118260ba0d1d394ad0db61582e88e7f3b251ba6eda",
      "completed_at": "2026-05-28T12:36:21Z",
      "doc_hash_after": "sha256:ed6bb8579887e5b2e18f0404c48ed63d81143c445b47409f51e9c4af652dd73a"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T12:36:26Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:ed6bb8579887e5b2e18f0404c48ed63d81143c445b47409f51e9c4af652dd73a",
      "completed_at": "2026-05-28T12:37:30Z",
      "doc_hash_after": "sha256:55ec11e6c695a1c25d901493ab9b2cb55912d46a7360f4043b41007076624d6c"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T12:37:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:55ec11e6c695a1c25d901493ab9b2cb55912d46a7360f4043b41007076624d6c",
      "completed_at": "2026-05-28T12:38:07Z",
      "doc_hash_after": "sha256:d9132cb064ed0618b5a91d6c7fc39b00b8d5a8595edd4b027cebbd836c9a51c0"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T12:38:13Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:d9132cb064ed0618b5a91d6c7fc39b00b8d5a8595edd4b027cebbd836c9a51c0",
      "completed_at": "2026-05-28T12:39:15Z",
      "doc_hash_after": "sha256:a57bac15635b09ce74306174cf8eb57a97f9e3569825ef2e3254268d90e00a16"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T12:39:32Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:a57bac15635b09ce74306174cf8eb57a97f9e3569825ef2e3254268d90e00a16",
      "completed_at": "2026-05-28T12:43:59Z",
      "doc_hash_after": "sha256:9aacbdb202ad972e38422c2da022843aea2bbf767d81dfb7297b6bf03341a1ad"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this change, a thread opened from the Dock defaults to a quiet Messages timeline containing only user and agent message rows, while a compact control near the header lets the user cycle to Messages + Thinking and Everything. The same thread data remains available in the app, but non-message events are hidden until the selected visibility mode includes them, and stored/live ordering remains deterministic.

## 0.2 In scope

- Thread detail timeline filtering for stored turns, live notifications, and server request events.
- A compact, elegant visibility control in `SessionDetailView`, placed with the header/status area so it is visible before the timeline.
- A model-layer classification contract that defines which event kinds are messages, thinking, tool/command/output, request, system, or unknown.
- Deterministic ordering hardening for stored and live events, including same-turn item order and natural conversation flow.
- Focused Swift tests for visibility filtering, ordering, and request-card preservation.
- Final simulator/device-oriented verification using the existing Codex Dock relay path when implementation starts.

## 0.3 Out of scope

- Changing the app-server protocol or relay method names.
- Changing how the relay authenticates to raw app-server or how the phone discovers `ws://192.168.50.117:4510`.
- Adding search, per-thread persisted preferences, global settings, transcript export, or new timeline layouts beyond the requested compact visibility cycle.
- Moving request-card interaction into the timeline or hiding `RequestCardsView`.
- Rewriting Dock row sorting, archive behavior, host settings, transcription, or composer behavior.

## 0.4 Definition of done (acceptance evidence)

- `ThreadEventVisibilityMode` defaults to Messages and maps the three user-facing modes exactly: Messages, Messages + Thinking, Everything.
- Stored turns containing user messages, agent messages, reasoning, plan items, command execution, command output, tool calls, requests, system events, and unknown items filter into the expected visible sets for each mode.
- Live delta events merge and order correctly after filtering; hidden events do not corrupt visible message order.
- Request cards remain visible and actionable through `RequestCardsView` even when request timeline rows are hidden in Messages mode.
- The thread detail header includes a compact control near the status pills, with accessible labels and no text overlap on small iPhone widths.
- Smallest relevant checks pass: the focused normalizer/model tests added for the classification and ordering contract plus `rtk swift test --filter ThreadDetailStoreTests`. Because this plan changes installed UI behavior, run `rtk make app SIM='iPhone 17'` or report the exact blocker. Run `rtk xcodegen generate --spec project.yml` only if `project.yml` or project wiring changes.

## 0.5 Key invariants (fix immediately if violated)

- The canonical event stream remains one complete `[ThreadEvent]`; visibility is a projection, not a second source of truth.
- Message-only mode must not delete, stop receiving, or stop merging hidden events.
- Thinking mode includes reasoning and plan events, but not command/tool/output rows.
- Everything mode includes all currently normalized events.
- Request cards are independent of timeline visibility and must stay visible when pending/resolved.
- Ordering uses explicit turn/item/event sequence and timestamp data before unstable append order, and hidden-category event dates must not move visible Messages-mode rows.
- No fallbacks, runtime shims, secret movement, or phone direct connection to the raw authenticated `:4500` app-server.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Quiet default reading: thread detail should initially look like a conversation, not a debug transcript.
2. Complete recoverability: thinking, commands, output, requests, system, and unknown rows remain one tap away.
3. Deterministic order: filtering must not expose or hide ordering bugs.
4. Local fit: use existing SwiftUI header/card patterns and model/store tests rather than new infrastructure.
5. Low operational risk: avoid app-server, relay, secret, or service-path changes.

## 1.2 Constraints

- This is an iOS/macOS SwiftUI client with Swift package tests and an XcodeGen-generated app project.
- The normal phone path uses the Dock relay at `ws://192.168.50.117:4510`; the plan must not introduce direct raw `:4500` app-server use.
- `ThreadDetailStore` currently owns live observation, request-card updates, composer state, and ordered event publication.
- `SessionDetailView` currently owns the header and timeline rendering; design changes must fit the existing 8 px card radius, grouped background, and compact pill style.
- `project.yml` only changes if app target settings, assets, Info.plist, schemes, permissions, or project wiring change.

## 1.3 Architectural principles (rules we will enforce)

- Classification belongs with `ThreadEvent`/normalization, not ad hoc SwiftUI `if` chains.
- The store publishes canonical thread detail state; the view derives visibility without mutating the underlying event list.
- The compact control is a real UI control with an accessible state label, not hidden gesture magic.
- Tests assert behavior-level filtering and ordering, not screenshots or fragile visual constants.
- Existing request-card and composer flows remain unchanged unless a test proves a real coupling needs adjustment.

## 1.4 Known tradeoffs (explicit)

- The default hides useful debugging rows, but the control keeps them immediately reachable.
- Persisting the last-selected mode could be convenient, but it is out of scope because the request says default thread entry should show just messages.
- Filtering in the view keeps the store state simple, but the classification/filtering API must live in the model layer so tests and future callers do not duplicate rules.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Thread detail loads stored turns through `thread/read` plus `thread/turns/list`, resumes live updates through `thread/resume`, normalizes turns/notifications/requests into `ThreadEvent`, and renders every event as a card in `SessionDetailView`.

## 2.2 What is broken / missing (concrete)

- The timeline is spammy because reasoning, plan, command, output, tool-call, request, system, and unknown rows display by default beside actual user/agent messages.
- There is no user-facing way to switch between a clean conversation view and a debug/full transcript view.
- The event model has kinds, but it does not have a visibility/classification contract that matches the requested UX.
- Ordering is present but needs explicit plan coverage because hidden events and live deltas can make ordering bugs easier to miss.

## 2.3 Constraints implied by the problem

- The fix must preserve all normalized data so debug visibility is available.
- Filtering must be deterministic and testable without relying on preview rows.
- The UI should be compact enough to sit near the header/status area without crowding the existing title, host, live, and row-status pills.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- No external protocol or platform research is required for this plan. The change is a local SwiftUI/model projection over already-decoded app-server events, and the repo's existing UI patterns are the stronger source of truth.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors (do not reinvent):
  - `CodexDock/Models/ThreadEvent.swift` - defines `ThreadEventKind`, normalized `ThreadEvent` fields, stored-turn normalization, live-notification normalization, server-request normalization, and `ThreadEventDisplayOrder.naturalFlow`.
  - `CodexDock/State/ThreadDetailStore.swift` - owns thread detail load/resume, live observation, request-card upsert/resolve, event append/merge, and publication of `ThreadDetailSnapshot(events:)`.
  - `CodexDock/Features/Session/SessionDetailView.swift` - owns thread detail layout, `DetailHeaderView`, `EventTimelineView`, and `ThreadEventCard` rendering.
  - `CodexDock/Features/Session/RequestCardView.swift` - renders actionable server requests separately from the event timeline.
  - `CodexDockTests/ThreadEventNormalizerTests.swift` - existing contract tests for stored normalization, same-turn ordering, date/sequence metadata, live delta identity, server request events, and unknown item visibility.
  - `CodexDockTests/ThreadDetailStoreTests.swift` - existing store-level tests for read/resume, natural-flow display, live merge, server request event/card behavior, composer/voice behavior, and thread mismatch failure.
- Canonical path / owner to reuse:
  - `CodexDock/Models/ThreadEvent.swift` owns the new visibility classification/filtering contract because it already owns event kinds, event metadata, and display ordering.
  - `CodexDock/State/ThreadDetailStore.swift` should continue to own the canonical complete event list and should not be split into separate message/debug streams.
  - `CodexDock/Features/Session/SessionDetailView.swift` owns the compact cycle control and timeline projection because the selected mode is local presentation state.
- Adjacent surfaces tied to the same contract family:
  - `CodexDockTests/ThreadEventNormalizerTests.swift` must move with the classification/filtering contract so the model rules stay explicit.
  - `CodexDockTests/ThreadDetailStoreTests.swift` must keep proving canonical event order and request-card preservation.
  - `CodexDock/Features/Session/RequestCardView.swift` is adjacent but should remain independently visible; it should not become part of the filtered timeline.
  - `scripts/dock-relay.mjs`, `CodexDock/AppServer/ThreadDetailDTO.swift`, `CodexDock/AppServer/TurnDTO.swift`, and `CodexDock/AppServer/AppServerClient.swift` are protocol-adjacent but intentionally excluded unless implementation discovers a decoded field needed for stable ordering that already exists in server payloads but is not surfaced.
- Compatibility posture (separate from `fallback_policy`):
  - Preserve existing app-server and relay contracts. The change is a clean client-side projection over the same `ThreadEvent` data; no wire compatibility bridge is needed.
- Existing patterns to reuse:
  - `DockView` uses a compact segmented picker for tab filtering; the thread detail control should borrow the compact, scan-friendly spirit but use a single cycle button because the user requested a button-like compact control near the running/status badge.
  - `DetailPill` and `DockRowView` status capsules use SF Symbols, `caption`/`caption2` weight, and subtle opacity backgrounds; the visibility control should use the same restrained visual language.
  - `ComposerView` and `RequestCardView` use icon buttons and accessibility labels; the new control should follow that pattern.
- Prompt surfaces / agent contract to reuse:
  - Not applicable. This change displays agent output; it does not change prompts, model instructions, or agent behavior.
- Native model or agent capabilities to lean on:
  - Not applicable. Event visibility and ordering are deterministic client responsibilities.
- Existing grounding / tool / file exposure:
  - Existing fake sessions in `ThreadDetailStoreTests` can synthesize stored turns, live notifications, and server requests without reaching a real relay.
  - Existing JSON DTOs preserve raw item shapes as `JSONValue`, so tests can cover reasoning/plan/tool/command/unknown payloads directly.
- Duplicate or drifting paths relevant to this change:
  - No second timeline renderer exists today. The drift risk is adding filtering directly inside `SessionDetailView` without a reusable model contract, which would leave tests and future callers to duplicate visibility rules.
  - `ThreadEventKind.agentMessage` currently represents agent messages, plan items, reasoning, and live reasoning deltas. Visibility cannot rely on kind alone unless the plan refines classification with an explicit category or display role.
- Capability-first opportunities before new tooling:
  - Add a small model-layer enum and pure filtering function; no scripts, harnesses, or protocol adapters are needed.
- Behavior-preservation signals already available:
  - `rtk swift test --filter ThreadDetailStoreTests` protects thread detail load/resume, event merge, request-card behavior, composer, voice transcript, and mismatch failures.
  - `ThreadEventNormalizerTests` can be expanded to protect classification, filtering, and ordering without UI screenshots.

## 3.3 Decision gaps that must be resolved before implementation

- None. The user-supplied intent plus repo evidence resolves the mode set, default behavior, owner path, and protocol compatibility posture.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `CodexDock/Models/ThreadEvent.swift`
  - `ThreadEventKind` is the only current event-level type signal.
  - `ThreadEvent` carries body/title/date/live identity plus optional `turnID`, `itemID`, `turnSequence`, `itemSequence`, `eventSequence`, and `displayGroupDate`.
  - `ThreadEventDisplayOrder.naturalFlow(_:)` sorts by turn/item/event sequence and dates so the detail view reads like a normal conversation.
  - `ThreadEventNormalizer` translates stored turn items, live JSON-RPC notifications, and server JSON-RPC requests into `ThreadEvent`.
- `CodexDock/State/ThreadDetailStore.swift`
  - Loads thread metadata and turns through `thread/read` and `thread/turns/list`.
  - Resumes live updates through `thread/resume`.
  - Maintains one private `events` array and publishes `ThreadDetailSnapshot(events: ThreadEventDisplayOrder.naturalFlow(events))`.
  - Maintains `requestCards` separately from `events`.
- `CodexDock/Features/Session/SessionDetailView.swift`
  - Owns page composition: header, stale banner, composer, request cards, event timeline.
  - `EventTimelineView` renders every `snapshot.events` row.
  - `ThreadEventCard` chooses icon/color/font by `ThreadEventKind`.
- `CodexDock/Features/Session/RequestCardView.swift`
  - Renders pending server requests independently from timeline cards.
- `CodexDockTests/ThreadEventNormalizerTests.swift` and `CodexDockTests/ThreadDetailStoreTests.swift`
  - Own the most relevant behavior tests for this change.

## 4.2 Control paths (runtime)

1. User opens a Dock row.
2. `DockView` creates `ThreadDetailStore(host:row:)` and passes it to `SessionDetailView`.
3. `SessionDetailView.task` calls `store.load()`.
4. `ThreadDetailStore.load()` initializes the relay-backed `AppServerClient`, reads metadata, reads recent turns with `thread/turns/list(limit: 10)`, publishes stored events, then attempts `thread/resume(excludeTurns: true)`.
5. Notifications and server requests arrive on separate async streams.
6. Notifications become optional `ThreadEvent` values; server requests become both `ServerRequestCard` state and request `ThreadEvent` rows.
7. `publishLoaded()` sorts all events in natural conversation order and the view renders them all.

## 4.3 Object model + key abstractions

- `ThreadEventKind` currently mixes display and semantic concepts:
  - `.userMessage` and `.agentMessage` can be real conversation rows.
  - `.agentMessage` is also used for `"plan"`, `"reasoning"`, `"item/plan/delta"`, and `"item/reasoning/*"` rows.
  - `.command` is used for command executions and tool calls.
  - `.output`, `.request`, `.system`, and `.unknown` are debug or operational rows.
- `ThreadEvent` has enough identity/order metadata to support deterministic ordering, but no visibility category.
- `ThreadDetailSnapshot` exposes only the complete sorted event list.
- The selected timeline mode does not exist today.

## 4.4 Observability + failure behavior today

- Thread mismatch fails visibly in `ThreadDetailStoreError.threadMismatch`.
- Resume failure keeps stored events and marks the live state stale.
- Unsupported stored items remain visible as `.unknown`, which is good for debugging but contributes to message-view noise.
- Existing tests catch many store and normalization regressions but do not assert that actual conversation rows can be isolated from reasoning/tool/debug rows.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Today:

```text
Thread
[terminal] Build live detail
Amir-M5  Live  Running
thread-id · now

[composer]
[request cards]
[User / Agent / Plan / Reasoning / Command / Output / Tool / Request / System cards...]
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- `CodexDock/Models/ThreadEvent.swift`
  - Add `ThreadEventVisibilityCategory` with cases such as `.message`, `.thinking`, `.tooling`, `.request`, `.system`, and `.unknown`.
  - Add `ThreadEventVisibilityMode: CaseIterable` with exactly three cases:
    - `.messages`
    - `.messagesAndThinking`
    - `.everything`
  - Add the visibility category to `ThreadEvent`; if a defaulted initializer parameter is needed, default defensively to `.unknown` and have the normalizer explicitly classify every known event shape.
  - Add a pure projection API, for example `ThreadEventVisibilityMode.includes(_:)` and `ThreadEvent.filtered(_:for:)`.
  - Keep `ThreadEventDisplayOrder` as the single display-order function and harden it only where tests expose unstable ordering.
- `CodexDock/State/ThreadDetailStore.swift`
  - Continue publishing the complete event list in deterministic full-transcript order.
  - Do not add per-mode arrays, filtering state, or persistence to the store.
- `CodexDock/Features/Session/SessionDetailView.swift`
  - Add local `@State private var visibilityMode: ThreadEventVisibilityMode = .messages`.
  - Pass `snapshot.events` through the model-layer visibility projection before `EventTimelineView`.
  - Add a compact cycle control to the header/status area.
- `CodexDockTests/ThreadEventNormalizerTests.swift`
  - Add focused tests for category assignment, filtering, and ordering.
- `CodexDockTests/ThreadDetailStoreTests.swift`
  - Add or adjust tests only where store-level publication/order/request-card behavior needs proof.

## 5.2 Control paths (future)

1. Store load/resume flow remains unchanged and continues producing complete canonical events.
2. Normalization assigns each event a visibility category when the event is created:
   - stored/live user and agent messages -> `.message`
   - stored/live plan and reasoning -> `.thinking`
   - command execution, command output, tool call, dynamic tool call -> `.tooling`
   - server request timeline events and file-change items -> `.request`
   - thread status/closed -> `.system`
   - unsupported item/turn shapes -> `.unknown`
3. `publishLoaded()` continues publishing the complete event list in deterministic full-transcript order.
4. `SessionDetailView` keeps the complete snapshot but projects visible rows with the selected mode, then applies the model-layer display-order helper to the projected rows so hidden-category timestamps cannot move visible message rows:
   - Messages -> `.message`
   - Messages + Thinking -> `.message` and `.thinking`
   - Everything -> all categories
5. The header cycle button advances `messages -> messagesAndThinking -> everything -> messages`.
6. `RequestCardsView` remains outside the timeline filter and continues showing actionable requests regardless of selected mode.

Visibility category matrix:

| Source | Stored/live shape | Current kind | Future category | Visible in Messages | Visible in Messages + Thinking | Visible in Everything |
| ------ | ----------------- | ------------ | --------------- | ------------------- | ------------------------------- | --------------------- |
| Stored user input | `type: "userMessage"` | `.userMessage` | `.message` | yes | yes | yes |
| Stored agent text | `type: "agentMessage"` | `.agentMessage` | `.message` | yes | yes | yes |
| Live agent text | `item/agentMessage/delta` | `.agentMessage` | `.message` | yes | yes | yes |
| Stored plan | `type: "plan"` | `.agentMessage` | `.thinking` | no | yes | yes |
| Stored reasoning | `type: "reasoning"` | `.agentMessage` | `.thinking` | no | yes | yes |
| Live plan/reasoning | `item/plan/delta`, `item/reasoning/summaryTextDelta`, `item/reasoning/textDelta` | `.agentMessage` | `.thinking` | no | yes | yes |
| Live full item | `item/started`, `item/completed` with embedded item | depends on embedded item | same as stored item path | depends on embedded item | depends on embedded item | yes |
| Stored command | `type: "commandExecution"` command card | `.command` | `.tooling` | no | no | yes |
| Stored command output | `aggregatedOutput` row | `.output` | `.tooling` | no | no | yes |
| Live command output | `item/commandExecution/outputDelta` | `.output` | `.tooling` | no | no | yes |
| Stored tool call | `mcpToolCall`, `dynamicToolCall` | `.command` | `.tooling` | no | no | yes |
| Server request timeline row | JSON-RPC request from app-server | `.request` | `.request` | no | no | yes |
| Stored file-change item | `type: "fileChange"` | `.request` | `.request` | no | no | yes |
| Thread status/closed | `thread/status/changed`, `thread/closed` | `.system` | `.system` | no | no | yes |
| Unsupported turn/item | unknown or malformed shapes | `.unknown` | `.unknown` | no | no | yes |

## 5.3 Object model + abstractions (future)

- `ThreadEventKind` remains the coarse display label/icon family for cards.
- `ThreadEventVisibilityCategory` becomes the semantic filtering category.
- `ThreadEventVisibilityMode` becomes the only public presentation-mode contract.
- The view should not infer thinking/tooling from `title`, `body`, or raw JSON.
- The store should not know which rows are hidden by the current UI selection.

## 5.4 Invariants and boundaries

- Single source of truth: one complete event array, one display-order helper, one filtering contract.
- Compatibility posture: preserve existing app-server/relay DTOs and method names; client-only projection.
- No fallback policy exception: if classification is missing for a new normalized event, it should intentionally land in `.unknown` and only appear in Everything mode unless a test-driven product decision says otherwise.
- Ordering boundary: sorting stays in `ThreadEventDisplayOrder`, and tests must pin the behavior for mixed stored/live message/thinking/tool rows before or alongside UI work.
- Ordering precedence must be explicit and stable:
  1. group events by `turnID` when present, then `itemID`, then event id;
  2. order groups in natural conversation flow by `turnSequence`, then `displayGroupDate`/`date`, then stable key;
  3. order rows inside a group oldest-to-newest by `itemSequence`, then `eventSequence`, then original append offset;
  4. each visible mode must sort the projected row set through the same display-order helper, so a hidden request/reasoning/tool row with a newer timestamp cannot move an older visible message group ahead of newer visible messages.
- UI boundary: `SessionDetailView` owns the selected mode; no new global settings or persistence.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Target compact header:

```text
Thread
[terminal] Build live detail
Amir-M5  Live  Running                    [Messages]
thread-id · now

[composer]
[request cards, if any]
[User / Agent message cards only by default]
```

Cycle states:

```text
[Messages] -> [Thinking] -> [Everything] -> [Messages]
```

Displayed button text can be compact while accessibility stays explicit:

- Visible labels: `Messages`, `Thinking`, `Everything`.
- Accessibility labels: `Timeline visibility: Messages`, `Timeline visibility: Messages and Thinking`, `Timeline visibility: Everything`.
- The `Thinking` visible label is acceptable shorthand only if the accessibility value and code mode remain `messagesAndThinking`; do not create a fourth mode or make Thinking mean reasoning-only.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Model | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventKind` / `ThreadEvent` | Kind is the only classification; `.agentMessage` includes real messages and thinking. | Add `ThreadEventVisibilityCategory`, `ThreadEventVisibilityMode`, category field, and pure filtering helpers. | Needed to hide thinking/tool rows by default without losing data. | `ThreadEvent.visibilityCategory`; `ThreadEventVisibilityMode.includes(_:)`; optional `ThreadEvent.visibleEvents(_:mode:)`. | `ThreadEventNormalizerTests` |
| Model | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventNormalizer.events(fromItem:)` | Normalizes plan/reasoning as `.agentMessage`; command/tool rows as `.command`; output/request/system/unknown are all visible. | Assign explicit visibility categories at creation time for every stored item type. | Filtering cannot rely on kind/title without drift. | Category assignment matrix in tests. | `ThreadEventNormalizerTests` |
| Model | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventNormalizer.event(from notification:)` | Live agent/reasoning deltas become visible rows; live status rows visible. | Classify live deltas: agent message `.message`, plan/reasoning `.thinking`, output `.tooling`, status `.system`. | Live behavior must match stored behavior. | Same category contract for stored and live. | `ThreadEventNormalizerTests`, `ThreadDetailStoreTests` |
| Model | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventNormalizer.event(from notification:)` for `item/started` / `item/completed` | Embedded live full items route through `events(fromItem:)` and can produce any stored-item-like row. | Ensure the shared `events(fromItem:)` path classifies live full-item events exactly like stored items. | Prevents live started/completed items from bypassing the category matrix. | Full-item notifications reuse stored item classification. | `ThreadEventNormalizerTests` |
| Model | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventNormalizer.event(from request:)` | Server requests become `.request` events in the timeline. | Classify request timeline rows as `.request`; they appear only in Everything while `RequestCardsView` remains separate. | Messages mode should stay quiet but pending actions must remain visible. | Timeline request row hidden unless mode is Everything. | `ThreadDetailStoreTests` |
| Ordering | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventDisplayOrder.naturalFlow(_:)` | Sorts the detail timeline in natural conversation flow, then item/event sequence inside a turn. | Add tests and harden projection/order behavior so hidden-category event dates cannot move visible Messages-mode rows. | User observed newest user messages appearing pinned at the top; hidden rows must not cause visible conversation jumps. | Preserve one display-order API; apply it to projected visible rows for each mode. | `ThreadEventNormalizerTests`, `ThreadDetailStoreTests` |
| Store | `CodexDock/State/ThreadDetailStore.swift` | `publishLoaded()` | Publishes all sorted events. | Keep publishing the complete sorted event list; do not filter in store. Consider adding a store test that hidden request rows do not affect request cards. | Store remains canonical and UI mode-local. | No new store API unless tests show a need. | `ThreadDetailStoreTests` |
| UI | `CodexDock/Features/Session/SessionDetailView.swift` | `SessionDetailView` | No selected visibility state; timeline receives all events. | Add local visibility state and pass filtered events to `EventTimelineView`. | Default message-only view with one-tap expansion. | `@State var visibilityMode = .messages`; `snapshot.events.visible(in:)`. | Build/UI verification |
| UI | `CodexDock/Features/Session/SessionDetailView.swift` | `DetailHeaderView` | Shows host, live-state, and row-status pills only. | Add an optional compact cycle control near the pills/status area, likely trailing within the pill row. | Matches requested placement near running badge without another toolbar. | `VisibilityModeButton(mode:onCycle:)` or equivalent local view. | Build/UI verification |
| UI | `CodexDock/Features/Session/SessionDetailView.swift` | `EventTimelineView` / empty state | Empty state says no transcript only when full event list empty. | Empty state should reflect the selected mode when events exist but no rows match, e.g. no messages in this view. | Prevents confusing "no transcript" when Everything has rows. | `EventTimelineView(events:mode:hasUnfilteredEvents:)` or equivalent. | Build/UI verification |
| Tests | `CodexDockTests/ThreadEventNormalizerTests.swift` | Existing normalizer tests | Cover stored normalization and display order, not visibility modes. | Add matrix tests for mode filtering and category assignment. | Protects the main new contract. | Pure model tests. | `rtk swift test --filter ThreadEventNormalizerTests` if supported, otherwise package tests or target tests |
| Tests | `CodexDockTests/ThreadEventNormalizerTests.swift` | Ordering coverage | Existing tests prove natural conversation flow and same-turn event order for stored rows. | Add mixed hidden/visible tests proving per-mode projection and ordering preserve visible message order; add a live-delta test if current fallback can reorder same-turn live events. | Directly addresses the suspected out-of-order bug. | Ordering remains centralized in `ThreadEventDisplayOrder`. | `ThreadEventNormalizerTests` |
| Tests | `CodexDockTests/ThreadDetailStoreTests.swift` | Existing detail store tests | Cover load/order/live/request-card behavior. | Add focused checks for request card independence and ordering with hidden events if needed. | Prevents regressions in the user-facing flow. | Store keeps complete events; UI filters later. | `rtk swift test --filter ThreadDetailStoreTests` |
| Project config | `project.yml`, `CodexDock.xcodeproj/project.pbxproj` | XcodeGen project wiring | No new files unless implementation splits models/views into new files. | If new Swift files are added under existing target path, verify whether XcodeGen/source glob includes them; update `project.yml` only if needed. | Repo rule: `project.yml` is source of truth for project config. | No config change expected. | XcodeGen/build only if config changes |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  - `CodexDock/Models/ThreadEvent.swift` owns category and filtering.
  - `CodexDock/Features/Session/SessionDetailView.swift` owns local selected mode and the compact control.
- Deprecated APIs (if any):
  - None expected. Existing `ThreadEvent` initializer can gain a defaulted `visibilityCategory` parameter to avoid broad churn.
- Delete list (what must be removed; include superseded shims/parallel paths if any):
  - No live code deletions expected unless implementation creates then supersedes a local helper during refactor. Do not leave duplicate filtering helpers in the view and model.
- Adjacent surfaces tied to the same contract family:
  - Include normalizer tests and store tests now.
  - Exclude relay/app-server protocol code unless implementation uncovers an existing ordering field that the client should already decode.
  - Exclude persistent user settings and global preferences.
- Compatibility posture / cutover plan:
  - Preserve wire contracts; clean client-side cutover to mode-filtered timeline.
- Capability-replacing harnesses to delete or justify:
  - None. Do not add harnesses, scripts, screenshot gates, or grep checks.
- Live docs/comments/instructions to update or delete:
  - No README or AGENTS change expected. Add one concise code comment only if the visibility category assignment matrix is non-obvious at the model boundary.
- Behavior-preservation signals for refactors:
  - `rtk swift test --filter ThreadDetailStoreTests`.
  - Focused normalizer tests for categories/order. If XCTest filtering by class is unavailable, report exact command behavior and run the smallest supported Swift test command.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Event projection | `ThreadEvent.swift` | Model-owned enum + pure projection helper | Avoids view-only filtering rules drifting from tests and future callers. | include |
| UI control | `SessionDetailView.swift` / `DetailPill` pattern | Compact SF Symbol/text capsule or bordered button with accessibility label | Keeps the control aligned with existing header/status styling. | include |
| Request actions | `RequestCardView.swift` | Keep actions outside timeline filter | Prevents hidden request timeline rows from hiding required user actions. | include |
| Preferences | New settings storage | Persist selected mode | Nice-to-have but conflicts with default message-only thread entry. | exclude |
| Protocol | `scripts/dock-relay.mjs` and DTOs | Server-side event filtering | Adds unnecessary contract surface and risks phone/relay drift. | exclude |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable work. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

## Phase 1 — Model-owned visibility and ordering contract

* Goal:
  Establish the single source of truth for which events are messages, thinking, tooling, requests, system rows, or unknown rows, and prove that visibility projection never lets hidden rows change visible conversation ordering.
* Work:
  This phase works at the `ThreadEvent` model boundary first because that is the highest-risk seam: current `.agentMessage` rows include both real messages and reasoning/plan rows. Later UI work can rely on this contract without duplicating event-type rules.
* Checklist (must all be done):
  - Add `ThreadEventVisibilityCategory` in `CodexDock/Models/ThreadEvent.swift`.
  - Add `ThreadEventVisibilityMode` with exactly `.messages`, `.messagesAndThinking`, and `.everything`.
  - Add a `visibilityCategory` field or equivalent explicit category on `ThreadEvent`, with a defaulted initializer parameter only if needed to keep existing call sites simple.
  - Add pure filtering helpers owned by the model layer, not by `SessionDetailView`.
  - Assign the full Section 5.2 visibility matrix during stored-turn normalization.
  - Assign the full Section 5.2 visibility matrix during live notification normalization.
  - Add a focused test proving `item/started` and `item/completed` full-item notifications classify through the same path as stored items.
  - Assign server request timeline events to the `.request` category.
  - Keep unsupported turns/items visible only through the `.unknown` category and Everything mode.
  - Keep `ThreadEventDisplayOrder.naturalFlow(_:)` as the single ordering API.
  - Add focused normalizer/model tests proving all three visibility modes include and exclude the expected categories.
  - Add focused ordering tests proving projected visible messages retain the expected conversation order when hidden thinking/tooling rows are present.
  - Add a focused ordering test where an old turn receives a hidden request/reasoning/tool event with a newer timestamp and the Messages projection still keeps newer visible message turns ahead of that old turn.
* Verification (required proof):
  - Run the smallest supported Swift test command that covers the normalizer/model tests. Prefer `rtk swift test --filter ThreadEventNormalizerTests`; if that filter is unsupported, report the exact failure and run the smallest supported equivalent.
* Docs/comments (propagation; only if needed):
  - Add one concise model-boundary comment only if the visibility matrix would be hard to understand from enum names and tests alone.
* Exit criteria (all required):
  - `ThreadEventKind` no longer has to be interpreted to decide visibility by itself.
  - Messages mode includes only real user/agent message events.
  - Messages + Thinking includes messages plus plan/reasoning events and excludes tooling/request/system/unknown rows.
  - Everything includes every normalized event category.
  - The canonical ordering function remains the only ordering source.
  - Per-mode projection plus ordering is tested and does not let hidden-category timestamps reorder visible Messages-mode rows.
  - Live full-item `item/started` and `item/completed` notifications cannot bypass category assignment.
  - The required normalizer/model tests pass or an exact environment/tooling blocker is recorded.
* Rollback:
  Revert the enum/category/helper additions and test changes as one unit; no app-server, relay, or project configuration rollback is expected.

## Phase 2 — Thread detail integration and compact cycle control

* Goal:
  Make the thread detail screen default to Messages while preserving one-tap access to Thinking and Everything from a compact control near the status/header area.
* Work:
  This phase connects the proven model contract to the real SwiftUI surface: `SessionDetailView` gets local visibility state, derives visible timeline events from the canonical snapshot, and exposes the requested cycle control without changing store ownership.
* Checklist (must all be done):
  - Add local `visibilityMode` state in `SessionDetailView` with `.messages` as the initial value.
  - Derive visible timeline rows from `snapshot.events` using the model-layer helper.
  - Keep `ThreadDetailStore` publishing the complete event list; do not add per-mode arrays to the store.
  - Add a compact cycle control near the header pills/status area, visually aligned with existing `DetailPill`/status capsule styling.
  - Implement the exact cycle order: Messages -> Messages + Thinking -> Everything -> Messages.
  - Use compact visible labels that fit small widths; keep the accessibility label/value explicit for all three modes.
  - Keep `RequestCardsView(store:)` outside the timeline filter so pending/resolved requests remain visible and actionable in Messages mode.
  - Update `EventTimelineView` empty-state handling so "no rows in this mode" is distinct from "thread returned no readable events."
  - Avoid adding global settings, persisted preferences, new routes, new relay calls, or a second timeline renderer.
* Verification (required proof):
  - Run `rtk swift test --filter ThreadDetailStoreTests`.
  - Run the normalizer/model test command from Phase 1 if Phase 2 changes the projection API or event categories.
* Docs/comments (propagation; only if needed):
  - No README or AGENTS update is expected. If implementation adds a reusable SwiftUI subview in a new file, update `project.yml` first only if project wiring requires it, then regenerate with `rtk xcodegen generate --spec project.yml`.
* Exit criteria (all required):
  - A newly opened thread starts in Messages mode.
  - The cycle control can reach Messages + Thinking and Everything and cycles back to Messages.
  - The control is compact, uses existing design language, and does not overlap title/status/thread-id text.
  - The timeline uses filtered rows, while request cards remain independent and actionable.
  - Hidden request/tool/reasoning rows remain in the canonical event stream and reappear in the correct modes.
  - Required store/UI-adjacent tests pass or an exact environment/tooling blocker is recorded.
* Rollback:
  Remove the local mode state/control and pass `snapshot.events` directly to `EventTimelineView` again; retain Phase 1 only if the model contract is still useful and all tests remain green.

## Phase 3 — Final proof, installed UI check, and drift cleanup

* Goal:
  Prove the complete user-facing behavior and remove any drift introduced while implementing the model/UI changes.
* Work:
  This phase is the final proof gate. It makes sure the feature works as a user would experience it, while keeping verification proportional and avoiding screenshot/grep bureaucracy.
* Checklist (must all be done):
  - Run `rtk swift test --filter ThreadDetailStoreTests`.
  - Run the focused normalizer/model tests added in Phase 1.
  - Inspect the final diff for duplicated filtering logic, store-level per-mode arrays, protocol changes, and stale comments.
  - Confirm `scripts/dock-relay.mjs`, app-server DTO method names, raw bearer token handling, and phone relay path remain unchanged unless a prior phase explicitly required otherwise.
  - Because Phase 2 changes installed UI behavior, run `rtk make app SIM='iPhone 17'` or report the exact blocker.
  - Perform a manual installed UI check that the header control fits and Messages, Messages + Thinking, and Everything show the expected rows.
  - If project wiring changed, ensure `project.yml` was updated before generated project files and run `rtk xcodegen generate --spec project.yml`.
* Verification (required proof):
  - Test output from the smallest relevant Swift checks.
  - XcodeGen evidence only when project wiring changes; simulator evidence is required because this plan changes installed UI behavior.
  - Manual UI check that the header control fits and the three modes show expected rows.
* Docs/comments (propagation; only if needed):
  - Delete or rewrite any touched stale comment that claims every event is always shown by default.
  - Do not add dated docs or extra runbooks for this local UI change.
* Exit criteria (all required):
  - Default thread entry is quiet and message-only.
  - Messages + Thinking and Everything remain reachable from the compact control.
  - Suspected ordering risk is covered by deterministic tests and no known out-of-order visible sequence remains.
  - Manual installed UI check confirms no header/status/thread-id overlap and each mode displays the expected row set, or an exact simulator/device blocker is recorded.
  - Request cards, composer, live updates, and stale/error UI still behave as before.
  - No relay, app-server, secret, or service-path contract changed.
  - All required verification has either passed or is blocked by an exact reported environment issue.
* Rollback:
  Revert the feature files from Phases 1-2 together, regenerate project files only if project wiring changed, and re-run the smallest thread-detail tests to confirm the old all-events timeline behavior is restored.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Unit tests (contracts)

- Start model-contract proof with the smallest supported command for `ThreadEventNormalizerTests` because visibility classification and filtering belong to `ThreadEvent.swift`.
- Run `rtk swift test --filter ThreadDetailStoreTests` for store-level thread detail, live events, request-card response behavior, and timeline state.

## 8.2 Integration tests (flows)

- Use existing store-level fake sessions to prove stored and live events still merge and sort correctly.
- Keep request-card tests behavior-level: hidden request timeline rows must not hide or break actionable `RequestCardsView` state.

## 8.3 E2E / device tests (realistic)

- Regenerate with `rtk xcodegen generate --spec project.yml` only if project config changed, then run the relevant Xcode build/test or `rtk make app SIM='iPhone 17'` for installed-app behavior. If the simulator/app command cannot run, report the exact command and blocker.
- Real phone-path completion evidence must remain relay-backed through `ws://192.168.50.117:4510`, not loopback or mock-only paths.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

No staged rollout is needed. This is a local client UI/model change with no protocol migration.

## 9.2 Telemetry changes

No telemetry is required for the first implementation. The visible state is user-local UI state.

## 9.3 Operational runbook

Normal service checks stay unchanged: `rtk make app-server-status` and `rtk make dock-relay-status` when local services matter. Do not restart services unless implementation verification specifically calls for it.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, auto-plan receipts, target architecture, call-site audit, phase obligations, verification, rollout, and cited thread-detail code paths.
- Findings summary:
  - Explorer 1 found Section 0/7/8 verification wording drift around XcodeGen versus installed UI proof.
  - Explorer 1 found Phase 3 manual UI proof stranded in `Verification` without checklist/exit-criteria coverage.
  - Explorer 2 found a blocking ordering contradiction: hidden live/request/reasoning rows could move visible Messages-mode rows if ordering only used the complete unfiltered stream.
  - Explorer 2 found live full-item `item/started` and `item/completed` notification classification was under-specified.
- Integrated repairs:
  - Section 0.4 and Section 8 now require `rtk make app SIM='iPhone 17'` for this installed UI change and limit `rtk xcodegen generate --spec project.yml` to project wiring changes.
  - Phase 3 now requires the manual installed UI check in `Checklist` and names it in `Exit criteria`.
  - Sections 0, 5, 6, and 7 now state that hidden-category event dates must not move visible Messages-mode rows, and the phase plan requires a direct regression test.
  - Sections 5, 6, and 7 now explicitly cover `item/started` / `item/completed` live full-item classification through the shared item path.
  - The plan now describes one complete event list plus one display-order helper and one filtering contract, avoiding a second store-owned timeline source of truth.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - User intent approves active auto-plan

Context

The user requested a new full implementation plan and explicitly asked to use the ArcStep auto-plan flow until plan audit agrees, with no implementation yet.

Options

- Stop after a draft North Star and ask for confirmation.
- Treat the explicit request as approval to continue planning to decision-complete status.

Decision

Treat the provided objective as active planning approval and continue through research, deep-dive, phase-plan, consistency, and plan audit before implementation.

Consequences

The plan starts with `status: active`, remains docs-only, and must not proceed to code implementation in this run.

## 2026-05-28 - Intent-derived: hidden rows must not move Messages order

Blocker:

The cold read found two credible ordering interpretations: either hidden request/reasoning/tool rows can move the whole turn group in the complete transcript order, or Messages-mode visible ordering is anchored only to visible message rows.

Consulted:

TL;DR, Section 0.1, Section 0.4, Section 0.5, Section 5.4, and Section 7 Phase 1.

Intent says:

The user wants the default thread view to show actual back-and-forth messages and specifically suspected an ordering bug, so hidden debug/activity rows must not make the visible conversation appear out of order.

Decision:

Messages-mode ordering must not be affected by hidden-category event dates. The implementation should keep one complete event list, but each visible mode sorts the projected row set through the model-owned display-order helper.

Consequences:

Section 5.4 and Phase 1 now require a direct test where an old turn receives a newer hidden request/reasoning/tool event and the Messages projection still keeps newer visible message turns ahead of that old turn.
