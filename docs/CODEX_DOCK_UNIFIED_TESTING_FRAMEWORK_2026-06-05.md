# Codex Dock Unified Testing Framework Plan

Date: 2026-06-05
Status: plan
Owners: Amir, Codex
Primary guide now: `docs/TESTING.md`
Scenario coverage ledger: `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`
Model-consensus artifacts:
`.arch_skill/model-consensus/codex-dock-unified-testing-framework-20260605T110717Z/`

## Direct Answer

Codex Dock should keep `Makefile` as the single public command surface and
unify testing by adding three future Makefile targets:
`test-smoke`, `test-full`, and `test-overtime`.

The current repo already has strong building blocks: Swift tests, Node relay
tests, contract checks, simulator UI proof, physical install/config targets,
proof-report schemas, and a current failure-class coverage ledger. The missing
pieces are a clear tiered entrypoint, one scenario source of truth, a
large/stale/changing corpus generator for the 900-thread class of failures, and
durable proof that every historical failure class in
`docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` is either covered, explicitly
planned, or explicitly out of scope.

This plan does not add those targets yet. Until they exist in `Makefile`, use
the current commands in `docs/TESTING.md`.

## North Star

A future agent can answer two questions without searching history:

1. "How do I prove this change is safe?"
2. "Where do I add the next real-world test scenario?"

The answer should route through `AGENTS.md`, `docs/TESTING.md`, and `Makefile`.
The framework must prove not only isolated unit behavior, but also real app
behavior over time: many threads, stale threads, actively changing threads,
detail updates, command acknowledgement, reconnect, foreground resume, request
cards, archive transitions, source refresh, multi-host isolation, and physical
phone path boundaries.

## Non-Goals

- Do not create a new top-level runner beside `Makefile`.
- Do not make `package.json`, `Package.swift`, or `project.yml` the public test
  surface. They remain sub-manifests.
- Do not present future targets as current commands.
- Do not restore the old raw authenticated `ws://127.0.0.1:4500` app-server as
  a normal app or proof path.
- Do not treat mocks, screenshots, preview rows, loopback-only paths, status
  endpoints, debug bundles, or one-shot UI dumps as completion proof.
- Do not delete current accurate docs before the replacement has absorbed their
  useful content.

## Current Inventory

Public command owner:

- `Makefile`: service, simulator, app, proof, latency, and device targets.

Sub-manifests:

- `package.json`: `contract:check`, `test:relay`, `test:host-service`, and
  `test:docs`, and aggregate `test`.
- `Package.swift`: SwiftPM package and `CodexDockTests`.
- `project.yml`: XcodeGen source for `CodexDockApp`, `CodexDockTests`, and
  `CodexDockUITests`.

Contract and proof truth:

- `contract/projection/**`: projection envelope, Dock card, Thread Detail, and
  witness schemas and fixtures.
- `contract/proof/**`: relay sync audit, simulator UI sync, controlled
  scenario, matrix, route name, field name, and UI dump schemas.
- `scripts/check-projection-contract.mjs` and
  `scripts/check-proof-report-contracts.mjs`: contract gates.
- `scripts/proof-report-contracts.mjs`: proof-report assertions, including the
  raw `:4500` rejection and scripted-scenario rejection.
- `scripts/codex-dock-test-scenario-coverage.test.mjs`: static docs/proof
  guard that fails if root bug docs or controlled simulator scenarios are not
  represented in `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`.

Swift test owners:

- `CodexDockTests/AppServerClientTests.swift`
- `CodexDockTests/DockStoreTests.swift`
- `CodexDockTests/DockStoreTestsProjection.swift`
- `CodexDockTests/DockStoreStreamTests.swift`
- `CodexDockTests/ThreadDetailStoreTests.swift`
- `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`
- `CodexDockTests/ProjectionReducerTests.swift`
- `CodexDockTests/ProjectionRuntimeTests.swift`

Simulator proof owners:

- `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`
- `CodexDockUITests/DisplayedUICaptureSupport.swift`
- `scripts/dock-relay-sync-audit.mjs`
- `scripts/dock-relay-simulator-ui-sync-proof.mjs`
- `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `scripts/dock-relay-controlled-simulator-matrix.mjs`

Physical proof owners:

- `rtk make iphone-17-pro`
- `rtk make iphone-14`
- `rtk make device-install`
- `rtk make device-install-all`
- `rtk make device-config-verify`
- `rtk make device-config-verify-all`

## Current Problems

### 1. No Tiered Public Entry Point

The repo has many accurate granular targets, but no single current
`test-smoke`, `test-full`, or `test-overtime` target. That makes future agents
choose from scattered commands and increases the chance of claiming completion
from a weaker proof.

### 2. Scenario Knowledge Is Duplicated

Controlled simulator scenarios are split across:

- `SUPPORTED_SCENARIOS` in `scripts/dock-relay-controlled-simulator-fixture.mjs`
- `DEFAULT_REQUIRED_SCENARIOS` and `SCENARIO_REQUIREMENTS` in
  `scripts/dock-relay-controlled-simulator-matrix.mjs`
- `SIM_UI_CONTROLLED_MATRIX_SCENARIOS` and the per-scenario timing `case` block
  in `Makefile`

That duplication has already drifted: `file-change-review` is supported by the
fixture but is not part of the default matrix.

### 3. No Large/Stale/Changing Corpus

`scripts/codex-dock-isolated-home.mjs` can clone real threads with
`--thread-count` and `--max-rollout-bytes`, but it does not synthesize a
900-thread corpus, does not mark stale fractions, and does not configure
actively changing fractions. That means current proof can pass small controlled
cases while missing the user's 900-thread, stale, changing-data failure class.

### 4. Proof Doctrine Is Scattered

The important proof rules are enforced in code and repeated in dated docs, but
they are not concentrated in a current testing entrypoint. Examples:

- Raw `:4500` cannot satisfy proof.
- Scripted Dock stream scenarios cannot satisfy live-update proof.
- Passing proof reports require route evidence.
- `thread/detail/read` and `projection/witness/read` are not production app UI
  completion proof.

### 5. Existing Dated Docs Are Too Narrow As The Entry Point

`docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md` and related sync docs
are useful narrow references, but they are no longer the top-level testing
map. They should be demoted behind `docs/TESTING.md` and eventually folded or
deleted once their useful details are carried forward.

### 6. Latency Proofs Are Bespoke

`sim-ui-client-rename-proof` and `sim-ui-user-message-latency-proof` duplicate
some controlled proof orchestration. They should not be deleted yet because
they carry optimistic UI budget and upstream acknowledgement timing signals
that the generic matrix may not currently prove.

### 7. Historical Failure Classes Are Not All Runtime-Gated Yet

The 2026-06-05 docs review inventoried 280 Markdown docs and folded their
durable regression signal into
`docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`. That ledger exposed additional
coverage gaps that the original live-sync plan did not name strongly enough:

- Pinned `Unpin` action survival while live Dock updates arrive.
- System Health must not turn a fresh row window such as `Showing 250 of 964`
  into false broad feature degradation.
- Private `stdio://` runtime rows must not imply detail attachability.
- Physical phone claims must prove current installed build/config state or
  record the exact blocker.
- Large live Thread Detail payloads must keep using compact read, paged turns,
  and compact resume.

The current `rtk npm run test:docs` guard catches coverage-ledger drift, but it
does not replace the missing runtime scenarios. Those cases must be added to
the scenario catalog, Swift/UI tests, or physical proof flow before
`test-overtime` can claim exhaustive regression coverage.

## Target Framework

### Public Makefile Tiers

Add these concrete Makefile targets.

`test-smoke`:

- Runs `rtk npm test`.
- Runs the focused Swift filters:
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
- Does not boot a simulator.
- Purpose: fast local proof for contract, relay, host-service, docs coverage,
  and main Swift state surfaces.

`test-full`:

- Runs `test-smoke`.
- Runs `rtk swift test`.
- Runs `rtk make app-test SIM='iPhone 17'`.
- Runs one real relay-backed over-time proof:
  `rtk make sim-ui-sync-proof SIM='iPhone 17'`.
- Purpose: broad local plus generated-project and one end-to-end simulator
  path.

`test-overtime`:

- Runs the complete controlled simulator matrix through the real app sampler.
- Uses `SIM_UI_CONTROLLED_MATRIX_PASSES=2`,
  `SIM_UI_SYNC_CHECKPOINT_SWEEP=1`, and `MAX_UI_LAG_MS=2000` by default.
- Runs against a large/stale/changing corpus through a scale profile.
- Exercises all cataloged real-world scenarios, including detail, Dock,
  Archive, command acknowledgement, stale state, reconnect, foreground resume,
  source refresh, multi-host isolation, file change review, request cards,
  rapid mutation, and large list order.
- Purpose: completion-grade over-time proof for "it stayed correct while data
  changed," including the 900-thread class of failures.

Physical apex:

- Keep physical proof as explicit device targets, not an automatic dependency
  of the above tiers:
  - `rtk make iphone-17-pro`
  - `rtk make iphone-14`
  - `rtk make device-install-all`
- A physical claim still needs the installed app connected to relay-backed
  `:4510`, rendering real `DockThreadCard` rows, and showing offline/error UI
  when that same host path is unavailable.

### Single Scenario Source Of Truth

Create one scenario catalog that both Node proof code and `Makefile` derive
from. The recommended owner is:

```text
scripts/dock-relay-scenarios.mjs
```

The catalog should define each scenario once with fields like:

```text
id
description
surfaces
defaultDurationMS
defaultHoldMS
defaultSampleMS
scaleProfile
requiredRoutes
requiredRouteCounts
minScenarioTransitionChecks
minDetailTransitionChecks
minCheckpointSweeps
minDetailSweeps
minDockOrderChecks
minDetailMessageOrderChecks
latencyAssertions
```

The controlled fixture should import the catalog to know which scenarios exist
and how to run them. The matrix verifier should import the catalog to know the
required scenarios and their pass conditions. The Makefile should derive the
default scenario list and per-scenario timing from the catalog, likely through
a small CLI mode such as:

```bash
rtk node scripts/dock-relay-scenarios.mjs list
rtk node scripts/dock-relay-scenarios.mjs timing <scenario-id>
```

Exit criteria:

- The scenario set is defined in exactly one place.
- `file-change-review` is either included in the default matrix with
  requirements or deleted from the fixture.
- `rtk npm run contract:check` or `rtk npm run test:relay` catches drift
  between fixture, matrix, and Makefile derivation.

### Large/Stale/Changing Corpus

Extend `scripts/codex-dock-isolated-home.mjs` so `test-overtime` can run
against a realistic isolated Codex home.

Recommended shape:

```bash
rtk node scripts/codex-dock-isolated-home.mjs synthesize \
  --thread-count 900 \
  --stale-fraction 0.15 \
  --changing-fraction 0.20 \
  --archive-fraction 0.10 \
  --request-card-fraction 0.05 \
  --file-change-fraction 0.05 \
  --output-home /tmp/codex-client/<run>/codex-home \
  --json-out /tmp/codex-client/<run>/isolated-home.json
```

Add a Makefile profile variable:

```text
CODEX_DOCK_SCALE_PROFILE=small|large|huge
```

Proposed profile defaults:

- `small`: 25 threads, low stale/change fractions, for debugging.
- `large`: 900 threads, stale and changing fractions enabled, for the user
  complaint class.
- `huge`: larger than 900, opt-in only, for capacity investigation.

The corpus must drive the real relay and projection path. It must not become a
mock-only or fixture-only proof path.

The judge must be hardened for scale before `test-overtime` can be trusted:

- Track sweep completeness.
- Record capture timestamps for large row sweeps.
- Keep the `MAX_UI_LAG_MS=2000` budget meaningful under long captures.
- Fail closed when structured UI state is missing.
- Separate true app lag from judge sampling skew.

The scale proof report must expose enough data to debug false failures:

```text
scaleProfile
threadCount
expectedVisibleRowCount
observedVisibleRowCount
sampleCount
sweepStartedAt
sweepCompletedAt
captureDurationMS
maxRelayToUILagMS
maxJudgeSkewMS
incompleteSweepCount
missingStructuredSnapshotCount
artifactBytes
wallClockDurationMS
```

Large-profile acceptance requires zero incomplete sweeps, zero missing
structured snapshots, route evidence for every required route, and
`maxRelayToUILagMS <= MAX_UI_LAG_MS`. The first implementation of
`test-overtime` must record observed wall-clock runtime and artifact size
before it can become a default local recommendation.

### Exhaustive Coverage Audit

"Exhaustive" must be earned. Before `test-overtime` is called complete, create
a scenario coverage audit that maps real-world cases to catalog entries.

The coverage ledger should live at:

```text
docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md
```

The ledger should track:

```text
caseID
surface
user-visible risk
catalogScenarioID
scaleProfile
proofCommand
requiredRoutes
currentStatus
owner
lastProofArtifact
```

The audit must cover at least:

- Dock row identity, ordering, active work, and current-work visibility.
- Archive and unarchive transitions.
- Thread Detail history, live updates, replay pressure, reconnect, and message
  order.
- Server requests and resolved request state.
- User message send, manual send control, optimistic UI, and upstream ack.
- Rename latency and server-side rename acknowledgement.
- File change review visibility and approval flow.
- Stale rows and source refresh failure/recovery.
- Live lease expiry.
- Multi-host isolation.
- Spawn edge and parent-child source behavior.
- Sequence gaps and resync.
- Foreground resume across all surfaces.
- Large list checkpoint and root catch-up window contracts.
- Rapid mutation and bursty updates.
- Physical phone host config and offline/error behavior.
- Pinned-row action stability while live Dock updates arrive.
- System Health route-evidence behavior, including the rule that a fresh
  windowed row set is not service degradation.
- Private runtime capability mismatch, where a row may be visible but not
  attachable through Thread Detail.
- Physical stale-build/runtime state, including installed build number and saved
  host-list proof.
- Large live Thread Detail payload protection through compact read, paged turns,
  and compact resume.

If a real-world case has no catalog entry, add one or explicitly record why it
is out of scope.

`docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` is the current seed of that audit.
It must stay checked by `rtk npm run test:docs` until the scenario catalog can
own the same mapping directly.

## Add-A-Test Rules After The Framework Lands

Swift behavior:

- Add or extend the owning `CodexDockTests/**` file.
- Reuse local test support before adding new fakes.
- Run the narrow Swift filter first, then the relevant tier.

Relay behavior:

- Add or extend a `scripts/*.test.mjs` file.
- Reuse `scripts/dock-relay-test-helpers.mjs`.
- Keep `package.json` as the Node test manifest.

Contract or proof shape:

- Update `contract/projection/**` or `contract/proof/**`.
- Update fixtures with the schema.
- Run `rtk npm run contract:check`.

Over-time scenario:

- Add one scenario catalog entry.
- Add or connect the scenario runner.
- Add matrix requirements in the catalog.
- Add proof-contract fields or route names only when the report contract needs
  them.
- Run the focused scenario proof, then `test-overtime`.

Docs:

- Update `docs/TESTING.md` when a command, tier, scenario add path, proof rule,
  or diagnostic boundary changes.
- Update `AGENTS.md` when future agents need to discover the new rule before
  reading deep docs.
- Keep README as the human orientation layer, not the full testing spec.

## Delete, Demote, And Fold Ledger

Do now:

- Keep old sync docs in place.
- Link `README.md` and `AGENTS.md` to `docs/TESTING.md`.
- Mark older exhaustive sync docs as narrower historical references.

Do during implementation:

- Remove scenario list duplication from `Makefile`,
  `scripts/dock-relay-controlled-simulator-fixture.mjs`, and
  `scripts/dock-relay-controlled-simulator-matrix.mjs` after the catalog owns
  the list.
- Include or delete `file-change-review`; do not leave it fixture-only.
- Fold latency proof targets into the scenario catalog only after equivalent
  optimistic UI and upstream ack assertions exist in the matrix.
- Keep `sim-ui-dump`, status endpoints, logs, and debug bundles as diagnostic
  tools only.
- Keep `projection/witness/read` proof-only and unavailable as app UI evidence.

Do after the framework lands:

- Fold useful content from
  `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md` and
  `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md` into
  `docs/TESTING.md`, then delete or clearly retire the old dated files.
- Fold this dated plan into `docs/TESTING.md` after implementation and delete
  this plan so it does not become another stale parallel source of truth.

## Proof Doctrine

Passing proof must include client-route evidence for the route family the app
uses. The app and phone connect to the Dock relay on `:4510`; they do not
connect directly to a raw authenticated app-server on `:4500`.

Completion proof cannot rely on:

- Screenshots or recordings as the primary proof.
- Fixture or SwiftUI preview rows.
- Mocks, scripted transports, Unix sockets, or loopback-only WebSockets.
- Service status endpoints alone.
- `sim-ui-dump` alone.
- Raw app-server detail side doors as app display truth.
- `projection/witness/read` as production UI evidence.

Physical-phone claims require physical-phone evidence or the exact skipped
command and blocker.

## Implementation Order

### Phase 0 - Documentation Entry Point

Create `docs/TESTING.md`, create this plan, create
`docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`, update `AGENTS.md`, update
`README.md`, and add the fast docs coverage test.

Exit proof:

- `docs/TESTING.md` lists only current commands.
- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` lists current controlled
  scenarios, root bug docs, and doc-mined failure classes.
- `rtk npm run test:docs` fails when a root bug doc or supported controlled
  scenario is not represented in the coverage ledger.
- This plan marks future targets as future.
- `AGENTS.md` and `README.md` point to the testing guide.
- Model consensus, Composer 2.5 Fast fresh consult, and `plan-audit` have been
  run on the written plan; the 2026-06-05 docs-mined regression pass updates
  the plan-audit ledger.

### Phase 1 - Makefile Tier Targets

Add `test-smoke`, `test-full`, and `test-overtime` to `Makefile`, composing
existing targets first.

Exit proof:

- `rtk make -n test-smoke`, `rtk make -n test-full`, and
  `rtk make -n test-overtime` show the expected existing commands.
- `docs/TESTING.md` is updated so the targets are no longer marked future.
- `test-smoke` includes the docs coverage guard through `rtk npm test`.

### Phase 2 - Scenario Catalog

Create the single scenario source of truth and migrate fixture, matrix, and
Makefile derivation to it.

Exit proof:

- Scenario ids are defined once.
- The matrix default list comes from the catalog.
- The Makefile does not hard-code scenario ids or timing in a separate list.
- `file-change-review` is matrix-gated or deleted.
- The catalog absorbs the current coverage-ledger scenario mappings or
  generates them from the same source.

### Phase 3 - Large/Stale/Changing Corpus

Extend isolated-home support to synthesize or assemble realistic large homes
with stale and actively changing fractions.

Exit proof:

- `CODEX_DOCK_SCALE_PROFILE=large` produces a 900-thread class corpus.
- The corpus drives the relay/projection path, not a mock path.
- The judge reports sweep completeness and fails closed on missing structured
  state.

### Phase 4 - Exhaustive Overtime Proof

Run the full scenario catalog against the large/stale/changing corpus.

Exit proof:

- `test-overtime` uses the real simulator app path.
- The matrix runs at least two passes by default.
- `MAX_UI_LAG_MS=2000` is enforced.
- Scenario coverage audit has no unowned real-world case.
- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` has no `gap` or
  `fixture-only-gap` row for an in-scope completion claim.

### Phase 5 - Cleanup And Retirement

Fold stale docs, delete duplicated scenario lists, and remove any old proof path
that became redundant.

Exit proof:

- `docs/TESTING.md` is the living testing guide.
- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` is either generated from the
  scenario catalog or folded into the living testing guide with an equivalent
  guard.
- This dated plan is folded and deleted or explicitly retired.
- Old sync docs no longer appear as the top-level testing entrypoint.

## Validation Status

- Model consensus: complete. Artifacts are under
  `.arch_skill/model-consensus/codex-dock-unified-testing-framework-20260605T110717Z/`.
- Fresh Composer 2.5 Fast consult: complete. Artifacts are under
  `/tmp/fresh-consult/codex-dock-testing-docs-20260605T112739Z-xEXkdd/`.
- `plan-audit`: complete. Audit log:
  `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05_PLAN_AUDIT.md`.
- Docs-mined regression pass: complete. The pass reviewed the repo Markdown
  inventory, created `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`, and added
  `scripts/codex-dock-test-scenario-coverage.test.mjs`.
