# Dock Relay Aggregator Plan Feedback Summary

Participants:

- Model A: `codex`, `gpt-5.5`, `xhigh`, collaborator
- Model B: `claude`, `claude-opus-4-8`, `max`, collaborator

Status:

- One feedback round completed.
- Model A reported one blocker.
- Model B reported no blockers but identified several protocol precision risks.
- Parent integrated the blocking and highest-value precision feedback into
  `docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md`.

Integrated feedback:

- Offline/disconnected host row retention is now required in relay, Swift,
  simulator, and logging proof.
- `epoch`, `seq`, and `baseSeq` are explicitly per-stream.
- Snapshot/resync replacement is scoped to the stream's represented host or
  hosts and must not clear other relay hosts' rows.
- Heartbeats report current stream `seq` and do not advance the sequence.
- Snapshot/delta/heartbeat messages now require a `kind` discriminator.
- Codex active-flag precedence is now explicit:
  `needsApproval`, then `needsInput`, then `running`.
- `dormant` is a canonical wire value, not required visible copy; Dock Home
  must not render `Not loaded`.
- `README.md:131` through `:142` is explicitly named as stale live-doc text to
  update after cutover.

Artifacts:

- `round-01/model-a-final.md`
- `round-01/model-b-final.md`
- `round-01/model-a-events.jsonl`
- `round-01/model-b-events.jsonl`
