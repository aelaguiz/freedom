# Consensus Round 02

You have already completed an independent architecture pass. Now read the other
model's final pass and give a focused signoff or objection. Do not reopen the
entire investigation unless an agreed point is factually wrong.

Inputs:

- Codex/GPT final:
  `.arch_skill/model-consensus/codex-dock-app-server-architecture-20260529T012239Z/round-01/gpt55xhi/final.md`
- Claude/Opus final:
  `.arch_skill/model-consensus/codex-dock-app-server-architecture-20260529T012239Z/round-01/opus-max/final.md`

The parent synthesis candidate is:

1. Keep the phone-facing relay on `:4510`, but treat it as a Mac-side Codex
   Dock Host Agent.
2. Keep a dedicated Dock-owned raw history app-server on
   `ws://127.0.0.1:4500` as the stable history anchor.
3. Split Host Agent internals into:
   - `HistoryClient`: one long-lived multiplexed pooled JSON-RPC connection to
     `:4500`.
   - `LiveStatusCache`: cached/background live endpoint discovery plus pooled,
     read-only status sweeps.
   - `SessionRouter`: one focused `thread/resume` connection only for the open
     detail thread and turn control.
   - `TranscriptionProxy`: OpenAI Realtime stays Mac-side.
4. Dashboard `thread/list` membership, order, and cursor are history-plane
   truth. Live status may repaint `status`, `attention`, `ownerEndpoint`, and
   degradation metadata, but it must not move, filter, or page rows.
5. Use `updatedAt desc` plus deterministic `threadId` tie-break for "Newest".
6. Remove list-time per-row preview and attention fanout. Preview must become
   lazy/bounded or come from a future Codex-provided row field.
7. Collapse to one logical host per relay instance id. Endpoint aliases are an
   ordered failover list, not separate hosts.
8. Prefer a single union `sourceKinds` list query tagged by source kind. If
   that proves unsafe for coverage or Codex filtering, keep dual scopes but run
   them through the same pooled HistoryClient; do not let scopes multiply
   upstream sockets or logical hosts.
9. `ps`-based live discovery is acceptable only as a cached transitional
   scanner with visible blind-spot/degraded state. The long-term ideal is a
   Codex-native endpoint/session registry.
10. Add explicit observability: redacted structured relay logs, stable
    `/statusz`, `/metricsz`, `/debugz/sessions`, open-upstream socket gauges,
    fd gauges, `relay-probe`, `relay-leak-check`, and `relay-doctor`.

Please answer in this exact shape:

## Signoff

Say one of:

- `converged`
- `converged-with-required-edit`
- `not-converged`

## Required Edits Before Canonical Doc

List only architecture changes that must be made before the parent writes the
canonical architecture doc. If none, say `None`.

## Reason

Explain the smallest decisive reason in 3-8 bullets.

## Exact Wording To Include

Give any precise invariant wording that should appear in the canonical doc.
