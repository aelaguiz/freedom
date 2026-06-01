# Codex Dock Intended Live UX Worklog

Date: 2026-06-01

Parent doc:
[CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01.md](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01.md)

Intention doc:
[CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md](CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md)

## Goal

Make Codex Dock behave like a live control panel:

- Dock rows show current Codex work.
- Opening a thread shows current thread contents.
- An already-open Thread Detail keeps up when that thread advances.
- Filters only change intentional visibility; they do not explain away missing
  current work.
- `Live` means the visible thread contents are converging with Codex's current
  state.

## Iteration 1 - Dock Row Activity Invalidates Open Thread Detail

Status: superseded by Iteration 2

Root cause from live simulator proof:

- Moving target: `019e8305-970e-7243-9528-6ae3e9181ecf`
- Relay truth changed while the simulator had the same thread open:
  - `Messages`: `15 -> 19`
  - `All`: `24 -> 32`
- Simulator Thread Detail stayed frozen:
  - `Messages`: `15`
  - `All`: `25`
- The Dock stream continued to resync, but Thread Detail did not receive
  matching live item notifications.

Fix direction:

- Keep the Dock stream as the card-list freshness source.
- Use Dock row activity only as an invalidation signal for the currently open
  Thread Detail.
- Rehydrate Thread Detail through its existing canonical history path:
  `thread/read` plus `thread/turns/list`, followed by `thread/resume`.
- Do not let Dock card payloads become a second source of thread-event truth.

Code changed:

- `CodexDock/State/ThreadDetailStore.swift`
  - Added `observeDockRowUpdate(_:)`.
  - When the same Dock row advances, the store updates the header and queues a
    rehydrate through the existing `readFullThread` / `resumeCompactThread`
    path.
  - Relative label-only changes, such as `now` becoming `1m ago`, update the
    header but do not trigger a rehydrate.
- `CodexDock/Features/Dock/DockView.swift`
  - Keeps the active `ThreadDetailStore` while navigation is open.
  - Watches loaded Dock snapshots and forwards the matching updated row to the
    open detail store.
  - Handles both body rows and pinned rows through the same `openDetail(row:)`
    path.
- `CodexDockTests/ThreadDetailStoreTests.swift`
  - Added proof that a Dock row activity advance rehydrates from canonical
    history.
  - Added proof that relative label-only churn does not rehydrate.
- `CodexDockTests/ThreadDetailStoreTestSupport.swift`
  - Extended `makeDetailRow` so tests can set activity dates and order keys.

Test evidence:

```bash
rtk swift test --filter ThreadDetailStoreTests
```

Result:

- Passed.
- Executed `58` tests.
- Failures: `0`.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-live-detail-unity-20260601T124607Z-obY072`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Main note: body and pinned Dock rows were covered through the same open path;
  Archive detail was not covered and was treated as out of scope for the live
  Dock bug.

Why this was not enough:

- A later live simulator proof showed visible counts could still go down during
  open Thread Detail sampling.
- Root cause: Dock-driven rehydrate used canonical replacement. If live
  notifications were ahead of `thread/turns/list`, an early canonical read
  could delete the live-ahead rows from the visible event index.

## Iteration 2 - Preserve Live-Ahead Events During Dock-Driven Refresh

Status: implemented and unit-tested

Root cause:

- Dock row activity can lead canonical thread history by a few seconds.
- The open Thread Detail can already have newer live notification rows.
- Replacing the event index from an early canonical read makes the UI visibly
  move backward.

Fix direction:

- Keep using Dock row activity only as an invalidation signal.
- On Dock-driven refresh, reread canonical history and merge it into the current
  event index.
- Keep reconnect and foreground recovery as replace operations because those
  are session-boundary recovery paths where local live state may be wrong.
- Add one settled reread after `3` seconds through the same canonical history
  path so the relay has time to expose the new turn through
  `thread/turns/list`.

Code changed:

- `CodexDock/State/ThreadDetailStore.swift`
  - Added Dock row activity markers.
  - Added immediate and settled Dock-row refresh scheduling.
  - Changed Dock-driven refresh to `mergeEvents(from:liveState:)`.
  - Kept reconnect and foreground rehydrate on `replaceEvents(from:liveState:)`.
- `CodexDock/Configuration/CodexDockConstants.swift`
  - Added `CodexDockConstants.Dock.threadDetailCanonicalHistorySettleDelay`.
- `CodexDockTests/ThreadDetailStoreTests.swift`
  - Updated Dock-row refresh tests so canonical rereads are full history, not
    single-row replacement fixtures.
  - Added
    `testDockRowAdvanceDoesNotDropLiveAheadEventBeforeCanonicalHistorySettles`.

Test evidence:

```bash
rtk swift test --filter ThreadDetailStoreTests
```

Result:

- Passed.
- Executed `60` tests.
- Failures: `0`.

Relay/proof harness evidence:

```bash
rtk node --test scripts/codex-dock-live-filter-truth.test.mjs scripts/codex-dock-live-filter-compare.test.mjs
rtk npm run test:relay
```

Results:

- Live filter proof-script tests: `5` passed, `0` failed.
- Relay test suite: `91` passed, `0` failed.

Proof harness corrections:

- `scripts/codex-dock-live-filter-truth.mjs`
  - Requests `thread/turns/list` with `sortDirection: "desc"` and
    `itemsView: "full"`.
  - Counts whitespace-only command output the same way Swift does: it is not a
    visible Output row.
- `scripts/codex-dock-live-filter-compare.mjs`
  - Compares settled-history convergence over time instead of exact
    nearest-sample equality.
  - Allows the UI to be ahead of settled relay history because live
    notifications can arrive before canonical history settles.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-settled-detail-refresh-20260601T125916Z-J8UPl7`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Main note: the settled reread is justified by the real Dock-leads-history
  race.

## Iteration 3 - Fresh Consult On Merge-Vs-Replace And Live Simulator Proof

Status: current best evidence passes for live Dock Thread Detail

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-thread-detail-live-merge-20260601T132152Z-JOIHEq`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Summary: the fix is unified for the live Dock path. Dock body rows, pinned
  rows, host lenses, branch lenses, and open Thread Detail use the same stable
  store and Dock-row invalidation path. Merge for Dock-driven refresh and
  replace for reconnect/foreground is a principled distinction, not a side
  door.
- Non-blocking notes:
  - Archive Thread Detail does not use `observeDockRowUpdate`; this is treated
    as out of scope for the live Dock bug.
  - Store tests cover the bug class directly, but there is no separate
    `DockView.syncSelectedDetail` wiring unit test.
  - If more refresh paths appear, the merge/replace distinction should become
    typed or more explicitly documented.

First live iPhone 17 proof attempt:

- Artifact directory:
  `/tmp/codex-client/live-filter-moving-019e8348-merge-20260601T132425Z`
- Target thread: `019e8348-da6a-79a1-9c3e-080e06a01638`
- Compare result: `status=fail`, `relayMoving=true`, `uiMoving=false`.
- Interpretation: this did not prove the app was wrong. Relay movement happened
  before the simulator began sampling the open Thread Detail, and the first UI
  sample was already caught up at `Messages=32`, `All=45`.

Second live iPhone 17 proof attempt:

- Artifact directory:
  `/tmp/codex-client/live-filter-moving-019e8348-merge-rerun-20260601T132656Z`
- Target thread: `019e8348-da6a-79a1-9c3e-080e06a01638`
- Config:
  - Hosts: `127.0.0.1:4510`
  - Filters: `messages`, `all`, `messages`
  - Dwell: `20000` ms
  - Sample interval: `1000` ms
- Relay truth:
  - `Messages`: `35 -> 37`
  - `All`: `48 -> 50`
  - `activityAt` changed from `2026-06-01T13:26:38.000Z` to
    `2026-06-01T13:27:24.000Z`
- Simulator-visible Thread Detail:
  - `Messages` run 0: `36 -> 37`
  - `All` run 1: `50 -> 50`
  - `Messages` run 2: `37 -> 37`
  - No count drops were observed.
- Compare:

```bash
rtk node scripts/codex-dock-live-filter-compare.mjs \
  --relay-truth /tmp/codex-client/live-filter-moving-019e8348-merge-rerun-20260601T132656Z/relay-truth-over-time.json \
  --ui-proof /tmp/codex-client/live-filter-moving-019e8348-merge-rerun-20260601T132656Z/live-filter-ui.json \
  --json-out /tmp/codex-client/live-filter-moving-019e8348-merge-rerun-20260601T132656Z/compare.json \
  --max-lag-ms 7000 \
  --require-moving
```

Result:

- `status=pass`
- `relayMoving=true`
- `uiMoving=true`
- Comparisons: `57`

Current conclusion:

- The original open-detail freeze is fixed for the live Dock path under real
  relay and iPhone 17 simulator evidence.
- The prior count-drop failure is covered by unit tests and was not observed in
  the passing simulator proof.
- This is not a claim that every future live edge case is proven; it is the
  current strongest evidence for the user's stated live Dock intention.

## Iteration 4 - Per-View Stream Sequence Cursors

Status: implemented, consulted, relay-tested

Root cause:

- Dock and Archive streams shared a global sequence counter.
- A Dock subscriber could receive an Archive-only sequence jump and interpret
  it as a gap in the Dock stream.
- That made the proof path noisier than the product contract: Dock continuity
  should be measured against Dock stream state, Archive continuity against
  Archive stream state.

Fix direction:

- Keep one relay state store, but expose per-view stream cursors for Dock and
  Archive continuity.
- Publish Dock deltas with Dock `baseSeq` and Archive deltas with Archive
  `baseSeq`.
- Keep global state sequencing internal; client-facing stream continuity is
  view-specific.

Code changed:

- `scripts/dock-relay-state-store.mjs`
  - Added `currentSeqForView(view)`.
  - Reconciliation now returns `baseSeq` plus `seq` for the affected view.
  - Stale-scope marking also returns per-view sequence data.
- `scripts/dock-relay-state-engine.mjs`
  - Dock and Archive publish paths now use the per-view `baseSeq`.
  - Heartbeats, snapshots, and catchup abandonment read per-view stream
    sequence.
- `scripts/dock-relay-state-subscriptions.mjs`
  - Subscription sequence fields use per-view stream sequence when available.
- Relay tests were extended for:
  - Store-level per-view stream sequence cursors.
  - Heartbeat sequence by subscribed view.
  - Dock subscriber continuity when Archive-only reconciliation happens between
    Dock updates.
  - Sync-audit acceptance of per-view sequence jumps when `baseSeq` is
    coherent.

Test evidence:

```bash
rtk npm run test:relay
```

Result:

- Passed.
- Executed `95` tests.
- Failures: `0`.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-per-view-stream-seq-20260601T140211Z-8PsZoH`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Main note: this is a unified per-view stream fix; no production path was
  found still using the global sequence for client continuity.

## Iteration 5 - Simulator Proof Uses Live Stream Truth

Status: implemented, consulted, relay-tested

Root cause:

- The iPhone 17 displayed-UI proof failed even though the UI had followed a
  live `dock/update` delta.
- The verifier compared simulator UI samples to sparse periodic
  `dock/subscribe` snapshots and ignored the timestamped stream state produced
  by live `dock/update` notifications.
- Example from artifact
  `/tmp/codex-client/sim-ui-sync-live-20260601T140348Z`:
  - UI sample at `2026-06-01T14:04:47.452Z` showed the order after a live
    stream delta.
  - Relay periodic sample `1` finished earlier at
    `2026-06-01T14:04:44.156Z` and still had the old order.
  - Relay client-path evidence had a `dock/update` delta at
    `2026-06-01T14:04:46.901Z`, before the UI sample.
  - Later relay periodic sample `2` matched the UI order, proving the UI had
    followed stream truth ahead of the sparse verifier sample.

Second proof-harness issue:

- The checkpoint sweep expected `221` rows but only captured `118` because the
  simulator sweep has a `30` step cap.
- Treating a capped sweep as if it had exhaustively visited every row created
  false missing-row failures.

Fix direction:

- Treat `dock/update` and `archive/update` stream notifications as timestamped
  relay truth in the proof report.
- Score each UI sample against the newest relay stream truth at or before that
  UI sample.
- Label capped checkpoint sweeps as partial evidence instead of pretending
  they are exhaustive.

Code changed:

- `scripts/dock-relay-sync-audit.mjs`
  - `DockStreamProbe` now attaches a sanitized current snapshot to each
    stream `delta` or `snapshot` notification after applying it.
- `scripts/dock-relay-simulator-ui-sync-proof.mjs`
  - `relayTruthSamples` now merges periodic samples, stream notification
    snapshots, and transition truths into one ordered truth timeline.
  - Capped sweeps with `stopReason == "maxSteps"` no longer generate
    exhaustive missing-row/count failures.
- `CodexDockUITests/DisplayedUICaptureSupport.swift`
  - Dock sweeps now report `maxSteps` and `stopReason`.
- `scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
  - Added proof that stream notification truth is used between sparse relay
    samples.
  - Added proof that a large capped sweep does not fail solely because the cap
    prevented exhaustive coverage.

Test evidence:

```bash
rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs scripts/dock-relay-sync-audit.test.mjs
rtk npm run test:relay
```

Results:

- Focused verifier tests: `32` passed, `0` failed.
- Relay test suite: `97` passed, `0` failed.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-sim-proof-live-truth-20260601T141330Z-Qvrtv6`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Main note: this is a unified verifier fix. It aligns simulator proof with
  the `dock/update` stream truth the app actually receives, while preserving
  row, status, order, and lag checks.

## Iteration 6 - Voice Forwarding Task Does Not Retain Thread Detail Store

Status: implemented, consulted, Swift-tested

Root cause:

- `ThreadDetailStoreTests` failed intermittently only when the full suite ran.
- The failing test changed between runs:
  - `testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit`
  - `testUnexpectedCaptureStreamEndFailsRecoverablyWithoutSubmitting`
- Each failed test passed by itself.
- Root cause was a cleanup bug in `startVoiceCaptureForwarding`:
  - The detached task captured `[weak self]`.
  - It immediately promoted that to strong `self`.
  - The task then waited on an audio `AsyncStream`.
  - Tests that intentionally left capture active could keep old
    `ThreadDetailStore` instances and tasks alive into later tests.

Fix direction:

- The long-running forwarding task should hold only the audio session,
  transcription session, and voice capture engine while waiting for chunks.
- It should touch `ThreadDetailStore` only after stream completion or failure.

Code changed:

- `CodexDock/State/ThreadDetailStore+Voice.swift`
  - Removed the early strong `guard let self` from the detached forwarding
    task.
  - Completion/failure callbacks now use `self?`.

Test evidence:

```bash
rtk swift test --filter ThreadDetailStoreTests
```

Result:

- Passed after the fix.
- Executed `60` tests.
- Failures: `0`.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-voice-forwarding-retain-cycle-20260601T141846Z-67450`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Main note: this is a unified lifecycle fix. It removes a store-retain cycle
  without changing active voice capture, commit, stream end, append failure, or
  cancellation behavior.

## Iteration 7 - Simulator Proof Scores Dock Rows At Observation Time

Status: implemented, consulted, relay-tested

Root cause:

- A later iPhone 17 displayed-UI proof failed with:
  - `dock_ui_order_mismatch`
  - `dock_ui_sweep_order_mismatch`
- Relay client-path proof was healthy:
  - `OK: true`
  - `Client-path OK: true`
  - Long-lived stream mismatches: `0`
  - Max observed stream lag: `0 ms`
- Artifact directory:
  `/tmp/codex-client/sim-ui-sync-live-20260601T141708Z`
- The failing UI sample was captured at `2026-06-01T14:18:27.639Z`, but
  `sample.finishedAt` was `2026-06-01T14:21:15.323Z` because the same sample
  performed a long checkpoint sweep after reading visible rows.
- The verifier used `finishedAt`, so it compared visible top rows from
  `14:18:27` against relay truth from `14:20:12`.

Fix direction:

- Dock-row comparisons should use `sampledAt`, because that is when the
  visible Dock rows were read.
- `finishedAt` remains useful metadata, but it must not move visible-row truth
  into the future when a sample includes long extra work.

Code changed:

- `scripts/dock-relay-simulator-ui-sync-proof.mjs`
  - `sampleTimeMS` now prefers `sampledAt` over `finishedAt`.
  - Added a short code comment explaining that `finishedAt` may include a long
    checkpoint sweep after visible rows were read.
- `scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
  - Added a regression test proving visible Dock rows are scored at
    `sampledAt` even when a checkpoint sweep finishes after a later relay
    reorder.

Test evidence:

```bash
rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs
rtk npm run test:relay
```

Results:

- Focused verifier tests: `28` passed, `0` failed.
- Relay test suite: `100` passed, `0` failed.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-ui-proof-sampled-at-20260601T143529Z-74132`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Main note: this is a correct verifier clock-skew fix. It removes a false
  `dock_ui_order_mismatch` without weakening real row order or lag detection.

## Iteration 8 - Current iPhone 17 Displayed-UI Proof Passes

Status: passed

Command:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17' SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-sync-live-20260601T143633Z SIM_UI_SYNC_HOSTS='127.0.0.1:4510' SIM_UI_SYNC_RELAY_WS='ws://127.0.0.1:4510'
```

Artifact directory:

```bash
/tmp/codex-client/sim-ui-sync-live-20260601T143633Z
```

Simulator displayed-UI proof:

- Started: `2026-06-01T14:36:45.207Z`
- Ended: `2026-06-01T14:37:52.193Z`
- Relay: `ws://127.0.0.1:4510/`
- OK: `true`
- Relay client-path OK: `true`
- UI samples: `32`
- Scored UI samples: `32`
- Relay samples: `16`
- Displayed row checks: `128`
- Checkpoint sweeps: `1`
- Checkpoint sweep row checks: `109`
- Dock visible order checks: `32`
- UI lag budget: `2000 ms`
- UI lag observed: `0 ms`
- UI lag converged: `true`
- Best consecutive passing samples: `32`
- Failures: none

Relay client-path proof:

- Started: `2026-06-01T14:36:39.661Z`
- Ended: `2026-06-01T14:39:46.423Z`
- OK: `true`
- Client-path OK: `true`
- Samples: `7`
- Errors: `0`
- Warnings: `0`
- Long-lived stream mismatches: `0`
- Stream lag budget: `2000 ms`
- Max observed stream lag: `0 ms`
- Stream lag failures: `0`
- Detail probes: `35`
- Client-path routes:
  `dock/resync`, `dock/subscribe`, `dock/update`, `initialize`,
  `initialized`, `thread/read`, `thread/resume`, `thread/turns/list`

Current conclusion:

- The current live Dock list path passes against relay truth and literal
  iPhone 17 simulator accessibility state.
- The prior visible-order failure was a verifier clock-skew bug caused by long
  checkpoint sweep duration, not proven app misordering.
- The open Thread Detail live-update path still has the earlier passing
  moving-thread proof from Iteration 3.
- This remains a live-system proof, not a mathematical guarantee that no future
  edge case exists. It is the strongest current evidence that the app now
  matches the intended live user experience for the checked surfaces.

## Iteration 9 - Fast Live Proof Exposes Real Duplicate Dock Rows

Status: failed, root-caused

Artifact directory:

```bash
/tmp/codex-client/sim-ui-sync-live-default-fast-20260601T150931Z
```

Simulator displayed-UI proof:

- OK: `false`
- Relay client-path OK: `true`
- UI samples: `5`
- Scored UI samples: `5`
- Relay samples: `3`
- Displayed row checks: `20`
- Dock visible order checks: `5`
- UI lag budget: `5000 ms`
- UI lag observed: `3261 ms`
- UI lag converged: `true`
- Best consecutive passing samples: `2`

Failures:

- `dock_ui_duplicate_row`
- `dock_ui_order_mismatch`

Key evidence:

- The relay client path passed in the same run:
  - `OK: true`
  - `Client-path OK: true`
  - Long-lived stream mismatches: `0`
  - Stream lag failures: `0`
  - Detail probes: `10`
  - Client-path routes:
    `dock/resync`, `dock/subscribe`, `dock/update`, `initialize`,
    `initialized`, `thread/read`, `thread/resume`, `thread/turns/list`
- Visible samples exposed duplicate row IDs while relay truth remained ordered:
  - Sample 1:
    `019e8364 > 019e7e7d > 019e8364 > 019e83a6`
  - Sample 4:
    `019e82fa > 019e7e7d > 019e8364 > 019e7e7d`

Root cause:

- This was not a relay data loss bug.
- `DockView` already renders Dock body rows through parent keyed collections:
  - `ForEach(projection.rows)` for the newest lens.
  - `ForEach(group.rows)` for host and branch lenses.
- `DockSwipeActionRow` also applied `.id(row.id)` inside each row.
- That gave SwiftUI two row identity owners for the same row. During live
  reorder, the parent list could move rows while the nested row identity kept a
  stale accessibility subtree alive, making the simulator-visible UI expose the
  same row twice.

Conclusion:

- The relay was current.
- The client rendered duplicate visible rows during live reorder because row
  identity ownership was split between parent `ForEach` and child row wrapper.

## Iteration 10 - Dock Row Identity Ownership Unified

Status: implemented, tested, consulted

Fix direction:

- Parent `ForEach` owns Dock row identity.
- `DockSwipeActionRow` owns only swipe state.
- No dedupe layer, filter workaround, or relay workaround was added.

Code changed:

- `CodexDock/Features/Dock/DockPinnedViews.swift`
  - Removed nested `.id(row.id)` from `DockSwipeActionRow`.
  - Added a code comment saying parent `ForEach` owns row identity and nested
    `.id` must not be reintroduced.
  - Kept data-driven swipe resets non-animated.
  - Kept the guard that avoids creating a spring transaction when there is no
    open swipe offset.

Live proof command:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17' SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-sync-live-row-identity-20260601T151616Z SIM_UI_SYNC_HOSTS='127.0.0.1:4510' SIM_UI_SYNC_RELAY_WS='ws://127.0.0.1:4510' SIM_UI_SYNC_DURATION_MS=30000 SIM_UI_SYNC_SAMPLE_MS=1500 SIM_UI_SYNC_RELAY_DURATION_MS=30000 SIM_UI_SYNC_RELAY_SAMPLE_MS=5000 MAX_UI_LAG_MS=5000
```

Artifact directory:

```bash
/tmp/codex-client/sim-ui-sync-live-row-identity-20260601T151616Z
```

Simulator displayed-UI proof:

- Started: `2026-06-01T15:16:28.538Z`
- Ended: `2026-06-01T15:16:55.979Z`
- Relay: `ws://127.0.0.1:4510/`
- OK: `true`
- Relay client-path OK: `true`
- UI samples: `10`
- Scored UI samples: `9`
- Relay samples: `5`
- Displayed row checks: `40`
- Dock visible order checks: `9`
- UI lag budget: `5000 ms`
- UI lag observed: `3057 ms`
- UI lag converged: `true`
- Best consecutive passing samples: `8`
- Failures: none

Relay client-path proof:

- Started: `2026-06-01T15:16:23.184Z`
- Ended: `2026-06-01T15:16:53.186Z`
- OK: `true`
- Client-path OK: `true`
- Samples: `3`
- Errors: `0`
- Warnings: `0`
- Long-lived stream mismatches: `0`
- Stream lag budget: `5000 ms`
- Max observed stream lag: `0 ms`
- Stream lag failures: `0`
- Detail probes: `15`
- Detail buffered initial live events: `3`
- Client-path routes:
  `dock/resync`, `dock/subscribe`, `dock/update`, `initialize`,
  `initialized`, `thread/read`, `thread/resume`, `thread/turns/list`

Test evidence:

```bash
rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs scripts/codex-dock-live-filter-compare.test.mjs
rtk swift test --filter DockStoreTests
rtk npm run test:relay
rtk swift test --filter ThreadDetailStoreTests
```

Results:

- Proof-tool tests: `38` passed, `0` failed.
- Dock Swift tests: `54` passed, `0` failed.
- Relay test suite: `110` passed, `0` failed.
- Thread Detail tests:
  - One run in parallel with the full relay suite timed out in
    `testUnexpectedCaptureStreamEndFailsRecoverablyWithoutSubmitting`.
  - The same test passed alone in `0.082 s`.
  - The full Thread Detail suite then passed alone: `60` passed, `0` failed.
  - Current interpretation: the timeout was test-run contention, not a
    repeatable product failure from the Dock row identity fix.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-row-identity-fix-20260601T151825Z-FASIjT`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Confidence: high
- Summary for parent:
  removing nested `.id(row.id)` restores single identity ownership for all
  `DockSwipeActionRow` surfaces, preserves pinned UIKit swipe behavior, and
  creates more unity rather than more complexity.

Current conclusion:

- The duplicate visible Dock-row bug was a client SwiftUI identity bug.
- The relay client path was already correct for this failure.
- The fix is localized and unifies the row identity rule across newest, host,
  and branch Dock surfaces.

## Iteration 11 - Continuation Verification After Row Identity Fix

Status: verified, consulted

Checks rerun in this continuation:

```bash
rtk npm run test:relay
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests/testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit
rtk swift test --filter ThreadDetailStoreTests
```

Results:

- Relay test suite: `110` passed, `0` failed.
- Dock Swift tests: `54` passed, `0` failed.
- The parallel Thread Detail run timed out once in
  `testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit`
  while another SwiftPM process was also using `.build`.
- The exact timeout test passed alone in `0.086 s`.
- The full Thread Detail suite then passed alone: `60` passed, `0` failed.

Second fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-row-identity-unity-20260601T151937Z-Npj34N`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Confidence: high
- Summary for parent:
  the row-identity fix is a single choke-point fix in `DockSwipeActionRow`,
  covers the swipeable newest/host/branch Dock surfaces, removes duplicate row
  identity ownership, and does not create a new one-off path.

Current conclusion:

- The row-identity fix remains accepted after a second cold read.
- The remaining question before closing the broader intention goal is whether
  the existing current Dock proof plus the earlier moving Thread Detail proof
  are enough, or whether another current Thread Detail simulator proof should be
  run before calling the live user experience achieved.

## Iteration 12 - Current Open Thread Detail Moving Proof

Status: passed

Target:

- Thread ID: `019e7e7d-66ca-7280-9aa0-2e272f1752b1`
- Relay path: `ws://127.0.0.1:4510`
- Simulator: `iPhone 17`

First current proof attempt:

- Artifact directory:
  `/tmp/codex-client/live-filter-current-019e7e7d-20260601T152657Z`
- Filters: `messages`, `all`, `messages`
- Result: `status=fail`, `relayMoving=true`, `uiMoving=false`.
- Interpretation: this was not strong evidence of a product failure. The
  target thread had more than `240` rows under `messages` and `all`, so the
  simulator-visible count hook stayed capped at `240`. Because the run did not
  include a detail row sweep, the UI proof had no visible event IDs to prove
  movement.

Second current proof attempt:

```bash
rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockLiveFilterProofTests/testSamplesRealThreadDetailFiltersOverTime'
rtk node scripts/codex-dock-live-filter-truth.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --thread-id 019e7e7d-66ca-7280-9aa0-2e272f1752b1 \
  --json-out /tmp/codex-client/live-filter-current-command-output-019e7e7d-20260601T153008Z/relay-truth-over-time.json \
  --duration-ms 110000 \
  --sample-ms 1000
rtk node scripts/codex-dock-live-filter-compare.mjs \
  --relay-truth /tmp/codex-client/live-filter-current-command-output-019e7e7d-20260601T153008Z/relay-truth-over-time.json \
  --ui-proof /tmp/codex-client/live-filter-current-command-output-019e7e7d-20260601T153008Z/live-filter-ui.json \
  --json-out /tmp/codex-client/live-filter-current-command-output-019e7e7d-20260601T153008Z/compare.json \
  --max-lag-ms 7000 \
  --require-moving
```

Artifact directory:

```bash
/tmp/codex-client/live-filter-current-command-output-019e7e7d-20260601T153008Z
```

Config:

- Filters: `command`, `output`, `command`
- Dwell: `15000` ms
- Sample interval: `1000` ms
- Detail sweep: disabled

Relay truth:

- Samples: `60`
- Moving: `true`
- Activity changed from `2026-06-01T15:29:39.000Z` to
  `2026-06-01T15:31:46.000Z`.
- `command`: `100 -> 101`
- `output`: `65 -> 66`

Simulator-visible Thread Detail:

- UI samples: `39`
- First `command` run: `100 -> 101`
- `output` run: `66 -> 66`
- Second `command` run: `101 -> 101`

Compare result:

- `status=pass`
- `relayMoving=true`
- `uiMoving=true`
- Comparisons: `39`
- Failures: none

Current conclusion:

- The current open Thread Detail path converged for an actively moving real
  Codex thread when the proof used an uncapped visible signal.
- The failed capped `messages/all` attempt is a proof-method lesson, not a
  product regression.

## Iteration 13 - Multi-Lens Dock Live Proof Coverage

Status: verified, consulted

Reason for this iteration:

- The duplicate-row fix touched `DockSwipeActionRow`, which is shared by the
  newest, host, and branch Dock surfaces.
- The first passing live proof exercised the newest surface.
- The proof harness needed to switch lenses inside the same simulator-visible
  path so host and branch were checked without creating a second proof route.

Harness changes inspected:

- `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`
  - Added optional `dockLenses` to the displayed-UI proof config.
  - The no-open-thread Dock sampler now rotates configured lenses with the same
    XCTest and the same accessibility capture path.
  - Samples are appended incrementally so a blocked run still leaves usable
    partial evidence.
- `scripts/dock-relay-simulator-ui-sync-proof.mjs`
  - Reads `lens=` from the Dock root accessibility value.
  - Applies global relay render-order checks only to `newest`.
  - Keeps duplicate, status, origin, unexpected-row, row-count, and freshness
    checks active across all lenses.
- `scripts/dock-relay-simulator-ui-sync-proof.test.mjs`
  - Proves grouped host/branch lenses skip global order checks.
  - Proves grouped host/branch lenses still fail duplicate visible rows.
- `Makefile`
  - Added `SIM_UI_SYNC_LENSES`, defaulting to `newest`.
  - The canonical `sim-ui-sync-proof` target writes `dockLenses` into the same
    locked simulator config file:
    `/tmp/codex-client/codex-dock-sim-ui-sync-config.json`.

Live proof command:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17' SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-sync-live-lenses-short-20260601T152640Z SIM_UI_SYNC_HOSTS='127.0.0.1:4510' SIM_UI_SYNC_RELAY_WS='ws://127.0.0.1:4510' SIM_UI_SYNC_LENSES='newest,host,branch' SIM_UI_SYNC_DURATION_MS=15000 SIM_UI_SYNC_SAMPLE_MS=1500 SIM_UI_SYNC_RELAY_DURATION_MS=15000 SIM_UI_SYNC_RELAY_SAMPLE_MS=5000 MAX_UI_LAG_MS=5000
```

Passing artifact directory:

```bash
/tmp/codex-client/sim-ui-sync-live-lenses-short-20260601T152640Z
```

Simulator displayed-UI proof:

- Started: `2026-06-01T15:26:49.410Z`
- Ended: `2026-06-01T15:27:03.305Z`
- Relay: `ws://127.0.0.1:4510/`
- OK: `true`
- Relay client-path OK: `true`
- UI samples: `5`
- Scored UI samples: `5`
- Relay samples: `3`
- Displayed row checks: `17`
- Dock visible order checks: `2`
- UI lag budget: `5000 ms`
- UI lag observed: `0 ms`
- UI lag converged: `true`
- Best consecutive passing samples: `5`
- Failures: none

Lens coverage from `ui-samples.jsonl`:

- `newest`: `2`
- `host`: `2`
- `branch`: `1`

Relay client-path proof:

- Started: `2026-06-01T15:26:44.997Z`
- Ended: `2026-06-01T15:27:01.042Z`
- OK: `true`
- Client-path OK: `true`
- Samples: `2`
- Errors: `0`
- Warnings: `0`
- Long-lived stream mismatches: `0`
- Stream lag budget: `5000 ms`
- Max observed stream lag: `0 ms`
- Stream lag failures: `0`
- Detail probes: `10`
- Detail buffered initial live events: `2`
- Client-path routes:
  `dock/resync`, `dock/subscribe`, `dock/update`, `initialize`,
  `initialized`, `thread/read`, `thread/resume`, `thread/turns/list`

Blocked longer run:

- Artifact directory:
  `/tmp/codex-client/sim-ui-sync-live-lenses-20260601T152504Z`
- Status: blocked, not passing proof.
- Reason:
  `sim UI sync test failed; see /Users/aelaguiz/workspace/codex-client/.codex-dock/logs/sim-ui-sync-test-20260601152505.log`
- The test log showed XCTest exited non-zero after `50.815 s` without a verifier
  mismatch or product assertion message.
- The run wrote five lens-tagged samples, but it is not cited as passing
  evidence because the proof report is blocked.

Focused test evidence:

```bash
rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs
rtk swift test --filter DockStoreTests
rtk npm run test:relay
```

Results:

- Simulator proof-tool tests: `33` passed, `0` failed.
- Dock Swift tests: `54` passed, `0` failed.
- Relay test suite after the harness change: `112` passed, `0` failed.

Fresh consult:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-lens-proof-coverage-20260601T152725Z-WORhit`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Confidence: high
- Summary for parent:
  lens cycling is a unified, canonical improvement to `sim-ui-sync-proof`: same
  Make target, same XCTest, same config path, and same verifier. The verifier
  correctly skips global render-order checks for grouped host/branch lenses
  while still enforcing duplicate/status/origin row checks on all lenses. The
  short live run proves newest, host, and branch were sampled and passed.

Current conclusion:

- The row-identity fix is now live-proven on the visible newest, host, and
  branch Dock surfaces.
- This does not replace scenario or controlled fixture proof.
- Together with Iteration 12, the current evidence now covers live Dock rows
  and an actively moving open Thread Detail on the iPhone 17 simulator.

Continuation note:

- A later long combined lens-cycling run also crashed XCTest and wrote a blocked
  proof report:
  `/tmp/codex-client/sim-ui-sync-live-lenses-rerun-20260601T153756Z`.
- That run is not cited as passing evidence.
- Separate per-lens reruns avoided the long-process lens-cycling instability:
  - Host:
    `/tmp/codex-client/sim-ui-sync-live-host-lens-20260601T154100Z`,
    `OK: true`, `5` UI samples, `15` displayed row checks, no failures.
  - Branch:
    `/tmp/codex-client/sim-ui-sync-live-branch-lens-20260601T154153Z`,
    `OK: true`, `5` UI samples, `15` displayed row checks, no failures.
- Focused UI smoke test also passed:
  `rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testDockLensesAndFiltersAreDrivableInSimulator'`.

## Iteration 14 - Sampled-Filter Movement Comparator Correction

Status: verified, consulted

Reason for this iteration:

- A current open Thread Detail proof against thread
  `019e7e7d-66ca-7280-9aa0-2e272f1752b1` originally reported
  `relayMoving=true` and `uiMoving=false`.
- That sounded like a product failure, but the proof sampled only `messages`,
  `all`, and `messages`.
- On this thread, those filters were capped at `240` visible rows and their
  visible heads did not change.
- Relay truth did move overall, but the movement was in unsampled filters such
  as `command` and `output`.
- App logs from the same run showed the open Thread Detail was refreshing while
  the simulator had it open.

Root cause:

- The comparator treated `relayTruth.summary.moving` as enough to require UI
  movement, even when the relay movement happened only outside the filters the
  UI proof sampled.
- That made the proof harness capable of falsely blaming the product UI for a
  bad witness plan.

Code changed:

- `scripts/codex-dock-live-filter-compare.mjs`
  - Added sampled-filter movement accounting:
    `relayMovingInSampledFilters` and `relayMovingFilters`.
  - `--require-moving` now requires movement in at least one sampled relay
    filter before it can demand matching UI movement.
  - If relay moved only outside sampled filters, the proof fails with
    `sampled_filter_movement_not_observed`.
  - If a sampled relay filter moved and the UI did not, the proof fails with
    `moving_updates_not_proven`.
  - Updated `--require-moving` help text to name the sampled-filter scope.
  - Clarified the `moving_updates_not_proven` payload so it includes both
    overall `relayMoving` and scoped `relayMovingInSampledFilters`.
- `scripts/codex-dock-live-filter-compare.test.mjs`
  - Added proof that unsampled relay movement does not produce
    `moving_updates_not_proven`.
  - Added proof that sampled relay movement with static UI does produce
    `moving_updates_not_proven`.

Rechecked capped artifact:

```bash
rtk node scripts/codex-dock-live-filter-compare.mjs \
  --relay-truth /tmp/codex-client/live-filter-current-019e7e7d-20260601T153250Z/relay-truth-over-time.json \
  --ui-proof /tmp/codex-client/live-filter-current-019e7e7d-20260601T153250Z/live-filter-ui.json \
  --json-out /tmp/codex-client/live-filter-current-019e7e7d-20260601T153250Z/compare-after-sampled-filter-final.json \
  --max-lag-ms 7000 \
  --require-moving
```

Result:

- `status=fail`
- `relayMoving=true`
- `relayMovingInSampledFilters=false`
- `relayMovingFilters=[]`
- `uiMoving=false`
- Failure code: `sampled_filter_movement_not_observed`
- Sampled filters: `all`, `messages`
- Interpretation: this artifact does not prove UI movement or UI failure. It
  proves the proof sampled filters that did not visibly move.

Passing moving Thread Detail artifact:

```bash
rtk node scripts/codex-dock-live-filter-compare.mjs \
  --relay-truth /tmp/codex-client/live-filter-current-019e7e7d-output-20260601T154245Z/relay-truth-over-time.json \
  --ui-proof /tmp/codex-client/live-filter-current-019e7e7d-output-20260601T154245Z/live-filter-ui.json \
  --json-out /tmp/codex-client/live-filter-current-019e7e7d-output-20260601T154245Z/compare-after-sampled-filter-final.json \
  --max-lag-ms 7000 \
  --require-moving
```

Result:

- `status=pass`
- `relayMoving=true`
- `relayMovingInSampledFilters=true`
- `relayMovingFilters=["output"]`
- `uiMoving=true`
- Relay `output`: `102 -> 106`
- Simulator-visible `output`: `102 -> 104`
- UI samples: `17`
- Comparisons: `17`
- Failures: none

Focused test evidence:

```bash
rtk node --test scripts/codex-dock-live-filter-compare.test.mjs scripts/codex-dock-live-filter-truth.test.mjs
rtk npm run test:relay
```

Results:

- Live filter proof-script tests: `14` passed, `0` failed.
- Relay test suite after comparator polish: `114` passed, `0` failed.

Fresh consult 1:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-sampled-filter-moving-20260601T155419Z-GQ4DtJ`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Confidence: high
- Summary for parent:
  the sampled-filter movement fix is correct, honest, and unified in the
  canonical compare script. It stops falsely blaming the UI when relay movement
  happened only in unsampled filters while the proof watched capped filters.

Fresh consult 2:

- Runtime: `agent`
- Model: `composer-2.5-fast`
- Effort: `encoded-in-model`
- Run directory:
  `/tmp/fresh-consult/codex-dock-sampled-filter-final-20260601T155654Z-0iE7RJ`
- Verdict: `pass-with-notes`
- Blocking findings: none
- Confidence: high
- Summary for parent:
  the polish fully implements the prior notes: help text, positive
  `moving_updates_not_proven` test, and failure payload separation for overall
  relay movement versus sampled-filter movement. No blocking comparator work
  remains; continue live simulator testing and use moving filters or detail
  sweeps on capped threads.

Current conclusion:

- The comparator no longer confuses "relay moved somewhere" with "the
  UI-sampled filter moved."
- The current open Thread Detail path is proven moving on the iPhone 17
  simulator when sampled against an uncapped moving filter.
- Capped `messages/all` artifacts are now classified as weak proof, not as
  product failures.

## Iteration 15 - Current Live Simulator Rerun

Status: Dock passed; Thread Detail convergence passed; moving Thread Detail
proof was inconclusive because the sampled filter did not move

Service checks:

```bash
rtk make app-server-status
rtk make dock-relay-status
rtk make sim-config-verify SIM='iPhone 17'
```

Results:

- Raw app-server ready: yes.
- Dock relay ready: yes.
- Relay status snapshot/history/routes: OK.
- iPhone 17 simulator config: installed.

Short Dock proof attempt:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17' \
  SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-sync-live-current-20260601T1559Z \
  SIM_UI_SYNC_HOSTS='127.0.0.1:4510' \
  SIM_UI_SYNC_RELAY_WS='ws://127.0.0.1:4510' \
  SIM_UI_SYNC_LENSES='newest,host,branch' \
  SIM_UI_SYNC_DURATION_MS=15000 \
  SIM_UI_SYNC_SAMPLE_MS=1500 \
  SIM_UI_SYNC_RELAY_DURATION_MS=15000 \
  SIM_UI_SYNC_RELAY_SAMPLE_MS=5000 \
  MAX_UI_LAG_MS=5000
```

Result:

- `status=fail`
- Failure:
  `dock_ui_row_status_mismatch`
- Key:
  `Amir-M5::019e7e7d-66ca-7280-9aa0-2e272f1752b1`
- UI status at `2026-06-01T15:59:37.999Z`: `running`
- Relay sample used by the verifier finished at
  `2026-06-01T15:59:33.432Z` with status `idle`.
- Current relay probe at `2026-06-01T16:00:10.446Z` showed the same thread as
  `running` with `activityAt=2026-06-01T15:59:34.000Z`.

Interpretation:

- This was a proof-window issue, not stale UI.
- The UI saw a newer relay state than the short relay recorder retained.
- The short recorder ended too soon to score a live status transition near the
  end of the UI sample window.

Passing Dock proof rerun:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17' \
  SIM_UI_SYNC_DIR=/tmp/codex-client/sim-ui-sync-live-current-long-relay-20260601T1601Z \
  SIM_UI_SYNC_HOSTS='127.0.0.1:4510' \
  SIM_UI_SYNC_RELAY_WS='ws://127.0.0.1:4510' \
  SIM_UI_SYNC_LENSES='newest,host,branch' \
  SIM_UI_SYNC_DURATION_MS=15000 \
  SIM_UI_SYNC_SAMPLE_MS=1500 \
  SIM_UI_SYNC_RELAY_DURATION_MS=45000 \
  SIM_UI_SYNC_RELAY_SAMPLE_MS=5000 \
  MAX_UI_LAG_MS=5000
```

Artifact directory:

```bash
/tmp/codex-client/sim-ui-sync-live-current-long-relay-20260601T1601Z
```

Result:

- `status=pass`
- `OK: true`
- Relay client-path OK: `true`
- UI samples: `5`
- Scored UI samples: `5`
- Relay samples: `15`
- Lens coverage: `newest` x2, `host` x2, `branch` x1
- Displayed row checks: `17`
- Dock visible order checks: `2`
- UI lag observed: `0 ms`
- Failures: none

Open Thread Detail rerun:

```bash
rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockLiveFilterProofTests/testSamplesRealThreadDetailFiltersOverTime'
rtk node scripts/codex-dock-live-filter-truth.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --thread-id 019e7e7d-66ca-7280-9aa0-2e272f1752b1 \
  --json-out /tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z/relay-truth-over-time.json \
  --duration-ms 90000 \
  --sample-ms 1000
rtk node scripts/codex-dock-live-filter-compare.mjs \
  --relay-truth /tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z/relay-truth-over-time.json \
  --ui-proof /tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z/live-filter-ui.json \
  --json-out /tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z/compare.json \
  --max-lag-ms 7000 \
  --require-moving
```

Artifact directory:

```bash
/tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z
```

Moving compare result:

- `status=fail`
- `relayMoving=true`
- `relayMovingInSampledFilters=false`
- `relayMovingFilters=[]`
- `uiMoving=false`
- Failure code: `sampled_filter_movement_not_observed`
- Sampled filter: `output`

Relay truth:

- Overall `activityAt` moved:
  `2026-06-01T16:02:48.000Z -> 2026-06-01T16:04:14.000Z`
- `output`: `0 -> 0`
- `command`: `33 -> 33`
- `messages`: capped `240 -> 240`
- `all`: capped `240 -> 240`

Convergence-only compare:

```bash
rtk node scripts/codex-dock-live-filter-compare.mjs \
  --relay-truth /tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z/relay-truth-over-time.json \
  --ui-proof /tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z/live-filter-ui.json \
  --json-out /tmp/codex-client/live-filter-current-output-rerun-20260601T1603Z/compare-convergence-only.json \
  --max-lag-ms 7000
```

Result:

- `status=pass`
- `relayMoving=true`
- `relayMovingInSampledFilters=false`
- `uiMoving=false`
- Comparisons: `20`

Regression checks:

```bash
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter DockStoreTests
```

Results:

- `ThreadDetailStoreTests`: `60` passed, `0` failed.
- `DockStoreTests`: `54` passed, `0` failed.

Interpretation:

- The open Thread Detail showed the correct static `output=0` visible state.
- This run did not prove moving Thread Detail updates because no sampled
  renderable filter moved.
- That is not a product regression under the corrected comparator; it is an
  honest "bad movement witness" result.

Current conclusion:

- Latest current Dock proof passes on newest, host, and branch lenses.
- Latest current Thread Detail rerun proves convergence for a static sampled
  filter.
- A `20s` relay-truth scan of the top three recent Dock threads did not find a
  currently moving renderable Thread Detail filter:
  - `/tmp/codex-client/live-target-scan-019e7e7d-20260601T1607Z`
  - `/tmp/codex-client/live-target-scan-019e82fa-20260601T1607Z`
  - `/tmp/codex-client/live-target-scan-019e8364-20260601T1607Z`
- For all three scanned threads, `messages` and `all` were capped/static and
  `command`, `output`, `request`, `unknown`, and message-specific filters did
  not change during the scan window.
- The broader moving Thread Detail claim still relies on the earlier passing
  moving artifact:
  `/tmp/codex-client/live-filter-current-019e7e7d-output-20260601T154245Z`.

## Iteration 16 - Broad Live Thread Picker And Moving Thread Detail Proof

Status: passed

Reason for this iteration:

- The previous fresh Thread Detail rerun picked a thread whose Dock
  `activityAt` moved but whose sampled renderable filters did not.
- The user correctly pointed out that there are many active threads on this
  machine, so a narrow top-three scan was not enough.

Picker:

- Temporary picker script:
  `/tmp/codex-client/live-moving-thread-picker-20260601T1610Z.mjs`
- Output directory:
  `/tmp/codex-client/live-moving-thread-picker-20260601T1610Z`
- Method:
  - Read the live Dock from `ws://127.0.0.1:4510`.
  - Scan up to `18` recent Dock rows in batches of `3`.
  - Record `30s` of relay truth per candidate.
  - Stop as soon as a candidate has a moving renderable Thread Detail filter.

Winner:

- Thread ID: `019e8402-ce6f-7733-a100-2e686b60778b`
- Host: `Amir-M5`
- Status at pick time: `dormant`
- Activity at pick time: `2026-06-01T16:40:14.000Z`
- Title:
  `is our shader system compatible with android - the one we built for our animations`
- Picker evidence:
  - `all`: `26 -> 27`
  - `agentMessage`: `21 -> 22`
- Picker report:
  `/tmp/codex-client/live-moving-thread-picker-20260601T1610Z/picker-report.json`

Live simulator proof command:

```bash
rtk make app-test SIM='iPhone 17' APP_TEST_ONLY='CodexDockUITests/CodexDockLiveFilterProofTests/testSamplesRealThreadDetailFiltersOverTime'
rtk node scripts/codex-dock-live-filter-truth.mjs \
  --relay-url ws://127.0.0.1:4510 \
  --thread-id 019e8402-ce6f-7733-a100-2e686b60778b \
  --json-out /tmp/codex-client/live-filter-picked-019e8402-20260601T1612Z/relay-truth-over-time.json \
  --duration-ms 90000 \
  --sample-ms 1000
rtk node scripts/codex-dock-live-filter-compare.mjs \
  --relay-truth /tmp/codex-client/live-filter-picked-019e8402-20260601T1612Z/relay-truth-over-time.json \
  --ui-proof /tmp/codex-client/live-filter-picked-019e8402-20260601T1612Z/live-filter-ui.json \
  --json-out /tmp/codex-client/live-filter-picked-019e8402-20260601T1612Z/compare.json \
  --max-lag-ms 7000 \
  --require-moving
```

Artifact directory:

```bash
/tmp/codex-client/live-filter-picked-019e8402-20260601T1612Z
```

Relay truth:

- Samples: `85`
- Started: `2026-06-01T16:42:30.252Z`
- Finished: `2026-06-01T16:44:00.288Z`
- Overall moving: `true`
- `activityAt` moved:
  `2026-06-01T16:42:13.000Z -> 2026-06-01T16:43:43.000Z`
- Moving filters:
  - `messages`: `15 -> 16`
  - `all`: `27 -> 48`
  - `agentMessage`: `22 -> 23`
  - `command`: `0 -> 10`
  - `output`: `0 -> 10`

Simulator-visible Thread Detail:

- UI status: `pass`
- Captured: `2026-06-01T16:42:48.463Z`
- Finished: `2026-06-01T16:43:45.171Z`
- Opened thread:
  `019e8402-ce6f-7733-a100-2e686b60778b`
- Filters sampled: `all`, `agentMessage`, `all`
- UI samples: `45`
- First `all` run: `29 -> 32`
- `agentMessage` run: `25 -> 26`
- Second `all` run: `39 -> 50`

Compare result:

- `status=pass`
- `relayMoving=true`
- `relayMovingInSampledFilters=true`
- `relayMovingFilters=["agentMessage","all"]`
- `uiMoving=true`
- Comparisons: `45`
- Failures: none

Current conclusion:

- The live simulator proof now uses a thread selected from a broader live scan,
  not a hand-picked stale candidate.
- The open Thread Detail visibly moved while the iPhone 17 simulator had that
  thread open.
- This is current positive evidence for the intended experience: real relay
  movement in sampled Thread Detail filters converged into simulator-visible UI
  movement without reopening the thread.
