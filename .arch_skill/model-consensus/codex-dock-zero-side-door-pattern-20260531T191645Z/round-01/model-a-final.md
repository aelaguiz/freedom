I have verified evidence. Both contested findings are confirmed and one is sharper than either prior reviewer stated. Here is my consensus.

---

# Verdict

**Not ready. Converge on Model B's architecture, but the plan is still implementable in a way that drifts.** Model B's single-projection / render-only pattern is correct and necessary, and Model B correctly adds the two repairs the plan-audit missed (archive mutations, scripted fixtures). But neither the plan, the plan-audit's five findings, nor Model B's six bullets name three concrete code paths where old truth survives even after a faithful implementation. I verified them against source:

1. **Unarchive writes a fabricated list-ordinal rank.** `applyArchiveMutation` sets `order_key = dockOrderKey(0, threadID)` on unarchive (`scripts/dock-relay-state-store.mjs:825`), and `dockOrderKey` is pure list-ordinal (`scripts/dock-relay-state-views.mjs:182-185`). It also writes `freshness_status='stale'` directly (`:829`). This is the *exact* ordinal-drift class Phase 0 is trying to kill, on a writer the plan's Endpoint Disposition table never lists. Model B's "make it a projection input" is directionally right but does not name this write, so an implementer can satisfy that wording and still ship the ordinal-0 jump.
2. **Live-only rows are never enumerated.** `orderedDockRows` overlays live status onto existing rows but does not add live rows absent from `thread/list`/supplements (audit `:247`, drift inventory). A live thread missing from the list stays absent from Dock entirely — a completeness hole orthogonal to ordering that no finding covers.
3. **A dead drift-control table is left wired-but-unused.** `thread_field_provenance` exists (`scripts/dock-relay-state-store.mjs:159-167`) but no card reader uses it (audit `:260`). Either it becomes the stored proof-of-source bit the honest-freshness invariant requires, or it is deleted — leaving it is a trap that makes future readers believe provenance is enforced.

I also confirmed the worst HTTP offenders are card truth, not mere ops health: `/statez` returns the full state snapshot and `/explainz/thread/{id}` returns the per-thread stored-row explanation (`scripts/dock-relay.mjs:895-897, 926-934`). The plan's keep-list (`/readyz`, `/statusz`, `/routesz`, `/metricsz`) omits them, so "not mentioned = keep" is a live risk.

---

# Must Change In The Plan

1. **Kill the accepted residual gap (PLA-001/PLA-005).** Delete "Known Residual Gap." Replace with the hard invariant in the next section. `thread/list.updatedAt` is proven stale (runtime: `read.updatedAt=1780238608` < `turn.startedAt=1780249079`), so it is **not** an upper bound and can never justify "rows below the window can't outrank." A stream may present `fresh`+`complete` only when every emitted card's activity is proven, or a real per-host max-activity watermark proves unscanned rows cannot outrank.
2. **Add a normative route-scope table** (JSON-RPC *and* HTTP) as a governing section authored *before* Phase 0 — see Final Pattern. The keep/strip decision for `/statez`, `/syncz`, `/dbz`, `/explainz/thread/*`, `/subscriptionsz`, `/selftestz`, `/bundlez` must be explicit; `/statez` and `/explainz/thread/*` must be deleted or stripped of card/state payloads because they return stored card truth.
3. **Add a Phase 1.5: Archive/unarchive as projection input.** Explicitly delete the `dockOrderKey(0, threadID)` and direct `freshness_status` writes in `applyArchiveMutation`; route both mutations through the canonical-activity recompute; emitted delta carries uncertain freshness until upstream confirmation folds in.
4. **Make Phase 1 enumerate live-only rows**, not just overlay status — close the `orderedDockRows` live-only-absence hole. The "live-only thread appears" item must be an architecture guarantee, not only a test.
5. **Wire or delete `thread_field_provenance`.** The honest-freshness invariant needs a *stored* per-card "activity proven" bit; this table is the obvious home. If not used, delete it in Phase 4.
6. **Bind the existing contract vocabulary to proof.** The schema already has per-card `completeness` (`complete|partial|unknown`) and `freshness` (`unknown|fresh|stale|...`) plus stream `complete` and host `freshness.status` (`contract/dock/dock-thread-card.schema.json:337-352, 30-31, 164-170`). The fix needs **no new schema** — it needs a rule: unproven activity ⇒ card `completeness:partial`/`unknown`; any unproven card in the emitted ordering set ⇒ stream `complete=false` + host `freshness.status=stale`.
7. **Extend Phase 4 to the proof scripts** (`dock-relay-sync-audit.mjs`, `dock-relay-state-parity.mjs`, `dock-relay-thread-fidelity.mjs`, `dock-relay-probe.mjs`) — rewrite to card-stream-only or delete (PLA-003). Add the `thread/read`/`thread/turns/list`/`thread/resume` detail-only proof ban (PLA-004), which Phase 4's current list omits.

---

# Final Pattern

**One projection, one stored row, two card streams, render-only client — governed by a normative route-scope allow-list and an honest-freshness invariant.**

**Honest-freshness invariant (replaces the bounded-scan gap):**
> Every emitted Dock/Archive card carries a relay-computed `activityAtMs = max(updatedAt, createdAt, newestTurn, liveEvent)` **and** a stored proof-of-source state. A card is `completeness:complete` only if its canonical activity was derived from an actually-inspected authoritative source (a read turn page, a folded live turn event, or a value proven to be an upper bound). A card ranked only on `thread/list.updatedAt` is `completeness:partial`/`unknown`. Any stream whose emitted ordering set contains an unproven card MUST emit `complete=false` and host `freshness.status=stale`, and the client MUST NOT present it as a fully-fresh newest-first list. Implementation may use background/incremental scanning, but the **contract never permits a knowingly mis-ranked card inside a stream labeled fresh.**

**Route-scope table (normative allow-list; a route not marked card-truth=yes cannot prove card truth in any code or test):**

| Route | Plane | App-facing | May prove card truth | Disposition |
|---|---|---|---|---|
| `dock/subscribe·update·resync`, `archive/subscribe·update·resync` | card | yes | **yes (only these)** | keep |
| `thread/read·turns/list·resume` | detail | yes | no | keep; prove Detail only *after* a card is selected; never prove Dock/Archive order, freshness, summary, membership, completeness |
| `thread/archive·unarchive` | command | yes | no | keep as **projection input only**; no separate order/freshness writer |
| `thread/list·search·goal/get·loaded/list` | internal input | no | no | remove app-facing route; never card proof |
| `relay/state/snapshot`, `state/query` | oracle | no | no | **delete route + tests** |
| HTTP `/readyz·healthz·statusz·routesz·metricsz` | process/route health | yes | no | keep; never shown as data freshness |
| HTTP `/statez·explainz/thread/*` | **state/card** | no | no | **delete or strip card/state payload** (return stored rows today) |
| HTTP `/syncz·dbz·subscriptionsz·selftestz·bundlez` | diagnostic | no | no | strip to process/route data or gate to non-shipping builds; never card-proof |
| voice + `turn/*` | side | n/a | no | out of scope; no card authority |

Pins/labels/rails/pin-order stay local; title/status/activity/summary/order never come from local cache or `LocalPinnedDisplaySnapshot`.

---

# No-Side-Door Proof Rules

The guarantee is **structural, not lexical** — no keyword linter, no wrapper guard.

1. **Delete the path, don't interdict it.** Oracle routes (`relay/state/snapshot`, `state/query`) and the card/state HTTP endpoints are removed/stripped, and the audit/probe scripts are rewritten to card-stream-only or deleted. A route that does not exist cannot be a side door; a linter that greps for its name can be bypassed or deleted. This is the only real guarantee.
2. **Single typed proof entry point.** Card/Archive correctness tests observe card data only through the same `dock/*`/`archive/*` subscription client the app uses. Raw upstream routes, leases, SQLite, and HTTP state are available to tests **only as inputs to a fake history/upstream server placed behind the relay**, never as a relay-exposed surface the test reads to assert card truth. The harness physically cannot read an oracle to judge order/freshness because the only card-shaped data it can observe came out of the stream.
3. **Fixtures carry production semantics.** `ScriptedDockStreamClient`/`ThreadCardFixtureQuery` may exercise rendering/reducers, but must build cards through the same projection/normalization helper as the relay and obey the same completeness/freshness rule. A fixture that emits `fresh`+`complete` without proven activity is itself a banned side door and may never be the artifact a freshness/order test asserts as production proof.
4. **Contract checks validate shape only.** Replace keyword confidence in `check-dock-thread-card-contract.mjs` with real JSON-Schema fixture validation; semantic recency is proven only through relay projection + card streams.

---

# Signoff Criteria

The plan is ready when **all** hold:

- [ ] Residual-gap section deleted; honest-freshness invariant present and bound to existing `completeness`/`freshness`/stream-`complete` fields (no new DTO/schema v2).
- [ ] Normative route-scope table present (every JSON-RPC and HTTP route classified), authored before Phase 0; `/statez` and `/explainz/thread/*` marked delete/strip with reason.
- [ ] Phase 1.5 present: `dockOrderKey(0)` and direct `freshness_status` writes in `applyArchiveMutation` removed; archive/unarchive routed through canonical recompute.
- [ ] Phase 1 guarantees live-only-row enumeration (architecture, not just a test).
- [ ] `thread_field_provenance` either wired as the proof-of-source store or scheduled for deletion.
- [ ] Phase 4 covers proof scripts (`sync-audit`/`state-parity`/`thread-fidelity`/`probe`) and the detail-only proof ban for `thread/read`/`turns/list`/`resume`.
- [ ] Proof rules state delete-the-path + single-typed-entry-point + production-semantics fixtures, with no reliance on keyword linters/wrapper guards.

**Where drift still lives if these are skipped:** unarchive ordinal-0 rank (`state-store.mjs:825`), live-only rows never shown (`state-views.mjs:247`), `/statez` + `/explainz/thread/*` serving card truth over HTTP (`dock-relay.mjs:895,926`), a fixture asserting fabricated `fresh`, and any test reading `thread/turns/list` as a Dock ordering oracle. Each is reachable after a faithful implementation of the plan and Model B *as currently written*.
