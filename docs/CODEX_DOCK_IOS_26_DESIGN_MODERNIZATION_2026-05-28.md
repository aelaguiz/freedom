---
title: "Codex Dock - iOS 26 Design Modernization - Architecture Plan"
date: 2026-05-28
status: active
fallback_policy: forbidden
owners: [aelaguiz]
reviewers: [Codex]
doc_type: architectural_change
related:
  - docs/CODEX_DOCK_IOS_26_DESIGN_REFERENCES_2026-05-28.md
  - docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md
  - docs/EPIC_CODEX_DOCK_MVP_2026-05-27.md
  - docs/mockups/codex-dock-2026-05-27-v2/01-dock-normal.png
  - docs/mockups/codex-dock-2026-05-27-v2/02-dock-needs-me.png
  - docs/mockups/codex-dock-2026-05-27-v2/03-session-detail.png
  - docs/mockups/codex-dock-2026-05-27-v2/04-session-dictation-inline.png
  - docs/mockups/codex-dock-2026-05-27-v2/05-archive.png
  - docs/mockups/codex-dock-2026-05-27-v2/06-hosts.png
---

# TL;DR

- Outcome: Codex Dock keeps its current mobile-operations shape, but its SwiftUI shell, navigation, controls, composer, and surfaces are modernized for iOS 26 with Apple-standard controls, restrained Liquid Glass, and explicit light/dark/accessibility support.
- Problem: The current app uses custom headers, hidden navigation chrome, custom search fields, plain card backgrounds, and scattered styling. It is functional, but it does not let the iOS 26 design system carry navigation, toolbar, search, glass, or appearance adaptation.
- Approach: Raise the app and Swift package to iOS 26.0, centralize semantic visual tokens and direct iOS 26 control helpers, then restore system navigation/toolbars/search, then apply Liquid Glass only to the control/navigation layer, then polish content cards and accessibility without changing the product model.
- Plan: Prove the design system seam in one vertical Dock slice, expand it to Thread detail and composer controls, then carry the same pattern across Archive, Relay, and bootstrap.
- Non-negotiables: iOS 26.0 is the deployment floor, no iOS 17-25 compatibility branch, no glass content-card blanket, no hard-coded light or dark palette, no duplicate visual systems, no hidden navigation fork, and no visual change that makes the app unrecognizable.

<!-- arch_skill:block:planning_passes:start -->
<!--
arch_skill:planning_passes
deep_dive_pass_1: done 2026-05-28
external_research_grounding: done 2026-05-28 (Apple-primary iOS 26/Liquid Glass research saved in docs/CODEX_DOCK_IOS_26_DESIGN_REFERENCES_2026-05-28.md)
deep_dive_pass_2: done 2026-05-28
recommended_flow: deep dive -> external research grounding -> deep dive again -> phase plan -> implement
note: This block tracks stage order only. It never overrides readiness blockers caused by unresolved decisions.
-->
<!-- arch_skill:block:planning_passes:end -->

<!-- arch_skill:block:auto_plan_receipts:start -->
{
  "version": 1,
  "digest": "sha256:0b04d2db3469665128319d5f561fd1c73909ddc93b5b8a1445931ac11137b860",
  "receipts": [
    {
      "stage": "research",
      "command": "research",
      "status": "complete",
      "started_at": "2026-05-28T12:01:56Z",
      "command_ref_hash": "sha256:5ad5dc9efcb3c7d0d42e1d9014e3ee66fd24b8d2f1c85eef2c5ee96543e05c96",
      "doc_hash_before": "sha256:91b3391a99a618a6343119494fa29d9a9feed7f3ecfb1d2de2f776dd6703e985",
      "completed_at": "2026-05-28T12:02:33Z",
      "doc_hash_after": "sha256:f308d62365d8ff7efecb415a0b0d214f585a09f5af333bb72ee5931ac7158cea"
    },
    {
      "stage": "deep-dive-pass-1",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T12:02:36Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:f308d62365d8ff7efecb415a0b0d214f585a09f5af333bb72ee5931ac7158cea",
      "completed_at": "2026-05-28T12:04:39Z",
      "doc_hash_after": "sha256:044869ea1d5f00dbde97abf9ba133bf810c48455056983b68da26691c4412964"
    },
    {
      "stage": "deep-dive-pass-2",
      "command": "deep-dive",
      "status": "complete",
      "started_at": "2026-05-28T12:04:44Z",
      "command_ref_hash": "sha256:c06af6026c9d59dec9c11dae8319ead3a2864dd67c05a2b8b07392ce1c62597a",
      "doc_hash_before": "sha256:044869ea1d5f00dbde97abf9ba133bf810c48455056983b68da26691c4412964",
      "completed_at": "2026-05-28T12:05:02Z",
      "doc_hash_after": "sha256:5b9a868db4f98d6eec2892be0f921ffb1459fc2fe3d28e88ea1a0474987fea48"
    },
    {
      "stage": "phase-plan",
      "command": "phase-plan",
      "status": "complete",
      "started_at": "2026-05-28T12:05:08Z",
      "command_ref_hash": "sha256:1ce4687beab44819933a8a404a02b8e1345823a7a996f7d651f3dd25a0c54aa3",
      "doc_hash_before": "sha256:5b9a868db4f98d6eec2892be0f921ffb1459fc2fe3d28e88ea1a0474987fea48",
      "completed_at": "2026-05-28T12:06:04Z",
      "doc_hash_after": "sha256:038026e361a25b4fb54e55ce74b03a593ed723339f14a374b0cb48fedde9817a"
    },
    {
      "stage": "consistency-pass",
      "command": "consistency-pass",
      "status": "complete",
      "started_at": "2026-05-28T12:06:13Z",
      "command_ref_hash": "sha256:439e1ccf2a90587bbec572e8bf46c4e08f16c9c81c75fcf835f736db479d3d74",
      "doc_hash_before": "sha256:038026e361a25b4fb54e55ce74b03a593ed723339f14a374b0cb48fedde9817a",
      "completed_at": "2026-05-28T12:11:13Z",
      "doc_hash_after": "sha256:aca5e0861601b27ea95f2a2215eba0bf5fc321c53e1229797add2e5f046539ff"
    }
  ]
}
<!-- arch_skill:block:auto_plan_receipts:end -->

# 0) Holistic North Star

## 0.1 The claim (falsifiable)

After this plan is implemented, a user who knows the current Codex Dock should
still recognize every major screen and workflow, but the app should look and
feel like it belongs on iOS 26: standard navigation and toolbar chrome, system
search, restrained Liquid Glass controls, semantic content cards, and verified
light-mode, dark-mode, and accessibility behavior.

## 0.2 In scope

- Restore and modernize the SwiftUI app shell around the existing top-level
  tabs: Dock, Archive, and Relay.
- Replace custom top headers/actions with standard navigation titles and
  toolbar items while keeping real workflows intact.
- Replace the custom Dock search row with a system search pattern if behavior
  remains a filter over the Dock feed.
- Add a single shared visual-system owner for semantic backgrounds, content-card
  treatment, status chips, control treatment, and iOS 26 glass helpers.
- Apply Liquid Glass only to navigation/control surfaces: toolbars, primary
  actions, compact control clusters, and composer controls touched by this
  plan.
- Keep content cards readable and semantic rather than glass-heavy.
- Verify and preserve system light mode, dark mode, Increased Contrast, Reduced
  Transparency, Reduce Motion, Dynamic Type, and VoiceOver behavior.
- Respect the user's iOS system appearance. The app must render correctly in
  system Light Mode and Dark Mode without a custom app theme switcher or forced
  color scheme.
- Raise and keep the app deployment floor at iOS 26.0 in `Package.swift`,
  `project.yml`, and the generated Xcode project.

## 0.3 Out of scope

- Replacing the Codex Dock product model, top-level tabs, thread list, detail
  timeline, composer, archive, or relay setup flows.
- Adding new product features such as AIMGR account rotation, Claude backend
  support, global search as a new tab, notifications, widgets, or telemetry.
- Making every card or row Liquid Glass.
- Introducing custom renderers or compatibility shims that imitate Liquid Glass
  outside the iOS 26 system APIs.
- Preserving iOS 17-25 deployment support in this modernization path.
- Building visual-golden or screenshot-diff infrastructure as the main proof.
- Custom theme picker, dark-only design, light-only design, or forcing
  `.preferredColorScheme`.
- App icon redesign or Icon Composer asset work. This can be a named follow-up,
  but it is not required to modernize the app UI surfaces requested here.

## 0.4 Definition of done (acceptance evidence)

- Apple reference guidance is saved in
  `docs/CODEX_DOCK_IOS_26_DESIGN_REFERENCES_2026-05-28.md`.
- `Package.swift`, `project.yml`, and generated Xcode project settings target
  iOS 26.0.
- `rtk xcodegen generate --spec project.yml` has been run after the target
  change.
- The implemented app still builds and launches through the generated Xcode
  project.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
  passes after UI/project changes.
- Relevant Swift tests pass for touched behavior:
  `rtk swift test --filter DockStoreTests` for Dock/archive/host state and
  `rtk swift test --filter ThreadDetailStoreTests` for thread detail/composer.
- Manual or screenshot review covers Dock, Thread detail, Archive, Relay, and
  bootstrap on `iPhone 17` in both light mode and dark mode.
- Dock, Thread detail, Composer, Request cards, Archive, Relay, bootstrap,
  empty/error/offline states, labels, rails, and status colors are checked in
  both system Light Mode and Dark Mode on `iPhone 17`.
- Accessibility review covers Dynamic Type, VoiceOver labels, Reduced
  Transparency, Increased Contrast, and Reduce Motion for changed control/glass
  behavior.
- Existing relay path and app-server behavior remain unchanged.

## 0.5 Key invariants (fix immediately if violated)

- The app remains an operations board, not a marketing page or decorative demo.
- The existing three-tab navigation model remains recognizable.
- Liquid Glass is a functional control/navigation layer, not a content-card
  skin.
- System appearance settings own light/dark behavior; no fixed palette may
  fight system appearance.
- Status and label meaning must never rely on color alone.
- iOS 26 APIs may be used directly because the app no longer supports iOS
  17-25.
- Do not add `#available(iOS 26, *)` branches for the core visual
  modernization; the minimum target is iOS 26.0.
- Visual helper APIs must be single-source and reusable; individual screens must
  not invent parallel glass/color/card systems.
- No secrets, raw app-server tokens, or OpenAI keys move into the iPhone app as
  part of visual work.

# 1) Key Design Considerations (what matters most)

## 1.1 Priorities (ranked)

1. Preserve the existing product shape and workflows.
2. Keep a clean iOS 26-only implementation with no old-OS compatibility layer.
3. Respect Apple iOS 26 design guidance through standard SwiftUI components
   before custom effects.
4. Respect light mode, dark mode, accessibility appearance settings, and
   readable contrast.
5. Use Liquid Glass sparingly where it clarifies controls and navigation.
6. Centralize visual rules so Dock, Archive, Relay, bootstrap, and Thread detail
   do not drift.
7. Keep verification practical: builds, relevant store tests, and focused
   simulator/manual review.

## 1.2 Constraints

- `Package.swift` and `project.yml` are being raised to iOS 26.0 as part of
  this plan.
- iOS 26 APIs such as `glassEffect`, `.buttonStyle(.glass)`, and newer tab or
  toolbar behavior should be used directly after the deployment target cutover.
- The app connects to the relay at `ws://192.168.50.117:4510` for the normal
  local path; visual work must not disturb service routing.
- UI code is SwiftUI under `CodexDock/Features/**` plus app target wiring under
  `CodexDockApp` and `project.yml`.
- `project.yml` is the XcodeGen source of truth for app target, Info.plist,
  permissions, and asset wiring.

## 1.3 Architectural principles (rules we will enforce)

- Standard component first: use SwiftUI system navigation, toolbar, search,
  tab, menu, sheet, and button APIs before custom wrappers.
- One visual-system owner: shared style helpers own semantic surfaces, glass
  usage, and card/control treatment.
- Clean iOS 26 cutover: no compatibility helpers, old-OS materials path, or
  fake glass renderer.
- Content stays content: rows, transcript cards, request cards, and relay forms
  keep readable semantic surfaces.
- Appearance-safe colors: use semantic colors and system backgrounds, not fixed
  light-only or dark-only values.
- Verification follows risk: app build plus focused store tests and manual
  simulator appearance checks.

## 1.4 Known tradeoffs (explicit)

- Dropping iOS 17-25 support removes the availability-helper complexity and
  makes the design implementation easier to reason about. The tradeoff is that
  older devices/OS installs are intentionally outside support for this app.
- Restoring system navigation chrome will change vertical rhythm and title
  placement. This is intended, but the Dock content and main actions must remain
  familiar.
- Not making content cards glass is less flashy, but it follows Apple's
  hierarchy guidance and protects scanability in long lists.
- Manual light/dark/accessibility review is required because unit tests cannot
  prove that Liquid Glass and system appearance behavior are visually right.

# 2) Problem Statement (existing architecture + why change)

## 2.1 What exists today

Codex Dock is a SwiftUI app with:

- `TabView` root for Dock, Archive, and Relay.
- Each screen wraps a `NavigationStack`, then hides the iOS navigation bar
  through `dockNavigationChrome()`.
- Custom top headers provide large titles and icon buttons.
- Dock search is a custom `HStack` with a `TextField`.
- Content uses semantic-ish grouped backgrounds and `.background` card fills.
- Buttons use `.bordered`, `.borderedProminent`, `.borderless`, and `.plain`.
- The app already uses many system foreground styles and grouped backgrounds,
  which is a good base for light and dark mode.

## 2.2 What is broken / missing (concrete)

- The app hides system navigation chrome, so iOS 26 cannot apply standard
  toolbar/navigation glass treatment.
- Header actions are hand-placed instead of living in `.toolbar` groups.
- Dock search is custom, so it misses the latest system search behavior.
- Card/control styling is repeated across feature files instead of using one
  design owner.
- The app does not have an explicit light/dark/accessibility visual contract for
  future glass work.
- The current UI looks functional but not current with Apple's iOS 26 visual
  system.

## 2.3 Constraints implied by the problem

- The modernization must be incremental and recognizable.
- The implementation must be code-grounded in existing SwiftUI feature files.
- iOS 26-specific APIs can be used directly after the deployment target is
  raised.
- The plan must avoid broad product redesign and focus on visual/system
  modernization.
- Completion needs visual/manual proof in system appearances, not only tests.

# 3) Research Grounding (external + internal "ground truth")

<!-- arch_skill:block:research_grounding:start -->
## 3.1 External anchors (papers, systems, prior art)

- Apple "What's new in iOS 26" -
  https://developer.apple.com/ios/whats-new/ - adopt as the platform baseline:
  iOS 26 introduces a new design system centered on Liquid Glass and updated
  standard components.
- Apple HIG: Materials -
  https://developer.apple.com/design/human-interface-guidelines/materials -
  adopt the core hierarchy rule: Liquid Glass is for controls and navigation,
  while standard materials belong in the content layer.
- Apple HIG: Color -
  https://developer.apple.com/design/human-interface-guidelines/foundations/color/ -
  adopt sparse color use on Liquid Glass. Use accent/background color for true
  emphasis and keep labels/symbols legible across light and dark content.
- Apple HIG: Buttons -
  https://developer.apple.com/design/human-interface-guidelines/buttons -
  adopt 44x44 pt minimum hit regions, built-in press states, semantic button
  roles, and only one or two prominent buttons per view.
- Apple HIG: Tab bars -
  https://developer.apple.com/design/human-interface-guidelines/tab-bars -
  adopt top-level navigation semantics for Dock, Archive, and Relay; reject
  tab-bar actions.
- Apple HIG: Toolbars -
  https://developer.apple.com/design/human-interface-guidelines/toolbars -
  adopt standard toolbar grouping and symbol-first common actions.
- Apple HIG: Search fields and Searching -
  https://developer.apple.com/design/human-interface-guidelines/search-fields
  and https://developer.apple.com/design/human-interface-guidelines/searching -
  adopt system search for the Dock's local session filtering surface.
- Apple SwiftUI updates -
  https://developer.apple.com/documentation/updates/swiftui - adopt
  direct iOS 26 usage of `glassEffect(_:in:)`, `.buttonStyle(.glass)`,
  `ToolbarSpacer`, `scrollEdgeEffectStyle(_:for:)`,
  `backgroundExtensionEffect()`, `tabBarMinimizeBehavior(_:)`, search-role tabs,
  and tab-view bottom accessories only where they fit this app.
- Apple SwiftUI Liquid Glass docs -
  https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views,
  https://developer.apple.com/documentation/swiftui/glass,
  https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29,
  https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass,
  https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent,
  https://developer.apple.com/documentation/swiftui/glasseffectcontainer, and
  https://developer.apple.com/documentation/swiftui/view/glasseffectid%28_%3Ain%3A%29 -
  adopt system APIs for any custom glass; reject fake blur/tint stacks.
- Apple Landmarks Liquid Glass sample -
  https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass -
  adopt as implementation precedent for system-provided toolbar glass, grouped
  toolbar controls, custom glass used sparingly, Icon Composer awareness, and
  content extending behind system structures only when it serves the content.
- WWDC25 "Meet Liquid Glass" -
  https://developer.apple.com/videos/play/wwdc2025/219/ - adopt the design
  principle that glass is a dynamic adaptive material and should not be placed
  inside or on top of other glass layers.
- WWDC25 "Get to know the new design system" -
  https://developer.apple.com/videos/play/wwdc2025/356/ - adopt the hierarchy,
  harmony, consistency, concentricity, grouped item, system color, and
  typography direction.
- WWDC25 "Build a SwiftUI app with the new design" -
  https://developer.apple.com/videos/play/wwdc2025/323/ - adopt SwiftUI-first
  migration: app structure, toolbars, search, controls, and then custom Liquid
  Glass only for the control surfaces named in this plan.
- Apple new design gallery -
  https://developer.apple.com/design/new-design-gallery-2026/ - adopt as
  pattern evidence: successful iOS 26 apps modernize navigation, toolbars, tab
  bars, and control grouping while keeping core product identity.

## 3.2 Internal ground truth (code as spec)

- Authoritative behavior anchors:
  - `README.md` - service path, simulator/device commands, and the relay-backed
    app route.
  - `Makefile` - canonical runnable commands for services and app launch.
  - `Package.swift` - Swift package platform support; this plan raises iOS
    support to 26.0 and keeps macOS 14.
  - `project.yml` - XcodeGen source of truth; this plan raises app, framework,
    and test deployment targets to iOS 26.0 and owns Info.plist/app-icon wiring.
  - `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` - product UX north star:
    a calm personal operations board, not a full Codex TUI replacement.
  - `docs/EPIC_CODEX_DOCK_MVP_2026-05-27.md` - implemented MVP phase shape and
    real relay-backed acceptance path.
  - `docs/mockups/codex-dock-2026-05-27-v2/*.png` - recognizable visual anchors
    for Dock, Needs-me, Thread detail, dictation, Archive, and Relay.
- Canonical path / owner to reuse:
  - New shared UI owner lives at
    `CodexDock/Features/Design/DockDesignSystem.swift` and is imported by
    existing SwiftUI feature files.
  - `CodexDock/Features/Dock/DockView.swift` owns root tabs, Dock feed,
    `DockRowView`, shared `DockMessageView`, `HostSummaryView`, banners, and
    `dockNavigationChrome()`.
  - `CodexDock/Features/Session/SessionDetailView.swift` owns Thread detail
    header, timeline cards, and detail empty/error cards.
  - `CodexDock/Features/Session/ComposerView.swift` owns the composer control
    cluster and mic/send controls.
  - `CodexDock/Features/Session/RequestCardView.swift` owns approval/input card
    styling and primary/secondary request actions.
  - `CodexDock/Features/Archive/ArchiveView.swift` owns Archive screen
    structure and restore controls.
  - `CodexDock/Features/Hosts/HostsView.swift` owns Relay settings rows and
    edit form controls.
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift` owns first-run relay
    discovery/manual-connect UI.
- Adjacent surfaces tied to the same visual contract:
  - `CodexDockApp/Info.plist` and `project.yml` - if app icon, display metadata,
    permission copy, or target settings change.
  - `docs/app-icon/**` - existing generated app icon source/reference assets.
  - `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` - may need a short
    supersession note after implementation if it keeps old visual assumptions.
  - `docs/epic/CODEX_DOCK_MVP_2026-05-27/PHASE_08_VOICE_ACCESSIBILITY_FINAL_POLISH_2026-05-27.md`
    and worklog/audit docs - passive history by default; do not rewrite unless
    implementation touches final-polish truth.
- Cutover posture (separate from `fallback_policy`):
  - Preserve existing runtime/data contracts, but perform a clean deployment
    cutover to iOS 26.0. Add iOS 26 effects directly through SwiftUI APIs, not
    through compatibility visual branches.
- Existing patterns to reuse:
  - Semantic colors already used: `.primary`, `.secondary`, `.background`,
    `Color(uiColor: .systemGroupedBackground)`.
  - Existing minimum control size pattern: 44x44 icon buttons in headers,
    composer, and rows.
  - Existing status-chip pattern: colored text plus low-opacity capsule.
  - Existing local state/test split: UI files stay thin while stores own data
    behavior.
- Duplicate or drifting paths relevant to this change:
  - `dockNavigationChrome()` hides navigation bars for all iOS feature screens;
    modernization must either retire it or narrow it.
  - Card backgrounds are repeated as `.background(.background, in:
    RoundedRectangle(cornerRadius: 8, style: .continuous))` across many files.
  - Status chip and banner styling repeats across Dock, Session detail, Hosts,
    and Request cards.
  - Custom search/edit-field backgrounds repeat in Dock, bootstrap, Hosts, and
    request-card input fields.
- Behavior-preservation signals already available:
  - `rtk swift test --filter DockStoreTests` - Dock/archive/host data behavior.
  - `rtk swift test --filter ThreadDetailStoreTests` - thread detail, composer,
    voice, and request-card behavior.
  - `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
    - app target compilation and availability issues.
  - `rtk make app SIM='iPhone 17'` - installed simulator behavior when needed.

## 3.3 Decision gaps that must be resolved before implementation

- None. The user explicitly requested iOS 26 modernization, recognizable UI,
  Apple standards, exhaustive research saved to docs, ArcStep auto-plan, plan
  audit agreement, parallel agents, system light/dark respect, and a clean iOS
  26-only deployment cutover. That resolves the main technical posture: raise
  `Package.swift`, `project.yml`, and generated Xcode settings to iOS 26.0 and
  remove old-OS compatibility branches from this design work.
<!-- arch_skill:block:research_grounding:end -->

# 4) Current Architecture (as-is)

<!-- arch_skill:block:current_architecture:start -->
## 4.1 On-disk structure

- `CodexDockApp/CodexDockApp.swift` launches `CodexDockBootstrapView()`.
- `project.yml` owns generated Xcode project settings, bundle identifiers,
  deployment target, app icon name, Info.plist, Bonjour, local network, and
  microphone permission copy.
- `Package.swift` owns SwiftPM platform support and this plan raises iOS
  support to 26.0.
- `CodexDock/Features/Dock/DockView.swift` owns:
  - `CodexDockRootView`
  - `DockView`
  - `DockFilter`
  - `DockRowView`
  - `HostSummaryView`
  - `MappingFailureBanner`
  - `ActionErrorBanner`
  - `DockMessageView`
  - `dockNavigationChrome()`
- `CodexDock/Features/Dock/CodexDockBootstrapView.swift` owns relay discovery
  and manual relay setup UI.
- `CodexDock/Features/Archive/ArchiveView.swift` owns Archive UI and reuses
  shared Dock row/message components.
- `CodexDock/Features/Hosts/HostsView.swift` owns Relay settings rows, edit
  form, URL text fields, and Test/Save controls.
- `CodexDock/Features/Session/SessionDetailView.swift` owns thread header,
  live-state pills, event cards, and detail message cards.
- `CodexDock/Features/Session/ComposerView.swift` owns composer text entry,
  hold-to-dictate mic, Send button, and voice status/error labels.
- `CodexDock/Features/Session/RequestCardView.swift` owns request/approval
  cards and request action buttons.
- `CodexDockApp/Assets.xcassets/AppIcon.appiconset/**` owns app icon assets
  used by the app target.
- `docs/app-icon/**` contains app-icon source/reference output, but it is not
  enough by itself to change app target assets.

## 4.2 Control paths (runtime)

- Bootstrap path:
  - `CodexDockApp` launches `CodexDockBootstrapView`.
  - `RelayBootstrapStore` discovers or accepts a relay URL.
  - Ready state builds `CodexDockRootView(registry:)`.
- Root tab path:
  - `CodexDockRootView` shows a standard `TabView` with Dock, Archive, and
    Relay tabs.
  - The root applies `.tint(.blue)`.
- Screen shell path:
  - Dock, Archive, Relay, and bootstrap each create their own
    `NavigationStack`.
  - They use `ScrollView` plus custom HStack/VStack headers.
  - They apply `.dockNavigationChrome()`, which hides the iOS navigation bar.
- Dock path:
  - `DockView` loads and refreshes `DockStore`, filters in local SwiftUI state,
    renders host summaries, banners, sections, and `DockRowView`.
  - Tapping a row opens `SessionDetailView`.
- Thread detail path:
  - `SessionDetailView` loads `ThreadDetailStore`, renders header/composer/
    request cards/timeline, and closes the store on disappear.
- Composer path:
  - `ComposerView` binds `store.composer.draft` to a vertical `TextField`.
  - Send starts `store.sendDraft()`.
  - Mic uses a zero-distance `DragGesture` to start/finish voice capture.
- Relay settings path:
  - `HostsView` edits `HostSettingsStore` rows directly on screen.

## 4.3 Object model + key abstractions

- There is no central design-system module today.
- Shared view components are currently co-located in `DockView.swift`.
- Content-card styling repeats as `.background(.background, in:
  RoundedRectangle(cornerRadius: 8, style: .continuous))`.
- Status chip styling repeats as colored foreground text plus
  `color.opacity(0.12)` in a `Capsule`.
- Text input styling repeats as a fixed-height rounded background using either
  `.background` or `.secondary.opacity(0.08)`.
- Several controls use fixed heights (`frame(height: 40)` or similar) that can
  clip with very large Dynamic Type: Dock search, manual relay URL, and Relay
  settings text fields are the main examples.
- Several status treatments use low opacity color fills (`0.08` or `0.12`),
  which need explicit light/dark and Increased Contrast review.
- Header pills and thread metadata use single-line HStacks in Thread detail,
  which can overflow or truncate at large text sizes.
- Screens already use system fonts and semantic foreground styles:
  `.primary`, `.secondary`, `.red`, `.blue`, `.green`, `.orange`, `.purple`,
  and `.teal`.
- Screens already use adaptive grouped backgrounds through
  `Color(uiColor: .systemGroupedBackground)` on iOS.

## 4.4 Observability + failure behavior today

- UI failure states render inline message cards and banners, not alerts.
- Relay/bootstrap failure renders the same setup screen with an error title and
  manual-connect path.
- Dock/Archive mapping/action failures render banners.
- Thread live stale/error states render inline detail messages.
- Store tests cover behavior. The current repo has no UI snapshot or visual
  regression harness.

## 4.5 UI surfaces (ASCII mockups, if UI work)

Current shape, simplified:

```text
TabView
  Dock tab
    NavigationStack(hidden bar)
      custom header: "Dock" + disabled plus button
      segmented filter
      custom search field
      host summaries
      section headers
      row cards
  Archive tab
    NavigationStack(hidden bar)
      custom header: "Archive" + refresh button
      host summaries
      archived row cards + Restore
  Relay tab
    NavigationStack(hidden bar)
      custom header: "Relay" + Test All
      relay rows
      inline relay editor
```

Thread detail:

```text
NavigationStack detail
  inline navigation title: "Thread"
  header with terminal icon, title, repo/branch, status pills
  composer: text field + mic + send
  request cards
  event timeline cards
```
<!-- arch_skill:block:current_architecture:end -->

# 5) Target Architecture (to-be)

<!-- arch_skill:block:target_architecture:start -->
## 5.1 On-disk structure (future)

- Add one narrow shared visual owner:
  - `CodexDock/Features/Design/DockDesignSystem.swift`
- Keep existing feature files as screen owners:
  - `CodexDock/Features/Dock/DockView.swift`
  - `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
  - `CodexDock/Features/Archive/ArchiveView.swift`
  - `CodexDock/Features/Hosts/HostsView.swift`
  - `CodexDock/Features/Session/SessionDetailView.swift`
  - `CodexDock/Features/Session/ComposerView.swift`
  - `CodexDock/Features/Session/RequestCardView.swift`
- Use `project.yml` only when app target, Info.plist, permissions, or
  deployment target actually changes. This plan changes the deployment target
  to iOS 26.0, so `project.yml` and the generated Xcode project are in scope.
  App icon wiring is out of scope for this plan.
- Keep reference/planning truth in:
  - `docs/CODEX_DOCK_IOS_26_DESIGN_REFERENCES_2026-05-28.md`
  - `docs/CODEX_DOCK_IOS_26_DESIGN_MODERNIZATION_2026-05-28.md`

## 5.2 Control paths (future)

- Root tab path remains `CodexDockRootView` with Dock, Archive, and Relay tabs.
- Each tab keeps its existing content ownership, but system navigation should
  own titles and toolbar actions:
  - Dock title and Add/Refresh-style actions move into `.navigationTitle` and
    `.toolbar` where behavior exists.
  - Archive title and Refresh move into `.navigationTitle` and `.toolbar`.
  - Relay title and Test All move into `.navigationTitle` and `.toolbar`.
  - Bootstrap title/action treatment uses standard navigation title/toolbar
    patterns or one shared setup header that does not hide useful system chrome.
- `dockNavigationChrome()` should be retired, renamed, or narrowed so iOS
  navigation bars are not globally hidden when the standard chrome is the
  intended system design surface.
- Dock search should move from a custom HStack field to `.searchable` or a
  standard toolbar/search placement while preserving row-filter behavior.
- Liquid Glass should appear through system components first, then through
  shared iOS 26 helpers for specific control clusters:
  - toolbar buttons
  - primary actions
  - composer mic/send cluster
  - compact active controls
- Content rows/cards continue to use semantic content backgrounds, not default
  glass.

## 5.3 Object model + abstractions (future)

Add a small shared style surface with responsibilities like:

- semantic app background
- semantic card background
- content card shape/radius
- status chip style
- banner style
- text field container style
- Dynamic Type-safe control sizing guidance
- iOS 26 glass control treatment
- helper comments documenting that Liquid Glass belongs on controls/navigation,
  not row/card content

This must stay small. It is not a theme engine, brand framework, or runtime
style registry.

Light/dark contract:

- Use semantic SwiftUI colors/materials or dynamic design tokens.
- Do not override `colorScheme`.
- Do not call `.preferredColorScheme`.
- If custom colors/assets are introduced, they must provide light and dark
  variants or be derived from system colors.
- Status/rail colors stay accompanied by text/icons; color is not the only
  meaning carrier.
- Compact pills, chips, and field rows should wrap, stack, or grow vertically
  before truncating important status or endpoint information.

Deployment contract:

- Set the app, framework, tests, and Swift package to iOS 26.0.
- Run XcodeGen after `project.yml` changes:
  `rtk xcodegen generate --spec project.yml`.
- Use iOS 26 SwiftUI design APIs directly. Do not add iOS 17-25 fallback
  branches or fake-glass shims.

## 5.4 Invariants and boundaries

- Visual-system ownership is single-source. Screens may choose layout, but not
  invent parallel card/glass/token contracts.
- Navigation modernization must not change relay connection behavior or store
  state ownership.
- Content-card readability beats glass spectacle.
- Standard SwiftUI controls get first right of refusal.
- App icon/project changes go through `project.yml` and generated assets, not a
  direct Xcode project edit.
- No new user-facing modes, settings, theme pickers, tabs, or product features
  are introduced by this visual modernization.

## 5.5 UI surfaces (ASCII mockups, if UI work)

Target shape, simplified:

```text
TabView
  Dock tab
    NavigationStack(system chrome)
      navigation title: Dock
      toolbar: primary/action controls
      filter/control cluster: Search sessions, Sort, Idle
      host summaries
      section headers
      recognizable row cards
  Archive tab
    NavigationStack(system chrome)
      navigation title: Archive
      toolbar: Refresh
      host summaries
      recognizable archived row cards + Restore
  Relay tab
    NavigationStack(system chrome)
      navigation title: Relay
      toolbar: Test All
      relay rows
      relay editor or scoped form
```

Thread detail:

```text
NavigationStack detail
  system back/title behavior
  header remains recognizable
  composer control cluster may use restrained glass on iOS 26
  request cards remain semantic content surfaces
  event cards remain readable content surfaces
```
<!-- arch_skill:block:target_architecture:end -->

# 6) Call-Site Audit (exhaustive change inventory)

<!-- arch_skill:block:call_site_audit:start -->
## 6.1 Change map (table)

| Area | File | Symbol / Call site | Current behavior | Required change | Why | New API / contract | Tests impacted |
| ---- | ---- | ------------------ | ---------------- | --------------- | --- | ------------------ | -------------- |
| App entry | `CodexDockApp/CodexDockApp.swift` | `CodexDockApp` | Launches bootstrap | Preserve unless implementation needs app-wide environment setup | App launch path must stay stable | No product change | Xcode build |
| Project config | `project.yml` | deployment target, app icon, Info.plist | Target was iOS 17 before the approved cutover; generated Info.plist and app icon wiring live here | Raise app/framework/test deployment targets to iOS 26.0; regenerate with XcodeGen | Canonical project source and user-approved cutover | `rtk xcodegen generate --spec project.yml` | XcodeGen + Xcode build |
| Swift package | `Package.swift` | platforms | Package was iOS 17 before the approved cutover | Raise package iOS platform to 26.0 | Keep SwiftPM and Xcode target truth aligned | Direct iOS 26 APIs, no compatibility wrapper | Swift/Xcode build |
| Root shell | `CodexDock/Features/Dock/DockView.swift` | `CodexDockRootView` | Standard `TabView`, `.tint(.blue)` | Preserve tabs; evaluate iOS 26 tab behavior without changing sections | Root nav must remain recognizable | top-level tabs unchanged | Xcode build/manual |
| Hidden nav chrome | `CodexDock/Features/Dock/DockView.swift` | `dockNavigationChrome()` | Hides iOS navigation bars | Retire/narrow and restore system navigation/toolbars | Lets iOS 26 standard chrome carry glass | system navigation owner | Xcode build/manual |
| Dock shell | `CodexDock/Features/Dock/DockView.swift` | `DockView.body`, `header`, `controls` | Custom header, disabled Add Host plus, segmented picker, custom search row | Move title/search to system navigation/search; remove the dead disabled plus unless it gets real behavior in a separate feature | Standard components first and no fake action | `.navigationTitle`, `.toolbar`, `.searchable` | Xcode build/manual |
| Dock filtering | `CodexDock/Features/Dock/DockView.swift` | `filter`, `searchText`, `filteredSections` | Local state filters rows | Preserve behavior while changing search control surface | Visual change must not break scan behavior | same predicate behavior | Existing DockStoreTests if state changes; otherwise manual |
| Dock row cards | `CodexDock/Features/Dock/DockView.swift` | `DockRowView` | Recognizable content card with rail/status chip | Keep structure; adopt shared card/chip styling; avoid row-level glass | Main recognizable component | shared semantic card/chip helper | Xcode build/manual light/dark |
| Shared messages/banners | `CodexDock/Features/Dock/DockView.swift` | `DockMessageView`, `ActionErrorBanner`, `MappingFailureBanner` | Local repeated backgrounds/chips | Move to shared semantic treatment or keep reusable owner | Avoid drift and contrast bugs | shared message/banner helper | Xcode build/manual |
| Bootstrap | `CodexDock/Features/Dock/CodexDockBootstrapView.swift` | `RelaySetupView` | Custom header, relay rows, manual field, Connect | Apply shared field/card/control treatment; review nav/header standardization | First-run UI should match new system | shared visual helpers | Xcode build/manual |
| Archive | `CodexDock/Features/Archive/ArchiveView.swift` | `ArchiveView.header`, `archiveRow` | Custom header, Refresh, reused rows, Restore | Move title/Refresh to toolbar; reuse shared row/control treatment | Consistent tab chrome | `.navigationTitle`, `.toolbar`, shared controls | Xcode build/manual |
| Relay settings | `CodexDock/Features/Hosts/HostsView.swift` | `HostsView`, `HostSettingsRow`, `HostTextField` | Custom header, fixed-height fields, inline editor | Move title/Test All to toolbar; shared fields/cards; avoid Dynamic Type clipping | Utility form should respect system/accessibility | shared field/card helpers | Xcode build/manual |
| Thread detail shell | `CodexDock/Features/Session/SessionDetailView.swift` | `SessionDetailView.body`, `DetailHeaderView` | Standard inline title plus custom header/pills/cards | Keep recognizable; apply shared chips/cards; fix wrapping risk | Detail scanability and accessibility | shared chip/card helpers | ThreadDetailStoreTests if behavior changes; build/manual |
| Event cards | `CodexDock/Features/Session/SessionDetailView.swift` | `ThreadEventCard` | Plain semantic background card | Keep content surface non-glass; shared card style | Long text readability | shared content card | Xcode build/manual |
| Composer | `CodexDock/Features/Session/ComposerView.swift` | `ComposerView`, `micButton` | Text field + mic + send, bordered/prominent styles | Apply restrained control glass through direct iOS 26 APIs; preserve labels and 44pt targets | Best high-value glass seam | shared glass control helper | ThreadDetailStoreTests if behavior changes; build/manual |
| Request cards | `CodexDock/Features/Session/RequestCardView.swift` | `RequestCardView` | Status-tinted card/action buttons | Preserve semantic card; use shared contrast-safe chip/action treatment | Avoid color-only meaning | shared request/card controls | ThreadDetailStoreTests if behavior changes; manual |
| Dynamic Type | `CodexDock/Features/**` | Fixed-height fields, non-wrapping pills, one-line metadata | Several compact controls may clip or truncate | Allow vertical growth/wrapping in changed surfaces | Accessibility is part of the visual requirement | Dynamic Type-safe layout rule | manual accessibility review |
| Light/dark appearance | `CodexDock/Features/**` | Mostly semantic colors, but opacity chips and fills vary by context | Preserve semantic colors; verify contrast in both modes | User explicitly requested system light/dark respect | system appearance is source of truth | manual light/dark review |
| App icon | `CodexDockApp/Assets.xcassets/AppIcon.appiconset/**`, `docs/app-icon/**`, `project.yml` | Existing generated icon set | Research/reference only in this plan; no implementation work | Avoid hidden asset scope in a UI modernization plan | out of implementation scope | none |
| Reference docs | `docs/CODEX_DOCK_IOS_26_DESIGN_REFERENCES_2026-05-28.md` | source pack | New Apple guidance doc | Keep as reference only, not execution checklist | Avoid second plan | related doc | readback/git status |
| UX spec | `docs/CODEX_DOCK_IPHONE_UX_SPEC_2026-05-27.md` | current UX spec | Calm operations-board spec | Inspect during final pass; update stale live visual guidance or record no update needed | Avoid live-doc drift | docs review | docs readback |

## 6.2 Migration notes

* Canonical owner path / shared code path:
  * Add a small `DockDesignSystem` style/helper surface and migrate repeated
    card/chip/field/control styling to it.
* Deprecated APIs (if any):
  * `dockNavigationChrome()` should be removed, narrowed, or renamed once
    screens use standard navigation chrome.
* Delete list (what must be removed; include superseded shims/parallel paths if any):
  * Remove duplicated ad hoc card/chip/search/field style code only after each
    adopter moves to the shared helper.
  * Remove custom headers where a system navigation title/toolbar fully owns the
    same action.
* Adjacent surfaces tied to the same contract family:
  * Bootstrap, Dock, Archive, Relay, Thread detail, Composer, Request cards,
    project config, and UX docs as listed above. App icon assets are reference
    only and out of implementation scope.
* Compatibility posture / cutover plan:
  * Preserve runtime behavior and service/data contracts.
  * Clean deployment cutover to iOS 26.0; remove old-OS visual branches from
    the plan.
  * Clean UI cutover is allowed for custom header/search/chrome internals once
    system equivalents preserve behavior.
* Capability-replacing harnesses to delete or justify:
  * None. This is not agent-backed behavior and should not add harnesses.
* Live docs/comments/instructions to update or delete:
  * Inspect UX spec and README during finalization; update stale live visual
    guidance or record that no update was needed.
* Behavior-preservation signals for refactors:
  * Relevant Swift tests for touched behavior plus app build and manual
    simulator review.

## Pattern Consolidation Sweep (anti-blinders; scoped by plan)

| Area | File / Symbol | Pattern to adopt | Why (drift prevented) | Proposed scope |
| ---- | ------------- | ---------------- | ---------------------- | -------------- |
| Card backgrounds | `DockRowView`, `DockMessageView`, `ThreadEventCard`, `HostSettingsRow`, `RequestCardView`, bootstrap relay row | Shared semantic card helper | Prevent light/dark and radius drift | include |
| Status chips | Dock status, live pills, host status, request status | Shared chip helper with text/icons | Prevent contrast/color-only regressions | include |
| Text fields | Dock search, composer draft, request input, host fields, manual relay URL | Shared field treatment where not replaced by system search | Prevent Dynamic Type clipping and background drift | include |
| Navigation headers | Dock, Archive, Relay, bootstrap | System navigation title and toolbar | Let iOS 26 standard controls carry glass | include |
| Composer controls | Composer mic/send cluster | Shared direct iOS 26 glass control helper | Proves useful custom glass seam | include |
| App icon | App icon asset catalog | iOS 26 icon variants/Icon Composer pass | Valuable but separable from UI chrome | exclude from this plan; named follow-up only |
<!-- arch_skill:block:call_site_audit:end -->

# 7) Depth-First Phased Implementation Plan (authoritative)

<!-- arch_skill:block:phase_plan:start -->
> Rule: depth-first implementation protects the full destination while proving the path early. Treat TL;DR, Section 0, Sections 5-6, and approved decisions as the destination map: they preserve final known scope, not a Phase 1 checklist. Section 7 should choose the first working slice that proves one real path through the canonical owner path and highest-risk seam, compatibility or migration posture, and verification shape. Later phases expand along named axes from that proof. Phase boundaries are proof gates: each phase must create evidence that later work can safely rely on. Before a phase plan is valid, run an obligation sweep and either place required work in the current phase, assign it to a named later phase in the expansion map, or stop for an explicit user decision; do not hide unresolved branches. Phase count is an outcome of dependency edges, proof gates, reversibility or migration boundaries, and user-review boundaries; split only when a phase blends separately provable units. `Work` explains the unit and is explanatory only for modern docs. `Checklist (must all be done)` is the authoritative must-do list inside the phase. `Exit criteria (all required)` names the exhaustive concrete done conditions the audit must validate. Refactors, consolidations, and shared-path extractions must preserve existing behavior with credible evidence proportional to the risk. For agent-backed systems, prefer prompt, grounding, and native-capability changes before new harnesses or scripts. No fallbacks/runtime shims - the system must work correctly or fail loudly (delete superseded paths). If a bridge is explicitly approved, timebox it and include removal work; otherwise plan either clean cutover or preservation work directly. Prefer programmatic checks per phase; defer manual/UI verification to finalization. Avoid negative-value tests and heuristic gates (deletion checks, visual constants, doc-driven gates, keyword or absence gates, repo-shape policing). Also: document new patterns/gotchas in code comments at the canonical boundary (high leverage, not comment spam).

## Phase 1 - Dock vertical modernization seam

* Goal:
  Prove the modernization approach in the highest-value visible path: the Dock
  tab. This phase must first make the repo iOS 26-only, then establish the
  shared visual owner, restore system navigation/search where it matters most,
  and show iOS 26-ready controls without changing Dock behavior.
* Work:
  Raise the SwiftPM and Xcode deployment floor to iOS 26.0, regenerate the
  Xcode project, add the small shared design helper surface, then use it in
  Dock for app background, card treatment, status chips, banners,
  toolbar/search controls, and the row/card shape. Restore system navigation
  chrome for Dock before widening to other screens.
* Checklist (must all be done):
  - Set `Package.swift` to iOS 26.0.
  - Set `project.yml` global, app, framework, and test deployment targets to
    iOS 26.0.
  - Run `rtk xcodegen generate --spec project.yml` after the `project.yml`
    target change.
  - Add the shared design/style owner at
    `CodexDock/Features/Design/DockDesignSystem.swift`.
  - Document in the shared design owner that Liquid Glass is for controls and
    navigation, not long scrolling content cards.
  - Add direct iOS 26 glass/control helpers without iOS 17-25 compatibility
    branches.
  - Replace Dock's custom title header with a standard navigation title.
  - Remove the disabled Dock plus affordance from the visible primary header;
    Relay remains the host-management surface.
  - Modernize Dock's Search/Sort/Idle controls row as one behavior surface.
    Preserve local Search, `Branch`/`Newest` sort, and default-off `Idle`
    semantics instead of replacing it with a search-only surface.
  - Retire or narrow `dockNavigationChrome()` for Dock so it no longer hides the
    intended system navigation surface.
  - Migrate `DockRowView`, `DockMessageView`, `ActionErrorBanner`,
    `MappingFailureBanner`, and Dock control backgrounds to the shared semantic
    card/chip/banner/control treatment.
  - Migrate Dock's app background to the shared semantic app-background
    treatment.
  - Preserve Dock row information architecture: rail, title, status, repo,
    branch, label, summary, last activity, and navigation affordance.
  - Ensure Dock status/rail meaning is not color-only and remains labeled.
  - Ensure changed Dock controls and rows respond to system Light Mode and Dark
    Mode without a forced color scheme.
* Verification (required proof):
  - Run `rtk xcodegen generate --spec project.yml`.
  - Run `rtk swift test --filter DockStoreTests` if Dock state/filter behavior
    code changes; otherwise record why UI-only changes did not need store tests.
  - Run `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`.
  - Manual or screenshot review Dock on `iPhone 17` in system Light Mode and
    Dark Mode.
* Docs/comments (propagation; only if needed):
  - Update a short code comment at the shared design owner boundary only if it
    prevents future glass/card misuse.
* Exit criteria (all required):
  - `Package.swift`, `project.yml`, and the generated project all target iOS
    26.0.
  - Dock uses the shared design owner for its migrated visual primitives.
  - Dock's app background uses the shared semantic app-background treatment.
  - Dock no longer depends on hidden custom navigation chrome for its standard
    title/action/search surface.
  - Dock Search, Sort, and `Idle` still project the same sessions by the same
    query, ordering, and idle-visibility intent.
  - Dock row shape remains recognizable against the v2 Dock mockups.
  - Dock is checked in Light Mode and Dark Mode on `iPhone 17`, including Dock
    empty/error/offline states, labels, rails, and status colors.
  - No iOS 17-25 compatibility branch or fake-glass shim is introduced.
* Rollback:
  Revert the Dock feature-file changes and the shared helper adoption for Dock.
  Store/data code should not need rollback because this phase is visual.

## Phase 2 - Thread detail, composer, and request controls

* Goal:
  Expand the proven visual system to the thread workflow where controls matter
  most: detail header, composer, voice/send controls, request cards, and event
  timeline cards.
* Work:
  Keep the thread detail layout recognizable while making controls more modern:
  use shared content-card and chip treatment for cards/pills, apply restrained
  glass only to the composer/control cluster where it helps, and fix known
  Dynamic Type wrapping risks.
* Checklist (must all be done):
  - Migrate `DetailHeaderView`, `DetailPill`, `ThreadEventCard`, and
    `DetailMessageView` to the shared semantic card/chip treatment.
  - Preserve event-card readability by keeping timeline cards as content
    surfaces, not Liquid Glass controls.
  - Apply the shared direct iOS 26 glass/control helper to the composer
    mic/send cluster.
  - Preserve composer behavior: typed draft, mic start/finish, voice status,
    explicit Send, sending progress, and error labels.
  - Preserve request-card behavior and migrate card/chip/action styling to the
    shared contrast-safe treatment.
  - Fix or avoid single-line/wrapping risks in the changed Thread detail pills,
    thread metadata, composer controls, and request-card controls.
  - Ensure voice, request, and live-state meanings remain visible through text
    or symbols and do not rely on color alone.
  - Ensure changed Thread detail surfaces respond to system Light Mode and Dark
    Mode without a forced color scheme.
* Verification (required proof):
  - Run `rtk swift test --filter ThreadDetailStoreTests` if composer, request,
    voice, or thread-detail behavior code changes; otherwise record why UI-only
    changes did not need store tests.
  - Run `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`.
  - Manual or screenshot review Thread detail, Composer, and Request cards on
    `iPhone 17` in Light Mode and Dark Mode.
* Docs/comments (propagation; only if needed):
  - Update code comments only at non-obvious shared helper boundaries.
* Exit criteria (all required):
  - Thread detail, Composer, and Request cards use the shared design owner for
    migrated card/chip/control styling.
  - Composer remains an in-place edit-then-send flow.
  - Request cards remain readable content cards with clear actions.
  - Dynamic Type review confirms changed pills/metadata/controls do not clip in
    the normal tested range.
  - Light Mode and Dark Mode review covers detail header, event cards, Composer,
    Request cards, empty/error/stale/live states, validation/request/voice
    status colors, and status labels.
  - No iOS 17-25 compatibility branch or fake-glass shim is introduced.
* Rollback:
  Revert Thread detail, Composer, and Request-card style adoption while leaving
  Phase 1 Dock work intact.

## Phase 3 - Archive, Relay, and bootstrap expansion

* Goal:
  Finish the app-wide recognizable modernization by applying the proven system
  navigation and shared visual contracts to the remaining top-level and setup
  surfaces.
* Work:
  Migrate Archive, Relay settings, and relay bootstrap from custom headers and
  repeated field/card styles to the shared pattern. Keep each screen's utility
  workflow intact.
* Checklist (must all be done):
  - Move Archive title/Refresh ownership to standard navigation title and
    toolbar patterns.
  - Migrate Archive-specific restore controls and reused row/card surfaces to
    the shared control treatment without changing archive/restore behavior.
  - Move Relay title/Test All ownership to standard navigation title and
    toolbar patterns.
  - Apply standard navigation title/header treatment to bootstrap so it no
    longer hides useful system chrome.
  - Retire, remove, or narrow `dockNavigationChrome()` across Archive, Relay,
    and bootstrap after those screens use their system navigation title/toolbar
    surfaces.
  - Remove custom Archive, Relay, and bootstrap headers where system
    title/toolbar ownership fully replaces them.
  - Migrate `HostSettingsRow`, `HostTextField`, validation banners, and Save/Test
    controls to the shared field/card/control treatment.
  - Fix or avoid fixed-height field clipping risks in Relay settings fields.
  - Modernize relay bootstrap rows, manual URL field, and Connect action with
    the shared visual treatment.
  - Keep relay discovery/manual-connect behavior and all no-phone-secret
    constraints unchanged.
  - Ensure Archive, Relay, and bootstrap surfaces respond to system Light Mode
    and Dark Mode without a forced color scheme.
* Verification (required proof):
  - Run `rtk swift test --filter DockStoreTests` if Archive or Host settings
    behavior code changes; otherwise record why UI-only changes did not need
    store tests.
  - Run `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`.
  - Manual or screenshot review Archive, Relay, and bootstrap on `iPhone 17` in
    Light Mode and Dark Mode.
* Docs/comments (propagation; only if needed):
  - Inspect README and the UX spec for stale live guidance after this phase;
    update stale live guidance or record that no live-doc update was needed.
* Exit criteria (all required):
  - Archive, Relay, and bootstrap no longer maintain separate ad hoc visual
    treatment for migrated cards, fields, chips, and primary controls.
  - Archive, Relay, and bootstrap use standard navigation title/header
    treatment instead of hidden custom navigation chrome.
  - `dockNavigationChrome()` is removed, narrowed to non-iOS contexts, or no
    longer applied to screens that now depend on system navigation chrome.
  - Archive restore, Relay test/save, and bootstrap manual-connect behavior
    remain unchanged.
  - Fixed-height field risks introduced by changed code are removed or justified
    with manual Dynamic Type evidence.
  - Light Mode and Dark Mode review covers Archive rows/restore, Relay rows,
    Relay editor, Archive empty/error/offline states, Relay validation/status
    states, bootstrap searching/failed states, manual URL field, labels, status
    colors, and primary actions.
  - No visual work changes relay endpoints, secrets posture, app-server tokens,
    or OpenAI-key handling.
* Rollback:
  Revert Archive, Relay, and bootstrap style adoption while leaving earlier
  Dock/detail work intact.

## Phase 4 - Final appearance, accessibility, and docs truth pass

* Goal:
  Prove the app-wide modernization is cohesive, accessible, Apple-aligned, and
  documented without turning visual verification into brittle automation.
* Work:
  Run final build and appearance review across all changed surfaces; fix
  inconsistencies found during light/dark/accessibility review; update docs only
  where live truth changed.
* Checklist (must all be done):
  - Run the required app build after all UI changes.
  - Review Dock, Thread detail, Composer, Request cards, Archive, Relay, and
    bootstrap on `iPhone 17` in system Light Mode.
  - Review Dock, Thread detail, Composer, Request cards, Archive, Relay, and
    bootstrap on `iPhone 17` in system Dark Mode.
  - In both Light Mode and Dark Mode, include empty, error, offline, stale/live,
    validation, voice-status, request-status, label, rail, and status-color
    states where those states exist in the changed surfaces.
  - Review changed controls with Dynamic Type large enough to expose clipping in
    pills, text fields, toolbar controls, and composer controls.
  - Review VoiceOver labels for changed icon-only controls.
  - Review Reduced Transparency, Increased Contrast, and Reduce Motion for
    changed glass/control behavior.
  - Confirm no custom theme picker, forced `.preferredColorScheme`, fake glass
    renderer, or content-card glass blanket was introduced.
  - Update this plan/worklog when implementation evidence exists.
  - Inspect the UX spec and README for stale live guidance; update stale live
    guidance or record that no live-doc update was needed.
* Verification (required proof):
  - Run `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`.
  - Run any relevant Swift tests from earlier phases if the final pass changes
    behavior-bearing code.
  - Record manual appearance/accessibility evidence in the worklog.
* Docs/comments (propagation; only if needed):
  - Update live docs/comments that would otherwise teach stale UI or project
    truth. Do not rewrite passive history docs.
* Exit criteria (all required):
  - All planned screens are reviewed in Light Mode and Dark Mode.
  - Light/Dark review includes Dock, Thread detail, Composer, Request cards,
    Archive, Relay, bootstrap, empty/error/offline states, labels, rails, and
    status colors.
  - Changed controls have acceptable Dynamic Type, VoiceOver, Reduced
    Transparency, Increased Contrast, and Reduce Motion behavior.
  - Build passes after final changes.
  - Required behavior tests pass or are explicitly not run with an exact
    UI-only reason.
  - README and the UX spec were inspected for stale live guidance, and any
    stale touched guidance is current.
  - App icon redesign remains out of scope for this implementation plan.
* Rollback:
  Revert final polish changes that caused regressions and keep earlier proven
  phases if their proof remains valid.
<!-- arch_skill:block:phase_plan:end -->

# 8) Verification Strategy (common-sense; non-blocking)

Avoid verification bureaucracy. Use existing repo checks first, add no
visual-golden harness, and use focused simulator/manual review for appearance
truth.

## 8.1 Unit tests (contracts)

- Use `rtk swift test --filter DockStoreTests` when Dock/archive/host behavior
  is touched.
- Use `rtk swift test --filter ThreadDetailStoreTests` when thread detail,
  composer, voice, or request-card behavior is touched.
- No new unit tests are required for pure SwiftUI styling helpers unless the
  implementation introduces logic that can regress independently of rendering.

## 8.2 Integration tests (flows)

- Use `rtk xcodegen generate --spec project.yml` when project metadata, assets,
  Info.plist, or app icon wiring changes.
- Use `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
  for app UI/project changes.

## 8.3 E2E / device tests (realistic)

- Use `rtk make app SIM='iPhone 17'` when installed simulator behavior matters.
- Manual or screenshot review should cover Dock, Thread detail, Archive, Relay,
  bootstrap, Composer, Request cards, empty/error/offline states, labels, rails,
  and status colors in light mode and dark mode.
- Manual accessibility review should cover Dynamic Type, VoiceOver labels,
  Reduced Transparency, Increased Contrast, and Reduce Motion for changed
  glass/control behavior.

# 9) Rollout / Ops / Telemetry

## 9.1 Rollout plan

This is a local app visual modernization. Ship as a normal app update after
build and manual appearance checks pass.

## 9.2 Telemetry changes

No telemetry changes are required. This plan changes UI presentation, not relay
protocol, app-server methods, or service lifecycle.

## 9.3 Operational runbook

Keep using the existing service path:

- Raw Codex app-server: `ws://192.168.50.117:4500`
- Dock relay: `ws://192.168.50.117:4510`

If the app stops loading sessions after visual work, debug service status with:

- `rtk make app-server-status`
- `rtk make dock-relay-status`

Do not debug visual modernization by passing secrets or raw app-server tokens
into the iPhone app.

<!-- arch_skill:block:consistency_pass:start -->
## Consistency Pass

- Reviewers: explorer 1, self-integrator
- Scope checked:
  - Explorer 1 checked the stale iOS 17/availability-gating wording across the
    plan, design reference, and audit sidecar after the user's new iOS 26-only
    decision.
  - Self-integrator updated TL;DR, Sections 0-8, Section 10, the design
    reference, the audit sidecar, `Package.swift`, and `project.yml` to carry
    the clean iOS 26.0 cutover.
- Findings summary:
  - Blocking finding accepted: the prior plan preserved older OS support and
    created branching visual complexity that the user rejected.
  - Blocking finding accepted: Phase 1 needed to own the deployment-target
    cutover and XcodeGen regeneration before UI modernization work.
  - Blocking finding accepted: the audit sidecar and design-reference doc were
    stale after the user's decision.
- Integrated repairs:
  - Set the plan posture to iOS 26.0-only with no iOS 17-25 compatibility
    branch or fake-glass shim.
  - Added `Package.swift`, `project.yml`, generated Xcode project regeneration,
    and direct iOS 26 API usage to Phase 1.
  - Replaced the availability contract with a deployment contract.
  - Appended a Decision Log entry that supersedes the earlier iOS 17-preserving
    assumption.
  - Updated the design reference and audit sidecar to match the clean cutover.
- Remaining inconsistencies: none
- Unresolved decisions: none
- Unauthorized scope cuts: none
- Decision-complete: yes
- Decision: proceed to implement? yes
<!-- arch_skill:block:consistency_pass:end -->

# 10) Decision Log (append-only)

## 2026-05-28 - Treat user objective as North Star confirmation for auto-plan

Context

The user asked to deeply research iOS 26 design guidance, save references in
`docs/`, then use the ArcStep auto-plan path to plan a recognizable but more
modern Codex Dock design. The user also said the work is not done until the
audit plan and skill agree.

Options

- Stop after a draft North Star and ask for confirmation.
- Treat the explicit goal-context objective as the approved North Star for this
  planning run.

Decision

Proceed with `status: active`, save references, and run the auto-plan sequence
against this document.

Consequences

The plan can advance through research, deep-dive, phase-plan,
consistency-pass, and plan-audit in this turn without narrowing the requested
behavior.

Follow-ups

None.

## 2026-05-28 - Intent-derived: keep app icon redesign out of this UI modernization

Blocker: Apple iOS 26 guidance includes new app icon workflows, and this repo
has app-icon assets, but the user asked for UI effects, controls, standards,
glass, and recognizable app design rather than an icon redesign.

Consulted: TL;DR, Section 0, Section 3.1, Section 3.2, and
`docs/app-icon/README.md`.

Intent says: modernize the app UI so it looks cooler and up to current design
specs while remaining recognizable.

Decision: Treat app icon work as a named follow-up outside this implementation
plan. Keep project/icon references in research so a future asset pass starts
from the right canonical paths.

Consequences: Section 7 can stay focused on app UI modernization and does not
carry conditional app-icon obligations.

## 2026-05-28 - Intent-derived: remove the dead Dock plus during navigation modernization

Blocker: The current Dock header includes a disabled plus button labeled Add
host. Moving it into an iOS 26 toolbar would preserve a visible control that
does not work, while implementing Add Host from Dock would add product scope.

Consulted: TL;DR, Section 0.2, Section 0.3, Section 5.2, and current
`DockView.header`.

Intent says: modernize the recognizable UI without adding new product features
or keeping fake controls.

Decision: Remove the disabled Dock plus from the visible primary header during
the Dock modernization phase. Relay remains the host-management surface.

Consequences: The Dock toolbar can stay focused on real controls, and this plan
does not add a new Add Host workflow.

## 2026-05-28 - Intent-derived: use Features/Design as the shared UI owner

Blocker: The plan initially allowed either `CodexDock/Features/Design/` or
`CodexDock/Design/` for the shared visual owner. That left implementation with
a branchy owner-path decision.

Consulted: Section 3.2, Section 4.1, Section 5.1, and the current repo layout.

Intent says: modernize the existing SwiftUI feature surfaces without inventing a
large theme framework.

Decision: Use `CodexDock/Features/Design/DockDesignSystem.swift` as the single
shared visual owner.

Consequences: The shared helper stays close to the existing `Features` UI
surface and avoids a new top-level design framework.

## 2026-05-28 - Superseded: earlier compatibility assumption

This entry records that the first planning pass assumed older OS support would
remain. The user later rejected that complexity and directed the iOS 26-only
cutover below, so this entry is historical only and no longer governs the plan.

## 2026-05-28 - User-directed: supersede compatibility with iOS 26-only cutover

Context

After reviewing the compatibility plan, the user rejected the iOS 17-preserving
approach and explicitly directed the plan to raise the deployment target, remove
the old-OS complexity, and support only iOS 26.

Options

- Keep the previous iOS 17-preserving plan and availability-gate iOS 26 APIs.
- Raise the app and package deployment floor to iOS 26.0 and use iOS 26 design
  APIs directly.

Decision

Supersede the prior iOS 17-preserving decision. `Package.swift`, `project.yml`,
and the generated Xcode project must target iOS 26.0. The design modernization
must not carry an iOS 17-25 compatibility branch or fake-glass shim.

Consequences

Implementation gets simpler: shared helpers can focus on semantic design and
direct iOS 26 API use instead of old-OS branching. The app intentionally drops
iOS 17-25 deployment support.
