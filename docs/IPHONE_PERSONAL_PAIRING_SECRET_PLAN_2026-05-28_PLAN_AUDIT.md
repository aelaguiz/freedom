# Plan Audit Log

Plan: `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`
Audit log: `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve-with-notes
Last reviewed: 2026-05-28
Scope: whole plan

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

No blocking implementation findings remain in the code-reviewed scope.

Implementation note:

- IMP-NOTE-001 - Physical home-screen proof remains pending on local Xcode signing/provisioning, not on a current code-review blocker.
  - Lens: proof and phase exit
  - Scope: Phase 4 manual acceptance
  - Plan expects: physical install, home-screen launch, discovery, relaunch/reboot persistence, and relay voice transcription proof before the change is truly complete.
  - Code reality: `device-install` reaches signing/install, Mac services start, and generated-project builds pass; local Xcode account/provisioning for team `Q2V42N8S7R` and bundle id `com.aelaguiz.CodexDockApp` still blocks installation.
  - Required implementation repair: none known in repo code; complete the manual proof after Xcode account/provisioning is fixed.
  - Status: open

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| App bootstrap and host config | `CodexDockApp/CodexDockApp.swift`; `CodexDock/Configuration/DockHostConfiguration.swift`; `CodexDock/Configuration/HostRegistry.swift`; `CodexDock/Features/Dock/DockView.swift`; `CodexDock/State/HostSettingsStore.swift`; `CodexDock/Features/Hosts/HostsView.swift`; `CodexDock/AppServer/AppServerClient.swift` | Confirms app startup is environment-only today, Hosts edits are in-memory, first-run setup is blocked when config is missing, and the low-level WebSocket transport already supports omitting bearer auth | Parallel app/config reader plus parent spot-check | read |
| Build/install/run commands | `Makefile`; `README.md`; `project.yml`; `CodexDockApp/Info.plist`; `Package.swift`; `scripts/sim.py`; `package.json`; generated `.codex-dock/*.plist` where present | Confirms current app target is simulator-only, uses `SIMCTL_CHILD_*`, lacks physical-device install docs, and currently reuses the raw app-server token as relay client auth | Parallel build reader plus parent spot-check | read |
| Voice/OpenAI path | `CodexDock/Voice/TranscriptionService.swift`; `CodexDock/Voice/VoiceCaptureController.swift`; `CodexDock/State/ThreadDetailStore.swift`; `CodexDock/Features/Session/ComposerView.swift`; `CodexDock/Features/Session/SessionDetailView.swift`; `CodexDock/Features/Session/RequestCardView.swift` | Confirms voice capture works but OpenAI key/model are process-environment-derived and value-captured at client init | Parallel voice reader plus parent spot-check | read |
| Relay/security boundary | `scripts/dock-relay.mjs`; `scripts/dock-relay.test.mjs`; `CodexDock/AppServer/AppServerClient.swift`; `CodexDock/AppServer/AppServerMethods.swift`; `CodexDock/AppServer/JSONRPC.swift`; `CodexDock/State/DockStore.swift`; `CodexDock/State/ArchiveStore.swift` | Confirms relay method allowlist, bearer auth, mutation/control scope, and current shared relay/history token default | Parallel relay/security reader plus parent spot-check | read |
| Tests and docs constraints | `CodexDockTests/*`; `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`; `docs/EPIC_CODEX_DOCK_MVP_2026-05-27.md`; relevant `README.md` sections | Confirms current tests prove env config and composer behavior, existing real-host smoke tests still require bearer env/file, and stale docs still describe phone-side OpenAI key/env paths | Parallel tests/docs reader plus parent spot-check | read |
| Existing local persistence pattern | `CodexDock/State/LocalThreadMetadataStore.swift` | Provides the Application Support JSON pattern for non-secret local metadata | Parent spot-check | read |
| Implementation Swift no-secret path | `CodexDockApp/CodexDockApp.swift`; `CodexDock/Configuration/RelayBootstrapStore.swift`; `CodexDock/Configuration/RelayDiscovery.swift`; `CodexDock/Features/Dock/CodexDockBootstrapView.swift`; `CodexDock/Features/Dock/DockView.swift`; `CodexDock/Features/Archive/ArchiveView.swift`; `CodexDock/Features/Hosts/HostsView.swift`; `CodexDock/State/HostSettingsStore.swift`; `CodexDock/State/ThreadDetailStore.swift`; `CodexDock/Voice/TranscriptionService.swift`; `CodexDockTests/DockStoreTests.swift`; `CodexDockTests/AppServerClientTests.swift` | Confirms physical startup is bootstrap/discovery-backed, saved/manual relay config is non-secret, Relay UI has no token save path, shared registry reaches Dock/Archive/Relay/Thread Detail, production voice defaults through the relay, and credential-bearing URLs are rejected | Parent implementation audit plus reused native agent audit | read |
| Implementation relay/build/docs boundary | `scripts/dock-relay.mjs`; `scripts/dock-relay-transcription.mjs`; `scripts/dock-relay-bonjour.mjs`; `scripts/dock-relay.test.mjs`; `Makefile`; `README.md`; `project.yml`; `CodexDockApp/Info.plist`; `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`; `.gitignore` | Confirms phoneAuth none, raw/history token stays behind relay, OpenAI key/model live on Mac relay, Bonjour TXT metadata is non-secret, device install has no env launch, stale docs are superseded, secret runtime files are ignored, relay failure tests cover missing key/upstream/empty/timeout, and the main relay script stays below the 1,000-line maintainability threshold | Parent implementation audit plus reused native agent audit | read |
| External transcription model scan | Artificial Analysis `gpt-4o-transcribe` page; UsefulAI 2026 transcription roundup; APIScout 2026 STT comparison; The Decoder Artificial Analysis coverage; Nils Durner diarization writeup | Confirms `gpt-4o-transcribe` is the strongest OpenAI-native default for this app, `gpt-4o-mini-transcribe` is cost-first override, and diarization is not V1 unless speaker labels are added | Parent web search plus plan carry-through check | read |
| Local instructions | `/Users/aelaguiz/.codex/RTK.md`; prompt-provided `AGENTS.md` instructions | Confirms shell commands should be prefixed with `rtk` | Parent | read |

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
| DEC-001 | Can app setup rely on Mac/debugger launch env? | Yes, keep `SIMCTL_CHILD_*`; no, phone must discover/connect from normal home-screen launch | Determines whether home-screen relaunch works | No Mac/debugger app launch after install; relay discovery is required | User | Plan North Star and Simple Solution require home-screen launch and no Mac-side app launch | resolved |
| DEC-002 | Should secrets be compiled into the app because it is personal? | Compile secrets; store/import secrets on phone; keep secrets on Mac relay | Determines binary leakage and app setup burden | Do not compile or store secrets on phone; relay owns secrets on Mac | User correction plus agent code read | Plan North Star, Simple Solution, Target Architecture, Security Posture, and Done State say the phone receives no OpenAI key or Codex token | resolved |
| DEC-003 | Should phone receive the raw/history app-server token? | Send raw token to phone; send relay token to phone; send no token to phone | Determines whether the phone can bypass relay API narrowing and whether setup has secrets | Send no token to phone; Mac relay keeps raw/history auth and exposes only app API | User correction plus relay/security read | Plan Relay Changes, Target Architecture, Security Posture, and Done State require server-owned secrets | resolved |
| DEC-004 | Is `ws://` acceptable for V1? | Require `wss://`; allow `ws://` on trusted private networks | Determines implementation scope and setup burden | Accept `ws://` for trusted LAN/Tailscale personal V1; document not public | Agent, from user simplicity goal | Plan Explicit V1 Choices and Security Posture carry this through | resolved |
| DEC-005 | Should V1 add QR/pairing at all? | Pair by QR/deep link; discover relay automatically | Determines setup burden and secret movement | No secret pairing in V1; use Bonjour relay discovery | User correction plus agent synthesis | Plan Simple Solution, Relay Changes, and iPhone App Changes remove QR/pairing and use discovery | resolved |
| DEC-006 | Should client auth be required for the phone-to-relay hop? | Bearer token in phone; Mac-side device approval; no client auth on trusted local network | Determines whether app can be install-and-open without setup | No client auth for personal V1; rely on private LAN/Tailscale and narrow relay API; harden later if needed | Agent, from user simplicity goal and relay code read | Plan Explicit V1 Choices and Security Posture carry no-client-token local mode and later hardening as non-V1 | resolved |
| DEC-007 | Which OpenAI transcription model should the relay default to? | `whisper-1`; `gpt-4o-mini-transcribe`; `gpt-4o-transcribe`; `gpt-4o-transcribe-diarize` | Determines accuracy/cost tradeoff and whether the phone can choose models | Use `gpt-4o-transcribe` as relay default; allow Mac-side cost override to `gpt-4o-mini-transcribe`; keep diarization out of V1 | Agent, after user requested online search beyond OpenAI docs | Plan Section 3 external anchors, Section 5 invariants, Section 7 Phase 1/3, Section 8, and Decision Log carry model policy and phone-side model-selection ban | resolved |

## Pass History

### Pass 1 - 2026-05-28

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: worktree files and parallel read reports; no implementation diff reviewed
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: five parallel read slices for app/config, build, voice, relay/security, tests/docs; parent ran all required plan-audit lenses plus docs-contract-drift and security-boundary
- Code areas read: app startup, host registry/config, Hosts UI/store, Dock root propagation, voice transcription/capture, relay auth/methods, Makefile/run path, simulator helper, XcodeGen project, Info.plist, local persistence pattern, tests, README, UX/epic docs
- Findings added: none after plan repair
- Findings resolved:
  - The first draft incorrectly leaned toward debug-launch seeding; replaced with phone-local pairing/import and home-screen relaunch.
  - The first draft did not separate relay and raw/history tokens; added token separation across payload, Makefile, tests, security posture, and done state.
  - The first draft did not name a persistence owner clearly; added canonical ownership for `LocalDockConfigurationStore`, `HostSettingsStore`, `HostRegistry`, and `DockHostConfiguration`.
  - The first draft under-specified physical install; added `device-install` as install-only with no env launch.
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code changes exist

### Pass 2 - 2026-05-28

- Mode: plan-readiness
- Scope: whole plan after user correction
- Baseline reviewed: same repo coverage plus new plan artifact
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent reran outcome, simplicity, canonical owner, proof, docs-contract-drift, and security-boundary lenses against the revised server-owned-secret plan
- Code areas read: same coverage as pass 1; no new code required because the change is architectural direction over already-read relay/app surfaces
- Findings added: none
- Findings resolved:
  - Superseded phone-side Keychain/pairing secret plan with local relay ownership of all OpenAI/Codex secrets.
  - Removed secret QR/pairing payload requirement.
  - Reframed setup around Bonjour discovery and no-client-token local relay mode.
  - Moved OpenAI transcription from phone-side API calls to relay-side `audio/transcribe`.
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code changes exist

### Pass 3 - 2026-05-28

- Mode: plan-readiness
- Scope: canonical full-arch plan after arch-step auto-plan, independent transcription-model web scan, and consistency repairs
- Baseline reviewed: `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`; existing audit log; repo code/read reports; two cold-reader consistency reports; parent spot-checks of plan sections and repo anchors
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: arch-step auto-plan research/deep-dive/phase-plan/consistency stages; four repo read explorers for relay/build, app/config, voice/session, tests/docs; two consistency explorers; parent reran all required plan-audit lenses plus docs-contract-drift, security-boundary, physical-device-proof, and transcription-model-selection lenses
- Code areas read: relay auth/API/logging/transcription insertion points; Makefile LaunchAgent and simulator env paths; app bootstrap/host config/Hosts UI; optional bearer transport; Dock/Archive/ThreadDetail consumers; voice transcription/composer behavior; real-host smoke tests; local JSON persistence pattern; README and stale UX/epic docs
- Findings added: none remain open
- Findings resolved:
  - Converted the noncanonical local-relay draft into a canonical full-arch document with active frontmatter, TL;DR, Section 0 through Section 10, planning receipts, call-site audit, and authoritative phases.
  - Repaired stale consistency gate metadata so the plan no longer says both "ready" and "do not proceed."
  - Added explicit migration coverage for existing real-host Swift smoke tests that still require bearer token env/file, preventing old phone-token proof from surviving as canonical physical acceptance.
  - Added Phase 1 exit proof for Bonjour advertisement, non-secret TXT metadata, transcription timeout behavior, and full sensitive-output redaction.
  - Tightened Phase 4 so manual physical-device proof is required before completion; missing device/signing access means pending proof, not done.
  - Rewrote verification language from "non-blocking" to "lean but required" where Section 7 and done-state require proof.
  - Added independent web-scan model decision: relay defaults to `gpt-4o-transcribe`; `gpt-4o-mini-transcribe` is Mac-side cost override only; `whisper-1` and diarization are not V1 defaults.
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code changes exist, especially no-client-auth relay boundary, stale real-host token tests, Bonjour proof, relay transcription model/default, and physical install proof

### Pass 4 - 2026-05-28

- Mode: implementation-audit
- Scope: whole plan implementation through Phase 4 code/docs/install target, excluding manual physical-device proof that is blocked by local Xcode signing/provisioning
- Baseline reviewed: current dirty worktree after relay boundary, Swift bootstrap/discovery, relay transcription, Relay tab cleanup, Makefile install target, generated project, README, UX-spec supersession note, worklog, and changed tests
- Test/CI context accepted, if supplied: `rtk npm test` passed with 14 relay tests; `rtk swift test` passed with 86 tests and 5 real-host smoke skips; generated simulator and generic iphoneos builds passed; physical install attempt reached signing/provisioning and failed because Xcode has no usable account/profile for team `Q2V42N8S7R` and bundle id `com.aelaguiz.CodexDockApp`
- Agents/lenses run: parent ran implementation-audit lenses for plan-code-fit, outcome-realization, requirement traceability, phase-frontier review, canonical owner/SSOT, existing-pattern fit, deletion/side-door closure, drift-proof coupling, caller/invariant/state, elegance/code-judo, tiny-team maintainability, test-code review, docs-contract-drift, security-boundary, and scope-creep; attempted to spawn new audit agents but the harness was at thread limit; reused existing native agent threads for Swift no-secret path and relay/build/docs boundary review, then repaired the returned findings
- Code areas read: `scripts/dock-relay.mjs`; `scripts/dock-relay-transcription.mjs`; `scripts/dock-relay-bonjour.mjs`; `scripts/dock-relay.test.mjs`; `Makefile`; `README.md`; `project.yml`; `CodexDockApp/Info.plist`; `CodexDockApp/CodexDockApp.swift`; `CodexDock/Configuration/*`; `CodexDock/AppServer/*`; `CodexDock/Features/Dock/*`; `CodexDock/Features/Archive/ArchiveView.swift`; `CodexDock/Features/Hosts/HostsView.swift`; `CodexDock/State/HostSettingsStore.swift`; `CodexDock/State/ThreadDetailStore.swift`; `CodexDock/Voice/TranscriptionService.swift`; `CodexDockTests/DockStoreTests.swift`; `CodexDockTests/AppServerClientTests.swift`; `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md`; `.gitignore`
- Obligations checked: no-client-auth phone relay; Mac-side raw/history token; narrow relay method allowlist; relay `audio/transcribe`; no phone-supplied model; Mac-side `gpt-4o-transcribe` default; Bonjour advertisement; optional Swift bearer config; env-independent physical startup; saved/manual non-secret relay persistence; Relay UI with no token side door; shared registry propagation; relay-backed production voice default; install-only physical target with no env launch; stale docs updated/superseded; ignored secret runtime files
- Findings added:
  - IMP-NOTE-001 - physical home-screen proof remains pending on local Xcode signing/provisioning
- Findings resolved:
  - The strict maintainability review flagged `scripts/dock-relay.mjs` crossing 1,000 lines; transcription and Bonjour helpers were split into focused modules, leaving the main relay script at 961 lines.
  - Agent implementation audit flagged credential-bearing WebSocket URLs as a phone-secret side door; shared URL validation now rejects URL username/password credentials for env config, bootstrap manual entry, and Relay tab saves.
  - Agent implementation audit flagged thin relay failure proof; relay tests now cover missing OpenAI key, upstream non-OK failure, empty transcript, and timeout.
  - Agent implementation audit flagged phone-reachable smoke tests that could accidentally send a bearer token; those smoke tests now instantiate phone-reachable clients with `bearerToken: nil`.
  - The Relay tab no longer exposes or preserves a bearer-token draft/save path.
  - Saved relay configuration is now an actual startup path when Bonjour has not yet produced a relay.
  - Manual Relay tab edits now persist through `LocalDockConfigurationStoring` with `bearerToken: nil`.
  - Stale UX-spec Host/token language is explicitly superseded by the relay-owned-secret plan.
- Findings carried forward:
  - IMP-NOTE-001
- Verdict: approve-with-notes
- Next audit focus: complete manual physical-device proof after Xcode account/provisioning is fixed; then re-run a short implementation audit focused only on Phase 4 proof artifacts and logs
