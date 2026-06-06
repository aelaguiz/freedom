# Codex Dock Client

This repo is the Swift client for the Codex Dock MVP.

## Canonical Product Intent

The canonical intended user journey is
`docs/CODEX_DOCK_CANONICAL_USER_JOURNEY.md`. Use it as the product-intent
source of truth when current code, dated plans, or older UX specs disagree about
what the app should do.

## App-Server Runbook

Codex owns app-server/session processes. Dock owns one phone-facing relay that
discovers those existing Codex endpoints and aggregates them.

The normal Codex daemon provides durable history on this Unix socket:

```text
~/.codex/app-server-control/app-server-control.sock
```

Running Codex clients can also create live app-server/session owners. The relay
discovers attachable Unix-socket and loopback WebSocket owners from the local
process table, records private stdio owners as diagnostics, and prefers the
attachable owner for thread-specific methods when it has a current lease.

Dock no longer starts a special raw `:4500` app-server. The iPhone never connects
directly to a Codex app-server. It connects to the Dock relay on `:4510`, and
the relay chooses the right Codex endpoint for each request.

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

## Testing And Proof

Current test commands, proof rules, and add-a-test guidance are documented in
`docs/TESTING.md`.

Historical bug, plan, audit, worklog, and UI-requirement coverage is tracked in
`docs/CODEX_DOCK_TEST_SCENARIO_COVERAGE.md`. When adding a root bug doc under
`docs/bugs/`, adding or removing a controlled simulator scenario, or finding a
new failure class in old docs, update that ledger and run:

```sh
rtk npm run test:docs
```

The future unified framework plan is
`docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`. It defines the
proposed `test-smoke`, `test-full`, and `test-overtime` Makefile targets, but
those targets are not current commands until `Makefile` contains them.

The older exhaustive sync runbook,
`docs/CODEX_DOCK_EXHAUSTIVE_SYNC_RUNBOOK_2026-05-31.md`, remains a narrower
historical reference for over-time sync proof.

## Canonical Service Start

Use this target for local Dock development instead of manually starting and
stopping host services:

```sh
rtk make services
```

It starts/reuses one real service and leaves it running:

- Dock relay on `ws://<APP_SERVER_HOST>:4510`

Codex daemon history and live session owners provide upstream data. The relay is
the app endpoint. Dock Home subscribes to relay-owned `dock/*` methods:
`dock/subscribe` returns the first normalized snapshot, `dock/update` pushes
deltas and heartbeats, and `dock/resync` returns a replacement snapshot if the
client detects a sequence gap. The relay materializes app-server thread
projections in SQLite at `.codex-dock/relay-state.sqlite`, serves Dock Home from
that state store, and keeps stale rows visible when a source refresh fails.

Card truth has one path. The relay may inspect Codex app-server facts such as
`thread/list`, `thread/read`, `thread/turns/list`, live events, and live loaded
IDs internally, but Swift never uses those raw routes to prove Dock or Archive
cards. Swift renders card truth only from `dock/*` and `archive/*` streams.

Row text has two separate meanings. Raw history `preview` is preserved as the
app-server's stored preview and may be the opening message. Dock overview rows
use relay-owned card fields from the canonical projection. That projection may
inspect newest turns and live events to compute honest activity, but any
unproven card makes the stream partial or stale instead of pretending the list
is fresh.

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
canonical Dock status, repository or working directory, source, and the fixed
`Newest activity` sort. Status `Any` includes `Idle`, so idle rows are visible
by default and can be narrowed through the status filter. Search is full-width and
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
Swift consumes relay-owned `thread/detail/subscribe`, `thread/detail/update`,
and `thread/detail/resync` projection rows. The relay may still use raw
`thread/read includeTurns:false`, paged `thread/turns/list`, and upstream
`thread/resume excludeTurns:true` internally, but those raw routes are not the
phone-facing Thread Detail display contract. Failed user sends are not silently
replayed. If the relay loses its upstream session, it either re-resumes upstream
or closes the phone WebSocket so Swift can mark the detail stale or reconnect.

When iOS backgrounds the app, root refresh and reconnect attempts pause instead
of spending retry budget. Open details keep visible events, request action
state, and draft text but are no longer labeled fresh. Active voice capture is
cancelled without auto-submitting. On foreground resume, Dock and Archive
refresh from root, open details rehydrate through `thread/detail/resync`, and
the indicator moves through `Backgrounded` / `Resuming` / `Reconnecting` as
appropriate.

The service targets install per-repo launchd files on macOS and systemd user
files on Linux, with runtime files under `.codex-dock/`:

```text
.codex-dock/services/com.aelaguiz.codex-dock.relay.plist
.codex-dock/services/codex-dock-relay.service
.codex-dock/service.env
.codex-dock/host.env
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

Process health, route health, and card freshness are separate. `/readyz` only
means the relay process can answer HTTP. `/statusz`, `/routesz`, `/metricsz`,
and `/syncz` expose process and route health only; they do not prove Dock or
Archive card ordering, contents, freshness, completeness, or membership.

Route-health diagnostics:

```sh
rtk make relay-doctor
rtk make relay-host-compare HOSTS=amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510
rtk make relay-debug-bundle
```

The relay stores bounded route evidence under `.codex-dock/observability/`.
Automatic probes only use auto-probe-safe routes; archive, turn, and
transcription routes are passive evidence from real app traffic. HTTP
diagnostics intentionally do not expose card rows or stored card state.

Print the app-safe relay host config:

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
installs, starts, and waits for the Dock relay service. Codex app-server
instances are discovered by the relay; they are not launched by the Dock service
wrapper.

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
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make services'
```

Check `home` after start:

```sh
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-status'
rtk ssh home 'cd /home/aelaguiz/workspace/codex-client && rtk make host-service-doctor'
```

From the Mac, the app-facing `home` relay should answer:

```sh
curl -fsS --max-time 5 http://100.66.11.7:4510/readyz
curl -fsS --max-time 5 http://100.66.11.7:4510/statusz
curl -fsS --max-time 5 http://100.66.11.7:4510/routesz
```

Use `readyz` only as process proof. Use `statusz` or `routesz` for route proof;
an app-critical route failure should make `relay-doctor` report a problem even
when `readyz` succeeds. `home` status should report relay identity `home` /
`Home`; if it reports `Amir-M5`, the host-service status check should fail.

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

That command starts/reuses the persistent relay service and boots the simulator in
the background. If `com.aelaguiz.CodexDockApp` is already running on that
simulator, it leaves the app alone and skips build/install/launch so Simulator
does not keep stealing focus.

Force a replacement build and launch only when you actually need it:

```sh
FORCE_LAUNCH=1 rtk make app SIM=DEF1631B-7125-43C6-BFA3-4423BF103C91
```

When it does launch, it uses generated app config from `.codex-dock/host.env`.
It does not pass an OpenAI key or Codex app-server credential into the app.

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

Today that means the no-client-auth Dock relay. If another local service becomes
required later, add it behind this target so `rtk make app SIM=...` keeps doing
the whole setup idempotently.

The service targets write host-side settings to `.codex-dock/service.env`,
write app-safe settings to `.codex-dock/host.env`, and leave the user-owned
`.env` untouched. They may read `OPENAI_API_KEY` from the shell or `.env`, but
they must not rewrite `.env`. Host identity is derived by the host-service
wrapper when `CODEX_DOCK_REAL_HOST_ID` and `CODEX_DOCK_REAL_HOST_NAME` are not
set, so `rtk make services` derives `Amir-M5` on the Mac and `home` / `Home` on
the Linux `home` host.

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

Dump the current visible simulator state without relaunching, navigating,
seeding, or taking screenshots:

```sh
rtk make sim-ui-dump SIM='iPhone 17'
```

This writes accessibility-state proof to `/tmp/codex-client/.../sim-ui-dump.json`
and `/tmp/codex-client/.../sim-ui-dump.md`. The JSON contains the visible
screen, visible Dock rows or Thread Detail messages when present, rollups, and
the raw accessibility element list. If the app is not running or the current
screen cannot be classified, the target writes a blocked/non-fresh report
instead of silently passing.

Run the controlled over-time simulator proof before claiming live update
behavior is fixed:

```sh
rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'
```

The matrix mutates controlled Codex data, watches relay truth, samples the
literal simulator accessibility state over time, and fails when the UI does not
converge within the configured lag budget. Dock row identity and order are read
from the test-only Dock automation snapshot file advertised by the Dock root
accessibility value as `automationSnapshotPath=...`, so missing structured Dock
state fails loud instead of being reconstructed from a visual scrape. The root
value stays bounded to scalar state such as row count, revision, and snapshot
metadata; it no longer carries a full row payload. Thread Detail message order
is checked from top-to-bottom accessibility frames in the scenarios where
ordering matters. The proof reports are schema-checked by `rtk npm run
contract:check`.

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
