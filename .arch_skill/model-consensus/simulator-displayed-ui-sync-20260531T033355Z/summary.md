# Simulator Displayed-UI Sync Consensus Summary

Participants:

- Model A: `claude`, `claude-opus-4-8`, effort `max`, collaborator.
- Model B: `codex`, `gpt-5.5`, effort `xhigh`, collaborator.

Status: converged.

Consensus:

- Build the third leg as a real `iPhone 17` XCUITest displayed-UI sampler plus
  a sibling Node judge/orchestrator that reuses
  `scripts/dock-relay-sync-audit.mjs` as the canonical relay/client-route
  truth.
- Launch the real app path with `CODEX_DOCK_HOSTS=<relay>:4510` through the
  existing Makefile/XCTest flow. Do not set
  `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`; do not use mocks, preview rows,
  scripted transports, or raw `:4500` as completion proof.
- Run the relay soak recorder and simulator UI sampler concurrently.
- Observe literal rendered state through the accessibility tree:
  `codexdock.dock.root`, `codexdock.dock.row.<host>.<thread>`,
  `codexdock.session.root.<thread>`, `codexdock.session.header`,
  `codexdock.session.message.<eventID>`, and request-card IDs/values.
- Judge UI samples against relay truth by time window plus
  `(logicalHostID, threadID)`, using existing audit helpers for card IDs,
  comparison, normalization, redaction, and lag budget.
- Treat fast samples as watched/visible row proof plus root row-count proof;
  run bounded full-scroll sweeps at stable checkpoints for missing, extra,
  duplicate, and order checks. Full sweeps are not the fast lag clock.
- Measure rendered lag as the first matching UI sample after `t_relay_seen`;
  fail if it exceeds the configured UI lag budget, default 2,000 ms. Require
  two consecutive matching UI samples for stability.
- Add only minimal redaction-safe instrumentation: hash/fingerprint 1:1 visible
  fields such as Dock row title and detail event title/body. Do not fingerprint
  client-derived preview/summary fields as relay truth.
- Completion-grade lag proof requires a deterministic isolated-`CODEX_HOME`
  scenario actuator that produces real app-server/relay/client-visible changes.
  Passive real-home UI observation is smoke/regression evidence only because it
  can pass without an observed change.

Residual risks:

- Fingerprint normalization drift can false-mismatch; gate fingerprints behind
  parity tests before they fail CI.
- Fast samples only see materialized SwiftUI rows; full offscreen proof depends
  on checkpoint sweeps and legs 1-2 relay parity.
- Keep the isolated-home actuator thin: create thread, add turn,
  archive/unarchive.
- UI lag math needs a relay event log or equivalent `t_relay_seen` source plus
  a clock-skew guard.
- Sampling at <= budget/4 conservatively overestimates lag but can miss
  appear-and-vanish transitions inside one interval.
