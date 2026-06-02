✅ Model B first pass: the leanest correct target is **one relay-owned projection plane plus one bounded Swift projection runtime**. The repo is already halfway there; the new doc should make that final shape mandatory and retire every display/proof side door.

**Proposed Architecture**
Raw Codex data should flow like this:

```text
raw Codex adapters
-> relay projection engine
-> versioned projection store / witness log
-> typed projection streams
-> shared Swift projection apply law
-> domain render projectors
-> render-only SwiftUI
```

The important rule:

```text
If the user can see a row, its identity, order, freshness, revision, and source host came from the relay projection contract.
```

Swift may validate, store, filter, decorate, and render. Swift must not invent visible identity, sort from timestamps, dedupe by text/request ID, or call raw Codex routes as display truth.

**Evidence Read**
- [README.md](/Users/aelaguiz/workspace/codex-client/README.md): confirms phone path is relay `:4510`, card truth is `dock/*` / `archive/*`, and stale rows can be retained.
- [CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md): current canonical live-update doc; it already names the client catch-up gap.
- [CODEX_DOCK_THREAD_019E8833_APP_VS_CODEX_LIVE_AUDIT_WORKLOG_2026-06-02.md](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_THREAD_019E8833_APP_VS_CODEX_LIVE_AUDIT_WORKLOG_2026-06-02.md): proves the stuck refresh loop in real app behavior.
- [CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md): strongest existing identity plan; I would broaden it into the holistic client runtime plan.
- [contract/projection/**](/Users/aelaguiz/workspace/codex-client/contract/projection/projection-envelope.schema.json): shows the shared contract exists, but Dock/Archive `revision` is still optional.
- [scripts/dock-relay-projection-engine.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-projection-engine.mjs): correct owner for `projectionID`, `sourceRef`, and `displayOrderKey`.
- [scripts/dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs): `initialize` returns `relayInstanceID`, but not yet `sourceHostID` or `contractFingerprint`.
- [ThreadDetailStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadDetailStore.swift): current refresh replay can keep buffering during replay and wedge.
- [ThreadDetailDataEngine.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/ThreadDetail/ThreadDetailDataEngine.swift) and [ThreadCardTable.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardTable.swift): both enforce pieces of the same projection law, but separately.
- [ClientRuntime.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Runtime/ClientRuntime.swift): still constructs old stores, so runtime cutover is not complete.

**Canonical Owners**
- New doc: `docs/CODEX_DOCK_CANONICAL_CLIENT_PROJECTION_RUNTIME_ARCHITECTURE_2026-06-02.md`.
- Contract owner: `contract/projection/**`; `contract/dock/**` should stay compatibility-only or disappear.
- Relay owner: `scripts/dock-relay-projection-engine.mjs`, with `dock-relay-state-*` and `dock-relay-thread-detail-ledger.mjs` as adapters/ledgers.
- Swift runtime owner: `CodexDock/Runtime/ClientRuntime.swift`.
- New Swift shared core: `CodexDock/Projection/**`, because `ThreadCardTable` and `ThreadDetailDataEngine` duplicate the same apply law today.

**Old Paths To Retire**
- `logicalHostID` as visible identity; keep only as a temporary alias/action helper.
- `HostScopedThreadID` as row identity; row identity is `projectionID`.
- Raw display routes in Swift production display: `thread/read`, `thread/turns/list`, `thread/resume`.
- Unbounded `ThreadDetailLiveEventBuffer` replay.
- Acceptance-proof helpers that compute expected projection IDs locally.
- Optional Dock/Archive row `revision`.
- Simple `viewParamsKey` strings like `dock:<host>`; use canonical hashed view params.
- Runtime-facing `DockStore`, `ArchiveStore`, `ThreadDetailStore` as monoliths; final views should bind to screen stores backed by engines.

**Core Invariants**
- One identity owner: relay projection engine.
- One stream grammar: `snapshot`, `upsert`, `delete`, `heartbeat`, `resyncRequired`.
- One apply law: reject bad `sourceHostID`, `contractFingerprint`, `viewParamsKey`, `epoch`, `seq`, `projectionID`, `sourceRef`, `displayOrderKey`, or stale `revision`.
- One freshness rule: route health is never data freshness.
- One proof oracle: retained relay projection witnesses from the same proof run.

**Refresh, Catch-Up, Lifecycle**
Every refresh/resync needs a bounded generation. During catch-up, live updates after the cutoff must go into the next generation or apply after the snapshot, not refill the same replay buffer forever. If catch-up cannot finish inside its budget, the screen becomes `stale` or `reconnecting`; it never stays “live” with a stuck task.

Lifecycle should be runtime-owned: background pauses retries, foreground forces projection resync, and all root/detail streams use the same foreground gate.

**Testing Method**
- Instant tests: projection engine golden/property tests, Swift `ProjectionTableTests`, stale revision tests, duplicate source tests, null timestamp ordering tests, and deterministic catch-up stress tests.
- Simulator proof: `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'`, `rtk make sim-ui-sync-proof SIM='iPhone 17'`, and `rtk make sim-ui-dump SIM='iPhone 17'`.
- Device proof: `rtk make device-install DEVICE=<udid>` or repo device targets; only relay-backed `:4510` phone behavior counts.
- Long-running detection: a soak harness that records relay witnesses, Swift state, UI accessibility dumps, lag budgets, stale duration, and crash/log evidence over minutes, not one static sample.

**Rejected Alternatives**
- Swift dedupe patches: hide drift after it already happened.
- Local timestamp sorting: creates a second ordering owner.
- Optimistic/pending visible rows: adds another identity lifecycle.
- One giant universal store: overbuilt; the key is one shared apply law.
- Screenshots as proof: not machine-checkable enough.
- Raw `:4500` phone path: wrong security and wrong product path.

**Risks / Open Questions**
- Whether to keep route names like `dock/subscribe` and `thread/detail/subscribe` as wrappers, or move to generic `projection/subscribe`. I prefer keeping route names and enforcing one envelope.
- Exact `contractFingerprint` contents.
- Migration cost for Dock/Archive `revision`.
- How strict to make witness schemas without hurting debug usefulness.

**Need From Other Model**
I want Opus to challenge three points: whether route names can stay view-specific, whether one shared apply core is enough versus a single generic table, and whether any side door remains that I missed in proof scripts or runtime construction.