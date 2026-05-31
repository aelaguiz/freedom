I have decisive verification. Three findings refine the convergence and correct two of Model B's claims. Here is the converged plan.

---

## Verification corrections (both first passes had errors)

- **`reconcileDock` confirmed turn-blind** (`dock-relay-state-engine.mjs:252-288`): it drains `thread/list` (`sortKey:"updated_at"`), enriches via `thread/read includeTurns:false`, and sets `orderKey: dockOrderKey(index, …)` = **list ordinal**. The `sortDirection:"desc"` at `:259/:382` is on the **list**, not turns. Audit confirmed.
- **A turns-desc helper already exists** in the oracle paths (`dock-relay-state-snapshot.mjs:276`, `dock-relay-state-parity.mjs:2849`, `dock-relay-probe.mjs:51`) — so canonical recency can **reuse an existing `thread/turns/list sortDirection:"desc"` pattern**, not invent one.
- **Model B is wrong that `ThreadSummaryCache` is "unused."** It is instantiated in production: `dock-relay-thread-data.mjs:16` imports it, `:84` does `config.threadSummaryCache = new ThreadSummaryCache({…})`. Disposition is **absorb + remove the construction site + its test (`dock-relay.test.mjs:693`)** — not "delete as unused" (that breaks config construction).
- **Model A (my) S11 was too glib.** `AppServerClient.threadList` is **registered app-critical** at `ObservabilityContract.swift:53` and `SystemHealthProjector.swift:92`, with tests at `AppServerClientTests.swift`, `DiagnosticsLoggingTests.swift:47`, `SystemHealthProjectorTests.swift:14`. Deletion must remove those registrations too.
- **`applyLeaseToCard` is a read-time overlay at three sites** (`dock-relay-state-store.mjs:428,563,878`). This makes Model B's "remove the read-time overlay" architecturally correct (below).

---

## 1. Where we agree

- **Canonical owner = the relay Dock projection** (`dock-relay-state-views.mjs` `normalizeThread` + `dock-relay-state-engine.mjs` reconcile), persisted to the `threads` table, emitted via `dock/*`+`archive/*` as `DockThreadCardDTO` per `contract/dock/dock-thread-card.schema.json`. Client is **render-only**.
- **Recency = newest real work**: `activityAtMs = max(updatedAt, createdAt, newest-turn, live-event)`; `activityAt`, `orderKey`, summary all derive from it.
- **Kill the active-Dock ordinal `orderKey`** (`dock-relay-state-views.mjs:182`); share one descending activity key for Dock + Archive.
- **Session-index supplements become ID-only** (`dock-relay-thread-data.mjs:245`); display from `thread/read` + canonical turns.
- **Strip cached pinned display as a card source** (`ThreadCardRowProjector.swift:61`); keep label/rail/pin/order.
- **Reject** schema-only fixes, client turn-polling, keyword linters, and "keep `state/query` for tests."
- Same migration spine: relay truth first → contract tighten → client render-only → delete side doors → docs.

## 2. Disagreements / tightening

- **Lease handling — converge to Model B's stronger form.** My "keep status-only overlay, fix expiry" preserves a second mutation point. Adopt **remove the read-time `applyLeaseToCard` overlay at all three sites** (`store:428,563,878`); fold live status into the projection **before `upsertThreadCard`** so the stored row is the single card truth; lease expiry triggers recompute via the existing `scheduleLiveLeaseExpiryReconciliation`. Add: lease *acquisition/status-change* must also schedule a prompt delta (not only expiry).
- **`thread/list` removal is not a no-op** (correction above): also remove its app-critical health registrations and fix the dependent health tests.
- **`ThreadSummaryCache` is wired** (correction above): absorb, don't "delete as unused."
- **Connectivity HTTP endpoints stay.** `/statusz`, `/routesz`, `/readyz` are legitimate **ops health** (read by `AppConnectivityStore`/diagnostics) — not card side doors. The fix is presentation only: relay `.stale` → Swift first-class `.stale`, `.stale` **not** in `isOnlineLike` (today `AppConnectivityStore.swift:19` includes `.partial`). Keep capability, sever the "health = freshness" conflation.
- **Keep `thread/read`, `thread/turns/list`, `thread/resume` app-facing** — Thread Detail legitimately uses them (`ThreadDetailStore.swift:563`).

## 3. Recency strategy — resolved: **bounded latest-turn scan now; defer the ingestor**

Pick the **latest-turn scan, bounded**, not the full incremental ingestor and not a 961-row full scan.

- **Why not full per-row scan:** evidence shows 961 rows on one host (REPORT:22) → ~961 upstream calls per reconcile. Unacceptable.
- **Why not the incremental turn/live ingestor (b):** it is the most *new* machinery (a live turn-event subscription that does not exist today, CONTRACT:292) **and** has a cold-start correctness gap (only covers threads we're subscribed to). Neither safest nor simplest.
- **Chosen path:** in `reconcileDock`, after draining the list, run a `thread/turns/list` (page-1, `sortDirection:"desc"`) for **only**: (i) live-leased threads, and (ii) the top-N within the publish window (the Dock already bounds to a ~600-row budget, REPORT:24). Feed the newest turn into `normalizeThread`. Reuse the existing turns-desc helper. Cap concurrency + page size via **named constants in `dock-relay-constants.mjs`** (Model B's point).
- **Coverage:** this fixes the exact evidence bug — the active thread (`019e7e7d`) is live-leased, so it is scanned and rises to top. The visible window is turn-accurate.
- **Residual gap, stated honestly:** a thread that is neither live nor in the top window but has newer turns than its list `updatedAt` stays mis-ranked. That is the only case the deferred ingestor would close; we **do not build it now** (overbuild), but document it as the known follow-up.
- **Open risk to verify at implementation:** confirm upstream honors `thread/turns/list sortDirection:"desc"` so page-1 = newest (the snapshot/parity code already relies on it — validate, and if not, drain to first real turn).

## 4. Diagnostic routes — resolved (honoring "no side doors, including tests")

Three tiers, not one rule:

- **Card-truth RPC side doors → DELETE outright, with their tests:** `relay/state/snapshot` (`dock-relay.mjs:483`) and `state/query` (`dock-relay.mjs:511`). Delete the `state/query` test at `dock-relay.test.mjs:1411` and the snapshot-oracle tests — **no test-only retention** (this is exactly the "keep it for tests" pattern the user rejects). My first-pass "demote to test-only helper" is **withdrawn.**
- **Raw thread RPC routes → internalize:** remove client-facing `thread/list`, `thread/search`, `thread/goal/get`, `thread/loaded/list` route cases (`dock-relay.mjs:469+`); keep the internal functions (`aggregateThreadList`, etc.) the relay itself calls. Remove Swift `AppServerClient.threadList:279`, its app-critical registrations (`ObservabilityContract.swift:53`, `SystemHealthProjector.swift:92`), and update/delete dependent tests.
- **HTTP `/…z` ops-health endpoints → KEEP:** they serve connectivity UI, not card truth. No card-data side door; fix only the Swift presentation so they never read as data freshness.

## 5. Cached pinned display — resolved

Both models already agree; final form: **delete `lastKnownPinnedDisplay` as a card-data source** (`LocalThreadMetadataStore` / `ThreadCardRowProjector.swift:61`). A pinned thread with no current relay card renders as an **explicitly-not-loaded placeholder** that still shows the user's own label and remains tappable. Local metadata owns labels/rails/pins/order **only** — never title/status/activity/summary. Relay stays the sole card-field source.

## 6. Final must-have phases + test gates

**Phase 0 — Relay canonical recency (additive, no client change).**
Changes: bounded latest-turn scan in `reconcileDock` (live + top-window, page-1 desc, capped via `dock-relay-constants.mjs`); `normalizeThread` `activityAtMs = max(updatedAt,createdAt,newestTurn,liveEvent)`; add `canonical_activity_at_ms` column to `threads` (`dock-relay-state-store.mjs`); generalize `archiveOrderKey` → one shared activity key, replace `dockOrderKey` ordinal use at `:286`; fix `mergeAuthoritativeThreadRead` (`dock-relay-thread-data.mjs:623`) to take `max` activity and stop deleting turns.
Gates: new relay test — newer turn ⇒ card `activityAtMs`/`orderKey` reflect the turn (reproduces CONTRACT:13-18); `listDockCards` order == canonical-activity order; **rewrite** `dock-relay.test.mjs:1280` (activity from turns, not thread fields).

**Phase 1 — Relay single live source + summary + freshness scoping.**
Changes: remove read-time `applyLeaseToCard` (`store:428,563,878`); fold live status into projection pre-`upsertThreadCard`; lease acquire/expire schedules recompute+delta; unify `LiveStatusCache`+`live_leases` into one source feeding `SessionRouter` and the projection; absorb `ThreadSummaryCache` (remove `thread-data.mjs:84` construction + `dock-relay.test.mjs:693`), keep a pure "latest safe turn summary" helper; session-index supplements ID-only; one supplement rejection fails only that candidate, not whole-host (`reconcileDock` `complete` logic at `:289-296`).
Gates: **rewrite** `dock-relay.test.mjs:292` (expired lease ⇒ projected status, never stale `running`) and `:243` (lease never changes activity/order/summary); add live-only-thread-via-projection, supplement-id-only, and freshness-scoping tests.

**Phase 2 — Contract tighten.**
Changes: make `activityAtMs` **required** (`dock-thread-card.schema.json:231,277`); regenerate `DockThreadCardDTO.swift` via `generate-dock-thread-card-contract.mjs`; add stale + latest-turn fixtures under `contract/dock/fixtures/`; replace keyword forbid-list confidence in `check-dock-thread-card-contract.mjs` with **real JSON-Schema validation**.
Gates: `npm run contract:check` validates fixtures against the full schema; generated DTO matches.

**Phase 3 — Swift render-only.**
Changes: `DockCardProjection.swift` — delete `lastActivityDate`-first branch in `rowPrecedesByRecency:369-389`, order by relay `orderKey`; keep filter/group/facet/summary/counts. `ThreadCardRowProjector.swift` — delete `activityDate` ISO-parse/`.distantPast`, consume `activityAtMs` verbatim, keep `relativeTime` formatting, delete cached-pinned path. First-class `.stale`: `ThreadCardTable.hostStatus:321`, `AppConnectivityStore` (`.stale` out of `isOnlineLike:19`), `GlobalConnectivityIndicatorView`/`SystemHealthProjector`. Unify on `ThreadCardTable`; delete `ThreadCardStreamSnapshotCollector`; point Archive + cleanup at it.
Gates: **rewrite** `DockStoreTestsProjection.swift:13,46` (client preserves relay `orderKey`), `DockStoreStreamTests.swift:219` (`.stale` not `.partial`), `AppConnectivityStoreTests.swift` (`.stale` not online-like), `DockRenderProjectorTests.swift:44` (placeholder, no fabricated data); add client-no-recompute test.

**Phase 4 — Delete side doors + their tests.**
Changes: delete `relay/state/snapshot` + `state/query` routes and their tests (`dock-relay.test.mjs:1411` + snapshot oracle); internalize the four raw thread routes; remove Swift `threadList` + health registrations; **rewrite** `dock-relay-phase5.test.mjs:553,691` (they encode the old no-turn-warming behavior and must flip); replace `ThreadCardFixtureQuery` scope tests (`DockStoreTestSupport.swift:12`) with direct `DockThreadCardDTO` stream fixtures; update `AppServerClientTests.swift`/`DiagnosticsLoggingTests.swift:47`/`SystemHealthProjectorTests.swift:14`.
Gates: add "removed route returns unsupported method" test; full relay + Swift suites green.

**Phase 5 — Docs + in-code invariants.**
Changes: invariant doc-comments on `normalizeThread`, the canonical scan function, `applyDockReconciliation`, `DockThreadCardDTO`/schema descriptions, `DockCardProjection`, `LocalThreadMetadata`, `AppConnectivityStore.HostConnectivityPhase`; update README contract section; cross-link plan ↔ `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`; mark audit drift-inventory resolved.
Gates: `rtk npm run test:relay`, `rtk swift test` (DockStore/ThreadDetail/AppServerClient), `rtk npm run contract:check`, and **extend `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`** to assert an active-thread-with-new-turn lands on top (the real user symptom).

---

**Net convergence:** one relay projection folds list/read/turn/live/session-index into one stored card; client renders relay `orderKey` + fields verbatim; live status lives inside the projection (no read-time overlay, no second live cache); card-truth RPC side doors and their tests are deleted (not hidden); ops-health endpoints stay but never read as freshness; pinned-but-absent rows degrade honestly. The only deferred item is the live turn-event ingestor, explicitly left unbuilt to avoid overbuild, with its residual gap documented.
