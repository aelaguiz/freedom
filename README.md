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

### 3. Phone-reachable mode

For the real Phase 1 proof, the app-server must listen on an address the phone
can reach, such as LAN or Tailscale:

```sh
rtk codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file /absolute/path/to/token
```

The phone connects to the host's real IP, not `0.0.0.0`:

```text
ws://<amir-m5-lan-or-tailscale-ip>:4500
```

Non-loopback WebSocket listeners require Codex websocket auth. The Swift client
sends `Authorization: Bearer <token>` when it is configured with a token.

## Phase 1 Rule

Mocks, scripted transports, Unix sockets, and loopback-only WebSockets do not
complete Phase 1. Phase 1 completed on 2026-05-28 after the `iPhone 17`
simulator path connected to a real Codex app-server on `Amir-M5` at
`ws://192.168.50.117:4500` with websocket auth.

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

Print the environment needed by Swift tests or app launch commands:

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
relay environment.

Start all local services the app currently needs:

```sh
rtk make services
```

Today that means the authenticated raw LAN app-server plus the authenticated
Dock relay. If another local service becomes required later, add it behind this
target so `rtk make app SIM=...` keeps doing the whole setup idempotently.

The service targets also rewrite `.env` with the current connection settings:

```text
CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510
CODEX_DOCK_APP_SERVER_BEARER_TOKEN_FILE=/Users/aelaguiz/workspace/codex-client/.codex-dock/app-server.token
CODEX_DOCK_REAL_HOST_ID=Amir-M5
CODEX_DOCK_REAL_HOST_NAME=Amir-M5
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

Prefer `rtk make app SIM='iPhone 17'` for launch. If you need to launch an
already-installed build manually, point it at the relay by passing simulator
environment variables with the `SIMCTL_CHILD_` prefix:

```sh
rtk xcrun simctl install <iphone-17-device-id> /path/to/CodexDockApp.app
rtk env SIMCTL_CHILD_CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS=ws://192.168.50.117:4510 SIMCTL_CHILD_CODEX_DOCK_APP_SERVER_BEARER_TOKEN=<token> SIMCTL_CHILD_CODEX_DOCK_REAL_HOST_ID=Amir-M5 SIMCTL_CHILD_CODEX_DOCK_REAL_HOST_NAME=Amir-M5 xcrun simctl launch --terminate-running-process <iphone-17-device-id> com.aelaguiz.CodexDockApp
```

Do not use preview rows as production evidence. A Phase 3 pass means the
installed app connects to the real relay-backed host path, renders real
`SessionSummary` rows, and shows offline/error UI when that same host path is
unavailable.
