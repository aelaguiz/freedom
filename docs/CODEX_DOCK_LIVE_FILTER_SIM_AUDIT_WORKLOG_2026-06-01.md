# Codex Dock Live Filter Simulator Audit Worklog

Date: 2026-06-01

## Objective

Prove Dock and Thread Detail filters against real relay-backed Codex data in
the `iPhone 17` simulator, including threads that are actively changing. This
work must compare the simulator's visible accessibility state against live
relay truth, not only static fixtures.

## Current Target Thread

- Thread ID: `019e82d8-0527-7fa2-a622-6383e3487f3c`
- User concern: not everything appears to be coming through in Thread Detail.
- Relay host used for initial truth probe: `ws://127.0.0.1:4510`

## Artifacts

- Initial relay one-shot report:
  `/tmp/codex-client/live-filter-audit-20260601T112909Z/relay-one-shot.json`
- Initial simulator current-screen dump:
  `/tmp/codex-client/sim-ui-dump-20260601T112944Z/sim-ui-dump.json`
- Target thread relay truth:
  `/tmp/codex-client/live-filter-target-019e82d8-20260601T115353Z/relay-truth.json`
- Target thread simulator filter proof:
  `/tmp/codex-client/live-filter-target-019e82d8-20260601T115353Z/live-filter-ui.json`
- Passing iPhone 17 proof result:
  `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.06.01_06-56-03--0500.xcresult`
- Passing iPhone 17 proof log:
  `.codex-dock/logs/app-test-20260601115602.log`

## Findings

### Finding 1 - Target thread has more than the default message filter should show

Status: confirmed; superseded by the newer count in Finding 3

The initial relay truth probe for
`019e82d8-0527-7fa2-a622-6383e3487f3c` returned:

- 13 turns from `thread/turns/list`
- 117 approximate renderable events
- 75 expected rows under the default Thread Detail `Messages` filter
- 117 expected rows under the `All` filter

The thread changed while this audit was running. The later successful simulator
proof in Finding 3 captured 143 renderable events, with 95 under `Messages` and
143 under `All`. The core finding stayed the same: the default `Messages`
filter shows user messages, agent messages, and request rows; it intentionally
hides thinking/reasoning/tooling rows.

### Finding 2 - Current simulator was on a different live thread

Status: confirmed

`rtk make sim-ui-dump SIM='iPhone 17'` showed the simulator was already on a
Thread Detail screen, but for thread
`019e82eb-d194-7003-8bc9-4b1d43d9093c`, not the target thread above. That dump
reported:

- screen: `thread`
- live state: `Live`
- filter: `messages`
- visible/detail message count: 7

This was true for the initial dump. The explicit target-thread simulator pass
is now recorded in Finding 3.

### Finding 3 - Target thread is coming through on the local relay-backed simulator path

Status: confirmed

The successful `iPhone 17` proof opened thread
`019e82d8-0527-7fa2-a622-6383e3487f3c` through only `127.0.0.1:4510`, so the
simulator could not silently fall back to `home`. The app log for the passing
run showed:

- Dock loaded from the local relay with 216 rows.
- Thread Detail loaded the exact target thread from `127.0.0.1:4510`.
- Thread Detail finished live with 143 events in 543 ms.

The relay truth captured just before the passing run said:

- Dock target card found: yes.
- Dock stream freshness: fresh.
- Target card status: `idle`.
- Target card activity: `2026-06-01T11:42:53.000Z`.
- Turn pages: 1.
- Turns: 13.
- Swift-renderable event estimate: 143.
- Default `Messages` filter expected rows: 95.
- `All` filter expected rows: 143.

The simulator accessibility proof matched those counts exactly:

- `Messages`: `events=95; filter=messages`.
- `All`: `events=143; filter=all`.

So for this thread, the currently proven behavior is not relay loss and not a
Thread Detail loading failure. The default `Messages` filter hides the
non-message rows by design. In this captured thread, that means `All` exposes
48 additional rows: 47 thinking rows plus 1 unsupported/unknown row.

### Finding 4 - The old simulator proof path itself had two bad assumptions

Status: confirmed and harness patched

The target-thread proof exposed two problems in the proof harness:

- It only tried to tap a row already visible in the first Dock viewport. That
  is invalid for a real Dock with hundreds of rows. The harness now searches
  the Dock by exact thread ID before opening the row.
- It tried to gather every message card through Accessibility. On real large
  Thread Detail screens, that can hang Xcode's UI test runner. The harness now
  uses the screen's canonical count hook by default:
  `codexdock.session.message-list` exposes `events=<count>; filter=<filter>`.

Those were test-harness bugs, not product behavior changes. The product code
path under proof is still the real Dock search, real Thread Detail open, real
Thread Detail filter control, and real relay-backed data.

### Finding 5 - Current FYI target re-check still matches relay truth

Status: confirmed

At `2026-06-01T12:06:56Z`, I re-ran the exact target-thread proof for:

- Thread ID: `019e82d8-0527-7fa2-a622-6383e3487f3c`
- Relay path: `127.0.0.1:4510`
- Simulator: `iPhone 17`
- UI proof artifact:
  `/tmp/codex-client/live-filter-target-019e82d8-20260601T120640Z/live-filter-ui.json`
- Relay truth artifact:
  `/tmp/codex-client/live-filter-target-019e82d8-20260601T120640Z/relay-truth-over-time.json`
- Compare artifact:
  `/tmp/codex-client/live-filter-target-019e82d8-20260601T120640Z/compare.json`

The relay truth did not move during the 45-second capture:

- `moving=false`
- target card activity: `2026-06-01T11:42:53.000Z`
- `Messages`: `95 -> 95`
- `All`: `143 -> 143`
- `request`: `6 -> 6`
- `unknown`: `1 -> 1`

The simulator proof matched the relay exactly:

- `Messages`: `events=95; filter=messages`
- `All`: `events=143; filter=all`
- comparator result: `status=pass`
- comparison count: `8`
- failures: `[]`

Interpretation: this exact thread is currently coming through from the local
relay into the simulator. If it looks incomplete in the app, the proven reason
for this thread is the selected Thread Detail filter: `Messages` shows 95 rows,
while `All` shows all 143 renderable rows. That is a product clarity problem if
the user expects "everything" by default, but it is not relay data loss in this
capture.

### Finding 6 - A separate moving-thread bug is real: Thread Detail can stay frozen while Dock updates

Status: confirmed, root-cause layer identified

This is separate from the FYI target thread above.

Moving proof target:

- Thread ID: `019e8305-970e-7243-9528-6ae3e9181ecf`
- Relay truth artifact:
  `/tmp/codex-client/live-filter-moving-019e8305-20260601T120244Z/relay-truth-over-time.json`
- Simulator proof artifact:
  `/tmp/codex-client/live-filter-moving-019e8305-20260601T120244Z/live-filter-ui.json`
- Compare artifact:
  `/tmp/codex-client/live-filter-moving-019e8305-20260601T120244Z/compare.json`

The relay truth changed while the simulator had that same thread open:

- Relay `Messages`: `15 -> 19`
- Relay `All`: `24 -> 32`
- Relay `activityAt`: `2026-06-01T12:02:33.000Z -> 2026-06-01T12:03:56.000Z`
- Comparator: `relayMoving=true`

The simulator did not move:

- UI `Messages`: stayed `15`
- UI `All`: stayed `25`
- Comparator: `uiMoving=false`
- Comparator result: `status=fail`

The app logs from the same run show why this is possible:

- Thread Detail loaded the target thread at `2026-06-01 07:03:03.192`.
- Thread Detail finished live at `2026-06-01 07:03:13.743` with `events=25`.
- The Dock stream then resynced from relay updates at:
  - `2026-06-01 07:03:37.782`, `seq=5170`, `rows=218`
  - `2026-06-01 07:03:43.230`, `seq=5171`, `rows=218`
  - `2026-06-01 07:03:48.265`, `seq=5173`, `rows=218`
  - `2026-06-01 07:03:58.165`, `seq=5176`, `rows=218`
- There were no `thread notification handled` log lines for that target while
  the relay truth was moving.

Current code path:

- Initial Thread Detail load reads history with `thread/read` plus
  `thread/turns/list` in `CodexDock/State/ThreadDetailStore.swift:563`.
- It then calls `thread/resume` with `excludeTurns: true` in
  `CodexDock/State/ThreadDetailStore.swift:615`.
- Because `excludeTurns` is true, the resume response is deliberately compact;
  the store keeps the historical turns it already read:
  `resumeResponse.thread.replacingTurns(turns)`.
- After that, normal updates only enter Thread Detail through the notification
  or server-request streams in `CodexDock/State/ThreadDetailStore.swift:715`
  and `CodexDock/State/ThreadDetailStore.swift:746`.
- The only automatic full re-read path is reconnect/foreground rehydrate in
  `CodexDock/State/ThreadDetailStore.swift:637`.
- The Dock stream is a separate live path. It can know a row changed and resync
  the card list, but Thread Detail does not currently treat "the open row
  changed in Dock" as a reason to re-read that open thread.

Relay code path:

- The relay forwards `thread/resume` to the raw app-server in
  `scripts/dock-relay.mjs:258`.
- It forwards upstream notifications to the phone if the raw app-server sends
  them in `scripts/dock-relay.mjs:316`.
- It does not currently bridge Dock/history changes into Thread Detail
  notifications or force Thread Detail to rehydrate when the open thread's Dock
  card changes.

Root cause: Thread Detail assumes `thread/resume` notifications are a complete
live source after the initial `thread/turns/list` read. The moving-thread proof
shows that assumption is false for at least one real Codex update path: relay
history and Dock cards moved, but the open Thread Detail notification stream did
not deliver matching item updates. The UI stayed stale while still labeling the
detail session `Live`.

Testing gap:

- `CodexDockTests/ThreadDetailStoreTests.swift:87` and
  `CodexDockTests/ThreadDetailStoreTests.swift:493` prove that Thread Detail
  updates if a fake session explicitly emits notifications.
- `CodexDockTests/ThreadDetailStoreLifecycleTests.swift:263` proves that
  foreground rehydrate re-reads history.
- Those tests do not prove the real relay/Codex behavior where history changes
  but no matching live notification reaches the detail WebSocket.
- The new comparator proof does catch this class of bug because it compares
  simulator-visible count hooks against a parallel relay `thread/turns/list`
  truth stream over time.

Interpretation: this is not a "static snapshot count" problem anymore. We now
have a real moving-thread test that catches the actual user-visible failure:
the Dock says work changed, but the open Thread Detail does not refresh. The
fix should make Thread Detail converge from the same canonical history source
when its open Dock row advances, rather than relying only on raw live
notifications.
