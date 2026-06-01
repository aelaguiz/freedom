✅ My recommendation: make the relay the only production data owner, and make every live subscription/session rebuild itself whenever its identity changes. A socket being “connected” must never count as proof that Dock cards or Thread Detail are fresh.

**Proposed Architecture**
1. Phone talks only to Dock relay `:4510`; raw app-server `:4500` stays Mac-side.
2. Dock and Archive card truth comes only from relay `dock/*` and `archive/*`.
3. Relay owns card freshness, completeness, order, human filtering, and SQLite projection.
4. Swift renders relay `orderKey`; local metadata can only decorate rows.
5. Thread Detail always follows one path: `thread/read includeTurns:false` → full paged `thread/turns/list` → `thread/resume excludeTurns:true`.
6. No silent reconnects for stateful paths. If Dock, Archive, or Detail loses a stream/session generation, the missing state must be rebuilt.
7. For Thread Detail, the leanest rule is: if relay loses and recovers the upstream `thread/resume` session, close the downstream phone socket unless app-server gives a proven replay guarantee. Swift already knows how to rehydrate after a visible reconnect.

**Ongoing Test Method**
Use five tiers, and do not let lower tiers replace higher tiers:

1. Contract checks: `rtk npm run contract:check`, plus drift checks tying schema, Swift DTOs, relay allow-list, and docs together.
2. Swift unit tests: keep fake-stream tests for merge, resync, pagination, request cards, stale UI, and edge cases.
3. Relay integration tests: fake app-server + real relay, proving real `dock/update`, `archive/update`, `dock/resync`, multi-subscriber, delete-only delta, archive mutation, and upstream recovery behavior.
4. Real relay soak: `scripts/dock-relay-sync-audit.mjs` must compare long-lived stream state against fresh client-path snapshots over time and fail on lag over budget.
5. Simulator/phone proof: `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' ... SIM_UI_CONTROLLED_MATRIX_PASSES=2 MAX_UI_LAG_MS=2000`, then physical phone proof when claiming phone completion.

**Owner Paths**
- Card contract: `contract/dock/dock-thread-card.schema.json`, `scripts/generate-dock-thread-card-contract.mjs`, `scripts/check-dock-thread-card-contract.mjs`.
- Relay route allow-list: `scripts/dock-relay.mjs`.
- Swift route names: `CodexDock/AppServer/AppServerMethods.swift`.
- Relay card truth: `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-subscriptions.mjs`, `scripts/dock-relay-state-store.mjs`.
- Dock client: `CodexDock/State/AppServerThreadCardStreamClient.swift`, `CodexDock/State/DockStore.swift`, `CodexDock/State/ThreadCardTable.swift`.
- Detail client: `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/State/AppServerThreadDetailSession.swift`, `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`.
- Proof harness: `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-controlled-simulator-fixture.mjs`, `scripts/dock-relay-controlled-simulator-matrix.mjs`, `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, `Makefile`.

**Edge Cases To Require**
- Silent WebSocket reconnect without `dock/subscribe`.
- Relay upstream detail recovery with phone socket still open.
- Cold, empty, stale, or partial SQLite cache.
- Raw app-server down while relay process is up.
- Sequence gap, schema mismatch, epoch mismatch, large snapshot fallback.
- Partial windows and catch-up restart.
- Duplicate card IDs, missing `dock/update` params, stale compatible snapshots.
- Non-human row replacing an existing human row.
- Archive/unarchive updating both Dock and Archive views.
- Multi-host alias collisions.
- Repeated turn cursors, compact resume payloads, missing `threadId`, unknown live events.
- Server request stale generation and request-card resolution.
- Background/foreground rehydrate.
- `itemsView:"full"` for detail turn history, if app-server supports that enum.

**Side Doors To Close**
- Swift must not call phone-side `thread/list`, `thread/loaded/list`, `thread/search`, or `relay/state/*`.
- `/readyz`, `/statusz`, `/routesz`, `/metricsz`, and `/syncz` are diagnostics, not freshness proof.
- `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO` is fixture-only and cannot count as live proof.
- One-shot host tests cannot prove Dock Home’s existing stream.
- Local metadata cannot create rows or change freshness/order.
- Preview rows and static fixtures cannot be production evidence.
- Phone must not connect to raw `:4500`.

**Rejected Alternatives**
- Relying on snapshots/fixtures: catches merge bugs, misses over-time delivery bugs.
- Letting Swift infer recency from timestamps: creates a second card-truth path.
- Treating route health as data health: route success can coexist with stale cards.
- Adding a second relay state oracle route: creates drift beside `dock/*` and `archive/*`.
- Keeping detail upstream recovery invisible: this is the exact stale-detail failure shape.

**Documentation Deliverable Shape**
Create a new doc, likely:
`docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`

Keep it shorter than the audit doc and structure it as:
- canonical architecture;
- protocol owner map;
- forbidden side doors;
- update/session lifecycle rules;
- edge/exception matrix;
- required test tiers and exact commands;
- proof acceptance rules;
- rejected alternatives;
- drift maintenance rules.

**Evidence Read**
I inspected the goal, the existing 3,040-line architecture audit, the exhaustive sync runbook, relay code, Swift stores, DTOs, tests, Makefile targets, schema, and UI proof harness.

Key evidence:
- `DockStore` subscribes once and later uses `resync`, not resubscribe: `CodexDock/State/DockStore.swift:295`.
- Stream client ignores missing update params: `CodexDock/State/AppServerThreadCardStreamClient.swift:77`.
- `ThreadCardTable` enforces schema, epoch, sequence, window: `CodexDock/State/ThreadCardTable.swift:82`.
- Detail rehydrates only through visible reconnect/foreground paths: `CodexDock/State/ThreadDetailStore.swift:628`.
- Relay can recover upstream without closing phone until recovery fails: `scripts/dock-relay.mjs:338`.
- Relay allow-list is explicit: `scripts/dock-relay.mjs:448`.
- Relay protects subscribe-time buffering: `scripts/dock-relay-state-engine.mjs:683`.
- Current Swift `ThreadTurnsListParams` lacks `itemsView`: `CodexDock/AppServer/ThreadDetailDTO.swift:18`.
- Real UI proof removes scripted stream env: `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift:128`.
- Runbook already defines over-time proof and lag-budget failure: `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md:8`.

**Risks / Open Questions**
- Confirm the exact app-server enum for full detail history: likely `itemsView:"full"`, but this must be verified before documenting as final.
- Decide whether heartbeat is real contract or dead contract. Today schema/Swift know it; relay does not emit it.
- Decide whether Thread Detail upstream recovery should always close downstream, or emit a new explicit “rehydrate required” notification. My vote is close downstream because it is simpler and harder to drift.
- Archive mutation currently looks drift-prone because generic reconciliation calls Dock; Archive needs explicit proof.

**What I Need From Claude**
I need Claude to challenge these three decisions: close downstream on upstream detail recovery, require full `thread/turns/list` detail, and keep/remove heartbeat. If Claude agrees, the consensus doc can be written directly from this architecture.