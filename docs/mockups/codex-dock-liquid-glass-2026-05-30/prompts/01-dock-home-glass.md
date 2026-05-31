Create a polished iPhone 17 portrait UI mockup for the existing Codex Dock app.
Use the attached current Dock screenshot, prior activity-first Dock mockup, and
compact controls reference as product/style anchors. This is an iOS 26 Liquid
Glass visual modernization, not a new product.

Design goal:
- Show the default daily Dock home screen with the latest iOS 26 look and feel.
- Keep the app recognizable: session feed, host/repo/branch/status metadata,
  root connectivity, newest-first scanning, and compact operational density.
- Use Liquid Glass only for navigation and controls, not as row decoration.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41 status bar, no device frame,
  no hand, no desktop background.
- Standard SwiftUI NavigationStack feel with large title text "Dock".
- Top-right toolbar/control cluster on Liquid Glass: connectivity chip
  "Online 2/2" and a compact More button.
- System search entry on a glass surface with placeholder
  "Search sessions, repo, branch, host".
- A single glass control cluster for "Newest", "Host", "Branch", and the
  filter icon. The selected state is clear but not saturated.
- Compact active filter chips: "Hosts: Any", "Branch: Any", "Idle hidden",
  and "1,178 shown".
- Dense readable session rows below. Rows should use solid adaptive grouped
  backgrounds, subtle border/shadow, colored status rails, and semantic status
  chips such as "Active", "Idle", and "Not loaded".
- Bottom iOS 26 tab bar may appear floating and translucent, but it must not
  cover important row text.

Exact readable UI text to include:
- "Dock"
- "Online 2/2"
- "Search sessions, repo, branch, host"
- "Newest"
- "Host"
- "Branch"
- "Hosts: Any"
- "Branch: Any"
- "Idle hidden"
- "1,178 shown"
- Row titles: "review docs/epic/SCENE_RENDERING_UNIFICATION", "Implement the scene-rendering unification epic", "Fix asset disposal race condition"
- Row metadata examples: "Amir-M5", "Home", "codex-client", "feat/remount"

Visual rules:
- Content remains the star; glass should be quiet, functional, and sparse.
- Use system blue as the main accent, with green/orange/purple row rails.
- Keep typography crisp and native to iOS. No garbled labels, no lorem ipsum,
  no fake brand names, no marketing hero composition.
- Avoid making every row, card, or background a transparent glass panel.
