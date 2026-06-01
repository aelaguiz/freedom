# Codex Dock Live Update Architecture Implementation Worklog

Plan: `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
Started: 2026-06-01
Status: complete

## North Star

Codex Dock must show current Dock, Archive, and Thread Detail state through one
relay-owned production truth path, and every freshness claim must be proven over
time from source change to rendered iPhone UI state.

## Implementation Ledger

| Phase | Status | Evidence |
| --- | --- | --- |
| Phase 1 - Canonical Current-Simulator UI Dump | complete | `rtk make sim-ui-dump SIM='iPhone 17'` wrote `/tmp/codex-client/sim-ui-dump-20260601T014628Z/sim-ui-dump.json` and `.md`; `rtk make app-test SIM='iPhone 17'` passed. |
| Phase 2 - Heartbeat And Stale-Stream Vertical Slice | complete | `rtk npm run test:relay`, `rtk swift test --filter DockStoreStreamTests`, and `rtk swift test --filter DockStoreTests` passed. |
| Phase 3 - Monotonic Stream State And Shared Dock/Archive Lifecycle | complete | `rtk swift test --filter DockStoreStreamTests`, `rtk swift test --filter DockStoreTests`, `rtk swift test --filter ArchiveDataEngineTests`, `rtk swift test --filter ArchiveScreenStoreTests`, `rtk swift test --filter ArchiveCleanupStoreTests`, and `rtk npm run test:relay` passed. Production `ThreadCardHostSnapshotLoader` and `ThreadCardStreamSnapshotCollector` were deleted. |
| Phase 4 - Thread Detail Full History And Visible Recovery | complete | `rtk swift test --filter AppServerClientTests`, `rtk swift test --filter ThreadDetailStoreTests`, and `rtk npm run test:relay` passed. New relay recovery coverage proves a successful upstream recovery closes the downstream phone socket with `1012` so Swift must reconnect and rehydrate. |
| Phase 5 - Relay Freshness Fails Closed | complete | Live-source refresh is now part of relay completeness proof; stale live refresh marks the stream stale. `rtk npm run test:relay` passed with 73 tests. |
| Phase 6 - Proof Contracts, Gates, And Runbook Alignment | complete | `rtk npm run contract:check` validates Dock card contracts plus 5 proof schemas and 5 canonical proof samples. Proof reports now reject raw `:4500`, scripted stream side doors, mismatched `proofRunID`, and missing relay-owned route evidence. |
| Phase 7 - Final Simulator And Phone-Claim Evidence | complete | Final order-aware matrix report `/tmp/codex-client/sim-ui-controlled-matrix-final3-20260601T055358Z/controlled-simulator-matrix.json` passed 12/12 required scenarios with max observed UI lag 1914 ms. `rtk make sim-ui-dump SIM='iPhone 17'` wrote current visible simulator proof and passed schema validation. |

## Pass 1 - 2026-06-01

- Resolved `$arch-step auto-implement` to `implement-loop`.
- Confirmed `arch_stage_gate.py ready` reports `READY next=implement-loop`.
- Opened the implementation gate in the plan because the required planning
  receipts, Composer consults, and plan-audit had passed.
- Started with Phase 1 so current simulator state can be dumped before deeper
  live-update changes.
- Added the canonical current-screen dump requirement to the plan invariants:
  `rtk make sim-ui-dump SIM='iPhone 17'` is the one operator path for dumping
  the already-visible simulator Dock or Thread Detail state.
- Extracted displayed UI capture into shared UITest support and added
  `CodexDockCurrentUIDumpTests/testDumpsCurrentVisibleScreenOnce`.
- Added `rtk make sim-ui-dump SIM='iPhone 17'`. The target copies config into
  the simulator filesystem, lets the UI test write accessibility JSON/Markdown
  there, then copies the artifacts back to `/tmp/codex-client/...` on the Mac.
- First successful dump observed the simulator on Thread Detail:
  `screenBefore=thread`, `screenAfter=thread`, `didRelaunch=false`,
  `activeThreadID=019e8004-daac-7900-a401-b2ecdaf47907`,
  `detailMessages=52`.
- Re-ran the dump after warning cleanup:
  `/tmp/codex-client/sim-ui-dump-20260601T014628Z/sim-ui-dump.json`.
- Ran `rtk make app-test SIM='iPhone 17'`; it passed after the dump test was
  integrated into the generated Xcode project.

## Pass 2 - 2026-06-01

- Added relay heartbeat cadence constant
  `RELAY_STATE_HEARTBEAT_INTERVAL_MS`.
- `StateSubscriptionHub` now starts heartbeat emission only while subscribers
  exist, emits per-view `kind:"heartbeat"` updates, and stops the timer when
  the final subscriber unsubscribes.
- Relay heartbeats carry the same stream contract fields as card updates:
  `schemaVersion`, `view`, `epoch`, `seq`, `stateGeneration`, `complete`,
  `totalRows`, `window`, and `freshness`.
- Added Swift `CodexDockConstants.Dock.streamHeartbeatTimeout`.
- `DockStore` now resets a per-host heartbeat/activity timer on subscribe and
  every update. If heartbeats/updates stop, it marks the host partial/offline
  with retained rows and uses the existing reconnect path.
- Added regression coverage:
  `DockStoreStreamTests.testMissingHeartbeatMarksConnectedHostStaleAndRetainsRows`
  and `scripts/dock-relay-state-subscriptions.test.mjs`.
- Verification:
  `rtk swift test --filter DockStoreStreamTests`,
  `rtk npm run test:relay`, and
  `rtk swift test --filter DockStoreTests` all passed.

## Pass 3 - 2026-06-01

- Completed the monotonic stream-state cutover started in the prior pass:
  `ThreadCardTable` stores per-host `stateGeneration`, rejects older compatible
  updates with `.staleGeneration`, and accepts an explicit expected stream view
  so Dock and Archive use the same table rules.
- Added `ThreadCardStreamLifecycle` as the shared Dock/Archive stream owner for
  subscribe, resync, update, heartbeat timeout, failure, reconnect, and publish
  callbacks.
- Migrated `ArchiveStore` to the shared long-lived Archive stream lifecycle.
  Active Archive no longer treats `archive/subscribe` as a one-shot freshness
  answer.
- Migrated Archive Cleanup preview to `DockCardStateProviding`; production
  cleanup now refreshes and reads the Dock store's stream-backed snapshot
  instead of opening a cleanup-specific Dock stream.
- Deleted production `ThreadCardHostSnapshotLoader` and
  `ThreadCardStreamSnapshotCollector`.
- Changed relay archive mutations so `thread/archive` and `thread/unarchive`
  immediately reconcile both Dock and Archive views. Added relay coverage that
  proves both views are invoked from one archive mutation.
- Verification:
  `rtk swift test --filter ArchiveCleanupStoreTests`,
  `rtk swift test --filter ArchiveDataEngineTests`,
  `rtk swift test --filter ArchiveScreenStoreTests`,
  `rtk swift test --filter DockStoreStreamTests`,
  `rtk swift test --filter DockStoreTests`, and
  `rtk npm run test:relay` all passed.

## Pass 4 - 2026-06-01

- Added `ThreadTurnItemsView` and optional `itemsView` to
  `ThreadTurnsListParams`.
- `ThreadDetailStore.readAllTurns` now requests `itemsView: .full` so the
  detail path asks the app-server/relay for full turn payloads instead of
  relying on a compact/default turn shape.
- Preserved the relay pass-through route for `thread/turns/list`; the new
  field rides the existing typed request contract rather than adding a side
  route.
- Changed relay live-thread upstream recovery: after a dropped upstream socket
  successfully reconnects and resumes, the relay closes the downstream phone
  socket with close code `1012` and reason `upstream recovered; rehydrate`.
  This makes recovery visible to Swift so the open Thread Detail view must
  reconnect and rebuild from history/live state.
- Added `scripts/dock-relay-thread-recovery.test.mjs` and included it in
  `npm run test:relay`.
- Updated Swift detail/session expectations so typed turn-list calls include
  `itemsView: .full`.
- Verification:
  `rtk swift test --filter AppServerClientTests`,
  `rtk swift test --filter ThreadDetailStoreTests`, and
  `rtk npm run test:relay` all passed. The Thread Detail lifecycle XCTest suite
  was included by the `ThreadDetailStoreTests` filter; a separate file-name
  filter ran zero tests because XCTest filters by suite/class names.

## Pass 5 - 2026-06-01

- Made relay Dock completeness fail closed on active live source refresh:
  `reconcileDock` now treats loaded live sessions as required freshness proof,
  so a failed live refresh reports a stale stream instead of publishing a
  falsely complete Dock view.
- Added relay coverage for that rule:
  `dock/subscribe marks stream stale when a live source refresh fails`.
- Closed controlled-fixture side doors that made simulator tests less real than
  production:
  controlled fake app-servers now implement `thread/read` and
  `thread/turns/list` where the real client path needs them, and detail/history
  fixtures return full thread rows with `source: "cli"`.
- Added the `archive-toggle` controlled scenario so the matrix proves Dock and
  Archive both move through the shared relay-owned mutation path.
- Fixed the live-lease-expiry proof to measure UI lag from the actual lease
  expiry time and expect the real post-expiry status, `dormant`.
- Taught the sync audit to understand relay heartbeat payloads, detect heartbeat
  sequence gaps, and compare semantic freshness fields such as `status` and
  `lastError` while ignoring harmless timestamp churn.
- Fixed replacement deltas: a relay delta that carries every current row is now
  marked complete even when it also deletes stale rows from the prior client
  view. This prevents a recovered source from staying visually `Partial` until
  a later heartbeat.
- Verification:
  `rtk npm exec -- node --test scripts/dock-relay-sync-audit.test.mjs`,
  `rtk npm exec -- node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs`,
  and `rtk npm exec -- node --test scripts/dock-relay-card-contract.test.mjs`
  passed.
- Focused simulator proof:
  `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO='source-refresh' ...`
  passed with observed UI lag 678 ms.
- Focused simulator proof:
  `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO='live-lease-expiry' ...`
  passed with observed UI lag 658 ms.
- Full simulator matrix:
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` passed. Report:
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260601T031820Z/controlled-simulator-matrix.json`.
  Summary: 11 required scenarios, 11 passing, 0 missing, 0 failed, 0 findings,
  max observed UI lag 1890 ms.
- Final relay suite:
  `rtk npm run test:relay` passed with 73 tests, 73 passing, 0 failing.

## Pass 6 - 2026-06-01

- Added proof report contracts under `contract/proof/` for relay sync audit,
  controlled simulator scenario relay reports, simulator UI sync proof,
  controlled simulator matrix reports, and current simulator UI dumps.
- Wired `scripts/check-proof-report-contracts.mjs` into
  `rtk npm run contract:check`, so proof artifacts are checked like the Dock
  card DTO contract instead of remaining free-form JSON.
- Added proof-level side-door guards:
  raw `ws://...:4500` app-server URLs cannot satisfy proof, scripted
  `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO` paths cannot satisfy live proof,
  passing reports must include relay-owned Dock/Archive/Thread route evidence,
  and simulator UI proof must share the same `proofRunID` as the embedded relay
  proof.
- Extended controlled proof to cover Archive as a real stream path. The
  `archive-toggle` scenario now opens `archive/subscribe`, observes
  `archive/update`, proves archive membership after archive, and proves removal
  after unarchive.
- Tightened Thread Detail proof. The `detail-history-request` and
  `server-request` scenarios now require real `thread/read` plus
  `thread/turns/list` calls with `itemsView: "full"` before detail correctness
  can pass.
- Tightened request-card visibility proof. A request is considered visible only
  when the simulator shows the expected request card identity with the expected
  event count, or the exact expected message event IDs when that is the intended
  assertion.
- Rejected the raw app-server proof side door in
  `scripts/dock-relay-sync-audit.mjs`; `--relay-url ws://...:4500` now fails
  before the audit can run.
- Fixed open Thread Detail reconnect handling in
  `CodexDock/State/ThreadDetailStore.swift`: reconnect rehydrate now replaces
  history/live state before replaying buffered live notifications, instead of
  appending on top of stale state.
- Added regression coverage in
  `CodexDockTests/ThreadDetailStoreLifecycleTests.swift` for reconnect
  rehydrate plus buffered live notification replay.
- Fixed the fake voice capture helper so each capture start gets a fresh fake
  stream. This made the full `ThreadDetailStoreTests` suite match real mic
  behavior instead of reusing a completed stream.
- Made `rtk make sim-ui-dump SIM='iPhone 17'` write canonical blocked artifacts
  even when the app is not running. Verified blocked output:
  `/tmp/codex-client/sim-ui-dump-20260601T041228Z/sim-ui-dump.json`.
- Verified happy-path current simulator dump after launching the app:
  `/tmp/codex-client/sim-ui-dump-20260601T041320Z/sim-ui-dump.json`,
  status `pass`, screen `dock`, state `runningForeground`, 55 visible elements,
  and 3 Dock rows.
- Final controlled simulator matrix:
  `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` passed. Report:
  `/tmp/codex-client/sim-ui-controlled-matrix-run-20260601T040651Z/controlled-simulator-matrix.json`.
  Summary: 11 required scenarios, 11 passing, 0 missing, 0 failed, 0 findings,
  max observed UI lag 1431 ms.
- Final verification:
  `rtk npm run contract:check`,
  `rtk npm run test:relay`,
  `rtk swift test --filter ThreadDetailStoreTests`, and
  `rtk swift test --filter DockStoreTests` all passed.
- Updated `README.md` with the canonical current simulator dump command and
  controlled over-time simulator proof command.

## Pass 7 - 2026-06-01

- Ran a fresh Composer 2.5 Fast consult against the implemented live-update
  architecture. Verdict: pass-with-notes, with one proof blind spot that
  mattered for the user's reported bug class: simulator UI proof checked
  membership/status but not visible ordering.
- Closed that blind spot in the proof path:
  `DisplayedUICaptureSupport.swift` now preserves actual top-to-bottom
  accessibility frame order, and `scripts/dock-relay-simulator-ui-sync-proof.mjs`
  compares Dock row order and Thread Detail message order against relay truth.
- Added matrix gates for ordering proof:
  `large-list-checkpoint` requires Dock sweep order proof,
  `detail-reconnect` and `detail-history-request` require Thread Detail message
  order proof, and the proof summaries now retain `dockVisibleOrderChecks`,
  `dockSweepOrderChecks`, and `detailMessageOrderChecks`.
- The stronger proof exposed a real Swift ordering bug in
  `DockCardProjection`: equal relay `orderKey` values were falling through to
  localized title comparison, while the relay tie-breaks by stable card ID.
  Swift now tie-breaks equal relay order keys with stable `hostID::threadID`.
- Added `DockStoreTestsProjection.testNewestProjectionUsesStableRowIDWhenRelayOrderKeysTie`
  for that bug.
- The stronger proof then exposed a proof/report bug in
  `dock-relay-sync-audit`: report sanitization stripped `activityAtMs` and
  `orderKey`, so merged multi-host expected order could drift from relay
  order. Sanitized proof cards now retain both fields.
- Added relay test coverage:
  `sync audit report sanitizer preserves relay ordering fields`.
- Final controlled simulator matrix:
  `/tmp/codex-client/sim-ui-controlled-matrix-final3-20260601T055358Z/controlled-simulator-matrix.json`.
  Summary: 12 required scenarios, 12 passing, 0 missing, 0 failed, 0
  unexpected, 0 findings, max observed UI lag 1914 ms.
- Final order-check coverage in that matrix:
  Dock visible order checks in `large-list-checkpoint`, `thread-activity`,
  `multi-host-isolation`, `resync-gap`, and `rapid-mutations`; Dock sweep order
  checks in those same scenarios; Thread Detail message order checks in
  `detail-reconnect` and `detail-history-request`.
- Final verification after the ordering fixes:
  `rtk npm run contract:check` passed,
  `rtk npm run test:relay` passed with 86 tests, and
  `rtk swift test --filter DockStoreTestsProjection` passed with 25 tests.

## Pass 8 - 2026-06-01

- Removed the stale simulator UI sync config override path from
  `CodexDockDisplayedSyncProofTests.swift`. The sync proof now has one
  canonical config path:
  `/tmp/codex-client/codex-dock-sim-ui-sync-config.json`, guarded by
  `/tmp/codex-client/codex-dock-sim-ui-sync-config.lock` in the Makefile
  targets.
- Verified the focused `detail-reconnect` proof after that cleanup. It passed
  with 38 UI samples, 35 detail samples, 2 detail transition checks, and 0
  failures.
- The full matrix then exposed two proof-contract ordering bugs:
  `detail-reconnect` had an older detail-message order expectation, and
  `multi-host-isolation` built its composite expected order from host-grouped
  sanitized cards instead of newest-first visible order across hosts.
- Fixed the controlled fixture expectations:
  `detail-reconnect` expects newest detail message first, and
  `multi-host-isolation` uses distinct fixture activity times plus composite
  render order that falls back to `activityAt` when `orderKey` is absent from
  sanitized report cards.
- Re-ran the focused `multi-host-isolation` proof after the composite-order
  fix. It passed with 16 UI samples, 78 displayed-row checks, 16 visible-order
  checks, and 0 failures.
- Final controlled simulator matrix:
  `/tmp/codex-client/sim-ui-controlled-matrix-final3-20260601T055358Z/controlled-simulator-matrix.json`.
  Summary: 12 required scenarios, 12 passing, 0 missing, 0 failed, 0
  unexpected, 0 findings, max observed UI lag 1914 ms.
- Final deterministic checks:
  `rtk npm run contract:check` passed,
  `rtk npm run test:relay` passed with 86 tests, and
  `rtk make app-test SIM='iPhone 17'` passed.
- Current simulator UI dump:
  `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1 && rtk make sim-ui-dump
  SIM='iPhone 17'` passed and wrote
  `/tmp/codex-client/sim-ui-dump-20260601T060445Z/sim-ui-dump.json`.
  Summary: status `pass`, screen `dock`, state `runningForeground`, 51
  visible elements, 4 Dock rows.
- Final Composer 2.5 Fast fresh consult:
  `/tmp/fresh-consult/codex-dock-live-update-implementation-20260601T060601Z-GNhrn8/final.txt`.
  Verdict: `pass-with-notes`; blocking findings: none.

## Pass 9 - 2026-06-01

- Closed the last proof-quality side door in `rtk make sim-ui-dump
  SIM='iPhone 17'`: if the dump test writes a blocked JSON artifact, the
  Makefile now runs `scripts/check-proof-report-contracts.mjs` on that artifact
  before exiting nonzero.
- Re-ran the current simulator dump after that hardening:
  `/tmp/codex-client/sim-ui-dump-20260601T061107Z/sim-ui-dump.json`.
  Summary: status `pass`, screen `dock`, state `runningForeground`, 51
  visible elements, 4 Dock rows, and proof schema validation passed.
