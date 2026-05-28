# Codex App Server Ramp-Up

Date captured: 2026-05-27

## Bottom Line

Yes. If the Codex app-server daemon is running, a client can connect to it and
do real work through it.

The app server is not a REST API. It is a bidirectional JSON-RPC API. For the
local daemon, messages travel as WebSocket frames over a Unix socket.

At the time this note was captured, this machine's daemon was not running:

```sh
codex app-server daemon version
```

failed because it could not connect to:

```text
/Users/aelaguiz/.codex/app-server-control/app-server-control.sock
```

The failure was:

```text
No such file or directory (os error 2)
```

## Main Repo Surfaces

The app-server implementation is split across a few crates in
`/Users/aelaguiz/workspace/codex/codex-rs`:

- `app-server`: the JSON-RPC server.
- `app-server-protocol`: the typed API surface and generated schemas.
- `app-server-daemon`: local daemon lifecycle management.
- `app-server-client`: shared client code for in-process and remote app-server
  connections.
- `app-server-transport`: stdio, WebSocket, Unix socket, auth, and remote
  control transport code.

Useful local docs and code references:

- `codex-rs/app-server/README.md`
- `codex-rs/app-server-daemon/README.md`
- `codex-rs/app-server-protocol/src/protocol/common.rs`
- `codex-rs/app-server-client/src/remote.rs`
- `codex-rs/app-server-transport/src/transport/mod.rs`
- `codex-rs/cli/src/main.rs`

## How To Start Or Check The Daemon

The daemon lifecycle commands are:

```sh
codex app-server daemon start
codex app-server daemon restart
codex app-server daemon enable-remote-control
codex app-server daemon disable-remote-control
codex app-server daemon stop
codex app-server daemon version
codex app-server daemon bootstrap --remote-control
```

The current daemon lifecycle implementation is Unix-only. On non-Unix
platforms it returns:

```text
codex app-server daemon lifecycle is only supported on Unix platforms
```

`codex app-server daemon start` is idempotent. It returns after app-server is
ready to answer the normal JSON-RPC initialize handshake on the Unix control
socket.

`bootstrap --remote-control` is for durable SSH-driven use. It records daemon
settings under:

```text
$CODEX_HOME/app-server-daemon/
```

and starts app-server as a pidfile-backed detached process. In the standalone
install case, it also starts an updater loop.

The daemon state directory contains files such as:

```text
$CODEX_HOME/app-server-daemon/settings.json
$CODEX_HOME/app-server-daemon/app-server.pid
$CODEX_HOME/app-server-daemon/app-server-updater.pid
$CODEX_HOME/app-server-daemon/daemon.lock
```

## Local Socket Path

The daemon-managed control socket is:

```text
$CODEX_HOME/app-server-control/app-server-control.sock
```

On this machine that resolves to:

```text
/Users/aelaguiz/.codex/app-server-control/app-server-control.sock
```

The helper that computes that path lives in:

```text
codex-rs/app-server-transport/src/transport/mod.rs
```

## Supported Transports

`codex app-server` supports these listen modes:

- `stdio://`: default, newline-delimited JSON over stdin/stdout.
- `unix://`: WebSocket connections over the default app-server control socket.
- `unix://PATH`: WebSocket connections over a custom Unix socket path.
- `ws://IP:PORT`: WebSocket over TCP. This is experimental and unsupported for
  production workloads.
- `off`: do not expose a local transport.

The default direct server command uses stdio:

```sh
codex app-server --listen stdio://
```

The daemon uses the Unix socket control-plane path.

Important detail: the daemon's Unix socket is not "raw JSONL over a socket." It
expects a WebSocket HTTP Upgrade handshake, then WebSocket frames. The internal
client handshake URL used over the Unix socket is:

```text
ws://localhost/rpc
```

That URL is only for the WebSocket handshake. The bytes still travel over the
Unix socket, not TCP.

## Practical Connection Options

Use one of these approaches:

1. Use the Rust client in `app-server-client`.

   `RemoteAppServerClient` supports:

   ```rust
   RemoteAppServerEndpoint::UnixSocket { socket_path }
   RemoteAppServerEndpoint::WebSocket { websocket_url, auth_token }
   ```

   It owns the connection lifecycle, initialize handshake, request/response
   routing, server-request resolution, and notification streaming.

2. Use a generic client that can speak WebSocket over a Unix socket.

   Connect to:

   ```text
   /Users/aelaguiz/.codex/app-server-control/app-server-control.sock
   ```

   and perform the WebSocket handshake as `ws://localhost/rpc`.

3. Use:

   ```sh
   codex app-server proxy --sock /path/to/app-server-control.sock
   ```

   This opens one raw stream connection to the app-server control socket and
   proxies bytes between that socket and stdin/stdout.

   The proxy does not turn the Unix socket API into plain JSONL. Your client
   still needs to speak WebSocket frames through the proxy.

4. Launch app-server directly on stdio:

   ```sh
   codex app-server --listen stdio://
   ```

   This is the easiest path for a simple test client because the protocol is
   newline-delimited JSON instead of WebSocket-framed JSON.

5. Launch app-server directly on a TCP WebSocket listener:

   ```sh
   codex app-server --listen ws://127.0.0.1:4500
   ```

   This transport is marked experimental and unsupported. For non-loopback
   listeners, app-server refuses to start unless websocket auth is configured
   with either:

   ```sh
   --ws-auth capability-token
   ```

   or:

   ```sh
   --ws-auth signed-bearer-token
   ```

## Connection Handshake

Each connection must initialize before invoking any other method.

First, send `initialize`:

```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": {
      "name": "my_client",
      "title": "My Client",
      "version": "0.1.0"
    },
    "capabilities": {
      "experimentalApi": true
    }
  }
}
```

Then send the `initialized` notification:

```json
{
  "method": "initialized"
}
```

Requests sent before initialization are rejected with:

```text
Not initialized
```

A repeated `initialize` call on the same connection is rejected with:

```text
Already initialized
```

The initialize response returns:

- `userAgent`: the user agent app-server will present upstream.
- `codexHome`: the server's Codex home directory.
- `platformFamily`: the app-server runtime platform family.
- `platformOs`: the app-server runtime operating system.

`clientInfo.name` matters. It is used to identify the client for the OpenAI
Compliance Logs Platform.

## Minimal Conversation Flow

Start a thread:

```json
{
  "method": "thread/start",
  "id": 1,
  "params": {
    "cwd": "/Users/aelaguiz/workspace/codex",
    "approvalPolicy": "never",
    "sandbox": "workspaceWrite"
  }
}
```

The response includes a `thread` object. The server also emits a
`thread/started` notification.

Then start a turn:

```json
{
  "method": "turn/start",
  "id": 2,
  "params": {
    "threadId": "thr_123",
    "input": [
      {
        "type": "text",
        "text": "Run tests and summarize failures"
      }
    ]
  }
}
```

After `turn/start`, keep reading messages from the server. The response is only
the start of the turn. Progress and results arrive through notifications such as:

- `turn/started`
- `item/started`
- `item/agentMessage/delta`
- `item/commandExecution/outputDelta`
- `item/completed`
- `turn/completed`

## Core Primitives

The API exposes three top-level interaction primitives:

- Thread: a conversation between a user and the Codex agent.
- Turn: one user-to-agent exchange inside a thread.
- Item: a unit inside a turn, such as a user message, agent message, command,
  file edit, reasoning block, MCP tool call, or web search.

Use thread APIs to create, resume, fork, list, read, archive, and manage
conversations.

Use turn APIs to send user input and stream the agent's work.

Use item notifications to render the live work happening inside a turn.

## What You Can Do Through The App Server

The short version: the app server exposes almost everything a rich Codex client
needs.

### Conversation And Thread Work

Supported operations include:

- `thread/start`: create a new thread.
- `thread/resume`: reopen an existing thread.
- `thread/fork`: branch an existing thread.
- `thread/list`: page through stored rollouts.
- `thread/loaded/list`: list thread ids currently loaded in memory.
- `thread/read`: read a stored thread without resuming it.
- `thread/turns/list`: experimental paging of turn history.
- `thread/metadata/update`: update stored thread metadata.
- `thread/settings/update`: experimental next-turn settings update.
- `thread/memoryMode/set`: experimental persisted memory eligibility update.
- `memory/reset`: experimental memory reset.
- `thread/name/set`: set a user-facing thread name.
- `thread/archive`: archive a thread.
- `thread/unarchive`: restore an archived thread.
- `thread/unsubscribe`: unsubscribe this connection from thread events.
- `thread/rollback`: drop the last N turns from in-memory context and persist a
  rollback marker.
- `thread/compact/start`: manually trigger history compaction.
- `thread/shellCommand`: run a TUI-style `!` shell command against a thread.

### Goals

Goal APIs:

- `thread/goal/set`
- `thread/goal/get`
- `thread/goal/clear`

Goal notifications:

- `thread/goal/updated`
- `thread/goal/cleared`

### Agent Turns

Use `turn/start` to send user input and trigger Codex generation.

Input can include:

- Text: `{"type":"text","text":"Explain this diff"}`
- Remote image URL: `{"type":"image","url":"https://example.com/image.png"}`
- Local image path: `{"type":"localImage","path":"/tmp/screenshot.png"}`
- Skill mention input.
- App mention input.
- Plugin mention input.

`turn/start` can also override settings such as:

- `cwd`
- model
- reasoning effort
- summary behavior
- personality
- approval policy
- sandbox policy
- permission profile
- output schema
- runtime workspace roots
- experimental environment selection

Same-turn steering is available with:

```text
turn/steer
```

Turn cancellation is available with:

```text
turn/interrupt
```

### Review Mode

Use:

```text
review/start
```

to run Codex's automated reviewer.

Review targets include:

- Uncommitted changes.
- A base branch.
- A specific commit.
- Custom review instructions.

Delivery can be:

- `inline`: review runs as a new turn on the existing thread.
- `detached`: app-server forks a new review thread and runs the review there.

The final review text arrives through `exitedReviewMode` item notifications.

### Command Execution

Use:

```text
command/exec
```

to run a standalone command under the server sandbox without creating a thread
or turn.

Example:

```json
{
  "method": "command/exec",
  "id": 32,
  "params": {
    "command": ["ls", "-la"],
    "processId": "ls-1",
    "cwd": "/Users/me/project",
    "timeoutMs": 10000
  }
}
```

Related methods:

- `command/exec/write`: write base64-decoded stdin bytes to a running command.
- `command/exec/resize`: resize a running PTY-backed command.
- `command/exec/terminate`: terminate a running command.

Related notification:

- `command/exec/outputDelta`: base64-encoded stdout/stderr chunks.

For command execution, `processId` is connection-scoped. If the originating
connection closes, app-server terminates the process.

### Unsandboxed Process Execution

Experimental process APIs:

- `process/spawn`
- `process/writeStdin`
- `process/resizePty`
- `process/kill`

Notifications:

- `process/outputDelta`
- `process/exited`

These spawn standalone processes without the Codex sandbox on the host where
app-server is running. They require `experimentalApi: true`.

### Filesystem Operations

Filesystem methods operate on absolute paths on the app-server host.

Methods include:

- `fs/readFile`: read a file and return `{ dataBase64 }`.
- `fs/writeFile`: write base64 bytes to a file.
- `fs/createDirectory`: create a directory.
- `fs/getMetadata`: return path metadata.
- `fs/readDirectory`: list direct child entries.
- `fs/remove`: remove a file or directory tree.
- `fs/copy`: copy files or directories.
- `fs/watch`: subscribe to filesystem changes.
- `fs/unwatch`: stop watching a path.

Change notification:

- `fs/changed`

`fs/readFile` always returns base64 bytes. `fs/writeFile` always expects
base64 bytes.

### Models, Config, Accounts, And Features

Useful methods include:

- `model/list`
- `modelProvider/capabilities/read`
- `experimentalFeature/list`
- `experimentalFeature/enablement/set`
- `permissionProfile/list`
- `config/read`
- `config/value/write`
- `config/batchWrite`
- `configRequirements/read`
- `account/login/start`
- `account/login/cancel`
- `account/logout`
- `account/read`
- `account/rateLimits/read`
- `account/sendAddCreditsNudgeEmail`

### Skills, Hooks, Apps, Plugins, And Marketplaces

Methods include:

- `skills/list`
- `skills/config/write`
- `hooks/list`
- `app/list`
- `marketplace/add`
- `marketplace/remove`
- `marketplace/upgrade`
- `plugin/list`
- `plugin/installed`
- `plugin/read`
- `plugin/skill/read`
- `plugin/install`
- `plugin/uninstall`
- `plugin/share/save`
- `plugin/share/updateTargets`
- `plugin/share/list`
- `plugin/share/checkout`
- `plugin/share/delete`

Some plugin methods are under development and should not be called from
production clients unless the client intentionally accepts that instability.

### MCP

Methods include:

- `mcpServer/oauth/login`
- `config/mcpServer/reload`
- `mcpServerStatus/list`
- `mcpServer/resource/read`
- `mcpServer/tool/call`

MCP OAuth login returns an authorization URL and later emits:

```text
mcpServer/oauthLogin/completed
```

MCP servers can also send structured elicitations to the client through:

```text
mcpServer/elicitation/request
```

### Realtime

Experimental realtime methods include:

- `thread/realtime/start`
- `thread/realtime/appendAudio`
- `thread/realtime/appendText`
- `thread/realtime/stop`
- `thread/realtime/listVoices`

Realtime notifications include:

- `thread/realtime/started`
- `thread/realtime/sdp`
- `thread/realtime/itemAdded`
- `thread/realtime/transcript/delta`
- `thread/realtime/transcript/done`
- `thread/realtime/outputAudio/delta`
- `thread/realtime/error`
- `thread/realtime/closed`

### Remote Control

Experimental remote-control methods:

- `remoteControl/enable`
- `remoteControl/disable`
- `remoteControl/status/read`

Notification:

- `remoteControl/status/changed`

The status is one of:

- `disabled`
- `connecting`
- `connected`
- `errored`

### Other Utilities

Other useful surfaces:

- `windowsSandbox/setupStart`
- `windowsSandbox/readiness`
- `feedback/upload`
- `externalAgentConfig/detect`
- `externalAgentConfig/import`
- `environment/add`
- `collaborationMode/list`
- `fuzzyFileSearch/sessionStart`
- `fuzzyFileSearch/sessionUpdate`
- `fuzzyFileSearch/sessionStop`

## Events And Streaming

App-server sends server-initiated notifications while work is happening.

Clients should keep reading after every request, especially after:

- `thread/start`
- `thread/resume`
- `thread/fork`
- `turn/start`
- `review/start`
- `command/exec`
- `process/spawn`
- `fs/watch`

Common thread notifications:

- `thread/started`
- `thread/archived`
- `thread/unarchived`
- `thread/closed`
- `thread/status/changed`
- `thread/name/updated`
- `thread/tokenUsage/updated`

Common turn notifications:

- `turn/started`
- `turn/completed`
- `turn/diff/updated`
- `turn/plan/updated`

Common item notifications:

- `item/started`
- `item/completed`
- `item/agentMessage/delta`
- `item/plan/delta`
- `item/reasoning/summaryTextDelta`
- `item/reasoning/summaryPartAdded`
- `item/reasoning/textDelta`
- `item/commandExecution/outputDelta`
- `item/fileChange/patchUpdated`

The per-item lifecycle is usually:

```text
item/started -> zero or more item-specific deltas -> item/completed
```

`turn/completed` currently carries an empty `items` array even when item events
were streamed. Rely on `item/*` notifications for the canonical item list.

## Server-Initiated Requests

The app-server protocol is bidirectional. A serious client cannot only send
requests and ignore inbound messages.

The server can send JSON-RPC requests back to the client for:

- Command execution approval.
- File change approval.
- Permission approval.
- Tool `requestUserInput`.
- MCP server elicitation.
- Dynamic tool calls.
- ChatGPT auth-token refresh.
- Attestation generation.
- Legacy patch and exec approvals.

If the client does not answer these server-initiated requests, some turns can
stall.

Important server request methods include:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/tool/requestUserInput`
- `mcpServer/elicitation/request`
- `item/permissions/requestApproval`
- `item/tool/call`
- `account/chatgptAuthTokens/refresh`
- `attestation/generate`

After a pending server request is resolved or cleared, app-server emits:

```text
serverRequest/resolved
```

## Approval Flow

Command and file edits can require approval depending on config and the active
permission profile.

Command approval order:

1. `item/started` emits the pending `commandExecution` item.
2. `item/commandExecution/requestApproval` asks the client to approve or deny.
3. The client sends a response, such as `{ "decision": "accept" }`.
4. `serverRequest/resolved` confirms the pending request is no longer open.
5. `item/completed` emits the final command state.

File-change approval order:

1. `item/started` emits a pending `fileChange` item with diffs.
2. `item/fileChange/requestApproval` asks the client to approve or deny.
3. The client sends a response, such as `{ "decision": "accept" }`.
4. `serverRequest/resolved` confirms the pending request is no longer open.
5. `item/completed` emits the final file-change state.

Permission requests use:

```text
item/permissions/requestApproval
```

The client response should include the granted subset of the requested
permission profile.

## Notification Opt-Out

Clients can suppress exact notification methods during initialization:

```json
{
  "method": "initialize",
  "id": 1,
  "params": {
    "clientInfo": {
      "name": "my_client",
      "title": "My Client",
      "version": "0.1.0"
    },
    "capabilities": {
      "experimentalApi": true,
      "optOutNotificationMethods": [
        "thread/started",
        "item/agentMessage/delta"
      ]
    }
  }
}
```

Matching is exact. There are no wildcards or prefixes.

## Experimental API Opt-In

Some methods and fields require:

```json
{
  "capabilities": {
    "experimentalApi": true
  }
}
```

If a method or field is experimental and the connection did not opt in,
app-server gates it.

Examples of experimental surfaces include:

- `thread/turns/list`
- `thread/backgroundTerminals/clean`
- `thread/realtime/*`
- `process/*`
- `remoteControl/*`
- `collaborationMode/list`
- `environment/add`
- `tool/requestUserInput`
- fuzzy file search session APIs

## Schema Generation

Generate version-matched TypeScript bindings:

```sh
codex app-server generate-ts --out DIR
```

Generate version-matched JSON Schema:

```sh
codex app-server generate-json-schema --out DIR
```

Include experimental APIs:

```sh
codex app-server generate-ts --out DIR --experimental
codex app-server generate-json-schema --out DIR --experimental
```

These artifacts are specific to the Codex version used to run the command.

## Security And Auth Notes

For local daemon usage, the Unix socket is intended for local app-server
control-plane clients.

For TCP WebSocket usage:

- Loopback `ws://127.0.0.1:PORT` can run without websocket auth.
- Non-loopback websocket listeners refuse to start without auth.
- Auth modes are `capability-token` or `signed-bearer-token`.
- `wss://` or loopback `ws://` are the supported shapes for auth-token use in
  interactive TUI remote mode.

The server also rejects HTTP requests that carry an `Origin` header on the
WebSocket listener, including `/healthz` and `/readyz` probes.

## Quick Test Shape

The simplest test path is direct stdio:

```sh
codex app-server --listen stdio://
```

Then send:

```json
{"method":"initialize","id":0,"params":{"clientInfo":{"name":"my_client","title":"My Client","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}
{"method":"initialized"}
{"method":"thread/start","id":1,"params":{"cwd":"/Users/aelaguiz/workspace/codex","approvalPolicy":"never","sandbox":"workspaceWrite"}}
```

For the daemon path, first start it:

```sh
codex app-server daemon start
```

Then connect over WebSocket frames on:

```text
/Users/aelaguiz/.codex/app-server-control/app-server-control.sock
```

using handshake URL:

```text
ws://localhost/rpc
```

## Practical Takeaway

If the daemon is running, a client can connect and operate Codex through it.
The practical route is to use `RemoteAppServerClient` or another client that
speaks WebSocket over the daemon Unix socket, then drive `thread/start` plus
`turn/start` and consume the notification/request stream.

The main implementation gotcha is bidirectionality. A client that does not
process server-initiated requests for approvals, permissions, MCP elicitations,
dynamic tools, and auth refresh will work only for simple cases.

## Deep Command And Session Specification

This section is the deeper operating spec for "can I connect to an app server
that is already running, can I start or resume Codex sessions, and what happens
if several Codex instances exist at the same time?"

Source basis: this was read from the local repo on 2026-05-27, especially:

- `codex-rs/cli/src/main.rs`
- `codex-rs/app-server/README.md`
- `codex-rs/app-server/src/request_processors/thread_processor.rs`
- `codex-rs/app-server/src/request_processors/turn_processor.rs`
- `codex-rs/app-server/src/request_processors/thread_lifecycle.rs`
- `codex-rs/app-server/src/thread_state.rs`
- `codex-rs/app-server-daemon/src/lib.rs`
- `codex-rs/app-server-daemon/src/backend/pid.rs`
- `codex-rs/app-server-transport/src/transport/mod.rs`
- `codex-rs/app-server-transport/src/transport/unix_socket.rs`
- `codex-rs/app-server-transport/src/transport/websocket.rs`
- `codex-rs/app-server-transport/src/transport/auth.rs`
- `codex-rs/tui/src/lib.rs`
- `codex-rs/tui/src/app_server_session.rs`

### Mental Model

Think of app-server like this:

- `codex app-server` starts a JSON-RPC server.
- A Codex conversation is called a `Thread`.
- A model run inside a thread is called a `Turn`.
- Starting a new conversation is `thread/start`.
- Continuing an existing conversation is `thread/resume`, then `turn/start`.
- Branching an existing conversation is `thread/fork`.
- Reading or listing old conversations is not the same as resuming them.

The normal client flow is:

1. Open a transport connection.
2. Send `initialize`.
3. Send `initialized`.
4. Call `thread/start`, `thread/resume`, or `thread/fork`.
5. Call `turn/start` to make Codex do work.
6. Keep reading notifications and server-initiated requests until the turn
   completes.

Any non-initialize request sent before initialization is rejected with
`"Not initialized"`. A second `initialize` on the same connection is rejected
with `"Already initialized"`.

### Command Matrix

Direct app-server process:

```sh
codex app-server
codex app-server --listen stdio://
codex app-server --listen unix://
codex app-server --listen unix:///tmp/codex.sock
codex app-server --listen ws://127.0.0.1:4500
codex app-server --listen off
codex app-server --strict-config
codex app-server --analytics-default-enabled
```

Direct app-server TCP WebSocket with auth:

```sh
codex app-server --listen ws://0.0.0.0:4500 \
  --ws-auth capability-token \
  --ws-token-file /absolute/path/to/token

codex app-server --listen ws://0.0.0.0:4500 \
  --ws-auth capability-token \
  --ws-token-sha256 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

codex app-server --listen ws://0.0.0.0:4500 \
  --ws-auth signed-bearer-token \
  --ws-shared-secret-file /absolute/path/to/secret \
  --ws-issuer expected-issuer \
  --ws-audience expected-audience \
  --ws-max-clock-skew-seconds 30
```

Daemon lifecycle:

```sh
codex app-server daemon start
codex app-server daemon restart
codex app-server daemon stop
codex app-server daemon version
codex app-server daemon bootstrap
codex app-server daemon bootstrap --remote-control
codex app-server daemon enable-remote-control
codex app-server daemon disable-remote-control
```

Proxy and generated protocol artifacts:

```sh
codex app-server proxy
codex app-server proxy --sock /absolute/path/to/app-server-control.sock
codex app-server generate-ts --out DIR
codex app-server generate-ts --out DIR --experimental
codex app-server generate-json-schema --out DIR
codex app-server generate-json-schema --out DIR --experimental
```

TUI local/remote connection commands:

```sh
codex --remote unix://
codex --remote unix:///tmp/codex.sock
codex --remote ws://127.0.0.1:4500
codex --remote wss://example.com:443 --remote-auth-token-env CODEX_REMOTE_TOKEN
```

TUI resume/fork commands:

```sh
codex resume
codex resume --last
codex resume <SESSION_ID_OR_THREAD_NAME>
codex resume --all
codex resume --include-non-interactive

codex fork
codex fork --last
codex fork <SESSION_ID>
codex fork --all
```

`codex resume` and `codex fork` also accept the interactive `--remote` shape:

```sh
codex resume --remote unix://
codex resume --remote ws://127.0.0.1:4500
codex fork --remote unix://
```

### How To Start The App Server

There are four important start modes.

#### Mode 1: One-Off stdio Server

Use this when a parent process wants to spawn app-server and own its lifetime:

```sh
codex app-server --listen stdio://
```

This is the default. Each line on stdin is one JSON message. Each line on
stdout is one JSON message. There is one app-server connection.

This is best for tests, IDE extension subprocesses, and small custom clients.
It is not a shared daemon.

#### Mode 2: Direct Unix Socket Server

Use this when you want a local socket listener:

```sh
codex app-server --listen unix://
```

Bare `unix://` resolves to:

```text
$CODEX_HOME/app-server-control/app-server-control.sock
```

On this machine, with default `CODEX_HOME`, that is:

```text
/Users/aelaguiz/.codex/app-server-control/app-server-control.sock
```

The socket is a WebSocket server over a Unix domain socket. It is not raw JSONL.
The server accepts a Unix stream, performs a WebSocket upgrade, then exchanges
one JSON-RPC message per WebSocket text frame.

The socket directory is private owner-only state and the socket is chmodded
`0600`. Startup refuses to take over an active socket. If an old path is stale,
the server may remove it.

#### Mode 3: Managed Local Daemon

Use this when you want Codex to manage a persistent local app-server process:

```sh
codex app-server daemon start
```

This command is idempotent:

- If the socket answers, it reports `alreadyRunning`.
- If a pid-managed backend exists but is not ready yet, it waits for readiness.
- Otherwise it starts the managed app-server backend and waits until the socket
  answers the app-server probe.

The daemon uses:

```text
$CODEX_HOME/app-server-control/app-server-control.sock
$CODEX_HOME/app-server-daemon/app-server.pid
$CODEX_HOME/app-server-daemon/app-server-updater.pid
$CODEX_HOME/app-server-daemon/daemon.lock
$CODEX_HOME/app-server-daemon/settings.json
```

On this machine, with default `CODEX_HOME`, those are under:

```text
/Users/aelaguiz/.codex/
```

Important daemon detail: the daemon lifecycle expects the managed standalone
Codex binary at:

```text
$CODEX_HOME/packages/standalone/current/codex
```

on Unix, or:

```text
$CODEX_HOME/packages/standalone/current/codex.exe
```

on Windows. The daemon lifecycle itself is currently Unix-only, so the practical
managed daemon path today is the Unix `codex` path. If that binary is missing,
daemon start/bootstrap tells the user to install Codex with:

```sh
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

At the time this doc was first created, the daemon was not running. The check:

```sh
codex app-server daemon version
```

failed because the default socket did not exist.

#### Mode 4: Direct TCP WebSocket Server

Use this when you want a WebSocket listener on a TCP port:

```sh
codex app-server --listen ws://127.0.0.1:4500
```

Loopback listeners can run without websocket auth. Non-loopback listeners refuse
to start unless websocket auth is configured.

Health probes for the TCP listener:

```text
GET /readyz
GET /healthz
```

Both return `200 OK` when the listener is healthy and the request does not have
an `Origin` header. Requests with an `Origin` header are rejected with
`403 Forbidden`.

### WebSocket Auth Rules

Auth is only for WebSocket listeners. The app-server auth flags are:

```text
--ws-auth
--ws-token-file
--ws-token-sha256
--ws-shared-secret-file
--ws-issuer
--ws-audience
--ws-max-clock-skew-seconds
```

Supported `--ws-auth` modes:

```text
capability-token
signed-bearer-token
```

Capability-token mode:

- Requires exactly one of `--ws-token-file` or `--ws-token-sha256`.
- Rejects signed-bearer-only flags.
- Validates `Authorization: Bearer <token>` on the WebSocket upgrade.

Signed-bearer-token mode:

- Requires `--ws-shared-secret-file`.
- Optional `--ws-issuer`.
- Optional `--ws-audience`.
- Optional `--ws-max-clock-skew-seconds`; default is 30 seconds.
- The shared secret must be at least 32 bytes.
- Validates `Authorization: Bearer <jwt>` on the WebSocket upgrade.

Path-valued auth flags must be absolute paths. If `--ws-auth` is omitted, auth
specific flags are rejected.

### What `codex app-server proxy` Does

`codex app-server proxy` connects stdio to a Unix domain socket:

```sh
codex app-server proxy
codex app-server proxy --sock /absolute/path/to/app-server-control.sock
```

The proxy is byte-level. It is not a JSONL adapter. If the target is the app
server Unix socket, the stream still has to carry the HTTP WebSocket upgrade and
WebSocket frames.

That means this is not enough:

```sh
printf '{"method":"initialize",...}\n' | codex app-server proxy
```

A client using the proxy still needs to speak WebSocket framing over the proxied
byte stream.

### Protocol Envelope

The app-server protocol is JSON-RPC shaped, but the wire omits the
`"jsonrpc": "2.0"` field.

Request:

```json
{
  "method": "thread/start",
  "id": 1,
  "params": {}
}
```

Response:

```json
{
  "id": 1,
  "result": {}
}
```

Notification:

```json
{
  "method": "thread/started",
  "params": {}
}
```

Error:

```json
{
  "id": 1,
  "error": {
    "code": -32600,
    "message": "Not initialized"
  }
}
```

Stdio transport uses one JSON message per newline. WebSocket transport uses one
JSON message per WebSocket text frame.

### Required Initialize Handshake

Every transport connection must initialize separately.

Minimum stable initialize:

```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": {
      "name": "my_client",
      "title": "My Client",
      "version": "0.1.0"
    },
    "capabilities": {}
  }
}
```

Then send:

```json
{
  "method": "initialized"
}
```

Experimental APIs require an experimental opt-in on that same connection:

```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": {
      "name": "my_client",
      "title": "My Client",
      "version": "0.1.0"
    },
    "capabilities": {
      "experimentalApi": true
    }
  }
}
```

The experimental opt-in is per connection. One client connection can have
experimental API enabled while another connection to the same server does not.

Per-connection notification opt-out is also negotiated during initialize:

```json
{
  "method": "initialize",
  "id": 0,
  "params": {
    "clientInfo": {
      "name": "my_client",
      "title": "My Client",
      "version": "0.1.0"
    },
    "capabilities": {
      "optOutNotificationMethods": [
        "item/agentMessage/delta",
        "thread/started"
      ]
    }
  }
}
```

The opt-out list uses exact method names. It does not support wildcards.

### Start A New Codex Session Through App-Server

In app-server terms, a new session is a new thread:

```json
{
  "method": "thread/start",
  "id": 1,
  "params": {
    "cwd": "/Users/aelaguiz/workspace/codex",
    "approvalPolicy": "never",
    "sandbox": "workspaceWrite"
  }
}
```

Important response/event behavior:

- The `thread/start` response returns the initial thread object.
- The server also emits `thread/started`.
- The requesting connection is auto-subscribed to events for that thread.
- If `ephemeral: true`, the thread is intentionally in-memory only and
  `thread.path` is `null`.

Common `thread/start` request fields:

```text
model
modelProvider
serviceTier
cwd
runtimeWorkspaceRoots
approvalPolicy
approvalsReviewer
sandbox
permissions
config
serviceName
baseInstructions
developerInstructions
personality
ephemeral
sessionStartSource
threadSource
environments
dynamicTools
experimentalRawEvents
persistExtendedHistory
```

Notes:

- `runtimeWorkspaceRoots`, `permissions`, `environments`, `dynamicTools`, and
  `experimentalRawEvents` are experimental.
- `sandbox` and `permissions` cannot be combined.
- `persistExtendedHistory` is deprecated and ignored.
- Wire fields are camelCase.

### Make Codex Do Work

After a thread exists and is loaded, call `turn/start`:

```json
{
  "method": "turn/start",
  "id": 2,
  "params": {
    "threadId": "THREAD_ID_FROM_THREAD_START",
    "input": [
      {
        "type": "text",
        "text": "Explain the app-server daemon lifecycle."
      }
    ],
    "cwd": "/Users/aelaguiz/workspace/codex",
    "approvalPolicy": "never"
  }
}
```

`turn/start` immediately returns an initial in-progress turn. The real work is
then streamed through notifications:

```text
turn/started
item/started
item/agentMessage/delta
item/completed
turn/completed
thread/tokenUsage/updated
```

Common `turn/start` fields:

```text
threadId
input
responsesapiClientMetadata
additionalContext
environments
cwd
runtimeWorkspaceRoots
approvalPolicy
approvalsReviewer
sandboxPolicy
permissions
model
serviceTier
effort
summary
personality
outputSchema
collaborationMode
```

Notes:

- The target thread must already be loaded.
- `thread/read` does not load the thread.
- `thread/list` does not load the thread.
- To continue a stored thread, call `thread/resume` first, then `turn/start`.
- `sandboxPolicy` and `permissions` cannot be combined.

### Resume An Existing Codex Session Through App-Server

To continue a stored session:

```json
{
  "method": "thread/resume",
  "id": 3,
  "params": {
    "threadId": "THREAD_ID"
  }
}
```

Then start a new turn:

```json
{
  "method": "turn/start",
  "id": 4,
  "params": {
    "threadId": "THREAD_ID",
    "input": [
      {
        "type": "text",
        "text": "Continue from here."
      }
    ]
  }
}
```

Resume behavior:

- `thread/resume` reopens an existing thread so future `turn/start` calls append
  to it.
- By default, it reconstructs turn history into `thread.turns`.
- If persisted token usage exists, the server may emit
  `thread/tokenUsage/updated` immediately after the response.
- If the thread is already loaded/running in that server process,
  `thread/resume` rejoins the live thread instead of duplicating it.
- A running-thread resume can replay active turn state and pending
  server-initiated requests to the newly subscribed connection.

Common `thread/resume` fields:

```text
threadId
history
path
model
modelProvider
serviceTier
cwd
runtimeWorkspaceRoots
approvalPolicy
approvalsReviewer
sandbox
permissions
config
baseInstructions
developerInstructions
personality
environments
excludeTurns
persistExtendedHistory
```

Notes:

- `history` and `path` are unstable/experimental style resume inputs.
- For a cold resume, effective source precedence is history, then non-empty
  path, then thread id.
- For a running thread, thread id rejoins the live thread and path is a
  consistency check.
- `excludeTurns: true` is experimental. It returns metadata/live state without
  full turn history so the client can page history with `thread/turns/list`.
- `sandbox` and `permissions` cannot be combined.
- `persistExtendedHistory` is deprecated and ignored.

### Fork A Session Through App-Server

To branch from a stored or loaded session:

```json
{
  "method": "thread/fork",
  "id": 5,
  "params": {
    "threadId": "SOURCE_THREAD_ID",
    "ephemeral": true
  }
}
```

Fork behavior:

- The server creates a new thread id with copied history.
- The returned thread's `forkedFromId` points at the source thread when known.
- The returned thread's `sessionId` identifies the current live session tree
  root.
- The server emits `thread/started` for the new thread.
- The requesting connection is auto-subscribed to the new thread.
- If the source thread is mid-turn, the fork records an interruption marker
  instead of inheriting an unmarked partial turn suffix.
- `ephemeral: true` keeps the fork in memory only.

Common `thread/fork` fields:

```text
threadId
path
model
modelProvider
serviceTier
cwd
runtimeWorkspaceRoots
approvalPolicy
approvalsReviewer
sandbox
permissions
config
baseInstructions
developerInstructions
personality
ephemeral
threadSource
excludeTurns
persistExtendedHistory
```

### Browse Sessions Without Loading Them

List stored sessions:

```json
{
  "method": "thread/list",
  "id": 10,
  "params": {
    "limit": 25,
    "sortKey": "createdAt",
    "sortDirection": "desc"
  }
}
```

`thread/list` params:

```text
cursor
limit
sortKey
sortDirection
modelProviders
sourceKinds
archived
cwd
useStateDbOnly
searchTerm
```

Defaults and limits:

- Default limit is 25.
- Max limit is 100.
- Default sort key is `createdAt`.
- Default sort direction is `desc`.
- Default list excludes archived threads.

List currently loaded in-memory threads:

```json
{
  "method": "thread/loaded/list",
  "id": 11
}
```

Read one stored thread without resuming it:

```json
{
  "method": "thread/read",
  "id": 12,
  "params": {
    "threadId": "THREAD_ID",
    "includeTurns": true
  }
}
```

Page stored turn history without resuming:

```json
{
  "method": "thread/turns/list",
  "id": 13,
  "params": {
    "threadId": "THREAD_ID",
    "limit": 25
  }
}
```

Important:

- `thread/list` is browsing.
- `thread/read` is browsing.
- `thread/turns/list` is browsing.
- None of those load the thread for continuation.
- To continue, call `thread/resume`, then `turn/start`.

### Steer Or Interrupt A Running Turn

Add input to an already active regular turn:

```json
{
  "method": "turn/steer",
  "id": 20,
  "params": {
    "threadId": "THREAD_ID",
    "expectedTurnId": "TURN_ID",
    "input": [
      {
        "type": "text",
        "text": "Also consider the daemon path."
      }
    ]
  }
}
```

Cancel an active turn:

```json
{
  "method": "turn/interrupt",
  "id": 21,
  "params": {
    "threadId": "THREAD_ID",
    "turnId": "TURN_ID"
  }
}
```

`turn/steer` only works for an active regular turn. Review turns and manual
compaction turns reject steering. If the expected turn id mismatches, steering
fails.

### Server-Initiated Requests

The server can send JSON-RPC requests to the client. A real client must answer
these by `id`.

Server-to-client request methods include:

```text
item/commandExecution/requestApproval
item/fileChange/requestApproval
item/tool/requestUserInput
mcpServer/elicitation/request
item/permissions/requestApproval
item/tool/call
account/chatgptAuthTokens/refresh
attestation/generate
applyPatchApproval
execCommandApproval
```

This is why a simple request/response-only client is incomplete. It may work
for a trivial `thread/start`, but it will fail or hang once the model needs a
tool approval, file approval, MCP elicitation, dynamic tool call, ChatGPT token
refresh, or attestation.

### What If Six Codex Instances Are Running?

There are several different meanings of "six Codex instances." They behave
differently.

#### Case A: Six Clients Connected To One Daemon

This is the shared-live-world model.

```text
client 1 ----\
client 2 -----\
client 3 ------> one app-server daemon process
client 4 -----/
client 5 ----/
client 6 ---/
```

What is shared:

- The app-server process.
- Loaded in-memory threads in that process.
- Thread status tracking.
- The default `CODEX_HOME`.
- Stored session history under that `CODEX_HOME`.
- The daemon socket.

What is per connection:

- Initialize state.
- Experimental API opt-in.
- Notification opt-out list.
- Subscriptions to thread events.
- Pending server-to-client request routing.

Starting, resuming, and forking auto-subscribe the requesting connection to the
target thread. A second client can call `thread/resume` for a thread that is
already loaded/running in the daemon. In that case, app-server rejoins the live
thread and can replay history, active turn state, and pending server requests to
that connection.

Events are subscription-scoped. A connection does not automatically receive
every event for every loaded thread just because it is connected to the daemon.

Use:

```json
{ "method": "thread/loaded/list", "id": 30 }
```

to see the thread ids currently loaded in that app-server process.

#### Case B: Six TUI Windows

A TUI launch chooses one of three app-server targets:

```text
Embedded
LocalDaemon
Remote
```

Rules:

- Explicit `--remote` wins and uses `Remote`.
- Without explicit `--remote`, the TUI may auto-connect to the default local
  daemon socket if it exists and the launch config is reusable by the daemon.
- If there is no usable daemon socket, the TUI starts an embedded app-server
  in-process.

The default daemon auto-connect is conservative. The TUI skips implicit daemon
reuse when launch config cannot be replayed into the daemon, for example when
there are CLI config overrides, non-default loader overrides, `--strict-config`,
or non-replayable hook-trust overrides.

So six TUI windows can mean:

- Six windows all using one local daemon.
- Six windows each using its own embedded in-process app-server.
- Some mix of embedded, local daemon, and explicit remote.

The reliable way to force sharing is to start/connect to a common server:

```sh
codex app-server daemon start
codex --remote unix://
codex resume --remote unix://
codex fork --remote unix://
```

The reliable way to force a separate server is to run a separate `codex
app-server` process with `stdio://`, a different custom Unix socket, or a
different WebSocket port.

#### Case C: Six Independent App-Server Processes

This is six separate live worlds.

Examples:

```sh
codex app-server --listen stdio://
codex app-server --listen unix:///tmp/codex-1.sock
codex app-server --listen unix:///tmp/codex-2.sock
codex app-server --listen ws://127.0.0.1:4501
codex app-server --listen ws://127.0.0.1:4502
codex app-server --listen ws://127.0.0.1:4503
```

Each process has its own:

- Connections.
- Loaded in-memory threads.
- Listener tasks.
- Pending server-to-client requests.
- Active turns.

They may still share the same `CODEX_HOME`, config files, auth, and stored
rollout history if launched with the same environment. That means they can see
the same persisted sessions in `thread/list`, but their live loaded-thread
state is process-local.

Practical rule: use one daemon if you want one coordinated live runtime. Use
separate sockets/ports only when you intentionally want separate app-server
processes.

#### Case D: Two Servers Want The Default Daemon Socket

Only one process can own:

```text
$CODEX_HOME/app-server-control/app-server-control.sock
```

If a live app-server is already accepting connections there, a second
`codex app-server --listen unix://` refuses to start with an address-in-use
style error.

Use custom paths for separate socket servers:

```sh
codex app-server --listen unix:///tmp/codex-a.sock
codex app-server --listen unix:///tmp/codex-b.sock
```

### Thread Lifetime And Loaded State

The app-server keeps loaded thread state in memory. A loaded thread has a
listener task that streams app-server events to subscribed connections.

When no connections are subscribed and the thread is not active, the server
starts an unload countdown. The current unload delay is:

```text
30 minutes
```

After that, the server can unload the thread and emit `thread/closed`.

Important consequences:

- A stored thread can exist on disk but not be loaded.
- `thread/loaded/list` shows only in-memory loaded threads.
- `thread/list` shows stored sessions and projects live status into results
  when known.
- A thread that is not loaded must be resumed before `turn/start`.

### How The TUI Uses App-Server Internally

The TUI wraps the app-server methods in `AppServerSession`.

Important wrappers:

```text
start_thread -> thread/start
resume_thread -> thread/resume
fork_thread -> thread/fork
thread_list -> thread/list
thread_loaded_list -> thread/loaded/list
thread_read -> thread/read
turn_start -> turn/start
turn_steer -> turn/steer
turn_interrupt -> turn/interrupt
```

The TUI chooses whether thread params look local or remote:

- `Embedded` and `LocalDaemon` use local/embedded-style thread params.
- Explicit `Remote` uses remote workspace behavior.

That means local daemon is remote transport, but not necessarily remote
workspace semantics.

### Can We Start And Resume Codex Sessions?

Yes.

CLI path:

```sh
codex
codex resume
codex resume --last
codex resume <SESSION_ID_OR_THREAD_NAME>
codex fork
codex fork --last
codex fork <SESSION_ID>
```

App-server path:

```text
initialize
initialized
thread/start
turn/start
```

or:

```text
initialize
initialized
thread/resume
turn/start
```

or:

```text
initialize
initialized
thread/fork
turn/start
```

### What You Can Do Through App-Server

The app-server surface is much larger than start/resume:

Thread/session:

```text
thread/start
thread/resume
thread/fork
thread/list
thread/loaded/list
thread/read
thread/turns/list
thread/archive
thread/unarchive
thread/unsubscribe
thread/rollback
thread/compact/start
thread/shellCommand
thread/name/set
thread/metadata/update
thread/metadata/gitInfo/update
thread/memoryMode/set
```

Turn execution:

```text
turn/start
turn/steer
turn/interrupt
review/start
```

Realtime:

```text
thread/realtime/start
thread/realtime/appendAudio
thread/realtime/appendText
thread/realtime/stop
thread/realtime/listVoices
```

Filesystem:

```text
fs/readFile
fs/writeFile
fs/createDirectory
fs/getMetadata
fs/readDirectory
fs/remove
fs/copy
fs/watch
fs/unwatch
```

Processes:

```text
process/spawn
process/writeStdin
process/resizePty
process/kill
```

Auth/account:

```text
account/read
account/login/start
account/login/cancel
account/logout
account/rateLimits/read
account/sendAddCreditsNudgeEmail
```

Models/config:

```text
model/list
config/read
config/value/write
config/batchWrite
config/mcpServer/reload
experimentalFeature/enablement/set
```

MCP:

```text
mcpServer/oauth/login
mcpServerStatus/list
mcpServer/resource/read
mcpServer/tool/call
```

Apps/plugins/skills:

```text
app/list
marketplace/add
marketplace/remove
marketplace/upgrade
plugin/list
plugin/installed
plugin/read
plugin/skill/read
plugin/install
plugin/uninstall
skills/config/write
```

Feedback/migration/remote control:

```text
feedback/upload
externalAgentConfig/detect
externalAgentConfig/import
environment/add
remoteControl/enable
remoteControl/disable
remoteControl/status/read
```

Experimental methods require `initialize.params.capabilities.experimentalApi =
true` on that connection.

### Minimal Recipes

Check whether daemon is currently running:

```sh
codex app-server daemon version
```

Start daemon if installed as a managed standalone Codex:

```sh
codex app-server daemon start
```

Start a temporary app-server for one parent process:

```sh
codex app-server --listen stdio://
```

Start a local app-server socket manually:

```sh
codex app-server --listen unix://
```

Start two separate local socket servers:

```sh
codex app-server --listen unix:///tmp/codex-a.sock
codex app-server --listen unix:///tmp/codex-b.sock
```

Start a loopback WebSocket server:

```sh
codex app-server --listen ws://127.0.0.1:4500
```

Connect TUI to default daemon socket:

```sh
codex --remote unix://
```

Resume through default daemon socket:

```sh
codex resume --remote unix://
```

Fork through default daemon socket:

```sh
codex fork --remote unix://
```

List loaded threads through a JSON-RPC client:

```json
{
  "method": "thread/loaded/list",
  "id": 100
}
```

### Practical Answer

If you have the app-server daemon running, you can connect to it and control
Codex sessions. You can start a new session, resume an old one, fork a branch,
send turns, steer or interrupt an active turn, browse stored sessions, inspect
loaded sessions, read/write files through the app-server filesystem API, call
MCP tools, manage auth, query models and rate limits, and more.

The key implementation rule is: one app-server process can serve many clients,
but every client connection must initialize and every client that wants live
events for a thread must be subscribed to that thread. Starting, resuming, and
forking handle that subscription automatically for the requesting connection.

## Parallel Explorer Addendum

The following adds the details that were found by the parallel read-only
explorers after the first deep spec was saved.

### Standalone Binary Versus CLI Subcommand

There are two ways to run the app-server binary surface:

```sh
codex app-server
codex-app-server
```

`codex app-server` is the normal top-level CLI subcommand. It hardcodes
`SessionSource::VSCode` for the app-server run path, passes runtime paths,
transport settings, websocket auth settings, strict-config behavior, analytics
defaulting, and the hidden remote-control flag.

`codex-app-server` is also a standalone binary from the `app-server` crate. Its
notable flags include:

```text
--listen URL
--session-source SOURCE
--strict-config
--remote-control
```

The standalone binary's `--session-source` defaults to `vscode`. Its analytics
default is false.

### Daemon Output Contract

Daemon lifecycle commands print exactly one JSON object on success. The CLI
serializes the daemon output with `serde_json::to_string`.

Examples:

```sh
codex app-server daemon start
codex app-server daemon restart
codex app-server daemon stop
codex app-server daemon version
codex app-server daemon bootstrap --remote-control
codex app-server daemon enable-remote-control
codex app-server daemon disable-remote-control
```

Expected status vocabulary includes:

```text
started
alreadyRunning
restarted
stopped
notRunning
running
bootstrapped
enabled
alreadyEnabled
disabled
alreadyDisabled
```

The exact object shape depends on the command, but the important operational
contract is "one JSON object," not human-formatted logs.

### Daemon Locking And Timeouts

The daemon is singleton-like per `CODEX_HOME`, not machine-wide.

The daemon derives these from `CODEX_HOME`:

```text
app-server-control/app-server-control.sock
app-server-control/app-server-startup.lock
app-server-daemon/
app-server-daemon/settings.json
app-server-daemon/app-server.pid
app-server-daemon/app-server-updater.pid
app-server-daemon/daemon.lock
```

Mutating daemon commands take the daemon operation lock. The lock wait timeout
is currently 75 seconds. This serializes:

```text
start
restart
stop
bootstrap
enable-remote-control
disable-remote-control
```

Readiness waits currently use:

```text
10 seconds app-server readiness wait
50 ms poll interval
2 seconds control-socket probe timeout
```

If readiness fails, daemon startup diagnostics append managed binary identity
and up to 4096 bytes of the managed app-server stderr log tail.

Managed stop behavior:

```text
send SIGTERM
wait grace period
send SIGKILL after 60 seconds
fail after 70 seconds total
```

PID records are JSON with:

```text
pid
processStartTime
```

The daemon compares both PID and process start time so PID reuse does not look
like the old managed app-server.

Derived pid-management files can include:

```text
app-server.pid.lock
app-server.pid.tmp
app-server.stderr.log
app-server-updater.pid.lock
app-server-updater.pid.tmp
app-server-updater.stderr.log
```

### Daemon Bootstrap And Auto-Update

`codex app-server daemon bootstrap` does more than `start`.

It:

1. Requires the managed standalone Codex binary.
2. Writes `settings.json`.
3. Refuses to manage a non-daemon app-server already on the default socket.
4. Stops any existing managed app-server process.
5. Starts the app-server backend.
6. Restarts the updater backend if needed.
7. Starts the updater backend.
8. Waits for app-server readiness.
9. Returns daemon/bootstrap JSON.

The updater loop:

- Waits 5 minutes before the first update check.
- Then runs hourly.
- Fetches `https://chatgpt.com/codex/install.sh`.
- Runs it with `/bin/sh -s`.
- Can restart app-server after the managed binary changes.
- Is not reboot-persistent according to the local daemon README.

### Remote Control CLI Versus App-Server RPC

There are two related but different remote-control surfaces.

Process-local app-server RPCs:

```text
remoteControl/enable
remoteControl/disable
remoteControl/status/read
remoteControl/status/changed
```

These are experimental app-server APIs. `remoteControl/enable` enables remote
control for the current process but does not persist the desired setting by
itself. `remoteControl/disable` disables the current process and clears the
client-visible `environmentId`, but it does not revoke already enrolled
controller devices.

CLI surface:

```sh
codex remote-control
codex remote-control --json
codex remote-control start
codex remote-control start --json
codex remote-control stop
codex remote-control stop --json
```

`codex remote-control` with no subcommand is foreground mode. It creates a
private temporary socket like:

```text
/tmp/codex-rc-*/rc.sock
```

then starts an in-process app-server with Unix socket transport and remote
control enabled, waits for remote-control readiness through the socket, prints
readiness, and stops on Ctrl-C.

`codex remote-control start` is daemon mode. It ensures the managed app-server
daemon is started with remote control enabled, then sends `remoteControl/enable`
over the control socket and waits up to 10 seconds for a status that is no
longer `connecting`.

Remote-control status values:

```text
disabled
connecting
connected
errored
```

Remote control depends on the SQLite state DB and ChatGPT-style auth. API-key
auth is rejected for remote-control connection auth. Missing account id can
produce a retryable "waiting for account id" state. Connection errors produce
`errored` and reconnect with backoff capped at 30 seconds; 401/403 attempts auth
recovery; 404 clears stale enrollment.

### Direct Process Boundaries

`stdio://` is one client per app-server process.

In stdio mode:

- App-server creates exactly one connection id.
- It reads newline-delimited JSON from stdin.
- It writes newline-delimited JSON to stdout.
- EOF sends `ConnectionClosed`.
- App-server runs in single-client mode and shuts down when no connections
  remain.

Unix socket and TCP WebSocket transports can host multiple clients in one
server process. Each accepted stream gets its own connection id.

Direct app-server processes are independent unless they collide on a resource:

- Same default `unix://` socket path: conflict.
- Same explicit Unix socket path: conflict.
- Same TCP port: bind conflict.
- Different Unix socket paths: separate app-server processes.
- Different TCP ports: separate app-server processes.
- Separate stdio processes: separate app-server processes.

### Per-Connection State In One Server

One app-server process has one shared message processor, but each connection has
its own session state.

Per-connection state includes:

```text
initialized flag
experimentalApi capability
notification opt-out methods
thread subscriptions
server-request routing
command/process handles
```

Notifications are sent only to initialized connections. Experimental
notifications are filtered out for connections that did not opt into
`experimentalApi`. Notification opt-outs are also applied per connection.

Thread subscription maps are connection-scoped:

```text
thread_id -> connection_ids
connection_id -> thread_ids
```

Disconnect removes that connection's subscriptions. `thread/unsubscribe`
removes only that connection's subscription to the named thread.

Thread events are sent to subscribed connection ids, not automatically to every
connected client. New thread creation has additional best-effort listener attach
logic for currently initialized connections in the same process, but normal
client code should still treat thread event delivery as subscription-scoped.

### Loaded Thread And Turn Concurrency

Loaded threads are process memory.

One app-server process has one in-process thread manager:

```text
ThreadId -> CodexThread
```

`thread/loaded/list` reads that in-memory manager. A second app-server process
has its own manager. It may see the same persisted history on disk, but it does
not share:

```text
loaded CodexThread objects
active turns
listener tasks
subscriptions
pending server requests
command sessions
process sessions
```

Concurrent turns on one loaded thread are serialized through the core session.
`turn/start` submits input to the target thread. The core session receives
submissions serially and does not run two independent active agent turns for
the same loaded thread. Extra input can be steered into an active turn through
`turn/steer` when allowed.

### Connection-Scoped Command And Process Handles

Command/process handles are not global.

The command execution API keys sessions by:

```text
connection_id + process_id
```

The experimental process API keys sessions by:

```text
connection_id + process_handle
```

Closing a connection terminates only that connection's command/process sessions.
Output notifications are sent back to that same connection.

### Command Execution API

There are two process-like APIs.

Stable sandboxed command execution:

```text
command/exec
command/exec/write
command/exec/terminate
command/exec/resize
command/exec/outputDelta
```

This runs a standalone command in the server sandbox. The response is deferred
until the command exits. Output can stream through `command/exec/outputDelta`.
`processId` is connection-scoped and is used for TTY, stdin streaming,
stdout/stderr streaming, and follow-up write/terminate/resize calls.

Important `command/exec` gotchas:

- Empty commands are rejected.
- `sandboxPolicy` and experimental `permissionProfile` are mutually exclusive.
- `size` requires `tty`.
- `disableOutputCap` conflicts with `outputBytesCap`.
- There is a default output cap.
- Env values can override or unset environment variables.
- Closing the connection terminates active command sessions for that connection.
- Windows sandbox mode rejects streaming/custom caps and does not support
  follow-up write/terminate/resize.

Experimental unsandboxed process API:

```text
process/spawn
process/writeStdin
process/kill
process/resizePty
process/outputDelta
process/exited
```

`process/spawn` is explicitly unsandboxed and runs on the host where app-server
is running. It returns after process registration, not after exit. Output and
exit arrive through notifications. `cwd` must be absolute. The handle is
connection-scoped. Closing the connection kills spawned processes.

### More Capability Surface

The earlier capability list intentionally focused on the common session/file/MCP
flows. The protocol also includes these surfaces.

Goals:

```text
thread/goal/set
thread/goal/get
thread/goal/clear
thread/goal/updated
thread/goal/cleared
```

Goal APIs need the feature gate, a materialized non-ephemeral thread, and the
SQLite DB.

Catalog/config extras:

```text
configRequirements/read
modelProvider/capabilities/read
experimentalFeature/list
experimentalFeature/enablement/set
permissionProfile/list
collaborationMode/list
```

`collaborationMode/list` is experimental.

Skills/hooks/apps/plugins/marketplace:

```text
skills/list
hooks/list
skills/config/write
app/list
marketplace/add
marketplace/remove
marketplace/upgrade
plugin/list
plugin/installed
plugin/read
plugin/skill/read
plugin/install
plugin/uninstall
plugin/share/save
plugin/share/updateTargets
plugin/share/list
plugin/share/checkout
plugin/share/delete
```

Local docs warn that some plugin/app APIs are still under development even when
their method gate is stable.

Fuzzy file search:

```text
fuzzyFileSearch
fuzzyFileSearch/sessionStart
fuzzyFileSearch/sessionUpdate
fuzzyFileSearch/sessionStop
fuzzyFileSearch/sessionUpdated
fuzzyFileSearch/sessionCompleted
```

The session API is experimental. Search caps matches at 50 and sorts by score
then path.

Windows sandbox:

```text
windowsSandbox/setupStart
windowsSandbox/readiness
windowsSandbox/setupCompleted
windows/worldWritableWarning
```

Non-Windows reports `notConfigured` for readiness.

Other control surfaces:

```text
thread/shellCommand
thread/inject_items
feedback/upload
```

`thread/shellCommand` runs an unsandboxed shell command from thread context and
does not inherit the thread sandbox. `thread/inject_items` appends raw Responses
API items without starting a turn; those items persist and are included in
future model requests.

### Shared Disk State Versus Shared Runtime State

Multiple app-server processes can share durable disk state if they use the same
`CODEX_HOME` and `sqlite_home`.

Shared durable state can include:

```text
config.toml
auth material
rollout JSONL history
SQLite thread metadata
memories
plugin/marketplace state
```

But runtime coordination is mostly process-local:

```text
loaded threads
live rollout writer maps
active turns
listener subscriptions
pending server requests
command sessions
process sessions
```

So if two separate app-server processes use the same `CODEX_HOME`, they can
often list/read the same stored sessions. They are not sharing the same live
session objects.

For one coordinated live workspace, use one daemon or one explicit shared
server. For intentionally isolated live runtimes, use separate app-server
processes on separate sockets/ports or separate `CODEX_HOME` values.

### Backpressure And Slow Clients

App-server uses bounded queues between transport ingress, request processing,
and outbound writes.

If request ingress is saturated, new requests can fail with:

```json
{
  "error": {
    "code": -32001,
    "message": "Server overloaded; retry later."
  }
}
```

Clients should use retry with exponential backoff and jitter.

Slow disconnect-capable outbound connections can be disconnected when their
outbound queue fills.

### Sharp Edges Checklist

- `--strict-config` is accepted on `codex app-server` itself, not app-server
  subcommands such as `proxy` or `daemon`.
- Root `--remote` and `--remote-auth-token-env` are for interactive TUI
  commands, not `codex app-server` or `codex remote-control`.
- `unix://PATH` can be relative; it resolves relative to the current working
  directory. Use absolute paths when you need a stable location.
- `codex app-server proxy` is a raw byte proxy; it does not convert JSONL into
  WebSocket frames.
- Non-loopback `ws://` requires websocket auth.
- Auth path flags must be absolute.
- `thread/read`, `thread/list`, and `thread/turns/list` do not load a thread
  for continuation.
- `turn/start` requires a loaded thread.
- `thread/resume` on an already loaded/running thread mostly means "rejoin";
  mismatched overrides may be ignored unless the thread is idle with no
  subscribers and can be cold-resumed.
- `ephemeral: true` means in-memory only; some stored-history read/list paths
  are not available for ephemeral threads.
- Archived threads are hidden from normal `thread/list`, but direct read/resume
  and fork paths can still address archived storage by id/path.
- Experimental method or field use requires per-connection
  `capabilities.experimentalApi = true`.
