I've read both passes. We are close, and GPT's core thesis — Makefile as the single public surface, no new runner — matches my #1 ask. The parent's reframe ("write the docs now, not the framework now") is the key lens, and it corrects parts of *my own* first pass more than GPT's. Here's my critique and a converged docs plan.

## Agreements

✅ **Makefile is the single public test surface. No new runner, no new scenario language.** GPT's thesis and my "keep three runners" land in the same place. Locked.

✅ **Three tiers that wrap the existing Swift / Node / simulator / device paths**, with `package.json`, `Package.swift`, `project.yml`, and the `contract/**` system as sub-manifests. Agreed.

✅ **Proof doctrine is already in code and should be lifted into docs, not reinvented:** no raw `:4500`, no mocks/loopback/screenshots/preview rows/scripted transports/one-shot as completion proof; relay-owned route evidence required. GPT added good specifics I'll adopt — `sim-ui-dump`, `/readyz`/`/statusz`/`/routesz`, debug bundles, `thread/detail/read`, `projection/witness/read` are diagnostic/proof-only, never app-UI completion proof.

✅ **One new docs file is the canonical entrypoint; AGENTS.md gets a short testing section; README points to it; old sync docs stop being the entrypoint.**

✅ **The scenario list duplication is a real problem to resolve to one source** (GPT lists it as a risk; I verified the divergence and the orphaned `file-change-review`).

## Disagreements (several correct *my* first pass)

⚠️ **D1 — Doc form: dated plan doc now, not an evergreen `docs/TESTING.md` now.** My "create `docs/TESTING.md` now" was wrong for this step. The user explicitly asked for "the exhaustive plan put together as a new document in the docs directory," gated by a Composer consult and the plan-audit skill. That artifact is a **dated plan doc**. The evergreen `docs/TESTING.md` is an *end-state deliverable the plan specifies* — created when the work lands, not now. Both-but-sequenced.

⚠️ **D2 — The umbrella targets don't exist; docs must say so.** Both of us wrote `test-smoke/full/realtime` as if real. They are not in the Makefile (I confirmed: no umbrella targets). AGENTS.md is a live instruction file an agent will execute — listing `rtk make test-smoke` today creates a broken command. The plan must mark the tiers **proposed/future**; AGENTS.md keeps pointing at the **real current commands** until the targets merge.

⚠️ **D3 — The large/stale/changing corpus is a required plan item, and GPT omits it.** This is my main substantive hold. The user's headline pain is literally "900 threads, many changing, some stale." I verified the producer does not exist (`codex-dock-isolated-home.mjs` is a cloner, default `--thread-count 1`, no stale/change knob). GPT's plan, as written, would have `test-realtime` re-run the same small controlled scenarios — which is exactly the "isolated tests look good but break at scale" failure the user is complaining about. A plan that omits the corpus does not cover the goal.

⚠️ **D4 — Adopt GPT's catch: `test-realtime` is an ambiguous name.** The repo already has OpenAI Realtime transcription (`CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL`, `dock-relay-realtime-transcription.test.mjs`). Rename the over-time tier — I propose `test-overtime` (or `test-live-sync`).

⚠️ **D5 — Document the single scenario SSOT as the add-a-test path.** GPT's "Adding New Tests → add to fixture, add to matrix, then expose through Makefile" documents the triplication *as* the path. That's the opposite of unifying, and it contradicts GPT's own risk note. The plan should make "edit one catalog entry" the documented path.

## Simplifications I recommend (these shrink both our passes)

🔧 **The immediate docs footprint is exactly: ONE new dated plan doc + small pointer edits to AGENTS.md and README.** The tiers, scenario SSOT, corpus, and evergreen `docs/TESTING.md` are *content inside the plan describing the end state* — not separate docs to create now.

🔧 **Don't create `docs/TESTING.md` yet** — it would be full of commands that don't exist. The plan names it as the end-state home.

🔧 **Defer every deletion to implementation time.** The dated sync docs still describe *current* reality until the framework is built. Demote-by-link now (point README/AGENTS.md at the plan); the plan carries the fold/delete list. This corrects my "delete now," which would have removed accurate current docs before the replacement existed — GPT's "make them historical references" is the right immediate move.

🔧 **Latency proofs: keep bespoke now; fold later only with a signal-equivalence precondition.** They capture optimistic-UI-budget and upstream-ack timing the generic sampler may not. The plan documents them as current canonical latency proofs and lists "fold into the matrix once it can carry latency/ack assertions" as a *conditional* future cleanup. I'm softening from my "fold" to converge.

🔧 **Smoke vs full split by GPT's filter idea:** smoke = `rtk npm test` + the three blessed `rtk swift test` filters; full = the complete `swift test` + `app-test` + one real over-time sync proof. Resolves my open question without needing a timing measurement to write the plan.

## Repo evidence that decides the disagreements

- **Corpus is required and missing (D3):** `scripts/codex-dock-isolated-home.mjs:14-15,38-39,90-92,142-189` — clones N real threads, default 1, bounded by `--max-rollout-bytes`; no staleness or change-rate control. Nothing else produces a large evolving corpus. The user's goal sentence names this exact gap.
- **Targets don't exist (D2):** Full `Makefile` read + `rg '^test|^smoke|^test-'` → no umbrella targets. `package.json:9` already composes `contract:check + test:relay + test:host-service`.
- **Name collision (D4):** `Makefile:53` `CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL`; `package.json:10` `dock-relay-realtime-transcription.test.mjs`.
- **Triplication + orphan (D5):** fixture `SUPPORTED_SCENARIOS` (`dock-relay-controlled-simulator-fixture.mjs:32-36`, includes `file-change-review`), matrix `DEFAULT_REQUIRED_SCENARIOS` (`dock-relay-controlled-simulator-matrix.mjs:12`, excludes it), `Makefile:111`+`:499` case block. `file-change-review` is implemented (`:6874`) but never gated by the matrix.
- **Doctrine in code (agreement):** `proof-report-contracts.mjs:36,186,189-190,198`.
- **Doc form (D1):** `docs/` listing shows only dated trios, no evergreen home; the user's raw goal mandates a "new document in the docs directory" behind a Composer consult + plan-audit gate.

*(One honesty note: GPT cited `project.yml:75` and `StreamReconciler.swift:76`/`ProjectionReducer.swift:147` as owners; I did not independently open those two files. They're plausible and don't change the docs plan, so I accept them as owner pointers without re-verifying.)*

## Revised consensus proposal — the docs plan

**Write now (3 things):**

1. **One dated plan doc** — `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`. Structure:
   - **North star + current-state inventory** (Swift unit, relay, contract, over-time sim proof, physical, diagnostics) with the verified problems: no tiers, triplicated scenarios + orphaned `file-change-review`, no large/stale corpus, scattered dated docs.
   - **Target end state:** the three tiers (`test-smoke`, `test-full`, `test-overtime`) **explicitly labeled "proposed — not yet in the Makefile,"** each defined as a composition of *named existing* targets; physical (`iphone-17-pro`/`iphone-14`) as the manual apex.
   - **Single scenario SSOT** (one catalog the fixture, matrix, and Makefile derive from) as the documented add-a-test path; resolves the divergence and the orphan.
   - **Large/stale/changing corpus** as a required capability with a recommended lean owner (extend `codex-dock-isolated-home.mjs` with synthesize + stale/change fractions) and a `CODEX_DOCK_SCALE_PROFILE` knob feeding `test-overtime`. Flag the judge-hardening risk (O(n) sweep/lag at 900) as part of that tier's definition of done.
   - **Proof doctrine** lifted from code into prose; diagnostic-only list.
   - **Add-a-test recipes** (Swift / relay / contract / over-time scenario).
   - **End-state docs**: an evergreen `docs/TESTING.md` becomes the living home; this dated plan is retired/folded into it once implemented.
   - **Delete/demote/fold ledger** (the dated sync trios, the triplication, the latency-proof fold-with-precondition) as *implementation-time* actions.

2. **AGENTS.md** — add a short **"Testing And Proof"** section that: states the proof doctrine; keeps the **real current commands** (`rtk npm test`, the blessed `rtk swift test` filters, the real `sim-ui-*` proof targets, device targets); and links to the plan doc for the proposed tiers + scenario SSOT. Add the plan doc (and future `docs/TESTING.md`) to the Docs Map. **No vapor commands.**

3. **README.md** — replace the "Exhaustive Sync Harness" fragment (`:54`) with a one-line pointer to the plan doc; mark the dated sync docs as historical references.

**Discoverability contract:** "how to use" = AGENTS.md Testing section + plan doc tier table; "how to add" = the plan's single-catalog recipe. When the framework lands, the evergreen `docs/TESTING.md` inherits both and AGENTS.md gains the real tier commands.

## Ready to sign off?

**Yes on the docs plan above, contingent on GPT's explicit assent to two items:**
1. **The corpus is a required plan item** (the user's headline complaint), framed leanly as a capability + recommended owner — not dropped.
2. **The tiers are documented as proposed/future**, with AGENTS.md keeping real current commands until the Makefile targets exist.

If GPT agrees to those, we're converged — and I'll have moved on doc-form (dated, not evergreen-now), deletions (defer, don't delete now), latency proofs (keep bespoke), and the tier rename, all toward GPT/the reframe. If GPT rejects the corpus, that's a **real unresolved decision** I'd surface to the user rather than paper over, because a plan without it doesn't answer "it breaks at 900 threads."