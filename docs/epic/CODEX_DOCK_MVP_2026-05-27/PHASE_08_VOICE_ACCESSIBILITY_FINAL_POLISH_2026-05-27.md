---
title: "Codex Dock - Voice Accessibility Final Polish - Architecture Plan"
date: 2026-05-27
status: complete
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: new_system
related:
  - ../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - ../../mockups/codex-dock-2026-05-27-v2/04-session-dictation-inline.png
  - ../../mockups/codex-dock-2026-05-27-v2/07-dock-rotation-feedback.png
---

# TL;DR

- Outcome: Finish V1 with in-place push-to-talk transcription, accessibility,
  visual polish, and final acceptance.
- Problem: The app becomes operational before this phase, but road-use voice and
  final quality still matter for MVP.
- Approach: Reuse the existing composer, add voice capture/transcription into
  the text box, then run final UI/accessibility acceptance.
- Plan: Add fake-service composer state first, then real recording/transcription,
  then final screen polish.
- Non-negotiables: no auto-submit, no separate voice screen, no AIMGR.

<!-- arch_skill:block:implementation_audit:start -->
# Implementation Audit (authoritative)
Date: 2026-05-28
Verdict (code): COMPLETE
Manual QA: complete (non-blocking)

## Code blockers (why code is not done)
- None.

## Reopened phases (false-complete fixes)
- None.

## Missing items (code gaps; evidence-anchored; no tables)
- None.

## Non-blocking follow-ups (manual QA / screenshots / human verification)
- Historical thread detail currently loads one bounded `thread/turns/list`
  page before live updates. Older-history pagination is a post-MVP expansion if
  needed.
- `CodexDockTests/AppServerClientTests.swift` remains a large protocol test
  file. It was already above 1k lines before Phase 8, but should split by
  method family if the protocol surface expands again.
<!-- arch_skill:block:implementation_audit:end -->

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-27
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-27
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:2f629a685b785788fa4180e11c4eaa08f08b290377516b34da1930bac13982cb",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T00:24:37Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:5f433ed43d2aa02e28cc69153f4efd5ab94f6dd1f95e2e3a97b99ad034c71b9d",
      "completed_at": "2026-05-28T00:25:39Z",
      "doc_hash_after": "sha256:c2389c5eac96c67324319ac52a3de0a4fe57cbe2280308de6cf37858855721a6"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:25:45Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:c2389c5eac96c67324319ac52a3de0a4fe57cbe2280308de6cf37858855721a6",
      "completed_at": "2026-05-28T00:27:30Z",
      "doc_hash_after": "sha256:61c7b7aaeabea86102d56daade1631849f5096603ce20a5a2d743efdddb3fe01"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T00:27:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:61c7b7aaeabea86102d56daade1631849f5096603ce20a5a2d743efdddb3fe01",
      "completed_at": "2026-05-28T00:30:32Z",
      "doc_hash_after": "sha256:549e945cecaf0e9e9a70633e5bc3a23f691ca3b619096f19898ba2a771b62315"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T00:30:35Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:549e945cecaf0e9e9a70633e5bc3a23f691ca3b619096f19898ba2a771b62315",
      "completed_at": "2026-05-28T00:31:30Z",
      "doc_hash_after": "sha256:de4da0d4684e2baa6b7f159cfb4bc95c6c756e7fbe02681628220bc0301e3757"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T00:31:33Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:de4da0d4684e2baa6b7f159cfb4bc95c6c756e7fbe02681628220bc0301e3757",
      "completed_at": "2026-05-28T00:32:11Z",
      "doc_hash_after": "sha256:39b2e23c25b36d9e758f05056e63b2f5a32c9d2bb937a0ed65391a45e4cb8a8e"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

The user can hold the mic in the existing composer, release to transcribe into
the text box, edit the transcript, manually tap Send, and use the final MVP
screens without obvious accessibility/layout breakage.

## 0.2 In scope

- In-place push-to-talk.
- OpenAI transcription boundary.
- Editable transcript inserted into composer.
- Accessibility and Dynamic Type pass.
- Final V1 acceptance audit.

## 0.3 Out of scope

- Realtime voice conversation.
- Voice auto-submit.
- Separate blue recording screen.
- AIMGR/Rotate implementation.

## 0.4 Definition of done (acceptance evidence)

- Transcript insertion does not send automatically.
- Real or fake transcription path is verified.
- Main screens pass visual/accessibility review.
- V1 acceptance checklist has evidence.

## 0.5 Key invariants (fix immediately if violated)

- Voice writes into the existing composer.
- Send remains explicit.
- The `.env` OpenAI API key is Mac-side only. The iPhone client must not receive
  it; voice uses the relay-owned Realtime transcription path.
- Rotation mockup stays post-V1 only.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Preserve composer semantics.
2. Safe voice failure handling.
3. Accessibility and no overlap.
4. Final acceptance evidence.

## 1.2 Constraints

- OpenAI Realtime API details should be verified at implementation time.
- `.env` may contain the Mac-side OpenAI API key for the relay. Do not pass it
  into the app, and do not print the key value, raw audio, base64 audio,
  transcripts, provider response bodies, logs, telemetry, screenshots, or
  errors.

## 1.3 Architectural principles (rules we will enforce)

- Voice service boundary is narrow.
- UI uses state from the existing detail store.
- Mockups guide, not golden-test.

## 1.4 Known tradeoffs (explicit)

- Manual visual QA is acceptable.
- Provider integration can be hidden if unavailable, but no fake success.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Earlier phases provide core app operation, text control, multi-host scan,
archive, and Hosts.

## 2.2 What’s broken / missing (concrete)

The road-use dictation flow and final polish are not yet complete.

## 2.3 Constraints implied by the problem

Voice must deepen the existing composer path.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal “ground truth”)

## External anchors (papers, systems, prior art)
- iOS microphone/audio-session conventions — use platform permission and
  capture behavior.
- OpenAI speech transcription API — use OpenAI transcription behind a narrow
  service boundary; verify exact current API during implementation.

## Internal ground truth (code as spec)
- Authoritative behavior anchors:
  - `../../CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` — voice is in-place,
    hold/release, transcript into text box, manual Send.
  - `../../mockups/codex-dock-2026-05-27-v2/04-session-dictation-inline.png` —
    inline dictation visual anchor.
  - `../../mockups/codex-dock-2026-05-27-v2/07-dock-rotation-feedback.png` —
    post-V1 exploration only.
- Canonical path / owner to reuse:
  - Phase 5 composer state; new transcription service writes text into it.
- Adjacent surfaces tied to the same contract family:
  - Typed composer and voice composer share Send semantics.
  - Final polish touches Dock, Needs-me, Session, Archive, and Hosts screens.
- Compatibility posture:
  - Preserve typed send behavior; voice adds text entry only.
- Existing patterns to reuse:
  - Phase 5 composer state and error handling.
- Prompt surfaces / agent contract to reuse:
  - Voice text becomes normal user-authored Codex input.
- Native model or agent capabilities to lean on:
  - OpenAI transcription; no custom speech model.
- Existing grounding / tool / file exposure:
  - `.env` contains the client OpenAI API key. The user has said this key is
    safe to embed in the client, but implementation must not print the key value
    or log transcripts.
- Duplicate or drifting paths relevant to this change:
  - Avoid standalone blue voice screen and separate voice send path.
- Capability-first opportunities before new tooling:
  - Platform audio capture plus OpenAI transcription before custom audio logic.
- Behavior-preservation signals already available:
  - Phase 5 composer send checks remain green.

## Decision gaps that must be resolved before implementation
- none
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)
## On-disk structure
- Core MVP surfaces exist by Phase 7; voice and final QA do not.
## Control paths (runtime)
- Composer sends typed text; no voice capture/transcription path.
## Object model + key abstractions
- `ComposerState` exists; no voice/transcription service.
## Observability + failure behavior today
- Typed send errors exist; microphone/transcription errors absent.
## UI surfaces (ASCII mockups, if UI work)
- Inline dictation and final screen mockups anchor polish.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)
## On-disk structure (future)
- `Voice/VoiceCaptureController.swift`.
- `Voice/TranscriptionService.swift`.
- `RelayRealtimeTranscriptionClient` and Realtime abstractions inside `Voice/`.
- `Features/Session/ComposerView.swift` extension.
- `CodexDockTests/ThreadDetailStoreTests.swift` voice coverage.
## Control paths (future)
1. Hold mic records.
2. Release transcribes.
3. Transcript inserts into existing composer.
4. User edits and taps Send manually.
## Object model + abstractions (future)
- `VoiceCaptureState`, `TranscriptionService`, composer voice extension.
## Invariants and boundaries
- No auto-submit, no separate voice screen, no AIMGR.
## UI surfaces (ASCII mockups, if UI work)
- Anchor: [Inline dictation](../../mockups/codex-dock-2026-05-27-v2/04-session-dictation-inline.png).
- Explicit post-V1 exclusion: [Dock rotation feedback](../../mockups/codex-dock-2026-05-27-v2/07-dock-rotation-feedback.png).
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)
## Change map (table)
| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Voice | `TranscriptionService.swift` | service | Missing | Add speech-to-text boundary | Provider isolation | async transcribe | Unit |
| Voice | `VoiceCaptureController.swift` | capture | Missing | Add hold/release recording | UX requirement | capture API | Manual/unit |
| Provider | `RelayRealtimeTranscriptionClient` | OpenAI Realtime through Mac relay | Implemented | Keep relay-owned Realtime transcription | Required voice mode without phone secrets | provider | Integration/manual |
| Composer | `ComposerView.swift` / store | voice state | Typed only | Insert transcript into text field | In-place voice | composer state | Unit |
| Polish | UI views | accessibility | Basic | Dynamic Type/touch/labels pass | MVP quality | UI | Manual |
## Migration notes
* Canonical owner path / shared code path: existing composer state.
* Deprecated APIs (if any): none.
* Delete list: any standalone voice screen if introduced.
* Adjacent surfaces tied to the same contract family: typed send path.
* Compatibility posture / cutover plan: preserve typed send behavior.
* Capability-replacing harnesses to delete or justify: no custom speech model.
* Live docs/comments/instructions to update or delete: local API key setup if needed.
* Behavior-preservation signals for refactors: Phase 5 composer tests.
## Pattern Consolidation Sweep (anti-blinders; scoped by plan)
| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Composer | existing store | one send path | Prevent voice auto-submit | include |
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:deep_dive_pass_2:start -->
# Deep-Dive Pass 2 Hardening

- Scope lock: voice is in-place hold/release transcription into the existing
  composer; no blue screen, auto-submit, or AIMGR Rotate implementation.
- Adjacent-surface check: transcription writes into Phase 5 composer state and
  must preserve the same explicit Send semantics.
- Secret posture: `.env` contains a user-declared client OpenAI API key that is
  safe to embed in the iPhone client, but the key value and transcripts must not
  be printed in docs, logs, telemetry, screenshots, or errors.
- Depth-first proof: fake transcription state can prove composer behavior before
  real recording and OpenAI transcription are wired.
<!-- arch_skill:block:deep_dive_pass_2:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan

## Implementation slice 1: fake transcription into composer

Status: COMPLETE

Work: Prove voice UI state against the existing composer before touching audio
or provider integration.

Checklist (must all be done):
- Holding the mic enters recording/transcribing UI state in the existing detail
  composer.
- Releasing inserts fake transcript text into the composer draft.
- Draft remains editable.
- Send remains manual.
- Visuals follow [Inline dictation](../../mockups/codex-dock-2026-05-27-v2/04-session-dictation-inline.png).

Exit criteria (all required):
- Test or manual proof shows transcript insertion never auto-submits.

Completed work:
- Added composer voice state and injectable fake voice/transcription services
  in `ThreadDetailStoreTests`.
- Verified transcript insertion and draft appending without auto-submit.

## Implementation slice 2: real hold/release recording and OpenAI transcription

Status: COMPLETE

Work: Add microphone capture and provider transcription behind a narrow service
boundary.

Checklist (must all be done):
- Microphone permission and recording errors surface in composer state.
- Release triggers transcription and inserts text on success.
- OpenAI transcription uses the client-scoped `.env` API key the user declared
  safe to embed in the iPhone client.
- Key value, raw audio paths, and transcripts are not printed in docs, logs,
  telemetry, screenshots, or errors.

Exit criteria (all required):
- A real or provider-stubbed transcription path inserts text without sending.
- Typed composer behavior from Phase 5 remains unchanged.

Completed work:
- Added iOS microphone capture through `VoiceCaptureController`.
- Historical note: the earlier direct `OpenAITranscriptionClient` path has been superseded by relay-owned Realtime transcription.
- Added app launch and `.env` model/key wiring without printing key values.
- Verified voice denial and provider-stubbed transcript insertion paths.

## Implementation slice 3: accessibility, visual polish, and final acceptance

Status: COMPLETE

Work: Run final quality passes over Dock, Needs-me, Session, Archive, and Hosts.

Checklist (must all be done):
- Important controls have accessibility labels and reachable hit targets.
- Dynamic Type does not create obvious overlap in main screens.
- Empty/error/loading states are coherent across screens.
- V1 excludes AIMGR/Rotate; [Dock rotation feedback](../../mockups/codex-dock-2026-05-27-v2/07-dock-rotation-feedback.png)
  remains post-V1 exploratory only.

Exit criteria (all required):
- Final manual acceptance covers all v2 mockup-backed screens.
- No separate voice screen, auto-submit path, or AIMGR integration exists.

Completed work:
- Hardened Dock, Archive, Hosts, and composer controls for hit targets,
  accessibility labels, and Dynamic Type layout.
- Corrected Dock live filtering so Running includes real loaded live sessions.
- Corrected thread detail for large real live threads using compact read,
  paged turns, and `thread/resume excludeTurns:true`.
- Verified final V1 exclusions by implementation-code search.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

<!-- arch_skill:block:consistency_pass:start -->
# Consistency Pass

## Decision inventory
- Decision-complete:
  - yes
- Unresolved decisions:
  - none
- Decision: proceed to implement? yes

## Verification strategy
- Run composer voice tests proving transcript insertion does not submit.
- Run microphone/transcription service tests with fake provider and, when
  available, a real OpenAI transcription path.
- Manual/screenshot check against [Inline dictation](../../mockups/codex-dock-2026-05-27-v2/04-session-dictation-inline.png).
- Run final manual acceptance over Dock, Needs-me, Session, Archive, and Hosts
  screens.
- Verify the `.env` client OpenAI API key value and transcripts are not printed
  in logs, errors, telemetry, docs, or screenshots.

## Cold-read consistency checks
- Voice is hold/release in the existing thread composer, not a separate screen.
- Send remains explicit after transcription.
- [Dock rotation feedback](../../mockups/codex-dock-2026-05-27-v2/07-dock-rotation-feedback.png)
  remains a post-V1 exclusion, not implementation scope.
<!-- arch_skill:block:consistency_pass:end -->

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

Final local-device MVP pass.

## 9.2 Telemetry changes

No analytics.

## 9.3 Operational runbook

Verify voice, accessibility, and final acceptance on simulator/device.

# 10) Decision Log (append-only)

## 2026-05-27 - Voice stays in composer

Context
: User clarified push-to-talk is hold/release in the thread composer, no blue
  screen, and no auto-submit.

Options
: Add a separate voice screen, or deepen the composer.

Decision
: Voice deepens the composer.

Consequences
: This phase must not create a separate submit path.

## 2026-05-28 - Use compact real thread detail for large live rows

Context
: Real iPhone detail verification on `Amir-M5` exposed `Message too long` when
  a large active thread returned full turns in one WebSocket response.

Options
: Increase client/transport message size, invent relay chunking, or use Codex's
  supported paged history and compact resume APIs.

Decision
: Use `thread/read includeTurns:false`, `thread/turns/list limit:10`, and
  `thread/resume excludeTurns:true`.

Consequences
: Detail remains real and live without a custom payload protocol. Older-history
  pagination is a post-MVP expansion if needed.

## 2026-05-28 - Running means loaded live sessions

Context
: Real relay data contained many loaded `idle` Codex sessions and one
  `active` session, while stored `notLoaded` rows could make All look stale and
  Running empty.

Options
: Keep Running as only actively streaming turns, fake Needs-me rows from
  process presence, or align Running to the Dock user's need: loaded live
  sessions.

Decision
: Running includes `needsMe`, `running`, `idle`, and `failed` rows. Needs-me
  stays strict and only uses real app-server attention flags or replayed
  pending requests.

Consequences
: The Dock now shows real loaded Codex sessions without inventing attention
  status.
