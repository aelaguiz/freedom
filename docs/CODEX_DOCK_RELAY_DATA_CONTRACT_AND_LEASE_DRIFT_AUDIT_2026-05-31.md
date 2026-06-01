# Codex Dock Relay Data Contract And Lease Drift Audit - 2026-05-31

> 2026-05-31 implementation note: this file began as a pre-fix root-cause
> audit. Lower sections intentionally preserve historical evidence about the
> bug and deleted side doors. Current shipped card truth is `dock/*` and
> `archive/*` only. `relay/state/snapshot`, `state/query`, `thread/search`,
> `thread/goal/get`, app-facing `thread/loaded/list`, `/statez`, `/dbz`,
> `/explainz`, `/debugz`, `/subscriptionsz`, `/tracesz`, `/selftestz`, and
> `/bundlez` are not valid current card proof paths.

Current UX intention:
[CODEX_DOCK_USER_INTENTION_2026-06-01.md](CODEX_DOCK_USER_INTENTION_2026-06-01.md),
[CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md](CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md)
and
[CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md](CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md).

## Historical Bottom Line

The original drift was real. Before the single-source implementation, the
generated Dock card contract kept the JSON payload shape aligned between relay
and Swift, but it did not unify the semantic source of truth for activity time,
row order, live lease state, host freshness, or turn-level updates.

The exact pre-fix failure mode was: Dock cards were built from thread-level
`thread/list` plus `thread/read includeTurns:false`, while current work could
live only in `thread/turns/list` or live turn events. The implemented fix folds
those inputs through the canonical relay card projection before any Dock or
Archive card stream is emitted.

Implementation plan: [Codex Dock Data Contract Single Source Implementation Plan](CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md).

## Runtime Evidence From The Current Bug

Observed on 2026-05-31:

- Active thread: `019e7e7d-66ca-7280-9aa0-2e272f1752b1`.
- `thread/read` returned `updatedAt=1780238608`, which is `2026-05-31T14:43:28Z`.
- `thread/turns/list` returned newer turns:
  - `startedAt=1780249079`, `2026-05-31T17:37:59Z`, status `interrupted`.
  - `startedAt=1780246962`, `2026-05-31T17:02:42Z`, status `completed`.
- `dock/subscribe` used the stale thread-level activity timestamp, so the card sorted as old even though current turn activity existed.

Plain English: the relay did not lose the current work. It was visible on the turn-detail route. The Dock overview simply never looked at that route when creating the card.

## What The Existing Generated Contract Actually Protects

The canonical card payload shape is `contract/dock/dock-thread-card.schema.json`.

Line audit:

| File | Lines | What it protects | What it does not protect |
| --- | ---: | --- | --- |
| `contract/dock/dock-thread-card.schema.json` | 6-23 | Every stream update must have `kind`, `schemaVersion`, `view`, `epoch`, and `seq`; schema version is fixed at `2`. | It does not say where `activityAtMs` must come from. |
| `contract/dock/dock-thread-card.schema.json` | 30-95 | The stream may carry `complete`, `totalRows`, `window`, `freshness`, hosts, cards, upserts, and deletes. | It does not prove a complete stream inspected turns. |
| `contract/dock/dock-thread-card.schema.json` | 97-124 | Old session/message fields are explicitly rejected. | It only rejects obsolete fields; it does not validate semantic freshness. |
| `contract/dock/dock-thread-card.schema.json` | 157-191 | Host-level freshness has `unknown`, `fresh`, `stale`, `offline`, `error`. | It does not define row-level freshness behavior during retained stale rows. |
| `contract/dock/dock-thread-card.schema.json` | 223-240 | Card required fields include `orderKey`, `activityAt`, `displaySummary`, `title`, `status`, `sourceKind`, `lane`, `archiveState`, `freshness`, and `completeness`. | It requires these fields to exist, not to be derived from the latest real work. |
| `contract/dock/dock-thread-card.schema.json` | 269-282 | `orderKey`, `activityAt`, and optional `activityAtMs` exist in the payload. | It does not say whether order uses list ordinal, thread `updatedAt`, latest turn time, or lease time. |
| `CodexDock/AppServer/DockThreadCardDTO.swift` | 1-2 | Swift DTO is generated from that schema. | Generated Swift mirrors shape only. |
| `CodexDock/AppServer/DockThreadCardDTO.swift` | 342-365 | Swift decodes the card fields exactly as the relay sends them. | Swift has no second source for newer card activity. |
| `scripts/generate-dock-thread-card-contract.mjs` | 500-518 | `npm run contract:check` fails if generated Swift is stale. | The generator cannot detect bad source selection inside relay projection. |

Net: we made payload-shape drift hard. We did not make data-source drift hard.

## Exhaustive Contract Surface Map

This section is the missing contract map. It separates three things that had
been blurred together:

1. The source that owns data.
2. The endpoint that exposes or transforms that data.
3. The app or script that consumes that endpoint.

The important point: the generated `DockThreadCard` contract covers only the
card stream shape. It does not cover every source, every relay route, or every
consumer that can affect what the user sees.

### Data Planes

| Plane | What it is | Primary owners | Primary consumers | Contract status |
| --- | --- | --- | --- | --- |
| Raw Codex history | The app-server at `historyUrl`; relay reads it through pooled JSON-RPC. | `scripts/dock-relay-thread-data.mjs:38-48`, `scripts/dock-relay-thread-data.mjs:552-566` | Relay `thread/list`, `thread/read`, `thread/turns/list`, `thread/search`, `thread/goal/get`, Dock reconcile | Not covered by `DockThreadCard`; raw `ThreadDTO`/list/detail shapes. |
| Live upstream sessions | Current app-server sessions found through `thread/loaded/list` and `thread/read`. | `scripts/dock-relay-thread-data.mjs:92-120`, `scripts/dock-relay-live-status-cache.mjs:94-153` | `SessionRouter`, `thread/read`, `thread/turns/list`, `thread/resume`, live leases | Not covered except when projected into a card stream. |
| Relay SQLite projection | `.codex-dock/relay-state.sqlite`; stores projected cards, sync scopes, changes, and live leases. | `scripts/dock-relay-state-store.mjs:124-195`, `scripts/dock-relay-state-store.mjs:535-620` | `dock/subscribe`, `dock/update`, `dock/resync`, `archive/*`, diagnostics | Card rows are covered after projection; DB-only fields are not. |
| Generated card contract | JSON schema plus generated Swift DTO for card stream updates. | `contract/dock/dock-thread-card.schema.json`, `CodexDock/AppServer/DockThreadCardDTO.swift` | Dock, Archive, cleanup, snapshot loader | Covers shape, enum vocabulary, stream version, and required fields. Does not cover freshness source. |
| Swift local metadata | User-owned local pin/label/rail display state. | `CodexDock/State/LocalThreadMetadataStore.swift:3-120`, `CodexDock/Metadata/LocalMetadataEngine.swift:83-105` | Dock projection, Archive, Archive cleanup | Not covered; it is a local overlay keyed by card identity. |
| Detail/live event stream | Raw thread turns, notifications, and server requests after opening a thread. | `CodexDock/State/ThreadDetailStore.swift:563-625`, `scripts/dock-relay.mjs:446-524` | Thread Detail, composer, request cards | Not covered by `DockThreadCard`; mostly `ThreadDTO`, turn DTOs, and raw `JSONValue`. |
| Observability | Route health, traces, metrics, status snapshots. | `scripts/dock-relay-observability.mjs`, `scripts/dock-relay-status.mjs` | Connectivity UI, diagnostics, Makefile targets, audits | Not a data contract for rows. |
| Voice transcription | Relay-owned realtime transcription bridge. | `scripts/dock-relay-realtime-transcription.mjs`, `CodexDock/AppServer/RealtimeTranscriptionDTO.swift` | Voice composer | Separate voice contract; no Dock card authority. |

### Source Inventory

| Source / table / cache / file | Fields it owns | Writers | Readers / consumers | Drift risk | Covered by generated card schema? |
| --- | --- | --- | --- | --- | --- |
| Raw `thread/list` history | Thread rows, list pagination, thread-level `updatedAt`/`createdAt`, title/name/status/path/source metadata. | Raw app-server. | `aggregateThreadList`, Dock reconcile, Archive reconcile, diagnostics. | High: list metadata can be older than latest turns. | No. |
| Raw `thread/read` history | Authoritative thread object, optionally turns if requested. | Raw app-server. | Detail load, relay human-thread validation, route assertions, session-index validation. | High: Dock enrichment requests `includeTurns:false`, so turns are excluded. | No. |
| Raw `thread/turns/list` | Turn pages, turn timestamps, item history. | Raw app-server or live owner. | Thread Detail, `relay/state/snapshot`, parity/sync audits, summary cache. | High: newest work can live here while Dock cards ignore it. | No. |
| Raw `thread/search` | Search result rows. | Raw app-server. | Relay route and diagnostic/oracle scripts. No Swift app method was found. | Medium: useful for probes, not global row truth. | No. |
| Raw `thread/goal/get` | Goal objective/status/budget/token fields. | Raw app-server or live owner. | Relay route, parity/sync audit. Not current Swift client path. | Medium: another truth surface outside cards. | No. |
| Raw `thread/loaded/list` | Live thread IDs. | Live endpoints. | `LiveStatusCache`, `thread/loaded/list`, live lease refresh, diagnostics. | High: membership/status only; no card summary or latest turn data. | No. |
| `$CODEX_HOME/session_index.jsonl` | Candidate thread id/name/updated time for missing human-started sessions. | Codex home session index writer. | `readSessionIndexCandidates`, `readSessionIndexHumanStartedSupplements`, Dock/list supplement path. | High side door: can add rows not returned by `thread/list`. | Only after normalized into card fields. |
| `threads` SQLite table | Projected card id, host fields, order, activity, title, summary, status, lane/source, repo/cwd/branch, archive state, freshness, raw projected JSON. | `applyDockReconciliation`, `applyArchiveReconciliation`, `applyArchiveMutation`, `upsertThreadCard`. | `listDockCards`, `listArchiveCards`, `cardForThread`, `/explainz/thread`. | Very high: this is what card streams actually serve. | Card fields yes; DB-only fields no. |
| `thread_field_provenance` SQLite table | Intended per-field source provenance. | Table exists at `scripts/dock-relay-state-store.mjs:159-167`. | No production Dock ordering/recency reader found. | Medium: looks like a drift-control mechanism but is not wired to card semantics. | No. |
| `sync_scopes` SQLite table | Scope freshness, completion, generation, last attempt/sync/error. | `recordSyncScope`, `markScopeStale`. | `freshnessForHost`, snapshots, `/syncz`, host freshness display. | High: host freshness is scope-level, not row-level truth. | Stream freshness shape yes; semantics no. |
| `live_leases` SQLite table | Live endpoint, backend session id, status, waiting state, validation time, expiry. | `refreshLiveLeases`, `upsertLiveLease`. | `listDockCards`, `cardForThread`, `applyDockReconciliation`, lease-expiry publishing. | High: status can update while activity/title/summary remain stale. | Only projected `status`/`backendSessionID`; lease metadata is hidden. |
| `changes` SQLite table | Global stream sequence and change payload log. | `recordChange`. | Subscribers, snapshots, deltas, resync. | Medium: sequence proof, not semantic proof; pruned to a bounded history. | `seq`/`baseSeq`/`stateGeneration` yes. |
| `LiveStatusCache` memory cache | Live overlay state, checked time, endpoint failures, live rows. | `refreshNow`. | `SessionRouter`, `aggregateLoadedList`, `aggregateThreadRead`. | High: independent from SQLite `live_leases`. | No, except indirect projected effects. |
| `SessionRouter` | Which endpoint owns a thread right now. | Built from `LiveStatusCache`. | `thread/read`, `thread/turns/list`, `thread/goal/get`, `thread/resume`. | High: detail can route to newer live owner while Dock still serves old projection. | No. |
| Active resumed upstream session | Bound thread live connection for turn commands and request cards. | `thread/resume` relay path. | `turn/start`, `turn/steer`, `turn/interrupt`, upstream server requests. | Medium-high: live session state does not automatically update Dock cards. | No. |
| Local `thread-metadata.json` | User label, rail, pin state, pin order, cached pinned display snapshot. | `LocalMetadataEngine`. | Dock rows, pinned rows, Archive, Archive cleanup. | High: cached pinned display can outlive current stream truth. | No. |
| Scripted/debug/preview fixtures | Fake cards, fake streams, fake detail sessions. | DEBUG/test code. | Swift tests and previews. | High if mistaken for production proof. | Sometimes uses generated DTOs, but not production evidence. |

### Endpoint Inventory

The endpoints divide into app card contracts, thread/detail contracts, side-door
diagnostics, and unrelated voice/health contracts.

| Endpoint / route | Handler | Data sources touched | Current consumers | Contract status | Drift / side-door risk |
| --- | --- | --- | --- | --- | --- |
| `initialize` | `scripts/dock-relay.mjs:461-468` | Config, OS, `CODEX_HOME`. | Swift handshake in `AppServerClient`. | Not card contract. | Low. |
| `initialized` notification | Relay ignores at `scripts/dock-relay.mjs:1070`. | None. | Swift sends after initialize. | Not card contract. | Low. |
| `thread/list` | `scripts/dock-relay.mjs:469-470`, `scripts/dock-relay-thread-data.mjs:872-907` | History list, human filter, `thread/read includeTurns:false`, session index, live overlay. | Swift wrapper exists; relay/Dock internals and tests use it. README says Dock UI should not use it as list contract. | No. | High side door: raw list is not the app-facing card stream. |
| `thread/search` | `scripts/dock-relay.mjs:471-472`, `scripts/dock-relay-thread-data.mjs:909-927` | History search plus human filter. | Tests/oracle scripts; no Swift method in `AppServerMethods`. | No. | Medium: useful for probes, not complete list truth. |
| `thread/goal/get` | `scripts/dock-relay.mjs:473-474`, `scripts/dock-relay-thread-data.mjs:929-942` | History or routed live owner. | Sync/parity audits; not current Swift Dock/Detail path. | No. | Medium: separate thread state not exposed by cards. |
| `dock/subscribe` | `scripts/dock-relay.mjs:475-476`, `scripts/dock-relay-state-engine.mjs:603-675` | Relay SQLite projection built from history/live/session-index sources. | Dock stream client, Dock store. | Yes, primary Dock card contract. | High if projection source is stale while shape is valid. |
| `dock/update` notification | `scripts/dock-relay-state-engine.mjs:646`, `scripts/dock-relay-state-subscriptions.mjs:112` | Relay SQLite projection and `changes`. | `AppServerThreadCardStreamClient`, `ThreadCardTable`. | Yes. | Primary delta path; shape-safe, source-unsafe. |
| `dock/resync` | `scripts/dock-relay.mjs:477-478`, `scripts/dock-relay-state-engine.mjs:678-690` | Relay SQLite projection. | Dock stream client after gaps/schema errors. | Yes. | Recovery path; still returns projected truth. |
| `archive/subscribe` | `scripts/dock-relay.mjs:479-480`, `scripts/dock-relay-state-engine.mjs:617-629` | Relay SQLite projection built from archived scope. | Archive UI, snapshot loader. | Yes, archive view. | Separate stream path from active Dock. |
| `archive/update` notification | `scripts/dock-relay-state-engine.mjs:646` | Relay SQLite projection and `changes`. | Archive stream client. | Yes, archive view. | Same source-safety limits as Dock. |
| `archive/resync` | `scripts/dock-relay.mjs:481-482`, `scripts/dock-relay-state-engine.mjs:691-703` | Relay SQLite projection. | Archive stream recovery. | Yes, archive view. | Recovery path; projected truth only. |
| `relay/state/snapshot` | `scripts/dock-relay.mjs:483-484`, `scripts/dock-relay-state-snapshot.mjs:564-590` | App-server list/read/turn/goal/loaded surfaces; explicitly not the SQLite stream source. | Oracle audits/tests. | No. | High side door: can be fresher or different from Dock stream. |
| `thread/loaded/list` | `scripts/dock-relay.mjs:485-486`, `scripts/dock-relay-thread-data.mjs:944-955` | `LiveStatusCache` live rows. | Relay internals/tests/diagnostics. | No. | Live membership only, not row data. |
| `thread/read` | `scripts/dock-relay.mjs:487-488`, `scripts/dock-relay-thread-data.mjs:957-974` | Live row fast path or history. | Thread Detail load and relay validation. | No. | Detail can be current while Dock card remains old. |
| `thread/turns/list` | `scripts/dock-relay.mjs:489-490`, `scripts/dock-relay-thread-data.mjs:976-985` | History or routed live owner. | Thread Detail, diagnostics, state snapshot. | No. | Primary source of newest work, but not part of card projection. |
| `thread/resume` | `scripts/dock-relay.mjs:491-492` | Active live upstream session plus human-thread assertion. | Thread Detail live attach. | No. | Starts live detail path; no automatic Dock card repair. |
| `thread/archive` | `scripts/dock-relay.mjs:493-500` | Upstream archive command and local SQLite mutation. | Row/context archive command. | Indirect only through emitted card deltas. | Medium-high: local mutation can temporarily diverge from upstream. |
| `thread/unarchive` | `scripts/dock-relay.mjs:502-509` | Upstream unarchive command and local SQLite mutation. | Archive restore command. | Indirect only through emitted card deltas. | Medium-high: same local mutation drift. |
| `state/query` | `scripts/dock-relay.mjs:511-512` | Relay SQLite projection. | Tests/diagnostics; not in `AppServerMethods`. | Not route-contract covered. | Side door around subscribe/update sequencing. |
| `turn/start` | `scripts/dock-relay.mjs:521-524`, `scripts/dock-relay.mjs:446-456` | Active resumed upstream session. | Composer send path. | No. | Requires active thread binding; not Dock source. |
| `turn/steer` | `scripts/dock-relay.mjs:521-524`, `scripts/dock-relay.mjs:446-456` | Active resumed upstream session. | Composer active-turn send path. | No. | Not Dock source. |
| `turn/interrupt` | `scripts/dock-relay.mjs:521-524`, `scripts/dock-relay.mjs:446-456` | Active resumed upstream session. | Constant exists; no typed Swift wrapper found. | No. | Exposed side route. |
| Upstream server request bridge | `scripts/dock-relay.mjs:332`, `scripts/dock-relay.mjs:1045` | Active resumed upstream session. | Thread Detail request cards and responses. | No. | Raw JSON-RPC side channel; payload shape can drift. |
| `audio/transcription/start` | `scripts/dock-relay.mjs:513-514` | Relay realtime transcription session. | Voice client. | Separate voice DTO. | Not Dock data. |
| `audio/transcription/append` | `scripts/dock-relay.mjs:515-516` | Relay realtime transcription session. | Voice client. | Separate voice DTO. | Not Dock data. |
| `audio/transcription/commit` | `scripts/dock-relay.mjs:517-518` | Relay realtime transcription session. | Voice client. | Separate voice DTO. | Not Dock data. |
| `audio/transcription/cancel` | `scripts/dock-relay.mjs:519-520` | Relay realtime transcription session. | Voice client. | Separate voice DTO. | Not Dock data. |
| Audio transcription notifications | `scripts/dock-relay.mjs:999`, realtime transcription module. | Relay realtime transcription session. | Voice client notification switch. | Separate voice DTO. | Not Dock data. |
| `/readyz` | `scripts/dock-relay.mjs:850-856` | Relay process/config only. | Makefile/service probes/manual checks. | No. | High if mistaken for app-path proof. |
| `/healthz` | `scripts/dock-relay.mjs:858-870` | Relay process/config only. | Service probes. | No. | Health does not mean row freshness. |
| `/statusz` | `scripts/dock-relay.mjs:763-767`, `scripts/dock-relay.mjs:872-881` | Raw app-server health, runtime, route status, state summary. | Connectivity diagnostics, relay status targets. | No. | Good diagnostic surface, not row contract. |
| `/metricsz` | `scripts/dock-relay.mjs:769-774`, `scripts/dock-relay.mjs:883-886` | Observability/runtime/state summaries. | Diagnostics/scripts. | No. | Metrics only. |
| `/debugz/sessions` | Deleted from shipped relay HTTP surface. | Runtime sessions. | Negative 404 tests only. | No. | Do not restore as a card or runtime proof path. |
| `/routesz` | `scripts/dock-relay.mjs:783-794`, `scripts/dock-relay.mjs:891-894` | Route health. | `RelayDiagnosticsClient`, `AppConnectivityStore`. | No. | Route health is not data freshness. |
| `/statez` | Deleted from shipped relay HTTP surface. | Former relay state snapshot. | Negative 404 tests only. | No. | Deleted because it was a card-state side door. |
| `/syncz` | Shipped, stripped to service availability only. | `{ ok, service, schema, state }`. | Diagnostics/tests. | No. | No card, DB, route, or sync-scope payload. |
| `/subscriptionsz` | Deleted from shipped relay HTTP surface. | Former subscription counts. | Negative 404 tests only. | No. | Do not restore as proof. |
| `/dbz` | Deleted from shipped relay HTTP surface. | Former SQLite health/details. | Negative 404 tests only. | No. | Deleted because DB reads were a side-door proof path. |
| `/explainz/thread/{threadID}` | Deleted from shipped relay HTTP surface. | Former stored-card explanation. | Negative 404 tests only. | No. | Deleted because it exposed stored card truth outside `dock/*` and `archive/*`. |
| `/tracesz/recent` and `/tracesz/{operationID}` | Deleted from shipped relay HTTP surface. | Former observability traces. | Negative 404 tests only. | No. | Do not restore as card evidence. |
| `/selftestz` | Deleted from shipped relay HTTP surface. | Former route registry/state checks. | Negative 404 tests only. | No. | Do not restore as proof. |
| `/bundlez` | Deleted from shipped relay HTTP surface. | Former mixed diagnostic bundle. | Negative 404 tests only. | No. | Do not restore as proof. |

### Current Consumer Inventory

| Consumer / surface | What it consumes | Fields used | Alternate source or side door | Drift risk |
| --- | --- | --- | --- | --- |
| `AppServerThreadCardStreamClient` | `dock/subscribe`, `dock/update`, `dock/resync`, `archive/*`. | Decoded `ThreadCardStreamUpdateDTO`. | DEBUG scripted stream client. | Route/view mismatch or stale projected cards. |
| `ThreadCardTable` / `DockDataEngine` | `ThreadCardStreamUpdateDTO`. | Schema version, view, epoch, seq, window, hosts, cards, upserts, deletes. | None. | Strict shape gate, no semantic freshness gate. |
| `DockStore` | Card stream, local metadata, connectivity, commands. | Hosts, cards, local labels/pins/rails, row command targets. | Local metadata and reconnect state. | Retained stale rows plus local overlays can remain visible. |
| `HumanThreadCardPolicy` | Card `lane` and `sourceKind`. | Human vs automation eligibility. | Cached pinned origin kind. | Relay human classification changes can drop/keep rows. |
| `ThreadCardRowProjector` | `DockThreadCardDTO` plus local metadata. | Thread id, backend id, host, title, repo, branch, status, activity, summary, source, relationship, pin/label/rail. | Cached pinned display snapshot. | Wrong relay activity/title becomes wrong UI. |
| `DockCardProjection` / `DockScreenStore` | Projected rows. | Search/filter/sort facets, pin grouping, row dates, host states. | Local metadata. | UI sorts over whatever activity date the relay/local cache supplied. |
| Dock views/context menus | Projected rows and commands. | Display text, status, host, labels, pin/archive actions. | User metadata actions. | Mostly display/action drift. |
| Local metadata engine | `thread-metadata.json` keyed by host/backend/thread id. | label, rail, pin order, cached pinned display. | None; local store is its own source. | Can preserve stale title/status/summary for pinned missing rows. |
| Archive UI | `archive/subscribe`, `archive/update`, `archive/resync`. | Same card fields, archive grouping. | Local metadata. | Separate stream path from Dock. |
| Archive cleanup | One-shot `dock` stream snapshot. | last activity, source/origin, pin status, status, labels. | Local metadata. | Cleanup decisions depend on projected row truth. |
| `ThreadCardStreamSnapshotCollector` | Subscribe/update stream until complete. | Schema version, expected view, hosts/cards/upserts/deletes, complete/window. | Used by Archive and Cleanup. | Less strict than `ThreadCardTable`; sorts by `orderKey`. |
| Thread Detail entry | Dock row snapshot, then `thread/read`, `thread/turns/list`, `thread/resume`. | Header from Dock row, actual events from detail endpoints. | Direct `ThreadDTO`/turn DTOs. | Header can be stale while detail body is current. |
| Thread Detail data engine | `ThreadDTO.turns`, notifications, server requests. | Turn ids/status/items, item content, deltas, request cards. | Raw `JSONValue` payloads. | Event/request shapes can drift outside generated card DTO. |
| Session Detail / composer | Detail snapshot, request cards, command client, voice state. | Event rows, draft, active turn id, request responses. | Live session state. | Detail state not pushed back to Dock card projection. |
| Server request cards | JSON-RPC server requests from active upstream session. | method, request id, thread id, turn id, item id, command/reason/cwd/permissions/questions. | Live server request side channel. | Payload drift breaks approvals/input independently of cards. |
| Command engine | Row ids plus turn/detail commands. | `threadID`, active turn id, draft text, request responses. | Direct `turn/*` and `thread/archive` endpoints. | Command target comes from projected row snapshot. |
| Legacy `thread/list` Swift wrapper | `ThreadListResponseDTO`. | `ThreadListParams`, `ThreadDTO` fields. | Direct list endpoint. | Still exposed, but not Dock UI source. |
| Connectivity store / diagnostics | `/statusz`, `/routesz`, traces. | Route health, app-critical failures, relay identity, configured host. | HTTP diagnostics. | Can say route is healthy while data is stale. |
| Sync/parity/state audits | `dock/*`, `relay/state/snapshot`, `thread/list`, `thread/search`, `thread/goal/get`, `thread/loaded/list`, SQLite. | Client-route proof plus oracle comparisons. | Oracle side doors. | Oracle truth can be newer than client stream without failing shape contract. |
| DEBUG/previews/tests | Scripted stream/detail fixtures. | Fake card and detail data. | Preview-only data. | Not production evidence. |

### Enforcement Inventory

| Artifact | What it guarantees | What it does not guarantee | Drift currently permitted |
| --- | --- | --- | --- |
| `package.json:6-10` | `npm test` runs `contract:check` before relay tests. | Swift tests are separate. | Relay contract can pass while Swift projection/detail behavior drifts. |
| `scripts/generate-dock-thread-card-contract.mjs:5-15` and `:509-515` | Generated Swift DTO must match generator output and schema version `2`. | Generator text is hand-authored; it is not a full schema-to-Swift compiler. | Schema intent can drift from generated code unless generator/checker changes too. |
| `scripts/check-dock-thread-card-contract.mjs:10-16` | Forbids legacy keys: `messageSummary`, `messageUpdatedAt`, `sessions`, `upsertSessions`, `deleteSessionIDs`. | Does not scan all docs or runtime payloads. | Stale docs can still mention dead contract names. |
| `scripts/check-dock-thread-card-contract.mjs:49-107` | Fixture cards must have core non-empty card strings and stream version/view/kind. | Not a full JSON Schema validator; does not validate semantic recency. | Extra invalid fields, enum drift, host/window drift, and stale source selection can slip. |
| Contract fixtures | One snapshot and one archive delta use current shape. | No broad fixture coverage for windows, leases, stale rows, multi-host, latest-turn recency. | Contract check can pass with no proof for the bug class in this audit. |
| Relay tests | Exercise cached subscribe, stale row retention, leases, window catch-up, route splits, human filtering, state snapshot, parity, sync audit, observability. | Do not require Dock cards to use `thread/turns/list` or live event timestamps. | Detail can be correct while Dock overview is stale. |
| Swift tests | Exercise stream decoding, table sequencing, stale heartbeat behavior, projection, local pins, thread detail loading, detail event order. | Do not make detail recency feed Dock card recency. | Swift can faithfully render stale relay card fields. |
| README/docs | Say the Dock app uses `dock/*`, raw `thread/list` is not the Dock list contract, and `/readyz` is process-only proof. | Docs do not enforce code. Some older docs still describe legacy names. | Humans can follow stale docs and reintroduce side-door assumptions. |

### Undocumented Contract Gaps

These are the places where the current data contract lets the system drift:

1. `activityAt` has no canonical source. It might come from `thread.activityAt`, `thread.updatedAt`, `thread.createdAt`, list ordinal, or a cached row. The schema only requires the field to exist.
2. `orderKey` has no semantic rule. Active Dock uses list ordinal order; Archive uses activity-derived order; the client may sort again by local activity date.
3. `displaySummary` has no freshness rule. It can be derived from thread-level metadata even when newer turn content exists.
4. `thread/turns/list` is the detail source for newest work, but the card stream contract does not require Dock cards to inspect it.
5. Live leases are status overlays only. They do not carry or repair `activityAt`, `orderKey`, `title`, `displaySummary`, repo, branch, or working directory.
6. `LiveStatusCache` and SQLite `live_leases` have separate lifecycles. Detail routing can disagree with Dock lease overlay.
7. Host freshness is scope-level. A host can be stale while rows remain visible, and a row can look fresh while its semantic source is stale.
8. Local pin metadata is a separate display cache. It can keep a pinned row visible with old title/status/activity when no current card exists.
9. `relay/state/snapshot`, `state/query`, `/statez`, `/syncz`, `/explainz`, and parity scripts are useful truth/oracle surfaces, but they are not the app card contract.
10. Route health is not row freshness. `/readyz`, `/statusz`, `/routesz`, and traces can be green while card ordering is wrong.
11. Thread Detail has its own raw event/request contract. Request cards and turn events can drift independently from `DockThreadCard`.
12. Contract checks protect only a small fixture set and generated Swift text. They do not run full JSON Schema validation against broad runtime examples.

## End-To-End Dock Data Flow

### 1. Relay route split

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay.mjs` | 459-490 | `handleRequest` sends `thread/list`, `thread/read`, `thread/turns/list`, `dock/subscribe`, and `dock/resync` to separate handlers. | Dock and thread detail are separate paths. |
| `scripts/dock-relay.mjs` | 475-478 | `dock/subscribe` and `dock/resync` use `RelayStateEngine`. | Dock reads cached relay state. |
| `scripts/dock-relay.mjs` | 487-490 | `thread/read` and `thread/turns/list` go through detail/raw thread handlers. | Turn data is not part of Dock card projection. |
| `scripts/dock-relay-observability-contract.mjs` | 273-296 | `dock/subscribe`, `dock/update`, and `dock/resync` are app-critical card summary routes. | Route health can be green even when card data is semantically stale. |
| `scripts/dock-relay-observability-contract.mjs` | 236-258 | `thread/read` and `thread/turns/list` are separate app-critical detail routes. | The route contract itself encodes the split. |

### 2. Subscribe returns cached state first

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay-state-engine.mjs` | 603-615 | `subscribeDock` calls `subscribeCardView` and schedules reconcile after the response. | The first screen can show old cached rows before a refresh. |
| `scripts/dock-relay-state-engine.mjs` | 631-675 | `subscribeCardView` returns the current snapshot and only then starts catch-up/reconcile work. | Subscribe is intentionally fast; not a fresh read guarantee. |
| `scripts/dock-relay-state-engine.mjs` | 226-234 | `shouldReconcileAfterResponse` skips reconcile when row count exists, no incomplete scopes exist, and freshness is `fresh`. | If stale semantic data is marked fresh, Dock will not self-correct. |
| `scripts/dock-relay-state-engine.mjs` | 742-839 | Window catch-up sends more cached cards when a snapshot is incomplete. | Catch-up completes the window, not the semantic recency check. |

### 3. Reconcile uses thread-level list/read, not turns

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay-state-engine.mjs` | 252-261 | Dock reconcile asks for active rows sorted by `updated_at desc`. | Sorting depends on thread-level `updatedAt`. |
| `scripts/dock-relay-state-engine.mjs` | 263-266 | Reconcile runs `refreshLiveLeases()` and `drainThreadListScope(...)` in parallel. | Lease refresh and list refresh are related but not one data source. |
| `scripts/dock-relay-state-engine.mjs` | 267-281 | Reconcile enriches list rows as human-started rows and session-index supplements. | Still thread rows only. |
| `scripts/dock-relay-state-engine.mjs` | 281-288 | Rows become cards through `orderedDockRows` and `normalizeThread`. | Card activity is finalized here without turns. |
| `scripts/dock-relay-thread-data.mjs` | 640-643 | Human-started enrichment defaults to `thread/read { includeTurns:false }`. | The validation/enrichment path explicitly excludes turns. |
| `scripts/dock-relay-thread-data.mjs` | 623-637 | `mergeAuthoritativeThreadRead` lets `thread/read` fields override list fields and deletes `turns`. | A stale `thread/read.updatedAt` can replace fresher list data, and turns are removed. |
| `scripts/dock-relay-thread-data.mjs` | 705-710 | Session-index supplements also validate with `thread/read includeTurns:false`. | Supplements can add missing rows but not turn-derived recency. |
| `scripts/dock-relay-thread-data.mjs` | 872-907 | `aggregateThreadList` returns enriched thread rows plus live overlay metadata. | Raw `thread/list` still does not become turn-aware. |
| `scripts/dock-relay-thread-data.mjs` | 976-985 | `listThreadTurns` exists, validates the human thread, and routes to owner/history. | It is used by detail, not by Dock reconcile. |

### 4. Card projection chooses thread timestamps

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay-thread-data.mjs` | 192-205 | Thread preference compares status priority, then `updatedAt ?? createdAt`. | Turn timestamps are ignored when choosing between candidate rows. |
| `scripts/dock-relay-state-views.mjs` | 182-185 | `dockOrderKey` is based on list ordinal plus thread id. | Active Dock order is not activity-time-derived. |
| `scripts/dock-relay-state-views.mjs` | 269-279 | `overlayLiveStatus` copies live `status` and `sessionId` only. | It does not copy activity time, summary, title, repo, or branch. |
| `scripts/dock-relay-state-views.mjs` | 281-310 | `orderedDockRows` overlays live rows onto existing rows but does not add live-only rows. | A live thread absent from list/supplements can stay absent from Dock cards. |
| `scripts/dock-relay-state-views.mjs` | 312-349 | `normalizeThread` sets `activityAtMs` from `thread.activityAt` else `rowTimestamp(thread)`. | `rowTimestamp` is still `updatedAt ?? createdAt`; no `thread/turns/list`. |
| `scripts/dock-relay-state-views.mjs` | 333-344 | The final card carries `activityAt`, `activityAtMs`, `freshness`, and `completeness`. | These fields look canonical to Swift even when derived from stale thread metadata. |
| `scripts/dock-relay-state-views.mjs` | 352-381 | Stored cards are reconstructed from SQLite. | Cached stale activity can keep flowing forward. |
| `scripts/dock-relay-state-views.mjs` | 384-399 | Lease overlay on stored cards changes `backendSessionID` and status only. | Leases do not repair stale activity/order/summary. |

### 5. SQLite persists the projected card, not the raw truth

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay-state-store.mjs` | 130-154 | `threads` stores `order_key`, `activity_at`, `activity_at_ms`, `display_summary`, `status`, `updated_at_ms`, `freshness_status`, and `raw_json`. | Persisted state stores projected card values. |
| `scripts/dock-relay-state-store.mjs` | 159-167 | `thread_field_provenance` exists as a table. | It is not used by Dock card ordering or recency. |
| `scripts/dock-relay-state-store.mjs` | 169-179 | `sync_scopes` stores complete/incomplete sync status. | Freshness is scope-level, not proof of latest turn activity. |
| `scripts/dock-relay-state-store.mjs` | 182-190 | `live_leases` stores endpoint, backend session, status, waiting state, capability. | No activity fields exist in the lease table. |
| `scripts/dock-relay-state-store.mjs` | 394-430 | `listDockCards` orders by `t.order_key ASC`, then applies lease status. | Store read order follows projected list ordinal, not latest real activity. |
| `scripts/dock-relay-state-store.mjs` | 570-599 | `applyDockReconciliation` compares projected cards and publishes upserts. | It publishes projected changes only. |
| `scripts/dock-relay-state-store.mjs` | 601-608 | Missing rows are deleted only when reconciliation is complete. | Incomplete refresh intentionally keeps stale rows visible. |
| `scripts/dock-relay-state-store.mjs` | 703-779 | `upsertThreadCard` writes `updated_at_ms = card.activityAtMs` and `freshness_status = card.freshness || "fresh"`. | The DB has no independent raw `thread.updatedAt` or latest-turn timestamp. |
| `scripts/dock-relay-state-store.mjs` | 885-916 | `upsertLiveLease` writes lease status/session/expiry. | Lease state is a status overlay, not a card-data repair. |
| `scripts/dock-relay-state-store.mjs` | 946-975 | `recordSyncScope` updates `last_attempt_at`, `last_sync_at`, and `last_error`. | A complete scope can still be semantically stale if thread metadata was stale. |
| `scripts/dock-relay-state-store.mjs` | 978-999 | `markScopeStale` marks a scope stale and records a change, without clearing cards. | Stale cached rows stay on screen by design. |

### 6. Freshness is host/global, not a guarantee per card

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay-state-store.mjs` | 369-392 | `freshnessForHost` returns `stale` if any sync scope for that host has `complete = 0`. | One failed scope can make the host stale; no row-level proof. |
| `scripts/dock-relay-state-engine.mjs` | 308-323 | Reconcile publishes `freshness` from `freshnessForHost`. | A card can remain stale while the host says fresh, or vice versa. |
| `scripts/dock-relay-state-engine.mjs` | 483-549 | Dock snapshots include store cards plus host freshness. | Snapshot `complete` means window coverage, not turn inspection. |
| `scripts/dock-relay-state-engine.mjs` | 552-572 | Archive snapshots use the same host freshness source. | Archive failures can affect host-level health language even when Dock rows are present. |

### 7. Live leases are a separate clock

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay-thread-data.mjs` | 51-59 | `LiveStatusCache` collects live rows with `includeHistory:false`. | Detail routing and Dock lease refresh do not share the exact same source set. |
| `scripts/dock-relay-state-engine.mjs` | 441-468 | `refreshLiveLeases` collects live rows with `includeHistory:true` and writes `live_leases`. | The lease table can differ from detail routing cache. |
| `scripts/dock-relay-live-status-cache.mjs` | 12-46 | Live overlay can be `ready`, `degraded`, `stale`, `unavailable`, or `disabled`. | This overlay is separate from Dock stream freshness. |
| `scripts/dock-relay-live-status-cache.mjs` | 94-143 | Cache refresh records live rows and failures on its own timer. | It is not automatically synchronized with every Dock reconcile. |
| `scripts/dock-relay-live-status-cache.mjs` | 178-186 | Detail route selection uses cache row lookup and falls back to history. | Detail can route history while Dock lease still says live, or the reverse. |
| `scripts/dock-relay-state-views.mjs` | 384-399 | Expired lease only downgrades `dormant` to `unknown`; otherwise stored status remains. | A stored `running` status can outlive its lease until history rewrites it. |
| `scripts/dock-relay-state-ingest.mjs` | 14-41 | Notification ingestor handles archive mutations and live-disconnect stale marking. | There is no live turn-event ingestor that bumps card recency. |

Net: leases were never unified with the card contract. They are an overlay with their own expiry, not the source of card activity truth.

## Swift Client Touchpoints

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `CodexDock/AppServer/DockThreadCardDTO.swift` | 342-365 | Swift card DTO contains `orderKey`, `activityAt`, `activityAtMs`, title, summary, status, freshness, completeness. | Swift trusts relay values. |
| `CodexDock/State/ThreadCardTable.swift` | 82-112 | Snapshot application replaces cards with stream cards after schema/window validation. | Validation checks shape and stream continuity, not semantic recency. |
| `CodexDock/State/ThreadCardTable.swift` | 115-168 | Delta application upserts/deletes cards and enforces sequence/epoch rules. | Again, no turn-derived repair. |
| `CodexDock/State/ThreadCardTable.swift` | 321-350 | Host status maps stale/offline/error with retained rows to `.partial`. | User can see rows while data is stale by design. |
| `CodexDock/State/ThreadCardRowProjector.swift` | 27-58 | `DockThreadCardDTO` becomes `DockRowViewModel`. | Row model gets whatever activity the relay sent. |
| `CodexDock/State/ThreadCardRowProjector.swift` | 118-130 | Row activity uses `activityAtMs` first, then parses `activityAt`. | No fallback to `thread/turns/list` exists on the overview. |
| `CodexDock/State/ThreadCardRowProjector.swift` | 15-24 and 61-89 | Pinned cached rows can be rendered from local metadata. | A pinned row can remain visible without current relay card data. |
| `CodexDock/State/ThreadDetailStore.swift` | 563-574 | Thread detail explicitly calls `thread/read includeTurns:false`, then drains all turns. | Detail can be current while Dock overview stays stale. |

## Connectivity And Route Health Touchpoints

Line audit:

| File | Lines | Behavior | Drift point |
| --- | ---: | --- | --- |
| `scripts/dock-relay.mjs` | 848-855 | `/readyz` returns process-level OK. | It does not check raw app-server or Dock freshness. |
| `scripts/dock-relay.mjs` | 763-767 | `/statusz` runs raw app-server health then returns status snapshot. | Top-level status response can be OK while routes/state have failures. |
| `scripts/dock-relay.mjs` | 783-794 | `/routesz` returns route health evidence. | Route health is not the same as data freshness. |
| `scripts/dock-relay-status.mjs` | 205-260 | Status snapshot includes `appCriticalFailures`, route list, live status, state, and errors. | Callers must inspect nested fields; `ok:true` alone is not enough. |
| `scripts/dock-relay-observability.mjs` | 291-355 | Route operations start as partial. | A running request can look partial independent of Dock data quality. |
| `scripts/dock-relay-observability.mjs` | 358-375 | Route operations finish from request success/failure. | A successful stale payload can still mark route success. |
| `scripts/dock-relay-observability.mjs` | 514-516 | `appCriticalFailures` only includes routes with `routeStatus == failed`. | Stale/incomplete data may not become an app-critical failure. |

## Drift Inventory

| Drift point | Root cause | User-visible result |
| --- | --- | --- |
| Current turn activity not on top | Dock never reads `thread/turns/list` during card reconcile. | A thread with active recent work appears old. |
| Old card summary/title | Summary comes from thread row fields, not latest turn content. | Card text can lag behind current conversation. |
| `orderKey` vs activity | Active Dock `orderKey` is list ordinal. | Store ordering can preserve stale list order. |
| `activityAtMs` vs turn timestamps | `activityAtMs` is projected from `activityAt` or thread `updatedAt/createdAt`. | Client cannot sort by real newest work if relay timestamp is stale. |
| Lease status vs card data | Leases update status/session only. | A live-looking card can still have old title/activity. |
| Expired lease edge | Expired lease only downgrades dormant cards. | A stored `running` status can survive lease expiry. |
| Live detail route vs Dock lease route | `LiveStatusCache` and `refreshLiveLeases` use different timing/source sets. | Detail and Dock can disagree about what is live. |
| Host freshness vs row freshness | `freshnessForHost` is scope-based; rows are retained. | UI can show data while also saying partial/stale. |
| Route health vs data freshness | Route observability measures request outcome, not payload semantic age. | `/readyz` or route health can look OK while Dock data is stale. |
| Generated schema confidence | Schema validates shape, not source semantics. | `contract:check` can pass while user-facing ordering is wrong. |

## Tests That Encode Current Behavior

These tests are useful guardrails, but several of them encode the behavior that makes the current bug possible:

- `scripts/dock-relay.test.mjs:206` - stale scope keeps existing rows visible.
- `scripts/dock-relay.test.mjs:243` - live lease publishes status-only card changes.
- `scripts/dock-relay.test.mjs:292` - expired lease behavior is tested for the dormant case.
- `scripts/dock-relay.test.mjs:628` - fresh cached `dock/subscribe` can skip refresh.
- `scripts/dock-relay.test.mjs:1280` - Dock card activity comes from thread fields.
- `scripts/dock-relay-observability.test.mjs:190` - `/readyz` can pass while Dock state freshness is stale.
- `scripts/dock-relay-observability.test.mjs:238` - `dock/subscribe` route health can be healthy while serving stale cached state.
- `CodexDockTests/DockStoreStreamTests.swift:219` - stale heartbeat retains rows as partial.
- `CodexDockTests/ThreadDetailStoreTests.swift:5` and related tests - detail store relies on `thread/turns/list`, which is separate from Dock cards.
- `CodexDockTests/DockRenderProjectorTests.swift:44` - cached pinned rows can render without live cards.

## What Would Make Drift Actually Hard

This is not an implementation plan, just the architectural conclusion from the audit.

The contract would need to define a canonical activity source, not just fields:

1. Dock card recency must mean "latest user-visible thread activity", with a precise priority order such as latest turn timestamp, then live event timestamp, then thread `updatedAt`, then `createdAt`.
2. Relay state must persist that canonical activity timestamp separately from list ordinal and raw `updatedAt`.
3. `orderKey` must be derived from canonical activity, or the client must ignore relay order for global recency.
4. Live leases must either remain a status-only overlay by contract, or explicitly carry activity/summary fields and a freshness source.
5. Route health must not be presented as data freshness. `/readyz` remains process proof only.
6. The generated schema should be extended only if the semantic source can be enforced or tested; otherwise it will keep giving false confidence.

## Verdict

The relay/client contract is not "impossible to drift." It is shape-safe but source-unsafe.

The current user-facing bug is not primarily a Swift display bug. Swift is faithfully displaying stale card fields. The deeper bug is in the relay Dock projection: it treats thread-level rows as canonical for overview recency while the real current work can exist only in turn-level data.
