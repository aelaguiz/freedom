# Screen Requirements: 06 Branch Search Results

Source: `docs/CODEX_DOCK_ACTIVITY_FIRST_DOCK_UX_2026-05-29.md` section 16.4.

## Purpose

Branch search is the fast known-target lookup state. It answers "show me the sessions for this branch or branch fragment" without forcing the user to understand branch grouping first.

## Requirements

- `S06-001` Entering a branch query such as `dock-ui` MUST show an active search state.
- `S06-002` Active search state MUST be visible as a chip, row, or equivalent summary, for example `Search: dock-ui`.
- `S06-003` Active search state MUST be clearable from the results screen.
- `S06-004` Branch search results MUST show visible result count when data is loaded.
- `S06-005` Branch search MAY flatten results into one newest-first result list even when the `Branch` lens is selected.
- `S06-006` If branch search preserves groups instead of flattening, the UI MUST still make the active search state and result count obvious.
- `S06-007` The chosen branch-search presentation MUST be consistent and documented; it MUST NOT sometimes flatten and sometimes group without visible reason.
- `S06-008` Branch search results MUST preserve active host, status, idle, repo, source, and archive filters.
- `S06-009` Branch search results MUST keep host visible on every row.
- `S06-010` Branch search results MUST keep branch visible on every row or in an active search token that is visually tied to the result list.

## Query Matching

- `S06-020` Branch search MUST match exact branch names.
- `S06-021` Branch search MUST match branch fragments.
- `S06-022` Branch search MUST match slash-separated branch names.
- `S06-023` Branch search MUST support repo plus branch.
- `S06-024` Branch search MUST support host plus branch.
- `S06-025` Branch search MUST support case-insensitive matching unless there is a product reason to expose case sensitivity.
- `S06-026` Branch search MUST handle long branch names without breaking layout.

## Result Rows

- `S06-030` Result rows MUST show title when available.
- `S06-031` Result rows MUST show host when more than one host exists.
- `S06-032` Result rows MUST show repo or working directory when available.
- `S06-033` Result rows MUST show branch when available.
- `S06-034` Result rows MUST show status when available.
- `S06-035` Result rows MUST show last activity time when available.
- `S06-036` Result rows SHOULD show a short latest-summary snippet when loaded detail exists.
- `S06-037` Result rows MUST sort newest-first unless the user chose another explicit sort.

## Empty And Partial Results

- `S06-040` Empty branch-search results MUST state the query and active filters that caused emptiness.
- `S06-041` Empty branch-search results MUST provide a clear action to clear the search or clear filters.
- `S06-042` Partial host failures MUST not hide matches from online hosts.
- `S06-043` Not-loaded matches MUST appear with `Not loaded` unless hidden by an explicit filter.
- `S06-044` Not-loaded matches MUST not imply rate limits.

## Prohibited Content

- `S06-050` Branch search results MUST NOT show `Limited`.
- `S06-051` Branch search results MUST NOT show `Needs me` as a primary category.
- `S06-052` Branch search results MUST NOT rely on endpoint strings as host identity.
- `S06-053` Branch search MUST NOT be buried only inside the filter sheet.
- `S06-054` Branch search MUST NOT require the user to first select the correct host.

## Acceptance Evidence

- Searching for a known branch or fragment shows visible active search state and a visible result count.
- Results include host, repo, branch, status, and last activity where data exists.
- Clearing search restores the prior lens and filters.
- Accessibility output exposes the active search query and result count.
