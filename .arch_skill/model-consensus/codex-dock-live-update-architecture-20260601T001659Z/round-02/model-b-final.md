✅ I converge with Claude on the main direction: the lean answer is to make the existing live proof harness mandatory, scheduled, drift-gated, and retained. Do not build a new framework.

**Agreements**
- Use one canonical data path: app-server → relay `:4510` → Swift client → rendered UI.
- Make these first-class rules: live failures fail closed, older snapshots cannot overwrite newer state, and Archive mutations explicitly reconcile Archive.
- Make heartbeat real. It is already in schema, Swift, tests, and README, but the relay does not emit it.
- Scope `itemsView:"full"` to Thread Detail history only. Keep it off relay card-order proof calls.
- Use the minimal drift gates Claude named: route registry/dispatch parity, schemaVersion/DTO parity, executable doc-command gate, proof-result schema gate, plus current contract checks.

**Disagreements**
- Claude slightly overstates “harness exists in full.” The harness exists, but it has enforcement holes.
- Biggest example: `--turn-items-view` exists in [scripts/dock-relay-sync-audit.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-sync-audit.mjs:91), but the actual detail `thread/turns/list` request does not send `itemsView` at [scripts/dock-relay-sync-audit.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-sync-audit.mjs:1490).
- Proof JSON has `schemaVersion`/`kind`, but I found no proof-result JSON schema file. So “proof-result schema gate” is needed, not already done.

**Repo Evidence**
- Existing proof targets are real: [Makefile](/Users/aelaguiz/workspace/codex-client/Makefile:259), [Makefile](/Users/aelaguiz/workspace/codex-client/Makefile:280), and `test:relay` in [package.json](/Users/aelaguiz/workspace/codex-client/package.json:10).
- UI proof is opt-in and skips without `/tmp/codex-client/codex-dock-sim-ui-sync-config.json`: [CodexDockDisplayedSyncProofTests.swift](/Users/aelaguiz/workspace/codex-client/CodexDockUITests/CodexDockDisplayedSyncProofTests.swift:155).
- Docs have drifted: the runbook uses unsupported `--exhaustive`: [CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md:73). The parser throws on unknown flags: [scripts/dock-relay-sync-audit.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-sync-audit.mjs:367).
- Live endpoint failures are counted, then ignored by Dock freshness: [dock-relay-thread-data.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:579), [dock-relay-state-engine.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-engine.mjs:487).
- `stateGeneration` is on the wire, but Swift snapshots overwrite state without checking it: [DockThreadCardDTO.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/DockThreadCardDTO.swift:444), [ThreadCardTable.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ThreadCardTable.swift:82).
- Archive mutation currently schedules generic Dock reconciliation, not Archive reconciliation: [dock-relay-state-ingest.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-ingest.mjs:21), [dock-relay-state-engine.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-engine.mjs:142).
- Heartbeat is claimed by schema/README/Swift tests, but relay core has no heartbeat emitter: [dock-thread-card.schema.json](/Users/aelaguiz/workspace/codex-client/contract/dock/dock-thread-card.schema.json:18), [README.md](/Users/aelaguiz/workspace/codex-client/README.md:123), [DockStoreStreamTests.swift](/Users/aelaguiz/workspace/codex-client/CodexDockTests/DockStoreStreamTests.swift:236).
- App-server supports `itemsView` and defaults missing requests to summary: [/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs](/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs:1174), [/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs](/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs:2244).

**Revised Proposal**
Use Claude’s three principles plus my original seven architecture rules. Add three mandatory corrections: live-failure-fails-closed, snapshot generation guard, explicit Archive reconcile.

Testing should be six existing tiers, not a new framework: contract, Swift unit, relay integration, real relay soak, simulator displayed-UI matrix, physical phone proof. The new work is enforcement: CI-safe gate, path-based mandatory simulator proof for update-path changes, scheduled soak/matrix, retained JSON reports, and drift gates.

The doc deliverable should be:
`docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`

**Sign-Off**
✅ I am ready to sign off on this architecture and testing methodology.

Smallest remaining detail is not architectural: pick exact heartbeat cadence and timeout. The rule is already clear: heartbeat must prove stream liveness without ever marking failed data fresh.