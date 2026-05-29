# Codex Dock Canonical App-Server Architecture Thermonuclear Review

Date: 2026-05-29

## Verdict

Approved.

The implementation now has no structural code-quality blocker in the reviewed
scope. The prior acceptance proof gaps are now closed: multi-concurrent
simulator UI submit proof, stale-opening overview summary proof, and the
`Partial` / `Online` stable-service observation.

## Finding Fixed

- Automatic focused-upstream recovery did not share the same hard invariant as
  the initial `thread/resume` binder. The first bind rejected an upstream that
  returned the wrong thread id, but recovery only awaited `thread/resume` and
  then accepted the recovered upstream. The old upstream's
  `pendingServerRequests` also survived close, so a late phone response could
  be forwarded to a recovered upstream.
  - Fix: `scripts/dock-relay.mjs` now clears `pendingServerRequests` when the
    focused upstream closes, and recovery calls the same
    `assertResumeResultMatchesRequestedThread` guard before accepting the new
    upstream.
  - Regression tests:
    `scripts/dock-relay-phase5.test.mjs` now covers wrong-thread recovery
    binding and stale phone responses after upstream recovery.

## Structural Review

- Relay ownership is cleaner than the pre-plan shape. History list ownership is
  in `HistoryClient` / `UpstreamConnectionPool`; live status discovery and
  focused routing are in `LiveStatusCache` / `SessionRouter`; overview latest
  summaries are in `ThreadSummaryCache`; downstream message forwarding remains
  in `scripts/dock-relay.mjs`.
- The stale overview summary fix lives in the right layer. The relay owns
  `latestSummary`, Swift decodes it, and `SessionSummaryMapper` uses it before
  falling back to row turns or raw `preview`. The Swift fallback is acceptable
  because it handles richer future DTOs without taking ownership away from the
  relay.
- The list path does not reintroduce request-time per-row fanout. `thread/list`
  decorates rows only from cache, then warms missing summaries out of band with
  bounded concurrency.
- The focused submit path has one clear invariant: a downstream detail
  connection is bound by `thread/resume`; turn methods must name the same
  `threadId`; server-request responses must match a request id forwarded during
  the current active binding.
- Makefile ownership is now clear. The normal app, simulator, physical-device,
  config-readback, relay-probe, and service-status commands are Makefile
  targets. Raw Xcode/CoreDevice calls remain hidden implementation details
  inside those targets and write timestamped logs.
- Device identity is modeled directly enough for the current need. The iPhone
  17 Pro Tailscale profile and iPhone 14 LAN profile both point at the same
  logical `relayInstanceID`, so endpoint aliases do not multiply the Dock host
  list.
- No reviewed production file crossed 1,000 lines:
  - `scripts/dock-relay.mjs`: 976 lines.
  - `scripts/dock-relay-thread-data.mjs`: 536 lines.
  - `scripts/dock-relay-thread-summary-cache.mjs`: 242 lines.
  - `scripts/dock-relay-upstream-pool.mjs`: 233 lines.
  - `scripts/dock-relay-status.mjs`: 388 lines.
  - `CodexDock/State/DockStore.swift`: 789 lines.
  - `CodexDock/State/ThreadDetailStore.swift`: 870 lines.
  - `CodexDock/State/AppServerDockClient.swift`: 217 lines.
  - `CodexDock/State/AppServerThreadDetailSession.swift`: 177 lines.
  - `CodexDock/Configuration/RelayBootstrapStore.swift`: 386 lines.
  - `CodexDock/Configuration/DockHostConfiguration.swift`: 230 lines.

## Non-Blocking Follow-Ups

- If a live-only session is missing from `LiveStatusCache`, `SessionRouter`
  falls back to history. That should fail visibly rather than silently misroute,
  but the focused-route invariant now prevents a submitted turn from silently
  landing on a different resumed thread.
- First paint can still show raw `preview` until `ThreadSummaryCache` warms.
  This is the intentional bounded-resource tradeoff; do not "fix" it by moving
  per-row `thread/turns/list` back into the hot `thread/list` response.
- Physical Mobile MCP UI inspection for the iPhone 14 is blocked until
  WebDriverAgent is running. Exact blocker observed:
  `WebDriverAgent is not running on device`. The Makefile install and config
  readback proof passed.

## Independent Review

- Cursor Agent `composer-2.5-fast` fresh consult:
  `/tmp/fresh-consult/codex-dock-composer-impl-audit-20260529T035327Z-BsL6u3`.
- Verdict: `pass-with-notes`.
- Blocking findings: none for code/doc architecture alignment.
- Parent spot-check: the consult's main hardening note was the recovery
  thread-id invariant; this review fixed it before approval.

## Checks

- `rtk npm run test:relay`
  - Final result: passed, 59 tests, 0 failures.
- `rtk npm test`
  - Final result: passed, 59 relay tests and 31 host-service/device-config
    tests, 0 failures.
- `rtk make dock-relay-restart`
  - Final result: passed; Makefile-owned service restarted with the recovery
    hardening.
- `rtk make dock-relay-status`
  - Final result: passed; service status `ready`.
- `rtk make relay-probe`
  - Final result: passed; `liveOverlay.state=ready`, `ageMs=2474`, 2 live
    endpoints, and 8 live rows.
- `rtk swift test --filter AppServerClientTests`
  - Final result: passed, 48 tests, 5 explicit real-host smoke tests skipped
    because opt-in env vars were not set.
- `rtk swift test --filter DockStoreTests`
  - Final result: passed, 30 tests, 0 failures.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Final result: passed; launched simulator build `20260529041311`.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Final result: passed.
- `rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC DEVELOPMENT_TEAM=R6B8KXF3QW`
  - Final result: passed; installed iPhone 14 build `20260529041420`.
- `rtk make device-config-verify DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`
  - Final result: passed; read back
    `Amir-M5.local:4510,192.168.50.74:4510` and `relayInstanceID=Amir-M5`.
- `rtk git diff --check`
  - Final result: passed.
