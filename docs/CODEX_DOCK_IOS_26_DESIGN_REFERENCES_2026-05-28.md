# Codex Dock iOS 26 Design References

Date: 2026-05-28
Status: reference pack for design modernization planning
Owner: aelaguiz

## Purpose

This reference pack captures Apple-primary guidance for modernizing Codex Dock
for iOS 26 without making the app feel like a different product.

The design target is specific:

- Keep the current Dock, Archive, Relay, bootstrap, and Thread detail flows
  recognizable.
- Adopt the iOS 26 design system where SwiftUI and Apple guidance support it.
- Use Liquid Glass where it clarifies navigation or controls.
- Avoid glass as decoration in content cards.
- Respect system light mode, dark mode, Increased Contrast, Reduced
  Transparency, Reduce Motion, Dynamic Type, and VoiceOver.

## Source Set

Primary Apple sources researched:

- Apple iOS 26 overview and "What's new in iOS 26":
  - https://developer.apple.com/ios/
  - https://developer.apple.com/ios/whats-new/
- Apple Human Interface Guidelines:
  - https://developer.apple.com/design/human-interface-guidelines/
  - https://developer.apple.com/design/human-interface-guidelines/materials
  - https://developer.apple.com/design/human-interface-guidelines/foundations/color/
  - https://developer.apple.com/design/human-interface-guidelines/buttons
  - https://developer.apple.com/design/human-interface-guidelines/tab-bars
  - https://developer.apple.com/design/human-interface-guidelines/toolbars
  - https://developer.apple.com/design/human-interface-guidelines/search-fields
  - https://developer.apple.com/design/human-interface-guidelines/searching
  - https://developer.apple.com/design/human-interface-guidelines/sheets
  - https://developer.apple.com/design/human-interface-guidelines/popovers/
  - https://developer.apple.com/design/human-interface-guidelines/alerts
- Apple SwiftUI documentation and sample code:
  - https://developer.apple.com/documentation/technologyoverviews/liquid-glass
  - https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
  - https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
  - https://developer.apple.com/documentation/swiftui/glass
  - https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29
  - https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass
  - https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent
  - https://developer.apple.com/documentation/swiftui/glasseffectcontainer
  - https://developer.apple.com/documentation/swiftui/view/glasseffectid%28_%3Ain%3A%29
  - https://developer.apple.com/documentation/updates/swiftui
  - https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass
  - https://developer.apple.com/documentation/swiftui/landmarks-refining-the-system-provided-glass-effect-in-toolbars
  - https://developer.apple.com/documentation/swiftui/landmarks-displaying-custom-activity-badges
- Apple WWDC25 videos:
  - https://developer.apple.com/videos/play/wwdc2025/219/ - Meet Liquid Glass
  - https://developer.apple.com/videos/play/wwdc2025/356/ - Get to know the new design system
  - https://developer.apple.com/videos/play/wwdc2025/323/ - Build a SwiftUI app with the new design
  - https://developer.apple.com/videos/play/wwdc2025/284/ - Build a UIKit app with the new design
- Apple gallery examples:
  - https://developer.apple.com/design/new-design-gallery-2026/
  - https://developer.apple.com/design/new-design-gallery/

## Key Apple Guidance

### 1. Start With Standard SwiftUI Components

Apple's adoption guidance says existing apps should first build with the latest
Xcode and SDKs, then inspect how standard framework components pick up the new
look. For Codex Dock, this means the first design move should not be a custom
glass renderer. It should be a migration back toward standard `NavigationStack`,
`TabView`, `.toolbar`, `.searchable`, system `Button` styles, system menus, and
system presentation APIs.

Plan implication:

- Prefer native `TabView`, `NavigationStack`, `.toolbar`, `.searchable`,
  `Menu`, `.sheet`, `.confirmationDialog`, and context menus.
- Remove custom hidden navigation chrome where it prevents the system from
  applying the iOS 26 navigation/tooling treatment.
- Keep custom styling for domain content only where standard components do not
  express the Codex Dock model.

### 2. Liquid Glass Belongs In The Control And Navigation Layer

Apple's materials guidance draws a strong boundary: Liquid Glass is for the
functional layer above content, such as navigation and controls. Standard
materials remain appropriate inside the content layer. Overusing Liquid Glass in
custom content can make hierarchy confusing and can distract from content.

Plan implication:

- Use Liquid Glass for top/bottom controls, toolbar buttons, the composer
  control cluster, important transient controls, and selected primary actions.
- Do not make every `DockRowView`, `ThreadEventCard`, `RequestCardView`,
  `HostSettingsRow`, or message card a glass object.
- For content cards, prefer system adaptive backgrounds like grouped
  backgrounds, secondary grouped backgrounds, thin/regular material only when
  semantically useful, and semantic foreground styles.

### 3. Use Color Sparingly On Liquid Glass

Apple's color guidance says Liquid Glass naturally picks up color from content
behind it, and color should be reserved for elements that truly need emphasis.
For primary actions, color belongs on the glass background more than on the
symbol or label.

Plan implication:

- Keep Codex Dock's blue accent, but do not flood the interface with blue.
- Reserve colored prominent glass for primary actions like Send, Connect, Save,
  or Approve.
- Use status colors for status chips, rails, and warnings, but check contrast in
  light mode, dark mode, and Increased Contrast.
- Avoid applying the same bright accent color to text labels sitting on already
  colorful or translucent backgrounds.

### 4. Respect Light Mode And Dark Mode By Design

The app already uses many semantic colors: `.primary`, `.secondary`,
`.background`, and `Color(uiColor: .systemGroupedBackground)`. Those are the
right foundation because they respond to system appearance. The plan should
preserve this and avoid hard-coded light or dark surfaces.

Plan implication:

- Keep semantic colors for text and backgrounds.
- Prefer `Color(uiColor: .systemGroupedBackground)`,
  `Color(uiColor: .secondarySystemGroupedBackground)`, `.background`,
  `.regularMaterial`, or `.thinMaterial` over fixed RGB values.
- Any new design token layer must be semantic and environment-aware.
- Verification must include light and dark screenshots/manual checks on
  `iPhone 17`.

### 5. Accessibility Settings Are Part Of The Material Contract

Apple describes Liquid Glass as adapting to accessibility settings such as
Reduced Transparency, Increased Contrast, and Reduced Motion. This benefit
comes from using system materials and controls, not from imitating the effect
manually.

Plan implication:

- Use system-provided glass and materials instead of fake blur/tint stacks.
- Avoid custom motion that assumes elastic glass behavior is always enabled.
- Verify Reduced Transparency, Increased Contrast, Reduce Motion, Dynamic Type,
  and VoiceOver labels for the main flow.
- Keep hit targets at least 44x44 pt on iOS.

### 6. Buttons Need Clear Role, State, And Touch Area

Apple's button guidance emphasizes clear purpose, enough space, built-in press
states, and one or two prominent buttons per view. Buttons can show an activity
indicator when a task does not complete instantly.

Plan implication:

- Keep icon buttons at or above 44x44 pt.
- Use system roles for destructive actions like Archive or Decline when the API
  supports it.
- Use progress indicators inside Send/Connect/Test buttons when work is in
  flight.
- Do not use many prominent buttons in one card. Request cards should make the
  likely primary action obvious without turning every action into a saturated
  control.

### 7. Toolbars Should Be Standard, Grouped, And Symbol-First

Apple's toolbar guidance says toolbars contain titles, navigation controls,
search fields, and actions. Toolbar items should be deliberate, grouped by
function, and usually use recognizable symbols instead of text for common
actions. The Landmarks Liquid Glass sample shows that system toolbars get the
glass treatment automatically and that grouping toolbar items improves utility.

Plan implication:

- Move Dock, Archive, Relay, and bootstrap header actions into `.toolbar` where
  possible.
- Use `ToolbarSpacer` or logical toolbar grouping when available with the iOS 26
  SDK.
- Keep standard back/close behavior instead of custom header controls.
- Keep text labels where a symbol alone is ambiguous, especially inside request
  cards and forms.

### 8. Tab Bars Are Top-Level Navigation, Not Action Bars

Apple's tab bar guidance says tab bars navigate between top-level app sections.
In iOS 26, the tab bar floats above content on Liquid Glass and can allow
content to peek through. Search can be a distinct tab when search is important.

Plan implication:

- Keep `Dock`, `Archive`, and `Relay` as top-level tabs.
- Do not put one-off actions into the tab bar.
- Consider a Search tab only if search becomes a global app concept. For the
  current app, local session filtering/search inside Dock remains the better
  recognizable path.
- Preserve navigation state per tab.

### 9. Search Should Use The System Search Pattern

Apple's search guidance says search should have one clear place and use
placeholder text to explain what is searchable. Search can be a primary action,
toolbar field, tab, or inline field depending on the app.

Plan implication:

- Replace the custom Dock search HStack with `.searchable` or an iOS 26 toolbar
  search placement where it preserves the current feed shape.
- Keep the placeholder specific: "Search sessions".
- Keep search as a filter over Dock rows, not a separate global search product
  in this modernization pass.

### 10. Presentations Should Stay Contextual And Small

Apple's sheets, popovers, alerts, and menus guidance all point toward contextual
presentation: sheets for scoped tasks, popovers for small temporary controls on
wide views, action sheets/confirmation dialogs for choices tied to an action,
and alerts only for critical interruptive information.

Plan implication:

- Use `Menu` and `contextMenu` for row labels/colors/archive options.
- Use `.confirmationDialog` for destructive or multi-choice confirmations when
  needed.
- Use alerts sparingly for critical failures; use inline banners for normal
  relay/session errors.
- Keep Relay editing as a scoped form surface; it can become a sheet only if
  that makes the top-level Relay screen cleaner without hiding important state.

### 11. Shapes Should Harmonize With The System

Apple's new design system guidance emphasizes concentricity, capsule controls,
and consistent shape families. SwiftUI's default Liquid Glass effect shape is a
capsule, while larger custom glass can use rounded rectangles where a capsule
would look odd.

Plan implication:

- Use capsules for compact control chips and toolbar-style controls.
- Use rounded rectangles for content cards and forms, but keep radii consistent
  and avoid deeply nested card-in-card stacks.
- Increase content-card radius only if it harmonizes with surrounding system
  controls; do not turn every card into a pill.

### 12. Custom Liquid Glass Needs Performance Discipline

Apple's SwiftUI guidance says `GlassEffectContainer` improves rendering and
lets multiple glass shapes morph together. It also warns that too many glass
effects and containers can hurt performance.

Plan implication:

- Use one shared custom glass helper only if needed for reuse and consistency,
  not for old-OS compatibility gating.
- Limit custom `.glassEffect` to a few important controls or compact clusters.
- Use `GlassEffectContainer` for adjacent custom glass controls that should
  visually merge or morph.
- Avoid row-level glass in long scrolling lists.

### 13. Deployment Target Cutover Matters

The user approved a clean iOS 26-only cutover on 2026-05-28. `Package.swift`,
`project.yml`, and the generated Xcode project must all move to iOS 26.0 before
implementation relies on iOS 26 SwiftUI APIs.

Plan implication:

- Raise the Swift package and Xcode targets to iOS 26.0.
- Run `rtk xcodegen generate --spec project.yml` after the `project.yml`
  change.
- Use iOS 26 SwiftUI APIs directly through shared helpers where that improves
  consistency.
- Do not keep an iOS 17-25 compatibility branch in the visual system.
- Do not use runtime shims that claim glass is active when it is not.

### 14. App Icons Now Have A Broader System Story

Apple's Landmarks sample and iOS 26 guidance describe a new app icon workflow
with Icon Composer and light, dark, clear, and tinted variants. This repo
already has generated app-icon files under `docs/app-icon/` and app icon wiring
in `project.yml`.

Plan implication:

- Treat app icon modernization as a named later phase or explicit design asset
  pass, not as hidden UI code work.
- If app icon wiring changes, update `project.yml` first and regenerate with
  `rtk xcodegen generate --spec project.yml`.
- Keep icon assets in the canonical asset path used by the Xcode project, not
  only in docs.

## Codex Dock App-Specific Translation

### Current Screens

- Bootstrap relay setup: `CodexDock/Features/Dock/CodexDockBootstrapView.swift`
- Root tabs: `CodexDock/Features/Dock/DockView.swift`
- Dock feed and row cards: `CodexDock/Features/Dock/DockView.swift`
- Archive feed: `CodexDock/Features/Archive/ArchiveView.swift`
- Relay settings: `CodexDock/Features/Hosts/HostsView.swift`
- Thread detail timeline: `CodexDock/Features/Session/SessionDetailView.swift`
- Composer: `CodexDock/Features/Session/ComposerView.swift`
- Request cards: `CodexDock/Features/Session/RequestCardView.swift`

### Keep Recognizable

- Three-tab app shape: Dock, Archive, Relay.
- Dock feed grouped by host/branch sections.
- Session rows with status chip, repo/branch, summary, last activity, and color
  rail.
- Thread detail with header, composer, request cards, and event timeline.
- Relay setup and settings as utilitarian operational surfaces.

### Modernize First

- Restore system navigation and toolbar chrome instead of hiding it everywhere.
- Move header buttons into standard toolbars.
- Replace custom search rows with system search where it keeps current behavior.
- Add an iOS 26 design token/helper surface for semantic card backgrounds,
  control materials, glass usage, and light/dark behavior.
- Apply glass only to toolbar/control clusters and primary actions.
- Keep content cards semantic and readable in both appearances.

### Do Not Do

- Do not make every content card glass.
- Do not replace the app with a marketing-style hero or decorative scene.
- Do not introduce a second navigation model.
- Do not hard-code a light-only or dark-only palette.
- Do not keep iOS 17-25 compatibility branches after the approved iOS 26-only
  cutover.
- Do not make visual-golden tests the main proof. Use builds plus focused
  manual screenshots across appearances.

## Verification Checklist For Future Implementation

Required checks should be proportional to the phase being implemented:

- `rtk swift test --filter ThreadDetailStoreTests` for composer/thread-detail
  behavior changes.
- `rtk swift test --filter DockStoreTests` for Dock, host, archive, registry,
  or metadata behavior changes.
- `rtk xcodegen generate --spec project.yml` when project target settings,
  Info.plist, assets, or icon wiring change.
- `rtk xcodebuild -project CodexDock.xcodeproj -scheme CodexDockApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
  for app target UI/project changes.
- Manual or screenshot review on `iPhone 17` in light mode and dark mode.
- Manual accessibility review for Dynamic Type, VoiceOver labels, Reduced
  Transparency, Increased Contrast, and Reduce Motion when glass/motion/control
  behavior changes.
