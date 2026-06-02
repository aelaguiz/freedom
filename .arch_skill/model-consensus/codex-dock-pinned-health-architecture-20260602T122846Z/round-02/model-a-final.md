Verification paid off — it surfaced three facts that sharpen the round-2 decisions:

1. **There are two connectivity rollups, not one.** `AppConnectivityStore.rollup` (lines 608/615/621) *and* a parallel `ConnectivityDataEngine`→`ConnectivityRenderProjector` (lines 86/93/99) both independently roll host phases up to global `.partial`. B's instinct to cite `ConnectivityDataEngine` was right. This *validates* severing at the source: fix `hostStatus` and every downstream rollup is fixed regardless of how many exist.
2. **The bug is symmetric in Archive.** `ArchiveStore.swift:378–379` has the identical `.partial(_, message) → .partial(message)` mapping. The reference docs say "Archive is first-class … unified freshness semantics," so the fix must live in the *shared* status type, not a Dock-only patch.
3. **`.partial` has many producers** (`ThreadCardTable` lines 76, 87, 90, 434, 443, 446, 449, 451). A typed split (B's shape) forces every producer to declare its meaning — which is exactly the drift-proofing we want. `reorderPinnedRows` confirmed at `DockStore.swift:218` + `LocalMetadataEngine.swift:106`.

Here is my consensus-ready round-2 answer.

---

# Round 2 — Model A (Opus 4.8): Convergence

## 1. Assessment of Model B

**Architecturally equivalent on the two core fixes, with one part stronger, two parts missing.**

- **Equivalent (full agreement):** remove the private UIKit unpin path; render pinned rows through the same `DockSwipeActionRow`/`dockRow` owner; keep pin persistence exactly where it is (`DockStore.setPinned`/`LocalMetadataEngine`); split the overloaded Dock status; map fresh-windowed → online, not partial; make `SystemHealthProjector` degrade only from route evidence, never a global-partial fallback. Same thesis: **remove the two duplicate meanings.**
- **Stronger than my pass:** B's health *type shape* — `loaded(rowCount, window:)` + `degraded(rowCount, message:)` instead of keeping `partial(kind:)`. That fully removes the overloaded word rather than annotating it. I adopt it.
- **Missing — proof/testing entirely.** B says nothing about the `sim-ui-dump` schema/producer drift, the harness hang in the pinned state, or the absent interaction-survival proof. The bug doc's Fix Plan item 4 puts this in scope. I carry it.
- **Missing — System Health on-open behavior.** B specified "evidence-based only" but not what the screen *does* on open (auto-fetch vs. wait). I resolve it below; it's additive, not conflicting.
- **Net:** genuine convergence, no standoff. I move to B's reorder-mode and type-shape positions; B needs to absorb proof + on-open behavior.

## 2. The four exact choices — resolved

**a) Pinned reorder → explicit reorder mode via native SwiftUI `List.onMove` on a dedicated surface (sheet/pushed screen), launched from the pinned header. Not inline drag. Not staged.**
- Why: the live row surface must survive constant Dock/health updates; that is the North Star. Putting a stateful reorder gesture back on that surface re-creates the gesture-arbitration risk that caused the bug. A dedicated reorder surface has **no swipe**, **no nested-scroll problem**, and reuses Apple's proven `.onMove`/`EditMode` — zero custom drag math. Converges with B, sharpened to "native `List.onMove`, dedicated surface."
- Not staged (no UIKit-behind-a-flag): staging *is* keeping the duplicate interaction path we are deleting. Land the unified swipe surface and the reorder surface in one cutover so pinned rows are never without reorder.

**b) Health shape → adopt B's typed split, applied to the shared status type.** Replace `DockHostLoadStatus.partial(rowCount:message:)` with:
- `loaded(rowCount: Int, window: DockWindow?)` — `window` is an optional **Dock-only completeness annotation** (`{visible, total}` → "Showing 250 of 964"); fresh-but-windowed lands here.
- `degraded(rowCount: Int, message: String)` — service degradation **with retained rows** (stale / offline-with-cache / error-with-cache / reconnecting).
- Keep `checking`, `empty`, `offline`, `error`. **`window` is never read by connectivity; only `degraded`/`offline`/`error` map to a connectivity-affecting phase.** Transient "refreshing/unknown-with-rows" maps to a non-degrading checking phase, not degraded. Because the bug is symmetric, the split lives in the shared type so **Dock and Archive both inherit it**, and every `.partial` producer must reclassify (forcing intent, killing drift). The Dock-facing "windowed" badge is preserved — only its escape into connectivity is cut.

**c) System Health → auto-fetch route diagnostics on open, with honest intermediate states.** `.task { await store.refreshRelayDiagnostics() }` on open; categories show `checking` in-flight, then resolve to evidence-based `healthy/degraded/failed`; **no evidence or fetch failure → `notChecked` / error, never `degraded`.** "Run check" remains a manual re-fetch. Rationale: opening System Health *is* the diagnostic intent — making the user tap again is worse UX and invites the "everything says Not checked, is it broken?" confusion. This doesn't conflict with B's "evidence-based only": auto-fetch *produces* evidence, it never manufactures degradation.

**d) Proof → one canonical, contract-gated surface; no side test path.**
- **Producer ⊨ schema gate in the fast lane.** The schema (`contract/proof/*.schema.json`, validated by `scripts/proof-report-contracts.mjs`) is the single owner; add a cheap test that encodes the actual Swift producer type (`DisplayedUIAppMetadata`) and validates it against the schema, so drift fails in normal CI — not only when `sim-ui-dump` runs on a device with a build number. Decide once whether `configuredBuildNumber` belongs in the contract and encode that.
- **Interaction-survival proof extends the existing over-time harness** (`DisplayedUICaptureSupport`/`CodexDockDisplayedSyncProofTests` + relay pairing) — not a new bespoke test: open pinned swipe → inject a live Dock update → assert `Unpin` stays present/tappable across samples. This is the proof the bug doc says is currently missing.
- **Fast unit tests** on `ThreadCardTable.hostStatus` + `SystemHealthProjector` for the reclassification (windowed-fresh ⇒ dockFeed loaded/online + other categories `notChecked`; genuine `.stale` ⇒ only the matching category degraded), covering **Archive** too.
- A hung/skipped dump is `blocked`, never green (repo invariant). Fix 1 deletes the UIKit collection view that likely contributed to the accessibility-tree blow-up; re-validate the dump in the unified state.

## 3. Agreed architecture (consensus)

**One root cause, the repo's own invariant — "One Owner Per Fact / route health is not freshness."** Three subtractive enforcements:
- **One Dock row interaction surface.** Delete `DockPinnedReorderCollectionView`/`PinnedCollectionView`/`Coordinator`/long-press/height-loop. Pinned rows = body rows = `DockSwipeActionRow` in a `LazyVStack`. Reorder = dedicated native `List.onMove` surface.
- **Completeness ≠ health, at the source.** Typed split of the shared `DockHostLoadStatus`; `window` is Dock-only; only freshness-failure states reach connectivity. Both connectivity rollups and Archive are fixed for free because the leak is cut upstream.
- **System Health is evidence-based and self-fetching.** Remove the global-`partial`→category-`degraded` fallback; auto-fetch on open; `notChecked` is the honest no-evidence state.
- **Proof is contract-gated and over-time**, hung off existing owners.

## 4. Rejected alternatives (joint)
- Keep UIKit + diffable data source / suppress `reloadData()` only — preserves the duplicate interaction path; tiny-tweak class the user rejected.
- Inline SwiftUI drag-reorder on the live surface — re-introduces gesture arbitration on the must-be-stable surface.
- String-match `"Showing "` in System Health — treats a symptom, not the conflation.
- Pause live Dock updates while swiping — the row UI must *survive* updates, not suspend them.
- Fetch all rows to avoid windowing — windowing is intentional.
- New completeness/health subsystem, or unifying the two connectivity pipelines in this plan — over-built; the right states already exist and severing at source fixes all consumers. (Dual-pipeline duplication noted as follow-up, see blockers.)

## 5. Exact implementation phases (no code in this round)
1. **Type split (shared owner).** Redefine `DockHostLoadStatus` (`loaded(window:)` + `degraded`, drop `partial`); update `subtitle`/`isUnavailable`/`isPartial`-consumers; reclassify every producer in `ThreadCardTable` (76/87/90/434/443/446/449/451) and the parallel `ArchiveStore` producers. Done = no `.partial` remains; window info is the only completeness carrier.
2. **Sever completeness→connectivity.** `DockStore.reportDockState:428` and `ArchiveStore:378` stop forwarding window state; only `degraded`/`offline`/`error` produce a connectivity phase. Done = a fresh windowed host reports online in both `AppConnectivityStore` and `ConnectivityRenderProjector`.
3. **Projector + on-open fetch.** Delete `SystemHealthProjector.fallbackStatus` global-`partial`→`degraded` edge (78–79); `SystemHealthView` auto-fetches on open with `checking`/`notChecked`/error states.
4. **Unify the row surface.** Pinned rows render via `dockRow`; delete the UIKit representable; pinned section becomes `LazyVStack`+`ForEach`.
5. **Reorder surface.** Header entry point → dedicated native `List.onMove` (sheet/screen) → `store.reorderPinnedRows`. Land with phase 4.
6. **Proof.** Producer⊨schema fast-lane gate; interaction-survival proof on the existing harness; fast `hostStatus`/projector unit tests incl. Archive; re-validate `sim-ui-dump` in the unified state.

Order rationale: 1→3 (health) and 4→5 (interaction) are independent tracks; 6 locks both. Health track can ship first since it is pure data-flow and lowest-risk.

## 6. Remaining blockers
**No hard blockers to converging the plan.** Three implementation-time validations, not plan blockers:
- Confirm `DockStreamFreshnessDTO` fields (`status`/`lastError`) before coding the reclassification (high confidence already).
- **Flagged, deliberately out of scope:** the two parallel connectivity rollups (`AppConnectivityStore` vs `ConnectivityDataEngine`/`ConnectivityRenderProjector`) are a latent duplicate-meaning. Severing at source fixes the reported bug for both; unifying them is a separate follow-up I recommend recording in the plan, not folding in (avoids kitchen-sink scope).
- Reorder surface as sheet vs. pushed screen is a UX micro-choice for implementation.

I did not edit production files or write the final doc. I believe we are **converged**; what I need from B is confirmation that it accepts (c) auto-fetch-on-open and (d) the proof surface, since those were absent from B's pass — if so, the parent can synthesize the final plan at `docs/bugs/pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md`.
