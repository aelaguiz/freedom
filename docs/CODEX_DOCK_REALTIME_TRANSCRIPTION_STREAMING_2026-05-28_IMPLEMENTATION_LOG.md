# Codex Dock Realtime Transcription Streaming - Implementation Log

Date: 2026-05-28
Status: active
Parent: `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`

## Resume Snapshot

- Current slice: Realtime closeout is marked passed for the current installed build, and future physical-device checks are deferred manual QA rather than implementation blockers.
- Physical-device note: the top-level dock program records `iPhone 14` as the physical target for this work. For current visual proof, the user approved a non-Pro simulator fallback when the physical-device WebDriverAgent path blocks. As of 2026-05-28, missing physical-device testing must not block further implementation; use simulator/local/real-relay proof and add physical checks to Amir's deferred list.
- OpenAI source check: official docs and live probing confirm server-side WebSocket Realtime is the right backend path for keeping the standard API key on the relay. Current Realtime transcription uses upstream URL `wss://api.openai.com/v1/realtime?intent=transcription`, no `model=` URL query, `type: "transcription"`, `gpt-realtime-whisper` inside `session.audio.input.transcription.model`, 24 kHz mono `audio/pcm`, `input_audio_buffer.append`, manual `input_audio_buffer.commit`, and delta/completed transcription events.
- Evidence rule from user: mock/fake-upstream tests and fake Swift transcription sessions are preflight coverage only. They do not count as acceptance proof by themselves. Realtime now has real relay-to-OpenAI Realtime proof, user-confirmed basic physical iPhone 14 audio proof, and the detailed physical checklist marked passed by user manual check on 2026-05-28.

## Phase 0 - Prerequisite Readback

Result: satisfied for starting the relay slice.

- `CodexDock/State/AppConnectivityStore.swift` exists as the app-wide connectivity rollup.
- `CodexDock/State/AppLifecycleCoordinator.swift` exists as the root-owned lifecycle state owner.
- `CodexDock/Features/Dock/DockView.swift` has root-owned `runDockRefreshLoop()` and no old tab-local `runRefreshLoop()` implementation.
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift` and `CodexDock/Features/Dock/DockView.swift` forward SwiftUI scene phase changes into the lifecycle coordinator.
- `CodexDock/State/ThreadDetailStore.swift` receives `AppLifecycleCoordinator?` and handles lifecycle snapshots through the existing Connectivity path.
- Realtime Phase 1 is relay-only and does not add any app lifecycle, `scenePhase`, reconnect, or connectivity authority.

## Phase 1 - Relay Contract Scope

Result: code-complete for the relay-only slice. At this checkpoint, acceptance proof was still pending; later sections record real relay/OpenAI proof and physical manual closeout.

- Added purpose-specific relay JSON-RPC methods:
  - `audio/transcription/start`
  - `audio/transcription/append`
  - `audio/transcription/commit`
  - `audio/transcription/cancel`
- Added `scripts/dock-relay-realtime-transcription.mjs` as the relay-owned Realtime session manager.
- Kept phone-supplied provider controls forbidden: no model, endpoint, headers, API key, client secret, or raw upstream event proxy.
- Kept `OPENAI_API_KEY` Mac-side in `scripts/dock-relay.mjs`; the phone only gets the narrow session/audio control API.
- Configured upstream Realtime transcription as `type: "transcription"`, `gpt-realtime-whisper`, `audio/pcm`, 24 kHz, relay-owned language/delay, and optional server-side `OpenAI-Safety-Identifier`.
- Added fake-upstream relay tests for start, append, commit, delta accumulation, completed, failed, canceled, closed, downstream cleanup, provider override rejection, chunk bounds, ordering, and redaction. These are preflight tests only; they do not count as real acceptance proof.
- Left the existing one-shot `audio/transcribe` path in place for now. It is still scheduled for Phase 5 cutover deletion/rejection; Phase 1 only adds and proves the new relay contract.

Changed files:

- `scripts/dock-relay-realtime-transcription.mjs`
- `scripts/dock-relay-realtime-transcription.test.mjs`
- `scripts/dock-relay.mjs`
- `package.json`

## Phase 2 - Store-Owned Streaming Draft Reconciliation

Result: code-complete for the Swift store/composer state-machine slice. At this checkpoint, acceptance proof was still pending because this phase used fake streaming sessions; later sections record real relay/OpenAI proof and physical manual closeout.

- Added Swift Realtime transcript event/session contracts for started, delta, completed, failed, canceled, and closed events.
- Added future live-audio chunk/capture protocol shape for 24 kHz mono PCM chunks without wiring microphone capture yet.
- Expanded `ComposerVoicePhase` to `idle`, `starting`, `streaming`, and `finalizing`.
- Added active voice metadata to `ComposerVoiceState`: session id, active segment id, provisional transcript, final transcript, and last error.
- Moved draft reconciliation into `ThreadDetailStore`: cumulative `partialText` replaces only the active provisional segment, final transcript replaces the same segment, typed prefix text is preserved, explicit cancel/view close removes the provisional segment, recoverable failures freeze visible partial text, and app background uses the existing `AppLifecycleCoordinator` path.
- Locked user edits while voice is active and kept Send disabled/manual during active dictation.
- Removed the automatic store fallback to one-shot `audio/transcribe`; the default Phase 2 production voice path now fails visibly with `Realtime transcription is not connected yet.` until Phase 3 wires the relay-backed streaming client.
- Updated `ComposerView` for starting/listening/finalizing voice phases and disabled text editing while active dictation is in progress.
- Replaced one-shot file transcription tests with fake streaming-session preflight tests for partial replacement, final replacement, typed prefix preservation, edit lock, explicit cancel, close cleanup, failure before/after partial, commit failure, app background, startup failure, Send gating, and visible default failure.

Changed files:

- `CodexDock/Voice/TranscriptionService.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/Features/Session/ComposerView.swift`
- `CodexDockTests/ThreadDetailStoreTestSupport.swift`
- `CodexDockTests/ThreadDetailStoreTests.swift`
- `CodexDockTests/ThreadDetailStoreLifecycleTests.swift`

## Phase 3 - Swift Relay Client Integration With Synthetic Audio

Result: code-complete for the typed Swift relay-client slice. At this checkpoint, acceptance proof was still pending because tests used scripted relay notifications and no real OpenAI Realtime session; later sections record real relay/OpenAI proof and physical manual closeout.

- Added typed app-to-relay Realtime transcription DTOs for `audio/transcription/start`, `append`, `commit`, `cancel`, and relay notifications for `delta`, `completed`, `failed`, `canceled`, and `closed`.
- Added typed `AppServerClient` wrappers for the Realtime transcription methods. Raw JSON-RPC helpers remain transport primitives, but production voice code now uses typed wrappers.
- Added `RelayRealtimeTranscriptionClient`, which owns a separate app-to-relay `AppServerClient` connection, connects to the selected `DockHostConfiguration`, passes optional `host.bearerToken`, starts a relay transcription session, appends bounded base64 audio chunks with sequence numbers, commits/cancels, maps relay notifications into the Phase 2 `RealtimeTranscriptionEvent` stream, enforces commit timeout failure, and closes its voice connection on completion/failure/cancel.
- Switched `ThreadDetailStore` default voice construction to `RelayRealtimeTranscriptionClient(host:)`. It no longer constructs `RelayTranscriptionClient` or `audio/transcribe` as an automatic fallback.
- Added scripted Swift tests proving typed method shapes, no phone-supplied provider config fields, relay delta/final notification mapping, out-of-session event filtering, commit timeout failure, cancel cleanup, and store draft reconciliation from the real relay client abstraction.
- At the Phase 3 checkpoint, live PCM capture was not implemented yet. Phase 4 owns microphone chunks, tap mode, accessibility polish, and real held-mic UX.

Changed files:

- `CodexDock/AppServer/AppServerMethods.swift`
- `CodexDock/AppServer/AppServerClient.swift`
- `CodexDock/AppServer/RealtimeTranscriptionDTO.swift`
- `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDockTests/AppServerClientTests.swift`
- `CodexDockTests/ThreadDetailStoreTests.swift`

## Phase 4 - Live PCM Capture, Store Audio Forwarding, And Accessible Controls

Result: code-complete for the live capture/audio-forwarding/tap-control slice. Standalone real relay-to-OpenAI Realtime proof now passes with Mac-side `OPENAI_API_KEY` sourced from the user-owned `.env` into generated `.codex-dock/service.env` without modifying `.env`. The installed-app/manual physical iPhone 14 audio path passed after the empty-transcript relay fix, and the detailed manual checklist was later marked passed by user manual check. Physical UI readback remains blocked by WebDriverAgent, so future physical UI checks are deferred manual QA rather than implementation blockers.

- Added `LiveVoiceCaptureController`, which uses `AVAudioEngine` on iOS, configures `AVAudioSession` for spoken dictation, converts input buffers into 24 kHz mono PCM16 chunks, and emits `VoiceAudioChunk` values.
- Wired `ThreadDetailStore` to start live capture after the realtime session starts, forward each chunk into `RealtimeTranscriptionSession.appendAudio(...)`, stop capture before commit on release, and cancel capture on explicit cancel, close, app background, append failure, or relay terminal events.
- Fixed the hold-release cleanup risk by keeping the mic control enabled through `.starting` and `.finalizing`; `ThreadDetailStore` still guards duplicate starts, and release can still call `finishVoiceCapture()`.
- Added `ComposerVoiceInteractionMode` and `ThreadDetailStore.toggleTapVoiceCapture()` so tap-to-start/tap-to-stop dictation uses the same live relay-backed session path as hold dictation.
- Made `finishVoiceCapture(interactionMode:)` mode-scoped so a stale hold-release callback cannot finalize an active tap dictation session.
- Added client-side chunk validation in `RelayRealtimeTranscriptionClient`: empty chunks and chunks above the configured max are rejected before any base64 request is sent; accepted append sequence must match the requested sequence.
- Added route/interruption cleanup for live capture: audio interruptions and route changes that make the old device unavailable finish the active capture stream, remove observers, close the emitter, stop the engine, and deactivate the audio session.
- Added UI-facing composer presentation coverage for the hold and tap controls: labels, hints, disabled states, status text, finalizing state, and icon state.
- Added fake-capture and scripted-relay tests proving store audio forwarding, append request shape, hold/tap lifecycle idempotence, tap stop while starting, mode-scoped finish, unexpected capture stream failure handling, local chunk bounds, and no `audio/transcribe` fallback. These are preflight tests only; they do not count as real microphone, relay, or OpenAI acceptance proof.
- Earlier installed-app fallback proof showed the thread detail UI rendered both `Hold to dictate` and `Start dictation` against the real relay-backed host path, and tapping `Start dictation` failed through the real relay with `OpenAI Realtime transcription key is not configured on the relay`.
- Later closeout status: real relay-to-OpenAI Realtime proof, manual held-mic proof, manual tap-mode proof, and manual accessibility checklist coverage are recorded as passed or user-checked below.

Changed files:

- `CodexDock/Voice/VoiceCaptureController.swift`
- `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/Features/Session/ComposerView.swift`
- `CodexDockTests/AppServerClientTests.swift`
- `CodexDockTests/ComposerVoiceControlsPresentationTests.swift`
- `CodexDockTests/ThreadDetailStoreTestSupport.swift`
- `CodexDockTests/ThreadDetailStoreTests.swift`
- `project.yml`
- `CodexDockApp/Info.plist`

## Proof Ledger

- Passed: `node --check scripts/dock-relay-realtime-transcription.mjs`
- Passed: `node --check scripts/dock-relay-realtime-transcription.test.mjs`
- Passed: `node --check scripts/dock-relay.mjs`
- Preflight only: `node --test scripts/dock-relay-realtime-transcription.test.mjs` - 8 tests, 0 failures.
- Preflight only: `rtk npm run test:relay` - 41 tests, 0 failures.
- Passed: `rtk git diff --check -- scripts/dock-relay.mjs scripts/dock-relay-realtime-transcription.mjs scripts/dock-relay-realtime-transcription.test.mjs package.json docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md`.
- Preflight only: `rtk swift test --filter ThreadDetailStoreTests` - 39 tests, 0 failures.
- Preflight only: `rtk swift test` - 156 tests, 5 skipped, 0 failures.
- Preflight only: `rtk swift test --filter AppServerClientTests` - 44 tests, 5 skipped, 0 failures.
- Preflight only: `rtk swift test --filter ThreadDetailStoreTests` - 40 tests, 0 failures.
- Preflight only: `rtk swift test --filter ThreadDetailStoreTests` - 42 matching tests, 0 failures.
- Preflight only: `rtk swift test --filter AppServerClientTests` - 45 tests, 5 skipped, 0 failures.
- Preflight only: `rtk swift test` - 164 tests, 5 skipped, 0 failures.
- Preflight only: `rtk npm test` - 42 tests, 0 failures.
- Passed: `rtk xcodegen generate --spec project.yml`.
- Not passed before regeneration: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` failed because `CodexDock.xcodeproj` had not been regenerated after adding `CodexDock/AppServer/RealtimeTranscriptionDTO.swift`, so Xcode could not find the new DTO types.
- Not passed before iOS concurrency fix: the same Xcode build then failed in `CodexDock/Voice/VoiceCaptureController.swift` because Swift 6 treated non-Sendable `AVAudioEngine` access in cleanup as an iOS build error; fixed by importing AVFoundation as `@preconcurrency`.
- Passed: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Passed: `rtk git diff --check -- CodexDock.xcodeproj/project.pbxproj CodexDock/Voice/VoiceCaptureController.swift CodexDock/Voice/RelayRealtimeTranscriptionClient.swift CodexDock/State/ThreadDetailStore.swift CodexDock/Features/Session/ComposerView.swift CodexDockTests/AppServerClientTests.swift CodexDockTests/ThreadDetailStoreTests.swift CodexDockTests/ThreadDetailStoreTestSupport.swift docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_PLAN_AUDIT.md docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_THERMONUCLEAR_REVIEW.md`.
- Passed: `rtk git diff --check -- CodexDock/Voice/TranscriptionService.swift CodexDock/State/ThreadDetailStore.swift CodexDock/Features/Session/ComposerView.swift CodexDockTests/ThreadDetailStoreTests.swift CodexDockTests/ThreadDetailStoreLifecycleTests.swift CodexDockTests/ThreadDetailStoreTestSupport.swift`.
- Passed: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Not passed: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build` failed because no simulator exists with exact name `iPhone 17`. Available non-Pro fallback is `feat_anim_1 - iPhone 17` with UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Physical iPhone 14 smoke: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed `com.aelaguiz.CodexDockApp` on the physical device after starting services; `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` launched the app; `rtk xcrun devicectl device info processes --device 00008110-000E04940240A01E | rg -n "CodexDock|com\\.aelaguiz\\.CodexDockApp"` showed process `4386` before Phase 4 and process `4426` after the Phase 4 live-capture build/install.
- Physical service status after Phase 4 install/launch: `rtk make app-server-status` returned app-server pid `93066` healthy at `ws://192.168.50.117:4500`; `rtk make dock-relay-status` returned relay pid `92808` healthy at `ws://192.168.50.117:4510`, `phone auth: none`.
- Physical iPhone 14 Mobile MCP blocker: `mobile_list_elements_on_screen` and `mobile_take_screenshot` on `00008110-000E04940240A01E` both returned `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
- User-approved non-Pro simulator fallback smoke: `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` launched `com.aelaguiz.CodexDockApp: 5460` before Phase 4 and `com.aelaguiz.CodexDockApp: 99513` after Phase 4; Mobile MCP element readback on that simulator showed the real Dock app connected to `ws://192.168.50.117:4510` with live Dock rows and latest-message row summaries.
- User-approved non-Pro simulator fallback screenshot: `/tmp/codex-client/20260528T161315Z/realtime-phase4-smoke/001_dock_connected_fallback.png`.
- Preflight only: `rtk swift test --filter ComposerVoiceControlsPresentationTests` - 4 tests, 0 failures.
- Preflight only: `rtk swift test --filter ThreadDetailStoreTests` - 49 tests, 0 failures.
- Preflight only: `rtk swift test` - 175 tests, 5 skipped, 0 failures.
- Preflight only: `rtk npm test` - 42 tests, 0 failures.
- Passed: `rtk xcodegen generate --spec project.yml`.
- Not passed before iOS actor-isolation fix: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` failed in `CodexDock/Voice/VoiceCaptureController.swift` because route/interruption cleanup called main-actor-isolated capture cleanup from nonisolated notification/deinit contexts.
- Passed after fix: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Passed service status before physical install: `rtk make app-server-status` returned app-server pid `93066` healthy at `ws://192.168.50.117:4500`; `rtk make dock-relay-status` returned relay pid `98542` healthy at `ws://192.168.50.117:4510`, `phone auth: none`.
- Physical iPhone 14 install/launch after tap-control build: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed `com.aelaguiz.CodexDockApp`; `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` launched it; process listing showed pid `4434`.
- Physical iPhone 14 Mobile MCP blocker after tap-control build: `mobile_list_elements_on_screen` and `mobile_take_screenshot` on `00008110-000E04940240A01E` both returned `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
- User-approved non-Pro simulator fallback after tap-control build: `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` launched `com.aelaguiz.CodexDockApp: 49381`; Mobile MCP showed the real Dock app connected to `ws://192.168.50.117:4510 · 206 sessions`.
- User-approved non-Pro simulator fallback thread-detail readback after tap-control build: Mobile MCP showed `Online: Thread live`, `Message`, `Hold to dictate`, `Start dictation`, and `Send` on the real relay-backed thread detail path.
- User-approved non-Pro simulator fallback screenshot for tap controls: `/tmp/codex-client/20260528T163230Z/realtime-phase4-tap-controls-fallback.png`.
- User-approved non-Pro simulator fallback negative relay-path proof: tapping `Start dictation` produced the installed-app/real-relay error `App-server rejected request: OpenAI Realtime transcription key is not configured on the relay`.
- User-approved non-Pro simulator fallback screenshot for missing-key relay error: `/tmp/codex-client/20260528T163230Z/realtime-phase4-missing-key-fallback.png`.
- Superseded blocker confirmation: an earlier check returned `OPENAI_API_KEY_PRESENT=0`. After the user restored `.env`, `rtk make env-file` reads `OPENAI_API_KEY` from `.env`, writes it only into `.codex-dock/service.env`, and leaves `.env` mtime unchanged at `1779986258`.
- Passed after Realtime endpoint fix: `rtk node --check scripts/dock-relay-realtime-transcription.mjs`.
- Passed after Realtime endpoint fix: `rtk node --check scripts/dock-relay.mjs`.
- Passed after Realtime endpoint fix: `rtk node --check scripts/dock-relay-realtime-transcription.test.mjs`.
- Preflight only: `rtk node --test scripts/dock-relay-realtime-transcription.test.mjs` - 8 tests, 0 failures.
- Preflight only: `rtk npm run test:relay` - 42 tests, 0 failures.
- Passed env preservation proof: `rtk make env-file` printed `wrote generated service env .codex-dock/service.env; left .env untouched`, `OPENAI_API_KEY_SOURCE=.env`, `SERVICE_ENV_OPENAI_API_KEY=present`, and `ENV_MTIME_UNCHANGED=1`.
- Passed service restart proof: `rtk make dock-relay` loaded relay pid `77655` at `ws://192.168.50.117:4510`, kept `phone auth: none`, and left `.env` mtime unchanged.
- Real relay-to-OpenAI proof passed: a local JSON-RPC client connected to `ws://192.168.50.117:4510`, called `audio/transcription/start`, streamed representative 24 kHz mono PCM through `audio/transcription/append`, committed, and received real OpenAI Realtime events through the relay. Redacted evidence: `PCM_BYTES=123920`, `FORMAT=audio/pcm`, `SAMPLE_RATE=24000`, `MODEL=gpt-realtime-whisper`, `LANGUAGE=en`, `DELAY=low`, `APPEND_OK=1`, `CHUNKS=3`, `COMMIT_OK=1`, `DELTA_COUNT=9`, `TERMINAL_METHOD=audio/transcription/completed`, `COMPLETED_TEXT_BYTES=47`, `COMPLETED_TEXT_SHA256=a49fef874c839fee25b98c117f0f266d2ae983fdcf0de808e974564019d655ee`, and `CLOSED_SEEN=1`. The proof did not print the API key, audio body, base64 body, or transcript text.
- Passed post-proof service status: `rtk make dock-relay-status` returned relay pid `77655` healthy at `ws://192.168.50.117:4510`, `phone auth: none`.
- Preflight only: `rtk swift test --filter ComposerVoiceControlsPresentationTests` - 4 tests, 0 failures.
- Installed simulator app-side smoke found a real crash before the simulator guard fix: tapping `Start dictation` on simulator `BAD95C8E-3E57-4818-E1F1C420C693` launched the Realtime path and the app exited to the home screen with `SIGTRAP`; simulator logs showed `BUG IN CLIENT OF LIBDISPATCH: Assertion failed: Block was expected to execute on queue [com.apple.main-thread]` immediately after `AVAudioEngine` startup. This was not counted as acceptance.
- Fixed the simulator crash path by keeping live voice capture/transcription stream observation on `MainActor` and by making `LiveVoiceCaptureController` fail visibly on simulator before `AVAudioEngine` input startup. The physical iPhone build still uses `AVAudioEngine`; the simulator guard is not voice acceptance evidence.
- Preflight only after crash fix: `rtk swift test --filter ThreadDetailStoreTests` - 49 tests, 0 failures.
- Preflight only after crash fix: `rtk swift test --filter ComposerVoiceControlsPresentationTests` - 4 tests, 0 failures.
- User-approved non-Pro simulator fallback after crash fix: `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` rebuilt, installed, and launched `com.aelaguiz.CodexDockApp: 37271` against `ws://192.168.50.117:4510`; `.env` mtime stayed unchanged. Mobile MCP opened a real relay-backed thread detail view, tapped `Start dictation`, and the app stayed open with visible error `Voice recording could not start.` Screenshot: `/tmp/codex-client/20260528T164200Z/realtime-real-openai/004_app_simulator_voice_recording_unavailable_no_crash.png`. This proves fail-visible installed-app behavior on the simulator, not successful voice acceptance.
- Physical iPhone 14 build/install/launch after crash fix: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed `com.aelaguiz.CodexDockApp`, left `.env` unchanged, and `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` launched it; process listing showed pid `4473`.
- Physical iPhone 14 UI readback after crash fix remains blocked: `mobile_list_elements_on_screen` on `00008110-000E04940240A01E` returned `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.
- Passed service status after physical install/launch: `rtk make dock-relay-status` returned relay pid `42468` healthy at `ws://192.168.50.117:4510`, `phone auth: none`.
- Passed: `rtk git diff --check`.
- Later closeout status: the installed app/client path has user-confirmed physical iPhone 14 audio proof and a user-checked manual checklist. Future physical checks after later voice changes are deferred manual QA under the parent dock operating rule.

## 2026-05-28 - Phase 5 Cutover Cleanup

- Removed production one-shot Swift transcription surfaces: `TranscriptionServicing`, `OpenAITranscriptionClient`, `OpenAITranscriptionConfiguration`, `RelayTranscriptionClient`, `AppServerMethods.audioTranscribe`, `AppServerClient.audioTranscribe(...)`, `AudioTranscribeParams`, `AudioTranscribeResponseDTO`, and `CodexDock/AppServer/AudioTranscriptionDTO.swift`.
- Removed old file-recording production capture surfaces: `VoiceCaptureControlling`, `VoiceCaptureController`, `VoiceCaptureError.notRecording`, and the dead m4a fake capture test helper. Production dictation now stays on `LiveVoiceCaptureControlling`.
- Removed relay one-shot transcription helper/config access: deleted `scripts/dock-relay-transcription.mjs`, removed old one-shot imports/exports/config from `scripts/dock-relay.mjs`, removed `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL` and `--openai-transcription-model` from `Makefile`, and added `CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY=low` to generated service env.
- Added relay test coverage proving raw JSON-RPC `audio/transcribe` is rejected after Realtime cutover with JSON-RPC `-32601`.
- Updated README, AGENTS.md, `project.yml`, the iPhone pairing plan/worklog, iPhone UX spec, Multi-host plan, and Phase 8 voice docs so they point to relay-owned Realtime dictation and mark completed-file/direct-OpenAI material as historical or superseded.
- Passed focused checks:
  - `rtk node --check scripts/dock-relay.mjs`
  - `rtk node --check scripts/dock-relay.test.mjs`
  - `rtk swift test --filter AppServerClientTests` - 43 tests, 5 skips, 0 failures.
  - `rtk npm run test:relay` - 38 tests, 0 failures.
- Passed final Phase 5 checks:
  - `rtk node --check scripts/dock-relay-realtime-transcription.mjs`
  - `rtk swift test --filter ThreadDetailStoreTests` - 49 tests, 0 failures after updating stale relay error expectations.
  - `rtk swift test` - 173 tests, 5 explicit real-host skips, 0 failures.
  - `rtk xcodegen generate --spec project.yml`
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`
  - `rtk git diff --check`
- Restarted the real relay with cutover code: `rtk make dock-relay`; final status showed pid `88873`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- Re-ran real relay-to-OpenAI proof through `ws://192.168.50.117:4510`: raw `audio/transcribe` rejected; Realtime session started with `MODEL=gpt-realtime-whisper`, `DELAY=low`; `APPEND_OK=1`, `CHUNKS=3`, `COMMIT_OK=1`, `DELTA_COUNT=10`, terminal `audio/transcription/completed`, `COMPLETED_TEXT_BYTES=48`, `COMPLETED_TEXT_SHA256=8e9c23af0bbe80abc5244e2094cb1475a8a28dd05457bc9a116ce2cac037e366`. No key, transcript text, raw audio, or base64 audio was printed.
- Simulator installed-app smoke passed: `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` built, installed, and launched `com.aelaguiz.CodexDockApp: 87615`.
- Physical iPhone 14 build/install passed: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed `com.aelaguiz.CodexDockApp` on the device.
- `.env` stayed untouched throughout: mtime remained `1779986258`.
- Physical Mobile MCP remains intentionally out of use for this slice. Later user manual testing closed the physical iPhone 14 checklist for the current installed build; future physical checks are deferred manual QA.

## 2026-05-28 - Physical iPhone 14 Voice Capture Stop Fix

- User physical iPhone 14 feedback after the prior install: hold dictation showed `Listening. Release to finalize.`, then stopped by itself with `Voice capture stopped. Try again.` / `Realtime transcription stopped.` This is a failed physical Realtime voice acceptance result.
- Diagnosis: `ThreadDetailStore` shows `Voice capture stopped. Try again.` only when the local live capture chunk stream ends while voice is still `.streaming`. The likely physical-device root cause was over-eager `AVAudioSession` notification cleanup in `LiveVoiceCaptureController`: route `.categoryChange` could finish capture during normal audio-session setup, which ended the chunk stream before the user released the hold control.
- Fix: added a small `VoiceCaptureSessionStopPolicy`; route `.categoryChange` and other non-input-loss route changes no longer stop capture, route `.oldDeviceUnavailable` still stops capture, interruption `.ended` no longer stops capture, and interruption `.began`/unknown/missing interruption type still stops capture.
- Added `VoiceCaptureControllerTests` for route/interruption stop policy.
- Added `ThreadDetailStoreTests.testHoldVoiceCaptureStreamEndWhileHeldFailsRecoverablyAndReleaseDoesNotCommit` to lock the user-reported failure mode: if capture really does end while the user is still holding, the store keeps the partial draft editable, cancels Realtime, does not commit, does not send, and a later hold-release does nothing.
- Passed focused checks:
  - `rtk swift test --filter VoiceCaptureControllerTests` - 5 tests, 0 failures.
  - `rtk swift test --filter ThreadDetailStoreTests` - 50 tests, 0 failures.
  - `rtk xcodegen generate --spec project.yml`.
  - `rtk git diff --check -- CodexDock/Voice/VoiceCaptureController.swift CodexDockTests/VoiceCaptureControllerTests.swift CodexDockTests/ThreadDetailStoreTests.swift`.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
  - `rtk swift test` - 179 tests, 5 explicit real-host skips, 0 failures.
  - `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`.
  - `rtk git diff --check`.
- Physical install/launch after fix: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed `com.aelaguiz.CodexDockApp`, left `.env` untouched, and `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` launched the patched app.
- Service status after fix: `rtk make dock-relay-status` returned relay pid `83502`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- Secret preservation after fix: `.env` mtime remained `1779986258`.
- Later closeout status: this retest requirement was superseded by the later user-confirmed physical iPhone 14 Realtime pass and manual checklist closeout.

## 2026-05-28 - Realtime Audio Observability Instrumentation

- Reviewed `docs/CODEX_DOCK_OBSERVABILITY_LOGGING_FRAMEWORK_2026-05-28.md` and used the implemented `DockLog` / relay logger framework for the physical iPhone 14 realtime-audio debug path.
- Instrumented `LiveVoiceCaptureController` with safe AVAudioSession and AVAudioEngine details: permission, active sample rate, input channel count, input availability, IO buffer duration, input/output `portType` values only, input format, route-change notifications, interruption notifications, stop decisions, emitted chunk count, emitted byte count, and capture duration. It still does not log route names, route UIDs, audio buffers, PCM samples, or base64 audio.
- Instrumented `ThreadDetailStore` voice orchestration with safe forwarding summaries and terminal context: stream start, deferred hold release while start is still in flight, append failures with sequence/byte/count totals, capture-stream end while still streaming, transcription event stream end, commit returning without a terminal event, stop/cancel requests, and forwarded chunk/byte totals. It still does not log composer draft text, partial text, final transcript, prompt text, or JSON-RPC payloads.
- Instrumented `RelayRealtimeTranscriptionClient` with connect-vs-start timing, append transport failures, accepted chunk/byte totals, zero-audio commit signal, commit failure context, terminal event context, completion timeout context, and final session totals. It still does not log the Swift `Data`, `base64Audio`, transcript fields, bearer tokens, or provider configuration.
- Instrumented `scripts/dock-relay-realtime-transcription.mjs` with relay-side realtime limits, append validation rejection reason codes, accepted chunk/byte totals, commit totals, upstream close code/reason byte length, upstream error type/code, ignored upstream event type, session failure totals, and session close totals. It still does not log raw audio, base64 audio, prompt text, transcript text, `OPENAI_API_KEY`, or bearer tokens.
- Added relay test coverage: `realtime transcription logs safe audio totals and limits` verifies sample rate/limits, accepted chunk and byte totals, commit totals, close totals, and absence of base64 audio/transcript text.
- Passed focused checks:
  - `rtk swift test --filter VoiceCaptureControllerTests` - 5 tests, 0 failures.
  - `rtk swift test --filter ThreadDetailStoreTests` - 50 tests, 0 failures.
  - `rtk swift test --filter AppServerClientTests` - 43 tests, 5 explicit real-host skips, 0 failures.
  - `rtk npm run test:relay` - 40 tests, 0 failures.
- Passed full and build checks:
  - `rtk swift test` - 182 tests, 5 explicit real-host skips, 0 failures.
  - `rtk git diff --check`.
  - `rtk xcodegen generate --spec project.yml`.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Physical iPhone 14 install/launch after instrumentation:
  - `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed `com.aelaguiz.CodexDockApp`.
  - `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` launched the app.
- Services after instrumentation:
  - `rtk make app-server-status` returned HTTP 200 OK at `ws://192.168.50.117:4500`.
  - `rtk make dock-relay-status` returned relay pid `57090`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- Physical logarchive capture remains blocked without root:
  - `rtk xcrun log collect --device-udid 00008110-000E04940240A01E --last 10m --predicate 'subsystem == "com.aelaguiz.CodexDock"' --output /tmp/codex-client/20260528T183720Z/codex-dock-device.logarchive`
  - Exact blocker: `log: Must be root to collect logs from attached device`.
- `.env` stayed untouched throughout the instrumentation pass; mtime remained `1779986258`.
- Physical Mobile MCP was not used. This retest requirement was later superseded by the user-confirmed physical iPhone 14 Realtime pass and manual checklist closeout.

## 2026-05-28 - Physical iPhone 14 Voice Tap Crash Fix

- User reported that tapping the voice transcript button crashed the physical iPhone app after the instrumentation install.
- Physical attached launch repro: `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing --console com.aelaguiz.CodexDockApp` returned `App terminated due to signal 5`.
- Relay evidence at the same time showed `audio/transcription/start` succeeded, then the downstream app socket closed before any `audio/transcription/append`; accepted audio totals stayed `acceptedChunks:0`, `acceptedBytes:0`.
- Local crash report evidence from the matching simulator path identified the crash as a Swift actor-isolation trap in `closure #1 in LiveVoiceCaptureController.startCapture()` on Apple's `RealtimeMessenger.mServiceQueue`. The `AVAudioEngine` tap callback was inheriting main-actor isolation and was being invoked from the realtime audio queue.
- Fix: moved the `AVAudioEngine` tap block creation into a non-actor top-level helper, so the realtime audio callback can call the locked `PCM16Mono24kChunkEmitter` without tripping Swift's main-actor executor check.
- Fix: changed `ThreadDetailStore.beginVoiceCapture` to start local live mic capture before opening the relay Realtime transcription session. If capture startup fails, the app now fails before creating an upstream relay session, making the failure boundary clearer and avoiding zero-audio relay sessions.
- Passed focused checks after the crash fix:
  - `rtk swift test --filter VoiceCaptureControllerTests` - 5 tests, 0 failures.
  - `rtk swift test --filter ThreadDetailStoreTests` - 50 tests, 0 failures.
  - `rtk xcodegen generate --spec project.yml`.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Name-based simulator build remained blocked because there is no simulator literally named `iPhone 17`; available matching simulator is `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`, name `feat_anim_1 - iPhone 17`.
- Physical iPhone 14 install after crash fix passed: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
- `.env` stayed untouched during the crash fix and install; mtime remained `1779986258`.
- Physical Mobile MCP was not used. This retest requirement was later superseded by the user-confirmed physical iPhone 14 Realtime pass and manual checklist closeout.

## 2026-05-28 - Physical iPhone 14 Empty Transcript Relay Fix

- User physical iPhone 14 feedback after the crash fix: tapping voice no longer crashed, but speaking `test test test` produced `Realtime transcription stopped` with no draft text.
- Relay evidence showed this was not a microphone permission failure. The physical phone session `a2f98ed8-28dd-4cad-815d-e42f2f7d9193` accepted `25` audio chunks and `120000` bytes before commit.
- Relay root cause: OpenAI returned `conversation.item.input_audio_transcription.completed` with an `item_id` but an empty transcript. The relay incorrectly classified that as `invalid_upstream_event`, emitted a failed event, and the app showed `Realtime transcription stopped`.
- Checked current official OpenAI Realtime transcription docs via the OpenAI developer docs MCP:
  - `gpt-realtime-whisper` is still the documented realtime transcription model.
  - `audio.input.format` with `type: "audio/pcm"` and `rate: 24000` is the documented shape.
  - `conversation.item.input_audio_transcription.completed` is the documented final transcript event.
- Fix: relay now treats an empty completed transcript with a valid item id as a completed-empty transcription instead of a protocol failure. The app path will surface this as `No speech was detected.` instead of `Realtime transcription stopped.`
- Added relay audio-level telemetry to distinguish silence from real speech without logging raw audio: per-append and session-level `peakAbs`, `rms`, `maxRms`, and `nonSilentChunks`. No PCM bytes, base64 audio, or transcript text is logged.
- Fixed the review-found stuck-state edge case: if the Swift transcription event stream ends while voice is busy and no terminal event arrived, `ThreadDetailStore` now cancels capture and fails dictation recoverably instead of leaving the composer locked.
- Added tests:
  - Relay test for empty upstream completion completing without protocol failure.
  - Relay test assertions for safe aggregate audio-level metrics.
  - Thread detail test for transcription event stream ending while busy.
- Passed checks after the empty-transcript fix:
  - `rtk node --check scripts/dock-relay-realtime-transcription.mjs && rtk node --check scripts/dock-relay-realtime-transcription.test.mjs`.
  - `rtk swift test --filter ThreadDetailStoreTests` - 51 tests, 0 failures.
  - `rtk npm run test:relay` - 41 tests, 0 failures.
  - `rtk xcodegen generate --spec project.yml`.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Restarted relay after the Node fix:
  - `rtk make dock-relay-restart` restarted the relay.
  - Final relay status after install: pid `92791`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- Installed and launched the fixed app on physical iPhone 14:
  - `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
  - `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`.
- `.env` stayed untouched during the empty-transcript fix and install; mtime remained `1779986258`.
- Physical Mobile MCP was not used. This retest requirement was later superseded by the user-confirmed physical iPhone 14 Realtime pass and manual checklist closeout; the relay audio-level metrics remain available for future deferred physical QA if needed.

## 2026-05-28 - Basic Physical iPhone 14 Realtime Audio Pass And Listening Color Fix

- User physical iPhone 14 retest after the empty-transcript relay fix: `Okay, that worked.` This is the first successful user-confirmed real phone-path Realtime audio result after the crash and empty-transcript failures.
- Scope of this evidence: basic physical Realtime voice path success on the installed iPhone 14 app against the relay-backed host path. The remaining detailed closeout checklist was later marked passed by user manual check below.
- UI follow-up from user: listening text looked error-like when red, so active listening/finalizing presentation now uses blue. Red remains reserved for actual composer or voice errors.
- Changed `CodexDock/Features/Session/ComposerView.swift` so the hold mic button tint, tap mic button tint, and `.streaming` listening status are blue.
- Focused verification after the color change:
  - `rtk swift test --filter ComposerVoiceControlsPresentationTests` - 4 tests, 0 failures.
  - `rtk git diff --check -- CodexDock/Features/Session/ComposerView.swift` passed.
- Physical iPhone 14 install/launch after the color change:
  - `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
  - `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`.
- Service status after the install:
  - `rtk make dock-relay-status` returned relay pid `25390`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- `.env` stayed untouched during the color fix and physical install; mtime remained `1779986258`.

## 2026-05-28 - Realtime Structural Cleanup Audit Pass

- Review cleanup after the basic physical iPhone 14 pass and blue listening UI found two size/ownership risks: `ThreadDetailStore.swift` had absorbed too much voice/composer machinery, and `scripts/dock-relay.mjs` had absorbed too much thread-list/read/archive aggregation.
- Split voice/composer state and voice-capture orchestration out of `CodexDock/State/ThreadDetailStore.swift` into `CodexDock/State/ThreadDetailStore+Voice.swift`. The core detail store is now `890` lines and the voice extension is `556` lines.
- Extracted relay thread data helpers from `scripts/dock-relay.mjs` into `scripts/dock-relay-thread-data.mjs`. The relay server/session owner is now `649` lines and the extracted thread-data helper is `657` lines.
- Fixed the extraction boundary found by targeted relay tests: `thread/resume` still needed `collectLiveRows`, `initializeClient`, `parseLimit`, and `JsonRpcWebSocketClient` available from the server module path.
- Structural cleanup verification passed:
  - `rtk node --check scripts/dock-relay.mjs`.
  - `rtk node --check scripts/dock-relay-thread-data.mjs`.
  - `rtk node --test scripts/dock-relay-phase5.test.mjs` - 14 tests, 0 failures.
  - `rtk npm run test:relay` - 41 tests, 0 failures.
  - `rtk npm test` - 41 tests, 0 failures.
  - `rtk swift test --filter ThreadDetailStoreTests` - 51 tests, 0 failures.
  - `rtk swift test --filter ComposerVoiceControlsPresentationTests` - 4 tests, 0 failures.
  - `rtk swift test` - 183 tests, 5 skipped, 0 failures.
  - `rtk xcodegen generate --spec project.yml`.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
  - `rtk git diff --check`.
- Physical iPhone 14 install/launch after the structural cleanup:
  - `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
  - `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`.
- Service status after install: `rtk make dock-relay-status` returned relay pid `3815`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- `.env` stayed untouched during the structural cleanup and physical install; mtime remained `1779986258`.
- This closes the code-shape audit finding. The remaining detailed manual iPhone 14 checklist evidence was later marked passed by user manual check below.

## Next Slice

- Do not treat Phase 1, Phase 2, Phase 3, or Phase 4 as accepted from mocks/fakes/fake capture chunks/scripted relay notifications.
- Realtime plan-backed implementation audit and thermonuclear review have passed for code shape and automated proof after the current physical-pass build.
- Realtime manual physical iPhone 14 closeout is marked passed by user manual check for the current installed build.
- Future voice/composer/capture/relay transcription changes should use simulator/local/real-relay proof for implementation and add a deferred physical retest item for Amir rather than blocking implementation on physical-device availability.

## 2026-05-28 - Physical iPhone 14 Manual Checklist Ready Install

- Purpose: make the remaining manual Realtime checklist test-ready on the physical `iPhone 14` without claiming any checklist row passed.
- Services before install:
  - `rtk make app-server-status` returned HTTP 200 OK for `ws://192.168.50.117:4500`, pid `93066`.
  - `rtk make dock-relay-status` returned readyz OK for `ws://192.168.50.117:4510`, pid `47401`, `phone auth: none`.
- Install:
  - `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
  - Result: passed; installed `com.aelaguiz.CodexDockApp` at `file:///private/var/containers/Bundle/Application/C417248B-5B77-4146-8E0F-E13040F78D62/CodexDockApp.app/`.
  - The install target regenerated `CodexDock.xcodeproj` from `project.yml`, wrote generated service env to `.codex-dock/service.env`, and left `.env` untouched.
- Launch:
  - `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`.
  - Result: passed.
  - Process proof: `rtk xcrun devicectl device info processes --device 00008110-000E04940240A01E | rg -n "CodexDock|com\\.aelaguiz\\.CodexDockApp"` showed `CodexDockApp` running as pid `4619`.
- Services after launch:
  - `rtk make app-server-status` returned HTTP 200 OK for `ws://192.168.50.117:4500`, pid `93066`.
  - `rtk make dock-relay-status` returned readyz OK for `ws://192.168.50.117:4510`, pid `27411`, `phone auth: none`.
- Secret hygiene:
  - `.env` mtime remained `1779986258`.
- Acceptance boundary:
  - This is install/launch readiness only. It does not satisfy held dictation, tap dictation, typed-prefix preservation, editable final draft, explicit Send/no auto-submit, cancel/interruption recoverability, accessibility labels/hints, hit targets, or Dynamic Type evidence.
  - The manual checklist rows were later marked passed by user manual check below, so Multi-host Phase 1B/Phase 2 is no longer gated on Realtime physical evidence.

## 2026-05-28 - Physical iPhone 14 Manual Closeout Passed By User Check

- User confirmed the remaining physical iPhone 14 manual checklist had already been checked and asked to mark it off in the docs.
- Evidence source: user manual physical test on the installed relay-backed app path. No physical Mobile MCP was used.
- Scope marked complete from user confirmation:
  - held dictation live partial;
  - held dictation final/edit/manual Send;
  - tap dictation live partial/finalization;
  - typed-prefix preservation;
  - cancel/interruption recoverability;
  - accessibility labels/hints;
  - hit targets and Dynamic Type layout.
- Acceptance boundary:
  - This closes the Realtime manual physical iPhone 14 closeout checklist for the current installed build.
  - Any later voice/composer/capture/relay transcription code change makes this physical checklist stale.
  - Per the 2026-05-28 parent dock operating rule, fresh physical checks are deferred manual QA for Amir while implementation proceeds with simulator/local/real-relay proof.

## Manual Physical iPhone 14 Closeout Checklist

Status: passed by user manual physical iPhone 14 check on 2026-05-28. The source checklist lives in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` under Phase 5 "Verification (required proof)"; this section is the evidence capture ledger for the Realtime physical closeout gate. The target device was physical `iPhone 14` `00008110-000E04940240A01E`, connected through the relay-backed host path at `ws://192.168.50.117:4510`. Physical Mobile MCP was intentionally not used because WebDriverAgent is not running on the device; Amir manual testing was the proof source.

Prerequisites before running the checklist:

- `rtk make services` is healthy.
- The physical iPhone app is the current installed build.
- The app is connected to the Dock relay, not directly to raw `:4500`.
- `.env` remains user-owned and is not edited; `OPENAI_API_KEY` stays Mac-side.

| Item | Manual action | Passing evidence to record | Status |
| --- | --- | --- | --- |
| Held dictation live partial | Open a real thread detail, press and hold `Hold to dictate`, speak a normal sentence. | Text appears in the existing `Message` composer before releasing the hold control. | passed by user manual check |
| Held dictation final/edit/send | Release `Hold to dictate` after live text appears. Edit the resulting draft, then tap `Send` manually only after confirming the draft. | Final text remains editable; no Codex turn submits until `Send` is tapped. | passed by user manual check |
| Tap dictation live partial | Tap `Start dictation`, speak a normal sentence, then tap `Stop dictation`. | Live text appears while speaking; stopping finalizes into the same editable composer draft. | passed by user manual check |
| Typed-prefix preservation | Type a prefix into `Message`, then run held or tap dictation. | The typed prefix survives partial and final reconciliation; dictated text does not replace unrelated typed text. | passed by user manual check |
| Cancel/recoverability | Start dictation, then interrupt it through an available real path such as navigating back, backgrounding the app, or a real audio interruption. | No turn submits, the draft is not corrupted, the UI returns to an editable/recoverable state, and a later dictation attempt can start normally. | passed by user manual check |
| Accessibility labels/hints | With VoiceOver or the iOS accessibility inspector/manual readout, inspect the composer controls. | The controls expose meaningful labels and hints for `Message`, `Hold to dictate`, `Start dictation` / `Stop dictation`, and `Send`. | passed by user manual check |
| Hit targets and Dynamic Type | Increase Dynamic Type to a large size and inspect/use the composer controls. | Voice controls and `Send` remain tappable; status/control text is readable and does not overlap. | passed by user manual check |

Evidence format to append here after testing:

```text
Date:
Device:
Build/install command or installed-build source:
Relay status:
Held dictation:
Held final/edit/send:
Tap dictation:
Typed prefix:
Cancel/recoverability:
Accessibility:
Dynamic Type/hit targets:
Notes/errors:
```
