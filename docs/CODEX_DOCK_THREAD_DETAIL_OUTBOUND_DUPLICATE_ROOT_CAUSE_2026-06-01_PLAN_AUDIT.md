# Plan Audit Log

Plan: `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`
Audit log: `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve-with-notes for local
single-host iPhone 17 proof; default two-host deployment not signed off
Last reviewed: 2026-06-02T03:52:00Z
Scope: whole plan plus canonical protocol reference contract

## Current Blocking Findings

None.

## Current Non-Blocking Findings

- Default two-host proof remains blocked until `home.fairy-salmon.ts.net:4510`
  is updated to the same relay contract as `amir-m5.fairy-salmon.ts.net:4510`.
  This is a deployment blocker, not a local implementation blocker.
- There is no dedicated iPhone 17 UI test that sends an outbound composer
  message and asserts exactly one visible user row. The bug class is covered by
  the relay ledger tests, Swift outbound acceptance test, duplicate detail-row
  UI proof failure, and local-host iPhone 17 app-test proof.
- `CodexDockTests/LegacyThreadEventFixtureNormalizer.swift` and some fake
  sessions still spell projection identity locally for quarantined legacy/test
  fixtures. Production display does not import those paths.
- Dock/Archive actions still carry `HostScopedThreadID` as an action/navigation
  handle while wire/storage identity is `projectionID`.

## Current Implementation Findings

None.

## Resolved Implementation Findings

### IMP-001 - Projection Contract Package Was Still Dock-Only

- Status: resolved 2026-06-02T03:22:00Z
- Problem: the plan made `contract/projection/**` a hard architecture gate, but
  the worktree still used a Dock-only contract package.
- Resolution: added `contract/projection/**` with shared projection envelope,
  row-role, view-params, Dock/Archive thread-card stream, Thread Detail
  snapshot/update, Thread Detail row payload, projection witness, and fixture
  schemas. Existing Dock stream fixtures were copied into
  `contract/projection/fixtures`, and a Thread Detail projection fixture was
  added.
- Side-door closure: `contract/dock/dock-thread-card.schema.json` is now only a
  `$ref` compatibility pointer to
  `contract/projection/projection-thread-card-stream.schema.json`. The checker
  fails if that historical path becomes a second schema again.
- Tooling proof: `package.json` now runs
  `node scripts/check-projection-contract.mjs`; that checker validates the
  projection schema package, projection fixtures, the Dock compatibility
  pointer, the generated Dock Swift DTO source, and required Swift Thread
  Detail DTO fields read from the projection schemas.
- Runtime validation proof: `ThreadDetailEventDTO` now carries
  `projectionEngineVersion`, and `ThreadDetailDataEngine` rejects row-level
  projection engine version drift instead of only checking the snapshot/update
  envelope.
- Verification: `rtk npm run contract:check` passed, and
  `rtk swift test --filter ThreadDetailDataEngineTests` passed with 10 tests.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical plan artifact | `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md` | Owns the root cause, architecture, phases, side-door list, and proof requirements. | parent | read |
| Canonical protocol reference | `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md` proposed Thread Detail event ledger section, allowed routes, legacy/proposed flows, command gate notes | Must become the implementation contract so the audit doc does not become a second source of truth. | parent | read |
| Current Swift raw identity path | `CodexDock/Models/ThreadEvent.swift` `ThreadEvent`, `ThreadEventDisplayOrder`, `ThreadEventNormalizer` | Current duplicate source: raw history/live normalization, method-suffix delta IDs, UUID fallback, local ordering. | parent | read |
| Current Swift merge path | `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift` `ThreadDetailDataEngine`, `ThreadEventIndex`, `ThreadEventStreamMergeKey` | Current duplicate source: exact-ID merge plus secondary stream key. | parent | read |
| Current Swift Thread Detail owner | `CodexDock/State/ThreadDetailStore.swift` `ThreadDetailSession`, load/read/resume flow, dock-row reread, live notification/request handling, request-card storage | Main owner path that must move from raw detail routes to relay detail ledger DTOs. | parent | read |
| Current request-card join | `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`; `CodexDock/Models/ServerRequestCard.swift`; `CodexDock/Features/Session/ThreadMessageListView.swift` | Current side door: request cards use their own IDs and secondary stream-key join. | parent | read |
| Current relay routes and command binding | `scripts/dock-relay.mjs` `resumeThread`, upstream forwarding, command gate, dispatcher routes | Target owner must add `thread/detail/*` and make subscribe own command binding without exposing raw display truth. | parent | read |
| Swift route constants/client DTOs | `CodexDock/AppServer/AppServerMethods.swift`; `CodexDock/AppServer/AppServerClient.swift`; `CodexDock/AppServer/ThreadDetailDTO.swift`; `CodexDock/AppServer/ThreadDTO.swift` | New DTOs and client calls must fit the existing JSON-RPC client pattern. | parent | read |
| JS proof identity side door | `scripts/codex-dock-live-filter-truth.mjs`; `scripts/dock-relay-simulator-ui-sync-proof.mjs` | Current proof reconstructs event IDs independently; the plan requires proof to consume relay ledger IDs. | parent | read |
| Test/proof target | `Makefile`, README mentions, plan proof commands | Plan must align with the latest user instruction: final simulator proof is `SIM='iPhone 17'`. | parent | read |
| Final architecture acceptance | `/tmp/fresh-consult/projection-identity-final-architecture-accept-20260601T202033Z-iD2Csb`; plan `Fresh Consult Status`; canonical projection sections | Confirms the last zero-sunk-cost architecture pass has no remaining blocking architecture gaps before implementation. | parent | read |
| Current Composer tightening | `/tmp/fresh-consult/projection-identity-current-architecture-20260601T214835Z-2Y0zge`; `/tmp/fresh-consult/projection-identity-current-architecture-rerun-20260601T215013Z-q4WjoV`; plan `Composer Tightening Incorporated` | Confirms request-row identity, fail-closed witness export, Phase 1 contract package gate, Swift adapter limits, and forbidden-pattern gates are now normative in the plan. | parent | read |
| Current implementation side-door search | `rg -n -e baseSeq -e upsertCards -e deleteCardIDs -e visibleEventIDs -e expectedMessageProjectionIDs -e projectionIDForThread -e 'additionalProperties.*true' scripts contract/proof CodexDock CodexDockTests` | Confirms remaining hits are implementation targets already named by the plan, not unplanned architecture gaps. | parent | read |

Native subagents were not used for this plan-readiness audit because the current
multi-agent tool explicitly allows spawning only when the user explicitly asks
for sub-agents. The audit still used parallel local file reads.

## Required Lens Checklist

- [x] Outcome North Star
- [x] Ambiguity and miscommunication
- [x] Requirements, constraints, and simplicity
- [x] Tiny-team maintainability
- [x] Depth-first implementation risk
- [x] Code-truth map
- [x] Canonical owner and SSOT
- [x] Existing pattern and convergence
- [x] Caller, invariant, and state model
- [x] Drift-proof coupling
- [x] Elegance and code-judo
- [x] Deletion and side-door closure
- [x] Proof and phase exit
- [x] Conditional lenses: docs-contract-drift, security-boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PLA-001 | The plan still said not to implement and used `SIM='iPhone 17'`, while the active goal requires implementation and iPhone 16 simulator proof. | Treat those as stale planning text; or implement anyway and risk proof-target drift. | Could route implementation to the wrong stop boundary and simulator. | Make the plan implementation-ready and use `SIM='iPhone 16'` for final proof. | parent, from active goal | Updated plan status text and Phase 6/simulator commands in `docs/CODEX_DOCK_THREAD_DETAIL_OUTBOUND_DUPLICATE_ROOT_CAUSE_2026-06-01.md`. | resolved |
| PLA-002 | A prior thread update requested iPhone 17 simulator proof. | Treat iPhone 17 as final; or treat it as supplemental after active-goal metadata confirms iPhone 16. | Could produce proof on the wrong simulator. | Superseded by PLA-003: iPhone 17 proof is supplemental only. | user, then active goal metadata | Historical iPhone 17 proof remains in the implementation log as supplemental evidence. | superseded |
| PLA-003 | Active goal metadata explicitly required iPhone 16 simulator proof at that point. | Keep stale iPhone 17 doc text; or align the docs and final proof to the active goal. | Could finish with proof on the wrong simulator. | Use `SIM='iPhone 16'` for that pass. Treat iPhone 17 proof as supplemental historical evidence. | parent, from active goal metadata | Updated this audit, implementation log, and plan proof command to `SIM='iPhone 16'`; later superseded by PLA-004. | superseded |
| PLA-004 | The latest user instruction says, "switch to the iphone 17 for testing, note it in your plan." | Keep stale active-goal metadata as final; or treat the newest explicit user instruction as the proof target. | Could keep running the wrong simulator and keep documenting the wrong sign-off target. | Use `SIM='iPhone 17'` for current and final simulator proof. Treat iPhone 16 runs as historical evidence only. | user | Updated the main plan simulator command, this audit, and the implementation log to name `SIM='iPhone 17'` as the current proof target. | resolved |

## Pass History

### Pass 1 - 2026-06-01

- Mode: plan-readiness
- Scope: whole plan plus canonical protocol reference contract
- Baseline reviewed: current worktree docs and code
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent plan-audit lenses; no native subagents because tool policy prohibits spawning without explicit user request
- Code areas read: see coverage ledger
- Findings added: PLA-001
- Findings resolved: PLA-001
- Findings carried forward: none
- Verdict: ready
- Next audit focus: after implementation, run plan-audit in implementation-audit mode against changed code and this plan.

### Pass 2 - 2026-06-01

- Mode: plan-readiness refresh
- Scope: architecture doc plus canonical protocol reference after final contract edits
- Baseline reviewed: current worktree docs and partial implementation WIP
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent plan-audit lenses
- Findings added: none
- Findings resolved: none
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation must replace the partial event-id bridge with relay-owned `sourceHostID`, `sourceRef`, `projectionID`, `displayOrderKey`, `epoch`, and `seq`.

### Pass 3 - 2026-06-01

- Mode: plan-readiness refresh before active implementation
- Scope: whole plan, protocol reference, live-update cross-doc, current WIP diff
- Baseline reviewed: current worktree with partial Thread Detail projection implementation
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent plan-audit lenses; no native subagents because the available multi-agent tool permits spawning only when the user explicitly asks for sub-agents
- Code areas read: plan implementation phases, Thread Detail DTO/data-engine/store route surfaces, relay thread-detail ledger, relay dispatcher, simulator proof scripts, contract/proof side-door search
- Findings added: none
- Findings resolved: none
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code changes must prove the accepted nested projection-row envelope replaces the current flattened `ThreadDetailEventDTO` bridge and that proof scripts no longer accept fixture-computed visible IDs.

### Pass 4 - 2026-06-01T20:26:45Z

- Mode: plan-readiness final refresh after architecture acceptance
- Scope: whole plan, canonical protocol reference, final projection-plane tightening, and active-goal proof target
- Baseline reviewed: current worktree docs with partial Thread Detail projection WIP
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent plan-audit lenses; no native subagents because the available multi-agent tool permits spawning only when the user explicitly asks for sub-agents
- Code areas read: plan identity law, shared projection envelope, Dock/Archive scope authority, Archive Cleanup projection view, Host Registry projection rows, projection witness plane, acceptance criteria, final Composer 2.5 Fast consult status, and `SIM='iPhone 16'` proof command
- Findings added: none
- Findings resolved: none
- Findings carried forward: none
- Verdict: ready
- Next audit focus: use plan-implement for the unified relay projection architecture, then run plan-audit in implementation-audit mode against the changed code before final proof.

### Pass 5 - 2026-06-01T21:58:00Z

- Mode: plan-readiness refresh after current Composer tightening
- Scope: whole plan, new `2026-06-01 Current Ask Answer`, new `Composer Tightening Incorporated`, final consult status, and active side-door search
- Baseline reviewed: current dirty worktree with partial projection implementation and latest architecture doc edits
- Test/CI context accepted, if supplied: not applicable
- Agents/lenses run: parent plan-audit lenses; no native subagents because the available multi-agent tool permits spawning only when the user explicitly asks for sub-agents
- Code areas read: current plan anchors, Composer rerun verdicts, proof schemas, live-filter proof scripts, simulator proof scripts, relay state stream old-field hits, and projection helper imports
- Findings added: none
- Findings resolved: none
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation must delete or quarantine the remaining old proof and stream grammar side doors: `baseSeq`, `upsertCards`, `deleteCardIDs`, `visibleEventIDs`, fixture-computed expected projection IDs, permissive proof schemas, and request-card display IDs derived from `requestID`.

### Pass 6 - 2026-06-02T02:55:00Z

- Mode: proof-target update
- Scope: simulator proof target only
- Baseline reviewed: current user instruction, plan simulator proof command, implementation proof log
- Test/CI context accepted, if supplied: iPhone 16 local-only app-test finished with exit code 0; later iPhone 17 text is now superseded by active-goal metadata requiring iPhone 16
- Agents/lenses run: parent plan-audit target consistency check
- Code areas read: simulator proof command and implementation proof log
- Findings added: PLA-002
- Findings resolved: PLA-002
- Findings carried forward: IMP-001
- Verdict: not-approved until IMP-001 is repaired
- Next audit focus: create the shared projection contract package, then rerun implementation-audit before fresh consult / thermonuclear review.

### Pass 7 - 2026-06-02T03:22:00Z

- Mode: implementation-audit
- Scope: shared projection contract package gate from the accepted plan
- Baseline reviewed: current worktree after adding `contract/projection/**`,
  replacing the old Dock schema with a pointer, renaming the contract checker,
  regenerating `CodexDock/AppServer/DockThreadCardDTO.swift`, and binding
  `CodexDock/AppServer/ThreadDetailDTO.swift` to required projection schema
  fields through the checker
- Test/CI context accepted, if supplied: `rtk npm run contract:check` passed;
  `rtk swift test --filter ThreadDetailDataEngineTests` passed with 10 tests
- Agents/lenses run: parent plan-audit implementation lenses
- Code areas read: `contract/projection/**`,
  `contract/dock/dock-thread-card.schema.json`,
  `scripts/check-projection-contract.mjs`,
  `scripts/generate-dock-thread-card-contract.mjs`,
  `CodexDock/AppServer/DockThreadCardDTO.swift`,
  `CodexDock/AppServer/ThreadDetailDTO.swift`,
  `CodexDock/ThreadDetail/ThreadDetailDataEngine.swift`, `package.json`
- Findings added: none
- Findings resolved: IMP-001
- Findings carried forward: none
- Verdict: projection contract gate approved; final implementation remains
  pending fresh consult, thermonuclear review, and required simulator proof
  before overall sign-off.

### Pass 8 - 2026-06-02T03:27:00Z

- Mode: proof-target consistency update
- Scope: active-goal metadata versus stale simulator-target doc text
- Baseline reviewed: active goal metadata, plan proof command, plan audit, and
  implementation log
- Test/CI context accepted, if supplied: previous iPhone 16 and iPhone 17 runs
  are historical; at that pass final sign-off still required a current iPhone
  16 run
- Agents/lenses run: parent plan-audit target consistency check
- Code areas read: active goal metadata and simulator proof sections
- Findings added: PLA-003
- Findings resolved: PLA-003
- Findings carried forward: none
- Verdict at that pass: final simulator target was `SIM='iPhone 16'`;
  superseded by Pass 9 / PLA-004.

### Pass 9 - 2026-06-02

- Mode: proof-target consistency update
- Scope: latest user instruction versus stale active-goal simulator-target text
- Baseline reviewed: current user instruction, plan proof command, plan audit,
  and implementation log
- Test/CI context accepted, if supplied: previous iPhone 16 and iPhone 17 runs
  are historical; final sign-off now requires a current iPhone 17 run
- Agents/lenses run: parent plan-audit target consistency check
- Code areas read: simulator proof sections and implementation proof log
- Findings added: PLA-004
- Findings resolved: PLA-004
- Findings carried forward: none
- Verdict: final simulator target is `SIM='iPhone 17'`

### Pass 10 - 2026-06-02

- Mode: implementation-audit after iPhone 17 proof
- Scope: projection contract implementation, Swift render/store follow-through,
  relay Thread Detail projection rows, simulator proof, and default host-list
  blocker
- Baseline reviewed: current worktree after fixing required projection
  envelope fields, row-level Thread Detail `projectionEngineVersion`, voice
  capture failure ordering, required Dock stream `freshness`, test snapshot
  `schemaVersion`, and request-card projection fixture identity
- Test/CI context accepted, if supplied:
  `rtk npm run contract:check` passed;
  `rtk npm run test:relay` passed with 133 tests;
  `rtk swift test` passed with 343 tests, 5 intentional skips, and 0 failures;
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17'`
  passed
- Agents/lenses run: parent plan-audit implementation lenses
- Code areas read: implementation log, projection schemas/checkers, generated
  Dock DTO, Thread Detail DTO/data engine, Thread Detail render projector,
  Thread Detail voice store, Dock stream lifecycle/table, Dock test support,
  and iPhone 17 app-test evidence
- Findings added: none against local implementation; deployment blocker
  recorded for stale `home`
- Findings resolved: row-level Thread Detail projection envelope drift; required
  Dock stream freshness drift; request-card fixture identity drift; voice
  capture failure ordering race
- Findings carried forward: default two-host proof remains blocked until
  `home.fairy-salmon.ts.net:4510` is updated and restarted
- Verdict: local implementation is audit-clean for current Mac/iPhone 17 proof;
  default two-host deployment is not signed off because `home` still serves the
  old `cards/baseSeq` Dock grammar and rejects `thread/detail/subscribe` with
  `-32601 unsupported method`

### Pass 11 - 2026-06-02

- Mode: implementation-audit after Composer 2.5 Fast follow-up findings
- Scope: Thread Detail request-card display identity, outbound optimistic-row
  rule, simulator proof fixture identity, and current iPhone 17 proof target
- Baseline reviewed: Composer 2.5 Fast consult output at
  `/tmp/fresh-consult/projection-identity-implementation-20260602T033312Z-3plpJj`,
  `ThreadDetailStore`, `ThreadDetailRenderProjector`,
  `ThreadDetailScreenStore`,
  `ThreadDetailRequestCardPresentation`, request-card tests, outbound send
  test, and simulator UI sync proof tests
- Test/CI context accepted, if supplied:
  `rtk swift test --filter ThreadDetailStoreTests` passed;
  `rtk swift test --filter ThreadDetailRenderProjectorTests` passed;
  `rtk swift test --filter ThreadDetailStoreTests.testSendDraftOutboundUserMessageMergesWithCanonicalProjectionResync`
  passed;
  `rtk node --test scripts/dock-relay-simulator-ui-sync-proof.test.mjs` passed
- Agents/lenses run: parent follow-up audit after fresh consult
- Code areas read: request-card projection/render path, outbound send path,
  proof fixture ID helpers, implementation log
- Findings added: none after fixes
- Findings resolved: independent request-card render list; Swift optimistic-row
  ambiguity; test-side locally spelled projection ID grammar
- Findings carried forward at that pass: final Composer 2.5 Fast rerun,
  thermonuclear review, full regression, and final iPhone 17 proof were still
  pending then and are resolved in Pass 13; default two-host proof remains
  blocked by stale `home`
- Verdict at that pass: local follow-up fixes were audit-clean for the
  request-card and outbound duplicate class; final sign-off moved to Pass 13

### Pass 12 - 2026-06-02

- Mode: Composer 2.5 Fast fresh consult rerun after follow-up fixes
- Scope: production side doors for outbound duplicate identity, request-card
  display truth, no-Swift-optimistic-row rule, proof/test identity side doors,
  iPhone 17 proof target, and blockers before thermonuclear review
- Baseline reviewed by child: current dirty worktree, implementation docs,
  `Makefile`, Thread Detail store/data/projector/request-card paths, relay
  projection ledger/tests, simulator proof scripts/tests, and controlled
  simulator fixture
- Test/CI context accepted, if supplied: parent logged full Swift, relay,
  contract, and local-host iPhone 17 app-test proof
- Agents/lenses run: fresh consult via Cursor Agent Composer 2.5 Fast
- Run directory:
  `/tmp/fresh-consult/projection-identity-followup-20260602T034456Z-3KfpER`
- Verdict: `pass-with-notes`
- Blocking: none
- Non-blocking carried forward: default two-host proof blocked by stale
  `home`; thermonuclear review was still pending at this pass and was resolved
  in Pass 13; named `outbound-message-identity`
  controlled scenario remains plan-only; sync audit still computes Dock
  expected projection IDs for diagnostics; pending/`clientMutationID`
  supersession and full permanent architecture items remain future scope, not
  v1 regressions
- Parent spot-check: accepted. The non-blocking notes match current repo
  evidence and do not re-open the request-card or outbound duplicate production
  path.

### Pass 13 - 2026-06-02T03:52:00Z

- Mode: final implementation-audit
- Scope: whole local single-host implementation for the outbound duplicate bug
  class, shared projection identity, proof-side duplicate detection, final
  Composer 2.5 Fast consult, thermonuclear maintainability review, and iPhone
  17 simulator proof
- Baseline reviewed: current worktree after source-identity guards in
  `ThreadDetailDataEngine` and `ThreadCardTable`, request-card projection-state
  derivation, canonical projection engine usage in relay proof fixtures,
  duplicate Thread Detail UI-row proof detection, and final local service
  refresh
- Test/CI context accepted, if supplied:
  `rtk npm run test:relay` passed with 134 tests;
  `rtk npm run contract:check` passed;
  `rtk swift test` passed with 347 tests, 5 intentional skips, and 0 failures;
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17'`
  completed with exit code 0
- Agents/lenses run: parent plan-audit implementation lenses, earlier native
  parallel-agent blockers spot-checked against current code, Composer 2.5 Fast
  fresh consult, and thermo-nuclear maintainability review
- Run directory:
  `/tmp/fresh-consult/projection-identity-final-20260602T034516Z-mkzedL`
- Code areas read: implementation log, projection schemas/checkers, projection
  witness schema/route, relay projection engine, Thread Detail ledger, relay
  stream store/cache invalidation, controlled simulator matrix route
  requirements, simulator UI sync proof duplicate detection, Swift Thread
  Detail data engine/store/render path, request-card presentation path,
  `ThreadCardTable`, app-test log path, and final fresh-consult output
- Findings added: non-blocking notes only
- Findings resolved: stale final review/proof state; old source-identity guard
  gap; old raw-route proof matrix requirement; old request-row identity side
  door; old stream/witness contract drift; old projection cache fingerprint
  drift
- Findings carried forward: default two-host deployment remains blocked until
  `home.fairy-salmon.ts.net:4510` is updated; dedicated outbound-send iPhone 17
  UI test remains a non-blocking follow-up; test-local legacy projection
  grammar should be retired or further quarantined when practical
- Verdict: approve-with-notes for local single-host implementation and iPhone
  17 proof. Do not claim default two-host proof until `home` is updated.

### Pass 14 - 2026-06-02T03:54:01Z

- Mode: post-thermonuclear correction and current iPhone 17 proof refresh
- Scope: Thread Detail relay module structure, local relay restart, and current
  simulator proof target
- Baseline reviewed: current worktree after splitting
  `scripts/dock-relay-thread-detail-ledger.mjs` into a 235-line ledger module
  plus `scripts/dock-relay-thread-detail-projection-adapter.mjs` for pure
  raw-Codex-to-projection adapter code
- Test/CI context accepted:
  `rtk node --test scripts/dock-relay-thread-detail-ledger.test.mjs` passed;
  `rtk npm run test:relay` passed with 134 tests;
  `rtk npm run contract:check` passed;
  `rtk make dock-relay-restart` restarted the local relay/app-server bundle;
  `CODEX_DOCK_UI_TEST_HOSTS='amir-m5.fairy-salmon.ts.net:4510' rtk make app-test SIM='iPhone 17'`
  completed with exit code 0 after that restart, with log
  `.codex-dock/logs/app-test-20260602035221.log`
- Agents/lenses run: parent thermonuclear maintainability check plus current
  iPhone 17 runtime proof
- Findings added: none after the split
- Findings resolved: the oversized 1,157-line Thread Detail relay file is no
  longer accepted as-is; the mutable ledger path remains one path, while pure
  adapter helpers live in a separate module and continue to import identity
  primitives from `scripts/dock-relay-projection-engine.mjs`
- Findings carried forward: default two-host deployment remains blocked until
  `home.fairy-salmon.ts.net:4510` is updated; dedicated outbound-send iPhone 17
  UI proof remains a non-blocking follow-up
- Verdict: current local-host iPhone 17 implementation proof is clean. Do not
  claim default two-host proof until `home` is updated.

## Plan-Readiness Verdict

The plan is ready for implementation.

Evidence:

- The North Star is explicit: one outbound user send yields one visible user-message row, and identity drift is eliminated architecturally by one relay-owned detail event ledger.
- The canonical source of truth is explicit: `docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md` owns the proposed `ThreadDetailEventDTO`, `ThreadDetailSnapshotDTO`, `ThreadDetailUpdateDTO`, route, identity, ordering, and ledger semantics.
- The plan names the old Swift/JS identity side doors and requires removing or demoting them.
- The first implementation slices are depth-first: contract, relay normalizer, relay API, Swift DTO rendering, proof scripts, then runtime proof.
- Proof targets temporal convergence, not static snapshots: outbound live/history permutations, delta/completed/history convergence, request resolution, reconnect/resync, and simulator UI proof.
- The current user-selected proof target has been carried into the plan:
  iPhone 17 simulator. iPhone 16 proof remains historical evidence, not final
  sign-off.
- Current local iPhone 17 proof passed against
  `amir-m5.fairy-salmon.ts.net:4510` after restarting the local relay/app-server
  bundle; default two-host proof remains a deployment blocker until
  `home.fairy-salmon.ts.net:4510` is updated to the same contract.
- The final Composer 2.5 Fast consult accepted the architecture with `BLOCKING: none` and `CONFIDENCE: high`; remaining notes are implementation-phase gates, not architecture changes.
- The current Composer 2.5 Fast rerun accepted the tightened architecture with `BLOCKING: none` and `CONFIDENCE: high`; it verified request-row identity, witness fail-closed semantics, Phase 1 contract package gating, Swift render-adapter limits, and forbidden-pattern CI gates.
- The final implementation consult at
  `/tmp/fresh-consult/projection-identity-final-20260602T034516Z-mkzedL`
  returned `pass-with-notes` with `BLOCKING: none` and `CONFIDENCE: high`.
  Its notes are follow-ups or deployment scope, not local production duplicate
  blockers.
- The final plan now covers the formerly open side doors: Archive Cleanup, Host Registry, proof witnesses, fixture expected IDs, local pin metadata, and live-filter proof scripts.
