Candidate consensus

The simulator displayed-UI proof should be a real `iPhone 17` XCUITest sampler
plus a sibling Node orchestrator/judge that reuses `scripts/dock-relay-sync-audit.mjs`
as the canonical relay/client-route truth.

Required design points:

- Launch the real app path through existing Makefile/XCTest flows with
  `CODEX_DOCK_HOSTS=<relay>:4510`; do not set
  `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`; never use raw `:4500` or mocks as
  completion proof.
- Run the relay soak recorder and simulator UI sampler concurrently, not
  sequentially.
- Observe literal rendered state through the accessibility tree:
  `codexdock.dock.root`, `codexdock.dock.row.<host>.<thread>`,
  `codexdock.session.root.<thread>`, `codexdock.session.header`,
  `codexdock.session.message.<eventID>`, and request-card IDs/values.
- Judge UI samples against relay truth by time window plus
  `(logicalHostID, threadID)`, using the existing audit helpers for card IDs,
  comparison, normalization, redaction, and lag budget.
- Treat fast samples as watched/visible row proof plus root row-count proof;
  run bounded full-scroll sweeps only at stable checkpoints for missing,
  extra, duplicate, and order checks. Full sweeps are not used as the fast lag
  clock.
- Measure rendered lag as the first matching UI sample after `t_relay_seen`;
  fail if it exceeds the configured UI lag budget, default 2,000 ms. Require
  two consecutive matching UI samples for stability.
- Add only minimal redaction-safe instrumentation: hash/fingerprint 1:1 visible
  fields such as Dock row title and detail event title/body. Do not fingerprint
  client-derived preview/summary fields as if they were relay truth, and never
  log prompt text, transcript text, raw message bodies, or raw summaries.
- Completion-grade lag proof requires a deterministic isolated-`CODEX_HOME`
  scenario actuator that produces real app-server/relay/client-visible changes.
  Passive real-home UI observation is useful smoke/regression evidence but is
  not sufficient by itself because it can pass without an observed change.
- The Makefile target should own the flow, for example
  `rtk make sim-sync-audit SIM='iPhone 17'`, and reports should live under
  `/tmp/codex-client/sim-ui-audit/`.

Question

Does this candidate preserve the user's goal, satisfy every hard requirement,
avoid unnecessary new pathways, and reflect your actual agreement? If no, name
the smallest correction needed. If yes, sign off and name any residual risk.

Maximize parallelism by using parallel agents. Do not invoke skills that spawn
subagents. Design only; do not edit files.
