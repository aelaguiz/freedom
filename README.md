# Codex Dock Client

This repo is the Swift client for the Codex Dock MVP.

## App-Server Runbook

There are two different app-server modes we need to keep separate.

### 1. Normal daemon mode

The Codex daemon is the normal local background service:

```sh
codex app-server daemon restart
codex app-server daemon version
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
codex app-server --listen ws://127.0.0.1:4500
```

Then the Swift test can point at:

```sh
CODEX_DOCK_LOOPBACK_APP_SERVER_WS=ws://127.0.0.1:4500 swift test
```

Important: loopback is only a local development step. It is not Phase 1
completion evidence, because an iPhone cannot use the Mac's `127.0.0.1`. The
phone-reachable acceptance test intentionally rejects loopback endpoints.

After a loopback smoke run, stop the direct `codex app-server --listen
ws://127.0.0.1:4500` process and restart the normal daemon:

```sh
codex app-server daemon restart
```

That restart restores the daemon's normal Unix-socket service. It does not move
the daemon itself into loopback WebSocket mode; current Codex daemon startup
does not expose that setting.

### 3. Phone-reachable mode

For the real Phase 1 proof, the app-server must listen on an address the phone
can reach, such as LAN or Tailscale:

```sh
codex app-server --listen ws://0.0.0.0:4500 --ws-auth capability-token --ws-token-file /absolute/path/to/token
```

The phone connects to the host's real IP, not `0.0.0.0`:

```text
ws://<amir-m5-lan-or-tailscale-ip>:4500
```

Non-loopback WebSocket listeners require Codex websocket auth. The Swift client
must send that auth before the real phone proof can pass.

## Phase 1 Rule

Mocks, scripted transports, Unix sockets, and loopback-only WebSockets do not
complete Phase 1. Phase 1 is complete only after the iPhone path connects to a
real Codex app-server on `Amir-M5` or `Home`.
