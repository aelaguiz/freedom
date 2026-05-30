Create a polished iPhone 17 portrait UI mockup for Codex Dock using the
provided screenshots as visual references.

Goal: show a pinned filter/manage surface. This supports cleanup and review of
pinned threads; it is a companion to the recommended watch strip, not the only
pinned UX.

Keep from the current Filters screenshot:
- modal sheet with large title "Filters"
- top-right "Clear" action
- white card/sheet background over dimmed app
- compact chip controls
- native iOS typography

Main layout:
- Title: "Filters"
- Top summary: "3 pinned · 400 total shown"
- First section is "Pinned" with chips:
  "Any", "Pinned only", "Unpinned"
  and "Pinned only" is selected.
- Add a small "Manage pinned" subsection below the chips with three dense rows.
- Each pinned management row has a pin icon, title, host/repo/branch metadata,
  time, and an "Unpin" action.
- Use exact row text:
  1. "ramp up on code base..." / "Amir-M5 · freedom · codex-dock-agents-tab-live-counts" / "now"
  2. "psmobile animation engine" / "Amir-M5 · psmobile · feat/anim_stages" / "now"
  3. "relay aggregator architecture" / "Home · codex-client · dock-relay-aggregator" / "2m"
- After the pinned section, keep the existing filter sections visible below:
  Host, Branch, Status, Repo.
- The Branch grid should be less dominant than in the current screenshot,
  because pinned management is the active task.

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- no giant cards
- no fake predictive labels

Visual quality:
- crisp labels and touchable controls
- compact management list
- clear selected state for "Pinned only"
