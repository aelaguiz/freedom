# Model Consensus Summary: Codex Dock Identity Drift Architecture

Date: 2026-06-02

Status: converged

## User Ask

Create the most elegant permanent architecture plan for the outbound duplicate
message / identity drift issue class. Do not implement yet. Save the plan on
disk and cross-link it with the bug doc.

## Participants

- Model A: `claude-opus-4-8`, effort `max`
- Model B: `gpt-5.5`, effort `xhigh`

## Artifacts

- Round 1 Model A events:
  `.arch_skill/model-consensus/codex-dock-identity-architecture-20260602T140852Z/round-01/model-a-events.jsonl`
- Round 1 Model B final:
  `.arch_skill/model-consensus/codex-dock-identity-architecture-20260602T140852Z/round-01/model-b-final.md`
- Round 2 Model A events:
  `.arch_skill/model-consensus/codex-dock-identity-architecture-20260602T140852Z/round-02/model-a-events.jsonl`
- Round 2 Model B final:
  `.arch_skill/model-consensus/codex-dock-identity-architecture-20260602T140852Z/round-02/model-b-final.md`

Claude final text is stored in the JSONL `type:"result"` event's `result`
field.

## Consensus

The best architecture is a strict finish-the-cutover plan:

```text
raw Codex adapters
  -> relay projection engine
  -> projection cache/store keyed by sourceHostID + view + viewParamsKey + contractFingerprint
  -> projection streams: thread-card, thread-detail
  -> Swift projection appliers
  -> render-only SwiftUI
  -> retained relay witness proof
```

Both models agreed that the plan should:

- make `scripts/dock-relay-projection-engine.mjs` the only production identity
  owner
- close handshake, host namespace, revision, view-parameter, schema, witness,
  proof, and fixture side doors
- reject Swift dedupe, pending-row/clientMutationID/transaction machinery,
  extra streamed projection views for health/archive-cleanup/host-registry, and
  a universal store rewrite as required work
- use one shared Swift apply law without requiring a giant generic rewrite for
  its own sake

## Written Plan

The final plan is:

`docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md`

The bug doc cross-link was added to:

`docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`
