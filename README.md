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
ws://<amir-m5-lan-or-tailscale-ip>:4510
```

For the personal LAN/Tailscale path, the relay accepts the iPhone without a
client bearer token. The relay advertises `_codexdock._tcp` with non-secret
Bonjour metadata so the app can find it after a normal home-screen launch.

## Phase 1 Rule

Mocks, scripted transports, Unix sockets, and loopback-only WebSockets do not
complete the physical phone path. The current phone path is the relay at
`ws://192.168.50.117:4510`, with no iPhone-side bearer token.

## Canonical Service Start

Use this target for local Dock development instead of manually starting and
stopping host services:

```sh
rtk make services
```

It starts/reuses two real services and leaves them running:

- Raw Codex app-server on `ws://192.168.50.117:4500`
- Dock relay on `ws://192.168.50.117:4510`

The raw app-server provides stored history. The relay is the app endpoint. It
discovers the real loopback Codex app-server processes on `Amir-M5`, calls
supported Codex methods on them, and merges live loaded rows over stored
history. This is required because the active Codex sessions are usually attached
to private `ws://127.0.0.1:<port>` app-servers, and an iPhone cannot reach the
Mac's loopback addresses directly.

The relay also owns OpenAI transcription. Keep `OPENAI_API_KEY` in the Mac
environment or repo `.env`; the app never receives it. The default transcription
model is `gpt-4o-transcribe`, with an optional Mac-side
`CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL` override.

The Dock sorts rows by newest activity first. Status only breaks ties. The Dock
also refreshes itself every five seconds while the view is open, with
pull-to-refresh still available for manual checks.

The service targets install per-repo LaunchAgents with runtime files under
`.codex-dock/`:

```text
.codex-dock/com.aelaguiz.codex-dock.app-server.plist
.codex-dock/com.aelaguiz.codex-dock.relay.plist
.codex-dock/app-server.pid
.codex-dock/app-server.token
.codex-dock/app-server.log
.codex-dock/app-server.err.log
.codex-dock/dock-relay.pid
.codex-dock/dock-relay.log
.codex-dock/dock-relay.err.log
```

The default app endpoint is:

```text
ws://192.168.50.117:4510
```

Check services without restarting:

```sh
rtk make app-server-status
rtk make dock-relay-status
```

Print the environment for raw dev smoke tests:

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

## Simulator Commands

Build, install, and launch the app in a specific simulator:

```sh
rtk make app SIM='iPhone 17'
```

Or use a simulator ID:

```sh
rtk make app SIM=DEF1631B-7125-43C6-BFA3-4423BF103C91
```

That command starts/reuses the persistent services, boots the simulator,
builds the app, installs it, and launches it with the real `Amir-M5`
relay URL. It does not pass an OpenAI key or app-server bearer token into the
app.

Start all local services the app currently needs:

```sh
rtk make services
```

Today that means the authenticated raw LAN app-server plus the no-client-auth
Dock relay. If another local service becomes required later, add it behind this
target so `rtk make app SIM=...` keeps doing the whole setup idempotently.

The service targets also rewrite `.env` with the current connection settings:

```text
CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510
CODEX_DOCK_REAL_HOST_ID=Amir-M5
CODEX_DOCK_REAL_HOST_NAME=Amir-M5
CODEX_DOCK_OPENAI_TRANSCRIPTION_MODEL=gpt-4o-transcribe
OPENAI_API_KEY=<kept on Mac when configured>
```

List available simulators:

```sh
rtk make sims
```

Boot and open one simulator:

```sh
rtk make sim SIM='iPhone 17'
```

If a name matches more than one simulator, use the ID from `rtk make sims`:

```sh
rtk make sim SIM=DEF1631B-7125-43C6-BFA3-4423BF103C91
```

## iOS App Runbook

Phase 3 adds a real iOS app target generated by XcodeGen.

### Physical iPhone

Start or refresh the Mac services:

```sh
rtk make services
```

Install the app once on a physical iPhone:

```sh
rtk make device-install
```

By default this resolves the paired iPhone 14 and signs with team
`R6B8KXF3QW`, matching the working PS Mobile automatic-signing setup on this
machine. Override only when you intentionally want a different phone or team:

```sh
rtk make devices
rtk make device-install DEVICE=<device-udid>
rtk make device-install DEVICE_NAME='iPhone 17 Pro'
rtk make device-install DEVELOPMENT_TEAM=<team-id>
```

Do not use team `Q2V42N8S7R` for this app on this machine, and do not force a
manual provisioning profile such as `iOS Team Provisioning Profile: *`. The
working path is automatic signing with `R6B8KXF3QW`. The install target also
passes `-allowProvisioningDeviceRegistration`, so a second paired iPhone can be
registered into the development profile when Xcode is allowed to update
provisioning.

Then open Codex Dock from the iPhone home screen. The app discovers the Mac
relay over Bonjour, connects with no phone-side bearer token, loads sessions,
and sends dictation audio to the relay for transcription.

The physical install target builds for `iphoneos` and installs the app. It does
not launch the app, pass simulator env, or pass any OpenAI/Codex token to the
phone.

If XcodeGen is missing, install it:

```sh
rtk brew install xcodegen
```

Generate the project:

```sh
rtk xcodegen generate --spec project.yml
```

Build the app for the `iPhone 17` simulator:

```sh
rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Run unit tests through SwiftPM:

```sh
rtk swift test
```

Run generated-project tests on the `iPhone 17` simulator:

```sh
rtk xcodebuild test -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17'
```

Prefer `rtk make app SIM='iPhone 17'` for simulator launch. If you need to
launch an already-installed simulator build manually, point it at the relay by
passing non-secret simulator environment variables with the `SIMCTL_CHILD_`
prefix:

```sh
rtk xcrun simctl install <iphone-17-device-id> /path/to/CodexDockApp.app
rtk env SIMCTL_CHILD_CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 SIMCTL_CHILD_CODEX_DOCK_REAL_HOST_ID=Amir-M5 SIMCTL_CHILD_CODEX_DOCK_REAL_HOST_NAME=Amir-M5 xcrun simctl launch --terminate-running-process <iphone-17-device-id> com.aelaguiz.CodexDockApp
```

Do not use preview rows as production evidence. A Phase 3 pass means the
installed app connects to the real relay-backed host path, renders real
`SessionSummary` rows, and shows offline/error UI when that same host path is
unavailable.
