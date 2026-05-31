# Model Consensus Goal

## Raw Goal

The user wants an implementation plan based on
`docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`.
They want Model Consensus with Opus 48 Max and GPT-55X High.

They want the plan to:

1. Unify on a single source of truth end to end.
2. Remove side doors and multiple sources of truth completely.
3. Delete wrong paths, not leave them around for posterity or tests.
4. Remove tests that use wrong paths or change them to use the right path.
5. Preserve the intended user experience.
6. Interpret the ask from first principles when wording is imprecise.
7. Make the system robust and drift-proof end to end.
8. Ensure the client cannot find weird alternate ways to do the same thing.
9. Keep the architecture maximally elegant: less code, fewer pathways, no extra wrappers or keyword linters as fake safety.
10. Keep existing UI capability; do not use "less" as an excuse to cut user-facing features.
11. Document the code in the code where the invariant matters.
12. Lock the invariant with tests that catch drift.
13. Save the result into a thorough, exhaustive implementation plan cross-linked with the audit.

## Faithful Goal Brief

Create a repo-grounded implementation plan, not code changes, for a single
canonical Codex Dock thread/card data contract. The plan must identify the
single source of truth, delete or absorb side doors, retire tests and fixtures
that keep old paths alive, preserve the current intended user experience, and
define exact implementation and verification work across relay, Swift client,
tests, diagnostics, and docs.

The plan should be maximally lean. "World's best" means one direct architecture
with no duplicate paths, no ornamental enforcement layers, no legacy aliases,
and no test-only alternate contract. It should specify what to delete, what to
replace it with, what code comments must state, and what tests prove drift is
not possible.

## User-Named Inputs

- Repo root: `/Users/aelaguiz/workspace/codex-client`
- Audit: `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`

## Resolved Participants

- Model A: `Opus 48 Max` -> runtime `claude`, model `claude-opus-4-8`, effort `max`, role `collaborator`
- Model B: `GPT-55X High` -> runtime `codex`, model `gpt-5.5`, effort `high`, role `collaborator`

## Required Output

Each model must produce an implementation plan with:

- the one canonical source of truth
- exact side doors to delete or absorb
- exact owner files/modules to change
- exact tests to delete, rewrite, or add
- code-comment/documentation points that prevent future drift
- migration order that avoids half-old/half-new states
- rejected alternatives and why they are unnecessary
- evidence read from the repo

