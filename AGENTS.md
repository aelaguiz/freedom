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

## Communication

Use `$eli10` for every user-facing reply in this repo.

- Lead with the concrete answer in 1-3 short sentences.
- Preserve exact commands, paths, env vars, API names, ports, dates, and failure modes.
- Translate repo shorthand the first time it matters.
- Avoid workflow jargon when a plain word works.
- Do not append unsolicited next steps when the user only asked for an explanation.
- If the user asks for exact machine output, keep the output exact and use plain prose around it.

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
- Physical installed-app behavior: use `rtk make iphone-17-pro`, `rtk make iphone-14`, `rtk make device-install DEVICE=<device-udid>`, or `rtk make device-install-all`. These targets fresh-build with a timestamped `CURRENT_PROJECT_VERSION`, install, write the per-device relay config, verify the installed build number, and launch the app.
- If only `AGENTS.md` changed, read it back and check `rtk git status --short`; app tests are not needed.

If a check cannot run because Xcode, a simulator, a physical device, signing,
services, or env vars are missing, report the exact command skipped and the
exact blocker.

If physical Mobile MCP reports `WebDriverAgent is not running on device`, stop
retrying physical Mobile MCP for that task. Record that exact blocker and use
simulator/local proof only where it is valid. Amir will run the physical iPhone
manual test when the build is ready.

## Service Path

`rtk make services` is the canonical local service entrypoint. It starts or
reuses:

- Raw Codex app-server: `ws://127.0.0.1:4500`
- Dock relay: `ws://<APP_SERVER_HOST>:4510`; `APP_SERVER_HOST` prefers the
  Mac's Tailscale MagicDNS name and falls back to the LAN address/hostname

The app and phone normally connect to the Dock relay on `:4510`, not directly
to the raw authenticated app-server on `:4500`. The relay owns the raw bearer
token and forwards to Mac-side app-server/session owners.

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

Loopback WebSockets such as `ws://127.0.0.1:4500`, Unix sockets, mocks, and
scripted transports are local development tools. They are not physical-phone
completion evidence. A real phone-path pass means the installed app connects to
the relay-backed host path, renders real `SessionSummary` rows, and shows
offline/error UI when that same host path is unavailable.

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

- Do not create worktrees unless explicitly asked.
- Never use `git clean`, `git reset`, `git restore`, or `git checkout -- <path>` unless Amir explicitly asks.
- If Amir asks for a destructive git command, state the exact command and affected paths first.
- Do not commit, stage, push, or shape PRs unless explicitly asked.
- If asked to stage files, use explicit paths. Never use `git add .` or `git add -A`.
- Git is the archive. Delete or replace dead material instead of leaving `old`, `legacy`, `deprecated`, backup, or copy files beside the live path.

## Docs Map

- `README.md`: product orientation, app-server modes, relay runbook, simulator and device flows.
- `Makefile`: canonical service, simulator, device, and app commands.
- `project.yml`: XcodeGen target, settings, permissions, scheme, and app metadata source.
- `Package.swift`: SwiftPM package and test target source.
- `package.json`: Node relay scripts and dependencies.
