---
title: "Codex Dock - Realtime Transcription Streaming - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md
  - docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md
  - https://openai.com/index/advancing-voice-intelligence-with-new-models-in-the-api/
  - https://developers.openai.com/api/docs/guides/realtime-transcription
  - https://developers.openai.com/api/docs/guides/realtime
  - https://developers.openai.com/api/docs/guides/realtime-webrtc
  - https://developers.openai.com/api/docs/guides/realtime-websocket
  - https://developers.openai.com/api/docs/guides/speech-to-text
  - docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md
  - docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_08_VOICE_ACCESSIBILITY_FINAL_POLISH_2026-05-27.md
---

# TL;DR

## Supersession Note - 2026-05-28

`docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28.md`
supersedes this plan anywhere it refers to selected host config as stored
`host.webSocketURL` or `host.bearerToken`. Realtime still connects through the
selected Dock relay, but the app host model is endpoint-only and computes
`ws://<host>:<port>` only when creating the transport client. Provider config,
OpenAI keys, and raw app-server tokens remain relay-side.

- Outcome: Codex Dock voice dictation streams speech-to-text into the existing composer while the user is still talking; releasing the mic finalizes the transcript in the same draft and still requires manual Send.
- Original problem: Voice capture recorded an m4a file, waited for release, uploaded the whole file to `POST /v1/audio/transcriptions`, then inserted one final transcript. That could not produce the live "I see words appear as I speak" UX the user asked for.
- Approach: Replace the file-upload dictation path with one canonical realtime transcription session path. The iPhone streams microphone PCM frames through a Mac-owned relay to OpenAI Realtime transcription, receives transcript deltas, and patches only the active dictation segment in `ThreadDetailStore.composer.draft`.
- Plan: After Connectivity exits, first prove the relay can own Realtime session creation and event streaming without exposing OpenAI secrets; then prove store-owned draft reconciliation with fake streaming events; then connect Swift to the relay with synthetic audio; then replace iOS file recording with live PCM capture and accessible composer controls; then retire stale production file-upload/docs/config paths. In the top-level dock, this plan runs after connectivity resilience so voice interruption, app background/resume, and relay failures use the shared lifecycle/status owner instead of a second voice-only recovery path.
- Non-negotiables: no phone-side OpenAI key, no generic OpenAI proxy, no parallel voice composer, no voice auto-submit, no transcript/audio logging, no fallback that silently returns to slow file upload, and no Send while a dictation stream is active.
- Implementation status on 2026-05-28: Phase 0 prerequisite readback passed. Phase 1 relay contract is code-complete in the current working tree with `scripts/dock-relay-realtime-transcription.mjs`, `scripts/dock-relay-realtime-transcription.test.mjs`, `scripts/dock-relay.mjs`, and `package.json`; mock/fake-upstream relay tests are preflight coverage only and do not count as acceptance proof. Phase 2 store-owned streaming draft reconciliation is code-complete in Swift with fake streaming-session preflight coverage only. Phase 3 typed Swift relay client integration is code-complete with scripted relay-notification preflight coverage only, and default store voice construction now uses the typed relay-backed streaming client instead of one-shot `audio/transcribe`. Phase 4 live PCM capture, store audio forwarding, hold dictation, tap-to-start/tap-to-stop dictation, and route/interruption cleanup are code-complete: `AVAudioEngine` emits 24 kHz mono PCM16 chunks, `ThreadDetailStore` forwards them to `RealtimeTranscriptionSession.appendAudio(...)` before commit, and `ComposerView` exposes both `Hold to dictate` and `Start dictation`. Standalone real relay-to-OpenAI proof passes with redacted evidence, and the user confirmed the physical iPhone 14 Realtime audio path worked after the relay empty-transcript fix. Phase 5 cutover cleanup removes direct Swift OpenAI/file-upload transcription, removes typed one-shot app DTO/client surfaces, deletes the relay one-shot helper, removes old one-shot service config, and adds a raw `audio/transcribe` rejection test. The latest physical iPhone 14 build changes listening-state UI from red to blue; red remains reserved for actual errors. Follow-up implementation audit and thermonuclear review passed after splitting voice state into `ThreadDetailStore+Voice.swift` and relay thread-data helpers into `scripts/dock-relay-thread-data.mjs`. The detailed typed-prefix, explicit-Send, cancel/interruption, and accessibility checklist is marked passed by user manual physical iPhone 14 check for the current installed build. Future physical checks are deferred manual QA for Amir and do not block implementation while simulator/local/real-relay proof passes; do not require, retry, or wait on physical-device checks unless Amir explicitly asks.
- Current physical-device rule: `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md` supersedes older physical-proof wording in this plan. Do not require, retry, or wait on physical-device checks for Realtime unless Amir explicitly asks; use simulator/local/real-relay proof and record physical-only checks in the parent deferred physical-device test list.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: done 2026-05-28
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:837cfe20e11626d387911d4922a54386ad7e7d9317a5f5cb42dabff223960a61",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T10:52:23Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:b36969d5de160058a1aae3b3b0b63af05d6e39945655291ece4d901cb0b322fa",
      "completed_at": "2026-05-28T10:53:01Z",
      "doc_hash_after": "sha256:236f374e45f8151fa21af6e177a4159aa497e8ec73c09fcd3ed76479619fe060"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:53:04Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:236f374e45f8151fa21af6e177a4159aa497e8ec73c09fcd3ed76479619fe060",
      "completed_at": "2026-05-28T10:56:27Z",
      "doc_hash_after": "sha256:d2d6b0fc79163f901617c967c59124a051d2fa43aba62a32f99189a800ed9a20"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T10:56:29Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:d2d6b0fc79163f901617c967c59124a051d2fa43aba62a32f99189a800ed9a20",
      "completed_at": "2026-05-28T10:57:09Z",
      "doc_hash_after": "sha256:d6f98df95d5f192c8fdadf73dd33b17426d1f1c8d3a1c568a7e79d8e1997c52d"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T10:57:14Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:d6f98df95d5f192c8fdadf73dd33b17426d1f1c8d3a1c568a7e79d8e1997c52d",
      "completed_at": "2026-05-28T11:00:00Z",
      "doc_hash_after": "sha256:62c787f26d5aebf95f6102d9bd70f3a5f2210aed94bdd0693b46a7da3e40fa9b"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T11:00:08Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:62c787f26d5aebf95f6102d9bd70f3a5f2210aed94bdd0693b46a7da3e40fa9b",
      "completed_at": "2026-05-28T11:08:00Z",
      "doc_hash_after": "sha256:8d9d2bdd0007084f43b0067d90ebdaeb88d4ad6add1b3925e436dc21205fcabf"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

This change is done when a physical iPhone build can dictate from the existing thread composer using either hold-to-talk or accessible tap-to-start/tap-to-stop, stream live microphone audio to OpenAI Realtime transcription through the Mac relay, display transcript deltas in the text field while speech is still in progress, reconcile the final transcript without duplicating or erasing user text, and submit only when the user taps Send.

## 0.2 In scope

- Requested behavior scope:
  - live speech-to-text deltas appear inside the existing composer while the user is speaking;
  - final transcript reconciliation replaces the active partial dictation segment when OpenAI emits completion;
  - typed text before dictation is preserved;
  - the composer locks user edits while dictation is active so transcript updates and typed edits cannot race;
  - text remains editable after dictation finalizes or fails;
  - dictation remains in-place in `ComposerView`, not a separate voice screen;
  - hold-to-talk remains available and an accessible tap-to-start/tap-to-stop path exists for users who cannot comfortably hold the mic;
  - Dynamic Type, VoiceOver labels/hints, and button hit targets remain production-quality;
  - voice still never auto-submits a Codex turn.
- Technical scope:
  - introduce a relay-owned OpenAI Realtime transcription connection using `gpt-realtime-whisper`;
  - stream iOS microphone audio as PCM frames instead of recording an m4a file for the production path;
  - add a narrow relay JSON-RPC contract for starting, streaming, receiving deltas, committing/stopping, and canceling a transcription session;
  - extend `ThreadDetailStore` voice state so partial and final transcript updates are first-class state, not one final string;
  - keep the physical iPhone no-secret boundary from `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`.
  - preserve the implemented physical relay baseline: `DockHostConfiguration.bearerToken` may be nil, relay `phoneAuth=none` is valid, and the phone still receives no OpenAI key, Realtime client secret, raw app-server token, or relay bearer token.
  - integrate with the connectivity lifecycle from `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md` for app background, foreground resume, relay drops, and recoverable voice failure reporting.
- Allowed architectural convergence scope:
  - refactor `TranscriptionServicing` from one-shot file transcription into a streaming session abstraction;
  - move production OpenAI transcription ownership from Swift to `scripts/dock-relay.mjs`;
  - delete the old production file-upload client path and use fakes for tests instead of phone-side OpenAI upload;
  - update tests and live docs that still describe file upload as the voice path.
- Adjacent surfaces that move with this contract:
  - `CodexDock/Voice/*`, `ThreadDetailStore`, `ComposerView`, and voice tests;
  - relay JSON-RPC method allowlist, auth/secret handling, and Node relay tests;
  - `Makefile` service env/model configuration for relay-owned Realtime defaults;
  - `README.md`, the iPhone pairing plan, the iPhone UX spec, the multi-host service setup plan, Phase 8 plan/worklog docs, `project.yml`, and `CodexDockApp/Info.plist` where they mention the production voice path, microphone copy, or old relay transcription contract.
- Compatibility posture:
  - clean cutover for production physical iPhone dictation to Realtime streaming;
  - preserve the composer send contract and thread-detail JSON-RPC turn APIs;
  - preserve simulator/dev host config except phone-side OpenAI key injection, and do not keep slow upload as an automatic runtime fallback.

## 0.3 Out of scope

- Speech-to-speech voice agent behavior, assistant audio output, Realtime tool calls, Realtime translation, diarization, timestamps, confidence UI, meeting notes, background listening, hotword detection, and multi-speaker workflows.
- Arbitrary user-selectable OpenAI model choices from the phone.
- Sending transcript text automatically to Codex, changing Codex turn semantics, or changing request-card input behavior.
- Hostile-network hardening beyond the existing personal Mac/iPhone relay boundary.
- A second composer, separate voice screen, or alternative send path.

## 0.4 Definition of done (acceptance evidence)

- Programmatic proof:
  - Swift tests prove cumulative partial transcript updates replace the active dictation segment, final transcript replaces that segment, typed prefix text is preserved, user edits are locked while dictation is active, explicit cancel removes only the active dictation segment, failures keep existing draft recoverable, and Send remains disabled while voice is streaming.
  - Swift tests prove the production default transcription service is relay-backed and does not require `OPENAI_API_KEY` in the iPhone process.
  - Node tests prove the relay Realtime transcription path starts a session with `gpt-realtime-whisper`, forwards bounded audio chunks, emits cumulative partial/final events in order per `item_id` or relay session id, handles cancel/close, and does not log OpenAI keys, raw audio, base64 audio, transcript text, or full upstream responses.
  - Existing Dock, Archive, Thread Detail, request-card, and text composer tests still pass.
- Manual proof:
  - On a physical iPhone with relay services running, hold the mic and speak a sentence; text appears in the composer before release.
  - Release the mic; the final transcript remains editable and Send still requires a tap.
  - On a physical iPhone with relay services running, tap to start dictation, speak a sentence, observe live text, tap to stop, and confirm final text remains editable with Send still manual.
  - Start dictation after existing typed text; typed text survives.
  - Cancel/interruption does not submit, does not corrupt the draft, and leaves a clear recoverable state.

## 0.5 Key invariants (fix immediately if violated)

- The phone never contains, imports, stores, pastes, scans, or receives `OPENAI_API_KEY`.
- The phone never receives an OpenAI Realtime client secret, ephemeral token, SDP credential, or provider-scoped bearer as an implementation shortcut.
- The relay API is named and purpose-specific for Codex Dock transcription; it is not a generic OpenAI forwarding API.
- The relay-backed voice client must work with a nil host bearer token because that is the normal discovered physical-iPhone relay path.
- The production transcription client uses typed transcription methods only. Existing raw JSON-RPC helpers remain transport primitives, but they are not a production voice API and the relay must reject old or malformed transcription method strings.
- The composer draft remains the single source of truth for user text.
- Only one active dictation segment may edit the draft at a time.
- Partial transcript text may be revised by later deltas/final completion, but it may not erase user-typed text outside the active segment.
- Voice never auto-submits a turn.
- Sending is disabled while a transcription stream is active.
- Audio payloads and transcript text are never logged.
- Any OpenAI safety identifier is generated and attached server-side by the relay from stable privacy-preserving local context; the phone does not supply or control it.
- Runtime fallback policy is forbidden: Realtime either works or fails visibly; it must not silently switch back to slow file upload.

## 0.6 Cross-plan position

This is Phase 3 in `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`.

Inputs from earlier phases:

- the physical iPhone security baseline keeps relay/raw/OpenAI secrets off the phone and allows nil bearer host config;
- the connectivity plan owns `AppServerClient` lifecycle, `ThreadDetailStore` rehydrate, `AppConnectivityStore`, and app background/foreground handling.

Outputs consumed by later phases:

- the relay-owned Realtime transcription contract replaces the current one-shot `audio/transcribe` production path;
- host-service setup/status can report final Realtime transcription state instead of file-upload transcription state;
- old one-shot app/relay voice surfaces are deleted or rejected so multi-host setup does not preserve them as a fallback.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Actual live transcript UX in the existing composer.
2. No phone-side OpenAI secret.
3. Correct draft reconciliation under partial, final, cancel, error, and user-edit timing.
4. One canonical voice path and one canonical composer path.
5. Small relay API surface with fail-loud boundaries.
6. Tests that prove the behavior users feel, not only mock plumbing.

## 1.2 Constraints

- The app is Swift/iOS 17 with SwiftUI, `AVFoundation`, and a Swift package target shared by tests.
- `ThreadDetailStore` is the current composer owner and already owns voice state.
- `ComposerView` uses a multiline `TextField` bound to `store.composer.draft`.
- Existing voice capture uses `AVAudioRecorder` to create an m4a file; streaming uses `AVAudioEngine` live PCM capture.
- OpenAI Realtime transcription expects live audio chunks and emits transcript delta/completion events.
- The existing Node relay uses `ws`, already owns app-facing JSON-RPC, and can hold the OpenAI key on the Mac side.

## 1.3 Architectural principles (rules we will enforce)

- Keep OpenAI Realtime credentials and connection ownership on the Mac relay.
- Keep app UI business rules in `ThreadDetailStore`; `ComposerView` renders state and sends gestures.
- Model the streaming session explicitly rather than forcing deltas through a one-shot `transcribe(audioFile:)` API.
- Use a stable active dictation range/segment owner so deltas can replace partial text safely.
- Bound audio chunk size, session lifetime, and relay memory.
- Close or delete production side doors to the old file-upload transcription path.
- Prefer direct behavior tests over string-absence gates.

## 1.4 Known tradeoffs (explicit)

- Server-side WebSocket relay is favored over direct mobile WebRTC for V1 because the existing physical-phone plan forbids OpenAI secrets on the phone and the app already trusts a Mac relay for privileged work.
- Direct mobile WebRTC with ephemeral OpenAI tokens can be revisited later if latency through the relay is not acceptable, but it adds iOS WebRTC complexity and token-minting surface now.
- Direct mobile WebSocket to OpenAI Realtime is rejected for V1 even though it is locally simpler than adding relay methods. It either puts a provider secret on the phone or requires a token-minting path, and OpenAI's WebSocket guidance frames WebSockets as the better fit for server-side integrations.
- `gpt-realtime-whisper` is selected for live deltas. `gpt-4o-transcribe` remains better suited to request-response file transcription and should not remain the production path for this UX.
- Partial transcripts are allowed to change as the model receives more context. The UI must treat them as provisional until completion.

# 2) Problem Statement (existing architecture + why change)

## 2.1 Original Baseline Before Realtime Work

- `VoiceCaptureController` records an m4a file with `AVAudioRecorder` after mic press.
- `ThreadDetailStore.beginVoiceCapture()` marks `.recording` and starts recording.
- `ThreadDetailStore.finishVoiceCapture()` stops recording, switches to `.transcribing`, calls `TranscriptionServicing.transcribe(audioFile:)`, then inserts one final transcript into `composer.draft`.
- The original default store path was one-shot relay upload through `RelayTranscriptionClient` and `audio/transcribe`; Realtime Phases 2-3 removed that automatic store fallback and wired the default store voice path to the typed relay-backed streaming client. Phase 5 removes the direct Swift OpenAI/file-upload side door and the one-shot app/relay DTO/client/helper surfaces.
- `ComposerView` disables the mic during `.transcribing`, shows status text, and only updates the text field after the one-shot transcription returns.

## 2.2 What's broken / missing (concrete)

- Users must wait for recording to finish, upload, and decode before seeing any text.
- There is no representation of partial transcript state in the store or UI.
- The current protocol shape cannot stream transcript deltas.
- The current physical-phone direction says OpenAI keys belong on the Mac relay. The app default now uses relay-owned Realtime transcription, and the old `audio/transcribe` relay route is rejected after cutover.
- The relay exposes a realtime transcription stream contract, the basic physical iPhone 14 microphone path has user-confirmed success after the empty-transcript relay fix, and the detailed manual checklist is marked passed by user manual check for the current installed build.

## 2.3 Constraints implied by the problem

- The voice API has to change from one-shot file transcription to streaming session events.
- Partial transcript text must be reconciled against the editable composer draft without corrupting user text.
- The OpenAI connection belongs behind the relay unless the plan explicitly changes the no-secret posture.
- Verification must include timing/state behavior, because the main bug class is partial/final/cancel sequencing.

<!-- arch_skill:block:research_grounding:start -->
# 3) Research Grounding (external + internal "ground truth")

## 3.1 External anchors (papers, systems, prior art)

- OpenAI product announcement, 2026-05-07, `https://openai.com/index/advancing-voice-intelligence-with-new-models-in-the-api/` - adopt the model direction. The announcement introduces `GPT-Realtime-Whisper` as streaming speech-to-text that transcribes live as the speaker talks. This exactly matches the requested UX: text appears while speaking, not after upload.
- OpenAI Realtime and audio guide, `https://developers.openai.com/api/docs/guides/realtime` - adopt the architecture split. The guide says realtime sessions are for low-latency live audio, request-based Audio APIs are for files/bounded requests, and live transcription should use the Realtime transcription guide with `gpt-realtime-whisper`. Reject a Realtime voice-agent session because this app needs text from audio without model-generated spoken responses.
- OpenAI Realtime transcription guide, `https://developers.openai.com/api/docs/guides/realtime-transcription` - adopt as the target API contract. It specifies `type: "transcription"`, 24 kHz mono PCM when using `audio/pcm`, `audio.input.transcription.model: "gpt-realtime-whisper"`, transcript delta events (`conversation.item.input_audio_transcription.delta`), completion events (`conversation.item.input_audio_transcription.completed`), manual `input_audio_buffer.commit` when turn detection is disabled, and `item_id` reconciliation for ordering.
- OpenAI Realtime WebSocket guide, `https://developers.openai.com/api/docs/guides/realtime-websocket` - adopt for the Mac relay side. OpenAI recommends WebSockets for server-to-server Realtime integrations and says mobile/browser clients should generally prefer WebRTC. Because this app already has a trusted Mac relay that owns secrets, server-side WebSocket on the relay is the simpler V1 fit.
- OpenAI Realtime WebRTC guide, `https://developers.openai.com/api/docs/guides/realtime-webrtc` and OpenAPI endpoints `/v1/realtime/client_secrets`, `/v1/realtime/calls` - reject as V1 production path for this app. WebRTC/ephemeral tokens are valid for direct mobile/browser audio, but would require iOS WebRTC work plus token-minting. The phone must not receive `/v1/realtime/client_secrets` output in this V1. Keep WebRTC as a later latency optimization if relay WebSocket proves too slow.
- OpenAI Speech-to-text guide, `https://developers.openai.com/api/docs/guides/speech-to-text` - adopt only as evidence that the current file-upload path is the wrong path for this UX. The guide says file uploads and bounded audio use `/v1/audio/transcriptions`, but live transcript deltas from microphone/calls/media streams should use Realtime transcription instead.
- OpenAI `gpt-realtime-whisper` model page, `https://developers.openai.com/api/docs/models/gpt-realtime-whisper` - adopt as the model default for live dictation. It is designed for low-latency transcript deltas and priced by audio duration rather than text tokens.
- OpenAI Realtime costs guide, `https://developers.openai.com/api/docs/guides/realtime-costs` - adopt duration-based cost/ops framing for transcription sessions. Translation and transcription sessions stream audio continuously and receive transcript events as source audio arrives; they do not follow the normal Response lifecycle.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors:
  - `CodexDock/Voice/VoiceCaptureController.swift` - current iOS voice capture uses `AVAudioEngine`, emits bounded PCM16 mono 24 kHz chunks, and does not create m4a upload files for production dictation.
  - `CodexDock/Voice/TranscriptionService.swift` - current production voice abstractions are `RealtimeTranscriptionServicing`, `RealtimeTranscriptionSession`, `RealtimeTranscriptionEvent`, and `LiveVoiceCaptureControlling`; one-shot `TranscriptionServicing`, `OpenAITranscriptionClient`, and `RelayTranscriptionClient` have been removed.
  - `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift` - current typed client sends `audio/transcription/start`, `audio/transcription/append`, `audio/transcription/commit`, and `audio/transcription/cancel`, and maps relay delta/completed/failed/canceled/closed notifications.
  - `CodexDock/AppServer/AppServerMethods.swift` and `CodexDock/AppServer/AppServerClient.swift` - current typed app surface contains Realtime transcription methods only; one-shot `audioTranscribe(params:timeout:)` and `AudioTranscriptionDTO.swift` have been removed.
  - `CodexDock/State/ThreadDetailStore.swift` - current composer/voice owner streams live capture chunks into the active Realtime session, reconciles partial/final transcript text into the existing draft, and keeps Send explicit.
  - `CodexDock/Features/Session/ComposerView.swift` - UI binds `TextField` directly to `store.composer.draft`, supports hold and tap dictation controls, and disables Send through `composer.canSend` while voice is busy.
  - `CodexDockTests/ThreadDetailStoreTests.swift` - current proof covers live chunk forwarding, transcript insertion without auto-submit, append-to-existing-draft, recoverable transcription failure, and fake Realtime streaming sessions.
  - `scripts/dock-relay.mjs` - current Mac relay owns app-facing JSON-RPC, upstream app-server forwarding, allowlisted methods, LaunchAgent service behavior, and relay-owned Realtime transcription routing. Raw `audio/transcribe` falls through to unsupported method `-32601`.
  - `scripts/dock-relay.test.mjs` and `scripts/dock-relay-realtime-transcription.test.mjs` - current Node tests cover Realtime transcription contract behavior and raw legacy `audio/transcribe` rejection.
  - `CodexDock/Configuration/DockHostConfiguration.swift`, `CodexDock/Configuration/RelayBootstrapStore.swift`, and `CodexDock/Configuration/RelayDiscovery.swift` - current physical phone path discovers a no-client-auth relay and builds host config with `bearerToken: nil`. Realtime voice must use that same host contract rather than reintroducing a phone bearer or provider secret.
  - `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md` - preceding top-level phase owns app scene lifecycle, root connectivity status, and thread detail reconnect/rehydrate. Realtime voice must attach to those lifecycle hooks for app background/interruption handling.
  - `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md` - current physical-device plan says voice transcription should move through the relay and the phone should not contain OpenAI keys. That plan targeted `audio/transcribe` file upload; this plan supersedes that voice sub-slice with Realtime streaming.
  - `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_08_VOICE_ACCESSIBILITY_FINAL_POLISH_2026-05-27.md` - existing product constraint says voice is in-place dictation into the existing composer, no separate voice screen, and no auto-submit.
- Canonical path / owner to reuse:
  - `ThreadDetailStore` remains the canonical owner of composer draft, voice phase, Send gating, and transcript insertion/reconciliation.
  - `ComposerView` remains a thin SwiftUI surface bound to `ThreadDetailStore`.
  - `CodexDock/Voice/` remains the local audio capture and transcription client boundary, but the production transcription client becomes relay-backed and streaming.
  - `scripts/dock-relay.mjs` becomes the canonical owner of OpenAI Realtime credentials, upstream Realtime WebSocket connection, and app-facing transcription stream events.
- Adjacent surfaces tied to the same contract family:
  - `CodexDockTests/ThreadDetailStoreTests.swift` must change from one-shot fake transcript to streaming fake events while preserving the old no-auto-submit behavior.
  - `CodexDockTests/AppServerClientTests.swift` must cover the explicit JSON-RPC event/request surface used for relay transcription.
  - `scripts/dock-relay.test.mjs` must cover the relay Realtime session contract, not only helper functions.
  - `README.md`, the iPhone pairing plan, the iPhone UX spec, the multi-host service setup plan, Phase 8 plan/worklog docs, `project.yml`, and `CodexDockApp/Info.plist` must stop teaching slow file upload, release-to-transcribe-only UX, phone-side OpenAI keys, and one-shot `audio/transcribe` as the production voice path once this plan is implemented.
- Compatibility posture (separate from `fallback_policy`):
  - Clean production cutover from file-upload dictation to Realtime streaming.
  - Preserve text composer and app-server turn contracts.
  - Delete old production file-upload code, one-shot `audio/transcribe` app/relay surfaces, and one-shot relay transcription config/helpers/tests rather than keeping them as a hidden fallback.
- Existing patterns to reuse:
  - `ThreadDetailStore` dependency injection pattern for `voiceCapture` and `transcriptionService`.
  - `AppServerClient` JSON-RPC request/notification handling and optional bearer support for relay communication.
  - Node relay `JsonRpcWebSocketClient` and method allowlist pattern.
  - Existing Swift store tests with fake services for state-machine proof.
- Conflicting local-simple option resolved:
  - A direct iPhone-to-OpenAI WebSocket would reduce relay work, but is rejected for this plan because it revives phone-side provider credentials and conflicts with OpenAI's client guidance and the current physical-device no-secret direction.
- Prompt surfaces / agent contract to reuse:
  - Not applicable. This is app/relay runtime behavior, not a prompt or agent-instruction change.
- Native model or agent capabilities to lean on:
  - OpenAI Realtime transcription native `gpt-realtime-whisper` streaming deltas, not a custom local speech recognizer or post-hoc chunked file uploader.
- Existing grounding / tool / file exposure:
  - The relay already runs on the Mac where `.env` and process env can provide `OPENAI_API_KEY`.
  - The phone already has microphone permission copy and local-network permission copy.
  - Node already has `ws`; no new Node WebSocket dependency is needed for server-side Realtime.
- Duplicate or drifting paths relevant to this change:
  - `OpenAITranscriptionClient` as a compiled direct phone-to-OpenAI side door conflicts with the no-secret relay boundary if it remains reachable from production construction.
  - `RelayTranscriptionClient`, `AppServerMethods.audioTranscribe`, `AppServerClient.audioTranscribe`, `AudioTranscriptionDTO.swift`, and relay `audio/transcribe` handling are existing one-shot relay upload surfaces that conflict with streaming Realtime cutover if left reachable.
  - `scripts/dock-relay.mjs` one-shot transcription constants, endpoint/model env names, CLI flags, `transcribeAudio`, `decodedAudioTranscribeParams`, helper exports, and one-shot relay tests are discoverable side doors unless replaced with Realtime-specific config/tests.
  - `AppServerClient.sendRequest(method:)` and `sendNotification(method:)` are public raw JSON-RPC transport primitives; the Realtime plan must rely on production voice construction plus relay rejection, not on deleting those generic transport methods.
  - `TranscriptionServicing.transcribe(audioFile:)` is too narrow and will become a misleading abstraction if the production path is streaming.
  - Existing docs and app metadata that say voice waits for a completed audio file, uses hold-only dictation, embeds a phone OpenAI key, or preserves `audio/transcribe` will become stale after implementation.
- Capability-first opportunities before new tooling:
  - Use OpenAI Realtime transcription directly via the relay instead of simulating "streaming" by slicing completed files.
  - Use `AVAudioEngine`/PCM capture in Swift rather than adding a third-party audio stack.
  - Use existing JSON-RPC/WebSocket relay plumbing rather than adding a separate HTTP/SSE server for transcript events.
- Behavior-preservation signals already available:
  - Existing ThreadDetail store tests around no auto-submit and editable draft behavior.
  - Existing AppServer transport tests for optional bearer/no-secret relay connectivity.
  - Existing Node relay tests as a place to add contract, bounds, and log-redaction proof.

## 3.3 Decision gaps that must be resolved before implementation

- none
<!-- arch_skill:block:research_grounding:end -->

<!-- arch_skill:block:current_architecture:start -->
# 4) Current Architecture (as-is)

## 4.1 On-disk structure

- Swift voice:
  - `CodexDock/Voice/VoiceCaptureController.swift` - m4a file recording through `AVAudioRecorder`.
  - `CodexDock/Voice/TranscriptionService.swift` - one-shot `TranscriptionServicing` protocol, phone-side OpenAI file-upload client, and one-shot relay upload client.
- Swift composer:
  - `CodexDock/State/ThreadDetailStore.swift` - composer draft, Send gating, voice state, and one-shot transcript insertion.
  - `CodexDock/Features/Session/ComposerView.swift` - text field, mic hold/release gesture, voice status, and Send button.
  - `CodexDock/Features/Session/SessionDetailView.swift` - embeds `ComposerView` in thread detail.
- Swift transport/config:
  - `CodexDock/AppServer/AppServerClient.swift` - JSON-RPC over WebSocket, notifications, requests, optional bearer.
  - `CodexDock/AppServer/AppServerMethods.swift` and `CodexDock/AppServer/AudioTranscriptionDTO.swift` - current one-shot `audio/transcribe` method and DTOs.
  - `CodexDock/Configuration/*` and `CodexDockApp/CodexDockApp.swift` - host registry/bootstrap surfaces.
- Relay:
  - `scripts/dock-relay.mjs` - Node WebSocket relay with app-facing JSON-RPC method handling, app-server forwarding, one-shot `audio/transcribe`, one-shot transcription config/helper/export surfaces, and service health.
  - `scripts/dock-relay.test.mjs` - current Node tests, including one-shot `audio/transcribe` helper tests.
- Tests/docs:
  - `CodexDockTests/ThreadDetailStoreTests.swift` - voice behavior tests.
  - `CodexDockTests/AppServerClientTests.swift` - WebSocket/JSON-RPC transport tests.
  - `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`, Phase 8 docs/worklog, and `README.md` - operational truth that currently describes file-oriented transcription.

## 4.2 Control paths (runtime)

Original hold/release voice path before Realtime Phase 2:

1. User presses mic in `ComposerView`.
2. `ComposerView` calls `ThreadDetailStore.beginVoiceCapture()`.
3. Store sets `composer.voice.phase = .recording`.
4. `VoiceCaptureController.startRecording()` asks microphone permission, configures `AVAudioSession`, creates a temporary `.m4a`, and starts `AVAudioRecorder`.
5. User releases mic.
6. `ComposerView` calls `ThreadDetailStore.finishVoiceCapture()`.
7. Store sets `composer.voice.phase = .transcribing`.
8. `VoiceCaptureController.stopRecording()` returns the m4a URL.
9. Original default production path: `RelayTranscriptionClient.transcribe(audioFile:)` reads the completed m4a file, calls `AppServerClient.audioTranscribe`, and the relay handles `audio/transcribe` as a file-upload-style request.
9a. Current Phase 4/5 state: `ThreadDetailStore` no longer constructs that automatic one-shot fallback. The default voice path uses the typed relay-backed streaming client, starts `LiveVoiceCaptureController`, forwards 24 kHz mono PCM16 chunks through `RealtimeTranscriptionSession.appendAudio(...)`, stops capture before commit, and owns both hold and tap dictation modes. Real relay/OpenAI proof, the basic physical iPhone 14 Realtime audio path, and the detailed manual closeout checklist have passed for the current installed build.
9b. Current side-door state after Phase 5: `OpenAITranscriptionClient`, `RelayTranscriptionClient`, `AppServerClient.audioTranscribe(...)`, `AppServerMethods.audioTranscribe`, the one-shot DTO, and the relay `audio/transcribe` handler have been removed or rejected. Raw `audio/transcribe` requests now fail rather than falling back to file upload.
10. Store trims the returned text and appends it to `composer.draft`.
11. Store clears voice state; user may edit or tap Send.

Current send path:

1. User taps Send.
2. `composer.canSend` must be true: non-empty draft, not sending, and no busy voice phase.
3. Store sends `turn/start` or `turn/steer` through the existing app-server session.
4. Voice transcript text is indistinguishable from typed text after insertion.

## 4.3 Object model + key abstractions

- `TranscriptionServicing` has one method: `transcribe(audioFile:)`. This cannot represent a live session, partial deltas, cancellation, or final reconciliation.
- `VoiceCaptureControlling` has start/stop/cancel methods returning file URLs. This cannot emit PCM chunks.
- `ComposerVoiceState` stores only `phase` and `lastError`; it has no active segment, partial transcript, session id, finalization status, or chunk-sending state.
- `ComposerState.draft` is a plain `String`. There is no range owner for provisional transcript text.
- `ThreadDetailStore` owns draft mutation. This is good and should remain true.
- `AppServerClient` can transport JSON-RPC notifications and requests, but current typed app-server methods do not include transcription.
- `scripts/dock-relay.mjs` already owns the phone-facing privileged boundary, but it currently forwards app-server requests only and has no OpenAI Realtime lifecycle.

## 4.4 Observability + failure behavior today

- Swift voice errors surface as `composer.voice.lastError`.
- Transcription failures keep the existing draft recoverable.
- Send is blocked while `.recording` or `.transcribing`.
- The app does not log transcripts or audio in Swift today.
- Relay logs app-server aggregate/failure info. It must not start logging transcripts, audio chunks, base64 audio, OpenAI keys, or full OpenAI responses.
- There is no current telemetry for transcription latency, partial events, session closes, or chunk backpressure.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current:

```text
[ Message Codex                              ] [mic] [send]

Recording. Release to transcribe.
```

After release, user waits while status says:

```text
[ Message Codex                              ] [waveform] [send disabled]

Transcribing
```

Only after upload finishes:

```text
[ Check relay status                         ] [mic] [send]
```
<!-- arch_skill:block:current_architecture:end -->

<!-- arch_skill:block:target_architecture:start -->
# 5) Target Architecture (to-be)

## 5.1 On-disk structure (future)

- Swift voice:
  - `CodexDock/Voice/VoiceCaptureController.swift` is split or rewritten so the production capture path uses `AVAudioEngine` and emits 24 kHz mono PCM16 chunks.
  - `CodexDock/Voice/TranscriptionService.swift` defines a streaming transcription abstraction and keeps any file-upload client out of the physical default path.
  - New Swift types under `CodexDock/Voice/` define transcript stream events: started, delta, completed, failed, canceled, and closed.
- Swift composer:
  - `CodexDock/State/ThreadDetailStore.swift` owns active dictation segment reconciliation and Send gating.
  - `CodexDock/Features/Session/ComposerView.swift` renders live dictation state and keeps the existing text field.
- Relay:
  - `scripts/dock-relay.mjs` adds narrow Realtime transcription methods/events, an upstream OpenAI WebSocket client, session tracking, bounds, and cleanup.
  - `scripts/dock-relay.test.mjs` adds fake upstream OpenAI Realtime coverage.
- Config/docs:
  - `Makefile` exposes Mac-side Realtime model/delay configuration.
  - `README.md`, iPhone pairing plan, iPhone UX spec, multi-host service setup plan, Phase 8 plan/worklog docs, `project.yml`, and `CodexDockApp/Info.plist` are updated so production voice truth is Realtime streaming.

## 5.2 Control paths (future)

Target streaming path:

1. User presses mic in `ComposerView`.
2. `ThreadDetailStore.beginVoiceCapture()` creates an active dictation segment at the current draft end.
3. Store starts a streaming voice session through injected voice capture and transcription dependencies. `RelayRealtimeTranscriptionClient` opens a separate app-to-relay WebSocket for dictation instead of reusing the thread-detail app-server session. It uses the selected `DockHostConfiguration` exactly as discovered/configured; `bearerToken: nil` is valid for the physical relay.
4. iOS live capture emits bounded PCM chunks.
5. `RelayRealtimeTranscriptionClient` sends a narrow JSON-RPC start to `scripts/dock-relay.mjs`.
6. Relay opens a server-side WebSocket to OpenAI Realtime with `type: "transcription"`, `gpt-realtime-whisper`, 24 kHz mono PCM input, chosen delay/language config, and any server-side `OpenAI-Safety-Identifier`.
7. Swift sends audio chunks to the relay; relay forwards them to OpenAI with `input_audio_buffer.append`.
8. Relay receives incremental `conversation.item.input_audio_transcription.delta` events, accumulates them per `sessionId` plus OpenAI `item_id`, and forwards a sanitized notification containing both `deltaText` and cumulative `partialText`.
9. Store uses cumulative `partialText`, not the incremental `deltaText`, to replace the active dictation segment so the text field updates while the user is still speaking without duplicating or dropping words.
10. On release, Swift stops audio capture and commits/finalizes the relay/OpenAI buffer.
11. Relay forwards `conversation.item.input_audio_transcription.completed` final text.
12. Store replaces the active dictation segment with final text, clears active segment state, and keeps Send manual.

Stop/error path:

1. Audio capture stops for one explicit reason.
2. Relay closes upstream Realtime session and frees session state.
3. Store applies the stop reason policy:
   - successful release/commit keeps the active partial visible while finalizing, then replaces it with the final transcript;
   - explicit user cancel removes only the active provisional segment and preserves typed text outside it;
   - view disappear, `ThreadDetailStore.close()`, and `deinit` are lifecycle teardown cancels: stop mic, close relay, remove only the active provisional segment, and never submit;
   - upstream failure, invalid upstream payload, commit timeout, route interruption, app background, or capture failure after a partial freezes any visible provisional transcript as editable draft text, preserves user-typed draft text, clears active voice state, and reports a recoverable error;
   - capture startup failure before any partial preserves the existing draft, adds no transcript text, clears active voice state, and reports a recoverable error;
   - if final transcript already landed, it is normal draft text.
4. App background and foreground resume use the connectivity plan's root lifecycle path. Realtime voice can add detail-store hooks, but it must not add a separate scene-phase observer in `ComposerView` or a second app-wide lifecycle store.

Active edit policy:

1. `ThreadDetailStore` owns edit locking while voice is starting, streaming, or finalizing.
2. `ComposerView` keeps the text field visible but read-only/disabled for user edits while dictation is active.
3. Programmatic `updateDraft` calls during active dictation are ignored or rejected without mutating the draft.
4. The draft becomes editable again after final completion, explicit cancel, or recoverable failure.

## 5.3 Object model + abstractions (future)

- The production transcription service contract supports:
  - start session;
  - append audio chunks;
  - receive async transcript events;
  - commit/finalize;
  - cancel/close.
- The production live-capture protocol supports:
  - start live PCM capture;
  - emit 24 kHz mono PCM16 chunks or app-owned PCM format that is converted before relay send;
  - stop, commit, and cancel.
- `ComposerVoicePhase` expands from `.recording`/`.transcribing` to states that can describe live streaming:
  - idle;
  - starting;
  - streaming;
  - finalizing;
  - failed/recoverable via `lastError`.
- `ComposerVoiceState` gains active-session metadata:
  - `sessionID`;
  - active dictation segment id;
  - current provisional transcript;
  - optional final transcript;
  - last error.
- `ThreadDetailStore` gains draft segment helpers:
  - create active segment at the current draft end;
  - replace active segment with partial/final text;
  - clear active segment without touching typed text;
  - lock user draft edits while dictation is active so partial/final updates cannot race typed edits.
- Relay JSON-RPC contract stays purpose-specific. Method/event shape:
  - `audio/transcription/start` with no phone-side model and optional language/delay only if allowlisted by relay config;
  - `audio/transcription/append` with `sessionId`, `sequence`, and base64 PCM chunk;
  - `audio/transcription/commit` with `sessionId`;
  - `audio/transcription/cancel` with `sessionId`;
  - relay notification `audio/transcription/delta` with `sessionId`, `itemId`, `sequence`, `deltaText`, and cumulative `partialText`;
  - relay notifications `audio/transcription/completed`, `audio/transcription/failed`, `audio/transcription/canceled`, `audio/transcription/closed` with allowlisted, sanitized payloads.

## 5.4 Invariants and boundaries

- Mac relay owns `OPENAI_API_KEY`.
- Mac relay owns any OpenAI Realtime session credentials, including client-secret/WebRTC alternatives if those are ever introduced later.
- The phone may not set arbitrary OpenAI model, endpoint, or headers.
- The phone may not request or receive OpenAI Realtime client secrets or ephemeral provider tokens.
- The relay sets `OpenAI-Safety-Identifier` server-side when a stable privacy-preserving identifier is available.
- Relay only emits sanitized transcript events to the app.
- All app-visible Realtime errors, including JSON-RPC error responses from `start`/`append`/`commit`/`cancel` and failed notifications, use allowlisted error codes/categories and never forward raw upstream error messages, upstream bodies, transcript text, audio/base64, keys, client secrets, or provider headers.
- Relay must bound:
  - max chunk bytes;
  - max active sessions per client;
  - max session duration;
  - max pending upstream queue/backpressure;
  - upstream connection timeout.
- Swift must guarantee:
  - one active voice stream per composer;
  - Send disabled while streaming/finalizing;
  - user draft edits locked while streaming/finalizing;
  - cancel and errors never auto-submit;
  - draft reconciliation is local and deterministic.
- The old file-upload path is deleted from production and is not a runtime fallback.

## 5.5 UI surfaces (ASCII mockups, if UI work)

While speaking, partial text appears directly in the text box:

```text
[ Run the relay tests and check the log...    ] [mic.fill] [send disabled]

Listening
```

On release while finalizing:

```text
[ Run the relay tests and check the logs      ] [waveform] [send disabled]

Finalizing
```

After final:

```text
[ Run the relay tests and check the logs      ] [mic] [send]
```

On recoverable failure:

```text
[ Existing typed text frozen partial text     ] [mic] [send]

Realtime transcription stopped. Try again.
```
<!-- arch_skill:block:target_architecture:end -->

<!-- arch_skill:block:call_site_audit:start -->
# 6) Call-Site Audit (exhaustive change inventory)

## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Voice capture | `CodexDock/Voice/VoiceCaptureController.swift` | `VoiceCaptureControlling`, `VoiceCaptureController` | Records m4a file and returns URL on stop | Replace the production path with an `AVAudioEngine` live capture protocol | Need audio chunks while user speaks | async stream of bounded PCM chunks plus stop/cancel | New Swift voice capture unit seams; manual mic proof |
| Transcription protocol | `CodexDock/Voice/TranscriptionService.swift` | `TranscriptionServicing.transcribe(audioFile:)` | One-shot final string | Replace the production protocol with a streaming session abstraction and transcript events | Deltas/final/cancel cannot fit one return value | `RealtimeTranscriptionServicing` session/event API | ThreadDetail fake streaming service tests |
| Phone OpenAI client | `CodexDock/Voice/TranscriptionService.swift` | `OpenAITranscriptionClient` | Reads `OPENAI_API_KEY`, uploads file | Delete from the production app target and replace with relay-backed streaming construction | No phone-side secret; no slow fallback | relay-backed streaming client | Config/default-construction tests |
| Composer state | `CodexDock/State/ThreadDetailStore.swift` | `ComposerVoicePhase`, `ComposerVoiceState`, `ComposerState.canSend` | idle/recording/transcribing; busy blocks Send | Add streaming/finalizing states and active segment metadata; keep Send disabled while busy | State must represent partial transcript lifecycle | active dictation segment owned by store | ThreadDetailStoreTests |
| Draft mutation | `CodexDock/State/ThreadDetailStore.swift` | `insertTranscript`, `updateDraft` | Appends final text after upload; user edits always write draft | Add partial/final segment replacement, stop-reason behavior, and active-dictation edit lock | Prevent duplicate/erased text and edit/update races | deterministic segment reconciliation helpers | ThreadDetailStoreTests |
| Voice lifecycle | `CodexDock/State/ThreadDetailStore.swift` | `beginVoiceCapture`, `finishVoiceCapture`, `cancelVoiceCapture` | start file, stop file, upload, insert | Start streaming session, send chunks, commit on release, finalize on completion, cancel upstream | Actual realtime UX | async task owns capture+transcription streams | ThreadDetailStoreTests |
| Composer UI | `CodexDock/Features/Session/ComposerView.swift` | `micButton`, `voiceStatus`, `TextField` binding | Hold/release; shows Recording/Transcribing | Render Listening/Finalizing/error; keep text field bound to live draft; preserve hold-to-talk and add accessible tap-to-start/tap-to-stop mode | UI shows live text and remains usable for non-hold interaction | no new composer | Manual accessibility proof; store tests cover behavior |
| Detail lifecycle | `CodexDock/Features/Session/SessionDetailView.swift` | `.onDisappear { store.close() }` | Closes app-server session | Ensure close/cancel also closes active transcription stream | Avoid leaked mic/upstream session | `ThreadDetailStore.close()` cancels voice stream | Store tests |
| One-shot relay method | `scripts/dock-relay.mjs` | `handleRequest` case `"audio/transcribe"` | Accepts completed audio as one-shot base64 request | Remove from production path during cutover after streaming methods are live | Prevent hidden slow upload fallback | replaced by streaming `audio/transcription/*` methods | Node relay tests |
| Relay methods | `scripts/dock-relay.mjs` | `handleRequest` | Allows app-server methods and one-shot `audio/transcribe` | Add named transcription start/append/commit/cancel methods and delta/completed/failed/canceled/closed notifications; reject old raw `audio/transcribe` after cutover | Narrow Realtime bridge | JSON-RPC audio transcription stream contract | Node relay tests |
| Relay OpenAI client | `scripts/dock-relay.mjs` | new helper/client | None | Open server-side WebSocket to OpenAI Realtime, send session update/start config, forward audio, parse events | Secret stays on Mac | upstream Realtime WebSocket | Node fake upstream tests |
| Relay bounds/privacy | `scripts/dock-relay.mjs` | logging/error/JSON-RPC response paths | One-shot path can return relay error messages downstream | Enforce chunk/session/time bounds, redact logs, sanitize app-visible JSON-RPC errors and failed notifications, close on downstream disconnect | Avoid privacy/memory bugs and upstream detail leaks | fail-loud bounded relay with allowlisted errors | Node tests |
| Relay one-shot config/helpers | `scripts/dock-relay.mjs`, `scripts/dock-relay.test.mjs` | `DEFAULT_TRANSCRIPTION_MODEL`, `DEFAULT_TRANSCRIPTION_ENDPOINT`, `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL`, `CODEX_DOCK_OPENAI_TRANSCRIPTION_ENDPOINT`, `CODEX_DOCK_TRANSCRIPTION_MAX_BYTES`, `CODEX_DOCK_OPENAI_TRANSCRIPTION_TIMEOUT_MS`, `--openai-transcription-model`, `transcribeAudio`, `decodedAudioTranscribeParams`, helper exports, one-shot tests | File-upload model/endpoint/timeout helper surface | Delete or replace with Realtime-specific allowlisted config/tests | Prevent stale one-shot path from staying discoverable | relay-owned Realtime model/delay/bounds config | Node relay tests |
| Relay service config | `Makefile` | `dock-relay`, `env-file`, model vars | `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL=gpt-4o-transcribe` for file upload | Replace with Realtime model/delay vars owned by relay, e.g. `CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper`; stop passing phone-side OpenAI key env into the app | Realtime uses different model family and phone process must not receive OpenAI keys | Mac-side config only | Make/docs review |
| One-shot app method constants | `CodexDock/AppServer/AppServerMethods.swift` | `audioTranscribe` | Defines `"audio/transcribe"` | Remove from production app surface after streaming DTOs exist | Prevent old method reuse | replaced by typed streaming methods | AppServerClient/voice tests |
| One-shot app client method | `CodexDock/AppServer/AppServerClient.swift` | `audioTranscribe(params:timeout:)` | Sends one-shot `audio/transcribe` request | Remove from production app surface after streaming client exists | Prevent old method reuse | replaced by typed streaming client | AppServerClient/voice tests |
| One-shot audio DTOs | `CodexDock/AppServer/AudioTranscriptionDTO.swift` | `AudioTranscribeParams`, `AudioTranscribeResponseDTO` | Encodes full completed audio and final text | Remove from production app surface after streaming DTOs exist | Prevent old method reuse | replaced by streaming request/event DTOs | AppServerClient/voice tests |
| One-shot relay Swift client | `CodexDock/Voice/TranscriptionService.swift` | `RelayTranscriptionClient` | Reads completed file and calls `audio/transcribe` | Replace with `RelayRealtimeTranscriptionClient` | Prevent hidden slow relay upload fallback | streaming relay client | ThreadDetailStore/voice tests |
| App-server DTO/method constants | `CodexDock/AppServer/AppServerMethods.swift`, `CodexDock/Voice/*` DTO files | typed method names | Has one-shot `audio/transcribe`, no streaming transcription methods | Add explicit typed streaming transcription methods/notifications to the app-to-relay client surface, with voice DTOs kept under `CodexDock/Voice/` | Avoid stringly protocol drift without turning the client into a generic passthrough | narrow typed DTOs | AppServerClient/voice tests |
| Raw transport side door | `CodexDock/AppServer/AppServerClient.swift` | public `sendRequest(method:)`, `sendNotification(method:)` | Allows raw method strings | Keep as transport primitive, but production voice client must not use raw strings; relay must reject old `audio/transcribe` and malformed transcription method strings after cutover | Deleting typed one-shot APIs alone does not close stringly calls | typed voice client plus relay rejection proof | AppServerClient/voice/relay tests |
| Transport | `CodexDock/AppServer/AppServerClient.swift` | request/notification handling | Supports JSON-RPC | Use the existing host WebSocket/JSON-RPC transport implementation for a separate voice WebSocket owned by `RelayRealtimeTranscriptionClient` | Existing reliable socket path without mixing thread and voice notifications | separate relay voice connection, named methods only | Existing transport tests |
| Swift tests | `CodexDockTests/ThreadDetailStoreTests.swift` | fake voice/transcription services | One-shot fake returns final string | Fake streaming service emits deltas/final/fail/cancel | Prove user-visible behavior | async event fixtures | Updated/add tests |
| Node tests | `scripts/dock-relay.test.mjs` | helper tests | No server/upstream fake | Add relay contract and fake OpenAI Realtime tests | Prove secret/bounds/event behavior | fake ws upstream or injected client | Node tests |
| Docs and metadata | `README.md`, `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`, `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`, `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`, Phase 8 plan/worklog docs, `project.yml`, `CodexDockApp/Info.plist` | File-upload, release-to-transcribe-only, phone-key, hold-only, or `audio/transcribe` language | Update/supersede to Realtime streaming, tap mode, no slow fallback, and no phone OpenAI secret | Prevent stale implementation route and stale OS permission copy | docs and metadata match production path | Docs review; `rtk xcodegen generate --spec project.yml` if project metadata changes |

## 6.2 Migration notes

- Canonical owner path / shared code path:
  - `ThreadDetailStore` owns user-visible voice/composer state.
  - `CodexDock/Voice/` owns iOS audio capture plus relay-backed transcription client.
  - `scripts/dock-relay.mjs` owns OpenAI Realtime WebSocket, credentials, and app-facing transcription protocol.
- Superseded production APIs:
  - `TranscriptionServicing.transcribe(audioFile:)` is replaced by the streaming transcription contract for production dictation.
  - `OpenAITranscriptionClient` is removed from the production app target; tests use fakes rather than phone-side OpenAI file upload.
  - `RelayTranscriptionClient`, `AppServerMethods.audioTranscribe`, `AppServerClient.audioTranscribe`, `AudioTranscriptionDTO.swift`, and relay `audio/transcribe` handling are superseded by Realtime streaming methods for this voice path.
  - One-shot relay config/helper/test surfaces (`DEFAULT_TRANSCRIPTION_MODEL`, `DEFAULT_TRANSCRIPTION_ENDPOINT`, old `CODEX_DOCK_OPENAI_TRANSCRIPTION_*` env names, `CODEX_DOCK_TRANSCRIPTION_MAX_BYTES`, old timeout env, `--openai-transcription-model`, `transcribeAudio`, `decodedAudioTranscribeParams`, helper exports, and one-shot tests) are superseded by Realtime-specific config and tests.
- Delete list:
  - Delete automatic construction of phone-side `OpenAITranscriptionClient`.
  - Delete production dependency on completed m4a upload for dictation.
  - Delete production access to one-shot `audio/transcribe` method constants, DTOs, app client method, relay handler, and `RelayTranscriptionClient`.
  - Delete or replace one-shot relay transcription config/helper/export/test surfaces with Realtime-specific equivalents.
  - Delete docs that present file upload as the current production voice path after implementation.
- Adjacent surfaces tied to the same contract family:
  - Include now: Swift voice, ThreadDetail store/UI, relay, Makefile model config, Node/Swift tests, README/live docs.
  - Explicitly out of scope: direct mobile WebRTC, Realtime voice agents, assistant audio output, translation, diarization, background listening.
- Compatibility posture / cutover plan:
  - Clean cutover for production voice dictation.
  - Preserve existing text send/control semantics.
  - Preserve current app-server thread/session JSON-RPC behavior.
- Capability-replacing harnesses to delete or justify:
  - Do not add chunked file upload pretending to be realtime.
  - Do not add local speech recognition as a fallback.
- Live docs/comments/instructions to update or delete:
  - `README.md`
  - `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`
  - `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`
  - `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`
  - Phase 8 plan/worklog entries that describe the current production voice path.
  - `project.yml` and `CodexDockApp/Info.plist` microphone/local-network permission copy, because current hold-only copy becomes stale when tap mode ships.
- Behavior-preservation signals for refactors:
  - Existing ThreadDetail voice tests adapted to streaming.
  - Existing Dock/Archive/request-card tests remain green.
  - Manual proof confirms the same composer/send UX with live partial text.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Composer ownership | `ThreadDetailStore` | Store-owned draft mutation | Prevents UI or voice client from becoming alternate draft writers | include |
| Voice service injection | `ThreadDetailStore` initializer | Injected fakeable services | Keeps tests fast while production path changes | include |
| Relay privilege boundary | `scripts/dock-relay.mjs` | Named JSON-RPC methods | Avoids generic OpenAI proxy and keeps secrets on Mac | include |
| Audio model config | `Makefile`, relay env | Mac-side model/delay config | Prevents phone-side model selection drift | include |
| Raw JSON-RPC transport | `AppServerClient.sendRequest(method:)` | transport primitive, not production voice API | Prevents stringly voice calls while preserving existing app-server transport/tests | include |
| Direct mobile Realtime | future WebRTC client | Ephemeral token/WebRTC | Valid later latency optimization, not needed for server-owned-secret V1 | defer |
| Direct mobile WebSocket | `URLSessionWebSocketTask` to OpenAI | Provider secret on phone or token minting | Locally simple but violates V1 no-phone-secret boundary and OpenAI guidance | exclude |
| Old file upload | `OpenAITranscriptionClient` | delete production path | Prevents hidden slow fallback | include |
| Old relay one-shot upload | `audio/transcribe`, `RelayTranscriptionClient`, `AudioTranscriptionDTO` | delete production path | Prevents hidden slow relay fallback | include |
| Old relay transcription config/tests | `scripts/dock-relay.mjs`, `scripts/dock-relay.test.mjs`, `Makefile` | replace with Realtime-specific config/tests | Prevents stale file-upload model/endpoint helpers from becoming a fallback kit | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:phase_plan:start -->
# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 is the one authoritative execution checklist. `Work` explains the unit; `Checklist (must all be done)` is binding; `Exit criteria (all required)` is what an audit must validate. No hidden runtime fallback: if Realtime cannot work, the composer fails visibly instead of silently using slow file upload.

## Phase 0 - Top-Level Prerequisite Check

* Goal:
  - Confirm Realtime starts after the Connectivity owner exists, so voice recovery does not create a second lifecycle/status path.
* Status:
  - Complete in the current working tree. `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md` records the readback: `AppConnectivityStore`, `AppLifecycleCoordinator`, root-owned Dock refresh, scene-phase forwarding, and `ThreadDetailStore` lifecycle input are present. Phase 1 did not add a second lifecycle, `scenePhase`, reconnect, or connectivity authority.
* Checklist (must all be done before Phase 1 starts):
  - Do not start Realtime until `docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md` has landed.
  - Required baseline symbols/behaviors: `AppConnectivityStore` exists, the root lifecycle owner exists, `DockView.runRefreshLoop()` is gone or no longer authoritative, background/foreground resume is modeled, and `ThreadDetailStore` receives lifecycle/reconnect inputs from that owner.
  - Realtime phases may add voice participants to the Connectivity lifecycle; they must not create a second app lifecycle, `scenePhase`, reconnect, or connectivity authority.
* Exit criteria (all required):
  - A focused readback confirms the current branch has the Connectivity lifecycle/status owner.
  - Any Realtime implementation notes name the Connectivity lifecycle inputs they consume.

## Phase 1 - Relay Realtime Transcription Contract

* Goal:
  - Prove the highest-risk privilege and protocol seam first: the Mac relay can own an OpenAI Realtime transcription session, accept bounded app audio chunks, and stream sanitized transcript events back without exposing OpenAI secrets to the phone.
* Status:
  - Code-complete in the current working tree, not accepted from mocks. The relay now exposes `audio/transcription/start`, `audio/transcription/append`, `audio/transcription/commit`, and `audio/transcription/cancel`; owns OpenAI Realtime WebSocket setup; validates sequence/chunk/session bounds; accumulates transcript deltas; emits sanitized delta/completed/failed/canceled/closed notifications; and cleans up on cancel, upstream close, downstream close, timeout, or completion.
  - Preflight proof passed on 2026-05-28: `node --check scripts/dock-relay-realtime-transcription.mjs`, `node --check scripts/dock-relay-realtime-transcription.test.mjs`, `node --check scripts/dock-relay.mjs`, `node --test scripts/dock-relay-realtime-transcription.test.mjs` with 8 tests and 0 failures, `rtk npm run test:relay` with 41 tests and 0 failures, and focused `rtk git diff --check`. These tests use fake/mock upstreams and do not count as acceptance proof.
  - Acceptance proof status: later proof ran the relay against real OpenAI Realtime with the Mac-side `OPENAI_API_KEY`, streamed representative PCM through the relay contract, received real OpenAI transcription events, and recorded physical iPhone 14 user manual proof for the current installed app path.
  - The legacy one-shot `audio/transcribe` path still exists at this phase. That is intentional until Phase 5, where the production fallback surface must be deleted/rejected after Swift has moved to the Realtime path.
* Work:
  - Add the narrow relay-side session manager and fake-upstream test harness before touching Swift UI. This phase proves the server-side WebSocket shape, session lifecycle, privacy boundaries, and event ordering that later Swift work will depend on.
* Checklist (must all be done):
  - Add purpose-specific relay JSON-RPC methods in `scripts/dock-relay.mjs`: `audio/transcription/start`, `audio/transcription/append`, `audio/transcription/commit`, and `audio/transcription/cancel`.
  - Keep the method allowlist explicit; do not add a generic OpenAI proxy, arbitrary upstream URL, arbitrary model field, arbitrary header field, or raw `sendOpenAIEvent` method.
  - Add relay session tracking with one active transcription session per downstream voice WebSocket/composer session.
  - Configure upstream OpenAI Realtime transcription on the relay with `type: "transcription"`, default model `gpt-realtime-whisper`, `audio/pcm` input, 24 kHz mono PCM expectation, and relay-owned language/delay allowlists.
  - Attach `OpenAI-Safety-Identifier` server-side when a stable privacy-preserving local identifier is available.
  - Read `OPENAI_API_KEY` only in the Mac relay process; never accept it from the phone and never echo it in responses.
  - Forward app audio chunks to OpenAI as `input_audio_buffer.append` with monotonic downstream `sequence` validation.
  - Commit/finalize with `input_audio_buffer.commit` when the app releases the mic.
  - Accumulate OpenAI `conversation.item.input_audio_transcription.delta` text per relay `sessionId` plus OpenAI `item_id`, and map it into sanitized `audio/transcription/delta` notifications carrying `deltaText` plus cumulative `partialText`.
  - Map OpenAI `.completed` into sanitized completion notifications carrying final text and matching session/item ids.
  - Emit app-visible `audio/transcription/failed` for upstream errors, invalid upstream payloads, timeout, and relay-side fatal session errors.
  - Emit app-visible `audio/transcription/canceled` after downstream cancel is accepted.
  - Emit app-visible `audio/transcription/closed` when the upstream or downstream session closes after cleanup.
  - Enforce max chunk bytes, max session duration, max pending upstream queue, upstream connect timeout, and downstream disconnect cleanup.
  - Sanitize every app-visible Realtime JSON-RPC error response and notification so it uses allowlisted error categories only and never forwards raw upstream error messages, upstream bodies, transcript text, audio/base64, keys, client secrets, or provider headers.
  - Redact relay logging so logs contain lifecycle counts/error categories only and never OpenAI keys, raw audio bytes, base64 audio, transcript text, or full upstream payloads.
  - Add `scripts/dock-relay.test.mjs` coverage with an injected or fake OpenAI Realtime WebSocket that proves start, append, commit, delta accumulation into `partialText`, completed, cancel, upstream error, downstream disconnect, bounds rejection, ordering, downstream JSON-RPC error sanitization, failed-notification sanitization, and log redaction behavior.
* Verification (required proof):
  - `rtk npm run test:relay`
  - Real relay-to-OpenAI Realtime smoke proof with redacted evidence. Mock/fake-upstream tests are preflight checks and do not count as acceptance proof.
* Docs/comments (propagation; only if needed):
  - Add a short relay-boundary comment at the transcription session manager explaining that the method family is purpose-specific and must not become a generic OpenAI proxy.
* Exit criteria (all required):
  - The relay can run a complete fake-upstream transcription session from start through final completion.
  - The relay emits app-visible delta notifications with both incremental `deltaText` and cumulative `partialText`, plus completed, failed, canceled, and closed notifications with sanitized payloads.
  - The relay rejects oversized/out-of-order chunks and closes sessions on cancel, upstream close, or downstream disconnect.
  - Tests prove the phone cannot supply or override OpenAI model, endpoint, provider headers, provider credentials, or `OpenAI-Safety-Identifier`.
  - Tests prove sanitized notifications, sanitized downstream JSON-RPC errors, and secret/audio/transcript log redaction.
  - No Swift app code or simulator launch path is required for the relay to pass this phase.
* Rollback:
  - Remove the relay transcription methods/session manager/tests from `scripts/dock-relay.mjs` and `scripts/dock-relay.test.mjs`. Existing app-server forwarding methods remain unchanged.

## Phase 2 - Store-Owned Streaming Draft Reconciliation

* Goal:
  - Preflight-check the user-visible composer state machine with fake streaming events before depending on live audio or network timing.
* Work:
  - Replace the one-shot store mental model with a streaming voice state machine owned by `ThreadDetailStore`. This phase keeps the transport fake, so tests can focus on partial/final/cancel/error behavior in the single existing composer.
  - Current implementation note: code-complete in the working tree as preflight only. Fake Swift streaming sessions check store behavior, but they do not count as acceptance proof.
* Checklist (must all be done):
  - Define Swift transcript event/session types under `CodexDock/Voice/` for started, delta, completed, failed, canceled, and closed.
  - Replace production `TranscriptionServicing.transcribe(audioFile:)` with a fakeable streaming transcription service contract that supports start, append/audio input coordination, commit, cancel, and async transcript events.
  - Add a live-audio capture protocol shape that can later emit PCM chunks, while Phase 2 fakes drive transcript events without touching the microphone.
  - Expand `ComposerVoicePhase` to represent starting, streaming/listening, finalizing, idle, and recoverable failure states.
  - Add active dictation segment metadata to `ComposerVoiceState`: session id, active segment id/range anchor, provisional transcript, final transcript, and last error.
  - Implement deterministic draft helpers in `ThreadDetailStore` for creating an active segment, replacing that segment with cumulative `partialText`, replacing it with final text, clearing it on explicit cancel/lifecycle teardown, freezing it on recoverable failure when partial text exists, and preserving user text outside that segment.
  - Lock user edits while voice is starting, streaming, or finalizing; `updateDraft` must not mutate the draft during active dictation.
  - Implement the stop-reason policy from Section 5.2 for release/commit success, explicit user cancel, view disappear/`close()`/`deinit`, upstream failure, invalid upstream payload, commit timeout, route interruption, app background, and capture startup failure.
  - Make `beginVoiceCapture()` create the active segment and start the streaming service.
  - Make `finishVoiceCapture()` commit/finalize and wait for completion without clearing the partial text prematurely.
  - Make `cancelVoiceCapture()`, `close()`, and `deinit` close the streaming service and apply the exact stop-reason outcome.
  - Keep Send disabled while starting, streaming, or finalizing.
  - Keep voice from auto-submitting a Codex turn under all partial/final/error sequences.
  - Update `CodexDockTests/ThreadDetailStoreTests.swift` fakes and tests for cumulative `partialText` replacement, final-replaces-partial, typed prefix preservation, active edit locking, explicit cancel removal, lifecycle teardown removal, upstream failure freezing visible partial text as editable draft text, commit timeout behavior, route interruption/app background behavior, capture startup failure behavior, close/deinit cleanup, and Send gating.
* Verification (required proof):
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test`
* Docs/comments (propagation; only if needed):
  - Add one local code comment near the active-segment reconciliation helper describing the invariant: only the active provisional segment may be replaced by transcript updates.
* Exit criteria (all required):
  - Store tests prove text appears in `composer.draft` from cumulative `partialText` before commit/final completion.
  - Store tests prove final transcript reconciliation does not duplicate partial text.
  - Store tests prove typed text outside the active segment survives partial, final, explicit cancel, lifecycle teardown, and failure, and upstream failure leaves visible partial text editable instead of discarding it.
  - Store tests prove `updateDraft` cannot mutate the draft while dictation is starting, streaming, or finalizing, and text becomes editable again after final/cancel/failure.
  - Store tests prove Send remains manual and disabled during active voice states.
  - `ThreadDetailStore` remains the only writer that mutates the composer draft for voice text.
* Rollback:
  - Revert the Swift streaming state-machine changes and tests to the previous one-shot voice service contract. This rollback is code-level only; it does not introduce a runtime fallback in a completed implementation.

## Phase 3 - Swift Relay Client Integration With Synthetic Audio

* Goal:
  - Connect the store-owned streaming contract to the relay contract using synthetic audio chunks, proving the phone-to-relay path without relying on live microphone capture yet.
* Work:
  - Add a relay-backed transcription client that speaks the Phase 1 JSON-RPC contract and feeds the Phase 2 transcript event model. This is the cutover point for Swift production construction away from phone-side OpenAI file upload.
* Checklist (must all be done):
  - Add explicit typed app-to-relay transcription requests and notifications for `audio/transcription/start`, `append`, `commit`, `cancel`, `delta` with cumulative `partialText`, `completed`, `failed`, `canceled`, and `closed`.
  - Use the existing host WebSocket/JSON-RPC transport implementation for the phone-to-relay path, but open a separate relay WebSocket owned by `RelayRealtimeTranscriptionClient`; do not reuse the thread-detail session's notification stream.
  - Add `RelayRealtimeTranscriptionClient` under `CodexDock/Voice/` that owns its connection, notification iterator, request ids, chunk sequencing, commit/cancel lifecycle, and maps relay requests/notifications to the streaming transcript event contract.
  - Construct `RelayRealtimeTranscriptionClient` from the selected `DockHostConfiguration` supplied by `RelayBootstrapStore`/`HostRegistry`.
  - Connect the voice client to `host.webSocketURL` and pass `host.bearerToken` into the WebSocket transport exactly like `AppServerClient`; nil bearer is the normal physical iPhone path and must omit `Authorization`.
  - Do not read host env vars directly, hard-code `:4510`, or require `SIMCTL_CHILD_*` values for production voice.
  - Keep raw `AppServerClient.sendRequest(method:)` and `sendNotification(method:)` as transport primitives only; production transcription code must use typed transcription wrappers/constants and must not construct transcription method strings outside the typed API.
  - Ensure the client sends bounded base64 PCM chunks with sequence numbers and rejects local attempts to set OpenAI model, endpoint, provider headers, or provider credentials.
  - Update `ThreadDetailStore` production defaults so physical/simulator app construction uses the relay-backed streaming client, not `OpenAITranscriptionClient`.
  - Remove `OpenAITranscriptionClient` from production app construction; tests use fakes rather than a phone-side OpenAI file-upload client.
  - Remove `RelayTranscriptionClient`, `AppServerClient.audioTranscribe`, `AppServerMethods.audioTranscribe`, and one-shot `AudioTranscriptionDTO` use from production voice construction; tests use fakes or the new streaming client.
  - Add Swift transport/client tests using scripted relay notifications for cumulative partial delta, completed, failed, canceled, closed, out-of-order session events, commit timeout, cancel, connection cleanup, and thread-session independence.
  - Add tests proving the app process does not require `OPENAI_API_KEY` for default voice construction.
* Verification (required proof):
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test`
* Docs/comments (propagation; only if needed):
  - Add a short comment at the relay-backed transcription client boundary explaining that OpenAI credentials are relay-owned and phone inputs are limited to audio/session control.
* Exit criteria (all required):
  - Swift tests prove relay delta/final notifications drive the same draft behavior proven in Phase 2.
  - Swift tests prove `RelayRealtimeTranscriptionClient` owns a separate voice WebSocket and closes it on commit, cancel, failure, and store close without interfering with the thread-detail session.
  - Swift tests prove default voice construction is relay-backed and does not read `OPENAI_API_KEY` in the app process.
  - No phone-side OpenAI model/endpoint/header/credential input exists in the relay-backed client.
  - Production transcription code uses typed transcription APIs rather than raw method strings.
  - The old file-upload transcription client is not reachable as an automatic runtime fallback.
  - The old one-shot relay `audio/transcribe` Swift surface is not reachable as an automatic runtime fallback.
* Rollback:
  - Revert the relay-backed Swift client and restore injected fake-only streaming service for tests. Do not ship rollback as a fallback mode inside the app.

## Phase 4 - Live PCM Capture And Accessible Composer Interaction

* Goal:
  - Replace file recording with live microphone chunks and expose the final in-place live dictation UX in `ComposerView`.
* Current implementation note:
  - Code-complete in the current working tree. `LiveVoiceCaptureController` uses `AVAudioEngine` to emit 24 kHz mono PCM16 chunks, `ThreadDetailStore` forwards those chunks into `RealtimeTranscriptionSession.appendAudio(...)`, release stops capture before commit, the hold-release path stays enabled while startup/finalizing state changes, tap-to-start/tap-to-stop dictation uses the same relay-backed session path, and route/interruption cleanup finishes active capture.
  - Real relay-to-OpenAI proof has passed, and the user confirmed the physical iPhone 14 Realtime audio path worked after the empty-transcript relay fix. Preflight tests still remain useful but are not the acceptance proof by themselves.
  - Closeout status: detailed manual checklist evidence for held-mic mode, tap mode, typed-prefix preservation, explicit Send/no auto-submit, cancel/interruption recoverability, and accessibility behavior is marked passed by user manual physical iPhone 14 check for the current installed build.
* Work:
  - Add the real `AVAudioEngine` capture path, convert microphone input to relay-ready PCM, and wire the existing composer controls to streaming/finalizing states. This phase turns the proven contract into the actual user experience.
* Checklist (must all be done):
  - Replace production `AVAudioRecorder` recording with an `AVAudioEngine` live capture session that emits bounded 24 kHz mono PCM16 chunks.
  - Configure `AVAudioSession` for dictation capture and handle permission denial, route interruption, app background, and capture startup failure as visible recoverable voice errors.
  - Use the root lifecycle/app-background contract from the connectivity plan for app background handling. Do not add tab-local or view-local scene-phase ownership to the composer.
  - For app background, Realtime does not observe SwiftUI `scenePhase` directly. The Connectivity-owned `AppLifecycleCoordinator` or equivalent root lifecycle owner sends a lifecycle event to the open detail/composer path. Realtime implements the voice participant behavior only: stop/cancel capture, close the relay transcription session, preserve recoverable draft state, and never auto-submit.
  - Stop audio capture immediately on release while keeping the transcription session alive until commit/final completion or visible failure.
  - Ensure cancel, view disappear, interruption, and `ThreadDetailStore.close()` stop the mic and close the relay transcription session.
  - Update `ComposerView` to render listening, finalizing, failed, and idle states without introducing a separate voice screen or second composer.
  - Preserve hold-to-talk press/release behavior.
  - Add a tap-to-start/tap-to-stop mode reachable from the composer control for users who cannot comfortably hold the mic; `ThreadDetailStore` owns the tap-mode lifecycle/state and `ComposerView` only dispatches tap/hold intents.
  - Add control-state tests for tap start, tap stop, repeated tap idempotence, tap while finalizing, Send disabled while tap mode is active, close/disappear cleanup, and no second stream when hold and tap paths interact.
  - Keep the text field as the live partial transcript surface and keep final text editable before Send.
  - Make the text field visibly read-only or disabled for user edits while dictation is active, while still showing store-driven partial transcript updates.
  - Preserve Dynamic Type layout, VoiceOver labels/hints, button hit targets, and non-overlapping status text across supported sizes.
  - Add or update Swift/UI-facing tests around control state through the repo's existing stable test seams; keep behavior-critical assertions in store tests.
* Verification (required proof):
  - `rtk swift test`
  - Manual simulator or physical-device proof that holding the mic streams text before release and releasing finalizes without auto-submit.
  - Manual accessibility check for tap mode, VoiceOver labels/hints, and large Dynamic Type layout.
* Docs/comments (propagation; only if needed):
  - Add a short code comment near audio format conversion if the conversion math is not self-evident.
* Exit criteria (all required):
  - The production capture path emits live PCM chunks instead of waiting for a completed m4a file.
  - The existing composer displays partial transcript text while speech is still in progress.
  - Release finalizes the transcript and leaves text editable with Send still manual.
  - Explicit cancel/interruption/view close stops mic capture and closes relay session without submitting.
  - Hold mode and tap mode both work from the composer.
  - Repeated taps and hold/tap interactions cannot create duplicate streams or skip cleanup.
  - Text editing is locked during active dictation and restored after final/cancel/failure.
  - Accessibility checks confirm labels, hit targets, Dynamic Type, and status layout remain usable.
* Rollback:
  - Revert the live capture/UI wiring to the Phase 3 synthetic-audio integration state. Do not retain old file upload as a hidden runtime fallback.

## Phase 5 - Cutover Cleanup, Docs, And Final Proof

* Goal:
  - Remove stale production assumptions, update live operational truth, and prove the full destination end to end.
* Work:
  - Complete the clean cutover: Mac relay owns Realtime and secrets, the phone streams live dictation into the existing composer, and live docs/tests no longer teach the old file-upload production path.
* Checklist (must all be done):
  - Remove production construction and simulator launch dependence on phone-side `OPENAI_API_KEY`.
  - Keep `OPENAI_API_KEY` Mac-side for the relay, including repo `.env` when used by `rtk make services`.
  - Update `Makefile` so Realtime transcription model/delay configuration is Mac relay-owned and no `SIMCTL_CHILD_OPENAI_API_KEY`, physical app config key, or Swift default construction exposes `OPENAI_API_KEY` to the app process.
  - Rename/replace the old one-shot relay model env with a relay-only Realtime model env, but do not remove the relay's Mac-side OpenAI key source.
  - Delete production `OpenAITranscriptionClient`, `RelayTranscriptionClient`, m4a file-upload transcription code paths, one-shot `audio/transcribe` app DTO/client surfaces, and relay one-shot handler access; production defaults cannot call them.
  - Delete or replace one-shot relay config/helper/test surfaces: `DEFAULT_TRANSCRIPTION_MODEL`, `DEFAULT_TRANSCRIPTION_ENDPOINT`, old `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL`, old `CODEX_DOCK_OPENAI_TRANSCRIPTION_ENDPOINT`, `CODEX_DOCK_TRANSCRIPTION_MAX_BYTES`, old `CODEX_DOCK_OPENAI_TRANSCRIPTION_TIMEOUT_MS`, `--openai-transcription-model`, `transcribeAudio`, `decodedAudioTranscribeParams`, old helper exports, and one-shot `audio/transcribe` tests.
  - Add relay tests proving raw `audio/transcribe` requests are rejected after cutover, including requests sent through a raw JSON-RPC method string.
  - Update `README.md` service/runbook sections to describe relay-backed Realtime transcription and `rtk npm run test:relay`.
  - Rewrite or explicitly supersede each voice-transcription section/table/phase/decision in `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md` that prescribes `audio/transcribe`, `gpt-4o-transcribe`, m4a upload, or one-shot relay transcription.
  - Update `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`, `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`, and Phase 8 plan/worklog voice docs that describe release-to-transcribe, one-shot `audio/transcribe`, phone-side OpenAI keys, hold-only dictation, or production voice so they describe in-place streaming dictation, accessible tap mode, no auto-submit, and no phone OpenAI secret.
  - Update `project.yml` and `CodexDockApp/Info.plist` microphone/local-network permission copy for tap-to-start/tap-to-stop and relay-backed voice, then run `rtk xcodegen generate --spec project.yml`.
  - Confirm relay logs and app logs do not include audio chunks, base64 audio, transcript text, OpenAI keys, Realtime client secrets, or full upstream payloads.
  - Run the full Swift and relay test commands.
  - Perform final manual physical iPhone proof with relay services running.
* Verification (required proof):
  - `rtk npm run test:relay`
  - `rtk swift test`
  - `rtk make services`
  - `rtk make app` for simulator smoke plus the repo-standard physical-device launch path
  - Manual proof on physical iPhone: speak while holding mic, observe text before release, release, edit the final draft, tap Send manually, verify no auto-submit occurred.
  - Manual proof on physical iPhone: type a prefix, dictate, verify typed text survives final reconciliation, then cancel/interruption path verifies no submit and no draft corruption.
  - Manual accessibility proof on physical iPhone: tap-to-start/tap-to-stop works, VoiceOver labels/hints are meaningful, hit targets are usable, and large Dynamic Type keeps status/control text readable without overlap.
  - Physical-device operating note: this checklist is marked passed by user manual physical iPhone 14 check for the current installed build. Future physical checks are deferred manual QA for Amir and must not block implementation when simulator/local/real-relay proof passes.
  - Required physical iPhone 14 closeout checklist:

    | Item | Required passing evidence |
    | --- | --- |
    | Held dictation live partial | Press and hold `Hold to dictate`, speak, and confirm transcript text appears in the existing composer before release. |
    | Held dictation final/edit/send | Release after live text appears, confirm final text remains editable, and confirm no Codex turn submits until `Send` is tapped. |
    | Tap dictation live partial | Tap `Start dictation`, speak, tap `Stop dictation`, and confirm final text remains in the same editable composer draft. |
    | Typed-prefix preservation | Type text before dictation, dictate, finalize, and confirm typed text outside the active dictation segment was not overwritten. |
    | Cancel/interruption recovery | Start dictation, interrupt through a real path such as navigating back, backgrounding the app, or an audio interruption, and confirm no submit, no draft corruption, and a recoverable composer state. |
    | Accessibility labels/hints | Confirm `Message`, `Hold to dictate`, `Start dictation` / `Stop dictation`, and `Send` expose meaningful labels and hints. |
    | Hit targets and Dynamic Type | Confirm voice controls and `Send` remain tappable and status/control text stays readable without overlap at large Dynamic Type. |
* Docs/comments (propagation; only if needed):
  - Live docs listed in the checklist are part of this phase's required work; delete stale voice-path prose rather than preserving contradictory instructions.
* Exit criteria (all required):
  - Production voice dictation uses relay-backed OpenAI Realtime transcription.
  - The phone process receives no OpenAI API key, Realtime client secret, ephemeral provider token, provider bearer, or provider-controlled model/endpoint/header input.
  - File-upload transcription and one-shot relay `audio/transcribe` are not automatic runtime fallbacks.
  - Old one-shot relay config/helpers/exports/tests are deleted or replaced with Realtime-specific equivalents.
  - Raw JSON-RPC requests to `audio/transcribe` are rejected after cutover.
  - Full Swift tests and relay tests pass.
  - Manual proof confirms live partial text, final reconciliation, typed-text preservation, editable draft, explicit Send, cancel/error recoverability, accessible tap mode, VoiceOver labels/hints, hit targets, and Dynamic Type layout.
  - Live docs and Makefile/runbook instructions match the implemented production path.
* Rollback:
  - Revert the clean-cutover implementation as a code rollback. Do not add a runtime switch that silently falls back to slow file upload.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy

- Prefer Swift store tests for draft reconciliation and send gating because that is where the user-visible behavior is owned.
- Prefer Node relay tests with a fake OpenAI Realtime WebSocket/server seam for relay contract, auth, bounds, and log redaction.
- Keep manual device/simulator proof for the actual live microphone path and perceived latency.
- Do not add repo-policing gates whose only proof is that old strings are absent.
- Expected command proof:
  - `rtk swift test`
  - `rtk npm run test:relay`
  - `rtk xcodegen generate --spec project.yml` in any implementation phase that edits `project.yml`
  - final manual service proof through `rtk make services`, `rtk make app`, and the project-standard physical-device run path

# 9) Rollout / Ops / Telemetry

- Roll out as a clean production voice-path cutover once tests and manual proof are green.
- Keep Realtime model and delay setting Mac-side relay config, not phone-controlled.
- Log connection/session lifecycle counts and error categories only; never log audio chunks, base64 payloads, transcript text, OpenAI keys, or full upstream responses.
- Fail visibly in the composer if the relay cannot start or maintain a transcription session.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers: Newton, Kant, self-integrator
- Scope checked:
  - Frontmatter, TL;DR, Sections 0-10, helper blocks, phase plan, research/current/target/call-site sections, verification, rollout, cleanup, and required deletes.
- Findings summary:
  - Section 0 manual proof for typed-text preservation was not fully carried into Phase 5.
  - Existing one-shot `audio/transcribe` app/relay surfaces were undercounted in the call-site audit and cleanup plan.
  - Phase 1 did not explicitly require app-visible failed, canceled, and closed relay notifications even though later Swift phases depended on them.
  - The OpenAI safety identifier rule needed an explicit proof hook.
  - The future WebRTC exception and final accessibility proof needed clearer carry-through.
- Integrated repairs:
  - Updated TL;DR and Phase 5 proof to require physical typed-text preservation, cancel/interruption recoverability, and full accessibility proof.
  - Added current one-shot `audio/transcribe` surfaces to Sections 3, 4, 6, and Phase 5: `RelayTranscriptionClient`, `AppServerMethods.audioTranscribe`, `AppServerClient.audioTranscribe`, `AudioTranscriptionDTO.swift`, and relay handler access.
  - Added relay failed, canceled, and closed notification requirements to the target contract and Phase 1 checklist/exit criteria.
  - Added proof that the phone cannot supply or override OpenAI model, endpoint, provider headers, provider credentials, or `OpenAI-Safety-Identifier`.
  - Added the future WebRTC exception to the decision log as a deferred non-V1 latency option only.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

- 2026-05-28 - Intent-derived - The user explicitly requested a new ArcStep auto plan for OpenAI Realtime streaming STT and asked for end-to-end planning, so the North Star is treated as confirmed for the purpose of running auto-plan immediately.
- 2026-05-28 - Architecture direction - Choose Realtime transcription rather than Realtime voice-agent or request-response Audio API because the requested outcome is live transcript deltas in a text box without spoken assistant output.
- 2026-05-28 - Secret boundary - Choose Mac relay server-side Realtime WebSocket over direct phone WebSocket/WebRTC for V1. This keeps OpenAI keys and Realtime client secrets off the phone and matches the existing personal relay security direction.
- 2026-05-28 - UX/accessibility - Preserve hold-to-talk as the fast path, but require a tap-to-start/tap-to-stop dictation mode and Dynamic Type/VoiceOver-safe controls before the plan is implementation-ready.
- 2026-05-28 - Future exception - Direct mobile WebRTC with ephemeral OpenAI credentials is deferred as a possible future latency optimization only; it is not a V1 fallback, and no phone-side Realtime client secret is allowed in this plan.
- 2026-05-28 - Relay event DTO - Relay `delta` notifications carry both incremental `deltaText` and cumulative `partialText`; `ThreadDetailStore` uses `partialText` for draft replacement.
- 2026-05-28 - Active edit policy - The composer locks user edits while dictation is starting, streaming, or finalizing; text becomes editable again after final, explicit cancel, or recoverable failure.
- 2026-05-28 - Connection ownership - `RelayRealtimeTranscriptionClient` owns a separate app-to-relay WebSocket for dictation instead of reusing the thread-detail session's notification stream.
- 2026-05-28 - Stop reasons - Explicit user cancel and lifecycle teardown remove only the active provisional segment; recoverable failures after partial text freeze that partial as editable draft text; final text is normal draft text after completion.
- 2026-05-28 - Raw JSON-RPC boundary - Public raw JSON-RPC helpers remain transport primitives, but production voice must use typed transcription APIs and the relay must reject old or malformed transcription method strings after cutover.
