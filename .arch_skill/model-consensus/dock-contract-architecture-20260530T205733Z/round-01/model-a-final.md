I now have a thorough, evidence-backed picture across all eight dimensions. Here is my independent first-pass architecture as **Model A (Opus 4.8 max)**.

---

# Codex Dock — Drift-Proof Architecture (Model A, Round 1)

## Thesis (one sentence)

The bug is not that the client sorts wrong — **it's that the client sorts, projects, and classifies *at all*.** The relay already owns a correct, materialized, bounded, incrementally-diffed view; the client re-derives that same truth from fields the upstream contract never populates. The elegant cure is a single principle applied uniformly: **project once, at the authority; everything downstream is a faithful carrier or a pure presentation transform — never a re-derivation of owned truth.**

---

## 1. Product / user-experience model (inferred from evidence)

A **single-operator iPhone "calm operations board"** for thousands of Codex agent threads across several personal Macs (Amir-M5, Home, Studio) over Tailscale/LAN, via a Mac-side relay (`:4510`) proxying the raw Codex app-server. It answers *"what changed most recently, where is it running, how do I narrow this giant list?"* — explicitly **not** "which thread needs me" (Needs-me is demoted; recency + explicit filters beat weak prediction — `CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md` §0,§12).

- **3 tabs** (Dock | Archive | Relay/Hosts) + pushed Session Detail + one global connectivity indicator (`README.md:145-167`).
- **Dock** = flat **newest-activity-first** index across hosts; Host/Branch are *in-Dock lenses* that preserve newest-first inside groups (§8 lines 550-557).
- **Every row is self-describing**: title (LLM-or-fallback), status chip, last-activity age, host short name, branch, repo/cwd, short summary, optional user label+color (§7 lines 464-508).
- **Detail**: one newest-first message list, one filter, one card family, no caps; composer never auto-submits (`CODEX_DOCK_THREAD_DETAIL_MESSAGE_FLOW_GOALS_2026-05-29.md`).
- **Archive** = Codex's own archive state; archived rows vanish from all normal surfaces, reversible.
- **Scale is the experience**: live evidence of 1519–6494 rows, 141–150 s loads, 219 595 turn items. Bounded first payload + incremental deltas are a **non-negotiable promise**, not an optimization.
- **Secret boundary**: phone holds no bearer token on the personal relay; `OPENAI_API_KEY` stays Mac-side.

The UX makes the ordering contract *unambiguous* — which is exactly what the code violates.

## 2. Root cause (precise mechanism)

`codex.clientOrderRootCause` is a **split contract**, confirmed end-to-end:

1. **Relay computes correct order**: drains app-server `thread/list` (sortKey=updated_at, desc), assigns `dock_order` = arrival index (`dock-relay-state-views.mjs:211-240`), persists in SQLite, serves `ORDER BY dock_order ASC, updated_at_ms DESC, thread_id ASC` (`dock-relay-state-store.mjs:340`). The relay stream **is** genuinely newest-first.
2. **The wire DTO carries no order**: `DockStreamSessionDTO` (`DockStreamDTO.swift:222-275`) has `updatedAt`, `messageUpdatedAt`, `summary`, `messageSummary` but **no rank field**. Order is conveyed only by array position — and dies at the boundary.
3. **Client discards order, then re-derives it twice**: rows go into an **unordered dict** `sessionsByID` (`DockSessionTable.swift:24,95-99`); stage-1 sorts by `messageUpdatedAt ?? Int64.min` then `id` (`:257-270`); stage-3 (authoritative) `rowPrecedesByRecency` sorts by `lastActivityDate` then title then `host::thread` (`DockSessionProjection.swift:349-360`).
4. **The chosen key is structurally null**: `messageUpdatedAt`/`messageSummary` are **relay-invented fields the upstream `Thread` never provides** (`codex/.../v2/thread_data.rs:102-148` has only `preview`+`updatedAt`). `normalizeThread` emits null on 100% of live rows (1629/1629). So every row ties → collapses to lexicographic UUIDv7 `thread_id` → **old threads float to top**. The same null produces "No message preview" (ignores the populated `summary`).
5. **Upstream precision collapse (deeper layer)**: Codex orders internally by **milliseconds** with a monotonic +1 ms uniqueness allocator (`codex/.../threads.rs:640-678`), then truncates to **seconds** on the wire via `.timestamp()` (`thread_processor.rs:3944-3945`). Even the *correct* field loses its tiebreak; same-second updates collide with no canonical tiebreak transmitted.
6. **Tests mask it**: 100% of Swift fixtures populate the message fields (`DockStoreTestSupport.swift:272-273,842-843`); zero set them nil. The real pipeline is under test but the null-collapse path is never executed. The parity harness reads only the first 500-row window and never crosses the relay-JSON→Swift boundary (`dock-relay-state-parity.mjs:2746`).
7. **It is recurrent**: a prior arch-step already declared *"no duplicate sorting layer"* and *"fallback_policy: forbidden"* (`CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`), yet the duplicate sorts and split contract survived. **Point patches do not hold** → a by-construction contract is warranted. (The prior consensus run produced no architecture — design space is open.)

## 3. Core architecture proposal

Three owned truths, one ownership rule, zero downstream re-derivation.

**A. The relay is the single projection authority.** It is the *only* place raw Codex thread state becomes a Dock row. The wire row — call it **`DockRow`** — is **resolved and display-ready**: identity `(host_id, thread_id)`, resolved title, resolved `summary` (full fallback chain applied server-side), resolved Dock status (final enum, not a string to re-expand), host display name, branch, repo, source classification, and an explicit **`orderKey`**. The client performs **no** business decisions on these.

> This single move retires: the two `SessionSummary` builders, the 3 status enums + 3 mappings + the lossy collapse/re-expand round-trip, the `summary`/`messageSummary` split, and the `messageUpdatedAt`-vs-`updatedAt` ambiguity.

**B. Ordering is an explicit, globally-comparable, stable token (`orderKey`).** This is the heart of the fix and goes beyond "put `dock_order` on the wire":

- `orderKey` is a **total order with the tiebreak baked in** — primary recency (`updated_at_ms`, best available), deterministic tiebreak `(host_id, thread_id)`. It is **comparable across hosts** (multi-host merge is a deterministic merge by `orderKey`, not a client re-derivation), **stable across reconciles** for unchanged rows (no positional churn — strictly better than today's per-reconcile `dock_order` reassignment, and it makes position changes propagate incrementally for free), and **never null**.
- The client's *only* ordering operation is `compare(a.orderKey, b.orderKey)`. It compares **opaque authority-defined tokens**; it never decides what "recent" means. Lenses order groups by max child `orderKey`; within-group by `orderKey`. One key, one comparator, everywhere.
- **Ordering-by-construction during windowed load**: the relay sends window offset 0 (newest) first, so the client's partial list is always a correct prefix of the global order even before `complete:true`.

**C. User-local overlay is the one thing the client owns** — label, color/rail, pin order. These are personal and absent from Codex. They are overlaid deterministically *on top of* the resolved `DockRow` at one presentation site. (Archive *state* is server truth; label/pin are local — a clean ownership split that also fixes the `LocalPinnedDisplaySnapshot` projection-of-a-projection.)

The client projection collapses to a **pure 1:1 presentation mapping** `DockRow → DockRowViewModel` (format age string, pick SF Symbol for an already-decided status, apply local overlay). The SwiftUI views already never re-sort (`DockView.swift:640-682`), so no view changes are needed.

## 4. Single source of truth & contract ownership

| Truth | Sole owner | Carrier | Forbidden downstream |
|---|---|---|---|
| Row content (title/summary/status/repo/branch/host/source) | Relay `normalize` (one fn) | `DockRow` wire type | client re-deriving any field |
| Order | Relay `orderKey` | `DockRow.orderKey` | client choosing a sort key |
| Identity | `(host_id, thread_id)` canonical | `DockRow.id` | endpoint-string host identity |
| Local overlay (label/rail/pin) | Client metadata store | local only | server inventing label/color |
| History/turns | Codex app-server (lazy direct fetch) | `thread/turns/list` | relay mirroring full history |

**The wire contract must stop being two hand-kept definitions.** Today it is JS object literals (relay) + Swift Codable (client) kept in sync by hand — a rename is a silent nil, not a compile error. Adopt upstream's own pattern (`codex/.../app-server-protocol/schema/typescript/v2/`): **one schema artifact is the source**, the Swift decoder is generated/derived from it, and the Node emitter is validated against it. Drift becomes a build/test failure by construction.

## 5. Performance model (what stays sacred, verbatim)

The architecture is **additive to** the bounding machinery — `orderKey` is a tiny per-row field; the client merge is off-main and coalesced. Preserved exactly:

- **Bounded first payload**: 500-row window AND 1 MB byte soft-limit via halving shrink loop (`dock-relay-state-engine.mjs:375-393`).
- **Incremental delivery**: catch-up windows (256 KB-bounded, seq-guarded) until `complete:true`; deltas diff prev/next and emit only `upsertSessions`/`deleteSessionIDs`; >256 KB or >500 rows upgrades to a snapshot.
- **`dock/subscribe`+`dock/update`+`dock/resync` envelope** (epoch/seq/baseSeq/window/complete/totalRows) — kept verbatim; it *is* the bounded/incremental contract.
- **Client responsiveness**: `RenderCoalescer` (AsyncStream `bufferingNewest(1)` + monotonic `RenderRevision`), off-main `Task.detached(.userInitiated)` projection, 80 ms search / 50 ms voice debounce, `LazyVStack`, detail windowed to newest 240 events with separate `totalMatchingCount`, per-event targeted detail deltas, lazy detail fetch direct to app-server.
- **Strict improvement**: stable `orderKey` *removes* the spurious per-reconcile position churn (drift-risk: unchanged rows currently can't propagate position changes between full snapshots) — fewer deltas, not more.

## 6. Migration / refactor shape (sequence, not schedule)

- **Phase 0 — Lock the contract + prove the bug.** Single wire schema artifact; generate Swift decoder; add a **production-shaped conformance test** (message fields *absent*, like live) that replays real `dock/subscribe`+catch-up through the real client store→projection. It fails today → becomes the gate.
- **Phase 1 — Relay owns resolved projection + `orderKey`.** Add `orderKey` + resolved status + resolved `summary` (single fallback) to `DockRow`; `normalize` becomes the one projection. SchemaVersion bump; emit during transition.
- **Phase 2 — Client becomes faithful renderer.** Delete `DockSessionTable.sortedSessions` and the projection re-sort; order solely by `orderKey`; collapse to one presentation mapping; render resolved status/summary directly; delete `SessionSummary` re-derivation.
- **Phase 3 — Unify archive + lenses + counts.** Archive moves onto the same state-engine view + `orderKey`; move origin classification server-side so tabs/counts/rows share one resolved field (generalizes the existing one-predicate `DockTabID.includes` pattern).
- **Phase 4 — Unify local overlay.** Fold `LocalPinnedDisplaySnapshot` into overlay + last-known `orderKey`, rehydrated through the single presentation mapping.
- **Phase 5 (ideal, cross-repo) — Upstream fidelity.** `codex-rs` app-server emits `updated_at_ms` + stable tiebreak on the v2 `Thread`; the relay's arrival-rank bridge retires and `orderKey` gains full ms fidelity for free. **Not a hard dependency** — the relay synthesizes `orderKey` from app-server arrival order today.

## 7. Verification / proof strategy

- **One end-to-end conformance harness** drives the *real* relay engine and the *real* client decoder across the full windowed lifecycle (subscribe → catch-up → `complete:true` → live delta → resync), asserting order + row text on **production-shaped data**.
- **Fixtures derive from the schema's "live profile"** (message-specific fields absent) — killing the fixture skew that hid the bug.
- **Parity harness extended** to consume catch-up to completion and to cross the relay-JSON→Swift boundary (today it stops at window 0 and never compares relay-vs-client).
- **Invariant**: there exists exactly one comparator and one projection function; a test asserts no second ordering/projection site exists (structural, not lint — e.g. the comparator is the only `Comparable`/sort entry point the store exposes).

## 8. Existing owner paths to adopt vs retire

**Adopt/extend:** relay SQLite state engine (the authority); the windowed stream envelope; `RenderCoalescer` + off-main projection + debounces + detail windowing (sacred perf); detail-header-as-faithful-subset-of-row (`ThreadDetailStore.swift:61-83` — the template for all consumers); the one-predicate Agents/counts pattern (`CODEX_DOCK_AGENTS_TAB_LIVE_COUNTS`); upstream's TS-schema-as-source; bounded text caps + lazy detail fetch.

**Retire:** client-side ordering (`DockSessionTable.sortedSessions`, `messageUpdatedAt` key); the dict-as-ordering-mechanism; the two `SessionSummary` builders + REST `SessionSummaryMapper` on the Dock path; `messageSummary`/`messageUpdatedAt` as client sort/display authority; 3 status enums + mappings + re-expansion; the legacy direct `thread/list` Dock ingestion path; `LocalPinnedDisplaySnapshot` as a frozen projected row; per-reconcile positional `dock_order` churn; always-populated test fixtures.

## 9. Rejected alternatives

- **"Client owns order with one mandatory non-null key + single comparator" (no wire rank).** Simpler wire, but the client still owns ordering logic (the thing that drifted), and cross-host merge + cross-reconcile stability aren't free. Rejected in favor of relay-owned `orderKey`.
- **"Client preserves relay array order, no key."** Fails multi-host merge — each host is a separate stream; array order can't be merged deterministically. Rejected.
- **"Lint/CI rules that assert the two definitions match."** This is exactly what the user ruled out, and the 2026-05-28 doctrine proves rules don't hold. Rejected for schema-as-source + conformance.
- **"Backfill `messageSummary`/`messageUpdatedAt` via `ThreadSummaryCache` into the state path."** Treats the symptom (fill the invented fields) not the disease (two competing recency concepts). Rejected; collapse to one resolved `summary` + `orderKey`.
- **"Relay mirrors full turn history in SQLite."** Violates the bounded-payload promise; `turn_cache` is deliberately inert. Rejected.

## 10. Risks / open questions (to converge with GPT 5.5 xhigh)

1. **`orderKey` cross-host sub-second semantics.** My tiebreak `(updated_at, host_id, thread_id)` is deterministic but means a tied second sorts all of host A before host B. Honest and flicker-free, but is it the right product semantic, or do we want relay-receipt-time as a secondary signal (risking reconnect flicker)? **Need GPT's stress test.**
2. **Schema-as-source mechanism.** TS schema + Swift codegen vs JSON Schema + both-sides codegen vs one shared file + mandatory conformance test. What's the *minimal* mechanism that makes wire drift a build failure without overbuilding codegen?
3. **Upstream ms fix: hard dependency or future ideal?** I lean bridge-now/upstream-ideal.
4. **Ordered store vs sort-by-key-on-project.** I lean a single pure comparator (keep dict for O(1) lookup) for clarity; ordered store is an optional optimization.
5. **Recency semantic confirmation.** "Newest activity" = thread `updated_at`; note upstream gates `updated_at` bumps to turn-boundary events (`extract.rs:33-43`), so an actively-streaming thread may not float until a gating event. Acceptable? **Product decision.**
6. **Scope of host-alias dedup and archive-order unification** — I lean both in-scope under the single-identity / single-orderKey principle.

## 11. Evidence read (paths + why it mattered)

- `CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md`, `..._IPHONE_UX_SPEC_2026-05-27.md`, `README.md` — product model, row/ordering/connectivity contracts, scale evidence.
- `CODEX_DOCK_CLIENT_ORDER_ROOT_CAUSE_2026-05-30_WORKLOG.md` — live probe (1629/1629 null message fields), the six contract questions.
- `DockSessionTable.swift`, `DockSessionProjection.swift`, `DockRenderProjector.swift`, `SessionRowProjector.swift`, `DockStreamDTO.swift` — the client split: unordered dict, two re-sorts, null-keyed projection, no rank field.
- `dock-relay-state-{engine,store,views,subscriptions,snapshot}.mjs`, `dock-relay-constants.mjs` — relay is the authority; `dock_order`, windowing, byte caps, incremental diff; `messageUpdatedAt`/`messageSummary` never populated on the state path.
- `codex/.../v2/thread_data.rs`, `.../thread.rs`, `thread_processor.rs`, `threads.rs`, `rollout/src/list.rs`, `state/src/extract.rs` — upstream ms-internal/seconds-on-wire truncation, multi-sourced `updated_at`, tiebreak mismatch, single-owner preview/title projection.
- `RenderCoalescer.swift`, `DockScreenStore.swift`, `ThreadDetailRenderProjector.swift`, `CodexDockConstants.swift`, `ResponsivenessContractTests.swift` — the sacred perf invariants.
- `DockStoreTestSupport.swift`, `DockStoreStreamTests.swift`, `dock-relay-state-parity.mjs`, prior consensus `round-01/*.jsonl`, `CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md` — fixture skew, no boundary-crossing test, recurrence of the bug despite prior doctrine.

## 12. What I need from GPT 5.5 xhigh to converge

Adversarial pressure on three load-bearing claims before I'd sign "cannot imagine more perfect":
1. **Does the `orderKey` total-order truly eliminate drift, or does "client compares opaque tokens" smuggle a policy back in?** — especially cross-host sub-second determinism and incremental stability.
2. **What is the minimal schema-as-source mechanism** that makes wire drift mechanically impossible (build failure), without overbuilding codegen infra?
3. **Is full server-side projection collapse (status/summary/origin) safe** against any genuine client-only need (offline rehydrate, localized formatting, A/B of LLM titles), or must a thin seam remain?

**Honest signoff status: not yet at "cannot imagine more perfect."** I am highly confident in the core (relay-owned single projection + explicit globally-comparable `orderKey` + faithful client + production-shaped conformance). Three things must firm up first: (1) the cross-host `orderKey` tiebreak semantics validated against product intent, (2) the schema-as-source mechanism chosen, and (3) confirmation that full server-side projection doesn't strand a real client-only need. Resolve those with GPT and the user and I believe this converges to a genuinely beautiful single-source design.

---

I'm ready to receive GPT 5.5 xhigh's first pass for critique and convergence. I have **not** written the final doc yet, per the process.