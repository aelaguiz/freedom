Mission
You are Model A in a model-consensus run. You are a collaborator, not a prompt runner. Your job is to review and repair the current Codex Dock data-contract implementation plan until it fully satisfies the user's stronger requirement: no side doors, no accepted drift, no test-only oracle paths, and no fake linter/wrapper guardrails standing in for architecture.

System Context
The parent agent is orchestrating a two-model consensus run. Another model will independently produce a first pass. After both first passes, you will review each other's work and converge. Do not edit files. Do not implement code. Maximize parallelism by using parallel agents. Do not invoke skills that spawn subagents.

Authoritative Inputs
- Raw goal: see `.arch_skill/model-consensus/codex-dock-zero-side-door-pattern-20260531T191645Z/goal.md`.
- Work root: `/Users/aelaguiz/workspace/codex-client`.
- Plan to repair: `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md`.
- Current plan audit feedback: `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31_PLAN_AUDIT.md`.
- Source audit: `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`.

Hard Requirements
- No side doors, including tests, audit scripts, diagnostics, fixtures, docs, and proof paths.
- A fresh Dock/Archive list cannot be knowingly mis-ordered. If canonical activity is not proven for the emitted set, freshness must expose that uncertainty and the list must not claim fresh newest-first correctness.
- Thread Detail routes may remain only with an explicit route-scope boundary: they can prove Thread Detail behavior after a Dock/Archive card is selected, never Dock/Archive card ordering/freshness/list completeness/summary.
- Do not propose keyword linters, banned-word searches, or wrapper theater as the main drift solution.
- Preserve user-facing Dock/Archive/Thread Detail features, except fake card truth such as cached pinned display.

Repo Grounding
Read real repo evidence before recommending repairs. Start with the three named docs, then inspect route handlers, proof/audit scripts, tests, and client/relay owner paths as needed. Cite exact files and symbols/lines when they decide an issue.

Quality Bar
Prefer the smallest architecture that makes drift impossible by construction. The output should name exact plan edits and any route/script/test dispositions that must be added.

Output Contract
Return:
- whether the current plan is ready or not
- every remaining side door or drift path you find
- the exact plan repair for each blocker
- the final architecture pattern you recommend
- tests/proof rules that allow no side-door exceptions
- any residual risk that truly remains after the repaired plan
- evidence read

Stop Instead Of Continuing If
You cannot substantiate repo claims from files.
