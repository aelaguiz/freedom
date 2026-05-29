# Independent Architecture Pass: Opus Max

You are one participant in a model-consensus architecture review. Your role is
to independently propose the most elegant robust architecture for Codex Dock's
Codex app-server integration. You are not implementing code in this pass.

## Ground Rules

- Work root: `/Users/aelaguiz/workspace/codex-client`.
- Supporting Codex source root: `/Users/aelaguiz/workspace/codex`.
- Read real files before recommending architecture.
- Do not edit files.
- Do not use web search.
- Do not quote secrets, bearer tokens, raw prompt text, raw transcript text,
  raw audio, base64 audio, or full JSON-RPC payloads.
- Optimize for the architecture Codex Dock should have, not for preserving
  current Dock code.
- Prefer hard, explicit invariants over vague guidance.

## Required Repo Evidence To Inspect

At minimum inspect:

- `/Users/aelaguiz/workspace/codex-client/AGENTS.md`
- `/Users/aelaguiz/workspace/codex-client/README.md`
- `/Users/aelaguiz/workspace/codex-client/Makefile`
- `/Users/aelaguiz/workspace/codex-client/package.json`
- `/Users/aelaguiz/workspace/codex-client/Package.swift`
- `/Users/aelaguiz/workspace/codex-client/project.yml`
- `/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_CODEX_APP_SERVER_END_TO_END_AUDIT.md`
- `/Users/aelaguiz/workspace/codex-client/docs/CODEX_DOCK_THREAD_SORT_ROOT_CAUSE_2026-05-29_WORKLOG.md`
- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay.mjs`
- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-thread-data.mjs`
- `/Users/aelaguiz/workspace/codex-client/scripts/dock-relay-json-rpc-client.mjs`
- `/Users/aelaguiz/workspace/codex-client/scripts/codex-dock-host-service.mjs`
- `/Users/aelaguiz/workspace/codex-client/CodexDock/AppServer/AppServerClient.swift`
- `/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockStore.swift`
- `/Users/aelaguiz/workspace/codex-client/CodexDock/State/DockSessionProjection.swift`
- `/Users/aelaguiz/workspace/codex-client/CodexDock/Configuration/HostRegistry.swift`
- `/Users/aelaguiz/workspace/codex-client/CodexDock/Configuration/RelayBootstrapStore.swift`

At minimum inspect Codex source files that define the actual app-server model:

- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/main.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/lib.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/request_processors/thread_processor.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/thread_status.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server/src/filters.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/websocket.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/auth.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-transport/src/transport/remote_control/mod.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-daemon/src/lib.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-daemon/src/managed_install.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/core/src/thread_manager.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/thread-store/src/local/list_threads.rs`
- `/Users/aelaguiz/workspace/codex/codex-rs/app-server-protocol/src/protocol/v2/thread.rs`

## Architecture Questions To Answer

1. What is the true Codex app-server mental model: history plane, live plane,
   session identity, process lifetime, transport/auth, and daemon/control
   modes?
2. What should Codex Dock's ideal host-side architecture be if current code
   were not constraining it?
3. Should Dock keep a relay? If yes, what exact responsibilities should the
   relay own, and what responsibilities should move out of it?
4. How should Dock discover, identify, subscribe to, and health-check live
   Codex sessions without fragile load multipliers?
5. How should history rows and live rows be merged, deduped, paginated, and
   sorted?
6. How should device endpoint config work for iPhone 17 Pro on Tailscale and
   iPhone 14 on local DNS/LAN without hard-coded cross-device leakage?
7. What logging, metrics, diagnostics, health endpoints, and debug commands
   should exist so the next failure is obvious?
8. What should the Makefile expose as canonical commands?
9. What must be tested at relay unit, Swift unit, simulator, service, and
   physical-device levels?
10. What should be deleted or replaced from the current architecture?

## Output Contract

Return these sections:

- `Verdict`
- `Evidence Read`
- `Codex App-Server Truths`
- `Proposed Architecture`
- `Data And Control Flow`
- `Identity, Deduping, Sorting, And Pagination`
- `Observability And Debuggability`
- `Makefile And Ops Surface`
- `Testing And Acceptance Gates`
- `Migration / Replacement Plan`
- `Risks And Non-Negotiable Invariants`
- `Open Questions For Consensus`

Be decisive. If the elegant architecture requires large rewrites, say so.
