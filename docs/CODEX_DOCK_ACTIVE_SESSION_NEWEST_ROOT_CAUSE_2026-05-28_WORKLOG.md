# Active Session Newest Root Cause Worklog

Plan:
`docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`

Last updated: 2026-05-28T23:22:21Z

## Summary

Implemented the relay-only freshness fix. Active same-id live/history rows now
keep live status and routing while borrowing a fresher history `updatedAt`, so
the existing app-side `Newest` ordering receives a fresh activity timestamp.

## Files Changed By This Pass

- `scripts/dock-relay-thread-data.mjs`
  - Added `mergeLiveRowWithHistoryFreshness`.
  - Built a newest `historyById` map inside `mergeThreadListRows`.
  - Freshened live rows before sort/sanitize/fill.
- `scripts/dock-relay.test.mjs`
  - Added pure merge coverage for fresher-history wins, no downgrade,
    duplicate slot behavior, live status/source preservation, and sanitization.
- `scripts/dock-relay-phase5.test.mjs`
  - Added real relay `thread/list` coverage for stale live `updatedAt` plus
    fresh history `updatedAt`.
  - Added proof that same-thread turns routing remains on the live endpoint.
- `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28.md`
  - Marked phases complete and added implementation audit evidence.
- `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_PLAN_AUDIT.md`
  - Kept as the pre-implementation plan-audit record.
- `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_THERMONUCLEAR_REVIEW.md`
  - Added strict maintainability review.
- `docs/CODEX_DOCK_ACTIVE_SESSION_NEWEST_ROOT_CAUSE_2026-05-28_WORKLOG.md`
  - This worklog.

## Implementation Notes

- The fix stayed in `scripts/dock-relay-thread-data.mjs::mergeThreadListRows`.
- The relay keeps the live row as the authority for status, source, active
  flags, and internal `dockRelaySource`.
- History contributes only a fresher activity timestamp through `updatedAt`.
- Older history timestamps do not downgrade live rows.
- Same-id live/history rows still consume one returned slot.
- Archived lists remain history-only.
- No Swift, project, DTO, protocol, upstream Codex, timer, push stream, or
  extra live `thread/list` call was added.

## Verification

### Focused Tests

Command:

```bash
rtk npm run test:relay
```

Final result:

- `tests 51`
- `pass 51`
- `fail 0`
- `duration_ms 7520.262041`

Notes:

- Two intermediate reruns failed only in the newly added test assertion:
  first because the counters were in the wrong scope, then because preview
  enrichment already made one live `thread/turns/list` call before the explicit
  turns request.
- The final test now intentionally proves both live turns calls remain live
  routed and `historyTurnsRequests` stays `0`.

### Runtime Smoke

Command shape:

```bash
rtk node --input-type=module
```

The smoke script connected to:

- Relay: `ws://127.0.0.1:4510/`
- Raw history app-server: `ws://127.0.0.1:4500/`

Result:

```json
{
  "relayRows": 100,
  "historyRows": 100,
  "activeDuplicates": 2,
  "staleActiveDuplicates": 0
}
```

Sample active duplicate rows:

- `019e6e6a-d156-7d03-85b1-c49a55539c90`: relay `updatedAt`
  `1780010398`, history `updatedAt` `1780010398`, fresh `true`.
- `019e7001-4ab8-7842-a327-89e0da6a5877`: relay `updatedAt`
  `1780010386`, history `updatedAt` `1780010386`, fresh `true`.

### Service Status

Command:

```bash
rtk make dock-relay-status
```

Final result:

- `status: "ready"`
- raw app-server `:4500` active
- Dock relay `:4510` active
- relay app endpoint `ws://192.168.50.117:4510/`

## Service Reload Note

To make the smoke prove the edited relay code, the launchd relay process had to
load the updated module.

`rtk make dock-relay-restart` restarted the launchd services but then failed in
`host-service-wait` with `status: "not-ready"` because both launchd labels were
inactive with `exitCode: 113`. Directly bootstrapping the generated plist files
restored the services:

```bash
rtk launchctl bootstrap gui/501 /Users/aelaguiz/workspace/codex-client/.codex-dock/services/com.aelaguiz.codex-dock.app-server.plist
rtk launchctl bootstrap gui/501 /Users/aelaguiz/workspace/codex-client/.codex-dock/services/com.aelaguiz.codex-dock.relay.plist
```

This appears to be an existing host-service restart-management issue, not part
of the relay merge freshness fix.

## Review

- Sidecar reviewer verdict: pass, with one non-blocking routing-test gap.
- The routing-test gap was resolved in `scripts/dock-relay-phase5.test.mjs`.
- Thermo-nuclear review verdict: pass, no unresolved structural blockers.

## Open Items

None for this requested fix.
