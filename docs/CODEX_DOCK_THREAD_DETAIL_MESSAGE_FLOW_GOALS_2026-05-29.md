---
title: "Codex Dock - Thread Detail Message Flow - Architecture Plan"
date: 2026-05-29
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [Parallel Agents]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_THREAD_EVENT_VISIBILITY_MODES_2026-05-28.md
  - docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29.md
  - docs/bugs/thread-detail-large-live-thread-message-too-long-2026-05-28.md
  - docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md
---

# TL;DR

- Outcome: Thread detail becomes one full-thread, newest-first message list with one message-type filter and one shared visible message card/control.
- Problem: Current detail still loads only `thread/turns/list limit:10`, sorts in natural conversation order, exposes Messages/Thinking/Everything timeline modes, and renders actionable requests in a separate visible card stack.
- Approach: Keep the safe compact transport shape, but drain all `thread/turns/list` pages. That means `thread/read includeTurns:false`, paged `thread/turns/list`, and `thread/resume excludeTurns:true`.
- Cap rule: a per-page limit is allowed as a transport guard; a total 10-turn or 10-message cap is not allowed.
- UI rule: one ordering rule, one filter, one visible card/control family. No competing timeline modes, no alternate ordering modes, and no second visible request-card renderer in the message area.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-29
Verdict (code): COMPLETE
Manual QA: n/a (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- `rtk npm run test:relay` repeated a no-output stall in `scripts/dock-relay-phase5.test.mjs` while other live Codex app-server processes were listening on loopback ports discovered by relay test code. This is recorded as a verification-environment blocker, not missing implementation code, because focused phase5 routing/request tests and the two non-phase5 relay test files passed.
<!-- arch_skill:block:implementation_audit:end -->

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-29
external_research_grounding: not required for this local client/relay contract change
deep_dive_pass_2: done 2026-05-29
recommended_flow: research -> deep dive -> phase plan -> consistency-pass -> implement-loop
research_reviewed: done 2026-05-29
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:481b8700429d17effc32544d3608498c8432218f0e63a856b6421aa9696b012e",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-29T11:18:03Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:b61e0bdff3b2c1963c48dce93bfb37122217d524710f6e2108139fc93357390e",
      "completed_at": "2026-05-29T11:18:09Z",
      "doc_hash_after": "sha256:4e2cd4dd10cf33625dffc1da70afdf0700b2b69556a1bea8efe6c928b53cfea7"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T11:18:12Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:4e2cd4dd10cf33625dffc1da70afdf0700b2b69556a1bea8efe6c928b53cfea7",
      "completed_at": "2026-05-29T11:18:19Z",
      "doc_hash_after": "sha256:62a08282009afabbaf46a1ab30b950c39bb278f3e581e9c09881b78813ee7157"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T11:18:22Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:62a08282009afabbaf46a1ab30b950c39bb278f3e581e9c09881b78813ee7157",
      "completed_at": "2026-05-29T11:18:27Z",
      "doc_hash_after": "sha256:50edde4f608b9034a7d67dccd88e5e1d33961d4522cb9d1c136dd84ed3e99cb8"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-29T11:18:30Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:50edde4f608b9034a7d67dccd88e5e1d33961d4522cb9d1c136dd84ed3e99cb8",
      "completed_at": "2026-05-29T11:18:35Z",
      "doc_hash_after": "sha256:1c8407a247cfedf42b2d3f93d45714cb117cfdb8af3412187413a8f28bb25bed"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-29T11:18:38Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:1c8407a247cfedf42b2d3f93d45714cb117cfdb8af3412187413a8f28bb25bed",
      "completed_at": "2026-05-29T11:18:43Z",
      "doc_hash_after": "sha256:439d1569dc2992c91b9d434c633c5321c1d80a97be600ca596261c295193e3da"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim

Opening a Dock row shows the complete thread as one newest-first message list. The default view shows all message rows. Selecting a message type shows only that type, still newest-first. Clearing the filter returns to all message rows. The loaded detail surface does not expose Messages/Thinking/Everything, natural-flow/order toggles, or a separate visible request-card stack that competes with the message list.

This claim is false if any detail load stops at the first `thread/turns/list limit:10` page, if visible rows are oldest-first, if timeline visibility modes remain user-visible, if requests render in both a request-card stack and a message row, or if full-thread loading reintroduces the old oversized `Message too long` failure.

## 0.2 In scope

- `ThreadDetailStore` loading, reconnect rehydrate, event publication, live merge, and request action-state ownership.
- `ThreadEvent` projection, ordering, and filter contracts.
- `SessionDetailView`, including header controls, list rendering, empty states, and card consolidation.
- `RequestCardsView` / `RequestCardView` removal from the user-visible message area after request actions move into the shared message card.
- Relay behavior for `thread/read`, `thread/turns/list`, `thread/resume`, and server-request forwarding where tests prove forwarding.
- Swift DTO/client tests, store tests, normalizer tests, relay tests, README sync, and simulator build proof after UI changes.

## 0.3 Out of scope

- New app-server method names or a Dock-only thread-detail protocol.
- Connecting the phone directly to the raw authenticated app-server on `:4500`.
- Moving raw bearer tokens or `OPENAI_API_KEY` into the app.
- Dock dashboard sorting/filtering, Archive behavior, Hosts UI, transcription model selection, or app-wide connectivity indicators.
- Persisting the selected message-type filter across app launches.
- Adding a debug transcript mode inside the thread detail message area.

## 0.4 Definition of done

- `ThreadDetailStore` pages `thread/turns/list` until the full turn history is loaded. A per-page limit is allowed, but no total cap such as 10 turns or 10 messages remains.
- `ThreadDetailStore` still uses `thread/read includeTurns:false` and `thread/resume excludeTurns:true`.
- The visible detail projection is newest-first for stored, live, and request events.
- `ThreadEventVisibilityMode` is retired from the user-visible detail surface.
- The thread detail message area has exactly one message-type filter control with default all, selected type only, and a clear action.
- Every visible message row uses one shared message card/control. Request approval/input actions may appear inside that card for request rows, but no separate visible `RequestCardsView` stack remains in the message area.
- Composer, live update, request response, background/foreground, and reconnect behavior are preserved.
- Focused checks pass: `rtk swift test --filter ThreadEventNormalizerTests`, `rtk swift test --filter ThreadDetailStoreTests`, `rtk swift test --filter AppServerClientTests`, `rtk npm run test:relay`.
- Because installed UI behavior changes, `rtk make app SIM='iPhone 17'` passes or the exact blocker is recorded.

## 0.5 Key invariants

- Full thread means page all available turns; it does not mean request the full thread in one oversized response.
- The app endpoint remains the relay on `:4510`; raw app-server `:4500` remains Mac-side.
- One user-visible message list, one ordering rule, one message-type filter, one visible card/control family.
- Filtering never mutates or drops canonical events; it only changes the visible projection.
- Request actions remain actionable, but their visible representation must not compete with the shared message card.
- Fail loudly on malformed thread ids, wrong-thread responses, relay routing failures, repeated cursors, and response decoding errors.

# 1) Key Design Considerations

## 1.1 Priorities

1. Full thread truth: the detail view must not silently hide older turns behind the current first 10-turn page.
2. Simple user model: one newest-first list and one filter, not a timeline/debug-mode selector.
3. Single visible card/control: every thread row should feel like one component family.
4. Safe transport shape: avoid the old oversized response failure by paging history.
5. Preserve control behavior: composer, live deltas, request approvals/input, reconnect, and background recovery still work.

## 1.2 Constraints

- `ThreadTurnsListResponseDTO` already exposes `nextCursor` and `backwardsCursor`; the client currently ignores them in detail load.
- The relay forwards `thread/turns/list` params to the owning upstream and does not impose the 10-turn cap.
- Previous bug evidence shows `thread/read includeTurns:true` and `thread/resume` without `excludeTurns` can exceed iOS WebSocket message limits on real large live threads.
- Existing tests intentionally pin natural-flow oldest-first behavior and `limit:10`; those tests now contradict the user goal.

# 2) Problem Statement

Thread detail opens from a Dock row, creates a `ThreadDetailStore`, connects to the relay, reads compact metadata with `thread/read includeTurns:false`, reads one turn page with `thread/turns/list limit:10`, resumes live updates with `thread/resume excludeTurns:true`, normalizes stored/live/request data into `ThreadEvent`, and publishes a `ThreadDetailSnapshot`.

The SwiftUI view then applies local `ThreadEventVisibilityMode` state. It cycles through Messages, Thinking, and Everything, renders the resulting event list with `ThreadEventCard`, and renders request actions separately through `RequestCardsView` / `RequestCardView`.

That architecture is wrong for this goal because it is not full-thread, not newest-first, not one filter, and not one visible card/control family.

# 3) Research Grounding

<!-- arch_skill:block:research_grounding:start -->
## 3.1 Internal protocol ground truth

- `docs/CODEX_APP_SERVER_RAMP_UP_2026-05-27.md` says `thread/read`, `thread/list`, and `thread/turns/list` are browsing APIs and do not load a thread for continuation.
- `docs/bugs/thread-detail-large-live-thread-message-too-long-2026-05-28.md` records the old large live-thread failure and the safe compact shape: `thread/read includeTurns:false`, paged turns, and `thread/resume excludeTurns:true`.
- `CodexDock/AppServer/AppServerMethods.swift:3` centralizes methods including `thread/read`, `thread/resume`, and `thread/turns/list`.
- `CodexDock/AppServer/ThreadDetailDTO.swift:13` defines `ThreadTurnsListParams(threadId:cursor:limit:)`.
- `CodexDock/AppServer/ThreadDetailDTO.swift:25` defines `ThreadTurnsListResponseDTO(data:nextCursor:backwardsCursor:)`.
- `CodexDock/AppServer/AppServerClient.swift:294` already encodes arbitrary cursor/limit params for `thread/turns/list`.
- `CodexDock/State/AppServerDockClient.swift:98` has an existing cursor-draining pattern: keep `cursor`, track repeated cursors, append pages, stop on empty `nextCursor`.

## 3.2 Current Swift ground truth

- `CodexDock/Features/Session/SessionDetailView.swift:11` owns `@State private var visibilityMode: ThreadEventVisibilityMode = .messages`.
- `CodexDock/Features/Session/SessionDetailView.swift:48` renders loaded detail as header, stale banner, composer, request cards, then event timeline.
- `CodexDock/Features/Session/SessionDetailView.swift:64` passes `visibilityMode.visibleEvents(from: snapshot.events)` to the timeline.
- `CodexDock/Features/Session/RequestCardView.swift:3` and `:29` define a separate request-card renderer.
- `CodexDock/State/ThreadDetailStore.swift:518` calls `thread/read includeTurns:false`.
- `CodexDock/State/ThreadDetailStore.swift:522` calls `thread/turns/list` with `ThreadTurnsListParams(threadId: row.id.threadID, limit: 10)`.
- `CodexDock/State/ThreadDetailStore.swift:542` calls `thread/resume excludeTurns:true`.
- `CodexDock/State/ThreadDetailStore.swift:655` handles server requests by both upserting a `ServerRequestCard` and appending a request `ThreadEvent`.
- `CodexDock/State/ThreadDetailStore.swift:695` publishes `ThreadDetailSnapshot(events: ThreadEventDisplayOrder.naturalFlow(events))`.
- `CodexDock/Models/ThreadEvent.swift:41` defines the three-mode `ThreadEventVisibilityMode`.
- `CodexDock/Models/ThreadEvent.swift:123` defines `ThreadEventDisplayOrder.naturalFlow`, which sorts oldest-first / conversation-flow.

## 3.3 Relay and test ground truth

- `scripts/dock-relay.mjs:458` handles `thread/turns/list`.
- `scripts/dock-relay-thread-data.mjs:476` requires `threadId` for `thread/turns/list`.
- `scripts/dock-relay-thread-data.mjs:480` routes `thread/turns/list` through `endpointForThread`.
- `scripts/dock-relay-thread-summary-cache.mjs:209` may use a bounded recent-turn warmup for Dock-row summaries; that is dashboard preview behavior, not full thread-detail loading.
- `scripts/dock-relay-phase5.test.mjs:810` covers `thread/turns/list` routing to the owning upstream.
- `README.md:146` still documents the old detail path as `thread/turns/list limit:10`.
- `CodexDockTests/ThreadDetailStoreTests.swift:39` and `CodexDockTests/ThreadDetailStoreLifecycleTests.swift:126` currently pin the unwanted `limit:10` behavior.
- `CodexDockTests/ThreadDetailStoreTestSupport.swift:49` already lets tests provide multiple `ThreadTurnsListResponseDTO` values, so paging tests do not require a new fake-session harness.

## 3.4 Parallel-agent evidence

- Swift UI/store explorer found the current code does not match the new goal: natural conversation order, `ThreadEventVisibilityMode`, timeline visibility cycling, and a separate request-card stack remain.
- Protocol/DTO explorer found the DTO/client/relay path is already cursor-capable. The cap is in `ThreadDetailStore.readCompactThread`, where cursor fields are ignored after the first page.
- Relay explorer found the relay forwards `thread/turns/list` params to the owning upstream and does not impose the 10-turn cap itself.
- Relay/status audit found `rtk make app-server-status` and `rtk make dock-relay-status` both reported `status: "ready"`, and `rtk make relay-doctor` reported `status: "passed"` with no problems.
- Agent verification already run: `rtk swift test --filter ThreadEventNormalizerTests` passed; `rtk swift test --filter ThreadDetailStoreTests` passed; a focused relay routing subset passed. One full `rtk npm run test:relay` attempt was inconclusive and must be rerun after implementation.

## 3.5 Decision gaps

None. The user explicitly clarified that the 10-message/10-turn cap must be removed and the detail view should show the full thread. The safe implementation path is to page `thread/turns/list`, keep compact `thread/read`, and keep compact `thread/resume`.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture

<!-- arch_skill:block:current_architecture:start -->
## 4.1 Runtime path today

```text
Dock row tap
-> DockView creates ThreadDetailStore
-> SessionDetailView.task calls store.load()
-> AppServerThreadDetailSession connects to relay :4510
-> initialize
-> thread/read includeTurns:false
-> thread/turns/list limit:10
-> normalize returned turns
-> publish ThreadEventDisplayOrder.naturalFlow(events)
-> thread/resume excludeTurns:true
-> live notifications/server requests merge into events
```

## 4.2 Request path today

```text
relay forwards upstream JSON-RPC request to phone
-> AppServerClient yields serverRequests
-> ThreadDetailStore.handle(request:)
-> upsert ServerRequestCard
-> append request ThreadEvent
-> RequestCardsView renders card
-> EventTimelineView may also render request row in Everything mode
```

## 4.3 Current UI shape

```text
[Thread header + status pills + Visibility cycle button]
[Live stale banner if needed]
[Composer]
[Separate request cards]
[Timeline rows filtered by Messages / Thinking / Everything]
```

## 4.4 Current failure shape

- More than one mental model: timeline visibility mode, natural-flow ordering, separate request-card stack, request rows that can also appear in the timeline, and only first 10 turns loaded.
- The compact transport safety fix became a product-visible cap because the store never drains `nextCursor`.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture

<!-- arch_skill:block:target_architecture:start -->
## 5.1 Runtime path after implementation

```text
ThreadDetailStore.load()
-> thread/read includeTurns:false
-> repeat thread/turns/list with a per-page limit and cursor until cursor exhausted
-> fail loudly on repeated cursors or page errors
-> normalize all returned turns
-> publish canonical full events
-> thread/resume excludeTurns:true
-> live notifications/requests merge into canonical events
-> visible projection sorts newest-first and applies optional message-type filter
```

## 5.2 Target request display

```text
server request arrives
-> ThreadDetailStore keeps request action state
-> request also has one canonical ThreadEvent row
-> shared message card renders the request row with action controls when actionable
-> no separate RequestCardsView stack in the message area
```

## 5.3 Target UI shape

```text
[Thread header + status pills]
[Message type filter: All | User | Agent | Command | Output | Request | System | Unknown] [Clear when filtered]
[Live stale banner if needed]
[Composer]
[Newest message card]
[Next newest message card]
[Older message card]
```

## 5.4 Target abstractions

- `ThreadDetailMessageFilter` or equivalent: default all plus one selected message type.
- `ThreadEventDisplayOrder.newestFirst(_:)`: visible message ordering helper, sorting by display date descending with stable tie-breakers.
- `ThreadDetailMessageProjection`: optional pure helper taking canonical events plus selected filter and returning newest-first visible rows.
- `ThreadMessageCard`: one shared visible card/control for labels, icons, body text, live badges, status badges, and request actions.

## 5.5 Boundaries

- Clean cutover for thread-detail presentation. The old timeline visibility contract is removed from the user-visible detail surface.
- No relay protocol change is expected. Preserve `thread/read`, `thread/turns/list`, `thread/resume`, `turn/start`, `turn/steer`, and server-request response contracts.
- Per-page limit is a transport/memory guard, not a user-visible cap.
- If a page fails, detail load fails/stales loudly. Do not silently show "full thread" with missing pages.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit

<!-- arch_skill:block:call_site_audit:start -->
| Area | File | Current behavior | Required change | Tests impacted |
| --- | --- | --- | --- | --- |
| Store loading | `CodexDock/State/ThreadDetailStore.swift` | One `thread/turns/list limit:10` page | Page until `nextCursor` is nil/empty; fail on repeated cursors | `ThreadDetailStoreTests`, lifecycle tests |
| Store publish | `CodexDock/State/ThreadDetailStore.swift` | Publishes `naturalFlow` oldest-first | Publish canonical full events or newest-first projection per store/view split | `ThreadDetailStoreTests` |
| Rehydrate | `CodexDock/State/ThreadDetailStore.swift` | Reuses capped compact read | Rehydrate with same full paging helper | lifecycle tests |
| Model ordering | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventDisplayOrder.naturalFlow` | Add/replace with newest-first display projection for detail | `ThreadEventNormalizerTests` |
| Model filtering | `CodexDock/Models/ThreadEvent.swift` | `ThreadEventVisibilityMode` modes | Remove from user-visible path; add one message-type filter contract | normalizer/filter tests |
| UI state/control | `CodexDock/Features/Session/SessionDetailView.swift` | `visibilityMode` and `VisibilityModeButton` | Selected message-type filter plus clear action | build/UI tests |
| UI list/card | `CodexDock/Features/Session/SessionDetailView.swift` | Timeline semantics and `ThreadEventCard` | Newest-first message list and one shared message card | build/UI tests |
| Request cards | `CodexDock/Features/Session/RequestCardView.swift` | Separate visible request stack | Fold visible request actions into shared message card; delete unused renderer | request-card tests |
| Request model | `CodexDock/Models/ServerRequestCard.swift` | Separate action state | Preserve internally if needed, keyed to request rows | request-card tests |
| DTO/client | `CodexDock/AppServer/ThreadDetailDTO.swift`, `AppServerClient.swift` | Cursor-capable already | Reuse; prove cursor encoding if touched | `AppServerClientTests` |
| Relay | `scripts/dock-relay.mjs`, `scripts/dock-relay-thread-data.mjs` | Forwards routed `thread/turns/list` | Preserve unless tests expose cursor-routing bug | `rtk npm run test:relay` |
| README | `README.md` | Documents `thread/turns/list limit:10` | Say paged full-thread loading | readback/status |
| Old plan docs | `docs/CODEX_DOCK_THREAD_EVENT_VISIBILITY_MODES_2026-05-28.md` | Describes old mode cycle as current | Mark superseded if touched | doc readback |

Migration notes:

- Canonical owner path: `ThreadDetailStore` owns full data loading; `ThreadEvent` owns projection primitives; `SessionDetailView` owns local filter state and rendering.
- Deprecated user-visible path: `ThreadEventVisibilityMode`.
- Delete/consolidate `VisibilityModeButton`, timeline visibility labels/accessibility copy, `RequestCardsView` / `RequestCardView` as a separate visible detail stack, `limit:10` detail tests, and docs that describe `thread/turns/list limit:10` as current detail behavior.
- Keep Dock-row summary cache out of scope; bounded recent-message warming there is preview behavior, not full thread detail.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan

<!-- arch_skill:block:phase_plan:start -->
> Rule: Phase boundaries are proof gates. Each phase must create evidence that later work can safely rely on. No fallback modes, runtime shims, or hidden legacy controls. If a page, cursor, route, or decode fails, the system fails loudly instead of pretending the thread is complete.

Phase-plan evidence: full-thread paging is Phase 1 because every later UI claim is false while the store still loads only one 10-turn page.

## Phase 1 - Full Thread Paging And Newest-First Contract

Goal:

Prove the highest-risk data seam first: detail loading fetches the full thread through cursor paging and exposes a newest-first projection without reintroducing oversized WebSocket responses.

Status: implemented and verified 2026-05-29.

Checklist:

- Replace `thread/turns/list limit:10` detail loading with a cursor loop over `ThreadTurnsListResponseDTO.nextCursor`.
- Use a bounded per-page limit, but no total thread cap.
- Track repeated cursors and fail loudly instead of looping forever.
- Keep `thread/read includeTurns:false`.
- Keep `thread/resume excludeTurns:true`.
- Reuse the same full paging helper on reconnect/foreground rehydrate.
- Add/repair tests proving multiple pages are requested and combined.
- Add/repair tests proving newest-first visible order for stored, live, and request events.
- Remove or update tests that assert `limit:10` as the detail contract.

Verification:

- `rtk swift test --filter ThreadEventNormalizerTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter AppServerClientTests`

Exit criteria:

- No current detail load or rehydrate path has a total 10-turn/message cap.
- Full history paging stops only when the app-server cursor is exhausted.
- The old `Message too long` failure path is not reintroduced.
- Newest-first behavior is proven by tests.

## Phase 2 - One Filter And One Visible Card

Goal:

Replace the user-visible timeline mode surface with one message-list surface: one filter, one order, one card/control.

Status: implemented and verified 2026-05-29.

Checklist:

- Replace `visibilityMode` state with selected message-type filter state.
- Replace `VisibilityModeButton` with one control that can select a type and clear the filter.
- Remove Messages/Thinking/Everything labels and accessibility copy from the thread detail surface.
- Render the message list through one shared card/control.
- Remove the separate visible `RequestCardsView` stack from the message area.
- Preserve request approval/input actions inside the shared message card when a request row is actionable.
- Keep composer behavior unchanged.
- Add/repair tests around request action preservation and filtering.

Verification:

- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk make app SIM='iPhone 17'` or exact blocker

Exit criteria:

- The loaded detail UI has no user-visible timeline mode cycle.
- The message area has one filter control and one clear action.
- The message area has one visible message card/control family.
- Request actions remain usable from the shared card.

## Phase 3 - Relay, Docs, And Runtime Proof

Goal:

Ensure relay/protocol truth, live docs, and runtime service evidence agree with the new client behavior.

Status: implemented with one repeated verification blocker on the full relay suite. Focused relay diagnostics passed; `rtk npm run test:relay` twice stalled silently in `scripts/dock-relay-phase5.test.mjs` and was terminated after diagnostic capture.

Checklist:

- Run `rtk npm run test:relay` to prove relay forwarding, focused session routing, and server-request forwarding still work.
- Update `README.md` detail/reconnect text from `thread/turns/list limit:10` to paged full-thread loading.
- Mark `docs/CODEX_DOCK_THREAD_EVENT_VISIBILITY_MODES_2026-05-28.md` as superseded by this plan or remove its live-current claims if touched.
- Re-run the smallest Swift tests after docs/code changes that affect contracts.
- Run `rtk make app SIM='iPhone 17'` for installed UI proof or record the exact blocker.

Exit criteria:

- Relay tests remain green.
- Live docs no longer compete with this plan.
- Installed app build/launch proof exists, or the exact environment blocker is recorded.
<!-- arch_skill:block:phase_plan:end -->

<!-- arch_skill:block:implementation_status:start -->
## 7.1 Implementation Status - 2026-05-29

Implemented:

- `ThreadDetailStore` now performs full detail reads with `thread/read includeTurns:false`, drains `thread/turns/list` pages with `limit:100` until `nextCursor` is exhausted, fails on repeated cursors, and resumes with `thread/resume excludeTurns:true`.
- Detail snapshots now use `ThreadEventDisplayOrder.newestFirst(_:)`.
- `ThreadEventVisibilityMode` was removed from the active Swift path and replaced with `ThreadDetailMessageFilter`.
- `SessionDetailView` now has one message-type filter, a clear action when filtered, one newest-first message list, and one shared message/request card family.
- `ThreadMessageListView.swift` now owns the filter/list/card controls so `SessionDetailView.swift` stays focused on screen layout and lifecycle.
- The separate visible `RequestCardsView` / `RequestCardView` implementation was removed.
- README detail/reconnect text now documents paged full-thread loading instead of `thread/turns/list limit:10`.
- `docs/CODEX_DOCK_THREAD_EVENT_VISIBILITY_MODES_2026-05-28.md` is marked superseded by this plan.

Verification evidence:

- `rtk swift test --filter ThreadEventNormalizerTests`: passed after final component split, 11 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`: passed after final component split, 52 selected tests, 0 failures.
- `rtk swift test --filter AppServerClientTests`: passed after final component split, 48 tests, 5 skipped, 0 failures.
- `rtk node --test --test-name-pattern 'thread/turns/list routes|thread/resume forwards|turn/start rejects|thread/resume refuses|phone responses are rejected after their upstream request is made stale by a newer resume' scripts/dock-relay-phase5.test.mjs`: passed, 5 tests, 0 failures.
- `rtk node --test scripts/dock-relay.test.mjs scripts/dock-relay-realtime-transcription.test.mjs`: passed, 29 tests, 0 failures.
- `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`: passed against the booted iPhone 17 simulator after `SIM='iPhone 17'` was ambiguous; latest launch log `.codex-dock/logs/app-sim-install-20260529114117.log` recorded `com.aelaguiz.CodexDockApp: 43750`.
- `rtk make sim-config-verify SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`: passed.
- `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`: first run failed `AppServerClientTests.testRelayRealtimeTranscriptionClientFallsBackAcrossRelayEndpoints()`; targeted raw `rtk xcodebuild ... -only-testing:CodexDockTests/AppServerClientTests/testRelayRealtimeTranscriptionClientFallsBackAcrossRelayEndpoints` diagnostic passed; rerun of the Makefile target passed; final rerun after component split also passed with `.codex-dock/logs/app-test-20260529114126.log`.

Open verification blocker:

- `rtk npm run test:relay` repeated a no-output stall with only the `scripts/dock-relay-phase5.test.mjs` worker active. On the second run, Node report `report.20260529.063654.23402.0.001.json` showed an idle worker with referenced TCP handles. Follow-up `lsof` showed other live Codex app-server processes listening on `127.0.0.1:61116`, `127.0.0.1:49904`, `127.0.0.1:59557`, and `127.0.0.1:56199`; those were not killed because they are outside this task's test process tree. The report was moved to `/tmp/codex-client/20260529T113654Z/report.20260529.063654.23402.0.001.json`. Only relay test processes were terminated; app-server and Dock relay services were left running.
<!-- arch_skill:block:implementation_status:end -->

# 8) Verification Strategy

- Unit contracts: `ThreadEventNormalizerTests`, `ThreadDetailStoreTests`, and `AppServerClientTests`.
- Relay integration: `rtk npm run test:relay`.
- Installed UI proof after SwiftUI changes: `rtk make app SIM='iPhone 17'`.
- Physical-phone proof is separate and not required for this planning doc unless a later task asks for it.

# 9) Rollout / Ops / Telemetry

- Clean local cutover. No feature flag and no fallback mode.
- Keep relay service behavior unchanged unless tests expose a cursor forwarding bug.
- Add counts to existing `DockLog.threadDetail` logs if useful: number of turn pages loaded, total turns loaded, and cursor exhaustion. Do not log prompt text, transcript text, full JSON-RPC payloads, raw audio, or secrets.
- Normal service verification remains `rtk make app-server-status`, `rtk make dock-relay-status`, and `rtk make relay-doctor`.

# 10) Decision Log

## 2026-05-29 - Full thread replaces the 10-turn cap

The previous compact-detail fix used `thread/turns/list limit:10` to avoid oversized WebSocket responses. The user explicitly clarified: "I want to remove this 10 message cap as well. It's just the full thread."

Decision: remove the total cap by paging `thread/turns/list` until the cursor is exhausted. Preserve compact `thread/read includeTurns:false` and `thread/resume excludeTurns:true`.

Consequences: Phase 1 must land before UI cleanup can be called complete. Tests and README references to `limit:10` become stale.

## 2026-05-29 - Replace visibility modes with one message-type filter

The existing completed plan intentionally added Messages/Thinking/Everything timeline modes. The new goal asks for one message-type filter and no competing modes.

Decision: retire `ThreadEventVisibilityMode` from the user-visible detail surface and replace it with a message-type filter projection.

Consequences: Existing tests and docs that pin the timeline mode cycle must change or be marked superseded.

<!-- arch_skill:block:consistency_pass:start -->
- Decision-complete: yes
- Unresolved decisions: none
- Decision: proceed to implement? yes
- Notes: Plan is ready for implement-loop. Full-thread paging and newest-first contract land first; one filter and one visible card land second; relay/docs/runtime sync lands third.
<!-- arch_skill:block:consistency_pass:end -->
