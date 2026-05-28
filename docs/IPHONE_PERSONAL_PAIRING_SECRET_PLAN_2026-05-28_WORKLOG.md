# Codex Dock iPhone Local Relay Worklog

Date: 2026-05-28
Plan: `docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md`

## Summary

- Implemented the Mac relay as the no-phone-secret boundary.
- Implemented iPhone relay discovery/bootstrap with optional bearer host config.
- Moved production voice transcription to relay-backed JSON-RPC.
- Added the physical `rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>` path.
- Updated README and the stale iPhone UX spec so they no longer teach phone-side OpenAI keys or bearer-token simulator launch as the real route.

## Phase 1 - Relay Boundary

Status: implemented.

- Added `--phone-auth none|bearer`; `make services` runs the relay with `--phone-auth none`.
- Kept raw/history app-server bearer auth inside the relay through `--history-auth-token-file`.
- Added `audio/transcribe` to the relay.
- The relay reads `OPENAI_API_KEY` from Mac env or `.env`.
- The relay default transcription model is `gpt-4o-transcribe`.
- Phone-supplied transcription model selection is rejected.
- Added audio payload validation, size limit, timeout, safe upstream errors, and no transcript/audio/key logging.
- Added `_codexdock._tcp` Bonjour advertisement with non-secret TXT records.
- Added Node tests for auth boundary, history token boundary, unsupported methods, transcription request shape, model ownership, payload validation, missing key, upstream failure, empty transcript, timeout, and log redaction.
- Split relay transcription and Bonjour helpers out of the main relay script after a strict maintainability review pushed back on the main relay file crossing 1,000 lines.

Proof:

```sh
rtk npm test
```

Result: passed, 14 relay tests.

Follow-up syntax/structure proof:

```sh
rtk node --check scripts/dock-relay.mjs
rtk node --check scripts/dock-relay-transcription.mjs
rtk node --check scripts/dock-relay-bonjour.mjs
rtk npm test
```

Result: syntax checks passed, and 14 relay tests still passed after the split.

## Phase 2 - iPhone Discovery And No-Token Host Config

Status: implemented.

- Changed `DockHostConfiguration.bearerToken` to optional.
- Kept dev env configuration working with optional bearer tokens.
- Added `DiscoveredRelay`, `BonjourRelayDiscovery`, `LocalRelayConfiguration`, and `FileLocalDockConfigurationStore`.
- Added `RelayBootstrapStore` and `CodexDockBootstrapView`.
- App startup now uses bootstrap/discovery instead of failing immediately when env config is absent.
- Added Bonjour declarations to `project.yml` and `CodexDockApp/Info.plist`.
- Reworked the visible Hosts tab into the Relay tab.
- Removed the Relay tab's token field and the hidden bearer-token save path.
- Made Relay tab manual URL edits persist through the same non-secret relay configuration store.
- Made saved relay configuration an actual startup path when Bonjour has not yet published a relay.
- Rejected credential-bearing WebSocket URLs like `ws://token@host:4510` across env-derived config, first-launch manual setup, and Relay tab manual saves.

Proof:

```sh
rtk swift test
```

Result: passed, 86 tests, 5 real-host smoke tests skipped because their explicit env flags were not set.

## Phase 3 - Relay Voice Transcription

Status: implemented.

- Added `AudioTranscribeParams` and `AudioTranscribeResponseDTO`.
- Added `AppServerMethods.audioTranscribe` and `AppServerClient.audioTranscribe`.
- Added `RelayTranscriptionClient`.
- Changed `ThreadDetailStore` production default to `RelayTranscriptionClient(host:)`.
- Kept `OpenAITranscriptionClient` as non-default reusable code only; production app bootstrap no longer constructs it.
- Existing composer voice behavior tests still prove transcript insertion, no auto-submit, editable draft, and failure recovery.

Proof:

```sh
rtk swift test
```

Result: passed, including relay transcription request-shape coverage.

## Phase 4 - Install Target, Docs, And Physical Proof

Status: partially implemented; manual physical proof is blocked by local Xcode account/provisioning state.

- Added `rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>`.
- The target starts Mac services, builds for `iphoneos`, and installs with `xcrun devicectl`.
- The target does not launch the app and does not pass env vars or secrets to the phone.
- Updated README with the simple route: `rtk make services`, install once, open from home screen.
- Updated the stale UX spec sections that said the OpenAI key could be embedded in the iPhone client.
- Ran generated-project builds:

```sh
rtk xcodegen generate --spec project.yml
rtk xcodebuild -quiet -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'generic/platform=iOS Simulator' -derivedDataPath .codex-dock/DerivedData build
rtk xcodebuild -quiet -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'generic/platform=iOS' -derivedDataPath .codex-dock/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Result: both generic simulator and generic iphoneos compile checks passed.

Follow-up implementation audit pass:

```sh
rtk xcodegen generate --spec project.yml
rtk xcodebuild -quiet -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'generic/platform=iOS Simulator' -derivedDataPath .codex-dock/DerivedData build
rtk xcodebuild -quiet -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'generic/platform=iOS' -derivedDataPath .codex-dock/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Result: both generated-project builds passed after the Relay tab and saved-relay fallback fixes.

Physical install attempt:

```sh
rtk make device-install DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E DEVELOPMENT_TEAM=Q2V42N8S7R
```

Result:

- Mac services started.
- Relay health returned `{"ok":true,"service":"codex-dock-relay","auth":"none"}`.
- Physical build/install did not complete because Xcode reported no account/provisioning profile for team `Q2V42N8S7R` and bundle id `com.aelaguiz.CodexDockApp`.

Pending manual proof after Xcode account/provisioning is fixed:

- install on physical iPhone;
- launch from home screen;
- confirm Bonjour discovery;
- confirm session load;
- force-quit/relaunch;
- phone reboot/relaunch;
- confirm voice transcription through the relay.

## Secret/Log Check

Ran a targeted scan over relay logs, app docs, Makefile, relay code, and app code for concrete key/token/audio/transcript leak patterns.

Result:

- No OpenAI key value, raw bearer value, simulator secret injection, raw audio sample, or transcript sample appeared in the scanned logs/docs.
- Expected code-level identifiers such as `base64Audio` and `OPENAI_API_KEY` remain where they define the relay contract or Mac-side `.env` loading.
- `.env` and `.codex-dock/` are ignored by Git, including the generated app-server token and relay logs.

## Current Blocker

The only known incomplete acceptance item is physical home-screen proof. The app can compile for device, the service boundary is live, and `device-install` reaches signing, but Xcode needs a valid account/provisioning profile for `com.aelaguiz.CodexDockApp` before installation can finish.
