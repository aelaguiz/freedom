# Phase 5 Thermonuclear Code Quality Review

Date: 2026-05-28

Scope: Phase 5 typed text control, minimal request cards, relay turn/request
forwarding, and request-aware Dock attention enrichment.

Verdict: pass with one scale watch item.

## Blocking Findings

None.

## Non-Blocking Findings

1. Relay request-attention enrichment adds short-lived `thread/resume` probes
   for active rows.
   - Severity: non-blocking.
   - Why it matters: Phase 6 multi-host scanning can increase active-row count,
     and `thread/list` runs on a refresh loop.
   - Why it is acceptable now: it uses real supported app-server replay
     behavior, is limited to active rows without existing attention flags, and
     avoids fake Needs-me status.
   - Required follow-up: Phase 6 should decide whether this needs a TTL cache,
     host-level throttle, or upstream pending-request API.

## Code-Quality Assessment

- `ThreadDetailStore` grew into the correct owner for detail read/resume,
  composer state, active-turn tracking, and request cards. The file remains
  under 500 lines and did not cross a file-size cliff.
- `ServerRequestCard` is the right boundary for request method classification
  and response payload shape. The UI consumes typed card state rather than
  branching on raw JSON-RPC.
- `ComposerView` and `RequestCardView` are small, focused SwiftUI components.
  They do not call `AppServerClient` directly.
- `AppServerClient` remains the sole Swift JSON-RPC transport owner. New turn
  methods and `sendResponse` follow the existing typed-wrapper pattern.
- `scripts/dock-relay.mjs` is approaching the point where Phase 6 may want
  decomposition, but it remains under 1,000 lines and the new pure functions
  are covered by `scripts/dock-relay.test.mjs`.
- No second composer path was introduced. Phase 8 voice can still feed text
  into the same composer state.
- No permission-management product was introduced. Supported approvals remain
  intentionally minimal.
- Unsupported request methods remain visible as "Needs desktop" instead of
  being silently dropped.

## Architecture Review

The implementation keeps ownership clean:

- UI owns rendering only.
- `ThreadDetailStore` owns feature state and user actions.
- `AppServerClient` owns Swift JSON-RPC send/read/response mechanics.
- `ServerRequestCard` owns request/card normalization and response payloads.
- The relay owns host-local live-session aggregation and forwarding.

The main code-judo decision was to avoid building a separate phone-side status
system. Dock `Needs me` continues to use app-server status flags, and the relay
adds only a real pending-request replay probe when the owning app-server has
more attention state than `thread/list` exposes.

## Drift And Side-Door Review

- No mock rows or invented statuses were added.
- No UI path bypasses `ThreadDetailStore` to send text or request responses.
- No old read-only detail path competes with the new control path; it is the
  same detail store extended.
- Request method strings exist in both Swift request-card normalization and
  relay list-attention classification. This is acceptable for Phase 5 because
  they serve different boundaries, but Phase 6 should avoid expanding that
  duplication without a shared table or generated contract.

## Verification Context

Verification reported in the worklog:

- `rtk node --check scripts/dock-relay.mjs`
- `rtk npm run test:relay`
- `rtk swift test`
- `rtk make dock-relay-restart`
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath .codex-dock/DerivedData`
- `rtk make app SIM='iPhone 17'`
- `rtk git diff --check`
- Real typed-send smoke through `ws://192.168.50.117:4510`.
- Simulator screenshot: `/tmp/codex-dock-phase5-root-cause-composer.png`.

## Final Judgment

Phase 5 is structurally acceptable. The code adds the smallest real control
loop that matches the plan without faking Codex state, and it keeps later voice
and multi-host work on the existing owner paths. Commit it, then make relay
polling cost an explicit Phase 6 review item.
