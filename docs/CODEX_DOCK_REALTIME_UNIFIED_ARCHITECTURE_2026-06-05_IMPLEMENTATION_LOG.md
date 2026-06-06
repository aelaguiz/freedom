# Plan Implementation Log

Plan: docs/CODEX_DOCK_REALTIME_UNIFIED_ARCHITECTURE_2026-06-05.md
Audit log: none yet
Active scope: whole approved plan through Phase 7, with Phase 8 optional only if earlier proof shows upstream Codex gaps are material
Last updated: 2026-06-06T05:04:00Z
Current checkpoint: implementation complete on dirty local branch `codex-dock-agents-tab-live-counts`

## Resume Snapshot

- Current state: implementation and live-data simulator proof passed for the rename-title and archive-toggle realtime slices.
- Next useful move: commit, push, deploy both relay hosts, and verify service status.
- Do not redo unless stale: plan readiness gate; relay owner code mapping; local Node/Swift proof; real-data simulator proof in `/tmp/codex-client/sim-ui-realdata-realtime-20260606T045558Z`.
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
| `rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'` | real simulator app against live relay data | passed; root `/tmp/codex-client/sim-ui-realdata-realtime-20260606T045558Z`; `rename-title` and `archive-toggle` both relay OK and UI OK with `0` failures | relay/proof/UI changes | any touched app UI/proof/relay path |
| `rtk npm test` | Node contract, docs, relay, host-service | passed; `contract:check`, `test:docs`, `test:relay`, and `test:host-service` all passed | Node/proof/docs/service changes | any touched Node/proof/docs/service path |
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
