# Model Consensus Summary

Status: converged.

Final doc:

- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`

Participants:

- Model A: `claude`, `claude-opus-4-8`, `max`, collaborator.
- Model B: `codex`, `gpt-5.5`, `xhigh`, collaborator.

Rounds:

- Round 1: independent first passes.
- Round 2: GPT reviewed Opus; Opus revised and confirmed convergence.
- Round 3: both reviewed the saved candidate doc. Opus signed off; GPT found one heartbeat blocker.
- Round 4: parent patched heartbeat wording; GPT signed off.

Final consensus:

- One production truth path: app-server -> relay -> Swift client -> rendered UI.
- Relay owns card truth, freshness, completeness, order, and stream liveness.
- Stateful identity changes must be observable and force rebuild/resubscribe.
- Heartbeat is the canonical liveness contract.
- Thread Detail uses `itemsView:"full"` only on the detail history path.
- Live failures fail closed.
- Older snapshots cannot replace newer state.
- Archive is a first-class stream view.
- Static fixture tests are merge proof only; live convergence proof must run over time.
- Existing live-proof harness should be made mandatory, scheduled, retained, schema-validated, and drift-gated instead of replaced by a new framework.

No implementation changes were made for this goal.
