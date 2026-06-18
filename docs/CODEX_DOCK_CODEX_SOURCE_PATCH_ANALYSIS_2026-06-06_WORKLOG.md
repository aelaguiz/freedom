# Codex Source Patch Analysis Work Log

Date: 2026-06-06
Scope: source analysis only; no Codex or Codex Dock implementation changes.

## Goal

Answer this source-level question:

- If we were willing to patch upstream Codex, what is the smallest patch that
  would make multi-account, attachable Codex sessions work with less update
  churn?
- Do Codex plugins or hooks provide a way to change daemon, socket, auth, or
  session-home behavior without patching Codex source?
- Why does `codex -p yolo --remote unix://` not automatically mean "use the
  yolo account runtime"?

## Source Read

Read scope from `/Users/aelaguiz/workspace/codex`:

- `codex-rs/app-server/README.md`
- `codex-rs/app-server/src/main.rs`
- `codex-rs/app-server/src/in_process.rs`
- `codex-rs/app-server-client/src/lib.rs`
- `codex-rs/app-server-daemon/README.md`
- `codex-rs/app-server-daemon/src/lib.rs`
- `codex-rs/app-server-transport/src/transport/mod.rs`
- `codex-rs/tui/src/lib.rs`
- `codex-rs/cli/src/main.rs`
- `codex-rs/config/src/loader/mod.rs`
- `codex-rs/config/src/profile_toml.rs`
- `codex-rs/config/src/types.rs`
- `codex-rs/core/src/config/mod.rs`
- `codex-rs/config/src/config_toml.rs`
- `codex-rs/login/src/auth/manager.rs`
- `codex-rs/login/src/auth/storage.rs`
- `codex-rs/rollout/src/lib.rs`
- `codex-rs/rollout/src/list.rs`
- `codex-rs/rollout/src/metadata.rs`
- `codex-rs/thread-store/src/local/archive_thread.rs`
- `codex-rs/config/src/hook_config.rs`
- `codex-rs/core/src/hook_runtime.rs`
- `codex-rs/app-server/src/request_processors/plugins.rs`

## Findings

### Plugins and hooks do not solve this

Codex has plugin, marketplace, skill, and hook surfaces, but they run inside a
started Codex process. They do not control process launch, `CODEX_HOME`
resolution, daemon socket selection, auth storage, or session storage.

Evidence:

- App-server README lists `marketplace/*`, `plugin/*`, `skills/*`, `hooks/list`,
  and remote-control routes as app-server protocol methods, not launch-time
  daemon/auth selectors.
- `request_processors/plugins.rs` handles `plugin/list`, `plugin/read`, and
  `plugin/install` by loading marketplace/config data from the running
  app-server config.
- `hook_config.rs` defines hook events such as `PreToolUse`, `PostToolUse`,
  `SessionStart`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, and
  `Stop`.
- `hook_runtime.rs` runs those hooks around session/tool/turn lifecycle events.
  It has no hook point before `find_codex_home()`, no hook point for
  `AuthManager` construction, and no hook point for default daemon socket path.

Conclusion: there is no plugin-style patchless route for this. Any behavior
change at the daemon/auth/socket/session-home layer is a Codex source change or
an external launcher/runtime convention.

### App-server transport is already there, but default launch is not socketed

Codex app-server supports these transports:

- `stdio://`, default.
- `unix://`, default socket path under
  `$CODEX_HOME/app-server-control/app-server-control.sock`.
- `unix://PATH`, custom socket path.
- `ws://IP:PORT`, explicitly documented as experimental and unsupported.
- `off`.

Evidence:

- `app-server/README.md` says `stdio://` is default, `unix://` maps to
  `$CODEX_HOME/app-server-control/app-server-control.sock`, and websocket is
  experimental/unsupported.
- `app-server/src/main.rs` sets `--listen` default to
  `AppServerTransport::DEFAULT_LISTEN_URL`.
- `app-server-transport/src/transport/mod.rs` defines
  `DEFAULT_LISTEN_URL = "stdio://"` and computes the default Unix socket as
  `$CODEX_HOME/app-server-control/app-server-control.sock`.

Conclusion: the attachable local transport exists, but Codex must be launched in
a path that actually uses or exposes it. A private in-process runtime is still a
valid Codex code path.

### The daemon is scoped to `CODEX_HOME`

The app-server daemon is not a global account router. It is a `CODEX_HOME`
scoped process manager.

Evidence:

- `app-server-daemon/README.md` says the daemon lifecycle is experimental and
  stores state under `CODEX_HOME/app-server-daemon/`.
- `app-server-daemon/src/lib.rs::Daemon::from_environment()` calls
  `find_codex_home()`, derives the socket path from that home, stores daemon
  state under `codex_home/app-server-daemon`, and launches the managed binary
  under `codex_home/packages/standalone/current/codex`.
- Mutating daemon lifecycle commands are serialized per `CODEX_HOME`.

Conclusion: multiple accounts cannot safely share one daemon if each account is
supposed to have different auth state. The daemon namespace is currently the
Codex home.

### The private runtime path is intentional

Codex TUI chooses between:

- `Embedded`: an in-process app-server with no external listener.
- `LocalDaemon`: the implicit default daemon socket for the local
  `CODEX_HOME`.
- `Remote`: an explicit remote endpoint from `--remote`.

Evidence:

- `tui/src/lib.rs::AppServerTarget` has `Embedded`, `LocalDaemon`, and `Remote`.
- `app_server_target_for_launch()` chooses explicit remote when present; chooses
  `LocalDaemon` only when no explicit remote exists, the default daemon socket
  probes successfully, and `can_reuse_implicit_local_daemon` is true; otherwise
  it chooses `Embedded`.
- `can_reuse_implicit_local_daemon()` returns true only when CLI overrides are
  empty, loader overrides are default, strict config is false, and there are no
  non-replayable launch overrides.
- Selecting a profile sets loader overrides, so it prevents implicit daemon
  reuse unless `--remote` is explicitly provided.
- `app-server/src/in_process.rs` describes the in-process runtime as replacing
  socket/stdio transports with in-memory channels to avoid a process boundary.

Conclusion: when a profiled or otherwise non-default launch starts embedded, it
is private by design. Dock cannot attach because there is no Unix socket or
WebSocket listener to attach to.

### `codex -p yolo --remote unix://` is not "profile-specific daemon"

`-p yolo` selects a profile config layer. It does not create a separate
`CODEX_HOME`, a separate daemon namespace, a separate auth namespace, or a
separate session namespace.

Evidence:

- `cli/src/main.rs` defines `--profile` / `-p` as a profile selection.
- `loader_overrides_for_profile()` resolves the profile config path as
  `$CODEX_HOME/<profile>.config.toml`.
- `config/src/loader/mod.rs` documents the config stack as
  `$CODEX_HOME/config.toml`, then `$CODEX_HOME/<name>.config.toml`, then cwd/tree
  layers, then runtime flags.
- `config/src/profile_toml.rs::ConfigProfile` contains model/provider,
  permissions, personality, feature, and TUI fields. It does not contain
  `codex_home`, `auth_home`, `app_server_home`, or session-home fields.
- `tui/src/lib.rs::resolve_remote_addr("unix://")` resolves to the default
  socket path under `find_codex_home()`, not under the profile.

Conclusion: `codex -p yolo --remote unix://` means "load yolo profile values in
this CLI process, then connect to the default Unix socket for this
`CODEX_HOME`." It does not mean "connect to a yolo daemon/account." If the
shared daemon is running under a different account, that command can attach to
the wrong account's live control plane.

### Auth is keyed by `CODEX_HOME` and cached per process

Codex auth is built around a `CODEX_HOME` keyed storage model and an in-process
`AuthManager` snapshot.

Evidence:

- `config/src/types.rs::AuthCredentialsStoreMode` documents file auth as
  `CODEX_HOME/auth.json`; keyring/auto also use a key derived from the
  `CODEX_HOME` path.
- `login/src/auth/storage.rs::get_auth_file()` returns
  `codex_home.join("auth.json")`.
- `login/src/auth/storage.rs::compute_store_key()` hashes the canonical
  `codex_home` path for keyring and ephemeral storage.
- `core/src/config/mod.rs::AuthManagerConfig for Config` returns
  `self.codex_home` to the auth manager.
- `login/src/auth/manager.rs` says external modifications to `auth.json` are not
  observed until `reload()` is called.
- `AuthManager::refresh_token()` reloads only if the account id matches the
  cached auth. If the persisted auth account differs, it returns the account
  mismatch message: "Your access token could not be refreshed because you have
  since logged out or signed in to another account. Please sign in again."

Conclusion: account switching inside one shared `CODEX_HOME` is structurally
fragile. A live daemon can keep a cached auth snapshot while the disk auth has
moved to another account. That is not just a Dock problem.

### Sessions and archived sessions are also keyed by `CODEX_HOME`

Codex session history is currently read and written under `CODEX_HOME`.

Evidence:

- `rollout/src/lib.rs` defines `SESSIONS_SUBDIR = "sessions"` and
  `ARCHIVED_SESSIONS_SUBDIR = "archived_sessions"`.
- `rollout/src/list.rs::get_threads()` reads
  `codex_home.join(SESSIONS_SUBDIR)`.
- `rollout/src/list.rs::find_thread_path_by_id_str()` searches
  `CODEX_HOME/sessions`.
- `rollout/src/metadata.rs` backfills from `codex_home/sessions` and
  `codex_home/archived_sessions`.
- `thread-store/src/local/archive_thread.rs` moves active rollouts from
  `CODEX_HOME/sessions` into `CODEX_HOME/archived_sessions`.

Conclusion: using separate `CODEX_HOME` values per account solves auth and
daemon isolation, but it also splits session history unless sessions are copied,
symlinked, indexed across homes, or Codex gains a separate session-home concept.

### SQLite state is already partially decoupled

Codex already has one useful precedent: SQLite state can be moved outside
`CODEX_HOME`.

Evidence:

- `config/src/config_toml.rs` defines `sqlite_home` and says it defaults to
  `$CODEX_SQLITE_HOME` when set, otherwise `$CODEX_HOME`.
- `state/src/lib.rs` defines `CODEX_SQLITE_HOME` and SQLite filenames:
  `logs_2.sqlite`, `goals_1.sqlite`, `memories_1.sqlite`, and `state_5.sqlite`.
- `core/src/config/mod.rs` resolves `sqlite_home` from config, then
  `CODEX_SQLITE_HOME`, then `CODEX_HOME`.

Conclusion: if we patch Codex, the lowest-churn design should copy this style:
small, explicit home overrides instead of broad architectural rewrites.

## Patch Ranking

### Rank 0: no Codex patch, external launcher only

Use one `CODEX_HOME` per account/runtime and always launch with
`--remote unix://`. This already fits existing Codex behavior.

Pros:

- No Codex source churn.
- Auth, keyring key, app-server socket, daemon state, and daemon lifecycle are
  isolated because they all key off `CODEX_HOME`.

Cons:

- Session history splits by home unless AIMgr copies, moves, symlinks, or
  indexes sessions across runtime homes.
- Session continuity and no-duplicate-active-owner rules must be owned outside
  Codex.

This is the best no-source-change strategy, but it is not the patch answer.

### Rank 1: smallest Codex patch, but not complete

Patch launch selection so profile/non-default launches can still opt into a
socketed daemon instead of silently falling back to `Embedded`.

Possible shape:

- Add config/env support for a default remote target, for example
  `CODEX_APP_SERVER_REMOTE=unix://` or a config value such as
  `app_server.default_remote = "unix://"`.
- In `tui/src/lib.rs`, resolve that setting before `app_server_target_for_launch`.
- If the target is explicit, connect through `RemoteAppServerClient` instead of
  starting `InProcessAppServerClient`.
- Add tests around `can_reuse_implicit_local_daemon`,
  `app_server_target_for_launch`, and profile launches.

Pros:

- Small patch surface.
- Directly reduces private, non-attachable runtimes.
- Most churn is in `tui/src/lib.rs` and tests.

Cons:

- It does not fix multi-account auth.
- `-p yolo --remote unix://` would still connect to the shared
  `$CODEX_HOME/app-server-control/app-server-control.sock`.
- If that daemon belongs to the wrong account, sends can still fail.

Verdict: useful, but incomplete for Amir's workflow.

### Rank 2: smallest complete Codex patch

Add first-class separable homes for auth and app-server control while keeping
session history under the existing `CODEX_HOME` by default.

Possible shape:

- Add `CODEX_AUTH_HOME` or config `auth_home`.
- Add `CODEX_APP_SERVER_HOME` or config `app_server_home`.
- Keep `CODEX_HOME` as the default config/session home.
- Keep `CODEX_SQLITE_HOME` as the existing SQLite override.
- Make auth storage use `auth_home` instead of `codex_home` for:
  `auth.json`, keyring key derivation, and ephemeral auth keying.
- Make default app-server socket and daemon state use `app_server_home` instead
  of `codex_home` for:
  `app-server-control/app-server-control.sock`, startup lock, and
  `app-server-daemon/*`.
- Leave `CODEX_HOME/sessions` and `CODEX_HOME/archived_sessions` as the shared
  session-history root unless a separate `CODEX_SESSIONS_HOME` is also added.
- Make `resolve_remote_addr("unix://")`, `maybe_probe_default_daemon_socket()`,
  and daemon startup all agree on the same app-server home.

Why this is the smallest complete patch:

- It solves account isolation: each account/runtime can have distinct auth.
- It solves daemon/socket isolation: each account/runtime can have a distinct
  local control socket.
- It can preserve shared session history: all runtimes can still read the same
  `CODEX_HOME/sessions` if the launcher chooses that model.
- It avoids rewriting every rollout/session path immediately.
- It follows the existing `CODEX_SQLITE_HOME` pattern.

Main risk:

- Multiple daemons could see the same shared session history. Codex would still
  need an owner policy or AIMgr must enforce one effective active owner per
  session. Without that, two account runtimes could resume the same local
  session at once.

Likely source files:

- `codex-rs/core/src/config/mod.rs`: add resolved home fields and defaults.
- `codex-rs/config/src/config_toml.rs`: add TOML/env docs if config support is
  desired.
- `codex-rs/login/src/auth/manager.rs`: pass/use auth home.
- `codex-rs/login/src/auth/storage.rs`: file/keyring/ephemeral keys from auth
  home.
- `codex-rs/app-server-transport/src/transport/mod.rs`: default socket path
  from app-server home.
- `codex-rs/app-server-daemon/src/lib.rs`: daemon state and socket from
  app-server home.
- `codex-rs/tui/src/lib.rs`: `unix://` resolution and default-daemon probing
  from app-server home.
- Tests in auth storage, daemon lifecycle, transport parsing, and TUI launch
  target selection.

### Rank 3: profile becomes a true runtime namespace

Patch `--profile yolo` so a profile can define, or imply, a distinct runtime
home/account home/daemon home.

Pros:

- Matches the user mental model: `-p yolo` could mean the yolo account runtime.

Cons:

- Higher churn than env/config homes because profile loading currently happens
  as a layer inside the already-resolved `CODEX_HOME`.
- Would require careful two-phase loading if the profile itself changes the home
  that stores profile config.
- Existing profile schema is not account/runtime oriented.

Verdict: attractive UX, but a bigger patch than `CODEX_AUTH_HOME` plus
`CODEX_APP_SERVER_HOME`.

### Rank 4: full session-home split

Add `CODEX_SESSIONS_HOME` or config `sessions_home` / `archived_sessions_home`
and route every rollout/list/read/archive/backfill path through it.

Pros:

- Cleanest conceptual split: config home, auth home, app-server home, session
  home, SQLite home.

Cons:

- More source churn. Session logic is spread across rollout, thread-store,
  app-server tests, doctor, config, and migration/backfill code.
- More migration risk because sessions are the durable user-visible archive.

Verdict: probably right long-term, but not the lowest-churn patch if the
immediate goal is multi-account live control.

## Current Answer

Codex does not appear to have a plugin or hook surface that can change this.

The smallest patch that reduces private runtimes is a launcher/TUI remote-target
patch, but that is not enough for multi-account use.

The smallest patch that plausibly fixes the actual multi-account problem is to
decouple auth and app-server control homes from session history:

- shared `CODEX_HOME` for config and sessions, if shared session history is
  desired;
- account/runtime-specific `CODEX_AUTH_HOME`;
- account/runtime-specific `CODEX_APP_SERVER_HOME`;
- existing `CODEX_SQLITE_HOME` strategy decided separately.

That patch would let multiple account daemons exist without fighting over the
same socket or auth cache, while still allowing a shared local session history
if AIMgr enforces one active owner per thread.

## Open Questions

- Should shared session history remain in one `CODEX_HOME/sessions`, or should
  AIMgr own session import/copy between per-account `CODEX_HOME` directories?
- If shared session history is kept, should Codex itself enforce an active-owner
  lock per thread, or should AIMgr/Dock enforce that outside Codex?
- Should profile UX eventually map to runtime homes, or should account runtime
  selection remain an explicit launcher concern outside Codex?
