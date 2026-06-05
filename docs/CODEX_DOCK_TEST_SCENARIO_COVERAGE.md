# Codex Dock Test Scenario Coverage

Date: 2026-06-05
Status: current coverage ledger
Primary guide: `docs/TESTING.md`
Framework plan: `docs/CODEX_DOCK_UNIFIED_TESTING_FRAMEWORK_2026-06-05.md`

## Direct Answer

This file maps historical bug docs, plans, audits, worklogs, and UI
requirements to the tests or future scenarios that must catch the same bug
class next time.

Use `docs/TESTING.md` for commands. Use this file when adding a bug doc,
controlled simulator scenario, proof rule, or regression case. The fast guard
is `rtk npm run test:docs`, and it is included in `rtk npm test`.

## Reviewed Source Summary

This ledger was created from the repo Markdown review corpus on 2026-06-05:

- 280 Markdown docs included from `README.md`, `AGENTS.md`, `docs/**`, and
  `research/**`.
- 10 docs under `docs/bugs/**`.
- 61 plan-audit or thermonuclear-review docs.
- 56 worklogs or implementation logs.
- 74 plan, reference, requirement, goal, or spec docs.
- 60 mockup or UI requirement docs.
- 8 epic phase docs.
- 4 research docs.
- 4 current routing/testing docs.

The durable signal from those docs is not every dated implementation detail.
The durable signal is the failure class: wrong runtime owner, stale data,
identity drift, proof side doors, large payloads, over-time UI lag, private
runtime capability mismatch, physical stale build state, false health
degradation, pinned interaction instability, and fixture/matrix drift.

## How To Add Coverage

When adding a root bug doc under `docs/bugs/`:

- Add the bug doc path to the `coverage:bug-docs` block below.
- Add or update a failure-class row in this file.
- Name the smallest current command and the future over-time scenario, if the
  current framework cannot catch it yet.
- Run `rtk npm run test:docs`.
- Run the behavior-specific command from `docs/TESTING.md`.

When adding a controlled simulator scenario:

- Add the scenario id to the `coverage:controlled-scenarios` block below.
- Add a scenario row that names the user-visible risk and proof command.
- If the scenario is fixture-supported but not default-matrix-gated, mark it
  `fixture-only-gap`.
- Run `rtk npm run test:docs`.
- Run the focused proof, then the matrix proof when the scenario should be part
  of completion proof.

Status terms:

- `current`: a current command or default matrix scenario covers it.
- `planned`: the unified framework plan covers it, but the target or scenario
  is not implemented yet.
- `gap`: the reviewed docs show the failure class, but current coverage is not
  enough.
- `fixture-only-gap`: fixture code supports it, but the default matrix does not
  require it.
- `physical-only`: simulator/local proof can narrow the issue, but a physical
  claim still needs installed-phone evidence.
- `diagnostic-only`: useful for investigation, not completion proof.

## Controlled Scenario IDs

The block below is checked by
`scripts/codex-dock-test-scenario-coverage.test.mjs`. It must include every
scenario currently supported by
`scripts/dock-relay-controlled-simulator-fixture.mjs`.

<!-- coverage:controlled-scenarios:start -->
- `archive-toggle`
- `current-work-visible`
- `detail-reconnect`
- `detail-history-request`
- `detail-replay-pressure`
- `file-change-review`
- `foreground-resume-all-surfaces`
- `large-list-checkpoint`
- `live-lease-expiry`
- `multi-host-isolation`
- `mutation-ack-projection-refresh-failure`
- `rapid-mutations`
- `resync-gap`
- `root-catchup-window-contract`
- `server-request`
- `server-rename-notification`
- `server-status-notification`
- `source-refresh`
- `spawned-private-child-status-rollup`
- `spawn-edge`
- `thread-activity`
<!-- coverage:controlled-scenarios:end -->

## Bug Docs Covered

The block below is checked by
`scripts/codex-dock-test-scenario-coverage.test.mjs`. It tracks root bug docs,
not implementation logs, plan audits, or architecture-plan companions.

<!-- coverage:bug-docs:start -->
- `docs/bugs/codex-working-badge-phone-missing-2026-06-05.md`
- `docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md`
- `docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md`
- `docs/bugs/private-codex-runtime-thread-detail-unavailable-2026-06-05.md`
- `docs/bugs/thread-detail-large-live-thread-message-too-long-2026-05-28.md`
- `docs/bugs/thread-detail-logical-host-id-mismatch-2026-05-30.md`
<!-- coverage:bug-docs:end -->

## Scenario Coverage Ledger

| Scenario ID | Current status | Primary risk covered | Current proof command |
| --- | --- | --- | --- |
| `archive-toggle` | current default matrix | Archive/unarchive transitions must update Dock and Archive through relay-owned routes. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `current-work-visible` | current default matrix | Current work must appear as current work, not old stored history. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `detail-reconnect` | current default matrix | Thread Detail must recover through `thread/detail/resync` after reconnect. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `detail-history-request` | current default matrix | Historical detail rows, live updates, and request cards must remain visible and ordered. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `detail-replay-pressure` | current default matrix | Thread Detail replay pressure must not drop messages or request state. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `file-change-review` | fixture-only-gap | File-change review visibility and approval flow are fixture-supported but not default-matrix-gated. | Focused fixture only today; future `test-overtime` must gate it or the fixture support should be deleted. |
| `foreground-resume-all-surfaces` | current default matrix | Foreground resume must refresh Dock, Archive, and Thread Detail before claiming live truth. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `large-list-checkpoint` | current default matrix | Large visible lists must expose structured row/order proof instead of relying on screenshots or one-shot dumps. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `live-lease-expiry` | current default matrix | Expired live leases must not keep stale running state alive. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `multi-host-isolation` | current default matrix | One host must not leak rows, route state, filters, or identity into another host. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `mutation-ack-projection-refresh-failure` | current default matrix | Local mutation acknowledgement must not pretend projection refresh succeeded when it failed. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `rapid-mutations` | current default matrix | Bursty updates must preserve route evidence, row identity, and lag budget. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `resync-gap` | current default matrix | Sequence gaps must fail closed and recover through `dock/resync`. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `root-catchup-window-contract` | current default matrix | Bounded root snapshots must catch up through explicit page/update proof. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `server-request` | current default matrix | Server request cards and resolved request state must appear in the real detail route family. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `server-rename-notification` | current default matrix | Server-side rename updates must reach visible Dock rows. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `server-status-notification` | current default matrix | Server-side status changes must reach visible Dock rows. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `source-refresh` | current default matrix | Source refresh failure and recovery must not silently show stale rows as fresh. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `spawned-private-child-status-rollup` | current default matrix | Hidden private spawned child work must make the visible parent row show `running` without leaking the child row. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `spawn-edge` | current default matrix | Parent-child and spawn-edge source behavior must not reorder or misclassify rows. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |
| `thread-activity` | current default matrix | Thread activity must update visible row order and activity state over time. | `rtk make sim-ui-controlled-matrix-proof SIM='iPhone 17'` |

## Failure-Class Regression Ledger

| ID | Source docs | Failure class | Current coverage | Required future coverage |
| --- | --- | --- | --- | --- |
| COV-001 | `docs/bugs/dock-live-status-filters-use-wrong-app-server-2026-05-28.md`, `docs/CODEX_DOCK_APP_SERVER_REGISTRY_HARD_CUT_2026-06-05_WORKLOG.md` | Raw `:4500`, wrong app-server owner, or private/loopback owner can make Dock look stale or empty while real work exists. | `rtk npm run test:host-service`, `rtk npm run test:relay`, proof contract raw `:4500` rejection, `current-work-visible`, `thread-activity`, `source-refresh`. | `test-overtime` must run the same owner/route checks against the large/stale/changing corpus. |
| COV-002 | `docs/bugs/thread-detail-large-live-thread-message-too-long-2026-05-28.md`, Phase 8 worklogs | Opening a large live thread can fail if detail uses full-turn `thread/read` or `thread/resume` responses. | `rtk swift test --filter AppServerClientTests`, `rtk swift test --filter ThreadDetailStoreTests`, `detail-history-request`, `detail-replay-pressure`. | Add an explicit large-detail compact-payload case to the scenario catalog or large profile so oversized single-message regressions cannot pass. |
| COV-003 | `docs/bugs/thread-detail-logical-host-id-mismatch-2026-05-30.md`, `docs/CODEX_DOCK_IDENTITY_DRIFT_ELIMINATION_PLAN_2026-06-02.md` | Logical host identity can drift from saved endpoint identity and break detail, filters, archive, cleanup, and pinned metadata. | Swift resolver, Dock, Archive, and contract tests; `multi-host-isolation`; `rtk npm run contract:check`. | `test-overtime` large profile must include same-logical-host multi-endpoint rows and live `home`/`Home` casing. |
| COV-004 | `docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md`, companion architecture plan | Pinned `Unpin` can disappear during live updates, and a row-window message like `Showing 250 of 964` can become false broad health degradation. | Proof-schema drift is now covered by `rtk npm run contract:check`; the behavior itself is a gap. | Add `pinned-action-survives-update` and `system-health-window-not-degraded` to the scenario catalog or Swift/UI tests before claiming this bug class is covered. |
| COV-005 | `docs/bugs/codex-working-badge-phone-missing-2026-06-05.md` | Physical phone can show stale runtime/build state while simulator and relay are correct. | `rtk make device-install`, `rtk make device-config-verify`, and build-number verification in Makefile device targets. | Physical claims must record installed build number, saved host list, relay row status counts, and either phone UI proof or the exact physical blocker. |
| COV-006 | `docs/bugs/private-codex-runtime-thread-detail-unavailable-2026-06-05.md` | Private `stdio://` runtime evidence can make a row look live even though detail cannot attach to that runtime. | Registry and relay tests cover private transport classification; current docs now name the bug class. | Add `private-runtime-capability` coverage so list badges, row status, and detail availability agree before `test-overtime` passes. |
| COV-007 | `docs/CODEX_DOCK_STALENESS_ARCHITECTURE_ROOT_CAUSE_REPORT_2026-05-31.md`, `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md` | Relay route health can be green while Dock rows are retained stale or semantically old. | `source-refresh`, `live-lease-expiry`, stale proof rules, and route evidence requirements. | Large/stale/changing corpus must include stale fractions, true refresh recovery, max source age, and row-level freshness proof. |
| COV-008 | `docs/CODEX_DOCK_EXHAUSTIVE_SYNC_TEST_PLAN_2026-05-31.md`, `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md` | Oracle routes, status endpoints, one-shot dumps, screenshots, mocks, or scripted streams can falsely look like app proof. | `contract/proof/**`, `scripts/proof-report-contracts.mjs`, `docs/TESTING.md` proof rules, AGENTS proof rules. | Keep any new proof route in `contract/proof/proof-route-name.schema.json` and fail closed unless it is a real app route family. |
| COV-009 | `docs/bugs/pinned-unpin-menu-and-degraded-health-2026-06-02.md` | UI dump producer/schema drift or hung UI dump can hide exactly the UI state under investigation. | `rtk npm run contract:check` validates proof schemas and canonical samples. | `test-overtime` must treat missing structured snapshots, missing automation metadata, and hung/skipped UI dump paths as blocked or failed, never green. |
| COV-010 | `docs/USER_MESSAGE_ARCHITECTURE_REVIEW_2026-06-04.md`, duplicate outbound root-cause docs | User sends can block the UI, duplicate optimistic/live rows, or acknowledge before projection catches up. | `rtk make sim-ui-user-message-latency-proof SIM='iPhone 17'`, `rtk npm run test:relay`, `ThreadDetailStoreTests`. | Fold equivalent optimistic UI and upstream-ack assertions into the scenario catalog before deleting the bespoke proof. |
| COV-011 | `docs/THREAD_RENAME_LATENCY_FIX_2026-06-04.md`, `docs/THREAD_RENAME_SERVER_SYNC_2026-06-04.md` | Client and server rename paths can lag, drift, or update only a side route. | `rtk make sim-ui-client-rename-proof SIM='iPhone 17'`, `server-rename-notification`, relay rename tests. | Fold equivalent latency and server-ack assertions into the scenario catalog before deleting the bespoke proof. |
| COV-012 | `docs/CODEX_DOCK_FILE_CHANGE_DIFF_PLAN_2026-06-03.md`, fixture code | File-change review can exist in fixture code but not be part of completion proof. | `file-change-review` is fixture-supported and contract-sampled, but not default-matrix-gated. | Include `file-change-review` in the default matrix with requirements or delete fixture support. |
| COV-013 | Connectivity, foreground, live-window, and protocol docs | Foreground/background resume can claim live before Dock, Archive, and Thread Detail catch up. | `foreground-resume-all-surfaces`, `detail-reconnect`, `resync-gap`. | Large profile must repeat foreground resume while rows are stale and changing. |
| COV-014 | Mockup requirements and UX docs | UI requirements for filters, not-loaded rows, offline/partial states, archive, pinned rows, and order can drift from proof. | Some cases are covered by `large-list-checkpoint`, `multi-host-isolation`, `archive-toggle`, and Swift tests. | Future coverage ledger rows should link each durable mockup requirement to a scenario, unit test, or explicit non-goal. |
| COV-015 | Realtime transcription and voice docs | Voice and transcription routes are relay-side, secret-sensitive, and not Dock-card proof. | `rtk npm run test:relay` includes realtime transcription tests; docs forbid secrets in app and logs. | `test-overtime` should not mix voice proof with Dock-card proof unless a scenario explicitly covers composer/user-message behavior. |

## Current Gaps After The Docs Review

- `file-change-review` is supported by the controlled fixture but is not in the
  default matrix.
- Pinned-row action survival during live updates is not a current default
  matrix scenario.
- System Health route-evidence behavior is not a current default matrix
  scenario.
- Private runtime attachability/status mismatch is not a current default matrix
  scenario.
- The large live Thread Detail payload bug is covered by compact-detail unit
  and detail-pressure proof, but the future large profile should carry an
  explicit oversized-payload regression.
- Physical stale-build/runtime mismatches can only be fully closed by physical
  install/config/build-number proof or by recording the exact blocker.

Net: the current framework has strong pieces, and the unified framework plan
must now treat this ledger as the coverage checklist for `test-overtime`.
