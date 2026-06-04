Both verifications are decisive and they split the disagreements cleanly — one goes to Model B, one stays with me, and Model B's best catch actually reinforces my side. Here is my convergence review.

---

# Model A (Opus 4.8) — Round-1 Review of Model B

## Agreements (we independently converged on most of the architecture)

1. **Owner = `DockScreenStore`.** Both of us reject v0's three-product split. Model B says "DockScreenStore becomes the single presentation publish owner"; I say the same. `DockStore` stays the data/action owner.
2. **Delete the all-row payload from the live path:** `dockScreenValue`'s `rowValues=` build, `dockAutomationRows`, `automationEncoded`. Identical.
3. **Compact root accessibility value carrying a revision** (`loaded; rows=…; revision=R; automationRevision=R`). Identical — and both of us use it as the drift-closing anchor.
4. **Test-only `DockAutomationSnapshotStore`, keyed by accepted render revision.** Same name, same idea.
5. **Single Dock row oracle, no fallback parser.** Both insist on no dual oracle.
6. **A publish gate so heartbeat/no-change events produce zero new render state.** Same goal.
7. **Update README.md:596-597.** Same.
8. **Rejected alternatives align:** heartbeat-only throttle, "only remove rowValues," dual oracle — both reject all three.

## Disagreements and how the evidence resolves them

### 1. Automation proof route → **I concede to Model B: app-container JSON file, not a hidden accessibility element.**

I leaned hidden-element to minimize harness churn; Model B argued JSON file. The evidence backs Model B decisively:

- The proof processor **already consumes file artifacts** and does **not** parse accessibility itself: `dock-relay-simulator-ui-sync-proof.mjs` takes `--relay-report` (JSON) and `--ui-samples` (JSONL) via `readJSON`/`readJSONL`, and reads rows from `sample.dockRows[]`. So a file-based row source is the *native* shape.
- **App-side writes to `Application Support/CodexDock/` are established**, not net-new: `RelayDiscovery.swift:226` writes `relay-config.json` atomically; `LocalThreadMetadataStore` writes there too. A test-mode snapshot file extends an existing pattern.
- **Revision keying is already mechanical:** `DisplayedUICaptureSupport.dockRootRowCount` (`:625-634`) already parses `rows=` from the semicolon root value; `.mjs` has `parseSemicolonValue`. So "read compact root → get revision → read file → assert `file.revision == displayed revision`" needs no new parsing machinery.
- It eliminates my own stated risk (XCUITest reading a 469 KB single element / chunking) and keeps the invariant clean: **zero bulk data ever in the accessibility tree, in any build.**

My one hard requirement to preserve strictness: the compact root value (read from the **live** accessibility tree) still anchors the proof to the running UI's revision; the file supplies row detail for that revision; the proof **fails loud** if the file is missing or `file.revision ≠ live revision`. That replicates today's "fails loud, not a visual scrape" guarantee. Migration is localized to one function — `DisplayedUICaptureSupport.captureDisplayedUISample` swaps `dockRowsFromRootValue(root)` for `dockRowsFromSnapshotFile(revision)`; the `.mjs` proof and `contract` schema need no change.

### 2. UI state: mandatory `DockRowWindow` now → **I hold (keep full arrays), and Model B's own catch proves it.**

This is the one place I push back, on evidence. The deciding question is: *after* removing the accessibility payload, what main-thread work still scales with total rows? The inventory came back with **exactly two touches**:

- `dockScreenValue`/`dockAutomationRows` — being deleted.
- `syncSelectedDetail` (`DockView.swift:898`): `snapshot.rows.first(where:)` — O(n), but a **one-line fix to an O(1) dictionary lookup**, and only when a detail is open.

Everything else is bounded: `contextualHostStates`/`currentHostState` scan `hostStates` (host-count, not rows); `shouldShowPinnedBodyDivider` scans `groups` (group-count). Rows render via `LazyVStack { ForEach(projection.rows) }` (`:1020`, `:1243`) — SwiftUI materializes only visible+buffer rows; `dock.main_publish` is ~1 ms even today at 1,247 rows, so the full-array `ForEach` identity diff is already cheap.

So a windowed data model is **not required** to bound main-thread cost — the entire O(total) surface is two deletable/indexable touches. Mandatory windowing would instead:
- introduce a `DockRowWindow` type **plus "show more"/infinite-paging UX** — which Model B itself lists as an unresolved open question (net-new *product* surface from a *performance* fix = the overbuild our bar forbids), and
- make **displayed-set ≠ proof-set**: if the view holds 300 rows but relay has 1,247, the full-row sync proof would assert rows that aren't in the UI's scrollable content, muddying the "displayed UI matches sync" guarantee. Full arrays keep displayed-content == proof-set == model.

**Convergence offer:** I adopt Model B's `syncSelectedDetail` catch as a deletion/replacement item (it's a real O(n)→O(1) win), and I lock the drift-proofing Model B wants via a **regression test** (root value length bounded under 10k rows; no all-row main-thread rebuild on idle/scroll) plus a **named escalation trigger**: *if post-fix device profiling shows `frame.hitch` correlating with row count under LazyVStack, then introduce `DockRowWindow`.* That gives Model B the structural guarantee without paging UX or proof-semantic erosion.

### 3. Change detection: `DockScreenFingerprint` (B) → **I hold: `Equatable`-first**, with a correctness argument, not just a simplicity one.

- A fingerprint is a hash, and **hashes collide**. In a sync-proof-critical Dock, a collision silently drops a real update → displayed UI diverges from sync truth — the exact failure the strict proof exists to prevent. `Equatable` is exact.
- `Equatable` **short-circuits on first difference** (often cheaper than hashing every row, which must touch every byte).
- The fingerprint's only theoretical win is O(1) storage of the "last" key — but we already hold the last `.loaded` render snapshot in `state`, so storing the last accepted `(DockSnapshot, options)` is free. The advantage evaporates.
- Gate **before** projection on `(DockSnapshot, options)` (projection is a pure function of those — local collapse state is view `@State`, not projection input), which skips the off-main projection too; Model B's post-projection fingerprint still pays projection on every heartbeat.
- Escalation if equality ever profiles hot at extreme counts: a **per-row cached hash compared first, exact compare on hash-equal** — never a bare hash gate. Exactness is non-negotiable here.

### 4. Owner shape: new `DockPresentationPipeline` (B) → **fold the gate into `DockScreenStore`; no second publishing owner.**

We agree on one owner. My only concern is a *sibling* object that also publishes = a duplicate pathway. `DockScreenStore.enqueueProjection` already does exactly the pipeline's job (runs `DockRenderProjector` off-main, then publishes). So the gate + last-accepted memory belong **inside** `DockScreenStore`. If Model B wants the concept named, make it an internal collaborator (e.g., a `planPublish(...)` step), but not a second `@Published` surface. Substance is identical; this just avoids two owners.

## Simplifications I recommend (net reductions vs. both drafts)

- Drop `DockScreenFrame` / `DockRowWindow` from the permanent plan (keep `DockRenderSnapshot` with full arrays). Removes a type and a paging UX.
- Drop `DockScreenFingerprint` (use `Equatable`). Removes a type and a collision risk.
- Don't add a `DockPresentationPipeline` object (gate inside `DockScreenStore`). Removes a sibling owner.
- One funnel: route `publishCurrentSnapshotWithPendingRenames` (`DockStore.swift:551`) and the `DockStore.state` write through the same equality gate, so the optimistic-rename and connectivity channels can't reintroduce no-op storms.

## Repo evidence that decided each call

- **JSON over element:** `dock-relay-simulator-ui-sync-proof.mjs` consumes `--ui-samples` JSONL via `readJSONL` (reads `sample.dockRows[]`, not accessibility); app already writes `Application Support/CodexDock/` (`RelayDiscovery.swift:226`); root revision parse already exists (`DisplayedUICaptureSupport.swift:625-634`).
- **No windowing:** only remaining O(total) main-thread touch after the payload deletion is `syncSelectedDetail` (`DockView.swift:898`), one-line indexable; rows are lazy (`DockView.swift:1020`, `:1243`); `dock.main_publish` ~1 ms at 1,247 rows (worklog `17:57`/`18:08`).
- **Equatable over fingerprint:** all render types already `Equatable` (`DockRenderModels.swift`, `DockModels.swift`, `DockCardProjection.swift`); collision-induced dropped update violates the strict-proof constraint.

## Revised converged proposal

1. **Gate inside `DockScreenStore.enqueueProjection`:** store last accepted `(DockSnapshot, DockProjectionOptions)`; if a new pair is `==`, skip (no revision bump, no projection, no coalescer submit, no publish). Equality-guard `DockStore.state`; route the rename path through the same funnel. (Connectivity liveness is safe: a real freshness change mutates `hostStates` ∈ `DockSnapshot`, so it's not equal and passes.)
2. **Keep `DockRenderSnapshot` with full row arrays.** Delete the accessibility payload; replace `syncSelectedDetail`'s O(n) scan with an O(1) row index on the snapshot. No `DockRowWindow` now; regression test + escalation trigger lock it.
3. **`Equatable`-first change detection.** No fingerprint type; collision-safe escalation documented.
4. **App-container JSON automation snapshot**, written only when UI-testing by `DockAutomationSnapshotStore` keyed by accepted revision; compact root value carries `revision`/`automationRevision`; `DisplayedUICaptureSupport` reads compact root → revision → JSON file, asserts revision match, fails loud. Single oracle.
5. **Deletion story (one oracle):** remove `rowValues=` build + `dockAutomationRows` + `automationEncoded` (`DockView.swift:1090-1134`); remove `dockRowsFromRootValue` element parsing, replace with the file reader (`DisplayedUICaptureSupport.swift:636-662`); update README.md:596-597; the JSON file is the sole Dock row oracle, no fallback; collapse the dual `DockStore.state` write via the equality guard.
6. **Proof gates:** heartbeat/no-change → zero publishes; display-relevant change → publishes; root value length bounded under 10k rows; automation snapshot revision == displayed revision with full projected order; matrix proof passes reading the file; existing `RenderCoalescerTests` constants untouched.

## Sign-off

**Ready to sign off on items 1, 3, 4, 5, 6** — these are fully converged and evidence-backed. **One small decision remains: mandatory windowing now (B) vs. defer-behind-escalation (A, item 2).** The evidence (two-touch O(total) surface, lazy rows, proof-semantic erosion, B's own paging-UX open question) points strongly to **defer**, and I've adopted B's `syncSelectedDetail` fix to close the gap. If Model B accepts no-windowing-now + `Equatable`-first, I sign off on the whole plan. If Model B holds firm on windowing-now, that is the single item to surface to the user — not a blocker on the rest.

I have not edited the living doc or implemented anything; the orchestrator owns the doc.