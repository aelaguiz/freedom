# Plan Audit Log

Plan: `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01.md`
Audit log: `docs/CODEX_DOCK_LIVE_UPDATE_ARCHITECTURE_AND_TESTING_REFERENCE_2026-06-01_PLAN_AUDIT.md`
Current plan verdict: ready
Current implementation code-review verdict: approve-with-notes
Last reviewed: 2026-06-01 06:08 UTC
Scope: whole plan, Sections 0-10 as canonical implementation contract

## Current Blocking Findings

None.

## Current Non-Blocking Findings

None.

## Current Implementation Findings

### IMP-001 - Proof fixture file is still too large

- Severity: non-blocking maintainability note.
- Problem: `scripts/dock-relay-controlled-simulator-fixture.mjs` is now a very
  large proof harness file. It is organized enough to audit, but it is not a
  pleasant tiny-team maintenance unit.
- Why it does not block approval: this is proof-only infrastructure, not a
  production data side door, and the implementation deletes the old production
  side doors instead of moving them into the fixture. The final matrix and proof
  contracts depend on this harness today.
- Required follow-up when touching it again: split scenario data, fake
  app-server behavior, simulator orchestration, and report writing into focused
  modules without changing proof semantics.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-state-subscriptions.mjs`, `scripts/dock-relay-thread-data.mjs`, `contract/dock/dock-thread-card.schema.json`, `CodexDock/AppServer/DockThreadCardDTO.swift` | Relay-owned card truth, stream identity, freshness, heartbeat | parent, explorers, Composer | read |
| Swift stream application | `CodexDock/State/ThreadCardTable.swift`, `CodexDock/State/DockStore.swift`, `CodexDock/State/AppServerThreadCardStreamClient.swift` | Existing stream apply rules, `.dock` hard-code, stale-generation gap, heartbeat handling | parent, explorers, Composer | read |
| Archive and cleanup side doors | `CodexDock/Archive/ArchiveDataEngine.swift`, `CodexDock/State/ArchiveStore.swift`, `CodexDock/Archive/ArchiveCleanupDataEngine.swift`, `CodexDock/State/ArchiveCleanupStore.swift`, `CodexDock/State/ThreadCardHostSnapshotLoader.swift`, `CodexDock/Features/Archive/ArchiveCleanupView.swift` | Snapshot-only product paths that could bypass the canonical stream path | parent, explorers, Composer | read |
| Thread Detail continuity | `CodexDock/State/ThreadDetailStore.swift`, `CodexDock/AppServer/ThreadDetailDTO.swift`, `CodexDock/State/AppServerThreadDetailSession.swift`, `scripts/dock-relay.mjs` | Full history request, `itemsView`, upstream recovery close/reconnect behavior | parent, explorers, Composer | read |
| Simulator UI proof and current dump | `CodexDockUITests/CodexDockDisplayedSyncProofTests.swift`, `Makefile`, `scripts/dock-relay-simulator-ui-sync-proof.mjs` | Accessibility sampling, current lack of `sim-ui-dump`, launch/skip behavior, proof parsing | parent, explorers, Composer | read |
| Visible ordering proof | `CodexDockUITests/DisplayedUICaptureSupport.swift`, `scripts/dock-relay-simulator-ui-sync-proof.mjs`, `scripts/dock-relay-controlled-simulator-matrix.mjs`, `CodexDock/State/DockCardProjection.swift` | Proves the sim cannot pass while Dock rows or Thread Detail messages are visually reversed/out of relay order | parent, Composer | read |
| Controlled proof and scenarios | `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-controlled-simulator-fixture.mjs`, `scripts/dock-relay-controlled-simulator-matrix.mjs`, `Makefile` | Over-time proof, `archive-toggle` support gap, matrix coverage | parent, explorers, Composer | read |
| Raw endpoint/security boundary | `Makefile`, `CodexDock/Configuration/DockHostConfiguration.swift`, `scripts/device-relay-config.mjs`, host-service tests found by `rg :4500` | Ensure proof and phone path cannot count raw app-server `:4500` | parent, explorers, Composer | read |
| Docs/runbook contract | `README.md`, this plan, Appendix A source reference | Makefile-owned commands, proof semantics, appendix override | parent, Composer | read |

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
- [x] Docs-contract-drift
- [x] Security-boundary

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DEC-001 | Should current simulator visual-state proof use screenshots, recordings, or accessibility state? | Screenshots/recordings vs structured accessibility dump | Determines whether proof is machine-checkable and debuggable | Use accessibility state only; screenshots/recordings do not count as proof | Codex under user requirement | Plan lines 53-55, 187-188, 663-675, 846-896 | resolved |
| DEC-002 | Can Archive and Archive Cleanup keep snapshot-only paths? | Keep as exceptions vs migrate/delete | Could leave card truth split and stale-state bugs alive | Migrate active Archive and Archive Cleanup to shared stream-backed card state; delete production `ThreadCardHostSnapshotLoader` | Codex under user requirement | Plan lines 622-630, 714-716, 755-756, 790-793, 954-958 | resolved |
| DEC-003 | Can skipped proof, raw `:4500`, scripted UI debug, or fake fixtures satisfy live-update proof? | Allow as dev shortcuts vs reject from proof | Could let tests pass while app is stale | Reject them; emit blocked/fail reports instead of pass | Codex under user requirement | Plan lines 51-58, 1060-1078 | resolved |
| DEC-004 | How should relay upstream recovery affect an open Thread Detail? | Invisible upstream swap vs downstream close and Swift rehydrate | Could leave open thread stale while socket looks connected | Close downstream on successful recovery and rehydrate in Swift | Codex under user requirement | Plan lines 150-152, 653-660, 990-1002 | resolved |

## Pass History

### Pass 1 - 2026-06-01 01:45 UTC

- Mode: plan-readiness
- Scope: whole plan, Sections 0-10 as canonical execution contract; Appendix A treated as retained source history only.
- Baseline reviewed: current worktree plan and repo code paths named in the plan.
- Test/CI context accepted, if supplied: not supplied; no tests run for this plan-readiness audit.
- Agents/lenses run: two arch-step `explorer` agents for consistency slices; two fresh Composer 2.5 Fast consults; parent plan-audit synthesis using all required lenses.
- Code areas read: relay state/subscription/thread data, Swift stream table/store, Archive/Archive Cleanup, Thread Detail DTO/store/session, simulator UI proof, controlled fixture/matrix, Makefile, contract schema, README.
- Findings added: none current.
- Findings resolved: Composer/explorer notes were incorporated before this pass: Phase 1 dump wiring, Archive Cleanup decision, proof status vocabulary, raw/scripted proof rejection, Archive controlled scenario support, Section 8 blocking verification wording.
- Findings carried forward: none.
- Verdict: ready.
- Next audit focus: implementation-audit after code exists, especially Phase 1 `sim-ui-dump` and Phase 3 Archive/Cleanup stream migration.

### Pass 2 - 2026-06-01 06:04 UTC

- Mode: implementation-audit.
- Scope: full implementation against the plan, including final order-proof
  repairs after fresh Composer review.
- Baseline reviewed: current dirty worktree and changed behavior map.
- Test/CI context accepted: `rtk npm run contract:check` passed; `rtk npm run
  test:relay` passed with 86 tests; `rtk swift test --filter
  DockStoreTestsProjection` passed with 25 tests; `rtk make app-test
  SIM='iPhone 17'` passed; `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1 &&
  rtk make sim-ui-dump SIM='iPhone 17'` passed and wrote
  `/tmp/codex-client/sim-ui-dump-20260601T061107Z/sim-ui-dump.json`; final
  simulator matrix
  `/tmp/codex-client/sim-ui-controlled-matrix-final3-20260601T055358Z/controlled-simulator-matrix.json`
  passed 12/12 scenarios with max observed UI lag 1914 ms.
- Code areas read: relay state engine/subscriptions/store/sync audit, proof
  report contracts and schemas, controlled simulator fixture/matrix, simulator
  UI proof, current UI dump support, Swift Dock/Archive shared stream
  lifecycle, ThreadCardTable generation handling, Thread Detail recovery/buffer
  path, Dock projection ordering, deletion candidates, README/docs.
- Fresh consult context: Composer 2.5 Fast returned pass-with-notes with no
  blocking findings at
  `/tmp/fresh-consult/codex-dock-live-update-implementation-20260601T060601Z-GNhrn8/final.txt`.
  It confirmed the visible-order proof gap is closed by code and matrix gates.
- Blocking findings: none.
- Non-blocking findings added: IMP-001.
- Side-door review: production `ScriptedDockStreamClient`,
  `ScriptedThreadDetailSession`, `ThreadCardHostSnapshotLoader`, and
  `ThreadCardStreamSnapshotCollector` are deleted; raw app-server `:4500`
  cannot satisfy proof; scripted stream proof side doors cannot satisfy proof;
  passing proof requires relay-owned route evidence and matching proof run IDs.
- Drift review: proof reports are schema-checked by `rtk npm run
  contract:check`; simulator UI proof now retains visible order checks; Swift
  projection follows relay order and tie-breaks equal order keys by stable row
  ID.
- Final hardening note: `sim-ui-dump` now schema-validates copied blocked JSON
  artifacts before exiting nonzero, so failure evidence uses the same proof
  contract as pass evidence.
- Verdict: approve-with-notes.
