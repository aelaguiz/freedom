# Plan Audit Log

Plan: `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md`
Audit log: `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31_PLAN_AUDIT.md`
Current plan verdict: ready-to-implement
Current implementation code-review verdict: approve
Last reviewed: 2026-05-31 16:43:00 CDT
Scope: whole plan and current worktree implementation

## Current Blocking Findings

None open against the plan document or current implementation.

The implemented code now satisfies the plan's zero-side-door pattern: relay
projection owns card truth, Swift renders card streams, deleted app-facing
oracle routes are unsupported, and tests prove the client-visible stream paths
rather than alternate raw/oracle surfaces.

## Current Implementation Findings

None open.

## Thermo-Nuclear Code Quality Review

Verdict: approve.

- The diff deletes much more complexity than it adds: `69 files changed`,
  `1009 insertions`, `16978 deletions`.
- The implementation removes obsolete routes, scripts, oracle tests, and
  client wrappers instead of guarding them with a brittle linter.
- The core "code-judo" move is the canonical projection fold in
  `scripts/dock-relay-thread-data.mjs`, with stream emission restricted to
  `dock/*` and `archive/*`.
- Pre-existing large files remain large, but the largest side-door scripts were
  deleted or shrunk. No modified file crossed from under 1000 lines to over
  1000 lines.
- The remaining DEBUG scripted stream and sync-audit harness are render/client
  path tools only; they cannot prove production card truth.

## Resolved Findings

- [x] PLA-001 - Bounded latest-turn scan leaves a known recency drift gap
  - Lens: outcome North Star, canonical owner and SSOT, proof and phase exit
  - Original issue: the old plan limited newest-turn reads to live/top-N
    candidates and accepted a residual misranking gap.
  - Resolution: the plan now replaces bounded scan acceptance with the
    honest-freshness invariant: an emitted set containing unproven cards cannot
    be fresh or complete.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:56`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:74`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:82`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:219`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:239`
  - Status: resolved

- [x] PLA-002 - HTTP diagnostic side doors with card/state data are not classified
  - Lens: deletion and side-door closure, drift-proof coupling
  - Original issue: `/statez`, `/syncz`, `/dbz`, `/explainz/thread/{threadID}`,
    `/debugz/sessions`, `/subscriptionsz`, `/tracesz/*`, `/selftestz`, and
    `/bundlez` were not explicitly classified.
  - Resolution: the plan has a normative route-scope table and Phase 5
    delete/strip work for HTTP diagnostics. Card/state HTTP diagnostics
    cannot be card proof.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:156`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:185`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:188`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:191`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:192`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:437`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:449`
  - Status: resolved

- [x] PLA-003 - Audit/probe scripts remain able to use old oracle routes
  - Lens: deletion and side-door closure, proof and phase exit
  - Original issue: audit/probe scripts could still use `relay/state/snapshot`,
    SQLite, `thread/list`, `thread/search`, and related oracle surfaces.
  - Resolution: Phase 5 explicitly rewrites or deletes old oracle/probe scripts,
    and Phase 6 restricts proof to card-stream observation with raw data only as
    fake upstream input behind the relay.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:462`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:467`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:483`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:498`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:504`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:506`
  - Status: resolved

- [x] PLA-004 - `thread/read` and `thread/turns/list` are kept for detail but not explicitly banned as Dock proof
  - Lens: caller, invariant, and state model; drift-proof coupling
  - Original issue: Thread Detail routes are valid routes but could be reused as
    Dock/Archive proof.
  - Resolution: the route table scopes `thread/read`, `thread/turns/list`, and
    `thread/resume` to detail after card selection, and Phase 5 repeats the test
    proof ban.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:171`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:172`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:173`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:479`
  - Status: resolved

- [x] PLA-005 - Freshness must carry uncertainty
  - Lens: elegance and code-judo
  - Original issue: the old plan accepted an uncertain ordering state as a
    residual gap.
  - Resolution: the plan binds unproven activity to stream `complete=false`,
    non-fresh host freshness, and card `partial`/`unknown` completeness.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:74`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:76`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:77`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:79`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:362`
  - Status: resolved

- [x] PLA-006 - Archive/unarchive can remain a second card writer
  - Lens: canonical owner and SSOT, deletion and side-door closure
  - Added by model consensus: `applyArchiveMutation` can directly write
    `dockOrderKey(0, threadID)` and direct freshness status.
  - Resolution: the route table and Phase 2 make archive/unarchive command
    routes projection inputs only and explicitly remove direct order/freshness
    writes.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:174`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:175`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:320`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:326`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:327`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:329`
  - Status: resolved

- [x] PLA-007 - Live-only rows can stay missing from the candidate set
  - Lens: outcome North Star, caller/invariant/state model
  - Added by model consensus: live status overlay can update rows already present
    while failing to enumerate live threads absent from `thread/list`.
  - Resolution: candidate enumeration and Phase 1 require live-only row
    enumeration as architecture, not just a test.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:87`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:228`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:233`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:293`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:303`
  - Status: resolved

- [x] PLA-008 - `thread_field_provenance` can remain decorative drift-control machinery
  - Lens: drift-proof coupling, simplicity
  - Added by model consensus: a dead provenance table makes the system look
    safer than it is.
  - Resolution: the plan chooses explicit card-row proof fields and deletes the
    unused table. It does not leave a choice to keep it decorative.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:209`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:247`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:250`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:580`
  - Status: resolved

- [x] PLA-009 - Fixtures, previews, and scripted streams can preserve fake freshness
  - Lens: proof and phase exit, side-door closure
  - Added by model consensus: fake/scripted streams can train tests on false
    fresh/complete cards.
  - Resolution: source disposition, Phase 5, and Phase 6 classify fixtures as
    rendering/reducer only and ban them as production freshness/order proof.
  - Evidence:
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:215`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:476`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:512`
    - `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md:514`
  - Status: resolved

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Plan artifact | `docs/CODEX_DOCK_DATA_CONTRACT_SINGLE_SOURCE_IMPLEMENTATION_PLAN_2026-05-31.md` | Review target | Codex, Model A, Model B | read |
| Source audit | `docs/CODEX_DOCK_RELAY_DATA_CONTRACT_AND_LEASE_DRIFT_AUDIT_2026-05-31.md` | Full source/route/drift map | Codex, Model A | read |
| Relay route surface | `scripts/dock-relay.mjs` | JSON-RPC and HTTP side-door inventory | Codex, Model A, Model B | read |
| Relay projection/store | `scripts/dock-relay-state-engine.mjs`, `scripts/dock-relay-state-views.mjs`, `scripts/dock-relay-state-store.mjs`, `scripts/dock-relay-thread-data.mjs` | Projection ownership, archive mutation, live-only enumeration, proof storage | Codex, Model A, Model B | read |
| Contract schema | `contract/dock/dock-thread-card.schema.json` | Existing freshness/completeness fields | Model A, Model B | read |
| Audit/probe scripts | `scripts/dock-relay-sync-audit.mjs`, `scripts/dock-relay-state-parity.mjs`, `scripts/dock-relay-thread-fidelity.mjs`, `scripts/dock-relay-probe.mjs` | Test/proof side-door inventory | Codex, Model B | grep/read |
| Swift card paths | `CodexDock/AppServer/**`, `CodexDock/State/**`, `CodexDockTests/**` | Client render-only boundary and fixture side doors | Codex, Model A, Model B | grep/read |

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
- [x] Docs-contract-drift conditional lens

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Decision | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- |
| DEC-001 | Is a bounded scan with a known residual misranking gap acceptable? | No. A stream cannot be fresh/complete if emitted ordering is unproven. | Plan lines 56-83, 219-260 | closed |
| DEC-002 | Are HTTP state diagnostics allowed to expose card/state truth? | No. Card/state HTTP diagnostics are deleted or stripped and cannot be proof. | Plan lines 156-194, 437-461 | closed |
| DEC-003 | Can archive/unarchive mutate stored card order/freshness directly? | No. They are command routes and projection inputs only. | Plan lines 174-175, 320-335 | closed |
| DEC-004 | Should `thread_field_provenance` remain as an unused table? | No. The plan deletes it and uses explicit card-row proof fields. | Plan lines 209, 247-251, 580 | closed |
| DEC-005 | Can fixtures/previews/scripted streams prove freshness/order? | No. They are render/reducer fixtures only. | Plan lines 215, 512-515 | closed |

## Pass History

### Pass 1 - 2026-05-31 14:14:02 CDT

- Mode: plan-readiness
- Scope: whole plan
- Baseline reviewed: current working tree
- Test/CI context accepted, if supplied: not supplied
- Agents/lenses run: local plan-audit lenses
- Code areas read: plan, relay route surface, route/proof grep, selected
  audit/probe script excerpts
- Findings added: PLA-001, PLA-002, PLA-003, PLA-004, PLA-005
- Findings resolved: none
- Findings carried forward: all
- Verdict: not-ready

### Pass 2 - 2026-05-31 14:47:00 CDT

- Mode: model-consensus repair review
- Scope: whole plan, zero-side-door pattern
- Agents/lenses run:
  - Model A: `claude-opus-4-8`, effort `max`
  - Model B: `gpt-5.5`, effort `high`
  - Round 2 convergence back through Model B
- Consensus artifact:
  `.arch_skill/model-consensus/codex-dock-zero-side-door-pattern-20260531T191645Z/`
- Findings added: PLA-006, PLA-007, PLA-008, PLA-009
- Findings resolved: PLA-001 through PLA-009
- Verdict: ready-to-implement

### Pass 3 - 2026-05-31 16:43:00 CDT

- Mode: implementation-audit
- Scope: whole plan and current worktree implementation
- Baseline reviewed: current worktree diff against `HEAD`
- Test/CI context accepted:
  - `git diff --check`
  - `rtk npm run contract:check`
  - `rtk npm run test:relay` (`61/61`)
  - `rtk swift test --filter AppServerClientTests`
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter DockStoreStreamTests`
  - `rtk swift test --filter ArchiveDataEngineTests`
  - `rtk swift test --filter ArchiveCleanupStoreTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk make app-test SIM='iPhone 17'` after focused rerun of the known
    timing-sensitive voice test
- Fresh consult:
  - `Composer 2.5 Fast` via `agent`, run directory
    `/tmp/fresh-consult/codex-dock-single-source-implementation-final-rerun-20260531Tkmsh6X`
  - Verdict: `pass-with-notes`
  - Blocking: none
  - Summary: no reachable production side doors found; notes were limited to
    render-only Swift fixture indirection, possible live-turn reconcile latency,
    and large operator harness readability.
- Native subagents:
  - Attempted read-only relay and Swift audit explorers.
  - Both errored because the account hit a usage limit. Coverage was completed
    locally plus the fresh consult; this was not a code coverage blocker.
- Code areas read:
  - Relay route/HTTP surface:
    `scripts/dock-relay.mjs`,
    `scripts/dock-relay-observability-contract.mjs`,
    `scripts/dock-relay-observability.test.mjs`
  - Relay projection/store:
    `scripts/dock-relay-thread-data.mjs`,
    `scripts/dock-relay-state-engine.mjs`,
    `scripts/dock-relay-state-store.mjs`,
    `scripts/dock-relay-state-views.mjs`,
    `scripts/dock-relay-state-ingest.mjs`
  - Client card paths:
    `CodexDock/AppServer/AppServerMethods.swift`,
    `CodexDock/AppServer/DockThreadCardDTO.swift`,
    `CodexDock/State/ThreadCardRowProjector.swift`,
    `CodexDock/State/DockCardProjection.swift`,
    `CodexDock/State/ThreadCardTable.swift`,
    `CodexDock/State/ThreadCardStreamSnapshotCollector.swift`,
    `CodexDock/State/LocalThreadMetadataStore.swift`,
    `CodexDock/State/ScriptedDockStreamClient.swift`,
    `CodexDock/State/ArchiveThreadCardProjector.swift`,
    `CodexDock/Archive/ArchiveDataEngine.swift`,
    `CodexDock/Archive/ArchiveCleanupDataEngine.swift`
  - Contract/proof surfaces:
    `contract/dock/dock-thread-card.schema.json`,
    `contract/dock/fixtures/*.json`,
    `scripts/check-dock-thread-card-contract.mjs`,
    `scripts/dock-relay-card-contract.test.mjs`,
    `package.json`
  - Docs/commands:
    `README.md`, `Makefile`, this plan, this audit log, and the relay drift
    audit.
- Findings added: none
- Findings resolved:
  - Follow-up proof gap: live-only thread absent from raw `thread/list` now has
    a real `dock/subscribe` relay test.
  - Follow-up Swift fallback gap: Archive and cleanup no longer fall back to
    timestamp sorting when `orderKey` is missing.
- Findings carried forward: none
- Verdict: approve
- Next audit focus: none required before commit.
