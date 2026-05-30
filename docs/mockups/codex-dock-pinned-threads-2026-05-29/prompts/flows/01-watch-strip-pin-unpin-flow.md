Create a polished landscape 16:10 product-flow board for Codex Dock using the
provided screenshots as visual anchors. The board should show the full pin and
unpin experience for Option A: compact pinned watch strip.

Canvas:
- landscape UI storyboard board, 1536x1024
- four iPhone 17 portrait screens arranged left-to-right in a 4-panel flow
- each phone screen should look like the current Codex Dock iOS app
- crisp native iOS typography, white/light-gray app background, blue selected
  controls, green "Online 2/2" chip

Board title:
- "Option A: Pinned Watch Strip"

Panel labels:
1. "1. Pin from row"
2. "2. Watch in Dock"
3. "3. Open pinned thread"
4. "4. Unpin when done"

Panel 1:
- Dock list with "Newest" selected.
- Show a row action state on the first row.
- The row title is "ramp up on code base..."
- Row metadata is "Amir-M5 · freedom · codex-dock-agents-tab-live-counts".
- Show a clear blue action button or swipe action labeled "Pin".
- Show a pin icon next to the "Pin" action.

Panel 2:
- Same Dock screen after pinning.
- Show compact section "Pinned 1" below the filters summary and above the
  newest feed.
- Pinned row shows a filled pin icon, "ramp up on code base...", metadata, and
  "now".
- The same row still appears in the regular newest feed with a small pin marker.
- Keep enough newest feed visible.

Panel 3:
- Thread detail screen for the pinned thread.
- Header shows title "ramp up on code base..."
- Header metadata shows "Amir-M5 · freedom".
- Top toolbar includes filled pin icon selected.
- Thread body can show a compact message list.
- The main point is that the thread remains easy to open from the pinned strip.

Panel 4:
- Back on Dock or a small manage sheet.
- Show the pinned row with a contextual menu or swipe action labeled "Unpin".
- After unpin, the pinned strip is gone or shrinking.
- Show short feedback text "Unpinned" as a subtle toast/snackbar near bottom,
  not a modal.

Required exact visible labels somewhere:
- "Dock"
- "Online 2/2"
- "Newest"
- "Pinned 1"
- "Pin"
- "Unpin"
- "Unpinned"

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- no fourth app-level tab
- no huge marketing hero
- no decorative blobs
