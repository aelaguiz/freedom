# Codex Dock Host+Port Config Thermo-Nuclear Review

Date: 2026-05-28

## Verdict

Approved after one blocking structure issue was fixed.

The implementation now has one app-facing relay config model: endpoint-only
`host` + `port`. Swift persistence, bootstrap, host settings, generated app env,
Bonjour discovery, and Node host-service output all converge on that model. URL
construction remains computed and transport-facing; app config no longer stores
or receives bearer tokens, auth modes, network profiles, or Tailscale-specific
fields.

## Fixed Blocking Finding

### Bootstrap convergence was not atomic enough

Initial review found that environment, saved, and discovered endpoints could
replace each other instead of converging into one registry. That preserved a
split-source shape under a new endpoint model.

Fix:

- `RelayBootstrapStore` now keeps env-backed ready state while discovery runs.
- Saved endpoint lists upsert into the current registry without stopping
  discovery.
- Discovered endpoints upsert into the same registry and only then stop
  discovery.
- Persistence saves the merged endpoint list.

Proof:

- `DockConfigurationTests.testRelayBootstrapUsesSavedRelayAndKeepsDiscoveryAvailableForUpsert`
- `DockConfigurationTests.testRelayBootstrapMergesEnvironmentSavedAndDiscoveredEndpoints`
- `DockConfigurationTests.testEndpointParsingAcceptsLocalTailnetIPv4AndIPv6Hosts`
- `DockConfigurationTests.testEndpointParsingRejectsURLCredentialPathQueryFragmentWhitespaceAndBadPorts`
- `DockConfigurationTests.testFileLocalDockConfigurationStoreRejectsUnsupportedLegacyWebSocketURLsWithoutDeletingFile`
- `rtk swift test --filter DockConfigurationTests`

## Structural Review

No remaining structural blocker found.

- The new `DockRelayEndpoint` type earns its keep: it owns validation,
  normalization, identity, endpoint serialization, and computed WebSocket URL
  construction.
- `DockHostConfiguration` is now a thin selected-host wrapper around the
  endpoint, not a second URL/auth source of truth.
- `HostRegistry.fromEnvironment` only reads `CODEX_DOCK_HOSTS`.
- `LocalRelayEndpointList` is the single persisted shape for app relay config.
- `HostSettingsStore` saves the full endpoint list instead of one relay.
- `scripts/codex-dock-host-service-env.mjs` strips old app-facing URL/auth env
  before writing app-safe env.
- Bonjour TXT records expose only non-secret metadata.

## File-Size / Spaghetti Check

No changed file crosses the 1,000-line threshold.

`scripts/codex-dock-host-service.mjs` is close at 997 lines, but this change did
not add a new nested mode or Tailscale branch. The code-quality direction is
still toward deletion: the old Tailscale profile and app-facing URL/auth output
were removed instead of wrapped.

## Residual Risk

- Active historical plan bodies still contain old URL/auth/Tailscale-profile
  wording, but they now have supersession notes at the top. That is acceptable
  for this implementation; broader stale-doc retirement belongs to `$arch-docs`.
- Physical iPhone proof and remote `home` tailnet proof remain manual/ops
  follow-ups, not code-completeness blockers.

## Verification

Passed:

```sh
rtk npm test
rtk swift test --filter DockConfigurationTests
rtk swift test --filter DockStoreTests
rtk swift test --filter ThreadDetailStoreTests
rtk swift test --filter AppConnectivityStoreTests
rtk swift test --filter AppServerClientTests
rtk swift test
rtk make app-server-status
rtk make dock-relay-status
rtk make app-server-env
rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B
```

Known simulator-name blocker:

```text
Simulator 'iPhone 17' matched multiple devices; use one of these IDs:
```

The exact booted simulator ID passed:

```text
BAD95C8E-3E57-4818-9B90-E4ED22593B4B
```
