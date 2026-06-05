# Codex Dock Unified Attachable App-Server Registry

Date: 2026-06-05

## North Star

Codex Dock must treat every attachable Codex app-server transport as one app-server
protocol path. Unix sockets and WebSockets must be discovered, probed, routed, and
tested through the same registry owner model. The iPhone still talks only to the
Dock relay on `:4510`; the relay decides which local Codex app-server endpoint owns
each thread.

The intended user-visible truth is:

- If a Dock row says `Codex is working`, opening that row must route through an
  attachable app-server owner and load detail through `thread/detail/subscribe`.
- If the relay only has private `stdio://` process evidence for a thread, the row
  must not receive the same running badge as an attachable owner.
- If a Unix app-server has a loaded thread, the relay must discover it and route to
  it exactly like it routes to a WebSocket live owner.

## Mental Model

```text
iPhone / simulator
  |
  |  one phone-facing WebSocket contract
  v
Dock relay ws://<host>:4510
  |
  |  one transport-neutral registry
  v
Attachable Codex app-server endpoints
  |
  +-- unix://...      same JSON-RPC app-server protocol
  +-- ws://127...     same JSON-RPC app-server protocol
  +-- wss://...       same JSON-RPC app-server protocol when configured

Private observations
  |
  +-- stdio://        parent-owned stream; diagnostic only unless Codex exposes
                      an attachable endpoint for that runtime
```

## Current Facts

### Upstream Codex

- Installed Codex is `codex-cli 0.136.0-alpha.2`.
- `codex app-server --help` says `--listen` supports `stdio://`, `unix://`,
  `unix://PATH`, `ws://IP:PORT`, and `off`; `stdio://` is the default.
- Upstream app-server docs state the protocol is JSON-RPC and list supported
  transports as `stdio`, `websocket`, `unix socket`, and `off`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:22`).
- The same docs say WebSocket is experimental/unsupported and Unix socket is the
  intended local control-plane transport
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:37`).
- The same docs define `thread/loaded/list` as the API that returns thread ids
  loaded in memory (`/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md:138`).
- Upstream `AppServerTransport` has `Stdio`, `UnixSocket`, `WebSocket`, and
  `Off`, with default listen URL `stdio://`
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/mod.rs:66`).
- Upstream remote app-server client connects to either
  `RemoteAppServerEndpoint::WebSocket` or `RemoteAppServerEndpoint::UnixSocket`
  through the same client abstraction
  (`/Users/aelaguiz/workspace/codex/codex-rs/app-server-client/src/remote.rs:72`).
- Upstream `ThreadManager` is process-local in-memory state, and
  `list_thread_ids()` reads that manager's loaded thread map
  (`/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:169`,
  `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs:958`).

### Dock Relay Today

- `scripts/dock-relay-json-rpc-client.mjs` already adapts `unix://...` to the
  `ws` package's `ws+unix:<socket>:/` URL
  (`scripts/dock-relay-json-rpc-client.mjs:29`).
- The relay already has a test proving the Unix JSON-RPC client can initialize and
  call `thread/list` over a Unix app-server socket
  (`scripts/dock-relay-json-rpc-client.test.mjs:58`).
- Endpoint normalization already records `transport: "unix"` and `socketPath`
  (`scripts/dock-relay-app-server-discovery.mjs:275`).
- Process discovery currently classifies `codex app-server --listen unix://...`
  as `endpointType: "history"`, not live
  (`scripts/dock-relay-app-server-discovery.mjs:475`).
- Registry refresh currently admits live endpoints only when
  `endpointType === "live"` and transport is `ws` or `wss`
  (`scripts/dock-relay-app-server-registry.mjs:313`).
- The registry's live scan already uses transport-neutral JSON-RPC calls:
  `initialize`, `thread/loaded/list`, and `thread/read includeTurns:false`
  (`scripts/dock-relay-app-server-registry.mjs:598`).
- The phone-facing detail path routes through
  `routeForThreadMethod()` (`scripts/dock-relay-thread-data.mjs:1148`).
- `routeForThreadMethod()` currently checks private owner evidence before
  attachable owner evidence, so private evidence can block a real attachable owner
  if both exist for the same thread
  (`scripts/dock-relay-app-server-registry.mjs:706`).
- `privateLiveRows()` currently emits private `stdio://` observations with
  `status.type = "active"` (`scripts/dock-relay-app-server-registry.mjs:503`).
- Relay card normalization maps `status.type = "active"` to Dock status
  `running` (`scripts/dock-relay-state-views.mjs:134`).
- Swift renders Dock status `.running` as `Codex is working`
  (`CodexDock/Dock/DockModels.swift:14`).

## Requirements

1. The app-server registry must have one definition of attachability:
   the relay can open the endpoint, complete the app-server `initialize`
   handshake, and call `thread/loaded/list`.
2. Attachability must be transport-neutral for `unix`, `ws`, and `wss`.
3. `stdio://` must remain diagnostic-only unless Codex exposes a shareable
   endpoint for that runtime. Dock must not try to steal or attach to another
   process's private stdin/stdout.
4. A Unix endpoint that returns a loaded thread id from `thread/loaded/list` must
   create the same owner lease as a WebSocket endpoint.
5. A thread method that needs live ownership, including
   `thread/detail/subscribe`, must prefer an attachable live owner over private
   diagnostic evidence.
6. Private-only rows must not produce the `Codex is working` badge.
7. Swift must continue to talk only to relay-owned routes:
   `dock/*`, `archive/*`, and `thread/detail/*`. Swift must not learn how to
   pick Unix vs WebSocket vs stdio.
8. If no attachable live owner exists, history-safe routes may still use the
   selected history endpoint. Live-only operations must fail loudly with a clear
   relay error.
9. Route-health and proof probes must not treat private-only diagnostic rows as
   app-critical healthy detail sessions. A `thread/detail/subscribe` health pass
   for a running row requires an attachable owner route, not private process
   evidence.
10. The status/health pages must show enough sanitized evidence to distinguish
   attachable endpoints, private observations, failed endpoints, and owner leases
   without exposing bearer tokens or prompt payloads.
11. The implementation must run on both relay hosts from the same committed code.
12. Unix socket URL normalization must match upstream Codex semantics:
    `unix://` means the daemon control socket under `CODEX_HOME`, and
    `unix://PATH` means `PATH` resolved relative to the app-server process current
    working directory when `PATH` is relative. If the relay cannot know the cwd
    for a process-discovered relative Unix path, it must mark that endpoint
    diagnostic/failed instead of silently probing the wrong absolute `/PATH`.

## Non-Requirements

- Do not make the iPhone connect directly to raw Codex app-server endpoints.
- Do not pass app-server bearer tokens, OpenAI keys, prompt text, transcript text,
  or full JSON-RPC payloads to the phone or logs.
- Do not create a second phone-facing Unix-specific route family.
- Do not try to attach to private `stdio://` streams owned by Codex App, Codex CLI,
  VS Code, or another parent process.
- Do not solve upstream Codex process model limitations in this repo.
- Do not make WebSocket the preferred production assumption when Codex declares it
  experimental and Unix is the local control-plane path.

## Target Architecture

### 1. Registry Endpoint Roles

The registry should stop using `endpointType` as the only source of routing
truth. `endpointType` can remain as a discovery/reporting label for compatibility,
but live-owner probing must be derived from endpoint capability.

Target rule:

```text
live-owner-probe candidate =
  endpoint has no failure
  and endpoint is not Dock-owned raw legacy app-server
  and endpoint transport is one of: unix, ws, wss
  and either endpoint transport is unix or endpoint is discovered/configured as live
  and endpoint is local/allowed by existing security policy
```

This means:

- the daemon `unix://` history endpoint may also be probed for loaded owners;
- process-discovered `unix://PATH` app-servers are probed for loaded owners;
- existing loopback WebSocket app-servers continue to be probed;
- WebSocket endpoints configured only as history endpoints stay history-only
  unless they are also discovered or configured as live owners;
- private `stdio://` observations remain out of the attachable candidate set.

Unix path handling is part of attachability. `unix://` should canonicalize to
the daemon socket for the relevant `CODEX_HOME`. Absolute `unix:///path.sock`
can be probed directly. Relative `unix://path.sock` is only safely attachable
when the relay has the owning process cwd and can resolve the same absolute path
that upstream Codex resolved; otherwise the endpoint should become a sanitized
diagnostic failure such as `unix_socket_relative_cwd_unknown`.

The implementation may keep the public method name `liveEndpoints()` to reduce
caller churn, but its meaning must become "attachable owner-probe endpoints", not
"WebSocket endpointType live only." If renamed, all call sites must move in the
same change, with no compatibility side door left behind.

### 2. One Owner Lease Path

There should be one owner lease map:

```text
thread id -> { endpoint, row, checkedAt, checkedAtMs }
```

That map must be populated only by attachable endpoint probes that successfully
return loaded thread ids and readable thread rows. The existing
`recordLiveRows(endpoint, rows)` path already fits this model and should remain
the owner of live leases.

The endpoint stored in an owner lease can be `unix`, `ws`, or `wss`; callers must
not branch on transport.

### 3. Routing Precedence

For thread-specific methods, routing precedence must be:

1. Explicit active session endpoint, when present.
2. Active-session-only rejection for methods that cannot safely run without a
   current detail session.
3. Attachable owner lease, if the method is live-owner preferred.
4. Private owner rejection, only when no attachable owner lease exists and the
   method is not explicitly history-safe for private owners.
5. History endpoint for history-safe or fallback-compatible methods.

This fixes the current inversion where private evidence is checked before
attachable owner evidence.

### 4. Private-Only Rows Are Diagnostic, Not Running

Private process detection is useful, but it is not proof of attachability.
Private-only rows may remain visible so Amir can see that a real Codex runtime
exists, but they must not produce `status=running` or `Codex is working`.

Preferred implementation:

- keep private observations in the same live row merge path so there is no second
  list pipeline;
- make their relay status normalize to Dock `unknown`, using an unrecognized
  private diagnostic upstream status type such as `{ "type": "privateUnattachable" }`;
- preserve sanitized `dockRelaySource.failure.reason = "private_transport"` so
  detail/routing errors can explain the limitation;
- avoid adding a new Swift status unless the product needs a visible private-only
  badge label now.

Rationale: the immediate correctness bug is a false positive badge. Using an
existing non-badge state keeps the contract small. A new `unattachable` or
`private` status can be added later if the list UI needs a visible label, but it
is not required for the foundational Unix attachability fix.

### 5. Merge Rules

When the same thread id appears from both attachable and private evidence:

- attachable owner evidence wins for routing;
- attachable owner status wins for card status;
- private evidence may remain as diagnostic metadata, but it must not downgrade or
  block an attachable owner.

When the same thread id appears from history and attachable evidence:

- history continues to provide durable thread metadata;
- attachable evidence overlays current status and session id;
- detail and live-owner-preferred commands route to the attachable owner.

### 6. State And Health

Status snapshots should expose sanitized counts and endpoint summaries that make
this diagnosable:

- total endpoints;
- attachable owner-probe endpoints;
- selected history endpoint;
- private observations/private owners;
- owner lease count;
- failed endpoint count;
- failure reasons such as `unix_socket_missing`, `private_transport`, and
  `non_loopback_app_server`.

No token, prompt, transcript, full request payload, or raw JSON-RPC body should
be logged or returned.

## Implementation Plan

### Phase 1: Transport-Neutral Attachable Endpoint Selection

Change `scripts/dock-relay-app-server-registry.mjs` so the endpoint list used by
`liveEndpoints()` includes every healthy attachable app-server endpoint:

- `unix`;
- `ws`;
- `wss`;
- not `stdio`;
- not failed;
- not Dock-owned raw legacy endpoint.

Keep `failureForEndpoint()` as the local validation owner. Do not duplicate Unix
socket existence checks at call sites.

Expected first proof:

- a Unix fixture endpoint appears in `registry.liveEndpoints()`;
- `registry.collectLiveRows()` calls `thread/loaded/list` and `thread/read` over
  that Unix endpoint;
- `registry.ownerForThread(threadId)` points at the Unix endpoint.

### Phase 2: Routing And Badge Truth

Change `routeForThreadMethod()` so attachable owner leases outrank private owner
diagnostics.

Change `privateLiveRows()` so private-only rows no longer emit `status.type =
"active"`. Emit a private diagnostic status type that normalizes to Dock
`unknown` and keeps Swift contract compatibility.

Audit the status/probe path so `thread/detail/subscribe` failures caused by
private-only diagnostic rows do not keep route health in a false app-critical
state. Existing passive failures may age out, but new proof must show that
private-only diagnostics are not accepted as healthy running-detail sessions.

Expected proof:

- with both private and attachable owner evidence for a thread, route source is
  `live-owner`;
- with only private owner evidence, `thread/read` and `thread/detail/subscribe`
  still reject with `private_owner_unattachable`;
- private-only rows do not normalize to Dock status `running`;
- route-health/proof sampling either skips private-only `unknown` rows or marks
  their detail failures as expected private diagnostics; it must not classify
  them as successful running detail sessions.

### Phase 3: State Pipeline And Detail Proof

Keep callers on the existing registry path:

- `scripts/dock-relay-thread-data.mjs` uses `appServerRegistry.liveEndpoints()`;
- `scripts/dock-relay-state-engine.mjs` uses `appServerRegistry.liveEndpoints()`;
- Swift receives the same `DockThreadCardDTO` stream shape unless a new status is
  intentionally added.

Expected proof:

- controlled relay fixture with Unix live owner produces a Dock card status of
  `running`;
- tapping/opening the fixture detail route exercises `thread/detail/subscribe`
  through the same relay route and reaches the Unix owner;
- controlled private-only fixture does not show a running badge and detail fails
  with the private runtime explanation.

### Phase 4: Docs, Deployment, And Drift Closure

Update docs that currently teach WebSocket-only live discovery:

- `README.md`;
- `docs/bugs/private-codex-runtime-thread-detail-unavailable-2026-06-05.md`;
- this plan's worklog or final notes if a separate worklog is added.

Do not leave docs saying live owners are only "loopback WebSocket owners."

Deploy from the Mac authoritative checkout:

1. Commit and push the Mac branch.
2. Refresh the home checkout with `git fetch` and `git pull --ff-only`.
3. Run/restart the Dock relay service on both hosts through Makefile-owned
   targets.
4. Verify both hosts using status and route checks.

## Test Plan

### Focused Node Tests

Run:

```sh
rtk node --test scripts/dock-relay-json-rpc-client.test.mjs scripts/dock-relay-app-server-registry.test.mjs
```

Required new/updated tests:

1. Unix app-server endpoint is attachable:
   - fixture Unix server implements `initialize`, `thread/loaded/list`, and
     `thread/read`;
   - registry includes it in `liveEndpoints()`;
   - `collectLiveRows()` records an owner lease;
   - `routeForThreadMethod("thread/read", id)` returns `source: "live-owner"`.
2. Daemon history Unix endpoint is also owner-probe capable:
   - include daemon `unix://`;
   - fixture returns loaded thread id;
   - selected history endpoint remains Unix;
   - owner lease uses same endpoint without duplicate routing concepts.
3. Private evidence cannot outrank attachable evidence:
   - same thread id has `recordPrivateOwner()` and `recordLiveRows()`;
   - live-owner-preferred methods route to attachable owner;
   - the merged card/status keeps the attachable owner status rather than being
     downgraded or blocked by the private diagnostic row.
4. Private-only rows are not running:
   - private row status normalizes to `unknown`, not `running`;
   - no `Codex is working` badge can be inferred from private-only evidence.
5. Private-only live methods still fail loudly:
   - `thread/read` and `thread/detail/subscribe` reject with
     `private_owner_unattachable`;
   - `thread/turns/list` can still use history only when
     `allowHistoryForPrivateOwner` is set.
6. Route-health/proof probes do not accept private-only diagnostics as healthy
   running sessions:
   - a private-only row is skipped for successful running-detail proof or fails
     with an expected private diagnostic outcome;
   - an attachable Unix owner is required for a passing running-detail proof.
7. WebSocket behavior does not regress:
   - existing loopback WebSocket live-owner tests continue to pass.
8. Relative Unix socket paths do not silently point at the wrong socket:
   - `unix://` resolves to the daemon socket for the active `CODEX_HOME`;
   - absolute `unix:///tmp/example.sock` remains absolute;
   - relative `unix://example.sock` is resolved against process cwd when cwd is
     available, or is rejected with a diagnostic reason when cwd is unavailable.

### Full Relay Test Suite

Run:

```sh
rtk npm run test:relay
```

This must pass because the change affects relay routing, card status, controlled
fixture proof, state subscriptions, and detail recovery paths.

### Swift Tests

If no Swift status or DTO contract changes are made, Swift tests are not required
for the registry logic itself. If a new Dock status or DTO field is added, run:

```sh
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

If `project.yml` or app target wiring changes, use:

```sh
rtk make app-test SIM='iPhone 17'
```

### Controlled Simulator Proof

Use the repo's existing controlled relay/simulator fixture rather than preview
rows. The fixture proof must include:

- one Unix attachable live-owner row, including the detail route through that
  Unix owner;
- one private-only row;
- a successful `thread/detail/subscribe` on the Unix live-owner row;
- no `Codex is working` badge for the private-only row.

If the existing controlled fixture only supports WebSocket live endpoints, extend
the fixture once at the transport boundary so it can host a Unix app-server using
the same JSON-RPC handlers. Do not create a separate Unix-only proof harness.

### Real Local Relay Proof

Run:

```sh
rtk make services
rtk make dock-relay-status
rtk make app-server-status
```

Also probe the real relay with a script or existing sync audit to confirm:

- status snapshot shows Unix in owner-probe endpoints;
- daemon `unix://` can be initialized and queried;
- private-only rows do not report `running`;
- route health no longer gets new app-critical `thread/detail/subscribe`
  failures from private-only diagnostic rows masquerading as running rows;
- any thread with a real attachable owner can open detail.

If no currently running Unix app-server owns a loaded thread, record that exact
runtime state and rely on the Unix fixture for loaded-owner proof plus the real
daemon proof for transport proof.

### Physical Phone Proof

After commit/push/deploy, install or verify the configured physical app path only
through Makefile targets. Preferred commands:

```sh
rtk make device-install-all
rtk make device-config-verify-all
```

If physical device tooling is unavailable, record the exact skipped command and
exact blocker. Simulator/local proof cannot be described as physical-phone
completion evidence.

### Both-Host Deployment Proof

Mac:

```sh
rtk make services
rtk make dock-relay-status
```

Home:

```sh
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && git fetch && git pull --ff-only && rtk make services && rtk make dock-relay-status'
```

If home-only dirt blocks `git pull --ff-only`, report the dirty paths and the
cleanup command before discarding anything.

## Fresh Consult And Plan Audit Gates

Before implementation:

1. Run plan-readiness audit with `$plan-audit`.
2. Repair this plan until the audit log has no blocking findings.
3. Run `$fresh-consult` with `runtime=codex`, `model=gpt-5.5` if available, and
   reasoning effort `xhigh`.
4. Ask the consult to review this architecture, the current bug doc, current
   relay registry code, and this full test plan.
5. Incorporate valid consult findings into this plan.
6. Re-run plan audit until the plan is `ready`.

The fresh consult should be read-only. It must not edit files or run deploy
commands.

## Implementation Exit Criteria

The work is not complete until all of these are true:

- the architecture plan is audited ready;
- the fresh consult agrees there is no blocking architecture/test-plan issue, or
  all valid consult issues are repaired and re-audited;
- relay code implements transport-neutral owner probing for Unix/WebSocket;
- private-only rows no longer show `Codex is working`;
- route precedence prefers attachable owners over private diagnostics;
- focused Node tests pass;
- full relay tests pass;
- required Swift/app tests pass if Swift/app contract changes;
- simulator proof exercises actual Dock/detail routes with a Unix live-owner
  fixture and private-only fixture;
- real local relay status/probes pass or record exact runtime limits;
- thermonuclear code review runs after implementation and any valid findings are
  fixed;
- changes are committed and pushed from the Mac authoritative checkout;
- home checkout is updated from the pushed branch with `git pull --ff-only`;
- both relay hosts are running the new committed code and status checks pass or
  any remaining blocker is recorded exactly.

## Explicit Risk Register

- `stdio://` is not attachable by design. If most user sessions are pure private
  stdio with no Unix/WS owner, Dock can only stop lying about the badge unless
  upstream Codex changes how those sessions expose a control endpoint.
- The current daemon Unix socket may be history-only in practice unless it owns
  loaded sessions. The architecture still must probe it because Codex defines
  `thread/loaded/list` on that same endpoint.
- A new Swift status would create contract churn. Avoid it unless the relay cannot
  truthfully express private-only rows with existing non-running states.
- Route health can stay not-ready while the old relay is still running or while
  app-critical detail probes hit private-only threads. Verification must use the
  new code and a controlled attachable Unix owner proof.
