# Plan Audit Log

Plan: `docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06.md`
Audit log: `docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-06-06
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None. Cursor Composer returned non-blocking notes on 2026-06-06; the plan now
carries the useful repairs:

- test-only override fields are named as `config.threadRetentionWindowMs` and
  operation `nowMs`;
- retention reuses/export existing `rowActivityAtMs()` instead of duplicating
  timestamp parsing;
- exported `aggregateThreadList()` is included as defense in depth;
- the temporary "visible old card until next reconcile" window is documented.

## Current Implementation Findings

Not run. No implementation exists for this plan yet.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Local instructions | `AGENTS.md` prompt content, `/Users/aelaguiz/.codex/RTK.md`, `README.md`, `docs/TESTING.md`, `Makefile` | Repo command rules, real-relay proof rules, deploy commands, and service ownership | parent | read |
| Canonical owner path | `scripts/dock-relay-state-engine.mjs` `reconcileDock`, `reconcileArchive`, `refreshLiveLeases`; `scripts/dock-relay-thread-data.mjs` `drainThreadListRows`, `enrichHumanStartedRows`, `readSessionIndexHumanStartedSupplements`, `canonicalizeThreadRows`, route helpers | Main acquisition, proof, and route assertion path that can stop paying for old rows | parent | read |
| State store cleanup | `scripts/dock-relay-state-store.mjs` `applyDockReconciliation`, `applyArchiveReconciliation`, `listDockCards`, `listArchiveCards`; `scripts/dock-relay-state-store-human-filter.mjs` | Confirms existing reconciliation can delete old visible cards without adding a second sweeper | parent | read |
| Projection and timestamp pattern | `scripts/dock-relay-state-views.mjs` `timestampToMs`, `normalizeThread`, `orderedDockRows`; `scripts/dock-relay-constants.mjs` | Confirms existing timestamp parser and canonical constants location | parent | read |
| Downstream side doors | `scripts/dock-relay.mjs` `handleRequest`, `subscribeThreadDetail`, detail read helpers; `scripts/dock-relay-user-message-command.mjs` `send` | Confirms direct route families go through shared helpers and user-message delivery already calls `assertHumanThreadID()` before persistence/upstream delivery | parent | read |
| Upstream app-server params | `docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md`, `docs/CODEX_APP_SERVER_THREAD_MESSAGE_TURN_DATA_REFERENCE_2026-05-31.md` relevant `thread/list` sections | Confirms no documented server-side `updatedAfter` cutoff exists in current evidence | parent | read |
| Tests and proof surfaces | `package.json`, `scripts/dock-relay-card-contract.test.mjs`, `scripts/dock-relay-state-store.test.mjs`, `docs/TESTING.md`, `Makefile` simulator and relay targets | Confirms focused relay test owners and real-relay proof commands | parent | read |
| Deploy surfaces | `README.md` Mac and Linux `home` service sections, `Makefile` service/device targets | Confirms exact deploy/status commands and physical-device expectations | parent | read |
| Native subagent availability | `multi_agent_v1.spawn_agent` tool rules | Tool requires explicit user request for sub-agents; the user asked for fresh consult, not sub-agents | parent | prohibited |

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses, if triggered

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Should "older than 48h" be based on cheap `thread/list` activity or newest turn proof? | Cheap activity saves cost; turn proof is more semantically accurate but requires the expensive work being avoided. | Determines whether the change actually reduces `thread/read` and `thread/turns/list` cost. | Use cheap activity, with live-loaded rows as the safety exception. | agent, from repo evidence and user cost goal | Plan lines 65-70 and 650-653 | resolved |
| DEC-002 | Should live old rows remain visible? | Strict age hiding would hide active work; live bypass keeps active work visible. | Current sessions could disappear if no bypass exists. | Retain current live rows and hidden-child rollup parents through narrow live evidence. | agent, from repo live-row architecture | Plan lines 79-87 and 221-229 | resolved |
| DEC-003 | Should production have a retention toggle or env var? | Toggle aids rollout; fixed constant is simpler and matches user request. | Extra mode can create drift and test matrix growth. | Use a fixed production 48-hour constant; only tests can inject shorter windows. | agent, from user request and repo constant rules | Plan lines 51-53 and 177-186 | resolved |

## Pass History

### Pass 1 - 2026-06-06

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: current worktree after adding `docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06.md`
- Test/CI context accepted, if supplied: none supplied
- Agents/lenses run: parent-only plan-audit; native subagents not used because `multi_agent_v1.spawn_agent` requires an explicit user request for sub-agents
- Code areas read: see coverage ledger
- Findings added:
  - repaired before final log: real-data SQLite proof failed to exempt live rows;
  - repaired before final log: early-stop wording could imply broad old pagination to find live-bypass IDs;
  - repaired before final log: user-message command side door was not named explicitly.
- Findings resolved:
  - Plan now stops broad pagination at the first old page and uses direct one-ID live supplements.
  - Plan now names `thread/message/send`, `turn/start`, and `turn/steer` as covered by `assertHumanThreadID()`.
  - Real-data SQL proof now exempts nonexpired live leases and active live statuses.
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code exists, especially no scattered age checks, no old-row turn proof, no route side doors, and no file-size regression.

### Fresh Consult - 2026-06-06

- Skill: `$fresh-consult`
- Runtime/model/effort: `agent` / `composer-2.5-fast` /
  `encoded-in-model`
- Mode: `fresh-resumable`
- Chain directory:
  `/tmp/fresh-consult/codex-dock-48h-retention-20260606TxWtDLu`
- Run directory:
  `/tmp/fresh-consult/codex-dock-48h-retention-20260606TxWtDLu/turn-01`
- Session id: `c3b37933-8161-4a3e-bdda-c8f8734500cf`
- Verdict: `pass-with-notes`
- Blocking: none
- Non-blocking notes:
  - reuse or export existing `rowActivityAtMs()` instead of duplicating
    `cheapThreadActivityMs()`;
  - name the test-only config field for retention-window override;
  - optionally gate unused `aggregateThreadList()` for defense in depth;
  - document the brief window where an old visible card may reject before the
    next reconcile deletion arrives;
  - accept the intentional asymmetry where card fallback uses turn-proven
    `activityAtMs` while acquisition uses cheap upstream timestamps.
- Plan repairs from notes:
  - `docs/CODEX_DOCK_48H_THREAD_RETENTION_ARCHITECTURE_2026-06-06.md`
    now names `config.threadRetentionWindowMs`, requires reuse/export of
    `rowActivityAtMs()`, includes `aggregateThreadList()`, and documents the
    old-card-before-reconcile edge case.

## Plan-Readiness Verdict

VERDICT: ready
Confidence: high

Blocking findings: none.

The plan has a clear North Star, fixed 48-hour production behavior, one relay
policy owner, exact acquisition and route side-door gates, deletion through
existing reconciliation, and a real-relay test/deploy plan. The main tradeoff
is explicit: rows whose cheap app-server activity is stale will not receive
turn proof just to discover newer turn activity, because that proof is the cost
the plan is designed to avoid. Current live rows are the safety exception.
