Create a polished iPhone 17 portrait UI mockup for Codex Dock using the
provided screenshots as visual references.

Goal: show the recommended pinned-threads design. Pinned threads are a tiny
user-owned watchlist for the 2-3 threads the user cares about right now.

Keep from the current app:
- large title "Dock"
- green connectivity chip "Online 2/2"
- full-width search field with placeholder "Search sessions, repo, branch, host"
- Dock lens row with "Newest", "Host", "Branch", and a compact filter icon button
- light iOS native style, dense professional tool UI, bottom tabs "Dock",
  "Archive", "Relay"
- short host names like "Amir-M5" and "Home"

Main layout:
- "Newest" remains selected.
- Keep the active-scope summary line compact: "400 shown · Hosts: Any · Idle hidden".
- Add a compact section below the scope line titled "Pinned 3" with a small
  "Manage" action.
- Show three dense pinned rows or cards, not giant cards.
- Pinned items should show a pin icon, title, host, repo, branch, status/time,
  and a chevron.
- Use plausible exact row text:
  1. "ramp up on code base..." / "Amir-M5 · freedom · codex-dock-agents-tab-live-counts" / "now"
  2. "psmobile animation engine" / "Amir-M5 · psmobile · feat/anim_stages" / "now"
  3. "relay aggregator architecture" / "Home · codex-client · dock-relay-aggregator" / "2m"
- Below the pinned section, continue the regular newest feed. Pinned rows may
  also appear in the feed with a small pin marker because the feed remains the
  true newest-first list.

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- no huge decorative cards
- no marketing-style hero
- do not make "Pinned" a bottom app tab

Visual quality:
- native iOS typography, crisp labels, exact icon alignment
- touch-friendly but dense
- keep enough of the newest feed visible in the first viewport
