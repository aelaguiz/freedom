**Thesis**

Make Codex Dock a one-stream client. The iPhone connects to one Dock Relay Aggregator; that relay owns host/provider fan-out, Codex decoding, status normalization, caching, last-good state, snapshots, deltas, and resync. The client renders a clean `DockSnapshot` and never sees raw `thread/list`, `notLoaded`, cursors, live overlays, or provider-specific source fields.

**Evidence Read**

- Goal and working doc: [goal.md](/Users/aelaguiz/workspace/codex-client/.arch_skill/model-consensus/dock-relay-aggregator-architecture-20260529T194433Z/goal.md:1), [architecture draft](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md:1). These set the relay-as-hard-worker constraint.
- Root cause: [home refresh RCA](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_HOME_REFRESH_NOT_LOADED_ROOT_CAUSE_2026-05-29.md:1). It proves destructive partial snapshots and raw `notLoaded` leakage.
- Relay code: [dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:450), [dock-relay-thread-data.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:457), [dock-relay-live-status-cache.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-live-status-cache.mjs:7). Today the relay is a smart proxy plus caches, not a durable snapshot owner.
- Swift client: [DockStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockStore.swift:665), [AppServerDockClient.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/AppServerDockClient.swift:101), [ThreadListDTO.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/ThreadListDTO.swift:150), [SessionSummaryMapper.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Models/SessionSummaryMapper.swift:328). The client currently fans out, pages, decodes, maps, dedupes, and publishes partial state.
- Upstream Codex: [README](/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:137), [thread_status.rs](/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs:366). `notLoaded` is a runtime-memory status, not a product row state.

**Target Boundaries**

- Client: one aggregator connection, current snapshot, ordered update application, explicit resync, UI filters/search/grouping, local labels/rails.
- Relay aggregator: provider adapters, peer/host federation, canonical session store, row ordering, host status, stale-while-refresh, summaries, deltas, resync, retry/backoff, redacted diagnostics.
- Provider adapters: Codex, later Claude Code, etc. They translate provider facts into canonical facts. They do not define client protocol.

**Relay State Model**

- `epoch`: changes on relay restart or store reset.
- `seq`: monotonic update number inside an epoch.
- `hosts[hostID]`: `online | refreshing | degraded | stale | offline`, `lastSuccessAt`, `lastAttemptAt`, `rowCount`, safe display fields.
- `sessions[sessionID]`: stable key like `hostID/providerKind/providerSessionID`; title, workspace, repo, branch, summary, `updatedAt`, source class, runtime state, detail availability, archive state.
- `eventLog`: bounded in-memory update log for recent deltas.
- `lastGoodSnapshot`: atomically persisted under `.codex-dock/` so restart or upstream failure can still serve fast rows.

**Provider Adapter Model**

Each adapter implements: discover/connect, full scan, optional watch stream, detail read/resume/send/archive, status normalization, and safe diagnostics. Codex’s adapter combines history `thread/list`, live `thread/loaded/list`, `thread/read`, status notifications, and summary warming; it maps Codex `notLoaded` to something like `detailAvailability: "cold"` plus `runtimeState: "inactive"` instead of exposing `Not loaded`.

**Wire Protocol Shape**

Use JSON-RPC over the existing WebSocket, but add a new provider-agnostic API:

```json
dock/subscribe { "protocol": 1, "lastEpoch": "...", "lastSeq": 42 }
=> { "type": "snapshot", "epoch": "...", "seq": 100, "hosts": [], "sessions": [] }

dock/update notification:
{ "epoch": "...", "baseSeq": 100, "seq": 101,
  "upsertHosts": [], "upsertSessions": [], "deleteSessionIDs": [] }

dock/resync { "reason": "gap|reconnect|manual", "lastEpoch": "...", "lastSeq": 101 }
=> full snapshot
```

If `baseSeq` does not equal the client’s current `seq`, the client ignores the delta and calls `dock/resync`.

**Failure Semantics**

A failed refresh never clears rows. It marks the affected host/provider `stale`, keeps last-good sessions, and adds `lastError` metadata. Rows disappear only on explicit archive/delete/tombstone or a relay-owned retention rule. Live-status failure downgrades runtime freshness; history failure downgrades host freshness; neither becomes an empty list.

**Security**

`OPENAI_API_KEY`, raw Codex bearer tokens, provider credentials, loopback URLs, and `dockRelaySource` stay relay-side. Phone config remains host/port bootstrap only. `/statusz` stays redacted. The phone cannot send provider config or select transcription providers.

**Migration**

1. Add relay-owned `dock/subscribe`, `dock/update`, and `dock/resync` beside existing raw methods.
2. Build the Codex adapter from current relay pieces, but change ownership: relay produces canonical sessions.
3. Add coordinator behavior: saved phone endpoints become bootstrap candidates; the connected relay federates peers and returns one global Dock snapshot.
4. Move Swift Dock home to the new snapshot DTO. Delete `thread/list` paging, source decoding, `notLoaded` row status, multi-host fan-out, and scope dedupe from Dock home.
5. Keep raw detail methods temporarily; migrate detail later to the same snapshot/update/resync pattern.

**Tests**

Relay: adapter normalization, last-good snapshot persistence, stale-while-refresh, delta gap handling, peer federation, and “Codex `notLoaded` never appears on the client wire.”

Swift: decode canonical snapshot/update, apply ordered deltas, resync on gap, keep rows stale during disconnect.

Client proof: simulator first with `rtk make app-test SIM='iPhone 17'` and `rtk make app SIM='iPhone 17'`; verify logs show one aggregator subscription, stable Home rows during slow refresh, and no raw `thread/list` home path.

**Rejected Alternatives**

- Patch Swift with per-host stale cache: fixes flicker but keeps the wrong owner.
- Keep `thread/list + liveOverlay`: still Codex-shaped and not durable.
- Client connects to every relay and merges snapshots: violates the one-stream client goal.
- Forward raw provider notifications: leaks provider semantics and makes Claude Code hard.
- No persisted last-good snapshot: fast startup and transient tolerance fail after relay restart.

**Risks / Open Questions**

- Peer federation topology: every relay as coordinator vs one nominated coordinator.
- Peer auth between relays.
- Whether snapshot persistence should start as atomic JSON or SQLite.
- How much detail state joins v1 versus staying behind existing detail APIs.
- Exact stale/retention TTLs.

**Need From Model B**

I need Model B to challenge the one-stream coordinator assumption, the persisted snapshot choice, and whether UI filtering should stay client-side. If B agrees on those three, the rest should converge cleanly.