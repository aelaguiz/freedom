# Codex Dock Observability Logging Framework - Implementation Log

Date: 2026-05-28

Parent plan: `docs/CODEX_DOCK_OBSERVABILITY_LOGGING_FRAMEWORK_2026-05-28.md`

Status: implemented with physical logarchive blocker recorded.

## Summary

The implementation adds one Swift diagnostics owner, one relay structured logger, MetricKit diagnostics capture, logging call sites across the app/relay surfaces named in the plan, and exact log capture commands in `Makefile`, `README.md`, and root `AGENTS.md`.

Physical install and launch proof passed on a real iPhone 14. Physical device logarchive collection did not pass because `xcrun log collect` requires root for the attached device on this machine; that exact blocker is recorded below.

## Phase 1 - Logging Primitives And Dock Refresh Slice

Status: implemented.

Changed code:

- `CodexDock/Diagnostics/Logging.swift`
  - Added `DockLog.subsystem = "com.aelaguiz.CodexDock"`.
  - Added Swift logging categories for app, lifecycle, bootstrap, relay discovery, host configuration, app-server, dock, archive, thread detail, connectivity, voice, transcription, persistence, and metrics.
  - Added `DockLog.endpoint(_:)`, `publicID(_:)`, `errorSummary(_:)`, `milliseconds(since:)`, `redacted(_:)`, and `DockSignpost`.
- `CodexDock/AppServer/AppServerClient.swift`
  - Logged connect/open/initialize/request/receive/reconnect/offline/error/disconnect paths with method, request id, timing, and sanitized error context.
  - Preserved offline connection-failure state while adding diagnostics.
- `CodexDock/State/DockStore.swift`
  - Logged dock refresh start/end/failure, host context, scope, row count, mapping failures, scoped failures, conflicts, and duration.
- `scripts/dock-relay-logger.mjs`
  - Added structured JSON stderr logger with injected stream/clock support and redaction.
- `scripts/dock-relay.mjs`
  - Routed `thread/list` aggregate success/failure logging through the relay logger.
- `scripts/dock-relay-json-rpc-client.mjs`
  - Extracted the upstream JSON-RPC WebSocket client and added sanitized upstream lifecycle/request logs.

Verification:

- Passed: `rtk swift test --filter AppServerClientTests` - 43 tests, 5 skipped.
- Passed: `rtk swift test --filter DockStoreTests` - 19 tests.
- Passed: `rtk npm run test:relay` - 39 tests.
- Passed service smoke: `rtk make services`.
- Passed service smoke: `rtk make dock-relay-status` returned `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.

## Phase 2 - Swift State Coverage

Status: implemented.

Changed code:

- `CodexDock/Configuration/RelayBootstrapStore.swift`
  - Logged bootstrap start/discovery/manual/saved configuration and persistence failures.
- `CodexDock/Configuration/RelayDiscovery.swift`
  - Logged Bonjour search start/stop, service add/remove, resolve success/failure, and relay count changes.
- `CodexDock/Configuration/DockHostConfiguration.swift`
  - Logged sanitized host configuration load/save details at caught caller boundaries.
- `CodexDock/Configuration/HostRegistry.swift`
  - Logged host registry parsing and configuration failures without credentials.
- `CodexDock/State/AppLifecycleCoordinator.swift`
  - Logged scene/lifecycle and resume-generation transitions.
- `CodexDock/State/AppConnectivityStore.swift`
  - Logged overall and per-host status transitions without repeated identical-state spam.
- `CodexDock/State/ArchiveStore.swift`
  - Logged archive load/restore outcomes and unavailable/empty/loaded states.
- `CodexDock/State/HostSettingsStore.swift`
  - Logged host test and save outcomes.
- `CodexDock/State/LocalThreadMetadataStore.swift`
  - Logged local metadata persistence failures.

Verification:

- Passed: `rtk swift test --filter DockStoreTests` - 19 tests.
- Passed: `rtk swift test --filter AppConnectivityStoreTests` - 11 tests.
- Passed: `rtk swift test --filter DockConfigurationTests` - 14 tests.

## Phase 3 - Thread Detail, Composer, Voice, And Transcription Coverage

Status: implemented.

Changed code:

- `CodexDock/State/ThreadDetailStore.swift`
  - Logged detail load/read/turns/resume, notification/request observation lifecycle, reconnect/stale/live/closed transitions, send draft, request-card response, and voice orchestration using counts/IDs/reason codes only.
- `CodexDock/Voice/VoiceCaptureController.swift`
  - Logged microphone permission, simulator unavailable path, audio session/engine start and stop, route-change stop, interruption stop, failure, chunk count, and duration.
- `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`
  - Logged start/append/commit/cancel, completion timeout, session mismatch, invalid event, stream end, and terminal outcomes without transcript text or audio/base64 audio.
- `scripts/dock-relay-realtime-transcription.mjs`
  - Logged start/append/commit/cancel, upstream open/failure/close, invalid upstream event, duration exceeded, missing API key, and close reason with IDs/counts/reason codes only.
- `scripts/dock-relay-realtime-transcription.test.mjs`
  - Added sanitized logging coverage for realtime transcription paths.

Verification:

- Passed: `rtk swift test --filter ThreadDetailStoreTests` - 50 matching tests.
- Passed: `rtk swift test --filter VoiceCaptureControllerTests` - 5 tests.
- Passed: `rtk swift test --filter AppServerClientTests` - 43 tests, 5 skipped.
- Passed: `rtk npm run test:relay` - 39 tests.

## Phase 4 - Crash, Hang, And Fatal Process Diagnostics

Status: implemented.

Changed code:

- `CodexDock/Diagnostics/MetricKitDiagnosticsReporter.swift`
  - Added a MetricKit subscriber where available.
  - Logs metric/diagnostic payload summaries for crash, hang, CPU exception, disk write, and app launch diagnostics.
  - Persists latest metrics and diagnostics JSON under Application Support `CodexDock/Diagnostics`.
  - Treats persistence failure as non-fatal and logs it once.
- `CodexDockApp/CodexDockApp.swift`
  - Starts the MetricKit reporter once during app initialization.
  - Logs app launch.
- `scripts/dock-relay-logger.mjs`
  - Added fatal process handlers for uncaught exceptions and unhandled rejections that log synchronously and exit.

Verification:

- Passed: `rtk swift test`.
  - Result: 182 tests, 5 skipped, 0 failures.
- Passed: `rtk xcodegen generate --spec project.yml`.
- Not passed first: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`.
  - Exact blocker: no simulator exists with exact name `iPhone 17`.
  - Available fallback used: `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- Passed after fallback and an iOS-only logging autoclosure fix: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Passed: `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B'`.
- Passed: `rtk npm run test:relay` - 39 tests.

## Phase 5 - Capture Commands, Instructions, And Runtime Proof

Status: implemented with physical logarchive blocker recorded.

Changed files:

- `Makefile`
  - Added `LOG_STYLE`, `LOG_PREDICATE`, `LOG_LAST`, and `DEVICE_LOG_OUTPUT`.
  - Added `app-server-logs`, `dock-relay-logs`, `sim-logs`, and `device-logs`.
  - `device-logs` uses `xcrun log collect --device-udid`, because `devicectl device log stream --device` is not supported by the installed Xcode.
- `README.md`
  - Added logging commands and the physical log collection root requirement caveat.
- `AGENTS.md`
  - Added `Logging And Diagnostics` guidance, exact capture commands, redaction rules, and the exact physical root blocker to record.

Runtime proof:

- Passed: `rtk make services`.
  - App-server endpoint: `ws://192.168.50.117:4500`.
  - Relay endpoint: `ws://192.168.50.117:4510`.
  - `.env` was left untouched; generated service env was written under `.codex-dock/service.env`.
- Passed: `rtk make app-server-status`.
  - HTTP 200 OK.
- Passed: `rtk make dock-relay-status`.
  - HTTP 200 OK with `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
- Passed: `rtk tail -n 20 .codex-dock/dock-relay.err.log`.
  - Structured JSON records were present.
- Passed: `rtk make app SIM='feat_anim_1 - iPhone 17'`.
  - Launched `com.aelaguiz.CodexDockApp` on simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
  - Launch endpoint was `ws://192.168.50.117:4510`.
- Passed simulator log proof: `rtk xcrun simctl spawn BAD95C8E-3E57-4818-9B90-E4ED22593B4B log show --last 2m --style compact --predicate 'subsystem == "com.aelaguiz.CodexDock"'`.
  - Relevant `CodexDockApp[38510]` lines included:
    - `MetricKit diagnostics reporter started`
    - `Codex Dock app launch`
    - `host configuration loaded ... endpoint=ws://192.168.50.117:4510 bearer_configured=false`
    - `relay bootstrap environment ready hosts=1`
    - `app-server connect initialize finished ... user_agent=codex_dock_relay/0.1.0`
    - `connectivity overall status=Online message=206 sessions`
    - `dock reload finished hosts=1 rows=206 mapping_failures=0 scope_failures=0 conflicts=0`
- Passed relay proof after simulator/physical launch: `rtk tail -n 40 .codex-dock/dock-relay.err.log`.
  - Structured records included `thread_list.loaded`, `downstream.request_succeeded`, and `downstream.closed`.
  - A representative `thread_list.loaded` record reported `historyRows:100`, `liveRows:13`, `endpoints:14`, `failedEndpoints:0`, `returnedRows:100`.
- Passed physical device install: `rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC DEVELOPMENT_TEAM=R6B8KXF3QW`.
  - Installed `com.aelaguiz.CodexDockApp` on the iPhone 14 device.
- Passed physical device launch: `rtk xcrun devicectl device process launch --device 0A4EFF8B-54D8-58FB-B3FB-63263265B9CC --terminate-existing com.aelaguiz.CodexDockApp`.
  - Output: `Launched application with com.aelaguiz.CodexDockApp bundle identifier.`
- Passed physical process proof: `rtk xcrun devicectl device info processes --device 0A4EFF8B-54D8-58FB-B3FB-63263265B9CC | rtk rg -n "CodexDock|com\\.aelaguiz\\.CodexDockApp"`.
  - Output showed `CodexDockApp` pid `4561`.
- Physical logarchive blocked: `rtk make device-logs DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC DEVICE_LOG_OUTPUT=/tmp/codex-client/observability-physical-0A4EFF8B-54D8-58FB-B3FB-63263265B9CC.logarchive`.
  - Exact blocker: `log: Must be root to collect logs from attached device`.

## Hygiene And Redaction Proof

- Passed static scan: `rtk rg -n "print\\(|debugPrint\\(|NSLog\\(|dump\\(" CodexDock CodexDockApp CodexDockTests`.
  - No matches.
- Passed static scan: `rtk rg -n "console\\.(error|warn|log|debug)" scripts/dock-relay*.mjs`.
  - No matches.
- Passed ASCII punctuation scan on logging/realtime files.
  - No matches.
- Passed sampled relay-log secret scan: `rtk rg -n "transcript|prompt|base64Audio|Authorization|Bearer|OPENAI_API_KEY|sk-" .codex-dock/dock-relay.err.log`.
  - No matches.
- Passed `Makefile` readback: `rtk make help` showed `sim-logs`, `device-logs`, and `dock-relay-logs`.

## Remaining Boundary

No implementation blocker remains for this plan. The only incomplete proof artifact is the physical device logarchive, and the exact local blocker is recorded: `log: Must be root to collect logs from attached device`.

## 2026-05-28 - Realtime Audio Debug Instrumentation Follow-Up

Scope:

- Applied the observability framework to the physical iPhone 14 realtime-audio failure path after manual feedback that hold dictation reached `Listening. Release to finalize.` and then stopped with `Voice capture stopped. Try again.` / `Realtime transcription stopped.`
- Target device for this follow-up: physical iPhone 14 `00008110-000E04940240A01E`.
- Physical Mobile MCP was not used for this follow-up because the device-side blocker remains `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.

Changed runtime signals:

- Swift voice capture now logs AVAudioSession activation, input availability, IO buffer duration, input/output `portType` values, input format, every route/interruption notification decision, stop reason, emitted chunk count, emitted byte count, and duration.
- Swift thread-detail voice orchestration now logs forwarding totals, unexpected capture stream ends, append failure metadata, commit-without-terminal-event context, transcription stream end, and stop/cancel requests.
- Swift realtime transcription client now logs connect/start split timing, append transport failures, append totals, zero-audio commit signal, commit failures, terminal event context, completion timeouts, and final session totals.
- Node realtime transcription relay now logs realtime limits, append validation reason codes, accepted chunk/byte totals, commit totals, upstream close code/reason byte length, upstream error type/code, ignored upstream event types, failure totals, and close totals.
- All new logs use counts, IDs, durations, reason codes, and sanitized endpoints only. They do not log `OPENAI_API_KEY`, bearer tokens, prompt text, transcript text, partial text, delta text, raw audio, base64 audio, full JSON-RPC payloads, route names, or route UIDs.

Verification:

- Passed: `rtk swift test --filter VoiceCaptureControllerTests` - 5 tests, 0 failures.
- Passed: `rtk swift test --filter ThreadDetailStoreTests` - 50 tests, 0 failures.
- Passed: `rtk swift test --filter AppServerClientTests` - 43 tests, 5 explicit real-host skips, 0 failures.
- Passed: `rtk npm run test:relay` - 40 tests, 0 failures.
- Passed: `rtk swift test` - 182 tests, 5 explicit real-host skips, 0 failures.
- Passed: `rtk git diff --check`.
- Passed: `rtk xcodegen generate --spec project.yml`.
- Passed after fixing two iOS-only compile issues caught by Xcode: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Passed install: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
- Passed launch: `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`.
- Passed service status: `rtk make app-server-status` returned HTTP 200 OK at `ws://192.168.50.117:4500`.
- Passed service status: `rtk make dock-relay-status` returned relay pid `57090`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- Physical device logarchive remains blocked without root:
  - Command: `rtk xcrun log collect --device-udid 00008110-000E04940240A01E --last 10m --predicate 'subsystem == "com.aelaguiz.CodexDock"' --output /tmp/codex-client/20260528T183720Z/codex-dock-device.logarchive`
  - Exact blocker: `log: Must be root to collect logs from attached device`.
- `.env` stayed untouched; mtime remained `1779986258`.

## 2026-05-28 - Voice Tap Crash Follow-Up

Scope:

- Followed up on physical iPhone 14 feedback that tapping the voice transcript button crashed the app after the realtime-audio instrumentation install.
- Target device: physical iPhone 14 `00008110-000E04940240A01E`.
- Physical Mobile MCP was not used because the device-side blocker remains `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.

Evidence:

- Attached physical launch reproduced the crash with `App terminated due to signal 5`.
- Relay logs showed `audio/transcription/start` succeeded before the crash, followed by downstream socket close and no audio appends: `acceptedChunks:0`, `acceptedBytes:0`.
- Simulator crash report for the same code path showed a Swift actor-isolation trap in `closure #1 in LiveVoiceCaptureController.startCapture()` on Apple's `RealtimeMessenger.mServiceQueue`. The `AVAudioEngine` tap callback was inheriting main-actor isolation but was invoked on the realtime audio queue.

Fix:

- Built the `AVAudioEngine` tap callback through a non-actor top-level helper so the realtime queue can call the locked `PCM16Mono24kChunkEmitter` without a main-actor executor trap.
- Reordered `ThreadDetailStore.beginVoiceCapture` so live mic capture starts before relay Realtime transcription starts. Capture startup failure now happens before any upstream relay session is opened.

Verification:

- Passed: `rtk swift test --filter VoiceCaptureControllerTests` - 5 tests, 0 failures.
- Passed: `rtk swift test --filter ThreadDetailStoreTests` - 50 tests, 0 failures.
- Passed: `rtk xcodegen generate --spec project.yml`.
- Name-based simulator build was blocked because no simulator is literally named `iPhone 17`; the available non-Pro simulator is `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`, name `feat_anim_1 - iPhone 17`.
- Passed: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Passed install: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
- `.env` stayed untouched; mtime remained `1779986258`.

Manual acceptance still required:

- Amir needs to retest tap dictation and held dictation on physical iPhone 14 against the installed crash-fix build. The automated tests and physical install do not count as physical voice acceptance.

## 2026-05-28 - Empty Transcript And Audio-Level Follow-Up

Scope:

- Followed up on physical iPhone 14 feedback that voice no longer crashed, but saying `test test test` produced `Realtime transcription stopped` with no draft text.
- Target device: physical iPhone 14 `00008110-000E04940240A01E`.
- Physical Mobile MCP was not used because the device-side blocker remains `WebDriverAgent is not running on device (tunnel okay, port forwarding okay)`.

Evidence:

- Relay logs showed physical phone audio was reaching the Mac relay. Session `a2f98ed8-28dd-4cad-815d-e42f2f7d9193` accepted `25` chunks and `120000` bytes before commit.
- The failing upstream result was `conversation.item.input_audio_transcription.completed` with a valid `item_id` and empty transcript. The relay classified that as `invalid_upstream_event`, which made the phone show `Realtime transcription stopped`.
- Checked current official OpenAI Realtime transcription docs via the OpenAI developer docs MCP. The current documented path still uses `gpt-realtime-whisper`, 24 kHz mono `audio/pcm`, manual `input_audio_buffer.commit`, and `conversation.item.input_audio_transcription.completed`.

Fix:

- Empty completed transcript events with a valid item id now complete as `completed_empty` instead of failing as invalid protocol.
- Relay logs now include safe aggregate audio-level metrics: `peakAbs`, `rms`, `maxRms`, and `nonSilentChunks`. These do not expose raw audio, base64 audio, transcript text, prompt text, tokens, or credentials.
- Swift store now handles a transcription event stream ending while dictation is busy by canceling capture and failing recoverably, rather than leaving the composer stuck busy.

Verification:

- Passed: `rtk node --check scripts/dock-relay-realtime-transcription.mjs && rtk node --check scripts/dock-relay-realtime-transcription.test.mjs`.
- Passed: `rtk swift test --filter ThreadDetailStoreTests` - 51 tests, 0 failures.
- Passed: `rtk npm run test:relay` - 41 tests, 0 failures.
- Passed: `rtk xcodegen generate --spec project.yml`.
- Passed: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`.
- Restarted relay with `rtk make dock-relay-restart`.
- Installed physical iPhone 14 build: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`.
- Launched physical iPhone 14 build: `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`.
- Final relay status: pid `92791`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- `.env` stayed untouched; mtime remained `1779986258`.

Manual acceptance still required:

- Amir needs to retest physical iPhone 14 tap dictation and held dictation against this installed build. If the result is still empty, inspect relay `peakAbs`, `maxRms`, and `nonSilentChunks` for the latest transcription session to determine whether the phone sent silence or non-silent speech.
