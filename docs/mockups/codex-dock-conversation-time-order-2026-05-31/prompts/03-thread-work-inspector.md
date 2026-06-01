Create a polished iPhone 17 portrait UI mockup for Codex Dock's Thread detail
screen showing the Work layer. Use the attached current Thread screenshot,
prior first-unread timeline mock, and prior exact timestamp inspector mock as
anchors. This screen should show how a user can inspect what Codex did without
losing the conversation or the time/order context.

Design goal:
- Show the same thread after the user taps "Show work" or switches to "Work".
- Conversation remains visible and ordered.
- The selected turn reveals readable work chips and an inspector/drawer with
  exact details.
- The user can still see when things happened and where they are in the thread.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Top navigation: "Dock", title "Flutter tests", More button.
- Header chips: "Amir-M5", "psmobile", "Live", "Running".
- Header row:
  "Work - oldest to newest - 6 events in this turn"
- View mode control with "Work" selected:
  "Conversation", "Work", "Files", "Activity", "Debug".
- Timeline remains visible behind the inspector.
- A selected turn has compact work chips:
  "Plan", "Commands 2", "Files 3", "Web 1", "Reasoning summary".
- The selected command row is visible in the timeline:
  "Command completed - 2:11 PM - 12s".
- Bottom inspector/drawer titled "Command details".

Exact readable UI text to include:
- "Dock"
- "Flutter tests"
- "Work"
- "Conversation"
- "Files"
- "Activity"
- "Debug"
- "Work - oldest to newest - 6 events in this turn"
- "Today"
- "You"
- "Can you confirm the scene rendering constants?"
- "Codex"
- "I found the remaining geometry mismatch."
- "Plan"
- "Commands 2"
- "Files 3"
- "Web 1"
- "Reasoning summary"
- "Command completed - 2:11 PM - 12s"
- "Command details"
- "commandExecution"
- "rtk rg SCENE_RENDERING docs"
- "cwd: /Users/aelaguiz/workspace/codex-client"
- "Exit code 0"
- "Completed Today at 2:11:32 PM CDT"
- "Open Activity"
- "Copy command"
- "Message Codex"

Visual rules:
- The Work mode should be denser than Conversation but still readable.
- The inspector should preserve context: do not navigate away to a blank log
  screen.
- Use a supplemental drawer/bottom sheet, not a full raw JSON page.
- Show exact local time in the inspector and compact time in the timeline.
- Use terminal/file/web icons where helpful.
- Use neutral backgrounds for work details, amber only for active approvals or
  failures, blue for selected controls.
- Avoid raw JSON dumps except for the small visible `commandExecution` type
  label.
