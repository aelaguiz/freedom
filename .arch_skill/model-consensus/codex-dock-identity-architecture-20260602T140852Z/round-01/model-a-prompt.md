# Mission

You are Model A in a two-model consensus run. You are an expert architecture collaborator, not a prompt runner. Your job is to reason from repo evidence and converge on the most elegant permanent architecture for the user's goal.

Another model will independently produce a first pass. After both first passes, you will critique and revise until both models agree or expose a real unresolved decision.

## Raw User Goal

Well, what's the most elegant fix for these issues? not like what's the tiny tweak to what we currently do. What's the best architectural fix? work with model consensus Opus 4 8 Max and GBD-55XI to put a plan together on disk cross-linked with the bug doc. Do not implement yet.

## Faithful Goal Brief

Define the best permanent architecture for the Codex Dock identity-drift class of bugs, especially the Thread Detail outbound duplicate issue. The answer must avoid small local hacks and zero-sunk-cost bias toward the current implementation. It should produce a plan document on disk cross-linked to the bug doc. This is planning only; do not implement production code.

## Work Root

`/Users/aelaguiz/workspace/codex-client`

## User-Named Inputs

- Source bug doc: `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`
- Existing related architecture proposal: `docs/CODEX_DOCK_PERMANENT_PROJECTION_IDENTITY_ARCHITECTURE_2026-06-01.md`

## Hard Constraints

- Do not edit files.
- Do not implement code.
- Ground repo claims in real evidence before recommending or agreeing.
- Prefer the smallest architecture that eliminates the whole identity-drift class.
- Reject local dedupe, body-text matching, route-specific hacks, or proof-only fixes.
- Find side doors in production code, DTOs, caches, tests, proof tooling, and docs.

## Repo Requirement

You must read real repo evidence before recommending or agreeing. Start from the source bug doc and existing architecture proposal, then choose the code, docs, tests, scripts, schemas, and local artifacts needed for the goal. Cite what you inspected and why it matters. For planning work, identify the existing owner path before proposing where new work belongs.

Maximize parallelism by using parallel agents. Do not invoke skills that spawn subagents.

## Quality Bar

The user wants the best architecture, not a tiny tweak to what currently exists. Zero sunk-cost bias is allowed. The plan should be strict enough that identity bugs like outbound duplicate rows, stale cache rows, wrong host identity, request-card identity splits, and proof/test drift become architecturally impossible when correctly implemented.

Agreement must be earned through evidence and simplification. Do not produce a kitchen-sink plan. If the existing `CODEX_DOCK_PERMANENT_PROJECTION_IDENTITY_ARCHITECTURE_2026-06-01.md` is already correct, say so and tighten it. If it is overbuilt or leaves side doors, name the correction.

## Output Contract

Return:

- concise proposed architecture
- evidence read and why it mattered
- existing owner paths to adopt or retire
- side doors the plan must close
- rejected alternatives and why
- tests/proof methodology that would catch real-life identity drift
- whether you are ready to converge

Stop instead of continuing if repo access is unavailable or you cannot substantiate repo claims from files.
