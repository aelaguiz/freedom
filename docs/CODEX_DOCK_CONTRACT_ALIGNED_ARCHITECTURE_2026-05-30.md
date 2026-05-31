---
title: "Codex Dock DockThreadCard Hard-Cut Architecture Plan"
date: 2026-05-30
status: active
doc_type: phased_refactor
fallback_policy: forbidden
owners:
  - Amir
reviewers:
  - Composer 2.5 Fast
  - plan-audit
related:
  - docs/CODEX_DOCK_CLIENT_ORDER_ROOT_CAUSE_2026-05-30_WORKLOG.md
  - docs/CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30.md
  - .arch_skill/model-consensus/dock-contract-architecture-20260530T205733Z/
---

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:26d04a51dba3cfb733506d16f203056914d5edc7559176cb79e648db1b9906f0",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-30T21:48:22Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:0ee988d9d4c2172041264a6432f4a6fa64ee12184312b5c784e6ab642ba7216e",
      "completed_at": "2026-05-30T21:48:30Z",
      "doc_hash_after": "sha256:c4ade70ae6cb9b9c1ea4a375f6f9252d145988cc465f05ea782f634feea402ec"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T21:48:35Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:c4ade70ae6cb9b9c1ea4a375f6f9252d145988cc465f05ea782f634feea402ec",
      "completed_at": "2026-05-30T21:48:54Z",
      "doc_hash_after": "sha256:e5686a9ab5fa7de75c04bb7653d4ee687d82a7a7f558e71e46c94c1f1cff0f4f"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-30T21:48:58Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:e5686a9ab5fa7de75c04bb7653d4ee687d82a7a7f558e71e46c94c1f1cff0f4f",
      "completed_at": "2026-05-30T21:49:05Z",
      "doc_hash_after": "sha256:009db252a5f21ec5ac52a1347c71d7646a310edebd6f4baf10ffbe0a31623b30"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-30T21:49:08Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:009db252a5f21ec5ac52a1347c71d7646a310edebd6f4baf10ffbe0a31623b30",
      "completed_at": "2026-05-30T21:49:13Z",
      "doc_hash_after": "sha256:9324edff110e9ada72753a04bbf1118c873e53e67c2213b4ce43dc5756563bf5"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-30T21:49:16Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:9324edff110e9ada72753a04bbf1118c873e53e67c2213b4ce43dc5756563bf5",
      "completed_at": "2026-05-30T21:49:20Z",
      "doc_hash_after": "sha256:118f4acefa94f13c335e59d7a6085ecf177ef5868a4e113846d135a646ddbfee"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->


# TL;DR

Codex Dock should hard-cut to one relay-owned `DockThreadCard` contract for
Dock and Archive list rows. Swift should stop rebuilding list semantics from
thread history, message previews, nullable timestamps, or direct `thread/list`
responses.

The relay becomes the only owner of row truth: identity, ordering, activity,
summary, lane/source/status, archive state, and completeness. Swift remains the
owner of presentation, local overlays, search, filters, grouping, pinned order,
navigation, and host connection UI.

This is not a compatibility migration. Old production row contracts, fallback
projection paths, and side-door loaders must be deleted or renamed so they
cannot silently re-enter the Dock or Archive list path.

```
planning_passes:
  mode: auto-plan
  research: done 2026-05-30
  deep_dive_pass_1: done 2026-05-30
  deep_dive_pass_2: done 2026-05-30
  phase_plan: done 2026-05-30
  consistency_pass: done 2026-05-30
  fresh_consult: done 2026-05-30 Composer 2.5 Fast pass-with-notes, no blockers
  plan_audit: done 2026-05-30 ready, no open findings
  implementation: done 2026-05-31 hard cut implemented and verified
```

# 0) Holistic North Star

The north star is a clean product contract:

`relay state -> DockThreadCard stream -> Swift reducer -> Swift presentation`

Anything that decides what a Dock or Archive row is belongs before the stream
boundary. Anything that decides how that already-defined row is displayed,
searched, grouped, pinned, filtered, or navigated belongs after the stream
boundary.

The hard cut is successful only when these statements are true:

- The app's Dock list consumes `DockThreadCard`, not raw thread history and not
  `SessionSummary`.
- The app's Archive list consumes the same card family, not direct
  `thread/list` pages.
- The relay emits one canonical order key for rows, and Swift preserves that
  order except for explicit local pinned ordering.
- The relay emits one canonical human-visible summary, and Swift displays that
  summary without trying to infer a better one from events.
- Schema drift fails loudly in tests and at runtime. There is no runtime shim
  that accepts old row shapes.
- Local overlays such as pins, labels, host selections, filters, and search are
  preserved, but they attach to canonical card identity instead of inventing
  row truth.

User-facing behavior that must not regress:

- Dock shows real live sessions, newest meaningful activity first.
- Archive shows archived sessions and supports restore.
- Hosts still show online, offline, and connection failure states.
- Host-specific saved configs remain endpoint lists only; phone configs do not
  persist relay instance IDs or raw app-server secrets.
- Search, status filters, host filters, branch/repository filters, source
  filters, grouping, pins, reorder, local labels, request cards, thread detail,
  composer behavior, and voice transcript handling keep their existing product
  behavior unless this plan names a deliberate UI change.
- Existing relay stream mechanics remain: snapshots, deltas, sequence numbers,
  bounded windows, resync, catch-up, coalesced rendering, and lazy detail.

Out of scope:

- Redesigning the visible Dock UI.
- Mirroring full thread history into Swift.
- Moving search/filter/group logic to the relay in this cut.
- Adding OpenAI keys, raw app-server bearer tokens, prompt text, transcript
  text, base64 audio, raw audio bytes, or full JSON-RPC payloads to app logs.
- Creating a second architecture source of truth beside this document.

# 1) Priorities, Constraints, Principles, and Tradeoffs

The priority order is:

1. Preserve user-facing workflows.
2. Remove contract drift permanently.
3. Keep relay stream performance characteristics.
4. Keep Swift state simple enough to reason about.
5. Delete old list semantics instead of hiding them behind adapters.

Hard constraints from this repo:

- `README.md` is orientation, but `Makefile`, `project.yml`,
  `Package.swift`, `package.json`, and code are runnable truth when docs
  disagree.
- App, simulator, and physical-device workflows are Makefile-owned.
- `project.yml` is the XcodeGen source of truth for generated project wiring.
- Services normally run through `rtk make services`.
- Phone path uses the Dock relay on `:4510`, not raw authenticated app-server
  `:4500`.
- Saved physical-device configs must contain only host/port endpoint values.
- `.env` is user-owned and must not be overwritten.

Architecture principles:

- Name the contract after the product object: `DockThreadCard`.
- Treat `DockRowViewModel` as presentation only.
- Treat `SessionSummary` as legacy for Dock/Archive production list rows after
  this cut.
- Generate DTOs from one schema and check generated code into the repo.
- Validate relay emission against the same schema in tests.
- Separate user-facing wire version, relay SQLite schema version, and diagnostic
  snapshot version.
- Keep local overlays local, but make their keys match canonical identity.
- Prefer deletion over deprecation when removing old production paths.

Tradeoffs accepted:

- This is a coordinated app-plus-relay cut. Mixed old/new runtime compatibility
  is intentionally not supported.
- Tests and fixture rewrites are broad because the contract is intentionally
  broad.
- The relay owns more semantic work, but that is the correct boundary because
  only the relay can consistently normalize raw app-server data, cache state,
  archive state, LLM-generated labels, host identity, and stream ordering.
- Swift loses some defensive inference power, but gains deterministic behavior
  and a smaller state model.

Tradeoffs rejected:

- Do not keep `messageSummary` and `messageUpdatedAt` as parallel row truth.
- Do not keep `dock_order` as a database-only concept that differs from the
  wire order contract.
- Do not keep direct `thread/list` Archive loading as a fallback.
- Do not keep a Swift mapper that silently reconstructs Dock cards from raw
  thread events.
- Do not put `relayInstanceID` or `CODEX_DOCK_RELAY_INSTANCE_ID` into phone
  saved configs.

# 2) Problem Statement

The current Dock list has multiple sources of truth:

- The relay orders rows with `dock_order` and raw app-server source order.
- Relay wire rows expose `updatedAt`, `summary`, `messageSummary`, and
  `messageUpdatedAt`.
- Swift re-sorts decoded rows by nullable `messageUpdatedAt`.
- Swift maps stream rows back into `SessionSummary`.
- Archive still loads direct `thread/list` pages through `AppServerDockClient`
  and maps those through `SessionSummary`.
- Tests, previews, scripted streams, and parity tools still assert old message
  preview fields.

That makes the user-visible list contract easy to drift. A relay fix can be
undone by Swift sorting. A Swift display fix can be bypassed by Archive's
direct loader. A test can pass because it exercised a scripted row, not the
real relay-emitted card. A future LLM label feature can add a new field without
one owner for how it becomes a user-facing row.

The desired contract is one product object:

```
DockThreadCard
```

That card must answer the product questions directly:

- Which logical host owns this row?
- Which backend session and thread does this row open?
- What is the one stable order key?
- What activity time should be displayed?
- What title and summary should the user see?
- What status, source, lane, repository, branch, archive state, freshness, and
  completeness should the row show?

Swift should not need to know how the relay got those answers.

# 3) Research Grounding and Architecture Discovery

<!-- arch_skill:block:research_grounding:start -->

## Internal Ground Truth

The current repo confirms the split-brain contract.

`CodexDock/AppServer/DockStreamDTO.swift`

- `DockStreamHostDTO` exposes host id, display name, and endpoint.
- `DockStreamSessionDTO` exposes row fields such as `updatedAt`, `summary`,
  `messageSummary`, `messageUpdatedAt`, `source`, `status`, `branch`,
  `repository`, and `workingDirectory`.
- `DockStreamUpdateDTO` already has the correct envelope family:
  `kind`, `schemaVersion`, `view`, `complete`, `totalRows`, `window`,
  `stateGeneration`, `epoch`, `baseSeq`, `seq`, `upsertSessions`, and
  `deleteSessionIDs`.

`CodexDock/State/DockSessionTable.swift`

- `HostStreamState` stores sessions by id.
- Snapshots and deltas already preserve stream mechanics.
- The root drift is in the final projection: `sortedSessions(for:)` sorts by
  nullable `messageUpdatedAt` and falls back to id.
- Schema and window contract checks already exist and should remain.

`scripts/dock-relay-state-views.mjs`

- `orderedDockRows` creates a relay-side row order, but the wire payload does
  not carry a stable opaque `orderKey`.
- `normalizeThread` and `normalizeStoredSession` emit old row fields:
  `updatedAt`, `summary`, `messageSummary`, and `messageUpdatedAt`.
- `buildWindow` already owns bounded windows and should be kept.
- Bounded text helpers already exist and should remain the defensive text
  boundary for titles and summaries.

`scripts/dock-relay-state-store.mjs`

- SQLite stores `message_summary`, `message_updated_at_ms`, and `dock_order`.
- Dock list queries order by `dock_order ASC, updated_at_ms DESC, thread_id ASC`.
- Archive list queries order by `updated_at_ms DESC, thread_id ASC`.
- Reconciliation writes `dockOrder: index`, making ordering relay-visible but
  not wire-contract-visible.
- Archive mutation already updates relay state and publishes a Dock delta.

`scripts/dock-relay-state-engine.mjs`

- `reconcileDock`, `snapshotDock`, `subscribeDock`, `resyncDock`,
  catch-up, and `makeDockWindowDelta` are the right stream mechanics.
- `snapshotArchive` exists, which means the relay already has an Archive state
  view to promote into the same card family.
- `makeSnapshot` hardcodes `schemaVersion: 1`.
- Archive mutation currently publishes Dock changes only; the Archive stream
  must receive matching card updates/deletes after this cut.

`scripts/dock-relay-state-subscriptions.mjs`

- Sequence fields hardcode `schemaVersion: 1`.
- `dockDelta` emits old `upsertSessions` row shapes.
- Size guards and sequence handling should be kept.

`CodexDock/Dock/DockRenderProjector.swift`

- The stream row is converted back into `SessionSummary`.
- The projection reads `messageSummary` and `messageUpdatedAt`.
- Status and origin are re-derived from stream fields.

`CodexDock/State/SessionRowProjector.swift`

- `SessionSummary` becomes `DockRowViewModel`.
- `activityMode` chooses between `.dockMessage` and `.raw`.
- `rowSummary` creates fallback strings such as `No message preview`.
- Status is derived again from `SessionStatus`.

`CodexDock/State/DockSessionProjection.swift`

- Search, filters, grouping, and pinned ordering are client-side behavior.
- This file should keep owning local presentation projection, but consume
  canonical fields from `DockThreadCard` rows instead of legacy inferred fields.

`CodexDock/State/AppServerDockClient.swift`

- `loadSessions` calls raw `thread/list` pages.
- It maps app-server responses with `SessionSummaryMapper.map`.
- This is a legacy side door for production Dock/Archive list rows after the
  hard cut.

`CodexDock/State/ArchiveStore.swift` and
`CodexDock/Archive/ArchiveDataEngine.swift`

- Archive still defaults to `AppServerDockClient`.
- Archive loads direct pages through `DockSessionLoading`.
- Archive uses `SessionSummary` projection rather than the relay card stream.

`CodexDock/Configuration/DockHostConfiguration.swift` and
`CodexDock/Configuration/HostRegistry.swift`

- Host identity is currently endpoint-derived.
- Saved configs should remain host/port lists, but card identity needs a relay
  logical host id that does not create phone-side relay-instance persistence.

`CodexDock/State/LocalThreadMetadataStore.swift`

- Local metadata is keyed by host id, backend session id, and thread id.
- Pinned display snapshots persist title, subtitle, detail, and last activity.
- This store needs a one-time migration to canonical logical host ids without
  losing pins, labels, local archive overlays, or pinned ordering.

`CodexDockTests/**`, `scripts/*.test.mjs`, previews, and scripted clients

- Test fixtures still create and assert `messageSummary`,
  `messageUpdatedAt`, and legacy ordering.
- They must be converted to schema-backed `DockThreadCard` fixtures.
- Old message-field assertions should be deleted, not weakened.

The follow-up repo scan also found route health and generated-project surfaces:
`CodexDock/AppServer/AppServerMethods.swift`,
`CodexDock/Diagnostics/ObservabilityContract.swift`,
`scripts/dock-relay-observability-contract.mjs`, observability tests, and
`CodexDock.xcodeproj/project.pbxproj`. These are affected because method names,
route health, and generated Xcode references can otherwise preserve old stream
language after the card cut.

## External Research

No browser research is required for this plan. The contract boundary is
repo-local, and the runnable sources above are authoritative. The previous
model consensus artifact under `.arch_skill/model-consensus/` is supporting
review evidence, not an external dependency.

## Architecture Facts Carried Forward

- Stream envelope mechanics are working architecture and should be preserved.
- Relay state is already close to the correct owner; the missing piece is a
  named wire card with schema validation and no Swift re-inference.
- Archive already has relay state support and should join the card stream
  family instead of continuing as a direct loader.
- Pinned and local metadata need preservation, but not ownership of row truth.
- LLM labels and future semantic summaries should feed the relay card, not a
  Swift fallback mapper.

## Decision Gaps

There are no user-blocking product questions left open. The plan deliberately
chooses exact names, exact ownership, exact deletion policy, and exact affected
locations so implementation can proceed without asking for architectural
direction.

<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture

<!-- arch_skill:block:current_architecture:start -->

## Current Data Flow

Current Dock data flow:

1. Raw app-server thread state is read by the relay.
2. Relay reconciliation produces cached rows and old wire DTOs.
3. Swift decodes `DockStreamSessionDTO`.
4. `DockSessionTable` stores rows by session id.
5. `DockSessionTable.sortedSessions(for:)` sorts by `messageUpdatedAt`.
6. `DockRenderProjector` maps stream rows back into `SessionSummary`.
7. `SessionRowProjector` maps `SessionSummary` into `DockRowViewModel`.
8. `DockSessionProjection` applies local search, filters, grouping, and pinned
   ordering.

Current Archive data flow:

1. `ArchiveStore` defaults to `AppServerDockClient`.
2. `ArchiveDataEngine` calls `loadSessions(... .archivedHuman)`.
3. `AppServerDockClient` calls raw `thread/list`.
4. `SessionSummaryMapper` maps raw thread rows into `SessionSummary`.
5. `ArchiveSessionProjector` maps `SessionSummary` into archive row view
   models.

Current local overlay flow:

1. `LocalThreadMetadataStore` stores local thread metadata under an endpoint
   style host id plus backend session id and thread id.
2. Pinned row snapshots store display strings and last activity so hidden rows
   can still show pinned placeholders.
3. `PinnedMetadataOrdering` owns local pinned order.

Current test flow:

1. Swift tests construct `DockStreamSessionDTO` or `SessionSummary` fixtures.
2. Relay tests assert old row fields and ordering behavior.
3. Parity tools compare active order with raw app-server order and stream
   output, but not a single schema-backed card contract.

## Current Failure Modes

- Relay order can be overwritten by Swift sorting.
- Relay summary selection can be overwritten by Swift event inference.
- Archive can behave differently from Dock because it uses direct loading.
- Schema version `1` covers too many meanings and is easy to drift.
- Test fixtures can pass without proving real relay emission.
- Future LLM label work can add another partial source of row truth.
- Endpoint-derived host identity can collide with the desired logical-host
  product identity.

## Current Code That Should Be Preserved

Preserve these mechanics while changing the card payload:

- Relay snapshot, delta, catch-up, sequence, and window mechanics.
- Relay state cache and bounded text helpers.
- Swift stream reducer shape and stream contract checks.
- `RenderCoalescer` behavior.
- Lazy thread detail loading.
- Local search/filter/group UX.
- Local pinned ordering.
- Archive restore command behavior.
- Host connectivity and offline/error UI.
- Existing logging secrecy rules.

## Current Code That Should Not Survive As Production Row Truth

Delete or rename these as production Dock/Archive list semantics:

- `DockStreamSessionDTO` as the row contract.
- `messageSummary` and `messageUpdatedAt` as Dock wire fields.
- `dock_order` as an internal-only order that is not surfaced as `orderKey`.
- `SessionSummaryMapper` on the Dock/Archive production list path.
- `AppServerDockClient.loadSessions` as a production Dock/Archive loader.
- `ArchiveDataEngine` direct `DockSessionLoading` dependency.
- `ArchiveSessionProjector` raw `SessionSummary` projection.
- Any test helper that keeps old message fields alive by default.

<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture

<!-- arch_skill:block:target_architecture:start -->

## Canonical Product Contract

The canonical row object is:

```
DockThreadCard
```

The canonical stream family is:

```
ThreadCardStreamUpdate
```

The stream family supports these views:

```
dock
archive
```

The relay emits cards. Swift consumes cards. No production Swift code rebuilds
cards from raw thread event history.

## Required Card Fields

The exact schema file should own names and types, but the product contract must
cover these fields:

Identity:

- `id`: stable opaque card id scoped enough for list diffing. Relay composes it
  exactly as `logicalHostID::threadID`; `backendSessionID` stays separate card
  data and never enters `DockThreadCardDTO.id`. Swift treats `id` as opaque and
  never rebuilds it.
- `logicalHostID`: stable product host identity supplied by relay status or
  relay-owned host metadata.
- `threadID`: app-server thread id.
- `backendSessionID`: app-server/backend session id if present.
- `hostDisplayName`: display name used by the UI.

Ordering and activity:

- `orderKey`: relay-owned opaque lexicographic key. Swift compares it as a
  string and does not parse it.
- `activityAt`: ISO-8601 timestamp for user display.
- `activityAtMs`: numeric timestamp only if needed for efficient relay storage
  or tests; Swift presentation should not sort by it except where explicitly
  allowed by the schema.

Text:

- `title`: user-visible row title.
- `displaySummary`: user-visible row summary.
- `summarySource`: optional enum describing where the summary came from, such
  as `assistant_message`, `llm_label`, `archive_snapshot`, or `fallback`.

State:

- `status`: canonical status enum.
- `sourceKind`: canonical source enum.
- `lane`: canonical lane enum.
- `archiveState`: canonical archive state enum.
- `freshness`: canonical freshness enum.
- `completeness`: canonical completeness enum.

Context:

- `repository`: optional repository name.
- `workingDirectory`: optional working directory.
- `branch`: optional branch name.
- `appServerBaseURL` or endpoint display metadata only when safe and
  non-secret.

Diagnostics:

- `contractVersion`: card contract version if useful inside the row. The
  envelope `schemaVersion` remains the runtime gate.
- `debugSource` can exist only in diagnostics or test snapshots, not normal UI
  display.

Hard removals from the production wire card:

- `messageSummary`
- `messageUpdatedAt`
- Raw prompt text
- Raw transcript text
- Raw full JSON-RPC payloads
- OpenAI keys or raw app-server bearer tokens
- Phone-side relay instance ids

## Stream Envelope

Keep the existing stream envelope shape because it already models the right
transport behavior:

- `kind`
- `schemaVersion`
- `view`
- `complete`
- `totalRows`
- `window`
- `stateGeneration`
- `epoch`
- `baseSeq`
- `seq`
- `reason`
- `upsertCards`
- `deleteCardIDs`

The old `upsertSessions` and `deleteSessionIDs` names should be replaced in
production code with `upsertCards` and `deleteCardIDs`. Do not keep typealiases
or compatibility branches for old names in app or relay runtime code.

The schema version for this hard cut should move to a new wire version, for
example `2`, and every relay emitter plus Swift decoder must agree on that
single value.

## Schema And Generation

Add one schema source of truth:

```
contract/dock/dock-thread-card.schema.json
```

Add contract support scripts:

```
contract/dock/generate-swift.mjs
contract/dock/validate-emitter.mjs
contract/dock/fixtures/dock-thread-card.snapshot.json
contract/dock/fixtures/archive-thread-card.snapshot.json
```

Generated Swift should land in the existing Swift source tree so `Package.swift`
and `project.yml` do not need new source directories:

```
CodexDock/AppServer/DockThreadCardDTO.swift
```

The generated file should include a clear generated-file header. The generator
and committed generated output must both be checked in.

The existing `CodexDock/AppServer/DockStreamDTO.swift` should either be
replaced by generated card stream DTOs or reduced to envelope-only support. It
must not keep a legacy `DockStreamSessionDTO` production row type.

Add Makefile/package entry points:

```
rtk npm run contract:generate
rtk npm run contract:check
```

The exact `package.json` scripts can call the contract scripts above. The
Makefile can expose matching `rtk make contract-generate` and
`rtk make contract-check` targets if that matches existing command style.

## Relay Ownership

Relay owns:

- `logicalHostID`
- `id`
- `threadID`
- `backendSessionID`
- `orderKey`
- `activityAt`
- `title`
- `displaySummary`
- `status`
- `sourceKind`
- `lane`
- `repository`
- `workingDirectory`
- `branch`
- `archiveState`
- `freshness`
- `completeness`
- Card validation before emission

Relay state store should persist card facts directly:

- Replace `dock_order` with `order_key`.
- Replace `message_summary` with `display_summary`.
- Replace `message_updated_at_ms` with canonical `activity_at_ms` or remove it
  if `updated_at_ms` is already the canonical activity source after migration.
- Add or normalize `logical_host_id`.
- Add columns needed for card status/source/lane/archive state if they are not
  already normalized.

Relay ordering rule:

- Dock rows order by `order_key ASC`.
- Archive rows order by the archive view's card `order_key ASC`.
- The key is opaque outside the relay. If it encodes timestamps or source
  precedence internally, that encoding is not a Swift contract.

Relay text rule:

- `title` and `displaySummary` are bounded, sanitized, and safe for UI display.
- Missing data is represented by explicit freshness/completeness fields, not by
  Swift inventing fallback text.

## Swift Ownership

Swift owns:

- Decoding the card stream.
- Preserving relay order.
- Applying local pinned order on top of relay order only where the UI already
  supports pinned ordering.
- Presenting card fields.
- Searching canonical card text/context fields.
- Filtering canonical card status/source/lane/archive/host/branch/repository
  fields.
- Grouping canonical card fields.
- Local labels, pins, pinned snapshots, and pinned ordering.
- Navigation to thread detail using canonical identity.
- Host settings UI, connection state UI, and offline/error presentation.

Swift does not own:

- Deriving card summaries from raw events.
- Deriving Dock row activity from message events.
- Sorting unpinned rows by nullable message timestamp.
- Loading Archive rows from direct raw `thread/list`.
- Accepting old stream row shapes at runtime.

## Archive Joins The Card Family

Archive should use the same card stream family as Dock.

Add view-specific relay methods or a generic card-stream method. This plan
chooses explicit view methods to minimize UI churn:

```
dock/subscribe
dock/update
dock/resync
archive/subscribe
archive/update
archive/resync
```

Both Dock and Archive payloads use `ThreadCardStreamUpdate`. The `view` field
distinguishes `dock` from `archive`.

Archive restore remains a command, but restore success should be reflected by
card stream updates:

- Restoring from Archive removes or updates the Archive card.
- Restoring to Dock upserts or refreshes the Dock card.
- Archive subscribers receive archive deltas.
- Dock subscribers receive dock deltas.

## Host Identity

Use one canonical logical host id in card identity.

Saved app configs still contain only:

```
hosts: [{ host, port }]
```

Relay identity stays Mac-side in relay status metadata, not phone-side saved
config. Do not persist `relayInstanceID` or
`CODEX_DOCK_RELAY_INSTANCE_ID` into phone app config.

Relay `logicalHostID` source order:

1. `CODEX_DOCK_REAL_HOST_ID` or the equivalent real-host id already exposed in
   relay status metadata.
2. A relay-owned configured host id if the relay has one for that upstream.
3. A normalized endpoint id only as a last-resort bootstrap identity.

The chosen `logicalHostID` must be emitted in host metadata and every card.
Stream host metadata must use `host.id == host.logicalHostID`, and
`logicalHostID` is required. Swift can store and compare logical ids, but must
not infer them from display name, endpoint text, or row title.

The migration should map existing endpoint-derived local metadata keys to
logical host ids once the relay reports enough information to do so. The
migration is allowed because it preserves user data; it is not a runtime
compatibility shim for old row contracts.

## Local Metadata Migration

Pinned state, labels, archive overlays, and pinned display snapshots should be
preserved.

Migration requirements:

- Read existing metadata keyed by endpoint-style host id.
- Resolve a canonical `logicalHostID` for each configured host only after relay
  stream/card metadata proves that logical id.
- Rewrite keys to `logicalHostID + backendSessionID + threadID`.
- Keep pinned order stable.
- Keep local labels stable.
- Keep local archive overlays only if they still represent user intent.
- Keep pinned snapshots useful, but rewrite snapshot activity fields to card
  activity concepts where needed.
- Keep migration idempotent. A local metadata version is optional only if the
  implementation needs one for compatibility.

Do not leave both old and new keys live indefinitely. After migration, old keys
are backup input only during that migration step.

## LLM Labels And Summaries

LLM-created labels or summaries should feed relay card fields before emission.

Swift may show labels and summaries from the card, but it should not call an LLM
or parse raw thread data to repair a card. If a card lacks a label, the relay
should mark the relevant freshness/completeness state so Swift can display a
clear existing UI state.

Schema mapping rule:

- Existing LLM label `title` maps to card `title`.
- Existing LLM label `details` maps to card `displaySummary`.
- `docs/CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30.md` must be updated to
  use the card field names once this contract lands.

## Host Settings Connectivity Test

The host settings "Test connection" flow must survive the deletion of
`DockSessionLoading`.

Replace the production `DockSessionLoading` dependency in
`HostSettingsStore.test()` with a narrow diagnostics protocol:

```
HostConnectionTesting
```

Default implementation:

```
CardStreamHostConnectionTester
```

Behavior:

- Connect and initialize against the configured relay endpoint.
- Request a Dock card stream snapshot with the normal card-stream client.
- Use the snapshot's `totalRows` as the visible row count.
- Close the connection after the test.
- Report offline/error through the existing host settings status UI.

Forbidden behavior:

- Do not call raw `thread/list`.
- Do not return `SessionSummary`.
- Do not expose Dock or Archive rows to host settings.
- Do not keep `DockSessionLoading` alive only for host testing.

## Versioning

Keep three separate versions:

- Wire/card stream schema version: gates Swift decode and relay emission.
- Relay SQLite schema version: gates relay persistence migration.
- Diagnostic snapshot version: gates debug and parity artifacts.

Do not use one version number to stand in for all three.

## Runtime Failure Policy

Runtime failure must be loud and actionable:

- If the relay emits the wrong schema version, Swift rejects that stream and
  shows the existing host error/offline UI.
- If a relay card fails schema validation in tests, tests fail.
- If a card lacks required identity or order fields, the relay must not emit it
  as a normal row.
- If an archive stream cannot subscribe, Archive shows existing loading/error
  UI rather than falling back to direct `thread/list`.

<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit and Affected-Location Checklist

<!-- arch_skill:block:call_site_audit:start -->

This is the exhaustive touch list for implementation planning. Rows marked
`touch` need code or fixture changes. Rows marked `delete-or-rename` must not be
left as old production paths. Rows marked `verify-only` should be read during
implementation but should not change unless the implementation proves they must.

Deep-dive pass 1 rule: a path is listed when it either owns row shape, row
order, row identity, row presentation, Archive list loading, local metadata,
route health, generated project references, or tests/fixtures that can keep the
old contract alive. This intentionally includes tests and docs because a hard
cut can drift through stale fixtures just as easily as stale runtime code.

## Contract And Build Wiring

| Location | Action | Reason |
| --- | --- | --- |
| `contract/dock/dock-thread-card.schema.json` | touch | New source of truth for `DockThreadCard` and stream payloads. |
| `contract/dock/generate-swift.mjs` | touch | Generates Swift DTOs from the schema. |
| `contract/dock/validate-emitter.mjs` | touch | Validates relay cards and fixtures against the schema. |
| `contract/dock/fixtures/*.json` | touch | Golden card fixtures for Dock and Archive. |
| `package.json` | touch | Add `contract:generate`, `contract:check`, and include contract checks in relevant test scripts. |
| `Makefile` | touch | Add contract generation/check targets if consistent with existing command style. |
| `Package.swift` | verify-only | Generated Swift should live under existing `CodexDock/` paths; no new source target should be needed. |
| `project.yml` | verify-only | Generated Swift under `CodexDock/` should be picked up; update only if file wiring or generated build phases change. |
| `CodexDock.xcodeproj/project.pbxproj` | generated-only | Do not edit directly; regenerate through `rtk xcodegen generate --spec project.yml` if source wiring changes. |

## Relay Runtime

| Location | Action | Reason |
| --- | --- | --- |
| `scripts/dock-relay-constants.mjs` | touch | Add wire card schema version and any card-size limits. |
| `scripts/dock-relay-state-views.mjs` | touch | Build `DockThreadCard` objects; emit `orderKey`, `activityAt`, `displaySummary`, and canonical enums. |
| `scripts/dock-relay-state-store.mjs` | touch | Migrate persistence from old row fields to card fields and `order_key`. |
| `scripts/dock-relay-state-engine.mjs` | touch | Emit card snapshots/deltas for Dock and Archive; publish Archive changes. |
| `scripts/dock-relay-state-subscriptions.mjs` | touch | Rename delta payloads to card names and use new schema version. |
| `scripts/dock-relay.mjs` | touch | Register Archive stream methods and ensure JSON-RPC handlers return card streams. |
| `scripts/dock-relay-logger.mjs` | verify-only | Keep structured logging and secret redaction rules. |
| `scripts/dock-relay-thread-summary-cache.mjs` | touch | Feed summaries/labels into relay card fields if it remains the summary source. |
| `scripts/dock-relay-thread-fidelity.mjs` | touch | Update fidelity probes to assert cards, not message fields. |
| `scripts/dock-relay-state-parity.mjs` | touch | Compare relay card order/content, drain catch-up windows like `DockStore`'s subscribe plus `connection.updates()` loop and existing relay catch-up tests, and stop treating raw active order as the app contract. |
| `scripts/dock-relay-json-rpc-client.mjs` | verify-or-touch | Ensure helper clients understand card stream payloads and Archive methods. |
| `scripts/dock-relay-probe.mjs` | verify-or-touch | Ensure probes do not assume old `dock/subscribe` session payloads. |
| `scripts/dock-relay-leak-check.mjs` | verify-or-touch | Ensure leak checks do not pin old route/payload assumptions. |
| `scripts/dock-relay-state-snapshot.mjs` | touch | Version diagnostic snapshots separately from the wire card schema. |
| `scripts/dock-relay-state-ingest.mjs` | verify-or-touch | Ensure ingested state contains enough facts for card construction without duplicating card semantics. |
| `scripts/dock-relay-thread-data.mjs` | verify-or-touch | Ensure raw thread helpers remain upstream data helpers, not card presentation owners. |
| `scripts/dock-relay-live-status-cache.mjs` | verify-or-touch | Feed canonical status into cards without making a second status contract. |
| `scripts/dock-relay-source-filter.mjs` | verify-or-touch | Keep source filtering aligned with canonical `sourceKind` and `lane`. |
| `scripts/dock-relay-observability-contract.mjs` | touch | Add Archive stream routes and keep route health names aligned with Swift. |
| `scripts/dock-relay-observability.mjs` | touch | Keep route health accurate after card and Archive stream methods change. |
| `scripts/dock-relay-status.mjs` | verify-or-touch | Ensure safe status output names card stream health without leaking secrets. |
| `scripts/dock-relay-diagnostics.mjs` | verify-or-touch | Ensure diagnostics use card snapshot version, not wire schema version. |
| `scripts/codex-dock-host-service.mjs` | verify-or-touch | Ensure host service `CODEX_DOCK_REAL_HOST_ID` feeds relay logical host identity without becoming phone config. |
| `scripts/codex-dock-host-service-env.mjs` | verify-or-touch | Ensure generated host env preserves real-host id/name and does not leak secrets. |
| `.codex-dock/**` | do-not-edit | Generated runtime state/logs only; inspect only for command failures. |

## Relay Tests

| Location | Action | Reason |
| --- | --- | --- |
| `scripts/dock-relay.test.mjs` | touch | Replace old message-field assertions with card contract assertions. |
| `scripts/dock-relay-state-snapshot.test.mjs` | touch | Assert `orderKey`, card view names, Archive stream behavior, diagnostic snapshot version, and card-shaped rows. |
| `scripts/dock-relay-state-store.test.mjs` | create-if-absent | Add if no existing relay store test owns SQLite migration and ordering by card fields. |
| `scripts/dock-relay-state-subscriptions.test.mjs` | create-if-absent | Add if no existing subscription test owns schema version and card delta naming. |
| `scripts/dock-relay-state-parity*.mjs` tests | touch | Assert card parity and diagnostic snapshot versioning. |
| `scripts/dock-relay-thread-fidelity.test.mjs` | touch | Assert fidelity checks understand cards and do not rely on legacy message fields. |
| `scripts/dock-relay-observability.test.mjs` | touch | Assert Dock and Archive card stream routes report correct health. |
| `scripts/dock-relay-phase5.test.mjs` | verify-or-touch | Update if it asserts old relay state or stream route behavior. |
| Any relay fixture containing `messageSummary` or `messageUpdatedAt` | delete-or-rename | Old fields must not survive as default fixtures. |

## Swift DTOs And Stream Client

| Location | Action | Reason |
| --- | --- | --- |
| `CodexDock/AppServer/DockStreamDTO.swift` | delete-or-rename | Remove legacy row DTO or reduce to envelope-only if superseded. |
| `CodexDock/AppServer/DockThreadCardDTO.swift` | touch | Generated Swift DTOs for card and stream updates. |
| `CodexDock/AppServer/AppServerMethods.swift` | touch | Add `archive/subscribe`, `archive/update`, and `archive/resync` constants. |
| `CodexDock/State/AppServerDockStreamClient.swift` | touch | Decode `ThreadCardStreamUpdate`, support Dock and Archive views, enforce new schema version. |
| `CodexDock/State/DockSessionTable.swift` | touch | Store cards, preserve `orderKey`, remove `messageUpdatedAt` sort. |
| `CodexDock/Configuration/CodexDockConstants.swift` | touch | Bump stream schema version and centralize any new production constants. |
| `CodexDock/State/ScriptedDockStreamClient.swift` | touch | Replace scripted old session rows with scripted cards. |
| `CodexDock/Diagnostics/ObservabilityContract.swift` | touch | Add Archive stream route configs and keep Dock card routes app-critical. |
| `CodexDock/Diagnostics/ClientObservabilityStore.swift` | verify-or-touch | Ensure route health can represent card schema failures and Archive stream routes. |
| `CodexDock/Diagnostics/RelayDiagnosticsClient.swift` | verify-or-touch | Keep relay diagnostics aligned with card stream route names. |
| `CodexDock/Runtime/ConnectivityEventSink.swift` | verify-or-touch | Ensure card stream failures surface as host connectivity events. |

## Swift Dock UI State

| Location | Action | Reason |
| --- | --- | --- |
| `CodexDock/Dock/DockRenderProjector.swift` | touch | Map cards directly to row view models; stop creating `SessionSummary`. |
| `CodexDock/State/SessionRowProjector.swift` | delete-or-rename | Keep only if renamed to card presentation and no longer accepts `SessionSummary`. |
| `CodexDock/State/DockSessionProjection.swift` | touch | Search/filter/group canonical card fields and preserve pinned behavior. |
| `CodexDock/Dock/DockDataEngine.swift` | touch | Use card state where it currently assumes legacy session rows. |
| `CodexDock/Dock/DockScreenStore.swift` | touch | Keep render coalescing/search debounce intact while projecting card-backed snapshots. |
| `CodexDock/Dock/DockModels.swift` | touch | Replace legacy model types if they encode `SessionSummary` assumptions. |
| `CodexDock/Dock/DockRenderModels.swift` | touch | Ensure row view models are presentation-only and card-backed. |
| `CodexDock/State/DockStore.swift` | touch | Inject card stream client and remove any legacy list-loading assumptions. |
| `CodexDock/Features/Dock/DockView.swift` | touch | Constructor/default dependencies should not instantiate legacy row loaders for Dock. |
| `CodexDock/Features/Dock/DockViewPreview.swift` | touch | Preview rows should be card-backed fixtures. |
| `CodexDock/Features/Dock/DockFilterSurfaceView.swift` | verify-or-touch | Ensure visible filters read canonical card facets. |
| `CodexDock/Features/Dock/DockGroupRows.swift` | verify-or-touch | Ensure grouped rows use card-backed row view models only. |
| `CodexDock/Features/Dock/DockPinnedViews.swift` | verify-or-touch | Ensure pinned UI composes local pin order with relay card identity. |
| `CodexDock/Features/Dock/DockSharedViews.swift` | verify-or-touch | Ensure shared row components do not assume `SessionSummary` wording. |
| `CodexDock/Runtime/ClientRuntime.swift` | touch | Runtime dependency graph should wire card clients, not legacy Dock/Archive loaders. |

## Swift Archive State

| Location | Action | Reason |
| --- | --- | --- |
| `CodexDock/State/ArchiveStore.swift` | touch | Replace direct loader dependency with Archive card stream/snapshot path. |
| `CodexDock/Archive/ArchiveDataEngine.swift` | delete-or-rename | Remove direct `DockSessionLoading` path or turn it into card-stream archive engine. |
| `CodexDock/State/ArchiveSessionProjector.swift` | delete-or-rename | Replace raw `SessionSummary` projection; Archive section/row order must come from card `orderKey`, not client `lastActivityDate` sorting. |
| `CodexDock/Archive/ArchiveScreenStore.swift` | touch | Preserve Archive loading/error/action state while switching row data to cards. |
| `CodexDock/Features/Archive/ArchiveView.swift` | touch | Render card-backed archive rows and restore actions. |
| `CodexDock/Archive/**` | touch | Update archive row models and restore flow to card identity. |
| `CodexDock/State/ClientCommandEngine.swift` | verify-only | Restore/unarchive commands remain commands; verify identity inputs match cards. |

## Swift Legacy Mapping And Direct Loading

| Location | Action | Reason |
| --- | --- | --- |
| `CodexDock/State/AppServerDockClient.swift` | split-or-rename | Delete `DockSessionLoading` and `loadSessions`; keep only the archive/unarchive command surface as a renamed command client, or move that command surface into `ClientCommandEngine`. |
| `CodexDock/Models/SessionSummaryMapper.swift` | delete-or-rename production use | No Dock/Archive production list row should be derived from raw events. |
| `CodexDock/Models/SessionSummary.swift` | touch-or-delete production row use | Keep only if thread detail or diagnostics still need it; otherwise remove from list surfaces. |
| `ThreadMessageSemantics` call sites | verify-only | Thread detail may still need message semantics; list cards should not. |
| `AppServerClientTests` direct loader tests | touch | Move old loader coverage to explicit diagnostics or delete if no longer product behavior. |

## Host Identity And Local Metadata

| Location | Action | Reason |
| --- | --- | --- |
| `CodexDock/Configuration/DockHostConfiguration.swift` | touch | Separate saved endpoint identity from relay logical host identity. |
| `CodexDock/Configuration/HostRegistry.swift` | touch | Track logical host ids without collapsing physical device configs. |
| `CodexDock/Configuration/RelayDiscovery.swift` | verify-or-touch | Preserve relay-discovered identity as metadata, not saved phone config truth. |
| `CodexDock/Configuration/RelayBootstrapStore.swift` | verify-or-touch | Ensure bootstrap config stays endpoint-based and does not persist relay instance ids. |
| `CodexDock/State/LocalThreadMetadataStore.swift` | touch | Migrate metadata keys to logical host identity and card activity concepts. |
| `CodexDock/State/PinnedMetadataOrdering.swift` | touch | Verify pinned ordering composes with relay `orderKey`. |
| `CodexDock/State/HostSettingsStore.swift` | touch | Use `HostConnectionTesting`, not `DockSessionLoading`, for "Test connection"; saved configs remain host/port only. |
| `CodexDock/Hosts/HostSettingsScreenStore.swift` | verify-or-touch | Ensure host testing no longer depends on Dock/Archive list loader semantics. |
| `CodexDock/Metadata/LocalMetadataEngine.swift` | touch | If this owns metadata mutation/versioning, add the logical-host migration here. |
| `CodexDock/State/LocalHostDisplayStore.swift` | verify-only | Display names should not become row truth. |
| `CodexDock/Connectivity/ConnectivityDataEngine.swift` | verify-or-touch | Keep connectivity state keyed consistently after logical host migration. |
| `CodexDock/Connectivity/ConnectivityRenderProjector.swift` | verify-only | Presentation should stay host-health-only unless card route names appear. |
| `CodexDock/Connectivity/ConnectivityRenderModels.swift` | verify-only | Presentation model should not become card truth. |
| `scripts/device-relay-config.mjs` | verify-or-touch | Preserve per-device saved config as host/port values only. |
| `scripts/device-relay-config.test.mjs` | touch | Keep tests proving saved configs reject/purge `relayInstanceID`. |

## Swift Tests

| Location | Action | Reason |
| --- | --- | --- |
| `CodexDockTests/AppServerClientTests.swift` | touch | Decode card stream, reject old schema, verify no message-field contract. |
| `CodexDockTests/DockStoreTests.swift` | touch | Assert relay card order is preserved and pinned order composes correctly. |
| `CodexDockTests/DockStoreStreamTests.swift` | touch | Convert stream snapshot/delta fixtures from sessions to cards. |
| `CodexDockTests/DockStoreScopeTests.swift` | touch | Replace fake `DockSessionLoading` scope tests with card-stream or diagnostics-only tests. |
| `CodexDockTests/DockStoreTestsProjection.swift` | touch | Assert search/filter/group on canonical card fields. |
| `CodexDockTests/DockDataEngineTests.swift` | touch | Update data engine snapshot tests to card-backed state. |
| `CodexDockTests/DockRenderProjectorTests.swift` | touch | Assert card-to-view-model projection directly. |
| `CodexDockTests/DockScreenStoreTests.swift` | verify-or-touch | Preserve screen state/coalescing behavior after card-backed snapshots. |
| `CodexDockTests/ThreadDetailStoreTests.swift` | verify-only | Detail behavior should not regress; update only if identity wiring changes. |
| `CodexDockTests/DockStoreTestSupport.swift` | touch | Replace old session fixture builders with card fixture builders. |
| `CodexDockTests/ArchiveDataEngineTests.swift` | touch | Replace direct loader expectations with Archive card stream expectations. |
| `CodexDockTests/ArchiveScreenStoreTests.swift` | touch | Preserve Archive UI state while changing row source. |
| `CodexDockTests/ThreadListMappingTests.swift` | delete-or-rename | Delete if `SessionSummaryMapper` is removed; otherwise rename to explicit diagnostics mapping tests. |
| `CodexDockTests/ClientRuntimeTests.swift` | touch | Assert runtime wires card stream clients and no production Archive loader. |
| `CodexDockTests/ConnectivityDataEngineTests.swift` | verify-or-touch | Update only if logical host identity affects connectivity keys. |
| `CodexDockTests/HostSettingsScreenStoreTests.swift` | verify-or-touch | Update if host test dependency stops using `DockSessionLoading`. |
| `CodexDockTests/DiagnosticsLoggingTests.swift` | verify-or-touch | Keep route names and secret-redaction expectations accurate. |
| `CodexDockTests/DockConfigurationTests.swift` | touch | Assert endpoint config stays host/port while logical host id is separate. |
| `CodexDockTests/LocalMetadataEngineTests.swift` | touch | Assert one-time metadata migration preserves pins/labels/order. |
| `CodexDockTests/ClientCommandEngineTests.swift` | verify-or-touch | Restore/unarchive command identity should match card identity. |
| Any test fixture containing `messageSummary` or `messageUpdatedAt` | delete-or-rename | Old contract should not survive as test default. |

## Docs And User-Facing Runbooks

| Location | Action | Reason |
| --- | --- | --- |
| `README.md` | touch | Update relay stream contract and Archive path documentation. |
| `AGENTS.md` | touch-after-implementation | Remove stale `SessionSummary` row wording once the code has moved to `DockThreadCard`; keep workflow rules intact. |
| `docs/CODEX_DOCK_CLIENT_ORDER_ROOT_CAUSE_2026-05-30_WORKLOG.md` | touch-or-supersede | Link to this hard-cut plan as the canonical resolution. |
| `docs/CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30.md` | touch | Align LLM `title`/`details` wording with relay-owned card `title`/`displaySummary`. |
| `docs/**` older architecture/worklog files | verify-only | Do not mine broadly; update only direct stale references found during implementation. |

## Do-Not-Touch For This Contract Cut

These should not change unless a test failure proves a direct contract impact:

- Raw OpenAI key handling.
- Realtime transcription provider selection.
- Audio byte handling.
- Request-card response UI.
- Thread detail message rendering.
- Composer text submission behavior.
- Physical-device host/port expectations.
- Service stop/restart behavior.
- `.env`.

## Required Deletion Sweep

Implementation is not complete until `rg` shows no production references to:

```
messageSummary
messageUpdatedAt
DockStreamSessionDTO
DockSessionLoading
ArchiveDataEngine.loadAllHosts
SessionSummaryMapper.map(thread:)
upsertSessions
deleteSessionIDs
dock_order
message_summary
message_updated_at_ms
```

Allowed exceptions must be narrow and named:

- Historical docs.
- Migration code that reads old SQLite columns once and drops or rewrites them.
- Test names that explicitly assert old shapes are rejected.
- Diagnostics that are explicitly not production Dock/Archive row paths.
- A renamed archive/unarchive command client may survive, but it must not expose
  `DockSessionLoading`, `loadSessions`, `SessionSummary`, or row projection.

Deep-dive pass 2 hardening rule: an exception is not allowed just because a
path is "test-only" or "diagnostic." The implementation owner must name what
behavior that exception proves and why it cannot route production Dock or
Archive rows. If that explanation is weak, delete the exception and convert the
path to `DockThreadCard`.

<!-- arch_skill:block:call_site_audit:end -->

# 7) Phase Plan

<!-- arch_skill:block:phase_plan:start -->

## Phase 1 - Contract Spine And Boundary Proof

Goal:

Create the canonical card schema, generated Swift DTO, relay validation, and one
end-to-end Dock stream proof that uses the new card shape.

Phase dependency rule: Phase 1 must establish the schema and generated DTO
before any later phase can update production row projection. Later phases may
not create hand-written substitute DTOs to get around this dependency.

Touch:

- `contract/dock/dock-thread-card.schema.json`
- `contract/dock/generate-swift.mjs`
- `contract/dock/validate-emitter.mjs`
- `contract/dock/fixtures/*.json`
- `package.json`
- `Makefile`
- `CodexDock/AppServer/DockThreadCardDTO.swift`
- `CodexDock/AppServer/DockStreamDTO.swift`
- `CodexDock/AppServer/AppServerMethods.swift`
- `CodexDock/Configuration/CodexDockConstants.swift`
- `CodexDock/Diagnostics/ObservabilityContract.swift`
- `scripts/dock-relay-observability-contract.mjs`
- `scripts/dock-relay-constants.mjs`
- `scripts/dock-relay-state-views.mjs`
- `scripts/dock-relay-state-subscriptions.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay.test.mjs`
- `CodexDockTests/AppServerClientTests.swift`

Implementation notes:

- Define `DockThreadCard` and `ThreadCardStreamUpdate`.
- Bump stream schema version.
- Generate Swift DTOs and check them in.
- Make relay card emission validate against schema in tests.
- Replace `upsertSessions`/`deleteSessionIDs` with
  `upsertCards`/`deleteCardIDs`.
- Remove `messageSummary` and `messageUpdatedAt` from the new card fixture.
- Keep stream envelope semantics intact.
- Add a production-shaped contract gate in relay tests: real `dock/subscribe`
  emits cards with `orderKey`, `activityAt`, and `displaySummary`, and does not
  emit `messageSummary` or `messageUpdatedAt`.
- Add a Swift decode/order gate in `AppServerClientTests`: generated card DTOs
  decode the relay fixture, reject the old schema version, and preserve relay
  `orderKey` order.

Acceptance checks:

```
rtk npm run contract:check
rtk npm run test:relay
rtk swift test --filter AppServerClientTests
```

Exit criteria:

- A real relay Dock snapshot fixture validates as `DockThreadCard`.
- Swift decodes the same fixture.
- Relay and Swift both prove one production-shaped fixture has no legacy message
  fields and preserves `orderKey`.
- Old schema version or old row fields fail tests.
- No production code can decode old `DockStreamSessionDTO` as a normal Dock row.

## Phase 2 - Dock Runtime Cutover

Goal:

Make the visible Dock list card-backed end to end while preserving user-facing
Dock behavior.

Touch:

- `CodexDock/State/AppServerDockStreamClient.swift`
- `CodexDock/State/DockSessionTable.swift`
- `CodexDock/Dock/DockRenderProjector.swift`
- `CodexDock/State/SessionRowProjector.swift`
- `CodexDock/State/DockSessionProjection.swift`
- `CodexDock/Dock/DockDataEngine.swift`
- `CodexDock/Dock/DockScreenStore.swift`
- `CodexDock/Dock/DockModels.swift`
- `CodexDock/Dock/DockRenderModels.swift`
- `CodexDock/State/DockStore.swift`
- `CodexDock/State/ScriptedDockStreamClient.swift`
- `CodexDock/Features/Dock/DockView.swift`
- `CodexDock/Features/Dock/DockViewPreview.swift`
- `CodexDock/Features/Dock/DockFilterSurfaceView.swift`
- `CodexDock/Features/Dock/DockGroupRows.swift`
- `CodexDock/Features/Dock/DockPinnedViews.swift`
- `CodexDock/Features/Dock/DockSharedViews.swift`
- `CodexDockTests/DockStoreTests.swift`
- `CodexDockTests/DockStoreStreamTests.swift`
- `CodexDockTests/DockStoreTestSupport.swift`
- `CodexDockTests/DockStoreTestsProjection.swift`
- `CodexDockTests/DockDataEngineTests.swift`
- `CodexDockTests/DockRenderProjectorTests.swift`

Implementation notes:

- Store cards in the stream table.
- Preserve relay `orderKey` order for unpinned rows.
- Keep pinned rows ordered by local pin ordering on top of relay order.
- Map cards directly to `DockRowViewModel`.
- Rename or delete `SessionRowProjector` so it cannot be mistaken for a
  `SessionSummary` bridge.
- Update search/filter/group logic to canonical card fields.
- Replace scripted and preview old sessions with card fixtures.

Acceptance checks:

```
rtk swift test --filter DockStoreTests
rtk swift test --filter AppServerClientTests
```

Exit criteria:

- Dock rows render from cards without `SessionSummaryMapper`.
- Unpinned order follows relay `orderKey`.
- Pins, filters, grouping, search, labels, host state, and navigation still
  work in tests.
- `messageUpdatedAt` does not decide Dock order anywhere in production Swift.

## Phase 3 - Archive Card Stream Cutover

Goal:

Move Archive to the same card family and delete the direct `thread/list` Archive
loader path.

Touch:

- `scripts/dock-relay.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-store.mjs`
- `scripts/dock-relay-state-subscriptions.mjs`
- `scripts/dock-relay-observability.mjs`
- `scripts/dock-relay-observability-contract.mjs`
- `CodexDock/State/AppServerDockStreamClient.swift`
- `CodexDock/AppServer/AppServerMethods.swift`
- `CodexDock/State/ArchiveStore.swift`
- `CodexDock/Archive/ArchiveDataEngine.swift`
- `CodexDock/Archive/ArchiveScreenStore.swift`
- `CodexDock/State/ArchiveSessionProjector.swift`
- `CodexDock/Features/Archive/ArchiveView.swift`
- `CodexDock/Archive/**`
- `CodexDock/State/ClientCommandEngine.swift`
- `CodexDockTests/ArchiveDataEngineTests.swift`
- `CodexDockTests/ArchiveScreenStoreTests.swift`
- Relay Archive tests, creating them if absent

Implementation notes:

- Add `archive/subscribe`, `archive/update`, and `archive/resync`.
- Use the same `ThreadCardStreamUpdate` payload for Archive.
- Publish Archive deltas when archive state changes.
- Keep restore as a command.
- Make restore reflect in both Archive and Dock streams.
- Delete `DockSessionLoading` from Archive production dependencies.
- Delete client-side Archive ordering by `lastActivityDate`; Archive row and
  section order must follow relay card `orderKey` and explicit card grouping
  fields.

Acceptance checks:

```
rtk npm run test:relay
rtk swift test --filter DockStoreTests
```

Add or update a focused Archive Swift test command if the repo already has a
matching filter by implementation time.

Exit criteria:

- Archive rows render from cards.
- Archive rows and sections preserve relay card order instead of re-sorting by
  client `lastActivityDate`.
- Restore removes or updates Archive cards and refreshes Dock cards.
- Archive no longer calls direct `thread/list` for production row loading.
- Archive does not use `SessionSummary` as row truth.

## Phase 4 - Host Identity And Local Metadata Migration

Goal:

Move local overlays to canonical logical host identity without losing user data.

Touch:

- `CodexDock/Configuration/DockHostConfiguration.swift`
- `CodexDock/Configuration/HostRegistry.swift`
- `CodexDock/Configuration/RelayDiscovery.swift`
- `CodexDock/Configuration/RelayBootstrapStore.swift`
- `CodexDock/State/LocalThreadMetadataStore.swift`
- `CodexDock/State/PinnedMetadataOrdering.swift`
- `CodexDock/State/HostSettingsStore.swift`
- `CodexDock/Hosts/HostSettingsScreenStore.swift`
- `CodexDock/Metadata/LocalMetadataEngine.swift`
- `CodexDock/Connectivity/ConnectivityDataEngine.swift`
- `CodexDock/Runtime/ClientRuntime.swift`
- `scripts/codex-dock-host-service.mjs`
- `scripts/codex-dock-host-service-env.mjs`
- `scripts/device-relay-config.mjs`
- `scripts/device-relay-config.test.mjs`
- `CodexDockTests/LocalMetadataEngineTests.swift`
- `CodexDockTests/DockConfigurationTests.swift`
- `CodexDockTests/HostSettingsScreenStoreTests.swift`
- Host registry tests, creating them if absent

Implementation notes:

- Keep saved phone configs as host/port endpoint lists.
- Resolve relay logical host ids from relay status or card metadata.
- Add a metadata store version for the key migration.
- Rewrite old endpoint-keyed metadata to logical-host-keyed metadata once.
- Preserve pins, labels, pinned order, and pinned display snapshots.
- Delete old-key live lookup after migration completes.
- Replace host settings testing with `HostConnectionTesting`.
- Implement `CardStreamHostConnectionTester` by connecting to the configured
  relay, requesting a Dock card stream snapshot, using `totalRows` for the
  visible row count, and closing the connection.
- Do not use `DockSessionLoading` or raw `thread/list` for host testing.

Acceptance checks:

```
rtk swift test --filter DockStoreTests
rtk swift test --filter AppServerClientTests
```

Exit criteria:

- Existing local pins and labels survive migration.
- New metadata is keyed by logical host id.
- Saved app configs contain only host/port values.
- No phone-side relay instance id is persisted.
- "Test connection" still reports online/offline/error and row count without
  using `DockSessionLoading`.

## Phase 5 - Legacy Deletion And Drift Guard

Goal:

Remove old production paths and add tests that prevent them from returning.

Touch:

- `CodexDock/State/AppServerDockClient.swift`
- `CodexDock/Models/SessionSummaryMapper.swift`
- `CodexDock/Models/SessionSummary.swift`
- `CodexDockTests/AppServerClientTests.swift`
- `CodexDockTests/DockStoreTestSupport.swift`
- `CodexDockTests/ThreadListMappingTests.swift`
- `CodexDockTests/ClientRuntimeTests.swift`
- `scripts/dock-relay.test.mjs`
- `scripts/dock-relay-state-parity.mjs`
- `scripts/dock-relay-thread-fidelity.mjs`
- `scripts/dock-relay-state-snapshot.mjs`
- `scripts/dock-relay-state-snapshot.test.mjs`
- `scripts/dock-relay-json-rpc-client.mjs`
- `scripts/dock-relay-probe.mjs`
- `scripts/dock-relay-leak-check.mjs`
- `README.md`
- `AGENTS.md`
- `docs/CODEX_DOCK_CLIENT_ORDER_ROOT_CAUSE_2026-05-30_WORKLOG.md`
- `docs/CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30.md`

Implementation notes:

- Rename any remaining direct raw app-server client to a diagnostics-only name
  if it must survive.
- Split `AppServerDockClient`: delete list loading and keep only a renamed
  archive/unarchive command client, or move the command implementation into
  `ClientCommandEngine`.
- Delete `DockSessionLoading` as a production protocol.
- Delete `SessionSummaryMapper` from Dock/Archive production use.
- Update LLM label docs so `details` maps to card `displaySummary`.
- Update parity tooling to consume catch-up windows like the real client before
  declaring card order/content parity; use `DockStore`'s subscribe plus
  `connection.updates()` loop and existing relay catch-up test behavior as the
  reference shape.
- Add `rg`-based or test-backed guardrails for old contract names.
- Update docs so this plan remains the canonical source, not a stale side note.

Acceptance checks:

```
rtk npm run contract:check
rtk npm run test:relay
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
```

Exit criteria:

- The deletion sweep has only named exceptions.
- Old field names are not used by production runtime.
- Docs no longer describe direct Archive list loading as the normal path.
- LLM labels feed relay card fields.

## Phase 6 - App-Level Verification

Goal:

Prove the hard cut did not regress the installed app path.

Run the smallest checks first:

```
rtk npm run contract:check
rtk npm run test:relay
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
```

Then run app-level checks when the targeted suites pass:

```
rtk make app SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make sim-config-verify SIM='iPhone 17'
```

Physical-device verification, only when requested or when implementation scope
requires it:

```
rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>
rtk make device-config-verify DEVICE=<device-udid>
```

Exit criteria:

- Simulator Dock connects to relay-backed host path.
- Simulator Dock shows real `DockThreadCard` rows.
- Archive shows real card-backed rows and restore works.
- Offline/error UI still appears when the same relay-backed host path is
  unavailable.
- No raw OpenAI key or raw bearer token is passed to the app.

<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy

Verification starts at the contract and moves outward.

Contract checks:

```
rtk npm run contract:generate
rtk npm run contract:check
```

Relay checks:

```
rtk npm run test:relay
```

Swift checks:

```
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

Generated project and simulator checks:

```
rtk xcodegen generate --spec project.yml
rtk make app SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
```

Service status checks:

```
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make relay-doctor
```

Log checks, only when a failure points there:

```
rtk make sim-logs SIM='iPhone 17'
rtk make dock-relay-logs
```

Required proof before declaring implementation complete:

- Relay validates emitted Dock cards against the schema.
- Relay validates emitted Archive cards against the schema.
- Swift decodes generated card DTOs.
- Swift rejects old schema version.
- Dock order follows `orderKey`.
- Archive no longer calls direct `thread/list`.
- Pins, labels, local grouping, filters, search, and restore are tested.
- `rg` deletion sweep has only documented exceptions.

If a check cannot run because Xcode, simulator, physical device, signing,
services, or env vars are missing, report the exact command skipped and exact
blocker.

# 9) Rollout, Operations, Telemetry, and Ownership

This is a local hard cut, not a staged compatibility rollout.

Rollout rule:

- Relay and app move together in the repo.
- Old stream row shapes are rejected.
- Old production list loaders are deleted or renamed out of the production
  dependency graph.
- Tests become the compatibility boundary, not runtime fallback logic.

Operational expectations:

- `rtk make services` remains the service entrypoint.
- App and phone paths continue connecting to the Dock relay on `:4510`.
- Physical device configs remain separate for Amir's iPhone / iPhone 17 Pro and
  iPhone / iPhone 14.
- Relay logs continue using structured JSON logs through
  `scripts/dock-relay-logger.mjs`.
- Swift diagnostics continue using `DockLog`.
- Secrets and raw payloads remain out of logs.

Telemetry and diagnostics:

- Add card contract version to safe diagnostics.
- Add relay card validation failures to tests, not noisy runtime logs.
- Add concise host-level error state when schema mismatch prevents stream use.
- Keep diagnostic snapshots versioned separately from wire schema.

Ownership:

- Relay owns semantic row truth.
- Swift owns local UI behavior and local overlays.
- Schema owns field names and DTO shape.
- Tests own drift prevention.
- Docs explain the contract but do not override runnable files.

# 10) Decision Log

## Decision 1 - Hard Cut, No Runtime Bridge

Decision:

Use a hard cut to `DockThreadCard`. Do not accept both old and new row shapes in
production runtime.

Why:

The defect class is contract drift. A compatibility bridge would preserve the
same drift paths under new names.

Consequence:

Implementation must update relay, Swift, fixtures, tests, and docs together.

## Decision 2 - Relay Owns Row Semantics

Decision:

Relay owns order, activity, title, summary, status, source, lane, archive state,
freshness, and completeness.

Why:

The relay sees app-server state, archive state, cached summaries, host identity,
and stream ordering in one place.

Consequence:

Swift stops parsing raw events or message summaries to create list semantics.

## Decision 3 - Swift Owns Local UI Projection

Decision:

Search, filters, grouping, pinned order, local labels, and presentation remain
client-side.

Why:

These are responsive local UI behaviors and should not require a relay round
trip.

Consequence:

Swift projection code remains, but consumes canonical fields only.

## Decision 4 - Archive Uses The Same Card Family

Decision:

Archive moves to `ThreadCardStreamUpdate` with `view: archive`.

Why:

Archive is a user-facing thread-card list. Keeping it on direct `thread/list`
would leave a permanent old production row path.

Consequence:

Archive stream methods and tests are required.

## Decision 5 - Generated DTOs From Schema

Decision:

`contract/dock/dock-thread-card.schema.json` is the source of truth for card and
stream DTOs.

Why:

Hand-maintained Swift and Node DTOs are too easy to drift.

Consequence:

Generated Swift must be checked in, and contract checks must fail when generated
output is stale.

## Decision 6 - Logical Host ID Is Card Identity, Not Phone Config

Decision:

Cards use `logicalHostID`, while saved app configs remain host/port endpoint
lists.

Why:

The app needs stable product identity, but phone configs must not persist
relay-instance metadata or secrets.

Consequence:

Local metadata needs a one-time migration.

## Decision 7 - LLM Labels Feed Relay Cards

Decision:

LLM labels and summaries become relay card inputs.

Why:

They are semantic row facts, and the relay is the semantic boundary.

Consequence:

Swift displays them from cards and does not run fallback inference.

<!-- arch_skill:block:consistency_pass:start -->

## Consistency Pass

- Decision-complete: yes
- Unresolved decisions: none
- Decision: proceed to implement? yes

This plan is internally consistent on the key questions:

- One canonical product object: `DockThreadCard`.
- One card stream family: `ThreadCardStreamUpdate`.
- Two views using the same family: `dock` and `archive`.
- One semantic owner: relay.
- One presentation owner: Swift.
- One schema source: `contract/dock/dock-thread-card.schema.json`.
- One migration policy: hard cut, no runtime compatibility bridge.
- One deletion policy: remove old production row paths and guard against their
  return.

Named old concepts are either deleted, migrated once, or restricted to explicit
diagnostics/tests:

- `messageSummary`: deleted from production row contract.
- `messageUpdatedAt`: deleted from production row contract.
- `DockStreamSessionDTO`: deleted or renamed out of production row use.
- `DockSessionLoading`: deleted from production Dock/Archive dependencies.
- `SessionSummaryMapper`: deleted from production Dock/Archive row derivation.
- `dock_order`: migrated to `order_key` and surfaced as wire `orderKey`.
- Direct Archive `thread/list`: deleted as production row path.

No section in this plan requires Swift to infer a Dock or Archive row from raw
thread events after the cut. No section requires the relay to know local pinned
order, local search text, or local UI grouping. That keeps the boundary clean.

<!-- arch_skill:block:consistency_pass:end -->
