Create a polished iPhone 17 portrait UI mockup for the Codex Dock home screen.
Use the attached current Dock screenshot, prior time/order Dock mock, and prior
glass Dock mock as visual anchors. This is the existing Codex Dock app, not a
marketing page.

Design goal:
- Show the two UX features together: time/order clarity plus conversation-first
  message type triage.
- The Dock should feel like an activity inbox where the user can instantly tell
  what happened, when it happened, and whether it was a reply, work, or a
  needs-me request.
- Keep the app compact, native, and scannable.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Top title "Dock".
- Search field.
- Online pill "Online 2/2".
- Sort control labeled "Sort: Newest activity".
- Compact filter chips or segmented controls:
  - "Newest"
  - "Replies"
  - "Needs me"
  - "Work"
- Separate visible sections:
  - "Needs me"
  - "Newest conversations"
  - "Work updates"

Exact readable UI text to include:
- "Dock"
- "Online 2/2"
- "Search threads, repo, branch, host"
- "Sort: Newest activity"
- "Newest"
- "Replies"
- "Needs me"
- "Work"
- "Needs me"
- "Flutter tests"
- "Needs approval since 12m ago"
- "Codex replied 2m ago"
- "1 new reply"
- "6 work hidden"
- "Review group 01 cutover"
- "Codex replied 4m ago"
- "2 replies"
- "Work hidden: plan, 3 commands, 1 file"
- "Fix clipped stage card layers"
- "Work updated 8m ago"
- "No new reply"
- "Command completed"
- "Build archive restore proof"
- "You sent 18m ago"
- "Waiting on Codex"
- "Amir-M5"
- "psmobile"
- "feat/refactoring_scenes"

Card behavior to show:
- The top-right card time is the latest meaningful activity age.
- Reply unread and hidden work are not the same thing.
- Needs-me state can be above ordinary newest activity without hiding the real
  activity age.
- Work-only activity is labeled as work, not as a chat reply.
- Pinned or special placement must not imply recency by itself.

Visual rules:
- Use the attached app screenshots for spacing, chips, fonts, and iOS feel.
- Use solid readable cards, 8px-ish radius, restrained color.
- Use blue for conversation/reply affordances, amber for needs-me approval,
  green for running/live, and neutral gray for work-only activity.
- Use icons where helpful: chat bubble for replies, shield/check for approval,
  terminal for command/work, clock for time.
- Avoid random lorem ipsum, fake brands, unreadable microtext, giant hero art,
  or decorative gradients.
