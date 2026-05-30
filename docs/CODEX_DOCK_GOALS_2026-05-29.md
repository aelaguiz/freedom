---
title: "Codex Dock Goals"
date: 2026-05-29
status: active
doc_type: goals
owners: [Amir, Codex]
related:
  - docs/CODEX_DOCK_RELAY_STATE_PARITY_WORKLOG_2026-05-30.md
  - docs/CODEX_DOCK_RELAY_THREAD_FIDELITY_WORKLOG_2026-05-29.md
  - docs/CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md
  - docs/CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md
---

# Codex Dock Goals

## Intent

Codex Dock is a phone-native command center for real Codex work. It should show
what is running, what is waiting, what changed, what is old but still relevant,
what belongs to spawned agents, and what can be safely ignored.

The app should be trustworthy enough to act on. A visible session row should
match the real Codex state closely enough that opening, resuming, archiving,
pinning, filtering, counting, or ignoring it feels safe.

This audit exists to make the app stop being accidentally misleading. The app
must not present stale, archived, dormant, spawned, or user-created sessions as
the wrong kind of work.

## Objectives

- Every underlying Codex thread is represented by the relay on a one-to-one
  basis.
- Every state and every detail that exists in Codex sessions is available
  through the relay, with no missing data.
- Every relay state and detail has an exact known meaning in Codex terms, with
  no guessed definitions.
- The client can trust the relay as the complete source of truth.

## Fundamental Relay Requirements

- The relay knows every real Codex thread that exists.
- The relay represents each Codex thread exactly once.
- The relay knows the true lifecycle state of each thread: active, archived,
  deleted/missing, ephemeral, loaded/live, or stored/not-loaded.
- The relay knows the true origin of each thread: human-created, spawned agent,
  exec, app-server/MCP, internal/system, forked, or truly unknown.
- The relay knows the true mode and start shape when Codex exposes it: normal
  interactive work, JSON/output-schema turns, prompt-started work, promptless
  restored work, or unknown.
- The relay preserves the real relationships between threads, including
  spawned parent/child sessions, forks, and host ownership.
- The relay exposes every state and detail that exists in the underlying Codex
  session, or explicitly marks the gap as unknown.
- The relay defines the meaning of each represented state and detail.
- The relay knows how fresh and complete its view is.
- The relay can explain every inclusion and exclusion.

## Completion Boundary

The relay runtime must use app-server only. The parity audit may read disk and
SQLite only to check whether the app-server-backed relay view matches Codex's
durable state.

For this goal, "complete" means every app-server-exposed state is represented,
ordered, and named by the relay. A fact that Codex stores on disk or in SQLite
but does not expose through app-server is a documented app-server boundary, not
a relay workaround target.

## App-Server-Exposed Completion Requirements

- Every app-server-listable active thread is represented by the relay exactly
  once.
- Normal app-facing relay sessions exclude Codex-archived threads and include
  every active app-server-listable thread.
- `dock/subscribe` preserves Codex app-server order, or labels order movement
  as audit-time freshness movement.
- `dock/subscribe` shows loaded/live sessions as live, not dormant.
- Spawned parent/child relationships match the app-server-listable spawned
  thread rows.
- `thread/turns/list` is exhaustively drained for every app-server-listable
  thread, preserving returned app-server page order.
- Current thread goals returned by `thread/goal/get` match goal rows for
  materialized thread IDs.
- The relay records a deterministic app-server metadata projection and states
  which app-server surface won each field.
- Every known non-exposed Codex fact is explicitly documented as outside current
  app-server support.

## Current Outcome Status

- Proven complete for app-server-exposed relay state: the latest stable live
  exhaustive audit reported
  `completionBoundary.appServerExposedParityComplete` as `true`; every named
  app-server check passed.
- Proven: the relay represented every active app-server-listable Codex thread
  exactly once: 1519 of 1519. SQLite had 1520 active thread rows total; the
  remaining row is outside current app-server list discovery.
- Proven: normal app-facing session rows excluded Codex-archived threads, had
  no duplicate session IDs, had no duplicate thread IDs, and matched 1519 of
  1519 active app-server-listable threads.
- Proven: `dock/subscribe` compared against app-server `active:allSourceKinds`
  order for 1519 threads. It had 0 stable order mismatches; the 5 observed
  order mismatches were explicitly classified as freshness movement during the
  audit.
- Proven: `dock/subscribe` now overlays app-server live status. The latest
  audit compared 11 loaded sessions and found 0 live-status mismatches and 0
  loaded sessions shown as dormant or unknown.
- Proven: spawned parent/child edges matched app-server-listable spawned rows
  exactly: 1192 of 1192.
- Proven: `thread/turns/list` full-item coverage was complete for every
  app-server-listable thread: 5797 turns and 219595 items across 1519 threads,
  with no incomplete threads, duplicate turn IDs, or ordinal mismatches.
- Proven: prompt-shape evidence was counted from full app-server turn items
  without storing prompt text: 1495 threads had at least one `userMessage` item,
  24 had no `userMessage` item, 1419 had `userMessage` in the oldest returned
  turn, and 100 did not.
- Proven: full historical turn items exposed zero top-level output-schema
  fields: 0 threads, 0 turns, and 0 items had `outputSchema`, `output_schema`,
  `finalOutputJsonSchema`, `final_output_json_schema`, `outputSchemaJson`, or
  `output_schema_json`.
- Proven: the relay emits a deterministic canonical app-server projection for
  compared thread metadata. In the latest audit, all 1519 app-server-listable
  threads had a canonical projection, 0 were missing it, and all 22776
  projected fields came from `routed thread/read`. The projection records
  conflicts instead of hiding them: 1747 projected fields had app-server surface
  conflicts.
- Proven: the relay forwards app-server `thread/search` without disk access.
  The latest audit also probed the stable missing SQLite thread through relay
  `thread/search` using safe known terms across both default interactive and
  explicit all-source scopes.
- Proven: the relay forwards app-server `thread/goal/get` without disk access
  and routes it to the owning live app-server when a thread is loaded there.
  The latest audit found 145 current thread goals through app-server with 0
  missing current materialized-thread goals, 0 extra relay goals, and 0 goal
  read errors.
- Outside current app-server enumeration support: one real Codex thread is
  direct-readable by ID but is not discoverable through current app-server
  `thread/list` because its preview is empty. The latest relay-backed
  `thread/search` probes also did not find it, so this remains an app-server
  discovery boundary rather than a relay disk-reading problem.
- Outside current app-server goal identity support: app-server goal state is
  exposed by thread ID and does not expose SQLite `goal_id`.
- Outside current app-server goal enumeration support: orphan goal rows exist
  in SQLite but are not exposed through a standalone app-server goal list. In
  the latest audit, app-server exposed 145 current thread goals, while SQLite
  had 168 goal rows, including 23 rows whose thread IDs were absent from
  `state_5.sqlite.threads`.
- Outside current app-server atomic snapshot support: four goal rows changed
  during the latest exhaustive audit, and app-server responses do not include a
  shared snapshot/revision ID across `thread/list`, `thread/read`,
  `thread/turns/list`, and `thread/goal/get`.
- Codex storage meaning boundary: some SQLite metadata still differs from
  rollout `session_meta` or app-server read rows. The latest audit counted 177
  storage disagreements and 21 read-detail disagreements. The relay has a
  deterministic app-server projection, but Codex has not exposed a single
  storage-truth selector for SQLite-vs-rollout disagreements.
- Outside raw rollout reconstruction support: the turn proof proves app-server
  `thread/turns/list` order and item availability, not a raw rollout-event
  reconstruction.
- Outside current app-server history support: `thread/start.sessionStartSource`
  is a start request parameter, not a historical `thread/list`, `thread/read`,
  or `thread/turns/list` field, so prompt-start shape can only be inferred from
  `userMessage` items.
- Outside current app-server history support: `turn/start.output_schema` is a
  per-turn request parameter, but current historical app-server read surfaces do
  not expose which past turns used it.
- Outside current app-server support: `thread/turns/items/list` exists in the
  app-server protocol, but the Codex app-server currently returns
  `method_not_found` for it, so it is not an app-server-provided detail surface
  yet.

## App-Server Boundary Proofs

- Previewless thread discovery is outside current app-server enumeration:
  `thread/list` only returns list-discoverable rows, while `thread/read` can
  read the stable missing thread only after the relay already knows its ID.
- `thread/search` is not enumeration: Codex requires a non-empty `searchTerm`
  and searches rollout content matches.
- Exact goal identity is outside current app-server goal state: SQLite has
  `goal_id`, but app-server `ThreadGoal` omits it.
- Orphan goals are outside current app-server goal state: `thread/goal/get`
  reads by known materialized `threadId`; app-server does not expose a
  standalone goal list.
- Atomic cross-surface audits are outside current app-server responses:
  `thread/list`, `thread/search`, `thread/read`, `thread/turns/list`, and
  `thread/goal/get` responses do not include one shared snapshot, revision, or
  transaction ID.
- Formal historical start source is outside current app-server read state:
  Codex accepts `thread/start.sessionStartSource`, but does not return it on
  historical thread list/read/turn responses.
- Historical JSON/output-schema mode is outside current app-server read state:
  Codex accepts `turn/start.output_schema`, but current `thread/turns/list`
  items do not expose a corresponding field for past turns.
- App-server surface conflicts are visible and relay-resolved for client
  projection: the relay canonical app-server projection records a deterministic
  field winner and source surface. Codex storage conflicts remain outside that
  projection when SQLite and rollout `session_meta` disagree.

## Related Docs

- [Relay state parity worklog](CODEX_DOCK_RELAY_STATE_PARITY_WORKLOG_2026-05-30.md):
  tracks the relay-only work toward exhaustive app-server-backed state parity.
- [Relay thread fidelity worklog](CODEX_DOCK_RELAY_THREAD_FIDELITY_WORKLOG_2026-05-29.md):
  tracks the audit tool and the current relay-vs-storage mismatch outcomes.
- [App-server thread types and state](CODEX_APP_SERVER_THREAD_TYPES_AND_STATE_2026-05-29.md):
  defines what the app-server can prove about live, loaded, archived, spawned,
  goal, and JSON-mode thread state.
- [Disk and database thread types and state](CODEX_DISK_DB_THREAD_TYPES_AND_STATE_2026-05-29.md):
  defines what Codex rollout files and SQLite can prove about durable thread
  state.

## Outcomes

- G-001: Codex Dock does not show Codex-archived threads in normal app session
  lists.
- G-001a: Codex-archived threads do not appear on Home, Dock, Activity,
  Agents, pinned/watchlist, search, recent-session, badge-count, or normal
  thread-opening surfaces.
- G-001b: Codex-archived threads appear only in an explicit archive or restore
  surface.
- G-001c: Active, old, not-loaded, or dormant threads still appear when they are
  not Codex-archived.
- G-001d: Active-session counts, human-session counts, agent-session counts, and
  notification-style counts exclude Codex-archived threads.
- G-001e: If a visible thread becomes Codex-archived, the app stops presenting
  it as an active session.
- G-001f: A Codex-archived thread means Codex's own archive state: the thread is
  returned by archived thread listing, marked archived in Codex storage, or
  stored under Codex's archived session files.
