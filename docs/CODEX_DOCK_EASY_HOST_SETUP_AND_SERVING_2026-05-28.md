---
title: "Codex Dock - Easy Host Setup & Multi-Host Serving (Add-a-Host + LAN/Tailscale) - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [amir]
reviewers: [amir]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md
  - docs/IPHONE_PERSONAL_PAIRING_SECRET_PLAN_2026-05-28.md
  - docs/CODEX_DOCK_CONNECTIVITY_RESILIENCE_2026-05-28.md
  - README.md
  - Makefile
  - scripts/codex-dock-host-service.mjs
---

# TL;DR

## Supersession Note - 2026-05-28

`docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28.md`
supersedes this plan anywhere it tells the app or generated app config to use
WebSocket URLs, auth modes, bearer/token fields, host display-name env, or a
Tailscale network profile. Current app-facing relay config is endpoint-only:
`CODEX_DOCK_HOSTS=<host>:<port>[,<host>:<port>]`, and Tailscale is only an
operator way to make that host reachable.

- **Outcome:** From a clean state, a user can (1) run one setup command on the Mac and one on the home Linux box — each prints a phone-reachable relay URL for a chosen network profile (LAN/open-IP or Tailscale) — and (2) in the iPhone app, add both hosts by URL (or accept a discovered one), see them **persist across app cold start**, and load real sessions from whichever hosts are reachable. No env-var injection on a real device, no secrets on the phone, Tailscale optional.
- **Problem:** On the phone there is no real "add a host": multi-host only works via env injection (`make app` SIMCTL vars); the in-app Add Relay form persists only **one** relay to `relay-config.json`, so a second host is lost on relaunch, and bootstrap precedence (env → first-discovered → single-saved) is a split source of truth. On the serving side, the relay binds `0.0.0.0` (so it already listens on the Tailscale interface) but the phone is only ever told the **en0 LAN IP** and can only discover via **LAN-only mDNS**, so off-LAN/Tailscale never connects; the home Linux box is unwired (empty `HOME_WS`); the cross-platform installer already supports `tailscale`/`linux` profiles but the Makefile hardwires `macos`+`lan`+single-host and there is no multi-host handoff or Tailscale-IP autodetect.
- **Approach:** Make a **durable on-device multi-host registry the single source of truth** on the phone (add/edit/remove, survives relaunch); collapse the split bootstrap/edit ownership into that one store; demote env + Bonjour to **seed/import/upsert**, not competing runtime truth. On the serving side, **wire the existing `codex-dock-host-service.mjs` profiles end-to-end**: one idempotent setup command per machine that selects platform + network profile, autodetects the Tailscale address, prints the exact `ws(s)://host:4510` URL to paste into the app, and brings up the home Linux box via systemd just like the Mac via launchd. Resolve the iOS App Transport Security posture for cleartext `ws://` over non-LAN (Tailscale/open-IP) endpoints.
- **Plan:** Phase 1 — durable multi-host store as on-device SSOT (+ one-time migration/import from `relay-config.json` and env). Phase 2 — complete in-app "Add a host" UX (edit/remove/bearer/auth-mode, discovery becomes add-not-replace) on that store. Phase 3 — easy per-machine serving with selectable network profile + Tailscale-address autodetect + clear URL emission, and the resolved ATS posture so Tailscale/open-IP actually connects. Phase 4 — wire the second "home" Linux box (systemd) end-to-end and the multi-host handoff so both hosts are added and tolerate one being offline.
- **Non-negotiables:** No secrets on the phone (relay `auth=none` default; bearer optional & user-entered; `OPENAI_API_KEY` + raw app-server token stay host-side). One on-device source of truth for hosts — no parallel host stores, no silent precedence confusion. Relay is the only phone endpoint (never raw `:4500`). `ws://`/`wss://` only, host required, no embedded credentials (reuse the existing validator). Tailscale is a **profile, not a dependency** — removing it only changes the URL. Never overwrite user-owned `.env`. No new product surfaces (no account login, AIMGR rotation, push, or required public funnel).

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: not started
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:dfa718432a059f34986849363705c9a3064ad98a5ae88f1fad576494598a64d7",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T21:18:29Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:6965bce8f0b57c5ceb91a380d69e4fdf9dba2bf1eb94cb0cf05abb3d6aa2a4b5",
      "completed_at": "2026-05-28T21:20:07Z",
      "doc_hash_after": "sha256:711c31e0b89242312e5c31b27eac8ce0191eabf74ed6031b78bbdbf6fa98ac7e"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T21:20:07Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:711c31e0b89242312e5c31b27eac8ce0191eabf74ed6031b78bbdbf6fa98ac7e",
      "completed_at": "2026-05-28T21:23:09Z",
      "doc_hash_after": "sha256:5bc9f8bdff09c729976bb0c7bb38e8bd1e5b8cc596958cec3792068775b2d218"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T21:23:09Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:5bc9f8bdff09c729976bb0c7bb38e8bd1e5b8cc596958cec3792068775b2d218",
      "completed_at": "2026-05-28T21:24:37Z",
      "doc_hash_after": "sha256:cda88977fbb1e6ccdfba5d5ea43bce7fb75bf70e2eab1600af231f4eee7b79c3"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T21:24:37Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:cda88977fbb1e6ccdfba5d5ea43bce7fb75bf70e2eab1600af231f4eee7b79c3",
      "completed_at": "2026-05-28T21:26:56Z",
      "doc_hash_after": "sha256:9a238a7d7b4229734a4a9135ecf75e459c75843b9a9ef668acf29b4e9f01ad9c"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T21:26:56Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:9a238a7d7b4229734a4a9135ecf75e459c75843b9a9ef668acf29b4e9f01ad9c",
      "completed_at": "2026-05-28T21:31:40Z",
      "doc_hash_after": "sha256:848d32468d69ed80df2265edeea0e70d42e4661aa862f13bca82b1dff908ed4d"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

From a clean state, a user can:
1. run **one** setup command on the Mac (launchd) and **one** on the home Linux box (systemd-user), each of which selects a network profile (`lan`/open-IP or `tailscale`), brings up the raw app-server + Dock relay, and **prints the exact phone-reachable `ws(s)://host:4510` URL** for that profile; and
2. in the iPhone app, **add both hosts by pasting their URLs** (or accept a Bonjour-discovered relay on the LAN), where the added hosts **persist across an app cold start**, appear in the Dock, and load real `SessionSummary` rows from every reachable host — with **one host offline still loading the other**, **no env-var injection on the physical device**, and **no secret stored on the phone**.

Falsifiable failure signs: a second added host disappears after relaunch; the phone cannot connect to a host reachable only over Tailscale; the home Linux box has no working served endpoint; configuring a host requires editing env vars or rebuilding; any OpenAI key or raw app-server bearer token reaches the phone.

## 0.2 In scope

Requested behavior (user-visible):
- A durable on-device **multi-host registry**: add / edit / **remove** hosts; values survive relaunch and cold start; this list is authoritative on the phone.
- In-app host fields: `id`, display `name`, `ws://`/`wss://` URL, **optional bearer token + auth mode** (default none). Validation with friendly errors.
- Bonjour-discovered relays become an explicit **"add this host"** action (not an auto-replace of the whole registry).
- Per-machine serving made easy: select network profile (`lan`|`tailscale`|`manual`), **autodetect the Tailscale address**, emit the phone-reachable URL clearly; same one-command experience on the Mac (launchd) and the home Linux box (systemd).
- Tailscale **or** plain opened IP both work; Tailscale never required.

Allowed architectural convergence (internal, not new product):
- Introduce one canonical persistent multi-host store and route both `RelayBootstrapStore` (boot/discovery) and `HostSettingsStore` (in-app editing) through it; retire the single-relay `relay-config.json` path with a one-time migration.
- Generalize `HostRegistry` from env-only construction to "from persistent store", keeping env as a **seed/upsert** format (so the simulator `make app` flow still works).
- Extend `codex-dock-host-service.mjs` with Tailscale-address autodetection, and make the Makefile consume the installer's `app-config --format env` so the `CODEX_DOCK_HOST_<SUFFIX>_*` names have a single writer (no separate multi-host merge — see audit PLA-001/PLA-002).
- Parametrize the `Makefile` for platform + network profile + host, add a home-box path, and emit the phone-reachable URL.
- Adjust `CodexDockApp/Info.plist` / `project.yml` ATS only as needed for the resolved non-LAN cleartext posture.

## 0.3 Out of scope

- New product features: account login / multi-user sharing, AIMGR account rotation, push notifications / background networking, QR-code host handoff (named follow-up, not now), and any **required** public funnel.
- Tailscale **Serve / Funnel as a hard dependency** (it may be an *option* for `wss://`, never required).
- Security hardening beyond what the ATS decision needs (mTLS, device-approval, per-request signing).
- Changing the relay's upstream Codex discovery (`ps`-based loopback scan + history server) — that mechanism stays as-is.
- The raw app-server's own listen contract and bearer model — unchanged.

## 0.4 Definition of done (acceptance evidence)

- **Swift unit tests** (reuse `CodexDockTests` patterns): persistent multi-host store round-trip (add/edit/remove/persist/reload); one-time migration import from a single `relay-config.json` and from env (`CODEX_DOCK_HOSTS...`) upsert-by-id; `HostRegistry` built from the store; bootstrap precedence (store authoritative when non-empty; env seeds/upserts; discovery adds, never replaces); bearer/auth-mode persistence.
- **Node tests** (reuse `scripts/codex-dock-host-service.test.mjs`): `app-config --format env` single-writer output + Node↔Swift suffix agreement; `tailscale` profile URL emission and Tailscale-address autodetect parsing; existing launchd/systemd render still green.
- **Manual physical (finalization, non-blocking, Amir-owned):** on a real iPhone, add the Mac host and the home host by URL; confirm both persist across a cold start; load sessions from Amir-M5 (launchd) and Home (Linux systemd) over (a) LAN/open-IP and (b) Tailscale; take one host offline and confirm the other still loads; confirm no secret is present on the phone.
- **ATS spike (gates Phase 3):** a real device connection to a non-LAN endpoint over the chosen scheme proves the resolved ATS posture (scoped cleartext-`ws` exception for tailnet/DNS hostnames by default; `wss`/Serve or broader posture only if proven necessary).

## 0.5 Key invariants (fix immediately if violated)

- **No secrets on the phone.** Relay `auth=none` is the personal default; bearer is optional and user-entered; `OPENAI_API_KEY` and the raw app-server token never leave the host. Bonjour TXT stays non-secret.
- **One on-device source of truth for hosts.** Exactly one persistent store; `RelayBootstrapStore` and `HostSettingsStore` share it via injection. No parallel writers, no shadow precedence.
- **Discovery and env upsert, never replace.** Bonjour/env may add or refresh entries by `id`; they never silently wipe the user's list.
- **Relay-only phone endpoint.** The phone connects to the relay (`:4510`), never the raw `:4500` app-server.
- **URL hygiene.** `ws://`/`wss://` only, host required, no embedded credentials — reuse `DockHostConfiguration.validatedWebSocketURL`.
- **Tailscale is a profile, not a dependency.** Removing Tailscale changes only the configured URL; no app/relay/service code path depends on it.
- **Fail-loud, no silent drift.** An unreachable host shows offline/error and is never silently dropped; partial multi-host availability is preserved.
- **Do not overwrite user-owned `.env`.** Generated config lives under `.codex-dock/`.
- **No fallbacks / runtime shims** (default `fallback_policy: forbidden`). Migration of the old single-config is a one-time import + clean cutover, not a permanent dual path.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. **Correctness of the source-of-truth model** — the on-device registry must be the one authoritative, durable list; precedence must be unambiguous.
2. **End-to-end ease for the real (physical) device** — add-a-host by URL must work with no env injection and no secrets.
3. **Both machines serve with one command each, Tailscale optional** — Mac (launchd) and home (systemd) parity using the existing installer.
4. **Reuse over reinvention** — build on `codex-dock-host-service.mjs`, `HostRegistry`, `FileLocalDockConfigurationStore`, and existing connectivity/voice stores; do not fork parallel infra.
5. **Preserve existing behavior** — simulator `make app` flow, connectivity/reconnect, and voice must keep working unchanged.

## 1.2 Constraints

- Swift 6 / iOS 26 deployment target; SwiftUI; framework + app + test targets generated by XcodeGen from `project.yml`.
- Node relay + installer are ESM `.mjs`; protocol method/DTO names must move together across `scripts/dock-relay*.mjs`, `CodexDock/AppServer/**`, `CodexDock/Voice/**`, and `CodexDockTests/**` (AGENTS.md).
- iOS App Transport Security governs cleartext `ws://`; `NSAllowsLocalNetworking` covers LAN/RFC1918/`.local` but not arbitrary public/CGNAT IP literals.
- Canonical runnable sources (`Makefile`, `project.yml`, `Package.swift`, `package.json`) win over docs.
- `$eli10` for user-facing replies; never overwrite `.env`; do not commit/stage unless asked.

## 1.3 Architectural principles (rules we will enforce)

- **Single source of truth for hosts**, realized in code by one injected store actor shared by bootstrap and settings — not by convention.
- **Seed/upsert, not replace**: env and discovery call an explicit upsert-by-id on the store; the registry is rebuilt from the store.
- **Reuse the canonical URL validator and host model** (`DockHostConfiguration`) rather than re-validating ad hoc.
- **Tailscale isolation**: the only Tailscale-aware code is address resolution in the installer (a profile), keyed off a profile string + autodetect; nothing else references Tailscale.
- **Installer is the one service owner** (`codex-dock-host-service.mjs`); the Makefile only parametrizes it. No second service-bringup path.
- **Fail-loud boundaries**: unreachable host → visible offline/error via the existing `AppConnectivityStore`; no silent fallback.

## 1.4 Known tradeoffs (explicit)

- **Migrate-and-delete the single `relay-config.json`** vs keep both: choosing clean cutover + one-time import to avoid dual sources of truth (git retains history).
- **Env stays as a launch-time seed/upsert** (so the simulator stays ergonomic) rather than being removed — accepted because it converges on the store rather than competing with it.
- **Default to scoped cleartext-`ws` over DNS/tailnet hostnames** (smallest ATS surface) over `NSAllowsArbitraryLoads` (broad) or `wss`/Tailscale Serve (most secure but adds a cert dependency) — pending the Phase 3 spike; alternatives named in the Decision Log.
- **Run the installer on each box** (the user already SSHes in) as the core path, with an optional SSH convenience wrapper — avoids fragile remote orchestration as new infra.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

- 3 tiers: iPhone SwiftUI app ↔ Node Dock relay (`scripts/dock-relay.mjs`, listens `0.0.0.0:4510`) ↔ raw Codex app-server (loopback `:4500` + live per-session loopback servers the relay finds via `ps`).
- Client config sources: env (`CODEX_DOCK_HOSTS` + per-host scoped vars), Bonjour discovery (`_codexdock._tcp.local.`), and a single saved `relay-config.json`. Bootstrap precedence lives in `RelayBootstrapStore`; in-app editing lives in `HostSettingsStore`.
- A cross-platform installer `scripts/codex-dock-host-service.mjs` already supports network profiles (`lan|manual|tailscale|simulator-local`), launchd (macOS) and systemd-user (Linux), idempotent install/start/stop/status/doctor, and single-host `app-config` emit; it health-checks the relay at its public URL.
- `make services` brings up the Mac via the installer with `platform=macos`, `network-profile=lan`, `public-host=$(ipconfig getifaddr en0)`, single host `Amir-M5`.

## 2.2 What's broken / missing (concrete)

- **No durable multi-host on the phone.** `HostSettingsStore.saveHost` persists only one `LocalRelayConfiguration` to `relay-config.json` (CodexDock/State/HostSettingsStore.swift:227); adding a 2nd host updates in-memory only and is lost on relaunch. The discovery path builds a one-host registry (`RelayBootstrapStore.swift:246`). Real multi-host only works via env injection (`Makefile:149` SIMCTL vars) — simulator/dev only.
- **Split source of truth.** Boot precedence (env → first-discovered → single-saved) in `RelayBootstrapStore.swift:44` vs in-app edits in `HostSettingsStore` — two owners, no shared persistent list.
- **Off-LAN can't connect.** Relay binds `0.0.0.0` (`dock-relay.mjs:673`), but the phone is told only the en0 LAN IP (`Makefile:2`) and discovery is LAN-only mDNS (`scripts/dock-relay-bonjour.mjs`). No Tailscale address is ever advertised or configured.
- **Home Linux box unwired.** `CODEX_DOCK_HOST_HOME_WS` is empty (`Makefile:46`); nothing installs/runs the relay on the home box or pulls its URL back.
- **No Tailscale autodetect, no multi-host handoff/merge.** `app-config` emits one host (`codex-dock-host-service.mjs:559`); the `tailscale` profile needs a manually supplied `--tailscale-address`.
- **ATS unknown for non-LAN cleartext `ws://`.** `NSAllowsLocalNetworking` may not cover Tailscale 100.64/10 or public IP literals.

## 2.3 Constraints implied by the problem

- The fix is mostly **integration + a client persistence refactor**, not new architecture: the installer already does the hard cross-platform/profile work.
- The client refactor must **migrate existing saved/relay config and keep the simulator env flow** working (no regressions).
- The Tailscale path must be made **addressable + ATS-permitted**, and that posture must be a recorded decision, not an accident.

# 3) Research Grounding (external + internal “ground truth”)

<!-- arch_skill:block:research_grounding:start -->
## External anchors (papers, systems, prior art)

- **Apple App Transport Security (ATS) — `NSAppTransportSecurity`** — *adopt as a hard constraint, partially reject the easy path* — `NSAllowsLocalNetworking: true` (already set in `CodexDockApp/Info.plist` / `project.yml`) permits cleartext loads to link-local, RFC1918 (`10/8`, `172.16/12`, `192.168/16`), and `.local` names. It does **not** clearly cover Tailscale's `100.64.0.0/10` CGNAT range or arbitrary public IP literals. ATS exceptions (`NSExceptionDomains`) key on **domain names, not IP literals**, so the scoped path is to address non-LAN hosts by **hostname** (Tailscale MagicDNS `*.ts.net`, or a DNS name for an opened box) and add a scoped `NSExceptionAllowsInsecureHTTPLoads` for that domain — or use `wss://`. Reject `NSAllowsArbitraryLoads` as the default (too broad) unless the user explicitly opts in.
- **Tailscale addressing (`tailscale ip -4`, `tailscale status --json`, MagicDNS)** — *adopt for autodetect* — a node's tailnet IPv4 is discoverable via `tailscale ip -4`; MagicDNS gives a stable `<host>.<tailnet>.ts.net` name. The installer already accepts `--tailscale-address` (hostname or IP) for the `tailscale` profile; autodetect should prefer the MagicDNS name (ATS-friendly) and fall back to the 100.x IP.
- **launchd (macOS) / systemd-user (Linux) service managers** — *already adopted in repo* — `codex-dock-host-service.mjs` renders and manages both; no new prior art needed. The home box uses the same installer with `--platform linux`.

## Internal ground truth (code as spec)

- Authoritative behavior anchors (do not reinvent):
  - `scripts/codex-dock-host-service.mjs:202-233` (`resolveRelayPublicURL`) — the **profile→URL resolver**; `tailscale` needs `--tailscale-address` or `TAILSCALE_IP/TAILSCALE_ADDRESS/TS_IP`; `lan` uses `--public-host`/`APP_SERVER_HOST`/`os.hostname()`; `manual` requires `--relay-public-url`; `simulator-local` uses loopback.
  - `scripts/codex-dock-host-service.mjs:471-533` (`renderHostServices`) — launchd plist + systemd unit rendering (cross-platform already done).
  - `scripts/codex-dock-host-service.mjs:556-579` (`appConfigJSON` / `appConfigEnv`) — emits a **single** host's app-facing config (`CODEX_DOCK_HOSTS`, `CODEX_DOCK_HOST_<SUFFIX>_{WS,NAME,AUTH_MODE}`); `authMode` is `none|bearer`.
  - `scripts/codex-dock-host-service.mjs:826-853` (`statusHostServices`) — health-checks `/readyz` + `/statusz` and the relay at its **public** URL when not `simulator-local`.
  - `scripts/dock-relay.mjs:673,766` — relay binds `server.listen(port, listenHost)` with `listenHost` default `0.0.0.0` (already listens on every interface incl. Tailscale).
  - `scripts/dock-relay-bonjour.mjs` — advertises `_codexdock._tcp.local.` via `dns-sd -R` (LAN-only mDNS; non-secret TXT `version/auth/scheme`).
  - `CodexDock/Configuration/DockHostConfiguration.swift:50-65` (`validatedWebSocketURL`) — the **canonical URL validator** (ws/wss, host required, no credentials). Reuse everywhere.
  - `CodexDock/Configuration/HostRegistry.swift:17-66` (`fromEnvironment`) — builds a multi-host registry from `CODEX_DOCK_HOSTS` + scoped per-host vars; the env seed/import format.
  - `CodexDock/State/DockStore.swift` (`AppServerDockClient`, multi-host fanout) — already loads **all** `registry.hosts` in parallel and tolerates per-host failure; the multi-host *consumer* already exists.
- Canonical path / owner to reuse:
  - On-device host persistence: `CodexDock/Configuration/RelayDiscovery.swift:55-119` — `LocalRelayConfiguration` + `FileLocalDockConfigurationStore` (Application Support JSON, actor, atomic write). **This is the owner path to generalize** from one record to a host **list** (`hosts.json`), keeping the actor + atomic-write pattern.
  - Host registry construction: `HostRegistry` — add a `from(persisted:)`/store-backed constructor next to `fromEnvironment`.
  - Service bringup: `scripts/codex-dock-host-service.mjs` is the **one** service owner; the Makefile only parametrizes it.
- Adjacent surfaces tied to the same contract family:
  - `CodexDock/Configuration/RelayBootstrapStore.swift:44,99-137,224-253` — boot precedence + `useConfiguration` builds a **one-host** registry and saves a single config; must read/write the new list store and upsert (not replace) on discovery.
  - `CodexDock/State/HostSettingsStore.swift:182-252` — `saveHost` persists a single config; must persist the full list, gain `removeHost`, and share the **same** store instance as bootstrap (collapse the split).
  - `CodexDock/Features/Hosts/HostsView.swift:102-161` — Add/Edit Relay form; needs remove + optional bearer/auth-mode + "add discovered".
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift` — consumes `RelayBootstrapState`; must still resolve to a `HostRegistry` (now from the store).
  - `Makefile:1-53,145-153` — host/profile/platform params + simulator env injection + (new) home-box path + URL emission.
  - `CodexDockApp/Info.plist` + `project.yml` (ATS keys) — adjacent to the Tailscale/open-IP serving decision.
  - Env var contract `CODEX_DOCK_HOSTS` / `CODEX_DOCK_HOST_<SUFFIX>_*` is shared by the installer (`appConfigEnv`) and the app (`HostRegistry.fromEnvironment`); both must keep agreeing.
- Compatibility posture (separate from `fallback_policy`):
  - Client persistence: **clean cutover with one-time migration** — import the existing single `relay-config.json` into the new `hosts.json` once, then stop reading the single path. No permanent dual store.
  - App-config / env contract: **extend, preserve names** — multi-host `app-config` is additive; single-host output stays a subset; the `CODEX_DOCK_HOSTS`/scoped-var names are preserved as the seed/import format.
  - Env at runtime: **preserve** the simulator flow by upserting env hosts into the store by id at launch.
- Existing patterns to reuse:
  - `RelayDiscovery.swift:79-119` — actor + Application Support JSON + atomic write + in-memory cache (clone for the list store).
  - `HostRegistry.envKeyComponent`/`hostIDs` parsing — reuse for env upsert.
  - `DockStore` `withTaskGroup` multi-host fanout + `DockLoadFailure` per-host status — already the consumer.
  - `codex-dock-host-service.test.mjs` / `dock-relay*.test.mjs` — test harness patterns to extend.
- Prompt surfaces / agent contract to reuse:
  - **N/A** — this change is configuration + networking + persistence, not LLM/agent-backed behavior. The only model surface (relay-owned OpenAI Realtime transcription) is untouched. Capability-first ladder does not apply; no new agent tooling is proposed.
- Duplicate or drifting paths relevant to this change:
  - Two host-config owners today (`RelayBootstrapStore` env/discovery/single-saved vs `HostSettingsStore` in-memory edits) with no shared persistence — the core drift this plan removes.
  - The home host appears in two half-states: env name-only with empty WS (`Makefile:46`, `.codex-dock/service.env`) — to be replaced by a real served endpoint.
- Capability-first opportunities before new tooling:
  - **N/A (not agent-backed).** Tailscale autodetect is a 1-call shell helper (`tailscale ip -4`), not a harness; multi-host handoff is "each box prints its URL; user pastes it" and the simulator multi-host seed already comes from existing env injection — no new merge or orchestration layer.
- Behavior-preservation signals already available:
  - `CodexDockTests/DockConfigurationTests.swift`, `DockStoreTests.swift`, `ThreadListMappingTests.swift` — guard host-registry + Dock behavior.
  - `scripts/codex-dock-host-service.test.mjs`, `scripts/dock-relay.test.mjs`, `dock-relay-phase5.test.mjs` — guard installer + relay behavior.
  - `make app SIM='iPhone 17'` end-to-end simulator launch — proves the env-seed flow still works after the store refactor.

## Decision gaps that must be resolved before implementation

All four plan-shaping decisions below are **resolved from approved intent** and recorded in Section 10 (Intent-derived). None remain open blockers:
- Env vs store precedence → store is SSOT; env upserts by id at launch (Decision Log 2026-05-28).
- Single `relay-config.json` → migrate once into `hosts.json`, clean cutover (Decision Log 2026-05-28).
- Client per-host auth representation → explicit `authMode` (`none|bearer`) mirroring `app-config` (Decision Log 2026-05-28).
- North Star confirmation → via the user's `plan-audit` loop (Decision Log 2026-05-28).

One **spike-gated decision** has a chosen default and named alternatives (not an open blocker): the iOS ATS posture for non-LAN cleartext `ws://`. Default = address non-LAN hosts by **hostname** (Tailscale MagicDNS / DNS) and add a **scoped `NSExceptionDomains` cleartext-ws exception**; verify on a real device in Phase 3. Named alternatives if the spike disproves the default: `wss://` via Tailscale Serve (secure, adds cert dependency) or user-opted `NSAllowsArbitraryLoads` (broad). This is surfaced for the user to weigh in during `plan-audit`; it does not block planning because a default is chosen and the alternatives are bounded.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- App config code: `CodexDock/Configuration/{DockHostConfiguration,HostRegistry,RelayDiscovery,RelayBootstrapStore}.swift`.
- App state: `CodexDock/State/{HostSettingsStore,DockStore,AppConnectivityStore}.swift`.
- Hosts UI: `CodexDock/Features/Hosts/HostsView.swift`; boot UI: `CodexDock/Features/Dock/CodexDockBootstrapView.swift`.
- Relay + installer: `scripts/dock-relay*.mjs`, `scripts/codex-dock-host-service.mjs` (+ `-env`, `-runtime` helpers), `scripts/dock-relay-bonjour.mjs`.
- Runtime/service files: `.codex-dock/` (`service.env`, `app-server.token`, `services/*.plist`, logs); `Makefile` is the command source of truth; `CodexDockApp/Info.plist` + `project.yml` hold ATS + Bonjour + mic usage keys.
- On-device persistence today: a single `relay-config.json` under Application Support (`FileLocalDockConfigurationStore.defaultFileURL()`), holding one `LocalRelayConfiguration` (display name + ws URL, no secret).

## 4.2 Control paths (runtime)

- **Boot:** `RelayBootstrapStore.start()` calls `HostRegistry.fromEnvironment` unconditionally via `try?` (`RelayBootstrapStore.swift:44`). It succeeds only when an endpoint env var is set (`CODEX_DOCK_PHONE_REACHABLE_APP_SERVER_WS`/`CODEX_DOCK_APP_SERVER_WS`, optionally `CODEX_DOCK_HOSTS`) — the simulator/dev case — and then goes `.ready(registry)` immediately (env wins). On a real device with no such env it **throws** (`DockHostConfiguration.fromEnvironment` → `.missingEndpoint`), so discovery + a saved-config load run concurrently (`RelayBootstrapStore.swift:49-55`): Bonjour auto-`use(first)` on the first resolved relay builds a **one-host** `HostRegistry` and saves a single `LocalRelayConfiguration`, while a previously saved `relay-config.json` is used as a fallback while discovering (`RelayBootstrapStore.swift:179-206`).
- **Render/load:** `CodexDockBootstrapView` resolves `.ready(HostRegistry)` → `DockStore`/`AppServerDockClient` fan out across **all** `registry.hosts` in parallel, loading sessions and tagging rows with host id; per-host failures degrade to offline/error without dropping other hosts.
- **In-app edit:** `HostsView` → `HostSettingsStore.saveHost(...)` validates and appends/edits the in-memory `HostRegistry`, but only persists a **single** `LocalRelayConfiguration` to `relay-config.json`.
- **Serving:** `make services` → `codex-dock-host-service.mjs install/start` renders launchd plists, ensures the raw app-server token, starts `codex app-server --listen ws://127.0.0.1:4500 --ws-auth capability-token` + `dock-relay.mjs --listen-host 0.0.0.0 --port 4510 --history-url ws://127.0.0.1:4500 --phone-auth none`, and advertises Bonjour. The phone-reachable URL is computed from the en0 LAN IP only.
- **Relay upstream:** `dock-relay.mjs` proxies phone JSON-RPC to the history app-server (bearer from `app-server.token`) and merges live loaded rows discovered by `ps`-scanning `127.0.0.1` codex app-servers.

## 4.3 Object model + key abstractions

- `DockHostConfiguration` (id, displayName, webSocketURL, optional bearerToken) + `validatedWebSocketURL` (the canonical URL validator).
- `HostRegistry` (non-empty `[DockHostConfiguration]`) with `fromEnvironment` (env-only multi-host construction).
- `DiscoveredRelay` (Bonjour result → `hostConfiguration`), `LocalRelayConfiguration` (persisted single relay), `FileLocalDockConfigurationStore` (actor; Application Support JSON; atomic write; in-memory cache) behind `LocalDockConfigurationStoring`.
- `RelayBootstrapStore` (boot state machine + discovery + single-save) and `HostSettingsStore` (in-app registry edit + per-host connection test) — **two owners, one shared persistence record**.
- Relay/installer: `createHostServiceConfig`, `resolveRelayPublicURL` (profiles), `renderHostServices` (launchd/systemd), `appConfigJSON`/`appConfigEnv` (single host).

## 4.4 Observability + failure behavior today

- App: Apple unified logging via `DockLog` (subsystem `com.aelaguiz.CodexDock`); root `AppConnectivityStore` aggregates per-host status (Online/Partial/Offline/Reconnecting/etc.).
- Relay: structured JSON to stderr via `dock-relay-logger.mjs`; `/readyz`, `/healthz`, `/statusz` endpoints; installer `status`/`doctor` health-check the relay at its public URL.
- Failure today: a second in-app-added host silently vanishes on relaunch (persistence gap, not a loud failure); off-LAN connect simply never resolves (no Tailscale address advertised/configured); the home host shows as configured-by-name with an empty/unreachable URL.

## 4.5 UI surfaces (ASCII mockups, current)

Current Hosts (Relay) screen — add/edit only, no remove, no token field, list reflects in-memory registry (not durable):

```
┌──────────────── Relay ────────────────[✓]┐
│ ▢ Amir-M5                         Online  │
│   ws://192.168.50.117:4510                │
│   3 sessions · last checked 1:02 PM       │
│   [ Test ] [ Edit ]                       │
│-------------------------------------------│
│ Add Relay                                 │
│  Relay ID   [ ____________ ]              │
│  Name       [ ____________ ]              │
│  WebSocket  [ ____________ ]              │
│            [   Save Relay   ]             │
└───────────────────────────────────────────┘
(no Remove control; no bearer/auth field; added rows do not survive relaunch)
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- New on-device SSOT: a multi-host list persisted as `hosts.json` under Application Support, owned by a generalized store (evolve `FileLocalDockConfigurationStore` → list-capable, keeping the actor + atomic-write + cache pattern). The single `relay-config.json` is read **once** for migration, then no longer written or read.
- No new app modules required beyond the generalized store + small model additions; UI stays in `HostsView`; boot stays in `RelayBootstrapStore`.
- Serving artifacts unchanged in shape (`.codex-dock/services/*`, `service.env`); the Makefile gains profile/platform/host params and a home-box path; `Info.plist`/`project.yml` gain the resolved ATS exception (scoped, hostname-based) if the Phase 3 spike requires it.

## 5.2 Control paths (future)

- **Boot precedence (unambiguous):** `RelayBootstrapStore.start()` → load the persistent host store. (1) If env hosts are present, **upsert them into the store by id** (simulator/dev seed/refresh). (2) If the store is non-empty, build `HostRegistry` from the store and go `.ready` — the store is authoritative. (3) If the store is empty, run a one-time migration import of any legacy `relay-config.json`, then if still empty start Bonjour discovery and **offer** discovered relays as adds. Discovery never replaces the store.
- **In-app edit:** `HostsView` → `HostSettingsStore` add/edit/**remove**/bearer-auth → writes the **full list** to the same store instance → recompute `HostRegistry`. `RelayBootstrapStore` and `HostSettingsStore` are injected with the **same** store actor (split collapsed).
- **Live propagation (reuse, not new):** when the persisted list changes at runtime, the recomputed `HostRegistry` is pushed to the live Dock via the **existing** `DockStore.updateRegistry(_:)` (`CodexDock/State/DockStore.swift:522`, which re-fans-out via `reload(showLoading:true)`). The root (`DockView.swift:35-75`) is rewired to construct `DockStore` + `HostSettingsStore` from the **same** store and forward list changes into `updateRegistry`. No new fanout machinery is introduced.
- **Empty-list edge case:** `HostRegistry` is non-empty by contract (`HostRegistry.init` throws on empty), and `DockStore` currently indexes `registry.hosts[0]` **unguarded** in `init(registry:)` (`DockStore.swift:504`), `updateRegistry` (`:525`), and `reload`/snapshot (`:596,810`). So removing the **last** host must be handled explicitly: Phase 1/2 route that case to the bootstrap "no hosts → discover / add a host" state (alongside the existing empty-construction path at `DockStore.swift:507-514`) instead of calling `updateRegistry` with an empty registry. This is required new guarding, not current safe behavior.
- **Discovery-as-add:** a resolved `DiscoveredRelay` becomes an explicit "Add this host" action that upserts into the store by id; auto-use only applies on a truly empty first-run store (preserves the zero-config first launch) and writes through the store.
- **Serving (per machine, one command):** `make services` parametrized by `HOST_SERVICE_PLATFORM` (`macos|linux`), `HOST_SERVICE_NETWORK_PROFILE` (`lan|tailscale|manual`), and host id/name. For `tailscale`, the Tailscale address is autodetected (`tailscale ip -4`, prefer MagicDNS name) unless supplied. The installer prints the exact phone-reachable `ws(s)://host:4510` URL (status/app-config already know it). The home Linux box runs the same installer with `--platform linux` (systemd-user).
- **Handoff:** each machine prints its **own one-host** phone-reachable URL; the user pastes it into Add-a-host on the device, and the durable on-device registry holds both. No multi-host merge is added: the simulator already receives multi-host env via the existing `make app` SIMCTL injection + the installer's `codex-dock-host-service-env.mjs` multi-host `service.env` writer, and `HostRegistry.fromEnvironment` already parses a `CODEX_DOCK_HOSTS` list (audit PLA-001).
- **One env-name writer:** the `CODEX_DOCK_HOSTS` / `CODEX_DOCK_HOST_<SUFFIX>_*` naming contract gets a single writer — the Makefile **consumes** `codex-dock-host-service.mjs app-config --format env` instead of hand-writing host names, and the per-id suffix rule (`hostIDToEnvSuffix`) is the authority that the Swift reader (`HostRegistry.envKeyComponent`) must match (audit PLA-002).

## 5.3 Object model + abstractions (future)

- `DockHostConfiguration` gains an explicit `authMode` (`none|bearer`, default `none`); `bearer` requires a user-entered `bearerToken` (on-device only, never logged).
- A `PersistedHost` / `LocalHostsConfiguration` codable list (id, name, ws URL, authMode, optional token) replaces single `LocalRelayConfiguration`; `LocalDockConfigurationStoring` evolves to load/save a list + `upsert(byId:)` + `remove(id:)`.
- `HostRegistry` gains `from(persisted:)`; `fromEnvironment` is retained as the env seed/import reader feeding `upsert`.
- Installer: `resolveRelayPublicURL` `tailscale` branch gains an autodetected address input; the Makefile consumes `app-config --format env` so host env-var names have one writer; no new service abstraction and **no multi-host merge** (dropped per audit PLA-001).

## 5.4 Invariants and boundaries

- Exactly one persistent host store; `RelayBootstrapStore` + `HostSettingsStore` share it via DI (no second writer). Enforced by construction (single injected dependency), not by greps.
- Env/discovery only ever `upsert`/`remove` through the store API; they cannot replace the list.
- All host URLs pass `DockHostConfiguration.validatedWebSocketURL`.
- Relay-only phone endpoint; `auth=none` default; bearer optional + user-entered; no secret persisted in logs or Bonjour TXT.
- Tailscale code confined to installer address resolution keyed by the `tailscale` profile string.
- Migration is a one-time import + clean cutover; no permanent dual store (`fallback_policy: forbidden`).

## 5.5 UI surfaces (ASCII mockups, future)

Target Hosts (Relay) screen — durable multi-host with remove, optional auth, and discovered-relay add:

```
┌──────────────── Relay ────────────────[✓]┐
│ ▢ Amir-M5                         Online  │
│   ws://amir-m5.tailnet.ts.net:4510  none  │
│   3 sessions · [ Test ] [ Edit ] [Remove] │
│ ▢ Home                            Offline │
│   ws://100.x.y.z:4510               none  │
│   [ Test ] [ Edit ] [ Remove ]            │
│-------------------------------------------│
│ Discovered on this network:               │
│   • Codex Dock studio  [ + Add ]          │
│-------------------------------------------│
│ Add / Edit Host                           │
│  Host ID    [ ____________ ]              │
│  Name       [ ____________ ]              │
│  WebSocket  [ ws:// or wss:// ]           │
│  Auth       (•) None  ( ) Bearer          │
│  Token      [ ______ ] (only if Bearer)   │
│            [   Save Host   ]              │
└───────────────────────────────────────────┘
(added/edited/removed hosts persist across cold start; this list is the SSOT)
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Persistence | `CodexDock/Configuration/RelayDiscovery.swift:55-119` | `LocalRelayConfiguration`, `FileLocalDockConfigurationStore`, `LocalDockConfigurationStoring` | Stores **one** relay (name+url) in `relay-config.json` | Generalize to a **host list** (`hosts.json`): load/save `[PersistedHost]`, `upsert(byId:)`, `remove(id:)`; one-time import of legacy `relay-config.json` | On-device SSOT for multi-host; keep actor+atomic-write pattern | `LocalDockConfigurationStoring` becomes list-based; legacy single read kept only for migration | `DockConfigurationTests`, new store tests |
| Model | `CodexDock/Configuration/DockHostConfiguration.swift:3-28,50-65` | `DockHostConfiguration`, `validatedWebSocketURL` | id/name/url/optional bearer; canonical validator | Add explicit `authMode` (`none|bearer`, default none); reuse validator unchanged | Mirror installer `app-config` authMode; enable bearer hosts in-app | `authMode` field; `validatedWebSocketURL` reused everywhere | `DockConfigurationTests` |
| Registry | `CodexDock/Configuration/HostRegistry.swift:17-66` | `HostRegistry.fromEnvironment` | Builds multi-host registry from env only | Add `from(persisted:)`; keep `fromEnvironment` as the env **seed/import** reader feeding `upsert` | Store becomes authoritative; env demoted to seed | `HostRegistry.from(persisted:)` | `DockConfigurationTests`, `DockStoreTests` |
| Boot | `CodexDock/Configuration/RelayBootstrapStore.swift:36-56,99-137,224-253` | `start`, `handleDiscoveredRelays`, `use`, `useConfiguration` | env wins when an endpoint env var is set; else discovery + saved run concurrently — first discovered relay auto-used → one-host registry + single save, saved config as fallback | Read store; env upsert→store; store-authoritative `.ready`; one-time migrate; discovery **offers add** (auto-use only on empty first run); build registry from full list; share the store instance with settings | Unambiguous precedence; durable multi-host; no split owner | Injected shared store; `upsert`/`remove` calls | `DockStoreTests` (bootstrap), new bootstrap tests |
| Settings | `CodexDock/State/HostSettingsStore.swift:84-127,182-252` | `HostSettingsStore`, `saveHost` | Persists a **single** config; in-memory edits; no remove | Persist **full list** via shared store; add `removeHost`; accept bearer/auth-mode; same store instance as bootstrap | Collapse split source of truth; complete CRUD | `removeHost(id:)`; `saveHost` writes list + authMode | new `HostSettingsStore` tests |
| Hosts UI | `CodexDock/Features/Hosts/HostsView.swift:82-161,237-288` | `HostsView`, `HostDraft`, `hostEditor` | Add/Edit only; no remove; no token | Add **Remove**; optional **Auth mode + Token** fields; "Add discovered relay" action | Real "add a host" UX on the SSOT | Draft gains authMode/token; remove + add-discovered controls | snapshot/preview only (manual) |
| Boot UI | `CodexDock/Features/Dock/CodexDockBootstrapView.swift` | bootstrap state consumer | Renders discovering/ready | Render discovered relays as add-affordances; unchanged ready path | Discovery-as-add UX | none (state-driven) | manual |
| Dock store | `CodexDock/State/DockStore.swift:492-505` (init) + `:522-528` (`updateRegistry`) | `DockStore.init(registry:)`, `updateRegistry(_:)` | Takes `registry.hosts` once; `updateRegistry` (522-528) re-fans-out; `hosts[0]` indexed **unguarded** in init/updateRegistry/reload/snapshot (would crash on empty) | **Reuse** `updateRegistry(_:)` for live list changes; add empty-guard so last-host-removed routes to empty/bootstrap path (no `hosts[0]` crash) | Live "add a host" reflects in Dock without relaunch | none new (reuse `updateRegistry`) | `DockStoreTests` |
| Root wiring | `CodexDock/Features/Dock/DockView.swift:35-75` | `CodexDockRootView.init`, store construction | Builds `DockStore` + `HostSettingsStore` separately from one initial registry | Inject the **same** persistent store; forward `HostSettingsStore` list changes → `DockStore.updateRegistry` | One SSOT observed by both; no split | shared store dependency | `DockStoreTests` (wiring), manual |
| Installer | `scripts/codex-dock-host-service.mjs:202-233` | `resolveRelayPublicURL` (`tailscale` branch) | Requires `--tailscale-address`/`TS_IP` | Accept autodetected address (prefer MagicDNS name); keep manual override | Make Tailscale serving one-command | autodetect input param | `codex-dock-host-service.test.mjs` |
| Env-name contract | `scripts/codex-dock-host-service.mjs:194-200,556-579` + `Makefile:44-49,83,149` + `CodexDock/Configuration/HostRegistry.swift:68-75,102-109` | `hostIDToEnvSuffix`, `appConfigEnv`, Makefile env-file/app SIMCTL, `envKeyComponent` | **4 writers** of `CODEX_DOCK_HOST_<SUFFIX>_*`; 2 divergent suffix rules (Node regex collapses repeats → `MY_HOST`; Swift scalar map → `MY__HOST`) | Make installer `app-config --format env` the **single writer**: Makefile consumes it; delete hardcoded `AMIR_M5`/`HOME` literals; add a cross-language suffix-agreement test + sync comments at both suffix functions | Prevent off-LAN host-config drift / silent connect failure | one writer + agreement test | `codex-dock-host-service.test.mjs`, `DockConfigurationTests` |
| Tailscale detect | `scripts/codex-dock-host-service.mjs` (+ maybe `-runtime`) or `Makefile` | new small helper | none | Add `tailscale ip -4` / MagicDNS resolution helper used by the `tailscale` profile | One-command Tailscale serving | `resolveTailscaleAddress()` (no new orchestration layer) | `codex-dock-host-service.test.mjs` (parse) |
| Make | `Makefile:1-53,80-123,145-153` | service vars + `services`, `app`, `app-config` | macos+lan+single host hardwired; en0 IP; hand-writes host env names | Parametrize `HOST_SERVICE_PLATFORM`/`NETWORK_PROFILE`/host; emit phone URL; add home-box path; **consume installer `app-config --format env`** for host names (delete hardcoded `AMIR_M5`/`HOME`); keep simulator env-injection working | Easy per-machine + home box; one env-name writer | new make vars/targets | manual + status |
| Home box | `Makefile` (+ docs) | new `home-services` path | empty `CODEX_DOCK_HOST_HOME_WS` | Document/automate running the installer on the home Linux box (`--platform linux`), reachable via Tailscale or open IP; an SSH convenience wrapper is a **named follow-up**, not required | Wire the second host end-to-end | reuse installer; no new infra | manual |
| ATS | `CodexDockApp/Info.plist`, `project.yml` (ATS keys) | `NSAppTransportSecurity` | `NSAllowsLocalNetworking: true` only | Per the Phase 3 spike: add a **scoped `NSExceptionDomains`** cleartext-ws exception for tailnet/DNS hostnames (default), or `wss`/Serve, or user-opted broad load | Let non-LAN cleartext `ws://` connect | scoped ATS exception | device spike (manual) |
| Docs | `README.md`, `AGENTS.md` (Service Path) | runbook sections | single-host LAN runbook | Update to multi-host add-a-host + per-machine/home serving + Tailscale/open-IP + ATS note | Keep runnable docs truthful | n/a | n/a |

Rows above include non-code surfaces (Makefile, Info.plist/project.yml, README/AGENTS) because they participate in the same host-config / serving contract family.

## Migration notes

* **Canonical owner path / shared code path:** the generalized list store behind `LocalDockConfigurationStoring` (evolved `FileLocalDockConfigurationStore`) is the one on-device host SSOT; the installer (`codex-dock-host-service.mjs`) is the one service owner.
* **Deprecated APIs (if any):** single-record `LocalRelayConfiguration` save/load semantics (kept only as a one-time migration source, then removed from live read/write paths).
* **Delete list:** the live read/write of single `relay-config.json` after migration; the bootstrap "auto-use first discovered → one-host registry → single save" precedence branch (replaced by store-authoritative + upsert); the empty `CODEX_DOCK_HOST_HOME_WS` placeholder once the home box is wired.
* **Adjacent surfaces tied to the same contract family:** env var contract (`CODEX_DOCK_HOSTS`, `CODEX_DOCK_HOST_<SUFFIX>_{WS,NAME,AUTH_MODE,...}`) shared by installer `appConfigEnv` and app `HostRegistry.fromEnvironment` — preserve names; `Info.plist`/`project.yml` ATS; README/AGENTS runbooks.
* **Compatibility posture / cutover plan:** client persistence = clean cutover + one-time import (no dual store). App-config/env = extend, preserve names (single-host stays a subset). Runtime env = preserve simulator flow via upsert.
* **Capability-replacing harnesses to delete or justify:** none — not agent-backed; Tailscale autodetect is a single shell call and the handoff is print-URL (no merge), neither is a new harness.
* **Env-name source of truth:** `codex-dock-host-service.mjs app-config --format env` (suffix via `hostIDToEnvSuffix`) is the single writer; the Makefile consumes it (delete the hardcoded `CODEX_DOCK_HOST_AMIR_M5_*`/`HOME_*` literals) and the Swift reader `envKeyComponent` must agree (cross-language test + sync comments).
* **Live docs/comments/instructions to update or delete:** README "App-Server Runbook"/"Service Path", AGENTS.md "Service Path" (single-host LAN assumptions); fold the related multi-host doc rather than duplicate.
* **Behavior-preservation signals for refactors:** `DockConfigurationTests`, `DockStoreTests`, `ThreadListMappingTests`, `codex-dock-host-service.test.mjs`, `dock-relay*.test.mjs`, plus a real `make app SIM='iPhone 17'` to prove the env-seed simulator flow survives the store refactor.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Persistence | `FileLocalDockConfigurationStore` actor | One list store + upsert/remove; all writers go through it | Removes the two-owner split that loses hosts | include |
| Registry construction | `HostRegistry.fromEnvironment` | Env feeds `upsert`, not a competing registry | Single precedence story | include |
| URL validation | `DockHostConfiguration.validatedWebSocketURL` | Reuse the one validator in settings + bootstrap + discovery + manual | Consistent URL hygiene | include |
| Service bringup | `codex-dock-host-service.mjs` | One installer, Makefile only parametrizes | No second service path for the home box | include |
| Multi-host consumer | `DockStore` fanout | Already loads all hosts in parallel; reuse as-is | Avoid reinventing multi-host load | include (no change beyond registry source) |
| Account rotation / login | n/a | — | Out of MVP per related docs | exclude |
| QR-code handoff | n/a | — | Nice-to-have; URL paste suffices for now | exclude (named follow-up) |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

Destination map = TL;DR + Section 0 + Sections 5-6 + Decision Log. Depth-first order: Phase 1 proves the riskiest seam (durable on-device SSOT + migration) end-to-end with one host on the easiest transport (LAN); later phases widen along named axes — UX surface (P2), serving profiles incl. Tailscale + ATS (P3), and the second machine + handoff + offline tolerance (P4). The home box and Tailscale are carried by named later phases, not dropped.

## Phase 1 — Durable on-device multi-host store as the SSOT (+ one-time migration/env import)

* Goal: A persistent multi-host store (`hosts.json`) is the authoritative on-device host list; the app boots from it; a host written through the existing path survives an app cold start; legacy single `relay-config.json` and env hosts are imported/upserted (not competing). Proven on the simulator with at least one host loading real sessions. This is the first working slice through the canonical persistence owner path and the highest-risk seam (source-of-truth precedence).
* Work: Generalize the persistence owner (`FileLocalDockConfigurationStore` / `LocalDockConfigurationStoring`) from one record to a host list with upsert/remove + one-time migration; add `HostRegistry.from(persisted:)`; rewire `RelayBootstrapStore` precedence to be store-authoritative with explicit env upsert and discovery-as-add; finalize the persistence shape by adding `authMode` to the model now (UI surfacing is Phase 2). Move the minimal `HostSettingsStore.saveHost` list-write into this phase so the in-app save path is durable end-to-end through the SSOT (the bearer/auth-mode fields, Remove control, and discovery-as-add UI stay in Phase 2). Reuse the actor + atomic-write + cache pattern; reuse `validatedWebSocketURL`.
* Checklist (must all be done):
  - Add a codable multi-host type (`PersistedHost` + `LocalHostsConfiguration` list) and evolve `LocalDockConfigurationStoring` / `FileLocalDockConfigurationStore` to load/save the list with `upsert(byId:)` and `remove(id:)`, atomic write, actor isolation, in-memory cache; persist to `hosts.json` under Application Support.
  - Add `authMode` (`none|bearer`, default `none`) to `DockHostConfiguration`; encode/decode it (and any token) in `PersistedHost`; never log the token.
  - One-time migration: when `hosts.json` is absent but legacy `relay-config.json` exists, import that record into the list once, then stop reading/writing the legacy single path on the live flow.
  - Add `HostRegistry.from(persisted:)`; retain `HostRegistry.fromEnvironment` and use it to upsert env hosts into the store by id at launch.
  - Rewire `RelayBootstrapStore.start()` precedence to: load store → upsert env hosts → if store non-empty build registry from the full list and go `.ready` → else run migration → else start discovery; delete the old "auto-use first discovered → one-host registry → single save" precedence branch (auto-use now writes through the store, only on a truly empty first run).
  - Inject one shared store instance into `RelayBootstrapStore` (and expose the same injection point for Phase 2 root wiring).
  - Rewrite `HostSettingsStore.saveHost` to persist the **full list** through the shared store (default `authMode: none`) instead of a single `LocalRelayConfiguration`, so an in-app save is durable on the SSOT in this phase (audit PLA-003).
  - Handle last-host-removed by routing to the empty/bootstrap state instead of indexing `registry.hosts[0]`.
* Verification (required proof): `rtk swift test --filter DockStoreTests` and `--filter DockConfigurationTests` covering store round-trip (add/persist/reload), `saveHost` writes the full list (form-add → store → reload durability), one-time migration import (legacy single → list), env upsert-by-id, `HostRegistry.from(persisted:)`, store-authoritative bootstrap precedence, and `authMode` round-trip. Form-add durability is proven by these tests, **not** by the simulator run (injected env masks the form path on the simulator — audit PLA-003). Behavior-preservation: `rtk make app SIM='iPhone 17'` still launches and loads via the env-seed flow.
* Docs/comments (propagation; only if needed): one short comment at the store boundary stating "on-device SSOT for hosts; env/discovery upsert only; migrate-once from relay-config.json".
* Exit criteria (all required):
  - `hosts.json` list store exists; add/edit/remove/persist/reload proven by passing unit tests.
  - Legacy `relay-config.json` imported exactly once and no longer read/written on the live path; migration proven by a test.
  - `RelayBootstrapStore` builds the registry from the store; env upserts; discovery does not replace; last-host-removed routes to empty state — all proven by tests.
  - `authMode` persisted and round-tripped (default `none`).
  - `HostSettingsStore.saveHost` writes the full list to the store and a form-added host survives a cold start — proven by a unit/integration test (the simulator env-seed launch is a preservation check only, since injected env masks the form path).
  - `rtk make app SIM='iPhone 17'` launches and loads with the env-seed flow intact.
* Rollback: `git` revert of the phase restores the single-record store; no data loss because migration only reads the legacy file.

## Phase 2 — Complete in-app "Add a host" UX on the SSOT (edit/remove/bearer + discovery-as-add + live Dock propagation)

* Goal: `HostsView` is a real multi-host manager (add/edit/remove + optional bearer/auth-mode); Bonjour relays are offered as explicit adds; list changes reflect in the live Dock without relaunch. Widens the UX axis on top of Phase 1's store.
* Work: Surface the store CRUD in the UI and connect it to the live Dock via the existing `DockStore.updateRegistry(_:)`; make discovery additive; share one store across bootstrap, settings, and Dock through the root.
* Checklist (must all be done):
  - `HostsView`: add a **Remove** control (→ `HostSettingsStore.removeHost`); add **Auth mode** (None/Bearer) and a **Token** field shown only for Bearer; reuse `validatedWebSocketURL`; friendly validation errors.
  - `HostSettingsStore`: add `removeHost(id:)` and carry `authMode`/token through `saveHost` (the full-list write itself landed in Phase 1); use the **same** store instance injected into `RelayBootstrapStore`.
  - Root wiring (`CodexDock/Features/Dock/DockView.swift:35-75`): construct `DockStore` and `HostSettingsStore` from the same store; forward list changes into `DockStore.updateRegistry(_:)`; keep `AppConnectivityStore` host-test reporting wired across registry changes (`setConnectivityReporter`), and ensure it reflects **added/removed** hosts (not just test status) when the list changes (audit N1).
  - Discovery-as-add: `RelayBootstrapStore.handleDiscoveredRelays` upserts discovered relays by id and offers them as adds (no auto-replace of the list); `CodexDockBootstrapView` renders the add affordance; auto-use only on a truly empty first-run store.
* Verification (required proof): `rtk swift test --filter DockStoreTests` and `--filter ThreadDetailStoreTests` (as relevant) covering `saveHost` full-list persistence, `removeHost`, `authMode`/token persistence, discovery upsert-not-replace, `updateRegistry` invoked on list change, and the empty-list route. Manual (recorded): add/edit/remove in the running sim app reflects in the Dock without relaunch; add a bearer host.
* Docs/comments (propagation; only if needed): none beyond Phase 1's boundary comment.
* Exit criteria (all required):
  - Add/edit/remove all persist and survive a cold start; proven by unit tests + recorded manual check.
  - A bearer host can be added (token stored on device only, never logged); proven by a persistence test.
  - A discovered relay adds without wiping the existing list; proven by a test.
  - Live Dock reflects list changes via `updateRegistry` (and last-host-removed routes to empty) — proven by tests.
* Rollback: `git` revert hides remove/auth UI and reverts root wiring; Phase 1 store remains intact.

## Phase 3 — Easy per-machine serving: selectable profile + Tailscale autodetect + clear URL + resolved ATS (Mac)

* Goal: One idempotent command serves a machine with a chosen network profile (`lan`/open-IP or `tailscale`), autodetects the Tailscale address, prints the exact phone-reachable URL, and the iOS app can actually connect over that non-LAN endpoint (ATS resolved). Proven on the Mac. Widens the serving/transport axis.
* Work: Parametrize the Makefile over the installer's existing profiles; add Tailscale-address autodetect feeding the `tailscale` profile; surface the phone-reachable URL; resolve and apply the iOS ATS posture for non-LAN cleartext `ws://` (default: hostname addressing + scoped `NSExceptionDomains` exception), keeping LAN/RFC1918 on `NSAllowsLocalNetworking`.
* Checklist (must all be done):
  - Makefile: pass `HOST_SERVICE_PLATFORM`, `HOST_SERVICE_NETWORK_PROFILE`, host id/name through to `codex-dock-host-service.mjs`; `make services` works for `lan` and `tailscale`; keep the simulator env-injection (`make app`) working.
  - Converge host env-var names to **one writer** (audit PLA-002): the Makefile consumes `codex-dock-host-service.mjs app-config --format env` for `CODEX_DOCK_HOST_<SUFFIX>_*`; delete the hardcoded `CODEX_DOCK_HOST_AMIR_M5_*`/`HOME_*` literals; add a cross-language suffix-agreement test (`hostIDToEnvSuffix` ↔ Swift `envKeyComponent`) and a sync comment at both suffix functions.
  - Add Tailscale-address autodetect (`tailscale ip -4`; prefer the MagicDNS `*.ts.net` name) feeding the installer `tailscale` profile; preserve manual `--tailscale-address` override; fail loud if `tailscale` profile is selected and no address can be resolved.
  - Emit the exact phone-reachable `ws(s)://host:4510` URL prominently from `make services` / status (reuse `appConfigJSON`/`statusHostServices` public URL).
  - Resolve the ATS posture and apply it in `project.yml` (XcodeGen source of truth) + regenerate: default = address non-LAN hosts by hostname (MagicDNS/DNS) and add a scoped `NSExceptionDomains` `NSExceptionAllowsInsecureHTTPLoads` entry for the tailnet/DNS domain; keep `NSAllowsLocalNetworking` for LAN. If the device spike disproves the default, take a named alternative (`wss` via Tailscale Serve, or user-opted `NSAllowsArbitraryLoads`) and record it in the Decision Log.
* Verification (required proof): `rtk npm run test:relay` / installer tests covering `tailscale` URL emission, Tailscale-address autodetect parsing, profile selection, and the `app-config --format env` single-writer output; a cross-language suffix-agreement test (`hostIDToEnvSuffix` ↔ `envKeyComponent`); existing launchd render stays green. Manual/Amir-owned (recorded, non-blocking for agent work): a real device connects to the Mac over the chosen non-LAN endpoint (the ATS spike) and over LAN/open-IP.
* Docs/comments (propagation; only if needed): update `README.md` + `AGENTS.md` serving runbook for profile selection, the emitted URL, and the ATS/Tailscale note (this update is required for phase completeness).
* Exit criteria (all required):
  - `make services NETWORK_PROFILE=tailscale` and `=lan` bring up the Mac and print a phone-reachable URL; Tailscale address autodetected or loudly required; proven by installer tests + recorded run.
  - The chosen ATS posture is decided, applied in `project.yml`, and regenerated; the scoped-hostname default is implemented (or a recorded Decision Log alternative is).
  - A real-device connect over the non-LAN endpoint is recorded as Amir-owned manual QA; on failure the named alternative is taken and re-recorded.
  - Host env-var names have a **single writer** (Makefile consumes installer `app-config --format env`; hardcoded `AMIR_M5`/`HOME` literals deleted); Node↔Swift suffix agreement proven by a test.
  - `README.md` + `AGENTS.md` serving runbook updated to match.
* Rollback: `git` revert of Makefile params + ATS change; `lan` remains the working default.

## Phase 4 — Wire the second "home" Linux box (systemd) end-to-end + multi-host handoff + offline tolerance

* Goal: The home Linux box serves via the same installer (systemd-user), reachable over Tailscale or open IP; both hosts are added on the phone and the Dock tolerates one being offline; a handoff makes adding both easy. Widens to the second machine and proves the full multi-host story.
* Work: Bring up the home box with the existing cross-platform installer (`--platform linux` + chosen profile); replace the empty home placeholder with a real served endpoint + emitted URL; verify partial-availability end-to-end. The handoff is "each machine prints its own one-host URL → user adds it in-app" — **no multi-host merge** (audit PLA-001): the durable on-device registry holds both, and the simulator's multi-host env already comes from the existing `make app` injection + `service.env` writer.
* Checklist (must all be done):
  - Document and provide a runnable path to bring up the home box: run `codex-dock-host-service.mjs` (via `make services`) with `--platform linux` + chosen profile on the box (user SSHes in); a `make` SSH-convenience target that runs the **same** installer remotely is a **named follow-up**, not required (no new service infra).
  - Replace the empty `CODEX_DOCK_HOST_HOME_WS` placeholder; the home box prints its own phone-reachable URL for the chosen profile.
  - Handoff: each machine prints its own one-host phone-reachable URL; the user adds each in-app on the device (the SSOT holds both). No multi-host merge is added — device multi-host is the in-app registry (P1/P2) and the simulator already receives multi-host env from existing injection (audit PLA-001).
  - Verify partial availability: both hosts added on the phone; take one offline; the other still loads (reuse `DockStore` fanout + `AppConnectivityStore` `Partial` state).
* Verification (required proof): `rtk npm run test:relay` / installer tests for the existing systemd render plus the Phase 3 `app-config --format env` single-writer/suffix-agreement tests; manual/Amir-owned (recorded): home box served via systemd reachable over Tailscale and open IP, phone adds both hosts and they persist, one-host-offline tolerance holds, and no secret is present on the phone.
* Docs/comments (propagation; only if needed): update `README.md` + `AGENTS.md` for the multi-host + home-box runbook; fold the related `CODEX_DOCK_MULTI_HOST_SERVICE_SETUP_ROBUSTNESS_2026-05-28.md` content rather than duplicating (this fold/update is required for phase completeness).
* Exit criteria (all required):
  - Home box served via systemd and reachable over both transports; recorded.
  - Both hosts added on a real phone (each pasted from its machine's emitted URL) persist across cold start; recorded manual QA.
  - One-host-offline tolerance proven (the other still loads); recorded.
  - `README.md` + `AGENTS.md` updated and the related multi-host doc folded (no duplicate source of truth).
* Rollback: the home host is additive — `git` revert removes the home host wiring; the Mac path is unaffected.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Unit tests (contracts)

- Swift: persistent multi-host store round-trip; migration import (single `relay-config.json` → list; env upsert-by-id); `HostRegistry` from store; precedence rules; bearer/auth-mode persistence. Reuse `DockConfigurationTests` / `DockStoreTests` style.
- Node: `app-config --format env` single-writer output + Node↔Swift suffix agreement; `tailscale` URL emission + Tailscale-address autodetect parsing; launchd/systemd render unchanged. Reuse `codex-dock-host-service.test.mjs`.

## 8.2 Integration tests (flows)

- Bootstrap → store → `DockStore` multi-host fanout loads all hosts (reuse existing fanout + `DockSessionLoading`).
- HostSettings add/edit/remove → store → registry + Dock reflect the change; discovery add upserts without wiping.

## 8.3 E2E / device tests (realistic)

- Finalization, non-blocking, Amir-owned manual: two machines served (launchd + systemd), add both on a real phone, persist across cold start, load over LAN/open-IP and Tailscale, one-offline tolerance, no phone secret. Includes the ATS connection spike result.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

- Land the client store + migration first (reads old `relay-config.json` once, then owns `hosts.json`); then serving ergonomics (profiles/URL/autodetect + ATS); then the home box + handoff. Each phase is independently shippable and reversible.

## 9.2 Telemetry changes

- Reuse `DockLog` (app) and `scripts/dock-relay-logger.mjs` (relay). Add a bootstrap log line for host count + source (store/env/discovery). Relay `/statusz` already reports network profile + public URL.

## 9.3 Operational runbook

- Per-machine: `make services` with platform/profile/host params; home box via systemd; how to read the emitted phone-reachable URL and paste it into the app; Tailscale-vs-open-IP notes and the ATS posture. Update `README.md` + `AGENTS.md` service path.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: cold-reader 1 (spine: frontmatter, TL;DR, §0/1/2/7/8/9/10 + helper blocks), cold-reader 2 (architecture + grounding: §3/4/5/6/7 vs real code), self-integrator.
- Scope checked:
  - TL;DR ↔ Section 0 ↔ Section 7 agreement on outcome, scope, and the 4-phase shape.
  - Section 7 obligation sweep: deletes (legacy `relay-config.json` read), one-time migration, ATS change, docs updates, home-box wiring all live in `Checklist`/`Exit criteria`.
  - Section 3/5/6/7 agreement on canonical owner path, adjacent surfaces, compatibility posture, deletes, adoption scope.
  - Grounding of code claims (RelayDiscovery store, RelayBootstrapStore precedence, HostSettingsStore single-save + no remove, DockStore `updateRegistry`/`hosts[0]`, host-service profiles/render/app-config/status, HostRegistry env construction) against the real files.
  - `fallback_policy: forbidden` vs the one-time migration (not a permanent dual path).
- Findings summary:
  - Spine: consistent end to end; all four resolved decisions in the Decision Log match what TL;DR/§0/§7 rely on; no orphan obligations; no unresolved branchy language (ATS is a chosen default with bounded named alternatives, not an open fork).
  - Architecture/grounding: three real precision errors in the description of **current** behavior (not in the plan's decisions): (1) §4.2 over-simplified `HostRegistry.fromEnvironment` (it is called unconditionally and throws on a bare device, rather than "if env present"); (2) §6 Boot row over-simplified current precedence (discovery + saved run concurrently); (3) §5.2/§6 implied an existing safe empty-list path, but `DockStore` indexes `hosts[0]` unguarded in `init`/`updateRegistry`/`reload`/snapshot, so empty-guarding is required new work; plus an imprecise `updateRegistry` line cite.
- Integrated repairs:
  - §4.2 Boot rewritten to the accurate `try?`-unconditional-then-throw behavior with exact anchors.
  - §6 Boot "current behavior" cell corrected to concurrent discovery + saved fallback.
  - §5.2 empty-list note + §6 Dock-store row corrected to state the unguarded `hosts[0]` reality and that the empty-guard is required Phase 1/2 work; `updateRegistry` cite fixed to `:522-528`.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Intent-derived: North Star confirmation via plan-audit loop

- **Blocker:** `arch-step new` normally stops for explicit North Star confirmation before deeper planning.
- **Consulted:** the user's `/goal` directive (produce an `arch-step auto-plan`, then run `/plan-audit` and iterate until aligned, do not implement) and the session `/goal` stop-hook instruction not to pause for direction.
- **Intent says:** the user authorized the full auto-plan up front and chose `plan-audit` iteration as the confirmation/alignment mechanism.
- **Decision:** draft the North Star directly from the detailed goal, set `status: active`, proceed through the gated auto-plan stages, and treat `plan-audit` as the confirmation gate. North Star remains open to correction during that loop.
- **Consequences:** no interactive stop before `research`; any North Star correction from plan-audit is folded back via the normal commands.

## 2026-05-28 - Intent-derived: persistent store is the on-device SSOT; env/discovery upsert

- **Blocker:** how should env (`CODEX_DOCK_HOSTS...`) and Bonjour relate to a new persistent multi-host store once it exists?
- **Consulted:** TL;DR, Section 0.2/0.5, Problem 2.2 (split source of truth), `RelayBootstrapStore.swift:44`, `Makefile:149` (simulator env injection).
- **Intent says:** one authoritative durable list; the simulator `make app` env flow must keep working; discovery must not wipe the user's list.
- **Decision:** the persistent store is authoritative on device; at launch, env entries **upsert into the store by host id** (so the simulator stays fresh and a real device with empty env relies on the store + in-app adds); Bonjour offers explicit add/upsert, never replace.
- **Consequences:** removes precedence ambiguity; preserves the simulator flow; `HostRegistry` gains a "from store" constructor while `fromEnvironment` becomes the seed/import reader.

## 2026-05-28 - Intent-derived: migrate single relay-config.json to a multi-host list (clean cutover)

- **Blocker:** keep the single `relay-config.json` path alongside a new list, or migrate?
- **Consulted:** Section 0.5 (one source of truth, no fallbacks), `RelayDiscovery.swift:55-119` (`LocalRelayConfiguration` + `FileLocalDockConfigurationStore`).
- **Intent says:** no dual sources of truth; no runtime shims; git retains history.
- **Decision:** introduce a multi-host `hosts.json` list as the SSOT; on first launch import any existing single `relay-config.json` into it once, then own the list and stop reading the single path (clean cutover with one-time migration).
- **Consequences:** one persistence surface; a targeted migration test is required; the old single-config read path is deleted after import.

## 2026-05-28 - Intent-derived: client host model carries explicit auth mode

- **Blocker:** how should the app represent per-host auth so it can add a bearer-protected host and mirror the relay/app-config contract?
- **Consulted:** `codex-dock-host-service.mjs:556-579` (`authMode` in `app-config`), `DockHostConfiguration.swift` (has `bearerToken`, no explicit mode), AGENTS.md secrets rules.
- **Intent says:** default no-secret personal path, optional bearer; mirror the host-service `authMode` (`none|bearer`).
- **Decision:** add an explicit `authMode` (`none|bearer`) to the client host model, defaulting to `none`; `bearer` requires a user-entered token (stored on device only, never logged). Keeps parity with the installer's emitted `app-config`.
- **Consequences:** the Add-a-host form gains an optional token + mode; persistence and tests must cover it.

## 2026-05-28 - Intent-derived: live host-list changes propagate via existing DockStore.updateRegistry (deep-dive pass 2)

- **Blocker:** does adding/removing a host in-app reflect in the live Dock, or only after relaunch? And how, without new fanout machinery?
- **Consulted:** `CodexDock/State/DockStore.swift:492-527` (`updateRegistry` already re-fans-out), `CodexDock/Features/Dock/DockView.swift:35-75` (root constructs stores separately), Section 0.5 (one SSOT), Section 1.4 (reuse over reinvention).
- **Intent says:** one observed source of truth; reuse existing primitives; "add a host" should be real and immediate.
- **Decision:** route in-app list changes through the shared store, recompute `HostRegistry`, and push it into the existing `DockStore.updateRegistry(_:)`; rewire the root to inject the same store into both `DockStore` and `HostSettingsStore`. Removing the last host routes to the existing empty/bootstrap path (no `hosts[0]` crash).
- **Consequences:** live propagation with no new machinery; Phase 1/2 own the wiring; `DockStoreTests` covers `updateRegistry` on list change and the empty-list route.

## 2026-05-28 - Plan-audit PLA-001: drop the multi-host app-config merge (overbuild)

- **Context:** `plan-audit` (serving-side overbuild lens) found the proposed Phase 4 `app-config` multi-host merge redundant: device multi-host is the in-app durable registry (P1/P2), and the simulator already gets multi-host env via `make app` SIMCTL injection + `codex-dock-host-service-env.mjs`'s multi-host `service.env` writer, which `HostRegistry.fromEnvironment` already parses.
- **Options:** keep the merge for a "convenience listing"; or drop it and rely on per-machine URL emission + in-app add (device) / existing env injection (simulator).
- **Decision:** drop the merge. Handoff = each machine prints its own one-host URL; the user adds each in-app.
- **Consequences:** removed from Section 0.2, 3, 5.2/5.3, 6, Phase 4, and verification; one fewer concept and test surface; no contradiction with the per-machine one-command design.

## 2026-05-28 - Plan-audit PLA-002: one writer for the host env-var naming contract (drift)

- **Context:** `plan-audit` (drift/SSOT lens) found 4 writers of `CODEX_DOCK_HOST_<SUFFIX>_*` (Makefile `env-file`, Makefile `app` SIMCTL, installer `appConfigEnv`, Swift reader) with two divergent suffix rules (`hostIDToEnvSuffix` regex vs Swift `envKeyComponent` scalar — differ on repeated non-alphanumerics like `my--host`). The plan's Makefile parametrization forces removing the hardcoded `AMIR_M5`/`HOME` literals, so convergence is now required.
- **Options:** Makefile consumes installer `app-config --format env` (one writer); or keep two computed rules synced by a cross-language test; or leave-different (rejected — no justification, and parametrization breaks the hardcoding).
- **Decision:** make the installer `app-config --format env` the single writer the Makefile consumes; delete the hardcoded literals; add a Node↔Swift suffix-agreement test + sync comments at both suffix functions.
- **Consequences:** added to Section 5.2/5.3, 6, Phase 3 checklist/verification/exit; prevents silent off-LAN host-config drift.

## 2026-05-28 - Plan-audit PLA-003: move the saveHost list-write into Phase 1 (depth-first proof)

- **Context:** `plan-audit` (depth-first/proof lens) found Phase 1's "form-added host survives cold start" exit criterion unachievable in Phase 1, because `HostSettingsStore.saveHost`'s list-write was assigned to Phase 2; and on the simulator, injected env masks the form path, so the manual proof would be misleading.
- **Options:** move the minimal `saveHost`→store write into Phase 1 (Option A); or keep Phase 1 as-is and defer the durability proof to Phase 2 (Option B).
- **Decision:** Option A — Phase 1 rewrites `saveHost` to persist the full list through the shared store (default `authMode: none`); the bearer/auth-mode UI, Remove control, and discovery-as-add stay in Phase 2. Form-add durability is proven by unit/integration tests, not the env-masked simulator run.
- **Consequences:** Phase 1 is genuinely a working end-to-end slice; Phase 1 checklist/verification/exit updated; Phase 2 scope narrowed to UI + removeHost + discovery-as-add + live propagation.
