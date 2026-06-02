✅ I accept the synthesis.

⚠️ Blockers if omitted:
- A second canonical doc would create drift. Update the existing live-update doc.
- UI stores must not keep direct subscribe/resync/replay side doors.
- “One apply law” must be real code plus one shared test suite, not just prose.
- “Connected” must never mean “subscribed, caught up, and fresh.”
- Proof must not pass through fixture-built IDs, screenshots, lag-only checks, or weak matrix defaults.
- Strict concurrency must be required for state/projection/runtime layers, with named quarantines only for AVFoundation/URLSession-style bridges.

Required doc wording:

```text
This document is the canonical Codex Dock client live-update, projection-runtime, freshness, and proof reference. `docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md` is retained as source input, but this document supersedes it for implementation wherever the two differ.
```

```text
There is exactly one active `StreamSyncEngine` / `StreamReconciler` owner per visible stream key: Dock host view, Archive host view, and Thread Detail thread view. UI stores may send intents and render snapshots; they may not own subscription state, recovery tasks, replay buffers, heartbeat timers, generation tokens, or direct resync loops.
```

```text
Every refresh cause enters the reconciler as a serialized intent: initial load, user refresh, command mutation, foreground resume, transport reconnect, heartbeat timeout, sequence gap, relay `resyncRequired`, and Dock-row invalidation.
```

```text
Transport reconnect is not subscription recovery. A connected WebSocket proves only transport availability; it does not prove that a view stream is subscribed, caught up, or fresh.
```

```text
`Live` is derived from a freshness lattice. A view may render `Live` only when transport is connected, the stream subscription is active, heartbeat is within budget, no resync is pending, foreground gating allows visible work, and catch-up is complete for the current generation.
```

```text
Swift must use one projection apply law for Dock, Archive, and Thread Detail. The implementation may be a generic `ProjectionStore<Row>` or a shared reducer core used by typed tables, but it must have one invariant set and one shared test suite. A giant universal row store is not required unless it is the smallest way to prevent drift.
```

```text
Catch-up is bounded by generation and double-buffering. The replay set is frozen at catch-up start; already-covered events are dropped, continuous events are applied once, later events move to the next generation, and timeout moves the stream to stale/error.
```

```text
Strict concurrency is required for state, projection, and runtime ownership code. AVFoundation, URLSession, and other unavoidable bridge layers may be quarantined only if the quarantine is named, documented, isolated behind Sendable value boundaries, and covered by invariants/tests.
```