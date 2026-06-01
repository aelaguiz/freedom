Mission
Revise toward consensus. The parent will treat agreement as valid only if both models converge on the same small architecture and all hard requirements remain covered.

Inputs
- Goal brief: `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/goal.md`
- Your previous proposal: `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/round-01/model-a-final.md`
- GPT-5.5's Round-01 proposal: `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/round-01/model-b-final.md`
- GPT-5.5's Round-02 critique/signoff: `.arch_skill/model-consensus/codex-dock-live-update-architecture-20260601T001659Z/round-02/model-b-final.md`

GPT-5.5 converged on:
- existing live proof harness should become mandatory, scheduled, drift-gated, and retained;
- no new framework;
- first-class architecture rules: live failures fail closed, snapshot generation guard, explicit Archive reconcile;
- heartbeat should be made real;
- `itemsView:"full"` should apply only to Thread Detail history and remain off relay card-order proof calls;
- minimal drift gates: route registry/dispatch parity, schemaVersion/DTO parity, executable doc-command gate, proof-result schema gate, plus current contract checks.

GPT-5.5's material correction:
- The harness exists, but saying it exists "in full" is too strong. It has enforcement holes.
- `--turn-items-view` exists in `scripts/dock-relay-sync-audit.mjs`, but the detail `thread/turns/list` request does not actually send `itemsView`.
- Proof JSON has `schemaVersion`/`kind`, but there is no proof-result JSON schema file, so the proof-result schema gate is needed work.

Maximize parallelism by using parallel agents. Do not invoke skills that spawn subagents.

Output Contract
Return:
- final revised proposal;
- explicit requirement coverage;
- explicit statement of whether you agree with GPT-5.5;
- remaining disagreement, if any;
- evidence for any repo-dependent claim;
- whether the parent can write `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md` from the consensus now.

Stop instead of continuing if agreement would require dropping a hard requirement, inventing a new pathway without evidence, or hiding an unresolved decision.
