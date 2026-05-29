# Plan Audit Log

Plan: docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29.md
Audit log: docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29_PLAN_AUDIT.md
Current plan verdict: complete-current-evidence
Current implementation code-review verdict: pass
Last reviewed: 2026-05-29T04:16:00Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

No blocking implementation findings remain after the 2026-05-29T03:55Z pass.
The latest audit found and fixed one additional focused-routing side door in
upstream recovery before approval.

## Resolved Findings From This Pass

- [x] PLA-001 - Early phases depended on probe targets created too late.
  - Lens: proof and phase exit, docs-contract drift
  - Evidence: Phase 1 needed leak-check proof and Phase 2 needed `relay-probe`
    proof while Makefile target creation lived in Phase 5.
  - Required plan repair: Move `rtk make relay-leak-check` ownership to Phase 1
    and `rtk make relay-probe` ownership to Phase 2; keep Phase 5 for final
    reruns and docs.
  - Status: resolved
  - Resolution evidence: Phase 1 now adds/exits on `rtk make relay-leak-check`;
    Phase 2 now adds/exits on `rtk make relay-probe`; Phase 5 only reruns both
    as final proof.

- [x] PLA-002 - Swift still had a one-page `limit=200` assumption.
  - Lens: code-truth map, proof and phase exit
  - Evidence: `CodexDock/State/DockStore.swift` has `sessionPageLimit = 200`;
    `SessionSummaryMapper` maps `response.data` only; `ThreadListResponseDTO`
    decodes cursors but they did not leave the DTO boundary.
  - Required plan repair: Require Swift to request `limit=100`, preserve/use
    cursors, expose app-side continuation loading, and prove >100-row access
    through `DockStoreTests`.
  - Status: resolved
  - Resolution evidence: Phase 2 now explicitly carries `nextCursor`,
    `backwardsCursor`, and `liveOverlay` through `ThreadListResponseDTO` ->
    `AppServerDockClient` -> `DockLoadResult` -> `DockStore.makeSnapshot` /
    `DockHostLoadStatus` -> `AppConnectivityStore`, and requires >100-row Swift
    proof.

- [x] PLA-003 - `ps` discovery side doors existed outside `thread/list`.
  - Lens: deletion and side-door closure, canonical owner and SSOT
  - Evidence: `scripts/dock-relay-thread-data.mjs` calls `collectLiveRows()` in
    `aggregateThreadRead`, `endpointForThread`, `listThreadTurns`, and archive
    routing, not only dashboard list.
  - Required plan repair: Require all normal request paths to use
    `LiveStatusCache` or `SessionRouter`; allow `discoverLoopbackEndpoints`
    only inside the bounded cache refresh boundary.
  - Status: resolved
  - Resolution evidence: Section 0.5 and Phase 3 now name `thread/loaded/list`,
    `thread/read`, `thread/turns/list`, `thread/archive`, `thread/resume`,
    `endpointForThread`, and future focused routes as paths that must not call
    request-time `ps`.

- [x] PLA-004 - README and package scripts could keep teaching the old relay
  model.
  - Lens: docs-contract drift, deletion and side-door closure
  - Evidence: `README.md` still describes live rows merging over history;
    `package.json` exposes `npm run dock-relay` as direct relay startup.
  - Required plan repair: Require README/AGENTS/package scripts to stop teaching
    live-first merge or direct npm relay startup as the normal path.
  - Status: resolved
  - Resolution evidence: Phase 5 now requires README service-path text to say
    history list plus cached live overlay, and requires removing or demoting
    `npm run dock-relay` as a normal operator path.

- [x] PLA-005 - Relay instance id had no single app-safe source.
  - Lens: ambiguity and miscommunication, caller/state model
  - Evidence: The plan required grouping by relay instance id, while current
    app-safe config writes only `CODEX_DOCK_HOSTS` and saved device config
    carries endpoint host/port only.
  - Required plan repair: Choose the canonical identity source and carry exact
    field names through app env, device config, Bonjour, `/statusz`,
    initialization, and Swift grouping.
  - Status: resolved
  - Resolution evidence: Section 0.5 now makes generated app-safe config the
    canonical identity source: `CODEX_DOCK_RELAY_INSTANCE_ID` in host env and
    `relayInstanceID` in physical `relay-config.json`; initialization, Bonjour
    TXT `relay-id`, and `/statusz` echo it for verification.

- [x] PLA-006 - `/debugz/sessions` lacked an access boundary.
  - Lens: security boundary, docs-contract drift
  - Evidence: Current relay HTTP routes are unauthenticated and the relay
    listens on `0.0.0.0`; the plan added `/metricsz` and `/debugz/sessions`
    without saying whether they were public, auth-gated, or loopback-only.
  - Required plan repair: Define public vs local-only diagnostic endpoints and
    allowed fields.
  - Status: resolved
  - Resolution evidence: Section 0.5 and Phase 3 now define `/readyz`,
    `/healthz`, and `/statusz` as app-safe public diagnostics, and `/metricsz`
    plus `/debugz/sessions` as loopback-only Makefile-probe endpoints.

- [x] PLA-007 - One broad `RelayStatusSnapshot` would leak internal debug shape
  into app-facing DTOs.
  - Lens: elegance and code-judo, security boundary
  - Evidence: Current `ThreadListResponseDTO` needs a small app-facing metadata
    shape, while current relay status includes broader auth/history/transcription
    state.
  - Required plan repair: Keep one internal status owner but require narrow
    projections: `LiveOverlay`, `StatuszSnapshot`, `MetricsSnapshot`, and
    `DebugSessionsSnapshot`.
  - Status: resolved
  - Resolution evidence: Section 5.3 now defines `RelayStatusStore` plus narrow
    projection types and allowed field sets.

- [x] PLA-008 - Phase 2 degraded state was easy to misread before Phase 3.
  - Lens: ambiguity and miscommunication, proof and phase exit
  - Evidence: Phase 2 cut over list semantics while Phase 3 added the real
    `LiveStatusCache`; without a minimal Phase 2 response shape, the app could
    still appear fully healthy.
  - Required plan repair: Define the exact Phase 2 non-healthy `liveOverlay`
    shape and require Swift to map it to degraded/stale.
  - Status: resolved
  - Resolution evidence: Phase 2 now requires minimal `liveOverlay`:
    `{ ok: false, state: "disabled" | "unavailable", ageMs: null }`, carried
    through the Swift store/connectivity path.

- [x] PLA-009 - Logical-host migration omitted app-side owners that could keep
  endpoint-as-host behavior alive.
  - Lens: code-truth map, canonical owner and SSOT
  - Evidence: Current code uses endpoint IDs in `RelayDiscovery`,
    `LocalRelayEndpointList`, `RelayBootstrapStore`, `HostSettingsStore`,
    `CodexDockRootView`, `DockStore`, `ArchiveStore`, and connectivity state.
  - Required plan repair: Expand the call-site audit and Phase 4 to name every
    reader/writer and define one `LogicalHost` persistence/config shape.
  - Status: resolved
  - Resolution evidence: Sections 5, 6, and Phase 4 now name
    `DockRelayEndpoint`, `DockHostConfiguration`, `RelayDiscovery`,
    `LocalRelayEndpointList`, `RelayBootstrapStore`, `HostSettingsStore`,
    `HostsView`, `CodexDockRootView`, `DockStore`, `ArchiveStore`, and
    `AppConnectivityStore`.

- [x] PLA-010 - Direct phone `:4500` remained writable through app-safe config
  side doors.
  - Lens: security boundary, deletion and side-door closure
  - Evidence: Current Makefile device config variables, `DockRelayEndpoint`,
    manual Host Settings, legacy config migration, and host env generation can
    accept arbitrary valid ports.
  - Required plan repair: Add explicit Phase 4/5 work to reject raw `:4500` from
    generated simulator/device/manual/saved app config, while keeping Mac-side
    service internals on `ws://127.0.0.1:4500`.
  - Status: resolved
  - Resolution evidence: Section 0.5, Section 6.2, and Phase 4 now require
    rejecting raw `:4500` from app-facing config paths and tests.

- [x] PLA-011 - Relay metadata/cursor SSOT stopped at Swift DTO decode.
  - Lens: code-truth map, caller/invariant/state
  - Evidence: `ThreadListResponseDTO` decodes cursors, but
    `AppServerDockClient`, `DockLoadResult`, `SessionSummaryMapper`,
    `DockStore`, and `AppConnectivityStore` did not own response metadata.
  - Required plan repair: Name the exact response-level metadata owner path and
    require tests proving cursor/live-overlay metadata survive past DTO decode.
  - Status: resolved
  - Resolution evidence: Phase 2 now carries response metadata through
    `ThreadListResponseDTO` -> `AppServerDockClient` -> `DockLoadResult` ->
    `DockStore.makeSnapshot` / `DockHostLoadStatus` -> `AppConnectivityStore`.

## Resolved Implementation Findings From Pass 2

- [x] IMP-001 - Endpoint aliases could still split into endpoint-as-host rows
  when `CODEX_DOCK_HOSTS` had multiple endpoints but no relay instance id.
  - Evidence: `HostRegistry.fromEnvironment` mapped each endpoint to its own
    `DockHostConfiguration`; `LocalRelayEndpointList.hostConfigurations` did
    the same for saved multi-endpoint configs.
  - Fix: `DockHostConfiguration(endpoints:relayInstanceID:)` now rejects
    multiple endpoints without a relay instance id. `HostRegistry`,
    `LocalRelayEndpointList`, `FileLocalDockConfigurationStore`, and
    `RelayBootstrapStore` now follow that rule.
  - Proof: `rtk swift test --filter DockConfigurationTests`,
    `rtk swift test --filter DockStoreTests`, and
    `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` passed.

- [x] IMP-002 - Generated app-facing host env could keep a stale raw
  `:4500` endpoint from older service env.
  - Evidence: `scripts/codex-dock-host-service-env.mjs` merged endpoint-shaped
    values from existing `CODEX_DOCK_HOSTS` without rejecting port `4500`.
  - Fix: host-env generation now rejects raw `:4500` app-facing endpoints, and
    `--relay-public-url ws://...:4500` fails before generating app config.
  - Proof: `rtk npm run test:host-service` and `rtk npm run test:relay` passed.

- [x] IMP-003 - Thread detail used newest-first display ordering, which pinned
  new user messages at the top instead of leaving the conversation in natural
  flow.
  - Evidence: `ThreadDetailStore.publishLoaded()` used newest-first ordering.
  - Fix: `ThreadEventDisplayOrder.naturalFlow` is now the timeline display
    contract for thread detail and visibility projections.
  - Proof: `rtk swift test --filter ThreadEventNormalizerTests`,
    `rtk swift test --filter ThreadDetailStoreTests`, and
    `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` passed.

## Resolved Implementation Findings From Pass 3

- [x] IMP-004 - Focused relay submits could use a stale active upstream without
  rechecking the requested thread id.
  - Evidence: `turn/start`, `turn/steer`, and `turn/interrupt` used the
    connection's active upstream after `thread/resume`, but did not verify that
    `params.threadId` still matched the resumed thread. Raw phone responses to
    upstream server requests also forwarded to whatever upstream was active at
    response time.
  - Fix: The relay now accepts a focused upstream only when `thread/resume`
    returns the requested thread id, rejects focused turn methods whose
    `threadId` does not match the bound session, and tracks forwarded server
    request ids by session generation before forwarding phone responses.
  - Proof: `rtk npm run test:relay` passed with new regression cases for
    mismatched `turn/start`, mismatched `thread/resume`, and stale approval
    responses after a newer resume.

- [x] IMP-005 - Dock overview summaries could only fall back to stale raw
  history `preview` because raw `thread/list` returns `turns: []`.
  - Evidence: A real raw app-server probe showed list rows contain `turns: []`,
    the `preview` hash differed from the latest meaningful message hash, and
    `previewEqualsLatestMeaningful` was `false`.
  - Fix: The relay now owns a bounded `ThreadSummaryCache` that decorates rows
    with `latestSummary` from cached turns and warms missing/stale summaries
    out of band. Swift `ThreadDTO` decodes `latestSummary`, and
    `SessionSummaryMapper` prefers it before falling back to inline turns and
    raw preview.
  - Proof: `rtk npm run test:relay`,
    `rtk swift test --filter ThreadListMappingTests`,
    `rtk swift test --filter AppServerClientTests`,
    `rtk swift test --filter DockStoreTests`, and
    `rtk swift test --filter ThreadDetailStoreTests` passed.

- [x] IMP-006 - Upstream recovery could re-bind a focused session without
  rechecking the resumed thread id, and stale upstream server-request ids
  survived the closed upstream.
  - Evidence: The initial `thread/resume` path called
    `assertResumeResultMatchesRequestedThread`, but the automatic recovery path
    only awaited `thread/resume` before assigning the new upstream. On upstream
    close, `pendingServerRequests` also stayed populated for the same session
    generation.
  - Fix: Upstream close now clears `pendingServerRequests`, and recovery now
    applies the same resumed-thread invariant before accepting the new upstream.
  - Proof: `rtk npm run test:relay` passed with new regression cases for
    wrong-thread recovery binding and stale phone responses after upstream
    recovery.

## Resolved Open Follow-Ups From Pass 3

- [x] CPA-OPEN-001 - Simulator UI composer-submit through the actual interface
  into an active session is now proven for one active thread.
  - Evidence: Mobile MCP opened the simulator Dock detail for thread
    `019e71c0-ec97-70e0-bca8-ce9c16039c52`, entered a smoke-test message in
    the composer, tapped send, and the composer cleared with no visible error.
    Relay logs showed successful downstream `turn/steer` forwarding to active
    upstream `ws://127.0.0.1:59557/`.
  - Remaining related scope: CPA-OPEN-002 still requires a multi-concurrent
    session simulator proof pass.

## Resolved Implementation Findings From Pass 4

- [x] IMP-007 - Agent-scope `thread/list` responses could exceed the iOS
  WebSocket receive ceiling and flip the installed client to `Partial`.
  - Evidence: a real relay scan showed agent `limit:100` pages with response
    sizes up to `1332205` bytes. The default
    `URLSessionWebSocketTask.maximumMessageSize` on the local SDK is
    `1048576` bytes, matching the observed `Message too long` failure.
  - Fix: `AppServerDockClient` now requests active-agent rows with `limit:50`;
    the real relay scan for `limit:50` returned all `1171` agent rows across
    `24` pages with `maxRawBytes=594496`. The Swift WebSocket transport also
    sets an explicit `maximumMessageSize` of `8388608` bytes instead of relying
    on Apple's default.
  - Proof: `rtk swift test --filter AppServerClientTests` passed with the new
    bounded-agent-page and explicit-receive-limit tests.

- [x] IMP-008 - Live status refreshed every `30000` ms but became stale after
  `5000` ms, so the app was expected to oscillate between `Online` and
  `Partial`.
  - Evidence: the relay wrapper overrode `LiveStatusCache`'s `2500` ms default
    refresh cadence with `30000` ms while the cache stale threshold remained
    `5000` ms.
  - Fix: `liveStatusCacheForConfig` now leaves the refresh interval undefined
    unless explicitly configured, so `LiveStatusCache` uses its `2500` ms
    default. `AppServerDockClient` now keeps the newest live-overlay value
    across paginated loads, because the overlay is global relay state rather
    than page-specific data.
  - Proof: `rtk npm run test:relay` passed with
    `live status default refresh cadence stays below stale threshold`, and the
    simulator UI showed `Online: 1384 sessions` after reinstall.

## Resolved Open Follow-Ups From Pass 4

- [x] CPA-OPEN-002 - Simulator UI proof across multiple concurrent sessions is
  complete.
  - Evidence: Mobile MCP submitted through the installed simulator UI into
    thread `019e70b3-6b3b-7af1-a443-900ca409e895`, which mapped to active
    upstream `ws://127.0.0.1:61116/`; the message arrived in that session as
    `UI routing smoke 61116 from simulator. Please ignore.`
  - Evidence: Mobile MCP then submitted through the installed simulator UI into
    thread `019e71c0-ec97-70e0-bca8-ce9c16039c52`, which mapped to active
    upstream `ws://127.0.0.1:59557/`. Relay logs recorded
    `focused_request.route_verified` with matching `threadIDHash` and
    `activeThreadIDHash` of `5110ec7ce75d`, followed by
    `downstream.request_succeeded` for `turn/steer`.
  - Evidence: the 61116 route log recorded matching `threadIDHash` and
    `activeThreadIDHash` of `3af7f2f6d991`. The 59557 route log recorded
    matching hashes of `5110ec7ce75d`.

- [x] CPA-OPEN-003 - Simulator UI proof for latest-message Dock overview rows
  is complete.
  - Evidence: Mobile MCP search for `remount` showed a Dock overview row whose
    opening title was old, while the row summary showed the newer latest useful
    message beginning `The main production source-proof is now clean...`.
  - Screenshot:
    `/tmp/codex-client/20260529T0400Z/overview-latest-summary-remount.png`.

- [x] CPA-OPEN-004 - The `Partial` ↔ `Online` status toggle root cause is
  fixed and proven stable on the simulator.
  - Evidence before fix: UI showed `Agents: App-server disconnected: The
    operation couldn’t be completed. Message too long` and later
    `Partial: Amir-M5: Live status stale`.
  - Evidence after fix: Mobile MCP saw `Online: 1384 sessions`, `All 213`,
    `Agents 1171`, and host row
    `amir-m5.fairy-salmon.ts.net:4510 · 1384 sessions`.
  - Screenshot:
    `/tmp/codex-client/20260529T0415Z/overview-online-after-message-size-fix.png`.
  - Log proof: simulator unified logs contain
    `connectivity overall status=Online message=1384 sessions`; relay logs for
    active-agent `limit:50` pages show `liveOverlayState":"ready"`.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `scripts/dock-relay.mjs`, `scripts/dock-relay-thread-data.mjs`, `scripts/dock-relay-json-rpc-client.mjs`, `scripts/dock-relay-status.mjs` | Relay list, live discovery, focused routing, upstream lifecycle, status surfaces | parent, explorers | read |
| Host service and env | `Makefile`, `scripts/codex-dock-host-service.mjs`, `scripts/codex-dock-host-service-env.mjs`, `package.json` | Makefile-owned workflows, app-safe vs service env, direct relay startup side door | parent, explorers | read |
| Swift config identity | `DockHostConfiguration.swift`, `HostRegistry.swift`, `RelayDiscovery.swift`, `RelayBootstrapStore.swift`, `HostSettingsStore.swift` | Logical host identity, saved config, discovery, manual settings | parent, explorers | read |
| Swift list and connectivity | `ThreadListDTO.swift`, `AppServerClient.swift`, `DockStore.swift`, `SessionSummaryMapper.swift`, `AppConnectivityStore.swift` | Cursor/live-overlay metadata propagation and >100-row access | parent, explorers | read |
| Archive and adjacent callers | `ArchiveStore.swift`, `CodexDockRootView` references through `DockView.swift` | Endpoint-as-host side doors outside Dock tab | parent, explorers | read |
| Tests and proof surfaces | `scripts/*.test.mjs`, `CodexDockTests/AppServerClientTests.swift`, `CodexDockTests/DockConfigurationTests.swift`, `CodexDockTests/ThreadListMappingTests.swift` | Current tests encode old live-first/previews/endpoint assumptions and needed proof ownership | parent, explorers | read |
| Docs and instructions | `README.md`, `AGENTS.md`, architecture doc | Command/runbook drift and repo rules | parent, explorers | read |

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses: docs-contract drift and security boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PLA-005 | Where does Swift get `RelayInstanceID` before grouping aliases? | app-safe config, Bonjour, `/statusz`, initialize, probing each endpoint | Could still multiply hosts before identity is known | Use app-safe config as canonical; runtime surfaces echo for verification | Codex/agent, derived from user intent and repo safety constraints | Section 0.5, Section 5.3, Phase 4 | resolved |
| PLA-006 | Are `/metricsz` and `/debugz/sessions` phone-facing? | public, bearer-gated, loopback-only | Could expose debug topology on LAN/Tailscale | Make them loopback-only Makefile diagnostics | Codex/agent, security boundary | Section 0.5, Phase 3 | resolved |
| PLA-010 | Can app-facing config save `:4500`? | allow any port, known-device only, reject raw app-server ports | Could put phones on raw authenticated app-server path | Reject raw `:4500` from app-facing config paths | Codex/agent, explicit user/repo invariant | Section 0.5, Section 6.2, Phase 4 | resolved |

## Pass History

### Pass 1 - 2026-05-29T01:55:12Z

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed:
  - docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29.md
- Test/CI context accepted, if supplied:
  - none
- Agents/lenses run:
  - Explorer: code-truth-map + canonical-owner-and-SSOT
  - Explorer: proof-and-phase-exit + deletion-and-side-door + docs-contract-drift
  - Explorer: ambiguity-and-miscommunication + elegance-and-code-judo +
    tiny-team-maintainability + security-boundary
  - Parent synthesis across all required lenses
- Code areas read:
  - Relay, host service/env, Makefile, Swift config/loading/connectivity/archive,
    tests, README, AGENTS, and package scripts.
- Findings added:
  - PLA-001 through PLA-011
- Findings resolved:
  - PLA-001 through PLA-011, by plan repairs in the same pass
- Findings carried forward:
  - none
- Verdict:
  - ready
- Next audit focus:
  - implementation-audit mode after code implementation, before final approval.

### Pass 2 - 2026-05-29T03:35:00Z

- Mode: implementation-audit
- Scope: implemented plan phases plus user-reported follow-up notes.
- Baseline reviewed:
  - `CodexDock/Configuration/DockHostConfiguration.swift`
  - `CodexDock/Configuration/HostRegistry.swift`
  - `CodexDock/Configuration/RelayDiscovery.swift`
  - `CodexDock/Configuration/RelayBootstrapStore.swift`
  - `CodexDock/State/AppServerDockClient.swift`
  - `CodexDock/State/AppServerThreadDetailSession.swift`
  - `CodexDock/State/ThreadDetailStore.swift`
  - `CodexDock/Models/ThreadEvent.swift`
  - `scripts/codex-dock-host-service-env.mjs`
  - `scripts/codex-dock-host-service.mjs`
  - `scripts/dock-relay-thread-data.mjs`
  - focused Swift and Node tests.
- Independent review:
  - Fresh consult verdict: `pass-with-notes`.
  - Native read-only explorer found two real blockers that were fixed in this
    pass: multi-endpoint/no-relay-id fallback and stale generated app host env
    raw-`:4500`.
- Findings added:
  - IMP-001 through IMP-003.
- Findings resolved:
  - IMP-001 through IMP-003.
- Findings carried forward:
  - CPA-OPEN-001 through CPA-OPEN-004.
- Verification accepted:
  - `rtk swift test --filter DockConfigurationTests`: 31 passed.
  - `rtk swift test --filter DockStoreTests`: 30 passed.
  - `rtk swift test --filter AppServerClientTests`: 46 passed, 5 explicit
    real-host smoke tests skipped because opt-in env vars were not set.
  - `rtk swift test --filter ThreadDetailStoreTests`: 51 passed.
  - `rtk npm run test:host-service`: 31 passed.
  - `rtk npm run test:relay`: 53 passed.
  - `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
  - `rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
    DEVICE_RELAY_ENDPOINTS=Amir-M5.local:4510,192.168.50.74:4510
    DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed; installed build
    `20260529033451`.
  - `rtk make device-config-verify DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
    DEVICE_RELAY_ENDPOINTS=Amir-M5.local:4510,192.168.50.74:4510
    DEVICE_RELAY_INSTANCE_ID=Amir-M5`: passed.
- Verdict:
  - pass-with-open-followups.

### Pass 3 - 2026-05-29T03:55:27Z

- Mode: implementation-audit
- Scope: Phase 6 focused routing, Phase 7 Dock overview summaries, Makefile
  install/config workflow, and user-reported follow-up notes.
- Baseline reviewed:
  - `scripts/dock-relay.mjs`
  - `scripts/dock-relay-phase5.test.mjs`
  - `scripts/dock-relay-thread-data.mjs`
  - `scripts/dock-relay-thread-summary-cache.mjs`
  - `CodexDock/AppServer/ThreadListDTO.swift`
  - `CodexDock/Models/SessionSummaryMapper.swift`
  - `Makefile`
  - `README.md`
  - `AGENTS.md`
- Independent review:
  - Fresh consult: Cursor Agent `composer-2.5-fast`, run directory
    `/tmp/fresh-consult/codex-dock-composer-impl-audit-20260529T035327Z-BsL6u3`,
    verdict `pass-with-notes`.
  - The fresh consult independently flagged the recovery-path thread-id
    invariant gap; the parent had already identified and fixed the same issue
    in this pass.
  - Thermonuclear maintainability review recorded at
    `docs/CODEX_DOCK_CANONICAL_CODEX_APP_SERVER_ARCHITECTURE_2026-05-29_THERMONUCLEAR_REVIEW.md`;
    verdict approved after the same recovery fix.
- Findings added:
  - IMP-006.
- Findings resolved:
  - IMP-006 and CPA-OPEN-001.
- Findings carried forward:
  - CPA-OPEN-002 through CPA-OPEN-004.
- Verification accepted:
  - `rtk npm run test:relay`: 58 passed.
  - `rtk npm test`: relay 58 passed; host-service/device-config 31 passed.
  - `rtk make dock-relay-restart`: passed, loading the recovery hardening into
    the Makefile-owned relay service.
  - `rtk make dock-relay-status`: ready.
  - `rtk make relay-probe`: passed with `liveOverlay.state=ready`, 2 live
    endpoints, and 8 live rows.
  - `rtk git diff --check`: passed.
- Verdict:
  - pass-with-open-followups.

### Pass 4 - 2026-05-29T04:16:00Z

- Mode: implementation-audit plus installed simulator/phone proof.
- Scope: remaining CPA-OPEN-002 through CPA-OPEN-004, active-agent list sizing,
  live-status stability, simulator UI route proof, overview latest-summary UI
  proof, and iPhone 14 install/config proof.
- Baseline reviewed:
  - `CodexDock/AppServer/AppServerClient.swift`
  - `CodexDock/State/AppServerDockClient.swift`
  - `scripts/dock-relay-thread-data.mjs`
  - `scripts/dock-relay-live-status-cache.mjs`
  - `scripts/dock-relay.mjs`
  - `scripts/dock-relay.test.mjs`
  - `CodexDockTests/AppServerClientTests.swift`
- Findings added:
  - IMP-007 and IMP-008.
- Findings resolved:
  - IMP-007, IMP-008, CPA-OPEN-002, CPA-OPEN-003, and CPA-OPEN-004.
- Verification accepted:
  - `rtk swift test --filter AppServerClientTests`: 48 passed, 5 explicit
    real-host smoke tests skipped because opt-in env vars were not set.
  - `rtk npm run test:relay`: 59 passed.
  - `rtk npm test`: relay 59 passed; host-service/device-config 31 passed.
  - `rtk swift test --filter DockStoreTests`: 30 passed.
  - `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed and
    launched simulator build `20260529041311`.
  - `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
  - `rtk make relay-probe`: passed with `liveOverlay.state=ready`,
    `ageMs=2474`, 2 endpoints, and 8 live rows.
  - `rtk git diff --check`: passed.
  - `rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC
    DEVELOPMENT_TEAM=R6B8KXF3QW`: passed; installed iPhone 14 build
    `20260529041420`.
  - `rtk make device-config-verify DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`:
    passed and read back `Amir-M5.local:4510,192.168.50.74:4510`
    with `relayInstanceID=Amir-M5`.
  - Physical Mobile MCP UI inspection was not available; it returned exactly
    `WebDriverAgent is not running on device`. Per `AGENTS.md`, physical MCP
    retries stopped and simulator/local proof is the valid automated UI proof.
- Verdict:
  - pass.
