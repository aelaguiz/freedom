# Codex Dock Working Status Rollup Architecture

Status: Ready for implementation
Date: 2026-06-05
Scope: Relay-owned Dock card status rollup for hidden spawned/private Codex work
Non-scope: Swift UI inference, direct phone-to-`:4500` app-server routing, showing spawned child rows

## North Star

If real Codex work is active for a human-visible root thread, the Dock card for
that root thread must show the public status that Swift already knows how to
render, including `running`, `needsInput`, and `needsApproval`.

Hidden spawned/private child threads must remain hidden as rows. Their activity
is an internal relay fact that can update the visible parent card status.

## Current Failure

The relay has two separate ideas today:

1. Human-only row filtering keeps spawned/private child rows out of the app.
2. Live status overlay only works when the live row has the same thread ID as
   the visible row.

That means this real shape fails:

```text
Visible Dock row:
  parent-thread      status=idle        source=cli        app-facing=yes

Hidden live work:
  child-thread       status=active      parent=parent-thread
                    source=subagent    app-facing=no

Current app result:
  parent-thread      status=idle        no "Codex is working" badge

Required result:
  parent-thread      status=running     badge visible
  child-thread       not shown
```

## Code Ownership

Relay status ownership stays in Node:

- `scripts/dock-relay-human-thread-filter.mjs`
  owns human-vs-automation classification and parent identity from
  `thread_spawn.parent_thread_id`.
- `scripts/dock-relay-thread-data.mjs`
  owns live/private row collection and must preserve rejected child activity as
  non-visible rollup facts.
- `scripts/dock-relay-state-views.mjs`
  owns canonical row/card status folding before projection output.
- `scripts/dock-relay-state-engine.mjs`
  owns reconciliation, live cache snapshot overlay, and store writes.
- `scripts/dock-relay-state-store.mjs`
  stores only app-facing card truth.
- `CodexDock/**`
  must stay unchanged for this fix. Swift already renders `running` as
  `Codex is working`.

## Requirements

- A spawned child row with `status.type = "active"` rolls up to its visible
  parent as:
  - `waitingOnApproval` -> `needsApproval`
  - `waitingOnUserInput` -> `needsInput`
  - no waiting flags -> `running`
- A private spawned child owner with `thread_spawn.parent_thread_id` may roll up
  as `running` while the private owner proof is fresh, because the child row
  remains hidden and there is no attachable status channel.
- A root/private owner without spawned-child parent metadata must not globally
  force `running`; that path caused previous false-positive risk.
- Hidden child rows must never appear in `dock/subscribe`, `dock/update`, fresh
  Dock snapshots, or `thread/detail/subscribe`.
- The visible parent card must keep the parent's `threadID`,
  `backendSessionID`, route behavior, title, workspace, branch, and detail route.
- Rollup may update parent `status`, `activityAt`, `activityAtMs`, and
  `displayOrderKey`.
- When hidden activity disappears on the next reconciliation/snapshot refresh,
  the parent falls back to its own direct status.
- Store writes remain the source of truth for Swift; live cache snapshot overlay
  may provide the same rollup before the next scheduled reconciliation.
- No raw bearer tokens, prompts, transcripts, audio, or full JSON-RPC payloads
  may be logged.

## Non-Requirements

- Do not add a Swift-side rule like "if a child exists, infer running".
- Do not show spawned/private child rows as Dock cards.
- Do not add a new persisted rollup table unless tests prove the existing
  reconciliation/live-cache lifecycle cannot express the state.
- Do not make `privateUnattachable` a public status for every root row.
- Do not change physical iPhone endpoint config or make the phone use raw
  `:4500` app-server.

## Architecture

The relay should treat rejected child activity as an internal fact, not as a
card.

```text
App-server / process discovery
        |
        v
live rows + private rows
        |
        v
classifyThreadOrigin(row)
        |
        +--> allowed human root row
        |       |
        |       v
        |   normal Dock card candidate
        |
        +--> rejected spawned/private child row with parentThreadID
                |
                v
            hidden activity fact
            { targetThreadID: parentThreadID, statusProof, activityAtMs }
                |
                v
orderedDockRows / snapshot overlay
        |
        v
visible parent card status is folded before Swift receives it
```

The hidden activity fact is allowed to carry internal relay fields such as:

- `dockRelayRollupTargetThreadID`
- `dockRelayRollupStatus`
- `dockRelayRollupSource`

Those fields must not create a visible card and do not need to be part of the
Swift DTO.

## Status Precedence

When several facts target the same visible parent:

1. `needsApproval`
2. `needsInput`
3. `running`
4. parent's direct status (`idle`, `error`, `unknown`, `dormant`, or direct
   `running`)

Only active-ish child facts roll up. Hidden `idle`, `dormant`, `unknown`, and
unclassified child facts do not downgrade the parent.

If parent and child are both active-ish, the highest-priority public status wins.
If priorities match, the newest activity timestamp wins.

## Implementation Phases

### Phase 1: Preserve Hidden Activity Facts

Update `scripts/dock-relay-thread-data.mjs` so rejected rows with a real
`classification.parentThreadID` are not simply discarded.

Accepted rows still go to `rows`.

Rejected spawned/private child activity goes to `rollupRows` only when it has
active-ish proof:

- attachable live child: upstream `status.type = "active"`
- private spawned child owner: `status.type = "privateUnattachable"` plus
  `parentThreadID`

Rejected child IDs still feed the cleanup path so stale visible child cards are
removed.

### Phase 2: Fold Rollups Before Card Truth

Update `scripts/dock-relay-state-views.mjs` so `orderedDockRows()` can receive
hidden rollup rows and overlay active-ish status onto matching visible parents.

The overlay must not copy the child's `sessionId` to the parent. The parent card
must still route as the parent.

### Phase 3: Keep First Snapshots Honest

Update `scripts/dock-relay-state-engine.mjs` so fresh live-cache overlay applies
the same hidden rollups to stored cards before the first `dock/subscribe`
snapshot returns.

This avoids a window where the stream is correct only after the next scheduled
reconciliation.

### Phase 4: Controlled Proof

Add a dedicated controlled scenario:

```text
spawned-private-child-status-rollup
```

`spawn-edge` and `server-status-notification` are not enough by themselves:
they prove "child hidden" and "visible row can become running" separately. This
bug lives in the combined case where a hidden spawned/private child makes the
visible parent/root row `running`.

The new controlled scenario starts from the same shape as `spawn-edge`, then
adds active hidden child activity. The expected result is:

- child absent from Dock rows
- parent present
- parent status `running`
- detail subscribe to child rejected
- simulator-visible row uses the same relay-backed stream path

## Test Plan

### Contract Tests

Add or update `scripts/dock-relay-card-contract.test.mjs`:

- visible parent plus attachable spawned child:
  - parent status becomes `running`
  - child is absent
  - result is complete/fresh when upstream proof is complete
- spawned child waiting on approval:
  - parent status becomes `needsApproval`
  - child is absent
- spawned child waiting on user input:
  - parent status becomes `needsInput`
  - child is absent
- private spawned child owner:
  - parent status becomes `running`
  - private child is absent
- root private owner without parent metadata:
  - existing behavior does not become a blanket `running` false positive
- stale rejected spawned child cleanup still removes child cards.

### State/View Tests

Use existing state-view coverage where possible. Add focused tests only if the
contract tests cannot isolate precedence:

- hidden child `needsApproval` beats parent `running`
- hidden child `running` beats parent `idle`
- hidden child `unknown` does not downgrade parent
- child `sessionId` does not replace parent `backendSessionID`

### Registry Tests

Keep `scripts/dock-relay-app-server-registry.test.mjs` behavior that private
owners are route-private and not attachable through normal `thread/read`.

Do not require `normalizedStatus(privateUnattachable) === "running"` globally.
Private root presence is not enough to prove app-facing work.

### Controlled Simulator

Run the focused controlled simulator proof after implementation:

```bash
rtk make app SIM='iPhone 17' FORCE_LAUNCH=1
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=spawned-private-child-status-rollup
```

Expected proof:

- app connects to relay-backed `127.0.0.1:<fixture-port>`
- relay Dock stream shows parent `running`
- simulator UI has the parent row and not the child row
- no stale `partial 2/2` state is required for the badge

Also add the scenario to the duplicated scenario owners:

- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-controlled-simulator-fixture.test.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.test.mjs`
- `Makefile`
- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`

### Required Command Proof

For relay code changes:

```bash
rtk npm run test:relay
rtk npm run contract:check
```

For simulator/UI behavior:

```bash
rtk make app SIM='iPhone 17' FORCE_LAUNCH=1
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=spawned-private-child-status-rollup
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
```

If the scenario registry, proof schema, coverage doc, or generated docs checks
change, also run:

```bash
rtk npm run test:docs
```

If the simulator, Xcode, or automation snapshot setup blocks, report the exact
command and exact blocker.

## Side Doors To Close

- `dock/subscribe` initial snapshot must use the same rollup logic as
  reconciliation.
- `dock/update` must not leak hidden child rows as a workaround.
- `thread/detail/subscribe` for the child must stay rejected.
- `deleteRejectedThreadCards()` must still remove stale child/private rows.
- `deleteRejectedLiveLeases()` must not be the only mechanism that clears the
  parent badge; the next reconciliation without hidden activity must rewrite the
  parent status.
- Existing same-ID live overlay must continue to work for visible human rows.

## Done State

The fix is done when all of these are true:

- Unit/contract tests prove hidden active child -> parent `running` and child
  absent.
- Tests prove waiting child statuses roll up to `needsApproval` or `needsInput`.
- Tests prove private spawned child owner rolls up only through parent metadata.
- Tests prove root private owner presence is not a global `running` shortcut.
- `rtk npm run test:relay` passes.
- `rtk npm run contract:check` passes.
- Controlled simulator `spawned-private-child-status-rollup` proof passes or
  has an exact environment blocker.
- Controlled simulator matrix proof passes or has an exact environment blocker.
- No Swift source files changed for this issue.
