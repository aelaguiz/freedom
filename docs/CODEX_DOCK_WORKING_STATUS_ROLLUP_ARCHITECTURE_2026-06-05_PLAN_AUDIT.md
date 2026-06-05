# Plan Audit: Codex Dock Working Status Rollup Architecture

Plan:
`docs/CODEX_DOCK_WORKING_STATUS_ROLLUP_ARCHITECTURE_2026-06-05.md`

Audit mode: plan-readiness
Last audit: 2026-06-05
Verdict: ready

## Code Read

- `scripts/dock-relay-human-thread-filter.mjs`
- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-state-views.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-store.mjs`
- `scripts/dock-relay-state-store-human-filter.mjs`
- `scripts/dock-relay-app-server-registry.mjs`
- `scripts/dock-relay-card-contract.test.mjs`
- `scripts/dock-relay-app-server-registry.test.mjs`
- `scripts/dock-relay-state-subscriptions.test.mjs`
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-sync-audit.mjs`
- `CodexDock/Dock/DockModels.swift`
- `CodexDock/State/ThreadCardRowProjector.swift`

## Parallel Agent Inputs

- Relay review found the app-visible status is relay-owned and Swift only
  renders the DTO status it receives.
- Relay review confirmed `privateUnattachable` is internal and normalizes to
  `unknown`.
- Local code read found hidden spawned rows are currently discarded by
  `readLoadedRows()` / `mergePrivateLiveRows()` before `orderedDockRows()` can
  roll them up.
- Local code read found `orderedDockRows()` only overlays same-thread-ID live
  rows.

## Blocking Findings

None.

## Repairs Already Made To The Plan

- The plan explicitly keeps Swift unchanged.
- The plan distinguishes hidden spawned/private child rollup from root private
  owner false positives.
- The plan requires first-snapshot overlay, not only reconciliation-time store
  writes.
- The plan now requires a dedicated
  `spawned-private-child-status-rollup` controlled simulator scenario instead
  of relying on `spawn-edge` plus `server-status-notification` as separate
  partial proofs.
- The plan keeps child rows hidden and detail route rejection intact.
- The plan names exact owner files and required tests.

## Readiness Checklist

- North Star clear: yes.
- Done state concrete: yes.
- Existing owner paths named: yes.
- Side doors named: yes.
- Non-requirements named: yes.
- Depth-first implementation possible: yes.
- Tests tied to behavior: yes.
- Known ambiguity captured: yes. Root private owner presence alone must not
  become global `running`.
- Plan avoids duplicate source of truth: yes. Relay remains the status owner;
  Swift remains a renderer.

## Verdict

Ready.

The plan is specific enough to implement without guessing the product behavior:
hidden child activity may update the visible parent status, but hidden children
stay hidden and root private owner presence is not a blanket badge shortcut.
