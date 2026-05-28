# Phase 8 Thermonuclear Code Quality Review

Date: 2026-05-28

Scope: Phase 8 voice capture/transcription, composer integration, accessibility
polish, Dock live-row filter correction, compact thread detail path, relay
support, tests, and docs.

Verdict: pass with two non-blocking maintainability items.

## Blocking Findings

None.

## Non-Blocking Findings

1. Thread detail uses one bounded historical page before live updates.
   - Severity: non-blocking.
   - Why it matters: users cannot page older history yet from the iPhone detail
     view.
   - Why it is acceptable now: the plan requires real detail opening, real
     normalized events, and live updates. A bounded page plus live resume meets
     that, and it fixes a real `Message too long` failure without inventing a
     custom payload slicer.
   - Required follow-up: add older-history pagination only if post-MVP detail
     depth needs it.

2. `AppServerClientTests.swift` remains oversized.
   - Severity: non-blocking.
   - Why it matters: protocol tests are accumulating in one file.
   - Why it is acceptable now: the file was already over 1k lines before this
     phase (`1178` lines at `HEAD`), and Phase 8 adds a small same-family
     protocol test rather than crossing the 1k threshold.
   - Required follow-up: split app-server protocol tests by method family when
     the protocol surface expands again.

## Code-Quality Assessment

Voice:

- `VoiceCaptureController` is a narrow platform boundary around permission,
  recording, cancellation, and temp-file cleanup.
- `TranscriptionService` is the right provider boundary. OpenAI endpoint,
  model, key lookup, multipart construction, response decode, and provider
  errors are isolated from SwiftUI.
- The transcription client does not log API keys, transcript text, audio paths,
  or OpenAI response bodies.
- `ThreadDetailStore` owns voice state because the composer already lives
  there. That avoids a separate voice state tree or parallel send path.
- `ComposerView` remains a small view over existing store state. Voice is a
  hold/release control beside the text field, not a second screen.
- Send gating is simple: busy voice capture/transcription disables send.

Dock/live-row correction:

- `DockFilter.running` now matches the product meaning of the tab: loaded live
  sessions, including idle-but-loaded Codex threads.
- `SessionRowProjector` centralizes status priority sorting. That is the right
  owner because Dock and Archive already share projected row models.
- `Needs me` remains strict and data-backed. No invented status or fake row was
  added to satisfy a UI expectation.

Compact thread detail:

- The strongest code-judo move was to use Codex's own `thread/turns/list` and
  `thread/resume excludeTurns:true`.
- This deletes the need for a custom relay chunking protocol, WebSocket-size
  tuning, local caching, or fake truncated thread objects.
- The relay's `thread/turns/list` forwarding is small and routes through the
  same endpoint-selection helper used by read/resume/archive, so it does not
  introduce a parallel ownership model.
- `ThreadDTO.replacingTurns(_:)` is a pragmatic immutable-copy helper. It is
  slightly verbose because `ThreadDTO` is a plain value DTO with many fields,
  but it keeps turn grafting explicit and typed.

Accessibility / polish:

- Header action buttons were simplified to fixed icon targets instead of
  oversized text pills that broke under Dynamic Type.
- Host row icons and badges use stable dimensions so large text does not resize
  the layout unpredictably.
- The remaining large-type screenshots show scale pressure, but not incoherent
  overlap in the key Dock, Archive, or Hosts screens.

## Architecture Review

The implementation keeps the main ownership lines clean:

- OpenAI transcription is only a text producer.
- The composer remains the only user-input draft owner.
- Explicit Send remains the only submit path.
- The app-server remains the source of thread state.
- The relay remains a phone-reachable router over real Codex JSON-RPC methods.
- No local mock row source, fake attention status, or fallback app-server path
  was introduced.
- No AIMGR, Rotate, separate voice screen, auto-submit, or account switching
  code was introduced.

The main structural improvement beyond voice is the compact thread-detail path.
It uses a supported server API to avoid giant payloads and preserves the live
resume stream. That is better than raising transport limits or adding a custom
payload transformation layer.

## Drift And Side-Door Review

- `Makefile` writes and launches the same OpenAI model/key env surface without
  printing the key.
- `project.yml` and `Info.plist` both include the microphone permission text.
- `scripts/dock-relay.mjs` now supports the same thread detail method family as
  the Swift client: read, turns list, resume, turn start/steer.
- Direct raw `:4500` history endpoint still exists because the relay needs it,
  but the app launch path prints and uses `:4510`.
- V1 scope exclusions were searched in implementation code and remained absent.

## Verification Context

Verification reported in the worklog:

- `rtk swift test` passed 72 tests with 5 optional live-host tests skipped.
- `rtk npm run test:relay` passed 5 tests.
- `rtk node --check scripts/dock-relay.mjs` passed.
- `rtk make dock-relay-restart` restarted the phone-reachable relay.
- Explicit real phone-reachable smoke test passed through
  `ws://192.168.50.117:4510` for handshake, list, compact detail read, paged
  turns, and compact resume.
- `rtk make app SIM='iPhone 17'` built, installed, and launched the app on
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp
  -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath
  .codex-dock/DerivedData` passed.
- `rtk git diff --check` passed.
- Screenshots:
  - `/tmp/codex-dock-phase8-voice-after-release.png`
  - `/tmp/codex-dock-phase8-voice-denied.png`
  - `/tmp/codex-dock-root-cause-running-tab-correct.png`
  - `/tmp/codex-dock-root-cause-needs-me-tab.png`
  - `/tmp/codex-dock-after-detail-fix-open-row.png`
  - `/tmp/codex-dock-phase8-dynamic-type-dock-fixed.png`
  - `/tmp/codex-dock-phase8-dynamic-type-archive-fixed.png`
  - `/tmp/codex-dock-phase8-dynamic-type-hosts-fixed.png`
  - `/tmp/codex-dock-phase8-final-large-dock.png`

## Final Judgment

Phase 8 is structurally acceptable. The implementation deepens the existing
composer instead of adding a separate voice product path, uses a narrow OpenAI
provider boundary, keeps secrets and transcripts out of logs, fixes real live
Dock filtering and oversized detail payloads without mocks, and leaves the app
running against the real phone-reachable relay. Commit it.
