You are Model B in a model-consensus run for `/Users/aelaguiz/workspace/codex-client`.

Task: final convergence pass. Do not edit files. Read:

- `.arch_skill/model-consensus/codex-dock-client-robustness-20260602T201428Z/round-01/model-a-final.md`
- `.arch_skill/model-consensus/codex-dock-client-robustness-20260602T201428Z/round-01/model-b-final.md`
- `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
- `docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md`
- the code paths named in those docs/results if needed.

Proposed synthesis for the canonical doc:

1. Existing live-update doc remains the canonical document and gets updated. No duplicate new doc unless absolutely needed.
2. Client target is one `StreamSyncEngine` / `StreamReconciler` per visible stream key: Dock host view, Archive host view, Thread Detail thread view.
3. All refresh causes become serialized intents into that engine: initial load, user refresh, command mutation, foreground resume, reconnect, heartbeat timeout, sequence gap, relay `resyncRequired`, Dock-row invalidation.
4. The engine owns connection, subscribe, resync, catch-up, heartbeat, foreground gating, generation tokens, terminal states, and observability. UI stores only send intents and render snapshots.
5. Projection identity/order/freshness still comes only from the relay projection contract.
6. Swift uses one shared projection apply law. It may be implemented as one generic `ProjectionStore<Row>` or a shared reducer core plus typed tables, but the plan should require one law and one test suite. It should not require a giant universal row store unless that is objectively necessary to prevent drift.
7. Catch-up is bounded by generation and double-buffering: freeze the replay set, decode updates, drop already-covered events, apply continuous events, send later events to the next generation, and time out to stale/error.
8. Transport reconnect is not subscription reconnect. A connected socket is not proof the view stream is subscribed or caught up.
9. Freshness is a lattice: `Live` requires connected transport, active subscription, heartbeat within budget, no pending resync, and catch-up complete at the current generation.
10. Testing must include deterministic reducer tests, adversarial/generative interleavings, recorded real event replay, simulator accessibility dump/proof, controlled matrix with stricter defaults, and long-running soak/watchdog proof.
11. Strict concurrency is a target for state/projection/runtime layers; unavoidable AVFoundation/URLSession bridges may be quarantined, documented, and covered by invariants rather than blocking the whole plan.

Return only:

- Whether you accept this synthesis.
- Any blocker that would make the plan non-canonical or allow side doors.
- Exact wording changes you require in the doc.
