---
title: "Codex Dock Relay Thread Fidelity Worklog"
date: 2026-05-29
status: active
doc_type: worklog
owners: [Amir, Codex]
---

# Codex Dock Relay Thread Fidelity Worklog

## Objective

Build a reusable checker that compares the thread/session shape the Codex Dock
app receives from the Dock relay with Codex's durable storage record on disk and
in SQLite.

The goal is diagnostic only. This work documents differences; it does not fix
them.

## Tool Added

Added:

```bash
scripts/dock-relay-thread-fidelity.mjs
scripts/dock-relay-thread-fidelity.test.mjs
```

Added Make target:

```bash
rtk make relay-thread-fidelity
```

The Make target writes the full sanitized report to:

```bash
/tmp/codex-client/relay-thread-fidelity-<UTC timestamp>.json
```

It prints only a compact JSON summary to stdout so `rtk node` does not truncate
the useful report.

To choose the output path:

```bash
rtk make relay-thread-fidelity THREAD_FIDELITY_REPORT=/tmp/codex-client/thread-fidelity.json
```

Direct script examples:

```bash
rtk node -- scripts/dock-relay-thread-fidelity.mjs --max-threads 25 --json-out /tmp/codex-client/thread-fidelity.json --summary-only
rtk node -- scripts/dock-relay-thread-fidelity.mjs --thread-id <thread-id> --include-archived
rtk node -- scripts/dock-relay-thread-fidelity.mjs --fail-on-diff
```

## Comparison Surfaces

Relay/app-client side:

- `dock/subscribe`: the real app-facing session table path.
- `thread/loaded/list`: what the relay believes is currently loaded/live.
- `thread/list`: active interactive rows.
- `thread/list` with automation source kinds: active spawned/agent rows.
- Optional archived `thread/list` scopes with `--include-archived`.
- `thread/read`: per-thread relay detail without turns.

Codex storage side:

- `$CODEX_HOME/sessions/**/rollout-*.jsonl`.
- `$CODEX_HOME/archived_sessions/rollout-*.jsonl`.
- `$CODEX_HOME/session_index.jsonl`.
- `$CODEX_SQLITE_HOME/state_5.sqlite`.
- `$CODEX_SQLITE_HOME/goals_1.sqlite`.
- `state_5.sqlite.thread_spawn_edges`.
- `state_5.sqlite.thread_dynamic_tools`.
- `state_5.sqlite.backfill_state`.

## What It Can Tell Us

The tool can flag these classes of mismatch:

- App-facing `DockStreamSessionDTO` fields disagree with relay `thread/read`.
- Relay `thread/read` metadata disagrees with `state_5.sqlite` or rollout
  `session_meta`.
- A non-ephemeral relay thread has no durable DB/rollout proof.
- A dock session has the wrong `lane` for its storage source.
- A dock session has the wrong `source.kind` for its storage source.
- A dock session is visible even though storage classifies it as internal.
- `thread/loaded/list` disagrees with `thread/read.status`.
- `state_5.sqlite.threads.rollout_path` points somewhere different from the
  rollout found on disk.
- State DB archive flags disagree with active vs archived rollout location.
- Current goals exist in `goals_1.sqlite`.
- Rollout parse errors exist.

Live vs old is handled this way:

- Relay `thread/loaded/list` plus `thread/read.status` is treated as live-state
  evidence.
- Disk and SQLite only prove durable state. They cannot prove whether the
  app-server has a thread loaded right now.

User-created vs spawned is handled this way:

- `cli`, `vscode`, and known interactive custom sources are treated as human.
- `exec`, `mcp`/`appServer`, sub-agent variants, and `unknown` are treated as
  automation for the Dock table.
- `thread_spawn_edges` is included as stronger spawned-session proof when it
  exists.

JSON mode is handled this way:

- Normal turn JSON-output schema is not expected to be durable in rollout or
  `state_5.sqlite`.
- The report adds an informational finding when no persisted JSON-mode schema
  proof exists. That is expected for ordinary turns.

## Privacy

The checker does not print prompt text, transcript text, raw audio, full
JSON-RPC payloads, bearer tokens, or OpenAI keys.

Text-like fields are represented as fingerprints:

```json
{
  "present": true,
  "chars": 812,
  "bytes": 812,
  "sha256": "7cc7793ae39a"
}
```

This applies to fields such as:

- relay `preview`, `name`, and `latestSummary`;
- dock `title` and `summary`;
- DB `title`, `preview`, and `first_user_message`;
- rollout first user message;
- `goals_1.sqlite.thread_goals.objective`;
- `session_index.jsonl` names.

Structured source objects are summarized by normalized source class, object
keys, and hash. The report does not dump raw structured source JSON.

## Verification Run

Service status before running the checker:

```bash
rtk make app-server-status
rtk make dock-relay-status
```

Both returned `status: "ready"` with active `raw-app-server` and `dock-relay`
services.

Focused checks:

```bash
rtk node --check scripts/dock-relay-thread-fidelity.mjs
rtk node --test scripts/dock-relay-thread-fidelity.test.mjs
rtk npm run test:relay
```

Results:

- `rtk node --check scripts/dock-relay-thread-fidelity.mjs`: passed.
- `rtk node --test scripts/dock-relay-thread-fidelity.test.mjs`: 6 tests
  passed.
- `rtk npm run test:relay`: 74 tests passed.

Make target verification:

```bash
rtk make relay-thread-fidelity THREAD_FIDELITY_REPORT=/tmp/codex-client/20260529-relay-thread-fidelity/make-target-full.json
```

The target completed successfully and wrote:

```bash
/tmp/codex-client/20260529-relay-thread-fidelity/make-target-full.json
```

Compact summary from that run:

```json
{
  "ok": false,
  "checkedThreads": 50,
  "findings": 312,
  "errors": 62,
  "warnings": 144,
  "info": 106,
  "dockSessions": 200,
  "loadedThreadCount": 12
}
```

Storage status from the same run:

- `state_5.sqlite`: present.
- `goals_1.sqlite`: present.
- `backfill_state.status`: `complete`.

## Discrepancies Found

The 50-thread live run found no relay request failures and no durable-record
missing errors. The discrepancies were concentrated in client-visible fields:

```json
{
  "error dock.snapshot lane": 50,
  "error dock.snapshot status": 12,
  "warning relay.thread_read updatedAt": 48,
  "warning dock.snapshot updatedAt": 48,
  "warning dock.snapshot summary": 48
}
```

Current interpretation:

- Every checked dock snapshot row had `lane: null`, while storage classification
  expected either `human` or `agent`.
- 12 checked dock snapshot rows reported a status such as `dormant` while relay
  `thread/read` reported a live status such as `running`, `idle`, or `error`.
- 48 checked rows had relay `thread/read.updatedAt` behind the latest durable
  DB/rollout update time.
- 48 checked rows had dock `updatedAt` matching newer storage time while
  `thread/read.updatedAt` still reflected older live-thread metadata.
- 48 checked rows had dock `summary` hashes different from relay-derived
  `latestSummary || preview || title`, which is consistent with the relay summary
  cache being a separate app-facing overlay.

No discrepancy was found in the live run for these fields:

- durable record existence;
- rollout path existence;
- source classification between relay and storage;
- fork parent;
- model provider;
- working directory;
- git branch;
- archive state.

## Useful Report Paths

Latest focused 25-thread report:

```bash
/tmp/codex-client/20260529-relay-thread-fidelity/report.json
```

Latest Make target 50-thread report:

```bash
/tmp/codex-client/20260529-relay-thread-fidelity/make-target-full.json
```

These are scratch artifacts outside the repo. They are sanitized, but still
contain paths, thread IDs, timestamps, source classes, git metadata, and text
fingerprints.

## Current Limitations

- The tool reads rollout JSONL synchronously. That is fine for focused checks,
  but a very large full-history sweep should use streaming.
- It only checks rows selected from current relay surfaces unless explicit
  `--thread-id` values are provided.
- It reports summary-cache mismatches as warnings, even though some may be
  intentional app-facing enrichment.
- It cannot prove old JSON-mode turns from disk because Codex does not persist
  normal turn `final_output_json_schema` in the durable thread metadata.
- It cannot prove current realtime/transcription state from disk or SQLite.

## Files Changed

- `scripts/dock-relay-thread-fidelity.mjs`
- `scripts/dock-relay-thread-fidelity.test.mjs`
- `Makefile`
- `package.json`
- `docs/CODEX_DOCK_RELAY_THREAD_FIDELITY_WORKLOG_2026-05-29.md`
