# Screen Requirements: 01 Newest Default

Mockup: `../../outputs/01-newest-default.png`

## Purpose

The default Dock screen is the activity recovery surface. It answers what changed most recently across hosts without forcing the user to start from a host or branch grouping.

## Requirements

- `S01-001` The screen MUST open with `Newest` selected by default.
- `S01-002` The first visible content after the Dock controls MUST be session rows, not large host status cards.
- `S01-003` The visible list MUST be a flat newest-first list across all included hosts.
- `S01-004` The selected `Newest` control MUST be visually and accessibly distinct from `Host`, `Branch`, and `Filters`.
- `S01-005` The header MUST show `Dock`, compact connectivity such as `Online 2/2`, full-width search, and Dock-internal lens controls.
- `S01-006` The search field MUST use a placeholder equivalent to `Search sessions, repo, branch, host`.
- `S01-007` Active filter summary MUST show at least host scope, branch scope, idle visibility, and result count when data is loaded.
- `S01-008` Default host scope MUST be `Any` unless the user explicitly filters or pins a host.
- `S01-009` Default branch scope MUST be `Any` unless the user explicitly filters or pins a branch.
- `S01-010` Idle visibility MUST be visible as `Idle: Off`, `Hide idle`, or equivalent when idle rows are hidden.
- `S01-011` Result count MUST describe visible results, not total cached or hidden rows.
- `S01-012` The list MUST NOT show a `NEWEST` section header if it wastes vertical space; a header is allowed only if it improves accessibility or scanability.

## Row Requirements

- `S01-020` Each row MUST show a meaningful title when available.
- `S01-021` Each row MUST show host when more than one host exists.
- `S01-022` Each row MUST show repo or working directory when available.
- `S01-023` Each row MUST show branch when available.
- `S01-024` Each row MUST show a small status chip such as `Idle`, `Running`, `Not loaded`, `Error`, or `Unknown`.
- `S01-025` Each row MUST show last activity time when available.
- `S01-026` Each loaded row SHOULD show a short latest-summary snippet.
- `S01-027` Rows MAY use colored rails or icons as scan aids, but text identity MUST remain sufficient without color.
- `S01-028` Rows MUST have a clear tap affordance or row navigation affordance.
- `S01-029` A `Not loaded` row MUST remain in the list unless the user hides `Not loaded` through an explicit filter.
- `S01-030` `Not loaded` MUST appear as a neutral status chip and MUST NOT be styled like an error.

## Ordering

- `S01-040` Rows MUST sort by newest last activity first.
- `S01-041` `Needs me` MUST NOT reorder rows.
- `S01-042` Host order MUST NOT split the default feed.
- `S01-043` Branch grouping MUST NOT split the default feed.
- `S01-044` Idle and not-loaded rows MUST follow the same sorting rules unless hidden by an explicit filter.

## Prohibited Content

- `S01-060` The screen MUST NOT show `Needs me`.
- `S01-061` The screen MUST NOT show `Limited`.
- `S01-062` The screen MUST NOT show `All 0`, `Needs me 0`, `Running 0`, or `Agents 0` as primary controls.
- `S01-063` The screen MUST NOT show raw endpoint strings in row metadata.
- `S01-064` The screen MUST NOT make host health larger or more prominent than the newest session rows.

## Acceptance Evidence

- A screenshot or accessibility dump shows `Newest` selected on first app open.
- The first visible row includes title, host, repo, branch, status, and time where data exists.
- Search spans the Dock content width on iPhone 17 portrait.
- A text search over accessibility output finds `Not loaded` where applicable and does not find `Limited`.
- A text search over the primary Dock accessibility output does not find `Needs me`.
