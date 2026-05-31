Mission

Review Model A's first-pass proposal as a smart collaborator. Your goal is not
to win; it is to converge on the smallest correct simulator displayed-UI proof
design.

Inputs to read

- Goal: `.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/goal.md`
- Your previous proposal: `.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/round-01/model-b-final.md`
- Model A proposal: `.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/round-01/model-a-final.md`

Focus questions

- Should the first implementation use a sibling Node orchestrator/judge that
  imports `dock-relay-sync-audit.mjs`, or should it extend that script directly?
- Given SwiftUI lazy lists, what exact scope is honest for Dock row set proof:
  full list every sample, watched rows plus stable checkpoint sweeps, or
  something else?
- Is passive real-home over-time testing enough for the first completion proof,
  or does completion require deterministic scenario actuation first?
- Is accessibility-tree interval sampling enough for UI lag, or do we need
  app-emitted render timestamps or `waitForStringValue` timings?
- What is the minimum instrumentation needed, if any, to compare literal row
  and detail state without logging prompt text, transcript text, or raw bodies?

Quality bar

If Model A is better, adopt it. If your own first pass is better, defend only
with repo evidence. Reject any design that creates a second source of truth,
uses mocks as proof, hides lag as eventual success, or drops the literal
display requirement.

Maximize parallelism by using parallel agents. Do not invoke skills that spawn
subagents. Design only; do not edit files.

Output contract

Return:

- agreements
- disagreements
- simplifications you recommend
- repo evidence that decides the disagreements
- revised proposal
- whether you are ready to sign off
