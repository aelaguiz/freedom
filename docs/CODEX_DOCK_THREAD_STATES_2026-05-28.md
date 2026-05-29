---
title: "Codex Dock - Thread States Audit"
date: 2026-05-28
status: active
owners: [Amir, Codex]
doc_type: reference
---

# Codex Dock Thread States Audit

## Audit Summary

There is no single "thread state" in Codex Dock today. There are several overlapping state systems:

- Codex backend thread status: what the host says the thread is doing.
- Codex active flags: extra signals that explain an active thread.
- Dock row status: the simplified label shown in the thread list.
- Dock tab: the bucket the row appears under.
- Detail live state: whether the open thread view is currently live, stale, reconnecting, or closed.
- Detail screen state: whether the detail view is idle, loading, loaded, or showing an error.
- Host connection state: whether the app is connected to the relay/app-server path.

The main rule for future docs and UI copy: do not say just "state" when precision matters. Say "backend thread status", "Dock row status", "detail live state", or "host connection state".

The most confusing current mismatch is that the Running tab is not the same thing as the Running row status. The Running tab is a human-work bucket and can include rows labeled Needs me, Running, Idle, or Error. The Dock `Idle` control is a visibility toggle layered on top of tab membership: it is off by default, so Idle rows are hidden until enabled.

Also: thread summary text is not a thread state. A row summary should show the latest meaningful thread message or preview when available, not only the original opening message.

## 1. Backend Thread Status

This is the raw thread status reported by Codex. It is the closest thing to the "real" thread state.

| Backend status | Meaning | Usually shown as |
|---|---|---|
| active | The thread is currently doing work or waiting inside an active run. | Needs me or Running |
| idle | The thread is not currently running. | Idle |
| notLoaded | The app knows about the thread, but full status/details are not loaded. | Limited |
| systemError | Codex reported a system-level problem for the thread. | Error |
| unknown | The app received a status it does not understand yet. | Unknown |

## 2. Active Flags

Active flags only matter when the backend status is active. They explain what kind of active state the thread is in.

| Active flag | Meaning | Dock effect |
|---|---|---|
| waitingOnApproval | The thread is blocked until the user approves something. | Needs me |
| waitingOnUserInput | The thread is blocked until the user answers/provides input. | Needs me |
| unknown | Codex sent an active flag the app does not understand yet. | Preserve the signal, but do not invent a fake meaning. |
| none | The thread is active, but not known to be waiting on the user. | Running |

## 3. Dock Row Status

This is the short label shown on a thread row in the Dock. It is a projection of backend status plus active flags.

| Dock row status | User meaning | Comes from |
|---|---|---|
| Needs me | This thread needs the user to unblock it. | active plus waitingOnApproval or waitingOnUserInput |
| Running | This thread is doing work and is not known to be waiting on the user. | active with no user-blocking flag |
| Idle | This thread is quiet right now. | idle |
| Limited | The app only has partial information for this thread. | notLoaded |
| Error | The thread hit a system error. | systemError |
| Unknown | The app got a status it does not understand. | unknown or missing status |

## 4. Dock Tabs

Tabs are buckets. They are not the same thing as row status.

| Dock tab | What belongs there | Important note |
|---|---|---|
| All | All normal visible thread rows. | Mixed statuses; Idle rows are visible only when the Dock `Idle` toggle is enabled. |
| Needs me | Threads that need the user to act. | Rows should normally say Needs me. |
| Running | Human thread rows that are still relevant to active work. | Membership can include Needs me, Running, Idle, and Error rows; Idle rows are visible only when the Dock `Idle` toggle is enabled. |
| Limited | Rows where the app has partial/limited information. | Usually notLoaded-type rows. |
| Agents | Agent-origin rows, separated from normal human thread rows. | This is an origin bucket, not a backend status; Idle rows are visible only when the Dock `Idle` toggle is enabled. |

## 5. Detail Live State

This state belongs to an open thread detail view. It answers: "Is this screen currently receiving live updates?"

| Detail live state | Meaning |
|---|---|
| Connecting | The detail view is opening or trying to attach to live updates. |
| Reconnecting | The detail view lost the live path and is trying again. |
| Live | The detail view is attached and receiving current updates. |
| Stale | The last loaded content is still visible, but the live path is not healthy. |
| Closed | The live detail stream was closed. |

## 6. Detail Screen State

This state belongs to the detail screen data load. It is separate from the thread's backend status.

| Detail screen state | Meaning |
|---|---|
| Idle | The detail screen is not currently loading anything. |
| Loading | The detail screen is fetching thread data. |
| Loaded | Thread detail data is available on screen. |
| Error | The detail screen could not load or refresh the thread data. |

## 7. Host Connection State

This state belongs to the app's connection to the local relay/app-server path. It can affect many threads at once.

| Host connection state | Meaning |
|---|---|
| Idle | No active connection attempt is in progress. |
| Connecting | The app is trying to connect. |
| Connected | The app is connected. |
| Reconnecting | The app lost the connection and is trying to recover. |
| Offline | The app currently cannot reach the host path. |
| Error | The connection hit an error that should be surfaced. |
| Closed | The connection was closed. |

## 8. Things That Are Often Confused With Thread State

These are real product concepts, but they are not backend thread statuses.

| Concept | What it actually is |
|---|---|
| Archived | A storage/listing bucket. A thread can be archived without changing its backend status vocabulary. |
| Agent | A thread/source origin bucket. It is not a status. |
| Offline | Usually a host connection condition. It does not mean every thread changed backend status. |
| Reconnecting | Usually a host/detail live condition. It is not a backend thread status. |
| Stale | A screen freshness condition. The visible thread data may be old. |
| Starting voice | A composer voice-control phase, not a thread state. |
| Streaming voice | A composer voice-control phase, not a thread state. |
| Finalizing voice | A composer voice-control phase, not a thread state. |
| Request pending/submitted/failed/resolved | A request-card state inside a thread, not the whole thread's status. |
| Original message | Content. It should not be used as a proxy for current thread state. |
| Latest message/preview | Content. It helps the user understand the current thread, but it is still not a state. |

## 9. Naming Rule For Plans And UI

Use these names when writing future docs, tickets, or UI notes:

| Say this | When you mean |
|---|---|
| Backend thread status | active, idle, notLoaded, systemError, unknown |
| Active flag | waitingOnApproval, waitingOnUserInput, unknown, none |
| Dock row status | Needs me, Running, Idle, Limited, Error, Unknown |
| Dock tab | All, Needs me, Running, Limited, Agents |
| Detail live state | Connecting, Reconnecting, Live, Stale, Closed |
| Detail screen state | Idle, Loading, Loaded, Error |
| Host connection state | Idle, Connecting, Connected, Reconnecting, Offline, Error, Closed |

If a plan says "thread state", it should immediately clarify which one of these it means.
