Evidence is complete and cross-verified. Here is my independent first pass.

---

# Model A (Opus 4.8) — First-Pass Architecture

## What the evidence actually proves

I read the worklog, the v0 plan, and the live code paths. The diagnosis is sound but the v0 *plan* is heavier than the evidence justifies. The proven facts:

1. **The dominant cost is one main-thread string build.** `DockView.dockScreenValue` (`DockView.swift:1078-1107`) is attached as `.accessibilityValue(dockScreenValue)` on the Dock header `Text("Dock")` (`:634`). For `.loaded`, it walks **every** automation row (`dockAutomationRows`, `:1109-1129`), encodes each row's `automationValue` and joins them into the `rowValues=` payload — 469 KB / 20-22 ms at 1,247 rows, repeatedly (worklog `17:44`, `18:08`). This is a *computed property read on every body evaluation*, so the cost is paid on **any** observed change, not just new data.

2. **There is no publish gate anywhere, and heartbeats force full republishes.** `StreamReconciler.publish()` increments revision on *every* envelope including `heartbeat` (heartbeats are contractually row-empty — `ProjectionReducer.applyHeartbeat`). `DockStore.handleReconcilerSnapshot` (`DockStore.swift:468-499`) calls `publishSnapshot` on every host snapshot. `RenderCoalescer.submit` (`RenderCoalescer.swift:20-42`) drops only *stale revisions*, never *equal content*. Heartbeat cadence ≤15 s/host + 5 s reconnect ⇒ steady no-op republish storm (worklog: 9 publishes → 36 rebuilds while idle).

3. **Two render-invalidation channels fire per publish.** `publishSnapshot` writes **both** `DockStore.state = .loaded` (`:529`, observed by `CodexDockRootView` via `@StateObject`) **and** `screenStore.publish(...)` (`:530`, the render path `DockView` observes via `@ObservedObject`). `CodexDockRootView.body` doesn't even read `dockStore.state`, yet `@Published` invalidates it anyway → an extra DockView body re-eval → an extra 469 KB build. This is the ~4×-per-publish multiplier.

4. **The data model is already fully `Equatable`.** `DockRenderSnapshot`, `DockSnapshot`, `DockRowViewModel`, `DockCardProjection`, `DockProjectionOptions` are all `Equatable`/`Sendable`. **No fingerprinting or change-detection exists** anywhere. So a content-equality gate is essentially free to express — no new fingerprint type required to start.

5. **The detached pipeline is *not* the problem.** Off-main `dock.render.project` ~8 ms, `data_engine.snapshot` ~9 ms, `card_projection.project` ~7 ms, coalesced. LazyVStack already virtualizes row *views*; per-row `.accessibilityValue(row.automationValue)` (`DockSharedViews.swift:212`) is viewport-bounded. The dataset size hits the user **only** through the root accessibility payload and the publish frequency.

6. **The proof contract is the one real constraint.** `DisplayedUICaptureSupport.dockRowsFromRootValue` (`:636-662`) is the *sole* row oracle: it parses the header's `rowValues=` (split `|`, `id=value`, prefix `codexdock.dock.row.`, percent-decoded). README.md:596-597 elevates this to a documented strictness guarantee ("fails loud … not a visual scrape"). The full-set proof relies on the payload being built from the *model* (all 1,247 rows), which XCUITest could never materialize by scrolling a virtualized list. **This is why we can't "just read per-row elements."**

## Proposed architecture (minimal, two pillars + one non-change)

The target contract: **interaction cost is bounded by visible UI, never by dataset size, and a no-op data event costs nothing.** I reach it by reusing existing owners, not adding a subsystem.

### Pillar 1 — One render-eligibility gate at the single render funnel (`DockScreenStore`)

`DockScreenStore.enqueueProjection` (`DockScreenStore.swift:168`) is *already* the sole funnel for every render request (host publish, `updateOptions`, search debounce). Make it the **single owner of "is this a new rendered screen?"**:

- Store the last *accepted* `(DockSnapshot, DockProjectionOptions)`. On enqueue, if `snapshot == last.snapshot && options == last.options`, **skip**: no revision bump, no detached projection, no coalescer submit, no main publish. Uses the existing `Equatable` conformances — no new type.
- Kill the redundant second channel: guard `DockStore.state = .loaded(displayedSnapshot)` (`DockStore.swift:529`) with an equality check so an unchanged combined snapshot never re-fires `CodexDockRootView`. Route `publishCurrentSnapshotWithPendingRenames` (`:551`) through the same funnel so the optimistic-rename path can't bypass or duplicate the gate.

This is *the* drift-proof structural change: every render request flows through one comparison in one place. A future feature literally cannot reintroduce a no-op publish storm without deleting the gate. `RenderCoalescer` stays (it still drops stale revisions during genuine catch-up bursts) — the gate sits in front of it.

Why equality and not v0's fingerprints: the types are already `Equatable`; `O(n)` row comparison at ~1,247 rows is sub-millisecond-to-low-ms and prevents a 20 ms build plus the whole detached pipeline. Fingerprints are a documented *escalation* if equality ever shows hot at far larger counts — not day-one complexity.

### Pillar 2 — Remove the all-row payload from the live path; move proof out-of-band (test-only)

- **Delete from the hot path:** the `rowValues=` construction in `dockScreenValue` (`:1090-1097`), `dockAutomationRows(in:)` (`:1109-1129`), `automationEncoded` (`:1131-1134`). The header keeps a **bounded O(1)** value: `loaded; rows=N; visibleRows=V; pinned=P; lens=…; search=…; filters=…; revision=R; automation=R`. Production builds never construct the bulk payload at all.
- **Replace the oracle with a test-only automation snapshot.** A small `DockAutomationSnapshotStore` owned next to `DockScreenStore` receives each *accepted* `DockRenderSnapshot` and materializes the structured row payload **once per revision** (memoized), off the interactive path, **only when `CODEX_DOCK_UI_TESTING=1`**. Expose it via a dedicated hidden automation element (stable `AutomationID`, present only in test mode). Keep the **exact `rowValues=` string format** so `dockRowsFromRootValue` changes only *where* it reads (the dedicated element), not *how* it parses. Update README.md:596-597 to name the new source.
- **Strictness is preserved and slightly improved.** Same structured payload, same fail-loud parser, same full row set (derived from the model, so virtualization-independent). New: the bounded header carries `revision=R` and the automation snapshot carries the same `R`, so the proof can assert *displayed revision == automation snapshot revision* — closing the drift door the v0 plan worried about. Per-row `.accessibilityValue(row.automationValue)` stays as a secondary viewport-bounded channel.

### Non-change (explicit) — No data-model windowing, no fingerprints, now

The evidence does not justify windowing: LazyVStack virtualizes views, detached projection is cheap and off-main, `dock.main_publish` is ~1 ms. Keep full row arrays in `DockRenderSnapshot`. Document the escalation trigger: *if, after Pillars 1-2, profiling still shows total-row main-thread layout/diff cost*, introduce viewport windowing — but not before.

## Existing owner path to adopt

- **Render SSOT:** `DockScreenStore` (`enqueueProjection`) — already the funnel; add the gate here.
- **Combined-snapshot producer:** `DockStore.publishSnapshot` — add the equality guard on `state`; fold the rename path into the funnel.
- **Render product:** reuse `DockRenderSnapshot` / `DockSnapshot` / `DockCardProjection` (all already `Equatable`). Do **not** introduce `DockRenderPipeline` / `DockScreenModel` / `DockRenderDataset`.
- **Proof:** new `DockAutomationSnapshotStore` next to `DockScreenStore`; `DisplayedUICaptureSupport.dockRowsFromRootValue` reads the new element.

## What gets deleted or replaced

| Action | Target | Why |
|---|---|---|
| **Delete** | `dockScreenValue` `rowValues=` branch, `dockAutomationRows`, `automationEncoded` (`DockView.swift:1090-1134`) | The 469 KB/20 ms main-thread offender |
| **Delete** | unconditional dual write in `publishSnapshot` (`DockStore.swift:529-530`) | Collapse redundant invalidation; gate by equality |
| **Replace** | header `.accessibilityValue(dockScreenValue)` (`:634`) | Bounded O(1) value incl. `revision` |
| **Replace** | `dockRowsFromRootValue` source (`DisplayedUICaptureSupport.swift:636-662`) | Read dedicated test-only element; parse format unchanged |
| **Update** | README.md:596-597 | Point proof contract at the new automation element |
| **Keep** | per-row `automationValue`, `AutomationID.Dock.row`, `RenderCoalescer`, `DockCardProjection`, `ThreadCardProjectionState` per-host revisions | Already viewport-bounded / correct |
| **Watch (defer)** | `ThreadCardRowProjector` metadata fallback linear scan (O(metadata×rows)) | Off-main, not the proven dominant cost; index only if profiling flags it |

## Proof gates & performance guarantees

- **No-op events cost zero:** unit-test that an equal `(snapshot, options)` → no revision bump, no projection, no main publish; heartbeat with unchanged rows → no render. (Connectivity liveness is preserved because a real freshness change alters `hostStates`, which is *inside* `DockSnapshot`, so it's *not* equal and passes the gate.)
- **Per-event main work is O(visible), not O(total):** assert header value length is bounded (independent of row count); per-row values are viewport-only.
- **Production never builds the bulk payload:** assert that without `CODEX_DOCK_UI_TESTING` the automation element is absent and the header has no `rowValues=`.
- **Proof strictness intact:** sync/scenario/matrix proofs pass against the new element; add the `displayed-revision == automation-revision` assertion.
- **Existing budgets unbroken:** `RenderCoalescerTests.testRenderingConstantsMatchPhaseZeroPlan` still passes (constants untouched). Keep `dock.accessibility_value.built` + frame-hitch probes as permanent regression telemetry; retire high-volume row/scroll samplers.

## Alternatives rejected

- **v0's `DockRenderPipeline` + 3-product split** (`DockScreenModel`/`DockRenderDataset`/`DockAutomationSnapshot`): a parallel render owner beside the existing `DockScreenStore`/`DockRenderSnapshot` — a duplicate pathway, exactly what we're told to reject. Reuse the existing owner + `Equatable` types.
- **Row display fingerprints now** (v0 §2): premature; everything is already `Equatable`. Escalation-only.
- **Gating in `StreamReconciler`** (per-host heartbeat suppression): can't see cross-host equivalence or options-only changes; it's not the rendered-screen SSOT. Acceptable *optional* upstream complement (don't even wake the pipeline on a no-op heartbeat), but the durable gate must live where "rendered screen identity" is defined = `DockScreenStore`.
- **Data-model windowing now:** unjustified by evidence; documented escalation.

## Risks / open questions

1. **`O(n)` equality on the main actor** at extreme counts — fine at ~1.2k; escalate to a cheap row fingerprint if ever hot.
2. **XCUITest reading one large hidden-element value** — may need chunking/paging for very large sets (deferred). This is the main *automation-route* decision: hidden accessibility element (my pick — least proof-harness migration) vs app-container JSON file (zero accessibility-tree cost, integrates with the `.mjs` audit scripts).
3. **`CODEX_DOCK_UI_TESTING` is a new flag** — none exists today (only `CODEX_DOCK_PERFORMANCE_PROFILING` / `CODEX_DOCK_UI_TEST_HOSTS`). Needs app-launch wiring + Makefile proof-target wiring; read once.
4. **Single-channel collapse** — equality-guarding `DockStore.state` kills the no-op channel; fully removing the second channel for *genuine* changes (so one change = one body eval) is a deeper refactor I'd like to converge on, not assume.

## What I need from Model B to converge

1. Agree the **single gate owner is `DockScreenStore`** (reuse `DockRenderSnapshot`/`Equatable`), rejecting the new `DockRenderPipeline`/3-product object.
2. Agree to **equality-guard `DockStore.state`** (kill the redundant `CodexDockRootView` channel) and fold the optimistic-rename path into the one funnel — or propose a cleaner single-channel decoupling.
3. **Pick one automation route:** hidden test-only accessibility element vs app-container JSON file. I lean hidden element; persuade me if JSON is better given the `.mjs` audit + `contract:check` tooling.
4. Confirm **Equatable-first** (no fingerprints) and **no windowing now**, with the documented escalation triggers.
5. Stress-test two claims I'm relying on: (a) suppressing equal snapshots cannot starve **connectivity liveness** (my argument: freshness ∈ `DockSnapshot.hostStates`); (b) the **revision-match** assertion is sufficient to keep the sync proof strict after the oracle moves.

I'm holding here for Model B's first pass — I will not edit the living doc (the orchestrator owns it) and there is no implementation in this phase.