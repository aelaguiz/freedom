# Plan Audit - Single Endpoint Per Host

Date: 2026-05-29

Plan audited: `docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md`

Verdict: implementation approved.

This file contains the initial readiness audit plus the post-implementation plan-audit check.

## Summary

The plan is decision-complete and matches the user's requested direction: delete the multi-endpoint host model, do not archive or preserve it, and replace it with one endpoint per host.

The plan's ArcStep stage gate reports `READY next=implement-loop`, and the plan has enough concrete code ownership, deletion scope, phase boundaries, and verification commands for an implementer to proceed.

## Evidence Read

- Plan structure and stage receipts in `docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md`.
- Repo source anchors named by the plan:
  - `CodexDock/Configuration/DockHostConfiguration.swift`
  - `CodexDock/Configuration/HostRegistry.swift`
  - `CodexDock/Configuration/RelayDiscovery.swift`
  - `CodexDock/Configuration/RelayBootstrapStore.swift`
  - `CodexDock/AppServer/AppServerHostConnector.swift`
  - `CodexDock/State/HostSettingsStore.swift`
  - `CodexDock/State/AppServerDockClient.swift`
  - `CodexDock/State/AppServerThreadDetailSession.swift`
  - `CodexDock/Voice/RelayRealtimeTranscriptionClient.swift`
  - `scripts/device-relay-config.mjs`
  - `scripts/codex-dock-host-service-env.mjs`
  - `scripts/codex-dock-host-service.mjs`
- Representative Swift and Node tests named by the plan.
- Live instruction surfaces named by the plan: `README.md`, `Makefile`, and `AGENTS.md`.

Sub-agents were not used. The available multi-agent tool requires an explicit user request for sub-agents or delegation; this request asked for ArcStep auto plan plus plan audit, so the cold-read audit was performed locally.

## Blocking Findings

None.

## Non-Blocking Findings

None.

## Readiness Checks

Task-to-plan alignment: pass.

The TL;DR states the target directly: one host entry per relay and one endpoint per host, with `Amir-M5` and `Home` no longer collapsed into one row. The plan also says the old abstraction is deleted rather than hidden.

Deletion fidelity: pass.

The plan names the exact old surfaces to remove: `DockHostConfiguration.endpoints`, `webSocketURLs`, `displayEndpointList`, `init(endpoints:relayInstanceID:)`, endpoint aliases, phone-side `relayInstanceID`, fallback loops, and old tests.

Codebase ownership: pass.

The internal ground-truth section names the right owners for the Swift model, saved config, discovery/bootstrap, runtime connector, host settings, Node config writers, Makefile defaults, docs, and tests. That is enough to keep the implementation from becoming a UI-only change.

Compatibility posture: pass.

The plan consistently chooses a clean cutover with `fallback_policy: forbidden`. It explicitly rejects a decoder bridge for old saved `endpoints` JSON, old alias behavior, and old same-host fallback.

Phase structure: pass.

Phase 1 cuts the Swift model and runtime connector together, which is the right first proof because partial preservation of `host.endpoints` would keep the invalid state alive. Phase 2 moves generated config and Makefile/device behavior to the same contract. Phase 3 deletes stale live instructions and runs final proof.

Verification: pass.

The verification list is proportional to the change:

- `rtk swift test --filter DockConfigurationTests`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter DockStoreTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk npm test`
- `rtk make sim-config-verify SIM='iPhone 17'`
- `rtk make app SIM='iPhone 17'` when launch/config behavior is touched
- physical-device verification only when devices, signing, and services are available

Docs and instruction drift: pass.

The plan includes `README.md`, Makefile help/output, and `AGENTS.md`. That matters because the current live repo instructions still describe phone-side `relayInstanceID` and endpoint-alias expectations, which would contradict the new contract if left unchanged.

Security and protocol boundaries: pass.

The plan preserves the existing boundary that phones receive only relay host config on `:4510`, not `OPENAI_API_KEY`, raw app-server bearer tokens, or raw `:4500` app-server endpoints. It keeps relay identity as observed metadata rather than phone-side grouping config.

Execution-risk note: not a plan blocker.

The current worktree is already dirty in files the implementation may need to edit, including `README.md`, Swift tests, and generated Xcode project files. The implementer must preserve unrelated user work and avoid reverting changes they did not make.

## Commands Run For Audit

- `rtk rg -n "^##|^###|fallback|relayInstanceID|endpoints|Implementation Phase|Verification|Consistency|Appendix" docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md`
- `rtk nl -ba docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md`
- `rtk python3 /Users/aelaguiz/.agents/skills/arch-step/scripts/arch_stage_gate.py ready --doc docs/CODEX_DOCK_SINGLE_ENDPOINT_PER_HOST_GOALS_2026-05-29.md`
- `rtk git status --short`

No build or test commands were run because the user asked for planning and audit only, with no implementation.

## Final Audit Result

Initial readiness result: proceed to implementation when instructed.

The plan does not need another planning pass before implementation. It should be implemented as a clean cutover, and any implementation work should treat the old endpoint-list host model as deleted, not deprecated.

---

# Implementation Audit - Single Endpoint Per Host

Date: 2026-05-29

Verdict: approve.

The implementation matches the approved plan. The old app-facing multi-endpoint host model has been deleted, generated config now writes host-list JSON, docs no longer instruct phone-side relay identity, and verification passes.

## Blocking Findings

None.

## Non-Blocking Findings

None.

## Strict Review Follow-Through

The strict code-quality review found two issues during review, both fixed before this audit was approved:

- `DockHostConfiguration.fromEnvironment` reported multiple distinct hosts as duplicate hosts. It now throws `multipleHostsForSingleConfiguration`.
- `LocalRelayHostList(hosts:)` silently deduplicated inputs. It now preserves inputs and lets validation fail duplicate saved hosts loudly.

## Scope Checks

Swift host model: pass.

`DockHostConfiguration` stores one `endpoint`, derives `id` from that endpoint, and no longer has `endpoints`, `webSocketURLs`, `displayEndpointList`, endpoint-array initializers, phone-side `relayInstanceID`, or relay identity validation.

Host registry: pass.

`HostRegistry.fromEnvironment` maps each `CODEX_DOCK_HOSTS` entry to a separate `DockHostConfiguration`, rejects duplicate endpoint IDs, and ignores old phone-side relay identity env.

Saved app config: pass.

`LocalRelayHostList` uses strict `hosts` JSON only. Old `endpoints` JSON, old `webSocketURL` JSON, mixed `relayInstanceID`, duplicate host entries, and raw `:4500` hosts fail without deleting the original file.

Runtime connection path: pass.

`AppServerHostConnector` connects to exactly `host.endpoint`. The retry-next-endpoint helper and same-host fallback loop are gone. Thread detail and relay realtime transcription tests assert no fallback.

Host settings: pass.

Add creates a separate host row; edit replaces the selected host row; duplicate detection is endpoint-ID based.

Generated Node/device config: pass.

`scripts/device-relay-config.mjs` writes and verifies `{ "hosts": [...] }`, rejects old endpoint-list JSON, rejects extra phone-side relay identity, and rejects secrets/raw `:4500` env. Host-service app config emits only `CODEX_DOCK_HOSTS`.

Makefile and docs: pass.

Makefile variables and output use host-list language. `README.md` and `AGENTS.md` no longer require phone-side `relayInstanceID` or endpoint aliases.

Remaining `endpoints` and `relayInstanceID` references: pass.

Remaining `endpoints` hits are relay-internal live/upstream status data, not app-facing host config. Remaining `relayInstanceID` hits are relay-side metadata, initialize DTO metadata, negative tests, or docs that explicitly forbid phone-side persistence.

## Verification Evidence

- `rtk swift test --filter DockConfigurationTests`: passed, 28 tests, 0 failures.
- `rtk swift test --filter AppServerClientTests`: passed, 48 tests, 5 intentional skips, 0 failures.
- `rtk swift test --filter DockStoreTests`: passed, 30 tests, 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests`: passed, 52 tests, 0 failures.
- `rtk npm test`: passed, 61 relay tests and 33 host-service/device-config tests.
- `rtk make sim-config-verify SIM='iPhone 17'`: blocked by ambiguous simulator name; exact blocker was `Simulator 'iPhone 17' matched multiple devices`.
- `rtk make sim-config-verify SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B`: passed.
- `rtk make device-config-verify-all`: initially failed because existing physical saved config was old shape, then passed after rewriting both physical configs with `rtk make device-config`.
- `rtk make device-config DEVICE=CB9FFF0E-89AD-57B5-9C00-6552D814875E`: passed.
- `rtk make device-config DEVICE=0A4EFF8B-54D8-58FB-B3FB-63263265B9CC`: passed.
- `rtk make device-config-verify-all`: final run passed for both physical devices.

Skipped: `rtk make device-install-all`.

Reason: the plan only requires physical install proof when explicitly in reach. This implementation verified physical saved config readback without reinstalling either physical app.

## Final Implementation Audit Result

Approved. No required implementation work remains in the approved scope.
