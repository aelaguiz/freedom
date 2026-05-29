# Codex Dock Timeout And Magic Constant Audit

Date: 2026-05-29

## Scope

This audit inventories hard-coded timeout-like and behavior-shaping constants in
the Codex Dock app and relay source.

Included:

- Swift app and tests: `CodexDock/**`, `CodexDockApp/**`,
  `CodexDockTests/**`, `CodexDockUITests/**`
- Node relay, host-service, device config, and JS tests: `scripts/**`
- Canonical config and commands: `Makefile`, `Package.swift`, `package.json`,
  `project.yml`

Excluded:

- `docs/**`, `.codex-dock/**`, `.build/**`, `.swiftpm/**`, `node_modules/**`,
  logs, generated Xcode project files, historical artifacts
- Pure visual spacing, fixture timestamps, JSON-RPC version/status codes,
  normal loop counters, file modes, and protocol-defined limits unless they
  directly affect timing, retries, page size, queues, ports, or service behavior

Method:

- Parent local grep/read pass using `rg` and exact file reads.
- Parallel explorers:
  - `Singer`: Swift app/tests.
  - `Bohr`: Node relay/Makefile/scripts/tests.
  - `Nash`: repo-wide cross-check.

## Executive Summary

Yes, there are multiple fixed timeouts and magic constants. The `home` failure
is explained by a hard-coded relay upstream JSON-RPC timeout:

- `scripts/dock-relay-json-rpc-client.mjs:3`: `DEFAULT_TIMEOUT_MS = 5_000`

That `5s` relay timeout is shorter than several app-side `10s` request budgets.
So the app can be willing to wait, while the relay has already killed the raw
app-server `thread/list` page.

The riskiest pattern is disagreement between layers:

- Relay upstream connect/request: `5_000ms`
- Swift logical host connect: `5s`
- Swift JSON-RPC requests: `10s`
- Realtime connect: `10s`
- Realtime completion: `30s`
- Health checks: `500ms`
- Dock auto-refresh: `5s`
- Host service readiness: `10 * 1s = 10s`

The second major risk is full-list load amplification:

- Human list page size: `100`
- Agent list page size: `50`
- Relay `thread/list` max page size: `100`
- Live loaded-thread sweep: `500`
- History upstream pool: `1` connection
- Dock refresh loop: every `5s`

After removing caps, slow hosts with thousands of rows can exceed the relay's
fixed per-page request timeout.

## Highest Risk Findings

| Severity | Location | Value | Category | What It Controls | Why It Matters | Recommendation |
|---|---|---:|---|---|---|---|
| P0 | `scripts/dock-relay-json-rpc-client.mjs:3`, `:62`, `:179` | `5_000ms` | Timeout | Upstream WebSocket connect and every upstream JSON-RPC request. | This is the exact timeout hit by `home`; one `thread/list` page can exceed it. | Split connect and request timeouts. Add env/config knobs. Show active values in `/statusz`. |
| P1 | `CodexDock/State/AppServerDockClient.swift:70-71`, `:117` | `100`, `50`, `10s` | Page cap + timeout | Full dock list pagination and per-page wait. | Full thread loading can make many sequential pages per host/scope. | Put list policy in one place; consider bounded/incremental loading or host-specific timeout/backoff. |
| P1 | `CodexDock/AppServer/AppServerHostConnector.swift:32`, `:48`, `:69` | `5s` | Timeout | Logical host connect + initialize. | Can fail before normal app request timeout; duplicated from detail path. | Add `AppServerTimeoutPolicy.connectInitialize`; align with relay/app budgets. |
| P1 | `CodexDock/State/DockStore.swift:282`, `CodexDock/Features/Dock/DockView.swift:159` | `5s` | Interval | Dock auto-refresh cadence. | Can re-run expensive full-list loads while a slow host is still struggling. | Add slow-host backoff; make refresh cadence named/configurable. |
| P1 | `scripts/dock-relay-status.mjs:6`, `scripts/codex-dock-host-service-runtime.mjs:88` | `500ms` | Health timeout | Relay and host-service health probes. | Too short for busy/remote dev hosts; health can disagree with real request path. | Add shared `CODEX_DOCK_HEALTH_TIMEOUT_MS`; use separate local vs remote defaults if needed. |
| P1 | `scripts/dock-relay-thread-data.mjs:288-291` | `500` | Page cap | Live `thread/loaded/list` sweep. | Large burst and can silently miss loaded rows past first page. | Name and document the cap, or paginate/batch. |
| P1 | `scripts/dock-relay.mjs:564-567`, `scripts/dock-relay-thread-data.mjs:16-21` | `history: 1`, `live-status: 4` | Pool cap | Shared upstream connection limits. | A single slow history request blocks later history work; overload looks like app-server failure. | Centralize pool policy; make visible/configurable. |
| P2 | `scripts/dock-relay.mjs:57-59` | `2`, `100ms`, `25ms` | Retry/delay | Relay live upstream reconnect. | Much shorter than Swift reconnect behavior. | Make relay reconnect policy named/configurable and align with Swift policy. |
| P2 | `scripts/dock-relay-live-status-cache.mjs:3-4` | `5_000ms`, `2_500ms` | Stale age + interval | Live overlay freshness and refresh cadence. | Hidden background load/freshness policy. | Env-wire and expose active values in status. |
| P2 | `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift:38-39`, `scripts/dock-relay-realtime-transcription.mjs:11-15` | `30s`, `64KiB`, `10s`, `5min`, `1MiB` | Timeout/byte caps | Phone and relay transcription limits. | App and relay can drift if relay env overrides are used. | Return relay limits to the app; enforce advertised limits. |

## Production Inventory

### Swift App: Network And Request Timing

| Location | Value | Category | Controls | Risk | Recommendation |
|---|---:|---|---|---|---|
| `CodexDock/AppServer/AppServerClient.swift:35` | `3` attempts | Retry | Live detail reconnect attempts. | Arbitrary. | Name as default reconnect policy and document expected LAN/Tailscale behavior. |
| `CodexDock/AppServer/AppServerClient.swift:36` | `500ms` | Delay | Initial reconnect backoff. | Arbitrary. | Keep in a named reconnect policy. |
| `CodexDock/AppServer/AppServerClient.swift:37` | `5_000ms` | Delay cap | Max reconnect backoff. | Can under-wait slow network recovery. | Name and align with relay reconnect policy. |
| `CodexDock/AppServer/AppServerClient.swift:38` | `0.2` | Jitter | Reconnect jitter window, about +/-20%. | Reasonable but unexplained. | Name `reconnectJitterRatio`. |
| `CodexDock/AppServer/AppServerClient.swift:53` | `0.0` | Jitter default | Custom reconnect policy default. | Low. | Keep, but make reconnecting callers choose intentionally. |
| `CodexDock/AppServer/AppServerClient.swift:66` | `20` | Backoff cap | Caps exponent in reconnect delay calculation. | Cryptic. | Name `maximumBackoffExponent`. |
| `CodexDock/AppServer/AppServerClient.swift:156`, `:207`, `:240`, `:254`, `:272`, `:284`, `:296`, `:308`, `:320`, `:332`, `:344`, `:356`, `:368`, `:380`, `:392`, `:404` | `10s` | Timeout | Default initialize, generic request, typed request, thread, turn, archive, and audio JSON-RPC waits. | High duplication; not operation-aware. | Add `AppServerClient.defaultRequestTimeout`; override slow operations explicitly. |
| `CodexDock/AppServer/AppServerClient.swift:509` | caller timeout | Timeout task | Cancels pending Swift JSON-RPC requests. | Correct mechanism, but fed by many literals. | Route through named policy. |
| `CodexDock/AppServer/AppServerClient.swift:646` | reconnect policy | Sleep | Delay between reconnect attempts. | Depends on policy above. | Covered by reconnect policy fix. |
| `CodexDock/AppServer/AppServerClient.swift:687` | `250ms` | Poll interval | Waits for foreground work before reconnect. | Hidden duplicate of Dock foreground wait. | Share a lifecycle polling constant. |
| `CodexDock/AppServer/AppServerClient.swift:879` | `8 * 1024 * 1024` bytes | Message cap | URLSession WebSocket receive max, 8 MiB. | Large threads/details can fail at transport layer. | Surface a clear error; align with server/relay payload limits. |
| `CodexDock/AppServer/AppServerHostConnector.swift:32`, `:48`, `:69` | `5s` | Timeout | Logical host connect and initialize. | Shorter than normal app request timeout. | Use `AppServerTimeoutPolicy.connectInitialize`; consider `10-15s` for relay-backed hosts. |
| `CodexDock/State/ThreadDetailStore.swift:212` | `5s` | Timeout | Detail screen connect and initialize. | Duplicates host connector risk. | Use same connect timeout policy. |
| `CodexDock/State/ThreadDetailStore.swift:316`, `:322`, `:522`, `:544`, `:572` | `10s` | Timeout | Send draft, read thread, page turns, resume thread. | Slow real hosts may need more than a flat 10s. | Split into operation-named timeouts. |
| `CodexDock/State/AppServerDockClient.swift:117`, `:164`, `:175` | `10s` | Timeout | `thread/list`, archive, unarchive from Dock views. | `thread/list` is now full paginated work. | Use list/archive-specific policies. |
| `CodexDock/Configuration/RelayDiscovery.swift:292` | `4s` | Timeout | Bonjour `NetService.resolve(withTimeout:)`. | Could be short on slow LAN discovery. | Name `bonjourResolveTimeoutSeconds`; test slower discovery fallback. |

### Swift App: Load, Page, Poll, And Audio Caps

| Location | Value | Category | Controls | Risk | Recommendation |
|---|---:|---|---|---|---|
| `CodexDock/State/DockStore.swift:282` | `5s` | Refresh interval | Dock auto-refresh. | Amplifies slow full-list loads. | Add slow-host backoff and a named setting. |
| `CodexDock/Features/Dock/DockView.swift:149` | `250ms` | Poll interval | Initial Dock load waits for foreground work. | Hidden timing knob. | Share lifecycle polling constant. |
| `CodexDock/State/AppServerDockClient.swift:70` | `100` rows | Page cap | Human/default session list page size. | Interacts with full-list load cost. | Move to `DockPaginationPolicy`. |
| `CodexDock/State/AppServerDockClient.swift:71` | `50` rows | Page cap | Active-agent session list page size. | Looks arbitrary; doubles pages versus `100`. | Document why agents are half-size or align with server cap. |
| `CodexDock/State/ThreadDetailStore.swift:105` | `100` turns | Page cap | Full detail `thread/turns/list` page size. | Duplicated in tests; hidden protocol assumption. | Share a named page-limit constant. |
| `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift:38` | `30s` | Timeout | Wait after commit for final transcription event. | May drift from relay/OpenAI behavior. | Name and align with relay-advertised limits. |
| `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift:39` | `64 * 1024` bytes | Chunk cap | Max audio chunk sent by phone. | Can drift from relay env cap. | Have relay advertise max chunk bytes. |
| `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift:62`, `:153`, `:181` | `10s` | Timeout | Transcription start, append, commit JSON-RPC commands. | Same flat timeout across different operations. | Name audio operation timeouts separately. |
| `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift:200` | `5s` | Timeout | Best-effort transcription cancel. | Low; failure ignored. | Name and debug-log cancel failures. |
| `CodexDock/Voice/VoiceCaptureController.swift:69` | `24_000Hz` | Audio format | Preferred input sample rate. | Duplicated with relay sample rate. | Centralize in `VoiceAudioFormat.pcm16Mono24k`. |
| `CodexDock/Voice/VoiceCaptureController.swift:74` | `1` channel | Audio format | Preferred mono input. | Low. | Name `targetChannelCount`. |
| `CodexDock/Voice/VoiceCaptureController.swift:98` | `2_048` frames | Buffer cap | AVAudioEngine tap buffer size. | Controls latency and chunk cadence. | Name `captureTapBufferFrames`; document target chunk duration. |
| `CodexDock/Voice/VoiceCaptureController.swift:411` | `24_000.0Hz` | Audio format | PCM16 output resampling target. | Duplicate of preferred sample rate. | Use same sample-rate constant. |
| `CodexDock/Features/Session/ComposerView.swift:143` | `minimumDistance: 0` | Gesture threshold | Hold-to-dictate drag starts immediately. | Accidental gesture risk. | Name/comment or consider nonzero threshold if UX issues appear. |

### Swift App: Text, Logging, And Ordering Constants

| Location | Value | Category | Controls | Risk | Recommendation |
|---|---:|---|---|---|---|
| `CodexDock/Diagnostics/Logging.swift:41` | `96` chars | Log cap | `DockLog.publicID` clipping. | Low. | Name `publicIDMaxLength`. |
| `CodexDock/Diagnostics/Logging.swift:58` | `1_000` | Unit conversion | Seconds to milliseconds. | Not arbitrary. | Leave as-is. |
| `CodexDock/Diagnostics/Logging.swift:61` | `240` chars | Log cap | Default redacted string clipping. | Low. | Name `redactedMaxLength`. |
| `CodexDock/Diagnostics/Logging.swift:66` | `{16,}` | Redaction threshold | `sk-...` token detection. | Could miss shorter secrets. | Name/comment threshold. |
| `CodexDock/Diagnostics/Logging.swift:67` | `{120,}` | Redaction threshold | Large base64-ish token detection. | Arbitrary. | Name `largeTokenMinimumLength`. |
| `CodexDock/Models/SessionSummaryMapper.swift:365`, `:368` | `80` chars | Text cap | Dock row title from name/preview. | Low. | Name `displayTitleMaxLength`. |
| `CodexDock/Models/SessionSummaryMapper.swift:415` | `140` chars | Text cap | Default collapsed text length. | Possibly unused because callers pass `80`. | Remove default or name it. |
| `CodexDock/State/SessionRowProjector.swift:88-102` | `0...5` | Sort priority | Row status ordering. | Low. | Consider enum-backed priority names if it changes. |
| `CodexDock/State/AppConnectivityStore.swift:548-571` | `0...10` | Sort priority | Connectivity state ordering. | Low. | Consider enum-backed priority names if it changes. |
| `CodexDock/State/SessionRowProjector.swift:146-153` | `60`, `3_600`, `86_400` seconds | Time buckets | Relative activity labels. | Standard units. | Optional named minute/hour/day constants. |

### Node Relay And Host Services: Timeouts, Retries, Intervals

| Location | Value | Category | Controls | Risk | Recommendation |
|---|---:|---|---|---|---|
| `scripts/dock-relay-json-rpc-client.mjs:3`, `:62`, `:179` | `5_000ms` | Timeout | Upstream connect and JSON-RPC request timeout. | P0 for `home`; one value covers different operations. | Split connect/request; env-wire request timeout. |
| `scripts/dock-relay-json-rpc-client.mjs:250`, `:274-285` | `250ms` | Close timeout | Forced upstream WebSocket termination. | Could be short during cleanup. | Name/configure; align with relay close timeout. |
| `scripts/dock-relay-status.mjs:6`, `:23` | `500ms` | Health timeout | Relay raw app-server health GET. | Tight on busy/remote dev hosts. | Shared health timeout knob. |
| `scripts/codex-dock-host-service-runtime.mjs:88` | `500ms` | Health timeout | Host-service status/doctor HTTP checks. | Same risk as relay health. | Share with relay health timeout. |
| `Makefile:32`, `:121` | `10` attempts, `sleep 1` | Service wait | `rtk make services` readiness loop. | Fixed 10s total. | Add `HOST_SERVICE_WAIT_INTERVAL` or total timeout variable. |
| `scripts/dock-relay.mjs:57-59` | `2`, `100ms`, `25ms` | Retry/delay | Relay focused live upstream reconnect. | Very short recovery window. | Env/configure and align with Swift reconnect policy. |
| `scripts/dock-relay.mjs:868-872` | `250ms` | Shutdown timeout | Downstream socket force terminate. | Could interrupt graceful close. | Name and align with JSON-RPC close timeout. |
| `scripts/dock-relay.mjs:904` | `1_000ms` | Shutdown timeout | Force process exit after signal. | Cleanup may need longer. | Name and make configurable if needed. |
| `scripts/codex-dock-host-service.mjs:424` | `2s` | Restart delay | systemd `RestartSec`. | Arbitrary service recovery cadence. | Name/configure restart delay. |
| `scripts/codex-dock-host-service.mjs:671`, `:691`, `:709`, `:722` | `1_000ms` | Retry delay | launchd retry/bootout spacing. | Hidden fixed service-control delay. | Name constant and document. |
| `scripts/dock-relay-live-status-cache.mjs:3` | `5_000ms` | Stale max age | Live overlay freshness. | Hidden freshness policy. | Env-wire and expose in `/statusz`. |
| `scripts/dock-relay-live-status-cache.mjs:4`, `:73` | `2_500ms` | Refresh interval | Live status refresh cadence. | Background load source. | Env-wire and expose in `/statusz`. |
| `scripts/dock-relay-leak-check.mjs:24` | `2_000ms` | Health timeout | Leak-check status fetch. | Could fail on slow hosts. | Env-wire if used on remote hosts. |
| `scripts/dock-relay-leak-check.mjs:55-56`, `:70`, `:99` | `10_000ms`, `250ms` | Wait/interval | Waits for history pool pending requests to drain. | Medium. | Expose interval env too. |

### Node Relay And Host Services: Page, Queue, Pool, Audio, And Log Caps

| Location | Value | Category | Controls | Risk | Recommendation |
|---|---:|---|---|---|---|
| `scripts/dock-relay-thread-data.mjs:10`, `:176` | `100` rows | Page cap | Relay clamps `thread/list`. | Probably Codex cap; duplicated with Swift. | Comment/source this protocol cap; share in tests. |
| `scripts/dock-relay-thread-data.mjs:199` | `sorted.length || 1` | Page fallback | In-memory string pagination default. | Low. | Fine. |
| `scripts/dock-relay-thread-data.mjs:288-291` | `500` | Page cap | `thread/loaded/list` live discovery. | Can miss rows and creates burst reads. | Paginate or name/document cap. |
| `scripts/dock-relay-thread-data.mjs:330` | `100ms` | Delay | Pending-request probe after `thread/resume`. | Race-prone if reintroduced in hot path. | Delete if retired or replace with event wait. |
| `scripts/dock-relay-upstream-pool.mjs:6`, `:26` | `4` | Pool cap | Default max open upstream sockets per label. | Hidden capacity limit. | Expose config/status. |
| `scripts/dock-relay.mjs:564-567`, `scripts/dock-relay-thread-data.mjs:16-21` | `history: 1`, `live-status: 4` | Pool cap | Shared upstream pool limits. | Single history connection can block later work. | Centralize and make configurable. |
| `scripts/dock-relay-thread-summary-cache.mjs:5-7`, `:111-113` | `10`, `500`, `2` | Cache/page/concurrency | Summary turn limit, max cache entries, max concurrent warmers. | Hidden background load. | Expose in `/statusz`; consider env knobs. |
| `scripts/dock-relay-thread-summary-cache.mjs:14` | `10_000_000_000` | Time heuristic | Seconds-vs-ms timestamp cutoff. | Cryptic. | Name `SECONDS_TIMESTAMP_CUTOFF_MS`. |
| `scripts/dock-relay-thread-summary-cache.mjs:241`, `scripts/dock-relay.mjs:65` | `12` hex chars | Diagnostic cap | Short hashes in logs/errors. | Low. | Share one helper constant. |
| `scripts/dock-relay-realtime-transcription.mjs:8` | `24_000Hz` | Audio format | OpenAI realtime PCM sample rate. | Duplicated with Swift capture. | Share/adverstise audio format. |
| `scripts/dock-relay-realtime-transcription.mjs:10` | `"low"` | Realtime delay | Default OpenAI transcription delay. | Duplicated with Makefile/env writer. | Single source for default delay. |
| `scripts/dock-relay-realtime-transcription.mjs:11`, `:174-184` | `10_000ms` | Timeout | OpenAI realtime WebSocket open wait. | Medium; env-wired. | Document default; include in status/capabilities. |
| `scripts/dock-relay-realtime-transcription.mjs:12`, `:535-545` | `5 * 60_000` | Max duration | Max transcription session length, 5 minutes. | Medium; env-wired. | Return active limit to app. |
| `scripts/dock-relay-realtime-transcription.mjs:13` | `64 * 1024` bytes | Chunk cap | Max incoming audio chunk. | Duplicated with Swift. | Return active limit to app. |
| `scripts/dock-relay-realtime-transcription.mjs:14`, `:378-390` | `1024 * 1024` bytes | Queue cap | Pending audio WebSocket buffer. | Medium. | Expose active value in status/capabilities. |
| `scripts/dock-relay-realtime-transcription.mjs:15`, `:170-171` | `64 * 1024` bytes | Text cap | Safe transcript/error text clipping. | Medium. | Env-wire if needed. |
| `scripts/dock-relay-realtime-transcription.mjs:16`, `:591` | `512` | Audio threshold | Non-silent PCM peak count. | Arbitrary tuning. | Name rationale or tune from real audio. |
| `scripts/dock-relay-realtime-transcription.mjs:88-89` | `3 / 4`, `+2` | Byte heuristic | Pre-decode base64 size estimate. | Low but cryptic. | Comment padding tolerance. |
| `scripts/dock-relay-realtime-transcription.mjs:116-127` | `2` bytes | PCM frame size | PCM16 sample stats. | Not arbitrary. | Name `PCM16_BYTES_PER_SAMPLE`. |
| `scripts/dock-relay-logger.mjs:7-9` | `500`, `20`, `40` | Log caps | Sanitized log string/array/object clipping. | Medium. | Keep named; consider central shared logging constants. |
| `scripts/dock-relay-logger.mjs:25-26`, `scripts/codex-dock-host-service-runtime.mjs:125-126` | `{16,}`, `{120,}` | Redaction thresholds | Secret/token redaction. | Duplicated and arbitrary. | Share named redaction policy. |
| `scripts/codex-dock-host-service-runtime.mjs:67` | `32` bytes | Token entropy | Raw app-server bearer token size. | Good default, not risky. | Optional `TOKEN_BYTES` constant. |
| `scripts/codex-dock-host-service-runtime.mjs:83`, `scripts/codex-dock-host-service.mjs:864`, `:868-880`, `Makefile:165`, `:168`, `:180`, `:185`, `:192`, `:209`, `:212`, `:219` | `200`, `40`, `80` lines | Log caps | Tail size in status/build failure outputs. | Can hide root cause lines. | Add `LOG_TAIL_LINES` / failure-tail variables. |

### Ports, Listen Defaults, And Endpoint Guards

| Location | Value | Category | Controls | Risk | Recommendation |
|---|---:|---|---|---|---|
| `Makefile:3`, `scripts/codex-dock-host-service.mjs:22` | `4500` | Port | Raw Codex app-server. | Intentional but duplicated. | Keep canonical constants; avoid fresh literals. |
| `Makefile:15`, `:47`, `:50`, `:52`, `scripts/codex-dock-host-service.mjs:23`, `scripts/dock-relay.mjs:936` | `4510` | Port | Dock relay. | Intentional but duplicated across Swift/JS/tests. | Add Swift default relay/raw port constants. |
| `Makefile:16`, `scripts/codex-dock-host-service.mjs:25` | `0.0.0.0` | Listen host | Relay bind address. | Medium with `phoneAuth: none`; expected for phone access. | Document/security-check default. |
| `scripts/codex-dock-host-service.mjs:162`, `scripts/device-relay-config.mjs:42` | `65_535` | Port limit | TCP port validation. | Protocol-defined. | Keep. |
| `scripts/codex-dock-host-service-env.mjs:83`, `scripts/device-relay-config.mjs:45-46`, `CodexDock/Configuration/DockHostConfiguration.swift:161` | `4500`, `4510` | Port guard | Reject app-facing raw app-server endpoint. | Good guard, but string drift risk. | Centralize raw/relay port names per language. |
| `CodexDock/Configuration/RelayBootstrapStore.swift:15`, `CodexDock/Features/Hosts/HostsView.swift:333`, `CodexDock/Features/Dock/CodexDockBootstrapView.swift:278`, `:283` | `"4510"` | UI default | Manual host/relay port fields. | Duplicates relay default. | Use Swift default relay port constant. |
| `scripts/dock-relay-bonjour.mjs:13`, `:21` | `63`, `255` chars | Protocol-ish cap | Bonjour service name/TXT record length. | Low. | Add comments naming DNS/TXT limits. |

## Test-Only Inventory

These are test waits/caps. They do not affect production behavior directly, but
they can cause flaky verification or hide slow-path bugs.

### Swift Tests

| Location | Value | Category | Controls | Recommendation |
|---|---:|---|---|---|
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:15`, `:38`, `:58` | `20s` | UI wait | Initial Dock/bootstrap/search field waits. | Put UI launch waits in `UITestTimeouts`. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:33` | `3s` | UI wait | Idle toggle value update. | Named short UI wait. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:42`, `:72` | `10s` | UI wait | Relay root/session header waits. | Named medium UI wait. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:64` | `25s` | UI wait | Wait for real relay-backed Dock row. | Env-tunable; include relay status in failure. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:71` | `15s` | UI wait | Session detail root wait. | Named navigation wait. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:79`, `:154`, `:168`, `:171` | `5s` | UI wait | Send button and fallback tab waits. | Centralize. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:107` | `0.2s` | Poll interval | First identifier poll. | Named UI poll interval. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:125`, `:209` | `0.25s` | Poll interval | Element/button scan loops. | Reuse one poll interval unless intentionally different. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:147`, `:162` | `2s` | UI wait | Fast tab lookup before fallback. | Name. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:45`, `:48` | `maxSwipes: 3` | Attempt cap | Scroll search for relay fields. | Name `relayFormMaxScrollAttempts`. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:176`, `:181` | `1s` | UI wait | Per-scroll element wait. | Name. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:197` | `30` buttons | Scan cap | Hittable-button row search. | Name; consider query count. |
| `CodexDockUITests/CodexDockAutomationSmokeTests.swift:243` | `0.1s` | Poll interval | String-value wait cadence. | Reuse UI poll interval. |
| `CodexDockTests/ThreadDetailStoreTestSupport.swift:394`, `:402` | `1s`, `10ms` | Test wait/poll | `waitForDetailStore`. | Central async test wait constants. |
| `CodexDockTests/DockConfigurationTests.swift:697`, `:706` | `1s`, `10ms` | Test wait/poll | `waitForRelayBootstrap`. | Central async test wait constants. |
| `CodexDockTests/AppLifecycleCoordinatorTests.swift:84` | `1s` | Test timeout | `valueWithinOneSecond`. | Share with other async helpers. |
| `CodexDockTests/AppServerClientTests.swift:2482`, `:2490` | `1s`, `10ms` | Test wait/poll | `waitUntil`. | Centralize. |
| `CodexDockTests/ThreadDetailStoreTests.swift:306`, `:394`; `CodexDockTests/ThreadDetailStoreLifecycleTests.swift:304`, `:425`; `CodexDockTests/DockConfigurationTests.swift:255`, `:302`, `:354` | `50ms` | Fixed sleeps | Negative/assertion settling. | Prefer predicate waits. |
| `CodexDockTests/AppServerClientTests.swift` many lines | `1s`, `50ms`, `100ms`, `200ms`, `250ms`, `300ms` | Test timeout/delay | Synthetic JSON-RPC timeout and reconnect tests. | Replace with named helpers and injectable clock where practical. |
| `CodexDockTests/AppServerClientTests.swift:1869`, `:1879`, `:1889`, `:1893`, `:1917`, `:1961` | `5s` | Real-host test timeout | Loopback/phone-reachable smoke calls. | Make real-host smoke timeout env-tunable. |
| `CodexDockTests/AppServerClientTests.swift:1921`, `:1931`, `:1935`, `:1939`, `:1973`, `:1985`, `:1996`, `:2005`, `:2017`, `:2027` | `10s` | Real-host test timeout | Real-host read/resume/archive/list calls. | Use one real-host timeout constant. |
| `CodexDockTests/ThreadDetailStoreTests.swift:43`, `:93`, `:94`, `:144`, `:145`; `CodexDockTests/ThreadDetailStoreLifecycleTests.swift:127`, `:128`, `:253`, `:254` | `limit: 100` | Page cap assertion | Expected detail turn page size. | Avoid duplicating hidden production value. |

### Node Tests

| Location | Value | Category | Controls | Recommendation |
|---|---:|---|---|---|
| `scripts/dock-relay-test-helpers.mjs:46`, `:61` | `1_000ms` | Test wait | JSON-RPC and relay-message waits. | Name `TEST_WAIT_TIMEOUT_MS`; tune once. |
| `scripts/dock-relay-test-helpers.mjs:102` | `1_000ms` | Interval | Keeps fake loopback app-server marker alive. | Fine or name if reused. |
| `scripts/dock-relay-test-helpers.mjs:124` | `500ms` | Test wait | Gives child process time to exit. | Named `PROCESS_CLOSE_GRACE_MS`. |
| `scripts/dock-relay-realtime-transcription.test.mjs:20`, `:30` | `1_000ms` | Test wait | Realtime connection/message waits. | Share helper timeout. |
| `scripts/dock-relay-phase5.test.mjs` many fixed sleeps | `10ms`, `20ms`, `25ms`, `100ms`, `500ms` | Test delay | Mock upstream ordering/close races. | Replace with predicate/event waits where possible. |
| `scripts/dock-relay-phase5.test.mjs:1776`, `:1786`, `:1863` | `10_000ms`, `<500ms`, `20ms` | Test timeout | Upstream close and timeout behavior. | Use named constants; avoid brittle wall-clock assertions. |
| `scripts/dock-relay.test.mjs:144-150`, `scripts/dock-relay-phase5.test.mjs:171` | `200 -> 100`, `0 -> 100` | Page cap test | `THREAD_LIST_MAX_LIMIT` behavior. | Import/export production constant if practical. |
| `scripts/dock-relay-realtime-transcription.test.mjs:128`, `:142`, `:313-315` | `24_000`, `64KiB`, `1MiB` | Audio cap test | Mirrors realtime defaults. | Import/export defaults if practical. |

## Consolidation Plan

1. Add a small timeout/policy layer instead of scattered literals.
   - Swift: `AppServerTimeoutPolicy`, `DockPaginationPolicy`,
     `VoiceTranscriptionLimits`, `AsyncTestTimeouts`, `UITestTimeouts`.
   - Node: `dock-relay-timeouts.mjs` or colocated exported constants for relay
     upstream, health, live status, summary cache, and service control.

2. Fix the `home`-class failure first.
   - Split relay upstream connect/request timeouts.
   - Make history `thread/list` request timeout longer or configurable.
   - Surface active timeout values in `/statusz`.
   - Consider incremental/bounded full-thread loading rather than blocking the
     whole Dock on every page.

3. Align layer budgets.
   - Relay upstream request timeout should not be shorter than the app-facing
     operation timeout unless that is explicit and visible.
   - Health timeout should not be treated as proof that real JSON-RPC work will
     complete.
   - Swift connect timeout, relay connect timeout, and real-host test timeouts
     should be named and intentionally different only when documented.

4. Reduce fixed sleeps in tests.
   - Replace negative-check sleeps with predicate/event waits.
   - Use one async test wait helper per language.
   - Add env timeout scaling for UI and real-host smoke tests.

5. Centralize protocol-ish constants.
   - Raw app-server port `4500`, relay port `4510`, max port `65535`.
   - Thread list cap `100`, turn page cap `100`.
   - PCM16 mono 24k sample rate, chunk byte caps.

## Immediate Root-Cause Note

The `home` timeout that triggered this audit is not caused by iOS simulator
network access. It is caused by this layered timing mismatch:

```text
Swift Dock list call waits up to 10s for a page
-> relay forwards thread/list to home raw app-server
-> relay upstream client waits only 5_000ms
-> one home raw app-server history page takes longer than 5_000ms
-> relay closes upstream and app sees:
   timed out waiting for thread/list from ws://127.0.0.1:4500/
```

That makes `scripts/dock-relay-json-rpc-client.mjs:3` the first timeout to fix
or make explicit.
