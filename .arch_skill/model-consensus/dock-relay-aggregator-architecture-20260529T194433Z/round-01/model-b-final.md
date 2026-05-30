I've now directly verified the three load-bearing facts. Let me confirm what I'm grounding the design on:

1. **Relay keeps no durable snapshot and does not merge live status into list rows.** `aggregateThreadList` (`scripts/dock-relay-thread-data.mjs:457-478`) reads history on the request path, decorates summaries, warms a cache, attaches a `liveOverlay` object, and returns `{...history, data, liveOverlay}`. List `status` is passed through verbatim from history.
2. **The client does a destructive cross-stream merge.** `loadAllHostsPublishingPartial` + `makeSnapshot` (`CodexDock/State/DockStore.swift:665-837`) builds rows only from hosts that finished this refresh; a still-checking host gets `.checking` and **zero rows** — no last-good cache. The client also fans out 2 scopes/host, dedupes, and resolves human/agent conflicts (`deduplicated`/`shouldPrefer`, 876-931).
3. **"History status wins" is a pinned contract.** `scripts/dock-relay-phase5.test.mjs:304-309` asserts `status.type === "notLoaded"` survives and `dockRelaySource` is stripped — an intentional, tested behavior that my design must retire.

I have enough grounded evidence to produce my independent first pass.

---

# Model B — First-Pass Target Architecture: Codex Dock Relay Aggregator

## 1. Architecture thesis

**Make the relay a stateful, provider-agnostic *session-table service* and turn the client into a dumb subscriber to that table.**

Each per-host relay continuously maintains a normalized, last-known-good **session table** in the background (not on the request path), merges live runtime status into rows, and pushes the client a **full snapshot on connect, incremental deltas while connected, and a fresh snapshot on resync**. The client holds one table per host keyed by stable session id, applies deltas, and renders. Rows are only ever mutated by an explicit upsert/remove delta — *never* cleared by a refresh, a slow upstream, or a transient failure. Host connectivity and data freshness are separate metadata, not row presence.

This single move dissolves all three documented root causes at once:
- Destructive partial snapshots die because the client never rebuilds rows from "who finished this refresh."
- `notLoaded` stops being the dominant badge because status is normalized and live-merged **relay-side**, and the Codex `notLoaded` concept never crosses the wire.
- Cold-path latency (Home's 4–6s `thread/list`) leaves the client path because the relay serves a warm cached snapshot and does the slow upstream polling in the background.

Provider-agnosticism falls out for free: the wire model is a normalized session, so a future Claude Code adapter is a relay-internal addition with **zero client changes**.

## 2. Evidence read and why it mattered

| Evidence inspected | Why it mattered to the design |
|---|---|
| `goal.md`, working doc, root-cause doc | Pinned the three failure modes and the non-negotiables (relay owns hard work, client simple/agnostic, snapshot+delta+resync, no preservation of current arch). |
| `dock-relay-thread-data.mjs:457-478` (`aggregateThreadList`) — *read directly* | Proves the relay does the **list fetch on the client's request path** and only attaches `liveOverlay`; no durable snapshot, no live-status merge. This is the latency + flicker source and the thing to invert. |
| `dock-relay-thread-data.mjs:211-227, 298-423` (loopback discovery, `collectLiveRows`, `preferThread`) | The relay **already** discovers live app-servers and reads live rows on a background cadence — the seed of the sync loop and the merge it currently refuses to do. |
| `dock-relay-live-status-cache.mjs` (2.5s refresh / 5s max-age, overlay states ready/degraded/stale/unavailable/disabled) | Proof the relay already runs a background poller with freshness states. The target generalizes this pattern to the whole session table. |
| `DockStore.swift:665-837, 876-931` — *read directly* | Proves the client owns fan-out (2 scopes × N hosts), dedup, human/agent conflict resolution, and the destructive partial merge. This is the "weird logic" to delete. |
| `SessionSummaryMapper.swift` / `ThreadListDTO.swift` (ThreadStatus, ThreadSourceKind enums, origin classification) | Proves the client decodes raw Codex concepts (notLoaded/active/activeFlags, exec/appServer/subAgent*). The normalized wire model must absorb all of this. |
| `dock-relay-phase5.test.mjs:192-323` — *read directly* | The "notLoaded wins / strip dockRelaySource" contract is **deliberate and tested** — the single biggest migration trap; my design explicitly replaces this test. |
| Upstream Codex app-server (README, `thread_status.rs`, `thread_processor.rs`) | `notLoaded` = "not in this process's runtime memory," not "no data." And app-server is **request/response only** (no list subscription). ⇒ the relay must *poll upstream and synthesize deltas itself*; it cannot subscribe upstream. This is a hard constraint, not a choice. |
| Host registry / single-endpoint-per-host doc + `DockHostConfiguration`/`HostRegistry` | One relay per host is freshly, deliberately shipped. The target should keep it and do a trivial client-side union, not add an aggregator tier. |
| Test/sim harness (`DockSessionLoading` injection seam, `os_log` subsystem `com.aelaguiz.CodexDock`, Makefile `sim-logs`/`app`, `node --test`) | The proof infrastructure already exists; the simulator-proof strategy plugs into it (scripted fake relay + log assertions), and the client injection seam survives the redesign. |

## 3. Component boundaries

```
┌────────────────────────── PHONE CLIENT (thin) ──────────────────────────┐
│ DockStreamClient (per host): subscribe → AsyncStream<Snapshot|Delta>     │
│ SessionTable (per host): Map<sessionId, NormalizedSession> + applyDelta  │
│ Trivial cross-host union → render. Tabs/filters = filter on `lane`.      │
│ Host chrome from HostStatus metadata (online/refreshing/stale/offline).  │
└───────────────▲───────────────────────────── one WS per host ───────────┘
                │  provider-agnostic wire: snapshot / delta / resync
┌───────────────┴────────────────── PER-HOST RELAY ───────────────────────┐
│ Subscriber registry  ── snapshot-then-deltas, coalescing backpressure    │
│ SessionTable (authoritative): rows + epoch + seq + asOf + freshness      │
│ SyncLoop: poll adapter → normalize → merge live status → diff → bump seq │
│ DetailRouter: read/turns/resume/turn-control pass-through to adapter     │
│ Secrets: upstream tokens, OpenAI key, loopback discovery (never leave)   │
└───────────────▲──────────────────────────────────────────────────────────┘
                │  internal ProviderAdapter contract (provider-specific)
        ┌───────┴────────┐                      ┌────────────────────┐
        │ Codex adapter  │   (future, no client │ Claude Code adapter│
        │ app-server +   │    change)           │  (same contract)   │
        │ loopback live  │                      └────────────────────┘
        └────────────────┘
```

Boundary rules:
- **Client ↔ relay:** one WebSocket per host carrying the normalized protocol. The client knows *sessions, status, freshness, hosts* — nothing about Codex, app-server, cursors, scopes, or loopback.
- **Relay core ↔ adapter:** the core is provider-agnostic (poll/normalize/diff/serve). All provider weirdness lives behind `ProviderAdapter`.
- **Cross-host:** stays client-side and trivial (union of independent per-host tables). No aggregator service.

## 4. Relay state model

Per host, in memory (rebuildable; disk persistence deferred):

```
SessionTable {
  epoch: string            // changes on relay restart / cache rebuild
  seq: u64                 // monotonic per update within epoch
  asOf: timestamp          // when this table was last refreshed
  freshness: fresh | stale // stale = last upstream poll failed/timed out
  lastSuccessfulSyncAt: timestamp
  lastError: { subsystem, code, message, retryable } | null
  rows: Map<sessionId, NormalizedSession>
}
```

- **SyncLoop** (generalizes today's 2.5s live cache loop): on each tick, ask the adapter for (a) the base/history list and (b) live runtime status; normalize; **merge live status onto base rows** (the merge the relay refuses to do today); diff against current `rows`; if changed, bump `seq`, set `asOf`, emit `{upserts, removals}` to subscribers. On adapter failure/timeout: keep `rows` intact, flip `freshness=stale`, record `lastError`, emit a freshness-only update. **Last-known-good is never erased by a failed poll.**
- **SubscriberRegistry:** on subscribe, send current snapshot then stream deltas. Per-subscriber coalescing: a slow client that falls behind is collapsed to a fresh snapshot rather than buffering unbounded deltas (bounded memory, self-healing).
- **DetailRouter:** `read/turns/resume/turn-control` are *not* in the table; they pass through to the adapter on demand (today's live-or-history routing, kept).

Polling cadence is adaptive: fast (~1–2.5s) when a subscriber is connected and rows are active, slow/idle when no subscribers. Slow upstreams (Home) just make `asOf` older; they never block the client.

## 5. Provider adapter model

A relay-internal interface; the core never imports Codex concepts.

```
interface ProviderAdapter {
  capabilities(): { liveStatus, resume, turnControl, archive, search }
  listSessions(opts): NormalizedSession[]     // base/durable set (history)
  liveStatus(): RuntimeStatus[]               // currently-active runtime facts
  readSession(id, {includeTurns}): Detail
  // optional, capability-gated:
  resume(id) / steer / interrupt / archive / unarchive
}
```

The adapter is the **only** place that:
- speaks the provider's transport/methods (Codex: `thread/list`, `thread/loaded/list`, `thread/read`, loopback `ps` discovery, `initialize` handshake, bearer tokens);
- maps provider status → the canonical enum (Codex `NotLoaded→dormant`, `Idle→idle`, `Active{flags}→running/needsInput/needsApproval`, `SystemError→error`);
- assigns `lane` (human|agent) from provider source metadata (Codex `sourceKind`: cli/vscode→human; exec/appServer/subAgent*→agent);
- mints a stable, namespaced `sessionId` (`{provider}:{host}:{threadId}`).

`NormalizedSession` (the clean wire model):

```
{ id, provider, host,
  title, preview,
  repo, cwd, branch,
  lane: "human" | "agent",
  status: "running" | "needsInput" | "needsApproval" | "idle" | "error" | "dormant",
  kindLabel,            // display-only origin label ("VS Code", "exec", "review sub-agent")
  lastActivityAt,
  archived }
```

`dormant` (history row with no live runtime) is rendered as a quiet baseline (or no badge) — **the client never sees `notLoaded`** and never branches on `kindLabel`. Claude Code later implements the same interface; because the client consumes only `NormalizedSession`, it needs no change.

## 6. Wire protocol (snapshot / incremental / resync)

WebSocket, one connection per host (keeps today's transport, port, bearer-token auth). Server→client messages:

```
SNAPSHOT  { type:"snapshot", epoch, seq, asOf, freshness,
            host:{ id, displayName, connection, lastSyncAt },
            sessions:[ NormalizedSession, ... ] }

DELTA     { type:"delta", epoch, fromSeq, seq, asOf, freshness,
            upserts:[ NormalizedSession, ... ], removals:[ sessionId, ... ],
            host:{ connection, lastSyncAt } }

HEARTBEAT { type:"heartbeat", epoch, seq, asOf, freshness }   // liveness w/o row churn
```

Client→server:

```
SUBSCRIBE { type:"subscribe", since?:{ epoch, seq } }
RESYNC    { type:"resync" }            // force fresh snapshot
```

Semantics:
- **Full snapshot:** sent on every `subscribe` (and on `resync`). The client *replaces* its table for that host atomically.
- **Incremental update:** `delta` carries only changed rows + removals; `fromSeq` must equal the client's last `seq` or the client requests `resync`. `freshness`/`asOf` ride on every message so staleness is always current.
- **Resync:** explicit (`resync`) or implicit (epoch mismatch, gap in `seq`, reconnect). Always answered with a fresh `snapshot`. **V1 keeps resync = full snapshot** (no cursor replay log) — correct and lean.
- Detail/control (`read`, `turns`, `resume`, `turn/*`) stay request/response and unchanged in spirit; renaming `thread/* → session/*` is cosmetic and deferrable.

The protocol carries a `schemaVersion`/capabilities field at subscribe time — the one piece of versioning the system lacks today — so providers/fields can evolve without silently breaking the client.

## 7. Failure / staleness semantics

- **Upstream slow/timeout/ECONNREFUSED:** relay serves last-known-good `rows`, sets `freshness=stale`, records `lastError`, keeps streaming heartbeats. Client shows rows + a subtle "stale/reconnecting (last good HH:MM)" affordance. **No row ever disappears.**
- **Relay restart:** new `epoch`; first reachable subscribe gets a fresh snapshot. Brief cold window where the relay re-warms; client shows "reconnecting" with prior rows retained until the snapshot lands (client keeps its last table across socket drops).
- **Client reconnect:** resubscribe → snapshot → resume deltas. Idempotent.
- **One host down:** only that host's chrome flips to offline; its last rows can be shown dimmed-as-stale or hidden per product choice — independent of other hosts (fault isolation from one-relay-per-host).
- **Three orthogonal axes, never collapsed** (the UX fix the root-cause doc demands): host *connection* (online/reconnecting/offline) · table *freshness* (fresh/stale + asOf) · row *runtime status* (running/needsInput/idle/error/dormant). Row *availability* is no longer a concept — if we have a row, we show it.

## 8. Client responsibilities (deliberately small)

The client **only**:
1. Maintains one WebSocket per host (existing transport) and resubscribes on drop.
2. Holds `Map<sessionId, NormalizedSession>` per host; applies snapshot (replace) and delta (upsert/remove); requests resync on gap.
3. Unions per-host tables (concatenate) and renders. Human/Agents tabs = filter on `lane`; sort by `lastActivityAt`.
4. Renders host chrome from `HostStatus` metadata.
5. Issues detail/control requests on tap.

The client **no longer**: pages cursors, runs scope fan-out, dedupes, resolves human/agent conflicts, decodes ThreadStatus/sourceKind, interprets `liveOverlay`, or rebuilds rows from "who finished." All of `DockStore.makeSnapshot/deduplicated/shouldPrefer` and the `SessionSummaryMapper` Codex decoding are deleted.

## 9. Security / secrets boundary

- **Relay-side only:** upstream history/live bearer tokens, OpenAI realtime key + safety id, loopback `ps` discovery, and all app-server method knowledge. None cross the wire.
- **Client→relay:** single relay bearer token over the WS upgrade (existing), inside the Tailscale network boundary. Client holds no provider/app-server/OpenAI credentials.
- **Debug surface stays loopback-gated** (`/statusz`, `/metricsz`, `/debugz`). The normalized snapshot deliberately excludes internal fields (today's `dockRelaySource` stripping generalizes to "adapter fields never serialize"). A schema/golden test enforces "no provider-internal field leaks to the wire."

## 10. Migration strategy (no implementation)

Phased, each phase independently shippable and simulator-proven:

1. **Relay: build the SessionTable + SyncLoop behind a new subscribe channel**, alongside today's `thread/list` (no client change yet). Generalize the existing live-status cache loop to maintain the whole table and to **merge live status onto base rows + normalize status**. Internally retire the "history status wins" rule.
2. **Replace the pinned contract test.** `dock-relay-phase5.test.mjs`'s "keeps history status / notLoaded wins" becomes "status is normalized and live-merged; `notLoaded` never serialized." This is the deliberate contract flip the doc flagged.
3. **Client: add `DockStreamClient` + per-host `SessionTable`** behind the existing `DockSessionLoading`-style injection seam; render from the normalized model. Feature-flag old vs new path.
4. **Delete client complexity** (`makeSnapshot` partial logic, `deduplicated`/`shouldPrefer`, scope fan-out, `SessionSummaryMapper` Codex decoding) once the new path is simulator-proven.
5. **Decommission `thread/list` as a client API** (keep detail/control routes). Optionally rename `thread/* → session/*`.
6. **Later, no client change:** add the Claude Code adapter.

Deferred (explicitly, to stay lean): cursor delta-replay across reconnect; disk persistence across relay restart; an aggregator tier; protocol method renames.

## 11. Test strategy (simulator proof = primary client evidence)

- **Primary client proof — simulator, not unit tests.** Point the app (`CODEX_DOCK_HOSTS`, existing Makefile `app` target) at a **scripted fake relay** that speaks the new protocol with deterministic timing — finally making the "slow Home" scenario forceable, which the root-cause doc said we currently cannot do. Drive scenarios and assert via the existing `com.aelaguiz.CodexDock` os_log stream (`sim-logs`): (a) snapshot paints fast from cache; (b) when the fake relay flips a host to `stale`/reconnecting, **selected-host rows remain** (no drop to zero — the exact regression); (c) deltas update rows in place; (d) resync after reconnect repaints with no flicker. Add structured log lines (e.g., `dock stream snapshot epoch= seq= rows=`, `dock host freshness=`, `dock rows_retained host=`) as the machine-checkable assertions.
- **Relay proof — `node --test` against the adapter contract + sync loop:** feed a fake adapter; assert live-merge/normalization (no `notLoaded` on the wire), correct diff (upserts/removals/seq monotonicity), last-good retention + `freshness=stale` on adapter failure, and `resync` → full snapshot. Plus a **Codex-adapter conformance test** and a **schema/golden test** (provider-agnostic; no internal/provider fields leak), so adding Claude Code can't break the client.
- Unit tests (DockStore reducer / delta application) remain useful but are **not** completion evidence.

## 12. Rejected alternatives

1. **Client-side stale-while-refresh only** (root-cause Options A/B): fixes flicker but leaves Codex decoding, scope fan-out, dedup, and cold-path latency in the client; doesn't generalize to Claude Code. Fine as a stopgap patch; wrong as the *architecture*.
2. **Merge live status into `thread/list`, client still polls list+overlay** (Option D): better status, but client still pages/merges/dedupes/rebuilds and stays Codex-shaped. Half-measure.
3. **Relay-owned snapshot endpoint that the client polls** (Option C, poll form): genuinely close and simpler — relay owns assembly + cache. But polling can't cleanly express incremental updates, forces an interval/load tradeoff, and gives weaker staleness precision than the goal wants. I treat it as the **minimum-viable fallback**, not the target. (Flagged for Model A — see §14.)
4. **Aggregator relay tier across all hosts:** centralizes the union but adds an always-on SPOF + extra hop, and fights the just-shipped one-endpoint-per-host model. Client-side trivial union is simpler and fault-isolates host outages.
5. **Event-sourced log / CRDT / message bus client↔relay:** kitchen-sink for a few hosts and hundreds of rows. Rejected as overbuild.
6. **Subscribe to app-server upstream for push deltas:** impossible — app-server lists are request/response only. The relay *must* poll and synthesize deltas. (Constraint, recorded so we don't relitigate it.)

## 13. Risks / open questions

- **Subscription complexity vs. lean.** A push channel + coalescing + epoch/seq is more than a poll-a-snapshot endpoint. Justified only if "fast incremental + precise staleness" is worth it. Honest tension worth converging on.
- **`dormant` rendering.** What replaces "Not loaded" visually so a mostly-history list isn't a wall of one badge — quiet baseline vs no badge vs "history." Product-ish but the relay owns the normalization, so we must fix the enum now.
- **Backpressure/coalescing** must be bounded and tested, or a slow client leaks relay memory.
- **`sessionId` stability** across history↔live and forks (Codex `forkedFromId`) — the merge key must be rock-solid or rows duplicate/flto-flicker.
- **Adaptive poll cadence** vs. upstream load (Home's 6s list): cadence must not stampede a slow app-server.
- **Claude Code unknowns:** no persisted "history" endpoint? different status model? The adapter interface must not secretly assume Codex's history/live split. (Capabilities flags mitigate.)

## 14. What I need from Model A to converge

1. **Push subscription vs. relay-owned poll-a-snapshot.** Do we pay WS-subscription complexity for fast incremental + precise staleness, or is a cached `dock/snapshot` the client polls "lean enough"? I lean subscription; I want A's strongest case for the poll form.
2. **One-relay-per-host + client union vs. aggregator tier.** I lean keep per-host (fault isolation, matches shipped model). Does A see a reason to centralize?
3. **Resync model in V1:** full-snapshot-on-reconnect (my lean) vs. cursor delta-replay log now.
4. **Canonical `status` enum + `dormant` semantics**, and whether `lane` (human/agent) is an on-wire field (my lean) or derived client-side from a generic origin label.
5. **epoch+seq at table granularity** (my lean) vs. per-row versioning.
6. **Disk persistence of the table across relay restart** — defer (my lean) or in V1?
7. **Method rename `thread/* → session/*`** now vs. deferred.

If A and I align on (1) and (2), the rest is detail and we converge fast. If A argues poll-a-snapshot, the crux of the debate is whether "fast" + "incremental updates" in the goal are first-class requirements or nice-to-haves — that's the one decision worth a real fight before we write the doc.

---

I've completed my independent first pass grounded in directly-inspected repo evidence. I have **not** written to the working doc or any source file — per the consensus protocol this first pass is returned for the cross-review phase. I'm ready to review Model A's pass and converge (or surface a real unresolved decision, most likely item 14.1).
