---
title: "Codex Dock - File Change Diff Plan"
date: 2026-06-03
status: implemented
doc_type: architecture_plan
fallback_policy: forbidden
owners: [Amir, Codex]
reviewers: [Amir]
canonical: true
related:
  - docs/mockups/codex-dock-file-change-diff-2026-06-03/outputs/contact-sheet.png
  - docs/mockups/codex-dock-file-change-diff-2026-06-03/outputs/01-file-change-summary-card.png
  - docs/mockups/codex-dock-file-change-diff-2026-06-03/outputs/02-file-change-file-list.png
  - docs/mockups/codex-dock-file-change-diff-2026-06-03/outputs/03-file-change-unified-diff.png
  - docs/CODEX_DOCK_PROTOCOL_AND_UPDATE_ARCHITECTURE_REFERENCE_2026-05-31.md
---

# Codex Dock File Change Diff Plan

## 0) Canonical Source

This file is the single planning source for iPhone file-change diff support.

The mockup folder is an asset folder only. It contains screenshots and generated
images that this plan links to; it is not a second plan, UX spec, or
unsupported-message audit.

If implementation notes, audit findings, or follow-up decisions are needed,
append them to this file instead of creating another file-change planning doc.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-06-03
external_research_grounding: folded prior research into this single plan on 2026-06-03
deep_dive_pass_2: done 2026-06-03
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:c3a21f58a71c603e987d31c6afec51036774bd720054986e01460e768b6abe65",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-06-03T21:44:38Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:5abef15774b6af7ea8997d86bb99b3f97d86607af189b81d4c29e5f666d19189",
      "completed_at": "2026-06-03T21:44:47Z",
      "doc_hash_after": "sha256:9d07fc139116e88c48a7ee57b42551c91cde5b9012b112c01265301df576a13f"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-03T21:44:50Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:9d07fc139116e88c48a7ee57b42551c91cde5b9012b112c01265301df576a13f",
      "completed_at": "2026-06-03T21:44:56Z",
      "doc_hash_after": "sha256:cad6a3492452e6c24a4a3034edeefd2148d36f99b503e4f0d555d9e31be7cff7"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-06-03T21:45:00Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:cad6a3492452e6c24a4a3034edeefd2148d36f99b503e4f0d555d9e31be7cff7",
      "completed_at": "2026-06-03T21:45:08Z",
      "doc_hash_after": "sha256:f08da04fa0b41bc4b540a1d9d766293ab4dbd4f256492ea7fa50d865dd4f6919"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-06-03T21:45:11Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:f08da04fa0b41bc4b540a1d9d766293ab4dbd4f256492ea7fa50d865dd4f6919",
      "completed_at": "2026-06-03T21:45:19Z",
      "doc_hash_after": "sha256:e2df9f82390e97730d62153d9ff8291d7601aa579adcf903d4c026be6802e6f1"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-06-03T21:45:22Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:e2df9f82390e97730d62153d9ff8291d7601aa579adcf903d4c026be6802e6f1",
      "completed_at": "2026-06-03T21:45:30Z",
      "doc_hash_after": "sha256:cf4911faf9d235589624dcb6d827380c1eaefbf4a4d2cf039f1fed0c7a749c98"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

## 1) TL;DR

### Outcome

Codex Dock on iPhone should render Codex `fileChange` items as a native review
flow:

- a compact Thread Detail summary card;
- a changed-file list;
- a single-file unified diff view;
- explicit unavailable, binary, generated, truncated, moved, deleted, and
  missing states;
- guarded approval actions.

The placeholder text `File changes are available on desktop.` is allowed only
as a legacy fallback when the structured file-change payload is absent.

### Root Cause

The raw Mac-side app-server receives completed `fileChange.changes[]` data, but
the phone-facing Dock relay projection drops the file list and diff before Swift
can render it. The iPhone can approve `item/fileChange/requestApproval` today,
but it cannot inspect the patch first.

### Minimal Architecture

Use the existing Thread Detail projection.

Add one optional nested object, `payload.fileChange`, to the existing
thread-detail row. Keep the existing:

- JSON-RPC route;
- subscription/update path;
- `projectionID`;
- `sourceRef`;
- row ordering;
- `rowRole`;
- `renderKind`;
- `visibility`;
- request response path;
- outer `schemaVersion`, `identityVersion`, and `projectionEngineVersion`.

Do not add a new JSON-RPC method, subscription, raw app-server endpoint, direct
iPhone app-server path, side channel, or runtime shim.

### Done State

The feature is done only when the installed `iPhone 17` simulator app proves:

1. A structured file-change row shows a summary card instead of the desktop
   placeholder.
2. Tapping `Review changes` opens the file list.
3. Tapping a file opens a unified diff.
4. The diff shows exact added, removed, and context lines for supported text
   diffs.
5. Non-renderable files are visible and explicitly acknowledged.
6. `Approve` is not the first action from the Thread Detail card.
7. Approval is direct only after review requirements are satisfied.
8. Limited or incomplete review requires a confirmation.
9. Decline is available and confirmed.
10. Existing request responses still send exactly
    `{"decision":"accept"}` and `{"decision":"decline"}`.

## 2) Non-Negotiables

- One canonical plan: this file.
- No second unsupported-message plan for this work.
- No second UX spec for this work.
- No prompt file or mockup README may act as product truth.
- The phone continues to use `thread/detail/subscribe` and
  `thread/detail/update`.
- The app normally connects to the Dock relay on `:4510`, not directly to the
  raw authenticated app-server on `:4500`.
- Add optional data inside the existing row payload.
- Keep outer projection versions at `1` for this first implementation.
- Put nested file-change evolution behind `payload.fileChange.version`.
- Swift must use typed DTOs, not `diagnostic` or raw JSON mining.
- No duplicate blind approval card for the same file-change request.
- No primary `Approve` button before the user can review or explicitly accept
  limited review.
- Missing, truncated, binary, generated, renamed, deleted, and unsupported
  files must remain visible.
- Do not log full diffs, full JSON-RPC payloads, prompt text, transcript text,
  bearer tokens, audio, raw audio, or secrets.
- Any production caps belong in `CodexDock/Configuration/CodexDockConstants.swift`
  or `scripts/dock-relay-constants.mjs`.

## 3) Scope

### In Scope

User-visible work:

- Replace supported file-change placeholders with `FileChangeReviewCard`.
- Show file count, additions, deletions, approval state, and warnings.
- Show every changed file with filename, path, status, additions, deletions,
  hunk count when available, viewed state, and renderability state.
- Show a single-file unified diff with line numbers, signs, red/green accents,
  non-color labels, hunk navigation, and expandable context.
- Keep decline available.
- Gate or confirm approval when review is incomplete or limited.
- Support VoiceOver labels, Dynamic Type, Increase Contrast, Differentiate
  Without Color, light mode, and dark mode.

Technical work:

- Relay projection in `scripts/dock-relay-thread-detail-projection-adapter.mjs`.
- Relay live merge behavior in `scripts/dock-relay-thread-detail-ledger.mjs`.
- Projection schema and fixtures under `contract/projection/**`.
- Swift DTOs in `CodexDock/AppServer/ThreadDetailDTO.swift`.
- Swift render model in `CodexDock/Models/ThreadEvent.swift`.
- Request behavior through `CodexDock/Models/ServerRequestCard.swift` and
  `CodexDock/State/ThreadDetailStore.swift`.
- Thread Detail UI under `CodexDock/Features/Session/**`.
- Focused relay, Swift, projection, and simulator tests.

### Out Of Scope

- Side-by-side diff on iPhone.
- Inline review comments.
- Suggested changes.
- Branch checkout.
- Editing patches from the phone.
- Full desktop pull request behavior.
- New app-server methods.
- Direct iPhone access to the raw authenticated app-server.
- A new diff service.
- A hunk-level relay schema in v1.
- A visual golden-test system for mockup pixels.
- `Largest` sorting in v1.

<!-- arch_skill:block:research_grounding:start -->
## 4) Research Grounding

Stage receipt note: research grounding was reconfirmed against the collapsed
single-plan content on 2026-06-03.

### External UX Anchors

- GitHub pull request file comparison docs:
  <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-comparing-branches-in-pull-requests?apiVersion=2022-11-28>
  - Adopt the shape: summary first, file list second, per-file diff third.
  - Reject desktop-style side-by-side diff as the default on iPhone.
- GitHub improved `Files changed` page:
  <https://github.blog/changelog/2026-01-22-improved-pull-request-files-changed-page-on-by-default/>
  - Adopt clear file navigation and review progress.
  - Compress it for iPhone instead of copying the desktop layout.
- GitHub Mobile expandable context:
  <https://github.blog/changelog/2022-05-17-expand-code-lines-while-you-are-reviewing-a-pull-request-on-github-mobile/>
  - Adopt expandable unchanged context in the unified diff view.
- GitHub Mobile unchanged-line commenting:
  <https://github.blog/changelog/2026-02-03-github-mobile-comment-on-unchanged-lines-in-pull-request-files/>
  - Treat exact line context as mobile-critical.
  - Do not add comments in this pass.
- GitHub accessibility guide for pull requests:
  <https://accessibility.github.com/documentation/guide/pull-requests/>
  - Adopt non-color-only indicators, semantic labels, and reachable controls.
- Linear diffs:
  <https://linear.app/docs/diffs>
  - Adopt concise review connected to task context.
  - Do not create a separate PR-like product mode.
- Apple iPhone accessibility settings:
  <https://support.apple.com/en-us/111773>
  - Support Dynamic Type, Increase Contrast, and Differentiate Without Color.
- 2025 code-review-order study:
  <https://arxiv.org/abs/2506.10654>
  - File order affects review comprehension.
  - Use stable source order for v1; defer extra sorting.

### Mockup Assets

- Contact sheet:
  [outputs/contact-sheet.png](mockups/codex-dock-file-change-diff-2026-06-03/outputs/contact-sheet.png)
- Summary card:
  [outputs/01-file-change-summary-card.png](mockups/codex-dock-file-change-diff-2026-06-03/outputs/01-file-change-summary-card.png)
- File list:
  [outputs/02-file-change-file-list.png](mockups/codex-dock-file-change-diff-2026-06-03/outputs/02-file-change-file-list.png)
- Unified diff:
  [outputs/03-file-change-unified-diff.png](mockups/codex-dock-file-change-diff-2026-06-03/outputs/03-file-change-unified-diff.png)

The mockups are visual intent. This plan and the source code are product truth.
<!-- arch_skill:block:research_grounding:end -->

<!-- arch_skill:block:current_architecture:start -->
## 5) Current State And Unsupported Audit

Stage receipt note: deep-dive pass 1 reconfirmed the current unsupported
file-change path and adjacent placeholder surfaces on 2026-06-03.

### Confirmed Pre-Implementation State

The raw app-server had the data. Before this implementation, the Dock relay did
not forward the structured file-change payload to the phone.

Pre-implementation phone result:

- `fileChange` item:
  - title: `File change`;
  - body: `File changes are available on desktop.`;
  - visible by default as a request-category row.
- `item/fileChange/requestApproval`:
  - visible approval card;
  - can approve or decline;
  - does not show the diff being approved.

Net: no protocol-level product redesign was needed. The implemented fix expands
the existing thread-detail row payload and renders the new typed data in Swift.

### Unsupported Or Partial Thread Detail Rows

This audit is folded into the file-change plan so it does not become a second
planning source.

| Input | Pre-implementation phone behavior | Missing content | Implementation result |
| --- | --- | --- | --- |
| `fileChange` item | Placeholder row: `File changes are available on desktop.` | File list, diff, status detail, file summary | Implemented with `payload.fileChange` and `FileChangeReviewCard` |
| `item/fileChange/requestApproval` | `File change approval` card with `Approve` and `Decline` | Actual diff being approved | Implemented as the same file-change row with guarded review/approval |
| `mcpToolCall` item | Hidden tooling row titled `Tool call` | Arguments, result, error, status, resource URI, duration | Future work |
| `dynamicToolCall` item | Hidden tooling row titled `Tool call` | Namespace, arguments, result, status, content | Future work |
| Unknown thread item type | Hidden `Unsupported event` row | Full item payload and typed renderer | Future work |
| Unknown request method | `Needs desktop`; no response payload | Method-specific UI/action | Future work |
| `mcpServer/elicitation/request` | MCP elicitation card; decline only | Form/schema submission | Future work |

Partial support gaps outside this feature:

- `userMessage` drops non-text input parts.
- `agentMessage` drops metadata like `phase` or future structured parts.
- `plan` drops structured plan metadata.
- `reasoning` collapses multiple summaries/parts.
- `commandExecution` omits `cwd`, `processId`, `status`, `exitCode`,
  `durationMs`, and command actions.
- `item/tool/requestUserInput` handles only the first question.
- `item/permissions/requestApproval` lacks detailed per-path/per-host controls.

Ignored notifications outside this feature:

- `item/fileChange/patchUpdated`;
- `item/mcpToolCall/progress`;
- `item/commandExecution/terminalInteraction`;
- `item/autoApprovalReview/started`;
- `item/autoApprovalReview/completed`;
- `rawResponseItem/completed`;
- `item/reasoning/summaryPartAdded`;
- `turn/diff/updated`;
- `turn/plan/updated`;
- `thread/compacted`;
- future unknown notifications.
<!-- arch_skill:block:current_architecture:end -->

<!-- arch_skill:block:call_site_audit:start -->
## 6) Internal Ground Truth

### Relay And Contract Owners

- `scripts/dock-relay-thread-detail-projection-adapter.mjs`
  - Owns `fileChange` rows.
  - Owns item-backed `item/fileChange/requestApproval` projection.
  - Should normalize `payload.fileChange`.
- `scripts/dock-relay-thread-detail-ledger.mjs`
  - Owns live row upsert/merge behavior.
  - Must preserve request and file-change payload fields regardless of arrival
    order.
- `scripts/dock-relay-projection-engine.mjs`
  - Owns outer projection version constants.
  - Outer versions stay at `1`.
- `contract/projection/payloads/thread-detail-row.schema.json`
  - Must allow optional `payload.fileChange`.
- `contract/projection/fixtures/thread-detail-snapshot.json`
  - Must prove a structured file-change row.
- `contract/projection/fixtures/projection-witness-thread-detail.json`
  - Must include witness coverage for the structured file-change row.

### Swift Owners

- `CodexDock/AppServer/ThreadDetailDTO.swift`
  - Add optional typed file-change DTOs.
- `CodexDock/Models/ThreadEvent.swift`
  - Carry optional file-change data to rendering.
  - Do not add `ThreadEventKind.fileChange`.
- `CodexDock/Models/ServerRequestCard.swift`
  - Keep existing approve/decline response payloads.
- `CodexDock/State/ThreadDetailStore.swift`
  - Own viewed state and approval guards.
- `CodexDock/ThreadDetail/ThreadDetailScreenStore.swift`
  - Keep file-change rows in the normal render state.
- `CodexDock/ThreadDetail/ThreadDetailRenderProjector.swift`
  - Keep request cards as decorations on canonical rows.
- `CodexDock/Features/Session/SessionDetailView.swift`
  - Wire file-change review actions to the store.
- `CodexDock/Features/Session/ThreadMessageListView.swift`
  - Choose `FileChangeReviewCard` when `event.fileChange != nil`.
- `CodexDock/Features/Session/FileChangeReviewViews.swift`
  - Feature-owned UI for summary, file list, unified diff, and review actions.
- `CodexDock/Models/FileChangeReviewModels.swift`
  - Feature-owned parser/view models for file and diff line state.
<!-- arch_skill:block:call_site_audit:end -->

<!-- arch_skill:block:target_architecture:start -->
## 7) Target Data Contract

Stage receipt note: deep-dive pass 2 reconfirmed the target optional payload,
Swift typed boundary, and store-owned approval guard on 2026-06-03.

### Contract Shape

Add optional `payload.fileChange` to the existing thread-detail row.

Required nested fields:

- `version`: initially `1`.
- `status`: `completed`, `pending`, `applied`, `declined`, `failed`, or
  `unknown`.
- `approvalRequired`: true when a pending request is attached.
- `summary.fileCount`: number of changed files.
- `summary.additions`: best-effort added-line count.
- `summary.deletions`: best-effort removed-line count.
- `summary.truncated`: true if any entry is capped or truncated.
- `changes[].path`: absolute or repo path from the raw item.
- `changes[].oldPath`: move/rename source path when known, otherwise null.
- `changes[].kind`: `add`, `update`, `delete`, `move`, or `unknown`.
- `changes[].additions`: best-effort per-file additions.
- `changes[].deletions`: best-effort per-file deletions.
- `changes[].diffAvailability`: `available`, `binary`, `generated`,
  `tooLarge`, `missing`, `unsupported`, or `unknown`.
- `changes[].diff`: raw unified diff text or full added-file content when
  supplied.
- `changes[].truncated`: per-file truncation state.
- `changes[].unavailableReason`: reason when the diff is not renderable.
- top-level `unavailableReason`: row-level reason when no file list or diff is
  available.

### Raw App-Server Example

```json
{
  "type": "fileChange",
  "id": "call_example_file_change_1",
  "changes": [
    {
      "path": "/Users/aelaguiz/workspace/codex-client/docs/example.md",
      "kind": {
        "type": "update",
        "move_path": null
      },
      "diff": "@@ -17,2 +17,5 @@\n Existing line\n-Old line\n+New line\n+Added line\n"
    }
  ],
  "status": "completed"
}
```

### Current Phone Placeholder Example

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "host-example",
  "view": "thread.detail",
  "threadID": "thread-example",
  "projectionID": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1/row:fileChange",
  "sourceRef": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1",
  "rowRole": "fileChange",
  "payload": {
    "turnID": "turn-example",
    "itemID": "call_example_file_change_1",
    "itemType": "fileChange",
    "visibility": "request",
    "renderKind": "request",
    "title": "File change",
    "body": "File changes are available on desktop.",
    "requestID": null,
    "request": null,
    "diagnostic": null
  }
}
```

### Target Completed Row Example

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "host-example",
  "view": "thread.detail",
  "threadID": "thread-example",
  "projectionID": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1/row:fileChange",
  "sourceRef": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1",
  "rowRole": "fileChange",
  "payload": {
    "turnID": "turn-example",
    "itemID": "call_example_file_change_1",
    "itemType": "fileChange",
    "visibility": "request",
    "renderKind": "request",
    "title": "File change",
    "body": "1 file changed, +2 -1",
    "requestID": null,
    "request": null,
    "diagnostic": null,
    "fileChange": {
      "version": 1,
      "status": "completed",
      "approvalRequired": false,
      "summary": {
        "fileCount": 1,
        "additions": 2,
        "deletions": 1,
        "truncated": false
      },
      "changes": [
        {
          "path": "/Users/aelaguiz/workspace/codex-client/docs/example.md",
          "oldPath": null,
          "kind": "update",
          "additions": 2,
          "deletions": 1,
          "diffAvailability": "available",
          "diff": "@@ -17,2 +17,5 @@\n Existing line\n-Old line\n+New line\n+Added line\n",
          "truncated": false,
          "unavailableReason": null
        }
      ],
      "unavailableReason": null
    }
  }
}
```

### Target Approval-Linked Row Example

The approval request uses the same file-change row identity. The row gains both
`payload.request` and `payload.fileChange`.

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "host-example",
  "view": "thread.detail",
  "threadID": "thread-example",
  "projectionID": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1/row:fileChange",
  "sourceRef": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1",
  "rowRole": "fileChange",
  "payload": {
    "turnID": "turn-example",
    "itemID": "call_example_file_change_1",
    "itemType": "fileChange",
    "visibility": "request",
    "renderKind": "request",
    "title": "File change approval",
    "body": "Review 1 file before approving, +2 -1",
    "requestID": "request-example-file-change-approval",
    "request": {
      "requestID": "request-example-file-change-approval",
      "method": "item/fileChange/requestApproval",
      "params": {
        "threadId": "thread-example",
        "turnId": "turn-example",
        "itemId": "call_example_file_change_1",
        "reason": "Review 1 file before approving, +2 -1"
      },
      "status": "pending"
    },
    "diagnostic": null,
    "fileChange": {
      "version": 1,
      "status": "pending",
      "approvalRequired": true,
      "summary": {
        "fileCount": 1,
        "additions": 2,
        "deletions": 1,
        "truncated": false
      },
      "changes": [
        {
          "path": "/Users/aelaguiz/workspace/codex-client/docs/example.md",
          "oldPath": null,
          "kind": "update",
          "additions": 2,
          "deletions": 1,
          "diffAvailability": "available",
          "diff": "@@ -17,2 +17,5 @@\n Existing line\n-Old line\n+New line\n+Added line\n",
          "truncated": false,
          "unavailableReason": null
        }
      ],
      "unavailableReason": null
    }
  }
}
```

### Target Unavailable-Diff Row Example

```json
{
  "schemaVersion": 1,
  "identityVersion": 1,
  "projectionEngineVersion": 1,
  "sourceHostID": "host-example",
  "view": "thread.detail",
  "threadID": "thread-example",
  "projectionID": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1/row:fileChange",
  "sourceRef": "host:host-example/thread:thread-example/turn:turn-example/item:call_example_file_change_1",
  "rowRole": "fileChange",
  "payload": {
    "turnID": "turn-example",
    "itemID": "call_example_file_change_1",
    "itemType": "fileChange",
    "visibility": "request",
    "renderKind": "request",
    "title": "File change",
    "body": "Diff unavailable on phone.",
    "requestID": "request-example-file-change-approval",
    "request": {
      "requestID": "request-example-file-change-approval",
      "method": "item/fileChange/requestApproval",
      "params": {
        "threadId": "thread-example",
        "turnId": "turn-example",
        "itemId": "call_example_file_change_1",
        "reason": "Diff unavailable on phone."
      },
      "status": "pending"
    },
    "diagnostic": null,
    "fileChange": {
      "version": 1,
      "status": "pending",
      "approvalRequired": true,
      "summary": {
        "fileCount": 0,
        "additions": 0,
        "deletions": 0,
        "truncated": false
      },
      "changes": [],
      "unavailableReason": "missingDiff"
    }
  }
}
```

## 8) Target Interface

### Visual Model

The iPhone flow has three layers:

1. Summary card in Thread Detail.
2. File list sheet/screen.
3. Single-file unified diff screen.

The flow is intentionally not a desktop PR page. The summary keeps the
conversation readable, the file list gives scope, and the diff screen gives
exact inspection when needed.

### Screen 1 - Thread Detail Summary Card

```text
Thread Detail
< Back                                            ...
-----------------------------------------------------
Agent
Implemented the thread detail changes.

+---------------------------------------------------+
| Files changed                            Pending |
| 7 files  +184  -42                               |
| Review the diff before approving this change.    |
|                                                   |
| ThreadMessageListView.swift        +72   -18     |
| dock-relay-thread-detail...        +55    -6     |
| ThreadDetailDTO.swift              +31    -4     |
|                                                   |
| [Review changes]                     [Decline]   |
+---------------------------------------------------+

Composer...
-----------------------------------------------------
```

Rules:

- `Review changes` is the primary action.
- `Decline` appears when request data is present.
- `Approve` does not appear on the Thread Detail summary card.
- If `payload.fileChange` is absent, show legacy fallback text.
- If no diff is available, show an explicit warning and route to limited-review
  confirmation.

### Screen 2 - File List

```text
File changes
< Thread                                           ...
-----------------------------------------------------
7 files changed
+184 additions  -42 deletions  Pending approval

[All] [Unviewed]

0 of 7 viewed

ThreadMessageListView.swift
CodexDock/Features/Session
[Modified] [UI] [5 hunks]                   +72 -18

dock-relay-thread-detail-projection-adapter.mjs
scripts
[Modified] [Relay] [3 hunks]                +55  -6

ThreadDetailDTO.swift
CodexDock/AppServer
[Modified] [DTO] [2 hunks]                  +31  -4

-----------------------------------------------------
[Decline]                  [Review before approve]
```

Rules:

- Source order is the required v1 order.
- `All` and `Unviewed` are allowed because viewed state is part of approval
  safety.
- `Largest` sorting is not v1 scope.
- Tapping a file opens its diff screen.
- Non-renderable file rows open a reason screen and require acknowledgement.

### Screen 3 - Unified Diff

```text
ThreadMessageListView.swift
< Files                                           ...
-----------------------------------------------------
[Modified] [5 hunks] [+72] [-18]     1 of 7 viewed

@@ -52,7 +52,11 @@ struct ThreadMessageListView: View {
  52   52   var body: some View {
  53   53     VStack {
- 54        PlaceholderMessage("File changes are available...")
+      54   FileChangeReviewCard(summary: fileChange.summary)
+      55     .onTapGesture { openReview() }
  56   56     }
  57   57   }

[Expand 10 unchanged lines]

-----------------------------------------------------
[Decline]                         [Approve changes]
```

Rules:

- Use a single-column unified diff on iPhone.
- Show line numbers when available.
- Show `+` and `-` signs so meaning is not color-only.
- Use red/green accents, but do not rely on color alone.
- Hunk headers are navigable when parsed.
- Collapsed context can expand.
- Opening a renderable file marks it viewed.
- A non-renderable file is viewed only after explicit acknowledgement.

### Approval States

| State | Button text | Behavior |
| --- | --- | --- |
| No file opened | `Review before approve` | Disabled or routes to unviewed reminder |
| Some files unviewed | `Approve without reviewing all files?` | Opens confirmation |
| Any file limited/non-renderable | `Approve with limited diff?` | Opens confirmation |
| All renderable files viewed | `Approve changes` | Sends existing accept response |
| Request already resolved | `Resolved` | No send |
| Send failed | `Try again` | Uses existing retry/send state |

Decline always opens confirmation before sending `{"decision":"decline"}`.

## 9) Interaction Contract

- Summary `Review changes` opens the file list.
- Summary `Decline` opens decline confirmation.
- Summary card tap outside explicit controls does not approve.
- File row tap opens that file.
- File diff marks that file viewed when opened.
- Non-renderable state marks the file viewed only after acknowledgement.
- `All` shows every file.
- `Unviewed` filters to files that still need review or acknowledgement.
- `Approve changes` calls `ThreadDetailStore.respond(to:action:)`.
- Approval guard lives in `ThreadDetailStore`, so UI closures cannot bypass it.
- The request response payload remains unchanged:
  - accept: `{"decision":"accept"}`;
  - decline: `{"decision":"decline"}`.
<!-- arch_skill:block:target_architecture:end -->

<!-- arch_skill:block:phase_plan:start -->
## 10) Implementation Plan

Stage receipt note: phase-plan readiness was reconfirmed against the five
implementation phases after the single-plan collapse on 2026-06-03.

### Phase 1 - Relay Payload Seam

Goal: prove raw `fileChange.changes[]` becomes optional
`payload.fileChange` on the existing row without changing identity, ordering,
transport, request path, or outer versions.

Required work:

- Add file-change normalization in
  `scripts/dock-relay-thread-detail-projection-adapter.mjs`.
- Add optional `fileChange` support to `makeProjectionRow()`.
- Attach structured payload for supported `fileChange` rows.
- Attach or merge payload for stable `item/fileChange/requestApproval` rows.
- Add unavailable-diff payload when approval exists but diff data is absent.
- Update `scripts/dock-relay-thread-detail-ledger.mjs` so request and
  file-change payloads survive both arrival orders.
- Update `contract/projection/payloads/thread-detail-row.schema.json`.
- Update `contract/projection/fixtures/thread-detail-snapshot.json`.
- Update `contract/projection/fixtures/projection-witness-thread-detail.json`.
- Preserve old fallback title/body when structured payload is absent.
- Keep outer projection versions at `1`.

Required proof:

- `rtk npm run contract:check`
- `rtk npm run test:relay`

Exit criteria:

- Existing file-change row identity stays stable.
- Structured fixture emits `payload.fileChange.version: 1`.
- Approval-linked row keeps existing `payload.request` shape.
- Ledger tests prove item-before-request and request-before-item merge.
- No new JSON-RPC route, subscription, app-server call, or outer version bump.

### Phase 2 - Swift DTO And Model Seam

Goal: decode the optional payload and carry it to Thread Detail without
breaking legacy rows.

Required work:

- Add `ThreadDetailFileChangeDTO`,
  `ThreadDetailFileChangeSummaryDTO`, and
  `ThreadDetailFileChangeEntryDTO`.
- Add `fileChange: ThreadDetailFileChangeDTO?` to
  `ThreadDetailEventPayloadDTO`.
- Preserve legacy decode when `fileChange` is absent.
- Carry optional file-change data through `ThreadEvent`.
- Keep `ThreadEventKind.request`.
- Add parser/view models for file state and diff-line state.
- Preserve existing `ServerRequestCard` response payloads.

Required proof:

- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter ThreadDetailRenderProjectorTests`
- `rtk swift test --filter ThreadDetailScreenStoreTests`
- `rtk swift test --filter ServerRequestCardTests`
- `rtk swift test --filter FileChangeReviewModelsTests`

Exit criteria:

- Legacy rows decode.
- Structured rows decode.
- Unavailable-diff rows decode.
- `ThreadEvent` exposes file-change data.
- No UI code mines `diagnostic` or raw request params for file data.

### Phase 3 - Summary Card And File List

Goal: replace the visible placeholder with reviewable UI while keeping approval
behind review.

Required work:

- Render `FileChangeReviewCard` when `event.fileChange != nil`.
- Keep legacy fallback when `event.fileChange == nil`.
- Show summary counts, approval state, and warning state.
- Add `Review changes` as the primary summary action.
- Add confirmed `Decline` when request data is present.
- Do not show summary-card `Approve`.
- Add file list rows with filename, path, status, hunk count when available,
  additions, deletions, and viewed state.
- Track viewed state in `ThreadDetailStore`.
- Preserve source order.
- Add `All` / `Unviewed` only if viewed state is exposed.

Required proof:

- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter ThreadDetailRenderProjectorTests`
- `rtk swift test --filter ThreadDetailScreenStoreTests`
- focused UI/view-model tests where available.

Exit criteria:

- Structured rows render summary card.
- File list opens and shows every changed file.
- Legacy no-payload rows still render a clear fallback.
- Approval cannot happen directly from the summary card.

### Phase 4 - Unified Diff And Non-Renderable States

Goal: complete inspection for supported diffs and explicit handling for limited
diffs.

Required work:

- Add `FileChangeDiffView`.
- Parse hunked diffs, context lines, additions, and deletions.
- Render full-content add strings as added lines when no hunk header exists.
- Show line numbers where possible.
- Add hunk navigation and context expansion.
- Render binary, generated, deleted, moved, missing, too-large, unsupported,
  and truncated states explicitly.
- Use lazy rendering and stable row dimensions.
- Add accessibility labels for counts, files, hunks, and changed lines.

Required proof:

- `rtk swift test --filter FileChangeReviewModelsTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`

Exit criteria:

- Tapping a file opens a unified diff.
- Supported text diffs show exact changed lines.
- Non-renderable files stay visible and can be acknowledged.
- Diff meaning is not color-only.
- Text does not overlap in normal and large Dynamic Type.

### Phase 5 - Approval Safety And Final Simulator Proof

Goal: wire approve/decline into the completed review flow and prove it on the
installed simulator app.

Required work:

- Keep decline available in the review surface.
- Confirm decline before sending.
- Enable direct approve only after review requirements are satisfied.
- Confirm approval when files are unviewed.
- Confirm approval when any file has missing, truncated, or non-renderable
  diff data.
- Preserve existing request response send path.
- Preserve loaded diff data through offline/error states.
- Update this plan's unsupported audit after support lands.
- Add controlled simulator proof for summary -> list -> diff -> approve.

Required proof:

- `rtk npm run contract:check`
- `rtk npm run test:relay`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter ThreadDetailRenderProjectorTests`
- `rtk swift test --filter ThreadDetailScreenStoreTests`
- `rtk swift test --filter ServerRequestCardTests`
- `rtk swift test --filter FileChangeReviewModelsTests`
- `rtk swift test --filter ProjectionReducerTests`
- `rtk swift test --filter AutomationIDTests`
- `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`

Exit criteria:

- Summary card, file list, unified diff, non-renderable states, decline, and
  guarded approval all work in the installed `iPhone 17` simulator app.
- Accept and decline payloads are unchanged.
- Approval is never blind unless the user explicitly confirms a missing or
  limited diff state.
- Store-owned approval guards cannot be bypassed by Thread Detail UI closures.
- Light mode and dark mode are readable.
- No full diffs or secrets appear in logs.
<!-- arch_skill:block:phase_plan:end -->

## 11) Verification Strategy

Use the smallest check that proves the touched layer first, then run the final
set before commit.

Relay and contract:

- `rtk npm run contract:check`
- `rtk npm run test:relay`

Swift:

- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter ThreadDetailRenderProjectorTests`
- `rtk swift test --filter ThreadDetailScreenStoreTests`
- `rtk swift test --filter ServerRequestCardTests`
- `rtk swift test --filter FileChangeReviewModelsTests`
- `rtk swift test --filter ProjectionReducerTests`
- `rtk swift test --filter AutomationIDTests`

Simulator:

- `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`

Required simulator proof:

- summary card;
- file list;
- unified diff;
- reviewed-file state;
- unviewed-file approval confirmation;
- limited-diff approval confirmation;
- decline confirmation;
- Dynamic Type and no overlap;
- light mode;
- dark mode.

Physical iPhone proof is useful but not required for this plan. If physical
Mobile MCP reports `WebDriverAgent is not running on device`, stop retrying
physical Mobile MCP for that task and record that exact blocker.

## 12) Rollout And Operations

- Implement behind data presence, not a feature flag.
- Structured rows use the new UI.
- Legacy rows without `payload.fileChange` use fallback rendering.
- Old relay/app compatibility is preserved by keeping outer versions at `1`.
- No raw app-server deployment is required.
- Start local services with `rtk make services`.
- Check service state with:
  - `rtk make app-server-status`;
  - `rtk make dock-relay-status`.
- Build/launch simulator with:
  - `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`.
- Capture simulator logs with:
  - `rtk make sim-logs SIM='iPhone 17'`.
- Capture relay logs with:
  - `rtk make dock-relay-logs`.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: self-integrator
- Scope checked:
  - One canonical plan doc, unsupported-message audit, target UX, protocol
    contract, implementation phases, verification, and rollout.
  - Relay projection, projection contract fixtures, Swift DTO/model/store/UI
    path, request-card response path, simulator proof path, and docs cleanup.
- Findings summary:
  - The plan now keeps file-change decisions in one doc while linking mockup
    images as assets only.
  - The minimal protocol change remains optional `payload.fileChange` on the
    existing thread-detail row.
  - The approved implementation frontier remains Phases 1-5.
- Integrated repairs:
  - Removed sidecar mockup README/prompt docs from the working spec surface.
  - Kept research links, protocol examples, wireframes, interactions, phases,
    and verification requirements in this single plan.
  - Re-minted arch-step readiness receipts after the single-plan collapse.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

<!-- arch_skill:block:implementation_audit:start -->
## 13) Implementation Result

Status: implemented on 2026-06-03.

Implemented shape:

- Relay projects structured file-change data as optional
  `payload.fileChange.version: 1` on the existing Thread Detail row.
- Relay live/history merge preserves `payload.request` and
  `payload.fileChange` in either arrival order.
- Swift decodes typed file-change DTOs, carries them on `ThreadEvent`, and
  renders `FileChangeReviewCard` for `event.fileChange != nil`.
- Thread Detail shows summary, file list, single-file unified diff, viewed
  state, unavailable states, limited-diff warnings, and guarded approval.
- `ThreadDetailStore` owns viewed-file state and blocks direct accept until the
  review state is complete or the user confirms the risk.
- Legacy rows without `payload.fileChange` keep the fallback body behavior.

Simulator proof:

- Passing proof directory:
  `/tmp/codex-client/file-change-review-proof-20260603T232800Z`
- Relay report:
  `/tmp/codex-client/file-change-review-proof-20260603T232800Z/relay-client-path.json`
- Rendered UI proof:
  `/tmp/codex-client/file-change-review-proof-20260603T232800Z/simulator-ui-sync.json`
- Command:
  `rtk make sim-ui-controlled-scenario-sync-proof SIM='iPhone 17' SIM_UI_SYNC_SCENARIO='file-change-review' SIM_UI_SYNC_DIR='/tmp/codex-client/file-change-review-proof-20260603T232800Z' SIM_UI_SYNC_DURATION_MS=16000 SIM_UI_SYNC_SAMPLE_MS=1000 SIM_UI_SYNC_SCENARIO_HOLD_MS=1000 SIM_UI_SYNC_RELAY_DURATION_MS=120000 SIM_UI_SYNC_READY_TIMEOUT_MS=120000 MAX_UI_LAG_MS=3000`
- Result: pass. The proof covers the summary card, `Review changes`, file
  list, file row navigation, unified diff, reviewed-file approval path, relay
  `server/response`, and rendered `Pending` -> `Resolved` status.

Verification passed:

- `rtk npm run contract:check`
- `rtk npm run test:relay`
- `rtk swift test --filter AppServerClientTests`
- `rtk swift test --filter ThreadDetailStoreTests`
- `rtk swift test --filter ThreadDetailRenderProjectorTests`
- `rtk swift test --filter ThreadDetailScreenStoreTests`
- `rtk swift test --filter ServerRequestCardTests`
- `rtk swift test --filter FileChangeReviewModelsTests`
- `rtk swift test --filter ProjectionReducerTests`
- `rtk swift test --filter AutomationIDTests`
- `rtk git diff --check`
- `rtk make app SIM='iPhone 17' FORCE_LAUNCH=1`

Thermo-nuclear code quality review:

- Result: no blocking structural issue found before commit.
- `scripts/dock-relay-thread-detail-projection-adapter.mjs` was kept under
  1000 lines by extracting file-change normalization into
  `scripts/dock-relay-thread-detail-file-change.mjs`.
- `CodexDock/Features/Session/FileChangeReviewViews.swift` is large at 846
  lines, but still cohesive: it contains one review flow and private local
  subviews. Splitting it now would move concepts around without deleting
  complexity.
- `scripts/dock-relay-controlled-simulator-fixture.mjs` is already a large
  scenario harness. The file-change scenario follows that existing harness
  pattern; extracting one scenario now would require exposing many private test
  helpers and would not simplify the production code path.

Known proof limitation:

- The app implements decline confirmation with SwiftUI `confirmationDialog` in
  both the summary card and review sheet. The controlled simulator proof records
  the visible `Decline` control, but does not automate `Decline -> Cancel`
  because that XCUITest action-sheet path proved brittle and blocked the stable
  approval proof. This is a proof limitation, not a protocol or render-path
  limitation.
<!-- arch_skill:block:implementation_audit:end -->

## 14) Decision Log

### 2026-06-03 - Single Canonical Plan

Decision: keep all file-change UX, protocol, unsupported-audit, implementation,
verification, and rollout truth in this file.

Why: the prior working shape split the same feature across a plan, mockup
package docs, and process notes. That made it too easy for one document to drift
from another.

Consequence: the mockup folder is assets only. Any durable requirement must be
in this file.

### 2026-06-03 - Optional Nested Payload

Decision: add optional `payload.fileChange` to the existing thread-detail row.

Why: it is the smallest safe change. It expands the payload the phone already
receives instead of adding a new route or moving the phone closer to the raw
authenticated app-server.

Consequence: relay, schema, Swift DTOs, and UI must move together, but the
carefully tested projection route stays intact.

### 2026-06-03 - Raw Diff Strings In V1

Decision: carry raw `changes[].diff` strings plus summary counts in
`payload.fileChange.version: 1`; parse display hunks in Swift.

Why: confirmed upstream data already has raw diff strings. A hunk-level relay
schema would be bigger protocol work than v1 needs.

Consequence: richer hunk JSON can be reconsidered later only if implementation
evidence proves it is worth the protocol surface.

### 2026-06-03 - Stable Source Order In V1

Decision: preserve source order and support `All` / `Unviewed` when viewed
state is exposed. Do not implement `Largest` sorting in v1.

Why: approval safety needs viewed state. It does not need a broader sorting
product surface.

Consequence: `Largest` remains a named follow-up, not part of the first
implementation.

### 2026-06-03 - Approval Guard Lives In Store

Decision: `ThreadDetailStore` owns viewed state and approval gating.

Why: UI-only gating is bypassable through another action closure. The store is
the boundary before the existing request response sender.

Consequence: any approve action must pass through the same guard before sending
`{"decision":"accept"}`.

### 2026-06-03 - Mockup Docs Retired

Decision: remove the mockup README and generation prompt docs from the working
plan surface.

Why: they were process artifacts, but they looked like separate UX/spec docs.

Consequence: this plan links directly to the generated mockup images and owns
all durable requirements.
