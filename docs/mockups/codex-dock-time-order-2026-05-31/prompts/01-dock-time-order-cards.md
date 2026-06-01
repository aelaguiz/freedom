Create a polished iPhone 17 portrait UI mockup for the existing Codex Dock app.
Use the attached current live Dock screenshot, prior Dock Liquid Glass mockup,
and compact controls reference as product/style anchors. This is not a new app.
It is Codex Dock with best-in-class time, order, unread, and recency UX.

Design goal:
- Show the Dock card list as an activity inbox where the user instantly knows
  what changed, how long ago it changed, what is unread, and why each card is
  placed where it is.
- Keep the app recognizable: Codex Dock title, host/repo/branch metadata,
  compact iOS typography, operational density, and solid readable rows.
- Use Liquid Glass only for navigation, search, sort, and compact control
  surfaces. Keep thread cards solid and legible.

Layout:
- Native iPhone 17 screenshot, Dynamic Island, 9:41 status bar, no device
  frame, no hand, no desktop background.
- Large title: "Dock".
- Top-right controls: "Online 2/2" and a More button.
- Search field: "Search threads, repo, branch, host".
- Visible sort control labeled "Sort: Newest activity".
- Segmented/lens controls: "Newest", "Unread", "Needs input", "Pinned".
- A separate "Pinned" section above "Newest activity" so pinned cards do not
  pretend to be newer than they are.
- Cards should show title on the left and the last meaningful activity age on
  the top right.
- Card subtitle should say what happened, not just "updated".
- Unread cards need both count and age.
- Running/waiting cards need elapsed time.

Exact readable UI text to include:
- "Dock"
- "Online 2/2"
- "Search threads, repo, branch, host"
- "Sort: Newest activity"
- "Newest"
- "Unread"
- "Needs input"
- "Pinned"
- "Pinned"
- "Flutter tests"
- "Waiting for approval"
- "Needs input for 12m"
- "1 new"
- "Review group 01 cutover"
- "Codex replied - 3 new"
- "latest 2m ago"
- "New since 1:42 PM"
- "Fix clipped stage card layers"
- "Running for 8m"
- "No output for 6m"
- "Newest activity"
- "Build archive restore proof"
- "You sent 18m ago"
- "Amir-M5"
- "psmobile"
- "codex-client"
- "feat/refactoring_scenes"

Visual rules:
- The top-right time on each card is activity time: "2m ago", "12m ago",
  "18m ago", "Yesterday".
- Show small clock, unread dot/count, approval, and running icons where useful.
- Use a quiet native iOS palette with system blue, green, amber, and purple
  semantic accents.
- Keep text crisp and readable. No lorem ipsum. No generic fake app names.
- Avoid marketing hero layout, empty decorative gradients, and glass cards for
  long technical content.
- The mock should look like a believable SwiftUI screen in this repo, not a
  generic Dribbble chat concept.
