✅ I would converge on Model A as the base, with three corrections: keep the UI judge as a sibling script, do not call passive real-home lag proof complete, and do not claim full lazy-list UI equality on every fast sample.

**Agreements**
- Use the existing `scripts/dock-relay-sync-audit.mjs` report as relay/client-route truth.
- Use `CodexDockUITests` and the `iPhone 17` simulator accessibility tree as the literal UI proof surface.
- Do not set `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`; that activates scripted streams.
- Screenshots/logs are diagnostics only, not completion proof.
- UI lag must fail while visible, not pass because it eventually catches up.

**Disagreements**
- **Sibling script vs extending sync audit:** sibling wins. Keep `dock-relay-sync-audit.mjs` as the truth library and add `scripts/dock-relay-simulator-ui-sync-proof.mjs` or similar as the XCTest orchestrator/judge.
- **Lazy list proof:** no full-list proof every sample. Fast samples should cover watched visible rows; stable checkpoints should do bounded scroll/search sweeps plus root row-count checks.
- **Passive real-home:** not enough for completion. It is useful smoke evidence, but completion needs deterministic scenario actuation or at least a real observed relay transition.
- **UI lag timing:** use accessibility interval samples joined to `t_relay_seen`. Do not rely on `sample.finishedAt` if a finer relay event log is available.
- **Instrumentation:** current AX values are enough for structural proof. Add hash/length-only fields only for title/summary/body exactness.

**Repo Evidence**
- Phase 6 requires literal `iPhone 17` rendered UI over time: [plan](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md:1239).
- Scenario actuators are still incomplete: [implementation log](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md:36).
- Existing audit exports reusable truth/lag helpers: [dock-relay-sync-audit.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-sync-audit.mjs:2136).
- Dock root exposes row count/lens/filter state: [DockView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockView.swift:786).
- Dock row AX value exposes host/thread/status/origin/pin: [DockSharedViews.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Dock/DockSharedViews.swift:271).
- Detail AX exposes host/thread/live/events: [SessionDetailView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Session/SessionDetailView.swift:125).
- Message/request cards expose structural IDs/status: [ThreadMessageListView.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Features/Session/ThreadMessageListView.swift:295).

**Revised Proposal**
1. Add `CodexDockDisplayedSyncProofTests.swift` in `CodexDockUITests`.
2. Add a Makefile target like `rtk make sim-ui-sync-proof SIM='iPhone 17'`.
3. Run existing relay audit and UI sampler concurrently against the same relay-backed host path.
4. Add a small relay event log if needed for `t_relay_seen`.
5. Judge UI samples against relay truth by `logicalHostID + threadID`.
6. Fail on UI missing row, duplicate row, wrong status/order/host/archive/stale state, wrong detail thread, wrong event/request structure, or UI lag over budget.
7. Treat passive real-home as preflight; use deterministic scenarios for final completion.

**Sign-Off**
I’m ready to sign off on that revised design. Net: Model A’s proof model is stronger; Model B’s sibling-orchestrator shape keeps it lean.