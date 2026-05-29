---
title: "Codex Dock - UI Automation Accessibility Hooks - Architecture Plan"
date: 2026-05-29
status: implemented
fallback_policy: forbidden
owners: [Amir]
reviewers: [Codex]
doc_type: architectural_change
related:
  - README.md
  - Makefile
  - project.yml
  - Package.swift
  - CodexDockApp/CodexDockApp.swift
  - CodexDock/Features/Dock/CodexDockBootstrapView.swift
  - CodexDock/Features/Dock/DockView.swift
  - CodexDock/Features/Dock/DockSharedViews.swift
  - CodexDock/Features/Archive/ArchiveView.swift
  - CodexDock/Features/Hosts/HostsView.swift
  - CodexDock/Features/Session/SessionDetailView.swift
  - CodexDock/Features/Session/ComposerView.swift
  - CodexDock/Features/Session/ThreadMessageListView.swift
  - CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift
---

# TL;DR

Outcome: Codex Dock's full SwiftUI surface becomes drivable through the accessibility tree, so simulator automation can see named screens, controls, rows, state, and action targets without guessing from screenshots.

Problem: the app has useful accessibility labels in a few controls, but there is no stable automation identifier contract, no UI-test target, and no full-screen coverage map for Dock, Archive, Relay setup/settings, Session detail, Composer, request cards, and global connectivity.

Approach: add one canonical automation identifier owner, apply identifiers and semantic labels/values at the view boundaries, then prove the contract with a narrow real simulator slice before expanding to every first-class screen.

Plan: first build the shared ID contract and a real simulator accessibility-tree proof, then expand to root tabs and setup/settings, then Dock rows, then thread detail and request cards, then add the simulator runbook and docs.

Non-negotiables: no screenshot interpretation as the main proof, no identifiers based on visible copy or row order, no sensitive prompt/transcript/secret text in automation identifiers, no duplicate ID registries, and no fallback test-only UI.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-29
external_research_grounding: done 2026-05-29
deep_dive_pass_2: done 2026-05-29
recommended_flow: research -> deep dive -> deep dive -> phase plan -> consistency pass -> plan audit
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:4325c5e456d00ee10c474b3e16d26963cb7406b9dca92d2e2998363cb47fd27c",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-29T12:10:53Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:d7636db0be435377667200b97c2ad70b22805f516d98f29d66637cd4aa6e78d0",
      "completed_at": "2026-05-29T12:11:24Z",
      "doc_hash_after": "sha256:f9ffd21b2b03e240842bd7050149664fa200ce8252b3fdcbd5f347f37299701e"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T12:11:35Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:f9ffd21b2b03e240842bd7050149664fa200ce8252b3fdcbd5f347f37299701e",
      "completed_at": "2026-05-29T12:12:48Z",
      "doc_hash_after": "sha256:44a23547262a07c28712ffd44c9b78d521a4ea7b45eaefdd793302fc22cf4402"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-29T12:13:27Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:44a23547262a07c28712ffd44c9b78d521a4ea7b45eaefdd793302fc22cf4402",
      "completed_at": "2026-05-29T12:13:43Z",
      "doc_hash_after": "sha256:4dc7f342521a00fd7ac32b2d788f3aa527ff548b3f0b9d98f7590eeb45374797"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-29T12:13:54Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:4dc7f342521a00fd7ac32b2d788f3aa527ff548b3f0b9d98f7590eeb45374797",
      "completed_at": "2026-05-29T12:14:34Z",
      "doc_hash_after": "sha256:5c0b58c7c5a58b4ce4c2c8c9c809d52c41b6ce59916d4480af7f9311f12591a3"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-29T12:14:40Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:5c0b58c7c5a58b4ce4c2c8c9c809d52c41b6ce59916d4480af7f9311f12591a3",
      "completed_at": "2026-05-29T12:15:15Z",
      "doc_hash_after": "sha256:7cf53223dc8b793b88165aff7eae23a236aa78afac99d472d960fa9cb88fdf83"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After implementation, an automation driver can launch Codex Dock in the `iPhone 17` simulator, inspect the accessibility tree, and drive every primary user path by stable identifiers and semantic accessibility state instead of screenshot interpretation.

## 0.2 In scope

- A single canonical automation identifier contract for SwiftUI views.
- Root app and bootstrap state identification.
- Top-level TabView identification for Dock, Archive, and Relay.
- Dock list controls, host summaries, banners, sections, session rows, row-scoped actions, and empty/error states.
- Archive list controls, archive rows, restore actions, host summaries, empty/unavailable states, and action errors.
- Relay setup and Relay settings screens, including discovered relay rows, manual host/port entry, saved host rows, test/edit/remove/save actions, and validation errors.
- Session detail, header/live state, message filter, composer, voice buttons, send button, message cards, request-card input, request-card approve/decline/send/unsupported states, and stale/error states.
- Global connectivity indicator identification and value exposure across bootstrap, Dock, Archive, Relay, and Session detail.
- Generated Xcode project wiring for a UI-test target through `project.yml`.
- A focused UI automation proof path run through `rtk make app-test SIM='iPhone 17'` or a Makefile-owned equivalent if the target needs a new command.
- README/runbook updates for automation-driven simulator inspection.

## 0.3 Out of scope

- No visual redesign beyond a small user-visible row action affordance if an existing context-menu-only action cannot be made automation-drivable.
- No new product behavior beyond accessibility and automation hooks.
- No physical-phone automation requirement for this architecture change.
- No screenshot diff/golden-image infrastructure.
- No OCR, pixel parsing, or image-recognition harness.
- No runtime debug overlay, hidden test menu, or test-only visible UI.
- No broad refactor of store logic unless a view needs a small model helper to produce stable, privacy-safe identifiers.

## 0.4 Definition of done (acceptance evidence)

- Type-level evidence: one canonical identifier namespace exists and views use it instead of ad hoc string literals for automation identifiers.
- Runtime evidence: every first-class screen exposes a root identifier and meaningful screen-state value.
- Control evidence: every tappable/editable primary control is discoverable by identifier, and dynamic state is exposed through `accessibilityValue` where it matters.
- Row evidence: Dock, Archive, Relay host rows, discovered relay rows, message rows, and request cards expose stable row/card identifiers derived from stable model IDs, not display order or visible copy.
- Privacy evidence: identifiers and labels do not include `OPENAI_API_KEY`, bearer tokens, raw prompt text, transcript text, raw audio, or full JSON-RPC payloads.
- UI-test evidence: a real simulator UI test launches the app, waits for the appropriate bootstrap/root state, drives at least one Dock-to-Session path and one Relay settings path using identifiers, and fails loudly if identifiers drift.
- Project evidence: `project.yml` is the source of truth for the UI-test target and generated scheme.
- Command evidence: the smallest relevant generated-project command is documented and runs through `rtk`, starting with `rtk make app-test SIM='iPhone 17'` if the existing target can own it, or a new Makefile target if UI tests need separate ownership.

## 0.5 Key invariants (fix immediately if violated)

- Automation selectors are stable API, not visible text.
- Accessibility labels remain human-readable and localized-copy-friendly; automation identifiers are stable and not localized.
- Dynamic state belongs in `accessibilityValue` or traits, not in ever-changing identifiers.
- IDs may include stable model keys such as host ID, thread ID, card ID, tab ID, or event ID only after privacy review.
- Full prompt/transcript/message bodies never become identifiers.
- One canonical owner defines identifier names and dynamic ID builders.
- The UI test target is generated from `project.yml`; do not hand-edit `CodexDock.xcodeproj`.
- Simulator proof may use automation-tree inspection. Screenshot proof is supporting evidence only.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Make the app automation-readable through the accessibility tree.
2. Keep real accessibility useful for people, not only tests.
3. Keep selector ownership centralized and boring.
4. Prove one real end-to-end simulator path early.
5. Expand coverage by screen and row family only after the first path works.
6. Avoid leaking sensitive or bulky user content into automation metadata.

## 1.2 Constraints

- The repo is SwiftUI-first and generated-project-first: `project.yml` owns Xcode targets and schemes.
- Mobile builds and tests are Makefile-owned; normal verification uses `rtk make app`, `rtk make app-test`, or a new Makefile wrapper rather than raw `xcodebuild`.
- The app connects to the Dock relay on `:4510`; UI tests must not route the app to the raw authenticated `:4500` app-server for normal local proof.
- `.env` is user-owned and must not be rewritten.
- The app must not receive OpenAI keys, raw app-server bearer tokens, or raw audio.
- Existing unit tests are in `CodexDockTests`; there is no current `CodexDockUITests` target.
- Current UI state is mostly owned by `@MainActor ObservableObject` stores and SwiftUI views.
- Physical WebDriverAgent may be unavailable; this plan must make simulator proof useful without turning physical device automation into a blocker.

## 1.3 Architectural principles (rules we will enforce)

- One namespace, many call sites: views call a shared automation ID API, not literal strings scattered through the UI.
- Human accessibility and automation have separate jobs: labels/hints explain controls to people; identifiers give tests stable handles.
- Dynamic IDs are generated by typed helpers that make unsafe or unstable inputs harder to use.
- Rows and cards expose compact metadata that lets automation decide what it is looking at without reading pixels.
- UI tests should drive the same user-facing controls the user would use.
- The first implementation slice must cross the real app launch, generated Xcode project, simulator, and SwiftUI accessibility tree.

## 1.4 Known tradeoffs (explicit)

- The app will gain a small shared automation namespace. That is extra API surface, but it prevents hundreds of drifting string literals.
- Some existing views will need explicit accessibility grouping so automation sees useful containers instead of many loose text fragments.
- UI tests are slower than unit tests, so the plan keeps them as narrow end-to-end proof plus selector contract smoke tests, not a full business-logic test suite.
- Stable row identifiers can expose stable internal IDs like host IDs and thread IDs. That is acceptable only for non-secret, already-visible operational IDs; prompt and transcript content stays out.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

The app has SwiftUI screens for bootstrap relay setup, Dock, Archive, Relay settings, Session detail, Composer, request cards, and a global connectivity indicator. A few controls already define accessibility labels, values, or hints, especially the composer voice controls and Dock idle toggle.

## 2.2 What's broken / missing (concrete)

- There is no `accessibilityIdentifier` contract for automation.
- There is no UI-test target in `project.yml`.
- Existing labels are human-facing, not stable selectors.
- Most rows, cards, empty states, banners, tabs, and screen roots are not uniquely named in the accessibility tree.
- Automation cannot reliably tell which screen/state it is looking at without reading screenshots or visible text.
- Session rows and message cards do not expose stable row/card identifiers.
- Request-card controls share generic labels like `Send`, `Approve`, or `Decline` without a card-scoped identifier.
- The global connectivity indicator has a label, but no stable root identifier/value pair for automation to find across screens.

## 2.3 Constraints implied by the problem

- The fix must be architectural, not a one-off label pass.
- Selectors must be owned centrally so future UI work does not drift.
- The app must remain usable with VoiceOver and large Dynamic Type.
- Proof must run against the generated app target in a simulator, because the user's ask is specifically about making simulator testing easy and non-visual.
- The plan must not implement any code in this turn.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
# Research Grounding (external + internal "ground truth")

## External anchors (papers, systems, prior art)

- Apple SwiftUI `accessibilityIdentifier(_:)` — adopt as the automation selector hook for SwiftUI views. It is the platform-native way to attach stable identifiers to views for UI automation: <https://developer.apple.com/documentation/swiftui/view/accessibilityidentifier%28_%3A%29>
- Apple XCTest `XCUIElement` — adopt as the UI-test driving API. It represents an app UI element and supports state queries plus gestures like tap, type, swipe, and waits: <https://developer.apple.com/documentation/xctest/xcuielement>
- Apple XCTest `XCUIElementAttributes` — adopt because UI tests can query accessibility identifier plus element attributes. The plan should expose state through identifier/value/label traits instead of screenshots: <https://developer.apple.com/documentation/xctest/xcuielementattributes>
- Apple SwiftUI accessible descriptions — adopt labels, values, and hints for human accessibility. Use identifiers for automation and labels/values/hints for user meaning: <https://developer.apple.com/documentation/swiftui/accessible-descriptions>

## Internal ground truth (code as spec)

- Authoritative behavior anchors (do not reinvent):
  - `README.md` — defines the app-server/relay runbook, `rtk make app-test SIM='iPhone 17'`, physical-device caveats, and the existing manual VoiceOver/Dynamic Type checklist.
  - `Makefile` — owns `app`, `app-test`, simulator launch/config, device install/config, logs, and service targets. Future UI-test commands must stay Makefile-owned.
  - `project.yml` — XcodeGen source of truth. It currently defines `CodexDock`, `CodexDockApp`, and `CodexDockTests`, but no UI-test target.
  - `Package.swift` — SwiftPM currently exposes `CodexDock` and `CodexDockTests` only; simulator UI tests belong in generated Xcode project wiring, not SwiftPM.
  - `CodexDockApp/CodexDockApp.swift` — app entry point mounts `CodexDockBootstrapView`.
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift` — owns bootstrap states, discovered relay rows, manual relay fields, and pre-root connectivity overlay.
  - `CodexDock/Features/Dock/DockView.swift` — owns root `TabView`, Dock screen, controls, sections, session rows, and context menu actions.
  - `CodexDock/Features/Dock/DockSharedViews.swift` — owns shared Dock host summary, row, message, banner, and navigation chrome view helpers.
  - `CodexDock/Features/Archive/ArchiveView.swift` — owns Archive screen, refresh, archive rows, restore actions, and archive empty/unavailable states.
  - `CodexDock/Features/Hosts/HostsView.swift` — owns Relay settings rows, host editor, host/port fields, test/edit/remove/save actions, and validation errors.
  - `CodexDock/Features/Session/SessionDetailView.swift` — owns Session detail shell, detail header, live state, message filter, composer, and thread message list.
  - `CodexDock/Features/Session/ComposerView.swift` — already has human accessibility labels/hints/values for message, send, hold mic, and tap mic controls.
  - `CodexDock/Features/Session/ThreadMessageListView.swift` — owns message cards, request-card input, request-card actions, and detail empty states.
  - `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` — already has a human-facing accessibility label but no stable identifier/value split.
- Canonical path / owner to reuse:
  - New `CodexDock/Automation/AutomationID.swift` — proposed single source of truth for screen, control, row, card, banner, tab, and state identifiers.
  - New `View.codexAutomationID(_:)` helper in the same automation module — proposed thin wrapper around SwiftUI `accessibilityIdentifier(_:)` so call sites do not pass raw strings.
- Adjacent surfaces tied to the same contract family:
  - `project.yml` and generated `CodexDock.xcodeproj` — target/scheme changes must start in `project.yml`.
  - `Makefile` — if UI tests need a dedicated target command, add it here instead of asking implementers to run raw `xcodebuild`.
  - `README.md` — must document the automation-tree proof path and avoid screenshot-first testing guidance for this workflow.
  - `CodexDockTests/ComposerVoiceControlsPresentationTests.swift` — current proof surface for human accessibility copy; keep it for labels/hints while UI tests prove identifiers and screen navigation.
  - `CodexDockTests/DockStoreTestsProjection.swift`, `CodexDockTests/DockStoreTests.swift`, `CodexDockTests/ThreadDetailStoreTests.swift`, and `CodexDockTests/ServerRequestCardTests.swift` — existing behavior tests protect state/model logic; UI tests should not duplicate that business logic.
- Compatibility posture (separate from `fallback_policy`):
  - Clean additive cutover for identifiers: existing UI behavior stays, but every new selector must route through the canonical ID owner. No bridge or fallback selector registry.
- Existing patterns to reuse:
  - Existing SwiftUI view decomposition by screen/component — add identifiers at view boundaries rather than creating a separate automation view layer.
  - Existing `@MainActor ObservableObject` state stores — use their public view models to derive stable row/card IDs; do not duplicate state for automation.
  - Existing focused XCTest style — keep unit tests for logic and add narrow UI tests for real simulator tree driving.
  - Existing Makefile/XcodeGen ownership — route generated-project test changes through `project.yml` and `rtk make`.
- Prompt surfaces / agent contract to reuse:
  - `AGENTS.md` and README already define that simulator/device proof is Makefile-owned and that physical Mobile MCP can be blocked by WebDriverAgent. The plan should make simulator accessibility-tree proof the normal automation path.
- Native model or agent capabilities to lean on:
  - Simulator UI automation and XCTest accessibility queries — rely on the platform tree instead of screenshots or OCR.
  - Mobile MCP accessibility readback, when available — consume the same accessibility identifiers and values that XCTest uses.
- Existing grounding / tool / file exposure:
  - The assistant can read source files and run `rtk make app-test SIM='iPhone 17'` after implementation. That proof should expose tree-readable state, not require image interpretation.
- Duplicate or drifting paths relevant to this change:
  - Existing scattered `.accessibilityLabel(...)` calls are useful for people but must not become automation selectors.
  - Existing docs and past plan logs mention screenshots/manual visual proof; this plan must narrow its own proof to accessibility-tree automation and only use screenshots as supporting evidence.
  - Context-menu actions in Dock and Archive can become side doors if not identified by row/card scope.
- Capability-first opportunities before new tooling:
  - Use SwiftUI `accessibilityIdentifier`, `accessibilityLabel`, `accessibilityValue`, grouping, and XCTest queries before adding custom scripts.
  - Use `project.yml` + Xcode UI-test target before external runners.
  - Use store view-model IDs before inventing separate automation IDs for dynamic rows.
- Behavior-preservation signals already available:
  - `rtk swift test --filter ComposerVoiceControlsPresentationTests` protects voice-control labels/hints.
  - `rtk swift test --filter DockStoreTests` protects Dock, Archive, Hosts, and row behavior.
  - `rtk swift test --filter ThreadDetailStoreTests` protects Session detail, composer, live events, and request-card behavior.
  - `rtk make app-test SIM='iPhone 17'` is the generated-project test path that future UI tests should join or extend.

## Decision gaps that must be resolved before implementation

- none — repo evidence plus the user objective settle the key choices: use platform accessibility identifiers, centralize the ID contract, prove the simulator tree path early, and keep screenshots as support rather than primary automation.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
# Current Architecture (as-is)

## On-disk structure

- `CodexDockApp/CodexDockApp.swift` mounts `CodexDockBootstrapView` directly.
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift` handles pre-root setup:
  - `.starting`
  - `.discovering(relays:message:)`
  - `.ready(HostRegistry)`
  - `.failed(String)`
  - manual host and port fields
  - discovered relay selection rows
  - non-ready global connectivity overlay
- `CodexDock/Features/Dock/DockView.swift` contains both `CodexDockRootView` and the Dock screen:
  - `TabView` with Dock, Archive, and Relay tabs
  - Dock filter picker, search, sort, idle toggle
  - host summaries, error/empty banners, branch/newest sections, session rows, and row context actions
  - shared component types: `HostSummaryView`, `MappingFailureBanner`, `ActionErrorBanner`, `ScopeLoadFailureBanner`, `ScopeConflictBanner`, `DockMessageView`, and `DockRowView`
- `CodexDock/Features/Archive/ArchiveView.swift` owns Archive state rendering, archived rows, and restore actions.
- `CodexDock/Features/Hosts/HostsView.swift` owns Relay settings rows and host editor form.
- `CodexDock/Features/Session/SessionDetailView.swift` owns detail shell, header, live-state pills, message filter, composer, and message list.
- `CodexDock/Features/Session/ComposerView.swift` owns text input, send, hold mic, tap mic, voice status, and composer errors.
- `CodexDock/Features/Session/ThreadMessageListView.swift` owns event cards and request-card controls.
- `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` owns app-wide connectivity display.
- `CodexDockTests/**` contains unit tests and no UI-test target.
- `project.yml` defines generated targets for `CodexDock`, `CodexDockApp`, and `CodexDockTests`; no `CodexDockUITests` target exists.

## Control paths (runtime)

- Bootstrap starts discovery, loads saved relay config, and either enters root UI or shows setup/error UI.
- Root UI creates one shared `AppConnectivityStore` and passes it into Dock, Archive, Relay, and pushed detail flows.
- Dock loads real session rows from configured relay hosts, projects rows through filters/sort/idle visibility, and opens Session detail through `NavigationLink`.
- Archive loads archived rows and restores them through `ArchiveStore`.
- Relay settings edits the saved relay host list through `HostSettingsStore`.
- Session detail loads full thread events, resumes live updates, renders request cards, and sends composer/request responses through `ThreadDetailStore`.

## Object model + key abstractions

- `DockHostConfiguration`, `HostRegistry`, and `DockHostViewModel` identify relay hosts.
- `DockSnapshot`, `DockSectionViewModel`, `DockRowViewModel`, and `DockTabViewModel` identify Dock row families and tab counts.
- `ArchiveSnapshot` reuses the same `DockRowViewModel` and host summary model for archived rows.
- `HostSettingsRowViewModel` identifies saved relay rows.
- `ThreadDetailHeader`, `ThreadDetailSnapshot`, `ThreadEvent`, and `ServerRequestCard` identify detail rows, live state, and request-card actions.
- There is no automation-specific type. Existing view code uses ad hoc visible labels and string literals only where human accessibility already needed them.

## Accessibility state today

- Existing explicit labels/values:
  - Dock Add Host button label.
  - Dock Sort picker label.
  - Dock Idle button label, value, hint, and selected trait.
  - Archive Refresh label.
  - Relay Test All label.
  - Message field, Send button, hold mic, and tap mic labels/hints/values.
  - Clear message type filter label.
  - Global connectivity label containing label and message text.
- Missing stable identifiers:
  - App root, bootstrap root, root tabs, screen roots.
  - Dock/Archive/Relay/Detail screen states.
  - Every dynamic row/card family.
  - Every card-scoped action and text field.
  - Empty/error/banner states.
  - Context menu row actions.
  - Connectivity indicator identity/value split.

## Observability + failure behavior today

- When automation cannot find a control, it must infer from screenshots, visible text, or element order.
- Because selectors are not centralized, future UI text polish could break automation without compile-time or UI-test signal.
- Because no UI-test target exists, generated-project testing cannot currently prove real simulator tree navigation.
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
# Target Architecture (to-be)

## Canonical owner

Create `CodexDock/Automation/AutomationID.swift` as the only source of truth for automation identifiers.

The owner should define:

- Static screen and control IDs:
  - `codexdock.app.root`
  - `codexdock.bootstrap.root`
  - `codexdock.root.tabs`
  - `codexdock.dock.root`
  - `codexdock.archive.root`
  - `codexdock.relay.root`
  - `codexdock.session.root`
- Dynamic row/card builders:
  - Dock row by `hostID` + `threadID`
  - Archive row by `hostID` + `threadID`
  - Relay host row by `hostID`
  - Discovered relay row by discovered relay ID or endpoint ID
  - Message card by `ThreadEvent.id`
  - Request card by `ServerRequestCard.id`
- Child action builders:
  - request-card approve/decline/send/input by card ID
  - Dock row context actions by row ID and action kind
  - Archive restore by row ID
  - Relay row test/edit/remove by host ID
- State identifiers:
  - loading, empty, offline, error, stale, validation error, mapping failure, scope conflict, scope load failure.

Dynamic builders must use a shared `safeSegment(_:)` function that allows only stable printable ID segments. Anything outside the allowed segment alphabet must be percent-escaped or otherwise deterministically encoded. Call sites must not hand-roll dynamic identifiers.

## View integration contract

Add a small SwiftUI helper beside `AutomationID`:

```swift
extension View {
    func codexAutomationID(_ id: AutomationID) -> some View
}
```

The helper is intentionally thin. It should call SwiftUI `accessibilityIdentifier(_:)` and keep raw string access centralized. The plan does not require a framework, runtime registry, or debug overlay.

## Human accessibility contract

- Keep human-facing `accessibilityLabel`, `accessibilityHint`, `accessibilityValue`, and traits separate from automation identifiers.
- Use `accessibilityValue` for dynamic states automation needs to read:
  - connectivity phase and message
  - Dock filter/sort/idle state
  - row status and label where useful
  - Session live state
  - Composer send/voice readiness
  - Request-card status
  - Relay host test status
- Use grouping deliberately:
  - screen roots and rows/cards should be discoverable containers
  - nested controls inside cards must remain individually actionable
  - decorative icons stay `accessibilityHidden(true)` where they add noise

## UI-test architecture

- Add `CodexDockUITests` through `project.yml` as a generated Xcode UI-test target.
- The target should be `bundle.ui-testing`, source `CodexDockUITests`, and run against `CodexDockApp`; add a `CodexDock` dependency too if the UI-test target can import the framework ID contract directly.
- The generated `CodexDockApp` scheme should include `CodexDockTests` plus `CodexDockUITests` unless a separate Makefile-owned UI-test command is required.
- Add a focused UI test support layer inside that target:
  - `CodexDockUITestIDs` imports or mirrors the app's public `AutomationID` contract if target access allows it.
  - `CodexDockUITestApp` wraps `XCUIApplication` launch, waits, and element lookup.
  - Helpers use IDs and values, never visible copy as the primary selector.
- Wire the generated scheme so `rtk make app-test SIM='iPhone 17'` runs both unit tests and UI tests if that is practical. If mixed unit/UI execution is unreliable, add a Makefile-owned `app-ui-test` target and document it as the UI automation proof command.
- UI tests should run against simulator relay config generated by the existing service path. If no real rows are available, tests may use bootstrap/Relay settings paths that do not require real thread data, but the first full navigation proof must eventually run against a relay-backed Dock row.

## Automation proof posture

Use three proof layers, in this order:

1. Identifier contract tests: deterministic unit tests for `AutomationID` static strings, dynamic builders, and escaping. These are fast and protect drift in the selector API.
2. Simulator accessibility-tree smoke: generated-project UI tests that launch the real app, find root/bootstrap state, switch root tabs, exercise Relay settings form controls, and verify global connectivity values through `XCUIElement`.
3. Live relay navigation proof: a simulator UI test or Makefile-owned smoke that opens a real relay-backed Dock row into Session detail and verifies header, live state, composer, message list, and request-card hooks when those elements exist.

Do not add a fake second UI or in-app test menu. If deterministic data is needed later, prefer a relay-side fixture or existing app-server fixture boundary that still exercises the production SwiftUI screens. Any fixture must be explicitly named as test data, not completion evidence for the physical phone path.

## Identifier taxonomy

Identifiers should read like stable paths, not UI copy:

- screen roots: `codexdock.<screen>.root`
- controls: `codexdock.<screen>.<control>`
- rows: `codexdock.<screen>.row.<safe-host-id>.<safe-row-id>`
- request-card children: `codexdock.session.request.<safe-card-id>.<action>`
- banners/states: `codexdock.<screen>.state.<state-kind>`

Allowed dynamic segments are model IDs only after privacy review. Never use array index, visible title, summary, message body, command string, transcript, or error text as an identifier segment.

## Full-surface coverage map

Implementation is not complete until these user-visible surfaces have root/action/state coverage:

- Bootstrap setup: starting, discovering, failed, discovered relay row, manual host, manual port, connect.
- Root tabs: Dock, Archive, Relay.
- Dock: filter, search, sort, idle, host summary, banners, sections, session rows, row navigation, row-scoped actions.
- Archive: refresh, host summary, archived rows, restore, empty/unavailable/action-error states.
- Relay settings: test all, saved host rows, test/edit/remove, host editor, save/cancel, validation errors.
- Session detail: root/header, host/live/status pills, stale/error states, message filter, composer, voice controls, send, message cards, request-card controls.
- Global connectivity: one stable indicator identity and value on every screen where it appears.

## Screen coverage contract

Every first-class screen gets:

- root identifier
- state value
- primary actions
- empty/loading/error state identifiers
- row/card container identifiers
- row/card child action identifiers
- stable value fields that automation can assert without reading pixels

## Privacy and safety contract

- Never place secrets, bearer tokens, `OPENAI_API_KEY`, raw audio, raw prompt text, transcript text, full message body, or full JSON-RPC payloads in identifiers.
- Accessibility labels may describe controls and high-level state, but they should not expose large message bodies only for automation convenience.
- Message-card identifiers use event IDs, not event bodies.
- Request-card identifiers use card IDs, not command text or user prompt text.

## No-parallel-path stance

- No separate test-only UI.
- No separate selector file per screen.
- No screenshot-first automation runner.
- No raw string identifiers in view files once the central helper exists.
- No duplicated ID enum in UI tests unless import boundaries make direct app-module import impossible; if a mirror is required, it must be generated or checked with a focused test so drift fails loudly.
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
# Call-Site Audit (exhaustive change inventory)

## Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| Canonical IDs | `CodexDock/Automation/AutomationID.swift` | new file | No owner exists. | Add typed/static ID namespace and dynamic ID builders. | Prevent selector drift and raw strings. | `AutomationID` + `safeSegment(_:)` | New unit tests for ID formatting. |
| SwiftUI helper | `CodexDock/Automation/AutomationID.swift` or sibling file | `View.codexAutomationID(_:)` | Views would call `accessibilityIdentifier` directly or not at all. | Add thin helper. | Keeps call sites consistent and searchable. | `codexAutomationID` | UI tests use produced IDs. |
| App root | `CodexDockApp/CodexDockApp.swift` | `WindowGroup` content | Mounts bootstrap without root ID. | Mark app root or bootstrap root at first visible container. | Automation needs first stable wait point. | `AutomationID.App.root` | UI launch smoke. |
| Bootstrap root | `CodexDock/Features/Dock/CodexDockBootstrapView.swift` | `content`, `RelaySetupView` | Starting/discovering/failed states are visible but unnamed. | Add bootstrap root/state IDs and values. | Automation must know whether it is pre-root or in main tabs. | `AutomationID.Bootstrap.root/state` | Bootstrap UI test. |
| Discovered relay list | `CodexDock/Features/Dock/CodexDockBootstrapView.swift` | `relayList`, discovered relay `Button` | Rows selected by visible text/order only. | Add row IDs by discovered relay ID/endpoint and action ID. | Lets automation choose a relay without screenshots. | `AutomationID.Bootstrap.discoveredRelayRow(...)` | Bootstrap UI test. |
| Manual setup | `CodexDock/Features/Dock/CodexDockBootstrapView.swift` | `manualHostField`, `manualPortField`, Connect | Fields/buttons unnamed for automation. | Add IDs and validation/error state IDs. | Supports setup path and failure proof. | `manualHostField`, `manualPortField`, `manualConnectButton` | Bootstrap/Relay setup test. |
| Root tabs | `CodexDock/Features/Dock/DockView.swift` | `CodexDockRootView.body` `TabView` | Tabs use visible labels only. | Add TabView ID and per-tab IDs/values if possible. | Automation needs cross-screen navigation without label coupling. | `AutomationID.Root.tabs`, `Root.tab(.dock/.archive/.relay)` | Root navigation UI test. |
| Dock root | `CodexDock/Features/Dock/DockView.swift` | `DockView.body` | Screen root unnamed. | Add Dock root ID and state value. | Stable screen wait and state assertion. | `AutomationID.Dock.root` | Dock UI test. |
| Dock controls | `CodexDock/Features/Dock/DockView.swift` | filter picker, search, sort, idle | Some human labels exist; no stable IDs. | Add IDs and values for filter/search/sort/idle. | Automation can filter rows and read current mode. | `Dock.filterPicker`, `Dock.searchField`, `Dock.sortPicker`, `Dock.idleToggle` | Dock UI test. |
| Dock state cards | `CodexDock/Features/Dock/DockView.swift` | `DockMessageView`, `ActionErrorBanner`, `MappingFailureBanner`, `ScopeConflictBanner`, `ScopeLoadFailureBanner` | Generic reusable components without scoped IDs. | Add optional automation ID parameters or wrapper-level IDs at call sites. | Empty/error/banner states need specific identity. | `Dock.emptyState(...)`, `Dock.banner(...)` | Unit compile + UI state tests. |
| Dock host summaries | `CodexDock/Features/Dock/DockView.swift` | `HostSummaryView` | Host/status visible text only. | Add host summary ID/value by host ID and screen scope. | Automation can read host status without OCR. | `HostSummaryID(scope:hostID:)` | Dock/Archive UI tests. |
| Dock sections | `CodexDock/Features/Dock/DockView.swift` | `ForEach(sections)` | Section titles visible text only. | Add section IDs using section ID and screen scope. | Automation can find rows inside branch/newest groups. | `Dock.section(section.id)` | Dock UI test. |
| Dock rows | `CodexDock/Features/Dock/DockView.swift` | `NavigationLink`, `DockRowView` | Rows visible but unnamed; navigation by order/text. | Add row container/action ID by host ID + thread ID and values for status/origin. | Enables Dock-to-detail navigation. | `Dock.row(hostID:threadID:)` | Dock-to-detail UI test. |
| Dock row actions | `CodexDock/Features/Dock/DockView.swift` | `rowContextMenu(_:)` and any replacement action menu | Actions are context-menu-only, visible by labels only, and not row-scoped. | Add scoped action IDs if XCTest exposes context menu children reliably; otherwise replace the context-menu-only access with a small user-visible `Menu` or equivalent row action affordance that automation can open by row ID. | Prevents row actions from remaining an untestable side door. | `Dock.rowAction(rowID:action:)` | UI row-action test. |
| Archive root | `CodexDock/Features/Archive/ArchiveView.swift` | `ArchiveView.body` | Screen root unnamed. | Add Archive root ID/state value. | Stable screen wait. | `Archive.root` | Archive UI test. |
| Archive refresh | `CodexDock/Features/Archive/ArchiveView.swift` | refresh button | Human label only. | Add stable ID. | Automation refresh proof. | `Archive.refreshButton` | Archive UI test. |
| Archive rows | `CodexDock/Features/Archive/ArchiveView.swift` | `archiveRow(_:)`, `DockRowView` | Reuses row UI without archive-specific ID. | Add archive row and restore IDs by host ID + thread ID. | Restore action must be row-scoped. | `Archive.row(...)`, `Archive.restoreButton(...)` | Archive UI test. |
| Relay root | `CodexDock/Features/Hosts/HostsView.swift` | `HostsView.body` | Screen root unnamed. | Add Relay root ID/state value. | Stable tab wait. | `Relay.root` | Relay UI test. |
| Relay settings rows | `CodexDock/Features/Hosts/HostsView.swift` | `HostSettingsRow` | Rows and actions visible by text only. | Add row ID and Test/Edit/Remove IDs by host ID; status value. | Automation can manage saved relay rows. | `Relay.hostRow(...)`, `Relay.test/edit/remove(...)` | Relay UI test. |
| Relay editor | `CodexDock/Features/Hosts/HostsView.swift` | host editor, `HostTextField`, Save, Cancel | Form controls visible but unnamed. | Add IDs for host field, port field, save, cancel, validation banner. | Automation can add/edit host without visible-copy selectors. | `Relay.editor.*` | Relay UI test. |
| Connectivity indicator | `CodexDock/Features/Status/GlobalConnectivityIndicatorView.swift` | `GlobalConnectivityIndicatorView.body` | Human label combines status and message. | Add stable ID and value; keep label human-friendly. | Automation can read app-wide state everywhere. | `Connectivity.globalIndicator` + value | Root/Bootstrap UI tests. |
| Session root | `CodexDock/Features/Session/SessionDetailView.swift` | `SessionDetailView.body` | Pushed screen has title but no root ID. | Add root ID and values for host/thread/live state. | Automation can verify row navigation landed on correct detail. | `Session.root(threadID:)` | Dock-to-detail UI test. |
| Detail header | `CodexDock/Features/Session/SessionDetailView.swift` | `DetailHeaderView`, `DetailPill` | Header/pills visible only. | Add header/live/status/host IDs and values. | Automation can read live/stale state without pixels. | `Session.header`, `Session.livePill` | Thread detail UI test. |
| Message filter | `CodexDock/Features/Session/ThreadMessageListView.swift` | `MessageTypeFilterControl` | Menu selected by visible labels. | Add filter menu ID/value and clear ID. | Automation can change filters reliably. | `Session.messageFilter`, `Session.clearMessageFilter` | Thread detail UI test. |
| Composer | `CodexDock/Features/Session/ComposerView.swift` | message field, send, mic buttons, voice status | Human labels/hints exist; no stable IDs. | Add IDs and values while preserving labels/hints. | Composer is primary action surface. | `Composer.messageField`, `sendButton`, `holdMicButton`, `tapMicButton`, `voiceStatus` | UI + existing composer tests. |
| Message list | `CodexDock/Features/Session/ThreadMessageListView.swift` | `ThreadMessageListView`, `ThreadMessageCard` | Cards visible but unnamed. | Add list ID, empty-state IDs, card IDs by event ID, kind/status values. | Automation can inspect thread contents structurally. | `Session.messageList`, `Session.messageCard(eventID:)` | Thread detail UI test. |
| Request cards | `CodexDock/Features/Session/ThreadMessageListView.swift` | `requestControls`, `requestActions` | Card actions generic; input field generic. | Add card-scoped IDs for input, approve, decline, send, unsupported, status/error. | Automation can respond exactly as user would. | `RequestCard.*(cardID:)` | Request-card UI test + existing unit tests. |
| Shared cards | `CodexDock/Features/Dock/DockSharedViews.swift`, `ThreadMessageListView.swift` | `DockMessageView`, `DetailMessageView` | Reusable views have no ID parameter. | Add scoped optional automation ID parameters or apply at call site. | Avoid same empty-state ID on different screens. | Scope-specific IDs | Compile/UI tests. |
| Project config | `project.yml` | targets/schemes | No UI-test target. | Add `CodexDockUITests` target and scheme wiring. | Generated Xcode project must know UI tests. | XcodeGen source of truth | `rtk xcodegen generate --spec project.yml`, `rtk make app-test SIM='iPhone 17'`. |
| UI test files | `CodexDockUITests/**` | new target files | No UI tests exist. | Add launch smoke, root navigation, Dock-to-detail slice, Relay editor slice. | Proves non-screenshot automation path. | XCTest + `AutomationID` | Generated-project tests. |
| Makefile | `Makefile` | `app-test` or new target | `app-test` runs generated-project tests for existing scheme. | Ensure UI tests run through Makefile-owned command; add `app-ui-test` only if needed. | Avoid raw platform command workflow. | `rtk make app-test SIM='iPhone 17'` or `rtk make app-ui-test SIM='iPhone 17'` | Command proof. |
| README | `README.md` | verification/runbook sections | Mentions manual VoiceOver/Dynamic Type and screenshots. | Add automation-tree testing command and explain screenshot role as support only. | Future agents use the new contract correctly. | README runbook | Docs review. |

## Migration notes

* Canonical owner path / shared code path:
  * `CodexDock/Automation/AutomationID.swift` owns all identifiers and dynamic builders.
  * `View.codexAutomationID(_:)` is the only app-view call-site API for automation IDs.
* Deprecated APIs (if any):
  * None. This is additive, but raw string `accessibilityIdentifier(...)` in app views becomes disallowed by convention after the helper lands.
* Delete list (what must be removed; include superseded shims/parallel paths if any):
  * No existing automation registry to delete.
  * Do not preserve any test-only selector copy if direct import from `CodexDock` into `CodexDockUITests` works.
* Adjacent surfaces tied to the same contract family:
  * `project.yml`, `Makefile`, `README.md`, app views, UI-test target, and relevant unit tests.
* Compatibility posture / cutover plan:
  * Clean additive cutover. Existing UI behavior stays; selector ownership changes immediately to the central helper.
* Capability-replacing harnesses to delete or justify:
  * No OCR or screenshot interpretation harness should be added.
  * No external UI automation runner should be added before XCTest/Mobile MCP accessibility-tree paths are proven insufficient.
* Live docs/comments/instructions to update or delete:
  * `README.md` must document the new simulator automation path.
  * Add small code comments only at the `AutomationID` boundary if they prevent future raw-string drift.
* Behavior-preservation signals for refactors:
  * Existing Swift unit tests stay as logic proof.
  * New UI tests prove only simulator tree driving and selector contract.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope (include/defer/exclude/blocker question) |
| ---- | ------------- | ---------------- | ---------------------- | ------------------------------------- |
| Human labels | Existing `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint` calls | Preserve and augment | Avoid degrading VoiceOver while adding automation IDs. | include |
| Dynamic rows | `DockRowViewModel`, `HostSettingsRowViewModel`, `ThreadEvent`, `ServerRequestCard` | Stable ID builders from model IDs | Prevent order/text selectors. | include |
| Global state | `AppConnectivityStore` / `GlobalConnectivityIndicatorView` | Identifier + value split | Avoid parsing labels for state. | include |
| Shared cards | `DockMessageView`, `DetailMessageView`, banners | Scoped optional ID parameters | Avoid generic IDs reused on multiple screens. | include |
| Generated project | `project.yml` | XcodeGen target ownership | Prevent hand-edited project drift. | include |
| Make commands | `Makefile` | Makefile-owned simulator checks | Keep repo workflow consistent. | include |
| Screenshots | Prior docs/worklogs | Supporting evidence only | Prevent old screenshot-first proof from controlling this plan. | include for README clarification, exclude screenshot harness |
| Physical Mobile MCP | Physical device instructions | Simulator-first accessibility proof | Avoid blocking on WebDriverAgent for this plan. | defer physical proof |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
# Depth-First Phased Implementation Plan (authoritative)

> Rule: Section 7 is the execution checklist. Sections 5 and 6 define the destination and inventory, but implementation is complete only when the relevant phase checklist and exit criteria are complete. Build depth-first: prove one real generated-project simulator accessibility path first, then widen by screen family. Do not add screenshot/OCR infrastructure, hidden test UI, or a duplicate selector registry.

## Phase 1 — Canonical ID Contract And First Simulator Tree Proof

* Goal:
  * Prove the riskiest seam first: generated Xcode project wiring, app launch in the simulator, SwiftUI `accessibilityIdentifier` exposure, and `XCUIElement` lookup using a shared ID contract.
* Work:
  * Add the canonical `AutomationID` owner and SwiftUI helper, add the UI-test target through `project.yml`, and hook IDs into the smallest useful visible path: app/bootstrap/root, Dock root, global connectivity, Dock idle/search/sort controls, and Relay tab/root.
* Checklist (must all be done):
  * Add `CodexDock/Automation/AutomationID.swift` with static screen/control IDs, dynamic builder shape, and `safeSegment(_:)`.
  * Add `View.codexAutomationID(_:)` beside the ID owner.
  * Add focused unit tests for static IDs, dynamic row/card builders, and escaping.
  * Update `project.yml` with `CodexDockUITests` as a `bundle.ui-testing` target that runs against `CodexDockApp`; add `CodexDock` as a dependency if direct `AutomationID` import works.
  * Regenerate with `rtk xcodegen generate --spec project.yml`.
  * Add initial `CodexDockUITests` files for app launch, element waits, and ID-based lookup.
  * Add IDs to app/bootstrap/root/Dock/Relay roots, global connectivity indicator, Dock search/sort/idle controls, and Relay root.
  * Use `accessibilityValue` for connectivity state and Dock control state where automation must read state.
  * Ensure app-view call sites use `codexAutomationID(_:)`, not raw `accessibilityIdentifier(...)`.
  * Decide whether existing `rtk make app-test SIM='iPhone 17'` can run UI tests; if not, add a Makefile-owned UI-test target and document the exact command.
* Verification (required proof):
  * `rtk swift test --filter AutomationIDTests`
  * `rtk xcodegen generate --spec project.yml`
  * `rtk make app-test SIM='iPhone 17'` or the new Makefile-owned UI-test command if Phase 1 adds one.
* Docs/comments (propagation; only if needed):
  * Add one short code comment at the `AutomationID` boundary explaining that IDs are stable automation API and must not use visible text or sensitive content.
* Exit criteria (all required):
  * The simulator UI test launches the app and finds at least one real screen root by identifier.
  * The test reads global connectivity state through an element value, not screenshot text.
  * The test interacts with at least one Dock control by ID.
  * The generated Xcode project is regenerated from `project.yml`.
  * No app-view file added raw `accessibilityIdentifier(...)` calls outside the helper.
* Rollback:
  * Remove the UI-test target, helper, and first ID call sites as one unit if generated-project testing cannot launch. Do not leave a half-wired selector API.

## Phase 2 — Bootstrap, Root Tabs, Relay Settings, And Archive Surfaces

* Goal:
  * Expand the proven selector path across every non-session screen and every app setup/settings path that must be drivable without relying on real thread data.
* Work:
  * Add root/action/state IDs for bootstrap setup, root tabs, Relay settings, Archive, host summaries, shared empty/error states, and validation/action banners.
* Checklist (must all be done):
  * Add bootstrap IDs for starting/discovering/failed states, discovered relay rows, manual host field, manual port field, and Connect.
  * Add root tab IDs or stable tab accessors for Dock, Archive, and Relay.
  * Add Relay settings IDs for Test All, host rows, host row test/edit/remove, host editor fields, Save, Cancel, and validation errors.
  * Add Archive IDs for root, refresh, host summaries, empty/unavailable states, archived rows, and restore buttons.
  * Update shared `DockMessageView`, `DetailMessageView`, banners, and host summaries so call sites can pass scoped IDs without creating generic duplicate IDs.
  * Add UI tests that navigate tabs and drive Relay settings controls by ID.
  * Keep existing store tests focused on behavior; do not move business logic into UI tests.
* Verification (required proof):
  * `rtk swift test --filter DockStoreTests`
  * `rtk swift test --filter DockConfigurationTests`
  * `rtk make app-test SIM='iPhone 17'` or the Phase 1 UI-test command.
* Docs/comments (propagation; only if needed):
  * Update README only if Phase 2 changes the command name or setup path needed for UI automation.
* Exit criteria (all required):
  * Automation can identify whether the app is in bootstrap, root Dock, root Archive, or root Relay.
  * Automation can edit Relay host/port fields and observe validation/action state by ID/value.
  * Archive root, refresh, row, restore, empty, and unavailable states have scoped IDs even when no archived rows are present.
  * Shared reusable message/banner views do not emit duplicate unscoped identifiers across screens.
* Rollback:
  * Revert the Phase 2 IDs and UI tests together if the root/tab wiring creates unstable accessibility behavior.

## Phase 3 — Dock Row Families And Row-Scoped Actions

* Goal:
  * Make the main operating screen drivable at row level: automation can find a specific Dock row, read its state, open it, and target row-scoped actions without depending on row order or visible copy.
* Work:
  * Apply dynamic row/section IDs to Dock sections and rows, add values for status/origin/label where useful, and make row actions automation-drivable.
* Checklist (must all be done):
  * Add Dock section IDs using stable section IDs.
  * Add Dock row IDs by host ID + thread ID at the `NavigationLink` or row container that automation taps.
  * Add row accessibility values for status, origin family, label presence, and host/thread identity where safe.
  * Add Dock state IDs for configuration error, idle/loading/offline/error, empty, mapping failure, scope conflict, scope load failure, and action error.
  * Add row-scoped IDs for Mark Watch, Clear Label, Archive, Color choices, and Clear Color.
  * If XCTest cannot reliably access existing context menu children, replace the context-menu-only path with a small user-visible `Menu` or equivalent row action affordance that preserves the same actions and can be opened by row ID.
  * Add UI proof that opens a real relay-backed Dock row to Session detail when a row exists.
* Verification (required proof):
  * `rtk swift test --filter DockStoreTests`
  * `rtk swift test --filter DockStoreTestsProjection`
  * `rtk make app-test SIM='iPhone 17'` or the Phase 1 UI-test command.
* Docs/comments (propagation; only if needed):
  * No broad docs expected unless the command/proof path changes.
* Exit criteria (all required):
  * Dock rows are addressable by stable model IDs, not visible title/order.
  * Dock row status and origin are exposed as structured accessibility state.
  * The Dock-to-detail navigation path is tested through an ID-based row tap against the simulator app when a relay-backed row is available.
  * Missing real rows are reported as an exact environment blocker, not silently treated as pass.
  * Row action coverage is implemented through IDs on the existing context menu or through a small user-visible action affordance; a platform limitation is not treated as completion.
* Rollback:
  * Revert Dock row/action IDs and tests if they create unusable row accessibility grouping. Keep Phase 1-2 screen/control IDs intact if stable.

## Phase 4 — Session Detail, Composer, Message Cards, And Request Cards

* Goal:
  * Make the full thread interaction surface automation-drivable: detail state, composer actions, voice controls, message filtering, message cards, and request-card responses.
* Work:
  * Add scoped IDs and values to `SessionDetailView`, `DetailHeaderView`, `MessageTypeFilterControl`, `ComposerView`, `ThreadMessageListView`, message cards, and request-card controls.
* Checklist (must all be done):
  * Add Session root ID by thread ID and values for host/thread/live state.
  * Add header, host pill, live pill, and status pill IDs/values.
  * Add stale/error/detail empty-state IDs.
  * Add message filter menu ID/value and clear-filter ID.
  * Add Composer IDs for message field, Send, hold mic, tap mic, voice status, composer error, and voice error.
  * Preserve existing human labels/hints/values for voice controls.
  * Add message-list ID and message-card IDs by event ID with kind/live/request status values.
  * Add request-card IDs for card container, input field, approve, decline, send input, unsupported state, busy/resolved/failed status, and card error.
  * Ensure request-card identifiers use card IDs, not prompt text, command text, or message bodies.
  * Add UI proof that verifies Session detail hooks after Dock row navigation or through a Makefile-owned live-detail smoke.
* Verification (required proof):
  * `rtk swift test --filter ThreadDetailStoreTests`
  * `rtk swift test --filter ComposerVoiceControlsPresentationTests`
  * `rtk swift test --filter ServerRequestCardTests`
  * `rtk make app-test SIM='iPhone 17'` or the Phase 1 UI-test command.
* Docs/comments (propagation; only if needed):
  * Add a short request-card ID comment only if needed to explain the no-prompt-text rule.
* Exit criteria (all required):
  * Automation can identify the Session detail root and read live state without screenshot interpretation.
  * Automation can type into the composer and find Send by ID.
  * Voice controls keep their existing human accessibility labels/hints and gain stable IDs.
  * Message cards and request cards are addressable by stable IDs.
  * Request actions are card-scoped so automation cannot approve or decline the wrong card by generic button text.
  * No message body, transcript, command text, prompt text, secret, raw audio, or full JSON-RPC payload appears in an automation identifier.
* Rollback:
  * Revert Session-detail IDs and UI tests as one unit if grouping breaks nested controls. Keep earlier screen/root/control IDs if they remain stable.

## Phase 5 — Runbook, Final Proof, And Drift Guardrails

* Goal:
  * Make the new automation contract discoverable for future agents and verify the full non-screenshot simulator workflow end to end.
* Work:
  * Update README/commands, run the relevant checks, and close any drift between docs, project config, tests, and app-view call sites.
* Checklist (must all be done):
  * Update `README.md` with the exact simulator automation command and explain that accessibility-tree readback is primary proof for this workflow.
  * Keep screenshot guidance as supporting evidence only, not the primary selector strategy.
  * Ensure `project.yml`, generated project behavior, Makefile target, and README command text agree.
  * Run a final search for raw `accessibilityIdentifier(` in app view files and replace any direct call with `codexAutomationID(_:)` unless it is inside the helper.
  * Run the full relevant verification set.
  * Record any physical-device automation limitation as a non-blocking physical follow-up, not a blocker for simulator automation readiness.
* Verification (required proof):
  * `rtk swift test`
  * `rtk xcodegen generate --spec project.yml`
  * `rtk make app-test SIM='iPhone 17'`
  * `rtk make app SIM='iPhone 17'` if UI-test/project wiring changes affect installed app behavior.
* Docs/comments (propagation; only if needed):
  * `README.md` must name the exact command and the expected proof shape.
  * No new standalone architecture docs are required after implementation unless an implementation worklog is being kept for that turn.
* Exit criteria (all required):
  * Future agents can run one documented command to inspect/drive the simulator UI through the accessibility tree.
  * Every first-class screen and primary user action listed in Section 5 has an ID/value contract.
  * The final verification commands either pass or report exact environment blockers.
  * Physical WebDriverAgent availability is not required for this plan's completion.
  * No duplicate selector registry, screenshot-first harness, hidden test UI, or raw-string selector spread remains.
* Rollback:
  * If final proof exposes systemic selector instability, revert only the unstable screen family and keep the canonical ID owner plus proven earlier phases. Repair the phase plan before retrying broad expansion.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy

## 8.1 Verification by layer

- ID contract:
  - `rtk swift test --filter AutomationIDTests`
- Existing app behavior:
  - `rtk swift test --filter DockStoreTests`
  - `rtk swift test --filter DockConfigurationTests`
  - `rtk swift test --filter ThreadDetailStoreTests`
  - `rtk swift test --filter ComposerVoiceControlsPresentationTests`
  - `rtk swift test --filter ServerRequestCardTests`
- Generated project and simulator UI automation:
  - `rtk xcodegen generate --spec project.yml`
  - `rtk make app-test SIM='iPhone 17'`
  - A new Makefile-owned UI-test command only if `app-test` cannot reliably own UI tests.
- Installed simulator behavior:
  - `rtk make app SIM='iPhone 17'` when target/project wiring changes affect the installed app.

## 8.2 Proof that does not count by itself

- Screenshot-only proof does not prove this plan.
- Preview rows do not prove live Dock navigation.
- Physical-device automation is not required for this plan and must not block simulator automation readiness.
- Raw `xcodebuild`, raw `simctl install`, and raw `devicectl` are not normal proof commands for this repo.
- A fixture relay, if ever added, proves selector coverage only. It is not physical phone-path completion evidence.

## 8.3 Final plan evidence shape

Implementation closeout should report:

- exact command(s) run
- whether `rtk make app-test SIM='iPhone 17'` owns UI tests or a new Makefile target was added
- simulator name and any exact blocker if Xcode/simulator/services are missing
- which screens were driven through the accessibility tree
- any known platform limitation, especially context-menu automation or physical WebDriverAgent availability

# 9) Rollout, Migration, And Cleanup

## 9.1 Rollout posture

This is a clean additive UI automation contract. Existing UI behavior should remain the same, but the view code gains stable identifiers and values.

## 9.2 Migration work

- Add the central ID owner before broad call-site adoption.
- Migrate each screen family to the central helper.
- Add the UI-test target through `project.yml`; regenerate the project.
- Keep existing unit tests as behavior proof; do not replace them with UI tests.
- Update README after the command and proof path are known.

## 9.3 Cleanup and side-door closure

- Do not leave raw selector strings spread through views.
- Do not keep a second selector registry in UI tests unless direct app-module import is impossible and drift is checked.
- Do not add hidden UI, OCR, screenshot-first tooling, or a runtime debug overlay.
- Do not add stale docs that keep screenshot interpretation as the recommended automation path.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass
- Reviewers:
  - self-integrator
  - native explorer agents not used because this session's tool rules only allow subagent spawning when the user explicitly asks for it
- Scope checked:
  - frontmatter, TL;DR, Sections 0 through 9, helper blocks, phase plan, verification, rollout, and decision posture
- Findings summary:
  - The TL;DR originally said the first proof was a Dock happy-path UI test, while Section 7 correctly puts full Dock row navigation in Phase 3. That was a real sequencing mismatch.
  - The plan consistently chooses a central `AutomationID` owner, SwiftUI accessibility identifiers, generated-project UI tests, Makefile-owned commands, simulator-first proof, and screenshot support only.
  - The plan consistently treats physical WebDriverAgent availability as non-blocking for this architecture change.
- Integrated repairs:
  - Reworded the TL;DR plan sentence so Phase 1 is a real simulator accessibility-tree proof and Dock row navigation belongs to Phase 3.
  - Added Sections 8 and 9 so verification, rollout, and cleanup do not live only inside phase prose.
  - Tightened Dock row action coverage so context-menu automation limits require a user-visible automatable affordance instead of becoming a waived side door.
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

# 10) Decision Log

- 2026-05-29 — North Star accepted from user objective: make the full UI drivable through automation-accessible tree state rather than screenshot interpretation. Consequence: the plan must cover every first-class screen and primary action, not just a small UI polish pass.
- 2026-05-29 — Use SwiftUI `accessibilityIdentifier(_:)` and XCTest `XCUIElement` as the platform path. Consequence: no OCR, screenshot-first runner, or hidden debug UI.
- 2026-05-29 — Create one canonical `AutomationID` owner. Consequence: app views use `codexAutomationID(_:)`; raw selector strings outside the helper become drift risks to remove.
- 2026-05-29 — Add UI-test wiring through `project.yml` and Makefile-owned commands. Consequence: do not hand-edit `CodexDock.xcodeproj` and do not make raw `xcodebuild` the normal workflow.
- 2026-05-29 — Simulator accessibility-tree proof is the completion path for this architecture change. Consequence: physical WebDriverAgent failure is a physical-device follow-up, not a blocker for this plan.
- 2026-05-29 — Implementation completed through the accessibility tree path. Consequence: app views now use the shared `AutomationID` helper, `project.yml` owns `CodexDockUITests`, and `README.md` documents accessibility-tree proof as primary simulator evidence.
- 2026-05-29 — Visible Dock row action affordance rejected after user review. Consequence: Dock cards keep their original visual shape; row actions remain on the existing context menu with stable action IDs for automation instead of a new on-card button.
- 2026-05-29 — Local simulator name `iPhone 17` was ambiguous. Consequence: verification used simulator UDID `BAD95C8E-3E57-4818-9B90-E4ED22593B4B`; the documented command remains `rtk make app-test SIM='iPhone 17'` for machines with a unique simulator name.

# 11) Implementation Evidence

- Worklog: `docs/CODEX_DOCK_UI_AUTOMATION_ACCESSIBILITY_HOOKS_2026-05-29_WORKLOG.md`
- `rtk swift test` passed with 224 tests executed, 5 skipped, and 0 failures.
- `rtk make app-test SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` passed; latest result bundle: `.codex-dock/DerivedData/Logs/Test/Test-CodexDockApp-2026.05.29_08-11-01--0500.xcresult`.
- `rtk make app SIM=BAD95C8E-3E57-4818-9B90-E4ED22593B4B` passed.
- Raw platform selector search found `accessibilityIdentifier(...)` only inside `CodexDock/Automation/AutomationID.swift`.
