# Worklog - Single Endpoint Per Host

Date: 2026-05-29

Plan: `docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md`

## Implementation Summary

- Replaced the Swift app-facing host model with one `DockRelayEndpoint` per `DockHostConfiguration`.
- Changed `HostRegistry.fromEnvironment` so comma-separated `CODEX_DOCK_HOSTS` entries become separate host rows.
- Replaced saved app config with strict `{ "hosts": [{ "host": "...", "port": 4510 }] }` JSON.
- Made old `endpoints` JSON, mixed phone-side `relayInstanceID`, duplicate saved hosts, raw `:4500` hosts, and unsafe host strings fail loudly.
- Removed same-host endpoint fallback from `AppServerHostConnector`, thread detail session creation, and relay realtime transcription startup.
- Changed Host settings so add creates a separate host and edit replaces the selected host.
- Updated Node device config, host-service app config, Makefile variables/output, `README.md`, and `AGENTS.md` to use host-list language and stop writing phone-side relay identity.

## Verification

- `rtk swift test --filter DockConfigurationTests`
  - Passed: 28 tests, 0 failures.
- `rtk swift test --filter AppServerClientTests`
  - Passed: 48 tests, 5 intentional skips, 0 failures.
- `rtk swift test --filter DockStoreTests`
  - Passed: 30 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`
  - Passed: 52 tests, 0 failures.
- `rtk npm test`
  - Passed: 61 relay tests and 33 host-service/device-config tests.
- `rtk make sim-config-verify SIM='iPhone 17'`
  - Initial run blocked by ambiguous simulator name:
    `Simulator 'iPhone 17' matched multiple devices; use one of these IDs:`
    `BAD95C8E-3E57-4818-9B90-E4ED22593B4B` and
    `DEF1631B-7125-43C6-BFA3-4423BF103C91`.
- `rtk make sim-config-verify SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Passed.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`
  - Passed; simulator build/install/launch completed.
- `rtk make device-config-verify-all`
  - Initial run reached physical device config but failed because saved config was still old shape:
    `expected {"hosts":[{"host":"amir-m5.fairy-salmon.ts.net","port":4510},{"host":"home.fairy-salmon.ts.net","port":4510}]} got {"hosts":null}`.
- `rtk make device-config DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`
  - Passed; wrote and verified `amir-m5.fairy-salmon.ts.net:4510,home.fairy-salmon.ts.net:4510`.
- `rtk make device-config DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`
  - Passed; wrote and verified `Amir-M5.local:4510,192.168.50.74:4510`.
- `rtk make device-config-verify-all`
  - Passed after rewriting both device configs with host-list JSON.

## Notes

- `rtk make device-install-all` was not run. The plan only requires physical install proof when explicitly in reach; this run verified saved physical configs without reinstalling either app.
- The relay-side `relayInstanceID` fields remain in relay status/metadata paths. Phone-side saved config, launch env, and device config no longer carry relay identity.

## Reviews

- Thermo-nuclear code-quality review: passed after fixing the misleading single-host error and duplicate saved-host compaction.
- Plan-audit implementation check: approved in `docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29_PLAN_AUDIT.md`.
