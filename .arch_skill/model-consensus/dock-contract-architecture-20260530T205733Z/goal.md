# Model Consensus Goal - Dock Contract Architecture

## Raw Goal

work with $model-consensus opus 4.8 max and gpt 5.5 xhigh to I want them to design an architecture that is the world's most elegant, that keeps these contracts aligned architecturally. So I don't want a bunch of lint that checks to make sure we're not violating the rules. like I want architectural alignment that creates a single source of truth and makes them very drift proof. I want it to be the most beautiful and elegant architecture they can possibly imagine. and it should solve this codex.clientOrderRootCause issue and also a whole variety of issues that may emerge, but it should not lose the performance characteristics that we've worked so hard to get in which the massive data payloads like don't fucking overwhelm the client and the incremental updates and all these things that we've built, it can't lose those but it should become incredibly elegant and it should require a fairly large refactor to achieve maximum elegance. and they should save this out into a new doc once they're in complete alignment. do not implement it, but it should be maximally elegant. They should say that they cannot imagine a more perfect architecture that supports everything we're trying to do, but prevents contract drift and supports the feature set as my intended use case, right? So they have to understand the user experience I'm trying to build. They have to understand what this app is for. and if they don't then they can't possibly design like the maximally elegant solution. They're just looking at abstractions and they cannot do that properly Do not implement, save everything out as a new doc in the docs directory.

## Faithful Goal Brief

Design, through a two-model consensus process, a maximally elegant Codex Dock architecture that makes the Dock row/list/detail contracts drift-proof by construction, not by lint-only checks. The architecture must solve the current `codex.clientOrderRootCause` failure, preserve the hard-won large-payload and incremental-update performance characteristics, and support the intended iPhone user experience: a fast personal operations dashboard for thousands of Codex threads across hosts, with reliable newest ordering, useful row summaries, resilient connectivity, archive/detail workflows, and real updates.

The final deliverable is one new Markdown architecture document under `docs/`. No production implementation is allowed in this goal.

## Hard Constraints

- Do not implement code.
- Save the final aligned architecture as a new doc under `docs/`.
- Use model-consensus with:
  - Opus 4.8 max
  - GPT 5.5 xhigh
- Require both models to understand the product/user experience before proposing abstractions.
- Preserve high-scale performance: bounded first payloads, incremental updates, client responsiveness, and no massive raw history payload pushed to the phone.
- Prefer architectural alignment and a single source of truth over lint or after-the-fact rules.
- A large refactor is acceptable if it produces the cleanest architecture.

## Repo And Issue Context

- Work root: `/Users/aelaguiz/workspace/codex-client`
- Related upstream Codex source: `/Users/aelaguiz/workspace/codex`
- Current root-cause artifact for `codex.clientOrderRootCause`: `docs/CODEX_DOCK_CLIENT_ORDER_ROOT_CAUSE_2026-05-30_WORKLOG.md`
- Product orientation starts in `README.md`.

## Desired Output

The consensus output should be suitable to turn into:

`docs/CODEX_DOCK_CONTRACT_ALIGNED_ARCHITECTURE_2026-05-30.md`

The doc must include the agreed architecture, user experience model, single-source-of-truth contract, relay/client boundaries, stream protocol shape, projection pipeline, verification strategy, migration plan, rejected alternatives, and explicit signoff from both models that they cannot imagine a better architecture for these goals after reading the evidence.
