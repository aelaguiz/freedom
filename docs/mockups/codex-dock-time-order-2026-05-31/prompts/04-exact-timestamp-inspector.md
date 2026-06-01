Create a polished iPhone 17 portrait UI mockup for Codex Dock showing exact
timestamp inspection. Use the attached fresh current Thread screenshot, prior
Thread Liquid Glass mockup, current Dock screenshot, and compact controls
reference as anchors.

Design goal:
- Show how a user can start from relative time in the normal UI and open an
  exact timestamp/detail inspector when they need audit-level certainty.
- Keep the screen in the existing Codex Dock visual language.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41, no device frame.
- Thread detail screen in the background with a selected Codex event.
- Header title: "Flutter tests".
- Timeline card selected: "Codex replied" with visible group time "2:10 PM".
- A native iOS popover or bottom sheet is open over the lower half of the
  screen.
- Sheet title: "Event time".
- The sheet shows both relative and exact times with clear labels.
- Include event source and sequence context in human language.
- Include actions "Copy event link" and "Show exact timestamps".

Exact readable UI text to include:
- "Flutter tests"
- "Codex replied"
- "2:10 PM"
- "Event time"
- "Relative"
- "7 minutes ago"
- "Exact local time"
- "May 31, 2026 at 2:14:32 PM CDT"
- "Timezone"
- "America/Chicago"
- "Event"
- "Assistant message completed"
- "Arrival"
- "Dock received 2:14:34 PM CDT"
- "Seen"
- "First viewed 2:16 PM CDT"
- "After your 2:09 PM prompt"
- "Copy event link"
- "Show exact timestamps"

Visual rules:
- The normal UI should still use relative/compact time, but the inspector must
  show exact local time.
- The sheet should feel native to iOS and reachable on touch, not hover-only.
- Keep labels readable and aligned like a real settings/detail sheet.
- Use solid cards for technical content and restrained glass for the sheet
  chrome/control surfaces.
- Avoid raw Unix timestamps, bare UUIDs, lorem ipsum, fake app names, or
  decorative marketing styling.
