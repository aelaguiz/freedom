# Codex Dock Client

This repo is the Swift client for the Codex Dock MVP.

## App-Server Runbook

There are two different app-server modes we need to keep separate.

### 1. Normal daemon mode

The Codex daemon is the normal local background service:

```sh
rtk codex app-server daemon restart
rtk codex app-server daemon version
```

Today, this daemon always starts its managed app-server on a Unix socket:

```sh
app-server --remote-control --listen unix://
```

That socket is:

```text
/Users/aelaguiz/.codex/app-server-control/app-server-control.sock
```

This is fine for local Codex tooling, but it is not reachable from an iPhone.

### 2. Loopback WebSocket mode

For local WebSocket development, start a direct app-server process in loopback
mode:

```sh
rtk codex app-server --listen ws://127.0.0.1:4500
```

Then the Swift test can point at:

```sh
rtk env CODEX_DOCK_LOOPBACK_APP_SERVER_WS=ws://127.0.0.1:4500 swift test
```

Important: loopback is only a local development step. It is not Phase 1
completion evidence, because an iPhone cannot use the Mac's `127.0.0.1`. The
phone-reachable acceptance test intentionally rejects loopback endpoints.

After a loopback smoke run, stop the direct `codex app-server --listen
ws://127.0.0.1:4500` process and restart the normal daemon:

```sh
rtk codex app-server daemon restart
```

That restart restores the daemon's normal Unix-socket service. It does not move
the daemon itself into loopback WebSocket mode; current Codex daemon startup
does not expose that setting.

### 3. Phone-reachable relay mode

The raw Codex app-server still runs with bearer auth on the Mac. The iPhone does
not connect to that raw server directly. It connects to the Dock relay on the
Mac, and the relay uses the raw app-server token behind the scenes.

```sh
rtk make services
```

The phone-facing endpoint is:

```text
<amir-m5-lan-or-tailscale-host>:4510
```

For the personal LAN/Tailscale path, the relay accepts the iPhone without a
client bearer token. The relay advertises `_codexdock._tcp` with non-secret
Bonjour metadata so the app can find it after a normal home-screen launch.

## Physical Phone Rule

Mocks, scripted transports, Unix sockets, and loopback-only WebSockets do not
complete the physical phone path. The current phone path is the Dock relay on
`:4510`, with no iPhone-side bearer token. The iPhone 17 Pro uses
`ws://amir-m5.fairy-salmon.ts.net:4510` and
`ws://home.fairy-salmon.ts.net:4510`; the iPhone 14 uses
`ws://Amir-M5.local:4510` and `ws://192.168.50.74:4510`.

Physical-device proof is Makefile-owned. Use `rtk make device-install` and
`rtk make device-config-verify`; if a phone is actively in use, unavailable, or
blocked by device tooling, record the exact skipped command and exact blocker.
Simulator, local relay, service-status, and generated-artifact proof only prove
the parts they actually exercise.

## Canonical Service Start

Use this target for local Dock development instead of manually starting and
stopping host services:

```sh
rtk make services
```

It starts/reuses two real services and leaves them running:

- Raw Codex app-server on loopback `ws://127.0.0.1:4500`
- Dock relay on `ws://<APP_SERVER_HOST>:4510`

The raw app-server provides stored history. The relay is the app endpoint. Dock
Home subscribes to relay-owned `dock/*` methods: `dock/subscribe` returns the
first normalized snapshot, `dock/update` pushes deltas and heartbeats, and
`dock/resync` returns a replacement snapshot if the client detects a sequence
gap. The relay materializes app-server thread projections in SQLite at
`.codex-dock/relay-state.sqlite`, serves Dock Home from that state store, and
keeps stale rows visible when a source refresh fails. Raw `thread/list` remains
available for thread detail support, archive command diagnostics, and host
settings diagnostics; it is no longer the Dock or Archive list contract.

Row text has two separate meanings. Raw history `preview` is preserved as the
app-server's stored preview and may be the opening message. Dock overview rows
use bounded relay state fields from the app-server projection; row summary
work is not allowed to read turns, block subscribe/list, or reorder the
dashboard response.

The relay also owns OpenAI Realtime transcription. Keep `OPENAI_API_KEY` in the
Mac environment or repo `.env`; the app never receives it. The default Realtime
transcription model is `gpt-realtime-whisper`, with optional Mac-side
`CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL` and
`CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY` overrides.

The Dock filters loaded thread cards locally. It opens to `Newest`: one flat
newest-first list across configured hosts. Rows carry their own short host
name, repository or working directory, branch, status, last activity, local
label, and latest summary. `Host` and `Branch` are Dock lenses, not app-level
tabs or a separate sort picker; both preserve newest-first ordering inside
their groups. `Filters` opens one shared filter surface for host, branch,
canonical Dock status, repository or working directory, source, idle
visibility, and the fixed `Newest activity` sort. Search is full-width and
matches session title, label, repository or working directory, branch, summary,
status, host display name, host id, source, and thread id. Codex runtime
`notLoaded` is normalized by the relay to Dock `dormant`; Dock Home does not
spend row-badge space on that background state.

The app has one root connectivity indicator. It appears above Dock and opens
the `System Health` sheet for relay and route diagnostics. Archive recovery,
cleanup, and relay host editing live in the Dock `More` menu as `Archived
Threads`, `Archive Cleanup`, and `Relay Settings` task sheets, not app-level
tabs. The labels are `Unconfigured`,
`Checking`, `Online`, `Partial`, `Reconnecting`, `Backgrounded`, `Resuming`,
`Stale`, `Offline`, `Error`, and `Config error`. A nil host bearer token is
normal for the personal physical-phone relay path; it is not shown as missing
credentials.

Live Session detail connections reconnect automatically when recovery is safe.
After reconnect, the app re-runs the full detail rehydrate path:
`thread/read includeTurns:false`, paged `thread/turns/list` until `nextCursor`
is exhausted, and `thread/resume excludeTurns:true`. The turn-list page size is
a transport guard, not a total message cap. Failed user sends are not silently
replayed. If the relay loses its upstream session, it either re-resumes upstream
or closes the phone WebSocket so Swift can mark the detail stale or reconnect.

When iOS backgrounds the app, root refresh and reconnect attempts pause instead
of spending retry budget. Open details keep visible events, request action
state, and draft text but are no longer labeled fresh. Active voice capture is
cancelled without auto-submitting. On foreground resume, Dock and Archive
refresh from root, open details rehydrate through the same full detail path, and
the indicator moves through `Backgrounded` / `Resuming` / `Reconnecting` as
appropriate.

The service targets install per-repo launchd files on macOS and systemd user
files on Linux, with runtime files under `.codex-dock/`:

```text
.codex-dock/services/com.aelaguiz.codex-dock.app-server.plist
.codex-dock/services/com.aelaguiz.codex-dock.relay.plist
.codex-dock/services/codex-dock-app-server.service
.codex-dock/services/codex-dock-relay.service
.codex-dock/app-server.token
.codex-dock/service.env
.codex-dock/host.env
.codex-dock/logs/app-server.log
.codex-dock/logs/app-server.err.log
.codex-dock/logs/dock-relay.log
.codex-dock/logs/dock-relay.err.log
```

The default app endpoint is:

```text
ws://amir-m5.fairy-salmon.ts.net:4510
```

Check services without restarting:

```sh
rtk make app-server-status
rtk make dock-relay-status
```

Process health and app-path health are separate. `/readyz` only means the relay
process can answer HTTP. The app path is healthy only when the relevant route
is healthy in `/statusz`, `/routesz`, or the debug bundle.

Route-health diagnostics:

```sh
rtk make relay-doctor
rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
rtk make relay-debug-bundle
```

The relay stores bounded route evidence under `.codex-dock/observability/` and
serves `/routesz`, `/tracesz/recent`, `/tracesz/<operationID>`, `/selftestz`,
and `/bundlez`. Automatic probes only use auto-probe-safe routes; archive,
turn, and transcription routes are passive evidence from real app traffic.

Print the app-safe host config plus raw dev smoke helpers:

```sh
rtk make app-server-env
```

Only stop services intentionally:

```sh
rtk make app-server-stop
rtk make dock-relay-stop
```

Normal verification should use `rtk make services`, `rtk make
app-server-status`, or `rtk make dock-relay-status`; it should not stop the
services.

## Cross-Platform Host Services

The same host-service wrapper is used on macOS and Linux. `rtk make services`
installs, starts, and waits for the raw app-server plus Dock relay bundle. The
relay is always the app-facing endpoint; the raw app-server stays host-side and
loopback by default.

Mac local service:

```sh
rtk make services
rtk make app-server-status
rtk make dock-relay-status
rtk make host-service-doctor
rtk make relay-doctor
```

Linux `home` service over Tailscale:

```sh
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make services HOST_SERVICE_PLATFORM=linux CODEX_BIN=/home/aelaguiz/.local/bin/codex NODE_BIN=/home/aelaguiz/.local/node-v24.16.0-linux-x64/bin/node CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home APP_SERVER_HOST=100.66.11.7 DOCK_RELAY_WS=ws://100.66.11.7:4510 APP_SERVER_LISTEN=ws://127.0.0.1:4500 DOCK_RELAY_HISTORY_WS=ws://127.0.0.1:4500'
```

Check `home` after start with the same overrides:

```sh
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-status HOST_SERVICE_PLATFORM=linux CODEX_BIN=/home/aelaguiz/.local/bin/codex NODE_BIN=/home/aelaguiz/.local/node-v24.16.0-linux-x64/bin/node CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home APP_SERVER_HOST=100.66.11.7 DOCK_RELAY_WS=ws://100.66.11.7:4510 APP_SERVER_LISTEN=ws://127.0.0.1:4500 DOCK_RELAY_HISTORY_WS=ws://127.0.0.1:4500'
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-doctor HOST_SERVICE_PLATFORM=linux CODEX_BIN=/home/aelaguiz/.local/bin/codex NODE_BIN=/home/aelaguiz/.local/node-v24.16.0-linux-x64/bin/node CODEX_DOCK_REAL_HOST_ID=home CODEX_DOCK_REAL_HOST_NAME=Home APP_SERVER_HOST=100.66.11.7 DOCK_RELAY_WS=ws://100.66.11.7:4510 APP_SERVER_LISTEN=ws://127.0.0.1:4500 DOCK_RELAY_HISTORY_WS=ws://127.0.0.1:4500'
```

From the Mac, the app-facing `home` relay should answer:

```sh
curl -fsS --max-time 5 http://100.66.11.7:4510/readyz
curl -fsS --max-time 5 http://100.66.11.7:4510/statusz
curl -fsS --max-time 5 http://100.66.11.7:4510/routesz
```

Use `readyz` only as process proof. Use `statusz` or `routesz` for route proof;
an app-critical route failure should make `relay-doctor` report a problem even
when `readyz` succeeds.

`home` Realtime transcription is not claimed unless `OPENAI_API_KEY` is
configured on `home`. The current safe state is that the `home` relay reports
transcription `enabled: false` and `keyPresent: false`.

## Diagnostics Commands

The iOS app writes Apple unified logs under subsystem
`com.aelaguiz.CodexDock`. The Dock relay writes structured JSON lines to
stderr, which the service target stores at
`.codex-dock/logs/dock-relay.err.log`.

The app also writes app-owned route evidence under
`Library/Application Support/CodexDock/Diagnostics/`. This is the preferred
physical-device artifact path when Apple unified log collection is blocked.

Fetch a relay debug bundle:

```sh
rtk make relay-debug-bundle
```

Compare configured relay hosts:

```sh
rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
```

Copy app-owned diagnostics from a simulator:

```sh
rtk make sim-debug-bundle SIM='iPhone 14'
```

Copy app-owned diagnostics from a physical iPhone:

```sh
rtk make device-debug-bundle DEVICE=<device-udid>
```

Stream simulator logs:

```sh
rtk make sim-logs SIM='iPhone 17'
```

Collect physical device logs:

```sh
rtk make device-logs DEVICE=<device-udid>
```

On some Xcode installs, physical log collection requires root. If this prints
`log: Must be root to collect logs from attached device`, rerun the raw
`xcrun log collect` command with root privileges or treat that as the log
collection blocker.

Tail Dock relay logs:

```sh
rtk make dock-relay-logs
```

## Simulator Commands

Start the simulator app path for a specific simulator:

```sh
rtk make app SIM='iPhone 17'
```

Or use a simulator ID:

```sh
rtk make app SIM=DEF1631B-7125-43C6-BFA3-4423BF103C91
```

That command starts/reuses the persistent services and boots the simulator in
the background. If `com.aelaguiz.CodexDockApp` is already running on that
simulator, it leaves the app alone and skips build/install/launch so Simulator
does not keep stealing focus.

Force a replacement build and launch only when you actually need it:

```sh
FORCE_LAUNCH=1 rtk make app SIM=DEF1631B-7125-43C6-BFA3-4423BF103C91
```

When it does launch, it uses generated app config from `.codex-dock/host.env`.
It does not pass an OpenAI key or app-server bearer token into the app.

Run the generated-project app tests through the same Makefile-owned path:

```sh
rtk make app-test SIM='iPhone 17'
```

Verify the generated app-safe relay config used by simulator launches:

```sh
rtk make sim-config-verify SIM='iPhone 17'
```

When these targets build, they stamp debug builds with `APP_BUILD_NUMBER` so
stale simulator artifacts fail verification instead of silently launching.

Start all local services the app currently needs:

```sh
rtk make services
```

Today that means the authenticated raw loopback app-server plus the
no-client-auth Dock relay. If another local service becomes required later, add
it behind this target so `rtk make app SIM=...` keeps doing the whole setup
idempotently.

The service targets write host-side settings to `.codex-dock/service.env`,
write app-safe settings to `.codex-dock/host.env`, and leave the user-owned
`.env` untouched. They may read `OPENAI_API_KEY` from the shell or `.env`, but
they must not rewrite `.env`.

`.codex-dock/service.env` may contain host-side secrets and relay provider
settings:

```text
CODEX_DOCK_HOSTS=amir-m5.fairy-salmon.ts.net:4510
CODEX_DOCK_REAL_HOST_ID=Amir-M5
CODEX_DOCK_REAL_HOST_NAME=Amir-M5
CODEX_DOCK_OPENAI_REALTIME_TRANSCRIPTION_MODEL=gpt-realtime-whisper
CODEX_DOCK_REALTIME_TRANSCRIPTION_DELAY=low
OPENAI_API_KEY=<kept on Mac when configured>
```

`.codex-dock/host.env` is the generated app config. It must stay non-secret:

```text
CODEX_DOCK_HOSTS=amir-m5.fairy-salmon.ts.net:4510
```

List available simulators:

```sh
rtk make sims
```

Boot and open one simulator explicitly:

```sh
rtk make sim SIM='iPhone 17'
```

If a name matches more than one simulator, use the ID from `rtk make sims`:

```sh
rtk make sim SIM=DEF1631B-7125-43C6-BFA3-4423BF103C91
```

## iOS App Runbook

The iOS app target is generated by XcodeGen from `project.yml`.

### Physical iPhone

This section is for physical-device install and readback through the Makefile.
Do not touch a phone Amir says he is actively using; record that exact reason
beside the skipped command.

Start or refresh the Mac services:

```sh
rtk make services
```

Install the app once on a physical iPhone:

```sh
rtk make device-install
```

By default this resolves the paired iPhone 14, signs with team `R6B8KXF3QW`,
fresh-builds the app, installs it, writes the device's saved relay host list,
verifies the installed build number, and launches Codex Dock. Override only
when you intentionally want a different phone or team:

```sh
rtk make devices
rtk make device-install DEVICE=<device-udid>
rtk make device-install DEVICE_NAME='iPhone 17 Pro'
rtk make device-install DEVELOPMENT_TEAM=<team-id>
```

Install/configure both current physical phones:

```sh
rtk make device-install-all
```

Convenience install shortcuts:

```sh
rtk make iphone-17-pro
rtk make iphone-14
```

The iPhone 17 Pro (`CB9FFF0E-89AD-57B5-9C00-6552D814875E`) is configured with
`amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`. The
iPhone 14 (`0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`) is configured with
`Amir-M5.local:4510` and `192.168.50.74:4510`. Verify the saved host list without
reinstalling:

```sh
rtk make device-config-verify DEVICE=<device-udid>
rtk make device-config-verify-all
```

Do not use team `Q2V42N8S7R` for this app on this machine, and do not force a
manual provisioning profile such as `iOS Team Provisioning Profile: *`. The
working path is automatic signing with `R6B8KXF3QW`. The install target also
passes `-allowProvisioningDeviceRegistration`, so a second paired iPhone can be
registered into the development profile when Xcode is allowed to update
provisioning.

The install target launches Codex Dock after writing the saved host list. If the
app is closed later, open it from the iPhone home screen; it connects with no
phone-side bearer token, loads relay-backed thread cards, and sends dictation
audio to the relay for transcription.

When physical testing resumes, manual physical iPhone 14 testing should cover
the actual composer path:

- hold `Hold to dictate`, speak, and confirm text appears before release;
- release, edit the final draft, and verify `Send` is still manual;
- tap `Start dictation`, speak, tap `Stop dictation`, and verify the final
  draft remains editable;
- type a prefix before dictation and confirm it survives final transcription;
- interrupt dictation by navigating away, backgrounding, or using another real
  interruption path and confirm no turn submits and the draft is recoverable;
- check VoiceOver labels/hints, tappable controls, and large Dynamic Type
  layout.

Record new evidence in the relevant plan log or in the deferred physical QA
checklist in `docs/CODEX_DOCK_CROSS_PLAN_IMPLEMENTATION_DOCK_2026-05-28.md`.

The physical install target builds for `iphoneos`, installs the app, writes the
saved relay host list, verifies the installed build number, and launches the
app. It does not pass simulator env, OpenAI keys, or raw Codex tokens to the
phone.

If XcodeGen is missing, install it:

```sh
rtk brew install xcodegen
```

Generate the project:

```sh
rtk xcodegen generate --spec project.yml
```

Build, install, and launch the app for the `iPhone 17` simulator:

```sh
rtk make app SIM='iPhone 17'
```

Run unit tests through SwiftPM:

```sh
rtk swift test
```

Run generated-project tests on the `iPhone 17` simulator:

```sh
rtk make app-test SIM='iPhone 17'
```

The generated-project test target includes UI automation smoke tests. Those
tests use the accessibility tree as the primary proof: screens, controls, rows,
visible state banners, and visible error states expose stable
`codexdock.*` automation identifiers plus accessibility values where the state
matters. Screenshots are useful triage evidence, but they are not the selector
strategy for this workflow.

By default the simulator and UI tests launch the app against the current
two-host relay list: `amir-m5.fairy-salmon.ts.net:4510` and
`home.fairy-salmon.ts.net:4510`. `CODEX_DOCK_HOSTS` is the complete host list
for that launch, so saved or discovered hosts do not change the test surface.
To use a different relay endpoint, pass a comma-separated host list:

```sh
CODEX_DOCK_UI_TEST_HOSTS='Amir-M5.local:4510' rtk make app-test SIM='iPhone 17'
```

Builds and installs are Makefile-owned. Do not use raw Xcode, CoreDevice,
simulator install, or Flutter build/install commands as the normal workflow;
add or fix a make target instead. Raw platform commands are for diagnosing a
failed make target.

Do not use fixture or SwiftUI preview rows as production evidence. A physical
phone pass means the installed app connects to the real relay-backed host path,
renders real `DockThreadCard` rows, and shows offline/error UI when that same
host path is unavailable. While physical testing is deferred, the agent-side
stand-in is simulator plus local/real-relay/service-status proof, with the
physical checks recorded for Amir.
