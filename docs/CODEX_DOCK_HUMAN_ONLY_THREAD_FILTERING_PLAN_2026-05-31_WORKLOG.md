---
title: "Codex Dock - Human-Only Thread Filtering - Implementation Worklog"
date: 2026-05-31
status: complete
doc_type: implementation_worklog
related:
  - docs/CODEX_DOCK_HUMAN_ONLY_THREAD_FILTERING_PLAN_2026-05-31.md
  - docs/CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md
  - /tmp/fresh-consult/human-only-final-signoff-r3-20260531T130712Z-OOZPrO/final.txt
---

# Implementation Worklog

## Summary

Implemented the human-only app-facing thread invariant on branch
`codex-dock-agents-tab-live-counts`.

Primary implementation commit:

- `48c8d95dc06991d85a864e388ba60864f9e9531a` -
  `Enforce human-only Dock threads`

Follow-up implementation in this pass:

- Thread Detail now maps relay `-32043` human-only rejections to
  `Thread unavailable.` through `ThreadDetailHumanOnlyRejection` and proves it
  does not call `thread/resume` after a rejected `thread/read`.
- `AppServerClientTests` now proves the typed `-32043` JSON-RPC error code and
  redacted data survive Swift decoding.

Manual-fork implementation in the later 2026-05-31 pass:

- Fork is now a relationship, not an origin. Human-source manual forks are
  accepted as human-started rows with `relationship: "forked"` and
  `forkedFromID`; spawned children, `exec`, app-server/API, MCP,
  memory/internal, unknown, missing-source, and contradictory-source rows
  remain rejected.
- Relay list/search state enriches eligible rows with authoritative
  `thread/read includeTurns:false` metadata before publishing app-facing cards.
  It may supplement omitted candidates from `session_index.jsonl`, but only
  after authoritative read confirms a human-started row.
- Dock and Archive streams both carry the relationship metadata. Archived
  manual forks stay out of active Dock by design and appear in Archive with the
  same `Fork` badge metadata.
- Swift decodes older cards without relationship fields, projects forked cards
  into fork-badged rows, preserves relationship in cached pinned display
  snapshots, opens Archive rows into Thread Detail, and shows the fork pill in
  Thread Detail.

## Phase Evidence

Phase 1 - Canonical classifier plus Dock subscribe slice:

- Added `scripts/dock-relay-human-thread-filter.mjs`.
- Reused source normalization from `scripts/dock-relay-source-filter.mjs`.
- Removed normal all-source Dock reconciliation from the app-facing path.
- Proof: `rtk npm run test:relay` passed with 216 tests, 0 failures.

Phase 2 - Complete relay state, Archive, live leases, and cleanup:

- Added human-only store cleanup and SQL helpers in
  `scripts/dock-relay-state-store-human-filter.mjs`.
- Guarded persisted Dock cards, Archive cards, card lookup, live leases, and
  `SessionRouter` outputs.
- Proof: `rtk npm run test:relay` passed with 216 tests, 0 failures.
- Proof: `rtk swift test --filter DockStoreTests` passed with 48 tests, 0
  failures.
- Proof: `rtk swift test --filter DockStoreStreamTests` passed with 12 tests,
  0 failures.
- Proof: `rtk swift test --filter DockRenderProjectorTests` passed with 4
  tests, 0 failures.
- Proof: `rtk swift test --filter ArchiveDataEngineTests` passed with 3 tests,
  0 failures.

Phase 3 - Raw route, detail, resume, and focused-turn gates:

- Added direct-ID rejection to raw app-facing routes through
  `assertHumanThreadID` and relay error code `-32043`.
- Added `thread/resume` preflight and accepted-human focused-turn session
  binding.
- Proof: `rtk npm run test:relay` passed with 216 tests, 0 failures.
- Proof: `rtk swift test --filter AppServerClientTests` passed on
  2026-05-31 with 53 tests, 5 expected env-gated skips, and 0 failures.

Phase 4 - Swift defensive filtering, pinned metadata, filters, and detail UX:

- Added `CodexDock/State/HumanThreadCardPolicy.swift`.
- Guarded stream collection, thread-card table insertion, projection, and
  cached pinned display revival.
- Added Thread Detail handling for relay human-only rejection code `-32043`.
- Proof: `rtk swift test --filter DockStoreTests` passed with 48 tests, 0
  failures.
- Proof: `rtk swift test --filter DockStoreStreamTests` passed with 12 tests,
  0 failures.
- Proof: `rtk swift test --filter DockDataEngineTests` passed with 3 tests, 0
  failures.
- Proof: `rtk swift test --filter DockRenderProjectorTests` passed with 4
  tests, 0 failures.
- Proof: `rtk swift test --filter ArchiveDataEngineTests` passed with 3 tests,
  0 failures.
- Proof: `rtk swift test --filter ThreadDetailStoreTests` passed on
  2026-05-31 with 55 tests, 0 failures.

Phase 5 - Contracts, diagnostics, simulator, live proof, and docs sync:

- Updated controlled simulator and sync-audit spawn-edge expectations so
  spawned child rows stay absent and reject through `thread/read`.
- Updated state snapshot and parity diagnostics to label normal app-facing
  visibility as human-started only and all-source data as diagnostic.
- The manual-fork pass did change the Dock card contract and generated Swift
  DTO by adding optional `relationship` and `forkedFromID` fields. It did not
  change Makefile targets, README runbook text, app target settings, assets, or
  physical-device paths.
- Proof: `rtk npm run test:relay` passed with 216 tests, 0 failures.
- Proof: `rtk git diff --check` passed on 2026-05-31.
- `rtk make dock-relay-restart` completed on 2026-05-31 so live proof tested
  the current relay MJS code, not a stale launchd process.
- Service status commands passed on 2026-05-31:
  - `rtk make app-server-status`
  - `rtk make dock-relay-status`
- `rtk make relay-doctor` passed on 2026-05-31 with no reported problems.
- Live JSON-RPC proof on 2026-05-31:
  - 186 Dock cards returned from `dock/subscribe`.
  - 1 Archive card returned from `archive/subscribe`.
  - 0 sampled app-facing Dock/Archive cards had non-human `lane` or
    `sourceKind`.
  - `state/query` reported app-facing human-started-only visibility.
  - Diagnostic snapshot used `includeRejectedThreads: true` and reported
    `visibility.mode: diagnostic_includes_rejected_threads`.
  - Diagnostic rejected counts sampled in the first 100 rows: `not_base_level`
    2,121 and `exec` 214.
  - Sampled rejected thread
    `019e7de1-161d-79f0-b10d-551eb0890a4e`.
  - `thread/read` rejected the sample with `-32043`.
  - `thread/resume` rejected the sample with `-32043`.
- Live SQLite proof on 2026-05-31:
  - active human cards: 186.
  - archived human cards: 1.
  - rejected cards: 0.
  - live leases total: 10.
  - rejected live leases: 0.

Manual-fork live proof on 2026-05-31:

- `thread/read` for `Flutter tests`
  (`019e7e1c-0f7a-7051-90bc-22c71490a9c8`) succeeded through the relay.
- The authoritative row has `source: "vscode"` and
  `forkedFromId: "019e7da2-9dbe-79f2-b084-7ff7113b59e3"`, so the
  classification is human-started plus forked.
- Active Dock returned 186 rows, did not include `Flutter tests`, and had 0
  automation cards in the visible window because the thread is archived.
- Archive returned 75 rows and included `Flutter tests` with `lane: "human"`,
  `sourceKind: "human"`, `relationship: "forked"`, matching `forkedFromID`,
  `archiveState: "archived"`, and 0 automation cards in the visible window.
- iPhone 17 simulator build `20260531141919` showed `Flutter tests` in Archive
  as a button with visible `Fork` badge and accessibility value
  `relationship=forked`; tapping the row opened Thread Detail, whose header
  showed the `Fork` pill instead of `Thread unavailable.`

## Review Evidence

- Planning fresh consult:
  `/tmp/fresh-consult/human-only-thread-filter-20260531T113112Z-w8uhbk/final.txt`
- Planning fresh consult round 2:
  `/tmp/fresh-consult/human-only-thread-filter-r2-20260531T113408Z-NieUSV/final.txt`
- Post-implementation fresh consult:
  `/tmp/fresh-consult/human-only-implementation-20260531T122616Z-sSlkaH/final.txt`
  returned `pass-with-notes`, `BLOCKING: none`; its notes were folded back
  into the shipped implementation.
- Final pre-commit fresh consult:
  `/tmp/fresh-consult/human-only-final-signoff-r3-20260531T130712Z-OOZPrO/final.txt`
  returned `pass-with-notes`, `BLOCKING: none`, and high confidence after
  reading the final working tree and re-running `rtk npm run test:relay` plus
  `rtk swift test --filter ThreadDetailStoreTests`.

## Thermo-Nuclear Code Quality Review Receipt

Date: 2026-05-31
Verdict: PASS

- The policy lives in one canonical relay module:
  `scripts/dock-relay-human-thread-filter.mjs`.
- State-store SQL policy was split into
  `scripts/dock-relay-state-store-human-filter.mjs`, keeping
  `scripts/dock-relay-state-store.mjs` at 995 lines instead of pushing it over
  the 1,000-line threshold.
- Swift uses one defensive card policy in
  `CodexDock/State/HumanThreadCardPolicy.swift` rather than scattered
  ad-hoc UI checks.
- Thread Detail rejection messaging lives in
  `CodexDock/State/ThreadDetailHumanOnlyRejection.swift`, keeping
  `CodexDock/State/ThreadDetailStore.swift` at 993 lines after the follow-up
  fix.
- Live-service proof is complete against the restarted local relay.

Reviewed against the `$thermo-nuclear-code-quality-review` bar:

- No implementation file was pushed from under 1,000 lines to over 1,000 lines
  after the follow-up decomposition.
- The central relay classifier deletes scattered source checks instead of
  adding route-local policy branches.
- Store cleanup and query gates live in the state-store boundary, not in Swift
  UI filtering.
- Swift has one card-display policy and one Thread Detail rejection-message
  policy instead of spreading special cases through views.
- No fallback path, compatibility shim, or caller-supplied source broadening can
  re-admit non-human rows to normal app-facing surfaces.
- No obvious code-judo simplification remains that would delete a meaningful
  layer or condition family without weakening the explicit human-only boundary.

## Handoff

Code-complete handoff is to `$arch-docs` for any later evergreen doc
consolidation or stale-plan retirement.
