Create a polished iPhone 17 portrait UI mockup for the existing Codex Dock app.
Use the provided screenshots as visual anchors, especially the current Dock live
screenshot. Keep the UI native to iOS 26 with compact Liquid Glass chrome,
clear typography, and dense readable session rows.

Option name: Dock only, maintenance in More.

Screen state:
- The main screen is `Dock`.
- The bottom root tab bar is gone.
- Reclaim the old tab bar space for the session list.
- Header row shows large `Dock`, a green status chip `Online 2/2`, and a compact circular More button with an ellipsis icon.
- The More menu is open from the top-right button.
- The menu items are exactly:
  - `Archive cleanup`
  - `Archived threads`
  - `System health`
  - `Relay settings`
- The menu should be compact and native, not a large card.
- Keep a full-width search field with placeholder `Search sessions, repo, branch, host`.
- Keep compact lens controls: `Newest`, `Host`, `Branch`, and a filter icon button.
- Keep active filter state compact. It can say `Human sessions · active only · Newest activity`, but it must not wrap into a tall block.
- Show at least six visible session rows so the reclaimed vertical space is obvious.
- Use realistic row content from the current Codex Dock domain: repo, branch, host, status, last activity, and short summary.

Design rules:
- No bottom `Archive` or `Relay` tabs.
- No marketing hero.
- No decorative gradient blobs.
- No nested cards.
- Keep text legible and inside its containers.
- Keep colors close to the current app, with a restrained blue accent and green online status.

Purpose:
Show that Archive, Relay, and diagnostics stay reachable while Dock becomes the
single daily surface with more visible thread rows.
