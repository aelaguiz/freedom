# Codex Dock Exhaustive Sync Test Plan Audit

Date: 2026-05-31
Plan: `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md`
Auditor: Codex
Audit type: `$plan-audit`
Verdict: ready

## Summary

The plan is ready for implementation. It defines the missing mechanism the user
asked for: an initial tool build plus an ongoing over-time loop that compares
local Codex durable state, app-server state, relay projection state, Dock stream
state, Swift Dock list state, and click-through thread detail state.

No blocking findings remain in this audit pass.

## Audit Method

The audit checked whether the plan answers these questions:

1. Does it say whether the current harness already proves over-time sync?
2. Does it define what "fully in sync" means for Dock/Home list data?
3. Does it define what "fully in sync" means for click-through thread detail?
4. Does it include an initial tool build, not only a manual process?
5. Does it include a long-running process that watches drift over time?
6. Does it compare against actual local Codex state, not only mocks?
7. Does it handle stale, incomplete, unsupported, and app-server-limited facts?
8. Does it name the exact proof gates and repo-owned commands?
9. Does it avoid implementation work in this docs-only pass?

All nine checks passed.

## Evidence Read

Repository guidance:

- `README.md`
- `Makefile`
- `AGENTS.md`
- `/Users/aelaguiz/.codex/RTK.md`

Architecture and prior analysis:

- `docs/CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md`
- `docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md`
- `docs/CODEX_DOCK_CODEX_APP_SERVER_END_TO_END_AUDIT.md`
- `docs/CODEX_DOCK_RELAY_STATE_PARITY_WORKLOG_2026-05-30.md`

Relay and parity files:

- `scripts/dock-relay-state-parity.mjs`
- `scripts/dock-relay-state-snapshot.mjs`
- `scripts/dock-relay-state-engine.mjs`
- `scripts/dock-relay-state-store.mjs`
- `scripts/dock-relay-state-views.mjs`
- `scripts/dock-relay-thread-fidelity.mjs`
- `scripts/dock-relay-constants.mjs`

Swift client files:

- `CodexDock/State/DockStore.swift`
- `CodexDock/State/AppServerThreadCardStreamClient.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/State/AppServerThreadDetailSession.swift`
- `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`
- `CodexDock/AppServer/AppServerClient.swift`
- `CodexDock/AppServer/AppServerMethods.swift`

Tests checked for current coverage and gaps:

- `CodexDockTests/DockStoreStreamTests.swift`
- `CodexDockTests/DockStoreTests.swift`
- `CodexDockTests/ThreadDetailStoreTests.swift`
- `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`
- `CodexDockTests/ThreadDetailStreamingMergeTests.swift`
- `scripts/dock-relay.test.mjs`

Parallel read-only agents were also used for coverage:

- Storage and parity explorer.
- Relay and Dock-list explorer.
- Thread-detail click-through explorer.

## Coverage Ledger

### Current Harness Answer

Status: pass

The plan clearly states that `scripts/dock-relay-state-parity.mjs` is a strong
one-shot foundation but does not yet prove long-running over-time sync. This
directly answers the user's original question.

### Actual Local Codex State

Status: pass

The plan requires the verifier to read `CODEX_HOME`, `state_5.sqlite`,
`goals_1.sqlite`, rollout JSONL session files, archived session files, and
`session_index.jsonl`. It also distinguishes durable storage truth from live
app-server truth.

### App-Server State

Status: pass

The plan requires `thread/list`, `thread/read`, `thread/turns/list`,
`thread/goal/get`, `thread/loaded/list`, `thread/resume`, notifications, and
server requests. It also records app-server limits such as no global atomic
snapshot id and no global goal list.

### Relay Projection

Status: pass

The plan covers relay reconciliation, freshness, incomplete scopes, stale rows,
live status overlay, windowing, catch-up, sequence gaps, `dock/subscribe`,
`dock/update`, and `dock/resync`.

### Dock/Home List

Status: pass

The plan defines exact card matching, field matching, ordering, archive
membership, live status, host identity, duplicate detection, and stale state
handling.

### Swift DockStore

Status: pass

The plan requires Swift store proof, not just relay protocol proof. It names
`DockStore`, `AppServerThreadCardStreamClient`, host isolation, resync behavior,
and stale/offline state.

### Thread Detail Click-Through

Status: pass

The plan starts detail verification from actual Dock rows and requires matching
thread id, matching host, `thread/read`, complete `thread/turns/list`, resume,
live notifications, server request cards, request resolution, reconnect
rehydrate, and `.live` state boundaries.

### Over-Time Soak

Status: pass

The plan requires `t0`, `t_change`, `t_relay_seen`, `t_dock_seen`,
`t_detail_seen`, and `t_stable`, plus two stable samples after convergence. It
also includes one-shot, soak, controlled scenario, and Swift proof loops.

### Unsupported Facts

Status: pass

The plan requires every unsupported fact to be classified as
`outside_app_server_contract`, `outside_client_contract`, or `product_gap`, and
blocks final completion on client-required `product_gap`.

### Proof Gates

Status: pass

The plan uses repo-owned commands:

- `rtk make services`
- `rtk make app-server-status`
- `rtk make dock-relay-status`
- `rtk npm run test:relay`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter AppServerClientTests`
- `rtk make app-test SIM='iPhone 17'`

It avoids raw `xcodebuild`, raw `simctl install`, and raw `devicectl device
install app` as the normal workflow.

### Docs-Only Constraint

Status: pass

The plan explicitly says it is a plan only and no implementation is included.
The current change adds only docs files.

## Residual Risks

These are not blockers because the plan names them and requires mitigation:

- There is no atomic cross-plane snapshot id.
- The thread-detail initial-load live-event race needs proof or a buffering
  mechanism.
- Previewless storage rows may be outside current `thread/list` support.
- Orphan goals cannot be globally proven through current app-server APIs.
- Some historical prompt-start and output schema facts may remain outside the
  app-server contract.

## Fresh Consult Result

Reviewer: Cursor Agent `composer-2.5-fast`
Run directory: `/tmp/fresh-consult/codex-dock-sync-plan-20260531T021841Z`
Result file: `/tmp/fresh-consult/codex-dock-sync-plan-20260531T021841Z/events.jsonl`
Verdict: PASS

Blocking findings: none.

The reviewer confirmed all requested plan requirements were present. It also
raised non-blocking notes about scenario actuators, detail stream collection,
turn ordering, resync gap injection, and migration use of the existing parity
command. Those notes were folded back into the plan, then the review was rerun
on the final plan and passed again. One final non-blocking flag-citation note
was corrected from `--include-dock-subscribe` to the actual opt-out
`--no-dock-subscribe`.

## Audit Result

Verdict: ready

The plan is specific enough for implementation to start. It is not just a test
wish list: it defines the tool shape, oracles, probes, invariants, failure
codes, scenarios, over-time loop, proof gates, and completion criteria.
