# Codex Dock Host+Port Config Implementation Log

Date: 2026-05-28

## Summary

Implemented endpoint-only app-facing relay config from
`docs/CODEX_DOCK_HOST_PORT_CONFIG_TAILSCALE_OPS_SEPARATION_2026-05-28.md`.

The app now stores and displays relay endpoints as `host:port`, computes
`ws://<host>:<port>` only at the transport boundary, persists endpoint lists,
and no longer carries phone-side bearer/auth-mode/url config in
`DockHostConfiguration`.

Generated app config now emits only:

```text
CODEX_DOCK_HOSTS=<host>:<port>[,<host>:<port>]
```

Tailscale is documented as an operator reachability path, not as a Swift or
host-service app-config profile.

## Implementation Notes

- Replaced URL/auth host config with `DockRelayEndpoint` and endpoint-only
  `DockHostConfiguration`.
- Replaced scoped `_WS`, `_AUTH_MODE`, `_NAME`, and token app env parsing with
  comma-separated `CODEX_DOCK_HOSTS`.
- Replaced single saved relay URL config with `LocalRelayEndpointList`.
- Added legacy `ws://host:port` saved-config migration and rejection for
  unsupported legacy URL shapes.
- Updated bootstrap, Bonjour discovery, host settings, Dock, Archive,
  Thread Detail, Realtime transcription, connectivity, and previews to use
  endpoint-derived display and endpoint-derived transport URLs.
- Fixed bootstrap convergence so environment, saved, and discovered endpoints
  merge into one registry instead of replacing each other.
- Replaced Hosts and bootstrap manual URL entry with separate `Host` and
  `Port` fields.
- Updated host-service app-config and Makefile app env generation to emit
  endpoint-only phone config.
- Removed host-service `tailscale` network-profile support and
  `--tailscale-address`.
- Removed phone-readable Bonjour `auth=` and `scheme=ws` TXT records.
- Added supersession notes to active docs that still contain historical
  URL/auth/Tailscale-profile wording.

## Verification

Passed:

```sh
rtk swift test --filter DockConfigurationTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter AppConnectivityStoreTests
rtk swift test --filter AppServerClientTests
rtk swift test
rtk npm run test:host-service
rtk npm run test:relay
rtk npm test
rtk make app-server-status
rtk make dock-relay-status
rtk make app-server-env
rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B
```

`rtk swift test` result: 200 tests, 5 expected skips, 0 failures.

`rtk npm test` result: 51 relay tests and 21 host-service tests passed.

`rtk make app-server-env` emitted endpoint-only app config plus test-only
transport smoke helpers:

```text
CODEX_DOCK_HOSTS=192.168.50.117:4510
export CODEX_DOCK_LOOPBACK_APP_SERVER_WS=ws://127.0.0.1:4500
export CODEX_DOCK_TEST_APP_SERVER_WS=ws://192.168.50.117:4510
export CODEX_DOCK_TEST_APP_SERVER_BEARER_TOKEN_FILE=/Users/aelaguiz/workspace/codex-client/.codex-dock/app-server.token
```

The generated phone env at `.codex-dock/host.env` contains only:

```text
CODEX_DOCK_HOSTS=192.168.50.117:4510
```

`rtk make app SIM='iPhone 17'` was first attempted and failed because the
simulator name matched multiple devices:

```text
Simulator 'iPhone 17' matched multiple devices
```

The rerun with the booted simulator ID
`BAD95C8E-3E57-4818-9B90-E4ED22593B4B` passed.

## Notes

- `.env` was not edited.
- `project.yml` was not changed.
- Historical docs and worklogs still contain old URL/auth/profile terms as
  passive history. Active docs now have supersession notes where those terms
  conflict with the endpoint-only contract.
