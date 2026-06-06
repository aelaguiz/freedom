@/Users/aelaguiz/.codex/RTK.md

# AGENTS.md (repo-wide)

Codex Dock client repo: Swift/iOS app plus a Node Dock relay. Start with
`README.md`; treat `Makefile` as the runnable command source of truth. If docs
disagree with `Makefile`, `project.yml`, `Package.swift`, `package.json`, or
the code, the runnable source wins.

`project.yml` is the XcodeGen source of truth for `CodexDock.xcodeproj`.
When target settings, schemes, bundle config, app permissions, Info.plist
properties, or assets wiring change, update `project.yml` first and regenerate:

```bash
rtk xcodegen generate --spec project.yml
```

## Mandatory User Communication Style

Use `$eli10` for every user-facing message in this repo. This is mandatory for
status updates, plans, reviews, explanations, recommendations, decisions, and
final replies; it applies alongside any other task-specific skill.

- Lead with the concrete answer in 1-3 short sentences.
- Use plain speech without dropping exact commands, paths, env vars, API names,
  ports, dates, or failure modes.
- Put root cause before symptom when explaining failures.
- Translate repo shorthand on first use.
- Use `$eli10` scan markers when they improve readability: `✅`, `⚠️`, `🧠`,
  `🔧`, `❌`, `➡️`, and `Net:`.
- Never put emoji markers inside code, commands, JSON, YAML, schemas, or copied
  machine output.
- Do not append unsolicited next steps. If the user only asked for an
  explanation, explain and stop.
- If the user asks for exact machine output, keep the output exact and use
  `$eli10` prose only around it.

## Commands

Swift package checks:

```bash
rtk swift test
rtk swift test --filter AppServerClientTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
```

Node relay checks:

```bash
rtk npm test
rtk npm run test:relay
rtk npm run test:docs
```

Generated Xcode project checks:

```bash
rtk xcodegen generate --spec project.yml
rtk make app SIM='iPhone 17'
rtk make app-test SIM='iPhone 17'
```

Local services and app launch:

```bash
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make relay-doctor
rtk make app-server-env
rtk make app SIM='iPhone 17'
rtk make sim-config-verify SIM='iPhone 17'
rtk make device-install DEVICE=<device-udid> DEVELOPMENT_TEAM=<team-id>
rtk make iphone-17-pro
rtk make iphone-14
rtk make device-install-all
rtk make device-config-verify DEVICE=<device-udid>
rtk make device-config-verify-all
```

Mobile builds and installs are Makefile-owned. Do not run raw `xcodebuild`,
`devicectl device install app`, `simctl install`, `flutter build`, or
`flutter install` as the normal workflow. Use or fix `rtk make app`,
`rtk make app-test`, `rtk make device-install`, and
`rtk make device-install-all`; raw platform commands are only failure
diagnostics for a make target.

Use the smallest relevant check first:

- Relay changes under `scripts/dock-relay*.mjs`: run `rtk npm run test:relay`.
- JSON-RPC, DTO, app-server client, or transcription-client changes: start with `rtk swift test --filter AppServerClientTests`.
- Dock, host registry, relay bootstrap, archive, local metadata, or host settings changes: start with `rtk swift test --filter DockStoreTests`.
- Thread detail, live events, composer, voice transcript handling, or request-card responses: start with `rtk swift test --filter ThreadDetailStoreTests`.
- App target, Info.plist, assets, project config, simulator launch, or installed UI behavior: use `rtk make app SIM='iPhone 17'` or `rtk make app-test SIM='iPhone 17'`. These targets regenerate the Xcode project and write detailed build logs under `.codex-dock/logs/`.
- When replacing an already-running simulator app, use `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`; otherwise the app target intentionally skips build/install/launch.
- Physical installed-app behavior: use `rtk make iphone-17-pro`, `rtk make iphone-14`, `rtk make device-install DEVICE=<device-udid>`, or `rtk make device-install-all`. These targets fresh-build with a timestamped `CURRENT_PROJECT_VERSION`, install, write the per-device relay config, verify the installed build number, and launch the app.
- If only `AGENTS.md` changed, read it back and check `rtk git status --short`; app tests are not needed.

If a check cannot run because Xcode, a simulator, a physical device, signing,
services, or env vars are missing, report the exact command skipped and the
exact blocker.

If physical Mobile MCP reports `WebDriverAgent is not running on device`, stop
retrying physical Mobile MCP for that task. Record that exact blocker and use
simulator/local proof only where it is valid. Amir will run the physical iPhone
manual test when the build is ready.

## Testing And Proof

`docs/TESTING.md` is the current testing guide. It explains which existing
commands to run, what counts as proof, and how to add Swift, relay, contract,
and over-time simulator tests.

`docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md` is the plan for the
future unified framework. It proposes `test-smoke`, `test-full`, and
`test-overtime`, but those targets do not exist until `Makefile` contains them.
Do not tell a user or another agent to run those proposed targets as current
commands.

Current completion-grade live-update proof is:

```bash
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
```

Fixture-backed simulator proof is regression proof, not real-data proof. For
user-visible app or relay behavior, also run the real relay-backed simulator
pass before claiming the app was tested against live data:

```bash
rtk make sim-ui-sync-proof SIM='iPhone 17'
```

For realtime Dock-card changes where rename/archive behavior matters, prefer
the focused real-data gate:

```bash
rtk make sim-ui-realdata-realtime-proof SIM='iPhone 17'
```

Real-data simulator proof means the installed simulator app connects to the
normal Dock relay on `:4510` and renders real Codex session rows. Do not
describe controlled fixtures, fixture rows, mocks, loopback-only WebSockets,
relay-only probes, status endpoints, or direct `dock/subscribe` counts as
"tested in the sim against live data". If the real-data simulator pass cannot
run, report the exact command and blocker before claiming the work is done.

Current full Node contract and relay proof is:

```bash
rtk npm run contract:check
rtk npm test
rtk npm run test:docs
rtk npm run test:host-service
```

Current diagnostic visibility proof is:

```bash
rtk make sim-ui-dump SIM='iPhone 17'
```

`sim-ui-dump` is not live-update acceptance proof by itself. Status endpoints,
logs, debug bundles, screenshots, mocks, fixture rows, SwiftUI preview rows,
Unix sockets, scripted transports, loopback-only WebSockets, raw
`ws://127.0.0.1:4500`, raw detail side-door routes, and
`projection/witness/read` are not app completion proof.

When adding an over-time simulator scenario today, update all current owners:
`scripts/dock-relay-controlled-simulator-fixture.mjs`,
`scripts/dock-relay-controlled-simulator-matrix.mjs`, `Makefile`, relevant
Node tests, and proof contracts if route or field evidence changes. The future
plan replaces that three-place scenario workflow with one scenario catalog.

When adding a root bug doc under `docs/bugs/`, adding or removing a controlled
simulator scenario, or discovering a new failure class in a plan, audit,
worklog, or debug note, update
`docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md` and run
`rtk npm run test:docs`. That guard checks that bug docs and controlled
scenario ids stay discoverable, and that fixture-only simulator scenarios are
called out as gaps instead of quietly falling out of completion proof.

## Service Path

`rtk make services` is the canonical local service entrypoint. It starts or
reuses one phone-facing service:

- Dock relay: `ws://<APP_SERVER_HOST>:4510`; `APP_SERVER_HOST` prefers the
  Mac's Tailscale MagicDNS name and falls back to the LAN address/hostname

Codex owns app-server and session runtimes. Dock does not start a special raw
Codex app-server on `:4500`. The app and phone connect only to the Dock relay on
`:4510`; the relay owns an `AppServerRegistry` that discovers Codex daemon
history, attachable loopback live owners, and private runtime diagnostics on the
Mac side.

Physical iPhone endpoint expectations:

- Amir's iPhone / iPhone 17 Pro
  (`CB9FFF0E-89AD-57B5-9C00-6552D814875E`) is on Tailscale. Configure Codex
  Dock on that device with `amir-m5.fairy-salmon.ts.net:4510` and
  `home.fairy-salmon.ts.net:4510`.
- iPhone / iPhone 14 (`0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`) is not on
  Tailscale. Configure Codex Dock on that device with `Amir-M5.local:4510` and
  `192.168.50.74:4510`.
- Keep these as separate per-device saved app configs. Do not collapse them
  into one baked-in or hard-coded host.
- Saved app configs should contain only a `hosts` list of `{host, port}` values.
  Relay identity stays Mac-side in relay status metadata such as
  `CODEX_DOCK_REAL_HOST_ID`; do not persist or launch phone-side
  `relayInstanceID` / `CODEX_DOCK_RELAY_INSTANCE_ID`.

Loopback WebSockets, Unix sockets, mocks, and scripted transports are local
development or relay-side discovery tools. They are not physical-phone
completion evidence. A real phone-path pass means the installed app connects to
the relay-backed host path on `:4510`, renders real `DockThreadCard` rows, and
shows offline/error UI when that same host path is unavailable. The old
Dock-owned raw `ws://127.0.0.1:4500` path is legacy/diagnostic-only and must not
be restored as a normal service path.

Prefer status checks during normal verification:

```bash
rtk make app-server-status
rtk make dock-relay-status
```

Stop and restart targets are intentional service disruption. Use
`rtk make app-server-stop`, `rtk make dock-relay-stop`, or restart targets only
when the task specifically calls for it.

## Logging And Diagnostics

The app uses Apple unified logging with subsystem
`com.aelaguiz.CodexDock`. The Dock relay writes structured JSON logs to
stderr at `.codex-dock/logs/dock-relay.err.log` when launched by `rtk make
services`.

Capture simulator app logs with:

```bash
rtk make sim-logs SIM='iPhone 17'
```

The raw simulator command is:

```bash
rtk sh -c 'udid="$(python3 scripts/sim.py resolve "iPhone 17")"; xcrun simctl spawn "$udid" log stream --style compact --level debug --predicate '\''subsystem == "com.aelaguiz.CodexDock"'\'''
```

Collect physical-device app logs with:

```bash
rtk make device-logs DEVICE=<device-udid>
```

The raw physical-device command is:

```bash
rtk xcrun log collect --device-udid <device-udid> --last 10m --predicate 'subsystem == "com.aelaguiz.CodexDock"' --output /tmp/codex-client/codex-dock-device.logarchive
```

If physical log collection fails with `log: Must be root to collect logs from
attached device`, record that exact blocker.

Capture relay logs with:

```bash
rtk make dock-relay-logs
```

The raw relay command is:

```bash
rtk tail -n 200 -f .codex-dock/logs/dock-relay.err.log
```

Never log `OPENAI_API_KEY`, bearer tokens, base64 audio, raw audio bytes,
prompt text, transcript text, or full JSON-RPC payloads. Swift app diagnostics
must use `DockLog`; relay diagnostics must use `scripts/dock-relay-logger.mjs`
instead of direct `console.error`.

## Secrets And Protocol

- `.env` is user-owned. Never overwrite, regenerate, truncate, normalize, or
  "refresh" `.env` unless Amir explicitly asks for `.env` to be changed. Service
  generated env belongs under `.codex-dock/`; read `.env` only as an input for
  values such as `OPENAI_API_KEY`.
- `OPENAI_API_KEY` and raw Codex app-server bearer tokens stay on the Mac side.
- Simulator and device launch must not pass OpenAI keys or raw app-server bearer tokens into the app.
- Bonjour TXT records must stay non-secret.
- Realtime transcription model and delay selection are relay-side only; do not accept phone-supplied provider config.
- WebSocket URLs must be `ws://` or `wss://`, include a host, and must not contain username/password credentials.
- Do not make the iPhone connect directly to the raw authenticated `:4500` app-server for the normal local path.
- Protocol method names and DTO shapes must move together across `scripts/dock-relay*.mjs`, `CodexDock/AppServer/**`, `CodexDock/Voice/**`, and `CodexDockTests/**`.
- The real-host archive round-trip is opt-in only. Do not run it casually; it is gated by `CODEX_DOCK_RUN_ARCHIVE_ROUND_TRIP=1`.

## Constants

Production Swift timing, page-size, port, and audio defaults live in
`CodexDock/Configuration/CodexDockConstants.swift`. Production relay MJS timing,
page-size, port, pool, and realtime audio defaults live in
`scripts/dock-relay-constants.mjs`.

Do not add hard-coded production timeouts, intervals, retry delays, page limits,
pool caps, ports, or byte caps outside those files unless the value is truly
local and documented. Test-only waits and fixture values can stay in tests.

## Context And Scratch Hygiene

Treat `docs/**`, dated plan/audit/worklog files, `.codex-dock/**`, `.build/**`,
`.swiftpm/**`, `node_modules/**`, logs, transcripts, and generated artifacts as
passive history by default. Do not browse, summarize, mine, or scan them
broadly unless the user names the exact path or file class, the current task
requires it, or a current command failure points there.

Scratch and support artifacts go outside the repo by default. Use
`/tmp/codex-client/<session-id>/...`; if no session id exists, use a UTC
timestamp slug such as `20260528T153000Z`. Put raw dumps, temporary notes, full
tool readbacks, and handoff files there.

Prefer `rg` and exact file reads for repo discovery. Do not create parallel
sources of truth; update the canonical file instead. In this repo, the usual
canonical files are `Makefile`, `project.yml`, `Package.swift`, `package.json`,
`README.md`, and the exact source or test file that owns the behavior.

Do not use preview rows as production evidence.

## Git And Local Work

You may be in a dirty worktree. Do not block on unrelated dirty or untracked
files; treat them as intentional local work.

- The Mac checkout at `/Users/aelaguiz/workspace/codex-client` is the
  authoritative repo. The `home` server checkout at
  `/home/aelaguiz/workspace/codex-client` is only a pull-and-run deployment
  copy; do not author, preserve, stash, merge, or commit home-only dirty repo
  work there.
- When refreshing `home`, first make the Mac branch clean and pushed, then
  update `home` from that pushed branch with `git fetch` and `git pull
  --ff-only`. If home-only dirt blocks the pull, report the exact dirty paths
  and the cleanup command before discarding it; do not treat that dirt as work
  to save.
- Do not create worktrees unless explicitly asked.
- Never use `git clean`, `git reset`, `git restore`, or `git checkout -- <path>` unless Amir explicitly asks.
- If Amir asks for a destructive git command, state the exact command and affected paths first.
- Do not commit, stage, push, or shape PRs unless explicitly asked.
- If asked to stage files, use explicit paths. Never use `git add .` or `git add -A`.
- Git is the archive. Delete or replace dead material instead of leaving `old`, `legacy`, `deprecated`, backup, or copy files beside the live path.

## Docs Map

- `README.md`: product orientation, app-server modes, relay runbook, simulator and device flows.
- `docs/TESTING.md`: current testing commands, proof rules, and add-a-test guidance.
- `docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`: docs-mined bug, scenario, and failure-class coverage ledger.
- `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`: plan for unified smoke, full, and over-time test tiers.
- `Makefile`: canonical service, simulator, device, and app commands.
- `project.yml`: XcodeGen target, settings, permissions, scheme, and app metadata source.
- `Package.swift`: SwiftPM package and test target source.
- `package.json`: Node relay scripts and dependencies.

## Writing And Replies

- `$eli10` is the required writing style. Make the whole answer readable on
  first pass, not just one summary paragraph.
- Write for a human reader first.
- Use `$eli10` style for every user-facing reply when the skill is available:
  lead with the concrete answer, explain jargon in plain English, preserve exact
  paths and commands, and use scan markers only when they make the answer easier
  to read.
- Use plain English. Do not make the reader decode house jargon, compressed
  labels, or pseudo-technical wording.
- Lead with the concrete thing in 1-3 sentences: what changed, what to run, what
  happens next, or what the blocker is.
- If the real answer is a path, command, setting, or skill name, name that exact
  thing first.
- Prefer simple action language over workflow jargon. Say `I installed it on
  this machine`, not `I completed the host-local cutover`.
- Say `Only AGENTS.md changed, so I didn't run tests.` when that is the truth.
