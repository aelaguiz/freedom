# Plan Implementation Log

Plan: docs/CODEX_DOCK_REALTIME_UNIFIED_ARCHITECTURE_2026-06-05.md
Audit log: none yet
Active scope: whole approved plan through Phase 7, with Phase 8 optional only if earlier proof shows upstream Codex gaps are material
Last updated: 2026-06-06T07:01:24Z
Current checkpoint: implementation complete on dirty local branch `codex-dock-agents-tab-live-counts`

## Resume Snapshot

- Current state: implementation, live-data simulator proof, and the full controlled simulator matrix passed after correcting stale fresh-snapshot and multi-host proof-scoring edges.
- Next useful move: commit, push, deploy both relay hosts, and verify service status.
- Do not redo unless stale: plan readiness gate; relay owner code mapping; local Node/Swift proof; real-data simulator proof in `/tmp/codex-client/sim-ui-realdata-realtime-20260606T062729Z`; controlled matrix proof in `/tmp/codex-client/sim-ui-controlled-matrix-run-20260606T063413Z`.
- Known blockers: none yet.
- Native subagents used or useful next: not used yet; use only for independent review/mapping if explicitly useful.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Real-data proof target | Phase 0 | done | Makefile, proof scripts | `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` passed | thermonuclear review passed |
| Server rename vertical slice | Phase 1 | done | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-sync-audit.mjs` | real-data `rename-title` UI + relay proof passed | no blocking findings |
| Targeted one-thread projector | Phase 2 | done | `scripts/dock-relay-thread-data.mjs`, state store/engine | Node relay tests passed | no blocking findings |
| Status badges | Phase 3 | done for targeted status notification path | state engine/store | Node relay tests passed | no blocking findings |
| Activity/latest summary | Phase 4 | done for low-overhead dirty rollup path | dirty queue/listener leases/projector | Node relay tests passed | no blocking findings |
| Archive/unarchive moves | Phase 5 | done | relay command path/state engine/store | real-data `archive-toggle` UI + relay proof passed | no blocking findings |
| Discovery/private boundaries | Phase 6 | preserved | registry/status diagnostics | Node registry and hidden/private tests passed | no blocking findings |
| Delete old normal polling path | Phase 7 | done for normal targeted mutation paths; broad reconcile remains recovery/backstop | state engine/thread data/docs | Node relay tests passed | no blocking findings |

## Code Read Ledger

| Area | Files/symbols read | Why relevant | Fresh until | Notes |
| --- | --- | --- | --- | --- |
| Plan | `docs/CODEX_DOCK_REALTIME_UNIFIED_ARCHITECTURE_2026-06-05.md` | source of truth | plan changes | Section 7 phases 0-7 are required; Phase 8 optional. |
| Relay state engine | `scripts/dock-relay-state-engine.mjs` | current broad reconcile owner | file changes | Rename/status/archive currently route to broad reconcile. |
| Relay store | `scripts/dock-relay-state-store.mjs` | projection row/sequence owner | file changes | Store has broad apply methods but no one-card mutation APIs yet. |
| Thread data | `scripts/dock-relay-thread-data.mjs` | canonical card facts | file changes | `canonicalizeThreadRows()` already proves activity with `thread/turns/list`. |
| Relay entrypoint | `scripts/dock-relay.mjs` | command and notification routing | file changes | `thread/name/set`, `thread/archive`, and `thread/unarchive` call broad mutation follow-up today. |
| Proof runner | `Makefile`, `scripts/dock-relay-sync-audit.mjs` | simulator/real-data proof | file changes | Existing archive scenario is real relay-backed; activity scenario is fixture-backed; rename/status real scenario absent. |
| Tests | `scripts/dock-relay-card-contract.test.mjs`, `scripts/dock-relay-state-subscriptions.test.mjs` | behavior proof | file changes | Current tests allow broad reconcile for notification paths. |

## Proof Freshness Ledger

| Proof | Scope covered | Result/context | Fresh until | Rerun trigger |
| --- | --- | --- | --- | --- |
| `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_REALTIME_UNIFIED_ARCHITECTURE_2026-06-05.md` | plan readiness | `READY next=implement-loop` | plan edit | any plan source-truth edit |
| `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` | real simulator app against live relay data | passed; root `/tmp/codex-client/sim-ui-realdata-realtime-20260606T062729Z`; `rename-title` and `archive-toggle` both relay OK and UI OK with `0` failures | relay/proof/UI changes | any touched app UI/proof/relay path |
| `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` | full controlled simulator matrix over real app UI | passed; root `/tmp/codex-client/sim-ui-controlled-matrix-run-20260606T063413Z`; `42` reports, `21/21` scenarios passing, max observed UI lag `755 ms`, `0` findings | relay/proof/UI changes | any touched app UI/proof/relay path |
| `rtk npm test` | Node contract, docs, relay, host-service | passed after final proof-scoring patch; `contract:check`, `test:docs`, `271` relay tests, and `37` host-service tests all passed | Node/proof/docs/service changes | any touched Node/proof/docs/service path |
| `rtk npm run test:relay` | Node relay/proof tests | passed after stale fresh-snapshot patch; later full `rtk npm test` covered final `271` relay tests | relay/proof changes | any touched relay/proof path |
| `rtk swift test --filter DockStoreTests` | Dock Swift store/projection | passed; `57` tests, `0` failures | Swift Dock changes | any touched Dock/store Swift path |
| `rtk swift test --filter AppServerClientTests` | Swift JSON-RPC/DTO/client behavior | passed; `54` tests executed, `5` opt-in real-host tests skipped | protocol/client changes | any touched Swift client/protocol path |
| `rtk swift test --filter ThreadDetailStoreTests` | Thread detail Swift store/projection | passed; `65` tests, `0` failures | thread detail changes | any touched detail/composer Swift path |
| `git diff --check` | whitespace sanity | passed | any source/doc edit | before commit |

## Continuous Review Ledger

| Finding | Source | Status | Repair anchor | Notes |
| --- | --- | --- | --- | --- |
| Large-file pressure remains in existing relay/proof scripts | thermonuclear review | accepted for this branch | future extraction | Touched JS files were already over `1000` lines; new behavior is centralized in the store/engine/proof owners and covered by tests. No blocking spaghetti/regression found. |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| Rename/status notification broad reconcile | targeted normal path | targeted card patch/read | done | Phase 1/3 |
| Archive mutation broad reconcile | targeted active/archive move | targeted active/archive move | done | Phase 5/7 |
| Session index supplement | named backstop only | mixed into broad reconcile | open | Phase 5/7 |
| Live loaded polling badge path | backstop/private support | targeted dirty notification rollup + recovery/backstop | done for normal update path | Phase 6 |

## Decision Carry-Through

| Decision | Owner | Plan carry-through | Code carry-through | Status |
| --- | --- | --- | --- | --- |
| Keep phone on relay projection streams | Section 0/5 | phone does not talk to raw `:4500` | no Swift protocol rewrite planned | active |
| Real-data simulator proof required | Section 0/8 | fixture proof support only | new Makefile target required | active |
| Broad reconcile remains recovery/backstop | Section 5/7 | no normal event scenario may rely on it | targeted state APIs required | active |

## Pass Notes

### 2026-06-06 - implementation preflight

- Intent: start `$arch-step auto-implement` from the approved plan.
- Changed: created this implementation log only.
- Read: plan, arch-step/plan-implement/thermonuclear skills, relay state engine/store/thread-data, proof runner, representative tests.
- Proof: plan readiness gate passed.
- Review: broad reconcile is confirmed as the current normal path for rename/status/archive mutation follow-up.
- Next: edit relay/store/thread-data and proof target for the first targeted update slice.

### 2026-06-06 - implementation complete

- Implemented per-view projection sequence numbers so Dock and Archive streams stay contiguous even when the other view changes.
- Replaced normal rename/status/archive mutation follow-up with targeted store writes and targeted stream deltas.
- Added canonical one-thread projection reads for low-overhead dirty updates.
- Removed live-cache overlay from snapshot assembly; snapshots now expose the committed projection that subscribers can actually receive.
- Added real-data `rename-title` and `archive-toggle` simulator proof target in `Makefile`.
- Tightened proof scoring so scenario acceptance is gated by the named scenario transition, while whole-list drift from unrelated live Codex rows remains diagnostic.
- Proof: `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` passed against `ws://amir-m5.fairy-salmon.ts.net:4510`.
  - `rename-title`: relay OK, UI OK, `0` failures, `0` scenario transition failures, UI lag `549 ms`.
  - `archive-toggle`: relay OK, UI OK, `0` failures, `0` scenario transition failures, UI lag `0 ms`.
- Tests: `rtk npm test`, `rtk swift test --filter DockStoreTests`, `rtk swift test --filter AppServerClientTests`, `rtk swift test --filter ThreadDetailStoreTests`, and `git diff --check` passed.
- Thermonuclear review: no blocking structural findings. The main remaining quality debt is pre-existing file size in relay/proof scripts; this branch keeps new logic in canonical owners instead of spreading it across client-side special cases.

### 2026-06-06 - final proof-scoring correction

- Root cause: the real-data `archive-toggle` rerun exposed a proof-scoring false positive where the long-lived Dock stream was ahead of the fresh snapshot (`streamSeq > freshSeq`), but the scorer counted that as stream lag.
- Changed: `evaluateStreamConvergenceLag()` now ignores mismatch attempts where the fresh snapshot is behind the long-lived stream, and only reports convergence when a matching sample exists.
- Thermonuclear review: found and fixed one proof-semantics edge where a stale-fresh-only run could be marked as converged without an actual matching sample.
- Proof: `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` passed against `ws://amir-m5.fairy-salmon.ts.net:4510`; root `/tmp/codex-client/sim-ui-realdata-realtime-20260606T053843Z`.
  - `rename-title`: relay OK, UI OK, `0` failures, `0` scenario transition failures, UI lag `554 ms`, routes included `dock/subscribe`, `dock/update`, `initialize`, `initialized`, and `thread/name/set`.
  - `archive-toggle`: relay OK, UI OK, `0` failures, `0` scenario transition failures, UI lag `576 ms`, routes included `dock/subscribe`, `dock/update`, `initialize`, `initialized`, `thread/archive`, and `thread/unarchive`.
- Tests after patch: `rtk npm run test:relay` passed with `269` tests and `0` failures; `rtk npm test` passed; `git diff --check` passed.

### 2026-06-06 - controlled matrix proof-scoring correction

- Root cause: `multi-host-isolation` displayed a correct composite Dock list, but the proof scorer compared it against one host's transition snapshot instead of the composite `freshDock` truth.
- Root cause: `large-list-checkpoint` is a static controlled scenario; the proof scorer discarded its relay truth as stale even though the fixture truth is intentionally static and valid for the late checkpoint sweep.
- Changed: transition scoring now uses composite `freshDock` truth for multi-host transitions, and static controlled scenario reports keep relay truth for checkpoint sweep scoring.
- Focused tests: `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs` passed with `54` tests and `0` failures.
- Clean controlled matrix proof: `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` passed; root `/tmp/codex-client/sim-ui-controlled-matrix-run-20260606T063413Z`.
  - Summary: `42` reports, `21/21` required scenarios passing, `0` missing scenarios, `0` failed scenarios, `0` findings, max observed UI lag `755 ms` against the `2000 ms` budget.
- Latest real-data simulator proof: `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` passed; root `/tmp/codex-client/sim-ui-realdata-realtime-20260606T062729Z`.
  - `rename-title`: relay OK, UI OK, `0` failures, `0` scenario transition failures, UI lag `552 ms`.
  - `archive-toggle`: relay OK, UI OK, `0` failures, `0` scenario transition failures, UI lag `0 ms`.
- Full Node proof after final proof changes: `rtk npm test` passed; `contract:check`, `test:docs`, `271` relay tests, and `37` host-service tests all passed.
- Thermonuclear review: no blocking findings after replacing the remaining raw proof-policy conditions with named helpers (`isCompositeDockTransition()` and `hasStaticControlledScenarioTruth()`).
- Post-review proof: focused proof tests passed (`54` tests); the affected `multi-host-isolation` and `large-list-checkpoint` matrix artifacts were rescored with the current proof code; matrix verify still passed with `42` reports, `21/21` scenarios, max UI lag `755 ms`, and `0` findings; `rtk npm test` passed again.
