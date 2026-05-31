✅ My design: add a small **simulator UI proof leg** that augments the existing relay sync report. Do not create a second oracle; use `scripts/dock-relay-sync-audit.mjs` as the truth report, and add an `iPhone 17` XCTest UI sampler that records what the app literally exposes through the accessibility tree over time.

**Proposed Harness**
- New orchestrator: `scripts/dock-relay-simulator-ui-sync-proof.mjs`
  - runs the existing relay/client-route audit;
  - runs the real `iPhone 17` UI proof through Makefile-owned XCTest;
  - merges both reports and fails on UI mismatch or UI lag.
- New UI test: `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`
  - launches the real app with `CODEX_DOCK_HOSTS`;
  - must not set `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`;
  - samples `XCUIApplication` accessibility state every ~500 ms;
  - writes sanitized UI samples under `/tmp/codex-client/...`.
- New Makefile target, not raw `xcodebuild`:
  - `rtk make sim-ui-sync-proof SIM='iPhone 17'`

**Evidence Read**
- [plan](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md): Phase 6 requires literal `iPhone 17` displayed UI over time.
- [implementation log](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md): relay/client-route proof exists; simulator UI proof is missing.
- [Makefile](/Users/aelaguiz/workspace/codex-client/Makefile): simulator builds/tests are Makefile-owned.
- [project.yml](/Users/aelaguiz/workspace/codex-client/project.yml): `CodexDockUITests` already exists.
- [AutomationID.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Automation/AutomationID.swift): stable row/detail/message/request IDs already exist.
- [dock-relay-sync-audit.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-sync-audit.mjs): current report has `samples[*].freshDock`, stream lag, route counts, and detail probes.
- [DockSharedViews.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockSharedViews.swift): current row values are useful but too thin for exhaustive UI proof.

**Invariants**
- Dock row key: `logicalHostID + threadID`.
- UI must show expected row count, no duplicate row IDs, correct visible order, status, host, source/origin, pinned/local state, stale/offline state.
- Detail tap must open `codexdock.session.root.<threadID>` for the tapped row.
- Detail header must match host/thread/live/status.
- Message/request UI must match expected event/request IDs and order.
- `lag_route_to_ui_ms` must stay within `maxStreamLagMs`, default `2000`.
- Two consecutive UI samples must match before calling a state stable.

**UI Observation**
Use the accessibility tree as the proof surface:
- Dock root: `codexdock.dock.root`
- Rows: `codexdock.dock.row.<host>.<thread>`
- Detail root: `codexdock.session.root.<thread>`
- Header: `codexdock.session.header`
- Messages: `codexdock.session.message.<eventID>`
- Requests: `codexdock.session.request.<cardID>`

Need one small instrumentation slice: add sanitized fingerprints to row/detail accessibility values for visible title/summary/body-like fields. Do not write prompt text, transcript text, raw summaries, or raw message bodies.

**Correlation**
The merged report should key UI samples to relay audit samples by:
- `auditSampleIndex`
- `freshDock.seq`
- `freshDock.epoch`
- `logicalHostID`
- `threadID`

Lag is measured as:

```text
lag_route_to_ui_ms = first_matching_ui_sample_at - relay_sample_finished_at
```

For controlled scenarios later, use the plan’s fuller timing: `t_change`, `t_relay_seen`, `t_dock_seen`, `t_detail_seen`, `t_stable`.

**Implementation Slices**
1. Add sanitized UI fingerprint helpers and richer accessibility values.
2. Add `CodexDockDisplayedSyncProofTests.swift`.
3. Add the Node correlator/orchestrator.
4. Add `rtk make sim-ui-sync-proof SIM='iPhone 17'`.
5. Add focused tests for parser/correlation logic.

Proof command shape:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make sim-ui-sync-proof SIM='iPhone 17'
```

**Rejected**
- ❌ Screenshot-only proof: too weak and hard to compare.
- ❌ Scripted UI transports: explicitly disallowed.
- ❌ Direct `ws://127.0.0.1:4500`: raw app-server path, not app path.
- ❌ New relay truth collector: duplicates `dock-relay-sync-audit.mjs`.

**Need From Model A**
I want Model A to challenge two points: whether the UI sampler must scroll the full lazy list on every sample, and whether the first implementation should extend `dock-relay-sync-audit.mjs` directly or keep the simulator orchestrator separate. My vote is separate orchestrator, full-list sweep only at stable checkpoints, fast lag checks on watched visible rows.