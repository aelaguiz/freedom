# Screen Requirements: 05 Filters

Mockup: `../../outputs/05-filters.png`

## Purpose

The filter surface gives explicit, reversible controls for narrowing a huge Dock list by host, branch, status, repo, sort order, idle visibility, and archive visibility.

## Requirements

- `S05-001` Selecting `Filters` or the equivalent filter control MUST open the Dock filter surface.
- `S05-002` The filter surface MUST remain within the Dock context, not become a top-level app tab.
- `S05-003` The selected `Filters` control MUST be visually and accessibly distinct when the filter surface is active.
- `S05-004` The filter surface MUST show visible result summary, for example `1,178 shown`.
- `S05-005` The filter surface MUST show whether filters are currently applied.
- `S05-006` The filter surface MUST provide `Reset`, `Clear`, or equivalent.
- `S05-007` If the surface uses staged changes, it MUST provide `Apply`.
- `S05-008` If the surface applies changes immediately, it MUST not show a misleading inactive `Apply` button.
- `S05-009` The filter surface MUST preserve the full-width global search field above or inside the filter context.
- `S05-010` If both the header filter icon and `Filters` lens/control are visible, they MUST open the same filter surface.
- `S05-011` If both the header filter icon and `Filters` lens/control are visible, active filter count or selected state MUST stay synchronized between them.

## Filter Sections

- `S05-020` Host filter MUST include `Any`.
- `S05-021` Host filter MUST include each configured host with short display names.
- `S05-022` Host filter SHOULD show counts or availability when practical.
- `S05-023` Branch filter MUST include branch search.
- `S05-024` Branch filter SHOULD show popular, recent, or matching branch chips.
- `S05-025` Branch filter MUST support selecting a branch chip.
- `S05-026` Status filter MUST include `Any`.
- `S05-027` Status filter MUST include `Running` when reliable data exists.
- `S05-028` Status filter MUST include `Idle`.
- `S05-029` Status filter MUST include `Not loaded`.
- `S05-030` Status filter MUST include `Error` when error rows exist.
- `S05-031` Repository filter MUST include available repos or working directories.
- `S05-032` Repository filter MUST include an all-repos state.
- `S05-033` Source filter MUST include human and agent scope when source data is available, even if the mockup labels this area as repository only.
- `S05-034` Sort controls MUST include newest last activity as the default.
- `S05-035` Sort controls MAY include created date.
- `S05-036` Sort controls MAY include updated date only if it is clearly distinct from newest last activity.
- `S05-037` Visibility controls MUST include idle visibility.
- `S05-038` Visibility controls MUST include archive visibility when archived sessions can be shown.
- `S05-039` Visibility controls MAY include not-loaded-only or show-not-loaded behavior if product chooses to expose it.
- `S05-040` If the user filters to `Not loaded` only, the results area MUST show explanatory copy that these sessions exist but Dock does not have loaded thread detail for them.
- `S05-041` If a `Not loaded`-only result section is shown, its section label MUST use `Not loaded`, not `Limited`.

## Interaction Rules

- `S05-050` Filters MUST compose with search.
- `S05-051` Filters MUST compose with the selected lens.
- `S05-052` Applying a host filter MUST update newest, host, and branch views consistently.
- `S05-053` Applying a branch filter MUST update newest, host, and branch views consistently.
- `S05-054` Applying a status filter MUST not change the meaning of status labels.
- `S05-055` Reset MUST restore the default explicit state.
- `S05-056` Filter changes MUST update visible result count when practical.
- `S05-057` The active filter summary outside the filter surface MUST reflect applied filters after the surface closes.
- `S05-058` Filter controls MUST be touch-friendly while preserving dense information layout.

## Prohibited Content

- `S05-070` Filters MUST NOT include `Needs me` as a default or primary filter.
- `S05-071` Filters MUST NOT show `Limited`.
- `S05-072` Filters MUST NOT hide branch behind search-only behavior.
- `S05-073` Filters MUST NOT use raw endpoint strings as host chip labels.
- `S05-074` Filters MUST NOT apply hidden constraints that are absent from summary state.
- `S05-075` Filters MUST NOT use ambiguous sort labels without a clear mapping to data fields.

## Acceptance Evidence

- A screenshot or accessibility dump shows the filter surface active.
- Host, branch, status, repo or working-directory, sort, idle, and archive controls are present.
- `Not loaded` exists as a status filter.
- `Limited` and `Needs me` are absent from the primary filter surface.
- Applying and resetting filters changes visible summary state predictably.
