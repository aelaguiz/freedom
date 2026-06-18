# Codex Dock Thread Control Architecture Audit

Date: 2026-06-06
Status: audit only, no implementation
Scope: why Codex Dock can show real threads that it cannot fully read, subscribe
to, or send messages into

## Direct Answer

2026-06-06 correction: the root cause is not primarily a Codex Dock app bug.
Codex Dock exposes the problem because it tries to route messages into visible
threads, but the failing layer is current Codex CLI/app-server behavior: the
Codex CLI can launch private in-process runtimes or route through a long-lived
daemon whose auth state belongs to one `$CODEX_HOME`. We do not get to change
upstream Codex in this repo, so the answer here is to design around that fixed
contract with launch discipline, account-scoped homes, relay capability checks,
and Dock UI state that refuses to treat non-controllable rows as sendable.

The deeper failure is architectural: Dock currently treats "visible in history"
as close enough to "controllable from the phone." Those are not the same thing.

A thread that appears in the main Dock app should be fully controllable:

- it should have complete enough detail for the user to understand it,
- it should support live updates,
- it should accept user messages,
- it should support relevant controls like interrupt, approve, rename, archive,
  fork, and continue,
- and if any of that is temporarily unavailable, the app should know that before
  presenting the thread as an active conversation.

Today that invariant is false. The phone can see rows that are backed by Codex
history or private `stdio` Codex runtimes, while the send path requires a
controllable loaded app-server thread. That split is why messages can fail even
though the row looks real.

Net: the fix should not be "rename `Check`." The fix is to rebuild the Dock
control plane and the CLI launch model so the app never presents a normal active
thread unless current Codex can fully control that thread through one
authoritative owner. For the account-switching failure, the practical root fix
available to us is to launch Codex with explicit account-scoped auth homes and
account-scoped daemon sockets, so there is no ambiguous owner for the resumed
thread.

## Evidence Snapshot

Local Mac relay evidence on 2026-06-06:

- `rtk make dock-relay-status` passed.
- `/readyz`, `/statusz`, and the app-facing `/readyz` checks passed.
- Relay status showed `privateOwners: 40`.
- Relay status showed `threadOwners: 0`.
- Relay live discovery showed `rows: 19`.
- Relay app-server registry showed `liveEndpoints: 12`.
- Relay app-server registry showed `unreachableObserved: 47`.
- Relay outbound user-message table had one fresh `failedDefinite` row.
- That row had error code `-32020`.
- That row's error message was:

```text
thread ... is owned by a private Codex runtime
```

Older successful outbound rows used `ws://127.0.0.1:4500/`, which is the old
local/raw path, not the current normal phone path through Dock relay `:4510`.

This explains the real-world symptom: the relay is healthy enough to show rows,
but the rows the user is touching are often not owned by an attachable runtime.

A focused private-runtime inventory at `2026-06-06T15:35:32.343Z` found 41
private-owner candidates. That count is one higher than the earlier relay status
snapshot because the live process set changed during the audit.

## Private Runtime Inventory

### How candidates were found

The inventory used the relay's own discovery model:

- `defaultProcessListProvider(...)` enumerated local Codex processes.
- `discoverAppServerEndpointsFromProcesses(...)` classified attachable
  endpoints and private owners.
- `codex-cli-resume` means the relay found a thread id in a Codex CLI resume
  process.
- `codex-cli-session-file` means the relay found a Codex CLI process with that
  session file open.

This audit intentionally did not capture or print command lines, prompt text,
transcript text, or full JSON-RPC payloads.

### Accessibility checks performed

For each private-owner PID, the audit checked:

- TCP listeners owned by the process with `lsof -nP -a -p <pid> -iTCP
  -sTCP:LISTEN -F n`.
- Connectable named Unix socket paths owned by the process with `lsof -nP -a
  -p <pid> -U -F n`. Anonymous Unix IPC file descriptors do not count as a
  Dock-attachable app-server endpoint.
- Whether any currently attachable app-server owner had the thread loaded, by
  calling `thread/loaded/list` after `initialize` on each discovered endpoint.

The same inventory also checked the Codex home socket surface:

```text
/Users/aelaguiz/.codex/vendor_imports/skills/.git/fsmonitor--daemon.ipc
/Users/aelaguiz/.codex/app-server-control/app-server-control.sock
```

The first path is Git filesystem-monitor IPC, not a Codex thread app-server.
The second path is the Codex daemon control socket. It was reachable, but
`thread/loaded/list` returned zero loaded owners during this audit.

The relay found 12 attachable endpoints:

| Endpoint | Reachable | Loaded thread owners |
| --- | --- | --- |
| `ws://127.0.0.1:59384/` | Yes | 0 |
| `ws://127.0.0.1:61964/` | Yes | 0 |
| `ws://127.0.0.1:55009/` | Yes | 0 |
| `ws://127.0.0.1:57064/` | Yes | 0 |
| `ws://127.0.0.1:64302/` | Yes | 0 |
| `ws://127.0.0.1:64792/` | Yes | 0 |
| `ws://127.0.0.1:64010/` | Yes | 0 |
| `ws://127.0.0.1:58962/` | Yes | 0 |
| `ws://127.0.0.1:54344/` | Yes | 0 |
| `ws://127.0.0.1:64569/` | Yes | 0 |
| `ws://127.0.0.1:54200/` | Yes | 0 |
| `unix:///Users/aelaguiz/.codex/app-server-control/app-server-control.sock` | Yes | 0 |

### Per-thread findings

Every private-runtime candidate had the same material result:

```text
No process-owned TCP listener.
No process-owned named Unix socket path.
No currently attachable app-server owner with the thread loaded.
```

That means these threads are inaccessible through the current Dock relay control
model. The audit did not find a hidden WebSocket listener, a hidden named Unix
app-server socket, or a loaded attachable app-server owner for any of them.

| Thread ID | PID | Owner evidence | PID TCP listener? | PID named Unix socket path? | Attachable loaded owner? | Finding |
| --- | ---: | --- | --- | --- | --- | --- |
| `019e9469-80b6-7161-b93a-136a3cd709c5` | 92805 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9482-fe61-7af0-a870-2c2df5089667` | 50819 | `codex-cli-resume` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9506-2b0f-7a80-bbd0-900756fd2f33` | 34587 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e977a-d9f0-7783-a98d-88ec1ad6348c` | 99648 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9789-d8cf-74a3-9a6a-b31a4f967402` | 68558 | `codex-cli-resume` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e97ab-3b2e-75d1-884b-b40b8f8397aa` | 44593 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e97c2-d33c-7ca2-b831-1b1318f5e402` | 44593 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e97c2-fe69-7f42-96b9-5e7bc6d3bf72` | 44593 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e97c3-1acc-7052-88d3-552f32f11034` | 44593 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e986a-5b88-7683-9094-d193cdb2e682` | 40734 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e98ac-77e1-7c92-bfe7-199fa977fbda` | 97200 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e98b9-4092-7be2-aa16-49a363ac32f8` | 76234 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e995f-daee-7d51-b73c-b3387939846b` | 85767 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e99c3-6cf6-71f3-ad6b-4705a3dd4298` | 99648 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e99c3-804e-7520-8481-04ba1fbc0a06` | 99648 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e99c3-93e3-7ef1-876f-66e411df8054` | 99648 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e99d6-09d4-7841-8c5f-66a38d256cc2` | 68558 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9a39-e466-7e40-8344-1567eaaa5407` | 99648 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9a39-fdad-7741-b710-04182e8a7ee8` | 99648 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9a3a-0cbf-7e03-a86a-7e0773788c69` | 99648 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9a7b-8fdf-7702-8425-7681eb0f689e` | 16601 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9a7c-8757-7751-9f76-73a101068b73` | 17594 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9aa6-9ebf-7c90-bf86-718a6ab8cab1` | 68558 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9aa6-b7db-7b31-b746-8affa458ce17` | 68558 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9ab7-2106-72a2-bec2-c8bba37646ed` | 97200 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9ab7-39f4-7ec0-a211-f94efde820d3` | 97200 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9ad0-8009-7fb0-8c15-9ef03ec8be5c` | 16283 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9adc-cfa5-7eb1-97d9-fdb9f6334d33` | 40603 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9adf-9860-79d1-b5f1-c0cd2dd8db7a` | 40603 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9adf-b2d2-73f2-874e-1f98fc565b43` | 40603 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9adf-d112-7371-9f4e-acbc82dd0eef` | 40603 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9aeb-58ea-7df1-a6a7-8e7b95a8e237` | 40603 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9aeb-5c27-7830-a82a-6ec6bbd1b952` | 40603 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9aeb-5e54-7d03-8159-b58222c65b4c` | 40603 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9c95-8920-7a63-83bc-f3644522719a` | 89797 | `codex-cli-resume` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9ca8-8473-7342-af21-a35d9629d66b` | 68705 | `codex-cli-resume` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9ccb-0d79-7111-929b-863c4123efc7` | 37876 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9cee-eb38-7e12-a7cf-fda540ec339f` | 81510 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9d90-b2a1-7913-9d20-1361c6c9b388` | 68558 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9d90-b4e1-7301-b8ae-9544f49c7e2a` | 68558 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |
| `019e9d90-b707-7071-8d7a-2715c1193087` | 68558 | `codex-cli-session-file` | No | No | None | Inaccessible by current Dock relay: no process socket and no attachable loaded owner found. |

### What this proves and does not prove

This proves that, at the time of the inventory, Dock had no concrete endpoint it
could use to control those private-runtime threads:

- no connectable app-server socket path owned by the private runtime process,
- no WebSocket listener owned by that process,
- no named Unix app-server socket owned by that process,
- no already-loaded owner in any discovered attachable app-server endpoint,
- and no loaded owner in the Codex daemon control socket.

It does not prove that Codex could never build a handoff, proxy, or takeover
API. It proves that the current Dock relay and current inspected Codex runtime
surface do not expose one. That is the architectural failure: these threads are
visible to Dock, but they do not have a present control path.

## Today-only Private Runtime Follow-up

The old `--tend` path explains stale loopback app-server processes from
2026-05-29 and 2026-05-30, but it does not explain new private threads created
on 2026-06-06.

A second pass filtered the live private-owner inventory to rollout files under:

```text
$CODEX_HOME/sessions/2026/06/06
```

That pass found 9 today-created private-owner threads:

- 8 on `Amir-M5`
- 1 on `home`, whose shell hostname is `amir-server`

All 9 were launched as plain Codex CLI/TUI runtimes:

```text
codex -p yolo
codex -p yolo resume <thread-id>
```

None were launched as:

```text
codex app-server --listen ...
```

### Today-created private-owner rows

| Thread ID | Machine | Rollout created | PID | Process started | Process shape | Owner evidence | TCP listener? | Named Unix socket path? | Anonymous Unix IPC FDs | Finding |
| --- | --- | --- | ---: | --- | --- | --- | --- | --- | ---: | --- |
| `019e9c95-8920-7a63-83bc-f3644522719a` | `Amir-M5` | `2026-06-06T05-58-26` | 89797 | `Sat Jun 6 10:32:53 2026` | `codex cli profile=yolo resume` | `codex-cli-resume` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9ca8-8473-7342-af21-a35d9629d66b` | `Amir-M5` | `2026-06-06T06-19-10` | 68705 | `Sat Jun 6 10:18:02 2026` | `codex cli profile=yolo resume` | `codex-cli-resume` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9ccb-0d79-7111-929b-863c4123efc7` | `Amir-M5` | `2026-06-06T06-56-53` | 37876 | `Sat Jun 6 06:56:53 2026` | `codex cli profile=yolo interactive` | `codex-cli-session-file` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9ccc-7b2b-7d83-a9c5-d55c09f9ec4d` | `home` / `amir-server` | `2026-06-06T06-58-27` | 2313541 | `Sat Jun 6 10:34:26 2026` | `codex cli profile=yolo resume` | `codex-cli-resume` | No | No | 6 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9cee-eb38-7e12-a7cf-fda540ec339f` | `Amir-M5` | `2026-06-06T07-36-04` | 81510 | `Sat Jun 6 07:36:03 2026` | `codex cli profile=yolo interactive` | `codex-cli-session-file` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9d89-b88b-7810-83c7-13f930e7394f` | `Amir-M5` | `2026-06-06T10-25-09` | 82987 | `Sat Jun 6 10:25:08 2026` | `codex cli profile=yolo interactive` | `codex-cli-session-file` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9d90-b2a1-7913-9d20-1361c6c9b388` | `Amir-M5` | `2026-06-06T10-32-46` | 68558 | `Fri Jun 5 09:35:31 2026` | `codex cli profile=yolo resume` | `codex-cli-session-file` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9d90-b4e1-7301-b8ae-9544f49c7e2a` | `Amir-M5` | `2026-06-06T10-32-47` | 68558 | `Fri Jun 5 09:35:31 2026` | `codex cli profile=yolo resume` | `codex-cli-session-file` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |
| `019e9d90-b707-7071-8d7a-2715c1193087` | `Amir-M5` | `2026-06-06T10-32-47` | 68558 | `Fri Jun 5 09:35:31 2026` | `codex cli profile=yolo resume` | `codex-cli-session-file` | No | No | 7 | Private CLI/TUI runtime; no Dock-attachable listener. |

The `anonymous Unix IPC FDs` column is included to avoid an imprecise
conclusion. These CLI processes do have local anonymous Unix IPC descriptors,
but they do not have a named Unix socket path that another process can connect
to as an app-server endpoint.

### Why new `codex -p yolo` threads have no listeners

`codex -p yolo` starts the Codex CLI/TUI surface. It does not start an external
app-server listener.

Codex TUI still uses app-server semantics internally, but it uses an
in-process app-server client:

```text
codex-rs/tui/src/lib.rs
codex-rs/app-server-client/src/lib.rs
codex-rs/app-server/src/in_process.rs
```

That in-process runtime uses in-memory channels. It is intentionally transport
local. There is no WebSocket URL, no Unix socket path, and no `thread/loaded/list`
endpoint for Dock to connect to from outside the process.

The `yolo` profile controls Codex runtime policy such as sandbox and approval
settings. It does not change the app-server transport. Running `codex -p yolo`
therefore creates a controllable terminal session for the human in that
terminal, but not a Dock-controllable app-server endpoint.

### Why some processes have app-server listeners

The processes with listeners are different commands:

```text
codex app-server --listen ws://127.0.0.1:<port> --enable goals
codex app-server --listen unix://
```

Those commands explicitly start app-server transports. The current `Amir-M5`
loopback WebSocket app-server processes all include `--enable goals` and were
started on 2026-05-29 or 2026-05-30. That is the old Tend private-app-server
shape, not the current today-created `codex -p yolo` shape.

The current `home` app-server process is:

```text
codex app-server --listen unix://
```

It is an app-server process, but it is not the owner of the new `home` thread
created today. The today-created `home` private thread is owned by:

```text
codex -p yolo resume <thread-id>
```

So the answer is not "some `codex -p yolo` starts get app servers and some do
not." The answer is:

```text
codex -p yolo starts a private CLI/TUI runtime with an in-process app-server.
codex app-server --listen ... starts an external app-server transport.
```

Dock can discover both process families, but only the second family has a
connectable endpoint.

### Host attribution note

The `home` shell audit ran over SSH and `hostname` returned:

```text
amir-server
```

However, `home`'s `.codex-dock/service.env` currently contains:

```text
CODEX_DOCK_REAL_HOST_ID=Amir-M5
CODEX_DOCK_REAL_HOST_NAME=Amir-M5
```

That means the `home` relay can identify itself as `Amir-M5` even though the
process audit is running on `home`. This is a host-labeling/configuration bug,
not the reason the today-created private thread has no listener.

## YOLO Profile And Daemon Reuse Audit

This follow-up checked whether the failure is just a `yolo` configuration
issue. The answer is: partly, but not in the simple sense of "add an app-server
listener setting to `yolo.config.toml`."

### Live `yolo` config shape

On `Amir-M5`, `codex -p yolo` loads:

```text
/Users/aelaguiz/.codex/yolo.config.toml
```

The relevant lines are:

```text
1:approval_policy = "never"
2:model = "gpt-5.5"
3:model_reasoning_effort = "xhigh"
4:model_reasoning_summary = "detailed"
5:model_verbosity = "high"
6:plan_mode_reasoning_effort = "xhigh"
7:sandbox_mode = "danger-full-access"
8:service_tier = "fast"
9:default-service-tier = "priority"
10:tool_output_token_limit = 25000
12:[features]
20:[tui]
```

On `home`, `codex -p yolo` loads:

```text
/home/aelaguiz/.codex/yolo.config.toml
```

The relevant lines are:

```text
1:model = "gpt-5.5"
2:model_reasoning_effort = "xhigh"
3:model_reasoning_summary = "detailed"
4:approval_policy = "never"
5:model_verbosity = "high"
6:sandbox_mode = "danger-full-access"
7:tool_output_token_limit = 25000
9:plan_mode_reasoning_effort = "xhigh"
10:service_tier = "fast"
12:[features]
```

Neither file contains an app-server transport setting. The inspected Codex CLI
surface exposes app-server transport through commands and flags:

```text
codex app-server --listen stdio://
codex app-server --listen unix://
codex app-server --listen unix://PATH
codex app-server --listen ws://IP:PORT
codex --remote unix://
codex --remote unix://PATH
codex --remote ws://host:port
```

No inspected config key makes `codex -p yolo` expose a listener from inside the
profile file.

### Profile v2 is the important switch

`codex --help` says:

```text
-p, --profile <CONFIG_PROFILE_V2>
Layer $CODEX_HOME/<name>.config.toml on top of the base user config
```

The source confirms that profile name resolution maps `yolo` to:

```text
$CODEX_HOME/yolo.config.toml
```

Source evidence:

```text
/Users/aelaguiz/workspace/codex/codex-rs/core/src/config/mod.rs:1577
/Users/aelaguiz/workspace/codex/codex-rs/core/src/config/mod.rs:1581
```

When the TUI sees a profile, it sets loader overrides before choosing the
app-server target:

```text
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:931
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:935
```

Then Codex decides whether it can reuse the implicit local daemon:

```text
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:867
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:878
```

That function only returns true when all of these are true:

- no `-c` CLI config overrides;
- loader overrides are default;
- strict config is off;
- there are no non-replayable launch overrides.

`-p yolo` makes loader overrides non-default. That makes
`can_reuse_implicit_local_daemon(...)` false.

After that, Codex only probes the default daemon socket when daemon reuse is
allowed:

```text
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:943
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:944
```

If reuse is false and no explicit `--remote` endpoint was passed, target
selection falls back to embedded:

```text
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:831
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:846
```

Embedded means in-process app-server:

```text
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:519
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:533
/Users/aelaguiz/workspace/codex/codex-rs/app-server-client/src/lib.rs:485
/Users/aelaguiz/workspace/codex/codex-rs/app-server-client/src/lib.rs:494
/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/in_process.rs:18
/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/in_process.rs:24
```

So the actual failure chain is:

```text
codex -p yolo
-> loads $CODEX_HOME/yolo.config.toml through profile-v2 loader overrides
-> loader overrides are no longer default
-> Codex refuses implicit local daemon reuse
-> Codex does not probe the existing daemon socket
-> Codex starts an embedded in-process app-server
-> Dock sees the thread in history/private-owner discovery, but has no listener to attach to
```

This is why today's threads are private even though both machines already have
daemon sockets.

### Existing daemon state on both machines

`Amir-M5` has a live daemon socket:

```text
/Users/aelaguiz/.codex/app-server-control/app-server-control.sock
```

`codex app-server daemon version` returned:

```json
{"status":"running","backend":"pid","managedCodexPath":"/Users/aelaguiz/.codex/packages/standalone/current/codex","managedCodexVersion":"0.132.0","socketPath":"/Users/aelaguiz/.codex/app-server-control/app-server-control.sock","cliVersion":"0.136.0-alpha.2","appServerVersion":"0.132.0"}
```

The daemon process is:

```text
85770     1 Wed May 27 20:04:34 2026 /Users/aelaguiz/.codex/packages/standalone/current/codex app-server --remote-control --listen unix://
```

Local daemon settings contain:

```json
{
  "remoteControlEnabled": true
}
```

`home` has a live daemon socket:

```text
/home/aelaguiz/.codex/app-server-control/app-server-control.sock
```

`ssh home 'codex app-server daemon version'` returned:

```json
{"status":"running","backend":"pid","managedCodexPath":"/home/aelaguiz/.codex/packages/standalone/current/codex","managedCodexVersion":"0.136.0-alpha.1","socketPath":"/home/aelaguiz/.codex/app-server-control/app-server-control.sock","cliVersion":"0.136.0-alpha.1","appServerVersion":"0.135.0-alpha.2"}
```

The `home` daemon process is:

```text
1660162       1 Thu May 28 19:40:28 2026 /home/aelaguiz/.nvm/versions/node/v22.18.0/bin/node /home/aelaguiz/.nvm/versions/node/v22.18.0/lib/node_modules/@openai/codex/bin/codex.js app-server --listen unix://
```

`home` does not currently have:

```text
/home/aelaguiz/.codex/app-server-daemon/settings.json
```

### Version mismatch risk

Even after fixing the launch shape, daemon version drift may still matter.

Current `Amir-M5` versions:

```text
CLI: 0.137.0
daemon managed Codex: 0.137.0
app-server: 0.137.0
```

Current `home` versions:

```text
CLI: 0.136.0-alpha.1
daemon managed Codex: 0.136.0-alpha.1
app-server: 0.135.0-alpha.2
```

This audit did not upgrade or restart either daemon. It only recorded that
daemon sockets exist and that profile/non-default launch shape can make the TUI
skip implicit daemon reuse.

### Is this fixable by config?

Near-term, probably yes, if "config" includes the launch shape:

```text
Move the yolo defaults into the base Codex config and stop launching with `-p yolo`.
```

Then a plain `codex` launch with no non-replayable overrides should be eligible
for implicit local daemon reuse when this socket exists:

```text
$CODEX_HOME/app-server-control/app-server-control.sock
```

Codex source tests confirm that default launches with a default daemon socket
target `AppServerTarget::LocalDaemon`, and non-replayable launch config falls
back to `AppServerTarget::Embedded`:

```text
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:2208
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:2226
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:2251
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:2262
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:2265
/Users/aelaguiz/workspace/codex/codex-rs/tui/src/lib.rs:2301
```

But this is not fixable by simply adding one key to
`$CODEX_HOME/yolo.config.toml`. The inspected profile file has no transport
setting, and the inspected TUI code chooses embedded before any profile-specific
runtime can expose a listener.

### Fixed-Codex design-around

The stronger fix is not "remember to avoid `-p yolo`." The stronger fix we can
actually own is to make the launcher and Dock relay obey current Codex's fixed
runtime contract:

```text
one account label
-> one CODEX_HOME
-> one auth.json / credential store
-> one app-server-control socket
-> one daemon auth cache
-> one Dock relay identity when exposed to the phone
```

That gives the app an owner it can reason about without patching Codex.

The usable launch rules are:

1. Put each Codex account in its own `CODEX_HOME`.
2. Login once inside each account home.
3. Start or resume sessions with that same `CODEX_HOME`.
4. Use explicit `--remote unix://` when the session must be Dock-controllable
   through the account's daemon socket.
5. Use `-C "$PWD"` to preserve the intended workspace root; it is not the
   account selector.
6. Prefer moving `yolo` defaults into each account's base config. If `-p yolo`
   is still used, keep explicit `--remote unix://` so the profile does not
   silently create a private embedded runtime.

The safe command shape is:

```bash
CODEX_HOME="$HOME/.codex-accounts/personal" codex --remote unix:// -C "$PWD"
CODEX_HOME="$HOME/.codex-accounts/personal" codex --remote unix:// -C "$PWD" resume <thread-id>
```

If the profile is still needed:

```bash
CODEX_HOME="$HOME/.codex-accounts/personal" codex -p yolo --remote unix:// -C "$PWD" resume <thread-id>
```

Net: this is a real root cause for the June 6 failures. The daemon can exist and
still be the wrong owner if it shares auth across account switches, or Codex can
start a private embedded runtime that exposes no Dock-attachable listener. The
fix available to this repo is account-scoped launch and relay discipline, plus
Dock capability checks before the composer is enabled.

## Multi-account Codex CLI Launch Audit

This follow-up investigated a separate but related failure seen on `home` /
`amir-server` while running:

```bash
codex -p yolo --remote unix:// -C "$PWD" resume 019e99ca-c68a-7e93-8c8d-67d10f229975
```

The user-visible failure was:

```text
Your access token could not be refreshed because you have since logged out or signed in to another account. Please sign in again.
```

The important correction is that this is not a Codex Dock failure. It happens
inside Codex itself. Dock can observe the bad state and should avoid presenting
it as a normal sendable conversation, but the account/runtime failure is caused
by how Codex CLI, Codex auth, and the Codex app-server daemon are launched.

### Home-server evidence

On `home`, `codex app-server daemon version` returned:

```json
{"status":"running","backend":"pid","managedCodexPath":"/home/aelaguiz/.codex/packages/standalone/current/codex","managedCodexVersion":"0.136.0-alpha.1","socketPath":"/home/aelaguiz/.codex/app-server-control/app-server-control.sock","cliVersion":"0.136.0-alpha.1","appServerVersion":"0.135.0-alpha.2"}
```

The daemon process had been running since:

```text
Thu May 28 19:40:28 2026
```

The default Codex home in the SSH shell was:

```text
CODEX_HOME=/home/aelaguiz/.codex
```

The default bare Unix remote:

```text
unix://
```

resolves to:

```text
$CODEX_HOME/app-server-control/app-server-control.sock
```

For this shell, that means:

```text
/home/aelaguiz/.codex/app-server-control/app-server-control.sock
```

Read-only socket proof showed that the daemon could see thread
`019e99ca-c68a-7e93-8c8d-67d10f229975` and that the thread was loaded, but its
status was:

```json
{"type":"systemError"}
```

The same daemon stderr log contained repeated auth refresh failures during the
repro window, from `2026-06-06T15:59:26Z` through
`2026-06-06T16:01:54Z`:

```text
Failed to refresh token: Your access token could not be refreshed because you have since logged out or signed in to another account. Please sign in again.
```

Those timestamps match the user repro around `11:02 AM CDT` on
2026-06-06.

### Source evidence

Codex source confirms the account coupling:

- `codex-rs/tui/src/lib.rs:407`: `unix://` with no path resolves from the
  active Codex home.
- `codex-rs/app-server-transport/src/transport/mod.rs:50`: the default control
  socket is `$CODEX_HOME/app-server-control/app-server-control.sock`.
- `codex-rs/app-server/src/lib.rs:702`: a daemon app-server creates one
  `AuthManager` from its config.
- `codex-rs/login/src/auth/manager.rs:1246`: `AuthManager` is a cached single
  source of truth; external changes to `auth.json` are not observed until
  explicit reload.
- `codex-rs/login/src/auth/manager.rs:1450`: token refresh only reloads auth
  from disk when the on-disk account id still matches the cached account id.
- `codex-rs/login/src/auth/manager.rs:1709`: if the guarded reload is skipped,
  Codex returns a permanent refresh failure.
- `codex-rs/login/src/auth/manager.rs:94`: the permanent failure message is the
  exact user-facing string about having logged out or signed into another
  account.
- `codex-rs/login/src/auth/storage.rs:84`: file auth storage is
  `$CODEX_HOME/auth.json`.
- `codex-rs/login/src/auth/storage.rs:136`: file auth save writes that same
  account store.

So the practical model is:

```text
one CODEX_HOME
-> one auth.json / credential store
-> one default app-server-control socket
-> one daemon auth cache
-> unsafe for multiple concurrently switched Codex accounts
```

### Why `-C "$PWD"` is not the auth cause

`-C "$PWD"` is still useful, but it is not the account switch. In the inspected
TUI source, `-C` supplies the remote working-directory override for
`thread/start`, `thread/resume`, and `thread/fork`.

The account behavior comes from:

```text
--remote unix://
```

because that selects the daemon socket under the active `$CODEX_HOME`.

### Required launch model for multiple accounts

For multiple accounts, a launch must make account identity explicit before Codex
chooses the daemon socket. The clean rule is:

```text
one Codex account = one CODEX_HOME = one auth store = one daemon socket
```

That means account A should not share this with account B:

```text
/home/aelaguiz/.codex/auth.json
/home/aelaguiz/.codex/app-server-control/app-server-control.sock
```

Instead, each account needs its own home, for example:

```text
/home/aelaguiz/.codex-accounts/personal
/home/aelaguiz/.codex-accounts/work
/home/aelaguiz/.codex-accounts/client
```

Then each account gets a separate default socket:

```text
/home/aelaguiz/.codex-accounts/personal/app-server-control/app-server-control.sock
/home/aelaguiz/.codex-accounts/work/app-server-control/app-server-control.sock
/home/aelaguiz/.codex-accounts/client/app-server-control/app-server-control.sock
```

The intended launch shape is:

```bash
CODEX_HOME="$HOME/.codex-accounts/personal" codex --remote unix:// -C "$PWD"
CODEX_HOME="$HOME/.codex-accounts/work" codex --remote unix:// -C "$PWD"
CODEX_HOME="$HOME/.codex-accounts/client" codex --remote unix:// -C "$PWD"
```

And resume under the intended account by using that same `CODEX_HOME`:

```bash
CODEX_HOME="$HOME/.codex-accounts/personal" codex --remote unix:// -C "$PWD" resume <thread-id>
CODEX_HOME="$HOME/.codex-accounts/work" codex --remote unix:// -C "$PWD" resume <thread-id>
CODEX_HOME="$HOME/.codex-accounts/client" codex --remote unix:// -C "$PWD" resume <thread-id>
```

This does not magically make a thread usable under the wrong account. It makes
the account boundary explicit. If a thread was created under account A, resuming
it under account B may still fail because the upstream account/workspace is
different. The improvement is that account A and account B no longer fight over
the same daemon cache and same `auth.json`.

### What the launcher should become

The recommended CLI wrapper should take an account label and set `CODEX_HOME`
before invoking Codex:

```bash
codex-account personal --remote unix:// -C "$PWD"
codex-account work --remote unix:// -C "$PWD"
codex-account client --remote unix:// -C "$PWD"
```

Conceptually that wrapper expands to:

```bash
CODEX_HOME="$HOME/.codex-accounts/<account-label>" codex --remote unix:// -C "$PWD" "$@"
```

It should also avoid `-p yolo` once the yolo defaults have been moved into that
account's base config, because `-p yolo` currently makes Codex skip implicit
daemon reuse. If the wrapper uses explicit `--remote unix://`, it can still use
profile flags, but the safer long-term model is account-local base config plus
explicit daemon routing.

### What Dock relay should do for parallel accounts

Codex Dock already has the repo knobs needed for account-scoped relay launches:

```text
CODEX_HOME
APP_SERVER_DIR
DOCK_RELAY_PORT
CODEX_DOCK_REAL_HOST_ID
CODEX_DOCK_REAL_HOST_NAME
```

The evidence is:

- `Makefile:1`: `APP_SERVER_DIR ?= .codex-dock`
- `Makefile:2`: `CODEX_HOME ?=`
- `Makefile:6`: `DOCK_RELAY_PORT ?= 4510`
- `Makefile:49`: `CODEX_DOCK_REAL_HOST_ID ?=`
- `Makefile:50`: `CODEX_DOCK_REAL_HOST_NAME ?=`
- `Makefile:145`: `HOST_SERVICE_CODEX_HOME_ARG` passes `--codex-home`.
- `scripts/codex-dock-host-service.mjs:360`: host service reads `--codex-home`
  or `CODEX_HOME`.
- `scripts/codex-dock-host-service.mjs:533`: service env includes `CODEX_HOME`
  when configured.
- `scripts/dock-relay.mjs:1703`: relay config uses `--codex-home`,
  `CODEX_HOME`, or `~/.codex`.

For one active account relay, this is enough:

```bash
CODEX_HOME="$HOME/.codex-accounts/personal" rtk make services
```

For multiple account relays in parallel, every relay also needs a distinct
runtime directory, port, and host identity:

```bash
CODEX_HOME="$HOME/.codex-accounts/personal" \
APP_SERVER_DIR=".codex-dock-personal" \
DOCK_RELAY_PORT=4511 \
CODEX_DOCK_REAL_HOST_ID="home-personal" \
CODEX_DOCK_REAL_HOST_NAME="Home Personal" \
rtk make services

CODEX_HOME="$HOME/.codex-accounts/work" \
APP_SERVER_DIR=".codex-dock-work" \
DOCK_RELAY_PORT=4512 \
CODEX_DOCK_REAL_HOST_ID="home-work" \
CODEX_DOCK_REAL_HOST_NAME="Home Work" \
rtk make services
```

The phone should then treat those as separate hosts. Do not collapse them into a
single `home` row because the relay identity is now part of the account/runtime
boundary.

### Explicit non-solution

Do not make upstream Codex changes part of this repo's recommendation. The
possible fixes here are:

- launch wrappers that select the correct `CODEX_HOME`,
- account-local Codex config,
- Dock relay launches that use the matching `CODEX_HOME`,
- distinct relay runtime directories, ports, and host IDs for parallel accounts,
- relay capability classification for `systemError`, private runtime, history
  only, and not-loaded rows,
- app UI that disables send/control actions until the row is controllable.

Net: the immediate fix is account-scoped `CODEX_HOME` values and account-scoped
daemon sockets. The durable fix available to Codex Dock is to make account and
runtime ownership explicit at launch and in row capability state instead of
inferring sendability from whichever shared `auth.json` happens to be active.

## AIMgr Account Runtime Audit

This follow-up changes the lens: upstream Codex is a fixed dependency for this
project. The layers we can change are AIMgr, Codex Dock, launch commands, relay
configuration, tests, and docs. Under that constraint, AIMgr is the right owner
for account-scoped Codex launches because the user already uses `aim codex use`
and AIMgr already owns Redis-backed Codex account selection.

The missing invariant is not "one account owns one whole home." That breaks the
thing AIMgr is trying to do: continue one work session after the current account
runs out. The corrected invariant is:

```text
one logical Codex run = one stable session continuity namespace
one account epoch = one isolated auth.json + one isolated daemon socket
account rotation = move the run to a new account epoch without losing sessions
```

Today AIMgr does not enforce that invariant for Codex.

### AIMgr source evidence

AIMgr is a Node CLI in `/Users/aelaguiz/workspace/aimgr`, not a Go service. It is
changeable and is the correct place to encode account/runtime ownership. The
current Codex path is still global by default:

- `src/io/paths.js:113`: `resolveManagedCodexHomeDir({ homeDir, env })` first
  respects `env.CODEX_HOME`.
- `src/io/paths.js:118`: if no `CODEX_HOME` is present, it returns
  `path.join(homeDir, ".codex")`.
- `src/targets/codex-cli.js:49`: `applyCodexCliFromState` resolves that one
  managed home for any selected label.
- `src/targets/codex-cli.js:53`: it writes the selected label's Codex
  `auth.json` into that home.
- `src/targets/codex-cli.js:64-68`: it records `target.homeDir`,
  `target.activeLabel`, `target.expectedAccountId`, and `target.lastAppliedAt`.
- `src/cli/commands/codex.js:20-30`: `aim codex use <label>` calls
  `activateCodexLabelSelection` and writes the Redis view into local state.
- `src/cli/commands/codex.js:236-244`: non-Redis `aim codex use` does the same
  projection.
- `src/targets/codex-cli.js:221-224`: watch/tend preservation also reads live
  Codex auth from that same managed home.
- `src/targets/codex-tender.js:362-363`: Tend resolves one Codex home and uses
  `sessions` under that home.
- `src/targets/codex-tender.js:403-430`: Tend starts the child process with
  inherited env plus a start-only originator override; it does not force
  `CODEX_HOME` unless the parent env already had one.
- `src/targets/codex-tender.js:115-126`: Tend rejects user-supplied `--remote`
  and `--remote-auth-token-env`.
- `src/targets/codex-tender.js:164-172`: Tend launches
  `codex --no-alt-screen`, optional `-p`, and optional `resume`; it does not
  launch a Dock-controllable Codex daemon path.
- `README.md:120-126`: AIMgr documents that `aim codex run --tend` does not use
  a private Codex app-server or Codex `--remote`, and pass-through `--remote`
  args are forbidden.
- `README.md:171-174`: AIMgr documents the current Codex projection target as
  `~/.codex/auth.json`.
- `README.md:199-205`: AIMgr tests warn to run with `env -u CODEX_HOME` because
  an inherited `CODEX_HOME` can point tests at a real Codex home.

That means `CODEX_HOME` is already the escape hatch, but the normal AIMgr path
does not choose a runtime-scoped home. Without a manual env override, `aim codex
use pro4` on this Mac writes into `/Users/aelaguiz/.codex/auth.json`; on `home`,
the same pattern writes into `/home/aelaguiz/.codex/auth.json`.

### Live AIMgr proof on 2026-06-06

The local shell had no `CODEX_HOME` set:

```text
HOME=/Users/aelaguiz
```

AIMgr Redis config was live at:

```text
redis://amirs-mac-studio:6380
```

`aim status --json` showed the current Codex target as:

```text
homeDir=/Users/aelaguiz/.codex
authPath=/Users/aelaguiz/.codex/auth.json
storeMode=file
activeLabel=pro4
inferredLabel=pro4
lastSelectionReceipt.previousLabel=pro3
lastSelectionReceipt.label=pro4
lastSelectionReceipt.observedAt=2026-06-06T15:32:48Z
```

The account id and credential payload were intentionally not copied into this
audit. The relevant fact is that a real `aim codex use` rotation on this machine
selected `pro4` by overwriting the shared Codex target home, not by selecting a
run-owned runtime home or account epoch.

### Current failure chain

With fixed upstream Codex, this is the failure path that matters:

```text
aim codex use pro3
-> writes /Users/aelaguiz/.codex/auth.json for account pro3
-> codex --remote unix:// starts or reuses /Users/aelaguiz/.codex/app-server-control/app-server-control.sock
-> daemon builds one in-memory AuthManager for pro3
-> aim codex use pro4
-> overwrites /Users/aelaguiz/.codex/auth.json for account pro4
-> the existing daemon still has cached pro3 auth
-> token refresh cannot safely reload because disk now says pro4
-> Codex reports the signed-out / signed-into-another-account refresh failure
-> Dock sees loaded, history-readable, or systemError rows that cannot send
```

This is why a thread can look present but fail every send. The problem is not
that Dock has a bad word for the UI state. The deeper problem is that the
thread/runtime/account ownership boundary is wrong.

### Why pure label homes are wrong

The earlier "one Codex label = one Codex home" model is not sufficient. It fixes
auth isolation by splitting the entire home, but it also splits the session
corpus. That conflicts with AIMgr's job.

AIMgr Tend currently works like this:

- `src/targets/codex-tender.js:362-363`: it resolves one Codex home, then uses
  `sessions` under that home.
- `src/targets/codex-rollout.js:147-161`: for a new goal, it binds the owned
  thread by scanning rollout files under that `sessions` directory.
- `src/targets/codex-rollout.js:164-184`: for a known thread, it finds the
  rollout for the session id in that same `sessions` directory.
- `src/targets/codex-tender.js:561-588`: on `usageLimited`, it rotates account,
  exits the old session, and starts Codex again in `resume` mode.
- `test/codex/codex-10.cases.js:699-740`: the expected behavior is one
  `usageLimited` goal, one account rotation, and a second Codex start with
  `codex --no-alt-screen resume <same-session-id>`.

So AIMgr is not only an account selector. It is a continuity engine: keep the
same work going when the current account is exhausted. A design that hides the
old rollout under another account's `$CODEX_HOME/sessions` breaks that.

### Claude is only a partial precedent

AIMgr's Claude path proves that per-label projection is possible:

- `src/io/paths.js:78-83`: `resolveAimgrClaudeLabelHomeDir` builds
  `~/.aimgr/claude-homes/<label>`.
- `src/cli/commands/claude.js:125-133`: `aim claude run <label>` resolves that
  label home, creates it, and projects the Redis-backed Claude credential there.
- `src/cli/commands/claude.js:151-155`: the launched Claude process receives the
  label-owned home.
- `test/cli/redis-projection-command.test.js:284-344`: tests assert Claude
  runs from a per-label home and records a `claude-homes/<label>` path in local
  state.

Codex cannot copy that shape directly because Codex puts auth, daemon socket,
rollout sessions, archived sessions, history, config, plugins, trust, and state
database concerns under one `$CODEX_HOME`. For Codex, AIMgr needs a composed
runtime home, not a naive label home.

### Required AIMgr model

AIMgr should model three separate things:

```text
account credential:       pro4, pro5, ...
logical run/thread:       the work that must continue
account epoch/runtime:    one launch of that run under one account
```

The durable filesystem shape should look more like this:

```text
~/.aimgr/codex-sessions/                  # shared session continuity store
  sessions/
  archived_sessions/

~/.aimgr/codex-runtimes/<run-id>/
  current -> epochs/<epoch-id>
  epochs/
    pro4-20260606T153248Z/
      auth.json                           # pro4 only
      config.toml                         # generated/copied safe config
      sessions -> ~/.aimgr/codex-sessions/sessions
      archived_sessions -> ~/.aimgr/codex-sessions/archived_sessions
      app-server-control/
    pro5-20260606T160501Z/
      auth.json                           # pro5 only
      config.toml
      sessions -> ~/.aimgr/codex-sessions/sessions
      archived_sessions -> ~/.aimgr/codex-sessions/archived_sessions
      app-server-control/
```

The exact directory names can change. The required property is that session
history stays visible across account rotation while auth and sockets do not.

### Session copying is an open mechanism question

Copying or adopting session files might be part of a correct migration or
rotation design, but it is not proven yet. The distinction that matters is not
"copy" versus "symlink"; it is whether the system creates multiple live truth
sources for the same thread.

Risky version:

```text
epoch A has one copy of sessions/
epoch B has another copy of sessions/
both remain visible or writable as independent stores
```

Likely failures in that shape are stale thread lists, resume misses, duplicate
rollout files, archive drift, state DB rows pointing at old copies, and two
runtimes writing the same thread after rotation.

Potentially valid versions:

```text
one-time migration:
  copy sessions/ from legacy ~/.codex into the AIMgr run store
  -> stop using the legacy copy for this run

handoff/adoption:
  copy or move the selected thread files into the new run store
  -> fence the old owner before the new epoch writes

projection:
  expose one backing run store at each epoch's $CODEX_HOME/sessions
```

The required property is one effective session corpus for a logical run after
handoff completes. An account epoch home can expose that corpus at
`$CODEX_HOME/sessions` and `$CODEX_HOME/archived_sessions` through copying,
moving, symlinks, or another projection, but the design must prove that old
copies cannot keep acting as active truth sources.

AIMgr must also enforce one active writer for a thread at a time. During
rotation, it must stop or fence the old epoch before the new epoch writes to the
same logical thread.

### Codex SQLite state is a separate proof target

Codex does not persist only rollout JSONL files. Local Codex source shows:

- `sqlite_home` defaults to `$CODEX_SQLITE_HOME` when set; otherwise it uses
  `$CODEX_HOME`.
- SQLite files are `state_5.sqlite`, `goals_1.sqlite`, `logs_2.sqlite`, and
  `memories_1.sqlite`.
- rollout backfill scans `$CODEX_HOME/sessions` and
  `$CODEX_HOME/archived_sessions`.

That means "shared sessions" is necessary but not enough. The correct AIMgr
design must explicitly choose and test one SQLite strategy:

1. Set `CODEX_SQLITE_HOME` to a stable run-level SQLite home while each account
   epoch keeps its own `CODEX_HOME` auth/socket area.
2. Keep SQLite epoch-local and prove Codex can rebuild all required
   list/resume/goal state from the shared backing rollout corpus after
   rotation.
3. Share selected SQLite files through a stable run-level DB home and prove
   locking/WAL behavior is safe with the one-active-writer invariant.

Until one of those strategies is proven against real Codex CLI behavior, the
architecture is incomplete. Session projection and SQLite continuity are two
separate requirements.

`aim codex use` should not silently mutate `~/.codex/auth.json` as the normal
path anymore. If legacy global-home behavior remains available, it should be
explicit, for example `--legacy-global-home`, and status should call it out as
unsafe for parallel work.

AIMgr should also copy or generate the Codex config needed inside each runtime
epoch home. At minimum:

- ensure file-backed auth mode,
- carry the user's yolo defaults into the runtime epoch home or reference a shared
  config safely,
- avoid profile behavior that accidentally starts a private embedded runtime
  when the user intended Dock control,
- keep secrets on the machine side.

### Required AIMgr launch surface

`aim codex use` should be a projection/status operation, but it should not be
the only thing a human relies on. AIMgr needs a Codex launch command that makes
the run and label explicit before Codex chooses an auth store or daemon socket.

One acceptable shape:

```bash
aim codex launch --label pro4 -- -C "$PWD"
aim codex launch --label pro4 --resume <thread-id> -- -C "$PWD"
```

Conceptually, for a new run that command expands to a generated runtime epoch:

```bash
CODEX_HOME="$HOME/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>" \
codex --remote unix:// -C "$PWD"
```

For a resume, it reuses the same shared session store but creates or selects an
epoch for the intended account:

```bash
CODEX_HOME="$HOME/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>" \
codex --remote unix:// -C "$PWD" resume <thread-id>
```

The exact command name can change, but the invariant cannot: the AIMgr label
and runtime epoch must be resolved before the Codex process starts.

### Tend under this model

Current `aim codex run --tend` is closest to the desired continuity behavior. It
already watches owned goal state, rotates on `usageLimited`, exits the old Codex
process, and resumes the same session id. The broken part is that all of this is
currently anchored to one shared Codex home.

Tend should become runtime/epoch scoped:

```text
start run under pro4 epoch home
-> bind thread id from shared sessions
-> detect usageLimited on owned goal
-> preserve live auth for pro4
-> create pro5 epoch home with same shared sessions
-> stop old Codex process
-> start `codex resume <same-thread-id>` with CODEX_HOME=pro5 epoch home
-> verify goal becomes active again
```

Current Tend intentionally rejects Codex `--remote` and runs through AIMgr's
foreground relay. That can remain true for the TUI path, but it does not produce
the daemon socket Dock needs.

Therefore AIMgr needs one of these explicit choices:

1. Keep Tend as a separate automation mode, but make it runtime-epoch scoped so
   it does not corrupt shared `~/.codex`, and make sessions shared across
   account epochs.
2. Add a new Dock-oriented run mode, for example `aim codex run --dock <label>`
   or `aim codex launch`, that starts Codex with `--remote unix://` from the
   active runtime epoch.
3. Teach Tend a separate daemon-backed mode, but only if its PTY/rollout
   assumptions still hold when Codex is remote-controlled.

Do not treat current Tend as the Dock fix. It addresses goal tending and account
rotation, but the current source explicitly rejects the remote app-server path.

### Watch and rotation under this model

`aim codex watch` should not rotate a running daemon by overwriting that
daemon's `auth.json` with a different account. With fixed upstream Codex, that
is the unsafe action.

The safe rotation behavior is:

```text
detect current label is exhausted
-> choose next label
-> create the next account epoch for the same logical run
-> point that epoch at the shared session store
-> launch or resume under that epoch home
-> keep the old epoch home and old daemon separate or explicitly shut them down
```

If a thread belongs to account A and account B cannot resume it, the failure
should be explicit: `wrong_account_for_thread` or equivalent. The system should
not present it as a generic send failure or leave the app in terminal `Check`.

### Required AIMgr status output

AIMgr status should expose enough information for Dock and humans to detect the
bad state before sending:

```text
codexCli.homeMode=runtime-epoch | legacy-global
codexCli.runId=<run-id>
codexCli.threadId=<thread-id or null before bind>
codexCli.activeLabel=pro4
codexCli.activeEpochHome=/Users/aelaguiz/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>
codexCli.sessionStore=/Users/aelaguiz/.aimgr/codex-sessions
codexCli.authPath=/Users/aelaguiz/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>/auth.json
codexCli.socketPath=/Users/aelaguiz/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>/app-server-control/app-server-control.sock
codexCli.expectedAccountId=<redacted or summarized>
codexCli.actualAccountId=<redacted or summarized>
codexCli.daemonRunning=true | false
codexCli.daemonAccountMatches=true | false | unknown
```

The status output should keep tokens and raw credential bodies out of terminal
and logs.

### Dock relay integration through AIMgr

Codex Dock already accepts the knobs needed for account-specific relays:

```text
CODEX_HOME
APP_SERVER_DIR
DOCK_RELAY_PORT
CODEX_DOCK_REAL_HOST_ID
CODEX_DOCK_REAL_HOST_NAME
```

AIMgr can become the human-facing launcher for those relays. The current manual
shape for a runtime epoch is:

```bash
CODEX_HOME="$HOME/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>" \
APP_SERVER_DIR=".codex-dock-<run-id>-pro4" \
DOCK_RELAY_PORT=4511 \
CODEX_DOCK_REAL_HOST_ID="m5-<run-id>-pro4" \
CODEX_DOCK_REAL_HOST_NAME="M5 <run-id> pro4" \
rtk make services
```

The AIMgr-owned future shape could be:

```bash
aim codex dock-relay <run-id> --label pro4 --port 4511
```

The phone should treat relay identity as runtime ownership, not as a permanent
account. During rotation, the logical thread can stay the same while the owning
runtime epoch changes. The app should show a short migrating/unavailable state,
disable send while no epoch is controllable, then re-enable send once the new
epoch has loaded the thread.

### Diagnostic command shape is not the fix

The env-based command shape is useful only as diagnostic proof that isolated
account epochs solve the auth/socket collision. It also demonstrates why pure
label homes are incomplete: without shared `sessions`, a later account cannot
find and resume the original run. It should not be treated as the product answer
because it depends on a human never forgetting to pass the same `CODEX_HOME`
through every related command and does not model session continuity.

```bash
CODEX_HOME="$HOME/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>" aim codex use pro4
CODEX_HOME="$HOME/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>" codex --remote unix:// -C "$PWD"
CODEX_HOME="$HOME/.aimgr/codex-runtimes/<run-id>/epochs/pro4-<timestamp>" codex --remote unix:// -C "$PWD" resume <thread-id>
```

The correct fix is to make that expansion internal to AIMgr. A later plain
`aim codex use` with no `CODEX_HOME` must not be able to drift back to the
shared global `~/.codex` target.

### Correct fix shape

The right fix is not "teach people a safer command." The right fix is to remove
the unsafe command path from normal use:

```text
aim codex use pro4
-> AIMgr resolves the logical run and active account epoch
-> AIMgr writes auth/config only inside that epoch home
-> AIMgr links that epoch home to the run's shared sessions
-> AIMgr records activeLabel, runId, threadId, activeEpochHome, and sessionStore
-> AIMgr launches Codex with CODEX_HOME already set to that epoch home
-> Codex creates/reuses only that epoch home's daemon socket
-> Codex Dock relay connects to that same epoch home
-> phone sees a relay identity that is account/runtime scoped
```

The old global target can remain only as an explicit legacy/debug mode. It
should be visibly unsafe in status output and should not be the default for
`aim codex use`, `aim codex launch`, `aim codex watch`, or a Dock-facing Tend
mode.

### AIMgr implementation map

The AIMgr changes needed are:

1. Add runtime records for Codex runs: `runId`, optional `threadId`, shared
   `sessionStore`, `activeLabel`, `activeEpochHome`, and epoch history.
2. Add a runtime-home builder that creates per-account epoch homes and links
   `sessions` / `archived_sessions` to the run's shared session store.
3. Define and test the Codex SQLite continuity strategy for that run: shared
   `CODEX_SQLITE_HOME`, epoch-local rebuild from the shared rollout corpus, or
   explicitly shared DB files with locking proof.
4. Update `applyCodexCliFromState`, `readCodexCliTargetStatus`,
   `preserveLiveCodexAuthForActiveLabel`, `aim codex use`, and `aim codex watch`
   to operate on the selected runtime epoch instead of global `~/.codex`.
5. Ensure each epoch home has file-backed Codex auth config and the user's
   intended Codex defaults.
6. Update Tend so account rotation creates/selects the next epoch home, sets
   child `CODEX_HOME`, and resumes the same thread id from the shared session
   store.
7. Add an AIMgr Codex launch command that sets `CODEX_HOME` to the epoch home
   and uses `codex --remote unix://` for Dock-controllable sessions.
8. Keep Tend either runtime-epoch scoped but non-Dock, or add a separate
   daemon-backed Tend mode.
9. Update AIMgr tests that currently assert `.codex/auth.json` so they assert
   epoch-local `auth.json` plus shared session visibility.
10. Add tests proving that `aim codex use pro3` and `aim codex use pro4` do not
   overwrite each other, that rotation can resume the same session id under a
   new account epoch, that child launches receive the intended `CODEX_HOME`, and
   that status exposes run id, epoch home, session store, home mode, and socket
   path without secrets.
11. Add Codex Dock proof that account-epoch relays use distinct runtime dirs,
    ports, host IDs, and app capability state while preserving logical thread
    continuity across rotation.

Net: with fixed Codex, the architectural answer is not to patch Codex. The
answer is to make AIMgr stop treating Codex as one mutable global target while
also not splitting session history by account. AIMgr needs runtime homes with
shared sessions and isolated account epochs, and Codex Dock needs to consume
explicit runtime ownership instead of assuming visibility means sendability.

## Terms

These states are currently collapsed together too often:

| Term | Meaning | Current problem |
| --- | --- | --- |
| Visible | The row appears in Dock's list. | Visibility can come from history or private-owner presence. |
| Readable | The relay can reconstruct detail from persisted rollout history. | Readable does not imply live control. |
| Loaded | A Codex app-server process has the thread in its in-process `ThreadManager`. | `turn/start` requires this. |
| Subscribed | The phone connection has a live `thread/detail/subscribe` listener. | Private-owner fallback can return a history snapshot instead. |
| Sendable | `turn/start` or `turn/steer` can be routed to the real owner. | Many visible rows are not sendable. |
| Owned | One runtime is the active writer/controller for the thread. | Dock infers this outside Codex for private CLI processes. |
| Controllable | Read, live subscribe, send, interrupt, approve, and other controls work. | This should be the main app invariant, but it is not. |

The product invariant should be:

```text
Main Dock row = controllable thread
```

The current implementation often behaves like:

```text
Main Dock row = visible or historically readable thread
```

That is the wrong abstraction for a phone app.

## Dock Architecture Findings

### 1. The relay lists threads from history first

`scripts/dock-relay-thread-data.mjs` builds the Dock thread list by reading
Codex history through `thread/list`, filtering to human-facing rows, enriching
them, and merging live supplements.

That is useful for discovering work, but it means the primary row source is not
"threads currently controllable by a phone-facing owner." It is "threads the
history daemon can list and read."

This creates the first split:

```text
listed thread != loaded/control-owned thread
```

### 2. Private runtime presence is represented as live-ish row data

`scripts/dock-relay-app-server-registry.mjs` records private Codex owners and
exposes them as `privateLiveRows()` with:

```text
status.type = privateUnattachable
dockRelaySource.endpointType = private
dockRelaySource.transport = stdio
dockRelaySource.failure.reason = private_transport
```

The relay then merges those private rows into live status via
`mergePrivateLiveRows(...)`.

This is useful as status evidence, but it is not control evidence. A private
`stdio` runtime is explicitly not attachable by the relay.

### 3. The relay allows read paths for private owners but blocks control paths

`scripts/dock-relay-app-server-registry.mjs` has three relevant method buckets:

- `LIVE_OWNER_PREFERRED_METHODS`
- `ACTIVE_SESSION_ONLY_METHODS`
- `HISTORY_SAFE_PRIVATE_OWNER_METHODS`

`HISTORY_SAFE_PRIVATE_OWNER_METHODS` includes:

```text
thread/read
thread/turns/list
thread/name/set
```

It does not include:

```text
thread/resume
thread/detail/subscribe
thread/message/send
turn/start
turn/steer
turn/interrupt
thread/archive
```

When a private owner exists and no attachable live owner exists,
`routeForThreadMethod(...)` throws:

```text
thread <id> is owned by a private Codex runtime
```

That is a deliberate read/control split. It prevents the relay from pretending
it can drive a private process, but it also proves that the app can show a row it
cannot control.

### 4. Thread Detail silently falls back to history for private owners

`scripts/dock-relay.mjs` handles `thread/detail/subscribe` like this:

1. Try `resumeThread(...)`.
2. If the error is `private_owner_unattachable`, return
   `readHistoryBackedThreadDetailSnapshot(...)`.

That fallback is the second major architectural bug. The method name says
`thread/detail/subscribe`, but for private owners the user can receive a
history-backed snapshot instead of a live subscription.

That means the UI can look like it opened a real active conversation, even
though the relay failed to attach to the controlling runtime.

### 5. The send path assumes a route to `turn/start` or `turn/steer`

`scripts/dock-relay-user-message-command.mjs` handles `thread/message/send`.

Its `submitToCodex(...)` behavior is:

- if the current downstream session is already actively resumed to this thread,
  send through that active upstream session;
- otherwise pick `turn/steer` if an active turn is known;
- otherwise pick `turn/start`;
- ask the app-server registry for a route to that method.

For a private-owned thread, that route fails. For a merely history-visible
thread, `turn/start` can only work if the target endpoint can load the thread.

The send path is therefore not based on the invariant:

```text
detail is subscribed and thread is controllable before Send is enabled
```

It is based on:

```text
try to route a write when the user taps Send
```

That is too late.

### 6. Health checks prove visibility, not sendability

Current relay status can pass while sends are impossible for the rows a user
actually touches.

The local relay was `ready`, but it had:

```text
privateOwners: 40
threadOwners: 0
```

That means the relay was healthy as a process and history/list service, but not
healthy as an end-to-end control plane for those private-owned rows.

The health model is missing a completion-grade check:

```text
for each app-visible active row, can the relay resume/subscribe/send/control it?
```

### 7. Swift makes definite architecture failures look ambiguous

`CodexDock/State/ThreadDetailStore.swift` catches any thrown send error and
sets:

```swift
pendingMessage.deliveryState = .failedAmbiguous(message)
```

`CodexDock/ThreadDetail/OutboundUserMessage.swift` labels that state:

```text
Check
```

So a known architectural failure such as:

```text
thread ... is owned by a private Codex runtime
```

can become a vague user-visible `Check`.

That is not the root cause, but it hides the root cause during manual testing.

## Codex Source Findings

The local Codex source audited was:

- repo: `/Users/aelaguiz/workspace/codex`
- branch: `main`
- commit: `9ddb1de633`
- installed standalone binary: `/Users/aelaguiz/.codex/packages/standalone/current/codex`
- installed binary version: `codex-cli 0.132.0`

### 1. Codex has the right primitive: `thread/resume`

Codex app-server docs say the intended lifecycle is:

1. `thread/start` for new work, or `thread/resume` for existing work.
2. `turn/start` to send user input.
3. live notifications stream on the same connection.

`codex-rs/app-server/src/request_processors/thread_processor.rs` implements
`thread_resume_inner(...)` by loading stored history, calling
`thread_manager.resume_thread_with_history(...)`, then auto-attaching a thread
listener for the connection.

That is the correct shape for Dock:

```text
resume/subscription first, send second
```

Dock currently does not make that a hard product invariant for every visible
row.

### 2. Codex `turn/start` requires an in-process loaded thread

`codex-rs/app-server/src/request_processors/turn_processor.rs` implements
`turn_start_inner(...)`.

Before it can submit user input, it calls:

```text
load_thread(&params.thread_id)
```

That function resolves the thread id, then calls:

```text
thread_manager.get_thread(thread_id)
```

If the thread is not loaded in that app-server process, it returns:

```text
thread not found: <thread_id>
```

This means Codex does not define `turn/start` as "find any persisted thread and
resume it automatically." It defines `turn/start` as "start a turn on a thread
already loaded in this app-server process."

So Dock cannot safely send into arbitrary history rows unless it first resumes
them on a controllable app-server process.

### 3. Codex `thread/read` intentionally supports read-only persisted views

`codex-rs/app-server/src/request_processors/thread_processor.rs` implements
`read_thread_view(...)`.

For metadata-only reads, it can load persisted data without a live thread. For
`includeTurns`, it can also load persisted history from the thread store when
the thread is not loaded.

That means Codex itself exposes this distinction:

```text
thread/read can work while turn/start cannot
```

This is acceptable inside Codex as an API distinction. It is not acceptable for
Dock to blur the distinction in the main conversation UI.

### 4. Codex `ThreadStatus` does not express phone control capability

`codex-rs/app-server-protocol/src/protocol/v2/thread.rs` defines
`ThreadStatus` as:

```text
notLoaded
idle
systemError
active
```

There is no built-in field for:

- sendable,
- subscribable,
- controllable,
- read-only,
- private owner,
- owner endpoint,
- takeover required,
- handoff available,
- or "can the mobile app continue this thread?"

Dock filled that gap with relay-side heuristics. That is why the app can drift
from Codex truth.

### 5. Codex live thread writers are process-scoped

`codex-rs/app-server/src/message_processor.rs` explicitly says:

```text
The thread store is intentionally process-scoped.
```

`codex-rs/thread-store/src/local/live_writer.rs` prevents duplicate live writers
inside one `LocalThreadStore` by checking an in-memory `live_recorders` map.

`codex-rs/thread-store/src/local/mod.rs` has tests that duplicate create/resume
inside the same store fail with:

```text
already has a live local writer
```

That is good process-local protection, but it is not a machine-wide control
plane. The audited code does not expose a Codex-owned API that says:

```text
thread X is owned by process Y, here is how to attach, hand off, or take over
```

Dock is currently inferring that answer by discovering processes and session
files. That is the wrong layer for a production mobile control path.

### 6. Private `stdio` app-server is private by design

Codex app-server supports:

- `stdio://`
- `ws://...`
- `unix://...`
- `off`

The docs call websocket experimental and unsupported for production workloads.
The unix socket transport is intended for local app-server control-plane
clients. `stdio` is tied to the parent process.

So the relay is right that a private `stdio` runtime is not attachable as a
normal phone endpoint. The mistake is not "why did the relay fail to attach to
stdio?" The mistake is that a private `stdio` thread is still allowed to appear
as a normal active Dock thread without a full-control path.

## The Core Architectural Bug

Dock has three partial sources of truth:

1. Codex history daemon and thread store: good at listing and reading stored
   threads.
2. App-server registry and live owner discovery: good at finding attachable
   app-server endpoints when they expose loaded threads.
3. Private process/session-file discovery: good at noticing active work that is
   not attachable.

Those were combined into one app experience without a strict capability gate.

The result is a row that can be:

- visible from history,
- marked active from private process presence,
- readable from persisted turns,
- opened in detail through a history fallback,
- but not sendable because no controllable loaded owner exists.

That row should not be a normal thread in the main app.

## Why The Current Design Fails In Real Life

A typical failure path is:

1. User runs Codex normally in a CLI/TUI/private process.
2. That runtime owns a thread over private `stdio`.
3. Dock relay detects private-owner presence.
4. Dock list shows the thread because it can read history and/or see private
   activity.
5. User opens Thread Detail.
6. Relay tries `thread/resume`.
7. Relay sees private owner and refuses to attach or duplicate the writer.
8. Relay falls back to a history-backed detail snapshot.
9. User types a message and sends.
10. Relay tries to route `turn/start` or `turn/steer`.
11. Registry rejects the route with `private_owner_unattachable`.
12. Relay records `failedDefinite`.
13. Swift catches the thrown error and shows `Check`.

The user sees "message failed for no reason."

The real reason is:

```text
Dock exposed a thread whose owning runtime was not controllable by Dock.
```

## What Is Unacceptable

These should not be accepted as normal app states:

- "I can see a thread but cannot send to it."
- "I can open detail but it is only a history snapshot."
- "I can read partial detail but not get a live subscription."
- "The relay knows a row is private/unattachable, but the UI still enables Send."
- "Health checks pass while all rows the user cares about are not sendable."
- "The app treats private runtime ownership as a badge problem instead of a
  control-plane failure."

Read-only history can exist as a separate archive/debug mode. It should not be
the default active conversation experience.

## Better Dock Architecture Under Fixed Codex

### Preferred Rebuild: One Account-Scoped Control Plane

The clean architecture available to this repo is:

```text
Codex launcher wrapper
-> account-scoped CODEX_HOME
-> account-scoped Codex daemon socket
-> account-scoped Dock relay identity
-> phone host row
```

The Codex daemon is still an external dependency. Dock cannot make a private
embedded TUI runtime controllable if current Codex did not expose a listener for
it. Dock can, however, stop treating private/history/system-error rows as normal
active conversations.

In the fixed-Codex model:

- The CLI wrapper decides the intended account before Codex chooses a socket.
- The phone talks to a Dock relay launched with the same `CODEX_HOME`.
- Each parallel account relay has its own port, runtime dir, and host identity.
- Dock uses current Codex signals to compute capability: visible, readable,
  loaded, subscribed, sendable, and controllable.
- Dock disables send/control actions unless `thread/resume`,
  `thread/detail/subscribe`, and the relevant control route have succeeded.
- Private embedded runtimes stay visible only as read-only/history/debug state
  until a Dock-controllable owner exists.

This is the target state that makes "threads we can't send to" disappear from
the main app.

### Required Dock Boundary Contract

Dock should expose a phone-facing thread-control contract even if current Codex
does not expose one clean primitive. The relay can compute it from daemon
routes, loaded-thread probes, route failures, private-owner detection, and
session state:

```text
dock/thread/control/list
dock/thread/control/read
dock/thread/control/subscribe
dock/thread/control/resume
dock/thread/control/capabilities
```

The exact method names can differ, but the contract needs to answer:

- Is this thread controllable by this client?
- Who owns it?
- Is it loaded?
- Can it be resumed?
- Can it be subscribed to live?
- Can it accept user input now?
- Can it accept interrupt/approval/control messages?
- If not, is this read-only history, private runtime, not loaded, auth failure,
  or transport failure?

Dock should use process discovery as evidence only. It should not treat process
presence or history presence as proof of control.

### Thread Capability Model

Every thread returned to the app should carry a Dock-computed control model
like:

```json
{
  "control": {
    "state": "controllable",
    "read": true,
    "subscribe": true,
    "send": true,
    "interrupt": true,
    "approve": true,
    "rename": true,
    "archive": true,
    "owner": {
      "kind": "daemon",
      "endpoint": "unix"
    }
  }
}
```

For a private owner, Dock should return something explicit:

```json
{
  "control": {
    "state": "readOnlyPrivateRuntime",
    "read": true,
    "subscribe": false,
    "send": false,
    "reason": "ownedByPrivateRuntime",
    "handoffAvailable": false
  }
}
```

But the main active Dock list should ideally only include `state:
controllable`. Everything else belongs in a separate history/read-only area or
must render with disabled composer/control affordances until Dock proves a
controllable owner exists.

### `thread/resume` Must Be The Gate

Before a thread appears as an active detail screen, Dock should be able to prove:

```text
thread/resume succeeded
thread/detail/subscribe succeeded
the resumed thread id matches the requested id
the relay has an active upstream session for the thread
Send is routed through that session
```

If this cannot be proven, the composer should not be active.

The better invariant is:

```text
composer enabled == active controllable upstream session exists
```

### Send Should Not Be A Route Guess

`thread/message/send` should not discover at send time that the thread is
uncontrollable.

A better flow:

1. Dock opens thread detail.
2. Relay resumes/subscribes or performs Codex-owned handoff.
3. Relay marks the detail session as controllable.
4. Composer becomes enabled.
5. Send always uses the active upstream session.
6. If the session drops, composer moves to reconnecting/unavailable before the
   user can send another message.

The relay can still have an outbox for durability and idempotency, but send
should not be the first moment we learn the thread cannot be controlled.

### Private Runtime Handling

There are only three acceptable private-runtime paths:

1. **Proxy:** private runtime registers a control socket with the daemon; daemon
   routes phone commands to it.
2. **Handoff:** daemon asks the private runtime to stop owning the thread, then
   daemon resumes it and becomes owner.
3. **Hide from active app:** if proxy/handoff is unavailable, the thread does
   not appear as a normal active conversation.

The current fourth option is unacceptable:

```text
show it, let user type, then fail on send
```

### Health Checks Must Prove Control

Relay health should include a control-plane proof, not just process/list proof.

For the active app corpus, proof should answer:

- How many visible rows are controllable?
- How many are read-only?
- How many are private-unattachable?
- How many have active upstream sessions?
- Can a selected real row resume, subscribe, and route a dry-run send
  capability check?

The app should not claim "ready" for a user-message workflow when
`privateOwners` is high and `threadOwners` is zero.

## Immediate Product Rule

Until the control plane is rebuilt:

```text
Do not enable Send unless the thread has an active controllable upstream session.
```

That is still not the final architecture, but it prevents lying to the user.

The desired final architecture is stronger:

```text
Do not show a normal active thread unless it is controllable.
```

## Findings To Carry Into Rebuild

1. Dock must stop treating history visibility as active controllability.
2. Dock must stop silently falling back from live detail subscription to a
   history-backed snapshot in the main active thread flow.
3. Codex needs an authoritative machine-wide owner registry or daemon-owned
   control plane.
4. Private `stdio` runtimes must register, proxy, hand off, or be excluded from
   the active app.
5. `turn/start` requires a loaded in-process thread; Dock must not route it as a
   blind write to any history-visible row.
6. `thread/read` being successful is not proof that `turn/start` can succeed.
7. `ThreadStatus` is not enough; Dock needs explicit control capabilities.
8. Relay health must include row-level control proof.
9. Swift must preserve definite control-plane failures, not collapse them into
   `Check`.
10. Simulator fixture proof is not enough; real relay-backed proof must cover
    resume, subscribe, and sendability of real rows.

## Test And Proof Gaps

Add tests/proof for:

- visible row with private owner must not be treated as active-sendable;
- `thread/detail/subscribe` private fallback must be named read-only or removed
  from active flow;
- composer enabled only after active controllable upstream session exists;
- `thread/message/send` on private owner preserves `failedDefinite`;
- relay status reports app-visible controllable vs read-only counts;
- real relay-backed simulator proof that every visible active row can resume
  and subscribe;
- real relay-backed send proof on a row that came from the same control plane;
- Codex daemon/control-plane tests for owner registration, handoff, takeover,
  and duplicate writer prevention.

## Files Read

Dock repo:

- `scripts/dock-relay.mjs`
- `scripts/dock-relay-app-server-registry.mjs`
- `scripts/dock-relay-live-status-cache.mjs`
- `scripts/dock-relay-thread-data.mjs`
- `scripts/dock-relay-user-message-command.mjs`
- `scripts/dock-relay-app-server-registry.test.mjs`
- `scripts/dock-relay-thread-detail-ledger.mjs`
- `CodexDock/State/ThreadDetailStore.swift`
- `CodexDock/ThreadDetail/OutboundUserMessage.swift`
- `CodexDock/Features/Session/ThreadMessageListView.swift`
- `.codex-dock/relay-state.sqlite`

Codex source repo:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/README.md`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-daemon/README.md`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/main.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/message_processor.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/turn_processor.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_lifecycle.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_state.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread_data.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/store.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/live_writer.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/mod.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/live_thread.rs`

## Commands Run

```bash
rtk command -v codex
rtk /Users/aelaguiz/.codex/packages/standalone/current/codex --version
rtk git -C /Users/aelaguiz/workspace/codex rev-parse --short HEAD
rtk git -C /Users/aelaguiz/workspace/codex branch --show-current
rtk rg -n "routeForThreadMethod|private Codex runtime|HISTORY_SAFE_PRIVATE_OWNER_METHODS|LIVE_OWNER_PREFERRED_METHODS|thread .*private|owned by a private" scripts/dock-relay-app-server-registry.mjs scripts/dock-relay-thread-data.mjs scripts/dock-relay-user-message-command.mjs
rtk sqlite3 -header -column .codex-dock/relay-state.sqlite "SELECT state, COUNT(*) AS count FROM outbound_user_messages GROUP BY state ORDER BY state; SELECT created_at, updated_at, thread_id, client_user_message_id, state, upstream_method, upstream_endpoint_url, last_error_code, last_error_message FROM outbound_user_messages ORDER BY created_at DESC LIMIT 20;"
rtk make dock-relay-status
rtk make relay-doctor
rtk sh -c 'curl -fsS http://127.0.0.1:4510/statusz | node -e ...'
rtk find /Users/aelaguiz/.codex -maxdepth 4 '\(' -type s -o -name '*.sock' '\)' -print
rtk node --input-type=module <<'NODE'
# Relay discovery inventory plus per-PID lsof socket checks.
NODE
rtk lsof -nP -a -p <private-owner-pid> -iTCP -sTCP:LISTEN -F n
rtk lsof -nP -a -p <private-owner-pid> -U -F n
rtk node --input-type=module <<'NODE'
# Today-only private-owner inventory for $CODEX_HOME/sessions/2026/06/06 on Amir-M5.
NODE
ssh home 'cd /home/aelaguiz/workspace/codex-client && node --input-type=module' <<'NODE'
# Today-only private-owner inventory for $CODEX_HOME/sessions/2026/06/06 on home.
NODE
ssh home 'ps -o pid=,ppid=,command= -p 1660171,477696,2313541'
rtk rg -n "turn/start|turn_start|thread/resume|thread_resume|thread/read|thread/loaded/list|thread/list|turn/steer|remoteControl|remote_control|daemon" /Users/aelaguiz/workspace/codex/codex-rs/app-server/src /Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src /Users/aelaguiz/workspace/codex/codex-rs/app-server-daemon/src
rtk rg -n "async fn load_thread|fn load_thread|load_thread\\(" /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/turn_processor.rs /Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors.rs
rtk rg -n "LiveWriter|live_writer|ThreadLive|lock|lease|owner|process|pid" /Users/aelaguiz/workspace/codex/codex-rs/thread-store/src /Users/aelaguiz/workspace/codex/codex-rs/app-server/src /Users/aelaguiz/workspace/codex/codex-rs/core/src/session
rtk rg -n "InProcess|in_process|InProcessAppServerClient" /Users/aelaguiz/workspace/codex/codex-rs/tui /Users/aelaguiz/workspace/codex/codex-rs/app-server-client /Users/aelaguiz/workspace/codex/codex-rs/app-server
rtk npm run test:docs
```
