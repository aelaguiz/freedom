# Codex Dock Data Contract Single Source Implementation Plan - 2026-05-31

## Bottom Line

The intended user experience is simple: Dock and Archive show the work that most
recently happened, newest first. Manual pins may keep a thread visible, but pins
must not invent recency, status, title, summary, freshness, or activity.

The implementation pattern is also simple: one relay projection owns all card
truth. Swift renders `dock/*` and `archive/*` card streams. Every other route,
diagnostic, script, fixture, command, and local cache is explicitly scoped so it
cannot become a second source of Dock or Archive card truth.

Related audit: [Codex Dock Relay Data Contract And Lease Drift Audit](CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md).

## Model Consensus

This plan reflects the requested model-consensus repair pass:

- Model A: `claude-opus-4-8`, effort `max`.
- Model B: `gpt-5.5`, effort `high`.
- First consensus artifact:
  `.arch_skill/model-consensus/codex-dock-single-source-contract-20260531T183258Z/`.
- Zero-side-door convergence artifact:
  `.arch_skill/model-consensus/codex-dock-zero-side-door-pattern-20260531T191645Z/`.

Consensus result:

- The original direction was correct, but the prior plan was not ready.
- A bounded latest-turn scan is not acceptable if it can still present a
  knowingly misordered list as fresh.
- HTTP diagnostics, audit/probe scripts, Thread Detail routes, archive/unarchive
  commands, scripted fixtures, live-only rows, and the unused provenance table
  must all be addressed explicitly.
- No keyword linter, wrapper, or "test-only" exception is a sufficient guard.
  Side doors must be removed, stripped, or structurally unable to prove card
  truth.

## Non-Negotiable Invariants

### User-Facing Ordering

Dock and Archive card order is semantic recency order. Recency means latest
user-visible activity, not raw `thread/list` position and not a stale
thread-level `updatedAt`.

Canonical activity is:

```text
max(thread.updatedAt, thread.createdAt, newest turn timestamp, live event timestamp)
```

`orderKey`, `activityAt`, `activityAtMs`, `displaySummary`, card `status`,
card `freshness`, and card `completeness` are relay-owned card semantics.

### Honest Freshness

Every emitted Dock or Archive card carries relay-computed canonical activity and
a stored proof state for that activity.

A card is `completeness: complete` only when the relay actually inspected an
authoritative source for activity or proved a real upper bound. Valid proof
sources are:

- A newest-turn page or equivalent turn payload.
- A folded live turn event.
- A raw thread value that is proven to be an upper bound for that thread.
- A host-level max-activity watermark that proves unscanned candidates cannot
  outrank emitted candidates.

`thread/list.updatedAt` is not a safe upper bound by itself. The runtime bug
already proved it can be older than `thread/turns/list.startedAt`.

If any emitted ordering set contains an unproven card:

- Stream `complete` must be `false`.
- Host `freshness.status` must not be `fresh`.
- Affected cards must not be `fresh`.
- Affected cards must be `completeness: partial` or `completeness: unknown`.
- Swift must not present the host as a fully fresh newest-first list.

Implementation may scan incrementally or in the background. The contract may not
allow a knowingly misranked card inside a stream labeled fresh.

### One Projection

Raw `thread/list`, raw `thread/read`, raw `thread/turns/list`, live loaded IDs,
live events, session-index IDs, and archive/unarchive command outcomes all fold
through one canonical relay projection.

That projection writes one stored card row per thread and emits only:

- `dock/subscribe`
- `dock/update`
- `dock/resync`
- `archive/subscribe`
- `archive/update`
- `archive/resync`

Swift may format, filter, search, group, count, and render rows. Swift must not
compute card recency, card order, card status, card freshness, card
completeness, card title, or card summary from any other source.

### Local Metadata Scope

Swift local metadata may own:

- Pin state.
- Pin order.
- Labels.
- Rails.
- Local-only grouping or display preferences.

Swift local metadata must not own or cache as card truth:

- Title.
- Status.
- Activity timestamp.
- Summary.
- Freshness.
- Completeness.
- Archive state.

`LocalPinnedDisplaySnapshot` / `lastKnownPinnedDisplay` must stop being a card
data source. A pinned-but-missing thread should render as an explicit missing or
not-loaded placeholder, not as a fabricated old card.

## Root Cause

The current generated contract is shape-safe but source-unsafe.

- Shape-safe: `contract/dock/dock-thread-card.schema.json` generates
  `CodexDock/AppServer/DockThreadCardDTO.swift`.
- Source-unsafe: relay card paths can build cards from `thread/list` and
  `thread/read includeTurns:false`, while the newest work may exist only in
  `thread/turns/list` or live turn events.

That is why a thread can have current work in detail data while Dock still sorts
it as old.

## Canonical Owner

Canonical card truth belongs here:

- Projection/reconcile: `scripts/dock-relay-state-engine.mjs`.
- Projection semantics: `scripts/dock-relay-state-views.mjs`.
- Raw data folding: `scripts/dock-relay-thread-data.mjs`.
- Stored card state: `scripts/dock-relay-state-store.mjs`.
- App-facing shape: `contract/dock/dock-thread-card.schema.json`.
- Swift decoded shape: `CodexDock/AppServer/DockThreadCardDTO.swift`.

The single projection must own the transition from raw facts to card facts. No
route, diagnostic, test, script, fixture, preview, or local metadata path may
produce an alternate Dock or Archive card truth.

## Normative Route Scope

Default rule: if a route is not explicitly marked "May prove Dock/Archive card
truth", it cannot be used in code, tests, scripts, docs, or diagnostics to prove
Dock or Archive ordering, freshness, completeness, title, summary, status, list
membership, or archive membership.

| Route / surface | Plane | App-facing | May prove Dock/Archive card truth | Final disposition |
| --- | --- | --- | --- | --- |
| `dock/subscribe` | Card stream | Yes | Yes | Keep. Primary Dock snapshot stream. |
| `dock/update` | Card stream | Yes | Yes | Keep. Primary Dock delta stream. |
| `dock/resync` | Card stream | Yes | Yes | Keep. Primary Dock resync path. |
| `archive/subscribe` | Card stream | Yes | Yes | Keep. Primary Archive snapshot stream. |
| `archive/update` | Card stream | Yes | Yes | Keep. Primary Archive delta stream. |
| `archive/resync` | Card stream | Yes | Yes | Keep. Primary Archive resync path. |
| `thread/read` | Thread Detail | Yes | No | Keep only for detail after a card is selected from `dock/*` or `archive/*`. Never Dock/Archive proof. |
| `thread/turns/list` | Thread Detail | Yes | No | Keep only for detail after a card is selected. Relay projection may use it internally. Never Dock/Archive proof. |
| `thread/resume` | Thread Detail/live session | Yes | No | Keep only for detail/session workflow after card selection. Never Dock/Archive proof. |
| `thread/archive` | Command | Yes | No | Keep as a command. Its result is a projection input only. No direct card order/freshness writer. |
| `thread/unarchive` | Command | Yes | No | Keep as a command. Its result is a projection input only. No `dockOrderKey(0, threadID)` writer. |
| `turn/start`, `turn/steer`, `turn/interrupt` | Live command | Yes | No | Keep for active detail/session workflow. Fold any card-affecting live events back through projection. |
| `audio/transcription/start`, `audio/transcription/append`, `audio/transcription/commit`, `audio/transcription/cancel` | Voice | Yes | No | Keep as separate voice contract. No card authority. |
| `initialize`, `initialized` | Transport/session | Yes | No | Keep. No card authority. |
| `thread/list` | Internal raw input | No | No | Remove app-facing relay route and Swift wrapper unless a non-card feature explicitly owns it. Internal projection input only. |
| `thread/search` | Internal raw input/probe | No | No | Remove app-facing relay route. No global card/list proof. |
| `thread/goal/get` | Internal raw input/probe | No | No | Remove app-facing relay route unless a future non-card feature owns it explicitly. No card proof. |
| `thread/loaded/list` | Internal live membership input | No | No | Remove app-facing relay route. Internal projection/session-router input only. |
| `relay/state/snapshot` | Oracle | No | No | Delete shipped route and tests. |
| `state/query` | Oracle | No | No | Delete shipped route and tests. |
| `/readyz`, `/statusz`, `/routesz`, `/metricsz` | Process/route health | Yes | No | Keep only as transport/process health. Never display as data freshness. |
| `/debugz/sessions` | Diagnostic | No | No | Keep only non-card process/session counts. Never card proof. |
| `/tracesz/recent`, `/tracesz/*` | Diagnostic | No | No | Keep only if traces exclude card payload truth and prompt/secret content. Never card proof. |
| `/statez` | State/card diagnostic | No | No | Delete or strip card/state payload. It currently exposes full state snapshot. |
| `/syncz` | State/freshness diagnostic | No | No | Strip to process-level sync metadata only. Never card proof. |
| `/subscriptionsz` | Diagnostic | No | No | Keep only subscriber counts/process metadata. Never card proof. |
| `/dbz` | DB diagnostic | No | No | Delete or strip DB/card payloads. Never card proof. |
| `/explainz/thread/{threadID}` | State/card diagnostic | No | No | Delete or strip card explanation. It currently exposes stored card truth. |
| `/selftestz` | Diagnostic bundle | No | No | Strip to process/route health. Never card proof. |
| `/bundlez` | Diagnostic bundle | No | No | Strip to process/route health. Never card proof. |

## Source Disposition

| Source | Current role | Final role |
| --- | --- | --- |
| Raw `thread/list` | Dock/Archive enumeration and stale timestamp source. | Internal relay candidate input only. Never app-facing card proof. |
| Raw `thread/read` | Detail read and Dock enrichment with `includeTurns:false`. | Detail route stays app-facing. Projection uses metadata internally; metadata cannot downgrade proven activity. |
| Raw `thread/turns/list` | Detail and oracle/audit path; Dock does not use it for cards. | Detail route stays app-facing. Projection uses it internally to prove card activity. |
| Raw `thread/search` | Diagnostic/oracle side door. | Remove app-facing relay route. No card-proof tests. |
| Raw `thread/goal/get` | Diagnostic/oracle side door. | Remove app-facing relay route unless a future non-card feature owns it. |
| Raw `thread/loaded/list` | Live membership/status input. | Internal relay input. Live-only IDs must become card candidates. |
| Live turn events | Can update detail without updating Dock. | Fold through projection and schedule card recompute/delta. |
| `$CODEX_HOME/session_index.jsonl` | Can supplement rows with candidate metadata. | ID-only candidate input. Display fields come from projection. |
| `threads` SQLite table | Stored card rows plus read-time live lease overlay. | Single stored card source for stream emission. No read-time card truth overlay after storage. |
| `thread_field_provenance` SQLite table | Exists but unused as enforcement. | Delete it. This plan uses explicit card-row activity proof columns on `threads` instead of a decorative side table. |
| `sync_scopes` SQLite table | Host/scope freshness, not row proof. | Host sync metadata only. It cannot make an unproven emitted ordering set fresh. |
| `live_leases` SQLite table | Read-time status overlay. | Internal projection input. Lease status is folded before storage/emission. |
| `LiveStatusCache` | Independent memory cache feeding session router and live status. | Internal input feeding session routing and projection; no separate card output. |
| `ThreadSummaryCache` | Relay-side summary helper/cache. | Absorb into projection or keep as projection-owned helper only. It cannot publish separate summary truth. |
| Swift local metadata | Pins, labels, rails, cached pinned display. | Pins, labels, rails, pin order only. No title/status/activity/summary fallback. |
| Scripted/previews/fixtures | Fake streams and query-scope fixtures. | Rendering/reducer fixtures only. Never production freshness/order proof. |

## Implementation Plan

### Phase 0: Establish Canonical Projection Inputs And Honest Freshness

Replace the bounded top-N recency plan with an honest projection plan.

Changes:

- Add one canonical card-row fold path in
  `scripts/dock-relay-thread-data.mjs`, for example
  `readCanonicalDockThreadRows(...)`.
- Candidate enumeration must include:
  - raw `thread/list` candidates
  - archived-scope candidates
  - session-index ID candidates
  - live loaded IDs
  - live-only thread IDs that are absent from `thread/list`
  - archive/unarchive command outcomes waiting for confirmation
- For every emitted Dock/Archive ordering set, compute
  `activityAtMs = max(updatedAt, createdAt, newestTurn, liveEvent)`.
- Use `thread/turns/list` or equivalent authoritative turn payloads to prove
  newest turn activity for emitted candidates.
- If proving every candidate synchronously is too expensive, emit explicit
  uncertainty until the proof completes. Do not emit `fresh` for unproven
  ordering.
- Do not treat `thread/list.updatedAt` as an upper bound unless the relay has a
  separate proof that it is one.
- Stop using active Dock list ordinal `dockOrderKey(index, ...)` as semantic
  ordering.
- Use one activity-derived order-key strategy for active Dock and Archive.
- Add explicit stored proof columns on `threads`, such as
  `activity_proof_status`, `activity_proof_source`, and
  `activity_proof_checked_at`.
- Delete the unused `thread_field_provenance` table. Do not leave decorative
  drift-control machinery in the schema.
- Bind stored proof to existing contract fields:
  - proven card activity can be `completeness: complete`
  - unproven card activity is `completeness: partial` or `unknown`
  - any unproven emitted ordering set makes stream `complete=false`
  - any unproven emitted ordering set makes host freshness not `fresh`
- Fix `mergeAuthoritativeThreadRead(...)` so `thread/read includeTurns:false`
  cannot delete, downgrade, or overwrite newer proven turn activity.
- Lift any useful pagination logic from `state-snapshot`, `state-parity`, or
  `probe` into canonical helpers. Do not reuse those oracle scripts as proof
  patterns.

Tests:

- Stale `thread/read.updatedAt`, newer `thread/turns/list.startedAt`: card uses
  the newer turn for `activityAtMs`, `activityAt`, and `orderKey`.
- If an emitted card's activity is unproven, stream `complete=false`, host
  freshness is not `fresh`, and card completeness is not `complete`.
- `listDockCards` and `listArchiveCards` order by canonical activity order.
- `thread/read includeTurns:false` cannot downgrade proven turn activity.
- The old "activity from thread fields only" tests are rewritten.

Gate:

```bash
rtk npm run test:relay
rtk npm run contract:check
```

### Phase 1: Fold Live State Into Projection And Enumerate Live-Only Rows

The stored card row should already contain the live state the client sees.

Changes:

- Remove read-time `applyLeaseToCard` mutation from
  `scripts/dock-relay-state-store.mjs`.
- Fold live status into canonical projection before `upsertThreadCard`.
- Lease acquisition, status change, live loaded-list change, live turn event,
  and lease expiry must schedule recompute and delta publish.
- Live status is status/session proof only. It must not mutate activity, order,
  summary, title, or freshness except through canonical projection proof.
- Enumerate live-only rows as candidates. Do not merely overlay live status onto
  rows already discovered by `thread/list` or session-index supplements.
- Collapse `LiveStatusCache` plus `live_leases` into one input feeding
  `SessionRouter` and card projection.
- Make session-index supplements ID-only.
- Change supplement validation so one bad supplemental candidate fails that
  candidate, not the entire host freshness.

Tests:

- A live-only thread absent from `thread/list` appears through canonical
  projection.
- Expired lease falls back to projected status and never leaves stale
  `running`.
- Lease status changes do not change activity, order, summary, or title unless
  a canonical activity source changes.
- Session-index can contribute an ID, but stale session-index `updatedAt` cannot
  win.
- Supplemental validation failure marks that candidate failed without poisoning
  all host freshness.

Gate:

```bash
rtk npm run test:relay
```

### Phase 2: Make Archive And Unarchive Projection Inputs Only

Archive and unarchive are user commands, not separate card writers.

Changes:

- Keep app-facing `thread/archive` and `thread/unarchive` command routes.
- Remove direct card-order and freshness writes from `applyArchiveMutation`.
- Specifically remove the unarchive path that writes
  `dockOrderKey(0, threadID)`.
- Specifically remove direct `freshness_status = 'stale'` writes as a substitute
  for projection truth.
- Command success should enqueue canonical recompute and publish deltas from the
  same stored projection path as every other card update.
- Until upstream archive state and canonical activity are folded, emitted rows
  must carry uncertain/stale freshness according to the honest-freshness rule.

Tests:

- Unarchive cannot jump a thread to top by ordinal key.
- Archive/unarchive deltas come from canonical projected rows.
- Archive/unarchive does not bypass activity proof or freshness proof.
- Archive and Dock views agree after command confirmation.

Gate:

```bash
rtk npm run test:relay
```

### Phase 3: Tighten The Contract And DTO Semantics

After relay projection owns canonical activity, make the contract carry that
semantics without adding a parallel DTO.

Changes:

- Make `activityAtMs` required in
  `contract/dock/dock-thread-card.schema.json` if implementation has not
  already done so.
- Update the `activityAtMs` description to say it is canonical latest
  user-visible activity, not just thread `updatedAt`.
- Document the existing field semantics:
  - stream `complete=false` means the emitted ordering set is not fully proven
  - host `freshness.status=fresh` is allowed only when emitted ordering is
    proven
  - card `freshness=fresh` is allowed only when that card's activity is proven
  - card `completeness=complete` is allowed only when canonical activity is
    proven
- Regenerate `CodexDock/AppServer/DockThreadCardDTO.swift` using the repo's
  contract generation path.
- Add fixtures under `contract/dock/fixtures/` for:
  - stale thread-level timestamp but newer turn timestamp
  - unproven card activity
  - stale retained host freshness
  - live-only row projection
  - archive/unarchive projection
- Replace keyword-style confidence in
  `scripts/check-dock-thread-card-contract.mjs` with real JSON-Schema fixture
  validation. Shape checks do not prove semantic recency.

Gate:

```bash
rtk npm run contract:check
```

### Phase 4: Make Swift Render-Only For Card Truth

Swift still owns presentation, not semantic card truth.

Changes:

- In `CodexDock/State/DockCardProjection.swift`, remove local
  `lastActivityDate`-first ordering once relay `orderKey` is canonical.
- Sort card rows by relay `orderKey` for body rows and groups.
- Keep local search, filters, grouping, facets, counts, and relative-time
  formatting.
- In `CodexDock/State/ThreadCardRowProjector.swift`, consume required
  `activityAtMs` as the display date source. Remove ISO fallback and
  `.distantPast` card-truth behavior.
- Delete `LocalPinnedDisplaySnapshot` / `lastKnownPinnedDisplay` as a card-data
  source.
- Render pinned-but-missing rows as explicitly not loaded while preserving
  label, rail, and pin order.
- Add first-class stale/uncertain state in `ThreadCardTable.hostStatus(...)`,
  `AppConnectivityStore`, and global status UI.
- `.stale` must not be online-like.
- Remove `thread/list` from app-critical health in
  `CodexDock/Diagnostics/ObservabilityContract.swift` and
  `CodexDock/Features/Status/SystemHealthProjector.swift`.
- Remove `AppServerClient.threadList` and `AppServerMethods.threadList` if no
  legitimate non-card production caller remains.
- Prefer one stream reducer: move Archive and cleanup away from loose collector
  behavior if it duplicates `ThreadCardTable`.

Tests:

- `DockStoreTestsProjection.swift` ordering tests assert Swift preserves relay
  `orderKey`.
- `DockStoreStreamTests.swift` stale tests assert stale host freshness is not
  `.partial` or online-like.
- `AppConnectivityStoreTests.swift` asserts stale is not online-like.
- `DockRenderProjectorTests.swift` cached pinned tests assert degraded
  placeholder, not fabricated card data.
- Add a "client does not recompute card recency" test.
- Remove or rewrite Swift tests that treat `thread/list` as app-critical Dock
  health or card proof.

Gates:

```bash
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

### Phase 5: Delete Or Strip Side Doors

This phase makes drift hard to reintroduce by removing alternate proof paths.

Changes:

- Delete shipped `relay/state/snapshot` route and snapshot-oracle tests.
- Delete shipped `state/query` route and tests.
- Remove app-facing downstream route cases for `thread/list`, `thread/search`,
  `thread/goal/get`, and `thread/loaded/list`.
- Keep internal relay helper functions only where canonical projection uses
  them.
- Delete or strip HTTP diagnostics according to the route-scope table:
  - `/statez`
  - `/syncz`
  - `/dbz`
  - `/explainz/thread/{threadID}`
  - `/debugz/sessions`
  - `/subscriptionsz`
  - `/tracesz/*`
  - `/selftestz`
  - `/bundlez`
- Update `scripts/dock-relay-observability-contract.mjs` and related tests so
  HTTP diagnostics cannot expose card ordering, card contents, card freshness,
  completeness, or stored row truth.
- Do not preserve card/state diagnostic payloads behind test flags, local-only
  gates, or "debug" routes. A gated card-state endpoint is still a side door.
- Rewrite or delete old oracle/probe scripts:
  - `scripts/dock-relay-sync-audit.mjs`
  - `scripts/dock-relay-state-parity.mjs`
  - `scripts/dock-relay-thread-fidelity.mjs`
  - `scripts/dock-relay-probe.mjs`
- Rewrite tests that encode old oracle behavior:
  - `scripts/dock-relay-state-snapshot.test.mjs`
  - `scripts/dock-relay-observability.test.mjs`
  - `scripts/dock-relay-phase5.test.mjs`
  - `scripts/dock-relay-sync-audit.test.mjs`
  - `scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
  - any relay test proving card truth through raw routes or SQLite
- Remove Swift `threadList` tests and real-host smoke tests that treat
  `thread/list` as app proof.
- Replace `ThreadCardFixtureQuery` scope-style tests in
  `CodexDockTests/DockStoreTestSupport.swift` with direct
  `DockThreadCardDTO` stream fixtures that obey production card semantics.
- Keep `thread/read`, `thread/turns/list`, and `thread/resume` tests only for
  Thread Detail after a stream-selected card. They cannot prove Dock/Archive
  ordering, freshness, completeness, summary, or list membership.

Tests:

- Removed routes return unsupported method.
- HTTP card/state diagnostics no longer return card truth.
- Dock/Archive freshness proof uses only `dock/*` and `archive/*` streams.
- No test proves card correctness by reading raw routes, SQLite, HTTP state
  diagnostics, scripted fake streams, or previews.

Gate:

```bash
rtk npm run test:relay
rtk swift test
```

### Phase 6: Structural Proof Harness

The proof harness must make the right path easy and the wrong path unavailable.

Rules:

- Card correctness tests observe cards only through the same `dock/*` and
  `archive/*` stream client the app uses.
- Raw upstream routes, leases, SQLite, and HTTP state are allowed in tests only
  as fake upstream inputs behind the relay.
- Tests may seed raw history, live owner, or session-index fixtures, then assert
  only on emitted card streams.
- Contract checks validate schema shape and fixtures. Semantic recency is
  tested through projection plus card streams.
- Scripted streams, Swift previews, and reducer fixtures are render-only. They
  can never be acceptance proof for freshness, order, or completeness.
- A fixture that emits `fresh` and `complete` without proven canonical activity
  is invalid.

This is structural, not lexical. Do not add a banned-word linter or wrapper as
the guard. Delete or strip the side door, then structure tests so the side door
is not available.

### Phase 7: Document Invariants In Code And Docs

Add comments where future edits are likely to recreate drift.

Required comments:

- `scripts/dock-relay-thread-data.mjs`: canonical fold function comment saying
  this is the only place raw list/read/turn/live/session-index/archive facts
  collapse into Dock card facts.
- `scripts/dock-relay-state-views.mjs`: normalization/order comment saying
  input must already be canonical card facts and must not read raw side-door
  sources.
- `scripts/dock-relay-state-store.mjs`: storage comment saying stored `threads`
  rows are the client card source, activity proof lives with card rows, and live
  lease fields must not be overlaid after storage.
- `scripts/dock-relay-state-store.mjs`: archive/unarchive comment saying
  commands enqueue projection recompute and must not write order/freshness
  directly.
- `contract/dock/dock-thread-card.schema.json`: `activityAtMs`, `freshness`,
  `completeness`, and stream `complete` descriptions carry the honest-freshness
  rule.
- `CodexDock/State/DockCardProjection.swift`: render-only ordering comment
  saying relay `orderKey` is semantic order.
- `CodexDock/State/LocalThreadMetadataStore.swift`: local metadata comment
  saying pins/labels/rails are local, but title/status/activity/summary are not.
- `CodexDock/State/AppConnectivityStore.swift`: freshness comment saying
  transport reachability and Dock data freshness are separate.

Docs:

- Link this plan from
  `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`.
- Update `README.md` so it says relay projection may inspect latest turns and
  live events, but Swift consumes only `dock/*` and `archive/*` card streams for
  card truth.
- Mark the audit drift inventory as resolved only after the corresponding code
  and tests land.

Final gate:

```bash
rtk npm run test:relay
rtk npm run contract:check
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk make app-test SIM='iPhone 17'
```

## Explicit Non-Goals

- Do not make Swift call `thread/turns/list` to repair Dock cards.
- Do not keep `state/query` or `relay/state/snapshot` as test-only proof paths.
- Do not keep `/statez`, `/explainz/thread/*`, or `/dbz` as HTTP card-truth
  diagnostics.
- Do not add a second DTO or parallel card schema to paper over source drift.
- Do not preserve cached pinned display as a safety net.
- Do not rely on keyword linters, route-name greps, or wrappers as the main
  side-door guard.
- Do not leave `thread_field_provenance` in place as decorative drift-control
  machinery.

## Ready-To-Implement Criteria

The plan is ready only when all of the following are true in the plan and then
in code:

- No known misranked card can appear in a stream labeled fresh.
- Only `dock/subscribe`, `dock/update`, `dock/resync`, `archive/subscribe`,
  `archive/update`, and `archive/resync` can prove Dock/Archive card truth.
- Commands, detail routes, voice routes, health endpoints, HTTP diagnostics,
  scripts, fixtures, and previews cannot prove Dock/Archive freshness, ordering,
  completeness, title, summary, status, or membership.
- Archive/unarchive, live status, session-index IDs, turns, reads, and list rows
  all enter through one canonical projection.
- Live-only rows are enumerated as candidates.
- There is no dead provenance mechanism and no direct second writer for card
  order/freshness.
- Tests prove the real card stream path, not an oracle.

## Implementation Status

Implemented in this branch:

- Relay card truth now flows through `scripts/dock-relay-state-engine.mjs`,
  `scripts/dock-relay-thread-data.mjs`,
  `scripts/dock-relay-state-views.mjs`, and
  `scripts/dock-relay-state-store.mjs`.
- The relay canonicalizes card activity from raw list/read/turn/live inputs
  before storage and marks unproven activity as partial or stale.
- Live rows are card candidates; live leases no longer overlay card truth at
  read time.
- Relay integration coverage now proves a live-only thread absent from raw
  `thread/list` still appears through `dock/subscribe` in canonical recency
  order.
- Archive and unarchive commands enqueue projection recompute instead of
  writing card order or freshness directly.
- App-facing raw card side doors were removed: `thread/list`, `thread/search`,
  `thread/goal/get`, `thread/loaded/list`, `relay/state/snapshot`,
  `state/query`, and HTTP card-state diagnostics.
- Swift no longer has a `threadList` wrapper and no longer uses local pinned
  display snapshots as card rows.
- Swift local metadata now decorates relay-delivered rows only.
- `activityAtMs` is required in the schema and generated Swift DTO; Swift no
  longer parses `activityAt` or falls back to `.distantPast` to invent card
  recency.
- Swift Dock body rows and groups sort by relay `orderKey`; manual pinned order
  remains the only local ordering behavior.
- Swift Archive and cleanup views use relay `orderKey` for card recency and
  fall back only to stable identity/title ordering if a malformed row lacks an
  order key.
- Archive and cleanup snapshot collection carries stream freshness/completeness
  into host state instead of treating terminal `complete:false` windows as
  loaded.
- Contract checks now validate every fixture with JSON Schema and include
  partial/unproven, live-only, and archive unarchive fixtures.
- Card tests now assert through `dock/*` and `archive/*` stream fixtures; raw
  route fixtures exist only behind fake upstream app-server inputs.

Current proof commands run during implementation:

```bash
rtk npm run contract:check
git diff --check
node --check scripts/dock-relay-thread-data.mjs
node --check scripts/dock-relay-state-store.mjs
node --check scripts/dock-relay-state-engine.mjs
node --check scripts/dock-relay-sync-audit.mjs
node --check scripts/dock-relay-controlled-simulator-fixture.mjs
node --check scripts/dock-relay-card-contract.test.mjs
node --check scripts/check-dock-thread-card-contract.mjs
rtk npm run test:relay
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter DockStoreStreamTests
rtk swift test --filter ArchiveDataEngineTests
rtk swift test --filter ArchiveCleanupStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockTests/ThreadDetailStoreTests/testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit'
rtk make app-test SIM='iPhone 17'
rtk make services
rtk make app SIM='iPhone 17' FORCE_LAUNCH=1
rtk make sim-config-verify SIM='iPhone 17'
```

Fresh consult:

- Final rerun: `Composer 2.5 Fast` (`agent`, `composer-2.5-fast`) returned
  `VERDICT: pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high` in
  `/tmp/fresh-consult/codex-dock-single-source-implementation-final-rerun-20260531Tkmsh6X`.
- The consult found no reachable production side doors. Its notes were limited
  to render-only Swift fixture indirection, possible live-turn reconcile
  latency, and the large sync-audit harness, which still asserts through
  `dock/subscribe`.

One full `rtk make app-test SIM='iPhone 17'` run hit the known timing-sensitive
voice-capture test
`ThreadDetailStoreTests.testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit`.
The exact simulator test passed immediately afterward with `APP_TEST_ONLY`, and
the next full `rtk make app-test SIM='iPhone 17'` run passed.

Final simulator proof: the restarted local service path reported ready for both
raw app-server and Dock relay, `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`
installed and launched the current app build, `rtk make sim-config-verify
SIM='iPhone 17'` passed, and Mobile MCP observed the Dock screen loaded in the
`iPhone 17` simulator with `rows=1155`.
