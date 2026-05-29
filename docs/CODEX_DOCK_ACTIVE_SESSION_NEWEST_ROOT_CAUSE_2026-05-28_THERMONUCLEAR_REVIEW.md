# Thermo-Nuclear Code Quality Review

Plan:
`docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`

Reviewed at: 2026-05-28T23:22:21Z

Verdict: PASS

## Scope

- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay.test.mjs`
- `scripts/dock-relay-phase5.test.mjs`
- Runtime smoke evidence for `ws://127.0.0.1:4510/`
- Focused relay test output

## Blocking Findings

None.

## Non-Blocking Findings

None remaining.

The sidecar reviewer initially found one non-blocking proof gap: live-side turns
routing was preserved by code shape but not directly asserted in the freshness
regression test. That gap was closed by asserting that both preview enrichment
and explicit `thread/turns/list` stay on the live endpoint, while the history
endpoint receives `0` turns requests.

## Structural Review

### Ownership

Pass. The fix is in the canonical relay merge owner:
`scripts/dock-relay-thread-data.mjs::mergeThreadListRows`.

No Swift workaround, protocol change, DTO migration, upstream Codex edit, timer,
push stream, or extra live `thread/list` call was introduced.

### Complexity

Pass. The production change is one small helper plus a `historyById` map in the
existing merge path.

The helper keeps a narrow contract:

- if there is no matching history row, return the live row unchanged
- if history has no valid timestamp, return the live row unchanged
- if live is already as fresh or fresher, return the live row unchanged
- otherwise return the live row with only `updatedAt` replaced

That avoids a broad field overlay and keeps live status/routing/source as the
authority.

### Coupling

Pass. The change uses fields already present in the existing `thread/list` row
shape. It does not create a second sorting source of truth.

The app can keep consuming the existing relay `updatedAt` field; no Swift
sorting compensation is needed.

### Side Doors

Pass. Checked behaviors:

- archived lists remain history-only
- source filtering still happens before sanitization
- `dockRelaySource` is not returned to clients
- duplicate same-id rows consume one returned slot
- live-first history fill remains in the same merge path
- live-side `thread/turns/list` routing remains live-routed after freshness
  merge

### File Size And Maintainability

File sizes after implementation:

- `scripts/dock-relay-thread-data.mjs`: `691` lines
- `scripts/dock-relay.test.mjs`: `534` lines
- `scripts/dock-relay-phase5.test.mjs`: `1408` lines

The production file remains under `1000` lines. The phase 5 test file is large,
but this change added one focused regression test to an already established
integration-test file rather than creating a new scattered harness. No
production >1k file was created.

## Verification Reviewed

Focused tests:

```bash
rtk npm run test:relay
```

Result:

- `tests 51`
- `pass 51`
- `fail 0`
- `duration_ms 7520.262041`

Runtime smoke:

- Relay: `ws://127.0.0.1:4510/`
- History: `ws://127.0.0.1:4500/`
- `relayRows: 100`
- `historyRows: 100`
- `activeDuplicates: 2`
- `staleActiveDuplicates: 0`

Service status after reload:

- `rtk make dock-relay-status`
- `status: "ready"`
- raw app-server `:4500` active
- Dock relay `:4510` active

## Final Judgment

This is the smallest maintainable fix for the observed failure. It corrects the
relay data contract where the bad merged row is produced, keeps the app and
protocol unchanged, and proves the highest-risk same-id active/history path
through pure tests, relay integration tests, and a local relay smoke.
