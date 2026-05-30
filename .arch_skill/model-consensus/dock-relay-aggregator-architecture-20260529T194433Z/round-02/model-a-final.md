**Decision Memo**

I mostly converge with Model B. I change my first-pass recommendation on cross-host aggregation: V1 should use one clean stream per relay host plus a trivial client union, not a coordinator relay across all hosts.

**Where I Agree With Model B**

- Client should subscribe to relay-owned state, not poll `dock/snapshot` on an interval.
- Relay polls upstream providers internally, builds a warm session table, then pushes `snapshot` and `delta` messages to the client.
- V1 resync should always return a full snapshot. No replayable delta log yet.
- `lane` should be on the wire: `human | agent`. The client should not derive that from Codex `sourceKind`.
- Raw Codex `notLoaded` should disappear entirely from the client wire.

**Where I Change My First Pass**

I now endorse Model B’s per-host relay model over my coordinator relay model.

Reason: a coordinator adds peer discovery, peer auth, failure routing, and a new service boundary. That is real complexity. If each host relay sends a clean provider-agnostic session table, the client’s “union” is just concatenate normalized rows and sort by `lastActivityAt`. That is UI composition, not provider/state recovery logic.

So: no client decoding, no scope fan-out, no raw Codex merging, no cursor paging. But multiple host streams are acceptable if each stream is already clean.

**Point I Still Reject**

I still reject deferring disk persistence entirely.

The goal calls the relay the durable aggregator. V1 does not need SQLite or a durable delta log, but it should persist the last-good full session table atomically under `.codex-dock/`. That is the lean version of durability: after relay restart or upstream failure, the relay can still serve a fast stale snapshot instead of cold-empty state.

**Exact Target Architecture I Endorse**

- Each relay host runs a stateful provider-agnostic `SessionTable`.
- The relay owns provider adapters, Codex decoding, live/history merge, summary warming, retry/backoff, status normalization, caching, stale-while-refresh, and last-good snapshot persistence.
- The phone opens one clean stream per configured relay host.
- Each stream starts with a full `snapshot`, then sends ordered `delta` updates.
- Client stores one table per host. Cross-host view is `allTables.flatMap(rows).sorted(lastActivityAt desc)`.
- If `epoch` changes, `seq` gaps, or reconnect happens, client requests `resync` and receives a full snapshot.
- V1 has no delta replay log. Deltas are for connected clients only.
- V1 has minimal disk persistence: last-good full snapshot, not event sourcing.
- Wire status is canonical, for example:
  - `lane: human | agent`
  - `runtimeStatus: running | needsInput | needsApproval | idle | error | inactive | unknown`
  - `detailAvailability: live | cold | unavailable`
  - `freshness: fresh | stale`
- The string `notLoaded` never crosses the client wire.

**What The Final Doc Should Say**

The final architecture should pick these decisions clearly:

1. Target is push subscription: relay-owned snapshot, incremental delta, explicit full-snapshot resync.
2. Target topology is per-host relay streams with trivial client union, not coordinator relay federation.
3. Resync V1 is full snapshot only.
4. V1 persists last-good full snapshots to disk; no persisted delta log.
5. Provider adapters own raw status/source decoding; client receives canonical `lane`, `runtimeStatus`, `detailAvailability`, and `freshness`.
6. `notLoaded` is a Codex adapter input only, never a client-visible row status.
7. Client remains simple: connect, subscribe, apply snapshot/delta, resync on gap, render.