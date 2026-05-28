# Codex Dock Phase 8 Worklog

Date: 2026-05-28

Plan: `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_08_VOICE_ACCESSIBILITY_FINAL_POLISH_2026-05-27.md`

Status: complete

## Summary

Phase 8 finishes the V1 MVP polish surface:

- In-place hold/release voice dictation in the existing thread composer.
- OpenAI transcription behind a narrow service boundary.
- Transcript insertion into the editable draft with explicit manual Send.
- Microphone permission, recording, transcription, and no-speech errors surfaced
  in composer state.
- Accessibility and Dynamic Type hardening across Dock, Archive, Hosts, and the
  thread composer.
- Final real-host Dock filter correction discovered during acceptance:
  `Running` now means loaded live sessions, not only an actively streaming turn.
- Final real-host thread-detail correction discovered during acceptance:
  large live threads now use paged `thread/turns/list` plus compact resume
  instead of a multi-megabyte single WebSocket response.

Out of V1:

- No voice auto-submit.
- No separate voice screen.
- No AIMGR, Rotate, AI Manager, or account-switching implementation.

## OpenAI Provider Grounding

Official OpenAI docs checked on 2026-05-28:

- Speech-to-text guide:
  `https://platform.openai.com/docs/guides/speech-to-text?lang=curl`
- Audio transcription API reference:
  `https://platform.openai.com/docs/api-reference/audio/createTranscription.class`
- `gpt-4o-transcribe` model page:
  `https://platform.openai.com/docs/models/gpt-4o-transcribe`

Implementation matches the documented shape used for completed audio files:

- Endpoint: `POST https://api.openai.com/v1/audio/transcriptions`.
- Model default: `gpt-4o-transcribe`.
- File type: `.m4a`, a supported upload type.
- Response format: `json`, which the API reference lists as the supported
  response format for `gpt-4o-transcribe`.

## Implemented

Voice:

- Added `CodexDock/Voice/VoiceCaptureController.swift`.
- Added `CodexDock/Voice/TranscriptionService.swift`.
- Added `NSMicrophoneUsageDescription`.
- Added `OPENAI_API_KEY` and `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL` app launch
  wiring through `rtk make app`.
- Preserved existing `.env` key values without printing them.
- Added composer voice state, recording/transcribing phases, and inline
  recording/error labels.
- The mic button is a 44pt hit target with `Hold to dictate` accessibility
  label.
- Transcribed text appends into the existing draft and never sends
  automatically.

Final Dock/live fixes:

- `DockFilter.running` now includes loaded live row states:
  `needsMe`, `running`, `idle`, and `failed`.
- All sections and rows now sort by live status priority before timestamp, so
  loaded live rows are not buried by newer stored `Limited` history.
- `Needs me` remains strict: only real app-server attention flags or replayed
  pending requests can populate it.

Large thread detail fix:

- Added typed `thread/turns/list` support.
- Added `excludeTurns` to typed `thread/resume` params.
- Relay now forwards `thread/turns/list` to the real owning upstream app-server.
- Thread detail now loads:
  - `thread/read includeTurns:false`
  - `thread/turns/list limit:10`
  - `thread/resume excludeTurns:true`
- This keeps the view on the real live thread while avoiding oversized iOS
  WebSocket messages.

Accessibility / visual polish:

- Replaced oversized text header buttons with fixed icon hit targets where the
  label could overflow.
- Fixed host summary icon sizing and text layout priority.
- Added fixed-size status badges where Dynamic Type could create bad wrapping.
- Checked Dock, Archive, and Hosts at `accessibility-extra-large`.

## Real-Host Evidence

Phone-reachable relay:

- Endpoint: `ws://192.168.50.117:4510`.
- Raw history app-server behind relay: `ws://127.0.0.1:4500`.
- Host: `Amir-M5`.
- Simulator: `iPhone 17`,
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.

Final relay probe:

```json
{
  "rows": 108,
  "loadedIDs": 19,
  "counts": {
    "idle": 19,
    "active": 1,
    "notLoaded": 88
  },
  "mappedRunning": 20,
  "needs": 0
}
```

Large-thread payload evidence:

- Failing real thread: `019e6c01-7f74-7460-a3d7-d35e32b41162`.
- Old `thread/resume` without `excludeTurns`: about `2.4 MB`.
- New compact `thread/resume excludeTurns:true`: about `1.1 KB`.
- `thread/turns/list limit:10` for a loaded thread returned a bounded real
  page and kept detail rendering live.

## Verification

Commands run:

```sh
rtk swift test
rtk npm run test:relay
rtk node --check scripts/dock-relay.mjs
rtk make dock-relay-restart
rtk env CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=.codex-dock/app-server.token CODEX_DOCK_REAL_HOST_ID=Amir-M5 CODEX_DOCK_REAL_HOST_NAME=Amir-M5 swift test --filter AppServerClientTests/testPhoneReachableRealHost
rtk make app SIM='iPhone 17'
rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' -derivedDataPath .codex-dock/DerivedData
rtk rg "AIMGR|Rotate|account switching|AI Manager" CodexDock CodexDockApp scripts -n
rtk rg "auto-submit|separate voice screen|blue recording" CodexDock CodexDockApp -n
rtk rg "OPENAI_API_KEY|audioFile|recording\\.m4a|transcript|raw audio|server body|print\\(|NSLog|os_log|Logger" CodexDock CodexDockApp Makefile project.yml -n
rtk xcrun simctl ui BAD95C8E-3E57-4818-9B90-E4ED22593B4B content_size accessibility-extra-large
rtk xcrun simctl ui BAD95C8E-3E57-4818-9B90-E4ED22593B4B content_size large
rtk git diff --check
```

Results:

- SwiftPM tests passed: 72 tests, 5 optional live-host tests skipped.
- Relay unit tests passed: 5 tests.
- Relay syntax check passed.
- Relay was restarted and left running with `thread/turns/list` forwarding.
- Real phone-reachable host smoke tests passed: handshake, `thread/list`,
  compact detail read, paged turns, and compact resume.
- App build/install/launch passed on canonical `iPhone 17`.
- Xcode simulator tests passed on canonical `iPhone 17`.
- V1 implementation code contains no AIMGR/Rotate/account-switching
  integration.
- V1 implementation code contains no auto-submit, separate voice screen, or
  blue recording screen.
- Secret/log review found expected key/transcript variable names only; no
  logging calls print API keys, transcripts, raw audio paths, or OpenAI server
  bodies.
- Whitespace check passed.

## Screenshots

- Voice permission prompt:
  `/tmp/codex-dock-phase8-voice-after-release.png`.
- Voice denied inline error:
  `/tmp/codex-dock-phase8-voice-denied.png`.
- All with live rows first:
  `/tmp/codex-dock-root-cause-latest.png`.
- Running populated by real loaded rows:
  `/tmp/codex-dock-root-cause-running-tab-correct.png`.
- Needs me empty for the correct real-data reason:
  `/tmp/codex-dock-root-cause-needs-me-tab.png`.
- Large live row opens after compact detail fix:
  `/tmp/codex-dock-after-detail-fix-open-row.png`.
- Dynamic Type Dock:
  `/tmp/codex-dock-phase8-dynamic-type-dock-fixed.png`.
- Dynamic Type Archive:
  `/tmp/codex-dock-phase8-dynamic-type-archive-fixed.png`.
- Dynamic Type Hosts:
  `/tmp/codex-dock-phase8-dynamic-type-hosts-fixed.png`.
- Final normal-size Dock:
  `/tmp/codex-dock-phase8-final-large-dock.png`.

## Services Left Running

- Raw history app-server: `ws://192.168.50.117:4500`, pid `93066`.
- Dock relay: `ws://192.168.50.117:4510`, pid `59922`.
- iPhone 17 app process: `com.aelaguiz.CodexDockApp`, latest launch pid
  `7711`.
