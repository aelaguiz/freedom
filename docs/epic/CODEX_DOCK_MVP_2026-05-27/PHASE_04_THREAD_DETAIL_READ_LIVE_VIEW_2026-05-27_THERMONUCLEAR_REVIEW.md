# Phase 4 Thermonuclear Code Quality Review

Date: 2026-05-28
Scope: Phase 4 thread detail read/live view and relay read/resume forwarding
Verdict: approve-with-notes

## Blocking Findings

- None.

## Repairs Made During Review

- Preserved whitespace in live message deltas. The first implementation trimmed
  every delta through the generic non-empty helper, which would have collapsed
  `"hello "` plus `"world"` into `"helloworld"`. `ThreadEventNormalizer` now
  validates non-empty deltas without stripping meaningful whitespace.
- Regenerated `CodexDock.xcodeproj` with `rtk xcodegen generate --spec
  project.yml` after adding new files, because `make app` uses XcodeGen and the
  generated project must match the canonical app build path.
- Added an optional real-host XCTest for `thread/read includeTurns:true` plus
  `thread/resume` against the phone-reachable endpoint. Phase 4 now has a
  repeatable real-host proof, not just a one-off relay probe.

## Structural Review

- `AppServerClient` remains the JSON-RPC owner. Phase 4 added typed
  read/resume wrappers and a server-request stream without moving protocol
  parsing into UI or feature state.
- `ThreadDetailStore` is the correct detail owner. It validates host/thread
  identity, reads the stored thread, resumes the live thread, owns stale/error
  state, and merges matching notifications/requests. `SessionDetailView` only
  renders store state.
- `ThreadEventNormalizer` is a narrow projection layer over Codex thread/event
  shapes. The view never renders `JSONValue` or raw JSON directly.
- Dock row navigation reuses `HostScopedThreadID` and the existing
  `DockHostConfiguration`. It does not create a second host registry or a
  shadow thread id.
- The relay extension is justified by the real runtime topology: the iPhone can
  reach the relay, while loaded thread state and notifications are attached to
  real loopback Codex app-server processes. The relay still uses supported
  Codex JSON-RPC methods and does not invent transcripts or statuses.
- `project.yml` remains the source of truth for the Xcode project. The checked
  in `CodexDock.xcodeproj` was regenerated through XcodeGen instead of being
  hand-maintained as a parallel project definition.

## Maintainability Review

- New file sizes are acceptable: `ThreadDetailStore.swift` is under 300 lines,
  `ThreadEvent.swift` is under 500 lines, `SessionDetailView.swift` is under
  300 lines, and the relay remains under 600 lines.
- The detail state enum is explicit enough for the phase: idle, loading,
  loaded, error, plus live/stale/closed state inside the loaded snapshot. There
  are no hidden nullable mode flags.
- Event merge is intentionally simple: stable live event ids append deltas;
  final/full item events replace by id. This is enough for read/live detail and
  keeps rich transcript semantics out of Phase 4.
- Preview data remains preview-only. Production detail data comes from
  `ThreadDetailStore` over a real `AppServerClient`.
- The optional real-host tests are gated by endpoint env, so the normal unit
  suite stays fast while the acceptance path remains executable.

## Risk Notes

- `ThreadEventNormalizer` is deliberately conservative. Some future Codex item
  shapes may render as `unknown` until Phase 5/6 expands richer cards. That is
  acceptable because unsupported events remain visible instead of disappearing.
- Server requests are surfaced but not answerable yet. This is a Phase 5
  boundary, not a Phase 4 bug, but Phase 5 must add response plumbing through
  the relay instead of opening a second protocol path.
- Relay `thread/resume` keeps one upstream session per downstream WebSocket.
  That matches one open detail view. If Phase 6 adds multi-host or multiple
  simultaneous detail surfaces, session lifecycle and fan-out should be
  revisited.
- Detail UI currently displays transcript cards in a straightforward vertical
  list. If command output grows large, Phase 5/8 may need collapse/expand
  affordances, but Phase 4 has no evidence of layout breakage in the simulator
  proof.

## Approval Bar

Approved with notes. The implementation meets the real-host requirement: a
phone-reachable relay reads and resumes a real Codex thread, the app opens a
real Dock row into detail on the `iPhone 17` simulator, normalized events render
without raw JSON, and the connection keeps accepting notifications/server
requests. No production mocks or unsupported Codex daemon assumptions were
introduced.
