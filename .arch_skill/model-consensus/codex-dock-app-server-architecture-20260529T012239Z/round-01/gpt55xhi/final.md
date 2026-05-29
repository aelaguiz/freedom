**Verdict**

Keep the relay, but redesign it as a Mac-side Codex Dock host agent. The current shape is too fragile: it treats endpoint aliases as hosts, discovers live sessions in request paths, opens too many upstream WebSockets, hides live failures, drops pagination cursors, and sorts live rows ahead of history rows instead of globally sorting.

This is a large rewrite, and it is worth doing.

**Evidence Read**

I read the required Dock files: `AGENTS.md`, `README.md`, `Makefile`, `package.json`, `Package.swift`, `project.yml`, both named docs, the relay scripts, host-service script, `AppServerClient.swift`, `DockStore.swift`, `DockSessionProjection.swift`, `HostRegistry.swift`, and `RelayBootstrapStore.swift`.

I also read the required Codex source under `/Users/aelaguiz/workspace/codex/codex-rs/**`, including app-server main/lib, thread processor/status/filtering, WebSocket transport/auth, remote control, daemon, managed install, thread manager, local thread listing, and protocol v2 thread definitions.

**Codex App-Server Truths**

Codex has two different planes:

- History plane: durable thread metadata and turns from the thread store/state DB/rollout files. `thread/list`, `thread/read`, and `thread/turns/list` mostly live here.
- Live plane: process-local loaded threads inside one app-server process. `thread/loaded/list` is only “what this one process has in memory,” not global truth.

`thread/list` is not a global live-session API. It reads history and overlays statuses only for threads loaded in that same process.

`thread/loaded/list` is process-local and sorted by thread ID, not recency.

Raw `thread/list` caps `limit` at `100`. Dock asking for `200` does not make Codex return 200 raw rows.

Session identity is Codex `threadId`. Host identity must be Dock’s logical host identity. Endpoint aliases like `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510` must not become separate logical hosts.

Transport truth:

- App-server supports `stdio://`, `unix://`, `ws://IP:PORT`, and `off`.
- Non-loopback WebSocket requires auth.
- The daemon path normally runs `app-server --remote-control --listen unix://`.
- Phones must connect to Dock relay `:4510`, not raw authenticated app-server `:4500`.

Loaded threads are process lifetime state. They can unload after inactivity/no subscribers. A thread ID does not tell Dock which process currently owns the live instance.

**Proposed Architecture**

Codex Dock should have one Mac-side Host Agent, implemented as the relay process or a replacement for it.

The Host Agent owns:

- Raw Codex app-server auth.
- `OPENAI_API_KEY` and transcription provider config.
- Phone-safe WebSocket endpoint on `:4510`.
- Logical host identity and endpoint fallback metadata.
- A bounded upstream connection pool to the raw history app-server.
- A background live-session registry.
- History/live merge, dedupe, sort, pagination, and degradation metadata.
- Health, metrics, debug snapshots, and service diagnostics.

Swift owns:

- Rendering.
- Search/filter/tab projection.
- Saved device config.
- Selecting a logical host and its endpoint fallback list.
- Detail-view state.

Swift should not own alias dedupe, live discovery, upstream fanout, or Codex history/live merge semantics.

**Data And Control Flow**

Normal list flow:

`iPhone/simulator -> ws://<Mac host>:4510 -> Host Agent -> history app-server ws://127.0.0.1:4500 + live endpoint registry -> merged session list`

Detail flow:

`Swift opens thread -> Host Agent routes read/turns/subscription to owning live endpoint if loaded, otherwise history endpoint`

Turn flow:

`turn/start`, `turn/steer`, and `turn/interrupt` must route to the active live upstream for that session. If no live upstream exists, the Host Agent must explicitly resume or fail with a clear state.

Discovery flow must be background-only. Do not run `ps`, `thread/loaded/list`, or per-row `thread/read` inside every list request.

The transitional live discovery can still use `ps`, but only as a cached background scanner with backoff and visible failure state. The ideal end state is a first-class Codex endpoint/session registry exposed by the daemon or remote-control layer.

**Identity, Deduping, Sorting, And Pagination**

Canonical row key:

`logicalHostId + threadId`

Not:

`endpointHost + endpointPort + threadId`

Merge rule:

- History row is the durable base.
- Live row overlays status, live owner endpoint, active flags, and freshest live-only metadata.
- `updatedAt` should be the freshest trustworthy activity timestamp.
- Live-only rows are allowed, but must be marked as `liveOnly`/not-yet-durable.

Sorting rule:

Globally sort after merge and dedupe. Never concatenate “live first, history second.”

For newest sort:

`updatedAt desc`, then stable tie-breakers such as status priority and `threadId`.

Pagination rule:

Relay cursors must be real. Do not return `nextCursor: null` after reading a raw paginated source.

The relay cursor should be opaque and include enough state to continue the merged list, for example sort tuple, history cursors by scope, and live snapshot version.

**Observability And Debuggability**

Relay logs should be structured and redacted. Include:

`requestId`, `method`, `logicalHostId`, `historyRows`, `liveRows`, `mergedRows`, `historyLatencyMs`, `liveLatencyMs`, `failedLiveEndpoints`, `degraded`, `cursorPresent`, `upstreamSocketCount`, `fdCount`, and `cacheAgeMs`.

Never log bearer tokens, `OPENAI_API_KEY`, prompt text, transcript text, raw audio, base64 audio, or full JSON-RPC payloads.

Endpoints should mean different things:

- `/readyz`: relay can accept connections.
- `/healthz`: static config and lightweight dependency state.
- `/statusz`: redacted full state: history health, live registry health, pool state, endpoint failures, logical host config.
- `/metricsz`: counters/gauges for sockets, failures, timeouts, discovery age, rows merged, duplicate rows.
- `/debugz/sessions`: redacted row keys, timestamps, status, provenance, and owning live endpoint.

The next failure should answer: “history down, live discovery down, endpoint alias duplication, stale cache, sort bug, cursor bug, or socket leak.”

**Makefile And Ops Surface**

Keep these canonical:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make host-service-doctor
rtk make app SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>
rtk make device-install-all
rtk make device-config-verify DEVICE=<device-udid>
```

Add these:

```bash
rtk make dock-relay-doctor
rtk make dock-relay-sessions
rtk make dock-relay-fds
rtk make device-config-verify-all
rtk make sim-config-verify SIM='iPhone 17'
```

Device config should use explicit profiles:

- iPhone 17 Pro `CB9FFF0E-89AD-57B5-9C00-6552D814875E`: `amir-m5.fairy-salmon.ts.net:4510`, `home.fairy-salmon.ts.net:4510`
- iPhone 14 `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`: `Amir-M5.local:4510`, `192.168.50.74:4510`

These are fallback endpoints for one logical host, not separate hosts.

**Testing And Acceptance Gates**

Relay unit tests must cover:

- Global sort after live/history merge.
- Alias dedupe into one logical host.
- Real cursor preservation.
- Live discovery failure returning degraded metadata.
- Bounded upstream socket counts.
- Timeout closes/terminates upstream sockets.
- No per-row preview fanout in the list hot path.

Swift unit tests must cover:

- Host registry groups fallback endpoints.
- `DockStore` loads once per logical host, not once per alias.
- Degraded relay metadata maps to visible UI state.
- Per-device endpoint config stays separate.
- Idle filtering does not masquerade as missing data.

Service tests must prove:

- Repeated reloads do not grow file descriptors.
- `thread/loaded/list` succeeds when live sessions exist.
- Killing a live endpoint degrades visibly instead of silently returning stale history-only rows.

Physical-device acceptance:

- Phone connects only to relay `:4510`.
- Phone receives no raw app-server bearer token and no `OPENAI_API_KEY`.
- Installed app renders real `SessionSummary` rows over the relay path.
- The same host path shows offline/error UI when unavailable.

**Migration / Replacement Plan**

1. Replace endpoint-as-host with logical host plus fallback endpoints.
2. Add relay degradation metadata and expose it in Swift.
3. Remove per-row preview enrichment from `thread/list`.
4. Replace hot-path live discovery with a background live registry.
5. Replace fresh upstream WebSocket per operation with bounded clients/pools.
6. Fix merge: dedupe first, then globally sort, then paginate.
7. Preserve raw history cursors through relay cursors.
8. Add redacted debug and metrics endpoints.
9. Move toward a Codex-native live endpoint registry so `ps` discovery can be deleted.

**Risks And Non-Negotiable Invariants**

Raw `:4500` history is not global live truth.

`thread/loaded/list` is process-local.

A phone must never connect directly to raw authenticated `:4500`.

A phone must never receive raw app-server bearer tokens or `OPENAI_API_KEY`.

Endpoint aliases must not multiply host loads.

Relay upstream sockets must be bounded and stable after repeated refreshes.

Live failure must be visible as degraded state.

Merged rows must be globally sorted after dedupe.

Pagination cursors must not be discarded.

Agent scope must explicitly request agent `sourceKinds`; nil/empty means interactive defaults.

Relay must respect raw Codex `thread/list` max `limit=100`.

**Open Questions For Consensus**

Should Codex expose a first-class daemon/session registry so Dock can delete `ps` discovery entirely?

Should Dock define aggregate RPC methods like `dock/session/list`, or keep overloading `thread/list` behind the relay?

Should previews be removed from list rows or served by a bounded lazy preview endpoint?

What stable `logicalHostId` values should be used for `Amir-M5` and `home`?

Should the relay subscribe to all loaded sessions, or only detail-open sessions plus periodic list snapshots?

What degradation states should block display versus show partial data?