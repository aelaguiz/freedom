Verified against real source: `THREAD_LIST_MAX_LIMIT = 100` with `limit.clamp(1, 100)` at `thread_processor.rs:1817` and `:1897` (and `thread/turns/list` likewise caps at 100, `:3633`). GPT is correct; my pass's `limit=200` assumption was wrong — Codex silently clamps Dock's `DockStore.swift:62` request to 100. This is the one fork that changes a recommendation.

## Signoff

`converged-with-required-edit`

## Required Edits Before Canonical Doc

1. **Record the hard 100-row cap as an invariant and purge the `limit=200` assumption.** `thread/list` clamps `limit` to `[1,100]` server-side (`thread_processor.rs:1817,1897`); Dock's `sessionPageLimit = 200` returns at most 100 rows per scope today. The canonical doc must state the cap and never imply 200 is honored.

2. **Make pagination a baseline prerequisite, and gate the union-scope default on it (amends parent points 6 and 8).** At a 100-row cap, a *single union* `sourceKinds` page forces interactive and agent rows to compete for the same 100 slots, which can starve the All/Agents tabs. So: union scope is acceptable **only** with working relay pagination that guarantees per-tab coverage; **absent pagination, the default is dual scopes run over the one pooled `HistoryClient`** (each kind gets its own ≤100 page). Honest cursor passthrough (`nextCursor` must never be clobbered to `null`) moves from "nice-to-have / open question" into the required baseline, because >100 threads already exist (incident showed ~100/scope) and the tail is currently invisible.

That is the only blocker. Everything else in the parent's 10 points is converged.

## Reason

- Verified fact: `THREAD_LIST_MAX_LIMIT = 100`, `clamp(1, 100)` at `thread_processor.rs:1817` & `:1897` — the server ignores the extra 100 Dock asks for.
- Incident evidence (~609–627 rows across 3 aliases × 2 scopes ≈ ~100/scope) confirms the thread corpus far exceeds 100, so the cap bites *now*: older threads are unreachable because the relay returns `nextCursor: null` (`dock-relay-thread-data.mjs:598`).
- Consequence: "prefer union" (parent point 8) is a *regression risk* under the cap unless paired with pagination — the opposite of the simplification it was sold as. The safe default flips to dual-scope-over-pool until pagination ships.
- Therefore pagination is not optional (my open Q6 / parent point 6 framing was too soft); it's a correctness requirement for any user with >100 threads, which is the actual user.
- Beyond this, the two passes and the parent candidate are structurally identical: Host Agent boundary, `HistoryClient`/`LiveStatusCache`/`SessionRouter`/`TranscriptionProxy` split, history-is-membership-truth with live as repaint-only, `updatedAt desc` + `threadId` tiebreak, one logical host per relay instance id with alias failover, `ps` as cached/transitional with visible degraded state, and the observability surface. No objection on any of these.
- One residual wording divergence worth nailing down (not a blocker): GPT permits marked `liveOnly` rows in the list; my pass keeps membership history-only. Pick one explicitly so the repaint-only invariant stays drift-proof.

## Exact Wording To Include

- **Page cap:** "Codex `thread/list` hard-clamps `limit` to `[1,100]` (`THREAD_LIST_MAX_LIMIT`). Dock must never assume a larger page; one scope returns at most 100 rows. `thread/turns/list` is likewise capped at 100."
- **Union gating:** "A single union `sourceKinds` query is permitted only when the Host Agent paginates to guarantee per-tab coverage under the 100-row cap. Without working pagination, the Host Agent issues dual scopes (interactive, agent) over the one pooled `HistoryClient` connection so each kind gets its own ≤100 page. Scopes never multiply upstream sockets or logical hosts."
- **Cursor honesty (promote to invariant):** "The Host Agent forwards real history pagination cursors. It must never return `nextCursor: null` after reading a paginated upstream. The relay cursor is opaque and carries enough state (sort tuple, per-scope history cursor, live snapshot version) to continue the merged list; rows are deduped by `threadId` across pages."
- **Membership (resolve the live-only fork):** "Dashboard list membership and order are a pure function of the history plane. Live status may repaint `status`, `attention`, `ownerEndpoint`, and degradation metadata only — it must not add, remove, move, filter, or page rows. A freshly started thread appears in the list when it appears in history; surfacing a not-yet-persisted session is the detail view's job, not the dashboard list's."
