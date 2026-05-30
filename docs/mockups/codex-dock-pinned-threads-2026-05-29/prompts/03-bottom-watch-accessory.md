Create a polished iPhone 17 portrait UI mockup for Codex Dock using the
provided screenshots as visual references.

Goal: show the "bottom watch accessory" alternative. Pinned threads remain
visible while the user scrolls, similar to a compact mini-player, but still
belong to Dock.

Keep from the current app:
- title "Dock"
- "Online 2/2"
- search field
- "Newest", "Host", "Branch", and filter controls
- regular newest feed rows
- bottom tabs "Dock", "Archive", "Relay"
- short host names like "Amir-M5" and "Home"

Main layout:
- "Newest" is selected.
- Do not add a large pinned section at the top.
- Show the regular newest feed occupying the main space.
- Add a compact floating accessory immediately above the bottom tab bar.
- Accessory text: "Pinned 3"
- Accessory includes two tiny live snippets:
  "ramp up... now" and "anim engine now", plus a third indicator "+1".
- Accessory has a pin icon and an expand chevron.
- It should look touchable but not cover too much content.
- The feed behind it should remain readable.

Avoid:
- no "Needs me"
- no "Limited"
- no rate-limit language
- no raw endpoint strings
- no huge bottom drawer
- do not replace the bottom tab bar

Visual quality:
- native iOS glass/accessory treatment that feels plausible in iOS 26
- restrained and practical, not decorative
- make the risk visible: this option consumes bottom space but keeps pins
  available while scrolling
