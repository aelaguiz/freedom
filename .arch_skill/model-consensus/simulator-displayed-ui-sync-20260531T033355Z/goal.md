# Model Consensus Goal

Raw goal:

Use `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md` via
`$plan-implement` to implement the exhaustive sync testing harness and prove
that the relay gives the client every piece of information it needs, stays up
to date with the actual local Codex instances and sessions, does not drop or
lag client-visible data, and exercises the actual paths the client exercises.
The user later added that completion also requires a third leg: literal
`iPhone 17` simulator displayed-UI proof over time. Before building that third
leg, run `$model-consensus` with Opus 4.8 Max and GPT-5.5 X-High to design the
most elegant end-to-end-to-end harness and the invariants that must hold.

Goal brief:

Design the simulator displayed-UI proof leg for Codex Dock. The design must
use the existing repo and plan as source truth, preserve the already-built
relay/client-route harness, and add the missing end-to-end-to-end assurance
that the literal simulator UI stays complete, correct, and close to real time
over multiple samples. This is design only; do not edit repo files.

User-named inputs:

- `/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md`
- `/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md`
- Repo root: `/Users/aelaguiz/workspace/codex-client`

Hard constraints:

- Use the normal `iPhone 17` simulator app path and relay-backed host path.
- Do not use mocks, preview rows, direct raw app-server connections, or
  transports the client does not exercise as completion proof.
- The proof must run over time; a single screenshot or one-shot UI check is not
  enough.
- Significant lag is a failure even if eventual sync succeeds.
- The design must identify exact invariants for missing data, stale displayed
  data, wrong detail data, wrong ordering/status/archive state, and lag.
- Reuse existing repo owner paths and Makefile/`rtk` flows where possible.
- Keep the solution lean; avoid a second source of truth for relay/client
  protocol comparison.
- Do not edit files in this model-consensus run.

Desired output:

- Lean proposed harness architecture.
- Existing repo paths and patterns to adopt.
- Exact displayed-UI invariants.
- How to observe literal simulator display state.
- How to correlate UI state to the existing relay/client-route audit report.
- How to measure over-time lag through the rendered client.
- Implementation slices and proof commands.
- Rejected alternatives and remaining risks.
