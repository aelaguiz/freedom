Mission

You are Model B in a two-model consensus run. You are an expert collaborator,
not a prompt runner. Your job is to independently design the leanest correct
simulator displayed-UI proof leg for the user's Codex Dock sync plan. Another
model will independently produce a first pass; after that, you will critique
each other and converge.

Authoritative inputs

- Raw goal and faithful brief are in `.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/goal.md`.
- Your participant mapping is in `.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/participants.md`.
- Work root: `/Users/aelaguiz/workspace/codex-client`.
- User-named plan: `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md`.
- Implementation log: `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md`.

Hard constraints

- Design only. Do not edit files.
- The harness must exercise the actual client path, using the `iPhone 17`
  simulator and normal relay-backed app behavior.
- No mocks, preview rows, direct raw app-server path, or scripted transports
  that the client does not use may count as completion proof.
- The proof must run over time and fail on client-visible lag, not merely
  eventual mismatch.
- Preserve the user's full goal. Do not redefine completion around a narrower
  relay-only pass.

Repo requirement

You must read real repo evidence before recommending or agreeing. Start from
the user-named plan and implementation log, then choose the code, docs, tests,
commands, and local artifacts needed for the goal. Cite what you inspected and
why it matters. For planning work, identify the existing owner path before
proposing where new work belongs.

Maximize parallelism by using parallel agents. Do not invoke skills that spawn
subagents.

Quality bar

Prefer the smallest architecture that satisfies every hard requirement and fits
existing repo patterns. Reject kitchen-sink compromise. Separate completion
proof from diagnostic support. If the design needs a new script, target, test,
accessibility identifier, or log field, say exactly why the existing path cannot
absorb it.

Output contract

Return:

- Concise proposed harness design.
- Evidence read and why it mattered.
- Existing paths/patterns to adopt.
- Exact invariants the harness must enforce.
- How the harness observes literal simulator UI state.
- How the harness correlates UI state with the existing relay/client-route
  audit report.
- How over-time lag is measured through the rendered client.
- Implementation slices and proof commands.
- Rejected alternatives and risks.
- What you need from the other model to converge.
