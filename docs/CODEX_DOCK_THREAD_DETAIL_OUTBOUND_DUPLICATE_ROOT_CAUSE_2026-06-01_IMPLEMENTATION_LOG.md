# Codex Dock Thread Detail Event Ledger Implementation Log

Date: 2026-06-01

Status: local single-host implementation proof complete; default two-host
deployment remains pending until `home` serves the same relay contract.
Last updated: 2026-06-02T03:54:01Z

Plan:

- `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`
- `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01_PLAN_AUDIT.md`
- `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md`

## Implementation Contract

Thread Detail display state must come from one relay-owned event ledger.

The app may still send focused commands and JSON-RPC responses through the
active relay session, but it must not build visible Thread Detail rows from raw
`thread/read`, `thread/turns/list`, `thread/resume`, upstream notifications, or
upstream server requests.

## Work Log

### 2026-06-01

- Started from a clean production-code state. Only plan/protocol docs were
  modified before implementation began.
- Read the relay session path in `scripts/dock-relay.mjs`.
- Read relay history/session helpers in `scripts/dock-relay-thread-data.mjs`.
- Read Swift Thread Detail session/store/data-engine/render paths.
- Read existing request-card identity and response handling.
- Added a relay-owned Thread Detail projection ledger in
  `scripts/dock-relay-thread-detail-ledger.mjs`.
- Added phone-facing Thread Detail projection routes:
  `thread/detail/read`, `thread/detail/subscribe`, `thread/detail/resync`, and
  passive `thread/detail/update`.
- Cut `ThreadDetailStore` over from raw `thread/read` +
  `thread/turns/list` + `thread/resume` display loading to relay projection
  snapshots and updates.
- Removed the production `serverRequests` display side stream from
  `ThreadDetailStore`; request rows now arrive as projection updates.
- Changed Thread Detail rows to the accepted envelope plus nested `payload`
  shape. The Swift DTO keeps read-only convenience accessors, but the wire row
  shape is no longer flattened.
- Added client-side projection envelope validation in
  `ThreadDetailDataEngine`: schema version, identity version, source host,
  view, view params key, order, row identity, duplicate projection IDs, and
  delete projection IDs are checked before rows are rendered.
- Made request-card accessibility and UI identity follow the relay
  `projectionID`; `requestID` remains response routing only.
- Removed `expectedMessageEventIDs` from simulator proof code and fixture
  reports. Proof now accepts `expectedMessageProjectionIDs` only.
- Added a relay `sourceHostID` resolver: explicit `CODEX_DOCK_REAL_HOST_ID` or
  config `hostId` wins; otherwise the relay reads or writes
  `.codex-dock/source-host-id`. Endpoint-shaped IDs such as
  `127.0.0.1:4510` are rejected.
- Updated `README.md` so Thread Detail display truth is documented as
  `thread/detail/*` projection rows, with raw `thread/read`,
  `thread/turns/list`, and upstream `thread/resume` described as relay-internal
  adapters only.
- Added `scripts/dock-relay-projection-engine.mjs` as the single owner for
  shared projection versions, safe segments, Thread Detail source refs,
  `projectionID`s, default `viewParamsKey`, and `displayOrderKey`.
- Cut `scripts/dock-relay-thread-detail-ledger.mjs` over to import identity,
  order, and version primitives from `scripts/dock-relay-projection-engine.mjs`
  instead of defining local copies.
- Cut the controlled simulator fixture over to import Thread Detail projection
  identity from `scripts/dock-relay-projection-engine.mjs`, not the ledger.
- Added `scripts/dock-relay-projection-engine.test.mjs` and wired it into
  `npm run test:relay`.
- Made Thread Detail snapshot/update `projectionEngineVersion` required in
  `CodexDock/AppServer/ThreadDetailDTO.swift`.
- Made `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` reject
  unsupported projection engine versions before rendering.
- Added focused Swift tests proving snapshot and update engine-version drift is
  rejected.
- Added a relay projection witness recorder in `scripts/dock-relay.mjs`.
  `projection/witness/read` returns retained projection envelopes only when
  `projectionWitnessEnabled` is explicitly set; it fails closed otherwise.
- Changed controlled simulator request approval flow so the UI sampler can tap
  the first visible request card without precomputed projection identity.
- Changed controlled simulator detail proof truth to come from
  `projectionWitness.projectionIDs` read from the relay, not from fixture-side
  `projectionIDFor*` calls.
- Tightened `scripts/dock-relay-simulator-ui-sync-proof.mjs` so legacy
  `expectedMessageProjectionIDs` without `projectionWitness` is reported as a
  proof failure.
- Removed production `ThreadEventNormalizer` from
  `CodexDock/Models/ThreadEvent.swift`. The old raw-fixture normalizer now
  lives only in `CodexDockTests/LegacyThreadEventFixtureNormalizer.swift`.
- Extended Dock/Archive card streams to carry the shared projection envelope:
  `schemaVersion`, `identityVersion`, `projectionEngineVersion`,
  `sourceHostID`, `view`, `projectionID`, `sourceRef`, `rowRole`, and
  `displayOrderKey`.
- Bumped the Dock/Archive stream schema to v3 and centralized the relay-side
  stream version in `RELAY_STATE_STREAM_SCHEMA_VERSION`.
- Made relay cached card normalization synthesize the projection envelope for
  old SQLite rows before they can leave the relay.
- Made Swift `ThreadCardTable` reject malformed v3 Dock/Archive card rows
  before applying snapshots or updates.
- Made Dock/Archive upsert and delete identity use `projectionID` only; removed
  Swift and relay fallbacks to legacy card `id`.
- Added `projectionID` to `DockRowViewModel` and Dock row accessibility values
  as `projection=...` so simulator/UI dump proof compares relay-emitted row
  identity directly.
- Updated simulator sync proof, controlled simulator multi-host checks, sync
  audit, and live-filter diagnostics to stop treating `host::thread` as
  production display identity.
- Fixed Swift test fixtures so `sourceHostID` remains the configured relay
  source identity while `logicalHostID` stays display payload.
- Added the shared projection contract package under `contract/projection/**`.
  `contract/dock/dock-thread-card.schema.json` is now only a compatibility
  `$ref` to the projection stream schema.
- Replaced the old contract checker with `scripts/check-projection-contract.mjs`
  in `package.json`. The checker validates projection fixtures, generated Dock
  Swift DTOs, the Dock compatibility pointer, and required Swift Thread Detail
  DTO fields from the projection schemas.
- Added row-level `projectionEngineVersion` to `ThreadDetailEventDTO` and made
  `ThreadDetailDataEngine` reject row-level projection engine version drift.
- Added the shared projection contract package under `contract/projection/**`:
  shared row envelope, row roles, view params, Dock/Archive thread-card stream,
  Thread Detail snapshot/update, Thread Detail row payload, projection witness,
  and canonical fixtures.
- Converted `contract/dock/dock-thread-card.schema.json` into a compatibility
  pointer to `contract/projection/projection-thread-card-stream.schema.json` so
  it cannot remain a second production schema.
- Renamed the contract checker path from Dock-only terminology to
  `scripts/check-projection-contract.mjs` and made `package.json`
  `contract:check` use it.
- Regenerated `CodexDock/AppServer/DockThreadCardDTO.swift` from
  `contract/projection/projection-thread-card-stream.schema.json`.
- Removed the remaining Thread Detail request-card display side door. The store
  no longer keeps a stored `@Published requestCards` list; `requestCards` is a
  derived view over current `ThreadEvent` projection rows.
- Added `CodexDock/ThreadDetail/ThreadDetailRequestCardPresentation.swift` for
  the only allowed client-local request state: typed input and transient
  response status keyed by `projectionID`.
- Removed the `requestCards:` render input from
  `ThreadDetailRenderProjector` and `ThreadDetailScreenStore`; request controls
  now attach to rows through `ThreadEvent.request`.
- Added a code guardrail at `ThreadDetailStore.sendDraft`: Projection v1 does
  not create Swift-side optimistic rows. Visible outbound rows must arrive from
  relay projection updates.
- Tightened `scripts/dock-relay-simulator-ui-sync-proof.test.mjs` so fake relay
  samples call the canonical projection engine helpers instead of spelling a
  local Thread Card / Thread Detail projection ID grammar.
- Split the oversized Thread Detail relay module after thermonuclear review.
  `scripts/dock-relay-thread-detail-ledger.mjs` now owns the mutable ledger
  class and re-exports the old public helpers for compatibility;
  `scripts/dock-relay-thread-detail-projection-adapter.mjs` owns the pure
  raw-Codex-to-projection adapter helpers. Identity still comes from
  `scripts/dock-relay-projection-engine.mjs`; the split removes file-size
  sprawl without creating a second identity path.

## Proof Log

- `rtk npm run test:relay` passed with 126 tests.
- `rtk swift test --filter AppServerClientTests` passed with 51 tests, 5
  intentional real-host smoke skips, and 0 failures.
- `rtk swift test --filter ThreadDetailStoreTests` passed with 60 tests and 0
  failures.
- `rtk swift test` passed on rerun with 339 tests, 5 intentional real-host
  smoke skips, and 0 failures. The first full run had one
  `ThreadDetailStoreTests` voice-capture timeout; the same test passed by
  itself immediately and passed in the full rerun.
- Initial `rtk make app-test SIM='iPhone 16'` exposed a real deployment
  mismatch: the already-running local relay was still serving Dock/Archive
  stream `schemaVersion: 2` with no projection envelope, while the new app
  correctly required v3. Direct `dock/subscribe` confirmed
  `rootSchemaVersion: 2` and no `projectionID`.
- Restarted the local services through `rtk make services` after
  `rtk make dock-relay-restart` stopped the launchd jobs but failed to
  bootstrap them back. Direct `dock/subscribe` then confirmed
  `rootSchemaVersion: 3`, `projectionID` present,
  `projectionEngineVersion: 1`, `view: dock`, and `rowRole: threadCard`.
- `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests' rtk make app-test SIM='iPhone 16'`
  passed after the local relay served v3 rows, proving Dock and Archive
  relay-backed rows could open Thread Detail by identifier in the iPhone 16
  simulator at that point in the implementation.
- A later default `rtk make app-test SIM='iPhone 16'` rerun exposed a separate
  deployment mismatch. The default test host list includes
  `amir-m5.fairy-salmon.ts.net:4510` and `home.fairy-salmon.ts.net:4510`.
  Direct relay probes showed `amir-m5` serving the new projection stream
  envelope with `rows`, `sourceHostID`, and `viewParamsKey`, while `home` was
  still serving the old stream grammar with `cards`, `hosts`, `baseSeq`, and
  `stateGeneration`.
- The app correctly rejected stale `home` as `schemaMismatch`. Local-only
  iPhone 16 proof passed with:
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testDockRowOpensSessionDetailByIdentifierWhenRowsExist' rtk make app-test SIM='iPhone 16'`.
- Focused default two-host proof failed with:
  `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testDockRowOpensSessionDetailByIdentifierWhenRowsExist' rtk make app-test SIM='iPhone 16'`.
  Simulator logs showed repeated `home.fairy-salmon.ts.net:4510`
  `schemaMismatch` rejections. This is not evidence that the local
  implementation duplicates outbound rows; it is evidence that default
  two-host proof cannot be considered clean until `home` is updated to the same
  code and restarted.
- 2026-06-02 simulator-target update: the latest user instruction switches the
  current and final simulator proof target to `SIM='iPhone 17'`. Earlier
  iPhone 16 runs are historical evidence only.
- `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 16'`
  completed with exit code 0 as historical proof.
- `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17'`
  completed with exit code 0 as the current simulator target. It intentionally
  excludes stale `home` until that host is updated to the same relay contract.
- `rtk node --test scripts/dock-relay-projection-engine.test.mjs scripts/dock-relay-thread-detail-ledger.test.mjs` passed.
- `rtk swift test --filter ThreadDetailDataEngineTests` passed after the
  required `projectionEngineVersion` change.
- `rtk node --test scripts/dock-relay-controlled-simulator-fixture.test.mjs scripts/dock-relay-simulator-ui-sync-proof.test.mjs scripts/dock-relay-observability.test.mjs scripts/dock-relay-projection-engine.test.mjs scripts/dock-relay-thread-detail-ledger.test.mjs` passed.
- `rtk node --test scripts/dock-relay-thread-detail-ledger.test.mjs` passed.
- `rtk swift test --filter ThreadDetailDataEngineTests` passed.
- `rtk swift test --filter ThreadDetailStoreTests` passed.
- `rtk swift test --filter AppServerClientTests` passed.
- `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs` passed.
- `rtk node --test scripts/dock-relay-observability.test.mjs` passed.
- `rtk npm run test:relay -- --test-name-pattern='thread detail ledger'`
  ran the relay test script and passed all 118 relay tests.
- `rtk npm run contract:check` passed after the Dock/Archive v3 envelope.
- `rtk node --test scripts/dock-relay-state-store.test.mjs scripts/dock-relay-card-contract.test.mjs scripts/dock-relay-state-subscriptions.test.mjs scripts/dock-relay-sync-audit.test.mjs scripts/dock-relay-projection-engine.test.mjs scripts/dock-relay-thread-detail-ledger.test.mjs` passed.
- `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs scripts/dock-relay-sync-audit.test.mjs scripts/dock-relay-controlled-simulator-fixture.test.mjs` passed.
- `rtk swift test --filter DockStoreStreamTests` passed with 17 tests,
  including malformed projection envelope resync coverage.
- `rtk swift test --filter DockStoreTests` passed with 54 tests.
- `rtk swift test --filter Archive` passed with 24 tests and 1 intentional
  skipped real-host archive round-trip.
- `rtk swift test --filter ThreadDetailDataEngineTests` passed with 9 tests.
- `rtk npm run contract:check` passed after adding the shared projection
  package and Thread Detail DTO guard.
- `rtk swift test --filter ThreadDetailDataEngineTests` passed with 10 tests
  after adding row-level projection engine version validation.
- `rtk npm run contract:check` passed through
  `scripts/check-projection-contract.mjs`, validating projection contract
  fixtures, the Dock compatibility pointer, generated Dock DTO freshness, and
  proof schemas.
- A later iPhone 17 Thread Detail open failed because the already-running local
  relay process was stale: live `thread/detail/subscribe` rows had
  `schemaVersion: 1` and `identityVersion: 1`, but no row-level
  `projectionEngineVersion`. Swift correctly rejected those rows after the DTO
  contract required `projectionEngineVersion`.
- `scripts/dock-relay-thread-detail-ledger.mjs` now emits row-level
  `projectionEngineVersion`, `contract/projection/payloads/thread-detail-row.schema.json`
  requires it directly, `scripts/dock-relay-thread-detail-ledger.test.mjs`
  proves emitted ledger rows carry the full projection envelope, and
  `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` rejects row-level
  projection-engine drift.
- `rtk npm run contract:check` passed after the row-level Thread Detail
  projection envelope tightening.
- `rtk npm run test:relay` passed with 129 relay tests after the relay ledger
  envelope test.
- `rtk swift test` passed on rerun with 340 tests, 5 intentional skips, and 0
  failures after the row-level projection validation change.
- Restarted local services with `rtk make services` after a failed
  `rtk make dock-relay-restart` left the services stopped. Direct
  `thread/detail/subscribe` then confirmed rows include
  `projectionEngineVersion: 1`.
- `APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testArchivedThreadRowOpensSessionDetailByIdentifierWhenRowsExist' rtk make app-test SIM='iPhone 17'`
  passed after the local relay served row-level `projectionEngineVersion`.
- Full `rtk make app-test SIM='iPhone 17'` then exposed an unrelated but real
  voice-state ordering bug:
  `ThreadDetailStoreTests.testUnexpectedCaptureStreamEndFailsRecoverablyWithoutSubmitting`.
  Root cause: the local capture-failure path canceled the realtime session
  before preserving the local failure state, and the downstream `.canceled` /
  `.closed` events could clear the visible recovery error in the Xcode/iOS
  timing path. `CodexDock/State/ThreadDetailStore+Voice.swift` now freezes the
  local failure state and stops observation before canceling the realtime
  session.
- Focused voice proof passed:
  `rtk swift test --filter ThreadDetailStoreTests.testUnexpectedCaptureStreamEndFailsRecoverablyWithoutSubmitting`
  and
  `APP_TEST_ONLY='CodexDockTests/ThreadDetailStoreTests/testUnexpectedCaptureStreamEndFailsRecoverablyWithoutSubmitting' rtk make app-test SIM='iPhone 17'`.
- Full `rtk make app-test SIM='iPhone 17'` still failed on the Dock-row UI
  smoke because the default test host list includes stale
  `home.fairy-salmon.ts.net:4510`.
- Direct JSON-RPC probe showed the concrete host drift:
  `amir-m5.fairy-salmon.ts.net:4510` returns the new projection Dock payload
  with `rows`, `projectionEngineVersion`, `projectionID`, and
  `sourceHostID`, and `thread/detail/subscribe` succeeds for the first row.
  `home.fairy-salmon.ts.net:4510` returns the old Dock payload with
  `cards`, `baseSeq`, `stateGeneration`, and no `sourceHostID`, and
  `thread/detail/subscribe` fails with `-32601 unsupported method`.
- Local-host iPhone 17 Dock-row proof passed:
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' APP_TEST_ONLY='CodexDockUITests/CodexDockAutomationSmokeTests/testDockRowOpensSessionDetailByIdentifierWhenRowsExist' rtk make app-test SIM='iPhone 17'`.
- Full local-host iPhone 17 proof passed:
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17'`.
- Full `rtk swift test` passed with 343 tests, 5 intentional skips, and 0
  failures after fixing the required `freshness` DTO usage, the test snapshot
  `schemaVersion` helper, and the request-card fixture.
- `rtk npm run contract:check` passed after these fixes.
- `rtk npm run test:relay` passed with 133 relay tests after these fixes.
- Composer 2.5 Fast fresh consult at
  `/tmp/fresh-consult/projection-identity-implementation-20260602T033312Z-3plpJj`
  returned `pass-with-notes` with follow-up blockers. The verified fixes after
  that consult are: remove the parallel request-card render list, test the
  no-Swift-optimistic-row rule, and route the simulator proof fixture IDs
  through the canonical projection engine.
- `rtk swift test --filter ThreadDetailStoreTests` passed with 61 tests and 0
  failures after removing the stored request-card list.
- `rtk swift test --filter ThreadDetailRenderProjectorTests` passed with 2
  tests and 0 failures after removing the `requestCards:` render input.
- `rtk swift test --filter ThreadDetailStoreTests.testSendDraftOutboundUserMessageMergesWithCanonicalProjectionResync`
  passed after adding the no-optimistic-row assertion.
- `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs` passed
  with 34 tests after routing fixture IDs through the canonical projection
  engine.
- Full `rtk swift test` passed with 347 tests, 5 intentional skips, and 0
  failures after the request-card projection-state follow-up.
- Full `rtk npm run test:relay` passed with 134 relay tests after the proof
  fixture canonical-helper follow-up.
- `rtk npm run contract:check` passed after the follow-up changes.
- Composer 2.5 Fast fresh consult rerun at
  `/tmp/fresh-consult/projection-identity-followup-20260602T034456Z-3KfpER`
  returned `pass-with-notes`, `BLOCKING: none`, `CONFIDENCE: high`.
  Non-blocking notes: default two-host iPhone 17 proof remains blocked by stale
  `home`; thermonuclear review was still pending at that pass and is resolved
  below; a named
  `outbound-message-identity` controlled scenario is still plan-only;
  `dock-relay-sync-audit.mjs` still computes Dock expected projection IDs for
  audit diagnostics, not Thread Detail acceptance proof; relay
  pending/`clientMutationID` supersession and full permanent architecture items
  remain future scope, not v1 regressions.
- Final regression rerun after the latest source-identity and proof checks:
  `rtk npm run test:relay` passed with 134 relay tests;
  `rtk npm run contract:check` passed;
  `rtk swift test` passed with 347 tests, 5 intentional real-host skips, and 0
  failures.
- Final local-host iPhone 17 proof passed:
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17'`
  completed with exit code 0. The Makefile log for this run is
  `.codex-dock/logs/app-test-20260602034243.log`.
- Final Composer 2.5 Fast consult ran at
  `/tmp/fresh-consult/projection-identity-final-20260602T034516Z-mkzedL`.
  Verdict: `pass-with-notes`; `BLOCKING: none`; `CONFIDENCE: high`.
  The consult signed off the local single-host outbound duplicate bug class and
  the Thread Detail projection architecture. Its non-blocking notes are: no
  dedicated outbound-send iPhone 17 UI test yet, test fakes still spell some
  projection IDs locally, controlled fixtures still model relay-internal raw
  routes as adapter traffic, Dock/Archive navigation still carries
  `HostScopedThreadID` as an action handle, and default two-host proof remains
  blocked until `home.fairy-salmon.ts.net:4510` is updated.
- Thermonuclear maintainability review found one real structural cleanup: the
  new Thread Detail relay module had grown to 1,157 lines. That was fixed by
  splitting pure adapter code into
  `scripts/dock-relay-thread-detail-projection-adapter.mjs`. The ledger file is
  now 235 lines, the adapter file is 970 lines, and both still import identity
  primitives from `scripts/dock-relay-projection-engine.mjs`.
- `rtk node --test scripts/dock-relay-thread-detail-ledger.test.mjs` passed
  after the split.
- `rtk npm run test:relay` passed with 134 relay tests after the split.
- `rtk npm run contract:check` passed after the split.
- Restarted the local relay/app-server bundle with `rtk make dock-relay-restart`
  so the simulator proof used the current relay JavaScript.
- Current final local-host iPhone 17 proof passed after that restart:
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17'`
  completed with exit code 0. The Makefile log for this run is
  `.codex-dock/logs/app-test-20260602035221.log`.
- `rtk make dock-relay-status` reported both `raw-app-server` and `dock-relay`
  active, with `raw-app-server-readyz`, `relay-readyz`, and `relay-statusz`
  healthy.

## Remaining Audit Targets

These are not signed off yet:

- Default two-host proof is blocked until the `home` relay deployment serves
  the same projection contract as `amir-m5`. This is proven by direct
  JSON-RPC: `home` still serves the old `cards/baseSeq` Dock grammar and
  rejects `thread/detail/subscribe` with `-32601 unsupported method`.
- Current required simulator proof target is `SIM='iPhone 17'`.
- Non-blocking follow-ups from Composer: add a dedicated outbound-send
  iPhone 17 UI proof, retire or further quarantine test-local projection
  grammar helpers, and continue the longer-term Dock/Archive action-handle
  transition away from `HostScopedThreadID`.
