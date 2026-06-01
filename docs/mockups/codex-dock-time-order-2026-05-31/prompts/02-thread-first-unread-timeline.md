Create a polished iPhone 17 portrait UI mockup for Codex Dock's Thread detail
screen. Use the attached fresh current Thread screenshot, prior Thread Liquid
Glass mockup, and current Dock screenshot as anchors. This is the existing app
with a best-in-class chronological timeline and first-unread UX.

Design goal:
- Show that the user always knows where they are in the thread, what order the
  events are in, and where new content starts.
- Keep the current Codex Dock product model: thread header, host/repo/branch
  chips, message filter, composer, message cards, command/request events.
- Make time and order visible without making the screen feel cluttered.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Inline navigation: back chevron labeled "Dock", title "Flutter tests", More
  button.
- Header metadata chips: "Amir-M5", "psmobile", "feat/refactoring_scenes",
  "Live", "Running".
- Thread header status row: "Last activity 2m ago · 4 new".
- Order label: "Viewing oldest → newest · Local time CDT".
- Header actions: "First unread" and "Latest".
- Timeline with a vertical rail, solid readable cards, and date dividers.
- Date divider "Today".
- First-unread divider in the timeline: "New since you last looked · 2:10 PM".
- Messages after the divider should feel new but not loud.
- Composer at bottom uses the app's current glass/solid style.

Exact readable UI text to include:
- "Dock"
- "Flutter tests"
- "Amir-M5"
- "psmobile"
- "feat/refactoring_scenes"
- "Live"
- "Running"
- "Last activity 2m ago · 4 new"
- "Viewing oldest → newest · Local time CDT"
- "First unread"
- "Latest"
- "Today"
- "You"
- "2:09 PM"
- "Can you confirm the scene rendering constants?"
- "New since you last looked · 2:10 PM"
- "Codex"
- "2:10 PM"
- "I found the remaining geometry mismatch."
- "Command"
- "2:11 PM"
- "rtk rg SCENE_RENDERING docs"
- "Approval needed"
- "Run command in workspace"
- "Deny"
- "Approve"
- "Message Codex"

Visual rules:
- Conversation order must clearly read top-to-bottom, oldest-to-newest.
- Date divider and unread divider should be visible anchors, not tiny gray
  metadata.
- Use compact exact clock times on message groups.
- Keep long message cards solid white/adaptive grouped, not transparent glass.
- Use amber for approval, green for live/running, blue for navigation/time
  affordances.
- Keep typography native, crisp, and readable.
- Avoid garbled labels, lorem ipsum, fake brands, or generic chat bubbles that
  do not resemble Codex Dock.
