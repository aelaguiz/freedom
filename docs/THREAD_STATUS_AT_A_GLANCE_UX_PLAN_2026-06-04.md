---
title: "Codex Dock - Thread Status At A Glance - Architecture Plan"
date: 2026-06-04
status: active
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: []
doc_type: architectural_change
related:
  - ./CODEX_DOCK_THREAD_STATE_UX_REFERENCE_2026-06-04.md
  - ./CODEX_DOCK_THREAD_TYPES_AND_STATES_REFERENCE_2026-05-31.md
  - ./mockups/codex-dock-thread-state-ux-2026-06-04/README.md
  - https://www.nngroup.com/articles/visibility-system-status/
  - https://www.nngroup.com/articles/response-times-3-important-limits/
  - https://www.nngroup.com/articles/progress-indicators/
  - https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
  - https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html
  - https://developer.apple.com/design/human-interface-guidelines/feedback
  - https://developer.apple.com/design/human-interface-guidelines/progress-indicators/
  - https://developer.atlassian.com/platform/forge/ui-kit/components/lozenge/
---

# TL;DR

## Outcome

Codex Dock will show thread status in human terms at a glance:

- Dock row badge: `Codex is working`, `Needs answer`, `Needs approval`, or
  `Error`.
- Thread Detail header badge: `Codex is working`, `Your turn · Ready`,
  `Your turn · Needs answer`, `Your turn · Needs approval`, or `Error`.
- Ready Dock rows stay quiet. They do not get loud badges.

## Problem

The app currently exposes source-ish labels such as `Running`, `Needs input`,
and `Idle`. `Running` is vague because it does not answer the user's real
question: "Is Codex doing something, is it my turn, or is something wrong?"

## Approach

Keep the existing Codex/relay/Swift state contract. Change only the user-facing
projection layer that already owns Dock row badges, filters, summaries, and
Thread Detail header status. Do not add new relay fields, fake activity states,
duplicate banners, or broad health/error surfaces.

## Plan

1. Align the current reference and mock package to this shippable scope: row
   badges and Thread Detail header badges only.
2. Add the missing Swift vocabulary boundary in `DockRowStatusKind`.
3. Point Thread Detail at a detail-specific status label instead of the Dock row
   badge label.
4. Update focused tests and verify on the simulator.

## Non-negotiables

- `idle` means ready for the next user turn. It does not mean
  `waitingOnUserInput`.
- Active wait flags are the only user-action blockers in the current contract:
  `waitingOnUserInput` and `waitingOnApproval`.
- Do not invent states like `Running tests`, `Editing`, `Reading repo`,
  `Thinking`, host offline, network error, reconnecting, or stale stream.
- Do not add a generic `Problem` bucket, header, section, filter, or banner.
- Do not add duplicate status banners below the Thread Detail header badge.
- Do not change relay DTOs unless implementation proves the current contract
  cannot express this first slice. Current research says it can.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-06-04
external_research_grounding: done 2026-06-04
deep_dive_pass_2: done 2026-06-04
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:e6a9dd94afae95ca3b88ef11278bc2fdfe957508fb4a7e0df94a7c761b0dd286",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-04T16:02:35Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:e00f46cd0acd6e2bdac760e28d71763cdcb66fd7315ea787f67e3e6304a042cd",
      "completed_at": "2026-06-04T16:02:55Z",
      "doc_hash_after": "sha256:c97f4577adc06be1c963a4f0192ffbb6b4e2e26407509515e442e3cdbb93e57c"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-04T16:03:05Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:c97f4577adc06be1c963a4f0192ffbb6b4e2e26407509515e442e3cdbb93e57c",
      "completed_at": "2026-06-04T16:03:31Z",
      "doc_hash_after": "sha256:3f66359c6c7eefd69a589887fdeb56a92999fcb2775ec821f8f78c4244eed5e8"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-04T16:03:38Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:3f66359c6c7eefd69a589887fdeb56a92999fcb2775ec821f8f78c4244eed5e8",
      "completed_at": "2026-06-04T16:03:54Z",
      "doc_hash_after": "sha256:35cbee428e7d5b1a4658f4312062452ef8cc28141fee97c68f7934e84ed99909"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-04T16:04:06Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:35cbee428e7d5b1a4658f4312062452ef8cc28141fee97c68f7934e84ed99909",
      "completed_at": "2026-06-04T16:04:21Z",
      "doc_hash_after": "sha256:12e7ad1ca751979933bd4365a5a6fd2a1388fc81eef45951dcf552bf1ec651ff"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-04T16:04:31Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:12e7ad1ca751979933bd4365a5a6fd2a1388fc81eef45951dcf552bf1ec651ff",
      "completed_at": "2026-06-04T16:04:57Z",
      "doc_hash_after": "sha256:b630ad4ce6f6dbc736f3a2095ff93400fd15f232c9f9828638755f9b3d077124"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

A user looking at the Dock or a Thread Detail header should immediately know
one of three things:

- Codex is working.
- It is the user's turn.
- This thread is in raw thread error.

The claim is false if the shipped UI still shows the main status as `Running`,
if `idle` is shown as generic `Idle`, if Thread Detail shows both a status badge
and a duplicate status banner, or if this slice adds unrelated network/offline
health UI.

## 0.2 In scope

- Rename user-facing status labels that come from `DockRowStatusKind`.
- Keep Dock row status as a small badge on the thread row.
- Keep ready/idle Dock rows quiet by leaving their visible row badge hidden.
- Make Thread Detail header show the status badge for both active and ready
  states.
- Use these exact first-slice labels:

| Raw Swift row status | Dock row badge | Thread Detail header badge | Filter/summary label |
| --- | --- | --- | --- |
| `running` | `Codex is working` | `Codex is working` | `Codex is working` |
| `needsInput` | `Needs answer` | `Your turn · Needs answer` | `Needs answer` |
| `needsApproval` | `Needs approval` | `Your turn · Needs approval` | `Needs approval` |
| `idle` | none | `Your turn · Ready` | `Ready` |
| `error` | `Error` | `Error` | `Error` |
| `dormant` | none | none | `Saved` |
| `unknown` | none | none | `Unknown` |

- Keep raw labels available as enum cases, debug values, JSON values, tests, and
  state references.
- Update the canonical UX reference and deterministic mock package if they still
  imply a new Dock section, exact request subtype labels, or duplicate banners
  in this first implementation slice.

## 0.3 Out of scope

- New Dock top-level sections such as a structural `Your turn` group.
- New tabs, global headers, watched-thread surfaces, notifications, or Live
  Activities.
- Host offline, host health, network error, reconnecting, stale stream, or
  relay-health redesign.
- A generic `Problem` state, problem section, problem filter, or problem banner.
- Detailed error recovery UI beyond a small `Error` badge on the affected
  thread or Thread Detail header.
- Exact Dock-row request subtype copy such as `Review command`, `Review files`,
  or `Grant permission`. The current Dock card DTO does not carry that detail.
  Exact request cards remain inside Thread Detail where the request object
  already exists.
- Relay contract changes, app-server protocol changes, persistence changes,
  telemetry events, or generated Xcode project changes.

## 0.4 Definition of done (acceptance evidence)

- The plan audit for this file says the scope is fully specified and not wider
  than this north star.
- Arch-step auto-plan receipts show research, deep-dive pass 1, deep-dive pass
  2, phase-plan, and consistency-pass completed.
- `DockRowStatusKind` produces the exact labels in Section 0.2.
- Thread Detail header status uses a detail-specific label and shows
  `Your turn · Ready` for `idle`.
- Dock row badges still hide `idle`, `dormant`, and `unknown`.
- The UX reference and mock package do not contradict the shipped scope.
- Focused Swift tests pass.
- The app builds and launches on the `iPhone 17` simulator through the Makefile.
- A strict review finds no oversized architecture, parallel state truth, or
  scope creep.
- Commit and push are completed after verification.

## 0.5 Key invariants (fix immediately if violated)

- Source truth remains raw Codex state projected through the relay and Swift
  `DockRowStatusKind`.
- User-facing strings are projection labels, not new raw states.
- `idle` is the normal full-permissions completion path.
- A ready thread in Dock should not look urgent.
- Thread Detail gets one status surface in the header badge.
- Accessibility must not rely on color alone; the visible text carries the
  status meaning.
- No fallback labels or silent unknown mapping are added beyond the existing
  explicit `unknown` state.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Human meaning: labels must answer "who has the turn?" before exposing raw
   implementation terms.
2. Contract fidelity: labels must map only from real supported Codex/Dock
   states.
3. Scope control: use the existing badges and header field; do not create new
   layout or status systems.
4. Quiet default: the most common ready state should be clear in Thread Detail
   but calm in the Dock.
5. Testability: the vocabulary should be unit-testable without simulator-only
   proof.

## 1.2 Constraints

- `DockThreadCardDTO` currently carries coarse status only. It does not carry a
  pending request kind.
- `ThreadDetailHeader.statusLabel` currently uses `row.status.visibleBadgeLabel`.
  That is too narrow because `idle` has no Dock badge but should have a Thread
  Detail header label.
- Dock filter and summary text use `DockRowStatusKind.label`.
- UI changes are Swift-only unless the implementation exposes an actual missing
  contract. Current source research does not.
- Mobile app verification must use the Makefile target, not raw `xcodebuild`.

## 1.3 Architectural principles (rules we will enforce)

- One vocabulary owner: `DockRowStatusKind` owns human status labels for Dock
  and Thread Detail.
- Separate row urgency from detail status: Dock visible badges and Thread Detail
  header labels are different projections of the same enum.
- Keep raw values raw: enum case names and DTO case names do not become
  marketing or UX copy.
- No duplicate UI truth: do not add a second banner that repeats the header
  status.
- No relay change for string polish: relay maps raw state to normalized status;
  Swift owns local presentation language.

## 1.4 Known tradeoffs (explicit)

- The Dock row for `idle` remains unbadged. The tradeoff is intentional:
  at-a-glance Dock scanning should reserve badges for active, action-needed, or
  error states.
- `Needs approval` stays coarse in Dock. The tradeoff avoids adding relay DTO
  fields before the UX actually needs exact request kind outside Thread Detail.
- `Your turn · Ready` uses the same middle-dot separator already used elsewhere
  in the app for compact UI labels, and shipped Swift strings should be exact
  and testable.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Codex source state is coarser than the UI currently implies:

- raw app-server thread status: `notLoaded`, `idle`, `systemError`, or
  `active { activeFlags }`.
- active flags: `waitingOnApproval`, `waitingOnUserInput`.
- relay normalized Dock status: `running`, `needsApproval`, `needsInput`,
  `idle`, `error`, `dormant`, or `unknown`.
- Swift row status: `DockRowStatusKind` with the same normalized cases.

Swift labels today:

- `running` -> `Running`
- `needsInput` -> `Needs input`
- `needsApproval` -> `Needs approval`
- `idle` -> `Idle`
- `dormant` -> `Not loaded`

## 2.2 What's broken / missing (concrete)

- `Running` is technically true but not clear enough. It does not say whether
  Codex is working independently or waiting for the user.
- `Idle` reads like a machine status, not a next-action state. For the common
  full-permissions path, the human meaning is "your turn; ready for the next
  prompt."
- Thread Detail reuses the Dock row badge label, so it cannot show a ready
  header state without making ready Dock rows noisy.
- Existing references and mocks risk over-scoping this first implementation if
  they imply new Dock sections or exact request labels not available in
  `DockThreadCardDTO`.

## 2.3 Constraints implied by the problem

- The fix belongs in Swift presentation projection, not relay state derivation.
- Thread Detail needs a label separate from Dock row badge visibility.
- Tests should pin the exact vocabulary so the UI does not drift back to raw
  words.
- Documentation and mocks must describe the first shippable slice, not a larger
  future design.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

Research pass evidence:
- Local source and external anchor check: 2026-06-04.
- External anchors are being used only to shape presentation principles. They
  do not override Codex source state or add new app states.

- Nielsen Norman Group, "Visibility of System Status": the useful product
  principle is that systems should communicate current state so users know what
  to do next. This supports `Codex is working` and `Your turn` over raw labels.
- Nielsen Norman Group, "Response Times: The 3 Important Limits": users need
  feedback when work is taking time. This supports visible active work feedback,
  but not invented sub-states.
- Nielsen Norman Group, "Progress Indicators Make a Slow System Less
  Insufferable": progress indicators reduce uncertainty. This supports a calm
  `Codex is working` badge while an active turn is open.
- W3C WCAG 2.2, Understanding 1.4.1 Use of Color: color must not be the only
  carrier of meaning. This supports text badges, not color-only dots.
- W3C WCAG 2.2, Understanding 4.1.3 Status Messages: status changes that do not
  move focus should still be programmatically understandable. This supports
  keeping status text accessible through the existing header and row labels.
- Atlassian Forge UI Kit Lozenge: lozenges are short textual status indicators
  for quick recognition. This supports short badges and argues against long
  status prose inside row chips.
- Apple Human Interface Guidelines feedback and progress-indicator pages are
  platform references. The fetched pages require JavaScript, so this plan uses
  them only as general platform anchors and does not derive specific text claims
  from the fetched content.

## 3.2 Internal ground truth (code as spec)

- `CodexDock/Dock/DockModels.swift` defines `DockRowStatusKind`, `label`, and
  `visibleBadgeLabel`.
- `CodexDock/State/ThreadCardRowProjector.swift` maps
  `DockThreadCardStatus` into `DockRowStatusKind`.
- `CodexDock/AppServer/DockThreadCardDTO.swift` defines the generated
  `DockThreadCardStatus` cases.
- `scripts/dock-relay-state-views.mjs` maps raw app-server state and active
  flags to normalized Dock statuses.
- `CodexDock/State/ThreadDetailStore.swift` builds `ThreadDetailHeader` and
  currently sets `statusLabel` from `row.status.visibleBadgeLabel`.
- `CodexDock/Features/Session/SessionDetailView.swift` renders
  `header.statusLabel` as the existing Thread Detail status pill.
- `CodexDock/Features/Dock/DockSharedViews.swift` renders
  `row.status.visibleBadgeLabel` as the existing Dock row status badge.
- `CodexDock/State/DockCardProjection.swift` uses `DockRowStatusKind.label` in
  status summary text.
- `CodexDock/Features/Dock/DockFilterSurfaceView.swift` uses the status label
  for filter options.
- `CodexDockTests/DockStoreTests.swift` and
  `CodexDockTests/ThreadDetailHeaderTests.swift` already pin status vocabulary
  and header behavior.

Canonical owner path:
- `CodexDock/Dock/DockModels.swift` owns the status vocabulary because it is the
  shared point used by Dock badges, filters, summaries, and Thread Detail
  header construction.

Adjacent surfaces intentionally excluded:
- `scripts/dock-relay-state-views.mjs` stays as raw-to-normalized mapping.
- `CodexDock/AppServer/DockThreadCardDTO.swift` stays as generated contract.
- Host health and stream freshness stay on their existing surfaces.

Compatibility posture:
- Preserve the existing relay and DTO contract. This is a presentation-language
  cutover inside Swift only.

Behavior-preservation signals:
- `rtk swift test --filter DockStoreTests` protects Dock vocabulary.
- `rtk swift test --filter ThreadDetailStoreTests` protects Thread Detail
  header projection.

## 3.3 Decision gaps that must be resolved before implementation

None. The first slice is explicitly row-badge and Thread Detail header label
work only. Relay contract changes, new Dock sections, host/network health, and
exact request subtype labels are excluded.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `scripts/dock-relay-state-views.mjs`: raw-to-normalized status mapping.
- `CodexDock/AppServer/DockThreadCardDTO.swift`: generated status DTO.
- `CodexDock/State/ThreadCardRowProjector.swift`: DTO-to-row projection.
- `CodexDock/Dock/DockModels.swift`: row status enum and user-facing labels.
- `CodexDock/Features/Dock/DockSharedViews.swift`: Dock row badge rendering.
- `CodexDock/State/ThreadDetailStore.swift`: detail header model creation.
- `CodexDock/Features/Session/SessionDetailView.swift`: detail header pill
  rendering.
- `CodexDock/State/DockCardProjection.swift`: projection summary labels.
- `CodexDock/Features/Dock/DockFilterSurfaceView.swift`: filter option labels.
- `docs/CODEX_DOCK_THREAD_STATE_UX_REFERENCE_2026-06-04.md`: product UX
  reference.
- `docs/mockups/codex-dock-thread-state-ux-2026-06-04/`: deterministic mocks.

## 4.2 Control paths (runtime)

```text
app-server Thread.status
  -> relay normalizedStatus(...)
  -> DockThreadCardDTO.status
  -> ThreadCardRowProjector.status(...)
  -> DockRowStatusKind
  -> Dock row badge / filters / summary / Thread Detail header
```

Current problem path:

```text
ThreadDetailHeader(row:)
  -> row.status.visibleBadgeLabel
  -> nil for idle
```

That makes sense for Dock row urgency, but not for Thread Detail status.

## 4.3 Object model + key abstractions

- `DockThreadCardStatus`: protocol/DTO status.
- `DockRowStatusKind`: Swift normalized row status.
- `DockRowStatusKind.label`: general visible label for filters and summaries.
- `DockRowStatusKind.visibleBadgeLabel`: Dock row badge label when the row
  should be visibly badged.
- `ThreadDetailHeader.statusLabel`: optional header pill text.

## 4.4 Observability + failure behavior today

- Thread-level raw error becomes `DockRowStatusKind.error`.
- Host health and stream freshness are separate surfaces. This plan does not
  change them.
- Unknown status remains `unknown`; it has no visible badge today.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Dock row examples:

```text
Implement transcript pipeline                         Codex is working
Mac Studio - codex-client - main

Review renamed thread sync                            Needs approval
Mac Studio - codex-client - main

Thread status doc cleanup
Mac Studio - codex-client - main
```

Thread Detail header examples:

```text
[Mac Studio] [Live] [Codex is working]
[Mac Studio] [Live] [Your turn · Ready]
[Mac Studio] [Live] [Your turn · Needs approval]
[Mac Studio] [Live] [Error]
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

The same Swift files remain the owners. No new modules are added.

Documentation and mock artifacts are aligned with the shipped scope:

- UX reference says Dock row status is a badge, not a new Dock section.
- Mock package shows row-level status badges and Thread Detail header badges.
- Exact request subtype copy remains documented as a Thread Detail request-card
  concern, not a Dock row status claim.

## 5.2 Control paths (future)

```text
Dock row:
DockRowStatusKind.visibleBadgeLabel
  -> running / needsInput / needsApproval / error badges only

Thread Detail:
DockRowStatusKind.threadDetailStatusLabel
  -> active, waiting, ready, or error header badge

Filters and summaries:
DockRowStatusKind.label
  -> human-readable status vocabulary
```

## 5.3 Object model + abstractions (future)

Add one small computed property:

```swift
public var threadDetailStatusLabel: String?
```

Expected values:

- `.running` -> `"Codex is working"`
- `.needsInput` -> `"Your turn · Needs answer"`
- `.needsApproval` -> `"Your turn · Needs approval"`
- `.idle` -> `"Your turn · Ready"`
- `.error` -> `"Error"`
- `.dormant` -> `nil`
- `.unknown` -> `nil`

Update existing `label` and `visibleBadgeLabel` values rather than adding a
parallel presenter object.

## 5.4 Invariants and boundaries

- Relay normalized status stays unchanged.
- `DockThreadCardDTO` stays unchanged.
- Dock row badge visibility stays separate from Thread Detail header visibility.
- Unknown and dormant do not suddenly become prominent header status pills.
- All shipped strings are exact Swift constants through computed properties, not
  scattered inline literals in view code.
- No second status-copy table is allowed in SwiftUI views, tests, mocks, or
  relay code. Tests may assert strings, but production status vocabulary lives
  in `DockRowStatusKind`.

## 5.5 UI surfaces (ASCII mockups, if UI work)

No new structural surfaces ship in this pass.

Dock keeps the current list layout:

```text
[thread title]                                      [Needs answer]
[host - repo - branch]
[summary]
```

Thread Detail keeps the current header pill row:

```text
[host] [live state] [status]
```

No second `status` banner is added below that header.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Vocabulary owner | `CodexDock/Dock/DockModels.swift` | `DockRowStatusKind.label` | Raw-ish labels: `Running`, `Needs input`, `Idle`, `Not loaded` | Human labels: `Codex is working`, `Needs answer`, `Ready`, `Saved` | Filters and summaries should speak human status | Existing property, changed values | `DockStoreTests` |
| Dock row badges | `CodexDock/Dock/DockModels.swift` | `visibleBadgeLabel` | Shows `Running`, `Needs input`, `Needs approval`, `Error`; hides quiet states | Shows `Codex is working`, `Needs answer`, `Needs approval`, `Error`; still hides `idle`, `dormant`, `unknown` | Badge the thread with useful status; keep ready quiet | Existing property, changed values | `DockStoreTests` |
| Thread Detail header | `CodexDock/Dock/DockModels.swift` | new `threadDetailStatusLabel` | No detail-specific projection | Add detail-specific labels including `Your turn · Ready` | Detail needs ready status without noisy Dock row badge | New computed property | `ThreadDetailHeaderTests` |
| Thread Detail model | `CodexDock/State/ThreadDetailStore.swift` | `ThreadDetailHeader.init(host:row:)` | Uses `row.status.visibleBadgeLabel` | Use `row.status.threadDetailStatusLabel` | Separates Dock urgency from detail status | Uses new property | `ThreadDetailHeaderTests` |
| DTO projection | `CodexDock/State/ThreadCardRowProjector.swift` | `status(for:)` | Maps DTO statuses to `DockRowStatusKind` | No change | Existing normalized status set is sufficient | Existing contract preserved | Existing Dock projection tests |
| Generated DTO | `CodexDock/AppServer/DockThreadCardDTO.swift` | `DockThreadCardStatus` | Coarse statuses only | No change | Avoids relay/contract expansion for first slice | Existing generated contract preserved | No DTO tests needed |
| Relay mapping | `scripts/dock-relay-state-views.mjs` | `normalizedStatus(thread)` | Maps raw active wait flags and idle/error/notLoaded to normalized status | No change | Relay already provides the needed coarse states | Existing relay contract preserved | No relay tests unless file changes |
| Detail UI rendering | `CodexDock/Features/Session/SessionDetailView.swift` | `DetailHeaderView.statusPill` | Renders whatever `statusLabel` provides | No structural change; receives better labels | Avoid duplicate banner work | No new contract | Simulator build |
| Dock row UI rendering | `CodexDock/Features/Dock/DockSharedViews.swift` | row status badge | Renders `visibleBadgeLabel` | No structural change; receives better labels | Existing badge is correct surface | No new contract | Simulator build |
| Dock filters | `CodexDock/Features/Dock/DockFilterSurfaceView.swift` | status filter labels | Uses `status.label` | No structural change; receives better labels | Filter labels should match status vocabulary | No new contract | Existing projection tests if present |
| Dock summary | `CodexDock/State/DockCardProjection.swift` | `statusSummaryText` | Uses `status.label` | No structural change; receives better labels | Summary should not say `Running`/`Idle` | No new contract | `DockStoreTests` if summary pinned |
| Tests | `CodexDockTests/DockStoreTests.swift` | status vocabulary assertions | Expects old badge strings | Update exact expected strings and quiet states | Prevent copy regression | Test contract only | `DockStoreTests` |
| Tests | `CodexDockTests/ThreadDetailHeaderTests.swift` | header status assertions | Expects running label and dormant nil only | Add ready/action/error coverage where fixture helpers allow | Prevent header/Dock badge coupling from regressing | Test contract only | `ThreadDetailStoreTests` |
| UX reference | `docs/CODEX_DOCK_THREAD_STATE_UX_REFERENCE_2026-06-04.md` | first-slice scope | May still mention structural `Your turn` or exact request sublabels as if shippable | Clarify first slice is row badge + Thread Detail header; exact request sublabels are Thread Detail request cards only | Keep doc from over-scoping implementation | Doc only | Readback/status |
| Mock package | `docs/mockups/codex-dock-thread-state-ux-2026-06-04/` | README/source/assets | May show top-level `Your turn` section | Regenerate to show existing Dock list with row badges only | Mocks must match implementation scope | Mock assets only | Node check/render |

## 6.2 Migration notes

- No data migration.
- No relay migration.
- No generated DTO migration.
- No Xcode project migration.
- No new persistent user preference.
- Existing tests that assert old strings must be updated to the new strings.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

- Do not add another enum or presenter unless implementation finds a real shared
  complexity problem. The current enum is already the right boundary.
- Do not move status copy into SwiftUI views; that would create scattered
  string ownership.
- Do not add a new mock-only state taxonomy. Mocks must use the same first-slice
  labels as code.
- If future work needs exact Dock request labels, it must be planned as a relay
  DTO contract expansion. This plan must not smuggle that expansion in through
  mock-only text or view-local inference.
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path, highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

<!-- arch_skill:block:phase_plan:start -->
## Phase 1 - Scope Artifact Alignment

Goal:
- Make the written reference and mocks match the shippable scope before code
  changes.

Work:
- Tighten docs and deterministic mocks to row-level Dock badges plus Thread
  Detail header badges only.

Checklist (must all be done):
- Update `docs/CODEX_DOCK_THREAD_STATE_UX_REFERENCE_2026-06-04.md` if it implies
  a new Dock structural `Your turn` section as first-slice scope.
- Update the mock README if it implies a new Dock structural section or exact
  request subtype badges as first-slice scope.
- Update `render-status-mockups.mjs` so the Dock mock uses the existing list
  shape with row badges only.
- Regenerate SVG/PNG/contact-sheet assets from the deterministic source.

Verification (required proof):
- `rtk node --check docs/mockups/codex-dock-thread-state-ux-2026-06-04/sources/render-status-mockups.mjs`
- `rtk node docs/mockups/codex-dock-thread-state-ux-2026-06-04/sources/render-status-mockups.mjs`
- Run the PNG/contact-sheet regeneration command documented in
  `docs/mockups/codex-dock-thread-state-ux-2026-06-04/README.md`.

Docs/comments (propagation; only if needed):
- No code comments.

Exit criteria (all required):
- The canonical UX reference, mock README, and mock assets all say/show the
  same shippable scope.
- No first-slice artifact claims a new Dock `Your turn` section.

Rollback:
- Revert only the doc/mock edits from this phase.

## Phase 2 - Swift Status Vocabulary Boundary

Goal:
- Put exact human-readable status vocabulary in the existing Swift owner.

Work:
- Update `DockRowStatusKind` labels and add the detail-specific header label.

Checklist (must all be done):
- Change `DockRowStatusKind.label` values to the Section 0.2 filter/summary
  labels.
- Keep `visibleBadgeLabel` hidden for `idle`, `dormant`, and `unknown`.
- Add `threadDetailStatusLabel` with the exact Section 5.3 values.
- Do not add a new enum, relay field, DTO field, or view-local status mapping.

Verification (required proof):
- `rtk swift test --filter DockStoreTests`

Docs/comments (propagation; only if needed):
- Add no comments unless the computed property split is unclear in review.

Exit criteria (all required):
- Unit tests prove exact Dock badge labels and hidden quiet states.
- No relay or generated DTO files changed.

Rollback:
- Revert only `DockModels.swift` and related tests from this phase.

## Phase 3 - Thread Detail Header Adoption

Goal:
- Make Thread Detail show the right "your turn" ready state without making Dock
  ready rows noisy.

Work:
- Point `ThreadDetailHeader` at `threadDetailStatusLabel`.

Checklist (must all be done):
- Update `ThreadDetailHeader.init(host:row:)` to use the detail-specific label.
- Update `ThreadDetailHeaderTests` for `running`, `idle`, waiting, error, and
  dormant/unknown behavior where fixture coverage exists or can be added
  cheaply.
- Do not add a new banner or duplicate visual status surface in
  `SessionDetailView`.

Verification (required proof):
- `rtk swift test --filter ThreadDetailStoreTests`

Docs/comments (propagation; only if needed):
- No new comments expected.

Exit criteria (all required):
- Thread Detail header shows `Your turn · Ready` for an idle row.
- Dormant/unknown behavior remains quiet unless a test fixture proves an
  existing intended exception.
- No duplicate status banner is introduced.

Rollback:
- Revert only `ThreadDetailStore.swift` and related tests from this phase.

## Phase 4 - Final Verification, Review, Commit, Push

Goal:
- Prove the focused UX slice works in tests and on the simulator, then archive
  it in git.

Work:
- Run focused tests, strict review, simulator build/launch, then commit and
  push explicit paths.

Checklist (must all be done):
- Run `rtk swift test --filter DockStoreTests`.
- Run `rtk swift test --filter ThreadDetailStoreTests`.
- Run deterministic mock checks from Phase 1 if mock sources changed.
- Run `rtk git diff --check`.
- Run the thermo-nuclear code quality review against the code diff.
- Run `rtk make app SIM='iPhone 17'`.
- Confirm no relay files changed. If relay files did change despite the plan,
  run `rtk npm run test:relay` and update local/home services only after a
  pushed relay commit.
- Stage explicit changed paths only.
- Commit and push.

Verification (required proof):
- Passing command output for all required tests/checks.
- Simulator app target completes through the Makefile.
- Git commit hash and push result recorded.

Docs/comments (propagation; only if needed):
- Update this plan status/work evidence only after implementation proof exists.

Exit criteria (all required):
- All tests/checks needed by changed files pass or any skipped command has an
  exact environment blocker.
- Strict review has no unresolved must-fix findings.
- Commit exists on the current branch and is pushed to its upstream.

Rollback:
- Use a normal revert commit if needed after push.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

## 8.1 Unit tests (contracts)

- `rtk swift test --filter DockStoreTests`
  - proves Dock row badge vocabulary and hidden quiet badges.
  - catches status filter/summary label drift if existing tests cover them.
- `rtk swift test --filter ThreadDetailStoreTests`
  - proves Thread Detail header status labels.

## 8.2 Integration tests (flows)

- No relay integration test is required unless relay files change.
- No DTO generation check is required unless generated contract files change.
- Deterministic mock checks run only because the mock source is part of this
  task:
  - `rtk node --check docs/mockups/codex-dock-thread-state-ux-2026-06-04/sources/render-status-mockups.mjs`
  - `rtk node docs/mockups/codex-dock-thread-state-ux-2026-06-04/sources/render-status-mockups.mjs`
  - PNG/contact-sheet regeneration from the mock README

## 8.3 E2E / device tests (realistic)

- Run `rtk make app SIM='iPhone 17'`.
- Physical device install is not required for this copy/projection slice unless
  simulator proof exposes installed-app-only behavior.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

- Clean in-place Swift copy/projection change.
- No user data migration.
- No feature flag.
- No relay deployment if relay files remain untouched.

## 9.2 Telemetry changes

- None.

## 9.3 Operational runbook

- If only Swift/docs/mocks change, run tests and simulator build, then commit
  and push.
- If a relay change unexpectedly appears, stop and justify it against this plan;
  then run `rtk npm run test:relay`, push, and refresh local/home services per
  repo instructions.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers:
  - self-integrator; native explorer agents were not used because the available
    multi-agent tool requires explicit user authorization for sub-agents.
- Scope checked:
  - frontmatter, TL;DR, Section 0 scope, Sections 3-6 architecture and
    call-site inventory, Section 7 phase exits, Section 8 verification,
    Section 9 relay/deploy runbook, and Section 10 decisions.
- Findings summary:
  - The artifact consistently scopes the first slice to existing Dock row badges
    and Thread Detail header status.
  - The artifact consistently excludes structural Dock `Your turn` sections,
    problem/offline/network/stale UX, exact Dock request subtype labels, relay
    DTO expansion, and duplicate Thread Detail banners.
  - The artifact consistently names `DockRowStatusKind` as the status vocabulary
    owner.
- Integrated repairs:
  - Added explicit compatibility posture during the research stage.
  - Added no-change rows for relay, DTO, and projector surfaces during
    deep-dive.
  - Added mock PNG/contact-sheet regeneration proof during phase planning.
- Remaining inconsistencies:
  - none
- Unresolved decisions:
  - none
- Unauthorized scope cuts:
  - none
- Decision-complete:
  - yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-06-04 - Scope: badges and header labels only

Context:
- The user clarified that the Dock should simply badge the thread with status
  and that the broad `Problem`/offline/network/error-recovery scope was not the
  intention.

Options:
- Add a new Dock `Your turn` section.
- Add a larger problem/error health system.
- Keep the first slice to existing row badges and Thread Detail header badges.

Decision:
- Ship existing row badges and Thread Detail header badges only.

Consequences:
- The implementation stays in Swift presentation labels.
- Relay contracts stay unchanged.
- Any mock or reference text that implies a new Dock structural section must be
  tightened before code lands.

## 2026-06-04 - Intent-derived: exact request labels stay in Thread Detail

Blocker:
- The desired UX language included examples like `Review command` and
  `Review files`, but the current Dock card DTO only carries coarse status.

Consulted:
- Section 0.2 in-scope labels.
- Section 0.3 out-of-scope exclusions.
- `CodexDock/AppServer/DockThreadCardDTO.swift`.
- `CodexDock/Models/ServerRequestCard.swift`.

Intent says:
- Do not widen this task into more relay contract work.

Decision:
- Dock row badges use `Needs answer` and `Needs approval`. Exact request-card
  titles remain in Thread Detail request cards.

Consequences:
- No relay or DTO change is needed for this first slice.
