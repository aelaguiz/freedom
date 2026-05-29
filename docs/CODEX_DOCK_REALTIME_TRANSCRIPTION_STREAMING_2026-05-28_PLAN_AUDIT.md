# Plan Audit Log

Plan: `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: Phase 5 cutover cleanup and structural cleanup passed programmatic/real-relay proof; basic physical iPhone 14 Realtime audio proof passed by user manual test; detailed manual closeout checklist passed by user manual physical iPhone 14 check on 2026-05-28
Last reviewed: 2026-05-28T20:14:00Z
Scope: whole plan

## Current Code/Design Blocking Findings

None. Realtime closeout is accepted for the current installed build, and the current code/design review has no unresolved blocking findings.

## Current Acceptance Proof Blockers

- None for current Realtime closeout.
- Physical Mobile MCP was intentionally not used because WebDriverAgent is not running on `00008110-000E04940240A01E`; user manual testing is the physical proof source.
- The source checklist is now carried in `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md` under Phase 5 "Verification (required proof)", and the evidence capture ledger is `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md` under "Manual Physical iPhone 14 Closeout Checklist".

## Current Non-Blocking Findings

None.

## 2026-05-28 Manual Physical Checklist Completion Audit

Verdict: approve for Realtime manual physical closeout evidence.

Evidence reviewed:

- User confirmed the remaining physical iPhone 14 manual checklist had already been checked and asked to mark it off in the docs.
- The implementation log now records the checklist rows as passed by user manual check.
- The check ran against the physical iPhone 14 path, not mocks, fake Swift sessions, simulator-only evidence, or physical Mobile MCP.

Acceptance boundary:

- Realtime manual physical closeout is accepted for the current installed build.
- A later voice/composer/capture/relay transcription code change invalidates this physical evidence and should add a fresh physical checklist item to Amir's deferred manual QA list rather than blocking implementation.

## 2026-05-28 Manual Physical Checklist Canonicalization Audit

Verdict: superseded by the completion audit above. The checklist source/evidence locations remain correct.

Evidence reviewed:

- The Realtime plan now owns the required physical iPhone 14 checklist in Phase 5 "Verification (required proof)".
- The implementation log owns the evidence capture ledger and points back to the Realtime plan as the source checklist.
- The top-level dock plan points to both the source checklist and evidence ledger.
- The Multi-host implementation log now treats Phase 1B/Phase 2 as unblocked by Realtime manual evidence.
- `README.md` now gives the short physical iPhone 14 manual test list and tells the tester where to record evidence.

Verification:

- `rtk git diff --check -- README.md docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_IMPLEMENTATION_LOG.md docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28_IMPLEMENTATION_LOG.md`
- `rtk make app-server-status` returned HTTP 200 OK for `ws://192.168.50.117:4500`.
- `rtk make dock-relay-status` returned readyz OK for `ws://192.168.50.117:4510` with `phone auth: none`.
- `.env` mtime remained `1779986258`.

Remaining proof gap:

- None for Realtime manual physical closeout on the current installed build. Future physical checks are deferred manual QA under the parent dock operating rule when later voice/composer/capture/relay transcription changes land.

## 2026-05-28 Realtime Structural Cleanup Implementation Audit

Verdict: pass for code shape, automated proof, and physical install/launch; later completion audit above records detailed checklist evidence as passed by user manual check.

Evidence reviewed:

- `CodexDock/State/ThreadDetailStore.swift` was split so voice/composer state and voice-capture orchestration now live in `CodexDock/State/ThreadDetailStore+Voice.swift`. Current line counts: `ThreadDetailStore.swift` `890`; `ThreadDetailStore+Voice.swift` `556`.
- `scripts/dock-relay.mjs` was split so thread list/read/archive aggregation now lives in `scripts/dock-relay-thread-data.mjs`. Current line counts: `dock-relay.mjs` `649`; `dock-relay-thread-data.mjs` `657`.
- The relay extraction boundary was tested and repaired: `thread/resume` still needed `collectLiveRows`, `initializeClient`, `parseLimit`, and `JsonRpcWebSocketClient` available to the server/session module.
- Physical iPhone 14 install/launch still targets `00008110-000E04940240A01E`; no physical Mobile MCP was used.
- `.env` mtime remained `1779986258` after the cleanup and install.

Verification passed:

- `rtk node --check scripts/dock-relay.mjs`
- `rtk node --check scripts/dock-relay-thread-data.mjs`
- `rtk node --test scripts/dock-relay-phase5.test.mjs` - 14 tests, 0 failures.
- `rtk npm run test:relay` - 41 tests, 0 failures.
- `rtk npm test` - 41 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests` - 51 tests, 0 failures.
- `rtk swift test --filter ComposerVoiceControlsPresentationTests` - 4 tests, 0 failures.
- `rtk swift test` - 183 tests, 5 skipped, 0 failures.
- `rtk xcodegen generate --spec project.yml`
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build`
- `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW`
- `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp`
- `rtk make dock-relay-status` - relay pid `3815`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- `rtk git diff --check`

Remaining proof gap:

- The structural cleanup closes the code-shape finding. The later completion audit above closes the manual iPhone 14 evidence gap for the current installed build.

## 2026-05-28 Physical iPhone 14 Basic Audio Pass And Listening Color Update

Verdict: source-truth update recorded; superseded by the structural implementation-audit pass above for current code-shape review.

Evidence reviewed:

- User manual physical iPhone 14 feedback after the empty-transcript relay fix: `Okay, that worked.` This supersedes the earlier crash and empty-transcript failures for the basic physical Realtime audio path.
- The app was then changed so active listening UI is blue instead of red in `CodexDock/Features/Session/ComposerView.swift`; red remains reserved for actual error labels.
- Focused proof after that UI change: `rtk swift test --filter ComposerVoiceControlsPresentationTests` executed 4 tests with 0 failures, `rtk git diff --check -- CodexDock/Features/Session/ComposerView.swift` passed, and `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` plus `rtk xcrun devicectl device process launch --device 00008110-000E04940240A01E --terminate-existing com.aelaguiz.CodexDockApp` installed/launched the build on the physical iPhone 14.
- Secret hygiene evidence after install: `.env` mtime remained `1779986258`; relay status was healthy at `ws://192.168.50.117:4510` with `phone auth: none`.

Remaining proof gap:

- Superseded by the completion audit above. The detailed manual checklist is marked passed by user manual check for the current installed build.

## 2026-05-28 Phase 5 Implementation Audit

Verdict: pass for cutover cleanup; physical/manual acceptance remains outside this automated audit.

Evidence reviewed:

- Swift one-shot side doors removed: `TranscriptionServicing`, `OpenAITranscriptionClient`, `OpenAITranscriptionConfiguration`, `RelayTranscriptionClient`, `AppServerMethods.audioTranscribe`, `AppServerClient.audioTranscribe(...)`, `AudioTranscribeParams`, `AudioTranscribeResponseDTO`, and `CodexDock/AppServer/AudioTranscriptionDTO.swift`.
- Old m4a production capture removed: `VoiceCaptureControlling`, `VoiceCaptureController`, `VoiceCaptureError.notRecording`, and dead m4a fake capture test helper are gone; production dictation uses `LiveVoiceCaptureControlling`.
- Relay one-shot path removed or rejected: `scripts/dock-relay-transcription.mjs` deleted, old helper imports/exports/config removed from `scripts/dock-relay.mjs`, Makefile no longer writes/passes `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL` or `--openai-transcription-model`, and `scripts/dock-relay.test.mjs` proves raw `audio/transcribe` returns `-32601`.
- Metadata/docs updated: README, AGENTS.md, `project.yml`, generated `CodexDockApp/Info.plist`, iPhone pairing plan/worklog, iPhone UX spec, Multi-host plan, and Phase 8 voice docs now point to relay-owned Realtime dictation or explicitly mark one-shot material as historical.
- Search evidence: runtime/config search for `audioTranscribe`, `AppServerMethods.audioTranscribe`, `AudioTranscribe`, `TranscriptionServicing`, `OpenAITranscriptionClient`, `OpenAITranscriptionConfiguration`, `RelayTranscriptionClient`, `VoiceCaptureControlling`, `VoiceCaptureController(`, `notRecording`, `CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL`, `CODEX_DOCK_TRANSCRIPTION_MAX_BYTES`, `--openai-transcription-model`, `dock-relay-transcription`, `transcribeAudio`, and `decodedAudioTranscribeParams` returned only Realtime names/test negative guards, not deleted runtime side doors.
- Generated project evidence: `rtk xcodegen generate --spec project.yml` regenerated the project and `CodexDockApp/Info.plist`; Xcode build removed stale `AudioTranscriptionDTO` objects.
- Secret/env evidence: `.env` mtime stayed `1779986258`; generated `.codex-dock/service.env` contains Realtime model/delay config and no old one-shot model env.

Verification passed:

- `rtk node --check scripts/dock-relay-realtime-transcription.mjs`
- `rtk node --check scripts/dock-relay.mjs`
- `rtk node --check scripts/dock-relay.test.mjs`
- `rtk swift test --filter AppServerClientTests` - 43 tests, 5 explicit real-host skips, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests` - 49 tests, 0 failures after stale OpenAI error expectations were updated to relay wording.
- `rtk swift test` - 173 tests, 5 explicit real-host skips, 0 failures.
- `rtk npm run test:relay` - 38 tests, 0 failures.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` - passed.
- Name-based simulator build with `name=iPhone 17` failed only because no simulator has that exact name; available matching simulator is `feat_anim_1 - iPhone 17` at `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
- `rtk make dock-relay` restarted the relay with cutover code; `rtk make dock-relay-status` showed pid `88873`, endpoint `ws://192.168.50.117:4510`, `phone auth: none`, readyz OK.
- Real relay-to-OpenAI cutover proof passed through `ws://192.168.50.117:4510`: raw `audio/transcribe` rejected, Realtime session started with `MODEL=gpt-realtime-whisper`, `DELAY=low`, `CHUNKS=3`, `DELTA_COUNT=10`, terminal `audio/transcription/completed`, `COMPLETED_TEXT_BYTES=48`, `COMPLETED_TEXT_SHA256=8e9c23af0bbe80abc5244e2094cb1475a8a28dd05457bc9a116ce2cac037e366`. Transcript text, key, audio, and base64 were not printed.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` built, installed, and launched the simulator app as `com.aelaguiz.CodexDockApp: 87615`.
- `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` built and installed `com.aelaguiz.CodexDockApp` on the physical iPhone 14 target.
- `rtk git diff --check` passed.

Audit notes:

- The first real-relay proof attempt failed because the proof harness split PCM16 into odd-byte chunks. A direct provider probe confirmed the error was invalid PCM chunking, not app/relay code. The proof was rerun with even chunk boundaries and passed.
- Physical Mobile MCP was not retried; this follows the repo instruction and Amir's explicit direction. The current physical iPhone 14 proof is user manual evidence, and future physical checks are deferred manual QA under the parent dock operating rule.

## Resolved Cross-Plan Findings

- [x] CPLA-001 - Realtime needed a hard Connectivity prerequisite gate
  - Lens: depth-first-risk, canonical-owner-and-SSOT
  - Evidence: Section 7 could start relay Realtime work before the `AppConnectivityStore`, root lifecycle owner, and `ThreadDetailStore` reconnect inputs existed.
  - Required plan repair: Add a Phase 0 prerequisite requiring the Connectivity lifecycle/status owner and forbidding a second Realtime-owned lifecycle authority.
  - Status: resolved
  - Resolution evidence: Phase 0 now requires Connectivity outputs before Realtime Phase 1 starts.

- [x] CPLA-002 - `RelayRealtimeTranscriptionClient` could bypass selected host config
  - Lens: security-boundary, caller-invariant-state
  - Evidence: The target path said a separate app-to-relay WebSocket but did not fully require `RelayBootstrapStore`/`HostRegistry` selected `DockHostConfiguration` and nil-bearer behavior.
  - Required plan repair: Require construction from selected `DockHostConfiguration`, `host.webSocketURL`, optional `host.bearerToken`, no direct env reads, no hard-coded `:4510`, and no production dependence on `SIMCTL_CHILD_*`.
  - Status: resolved
  - Resolution evidence: Phase 3 checklist now carries these requirements.

- [x] CPLA-003 - Background handling could become a second scene-phase owner
  - Lens: canonical-owner-and-SSOT, caller-invariant-state
  - Evidence: Realtime phases named app background handling without explicitly routing it through Connectivity-owned lifecycle.
  - Required plan repair: State Realtime does not observe SwiftUI `scenePhase` directly and only implements the voice participant behavior.
  - Status: resolved
  - Resolution evidence: Phase 4 checklist now names the Connectivity-owned lifecycle event path and Realtime voice participant duties.

- [x] CPLA-004 - Current voice path described the direct OpenAI client as primary
  - Lens: code-truth-map, security-boundary
  - Evidence: Section 4.2 listed `OpenAITranscriptionClient.transcribe(audioFile:)` as the current step even though `ThreadDetailStore` defaults to `RelayTranscriptionClient`.
  - Required plan repair: Describe the current default as one-shot relay upload and direct OpenAI upload as a manually constructed side door.
  - Status: resolved
  - Resolution evidence: Section 4.2 now names the default production path and side door separately.

- [x] CPLA-005 - `OPENAI_API_KEY` cleanup wording could remove the relay's Mac-side key source
  - Lens: security-boundary, docs-contract-drift
  - Evidence: Phase 5 intended to remove phone-side exposure, but could be read as deleting the relay's host-side `.env` key source.
  - Required plan repair: Clarify that `OPENAI_API_KEY` remains Mac-side for the relay and only app-process exposure is removed.
  - Status: resolved
  - Resolution evidence: Phase 5 now keeps the Mac-side relay key source while forbidding `SIMCTL_CHILD_OPENAI_API_KEY`, physical app config keys, and Swift default construction.

## Resolved Plan-Readiness Findings

- [x] PLA-001 - Existing one-shot `audio/transcribe` app/relay surfaces were undercounted.
  - Lens: code-truth-map; deletion-and-side-door; existing-pattern-and-convergence.
  - Evidence: `RelayTranscriptionClient`, `AppServerMethods.audioTranscribe`, `AppServerClient.audioTranscribe`, `AudioTranscriptionDTO.swift`, and relay `audio/transcribe` already existed.
  - Required plan repair: Carry those surfaces through current architecture, call-site audit, migration/delete list, and Phase 5.
  - Status: resolved
  - Resolution evidence: Plan Sections 3, 4, 6, and Phase 5 now name these one-shot app/relay surfaces and require deletion or replacement from the production voice path.

- [x] PLA-002 - Relay failed/canceled/closed event contract was not proven before Swift depended on it.
  - Lens: proof-and-phase-exit; drift-proof-coupling.
  - Evidence: Phase 3 consumed `failed`/`closed` events, while Phase 1 only mapped delta/completed.
  - Required plan repair: Make failed, canceled, and closed notifications part of the Phase 1 relay contract and tests.
  - Status: resolved
  - Resolution evidence: Target contract and Phase 1 now require delta, completed, failed, canceled, and closed notifications with sanitized payloads.

- [x] PLA-003 - Manual typed-text preservation proof was stranded outside authoritative Phase 5.
  - Lens: outcome-north-star; proof-and-phase-exit.
  - Evidence: Section 0.4 required typed text survival, but Phase 5 proof did not make it explicit.
  - Required plan repair: Add physical-device proof for typed-prefix preservation and cancel/interruption recoverability.
  - Status: resolved
  - Resolution evidence: Phase 5 verification and exit criteria now require physical proof for typed-prefix survival, cancel/interruption, editable final draft, and explicit Send.

- [x] PLA-004 - Old relay transcription config/helper/test surfaces were undercounted.
  - Lens: deletion-and-side-door; security-boundary; docs-contract-drift.
  - Evidence: `DEFAULT_TRANSCRIPTION_MODEL`, `DEFAULT_TRANSCRIPTION_ENDPOINT`, old `CODEX_DOCK_OPENAI_TRANSCRIPTION_*` env names, `CODEX_DOCK_TRANSCRIPTION_MAX_BYTES`, old timeout env, `--openai-transcription-model`, `transcribeAudio`, `decodedAudioTranscribeParams`, helper exports, and one-shot tests keep the old file-upload path discoverable.
  - Required plan repair: Add explicit relay cleanup work for those surfaces.
  - Status: resolved
  - Resolution evidence: Section 6 and Phase 5 now require deleting or replacing those one-shot relay config/helper/test surfaces with Realtime-specific equivalents.

- [x] PLA-005 - Raw JSON-RPC method-string transport could bypass typed transcription cleanup.
  - Lens: canonical-owner-and-SSOT; deletion-and-side-door; caller-invariant-state.
  - Evidence: `AppServerClient.sendRequest(method:)` and `sendNotification(method:)` are public raw JSON-RPC transport primitives.
  - Required plan repair: Decide the raw transport boundary and require proof that old/malformed transcription strings cannot remain a production voice path.
  - Status: resolved
  - Resolution evidence: Section 5 invariants, Section 6 call-site audit, Phase 3, and Phase 5 now state that raw JSON-RPC remains a transport primitive only, production voice uses typed transcription APIs, and raw `audio/transcribe` is rejected after cutover.

- [x] PLA-006 - Relay error sanitization missed downstream JSON-RPC error responses.
  - Lens: security-boundary; drift-proof-coupling.
  - Evidence: current relay sends `error.message` downstream in JSON-RPC error responses, and Swift preserves server error messages.
  - Required plan repair: Add app-visible error sanitization, not just log redaction.
  - Status: resolved
  - Resolution evidence: Section 5.4 and Phase 1 now require allowlisted error categories for Realtime JSON-RPC responses and failed notifications, with downstream WebSocket frame tests.

- [x] PLA-007 - Delta text semantics were undecided.
  - Lens: caller-invariant-state; ambiguity-and-miscommunication.
  - Evidence: the plan used "delta" while store behavior required replacing with full partial text.
  - Required plan repair: Define whether app events carry incremental delta or cumulative partial.
  - Status: resolved
  - Resolution evidence: Section 5, Phase 1, Phase 2, Phase 3, and the decision log now define `deltaText` as incremental and `partialText` as cumulative; `ThreadDetailStore` uses `partialText`.

- [x] PLA-008 - Editing during active dictation had no product rule.
  - Lens: caller-invariant-state; proof-and-phase-exit.
  - Evidence: current `ComposerView` binds a normal editable text field to `store.composer.draft`, while streaming updates would also mutate the draft.
  - Required plan repair: Decide whether editing is allowed while streaming/finalizing and carry the rule into tests.
  - Status: resolved
  - Resolution evidence: Section 5 and Phase 2/4 now lock user edits while dictation is active and require tests that `updateDraft` cannot mutate the draft during active dictation.

- [x] PLA-009 - Transcription WebSocket owner was ambiguous.
  - Lens: canonical-owner-and-SSOT; drift-proof-coupling.
  - Evidence: existing thread detail session and current one-shot relay client use different connection ownership shapes.
  - Required plan repair: Choose shared thread-detail connection or separate voice connection.
  - Status: resolved
  - Resolution evidence: Section 5, Phase 3, and the decision log now choose a separate app-to-relay WebSocket owned by `RelayRealtimeTranscriptionClient`.

- [x] PLA-010 - Stop-reason semantics were underdefined.
  - Lens: caller-invariant-state; proof-and-phase-exit.
  - Evidence: explicit cancel, view disappear, app background, route interruption, upstream failure, downstream close, commit timeout, and deinit have different UX implications.
  - Required plan repair: Add a stop-reason policy and tests.
  - Status: resolved
  - Resolution evidence: Section 5.2 now defines stop/error behavior; Phase 2 carries each stop reason into store tests.

- [x] PLA-011 - Tap-to-start/tap-to-stop lacked a testable owner.
  - Lens: caller-invariant-state; accessibility; proof-and-phase-exit.
  - Evidence: current `ComposerView` has an empty button action plus hold-only drag gesture.
  - Required plan repair: Name the owner and add idempotence/cleanup proof.
  - Status: resolved
  - Resolution evidence: Phase 4 now says `ThreadDetailStore` owns tap-mode lifecycle/state and requires tests for tap start/stop, repeated taps, finalizing, Send gating, close/disappear cleanup, and hold/tap interaction.

- [x] PLA-012 - Live docs and app metadata cleanup was too narrow.
  - Lens: docs-contract-drift; deletion-and-side-door.
  - Evidence: stale voice instructions exist in the iPhone pairing plan, iPhone UX spec, multi-host service setup plan, Phase 8 plan/worklog, `project.yml`, and `Info.plist`.
  - Required plan repair: Expand the required docs/metadata cleanup list.
  - Status: resolved
  - Resolution evidence: Section 0, Section 5, Section 6, and Phase 5 now name README, iPhone pairing, iPhone UX spec, multi-host service setup plan, Phase 8 plan/worklog, `project.yml`, and `CodexDockApp/Info.plist`.

- [x] PLA-013 - Current default-owner description was stale.
  - Lens: code-truth-map.
  - Evidence: `ThreadDetailStore` now defaults to one-shot `RelayTranscriptionClient`, while direct `OpenAITranscriptionClient` remains compiled.
  - Required plan repair: Describe the current state as one-shot relay upload plus direct OpenAI side door.
  - Status: resolved
  - Resolution evidence: Section 2 and Section 3 now state the current default is one-shot relay upload and direct OpenAI remains a side door.

## Current Implementation Findings

- Realtime Phase 1 relay code is preflight-complete but not accepted from mocks.
- Fake-upstream/mock relay tests are useful code checks but do not count as real proof.
- Realtime Phase 2 Swift store/composer code is preflight-complete but not accepted from fake streaming sessions.
- Realtime Phase 3 typed Swift relay-client code is preflight-complete but not accepted from scripted relay notifications.
- Realtime Phase 4 live PCM capture/audio-forwarding/tap-control code is preflight-complete but not accepted from fake capture chunks or scripted relay responses.
- Phase 2 correctly removed the hidden automatic store fallback to one-shot `audio/transcribe`; Phase 3 now wires default store voice construction to the typed relay-backed streaming client; Phase 4 now wires live capture chunks into `RealtimeTranscriptionSession.appendAudio(...)`, keeps hold dictation mode-scoped, adds tap-to-start/tap-to-stop dictation, and adds route/interruption cleanup. Real relay/OpenAI proof, basic physical iPhone 14 Realtime audio proof, and detailed manual physical checklist proof have passed for the current installed build.
- Phase 2 fake-session tests are useful state-machine checks but do not count as real phone/relay/audio proof.
- Phase 3 scripted relay-notification tests are useful client/store integration checks but do not count as real phone/relay/audio proof.
- Phase 4 fake capture chunk tests are useful app-code checks because they prove the store now calls `appendAudio(...)`, but they still do not count as real microphone/relay/OpenAI proof.
- Phase 4 current preflight checks passed: `rtk swift test --filter ComposerVoiceControlsPresentationTests` executed 4 tests with 0 failures; `rtk swift test --filter ThreadDetailStoreTests` executed 49 tests with 0 failures; `rtk swift test` executed 175 tests with 5 skipped and 0 failures; `rtk npm test` executed 42 tests with 0 failures; `rtk xcodegen generate --spec project.yml` passed; Xcode simulator build passed on `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`; `rtk git diff --check` passed; physical `iPhone 14` install/launch passed with process `4434`.
- Earlier Phase 4 fallback app proof was real relay-backed but not successful dictation acceptance: Mobile MCP on simulator `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` showed `ws://192.168.50.117:4510 · 206 sessions`, opened a real thread detail view, showed `Hold to dictate` and `Start dictation`, and tapping `Start dictation` surfaced `App-server rejected request: OpenAI Realtime transcription key is not configured on the relay`.
- Required acceptance proof at that checkpoint: real relay-to-OpenAI Realtime path with Mac-side `OPENAI_API_KEY`, representative PCM streamed through the relay contract, real OpenAI transcription events, redacted evidence, and physical `iPhone 14` client proof or an explicit accepted blocker/fallback. Later sections above record that proof as passed for the current installed build.
- Prior read-only implementation audit findings for pending queue enforcement, malformed upstream event handling, and `OpenAI-Safety-Identifier` provider-control proof were repaired in `scripts/dock-relay-realtime-transcription.mjs` and `scripts/dock-relay-realtime-transcription.test.mjs`; the full relay preflight suite now passes 41 tests with 0 failures.
- Prior strict review findings for plaintext `ws://` OpenAI key risk, relay shutdown cleanup, Realtime transcription URL mismatch, and missing cleanup-path tests were repaired; production endpoint validation now requires `wss:`, tests use an injected WebSocket factory, shutdown closes active downstream sockets, and the upstream URL is forced to `intent=transcription` with no `model` query.
- Real relay-to-OpenAI proof passed after the user restored `.env` and service env generation was changed to write only `.codex-dock/service.env`: local JSON-RPC client -> `ws://192.168.50.117:4510` relay -> OpenAI Realtime transcription. Redacted evidence: `PCM_BYTES=123920`, `MODEL=gpt-realtime-whisper`, `APPEND_OK=1`, `CHUNKS=3`, `COMMIT_OK=1`, `DELTA_COUNT=9`, `TERMINAL_METHOD=audio/transcription/completed`, `COMPLETED_TEXT_BYTES=47`, `COMPLETED_TEXT_SHA256=a49fef874c839fee25b98c117f0f266d2ae983fdcf0de808e974564019d655ee`, and `CLOSED_SEEN=1`.
- `.env` preservation is now enforced in `Makefile`: `rtk make env-file` writes `.codex-dock/service.env`, refuses `ENV_FILE=.env`, reads `.env` only as input for values such as `OPENAI_API_KEY`, and preserved `.env` mtime `1779986258` during verification.
- The approved non-Pro simulator app-side smoke exposed and then verified a real crash fix: before the fix, tapping `Start dictation` produced `SIGTRAP` after `AVAudioEngine` startup; after the fix, `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` launched pid `37271`, Mobile MCP tapped `Start dictation`, and the app stayed open with visible error `Voice recording could not start.` This is fail-visible simulator proof only, not successful voice acceptance.
- Physical iPhone 14 install/launch after the crash fix passed: `rtk make device-install DEVICE=00008110-000E04940240A01E DEVELOPMENT_TEAM=R6B8KXF3QW` installed the app, `devicectl ... process launch` launched it, process listing showed pid `4473`, and `.env` mtime stayed unchanged. Physical UI readback is still blocked by WebDriverAgent.
- Physical UI-readback blocker at that checkpoint: Mobile MCP could see physical iPhone 14 `00008110-000E04940240A01E`, but screenshot and element listing failed because WebDriverAgent was not running. Physical install/launch passed, and the user-approved non-Pro simulator fallback rendered real relay-backed Dock rows and thread detail controls. Current fallback screenshots: `/tmp/codex-client/20260528T161315Z/realtime-phase4-smoke/001_dock_connected_fallback.png`, `/tmp/codex-client/20260528T163230Z/realtime-phase4-tap-controls-fallback.png`, and `/tmp/codex-client/20260528T163230Z/realtime-phase4-missing-key-fallback.png`. Per the parent dock operating rule, missing physical UI-readback is not a current stop condition.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/State/ThreadDetailStore.swift`, `ComposerState`, `ComposerVoiceState`, `beginVoiceCapture`, `finishVoiceCapture`, `cancelVoiceCapture`, `sendDraft`, `close` | Composer draft, voice lifecycle, Send gating, stop behavior | Codex, Tesla | read |
| Composer UI caller | `CodexDock/Features/Session/ComposerView.swift`, `CodexDock/Features/Session/SessionDetailView.swift` | Hold gesture, tap mode owner, text-field edit lock, close on disappear | Codex, Tesla | read |
| Voice capture/service | `CodexDock/Voice/VoiceCaptureController.swift`, `CodexDock/Voice/TranscriptionService.swift` | Current m4a capture, one-shot protocol, relay upload side door, direct OpenAI side door | Codex, Tesla | read |
| App-server transport/contracts | `CodexDock/AppServer/AppServerClient.swift`, `CodexDock/AppServer/AppServerMethods.swift`, `CodexDock/AppServer/AudioTranscriptionDTO.swift` | Raw JSON-RPC side door, old one-shot method/DTOs, typed transport shape | Codex, Hooke | read |
| Relay implementation | `scripts/dock-relay.mjs` | One-shot handler/helper/config, future Realtime owner, logging/error response behavior | Codex, Hooke | read |
| Relay tests/package | `scripts/dock-relay.test.mjs`, `package.json` | Existing one-shot tests and correct relay test command | Codex, Hooke | read |
| Build/config | `Makefile`, `project.yml`, `CodexDockApp/Info.plist` | OpenAI env/config routing, LaunchAgent args, OS permission copy | Codex, Hooke | read |
| Existing Swift tests | `CodexDockTests/ThreadDetailStoreTests.swift`, `CodexDockTests/AppServerClientTests.swift` | Existing proof surface and fake seams | Codex, Tesla, Hooke | read |
| Live docs | `README.md`, `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`, `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`, `docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md`, Phase 8 plan/worklog/audit/review docs | Stale voice, key, one-shot relay, and accessibility instructions | Codex, Hooke, Gauss | read |
| Official OpenAI API grounding | Realtime, Realtime transcription, WebSocket, WebRTC, speech-to-text, model, costs docs | API correctness and model/transport choice | Codex | read |

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses: docs-contract-drift and security-boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Do relay delta events carry incremental or cumulative text? | Incremental delta only; cumulative partial text | Draft replacement could drop or duplicate words | Relay emits both `deltaText` and cumulative `partialText`; store uses `partialText` | Codex from repo/API evidence | Section 5.2, 5.3, Phase 1-3, Decision Log | resolved |
| DEC-002 | Can the user edit the composer while dictation is active? | Allow concurrent edits; lock edits until completion | Concurrent mutation can corrupt the active segment | Lock user edits while voice is starting/streaming/finalizing | Codex from UI/state evidence | Section 5.2, Phase 2, Phase 4, Decision Log | resolved |
| DEC-003 | Who owns the transcription WebSocket? | Shared thread-detail connection; separate voice connection | Notification routing and cleanup differ | `RelayRealtimeTranscriptionClient` owns a separate relay WebSocket | Codex from existing one-shot client pattern | Section 5.2, Phase 3, Decision Log | resolved |
| DEC-004 | What happens to partial text for each stop reason? | Remove partial; freeze partial; finalize partial | Cancel/failure/interruption UX differs | Stop-reason policy in Section 5.2 | Codex from UX constraints | Section 5.2, Phase 2, Phase 5, Decision Log | resolved |
| DEC-005 | How are raw JSON-RPC method-string side doors handled? | Delete raw transport; keep transport but reject old voice methods | App-server transport still needs generic primitives | Keep transport primitive; production voice uses typed API; relay rejects old/malformed transcription strings | Codex from transport tests/code | Section 0.5, Section 6, Phase 3, Phase 5, Decision Log | resolved |

## Pass History

### Pass 1 - 2026-05-28T11:08:00Z

- Mode: plan-readiness
- Scope: whole plan after ArcStep consistency gate reported ready
- Baseline reviewed: `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`
- Test/CI context accepted, if supplied: none
- Agents/lenses run: Newton/Kant consistency readers, then Hooke/Tesla/Gauss plan-audit lenses plus parent synthesis
- Code areas read: voice capture/service, composer store/UI, app-server transport/contracts, relay implementation/tests, Makefile/config, README/live docs
- Findings added: PLA-001 through PLA-013
- Findings resolved: none during initial lens read
- Findings carried forward: PLA-001 through PLA-013
- Verdict: not-ready
- Next audit focus: verify plan repairs for side-door closure, event DTO semantics, stop reasons, active edit policy, connection ownership, and docs/metadata cleanup

### Pass 2 - 2026-05-28T11:17:19Z

- Mode: plan-readiness
- Scope: whole plan after repair
- Baseline reviewed: `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`
- Test/CI context accepted, if supplied: none
- Agents/lenses run: parent synthesis over prior child findings; no new child reports needed because repairs were direct carry-through changes from Pass 1 findings
- Code areas read: same coverage as Pass 1, with spot-checks on relay/app/client/docs anchors
- Findings added: none
- Findings resolved: PLA-001 through PLA-013
- Findings carried forward: none
- Verdict: ready
- Next audit focus: after implementation, run implementation-audit against the completed code, especially relay error sanitization, old side-door deletion, stop-reason tests, and physical no-secret proof.

### Pass 3 - 2026-05-28T12:01:57Z

- Mode: cross-plan plan-readiness
- Scope: Realtime alignment with top-level Phase 3 ordering and no-phone-secret relay baseline
- Baseline reviewed: Realtime plan after cross-plan prerequisite/security/lifecycle repairs
- Test/CI context accepted, if supplied: none; docs-only audit pass
- Agents/lenses run: Boyle audited Realtime independently; parent synthesis ran all required plan-audit lenses plus docs-contract-drift and security-boundary
- Code areas read: `ThreadDetailStore.swift`, `TranscriptionService.swift`, `AppServerMethods.swift`, `AppServerClient.swift`, `AudioTranscriptionDTO.swift`, `RelayBootstrapStore.swift`, `RelayDiscovery.swift`, `DockHostConfiguration.swift`, `scripts/dock-relay.mjs`, `scripts/dock-relay-transcription.mjs`, `Makefile`, README voice/key anchors, top-level plan, and Connectivity plan anchors
- Findings added: CPLA-001 through CPLA-005
- Findings resolved: CPLA-001 through CPLA-005
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after Realtime code changes, especially selected-host construction, no phone OpenAI key, Connectivity lifecycle participation, and one-shot side-door deletion
