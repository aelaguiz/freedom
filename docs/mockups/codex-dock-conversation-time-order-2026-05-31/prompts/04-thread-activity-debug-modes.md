Create a polished iPhone 17 portrait UI mockup for Codex Dock's Thread detail
screen showing the Activity and Debug depth model. Use the attached current
Thread screenshot, prior first-unread timeline mock, and prior timestamp
inspector mock as anchors. This should make clear that raw event detail exists,
but it is not the default conversation view.

Design goal:
- Show the event-density ladder in one realistic screen: Conversation, Work,
  Files, Activity, Debug.
- Activity is selected and shows every supported event as a readable timeline
  with type labels, actor, status, and timestamps.
- Debug details are available in a contained inspector, not mixed into every
  chat row.
- Exact timestamps are visible because Activity/Debug is audit mode.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Top navigation: "Dock", title "Flutter tests", More button.
- Header status:
  "Activity - exact timestamps - oldest to newest"
- View mode control with "Activity" selected:
  "Conversation", "Work", "Files", "Activity", "Debug".
- Filter chips:
  "All", "Messages", "Commands", "Files", "Tools", "Web".
- A chronological activity timeline with readable event rows.
- A small lower inspector card titled "Debug details" for the selected event.

Exact readable UI text to include:
- "Dock"
- "Flutter tests"
- "Activity"
- "Conversation"
- "Work"
- "Files"
- "Debug"
- "Activity - exact timestamps - oldest to newest"
- "All"
- "Messages"
- "Commands"
- "Files"
- "Tools"
- "Web"
- "Today"
- "2:09:08 PM"
- "userMessage"
- "You sent a message"
- "2:09:21 PM"
- "plan"
- "Plan created"
- "2:10:03 PM"
- "commandExecution"
- "Command started"
- "2:10:54 PM"
- "fileChange"
- "Edited 3 files"
- "2:11:32 PM"
- "agentMessage final_answer"
- "Codex replied"
- "Debug details"
- "turnId"
- "itemId"
- "ThreadItem.type"
- "timestamp source: app-server"
- "Copy event"

Visual rules:
- Activity is a timeline/log hybrid, not a chat transcript.
- Type labels should be clear but compact.
- Exact timestamps are okay here; Conversation should stay cleaner.
- Debug details should be contained in the inspector card.
- Use monospace only for IDs/type labels, not for the whole UI.
- Avoid overwhelming the screen with full JSON.
- Keep the styling native to the attached Codex Dock screenshots.
