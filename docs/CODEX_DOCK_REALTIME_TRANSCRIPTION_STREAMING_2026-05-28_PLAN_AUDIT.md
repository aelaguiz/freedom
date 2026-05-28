# Plan Audit Log

Plan: `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28.md`
Audit log: `docs/CODEX_DOCK_REALTIME_TRANSCRIPTION_STREAMING_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: not-run
Last reviewed: 2026-05-28T12:01:57Z
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

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

Not run. This audit is pre-implementation plan-readiness only.

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
