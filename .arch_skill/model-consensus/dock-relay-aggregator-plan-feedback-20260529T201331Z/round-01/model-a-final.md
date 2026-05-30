I found one blocker. The plan is close, but Section 7 does not require proof that rows stay visible when a host is truly offline/disconnected.

**Blocking Findings**

- **BLOCKER**: Offline row-retention is promised but not carried into the authoritative phase proof.
  Plan evidence: [Section 0.1](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md:108) promises rows retained when a relay host is “slow, stale, offline, or restarting.” But Phase 3-5 proof covers stale/slow/reconnect and raw-path absence, not an offline/disconnected host proof: [Phase 3 exit](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md:809), [Phase 4 exit](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md:848), [Phase 5 checklist](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md:861).
  Repo evidence: current Home can replace row state with standalone `.offline`/`.error` states: [DockStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockStore.swift:436), and `reload` sets `.offline`/`.error` on complete host failure instead of keeping a row snapshot: [DockStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockStore.swift:606). This is exactly the behavior the plan must prevent, so offline/disconnect retention needs explicit checklist and simulator proof.

**Non-Blocking Findings**

- Clarify that “no provider-specific source/status decoding in the client” means the Dock Home stream path. Raw non-Home callers still intentionally use `ThreadListDTO` / `SessionSummaryMapper` for Archive and Host Settings.

- Keep raw `thread/list` compatibility tests separate from new `dock/*` normalization tests. `notLoaded` must disappear from `dock/*`, but preserved raw-list callers may still need raw Codex status behavior.

- In Phase 3, name the stream reconnect policy explicitly. `AppServerClient` defaults to `.oneShot`, while the plan expects reconnect/resync behavior.

**Evidence Read**

- [Architecture plan](/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md:1): checked TL;DR, North Star, target architecture, call-site audit, phases, verification.
- [DockStore.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockStore.swift:569): current Home reload, partial snapshots, offline/error row-clearing risk, `notLoaded` status model.
- [AppServerDockClient.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/AppServerDockClient.swift:83): current raw `thread/list` Home loader.
- [AppServerClient.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/AppServerClient.swift:141): existing request/response and notification transport support.
- [ThreadListDTO.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/ThreadListDTO.swift:256), [SessionSummaryMapper.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/Models/SessionSummaryMapper.swift:328), [SessionRowProjector.swift](/Users/aelaguiz/workspace/codex-client/CodexDock/State/SessionRowProjector.swift:58): current `notLoaded` decoding and projection.
- [dock-relay.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs:450), [dock-relay-thread-data.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs:457), [dock-relay-live-status-cache.mjs](/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-live-status-cache.mjs:43): current relay list/live-cache owners.
- Ran `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md`; result was `READY next=implement-loop`.

**Final Judgment**

Acceptable for plan-audit? **no**. Fix the offline/disconnect row-retention proof gap first.