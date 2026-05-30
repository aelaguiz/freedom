# Codex Dock Relay Aggregator Implementation Worklog

Plan: `docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md`
Date: 2026-05-29
Scope: full relay aggregator implementation through simulator proof.

## Code Changes

- Added relay-owned Dock session stream support in
  `scripts/dock-relay-session-table.mjs`.
- Added relay `dock/subscribe` and `dock/resync` dispatch in
  `scripts/dock-relay.mjs`; `dock/update` is server-to-client notification
  only.
- Added relay session constants in `scripts/dock-relay-constants.mjs`.
- Split relay environment helpers into `scripts/dock-relay-env.mjs`.
- Added Swift stream DTOs in `CodexDock/AppServer/DockStreamDTO.swift`.
- Added Swift stream connection/client in
  `CodexDock/State/AppServerDockStreamClient.swift`.
- Added Swift per-host stream reducer in `CodexDock/State/DockSessionTable.swift`.
- Cut Dock Home over to stream-backed state in `CodexDock/State/DockStore.swift`.
- Added DEBUG simulator proof stream in
  `CodexDock/State/ScriptedDockStreamClient.swift`, selected by
  `CODEX_DOCK_UI_DOCK_STREAM_SCENARIO`.
- Added focused stream reducer tests in
  `CodexDockTests/DockStoreStreamTests.swift`.
- Removed/confined old visible not-loaded and scope-conflict UI affordances from
  Dock Home.
- Updated `README.md`, `Makefile`, and `scripts/sim.py` so normal simulator
  iteration background-boots and reuses an already running app unless
  `FORCE_LAUNCH=1`.
- Updated `scripts/sim.py` resolution so `SIM='iPhone 17'` prefers the single
  booted matching simulator when duplicate simulator names exist.
- Added client schema-version mismatch recovery in `DockSessionTable` and a
  DEBUG simulator `schemaMismatch` scenario.
- Hardened Swift stream schema acceptance so missing `schemaVersion` is treated
  as incompatible and forces resync instead of being accepted as current.
- Hardened relay last-good persistence so incompatible persisted
  `schemaVersion` data is ignored instead of being promoted to the current
  stream schema.

## Verification Commands

All commands below were run from `/Users/aelaguiz/workspace/codex-client`.

| Command | Result |
| --- | --- |
| `python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_RELAY_AGGREGATOR_ARCHITECTURE_2026-05-29.md` | passed, `READY next=implement-loop` |
| `node --check scripts/dock-relay-session-table.mjs && node --check scripts/dock-relay.mjs && node --check scripts/dock-relay.test.mjs` | passed |
| `rtk npm run test:relay` | passed, 68 tests |
| `rtk swift test --filter DockStoreStreamTests` | passed, 7 tests |
| `rtk swift test --filter DockStoreTests` | passed, 34 tests |
| `rtk swift test --filter AppServerClientTests` | passed, 50 tests, 5 skipped |
| `rtk swift test --filter DockStoreScopeTests` | passed, 7 tests |
| `rtk swift test --filter AppConnectivityStoreTests` | passed, 13 tests |
| `rtk swift test --filter ThreadDetailStoreTests` | passed, 52 tests |
| `rtk swift test --filter ThreadDetailStoreLifecycleTests` | no matching test cases; lifecycle tests already ran under `ThreadDetailStoreTests` |
| `rtk make app-test SIM='iPhone 17'` | passed after resolver fix; log `.codex-dock/logs/app-test-20260529220829.log` |
| `APP_DERIVED_DATA=/tmp/codex-client/derived-data-relay-aggregator-20260529T2214Z rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` | passed from fresh DerivedData; Xcode result `Passed`, 238 passed, 5 skipped, 0 failed; log `.codex-dock/logs/app-test-20260529221426.log` |
| `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` | passed; log `.codex-dock/logs/app-test-20260529220546.log` |
| `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` | passed; installed simulator build `20260529220815` after the UI test runner had exited the app |
| `python3 scripts/sim.py app-running BAD95C8E-3E57-4818-9B90-E4ED22593B4B com.aelaguiz.CodexDockApp; printf 'exit=%s\n' $?` | passed, `exit=0` |
| `python3 scripts/sim.py resolve 'iPhone 17'` | passed, `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` |
| `python3 -m py_compile scripts/sim.py` | passed |
| `node --check scripts/dock-relay-session-table.mjs && node --check scripts/dock-relay.test.mjs` | passed after persisted-schema hardening |
| `rtk make sim-logs SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` | started through the canonical path; no fresh lines arrived before interrupt, so historical simulator logs were inspected with the same subsystem predicate |
| `rtk sh -c 'udid="$(python3 scripts/sim.py resolve "iPhone 17")"; xcrun simctl spawn "$udid" log show --last 5m --style compact --predicate '\''subsystem == "com.aelaguiz.CodexDock"'\'' ...'` | passed, confirmed scripted schema-mismatch resync in simulator logs |

## Simulator Evidence

Installed app evidence:

- Simulator: `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
- App bundle: `com.aelaguiz.CodexDockApp`
- Installed `CFBundleVersion`: `20260529215443`
- Installed `CFBundleShortVersionString`: `0.1.0`
- Running process check: `running com.aelaguiz.CodexDockApp ... exit=0`

Latest generated-project simulator UI evidence:

- `rtk make app-test SIM='iPhone 17'` passed after the simulator resolver fix.
- Test log: `.codex-dock/logs/app-test-20260529221426.log`
- Fresh Xcode result:
  `/tmp/codex-client/derived-data-relay-aggregator-20260529T2214Z/Logs/Test/Test-CodexDockApp-2026.05.29_17-14-26--0500.xcresult`
- Result summary: `Passed`, 238 passed, 5 skipped, 0 failed.
- `SIM='iPhone 17'` resolved to
  `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` because that was the single booted
  matching simulator.

Real relay path evidence from simulator logs:

- App loaded two configured hosts from environment.
- `dock stream subscribe started host_id=amir-m5.fairy-salmon.ts.net:4510`
- `dock stream subscribe finished host_id=amir-m5.fairy-salmon.ts.net:4510 seq=216`
- `dock stream subscribe started host_id=home.fairy-salmon.ts.net:4510`
- `dock stream subscribe finished host_id=home.fairy-salmon.ts.net:4510 seq=137`
- `dock stream reload finished hosts=2 rows=400 duration_ms=2780`

Scripted retention scenario evidence from simulator logs:

- `dock scripted stream enabled scenario=retention`
- `dock stream reload finished hosts=2 rows=4 duration_ms=204`
- stale heartbeat retained rows:
  `dock stream rows retained host_id=scripted-m5.local:4510 freshness=stale rows=2`
- stale heartbeat retained rows:
  `dock stream rows retained host_id=scripted-home.local:4510 freshness=stale rows=2`
- forced sequence gap:
  `dock stream sequence gap host_id=scripted-m5.local:4510 update_kind=delta seq=3`
- resync after gap:
  `dock stream resync finished host_id=scripted-m5.local:4510 seq=4 rows=3`
- forced sequence gap:
  `dock stream sequence gap host_id=scripted-home.local:4510 update_kind=delta seq=3`
- resync after gap:
  `dock stream resync finished host_id=scripted-home.local:4510 seq=4 rows=3`
- offline heartbeat retained rows:
  `dock stream rows retained host_id=scripted-m5.local:4510 freshness=offline rows=3`
- offline heartbeat retained rows:
  `dock stream rows retained host_id=scripted-home.local:4510 freshness=offline rows=3`
- stream-close offline retained rows:
  `dock stream rows retained host_id=scripted-m5.local:4510 freshness=offline rows=3`
- stream-close offline retained rows:
  `dock stream rows retained host_id=scripted-home.local:4510 freshness=offline rows=3`

Scripted schema-mismatch scenario evidence from simulator logs:

- `dock scripted stream enabled scenario=schemaMismatch`
- `dock stream subscribe started host_id=scripted-m5.local:4510 scripted_scenario=schemaMismatch`
- `dock stream subscribe finished host_id=scripted-m5.local:4510 seq=1 scripted_scenario=schemaMismatch`
- `dock stream subscribe started host_id=scripted-home.local:4510 scripted_scenario=schemaMismatch`
- `dock stream subscribe finished host_id=scripted-home.local:4510 seq=1 scripted_scenario=schemaMismatch`
- `dock stream reload finished hosts=2 rows=4 duration_ms=165`
- `dock stream resync needed host_id=scripted-m5.local:4510 reason=schemaMismatch update_kind=delta seq=2`
- `dock stream scripted resync finished host_id=scripted-m5.local:4510 seq=4 rows=3`
- `dock stream resync needed host_id=scripted-home.local:4510 reason=schemaMismatch update_kind=delta seq=2`
- `dock stream scripted resync finished host_id=scripted-home.local:4510 seq=4 rows=3`

## Physical Device

Skipped command:

```sh
rtk make iphone-17-pro
```

Blocker: the user explicitly instructed not to install on the iPhone 17 Pro.

## Focus-Stealing Fix

Permanent simulator behavior changed:

- `scripts/sim.py boot` background-boots only; it does not call
  `open -a Simulator`.
- `scripts/sim.py open` is the explicit command that opens the Simulator app.
- `rtk make sim SIM=...` intentionally opens Simulator.
- `rtk make app SIM=...` boots in the background and, if
  `com.aelaguiz.CodexDockApp` is already running, skips build/install/launch.
- `FORCE_LAUNCH=1 rtk make app SIM=...` is required when replacing the running
  simulator app is intentional.
- When duplicate simulator names exist, `scripts/sim.py resolve 'iPhone 17'`
  now chooses the single `Booted` or `Booting` match instead of forcing future
  sessions to discover and paste the UDID.

## Implementation Audit

Result: no open implementation findings from the parent audit after the
delegate-reported schema mismatch gap and strict-review schema/lifecycle gaps
were fixed.

Delegate review:

- Composer 2.5 Fast delegate run:
  `/tmp/agent-delegate/dock-relay-aggregator-review-20260529T215921Z-zCXnCH/final.txt`
- Delegate status was `partial`.
- Real implementation blocker: schema mismatch recovery was missing.
- Resolution: added schema mismatch rejection/resync, unit coverage, a two-host
  isolation test, and a simulator `schemaMismatch` scenario.
- Delegate's untracked-file note is not treated as a code blocker here because
  the user did not ask for staging or commit work.

Thermo-nuclear review:

- Finding: relay last-good persistence accepted any JSON with `hosts[]` and
  `sessions[]` without checking `schemaVersion`.
- Resolution: `readLastGood()` now rejects incompatible persisted schemas, and
  relay tests cover the stale-on-boot compatible path and incompatible-schema
  ignore path.
- Finding: `DockStore.openStream` could keep a connected stream cached after a
  subscribe snapshot was rejected and subscribe-time resync failed.
- Resolution: failed stream opens now clear the host stream task/connection and
  close the opened connection; `testFailedSubscribeResyncDropsConnectionSoRefreshCanReconnect`
  covers the reconnect path.
- Finding: Swift stream reducer accepted a missing `schemaVersion` as current,
  which was too loose for the new wire contract.
- Resolution: missing schema now returns `schemaMismatch` and triggers resync;
  `testMissingSchemaRequestsResync` covers the path.

The remaining requested reviews after this worklog update are:

- none
