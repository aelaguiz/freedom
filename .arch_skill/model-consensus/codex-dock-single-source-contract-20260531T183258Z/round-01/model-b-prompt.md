Mission
You are Model B in a two-model consensus run. You are a collaborator, not a
prompt runner. Your job is to read real repo evidence and propose the leanest
correct implementation plan for the user's goal. Another model will independently
do the same; after both first passes, you will critique and converge.

Raw Goal
The user wants an implementation plan based on
`docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`.
They want Model Consensus with Opus 48 Max and GPT-55X High.

They want to unify on a single source of truth end to end; remove side doors
and multiple sources of truth completely; delete wrong paths rather than keep
them for posterity or tests; remove or rewrite tests that use the wrong paths;
preserve the intended user experience; infer missing precision from first
principles; make the system robust and drift-proof end to end; prevent the
client from having alternate weird ways to do the same thing; keep the
architecture maximally elegant; avoid extra wrappers, linters, or keyword scans
as fake safety; keep existing UI capability; document the invariant in code;
and lock the invariant with drift-proof tests. The final artifact should be a
thorough implementation plan cross-linked with the audit.

Faithful Goal Brief
Create a repo-grounded implementation plan, not code changes, for a single
canonical Codex Dock thread/card data contract. The plan must identify the
single source of truth, delete or absorb side doors, retire tests and fixtures
that keep old paths alive, preserve the current intended user experience, and
define exact implementation and verification work across relay, Swift client,
tests, diagnostics, and docs.

Work Root
`/Users/aelaguiz/workspace/codex-client`

User-Named Input
`docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`

Repo Requirement
You must read real repo evidence before recommending or agreeing. Start from
the user-named audit, then choose the code, docs, tests, schemas, fixtures,
and commands needed for the goal. Cite what you inspected and why it matters.
For planning work, identify the existing owner path before proposing where new
work belongs.

Quality Bar
Prefer one existing path over two new ones. The right plan should delete side
doors, not wrap them. It should not preserve wrong endpoints or fixtures "for
tests." It should not add a second schema, a validator-only facade, a keyword
linter, or a generic abstraction unless the existing owner cannot absorb the
work. Preserve user-facing features, but collapse implementation pathways.

Maximize parallelism by using parallel agents when useful. Do not invoke skills
that spawn subagents.

Output Contract
Return:

- concise proposed implementation plan
- one canonical source of truth and why it is the right owner
- exact side doors to delete or absorb
- exact owner files/modules to change
- exact tests to delete, rewrite, or add
- code comments/docs that should be added in-code
- migration order that avoids half-old/half-new states
- rejected alternatives and why
- risks or open questions
- evidence read and why it mattered
- what you need from Model A to converge

Stop Instead Of Continuing If
Repo access is unavailable, the requested model cannot read files, or you
cannot substantiate repo claims from files.

