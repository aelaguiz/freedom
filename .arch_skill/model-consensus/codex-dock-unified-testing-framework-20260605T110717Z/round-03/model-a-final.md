**Yes — I sign off.** This candidate preserves the user's goal, satisfies every hard requirement, teaches no nonexistent commands, and reflects my actual agreement. It also resolves the doc-form question better than my round-1 position did: a short evergreen `docs/TESTING.md` that lists only real commands gives the "how to use it will always be discovered" requirement an immediate home, while the dated plan owns the future architecture — and the proposed/not-yet-existing marking keeps both honest.

Specifically, it carries both items I held firm on:
- ✅ **Corpus is a required plan item** (the 900-thread/stale complaint), framed leanly with `scripts/codex-dock-isolated-home.mjs` as the recommended owner.
- ✅ **Tiers marked proposed/future; AGENTS.md keeps real current commands.**

And it reflects every softening I converged to: dated-doc-not-evergreen-now, demote-don't-delete, keep latency proofs bespoke, rename off `test-realtime`, single scenario SSOT with `file-change-review` resolved.

One tiny decisiveness nudge, not a correction: the user demanded the plan be "fully specified," so I'd drop "or equivalent" and have the plan commit to one concrete name set — `test-smoke` / `test-full` / `test-overtime` — rather than leaving the over-time tier name open. The plan can still note it's bikeshed-able at implementation.

**Residual risks to bake into the dated plan (none block sign-off):**

1. 🧠 **Doc lifecycle / self-retirement.** The fold/delete ledger must include the *dated plan's own* retirement: once the framework lands, fold its content into `docs/TESTING.md` and delete the dated plan. Otherwise we breed exactly the stale dated trio this effort is cleaning up.

2. ⚠️ **Pending done-gates are still outstanding.** This consensus is plan *content* only. The user's explicit done-criteria — a fresh Cursor Composer 2.5 consult for architectural purity **and** a pass through the `plan-audit` skill — still must run on the written plan before stopping for review. The consensus doesn't satisfy those.

3. 🔧 **Corpus must stay completion-grade and the judge likely needs hardening.** The synthesized large/stale home must drive the **real relay/projection path**, not a mock, or it violates the proof doctrine the plan is enshrining. Synthesizing realistic homes is the riskiest build item, and at ~900 rows the judge's O(n) sweep/lag math can throw false fails — the plan should name "make the over-time judge trustworthy at scale" as part of that tier's definition of done, not a free byproduct.

4. 🧠 **"Exhaustive" implies a coverage audit, not just scale.** The user asked to test real-world cases "exhaustively." Running the existing ~19 scenarios at scale isn't the same as proving the scenario set *is* the real-world set. The plan should include a scenario-coverage-gap step so "exhaustive" is earned, not assumed.

Net: converged. Write the dated plan + short `docs/TESTING.md` + the AGENTS.md/README pointers as specified, fold the four residual risks into the plan's body, then run the Composer consult and plan-audit before handing to the user.