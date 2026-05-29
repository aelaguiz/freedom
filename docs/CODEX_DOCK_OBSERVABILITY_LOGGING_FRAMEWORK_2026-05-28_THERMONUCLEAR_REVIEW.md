# Codex Dock Observability Logging Framework - Thermonuclear Review

Date: 2026-05-28

Plan: `docs/CODEX_DOCK_OBSERVABILITY_LOGGING_FRAMEWORK_2026-05-28.md`

Scope: Swift `DockLog`/MetricKit diagnostics, relay structured logger, logging call sites across app-server/dock/archive/bootstrap/detail/voice/transcription/connectivity paths, capture commands, docs, and runtime proof.

Verdict: approved. No blocking findings remain. Physical device logarchive collection is blocked by a local root-permission requirement and is recorded as a proof blocker, not a code blocker.

## Blocking Findings

None open.

## Resolved During Review

- [x] OBS-001 - Physical-device log command used a non-existent `devicectl` log path
  - Evidence: `rtk sh -c 'timeout 20s xcrun devicectl device log stream --device 0A4EFF8B-54D8-58FB-B3FB-63263265B9CC --predicate '\''subsystem == "com.aelaguiz.CodexDock"'\'''` failed with `Error: Unknown option '--device'`; `xcrun devicectl device log stream --help` showed no `log` subcommand for this Xcode.
  - Why it mattered: the plan's future-agent instructions would have preserved a bad physical log command.
  - Fix: `Makefile`, `README.md`, `AGENTS.md`, and the plan now use `rtk xcrun log collect --device-udid <device-udid> --last 10m --predicate 'subsystem == "com.aelaguiz.CodexDock"' --output ...`.
  - Proof: `rtk make help` now advertises `rtk make device-logs DEVICE=<UDID> Collect Codex Dock device logarchive`.

- [x] OBS-002 - Physical logarchive collection needs root on this machine
  - Evidence: corrected command `rtk make device-logs DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC DEVICE_LOG_OUTPUT=/tmp/codex-client/observability-physical-0A4EFF8B-54D8-58FB-B3FB-63263265B9CC.logarchive` failed with `log: Must be root to collect logs from attached device`.
  - Why it mattered: the plan requires physical proof or an exact blocker.
  - Fix: recorded the exact blocker in `AGENTS.md`, `README.md`, the plan implementation-audit block, the worklog, and this review.
  - Boundary: physical install/launch/process proof passed, and relay logs showed the phone-path request sequence; only the physical device logarchive artifact needs root.

- [x] OBS-003 - Name-based simulator destination was not available
  - Evidence: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build` failed because no simulator has exact name `iPhone 17`.
  - Fix: used available fallback simulator `feat_anim_1 - iPhone 17`, UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`.
  - Proof: Xcode build, Xcode test, installed simulator launch, and simulator log proof all passed on the fallback UDID.

- [x] OBS-004 - Logging initially changed the offline initialization state shape
  - Evidence: `rtk swift test --filter AppServerClientTests` initially failed `testOfflineAndMalformedResponsePathsSurfaceExplicitState` after connect logging was added.
  - Why it mattered: logging must not alter connection-state behavior.
  - Fix: `AppServerClient.connectAndInitialize` now preserves offline connection failures through `isOfflineConnectionFailure` and only uses error state for non-offline failures.
  - Proof: `rtk swift test --filter AppServerClientTests` passed afterward with 43 tests and 5 skips.

- [x] OBS-005 - iOS-only build caught Logger autoclosure/self-capture issues
  - Evidence: the fallback Xcode build initially failed in `CodexDock/Voice/VoiceCaptureController.swift` after Swift package tests passed.
  - Why it mattered: Swift `Logger` interpolation autoclosures can capture actor-isolated or non-Sendable state differently under the iOS app target.
  - Fix: hoisted values before log interpolation and avoided unsafe `self` captures in the iOS voice logging paths.
  - Proof: `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` passed.

- [x] OBS-006 - Relay direct stderr side doors were closed
  - Evidence: relay logging previously used direct `console.error` paths.
  - Fix: added `scripts/dock-relay-logger.mjs`, injected the logger through relay/runtime helpers, and moved upstream WebSocket client logging into `scripts/dock-relay-json-rpc-client.mjs`.
  - Proof: `rtk rg -n "console\\.(error|warn|log|debug)" scripts/dock-relay*.mjs` returned no matches, and `rtk npm run test:relay` passed 39 tests.

- [x] OBS-007 - Secret/content redaction needed explicit tests and sampled runtime proof
  - Evidence: app and relay logging touches audio/transcription, host config, auth, JSON-RPC, and error surfaces.
  - Fix: added `CodexDockTests/DiagnosticsLoggingTests.swift`; relay logger sanitizes sensitive keys, URLs, byte buffers, full payload-like fields, bearer/API key strings, OpenAI key patterns, and large token-like strings.
  - Proof: `rtk swift test --filter DiagnosticsLoggingTests` passed; sampled `.codex-dock/dock-relay.err.log` scan for `transcript|prompt|base64Audio|Authorization|Bearer|OPENAI_API_KEY|sk-` returned no matches.

## Notes

- The relay emits a lot of debug records during `thread/list` preview enrichment. That is acceptable for this local observability pass because those records stay structured, sanitized, and in the relay stderr log; no runtime behavior or app UI is coupled to them.
- `MetricKitDiagnosticsReporter` delivery is platform-timed. The implementation proves subscription/summary/persistence wiring and app bootstrap buildability; it does not try to force a crash/hang payload during tests.
- Native subagents were not used for this review because the current multi-agent tool policy only permits subagents when the user explicitly asks for delegation or parallel agent work.

## Verification Accepted

- `rtk npm run test:relay` passed, 39 tests.
- `rtk swift test --filter DiagnosticsLoggingTests` passed, 3 tests.
- `rtk swift test --filter AppServerClientTests` passed, 43 tests, 5 skipped.
- `rtk swift test --filter DockStoreTests` passed, 19 tests.
- `rtk swift test --filter ThreadDetailStoreTests` passed, 50 matching tests.
- `rtk swift test --filter VoiceCaptureControllerTests` passed, 5 tests.
- `rtk swift test --filter AppConnectivityStoreTests` passed, 11 tests.
- `rtk swift test --filter DockConfigurationTests` passed, 14 tests.
- `rtk swift test` passed, 182 tests, 5 skipped.
- `rtk xcodegen generate --spec project.yml` passed.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B' build` passed.
- `rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'id=BAD95C8E-3E57-4818-9B90-E4ED22593B4B'` passed.
- `rtk make services`, `rtk make app-server-status`, and `rtk make dock-relay-status` passed.
- `rtk make app SIM='feat_anim_1 - iPhone 17'` passed and launched against `ws://192.168.50.117:4510`.
- Simulator log proof passed with `rtk xcrun simctl spawn BAD95C8E-3E57-4818-9B90-E4ED22593B4B log show --last 2m --style compact --predicate 'subsystem == "com.aelaguiz.CodexDock"'`.
- Physical iPhone 14 install passed with `rtk make device-install DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC DEVELOPMENT_TEAM=R6B8KXF3QW`.
- Physical iPhone 14 launch passed with `rtk xcrun devicectl device process launch --device 0A4EFF8B-54D8-58FB-B3FB-63263265B9CC --terminate-existing com.aelaguiz.CodexDockApp`.
- Physical process proof passed and showed `CodexDockApp` pid `4561`.
- Physical logarchive collection is blocked by `log: Must be root to collect logs from attached device`.
- `rtk make help` readback showed the new log commands.

## Acceptance Boundary

The logging framework implementation is complete for simulator, relay, Swift package, Xcode build/test, service, and physical install/launch proof. The only remaining artifact is physical device logarchive collection under root privileges; this is an environment permission blocker and does not change the approved code verdict.
