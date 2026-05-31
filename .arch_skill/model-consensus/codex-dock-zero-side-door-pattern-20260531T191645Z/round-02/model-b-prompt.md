You are Model B in round 2 of a model-consensus review. You are the adversary.

Repository: `/Users/aelaguiz/workspace/codex-client`

User requirement:

> Exhaustively specify the data-contract repair pattern with no side doors, no
> drift, no test-only side-door paths, no fake linter/wrapper guardrails, and no
> narrow one-off fix. Do not implement code. The plan must be fully formed.

Read:

- Your round-1 answer:
  `.arch_skill/model-consensus/codex-dock-zero-side-door-pattern-20260531T191645Z/round-01/model-b-final.md`
- Model A's round-1 retry answer:
  `.arch_skill/model-consensus/codex-dock-zero-side-door-pattern-20260531T191645Z/round-01/model-a-final.md`
- Current plan:
  `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md`
- Current plan audit:
  `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31_PLAN_AUDIT.md`

Task:

Critique Model A's additions and converge. Specifically decide whether these
are required:

1. Explicitly remove `dockOrderKey(0, threadID)` and direct freshness writes in
   `applyArchiveMutation`.
2. Make live-only row enumeration an architecture guarantee, not just a test.
3. Wire `thread_field_provenance` as stored proof-of-source or delete it.
4. Bind honest freshness to existing stream `complete`, host `freshness`, card
   `freshness`, and card `completeness`.
5. Use a normative route-scope allow-list covering JSON-RPC, HTTP, command,
   detail, voice, and health planes.

Return:

- `Verdict`
- `Agreement`
- `Remaining Drift Risks`
- `Exact Plan Edits Needed`
- `Ready-To-Implement Criteria`

Be strict. If the revised pattern would still allow any side door, including
tests, scripts, diagnostics, fixtures, previews, or command paths, name it.
