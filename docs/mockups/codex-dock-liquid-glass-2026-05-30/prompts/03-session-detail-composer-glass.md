Create a polished iPhone 17 portrait UI mockup for Codex Dock's Thread detail
screen after an iOS 26 Liquid Glass visual modernization. Use the attached
legacy Session detail mockup, current Dock screenshot, and compact controls
reference as anchors.

Design goal:
- Modernize the Thread detail view without changing its product model.
- Show readable event history, request cards, command output cards, and the
  composer.
- Put Liquid Glass on navigation controls and the composer control cluster.
- Keep event cards solid and legible for long technical text.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Standard inline navigation bar: back chevron labeled "Dock", centered title
  "Dart animation SSOT", trailing More button.
- Under the toolbar, show compact metadata chips: "Home", "lessons_studio",
  "feature/animation", "Live", "Running".
- Event timeline with a thin vertical rail and readable cards.
- Include one assistant message card, one command card, one approval/request
  card, and one collapsed output row.
- Bottom composer floats above the tab bar/safe area on a Liquid Glass surface.
  It includes text field "Message Codex", hold mic, tap mic, and Send.
- Send is disabled until the draft has text; the glass treatment should still
  make the control cluster feel native.

Exact readable UI text to include:
- "Dock"
- "Dart animation SSOT"
- "Home"
- "lessons_studio"
- "feature/animation"
- "Live"
- "Running"
- "Codex"
- "I found the remaining Dart-owned recipe paths."
- "Command"
- "rtk rg table.pocket_cards apps/flutter"
- "Output collapsed"
- "42 lines"
- "Open"
- "Approval needed"
- "Run command in workspace"
- "Deny"
- "Approve"
- "Message Codex"
- "Hold"
- "Send"

Visual rules:
- Use native iOS typography and spacing.
- Message/event cards are not glass; they use adaptive grouped backgrounds with
  subtle borders and high contrast.
- The composer is the strongest custom glass moment in this screen.
- Use accent color only for clear meaning: blue for active/navigation, green
  for live/success, amber for approval.
- Avoid decorative glass overlays on long text.
