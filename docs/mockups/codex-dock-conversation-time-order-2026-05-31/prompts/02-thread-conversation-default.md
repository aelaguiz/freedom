Create a polished iPhone 17 portrait UI mockup for Codex Dock's Thread detail
screen. Use the attached current Thread screenshot, prior first-unread timeline
mock, and prior glass Thread mock as anchors. This is the existing app with the
new conversation-first density model and clear time/order UX.

Design goal:
- Default Thread Detail should show the real back-and-forth: what the user said
  and what the primary Codex thread agent said back.
- Hidden work should be counted, not silently omitted.
- Time, order, unread position, and view mode should be visible.
- Active approvals and input requests pierce the default Conversation filter.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Inline navigation: back chevron labeled "Dock", title "Flutter tests", More
  button.
- Header metadata chips: "Amir-M5", "psmobile", "feat/refactoring_scenes",
  "Live", "Running".
- Thread status row:
  "Running - last reply 2m ago - 4 new - 6 work hidden"
- View mode control near the header with "Conversation" selected:
  "Conversation", "Work", "Files", "Activity", "Debug".
- Order label:
  "Conversation - oldest to newest - Local time: CDT"
- Header actions:
  "First unread" and "Latest".
- Timeline with a vertical rail, readable cards, and date dividers.
- Date divider "Today".
- First unread divider:
  "New since you last looked - 2:10 PM".
- Bottom composer with "Message Codex".

Exact readable UI text to include:
- "Dock"
- "Flutter tests"
- "Amir-M5"
- "psmobile"
- "feat/refactoring_scenes"
- "Live"
- "Running"
- "Running - last reply 2m ago - 4 new - 6 work hidden"
- "Conversation"
- "Work"
- "Files"
- "Activity"
- "Debug"
- "Conversation - oldest to newest - Local time: CDT"
- "First unread"
- "Latest"
- "Today"
- "You"
- "2:09 PM"
- "Can you confirm the scene rendering constants?"
- "Work hidden: plan, 2 commands, web search"
- "Show work"
- "New since you last looked - 2:10 PM"
- "Codex"
- "2:10 PM"
- "I found the remaining geometry mismatch."
- "Approval needed"
- "Run command in workspace"
- "Deny"
- "Approve"
- "Message Codex"

Visual rules:
- Conversation must clearly read top-to-bottom, oldest-to-newest.
- Conversation rows should be calmer and larger than work summaries.
- Hidden work summary should feel attached to the turn, not like a separate
  message from Codex.
- Approval card is visible in Conversation because it needs the user.
- Use compact exact group times on messages.
- Use amber for approval, green for live/running, blue for selected
  Conversation and navigation/time actions.
- Avoid showing command output as if it were the assistant response.
- Avoid random lorem ipsum, fake app names, and unreadable labels.
