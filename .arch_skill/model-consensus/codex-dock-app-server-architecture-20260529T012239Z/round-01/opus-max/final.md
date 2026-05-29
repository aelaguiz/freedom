I'll start by reading the required evidence systematically. Let me fan out across the Dock repo first, then the Codex source.
Now the project config, the key audit doc, and the relay scripts.
Excellent — the audit doc is rich. Now the relay scripts and host service.
Now the JSON-RPC client, host service, and the core Swift files.
Strong picture of the Dock side now. Let me read the remaining Dock config/projection files directly while dispatching two focused Explore agents to verify the Codex Rust truths in parallel (so I confirm the audit's claims against real source).
I have enough real evidence now — the Dock client, relay, host service, and Swift state, plus two citation-backed extractions of the Codex Rust source that confirm and sharpen the audit. Here is my independent architecture pass.

---

## Verdict

Keep the relay, but **rebuild its data layer** and **demote the live plane to a non-reordering decoration**. The 2026-05-29 stale-newest incident was not a Codex problem and not a Swift problem — it was the relay doing per-row, per-scope, per-request WebSocket fan-out against a single history endpoint, leaking ~10,900 sockets, then hiding the resulting live-discovery failure while concatenating live-before-history instead of globally sorting. Every one of those is an architectural choice, not a bug to patch.

The elegant target is a relay with three hard-separated planes and one ruthless invariant: **list order is a pure function of Codex history; live status may only repaint a row, never move it.** That single rule plus connection pooling deletes the entire class of failure seen in the incident. This requires a substantial rewrite of `scripts/dock-relay-thread-data.mjs` and `scripts/dock-relay-json-rpc-client.mjs`, and a smaller correctness change in the Swift host-identity layer. The Swift `AppServerClient`, projection, and store are largely sound and mostly survive.

## Evidence Read

Dock client (read in full): `AGENTS.md`, `README.md`, `Makefile`, `package.json`, `Package.swift`, `project.yml`, `docs/CODEX_DOCK_CODEX_APP_SERVER_END_TO_END_AUDIT.md`, `docs/CODEX_DOCK_THREAD_SORT_ROOT_CAUSE_2026-05-29_WORKLOG.md`, `scripts/dock-relay.mjs`, `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay-json-rpc-client.mjs`, `scripts/codex-dock-host-service.mjs`, `CodexDock/AppServer/AppServerClient.swift`, `CodexDock/State/DockStore.swift`, `CodexDock/State/DockSessionProjection.swift`, `CodexDock/Configuration/HostRegistry.swift`, `CodexDock/Configuration/RelayBootstrapStore.swift`.

Codex source (verified via two targeted source extractions with `file:line` citations): `app-server/src/main.rs`, `lib.rs`, `request_processors/thread_processor.rs`, `thread_status.rs`, `filters.rs`, `app-server-transport/.../websocket.rs`, `auth.rs`, `remote_control/mod.rs`, `app-server-daemon/src/lib.rs`, `managed_install.rs`, `core/src/thread_manager.rs`, `thread-store/src/local/list_threads.rs`, `app-server-protocol/.../v2/thread.rs`.

Decisive facts that survived verification:

- **No cross-process session registry exists in Codex.** Each app-server process is an island. The daemon manages exactly one long-lived app-server per `CODEX_HOME` at a fixed Unix socket (`{CODEX_HOME}/app-server-control/app-server-control.sock`, `lib.rs:262`). `--remote-control` enrolls *one* process to a backend by `installation_id`; it is not a local broker (`remote_control/mod.rs:179-294`).
- **`thread/list` default `sortKey` is `createdAt`** (`thread_processor.rs:1818`); Dock correctly overrides to `updatedAt`. Wire `created_at`/`updated_at` are **i64 seconds** (`thread_data.rs:117-122`) — same-second ties are guaranteed at scale.
- **Cursor is an RFC3339 timestamp ±1ms, forward-only** (`thread_processor.rs:3599`). Timestamp-only cursors over second-precision rows = real page-boundary tie hazards.
- **`modelProviders` omitted = current provider only; empty = all providers** (`thread_processor.rs:1489-1495`). Dock sends `[]` — correct.
- **`sourceKinds` omitted/empty = interactive only** = `[cli, vscode, atlas, chatgpt]` (`filters.rs:9-14`); agents need explicit kinds with a post-filter path.
- **Status overlay is process-local.** `loaded_statuses_for_threads` overlays `ThreadWatchManager` onto stored rows; untracked → `NotLoaded` (`thread_status.rs`). `thread/loaded/list` is process-local `list_thread_ids()`, lexically sorted, not a recency index (`thread_processor.rs:2002-2047`).
- **Idle unload = 30 min with no subscribers** (`thread_lifecycle.rs`). This matters: a relay that holds subscriptions to every session would prevent Codex from ever unloading them.
- **Non-loopback WS listeners refuse to start without auth; loopback is exempt** (`auth.rs:266-271`, `websocket.rs:135-142`). This is exactly why the relay (not the raw app-server) is the network boundary.

## Codex App-Server Truths

The mental model Dock must encode:

1. **Two planes, one of them authoritative for the list.** The *history plane* (persisted `~/.codex`, read via `thread/list`/`thread/read`/`thread/turns/list` with `useStateDbOnly=false` so rollout JSONL is scanned) is the single source of truth for *which threads exist* and *their recency*. Because rollout files are appended live, history `updatedAt` is fresh — the incident probe proved raw history returned age-0 rows. The *live plane* (in-memory status in whichever process loaded a thread) is authoritative only for *runtime status* and *live event routing*.
2. **Live state is per-process and unenumerable from Codex.** There is no "list all app-servers." Discovery is an OS-level act (process/socket inspection) or it does not happen. Any client design that needs all live sessions must own discovery and treat it as fallible.
3. **A dedicated, Dock-owned history app-server is the right anchor.** Running `codex app-server --listen ws://127.0.0.1:4500 --ws-auth capability-token` as a Dock-managed process (as today, `codex-dock-host-service.mjs:435-446`) gives a stable, isolated, auth-gated endpoint that sees *all* persisted history independent of the daemon's interactive lifecycle. Keep it.
4. **`notLoaded` from `:4500` is normal and meaningless for liveness** — it only means "not loaded in this process." Never render it as "dead."
5. **Subscription = resume.** A client gets a live event stream and status notifications by `thread/resume` (already-loaded path rejoins; otherwise reconstruct-from-history) or `thread/start`. There is no read-only "watch." Holding a resume keeps the thread loaded.
6. **The network boundary is forced by Codex's own auth rule.** Loopback can be unauthenticated; anything the phone can reach cannot. So the phone-facing surface must be a separate process (the relay) that terminates phone connections and holds the raw token Mac-side.

## Proposed Architecture

Four host-side components with single responsibilities and hard invariants. The relay stays, but it becomes thin and disciplined.

```
 iPhone / Sim ──ws/wss──▶ Dock Relay (:4510, 0.0.0.0)
                              │
        ┌─────────────────────┼───────────────────────────────┐
        │                     │                                │
   HistoryClient        LiveStatusCache                  SessionRouter
  (1 pooled conn        (timer-driven, pooled            (on-demand resume,
   to :4500)             conns per live endpoint)          1 conn per focused thread)
        │                     │                                │
        ▼                     ▼                                ▼
  codex app-server      discovered codex app-server     owning live endpoint,
  --listen ws://         --listen ws://127.0.0.1:<port>  else :4500 (loads it)
  127.0.0.1:4500         (cached discovery)
  (history SSOT)

   + TranscriptionProxy (OpenAI Realtime; key stays Mac-side)
```

**1. HistoryClient — the list SSOT.**
Owns exactly **one** long-lived, multiplexed JSON-RPC connection to `:4500`. JSON-RPC already multiplexes by `id`, so one socket serves all concurrent `thread/list`/`thread/read`/`thread/turns/list`. This collapses the ~10,900-socket storm to one connection. The relay's `thread/list` answer is built **solely** from this plane and returned in Codex's own order with Codex's cursor passed through.

*Invariant H1:* the rows and their order in a `thread/list` response are a pure function of the history plane. No live data is consulted to decide membership or order of the list page.
*Invariant H2:* the relay forwards Codex's `nextCursor`/`backwardsCursor` honestly (today `aggregateThreadList` hardcodes `nextCursor: null`, `dock-relay-thread-data.mjs:598` — that silently caps the dashboard at one page and must go).

**2. LiveStatusCache — push-light status table.**
A single background sweeper, not a per-request action. On a bounded cadence (~3–5s) it: (a) reads **cached** endpoint discovery, (b) for each live endpoint uses a **pooled** connection to call `thread/loaded/list` + batched `thread/read includeTurns:false`, (c) writes a `threadId → {status, attentionFlags, ownerEndpoint}` table. `thread/list` and `thread/read` **read** this table to repaint status badges and to know where to route, but never to reorder.

*Invariant L1:* live status is a decoration. If the table is empty, stale, or the sweep failed, the list still returns, correctly ordered, with a `liveOverlay:{ok,endpoints,failed,ageMs}` block telling the app the badges may be stale.
*Invariant L2:* the sweeper uses **reads, not resumes**, for the dashboard, so it does not pin sessions loaded and defeat Codex's 30-min idle unload. (Resume/subscribe is reserved for the focused detail thread only.)
*Invariant L3:* delete the per-row "resume + watch 100ms for approval requests" attention probe (`enrichRowAttention`/`pendingRequestsForActiveThread`, `dock-relay-thread-data.mjs:321-365`) from the list path. Dashboard "needs me" comes from the status snapshot's `activeFlags`; *precise* live attention comes from the focused detail subscription.

**3. SessionRouter — focused live attach.**
When the phone opens a thread, the relay establishes one resume connection to the **owning** endpoint (from the LiveStatusCache table) or, if not live anywhere, to `:4500` (which loads it from history and becomes owner). `turn/start|steer|interrupt` require that established connection (already enforced, `dock-relay.mjs:369-374`). This is the only place a resume happens, and it is one connection per focused thread, torn down on detail close. The existing reconnect/recovery loop (`dock-relay.mjs:295-367`) is good and stays.

**4. TranscriptionProxy** — unchanged in responsibility: OpenAI Realtime stays Mac-side; the key never crosses to the phone. Keep as-is.

**Connection-management substrate (cross-cutting).** Replace `withClient`'s open-per-op-close-in-finally pattern (`dock-relay-thread-data.mjs:267-275`) with a `UpstreamConnectionPool` keyed by endpoint URL: at most one live socket per URL, idle-evicted, health-checked, with a hard global ceiling and a monitored open-count gauge. Harden `JsonRpcWebSocketClient` (`dock-relay-json-rpc-client.mjs`): `close()` must await the close event or `terminate()` after a short deadline; a request timeout must **quarantine/tear down** the socket (a timed-out socket is untrustworthy) instead of leaving it established (`request()` timeout at `:164-176` currently only rejects the promise).

## Data And Control Flow

**Dashboard list (the hot path, today's failure path):**
1. Phone → relay `thread/list` (one call; see scope decision below).
2. Relay → HistoryClient single multiplexed `thread/list` to `:4500`, `sortKey=updatedAt`, `sortDirection=desc`, `modelProviders=[]`, `sourceKinds=<union>`, `archived` passthrough, `cursor` passthrough.
3. Relay repaints each row's `status`/`attentionFlags` from LiveStatusCache (read-only), attaches `origin`/`sourceKind`, attaches `liveOverlay` health, and **returns history order unchanged** with Codex's cursor.
4. Preview text is **not** fetched here. (See Identity section.)

Net upstream cost per refresh: **one** multiplexed request on **one** persistent socket, plus a background sweep that is independent of refresh frequency. Compare to today: history + ps-scrape + N live reads + up-to-200 per-row `thread/turns/list` opens, each a new socket, per scope, per host, per refresh.

**Detail open:** phone → relay `thread/read includeTurns:false` (table-routed) → `thread/turns/list limit:10` → `thread/resume excludeTurns:true` on the SessionRouter connection; live notifications stream straight through. This matches the README's compact detail path and stays.

**Discovery:** a cached `discoverLiveEndpoints()` refreshed on the sweep timer, not per request. Today `collectLiveRows` (and thus `discoverLoopbackEndpoints` → `execFileSync ps`) is re-invoked by `aggregateThreadList`, `aggregateThreadRead`, `endpointForThread`, `listThreadTurns`, and `resumeThread` — a single detail open can trigger several full `ps` sweeps. Caching makes `ps` failure rare and recoverable, and makes the sweep the only `ps` caller.

## Identity, Deduping, Sorting, And Pagination

**Identity.**
- Thread identity is the Codex thread UUID; host-scoped identity is `(hostId, threadId)` (Swift `HostScopedThreadID`). Keep.
- **Host identity must come from the relay, not the endpoint string.** Today `HostRegistry` derives `host.id` from the endpoint (`HostRegistry.swift`), so the simulator's three aliases for one relay (`amir-m5.fairy-salmon.ts.net`, `192.168.50.x`, `Amir-M5.local`) became three logical hosts → 3× load, duplicate sections. Fix: the relay advertises a **stable instance id** in its Bonjour TXT and in `initialize`/`/statusz`; the app groups all endpoints sharing that id into **one** logical host carrying an **ordered candidate-endpoint list** (failover), and connects to the first reachable.

*Invariant I1:* exactly one logical host per relay instance id. Multiple endpoints are failover transports of that one host, never independent hosts.

**Scope / dedup.**
Collapse the two-scope query to **one union `thread/list`** (`sourceKinds` = explicit union of interactive + agent kinds) and tag each row with `sourceKind`/`origin`. The app's tab filter already partitions on `origin.kind` (`DockStore.swift:222-241`). This deletes the human/agent scope multiplier *and* the entire Swift scope-conflict/dedup machinery (`deduplicated`, `DockScopeConflictViewModel`, `preferredScope`, `DockStore.swift:839-904`). Caveat: a single newest-N union page can starve a thin category; for a single-user dashboard at `limit=200` this is acceptable, and real pagination (below) covers the tail. If category-coverage ever matters, keep two scopes but run them over the pooled HistoryClient connection — cheap once connections are pooled. **Recommendation: union.**

**Sorting.**
- Global order = `updatedAt desc`, then a **stable tiebreak by `threadId`** — applied identically in relay and app. Wire seconds precision guarantees same-second ties; without a deterministic tiebreak, rows flap between refreshes.
- Kill `mergeThreadListRows`'s live-first concatenation (`dock-relay-thread-data.mjs:458-492`). Under H1 there is nothing to merge for ordering: the list is history-ordered; live only repaints.
- *Invariant S1:* status priority (needs-me/running/idle) may influence grouping/precedence **within the app's projection** (Branch grouping, `DockSessionProjection.swift`), but never the flat "Newest" order, which is recency-only with threadId tiebreak.

**Pagination.**
- Pass Codex's `cursor`/`nextCursor` through unchanged (history plane only).
- Because cursors are timestamp-only over second rows, dedupe by `threadId` across pages in the relay, and keyed-merge by `threadId` in the app. The LiveStatusCache decorates whatever page arrives.
- *Invariant P1:* the relay never invents `nextCursor: null`; it forwards exactly what `:4500` returned.

## Observability And Debuggability

The incident was invisible until someone ran `lsof | wc -l` by hand. Make the next failure self-announcing.

- **The one gauge that would have caught it:** open upstream connection count, per endpoint and total, in `/statusz`, with a hard ceiling that trips a structured `relay.upstream_ceiling_exceeded` error and refuses to open more. The pool makes this naturally bounded; the gauge proves it.
- **First-class live-overlay health, never hidden:** `/statusz` already records live discovery (`dock-relay.mjs:462-485`); make `endpoints`, `failed`, `lastError`, `lastSuccessAt`, `ageMs` permanent, and **echo a compact `liveOverlay` block into every `thread/list` response** so the app shows "live status stale/unavailable" without the list ever looking healthy-but-wrong. Today `aggregateThreadList` logs `thread_list.live_failed` and returns history-only silently — that masking is the bug; surface it.
- **Self-reported resource health:** sweeper reports `ps`/discovery outcome and (best-effort) open-fd count in `/statusz`; `doctor` flags abnormal socket/fd counts (extends `doctorHostServices`, `codex-dock-host-service.mjs:877-896`).
- **Heartbeat log line** at info every sweep: `{endpoints, failed, upstreamOpen, statusTableSize, historyConnUp}` — one grep shows health over time.
- **App side:** keep the rich connectivity indicator; add a distinct sub-state for "connected, live status stale" (driven by `liveOverlay.ok=false`) separate from "offline." A nil phone bearer token stays normal, not "missing credentials."
- Keep the redaction discipline already in place (`DockLog`, `dock-relay-logger.mjs`, `redactValue`): never log tokens, audio, prompt/transcript text, or full payloads.

## Makefile And Ops Surface

The canonical surface is already good (`services`, `app-server-status`, `dock-relay-status`, `app SIM=`, `app-test`, `device-install[-all]`, `device-config-verify`, `sim-logs`, `device-logs`, `dock-relay-logs`, `host-service-doctor`). Add the diagnostics the incident needed:

- `make relay-probe` — runs the two-endpoint JSON-RPC diff that diagnosed the incident: `thread/list` against raw `:4500` and against relay `:4510` for the union scope, printing top-row `updatedAt`/age/status from each. This is the single highest-value new target; it turns a 30-minute manual investigation into one command.
- `make relay-leak-check` — hammers relay `thread/list` N times and asserts the `/statusz` upstream-open gauge stays flat (regression guard for the connection-pool invariant).
- `make relay-doctor` — alias/extension of `host-service-doctor` that foregrounds socket/fd counts and live-overlay health.
- Keep `services` idempotent and the single entrypoint; keep `app-server`/`dock-relay` as aliases. Keep status/logs as the default verification path; stop/restart stay intentional-only.

## Testing And Acceptance Gates

**Relay unit (`node --test`, `npm run test:relay`):**
- History list is returned in Codex order with Codex cursor passed through (no `null` clobber).
- Live overlay repaints status but never changes membership or order (property test: shuffle/empty/failed live table → identical row order).
- Upstream request timeout tears down/quarantines the socket; `close()` awaits or force-terminates within deadline.
- Connection pool holds ≤1 socket per endpoint and never exceeds the global ceiling under concurrent list+detail load.
- Live discovery failure is surfaced in `liveOverlay` and `/statusz`, never silently dropped.
- Union `sourceKinds` returns interactive + agent rows tagged with `sourceKind`.
- Same-second tie ordering is deterministic by `threadId`.

**Swift unit (`swift test`):** keep `AppServerClientTests`, `DockStoreTests`, `ThreadDetailStoreTests`. Add: alias endpoints sharing a relay instance id collapse to one logical host with a candidate list (`HostRegistry`); keyed-merge pagination by `threadId`; projection unchanged; "live stale" connectivity sub-state.

**Simulator (`make app-test SIM='iPhone 17'`):** one logical host even when three aliases are configured; reload N times with the leak-check gauge flat.

**Service (`make services` + `host-service-doctor`/`relay-doctor`):** doctor passes; upstream-open gauge stable across repeated reloads; `relay-probe` shows relay top-row recency within one second of raw `:4500`.

**Physical (deferred, Amir-run per AGENTS.md):** installed app on iPhone 14 (local) and iPhone 17 Pro (Tailscale) renders real `SessionSummary` rows, correct newest order, live badges, offline/stale UI; per-device candidate lists verified by `device-config-verify`.

*Acceptance gate (hard):* `relay-probe` top-row `updatedAt` from `:4510` is within one second of `:4500`; leak-check gauge flat; `liveOverlay.ok` truthfully reflects discovery; no logical host duplication on the 3-alias simulator.

## Migration / Replacement Plan

Depth-first, each step independently shippable and testable.

1. **Connection substrate (root fix).** Introduce `UpstreamConnectionPool`; harden `JsonRpcWebSocketClient.close()`/timeout. Route HistoryClient through one pooled connection to `:4500`. *Gate:* `relay-leak-check` flat. This alone resolves the fd leak and `spawnSync ps EBADF` cascade.
2. **List from history only.** Rewrite `aggregateThreadList` to history-plane order + passthrough cursor; delete live-first concat in `mergeThreadListRows`; remove per-row preview from the list path; remove `enrichRowAttention` from the list path. *Gate:* order property tests; `relay-probe` recency parity.
3. **LiveStatusCache.** Add the timer sweeper (cached discovery, pooled reads, status table) and `liveOverlay` block in responses + `/statusz`. *Gate:* live-failure-surfaced tests.
4. **Union scope + Swift cleanup.** Relay accepts/forwards union `sourceKinds`, tags `sourceKind`; delete Swift scope-conflict/dedup (`DockStore.swift` dedup machinery). *Gate:* `DockStoreTests`.
5. **Host identity.** Relay advertises stable instance id (Bonjour TXT + `initialize`/`statusz`); app groups endpoints into one logical host with candidate failover. *Gate:* 3-alias simulator → one host.
6. **Pagination.** Honest cursor passthrough + keyed-merge in app. *Gate:* pagination tests.
7. **Ops/observability.** `relay-probe`, `relay-leak-check`, `relay-doctor`; heartbeat log; upstream-open ceiling.

**Delete/replace explicitly:**
- `withClient` open-per-op pattern → pool.
- Per-row `enrichThreadListPreviews` blocking the list (`dock-relay-thread-data.mjs:494-530`) → lazy/bounded preview (viewport- or detail-driven), over the pooled history connection.
- Live-first `mergeThreadListRows` concat → history order + non-reordering overlay.
- Per-request `collectLiveRows`/`discoverLoopbackEndpoints` calls → single cached sweeper.
- `aggregateThreadList`'s silent history-only fallback → surfaced `liveOverlay`.
- `nextCursor: null` clobber → passthrough.
- Swift scope-conflict/dedup → union + local classification.
- Endpoint-derived host identity → relay-advertised identity.
- `thread/loaded/list` as a synthetic global aggregate is no longer load-bearing once the list is history-only; keep only as a best-effort debug endpoint, not a product dependency.

## Risks And Non-Negotiable Invariants

**Invariants (hard):**
1. List membership and order are a pure function of the history plane (`updatedAt desc`, `threadId` tiebreak). Live status only repaints; it never reorders or filters the page.
2. Exactly one logical host per relay instance id; multiple endpoints are ordered failover transports, identity from the relay, never the endpoint string.
3. At most one pooled upstream socket per distinct endpoint URL; no per-request or per-row socket creation; open-upstream count is gauged with a hard ceiling.
4. A request timeout tears down/quarantines its socket; `close()` awaits close or force-terminates within a bounded deadline.
5. Live discovery/status are best-effort, their failure is surfaced in the response and `/statusz`, and they never block or silently degrade the list.
6. No phone receives the raw app-server bearer token or `OPENAI_API_KEY`; phone endpoints are `ws://`/`wss://` host:port only; Bonjour TXT stays non-secret.
7. The dashboard status sweep uses reads, not resumes — it must not pin sessions loaded and defeat Codex's 30-min idle unload.
8. Same-second timestamp ties are resolved deterministically by `threadId` in both relay and app.

**Risks:**
- *Union-page starvation:* one newest-N page dominated by agents could thin the human tab. Mitigation: `limit=200` + real pagination; fallback to dual-scope-over-pool if observed.
- *Stale "needs me" on the dashboard:* moving precise attention to the focused detail subscription means non-focused approval-waits may lag by one sweep. Acceptable for a single-user tool; surfaced via `liveOverlay` freshness.
- *Discovery blind spots persist:* `ps`-argv matching still misses Unix/stdio/in-process/remote-control sessions. Pooling removes the *failure cascade*, but discovery is still narrow. Mitigation: enumerate codex-owned listening sockets rather than exact argv, and always report "what I could not see" in `liveOverlay`.
- *Idle-unload interaction at the focused thread:* the SessionRouter resume legitimately pins one thread while open; ensure teardown on detail close so it can unload normally.

## Open Questions For Consensus

1. **Status sweep vs. focused subscription split:** is a periodic pull-based LiveStatusCache the right default (my recommendation, to protect idle-unload), or should the relay maintain persistent subscriptions for *all* live threads to get instant badges, accepting that it pins every session loaded? This is the single biggest behavioral fork.
2. **Union scope vs. dual scope:** collapse to one unioned `thread/list` (delete Swift dedup), or keep human/agent scopes but run them over the pool? Trade simplicity against guaranteed per-category coverage on a single page.
3. **Anchor endpoint:** keep a dedicated Dock-owned history app-server on `ws://127.0.0.1:4500` (my recommendation, for isolation), or connect the relay to the daemon's managed Unix control socket and stop running a second app-server process?
4. **Preview source:** drop list-time previews entirely in favor of title+status (cheapest), fetch lazily on viewport, or ask whether Codex's `thread/list` row can carry a server-computed last-message snippet so the relay never reads turns for previews at all?
5. **Discovery hardening ceiling:** is replacing argv-`ps` with codex-owned listening-socket enumeration worth it for a single-user tool, or is cached argv-`ps` + honest "blind spots" reporting sufficient?
6. **Pagination ambition:** is true cursor pagination a near-term requirement, or is a single newest-200 page acceptable for the dashboard while we fix ordering correctness first?
