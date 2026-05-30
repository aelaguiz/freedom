I've reviewed both passes. The good news: on the axis I flagged as the likely real fight (push vs poll), Model A independently chose **push subscription** — so that's settled, not contested. The genuine deltas between us are exactly two: **topology** (A wants a federating coordinator; I wanted per-host + client union) and **disk persistence in V1** (A wants it; I deferred it). Here's my convergence memo.

---

# Model B — Convergence Memo (Round 2)

## Decision table (the 5 axes)

| # | Axis | Verdict | Movement |
|---|---|---|---|
| 1 | Push subscription vs poll-a-snapshot | **Push** — `subscribe`→snapshot, `update`/`delta` notifications, `resync`. | Both chose push independently. **Settled.** |
| 2 | Per-host stream + client union vs coordinator/aggregator | **Per-host streams + trivial client union in V1**, but adopt A's *single-envelope `hosts[] + sessions[]`* shape so a coordinator can be added later with **zero client change**. Federation deferred. | I move toward A's protocol shape; A's federation moves to "deferred, optional." **Converged.** |
| 3 | V1 resync = full snapshot vs delta-replay log | **Full snapshot** on reconnect/gap. Bounded in-memory recent-delta buffer only for catch-up of a briefly-lagging *connected* client; no persistent replay log. | Both agree. **Settled.** |
| 4 | Disk persistence in V1 vs later | **Yes in V1** — one atomic JSON last-good blob per relay, loaded `stale`-on-boot. Defer SQLite / event-log persistence. | **I changed**: defer → adopt. **Converged to A.** |
| 5 | Canonical status/lane; does `notLoaded` leave the wire | **`notLoaded` never crosses the client wire.** Server assigns one canonical `status` badge + `lane: human\|agent` + display-only `kindLabel`. | Both agree on the core; I fold A's split fields into one badge. **Converged.** |

## Where I agree with Model A

- **Push subscription with epoch+seq, baseSeq gap → resync** (axis 1, 3). A's `dock/subscribe / dock/update / dock/resync` and my `subscribe / delta / resync` are the same design. The `baseSeq != current seq ⇒ ignore delta, resync` rule is identical. No daylight.
- **Relay owns everything hard**: provider adapters, Codex decoding, status normalization, last-good, snapshot/delta/resync, retry/backoff, redacted diagnostics. Client renders a clean model.
- **`notLoaded` is killed at the relay** (axis 5). A maps it to `detailAvailability:"cold" + runtimeState:"inactive"`; I map it to `status:"dormant"`. Same intent: it is an internal adapter detail, never a wire value. A relay test ("Codex `notLoaded` never appears on the client wire") is the right guardrail — it's the deliberate inverse of today's pinned `dock-relay-phase5.test.mjs:304-309`.
- **Stable composite session key** (`hostId/provider/providerSessionID`) — A and I wrote the same key, and it's load-bearing for both the single-envelope snapshot and trivial client union (keys are globally unique across hosts, so union is concatenation with no cross-host dedup).
- **Secrets boundary**: OpenAI key, upstream bearer tokens, loopback URLs, `dockRelaySource` stay relay-side; phone holds host/port bootstrap only; `/statusz` redacted; phone cannot select transcription providers. Identical.
- **Migration + simulator-first proof**: add new methods beside raw ones, build the Codex adapter from current relay pieces but flip ownership, move the client, delete client complexity, keep raw detail methods temporarily. Client proof is the simulator (`rtk make app / app-test SIM='iPhone 17'` + the `com.aelaguiz.CodexDock` log assertions). Aligned.

## Where I change my first-pass recommendation

**1. Disk persistence — adopt in V1 (axis 4).** A is right and I was wrong to defer. The top-line goals are *fast startup* and *transient tolerance*, and a relay restart (deploy, crash, reboot) is a transient. With an in-memory-only table, restart means an empty list until the SyncLoop re-warms — and the RCA proves that cold path is 4–6 s for Home (worse on a full drain). That reproduces the exact empty/flicker the project exists to kill, just triggered by restart. Persisting last-good fixes it directly.

I'll constrain the scope so it doesn't sprawl: **one atomic JSON blob of the normalized table per relay, written debounced on `seq` change, read on boot and served immediately with `freshness=stale` + persisted `asOf`, then a `SyncLoop` tick refreshes within seconds.** Bump `epoch` on boot so connected clients resync. This reuses mechanisms we already need (atomic write, the freshness model, `schemaVersion`). **Defer SQLite and any persistent delta/event log** — atomic JSON is enough for hundreds of rows. (This resolves A's own open question "atomic JSON vs SQLite" → atomic JSON for V1.)

**2. Snapshot envelope — adopt A's `hosts[] + sessions[]` single envelope** even in the per-host V1 (where `hosts[]` has length 1). My first pass carried a single `host` per stream; A's multi-host envelope is strictly better because it makes the wire protocol **topology-agnostic**: the client merges `hosts[]`/`sessions[]` across however many sockets it has, and if a coordinator is introduced later, one socket simply carries `hosts[]` of length N with no client change. This is the concession that dissolves most of our topology disagreement.

## What I still hold (and why) — federation in V1

**I reject building the coordinator/peer-federation tier in V1, but I do not reject it forever.** This is the one place I hold against A's first pass, and it's grounded in evidence, not preference:

- **It fights a just-shipped decision.** The repo landed "single endpoint per host" + host-registry automation days ago (`71e8591`, the single-endpoint-per-host goals doc): host identity *is* the endpoint, and relay-reported identity is explicitly "metadata, not to be used to merge endpoints." Federation reintroduces exactly the host-merging that decision removed.
- **It worsens the #1 goal (fault tolerance).** A coordinator is a new single point of failure and a new trust boundary — A's own open questions list "peer federation topology" and "peer auth between relays" as *unresolved*. If the phone's bootstrap/coordinator relay is down, the phone sees *nothing*, even when other hosts are up. Per-host streams give fault isolation for free: Home being slow/down has zero effect on Amir-M5's rows.
- **The benefit is hypothetical today.** The only thing a coordinator buys that per-host+union doesn't is reaching a host the phone has *no direct route to* (NAT/gateway). Everything is on Tailscale with direct routes right now, so that's speculative.
- **It costs nothing to defer.** Because we adopt the single-envelope protocol, a coordinator can be added later as a pure server-side topology change behind the *same* wire protocol, with zero client change.

So I reframe A's "one-stream client" goal: it's about **client simplicity and ownership**, which per-host + trivial union fully satisfies — the union is concatenation of independently-durable tables, *not* the destructive "rebuild from whoever finished" merge we're killing. A's rejected-alternative "client merges snapshots violates the one-stream goal" conflates transport count with merge complexity; with globally-unique keys and per-host last-good, there is no hard merge work on the client.

Net: **federation is a deferred, optional server-side topology, not a V1 component.** This actually *resolves* A's two open federation questions instead of leaving them open.

## The exact target architecture I now endorse

1. **Per-host relay = stateful session-table service.** A background `SyncLoop` (generalizing today's 2.5 s live-status loop) polls the provider adapter for the base/history list + live runtime status, **merges live status onto rows, normalizes status**, diffs against the current table, bumps `seq`, and emits deltas. Failed/slow poll ⇒ keep last-good rows, flip `freshness=stale`, record `lastError`; **never empty the list.**
2. **Last-good persistence (V1):** one atomic JSON blob per relay under `.codex-dock/`; load `stale`-on-boot, bump `epoch`, refresh in background.
3. **Provider adapter contract** (relay-internal): `capabilities / listSessions / liveStatus / readSession / resume|steer|interrupt|archive`. Codex adapter = today's app-server pieces (history `thread/list`, loopback discovery, `thread/loaded/list`, `thread/read`, attention enrichment). Claude Code later = same contract, **zero client change**.
4. **Wire protocol (topology-agnostic, push):**
   - `subscribe { protocol, since?:{epoch,seq} }` → `snapshot { epoch, seq, asOf, freshness, hosts:[…], sessions:[…] }`
   - `update`/`delta` notification `{ epoch, baseSeq, seq, asOf, freshness, upsertHosts, upsertSessions, deleteSessionIDs }`
   - `resync { reason }` → fresh full snapshot. `baseSeq` mismatch ⇒ client resyncs.
   - `heartbeat { epoch, seq, asOf, freshness }` for liveness without row churn.
   - `schemaVersion`/capabilities at subscribe — the versioning the system lacks today.
5. **Canonical session model:** `{ id, provider, hostId, title, preview, repo, cwd, branch, lane:"human"|"agent", status:"running"|"needsInput"|"needsApproval"|"idle"|"error"|"dormant", kindLabel(display-only), lastActivityAt, archived }`. One `status` badge is the SSOT (A's `runtimeState`/`detailAvailability` folded into it; an optional `detailHint` is deferred unless a UX need appears). `notLoaded` never serialized.
6. **Client (thin):** N sockets (one per host), each a `subscribe → AsyncStream<snapshot|delta>`; per-socket table keyed by composite id; **union `hosts[]`/`sessions[]` across sockets** for render; tabs/filters = filter on `lane`; host chrome from host metadata; detail/control on tap. Deletes `makeSnapshot` partial logic, `deduplicated`/`shouldPrefer`, scope fan-out, and `SessionSummaryMapper` Codex decoding.
7. **Three orthogonal axes never collapsed:** host *connection* · table *freshness*(+asOf) · row *runtime status*. "Row availability" ceases to exist — if we have a row, we show it.
8. **Deferred (explicitly):** coordinator/federation tier, SQLite/event-log persistence, cross-reconnect delta-replay log, `thread/* → session/*` rename.

## What the final parent-authored doc should say

The doc should record these as **resolved decisions** (not open questions):

- **Thesis:** relay = stateful per-host session-table service; client = thin subscriber. One topology-agnostic push protocol.
- **Axis verdicts (state each as decided):** (1) push subscription; (2) per-host streams + client union in V1 on a single-envelope `hosts[]+sessions[]` protocol that is coordinator-ready — **federation deferred**; (3) resync = full snapshot, in-memory recent-delta buffer only; (4) last-good **atomic-JSON persistence in V1**, SQLite deferred; (5) canonical `status`+`lane`, `notLoaded` removed from the wire, enforced by a relay test.
- **Component boundaries, relay state model, adapter contract, wire protocol, failure/staleness, security, client responsibilities, migration, tests** — as in §3–§11 of my first pass, amended by the two changes above (persistence in V1; `hosts[]+sessions[]` envelope).
- **Migration:** add new methods beside raw; flip ownership into the Codex adapter; **replace `dock-relay-phase5.test.mjs`'s "notLoaded wins" contract** with "status normalized & live-merged; `notLoaded` never serialized"; move client behind the existing injection seam; delete client complexity; keep raw detail methods temporarily; Claude Code adapter last.
- **Test strategy:** simulator-first client proof (scripted fake relay forces the slow-Home scenario; assert via `com.aelaguiz.CodexDock` logs that selected-host rows survive a stale refresh, deltas apply in place, resync repaints without flicker) + `node --test` relay proof (live-merge/normalization, diff/seq monotonicity, last-good retention + stale on failure, **persistence load-stale-on-boot**, resync→full snapshot, "notLoaded never on wire", schema/golden test).
- **One residual judgment call to note (not block on):** federation timing. Recommendation: defer until a real need (NAT-only host, or host count grows past comfortable socket fan-out) appears; it slots in behind the same protocol. This is the only point where a reasonable architect could choose otherwise, and the doc should say so plainly.

---

**Bottom line:** we converge. I adopted A's V1 persistence and A's multi-host snapshot envelope; A's federation becomes a deferred, optional server-side topology under the shared protocol (which also resolves A's two open federation questions). All five axes now have a single, coherent verdict. The only thing I hold against A's first pass is *building federation in V1* — and I've shown it can be added later with zero client change, so it's a sequencing decision, not an architectural fork. I don't think anything here needs another round; the parent can author the final doc from the decision table above.
