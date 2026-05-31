# Codex Dock Liquid Glass Research Notes

Date checked: 2026-05-30

## Bottom Line

Apple's current iOS 26 guidance supports a restrained modernization, not a
full visual reinvention.

For Codex Dock, that means:

- Use standard SwiftUI app structure first: `NavigationStack`, `TabView`,
  `.toolbar`, `.searchable`, system sheets, `Menu`, and standard buttons.
- Let system controls pick up Liquid Glass automatically where possible.
- Use custom glass only for important control clusters.
- Keep long content surfaces solid and readable.

## Apple Guidance Summary

### Liquid Glass Is A Functional Layer

Apple describes Liquid Glass as a dynamic material for controls and navigation.
The adoption guidance says standard SwiftUI/UIKit/AppKit components pick up the
new look when built with current SDKs.

Codex Dock implication:

- Use glass on toolbar controls, tab bar chrome, search, filter controls,
  sheets, compact status chips, and the composer.
- Do not make every `DockRowView`, `ThreadEventCard`, request card, or host row
  a glass object.

Sources:

- <https://developer.apple.com/documentation/technologyoverviews/liquid-glass>
- <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass>

### Standard Controls Before Custom Effects

Apple's "Build a SwiftUI app with the new design" session emphasizes that iOS
26 refines `TabView`, `NavigationSplitView`, sheets, toolbars, search, and
controls. It also says the best first move is to use standard app structures,
toolbars, search placements, and controls.

Codex Dock implication:

- Prefer standard navigation bars and toolbars over hidden custom headers.
- Prefer `.searchable` or a system search placement where it can preserve the
  Dock feed shape.
- Use `Menu` and native sheets for archive/relay maintenance actions.

Source:

- <https://developer.apple.com/videos/play/wwdc2025/323/>

### Toolbars Need Deliberate Grouping

Apple's toolbar guidance says toolbars hold navigation, search, and actions.
It also says to choose items deliberately and avoid overcrowding.

Codex Dock implication:

- The Dock header can use one compact action cluster: online chip plus More or
  Filters.
- Session detail can use a standard back button, centered title, and one More
  menu.
- Avoid turning the toolbar into a row of labeled pills.

Sources:

- <https://developer.apple.com/design/human-interface-guidelines/toolbars>
- <https://developer.apple.com/videos/play/wwdc2025/323/>

### Search Should Have One Clear Place

Apple's search guidance says important search should be visible and that the
placeholder should explain what content is searchable.

Codex Dock implication:

- Keep Dock search broad and clear: "Search sessions, repo, branch, host".
- Do not split search into multiple tiny fields across lenses.
- For Filters, use one filter search only inside the sheet.

Sources:

- <https://developer.apple.com/design/human-interface-guidelines/searching>
- <https://developer.apple.com/design/human-interface-guidelines/search-fields>

### Sheets Are Good For Focused Maintenance Jobs

Apple's iOS 26 sheet guidance and SwiftUI session describe partial-height sheets
as inset, Liquid Glass surfaces that let content peek through. Full-height sheets
become more opaque to keep focus.

Codex Dock implication:

- Archive Cleanup, Archived Threads, System Health, and Relay Settings fit as
  sheets better than permanent root tabs.
- The Dock screen can remain the daily surface while secondary jobs stay easy
  to reach.

Sources:

- <https://developer.apple.com/videos/play/wwdc2025/323/>
- <https://developer.apple.com/design/human-interface-guidelines/tab-bars/>

### Accessibility Is Part Of The Material Contract

Apple's Liquid Glass adoption guidance says the material adapts to settings such
as reduced transparency, increased contrast, and reduced motion when you use
system components.

Codex Dock implication:

- Avoid hand-built blur/tint stacks that pretend to be glass.
- Verify Reduced Transparency, Increased Contrast, Reduce Motion, Dynamic Type,
  and VoiceOver once implementation begins.
- Keep content-card contrast high even if glass becomes more opaque.

Source:

- <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass>

## Mockup Decisions

### Dock Home

Decision:

- Keep the Dock feed dense and recognizable.
- Use a glass control layer for online status, search, lenses, filters, and tab
  bar.
- Keep rows solid.

Why:

- The Dock is a scanning surface. It needs hierarchy and row count more than
  decorative translucency.

### Filters

Decision:

- Use an inset partial-height sheet with compact sections and active chips.

Why:

- The current filter model is broad. A sheet gives room for host, branch,
  status, source, idle, reset, and apply without crushing the first screen.

### Session Detail

Decision:

- Make the composer the main custom glass object.
- Keep event cards, commands, outputs, and approvals solid.

Why:

- The composer is interactive and always near the hand. Long technical output
  needs clarity more than glass.

### System Health And Relay

Decision:

- Model Relay as a focused System Health sheet with plain-language route status
  and a secondary Relay Settings row.

Why:

- Relay setup and diagnostics matter, but they are not the daily first-screen
  job.

### Archive Cleanup

Decision:

- Model cleanup as a focused sheet with age threshold, exclusions, preview, host
  split, and restore path.

Why:

- A destructive bulk operation needs preview and confidence. It should not be a
  hidden row action or a permanent tab.

## Implementation Guardrails

- Do not implement fake glass through custom blur/tint overlays.
- Do not make row cards or long text cards glass.
- Do not add iOS 17-25 fallback styling if the project remains iOS 26-only.
- Do not persist relay identity phone-side.
- Do not pass secrets such as `OPENAI_API_KEY` or raw app-server tokens to the
  app.
- Treat generated mockups as visual intent, not a pixel spec.
