The verification sweep closed real gaps in my draft. The most consequential findings that **change or sharpen the plan**:

1. **The legacy direct `thread/list` path (`AppServerDockClient`) is still the production default** — injected into `DockStore`, `ArchiveStore`, `HostSettingsStore`, `ClientRuntime`, `DockView`; its `loadSessions` calls `SessionSummaryMapper.map` for **Archive** and the **host-connectivity test**. So retiring the mapper is *not* purely additive.
2. **Three independent `schemaVersion`s** must not be conflated: wire-stream (the one to bump, literal in 3 places), SQLite-migration `RELAY_STATE_SCHEMA_VERSION`, and diagnostic `STATE_SNAPSHOT_SCHEMA_VERSION`.
3. **Hidden DEBUG consumers that break the build** when the DTO changes: `ScriptedDockStreamClient.swift` and `DockViewPreview.swift` both set `messageSummary`/`messageUpdatedAt`.
4. **No codegen infra exists** (no `Package.swift`; XcodeGen `project.yml` + `Makefile`; relay is hand-rolled `.mjs`) — the schema artifact + generator + Node validator must be **added**, and `swift test` may not even be wired (likely `xcodebuild test`).
5. **`AGENTS.md:217`** already carries the governance rule ("DTO shapes + method names must move together across relay/Swift/tests") — the schema-as-source is its enforcement.
6. **Pinned order is intentionally user-drag-ordered** (`CODEX_DOCK_SWIPE_PINNED_TOP...` status: complete) → confirms pin ordering stays a local overlay, *not* `orderKey`.
7. **The LLM-labels plan collides** (`llmTitle`/`llmDetails` with a parallel Swift fallback) — must be absorbed into the single resolved `displaySummary`.

These force three small architecture refinements (below), but none break the spine — they *strengthen* the single-contract elegance. Here is my finalized Round 2.

---

# Model A — Round 2 Final

## Agreements (locked, from round-1 + this sweep)
Unchanged from my last message — one canonical relay-owned resolved card, relay-owned `orderKey`, required `activityAt` + `displaySummary`, faithful Swift renderer with an ordered reducer, schema-as-source, performance shape preserved verbatim, production-shaped full-lifecycle verification, same retire/rejected lists. GPT and I independently reached all of this.

## Answers to the six questions

1. **Name → `DockThreadCard`** (adopt GPT's). The docs already speak "card"; it names the resolved *product object*, not a transport row. The envelope keeps its current shape/name.
2. **`orderKey` → opaque, relay-owned, lexicographically byte-comparable string**, built internally from `(activityAt_ms DESC, logicalHostID, threadID)`, **sparse** (no dense-rank shifts — GPT's point, which also kills my round-1 "positional churn" risk), **stable** for unchanged rows, **globally comparable across hosts**; the client compares bytes and cannot parse it. A **separate required `activityAt`** carries display recency. Opaque wins drift-proofing; `activityAt` keeps it debuggable.
3. **Schema mechanism → one schema artifact as declared SSOT + two-sided structural enforcement, codegen knob chosen by infra appetite.** Given the sweep confirms *zero* existing codegen infra: the realistic, decisively-not-lint shape is **one version-stamped schema → a checked-in generated (or conformance-locked) Swift Codable struct + a `make schema-verify` "regen is clean" gate → an ajv-style validator the relay runs over `normalizeThread`/`normalizeStoredSession`/`makeSnapshot`/`dockDelta` in `test:relay` → one production-shaped boundary conformance test (real relay output → Swift decode)**. Full bidirectional codegen is the ideal if the team accepts the toolchain; the schema+two-sided-conformance fallback is the pragmatic default on this repo's tooling. Either way drift is a CI failure from one source, not a runtime surprise.
4. **Projection boundary → the line is "derives owned truth" (relay) vs "consumes owned truth" (client), not "logic vs presentation."** Relay derives: identity, `orderKey`, `activityAt`, `displaySummary`, `title`, **final Dock status**, repo/branch, host display, **`sourceKind`/`lane`**. Client consumes + presents: rendering, age-string formatting, and **search/filter/group/lens as pure functions of canonical card fields only**, plus **local overlay** (pin/label/color). Search/filter/group stay client-side — they consume resolved fields, never re-derive them, and moving them server-side would destroy the sacred 80 ms-debounced local responsiveness. This answers GPT's explicit open question.
5. **Checklist shape → five buckets, bucket-1 grouped by subsystem; each entry = `path · locator · action · why · phase`.** Verified-exhaustive version below.
6. **Sign-off → see end.** I can now sign the architecture as the most elegant shape I can conceive for these goals, conditional on three confirmations.

## Three architecture refinements the sweep forced

- **R1 — Archive joins the card family (decided, not deferred).** Because Archive currently rides the legacy `SessionSummaryMapper`/`thread/list` path, and the relay *already* has an archive view (`listArchiveSessions`), the elegant move is: **the relay's archive view also emits `DockThreadCard`** (with its own `orderKey`), and `SessionSummaryMapper`'s message-derivation retires while its **source/origin classification moves relay-side** (relay owns `sourceKind`/`lane`). One card contract across Dock *and* Archive. The **host-connectivity test** keeps a minimal direct probe (it only needs reachability, not a projected card) — so the direct path isn't fully deleted, just demoted to diagnostics.
- **R2 — The LLM-labels feature becomes trivial, not a parallel fallback.** `llmTitle`/`llmDetails` feed the **relay's** resolved `title`/`displaySummary` (relay warms them async and pushes a delta); the client renders the resolved field. No `llmDetails ?? messageSummary ?? summary` chain on the client. The card contract *absorbs* the future feature — a strong elegance signal.
- **R3 — Persisted columns + version coordination are explicit.** Adding `orderKey` (and optionally `activityAt`/`displaySummary`) to the SQLite `threads` table bumps `RELAY_STATE_SCHEMA_VERSION` (migration), *distinct from* the wire `schemaVersion` bump; both move, for different reasons; the diagnostic snapshot version is untouched.

## Verified exhaustive affected-location checklist

### Bucket 1 — Must-touch production code

**A. Relay (Node) — projection authority, ordering, persistence, schema-emit**
- `scripts/dock-relay-state-views.mjs` — `normalizeThread` (242-270) **change**: emit `orderKey`, required `activityAt`, resolved `displaySummary` (latestSummary→preview→title), final status; **retire** `messageSummary`/`messageUpdatedAt` emit (264-265). `normalizeStoredSession` (272-296) **change**: identical canonical fields from SQLite; drop `message_*` (288-291). `orderedDockRows` (211-240) **change**: assign the opaque `orderKey`. `boundedText`/`firstBoundedText`/`buildWindow` (19-35, 315-325) **keep-verbatim** (displaySummary uses the caps).
- `scripts/dock-relay-state-store.mjs` — threads DDL (90-117) **change**: add `order_key` column; **retire** `message_summary`/`message_updated_at_ms` (104-105). `listDockSessions` ORDER BY (340) and `listArchiveSessions` ORDER BY (378) **change** to `order_key`. `upsertThreadSession` binds (515-580) **change**. `applyDockReconciliation` (453-513, `dockOrder=index` 473) **change** to persist `orderKey`; the **incremental diff machinery keep-verbatim**. Index (214-215) **change** to match.
- `scripts/dock-relay-state-engine.mjs` — `makeSnapshot` (429-454, `schemaVersion:1` @440) **change** (version from schema). `reconcileDock` (218-299), `snapshotDock` byte-shrink (337-404), `makeDockWindowDelta` (586-604) **change** payload type; **keep-verbatim** bounding/abort logic.
- `scripts/dock-relay-state-subscriptions.mjs` — `sequenceFields` (17-24, `schemaVersion:1` @19) and `dockDelta` (69-105) **change** (the real wire-version literal + delta builder). Size guards (107-121) **keep-verbatim**.
- `scripts/dock-relay-thread-summary-cache.mjs` — `decorateRows`/`warmOne` (137-153, 221-233) **change**: stop writing `messageSummary`/`messageUpdatedAt`; feed the relay-resolved `displaySummary`.
- `scripts/dock-relay.mjs` — JSON-RPC dispatch (462-495) **verify**: run the emitter-validator before `dock/update` send.
- `scripts/dock-relay-constants.mjs` — `RELAY_STATE_SCHEMA_VERSION` (27) **change** iff persisted columns added; text caps/window size **keep-verbatim**.

**B. Wire contract / schema-as-source (new SSOT)**
- **NEW** `contract/dock/dock-stream.schema.(json|ts)` + generated `…/DockStreamContract.swift` + `…/validate-emitter.mjs` **add** (no such dir exists; upstream `codex-rs/app-server-protocol/schema/…/v2/` is the *reference pattern*, not reusable since the relay is `.mjs`).
- `CodexDock/AppServer/DockStreamDTO.swift` — `DockStreamSessionDTO` (222-275) **change/replace** → generated `DockThreadCard` (add `orderKey`/`activityAt`/`displaySummary`; drop `messageSummary`/`messageUpdatedAt`; demote `updatedAt` from sort role). Status/lane/source/freshness enums (9-220) **change** (generated, string literals fixed by schema). `DockStreamHostDTO.endpoint` (133) **retire** as identity → `logicalHostID`. **Envelope** `DockStreamUpdateDTO` + `DockStreamWindowDTO` (277-352) **keep-verbatim shape** (epoch/seq/baseSeq/window/complete/totalRows), `schemaVersion` sourced from schema.
- `CodexDock/AppServer/AppServerDockStreamClient.swift` (72/98/114) **verify** decode boundary (anchor for the conformance test).
- `CodexDock/AppServer/AppServerMethods.swift` (dock method names 12-14) **verify** consistent with the schema.

**C. Swift DTO→domain (collapse two builders to one card→viewmodel copy)**
- `CodexDock/Dock/DockRenderProjector.swift` — `summary(from:)` (50-67) **change** (primary): copy resolved card fields; stop reading `messageSummary`/`messageUpdatedAt`; `sessionStatus` (69-86) becomes 1:1 pass-through. `snapshot(from:)` (10-36) **change**.
- `CodexDock/Models/SessionSummaryMapper.swift` — `map(thread:)` (48-106) **change/retire**: message-derivation (82-84) and `displayTitle` fallback (318-334) retire; **origin/source classification (108-296) moves relay-side**.
- `CodexDock/Models/SessionSummary.swift` (169-211) **change**: drop `messageActivityDate` (179); add/realign to `orderKey`/`activityAt`/`displaySummary` (or replace with the generated card).
- `CodexDock/Models/ThreadEvent.swift` — `ThreadMessageSemantics.latestMessage/activityDate` (134-140) **change**: remove the **list** consumption only; `ThreadEventDisplayOrder.newestFirst` (143-174) **keep-verbatim** (detail body).

**D. Swift state / projection (collapse all ordering to one `orderKey` comparator)**
- `CodexDock/State/DockSessionTable.swift` — `sessionsByID` dict (24; populate 95-99, 137-142) **change** → ordered reducer keyed by `orderKey` (keep O(1) id lookup alongside). `sortedSessions` (257-270) **retire** the `messageUpdatedAt` sort. `renderInput` (235-251) **change** to carry ordered cards. `acceptsSchemaVersion`/`acceptsStreamContract`/`acceptsWindowContract` (163-222) **keep-verbatim** (version bumps).
- `CodexDock/State/DockSessionProjection.swift` — `rowPrecedesByRecency` (349-360) **retire** → single `orderKey` byte-compare at all **six call sites** (47,55,56,57,108,141). `groupPrecedes` (335-347) + `newestActivityDate` derivations (123,150) **change** to key on canonical `orderKey`/`activityAt`. `searchableValues`/`matchesSearch`/`matchesNonIdleFilters`/`availableFacets` (238-333) **change**: key only on canonical card fields. `pinnedRowPrecedes` (362-382) **change** (minor): tiebreak on stable card id, stop reading retired recency.
- `CodexDock/State/SessionRowProjector.swift` — `activityDisplay`/`activityMode` (3-6,12,110-120) **change**: consume `activityAt`; retire the `.dockMessage`/`.raw` split. `rowSummary` (99-108) **retire** the absent-field fallback → read `displaySummary`. `makeRow` (30-58) **change** → faithful copy. `status/title/repository/rail` helpers (87-173) **change**: status/title/repo become pass-through; `rail` (158-164) **keep** (client display) unless relay owns color.
- `CodexDock/State/ArchiveSessionProjector.swift` — `rowPrecedes`/`sectionPrecedes` (39-55) **change** → `orderKey` (per R1, Archive joins the card family).

**E. Swift view models / views (mostly pass-through verify)**
- `CodexDock/Dock/DockModels.swift` — `DockRowViewModel` (179-243) **change**: add `orderKey`; `lastActivityDate`-as-sort-key replaced; summary/status become copies. `DockSortOrder` enum (60-71) + `DockFilterState.sortOrder` (129) **retire** (vestigial). `DockProjectionGroupViewModel.newestActivityDate` (263) **change**.
- `CodexDock/Features/Dock/DockSharedViews.swift` (180,187), `DockGroupRows.swift` (48-50), `SessionDetailView.swift` (180) **verify** (pure display of resolved fields).
- `CodexDock/State/DockStore.swift` (446-450) **verify** end-to-end order preserved into the screen store.

**F. Local overlay (client-owned)**
- `CodexDock/State/LocalThreadMetadataStore.swift` — `LocalPinnedDisplaySnapshot` (43-109) **change**: store overlay + last-known `orderKey`/`activityAt`; persisted-format migration. `LocalThreadMetadata` pin fields + persist sort (119-120,267-272) **keep-verbatim**.
- `CodexDock/State/SessionRowProjector.swift` `cachedPinnedRow` (60-85) **change** (align to new viewmodel shape).
- `CodexDock/State/PinnedMetadataOrdering.swift` (18-83) **keep-verbatim** (pin overlay ordering; confirmed intentional per SWIPE_PINNED doc).

**G. Identity**
- Endpoint-string host identity → `logicalHostID` wherever host id is keyed (`DockStreamHostDTO.endpoint`, host stores, and the host-alias dedup). **change.**

### Bucket 2 — Must-touch tests / fixtures / verifiers
- `CodexDockTests/DockStoreTestSupport.swift` (257-276, 765-846) **change**: stop populating `messageSummary`/`messageUpdatedAt`; set `orderKey`/`activityAt`/`displaySummary` (production shape).
- `CodexDockTests/DockStoreStreamTests.swift` (order asserts @47…463; windowed-order 294-348) **change**: assert order from `orderKey`; add Swift-order == relay-order; keep `schemaMismatch→resync` (83/194) at new version.
- `CodexDockTests/DockStoreTestsProjection.swift` (lens/idle/pinned order, `makeRow` 408-432) **change**: assert `orderKey` order; pinned tests stay.
- `CodexDockTests/ThreadListMappingTests.swift` — message-derivation cases (101-223) **retire**; source-classification cases (307-420) **verify**/migrate to relay fidelity tests.
- `CodexDockTests/AppServerClientTests.swift` (~315-380) **change**: new card shape; anchor the Swift-side conformance test.
- **NEW** production-shaped boundary conformance test (real relay JSON → generated Swift), both sides.
- `scripts/dock-relay-state-parity.mjs` — **keystone change**: `requestDockSubscribeSnapshot` (2737-2750) must keep the client open and drain `dock/update` catch-up to `complete:true` (post-cutover `dock/subscribe` returns `sessions:[]`, so today it would silently report an **empty** dock). `compareDockCodexOrder`/`sanitizeDockSession` (830-847, 2121-2183) **change** to compare `orderKey` order. Single-window status/order re-derivation findings (2156-2321) **retire**.
- `scripts/dock-relay-state-parity.test.mjs` (1003-1479) **change**: fixtures carry `orderKey`; drop timestamp-movement reclassification.
- `scripts/dock-relay.test.mjs` (894-1033, 1035-1177, 184-199, 421-443) **change** (assert card fields, anchor Node conformance test); window/catch-up tests (301-355) **keep-verbatim** (reference for the harness fix).
- `scripts/dock-relay-state-snapshot.test.mjs` (13-365) **verify** (diagnostic surface; add `orderKey` coverage if exposed).
- `scripts/dock-relay-thread-fidelity.test.mjs` **change/add**: new home for relay-owned source/lane classification coverage migrated off `ThreadListMappingTests`.
- **DEBUG build-breakers (production-adjacent)**: `CodexDock/State/ScriptedDockStreamClient.swift` (380-381,411-412; `.messageNoise` scenario obsolete) and `CodexDock/Features/Dock/DockViewPreview.swift` (63-100) **change** — compiled in DEBUG; break the build when the DTO changes.
- Commands (verify runner): relay `npm run test:relay`; Swift likely `xcodebuild test` (no `Package.swift` — confirm `swift test` wiring).

### Bucket 3 — Docs / runbook
**Change** (state the retired client-ordering/message-fallback model): `README.md` (98-144), `CODEX_DOCK_THREAD_STATES_2026-05-28.md`, `CODEX_DOCK_STATUS_LABELS_2026-05-29.md`, `CODEX_DOCK_RELAY_STATE_ENGINE_ARCHITECTURE_2026-05-30.md`, `CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md`, `CODEX_DOCK_SESSION_SORT_IDLE_FILTER_2026-05-28.md` (implemented), `CODEX_DOCK_ACTIVITY_FIRST_IMPLEMENTATION_ARCHITECTURE_PLAN_2026-05-29.md`, `CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md`, `CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30.md` (complete; call out pinned-exception), `CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS_2026-05-28.md`, `CODEX_DOCK_GOALS_2026-05-29.md` (the order requirement @81-82), `CODEX_DOCK_LLM_THREAD_CARD_LABELS_2026-05-30.md` (collision — fold into R2), `AGENTS.md` (217 governance → name the schema SSOT).
**Change/supersede** (prior root-cause worklogs → point to the card contract): `CODEX_DOCK_CLIENT_ORDER_ROOT_CAUSE_2026-05-30_WORKLOG.md`, `CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`, `CODEX_DOCK_THREAD_SORT_ROOT_CAUSE_2026-05-29_WORKLOG.md`.
**Verify** (pointer likely): `CODEX_DOCK_HOME_REFRESH_NOT_LOADED_ROOT_CAUSE_2026-05-29.md`, `CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29.md`, `CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md` (physical-QA checklist — extend), `CODEX_DOCK_LLM_THREAD_CARD_LABELS_..._WORKLOG.md`.
**New**: the final `DockThreadCard` architecture doc itself.

### Bucket 4 — Optional / upstream-ideal
- `codex/codex-rs/.../v2/thread_data.rs` (seconds), `thread_processor.rs` (3944-3945 `.timestamp()`), `state/src/runtime/threads.rs` (ms allocator) — emit true `updated_at_ms` + stable tiebreak so `orderKey` gains full fidelity. **Not a hard dependency** (relay synthesizes today).

### Bucket 5 — Explicitly NOT to touch (preserve verbatim)
- `CodexDock/Rendering/RenderCoalescer.swift` + `RenderCoalescerTests.swift`; off-main projection wiring; `ResponsivenessContractTests.swift`.
- Lazy detail: `ThreadDetailStore.swift`, `ThreadDetailRenderProjector.swift`, `ThreadEvent` detail pipeline + `ThreadEventDisplayOrder.newestFirst`.
- The bounded windowed **envelope mechanics** (epoch/seq/baseSeq/window/complete/totalRows) and relay **byte/row bounding + incremental diff**.
- `.codex-dock/services/*.plist` — **generated**; edit the `Makefile` host-service generator, never the plist.
- **Split-file flags (do not treat whole file as one bucket):** `DockStreamDTO.swift` (envelope keep / row change), `dock-relay-state-views.mjs` (`boundedText`/`buildWindow` keep / `normalizeThread` change), `dock-relay-state-store.mjs` (diff keep / ORDER BY + columns change), `ThreadEvent.swift` (detail order keep / list derivation change), `CODEX_DOCK_CLIENT_RESPONSIVENESS_ARCHITECTURE_2026-05-30.md` (mechanics keep / DockSessionTable ordering description change).
- **Config that must move in lockstep (not "not-touch", but coordinate):** wire `schemaVersion` literals — `CodexDockConstants.swift:17`, `dock-relay-state-subscriptions.mjs:19`, `dock-relay-state-engine.mjs:440`; plus `Makefile`/`package.json`/`project.yml` gain the schema-gen + validate steps. Keep `RELAY_STATE_SCHEMA_VERSION` and `STATE_SNAPSHOT_SCHEMA_VERSION` distinct.

## Repo evidence deciding the deltas
- **R1 (archive joins cards):** `dock-relay-state-store.mjs:378` already has a `listArchiveSessions` ORDER BY; `AppServerDockClient.loadSessions:133 → SessionSummaryMapper.map` is the only thing keeping Archive on the legacy path — migrating it removes the second projection.
- **D2 (sparse opaque key):** `applyDockReconciliation:472-473` reassigns dense `dock_order=index` every reconcile → churns; a timestamp-derived opaque key is sparse/stable.
- **D4 (filter/group client-side):** 80 ms debounce (`DockScreenStore.swift:101-116`) + `RenderCoalescerTests` make local responsiveness an executable contract; server-side search = a round-trip per keystroke.
- **D3 altitude:** sweep confirms no `Package.swift`, no codegen, XcodeGen+Makefile → full bidirectional codegen has real setup cost; schema + two-sided conformance is the realistic minimum that still makes drift a CI failure.

## Sign-off

**I can now sign off on the architecture itself as the most elegant shape I can conceive for these goals** — the relay resolves one `DockThreadCard` (Dock *and* Archive) carrying an opaque `orderKey`; the client is a faithful renderer that orders by one comparator, arranges client-side on canonical fields only, and owns just the local overlay; one schema is the single source; one harness proves it on production-shaped data. The sweep hardened rather than weakened it, and it absorbs the LLM-labels feature for free.

**Three confirmations remain before I sign the joint "cannot imagine more perfect" line — none are "I can imagine something better," all are "we must finish agreeing":**
1. **GPT confirms D4** (consume-vs-derive boundary; search/filter/group stay client-side on canonical fields).
2. **GPT confirms D2** (opaque sortable `orderKey` + separate `activityAt`; sparse/stable).
3. **One genuine open knob — D3 altitude:** generate-Swift+validate-Node **vs** schema+two-sided-conformance (no codegen). This is the single remaining decision; I recommend the **schema + two-sided conformance** default given zero existing codegen infra, upgrading to full codegen only if the team wants it.

**Smallest remaining correction:** pick the D3 altitude and have GPT confirm D2+D4. With those locked, I'm ready to co-author the final doc — including this checklist as the refactor guide. I have **not** written the doc yet (convergence step), per process.