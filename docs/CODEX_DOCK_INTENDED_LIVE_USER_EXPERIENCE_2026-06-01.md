# Codex Dock Intended Live User Experience

Date: 2026-06-01

## Intention

Codex Dock should behave like a live control panel for Codex, not like a cached
report.

The intended user experience is:

1. The Dock list shows the real current state of Codex work, newest activity
   first.

2. Opening a thread shows the real current contents of that thread.

3. If new work happens while the thread is open, the open Thread Detail updates
   without the user backing out, reopening, changing filters, or guessing
   whether it is stale.

4. The screen should not say `Live` unless the visible thread contents are
   actually converging with Codex's current state.

5. Filters should only change what category of rows the user is intentionally
   viewing. They should never explain away missing recent work.

6. `Messages` can mean "show message rows," but there must be an obvious,
   trustworthy way to see everything that happened. `All` should literally mean
   all renderable thread events that Codex has.

7. If the app cannot prove it is current, it should say that plainly: stale,
   reconnecting, delayed, or failed. It should not silently show old rows under
   a green-feeling state.

Net: when the user is actively working in Codex and then looks at Codex Dock,
the app should show the same reality the user is living in right now. Newest
work should be visible, detail views should keep up, and any gap should be
explicit instead of hidden behind filters, cache, relay drift, or fake `Live`
status.

## Implementation Notes

Iteration started on 2026-06-01:

- The open Thread Detail must converge when the Dock stream says that same
  thread advanced.
- The Dock stream is an invalidation signal only. Thread Detail must still
  reread canonical thread history through its own `thread/read` plus
  `thread/turns/list` path.
- A fix is not accepted just because the UI says `Live`; it must be checked
  against live relay truth and simulator-visible state.
- Current implementation direction:
  - Dock body rows and pinned rows open the same stable `ThreadDetailStore`.
  - Dock row activity is treated as an invalidation signal for the open Thread
    Detail.
  - Thread Detail still rereads canonical history through `thread/read`,
    `thread/turns/list`, and `thread/resume`.
  - Dock-driven refresh merges canonical history into the current live event
    index so live-ahead notifications are not deleted by an early canonical
    reread.
  - Reconnect and foreground recovery still replace from canonical history
    because those are session-boundary recovery paths.
- Latest whole-Dock displayed UI proof on 2026-06-01 used the live local
  relay path plus iPhone 17 simulator accessibility state.
  - Artifact directory:
    `/tmp/codex-client/sim-ui-sync-live-row-identity-20260601T151616Z`.
  - Simulator displayed-UI proof: `OK: true`.
  - Relay client-path proof: `OK: true`, `Client-path OK: true`.
  - UI samples: `10`, scored UI samples: `9`.
  - Displayed row checks: `40`.
  - Dock visible order checks: `9`.
  - UI lag observed: `3057 ms` against a `5000 ms` budget.
  - Relay stream mismatches: `0`.
  - Relay max observed stream lag: `0 ms`.
- Latest multi-lens Dock displayed UI proof on 2026-06-01 used the same
  canonical `sim-ui-sync-proof` path with
  `SIM_UI_SYNC_LENSES=newest,host,branch`.
  - Latest passing artifact directory:
    `/tmp/codex-client/sim-ui-sync-live-current-long-relay-20260601T1601Z`.
  - Simulator displayed-UI proof: `OK: true`.
  - Relay client-path proof: `OK: true`, `Client-path OK: true`.
  - UI samples: `5`, all scored.
  - Lens coverage: `newest` x2, `host` x2, `branch` x1.
  - Relay samples: `15`.
  - Displayed row checks: `17`.
  - Dock visible order checks: `2`.
  - UI lag observed: `0 ms` against a `5000 ms` budget.
  - Failures: none.
  - A shorter relay-recorder artifact
    `/tmp/codex-client/sim-ui-sync-live-current-20260601T1559Z` failed because
    the UI saw a `running` row after the relay recorder had stopped at the
    previous `idle` sample. A current relay probe confirmed the UI was ahead of
    the stale proof window, not stale versus live relay state.
  - Earlier passing artifact directory:
    `/tmp/codex-client/sim-ui-sync-live-lenses-short-20260601T152640Z`.
  - `newest` proves global relay render order. `host` and `branch` are grouped
    lenses, so they prove visible row identity/status/origin without applying
    the global newest-order check.
  - The longer artifact
    `/tmp/codex-client/sim-ui-sync-live-lenses-20260601T152504Z` is not cited
    as passing proof because XCTest exited non-zero and wrote a blocked proof
    report, even though it did write lens-tagged samples.
  - Fresh consult:
    `/tmp/fresh-consult/codex-dock-lens-proof-coverage-20260601T152725Z-WORhit`.
  - Fresh consult verdict: `pass-with-notes`, blocking findings: none,
    confidence: high.
- The latest live Dock fix removes duplicate SwiftUI row identity ownership:
  parent `ForEach` owns Dock row identity for newest, host, and branch
  surfaces; `DockSwipeActionRow` owns only swipe state.
  - Before-fix artifact:
    `/tmp/codex-client/sim-ui-sync-live-default-fast-20260601T150931Z`.
  - Before-fix failures: `dock_ui_duplicate_row` and
    `dock_ui_order_mismatch`.
  - Fix file: `CodexDock/Features/Dock/DockPinnedViews.swift`.
  - Fresh consult:
    `/tmp/fresh-consult/codex-dock-row-identity-fix-20260601T151825Z-FASIjT`.
  - Fresh consult verdict: `pass-with-notes`, blocking findings: none,
    confidence: high.
  - Second fresh consult:
    `/tmp/fresh-consult/codex-dock-row-identity-unity-20260601T151937Z-Npj34N`.
  - Second fresh consult verdict: `pass-with-notes`, blocking findings: none,
    confidence: high.
- Latest open Thread Detail proof on 2026-06-01 used real relay truth plus
  iPhone 17 simulator-visible state for thread
  `019e8402-ce6f-7733-a100-2e686b60778b`.
  - The live picker scanned recent Dock rows and found this thread had moving
    renderable filters:
    `/tmp/codex-client/live-moving-thread-picker-20260601T1610Z`.
  - Passing artifact directory:
    `/tmp/codex-client/live-filter-picked-019e8402-20260601T1612Z`.
  - Compare result: `status=pass`, `relayMoving=true`,
    `relayMovingInSampledFilters=true`,
    `relayMovingFilters=["agentMessage","all"]`, `uiMoving=true`.
  - Relay truth moved: `messages 15 -> 16`, `all 27 -> 48`,
    `agentMessage 22 -> 23`, `command 0 -> 10`, `output 0 -> 10`.
  - Simulator-visible Thread Detail moved while open:
    - First `all` run: `29 -> 32`.
    - `agentMessage` run: `25 -> 26`.
    - Second `all` run: `39 -> 50`.
  - UI samples: `45`.
  - Comparisons: `45`.
  - Failures: none.
- Previous open Thread Detail proof on 2026-06-01 used real relay truth plus
  iPhone 17 simulator-visible state for thread
  `019e7e7d-66ca-7280-9aa0-2e272f1752b1`.
  - Passing artifact directory:
    `/tmp/codex-client/live-filter-current-019e7e7d-output-20260601T154245Z`.
  - Final compare:
    `/tmp/codex-client/live-filter-current-019e7e7d-output-20260601T154245Z/compare-after-sampled-filter-final.json`.
  - Compare result: `status=pass`, `relayMoving=true`,
    `relayMovingInSampledFilters=true`, `relayMovingFilters=["output"]`,
    `uiMoving=true`.
  - Relay truth moved for `output`: `102 -> 106`.
  - Simulator-visible Thread Detail moved while open for `output`:
    `102 -> 104`.
  - Comparisons: `17`.
  - Failures: none.
  - The capped `messages/all` artifact
    `/tmp/codex-client/live-filter-current-019e7e7d-20260601T153250Z`
    is now correctly classified as `sampled_filter_movement_not_observed`,
    not as a UI update failure, because those sampled filters stayed capped at
    `240` while unsampled `command` and `output` filters moved.
  - Fresh consult on the final sampled-filter comparator:
    `/tmp/fresh-consult/codex-dock-sampled-filter-final-20260601T155654Z-0iE7RJ`.
  - Fresh consult verdict: `pass-with-notes`, blocking findings: none,
    confidence: high.
- Detailed work log:
  [CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01_WORKLOG.md](CODEX_DOCK_INTENDED_LIVE_USER_EXPERIENCE_2026-06-01_WORKLOG.md)

## Related Documents

- [User intention](CODEX_DOCK_USER_INTENTION_2026-06-01.md)
- [Trustworthy live window intention](CODEX_DOCK_TRUSTWORTHY_LIVE_WINDOW_INTENTION_2026-06-01.md)
- [Live means current user intention](CODEX_DOCK_LIVE_MEANS_CURRENT_USER_INTENTION_2026-06-01.md)
- [Live truth intention](CODEX_DOCK_LIVE_TRUTH_INTENTION_2026-06-01.md)
- [Live filter simulator audit worklog](CODEX_DOCK_LIVE_FILTER_SIM_AUDIT_WORKLOG_2026-06-01.md)
- [Live update architecture and testing reference](CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md)
- [Protocol and update architecture reference](CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md)
- [Relay data contract and lease drift audit](CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md)
- [Client card and thread detail complexity audit](CODEX_DOCK_CLIENT_CARD_AND_THREAD_DETAIL_COMPLEXITY_AUDIT_2026-05-31.md)
- [Thread types and states reference](CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md)
