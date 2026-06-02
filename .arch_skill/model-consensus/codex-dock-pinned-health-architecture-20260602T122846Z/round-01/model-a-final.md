I now have decisive first-hand evidence. The four reads close the loop, and one finding reframes the whole health bug:

**`ThreadCardTable.hostStatus` (lines 422–453) is the crux.** When `complete == false` it returns `.partial("Showing X of Y")` **before even consulting freshness** (line 428–435). But `complete`/`totalRows` and `freshness` arrive as *separate* parameters. So `.partial` is overloaded across six unrelated meanings — "windowed but fresh," "stale," "offline," "error," "refreshing" — and only the windowed one is benign. Everything downstream then treats all six identically: `.partial` → `HostConnectivityPhase.partial` → global `.partial` → every category `.degraded`.

And the projector already knows the honest answer: line 75–76 returns `.notChecked` for passive categories when `.online`, but line 78–79 blanket-`.degraded`s them when `.partial`. The right state already exists; the wrong edge overrides it.

Layout confirms the pinned fix too: body rows are a plain `LazyVStack { ForEach { dockRow } }` (DockView.swift:752–755), pinned rows render the *identical* `dockRowContent` (line 736, 859–865) — the UIKit `UICollectionView` exists **solely for long-press reorder**. Everything else (content, swipe-to-unpin) already works in the pure-SwiftUI path.

I have what I need. Here is my independent first pass.

---

# Architecture Plan (Model A / Opus 4.8 — first pass)

## Thesis: one root cause, stated as the repo's own invariant

All three symptoms are the **same architectural defect**: a fact owned in one place is silently **re-derived or destroyed by an unrelated subsystem**. The repo's own live-update reference already names the fix — **"One Owner Per Fact"** and **"route health is not freshness"** (P1, per the architecture-reference synthesis). The client code violates that invariant in three spots. The elegant fix is to *enforce the existing invariant*, which is overwhelmingly **subtractive** — remove conflation edges, delete a duplicate interaction surface — not add abstractions.

| Fact | Canonical owner | Who currently violates it |
|---|---|---|
| Swipe-open interaction state | the local row interaction surface (`DockSwipeActionRow.@State offset`) | the pinned UIKit bridge destroys it via `reloadData()` on every render |
| Service/route health | relay freshness DTO + `ClientObservabilityStore` route evidence | `ThreadCardTable` re-derives "degraded" from a capped data window |
| Displayed-state proof contract | `contract/proof/*.schema.json` + `proof-report-contracts.mjs` | the Codable producer re-declares fields the schema doesn't know |

---

## Fix 1 — One Dock row interaction surface (kills the pinned-unpin class)

**Problem (first-hand, `DockPinnedViews.swift`):** Pinned rows use `DockPinnedReorderCollectionView`, whose `updateUIView` calls `collectionView.reloadData()` + `invalidateLayout()` + `layoutIfNeeded()` on **every** SwiftUI update while `!isMoving` (lines 310–321). Any live Dock delta, height callback, or health tick reloads the list and closes the open UIKit swipe action → "menu appears then disappears." Body rows never have this because `DockSwipeActionRow` owns its `offset` locally and resets **only on semantic identity change** — `row.id`, `row.isPinned`, `resetToken` (lines 42–50), with explicit comments forbidding render-driven resets (lines 99–105).

**Architecture:** Pinned rows render through the **same** `dockRow(...)`/`DockSwipeActionRow` path as body rows, in a `LazyVStack`/`ForEach`, identical to DockView.swift:752–755. The UIKit bridge (`DockPinnedReorderCollectionView`, `PinnedCollectionView`, `Coordinator`, the long-press recognizer, the height-measurement loop) is **deleted**. The swipe surface owns its own interaction state and is immune to render/stream churn by construction.

**Reorder** — the *only* capability that justified UIKit — is re-homed without a render-churning container:
- **Preferred:** a SwiftUI long-press-then-vertical-drag reorder mode on the same row stack, local-state owned, committing only on drag-end via the existing `store.reorderPinnedRows(_:)`. Gesture arbitration by axis (horizontal short drag = swipe; vertical drag after long-press = reorder) — one arbiter, replacing the current two-recognizer delegate that returns `false` (the H2 conflict).
- **Fallback if SwiftUI drag-reorder proves fragile inside the outer ScrollView:** an explicit **Reorder mode** toggled from the pinned header that swaps the section into a SwiftUI `List{ }.onMove` *only while editing*; normal mode keeps the stable `LazyVStack`. Two render modes, but neither churns during normal swipe use.

**Owner paths:** `DockView.swift` (`projectedContent`, `dockRow`, `dockPinnedRow`), `DockPinnedViews.swift` (`DockSwipeActionRow`, `DockPinnedSectionView`; delete the UIKit representable). Pin/unpin persistence is untouched (`DockStore.setPinned` → `LocalMetadataEngine`).

---

## Fix 2 — Separate "data completeness" from "service health" at the source

**Problem (first-hand, `ThreadCardTable.hostStatus`, lines 422–453):** `if !complete { return .partial("Showing X of Y") }` fires *before* freshness is consulted. A fully-fresh, intentionally-windowed snapshot is emitted as `.partial`, indistinguishable from a `.stale`/`.offline` freshness failure. That single overloaded value propagates: `AppConnectivityStore.record` maps `.partial` → `HostConnectivityPhase.partial(message)`; `rollup` → global `.partial("Home: Showing 250 of 964")`; `SystemHealthProjector.fallbackStatus` (line 78–79) → every category `.degraded`.

**Architecture (three subtractive cuts, no new types — the right states already exist):**

1. **Window-completeness is Dock-only and never escalates.** In `hostStatus`, a windowed snapshot whose freshness is `.fresh` returns `.loaded` plus a *completeness annotation* ("Showing 250 of 964") surfaced only in Dock. Only freshness-derived states (`.stale`/`.offline`/`.error`) produce a connectivity-affecting status. This restores "route health is not freshness": the relay-owned freshness DTO is the single source for health; `complete`/`totalRows` is a separate Dock fact. (`complete` and `freshness` are *already separate parameters* — this is a clean output-side split.)

2. **System Health is strictly route-evidence-based.** Delete the `fallbackStatus` edge that maps global `.partial` → category `.degraded` (SystemHealthProjector.swift:78–79). With no route evidence, a category is **`.notChecked`** (the state already used at line 76), never `.degraded`. A global connectivity/transport status must not manufacture per-feature degradation.

3. **Fetch evidence on open.** `SystemHealthView` gains a `.task{ await store.refreshRelayDiagnostics() }` so categories reflect real per-route evidence instead of a fallback; until evidence lands they show `.checking`/`.notChecked`. The manual "Run check" button stays as a refresh, not the only path.

**Owner paths:** `ThreadCardTable.hostStatus` + `DockHostLoadStatus` (`DockModels.swift`) for the window/freshness split; `AppConnectivityStore.record`/`rollup` (the completeness→connectivity edge dies once `hostStatus` stops emitting benign `.partial`); `SystemHealthProjector.fallbackStatus` (remove the bad edge); `SystemHealthView` (on-open fetch). Route-evidence owner stays `ClientObservabilityStore`/`RouteDiagnosticSnapshot`/`ObservabilityRouteStatus`.

---

## Fix 3 — Make the proof contract un-driftable and add the missing proof *type*

**Problem (agent-mapped, confirmed shapes):** (a) `DisplayedUIAppMetadata` encodes `configuredBuildNumber`, but `contract/proof/sim-ui-dump.schema.json`'s `app` object is `additionalProperties:false` with only `bundleIdentifier` — drift invisible until a non-nil build number is produced. (b) The over-time harness exists (`DisplayedUICaptureSupport.DisplayedUISample`, `CodexDockDisplayedSyncProofTests`, paired via `dock-relay-simulator-ui-sync-proof.mjs`) but there is **no interaction-survival proof** — exactly the pinned bug class is unproven.

**Architecture:**
1. **Producer ⊨ schema contract test** in the proof-contracts owner (`scripts/proof-report-contracts.mjs` + a fast Swift/encode round-trip) so the Codable producer and JSON schema cannot drift silently — fail in fast CI, not at sim-dump time. Decide once whether `configuredBuildNumber` belongs in the contract and encode that decision in the schema.
2. **Interaction-survival proof** extending the canonical over-time harness (not a new framework): open a pinned-row swipe action, replay/inject a live Dock update through the existing relay-paired driver, and assert the `Unpin` action stays present across samples. This proves Fix 1 and locks it against regression.
3. **Health-classification proof:** a `SystemHealthProjector` unit test asserting a capped-window-but-fresh host yields `dockFeed` healthy/annotated and `threadDetail/archive/voice/diagnostics` = `notChecked` (never `degraded`), plus the inverse for genuine `.stale` evidence.

**Owner paths:** `contract/proof/*.schema.json`, `scripts/proof-report-contracts.mjs`, `CodexDockUITests/DisplayedUICaptureSupport.swift` + `CodexDockDisplayedSyncProofTests.swift`, `CodexDockTests/SystemHealthProjectorTests.swift`.

---

## Evidence read and why it mattered
- **`docs/bugs/...-2026-06-02.md`** — the authoritative symptom/root-cause record; defines scope (no physical device) and the two bug classes.
- **`DockPinnedViews.swift` (full, first-hand)** — proved the duplicate interaction path and the exact `reloadData()`-on-every-render line (310–321), and that `DockSwipeActionRow` already embodies the correct "reset only on semantic change" discipline (40–50, 99–113).
- **`ThreadCardTable.hostStatus` 422–453 (first-hand)** — proved `.partial` is emitted for benign windowing *before* freshness is read, and that completeness vs freshness are already separate inputs. This is the precise, minimal cut point for the health fix.
- **`SystemHealthProjector.swift` (full, first-hand)** — proved the bad `.partial→.degraded` fallback (78–79) and that `.notChecked` is already the correct no-evidence state (76). The fix is removing one edge, not adding machinery.
- **`SystemHealthView.swift` 1–115 (first-hand)** — proved no on-open evidence fetch; "Run check" is the only path (49–58).
- **`DockView.swift` 700–869 (first-hand)** — proved body rows are `LazyVStack`+`DockSwipeActionRow` and pinned rows host the *identical* `dockRowContent`; reorder is the sole reason for UIKit.
- **Architecture-reference synthesis** — supplied the governing vocabulary/invariants (One Owner Per Fact; route health ≠ freshness; freshness states `fresh/stale/partial/offline/unknown`; over-time proof). This is why my plan *enforces an existing invariant* rather than inventing one.
- **Proof-surface map** — located the schema/producer drift root cause and the canonical over-time harness to extend.

## Existing paths/patterns to adopt
- `DockSwipeActionRow`'s local-state + semantic-reset discipline → the single row interaction surface.
- Relay freshness DTO as the sole health owner; `ClientObservabilityStore`/`RouteDiagnosticSnapshot` as the sole route-evidence source; `SystemHealthCategoryStatus.notChecked` as the honest no-evidence state.
- The `DisplayedUISample` over-time proof harness + `proof-report-contracts.mjs` validation, extended (not replaced).

## Alternatives rejected
- **Keep UIKit, switch to `UICollectionViewDiffableDataSource` + guard-while-swipe-open.** Smaller diff, but preserves the duplicate interaction path, divergent accessibility shape, the long-press/swipe recognizer conflict, and the height-measurement loop. Violates "remove duplicate interaction paths instead of adding another workaround."
- **Suppress `reloadData()` during live updates only.** A tiny tweak; leaves the conflation in place and re-breaks on the next update source. Explicitly the "tiny tweak" the user rejected.
- **Add a new "completeness" enum/type or a new health subsystem.** Unnecessary — `complete`/`totalRows` already exist separately and `.notChecked`/`ObservabilityRouteStatus` already model the states. A new abstraction fails the "existing owner can absorb it" bar.
- **Auto-run full route checks aggressively / probe all routes on launch.** Over-built; on-open fetch in System Health + honest `notChecked` is sufficient and matches "route health is diagnostics, not freshness."

## Risks / open questions
- **Reorder ergonomics in pure SwiftUI** inside the outer ScrollView is the main implementation risk — drag-reorder vs. swipe gesture arbitration, and autoscroll. Preferred vs. fallback (edit-mode `List`) is a real decision.
- **Does any legitimate consumer rely on windowed-`.partial` as a signal today?** Need to confirm nothing outside Dock depends on "Showing X of Y" being connectivity-partial before severing the edge.
- **On-open `refreshRelayDiagnostics` cost/latency** and whether it should be debounced or cached.
- The reference docs are point-in-time; I should confirm the freshness DTO fields (`DockStreamFreshnessDTO.status/lastError`) still match before finalizing.

## What I need from Model B (GPT-5.5) to converge
1. Agreement on the **unifying thesis** (One Owner Per Fact) so the plan reads as one architecture, not three patches.
2. A position on **reorder**: SwiftUI drag-reorder vs. explicit edit-mode `List` — and whether deleting the UIKit bridge outright is acceptable, or staged.
3. Whether to express window-completeness as a **field on `DockHostLoadStatus`/`.loaded`** vs. a sibling annotation type — smallest change that keeps Dock's "Showing X of Y" while removing the health escalation.
4. Whether System Health should **auto-fetch on open** or stay `notChecked` until manual check (UX + cost trade-off).
5. Any evidence I missed that argues a capped window *should* ever surface as connectivity degradation.

I did **not** write production code or the final plan doc; per the orchestration the parent writes the converged plan to `docs/bugs/pinned-unpin-menu-and-degraded-health-architecture-plan-2026-06-02.md` after Model B and I align.
