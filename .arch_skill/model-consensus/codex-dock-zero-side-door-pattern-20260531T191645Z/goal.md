Raw Goal
The user wants the existing Codex Dock data-contract implementation plan revised through model consensus until it is exhaustively specified, has no side doors, has no drift, has no fake linter-style guardrails standing in for architecture, and has no test paths that preserve side doors. The user rejected the prior narrow plan because it accepted a residual recency gap and may leave diagnostic/test/proof routes around.

Faithful Goal Brief
Revise `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md` so it describes the fully formed pattern, not a narrow partial fix. The plan must preserve the intended UX: Dock and Archive card lists are newest-first by the latest real work, manual pins never fabricate card recency/status/title/summary/activity, and stale/unknown freshness is explicit rather than silently presented as fresh. The plan must remove or fully close every alternate card-truth path, including production routes, diagnostics, audit scripts, tests, fixtures, and local metadata. Legitimate Thread Detail routes may remain only with a hard route-scope boundary that prevents them from being used as Dock/Archive card proof. Do not propose keyword linters or wrapper theater as the drift solution. Prefer one elegant architecture that makes drift hard because there is one path.

User-Named Inputs
- `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md`
- `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31_PLAN_AUDIT.md`
- `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`

Hard Constraints
- No implementation yet.
- No code edits by child models.
- No side doors, not even for tests.
- No accepted residual drift where a fresh Dock/Archive list can be mis-ordered.
- No fake guardrails such as keyword linters in place of single-path architecture.
- Preserve existing user-facing features unless the current behavior is fake card truth.

Desired Output
Each model should produce the exact repairs needed to make the plan ready. The final consensus should be specific enough for the parent to edit the plan and close the audit findings.
