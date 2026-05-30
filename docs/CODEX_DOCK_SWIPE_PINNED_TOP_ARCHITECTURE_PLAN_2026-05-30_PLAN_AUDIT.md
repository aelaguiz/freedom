# Plan Audit Log

Plan: `docs/CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30.md`
Audit log: `docs/CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30_PLAN_AUDIT.md`
Current plan verdict: ready-for-user-review; implementation paused until user approval
Current implementation code-review verdict: stale after 2026-05-30 amendments; prior Composer 2.5 Fast pass-with-notes does not cover static order, native reorder, collapse, no Manage/Show-all, divider, or true-message Dock cards/order
Last reviewed: 2026-05-30
Scope: whole plan, implementation readiness, prior implementation review, and reopened amendment review

## Current Blocking Findings

None.

## Current Non-Blocking Findings

- Composer 2.5 Fast noted that `DockView.swift` had absorbed too much
  feature-specific swipe/manage UI. Follow-up split `DockSwipeActionRow` and
  `PinnedThreadsManageView` into `CodexDock/Features/Dock/DockPinnedViews.swift`.
- Composer 2.5 Fast noted that the simulator proof covers the scripted
  north-star path, not every optional pin surface such as search/filter
  narrowing, overflow, context menu, or accessibility-only pin. Unit tests cover
  projection and persistence for the non-simulator paths.
- Composer 2.5 Fast reported missing mockup PNGs, but parent spot-check found
  that note stale: `docs/mockups/codex-dock-swipe-pinned-top-2026-05-30/outputs/`
  contains generated PNG outputs.
- The first-pass implementation still contains now-rejected concepts in the
  dirty worktree, including activity-sorted pinned rows, Manage/overflow
  surfaces, and no native reorder/collapse/true-message card-order proof. That
  is implementation debt, not a plan blocker.
- The relay/client message-order path needs implementation diligence because
  raw `updatedAt` is still useful for freshness but must not remain the Dock
  row/card order key once true-message activity exists.

## Current Implementation Findings

The implementation finding below is historical. It does not clear the amended
scope because the amended scope did not exist when Composer reviewed the code.

Composer 2.5 Fast fresh review completed at
`/tmp/fresh-consult/codex-dock-swipe-pinned-review-20260530-kCPuWi` with:

- `VERDICT: pass-with-notes`
- `BLOCKING: none`
- `CONFIDENCE: high`
- Parent action taken: split pinned/swipe UI helpers out of `DockView.swift`
  and rerun simulator proof before final review closure.

## Relevant Code Coverage Ledger

| Area | Files/symbols read | Why relevant | Reader | Status |
| --- | --- | --- | --- | --- |
| Canonical owner path | `CodexDock/State/LocalThreadMetadataStore.swift`; `LocalThreadMetadata`, `LocalThreadMetadataKey`, `FileLocalThreadMetadataStore` | Pin state and cached display persistence owner | Codex | read |
| Canonical owner path | `CodexDock/State/DockSessionTable.swift`; `snapshot(hosts:localMetadata:now:)` | Correct insertion point for metadata-only pinned rows | Codex | read |
| Canonical owner path | `CodexDock/State/SessionRowProjector.swift`; `rows(from:)`, `makeRow(summary:)` | Live row projection and local metadata merge | Codex | read |
| Canonical owner path | `CodexDock/State/DockSessionProjection.swift`; `DockSessionProjectionProjector.project()` | Search/filter/lens split, body grouping, summary, facets, empty reasons | Codex | read |
| Store action path | `CodexDock/State/DockStore.swift`; `DockRowViewModel`, `DockRowStatusKind`, `setLabel`, `setRail`, `save(metadata:for:)`, `publishSnapshot()` | Row model, local metadata action pattern, save failure behavior | Codex | read |
| Dock UI path | `CodexDock/Features/Dock/DockView.swift`; `loadedContent`, `projectedContent`, `dockRow`, `rowActions`, refreshable root | Pinned section, swipe/context actions, first-pass Manage sheet now marked for deletion, refresh proof | Codex | read |
| Shared row UI | `CodexDock/Features/Dock/DockSharedViews.swift`; `DockRowView`, `DockRowViewModel.automationValue` | Pin visual/accessibility behavior and Archive leakage risk | Codex | read |
| Automation IDs | `CodexDock/Automation/AutomationID.swift`; `DockRowAction`, `AutomationID.Dock` | Stable UI-test handles for pin/unpin/Manage/section | Codex | read |
| Adjacent Archive path | `CodexDock/State/ArchiveSessionProjector.swift`; `CodexDock/Features/Archive/ArchiveView.swift` | Shared projector/view side door that must not become an accidental Archive feature | Codex | read |
| Scripted simulator proof | `CodexDock/State/ScriptedDockStreamClient.swift`; `CodexDock/Features/Dock/CodexDockBootstrapView.swift`; `CodexDockUITests/CodexDockAutomationSmokeTests.swift` | Deterministic simulator path for swipe/lens/refresh/relaunch proof | Codex | read |
| Tests and helpers | `CodexDockTests/DockStoreTestsProjection.swift`; `CodexDockTests/DockStoreTests.swift`; `CodexDockTests/DockStoreTestSupport.swift`; `CodexDockTests/ThreadDetailStoreTestSupport.swift`; `CodexDockTests/AutomationIDTests.swift` | Projection, persistence, helper constructor fallout, automation ID coverage | Codex | read |
| True-message owner | `CodexDock/Models/ThreadEvent.swift`; `ThreadEventVisibilityCategory`; `ThreadDetailMessageFilter`; `ThreadEventNormalizer` | Defines current Thread Detail default `Messages` predicate and event classification | Codex | read |
| Dock message mapper | `CodexDock/Models/SessionSummaryMapper.swift`; `latestMeaningfulSummary`; `isStoredMessageEvent`; `eventPrecedes` | Current duplicated Dock/list message predicate and preview derivation | Codex | read |
| Dock stream message path | `CodexDock/AppServer/DockStreamDTO.swift`; `CodexDock/State/DockSessionTable.swift`; `scripts/dock-relay-thread-summary-cache.mjs`; `scripts/dock-relay-session-table.mjs`; `scripts/dock-relay-thread-data.mjs` | Relay stream summary/activity path that currently uses raw `updatedAt` and generic summary fields | Codex | read |
| Message tests | `CodexDockTests/ThreadEventNormalizerTests.swift`; `CodexDockTests/ThreadListMappingTests.swift`; `scripts/dock-relay-phase5.test.mjs`; `scripts/dock-relay-state-parity.test.mjs` | Existing coverage proving Thread Detail filtering and relay summary warming partially exclude reasoning/tools | Codex | read |
| Local instructions | `AGENTS.md` user-provided repo instructions in prompt | Required command/test style and iPhone 17 simulator priority | Codex | read |
| Existing audit log | This audit log did not exist before this pass | Required repeat-audit baseline | Codex | read |

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
- [x] Conditional lenses: docs-contract drift and UI automation drift

## Ambiguity And Decision Ledger

| ID | Ambiguity/constraint question | Interpretations | Impact | Required decision | Decision owner | Plan carry-through evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| PLA-DEC-001 | Should `Pinned` mean user-owned pins or rate limits/limited data? | User-owned pins vs. system/rate-limit state | Changes product behavior and data model | Use user-owned local pin metadata; do not expose `Limited` | User | Section 0.2, 0.3, 0.5 and Section 5 | resolved |
| PLA-DEC-002 | Should pins be synced through relay/app-server? | Device-local vs. cross-device/server state | Changes protocols, secrets, and deployment | Device-local only for MVP | User/plan | Section 0.3, Section 1.4, Section 6.2 | resolved |
| PLA-DEC-003 | Should missing live thread data remove a pinned row? | Hide absent row vs. cached row vs. placeholder | Changes refresh/relaunch/offline UX | Cached local display first, then `Not loaded` placeholder | Plan with UX-spec carry-through | Section 0.4, Section 5.2, Section 5.3, Phase 1 | resolved |
| PLA-DEC-004 | Should Manage/overflow be deferred? | Inline cap only vs. real management sheet | Changes user control and overflow behavior | Superseded by PLA-DEC-006; no Manage, no overflow cap, no Show-all | Plan consistency pass, later user amendment | Section 5.3 and Phase 2 | superseded |
| PLA-DEC-005 | Should Archive inherit pin UI from shared row code? | Global shared row pin affordance vs. Dock-only opt-in | Could create accidental Archive feature | Keep Archive pin section/actions out; make shared visual opt-in from Dock | Plan audit | Section 3.2 adjacent surfaces and Section 6 call-site audit | resolved |
| PLA-DEC-006 | Should first-pass Manage/overflow survive the user amendment? | Keep cap/Manage vs. render all pins inline and unpin by swipe | Changes UI, tests, automation IDs, and implementation deletion list | Delete Manage/Show-all/cap. Reorder by native long-press row movement and collapse by tapping `Pinned` | User | TL;DR, Sections 0, 5, 6, 7 | resolved |
| PLA-DEC-007 | What should Dock row/card "message" mean? | Generic latest summary/raw updatedAt vs. Thread Detail default messages | Changes preview, sort order, relay DTOs, and tests | Use the same true-message predicate as `ThreadDetailMessageFilter.default`: `.message` visibility and user/agent message kind | User | TL;DR, Sections 0, 3, 5, 6, 7, 8 | resolved |
| PLA-DEC-008 | Can the client sort by true-message activity without relay help? | Client derives from ThreadDTO turns vs. relay provides message summary/activity | Affects stream protocol and performance | Add backward-compatible read-only relay fields if needed; do not sort by raw tool `updatedAt` when message activity is known | Plan/code research | Sections 1.2, 3.1, 5.2, 5.3, 6.1 | resolved |

## Pass History

### Pass 1 - 2026-05-30

- Mode: plan-readiness
- Scope: whole plan before implementation
- Baseline reviewed: `docs/CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30.md` after arch-step consistency pass
- Test/CI context accepted, if supplied: none; no tests run in plan-readiness audit
- Agents/lenses run: parent audit only; native subagents were not used for this pass because the available multi-agent tool requires explicit user permission for delegation. The prior arch consistency pass had already used two explorer reviews, and this audit re-read the relevant repo owner path directly.
- Code areas read: metadata store, session table, row projector, Dock projection, Dock store, Dock UI, shared row view, Archive adjacent path, automation IDs, scripted stream client, UI tests, projection/store/test helpers
- Findings added: none current
- Findings resolved during audit:
  - Clarified `ArchiveView`/`DockRowView` side door so shared pin visuals are Dock opt-in and Archive does not accidentally gain pin actions or a pinned section.
  - Added the missing `DockRowStatusKind: Codable` requirement because cached pinned display snapshots store status.
- Findings carried forward: none
- Verdict: ready
- Next audit focus: implementation-audit after code is written

### Pass 2 - 2026-05-30

- Mode: reopened-amendment-readiness
- Scope: static pin order, native long-press reorder, collapse, no cap/no
  Manage/no Show-all, divider, and true-message Dock card/order amendment
- Baseline reviewed:
  `docs/CODEX_DOCK_SWIPE_PINNED_TOP_ARCHITECTURE_PLAN_2026-05-30.md` after
  amendment edits
- Test/CI context accepted, if supplied: prior unit/simulator proof remains
  historical evidence only; no new implementation checks were run because this
  pass is planning-only
- Code areas read: Thread Detail filter and normalizer, session summary mapper,
  Dock stream DTO/table, relay session table, relay summary cache, relay
  thread-data aggregation, Dock projection/order, current plan and prior audit
- External/current SDK research:
  - Installed iOS 26 SwiftUI interface exposes `EditActions.move`,
    `List(... editActions:)`, and `DynamicViewContent.onMove`.
  - Apple SwiftUI documentation and HIG guidance were used as the grounding for
    native list movement, drag/drop, and section/separator treatment.
- Findings added:
  - The old plan and implementation-review verdict were stale because they did
    not cover static user pin order, native reorder, collapse, no management
    surface, divider separation, or true-message Dock card/order behavior.
  - `SessionSummaryMapper` already tries to derive a latest message from turns,
    but it owns a private predicate; the plan now requires a shared Swift
    helper used by both Thread Detail and Dock.
  - Relay stream rows currently need message-derived activity, not just raw
    `updatedAt`, for correct Dock ordering.
- Findings resolved during audit:
  - Added true-message centralization to TL;DR, North Star, constraints,
    target architecture, call-site inventory, phase plan, and verification.
  - Replaced the earlier Manage/overflow target with no cap, no Manage,
    swipe-to-unpin, native reorder, collapse, and divider requirements.
  - Marked prior simulator proof and code-review proof as stale for the final
    target, while preserving them as evidence for the older swipe/lens slice.
- Findings carried forward: none blocking
- Verdict: ready-for-user-review; implementation should not resume until the
  user accepts this amended plan
- Next audit focus: implementation-audit after code is updated to match this
  amended plan

## Proper-Audit Checklist Status

- Plan artifact resolved: yes
- Audit log path resolved and written: yes
- Local instructions and repo verification rules read: yes
- North Star and done-state requirements identified: yes
- Real ambiguities identified and carried through: yes
- Relevant code coverage complete for readiness: yes
- Native subagent policy recorded: yes, not used because available tool requires explicit user permission
- Architecture quality, proof, drift, deletion, and side-door lenses run: yes
- Remaining blockers: none
- What was not checked: physical device behavior, actual simulator execution of
  the amended flow, and fresh code-review verdicts; those belong after
  implementation.
