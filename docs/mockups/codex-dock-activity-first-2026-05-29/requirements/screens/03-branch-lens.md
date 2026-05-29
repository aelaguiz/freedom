# Screen Requirements: 03 Branch Lens

Mockup: `../../outputs/03-branch-lens.png`

## Purpose

The branch lens answers where the thread for a branch is, across hosts and repos, without hiding host identity.

## Requirements

- `S03-001` Selecting `Branch` MUST switch Dock into branch-grouped mode.
- `S03-002` The selected `Branch` control MUST be visually and accessibly distinct.
- `S03-003` Branch groups MUST be visible as compact section headers.
- `S03-004` Branch group headers MUST show branch name.
- `S03-005` Branch group headers MUST show visible session count when data is loaded.
- `S03-006` Branch group headers MUST show newest visible activity time when available.
- `S03-007` Branch group headers MUST show which hosts have visible rows for that branch.
- `S03-008` Branch groups MUST support expanded and collapsed states.
- `S03-009` Branch groups MUST sort by newest visible row.
- `S03-010` Rows inside each branch group MUST sort newest-first.
- `S03-011` The branch lens MUST preserve active search and filters.
- `S03-012` The screen MUST show active filter summary or chips, including host scope, status scope, idle visibility, and visible total when data is loaded.

## Row Requirements

- `S03-020` Rows MUST include host because branch grouping removes host from the section title.
- `S03-021` Rows MUST include repo or working directory when available.
- `S03-022` Rows MUST include title, status, and last activity time when available.
- `S03-023` Rows SHOULD include a short summary when loaded detail exists.
- `S03-024` Host chips or metadata MUST use short host display names.
- `S03-025` Rows MUST not rely on color or icon alone to communicate host.

## Branch Search And Lookup

- `S03-040` Branch search MUST support exact branch names such as `main`.
- `S03-041` Branch search MUST support partial branch fragments such as `dock`.
- `S03-042` Branch search MUST support slash branch names such as `feature/dock`.
- `S03-043` Branch search MUST support repo plus branch queries.
- `S03-044` Branch search MUST support host plus branch queries.
- `S03-045` Branch names MUST fit, wrap, or truncate gracefully without breaking controls.
- `S03-046` Popular or recent branch chips MAY be shown as shortcuts.

## Prohibited Content

- `S03-060` Branch mode MUST NOT be the default app-open state.
- `S03-061` Branch mode MUST NOT hide host identity in rows.
- `S03-062` Branch mode MUST NOT show `Needs me` as a primary category.
- `S03-063` Branch mode MUST NOT show `Limited`.
- `S03-064` Branch mode MUST NOT require free-text search as the only way to locate a branch.

## Acceptance Evidence

- A screenshot or accessibility dump shows `Branch` selected.
- Branch headers expose branch name, count, latest activity, host availability, and expanded or collapsed state.
- Rows under a branch include host display name.
- A branch search can find a known branch across both hosts.
- The visible primary text contains `Not loaded` where applicable and does not contain `Limited`.
