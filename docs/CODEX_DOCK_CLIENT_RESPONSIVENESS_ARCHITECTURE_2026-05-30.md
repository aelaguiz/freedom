---
title: "Codex Dock - Client Responsiveness Hard Cut - Architecture Plan"
date: 2026-05-30
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: ["Composer 2.5 Fast"]
doc_type: architectural_change
related:
  - README.md
  - Makefile
  - Package.swift
  - project.yml
  - docs/CODEX_DOCK_GOALS_2026-05-29.md
  - docs/CODEX_DOCK_RELAY_STATE_ENGINE_ARCHITECTURE_2026-05-30.md
  - https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance
  - https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness
  - https://developer.apple.com/tutorials/instruments/getting-started-with-hang-analysis
  - https://developer.apple.com/videos/play/wwdc2023/10160/
  - https://developer.apple.com/videos/play/wwdc2023/10248/
  - CodexDock/Features/Dock/DockView.swift
  - CodexDock/State/DockStore.swift
  - CodexDock/State/DockSessionTable.swift
  - CodexDock/State/DockSessionProjection.swift
  - CodexDock/State/ThreadDetailStore.swift
  - CodexDock/Features/Session/SessionDetailView.swift
  - CodexDock/Features/Session/ThreadMessageListView.swift
  - CodexDock/State/AppConnectivityStore.swift
  - CodexDock/AppServer/AppServerClient.swift
  - CodexDock/State/AppServerDockStreamClient.swift
  - scripts/dock-relay.mjs
  - scripts/dock-relay-state-engine.mjs
  - scripts/dock-relay-state-subscriptions.mjs
---

# TL;DR

Outcome: hard-cut the Swift client so user interaction, scrolling, typing,
navigation, swipe actions, and sheet presentation never wait on data-layer work.
The main actor becomes a tiny render presenter, not the place where Dock rows,
thread events, connectivity state, JSON, persistence, sorting, filtering, or
grouping are computed.

Problem: the server side is moving in the right direction with a relay-owned
bounded Dock stream, but the client still collapses too much work back into
`@MainActor` stores and SwiftUI `body` getters. Stream updates, full snapshot
projection, list filtering, thread normalization, event sorting, request-card
lookup, and connectivity rollups can all run on the same executor that must
paint frames and accept touches.

Approach: introduce a hard boundary between data engines and render stores.
Actors own protocol IO, persistence, indexing, merging, normalization, sorting,
search, filtering, grouping, and diff construction. `@MainActor` view stores
hold already-prepared render snapshots and enqueue intents. SwiftUI views render
stable bounded arrays and never derive large projections in `body`.

Plan: first lock the target architecture with Composer 2.5 Fast, then use the
ArcStep auto-plan receipts to turn this document into an implementation-ready
hard-cut plan, then get Composer 2.5 Fast to review the finished plan. No
production code is implemented by this document.

Non-negotiables: no runtime fallback to the current laggy store model, no
parallel old/new UI state, no bulk work on `MainActor`, no `.project()` calls
from SwiftUI `body`, no unbounded event arrays as render input, no data-layer
operation that can block taps or typing, and no implementation until Amir asks
for implementation in a later turn.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-30 - traced Dock, Thread Detail, Archive, Connectivity, protocol, and relay boundaries
external_research_grounding: done 2026-05-30 - official Apple SwiftUI performance, UI responsiveness, hang analysis, and Instruments guidance grounded the target
deep_dive_pass_2: done 2026-05-30 - converted findings into hard target boundaries, deletion posture, and render-state invariants
recommended_flow: research -> deep dive pass 1 -> Composer architecture consult -> deep dive pass 2 if needed -> phase plan -> consistency pass -> Composer plan consult -> implement only after explicit user request
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:ad46e48e0819a461c4dc1afc6f04b35ed23517b9227e92848569e7917760ab8f",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-30T17:36:53Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:99901c16ac7ab44a263fe3b745928d3944b7bf76afd843bcc6442da15520fb08",
      "completed_at": "2026-05-30T17:37:00Z",
      "doc_hash_after": "sha256:2970f824a248ae3a5b4690e2764d851643cc40464985cb518d85166eb96ef2f5"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T17:37:03Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:2970f824a248ae3a5b4690e2764d851643cc40464985cb518d85166eb96ef2f5",
      "completed_at": "2026-05-30T17:37:14Z",
      "doc_hash_after": "sha256:020a1e0e4b69eb536f35b12e898febe0267354a03ef45b01ca80e699bb9dda10"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T17:37:19Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:020a1e0e4b69eb536f35b12e898febe0267354a03ef45b01ca80e699bb9dda10",
      "completed_at": "2026-05-30T17:37:26Z",
      "doc_hash_after": "sha256:302d1b4bf823fab57efb5d642450256e10669fc055e9e223ae162e51be24a0d2"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-30T17:40:39Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:57010b575d57d57cd29293546942a5318ee86555c3b9d5731ce778f3045029a4",
      "completed_at": "2026-05-30T17:42:00Z",
      "doc_hash_after": "sha256:6c653ec6017893c87830867291eb8faae18520c28d9d77dbdc9dcbdbf51cea15"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-30T17:42:08Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:6c653ec6017893c87830867291eb8faae18520c28d9d77dbdc9dcbdbf51cea15",
      "completed_at": "2026-05-30T17:42:16Z",
      "doc_hash_after": "sha256:70ab74c01749c5819e1f6615331ad30cd641a4781a8a6295d6be93c0eb32d0ec"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, the client can receive Dock stream updates, page a large
thread, reconcile host connectivity, save local metadata, and process command
responses while the user can still scroll, type, swipe, navigate, and open
sheets without visible lag.

The claim is false if any of these remain true:

- A SwiftUI `body` getter sorts, filters, groups, searches, or joins full Dock
  or Thread Detail data.
- A `@MainActor ObservableObject` applies network deltas, normalizes thread
  events, sorts full event arrays, rebuilds full Dock projections, or performs
  persistence work before publishing UI state.
- A data update publishes more often than the render layer can display useful
  frames, instead of coalescing to the latest useful render state.
- Dock Home, Thread Detail, Archive, Hosts, or Connectivity render from
  unbounded arrays that can grow with all known history.
- The data layer has a path where slow decode, resync, disk IO, network IO, or
  large diff construction blocks UI gestures.
- A fallback path keeps the old client store model alive after cutover.

## 0.2 In scope

- Swift client architecture for Dock Home, Thread Detail, Archive, Hosts,
  Connectivity, local metadata, command/request cards, composer draft state,
  voice capture, and realtime transcription UI responsiveness.
- The client boundary to the Node Dock relay on `:4510`.
- The current relay-owned Dock stream contract: `dock/subscribe`,
  `dock/update`, and `dock/resync`.
- The existing raw detail/archive support methods: `thread/read`,
  `thread/turns/list`, `thread/resume`, `thread/list`, `thread/archive`, and
  `thread/unarchive`.
- Internal client layering, actors, render snapshots, render patches,
  projection caches, update coalescing, command routing, cancellation, and
  test/instrumentation proof.
- Deleting or replacing current client code when it violates the target
  boundary.

## 0.3 Out of scope

- Rebuilding the Codex app-server.
- Changing the relay state-engine plan unless the client boundary needs a
  small wire-contract addition.
- Adding cloud sync, multi-user auth, or a production backend.
- Visual redesign unrelated to responsiveness.
- Implementing code in this planning pass.
- Treating server correctness as an excuse for client lag. The client must stay
  responsive even when the data layer is slow, wrong, reconnecting, or
  resyncing.

## 0.4 Definition of done for the future implementation

- Main-thread profiling shows no JSON decode, full-list sort/filter/group,
  event normalization, disk IO, network IO, SQLite work, or bulk diff
  construction during Dock streaming, detail loading, or search/filter edits.
- SwiftUI Instruments shows no repeated long view-body updates caused by Dock
  or Thread Detail projections.
- The app can handle the current relay Dock window size and large Thread Detail
  histories without hangs or hitches during scroll, typing, swipe, navigation,
  and sheet presentation.
- Main actor publish work is bounded to assigning already-prepared render state
  and updating tiny local control state.
- Tests prove the old store responsibilities moved out of `@MainActor` paths.
- The old laggy paths are deleted, not hidden behind flags.

## 0.5 Performance budgets

These are design budgets, not measured claims yet:

- Main actor intent handling: under 1 ms for ordinary taps, typing updates,
  swipe actions, lens changes, host selection, and composer edits.
- Main actor render publication: under 2 ms for Dock, Thread Detail, Archive,
  Hosts, and Connectivity screens.
- SwiftUI view body work: no derived full-list work; body reads render-ready
  values and builds visible views only.
- User-perceived discrete interaction delay: under the 50-100 ms region Apple
  describes as the point where hangs become noticeable.
- Motion/update hitches: no work that risks missing the 8-16 ms display refresh
  window on normal iPhone refresh rates.
- Dock update rate: coalesced to useful render cadence; intermediate data
  states may be dropped when newer render state supersedes them.
- Thread Detail render input: windowed and indexed; render state must not be
  the entire thread history unless the thread is already tiny.

# 1) Key Design Considerations (what matters most)

## 1.1 MainActor is not the app architecture

`MainActor` is the UI executor. It is not the right owner for protocol
reconciliation, full-list projection, thread normalization, local metadata
merges, or connectivity rollups. The current code uses `@MainActor` too broadly
because it made UI publication convenient. The replacement must make background
ownership convenient and make accidental main-actor work hard.

## 1.2 Render state is a product, not a side effect

The target client should not publish raw-ish data and ask views to derive the
screen. It should publish render-ready state:

- rows already sorted and grouped;
- counts already computed;
- request cards already keyed by event ID;
- host and branch facets already prepared;
- visible Thread Detail windows already selected;
- loading/error/offline states already collapsed into user-facing state;
- stable identity and diff hints already attached.

## 1.3 The UI never waits for truth

Truth can be late. The UI should still respond immediately. User intents update
tiny optimistic UI state on main, enqueue commands to actors, and reconcile when
the actor returns success, failure, or a newer snapshot. A slow server response
can keep a spinner or stale marker visible; it cannot freeze a gesture.

## 1.4 Latest useful state wins

Dock Home does not need to render every intermediate stream update. If three
updates arrive while a projection is computing, the render layer should publish
the latest coherent result and skip stale intermediate work. Detail streaming
is different: event order must stay correct, but visible render publication
still needs coalescing.

## 1.5 Server-side bounded state is necessary but not sufficient

The relay state engine already prevents the client from crawling all app-server
history for Dock Home. That solves one class of server/data cost. It does not
solve client-side main-actor projection, SwiftUI body recomputation, or detail
event growth.

## 1.6 Hard cut beats compatibility drift

The final implementation should delete the old UI store shape. A bridge that
keeps old `DockStore`/`ThreadDetailStore` responsibilities alive would preserve
the lag source and make future performance work ambiguous.

# 2) Problem Statement (existing architecture + why change)

The current app has a correct product ambition but the wrong client execution
boundary. It receives bounded Dock stream data from the relay, then does too
much work inside main-actor stores and view getters. That means the most
latency-sensitive executor in the app also owns some of the largest and most
frequent work.

Dock Home is the clearest example. `DockStore` is `@MainActor`; it applies
stream snapshots and deltas, rebuilds a full `DockSnapshot`, saves metadata,
and reports connectivity. `DockSessionTable.snapshot(...)` flattens host data,
sorts sessions, projects row models, and computes host status. Then
`DockView` repeatedly calls `snapshot.project(options:)` from computed
properties and view construction, which filters, searches, groups, sorts,
builds facets, and computes summaries synchronously.

Thread Detail has the same shape with worse growth risk. `ThreadDetailStore` is
`@MainActor`; it reads the full thread, pages all turns, normalizes all turn
items into events, merges live deltas, sorts the full event list, and publishes
loaded snapshots. The view then filters events in `body`, and request-card
lookup scans the request-card list per event.

Archive and Connectivity add smaller but still real pressure. `ArchiveStore`
maps and sorts archive rows on the main actor after host loads. Connectivity
publishes a sorted rollup after every reported operation, and Dock publication
feeds connectivity reporting.

This architecture can be functionally correct and still feel bad. The failure
mode is not only one giant hang. It is also many small view updates, repeated
projection calls, event-list sorts, and extra publications that combine into
missed frames.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->

## 3.1 External Apple guidance

Apple's current SwiftUI performance guidance says view bodies need to compute
quickly, long body computations and too-frequent updates can produce hitches,
and expensive calculations should move out of the view body into asynchronous
work with cached results.

Source: [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).

Apple's user-interface responsiveness guidance distinguishes hangs from
hitches. It ties hangs to long-running main-thread work and points out that
even one display-refresh interval, commonly 8-16 ms, can be enough to create a
hitch during motion.

Source: [Understanding user interface responsiveness](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness).

Apple's Instruments hang tutorials call out asynchronous hangs, where work
scheduled from something like a network event runs on the main thread and makes
the app unresponsive later, not necessarily at the original user action.

Sources:

- [Getting started with hang analysis](https://developer.apple.com/tutorials/instruments/getting-started-with-hang-analysis)
- [Understanding synchronous and asynchronous hangs](https://developer.apple.com/tutorials/instruments/understanding-synchronous-and-asynchronous-hangs)

Apple's WWDC23 SwiftUI performance session emphasizes measuring symptoms,
understanding dependencies, reducing unnecessary updates, and keeping list/table
identity stable.

Source: [Demystify SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/).

Apple's WWDC23 hang analysis session uses roughly 100 ms as a useful "instant"
target for direct interactions and treats longer delays as increasingly
noticeable.

Source: [Analyze hangs with Instruments](https://developer.apple.com/videos/play/wwdc2023/10248/).

## 3.2 Internal repo facts

The README establishes the right server direction: Dock Home uses the relay on
`:4510`, not the raw app-server on `:4500`. The relay owns `dock/subscribe`,
`dock/update`, and `dock/resync`, materializes app-server thread projections in
SQLite, and leaves raw `thread/list` for archive/detail/diagnostics.

`CodexDock/AppServer/AppServerClient.swift` is already an actor. Protocol
request/response state, receive-loop decoding, notification routing, and
server request streams do not need to live on `MainActor`.

`CodexDock/State/AppServerDockStreamClient.swift` bridges relay notifications
into `AsyncThrowingStream<DockStreamUpdateDTO>`. This is a good boundary, but
the downstream consumer currently moves the heavy application and projection
work back to `MainActor`.

`CodexDock/State/DockStore.swift` is `@MainActor` and owns stream connection,
snapshot/delta application, metadata loading/saving, full snapshot publication,
and connectivity reporting.

`CodexDock/State/DockSessionTable.swift` applies snapshots/deltas and builds
full `DockSnapshot` values by flattening host sessions, sorting sessions, and
projecting rows.

`CodexDock/State/DockSessionProjection.swift` computes filtering, search,
pinned/body split, grouping, sorting, facets, and summaries from full snapshot
rows.

`CodexDock/Features/Dock/DockView.swift` calls `snapshot.project(options:)`
from multiple body-adjacent paths, including `currentProjection`,
`loadedContent`, and accessibility/screen value helpers.

`CodexDock/State/ThreadDetailStore.swift` is `@MainActor` and owns full-thread
read, all-turn pagination, event normalization, merge, sort, request-card
publication, and live event handling.

`CodexDock/Models/ThreadEvent.swift` has the full-event normalization and
newest-first sort helpers currently called from main-actor detail store paths.

`CodexDock/Features/Session/SessionDetailView.swift` filters loaded events in
view construction before passing them to `ThreadMessageListView`.

`CodexDock/Features/Session/ThreadMessageListView.swift` renders arrays passed
to it and scans request cards for each request event.

`CodexDock/State/AppConnectivityStore.swift` is `@MainActor` and maps/sorts
connectivity records after reports, including reports that Dock publication
triggers.

`scripts/dock-relay-state-engine.mjs` and related relay files already move Dock
truth toward a bounded server-side state engine. The client should build on
that instead of recreating a full derived-state engine on the UI executor.

## 3.3 Planning pass result

Research pass result: the external standard is clear enough to make this a hard
architecture rule, not a tuning preference. SwiftUI view bodies must stay fast,
frequent updates must be reduced, main-thread hangs are unacceptable, and
expensive derivation belongs outside `body` and outside hot main-actor
publication paths. The internal evidence shows Dock and Thread Detail currently
violate that standard in multiple places.

<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->

## 4.1 Runtime data flow today

Normal Dock Home path:

1. `AppServerClient` actor connects to the relay WebSocket.
2. `AppServerDockStreamClient` subscribes to `dock/subscribe` and exposes
   `DockStreamUpdateDTO` updates.
3. `DockStore` receives those updates on `MainActor`.
4. `DockStore` mutates `DockSessionTable`.
5. `DockStore.publishSnapshot()` asks the table to build a full
   `DockSnapshot`.
6. `DockView` repeatedly derives `DockSessionProjection` from that snapshot
   during view updates.

Thread Detail path:

1. `ThreadDetailStore.load()` connects and reads thread detail.
2. `ThreadDetailStore.readFullThread()` calls `thread/read`.
3. `ThreadDetailStore.readAllTurns()` pages `thread/turns/list` until complete.
4. `ThreadEventNormalizer` converts turns/items into `ThreadEvent` values.
5. `ThreadEventDisplayOrder.newestFirst` sorts all events.
6. `SessionDetailView` filters events during view construction.
7. `ThreadMessageListView` renders the resulting event array and looks up
   request cards by scanning.

Thread Detail composer/voice path:

1. `ThreadDetailStore+Voice.swift` extends the same `@MainActor`
   `ThreadDetailStore`.
2. Composer draft state, voice phase, active dictation segment, active
   transcription session, active capture session, and task references live
   beside the detail data-loading state.
3. `beginVoiceCapture(...)`, `finishVoiceCapture(...)`, commit/cancel helpers,
   transcription event observation, audio forwarding, draft replacement, and
   voice error handling all run through the main-actor store.
4. Audio chunk forwarding uses a `Task { @MainActor ... }` loop that awaits
   transcription appends while sharing the UI executor.
5. Transcription deltas update `composer.draft` directly on the same object
   that also owns full-thread read, live event merge, and snapshot publication.

Archive path:

1. `ArchiveStore.reload()` loads local metadata.
2. Host loads happen in a task group.
3. `ArchiveStore.makeSnapshot()` maps and sorts archive sections on
   `MainActor`.

Connectivity path:

1. Network/store operations report status.
2. `AppConnectivityStore.record(...)` mutates records on `MainActor`.
3. `AppConnectivityStore.publish()` maps, sorts, and rolls up all records.

## 4.2 Where UI and data responsibilities are mixed

`DockStore` currently owns both UI-facing state and data-engine behavior:

- host list management;
- stream connection lifecycle;
- stream snapshot/delta application;
- metadata load/save integration;
- full Dock snapshot construction;
- connectivity reporting;
- error and loading state publication.

`DockView` currently owns render derivation:

- search projection;
- lens/filter projection;
- host/branch grouping;
- pinned/body split;
- summary text;
- screen/accessibility aggregate values.

`ThreadDetailStore` currently owns both detail data and render data:

- transport connection;
- full read and pagination;
- event normalization;
- request-card merge;
- live event merge;
- full event sorting;
- loaded snapshot publication.

`ThreadDetailStore+Voice` currently makes composer and voice part of that same
main-actor object:

- immediate draft text;
- voice start/finish/cancel;
- live audio capture session;
- realtime transcription session;
- audio chunk forwarding;
- transcription event observation;
- provisional/final transcript merge into the composer draft;
- voice/transcription error state.

`SessionDetailView` and `ThreadMessageListView` still do derived-list work:

- filter events in `body`;
- scan request cards per event;
- receive unbounded event arrays as render input.

## 4.3 Why the relay work does not fully solve client lag

The relay state engine gives Dock Home a bounded server-side source. That is
necessary. It means the app should not have to crawl raw Codex history for the
normal Dock list.

But after the bounded data reaches the client, the current Swift code still
rebuilds and reprojects screen state on the main actor. A smaller input can
still cause a hitch if it is sorted, grouped, filtered, and republished too
often on the UI executor. Thread Detail is even less bounded because it still
pages and normalizes all turns for a thread.

## 4.4 Current architecture strengths to keep

- The relay is the normal phone endpoint; the iPhone does not need raw
  app-server auth.
- `AppServerClient` is already an actor with typed request/response APIs.
- Dock stream DTOs already distinguish snapshot, delta, heartbeat, sequence,
  base sequence, window size, and schema.
- The relay can resync when sequence gaps occur.
- Local metadata is already in a separate actor-backed store.
- Diagnostics already have `DockSignpost` and MetricKit persistence hooks.

## 4.5 Current architecture liabilities to delete

- `@MainActor` stores that apply large data deltas or build full projections.
- SwiftUI computed properties that perform full projection work.
- Full event arrays as primary render input for Thread Detail.
- Full-sort-on-every-publish detail snapshots.
- Request-card lookup by repeated scan.
- Connectivity publish work piggybacked synchronously on hot Dock publication.
- Voice/audio/transcription loops that share the same main-actor store as
  Thread Detail loading and event publication.
- Any test or preview that makes the old main-actor work look acceptable by
  using small fixtures only.

## 4.6 Deep-dive pass 1 conclusion

The highest-risk client pattern is repeated across screens: the same object
often owns connection, model mutation, render derivation, and UI publication.
That is the wrong abstraction for responsiveness. The first cut must split
ownership by executor and responsibility before optimizing individual loops.

<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->

## 5.1 One-sentence target

The data layer may be busy forever; the UI layer renders the latest prepared
screen state and accepts input immediately.

## 5.2 Target layers

### Layer A: Protocol clients

Owners:

- `AppServerClient`
- `AppServerDockStreamClient`
- future typed clients only where needed

Responsibilities:

- WebSocket connection lifecycle;
- JSON-RPC request/response matching;
- raw notification and server-request streams;
- typed DTO decode;
- transport errors and reconnect signals.

Rules:

- Protocol clients are actors or actor-owned.
- They do not publish SwiftUI state.
- They do not know lenses, search text, pinned layout, visible windows, or
  SwiftUI identity.

### Layer B: Data engines

Proposed owners:

- `DockDataEngine`
- `ThreadDetailDataEngine`
- `ArchiveDataEngine`
- `ConnectivityDataEngine`
- `LocalMetadataEngine` or retained `LocalThreadMetadataStore` behind a stricter
  engine facade
- `ClientCommandEngine`

Responsibilities:

- consume protocol streams;
- hold canonical in-memory indexes;
- apply snapshots/deltas;
- page detail data;
- merge live events;
- update local metadata;
- route commands;
- handle retries, sequence gaps, cancellation, and stale data;
- expose `AsyncSequence` outputs of model changes or render inputs.

Rules:

- Engines are not `MainActor`.
- Engines own mutation, indexing, and ordering.
- Engines expose immutable `Sendable` values.
- Engines make slow work cancellable and supersedable.

### Layer C: Projection and render engines

Proposed owners:

- `DockRenderProjector`
- `ThreadDetailRenderProjector`
- `ArchiveRenderProjector`
- `ConnectivityRenderProjector`
- shared `RenderCoalescer`

Responsibilities:

- turn canonical model indexes into render snapshots;
- sort, filter, group, search, facet, and summarize off main;
- maintain cached projections keyed by input version and view options;
- produce stable row IDs and diff hints;
- window large detail histories;
- drop obsolete projection tasks when newer inputs arrive.

Rules:

- Projection code is pure enough to unit-test without SwiftUI.
- Projection never runs from a SwiftUI `body`.
- Search/filter/lens changes enqueue projection work; the UI remains usable
  while projection catches up.
- Render coalescing is revision-driven first and time-based second: a newer
  model/options revision cancels or supersedes older projection work, while
  user typing may also use a small debounce constant to avoid projecting every
  intermediate character.
- Client render-window sizes, debounce delays, coalescing intervals, and
  publication budgets belong in `CodexDock/Configuration/CodexDockConstants.swift`.

### Layer D: MainActor render stores

Proposed owners:

- `DockScreenStore`
- `ThreadDetailScreenStore`
- `ArchiveScreenStore`
- `ConnectivityScreenStore`
- small shared intent helpers if needed

Responsibilities:

- hold `@Published` or `@Observable` render-ready screen state;
- hold tiny UI control state that must update immediately, such as focused
  search text, selected lens, selected host filter, composer draft text, and
  sheet visibility;
- forward intents to engines;
- publish the latest render snapshot from a coalesced stream.

Rules:

- Main actor stores do not decode JSON.
- Main actor stores do not page data.
- Main actor stores do not sort/filter/group full lists.
- Main actor stores do not normalize thread events.
- Main actor stores do not write files.
- Main actor stores do not wait for command completion before updating local
  interaction state.
- Screen stores use one observable surface per screen. Whether the final code
  uses `@Observable` or `ObservableObject` is an implementation detail; the
  invariant is a tiny publish surface with render-ready values only.

### Layer E: SwiftUI views

Responsibilities:

- render already-prepared state;
- collect user intent;
- use stable identity;
- keep layout predictable and bounded;
- avoid full-list derived work.

Rules:

- `body` can switch on screen state and map visible row models to row views.
- `body` cannot call `snapshot.project(...)` or equivalent full derivation.
- `body` cannot filter large event arrays.
- Request cards are dictionary lookups or already attached to event render
  models.
- Lists use lazy/native containers where appropriate and preserve stable IDs.

## 5.3 Target Dock flow

1. Relay sends `dock/subscribe` snapshot and `dock/update` deltas.
2. `AppServerDockStreamClient` decodes DTOs off main.
3. `DockDataEngine` applies snapshots/deltas to a host-scoped indexed model.
4. `DockDataEngine` emits versioned model changes.
5. `DockRenderProjector` combines model version, local metadata, current lens,
   current search query, current filters, and current grouping mode.
6. `DockRenderProjector` computes one render snapshot off main.
7. `RenderCoalescer` drops stale render snapshots and keeps the latest.
8. `DockScreenStore` assigns the latest render snapshot on `MainActor`.
9. `DockView` renders `DockRenderSnapshot` directly.

Dock render snapshot shape should include:

- `revision`;
- `isStale`;
- `hosts`;
- `summary`;
- `sections`;
- `visibleRows`;
- `pinnedRows`;
- `bodyRows`;
- `facets`;
- `emptyState`;
- `offlineState`;
- `accessibilitySummary`;
- stable row IDs and optional row-level change markers.

## 5.4 Target Thread Detail flow

1. Detail screen opens with immediate shell state: title/session identity,
   loading marker, composer enabled if safe, and last known summary if present.
2. `ThreadDetailDataEngine` reads header/compact detail and first useful event
   window off main.
3. All-turn pagination runs off main and is cancellable.
4. Event normalization and ordering are actor-owned and incremental.
5. Request cards are keyed by ID before they reach render state.
6. `ThreadDetailRenderProjector` publishes visible windows, not full unbounded
   history.
7. Live deltas update the event index and publish coalesced render changes.
8. `ThreadDetailScreenStore` assigns render-ready snapshots only.
9. `SessionDetailView` and `ThreadMessageListView` render visible event rows
   and never scan full data.

Thread Detail render snapshot shape should include:

- `revision`;
- `sessionHeader`;
- `connectionState`;
- `composerState`;
- `visibleWindow`;
- `scrollAnchors`;
- `hasOlder`;
- `hasNewer`;
- `pendingRequestCardsByEventID`;
- `liveActivity`;
- `emptyState`;
- `errorBanner`;
- stable event IDs and optional insert/update/delete hints.

Thread Detail window constants should be explicit Swift constants. Initial
planning defaults:

- newest visible event window: 150-300 render rows;
- pagination page size: owned by the data engine and existing DTO/server caps;
- request-card lookup: dictionary keyed by event/request ID before render;
- older/newer expansion: explicit user or scroll-triggered pagination, not
  automatic rendering of the entire thread.

## 5.4.1 Target composer, voice, and transcription flow

Composer text is UI state; audio capture and transcription are data/IO work.
The future architecture must split those facts cleanly.

1. `ThreadDetailScreenStore` owns immediate composer draft text, focus, send
   button state, and a tiny `ComposerVoiceRenderState`.
2. `VoiceCaptureEngine` owns live capture session lifecycle and audio chunk
   streams off main.
3. `TranscriptionEngine` owns realtime transcription session lifecycle, audio
   append, event observation, commit, cancel, and errors off main.
4. `ThreadDetailDataEngine` or `ClientCommandEngine` receives final composer
   send/voice transcript commands and reconciles with thread state.
5. A voice render projector/coalescer emits tiny transcript render updates:
   phase, provisional text, final text, and error.
6. `ThreadDetailScreenStore` applies provisional transcript updates to the
   visible draft without waiting on full Thread Detail render projection.

Rules:

- Audio forwarding never runs on `MainActor`.
- Transcription event observation never runs on `MainActor` except for the tiny
  final publication of render state.
- Provisional transcript updates may replace the visible draft immediately, but
  they cannot trigger full thread event projection.
- Voice cancel/finish must remain responsive while detail pagination,
  reconnect, or stream resync is in progress.
- The composer can be locally disabled by voice phase, but that is a tiny
  render-state rule, not a reason to block UI.

## 5.5 Target command flow

Commands must not be query/render state side effects.

1. View sends an intent, such as pin, unpin, archive, resume, respond to
   request card, send composer text, interrupt, retry, or refresh.
2. Main actor updates tiny optimistic UI state only if that is safe.
3. `ClientCommandEngine` receives the command.
4. The command engine validates against the latest engine-owned model.
5. The command engine calls the relay/app-server.
6. Data engines reconcile from command result or subsequent stream update.
7. Render projectors produce the next snapshot.
8. The main actor publishes the result or a bounded error state.

Rules:

- Command buttons do not wait synchronously for data projection.
- Duplicate commands are deduped by command ID where needed.
- Commands are cancellable when their screen disappears unless product behavior
  requires completion.
- Error UI is a render state, not an exception path that blocks future input.

## 5.6 Target connectivity flow

Connectivity should become a projection of route/host facts, not extra work
piggybacked on every Dock snapshot publish.

1. Protocol and data engines emit route events to `ConnectivityDataEngine`.
2. Connectivity engine keeps bounded records and rollups off main.
3. Connectivity projector emits render-ready connectivity state.
4. Main actor publishes tiny connectivity render state.

Rules:

- Dock render publication does not synchronously force connectivity sorting.
- Connectivity records are bounded by constants.
- Route-health and user-visible offline state use the same facts.

## 5.7 Target local metadata flow

Local metadata is user-owned UI/product state, but persistence is not UI work.

1. Main actor immediately records tiny optimistic state for local-only actions
   such as pin/unpin/collapse where product-safe.
2. Metadata command goes to a metadata engine/actor.
3. Actor persists and emits a model version.
4. Dock/Archive projectors recompute affected render snapshots off main.
5. Failures produce bounded error render state and rollback only if needed.

## 5.8 Target deletion posture

The implementation should delete or hollow out these old responsibilities:

- `DockStore` as a main-actor data engine;
- `DockSessionTable.snapshot(...)` as a main-actor projection path;
- `SessionRowProjector` as a helper reachable from main-actor snapshot
  publication; its row mapping, cached pinned row, and activity-display work
  must be owned by `DockRenderProjector` or a pure off-main helper;
- `DockView.currentProjection` and any view getter that computes full
  projections;
- `ThreadDetailStore` as a main-actor thread normalizer/sorter;
- `ThreadDetailStore+Voice` as a main-actor audio/transcription forwarding
  owner;
- `SessionDetailView` body filtering over full event arrays;
- `ThreadMessageListView` request-card scanning;
- `AppConnectivityStore.publish()` as hot main-actor sorting after every route
  report.

Existing names may be retained only if their responsibilities are replaced.
Keeping the name is fine. Keeping the laggy responsibility is not.

## 5.9 Deep-dive pass 2 conclusion

The target cannot be "move a few expensive loops off main." That would leave
too many accidental paths for future lag. The target must be a render-state
architecture where every screen has the same rule: data engines and render
projectors prepare state off main, and main-actor stores only publish prepared
state plus tiny immediate controls.

## 5.10 Screen-store and engine lifecycle contract

The phase plan must implement one lifecycle model, not invent one per screen.

Application lifetime:

- A `ClientRuntime` or equivalent composition root owns shared protocol clients,
  host registry access, local configuration, local metadata persistence,
  connectivity engine, and command engine.
- `CodexDockBootstrapView` creates or receives this runtime after relay
  bootstrap reaches a ready host registry.
- `CodexDockRootView` receives the runtime and asks it for screen stores and
  scoped factories instead of constructing broad stores directly.
- Shared engines are long-lived only when their state is cross-screen product
  state, such as Dock, host configuration, connectivity, and local metadata.
- Shared engines do not publish directly to SwiftUI.

Screen lifetime:

- Each screen creates or receives one screen store.
- Each screen store owns exactly one coalesced render subscription task per
  render stream.
- Detail screens own per-session `ThreadDetailDataEngine` handles or scoped
  sessions from a shared detail engine.
- Navigation pop/disappear cancels scoped pagination, projection, voice capture,
  transcription, and render subscription tasks unless a command has been
  explicitly promoted to command-engine ownership.
- Cancellation is normal control flow and must leave shared engines consistent.

Delivery:

- Engines expose `AsyncSequence` values of model changes or render snapshots.
- Projectors emit monotonically increasing render revisions.
- A render coalescer keeps only the latest coherent snapshot per screen.
- The only hop to `MainActor` is the final `screenState = latestSnapshot`
  assignment plus tiny immediate UI control mutations.
- Each screen has one consumer for its render stream; duplicate consumers are a
  bug because they multiply projection and publish work.

Search/filter/lens options:

- Immediate control text updates on main for typing responsiveness.
- Option changes are sent to the projector as versioned render options.
- Stale option projections are canceled or dropped by revision.
- Small debounce values, if used, live in `CodexDockConstants.swift`.

<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->

## 6.1 Swift client files

| Area | Current owner | Current problem | Target owner/change |
| --- | --- | --- | --- |
| Dock stream ingestion | `CodexDock/State/DockStore.swift` | Main actor consumes stream updates, applies table changes, publishes full snapshots. | Move stream application to `DockDataEngine`; main store receives render snapshots only. |
| Dock indexed state | `CodexDock/State/DockSessionTable.swift` | Snapshot construction flattens, sorts, maps, and computes status in the UI-facing flow. | Split into off-main model index plus render projector; keep pure helpers only if actor-owned. |
| Dock row projection | `CodexDock/State/SessionRowProjector.swift`, `CodexDock/State/PinnedMetadataOrdering.swift` | Row display mapping, cached pinned rows, activity labels, metadata overlay, and pinned ordering are pulled through `DockSessionTable.snapshot(...)`. | Move summary-to-render-row mapping, cached pinned row construction, and pinned order normalization into `DockRenderProjector` or a pure helper owned only by that projector. Delete any main-actor call path. |
| Dock projection | `CodexDock/State/DockSessionProjection.swift` | Full rows are searched, filtered, grouped, faceted, and summarized synchronously from view paths. | Move projection into `DockRenderProjector` with cache/version keys and no `body` calls. |
| Dock view | `CodexDock/Features/Dock/DockView.swift` | Calls `snapshot.project(options:)` from multiple body-adjacent computed properties. | Render `DockRenderSnapshot`; search/lens/filter changes enqueue projection intents. |
| App composition | `CodexDock/Features/Dock/DockView.swift`, `CodexDock/Features/Dock/CodexDockBootstrapView.swift`, `CodexDock/Configuration/RelayBootstrapStore.swift` | `CodexDockRootView` and bootstrap construct current stores directly and pass raw factories/clients into screens. | Phase 1 starts `ClientRuntime` wiring here; each later phase replaces the relevant factory/screen-store construction before its surface can be accepted. |
| App entry and previews | `CodexDockApp/CodexDockApp.swift`, `CodexDock/Features/Dock/DockViewPreview.swift` | App entry and previews can keep old construction seams alive after runtime wiring changes. | Repoint app entry and previews to bootstrap/runtime factories; previews may use scripted runtime fixtures but not old broad stores. |
| Lifecycle gating | `CodexDock/State/AppLifecycleCoordinator.swift` | Main-actor lifecycle snapshots gate foreground work and are passed through root/bootstrap today. | `ClientRuntime` owns lifecycle streams as an input to engines; screen stores receive render state, not raw lifecycle mutation responsibility. |
| Dock row/pinned rendering | `CodexDock/Features/Dock/DockPinnedViews.swift` and row views | May be fine visually, but must consume render-ready rows and stable identities only. | Keep UI components; remove derived data responsibilities if any remain. |
| Stream DTO bridge | `CodexDock/State/AppServerDockStreamClient.swift` | Good boundary, but downstream hot work returns to main actor. | Retain or move under protocol layer; feed `DockDataEngine`. |
| JSON-RPC actor | `CodexDock/AppServer/AppServerClient.swift` | Actor boundary is good; verify decode and callback streams never require main actor. | Retain as protocol layer; add instrumentation and typed backpressure where needed. |
| Thread detail store | `CodexDock/State/ThreadDetailStore.swift` | Main actor reads/paginates/normalizes/merges/sorts full thread state. | Replace with `ThreadDetailDataEngine`, `ThreadDetailRenderProjector`, and `ThreadDetailScreenStore`. |
| Thread detail composer/voice | `CodexDock/State/ThreadDetailStore+Voice.swift`, `CodexDock/Voice/VoiceCaptureController.swift`, `CodexDock/Voice/TranscriptionService.swift`, `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` | Main actor store owns composer draft, voice phase, active capture/transcription sessions, audio forwarding tasks, transcription observation, and draft merge. | Split immediate composer render state from `VoiceCaptureEngine` and `TranscriptionEngine`; publish tiny transcript render state to `ThreadDetailScreenStore`. |
| Thread detail session factory | `CodexDock/State/AppServerThreadDetailSession.swift`, `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/State/ScriptedThreadDetailSession.swift`, `CodexDockTests/ThreadDetailStoreTestSupport.swift` | Current views receive a `ThreadDetailSessionMaking` factory and stores create/live against current sessions directly. | Runtime exposes a detail-screen factory that creates `ThreadDetailScreenStore` plus scoped data engine/session handles; scripted factories move behind the same runtime seam. |
| Thread event model helpers | `CodexDock/Models/ThreadEvent.swift` | Normalization and sorting helpers are called from main actor paths. | Keep pure helpers but call from off-main engines/projectors; add incremental index helpers. |
| Session detail view | `CodexDock/Features/Session/SessionDetailView.swift` | Filters events in view construction and passes full arrays. | Render visible event window from screen state; filter changes enqueue projection. |
| Composer view | `CodexDock/Features/Session/ComposerView.swift` | Binds directly to current `ThreadDetailStore` composer state and voice methods. | Bind to `ThreadDetailScreenStore` composer render state and intents; voice intents route to voice/transcription engines. |
| Message list view | `CodexDock/Features/Session/ThreadMessageListView.swift` | Renders passed event array and scans request cards per event. | Render `[ThreadEventRenderRow]`; request cards already attached or dictionary keyed. |
| Archive store | `CodexDock/State/ArchiveStore.swift` | Main actor maps/sorts sections after host loads. | Move projection to `ArchiveRenderProjector`; main store publishes prepared sections. |
| Archive view | `CodexDock/Features/Archive/ArchiveView.swift` | Receives current archive store and can preserve old refresh/restore callback seams. | Bind to `ArchiveScreenStore` render state and command intents from runtime. |
| Connectivity store | `CodexDock/State/AppConnectivityStore.swift` | Main actor maps/sorts/rolls up records after reports. | Move record aggregation to `ConnectivityDataEngine`; publish bounded render state. |
| Local metadata store | `CodexDock/State/LocalThreadMetadataStore.swift` | Actor-owned file IO is okay, but UI awaits can still sequence into hot publishes. | Keep actor or wrap; make optimistic UI and async persistence reconciliation explicit. |
| Host settings | `CodexDock/State/HostSettingsStore.swift`, `CodexDock/Features/Hosts/HostsView.swift` | Low-traffic, but still `@MainActor`; rows are derived in a computed property, host tests call the raw loader, and status/reporting shares UI executor. | Keep simple UI, but move host tests/persistence/status aggregation behind host/config engines if implementation touches Hosts; render rows prepared before publication. |
| Diagnostics | `CodexDock/Diagnostics/Logging.swift`, MetricKit reporter | Existing hooks are useful but not enough to enforce render budgets. | Add signposts around projection, coalescing, main publish, body hot paths, and command latency. |
| Scripted UI/test harnesses | `CodexDock/State/ScriptedDockStreamClient.swift`, `CodexDock/State/ScriptedThreadDetailSession.swift`, `CodexDockTests/AppServerClientTests.swift` scripted transport support | Scripted clients currently match old store/session seams. | Preserve scripted proof by moving it behind protocol/data-engine/runtime seams so UI tests exercise the new architecture. |
| UI automation | `CodexDockUITests/CodexDockAutomationSmokeTests.swift` and related UI test support | UI tests may depend on old bootstrap/store construction and scripted scenarios. | Repoint scripted launch env and automation assertions to the runtime-backed screens; keep proving real screen behavior, not previews. |
| Tests | `CodexDockTests/DockStoreStreamTests.swift`, `ThreadDetailStoreTests.swift`, connectivity/archive tests | Mostly correctness tests over current stores; little performance/backpressure proof. | Replace/add tests around engines, render projectors, coalescing, windowing, and main-actor contracts. |

## 6.2 Node relay/server files

| Area | Current owner | Current role | Target change |
| --- | --- | --- | --- |
| Relay dispatch | `scripts/dock-relay.mjs` | Owns downstream app methods and WebSocket route. | Preserve method contracts unless a specific render contract addition is needed. |
| Relay state engine | `scripts/dock-relay-state-engine.mjs` | Reconciles app-server state and serves Dock snapshots/deltas. | Treat as the source of bounded Dock data; do not make client compensate with full-history work. |
| Relay subscriptions | `scripts/dock-relay-state-subscriptions.mjs` | Publishes deltas/snapshots with soft limits. | Keep sequence/gap semantics; add client-visible hints only if needed for coalescing/windowing. |
| Relay constants | `scripts/dock-relay-constants.mjs` | Owns window sizes, soft byte limits, update cadence. | Keep server-side caps explicit; client budgets must be separate Swift constants. |
| Relay tests | `scripts/dock-relay*.test.mjs` | Prove relay state behavior. | Add only if client plan requires DTO/wire additions. |

## 6.3 Documentation and command surfaces

| Surface | Required change |
| --- | --- |
| `README.md` | Update only after implementation to describe the client render architecture and responsiveness verification commands. |
| `Makefile` | Add any future performance/diagnostic targets here, not as ad hoc raw commands. |
| `project.yml` | Update first if new files, build settings, entitlements, assets, or schemes change. |
| `Package.swift` | Update for new Swift source/test ownership if package target structure changes. |
| `.env` | No change. Secrets stay Mac-side. |

## 6.4 Tests to retire or rewrite

The future implementation should rewrite tests that encode old store behavior
instead of preserving that behavior as compatibility:

- tests that require `DockStore` itself to apply stream deltas on
  `MainActor`;
- tests that inspect full `DockSnapshot.project(...)` from view-like paths;
- tests that require `ThreadDetailStore` to publish full sorted event arrays;
- tests that assume request cards are looked up by scanning arrays;
- tests that treat connectivity rollup as synchronous Dock-publish side work.
- tests that construct old stores directly when the screen should be created by
  `ClientRuntime` factories.

## 6.4.1 Test migration map

| Current test file | Future ownership |
| --- | --- |
| `CodexDockTests/DockStoreTests.swift` | Split into `DockDataEngineTests`, `DockRenderProjectorTests`, `DockScreenStoreTests`, and command/metadata tests. |
| `CodexDockTests/DockStoreStreamTests.swift` | Move stream snapshot/delta/gap/resync tests to `DockDataEngineTests`; keep scripted stream support behind runtime seam. |
| `CodexDockTests/DockStoreTestsProjection` | Move all projection assertions to `DockRenderProjectorTests`; no view/body projection tests remain. |
| `CodexDockTests/DockStoreScopeTests.swift` | Split host registry/runtime composition cases between `ClientRuntimeTests` and `HostSettingsDataEngineTests`. |
| `CodexDockTests/ThreadDetailStoreTests.swift` | Split paging/normalization/request-card/live tests into `ThreadDetailDataEngineTests`, `ThreadDetailRenderProjectorTests`, `ThreadDetailScreenStoreTests`, and `TranscriptionEngineTests`. |
| `CodexDockTests/ThreadDetailStreamingMergeTests.swift` | Move event merge and live delta tests to `ThreadEventIndexTests` and `ThreadDetailDataEngineTests`. |
| `CodexDockTests/ThreadDetailStoreLifecycleTests.swift` | Move lifecycle/cancellation tests to `ThreadDetailScreenStoreLifecycleTests` and `ClientRuntimeLifecycleTests`. |
| `CodexDockTests/VoiceCaptureControllerTests.swift` | Keep low-level capture tests and add `VoiceCaptureEngineTests` for off-main lifecycle/forwarding. |
| `CodexDockTests/ComposerVoiceControlsPresentationTests.swift` | Repoint to `ThreadDetailScreenStore` composer render state and `ComposerView` intent bindings. |
| `CodexDockTests/AppConnectivityStoreTests.swift` | Move aggregation/rollup tests to `ConnectivityDataEngineTests` and `ConnectivityRenderProjectorTests`. |
| `CodexDockTests/DockConfigurationTests.swift` | Keep endpoint validation; add runtime/bootstrap wiring tests for `RelayBootstrapStore` and `ClientRuntime`. |
| `CodexDockTests/AppLifecycleCoordinatorTests.swift` | Keep lifecycle coordinator tests; add runtime lifecycle subscription tests. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift` | Keep user-flow coverage; update scripted launch/runtime seams and automation IDs only where the new render models change screen state. |

## 6.5 Tests to add

- `DockDataEngineTests`: applies snapshot, delta, heartbeat, sequence gap, and
  resync triggers off main.
- `DockRenderProjectorTests`: search/filter/group/pinned/facet projections are
  deterministic and version-cached.
- `DockRenderCoalescerTests`: burst updates publish latest coherent render
  state and drop stale work.
- `DockScreenStoreTests`: main actor store only assigns prepared render state
  and forwards intents.
- `ThreadDetailDataEngineTests`: pages, normalizes, merges, dedupes, and
  maintains event index off main.
- `ThreadDetailRenderProjectorTests`: visible windows, filter changes, request
  cards, anchors, and live deltas render without full-array view filtering.
- `VoiceCaptureEngineTests` and `TranscriptionEngineTests`: audio forwarding,
  provisional/final transcript handling, cancel/finish, and errors do not
  require `MainActor` data work.
- `ThreadDetailScreenStoreComposerTests`: draft typing and voice phase updates
  stay immediate while detail pagination/projection is in flight.
- `ArchiveRenderProjectorTests`: archive sections and metadata overlays are
  prepared off main.
- `ConnectivityDataEngineTests`: route records and rollups are bounded and
  publish render-ready values.
- `ResponsivenessContractTests`: use injected large fixtures and assert
  projection functions are not reachable from main-actor screen-store publish
  paths.
- `Metric/Instrumentation smoke`: signpost names exist and are emitted around
  projection and main publish.

<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->

## 7.1 Implementation rules for every phase

This plan is depth-first. Each phase must leave the touched surface on the new
architecture before moving on. It is acceptable for new types to compile beside
old types during a phase, but a phase is not complete while the user-facing
runtime can still use the old laggy path for that surface.

Global rules:

- No production fallback flag to the old UI/data architecture.
- No SwiftUI `body` full-list projection.
- No `@MainActor` data engine.
- No `Task { @MainActor ... }` loop for network, audio, paging, projection,
  normalization, sorting, grouping, or file IO.
- No hard-coded production timing/window constants outside
  `CodexDock/Configuration/CodexDockConstants.swift`.
- Update `project.yml` before generated-project wiring changes, then run
  `rtk xcodegen generate --spec project.yml`.
- Use the Makefile commands named in this repo. Do not use raw `xcodebuild` or
  raw simulator install commands as the normal workflow.
- Delete or replace old code once its surface is cut over. Do not leave
  `old`, `legacy`, `deprecated`, backup, or copy files beside the live path.

Common new vocabulary:

- `ClientRuntime`: composition root for shared protocol clients, data engines,
  command engine, local configuration, local metadata, and connectivity.
- `RenderRevision`: monotonic revision attached to render snapshots.
- `RenderCoalescer`: actor or async helper that keeps latest coherent render
  state and drops superseded render work.
- `ScreenStore`: `@MainActor` observable object or observable type that owns
  render-ready screen state plus tiny immediate controls.
- `DataEngine`: non-main actor that owns canonical model mutation and IO.
- `RenderProjector`: non-main actor or pure worker that converts model/options
  revisions into render snapshots.
- `CommandEngine`: non-main actor that owns mutating commands and reconciliation
  with data engines.

## 7.2 Phase 0 - Foundation contracts, constants, and instrumentation

Status: COMPLETE

Completed work:

- Added rendering constants under `CodexDockConstants.Rendering`.
- Added rendering/runtime signpost categories and canonical render signpost
  names.
- Added `RenderRevision` and `RenderCoalescer`.
- Added `ConnectivityEventSink` as the non-main runtime seam for route facts
  before the full Phase 5 connectivity engine.
- Added `ClientRuntime` with screen factory descriptors for Dock, Thread
  Detail, Archive, Hosts, and Connectivity.
- Added focused Phase 0 tests for render coalescing, constants, runtime factory
  descriptors, injected clock behavior, and connectivity event sink drain.

Verification:

- `rtk swift test --filter RenderCoalescerTests` passed, 3 tests.
- `rtk swift test --filter ClientRuntimeTests` passed, 3 tests.
- `rtk swift test --filter DockStoreTests` passed, 48 tests.
- `rtk swift test --filter ThreadDetailStoreTests` passed, 52 tests.

Goal: make the new architecture possible without changing user behavior yet.

Files to add or edit:

- `CodexDock/Configuration/CodexDockConstants.swift`
- `CodexDock/Diagnostics/Logging.swift`
- new `CodexDock/Runtime/ClientRuntime.swift`
- new `CodexDock/Runtime/ConnectivityEventSink.swift`
- new `CodexDock/Rendering/RenderRevision.swift`
- new `CodexDock/Rendering/RenderCoalescer.swift`
- new `CodexDock/Rendering/RenderSignposts.swift` if keeping signpost names
  separate is cleaner than expanding `Logging.swift`
- `project.yml` if new groups/files require XcodeGen wiring
- `Package.swift` only if SwiftPM target wiring needs explicit changes

Implementation steps:

1. Add client responsiveness constants:
   - `mainPublishWarningBudgetMS = 2`;
   - `mainPublishCriticalBudgetMS = 4`;
   - Dock render coalescing policy;
   - `searchDebounceMS = 80`;
   - `voiceTranscriptPublishDebounceMS = 50`;
   - `threadInitialVisibleWindowRows = 240`;
   - `threadPaginationPrefetchThresholdRows = 60`;
   - `maxDockRowsPerMainPublish = 600`;
   - `renderStreamBufferNewest = 1`.
2. Add render signpost categories/names for model apply, projection, coalesce,
   main publish, command intent-to-render, detail page/normalize, and voice
   transcript publish.
3. Add `RenderRevision` as a small `Sendable`, comparable value.
4. Add `RenderCoalescer` with latest-wins semantics for snapshots. The data
   engine must preserve canonical truth; the coalescer only drops obsolete
   render outputs.
5. Add the screen-store subscription contract:
   - every screen store has `start()` and `stop()` or equivalent idempotent
     lifecycle methods;
   - each screen store owns exactly one render subscription task;
   - render streams use newest-one buffering for snapshots;
   - the only main-actor hop is final state assignment;
   - `deinit` cancels the subscription task.
6. Add `ClientRuntime` as a minimal composition root with factory methods for:
   - Dock screen store;
   - Thread Detail screen store/session handle;
   - Archive screen store;
   - Hosts screen store;
   - Connectivity screen store;
   - command and metadata engines.
7. Add `ConnectivityEventSink` as a minimal non-main actor/protocol seam used
   before the full Phase 5 connectivity engine exists. It may buffer or forward
   route facts, but Dock must not synchronously call `AppConnectivityStore.publish`.
8. Add focused tests for coalescer semantics, constants ownership, and runtime
   factory creation without starting app IO.

Acceptance criteria:

- New render/coalescer primitives compile and are independent of SwiftUI.
- `RenderCoalescer` tests prove old render revisions are dropped when newer
  coherent revisions arrive.
- `ClientRuntime` can construct screen-store factories without creating old
  broad stores.
- Dock can receive a connectivity event sink from runtime without depending on
  the Phase 5 connectivity render implementation.
- No user-facing screen has changed behavior yet.
- No production constants are introduced outside `CodexDockConstants.swift`.

Verification:

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- If project wiring changed: `rtk xcodegen generate --spec project.yml`

## 7.3 Phase 1 - Dock Home hard cut

Status: IN PROGRESS

Completed work:

- Added `DockRenderInput` and `DockRenderSnapshot`.
- Added `DockRenderProjector` as the owner for Dock row mapping, cached pinned
  row construction, local metadata overlay, summary conversion, and projection
  wrapping.
- Moved `DockSessionTable.snapshot(...)` to delegate snapshot construction to
  `DockRenderProjector`.
- Added `DockDataEngine` as a non-main actor that owns `DockSessionTable`
  mutation, local metadata input, and render snapshot production.
- Added focused tests for `DockRenderProjector` and `DockDataEngine`.

Verification so far:

- `rtk swift test --filter DockRenderProjectorTests` passed, 2 tests.
- `rtk swift test --filter DockDataEngineTests` passed, 3 tests.

Goal: move Dock Home stream ingestion, indexed state, projection, grouping,
search, filtering, pinned split, facets, host status, and main publication out
of the old main-actor store/view projection path.

Files to add or edit:

- `CodexDock/State/DockStore.swift`
- `CodexDock/State/DockSessionTable.swift`
- `CodexDock/State/DockSessionProjection.swift`
- `CodexDock/State/SessionRowProjector.swift`
- `CodexDock/State/PinnedMetadataOrdering.swift`
- `CodexDock/State/AppServerDockStreamClient.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/Features/Dock/DockPinnedViews.swift`
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
- `CodexDock/Features/Dock/DockViewPreview.swift`
- `CodexDockApp/CodexDockApp.swift`
- root composition in `CodexDock/Features/Dock/DockView.swift` where
  `CodexDockRootView` currently constructs stores
- `CodexDock/Configuration/RelayBootstrapStore.swift`
- `CodexDock/State/AppLifecycleCoordinator.swift`
- `CodexDock/Runtime/ConnectivityEventSink.swift`
- new `CodexDock/Dock/DockDataEngine.swift`
- new `CodexDock/Dock/DockRenderProjector.swift`
- new `CodexDock/Dock/DockScreenStore.swift`
- new `CodexDock/Dock/DockRenderModels.swift`
- `CodexDockTests/DockStoreTests.swift`
- `CodexDockTests/DockStoreStreamTests.swift`
- new focused Dock engine/projector/coalescer tests
- `project.yml` if new source files need XcodeGen wiring

Implementation steps:

1. Define `DockRenderSnapshot`, `DockRenderSection`, `DockRenderRow`,
   `DockRenderSummary`, `DockRenderFacets`, and `DockRenderOptions`.
2. Build `DockDataEngine` as a non-main actor that owns:
   - stream subscription;
   - snapshot/delta/heartbeat application;
   - schema/window/sequence gap handling;
   - resync requests;
   - host-scoped indexed sessions;
   - local metadata model revisions from the metadata engine.
3. Move the useful mutation pieces of `DockSessionTable` behind
   `DockDataEngine`. Keep pure helpers only if they are not main-actor bound.
4. Move `SessionRowProjector` responsibilities into `DockRenderProjector` or a
   pure helper owned by it:
   - summary-to-row mapping;
   - host display/endpoint lookup;
   - local metadata overlay;
   - cached pinned row construction;
   - message-vs-raw activity labels;
   - pinned ordering through `PinnedMetadataOrdering`.
5. Build `DockRenderProjector` to compute search, lens filters, pinned/body
   split, grouping, facets, counts, summaries, and accessibility text off main.
6. Make `DockRenderProjector` cache by model revision plus render options.
7. Build `DockScreenStore` as the only Dock `@MainActor` observable. It owns
   selected lens, search text, selected filters, sheet state, and the latest
   `DockRenderSnapshot`.
8. Wire Dock through the real composition points in this phase:
   - `CodexDockBootstrapView` creates/receives `ClientRuntime` when
     `RelayBootstrapStore` reaches `.ready(registry)`;
   - `CodexDockRootView` receives `ClientRuntime`;
   - `CodexDockRootView` asks the runtime for `DockScreenStore`;
   - `DockView` receives `DockScreenStore`, not old `DockStore`;
   - scripted stream clients are injected through runtime factories.
9. Make search and filter updates immediate locally, then enqueue versioned
   render options to the projector. Stale projections must be dropped.
10. Rewrite `DockView` to render `DockRenderSnapshot` directly. Remove every
   `snapshot.project(options:)` call and any equivalent body-time derivation.
11. Route Dock pin/unpin/archive/refresh intents through command/metadata
   engines or temporary command shims that do not block rendering. If a shim is
   used during this phase, delete it before phase acceptance.
12. Stop synchronous Dock publish -> connectivity publish coupling. In Phase 1,
    Dock emits route facts to the runtime `ConnectivityEventSink`; the full
    connectivity data/render engine arrives in Phase 5.
13. Delete or hollow old `DockStore` responsibilities. If the type name remains
    for compatibility with construction sites, it must be a screen store only.

Acceptance criteria:

- Dock Home runtime uses `DockScreenStore` + `DockDataEngine` +
  `DockRenderProjector`.
- `CodexDockRootView` and `CodexDockBootstrapView` construct Dock through
  `ClientRuntime`; Dock is not still wired through old direct store
  construction.
- `DockView` contains no full snapshot projection call.
- `SessionRowProjector` and cached pinned derivation are not reachable from
  main-actor snapshot publication.
- Dock stream updates can arrive while search/lens changes remain immediate.
- Main actor Dock publish is only assignment of render-ready state and tiny
  controls.
- Sequence gaps still trigger resync and stale/offline render state without
  freezing UI.
- Dock does not synchronously force `AppConnectivityStore.publish`; bootstrap
  and the global pre-ready connectivity indicator may keep their current
  connectivity store path until Phase 5.
- Tests use large Dock fixtures, not tiny-only examples.

Verification:

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AppServerClientTests`
- If app target wiring changed: `rtk make app SIM='iPhone 17'`

## 7.4 Phase 2 - Command and local metadata separation

Goal: make user actions independent of render/query state so taps, swipes, and
composer controls never wait on data projection.

Files to add or edit:

- `CodexDock/State/LocalThreadMetadataStore.swift`
- `CodexDock/State/AppServerDockClient.swift`
- `CodexDock/State/DockStore.swift` or replacement Dock screen store files
- `CodexDock/State/ArchiveStore.swift`
- new `CodexDock/Commands/ClientCommandEngine.swift`
- new `CodexDock/Metadata/LocalMetadataEngine.swift` if wrapping the existing
  actor is cleaner than changing it directly
- Dock, Archive, and Thread Detail tests that currently call action methods

Implementation steps:

1. Define command IDs and result states for pin, unpin, reorder pinned, archive,
   unarchive, refresh, resume, interrupt, request-card response, composer send,
   host test, host save, and host remove.
2. Build `ClientCommandEngine` as a non-main actor. It owns dedupe,
   cancellation, command status, app-server/relay mutation calls, and command
   result events.
3. Wrap local metadata persistence with an engine contract:
   - immediate optimistic state for safe local-only actions;
   - actor persistence;
   - reconciliation event;
   - bounded error state.
4. Route Dock local actions through the command/metadata engines.
5. Route Archive archive/unarchive actions through the command engine.
6. Route Thread Detail request-card responses and composer sends through the
   command engine.
7. Make screen stores display command pending/error render state without
   blocking gesture handling.
8. If Thread Detail has not yet moved to `ThreadDetailScreenStore`, allow only
   a temporary old-store command bridge for request-card/composer commands.
   That bridge must be deleted in Phase 3 before Thread Detail acceptance.
9. Delete direct view/store mutation paths that wait for persistence or network
   before updating tiny UI state.

Acceptance criteria:

- User actions do not call app-server/raw loader/persistence directly from a
  SwiftUI view or broad main-actor data store.
- Command failures are render states, not blocked UI.
- Local metadata failures can be shown and reconciled without freezing Dock.
- Command status can be tested without rendering SwiftUI.
- Any temporary old-store command bridge is named, tested, and has a Phase 3
  deletion assertion.

Verification:

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter AppServerClientTests`

## 7.5 Phase 3 - Thread Detail hard cut

Goal: move detail loading, pagination, normalization, event merge, ordering,
filtering, visible-window selection, request cards, and live updates out of the
main-actor store and out of SwiftUI body work.

Phase 3 and Phase 4 are one Thread Detail acceptance unit. Phase 3 may be used
as an internal implementation checkpoint, but the Thread Detail surface is not
accepted and must not be called complete until Phase 4 also moves
composer/voice/transcription off the old main-actor path.

Files to add or edit:

- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/State/ThreadDetailStore+Voice.swift`
- `CodexDock/State/AppServerThreadDetailSession.swift`
- `CodexDock/State/ScriptedThreadDetailSession.swift`
- `CodexDock/State/AppLifecycleCoordinator.swift`
- `CodexDock/Models/ThreadEvent.swift`
- `CodexDock/Features/Session/SessionDetailView.swift`
- `CodexDock/Features/Session/ThreadMessageListView.swift`
- `CodexDock/Features/Session/ComposerView.swift`
- `CodexDock/Features/Dock/DockView.swift` for detail navigation/factory wiring
- `CodexDock/AppServer/AppServerClient.swift` only if DTO/request APIs need
  small additions
- new `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`
- new `CodexDock/ThreadDetail/ThreadEventIndex.swift`
- new `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`
- new `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift`
- new `CodexDock/ThreadDetail/ThreadDetailRenderModels.swift`
- `CodexDockTests/ThreadDetailStoreTests.swift`
- new focused detail engine/projector/window tests

Implementation steps:

1. Define `ThreadDetailRenderSnapshot`, `ThreadEventRenderRow`,
   `ThreadVisibleWindow`, `ThreadDetailRenderOptions`, request-card render
   models, scroll anchors, live state, composer state, and error banners.
2. Build `ThreadDetailDataEngine` as a non-main actor for one session. It owns:
   - connection/session identity;
   - `thread/read`;
   - `thread/turns/list` pagination;
   - `thread/resume` or compact rehydrate calls;
   - live notifications;
   - server request cards;
   - event dedupe/merge;
   - cancellation on screen teardown.
3. Build `ThreadEventIndex` to maintain stable event order incrementally.
   Sorting the full event list on every publish is forbidden.
4. Move `ThreadEventNormalizer` calls off main. Keep pure normalizers if useful.
5. Build `ThreadDetailRenderProjector` to create visible windows and filtered
   render rows off main.
6. Replace request-card array scans with dictionary or pre-attached card render
   values.
7. Build `ThreadDetailScreenStore` as the only detail `@MainActor` observable.
   It owns selected filter, composer draft control state, sheet/alert state,
   and latest render snapshot.
8. Replace `ThreadDetailSessionMaking` view injection with a runtime-owned
   detail factory:
   - `ClientRuntime.makeThreadDetailScreenStore(row:)`;
   - scoped `ThreadDetailDataEngine`;
   - scoped session handle from `AppServerThreadDetailSessionFactory`;
   - scripted session handle for UI/test scenarios through the same seam;
   - lifecycle cancellation from `AppLifecycleCoordinator` snapshots.
9. Rewrite `SessionDetailView` so `body` does not call
   `filter.visibleEvents(from: snapshot.events)` over full history.
10. Rewrite `ThreadMessageListView` to receive visible render rows only.
11. Rebind `ComposerView` to `ThreadDetailScreenStore` composer render state
    and intents, but leave voice/audio implementation acceptance to Phase 4.
12. Delete or hollow old `ThreadDetailStore` responsibilities. If the type name
    remains, it must become the screen store and not own data loading,
    normalization, sorting, or request-card joins.

Acceptance criteria:

- Opening a large detail does not publish full sorted event arrays on
  `MainActor`.
- Detail loading can continue while text composer typing and navigation remain
  immediate.
- Event filter changes project off main and publish a bounded visible window.
- Live deltas merge into the event index and coalesce render publication.
- Request cards are attached or dictionary-looked-up before render rows reach
  SwiftUI.
- Thread Detail is not product-accepted until Phase 4 voice/transcription
  acceptance also passes.

Verification:

- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter AppServerClientTests`
- If UI behavior changed: `rtk make app-test SIM='iPhone 17'`

## 7.6 Phase 4 - Composer, voice capture, and transcription hard cut

Goal: ensure voice/audio/transcription cannot block Thread Detail rendering,
composer typing, or other UI gestures.

Files to add or edit:

- `CodexDock/State/ThreadDetailStore+Voice.swift`
- `CodexDock/Voice/VoiceCaptureController.swift`
- `CodexDock/Voice/TranscriptionService.swift`
- `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`
- `CodexDock/Features/Session/SessionDetailView.swift`
- `CodexDock/Features/Session/ComposerView.swift`
- Thread Detail screen-store/engine files from Phase 3
- new `CodexDock/Voice/VoiceCaptureEngine.swift`
- new `CodexDock/Voice/TranscriptionEngine.swift`
- new voice/transcription engine tests

Implementation steps:

1. Define `ComposerRenderState` and `ComposerVoiceRenderState` as small
   `Sendable` values.
2. Build `VoiceCaptureEngine` off main. It owns capture start/stop/cancel and
   audio chunk stream lifecycle.
3. Build `TranscriptionEngine` off main. It owns realtime session start,
   audio append, event observation, commit, cancel, and terminal errors.
4. Replace `Task { @MainActor ... }` audio forwarding with off-main tasks.
5. Publish only tiny voice render updates to `ThreadDetailScreenStore`.
6. Keep draft typing immediate on main. Provisional transcript replacement is a
   tiny draft-state update, not a full Thread Detail projection trigger.
7. Route final transcript/send through `ClientCommandEngine`.
8. Cancel scoped voice/transcription work on navigation teardown.
9. Delete old main-actor voice forwarding and transcription observation paths.

Acceptance criteria:

- Audio append and transcription event loops do not run on `MainActor`.
- Holding/tapping voice controls remains responsive during detail pagination.
- Cancel/finish voice works even while the thread render projector is busy.
- Provisional transcript updates do not trigger full event-list render work.
- Voice errors are bounded render state.
- Phase 3 and Phase 4 together are the only valid Thread Detail/composer/voice
  acceptance checkpoint.

Verification:

- `rtk swift test --filter ThreadDetailStoreTests`
- Focused voice/transcription tests once named
- If installed UI behavior changed: `rtk make app-test SIM='iPhone 17'`

## 7.7 Phase 5 - Archive, Hosts, and Connectivity hard cut

Goal: remove remaining lower-traffic main-actor derivation paths so the whole
client follows one architecture.

Files to add or edit:

- `CodexDock/State/ArchiveStore.swift`
- `CodexDock/State/AppConnectivityStore.swift`
- `CodexDock/State/HostSettingsStore.swift`
- `CodexDock/Features/Hosts/HostsView.swift`
- `CodexDock/Features/Status/**`
- `CodexDock/Features/Dock/DockView.swift` for root-tab store wiring
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift` for runtime factory
  wiring after bootstrap
- `CodexDock/Configuration/RelayBootstrapStore.swift`
- new `CodexDock/Archive/ArchiveDataEngine.swift`
- new `CodexDock/Archive/ArchiveRenderProjector.swift`
- new `CodexDock/Archive/ArchiveScreenStore.swift`
- new `CodexDock/Connectivity/ConnectivityDataEngine.swift`
- new `CodexDock/Connectivity/ConnectivityRenderProjector.swift`
- new `CodexDock/Hosts/HostSettingsDataEngine.swift`
- new `CodexDock/Hosts/HostSettingsScreenStore.swift`
- focused tests for archive, hosts, and connectivity

Implementation steps:

1. Move Archive host loads, metadata overlays, section building, and sorting
   behind archive data/render engines.
2. Make Archive screen store publish render-ready sections only.
3. Wire Archive through `ClientRuntime.makeArchiveScreenStore(...)` in the root
   tab during this phase, not in Phase 6.
4. Move Connectivity record aggregation, bounding, sorting, and overall rollup
   off main.
5. Make Dock, detail, commands, host tests, and relay diagnostics emit route
   facts to `ConnectivityDataEngine`.
6. Move host testing and host configuration persistence behind host settings
   data/command engines.
7. Wire Hosts through `ClientRuntime.makeHostSettingsScreenStore(...)` and
   Connectivity through `ClientRuntime.makeConnectivityScreenStore(...)`.
8. Keep Hosts UI simple but make rows render-ready before main publication.
9. Delete synchronous route where Dock publication forces connectivity
   sorting/rollup.

Acceptance criteria:

- Archive does not map/sort sections on `MainActor`.
- Connectivity rollups do not run synchronously from Dock render publication.
- Host tests and saves do not block Hosts UI or Dock UI.
- Root tabs receive Archive, Hosts, and Connectivity screen stores from
  `ClientRuntime`, not direct old store construction.
- Connectivity and route-health facts still match the existing observability
  contract.

Verification:

- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter AppConnectivityStoreTests`
- Archive/Host focused tests once named
- If relay DTOs changed: `rtk npm run test:relay`

## 7.8 Phase 6 - Residual wiring, deletion, and migration cleanup

Goal: remove any remaining old architecture after each surface has already been
wired through `ClientRuntime` in its own phase.

Files to add or edit:

- app entry/composition files
- `CodexDockApp/CodexDockApp.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/Features/Dock/DockViewPreview.swift`
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
- `CodexDock/Features/Session/SessionDetailView.swift`
- `CodexDock/Features/Archive/ArchiveView.swift`
- `CodexDock/Features/Hosts/HostsView.swift`
- `CodexDockUITests/CodexDockAutomationSmokeTests.swift`
- any files still constructing old stores directly
- `project.yml`
- `Package.swift`
- `README.md` after code behavior changes are real

Implementation steps:

1. Confirm `CodexDockBootstrapView` and `CodexDockRootView` no longer
   construct old broad stores directly for any accepted surface.
2. Confirm each screen receives a screen store or runtime factory from
   `ClientRuntime`.
3. Remove any temporary intra-phase shims left behind by earlier phases.
4. Delete old store/data responsibilities and stale tests.
5. Update docs only after behavior is actually implemented.
6. Run `rtk rg` checks for forbidden patterns:
   - `snapshot.project(options:)` inside `CodexDock/Features`;
   - `Task { @MainActor` in voice/transcription/network/paging code;
   - full event filtering from `SessionDetailView.body`;
   - request-card array scanning in message row rendering;
   - production constants outside `CodexDockConstants.swift`.

Acceptance criteria:

- Runtime has one architecture path.
- Old data-layer work cannot be reached by user-facing screens.
- No fallback flag or compatibility toggle exists.
- Deleted tests are replaced by engine/projector/screen-store contract tests.

Verification:

- `rtk swift test`
- `rtk npm run test:relay` if relay-facing DTOs changed
- `rtk xcodegen generate --spec project.yml`
- `rtk make app SIM='iPhone 17'`

## 7.9 Phase 7 - Responsiveness proof and final acceptance

Goal: prove the client is actually responsive, not just architecturally cleaner.

Implementation steps:

1. Add deterministic large fixtures:
   - 500 Dock rows;
   - multiple hosts;
   - multiple branches;
   - pinned/reordered metadata;
   - search-heavy titles and paths;
   - large Thread Detail with thousands of normalized render events;
   - request cards;
   - voice transcript bursts.
2. Add tests that assert render projectors work off main and screen-store
   publish paths do not invoke projection.
3. Add signpost assertions where practical and manual Instruments checklist
   where automated proof is not realistic.
4. Run simulator UI behavior with active services.
5. Capture logs and document any blocker exactly.

Acceptance criteria:

- Main-thread profiling shows no JSON decode, full-list projection, event
  normalization, file IO, network IO, or audio forwarding in the tested flows.
- SwiftUI Instruments shows no repeated long view-body updates caused by Dock
  or Thread Detail projection.
- Search typing, lens switching, swipe actions, sheet opening, detail
  navigation, composer typing, and voice cancel/finish stay responsive during
  data-layer work.
- The old bad paths are deleted.

Verification:

- `rtk swift test`
- `rtk npm run test:relay` if relay-facing contracts changed
- `rtk make app-test SIM='iPhone 17'`
- `rtk make sim-logs SIM='iPhone 17'`
- Manual Instruments pass with SwiftUI, Time Profiler, Hangs, and Points of
  Interest templates.

## 7.10 Phase dependency order

The implementation order is strict:

1. Phase 0 foundation.
2. Phase 1 Dock Home hard cut.
3. Phase 2 commands and local metadata.
4. Phase 3 Thread Detail core hard cut.
5. Phase 4 composer/voice/transcription hard cut. Phases 3 and 4 are one
   Thread Detail acceptance unit and must be executed back-to-back before the
   Thread Detail surface is called complete.
6. Phase 5 Archive/Hosts/Connectivity hard cut.
7. Phase 6 residual wiring and old-path deletion.
8. Phase 7 responsiveness proof.

If a later phase exposes a missing foundation contract, return to the earliest
phase that owns that contract and update the plan/doc before changing code.

<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Planning verification

- Run ArcStep stage gate status and ready checks against this document.
- Run Composer 2.5 Fast consult after the architecture review portion is
  written.
- Run Composer 2.5 Fast consult again after the phase plan and consistency pass
  are complete.
- Do not run app tests for this document-only planning work unless a later
  command edits production/test code.

## 8.2 Future code verification

Use the smallest relevant command first, as required by this repo:

- Dock/host/metadata changes: `rtk swift test --filter DockStoreTests`, renamed
  or replaced by the future focused engine/store tests.
- Thread detail changes: `rtk swift test --filter ThreadDetailStoreTests`,
  renamed or replaced by future detail engine/store tests.
- JSON-RPC/DTO/client changes: `rtk swift test --filter AppServerClientTests`.
- Relay changes: `rtk npm run test:relay`.
- Installed UI behavior: `rtk make app-test SIM='iPhone 17'`.

## 8.3 Future performance proof

- Use Xcode Instruments SwiftUI template to confirm view body updates are short
  and not frequent due to broad observable dependencies.
- Use Time Profiler and Hangs instruments to confirm Dock streaming, detail
  loading, and search/filter changes do not block the main thread.
- Use signposts for:
  - `dock.model.apply`;
  - `dock.render.project`;
  - `dock.render.coalesce`;
  - `dock.main.publish`;
  - `thread.model.page`;
  - `thread.model.normalize`;
  - `thread.render.project`;
  - `thread.main.publish`;
  - `connectivity.render.project`;
  - `command.intent.to.render`.
- Use MetricKit diagnostics to watch hangs, hitches, CPU exceptions, and app
  launch regressions in installed builds.
- Use large deterministic fixtures: 500 Dock rows, many hosts, many branches,
  pinned metadata, search-heavy titles, and Thread Detail fixtures with
  thousands of events plus request cards.

## 8.4 Future manual acceptance script

On `iPhone 17` simulator after implementation:

1. Start services with `rtk make services`.
2. Build/install with `rtk make app SIM='iPhone 17'`.
3. Open Dock Home with active relay stream.
4. While stream updates are arriving, type in search, clear search, switch
   lenses, swipe a row, open a sheet, and scroll.
5. Open a large Thread Detail.
6. While detail is loading, scroll, type in composer, respond to available
   request cards, and navigate back.
7. Confirm no visible freezes.
8. Capture simulator logs with `rtk make sim-logs SIM='iPhone 17'`.
9. Record Instruments proof for at least Dock burst updates and large Thread
   Detail open.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout posture

Hard cut. No runtime fallback to the old main-actor data-store model.

The future implementation may use a short-lived branch-local migration order,
but the completed code must have one client architecture:

- protocol actors;
- data engines;
- render projectors;
- main-actor render stores;
- SwiftUI views that render prepared state.

## 9.2 Failure behavior

- Transport failure: render stale/offline state, keep UI interactive.
- Sequence gap: engine requests resync, render stale marker, keep UI
  interactive.
- Projection superseded: cancel/drop stale projection, publish latest coherent
  result.
- Persistence failure: show bounded local error and reconcile metadata, keep UI
  interactive.
- Command failure: clear pending state, show row/card/banner error, keep UI
  interactive.
- Detail page failure: keep loaded visible window, mark pagination failure,
  allow retry.

## 9.3 Telemetry posture

Telemetry should prove boundaries, not just log symptoms:

- count model updates received;
- count render projections started/completed/cancelled;
- count coalesced updates dropped;
- measure projection duration off main;
- measure main publish duration;
- measure visible event window size;
- measure render row count;
- measure command intent-to-render latency;
- record sequence gaps and resync duration;
- record stale/offline UI durations.

No telemetry may include `OPENAI_API_KEY`, raw bearer tokens, raw audio, base64
audio, prompt text, transcript text, or full JSON-RPC payloads.

# 10) Decision Log (append-only)

<!-- arch_skill:block:consistency_pass:start -->

## 10.1 Current consistency status

- Decision-complete: yes
- Unresolved decisions: none
- Decision: proceed to implement? yes
- Implementation authorization note: this means the plan is ready for a future
  implementation turn. It does not authorize code implementation in the current
  documentation-only turn.

## 10.2 Consistency pass

- TL;DR, North Star, target architecture, call-site audit, phase plan, and
  verification strategy all use the same hard-cut posture.
- The plan preserves the relay as the normal app endpoint and does not route
  the iPhone directly to raw `:4500` app-server.
- All heavy work owners named in the target architecture are non-main actors or
  pure off-main projectors.
- Every user-facing surface in scope has a screen-store/render-snapshot target:
  Dock, Thread Detail, composer/voice/transcription, Archive, Hosts,
  Connectivity, local metadata, and commands.
- The old bad paths are identified for deletion or responsibility removal.
- Verification commands follow this repo's `rtk`/Makefile-owned workflow.
- No production code implementation is included in this planning document
  update.

## 10.3 Decisions

- 2026-05-30: User objective is the approved North Star. The client must never
  visibly lag because the data layer is busy.
- 2026-05-30: `fallback_policy: forbidden`. The plan is a hard cut; the future
  implementation deletes old laggy UI/data responsibility mixing instead of
  hiding it behind flags.
- 2026-05-30: Preserve the relay as the normal app endpoint on `:4510`. Client
  responsiveness work builds on the relay state engine; it does not make the
  iPhone connect directly to raw `:4500` app-server.
- 2026-05-30: Treat Apple SwiftUI/Instruments responsiveness guidance as the
  external standard for this plan.
- 2026-05-30: No production code implementation is authorized by this document
  creation turn.
- 2026-05-30: First Composer 2.5 Fast architecture consult returned
  `VERDICT: pass-with-notes` with two blocking document gaps: voice/composer
  ownership and screen-store/data-engine lifecycle. Run directory:
  `/tmp/fresh-consult/codex-dock-client-responsive-architecture-20260530T000000Z-jNqVG1`.
- 2026-05-30: Voice/composer ownership is in scope for the hard cut. Audio
  forwarding and transcription observation must move off `MainActor`; only tiny
  composer render state stays main-actor owned.
- 2026-05-30: Screen-store/data-engine lifecycle is standardized: shared
  runtime engines live in a composition root, scoped detail/voice work cancels
  on navigation teardown, and each screen has one coalesced render consumer.
- 2026-05-30: Second Composer 2.5 Fast architecture consult returned
  `VERDICT: pass`, `BLOCKING: none`. Architecture is accepted for ArcStep phase
  planning. Run directory:
  `/tmp/fresh-consult/codex-dock-client-responsive-architecture-r2-20260530T000000Z-iGqWJQ`.
- 2026-05-30: Final Composer 2.5 Fast plan consult returned `VERDICT: pass`,
  `BLOCKING: none`, `CONFIDENCE: high`. The plan is implementation-ready and
  no production code was implemented in this turn. Run directory:
  `/tmp/fresh-consult/codex-dock-client-responsive-plan-r3-20260530T000000Z-UxgQos`.
- 2026-05-30: Phase 0 implementation completed. Added render/runtime
  constants, signposts, `RenderRevision`, `RenderCoalescer`,
  `ConnectivityEventSink`, `ClientRuntime`, and focused tests. Verified with
  `rtk swift test --filter RenderCoalescerTests`,
  `rtk swift test --filter ClientRuntimeTests`,
  `rtk swift test --filter DockStoreTests`, and
  `rtk swift test --filter ThreadDetailStoreTests`.

<!-- arch_skill:block:consistency_pass:end -->
