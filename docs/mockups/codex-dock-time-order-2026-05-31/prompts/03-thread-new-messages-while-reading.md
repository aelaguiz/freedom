Create a polished iPhone 17 portrait UI mockup for Codex Dock's Thread detail
screen showing the user scrolled away from the live edge while new messages
arrive. Use the attached fresh current Thread screenshot, prior Thread Liquid
Glass mockup, and current Dock screenshot as product/style anchors.

Design goal:
- Show best-in-class live update behavior: new messages do not yank the
  viewport while the user is reading older content.
- The user can see which day they are reading, that newer messages arrived, and
  how to jump forward.
- Keep Codex Dock recognizable and dense.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Inline navigation: "Dock" back, title "Review group 01 cutover", More button.
- Header metadata chips: "Amir-M5", "psmobile", "feat/refactoring_scenes",
  "Live".
- Sticky day header just under the thread metadata: "Today · 17 events · 4 unread".
- The timeline is scrolled to older content around 1:42 PM.
- Show solid event cards with group timestamps.
- At the bottom above the composer, show a floating pill/button:
  "3 new messages · latest 2m ago".
- Also show a secondary "Jump to latest" action in or near that pill.
- The composer remains visible but the viewport is not auto-scrolled to the
  newest message.

Exact readable UI text to include:
- "Dock"
- "Review group 01 cutover"
- "Amir-M5"
- "psmobile"
- "feat/refactoring_scenes"
- "Live"
- "Today · 17 events · 4 unread"
- "You"
- "1:42 PM"
- "ramp up on GROUP_01 scene ownership"
- "Codex"
- "1:43 PM"
- "I checked the parent and peer documents."
- "Command completed"
- "1:44 PM"
- "42 lines"
- "3 new messages · latest 2m ago"
- "Jump to latest"
- "Message Codex"

Visual rules:
- Make the floating new-message control obvious but not disruptive.
- Do not show the latest messages themselves; this mock is about preserving the
  user's current reading position.
- Keep the event timeline solid and readable.
- Use a vertical timeline rail and compact timestamps.
- Use blue for jump/new-message affordances, green for live state, neutral gray
  for older event metadata.
- The mock should look like a real SwiftUI app screen, not a web chat mockup.
