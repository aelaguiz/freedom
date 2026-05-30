Create a polished landscape 16:10 product-flow board for Codex Dock using the
provided screenshots as visual anchors. The board should show the full pin and
unpin experience for Option B: Pinned as a Dock lens.

Canvas:
- landscape UI storyboard board, 1536x1024
- four iPhone 17 portrait screens arranged left-to-right in a 4-panel flow
- app styling should match the existing Codex Dock screenshots and generated
  pinned lens mockup
- crisp native iOS typography, light app background, blue selected controls

Board title:
- "Option B: Pinned Lens"

Panel labels:
1. "1. Pin from detail"
2. "2. Pinned lens appears"
3. "3. Review pinned"
4. "4. Unpin from lens"

Panel 1:
- Thread detail screen for "psmobile animation engine".
- Header metadata "Amir-M5 · psmobile · feat/anim_stages".
- Top toolbar shows an outline pin icon.
- Show the user tapping the toolbar action; use callout text "Pin".

Panel 2:
- Dock screen with lens row containing "Newest", "Pinned", "Host", "Branch".
- "Pinned" is selected in blue.
- Summary reads "Pinned 1 · sorted by newest activity".
- Show one pinned row for "psmobile animation engine" with filled pin icon and
  metadata.

Panel 3:
- Same Pinned lens with three pinned rows:
  1. "ramp up on code base..." / "Amir-M5 · freedom · codex-dock-agents-tab-live-counts" / "now"
  2. "psmobile animation engine" / "Amir-M5 · psmobile · feat/anim_stages" / "now"
  3. "relay aggregator architecture" / "Home · codex-client · dock-relay-aggregator" / "2m"
- Keep rows dense and scannable.

Panel 4:
- Show a row swipe or context menu within the Pinned lens.
- The visible action is "Unpin".
- After unpin, the list shows "Pinned 2 · sorted by newest activity".
- The unpinned row is no longer in the pinned list.

Required exact visible labels somewhere:
- "Dock"
- "Online 2/2"
- "Pinned"
- "Pinned 1 · sorted by newest activity"
- "Pin"
- "Unpin"
- "Pinned 2"

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- no app-level "Pinned" tab at the bottom
- no giant pinned cards
