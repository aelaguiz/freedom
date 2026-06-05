---
title: "Codex Dock - App-Server Registry Hard Cut - Architecture Plan"
date: 2026-06-05
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [composer-2.5-fast, gpt-55x-high, thermo-nuclear-code-quality-review]
doc_type: phased_refactor
related:
  - docs/CODEX_DOCK_APP_SERVER_RELATIONSHIP_AND_AGGREGATION_ARCHITECTURE_2026-06-05.md
---

# TL;DR

Outcome: Dock relay `:4510` becomes the only normal Dock service and owns a
relay-local AppServerRegistry that aggregates every addressable Codex
app-server instance it can connect to. The normal Dock path no longer starts,
authenticates to, or depends on a Dock-owned raw `ws://127.0.0.1:4500`
app-server.

Problem: Codex app-server live state is process-local. Dock's current private
`:4500` app-server can read shared history from `~/.codex`, but it cannot see
live turns owned by Codex.app, VS Code, CLI, or other app-server runtimes.

Approach: hard cut to a single relay-owned registry, add the missing upstream
transport/discovery pieces, route history/control/live through that registry,
and delete the old raw-app-server service path and tests that require it.

Plan: first prove the highest-risk seam with registry-owned history plus one
discovered live owner, then widen to multi-endpoint discovery, routing,
performance, Swift-visible degradation, service deletion, real-machine proof,
review, commit, push, and local/home deployment.

Non-negotiables: no hidden `:4500` fallback, no second normal path, no raw
Codex bearer token or `OPENAI_API_KEY` on the phone, no request-path process
scan, no claim that private `stdio://` or in-process runtimes are visible until
Codex exposes an attachable surface.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-06-05
external_research_grounding: not started
deep_dive_pass_2: done 2026-06-05
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:d75c30665b0e1447f5192031b1e0396d699efdd02af1318a33bd10e1a152034c",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-05T01:11:24Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:c206834ce214e0c1c55269e2ecfb0acb814032ff2100baaea528d0c719d93c1a",
      "completed_at": "2026-06-05T01:12:13Z",
      "doc_hash_after": "sha256:8daa47432b56d3bab1e29838869b050fbc21af56cc8f6823ab94f9f4f61bd508"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-05T01:12:16Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:8daa47432b56d3bab1e29838869b050fbc21af56cc8f6823ab94f9f4f61bd508",
      "completed_at": "2026-06-05T01:13:13Z",
      "doc_hash_after": "sha256:00cf00f08a3c1af5939785020cdd6d06c34c50ae70371c0b91c909329c0aa446"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-05T01:13:17Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:00cf00f08a3c1af5939785020cdd6d06c34c50ae70371c0b91c909329c0aa446",
      "completed_at": "2026-06-05T01:13:42Z",
      "doc_hash_after": "sha256:dcc0cd070efe89849bb8711b398e5c62c31a2df5d6ec249dd2566c6fc846bc49"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-05T01:13:47Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:dcc0cd070efe89849bb8711b398e5c62c31a2df5d6ec249dd2566c6fc846bc49",
      "completed_at": "2026-06-05T01:14:41Z",
      "doc_hash_after": "sha256:463d8ce285c7713f117860b922c36e41775638208ecf35fe4f6111cee70e9e70"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-05T01:15:03Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:463d8ce285c7713f117860b922c36e41775638208ecf35fe4f6111cee70e9e70",
      "completed_at": "2026-06-05T01:22:20Z",
      "doc_hash_after": "sha256:33472727ce1c5e19da936a87ebd96445708f21a084485081252376327222ee27"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this change, `rtk make services` on Mac and home starts only the Dock
relay as Dock-owned service infrastructure. The relay discovers and queries all
addressable Codex app-server endpoints on that host, uses a non-Dock-owned
history endpoint, routes live/control operations through registry-owned leases,
and makes private/unattachable runtimes visible as diagnostics rather than
false live status.

The claim is false if any normal host-service render still starts
`codex app-server --listen ws://127.0.0.1:4500`, if the relay still treats a
single configured `historyUrl` as the whole Codex world, if live badges come
from only Dock's private app-server, or if request handlers run process
discovery directly.

## 0.2 In scope

- Replace Dock's single `historyUrl`/manual `liveEndpoints` model with one
  relay-owned AppServerRegistry.
- Add upstream transport support for the selected non-Dock history path. The
  preferred target is Codex daemon `unix://` app-server transport, implemented
  directly or through a proven Codex proxy path.
- Discover local addressable `codex app-server --listen ws://127.0.0.1:<port>`
  endpoints and classify them by reachability, auth, transport, `codexHome`,
  user agent, and health.
- Query only addressable live endpoints for `thread/loaded/list` and
  `thread/read includeTurns:false`, then merge live rows with bounded fanout.
- Route thread control to the owner endpoint when a live lease exists and to
  the history endpoint only when that is the correct non-live operation.
- Delete the normal Dock-owned raw app-server service, token dependency,
  service dependency, Makefile defaults, docs, and tests that require the
  legacy path.
- Preserve the phone-facing Dock relay contract on `:4510`, including the
  saved per-device host list shape.
- Keep realtime transcription and phone authentication behavior relay-side.
- Produce local and home runtime proof that the relay sees and queries all
  addressable app-server instances on each machine.

## 0.3 Out of scope

- Making Dock attach to private `stdio://` pipes owned by another parent
  process.
- Making Dock see Codex in-process runtimes that expose no transport.
- Changing upstream Codex.app, VS Code, CLI, or daemon behavior in the Codex
  repo.
- Adding phone-side raw app-server configuration or direct phone-to-`:4500`
  connection.
- Preserving a compatibility mode where Dock secretly starts a raw
  `ws://127.0.0.1:4500` app-server for normal use.
- Introducing a new product mode, parallel relay protocol, or second state
  store to work around the existing `dock/*` projection contract.

## 0.4 Definition of done (acceptance evidence)

- `rtk npm run test:relay` passes with registry/discovery/history/live-routing
  tests, including bounded multi-endpoint behavior.
- `rtk npm run test:host-service` passes and proves host-service rendering no
  longer emits a raw app-server service or raw app-server token dependency.
- The smallest relevant Swift check passes if the app-facing degradation or DTO
  contract changes; otherwise relay-only proof is enough for pure relay work.
- `rtk make services`, `rtk make app-server-status`, and
  `rtk make dock-relay-status` show the new relay path on the Mac.
- Runtime proof on Mac prints attachable endpoint counts, unreachable private
  runtime counts, selected history endpoint, and queried live endpoint list.
- Runtime proof includes a real or fixture-backed discovered non-Dock app-server
  live owner with a visible running badge in simulator.
- Home checkout at `/home/aelaguiz/workspace/codex-client` is updated from the
  pushed branch and the home relay is restarted on the new code.
- Thermonuclear review has no blocking findings before commit/push/deploy.

## 0.5 Key invariants (fix immediately if violated)

- The phone talks only to Dock relay `:4510`.
- `OPENAI_API_KEY`, raw Codex bearer tokens, and raw app-server credentials stay
  Mac-side.
- Normal Dock services do not start Dock's private raw `:4500` app-server.
- There is one relay-side source of truth for upstream app-server discovery and
  owner leases: AppServerRegistry.
- Process discovery runs on a timer or explicit diagnostics path, never per row
  or per request handler.
- Registry failure is fail-loud in status and Swift-visible connectivity state.
- Private `stdio://` and in-process runtimes are diagnostics, not fake live
  owners.
- Git is the archive for removed legacy paths; no retired service path remains
  live for archaeology.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Correct live truth: Dock must stop asking one process for machine-wide live
   status.
2. Hard cut: delete the normal raw `:4500` path rather than preserving it as a
   fallback.
3. Performance at thousands of persisted threads: no request-path discovery,
   no unbounded fanout, and no full-history reread for live badges.
4. Security boundary: relay owns raw Codex auth; the phone sees only Dock relay.
5. Honest observability: surface addressable, unreachable, and failed upstreams
   separately.
6. Minimal product surface: reuse `dock/*`, `LiveStatusCache`,
   `SessionRouter`, and existing host/device config patterns.

## 1.2 Constraints

- Codex app-server WebSocket transport is documented as experimental.
- Codex default `stdio://` app-server children are private to their parent UI.
- Codex daemon Unix transport is valid Codex-side and requires Dock's upstream
  WebSocket client to disable `perMessageDeflate`; the real daemon control
  socket closes the handshake when Node advertises compression.
- Codex server clamps `thread/list` pages to 100 even though Dock constants use
  `THREAD_LIST_MAX_LIMIT = 250`.
- Current relay state and projection paths already carry host identity, source
  host identity, freshness, and error states; new work should reuse them.
- Mac and home have different filesystem roots and service managers, so the
  hard cut must preserve Makefile-owned deployment.

## 1.3 Architectural principles (rules we will enforce)

- One registry owns upstream discovery, endpoint health, history selection,
  live owner leases, and diagnostics.
- Existing relay data paths call registry APIs; they do not scan processes or
  parse command lines themselves.
- History is a registry-selected endpoint, not a hard-coded `historyUrl`.
- Live rows come only from loaded-thread queries on addressable endpoints.
- Control routing uses owner leases first, with explicit method-level fallback
  rules.
- Fail-loud beats silent fallback whenever the selected history path is missing.
- Constants for intervals, caps, pool sizes, and timeouts stay in
  `scripts/dock-relay-constants.mjs`.

## 1.4 Known tradeoffs (explicit)

- This fixes live truth for attachable endpoints now. It does not create
  magical access to private `stdio://` or in-process runtimes.
- Relying on discovered `ws://` app-server endpoints is best-effort because
  Codex marks that transport experimental.
- Requiring daemon history is cleaner than starting Dock's own history server,
  but it adds relay transport work and a fail-loud daemon availability contract.
- Deleting the raw app-server service will break tests that assumed `:4500`;
  those tests must be rewritten around relay-owned registry fixtures or deleted
  when they only prove legacy behavior.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

`rtk make services` renders a host-service bundle that starts two Dock-owned
processes: a raw Codex app-server on `ws://127.0.0.1:4500` and Dock relay on
`:4510`. The relay receives `--history-url` pointing at `:4500` and a
`--history-auth-token-file` for the raw app-server token. Optional live
endpoints are manual env/config values, not automatic discovery.

## 2.2 What's broken / missing (concrete)

The raw `:4500` app-server can read persisted Codex history from `~/.codex`,
but Codex live status is process-local. If the active turn is in Codex.app,
VS Code, CLI, or another app-server runtime, the Dock-owned `:4500` process
reports that thread as `notLoaded`. That produces the same wrong badge on the
phone even when the relay and phone connection are healthy.

## 2.3 Constraints implied by the problem

- The fix must move live status collection from "one history app-server" to
  "all addressable live app-server owners."
- The fix must not keep a compatibility fallback that preserves the same wrong
  mental model.
- The relay must distinguish "not loaded in this endpoint" from "loaded in a
  different endpoint" and from "live owner is private/unattachable."
- Performance must be designed around thousands of persisted threads and many
  short-lived app-server endpoints.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- No paper or web prior art is needed for the core decision. Codex source,
  Dock source, the local `ws` client implementation, and the runtime process
  probe are the authoritative anchors.
- `node_modules/ws/lib/websocket.js:714` through
  `node_modules/ws/lib/websocket.js:732` accept `ws+unix:` as an IPC
  WebSocket URL scheme, and `node_modules/ws/lib/websocket.js:807` through
  `node_modules/ws/lib/websocket.js:811` map that URL to `socketPath` plus
  request path. Adopt this for native relay upstream Unix transport instead of
  making a long-lived Codex proxy subprocess the normal path.

## 3.2 Internal ground truth (code as spec)

Authoritative behavior anchors:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md` defines
  app-server as the JSON-RPC API for rich clients. Its default transport is
  `stdio://`; `ws://IP:PORT` is experimental; `unix://` uses
  `$CODEX_HOME/app-server-control/app-server-control.sock`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/message_processor.rs`
  constructs a process-scoped `ThreadManager`.
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs`
  stores loaded threads in one in-memory `HashMap<ThreadId, Arc<CodexThread>>`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs`
  implements `thread/loaded/list` by reading that local `ThreadManager`.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs`
  derives `active`, `idle`, and `notLoaded` from process-local runtime facts.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/in_process.rs`
  proves some app-server use has no external transport to attach to.
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-daemon/README.md`
  marks the daemon path as experimental, so Dock must fail loud and observe it
  carefully instead of hiding assumptions.

Canonical path / owner to reuse:

- `scripts/dock-relay-thread-data.mjs` owns history reads, live row collection,
  and route helpers today. It should call registry-owned history/live APIs
  instead of owning a hard-coded single `historyUrl`.
- `scripts/dock-relay-live-status-cache.mjs` owns cached live rows and
  `SessionRouter`. Keep that ownership, but feed it from AppServerRegistry.
- `scripts/dock-relay-state-engine.mjs` owns relay state refresh and
  subscription snapshots. It should refresh leases from registry endpoints, not
  manually configured endpoints plus history fallback.
- `scripts/dock-relay-json-rpc-client.mjs` owns upstream JSON-RPC transport. It
  should become transport-neutral enough for `ws://`, `wss://`, and
  `unix://` app-server endpoints.
- `scripts/codex-dock-host-service.mjs` and `Makefile` own host service
  lifecycle. They must delete normal raw-app-server service rendering.

Adjacent surfaces tied to the same contract family:

- `scripts/codex-dock-host-service.test.mjs` has tests asserting raw
  app-server service rendering, token files, and start/stop ordering. Rewrite
  tests that cover current behavior; delete tests whose only purpose is proving
  legacy `:4500`.
- `scripts/dock-relay-card-contract.test.mjs`,
  `scripts/dock-relay-thread-recovery.test.mjs`,
  `scripts/dock-relay-user-message-command.test.mjs`,
  `scripts/dock-relay-observability.test.mjs`, and controlled simulator
  fixtures currently construct relay config with one `historyUrl`. Move those
  fixtures to registry-selected history endpoints.
- `README.md` and `AGENTS.md` service-path descriptions currently name raw
  `:4500` as canonical. Update touched live docs after the implementation.
- Swift saved app config already stores only relay hosts on `:4510`. Preserve
  that contract; do not add raw upstream endpoint config to Swift.

Compatibility posture (separate from `fallback_policy`):

- Clean cutover. The normal Dock service contract breaks from "relay plus
  Dock-owned raw app-server" to "relay only, with registry-owned upstreams."
  No runtime shim or hidden fallback is approved.

Existing patterns to reuse:

- `collectLiveRows` already performs bounded multi-endpoint loaded-row
  collection; reuse and move endpoint ownership behind registry.
- `LiveStatusCache` already caches live snapshots on a refresh interval.
- `SessionRouter` already maps thread IDs to live endpoints and falls back to a
  configured endpoint when appropriate; keep the shape but make registry own the
  fallback decision.
- Relay status and logs already use structured status payloads and
  `dock-relay-logger.mjs`; preserve secret hygiene.

Duplicate or drifting paths relevant to this change:

- `Makefile` variables `APP_SERVER_PORT`, `APP_SERVER_LISTEN`,
  `APP_SERVER_WS`, and `DOCK_RELAY_HISTORY_WS` encode the old normal path.
- `scripts/codex-dock-host-service.mjs` renders the raw app-server service and
  token dependency.
- `scripts/dock-relay.mjs` still requires `--history-auth-token-file` and
  defaults history to `DEFAULT_HISTORY_APP_SERVER_WS`.
- Manual live endpoint env vars are useful fixtures but must not remain the
  production discovery model.

Behavior-preservation signals already available:

- `rtk npm run test:relay` covers relay card contracts, state, subscriptions,
  projection, recovery, user commands, realtime transcription, simulator sync,
  and live filter behavior.
- `rtk npm run test:host-service` covers service rendering and device relay
  config.
- `rtk swift test --filter DockStoreTests` covers Swift host/stream state if
  the app-facing DTO or degradation shape changes.

## 3.3 Decision gaps that must be resolved before implementation

- none. The plan chooses native relay `unix://` upstream support by adapting it
  to the local `ws` package's `ws+unix:` client capability. If that proves false
  during implementation, the plan must be repaired before using a proxy path.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `Makefile` declares raw app-server defaults at the top:
  `APP_SERVER_PORT ?= 4500`, `APP_SERVER_LISTEN ?= ws://127.0.0.1:4500`,
  `APP_SERVER_WS ?= ws://127.0.0.1:4500`, app-server token/log/pid paths, and
  `DOCK_RELAY_HISTORY_WS ?= ws://127.0.0.1:4500`.
- `Makefile` builds `HOST_SERVICE_ARGS` with `--raw-app-server-listen`,
  `--relay-history-url`, `--raw-token-file`, app-server labels, and relay
  labels.
- `scripts/codex-dock-host-service.mjs` renders both `raw-app-server` and
  `dock-relay` service files, creates/reuses an app-server token, and starts or
  stops both services in dependency order.
- `scripts/dock-relay.mjs` parses one `historyUrl`, one history auth token file,
  and optional manual `liveEndpoints`.
- `scripts/dock-relay-thread-data.mjs` owns `historyClientForConfig(config)`,
  `configuredLiveEndpointsForConfig(config)`, `collectLiveRows`, `thread/list`,
  `thread/read`, `thread/turns/list`, archive, rename, and unarchive calls.
- `scripts/dock-relay-live-status-cache.mjs` owns cached live rows and
  `SessionRouter`.
- `scripts/dock-relay-state-engine.mjs` refreshes live leases by calling
  `configuredLiveEndpointsForConfig(config, { includeHistory: true })`.
- `scripts/dock-relay-json-rpc-client.mjs` owns upstream JSON-RPC over
  WebSocket URL strings.

## 4.2 Control paths (runtime)

Current normal path:

```text
iPhone / simulator
  -> ws://<host>:4510
  -> dock-relay.mjs
     -> historyUrl ws://127.0.0.1:4500
     -> Dock-owned codex app-server --listen ws://127.0.0.1:4500
     -> ~/.codex history
```

Current optional live path:

```text
dock-relay.mjs
  -> CODEX_DOCK_LIVE_APP_SERVER_WS / CODEX_DOCK_LIVE_ENDPOINTS
  -> collectLiveRows()
  -> thread/loaded/list and thread/read includeTurns:false
```

This optional path is not automatic discovery. If no manual env endpoint is
configured, live status is still effectively the raw `:4500` history process.

## 4.3 Object model + key abstractions

- `config.historyUrl` is treated as the primary app-server endpoint.
- `config.liveEndpoints` is an array of optional manual endpoint descriptors.
- `historyClientForConfig(config)` memoizes a single JSON-RPC client for
  history operations.
- `configuredLiveEndpointsForConfig(config, { includeHistory })` builds the
  live endpoint list from the optional manual live endpoints and, sometimes,
  the history endpoint.
- `LiveStatusCache` stores rows returned by `collectLiveRows`.
- `SessionRouter` maps thread IDs to live endpoints using cached rows and falls
  back to `historyEndpoint` when no live lease exists.

## 4.4 Observability + failure behavior today

- Status can report whether history is configured, but it does not report a
  complete registry view of addressable, unreachable, private, or failed Codex
  runtimes.
- Raw app-server token files and service logs exist as normal-path artifacts.
- If the raw history app-server is healthy but another runtime owns the live
  turn, the system fails silently at the product level: the badge is wrong, not
  clearly degraded.
- Private `stdio://` and in-process runtimes are not represented in relay
  status today.

## 4.5 UI surfaces (ASCII mockups, if UI work)

No new primary UI surface is planned. Existing host group unavailable/degraded
states should show relay registry degradation through current Swift
connectivity mechanisms:

```text
Amir-M5.local:4510
  degraded: History daemon unavailable
  rows retained from last good snapshot when possible
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- New relay module: `scripts/dock-relay-app-server-registry.mjs`.
- Updated upstream client: `scripts/dock-relay-json-rpc-client.mjs` supports
  `ws://`, `wss://`, and Codex `unix://` app-server endpoints by adapting
  `unix://<path>` to `ws+unix:<path>:/`.
- Updated relay data path: `scripts/dock-relay-thread-data.mjs` depends on
  registry APIs for history, live endpoints, and routing.
- Updated state path: `scripts/dock-relay-state-engine.mjs` refreshes live
  leases from registry snapshots.
- Updated host-service path: `scripts/codex-dock-host-service.mjs` renders only
  the Dock relay normal service.
- Updated Makefile: remove normal raw app-server startup variables and pass
  registry/daemon settings instead of `--relay-history-url` and
  `--raw-token-file`.

## 5.2 Control paths (future)

Normal service path:

```text
iPhone / simulator
  -> ws://<host>:4510
  -> Dock relay
     -> AppServerRegistry
        -> history endpoint: unix://$CODEX_HOME/app-server-control/app-server-control.sock
        -> live endpoints: discovered ws://127.0.0.1:<port> codex app-server processes
        -> unreachable observed: stdio:// and in-process/private runtimes
     -> dock/* snapshots, deltas, details, control, voice
```

History path:

```text
dock/* history operation
  -> registry.historyClient()
  -> selected non-Dock endpoint
  -> thread/list, thread/read, thread/turns/list, archive, rename, unarchive
```

Live path:

```text
registry refresh timer
  -> discover addressable endpoints
  -> initialize healthy upstream clients
  -> thread/loaded/list
  -> bounded thread/read includeTurns:false for loaded IDs only
  -> LiveStatusCache + threadOwnerById leases
```

Control path:

```text
thread method with a live owner lease
  -> owner endpoint

thread method without a live owner lease and safe history behavior
  -> history endpoint

thread method whose owner is known private/unreachable
  -> fail loud with "live owner is not attachable"
```

Method routing policy:

| Relay method / path | Registry route | History fallback | Private/unreachable owner behavior |
|---|---|---|---|
| `thread/list`, `dock/subscribe`, `dock/resync`, `archive/subscribe`, `archive/resync` | cached registry/live overlay plus history state/projection | allowed for history reads | show degraded/private diagnostic only |
| `thread/read includeTurns:false` | live row when lease exists, else history | allowed | return history row plus diagnostic if available |
| `thread/read includeTurns:true` | owner endpoint when live lease exists | allowed only when no live/private owner is known | fail loud if known private live owner |
| `thread/turns/list` | owner endpoint when live lease exists | allowed only when no live/private owner is known | fail loud if known private live owner |
| `thread/message/send`, `turn/start`, `turn/steer` | active session first, then registry owner route | allowed only to start/resume from valid history endpoint when no live owner lease/private owner exists | fail loud because sending to history can fork or miss the active turn |
| `turn/interrupt` | active session only | not allowed | fail loud because interrupting history endpoint is meaningless |
| raw JSON-RPC server-request / request-card response | active session upstream `sendRaw` only | not allowed | fail loud because approval responses belong to the session that emitted the request |
| `thread/archive`, `thread/name/set` | owner endpoint when live lease exists, else history | allowed | fail loud or require retry after owner becomes attachable |
| `thread/unarchive` | history endpoint | allowed | unaffected by live private owner |
| `thread/detail/subscribe`, `thread/detail/resync` | cached registry route plus active session route | allowed for history-backed detail only when no live/private owner is known | fail loud/degraded detail state if known private live owner |
| `projection/witness/read` | relay state/projection store | not an app-server route | unaffected |
| `audio/transcription/*` | relay realtime transcription service | not an app-server route | unaffected |

## 5.3 Object model + abstractions (future)

`AppServerRegistry` owns:

- discovery inputs: process scan, daemon Unix socket path, explicit test
  fixture endpoints, and future Codex registry output if it exists.
- endpoint records: `id`, `label`, `transport`, `url`, `socketPath`,
  `authSource`, `codexHome`, `pid`, `ppid`, `command`, `userAgent`,
  `discoveredAt`, `lastSeenAt`, `lastOkAt`, `failure`.
- history endpoint selection: one non-Dock app-server endpoint that can satisfy
  history/control reads.
- live endpoint list: all addressable endpoints that passed initialize.
- unreachable observed list: private `stdio://`, in-process/private evidence,
  unsupported auth, incompatible command, and failed connect attempts.
- `threadOwnerById`: live lease map from thread ID to endpoint.
- cached diagnostics for `/statusz` and host-service status.

Registry API shape:

```text
await registry.start()
await registry.stop()
await registry.refreshNow(reason)
registry.snapshot()
registry.historyEndpoint()
registry.historyClient()
registry.liveEndpoints()
registry.ownerForThread(threadID)
registry.routeForThreadMethod(method, threadID, options)
registry.recordLiveRows(endpoint, rows)
```

## 5.4 Invariants and boundaries

- AppServerRegistry is the only source of upstream endpoint truth.
- Registry refresh is timer/diagnostic driven, not request driven.
- Request handlers consume registry snapshots and clients; they do not scan
  processes.
- History endpoint absence is an error state, not permission to spawn `:4500`.
- Manual endpoint config may exist only as test/diagnostic override and must be
  labeled as such in code and tests.
- `stdio://` and in-process runtimes never become live owners unless Codex
  gives Dock an attachable endpoint.
- Duplicate rows for the same thread ID are merged by explicit status priority
  and recency rules, preserving current `preferThread` intent.
- All production intervals, page limits, concurrency caps, pool caps, and
  timeout values remain in `scripts/dock-relay-constants.mjs`.

Performance boundaries:

- Discovery runs on relay startup, on a registry refresh interval, and on
  explicit diagnostics refresh. It never runs inside `dock/list`,
  `dock/subscribe`, `dock/resync`, `archive/subscribe`, `archive/resync`,
  `thread/detail/subscribe`, `thread/detail/resync`, `thread/read`,
  `thread/turns/list`, user command, archive, rename, or voice request
  handlers.
- Request paths read cached registry snapshots. They must not call
  `registry.refreshNow()` or process discovery directly.
- Registry refresh must reuse upstream client pools and avoid reconnecting every
  endpoint on every tick when health is still fresh.
- `thread/loaded/list` is the only broad live query per endpoint. Follow-up
  `thread/read includeTurns:false` is capped by `LIVE_LOADED_LIST_LIMIT` and
  bounded by a new `LIVE_THREAD_READ_CONCURRENCY` constant in
  `scripts/dock-relay-constants.mjs`.
- Full persisted history drain stays separated from live-badge refresh. Home
  rendering should use relay state/projection windows rather than rereading all
  history rows for every visible update.
- Stale endpoints are evicted or marked unhealthy by TTL so ephemeral
  `ws://127.0.0.1:<port>` app-server processes do not accumulate forever.
- `/statusz` summarizes registry counts and capped endpoint details; it must
  not serialize thousands of rows or full command lines by default.

Discovery and auth boundaries:

- Process discovery accepts only `codex app-server` processes with attachable
  `--listen ws://127.0.0.1:<port>` or equivalent safe loopback address.
- Discovery must not classify `codex exec-server` or unrelated local WebSocket
  listeners as app-server endpoints.
- Endpoints requiring unavailable auth are recorded as `unreachableObserved`
  with auth failure, not silently skipped and not treated as live owners.
- The daemon Unix history endpoint is selected by path and health, not by
  parsing secrets from process arguments.
- No bearer token values, prompt text, transcript text, or raw JSON-RPC payloads
  enter registry diagnostics or logs.

Duplicate-owner policy:

- If multiple endpoints report the same `threadId`, prefer the row with the
  strongest status priority (`running`/active over idle over notLoaded/error)
  and then the newest update timestamp.
- Record the conflict in sanitized diagnostics so duplicate ownership can be
  investigated without exposing payload content.
- Route control to the endpoint that won the live-owner lease until the lease
  expires or another refresh supersedes it.

## 5.5 UI surfaces (ASCII mockups, if UI work)

The app keeps the existing relay-host mental model:

```text
Dock
  Host: Amir-M5.local:4510
    running badge from discovered app-server owner
    degraded host status if history daemon missing
```

The app does not show raw upstream URLs or tokens. If registry failure details
need to appear, they appear as sanitized relay connectivity messages already
supported by host state/freshness.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Relay registry | `scripts/dock-relay-app-server-registry.mjs` | new module | absent | Add registry discovery, endpoint records, health, leases, diagnostics, and test fixture injection | One SSOT for upstream app-server truth | `AppServerRegistry` | new relay registry tests |
| Upstream client | `scripts/dock-relay-json-rpc-client.mjs` | `JsonRpcWebSocketClient` | URL-only `new WebSocket(this.url, ...)` | Support `unix://` by adapting to `ws+unix:` and keep `ws://`/`wss://` behavior | Required for daemon history hard cut | transport-neutral endpoint descriptor | relay client tests |
| Relay config | `scripts/dock-relay.mjs` | args/env parse | requires history auth token and defaults history URL to `:4500` | Build registry config instead; remove normal `DEFAULT_HISTORY_APP_SERVER_WS` dependency | Stop treating one history URL as global Codex | `registryConfig` | observability/card/recovery tests |
| Thread data | `scripts/dock-relay-thread-data.mjs` | `historyClientForConfig` | single history client from `config.historyUrl` | Use `config.appServerRegistry.historyClient()` | Registry owns history endpoint | existing thread-data users |
| Thread data | `scripts/dock-relay-thread-data.mjs` | `configuredLiveEndpointsForConfig` | manual endpoints plus optional history | Replace with registry live endpoint snapshot | Automatic discovery | live filter, card contract |
| Thread data | `scripts/dock-relay-thread-data.mjs` | `collectLiveRows` | takes configured endpoints | Accept registry endpoint descriptors and update registry leases | Preserve bounded collection, move ownership | relay live tests |
| State engine | `scripts/dock-relay-state-engine.mjs` | `refreshLiveLeases` | queries configured endpoints including history | Query registry live endpoints and write owner leases | Avoid stale `historyUrl` fallback | registry live lease refresh | state subscriptions |
| Session routing | `scripts/dock-relay-live-status-cache.mjs` | `SessionRouter` | live row map plus history fallback | Use registry owner leases and method-level fallback policy | Route control to real owner where possible | owner route resolver | user command/recovery tests |
| Status | `scripts/dock-relay-status.mjs` | `rawHealthURLForHistoryURL`, `checkRawAppServerHealth`, `lastRawAppServerHealth`, `history.url`, `historyCredentialConfigured` | reports raw history app-server health from `config.historyUrl` | Replace with registry/daemon history health and sanitized registry summary; delete or rename raw history fields | Prevent stale old-model status side path | registry status snapshot | observability/status tests |
| User command | `scripts/dock-relay-user-message-command.mjs` | `submitToCodex`, `endpointForThread`, ephemeral client | sends to active session or endpoint selected by old router | Use `registry.routeForThreadMethod` and fail loud for known private owners | Prevent message send to wrong runtime | method route helper | user command tests |
| Host service | `scripts/codex-dock-host-service.mjs` | config/render/install/start/stop/status | renders raw app-server and relay services | Render/start/stop/status relay only for normal path | Delete legacy service | relay service only | host-service tests |
| Makefile | `Makefile` | top variables, `HOST_SERVICE_ARGS`, `app-server`, `app-server-env`, `app-server-logs`, `app-server-stop`, `app-server-restart`, status aliases | raw app-server variables and helper commands are normal path | Delete or convert old command surfaces; keep only relay/status names or explicit diagnostic-only commands | Entrypoint must match hard cut | registry/daemon args and relay-only helpers | host-service tests |
| Constants | `scripts/dock-relay-constants.mjs` | live/history caps | has live caps, thread max, default history URL | Add registry refresh/discovery constants and remove normal history default if present | Performance SSOT | registry constants | relay tests |
| Status | `scripts/dock-relay.mjs` | `/statusz` payload | limited history/live configured state | Add sanitized registry snapshot | Ops proof and Swift degradation | registryStatus | observability tests |
| Tests | `scripts/codex-dock-host-service.test.mjs` | raw service assertions | expects raw service/token/dependency | Rewrite for relay-only service; delete legacy-only assertions | Hard cut | relay-only host service | host-service test suite |
| Tests | `scripts/dock-relay-*.test.mjs` | relay fixtures | many fixtures pass `historyUrl` | Move fixtures to registry/test endpoints | Avoid old config contract | fixture registry factory | test:relay |
| Proof fixtures | `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-controlled-simulator-fixture.mjs`, `scripts/dock-relay-user-message-latency-fixture.mjs`, `scripts/dock-relay-client-rename-latency-fixture.mjs` | local history WebSocket fixture configs | construct `historyUrl` proof servers | Migrate to registry fixture factory or explicitly diagnostic-only override | Prevent proof from passing old model | registry fixture config | sync/simulator/latency proof tests |
| Docs | `README.md`, `AGENTS.md` | service path prose | says raw app-server `:4500` plus relay `:4510` | Rewrite to relay-only plus registry/history daemon truth | Avoid stale live instructions | updated runbook | readback/status only |
| Swift | `CodexDock/**`, `CodexDockTests/**` | connectivity/freshness only if DTO changes | app sees relay host state | Preserve unless relay status/degradation DTO changes | Phone must not know raw endpoints | sanitized relay diagnostics only | targeted Swift tests if touched |
| Diagnostics | existing relay status/doctor scripts | `relay-doctor`, debug bundle | no registry proof surface | Add sanitized registry summary and runtime proof output | Required local/home acceptance | registry diagnostics contract | observability/doctor tests |
| Runtime proof | support script under `/tmp` or existing diagnostic command | local proof command | ad hoc probes only | Produce explicit counts of addressable/unreachable endpoints queried by relay | Need real-machine proof without leaking secrets | status/proof output | manual proof, not a new product command unless needed |

## 6.2 Migration notes

Canonical owner path / shared code path:

- `AppServerRegistry` becomes the single relay-side source of upstream app-server
  truth. Existing relay modules consume it.

Deprecated APIs:

- Normal-path `config.historyUrl`, `config.historyAuthToken`, and manual-only
  `config.liveEndpoints` are retired. Fixture overrides may remain under
  registry config with explicit test/diagnostic naming.

Delete list:

- Dock-owned raw app-server service render.
- Normal `.codex-dock/app-server.token` dependency.
- Normal `--raw-app-server-listen`, `--relay-history-url`, and
  `--history-auth-token-file` host-service wiring.
- Linux `After=codex-dock-app-server.service` dependency.
- Tests whose only assertion is that raw `:4500` is created or started.
- Docs that describe raw `:4500` as canonical service path.

Adjacent surfaces tied to the same contract family:

- Host-service install/start/stop/status/doctor/log redaction.
- Relay `/statusz`, diagnostics bundle, and relay doctor.
- Simulator controlled fixtures that boot isolated service bundles.
- Device config verification must continue rejecting raw app-server hosts.

Compatibility posture / cutover plan:

- Clean cutover. Relay protocol to phone stays stable; host-service internals and
  relay upstream config are breaking changes.

Capability-replacing harnesses to delete or justify:

- None. This is relay infrastructure, not an agent prompt behavior change.

Live docs/comments/instructions to update or delete:

- `README.md` service-path sections.
- Repo `AGENTS.md` service path because it is a live instruction surface and
  currently describes raw `:4500` as canonical.
- Any comments in scripts that name `:4500` as normal history.

Behavior-preservation signals for refactors:

- `rtk npm run test:relay`.
- `rtk npm run test:host-service`.
- Targeted Swift test only if Swift contract changes.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | -------------------------------------------------------- |
| Relay upstream ownership | `scripts/dock-relay-thread-data.mjs` | registry-owned endpoints | Prevents history/live/manual config drift | include |
| Relay live refresh | `scripts/dock-relay-state-engine.mjs` | registry leases | Prevents duplicate route maps | include |
| Relay status | `scripts/dock-relay-status.mjs` | registry status snapshot | Prevents raw health status from preserving `historyUrl` | include |
| User command routing | `scripts/dock-relay-user-message-command.mjs` | registry method route helper | Prevents message send to wrong runtime | include |
| Host service lifecycle | `scripts/codex-dock-host-service.mjs` | relay-only normal service | Prevents raw app-server resurrection | include |
| Test fixtures | `scripts/dock-relay-test-helpers.mjs` and local fixture helpers | registry fixture factory | Prevents tests from keeping `historyUrl` alive | include |
| Proof fixtures | `scripts/dock-relay-sync-audit.mjs` and controlled/latency fixture scripts | registry fixture factory | Prevents real proof from exercising old model | include |
| Device config | `scripts/device-relay-config.test.mjs` | relay-host-only validation | Phone must remain raw-upstream-free | include |
| Upstream Codex private runtimes | Codex.app / VS Code / CLI | attachable registry from upstream Codex | Out of repo scope | exclude |

Pass 2 hardening decisions:

- Use native `unix://` upstream client support for daemon history. A Codex proxy
  subprocess is not part of the normal path unless implementation proves the
  native `ws+unix:` adapter is wrong and the plan is repaired.
- Keep manual upstream endpoint configuration only as an explicit test or
  diagnostic override inside registry config, not as production discovery.
- Do not add a repo-policing test that proves old files are absent by grep.
  Behavior tests should fail if raw service rendering or old routing still
  exists.
- Treat private runtime coverage as an honest limitation. Acceptance must prove
  all addressable endpoints are queried, not that Dock can see private endpoints
  Codex does not expose.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving
> the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions
> as the destination map. Phase 1 must prove a real registry-owned history plus
> discovered live-owner path. Later phases widen callers, delete service
> legacy, expose sanitized status, and prove the result on Mac/home.

## Phase 1 - Registry seam: non-Dock history plus one discovered live owner

Status: COMPLETE

Completed work:

- Added AppServerRegistry with endpoint descriptors, daemon history selection,
  process-discovered loopback live endpoints, owner leases, private-runtime
  diagnostics, and sanitized snapshots.
- Added native Codex `unix://` upstream support through the local `ws+unix:`
  adapter.
- Added focused registry/client tests and wired them into `test:relay`.
- Added registry refresh/status caps and `LIVE_THREAD_READ_CONCURRENCY` in
  `scripts/dock-relay-constants.mjs`.
- Proof: `rtk node --test scripts/dock-relay-json-rpc-client.test.mjs scripts/dock-relay-app-server-registry.test.mjs`
  passed with 4 tests and 0 failures.
- Proof: `rtk npm run test:relay` passed with 206 tests and 0 failures.

* Goal:
  Prove the highest-risk seam: the relay can select a non-Dock history endpoint,
  connect to Codex `unix://` through the native `ws+unix:` adapter, discover at
  least one loopback app-server endpoint, collect its loaded rows, and route a
  live owner lease without using Dock's private `:4500`.
* Work:
  Build the smallest real AppServerRegistry path and focused test fixtures.
  This phase is not final discovery breadth; it proves the canonical owner path
  and transport/routing shape.
* Checklist (must all be done):
  - Add `scripts/dock-relay-app-server-registry.mjs` with endpoint descriptors,
    registry lifecycle, fixture injection, history endpoint selection, live
    endpoint snapshot, unreachable-observed records, and sanitized diagnostics.
  - Update `scripts/dock-relay-json-rpc-client.mjs` so Codex `unix://` app-server
    endpoints connect through a `ws+unix:` client URL while existing `ws://` and
    `wss://` clients keep working.
  - Add tests for `unix://` URL adaptation using a Unix-socket WebSocket
    fixture.
  - Add tests for registry selection of daemon history over Dock-owned/raw
    endpoints.
  - Add tests for one discovered `ws://127.0.0.1:<port>` app-server endpoint
    returning `thread/loaded/list` plus `thread/read includeTurns:false`.
  - Add tests proving private `stdio://` observations are recorded as
    unreachable diagnostics and never used as live owners.
  - Keep all new production constants in `scripts/dock-relay-constants.mjs`.
* Verification (required proof):
  - Run the focused new registry/client tests first.
  - Run `rtk npm run test:relay` if the focused tests pass.
* Docs/comments (propagation; only if needed):
  - Add short code comments only at the Unix transport adapter and registry
    boundary if the mapping is not self-evident.
* Exit criteria (all required):
  - A registry instance can return a healthy history client without `:4500`.
  - A registry instance can return a live endpoint list from discovered
    endpoints.
  - Loaded rows from a discovered endpoint create thread owner leases.
  - Private runtime observations are visible in diagnostics but cannot be routed
    as owners.
  - No request handler or service code has been changed yet to rely on an
    incomplete registry.
* Rollback:
  - Remove the new registry module and focused tests. No service behavior has
    changed in this phase.

## Phase 2 - Relay caller migration onto registry APIs

* Goal:
  Move existing relay behavior from `historyUrl` and manual live endpoint config
  to registry-owned history, live endpoints, owner leases, and method routing.
* Work:
  Replace the old relay upstream config model where the app-server paths are
  consumed, while preserving the phone-facing `dock/*` contract and existing
  projection behavior.
* Checklist (must all be done):
  - Update `scripts/dock-relay.mjs` to construct and start AppServerRegistry,
    pass it through relay config, and stop requiring a normal
    `--history-auth-token-file`.
  - Add and use `registry.routeForThreadMethod(method, threadID, options)` as
    the canonical method-level route helper.
  - Update `scripts/dock-relay-thread-data.mjs` so `thread/list`, `thread/read`,
    `thread/turns/list`, archive, rename, unarchive, and detail helpers use
    registry history clients.
  - Replace `configuredLiveEndpointsForConfig` normal usage with registry live
    endpoints.
  - Update `collectLiveRows` integration so refresh results update registry
    owner leases and diagnostics.
  - Update `scripts/dock-relay-live-status-cache.mjs` and `SessionRouter` so
    owner routing comes from registry leases and history fallback is explicit by
    method.
  - Update `scripts/dock-relay-user-message-command.mjs` so
    `thread/message/send`, `turn/start`, and `turn/steer` use the route helper
    and fail loud for known private live owners.
  - Update `scripts/dock-relay-state-engine.mjs` live lease refresh to consume
    registry endpoint snapshots and cached leases.
  - Rewrite relay tests and fixture helpers that pass raw `historyUrl` so they
    use registry test fixtures instead.
  - Migrate `scripts/dock-relay-sync-audit.mjs`,
    `scripts/dock-relay-controlled-simulator-fixture.mjs`,
    `scripts/dock-relay-user-message-latency-fixture.mjs`, and
    `scripts/dock-relay-client-rename-latency-fixture.mjs` to the registry
    fixture factory, unless a fixture is explicitly rewritten as
    diagnostic-only override.
  - Keep manual endpoint overrides only under registry test/diagnostic config
    names.
  - Preserve realtime transcription behavior and phone auth behavior unchanged.
* Verification (required proof):
  - Run focused relay tests covering card contract, recovery, user commands,
    state subscriptions, and observability.
  - Run `rtk npm run test:relay`.
* Docs/comments (propagation; only if needed):
  - Update comments that still imply a single `historyUrl` owns Codex truth.
* Exit criteria (all required):
  - No normal relay request path reads `config.historyUrl` as the app-server
    source of truth.
  - Live badge rows are sourced from registry live endpoints and owner leases.
  - Thread control routes to the live owner lease when present.
  - The method routing table in Section 5 has tests for read, turn, interrupt,
    request-card response forwarding, archive/name, unarchive, detail, and
    private-owner failure behavior.
  - History operations fail loud when registry has no valid history endpoint.
  - All relay tests that remain assert the new registry contract, not legacy
    `:4500` behavior.
* Rollback:
  - Revert Phase 2 caller migrations while keeping Phase 1 registry code if it
    is still useful for diagnostics. Do not ship a mixed normal path.

## Phase 3 - Delete Dock-owned raw app-server service path

* Goal:
  Remove the normal host-service and Makefile path that starts Dock's private
  raw app-server.
* Work:
  Hard-cut host lifecycle to relay-only normal services and delete tests that
  only prove the old raw service exists.
* Checklist (must all be done):
  - Update `Makefile` so `rtk make services` no longer passes normal
    `--raw-app-server-listen`, `--relay-history-url`, `--raw-token-file`, or
    app-server service label args.
  - Remove normal `APP_SERVER_PORT`, `APP_SERVER_LISTEN`, `APP_SERVER_WS`,
    `APP_SERVER_TOKEN`, and `DOCK_RELAY_HISTORY_WS` usage where they only support
    the raw app-server path.
  - Update `scripts/codex-dock-host-service.mjs` so render/install/start/stop/
    restart/status manage the relay normal service without raw app-server
    service files.
  - Remove Linux `After=codex-dock-app-server.service` dependency.
  - Delete or convert Makefile old-model command surfaces:
    `app-server`, `app-server-env`, `app-server-logs`, `app-server-stop`, and
    `app-server-restart`. `app-server-status` may remain only as a compatibility
    alias to host/relay status if its output no longer refers to raw app-server
    health or credentials.
  - Rewrite host-service tests to assert relay-only render/start/stop/status.
  - Delete or rewrite tests whose only purpose is asserting raw app-server token
    creation, raw service files, or raw service start order.
  - Keep device config validation rejecting raw app-server hosts on the phone.
  - Update `README.md` and repo `AGENTS.md` service-path docs/instructions to
    the new relay-only registry model.
* Verification (required proof):
  - Run `rtk npm run test:host-service`.
  - Run `rtk npm test` if relay and host-service suites both changed.
* Docs/comments (propagation; only if needed):
  - Rewrite service runbook prose that names raw `:4500` as canonical.
  - Do not leave "legacy raw server" instructions in live docs.
* Exit criteria (all required):
  - Host-service render emits no normal raw app-server launchd plist or systemd
    unit.
  - Host-service start/stop order has no raw app-server step.
  - Normal generated service env contains no raw app-server bearer token path.
  - Makefile old app-server helper targets are gone, converted to relay-only
    aliases, or clearly diagnostic-only without raw token output.
  - `README.md` and repo `AGENTS.md` no longer describe raw `:4500` as the
    canonical normal service path.
  - App/device host config remains relay-only on `:4510`.
* Rollback:
  - Restore the previous host-service path only in git if the phase cannot pass
    tests. Do not deploy a relay that depends on both paths.

## Phase 4 - Status, degradation, and performance proof

* Goal:
  Make registry state visible enough for operations and Swift connectivity, and
  prove the performance-sensitive behavior under many threads/endpoints.
* Work:
  Add sanitized registry status and bounded refresh behavior. Touch Swift only
  if the existing freshness/connectivity path cannot represent the new fail-loud
  states.
* Checklist (must all be done):
  - Add registry summary to relay `/statusz` and relay diagnostics without raw
    tokens, prompt text, transcript text, or full payloads.
  - Update `scripts/dock-relay-status.mjs` so `checkRawAppServerHealth`,
    `rawHealthURLForHistoryURL`, `lastRawAppServerHealth`, `history.url`, and
    `historyCredentialConfigured` are deleted or renamed into registry/daemon
    concepts.
  - Include selected history endpoint transport, healthy live endpoint count,
    unreachable private count, stale/failed endpoint count, last refresh time,
    and capped endpoint details.
  - Add tests for daemon-history missing/failing state surfacing as relay
    degraded/error.
  - Add tests proving registry discovery and `registry.refreshNow()` are not
    invoked by per-row or ordinary request handlers, including `dock/resync`,
    `archive/subscribe`, `archive/resync`, `thread/detail/subscribe`, and
    `thread/detail/resync`.
  - Add tests or fixture proof for many persisted history rows, many live
    endpoints, bounded loaded-row reads, endpoint TTL, and duplicate-owner merge.
  - Add `LIVE_THREAD_READ_CONCURRENCY` to `scripts/dock-relay-constants.mjs`
    and assert per-endpoint `thread/read includeTurns:false` concurrency is
    bounded.
  - Update Swift DTO/connectivity tests only if relay status changes require app
    model changes.
  - Keep all performance constants in `scripts/dock-relay-constants.mjs`.
* Verification (required proof):
  - Run `rtk npm run test:relay`.
  - Run `rtk swift test --filter DockStoreTests` if Swift state changes.
* Docs/comments (propagation; only if needed):
  - Document registry status fields in README only if they are part of the
    operator runbook.
* Exit criteria (all required):
  - `/statusz` can explain "history unavailable", "private runtimes observed",
    and "N addressable endpoints queried" without leaking secrets.
  - `scripts/dock-relay-status.mjs` no longer exposes raw `historyUrl` health as
    the status model.
  - Performance-sensitive tests prove bounded behavior for thousands-scale
    history, multi-endpoint live refresh, and per-endpoint loaded-row reads.
  - Swift app either needs no change or correctly shows relay degraded/offline
    state through existing UI.
* Rollback:
  - Remove status additions and performance tests if they block; do not revert
    earlier hard-cut service deletion unless service startup itself fails.

## Phase 5 - Real Mac simulator proof and home deployment preparation

* Goal:
  Prove the implementation against real local Codex app-server process state and
  simulator UI before review and commit.
* Work:
  Run the service and app verification path on the Mac checkout, then prepare
  home to pull the pushed branch after commit.
* Checklist (must all be done):
  - Run `rtk npm test`.
  - Run `rtk make services` on Mac.
  - Run `rtk make app-server-status` and `rtk make dock-relay-status`; status
    must show relay-only normal service and registry health/degradation.
  - Produce runtime proof listing addressable app-server endpoints, observed
    private/unreachable runtimes, selected history endpoint, and which endpoints
    relay queried.
  - Ensure simulator/proof fixtures use registry fixture config and cannot pass
    solely through an old `historyUrl` setup.
  - Run simulator proof with a discovered non-Dock app-server owner showing a
    visible running badge.
  - Run the smallest relevant app check, likely
    `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`, if UI behavior changed.
  - Do not use physical phone proof as the only completion evidence if device
    logging or Mobile MCP blocks.
* Verification (required proof):
  - Save command outputs in the final implementation notes or worklog, not as
    new source-of-truth docs.
* Docs/comments (propagation; only if needed):
  - Update final touched docs after real proof if status/runbook wording differs
    from implementation.
* Exit criteria (all required):
  - Mac relay is running on the new code.
  - Runtime proof shows every addressable local app-server endpoint was either
    queried or reported with a concrete failure reason.
  - Private runtimes are counted honestly and not reported as visible live
    owners.
  - Simulator proof validates the phone-facing behavior through Dock relay
    `:4510`.
* Rollback:
  - Stop the new relay and report the exact failing command/status if real
    service startup fails after tests pass.

## Phase 6 - Review, commit, push, and deploy local/home relays

* Goal:
  Finish the change with strict review, clean git history, pushed branch, and
  both relay servers running the new code.
* Work:
  Run thermonuclear review, fix blockers, commit explicit paths, push, then
  update local and home services from the pushed branch.
* Checklist (must all be done):
  - Run the thermonuclear code quality review skill over the implementation.
  - Fix all blocking review findings or record the exact blocker if one cannot
    be fixed locally.
  - Re-run the smallest relevant checks after review fixes, including
    `rtk npm test` if relay/host-service code changed.
  - Inspect `rtk git status --short` and stage only explicit touched paths.
  - Commit the implementation and plan/docs changes with an accurate message.
  - Push the branch.
  - On home at `/home/aelaguiz/workspace/codex-client`, run `git fetch` and
    `git pull --ff-only` from the pushed branch.
  - Restart or start the home relay through Makefile-owned service commands.
  - Run home `rtk make dock-relay-status` and registry proof.
  - Re-check local `rtk make dock-relay-status` after deployment.
* Verification (required proof):
  - Thermonuclear review result.
  - `rtk npm test` or justified narrower check after final fixes.
  - Commit hash and pushed branch.
  - Local and home relay status outputs summarized in the final response.
* Docs/comments (propagation; only if needed):
  - No extra docs cleanup phase remains; touched docs must already match the new
    architecture.
* Exit criteria (all required):
  - No blocking review findings remain.
  - Branch is committed and pushed.
  - Local relay is running the new relay code.
  - Home relay is running the new relay code.
  - Final response states tests, review, commit, push, local deploy, and home
    deploy status with exact blockers if any.
* Rollback:
  - If home deployment fails after push, leave the branch pushed and report the
    exact home blocker and command output. Do not discard Mac work.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

- Start with `rtk npm run test:relay` for relay registry, thread data,
  state-engine, and projection behavior.
- Run `rtk npm run test:host-service` after service rendering and Makefile
  changes.
- Run targeted Swift tests only if Swift DTOs, connectivity state, or UI
  degradation behavior changes.
- Use `rtk make services`, `rtk make app-server-status`, and
  `rtk make dock-relay-status` for Mac service proof.
- Use simulator proof for visible badge behavior on a discovered non-Dock live
  endpoint.
- Use home pull/restart/status proof after commit and push.

# 9) Rollout / Ops / Telemetry

- Rollout is a hard cut on the current branch, not a dual-run migration.
- The Makefile remains the entrypoint for service lifecycle on Mac and home.
- Relay `/statusz` and host-service status must expose registry state without
  raw secrets: selected history transport, live endpoint count, unreachable
  private count, last refresh time, and failure reasons.
- Logs must use relay logger helpers and must not include bearer tokens,
  OpenAI keys, prompt text, transcript text, or full JSON-RPC payloads.
- If no valid history endpoint exists, relay status is degraded/error and the
  app shows host unavailable state; the relay must not create `:4500`.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: explorer 1, explorer 2, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Section 0 scope, priorities, problem statement, research,
    current architecture, target architecture, call-site audit, phase plan,
    verification, rollout, and decision log.
  - Clean cutover posture, no-fallback rule, registry canonical owner path,
    Unix history transport choice, live aggregation limits, private runtime
    honesty, service deletion, proof scripts, status surfaces, and deployment
    obligations.
- Findings summary:
  - Core architecture was consistent: relay-only `:4510`, one
    AppServerRegistry, no normal raw `:4500`, no hidden fallback, no phone-side
    upstream secrets, cached/bounded discovery, and honest private-runtime
    diagnostics.
  - Explorer 1 found `AGENTS.md` doc sync was required in Section 6 but softened
    in Phase 3.
  - Explorer 2 found missing old-model owners and underspecified exit criteria:
    `scripts/dock-relay-status.mjs`, method-level routing,
    `scripts/dock-relay-user-message-command.mjs`, old proof fixtures, Makefile
    helper targets, request-path refresh boundaries, and per-endpoint
    `thread/read` concurrency.
- Integrated repairs:
  - Made repo `AGENTS.md` service-path update explicitly required.
  - Added `scripts/dock-relay-status.mjs` to the call-site audit and Phase 4.
  - Added `registry.routeForThreadMethod(method, threadID, options)` and a
    method routing table.
  - Added `scripts/dock-relay-user-message-command.mjs` as a production caller.
  - Added sync-audit, controlled-simulator, user-message latency, and rename
    latency fixture migration.
  - Added Makefile old command surfaces to Phase 3.
  - Added cached-registry-only request-path boundaries for dock/archive/detail
    subscribe/resync paths.
  - Added required `LIVE_THREAD_READ_CONCURRENCY` and per-endpoint loaded-row
    concurrency proof.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-06-05 - Intent-derived - North Star already approved

The user explicitly requested a hard cut from Dock's broken raw-app-server
method to a single elegant Codex-supporting method, with no legacy fallback and
high performance for thousands of Codex threads. This plan is therefore
`status: active` and proceeds into auto-plan without asking for redundant
North Star confirmation.

## 2026-06-05 - Evidence-derived - Private runtimes remain honest diagnostics

Repo and Codex source evidence show `stdio://` children and in-process
app-server runtimes are not externally attachable by Dock. This plan requires
the relay to report those runtimes as observed private/unreachable instead of
pretending complete machine-wide live coverage.

## 2026-06-05 - Fresh Consult Composer Fast 2.5 - Pass with notes

Fresh Consult validated the core model and hard-cut direction. It also made the
implementation blocker explicit: daemon Unix history is Codex-valid, but Dock
relay needed a Unix-socket upstream client before daemon history could be the
normal path. The implementation adds that native `unix://` upstream path.

## 2026-06-05 - Evidence-derived - Native Unix upstream support is the chosen path

The local `ws` package supports `ws+unix:` IPC WebSocket URLs and maps them to
`socketPath`. The implementation adds a relay-side adapter from Codex
`unix://` app-server endpoints to `ws+unix:` client URLs, instead of making a
Codex proxy subprocess part of the normal service path.

Real-machine proof added one extra constraint: Node's WebSocket client must set
`perMessageDeflate: false` for upstream Codex app-server connections. The
Codex Unix control socket accepted a raw no-compression upgrade and rejected the
default compressed `ws` handshake with `socket hang up`.

## 2026-06-05 - Auto-plan deep-dive pass 2 - Performance and honesty hardened

The second planning pass made performance and coverage limits explicit:
discovery cannot run on request paths, live refresh must be bounded, endpoint
churn must be managed by health/TTL, duplicate live owners need deterministic
merge/routing policy, and acceptance must prove all addressable endpoints are
queried without claiming visibility into private `stdio://` or in-process
runtimes.

## 2026-06-05 - Fresh Consult GPT-5.5 High - Pass with notes

Fresh Consult returned `VERDICT: pass-with-notes`, `BLOCKING: none`, and high
confidence. It agreed the plan is architecture-ready: the Codex mental model is
correct, relay-only `:4510` plus AppServerRegistry is sound, performance limits
are explicit, and hard-cut deletion work is captured. The only plan repair was
to add raw JSON-RPC server-request/request-card response routing as an
active-session-only path; that repair is now included in the method routing
table and Phase 2 exit criteria.
