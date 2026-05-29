# Screen Requirements: 08 Filtered Empty Results

Source: `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md` section 15.

## Purpose

Filtered empty state explains that the Dock list is empty because the user's current search, filters, or hidden-state choices exclude all rows. It must make recovery obvious.

## Requirements

- `S08-001` Empty results caused by filters MUST say no sessions match the current filters.
- `S08-002` Empty results caused by search MUST show the active search query.
- `S08-003` Empty results caused by host filter MUST show the active host filter.
- `S08-004` Empty results caused by branch filter MUST show the active branch filter.
- `S08-005` Empty results caused by idle visibility MUST show idle visibility state.
- `S08-006` Empty results caused by status filter MUST show the active status filter.
- `S08-007` Empty results caused by repo or source filter MUST show that active filter when applied.
- `S08-008` Empty state MUST provide a clear action to clear filters.
- `S08-009` Empty state SHOULD provide a clear action to clear only search when search is active.
- `S08-010` Empty state MUST preserve the header, search field, lens controls, and bottom tabs.

## Behavior

- `S08-020` Clearing filters MUST restore default explicit state without changing app-level tab.
- `S08-021` Clearing search MUST preserve non-search filters unless the user chooses clear all.
- `S08-022` The selected lens MUST remain visible in empty state.
- `S08-023` Empty state MUST update when filters or search change.
- `S08-024` Empty state MUST not imply host failure unless a host failure is actually known.
- `S08-025` Empty state MUST not imply rate limiting.

## Copy

- `S08-030` Primary copy SHOULD be equivalent to `No sessions match these filters`.
- `S08-031` Secondary copy SHOULD list active constraints compactly, for example `Host: Amir-M5`, `Branch: dock-ui`, and `Idle: Off`.
- `S08-032` Clear action copy SHOULD be equivalent to `Clear filters`.
- `S08-033` Copy MUST use the same filter names as the rest of Dock.

## Prohibited Content

- `S08-040` Empty state MUST NOT show `Limited`.
- `S08-041` Empty state MUST NOT show `Needs me` as a suggested default recovery path.
- `S08-042` Empty state MUST NOT hide which filter caused the empty result.
- `S08-043` Empty state MUST NOT clear filters automatically.
- `S08-044` Empty state MUST NOT navigate away from Dock automatically.
- `S08-045` Empty state MUST NOT use raw endpoint strings as primary host names.

## Acceptance Evidence

- Applying a filter combination with zero matches shows active constraints and `Clear filters`.
- Clearing search and clearing all filters behave differently when both are active.
- Accessibility output exposes the empty message, active constraints, and clear action.
