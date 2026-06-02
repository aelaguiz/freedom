I've now confirmed both specifics against live code and the active bug doc. Two findings sharpen my answer:

- The `SystemHealthProjector` is **already mid-fix** in the working tree — `.partial` now maps to `.notChecked(...)` (lines 78–79), not the `.degraded(...)` the bug doc recorded. So the row-window→global-degraded conflation is real, reproduced, code-confirmed (bug doc H6; anchors `ThreadCardTable.swift:428-435`, `AppConnectivityStore.swift:610-616`), and being patched point-wise — which is exactly why the *law* must land in the canonical doc to stop regression.
- The same bug doc shows the proof path itself drifting (`sim-ui-dump` produces an `app` field the schema rejects) **and hanging** in the precise UI state under test. A proof tool that fails-open or hangs is itself a side door.

Here is my convergence position.

---

## 1. Do I accept the synthesis?

**Yes — conditionally.** The eleven points are the correct canonical shape, and the synthesis resolves both of my hard divergences (one generic `ProjectionStore` vs. shared-core; repo-wide strict concurrency) toward their lean forms **without abandoning the bug-class-killing invariants**. I withdraw the maximalist framing of Divergence 1 and Divergence 2.

But the side-door for points **6** and **11** lives in their *unstated enforcement*, and point **1** inherits a documented stale-status hazard. As written at the bullet level, those three would let drift back in. My acceptance is conditional on the blockers below being written into the doc.

## 2. Blockers (each is a side door or a second-truth path unless the doc states the fixed wording)

**B1 — "One apply law" (point 6) is non-canonical until bound to ONE proof.** "Generic store OR shared-core + typed tables" is acceptable *only* if the law is bound to a single parametrized test suite that drives the **real production apply entrypoint of all three views** (Dock, Archive, Thread Detail), **plus** a repo gate forbidding any view-facing store from keying / sorting / deduping / merging / revisioning rows outside the shared core. Without both, "one law" is aspirational and Dock can quietly satisfy six of the seven rules. The law = identity-plan Law 3's seven rules **plus** the reconciler generation rules. The binding artifact is the shared test suite, not the prose.

**B2 — Strict concurrency (point 11) must be a HARD gate on the three layers NOW, with a CLOSED quarantine.** "Target" is too soft and re-opens the data-race class. Required: state/projection/runtime compile under `strict-concurrency=complete` with **zero `@unchecked Sendable`, zero raw locks** as a build gate today; the quarantine is a **closed, enumerated, count-fixed allow-list** — name them (URLSession/WebSocket transport, `AVAudioEngine`/voice capture, stream-connection continuations) — each wrapped behind an actor so only `Sendable` value types cross into the isolated layers, and covered by ThreadSanitizer in CI. The gate fails if a new `@unchecked Sendable` or raw lock appears outside the list. Quarantine = the FFI edge only, never the layers above it.

**B3 — Single recovery path / no Task-as-mutex (points 3, 7).** This is the headline wedge and must be made unrepresentable in wording, not just "serialized." Required invariant: relay-detected gaps, client-detected gaps, Dock-row invalidation, foreground resume, reconnect, heartbeat timeout, and sequence gaps are the **same intent into the same engine queue**; overlapping intents during an in-flight generation are **coalesced into a pending bit — never dropped, never silently downgraded to a stale screen**; and catch-up readiness is an **explicit enumerated lifecycle state that is NEVER gated by "a recovery `Task` is non-nil" or "`isBuffering == true`."** That exact gate is the confirmed wedge (§0.6.4 steps 8–13; model-a-final lines 3–6). If the doc doesn't prohibit it *by name*, the wedge stays representable.

**B4 — Proof oracle stays singular (point 10).** The new generative/adversarial and recorded-replay tiers must not smuggle in a second acceptance oracle. Required: the **sole acceptance oracle is the relay's retained projection witness from the same run** (identity-plan Law 7). For pure Swift reducer unit tests where no relay runs, the expected set must be produced by the **canonical relay projection engine run headless** over the same scripted events (or engine-generated fixtures) — **never** by a hand-written second implementation of the apply law (that would defeat B1), and **never** by locally minted `projectionID`s (identity-plan Phase 5). One law produces truth everywhere.

**B5 — Doc positioning must subordinate stale status (point 1).** Folding into the live-update doc is correct, but that doc already warns (§0.7) that later sections falsely say "implemented/closed." Required: (a) the runtime architecture lives in **one demarcated section** (e.g. extend §0.6 with §0.6.8 "Canonical Client Runtime Architecture") that explicitly supersedes all conflicting later text; (b) front-matter `status:` is updated so the runtime work reads as planned/in-progress, not implemented; (c) §0.7 is extended to name the new section as the authority; (d) the identity-drift plan's "do not implement until approved" status is reconciled — either folded in as the identity pillar with status updated, or linked as the binding identity spec with the relationship stated — so the two documents cannot contradict. Otherwise a 2026-06-01 "implemented" section remains citable as proof of doneness.

## 3. Exact wording changes I require

**W1 — Name the engine once.** The synthesis says "StreamSyncEngine / StreamReconciler" — two names for one owner is itself the vocabulary drift this whole effort fights. Pick one (I recommend **`StreamReconciler`**) and state: *"There is exactly one `StreamReconciler` per visible stream key, keyed by `sourceHostID + view + scope + viewParamsKey` — the same key the witness oracle uses — and its lifecycle is tied to that key."*

**W2 — Add the orthogonality law to the freshness lattice (point 9).** Insert: *"Row-window completeness (e.g. `Showing 250 of 964`) is a Dock data-window fact, not connectivity or feature health. It must not by itself make global connectivity `partial` or any System Health category `degraded`. A category is `degraded` only on direct failed/degraded/stale **route** evidence for that category."* Cite `docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md` (H6). Note the projector point-fix is already in the working tree; the upstream Dock-window→global-`.partial` conflation in `AppConnectivityStore` still needs closing, so the **law** belongs in the doc.

**W3 — Tighten the render-only law (point 4).** Add: *"UI render paths are render-only over the projection snapshot. A view must not run an imperative refresh that can drop visible or interaction state — e.g. `UICollectionView.reloadData()` on every update, which closes open swipe actions."* Evidence: same bug doc, H1 (`DockPinnedViews.swift:310-320`).

**W4 — Put the proof harness itself under contract (point 10).** Add: *"The proof tooling is itself under contract: the `sim-ui-dump` producer and `contract/proof/sim-ui-dump.schema.json` may not drift (a regression test locks producer↔schema), and every proof/dump path is watchdog-bounded so it fails loudly rather than hanging."* Evidence: same bug doc — `sim-ui-dump` emitted a schema-rejected `app` field and the dump XCTest hung in the exact state under test. A proof path that fails-open or hangs is a side door.

**W5 — Make intents idempotent, not just serialized (point 3).** Add the word *idempotent*: replaying or coalescing the same intent must converge to the same state, so a reconnect storm or a duplicated invalidation cannot multiply work or rows.

---

**Net:** Accept the eleven points. B1 and B5 are the non-canonical / second-truth risks; B2, B3, B4 are the side-door risks; W1–W5 are completeness. With B1–B5 written in and W1–W5 applied, the synthesis is canonical and closes the side doors the bullet-level wording currently leaves open. No remaining disagreement on architecture — only on enforcement language.
