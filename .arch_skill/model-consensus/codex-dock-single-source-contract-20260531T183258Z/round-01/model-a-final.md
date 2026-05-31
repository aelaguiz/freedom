I now have first-hand, line-exact confirmation of every load-bearing claim. One finding is decisive: `DockCardProjection.swift:369-389` carries a comment that is effectively a **confession** that the relay's `orderKey` is broken ("Relay order keys are only stable inside one host's stream, so using them first can interleave stale rows… above newer work") — so the client recency re-sort exists *because* the relay order key is non-canonical. That pins the elegant fix exactly.

Here is my Model A first pass.

---

## ⚠️ Premise correction (must read first)

My very first file read returned "empty" for `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`. That was a tool glitch. The file is **not empty** — it is **372 lines / 46,778 bytes and is the richest doc in the corpus**. Your chosen option ("siblings + repo, then write it") assumed the audit needed authoring as deliverable #1. **It does not** — it already exists and is excellent. So I am **cross-linking the plan to the existing audit, not rewriting it**. I will not overwrite that file (it isn't mine and contradicts "empty"). Net effect: you still get the same plan, grounded in the same evidence, minus a redundant write.

Below, citations use: **CONTRACT** = the relay-data-contract audit (the named file), **REPORT** = staleness root-cause report, **CONNECTIVITY** = connectivity audit.

---

## 1. Proposed implementation plan (concise)

**The diagnosis in one line (CONTRACT:370):** the system is *shape-safe but source-unsafe*. There is exactly one payload contract (`contract/dock/dock-thread-card.schema.json` → `DockThreadCardDTO.swift`), but the **semantic source** of recency, order, summary, status, and freshness is computed in several places that disagree.

**The fix in one line:** make the **relay Dock projection** the single semantic authority — it computes one canonical activity timestamp per thread, derives `orderKey`/`activityAt(Ms)`/`displaySummary`/`status`/`freshness` from it, persists it, and streams it; the **Swift client renders relay output verbatim and computes nothing** about recency, order, status, or freshness.

Concretely, four collapses:

1. **Recency → one timestamp.** `normalizeThread` (`dock-relay-state-views.mjs:312-350`) currently sets `activityAtMs = thread.activityAt ?? updatedAt ?? createdAt` (`rowTimestamp`, line 162-164) and never looks at turns. Make it compute **canonical activity** = `max(latest turn time, live event time, updatedAt, createdAt)` (CONTRACT:361).
2. **Order → one key.** Active Dock uses `dockOrderKey(listIndex, threadID)` = list ordinal (`:182-185`); Archive uses `archiveOrderKey(activityAtMs, …)` = activity (`:187-190`); the **client re-sorts by its own `lastActivityDate`** as a documented workaround (`DockCardProjection.swift:369-389`). Make active Dock's `orderKey` activity-derived like archive's, then **delete the client recency sort** and sort purely by relay `orderKey` (CONTRACT:363 — do *both* halves).
3. **Live state → one source, status-only by contract.** Collapse `LiveStatusCache` + `live_leases` (two clocks, CONTRACT:187) into one live-state source feeding both `SessionRouter` and the card overlay. Keep the lease overlay status-only (CONTRACT:364 option A) and fix the expiry edge in `applyLeaseToCard` (`:384-399`) so an expired lease falls back to *projected* status, never a stale `running`.
4. **Freshness → one honest axis.** Relay freshness is the only freshness authority; Swift maps relay `.stale` to a **first-class `.stale`** (not `.partial`), and `.stale` is **not** online-like. Kill the `stale → partial → "Online 2/2"` collapse (REPORT:108-133, D7).

**The invariant to document in code and lock with tests:**

> Every Dock/Archive card's recency, ordering, summary, status, and freshness are computed **once, by the relay projection**, from a single canonical per-thread activity timestamp (priority: latest turn → live event → `updatedAt` → `createdAt`). The relay persists that timestamp and derives `orderKey`/`activityAt(Ms)`/`displaySummary`/`status`/`freshness` from it. The Swift client renders cards **in relay `orderKey` order, using relay field values verbatim**; it never recomputes recency, ordering, status, or freshness, and **sources card data only from the `dock/*`/`archive/*` stream**. Live leases are a **status-only overlay applied inside the projection before emission**; there is no second live-state source. Transport/route health is never presented as data freshness.

---

## 2. Canonical source of truth — and why it is the right owner

**Owner: the relay Dock projection** — `normalizeThread`/`orderedDockRows` in `scripts/dock-relay-state-views.mjs`, persisted to the `threads` table in `.codex-dock/relay-state.sqlite` (`dock-relay-state-store.mjs`), emitted via `dock/*` + `archive/*` as `DockThreadCardDTO` per `contract/dock/dock-thread-card.schema.json`.

Why this is the right (and only) owner, not a new one:

- **It already is the contract boundary.** The schema + generated Swift DTO already exist and every production consumer already reads the stream (REPORT:147-151). We make the existing path the *sole* semantic authority — we don't add a path.
- **It already persists projected rows** (`threads` table, CONTRACT:79/257). The canonical timestamp belongs in a column next to the values it derives.
- **The bug is here, and the client is innocent.** Both audits conclude Swift faithfully renders stale fields; the deeper bug is the relay choosing thread-level rows over turn-level activity (CONTRACT:372, REPORT:372). Fixing recency anywhere else (e.g., the client) just adds a *second* authority.
- **The client's own code admits it.** `rowPrecedesByRecency`'s comment (`DockCardProjection.swift:370-372`) says it ignores relay order *because* relay order interleaves stale rows. That is a workaround for a broken upstream key — the textbook signal that the upstream key, not the client, should be fixed.

---

## 3. Side doors to delete or absorb (exact)

| # | Side door (file:line) | Disposition | Why |
|---|---|---|---|
| S1 | `relay/state/snapshot` route — `dock-relay.mjs:483-484`, `dock-relay-state-snapshot.mjs` | **Delete from production surface** (demote to test-only oracle helper) | Reads list/read/turns/goal/loaded directly, "explicitly not the SQLite stream source," can be fresher/different (CONTRACT:108,190). Once projection reads turns, its reason to exist on the wire is gone. |
| S2 | `state/query` route — `dock-relay.mjs:511-512` | **Delete** | "Side door around subscribe/update sequencing"; not in `AppServerMethods` (CONTRACT:115). |
| S3 | Client recency re-sort — `DockCardProjection.swift:369-389` (`rowPrecedesByRecency`, used at :55,56,108,141) | **Delete the `lastActivityDate`-first logic; sort by relay `orderKey` only** | Third ordering authority; exists only because relay `orderKey` is non-canonical (see §2). Fixing S7 removes its reason to exist. |
| S4 | Client activity-date parsing + `.distantPast` fallback — `ThreadCardRowProjector.activityDate` (CONTRACT:307) | **Delete; consume required `activityAtMs` directly** | Silent wrong-order side door when `activityAt` won't parse. Keep relative-time *formatting* (UI), delete the value-derivation. |
| S5 | Cached pinned display snapshot — `LocalThreadMetadataStore.lastKnownPinnedDisplay`, `ThreadCardRowProjector` pinned path (CONTRACT:87,308) | **Delete the fabricated card snapshot; keep label/rail/pin/pinnedOrder** | Local metadata fabricates title/status/activity for absent threads (CONTRACT:189). Pin stays visible as a clearly-degraded placeholder; relay owns card fields, local owns overlay. (UX call — see §9.) |
| S6 | Two stream collectors — strict `ThreadCardTable`/`DockDataEngine` vs loose `ThreadCardStreamSnapshotCollector` (Archive+cleanup) (CONTRACT:145,154) | **Unify on `ThreadCardTable`; delete the loose collector** | Two decoders of one stream = drift. |
| S7 | Active-Dock ordinal order key — `dockOrderKey` `dock-relay-state-views.mjs:182-185`, used in `normalizeThread:324` | **Rewrite to activity-derived (like `archiveOrderKey:187-190`)** | Root of the ordering split; makes relay `orderKey` globally canonical so S3 can die. |
| S8 | `mergeAuthoritativeThreadRead` — `dock-relay-thread-data.mjs:623-637` | **Rewrite: never regress canonical activity (take max); stop deleting turns** | A stale `thread/read.updatedAt` can overwrite fresher data and drops turns (CONTRACT:231). |
| S9 | Two live-state sources — `LiveStatusCache` (`dock-relay-thread-data.mjs:51-59`) vs `live_leases` (`dock-relay-state-store.mjs:182-190`) | **Unify into one live-state source** | Separate clocks → detail routing disagrees with card overlay (CONTRACT:187,286-291). |
| S10 | Lease expiry edge — `applyLeaseToCard` `dock-relay-state-views.mjs:388-391` | **Rewrite: expired → projected status; valid → status-only overlay** | Confirmed verbatim: expired lease only fixes `dormant`, leaves stale `running` (CONTRACT:291,334). |
| S11 | Legacy `thread/list` Swift wrapper — `ThreadListResponseDTO`/`ThreadListParams` (CONTRACT:160) | **Delete if no production caller** | README says it is not the Dock list contract; deleting it removes an "alternate weird way" to fetch the list. |
| S12 | `partial`-counts-as-online — `ThreadCardTable.hostStatus` (`:321-352`) + `AppConnectivityStore.HostConnectivityPhase.isOnlineLike` + `GlobalConnectivityIndicatorView` | **Introduce first-class `.stale`; `.stale` not online-like** | The display SSOT collapse (REPORT:108-133). |
| S13 | `thread_field_provenance` table — `dock-relay-state-store.mjs:159-167` | **Delete (lean) unless a consumer is found** | Drift-control scaffolding with "no production reader" (CONTRACT:80,258); canonical-activity + behavioral tests enforce the invariant more simply. (Flag for Model B.) |

**Absorb, do not delete (real capability):** the `session_index.jsonl` supplement (`readSessionIndexHumanStartedSupplements`, CONTRACT:78) surfaces human threads `thread/list` misses — keep the rows, but route them through the one projection and **fix the failure scoping** so one supplemental `thread/read` rejection marks only that candidate, not whole-host stale (REPORT:75-82, D10).

---

## 4. Owner files/modules to change (exact)

**Relay (the canonical owner — primary work):**
- `scripts/dock-relay-state-views.mjs` — **primary.** `normalizeThread` (:312-350): canonical activity at line 318; `dockOrderKey` (:182-185) → activity-derived; `applyLeaseToCard` (:384-399) expiry+overlay; `rowTimestamp` (:162-164); `normalizeStoredCard` (:352-382) read-back of the new column.
- `scripts/dock-relay-state-engine.mjs` — `reconcileDock` (:252-288) feed turn recency; `refreshLiveLeases` (:441-468) unify live source; `shouldReconcileAfterResponse` (:226-234); freshness publish (:308-323).
- `scripts/dock-relay-thread-data.mjs` — `mergeAuthoritativeThreadRead` (:623-637); supplement validation (:640-643,:705-710); `listThreadTurns` (:976-985) now consumed by projection; `LiveStatusCache` (:51-59).
- `scripts/dock-relay-state-store.mjs` — `threads` schema (:130-154) add `canonical_activity_at_ms` column; `upsertThreadCard` (:703-779); `freshnessForHost` (:369-392); `live_leases` (:182-190); `listDockCards` order (:394-430); drop `thread_field_provenance` (:159-167).
- `scripts/dock-relay.mjs` — remove `relay/state/snapshot` (:483-484) and `state/query` (:511-512).
- `contract/dock/dock-thread-card.schema.json` — make **`activityAtMs` required** (currently `["integer","null"]` at :277-281, absent from `required` at :231-232); document canonical-activity semantics in field `description`s. Regenerate via `scripts/generate-dock-thread-card-contract.mjs`.
- `scripts/check-dock-thread-card-contract.mjs` — **replace keyword forbid-list confidence with real JSON-Schema validation** over fixtures (CONTRACT:193, D17). No new keyword linter.

**Swift (render-only):**
- `CodexDock/State/DockCardProjection.swift` *(already modified on branch)* — **primary client work.** Delete `lastActivityDate`-first in `rowPrecedesByRecency` (:369-389); order by `orderKey`. Keep filter/group/facet/summary/counts (UI capability over relay-provided values).
- `CodexDock/State/ThreadCardRowProjector.swift` — delete `activityDate` ISO-parse + `.distantPast`; keep `relativeTime` formatting; delete cached-pinned-display path.
- `CodexDock/State/ThreadCardTable.swift` — `hostStatus` (:321-352): `.stale` → first-class stale.
- `CodexDock/State/AppConnectivityStore.swift` — add `HostConnectivityPhase.stale`; remove `.partial` from `isOnlineLike`; separate data-freshness vs transport-reachability axes (CONNECTIVITY B16).
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` (+ `SystemHealthProjector`) — show stale honestly.
- `CodexDock/State/LocalThreadMetadataStore.swift` + `CodexDock/Metadata/LocalMetadataEngine.swift` — drop `lastKnownPinnedDisplay`.
- Delete `ThreadCardStreamSnapshotCollector`; point Archive + cleanup at `ThreadCardTable`.
- Delete legacy `thread/list` wrapper + its `AppServerMethods` entry (after confirming no caller).

---

## 5. Tests to delete / rewrite / add

**Rewrite (they lock side doors):**
- `scripts/dock-relay.test.mjs:1280` "card activity comes from thread fields" → assert it comes from **canonical (latest-turn)** activity.
- `scripts/dock-relay.test.mjs:292` expired-lease-dormant → assert expired lease yields **projected status**, never stale `running`.
- `CodexDockTests/DockStoreStreamTests.swift:219` stale → `.partial` → expect first-class `.stale`.
- `CodexDockTests/AppConnectivityStoreTests.swift` `.partial`-online-like asserts → `.stale` not online-like.
- `CodexDockTests/DockRenderProjectorTests.swift:44` cached pinned renders without live card → degraded placeholder, no fabricated status/activity.
- `CodexDockTests/DockStoreTestsProjection.swift` *(modified)* — ordering asserts (`:13`,`:46`) → assert **client preserves relay `orderKey` order**. Keep grouping/filter/count asserts (presentation over relay values).

**Keep but strengthen (they encode correct invariants):**
- `scripts/dock-relay.test.mjs:243` lease status-only → assert lease **never** changes activity/order/summary.
- `scripts/dock-relay-observability.test.mjs:190,238` (`/readyz`/route healthy while stale) → keep (route health ≠ freshness, D5) **and add** that the *client-facing* freshness surfaces as `.stale`.
- `scripts/dock-relay.test.mjs:206,628` stale retention / fresh-subscribe-skips-refresh → keep; retention is intended, now paired with loud-stale.

**Add (lock the invariant — behavioral, not keyword scans):**
1. **Relay recency** (reproduces CONTRACT:13-18): turn newer than `thread/read.updatedAt` ⇒ card `activityAtMs`/`orderKey` reflect the turn.
2. **Relay order**: `listDockCards` order == canonical-activity order (not list ordinal).
3. **Lease status-only + expiry**: overlay never mutates activity/order/summary; expired ⇒ projected status.
4. **Single live source**: detail routing and card overlay derive from the same source.
5. **Freshness scoping**: one supplement failure ⇒ only that candidate fails, host not poisoned.
6. **Client renders relay order**: `DockCardProjection` output order == input `orderKey` order across all lenses.
7. **Client no-recompute**: client uses `activityAtMs` verbatim; no ISO-parse path.
8. **Stale is loud**: relay `.stale` ⇒ Swift `.stale` ⇒ badge not "Online"; `.stale` not online-like.
9. **Contract**: add a stale + latest-turn-recency fixture under `contract/dock/fixtures/`; run full JSON-Schema validation.
10. **E2E**: extend `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` to assert the active-thread-with-new-turn lands at top (the real user symptom).

---

## 6. In-code invariant docs (no linters, no facades)

- Header doc-comment on `dock-relay-state-views.mjs` (the projection owner): the canonical-activity invariant + priority order, cross-linking `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`.
- Doc-comment on `DockThreadCardDTO` **and** the schema field `description`s: "values are canonical, computed once by the relay; the client renders verbatim and must not recompute recency/order/status/freshness."
- Doc-comment on `DockCardProjection` replacing the current `rowPrecedesByRecency` confession: "render-only; order by relay `orderKey`; never recompute recency."
- Doc-comment on `applyLeaseToCard`: "status-only overlay; never mutate activity/order/summary; expired ⇒ projected status."
- Doc-comment on `AppConnectivityStore.HostConnectivityPhase`: "data freshness and transport reachability are distinct axes; `.stale` is not online-like."

---

## 7. Migration order (no half-old/half-new states)

The trap: client trusting a value the relay doesn't yet produce, or requiring `activityAtMs` before the relay always sends it. So **relay produces canonical truth additively first, client switches to trust it, then dead paths are deleted.**

1. **Relay computes & persists canonical activity (additive).** Turn-aware `normalizeThread` + new `threads` column; always populate `activityAtMs`; `activityAtMs` still optional in schema. No client change — cards already sort correctly from the relay. *(+ relay recency/order tests.)*
2. **Relay: unify live source, fix lease expiry + freshness scoping.** *(+ lease/live/freshness tests.)*
3. **Contract tighten: `activityAtMs` required; regenerate DTO; full-schema fixtures.** Safe now because step 1 always emits it.
4. **Client → render-only.** Order by `orderKey`; delete recency sort + ISO-parse + `.distantPast`; first-class `.stale` + honest badge; unify on `ThreadCardTable`; drop cached pinned display. *(+ client render-order / stale-loud / degraded-pin tests.)*
5. **Delete side-door surfaces last.** Remove `relay/state/snapshot` + `state/query` routes; delete legacy `thread/list` wrapper; delete/rewrite their tests — only after nothing depends on them.
6. **Docs + in-code invariants.** Cross-link plan ↔ audit; update README contract section; mark the audit's drift-inventory items resolved.

Each step ships independently; no step has the client trusting a not-yet-emitted value.

---

## 8. Rejected alternatives

- **A new "canonical activity" module/service.** Rejected — the projection already owns derivation; a new module is a second owner. Absorb into `dock-relay-state-views.mjs`.
- **A second/v2 schema or DTO for recency.** Rejected — one schema exists; tighten it (`activityAtMs` required). Audit D6 warns against false-confidence schema growth.
- **Keep the client recency sort as a "safety net."** Rejected — it *is* the duplicate ordering authority; two orderings guarantee drift. Fix relay `orderKey`, delete the workaround.
- **Leases carry full card data (activity/summary)** (D4 option B). Rejected as the heavier branch — leases become a second card source. Choose status-only overlay (D4-A).
- **Client polls `thread/turns/list` per visible card.** Rejected — N+1 recompute at the wrong layer; recency must be relay-side.
- **Wire `thread_field_provenance` as the enforcement mechanism.** Rejected (lean) — per-field bookkeeping nobody reads; behavioral tests + canonical computation enforce more simply. (Flag.)
- **Keyword linter / validator-only facade.** Rejected per your constraint — use real JSON-Schema validation + behavioral recency tests.
- **Preserve `relay/state/snapshot` "for the oracle/tests."** Rejected per your constraint — demote to a test-only helper, not a shipped route.

---

## 9. Risks / open questions

1. **Turn-scan cost (biggest design risk).** Reading `thread/turns/list` for every visible card doesn't scale (961 rows in evidence, REPORT:22). Options: (a) **incremental live turn-event ingestor** that bumps card recency (the audit's explicitly-missing piece, CONTRACT:292) — preferred, lowest steady-state cost; (b) bounded turn-fetch for top-N by `updatedAt`; (c) hybrid. **Needs a decision.**
2. **Cached pinned display removal is a visible UX change.** Pinned-but-absent threads lose the fabricated preview, gaining a degraded placeholder. Preserves "pinned stays visible" but not fake data. **Confirm acceptable.**
3. **First-class `.stale` wording.** "Online 2/2" becomes "Stale"/"Online 1/2" (REPORT D8). **Confirm exact wording.**
4. **`activityAtMs` required + device fleet skew.** Phones/sim run different builds (REPORT:159-167). Step ordering (relay first) mitigates, but a newer client hitting an older relay would reject; needs a rollout note or a one-version grace.
5. **Max acceptable source age** (REPORT D11): hard-expire a list after N minutes without sync? **Product decision.**
6. **`thread_field_provenance` and the legacy `thread/list` wrapper:** confirm no consumer before delete.
7. **Archive ordering** already activity-derived — ensure the unified rule doesn't regress it (it shouldn't; we make Dock match Archive).

---

## 10. Evidence read and why it mattered

- **`docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md` (full, 372 lines)** — the spine: source/endpoint/consumer/side-door inventories with file:line, the "shape-safe/source-unsafe" thesis, and the canonical-activity prescription (D1–D6). *(Corrected: not empty.)*
- **`…STALENESS_ARCHITECTURE_ROOT_CAUSE_REPORT…` (full)** — the connectivity-collapse half (stale→partial→online) and the open decisions D7–D11, plus the validation-failure-poisons-host mechanism.
- **`…CONNECTIVITY_DETECTION_AND_DISPLAY_AUDIT…` + `…WORKLOG…`** — multiple connectivity reporters into one badge; runtime corroboration.
- **First-hand code reads (decisive):**
  - `DockCardProjection.swift:369-389` — confirmed client sorts by `lastActivityDate` first, with a comment confessing relay `orderKey` is non-canonical. *This pinned the elegant fix: repair relay order, delete client workaround.*
  - `dock-relay-state-views.mjs:162-190, 312-399` — confirmed `activityAtMs = updatedAt??createdAt` (no turns), `dockOrderKey` = list ordinal vs `archiveOrderKey` = activity, and `applyLeaseToCard` expiry-only-fixes-dormant verbatim.
  - `contract/dock/dock-thread-card.schema.json:231-281` — confirmed `activityAtMs` optional and absent from `required` (so "make it required" is a real tightening).
- **Three Explore agents** — relay map (owner = projection; lease/live mechanics), client map (recompute sites; cached pinned), test map (exact side-door-locking tests + the sync-proof harness to extend).

---

## 11. What I need from Model B to converge

1. **Agree the canonical owner = relay projection (`dock-relay-state-views.mjs`) + `dock/*` stream as the sole semantic authority, client render-only** — or substantiate a different owner from the code.
2. **Pick the recency-cost strategy:** incremental live turn-event ingestor (my lean pick) vs bounded turn-scan vs hybrid. This is the main open design decision.
3. **Confirm lease = status-only overlay (D4-A)** vs leases carrying activity (D4-B).
4. **Cached pinned display:** delete fabricated snapshot (my pick) vs keep-but-mark-stale — UX call.
5. **First-class `.stale` + badge wording.**
6. **Confirm deletes** of `thread_field_provenance`, `relay/state/snapshot` (route), `state/query`, and the legacy `thread/list` wrapper — and surface any caller I missed.
7. **`activityAtMs` required now** vs a one-version grace, given the multi-build device fleet.

If Model B disagrees on the owner (#1) or the recency strategy (#2), that's where the real convergence work is — everything else follows from those two.
