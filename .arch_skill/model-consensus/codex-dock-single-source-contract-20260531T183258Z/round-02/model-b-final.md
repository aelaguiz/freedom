✅ Convergence answer: Model A and I agree on the owner and direction. The final plan should use a narrow hybrid: canonical latest-turn scan during relay projection, plus live-event triggers that re-run the same projection for touched threads.

**1. Agreement**

- Canonical owner: relay card projection, not Swift. The owner path is `scripts/dock-relay-state-engine.mjs` + `scripts/dock-relay-state-views.mjs`, persisted through `scripts/dock-relay-state-store.mjs`, emitted only as `dock/*` and `archive/*`.
- Shape owner stays `contract/dock/dock-thread-card.schema.json` + generated `CodexDock/AppServer/DockThreadCardDTO.swift`.
- `activityAtMs`, `activityAt`, `orderKey`, `displaySummary`, card `status`, and freshness must be computed once before storage/emission.
- Active Dock must stop using ordinal `dockOrderKey`; use an activity-derived key like Archive.
- Swift must become render-only for card truth. `DockCardProjection.swift` should stop sorting by locally parsed `lastActivityDate` as the primary authority once relay `orderKey` is canonical.
- `thread/list`, `state/query`, `relay/state/snapshot`, and related oracle/test paths must not remain as proof paths.
- Cached pinned display cannot remain a second card-data source.
- Tests must prove behavior through `dock/subscribe`, `dock/update`, `dock/resync`, `archive/subscribe`, `archive/update`, and `archive/resync`.

**2. Tightening Model A**

Model A is right on direction, but these points need tightening:

- Do not start with a full incremental turn/live ingestor as a new subsystem. That is too much architecture and risks becoming a second source of truth.
- Do not delete all diagnostics blindly. Delete raw app-facing card/data side doors; retain process/health diagnostics that do not return alternate card truth.
- Make `activityAtMs` required only after the relay always emits it. Use a short compatibility phase: relay emits canonical `activityAtMs` first, then schema/DTO require it.
- Keep relative-time UI formatting in Swift. Delete Swift value derivation as card truth, not the display formatter itself.
- Live leases should stay status-only, but the overlay must happen inside the canonical projection/emission path, not as an independent read-time truth layer.

**3. Strategy Choice**

Pick the hybrid, but keep it narrow.

Implementation path:

1. `readCanonicalDockThreadRows(...)` in `scripts/dock-relay-thread-data.mjs` becomes the only place raw list/read/turn/live/session-index inputs collapse into card facts.
2. During `reconcileDock` and `reconcileArchive`, the relay fetches bounded latest turn facts via `thread/turns/list` with `sortDirection: "desc"` and named constants in `scripts/dock-relay-constants.mjs`.
3. For live events, do not build a separate event store. When the relay observes a live turn/status/request event or `turn/start` / `turn/steer` / `turn/interrupt`, schedule a per-thread canonical refresh that calls the same projection path.
4. The stored `threads` row remains the only client source.

Net: latest-turn scan repairs stale persisted/history rows; live triggers reduce lag without creating another authority.

**4. Raw Diagnostic Routes**

Delete raw app-facing side doors from downstream JSON-RPC:

- `thread/list`
- `thread/search`
- `thread/goal/get`
- `thread/loaded/list`
- `relay/state/snapshot`
- `state/query`

Keep internal helper functions where relay code needs them. Tests must not call those routes to prove Dock correctness.

Retain only diagnostics that do not create alternate card truth:

- `/readyz`, `/healthz`, `/statusz`, `/routesz`, `/metricsz`, traces: retained.
- `/statez`, `/syncz`, `/dbz`, `/explainz/thread/{threadID}`: either remove card-like fields or hide behind explicit internal/dev enablement. No production app path and no contract tests should rely on them.

**5. Cached Pinned Display**

Delete fabricated pinned card data.

Keep:

- `label`
- `rail`
- `isPinned`
- `pinnedAt`
- `pinnedOrder`
- identity keys

Remove or stop writing:

- `LocalPinnedDisplaySnapshot`
- `lastKnownPinnedDisplay`
- title/status/activity/summary/repository/branch as local fallback truth

Pinned missing rows may still show as placeholders, but they must be clearly degraded and must not claim current activity/status/summary.

**6. Final Phases And Gates**

Phase 1: canonical relay projection

- Add `readCanonicalDockThreadRows(...)` in `scripts/dock-relay-thread-data.mjs`.
- Fold `thread/list`, `thread/read includeTurns:false`, `thread/turns/list`, live row facts, and session-index IDs into one canonical row object.
- Make session-index ID-only.
- Add bounded latest-turn constants.

Gate:

- `rtk npm run test:relay`

Phase 2: relay storage and ordering

- Update `scripts/dock-relay-state-views.mjs` so `normalizeThread` consumes canonical facts only.
- Replace active `dockOrderKey` with activity-derived order.
- Store canonical `activityAtMs` in `threads`.
- Make lease overlay status-only and applied before stream emission.
- Expired lease falls back to projected status, never stale `running`.

Gate:

- `rtk npm run test:relay`
- `rtk npm run contract:check`

Phase 3: remove app-facing side doors

- Remove downstream JSON-RPC route cases in `scripts/dock-relay.mjs`.
- Rewrite tests that call `state/query`, `relay/state/snapshot`, or raw list/search/goal/loaded routes for card proof.
- Internal relay helpers stay internal.

Gate:

- `rtk npm run test:relay`

Phase 4: Swift render-only cleanup

- Remove raw `AppServerClient.threadList` and related `ThreadListDTO` tests if no production caller remains.
- Remove `thread/list` from Dock feed health in `CodexDock/Diagnostics/ObservabilityContract.swift` and `CodexDock/Features/Status/SystemHealthProjector.swift`.
- Make `DockCardProjection.swift` sort by relay `orderKey`.
- Use required `activityAtMs` for display date after compatibility phase.
- Remove cached pinned display as card truth.
- Prefer one stream reducer: move Archive/Cleanup away from loose collector behavior if it duplicates `ThreadCardTable`.

Gates:

- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`

Phase 5: contract tighten and docs

- Make `activityAtMs` required in `contract/dock/dock-thread-card.schema.json`.
- Regenerate DTOs with `rtk xcodegen generate --spec project.yml` only if project wiring changes; otherwise run contract generation/check per package scripts.
- Add in-code invariant comments in projection, store, schema field descriptions, and Swift render path.
- Update README to say turn-aware projection may happen in relay reconcile, but Swift still only consumes `dock/*`.

Final gate:

- `rtk npm test`
- `rtk swift test`
- If UI behavior changed: `rtk make app-test SIM='iPhone 17'`

Net: one canonical projection, one stored card, one stream contract, no raw route tests masquerading as app proof.