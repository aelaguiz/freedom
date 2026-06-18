I now have enough evidence, directly verified, to commit a first-pass architecture. Three load-bearing facts are confirmed by my own reads:

- **The "scale corpus" generator does not exist.** `scripts/codex-dock-isolated-home.mjs` is a *cloner* (defaults to `--thread-count 1`, clones real threads under `--max-rollout-bytes`; lines 14-15, 38-39, 90-92, 142-189). It has **no** staleness knob and **no** change-rate knob. So "900 threads, many changing, some stale" has no first-class producer today.
- **Scenario list is genuinely triplicated and already diverged.** Fixture `SUPPORTED_SCENARIOS` (20, includes `file-change-review` at `dock-relay-controlled-simulator-fixture.mjs:36`), matrix `DEFAULT_REQUIRED_SCENARIOS` (19, `dock-relay-controlled-simulator-matrix.mjs:12`) + `SCENARIO_REQUIREMENTS` (:36), and `Makefile:111` + its per-scenario `case` block. `file-change-review` is implemented and fixture-supported but the matrix never gates it.
- **No evergreen testing doc; no umbrella test target.** Only datestamped trios (PLAN + IMPLEMENTATION_LOG + PLAN_AUDIT; REFERENCE + PLAN_AUDIT + WORKLOG). `make test-smoke/full/realtime` do not exist. Proof doctrine (`:4500` ban, scripted-scenario ban, routes-required) lives in `proof-report-contracts.mjs:36,186,189-190,198` — in code, not docs.

Here is my first-pass position.

---

# First Pass — Unified Codex Dock Testing Framework (Collaborator: Opus 4MX)

**Net:** The test *layers* are mostly healthy and already canonical. The incoherence is four specific things: (1) no named run-tiers, (2) a triplicated scenario registry, (3) no real large/stale/over-time corpus, (4) testing knowledge scattered across datestamped worklogs. The lean fix is a **thin spine + one scenario SSOT + one corpus generator + one evergreen doc**, plus deletions. This is a refactor-and-unify, **not** a new test runner.

## Proposed architecture (smallest that satisfies every hard requirement)

**Keep three runners exactly as they are** — they are already the right tools and AGENTS.md forbids inventing a second command surface:
- Swift logic: `swift test` over `CodexDockTests/` (mock/fixture-based via the canonical `DockStoreTestSupport.swift`, `ThreadDetailStoreTestSupport.swift`).
- Relay logic: `node --test` over `scripts/*.test.mjs` (canonical `dock-relay-test-helpers.mjs`).
- Contract SSOT: `npm run contract:check` (+ `contract:generate`) over `contract/**`, which generates the Swift DTO. This already binds Node↔Swift shapes.
- Over-time proof engine: the relay-fixture → Swift accessibility sampler (`CodexDockDisplayedSyncProofTests` + `DisplayedUICaptureSupport.swift`) → Node judge (`dock-relay-simulator-ui-sync-proof.mjs`) → matrix aggregator. This is the crown jewel; keep it.

**Add four things, delete a lot:**

1. **A spine of three umbrella Makefile targets** (the entire "easy to run" story):
   - `make test-smoke` → `contract:check` + `swift test` + `test:relay` + `test:host-service`. No simulator. The fast pure-logic gate.
   - `make test-full` → smoke + `app-test` (XCUITest logic on sim) + one `sim-ui-sync-proof` (real relay, real home, sampled over time). One realistic end-to-end pass.
   - `make test-realtime` → `sim-ui-controlled-matrix-proof` across the whole scenario catalog **under a large/stale scale profile**, plus `sim-ui-isolated-scenario-sync-proof`. The over-time + scale gate that answers the headline complaint.
   - Physical (`make iphone-17-pro` / `iphone-14`) stays a **named, separate, manual** apex tier — not folded into automation (hardware + human + WebDriverAgent-blocked per AGENTS.md). Existing granular targets remain as the building blocks these compose.

2. **One scenario catalog = single SSOT.** Collapse the three lists into `scripts/dock-relay-scenarios.mjs` exporting `{name, run, timing:{durationMs,holdMs}, requirements:{minTransitionChecks,…}}`. The fixture and matrix `import` it; the Makefile reads the list and per-scenario timing via a tiny `node scripts/dock-relay-scenarios.mjs list|timing <name>` CLI instead of hardcoding `:111` and the `case` block. (Optional refinement: split the *metadata* into a JSON the Makefile can read directly, with the JS catalog attaching `run` functions — keeps timing/requirements declarative.) Acceptance proof: `git grep` finds the scenario set in exactly one place, and `file-change-review` is either gated by the matrix or deleted.

3. **One canonical large/stale/changing corpus generator** — the only genuinely new component, and the actual root of "passes small, breaks at 900." Extend `codex-dock-isolated-home.mjs` (it already owns the SQLite/rollout schema) with a synthesize mode: `--thread-count 900 --stale-fraction --changing-fraction` producing a Codex home with a realistic large starting state and a marked set of stale + actively-mutating threads. The over-time *mutation* engine already exists (relay sync-audit `rapid-mutations`/`thread-activity`); the corpus only needs to supply the large/stale *initial* state. A `CODEX_DOCK_SCALE_PROFILE = small|large|huge` selects the numbers and feeds `test-realtime`.

4. **One evergreen doc + AGENTS.md section** (discovery). New `docs/TESTING.md` (un-datestamped, living) is the single home: the tier taxonomy, the proof doctrine lifted out of code, the scenario-catalog location, the four "how to add" recipes, artifact paths, and pass/fail/blocked criteria absorbed from the runbook. AGENTS.md gets a short **"Testing And Proof"** section after "Service Path" naming the four tiers + doctrine + pointer to `docs/TESTING.md`, and the Docs Map lists it.

## Evidence read and why it matters
- `Makefile` (full, 551 lines) — confirms ~60 granular targets, no umbrella tier, and the over-time proof orchestration (`sim-ui-sync-proof:480`, `sim-ui-controlled-matrix-proof:498`, latency proofs `:284`/`:391`). Why: the spine must compose these, not replace them; the Makefile is the command SSOT.
- `package.json:6-11` — `test`/`test:relay`/`test:host-service`/`contract:*` already enumerate the logic surface. Why: `test-smoke` is just these composed; nothing new needed there.
- `codex-dock-isolated-home.mjs:14-92,142-189` — proves the corpus is a cloner with no stale/change control. Why: my headline fix is net-new generation, and I won't pretend it's just wiring.
- `dock-relay-controlled-simulator-fixture.mjs:32-36`, `dock-relay-controlled-simulator-matrix.mjs:12-36`, `Makefile:111`+`:499` — proves the triplication and the `file-change-review` divergence. Why: this is the "add-a-test is not obvious" problem and a live bug.
- `proof-report-contracts.mjs:36,186,189-190,198` — proof doctrine (`:4500` ban, scripted-scenario ban, routes-required) is enforced in code. Why: the doctrine is real and good; it must be surfaced in AGENTS.md/`docs/TESTING.md`, not reinvented.
- `CodexDockTests` + `CodexDockUITests` sweep — confirms unit/integration layers are well-factored around canonical fixtures and the UI sampler is scenario-agnostic. Why: don't churn healthy layers; adopt their fixtures as canonical.
- `docs/` listing — only datestamped trios exist. Why: an evergreen `docs/TESTING.md` is the correct owner path; the trios are delete/demote candidates.

## Existing paths/patterns to adopt as canonical
- Fixtures: `CodexDockTests/DockStoreTestSupport.swift`, `ThreadDetailStoreTestSupport.swift`; relay `scripts/dock-relay-test-helpers.mjs`.
- Over-time proof spine: `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` + `DisplayedUICaptureSupport.swift` (sampler) → `scripts/dock-relay-sync-audit.mjs` (relay truth) → `scripts/dock-relay-simulator-ui-sync-proof.mjs` (judge) → `dock-relay-controlled-simulator-matrix.mjs` (aggregate).
- Contract SSOT: `contract/projection/**` + `generate-dock-thread-card-contract.mjs` + `check-projection-contract.mjs`; proof SSOT `contract/proof/**` + `proof-report-contracts.mjs`. Keep scenario-catalog (behavior) and proof-schema (report shape) as **distinct** SSOTs.

## Paths to delete / demote / stop using (acceptance proof)
- **Delete (git is the archive):** `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_PLAN_AUDIT.md`, `..._IMPLEMENTATION_LOG.md`, `..._WORKLOG.md`, and the two `..._PLAN_AUDIT.md` siblings; fold then delete `CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md` and `CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md` into `docs/TESTING.md`.
- **Collapse triplication:** the scenario lists at `Makefile:111`+`:499`, fixture `:32`, matrix `:12`/`:36` → one catalog. Proof: scenario set lives in one file.
- **Fold the bespoke latency mini-framework:** `sim-ui-client-rename-proof` (`Makefile:284-389`) and `sim-ui-user-message-latency-proof` (`:391-475`) + their `dock-relay-*-latency-fixture.mjs` become scenarios under the one controlled-scenario harness; delete ~200 lines of duplicate ready/stop orchestration once equivalents pass. *(Lower-confidence — see risks.)*
- **Demote to diagnostic-only (name them non-completion-grade in the doc, keep as tools):** `sim-ui-dump`, `CodexDockCurrentUIDumpTests`, `relay-doctor`, `relay-debug-bundle`, `relay-host-compare`, `sim-debug-bundle`, `device-debug-bundle`, `sim-logs`, `device-logs`.

## How the framework exposes smoke / full / real-time-over-time
- **Smoke** = `make test-smoke` (contract + swift + relay + host-service; no sim).
- **Full** = `make test-full` (smoke + app-test + one real-relay over-time sync proof).
- **Real-time over time** = `make test-realtime` (full scenario catalog via the matrix, run under `CODEX_DOCK_SCALE_PROFILE=large` with stale + changing fractions; plus isolated-home scenario proof). This is where "900 threads, many changing, some stale" is exercised exhaustively over time.
- **Physical** = `make iphone-17-pro`/`iphone-14`, documented as the manual apex.

## How new scenarios/tests are added
- **Swift unit/integration:** add `CodexDockTests/<Name>Tests.swift`, reuse the support fixtures; auto-discovered; runs in smoke.
- **Relay test:** add `scripts/dock-relay-<name>.test.mjs`, reuse `dock-relay-test-helpers.mjs`, append to `package.json:test:relay`; runs in smoke.
- **Contract change:** edit/add schema+fixture under `contract/`, run `contract:generate` then `contract:check`; runs in smoke.
- **Over-time scenario:** add one entry to `scripts/dock-relay-scenarios.mjs` (name + timing + requirements) and implement its `run<Name>Scenario`; it then appears automatically in the fixture, matrix, and Makefile list; runs in realtime.

## What AGENTS.md / README / docs must say for discovery
- AGENTS.md: new **"Testing And Proof"** section — the four tiers and their commands, the proof doctrine (no `:4500`/mocks/screenshots/one-shot as completion proof; relay-route evidence required), pointer to `docs/TESTING.md` and the scenario catalog; reframe the existing "smallest relevant check first" list (`:89-98`) under the tiers; add `docs/TESTING.md` to the Docs Map.
- README: replace the "Exhaustive Sync Harness" fragment (`:54`) with a short pointer to `docs/TESTING.md`; keep runbook detail in the doc, not scattered.
- `docs/TESTING.md`: the canonical, evergreen home (taxonomy, doctrine, catalog, add-a-test recipes, artifacts, pass/fail/blocked).

## Risks / open questions
1. **Scale tier will likely surface judge bugs before app bugs.** The judge's sweep/lag math is O(n) and pins UI rows to a single relay moment; at 900 rows, partial sweeps and per-row capture skew can produce false fails. "Make the judge trustworthy at scale" (per-row capture timestamps, sweep-completeness accounting) is part of `test-realtime`'s definition of done — not free.
2. **Corpus realism vs. cost.** Synthetic 900-thread homes must look real enough to exercise the real code paths; and `test-realtime` (matrix × passes × scale × sim builds) is heavy — needs a scenario-subset / `min-passes` knob so it's runnable on demand.
3. **Latency-proof fold may lose signal.** The rename/user-message proofs capture optimistic-UI-budget and upstream-ack timing the generic sampler may not. Confirm the generic driver can carry those assertions before deleting the bespoke targets.
4. **Smoke tier boundary is empirical.** If the SwiftPM build dominates, `swift test` may belong in `full`, not `smoke`. Draw the line by measured runtime, not assertion.

## What I need from the other model (GPT-55XI) to converge
1. Agreement that this is **spine + registry-unification + corpus + doc**, not a new runner/framework rewrite. If you propose replacing `node --test`/XCTest/Makefile or a bespoke harness, I'll push back as kitchen-sink.
2. Agreement on the **single scenario-catalog location** (`scripts/dock-relay-scenarios.mjs` consumed by Node + a thin Makefile CLI) and that the Makefile stops hardcoding the list.
3. Agreement that the **scale/stale corpus + judge-hardening is the true center of gravity** (the headline pain), versus merely adding more scenarios.
4. A decision on the **latency proofs** (fold vs. keep bespoke) given risk #3.
5. Agreement on the **doc home** (`docs/TESTING.md` evergreen) and that the datestamped sync-test trios are deleted/folded.
6. Your view on **smoke composition** (swift test in or out) pending a real timing measurement.

I'll hold here for your first pass, then critique against this.