# Codex Dock Thread Detail Messages And History Worklog

Started: 2026-05-29T23:10:59Z

## Objective

Implement and test a default Thread Detail filter named `Messages` that shows
only user messages and actual AI messages, not tool calls or reasoning traces.
Root-cause and fix the visible `Not loaded` detail-state problem. Validate on
the `iPhone 17` simulator. Also investigate live-server full thread history and
duplicate partial/full message behavior instead of relying only on fixtures.

## Worklog

- 2026-05-29T23:10:59Z: Inspected Thread Detail filter/rendering paths:
  `ThreadDetailMessageFilter`, `SessionDetailView`, `ThreadMessageListView`,
  `ThreadDetailStore`, and simulator UI tests.
- 2026-05-29T23:10:59Z: Found the `Not loaded` root cause: `ThreadDetailHeader`
  copied `row.status.label`, and `.dormant.label` is `Not loaded`; Thread
  Detail then rendered that label even after the detail content loaded.
- 2026-05-29T23:10:59Z: Implemented `ThreadDetailMessageFilter.messages` as the
  default filter. Its inclusion rule is `visibilityCategory == .message` and
  `kind` is `.userMessage` or `.agentMessage`.
- 2026-05-29T23:10:59Z: Changed Thread Detail status display to use
  `row.status.visibleBadgeLabel`, so dormant/idle/unknown statuses do not show a
  visible stale status pill in detail.
- 2026-05-29T23:10:59Z: Added focused coverage:
  `ThreadEventNormalizerTests` for stored and live message filtering,
  `ThreadDetailHeaderTests` for dormant rows not showing `Not loaded`, and
  simulator UI coverage for the default `messages` filter plus a scripted
  dormant-row detail path.
- 2026-05-29T23:10:59Z: Ran focused checks:
  `rtk swift test --filter ThreadEventNormalizerTests`,
  `rtk swift test --filter ThreadDetailHeaderTests`, and
  `rtk swift test --filter ThreadDetailStoreTests`; all passed.
- 2026-05-29T23:10:59Z: Ran `rtk make app-test SIM='iPhone 17'`; passed on
  result bundle
  `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_18-08-43--0500.xcresult`
  with status `succeeded`, 247 tests, and 5 skipped.
- 2026-05-29T23:10:59Z: Ran a thermo-nuclear code-quality pass for the
  completed filter/status changes. Findings: the old optional-kind filter
  initializer became ambiguous after adding `messages`, and the new header test
  should not grow the already-large `ThreadDetailStoreTests.swift`. Resolved by
  removing the initializer/`selectedKind` helper and moving the header regression
  to `ThreadDetailHeaderTests.swift`.
- 2026-05-29T23:10:59Z: Discovered the active goal also includes live-server
  full thread history and duplicate partial/full message investigation. Work is
  continuing under this worklog; the filter/status work is not the full goal.
- 2026-05-29T23:13:25Z: Found duplicate partial/full root cause in
  `ThreadDetailStore.appendOrMerge`: live `item/agentMessage/delta` events and
  live `item/completed` full item snapshots have different event IDs even when
  they describe the same `turnId`/`itemId`, so exact-ID merging could display
  both.
- 2026-05-29T23:13:25Z: Added `ThreadEvent.isStreamingDelta` and a
  `StreamItemMergeKey` in `ThreadDetailStore` keyed by `turnID`, `itemID`,
  `kind`, and `visibilityCategory` for message/thinking/tooling item events.
  Full item snapshots now replace earlier deltas; late deltas after a full item
  snapshot are ignored instead of replacing the full text.
- 2026-05-29T23:13:25Z: Added
  `ThreadDetailStreamingMergeTests.testCompletedAgentMessageReplacesLiveDeltaInsteadOfDuplicating`;
  it passed with `rtk swift test --filter ThreadDetailStreamingMergeTests`.
- 2026-05-29T23:13:30Z: Reran
  `rtk swift test --filter ThreadEventNormalizerTests` and
  `rtk swift test --filter ThreadDetailStoreTests`; both passed.
- 2026-05-29T23:14:20Z: Ran a live relay probe against
  `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`
  without printing message bodies. `amir-m5` returned 20 list rows with 1
  loaded detail candidate. Paging that thread with `limit:1` reached 20 pages
  and was still not exhausted; reading with the app's `limit:250` returned 41
  turns and no `nextCursor`. `home` returned 20 list rows but no loaded detail
  candidates. This live evidence supports the current full-history path for
  available loaded threads and confirms the app's 250-turn page size gets the
  whole observed live thread in one page while still having cursor-loop code for
  larger threads.
- 2026-05-29T23:15:42Z: Reran `rtk make app-test SIM='iPhone 17'` after the
  duplicate-streaming fix. Result bundle
  `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_18-14-18--0500.xcresult`
  reported status `succeeded`, 248 tests, and 5 skipped. The result includes
  `ThreadDetailStreamingMergeTests.testCompletedAgentMessageReplacesLiveDeltaInsteadOfDuplicating`,
  `ThreadDetailHeaderTests.testDormantRowDoesNotShowNotLoadedAsThreadDetailStatus`,
  `CodexDockAutomationSmokeTests.testDockRowOpensSessionDetailByIdentifierWhenRowsExist`,
  and
  `CodexDockAutomationSmokeTests.testScriptedDormantRowDetailDoesNotShowNotLoadedStatus`.
- 2026-05-29T23:16:10Z: Ran the required thermo-nuclear code-quality review
  after the streaming fix. Findings from the earlier pass were already resolved:
  remove the ambiguous optional-kind filter initializer and move the detail
  header regression out of the large `ThreadDetailStoreTests.swift` file. New
  streaming merge review found no blockers: merge behavior is localized in
  `ThreadDetailStore`, uses a typed `StreamItemMergeKey` instead of scattered
  ID-string special cases, ignores late deltas after full snapshots, and keeps
  `ThreadDetailStore.swift` below 1,000 lines.
