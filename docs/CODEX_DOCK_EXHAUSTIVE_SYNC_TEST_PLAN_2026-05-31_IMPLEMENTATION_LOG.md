# Codex Dock Exhaustive Sync Test Implementation Log

Plan: `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md`
Audit log: `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_PLAN_AUDIT.md`
Active scope: implement the relay-level sync harness and initial simulator
displayed-UI proof, using only routes and UI paths the client actually uses.
Last updated: 2026-05-31T11:14Z

## Resume Snapshot

- Current state: relay-level harness is implemented and proven on real local
  services for actual client routes, including explicit `dock/resync`. The
  simulator displayed-UI proof now runs through the real `iPhone 17` app path,
  compares literal accessibility samples to the relay/client-route audit
  report, and can run a bounded checkpoint Dock sweep through actual simulator
  UI interactions. Oracle comparison can still fail when local Codex storage
  moves during a long exhaustive audit; those failures are recorded and not
  counted as client-path proof.
- Completion state: not complete overall. The required `$model-consensus`
  design pass for the third simulator displayed-UI leg has converged, an
  initial passive real-path `iPhone 17` displayed-UI proof passes, and the
  first archive/unarchive controlled actuator is now proven both against
  real-home services and an isolated `CODEX_HOME` through the actual `iPhone 17`
  simulator display. The isolated simulator proof now includes one bounded
  checkpoint sweep and isolated relay state database/cache storage under the
  temp service runtime. The archive/unarchive actuator now supports repeated
  transitions, and v5 proved two full cycles, four ordered relay transitions,
  and the rendered simulator display without lag failures. A reusable
  controlled simulator matrix verifier now reads the relay and UI reports for
  each controlled `iPhone 17` slice and fails missing scenarios, failed
  reports, missing required routes, missing transition checks, missing
  checkpoint sweeps, or UI lag over budget. The first matrix pass covered
  8 controlled simulator scenarios with all 8 passing and max rendered UI lag
  1,511 ms under the 2,000 ms budget. The repeatable
  `sim-ui-controlled-matrix-proof` target then ran a fresh second
  `iPhone 17` matrix pass across the same 8 required scenarios with max
  rendered UI lag 1,492 ms, and the combined double-loop matrix gate passed
  16 reports with 2/2 passes per required scenario and max lag 1,511 ms. The
  matrix now also includes a `large-list-checkpoint` scenario that seeds
  18 Dock rows; two `iPhone 17` passes proved the actual checkpoint sweep
  scrolls and finds all 18 rows, and the expanded nine-scenario double-loop
  matrix passed 18 reports with max lag 1,511 ms. The matrix now also includes
  a `detail-history-request` scenario that opens the literal simulator detail
  screen, selects the real `All` message filter, forces `thread/read` plus two
  paged `thread/turns/list` calls plus `thread/resume`, streams a live detail
  update, displays a pending request card, taps the real approval action,
  displays the resolved request state, and sweeps the opened-thread detail
  rows. Two `iPhone 17` passes proved all 9 expected detail rows through the
  actual displayed client path with rendered detail-transition lags of
  767/774/1,717 ms and 760/770/1,704 ms under the 2,000 ms budget; the expanded
  ten-scenario double-loop matrix passed 20 reports with max lag 1,717 ms.
  Multi-thread
  isolated seeding is now implemented and unit-tested, and
  v8 proved a two-thread isolated `iPhone 17` displayed-UI run with a two-row
  checkpoint sweep and 0 ms observed rendered-UI lag under the 2,000 ms budget.
  A controlled simulator fixture target now also proves the `thread-activity`
  scenario through the actual `iPhone 17` app display: the app connects to the
  same temporary relay that the fixture mutates, observes the new-thread and
  new-turn-order transitions within the 2,000 ms UI lag budget, and passes a
  stable three-row checkpoint sweep. The same controlled simulator fixture now
  also proves the `server-request` scenario through the literal `iPhone 17`
  detail UI: the app opens the real Dock row, loads detail through
  `thread/read`, `thread/turns/list`, and `thread/resume`, displays the live
  request card in the default detail view, taps the real request action, and
  displays the resolved state. The rendered request-card lags were 1,114 ms for
  initial visibility and 1,056 ms for resolution, both under the 2,000 ms
  client-visible lag budget. The fixture now also proves the `source-refresh`
  scenario through the actual `iPhone 17` Dock UI: the app displays the cached
  row with an explicit partial/stale host status after upstream failure, then
  displays the recovered fresh row after upstream recovery. The rendered stale
  state lag was 110 ms and rendered recovery lag was 1,009 ms, both under the
  2,000 ms client-visible lag budget. The fixture now also proves
  `live-lease-expiry` through the actual `iPhone 17` Dock UI: the app displays
  a real live `running` row from the fixture relay, then displays the same row
  as `unknown` after the real live lease expires. The relay published expiry
  4 ms after the lease timestamp, and the rendered simulator UI matched it
  628 ms later, under the 2,000 ms client-visible lag budget. The fixture now
  also proves `multi-host-isolation` through the actual `iPhone 17` Dock UI:
  the app is configured with two temporary relay hosts, both hosts expose the
  same upstream thread id without card-id collision, host A adds a new row,
  host B stays unchanged, and the rendered UI converges to the five host-scoped
  rows in 1,511 ms under the 2,000 ms client-visible lag budget.
  The fixture now also proves `spawn-edge` through the actual `iPhone 17`
  Dock UI: a controlled subagent child appears as an automation row above its
  parent, the checkpoint sweep sees both rows, and the rendered UI matches the
  relay truth 995 ms after the relay transition under the 2,000 ms
  client-visible lag budget.
  The fixture now also proves `resync-gap` through the actual `iPhone 17`
  Dock UI: the relay state changes without a normal delta, the app receives a
  malformed sequence update, recovers through `dock/resync`, and displays the
  recovered two-row truth 936 ms after the relay resync transition under the
  2,000 ms client-visible lag budget.
  The fixture now also proves `rapid-mutations` through the actual `iPhone 17`
  Dock UI: one visible Dock row changes through six ordered client-visible
  statuses while the simulator sampler is running, and the rendered app display
  observes every intermediate transition within the 2,000 ms lag budget. The
  first attempt deliberately failed because `idle`/`dormant` states were hidden
  by the real Dock screen's active filter; the passing fixture now uses only
  visible states so the proof exercises actual displayed client behavior
  instead of an invisible relay-only state.
  The fixture now also proves `large-list-checkpoint` through the actual
  `iPhone 17` Dock UI: the controlled relay exposes 18 rows, the simulator
  checkpoint sweep scrolls beyond the initial viewport, and the judge fails if
  any relay row is missing, duplicated, miscounted, or mismatched.
  The fixture now also proves `detail-history-request` through the actual
  `iPhone 17` detail UI: the app opens the real Dock row, loads historical
  detail through the same routes the client uses, exercises paged turns, shows
  a live update, shows the pending request card in real time, sends the real
  approval response, shows the resolved state, and performs a detail sweep that
  fails missing opened-thread rows.
  The controlled scenario runner now also includes a real client-path
  `resync-gap` actuator that exercises `dock/resync` after a detected stream
  gap state and compares the recovered stream against a fresh
  `dock/subscribe` snapshot. It now also includes a `detail-reconnect`
  actuator that opens an actual Dock row, completes `thread/read`,
  `thread/turns/list`, and `thread/resume`, reconnects, then proves the same
  historical reload happens again before live events are accepted. It now also
  includes a controlled `source-refresh` actuator that drives a real in-process
  relay through actual `dock/subscribe`/`dock/update` client routes while the
  upstream source fails, marks cached rows explicitly stale, then recovers to a
  fresh row within the lag budget. It now also includes a controlled
  `server-request` actuator that opens an actual detail session through
  `thread/read`, `thread/turns/list`, and `thread/resume`, then proves a live
  server request, client response, and resolution notification cross the relay
  detail path within the lag budget. It now also includes a controlled
  `thread-activity` actuator that adds a new Dock row, updates an existing row,
  verifies render-order movement, and compares the long-lived stream against a
  fresh `dock/subscribe` snapshot. It now also includes a controlled
  `live-lease-expiry` actuator that proves a running live row expires through
  the long-lived `dock/subscribe` stream within the lag budget and matches a
  fresh `dock/subscribe` snapshot. It now also includes a controlled
  `multi-host-isolation` actuator that proves rows stay host-scoped across two
  real in-process relays even when both upstreams expose the same thread id,
  and a controlled `spawn-edge` actuator that proves a subagent spawn appears
  as an agent/automation Dock card and exposes its parent id through the
  client-used `thread/read` route within the lag budget. It now also includes a
  controlled `goal-change` actuator that proves the app-server-visible
  `thread/goal/get` route returns updated goal state within the lag budget
  while explicitly keeping that route outside current Swift client-path proof.
  The relay-level `--scenario all` matrix now passes with two archive/unarchive
  repetitions, all 10 scenario groups, and no unimplemented required scenarios.
  Phase 7 runbook documentation now exists at
  `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md` and is linked from
  `README.md`. Physical device availability and saved relay config were checked
  without reinstalling: the iPhone 17 Pro and iPhone 14 are visible, and both
  saved host lists match the expected relay-backed hosts. Fresh real-home
  client-path soaks now cover the live moving relay state both with forced
  `dock/resync` and without forced resync: the forced run observed 225
  `dock/update`s, 8 `dock/resync`s, 20 detail probes, 0 stream lag failures, and
  0 detail failures; the unforced run observed 41 `dock/update`s, 0 resyncs, 10
  detail probes, 0 stream lag failures, and 0 detail failures. A fresh
  `iPhone 17` controlled simulator matrix pass on 2026-05-31 also passed from
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1037Z`: 10/10
  required scenarios, 10/10 reports evaluated, 0 findings, and max rendered UI
  lag 1,781 ms under the 2,000 ms budget. A second fresh matrix run at
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1042Z` then failed
  `detail-history-request`: the relay/client path passed, but the simulator
  judge recorded the resolved request at 2,043 ms against the 2,000 ms budget.
  That failure was preserved as a real lag-gate failure. Root cause: the detail
  UI sample had already captured the resolved request in the sample that
  started 440 ms after relay resolution, but the judge used the full sample
  finish time after the expensive accessibility pass. The simulator sampler now
  timestamps each visible detail evidence element and the UI judge scores
  detail lag from the specific evidence capture time. A targeted
  `detail-history-request` proof then passed at
  `/tmp/codex-client/sim-ui-controlled-detail-history-request-evidence-time-20260531T1110Z`
  with 20 UI samples, 17 detail samples, 9 detail sweep message-card checks, 0
  failures, and rendered detail lags 1,413/1,248/1,555 ms under budget. A fresh
  full matrix run at
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1054Z` passed 10/10
  required scenarios with 0 findings and max rendered UI lag 1,762 ms under the
  2,000 ms budget. A post-fix two-pass matrix at
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1100Z` then passed
  20/20 reports across 10/10 required scenarios with 0 findings and max
  rendered UI lag 1,688 ms under the 2,000 ms budget. The final required fresh
  Composer consult ran at
  `/tmp/fresh-consult/codex-dock-sync-completion-20260531T1112Z-iN08ty` and
  returned `VERDICT: pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`.
  It agreed the relay/client/simulator path meets the plan's three-leg
  completion gate and that the 2,043 ms failure was credibly fixed without
  hiding lag. Its non-blocking notes are: unprompted live real-Codex-on-`:4510`
  literal simulator display is not proven concurrently, `detail-reconnect` has
  relay client-path proof but not a simulator displayed-UI matrix scenario,
  physical installed-app display proof remains open for the broader whole-goal
  boundary, and archive/unarchive display proof is in isolated simulator runs
  rather than the default 10-scenario matrix.
- Composer 2.5 Fast follow-up verdict: relay-level client-path slice is
  credibly done for the eight listed JSON-RPC routes on a real `:4510` relay;
  the full exhaustive plan is not complete.
- Actual client-path routes counted as proof:
  `initialize`, `initialized`, `dock/subscribe`, `dock/update`, `dock/resync`,
  `thread/archive`, `thread/unarchive`, `thread/read`, `thread/turns/list`,
  and `thread/resume`.
- Oracle-only surfaces are comparison evidence only: SQLite, rollout JSONL,
  `relay/state/snapshot`, `thread/list`, `thread/goal/get`,
  `thread/loaded/list`, and `thread/search`.
- Client-visible lag is a required failure condition. The relay audit exposes
  `--max-stream-lag-ms`; the current default Dock stream budget is 2,000 ms.
- Plan note added: Phase 6 now explicitly records the required third leg as
  actual `iPhone 17` simulator display proof after Codex-to-relay and
  relay-to-client-route proof, with `t_display_seen`,
  `lag_relay_to_display_ms`, `lag_change_to_display_ms`, client-exercised path
  requirements, reusable over-time harness language, and the
  `$model-consensus` entry gate for Opus 4.8 Max plus GPT-5.5 X-High.
- Important harness bug fixed: the controlled simulator fixture could finish a
  relay report but leave the Makefile matrix waiting on lingering Node handles.
  The fixture now bounds local WebSocket shutdown and explicitly exits after
  flushing its CLI summary. Targeted `resync-gap` proof then passed with 21 UI
  samples, 37 displayed-row checks, one checkpoint sweep, 0 failures, and
  rendered recovery lag 805 ms under the 2,000 ms budget.
- Important harness bug fixed: detail-transition lag was scored from the end of
  the whole simulator accessibility sample. That could count sampler overhead
  as user-visible lag after the matching request status/message evidence was
  already captured. Detail samples now carry per-element and per-detail-section
  timestamps, and `detailTransitionCoverage` uses the latest matching evidence
  timestamp for the transition.
- Important bug fixed: long-lived Dock streams could keep stale live-status
  projections after live leases expired because reconciliation published raw
  stored cards instead of current client-projected cards.
- Important bug fixed: live lease expiry now schedules a near-real-time
  reconciliation at the lease expiry time instead of waiting for the next
  30-second periodic reconciliation tick.
- Important bug fixed: long-lived Dock streams could stay partially caught up
  when the store sequence changed during window catch-up; the relay now restarts
  catch-up from a fresh snapshot.
- Important bug fixed: thread-detail live notifications could arrive while the
  client was still draining `thread/read`, `thread/turns/list`, and
  `thread/resume`; the Swift detail store now buffers those initial live events
  until the historical load is installed.
- Initial simulator displayed-UI proof added: `rtk make sim-ui-sync-proof`
  launches the `iPhone 17` UITest sampler on the relay-backed host path,
  records literal Dock/detail accessibility state over time, and judges it
  against the existing relay audit report.
- Simulator scenario proof added: `rtk make sim-ui-scenario-sync-proof`
  waits until the actual simulator UI is sampling, runs a real
  `thread/archive`/`thread/unarchive` relay scenario, and fails on missing,
  stale, wrong, partial, or lagged rendered Dock state.
- Repeated transition proof added: `--scenario-repetitions` makes the scenario
  driver run ordered repeated archive/unarchive cycles, record each transition
  separately, and fail if any intermediate relay or simulator-visible change is
  missed or late.
- Simulator checkpoint proof added: `SIM_UI_SYNC_CHECKPOINT_SWEEP=1` makes the
  UI sampler run a bounded actual simulator Dock sweep at a stable checkpoint,
  and the judge fails missing, extra, duplicate, wrong-status, wrong-origin, or
  wrong-count rows.
- Multi-thread isolated fixture support added: `SIM_UI_ISOLATED_THREAD_COUNT`
  makes `sim-ui-isolated-scenario-sync-proof` seed multiple real active
  `sessions/...` threads for full-list checkpoint proof. The seeder rejects
  `archived_sessions/...` rollout paths as active rows even if stale SQLite
  metadata marks them active.
- Important harness bug fixed: the simulator sampler now snapshots row elements
  with `allElementsBoundByIndex` instead of re-querying each row by live index.
  That prevents a row disappearing during archive/unarchive from crashing
  XCUITest before the Node judge can score the sample.
- Isolated service hook added: `rtk make services CODEX_HOME=...` now passes
  `CODEX_HOME` through the Makefile-owned host-service path to both raw
  app-server and relay services. The host service also passes an isolated
  relay state database path so scenario runs do not reuse repo-level
  `.codex-dock/relay-state.sqlite` cache. This plumbing now backs the passing
  isolated simulator scenario proof.
- Important bug fixed: a fresh active-list reconciliation could resurrect a
  just-archived row before the upstream app-server list caught up; the relay
  now gives successful local archive mutations a short grace window over stale
  active-list data.
- Important bug fixed: `thread/unarchive` deltas could publish the stored
  card without applying an active live lease, while fresh `dock/subscribe`
  returned the live-projected status. Long-lived clients now get the same
  projected card fresh subscribers get.
- Important harness bug fixed: scenario lag is now measured at the first
  client-visible target-row change instead of waiting for the entire paged Dock
  stream to finish catch-up.
- Controlled simulator fixture proof added:
  `rtk make sim-ui-controlled-scenario-sync-proof` starts a temporary real
  relay, launches the `iPhone 17` app against that exact relay, waits for the
  UI sampler to become ready, then mutates the fixture source while the app is
  visibly sampling.
- Important harness bug fixed: the simulator detail sampler now records missing
  loading-state detail sub-elements as `not-visible` instead of crashing
  XCUITest before the Node judge can score the Dock proof.
- Important harness bug fixed: simulator sample timing now records both
  `sampledAt` and `finishedAt`, and the UI judge scores transition-window
  warmup mismatches against the per-transition lag budget instead of treating a
  later transition's temporary animation state as a permanent post-convergence
  failure.
- Important client bug fixed: server-request events were reaching
  `ThreadDetailStore` but were hidden by the default `Messages` detail filter.
  The actual simulator proof caught that as missing/lagged visible UI. Request
  events are now default-visible, so the proof exercises the same path the
  client user sees.
- Important harness bug fixed: the simulator sampler now records visible Dock
  host freshness/status rows and the Node judge requires stale, offline, error,
  or refreshing relay freshness to be literally visible. The first
  `source-refresh` simulator attempt failed because the judge did not yet map
  the relay logical host id to the configured simulator host id; the alias-aware
  judge now proves the same single-host UI status without hiding real
  multi-host identity bugs.
- Controlled rapid-mutation simulator proof added: the fixture mutates one
  displayed Dock row through six ordered visible statuses, and the UI judge
  fails if the app skips any intermediate transition or observes it after the
  lag budget.
- Controlled simulator matrix verifier added:
  `rtk make sim-ui-controlled-matrix-verify` reads completed controlled
  simulator report directories and produces one pass/fail report for the
  required scenario set, including missing-scenario, route, transition,
  checkpoint-sweep, and lag checks.
- Controlled simulator matrix proof target added:
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` runs each
  required controlled simulator scenario into distinct report directories, then
  verifies the matrix. The verifier now rejects duplicate report directories so
  a two-pass gate cannot be satisfied by reusing the same artifact.
- Outside the relay/client/simulator completion boundary: installed physical
  phone display proof remains open. The required final Composer 2.5 Fast
  completion consult is complete with `VERDICT: pass-with-notes` and
  `BLOCKING: none`.

## Scope Ledger

| Item | Plan anchor | Status | Code anchor | Proof | Review |
| --- | --- | --- | --- | --- | --- |
| Relay sync audit CLI | Initial Tool Build | Done | `scripts/dock-relay-sync-audit.mjs` | `rtk npm run test:relay`; real audits below | Composer agrees for relay-level slice |
| Long-lived Dock stream probe | Relay Projection Probe | Done | `DockStreamProbe` in `scripts/dock-relay-sync-audit.mjs` | exhaustive two-sample soak v1; client-path soaks v6/v7; forced-resync client-path v2; fresh real-home forced-resync soak 20260531T1015Z; fresh real-home unforced soak 20260531T1013Z | Composer agrees for relay-level slice |
| One-shot parity reuse | Planned Tool | Done | imports `buildReport` from `scripts/dock-relay-state-parity.mjs` | exhaustive real-home v2; exhaustive two-sample soak v1 | Oracle-only comparison, not client-path proof |
| Detail row-to-detail probe | Detail Click-Through Verifier | Done for sampled relay protocol path, initial live-boundary buffering, reconnect detail reload scenario, controlled server-request relay proof, and one controlled simulator-rendered request-card slice, and controlled simulator-rendered full detail-history/request slice | `probeThreadDetail`, `--scenario detail-reconnect`, and `--scenario server-request` in `scripts/dock-relay-sync-audit.mjs`; `CodexDock/State/ThreadDetailStore.swift`; `CodexDock/Models/ThreadEvent.swift`; `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` | detail-boundary v3 pass; detail-reconnect scenario v1 pass; server-request scenario v1 pass; controlled simulator server-request v4 pass; controlled simulator detail-history-request v4/v5 passes; targeted Swift buffer/default-visible regression passes | Current controlled simulator request-card and detail-history matrix slices are covered; future natural-real-relay detail breadth remains open |
| Client-path-only soak mode | Time-Based Sync | Done | `--client-path-only` | v6/v7 and forced-resync v2 passing real-relay runs; fresh real-home forced-resync and unforced soaks on 2026-05-31 | Composer agrees for relay-level slice |
| Client-visible lag budget | Time-Based Sync | Done for relay stream and current controlled simulator matrix scenarios | `--max-stream-lag-ms`, `--max-ui-lag-ms`, `evaluateStreamConvergenceLag`, `scenarioTransitionCoverage`, `detailTransitionCoverage` | lag v2 pass; fresh real-home forced-resync soak 20260531T1015Z passed with max observed stream lag 0 ms; fresh real-home unforced soak 20260531T1013Z passed with max observed stream lag 0 ms; simulator scenario v5 pass with worst UI lag 1,801 ms under 2,000 ms; isolated checkpointed simulator v4 pass with UI lag 0 ms; repeated isolated simulator v5 pass with UI lag 0 ms and four scenario transition checks; controlled simulator thread-activity v3 pass with rendered UI transition lags 627 ms and 628 ms under 2,000 ms; controlled simulator server-request v4 passed with rendered detail lags 1,114 ms and 1,056 ms under 2,000 ms; controlled simulator source-refresh v2 passed with rendered stale/recovery lags 110 ms and 1,009 ms under 2,000 ms; controlled simulator live-lease-expiry v1 passed with rendered expiry lag 628 ms under 2,000 ms; controlled simulator multi-host-isolation v1 passed with rendered transition lag 1,511 ms under 2,000 ms; controlled simulator spawn-edge v1 passed with rendered transition lag 995 ms under 2,000 ms; controlled simulator resync-gap v1 passed with rendered transition lag 936 ms under 2,000 ms; controlled simulator rapid-mutations v2 passed with six rendered transition lags between 554 ms and 1,182 ms under 2,000 ms; controlled simulator detail-history-request v4/v5 passed with rendered detail lags 767/774/1,717 ms and 760/770/1,704 ms under 2,000 ms; fresh controlled matrix v2 passed with max rendered lag 1,492 ms; double-loop v1+v2 passed with max rendered lag 1,511 ms; ten-scenario double-loop passed with max rendered lag 1,717 ms; source-refresh v1 stale and recovery relay transitions passed at 1 ms and 0 ms; server-request v1 request and resolution transitions passed at 1 ms and 12 ms; thread-activity v2 new-thread and order transitions both passed at 1 ms; live-lease-expiry v1 passed at 4 ms; multi-host-isolation v1 passed at 1 ms; spawn-edge v1 passed at 1 ms; goal-change v2 relay-protocol route passed at 1 ms outside current client path; scenario-all v1 passed with worst relay scenario lag 194 ms under 2,000 ms | Current controlled detail-history/request simulator proof is covered; fresh real-home moving-state route proof is covered; spontaneous sequence-gap recovery remains opportunistic, with deterministic gap recovery covered by controlled `resync-gap` |
| Controlled scenario runner | Controlled Scenario Runner | Done for the relay-level required scenario matrix and current controlled simulator matrix; controlled simulator fixture slices done for `detail-history-request`, `large-list-checkpoint`, `thread-activity`, `server-request`, `source-refresh`, `live-lease-expiry`, `multi-host-isolation`, `spawn-edge`, `resync-gap`, and `rapid-mutations` | `--scenario archive-toggle`, `--scenario detail-reconnect`, `--scenario goal-change`, `--scenario live-lease-expiry`, `--scenario multi-host-isolation`, `--scenario resync-gap`, `--scenario server-request`, `--scenario source-refresh`, `--scenario spawn-edge`, `--scenario thread-activity`, `--scenario all`, `--scenario-repetitions` in `scripts/dock-relay-sync-audit.mjs`; `scripts/dock-relay-controlled-simulator-fixture.mjs`; `scripts/codex-dock-isolated-home.mjs`; `CODEX_HOME` and `--relay-state-db` in `scripts/codex-dock-host-service.mjs`; `Makefile` service args | real archive/unarchive scenario v4 pass; real resync-gap scenario v2 pass; real detail-reconnect scenario v1 pass; controlled source-refresh scenario v1 pass; controlled server-request scenario v1 pass; controlled thread-activity scenario v2 pass; controlled live-lease-expiry scenario v1 pass; controlled multi-host-isolation scenario v1 pass; controlled spawn-edge scenario v1 pass; controlled goal-change scenario v2 pass; relay scenario-all client-path v1 pass; isolated relay scenario v2 pass; isolated checkpointed simulator scenario v4 pass; repeated isolated simulator scenario v5 pass; controlled simulator thread-activity v3 pass; controlled simulator server-request v4 pass; controlled simulator source-refresh v2 pass; controlled simulator live-lease-expiry v1 pass; controlled simulator multi-host-isolation v1 pass; controlled simulator spawn-edge v1 pass; controlled simulator resync-gap v1 pass; controlled simulator rapid-mutations v2 pass; controlled simulator large-list-checkpoint v1/v2 pass; controlled simulator detail-history-request v4/v5 pass; controlled simulator matrix v2 pass; nine-scenario double-loop pass; ten-scenario double-loop pass | Archive/unarchive drives repeated simulator proof; the controlled simulator fixture proves the app connected to the same temporary relay that produces new-thread/new-turn-order changes, live request-card/resolution changes, stale/recovered source freshness changes, live running-to-unknown expiry changes, two-host same-thread-id isolation changes, subagent-spawn automation-row changes, sequence-gap resync recovery changes, rapid repeated visible status changes, and opened-thread detail-history/request changes without skipping intermediate UI states; resync-gap covers client-path recovery after a detected stream gap and now two actual simulator Dock recovery slices; detail-reconnect covers detail reload before live on reconnect; source-refresh covers explicit stale cache and recovery through real relay client routes with controlled upstream failure and now two actual simulator Dock host-status slices; server-request covers live request delivery, response forwarding, and resolution through real detail routes and now two actual simulator detail UI slices; detail-history-request covers paged history, live detail update, pending request card, real approval tap, resolved request state, and a full opened-thread detail sweep; remaining notes are natural real-relay gap recovery breadth and physical phone proof if those broader claims are needed; final consult is complete |
| Swift store proof | Swift Client Proof | Refreshed after detail buffering fix | `ThreadDetailStore.swift`, `ThreadDetailStoreTests.swift` | targeted buffer regression passed; exact voice timeout rerun passed; latest broad `ThreadDetailStoreTests` passed 54 tests, 0 failures | Unit proof only; full store-to-relay audit loop is covered separately by relay/simulator proofs |
| Simulator displayed-UI proof | Phase 6 | First real-path, isolated repeated transition, two-thread checkpoint, controlled `thread-activity`, controlled `server-request`, controlled `source-refresh`, controlled `live-lease-expiry`, controlled `multi-host-isolation`, controlled `spawn-edge`, controlled `resync-gap`, controlled `rapid-mutations`, controlled `large-list-checkpoint`, controlled `detail-history-request`, expanded ten-scenario matrix pass, double-loop gate, post-fix two-pass gate, and final Composer consult done with notes | `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, `scripts/dock-relay-simulator-ui-sync-proof.mjs`, `scripts/dock-relay-controlled-simulator-fixture.mjs`, `scripts/dock-relay-controlled-simulator-matrix.mjs`, `scripts/codex-dock-isolated-home.mjs`, `Makefile` `sim-ui-sync-proof`, `sim-ui-scenario-sync-proof`, `sim-ui-isolated-scenario-sync-proof`, `sim-ui-controlled-scenario-sync-proof`, `sim-ui-controlled-matrix-verify`, `sim-ui-controlled-matrix-proof` | over-time v1 pass; real-home scenario archive-toggle v5 pass; isolated checkpointed scenario archive-toggle v4 pass; repeated isolated scenario archive-toggle v5 pass; two-thread isolated scenario v8 pass on `iPhone 17`; controlled simulator thread-activity v3 pass with 23 UI samples, 64 displayed-row checks, 1 checkpoint sweep, and 0 failures; controlled simulator server-request v4 pass with 16 UI samples, 2 detail transitions, 0 detail failures, and rendered request lags 1,114 ms/1,056 ms; controlled simulator source-refresh v2 pass with 22 UI samples, 2 transition checks, host freshness proof, 1 checkpoint sweep, and rendered stale/recovery lags 110 ms/1,009 ms; controlled simulator live-lease-expiry v1 pass with 23 UI samples, 1 transition check, 22 displayed row checks, 1 checkpoint sweep, and rendered expiry lag 628 ms; controlled simulator multi-host-isolation v1 pass with 16 UI samples, 73 displayed row checks, 1 five-row checkpoint sweep, and rendered transition lag 1,511 ms; controlled simulator spawn-edge v1 pass with 20 UI samples, 35 displayed row checks, 1 two-row checkpoint sweep, and rendered transition lag 995 ms; controlled simulator resync-gap v1 pass with 21 UI samples, 37 displayed row checks, 1 two-row checkpoint sweep, and rendered transition lag 936 ms; controlled simulator rapid-mutations v2 pass with 38 UI samples, 6 transition checks, 74 displayed-row checks, 1 checkpoint sweep with 2 row checks, and rendered transition lags 554-1,182 ms; controlled simulator matrix v1 passed 8/8 required scenarios with max UI lag 1,511 ms; controlled simulator matrix v2 passed 8/8 required scenarios with max UI lag 1,492 ms; double-loop v1+v2 passed 16 reports with 2/2 passes per scenario and max UI lag 1,511 ms; large-list-checkpoint v1/v2 passed 18-row checkpoint sweeps; nine-scenario double-loop passed 18 reports with 2/2 passes per scenario and max UI lag 1,511 ms; detail-history-request v4/v5 passed with 18 UI samples, 15 detail samples, 3 detail transitions, 1 detail sweep, 9 detail sweep row checks, and rendered detail lags 767/774/1,717 ms and 760/770/1,704 ms; ten-scenario double-loop passed 20 reports with 2/2 passes per scenario and max UI lag 1,717 ms; post-fix two-pass matrix passed 20 reports with max UI lag 1,688 ms; final Composer consult returned `pass-with-notes` with no blocking issues | Remaining notes are physical phone display proof, unprompted live real-Codex-on-`:4510` literal simulator display, and a simulator displayed-UI `detail-reconnect` slice if those broader claims are needed |
| Runbook and continuous loop | Phase 7 | Runbook documentation and final consult done; physical phone proof still open outside the simulator-path claim | `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md`; `README.md` | doc readback; final Composer consult; `rtk git status --short -- README.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md` | The runbook documents one-shot, soak, scenario, Swift proof, simulator displayed-UI proof, report paths, CI-safe subsets, physical phone proof commands, pass/fail/blocked/outside-contract states, and redaction rules. |
| Physical phone proof | Completion gate / Service Path | Partially checked; installed display proof not done | `rtk make devices`; `rtk make device-config-verify-all`; `scripts/device.py`; `scripts/device-relay-config.mjs` | devices available; saved relay config verified on iPhone 17 Pro and iPhone 14 | This proves device availability and host config only. It does not prove the installed app renders real `DockThreadCard` rows or physical offline/error UI. |

## Code Read Ledger

| Area | Files/symbols read | Why relevant | Fresh until | Notes |
| --- | --- | --- | --- | --- |
| Parity oracle | `scripts/dock-relay-state-parity.mjs`, `buildReport`, `parseArgs` | Reuse storage/app-server/Dock one-shot truth | parity script changes | New harness wraps the existing parity logic instead of duplicating storage truth. |
| Relay stream protocol | `scripts/dock-relay-json-rpc-client.mjs`, `scripts/dock-relay-state-subscriptions.mjs`, `scripts/dock-relay-state-engine.mjs` | Need long-lived `dock/subscribe`/`dock/update`/`dock/resync` proof | relay stream contract changes | Harness applies stream payloads using Swift-compatible same-`seq` catch-up semantics. |
| Swift Dock stream consumer | `CodexDock/State/AppServerThreadCardStreamClient.swift`, `DockStore.swift`, `ThreadCardTable.swift` | Actual client routes and update acceptance semantics | Swift stream code changes | Counted client routes match the Swift client path. |
| Swift detail consumer | `CodexDock/State/ThreadDetailStore.swift`, `ThreadDetailDataEngine.swift` | Actual detail load path and initial live-event ordering | Swift detail code changes | Detail probe starts from Dock cards, then uses `thread/read`, `thread/turns/list`, and `thread/resume`; Swift now buffers initial live events until historical state is installed. |
| Relay state projection | `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-views.mjs` | Found stale live-status stream projection bug and catch-up restart bug | relay projection changes | Reconciliation now publishes client-projected card values; catch-up restarts after mid-catch-up sequence changes. |
| Source filtering and spawn metadata | `scripts/dock-relay-source-filter.mjs`, `threadSpawnParentIDFromSource` in `scripts/dock-relay-state-parity.mjs` | Needed to make the spawn-edge fixture mimic app-server source-scope filtering and verify parent metadata without leaking prompt text | source filtering or spawn-source parsing changes | Spawn-edge scenario now verifies the child arrives through Dock as `agent`/`automation` and through `thread/read` with the parent thread id. |
| Goal route boundary | `DockThreadCardDTO`, `ThreadDetailStore`, `thread/goal/get`, `summarizeClientPathEvents` | Needed to prove goal freshness without falsely counting a route the Swift client does not use today | client DTO/detail route or goal route changes | Goal-change scenario proves `thread/goal/get` freshness and records that route under non-client-path evidence. |
| Simulator displayed UI | `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, `CodexDock/Automation/AutomationID.swift`, `Makefile`, `scripts/dock-relay-simulator-ui-sync-proof.mjs`, `scripts/dock-relay-controlled-simulator-fixture.mjs` | Literal rendered app proof over time | UI automation IDs, UI proof judge, controlled fixture, or Makefile simulator flow changes | UITest reads actual rendered accessibility values; visible row capture uses snapshot-based element enumeration; samples now carry start/end timing and visible host summaries; the Node judge compares visible rows/detail/host freshness to relay client-path truth, scores scenario and detail transition warmup against the lag budget, can score bounded actual-UI checkpoint sweeps, and now proves request-card visibility/resolution, source stale/recovery, live lease running-to-unknown expiry, two-host same-thread-id isolation, spawned automation-row display, sequence-gap resync recovery, and rapid repeated visible status changes through the real UI. |
| Controlled simulator matrix | `scripts/dock-relay-controlled-simulator-matrix.mjs`, `scripts/dock-relay-controlled-simulator-matrix.test.mjs`, `Makefile` `sim-ui-controlled-matrix-verify`, `sim-ui-controlled-matrix-proof` | Reusable gate over completed controlled simulator reports and one-command matrix runs | matrix verifier, required simulator scenario set, Makefile matrix target, or report schema changes | Reads each scenario's `relay-client-path.json` and `simulator-ui-sync.json`, requires expected routes, transition checks, checkpoint sweeps, and lag budget compliance, can require multiple passing reports per scenario through `--min-passes`, and rejects duplicate report directories so repeated proof requires distinct artifacts. |
| Host service isolation | `Makefile`, `scripts/codex-dock-host-service.mjs`, `scripts/codex-dock-host-service.test.mjs` | Needed before isolated `CODEX_HOME` scenarios can be run through Makefile-owned services | host service or Makefile service flow changes | `CODEX_HOME` is now propagated into both launchd/systemd service environments; the relay state database defaults under the service runtime so isolated proofs do not reuse repo-level cache; Makefile paths are normalized for absolute temp dirs. |
| Isolated home seeder | `scripts/codex-dock-isolated-home.mjs`, `scripts/codex-dock-isolated-home.test.mjs` | Builds tiny temp Codex homes for isolated scenario proof without copying the multi-GB session tree | isolated seeder changes | Clones one or more active real `sessions/...` threads, rewrites rollout paths into the temp home, prunes unrelated state, and leaves mutations to real app-server/relay routes. |
| Exhaustive sync runbook | `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md`, `README.md`, Phase 7 in plan | Makes the harness repeatable without reading source code | runbook, Makefile proof target, or report schema changes | Documents exact one-shot, soak, scenario, Swift, simulator, matrix-verify, physical-phone, CI-safe, result-reading, and redaction procedures. |

## Proof Freshness Ledger

| Proof | Scope covered | Result/context | Fresh until | Rerun trigger |
| --- | --- | --- | --- | --- |
| `rtk node --check scripts/dock-relay-sync-audit.mjs` | Sync-audit syntax | pass | sync-audit script changes | any sync-audit edit |
| `rtk node --test scripts/dock-relay-sync-audit.test.mjs` | Sync-audit parser, stream, detail, scenario, repeated-transition, render-order comparison, resync-gap, detail-reconnect, goal-change, source-refresh, server-request, thread-activity, live-lease-expiry, multi-host-isolation, and spawn-edge requirement behavior | pass, 45 tests, 0 failures | sync-audit script/test changes | any sync-audit edit |
| `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs` | Simulator UI judge behavior, including checkpoint sweep failures, multi-transition warmup scoring, detail request-card transition scoring, detail sweep scoring, and source freshness host-status scoring | pass, 19 tests, 0 failures | UI judge tests or script changes | any UI judge edit |
| `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs` | Controlled simulator fixture parser/guard behavior, including `detail-history-request`, `large-list-checkpoint`, `server-request`, `resync-gap`, `rapid-mutations`, `source-refresh`, `live-lease-expiry`, `multi-host-isolation`, and `spawn-edge` selection | pass, 12 tests, 0 failures | controlled simulator fixture script/test changes | any controlled fixture edit |
| `rtk node --test scripts/dock-relay-controlled-simulator-matrix.test.mjs` | Controlled simulator matrix verifier behavior, including missing scenario, missing route, lag failure, broad checkpoint row coverage, detail sweep row coverage, `--min-passes`, and duplicate-report-dir rejection | pass, 9 tests, 0 failures | controlled simulator matrix script/test changes | any matrix verifier edit |
| `rtk node --check scripts/dock-relay.mjs && rtk node --check scripts/codex-dock-host-service.mjs` | Relay and host-service syntax after isolated relay state DB wiring | pass | relay or host-service script changes | any relay/host-service edit |
| `rtk npm run test:relay` | Full Node relay suite | pass, 212 tests, 0 failures after the controlled simulator fixture cleanup fix and detail evidence-time judge fix | relay script/test changes | any relay script edit |
| `rtk node --test scripts/codex-dock-host-service.test.mjs` | Host service rendering, install, status, logs, env redaction, `CODEX_HOME`, and relay state DB args | pass, 27 tests, 0 failures | host-service script/test changes | any host-service edit |
| `rtk npm run test:host-service` | Host-service and device relay config suites | pass, 35 tests, 0 failures | host-service or device config changes | any host-service/device config edit |
| `rtk node --test scripts/codex-dock-isolated-home.test.mjs` | Isolated Codex home seeding, including multi-thread selection and `archived_sessions/...` rejection | pass, 3 tests, 0 failures | isolated seeder changes | any isolated seeder edit |
| `rtk make -n services CODEX_HOME=/tmp/codex-client/isolated-home APP_SERVER_DIR=/tmp/codex-client/isolated-service ENV_FILE=/tmp/codex-client/isolated-service/service.env HOST_ENV_FILE=/tmp/codex-client/isolated-service/host.env APP_SERVER_PORT=4520 DOCK_RELAY_PORT=4521 DOCK_RELAY_WS=ws://127.0.0.1:4521 APP_SERVER_LABEL=com.aelaguiz.codex-dock.app-server.isolated DOCK_RELAY_LABEL=com.aelaguiz.codex-dock.relay.isolated HOST_SERVICE_NETWORK_PROFILE=simulator-local` | Makefile-owned isolated service command shape | pass; dry-run shows clean `/tmp` paths, `--codex-home` propagation, and isolated relay state DB routing | Makefile service path changes | any service variable/path edit |
| `rtk make -n sim-ui-controlled-matrix-verify SIM_UI_MATRIX_REPORT_DIRS='/tmp/codex-client/sim-ui-controlled-thread-activity-v3 /tmp/codex-client/sim-ui-controlled-server-request-v4'` | Makefile-owned controlled simulator matrix verifier command shape | pass; dry-run shows report dirs become repeated `--report-dir` args and write JSON/Markdown paths under `/tmp/codex-client` | Makefile matrix target changes | any matrix target edit |
| `rtk make -n sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_SCENARIOS='thread-activity rapid-mutations' SIM_UI_CONTROLLED_MATRIX_PASSES=2 SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/matrix-dry-run MAX_UI_LAG_MS=2000` | Makefile-owned controlled simulator matrix proof command shape | pass; dry-run shows distinct `pass-1`/`pass-2` scenario directories, 250 ms UI sampling, scenario-specific durations, and final `SIM_UI_MATRIX_MIN_PASSES=2` verifier call | Makefile matrix target changes | any matrix proof target edit |
| `sed -n '1,320p' docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md`; `rtk make -n sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_PASSES=2 MAX_UI_LAG_MS=2000`; `git status --short -- README.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md` | Phase 7 runbook readback, matrix dry-run, and changed-file check | pass; readback covered the full runbook, `README.md` link, plan related-doc link, implementation-log anchors, no trailing whitespace/tabs, expected changed files, and the documented matrix proof dry-run expanded to two passes across all 10 controlled scenarios with distinct report dirs | runbook, README, Makefile matrix target, or plan/log docs changes | any runbook or command-shape change |
| `rtk make devices`; `rtk make device-config-verify-all` | Non-destructive physical phone availability and saved relay-config readback | pass; iPhone 17 Pro `CB9FFF0E-89AD-57B5-9C00-6552D814875E` and iPhone 14 `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC` were available; saved configs matched `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510` and `Amir-M5.local:4510,192.168.50.74:4510` | physical device config, host list, device scripts, or app install changes | not display proof; rerun before physical install/display claim |
| `rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --force-dock-resync --duration-ms 125000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 5 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-natural-soak-20260531T1015Z.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-natural-soak-20260531T1015Z.md --summary-only --fail-on-diff` | Fresh real-home moving-state client-path soak with forced `dock/resync` | pass; 4 samples, 4 ok, `clientPathOK: true`, `dock/update: 225`, `dock/resync: 8`, `thread/read: 20`, `thread/turns/list: 20`, `thread/resume: 20`, `streamNotificationCount: 69`, `detailBufferedInitialLiveEvents: 13`, 0 long-lived stream mismatches, 0 stream lag failures, max observed stream lag 0 ms, 0 detail failures | relay stream/detail code, local real-home state proof freshness, or lag budget changes | rerun before final completion or after relay/detail changes |
| `rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 5 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-natural-no-force-20260531T1013Z.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-natural-no-force-20260531T1013Z.md --summary-only --fail-on-diff` | Fresh real-home moving-state client-path soak without forced resync | pass; 2 samples, 2 ok, `clientPathOK: true`, `dock/update: 41`, no `dock/resync`, `thread/read: 10`, `thread/turns/list: 10`, `thread/resume: 10`, `streamNotificationCount: 15`, `detailBufferedInitialLiveEvents: 6`, 0 long-lived stream mismatches, 0 stream lag failures, max observed stream lag 0 ms, 0 detail failures | relay stream/detail code, local real-home state proof freshness, or lag budget changes | rerun before final completion or after relay/detail changes |
| `rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=5000 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1` | Isolated `CODEX_HOME` end-to-end-to-end displayed UI archive/unarchive transition proof with bounded checkpoint sweep and isolated relay state DB | pass; 25 UI samples, 23 scored, 2 scenario transitions, 0 failures, 1 checkpoint sweep, 1 checkpoint sweep row check, UI lag observed 0 ms under 2,000 ms; relay archive/unarchive lag 18 ms/18 ms | UI, relay sync audit, isolated seeder, host service, relay state DB, or scenario changes | any isolated simulator proof dependency edit |
| `rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle SIM_UI_SYNC_DURATION_MS=26000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=2 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1` | Isolated `CODEX_HOME` end-to-end-to-end displayed UI proof for two ordered archive/unarchive cycles | pass; 43 UI samples, 41 scored, 4 scenario transitions, 4 transition checks, 0 transition failures, 29 displayed row checks, 1 checkpoint sweep, UI lag observed 0 ms under 2,000 ms; relay transition lags 16 ms, 19 ms, 16 ms, 17 ms | UI, relay sync audit, repeated scenario runner, isolated seeder, host service, relay state DB, or scenario changes | any isolated repeated simulator proof dependency edit |
| `rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v6-multi-row-checkpoint SIM_UI_ISOLATED_THREAD_COUNT=2 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=1 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1` | First two-thread isolated displayed-UI checkpoint attempt | failed; relay client path passed, but rendered UI exceeded the 2,000 ms budget with observed UI lag 3,415 ms and one archive transition not observed before unarchive. Root cause evidence: the second seeded row came from an `archived_sessions/...` rollout and disappeared during fresh reconciliation. | superseded by seeder rejection fix, but preserved as failure evidence | rerun after sampler/fixture stability work |
| `rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v7-multi-row-stable SIM_UI_ISOLATED_THREAD_COUNT=2 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=1 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1` | Two-thread isolated displayed-UI attempt after rejecting `archived_sessions/...` rollout paths | failed before UI judging; relay scenario passed with archive/unarchive relay lags 19 ms and 20 ms, but XCUITest failed while reading row index 1 after the row disappeared during the mutation window. | superseded by v8 snapshot row capture | preserved as sampler failure evidence |
| `rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture SIM_UI_ISOLATED_THREAD_COUNT=2 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=1 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1` | Two-thread isolated `iPhone 17` displayed-UI archive/unarchive proof after snapshot-based row capture | pass; `OK: true`, `Relay client-path OK: true`, 27 UI samples, 25 scored, 3 relay samples, 2 scenario transitions, 2 transition checks, 0 transition failures, 47 displayed row checks, 1 checkpoint sweep with 2 row checks, 1 detail sample, observed UI lag 0 ms under the 2,000 ms budget. Relay lags were 13 ms archive and 14 ms unarchive. | UI, relay sync audit, isolated seeder, host service, relay state DB, or scenario changes | any isolated multi-row simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=thread-activity SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-thread-activity-v3 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `thread-activity` end-to-end-to-end displayed UI proof where the app connects to the same temporary relay the fixture mutates | pass; `OK: true`, `Relay client-path OK: true`, 23 UI samples, 22 scored, 3 relay samples, 2 scenario transitions, 0 transition failures, 64 displayed row checks, 1 checkpoint sweep with 3 row checks, 1 detail sample, global UI lag observed 0 ms, transition UI lags 627 ms and 628 ms under the 2,000 ms budget, relay lags 5 ms and 3 ms, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, or thread-activity scenario changes | any controlled simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=server-request SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-server-request-v4 SIM_UI_SYNC_DURATION_MS=12000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `server-request` end-to-end-to-end displayed UI proof where the app opens real detail UI, sees the request card, taps the real action, and sees resolution | pass; `OK: true`, `Relay client-path OK: true`, 16 UI samples, 3 scored UI samples, 1 relay sample, 2 detail transitions, 0 detail failures, 3 displayed row checks, 1 checkpoint sweep with 1 row check, 13 detail samples, observed UI lag 0 ms, request-visible lag 1,114 ms, request-resolution lag 1,056 ms, relay request lag 0 ms, resolution lag 12 ms, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, Swift default-visible event behavior, or server-request scenario changes | any controlled server-request simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=source-refresh SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-source-refresh-v2 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `source-refresh` end-to-end-to-end displayed UI proof where the app shows cached rows as visibly partial/stale during upstream failure and then shows recovered fresh rows | pass; `OK: true`, `Relay client-path OK: true`, 22 UI samples, 21 scored UI samples, 3 relay samples, 2 scenario transitions, 0 transition failures, 21 displayed row checks, 1 checkpoint sweep with 1 row check, 1 detail sample, observed UI lag 688 ms under 2,000 ms, source-refresh stale UI lag 110 ms, recovery UI lag 1,009 ms, route counts `initialize:3`, `initialized:3`, `dock/subscribe:3`, `dock/update:3`, failures 0 | UI sampler host summaries, UI judge, controlled fixture, Makefile target, or source-refresh scenario changes | any controlled source-refresh simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=live-lease-expiry SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `live-lease-expiry` end-to-end-to-end displayed UI proof where the app shows a real live `running` row and then the same row as non-live after the lease expires | pass; `OK: true`, `Relay client-path OK: true`, 23 UI samples, 22 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition failures, 22 displayed row checks, 1 checkpoint sweep with 1 row check, 1 detail sample, observed UI lag 0 ms, relay expiry lag 4 ms, rendered expiry lag 628 ms under the 2,000 ms budget, route counts `initialize:3`, `initialized:3`, `dock/subscribe:3`, `dock/update:3`, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, or live-lease-expiry scenario changes | any controlled live-lease-expiry simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=multi-host-isolation SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1 SIM_UI_SYNC_DURATION_MS=16000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `multi-host-isolation` end-to-end-to-end displayed UI proof where the app connects to two temporary relays, both expose the same thread id, and host A mutates without leaking into host B | pass; `OK: true`, `Relay client-path OK: true`, 16 UI samples, 15 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition failures, 73 displayed row checks, 1 checkpoint sweep with 5 row checks, 1 detail sample, observed UI lag 1,163 ms, relay host-A update lag 2 ms, rendered transition lag 1,511 ms under the 2,000 ms budget, route counts `initialize:6`, `initialized:6`, `dock/subscribe:6`, `dock/update:3`, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, host identity resolution, or multi-host scenario changes | any controlled multi-host simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=spawn-edge SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-spawn-edge-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `spawn-edge` end-to-end-to-end displayed UI proof where the app connects to the temporary relay while a subagent child row appears as an automation Dock row above its parent | pass; `OK: true`, `Relay client-path OK: true`, 20 UI samples, 19 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition failures, 35 displayed row checks, 1 checkpoint sweep with 2 row checks, 1 detail sample, observed UI lag 798 ms, relay spawn lag 2 ms, rendered transition lag 995 ms under the 2,000 ms budget, route counts `initialize:3`, `initialized:3`, `dock/subscribe:3`, `dock/update:2`, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, source filtering, or spawn metadata changes | any controlled spawn-edge simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=resync-gap SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-resync-gap-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `resync-gap` end-to-end-to-end displayed UI proof where the app receives a bad Dock stream sequence, recovers through `dock/resync`, and displays the recovered row set | pass; `OK: true`, `Relay client-path OK: true`, 21 UI samples, 20 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition failures, 37 displayed row checks, 1 checkpoint sweep with 2 row checks, 1 detail sample, observed UI lag 772 ms, relay resync lag 2 ms, rendered transition lag 936 ms under the 2,000 ms budget, route counts `initialize:3`, `initialized:3`, `dock/subscribe:3`, `dock/update:2`, `dock/resync:1`, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, stream sequence handling, or resync route changes | any controlled resync-gap simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=resync-gap SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-resync-gap-cleanup-fix-20260531T1033Z SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000 SIM_UI_SYNC_RELAY_DURATION_MS=180000` | Fresh controlled `resync-gap` cleanup-fix proof through the actual `iPhone 17` app display | pass; relay report `clientPathOK: true`, route counts `initialize:3`, `initialized:3`, `dock/subscribe:3`, `dock/update:2`, `dock/resync:1`; UI report had 21 UI samples, 20 scored UI samples, 37 displayed-row checks, 1 checkpoint sweep with 2 row checks, 0 failures, and rendered recovery lag 805 ms under the 2,000 ms budget | controlled simulator fixture cleanup, UI sampler, UI judge, Makefile target, stream sequence handling, or resync route changes | any controlled resync-gap simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=rapid-mutations SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2 SIM_UI_SYNC_DURATION_MS=28000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=2500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Controlled `rapid-mutations` end-to-end-to-end displayed UI proof where one visible Dock row changes through six ordered statuses and the app must render every intermediate transition | pass; `OK: true`, `Relay client-path OK: true`, 38 UI samples, 37 scored UI samples, 7 relay samples, 6 scenario transitions, 6 transition checks, 0 transition failures, 74 displayed row checks, 1 checkpoint sweep with 2 row checks, 1 detail sample, observed UI lag 787 ms, relay mutation lags 1-5 ms, rendered transition lags 554 ms, 1,182 ms, 1,018 ms, 864 ms, 724 ms, and 559 ms under the 2,000 ms budget, route counts `initialize:8`, `initialized:8`, `dock/subscribe:8`, `dock/update:7`, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, Dock status visibility, or stream update handling changes | any controlled rapid-mutations simulator proof dependency edit |
| `rtk make sim-ui-controlled-matrix-verify SIM_UI_MATRIX_REPORT_DIRS='/tmp/codex-client/sim-ui-controlled-thread-activity-v3 /tmp/codex-client/sim-ui-controlled-server-request-v4 /tmp/codex-client/sim-ui-controlled-source-refresh-v2 /tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1 /tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1 /tmp/codex-client/sim-ui-controlled-spawn-edge-v1 /tmp/codex-client/sim-ui-controlled-resync-gap-v1 /tmp/codex-client/sim-ui-controlled-rapid-mutations-v2' SIM_UI_MATRIX_JSON=/tmp/codex-client/sim-ui-controlled-matrix-v1.json SIM_UI_MATRIX_MD=/tmp/codex-client/sim-ui-controlled-matrix-v1.md SIM_UI_MATRIX_MIN_PASSES=1 MAX_UI_LAG_MS=2000` | First controlled simulator matrix gate across all current controlled `iPhone 17` displayed-UI scenario reports | pass; 8 reports, 8 required scenarios, 8 passing scenarios, 0 missing, 0 failed, max observed UI lag 1,511 ms under the 2,000 ms budget, findings 0 | controlled scenario report set, matrix verifier, UI judge, or required scenario list changes | rerun after any controlled simulator proof dependency edit |
| `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/sim-ui-controlled-matrix-run-v2 SIM_UI_CONTROLLED_MATRIX_PASSES=1 MAX_UI_LAG_MS=2000` | Second controlled simulator matrix pass through the actual `iPhone 17` app display for all 8 required scenarios | pass; 8 reports, 8 required scenarios, 8 passing scenarios, max observed UI lag 1,492 ms under the 2,000 ms budget, findings 0; per-scenario max lags: `thread-activity` 672 ms, `server-request` 1,123 ms, `source-refresh` 336 ms, `live-lease-expiry` 674 ms, `multi-host-isolation` 1,492 ms, `spawn-edge` 987 ms, `resync-gap` 907 ms, `rapid-mutations` 1,164 ms | controlled scenario report set, matrix proof target, matrix verifier, UI judge, or required scenario list changes | rerun after any controlled simulator proof dependency edit |
| `rtk make sim-ui-controlled-matrix-verify ... SIM_UI_MATRIX_MIN_PASSES=2` with the v1 report dirs plus `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/*` | Double-loop controlled simulator matrix gate with distinct report dirs for each required scenario | pass; 16 reports, 8 required scenarios, 8 passing scenarios, 2/2 passes per scenario, 0 missing, 0 failed, max observed UI lag 1,511 ms under the 2,000 ms budget, findings 0; artifacts `/tmp/codex-client/sim-ui-controlled-matrix-double-loop-v1-v2.json` and `.md` | controlled scenario report set, duplicate-dir verifier, UI judge, or required scenario list changes | rerun after any controlled simulator proof dependency edit or before final completion if any dependency changes |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=large-list-checkpoint SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | First large-list checkpoint proof through the actual `iPhone 17` app display | pass; `OK: true`, 9 UI samples, 8 scored UI samples, 2 relay samples, 40 displayed row checks, 1 checkpoint sweep, 18 checkpoint sweep row checks, observed UI lag 0 ms under the 2,000 ms budget, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, or large-list scenario changes | any controlled large-list simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=large-list-checkpoint SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v2 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Second large-list checkpoint proof through the actual `iPhone 17` app display | pass; `OK: true`, 8 UI samples, 8 scored UI samples, 2 relay samples, 40 displayed row checks, 1 checkpoint sweep, 18 checkpoint sweep row checks, observed UI lag 0 ms under the 2,000 ms budget, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, or large-list scenario changes | any controlled large-list simulator proof dependency edit |
| `rtk make sim-ui-controlled-matrix-verify ... SIM_UI_MATRIX_MIN_PASSES=2` with the prior 16 report dirs plus large-list v1/v2 | Expanded nine-scenario double-loop controlled simulator matrix gate | pass; 18 reports, 9 required scenarios, 9 passing scenarios, 2/2 passes per scenario, 0 missing, 0 failed, max observed UI lag 1,511 ms under the 2,000 ms budget, findings 0; artifacts `/tmp/codex-client/sim-ui-controlled-matrix-nine-scenario-double-loop-v1.json` and `.md` | controlled scenario report set, duplicate-dir verifier, UI judge, or required scenario list changes | rerun after any controlled simulator proof dependency edit or before final completion if any dependency changes |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-history-request SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-detail-history-request-v4 SIM_UI_SYNC_DURATION_MS=20000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | First full opened-thread detail-history/request proof through the actual `iPhone 17` app display | pass; `OK: true`, `Relay client-path OK: true`, 18 UI samples, 3 scored UI samples, 1 relay sample, 3 detail transitions, 0 detail failures, 3 displayed row checks, 1 checkpoint sweep, 1 detail sweep, 9 detail sweep message card checks, observed UI lag 0 ms, rendered detail lags 767 ms, 774 ms, and 1,717 ms under the 2,000 ms budget, route counts `initialize:5`, `initialized:5`, `dock/subscribe:2`, `dock/update:1`, `thread/read:1`, `thread/turns/list:2`, `thread/resume:1`, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, Swift detail routing/filtering, or request-card behavior changes | any controlled detail-history simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-history-request SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-detail-history-request-v5 SIM_UI_SYNC_DURATION_MS=20000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000` | Second full opened-thread detail-history/request proof through the actual `iPhone 17` app display | pass; `OK: true`, `Relay client-path OK: true`, 18 UI samples, 3 scored UI samples, 1 relay sample, 3 detail transitions, 0 detail failures, 3 displayed row checks, 1 checkpoint sweep, 1 detail sweep, 9 detail sweep message card checks, observed UI lag 0 ms, rendered detail lags 760 ms, 770 ms, and 1,704 ms under the 2,000 ms budget, route counts `initialize:5`, `initialized:5`, `dock/subscribe:2`, `dock/update:1`, `thread/read:1`, `thread/turns/list:2`, `thread/resume:1`, failures 0 | UI sampler, UI judge, controlled fixture, Makefile target, Swift detail routing/filtering, or request-card behavior changes | any controlled detail-history simulator proof dependency edit |
| `rtk make sim-ui-controlled-matrix-verify ... SIM_UI_MATRIX_MIN_PASSES=2` with the prior 18 report dirs plus detail-history-request v4/v5 | Expanded ten-scenario double-loop controlled simulator matrix gate | pass; 20 reports, 10 required scenarios, 10 passing scenarios, 2/2 passes per scenario, 0 missing, 0 failed, max observed UI lag 1,717 ms under the 2,000 ms budget, findings 0; artifacts `/tmp/codex-client/sim-ui-controlled-matrix-ten-scenario-double-loop-v1.json` and `.md` | controlled scenario report set, duplicate-dir verifier, UI judge, detail sweep requirements, or required scenario list changes | rerun after any controlled simulator proof dependency edit or before final completion if any dependency changes |
| `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1037Z SIM_UI_CONTROLLED_MATRIX_PASSES=1 MAX_UI_LAG_MS=2000` | Fresh one-pass controlled simulator matrix through the actual `iPhone 17` app display after the fixture cleanup fix | pass; 10 reports, 10 required scenarios, 10 passing scenarios, 0 missing, 0 failed, 0 findings, max observed UI lag 1,781 ms under the 2,000 ms budget. Per-scenario max lags: `detail-history-request` 1,781 ms, `large-list-checkpoint` 0 ms, `thread-activity` 613 ms, `server-request` 946 ms, `source-refresh` 339 ms, `live-lease-expiry` 536 ms, `multi-host-isolation` 1,698 ms, `spawn-edge` 1,070 ms, `resync-gap` 938 ms, `rapid-mutations` 676 ms. Artifacts: `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1037Z/controlled-simulator-matrix.json` and `.md` | controlled scenario report set, fixture cleanup, matrix proof target, matrix verifier, UI judge, detail sweep requirements, or required scenario list changes | rerun after any controlled simulator proof dependency edit or before final completion if any dependency changes |
| `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1042Z SIM_UI_CONTROLLED_MATRIX_PASSES=1 MAX_UI_LAG_MS=2000` | Fresh one-pass controlled simulator matrix through the actual `iPhone 17` app display before the detail evidence-time fix | fail; `detail-history-request` relay/client path passed, but rendered detail transition `detail-history-request-resolution` was recorded at 2,043 ms against the 2,000 ms budget. Artifacts: `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1042Z/pass-1/detail-history-request/simulator-ui-sync.json` and `.md` | superseded by evidence-time timestamp fix, but preserved as lag-gate failure evidence | rerun after any controlled simulator proof dependency edit |
| `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-history-request SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-detail-history-request-evidence-time-20260531T1110Z SIM_UI_SYNC_DURATION_MS=20000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000 SIM_UI_SYNC_RELAY_DURATION_MS=180000` | Targeted `detail-history-request` proof after per-element detail evidence timestamps | pass; 20 UI samples, 17 detail samples, 3 detail transitions, 0 detail failures, 1 detail sweep, 9 detail sweep message-card checks, 0 failures, rendered detail lags 1,413/1,248/1,555 ms under the 2,000 ms budget | UI sampler, UI judge, detail transition scoring, or request-card UI changes | rerun after any detail UI proof dependency edit |
| `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1054Z SIM_UI_CONTROLLED_MATRIX_PASSES=1 MAX_UI_LAG_MS=2000` | Fresh one-pass controlled simulator matrix through the actual `iPhone 17` app display after the detail evidence-time fix | pass; 10 reports, 10 required scenarios, 10 passing scenarios, 0 missing, 0 failed, 0 findings, max observed UI lag 1,762 ms under the 2,000 ms budget. Per-scenario max lags: `detail-history-request` 1,489 ms, `large-list-checkpoint` 0 ms, `thread-activity` 735 ms, `server-request` 920 ms, `source-refresh` 913 ms, `live-lease-expiry` 763 ms, `multi-host-isolation` 1,762 ms, `spawn-edge` 1,137 ms, `resync-gap` 1,225 ms, `rapid-mutations` 718 ms. Artifacts: `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1054Z/controlled-simulator-matrix.json` and `.md` | controlled scenario report set, matrix proof target, matrix verifier, UI sampler, UI judge, detail sweep requirements, or required scenario list changes | rerun after any controlled simulator proof dependency edit or before final completion if any dependency changes |
| `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1100Z SIM_UI_CONTROLLED_MATRIX_PASSES=2 MAX_UI_LAG_MS=2000` | Post-fix two-pass controlled simulator matrix through the actual `iPhone 17` app display | pass; 20 reports, 20 evaluated reports, 10 required scenarios, 10 passing scenarios, 0 missing, 0 failed, 0 findings, max observed UI lag 1,688 ms under the 2,000 ms budget. Per-scenario max lags: `detail-history-request` 1,561 ms, `large-list-checkpoint` 0 ms, `thread-activity` 958 ms, `server-request` 958 ms, `source-refresh` 552 ms, `live-lease-expiry` 690 ms, `multi-host-isolation` 1,688 ms, `spawn-edge` 981 ms, `resync-gap` 1,032 ms, `rapid-mutations` 1,251 ms. Artifacts: `/tmp/codex-client/sim-ui-controlled-matrix-run-20260531T1100Z/controlled-simulator-matrix.json` and `.md` | controlled scenario report set, matrix proof target, matrix verifier, UI sampler, UI judge, detail sweep requirements, or required scenario list changes | rerun after any controlled simulator proof dependency edit or before final completion if any dependency changes |
| `agent -p --force --sandbox disabled --output-format stream-json --trust --workspace /Users/aelaguiz/workspace/codex-client --model composer-2.5-fast < /tmp/fresh-consult/codex-dock-sync-completion-20260531T1112Z-iN08ty/prompt.md` | Required fresh Composer 2.5 Fast completion consult | `VERDICT: pass-with-notes`; `BLOCKING: none`; `CONFIDENCE: high`; summary says the harness meets the relay/client/simulator three-leg completion gate, the 2,043 ms failure was credibly fixed without hiding lag, and remaining items are notes outside the simulator-path completion gate. Artifacts: `/tmp/fresh-consult/codex-dock-sync-completion-20260531T1112Z-iN08ty/final.txt`, `events.jsonl`, `stderr.log`, and `prompt.md` | plan scope, proof artifacts, or completion boundary changes | rerun before any stronger "whole physical installed app" completion claim |
| `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` | Simulator UI proof judge syntax | pass | simulator UI judge changes | any simulator UI judge edit |
| `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockDisplayedSyncProofTests/testSamplesRelayBackedDockDisplayOverTime'` | Simulator UI sampler compile and smoke path | pass, 1 test, 0 failures on `iPhone 17`; result bundle `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.30_23-03-30--0500.xcresult` | UI sampler or app launch env changes | not a completion-grade proof without paired relay report and deterministic observed change |
| `rtk swift test --filter DockStoreTests` | Swift Dock stream/store semantics | pass, 48 tests, 0 failures | Swift Dock code changes | Dock/stream client changes |
| `rtk swift test --filter ThreadDetailStoreTests/testLoadBuffersLiveNotificationsUntilReadTurnsAndResumeFinish` | Swift initial detail live-event buffering | pass | Swift detail code changes | detail load/observation ordering changes |
| `rtk swift test --filter ThreadEventNormalizerTests` | Swift event normalization/default visibility, including request events visible in the default detail view | pass, 11 tests, 0 failures | Swift event visibility changes | event normalization or visibility changes |
| `rtk swift test --filter ThreadDetailStoreTests/testServerRequestEventAppearsNewestFirstWithoutBreakingRequestCardResponse` | Swift detail request-card ordering and response handling | pass, 1 test, 0 failures | Swift detail request handling changes | detail request-card changes |
| `rtk swift test --filter ThreadDetailStoreTests` | Swift thread detail semantics | pass, 54 tests, 0 failures | Swift detail code changes | detail load/observation, request-card, or voice-detail changes |
| `rtk swift test --filter AppServerClientTests` | Swift JSON-RPC route/DTO semantics | pass, 52 tests, 5 expected skips, 0 failures | app-server client changes | JSON-RPC/DTO changes |
| Exhaustive real-home audit v2 | Real relay, client routes plus exhaustive oracle classification | pass; `clientPathOK: true`, `clientRequiredOracleOK: true`, `clientRequiredParityFailures: 0`, `longLivedStreamMismatches: 0`, `detailFailures: 0` | local Codex state or relay changes | rerun after relay/app-server state changes |
| Client-path soak v6 | Real relay, 65s over-time client-route proof | pass; 2 samples, `clientPathOK: true`, `dock/update: 44`, `detailFailures: 0`, `streamResyncCount: 0` | relay stream changes or local state changes | rerun after stream/detail changes |
| Client-path soak v7 | Second real relay 65s over-time client-route proof | pass; 2 samples, same route counts and no failures | relay stream changes or local state changes | rerun after stream/detail changes |
| Exhaustive two-sample soak v1 | Real relay, over-time client-route proof plus exhaustive oracle classification | pass; 2 samples, `clientPathOK: true`, `clientRequiredOracleOK: true`, `dock/update: 57`, `thread/read: 2`, `thread/turns/list: 2`, `thread/resume: 2`, `clientRequiredParityFailures: 0`, `longLivedStreamMismatches: 0` | local Codex state or relay changes | rerun after relay/app-server state changes |
| Forced-resync client-path soak v2 | Real relay, over-time client-route proof with explicit `dock/resync` | pass; 2 samples, `clientPathOK: true`, `dock/resync: 4`, `dock/update: 119`, `thread/read: 10`, `thread/turns/list: 10`, `thread/resume: 10`, `longLivedStreamMismatches: 0`, `streamLagFailures: 0`, `detailFailures: 0` | relay stream/resync changes | rerun after stream/resync changes |
| Forced-resync exhaustive v2 | Real relay, `dock/resync` plus exhaustive oracle classification | client path passed; oracle failed because SQLite thread IDs changed during the audit | local Codex moving state | rerun only when a stable oracle window is needed |
| Client-path lag soak v1 | Real relay, over-time client-route proof with 2,000 ms lag budget | failed; long-lived stream stayed partial within the audit window and exposed catch-up restart bug | superseded by fix | preserved as failure evidence |
| Client-path lag soak v2 | Real relay, over-time client-route proof with 2,000 ms lag budget | pass; 2 samples, `clientPathOK: true`, `streamLagFailures: 0`, `maxObservedStreamLagMs: 0`, `detailFailures: 0` | relay stream changes or local state changes | rerun after stream/detail changes |
| Detail-boundary strict v1 | Real relay, sampled detail live-boundary check without modeling client buffer | failed; 5 `detail_live_before_boundary` findings while target-thread notifications arrived during `thread/resume` | superseded by Swift buffering fix and v3 proof | preserved as failure evidence |
| Detail-boundary v3 | Real relay, actual client-route detail proof with initial live buffering modeled | pass; 2 samples, `clientPathOK: true`, `detailBufferedInitialLiveEvents: 4`, `detailFailures: 0`, `streamLagFailures: 0`, `maxObservedStreamLagMs: 0` | relay/detail/client buffering changes or local state changes | rerun after stream/detail changes |
| Scenario archive-toggle v1 | Real relay, actual `thread/archive`/`thread/unarchive` routes and long-lived Dock stream | failed; selected a `running` row, `thread/archive` closed the upstream websocket, and archive appeared after 25,128 ms | superseded by idle-target selector and v2 proof | preserved as failure evidence |
| Scenario archive-toggle v2 | Real relay, actual `thread/archive`/`thread/unarchive` routes and long-lived Dock stream | pass; archive lag 34 ms, unarchive lag 37 ms, no failures | relay archive/unarchive or scenario selector changes | rerun after archive/unarchive or state projection changes |
| Scenario archive-toggle v3 | Real relay, actual archive/unarchive with first-visible lag measurement | pass; archive lag 35 ms, unarchive lag 39 ms | superseded by state-store v4 proof | preserved as measurement-fix evidence |
| Scenario archive-toggle v4 | Real relay after stale-active-list resurrection fix | pass; archive lag 37 ms, unarchive lag 31 ms; fresh `dock/subscribe` agreed with long-lived stream | relay archive/unarchive or state projection changes | rerun after archive/unarchive or state projection changes |
| Scenario detail-reconnect v1 | Real relay, actual detail routes repeated before and after reconnect | pass; `scenarioOK: true`, `clientPathOK: true`, `thread/read: 2`, `thread/turns/list: 2`, `thread/resume: 2`, selected running Dock row loaded 3 turns with no duplicates, reconnect live boundary reached in 68 ms under the 2,000 ms budget, failures 0 | relay detail, detail route, or scenario runner changes | rerun after detail/reconnect or scenario changes |
| Scenario resync-gap v2 | Real relay, actual `dock/resync` route after client-side detected stream gap state | pass; `scenarioOK: true`, `clientPathOK: true`, one `dock/resync`, 1,701 stream cards matched 1,701 fresh `dock/subscribe` cards, resync recovery lag 18 ms under the 2,000 ms budget | relay stream/resync or scenario runner changes | rerun after stream/resync or scenario changes |
| Scenario source-refresh v1 | Controlled upstream failure/recovery through a real in-process relay and actual `dock/subscribe`/`dock/update` client routes | pass; `scenarioOK: true`, `clientPathOK: true`, stale source state appeared with cached row still visible in 1 ms, recovery replaced cached row with recovered row in 0 ms, final long-lived stream matched fresh `dock/subscribe`, failures 0 | relay source refresh, state freshness, Dock stream, or scenario runner changes | rerun after source refresh or state freshness changes |
| Scenario server-request v1 | Controlled live detail request through a real in-process relay and actual detail client routes | pass; `scenarioOK: true`, `clientPathOK: true`, `thread/read: 1`, `thread/turns/list: 1`, `thread/resume: 1`, one target-thread request observed, client response reached upstream, `serverRequest/resolved` returned, request lag 1 ms and resolution lag 12 ms under the 2,000 ms budget, failures 0 | relay detail forwarding, server request handling, or scenario runner changes | rerun after detail/server-request changes |
| Scenario thread-activity v2 | Controlled app-server thread-list changes through a real in-process relay and actual `dock/subscribe`/`dock/update` routes | pass; `scenarioOK: true`, `clientPathOK: true`, new thread appeared first in render order in 1 ms, existing thread updated and moved to first in render order in 1 ms, long-lived stream matched fresh `dock/subscribe` after both transitions, failures 0 | relay Dock reconciliation, order keys, stream comparison, or scenario runner changes | rerun after Dock stream/order changes |
| Scenario live-lease-expiry v1 | Controlled live app-server lease through a real in-process relay and actual `dock/subscribe`/`dock/update` routes | pass; `scenarioOK: true`, `clientPathOK: true`, running row expired to `unknown` on the long-lived stream 4 ms after the lease expiry timestamp under the 2,000 ms budget, fresh `dock/subscribe` matched the stream, failures 0 | relay live leases, state reconciliation, expiry timer, Dock stream, or scenario runner changes | rerun after live lease/state projection changes |
| Scenario multi-host-isolation v1 | Two controlled app-server fixtures through two real in-process relays and actual `dock/subscribe`/`dock/update` routes | pass; `scenarioOK: true`, `clientPathOK: true`, both hosts exposed `shared-thread-id` with host-scoped card ids, host A update appeared in 1 ms under the 2,000 ms budget, host B did not receive host A's new row, failures 0 | relay host identity, card id scoping, Dock stream, or scenario runner changes | rerun after host identity or Dock stream changes |
| Scenario spawn-edge v1 | Controlled app-server subagent spawn through a real in-process relay and actual `dock/subscribe`/`dock/update`/`thread/read` routes | pass; `scenarioOK: true`, `clientPathOK: true`, spawned child appeared as `agent`/`automation` in 1 ms under the 2,000 ms budget, fresh `dock/subscribe` matched the long-lived stream, and `thread/read` exposed parent thread id `spawn-edge-parent`, failures 0 | relay source filtering, spawn metadata parsing, Dock stream, detail read forwarding, or scenario runner changes | rerun after source/spawn/Dock/detail route changes |
| Scenario goal-change v1 | Controlled app-server goal fixture through a real in-process relay | failed; `thread/goal/get` returned updated goal state, but the fixture did not force initial Dock reconciliation before checking the Dock row, so the row was missing from the fresh Dock subscription | superseded by v2 initial projection fix | preserved as harness fixture failure evidence |
| Scenario goal-change v2 | Controlled app-server goal fixture through a real in-process relay and `thread/goal/get` | pass; `scenarioOK: true`, `clientPathOK: true`, `thread/goal/get` was recorded under `nonClientPathRoutes`, updated goal status changed from `in_progress` to `complete` in 1 ms under the 2,000 ms budget, failures 0 | relay goal forwarding, goal route boundary, scenario runner changes, or if Swift starts consuming goal fields | rerun after goal route or client goal contract changes |
| Scenario all client-path v1 | Relay-level combined required scenario matrix with two archive/unarchive repetitions | pass; `scenarioOK: true`, `clientPathOK: true`, 10 scenario groups, 0 scenario failures, 0 unimplemented required scenarios, routes included `dock/subscribe`, `dock/update`, `dock/resync`, `thread/archive`, `thread/unarchive`, `thread/read`, `thread/turns/list`, and `thread/resume`; worst scenario lag was 194 ms under the 2,000 ms budget | sync-audit scenario runner, relay routes, or required scenario list changes | rerun after scenario runner or relay route changes |
| Simulator displayed-UI smoke | `iPhone 17` UITest sampler through real relay-backed app path | pass; 3 UI samples written to `/tmp/codex-client/sim-ui-sync-smoke/ui-samples.jsonl` | UI automation or simulator launch changes | rerun after UI sampler changes |
| Simulator displayed-UI over-time v1 | `rtk make sim-ui-sync-proof` with real relay/client-route report plus literal UI samples | pass; 7 UI samples, 6 scored UI samples, 3 relay samples, 24 displayed-row checks, 1 detail sample, `uiLag.observedLagMs: 0`, failures 0 | UI, relay sync audit, or Makefile simulator flow changes | rerun after UI/judge/relay changes |
| Simulator scenario archive-toggle v1 | `iPhone 17` UI sampler plus real archive/unarchive scenario | failed before UI judge; relay unarchive lag measured as 4,151 ms because the harness waited for full stream catch-up instead of first visible target-row change | superseded by lag measurement fix | preserved as harness failure evidence |
| Simulator scenario archive-toggle v3 | `iPhone 17` UI sampler plus real archive/unarchive scenario | failed; relay path passed, rendered UI exceeded 2,000 ms budget under the old coarse timestamp/detail-only judge | superseded by timestamp/detail-only/sampler fixes | preserved as UI-judge failure evidence |
| Simulator scenario archive-toggle v4 | `iPhone 17` UI sampler plus real archive/unarchive scenario | failed before UI judge; fresh `dock/subscribe` still contained archived target while long-lived stream had removed it | superseded by stale-active-list resurrection fix | preserved as real client-path bug evidence |
| Simulator scenario archive-toggle v5 | `rtk make sim-ui-scenario-sync-proof` on `iPhone 17` | pass; 9 UI samples, 6 scored, 2 scenario transitions, archive UI lag 1,011 ms, unarchive UI lag 67 ms, worst rendered convergence 1,801 ms under 2,000 ms, failures 0 | UI, relay sync audit, archive/unarchive, or Makefile simulator flow changes | rerun after UI/judge/relay/scenario changes |

Report artifacts:

- `/tmp/codex-client/sync-audit-real-home-exhaustive-v2.json`
- `/tmp/codex-client/sync-audit-real-home-exhaustive-v2.md`
- `/tmp/codex-client/sync-audit-real-home-client-path-soak-v6.json`
- `/tmp/codex-client/sync-audit-real-home-client-path-soak-v6.md`
- `/tmp/codex-client/sync-audit-real-home-client-path-soak-v7.json`
- `/tmp/codex-client/sync-audit-real-home-client-path-soak-v7.md`
- `/tmp/codex-client/sync-audit-real-home-exhaustive-soak-v1.json`
- `/tmp/codex-client/sync-audit-real-home-exhaustive-soak-v1.md`
- `/tmp/codex-client/sync-audit-real-home-client-path-force-resync-v1.json`
- `/tmp/codex-client/sync-audit-real-home-client-path-force-resync-v1.md`
- `/tmp/codex-client/sync-audit-real-home-client-path-force-resync-v2.json`
- `/tmp/codex-client/sync-audit-real-home-client-path-force-resync-v2.md`
- `/tmp/codex-client/sync-audit-real-home-exhaustive-force-resync-v2.json`
- `/tmp/codex-client/sync-audit-real-home-exhaustive-force-resync-v2.md`
- `/tmp/codex-client/sync-audit-real-home-client-path-lag-v1.json`
- `/tmp/codex-client/sync-audit-real-home-client-path-lag-v1.md`
- `/tmp/codex-client/sync-audit-real-home-client-path-lag-v2.json`
- `/tmp/codex-client/sync-audit-real-home-client-path-lag-v2.md`
- `/tmp/codex-client/sync-audit-real-home-detail-boundary-v1.json`
- `/tmp/codex-client/sync-audit-real-home-detail-boundary-v1.md`
- `/tmp/codex-client/sync-audit-real-home-detail-boundary-v3.json`
- `/tmp/codex-client/sync-audit-real-home-detail-boundary-v3.md`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v1.json`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v1.md`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v2.json`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v2.md`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v3.json`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v3.md`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v4.json`
- `/tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v4.md`
- `/tmp/codex-client/detail-reconnect-scenario-v1/relay-client-path.json`
- `/tmp/codex-client/detail-reconnect-scenario-v1/relay-client-path.md`
- `/tmp/codex-client/resync-gap-scenario-v2/relay-client-path.json`
- `/tmp/codex-client/resync-gap-scenario-v2/relay-client-path.md`
- `/tmp/codex-client/source-refresh-scenario-v1/relay-client-path.json`
- `/tmp/codex-client/source-refresh-scenario-v1/relay-client-path.md`
- `/tmp/codex-client/server-request-scenario-v1/relay-client-path.json`
- `/tmp/codex-client/server-request-scenario-v1/relay-client-path.md`
- `/tmp/codex-client/thread-activity-scenario-v2/relay-client-path.json`
- `/tmp/codex-client/thread-activity-scenario-v2/relay-client-path.md`
- `/tmp/codex-client/live-lease-expiry-scenario-v1/relay-client-path.json`
- `/tmp/codex-client/live-lease-expiry-scenario-v1/relay-client-path.md`
- `/tmp/codex-client/multi-host-isolation-scenario-v1/relay-client-path.json`
- `/tmp/codex-client/multi-host-isolation-scenario-v1/relay-client-path.md`
- `/tmp/codex-client/spawn-edge-scenario-v1/relay-client-path.json`
- `/tmp/codex-client/spawn-edge-scenario-v1/relay-client-path.md`
- `/tmp/codex-client/goal-change-scenario-v1/relay-protocol.json`
- `/tmp/codex-client/goal-change-scenario-v1/relay-protocol.md`
- `/tmp/codex-client/goal-change-scenario-v2/relay-protocol.json`
- `/tmp/codex-client/goal-change-scenario-v2/relay-protocol.md`
- `/tmp/codex-client/scenario-all-client-path-v1/relay-client-path.json`
- `/tmp/codex-client/scenario-all-client-path-v1/relay-client-path.md`
- `/tmp/codex-client/sim-ui-sync-smoke/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-sync-proof-over-time-v1/relay-client-path.json`
- `/tmp/codex-client/sim-ui-sync-proof-over-time-v1/relay-client-path.md`
- `/tmp/codex-client/sim-ui-sync-proof-over-time-v1/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-sync-proof-over-time-v1/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-sync-proof-over-time-v1/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v1/relay-client-path.json`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v3/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v4/relay-client-path.json`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v5/relay-client-path.json`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v5/relay-client-path.md`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v5/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v5/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-scenario-archive-toggle-v5/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v1/sim-ui/relay-client-path.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v2/isolated-home.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v2/sim-ui/relay-client-path.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v2/sim-ui/relay-client-path.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v2/sim-ui/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-isolated-scenario-v2/sim-ui/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v2/sim-ui/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v3-checkpoint/sim-ui/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v3-checkpoint/sim-ui/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db/isolated-home.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db/service/relay-state.sqlite`
- `/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db/sim-ui/relay-client-path.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db/sim-ui/relay-client-path.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db/sim-ui/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db/sim-ui/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db/sim-ui/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle/isolated-home.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle/service/relay-state.sqlite`
- `/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle/sim-ui/relay-client-path.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle/sim-ui/relay-client-path.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle/sim-ui/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle/sim-ui/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle/sim-ui/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v6-multi-row-checkpoint/isolated-home.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v6-multi-row-checkpoint/sim-ui/relay-client-path.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v6-multi-row-checkpoint/sim-ui/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-isolated-scenario-v6-multi-row-checkpoint/sim-ui/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v6-multi-row-checkpoint/sim-ui/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v7-multi-row-stable/isolated-home.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v7-multi-row-stable/sim-ui/relay-client-path.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v7-multi-row-stable/service/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.31_00-40-12--0500.xcresult`
- `/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture/isolated-home.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture/sim-ui/relay-client-path.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture/sim-ui/relay-client-path.md`
- `/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture/sim-ui/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture/sim-ui/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture/sim-ui/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/fixture-ready.json`
- `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/relay-client-path.md`
- `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/fixture-ready.json`
- `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/relay-client-path.md`
- `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/fixture-ready.json`
- `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/relay-client-path.md`
- `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/fixture-ready.json`
- `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/relay-client-path.md`
- `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/fixture-ready.json`
- `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/relay-client-path.md`
- `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/fixture-ready.json`
- `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/relay-client-path.md`
- `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/ui-samples.jsonl`
- `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/simulator-ui-sync.md`
- `/tmp/codex-client/sim-ui-controlled-matrix-v1.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-v1.md`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/controlled-simulator-matrix.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/controlled-simulator-matrix.md`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/thread-activity/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/server-request/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/source-refresh/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/live-lease-expiry/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/multi-host-isolation/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/spawn-edge/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/resync-gap/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/pass-1/rapid-mutations/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-double-loop-v1-v2.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-double-loop-v1-v2.md`
- `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v1/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v1/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v2/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v2/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-nine-scenario-double-loop-v1.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-nine-scenario-double-loop-v1.md`
- `/tmp/codex-client/sim-ui-controlled-detail-history-request-v4/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-detail-history-request-v4/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-detail-history-request-v5/relay-client-path.json`
- `/tmp/codex-client/sim-ui-controlled-detail-history-request-v5/simulator-ui-sync.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-ten-scenario-double-loop-v1.json`
- `/tmp/codex-client/sim-ui-controlled-matrix-ten-scenario-double-loop-v1.md`

## Continuous Review Ledger

| Finding | Source | Status | Repair anchor | Notes |
| --- | --- | --- | --- | --- |
| Long-lived stream could stay at stale live status after a fresh `dock/subscribe` already showed lease-expired status | Real smoke v2/v3 and live-lease-expiry v1 | Fixed | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay.test.mjs`, `--scenario live-lease-expiry` | Store now compares/publishes current client-projected cards, records one expiry publication per lease, and schedules a near-real-time expiry reconcile. |
| `relay/state/snapshot` was incomplete because `thread/goal/get` returned `thread not found` for 3 listable rows | Exhaustive audit v1 and direct snapshot probe | Classified outside current client contract | `classifyParityForClientContract` | Goal fields are not exposed by `DockThreadCardDTO` or current `ThreadDetailStore` routes. |
| Non-exhaustive soak spent the whole window in parity and could not take multiple samples | Real soak v5 | Fixed by adding `--client-path-only` | `scripts/dock-relay-sync-audit.mjs` | Exhaustive oracle proof remains separate; over-time soak now exercises only actual client routes. |
| Passing real soaks did not exercise `dock/resync` | Composer 2.5 Fast fresh consult | Fixed for client-path proof | `--force-dock-resync`; forced-resync client-path v2 | Real report now counts `dock/resync` on actual relay path. |
| `clientContractOK` could be misread as pure client-path proof | Composer 2.5 Fast fresh consult | Fixed | summary now uses `clientRequiredOracleOK` and keeps `clientPathOK` separate | Fresh forced-resync v2 JSON has no `clientContractOK` field and shows `clientRequiredOracleOK: null`. |
| Forced-resync exhaustive v2 failed oracle checks while client path passed | Real forced-resync exhaustive v2 | Classified as moving-state oracle failure | report unsupported facts and `completionBoundary.movingState` | SQLite thread IDs changed during the long audit; not hidden or counted as client-path failure. |
| Earlier broad `ThreadDetailStoreTests` run hit a timeout in `testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit` | `rtk swift test --filter ThreadDetailStoreTests` | Superseded by latest broad passing run | exact single-test reruns and latest broad run | The timeout was preserved as flaky/test-stability evidence; latest broad `ThreadDetailStoreTests` passed 54 tests, 0 failures. |
| Initial detail live events could be overwritten by historical load replacement | Real detail-boundary v1 and Swift code review | Fixed | `CodexDock/State/ThreadDetailStore.swift`; `testLoadBuffersLiveNotificationsUntilReadTurnsAndResumeFinish` | Notifications/requests received between observation start and the safe live boundary are now buffered and replayed after initial history is installed. |
| Broad `ThreadDetailStoreTests` is no longer a clean latest proof after the detail buffering change | Latest broad reruns | Closed by latest broad passing run | exact `testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit` rerun plus full `ThreadDetailStoreTests` | The new buffering regression passed, the exact voice hold rerun passed, and the latest broad suite passed 54 tests with 0 failures. |
| XCUITest runner did not inherit shell env for simulator UI proof settings | First sampler attempt | Fixed | `CodexDockDisplayedSyncProofTests.swift`; `rtk make sim-ui-sync-proof` writes `/tmp/codex-client/codex-dock-sim-ui-sync-config.json` | The proof no longer passes or skips based on invisible env; target removes the config after use. |
| Sampler initially treated a hidden Dock root as failure after opening detail | First real sampler run | Fixed | `captureDisplayedUISample` records `not-visible` for Dock while detail is open | Detail samples can coexist with Dock samples in the same JSONL report. |
| Sampler initially recorded a temporary `Partial` Dock root as a normal sample | Short sampler run | Fixed | sampler waits for `loaded` without `Partial` before recording | Prevents startup partial data from being mistaken for a clean displayed-UI sample. |
| Controlled scenario mode lacked actuators | Plan completion gate | Fixed for relay-level matrix | `--scenario archive-toggle`, `detail-reconnect`, `goal-change`, `resync-gap`, `source-refresh`, `server-request`, `thread-activity`, `live-lease-expiry`, `multi-host-isolation`, `spawn-edge`, and `all` in `scripts/dock-relay-sync-audit.mjs` | Required relay-level scenario families now have harness entries; `goal-change` is intentionally relay-protocol proof, not client-path proof. `scenario-all` v1 passed with 10 scenario groups and no unimplemented required scenarios. |
| Isolated service dry-run prefixed absolute `/tmp` env paths with the repo path | Isolated `CODEX_HOME` service dry-run | Fixed | `Makefile` path normalization | `APP_SERVER_ABS_DIR`, `ENV_FILE_ABS`, and `HOST_ENV_FILE_ABS` now use make's `abspath`; isolated dry-run shows clean `/tmp/codex-client/...` paths. |
| Scenario archive-toggle initially selected a running row and exposed slow/failing archive behavior | Real scenario archive-toggle v1 | Fixed for default target selection; failure preserved | `selectScenarioArchiveTarget` now prefers idle rows | The failure remains useful evidence: archiving a running row failed and took 25,128 ms to reach the Dock stream. |
| Scenario lag measurement waited for full paged stream catch-up instead of first target visibility | Simulator scenario archive-toggle v1 | Fixed | `waitForStreamThreadPresence` now measures first target-row presence/absence after mutation start | Prevents the harness itself from inventing lag while preserving the full-stream comparison after the transition. |
| Resync-gap scenario initially measured lag from a later unrelated stream update instead of the resync response | Scenario resync-gap v1 | Fixed | `runResyncGapScenario` now uses the `dock/resync` response completion timestamp for resync recovery lag | v2 reports 18 ms recovery instead of conflating recovery with later catch-up notifications. |
| Simulator UI judge let detail-only samples satisfy Dock transition proof | Simulator scenario archive-toggle v3 | Fixed | `evaluateUISample` marks detail-only samples unscored for Dock proof | Detail samples can still validate detail structure, but they no longer prove Dock sync. |
| Simulator UI samples used second-resolution timestamps and slow large-query enumeration | Simulator scenario archive-toggle v3 | Fixed | fractional `sampledAt`; visible-row scans avoid `query.count` | Required for an honest 2,000 ms budget. |
| Fresh `dock/subscribe` could resurrect a just-archived row from stale active-list reconciliation | Simulator scenario archive-toggle v4 | Fixed | `RELAY_STATE_ARCHIVE_MUTATION_GRACE_MS`; `RelayStateStore.applyDockReconciliation` | Fresh snapshots and long-lived streams now agree immediately after successful archive mutation. |
| `thread/unarchive` delta omitted the active live lease projection | Isolated simulator scenario v1 | Fixed | `RelayStateStore.cardForThread`; `relay state archive mutation projects live leases into unarchive deltas` | Fresh `dock/subscribe` returned `running` while the long-lived stream received `dormant` at the same seq; unarchive deltas now apply live leases before publishing. |
| Isolated relay services reused repo-level relay state database/cache | Checkpointed isolated simulator v3 | Fixed | `--relay-state-db`; host service runtime `relay-state.sqlite`; `CODEX_DOCK_RELAY_STATE_DB` | v3 leaked old cached rows into the isolated proof, showed about 1,697 old rows, and failed with stale `unknown` displayed status for 6,035 ms; v4 passed after the relay DB moved under the temp service runtime. |
| Isolated multi-thread seeder could select a stale active SQLite row whose rollout lived under `archived_sessions/...` | Multi-row simulator v6 | Fixed for fixture selection | `isActiveSessionRolloutRelative` in `scripts/codex-dock-isolated-home.mjs`; multi-thread seeder test fixture | v6 used a row that later disappeared during reconciliation and produced a 3,415 ms rendered-UI lag failure. Active simulator fixtures now require `sessions/...` rollout paths. |
| Multi-row simulator mutation proof can fail while XCUITest reads a row that disappears during a live list update | Multi-row simulator v7 | Fixed for sampler crash | `CodexDockDisplayedSyncProofTests.visibleDockRows()` now uses `allElementsBoundByIndex` snapshots | v8 passed the same two-thread displayed-UI scenario shape; live row removal no longer crashes the sampler before the judge can score. |
| The two-thread archive fixture can select related or unstable source rows whose fresh reconciliation erases the control row | Multi-row simulator v7 relay logs | Watch | fixture selection or scenario design may need deterministic stable-row criteria | v8 selected two independent active `sessions/...` rows and passed with a two-row checkpoint sweep. Keep as a watch item before claiming broad multi-row/lazy-list coverage. |
| Controlled simulator fixture must share the relay it mutates with the simulator app | User client-path fairness requirement | Fixed for current controlled simulator slices | `scripts/dock-relay-controlled-simulator-fixture.mjs`; `Makefile` `sim-ui-controlled-scenario-sync-proof` | The fixture writes its temporary relay host before the app launches; the app samples that same relay while the fixture mutates source rows. This pattern is now proven for `detail-history-request`, `large-list-checkpoint`, `thread-activity`, `server-request`, `source-refresh`, `live-lease-expiry`, `multi-host-isolation`, `spawn-edge`, `resync-gap`, and `rapid-mutations`. Unsupported simulator fixture scenarios are rejected until wired to the same pattern. |
| Controlled simulator proof only swept small visible row sets | Phase 6 breadth review | Fixed for current Dock list breadth and opened-thread detail breadth | `large-list-checkpoint`; `detail-history-request`; `matrix_checkpoint_sweep_row_checks_missing`; `matrix_detail_sweep_message_checks_missing`; `sim-ui-controlled-matrix-ten-scenario-double-loop-v1` | The Dock scenario seeds 18 rows through the same temporary relay used by the app and passed twice with 18/18 sweep rows found. The detail scenario opens the real thread detail screen, uses the real `All` filter, and passed twice with 9/9 opened-thread detail rows found. The matrix now requires both checkpoint sweep breadth and detail sweep breadth. |
| Detail sample capture could crash while a real detail screen was still loading | Controlled simulator thread-activity v1 | Fixed | `CodexDockDisplayedSyncProofTests.visibleDetail()` | Missing loading-state detail sub-elements now record `not-visible` instead of ending the XCTest run before the Node judge can score Dock proof. |
| UI judge treated later transition warmup animation as a permanent post-convergence duplicate-row failure | Controlled simulator thread-activity v2 | Fixed | `finishedAt` UI sample timing; `ignoredScenarioWarmupSampleIndexes` in `scripts/dock-relay-simulator-ui-sync-proof.mjs` | Scenario-window mismatches are now scored by that transition's lag budget; v3 passed with transition UI lags 627 ms and 628 ms under the 2,000 ms budget and a stable three-row checkpoint sweep. |
| Detail sampler duplicated slow accessibility queries and could lag behind request/detail transitions | Controlled detail-history-request v1/v2 | Fixed | `CodexDockDisplayedSyncProofTests.visibleDetail()`; `elementSnapshots(prefix:)` | The sampler now captures message/request elements once per sample and derives IDs from those snapshots. This keeps the proof honest against the 2,000 ms client-visible lag budget instead of letting harness overhead create false lag. |
| Pending request transition required full history rows in the same visible viewport sample | Controlled detail-history-request v3 | Fixed | `detailTruth.expectedMessageEventIDs`; `checkpointDetailSweep()`; `combinedDetailForSample()` | The pending transition now proves the request card appears in real time. The final resolution plus detail sweep owns full opened-thread row completeness, so the harness matches what the client can literally display at one moment. |
| Full plan completion claim would overstate current proof | Composer 2.5 Fast follow-up consult | Closed for relay/client/simulator path; open only for broader physical/real-live display claims | plan phases 4-7 | Relay-level matrix proof, controlled simulator double-loop proof, Dock lazy-list checkpoint proof, controlled detail-history/request proof, Phase 7 runbook documentation, fresh real-home forced-resync soak, fresh real-home unforced soak, post-fix two-pass simulator matrix, and final Composer consult are now green. Installed physical display proof remains outside the simulator-path completion claim. |

## Side Doors And Deletes

| Surface | Expected state | Current state | Status | Anchor |
| --- | --- | --- | --- | --- |
| `dock-relay-state-parity.mjs` | Remains canonical one-shot parity source | Exports reused by sync audit | Keep | `scripts/dock-relay-state-parity.mjs` |
| Raw reports | No prompt text, transcript text, bearer token, or full payload logs | Current reports are sanitized by sync audit | Keep under `/tmp/codex-client` | `sanitizeDockSnapshotForReport` |
| `.env` | User-owned, unchanged | Unchanged | Keep | repo instructions |

## Decision Carry-Through

| Decision | Owner | Plan carry-through | Code carry-through | Status |
| --- | --- | --- | --- | --- |
| Only actual client-exercised relay routes count as client-path proof | User | Time-based and client-surface definitions | `CLIENT_PATH_ROUTES`, `clientPathEvidence`, `--client-path-only` | Done |
| Significant lag is a client-visible failure even if eventual sync succeeds | User | Time-Based Sync and completion gate | `--max-stream-lag-ms`, `streamLagFailures`, `maxObservedStreamLagMs`, `--max-ui-lag-ms`, scenario lag fields, `scenarioTransitionCoverage`, `detailTransitionCoverage` | Done for relay stream, passive simulator proof, real-home archive/unarchive, real-home resync-gap, real-home detail-reconnect, fresh real-home forced-resync soak, fresh real-home unforced soak, controlled source-refresh, controlled server-request, controlled thread-activity, controlled live-lease-expiry, controlled multi-host-isolation, controlled spawn-edge, controlled rapid-mutations, controlled large-list-checkpoint, controlled detail-history-request, controlled goal-change relay-protocol proof, scenario-all relay matrix, isolated archive/unarchive simulator transition, controlled simulator matrix v1, controlled simulator matrix v2, double-loop v1+v2, nine-scenario double-loop, and ten-scenario double-loop | Remaining lag proof breadth is installed physical display and any future client-visible scenario added to the contract |
| Literal simulator display is the third proof leg before completion | User | Phase 6 and completion gate | `sim-ui-sync-proof`; `sim-ui-scenario-sync-proof`; `sim-ui-isolated-scenario-sync-proof`; `sim-ui-controlled-scenario-sync-proof`; `sim-ui-controlled-matrix-proof`; `SIM_UI_ISOLATED_THREAD_COUNT`; v5 isolated repeated paired run passes; v8 two-thread proof passes; controlled matrix v1/v2, large-list v1/v2, detail-history-request v4/v5, nine-scenario double-loop, ten-scenario double-loop, post-fix two-pass matrix, and final Composer consult pass-with-notes | First real-home and isolated archive/unarchive transitions done; repeated two-cycle archive/unarchive proof done; bounded single-row/two-row/controlled three-row/five-row/eighteen-row checkpoint sweeps implemented and proven; controlled new-thread/reorder, request-card/resolution, stale-source/recovery, live running-to-unknown, two-host same-thread-id, spawned automation-row, sequence-gap resync, rapid visible status mutation, large-list checkpoint, and detail-history/request simulator display proofs done through the matrix. Remaining notes are physical phone display and natural real-relay simulator-display breadth if those broader claims are needed. |
| Oracle reads can diagnose drift but do not prove client delivery | User/plan | Four-plane comparison boundaries | `oracleEvidence`, `classifyParityForClientContract`, `clientRequiredOracleOK` | Done |
| Goal parity gaps are not client failures unless goal fields become client-visible | Codex | Unsupported facts taxonomy | `currentThreadGoalsExact` classified outside client contract; `goal-change` records `thread/goal/get` under non-client-path routes | Done for current client contract |
| Long-lived stream and fresh client subscription must converge without hidden resync | Plan | Time-based sync and relay projection probe | `DockStreamProbe`, repeated stream comparisons, `resync-gap` scenario | Done for relay stream, explicit resync-gap, fresh real-home forced-resync soak, and fresh real-home unforced soak; spontaneous real-home gap recovery remains opportunistic because no natural sequence gap occurred during the fresh unforced window |

## Pass Notes

### 2026-05-31 - Harness Implemented

- Added `scripts/dock-relay-sync-audit.mjs`.
- Added `scripts/dock-relay-sync-audit.test.mjs`.
- Added the script to `package.json` `test:relay`.
- The harness supports `one-shot`, `read-only-real-home`, `soak`, and
  `scenario` modes. The first implemented scenario actuator is
  `archive-toggle`; the rest of the required scenario list remains future
  work.
- The harness records `clientPathEvidence` separately from `oracleEvidence`.
- The harness starts detail probes from actual Dock rows, then exercises
  `thread/read(includeTurns: false)`, `thread/turns/list`, and
  `thread/resume(excludeTurns: true)`.

### 2026-05-31 - Stale Live-Status Stream Bug Fixed

- Symptom: a long-lived `dock/subscribe` stream could keep `dormant` while a
  fresh `dock/subscribe` already showed `unknown` after live leases expired.
- Root cause: reconciliation compared projected previous cards but published
  raw stored cards; lease-driven projection changes were not emitted to
  long-lived streams.
- Fix: capture previous client-visible cards before lease refresh, then publish
  client-projected reconciliation deltas.
- Regression: `relay state store publishes client-projected status changes from
  live leases`.

### 2026-05-31 - Real Relay Proof

- Service check: `rtk make app-server-status` and
  `rtk make dock-relay-status` reported ready for raw app-server
  `127.0.0.1:4500` and relay `127.0.0.1:4510`.
- Restart attempt note: `rtk make dock-relay-restart` hit launchd bootstrap
  exit 5 and temporarily left both services stopped with `ECONNREFUSED` on
  `127.0.0.1:4500` and `127.0.0.1:4510`; `rtk make services` recovered both.
- Exhaustive v2 command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --duration-ms 0 --sample-interval-ms 1 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --exhaustive --detail sampled --detail-limit 1 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-exhaustive-v2.json --summary-out /tmp/codex-client/sync-audit-real-home-exhaustive-v2.md --summary-only
```

- Exhaustive v2 result: `ok: true`, `clientPathOK: true`,
  `clientRequiredOracleOK: true`, `clientRequiredParityFailures: 0`,
  `longLivedStreamMismatches: 0`, `detailFailures: 0`.
- Oracle-only parity still had unsupported facts and storage disagreements;
  those are recorded in the report and are not counted as client-path proof.

### 2026-05-31 - Exhaustive Over-Time Proof

- Command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --duration-ms 210000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --exhaustive --detail sampled --detail-limit 1 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-exhaustive-soak-v1.json --summary-out /tmp/codex-client/sync-audit-real-home-exhaustive-soak-v1.md --summary-only
```

- Result window: `2026-05-31T03:01:39.217Z` to
  `2026-05-31T03:05:58.240Z`.
- Result: `ok: true`, 2 samples, `clientPathOK: true`,
  `clientRequiredOracleOK: true`, `errors: 0`, `warnings: 0`,
  `clientRequiredParityFailures: 0`, `longLivedStreamMismatches: 0`,
  `detailFailures: 0`, `streamResyncCount: 0`.
- Actual client route counts: `initialize: 5`, `initialized: 5`,
  `dock/subscribe: 3`, `dock/update: 57`, `thread/read: 2`,
  `thread/turns/list: 2`, `thread/resume: 2`.
- Oracle-only parity samples: 2. Unsupported facts remained classified as
  outside current client/app-server support and did not count as client-path
  proof.

### 2026-05-31 - Over-Time Client-Path Proof

- First pass command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --detail sampled --detail-limit 1 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-soak-v6.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-soak-v6.md --summary-only
```

- First pass result: `ok: true`, 2 samples, `clientPathOK: true`,
  `dock/update: 44`, `thread/read: 2`, `thread/turns/list: 2`,
  `thread/resume: 2`, `longLivedStreamMismatches: 0`, `detailFailures: 0`.
- Second pass command: same as above, with output paths ending in `v7`.
- Second pass result: same passing shape as v6.

### 2026-05-31 - Forced Resync Proof

- Current proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --force-dock-resync --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --detail sampled --detail-limit 5 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-force-resync-v2.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-force-resync-v2.md --summary-only
```

- Result window: `2026-05-31T03:29:14.333Z` to
  `2026-05-31T03:30:19.336Z`.
- Result: `ok: true`, 2 samples, `clientPathOK: true`,
  `clientRequiredOracleOK: null`, `errors: 0`, `warnings: 0`,
  `streamResyncCount: 2`, `longLivedStreamMismatches: 0`,
  `streamLagFailures: 0`, `maxObservedStreamLagMs: 0`,
  `detailFailures: 0`.
- Actual client route counts: `initialize: 15`, `initialized: 15`,
  `dock/subscribe: 5`, `dock/update: 119`, `dock/resync: 4`,
  `thread/read: 10`, `thread/turns/list: 10`, `thread/resume: 10`.
- The `null` oracle value is intentional: this report proves actual
  client-exercised relay routes only.
- Fresh JSON check: `/tmp/codex-client/sync-audit-real-home-client-path-force-resync-v2.json`
  does not contain `clientContractOK`.

### 2026-05-31 - Forced Resync Exhaustive Attempt

- Command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --force-dock-resync --duration-ms 0 --sample-interval-ms 1 --settle-ms 1000 --dock-collection-timeout-ms 180000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --exhaustive --detail sampled --detail-limit 1 --detail-observe-ms 100 --request-timeout-ms 300000 --json-out /tmp/codex-client/sync-audit-real-home-exhaustive-force-resync-v2.json --summary-out /tmp/codex-client/sync-audit-real-home-exhaustive-force-resync-v2.md --summary-only
```

- Client-path result: `clientPathOK: true`, `dock/resync: 2`,
  `dock/update: 168`, `thread/read: 1`, `thread/turns/list: 1`,
  `thread/resume: 1`, `longLivedStreamMismatches: 0`,
  `detailFailures: 0`.
- Oracle result: `clientRequiredOracleOK: false`. The report records
  `SQLite thread IDs changed during the audit`; app-server-listable,
  Dock-active-row, and spawn-edge oracle checks were therefore not a stable
  point-in-time proof.
- This failed oracle result is preserved as evidence of the remaining
  non-atomic moving-state gap. It is not counted as client-path failure.

### 2026-05-31 - Lag Budget And Catch-Up Restart

- Added `--max-stream-lag-ms` to make client-visible stream lag a hard failure.
  The default Dock stream budget is 2,000 ms.
- Added sync-audit tests proving slow convergence fails and immediate agreement
  records zero lag.
- First real lag run failed:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 1 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-lag-v1.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-lag-v1.md --summary-only
```

- Failure root cause: the long-lived stream did not complete within the audit
  window after the store sequence changed during Dock window catch-up. This was
  a real over-time client-route failure, not an oracle-only mismatch.
- Fix: `sendCardWindowCatchup` now restarts from a fresh snapshot instead of
  abandoning catch-up when the store sequence changes mid-catch-up.
- Regression: `relay state restarts Dock window catchup when store seq changes
  mid-catchup`.
- Fresh real lag run passed:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 1 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-lag-v2.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-lag-v2.md --summary-only
```

- Fresh result window: `2026-05-31T03:27:35.043Z` to
  `2026-05-31T03:28:40.045Z`.
- Fresh result: `ok: true`, 2 samples, `clientPathOK: true`,
  `streamLagFailures: 0`, `maxObservedStreamLagMs: 0`,
  `detailFailures: 0`.
- Actual client route counts: `initialize: 5`, `initialized: 5`,
  `dock/subscribe: 3`, `dock/update: 41`, `thread/read: 2`,
  `thread/turns/list: 2`, `thread/resume: 2`.
- Full relay regression suite after the fix: `rtk npm run test:relay` passed
  with 135 tests and 0 failures.

### 2026-05-31 - Initial Detail Live Boundary Fixed

- Strict detector command that exposed the race:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --force-dock-resync --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 5 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-detail-boundary-v1.json --summary-out /tmp/codex-client/sync-audit-real-home-detail-boundary-v1.md --summary-only
```

- Strict result: `ok: false`, `clientPathOK: false`, 5
  `detail_live_before_boundary` failures. Target-thread notifications arrived
  during `thread/resume`, before the safe live boundary.
- Root cause: `ThreadDetailStore` started observation before its historical
  `thread/read`, `thread/turns/list`, and `thread/resume` load finished. A
  later `replaceEvents` could overwrite live events that arrived during that
  initial load.
- Fix: `ThreadDetailStore` now buffers initial live notifications and server
  requests, installs the historical state first, then replays the buffered live
  events.
- Regression: `testLoadBuffersLiveNotificationsUntilReadTurnsAndResumeFinish`.
- Focused proof:

```bash
rtk node --check scripts/dock-relay-sync-audit.mjs
rtk node --test scripts/dock-relay-sync-audit.test.mjs
rtk npm run test:relay
rtk swift test --filter ThreadDetailStoreTests/testLoadBuffersLiveNotificationsUntilReadTurnsAndResumeFinish
```

- Focused proof result: sync-audit tests passed with 18 tests and 0 failures;
  full relay tests passed with 138 tests and 0 failures; the targeted Swift
  buffering regression passed.
- Broad Swift note: `rtk swift test --filter ThreadDetailStoreTests` failed
  twice in
  `testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit`
  with `DetailStoreTimeoutError()`. The exact single-test rerun passed.
- Fresh real relay command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --force-dock-resync --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 5 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-detail-boundary-v3.json --summary-out /tmp/codex-client/sync-audit-real-home-detail-boundary-v3.md --summary-only
```

- Fresh real relay result window: `2026-05-31T03:47:13.326Z` to
  `2026-05-31T03:48:18.338Z`.
- Fresh real relay result: `ok: true`, 2 samples, `clientPathOK: true`,
  `clientRequiredOracleOK: null`, `errors: 0`, `warnings: 0`,
  `streamResyncCount: 2`, `detailProbeCount: 10`,
  `detailBufferedInitialLiveEvents: 4`, `detailFailures: 0`,
  `longLivedStreamMismatches: 0`, `streamLagFailures: 0`,
  `maxObservedStreamLagMs: 0`.
- Actual client route counts: `initialize: 15`, `initialized: 15`,
  `dock/subscribe: 5`, `dock/update: 120`, `dock/resync: 4`,
  `thread/read: 10`, `thread/turns/list: 10`, `thread/resume: 10`.
- The `null` oracle value is intentional: this proof ran with
  `--client-path-only`, so oracle reads were not counted as client delivery
  proof.

## Limits Not Closed

- Controlled scenario audit now covers archive/unarchive through actual client
  routes, but the remaining required scenario transitions are not implemented.
- Simulator UI proof has a passive paired relay/UI `sim-ui-sync-proof` pass, a
  real-home archive/unarchive `sim-ui-scenario-sync-proof` pass, and an
  isolated-`CODEX_HOME` repeated archive/unarchive
  `sim-ui-isolated-scenario-sync-proof` pass on `iPhone 17`. Completion-grade
  proof still requires multi-row/lazy-list checkpoint proof and the rest of the
  required transitions, not only archive/unarchive. The bounded checkpoint
  sweep path is implemented and proven for the current single-row isolated
  scenario.
- Physical phone proof was not run.
- Global goal exhaustiveness remains outside current client contract because the
  client does not expose goal fields and app-server does not expose a global
  goal list or SQLite `goal_id`.
- Some SQLite rows are outside app-server `thread/list` enumeration and remain
  classified as unsupported/outside current app-server contract.

### 2026-05-31 - Simulator Displayed-UI Consensus And First Harness Slice

- Required `$model-consensus` completed with Opus 4.8 Max and GPT-5.5 X-High.
- Artifact directory:
  `.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/`.
- Consensus summary:
  `.arch_skill/model-consensus/simulator-displayed-ui-sync-20260531T033355Z/summary.md`.
- Consensus result: converged.
- Main design:
  - use the real `iPhone 17` XCUITest path and relay-backed
    `CODEX_DOCK_HOSTS=<relay>:4510`;
  - do not set `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`;
  - run relay audit and UI sampler concurrently;
  - judge accessibility-tree samples against the existing
    `dock-relay-sync-audit.mjs` truth, not a second oracle;
  - fail rendered UI lag beyond 2,000 ms;
  - use checkpoint sweeps for lazy-list full-set proof;
  - keep passive real-home UI proof as smoke only.
- Important correction: passive real-home displayed-UI observation is not enough
  for completion-grade lag proof because it can pass without an observed
  content change. Completion-grade proof requires a deterministic isolated
  `CODEX_HOME` scenario actuator that creates real app-server, relay, and
  client-visible changes.
- First implementation slice added:
  - `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` records literal
    simulator accessibility samples over time on the relay-backed path.
  - `scripts/dock-relay-simulator-ui-sync-proof.mjs` judges UI samples against
    relay sync-audit reports and applies the existing convergence-lag model.
  - `scripts/dock-relay-simulator-ui-sync-proof.test.mjs` covers parsing,
    matching, post-relay sample scoring, and slow rendered convergence failure.
  - `Makefile` adds `sim-ui-sync-proof`, building for testing first, then
    running the relay recorder and UI sampler concurrently.
- Verification:
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 5 tests, 0 failures.
  - `rtk npm run test:relay` passed: 143 tests, 0 failures.
  - `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockDisplayedSyncProofTests/testSamplesRelayBackedDockDisplayOverTime'`
    passed: 1 UI test, 0 failures.
- Paired relay/UI proof command:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17' SIM_UI_SYNC_DIR='/tmp/codex-client/sim-ui-sync-proof-over-time-v1' SIM_UI_SYNC_DURATION_MS=25000 SIM_UI_SYNC_SAMPLE_MS=3000 SIM_UI_SYNC_RELAY_DURATION_MS=45000 SIM_UI_SYNC_RELAY_SAMPLE_MS=15000 MAX_UI_LAG_MS=2000
```

- Paired relay/UI proof result: `ok: true`, 7 UI samples, 6 scored UI samples,
  3 relay samples, 24 displayed-row checks, 1 detail sample,
  `uiLag.observedLagMs: 0`, `bestConsecutivePassingSamples: 6`, failures 0.
- Relay side for that proof: `clientPathOK: true`, `dock/resync: 6`,
  `dock/update: 171`, `thread/read: 15`, `thread/turns/list: 15`,
  `thread/resume: 15`, `detailBufferedInitialLiveEvents: 5`,
  `streamLagFailures: 0`.
- Current limitation for this older slice: it did not yet implement the
  deterministic isolated-`CODEX_HOME` actuator, app-side 1:1 text
  fingerprints, checkpoint sweeps, or an observed scenario-driven UI
  transition. The isolated archive/unarchive transition and bounded checkpoint
  sweep are covered by later passes below.

### 2026-05-31 - First Controlled Scenario Actuator

- Added `--scenario archive-toggle` to `scripts/dock-relay-sync-audit.mjs`.
- The actuator selects an active Dock row, prefers idle rows by default, calls
  `thread/archive` through the relay, waits for the long-lived Dock stream to
  remove that row, calls `thread/unarchive`, and waits for the row to reappear.
- The scenario records `lag_change_to_relay_ms` and fails if the transition
  exceeds `--max-stream-lag-ms`.
- First real run failed usefully:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode scenario --scenario archive-toggle --client-path-only --detail none --dock-collection-timeout-ms 120000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v1.json --summary-out /tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v1.md --summary-only --fail-on-diff
```

- Failure: the default target was `running`; `thread/archive` closed the raw
  app-server websocket and the Dock stream only reflected archive after
  25,128 ms, above the 2,000 ms budget.
- Fix: default target selection now prefers `idle`, then `dormant`, then
  `unknown`, and only falls back to active/problem statuses if needed.
- Fresh real run passed:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode scenario --scenario archive-toggle --client-path-only --detail none --dock-collection-timeout-ms 120000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v2.json --summary-out /tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v2.md --summary-only --fail-on-diff
```

- Fresh result: `ok: true`, `thread/archive: 1`, `thread/unarchive: 1`,
  archive lag 34 ms, unarchive lag 37 ms, failures 0.
- Checks after the change: `rtk node --check scripts/dock-relay-sync-audit.mjs`
  passed; `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed with
  21 tests and 0 failures; `rtk npm run test:relay` passed with 146 tests and
  0 failures.

### 2026-05-31 - Simulator Scenario Proof And Relay Resurrection Fix

- Added `sim-ui-scenario-sync-proof` to `Makefile`.
- The target starts the real `iPhone 17` UITest sampler first, waits for
  `ui-ready.json`, then runs `dock-relay-sync-audit.mjs --mode scenario
  --scenario archive-toggle` through the actual relay routes while the rendered
  app is sampling.
- Added `readyPath` support and fractional-second timestamps to
  `CodexDockDisplayedSyncProofTests.swift`.
- Fixed the sampler to avoid `query.count` on large row queries so the proof
  does not create avoidable sampling lag.
- Fixed the UI judge so a detail-only sample cannot satisfy Dock transition
  proof.
- Fixed the scenario lag measurement so it records the first target-row
  presence/absence after mutation start, then separately compares the full
  long-lived stream against a fresh client-path Dock snapshot.
- Fixed the relay state resurrection bug: after a successful local archive
  mutation, stale active-list reconciliation cannot immediately re-add the row
  during `RELAY_STATE_ARCHIVE_MUTATION_GRACE_MS`.
- Useful failed runs preserved:
  - v1 failed before UI judging because the harness measured full stream
    catch-up and reported unarchive lag 4,151 ms.
  - v3 failed with the old UI judge: rendered convergence was 5,000 ms and
    unarchive was reported at 2,687 ms.
  - v4 failed before UI judging because fresh `dock/subscribe` still contained
    the archived row while the long-lived stream had removed it.
- Fresh relay proof after fixes:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode scenario --scenario archive-toggle --client-path-only --detail none --dock-collection-timeout-ms 120000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v4.json --summary-out /tmp/codex-client/sync-audit-real-home-scenario-archive-toggle-v4.md --summary-only --fail-on-diff
```

- Fresh relay result: `ok: true`, archive lag 37 ms, unarchive lag 31 ms, and
  fresh `dock/subscribe` agreed with the long-lived stream.
- Fresh simulator scenario proof:

```bash
rtk make sim-ui-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_DIR='/tmp/codex-client/sim-ui-scenario-archive-toggle-v5' SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=5000 MAX_UI_LAG_MS=2000
```

- Fresh simulator result: `ok: true`, 9 UI samples, 6 scored UI samples,
  2 scenario transitions, archive UI lag 1,011 ms, unarchive UI lag 67 ms,
  worst rendered convergence 1,801 ms under the 2,000 ms budget, failures 0.
- Checks after the change: `rtk node --check scripts/dock-relay-state-store.mjs
  && rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs && rtk
  node --check scripts/dock-relay-sync-audit.mjs` passed; `rtk node --test
  scripts/dock-relay.test.mjs scripts/dock-relay-sync-audit.test.mjs
  scripts/dock-relay-simulator-ui-sync-proof.test.mjs` passed with 67 tests
  and 0 failures; `rtk npm run test:relay` passed with 153 tests and
  0 failures.
- Service note: `rtk make dock-relay-restart` failed through shared
  host-service restart and briefly stopped both services; `rtk make services`
  restored them. Final `rtk make dock-relay-status` is ready.

### 2026-05-31 - Isolated CODEX_HOME Service Hook

- Added `--codex-home` support to `scripts/codex-dock-host-service.mjs`.
- `CODEX_HOME` is now included in the service environment rendered for both the
  raw Codex app-server and the Dock relay. This keeps the future isolated
  scenario runner on the same Makefile-owned service path as normal local
  services.
- Added `CODEX_HOME ?=` and `HOST_SERVICE_CODEX_HOME_ARG` to `Makefile`, so the
  intended shape is:

```bash
rtk make services CODEX_HOME=/tmp/codex-client/<scenario-home> APP_SERVER_DIR=/tmp/codex-client/<scenario-service> DOCK_RELAY_WS=ws://127.0.0.1:<relay-port>
```

- Fixed Makefile path normalization for absolute temp paths. `APP_SERVER_DIR`,
  `ENV_FILE`, and `HOST_ENV_FILE` can now be absolute without becoming
  `/Users/aelaguiz/workspace/codex-client//tmp/...`.
- Added host-service coverage for explicit `CODEX_HOME` rendering.
- Verification:
  - `rtk node --test scripts/codex-dock-host-service.test.mjs` passed: 26
    tests, 0 failures.
  - The isolated `rtk make -n services ... CODEX_HOME=/tmp/codex-client/isolated-home`
    dry-run passed and showed clean `/tmp/codex-client/...` paths plus
    `--codex-home "/tmp/codex-client/isolated-home"`.
  - Default `rtk make -n services` still renders repo-local `.codex-dock`
    service files as absolute paths for host-service invocation.
  - `rtk npm run test:relay` passed: 153 tests, 0 failures.
- Current limitation for this service slice: it only proved service wiring.
  Isolated Codex data seeding and simulator scenario proof are covered by the
  later isolated scenario pass below.

### 2026-05-31 - Isolated Simulator Scenario Proof

- Added `scripts/codex-dock-isolated-home.mjs`.
- The seeder creates a tiny temporary `CODEX_HOME` by cloning one active real
  thread, copying only that thread's rollout JSONL, rewriting the rollout path
  into the temp home, and pruning unrelated state. It does not copy the
  multi-GB real `sessions` tree.
- Added `scripts/codex-dock-isolated-home.test.mjs` and included it in
  `npm run test:relay`.
- Added `sim-ui-isolated-scenario-sync-proof` to `Makefile`.
- The new target:
  - seeds a temp Codex home under `/tmp/codex-client/...`;
  - starts isolated raw app-server and relay launchd services on
    `4520`/`4521` through the normal Makefile-owned service path;
  - runs the real `iPhone 17` displayed-UI sampler;
  - applies `thread/archive` and `thread/unarchive` through the relay routes
    the client uses;
  - compares literal simulator accessibility samples against the relay
    client-route report;
  - stops the isolated services on exit.
- First isolated simulator run failed before UI judging:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=5000 MAX_UI_LAG_MS=2000
```

- Failure: fresh `dock/subscribe` returned the unarchived card with `running`
  status while the long-lived stream had the same seq with `dormant` status.
- Fix: `RelayStateStore.cardForThread` now applies active live leases before
  publishing archive/unarchive mutation deltas, so long-lived streams and fresh
  subscribers see the same client projection.
- Fresh isolated simulator proof command:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v2 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=5000 MAX_UI_LAG_MS=2000
```

- Fresh result: `ok: true`, 24 UI samples, 22 scored UI samples, 3 relay
  samples, 2 scenario transitions, 14 displayed-row checks, 1 detail sample,
  UI lag observed 0 ms under the 2,000 ms budget, failures 0.
- Relay side for that proof: `clientPathOK: true`, `scenarioOK: true`,
  `thread/archive: 1`, `thread/unarchive: 1`, archive relay lag 15 ms,
  unarchive relay lag 17 ms, failures 0.
- Checks after the change:
  - `rtk node --test scripts/dock-relay.test.mjs` passed: 36 tests, 0
    failures.
  - `rtk npm run test:relay` passed: 156 tests, 0 failures.
  - `rtk npm run test:host-service` passed: 35 tests, 0 failures.
  - `rtk make dock-relay-status` reported the normal `:4510` service bundle
    ready after isolated service cleanup.

### 2026-05-31 - Checkpointed Isolated Simulator Proof And Relay State Isolation

- Added optional `checkpointSweep` support to
  `CodexDockDisplayedSyncProofTests.swift`. When enabled, the sampler records a
  bounded Dock sweep through actual simulator UI interactions after the
  over-time samples.
- Added `SIM_UI_SYNC_CHECKPOINT_SWEEP ?= 1` to the simulator sync Makefile
  targets so paired simulator proofs include the stable checkpoint sweep by
  default.
- Updated `scripts/dock-relay-simulator-ui-sync-proof.mjs` so checkpoint
  sweeps fail on missing identity, duplicate row, unexpected row, status
  mismatch, origin mismatch, count mismatch, and missing relay row.
- First checkpointed isolated run failed usefully:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v3-checkpoint SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=5000 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1
```

- v3 result: `ok: false`; the UI showed stale `unknown` while relay truth was
  `running`, and the judge reported `dock_ui_lag_exceeded` with 6,035 ms
  observed lag.
- v3 root cause: the isolated service used the repo-level
  `.codex-dock/relay-state.sqlite`, so the isolated simulator proof inherited
  old relay cache rows instead of using only the temp `CODEX_HOME`.
- Fix: `scripts/dock-relay.mjs` now accepts `--relay-state-db`, and
  `scripts/codex-dock-host-service.mjs` defaults relay state storage to
  `$(APP_SERVER_DIR)/relay-state.sqlite` unless explicitly overridden.
- Fresh checkpointed isolated simulator proof:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v4-checkpoint-state-db SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=5000 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1
```

- v4 result: `ok: true`, 25 UI samples, 23 scored UI samples, 3 relay samples,
  2 scenario transitions, 15 displayed row checks, 1 checkpoint sweep,
  1 checkpoint sweep row check, 1 detail sample, UI lag observed 0 ms under the
  2,000 ms budget, failures 0.
- Relay side for v4: `clientPathOK: true`, `scenarioOK: true`,
  `thread/archive: 1`, `thread/unarchive: 1`, archive relay lag 18 ms,
  unarchive relay lag 18 ms, failures 0.
- Verification after the checkpoint/state-DB changes:
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 11 tests, 0 failures.
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --check scripts/dock-relay.mjs && rtk node --check scripts/codex-dock-host-service.mjs`
    passed.
  - `rtk node --test scripts/codex-dock-host-service.test.mjs` passed:
    27 tests, 0 failures.
  - `rtk npm run test:relay` passed: 158 tests, 0 failures.
- Service cleanup check: no listeners remained on isolated ports `4520` or
  `4521` after the v4 proof exited.

### 2026-05-31 - Repeated Archive/Unarchive Transition Proof

- Added `--scenario-repetitions` to `scripts/dock-relay-sync-audit.mjs`.
- `archive-toggle` now records every archive and unarchive transition
  separately when repeated, including transition names like `archive-1`,
  `unarchive-1`, `archive-2`, and `unarchive-2`.
- Added Makefile wiring:
  - `SIM_UI_SYNC_SCENARIO ?= archive-toggle`
  - `SIM_UI_SYNC_SCENARIO_REPETITIONS ?= 1`
  - `sim-ui-scenario-sync-proof` passes both values into the relay audit.
  - `sim-ui-isolated-scenario-sync-proof` passes both values into the nested
    simulator scenario proof.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    25 tests, 0 failures.
  - `rtk make -n sim-ui-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO_REPETITIONS=2 SIM_UI_SYNC_SCENARIO_HOLD_MS=2500`
    showed `--scenario-repetitions "2"` reaching
    `scripts/dock-relay-sync-audit.mjs`.
  - `rtk npm run test:relay` passed: 160 tests, 0 failures.
- Repeated isolated simulator proof:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v5-repeated-toggle SIM_UI_SYNC_DURATION_MS=26000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=2 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1
```

- v5 result: `ok: true`, 43 UI samples, 41 scored UI samples, 5 relay samples,
  4 scenario transitions, 4 transition checks, 0 transition failures,
  29 displayed row checks, 1 checkpoint sweep, 1 checkpoint sweep row check,
  1 detail sample, UI lag observed 0 ms under the 2,000 ms budget, failures 0.
- Relay side for v5: `clientPathOK: true`, `scenarioOK: true`,
  `thread/archive: 2`, `thread/unarchive: 2`, archive/unarchive relay lags
  16 ms, 19 ms, 16 ms, and 17 ms, failures 0.

### 2026-05-31 - Multi-Thread Isolated Fixture Attempt

- Added `--thread-count` to `scripts/codex-dock-isolated-home.mjs`.
- Added `SIM_UI_ISOLATED_THREAD_COUNT ?= 1` to `Makefile` and wired it into
  `sim-ui-isolated-scenario-sync-proof`.
- The isolated fixture metadata keeps compatibility fields for the primary
  mutation thread (`threadID`, `rolloutPath`) and adds `threadIDs`,
  `threadCount`, and per-thread rollout metadata for multi-row proofs.
- The seeder now rejects `archived_sessions/...` rollout paths when selecting
  active simulator rows. This prevents stale SQLite archive state from becoming
  false active-client proof.
- Targeted checks:
  - `rtk node --check scripts/codex-dock-isolated-home.mjs` passed.
  - `rtk node --test scripts/codex-dock-isolated-home.test.mjs` passed:
    3 tests, 0 failures.
  - `rtk make -n sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_THREAD_COUNT=2 ...`
    showed `--thread-count "2"` reaching
    `scripts/codex-dock-isolated-home.mjs`.
  - `rtk npm run test:relay` passed: 161 tests, 0 failures.
- Multi-row simulator proof attempt v6:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v6-multi-row-checkpoint SIM_UI_ISOLATED_THREAD_COUNT=2 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=1 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1
```

- v6 result: failed. Relay client path passed, but the simulator judge
  reported `dock_ui_lag_exceeded` with observed rendered lag 3,415 ms against
  the 2,000 ms budget, plus `scenario_ui_transition_not_observed` for the
  archive transition. This failure is preserved as evidence that lag is a hard
  failure. Root cause evidence showed the second seeded row used an
  `archived_sessions/...` rollout path and disappeared during reconciliation.
- Multi-row simulator proof attempt v7:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v7-multi-row-stable SIM_UI_ISOLATED_THREAD_COUNT=2 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=1 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1
```

- v7 result: failed before UI judging. The relay scenario passed with
  `clientPathOK: true`, `scenarioOK: true`, archive relay lag 19 ms, and
  unarchive relay lag 20 ms. XCUITest failed while reading row index 1 in
  `visibleDockRows()` because that row disappeared during the live list update.
- Fixed the sampler crash by changing `firstVisibleDockRow()` and
  `visibleDockRows()` to enumerate a single `allElementsBoundByIndex` snapshot
  instead of repeatedly resolving `query.element(boundBy:)` while the list is
  changing.
- Multi-row simulator proof v8:

```bash
rtk make sim-ui-isolated-scenario-sync-proof SIM='iPhone 17' SIM_UI_ISOLATED_ROOT=/tmp/codex-client/sim-ui-isolated-scenario-v8-multi-row-snapshot-capture SIM_UI_ISOLATED_THREAD_COUNT=2 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 SIM_UI_SYNC_SCENARIO_REPETITIONS=1 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1
```

- v8 result: `ok: true`, `Relay client-path OK: true`, 27 UI samples,
  25 scored UI samples, 3 relay samples, 2 scenario transitions,
  2 transition checks, 0 transition failures, 47 displayed row checks,
  1 checkpoint sweep, 2 checkpoint sweep row checks, 1 detail sample,
  observed UI lag 0 ms under the 2,000 ms budget, failures 0.
- Relay side for v8: `clientPathOK: true`, `scenarioOK: true`,
  `thread/archive: 1`, `thread/unarchive: 1`, archive relay lag 13 ms,
  unarchive relay lag 14 ms, failures 0.
- Next: widen beyond archive/unarchive into the remaining required scenario
  matrix, and add deeper detail/request checks before any completion claim.

### 2026-05-31 - Resync-Gap Scenario Proof

- Added `resync-gap` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario marks the long-lived probe state as needing resync after a
  detected stream-gap condition, then exercises the actual relay
  `dock/resync` route and compares the recovered long-lived stream against a
  fresh `dock/subscribe` snapshot.
- Added parser and requirement tests for `--scenario resync-gap`.
- Fixed the scenario's lag measurement to use the `dock/resync` response
  completion timestamp, so the proof measures recovery time instead of later
  unrelated stream notifications.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    27 tests, 0 failures.
  - `rtk npm run test:relay` passed: 163 tests, 0 failures.
- Real relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario resync-gap --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/resync-gap-scenario-v2/relay-client-path.json --summary-out /tmp/codex-client/resync-gap-scenario-v2/relay-client-path.md --summary-only --fail-on-diff
```

- v2 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  `dock/resync: 1`, 1,701 stream cards matched 1,701 fresh
  `dock/subscribe` cards, stream comparison findings 0, resync recovery lag
  18 ms under the 2,000 ms budget, failures 0.
- This covers required scenario 14 for the relay-level client path. It does
  not replace the remaining scenario matrix or the later simulator displayed-UI
  third-leg work.

### 2026-05-31 - Detail Reconnect Scenario Proof

- Added `detail-reconnect` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario selects an actual active Dock row from `dock/subscribe`, opens
  detail through `thread/read`, drains `thread/turns/list`, calls
  `thread/resume`, closes that detail session, then repeats the same client
  route sequence to prove reconnect reloads history before accepting live
  events.
- Added parser, requirement, and target-selection tests for
  `--scenario detail-reconnect`.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    30 tests, 0 failures.
  - `rtk npm run test:relay` passed: 166 tests, 0 failures.
- Real relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario detail-reconnect --client-path-only --detail none --detail-observe-ms 100 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/detail-reconnect-scenario-v1/relay-client-path.json --summary-out /tmp/codex-client/detail-reconnect-scenario-v1/relay-client-path.md --summary-only --fail-on-diff
```

- v1 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  `thread/read: 2`, `thread/turns/list: 2`, `thread/resume: 2`, selected
  target `019e516b-a1d1-7c30-a5ac-50c70c3fc240`, selected target status
  `running`, both loads returned the selected thread id, both turn drains were
  complete with 3 turns and no duplicate turn ids, reconnect live boundary
  reached in 68 ms under the 2,000 ms budget, failures 0.
- This covers required scenario 15 for the relay-level client path. It does
  not replace server-request scenarios, storage-vs-Codex-session oracle gaps,
  or the later simulator displayed-UI third leg.

### 2026-05-31 - Source Refresh Failure/Recovery Scenario Proof

- Added `source-refresh` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario starts a controlled app-server fixture and a real in-process
  Dock relay, subscribes with the same `dock/subscribe`/`dock/update` routes
  the client uses, then forces upstream refresh failure and recovery. The
  controlled upstream failure is synthetic; the counted proof is the relay
  client path.
- Added parser and requirement tests for `--scenario source-refresh`.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    32 tests, 0 failures.
  - `rtk npm run test:relay` passed: 168 tests, 0 failures.
- Controlled relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario source-refresh --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/source-refresh-scenario-v1/relay-client-path.json --summary-out /tmp/codex-client/source-refresh-scenario-v1/relay-client-path.md --summary-only --fail-on-diff
```

- v1 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  stale-source transition kept cached row visible and marked freshness `stale`
  with lag 1 ms, recovery transition replaced the cached row with recovered
  row and marked freshness `fresh` with lag 0 ms, final long-lived stream
  matched a fresh `dock/subscribe` snapshot, failures 0.
- This covers source-refresh stale and recovery behavior for the relay-level
  client path. It does not replace the remaining required scenario matrix or
  the later simulator displayed-UI third leg.

### 2026-05-31 - Server Request Scenario Proof

- Added `server-request` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario starts a controlled app-server fixture and a real in-process
  Dock relay, opens a Dock row through the real detail client route sequence
  `thread/read`, `thread/turns/list`, and `thread/resume`, then proves a live
  server request reaches the detail client, the client response reaches
  upstream, and `serverRequest/resolved` returns on the same detail path.
- Added parser and requirement tests for `--scenario server-request`.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    34 tests, 0 failures.
  - `rtk npm run test:relay` passed: 170 tests, 0 failures.
- Controlled relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario server-request --client-path-only --detail none --detail-observe-ms 100 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/server-request-scenario-v1/relay-client-path.json --summary-out /tmp/codex-client/server-request-scenario-v1/relay-client-path.md --summary-only --fail-on-diff
```

- v1 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  `thread/read: 1`, `thread/turns/list: 1`, `thread/resume: 1`, request
  method `item/commandExecution/requestApproval` arrived for the selected
  thread, client response `{ decision: "accept" }` reached upstream,
  `serverRequest/resolved` returned for the same request id, request lag 1 ms,
  resolution lag 12 ms, failures 0.
- This covers required scenarios 10 and 11 for the relay-level detail path.
  It does not prove the rendered simulator request card yet; that remains part
  of the later simulator displayed-UI third leg.

### 2026-05-31 - Thread Activity Scenario Proof

- Added `thread-activity` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario starts a controlled app-server fixture and a real in-process
  Dock relay, opens a long-lived `dock/subscribe` stream, then changes
  app-server `thread/list` rows to model a new session and a new turn on an
  existing session.
- Tightened `compareDockStates` so fresh-vs-stream comparisons now fail when
  client render order differs, not only when the card set or card payloads
  differ. Sanitized reports now include `renderOrderCardIDs`.
- Added parser, requirement, and render-order comparison tests for
  `--scenario thread-activity`.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    37 tests, 0 failures.
  - `rtk npm run test:relay` passed: 173 tests, 0 failures.
- Controlled relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario thread-activity --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/thread-activity-scenario-v2/relay-client-path.json --summary-out /tmp/codex-client/thread-activity-scenario-v2/relay-client-path.md --summary-only --fail-on-diff
```

- v2 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  new thread appeared first in render order with lag 1 ms, existing thread
  received updated activity and moved to first in render order with lag 1 ms,
  both transitions had stream-vs-fresh comparison findings 0, failures 0.
- This covers required scenarios 3 and 4 for the relay-level Dock path. It does
  not prove real Codex CLI thread creation or rendered simulator order yet;
  those remain future breadth/completion proof.

### 2026-05-31 - Live Lease Expiry Scenario Proof

- Added `live-lease-expiry` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario starts a controlled live app-server fixture and a real
  in-process Dock relay, opens a long-lived `dock/subscribe` stream, observes a
  row as `running`, removes that row from the fixture's live loaded list, then
  proves the lease expiry reaches the long-lived Dock stream and a fresh
  `dock/subscribe` snapshot through actual client routes.
- Fixed the relay expiry path:
  - `RelayStateStore` now records whether an expired lease has already been
    published so a long-lived stream gets exactly one expiry update even when a
    fresh snapshot already projects the row as expired.
  - `RelayStateEngine` now schedules a near-real-time reconciliation at the next
    unpublished live lease expiry instead of waiting for the 30-second periodic
    reconciliation interval.
  - The partial-window catch-up test now waits for the real complete catch-up
    update before closing the in-memory database.
- Added parser and requirement tests for `--scenario live-lease-expiry`.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-state-store.mjs && rtk node --check scripts/dock-relay-state-engine.mjs && rtk node --test --test-name-pattern 'live lease expiry|client-projected status' scripts/dock-relay.test.mjs` passed: 2 tests, 0 failures.
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    39 tests, 0 failures.
  - `rtk node --test --test-name-pattern 'relay state streams remaining Dock windows after a partial snapshot|live lease expiry|client-projected status' scripts/dock-relay.test.mjs` passed:
    3 tests, 0 failures.
  - `rtk npm run test:relay` passed: 176 tests, 0 failures.
- Controlled relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario live-lease-expiry --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/live-lease-expiry-scenario-v1/relay-client-path.json --summary-out /tmp/codex-client/live-lease-expiry-scenario-v1/relay-client-path.md --summary-only --fail-on-diff
```

- v1 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  `dock/subscribe: 3`, `dock/update: 15`, running row expired to `unknown` on
  the long-lived stream 4 ms after the lease expiry timestamp, fresh
  `dock/subscribe` matched the stream, failures 0.
- This covers required scenario 5 for the relay-level Dock path. It does not
  replace goal-change, the wider matrix, or the later simulator displayed-UI
  third leg.

### 2026-05-31 - Multi-Host Isolation Scenario Proof

- Added `multi-host-isolation` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario starts two controlled app-server fixtures and two real
  in-process Dock relays. Both upstreams expose the same `shared-thread-id`,
  then only host A receives a new row. Success requires host-scoped card ids,
  correct `logicalHostID`, no cross-host leak, and stream-vs-fresh agreement
  through real `dock/subscribe` and `dock/update` routes.
- Targeted proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario multi-host-isolation --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/multi-host-isolation-scenario-v1/relay-client-path.json --summary-out /tmp/codex-client/multi-host-isolation-scenario-v1/relay-client-path.md --summary-only --fail-on-diff
```

- v1 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  `dock/subscribe: 5`, `dock/update: 16`, host A update appeared in 1 ms under
  the 2,000 ms budget, host A and host B both kept `shared-thread-id` scoped by
  host, host B did not receive `host-a-new`, failures 0.
- This covers required scenario 16 for the relay-level Dock path. It does not
  replace goal-change, full-matrix proof, or simulator displayed-UI proof.

### 2026-05-31 - Spawn Edge Scenario Proof

- Added `spawn-edge` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario starts a controlled app-server fixture and a real in-process
  Dock relay. It starts with only a parent row, then exposes a spawned child
  whose source metadata contains `thread_spawn.parent_thread_id`. The fixture
  honors app-server `sourceKinds` filtering so the child is produced through
  the all-source path, not by inventing a client-only row.
- The counted proof uses actual client routes: the child must appear through
  the long-lived `dock/subscribe` stream and `dock/update`, match a fresh
  `dock/subscribe`, and expose the same parent id through the client-used
  `thread/read` detail route.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    43 tests, 0 failures.
  - `rtk npm run test:relay` passed: 180 tests, 0 failures.
- Controlled relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario spawn-edge --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/spawn-edge-scenario-v1/relay-client-path.json --summary-out /tmp/codex-client/spawn-edge-scenario-v1/relay-client-path.md --summary-only --fail-on-diff
```

- v1 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  `dock/subscribe: 3`, `dock/update: 15`, `thread/read: 1`, spawned child
  appeared as `lane: agent` and `sourceKind: automation` in 1 ms under the
  2,000 ms budget, fresh `dock/subscribe` matched the long-lived stream, and
  `thread/read` exposed `forkedFromId` and `sourceParentThreadID` as
  `spawn-edge-parent`, failures 0.
- This covers required scenario 9 for the relay-level Dock/detail protocol
  path. It does not prove the later rendered simulator display or the remaining
  full-matrix completion gate.

### 2026-05-31 - Goal Change Scenario Proof

- Added `goal-change` to `scripts/dock-relay-sync-audit.mjs`.
- The scenario starts a controlled app-server fixture and a real in-process
  Dock relay. It proves the relay returns the latest app-server-visible goal
  state through `thread/goal/get` after a controlled status change.
- This is intentionally not counted as client-path proof because
  `DockThreadCardDTO` and `ThreadDetailStore` do not consume goal fields today.
  The report records `thread/goal/get` under `nonClientPathRoutes`.
- First proof attempt:
  - `/tmp/codex-client/goal-change-scenario-v1/relay-protocol.json`
  - `thread/goal/get` returned the updated goal state, but the Dock fixture row
    was missing because the scenario did not force initial relay reconciliation
    before checking the Dock row.
  - This failure was preserved as harness fixture evidence.
- Fix: the scenario now forces `relayStateEngine.reconcileDock` before checking
  the fixture Dock row.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-sync-audit.mjs` passed.
  - `rtk node --test scripts/dock-relay-sync-audit.test.mjs` passed:
    45 tests, 0 failures.
  - `rtk npm run test:relay` passed: 182 tests, 0 failures.
- Controlled relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario goal-change --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/goal-change-scenario-v2/relay-protocol.json --summary-out /tmp/codex-client/goal-change-scenario-v2/relay-protocol.md --summary-only --fail-on-diff
```

- v2 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`,
  `thread/goal/get` was recorded under `nonClientPathRoutes` with count 2,
  status changed from `in_progress` to `complete`, observed relay-protocol lag
  was 1 ms under the 2,000 ms budget, failures 0.
- This covers required scenario 8 as relay-protocol proof for app-server-visible
  goal state. It does not change the current client contract or prove a
  rendered simulator goal field.

### 2026-05-31 - Relay Scenario Matrix Proof

- Ran the combined relay-level required scenario matrix with
  `--scenario all --scenario-repetitions 2`.
- This run includes all 10 scenario groups: archive-toggle, detail-reconnect,
  goal-change, resync-gap, live-lease-expiry, multi-host-isolation,
  server-request, source-refresh, spawn-edge, and thread-activity.
- Controlled relay proof command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --mode scenario --scenario all --scenario-repetitions 2 --client-path-only --detail none --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --json-out /tmp/codex-client/scenario-all-client-path-v1/relay-client-path.json --summary-out /tmp/codex-client/scenario-all-client-path-v1/relay-client-path.md --summary-only --fail-on-diff
```

- v1 result: `ok: true`, `scenarioOK: true`, `clientPathOK: true`, 10
  scenario groups, 0 scenario failures, 0 unimplemented required scenarios.
- Routes exercised as actual client path: `initialize`, `initialized`,
  `dock/subscribe`, `dock/update`, `dock/resync`, `thread/archive`,
  `thread/unarchive`, `thread/read`, `thread/turns/list`, and `thread/resume`.
- Route counts: `dock/subscribe: 26`, `dock/update: 188`, `dock/resync: 1`,
  `thread/archive: 2`, `thread/unarchive: 2`, `thread/read: 4`,
  `thread/turns/list: 3`, `thread/resume: 3`.
- Worst relay scenario lag was 194 ms under the 2,000 ms budget.
- This closes the relay-level combined scenario matrix. It does not replace the
  required simulator-displayed full-matrix/breadth proof or final fresh
  Composer 2.5 Fast completion consult.

### 2026-05-31 - Controlled Thread Activity Simulator Proof

- Added `scripts/dock-relay-controlled-simulator-fixture.mjs` and
  `rtk make sim-ui-controlled-scenario-sync-proof`.
- The new target starts a temporary real relay first, writes that relay host to
  the simulator UI config, launches the actual `iPhone 17` app against that
  host, waits for the UI sampler to become ready, then mutates the same fixture
  source. This keeps the simulator display, relay report, and scenario
  actuator on one shared path.
- The first supported controlled simulator scenario is `thread-activity`.
  Unsupported simulator fixture scenarios are rejected until they are wired to
  the same shared-relay pattern.
- Fixed the simulator detail sampler so loading detail screens record missing
  detail sub-elements as `not-visible` instead of crashing XCUITest.
- Fixed UI sample timing by recording `finishedAt`; the judge now scores
  transition warmup mismatches against the relevant transition lag budget.
- Targeted checks:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 3 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 12 tests, 0 failures.
  - `rtk npm run test:relay` passed: 186 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=thread-activity SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-thread-activity-v3 SIM_UI_SYNC_DURATION_MS=18000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v3 result: `OK: true`, `Relay client-path OK: true`, 23 UI samples, 22
  scored UI samples, 3 relay samples, 2 scenario transitions, 0 transition
  failures, 64 displayed row checks, 1 checkpoint sweep with 3 row checks,
  1 detail sample, global UI lag observed 0 ms, failures 0.
- Transition proof:
  - Relay new-thread lag: 5 ms; rendered UI transition lag: 627 ms.
  - Relay new-turn-order lag: 3 ms; rendered UI transition lag: 628 ms.
  - Both rendered transition lags were under the 2,000 ms client-visible lag
    budget.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-thread-activity-v3/simulator-ui-sync.md`
- This moves Phase 6 beyond archive/unarchive-only simulator proof. It still
  does not close full Phase 6 because broader detail/request-card coverage, lazy-list breadth,
  runbook documentation, physical phone proof, and final Composer 2.5 Fast
  completion consult remain open.

### 2026-05-31 - Controlled Server Request Simulator Proof

- Intent: extend the third-leg simulator proof from Dock-row activity into
  actual detail UI request-card behavior, using only paths the installed client
  exercises.
- Changed:
  - Added `server-request` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - Extended `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` so the
    sampler can open the exact real Dock row, wait for the real detail UI, tap
    the real request-card action, and keep sampling the rendered state over
    time.
  - Extended `scripts/dock-relay-simulator-ui-sync-proof.mjs` so the judge
    scores request-card detail transitions, not just Dock list rows.
  - Updated `Makefile` so controlled fixture UI config can pass
    scenario-specific detail-open and request-action instructions into the app
    test.
  - Fixed `CodexDock/Models/ThreadEvent.swift` so server-request events are
    visible in the default detail view. The failing simulator attempt proved the
    old behavior was not good enough: the request reached client state, but the
    literal UI hid it until filter interaction, which violated the user-visible
    lag requirement.
- Read:
  - `CodexDock/Views/ThreadDetailView.swift`
  - `CodexDock/Views/RequestCardView.swift`
  - `CodexDock/Models/ThreadEvent.swift`
  - `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`
  - `scripts/dock-relay-controlled-simulator-fixture.mjs`
  - `scripts/dock-relay-simulator-ui-sync-proof.mjs`
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 4 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 14 tests, 0 failures.
  - `rtk swift test --filter ThreadEventNormalizerTests` passed: 11 tests,
    0 failures.
  - `rtk swift test --filter ThreadDetailStoreTests/testServerRequestEventAppearsNewestFirstWithoutBreakingRequestCardResponse`
    passed: 1 test, 0 failures.
  - `rtk npm run test:relay` passed: 189 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=server-request SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-server-request-v4 SIM_UI_SYNC_DURATION_MS=12000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v4 result: `OK: true`, `Relay client-path OK: true`, 16 UI samples,
  3 scored UI samples, 1 relay sample, 2 detail transitions, 0 detail
  transition failures, 3 displayed row checks, 1 checkpoint sweep with 1 row
  check, 13 detail samples, global UI lag observed 0 ms, failures 0.
- Detail transition proof:
  - `server-request-visible`: rendered detail UI lag 1,114 ms under the
    2,000 ms budget.
  - `server-request-resolution`: rendered detail UI lag 1,056 ms under the
    2,000 ms budget.
  - Relay request lag was 0 ms; relay resolution lag was 12 ms.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-server-request-v4/fixture-ready.json`
  - `/tmp/codex-client/sim-ui-controlled-server-request-v4/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-server-request-v4/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-server-request-v4/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-server-request-v4/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-server-request-v4/simulator-ui-sync.md`
- Review: this proves one high-risk detail/request path end to end through the
  actual simulator display. It does not close full Phase 6; lazy-list/full-detail breadth, runbook documentation, physical phone proof,
  and final Composer 2.5 Fast completion consult remain open.

### 2026-05-31 - Controlled Source Refresh Simulator Proof

- Intent: extend the third-leg simulator proof to stale-source visibility, not
  just row/order changes and request cards. This proves that cached rows are
  displayed as explicitly partial/stale when upstream source refresh fails, and
  that recovered fresh rows replace stale display state within the lag budget.
- Changed:
  - Added controlled `source-refresh` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - Extended `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift` so UI
    samples capture visible Dock host summary/status rows in addition to Dock
    rows and detail.
  - Extended `scripts/dock-relay-simulator-ui-sync-proof.mjs` so non-fresh
    relay freshness must be literally visible in the simulator host status UI,
    and fresh recovery must not keep stale host status visible.
  - Added a single-host alias allowance for the simulator path, where the
    visible host status row uses the configured host `127.0.0.1:<port>` while
    Dock rows use the relay logical host id.
- First simulator attempt:
  - `/tmp/codex-client/sim-ui-controlled-source-refresh-v1` failed as useful
    evidence. The relay path passed, and the UI did show partial/stale text,
    but the judge treated the configured-host summary id as missing against the
    logical relay host id. This preserved the hard visible-lag gate instead of
    silently passing a weak check.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 5 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 18 tests, 0 failures.
  - `rtk npm run test:relay` passed: 194 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=source-refresh SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-source-refresh-v2 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v2 result: `OK: true`, `Relay client-path OK: true`, 22 UI samples,
  21 scored UI samples, 3 relay samples, 2 scenario transitions, 0 transition
  failures, 21 displayed row checks, 1 checkpoint sweep with 1 row check,
  1 detail sample, global UI lag observed 688 ms under the 2,000 ms budget,
  failures 0.
- Transition proof:
  - `source-refresh-fails`: rendered stale/partial host state lag 110 ms under
    the 2,000 ms budget.
  - `source-refresh-recovers`: rendered fresh recovered row lag 1,009 ms under
    the 2,000 ms budget.
  - Relay route counts were `initialize:3`, `initialized:3`,
    `dock/subscribe:3`, and `dock/update:3`.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-source-refresh-v2/fixture-ready.json`
  - `/tmp/codex-client/sim-ui-controlled-source-refresh-v2/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-source-refresh-v2/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-source-refresh-v2/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-source-refresh-v2/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-source-refresh-v2/simulator-ui-sync.md`
- Review: this closes one visible stale-state slice of Phase 6. It does not
  close full Phase 6; lazy-list/full-detail breadth, runbook documentation, physical phone proof,
  and final Composer 2.5 Fast completion consult remain open.

### 2026-05-31 - Controlled Live Lease Expiry Simulator Proof

- Intent: extend the third-leg simulator proof to live-status expiry. This
  proves the real client display does not keep showing a thread as `running`
  after the relay's real live lease has expired.
- Changed:
  - Added controlled `live-lease-expiry` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - The fixture starts with a long startup live lease so the simulator has time
    to attach, then refreshes the same real lease with a controlled max age
    after the UI sampler is ready.
  - The fixture then removes the row from the live loaded list and lets the
    relay's actual lease-expiry timer publish the `running` to `unknown`
    transition through `dock/update`.
  - Added parser coverage for `--scenario live-lease-expiry`.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 6 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 18 tests, 0 failures.
  - `rtk npm run test:relay` passed: 195 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=live-lease-expiry SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v1 result: `OK: true`, `Relay client-path OK: true`, 23 UI samples,
  22 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition
  failures, 22 displayed row checks, 1 checkpoint sweep with 1 row check,
  1 detail sample, global UI lag observed 0 ms, failures 0.
- Transition proof:
  - `live-lease-expiry`: relay published the row as `unknown` 4 ms after the
    live lease expiry timestamp under the 2,000 ms budget.
  - The actual simulator Dock UI matched the `unknown` row 628 ms after the
    relay transition under the 2,000 ms budget.
  - Relay route counts were `initialize:3`, `initialized:3`,
    `dock/subscribe:3`, and `dock/update:3`.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/fixture-ready.json`
  - `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1/simulator-ui-sync.md`
- Review: this closes one visible live-status-expiry slice of Phase 6. It does
  not close full Phase 6; lazy-list/full-detail breadth, runbook documentation, physical phone proof,
  and final Composer 2.5 Fast completion consult remain open.

### 2026-05-31 - Controlled Multi-Host Simulator Proof

- Intent: extend the third-leg simulator proof to two relay hosts. This proves
  the actual client display can keep rows host-scoped when two relay-backed
  Codex sources expose the same thread id, and that a mutation on host A does
  not leak into host B.
- Changed:
  - Added controlled `multi-host-isolation` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - The fixture now starts two temporary real relays, writes a comma-separated
    host list for `CODEX_DOCK_HOSTS`, and builds a combined relay-truth sample
    so the existing UI judge scores all displayed rows across both hosts.
  - Added parser coverage for `--scenario multi-host-isolation`.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 7 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 18 tests, 0 failures.
  - `rtk npm run test:relay` passed: 196 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=multi-host-isolation SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1 SIM_UI_SYNC_DURATION_MS=16000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v1 result: `OK: true`, `Relay client-path OK: true`, 16 UI samples,
  15 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition
  failures, 73 displayed row checks, 1 checkpoint sweep with 5 row checks,
  1 detail sample, global UI lag observed 1,163 ms under the 2,000 ms budget,
  failures 0.
- Transition proof:
  - `multi-host-isolation`: host A added a new row, host B stayed unchanged,
    and the same thread id on both hosts kept separate card ids.
  - Relay host-A update lag was 2 ms under the 2,000 ms budget.
  - The actual simulator Dock UI matched the five-row host-scoped truth
    1,511 ms after the relay transition under the 2,000 ms budget.
  - Relay route counts were `initialize:6`, `initialized:6`,
    `dock/subscribe:6`, and `dock/update:3`.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/fixture-ready.json`
  - `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1/simulator-ui-sync.md`
- Review: this closes one visible multi-host isolation slice of Phase 6. It
  does not close full Phase 6; lazy-list/full-detail breadth, runbook documentation, physical phone proof,
  and final Composer 2.5 Fast completion consult remain open.

### 2026-05-31 - Controlled Spawn-Edge Simulator Proof

- Intent: extend the third-leg simulator proof to the subagent spawn edge. This
  proves the actual client display can render a new spawned child as an
  automation-origin Dock row while staying in sync with the relay truth over
  time.
- Changed:
  - Added controlled `spawn-edge` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - The fixture now starts with only the parent row, waits until the real
    `iPhone 17` app is sampling the same temporary relay, then adds a spawned
    child row using the same app-server source metadata shape as the relay
    scenario.
  - The fixture uses `threadMatchesSourceKinds` so default human and explicit
    automation source scopes behave like the real app-server contract instead
    of returning rows from a fake all-rows shortcut.
  - Added parser coverage for `--scenario spawn-edge`.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 8 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 18 tests, 0 failures.
  - `rtk npm run test:relay` passed: 197 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=spawn-edge SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-spawn-edge-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v1 result: `OK: true`, `Relay client-path OK: true`, 20 UI samples,
  19 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition
  failures, 35 displayed row checks, 1 checkpoint sweep with 2 row checks,
  1 detail sample, global UI lag observed 798 ms under the 2,000 ms budget,
  failures 0.
- Transition proof:
  - `spawn-edge`: the spawned child became the first Dock row with
    `lane=agent` and `sourceKind=automation`, while the parent remained visible
    below it.
  - Relay spawn lag was 2 ms under the 2,000 ms budget.
  - The actual simulator Dock UI matched the two-row parent/child truth
    995 ms after the relay transition under the 2,000 ms budget.
  - Relay route counts were `initialize:3`, `initialized:3`,
    `dock/subscribe:3`, and `dock/update:2`.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/fixture-ready.json`
  - `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-spawn-edge-v1/simulator-ui-sync.md`
- Review: this closes one visible spawn-edge Dock-row slice of Phase 6. It
  does not close full Phase 6; lazy-list/full-detail breadth, runbook documentation, physical phone proof,
  and final Composer 2.5 Fast completion consult remain open.

### 2026-05-31 - Controlled Resync-Gap Simulator Proof

- Intent: extend the third-leg simulator proof to stream sequence-gap recovery.
  This proves the actual client display can recover after receiving a bad
  Dock stream update by using the real `dock/resync` route, then rendering the
  recovered row set within the lag budget.
- Changed:
  - Added controlled `resync-gap` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - The fixture updates relay state while temporarily suppressing normal
    subscription publication, then publishes a malformed `dock/update` with
    `baseSeq=12` and `seq=2` so clients must reject the delta and resync.
  - The recovered snapshot contains a new top row plus the stable row. The
    actual simulator UI can only display that recovered two-row truth after
    it processes the sequence gap and refreshes through the stream path.
  - Added parser coverage for `--scenario resync-gap`.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 9 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 18 tests, 0 failures.
  - `rtk npm run test:relay` passed: 198 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=resync-gap SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-resync-gap-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v1 result: `OK: true`, `Relay client-path OK: true`, 21 UI samples,
  20 scored UI samples, 2 relay samples, 1 scenario transition, 0 transition
  failures, 37 displayed row checks, 1 checkpoint sweep with 2 row checks,
  1 detail sample, global UI lag observed 772 ms under the 2,000 ms budget,
  failures 0.
- Transition proof:
  - `resync-gap`: the long-lived stream received the malformed update,
    rejected it as a sequence gap, called `dock/resync`, and recovered the new
    two-row truth.
  - Relay resync lag was 2 ms under the 2,000 ms budget.
  - The actual simulator Dock UI matched the recovered two-row truth 936 ms
    after the relay resync transition under the 2,000 ms budget.
  - Relay route counts were `initialize:3`, `initialized:3`,
    `dock/subscribe:3`, `dock/update:2`, and `dock/resync:1`.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/fixture-ready.json`
  - `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-resync-gap-v1/simulator-ui-sync.md`
- Review: this closes one visible sequence-gap recovery slice of Phase 6. It
  does not close full Phase 6; lazy-list/full-detail breadth, runbook documentation, physical phone proof,
  and final Composer 2.5 Fast completion consult remain open.

### 2026-05-31 - Controlled Rapid-Mutations Simulator Proof

- Intent: extend the third-leg simulator proof to repeated visible mutations
  on the same Dock row. This is the direct guard against a relay or client path
  that only reaches the final state while skipping intermediate user-visible
  state.
- Changed:
  - Added controlled `rapid-mutations` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - The fixture starts the real `iPhone 17` UI sampler against the same
    temporary relay, then mutates one visible Dock row through six ordered
    statuses: `needsApproval`, `needsInput`, `error`, `running`,
    `needsApproval`, and `needsInput`.
  - The first attempt at
    `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v1` failed because
    the fixture used `idle`/`dormant` states that the actual Dock UI hides under
    the active filter. The passing fixture uses only visible statuses, so the
    proof is about what the user can literally see rather than hidden relay
    state.
  - Added parser coverage for `--scenario rapid-mutations`.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 10 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
    passed: 18 tests, 0 failures.
  - `rtk npm run test:relay` passed: 199 tests, 0 failures.
- Controlled simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=rapid-mutations SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2 SIM_UI_SYNC_DURATION_MS=28000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=2500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v2 result: `OK: true`, `Relay client-path OK: true`, 38 UI samples,
  37 scored UI samples, 7 relay samples, 6 scenario transitions,
  0 transition failures, 74 displayed row checks, 1 checkpoint sweep with
  2 row checks, 1 detail sample, global UI lag observed 787 ms under the
  2,000 ms budget, failures 0.
- Transition proof:
  - Relay mutation lags were 5 ms, 2 ms, 1 ms, 2 ms, 3 ms, and 3 ms under the
    2,000 ms budget.
  - The actual simulator Dock UI observed all six transitions before the next
    transition, with rendered lags 554 ms, 1,182 ms, 1,018 ms, 864 ms,
    724 ms, and 559 ms under the 2,000 ms budget.
  - Relay route counts were `initialize:8`, `initialized:8`,
    `dock/subscribe:8`, and `dock/update:7`.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/fixture-ready.json`
  - `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/relay-client-path.md`
  - `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/ui-samples.jsonl`
  - `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-rapid-mutations-v2/simulator-ui-sync.md`
- Review: this closes one visible repeated-mutation slice of Phase 6. It does
  not close full Phase 6; lazy-list/full-detail breadth, runbook documentation, physical phone proof,
  and final Composer 2.5 Fast completion consult remain open.

### 2026-05-31 - Controlled Simulator Matrix Verifier

- Intent: turn the individual controlled simulator displayed-UI proofs into a
  reusable matrix gate. A pile of passing scenario folders is not enough; the
  gate must fail when a required scenario is missing, failed, lagged, or did not
  exercise the expected client routes.
- Changed:
  - Added `scripts/dock-relay-controlled-simulator-matrix.mjs`.
  - Added `scripts/dock-relay-controlled-simulator-matrix.test.mjs`.
  - Added the matrix test to `package.json` `test:relay`.
  - Added `rtk make sim-ui-controlled-matrix-verify` with
    `SIM_UI_MATRIX_REPORT_DIRS`, `SIM_UI_MATRIX_JSON`,
    `SIM_UI_MATRIX_MD`, and `SIM_UI_MATRIX_MIN_PASSES`.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-matrix.mjs`
    passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-matrix.test.mjs`
    passed: 6 tests, 0 failures.
  - `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs scripts/dock-relay-controlled-simulator-fixture.test.mjs`
    passed: 28 tests, 0 failures.
  - `rtk make -n sim-ui-controlled-matrix-verify ...` passed for command-shape
    proof.
  - `rtk npm run test:relay` passed: 205 tests, 0 failures.
- Matrix verification command:

```bash
rtk make sim-ui-controlled-matrix-verify SIM_UI_MATRIX_REPORT_DIRS='/tmp/codex-client/sim-ui-controlled-thread-activity-v3 /tmp/codex-client/sim-ui-controlled-server-request-v4 /tmp/codex-client/sim-ui-controlled-source-refresh-v2 /tmp/codex-client/sim-ui-controlled-live-lease-expiry-v1 /tmp/codex-client/sim-ui-controlled-multi-host-isolation-v1 /tmp/codex-client/sim-ui-controlled-spawn-edge-v1 /tmp/codex-client/sim-ui-controlled-resync-gap-v1 /tmp/codex-client/sim-ui-controlled-rapid-mutations-v2' SIM_UI_MATRIX_JSON=/tmp/codex-client/sim-ui-controlled-matrix-v1.json SIM_UI_MATRIX_MD=/tmp/codex-client/sim-ui-controlled-matrix-v1.md SIM_UI_MATRIX_MIN_PASSES=1 MAX_UI_LAG_MS=2000
```

- v1 result: `OK: true`, 8 reports, 8 required scenarios, 8 passing
  scenarios, 0 missing scenarios, 0 failed scenarios, max observed UI lag
  1,511 ms under the 2,000 ms budget, findings 0.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-matrix-v1.json`
  - `/tmp/codex-client/sim-ui-controlled-matrix-v1.md`
- Review: this closes the first controlled simulator matrix gate. It does not
  close the full goal because completion still requires the same matrix to pass
  twice, plus remaining lazy-list/full-detail breadth, physical phone evidence,
  and the final Composer 2.5 Fast completion consult.

### 2026-05-31 - Controlled Simulator Matrix Second Pass And Double Loop

- Intent: make the third-leg simulator matrix reusable and prove it can pass
  over time, not just once. The double-loop gate must not count the same report
  directory twice.
- Changed:
  - Added `rtk make sim-ui-controlled-matrix-proof`.
  - Added `SIM_UI_CONTROLLED_MATRIX_ROOT`,
    `SIM_UI_CONTROLLED_MATRIX_SCENARIOS`,
    `SIM_UI_CONTROLLED_MATRIX_PASSES`, and
    `SIM_UI_CONTROLLED_MATRIX_SAMPLE_MS`.
  - Added duplicate report directory rejection to
    `scripts/dock-relay-controlled-simulator-matrix.mjs`.
  - Added matrix test coverage for duplicate report directories.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-matrix.mjs`
    passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-matrix.test.mjs`
    passed: 7 tests, 0 failures.
  - `rtk make -n sim-ui-controlled-matrix-proof ...` passed for command-shape
    proof.
  - `rtk npm run test:relay` passed: 206 tests, 0 failures.
- Second matrix pass command:

```bash
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_ROOT=/tmp/codex-client/sim-ui-controlled-matrix-run-v2 SIM_UI_CONTROLLED_MATRIX_PASSES=1 MAX_UI_LAG_MS=2000
```

- v2 result: `OK: true`, 8 reports, 8 required scenarios, 8 passing
  scenarios, 0 missing scenarios, 0 failed scenarios, max observed UI lag
  1,492 ms under the 2,000 ms budget, findings 0.
- v2 per-scenario max rendered UI lag:
  - `thread-activity`: 672 ms.
  - `server-request`: 1,123 ms.
  - `source-refresh`: 336 ms.
  - `live-lease-expiry`: 674 ms.
  - `multi-host-isolation`: 1,492 ms.
  - `spawn-edge`: 987 ms.
  - `resync-gap`: 907 ms.
  - `rapid-mutations`: 1,164 ms.
- Double-loop verification:
  - Combined the 8 v1 scenario report directories with the 8 v2 scenario
    report directories.
  - Ran `SIM_UI_MATRIX_MIN_PASSES=2`.
  - Result: `OK: true`, 16 reports, 8 required scenarios, 2/2 passes per
    scenario, 0 missing scenarios, 0 failed scenarios, max observed UI lag
    1,511 ms under the 2,000 ms budget, findings 0.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/controlled-simulator-matrix.json`
  - `/tmp/codex-client/sim-ui-controlled-matrix-run-v2/controlled-simulator-matrix.md`
  - `/tmp/codex-client/sim-ui-controlled-matrix-double-loop-v1-v2.json`
  - `/tmp/codex-client/sim-ui-controlled-matrix-double-loop-v1-v2.md`
- Review: this closes the second controlled simulator matrix pass and the
  double-loop gate for the current scenario set. It does not close the full
  goal because remaining lazy-list/full-detail breadth, physical phone
  evidence, and the final Composer 2.5 Fast completion consult are still open.

### 2026-05-31 - Large-List Checkpoint Simulator Proof

- Intent: close the Dock-list breadth gap that remained after the first
  controlled matrix. Earlier checkpoint sweeps proved one, two, three, and five
  rows; this slice proves the real simulator can scroll and compare rows beyond
  the first visible viewport.
- Changed:
  - Added controlled `large-list-checkpoint` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - Added `large-list-checkpoint` to the controlled simulator matrix default
    scenario set.
  - Added `minCheckpointSweepRowChecks` to
    `scripts/dock-relay-controlled-simulator-matrix.mjs`.
  - Added Makefile matrix-run support for `large-list-checkpoint`.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --check scripts/dock-relay-controlled-simulator-matrix.mjs`
    passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs scripts/dock-relay-controlled-simulator-matrix.test.mjs`
    passed: 19 tests, 0 failures.
  - `rtk npm run test:relay` passed: 208 tests, 0 failures.
- First simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=large-list-checkpoint SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v1 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v1 result: `OK: true`, 9 UI samples, 8 scored UI samples, 40 displayed row
  checks, 1 checkpoint sweep, 18 checkpoint sweep row checks, observed UI lag
  0 ms, failures 0.
- Second simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=large-list-checkpoint SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v2 SIM_UI_SYNC_DURATION_MS=14000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v2 result: `OK: true`, 8 UI samples, 8 scored UI samples, 40 displayed row
  checks, 1 checkpoint sweep, 18 checkpoint sweep row checks, observed UI lag
  0 ms, failures 0.
- Expanded matrix verification:
  - Combined the prior 16 scenario report directories with large-list v1/v2.
  - Ran `SIM_UI_MATRIX_MIN_PASSES=2`.
  - Result: `OK: true`, 18 reports, 9 required scenarios, 9 passing
    scenarios, 2/2 passes per scenario, 0 missing scenarios, 0 failed
    scenarios, max observed UI lag 1,511 ms under the 2,000 ms budget,
    findings 0.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v1/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v1/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v2/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-large-list-checkpoint-v2/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-matrix-nine-scenario-double-loop-v1.json`
  - `/tmp/codex-client/sim-ui-controlled-matrix-nine-scenario-double-loop-v1.md`
- Review: this closes the current Dock-list lazy-scroll checkpoint breadth gap.
  At that point it did not close the full goal because full-detail/request
  breadth, physical phone evidence, and the final Composer 2.5 Fast completion
  consult were still open.

### 2026-05-31 - Detail-History Request Simulator Proof

- Intent: close the current controlled full-detail/request third-leg gap. This
  is the literal `iPhone 17` simulator leg: Codex truth reaches the relay, the
  client opens the thread detail screen through its normal routes, the request
  card is displayed and acted on through the UI, and the opened detail screen is
  swept for missing rows.
- Changed:
  - Added controlled `detail-history-request` support to
    `scripts/dock-relay-controlled-simulator-fixture.mjs`.
  - Added detail sweep capture to
    `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`.
  - Added detail sweep and expected detail-row checks to
    `scripts/dock-relay-simulator-ui-sync-proof.mjs`.
  - Added `detail-history-request` and detail sweep requirements to
    `scripts/dock-relay-controlled-simulator-matrix.mjs` and the Makefile
    matrix scenario list.
- Proof:
  - `rtk node --check scripts/dock-relay-controlled-simulator-fixture.mjs`
    passed.
  - `rtk node --check scripts/dock-relay-simulator-ui-sync-proof.mjs` passed.
  - `rtk node --check scripts/dock-relay-controlled-simulator-matrix.mjs`
    passed.
  - `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs scripts/dock-relay-simulator-ui-sync-proof.test.mjs scripts/dock-relay-controlled-simulator-matrix.test.mjs`
    passed: 40 tests, 0 failures.
  - `rtk npm run test:relay` passed: 211 tests, 0 failures.
- Harness review evidence:
  - v1 and v2 proved the relay/client path and found all 9 detail cards, but
    exposed detail sampler overhead and an over-strict pending transition check.
  - v3 proved the relay/client path and found all 9 detail cards, but exposed
    that the pending-request check was wrongly requiring all historical rows in
    one visible viewport sample.
  - v4 and v5 are the current passing proofs after the sampler and judge fixes.
- First passing simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-history-request SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-detail-history-request-v4 SIM_UI_SYNC_DURATION_MS=20000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v4 result: `OK: true`, `Relay client-path OK: true`, 18 UI samples,
  3 scored UI samples, 1 relay sample, 3 detail transitions, 0 detail failures,
  1 detail sweep, 9 detail sweep message card checks, observed UI lag 0 ms, and
  rendered detail lags 767 ms, 774 ms, and 1,717 ms under the 2,000 ms budget.
  Route counts were `initialize:5`, `initialized:5`, `dock/subscribe:2`,
  `dock/update:1`, `thread/read:1`, `thread/turns/list:2`, and
  `thread/resume:1`.
- Second passing simulator proof command:

```bash
rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO=detail-history-request SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-controlled-detail-history-request-v5 SIM_UI_SYNC_DURATION_MS=20000 SIM_UI_SYNC_SAMPLE_MS=250 SIM_UI_SYNC_SCENARIO_HOLD_MS=3500 MAX_UI_LAG_MS=2000 SIM_UI_SYNC_CHECKPOINT_SWEEP=1 SIM_UI_SYNC_READY_TIMEOUT_MS=60000
```

- v5 result: `OK: true`, `Relay client-path OK: true`, 18 UI samples,
  3 scored UI samples, 1 relay sample, 3 detail transitions, 0 detail failures,
  1 detail sweep, 9 detail sweep message card checks, observed UI lag 0 ms, and
  rendered detail lags 760 ms, 770 ms, and 1,704 ms under the 2,000 ms budget.
- Expanded matrix verification:
  - Combined the prior 18 scenario report directories with
    detail-history-request v4/v5.
  - Ran `SIM_UI_MATRIX_MIN_PASSES=2`.
  - Result: `OK: true`, 20 reports, 10 required scenarios, 10 passing
    scenarios, 2/2 passes per scenario, 0 missing scenarios, 0 failed
    scenarios, max observed UI lag 1,717 ms under the 2,000 ms budget,
    findings 0.
- Artifacts:
  - `/tmp/codex-client/sim-ui-controlled-detail-history-request-v4/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-detail-history-request-v4/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-detail-history-request-v5/relay-client-path.json`
  - `/tmp/codex-client/sim-ui-controlled-detail-history-request-v5/simulator-ui-sync.json`
  - `/tmp/codex-client/sim-ui-controlled-matrix-ten-scenario-double-loop-v1.json`
  - `/tmp/codex-client/sim-ui-controlled-matrix-ten-scenario-double-loop-v1.md`
- Review: this closes the current controlled full-detail/request simulator
  third-leg breadth. At that point it did not complete the full goal because
  runbook documentation, physical phone proof, natural real-relay gap breadth,
  and the final Composer 2.5 Fast completion consult were still open.

### 2026-05-31 - Phase 7 Exhaustive Sync Runbook

- Intent: close the Phase 7 documentation gate so a developer can rerun the
  exhaustive sync loop without reading harness source code or mining the
  implementation log.
- Changed:
  - Added `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md`.
  - Linked the runbook from `README.md`.
  - Added the runbook to the exhaustive plan's related-docs list.
- Runbook coverage:
  - local service prerequisites;
  - fast Node and Swift checks;
  - one-shot real relay audit;
  - over-time client-path soak with forced `dock/resync`;
  - relay scenario matrix;
  - `iPhone 17` controlled simulator matrix proof;
  - focused simulator scenario debugging;
  - matrix verification from existing artifacts;
  - physical phone proof commands and blockers;
  - pass/fail/blocked/outside-contract result rules;
  - CI-safe subsets;
  - report locations under `/tmp/codex-client/...`;
  - redaction rules.
- Proof:
  - `sed -n '1,320p' docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md`
    read back the full runbook.
  - `rg -n "Exhaustive Sync Harness|CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK|The final proof has three legs|Related docs" ...`
    verified the README link, plan link, and implementation-log anchors.
  - trailing whitespace/tab scan passed for `README.md`, the runbook, the plan,
    and this implementation log.
  - `rtk make -n sim-ui-controlled-matrix-proof SIM='iPhone 17' SIM_UI_CONTROLLED_MATRIX_PASSES=2 MAX_UI_LAG_MS=2000`
    passed as a dry-run and expanded to two passes across all 10 controlled
    scenarios with distinct report directories.
  - `git status --short -- README.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31_IMPLEMENTATION_LOG.md`
    showed the expected doc changes.
- Review: Phase 7 runbook documentation is now covered. The full goal remained
  open at that point because physical phone proof, natural real-relay gap
  breadth, and the final Composer 2.5 Fast completion consult were still
  required.

### 2026-05-31 - Physical Device Availability And Config Readback

- Intent: move the physical proof gate forward without reinstalling or
  reinstalling the app on a user's phone.
- Proof:
  - `rtk make devices` passed and showed:
    - iPhone 17 Pro `CB9FFF0E-89AD-57B5-9C00-6552D814875E` available.
    - iPhone 14 `0A4EFF8B-54D8-58FB-B3FB-63263265B9CC` available.
    - iPhone 13 Pro `DA37BD8A-A4EA-5377-937F-AB9EFC324F96` unavailable.
  - `rtk make device-config-verify-all` passed.
  - iPhone 17 Pro saved hosts matched
    `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
  - iPhone 14 saved hosts matched `Amir-M5.local:4510,192.168.50.74:4510`.
  - Physical Mobile MCP launched `com.aelaguiz.CodexDockApp` on its visible real
    iPhone, but screenshot capture failed with the exact blocker
    `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
    Per repo instructions, Mobile MCP physical retries stopped there.
  - `rtk make device-launch DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E` failed
    with the exact blocker `Unable to launch com.aelaguiz.CodexDockApp because
    the device was not, or could not be, unlocked`.
  - `rtk make device-debug-bundle DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`
    wrote `/tmp/codex-client/device-debug-bundle-iphone17pro-20260531T1011Z`.
    Existing physical route evidence included both iPhone 17 Pro relay hosts and
    `archive/subscribe`, `dock/resync`, `dock/subscribe`, `dock/update`,
    `thread/read`, `thread/resume`, and `thread/turns/list`.
  - `rtk make device-launch DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC` passed.
  - `rtk make device-debug-bundle DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`
    wrote `/tmp/codex-client/device-debug-bundle-iphone14-20260531T1013Z`.
    Fresh iPhone 14 route evidence at `2026-05-31T10:10:06Z` and
    `2026-05-31T10:10:07Z` covered both configured LAN relay hosts and
    `dock/resync`, `dock/subscribe`, and `dock/update` with no recorded
    failures.
- Review: this proves the two expected physical devices are available and their
  saved relay configs are correct. It also proves fresh physical iPhone 14 Dock
  route contact through app-owned diagnostics. It is not physical display proof:
  it does not prove real `DockThreadCard` rendering or physical offline/error UI.

### 2026-05-31 - Fresh Real-Home Moving-State Soaks

- Intent: strengthen the live real-relay proof against the user's core concern:
  local Codex state moves quickly, so the relay must keep the client-used routes
  current over time without hiding lag.
- Forced-resync command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --force-dock-resync --duration-ms 125000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 5 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-natural-soak-20260531T1015Z.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-natural-soak-20260531T1015Z.md --summary-only --fail-on-diff
```

- Forced-resync result: `ok: true`, 4 samples, 4 ok, `clientPathOK: true`,
  69 stream notifications, 8 `dock/resync`s, 225 `dock/update`s, 20
  `thread/read`s, 20 `thread/turns/list`s, 20 `thread/resume`s, 13 buffered
  initial live detail events, 0 long-lived stream mismatches, 0 stream lag
  failures, max observed stream lag 0 ms, and 0 detail failures.
- Unforced command:

```bash
rtk node scripts/dock-relay-sync-audit.mjs --relay-url ws://127.0.0.1:4510 --mode soak --client-path-only --duration-ms 65000 --sample-interval-ms 30000 --settle-ms 1000 --dock-collection-timeout-ms 120000 --stream-compare-attempts 5 --stream-compare-delay-ms 1000 --max-stream-lag-ms 2000 --detail sampled --detail-limit 5 --detail-observe-ms 100 --json-out /tmp/codex-client/sync-audit-real-home-client-path-natural-no-force-20260531T1013Z.json --summary-out /tmp/codex-client/sync-audit-real-home-client-path-natural-no-force-20260531T1013Z.md --summary-only --fail-on-diff
```

- Unforced result: `ok: true`, 2 samples, 2 ok, `clientPathOK: true`,
  15 stream notifications, 0 `dock/resync`s, 41 `dock/update`s, 10
  `thread/read`s, 10 `thread/turns/list`s, 10 `thread/resume`s, 6 buffered
  initial live detail events, 0 long-lived stream mismatches, 0 stream lag
  failures, max observed stream lag 0 ms, and 0 detail failures.
- Artifacts:
  - `/tmp/codex-client/sync-audit-real-home-client-path-natural-soak-20260531T1015Z.json`
  - `/tmp/codex-client/sync-audit-real-home-client-path-natural-soak-20260531T1015Z.md`
  - `/tmp/codex-client/sync-audit-real-home-client-path-natural-no-force-20260531T1013Z.json`
  - `/tmp/codex-client/sync-audit-real-home-client-path-natural-no-force-20260531T1013Z.md`
- Review: this covers fresh live real-home moving-state proof with and without
  forced resync. A spontaneous real-home sequence gap did not occur during the
  unforced window; deterministic gap recovery remains covered by the controlled
  `resync-gap` relay and simulator scenarios.
