✅ Model B plan: make `dock/*` and `archive/*` the only app-facing card contract, and make the relay build every card through one canonical projection path before SQLite. Raw `thread/list`, `thread/search`, `thread/goal/get`, `thread/loaded/list`, `state/query`, and `relay/state/snapshot` should stop being app-facing ways to prove or fetch Dock card truth.

**Canonical Owner**

The right owner is the relay card projection:

- Shape owner: [contract/dock/dock-thread-card.schema.json](/Users/aelaguiz/workspace/codex-client/contract/dock/dock-thread-card.schema.json:1) plus generated `DockThreadCardDTO`.
- Semantic owner: [scripts/dock-relay-state-engine.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-engine.mjs:252) and [scripts/dock-relay-state-views.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:312).
- Stored source for clients: [scripts/dock-relay-state-store.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:124), the `threads` table that backs `dock/subscribe`, `dock/update`, and `dock/resync`.

Why: Swift already consumes `dock/*` through [AppServerThreadCardStreamClient.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/AppServerThreadCardStreamClient.swift:95), and `ThreadCardTable` accepts only card stream updates by schema/version/sequence at [ThreadCardTable.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardTable.swift:82). The bug is not Swift rendering. The bug is that the relay projection currently chooses stale thread-level facts before storing the card.

**Implementation Plan**

1. 🔧 Add one canonical relay function in [scripts/dock-relay-thread-data.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:872), something like `readCanonicalDockThreadRows(config, { archived, scope })`.
   - It may use raw `thread/list`, `thread/read`, live routing, `thread/turns/list`, and session-index IDs internally.
   - It returns one normalized per-thread fact object. No caller gets to merge these sources differently.

2. 🔧 Make canonical card activity come from the newest real work.
   - Compute `activityAtMs` as the max of thread `activityAt`, `updatedAt`, `createdAt`, and newest turn timestamps from `thread/turns/list`.
   - Use `thread/turns/list` with `sortDirection: "desc"` and a named constant in `scripts/dock-relay-constants.mjs`.
   - Use the same `activityAtMs` for `activityAt` and `orderKey`.

3. 🔧 Replace active Dock ordinal ordering.
   - Current active `dockOrderKey` is list-index based at [scripts/dock-relay-state-views.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:182).
   - Replace it with one descending activity key shared by Dock and Archive, probably a renamed/generalized version of `archiveOrderKey`.
   - This preserves the README promise that Dock opens to newest activity at [README.md](/Users/aelaguiz/workspace/codex-client/README.md:143).

4. 🔧 Fold latest summary into the same projection.
   - Delete or absorb the unused async `ThreadSummaryCache` class in [scripts/dock-relay-thread-summary-cache.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-summary-cache.mjs:117).
   - Keep only a pure helper for “latest safe turn summary” if useful.
   - Do not keep a separate warming cache as a second truth path.

5. 🔧 Make live leases stop overriding stored cards at read time.
   - Current lease overlay mutates status/`backendSessionID` after storage at [scripts/dock-relay-state-views.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:384) and [scripts/dock-relay-state-store.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:558).
   - Instead, live status should feed the canonical projection before `upsertThreadCard`.
   - Lease expiry should schedule/recompute a canonical card update, not create a separate client-visible status source.

6. 🔧 Make session-index supplements ID-only.
   - Current supplement rows can bring `name` and `updatedAt` from `session_index.jsonl` at [scripts/dock-relay-thread-data.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:245).
   - Keep the UX of finding omitted human-started sessions, but only use session index to discover candidate IDs.
   - Display fields must come from `thread/read` plus canonical turn facts.

7. 🔧 Remove app-facing side-door routes.
   - Delete app-facing `handleRequest` cases for `thread/list`, `thread/search`, `thread/goal/get`, `thread/loaded/list`, `relay/state/snapshot`, and `state/query` in [scripts/dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:469).
   - Keep raw upstream helpers internal where the relay needs them.
   - Keep `thread/read`, `thread/turns/list`, and `thread/resume` because Thread Detail legitimately uses them at [ThreadDetailStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadDetailStore.swift:563).

8. 🔧 Remove Swift’s raw-list client surface.
   - Delete `AppServerClient.threadList` at [AppServerClient.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/AppServerClient.swift:279) if no production code needs it.
   - Remove `threadList` from app-critical Dock health in [ObservabilityContract.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Diagnostics/ObservabilityContract.swift:53) and [SystemHealthProjector.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Status/SystemHealthProjector.swift:91).
   - Keep diagnostics focused on `dock/subscribe`, `dock/update`, `dock/resync`.

9. 🔧 Rewrite local pinned fallback so it cannot become card truth.
   - [ThreadCardRowProjector.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardRowProjector.swift:61) currently uses cached pinned display fields.
   - Preserve pinned-row visibility, labels, rails, and pin order.
   - Do not let local metadata supply current title/status/activity/summary for loaded cards; missing pinned rows should look explicitly not loaded.

**Tests**

Delete or rewrite:

- `scripts/dock-relay.test.mjs` use of `state/query` in `dock/subscribe returns a normalized relay-owned session snapshot`.
- `scripts/dock-relay-phase5.test.mjs` tests that require `thread/list` to avoid turn warming:
  - `relay thread/list preserves history preview without warming turns`
  - `relay thread/list preserves history preview without warming live owner turns`
- `CodexDockTests/AppServerClientTests.swift` raw `threadList` tests at [AppServerClientTests.swift](/Users/aelaguiz/workspace/codex-client/CodexDockTests/AppServerClientTests.swift:1060), plus real-host `thread/list` smoke tests at [AppServerClientTests.swift](/Users/aelaguiz/workspace/codex-client/CodexDockTests/AppServerClientTests.swift:2207).
- Swift fixture-loader tests that model old query scopes through `ThreadCardFixtureQuery` in [DockStoreTestSupport.swift](/Users/aelaguiz/workspace/codex-client/CodexDockTests/DockStoreTestSupport.swift:12). Replace with direct `DockThreadCardDTO` stream fixtures.

Add:

- Relay test: stale `thread/read.updatedAt`, newer `thread/turns/list.startedAt`, card uses newer `activityAtMs`, summary, and order.
- Relay test: live-only human thread appears through canonical projection, not lease overlay.
- Relay test: session-index candidate contributes only ID; stale session-index `updatedAt` cannot win.
- Relay test: app-facing removed routes return unsupported method.
- Swift test: Dock health categories no longer treat `thread/list` as Dock-feed proof.
- Swift test: pinned missing row remains visible but is clearly not canonical current card data.

**In-Code Comments**

Add short comments in:

- `normalizeThread`: “Input must already be canonical card facts. Do not read raw thread/list, live lease, or local metadata here.”
- `readCanonicalDockThreadRows`: “This is the only place raw thread/list/read/turn/live/session-index facts collapse into a Dock card.”
- `applyDockReconciliation`: “Stored `threads` rows are the client card source; do not overlay live lease fields after storage.”
- `LocalThreadMetadata`: “Local metadata owns labels/pins/rails only, not current card activity, title, status, or summary.”

**Migration Order**

1. Add canonical projection and tests while old routes still exist.
2. Switch active Dock and Archive reconcile to canonical rows.
3. Move lease/session-index behavior into canonical projection.
4. Rewrite Swift tests and fixture helpers to use card stream DTOs only.
5. Delete app-facing side-door routes and raw Swift `threadList`.
6. Update README and audit docs so they say `dock/*` is the only card contract.
7. Run:
   - `rtk npm run test:relay`
   - `rtk swift test --filter AppServerClientTests`
   - `rtk swift test --filter DockStoreTests`
   - `rtk swift test --filter ThreadDetailStoreTests`
   - `rtk npm run contract:check`

**Rejected Alternatives**

❌ Schema-only fix: the schema enforces shape, not where `activityAtMs` came from.  
❌ Swift polling `thread/turns/list`: creates a second client-side card truth.  
❌ Keep `state/query` for tests: it bypasses stream sequencing and trains tests on the wrong path.  
❌ Background `ThreadSummaryCache` warming as truth: it is another cache with stale-version rules.  
❌ Keyword scans or lint rules: they do not prove runtime card freshness.

**Risks / Open Questions**

⚠️ Need confirm `thread/turns/list sortDirection: "desc"` guarantees newest turns first. If yes, first page is enough; if no, canonical projection must drain pages or the relay needs an upstream latest-turn field.

⚠️ Per-row turn reads can be expensive. Use a named concurrency cap and page limit in `dock-relay-constants.mjs`, not ad hoc values.

⚠️ Deleting JSON-RPC diagnostic routes will break local audit scripts. That is acceptable only if Model A agrees the goal means no app-facing diagnostic side doors, not merely no Swift side doors.

**Evidence Read**

I inspected the named audit, then verified the code paths it called out:

- Relay route split: [scripts/dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:459)
- Cached subscribe/reconcile behavior: [scripts/dock-relay-state-engine.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-engine.mjs:226)
- Thread-level timestamp/order projection: [scripts/dock-relay-state-views.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-views.mjs:162)
- `thread/read includeTurns:false` enrichment: [scripts/dock-relay-thread-data.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:640)
- Stored card table and lease overlay: [scripts/dock-relay-state-store.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:124)
- Swift card stream client/table/projector: [AppServerThreadCardStreamClient.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/AppServerThreadCardStreamClient.swift:95), [ThreadCardTable.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardTable.swift:82), [ThreadCardRowProjector.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardRowProjector.swift:27)
- Thread Detail’s valid separate path: [ThreadDetailStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadDetailStore.swift:563)
- README’s current, now-conflicting summary rule: [README.md](/Users/aelaguiz/workspace/codex-client/README.md:131)

**Need From Model A**

I need Model A’s view on three decisions:

1. Delete app-facing diagnostic routes entirely, or keep them but make them unable to produce card-like truth?
2. Use latest first `thread/turns/list` page as canonical, or drain all turn pages for perfect recency?
3. Strip cached pinned display down to a placeholder, or keep it only for explicitly stale “missing pinned row” UX?

Net: the lean fix is not another schema or validator. It is one relay projection path that folds raw list/read/turn/live facts once, stores that card once, and makes Swift consume only the card stream.