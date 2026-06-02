Confirmed with my own eyes. The stuck-loop mechanism is exactly as suspected, and it's the Rosetta Stone for the whole architecture:

- `ThreadDetailLiveEventBuffer.begin()` sets `isBuffering = true`; `finishReplay()` is the *only* thing that clears it, and it runs *after* the drain loop.
- `replayBufferedLiveEvents()` is `while let batch = takeBatch() { for … await apply() }` — each `await` suspends the `@MainActor` turn.
- During that suspension, the notifications consumer runs `handle(notification:)`, sees `isBuffering == true`, and **appends to the very buffer being drained**.
- Under sustained live traffic (an active turn streaming), `takeBatch()` never returns nil → the loop never terminates → `finishReplay()` never runs → `recoveryTask` never clears → every future `startRehydrateAfterReconnectIfNeeded`/`startDockRowRefreshIfNeeded` is gated off forever. The detail wedges.

The drain set is not fixed at catch-up start; it's a live-extending queue. That's an unbounded-catch-up loop, not a data-identity bug. I have enough grounding to form my independent position.

---

# Model A (Opus 4.8 Max) — First-Pass Architecture

## Central thesis (my independent read)

The repo already has the right *data* idea — **relay-owned projection identity** — and a strong, recent plan to finish it (`CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md`). But every symptom the user is describing is a **client runtime** failure wearing data clothing. There is no single owner of *time, concurrency, catch-up, and freshness* on the client. The stuck-replay wedge is a lifecycle bug. The duplicate rows are an identity bug. The stale-while-live is a freshness bug. The "tests pass while wrong" is a proof-oracle bug. They are being fixed in separate documents, each scoped to exclude the others (the identity plan explicitly defers lifecycle to the live-update reference and rejects the generic store).

**The canonical target is one document that unifies identity + runtime under a single ingestion pipeline, and makes each bug class *unrepresentable* rather than *tested-for*.** Ignoring sunk cost, that means six pillars, each of which converts a bug class into either a compile error, a structurally impossible state, or a loudly-failing invariant.

I diverge from the existing plan in five deliberate places (flagged ⚡ below) because the user explicitly disavowed cost bias and asked for the canonical best, not the minimal cutover.

---

## Proposed architecture — six pillars

### Pillar 1 — One Projection Pipeline (identity)
Adopt the identity-drift plan's spine: `scripts/dock-relay-projection-engine.mjs` is the **sole** constructor of `sourceRef`, `projectionID`, `displayOrderKey`, `rowRole`, `revision`, freshness. Live == canonical (same projection function). Host identity from the `initialize` handshake (`sourceHostID` + `contractFingerprint`); `logicalHostID` retired; `DockHostIdentityResolver` demoted to routing/labels.

⚡ **Divergence 1:** Where the plan hedges ("one apply law, not necessarily one generic table"), the canonical answer *is* one generic client `ProjectionStore<Row>` with one apply law, and Dock/Archive/ThreadDetail become **view memberships** over it. The plan rejects this as "not required to kill the bug class" — true for the *minimal* fix, but the user asked for canonical. Two engines sharing a "core" is two engines that can still drift; one store cannot. (I'll steelman the counter-argument under Open Questions — this is the #1 thing I want consensus on.)

### Pillar 2 — One Concurrency Law (data races)
⚡ **Divergence 2 (biggest, and absent from every existing doc):** Turn on **Swift 6 `strict-concurrency=complete` repo-wide** in `project.yml`/`Package.swift`. The concurrency sweep found it is **off**, with 8 `@unchecked Sendable` types, 3 `NSLock` sites with unlock/re-acquire windows, and a `Task.detached` voice path that can outlive its store. Today every one of those is a developer-discipline promise the compiler does not check.

The law: all view-facing mutable state is `@MainActor`; all ingest/merge/cache is `actor`-isolated; messages crossing boundaries are `Sendable` value types; **zero `@unchecked Sendable`, zero raw locks**. The websocket transport, voice capture, and stream-connection continuations get redesigned to actors. This makes the data-race class *unrepresentable by construction* — the strongest possible invariant, and a precondition for trusting everything above it.

### Pillar 3 — One Reconciler / Lifecycle State Machine (update loops)
⚡ **Divergence 3:** Elevate lifecycle from "deferred to another doc" to a first-class pillar, because the *headline* bug lives here. Replace the per-store ad-hoc pattern (`recoveryTask: Task?` used as a mutex + `liveEventBuffer.begin()/replay/finishReplay`) with **one `StreamReconciler`** shared by Dock, Archive, and every ThreadDetail, built on **generations**:

- Each stream carries a monotonic `generation`. Catch-up = "fetch snapshot at generation N, capture its watermark, apply, then drain only the buffer that existed at begin()." New live events during catch-up go to a **fresh buffer for generation N+1** (double-buffer swap at `begin()`), so the drain set is *fixed at the moment catch-up starts*.
- Recovery is an explicit state (`.catchingUp(generation:)`), not a nilable Task. It is **idempotent and bounded**: it always terminates and always clears, regardless of inbound rate.

**Invariant: catch-up completes in bounded steps independent of live-traffic rate.** The stuck-replay wedge becomes structurally impossible — `finishReplay()` can't be starved because it no longer drains a live-extending queue.

### Pillar 4 — One Freshness Lattice (stale-while-live)
Freshness is **derived, never asserted**, and lives per-row and per-view in the projection envelope + a `FreshnessProjector`. A view may render "Live" only if the conjunction holds: `transport.connected ∧ catchUpComplete(view.generation) ∧ heartbeatWithinBudget ∧ ¬resyncPending`. Any missing conjunct downgrades the badge to `catching-up / stale / offline / error`.

This kills two evidenced bugs at once: (a) `SystemHealthView` that fetches once and never re-subscribes (shows "Offline" after recovery); (b) `SystemHealthProjector` turning a Dock row-window partial (`Showing 250 of 964`) into a *global* degraded health. **Invariant: "Live" is a computed conjunction; row-window completeness is orthogonal to feature health.** Stale-while-live can't happen because nothing can *claim* live without the runtime proving it.

### Pillar 5 — One Contract, validated at both boundaries (relay/client drift)
⚡ **Divergence 4:** `contract/projection/*` is already the canonical schema, but the relay-contract sweep found drift is only *deny-listed in proof reports*, not blocked at the wire. Make the contract **bidirectional codegen + runtime validation**:
- Generator emits **both** Swift DTOs **and** relay encoders/decoders from the schema. Retire hand-written `ThreadDetailDTO.swift` and the generator's hard-coded enum lists.
- Relay validates every outbound message against the schema at send time (fail-closed in dev/proof).
- Swift validates on decode: an unknown enum or malformed `projectionID` becomes an explicit diagnostic-row/resync, **never a silent `.unknown`**.
- `contractFingerprint` handshake gates cache validity and stream acceptance.

**Invariant: a message that violates the contract cannot be emitted by the relay or accepted by the client.** Drift surfaces at the boundary, immediately, on both sides.

### Pillar 6 — One Proof Architecture (tests that pass while wrong)
⚡ **Divergence 5 — directly answering "surface issues like this in testing, where data comes in to capture that":** The existing proof is a *list of scenarios* that samples *lag*. Replace with a **generative + differential + monitored** harness, in three tiers (detailed below). The unifying rules: the **only** expected-state oracle is the relay's **retained projection witness from the same run** (agree with the plan); every invariant from Pillars 1–5 is a runtime assertion (`DockInvariant.assert`) compiled into debug/proof/UI-test builds so the *same* checks fire in unit, simulator, and device. Side doors become impossible because the invariants live in code, checked everywhere — not in a doc.

---

## How it handles each required dimension

| Dimension | Canonical mechanism |
|---|---|
| **Communication** | One JSON-RPC/WebSocket transport (actor), one stream grammar (`snapshot/upsert/delete/heartbeat/resyncRequired`) keyed by `epoch+seq` within `sourceHostID+view+scope+viewParamsKey`. No display `delta`/`card-v2`/`baseSeq`. |
| **Refresh** | Foreground/manual refresh = a generation bump through the *same* reconciler. Dock/Archive get the foreground gate ThreadDetail already has (evidence: gate mismatch in live-update ref). |
| **Catch-up** | Generation + double-buffer; bounded idempotent recovery; drain set fixed at begin(). The one place reconnect/resync/dock-row-advance all flow through. |
| **Identity** | Relay projection engine sole owner; `sourceHostID` from handshake; client never derives identity (Pillar 1). |
| **Lifecycle** | Explicit `StreamLifecycleState` (`idle/loading/live/catchingUp/backgrounded/stale/offline/error`) owned by the reconciler; background pauses retry budget; foreground resumes via generation bump. |
| **UI state** | Render-only SwiftUI keyed by `projectionID`, sorted by `displayOrderKey`; freshness lattice drives badges; no view-local caches that can drift (evidence: detail-sync lag, pinned `reloadData()` closing swipe menus → diffable data source instead). |

---

## Canonical owners and paths to retire

| Canonical owner (new/promoted) | Old paths to retire / demote |
|---|---|
| `dock-relay-projection-engine.mjs` = sole identity/order/freshness | identity logic in `dock-relay-thread-detail-ledger.mjs`, card-building in `dock-relay-state-subscriptions.mjs` |
| Swift `ProjectionStore` (one apply law) ⚡ | dual apply logic in `ThreadCardTable` + `ThreadDetailDataEngine` (fold into typed views over the store) |
| Swift `StreamReconciler` (generations) | per-store `recoveryTask` mutex + `ThreadDetailLiveEventBuffer.begin/replay`; missing Dock/Archive equivalents |
| `FreshnessProjector` (lattice) | scattered per-route freshness; `SystemHealthProjector` row-window→global-degraded conflation |
| `contract/projection/*` + bidirectional codegen | hand-written `ThreadDetailDTO.swift`; generator's hard-coded enums; deny-list-only proof guards |
| handshake `sourceHostID`+`contractFingerprint` | `logicalHostID`; `DockHostIdentityResolver` as identity (→ routing/labels only) |
| Retained-witness oracle + invariant monitors | fixture-minted projection IDs; lag-only sim assertions |

---

## Proof / testability methodology (three tiers)

**Tier 1 — Instant (unit, deterministic, no mocked apply law).**
A **virtual-clock simulation harness**: feed scripted relay event sequences into the *real* `ProjectionStore`/`StreamReconciler` (only the transport is simulated). A **reference model** computes the expected converged set; the client must match identity + order + membership exactly. ⚡ Add a **generative adversarial generator** that searches interleavings — *live-events-during-catch-up, out-of-order seq, duplicate sourceRef, reconnect storms, fingerprint change mid-stream.* The stuck-replay bug would have been a one-line property: "after any interleaving, reconciler reaches a terminal non-`catchingUp` state in ≤N steps." Invariants from Pillars 1–5 assert inside these runs.

**Tier 2 — Simulator/device proof (real app path).**
Keep `sim-ui-dump` + retained-witness comparison, but assert **full ordered-set equality** (row order, message order, membership) — not just lag (the evidenced gap: a permuted list passes today). Run **invariant monitors during every proof**: render/recovery counters that fail if they exceed a bound over a window (catches loops), and a "Live⇒actually-fresh" checker (catches stale-while-live). Replay **recorded real event streams** as deterministic regression fixtures — this is the "data comes in to capture the issue" loop: capture a production-shaped stream once, it's a permanent test.

**Tier 3 — Over-time / long-running regression.**
A **soak harness** driving continuous adversarial live traffic with a **watchdog** tripping on: unbounded buffer growth, a recovery state that never clears, render rate that never quiesces, monotonic memory growth. This is what would have caught the wedge "over time" as the user asked. Strict-concurrency build + Thread Sanitizer in CI closes the data-race tier.

---

## Alternatives I rejected (and why)

- **Swift-side dedupe / patch the symptoms** — treats the duplicate *after* drift; rejected (agrees with plan).
- **Pending-row / optimistic-insert subsystem** — adds a second identity lifecycle the product doesn't need; rejected (agrees with plan).
- **"One apply law via a shared core, two engines"** (the plan's position) — rejected for the *canonical* target: two engines can still drift; one store cannot. (Open for consensus — see below.)
- **Lag-only sim proof** — rejected; it passes on permuted/duplicated rows.
- **Leaving strict concurrency off and relying on `@unchecked Sendable` discipline** — rejected; it makes data races untested-and-uncheckable.
- **A universal `projection_rows` SQLite rewrite as prerequisite** — rejected; cache validity under `contractFingerprint+sourceHostID` suffices (agrees with plan).

---

## Risks / open questions

1. **Generic `ProjectionStore` vs. shared-core (Divergence 1).** Risk of over-abstraction; Dock cards and Detail rows have genuinely different payloads. Is one store elegant or a leaky generic? This is the central tension between "canonical best" (user) and "smallest that satisfies requirements" (quality bar).
2. **Strict-concurrency-complete cost (Divergence 2).** The voice/audio (`AVAudioEngine`) and `URLSession` websocket layers may resist full isolation. Is full repo-wide `complete` the target, or `complete` for the state/projection layer + quarantined `@preconcurrency` islands for AVFoundation?
3. **Generative proof harness (Divergence 5).** Real value, or gold-plating vs. a fixed adversarial scenario list + recorded replay? Where's the line for a tiny team?
4. **Document positioning.** Should the new doc **supersede** the identity-drift plan (fold it in as Pillar 1) or **layer above** it as the runtime umbrella that cross-links it? I lean supersede-by-inclusion to avoid yet another partial doc.
5. **Relay scope.** Bidirectional codegen + send-time validation touches the Node relay materially. In-scope for a "client architecture" doc, or a sibling relay doc cross-linked?

Proposed filename: `docs/CODEX_DOCK_CANONICAL_CLIENT_RUNTIME_ARCHITECTURE_2026-06-02.md`, cross-linked into the identity-drift plan, the live-update & testing reference, the duplicate root-cause, the relay data-contract/lease-drift audit, and the protocol/update reference.

---

## What I need from GPT-5.5 to converge

1. **Take a position on Divergence 1 (one generic store vs. shared-core/two engines).** This is the load-bearing disagreement with the existing plan. If you defend the plan's hedge, show why two engines + a shared law won't re-drift.
2. **Pressure-test Divergence 2.** Is repo-wide `strict-concurrency=complete` achievable given the `AVAudioEngine`/`URLSession`/`@unchecked Sendable` reality, or do we scope it to the state layer? Name the boundary.
3. **Challenge the proof architecture.** Is the generative/differential/soak harness the right canonical proof, or is it heavier than the bug class warrants? Where would you cut?
4. **Confirm or refute that lifecycle (Pillar 3) belongs *in* this doc** rather than staying in the live-update reference — i.e., is unifying identity+runtime in one canonical doc correct, or does it over-couple two concerns?
5. **Anything I under-weighted from evidence you'd read differently** — especially whether the relay-side work should be in or out of a "client" architecture doc.

I read real repo evidence (six parallel sweeps + direct reads of the identity-drift plan, the live-event buffer + replay/recovery code, the projection envelope schema, README/Makefile/package.json) and every claim above is grounded in a cited path. I'm ready to critique your first pass once you've formed it independently.
