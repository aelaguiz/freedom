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

## Findings

### Finding 1 - Target thread has more than the default message filter should show

Status: investigating

Relay truth for `019e82d8-0527-7fa2-a622-6383e3487f3c` returned:

- 13 turns from `thread/turns/list`
- 117 approximate renderable events
- 75 expected rows under the default Thread Detail `Messages` filter
- 117 expected rows under the `All` filter

The large difference is expected by current product semantics: `Messages`
shows user messages, agent messages, and request rows; it intentionally hides
thinking/reasoning/tooling rows. The next proof step is to open this exact
thread in the `iPhone 17` simulator and confirm whether:

- `Messages` shows the expected message/request subset.
- `All` shows the additional non-message rows.
- Both views continue updating while the real thread changes.

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

So the target thread still needs an explicit simulator open/filter pass.
