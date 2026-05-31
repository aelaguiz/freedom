Net: **not ready**. The current plan has the right main idea, but it still leaves places where old truth can survive: bounded recency, HTTP diagnostics, audit/probe scripts, Thread Detail proof bleed, archive mutations, and fake/scripted fixtures.

**Blocking Repairs**

- ❌ **Bounded latest-turn scan still allows mis-ordering.**  
  Evidence: the plan limits turn reads to live/top-N candidates, then explicitly accepts an outside-window mis-rank in [the plan](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:108) and [Known Residual Gap](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:282).  
  🔧 Repair: delete the residual gap. A Dock/Archive stream may claim `fresh` newest-first only when canonical activity is proven for every emitted candidate set, or when there is a real upper-bound proof that unscanned rows cannot outrank emitted rows. Since `thread/list.updatedAt` is proven stale, it is not an upper bound. Otherwise mark host/list freshness as stale/incomplete/uncertain and do not present it as fresh newest-first.

- ❌ **HTTP diagnostics still expose alternate state surfaces.**  
  Evidence: `/statez`, `/syncz`, `/dbz`, `/explainz/thread/{threadID}`, `/selftestz`, and `/bundlez` read relay state or passive Dock state in [dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:895), [runtimeSnapshot](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:585), and [selftest](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:668).  
  🔧 Repair: add an HTTP disposition table. Keep only process/route health public. Delete or strip state/card/freshness explainers so no HTTP endpoint can prove Dock/Archive ordering, card contents, completeness, or freshness.

- ❌ **Audit/probe scripts still teach the old oracle pattern.**  
  Evidence: `scripts/dock-relay-sync-audit.mjs` says oracle reads include `relay/state/snapshot`, SQLite, `thread/list`, and `thread/search` in [sync-audit](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-sync-audit.mjs:5052). `scripts/dock-relay-state-parity.mjs` calls `relay/state/snapshot`, `thread/read`, and `thread/search` in [state-parity](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-parity.mjs:2740). `scripts/dock-relay-probe.mjs` compares relay and history `thread/list` in [probe](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-probe.mjs:22).  
  🔧 Repair: rewrite proof scripts so Dock/Archive proof uses only `dock/subscribe`, `dock/update`, `dock/resync`, `archive/subscribe`, `archive/update`, and `archive/resync`. Raw upstream calls are allowed only inside controlled fixture servers behind the relay.

- ❌ **Thread Detail routes are not route-scoped tightly enough.**  
  Evidence: the plan keeps `thread/read`, `thread/turns/list`, and `thread/resume` in [Endpoint Disposition](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:89), but its proof ban omits them in [Phase 4](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:232). The audit script records them as detail proof in [sync-audit](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-sync-audit.mjs:1595).  
  🔧 Repair: add a hard rule: these routes may prove Thread Detail only after a Dock/Archive card is selected. They never prove Dock/Archive ordering, freshness, completeness, summary, or list membership.

- ❌ **Archive commands are card-affecting but skipped by the plan table.**  
  Evidence: `thread/archive` and `thread/unarchive` call `handleArchiveMutation` in [dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:493). That path directly updates SQLite order/freshness in [applyArchiveMutation](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-state-store.mjs:806).  
  🔧 Repair: keep the user command, but make archive/unarchive a projection input, not a separate card truth writer. The emitted Dock/Archive delta still comes from the same canonical projection state and must carry uncertain freshness until upstream confirmation is folded.

- ❌ **Fixtures and DEBUG scripted streams can preserve fake fresh truth.**  
  Evidence: `ScriptedDockStreamClient` emits `fresh` snapshots with fake cards in [ScriptedDockStreamClient.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/ScriptedDockStreamClient.swift:34), selected by env var in [CodexDockBootstrapView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/CodexDockBootstrapView.swift:119). Test fixtures still model raw query scopes through `ThreadCardFixtureQuery` in [DockStoreTestSupport.swift](/Users/aelaguiz/workspace/codex-client/CodexDockTests/DockStoreTestSupport.swift:12).  
  🔧 Repair: fixtures/previews/scripted streams may test rendering and reducer behavior, but they must use canonical `DockThreadCardDTO` semantics and never count as freshness/order proof.

**Final Architecture**

One path: raw `thread/list`, raw `thread/read`, raw `thread/turns/list`, live status, session-index IDs, and archive command outcomes fold inside one relay projection. That projection writes one stored card row and emits only `dock/*` and `archive/*` card streams. Swift renders those streams and may filter/search/group, but it does not invent or repair card truth.

**Proof Rules**

- No Dock/Archive correctness proof through `thread/list`, `thread/search`, `thread/goal/get`, `thread/loaded/list`, `thread/read`, `thread/turns/list`, `relay/state/snapshot`, `state/query`, SQLite, `/statez`, `/syncz`, `/dbz`, `/explainz`, `/selftestz`, or scripted fixtures.
- Contract checks may validate schema shape, but semantic recency must be tested through relay projection and card streams.
- A “fresh” list must prove canonical activity for its emitted ordering set. Unknown means stale/incomplete, not fresh.

**Residual Risk**

The only real residual risk after repair is cost: proving canonical activity for a large history may be slower. That is acceptable only if the UI exposes uncertainty until the proof completes.

**Evidence Read**

Read: the goal brief, implementation plan, current plan audit, source audit, relay route handler, relay projection/store/thread-data paths, audit/probe scripts, Swift app methods, diagnostics, metadata, row projector, stream collector, fixtures, scripted client, README, and package test wiring.