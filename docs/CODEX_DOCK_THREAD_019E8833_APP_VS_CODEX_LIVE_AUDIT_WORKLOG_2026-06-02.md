# Codex Dock Thread 019e8833 App vs Codex Live Audit Worklog

Date: 2026-06-02

Status: audit only. No product code was changed for this worklog.

Target thread:

```text
019e8833-0309-7b51-bd7b-05e2768e6533
```

## Related Documents

- `docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md`
  is the current architecture plan for eliminating display identity drift as a
  bug class.
- `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`
  is the duplicate outbound-message bug doc cross-linked by that plan.
- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
  is the canonical client live-update, projection-runtime, freshness, and proof
  reference. Section `0.7 Canonical Client Projection Runtime Architecture`
  folds this worklog's stuck Thread Detail evidence into the permanent plan.
- `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`
  records the broader protocol/update history.

## User Ask

Audit what the app shows for thread
`019e8833-0309-7b51-bd7b-05e2768e6533` versus what is actually happening in
Codex. Do not fix anything.

The audit was later sharpened to require an over-time comparison, not one static
snapshot. User also reported a physical phone crash after watching the thread
for roughly three minutes. Physical-device crash investigation was not performed
in this pass because the user separately instructed not to talk to the unplugged
physical iPhone 17 Pro path.

## Short Answer

The white Codex CLI updates in the user's screenshot are messages. They are
raw Codex `agentMessage` items and relay `message` rows, so they should appear
in Thread Detail when the `Messages` filter is selected. The gray italic
reasoning/status text is a different class of CLI-visible activity and is not
the same display expectation.

The current "new messages are not showing" symptom is now root-caused to the
client Thread Detail refresh path. The relay had the newer rows and answered
`thread/detail/resync`, but the open simulator detail view started a refresh at
`2026-06-02 11:49:31.787` and never logged `refresh finished` or
`refresh failed`. After that, the app kept noticing dock row advances, but it
could not start another detail refresh because `recoveryTask` stayed non-nil.

There is also a separate relay projection ordering bug for in-progress turns:

```text
raw Codex emits completedAt: null for in-progress turns
relay timestamp parsing treats null as numeric 0
0 wins over startedAt
active rows get eventTime/activityTime null
active rows get the fallback max displayOrderKey
the Swift client trusts displayOrderKey exactly
```

That ordering bug explains why active rows can appear in a confusing order. It
does not explain the later "no new messages are appearing" state by itself. The
missing-new-messages state is best explained by the client refresh/replay wedge
below.

Correction after review: this audit was run on `Amir-M5`. The `local`
`127.0.0.1:4510` relay sample and the `amir-m5.fairy-salmon.ts.net:4510` relay
sample were two network routes to the same host. They are useful for proving
the simulator was seeing the source host, but they are not independent
cross-host evidence.

The confusing part is real:

1. The Dock card title is the long initial goal text, not a current-work summary.
2. The Thread Detail screen is on the `Messages` filter, so it hides the newest
   command/output rows even when those are the most recent actual activity.
3. The raw app-server `thread/read.updatedAt` is stale at the thread creation
   timestamp, while relay projection and raw `thread/turns/list` prove live
   activity.
4. The target parent thread has many subagent children and concurrent active
   turns, so "what is happening" is split across parent turns, child threads,
   command output, file-change rows, and agent messages.
5. The open detail screen can wedge its refresh replay under sustained live
   updates, which makes the screen stop applying new relay data even though the
   relay and raw Codex still have it.
6. The `home.fairy-salmon.ts.net:4510` result is not a root-cause finding for
   this thread. It only confirms that this specific thread is an `Amir-M5`
   thread.

Net: the app can fail in two different ways here. First, active-turn ordering is
wrong because relay projection loses timestamps for in-progress turns. Second,
and more importantly for the screenshot/current complaint, the Thread Detail
client can enter a refresh state that never completes, so later real messages
never reach the visible screen.

## 2026-06-02 Stuck Refresh Proof

Simulator app log:

```text
/tmp/codex-client/thread-019e8833-log-20260602T175910Z/threaddetail.log
```

The last successful Thread Detail refresh for the target thread finished at:

```text
2026-06-02 11:49:30.901 ... thread detail dock row refresh finished ... events=2780
```

The next refresh started at:

```text
2026-06-02 11:49:31.787 ... thread detail dock row refresh started ...
```

There is no later `thread detail dock row refresh finished` or
`thread detail dock row refresh failed` for this open detail view through at
least:

```text
2026-06-02 12:59:02
```

After `11:49:31.787`, the same log still contains repeated:

```text
thread detail dock row advanced
thread detail dock row settle refresh queued
```

That means the client was not blind to relay/dock activity. It saw activity,
queued more work, and then could not complete the already-running detail
refresh.

## Relay Was Not Stuck

Relay log evidence shows the matching `thread/detail/resync` request succeeded:

```text
.codex-dock/logs/dock-relay.err.log
2026-06-02T16:49:32.158Z ... downstream.request_succeeded ... method=thread/detail/resync ... id=443 ... durationMs=322
```

Central time conversion:

```text
2026-06-02T16:49:32.158Z == 2026-06-02 11:49:32.158 America/Chicago
```

That is the same refresh window as the simulator-side stuck refresh start at
`2026-06-02 11:49:31.787`. So the relay answered quickly. The failure is on the
client side after the refresh request begins, not a relay outage or a missing
relay response.

## Client Replay Root Cause

The wedged path is in:

```text
CodexDock/State/ThreadDetailLiveEventBuffer.swift
CodexDock/State/ThreadDetailStore.swift
```

Relevant code:

```text
CodexDock/State/ThreadDetailLiveEventBuffer.swift:15 begin()
CodexDock/State/ThreadDetailLiveEventBuffer.swift:27 append(notification:)
CodexDock/State/ThreadDetailLiveEventBuffer.swift:31 takeBatch()
CodexDock/State/ThreadDetailLiveEventBuffer.swift:40 finishReplay()
CodexDock/State/ThreadDetailStore.swift:663 startDockRowRefreshIfNeeded(reason:)
CodexDock/State/ThreadDetailStore.swift:688 rehydrateAfterDockRowAdvance(reason:)
CodexDock/State/ThreadDetailStore.swift:697 replayBufferedLiveEvents()
CodexDock/State/ThreadDetailStore.swift:706 recoveryTask cleanup
CodexDock/State/ThreadDetailStore.swift:742 replayBufferedLiveEvents()
CodexDock/State/ThreadDetailStore.swift:754 handle(notification:)
```

Plain-English flow:

1. A dock-row advance starts canonical detail recovery.
2. `liveEventBuffer.begin()` turns buffering on.
3. The store awaits `session.threadDetailResync(...)`.
4. The store replaces local detail events with the canonical snapshot.
5. The store calls `replayBufferedLiveEvents()`.
6. Replay loops through `takeBatch()` until the buffer is empty.
7. `finishReplay()` only runs after that loop finishes.
8. `recoveryTask` only clears after replay finishes.

The dangerous part is that replay awaits `apply(notification:)` for each
buffered event. Because `ThreadDetailStore` is an actor, those awaits allow new
live notifications to enter the actor while replay is still running. Since
`isBuffering` remains true until `finishReplay()`, those new notifications are
appended into the same buffer being drained.

In a busy live thread, this can keep replenishing the buffer faster than replay
drains it. Then `takeBatch()` may never return nil, `finishReplay()` never runs,
the `refresh finished` log never appears, and `recoveryTask` never clears. That
matches the observed log exactly.

## Why Tests Missed It

Existing `ThreadDetailStoreTests` prove useful static and single-race behavior,
but they do not model this live traffic pattern.

Relevant tests:

```text
CodexDockTests/ThreadDetailStoreTests.swift:46 testDockRowAdvanceRehydratesOpenThreadFromCanonicalHistory
CodexDockTests/ThreadDetailStoreTests.swift:111 testDockRowAdvanceSchedulesSettledCanonicalHistoryRefresh
CodexDockTests/ThreadDetailStoreTests.swift:177 testDockRowAdvanceDoesNotDropLiveAheadEventBeforeCanonicalHistorySettles
```

The live-ahead test emits one buffered live event before canonical history
settles. It does not simulate sustained notifications arriving while
`replayBufferedLiveEvents()` is awaiting and draining batches.

Missing coverage:

1. No test proves `recoveryTask` clears under continuous live notifications.
2. No test proves replay has a bounded epoch or generation cutoff.
3. No test drives a long-running, busy, in-progress thread with repeated relay
   updates.
4. No end-to-end simulator proof compares visible Thread Detail output against
   raw Codex/relay truth over time.

That is why this bug looked fine in tests but failed in the real Codex CLI
workflow: the app is mostly about live updates, while the relevant tests still
lean too heavily on small, finite update sequences.

## Evidence Artifacts

Scratch artifacts:

```text
/tmp/codex-client/thread-019e8833-audit-20260602T161411Z
/tmp/codex-client/thread-019e8833-audit-20260602T162132Z
/tmp/codex-client/thread-019e8833-ui-watch-20260602T161534Z
/tmp/codex-client/thread-019e8833-detail-dump-20260602T162004Z
```

Important files:

```text
/tmp/codex-client/thread-019e8833-audit-20260602T161411Z/summary.json
/tmp/codex-client/thread-019e8833-audit-20260602T161411Z/local-thread-detail-read.raw.json
/tmp/codex-client/thread-019e8833-audit-20260602T161411Z/raw-thread-read.raw.json
/tmp/codex-client/thread-019e8833-audit-20260602T161411Z/raw-thread-turns-list.raw.json
/tmp/codex-client/thread-019e8833-audit-20260602T162132Z/summary.json
/tmp/codex-client/thread-019e8833-audit-20260602T162132Z/local-thread-detail-read.raw.json
/tmp/codex-client/thread-019e8833-audit-20260602T162132Z/raw-thread-read.raw.json
/tmp/codex-client/thread-019e8833-audit-20260602T162132Z/raw-thread-turns-list.raw.json
```

## Thread Identity

Local Codex state identifies the thread as:

```text
id: 019e8833-0309-7b51-bd7b-05e2768e6533
rollout: /Users/aelaguiz/.codex/sessions/2026/06/02/rollout-2026-06-02T06-58-25-019e8833-0309-7b51-bd7b-05e2768e6533.jsonl
cwd: /Users/aelaguiz/workspace/feat/gw-controls-scene-refactor
repo: git@github.com:funcountry/psmobile.git
branch: feat/redo_scene_arch
commit: 93646ad8bcde7bc5b0d6987e0daaf3034640a4a7
model: gpt-5.5
reasoning_effort: xhigh
source: cli
thread_source: user
```

The raw thread preview begins with:

```text
Implement `docs/APP/REF/PERSPECTIVE_SCENE_ZERO_SUNK_COST_IMPLEMENTATION_PLAN_2026-06-01.md` with `$arch-step auto-implement`.
```

The first user message later in the thread begins:

```text
Just as an FYI, it's probably worth looking at the iPhone 16 SIM...
```

This explains why the Dock card can look disconnected from current work: the
visible card title is rooted in the original long goal text, not the latest live
activity.

## Subagent Shape

`thread_spawn_edges` records 13 child threads for the parent:

```text
019e886a-5acd-7990-8195-ac07aabf9921 Lovelace  worker
019e886a-8f82-7091-adf3-602903ed425f Dalton    explorer
019e8878-3032-7710-9799-7519cef26da1 Popper    worker
019e8886-06d1-7ba3-820f-6fe4ee9a102e Tesla     worker
019e8886-3f14-7170-954d-95c6d5751f8f Averroes  worker
019e8892-0078-76d3-bf6e-d4f58c90fcaf Plato     worker
019e8892-33ff-7370-9d2c-f6b88b6bfc4f Lagrange  worker
019e8897-4d0b-7d52-9054-ca15e08a1dda Planck    worker
019e8897-8913-71e0-95df-fe9916129025 Nash      worker
019e88ae-5d05-74d1-b4cb-0caff8a338e0 Faraday   worker
019e88ae-5f84-70e0-8ca3-10fcd9c7756c Franklin  worker
019e88b4-314d-70e0-a4f3-9fad86b128ac Rawls     worker
019e88ca-5643-7c23-94c0-df5f313f668c Ramanujan explorer
```

All 13 children use the same `cwd`:

```text
/Users/aelaguiz/workspace/feat/gw-controls-scene-refactor
```

This matters because the parent thread is not a simple one-agent chat. The
actual work is a parent orchestration thread with child-agent work, plan edits,
tests, command output, file changes, and context compactions.

## Raw Codex Truth

The raw app-server `thread/read` result is misleading for activity:

```text
thread.createdAt: 1780401505
thread.updatedAt: 1780401505
status: active
```

That `updatedAt` stayed equal to the creation timestamp even while live turns
and relay rows were changing.

Raw `thread/turns/list` is the better raw evidence for activity:

First sample:

```text
collectedAt: 2026-06-02T16:14:19.515Z
turnCount: 12
latest listed turn: ebcc7e4a-0efe-4467-870f-9b6a3577d3d6
latest listed turn status: inProgress
latest listed turn itemCount: 69
```

Second sample:

```text
collectedAt: 2026-06-02T16:22:20.038Z
turnCount: 13
latest listed turn: ebcc7e4a-0efe-4467-870f-9b6a3577d3d6
latest listed turn status: inProgress
latest listed turn itemCount: 160
new listed turn: 711c1907-dcbc-4268-b524-ac9c8aa06d96
new listed turn status: inProgress
```

There were concurrent in-progress turns. In the second sample:

```text
ebcc7e4a-0efe-4467-870f-9b6a3577d3d6 startedAt 1780416515 inProgress
711c1907-dcbc-4268-b524-ac9c8aa06d96 startedAt 1780417170 inProgress
aba16964-2aaa-46de-90b3-879fbafcd2d0 startedAt 1780416599 completedAt 1780417170
```

This is another reason the thread can feel hard to read. "Most recent" is not
just one serialized message stream; raw Codex can expose overlapping active
turn state.

## Relay Projection Truth

Important limitation: this audit ran on `Amir-M5`. The `local` and `Amir-M5`
Tailscale samples below are the same source machine reached through different
addresses. They prove the source-host path was live; they do not prove anything
about a separate host independently having the same state.

Local relay, first sample:

```text
host: local ws://127.0.0.1:4510
dock target index: 1
dock target status: running
dock target updatedAt: 2026-06-02T16:14:02.000Z
thread/detail/read rows: 1611
thread/detail/resync rows: 1611
```

Amir-M5 Tailscale relay, first sample:

```text
host: amir-m5.fairy-salmon.ts.net:4510
dock target index: 1
dock target status: running
dock target updatedAt: 2026-06-02T16:14:02.000Z
thread/detail/read rows: 1611
thread/detail/resync rows: 1613
```

Local relay, second sample:

```text
host: local ws://127.0.0.1:4510
dock target index: 0
dock target status: running
dock target updatedAt: 2026-06-02T16:22:00.000Z
thread/detail/read rows: 1862
thread/detail/resync rows: 1864
```

Amir-M5 Tailscale relay, second sample:

```text
host: amir-m5.fairy-salmon.ts.net:4510
dock target index: 0
dock target status: running
dock target updatedAt: 2026-06-02T16:22:00.000Z
thread/detail/read rows: 1864
thread/detail/resync rows: 1864
```

The row count and timestamp movement prove that the relay path was live during
this audit.

Home relay did not have the target loaded in either sample:

```text
host: home.fairy-salmon.ts.net:4510
dock target index: -1
thread/detail/read: thread/read: thread not loaded: 019e8833-0309-7b51-bd7b-05e2768e6533
thread/detail/subscribe: thread/read: thread not loaded: 019e8833-0309-7b51-bd7b-05e2768e6533
thread/detail/resync: thread/read: thread not loaded: 019e8833-0309-7b51-bd7b-05e2768e6533
```

This is not evidence of the primary bug. It only means `home` did not have this
particular `Amir-M5` thread loaded.

## Projection Row Shape

First detail sample:

```text
activeTurnID: ebcc7e4a-0efe-4467-870f-9b6a3577d3d6
rowCount: 1611
commandOutput rows: 44
command rows: 47
agentMessage rows: 881
fileChange rows: 222
reasoning rows: 371
unknown rows: 17
toolCall rows: 22
userMessage rows: 7
```

Second detail sample:

```text
activeTurnID: ebcc7e4a-0efe-4467-870f-9b6a3577d3d6
rowCount: 1862
commandOutput rows: 101
command rows: 106
agentMessage rows: 975
fileChange rows: 243
reasoning rows: 391
unknown rows: 17
toolCall rows: 22
userMessage rows: 7
```

The newest projection rows in both samples were tooling rows:

```text
rowRole: commandOutput
visibility: tooling
renderKind: output
itemType: commandExecution
```

The Thread Detail simulator was visibly set to:

```text
message filter: Messages
message filter value: messages
```

That means the screen is not showing the newest activity rows when the newest
activity rows are command/output rows. It is showing the newest message rows.

## Follow-up Exact Screenshot Trace

After the user showed the Codex CLI screenshot, the audit traced exact visible
phrases instead of relying on row-category assumptions.

Probe time:

```text
2026-06-02T17:45:38.845Z
```

Raw Codex `thread/turns/list` reported:

```text
turnCount: 24
latest in-progress turn: fdc69209-12fd-40fb-92b8-1959a61ba70f
second in-progress turn: db02f45a-87ba-43ae-aa01-8b1af30084e0
```

The screenshot phrase:

```text
Current plan truth says Phase 3 through Phase 5
```

was found in raw Codex as:

```text
turnID: db02f45a-87ba-43ae-aa01-8b1af30084e0
turnStatus: inProgress
turnStartedAt: 1780421857
itemIndex: 6
itemID: item-2035
itemType: agentMessage
```

The same phrase was found in relay `thread/detail/read` as:

```text
index: 144-176 during observed probes
projectionID: host:Amir-M5/thread:019e8833-0309-7b51-bd7b-05e2768e6533/turn:db02f45a-87ba-43ae-aa01-8b1af30084e0/item:item-2035/row:agentMessage
rowRole: agentMessage
visibility: message
renderKind: agentMessage
eventTime: null
activityTime: null
displayOrderKey: 10000000000000000|0000000001|9999999993|9999999999|...
```

Another exact screenshot phrase:

```text
exact repo-local gate command still fails
```

was found in raw Codex as `itemType: agentMessage` and in relay as
`rowRole: agentMessage`, `visibility: message`, `renderKind: agentMessage`.

The simulator-visible messages at that moment were also real messages, but from
a different completed turn:

```text
turnID: 39e08caa-56df-4ab7-b597-bccdf11747a1
phrases:
- previous test process is no longer attached
- production `PerspectiveTablePublishedGeometry` lane
- Controller test is running; still no failure output
```

Conclusion: the user was right that the screenshot replies should be messages.
They are messages. The app/relay path was not dropping them as tooling. The
later root cause is that the relay had the message rows, but the client detail
refresh/replay path got wedged and stopped applying newer rows to the open
screen. A separate active-turn ordering bug also means the top of the app can
show a different turn than the Codex pane the user is watching.

## Confirmed Timestamp Bug

The relay projector parses timestamps in
`scripts/dock-relay-thread-detail-projection-adapter.mjs`.

The bug starts here:

```text
scripts/dock-relay-thread-detail-projection-adapter.mjs:53
numberValue(null) returns 0 because Number(null) is 0
```

Then in-progress turns hit this path:

```text
scripts/dock-relay-thread-detail-projection-adapter.mjs:548-555
turnCompletedAtMs checks turn.completedAt
raw Codex sends completedAt: null
turnCompletedAtMs becomes 0
```

Then `itemActivityMs` treats `0` as present:

```text
scripts/dock-relay-thread-detail-projection-adapter.mjs:153-168
agentMessage uses turnCompletedAtMs ?? turnStartedAtMs ?? defaultMs
0 wins over the real turnStartedAtMs
```

The local reproduction with raw Codex turn data produced:

```text
turn.startedAt: 1780422101
turn.completedAt: null
turnStartedAtMs: 1780422101000
turnCompletedAtMs: 0
activity: 0
displayOrderKey head: 10000000000000000
```

`scripts/dock-relay-projection-engine.mjs:21` also uses
`MAX_SORT_MS = 9_999_999_999_999_999`, which is above JavaScript's safe integer
range. JavaScript rounds it to `10000000000000000`, which explains the exact
fallback key prefix seen in relay output.

The Swift client is not recovering from this because it is deliberately
contract-driven:

```text
CodexDock/Models/ThreadEvent.swift:233-248
Thread Detail rows are ordered by relay displayOrderKey, then projectionID.
The client intentionally does not rebuild order from local timestamps.
```

That client behavior is architecturally correct if the relay contract is
correct. Here the relay contract output is wrong for in-progress turns.

## Earlier Simulator Evidence

The app was running on the `iPhone 17` simulator:

```text
simulator id: DEF1631B-7125-43C6-BFA3-4423BF103C91
simulator name: feat_remount-disposal-lifecycle-post-audit - iPhone 17
```

No physical iPhone commands were run in this pass.

Dock screen evidence before opening the thread:

```text
global connectivity: Online 2/2
target row identifier: codexdock.dock.row.Amir-M5.019e8833-0309-7b51-bd7b-05e2768e6533
target row status: running
target row relationship: root
target row host: Amir-M5
target row sourceHost: Amir-M5
target row repo/branch: psmobile / feat/redo_scene_arch
target row label: Pinned
```

Thread Detail header after opening:

```text
screen: Thread
host: Amir-M5
host endpoint value: amir-m5.fairy-salmon.ts.net:4510
live indicator: Live
status: Running
thread id line: 019e8833-0309-7b51-bd7b-05e2768e6533 · now
message filter: Messages
composer: visible
```

First observed Thread Detail top visible message:

```text
The clean fix is to make any full-table paint readiness request with stagePresentation require preparedRuntimeScene...
```

Second observed top visible message after waiting:

```text
I need to update direct controller harnesses to pass the legacy spec explicitly...
```

Third observed top visible message after more waiting:

```text
Format is clean and the controller scan has zero perspectiveSceneSpecProvider(...) / PerspectiveSceneSpecRequest hits...
```

That over-time movement only confirms that the visible simulator Thread Detail
had received newer message rows during an earlier, narrower observation window.
It is superseded by the later app-log proof that a subsequent open detail
refresh started at `2026-06-02 11:49:31.787` and never finished. Do not treat
this section as proof that the final observed detail state was healthy.

## Canonical UI Dump Harness Result

Attempted command:

```bash
SIM_UI_DUMP_DIR=/tmp/codex-client/thread-019e8833-detail-dump-20260602T162004Z EXPECTED_SCREEN=thread EXPECTED_THREAD_ID=019e8833-0309-7b51-bd7b-05e2768e6533 rtk make sim-ui-dump SIM='iPhone 17'
```

Result:

```text
make: *** [sim-ui-dump] Terminated: 15
sim UI dump failed; see /Users/aelaguiz/workspace/codex-client/.codex-dock/logs/sim-ui-dump-test-20260602162011.log
BUILD INTERRUPTED
```

The process was stopped after it sat inside `xcodebuild test-without-building`
without producing a dump artifact. This is a proof-harness problem, not direct
evidence that the app screen was stuck. The Mobile MCP accessibility element
dump did produce useful on-screen text evidence.

## Findings

### Finding 1: The screenshot replies are messages.

The exact Codex screenshot replies were found as raw `agentMessage` items and
relay `visibility: message` rows. They were not merely hidden command/tooling
output.

Conclusion: those white Codex CLI updates should appear in Thread Detail when
the `Messages` filter is selected.

### Finding 2: The current missing-new-messages symptom is client-side.

The simulator app log shows a Thread Detail refresh started at
`2026-06-02 11:49:31.787` and then never logged `refresh finished` or
`refresh failed`. Later log lines show dock-row advances were still observed.

Conclusion: the client saw new activity, but the open detail screen got stuck
inside refresh/replay and stopped applying it.

### Finding 3: The relay had the data and answered the matching resync.

The relay log shows `thread/detail/resync` request `id=443` succeeded at
`2026-06-02T16:49:32.158Z` with `durationMs=322`.

Conclusion: this specific stuck refresh was not caused by the relay failing to
answer. The failure is after the client starts handling the refresh response.

### Finding 4: Active-turn ordering is separately broken.

Active turns with `completedAt: null` are projected with `activityTime: null`
and fallback max `displayOrderKey` values. The client then renders those bad
relay order keys exactly.

Conclusion: even when the refresh path is not wedged, the app can still put the
wrong active-turn row at the top.

### Finding 5: "Messages" can hide newest non-message activity, but that is not this whole bug.

The most recent projection rows in earlier samples were command/output tooling
rows, while the visible simulator screen was on the `Messages` filter.

Conclusion: the `Messages` filter can make the screen look less current, but it
does not explain white `agentMessage` rows failing to appear. The refresh wedge
does.

### Finding 6: Raw `thread/read.updatedAt` is not trustworthy activity truth.

Raw `thread/read.updatedAt` stayed equal to `createdAt` while raw turns and
relay projection rows changed.

Conclusion: any client, test, proof, or diagnostic that uses raw
`thread/read.updatedAt` as current activity truth can lie.

### Finding 7: The Dock card title is not activity-first.

The Dock card title is the long initial goal text. It did not tell the user what
the currently active implementation slice was.

Conclusion: even when a row is live and sorted near the top, its textual preview
can feel stale because the title is not a latest-activity summary.

### Finding 8: Parent/child structure is not surfaced clearly enough.

The target thread has 13 subagent child threads. The app header shows one root
thread with host/repo/status, but it does not make the parent/subagent structure
obvious.

Conclusion: part of the "confusing mix" is real information architecture debt.
The app is showing a root thread, but the actual work is distributed across
parent turns and child threads.

### Finding 9: The host evidence was narrower than first framed.

The audit ran on `Amir-M5`. Therefore `local` and `amir-m5.fairy-salmon.ts.net`
were two routes to the same source host, not two independent host observations.

Conclusion: the strong evidence is about the `Amir-M5` source-host path. The
`home` miss should not be treated as important root-cause evidence for this
thread.

### Finding 10: The proof harness still has reliability debt.

`rtk make sim-ui-dump` is the intended canonical "what is on screen" dump path,
but it stalled in this pass. Mobile MCP accessibility dumping worked.

Conclusion: the plan to make simulator visual state dumpable is still
necessary. The intended proof path should be reliable enough that an audit does
not need manual Mobile MCP fallback.

### Finding 11: Physical crash remains unverified.

The user reported a physical phone crash after watching this thread for roughly
three minutes. This audit did not collect physical-device logs or crash reports.

Conclusion: the crash is a separate unresolved fact. It should be investigated
with device logs/crash reports once physical-device access is allowed again.

## Root Cause Framing

This thread exposed both a client live-update bug and a relay ordering bug.

The strongest root-cause framing after the full review is:

```text
The relay had the new message rows and answered detail resync. The Swift Thread
Detail store then entered a refresh/replay path that can keep buffering new live
notifications while replay awaits notification application. Under sustained
traffic, the replay loop may never empty, so finishReplay never runs,
recoveryTask never clears, and later real messages never reach the open screen.
Separately, relay timestamp normalization makes active-turn row ordering wrong
because completedAt: null is treated as timestamp 0.
```

The user-facing failure came from both a live-update correctness bug and
view-contract debt:

- Client detail refresh/replay can wedge under sustained live traffic.
- Once wedged, `recoveryTask` blocks all later canonical detail refreshes.
- Relay active-turn rows had broken activity timestamps.
- Relay active-turn rows therefore had fallback max order keys.
- Swift intentionally trusted relay `displayOrderKey`.
- Multiple in-progress turns were flattened into one list.
- Dock card text is not current-work text.
- Thread Detail default visible filter is not "all latest activity."
- Raw thread metadata is stale.
- Parent/child live work is not explained in the UI.
- The canonical UI dump proof path is not reliable enough.

The audit did not adequately prove the physical-phone path or the reported
physical crash. It also did not provide independent cross-host proof, because
the useful `local` and `Amir-M5` samples were both from `Amir-M5`.

## Architecture Implication

The existing
`docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md` is still the
right architecture direction for identity drift and duplicate rows: one
relay-owned projection identity, one client apply law, and retained relay
witness proof.

This worklog adds one UX/proof requirement to evaluate during implementation:

```text
The projection contract must make "latest visible row" and "latest actual
activity row" explicit, so the app cannot silently present a filtered message
view as if it were the whole live thread.
```

That does not mean adding a new identity path. It means the existing projection
path should expose enough row visibility and activity metadata for the UI and
proof to say exactly what is being shown.

## No Fixes Made

This pass only read local Codex state, relay/raw data, simulator accessibility
state, and existing docs. It did not change product code, relay code, tests, or
runtime services.

Post-review correction: the host framing was tightened because this audit was
run on `Amir-M5`, so `local` and `amir-m5.fairy-salmon.ts.net` were not
independent hosts.
