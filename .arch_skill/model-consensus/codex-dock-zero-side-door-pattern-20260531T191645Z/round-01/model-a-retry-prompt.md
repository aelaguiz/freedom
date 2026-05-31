You are Model A in a model-consensus review. You are the architecture reviewer.

Repository: `/Users/aelaguiz/workspace/codex-client`

User requirement:

> Exhaustively specify the data-contract repair pattern with no side doors, no
> drift, no test-only side-door paths, no fake linter/wrapper guardrails, and no
> narrow one-off fix. Do not implement code. The plan must be fully formed.

Task:

Review the current plan and Model B's completed critique, then return a concise
but strict consensus answer. Do not edit files. Do not spawn subagents. If you
need file evidence, read exact files only.

Inputs to read:

- Current plan:
  `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md`
- Current plan audit:
  `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31_PLAN_AUDIT.md`
- Source audit:
  `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md`
- Model B first pass:
  `.arch_skill/model-consensus/codex-dock-zero-side-door-pattern-20260531T191645Z/round-01/model-b-final.md`

Known evidence to consider:

- `scripts/dock-relay.mjs` exposes raw JSON-RPC routes for `thread/list`,
  `thread/search`, `thread/goal/get`, `relay/state/snapshot`,
  `thread/loaded/list`, `thread/read`, `thread/turns/list`, `thread/resume`,
  `thread/archive`, `thread/unarchive`, `state/query`, voice routes, and turn
  command routes.
- `scripts/dock-relay.mjs` exposes HTTP diagnostic routes including
  `/debugz/sessions`, `/statez`, `/syncz`, `/subscriptionsz`, `/dbz`,
  `/explainz/thread/{threadID}`, `/tracesz/*`, `/selftestz`, and `/bundlez`.
- `thread/archive` and `thread/unarchive` currently call archive command
  helpers and then `handleArchiveMutation`; `applyArchiveMutation` writes card
  state in `scripts/dock-relay-state-store.mjs`.
- Scripts/tests still mention or use old oracle paths:
  `scripts/dock-relay-sync-audit.mjs`,
  `scripts/dock-relay-state-parity.mjs`,
  `scripts/dock-relay-thread-fidelity.mjs`,
  `scripts/dock-relay-probe.mjs`,
  `scripts/dock-relay-state-snapshot.test.mjs`,
  `scripts/dock-relay-observability.test.mjs`,
  `scripts/dock-relay-phase5.test.mjs`,
  `scripts/dock-relay-sync-audit.test.mjs`, and related relay tests.
- Swift has `AppServerClient.threadList`, `AppServerMethods.threadList`,
  `ThreadCardFixtureQuery`, `ScriptedDockStreamClient`, local pinned display
  snapshots, and diagnostics that currently treat `thread/list` as
  app-critical health.

Questions to answer:

1. Is Model B's proposed architecture sufficient to close every drift point if
   implemented correctly? If not, list the missing requirements.
2. What exact invariant should replace the current bounded latest-turn scan so
   fresh Dock/Archive can never knowingly be misordered?
3. What route-scope table must exist so detail, commands, voice, health, and
   diagnostics cannot become card-truth side doors?
4. What test/script/proof rule prevents test-only side doors without relying on
   keyword linters or wrapper theater?
5. What implementation phases should the plan carry so the pattern is
   complete, not just a narrow fix?

Output format:

- `Verdict`
- `Must Change In The Plan`
- `Final Pattern`
- `No-Side-Door Proof Rules`
- `Signoff Criteria`

Be adversarial. If you can still imagine drift after the plan is implemented,
say exactly where.
