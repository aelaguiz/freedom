# Dock Latest Activity Plan Audit

Date: 2026-06-05

Plan under audit:

```text
docs/DOCK_LATEST_ACTIVITY_NORTH_STAR_2026-06-05.md
```

## Inputs Reviewed

- `README.md`
- `Makefile`
- `package.json`
- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-thread-summary-cache.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-store.mjs`
- `scripts/dock-relay-state-views.mjs`
- `scripts/dock-relay-card-contract.test.mjs`
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.mjs`
- `CodexDock/AppServer/DockThreadCardDTO.swift`
- `CodexDock/State/AppServerThreadCardStreamClient.swift`
- `CodexDock/State/ThreadCardRowProjector.swift`

Runtime proof reviewed:

```text
The exact Dock activity-proof path already receives summary-view
thread/turns/list rows with extractable userMessage / agentMessage text in
286/290 sampled real Dock rows.
```

## Iteration 1 Verdict

Verdict: not-ready

Blocking issues:

- The original plan had two summary paths: existing activity proof plus
  `ThreadSummaryCache`. That violated the requested clean unified architecture.
- The original plan treated `ThreadSummaryCache` as a fallback even though the
  real-data probe showed normal rows already carry extractable message text.
- The original plan did not explicitly require removal of dormant cache code, so
  the implementation could leave a second inactive source of truth.
- The original plan did not define the exact existing card fields that must
  carry the summary to Swift.

## Fixes Applied To Plan

- Made Plan B the only implementation path.
- Rejected Plan C for this fix.
- Required latest-summary extraction inside `readNewestTurnActivity`.
- Required the canonical row to carry `latestSummary`, `displaySummary`, and
  `summarySource:"latest_summary"` when a latest message is proven.
- Required no extra normal-path route beyond the existing activity proof
  `thread/turns/list` call.
- Required no global detail subscriptions and no full transcript cache.
- Required retiring the unused `ThreadSummaryCache` class/factory.
- Added test requirements for helper behavior, card contract behavior, route
  count, and simulator proof.

## Iteration 2 Verdict

Verdict: ready

Why it passes:

- Scope is relay-only unless tests prove otherwise.
- The source of truth remains `RelayStateEngine.reconcileDock` ->
  `canonicalizeThreadRows` -> `normalizeThread` -> `dock/update`.
- The plan uses data already read for card activity proof.
- The app-facing contract remains `DockThreadCardDTO.displaySummary` and
  `DockThreadCardDTO.summarySource`.
- The plan removes the unused cache path instead of adding a second path.
- The test plan covers pure extraction, card projection, stale fallback, route
  count, and simulator-visible Dock behavior.

Open risk:

- If a future Codex app-server build stops returning summary item text in
  `itemsView:"summary"`, rows will fall back to existing preview/title text.
  That is acceptable for this fix because the current verified server data
  already contains the needed text, and the design does not lie when text is
  absent.
