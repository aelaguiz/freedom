# Codex Dock Thread Detail Message Flow - Worklog

Date: 2026-05-29
Plan: `docs/CODEX_DOCK_THREAD_DETAIL_MESSAGE_FLOW_GOALS_2026-05-29.md`

## Summary

Implemented the full-thread detail flow: the detail store now pages all `thread/turns/list` results, the visible detail order is newest-first, the old Messages/Thinking/Everything mode cycle is gone, and request actions render inside the shared message card instead of a separate visible request-card stack.

## Implementation Notes

- Replaced capped `CompactThreadRead` behavior with full paged reads in `ThreadDetailStore`.
- Kept the safe transport shape: `thread/read includeTurns:false`, `thread/turns/list` pages, `thread/resume excludeTurns:true`.
- Added repeated-cursor detection so full-thread paging fails loudly instead of looping forever.
- Replaced `ThreadEventVisibilityMode` with `ThreadDetailMessageFilter`.
- Replaced `ThreadEventDisplayOrder.naturalFlow(_:)` with row-based `ThreadEventDisplayOrder.newestFirst(_:)`.
- Removed `CodexDock/Features/Session/RequestCardView.swift`; `SessionDetailView` now owns the single visible card/control family.
- Split the new filter/list/card controls into `CodexDock/Features/Session/ThreadMessageListView.swift` so `SessionDetailView.swift` stays focused on screen lifecycle and top-level layout.
- Regenerated `CodexDock.xcodeproj` through Makefile-owned app/test targets so the deleted source file is removed from the generated project.
- Updated README detail/reconnect docs and marked the previous visibility-mode plan as superseded.

## Verification

Passed:

- `rtk swift test --filter ThreadEventNormalizerTests`: 11 tests, 0 failures after final component split.
- `rtk swift test --filter ThreadDetailStoreTests`: 52 selected tests, 0 failures after final component split.
- `rtk swift test --filter AppServerClientTests`: 48 tests, 5 skipped, 0 failures after final component split.
- `rtk node --test --test-name-pattern 'thread/turns/list routes|thread/resume forwards|turn/start rejects|thread/resume refuses|phone responses are rejected after their upstream request is made stale by a newer resume' scripts/dock-relay-phase5.test.mjs`: 5 tests, 0 failures.
- `rtk node --test scripts/dock-relay.test.mjs scripts/dock-relay-realtime-transcription.test.mjs`: 29 tests, 0 failures.
- `rtk make app SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`: passed on the booted iPhone 17 simulator. Latest launch log: `.codex-dock/logs/app-sim-install-20260529114117.log`, `com.aelaguiz.CodexDockApp: 43750`.
- `rtk make sim-config-verify SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`: passed.
- `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`: passed on rerun and passed again after the final component split. Latest test log: `.codex-dock/logs/app-test-20260529114126.log`.

Important simulator note:

- `rtk make app SIM='iPhone 17'` failed because the name matched two simulators:
  - `feat_anim_1 - iPhone 17` / `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` / Booted
  - `feat_remount-disposal-lifecycle-post-audit - iPhone 17` / `DEF1631B-7125-43C6-BFA3-4423BF103C91` / Shutdown
- The booted simulator ID was used for the passing app/app-test checks.

Important app-test note:

- The first `rtk make app-test SIM='BAD95C8E-3E57-4818-9B90-E4ED22593B4B'` run failed `AppServerClientTests.testRelayRealtimeTranscriptionClientFallsBackAcrossRelayEndpoints()`.
- The targeted diagnostic command passed:
  `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath .codex-dock/DerivedData -only-testing:CodexDockTests/AppServerClientTests/testRelayRealtimeTranscriptionClientFallsBackAcrossRelayEndpoints CURRENT_PROJECT_VERSION=20260529113407`
- The Makefile-owned `rtk make app-test` target passed on the next run.

## Open Verification Blocker

`rtk npm run test:relay` repeated a no-output stall in `scripts/dock-relay-phase5.test.mjs`.

- First run: no output for about two minutes; active test PIDs were terminated with `rtk kill -TERM 94549 94608 94610 94546`.
- Second run: still silent after diagnostic wait; only `scripts/dock-relay-phase5.test.mjs` was active. Node report `report.20260529.063654.23402.0.001.json` showed an idle worker with referenced TCP handles. Follow-up `lsof` showed other live Codex app-server processes listening on `127.0.0.1:61116`, `127.0.0.1:49904`, `127.0.0.1:59557`, and `127.0.0.1:56199`; those were not killed because they are outside this task's test process tree. The report was moved to `/tmp/codex-client/20260529T113654Z/report.20260529.063654.23402.0.001.json`.
- Second run terminated only test PIDs with `rtk kill -TERM 23296 23355 23402 23293`.
- App-server and Dock relay services were not stopped or restarted.

## Review Results

- `$arch-step audit-implementation`: `Verdict (code): COMPLETE`; no code blockers or reopened phases.
- `$plan-audit` implementation check: `approve-with-notes`; no blocking findings. The only note is the full relay-suite environment blocker.
- `$thermo-nuclear-code-quality-review`: no blocking structural findings. The pre-review cleanup split the new filter/list/card controls into `ThreadMessageListView.swift`, leaving `SessionDetailView.swift` at 237 lines and `ThreadMessageListView.swift` at 367 lines; no changed file crosses the 1k-line threshold or preserves the old parallel UI mode/card paths.
